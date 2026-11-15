//
//  ApplicationGesturesPartViewController.swift
//  Scrollio
//
//  The Gestures part of an app's page: "Use the general gestures" and, while it is off,
//  the app's own set, all of the Gestures pane but its preview and the button to hold, in
//  the pane's rows and order (`MouseGestureRows`): "Mode", "Directions" (Up, Down, Left,
//  Right, Click, the same pull-downs, "Keyboard Shortcut…" with a name and an icon among
//  them), "Behavior" (invert, freeze, swipe speed) and "Logitech mouse" ("Let the mouse
//  track the gesture", "Pulse when a gesture locks in"), the last there while a connected
//  mouse can do one of them, as in the pane. They run while the app is in front
//  (`MouseGestureChoice`). In "Follow the hand" the Left and Right rows say so and the
//  speed applies, as the pane's do, by the app's own mode. The button to hold is a binding
//  of Buttons, or of the app's Buttons part: the first row, "Button to hold", says which
//  one runs the gestures with the app in front ("Gesture button, as everywhere", "Back
//  button, only in Figma", "None in Figma", `ApplicationTriggerRow`), and its button goes
//  there: "Show in Buttons", "Show in Figma › Buttons" (the app's Buttons part, that row
//  selected) or "Set Up…", which records a mouse button that runs the gestures only in
//  this app.
//
//  "Copy from Gestures" ends the own set, there with it: all of it becomes a copy of the
//  general gestures as they are now (greyed while it is one), the switch stays; the
//  window's Undo takes it back, also after the page closed.
//
//  While no button runs the gestures with the app in front (`ApplicationTriggerRule`),
//  the titles "Directions", "Behavior" and "Logitech mouse" fold what is under them
//  (`PreferencesDisclosureSection`), as the Gestures pane folds its sections; "Mode" and
//  "Reset to Defaults" stay, as there. A click opens a section, all of it editable. Once a
//  button runs them there, the titles are plain titles again and the set shows as before.
//

import Cocoa

final class ApplicationGesturesPartViewController: NSViewController, ApplicationPagePartController {

    enum Identifier {
        static let generalGestures = NSUserInterfaceItemIdentifier("apps-detail-general-gestures")
        static let mode = NSUserInterfaceItemIdentifier("apps-detail-gestures-mode")
        static let holdButton = NSUserInterfaceItemIdentifier("apps-detail-gestures-hold")
        static let reset = NSUserInterfaceItemIdentifier("apps-detail-gestures-reset")
    }

    typealias Slot = MouseGestureSettingsControls.Slot

    let application: Application
    var onHeightChange: (() -> Void)?
    /// Takes Undo and Redo of "Reset to Defaults"; the window's when nil.
    var paneUndoManager: UndoManager?
    /// The Gestures part that shows an app's entry now, if any (the pane's answer). An Undo
    /// or Redo of "Reset to Defaults" asks it when it runs, maybe after this page closed
    /// and the app's page opened again: it must not hold the page. nil: this part, while
    /// it is there.
    var partShowing: ((Application) -> ApplicationGesturesPartViewController?)?
    /// Whether the menus offer Logitech actions: a Logitech button runs Gesture Navigation
    /// while the app is in front (`ApplicationTriggerRule`), as the Gestures pane asks of
    /// its buttons. Tests replace it.
    var showsLogiActions: () -> Bool
    /// Whether "Follow the hand" can run at all (without it the mode is discrete). Tests
    /// replace it.
    var isInteractiveAvailable: () -> Bool = { DockSwipeSynthesizer.shared.isAvailable }
    /// What the connected mice can do: the "Logitech mouse" section shows as the Gestures
    /// pane's does. Tests replace it.
    var deviceSource: MouseGestureDeviceSource = .live
    /// "Show in Mouse": shows the Mouse pane. Tests replace it.
    var openMousePane: (() -> Void)?
    /// "Show in Buttons" of "Button to hold": the Buttons pane, the gesture button's row
    /// selected. Tests replace it.
    var openButtonsPane: (() -> Void)?
    /// "Show in Figma" of "Button to hold": the app's Buttons part, the row with this id
    /// selected (the page sets it).
    var showApplicationButtons: ((UUID) -> Void)?
    /// "Set Up…" of "Button to hold": records a mouse button at the push button that runs
    /// the gestures only while the app is in front (the page sets it: the app's Buttons
    /// part records it).
    var setUpButton: ((NSView) -> Void)?

