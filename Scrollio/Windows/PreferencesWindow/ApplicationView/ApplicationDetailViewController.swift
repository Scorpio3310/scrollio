//
//  ApplicationDetailViewController.swift
//  Mos
//  The page of one app under Apps, opened from its row in the list (it replaces the old
//  per-app popover). The way back is the window's: a back button in its title bar, beside
//  the app's name (PreferencesWindowController), as in System Settings; Esc and ⌘[ go back
//  too. A box shows the app (icon, name, where it is), with a muted line under it while
//  "Change scrolling only in these apps" is on (being on the list changes the app's
//  scrolling, whatever it was added for); under it a segmented control
//  chooses the part of the page that shows (`ApplicationPagePart`: Scrolling, Buttons,
//  Gestures, Shortcut Ring), one at a time, so the page stays short. The part shown last is shown
//  again, for every app alike (the UI state, beside Advanced of Scrolling); a part that
//  does not exist falls back to Scrolling, and a mark of the list opens its own part.
//
//  The page only edits the app it was opened for: `inherit` and its scroll options, its
//  own buttons, its `gestures` and its `ring`. The Apps pane puts the page in place of the list and takes
//  it away again; the page tells it when its height changed (the part, or the part's
//  content).
//

import Cocoa

final class ApplicationDetailViewController: NSViewController {

    /// Identifiers for the controls (tests and accessibility tooling).
    enum Identifier {
        static let header = NSUserInterfaceItemIdentifier("apps-detail-header")
        static let allowlistNote = NSUserInterfaceItemIdentifier("apps-detail-allowlist-note")
        static let parts = NSUserInterfaceItemIdentifier("apps-detail-parts")
        static let inherit = ApplicationScrollingPartViewController.Identifier.inherit
        static let generalRing = ApplicationRingPartViewController.Identifier.generalRing
        static let generalGestures = ApplicationGesturesPartViewController.Identifier.generalGestures
    }

    /// As wide as the Scrolling settings under the header.
    static let paneWidth: CGFloat = PreferencesScrollingViewController.paneWidth

    let application: Application
    private let uiStateDefaults: UserDefaults
    /// The parts of the page, in the order of the control.
    let parts: [ApplicationPagePart]

    /// Esc or ⌘[ asked to go back to the list.
    var onBack: (() -> Void)?
    /// The app's own settings changed in a way the list shows (its line, its marks). The
    /// Buttons part gets it as it is (an Undo there outlives the page).
    var onInheritChange: (() -> Void)? {
        didSet { buttonsPart?.onOwnButtonsChange = onInheritChange }
    }
    /// The pane's answer to which Buttons part shows an app's entry now; the Buttons part
    /// gets it as it is (an Undo there outlives the page).
    var buttonsPartShowing: ((Application) -> ApplicationButtonsViewController?)? {
        didSet { buttonsPart?.partShowing = buttonsPartShowing }
    }
    /// The same for the Shortcut Ring part and the Gestures part ("Reset to Defaults" has
    /// an Undo; so has the Buttons part's).
    var ringPartShowing: ((Application) -> ApplicationRingPartViewController?)? {
        didSet { ringPart?.partShowing = ringPartShowing }
    }
    var gesturesPartShowing: ((Application) -> ApplicationGesturesPartViewController?)? {
        didSet { gesturesPart?.partShowing = gesturesPartShowing }
    }
    /// The page's height changed: another part, the settings loaded, "Advanced" opened or
    /// closed, a row came or went.
    var onHeightChange: (() -> Void)?

    // MARK: - Views (read access for tests)

    private(set) var headerRow: ApplicationDetailHeaderRow!
    private(set) var headerSection: PreferencesGroupSection!
    /// Under the app's box while "Change scrolling only in these apps" is on: being on the
    /// list changes how the app scrolls, also for an app added only for its buttons,
    /// gestures or ring.
    private(set) var allowlistNote: NSTextField!
    private var controlUnderHeader: NSLayoutConstraint!
    private var controlUnderNote: NSLayoutConstraint!
    private(set) var partControl: NSSegmentedControl!
    /// Holds the view of the part shown.
    private(set) var partContainer: NSView!
    private(set) var shownPart: ApplicationPagePart
    /// Each part's controller, by the part's id: made with the page.
    private(set) var partControllers: [String: ApplicationPagePartController] = [:]

