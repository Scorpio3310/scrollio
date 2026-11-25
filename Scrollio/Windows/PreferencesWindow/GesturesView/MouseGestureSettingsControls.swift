//
//  MouseGestureSettingsControls.swift
//  Mos
//  The controls that edit Options.shared.gesture: mode, "Up and Down follow the hand too",
//  one action per direction and click, and the switches for invert left/right and freeze
//  pointer, and where the swipe speed and the two switches of a Logitech mouse are written.
//  The Gestures pane lays them out in its rows (`MouseGestureRows`, the rows themselves);
//  their rules live here. Changes apply immediately.
//
//  In "Follow the hand" the Left and Right rows say "Desktop follows the hand" and take no
//  choice. With "Up and Down follow the hand too" on, an Up or Down row whose action opens
//  with the hand on this Mac says so in place of the action ("Mission Control follows the
//  hand") and stays a pull-down with its menu; one whose action could, but does not here,
//  shows the action as ever and says why in its tooltip and VoiceOver help
//  (`MouseGestureFollowPresentation`, from `MouseGestureSettings.followPlan`, the answer
//  the hold itself goes by). What can follow on this Mac comes in as a value
//  (`followAvailability`), so tests and pictures show every state.
//
//  An app's page edits the app's own gestures with the same controls and rows
//  (`Edited.application`): every value is then the app's (`ApplicationGestures`), the mode
//  too, which decides what the Left and Right rows show and whether the speed applies.
//
//  The action of a direction is chosen with the pull-down of a button's row
//  (`ButtonActionPullDown`, as the Shortcut Ring pane's places): its menu offers the
//  pane's one-shot actions and "Keyboard Shortcut…", which records a key combination
//  there and can give it a name and an icon, as for a place of the ring.
//

import Cocoa

/// What the mode control and the action rows show for a stored mode. Pure.
struct MouseGestureModePresentation: Equatable {
    /// The mode in effect, shown as selected.
    var selectedMode: MouseGestureMode
    /// False greys out "Follow the hand".
    var isInteractiveSelectable: Bool
    /// False disables the Left and Right rows: the swipe owns sideways movement.
    var areHorizontalActionsEditable: Bool

    /// Tracking speed scales the swipe, so it only applies while the desktop follows the hand.
    var isTrackingSpeedEditable: Bool {
        return selectedMode == .interactive
    }

    /// Localization key of the one line the tab shows under "Mode": what the selected mode
    /// does, or why "Follow the hand" cannot be picked.
    var descriptionKey: String {
        guard isInteractiveSelectable else { return "gesture-mode-interactive-unavailable" }
        return selectedMode == .interactive ? "gesture-mode-interactive-description" : "gesture-mode-discrete-description"
    }

    /// Every line `descriptionKey` can be, so the row can keep room for the longest.
    static let descriptionKeys = [
        "gesture-mode-discrete-description",
        "gesture-mode-interactive-description",
        "gesture-mode-interactive-unavailable",
    ]

    /// Without the swipe synthesizer Scrollio runs discrete whatever is stored, so the control
    /// shows discrete. The stored mode is left alone and applies again once it is available.
    static func make(storedMode: MouseGestureMode, isInteractiveAvailable: Bool) -> MouseGestureModePresentation {
        let selected: MouseGestureMode = isInteractiveAvailable ? storedMode : .discrete
        return MouseGestureModePresentation(
            selectedMode: selected,
            isInteractiveSelectable: isInteractiveAvailable,
            areHorizontalActionsEditable: selected == .discrete
        )
    }
}

/// What the pane shows about "Up and Down follow the hand too": the switch, the line under
/// it and what the Up and Down rows say. Pure: from the settings as they run (the mode in
/// effect) and what can follow the hand on this Mac (`DockFollowAvailability`).
struct MouseGestureFollowPresentation: Equatable {

    /// What the row of a direction shows.
    enum Row: Equatable {
        /// The action as it is: its picture and its name.
        case plain
        /// A sentence in place of the action: it opens with the hand.
        case follows(String)
        /// The action as it is, and why it runs once on this Mac although the switch is
        /// on: the pull-down's tooltip and VoiceOver help.
        case runsOnceHere(String)

        /// The sentence shown in place of the action; nil: the action.
        var face: String? {
            if case .follows(let sentence) = self { return sentence }
            return nil
        }

        /// The tooltip and VoiceOver help; nil: none.
        var note: String? {
            if case .runsOnceHere(let sentence) = self { return sentence }
            return nil
        }
    }

    /// The stored choice: the switch shows it also while it does not apply.
    var isOn: Bool
    /// Only "Follow the hand" uses the switch.
    var isEditable: Bool
    /// The line under the switch: what opens with the hand on this Mac, or that the mode
    /// in effect does not use the switch.
    var hint: String
    var up: Row
    var down: Row

    /// What the row of `direction` shows. Left and Right are the desktops' in "Follow the
    /// hand", whatever this says: they are not asked.
    func row(for direction: MouseGestureDirection) -> Row {
        switch direction {
        case .up: return up
        case .down: return down
        case .left, .right: return .plain
        }
    }

