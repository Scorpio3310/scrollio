//
//  MouseGestureSettingsPopover.swift
//  Mos
//  Gesture Navigation settings: action per direction and click, invert left/right,
//  freeze pointer. Changes apply immediately to Options.shared.gesture.
//

import Cocoa

final class MouseGestureSettingsPopover: NSObject, NSPopoverDelegate {

    var onClose: (() -> Void)?

    private var popover: NSPopover?
    private var showLogiActions = false

    private static let contentWidth: CGFloat = 330
    private static let padding: CGFloat = 16
    private static let popupWidth: CGFloat = 210

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

        let rows: [[NSView]] = Slot.allCases.map { slot in
            let label = NSTextField(labelWithString: "\(slot.symbol)  " + NSLocalizedString(slot.labelKey, comment: ""))
            label.alignment = .right
            label.textColor = NSColor.secondaryLabelColor
            return [label, makeActionPopUp(for: slot)]
        }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline

        let separator = NSBox()
        separator.boxType = .separator

        let invert = NSButton(
            checkboxWithTitle: NSLocalizedString("gesture-invert-horizontal", comment: ""),
            target: self,
            action: #selector(invertToggled(_:))
        )
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

        let stack = NSStackView(views: [title, grid, separator, invert, freeze, footnote])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(14, after: title)
        stack.setCustomSpacing(12, after: grid)
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        let padding = Self.padding
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: Self.contentWidth),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: padding),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -padding),
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footnote.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        let vc = NSViewController()
        vc.view = container
        return vc
    }

    // MARK: - Action popups

    private func makeActionPopUp(for slot: Slot) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: true)
        popup.tag = slot.rawValue
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.widthAnchor.constraint(equalToConstant: Self.popupWidth).isActive = true

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

        let popups = popover?.contentViewController?.view.descendantPopUps ?? []
        if let popup = popups.first(where: { $0.tag == slot.rawValue }) {
            updateTitle(of: popup, identifier: identifier)
        }
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

private extension NSView {
    var descendantPopUps: [NSPopUpButton] {
        subviews.flatMap { view -> [NSPopUpButton] in
            if let popup = view as? NSPopUpButton { return [popup] }
            return view.descendantPopUps
        }
    }
}
