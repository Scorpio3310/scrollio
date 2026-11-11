//
//  MouseGestureSettingsControls.swift
//  Mos
//  The controls that edit Options.shared.gesture: mode, one action per direction and
//  click, and the switches for invert left/right and freeze pointer. The Gestures pane lays
//  them out in its rows; their rules live here. Changes apply immediately. (The tracking
//  speed is the pane's own.)
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

    /// Without the swipe synthesizer Mos runs discrete whatever is stored, so the control
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

    /// 1.5 -> "1.5×", 1.25 -> "1.25×": one decimal, two where a quarter needs them.
    static func text(_ value: Double) -> String {
        let tenths = (value * 10).rounded()
        let digits = abs(tenths - value * 10) < 1e-6 ? 1 : 2
        return String(format: "%.\(digits)f×", value)
    }
}

/// An action pop-up that tells when it gains or loses the keyboard focus (the tab's
/// preview shows the gesture of the focused row).
final class MouseGestureActionPopUpButton: NSPopUpButton {
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

        func value(in settings: MouseGestureSettings) -> String {
            switch self {
            case .up: return settings.upAction
            case .down: return settings.downAction
            case .left: return settings.leftAction
            case .right: return settings.rightAction
            case .click: return settings.clickAction
            }
        }

        func store(_ identifier: String, in settings: inout MouseGestureSettings) {
            switch self {
            case .up: settings.upAction = identifier
            case .down: settings.downAction = identifier
            case .left: settings.leftAction = identifier
            case .right: settings.rightAction = identifier
            case .click: settings.clickAction = identifier
            }
        }
    }

    /// Segment order of the mode control.
    static let modes: [MouseGestureMode] = [.discrete, .interactive]

    // MARK: - Controls

    let modeControl: NSSegmentedControl
    /// One pull-down per `Slot`, in `Slot.allCases` order.
    private(set) var actionPopUps: [NSPopUpButton] = []
    /// "Invert left and right" and "Freeze pointer": switches, named by the rows they sit in.
    let invertToggle: NSControl
    let freezeToggle: NSControl

    /// Called after a control has written a setting (and the controls show it).
    var onChange: (() -> Void)?
    /// Called when the pop-up of a slot gains (true) or loses the keyboard focus.
    var onFocusChange: ((Slot, Bool) -> Void)?

    /// Also offer Logi actions in the action popups. Changing it rebuilds their menus.
    var showLogiActions: Bool {
        didSet {
            guard showLogiActions != oldValue else { return }
            for popup in actionPopUps {
                guard let slot = Slot(rawValue: popup.tag) else { continue }
                popup.menu = makeActionMenu(for: slot)
            }
            applyModePresentation()
        }
    }

    private let isInteractiveAvailable: () -> Bool

    /// - Parameter showLogiActions: also offer Logi actions in the action popups.
    init(
        showLogiActions: Bool,
        isInteractiveAvailable: @escaping () -> Bool = { DockSwipeSynthesizer.shared.isAvailable }
    ) {
        self.showLogiActions = showLogiActions
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
    func actionPopUp(for slot: Slot) -> NSPopUpButton {
        return actionPopUps[slot.rawValue]
    }

    // MARK: - Sync

    /// Puts the stored settings and the mode rules into every control.
    func sync() {
        let settings = Options.shared.gesture
        Self.setOn(settings.invertHorizontal, invertToggle)
        Self.setOn(settings.freezePointer, freezeToggle)
        applyModePresentation()
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

        let settings = Options.shared.gesture
        for popup in actionPopUps {
            guard let slot = Slot(rawValue: popup.tag) else { continue }
            guard slot.isHorizontal else {
                updateTitle(of: popup, identifier: slot.value(in: settings))
                continue
            }
            popup.isEnabled = presentation.areHorizontalActionsEditable
            if presentation.areHorizontalActionsEditable {
                updateTitle(of: popup, identifier: slot.value(in: settings))
            } else if let titleItem = popup.menu?.items.first {
                // The configured action is kept for the discrete mode; it just does not apply now.
                titleItem.title = Self.followHorizontalValue
                titleItem.image = nil
            }
        }
    }

    // MARK: - Action popups

    private func makeActionPopUp(for slot: Slot) -> NSPopUpButton {
        let popup = MouseGestureActionPopUpButton(frame: .zero, pullsDown: true)
        popup.onFocusChange = { [weak self] focused in
            self?.onFocusChange?(slot, focused)
        }
        popup.tag = slot.rawValue
        popup.identifier = Identifier.action(slot.name)
        popup.setAccessibilityLabel(NSLocalizedString(slot.labelKey, comment: ""))
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.menu = makeActionMenu(for: slot)
        return popup
    }

    private func makeActionMenu(for slot: Slot) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        // Pull-down popups always show item 0 as their title.
        menu.addItem(NSMenuItem(title: "", action: nil, keyEquivalent: ""))

        let none = NSMenuItem(
            title: NSLocalizedString("gesture-action-none", comment: ""),
            action: #selector(actionSelected(_:)),
            keyEquivalent: ""
        )
        none.target = self
        none.tag = slot.rawValue
        none.representedObject = "" as NSString
        menu.addItem(none)
        menu.addItem(NSMenuItem.separator())

        for category in Self.actionCategories(showLogiActions: showLogiActions) {
            let categoryItem = NSMenuItem(
                title: SystemShortcut.localizedCategoryName(category.category),
                action: nil,
                keyEquivalent: ""
            )
            categoryItem.image = Self.symbolImage(SystemShortcut.categorySymbolName(category.category))
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            for shortcut in category.shortcuts {
                let item = NSMenuItem(
                    title: shortcut.localizedName,
                    action: #selector(actionSelected(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.tag = slot.rawValue
                item.representedObject = shortcut.identifier as NSString
                item.image = Self.symbolImage(shortcut.symbolName)
                submenu.addItem(item)
            }
            categoryItem.submenu = submenu
            menu.addItem(categoryItem)
        }
        return menu
    }

    /// Actions that make sense as a one-shot gesture: system shortcuts, mouse clicks and,
    /// for Logitech triggers, Logi actions. Hold-style actions (modifier keys, Mos scroll
    /// modes) and Gesture Navigation itself are left out.
    static func actionCategories(showLogiActions: Bool) -> [(category: String, shortcuts: [SystemShortcut.Shortcut])] {
        var categories = SystemShortcut.shortcutsByCategory.map { entry in
            (
                category: entry.category,
                shortcuts: entry.shortcuts.filter {
                    $0.isAvailable && $0.identifier != SystemShortcut.mouseGestureNavigation.identifier
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

    private func updateTitle(of popup: NSPopUpButton, identifier: String) {
        guard let titleItem = popup.menu?.items.first else { return }
        if let shortcut = SystemShortcut.getShortcut(named: identifier) {
            titleItem.title = shortcut.localizedName
            titleItem.image = Self.symbolImage(shortcut.symbolName)
        } else {
            titleItem.title = NSLocalizedString("gesture-action-none", comment: "")
            titleItem.image = nil
        }
    }

    private static func symbolImage(_ name: String) -> NSImage? {
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    // MARK: - Actions

    @objc private func actionSelected(_ sender: NSMenuItem) {
        guard let slot = Slot(rawValue: sender.tag),
              let identifier = sender.representedObject as? String else { return }
        var settings = Options.shared.gesture
        slot.store(identifier, in: &settings)
        Options.shared.gesture = settings
        updateTitle(of: actionPopUp(for: slot), identifier: identifier)
        onChange?()
    }

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
        Options.shared.gesture.invertHorizontal = Self.isOn(sender)
        onChange?()
    }

    @objc private func freezeToggled(_ sender: NSControl) {
        Options.shared.gesture.freezePointer = Self.isOn(sender)
        onChange?()
    }
}