    /// - Parameters:
    ///   - settings: the settings the pane edits (an app's own on its page), as stored.
    ///   - mode: what the mode control shows: the mode in effect counts, not a stored
    ///     "Follow the hand" that cannot run here.
    static func make(
        settings: MouseGestureSettings, mode: MouseGestureModePresentation, availability: DockFollowAvailability
    ) -> MouseGestureFollowPresentation {
        let isUsed = mode.selectedMode == .interactive
        // The plan the hold itself goes by (`followPlan`), for the mode in effect.
        var running = settings
        running.mode = mode.selectedMode
        func row(_ direction: MouseGestureDirection) -> Row {
            switch running.followPlan(for: direction, availability: availability) {
            case .follows(let target):
                return .follows(face(of: target, majorVersion: availability.majorVersion))
            case .cannotFollow(_, let obstacle):
                return note(for: obstacle).map(Row.runsOnceHere) ?? .plain
            case .doesNotFollow:
                return .plain
            }
        }
        return MouseGestureFollowPresentation(
            isOn: settings.actionsFollowHand,
            isEditable: isUsed,
            hint: isUsed
                ? hint(naming: availability.targetsThatFollow, majorVersion: availability.majorVersion)
                : text("gesture-follow-actions-hint-discrete"),
            up: row(.up),
            down: row(.down)
        )
    }

    private static func text(_ key: String) -> String {
        return NSLocalizedString(key, comment: "")
    }

    /// The order the switch's line names them in: the menu's.
    static let namedOrder: [DockFollowTarget] = [.missionControl, .apps, .showDesktop]

    /// What the listed action that opens `target` is called on macOS `majorVersion`
    /// ("Apps" from macOS 26 on, "Launchpad" before), as the menus call it.
    static func name(of target: DockFollowTarget, majorVersion: Int) -> String {
        return text(SystemShortcut.Shortcut.nameKey(of: target.actionIdentifier, onMacOS: majorVersion))
    }

    /// "Apps" is a plural: "Apps follow the hand", "Apps open with your hand".
    private static func isPlural(_ target: DockFollowTarget, majorVersion: Int) -> Bool {
        return target == .apps
            && SystemShortcut.Shortcut.nameKey(of: target.actionIdentifier, onMacOS: majorVersion) != target.actionIdentifier
    }

    /// The line under the switch in "Follow the hand": what opens with the hand on this
    /// Mac, `targets` in the line's own order ("Mission Control and Show Desktop open with
    /// your hand, like on a trackpad. Other actions run once."), or that nothing can now.
    static func hint(naming targets: [DockFollowTarget], majorVersion: Int) -> String {
        let named = namedOrder.filter(targets.contains)
        guard let first = named.first else { return text("gesture-follow-actions-hint-none") }
        let several = named.count > 1 || isPlural(first, majorVersion: majorVersion)
        return String(
            format: text(several ? "gesture-follow-actions-hint-several" : "gesture-follow-actions-hint-one"),
            InterfaceList.joined(named.map { name(of: $0, majorVersion: majorVersion) })
        )
    }

    /// Every line the switch's row can show on macOS `majorVersion`, so the row keeps room
    /// for the longest: the one of "One action per hold", the one for nothing, and one for
    /// each choice of the three that can open with the hand.
    static func hints(majorVersion: Int) -> [String] {
        var lines = [text("gesture-follow-actions-hint-discrete"), text("gesture-follow-actions-hint-none")]
        for choice in 1..<(1 << namedOrder.count) {
            let targets = namedOrder.enumerated().filter { choice & (1 << $0.offset) != 0 }.map(\.element)
            lines.append(hint(naming: targets, majorVersion: majorVersion))
        }
        return lines
    }

    /// The sentence a row shows in place of the action that opens `target`: "Mission
    /// Control follows the hand", "Apps follow the hand".
    static func face(of target: DockFollowTarget, majorVersion: Int) -> String {
        if isPlural(target, majorVersion: majorVersion) {
            return text("gesture-follow-apps-value")
        }
        return String(format: text("gesture-follow-action-value"), name(of: target, majorVersion: majorVersion))
    }

    /// Why a row whose action could open with the hand runs once here, where the reason is
    /// the row's own: this macOS (Show Desktop before macOS 27), or the Dock's own switch
    /// for the trackpad gesture. nil where it is not (nothing follows the hand at all, or
    /// macOS lets Scrollio post nothing): the row then shows its action without words.
    /// (Apps in a released build never gets here: nothing asks it to follow, `followPlan`.)
    static func note(for obstacle: DockFollowAvailability.Obstacle) -> String? {
        switch obstacle {
        case .notOnThisMacOS: return text("gesture-follow-once-macos")
        case .gestureOff: return text("gesture-follow-once-gesture-off")
        case .swipeUnavailable, .cannotPostEvents: return nil
        }
    }
}

/// Tracking speed slider: its tick marks, steps, clamping and the value label. Pure.
enum MouseGestureTrackingSpeed {
    /// A tick every 0.25 from 0.5 to 3; the knob stops only on them.
    static let scale = PreferencesSliderScale.ticksOnly(11)

    static var step: Double {
        return scale.step(in: MouseGestureSettings.trackingSpeedRange)
    }

    /// Clamps into `MouseGestureSettings.trackingSpeedRange` and rounds to the nearest tick.
    static func snapped(_ value: Double) -> Double {
        return scale.snapped(value, in: MouseGestureSettings.trackingSpeedRange)
    }

    /// 1.5 -> "1.5×", 1.25 -> "1.25×": one decimal, two where a quarter needs them, in the
    /// user's locale ("1,25×" with a decimal comma), as the Scrolling pane writes its speeds
    /// (`FactorText`). Display only: the stored value is not changed.
    static func text(_ value: Double, locale: Locale = .current) -> String {
        return FactorText.string(value, locale: locale)
    }
}