    var scrollingPart: ApplicationScrollingPartViewController! {
        return partControllers[ApplicationPagePart.scrolling.id] as? ApplicationScrollingPartViewController
    }
    var buttonsPart: ApplicationButtonsViewController! {
        return partControllers[ApplicationPagePart.buttons.id] as? ApplicationButtonsViewController
    }
    var ringPart: ApplicationRingPartViewController! {
        return partControllers[ApplicationPagePart.ring.id] as? ApplicationRingPartViewController
    }
    var gesturesPart: ApplicationGesturesPartViewController! {
        return partControllers[ApplicationPagePart.gestures.id] as? ApplicationGesturesPartViewController
    }
    var inheritRow: PreferencesSwitchRow! { return scrollingPart.inheritRow }
    var inheritSwitch: NSSwitch { return inheritRow.toggle }
    var scrollingController: PreferencesScrollingViewController! { return scrollingPart.scrollingController }
    var ringSection: PreferencesGroupSection! { return ringPart.ringSection }
    var generalRingRow: PreferencesSwitchRow! { return ringPart.generalRingRow }
    var generalRingSwitch: NSSwitch { return generalRingRow.toggle }
    var ringController: RingPreferencesViewController? { return ringPart.ringController }

    // MARK: - Lifecycle

    /// - Parameters:
    ///   - uiStateDefaults: where the part shown last and "Advanced" of the Scrolling
    ///     settings are remembered (shared with the Scrolling pane); tests and screenshots
    ///     give a store of their own.
    ///   - part: the part to open on (a mark of the list); nil: the one shown last.
    init(
        application: Application,
        uiStateDefaults: UserDefaults = .standard,
        part: ApplicationPagePart? = nil,
        parts: [ApplicationPagePart] = ApplicationPagePart.all
    ) {
        self.application = application
        self.uiStateDefaults = uiStateDefaults
        self.parts = parts
        let wanted = part ?? ApplicationPagePart.remembered(in: uiStateDefaults)
        shownPart = parts.contains(wanted) ? wanted : (parts.first ?? .scrolling)
        super.init(nibName: nil, bundle: nil)
        title = application.getName()
    }

    required init?(coder: NSCoder) {
        fatalError("ApplicationDetailViewController is built in code")
    }

