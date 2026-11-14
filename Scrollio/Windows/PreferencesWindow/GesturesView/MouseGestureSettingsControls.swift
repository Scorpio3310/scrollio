//
//  MouseGestureSettingsControls.swift
//  Mos
//  The controls that edit Options.shared.gesture: mode, one action per direction and
//  click, and the switches for invert left/right and freeze pointer. The Gestures pane lays
//  them out in its rows; their rules live here. Changes apply immediately. (The tracking
//  speed is the pane's own.)
//
//  An app's page edits the app's own gestures with the same controls (`Edited.application`):
//  the five actions and "Invert left and right" are then the app's; the mode, which decides
//  what the Left and Right rows show, and the freeze switch stay the Gestures pane's.
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
        /// An app's own set, on its page: its five actions and its "Invert left and right".
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
        actionPopUps.forEach { $0.cancelShortcutRecording() }
    }

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

    /// What the mode control and the action rows show now.
    var modePresentation: MouseGestureModePresentation {
        return MouseGestureModePresentation.make(
            storedMode: Options.shared.gesture.mode,
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
        slot.store(action, in: &settings)
        write(settings)
        applyModePresentation()
        onChange?()
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
        Options.shared.gesture.mode = mode
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
        Options.shared.gesture.freezePointer = Self.isOn(sender)
        onChange?()
    }
}