/// An action pull-down that tells when it gains or loses the keyboard focus (the tab's
/// preview shows the gesture of the focused row).
final class MouseGestureActionPopUpButton: ButtonActionPullDown {
    var onFocusChange: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { onFocusChange?(true) }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { onFocusChange?(false) }
        return resigned
    }
}

final class MouseGestureSettingsControls: NSObject {

    /// Identifiers for the controls (tests and accessibility tooling).
    enum Identifier {
        static let mode = NSUserInterfaceItemIdentifier("gesture-mode")
        /// The explanation under "Mode" in the Gestures pane.
        static let modeNote = NSUserInterfaceItemIdentifier("gesture-mode-note")
        /// "Up and Down follow the hand too".
        static let followActions = NSUserInterfaceItemIdentifier("gesture-follow-actions")
        static let invertHorizontal = NSUserInterfaceItemIdentifier("gesture-invert-horizontal")
        static let freezePointer = NSUserInterfaceItemIdentifier("gesture-freeze-pointer")
        static let trackingSpeed = NSUserInterfaceItemIdentifier("gesture-tracking-speed")
        static let deviceTracking = NSUserInterfaceItemIdentifier("gesture-device-tracking")
        static let haptics = NSUserInterfaceItemIdentifier("gesture-haptics")

        static func action(_ direction: String) -> NSUserInterfaceItemIdentifier {
            return NSUserInterfaceItemIdentifier("gesture-action-\(direction)")
        }
    }

    /// Which setting an action popup edits.
    enum Slot: Int, CaseIterable {
        case up, down, left, right, click

        var labelKey: String {
            switch self {
            case .up: return "gesture-direction-up"
            case .down: return "gesture-direction-down"
            case .left: return "gesture-direction-left"
            case .right: return "gesture-direction-right"
            case .click: return "gesture-direction-click"
            }
        }

        /// Stable name for `Identifier.action`.
        var name: String {
            switch self {
            case .up: return "up"
            case .down: return "down"
            case .left: return "left"
            case .right: return "right"
            case .click: return "click"
            }
        }

        /// Sideways rows belong to the swipe in "follow the hand" mode.
        var isHorizontal: Bool {
            return self == .left || self == .right
        }

        /// The direction of a hold the row is for; nil for Click.
        var direction: MouseGestureDirection? {
            switch self {
            case .up: return .up
            case .down: return .down
            case .left: return .left
            case .right: return .right
            case .click: return nil
            }
        }

        var symbol: String {
            switch self {
            case .up: return "↑"
            case .down: return "↓"
            case .left: return "←"
            case .right: return "→"
            case .click: return "●"
            }
        }

        /// Where the action of this row is (before "Invert left and right").
        var path: WritableKeyPath<GestureActions, GestureAction> {
            switch self {
            case .up: return \.up
            case .down: return \.down
            case .left: return \.left
            case .right: return \.right
            case .click: return \.click
            }
        }

        func action(in settings: MouseGestureSettings) -> GestureAction {
            return settings.actions[keyPath: path]
        }

        func value(in settings: MouseGestureSettings) -> String {
            return action(in: settings).action
        }

        func store(_ action: GestureAction, in settings: inout MouseGestureSettings) {
            settings.actions[keyPath: path] = action
        }
    }

    /// Whose gestures the controls edit.
    enum Edited {
        /// Every app's, in the Gestures pane (`Options.shared.gesture`).
        case general
        /// An app's own set, on its page: all of it (`ApplicationGestures`).
        case application(Application)
    }

    /// Segment order of the mode control.
    static let modes: [MouseGestureMode] = [.discrete, .interactive]

    let edited: Edited

    // MARK: - Controls

    let modeControl: NSSegmentedControl
    /// "Up and Down follow the hand too": a switch, named by the row it sits in.
    let followToggle: NSControl
    /// One pull-down per `Slot`, in `Slot.allCases` order.
    private(set) var actionPopUps: [MouseGestureActionPopUpButton] = []
    /// The pull-downs' stand-in bindings keep their identity while the controls live.
    private let slotIDs = Slot.allCases.map { _ in UUID() }
    /// "Invert left and right" and "Freeze pointer": switches, named by the rows they sit in.
    let invertToggle: NSControl
    let freezeToggle: NSControl

    /// Called after a control has written a setting (and the controls show it).
    var onChange: (() -> Void)?
    /// Called when the pop-up of a slot gains (true) or loses the keyboard focus.
    var onFocusChange: ((Slot, Bool) -> Void)?

    /// Starts the recorder of "Keyboard Shortcut…" at a row's pull-down. Tests replace it:
    /// a real recorder taps the system's events.
    var startShortcutRecorder: ((ButtonActionPullDown) -> Void)? {
        didSet {
            actionPopUps.forEach { $0.startShortcutRecorder = startShortcutRecorder }
        }
    }

    /// Also offer Logi actions in the action popups. Changing it rebuilds their menus.
    var showLogiActions: Bool {
        didSet {
            guard showLogiActions != oldValue else { return }
            for popup in actionPopUps {
                popup.use = .gesture(showsLogiActions: showLogiActions)
            }
            applyModePresentation()
        }
    }

    private let isInteractiveAvailable: () -> Bool
    private let followAvailability: () -> DockFollowAvailability

