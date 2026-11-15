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
//  the row under the pointer is lit in the drawing, a place under the pointer is lit too.
//  The drawing is an editor as well: a click on a drop opens that place's own menu under
//  the drop (the row's menu itself; what it opens, the recorder, the name and icon and
//  "Open App or File…", stands at the drop; nothing scrolls, unfolds or takes the
//  keyboard, and the place stays lit), and a secondary click offers "Swap With" and
//  "Clear" (`RingPlaceMenu`). "Swap With" also ends every place's own menu: the way of
//  the keyboard and of VoiceOver, to which the drawing is one image. Then a box
//  with what opens the ring: which button or key runs the Shortcut Ring is a binding of
//  the Buttons pane, and the row names it and chooses it in place, as the Gestures pane does
//  for its button: its pull-down (`TriggerChooser`) lists the connected mouse's buttons
//  with what each does now, "Record a Button or Key…" and "Show in Buttons" (the Buttons
//  pane with its row selected), and a choice writes the binding Buttons would, with Undo;
//  while only an app's own button or key opens it, the row says where ("Only in Figma:
//  Thumb panel.") and "Show in Figma › Buttons" shows that app's Buttons part
//  (`ApplicationTriggerRule`). With one button or key chosen the row says what to do with
//  it ("Hold it, move towards a shortcut and let go."); its explanation also says that a
//  key combination works, where that adds something (not when a key opens it).
//  Then the eight places, clockwise from the top, each with the pull-down a row of the
//  Buttons pane has
//  (`ButtonActionPullDown`, with the menu of what a place can hold): a listed action, a
//  key combination recorded there ("Keyboard Shortcut…") or an app, a file or a script
//  ("Open App or File…", the Buttons pane's popover). While nothing opens the ring (no
//  binding of Buttons, no app's own, or only apps that open their own ring: "Only in
//  Figma, with its own ring: Thumb panel."), the places are folded under their title
//  ("Shortcuts ›", `PreferencesDisclosureSection`): a click opens them and they can be
//  edited as ever (a click on a place of the drawing edits it and leaves them folded); once
//  something opens the ring they show by themselves, with a plain title. Under the boxes "Reset to
//  Defaults", as in the Scrolling pane (`PreferencesPaneReset`): the eight places and the
//  freeze switch of a new ring; what opens the ring is a binding of Buttons and stays.
//
//  The pane only edits Options.shared.ring.
//
//  An app's page under Apps shows the same drawing of the ring, across the whole width and
//  with the app's icon faint in its middle while nothing is lit (as the app's own ring shows
//  it on screen; the pane's middle stays empty), the same freeze switch and the same eight rows under "Shortcuts" (which the app's part folds
//  while nothing opens the ring with the app in front), in the pane's order, for the app's own ring
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

    /// The explanation of the pane's first row: with one button or key (which the pull-down
    /// names), what to do with it; with more, the buttons and keys, joined as a list; or
    /// in which apps only and with what ("Only in Figma: Thumb panel."); or that there is
    /// none yet; and that a key combination works too (but for the apps' line, also one
    /// that Logi Options+ sends for a button), except while a key opens it.
    var explanation: String {
        return explanation(fittingTwoLinesOf: nil)
    }

    /// The same for a line `width` wide (the row's, beside its pull-down as it is titled),
    /// which takes two lines at most: beside a long name ("Gesture button (button 6)",
    /// "Pointer speed button") the line says what to do and leaves out that a key
    /// combination works too. nil: the width is not known, nothing is left out.
    func explanation(fittingTwoLinesOf width: CGFloat?) -> String {
        if triggerTitles.count == 1 {
            let isKey = picture.onlyInAppPath == nil && picture.event?.type == .keyboard
            let whatToDo = NSLocalizedString("ring-trigger-one-key", comment: "")
            let withKeys = NSLocalizedString("ring-trigger-one", comment: "")
            return isKey || !Self.fitsTwoLines(withKeys, width: width) ? whatToDo : withKeys
        }
        if hasTrigger {
            let triggers = InterfaceList.joined(triggerTitles)
            return String(format: NSLocalizedString("ring-trigger-bound", comment: ""), triggers)
        }
        if let onlyInApps {
            // (Shorter after it: the apps and their buttons take room of their own.)
            return String(format: NSLocalizedString("ring-trigger-apps", comment: ""), onlyInApps.text)
        }
        return NSLocalizedString("ring-trigger-none", comment: "")
    }

    /// Whether `text` takes two lines at most `width` wide in the explanations' font, as
    /// the row lays it out (true while the width is not known).
    static func fitsTwoLines(_ text: String, width: CGFloat?) -> Bool {
        guard let width, width > 0 else { return true }
        return ApplicationPagePart.LineCount(width: width, font: PreferencesGroupedForm.explanationFont).of(text) <= 2
    }

    static var current: ShortcutRingBindingSummary {
        return ShortcutRingBindingSummary(
            bindings: Options.shared.buttons.binding, applications: ApplicationTriggerRule.storedApplications
        )
    }
}