    private(set) var generalSection: PreferencesGroupSection!
    private(set) var generalGesturesRow: PreferencesSwitchRow!
    /// "Button to hold", the first row: which button runs the gestures with the app in
    /// front, and a push button that goes there.
    private(set) var holdRow: PreferencesGroupRow!
    private(set) var holdButton: NSButton!
    /// What the row says now, and where its button leads.
    private(set) var shownHold: ApplicationTriggerRow?
    /// The app's own set: there only while "Use the general gestures" is off.
    private(set) var controls: MouseGestureSettingsControls?
    /// "Mode", in a box of its own above the sections (it never folds, as in the pane);
    /// like everything below it, there only while "Use the general gestures" is off.
    private(set) var modeSection: PreferencesGroupSection?
    private(set) var modeRow: PreferencesGroupRow?
    /// Up, Down, Left, Right, Click, in `Slot.allCases` order; empty while the app uses the
    /// general gestures.
    private(set) var directionRows: [PreferencesGroupRow] = []
    /// "Directions" and the box of the five rows; it folds them while no button runs the
    /// gestures with the app in front.
    private(set) var directionsFold: PreferencesDisclosureSection?
    /// The box of the five rows (its title is `directionsFold`'s).
    private(set) var directionsSection: PreferencesGroupSection?
    /// "Behavior": invert, freeze and the swipe speed.
    private(set) var behaviourFold: PreferencesDisclosureSection?
    private(set) var invertRow: PreferencesGroupRow?
    private(set) var freezeRow: PreferencesGroupRow?
    private(set) var trackingSpeedRow: PreferencesSliderRow?
    /// "Logitech mouse": there while a connected mouse can do one of its two switches.
    private(set) var logitechFold: PreferencesDisclosureSection?
    private(set) var deviceTrackingRow: PreferencesSwitchRow?
    private(set) var hapticsRow: PreferencesSwitchRow?
    /// "Haptic feedback is off under Mouse." with "Show in Mouse", under the "Logitech mouse"
    /// box, as the Gestures pane has it: in sight while the box shows its rows and a mouse
    /// has its haptics off because they were switched off under Mouse (no pulse comes).
    private(set) var hapticsOffNote: NSView?
    private(set) var hapticsOffLabel: NSTextField?
    private(set) var openMouseButton: NSButton?
    /// The sections whose titles fold them while no button runs the gestures here.
    var foldingSections: [PreferencesDisclosureSection] {
        return [directionsFold, behaviourFold, logitechFold].compactMap { $0 }
    }
    /// "Reset to Defaults" under the own set, there with it.
    private(set) var resetToDefaults: PreferencesPaneReset!
    var resetToDefaultsButton: NSButton {
        return resetToDefaults.button
    }
    private(set) var resetFooter: PreferencesGroupFooter!
    private var content: NSStackView!

    var generalGesturesSwitch: NSSwitch { return generalGesturesRow.toggle }