    /// - Parameters:
    ///   - showLogiActions: also offer Logi actions in the action popups.
    ///   - edits: whose gestures the action pop-ups and the invert switch edit.
    ///   - isInteractiveAvailable: whether "Follow the hand" can run at all.
    ///   - followAvailability: what can follow the hand up and down on this Mac now (the
    ///     macOS, the Dock's own switches, the build). Its `swipeIsAvailable` is not read:
    ///     `isInteractiveAvailable` says that, one answer for the mode and for the rows.
    init(
        showLogiActions: Bool,
        edits: Edited = .general,
        isInteractiveAvailable: @escaping () -> Bool = { DockSwipeSynthesizer.shared.isAvailable },
        followAvailability: @escaping () -> DockFollowAvailability = { .live }
    ) {
        self.showLogiActions = showLogiActions
        self.edited = edits
        self.isInteractiveAvailable = isInteractiveAvailable
        self.followAvailability = followAvailability

        modeControl = NSSegmentedControl(
            labels: [
                NSLocalizedString("gesture-mode-discrete", comment: ""),
                NSLocalizedString("gesture-mode-interactive", comment: ""),
            ],
            trackingMode: .selectOne,
            target: nil,
            action: nil
        )
        modeControl.identifier = Identifier.mode
        modeControl.setAccessibilityLabel(NSLocalizedString("gesture-mode-label", comment: ""))

        followToggle = PreferencesGroupedForm.makeSwitch(target: nil, action: nil)
        followToggle.identifier = Identifier.followActions
        invertToggle = PreferencesGroupedForm.makeSwitch(target: nil, action: nil)
        invertToggle.identifier = Identifier.invertHorizontal
        freezeToggle = PreferencesGroupedForm.makeSwitch(target: nil, action: nil)
        freezeToggle.identifier = Identifier.freezePointer

        super.init()

        modeControl.target = self
        modeControl.action = #selector(modeChanged(_:))
        followToggle.target = self
        followToggle.action = #selector(followToggled(_:))
        invertToggle.target = self
        invertToggle.action = #selector(invertToggled(_:))
        freezeToggle.target = self
        freezeToggle.action = #selector(freezeToggled(_:))
        actionPopUps = Slot.allCases.map { makeActionPopUp(for: $0) }
        sync()
    }

    /// On or off.
    static func isOn(_ toggle: NSControl) -> Bool {
        return (toggle as? NSSwitch)?.state == .on
    }

    static func setOn(_ on: Bool, _ toggle: NSControl) {
        (toggle as? NSSwitch)?.state = on ? .on : .off
    }

    /// The popup that edits `slot`.
    func actionPopUp(for slot: Slot) -> MouseGestureActionPopUpButton {
        return actionPopUps[slot.rawValue]
    }

    /// Ends a recording that still waits for a key and closes the popover of a name: the
    /// rows are about to go (the pane is left).
    func endEditing() {
        isEndingEditing = true
        defer { isEndingEditing = false }
        actionPopUps.forEach { $0.cancelShortcutRecording() }
    }

    /// While `endEditing` runs: what it stores (a name typed and not confirmed) takes no
    /// Undo of its own. What ended the editing ("Reset to Defaults") takes it back with the
    /// rest, the name included.
    private var isEndingEditing = false

    // MARK: - Sync

    /// Puts the stored settings and the mode rules into every control.
    func sync() {
        let settings = editedSettings
        Self.setOn(settings.invertHorizontal, invertToggle)
        Self.setOn(settings.freezePointer, freezeToggle)
        applyModePresentation()
    }

    /// The settings the controls show: the general ones, with the app's own set in them on
    /// an app's page.
    var editedSettings: MouseGestureSettings {
        switch edited {
        case .general:
            return Options.shared.gesture
        case .application(let application):
            return application.gesturesThatRun(general: Options.shared.gesture)
        }
    }

    /// Stores the actions and the invert switch of `settings` where the controls edit them.
    private func write(_ settings: MouseGestureSettings) {
        switch edited {
        case .general:
            Options.shared.gesture = settings
        case .application(let application):
            application.setOwnGestures(actions: settings.actions, invertHorizontal: settings.invertHorizontal)
        }
    }

    /// Stores one value where the controls edit: the Gestures pane's, or the app's own (from
    /// then on the app's, also while it equals the general one).
    private func write<Value: Equatable>(
        _ general: WritableKeyPath<MouseGestureSettings, Value>, _ own: WritableKeyPath<ApplicationGestures, Value?>, _ value: Value
    ) {
        switch edited {
        case .general:
            guard Options.shared.gesture[keyPath: general] != value else { return }
            Options.shared.gesture[keyPath: general] = value
        case .application(let application):
            application.changeOwnGestures { $0[keyPath: own] = value }
        }
    }

    /// The swipe speed (its row's slider, already on a tick).
    func setTrackingSpeed(_ speed: Double) {
        write(\.trackingSpeed, \.trackingSpeed, MouseGestureSettings.clampedTrackingSpeed(speed))
    }

    /// "Let the mouse track the gesture".
    func setDeviceTracking(_ tracks: Bool) {
        write(\.deviceTracking, \.deviceTracking, tracks)
    }

    /// "Pulse when a gesture locks in".
    func setHapticFeedback(_ pulses: Bool) {
        write(\.hapticFeedback, \.hapticFeedback, pulses)
    }

    /// What the mode control and the action rows show now: the mode of the settings the
    /// controls edit (an app's own on its page).
    var modePresentation: MouseGestureModePresentation {
        return MouseGestureModePresentation.make(
            storedMode: editedSettings.mode,
            isInteractiveAvailable: isInteractiveAvailable()
        )
    }

    /// What can follow the hand up and down on this Mac now. The swipe is there as the
    /// mode's own answer says: one answer for the mode and for the rows.
    var availability: DockFollowAvailability {
        var value = followAvailability()
        value.swipeIsAvailable = isInteractiveAvailable()
        return value
    }

