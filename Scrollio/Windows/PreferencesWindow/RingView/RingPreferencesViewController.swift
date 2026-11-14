//
//  RingPreferencesViewController.swift
//  Scrollio
//  "Shortcut Ring" preferences pane: what the ring holds, built in code on
//  PreferencesGroupedForm like the Gestures pane.
//
//  On top two cards, as the Gestures pane has them (`ShortcutRingHeaderView`): on the left
//  the button or key that opens the ring, on the connected mouse (`ShortcutRingTriggerCard`,
//  by the rule the Gestures pane's picture shares: the first trigger the row names, a
//  dashed blank key while nothing opens it; it presses once when the pane appears, when the
//  trigger changes and when the pointer enters the "Button or key" row); on the right
//  the ring as it stands open at the pointer, drawn by the code that draws it on
//  screen (`ShortcutRingArtwork`): its nine drops, at rest and drawn plainly. The drawing and the rows point at each other: the place of
//  the row under the pointer is lit in the drawing, a place under the pointer is lit too,
//  and a click on a place selects its row (its pull-down takes the keyboard and is
//  scrolled into view; the place stays lit). Then a box
//  with what opens the ring: which button or key runs the Shortcut Ring is chosen in the
//  Buttons pane, and the row names it and leads there ("Set Up…" records one, "Change"
//  shows the Buttons pane with its row selected), as the Gestures pane does for its button;
//  while only an app's own button or key opens it, the row says where ("Only in Figma:
//  Thumb panel.") and "Change" shows that app's Buttons part (`ApplicationTriggerRule`);
//  its explanation also says that a key combination works. Then the eight places, clockwise
//  from the top, each with the pull-down a row of the Buttons pane has
//  (`ButtonActionPullDown`, with the menu of what a place can hold): a listed action, a
//  key combination recorded there ("Keyboard Shortcut…") or an app, a file or a script
//  ("Open App or File…", the Buttons pane's popover). While nothing opens the ring (no
//  binding of Buttons, no app's own, or only apps that open their own ring: "Only in
//  Figma, with its own ring: Thumb panel."), the places are folded under their title
//  ("Shortcuts ›", `PreferencesDisclosureSection`): a click opens them and they can be
//  edited as ever, and a click on a place of the drawing opens them too; once something
//  opens the ring they show by themselves, with a plain title. Under the boxes "Reset to
//  Defaults", as in the Scrolling pane (`PreferencesPaneReset`): the eight places and the
//  freeze switch of a new ring; what opens the ring is a binding of Buttons and stays.
//
//  The pane only edits Options.shared.ring.
//
//  An app's page under Apps shows the same drawing of the ring, across the whole width, the
//  same freeze switch and the same eight rows, in the pane's order, for the app's own ring
//  (`init(application:)`, as the Scrolling settings there get a target application): then
//  they edit only that app's ring, and what is not the ring's is left out: what opens the
//  ring (and its card), the line on how to choose and "Reset to Defaults" (the part has
//  its own).
//

import Cocoa

/// What the stored button bindings mean for the pane: what opens the ring.
struct ShortcutRingBindingSummary: Equatable {
    /// The names of the buttons and keys of the Buttons pane that open the ring, as that
    /// pane titles them ("Thumb panel", "⌃⌥ Space").
    var triggerTitles: [String]
    /// With none of those: the apps whose own buttons or keys open it while they are in
    /// front (nil: none does).
    var onlyInApps: ApplicationTriggers?
    /// The trigger the pane's picture shows: the first of the row's (`TriggerPictureSource`).
    var picture: TriggerPictureSource

    /// A binding of the Buttons pane opens the ring.
    var hasTrigger: Bool {
        return !triggerTitles.isEmpty
    }

    init(triggerTitles: [String], onlyInApps: ApplicationTriggers? = nil, picture: TriggerPictureSource = .none) {
        self.triggerTitles = triggerTitles
        self.onlyInApps = triggerTitles.isEmpty ? onlyInApps : nil
        self.picture = picture
    }