    override func loadView() {
        let root = ApplicationDetailView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.onBack = { [weak self] in self?.goBack() }

        headerRow = ApplicationDetailHeaderRow(
            name: application.getName(),
            path: application.path,
            icon: application.getIcon()
        )
        headerRow.identifier = Identifier.header
        let header = PreferencesGroupSection(
            width: PreferencesGroupedForm.boxWidth(paneWidth: Self.paneWidth),
            rows: [headerRow]
        )
        headerSection = header

        let control = NSSegmentedControl(
            labels: parts.map(\.title), trackingMode: .selectOne, target: self, action: #selector(partClick(_:))
        )
        control.identifier = Identifier.parts
        control.segmentStyle = .automatic
        control.translatesAutoresizingMaskIntoConstraints = false
        control.setAccessibilityLabel(NSLocalizedString("apps-detail-parts", comment: ""))
        partControl = control

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        partContainer = container

        let note = NSTextField(wrappingLabelWithString: NSLocalizedString("apps-detail-allowlist-note", comment: ""))
        note.identifier = Identifier.allowlistNote
        note.font = PreferencesGroupedForm.explanationFont
        note.textColor = PreferencesGroupedForm.explanationColor(enabled: true)
        note.isSelectable = false
        let inset = PreferencesGroupedForm.rowHorizontalInset
        note.preferredMaxLayoutWidth = PreferencesGroupedForm.boxWidth(paneWidth: Self.paneWidth) - 2 * inset
        note.translatesAutoresizingMaskIntoConstraints = false
        allowlistNote = note

        for view in [header, note, control, container] {
            root.addSubview(view)
        }
        let margin = PreferencesGroupedForm.margin
        controlUnderHeader = control.topAnchor.constraint(equalTo: header.bottomAnchor, constant: PreferencesGroupedForm.boxSpacing)
        controlUnderNote = control.topAnchor.constraint(equalTo: note.bottomAnchor, constant: PreferencesGroupedForm.boxSpacing)
        let showsNote = Self.showsAllowlistNote
        note.isHidden = !showsNote
        NSLayoutConstraint.activate([
            // The app's box begins where the first box of every pane does.
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: margin),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: margin),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -margin),
            // A muted line close under the box, inset like the texts of its row.
            note.topAnchor.constraint(equalTo: header.bottomAnchor, constant: PreferencesGroupedForm.noteSpacing),
            note.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: inset),
            note.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -inset),
            showsNote ? controlUnderNote : controlUnderHeader,
            control.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            control.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: margin),
            // The part brings its own margins: the space above its first box.
            container.topAnchor.constraint(equalTo: control.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        // Every part is made now (their controls answer at once), and one is shown.
        for part in parts {
            let controller = part.makeController(application, uiStateDefaults)
            // (A part out of sight changes nothing on screen; the pane only measures again.)
            controller.onHeightChange = { [weak self] in self?.onHeightChange?() }
            if let scrolling = controller as? ApplicationScrollingPartViewController {
                scrolling.onInheritChange = { [weak self] in self?.onInheritChange?() }
            }
            if let buttons = controller as? ApplicationButtonsViewController {
                buttons.onOwnButtonsChange = onInheritChange
                buttons.partShowing = buttonsPartShowing
                // "Show Gesture Settings" of a row: the gestures of this app, not the pane.
                buttons.onGestureSettingsRequested = { [weak self] in self?.show(.gestures) }
            }
            (controller as? ApplicationRingPartViewController)?.partShowing = ringPartShowing
            (controller as? ApplicationGesturesPartViewController)?.partShowing = gesturesPartShowing
            addChild(controller)
            controller.view.translatesAutoresizingMaskIntoConstraints = false
            partControllers[part.id] = controller
        }
        // "Use the general ring" and "Use the general gestures" change the app's mark in
        // the list too.
        ringPart?.onHeightChange = { [weak self] in
            self?.onHeightChange?()
            self?.onInheritChange?()
        }
        gesturesPart?.onHeightChange = { [weak self] in
            self?.onHeightChange?()
            self?.onInheritChange?()
        }

        view = root
        put(shownPart)
        root.setFrameSize(root.fittingSize)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        // The Scrolling pane may have changed what an inheriting app shows.
        syncViewWithOptions()
    }

    /// The controller of the part shown.
    var shownController: ApplicationPagePartController? {
        return partControllers[shownPart.id]
    }

    // MARK: - Parts

    /// Shows `part` in place of the one shown, remembers it for every app's page, and tells
    /// the pane the page's height changed.
    func show(_ part: ApplicationPagePart) {
        guard isViewLoaded, parts.contains(part) else { return }
        guard part != shownPart else {
            part.remember(in: uiStateDefaults)
            return
        }
        shownController?.partWillHide()
        shownPart = part
        part.remember(in: uiStateDefaults)
        put(part)
        onHeightChange?()
    }

    /// Puts `part`'s view in the container (taking out the one there) and selects its
    /// segment.
    private func put(_ part: ApplicationPagePart) {
        guard let controller = partControllers[part.id] else { return }
        for subview in partContainer.subviews where subview !== controller.view {
            subview.removeFromSuperview()
        }
        partControl.selectedSegment = parts.firstIndex(of: part) ?? 0
        guard controller.view.superview !== partContainer else { return }
        controller.syncViewWithOptions()
        let partView = controller.view
        partContainer.addSubview(partView)
        NSLayoutConstraint.activate([
            partView.topAnchor.constraint(equalTo: partContainer.topAnchor),
            partView.leadingAnchor.constraint(equalTo: partContainer.leadingAnchor),
            partView.trailingAnchor.constraint(equalTo: partContainer.trailingAnchor),
            partView.bottomAnchor.constraint(equalTo: partContainer.bottomAnchor),
        ])
    }

    @objc func partClick(_ sender: NSSegmentedControl) {
        guard parts.indices.contains(sender.selectedSegment) else { return }
        show(parts[sender.selectedSegment])
    }

    /// The page goes away: what a part opened closes.
    func pageWillClose() {
        for controller in partControllers.values {
            controller.partWillHide()
        }
    }

    // MARK: - Refresh

    func syncViewWithOptions() {
        guard isViewLoaded else { return }
        // (Undo of a removal can bring back the name the app had.)
        let name = application.getName()
        if title != name {
            title = name
            headerRow.title = name
            headerRow.toolTip = Self.toolTip(name: name, path: application.path)
            headerRow.explanationLabel.toolTip = headerRow.toolTip
        }
        for controller in partControllers.values {
            controller.syncViewWithOptions()
        }
        let showsNote = Self.showsAllowlistNote
        if allowlistNote.isHidden == showsNote {
            allowlistNote.isHidden = !showsNote
            NSLayoutConstraint.deactivate([showsNote ? controlUnderHeader : controlUnderNote])
            NSLayoutConstraint.activate([showsNote ? controlUnderNote : controlUnderHeader])
            onHeightChange?()
        }
    }

    /// The line under the app's box shows while "Change scrolling only in these apps" is
    /// on: every app on the list then scrolls as its Scrolling part says, also one added
    /// only for its buttons, gestures or ring.
    static var showsAllowlistNote: Bool {
        return Options.shared.application.allowlist
    }

    /// What opens the Shortcut Ring while an app is in front, for the line of its switch.
    enum RingTrigger: Equatable {
        /// A button or key opens it there (Buttons', or one of the app's own).
        case opens
        /// Nothing opens it anywhere yet: neither Buttons nor any app's own buttons.
        case noTrigger
        /// Something opens it in other apps (a binding of Buttons, or another app's own),
        /// but nothing with this app in front.
        case replacedHere

        /// What opens the ring while `application` is in front, by the rule the Shortcut
        /// Ring pane counts by (`ApplicationTriggerRule`): Buttons' bindings with the app's
        /// own in them, as a press goes by them; and else whether anything opens it with
        /// another app in front.
        static func of(
            _ application: Application, general: [ButtonBinding],
            applications: [Application] = ApplicationTriggerRule.storedApplications
        ) -> RingTrigger {
            let rule = ApplicationTriggerRule.shortcutRing
            if !rule.bindings(general: general, own: application.ownButtonBindings).isEmpty { return .opens }
            let elsewhere = !rule.bindings(general: general).isEmpty
                || !rule.onlyInApps(general: general, applications: applications).isEmpty
            return elsewhere ? .replacedHere : .noTrigger
        }
    }

    /// "While Safari is in front, the general ring opens." / "While Safari is in front,
    /// the ring below opens." (The app in front decides, not the one under the pointer.)
    /// While no button or key opens the ring with the app in front, either way: that
    /// nothing opens it anywhere yet and where to set that up, or that nothing opens it
    /// with this app in front (where that is set: its Buttons part).
    static func generalRingExplanation(on: Bool, name: String, opens: RingTrigger = .opens) -> String {
        switch opens {
        case .noTrigger:
            return NSLocalizedString("apps-detail-ring-no-trigger", comment: "")
        case .replacedHere:
            return String(format: NSLocalizedString("apps-detail-ring-replaced", comment: ""), name)
        case .opens:
            let format = NSLocalizedString(on ? "apps-detail-ring-general-on" : "apps-detail-ring-general-off", comment: "")
            return String(format: format, name)
        }
    }

    /// "While Safari is in front, the general gestures run." / "While Safari is in front,
    /// the gestures below run." (The app in front decides, not the one under the pointer.)
    /// While no button runs Gesture Navigation with the app in front (`hasButton` false),
    /// either way: that none does there, and where that is set (its Buttons part).
    static func generalGesturesExplanation(on: Bool, name: String, hasButton: Bool = true) -> String {
        guard hasButton else {
            return String(format: NSLocalizedString("apps-detail-gestures-no-button", comment: ""), name)
        }
        let format = NSLocalizedString(on ? "apps-detail-gestures-general-on" : "apps-detail-gestures-general-off", comment: "")
        return String(format: format, name)
    }

    /// "Changes under Scrolling apply to Safari too." / "Safari keeps its own settings below."
    static func inheritExplanation(on: Bool, name: String) -> String {
        let format = NSLocalizedString(on ? "apps-detail-inherit-on" : "apps-detail-inherit-off", comment: "")
        return String(format: format, name)
    }

    // MARK: - Actions

    /// Esc, when a control of the page passes it on as a command.
    override func cancelOperation(_ sender: Any?) {
        goBack()
    }

    private func goBack() {
        onBack?()
    }

    // MARK: - Views

    /// Where the app is, for its header: the app bundle (not the program inside it that
    /// running apps are stored by), with `~` for the home folder.
    static func displayPath(for path: String) -> String {
        var bundlePath = path
        if let range = path.range(of: ".app/Contents/", options: .backwards) {
            bundlePath = String(path[..<path.index(range.lowerBound, offsetBy: 4)])
        }
        return (bundlePath as NSString).abbreviatingWithTildeInPath
    }

    /// The tooltip of an app's row and of its header: the name, which may be cut off, then
    /// the whole path on a second line.
    static func toolTip(name: String, path: String) -> String {
        return "\(name)\n\(path)"
    }
}