    init(application: Application) {
        self.application = application
        showsLogiActions = { [application] in
            ApplicationTriggerRule.gestureNavigation
                .bindings(general: Options.shared.buttons.binding, own: application.ownButtonBindings)
                .contains { LogiCenter.shared.isLogiCode($0.triggerEvent.code) }
        }
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("ApplicationGesturesPartViewController is built in code")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        content = PreferencesGroupedForm.installContentStack(in: root, paneWidth: ApplicationDetailViewController.paneWidth)
        let name = application.getName()
        let general = PreferencesSwitchRow(
            title: text("apps-detail-gestures-general"),
            explanation: nil,
            target: self,
            action: #selector(generalGesturesClick(_:))
        )
        general.toggle.identifier = Identifier.generalGestures
        // Room for the longer of the two lines, so switching never moves the rows below.
        general.reservedExplanations = [true, false].map { ApplicationDetailViewController.generalGesturesExplanation(on: $0, name: name) }
        generalGesturesRow = general
        let hold = PreferencesGroupedForm.makePushButton(
            title: text("gestures-gesture-button-set-up"), target: self, action: #selector(holdButtonClicked(_:))
        )
        hold.identifier = Identifier.holdButton
        ApplicationTriggerRow.limitWidth(of: hold)
        holdButton = hold
        holdRow = PreferencesGroupRow(title: text("gestures-gesture-button"), explanation: "", accessory: hold)
        // (No title: the part's segment names it.) The button to hold first, as in the pane.
        let section = PreferencesGroupSection(width: Self.boxWidth, rows: [holdRow, general])
        generalSection = section
        PreferencesGroupedForm.add([section], to: content)
        // A titled section's room above the app's own set.
        content.setCustomSpacing(PreferencesGroupedForm.sectionSpacing, after: section)
        let reset = PreferencesPaneReset(
            undoActionName: Self.resetActionName(for: application),
            title: text("apps-gestures-copy"),
            undoTitle: text("apps-part-undo"),
            hasSettingsToReset: { [weak self] in self?.hasSettingsToReset ?? false },
            undoManager: { [weak self] in self?.undoTarget },
            reset: { [weak self] undo in self?.resetGestures(undoManager: undo) }
        )
        // What is being edited (a name typed in a row's popover) goes first.
        reset.willReset = { [weak self] in self?.controls?.endEditing() }
        reset.button.identifier = Identifier.reset
        resetToDefaults = reset
        resetFooter = PreferencesGroupFooter(trailing: [reset.button])
        view = root
        syncViewWithOptions()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // A mouse that can track gestures or has haptics connected or left: the "Logitech
        // mouse" section follows, as the pane's does.
        for name in [LogiCenter.gestureStateChanged, LogiCenter.mouseStateChanged] {
            NotificationCenter.default.addObserver(self, selector: #selector(deviceStateDidChange(_:)), name: name, object: nil)
        }
    }

    @objc private func deviceStateDidChange(_ notification: Notification) {
        if Thread.isMainThread {
            syncViewWithOptions()
        } else {
            DispatchQueue.main.async { [weak self] in self?.syncViewWithOptions() }
        }
    }

    /// What "Button to hold" says and where its button leads, counted by the rule the
    /// Gestures pane counts by (`ApplicationTriggerRule`).
    static func hold(for application: Application, general: [ButtonBinding]) -> ApplicationTriggerRow {
        return ApplicationTriggerRow.make(.gestureNavigation, application: application, general: general)
    }

    /// Whether a button runs Gesture Navigation while the app is in front.
    static func hasButton(for application: Application, general: [ButtonBinding]) -> Bool {
        return !ApplicationTriggerRule.gestureNavigation.bindings(general: general, own: application.ownButtonBindings).isEmpty
    }

    /// Puts what runs the gestures here into "Button to hold". True when its line changed
    /// while the part is on screen (it may take more or less room).
    private func syncHold() -> Bool {
        let hold = Self.hold(for: application, general: Options.shared.buttons.binding)
        shownHold = hold
        ApplicationTriggerRow.show(hold.buttonTitle(applicationName: application.getName()), on: holdButton)
        guard holdRow.explanation != hold.text else { return false }
        holdRow.explanation = hold.text
        return view.superview != nil
    }

    private static var boxWidth: CGFloat {
        return PreferencesGroupedForm.boxWidth(paneWidth: ApplicationDetailViewController.paneWidth)
    }

    private func text(_ key: String) -> String {
        return NSLocalizedString(key, comment: "")
    }

    // MARK: - ApplicationPagePartController

    func syncViewWithOptions() {
        if sync() {
            onHeightChange?()
        }
    }

    /// Shows the stored settings; true when the page must measure again: the switch's line
    /// or the line under the box changed while the part is on screen (an Undo in the app's
    /// Buttons), and may take more or less room.
    @discardableResult
    private func sync() -> Bool {
        guard isViewLoaded else { return false }
        let usesGeneral = application.usesGeneralGestures
        generalGesturesRow.isOn = usesGeneral
        let hasButton = Self.hasButton(for: application, general: Options.shared.buttons.binding)
        let line = ApplicationDetailViewController.generalGesturesExplanation(on: usesGeneral, name: application.getName())
        var remeasures = generalGesturesRow.explanation != line && view.superview != nil
        generalGesturesRow.explanation = line
        remeasures = syncHold() || remeasures
        showOwnSet(!usesGeneral)
        // (Folds when it becomes foldable; the page measures again.)
        for fold in foldingSections where fold.isCollapsible == hasButton {
            fold.isCollapsible = !hasButton
            remeasures = remeasures || view.superview != nil
        }
        resetToDefaults.settingsDidChange()
        guard let controls else { return remeasures }
        controls.showLogiActions = showsLogiActions()
        controls.sync()
        if let logitechFold {
            let rules = logitechRules
            if logitechFold.isHidden == rules.showsOptions {
                logitechFold.isHidden = !rules.showsOptions
                remeasures = remeasures || view.superview != nil
            }
        }
        if syncHapticsOffNote() {
            remeasures = remeasures || view.superview != nil
        }
        showOwnValues()
        return remeasures
    }

    /// Shows the line under the "Logitech mouse" box, or takes it away: while the box shows
    /// its rows and the mice say that the haptics are off under Mouse. A line sits close
    /// under its box; without it the footer keeps a section's room. True when it came or
    /// went.
    @discardableResult
    private func syncHapticsOffNote() -> Bool {
        guard let note = hapticsOffNote, let logitechFold else { return false }
        let shows = !logitechFold.isHidden && logitechFold.showsBody && logitechRules.showsHapticsOffNote
        content.setCustomSpacing(shows ? PreferencesGroupedForm.noteSpacing : PreferencesGroupedForm.sectionSpacing, after: logitechFold)
        guard note.isHidden == shows else { return false }
        note.isHidden = !shows
        return true
    }

    /// What the Gestures pane shows of a Logitech mouse's switches, by the connected mice.
    private var logitechRules: MouseGestureControlRules {
        return MouseGestureControlRules(support: deviceSource.support(), hapticsOnUnderMouse: Options.shared.logiMouse.hapticsOn)
    }

    func partWillHide() {
        controls?.endEditing()
        resetToDefaults.endUndoOffer()
    }

    // MARK: - Reset to Defaults

    /// The undo action's name, its own, not the Gestures pane's: "Copy from Gestures in
    /// Calculator" (Edit › Undo says what it takes back, and the button's "Undo" never
    /// takes back the pane's reset or another app's copy).
    static let resetActionNameKey = "apps-undo-copy-gestures"

    static func resetActionName(for application: Application) -> String {
        return String(format: NSLocalizedString(resetActionNameKey, comment: ""), application.getName())
    }

    /// Where "Reset to Defaults" registers its Undo: the window's while the page is in it.
    var undoTarget: UndoManager? {
        return paneUndoManager ?? view.window?.undoManager
    }

    /// The own set is in use and differs from a copy of the general one as it is now (any
    /// of it: the five actions with their names and icons, the invert switch, the mode,
    /// the speed, the freeze and a Logitech mouse's two switches).
    var hasSettingsToReset: Bool {
        guard application.ownGestures != nil else { return false }
        let general = Options.shared.gesture
        return application.gesturesThatRun(general: general) != general
    }

    /// "Copy from Gestures": the own set as the switch starts it, a copy of the general one
    /// as it is now; the switch stays off. Edit › Undo brings back the set that was there.
    private func resetGestures(undoManager undo: UndoManager?) {
        guard hasSettingsToReset else { return }
        let showing = partShowing ?? { [weak self] entry in
            self?.application === entry ? self : nil
        }
        let copy = ApplicationGestures(inherit: false, copying: Options.shared.gesture)
        Self.putGestures(of: application, set: copy, undoManager: undo, showing: showing)
    }

    /// As the ring's reset (`ApplicationRingPartViewController`): the undo target is the
    /// settings, not the page; Undo and Redo find the app's entry by its path when they
    /// run, and show the change on the part `showing` gives for it. (A set kept for later
    /// takes them too: the switch is never touched.)
    private static func putGestures(
        of application: Application, set: ApplicationGestures, undoManager undo: UndoManager?,
        showing: @escaping (Application) -> ApplicationGesturesPartViewController?
    ) {
        guard let before = application.gestures else { return }
        application.replaceOwnGestureSet(with: set)
        guard application.gestures != before else { return }
        showing(application)?.syncViewWithOptions()
        guard let undo else { return }
        let path = application.path
        undo.registerUndo(withTarget: Options.shared) { [weak undo] _ in
            guard let entry = PreferencesApplicationViewController.existingApplication(
                forPaths: PreferencesApplicationViewController.knownPaths(forStoredPath: path)
            ) else { return }
            putGestures(of: entry, set: before, undoManager: undo, showing: showing)
        }
        undo.setActionName(resetActionName(for: application))
    }

    // MARK: - The app's own set

    /// Puts the app's own values into the rows that are not the controls' own: the Left and
    /// Right rows are dimmed while the desktop follows the hand (the app's own mode), as in
    /// the Gestures pane, their pull-downs say so (`MouseGestureSettingsControls`); the
    /// speed applies only then; a Logitech mouse's switches as the connected mice allow.
    private func showOwnValues() {
        guard let controls else { return }
        let presentation = controls.modePresentation
        modeRow?.explanation = text(presentation.descriptionKey)
        for slot in Slot.allCases where slot.isHorizontal {
            directionRows[slot.rawValue].isEnabled = presentation.areHorizontalActionsEditable
        }
        let settings = controls.editedSettings
        if let trackingSpeedRow {
            MouseGestureRows.show(settings, presentation: presentation, in: trackingSpeedRow)
        }
        if let deviceTrackingRow, let hapticsRow {
            MouseGestureRows.show(settings, rules: logitechRules, deviceTracking: deviceTrackingRow, haptics: hapticsRow)
        }
    }

    /// Puts the app's own set (the pane's rows from "Mode" to "Logitech mouse") and "Reset
    /// to Defaults" under the switch's box, or takes them away again: they are there exactly
    /// while "Use the general gestures" is off.
    private func showOwnSet(_ shows: Bool) {
        guard shows != (controls != nil) else { return }
        if let controls {
            controls.endEditing()
            resetToDefaults.endUndoOffer()
            for view in [modeSection, directionsFold, behaviourFold, logitechFold, hapticsOffNote, resetFooter] as [NSView?] {
                guard let view else { continue }
                content.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
            self.controls = nil
            modeSection = nil
            modeRow = nil
            directionRows = []
            directionsFold = nil
            directionsSection = nil
            behaviourFold = nil
            invertRow = nil
            freezeRow = nil
            trackingSpeedRow = nil
            logitechFold = nil
            deviceTrackingRow = nil
            hapticsRow = nil
            hapticsOffNote = nil
            hapticsOffLabel = nil
            openMouseButton = nil
            return
        }
        let controls = MouseGestureSettingsControls(
            showLogiActions: showsLogiActions(),
            edits: .application(application),
            isInteractiveAvailable: { [weak self] in self?.isInteractiveAvailable() ?? false }
        )
        controls.onChange = { [weak self] in
            self?.showOwnValues()
            // (A row moved the set off the general one, or back: "Reset to Defaults" follows.)
            self?.resetToDefaults.settingsDidChange()
        }
        self.controls = controls
        let width = Self.boxWidth
        let mode = MouseGestureRows.mode(controls.modeControl)
        mode.identifier = Identifier.mode
        modeRow = mode
        let modeBox = PreferencesGroupSection(width: width, rows: [mode])
        modeSection = modeBox
        // The rows of the Gestures pane, each with its pull-down (`popUpWidth` wide by itself).
        directionRows = Slot.allCases.map { slot in
            PreferencesGroupRow(title: text(slot.labelKey), accessory: controls.actionPopUp(for: slot))
        }
        let directions = PreferencesGroupSection(width: width, rows: directionRows)
        directionsSection = directions
        let invert = MouseGestureRows.invert(controls.invertToggle)
        invertRow = invert
        let freeze = MouseGestureRows.freeze(controls.freezeToggle)
        freezeRow = freeze
        let speed = MouseGestureRows.trackingSpeed(target: self, action: #selector(trackingSpeedChanged(_:)))
        trackingSpeedRow = speed
        let tracking = MouseGestureRows.deviceTracking(target: self, action: #selector(deviceTrackingToggled(_:)))
        deviceTrackingRow = tracking
        let haptics = MouseGestureRows.haptics(target: self, action: #selector(hapticsToggled(_:)))
        hapticsRow = haptics
        // Under titles that fold them (plain titles while they cannot), as the pane's.
        let folds = [
            PreferencesDisclosureSection(title: text("gestures-directions-header"), body: directions),
            PreferencesDisclosureSection(
                title: text("gestures-behaviour-header"), body: PreferencesGroupBox(width: width, rows: [invert, freeze, speed])
            ),
            PreferencesDisclosureSection(
                title: text("gestures-logitech-header"), body: PreferencesGroupBox(width: width, rows: [tracking, haptics])
            ),
        ]
        directionsFold = folds[0]
        behaviourFold = folds[1]
        logitechFold = folds[2]
        let collapsible = !Self.hasButton(for: application, general: Options.shared.buttons.binding)
        for fold in folds {
            fold.isCollapsible = collapsible
            fold.onExpandedChange = { [weak self] _ in
                // (The line under the Logitech box opens and folds with it.)
                self?.syncHapticsOffNote()
                self?.onHeightChange?()
            }
        }
        folds[2].isHidden = !logitechRules.showsOptions
        let note = MouseGestureRows.hapticsOffNote(boxWidth: width, target: self, action: #selector(openMouseClicked(_:)))
        hapticsOffNote = note.holder
        hapticsOffLabel = note.label
        openMouseButton = note.button
        PreferencesGroupedForm.add([modeBox] + folds + [note.holder, resetFooter], to: content)
        syncHapticsOffNote()
    }

    // MARK: - Actions

    /// On: the gestures of the Gestures pane run while the app is in front; the app's own
    /// set stays stored for later. Off: the app's own set, which starts as a copy of the
    /// general gestures as they are now (all of them) when the app never had one.
    /// The swipe speed's slider: the app's own speed, on a tick.
    @objc func trackingSpeedChanged(_ sender: NSSlider) {
        let value = MouseGestureTrackingSpeed.snapped(sender.doubleValue)
        trackingSpeedRow?.valueText = MouseGestureTrackingSpeed.text(value)
        controls?.setTrackingSpeed(value)
        resetToDefaults.settingsDidChange()
    }

    /// "Let the mouse track the gesture" of the app's own set.
    @objc func deviceTrackingToggled(_ sender: NSSwitch) {
        controls?.setDeviceTracking(sender.state == .on)
        showOwnValues()
        resetToDefaults.settingsDidChange()
    }

    /// "Pulse when a gesture locks in" of the app's own set.
    @objc func hapticsToggled(_ sender: NSSwitch) {
        controls?.setHapticFeedback(sender.state == .on)
        showOwnValues()
        resetToDefaults.settingsDidChange()
    }

    /// The push button of "Button to hold": where its line leads (what an Undo keeps up to
    /// date is what the row shows).
    @objc func holdButtonClicked(_ sender: NSButton) {
        let hold = shownHold ?? Self.hold(for: application, general: Options.shared.buttons.binding)
        switch hold.destination {
        case .setUp:
            setUpButton?(sender)
        case .applicationButtons(let id):
            showApplicationButtons?(id)
        case .buttonsPane:
            if let openButtonsPane {
                openButtonsPane()
                return
            }
            guard let split = PreferencesButtonsViewController.splitViewController(of: self),
                  split.selectPane(withIdentifier: PANEL_IDENTIFIER.buttons),
                  let buttons = split.controller(for: PANEL_IDENTIFIER.buttons) as? PreferencesButtonsViewController else { return }
            // The row the line names.
            if let id = hold.buttonsBindingID, buttons.selectBinding(id: id) { return }
            buttons.selectGestureButton()
        }
    }

    /// "Show in Mouse", next to the line that says the haptics are off there.
    @objc func openMouseClicked(_ sender: NSButton) {
        if let openMousePane {
            openMousePane()
            return
        }
        PreferencesButtonsViewController.splitViewController(of: self)?
            .selectPane(withIdentifier: MousePreferencesViewController.tabIdentifier)
    }

    @objc func generalGesturesClick(_ sender: NSSwitch) {
        // First what is being edited (a name typed in a row's popover) goes into the set,
        // while it is still the app's own.
        controls?.endEditing()
        application.setUsesGeneralGestures(sender.state == .on, general: Options.shared.gesture)
        // (The own set came or went: the page measures again, once.)
        sync()
        onHeightChange?()
    }
}
