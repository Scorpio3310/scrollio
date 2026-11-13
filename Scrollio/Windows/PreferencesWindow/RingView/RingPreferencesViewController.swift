//
//  RingPreferencesViewController.swift
//  Scrollio
//  "Shortcut Ring" preferences pane: what the ring holds, built in code on
//  PreferencesGroupedForm like the Gestures pane.
//
//  On top the ring as it opens at the pointer, drawn by the code that draws it on screen
//  (`ShortcutRingArtwork`). The drawing and the rows point at each other: the place of
//  the row under the pointer is lit in the drawing, a place under the pointer is lit too,
//  and a click on a place selects its row (its pull-down takes the keyboard and is
//  scrolled into view; the place stays lit). Then a box
//  with what opens the ring: which button or key runs the Shortcut Ring is chosen in the
//  Buttons pane, and the row names it and leads there ("Set Up…" records one, "Change"
//  shows the Buttons pane with its row selected), as the Gestures pane does for its button.
//  A muted line says that a key combination works too. Then the eight places, clockwise
//  from the top, each with a pull-down of the keyboard shortcuts a place can hold
//  (`ShortcutRingPlace.offeredCategories`).
//
//  The pane only edits Options.shared.ring.
//

import Cocoa

/// What the stored button bindings mean for the pane: what opens the ring.
struct ShortcutRingBindingSummary: Equatable {
    /// The names of the buttons and keys that open the ring, as the Buttons pane titles
    /// them ("Thumb panel", "⌃⌥ Space").
    var triggerTitles: [String]

    var hasTrigger: Bool {
        return !triggerTitles.isEmpty
    }

    init(triggerTitles: [String]) {
        self.triggerTitles = triggerTitles
    }

    /// - Parameters:
    ///   - bindings: the bindings that run (`Options.shared.buttons.binding`).
    ///   - titles: what the Buttons pane calls the triggers of `bindings`, in order.
    init(
        bindings: [ButtonBinding],
        titles: ([RecordedEvent]) -> [String] = { ButtonTriggerNaming.titles(for: $0) }
    ) {
        // What InputProcessor runs: an enabled binding whose trigger can run at all, a
        // mouse button or a key.
        let opens: (ButtonBinding) -> Bool = {
            $0.isEnabled && $0.systemShortcutName == SystemShortcut.shortcutRing.identifier
                && ButtonUtils.isRunnable($0.triggerEvent)
        }
        var names: [String] = []
        for (binding, name) in zip(bindings, titles(bindings.map(\.triggerEvent))) where opens(binding) {
            if !names.contains(name) {
                names.append(name)
            }
        }
        triggerTitles = names
    }

    /// The explanation of the pane's first row: the buttons and keys, joined as a list, or
    /// that there is none yet.
    var explanation: String {
        guard hasTrigger else {
            return NSLocalizedString("ring-trigger-none", comment: "")
        }
        let triggers = ListFormatter.localizedString(byJoining: triggerTitles)
        return String(format: NSLocalizedString("ring-trigger-bound", comment: ""), triggers)
    }

    static var current: ShortcutRingBindingSummary {
        return ShortcutRingBindingSummary(bindings: Options.shared.buttons.binding)
    }
}

/// The ring on a card, as it opens at the pointer. A place can be pointed at and clicked.
final class ShortcutRingPreviewView: NSView {

    /// The pointer is over this place of the drawing, or over none (nil).
    var onPlaceHovered: ((Int?) -> Void)?
    /// A place of the drawing was clicked.
    var onPlaceClicked: ((Int) -> Void)?


    /// The ring is drawn this much smaller than on screen.
    static let ringScale: CGFloat = 0.74
    static let preferredHeight: CGFloat = 206
    static let cornerRadius: CGFloat = 10

