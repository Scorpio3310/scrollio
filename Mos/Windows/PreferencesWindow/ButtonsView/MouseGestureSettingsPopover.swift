//
//  MouseGestureSettingsPopover.swift
//  Mos
//  Gesture Navigation settings: mode, action per direction and click, invert left/right,
//  freeze pointer. Changes apply immediately to Options.shared.gesture.
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

final class MouseGestureSettingsPopover: NSObject, NSPopoverDelegate {

    var onClose: (() -> Void)?

    /// Identifiers for the controls (tests and accessibility tooling).
    enum Identifier {
        static let mode = NSUserInterfaceItemIdentifier("gesture-mode")
        static let modeNote = NSUserInterfaceItemIdentifier("gesture-mode-note")
        static let invertHorizontal = NSUserInterfaceItemIdentifier("gesture-invert-horizontal")

        static func action(_ direction: String) -> NSUserInterfaceItemIdentifier {
            return NSUserInterfaceItemIdentifier("gesture-action-\(direction)")
        }
    }

    private var popover: NSPopover?
    private var showLogiActions = false
    private let isInteractiveAvailable: () -> Bool
    /// Controls of the content view built last; they follow the mode.
    private var actionPopUps: [NSPopUpButton] = []
    private weak var modeControl: NSSegmentedControl?
    private weak var modeNote: NSTextField?

    /// Segment order of the mode control.
    private static let modes: [MouseGestureMode] = [.discrete, .interactive]

    init(isInteractiveAvailable: @escaping () -> Bool = { DockSwipeSynthesizer.shared.isAvailable }) {
        self.isInteractiveAvailable = isInteractiveAvailable
        super.init()
    }

    /// Minimum sizes; long translations widen the popups (up to `maximumPopupWidth`) and the popover.
    private static let contentWidth: CGFloat = 330
    private static let padding: CGFloat = 16
    private static let columnSpacing: CGFloat = 10
    private static let popupWidth: CGFloat = 210
    private static let maximumPopupWidth: CGFloat = 300

    /// Which setting a popup edits.
    private enum Slot: Int, CaseIterable {
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

    // MARK: - Show / hide

    func show(at sourceView: NSView, showLogiActions: Bool) {
        hide()
        self.showLogiActions = showLogiActions

        let popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = makeContentViewController()
        popover.show(relativeTo: sourceView.bounds, of: sourceView, preferredEdge: .maxY)
        self.popover = popover
    }

    func hide() {
        popover?.close()
        popover = nil
    }

    func popoverDidClose(_ notification: Notification) {
        popover = nil
        onClose?()
    }

    // MARK: - View construction

    func makeContentViewController() -> NSViewController {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: NSLocalizedString("mouseGestureNavigation", comment: ""))
        title.font = NSFont.boldSystemFont(ofSize: 13)

        let mode = NSSegmentedControl(
            labels: [
                NSLocalizedString("gesture-mode-discrete", comment: ""),
                NSLocalizedString("gesture-mode-interactive", comment: ""),
            ],
            trackingMode: .selectOne,
            target: self,
            action: #selector(modeChanged(_:))
        )
        mode.identifier = Identifier.mode
        // Spans the popover; each segment as wide as its label needs.
        mode.segmentDistribution = .fillProportionally

        let modeNote = NSTextField(wrappingLabelWithString: "")
        modeNote.identifier = Identifier.modeNote
        modeNote.font = NSFont.systemFont(ofSize: 11)
        modeNote.textColor = NSColor.secondaryLabelColor

        var labels: [NSTextField] = []
        var popups: [NSPopUpButton] = []
        let rows: [[NSView]] = Slot.allCases.map { slot in
            let label = NSTextField(labelWithString: "\(slot.symbol)  " + NSLocalizedString(slot.labelKey, comment: ""))
            label.alignment = .right
            label.textColor = NSColor.secondaryLabelColor
            let popup = makeActionPopUp(for: slot)
            labels.append(label)
            popups.append(popup)
            return [label, popup]
        }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 8
        grid.columnSpacing = Self.columnSpacing
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline

        let separator = NSBox()
        separator.boxType = .separator

        let invert = NSButton(
            checkboxWithTitle: NSLocalizedString("gesture-invert-horizontal", comment: ""),
            target: self,
            action: #selector(invertToggled(_:))
        )
        invert.identifier = Identifier.invertHorizontal
        invert.state = Options.shared.gesture.invertHorizontal ? .on : .off

        let freeze = NSButton(
            checkboxWithTitle: NSLocalizedString("gesture-freeze-pointer", comment: ""),
            target: self,
            action: #selector(freezeToggled(_:))
        )
        freeze.state = Options.shared.gesture.freezePointer ? .on : .off

