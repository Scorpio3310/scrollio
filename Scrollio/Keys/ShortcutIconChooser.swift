//
//  ShortcutIconChooser.swift
//  Scrollio
//
//  The choice of an icon for a recorded key combination, in a popover of its own that
//  points at the icon well beside the name (as the small colour well of macOS opens its
//  picker): a search field on top, the symbols of `ShortcutIconSet` in a grid of groups
//  under it, and a footer with "Emoji & Symbols…" and "Remove Icon". When the search
//  holds one character that can be seen (typed, pasted, or put there by the system's
//  Emoji & Symbols viewer), that character is offered first: "Use “🔄”".
//
//  It has one size whatever it shows. The grid is cut through the middle of a row, so it
//  reads as a list that scrolls. Arrows move in the grid; Return, Space or a click
//  chooses; Esc closes the chooser and nothing else. It stores nothing: it tells
//  `onChoose` what was chosen (nil: no icon), and the editor keeps it with the name.
//

import Cocoa

/// The chooser's sizes, in points.
enum ShortcutIconChooserLayout {
    static let columns = 8
    static let cell: CGFloat = 32
    static let spacing: CGFloat = 4
    static let headerHeight: CGFloat = 24
    static let inset: CGFloat = 10
    /// The space under a group, before the next group's name.
    static let groupGap: CGFloat = 8
    /// Eight cells, seven gaps and the insets.
    static var width: CGFloat {
        return CGFloat(columns) * cell + CGFloat(columns - 1) * spacing + 2 * inset
    }
    /// The visible part of the grid: the first two groups (two rows each, under their
    /// names), the third group's name and half of its first row: the cut says "it scrolls".
    static var gridHeight: CGFloat {
        let group = headerHeight + 2 * cell + spacing + groupGap
        return 2 * group + headerHeight + cell / 2
    }
}

/// What the chooser offers for a search: one typed character first, then the groups of
/// symbols the search finds. Pure.
struct ShortcutIconChoices: Equatable {

    enum Entry: Equatable {
        /// "Use “🔄”": the one character of the search.
        case character(String)
        case symbol(ShortcutIconSet.Symbol)

        var icon: ShortcutLabel.Icon {
            switch self {
            case .character(let text):
                return .character(text)
            case .symbol(let symbol):
                return .symbol(symbol.name)
            }
        }
    }

    struct Section: Equatable {
        /// The group's name; nil for the typed character, which stands above the groups.
        let title: String?
        let entries: [Entry]
    }

    let sections: [Section]

    var isEmpty: Bool {
        return sections.isEmpty
    }

    var first: Entry? {
        return sections.first?.entries.first
    }

    func entry(at indexPath: IndexPath) -> Entry? {
        guard sections.indices.contains(indexPath.section),
              sections[indexPath.section].entries.indices.contains(indexPath.item) else { return nil }
        return sections[indexPath.section].entries[indexPath.item]
    }

    /// Where `icon` stands among the entries; nil: not there.
    func indexPath(of icon: ShortcutLabel.Icon?) -> IndexPath? {
        guard let icon else { return nil }
        for (section, group) in sections.enumerated() {
            if let item = group.entries.firstIndex(where: { $0.icon == icon }) {
                return IndexPath(item: item, section: section)
            }
        }
        return nil
    }

    /// What `query` finds. Empty: every group. One character that can be seen: that
    /// character first. A query with no letter or digit in it (an emoji, a sign) finds no
    /// symbol: the search matches words.
    static func matching(_ query: String) -> ShortcutIconChoices {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var sections: [Section] = []
        if trimmed.count == 1, case .character(let typed)? = ShortcutLabel.cleaned(.character(trimmed)) {
            sections.append(Section(title: nil, entries: [.character(typed)]))
        }
        let hasWords = trimmed.isEmpty || trimmed.contains { $0.isLetter || $0.isNumber }
        if hasWords {
            sections += ShortcutIconSet.groups(matching: trimmed).map { group in
                Section(title: group.title, entries: group.symbols.map { .symbol($0) })
            }
        }
        return ShortcutIconChoices(sections: sections)
    }
}

// MARK: - The grid's parts

