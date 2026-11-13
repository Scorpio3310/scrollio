//
//  PreferencesSidebarViewController.swift
//  Mos
//  The sidebar of the Preferences window: one row per pane (a coloured tile with a
//  symbol, then the pane's name), groups separated by a small gap, as in System Settings.
//

import Cocoa

protocol PreferencesSidebarDelegate: AnyObject {
    func sidebar(_ sidebar: PreferencesSidebarViewController, didSelect identifier: String)
}

final class PreferencesSidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {

    /// A row of the sidebar: a pane, or the gap between two groups.
    enum Row: Equatable {
        case pane(PreferencesPane, title: String)
        case gap
    }

    // MARK: - Layout

    static let rowHeight: CGFloat = 32
    static let gapHeight: CGFloat = 13
    static let tileSize: CGFloat = 20
    /// From the row's leading edge to the tile, and from the tile to the name.
    static let tileLeading: CGFloat = 3
    static let titleSpacing: CGFloat = 7

    // MARK: - State

    weak var delegate: PreferencesSidebarDelegate?
    let rows: [Row]
    private(set) var tableView: NSTableView!
    /// Set while the selection is changed in code, so the delegate hears only the user.
    private var isSelectingInCode = false

    init(panes: [PreferencesPane], titles: [String]) {
        var rows: [Row] = []
        for (pane, title) in zip(panes, titles) {
            if pane.startsGroup, !rows.isEmpty {
                rows.append(.gap)
            }
            rows.append(.pane(pane, title: title))
        }
        self.rows = rows
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("PreferencesSidebarViewController is built in code")
    }

    /// The pane identifier of each row, nil for a gap.
    var rowIdentifiers: [String?] {
        return rows.map { row in
            if case let .pane(pane, _) = row { return pane.identifier }
            return nil
        }
    }

    var selectedIdentifier: String? {
        let row = tableView?.selectedRow ?? -1
        return rowIdentifiers.indices.contains(row) ? rowIdentifiers[row] : nil
    }

    func row(for identifier: String) -> Int? {
        return rowIdentifiers.firstIndex(of: identifier)
    }

    // MARK: - Lifecycle

