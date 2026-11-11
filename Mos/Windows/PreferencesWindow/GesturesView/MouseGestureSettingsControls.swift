//
//  MouseGestureSettingsControls.swift
//  Mos
//  The controls that edit Options.shared.gesture: mode, one action per direction and
//  click, invert left/right, freeze pointer and tracking speed. The Gestures tab and the
//  Gesture Settings popover lay out the same controls, so their rules live here once.
//  Changes apply immediately.
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
    /// Localization key of the note under the mode control.
    var noteKey: String

    /// Tracking speed scales the swipe, so it only applies while the desktop follows the hand.
    var isTrackingSpeedEditable: Bool {
        return selectedMode == .interactive
    }

    /// Without the swipe synthesizer Mos runs discrete whatever is stored, so the control
    /// shows discrete. The stored mode is left alone and applies again once it is available.
    static func make(storedMode: MouseGestureMode, isInteractiveAvailable: Bool) -> MouseGestureModePresentation {
        let selected: MouseGestureMode = isInteractiveAvailable ? storedMode : .discrete
        return MouseGestureModePresentation(
            selectedMode: selected,
            isInteractiveSelectable: isInteractiveAvailable,
            areHorizontalActionsEditable: selected == .discrete,
            noteKey: isInteractiveAvailable
                ? "gesture-mode-interactive-note"
                : "gesture-mode-interactive-unavailable"
        )
    }
}

/// Tracking speed slider: steps, clamping and the value label. Pure.
enum MouseGestureTrackingSpeed {
    static let step = 0.1

    /// Clamps into `MouseGestureSettings.trackingSpeedRange` and rounds to a tenth.
    static func snapped(_ value: Double) -> Double {
        return ScrollTuningControlValues.snapped(value, to: MouseGestureSettings.trackingSpeedRange, step: step)
    }

    /// 1.5 -> "1.5×"
    static func text(_ value: Double) -> String {
        return String(format: "%.1f×", value)
    }
}

final class MouseGestureSettingsControls: NSObject {

    /// Identifiers for the controls (tests and accessibility tooling).
    enum Identifier {
        static let mode = NSUserInterfaceItemIdentifier("gesture-mode")
        static let modeNote = NSUserInterfaceItemIdentifier("gesture-mode-note")
        static let invertHorizontal = NSUserInterfaceItemIdentifier("gesture-invert-horizontal")
        static let freezePointer = NSUserInterfaceItemIdentifier("gesture-freeze-pointer")
        static let trackingSpeed = NSUserInterfaceItemIdentifier("gesture-tracking-speed")

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
    /// Under the mode control: what "Follow the hand" does, or why it cannot be picked.
    let modeNote: NSTextField
    /// One pull-down per `Slot`, in `Slot.allCases` order.
    private(set) var actionPopUps: [NSPopUpButton] = []
    let invertCheckbox: NSButton
    let freezeCheckbox: NSButton
    let trackingSpeedSlider: NSSlider
    let trackingSpeedValueLabel: NSTextField
    /// The slider with its value label to the right.
    let trackingSpeedLine: NSView

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

        modeNote = NSTextField(wrappingLabelWithString: "")
        modeNote.identifier = Identifier.modeNote
        modeNote.font = NSFont.systemFont(ofSize: 11)
        modeNote.textColor = NSColor.secondaryLabelColor
        modeNote.isSelectable = false

        invertCheckbox = NSButton(
            checkboxWithTitle: NSLocalizedString("gesture-invert-horizontal", comment: ""),
            target: nil,
            action: nil
        )
        invertCheckbox.identifier = Identifier.invertHorizontal

        freezeCheckbox = NSButton(
            checkboxWithTitle: NSLocalizedString("gesture-freeze-pointer", comment: ""),
            target: nil,
            action: nil
        )
        freezeCheckbox.identifier = Identifier.freezePointer