/// A group's name over its symbols.
final class ShortcutIconChooserHeader: NSView, NSCollectionViewElement {

    static let identifier = NSUserInterfaceItemIdentifier("shortcut-icon-chooser-header")

    let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ShortcutIconChooserLayout.inset + 2),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -ShortcutIconChooserLayout.inset),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("ShortcutIconChooserHeader is built in code")
    }
}

/// One entry: a symbol in a square cell, or the typed character as a wide row
/// ("🔄  Use “🔄”"). The chosen (selected) one is a solid accent rounded square with the
/// symbol in white.
final class ShortcutIconChooserCell: NSView {

    private let imageView = NSImageView()
    private let title = NSTextField(labelWithString: "")
    var onPress: (() -> Void)?

    var entry: ShortcutIconChoices.Entry? {
        didSet { fill() }
    }

    var isSelected = false {
        didSet {
            guard isSelected != oldValue else { return }
            colour()
            needsDisplay = true
            setAccessibilitySelected(isSelected)
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageView.imageScaling = .scaleNone
        imageView.translatesAutoresizingMaskIntoConstraints = false
        title.translatesAutoresizingMaskIntoConstraints = false
        title.lineBreakMode = .byTruncatingTail
        addSubview(imageView)
        addSubview(title)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) {
        fatalError("ShortcutIconChooserCell is built in code")
    }

    private var layout: [NSLayoutConstraint] = []

    private func fill() {
        NSLayoutConstraint.deactivate(layout)
        switch entry {
        case .symbol(let symbol)?:
            imageView.image = NSImage(systemSymbolName: symbol.name, accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .regular))
            title.isHidden = true
            layout = [
                imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
                imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            ]
            toolTip = symbol.spokenName
            setAccessibilityLabel(symbol.spokenName)
        case .character(let text)?:
            imageView.image = ShortcutIconSet.image(of: .character(text), side: 22)
            let use = String(format: NSLocalizedString("key-recorder-icon-use-character", comment: ""), text)
            title.stringValue = use
            title.isHidden = false
            layout = [
                imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
                imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 22),
                title.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8),
                title.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
                title.centerYAnchor.constraint(equalTo: centerYAnchor),
            ]
            toolTip = nil
            setAccessibilityLabel(use)
        case nil:
            imageView.image = nil
            title.isHidden = true
        }
        NSLayoutConstraint.activate(layout)
        colour()
    }

    private func colour() {
        let ink: NSColor = isSelected ? .white : .labelColor
        imageView.contentTintColor = ink
        title.textColor = ink
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isSelected else { return }
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
    }

    override func accessibilityPerformPress() -> Bool {
        onPress?()
        return onPress != nil
    }
}

final class ShortcutIconChooserItem: NSCollectionViewItem {

    static let identifier = NSUserInterfaceItemIdentifier("shortcut-icon-chooser-item")

    var cell: ShortcutIconChooserCell {
        return view as! ShortcutIconChooserCell
    }

    override func loadView() {
        view = ShortcutIconChooserCell(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
    }

    override var isSelected: Bool {
        didSet { cell.isSelected = isSelected }
    }
}

/// The grid: a click on an entry chooses it, Return or Space chooses the selected one, Esc
/// closes, and the up arrow on the first row goes back to the search field.
final class ShortcutIconChooserGrid: NSCollectionView {

    var onChooseAt: ((IndexPath) -> Void)?
    var onCancel: (() -> Void)?
    var onLeaveTop: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        let point = convert(event.locationInWindow, from: nil)
        if let indexPath = indexPathForItem(at: point) {
            onChooseAt?(indexPath)
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76, 49: // Return, Enter, Space
            if let indexPath = selectionIndexPaths.first {
                onChooseAt?(indexPath)
            }
        case 53: // Esc
            onCancel?()
        case 126 where isOnTheFirstRow(selectionIndexPaths.first):
            onLeaveTop?()
        default:
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    private func isOnTheFirstRow(_ indexPath: IndexPath?) -> Bool {
        guard let indexPath, let frame = collectionViewLayout?.layoutAttributesForItem(at: indexPath)?.frame,
              let top = collectionViewLayout?.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))?.frame else {
            return indexPath == nil
        }
        return abs(frame.minY - top.minY) < 1
    }
}