// MARK: - Header row

/// The app's row at the top of its page: its 32 pt icon, its name and where it is (one
/// line, shortened in the middle; the full name and path in the tooltip).
final class ApplicationDetailHeaderRow: PreferencesGroupRow {

    static let iconSize: CGFloat = 32
    /// Between the icon and the texts.
    static let iconSpacing: CGFloat = 10

    let iconView: NSImageView
    let path: String

    init(name: String, path: String, icon: NSImage) {
        let view = PreferencesListImageView()
        view.image = icon
        view.imageScaling = .scaleProportionallyUpOrDown
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setAccessibilityElement(false)
        iconView = view
        self.path = path
        let inset = PreferencesGroupedForm.rowHorizontalInset
        super.init(
            title: name,
            explanation: ApplicationDetailViewController.displayPath(for: path),
            leadingInset: inset + Self.iconSize + Self.iconSpacing
        )
        titleLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        explanationLabel.usesSingleLineMode = true
        explanationLabel.cell?.wraps = false
        explanationLabel.lineBreakMode = .byTruncatingMiddle
        explanationLabel.maximumNumberOfLines = 1
        toolTip = ApplicationDetailViewController.toolTip(name: name, path: path)
        explanationLabel.toolTip = toolTip

        addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            view.centerYAnchor.constraint(equalTo: centerYAnchor),
            view.widthAnchor.constraint(equalToConstant: Self.iconSize),
            view.heightAnchor.constraint(equalToConstant: Self.iconSize),
            view.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: PreferencesGroupedForm.controlMinimumInset),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("ApplicationDetailHeaderRow is built in code")
    }

    override func isAccessibilityElement() -> Bool {
        return true
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        return .group
    }

    /// The name, then where the app is.
    override func accessibilityLabel() -> String? {
        guard let explanation, !explanation.isEmpty else { return title }
        return "\(title), \(explanation)"
    }
}