        let speed = PreferencesForm.makeSliderLine(
            range: MouseGestureSettings.trackingSpeedRange,
            widestValue: MouseGestureTrackingSpeed.text(MouseGestureSettings.trackingSpeedRange.upperBound),
            target: nil,
            action: nil,
            accessibilityLabel: NSLocalizedString("gesture-tracking-speed-label", comment: "")
        )
        trackingSpeedSlider = speed.slider
        trackingSpeedSlider.identifier = Identifier.trackingSpeed
        trackingSpeedValueLabel = speed.valueLabel
        trackingSpeedLine = speed.line

        super.init()

        modeControl.target = self
        modeControl.action = #selector(modeChanged(_:))
        invertCheckbox.target = self
        invertCheckbox.action = #selector(invertToggled(_:))
        freezeCheckbox.target = self
        freezeCheckbox.action = #selector(freezeToggled(_:))
        trackingSpeedSlider.target = self
        trackingSpeedSlider.action = #selector(trackingSpeedChanged(_:))
        actionPopUps = Slot.allCases.map { makeActionPopUp(for: $0) }
        sync()
    }

    /// The popup that edits `slot`.
    func actionPopUp(for slot: Slot) -> NSPopUpButton {
        return actionPopUps[slot.rawValue]
    }

    // MARK: - Sync

    /// Puts the stored settings and the mode rules into every control.
    func sync() {
        let settings = Options.shared.gesture
        invertCheckbox.state = settings.invertHorizontal ? .on : .off
        freezeCheckbox.state = settings.freezePointer ? .on : .off
        // A refresh arriving mid-drag must not snap the knob back.
        if !PreferencesForm.isTrackingMouse {
            trackingSpeedSlider.doubleValue = settings.trackingSpeed
        }
        trackingSpeedValueLabel.stringValue = MouseGestureTrackingSpeed.text(settings.trackingSpeed)
        applyModePresentation()
    }

    private var modePresentation: MouseGestureModePresentation {
        return MouseGestureModePresentation.make(
            storedMode: Options.shared.gesture.mode,
            isInteractiveAvailable: isInteractiveAvailable()
        )
    }

    /// Brings the mode control, its note, the Left / Right rows and the tracking speed in
    /// line with the mode.
    private func applyModePresentation() {
        let presentation = modePresentation
        if let interactiveSegment = Self.modes.firstIndex(of: .interactive) {
            modeControl.selectedSegment = Self.modes.firstIndex(of: presentation.selectedMode) ?? 0
            modeControl.setEnabled(presentation.isInteractiveSelectable, forSegment: interactiveSegment)
        }
        modeNote.stringValue = NSLocalizedString(presentation.noteKey, comment: "")

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

        trackingSpeedSlider.isEnabled = presentation.isTrackingSpeedEditable
        trackingSpeedValueLabel.textColor = presentation.isTrackingSpeedEditable ? .labelColor : .tertiaryLabelColor
    }

    // MARK: - Action popups

    private func makeActionPopUp(for slot: Slot) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: true)
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

    /// Width a popup needs for its current title, or for `title` (without an icon).
    static func fittingWidth(of popup: NSPopUpButton, title: String? = nil) -> CGFloat {
        guard let title, let titleItem = popup.menu?.items.first else {
            return popup.cell?.cellSize.width ?? popup.fittingSize.width
        }
        let current = (title: titleItem.title, image: titleItem.image)
        titleItem.title = title
        titleItem.image = nil
        defer {
            titleItem.title = current.title
            titleItem.image = current.image
        }
        return popup.cell?.cellSize.width ?? popup.fittingSize.width
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
    }

    @objc private func invertToggled(_ sender: NSButton) {
        Options.shared.gesture.invertHorizontal = sender.state == .on
    }

    @objc private func freezeToggled(_ sender: NSButton) {
        Options.shared.gesture.freezePointer = sender.state == .on
    }

    @objc private func trackingSpeedChanged(_ sender: NSSlider) {
        let value = MouseGestureTrackingSpeed.snapped(sender.doubleValue)
        trackingSpeedValueLabel.stringValue = MouseGestureTrackingSpeed.text(value)
        if Options.shared.gesture.trackingSpeed != value {
            Options.shared.gesture.trackingSpeed = value
        }
    }
}
