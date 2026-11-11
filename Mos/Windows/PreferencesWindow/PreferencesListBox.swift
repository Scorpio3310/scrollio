//
//  PreferencesListBox.swift
//  Mos
//  A list in the grouped kit (PreferencesGroupedForm), as System Settings › General ›
//  Login Items shows one: a box of selectable rows with a bar under them, + and − on the
//  left and an optional view on the right. One row is selected at a time, the box is as
//  tall as its rows (the pane scrolls, never the list), and the pane that owns the list
//  keeps the data: the list only reports what the user asked for (add, remove, open) and
//  shows the rows it is given.
//
//  The pieces:
//  - PreferencesListBox: the box, its selection, the keyboard, the footer and the callbacks.
//  - PreferencesListRow: a PreferencesGroupRow with an id, an optional icon before its
//    texts and an optional chevron after its control (a row that opens a page of its own).
//  - PreferencesListEmptyRow: what a list without rows shows.
//  - PreferencesListGroupTitle: a small title inside the box above a group of its rows.
//  - PreferencesListSection: a list with a small title above it.
//

import Cocoa

// MARK: - List

final class PreferencesListBox: NSView {

    // MARK: Metrics

    /// The bar under the rows that holds + and −.
    static let footerHeight: CGFloat = 28
    static let footerButtonSize = NSSize(width: 24, height: 22)
    /// Between the box's left edge and the + button.
    static let footerButtonInset: CGFloat = 4
    /// The hairline between + and −.
    static let footerDividerHeight: CGFloat = 14
    /// Between the room of the right-hand view and the − button.
    static let footerAccessorySpacing: CGFloat = 8
    /// The selection is inset this much inside its row, its corners follow the box's.
    static let selectionInset: CGFloat = 4
    static let selectionCornerRadius: CGFloat = PreferencesGroupedForm.boxCornerRadius - selectionInset
    /// Above and below the texts of the empty row.
    static let emptyRowVerticalInset: CGFloat = 16

    // MARK: Colours

    /// The selection of the list the user works in (the key window): the accent colour.
    static let selectionColor = PreferencesGroupedForm.plain(name: "PreferencesListSelection") {
        .selectedContentBackgroundColor
    }

    /// The selection while the window is not key: a grey.
    static let unemphasizedSelectionColor = PreferencesGroupedForm.plain(name: "PreferencesListSelectionUnemphasized") {
        .unemphasizedSelectedContentBackgroundColor
    }

    // MARK: Callbacks

    /// + was clicked; the button, to anchor a menu or a popover on.
    var onAdd: ((NSButton) -> Void)?
    /// − was clicked, or Delete pressed, with this row selected (only a row that
    /// `isRemovable`). The owner removes it and calls `setRows`.
    var onRemove: ((AnyHashable) -> Void)?
    /// A row was double-clicked, or Return pressed while it is selected.
    var onOpen: ((AnyHashable) -> Void)?
    /// The pointer moved onto a row, or off the rows (nil). The empty row counts as none.
    var onHover: ((AnyHashable?) -> Void)?
    /// The selection changed, however it changed: a click, a key, `select`, or `setRows`
    /// dropping the selected row.
    var onSelect: ((AnyHashable?) -> Void)?

    // MARK: Views

    let width: CGFloat
    /// The rows, top to bottom (`setRows`).
    private(set) var rows: [PreferencesListRow] = []
    /// The titles inside the box, by the id of the row each stands above (`setRows`).
    private(set) var groupTitles: [AnyHashable: PreferencesListGroupTitle] = [:]
    /// The accessibility list: the rows, or the empty row.
    let rowsView = PreferencesListRowsView()
    let emptyRow: PreferencesListEmptyRow
    let footerView = NSView()
    let addButton: NSButton
    let removeButton: NSButton

    /// A view at the right end of the footer ("Checking buttons…"), or none.
    var footerAccessory: NSView? {
        didSet {
            guard footerAccessory !== oldValue else { return }
            oldValue?.removeFromSuperview()
            installFooterAccessory()
        }
    }

    // MARK: State