// MARK: - Page view

/// The page's view. Esc (passed up from whatever has the focus on the page) and ⌘[ go back.
///
/// A click on a row's chevron or mark opens the page at once, and may be the first click
/// of a double-click (a double-click on a row opens it too): the next mouse-down then
/// lands on the page, where the part's first switch can sit right under the pointer. Such
/// a continued click (one that began before the page opened) reaches nothing on the page;
/// a click that begins on the page goes through as always.
final class ApplicationDetailView: NSView {

    var onBack: (() -> Void)?
    /// The event being handled. Tests give theirs.
    var currentEvent: () -> NSEvent? = { NSApp.currentEvent }
    /// When the page opened, on the clock of the events' timestamps.
    private let openedAt = ProcessInfo.processInfo.systemUptime
    /// Until a click begins on the page, a continued click is held back.
    private var holdsBackContinuedClicks = true

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        guard holdsBackContinuedClicks, hit != nil, let event = currentEvent(),
              event.type == .leftMouseDown, event.timestamp > openedAt else { return hit }
        guard event.clickCount > 1 else {
            holdsBackContinuedClicks = false
            return hit
        }
        return self
    }

    /// A continued click held back (`hitTest`) ends here.
    override func mouseDown(with event: NSEvent) {}

    /// The focus lands here when the page opens, so Esc works straight away.
    override var acceptsFirstResponder: Bool { return true }

    /// Not a stop of Tab: only the page's controls are.
    override var canBecomeKeyView: Bool { return false }

    override func keyDown(with event: NSEvent) {
        if Self.isEscape(event) {
            onBack?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if Self.isBackShortcut(event) {
            onBack?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private static func modifiers(of event: NSEvent) -> NSEvent.ModifierFlags {
        return event.modifierFlags.intersection([.command, .option, .control, .shift])
    }

    /// Esc without modifiers.
    static func isEscape(_ event: NSEvent) -> Bool {
        return event.type == .keyDown && event.keyCode == KeyCode.escape && modifiers(of: event).isEmpty
    }

    /// ⌘[, as "Back" in Finder and Safari.
    static func isBackShortcut(_ event: NSEvent) -> Bool {
        return event.type == .keyDown && modifiers(of: event) == .command && event.charactersIgnoringModifiers == "["
    }
}
