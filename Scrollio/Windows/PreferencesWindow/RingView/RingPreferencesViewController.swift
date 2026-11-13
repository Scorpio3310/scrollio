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
//  shows the Buttons pane with its row selected), as the Gestures pane does for its button;
//  its explanation also says that a key combination works. Then the eight places, clockwise
//  from the top, each with the pull-down a row of the Buttons pane has
//  (`ButtonActionPullDown`, with the menu of what a place can hold): a listed action, a
//  key combination recorded there ("Keyboard Shortcut…") or an app, a file or a script
//  ("Open App or File…", the Buttons pane's popover).
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
    /// that there is none yet; and, either way, that a key combination works too (also one
    /// that Logi Options+ sends for a button).
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
    /// The name in its middle is not drawn that much smaller: it has to be read.
    static let titlePointSize: CGFloat = 11
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
        style.titlePointSize = Self.titlePointSize
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
    /// All pull-downs have this width, so they line up (the Buttons pane's).
    static let popUpWidth: CGFloat = ButtonActionPullDown.width

    /// Identifiers for the views of the pane (tests and accessibility tooling).
    enum Identifier {
        static let preview = NSUserInterfaceItemIdentifier("ring-preview")
        static let triggerButton = NSUserInterfaceItemIdentifier("ring-trigger-button")
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
    /// Shows "Open App or File" at a place's pull-down, as the Buttons pane does. Tests
    /// replace it: nothing is shown.
    var presentOpenTarget: (OpenTargetConfigPopover, NSView, OpenTargetPayload?) -> Void = { popover, anchor, existing in
        popover.show(at: anchor, existing: existing)
    }
    /// Starts the recorder of "Keyboard Shortcut…" at a place's pull-down. Tests replace
    /// it: a real recorder taps the system's events.
    var startShortcutRecorder: ((ButtonActionPullDown) -> Void)? {
        didSet {
            placePopUps.forEach { $0.startShortcutRecorder = startShortcutRecorder }
        }
    }
    /// "Open App or File" while it is open for a place.
    private(set) var openTargetPopover: OpenTargetConfigPopover?
    /// The pull-downs' stand-in bindings keep their identity while the pane lives.
    private let placeIDs = (0..<ShortcutRingSettings.placeCount).map { _ in UUID() }

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

    /// Lights `litPlace` in the drawing and tints the title of its row, so that the
    /// picture and the list say the same thing: this row is that place.
    private func showLitPlace() {
        let lit = litPlace
        previewView?.lit = lit
        for (place, row) in placeRows.enumerated() {
            row.titleLabel.textColor = place == lit
                ? NSColor.controlAccentColor
                : PreferencesGroupedForm.titleColor(enabled: true)
        }
    }

    // MARK: - Views (read access for tests)

    private(set) var previewView: ShortcutRingPreviewView!
    private(set) var triggerRow: PreferencesGroupRow!
    private(set) var triggerButton: NSButton!
    /// Top, Top right … Top left.
    private(set) var placeRows: [PreferencesGroupRow] = []
    private(set) var placePopUps: [ButtonActionPullDown] = []
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
        placePopUps = (0..<ShortcutRingSettings.placeCount).map { makePopUp(for: $0) }
        placeRows = (0..<ShortcutRingSettings.placeCount).map { makePlaceRow($0) }
        let places = makePlacesSection(rows: placeRows)

        sections = [preview, trigger, places]
        PreferencesGroupedForm.add(sections, to: content)
        content.setCustomSpacing(PreferencesGroupedForm.sectionSpacing, after: trigger)

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
        showLitPlace()
        // A recording that still waits for a key, and the popover, go with the pane.
        placePopUps.forEach { $0.cancelShortcutRecording() }
        openTargetPopover?.hide()
        openTargetPopover = nil
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
            // (A place that runs nothing shows "No Action", as the ring shows a dot.)
            popUp.configure(with: ring[place].asBinding(id: placeIDs[place]))
        }
        previewView.face = ShortcutRingFace(ring)
        // The ring on screen shows this face too: it is made here, not at a press.
        ShortcutRingController.prepare(previewView.face, for: ring)
        showLitPlace()
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
        showLitPlace()
    }

    /// The pointer is over `place` of the drawing (nil: over none).
    func placePointedAt(_ place: Int?) {
        pointedPlace = place
        showLitPlace()
    }

    /// A place of the drawing was clicked: its row is selected. The row's pull-down takes
    /// the keyboard (Space opens it) and is scrolled into view, and the place stays lit.
    func selectPlace(_ place: Int) {
        guard placePopUps.indices.contains(place) else { return }
        selectedPlace = place
        showLitPlace()
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

    /// Puts `new` into `place`. What a place cannot hold (a recorded mouse button, a
    /// modifier key by itself) is not stored: the pull-down shows again what was there.
    func setPlace(_ new: ShortcutRingPlace, at place: Int) {
        guard placePopUps.indices.contains(place) else { return }
        // The row whose pull-down was used is the selected one.
        selectedPlace = place
        var ring = Options.shared.ring
        guard new.isEmpty || new.runs, ring[place] != new else {
            reload()
            return
        }
        ring[place] = new
        Options.shared.ring = ring
        reload()
    }

    /// "Open App or File…" of a place: the Buttons pane's popover at the pull-down, with
    /// what the place opens now.
    private func presentOpenTargetPopover(forPlace place: Int) {
        guard placePopUps.indices.contains(place) else { return }
        openTargetPopover?.hide()
        let popover = OpenTargetConfigPopover()
        openTargetPopover = popover
        popover.onCommit = { [weak self] payload in
            self?.openTargetPopover = nil
            self?.setPlace(ShortcutRingPlace(openTarget: payload), at: place)
        }
        popover.onCancel = { [weak self] in
            self?.openTargetPopover = nil
        }
        presentOpenTarget(popover, placePopUps[place], Options.shared.ring[place].openTarget)
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
        // Room for two lines whatever the row says, so naming a button does not move the rows.
        row.reservedExplanations = [text("ring-trigger-none")]
        triggerRow = row
        return row
    }

    /// The pull-down of one place: the Buttons pane's, with the menu of a place.
    private func makePopUp(for place: Int) -> ButtonActionPullDown {
        let popUp = ButtonActionPullDown(
            binding: Options.shared.ring[place].asBinding(id: placeIDs[place]), forRingPlace: true
        )
        popUp.tag = place
        popUp.identifier = Identifier.action(place)
        popUp.setAccessibilityLabel(ShortcutRingPlaceName.localized(place))
        popUp.startShortcutRecorder = startShortcutRecorder
        popUp.onShortcutSelected = { [weak self] shortcut in
            self?.setPlace(ShortcutRingPlace(action: shortcut?.identifier ?? ""), at: place)
        }
        popUp.onCustomShortcutRecorded = { [weak self] name in
            self?.setPlace(ShortcutRingPlace(action: name), at: place)
        }
        popUp.onOpenTargetSelectionRequested = { [weak self] in
            self?.presentOpenTargetPopover(forPlace: place)
        }
        return popUp
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
}