    override func loadView() {
        let table = NSTableView()
        table.style = .sourceList
        table.headerView = nil
        table.rowSizeStyle = .custom
        table.rowHeight = Self.rowHeight
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.allowsEmptySelection = false
        table.allowsMultipleSelection = false
        table.allowsColumnReordering = false
        table.allowsColumnResizing = false
        table.floatsGroupRows = false
        table.focusRingType = .none
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.setAccessibilityLabel(NSLocalizedString("preferences-sidebar", comment: ""))
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("pane"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.dataSource = self
        table.delegate = self
        tableView = table

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.horizontalScrollElasticity = .none
        scroll.borderType = .noBorder
        view = scroll
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // Arrow keys move through the panes as soon as the window opens.
        if let window = view.window, window.firstResponder === window || window.firstResponder == nil {
            window.makeFirstResponder(tableView)
        }
    }

    /// Selects the row of `identifier` without telling the delegate.
    func select(_ identifier: String) {
        _ = view
        guard let row = row(for: identifier), tableView.selectedRow != row else { return }
        isSelectingInCode = true
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        isSelectingInCode = false
        tableView.scrollRowToVisible(row)
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        return rows.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return rows[row] == .gap ? Self.gapHeight : Self.rowHeight
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard case let .pane(pane, title) = rows[row] else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("PreferencesSidebarCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? PreferencesSidebarCellView
            ?? PreferencesSidebarCellView(identifier: identifier)
        cell.configure(title: title, image: Self.tileImage(symbolName: pane.symbolName, color: pane.tileColor))
        return cell
    }

    /// Gaps are never selected. The arrow keys step over them; a click on one changes nothing.
    func tableView(_ tableView: NSTableView, selectionIndexesForProposedSelection proposedSelectionIndexes: IndexSet) -> IndexSet {
        let current = tableView.selectedRowIndexes
        guard let proposed = proposedSelectionIndexes.first, proposedSelectionIndexes.count == 1 else {
            return current.isEmpty ? proposedSelectionIndexes : current
        }
        if rowIdentifiers.indices.contains(proposed), rowIdentifiers[proposed] != nil {
            return proposedSelectionIndexes
        }
        if let type = NSApp.currentEvent?.type, [.leftMouseDown, .leftMouseUp, .leftMouseDragged].contains(type) {
            return current
        }
        let step = proposed >= (current.first ?? -1) ? 1 : -1
        var next = proposed + step
        while rowIdentifiers.indices.contains(next), rowIdentifiers[next] == nil {
            next += step
        }
        return rowIdentifiers.indices.contains(next) ? IndexSet(integer: next) : current
    }

    func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
        if case let .pane(_, title) = rows[row] { return title }
        return nil
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isSelectingInCode, let identifier = selectedIdentifier else { return }
        delegate?.sidebar(self, didSelect: identifier)
    }

    // MARK: - Tiles

    /// A rounded square in `color`, lighter at the top, with the symbol in white: the icons
    /// of System Settings. Drawn at whatever scale the screen asks for.
    ///
    /// The symbol is centred by what it draws, not by its image. An SF Symbol's image is the
    /// box that sets it in a line of text (symbols are sized and placed against the cap
    /// height of the system font), and the glyph is not in the middle of that box: in these
    /// symbols it stands up to 0.75 pt low and 0.5 pt left of it. Centred by the box, the
    /// glyphs stood visibly off the middle of their tiles; the tiles of System Settings have
    /// theirs in the middle (measured on a screenshot: within a quarter of a point).
    static func tileImage(symbolName: String, color: NSColor, size: CGFloat = tileSize) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: size * 0.62, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        let ink = symbol.flatMap { Self.inkBounds(of: $0) }
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let radius = rect.width * 0.225
            let tile = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
            let top = color.blended(withFraction: 0.18, of: .white) ?? color
            NSGradient(starting: top, ending: color)?.draw(in: tile, angle: -90)
            if let symbol {
                let natural = symbol.size
                let limit = rect.width * 0.76
                let scale = min(1, limit / max(natural.width, natural.height, 1))
                // The middle of the glyph, in the symbol's own points (its box's middle if
                // nothing could be measured), goes to the middle of the tile.
                let middle = ink.map { NSPoint(x: $0.midX, y: $0.midY) }
                    ?? NSPoint(x: natural.width / 2, y: natural.height / 2)
                symbol.draw(in: NSRect(
                    x: rect.midX - middle.x * scale,
                    y: rect.midY - middle.y * scale,
                    width: natural.width * scale,
                    height: natural.height * scale
                ))
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    /// Where `image` really draws, in its own points (origin bottom left): the box of the
    /// pixels it covers at least half, drawn at 8× (so to an eighth of a point). nil when it
    /// draws nothing.
    static func inkBounds(of image: NSImage, scale: CGFloat = 8) -> NSRect? {
        let size = image.size
        let width = Int((size.width * scale).rounded(.up)), height = Int((size.height * scale).rounded(.up))
        guard width > 0, height > 0,
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        context.scaleBy(x: scale, y: scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        // The bitmap's first row is the image's top row.
        var minColumn = width, maxColumn = -1, minRow = height, maxRow = -1
        for row in 0..<height {
            for column in 0..<width where data[(row * width + column) * 4 + 3] >= 128 {
                minColumn = min(minColumn, column); maxColumn = max(maxColumn, column)
                minRow = min(minRow, row); maxRow = max(maxRow, row)
            }
        }
        guard maxColumn >= 0 else { return nil }
        return NSRect(
            x: CGFloat(minColumn) / scale,
            y: CGFloat(height - 1 - maxRow) / scale,
            width: CGFloat(maxColumn - minColumn + 1) / scale,
            height: CGFloat(maxRow - minRow + 1) / scale
        )
    }
}

/// A sidebar row: the tile, then the pane's name. The name turns white on the selection.
final class PreferencesSidebarCellView: NSTableCellView {

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: NSRect(x: 0, y: 0, width: 180, height: PreferencesSidebarViewController.rowHeight))
        self.identifier = identifier

        let tile = NSImageView()
        tile.imageScaling = .scaleNone
        tile.translatesAutoresizingMaskIntoConstraints = false
        tile.setAccessibilityElement(false)

        let title = NSTextField(labelWithString: "")
        title.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        title.textColor = .labelColor
        title.lineBreakMode = .byTruncatingTail
        title.translatesAutoresizingMaskIntoConstraints = false
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addSubview(tile)
        addSubview(title)
        imageView = tile
        textField = title

        let size = PreferencesSidebarViewController.tileSize
        NSLayoutConstraint.activate([
            tile.leadingAnchor.constraint(equalTo: leadingAnchor, constant: PreferencesSidebarViewController.tileLeading),
            tile.centerYAnchor.constraint(equalTo: centerYAnchor),
            tile.widthAnchor.constraint(equalToConstant: size),
            tile.heightAnchor.constraint(equalToConstant: size),
            title.leadingAnchor.constraint(equalTo: tile.trailingAnchor, constant: PreferencesSidebarViewController.titleSpacing),
            title.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("PreferencesSidebarCellView is built in code")
    }

    func configure(title: String, image: NSImage) {
        textField?.stringValue = title
        imageView?.image = image
        setAccessibilityLabel(title)
    }
}