    /// - Parameters:
    ///   - bindings: the Buttons pane's bindings (`Options.shared.buttons.binding`).
    ///   - applications: the apps on the list, whose own bindings count while they are in
    ///     front (`ApplicationTriggerRule`).
    ///   - titles: what the Buttons pane calls the triggers of `bindings`, in order.
    init(
        bindings: [ButtonBinding],
        applications: [Application] = [],
        titles: ([RecordedEvent]) -> [String] = { ButtonTriggerNaming.titles(for: $0) }
    ) {
        let rule = ApplicationTriggerRule.shortcutRing
        var names: [String] = []
        for (binding, name) in zip(bindings, titles(bindings.map(\.triggerEvent))) where rule.takes(binding) {
            if !names.contains(name) {
                names.append(name)
            }
        }
        triggerTitles = names
        let onlyInApps = ApplicationTriggers(rule.onlyInApps(general: bindings, applications: applications), titles: titles)
        self.onlyInApps = onlyInApps
        picture = TriggerPictureSource.make(rule: rule, general: bindings, onlyInApps: onlyInApps)
    }

    /// The explanation of the pane's first row: the buttons and keys, joined as a list; or
    /// in which apps only and with what ("Only in Figma: Thumb panel."); or that there is
    /// none yet; and, either way, that a key combination works too (but for the apps' line,
    /// also one that Logi Options+ sends for a button).
    var explanation: String {
        if hasTrigger {
            let triggers = ListFormatter.localizedString(byJoining: triggerTitles)
            return String(format: NSLocalizedString("ring-trigger-bound", comment: ""), triggers)
        }
        if let onlyInApps {
            // (Shorter after it: the apps and their buttons take room of their own.)
            return String(format: NSLocalizedString("ring-trigger-apps", comment: ""), onlyInApps.text)
        }
        return NSLocalizedString("ring-trigger-none", comment: "")
    }

    static var current: ShortcutRingBindingSummary {
        return ShortcutRingBindingSummary(
            bindings: Options.shared.buttons.binding, applications: ApplicationTriggerRule.storedApplications
        )
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
        ShortcutRingArtwork.draw(face, lit: lit, centre: CGPoint(x: bounds.midX, y: bounds.midY), style: style)
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
        static let header = NSUserInterfaceItemIdentifier("ring-header")
        static let triggerPicture = NSUserInterfaceItemIdentifier("ring-trigger-picture")
        static let preview = NSUserInterfaceItemIdentifier("ring-preview")
        static let triggerButton = NSUserInterfaceItemIdentifier("ring-trigger-button")
        static let freezePointer = NSUserInterfaceItemIdentifier("ring-freeze-pointer")
        static let placesHint = NSUserInterfaceItemIdentifier("ring-places-hint")
        static let places = NSUserInterfaceItemIdentifier("ring-places")
        static let reset = NSUserInterfaceItemIdentifier("ring-reset")

        static func action(_ place: Int) -> NSUserInterfaceItemIdentifier {
            return NSUserInterfaceItemIdentifier("ring-place-\(place)")
        }
    }

    // MARK: - State

    /// The app whose own ring the rows edit, on that app's page under Apps; nil in the
    /// pane, which edits the general ring.
    let application: Application?

    /// The ring the drawing and the rows show: the general one, or the app's own as it
    /// opens (its eight places and its freeze switch).
    private var shownRing: ShortcutRingSettings {
        let general = Options.shared.ring
        return application?.ringThatOpens(general: general) ?? general
    }