// MARK: - The chooser

final class ShortcutIconChooserController: NSViewController, NSCollectionViewDataSource,
    NSCollectionViewDelegateFlowLayout, NSSearchFieldDelegate {

    enum Identifier {
        static let search = NSUserInterfaceItemIdentifier("shortcut-label-icon-search")
        static let grid = NSUserInterfaceItemIdentifier("shortcut-label-icon-grid")
        static let noMatch = NSUserInterfaceItemIdentifier("shortcut-label-icon-no-match")
        static let emoji = NSUserInterfaceItemIdentifier("shortcut-label-icon-emoji")
        static let removeIcon = NSUserInterfaceItemIdentifier("shortcut-label-icon-remove")
    }

    /// The icon when the chooser opened; nil: none.
    let icon: ShortcutLabel.Icon?
    /// What was chosen: an icon, or nil for "Remove Icon".
    var onChoose: ((ShortcutLabel.Icon?) -> Void)?
    /// Esc: the chooser closes, nothing changes.
    var onCancel: (() -> Void)?
    /// Opens the system's Emoji & Symbols viewer. Does nothing under XCTest.
    var openCharacterPalette: () -> Void = ShortcutIconChooserController.systemCharacterPalette

    let searchField = NSSearchField()
    let grid = ShortcutIconChooserGrid()
    let scrollView = NSScrollView()
    let noMatchView = NSStackView()
    let emojiButton = NSButton(title: "", target: nil, action: nil)
    let removeButton = NSButton(title: "", target: nil, action: nil)

    private(set) var choices = ShortcutIconChoices.matching("")
    /// Something is typed in the search.
    private var isSearching = false
    private var scrollsToSelectionOnLayout = true

    init(icon: ShortcutLabel.Icon?) {
        self.icon = icon
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("ShortcutIconChooserController is built in code")
    }

    private static func systemCharacterPalette() {
        guard !AppRuntime.isRunningXCTest else { return }
        NSApp.orderFrontCharacterPalette(nil)
    }

    private static func text(_ key: String) -> String {
        return NSLocalizedString(key, comment: "")
    }

    // MARK: Showing

    /// The search field takes the keyboard. (The popover's window is made the key window:
    /// the parent popover's window had it.)
    func focusSearch() {
        guard let window = view.window else { return }
        window.makeFirstResponder(searchField)
        if !window.isKeyWindow, window.canBecomeKey {
            window.makeKey()
        }
    }

    /// Shows what `query` finds, the first entry selected when something was typed, the
    /// icon of the moment when nothing was.
    func search(_ query: String) {
        choices = ShortcutIconChoices.matching(query)
        grid.reloadData()
        let found = !choices.isEmpty
        scrollView.isHidden = !found
        noMatchView.isHidden = found
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        isSearching = !trimmed.isEmpty
        let selected = trimmed.isEmpty ? choices.indexPath(of: icon) : (found ? IndexPath(item: 0, section: 0) : nil)
        grid.selectionIndexPaths = selected.map { [$0] } ?? []
        if trimmed.isEmpty, selected != nil {
            scrollsToSelectionOnLayout = true
            view.needsLayout = true
        } else {
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    /// The selected entry is chosen; with none, the first one that was found (Return in
    /// the search field). With nothing typed and nothing selected (the icon is a typed
    /// character, a symbol that is not among these, or none) nothing was chosen: the
    /// chooser closes as for Esc, and the icon stays.
    func chooseSelected() {
        if let indexPath = grid.selectionIndexPaths.first {
            choose(at: indexPath)
        } else if !isSearching {
            onCancel?()
        } else if !choices.isEmpty {
            choose(at: IndexPath(item: 0, section: 0))
        }
    }

    func choose(at indexPath: IndexPath) {
        guard let entry = choices.entry(at: indexPath) else { return }
        onChoose?(entry.icon)
    }

    // MARK: Actions

    @objc private func removeIcon(_ sender: Any?) {
        onChoose?(nil)
    }

    @objc private func showCharacterPalette(_ sender: Any?) {
        // (The viewer types into the field that has the keyboard: the search field.)
        view.window?.makeFirstResponder(searchField)
        openCharacterPalette()
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    func controlTextDidChange(_ notification: Notification) {
        guard notification.object as? NSSearchField === searchField else { return }
        search(searchField.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === searchField else { return false }
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            chooseSelected()
            return true
        case #selector(NSResponder.moveDown(_:)):
            guard !choices.isEmpty else { return true }
            if grid.selectionIndexPaths.isEmpty {
                grid.selectionIndexPaths = [IndexPath(item: 0, section: 0)]
            }
            view.window?.makeFirstResponder(grid)
            if let selected = grid.selectionIndexPaths.first {
                grid.scrollToItems(at: [selected], scrollPosition: .nearestHorizontalEdge)
            }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onCancel?()
            return true
        default:
            return false
        }
    }

    // MARK: The grid's data

    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        return choices.sections.count
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return choices.sections[section].entries.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: ShortcutIconChooserItem.identifier, for: indexPath)
        if let item = item as? ShortcutIconChooserItem {
            item.cell.entry = choices.entry(at: indexPath)
            item.cell.isSelected = collectionView.selectionIndexPaths.contains(indexPath)
            item.cell.onPress = { [weak self] in self?.choose(at: indexPath) }
        }
        return item
    }

    func collectionView(_ collectionView: NSCollectionView, viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind,
                        at indexPath: IndexPath) -> NSView {
        let header = collectionView.makeSupplementaryView(ofKind: kind, withIdentifier: ShortcutIconChooserHeader.identifier, for: indexPath)
        (header as? ShortcutIconChooserHeader)?.label.stringValue = choices.sections[indexPath.section].title ?? ""
        return header
    }

    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> NSSize {
        let side = ShortcutIconChooserLayout.cell
        if case .character? = choices.entry(at: indexPath) {
            return NSSize(width: ShortcutIconChooserLayout.width - 2 * ShortcutIconChooserLayout.inset, height: side)
        }
        return NSSize(width: side, height: side)
    }

    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout,
                        referenceSizeForHeaderInSection section: Int) -> NSSize {
        let titled = choices.sections[section].title != nil
        return NSSize(width: 0, height: titled ? ShortcutIconChooserLayout.headerHeight : 6)
    }

    // MARK: Building

    override func loadView() {
        let layout = ShortcutIconChooserLayout.self
        let root = NSView(frame: NSRect(x: 0, y: 0, width: layout.width, height: 300))
        root.setAccessibilityElement(true)
        root.setAccessibilityRole(.group)
        root.setAccessibilityLabel(Self.text("key-recorder-icon"))

        searchField.placeholderString = Self.text("key-recorder-icon-search")
        searchField.delegate = self
        searchField.identifier = Identifier.search
        searchField.sendsSearchStringImmediately = true
        searchField.translatesAutoresizingMaskIntoConstraints = false

        let flow = NSCollectionViewFlowLayout()
        flow.itemSize = NSSize(width: layout.cell, height: layout.cell)
        flow.minimumInteritemSpacing = layout.spacing
        flow.minimumLineSpacing = layout.spacing
        flow.sectionInset = NSEdgeInsets(top: 0, left: layout.inset, bottom: layout.groupGap, right: layout.inset)
        flow.headerReferenceSize = NSSize(width: 0, height: layout.headerHeight)
        grid.collectionViewLayout = flow
        grid.register(ShortcutIconChooserItem.self, forItemWithIdentifier: ShortcutIconChooserItem.identifier)
        grid.register(ShortcutIconChooserHeader.self, forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
                      withIdentifier: ShortcutIconChooserHeader.identifier)
        grid.dataSource = self
        grid.delegate = self
        grid.isSelectable = true
        grid.allowsMultipleSelection = false
        grid.allowsEmptySelection = true
        grid.backgroundColors = [.clear]
        grid.identifier = Identifier.grid
        grid.setAccessibilityLabel(Self.text("key-recorder-icon"))
        grid.onChooseAt = { [weak self] indexPath in self?.choose(at: indexPath) }
        grid.onCancel = { [weak self] in self?.onCancel?() }
        grid.onLeaveTop = { [weak self] in
            guard let self else { return }
            self.view.window?.makeFirstResponder(self.searchField)
        }

        scrollView.documentView = grid
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        // (Over the grid, never beside it: a scroll bar beside it would take a column.)
        scrollView.scrollerStyle = .overlay
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let magnifier = NSImageView(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 28, weight: .light)) ?? NSImage())
        magnifier.contentTintColor = .tertiaryLabelColor
        let noMatch = NSTextField(labelWithString: Self.text("key-recorder-icon-no-match"))
        noMatch.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        noMatch.textColor = .secondaryLabelColor
        let noMatchHint = NSTextField(wrappingLabelWithString: Self.text("key-recorder-icon-no-match-hint"))
        noMatchHint.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        noMatchHint.textColor = .secondaryLabelColor
        noMatchHint.alignment = .center
        noMatchHint.preferredMaxLayoutWidth = layout.width - 4 * layout.inset
        noMatchView.orientation = .vertical
        noMatchView.alignment = .centerX
        noMatchView.spacing = 6
        noMatchView.setViews([magnifier, noMatch, noMatchHint], in: .center)
        noMatchView.setCustomSpacing(10, after: magnifier)
        noMatchView.identifier = Identifier.noMatch
        noMatchView.isHidden = true
        noMatchView.translatesAutoresizingMaskIntoConstraints = false

        emojiButton.title = Self.text("key-recorder-icon-emoji")
        emojiButton.bezelStyle = .push
        emojiButton.controlSize = .small
        emojiButton.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        emojiButton.target = self
        emojiButton.action = #selector(showCharacterPalette(_:))
        emojiButton.identifier = Identifier.emoji
        emojiButton.translatesAutoresizingMaskIntoConstraints = false

        removeButton.title = Self.text("key-recorder-icon-remove")
        removeButton.isBordered = false
        removeButton.controlSize = .small
        removeButton.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        removeButton.contentTintColor = .controlAccentColor
        removeButton.target = self
        removeButton.action = #selector(removeIcon(_:))
        removeButton.identifier = Identifier.removeIcon
        // Hidden, not off, when there is nothing to remove.
        removeButton.isHidden = icon == nil
        removeButton.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        for view in [searchField, scrollView, noMatchView, separator, emojiButton, removeButton] as [NSView] {
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: layout.width),
            searchField.topAnchor.constraint(equalTo: root.topAnchor, constant: layout.inset),
            searchField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: layout.inset),
            searchField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -layout.inset),
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: layout.gridHeight),
            noMatchView.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            noMatchView.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            noMatchView.widthAnchor.constraint(lessThanOrEqualTo: scrollView.widthAnchor, constant: -4 * layout.inset),
            separator.topAnchor.constraint(equalTo: scrollView.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            emojiButton.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 8),
            emojiButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: layout.inset),
            emojiButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -layout.inset),
            removeButton.centerYAnchor.constraint(equalTo: emojiButton.centerYAnchor),
            removeButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -layout.inset),
        ])
        // Tab: the search, the grid, the footer's buttons.
        searchField.nextKeyView = grid
        grid.nextKeyView = emojiButton
        emojiButton.nextKeyView = removeButton
        removeButton.nextKeyView = searchField
        view = root
        search("")
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // The grid as tall as its content. (The collection view does it by itself in a
        // window; before it is in one, a scroll to the selection has no room otherwise.)
        if let content = grid.collectionViewLayout?.collectionViewContentSize {
            let size = NSSize(width: scrollView.contentSize.width, height: max(content.height, scrollView.contentSize.height))
            if grid.frame.size != size {
                grid.setFrameSize(size)
            }
        }
        guard scrollsToSelectionOnLayout else { return }
        scrollsToSelectionOnLayout = false
        // The icon of the moment in the middle of the view, before the grid makes the items
        // it shows.
        guard let selected = grid.selectionIndexPaths.first,
              let frame = grid.collectionViewLayout?.layoutAttributesForItem(at: selected)?.frame else { return }
        let clip = scrollView.contentView
        let top = min(max(0, frame.midY - clip.bounds.height / 2), max(0, grid.frame.height - clip.bounds.height))
        clip.scroll(to: NSPoint(x: 0, y: top))
        scrollView.reflectScrolledClipView(clip)
        grid.needsLayout = true
    }
}