        let footnote = NSTextField(wrappingLabelWithString: NSLocalizedString("gesture-settings-footnote", comment: ""))
        footnote.font = NSFont.systemFont(ofSize: 11)
        footnote.textColor = NSColor.tertiaryLabelColor

        let stack = NSStackView(views: [title, mode, modeNote, grid, separator, invert, freeze, footnote])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(12, after: title)
        stack.setCustomSpacing(6, after: mode)
        stack.setCustomSpacing(14, after: modeNote)
        stack.setCustomSpacing(12, after: grid)
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        // Popups fit the actions shown now (long translated names such as "Move Space Left")
        // and the value the Left / Right rows show in follow mode, within limits; the popover
        // grows with them, with long checkbox titles and with the mode control.
        let labelColumnWidth = ceil(labels.map { $0.fittingSize.width }.max() ?? 0)
        let widestPopup = max(
            popups.map { Self.fittingWidth(of: $0) }.max() ?? 0,
            popups.first.map { Self.fittingWidth(of: $0, title: Self.followHorizontalValue) } ?? 0
        )
        let minimumPopupWidth = min(Self.maximumPopupWidth, max(Self.popupWidth, ceil(widestPopup)))
        let widestCheckbox = ceil([invert, freeze].map { $0.fittingSize.width }.max() ?? 0)
        let contentWidth = max(
            Self.contentWidth,
            2 * Self.padding + labelColumnWidth + Self.columnSpacing + minimumPopupWidth,
            2 * Self.padding + widestCheckbox,
            2 * Self.padding + ceil(mode.fittingSize.width)
        )
        // The popups take the room the labels leave, so every row ends at the right edge,
        // in line with the mode control and the separator.
        let popupWidth = contentWidth - 2 * Self.padding - labelColumnWidth - Self.columnSpacing
        grid.column(at: 0).width = labelColumnWidth
        for popup in popups {
            popup.widthAnchor.constraint(equalToConstant: popupWidth).isActive = true
        }

        let padding = Self.padding
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: contentWidth),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: padding),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -padding),
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footnote.widthAnchor.constraint(equalTo: stack.widthAnchor),
            mode.widthAnchor.constraint(equalTo: stack.widthAnchor),
            modeNote.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        actionPopUps = popups
        modeControl = mode
        self.modeNote = modeNote
        applyModePresentation()

        let vc = NSViewController()
        vc.view = container
        return vc
    }

    // MARK: - Action popups

    private func makeActionPopUp(for slot: Slot) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: true)
        popup.tag = slot.rawValue
        popup.identifier = Identifier.action(slot.name)
        popup.translatesAutoresizingMaskIntoConstraints = false

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

        popup.menu = menu
        updateTitle(of: popup, identifier: slot.value(in: Options.shared.gesture))
        return popup
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
    private static var followHorizontalValue: String {
        return NSLocalizedString("gesture-follow-horizontal-value", comment: "")
    }

    /// Width a popup needs for its current title, or for `title` (without an icon).
    private static func fittingWidth(of popup: NSPopUpButton, title: String? = nil) -> CGFloat {
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

    @objc private func actionSelected(_ sender: NSMenuItem) {
        guard let slot = Slot(rawValue: sender.tag),
              let identifier = sender.representedObject as? String else { return }
        var settings = Options.shared.gesture
        slot.store(identifier, in: &settings)
        Options.shared.gesture = settings

        if let popup = actionPopUps.first(where: { $0.tag == slot.rawValue }) {
            updateTitle(of: popup, identifier: identifier)
        }
    }

    // MARK: - Mode

    private var modePresentation: MouseGestureModePresentation {
        return MouseGestureModePresentation.make(
            storedMode: Options.shared.gesture.mode,
            isInteractiveAvailable: isInteractiveAvailable()
        )
    }

    /// Brings the mode control, its note and the Left / Right rows in line with the mode.
    private func applyModePresentation() {
        let presentation = modePresentation
        if let modeControl, let interactiveSegment = Self.modes.firstIndex(of: .interactive) {
            modeControl.selectedSegment = Self.modes.firstIndex(of: presentation.selectedMode) ?? 0
            modeControl.setEnabled(presentation.isInteractiveSelectable, forSegment: interactiveSegment)
        }
        modeNote?.stringValue = NSLocalizedString(presentation.noteKey, comment: "")

        let settings = Options.shared.gesture
        for popup in actionPopUps {
            guard let slot = Slot(rawValue: popup.tag), slot.isHorizontal else { continue }
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

    private static func symbolImage(_ name: String) -> NSImage? {
        if #available(macOS 11.0, *) {
            return NSImage(systemSymbolName: name, accessibilityDescription: nil)
        }
        return nil
    }
}