    var face = ShortcutRingFace(places: []) {
        didSet { needsDisplay = true }
    }
    /// The lit place: the one pointed at (in the rows or in the drawing), else the one
    /// whose row is selected.
    var lit: Int? {
        didSet {
            guard lit != oldValue else { return }
            needsDisplay = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(NSLocalizedString("ring-preview-description", comment: ""))
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    /// The place of the drawn ring at `point` of this view, an empty one too (its row can
    /// then be filled); nil in the ring's middle and beside the ring.
    func place(at point: NSPoint) -> Int? {
        // The geometry is the screen's: unscaled, and with y growing downwards.
        let offset = CGPoint(x: (point.x - bounds.midX) / Self.ringScale, y: -(point.y - bounds.midY) / Self.ringScale)
        guard case .place(let place) = ShortcutRingGeometry.target(at: offset, centre: .zero),
              hypot(offset.x, offset.y) <= ShortcutRingGeometry.outerRadius,
              face.places.indices.contains(place) else { return nil }
        return place
    }

    override func mouseMoved(with event: NSEvent) {
        onPlaceHovered?(place(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) {
        onPlaceHovered?(nil)
    }

    override func mouseDown(with event: NSEvent) {
        guard let place = place(at: convert(event.locationInWindow, from: nil)) else {
            return super.mouseDown(with: event)
        }
        onPlaceClicked?(place)
    }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: NSView.noIntrinsicMetric, height: Self.preferredHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        let card = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: Self.cornerRadius, yRadius: Self.cornerRadius
        )
        ScrollPreviewPalette.cardFill.setFill()
        card.fill()
        ScrollPreviewPalette.cardEdge.setStroke()
        card.lineWidth = 1
        card.stroke()

        var style = ShortcutRingArtwork.Style()
        style.backdrop = .drawn
        style.scale = Self.ringScale
        style.increasesContrast = PreferencesGroupedForm.isHighContrast(effectiveAppearance)
        let centre = CGPoint(x: bounds.midX, y: bounds.midY)
        ShortcutRingArtwork.drawShadow(centre: centre, scale: Self.ringScale)
        ShortcutRingArtwork.draw(face, lit: lit, centre: centre, style: style)
    }
}

final class RingPreferencesViewController: NSViewController {

    static let tabIdentifier = "ring"

    /// As wide as the other panes.
    static let paneWidth: CGFloat = 520
    static var boxWidth: CGFloat {
        return PreferencesGroupedForm.boxWidth(paneWidth: paneWidth)
    }
    /// All pull-downs have this width, so they line up (the Gestures pane's).
    static let popUpWidth: CGFloat = 240

    /// Identifiers for the views of the pane (tests and accessibility tooling).
    enum Identifier {
        static let preview = NSUserInterfaceItemIdentifier("ring-preview")
        static let triggerButton = NSUserInterfaceItemIdentifier("ring-trigger-button")
        static let triggerNote = NSUserInterfaceItemIdentifier("ring-trigger-note")
        static let placesHint = NSUserInterfaceItemIdentifier("ring-places-hint")

        static func action(_ place: Int) -> NSUserInterfaceItemIdentifier {
            return NSUserInterfaceItemIdentifier("ring-place-\(place)")
        }
    }

    // MARK: - State

    /// What opens the ring; tests and pictures replace it with fixtures.
    var bindingSummary: () -> ShortcutRingBindingSummary = { .current }
    /// "Set Up…" or "Change": shows the Buttons pane and, with nothing that opens the ring
    /// yet (true), records a button or key that gets the Shortcut Ring; with one (false),
    /// selects its row there. Tests replace it.
    var openButtonsPane: ((Bool) -> Void)?

    /// The place of the row under the pointer.
    private(set) var hoveredPlace: Int?
    /// The place under the pointer in the drawing.
    private(set) var pointedPlace: Int?
    /// The place that was clicked in the drawing, or whose pull-down was last used: its
    /// row is the selected one.
    private(set) var selectedPlace: Int?

    /// What the drawing lights: what is pointed at, else the selected place.
    var litPlace: Int? {
        return hoveredPlace ?? pointedPlace ?? selectedPlace
    }

    // MARK: - Views (read access for tests)

    private(set) var previewView: ShortcutRingPreviewView!
    private(set) var triggerRow: PreferencesGroupRow!
    private(set) var triggerButton: NSButton!
    private(set) var triggerNoteLabel: NSTextField!
    /// Top, Top right … Top left.
    private(set) var placeRows: [PreferencesGroupRow] = []
    private(set) var placePopUps: [NSPopUpButton] = []
    private(set) var placesHintLabel: NSTextField!
    /// Everything in the content stack, top to bottom.
    private(set) var sections: [NSView] = []

    // MARK: - Lifecycle

    init() {
        super.init(nibName: nil, bundle: nil)
        title = NSLocalizedString("ring-tab-title", comment: "")
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        title = NSLocalizedString("ring-tab-title", comment: "")
    }

    override func loadView() {
        let root = PreferencesForm.makeBackground()
        let content = PreferencesGroupedForm.installContentStack(in: root, paneWidth: Self.paneWidth)
        content.setHuggingPriority(.defaultHigh, for: .vertical)

        let preview = ShortcutRingPreviewView()
        preview.identifier = Identifier.preview
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.heightAnchor.constraint(equalToConstant: ShortcutRingPreviewView.preferredHeight).isActive = true
        preview.onPlaceHovered = { [weak self] in self?.placePointedAt($0) }
        preview.onPlaceClicked = { [weak self] in self?.selectPlace($0) }
        previewView = preview

        let width = Self.boxWidth
        let trigger = PreferencesGroupSection(width: width, rows: [makeTriggerRow()])
        triggerNoteLabel = Self.makeNote(text("ring-trigger-note"), identifier: Identifier.triggerNote)
        let triggerNote = Self.inset(triggerNoteLabel)
        placePopUps = (0..<ShortcutRingSettings.placeCount).map { makePopUp(for: $0) }
        placeRows = (0..<ShortcutRingSettings.placeCount).map { makePlaceRow($0) }
        let places = makePlacesSection(rows: placeRows)

        sections = [preview, trigger, triggerNote, places]
        PreferencesGroupedForm.add(sections, to: content)
        // The muted line sits close under its box.
        content.setCustomSpacing(PreferencesGroupedForm.noteSpacing, after: trigger)
        content.setCustomSpacing(PreferencesGroupedForm.sectionSpacing, after: triggerNote)

        view = root
        reload()
        root.setFrameSize(root.fittingSize)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        // A button may have been bound under Buttons meanwhile, or a file imported.
        reload()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        hoveredPlace = nil
        pointedPlace = nil
        selectedPlace = nil
        previewView.lit = nil
    }

    // MARK: - Refresh

    /// Puts the stored ring and what opens it into the rows and the drawing.
    func reload() {
        guard isViewLoaded, previewView != nil else { return }
        let summary = bindingSummary()
        triggerRow.explanation = summary.explanation
        triggerButton.title = text(summary.hasTrigger ? "ring-trigger-change" : "ring-trigger-set-up")

        let ring = Options.shared.ring
        for (place, popUp) in placePopUps.enumerated() {
            updateTitle(of: popUp, place: ring[place])
        }
        previewView.face = ShortcutRingFace(ring)
        previewView.lit = litPlace
        PreferencesForm.fitToContent(self)
    }

    // MARK: - The row under the pointer

    private static let hoverPlaceInfo = "ringPlace"

    private static func place(of event: NSEvent) -> Int? {
        return event.trackingArea?.userInfo?[hoverPlaceInfo] as? Int
    }

    /// The pointer entered or left the row of `place`: its place is lit in the drawing.
    func placeHoverChanged(_ place: Int, inside: Bool) {
        if inside {
            hoveredPlace = place
        } else if hoveredPlace == place {
            hoveredPlace = nil
        }
        previewView?.lit = litPlace
    }

    /// The pointer is over `place` of the drawing (nil: over none).
    func placePointedAt(_ place: Int?) {
        pointedPlace = place
        previewView?.lit = litPlace
    }

    /// A place of the drawing was clicked: its row is selected. The row's pull-down takes
    /// the keyboard (Space opens it) and is scrolled into view, and the place stays lit.
    func selectPlace(_ place: Int) {
        guard placePopUps.indices.contains(place) else { return }
        selectedPlace = place
        previewView?.lit = litPlace
        let popUp = placePopUps[place]
        popUp.scrollToVisible(popUp.bounds)
        view.window?.makeFirstResponder(popUp)
    }

    override func mouseEntered(with event: NSEvent) {
        guard let place = Self.place(of: event) else { return super.mouseEntered(with: event) }
        placeHoverChanged(place, inside: true)
    }

    override func mouseExited(with event: NSEvent) {
        guard let place = Self.place(of: event) else { return super.mouseExited(with: event) }
        placeHoverChanged(place, inside: false)
    }

    // MARK: - Actions

    @objc func triggerButtonClicked(_ sender: NSButton) {
        let addsTrigger = !bindingSummary().hasTrigger
        if let openButtonsPane {
            openButtonsPane(addsTrigger)
            return
        }
        guard let split = PreferencesButtonsViewController.splitViewController(of: self),
              split.selectPane(withIdentifier: PANEL_IDENTIFIER.buttons) else { return }
        guard let buttons = split.controller(for: PANEL_IDENTIFIER.buttons) as? PreferencesButtonsViewController else { return }
        if addsTrigger {
            buttons.beginAddingBinding(action: SystemShortcut.shortcutRing)
        } else {
            buttons.selectRingTrigger()
        }
    }

    /// A place's pull-down: an action's name, or "" for No Action.
    @objc func actionSelected(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String,
              placePopUps.indices.contains(sender.tag) else { return }
        // The row whose pull-down was used is the selected one.
        selectedPlace = sender.tag
        setAction(identifier, ofPlace: sender.tag)
    }

    /// Stores `identifier` (a `SystemShortcut` identifier, or "" for nothing) in `place`.
    func setAction(_ identifier: String, ofPlace place: Int) {
        var ring = Options.shared.ring
        let new = ShortcutRingPlace(action: identifier)
        guard ring[place] != new else {
            previewView?.lit = litPlace
            return
        }
        ring[place] = new
        Options.shared.ring = ring
        reload()
    }

    // MARK: - Rows

    private func text(_ key: String) -> String {
        return NSLocalizedString(key, comment: "")
    }

    /// "Button or key": what opens the ring, or nothing yet, and a push button to the
    /// Buttons pane.
    private func makeTriggerRow() -> PreferencesGroupRow {
        let button = PreferencesGroupedForm.makePushButton(
            title: text("ring-trigger-set-up"),
            target: self,
            action: #selector(triggerButtonClicked(_:))
        )
        button.identifier = Identifier.triggerButton
        triggerButton = button
        let row = PreferencesGroupRow(
            title: text("ring-trigger"),
            explanation: text("ring-trigger-none"),
            accessory: button
        )
        triggerRow = row
        return row
    }

    private func makePopUp(for place: Int) -> NSPopUpButton {
        let popUp = NSPopUpButton(frame: .zero, pullsDown: true)
        popUp.tag = place
        popUp.identifier = Identifier.action(place)
        popUp.setAccessibilityLabel(ShortcutRingPlaceName.localized(place))
        popUp.translatesAutoresizingMaskIntoConstraints = false
        popUp.widthAnchor.constraint(equalToConstant: Self.popUpWidth).isActive = true
        popUp.menu = makeActionMenu(for: place)
        return popUp
    }

    /// "No Action", then the categories of keyboard shortcuts, each a submenu.
    private func makeActionMenu(for place: Int) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        // A pull-down always shows item 0 as its title.
        menu.addItem(NSMenuItem(title: "", action: nil, keyEquivalent: ""))

        let none = NSMenuItem(title: text("ring-action-none"), action: #selector(actionSelected(_:)), keyEquivalent: "")
        none.target = self
        none.tag = place
        none.representedObject = "" as NSString
        menu.addItem(none)
        menu.addItem(NSMenuItem.separator())

        for category in ShortcutRingPlace.offeredCategories {
            let categoryItem = NSMenuItem(
                title: SystemShortcut.localizedCategoryName(category.category), action: nil, keyEquivalent: ""
            )
            categoryItem.image = Self.symbolImage(SystemShortcut.categorySymbolName(category.category))
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            for shortcut in category.shortcuts {
                let item = NSMenuItem(title: shortcut.localizedName, action: #selector(actionSelected(_:)), keyEquivalent: "")
                item.target = self
                item.tag = place
                item.representedObject = shortcut.identifier as NSString
                item.image = Self.symbolImage(shortcut.symbolName)
                submenu.addItem(item)
            }
            categoryItem.submenu = submenu
            menu.addItem(categoryItem)
        }
        // macOS 27 hides menu item images unless asked: every action keeps its symbol.
        menu.keepItemImagesVisible()
        return menu
    }

    private func updateTitle(of popUp: NSPopUpButton, place: ShortcutRingPlace) {
        guard let titleItem = popUp.menu?.items.first else { return }
        if let shortcut = place.shortcut {
            titleItem.title = shortcut.localizedName
            titleItem.image = Self.symbolImage(shortcut.symbolName)
        } else {
            titleItem.title = text("ring-action-none")
            titleItem.image = nil
        }
    }

    private static func symbolImage(_ name: String) -> NSImage? {
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    /// One place with its pull-down. The row tells the drawing when the pointer is over it.
    private func makePlaceRow(_ place: Int) -> PreferencesGroupRow {
        let row = PreferencesGroupRow(title: ShortcutRingPlaceName.localized(place), accessory: placePopUps[place])
        row.addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: [Self.hoverPlaceInfo: place]
        ))
        return row
    }

    /// "Shortcuts": its title, one line on the two ways to choose, and the box of rows.
    private func makePlacesSection(rows: [PreferencesGroupRow]) -> NSView {
        let inset = PreferencesGroupedForm.rowHorizontalInset
        let title = PreferencesGroupedForm.makeSectionTitle(text("ring-places-header"))
        let hint = Self.makeNote(text("ring-places-hint"), identifier: Identifier.placesHint)
        placesHintLabel = hint
        let box = PreferencesGroupBox(width: Self.boxWidth, rows: rows)

        let section = NSView()
        section.translatesAutoresizingMaskIntoConstraints = false
        for view in [title, hint, box] as [NSView] {
            section.addSubview(view)
        }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: section.topAnchor),
            title.leadingAnchor.constraint(equalTo: section.leadingAnchor, constant: inset),
            title.trailingAnchor.constraint(lessThanOrEqualTo: section.trailingAnchor, constant: -inset),
            hint.topAnchor.constraint(equalTo: title.bottomAnchor, constant: PreferencesGroupedForm.explanationSpacing),
            hint.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            hint.trailingAnchor.constraint(lessThanOrEqualTo: section.trailingAnchor, constant: -inset),
            box.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: PreferencesGroupedForm.sectionTitleSpacing + 2),
            box.leadingAnchor.constraint(equalTo: section.leadingAnchor),
            box.trailingAnchor.constraint(equalTo: section.trailingAnchor),
            box.bottomAnchor.constraint(equalTo: section.bottomAnchor),
        ])
        return section
    }

    /// A muted line.
    private static func makeNote(_ string: String, identifier: NSUserInterfaceItemIdentifier) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: string)
        label.identifier = identifier
        label.font = PreferencesGroupedForm.explanationFont
        label.textColor = PreferencesGroupedForm.explanationColor(enabled: true)
        label.isSelectable = false
        label.preferredMaxLayoutWidth = boxWidth - 2 * PreferencesGroupedForm.rowHorizontalInset
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    /// `label` inset like the text of the rows above it.
    private static func inset(_ label: NSTextField) -> NSView {
        let inset = PreferencesGroupedForm.rowHorizontalInset
        let holder = NSView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: holder.topAnchor),
            label.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
            label.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: inset),
            label.trailingAnchor.constraint(lessThanOrEqualTo: holder.trailingAnchor, constant: -inset),
        ])
        return holder
    }
}