    /// What opens the ring; tests and pictures replace it with fixtures.
    var bindingSummary: () -> ShortcutRingBindingSummary = { .current }
    /// What the pane shows of it now: "Set Up…" and "Change" do what the row says.
    private var shownSummary: ShortcutRingBindingSummary?
    /// "Set Up…" or "Change": shows the Buttons pane and, with nothing that opens the ring
    /// yet (true), records a button or key that gets the Shortcut Ring; with one (false),
    /// selects its row there. Tests replace it.
    var openButtonsPane: ((Bool) -> Void)?
    /// "Change" while only an app's own button or key opens the ring: shows that app's
    /// Buttons part, its row selected. Tests replace it.
    var openApplicationButtons: ((ApplicationTriggers) -> Void)?
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
    /// Takes Undo and Redo of "Reset to Defaults"; the window's when nil.
    var paneUndoManager: UndoManager?
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

    /// The ring card: in the pane the right one of the header, on an app's page across the
    /// whole width.
    private(set) var previewView: ShortcutRingPreviewView!
    /// The two cards; nil on an app's page.
    private(set) var headerView: ShortcutRingHeaderView?
    /// The button or key that opens the ring, drawn; nil on an app's page.
    var triggerCard: ShortcutRingTriggerCard? {
        return headerView?.triggerCard
    }
    private(set) var triggerRow: PreferencesGroupRow!
    private(set) var triggerButton: NSButton!
    /// "Freeze pointer while the ring is held" and its switch (the app's own on its page).
    private(set) var freezeRow: PreferencesGroupRow!
    private(set) var freezeToggle: NSControl!
    /// Top, Top right … Top left.
    private(set) var placeRows: [PreferencesGroupRow] = []
    private(set) var placePopUps: [ButtonActionPullDown] = []
    private(set) var placesHintLabel: NSTextField!
    /// "Shortcuts": the line on how to choose and the eight rows, folded while nothing
    /// opens the ring; nil on an app's page.
    private(set) var placesSection: PreferencesDisclosureSection?
    /// "Reset to Defaults" under the boxes: the places and the freeze switch of a new ring.
    /// Not what opens the ring.
    private(set) var resetToDefaults: PreferencesPaneReset!
    var resetToDefaultsButton: NSButton {
        return resetToDefaults.button
    }
    /// Everything in the content stack, top to bottom.
    private(set) var sections: [NSView] = []

    // MARK: - Lifecycle

    /// - Parameter application: an app whose own ring is in use ("Use the general ring"
    ///   off), for its page; nil for the pane.
    init(application: Application? = nil) {
        self.application = application
        super.init(nibName: nil, bundle: nil)
        title = NSLocalizedString("ring-tab-title", comment: "")
    }

    required init?(coder: NSCoder) {
        application = nil
        super.init(coder: coder)
        title = NSLocalizedString("ring-tab-title", comment: "")
    }