    private(set) var selectedID: AnyHashable?
    private(set) var hoveredID: AnyHashable?
    /// The selection draws in the accent colour (the window is key), not in grey.
    private(set) var isSelectionEmphasized = false
    /// Off for a moment while the selection blinks (`flash`).
    private var isFlashedOff = false
    private var flashGeneration = 0
    private var hoverNeedsRefresh = false
    private var trackingArea: NSTrackingArea?
    private var windowObservers: [NSObjectProtocol] = []

    /// - Parameters:
    ///   - width: as wide as the boxes of the pane (`PreferencesGroupedForm.boxWidth`).
    ///   - emptyTitle, emptyExplanation: what the list shows while it has no rows.
    init(width: CGFloat, rows: [PreferencesListRow] = [], emptyTitle: String, emptyExplanation: String? = nil) {
        self.width = width
        emptyRow = PreferencesListEmptyRow(title: emptyTitle, explanation: emptyExplanation, width: width)
        addButton = Self.makeFooterButton(symbol: "plus", label: NSLocalizedString("list-add", comment: "Accessibility label of the + button under a list"))
        removeButton = Self.makeFooterButton(symbol: "minus", label: NSLocalizedString("list-remove", comment: "Accessibility label of the − button under a list"))
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 0))
        translatesAutoresizingMaskIntoConstraints = false
        focusRingType = .default

        rowsView.list = self
        rowsView.orientation = .vertical
        rowsView.alignment = .leading
        rowsView.spacing = 0
        rowsView.detachesHiddenViews = true
        rowsView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rowsView)

        footerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(footerView)
        addButton.target = self
        addButton.action = #selector(addClicked(_:))
        removeButton.target = self
        removeButton.action = #selector(removeClicked(_:))
        footerView.addSubview(addButton)
        footerView.addSubview(removeButton)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: width),
            rowsView.topAnchor.constraint(equalTo: topAnchor),
            rowsView.leadingAnchor.constraint(equalTo: leadingAnchor),
            rowsView.trailingAnchor.constraint(equalTo: trailingAnchor),
            footerView.topAnchor.constraint(equalTo: rowsView.bottomAnchor),
            footerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            footerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            footerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            footerView.heightAnchor.constraint(equalToConstant: Self.footerHeight),
            addButton.leadingAnchor.constraint(equalTo: footerView.leadingAnchor, constant: Self.footerButtonInset),
            addButton.centerYAnchor.constraint(equalTo: footerView.centerYAnchor),
            // One point between the two for the hairline.
            removeButton.leadingAnchor.constraint(equalTo: addButton.trailingAnchor, constant: 1),
            removeButton.centerYAnchor.constraint(equalTo: footerView.centerYAnchor),
        ])
        setRows(rows)
    }

    required init?(coder: NSCoder) {
        fatalError("PreferencesListBox is built in code")
    }

    deinit {
        removeWindowObservers()
    }

    override var isFlipped: Bool { return true }

    private static func makeFooterButton(symbol: String, label: String) -> NSButton {
        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?.withSymbolConfiguration(configuration)
        let button = PreferencesListFooterButton(frame: NSRect(origin: .zero, size: footerButtonSize))
        button.setButtonType(.momentaryChange)
        button.isBordered = false
        button.title = ""
        button.image = image
        button.imagePosition = .imageOnly
        button.setAccessibilityLabel(label)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: footerButtonSize.width),
            button.heightAnchor.constraint(equalToConstant: footerButtonSize.height),
        ])
        return button
    }

    private func installFooterAccessory() {
        guard let footerAccessory else { return }
        footerAccessory.translatesAutoresizingMaskIntoConstraints = false
        footerView.addSubview(footerAccessory)
        NSLayoutConstraint.activate([
            footerAccessory.trailingAnchor.constraint(equalTo: footerView.trailingAnchor, constant: -PreferencesGroupedForm.rowHorizontalInset),
            footerAccessory.centerYAnchor.constraint(equalTo: footerView.centerYAnchor),
            footerAccessory.leadingAnchor.constraint(greaterThanOrEqualTo: removeButton.trailingAnchor, constant: Self.footerAccessorySpacing),
            footerAccessory.topAnchor.constraint(greaterThanOrEqualTo: footerView.topAnchor),
            footerAccessory.bottomAnchor.constraint(lessThanOrEqualTo: footerView.bottomAnchor),
        ])
    }

    // MARK: - Rows

    /// The rows that show, top to bottom.
    var visibleRows: [PreferencesListRow] {
        return rows.filter { !$0.isHidden }
    }

    var selectedRow: PreferencesListRow? {
        return selectedID.flatMap(row(withID:))
    }

    func row(withID id: AnyHashable) -> PreferencesListRow? {
        return rows.first { $0.id == id }
    }

    /// Shows `newRows` (ids unique). The selected row stays selected when a row with its id
    /// is among them; otherwise nothing is selected and `onSelect(nil)` is called. Without
    /// rows the list shows its empty row.
    /// - Parameter groupTitles: a small title inside the box above the row with that id
    ///   ("Other buttons and keys"), for the rows from there on; not above the first row.
    func setRows(_ newRows: [PreferencesListRow], groupTitles titles: [AnyHashable: String] = [:]) {
        for view in rowsView.arrangedSubviews {
            rowsView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for row in rows where !newRows.contains(where: { $0 === row }) {
            row.list = nil
        }
        rows = newRows
        var kept: [AnyHashable: PreferencesListGroupTitle] = [:]
        for row in newRows.dropFirst() {
            guard let title = titles[row.id] else { continue }
            let view = groupTitles[row.id] ?? PreferencesListGroupTitle(title: title)
            view.title = title
            kept[row.id] = view
        }
        groupTitles = kept
        var shown: [NSView] = []
        for row in newRows {
            if let title = kept[row.id] {
                shown.append(title)
            }
            shown.append(row)
        }
        if shown.isEmpty {
            shown = [emptyRow]
        }
        for view in shown {
            rowsView.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: rowsView.widthAnchor).isActive = true
        }
        for row in newRows {
            row.list = self
            row.contentWidth = width
        }

        let previous = selectedID
        if let previous, row(withID: previous) == nil {
            cancelFlash()
            selectedID = nil
        }
        applySelection()
        if selectedID != previous {
            selectionDidChange()
        }
        // Another row may now be under the pointer: look once the rows are laid out.
        hoverNeedsRefresh = true
        needsLayout = true
        needsDisplay = true
    }

    // MARK: - Selection

    /// Selects the row with `id`, or nothing (nil). An id that is not in the list selects
    /// nothing. Calls `onSelect` when the selection changes and scrolls the pane to the row.
    func select(_ id: AnyHashable?) {
        let wanted = id.flatMap { row(withID: $0)?.id }
        guard wanted != selectedID else { return }
        cancelFlash()
        selectedID = wanted
        applySelection()
        selectionDidChange()
        scrollSelectionToVisible()
    }

    /// Selects the row with `id` and blinks its selection twice ("this one is already
    /// there"). Only selects under Reduce Motion.
    func flash(_ id: AnyHashable) {
        select(id)
        guard selectedID == id, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        flashGeneration += 1
        let generation = flashGeneration
        for step in 1...4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12 * Double(step)) { [weak self] in
                guard let self, self.flashGeneration == generation else { return }
                self.isFlashedOff = step % 2 == 1
                self.applySelection()
            }
        }
    }

    /// Stops a blink in progress; the selection shows again.
    private func cancelFlash() {
        isFlashedOff = false
        flashGeneration += 1
    }

    private func selectionDidChange() {
        NSAccessibility.post(element: rowsView, notification: .selectedRowsChanged)
        onSelect?(selectedID)
    }

    /// Puts the selection and its emphasis into the rows, the − button and the drawing.
    fileprivate func applySelection() {
        removeButton.isEnabled = selectedRow?.isRemovable ?? false
        for row in rows {
            row.setSelection(selected: row.id == selectedID && !isFlashedOff, emphasized: isSelectionEmphasized)
        }
        needsDisplay = true
    }

    private func scrollSelectionToVisible() {
        guard let row = selectedRow else { return }
        // A row that was just added has no frame before the next layout.
        DispatchQueue.main.async { [weak row] in
            guard let row, row.window != nil else { return }
            row.scrollToVisible(row.bounds)
        }
    }

    /// The selection is emphasized while the window is key.
    func updateEmphasis() {
        let emphasized = window?.isKeyWindow ?? false
        guard emphasized != isSelectionEmphasized else { return }
        isSelectionEmphasized = emphasized
        applySelection()
    }

    override func viewWillDraw() {
        updateEmphasis()
        super.viewWillDraw()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        removeWindowObservers()
    }

    private func removeWindowObservers() {
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        windowObservers = []
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            let names = [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification]
            windowObservers = names.map { name in
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.updateEmphasis()
                }
            }
        }
        updateEmphasis()
    }

    // MARK: - Mouse

    /// A click on a row's background (not on one of its controls): selects it, and a
    /// double click opens it.
    fileprivate func rowWasClicked(_ row: PreferencesListRow, clickCount: Int) {
        window?.makeFirstResponder(self)
        select(row.id)
        if clickCount == 2, selectedID == row.id {
            onOpen?(row.id)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard trackingArea == nil else { return }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        setHovered(rowID(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseMoved(with event: NSEvent) {
        setHovered(rowID(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) {
        setHovered(nil)
    }

    /// The id of the row under `point` (the box's coordinates), nil over the footer or the
    /// empty row.
    func rowID(at point: NSPoint) -> AnyHashable? {
        return visibleRows.first { convert($0.bounds, from: $0).contains(point) }?.id
    }

    private func setHovered(_ id: AnyHashable?) {
        guard id != hoveredID else { return }
        hoveredID = id
        onHover?(id)
    }

    override func layout() {
        super.layout()
        // The hairlines and the selection move with the rows.
        needsDisplay = true
        noteFocusRingMaskChanged()
        if hoverNeedsRefresh {
            hoverNeedsRefresh = false
            DispatchQueue.main.async { [weak self] in self?.refreshHoverFromPointer() }
        }
    }

    private func refreshHoverFromPointer() {
        guard let window else { return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        setHovered(bounds.contains(point) ? rowID(at: point) : nil)
    }

    // MARK: - Keyboard

    override var acceptsFirstResponder: Bool { return true }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        if !handleKey(event) {
            super.keyDown(with: event)
        }
    }

    /// ↑ and ↓ move the selection (from nothing: the last or the first row), Delete and
    /// Forward Delete remove the selected row, Return and Enter open it. Delete only while
    /// the list itself has the keyboard: pressed in a control of a row (its pull-down) it
    /// reaches the list too, and is passed on.
    private func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch event.specialKey {
        case .upArrow?, .downArrow?:
            guard modifiers.isEmpty else { return false }
            moveSelection(by: event.specialKey == .upArrow ? -1 : 1)
            return true
        case .delete?, .deleteForward?, .backspace?:
            guard modifiers.subtracting(.command).isEmpty, window?.firstResponder === self else { return false }
            // With nothing selected, or a row that cannot be removed, the key does nothing
            // (and does not beep).
            if let selectedID, selectedRow?.isRemovable == true {
                onRemove?(selectedID)
            }
            return true
        case .carriageReturn?, .enter?, .newline?:
            guard modifiers.isEmpty, let selectedID else { return false }
            onOpen?(selectedID)
            return true
        default:
            return false
        }
    }

    private func moveSelection(by delta: Int) {
        let visible = visibleRows
        guard !visible.isEmpty else { return }
        let index: Int
        if let current = selectedID, let position = visible.firstIndex(where: { $0.id == current }) {
            index = min(visible.count - 1, max(0, position + delta))
        } else {
            index = delta > 0 ? 0 : visible.count - 1
        }
        select(visible[index].id)
    }

    // MARK: - Footer

    @objc private func addClicked(_ sender: NSButton) {
        onAdd?(sender)
    }

    @objc private func removeClicked(_ sender: NSButton) {
        guard let selectedID, selectedRow?.isRemovable == true else { return }
        onRemove?(selectedID)
    }

    // MARK: - Drawing

    private var hairlineThickness: CGFloat {
        return 1 / max(1, window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
    }

    /// The selection, in the box's (flipped) coordinates; nil while nothing is selected.
    var selectionRect: NSRect? {
        guard let row = selectedRow, !row.isHidden, !isFlashedOff else { return nil }
        let inset = Self.selectionInset
        return convert(row.bounds, from: row).insetBy(dx: inset, dy: inset)
    }

    /// The hairlines between the rows: on top of every row that shows except the first,
    /// inset like the rows' content, and none next to the selection. Above a group title
    /// the hairline is on top of the title, and none is between the title and its row.
    var separatorRects: [NSRect] {
        let inset = PreferencesGroupedForm.rowHorizontalInset
        let thickness = hairlineThickness
        let visible = visibleRows
        let selected = selectionRect == nil ? nil : visible.firstIndex { $0.id == selectedID }
        return visible.indices.dropFirst().compactMap { index in
            let row = visible[index]
            if let title = groupTitles[row.id], title.superview != nil {
                if let selected, index == selected + 1 {
                    return nil
                }
                let top = convert(title.bounds, from: title).minY
                return NSRect(x: inset, y: top, width: bounds.width - 2 * inset, height: thickness)
            }
            if let selected, index == selected || index == selected + 1 {
                return nil
            }
            let top = convert(row.bounds, from: row).minY
            return NSRect(x: inset, y: top, width: bounds.width - 2 * inset, height: thickness)
        }
    }

    /// The hairline between the rows and the footer, across the whole box.
    var footerSeparatorRect: NSRect {
        let top = convert(footerView.bounds, from: footerView).minY
        return NSRect(x: 0, y: top, width: bounds.width, height: hairlineThickness)
    }

    /// The short upright hairline between + and −.
    var footerDividerRect: NSRect {
        let footer = convert(footerView.bounds, from: footerView)
        let add = convert(addButton.bounds, from: addButton)
        let height = Self.footerDividerHeight
        return NSRect(x: add.maxX, y: footer.midY - height / 2, width: hairlineThickness, height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = PreferencesGroupedForm.boxCornerRadius
        PreferencesGroupedForm.boxFillColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        if let selection = selectionRect {
            (isSelectionEmphasized ? Self.selectionColor : Self.unemphasizedSelectionColor).setFill()
            let corner = Self.selectionCornerRadius
            NSBezierPath(roundedRect: selection, xRadius: corner, yRadius: corner).fill()
        }
        PreferencesGroupedForm.hairlineColor.setFill()
        for rect in separatorRects + [footerSeparatorRect, footerDividerRect] {
            rect.fill()
        }
        if drawsOutline {
            PreferencesGroupedForm.drawOutline(of: bounds)
        }
    }

    /// Under Increase Contrast the box has an outline, as the kit's other boxes.
    var drawsOutline: Bool {
        return PreferencesGroupedForm.isHighContrast(effectiveAppearance)
    }

    /// The focus ring goes round the box, and only where focus rings show for every control
    /// (Full Keyboard Access): a click on a row selects it without ringing the whole list.
    override var focusRingMaskBounds: NSRect {
        return bounds
    }

    override func drawFocusRingMask() {
        guard NSApp.isFullKeyboardAccessEnabled else { return }
        let radius = PreferencesGroupedForm.boxCornerRadius
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
    }
}

/// The + and − of a list: 24 × 22 pt is the button, whatever the symbol's own alignment
/// insets (they would make − a few points shorter than +).
final class PreferencesListFooterButton: NSButton {
    override var alignmentRectInsets: NSEdgeInsets {
        return NSEdgeInsetsZero
    }
}

/// A list row's icon or chevron: its frame is the size it is given (a symbol's alignment
/// insets would move it off the middle).
final class PreferencesListImageView: NSImageView {
    override var alignmentRectInsets: NSEdgeInsets {
        return NSEdgeInsetsZero
    }
}

// MARK: - Accessibility list

/// The rows of a PreferencesListBox, as an accessibility list: its rows are the rows of
/// the list (or the empty row), and VoiceOver can read and change the selection.
final class PreferencesListRowsView: NSStackView {

    fileprivate(set) weak var list: PreferencesListBox?

    override func isAccessibilityElement() -> Bool {
        return true
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        return .list
    }

    override func accessibilityOrientation() -> NSAccessibilityOrientation {
        return .vertical
    }

    /// The rows, with the group titles between them.
    override func accessibilityChildren() -> [Any]? {
        guard let list else { return [] }
        guard !list.rows.isEmpty else { return [list.emptyRow] }
        return list.visibleRows.flatMap { row -> [Any] in
            guard let title = list.groupTitles[row.id] else { return [row] }
            return [title, row]
        }
    }

    override func accessibilityRows() -> [Any]? {
        return list?.visibleRows ?? []
    }

    override func accessibilitySelectedRows() -> [Any]? {
        return list?.selectedRow.map { [$0] } ?? []
    }

    override func setAccessibilitySelectedRows(_ rows: [Any]?) {
        list?.select((rows?.first as? PreferencesListRow)?.id)
    }

    override func accessibilitySelectedChildren() -> [Any]? {
        return accessibilitySelectedRows()
    }

    override func setAccessibilitySelectedChildren(_ children: [Any]?) {
        setAccessibilitySelectedRows(children)
    }
}

// MARK: - Row

/// A row of a PreferencesListBox: a PreferencesGroupRow (title, explanation, control on
/// the right) with an id, an optional icon before the texts and an optional chevron after
/// the control for a row that opens a page of its own. Clicks on its controls go to the
/// controls; a click anywhere else selects the row.
///
/// On the selection of a key window its texts, symbol and chevron turn white. A subclass
/// that colours texts of its own does it in `applyEnabled()` and checks `isHighlighted`.
class PreferencesListRow: PreferencesGroupRow {

    enum Icon {
        /// An SF Symbol, 20 pt, in `iconTintColor`.
        case symbol(String)
        /// A picture as it is, 24 pt: an app's icon.
        case image(NSImage)
    }

    static let symbolIconSize: CGFloat = 20
    static let imageIconSize: CGFloat = 24
    /// Between the icon and the texts.
    static let iconSpacing: CGFloat = 8
    static let chevronWidth: CGFloat = 10
    static let chevronHeight: CGFloat = 16
    /// Between the control and the chevron.
    static let chevronSpacing: CGFloat = 8

    let id: AnyHashable
    let iconView: NSImageView?
    let chevronView: NSImageView?

    /// The colour of a symbol icon while the row is not on a key window's selection.
    var iconTintColor: NSColor = .secondaryLabelColor {
        didSet { applyEnabled() }
    }

    private(set) var isSelected = false
    /// − and Delete remove the row while it is selected. Off: − is off on it.
    var isRemovable = true {
        didSet {
            guard isRemovable != oldValue else { return }
            list?.applySelection()
        }
    }
    /// The list's window is key: the selection shows in the accent colour.
    private(set) var isSelectionEmphasized = false
    /// On the accent-coloured selection: the texts are white.
    var isHighlighted: Bool {
        return isSelected && isSelectionEmphasized
    }

    fileprivate weak var list: PreferencesListBox?

    /// - Parameters:
    ///   - id: what the list reports and keeps the selection by; unique in the list.
    ///   - accessory, centeredOn, controls: as in PreferencesGroupRow (a pull-down, a button).
    ///   - showsChevron: a `chevron.right` at the right edge, for a row that opens.
    init(
        id: AnyHashable,
        title: String,
        explanation: String? = nil,
        icon: Icon? = nil,
        accessory: NSView? = nil,
        centeredOn anchor: NSView? = nil,
        controls: [NSControl]? = nil,
        showsChevron: Bool = false
    ) {
        self.id = id
        let inset = PreferencesGroupedForm.rowHorizontalInset
        var iconSize: CGFloat = 0
        if let icon {
            let view = PreferencesListImageView()
            view.translatesAutoresizingMaskIntoConstraints = false
            view.setAccessibilityElement(false)
            switch icon {
            case .symbol(let name):
                iconSize = Self.symbolIconSize
                let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
                view.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
                view.imageScaling = .scaleProportionallyDown
            case .image(let image):
                iconSize = Self.imageIconSize
                view.image = image
                view.imageScaling = .scaleProportionallyUpOrDown
            }
            iconView = view
        } else {
            iconView = nil
        }
        if showsChevron {
            let view = PreferencesListImageView()
            view.translatesAutoresizingMaskIntoConstraints = false
            view.setAccessibilityElement(false)
            let configuration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            view.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
            view.imageScaling = .scaleNone
            chevronView = view
        } else {
            chevronView = nil
        }

        super.init(
            title: title,
            explanation: explanation,
            accessory: accessory,
            centeredOn: anchor,
            controls: controls,
            leadingInset: iconView == nil ? inset : inset + iconSize + Self.iconSpacing,
            trailingInset: chevronView == nil ? inset : inset + Self.chevronWidth + Self.chevronSpacing
        )

        // The row speaks for its texts.
        titleLabel.setAccessibilityElement(false)
        explanationLabel.setAccessibilityElement(false)

        var constraints: [NSLayoutConstraint] = []
        if let iconView {
            addSubview(iconView)
            constraints += [
                iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
                iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: iconSize),
                iconView.heightAnchor.constraint(equalToConstant: iconSize),
                iconView.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: PreferencesGroupedForm.controlMinimumInset),
            ]
        }
        if let chevronView {
            addSubview(chevronView)
            constraints += [
                chevronView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
                chevronView.widthAnchor.constraint(equalToConstant: Self.chevronWidth),
                chevronView.heightAnchor.constraint(equalToConstant: Self.chevronHeight),
                // On the control's line when there is one, in the middle of the row otherwise.
                chevronView.centerYAnchor.constraint(equalTo: (anchor ?? accessory ?? self).centerYAnchor),
            ]
        }
        NSLayoutConstraint.activate(constraints)
        applyEnabled()
    }

    required init?(coder: NSCoder) {
        fatalError("PreferencesListRow is built in code")
    }

    fileprivate func setSelection(selected: Bool, emphasized: Bool) {
        guard selected != isSelected || emphasized != isSelectionEmphasized else { return }
        isSelected = selected
        isSelectionEmphasized = emphasized
        applyEnabled()
    }

    override func applyEnabled() {
        super.applyEnabled()
        let highlighted = isHighlighted
        if highlighted {
            let white = NSColor.alternateSelectedControlTextColor
            titleLabel.textColor = white.withAlphaComponent(isEnabled ? 1 : 0.5)
            explanationLabel.textColor = white.withAlphaComponent(isEnabled ? 0.85 : 0.5)
        }
        if let iconView {
            if iconView.image?.isTemplate == true {
                iconView.contentTintColor = highlighted ? .alternateSelectedControlTextColor
                    : (isEnabled ? iconTintColor : .tertiaryLabelColor)
                iconView.alphaValue = 1
            } else {
                iconView.alphaValue = isEnabled ? 1 : 0.5
            }
        }
        chevronView?.contentTintColor = highlighted ? .alternateSelectedControlTextColor : .tertiaryLabelColor
        // On the accent colour the controls draw as on a dark box: a pull-down's text and an
        // ⓘ turn light, in light mode too (dark text on the accent is hard to read).
        accessory?.appearance = highlighted ? Self.darkAppearance(matching: effectiveAppearance) : nil
    }

    /// Dark, or dark high contrast when `appearance` is high contrast.
    private static func darkAppearance(matching appearance: NSAppearance) -> NSAppearance? {
        let highContrast = appearance.name.rawValue.contains("Accessibility")
        return NSAppearance(named: highContrast ? .accessibilityHighContrastDarkAqua : .darkAqua)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // High contrast went on or off.
        if isHighlighted {
            accessory?.appearance = Self.darkAppearance(matching: effectiveAppearance)
        }
    }

    // MARK: Clicks

    /// The row's background, its texts, icon and chevron take the click; its controls keep
    /// theirs (while they are on).
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return Self.takesClicks(hit, in: self) ? hit : self
    }

    private static func takesClicks(_ view: NSView, in row: NSView) -> Bool {
        var current: NSView? = view
        while let candidate = current, candidate !== row {
            if let field = candidate as? NSTextField {
                if field.isEditable || field.isSelectable { return true }
            } else if let image = candidate as? NSImageView {
                if image.isEditable { return true }
            } else if let control = candidate as? NSControl {
                // A control that is off does nothing with a click: the row takes it.
                return control.isEnabled
            }
            current = candidate.superview
        }
        return false
    }

    override func mouseDown(with event: NSEvent) {
        list?.rowWasClicked(self, clickCount: event.clickCount)
    }

    // MARK: Accessibility

    override func isAccessibilityElement() -> Bool {
        return true
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        return .row
    }

    /// The title, then the explanation.
    override func accessibilityLabel() -> String? {
        guard let explanation, !explanation.isEmpty else { return title }
        return "\(title), \(explanation)"
    }

    override func isAccessibilitySelected() -> Bool {
        return isSelected
    }

    override func setAccessibilitySelected(_ selected: Bool) {
        guard let list else { return }
        if selected {
            list.select(id)
        } else if list.selectedID == id {
            list.select(nil)
        }
    }

    override func accessibilityIndex() -> Int {
        return list?.visibleRows.firstIndex { $0 === self } ?? 0
    }

    /// Selects the row; a row with a chevron also opens.
    override func accessibilityPerformPress() -> Bool {
        guard let list else { return false }
        list.select(id)
        if chevronView != nil {
            list.onOpen?(id)
        }
        return true
    }
}

// MARK: - Empty row

/// What a list without rows shows: a title and an optional explanation, centred, in the
/// secondary colour (it says what to do, so it stays readable; the tertiary colour of a
/// dimmed row is too faint on a light box). It cannot be selected.
final class PreferencesListEmptyRow: NSView {

    let titleLabel: NSTextField
    let explanationLabel: NSTextField

    var title: String {
        get { return titleLabel.stringValue }
        set { titleLabel.stringValue = newValue }
    }

    var explanation: String? {
        get { return explanationLabel.isHidden ? nil : explanationLabel.stringValue }
        set {
            explanationLabel.stringValue = newValue ?? ""
            explanationLabel.isHidden = newValue == nil
        }
    }

    init(title: String, explanation: String?, width: CGFloat) {
        titleLabel = NSTextField(labelWithString: title)
        explanationLabel = NSTextField(wrappingLabelWithString: explanation ?? "")
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let inset = PreferencesGroupedForm.rowHorizontalInset

        titleLabel.font = PreferencesGroupedForm.titleFont
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        explanationLabel.font = PreferencesGroupedForm.explanationFont
        explanationLabel.textColor = .secondaryLabelColor
        explanationLabel.alignment = .center
        explanationLabel.isSelectable = false
        explanationLabel.isHidden = explanation == nil
        explanationLabel.preferredMaxLayoutWidth = max(0, width - 2 * inset)
        for label in [titleLabel, explanationLabel] {
            label.setAccessibilityElement(false)
        }

        let stack = NSStackView(views: [titleLabel, explanationLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = PreferencesGroupedForm.explanationSpacing
        stack.detachesHiddenViews = true
        let vertical = PreferencesListBox.emptyRowVerticalInset
        stack.edgeInsets = NSEdgeInsets(top: vertical, left: inset, bottom: vertical, right: inset)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("PreferencesListEmptyRow is built in code")
    }

    override func isAccessibilityElement() -> Bool {
        return true
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        return .staticText
    }

    override func accessibilityLabel() -> String? {
        guard let explanation, !explanation.isEmpty else { return title }
        return "\(title), \(explanation)"
    }
}

// MARK: - Group title

/// A small title inside a list's box, above a group of its rows ("Other buttons and
/// keys"): secondary, semibold, at the rows' inset, more room above it than under it. It is
/// not a row: it cannot be selected and the pointer over it points at no row.
final class PreferencesListGroupTitle: NSView {

    /// Above the title (under the hairline over it) and under it.
    static let topInset: CGFloat = 12
    static let bottomInset: CGFloat = 2

    let titleLabel: NSTextField

    var title: String {
        get { return titleLabel.stringValue }
        set { titleLabel.stringValue = newValue }
    }

    static var font: NSFont {
        return NSFont.systemFont(ofSize: PreferencesForm.hintFontSize, weight: .semibold)
    }

    init(title: String) {
        titleLabel = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let inset = PreferencesGroupedForm.rowHorizontalInset
        titleLabel.font = Self.font
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.setAccessibilityElement(false)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: Self.topInset),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.bottomInset),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -inset),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("PreferencesListGroupTitle is built in code")
    }

    override func isAccessibilityElement() -> Bool {
        return true
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        return .staticText
    }

    override func accessibilityLabel() -> String? {
        return title
    }
}

// MARK: - Section

/// A list with an optional small title above it ("Apps"), spaced like a titled
/// PreferencesGroupSection. The title also names the accessibility list.
final class PreferencesListSection: NSView {

    let titleLabel: NSTextField?
    let list: PreferencesListBox

    init(title: String? = nil, list: PreferencesListBox) {
        self.list = list
        self.titleLabel = title.map(PreferencesGroupedForm.makeSectionTitle)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        PreferencesGroupedForm.layOutSection(self, title: titleLabel, body: list)
        if let title {
            list.rowsView.setAccessibilityLabel(title)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("PreferencesListSection is built in code")
    }
}