    /// What the switch "Up and Down follow the hand too", its line and the Up and Down rows
    /// show now.
    var followPresentation: MouseGestureFollowPresentation {
        return MouseGestureFollowPresentation.make(settings: editedSettings, mode: modePresentation, availability: availability)
    }

    /// Every line the switch's row can show on this Mac (the room its row keeps).
    var followHints: [String] {
        return MouseGestureFollowPresentation.hints(majorVersion: followAvailability().majorVersion)
    }

    /// Brings the mode control, the switch under it and the rows of the directions in line
    /// with the mode: Left and Right are the swipe's in "Follow the hand"; Up and Down say
    /// that they follow the hand where they do.
    private func applyModePresentation() {
        let presentation = modePresentation
        if let interactiveSegment = Self.modes.firstIndex(of: .interactive) {
            modeControl.selectedSegment = Self.modes.firstIndex(of: presentation.selectedMode) ?? 0
            modeControl.setEnabled(presentation.isInteractiveSelectable, forSegment: interactiveSegment)
        }

        let settings = editedSettings
        let follow = MouseGestureFollowPresentation.make(settings: settings, mode: presentation, availability: availability)
        Self.setOn(follow.isOn, followToggle)
        followToggle.isEnabled = follow.isEditable
        for popup in actionPopUps {
            guard let slot = Slot(rawValue: popup.tag) else { continue }
            if slot.isHorizontal {
                // The configured action is kept for the discrete mode; it just does not apply now.
                popup.face = presentation.areHorizontalActionsEditable ? nil : Self.followHorizontalValue
                popup.isEnabled = presentation.areHorizontalActionsEditable
            } else if let direction = slot.direction {
                // (The pull-down stays one: its menu, the tick and what is stored are the action's.)
                let row = follow.row(for: direction)
                popup.face = row.face
                popup.note = row.note
            }
            // (An action this version does not run shows "No Action", and stays stored.)
            popup.configure(with: slot.action(in: settings).asBinding(id: slotIDs[slot.rawValue]))
        }
    }

    // MARK: - Action popups

    private func makeActionPopUp(for slot: Slot) -> MouseGestureActionPopUpButton {
        let popup = MouseGestureActionPopUpButton(
            binding: slot.action(in: editedSettings).asBinding(id: slotIDs[slot.rawValue]),
            use: .gesture(showsLogiActions: showLogiActions)
        )
        popup.onFocusChange = { [weak self] focused in
            self?.onFocusChange?(slot, focused)
        }
        popup.tag = slot.rawValue
        popup.identifier = Identifier.action(slot.name)
        popup.setAccessibilityLabel(NSLocalizedString(slot.labelKey, comment: ""))
        popup.onShortcutSelected = { [weak self] shortcut in
            self?.store(GestureAction(action: shortcut?.identifier ?? ""), in: slot)
        }
        popup.onCustomShortcutRecorded = { [weak self] name, label in
            self?.store(GestureAction(action: name, label: label), in: slot)
        }
        return popup
    }

    /// Puts `action` into `slot`. What a direction cannot run (a recorded mouse button, a
    /// modifier key by itself) is not stored: the pull-down shows again what was there.
    /// Edit › Undo of the window puts back what was there (`registerUndo`).
    func store(_ action: GestureAction, in slot: Slot) {
        var settings = editedSettings
        guard action.isEmpty || action.resolvedAction != nil else {
            applyModePresentation()
            return
        }
        guard slot.action(in: settings) != action else {
            applyModePresentation()
            return
        }
        let old = slot.action(in: settings)
        slot.store(action, in: &settings)
        write(settings)
        applyModePresentation()
        onChange?()
        if slot.action(in: editedSettings) == action {
            registerUndo(back: old, from: action, in: slot)
        }
    }

    // MARK: - Undo of a direction

    /// Whose gestures an Undo of a direction changes: the general ones, or an app's own
    /// set, found by the path it is stored with when the Undo runs (an app removed and
    /// added again is a new entry; a set kept for later takes it too, as "Reset to
    /// Defaults" does).
    private enum DirectionOwner {
        case general
        case application(path: String)
    }

    /// Where an Undo of a direction shows what it did: the window's panes; without them
    /// (controls in a window of their own) the controls that made the change. Neither is
    /// held.
    private struct DirectionShowing {
        weak var split: PreferencesSplitViewController?
        weak var controls: MouseGestureSettingsControls?
    }

    /// Registers the step back from `new` to `old` in `slot` on the undo manager of the
    /// window the row is in: "Undo Change Action", or "Undo Rename" when only the name or
    /// the icon of the same recorded key combination changed (as Buttons calls them,
    /// `ButtonRowChange.Kind`). The target is the settings, not these controls: an Undo
    /// after an app's page closed still works.
    private func registerUndo(back old: GestureAction, from new: GestureAction, in slot: Slot) {
        // (A manager that groups only by hand, as a test's, takes a step only inside a group.)
        guard !isEndingEditing, let window = actionPopUp(for: slot).window, let undo = window.undoManager,
              undo.groupsByEvent || undo.groupingLevel > 0 else { return }
        let owner: DirectionOwner
        switch edited {
        case .general:
            owner = .general
        case .application(let application):
            owner = .application(path: application.path)
        }
        let showing = DirectionShowing(split: window.contentViewController as? PreferencesSplitViewController, controls: self)
        Self.registerUndo(back: old, from: new, in: slot, of: owner, undoManager: undo, showing: showing)
    }

