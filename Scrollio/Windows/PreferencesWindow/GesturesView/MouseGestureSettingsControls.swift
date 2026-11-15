//
//  MouseGestureSettingsControls.swift
//  Mos
//  The controls that edit Options.shared.gesture: mode, one action per direction and
//  click, and the switches for invert left/right and freeze pointer, and where the swipe
//  speed and the two switches of a Logitech mouse are written. The Gestures pane lays them
//  out in its rows (`MouseGestureRows`, the rows themselves); their rules live here. Changes
//  apply immediately.
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
    /// user's locale ("1,25×" with a decimal comma), as the Scrolling pane writes its speeds.
    /// Display only: the stored value is not changed.
    static func text(_ value: Double, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 2
        let number = formatter.string(from: NSNumber(value: value)) ?? ""
        return String(format: NSLocalizedString("scrolling-speed-value", comment: ""), number)
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

    /// - Parameters:
    ///   - showLogiActions: also offer Logi actions in the action popups.
    ///   - edits: whose gestures the action pop-ups and the invert switch edit.
    init(
        showLogiActions: Bool,
        edits: Edited = .general,
        isInteractiveAvailable: @escaping () -> Bool = { DockSwipeSynthesizer.shared.isAvailable }
    ) {
        self.showLogiActions = showLogiActions
        self.edited = edits
        self.isInteractiveAvailable = isInteractiveAvailable

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

        invertToggle = PreferencesGroupedForm.makeSwitch(target: nil, action: nil)
        invertToggle.identifier = Identifier.invertHorizontal
        freezeToggle = PreferencesGroupedForm.makeSwitch(target: nil, action: nil)
        freezeToggle.identifier = Identifier.freezePointer

        super.init()

        modeControl.target = self
        modeControl.action = #selector(modeChanged(_:))
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

    /// Brings the mode control and the Left / Right rows in line with the mode.
    private func applyModePresentation() {
        let presentation = modePresentation
        if let interactiveSegment = Self.modes.firstIndex(of: .interactive) {
            modeControl.selectedSegment = Self.modes.firstIndex(of: presentation.selectedMode) ?? 0
            modeControl.setEnabled(presentation.isInteractiveSelectable, forSegment: interactiveSegment)
        }

        let settings = editedSettings
        for popup in actionPopUps {
            guard let slot = Slot(rawValue: popup.tag) else { continue }
            // (An action this version does not run shows "No Action", and stays stored.)
            popup.configure(with: slot.action(in: settings).asBinding(id: slotIDs[slot.rawValue]))
            guard slot.isHorizontal else { continue }
            popup.isEnabled = presentation.areHorizontalActionsEditable
            if !presentation.areHorizontalActionsEditable, let titleItem = popup.menu?.items.first {
                // The configured action is kept for the discrete mode; it just does not apply now.
                titleItem.attributedTitle = nil
                titleItem.title = Self.followHorizontalValue
                titleItem.image = nil
            }
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
    /// stored, with the direction's row selected (`selectRow`).
    private static func show(_ slot: Slot, of entry: Application?, in showing: DirectionShowing) {
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

    static func invert(_ toggle: NSControl) -> PreferencesGroupRow {
        return PreferencesGroupRow(
            title: text("gesture-invert-horizontal"),
            explanation: text("gesture-invert-horizontal-hint"),
            accessory: toggle
        )
    }

    static func freeze(_ toggle: NSControl) -> PreferencesGroupRow {
        return PreferencesGroupRow(
            title: text("gesture-freeze-pointer"),
            explanation: text("gesture-freeze-pointer-hint"),
            accessory: toggle
        )
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
    /// knob is dragged leaves the knob alone), editable only while the desktops follow the
    /// hand, with the line that says so.
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