/// The ring on a card, as it opens at the pointer. A place can be pointed at and clicked,
/// with either button. To VoiceOver it is one image: the rows hold what the drops open.
final class ShortcutRingPreviewView: NSView {

    /// The pointer is over this place of the drawing, or over none (nil).
    var onPlaceHovered: ((Int?) -> Void)?
    /// A place of the drawing was clicked.
    var onPlaceClicked: ((Int) -> Void)?
    /// The menu of a secondary click on a place (the right button, two fingers, a
    /// Control-click); nil shows none.
    var menuForPlace: ((Int) -> NSMenu?)?
    /// Shows that menu for a Control-click that arrives as a click. The menu runs until it
    /// closes, so tests replace it.
    var presentContextMenu: (NSMenu, NSEvent, NSView) -> Void = { menu, event, view in
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    /// Stands over a drop, for a popover to stand at. Flipped, as a pull-down is: a popover
    /// that asks for `.maxY` stands under it. It draws nothing, takes no click and is
    /// nothing to VoiceOver.
    private final class DropAnchor: NSView {
        override var isFlipped: Bool { return true }
        override func hitTest(_ point: NSPoint) -> NSView? { return nil }
    }

    /// One per place, made when first asked for (`anchor(forPlace:)`).
    private var dropAnchors: [Int: DropAnchor] = [:]

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
    /// An app's own ring (on its page): the app's icon in the middle while nothing is lit,
    /// as the ring shows it on screen. Nil in the pane: the general ring's middle is empty.
    var appIcon: NSImage? {
        didSet {
            guard appIcon !== oldValue else { return }
            needsDisplay = true
        }
    }
    /// "Reduce transparency", under which the app's icon is not faint. Tests replace it.
    var reducesTransparency: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency }

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
        // A Control-click that arrives as a click is the secondary click all the same.
        if event.modifierFlags.contains(.control) {
            if let menu = menuForPlace?(place) {
                presentContextMenu(menu, event, self)
            }
            return
        }
        onPlaceClicked?(place)
    }

    /// The secondary click: the menu of the place under it. None in the ring's middle (an
    /// app's icon there is no target) and beside the ring.
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let place = place(at: convert(event.locationInWindow, from: nil)) else { return nil }
        return menuForPlace?(place)
    }

    /// The drop of `place` as it rests, in this view (an empty place's drop is drawn
    /// smaller and a lit one larger and further out: their menus stand in the same spot).
    func dropRect(ofPlace place: Int) -> NSRect {
        // The geometry is the screen's: unscaled, and with y growing downwards.
        let offset = ShortcutRingGeometry.offset(ofPlace: place)
        let side = ShortcutRingGeometry.placeDiameter * Self.ringScale
        let centre = NSPoint(x: bounds.midX + offset.x * Self.ringScale, y: bounds.midY - offset.y * Self.ringScale)
        return NSRect(x: centre.x - side / 2, y: centre.y - side / 2, width: side, height: side)
    }

    /// The view over the drop of `place` that a popover stands at. Each place has its own,
    /// as each row has its pull-down: a popover left open at one place stays there while
    /// another place is edited.
    func anchor(forPlace place: Int) -> NSView {
        let anchor = dropAnchors[place] ?? DropAnchor()
        if anchor.superview !== self {
            dropAnchors[place] = anchor
            addSubview(anchor)
        }
        anchor.frame = dropRect(ofPlace: place)
        return anchor
    }

    override func layout() {
        super.layout()
        for (place, anchor) in dropAnchors {
            anchor.frame = dropRect(ofPlace: place)
        }
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
        style.reducesTransparency = appIcon != nil && reducesTransparency()
        ShortcutRingArtwork.draw(
            face, lit: lit, centre: CGPoint(x: bounds.midX, y: bounds.midY), style: style, appIcon: appIcon
        )
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
    /// What the pane shows of it now: "Show in Buttons" goes where the row says.
    private var shownSummary: ShortcutRingBindingSummary?
    /// The ring the rows and the drawing show now (an Undo reloads them when it differs).
    private var shownStoredRing: ShortcutRingSettings?
    /// "Show in Buttons": shows the Buttons pane, with the row of what opens the ring
    /// selected when something does. Tests replace it.
    var openButtonsPane: (() -> Void)?
    /// "Show in Buttons" while only an app's own button or key opens the ring: shows that
    /// app's Buttons part, its row selected. Tests replace it.
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
    /// On an app's page: the app's mark (its icon for the drawing's middle) with its look
    /// on disk, when the ring on screen has none made yet. Tests replace it.
    var makeAppMark: (String) -> ShortcutRingAppMark = { ShortcutRingAppMark.make(forPath: $0) }
    /// "Open App or File" while it is open for a place.
    private(set) var openTargetPopover: OpenTargetConfigPopover?
    /// The pull-downs' stand-in bindings keep their identity while the pane lives.
    private let placeIDs = (0..<ShortcutRingSettings.placeCount).map { _ in UUID() }

    /// The place of the row under the pointer.
    private(set) var hoveredPlace: Int?
    /// The place under the pointer in the drawing.
    private(set) var pointedPlace: Int?
    /// The place that was clicked in the drawing (with either button), or whose pull-down
    /// was last used: its row is the selected one.
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
    /// "Button or key"'s pull-down, and what it does; nil on an app's page.
    private(set) var triggerChooser: TriggerChooser?
    var triggerButton: TriggerChoicePullDown! {
        return triggerChooser?.pullDown
    }
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
        preview.onPlaceClicked = { [weak self] in self?.openMenu(forPlace: $0) }
        preview.menuForPlace = { [weak self] in self?.contextMenu(forPlace: $0) }
        previewView = preview

        let width = Self.boxWidth
        placePopUps = (0..<ShortcutRingSettings.placeCount).map { makePopUp(for: $0) }
        placeRows = (0..<ShortcutRingSettings.placeCount).map { makePlaceRow($0) }
        if application != nil {
            // An app's own ring: the drawing across the width, its freeze switch and the
            // eight rows under "Shortcuts", in the pane's order; nothing of what opens the
            // ring. (The app's part folds the rows while nothing opens the ring there.)
            preview.translatesAutoresizingMaskIntoConstraints = false
            preview.heightAnchor.constraint(equalToConstant: ShortcutRingPreviewView.preferredHeight).isActive = true
            let places = makePlacesSection(rows: placeRows, hint: false)
            placesSection = places
            sections = [preview, PreferencesGroupBox(width: width, rows: [makeFreezeRow()]), places]
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
        if application == nil { DifferentInAppsLine.add(to: content, part: .ring, pane: self, showsIcons: true) }
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

    /// An Undo or Redo ran: the pane on screen shows what opens the ring now and its
    /// places, when either changed (an Undo of typing elsewhere changes nothing here).
    @objc private func undoDidRun(_ notification: Notification) {
        guard isViewLoaded, view.window != nil,
              bindingSummary() != shownSummary || shownRing != shownStoredRing else { return }
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
        triggerChooser?.endEditing()
        resetToDefaults?.endUndoOffer()
    }

    /// Ends a recording that still waits for a key and closes "Open App or File": the
    /// rows are about to go (the pane is left, or an app's page takes its ring away).
    func endEditing() {
        isEndingEditing = true
        defer { isEndingEditing = false }
        placePopUps.forEach { $0.cancelShortcutRecording() }
        openTargetPopover?.hide()
        openTargetPopover = nil
    }

    /// While `endEditing` runs: what it stores (a name typed and not confirmed) takes no
    /// Undo of its own. What ended the editing ("Reset to Defaults") takes it back with the
    /// rest, the name included.
    private var isEndingEditing = false

    // MARK: - Refresh

    /// Puts the stored ring and what opens it into the rows and the drawing.
    func reload() {
        guard isViewLoaded, previewView != nil else { return }
        let ring = shownRing
        shownStoredRing = ring
        if application == nil {
            let summary = bindingSummary()
            shownSummary = summary
            triggerCard?.source = summary.picture
            // The pull-down names what the row names first, and offers the mouse's buttons;
            // "Show in Buttons" says where it goes (`showInButtons`).
            triggerChooser?.update(
                triggerTitles: summary.triggerTitles,
                showsInApplication: summary.hasTrigger ? nil : summary.onlyInApps?.applicationNames.first
            )
            // (After the pull-down has its title: the line is as wide as that leaves it.)
            triggerRow.explanation = summary.explanation(fittingTwoLinesOf: triggerLineWidth)
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
        previewView.appIcon = appMarkOfOwnRing()?.icon
        showLitPlace()
        resetToDefaults?.settingsDidChange()
        // (On an app's page the rows never change their height, and the page sizes itself.)
        if application == nil {
            PreferencesForm.fitToContent(self)
        }
    }

    /// A text of two lines at any width, for the room a row keeps (`reservedExplanations`).
    private static let twoLines = "A\nA"

    /// The room of the first row's line: the box's width without the row's margins, the
    /// pull-down as it is titled now and the space before it (`PreferencesGroupRow.titleColumnWidth`,
    /// which follows only at the next layout).
    private var triggerLineWidth: CGFloat {
        let row = Self.boxWidth - 2 * PreferencesGroupedForm.rowHorizontalInset
        guard let pullDown = triggerChooser?.pullDown else { return row }
        return row - pullDown.intrinsicContentSize.width - PreferencesGroupedForm.controlSpacing
    }

    /// The app's mark while the drawing is the app's own ring (its page, the app's own ring
    /// in use); nil for the general ring, whose middle stays empty. The one the ring on
    /// screen has, else made here, once, and handed on to the ring on screen when that app's
    /// own ring can open (a page that is only browsed pushes out no other app's mark).
    private func appMarkOfOwnRing() -> ShortcutRingAppMark? {
        guard let application, application.ownRingPlaces != nil else { return nil }
        let path = application.path
        if let prepared = ShortcutRingController.preparedAppMark(forPath: path) {
            madeAppMark = prepared
            return prepared
        }
        if madeAppMark == nil {
            madeAppMark = makeAppMark(path)
        }
        if let made = madeAppMark, ShortcutRingController.appMarksToPrepare().contains(path) {
            ShortcutRingController.prepare(made, forAppAt: path)
        }
        return madeAppMark
    }

    /// The app's mark this page made or found (`appMarkOfOwnRing`).
    private var madeAppMark: ShortcutRingAppMark?

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

    /// An Undo or Redo changed `place`: its row is selected. The row's pull-down takes
    /// the keyboard (Space opens it) and is scrolled into view, and the place stays lit.
    /// Folded places open first.
    func selectPlace(_ place: Int) {
        guard placePopUps.indices.contains(place) else { return }
        if let placesSection, !placesSection.showsBody {
            placesSection.setExpanded(true, animated: true)
            // (The pane refits itself; an app's page measures again.)
            placesSection.onExpandedChange?(true)
            view.layoutSubtreeIfNeeded()
        }
        selectedPlace = place
        showLitPlace()
        let popUp = placePopUps[place]
        popUp.scrollToVisible(popUp.bounds)
        view.window?.makeFirstResponder(popUp)
    }

    // MARK: - The drawing as an editor

    /// Shows a place's menu at its drop. The menu runs until it closes, so tests replace it.
    var presentPlaceMenu: ((NSMenu, NSPoint, NSView) -> Void)? {
        didSet {
            guard let presentPlaceMenu else { return }
            placePopUps.forEach { $0.presentMenu = presentPlaceMenu }
        }
    }

    /// A place of the drawing was clicked: its row's own menu opens under its drop, and
    /// what the menu opens stands at the drop. The place is the selected one; nothing
    /// scrolls, folded places stay folded and the keyboard stays where it is.
    func openMenu(forPlace place: Int) {
        guard placePopUps.indices.contains(place), let preview = previewView else { return }
        selectedPlace = place
        showLitPlace()
        let drop = preview.dropRect(ofPlace: place)
        placePopUps[place].popUpMenu(
            at: NSPoint(x: drop.minX, y: drop.minY - 4), in: preview, anchor: preview.anchor(forPlace: place)
        )
    }

    /// What "Swap With" and "Clear" offer for `place` of the ring as it is stored now.
    private func placeMenuModel(for place: Int) -> RingPlaceMenuModel {
        return RingPlaceMenuModel.make(for: place, in: shownRing)
    }

    /// The menu of a secondary click on a place of the drawing: "Swap With" and "Clear".
    /// The place is the selected one, as after a click: it stays lit under the menu.
    func contextMenu(forPlace place: Int) -> NSMenu? {
        guard placePopUps.indices.contains(place) else { return nil }
        selectedPlace = place
        showLitPlace()
        return RingPlaceMenu.make(
            placeMenuModel(for: place), target: self, swap: #selector(swapChosen(_:)), clear: #selector(clearChosen(_:))
        )
    }

    @objc func swapChosen(_ sender: NSMenuItem) {
        guard let swap = sender.representedObject as? RingPlaceSwap else { return }
        swapPlace(swap.place, with: swap.other)
    }

    /// "Clear": the place is emptied as "No Action" of its menu empties it.
    @objc func clearChosen(_ sender: NSMenuItem) {
        setPlace(.empty, at: sender.tag)
    }

    /// Exchanges `place` and `other` as they are stored, whole: the action, what it opens,
    /// the name and the icon (an action this version does not run moves as it is). One
    /// write, and one step for Edit › Undo ("Undo Swap"). Nothing happens when the two hold
    /// the same or neither holds anything that runs. `place` is the selected one.
    func swapPlace(_ place: Int, with other: Int) {
        guard placePopUps.indices.contains(place), placePopUps.indices.contains(other), place != other else { return }
        selectedPlace = place
        var ring = shownRing
        let old = [ring[place], ring[other]]
        guard old[0] != old[1], old[0].runs || old[1].runs else {
            reload()
            return
        }
        if let application {
            // The app's own ring and nothing else; the general ring stays as it is.
            guard application.ownRingPlaces != nil, var own = application.ring else { return }
            own[place] = old[1]
            own[other] = old[0]
            application.ring = own
        } else {
            ring[place] = old[1]
            ring[other] = old[0]
            Options.shared.ring = ring
        }
        reload()
        onPlaceChange?()
        guard let undo = undoTarget, undo.groupsByEvent || undo.groupingLevel > 0 else { return }
        let split = PreferencesButtonsViewController.splitViewController(of: self)
        Self.registerSwapUndo(
            back: old, at: [place, other], of: placeOwner, undoManager: undo,
            showing: PlaceShowing(split: split, controller: self)
        )
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

    /// "Show in Buttons": the Buttons pane with the row of what opens the ring selected;
    /// while only an app's own button or key opens it, that app's Buttons part (the item
    /// then says "Show in Figma › Buttons").
    func showInButtons() {
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
        if let openButtonsPane {
            openButtonsPane()
            return
        }
        guard let split = PreferencesButtonsViewController.splitViewController(of: self),
              split.selectPane(withIdentifier: PANEL_IDENTIFIER.buttons) else { return }
        guard summary.hasTrigger,
              let buttons = split.controller(for: PANEL_IDENTIFIER.buttons) as? PreferencesButtonsViewController else { return }
        buttons.selectRingTrigger()
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
    /// Edit › Undo puts back what was there (`registerUndo`).
    func setPlace(_ new: ShortcutRingPlace, at place: Int) {
        guard placePopUps.indices.contains(place) else { return }
        // The row whose pull-down was used is the selected one.
        selectedPlace = place
        var ring = shownRing
        guard new.isEmpty || new.runs, ring[place] != new else {
            reload()
            return
        }
        let old = ring[place]
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
        registerUndo(back: old, from: new, at: place)
    }

    /// A row changed a place or the freeze switch (the app's page: its "Reset to Defaults"
    /// follows).
    var onPlaceChange: (() -> Void)?

    // MARK: - Undo of a place

    /// Whose ring an Undo of a place changes: the general one, or an app's own, found by
    /// the path it is stored with when the Undo runs (an app removed and added again is a
    /// new entry; an own ring kept for later takes it too, as "Reset to Defaults" does).
    private enum PlaceOwner {
        case general
        case application(path: String)
    }

    /// Where an Undo of a place shows what it did: the window's panes; without them (the
    /// pane in no split view) the pane that made the change. Neither is held.
    private struct PlaceShowing {
        weak var split: PreferencesSplitViewController?
        weak var controller: RingPreferencesViewController?
    }

    /// Registers the step back from `new` to `old` in `place`: "Undo Change Action", or
    /// "Undo Rename" when only the name or the icon of the same recorded key combination
    /// changed (as Buttons calls them, `ButtonRowChange.Kind`). The target is the settings,
    /// not this pane: an Undo after an app's page closed still works.
    private func registerUndo(back old: ShortcutRingPlace, from new: ShortcutRingPlace, at place: Int) {
        // (A manager that groups only by hand, as a test's, takes a step only inside a group.)
        guard !isEndingEditing, let undo = undoTarget, undo.groupsByEvent || undo.groupingLevel > 0 else { return }
        let split = PreferencesButtonsViewController.splitViewController(of: self)
        Self.registerUndo(
            back: old, from: new, at: place, of: placeOwner, undoManager: undo,
            showing: PlaceShowing(split: split, controller: self)
        )
    }

    /// Whose ring the rows and the drawing edit.
    private var placeOwner: PlaceOwner {
        return application.map { PlaceOwner.application(path: $0.path) } ?? .general
    }

    /// Registers the step back from a swap: "Undo Swap" puts `old` back into `places`
    /// (the two as they were, whatever happened to the ring since, as a place's Undo puts
    /// back one) and shows the first of them, the place whose menu was used. Its target is
    /// the settings too.
    private static func registerSwapUndo(
        back old: [ShortcutRingPlace], at places: [Int], of owner: PlaceOwner,
        undoManager undo: UndoManager, showing: PlaceShowing
    ) {
        undo.registerUndo(withTarget: Options.shared) { [weak undo] _ in
            guard let place = places.first, let result = put(old, at: places, of: owner) else { return }
            show(place, of: result.entry, in: showing)
            guard let undo, result.was != old else { return }
            registerSwapUndo(back: result.was, at: places, of: owner, undoManager: undo, showing: showing)
        }
        undo.setActionName(NSLocalizedString("ring-undo-swap", comment: ""))
    }

    /// Puts `values` into `places` of the owner's ring, in one write. What was there, and
    /// the app's entry (nil: the general ring); nil when the app is no longer on the list
    /// or has no ring of its own.
    private static func put(
        _ values: [ShortcutRingPlace], at places: [Int], of owner: PlaceOwner
    ) -> (was: [ShortcutRingPlace], entry: Application?)? {
        switch owner {
        case .general:
            var ring = Options.shared.ring
            let was = places.map { ring[$0] }
            for (place, value) in zip(places, values) {
                ring[place] = value
            }
            if ring != Options.shared.ring {
                Options.shared.ring = ring
            }
            return (was, nil)
        case .application(let path):
            guard let entry = PreferencesApplicationViewController.existingApplication(
                forPaths: PreferencesApplicationViewController.knownPaths(forStoredPath: path)
            ), var ring = entry.ring else { return nil }
            let was = places.map { ring[$0] }
            for (place, value) in zip(places, values) {
                ring[place] = value
            }
            if ring != entry.ring {
                entry.ring = ring
            }
            return (was, entry)
        }
    }

    private static func registerUndo(
        back old: ShortcutRingPlace, from new: ShortcutRingPlace, at place: Int, of owner: PlaceOwner,
        undoManager undo: UndoManager, showing: PlaceShowing
    ) {
        undo.registerUndo(withTarget: Options.shared) { [weak undo] _ in
            guard let result = put(old, at: place, of: owner) else { return }
            show(place, of: result.entry, in: showing)
            guard let undo, result.was != old else { return }
            registerUndo(back: result.was, from: old, at: place, of: owner, undoManager: undo, showing: showing)
        }
        let renames = old.action == new.action && old.openTarget == new.openTarget && old.label != new.label
        undo.setActionName((renames ? ButtonRowChange.Kind.rename : .action).actionName)
    }

    /// Puts `value` into `place` of the owner's ring. What was there, and the app's entry
    /// (nil: the general ring); nil when the app is no longer on the list or has no ring
    /// of its own.
    private static func put(
        _ value: ShortcutRingPlace, at place: Int, of owner: PlaceOwner
    ) -> (was: ShortcutRingPlace, entry: Application?)? {
        switch owner {
        case .general:
            let was = Options.shared.ring[place]
            if was != value {
                Options.shared.ring[place] = value
            }
            return (was, nil)
        case .application(let path):
            guard let entry = PreferencesApplicationViewController.existingApplication(
                forPaths: PreferencesApplicationViewController.knownPaths(forStoredPath: path)
            ), let was = entry.ring?[place] else { return nil }
            if was != value {
                entry.ring?[place] = value
            }
            return (was, entry)
        }
    }

    /// Shows the place an Undo or Redo changed where it is: the Shortcut Ring pane, or the
    /// app's page under Apps on its Shortcut Ring part, comes forward and shows the ring as
    /// stored, with the place's row selected (`selectPlace`). Not for an app's ring kept
    /// for later (the app uses the general ring again): its part shows the switch alone,
    /// so nothing there would show the change (the place is back all the same).
    private static func show(_ place: Int, of entry: Application?, in showing: PlaceShowing) {
        if let entry, entry.ownRingPlaces == nil { return }
        if let split = showing.split {
            if let entry {
                let part = split.bringForward(pageOf: entry, part: .ring)?.ringPart
                part?.syncViewWithOptions()
                part?.ringController?.selectPlace(place)
            } else {
                let pane = split.bringForward(pane: tabIdentifier) as? RingPreferencesViewController
                pane?.reload()
                pane?.selectPlace(place)
            }
        } else if let controller = showing.controller, controller.application === entry {
            controller.reload()
            controller.onPlaceChange?()
            controller.selectPlace(place)
        }
    }

    /// "Open App or File…" of a place: the Buttons pane's popover at the pull-down, or at
    /// the place's drop when its menu was opened there, with what the place opens now.
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
        presentOpenTarget(popover, placePopUps[place].popoverAnchor, shownRing[place].openTarget)
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
            comeForward: { [weak self] in self?.comeForward() },
            didChange: { [weak self] in self?.reload() }
        )
        reset.willReset = { [weak self] in self?.endEditing() }
        reset.button.identifier = Identifier.reset
        return reset
    }

    /// An Undo or Redo of a step of the whole pane (its reset, the choice of what opens the
    /// ring) shows where it acts, as one of a place does: the pane comes forward while
    /// another one shows.
    private func comeForward() {
        PreferencesUndoPlace(of: self).bringForward(pane: Self.tabIdentifier)
    }

    // MARK: - Rows

    private func text(_ key: String) -> String {
        return NSLocalizedString(key, comment: "")
    }

    /// "Button or key": what opens the ring, or nothing yet, and the pull-down that
    /// chooses it (`TriggerChooser`): a choice shows at once in the row, the picture and the
    /// places, which no longer fold.
    private func makeTriggerRow() -> PreferencesGroupRow {
        let chooser = TriggerChooser(rule: .shortcutRing)
        chooser.undoManager = { [weak self] in self?.undoTarget }
        chooser.showInButtons = { [weak self] in self?.showInButtons() }
        chooser.didChange = { [weak self] in self?.reload() }
        chooser.comeForward = { [weak self] in self?.comeForward() }
        chooser.pullDown.identifier = Identifier.triggerButton
        triggerChooser = chooser
        let row = PreferencesGroupRow(
            title: text("ring-trigger"),
            explanation: text("ring-trigger-none"),
            accessory: chooser.pullDown
        )
        // Room for two lines whatever the row says, so naming a button does not move the rows.
        // (Two lines as such, not the longest of the row's lines: beside a long name in the
        // pull-down that one would be measured at three, and the row grew with the name.)
        row.reservedExplanations = [Self.twoLines]
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
        if let presentPlaceMenu {
            popUp.presentMenu = presentPlaceMenu
        }
        // "Swap With" ends the place's menu: the keyboard's and VoiceOver's way to it.
        popUp.trailingItem = RingPlaceMenu.swapItem(
            model: { [weak self] in self?.placeMenuModel(for: place) }, target: self, action: #selector(swapChosen(_:))
        )
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
    /// - Parameter hint: the line on how to choose under the title (the pane's; an app's
    ///   page leaves it out).
    private func makePlacesSection(rows: [PreferencesGroupRow], hint withHint: Bool = true) -> PreferencesDisclosureSection {
        let box = PreferencesGroupBox(width: Self.boxWidth, rows: rows)
        guard withHint else {
            let section = PreferencesDisclosureSection(title: text("ring-places-header"), body: box)
            section.identifier = Identifier.places
            return section
        }
        let inset = PreferencesGroupedForm.rowHorizontalInset
        let hint = Self.makeNote(text("ring-places-hint"), identifier: Identifier.placesHint)
        placesHintLabel = hint

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

// MARK: - Where an Undo shows itself

/// An Undo or Redo of a place of the ring (`RingPreferencesViewController`), of a
/// direction of Gesture Navigation (`MouseGestureSettingsControls`) or of a row of Buttons
/// (`PreferencesButtonsViewController.takeBack`) shows where it acts: its pane, or the
/// app's page on its part, comes forward.
extension PreferencesSplitViewController {

    /// The pane `identifier` comes forward, unless it is on show (`selectPane` would take
    /// it back to its top); its controller.
    @discardableResult
    func bringForward(pane identifier: String) -> NSViewController? {
        if selectedPaneIdentifier != identifier {
            selectPane(withIdentifier: identifier)
        }
        return controller(for: identifier)
    }

    /// Apps comes forward with the page of `application` on `part`; nil when the list has
    /// no row for it.
    func bringForward(pageOf application: Application, part: ApplicationPagePart) -> ApplicationDetailViewController? {
        guard let apps = bringForward(pane: PANEL_IDENTIFIER.application) as? PreferencesApplicationViewController,
              let id = apps.rowID(for: application) else { return nil }
        apps.openApplication(withID: id, part: part)
        return apps.detailController
    }
}

/// Where a step of a whole pane or of a whole part of an app's page shows itself when it
/// is undone or redone: a reset, a copy, the choice of the button to hold or of what opens
/// the ring, a pick of "Scrolling in Safari". The pane, or the app's page on that part,
/// comes forward, as for a row's Undo; the step itself, made where it is in sight, moves
/// nothing. Made when the step is registered, from the controller that makes it. The
/// window's panes are not held, and without them (a pane in a window of its own) nothing
/// comes forward.
struct PreferencesUndoPlace {

    private weak var split: PreferencesSplitViewController?

    init(of controller: NSViewController?) {
        split = controller.flatMap { PreferencesButtonsViewController.splitViewController(of: $0) }
    }

    /// The pane `identifier` comes forward, unless it is on show.
    func bringForward(pane identifier: String) {
        split?.bringForward(pane: identifier)
    }

    /// Apps comes forward with the page of `application` on `part`. Not for an entry the
    /// list no longer holds: there is no page to show.
    func bringForward(pageOf application: Application, part: ApplicationPagePart) {
        guard let split, Options.shared.application.applications.get(by: application.path) === application else { return }
        _ = split.bringForward(pageOf: application, part: part)
    }
}