    private static func registerUndo(
        back old: GestureAction, from new: GestureAction, in slot: Slot, of owner: DirectionOwner,
        undoManager undo: UndoManager, showing: DirectionShowing
    ) {
        undo.registerUndo(withTarget: Options.shared) { [weak undo] _ in
            guard let result = put(old, in: slot, of: owner) else { return }
            show(slot, of: result.entry, in: showing)
            guard let undo, result.was != old else { return }
            registerUndo(back: result.was, from: old, in: slot, of: owner, undoManager: undo, showing: showing)
        }
        let renames = old.action == new.action && old.label != new.label
        undo.setActionName((renames ? ButtonRowChange.Kind.rename : .action).actionName)
    }

    /// Puts `value` into `slot` of the owner's gestures. What was there, and the app's
    /// entry (nil: the general gestures); nil when the app is no longer on the list or has
    /// no set of its own.
    private static func put(
        _ value: GestureAction, in slot: Slot, of owner: DirectionOwner
    ) -> (was: GestureAction, entry: Application?)? {
        switch owner {
        case .general:
            let was = slot.action(in: Options.shared.gesture)
            if was != value {
                Options.shared.gesture.actions[keyPath: slot.path] = value
            }
            return (was, nil)
        case .application(let path):
            guard let entry = PreferencesApplicationViewController.existingApplication(
                forPaths: PreferencesApplicationViewController.knownPaths(forStoredPath: path)
            ), let was = entry.gestures?.actions[keyPath: slot.path] else { return nil }
            if was != value {
                entry.gestures?.actions[keyPath: slot.path] = value
            }
            return (was, entry)
        }
    }

    /// Shows the direction an Undo or Redo changed where it is: the Gestures pane, or the
    /// app's page under Apps on its Gestures part, comes forward and shows the gestures as
    /// stored, with the direction's row selected (`selectRow`). Not for Left or Right while
    /// the desktops follow the hand: the row shows the swipe and takes no choice, so nothing
    /// there would show the change (the value is back all the same). Nor for an app's set
    /// kept for later (the app uses the general gestures again): its part shows the switch
    /// alone.
    private static func show(_ slot: Slot, of entry: Application?, in showing: DirectionShowing) {
        if let entry, entry.ownGestures == nil { return }
        guard isEditable(slot, of: entry, in: showing) else { return }
        if let split = showing.split {
            if let entry {
                let part = split.bringForward(pageOf: entry, part: .gestures)?.gesturesPart
                part?.syncViewWithOptions()
                part?.controls?.selectRow(of: slot)
            } else {
                let pane = split.bringForward(pane: GesturesPreferencesViewController.tabIdentifier) as? GesturesPreferencesViewController
                pane?.reload()
                pane?.controls?.selectRow(of: slot)
            }
            return
        }
        guard let controls = showing.controls else { return }
        switch controls.edited {
        case .general where entry == nil:
            break
        case .application(let application) where application === entry:
            break
        default:
            return
        }
        controls.sync()
        controls.onChange?()
        controls.selectRow(of: slot)
    }

    /// Whether the row of `slot` takes a choice in the mode of the gestures it belongs to
    /// (the general ones, or the app's as they run), as `applyModePresentation` shows it.
    private static func isEditable(_ slot: Slot, of entry: Application?, in showing: DirectionShowing) -> Bool {
        guard slot.isHorizontal else { return true }
        let general = Options.shared.gesture
        let mode = entry?.gesturesThatRun(general: general).mode ?? general.mode
        let available = showing.controls?.isInteractiveAvailable() ?? DockSwipeSynthesizer.shared.isAvailable
        return MouseGestureModePresentation.make(storedMode: mode, isInteractiveAvailable: available).areHorizontalActionsEditable
    }

    /// The row of `slot` as the one an Undo or Redo changed: a folded section around it
    /// opens, its pull-down comes into view and takes the keyboard (the Gestures pane's
    /// preview then shows that direction), as a place of the ring does (`selectPlace`).
    private func selectRow(of slot: Slot) {
        let popup = actionPopUp(for: slot)
        var ancestor = popup.superview
        while let view = ancestor {
            if let fold = view as? PreferencesDisclosureSection, !fold.showsBody {
                fold.setExpanded(true, animated: true)
                // (The pane refits itself; an app's page measures again.)
                fold.onExpandedChange?(true)
            }
            ancestor = view.superview
        }
        popup.window?.contentView?.layoutSubtreeIfNeeded()
        popup.scrollToVisible(popup.bounds)
        popup.window?.makeFirstResponder(popup)
    }

    /// Actions that make sense as a one-shot gesture: system shortcuts, mouse clicks and,
    /// for Logitech triggers, Logi actions. Hold-style actions (modifier keys, scroll
    /// modes) and Gesture Navigation itself are left out.
    static func actionCategories(showLogiActions: Bool) -> [(category: String, shortcuts: [SystemShortcut.Shortcut])] {
        var categories = SystemShortcut.shortcutsByCategory.map { entry in
            (
                category: entry.category,
                shortcuts: entry.shortcuts.filter {
                    $0.identifier != SystemShortcut.mouseGestureNavigation.identifier
                }
            )
        }
        categories.append(SystemShortcut.mouseButtonsCategory)
        if showLogiActions {
            categories.append(SystemShortcut.logiActionsCategory)
        }
        return categories.filter { !$0.shortcuts.isEmpty }
    }

    /// Shown in the Left / Right rows while the swipe owns sideways movement.
    static var followHorizontalValue: String {
        return NSLocalizedString("gesture-follow-horizontal-value", comment: "")
    }