    override func loadView() {
        let root = PreferencesForm.makeBackground()
        let content = PreferencesGroupedForm.installContentStack(in: root, paneWidth: Self.paneWidth)
        content.setHuggingPriority(.defaultHigh, for: .vertical)

        let preview = ShortcutRingPreviewView()
        preview.identifier = Identifier.preview
        preview.onPlaceHovered = { [weak self] in self?.placePointedAt($0) }
        preview.onPlaceClicked = { [weak self] in self?.selectPlace($0) }
        previewView = preview

        let width = Self.boxWidth
        placePopUps = (0..<ShortcutRingSettings.placeCount).map { makePopUp(for: $0) }
        placeRows = (0..<ShortcutRingSettings.placeCount).map { makePlaceRow($0) }
        if application != nil {
            // An app's own ring: the drawing across the width, its freeze switch and the
            // eight rows, in the pane's order; nothing of what opens the ring.
            preview.translatesAutoresizingMaskIntoConstraints = false
            preview.heightAnchor.constraint(equalToConstant: ShortcutRingPreviewView.preferredHeight).isActive = true
            sections = [
                preview, PreferencesGroupBox(width: width, rows: [makeFreezeRow()]), PreferencesGroupBox(width: width, rows: placeRows),
            ]
            PreferencesGroupedForm.add(sections, to: content)
        } else {
            // What opens the ring beside the ring.
            let header = ShortcutRingHeaderView(ringCard: preview)
            header.identifier = Identifier.header
            header.triggerCard.identifier = Identifier.triggerPicture
            header.translatesAutoresizingMaskIntoConstraints = false
            header.heightAnchor.constraint(equalToConstant: ShortcutRingHeaderView.preferredHeight).isActive = true
            headerView = header
            let trigger = PreferencesGroupSection(width: width, rows: [makeTriggerRow(), makeFreezeRow()])
            let places = makePlacesSection(rows: placeRows)
            places.onExpandedChange = { [weak self] _ in
                guard let self else { return }
                PreferencesForm.fitToContent(self)
            }
            placesSection = places
            resetToDefaults = makeReset()

            sections = [header, trigger, places, PreferencesGroupFooter(trailing: [resetToDefaults.button])]
            PreferencesGroupedForm.add(sections, to: content)
            content.setCustomSpacing(PreferencesGroupedForm.sectionSpacing, after: trigger)
        }

        view = root
        reload()
        root.setFrameSize(root.fittingSize)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard application == nil else { return }
        // Edit › Undo or Redo of a change in Buttons or an app's Buttons part can change
        // what opens the ring while the pane shows.
        for name in [Notification.Name.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange] {
            NotificationCenter.default.addObserver(self, selector: #selector(undoDidRun(_:)), name: name, object: nil)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        // A button may have been bound under Buttons meanwhile, or a file imported.
        reload()
    }

    /// An Undo or Redo ran: the pane on screen shows what opens the ring now, when that
    /// changed (an Undo of typing elsewhere changes nothing here).
    @objc private func undoDidRun(_ notification: Notification) {
        guard isViewLoaded, view.window != nil, bindingSummary() != shownSummary else { return }
        reload()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // The picture shows once what opens the ring.
        triggerCard?.pulse()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        hoveredPlace = nil
        pointedPlace = nil
        selectedPlace = nil
        showLitPlace()
        // A recording that still waits for a key, and the popover, go with the pane.
        endEditing()
        resetToDefaults?.endUndoOffer()
    }

    /// Ends a recording that still waits for a key and closes "Open App or File": the
    /// rows are about to go (the pane is left, or an app's page takes its ring away).
    func endEditing() {
        placePopUps.forEach { $0.cancelShortcutRecording() }
        openTargetPopover?.hide()
        openTargetPopover = nil
    }

    // MARK: - Refresh

    /// Puts the stored ring and what opens it into the rows and the drawing.
    func reload() {
        guard isViewLoaded, previewView != nil else { return }
        let ring = shownRing
        if application == nil {
            let summary = bindingSummary()
            shownSummary = summary
            triggerRow.explanation = summary.explanation
            triggerCard?.source = summary.picture
            // (Opened only by an app's own button: "Change" leads to it, not "Set Up…".)
            let opens = summary.hasTrigger || summary.onlyInApps != nil
            triggerButton.title = text(opens ? "ring-trigger-change" : "ring-trigger-set-up")
            // Nothing opens this ring (nothing at all, or only apps that open their own):
            // its places wait, folded, a click away.
            let opensThisRing = summary.hasTrigger || summary.onlyInApps?.usesGeneralSettings == true
            placesSection?.isCollapsible = !opensThisRing
        }
        (freezeToggle as? NSSwitch)?.state = ring.freezePointer ? .on : .off
        for (place, popUp) in placePopUps.enumerated() {
            // (A place that runs nothing shows "No Action", as the ring shows a dot.)
            popUp.configure(with: ring[place].asBinding(id: placeIDs[place]))
        }
        previewView.face = ShortcutRingFace(ring)
        // The ring on screen shows this face too: it is made here, not at a press.
        ShortcutRingController.prepare(previewView.face, for: ring)
        showLitPlace()
        resetToDefaults?.settingsDidChange()
        // (On an app's page the rows never change their height, and the page sizes itself.)
        if application == nil {
            PreferencesForm.fitToContent(self)
        }
    }

    // MARK: - The row under the pointer

    private static let hoverPlaceInfo = "ringPlace"
    private static let hoverTriggerInfo = "ringTrigger"

    private static func place(of event: NSEvent) -> Int? {
        return event.trackingArea?.userInfo?[hoverPlaceInfo] as? Int
    }

    /// The pointer entered the "Button or key" row: the picture presses once (at most
    /// every 1.5 s, `ShortcutRingTriggerCard.pulse`).
    func triggerRowEntered() {
        triggerCard?.pulse()
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
    /// Folded places open first.
    func selectPlace(_ place: Int) {
        guard placePopUps.indices.contains(place) else { return }
        if let placesSection, !placesSection.showsBody {
            placesSection.setExpanded(true, animated: true)
            PreferencesForm.fitToContent(self)
            view.layoutSubtreeIfNeeded()
        }
        selectedPlace = place
        showLitPlace()
        let popUp = placePopUps[place]
        popUp.scrollToVisible(popUp.bounds)
        view.window?.makeFirstResponder(popUp)
    }

    override func mouseEntered(with event: NSEvent) {
        if event.trackingArea?.userInfo?[Self.hoverTriggerInfo] != nil {
            return triggerRowEntered()
        }
        guard let place = Self.place(of: event) else { return super.mouseEntered(with: event) }
        placeHoverChanged(place, inside: true)
    }

    override func mouseExited(with event: NSEvent) {
        guard let place = Self.place(of: event) else { return super.mouseExited(with: event) }
        placeHoverChanged(place, inside: false)
    }

    // MARK: - Actions

    @objc func triggerButtonClicked(_ sender: NSButton) {
        // (What the row says, which an Undo keeps up to date.)
        let summary = shownSummary ?? bindingSummary()
        if !summary.hasTrigger, let apps = summary.onlyInApps {
            if let openApplicationButtons {
                openApplicationButtons(apps)
            } else {
                PreferencesApplicationViewController.showButtons(of: apps, from: self)
            }
            return
        }
        let addsTrigger = !summary.hasTrigger
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

    @objc func freezeToggled(_ sender: NSControl) {
        let freezes = (sender as? NSSwitch)?.state == .on
        guard shownRing.freezePointer != freezes else { return }
        if let application {
            // The app's own ring's switch from now on; the general ring's stays as it is.
            application.setOwnRingFreezePointer(freezes)
        } else {
            Options.shared.ring.freezePointer = freezes
        }
        // The face made for the ring on screen is kept for the ring as it is stored now.
        reload()
        onPlaceChange?()
    }

    /// Puts `new` into `place`. What a place cannot hold (a recorded mouse button, a
    /// modifier key by itself) is not stored: the pull-down shows again what was there.
    func setPlace(_ new: ShortcutRingPlace, at place: Int) {
        guard placePopUps.indices.contains(place) else { return }
        // The row whose pull-down was used is the selected one.
        selectedPlace = place
        var ring = shownRing
        guard new.isEmpty || new.runs, ring[place] != new else {
            reload()
            return
        }
        if let application {
            // The app's own ring and nothing else; the general ring stays as it is.
            guard application.ownRingPlaces != nil else { return }
            application.ring?[place] = new
        } else {
            ring[place] = new
            Options.shared.ring = ring
        }
        reload()
        onPlaceChange?()
    }

    /// A row changed a place or the freeze switch (the app's page: its "Reset to Defaults"
    /// follows).
    var onPlaceChange: (() -> Void)?

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
        presentOpenTarget(popover, placePopUps[place], shownRing[place].openTarget)
    }

    // MARK: - Reset

    /// Where a reset registers its Undo: the window's undo manager while the pane is in
    /// the window.
    var undoTarget: UndoManager? {
        return paneUndoManager ?? view.window?.undoManager
    }

    /// "Reset to Defaults": the ring of a new installation, its eight places and "Freeze
    /// pointer while the ring is held" off. The button or key that opens the ring is a
    /// binding of the Buttons pane and is not touched. Edit › Undo ("Undo Reset Shortcut
    /// Ring") brings back the ring that was there.
    private func makeReset() -> PreferencesPaneReset {
        let reset = PreferencesPaneReset(
            store: PreferencesPaneReset.Store(
                defaults: ShortcutRingSettings.default,
                read: { Options.shared.ring },
                write: { Options.shared.ring = $0 },
                undoActionNameKey: "ring-undo-reset"
            ),
            undoManager: { [weak self] in self?.undoTarget },
            didChange: { [weak self] in self?.reload() }
        )
        reset.willReset = { [weak self] in self?.endEditing() }
        reset.button.identifier = Identifier.reset
        return reset
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
        // Pointed at, the picture above shows what it names.
        row.addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: [Self.hoverTriggerInfo: true]
        ))
        triggerRow = row
        return row
    }

    /// "Freeze pointer while the ring is held": the ring's own switch, as Gestures has one
    /// for a gesture. Off for a new ring; an app's own ring starts with the general one's.
    private func makeFreezeRow() -> PreferencesGroupRow {
        let toggle = PreferencesGroupedForm.makeSwitch(target: self, action: #selector(freezeToggled(_:)))
        toggle.identifier = Identifier.freezePointer
        freezeToggle = toggle
        let row = PreferencesGroupRow(
            title: text("ring-freeze-pointer"),
            explanation: text("ring-freeze-pointer-hint"),
            accessory: toggle
        )
        freezeRow = row
        return row
    }

    private func makePopUp(for place: Int) -> ButtonActionPullDown {
        let popUp = ButtonActionPullDown(
            binding: shownRing[place].asBinding(id: placeIDs[place]), forRingPlace: true
        )
        popUp.tag = place
        popUp.identifier = Identifier.action(place)
        popUp.setAccessibilityLabel(ShortcutRingPlaceName.localized(place))
        popUp.startShortcutRecorder = startShortcutRecorder
        popUp.onShortcutSelected = { [weak self] shortcut in
            self?.setPlace(ShortcutRingPlace(action: shortcut?.identifier ?? ""), at: place)
        }
        popUp.onCustomShortcutRecorded = { [weak self] name, label in
            self?.setPlace(ShortcutRingPlace(action: name, label: label), at: place)
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

    /// "Shortcuts": its title, one line on the two ways to choose, and the box of rows. The
    /// title folds the line and the box while nothing opens the ring (`reload`).
    private func makePlacesSection(rows: [PreferencesGroupRow]) -> PreferencesDisclosureSection {
        let inset = PreferencesGroupedForm.rowHorizontalInset
        let hint = Self.makeNote(text("ring-places-hint"), identifier: Identifier.placesHint)
        placesHintLabel = hint
        let box = PreferencesGroupBox(width: Self.boxWidth, rows: rows)

        let body = NSView()
        body.translatesAutoresizingMaskIntoConstraints = false
        for view in [hint, box] as [NSView] {
            body.addSubview(view)
        }
        NSLayoutConstraint.activate([
            hint.topAnchor.constraint(equalTo: body.topAnchor),
            hint.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: inset),
            hint.trailingAnchor.constraint(lessThanOrEqualTo: body.trailingAnchor, constant: -inset),
            box.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: PreferencesGroupedForm.sectionTitleSpacing + 2),
            box.leadingAnchor.constraint(equalTo: body.leadingAnchor),
            box.trailingAnchor.constraint(equalTo: body.trailingAnchor),
            box.bottomAnchor.constraint(equalTo: body.bottomAnchor),
        ])
        let section = PreferencesDisclosureSection(
            title: text("ring-places-header"), body: body, spacing: PreferencesGroupedForm.explanationSpacing
        )
        section.identifier = Identifier.places
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