    // MARK: - Actions

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        guard Self.modes.indices.contains(sender.selectedSegment) else { return }
        let mode = Self.modes[sender.selectedSegment]
        // An unavailable mode cannot be picked, even if the segment were reached another way.
        if mode == .interactive && !isInteractiveAvailable() {
            applyModePresentation()
            return
        }
        write(\.mode, \.mode, mode)
        applyModePresentation()
        onChange?()
    }

    /// "Up and Down follow the hand too": the pane's choice, or the app's own.
    @objc private func followToggled(_ sender: NSControl) {
        write(\.actionsFollowHand, \.actionsFollowHand, Self.isOn(sender))
        applyModePresentation()
        onChange?()
    }

    @objc private func invertToggled(_ sender: NSControl) {
        switch edited {
        case .general:
            Options.shared.gesture.invertHorizontal = Self.isOn(sender)
        case .application:
            var settings = editedSettings
            settings.invertHorizontal = Self.isOn(sender)
            write(settings)
        }
        onChange?()
    }

    @objc private func freezeToggled(_ sender: NSControl) {
        write(\.freezePointer, \.freezePointer, Self.isOn(sender))
        onChange?()
    }
}

// MARK: - The rows

/// The rows of the Gestures pane, made one way for the pane and for an app's page (its
/// Gestures part shows the same rows, in the same order): the titles, the lines under them,
/// the room they keep and the identifiers. What a row writes is the caller's action, which
/// hands the value to its `MouseGestureSettingsControls`.
enum MouseGestureRows {

    private static func text(_ key: String) -> String {
        return NSLocalizedString(key, comment: "")
    }

    /// "Mode": what the selected mode does under the title, the two modes across the box.
    static func mode(_ control: NSSegmentedControl) -> PreferencesGroupRow {
        control.segmentDistribution = .fillEqually
        let row = PreferencesGroupRow(
            title: text("gesture-mode-label"),
            explanation: text(MouseGestureModePresentation.descriptionKeys[0]),
            accessory: control,
            placement: .below
        )
        // Room for the longest line, so picking the other mode never changes the height.
        row.reservedExplanations = MouseGestureModePresentation.descriptionKeys.map(text)
        row.explanationLabel.identifier = MouseGestureSettingsControls.Identifier.modeNote
        return row
    }

    /// "Up and Down follow the hand too (Experimental)", under "Mode": what it does on this
    /// Mac under the title, the switch on the right. Always there, so that picking the
    /// other mode never changes the height; only "Follow the hand" uses it
    /// (`show(_:in:toggle:)`).
    /// - Parameter reserving: every line the row can show (`MouseGestureSettingsControls.followHints`):
    ///   it keeps room for the longest, whatever the mode, the switch and the Dock say.
    static func followActions(_ toggle: NSControl, reserving hints: [String]) -> PreferencesGroupRow {
        let row = PreferencesGroupRow(
            title: text("gesture-follow-actions-label"),
            explanation: hints.first ?? "",
            accessory: toggle
        )
        row.reservedExplanations = hints
        return row
    }

    /// Puts the switch "Up and Down follow the hand too" and its line into their row:
    /// dimmed in "One action per hold", with the line that says so (the stored choice
    /// still shows).
    static func show(_ follow: MouseGestureFollowPresentation, in row: PreferencesGroupRow, toggle: NSControl) {
        MouseGestureSettingsControls.setOn(follow.isOn, toggle)
        row.isEnabled = follow.isEditable
        row.explanation = follow.hint
    }

    static func invert(_ toggle: NSControl) -> PreferencesGroupRow {
        return PreferencesGroupRow(
            title: text("gesture-invert-horizontal"),
            explanation: text("gesture-invert-horizontal-hint"),
            accessory: toggle
        )
    }

    /// "Freeze pointer during a gesture"; who holds the pointer decides what it shows
    /// (`show(_:stored:keepsRoom:in:toggle:)`).
    static func freeze(_ toggle: NSControl) -> PreferencesGroupRow {
        return PreferencesGroupRow(
            title: text("gesture-freeze-pointer"),
            explanation: text("gesture-freeze-pointer-hint"),
            accessory: toggle
        )
    }

    /// Puts who holds the pointer into the Freeze row: while the mouse does, for every
    /// button that runs the gestures, the switch reads on and is dimmed with the reason
    /// (the kit gives the line to VoiceOver as the switch's help); else it shows `stored`
    /// and can be changed. Display only: nothing is stored, and a dimmed switch sends no
    /// action.
    /// - Parameter keepsRoom: a connected mouse can track a hold, so "Let the mouse track
    ///   the gesture" can change the line: the row keeps room for each of its lines and
    ///   never changes its height under that switch. Without such a mouse the row is as
    ///   it always was.
    static func show(
        _ holder: MouseGesturePointerHolder, stored: Bool, keepsRoom: Bool, in row: PreferencesGroupRow, toggle: NSControl
    ) {
        MouseGestureSettingsControls.setOn(holder.showsFreeze(stored: stored), toggle)
        row.isEnabled = holder.isFreezeEditable
        row.explanation = text(holder.freezeHintKey)
        let reserved = keepsRoom ? MouseGesturePointerHolder.freezeHintKeys.map(text) : []
        if row.reservedExplanations != reserved {
            row.reservedExplanations = reserved
        }
    }

    /// "Swipe speed": the slider stands where the Scrolling pane's sliders stand.
    static func trackingSpeed(target: AnyObject, action: Selector) -> PreferencesSliderRow {
        let row = PreferencesSliderRow(
            title: text("gesture-tracking-speed-label"),
            explanation: text("gesture-tracking-speed-hint"),
            range: MouseGestureSettings.trackingSpeedRange,
            scale: MouseGestureTrackingSpeed.scale,
            ends: (low: text("gesture-tracking-speed-slower"), high: text("gesture-tracking-speed-faster")),
            valueWidth: PreferencesGroupedForm.sliderValueWidth,
            target: target,
            action: action
        )
        row.slider.identifier = MouseGestureSettingsControls.Identifier.trackingSpeed
        row.reservedExplanations = [text("gesture-tracking-speed-hint"), text("gesture-tracking-speed-hint-discrete")]
        return row
    }

    static func deviceTracking(target: AnyObject, action: Selector) -> PreferencesSwitchRow {
        let row = PreferencesSwitchRow(
            title: text("mouse-gesture-device-tracking"),
            explanation: text("mouse-gesture-device-tracking-hint"),
            target: target,
            action: action
        )
        row.toggle.identifier = MouseGestureSettingsControls.Identifier.deviceTracking
        row.reservedExplanations = [text("mouse-gesture-device-tracking-hint"), text("mouse-gesture-device-tracking-unavailable")]
        return row
    }

    static func haptics(target: AnyObject, action: Selector) -> PreferencesSwitchRow {
        let row = PreferencesSwitchRow(
            title: text("mouse-gesture-haptics"),
            explanation: text("mouse-gesture-haptics-hint"),
            target: target,
            action: action
        )
        row.toggle.identifier = MouseGestureSettingsControls.Identifier.haptics
        row.reservedExplanations = [text("mouse-gesture-haptics-hint"), text("mouse-gesture-haptics-unavailable")]
        return row
    }

    /// Puts the speed of `settings` into its row: on the nearer tick (a refresh while the
    /// knob is dragged leaves the knob alone), editable only in "Follow the hand" (it
    /// scales everything that moves with the hand there: the desktops, and what Up and
    /// Down open), with the line that says so.
    static func show(_ settings: MouseGestureSettings, presentation: MouseGestureModePresentation, in row: PreferencesSliderRow) {
        if !row.isTracking {
            row.showValue(settings.trackingSpeed)
        }
        row.valueText = MouseGestureTrackingSpeed.text(settings.trackingSpeed)
        row.isEnabled = presentation.isTrackingSpeedEditable
        row.explanation = text(
            presentation.isTrackingSpeedEditable ? "gesture-tracking-speed-hint" : "gesture-tracking-speed-hint-discrete"
        )
    }

    /// "Haptic feedback is off under Mouse." at the rows' inset and "Show in Mouse" (small) at
    /// the right edge of a box `boxWidth` wide, in the column of its switches: the muted line
    /// under the "Logitech mouse" box, of the pane and of an app's Gestures part. Hidden
    /// until it is shown.
    static func hapticsOffNote(
        boxWidth: CGFloat, target: AnyObject, action: Selector
    ) -> (holder: NSView, label: NSTextField, button: NSButton) {
        let inset = PreferencesGroupedForm.rowHorizontalInset
        let label = NSTextField(wrappingLabelWithString: text("gestures-haptics-off-under-mouse"))
        label.font = PreferencesGroupedForm.explanationFont
        label.textColor = PreferencesGroupedForm.explanationColor(enabled: true)
        label.isSelectable = false
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let button = PreferencesGroupedForm.makePushButton(title: text("gestures-open-mouse"), target: target, action: action)
        button.controlSize = .small
        button.font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small))
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        // The button says where it goes; the line next to it says why.
        button.setAccessibilityHelp(label.stringValue)

        let spacing = PreferencesGroupedForm.controlSpacing
        label.preferredMaxLayoutWidth = max(0, boxWidth - 2 * inset - button.fittingSize.width - spacing)
        let holder = NSView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        holder.isHidden = true
        holder.addSubview(label)
        holder.addSubview(button)
        // Both on one middle line, the line as tall as the taller of the two.
        let middle = label.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        middle.priority = .defaultHigh
        let hug = holder.heightAnchor.constraint(equalToConstant: 0)
        hug.priority = .fittingSizeCompression
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: inset),
            label.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -spacing),
            label.topAnchor.constraint(greaterThanOrEqualTo: holder.topAnchor),
            label.bottomAnchor.constraint(lessThanOrEqualTo: holder.bottomAnchor),
            button.trailingAnchor.constraint(equalTo: holder.trailingAnchor, constant: -inset),
            button.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
            button.topAnchor.constraint(greaterThanOrEqualTo: holder.topAnchor),
            button.bottomAnchor.constraint(lessThanOrEqualTo: holder.bottomAnchor),
            middle, hug,
        ])
        return (holder, label, button)
    }

    /// Puts the two switches of a Logitech mouse of `settings` into their rows, enabled and
    /// explained by what the connected mice can do.
    static func show(
        _ settings: MouseGestureSettings, rules: MouseGestureControlRules,
        deviceTracking: PreferencesSwitchRow, haptics: PreferencesSwitchRow
    ) {
        deviceTracking.isOn = settings.deviceTracking
        deviceTracking.isEnabled = rules.deviceTrackingEnabled
        deviceTracking.explanation = text(rules.deviceTrackingHintKey)
        haptics.isOn = settings.hapticFeedback
        haptics.isEnabled = rules.hapticsEnabled
        haptics.explanation = text(rules.hapticsHintKey)
    }
}
