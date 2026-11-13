//
//  ShortcutManager.swift
//  Mos
//  快捷键管理器 - 菜单构建和快捷键触发
//  Created by Claude on 2025/9/27.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

/// 快捷键管理器
/// 职责: 构建分级快捷键菜单 (PopUpButton 使用)
class ShortcutManager {

    /// `representedObject` of the items that do more than bind a listed action.
    enum MenuMarker {
        /// "Open App or File…": the caller asks which app or file.
        static let openTarget = "__open__"
        /// "Keyboard Shortcut…": the caller records a key.
        static let keyboardShortcut = "__custom__"
        /// "Show Gesture Settings": the caller shows the Gestures pane.
        static let gestureSettings = "__gestureSettings__"
    }

    /// 创建带图标的 NSImage (SF Symbol)
    private static func createSymbolImage(_ symbolName: String) -> NSImage? {
        return NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
    }

    // MARK: - 菜单构建
    /// 构建分级快捷键菜单 (按分类组织系统快捷键)
    ///
    /// 菜单结构设计:
    /// - 索引0: 占位符 PopUpButton 显示此项,动态更新标题和图标
    /// - 索引1: 分割线 #1 (a pull-down never shows it: its item 0 is the title)
    /// - 索引2: "No Action" - representedObject 为 nil
    /// - 索引3: 分割线 #2 - 分隔操作区和分类菜单
    /// - 索引4+: 分类子菜单 (功能键,应用与窗口等), then Modifier Keys, Mouse Buttons,
    ///   Scrolling and, for a Logitech button, Logitech Mouse; every category with a symbol
    /// - last group, after a separator: "Gesture Navigation" (and "Show Gesture Settings"
    ///   while it is the button's action), "Shortcut Ring", "Open App or File…" and "Keyboard Shortcut…",
    ///   the actions that are configured rather than picked from a list
    ///
    /// - Parameter menu: 目标菜单对象
    /// - Parameter target: 菜单项点击事件的目标对象
    /// - Parameter action: 菜单项点击事件的选择器
    /// - Parameter showLogiActions: the trigger is a Logitech button: offer its actions.
    /// - Parameter showsGestureSettings: Gesture Navigation is the button's action: offer
    ///   "Show Gesture Settings" under it.
    static func buildShortcutMenu(
        into menu: NSMenu,
        target: AnyObject,
        action: Selector,
        showLogiActions: Bool = false,
        showsGestureSettings: Bool = false
    ) {
        // 清空现有菜单项
        menu.removeAllItems()
        menu.autoenablesItems = false

        // 添加占位符 (用于显示当前选中的快捷键)
        // NSPopUpButton 不会自动显示子菜单项标题,必须用占位符模式
        let placeholderItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        menu.addItem(placeholderItem)

        // 添加第一条分割线 (未绑定时会被隐藏)
        menu.addItem(NSMenuItem.separator())

        // 添加"未绑定"选项 (可选菜单项, representedObject 为 nil)
        // 标题会在 menuWillOpen 时根据当前状态动态更新为"未绑定"或"取消绑定"
        let unboundItem = NSMenuItem(title: NSLocalizedString("unbound", comment: ""), action: action, keyEquivalent: "")
        unboundItem.target = target
        unboundItem.representedObject = nil  // nil 表示清除绑定
        menu.addItem(unboundItem)

        // 添加第二条分割线 (分隔"未绑定"操作和分类菜单)
        menu.addItem(NSMenuItem.separator())

        var totalShortcuts = 0

        // 按分类构建分级菜单（顺序由 shortcutsByCategory 数组定义）
        for (categoryIdentifier, shortcuts) in SystemShortcut.shortcutsByCategory {
            // 创建分类主菜单项 (使用本地化名称)
            let categoryName = SystemShortcut.localizedCategoryName(categoryIdentifier)
            let categoryMenuItem = NSMenuItem(title: categoryName, action: nil, keyEquivalent: "")

            // 为分类添加图标 (macOS 11.0+)
            let symbolName = SystemShortcut.categorySymbolName(categoryIdentifier)
            categoryMenuItem.image = createSymbolImage(symbolName)

            // 创建子菜单
            let subMenu = NSMenu(title: categoryName)
            subMenu.autoenablesItems = false

            // 添加该分类下的所有快捷键到子菜单 (保持原始顺序)
            for shortcut in shortcuts {
                let menuKeyEquivalent = shortcut.keyEquivalent

                let shortcutMenuItem = NSMenuItem(
                    title: shortcut.localizedName,
                    action: action,
                    keyEquivalent: menuKeyEquivalent.keyEquivalent
                )
                shortcutMenuItem.keyEquivalentModifierMask = menuKeyEquivalent.modifierMask
                shortcutMenuItem.target = target
                shortcutMenuItem.representedObject = shortcut
                shortcutMenuItem.toolTip = shortcut.localizedName

                // 为快捷键添加图标 (macOS 11.0+)
                shortcutMenuItem.image = createSymbolImage(shortcut.symbolName)

                subMenu.addItem(shortcutMenuItem)
                totalShortcuts += 1
            }

            // 将子菜单关联到分类菜单项
            categoryMenuItem.submenu = subMenu

            // 将分类菜单项添加到主菜单
            menu.addItem(categoryMenuItem)
        }

        // 修饰键分类 (始终显示)
        addCategoryToMenu(
            menu: menu,
            category: SystemShortcut.modifierKeysCategory,
            target: target,
            action: action,
            totalShortcuts: &totalShortcuts
        )

        // 鼠标按键分类 (始终显示)
        addCategoryToMenu(
            menu: menu,
            category: SystemShortcut.mouseButtonsCategory,
            target: target,
            action: action,
            totalShortcuts: &totalShortcuts
        )

        // Scrolling: the hold actions of the Scrolling pane
        addCategoryToMenu(
            menu: menu,
            category: SystemShortcut.mouseScrollCategory,
            target: target,
            action: action,
            totalShortcuts: &totalShortcuts
        )

        // Logitech Mouse: only for a Logitech button
        if showLogiActions {
            addCategoryToMenu(
                menu: menu,
                category: SystemShortcut.logiActionsCategory,
                target: target,
                action: action,
                totalShortcuts: &totalShortcuts
            )
        }

        // 自定义绑定分隔线
        menu.addItem(NSMenuItem.separator())

        // Gesture Navigation: a top-level action with settings of its own (the Gestures
        // tab), not a function key. Its representedObject is the shortcut, so selecting it
        // binds like any item of the categories above.
        let gestureShortcut = SystemShortcut.mouseGestureNavigation
        let gestureItem = NSMenuItem(title: gestureShortcut.localizedName, action: action, keyEquivalent: "")
        gestureItem.target = target
        gestureItem.representedObject = gestureShortcut
        gestureItem.toolTip = NSLocalizedString("gesture-navigation-menu-tooltip", comment: "")
        gestureItem.image = createSymbolImage(gestureShortcut.symbolName)
        menu.addItem(gestureItem)
        totalShortcuts += 1

        if showsGestureSettings {
            let settingsItem = NSMenuItem(
                title: NSLocalizedString("buttons-show-gesture-settings", comment: ""),
                action: action,
                keyEquivalent: ""
            )
            settingsItem.target = target
            settingsItem.representedObject = MenuMarker.gestureSettings as NSString
            settingsItem.image = createSymbolImage("slider.horizontal.3")
            menu.addItem(settingsItem)
        }

        // The Shortcut Ring: like Gesture Navigation an action that is no key, with a pane
        // of its own for what it holds. A mouse button or a key can have it.
        let ringShortcut = SystemShortcut.shortcutRing
        let ringItem = NSMenuItem(title: ringShortcut.localizedName, action: action, keyEquivalent: "")
        ringItem.target = target
        ringItem.representedObject = ringShortcut
        ringItem.toolTip = NSLocalizedString("ring-menu-tooltip", comment: "")
        ringItem.image = createSymbolImage(ringShortcut.symbolName)
        menu.addItem(ringItem)
        totalShortcuts += 1

        // "Open App or File…"
        let openItem = NSMenuItem(
            title: NSLocalizedString("open-target-action", comment: ""),
            action: action,
            keyEquivalent: ""
        )
        openItem.target = target
        openItem.representedObject = MenuMarker.openTarget as NSString
        openItem.image = createSymbolImage("arrow.up.forward.app")
        menu.addItem(openItem)

        // "Keyboard Shortcut…"
        let customItem = NSMenuItem(
            title: NSLocalizedString("custom-shortcut", comment: ""),
            action: action,
            keyEquivalent: ""
        )
        customItem.target = target
        customItem.representedObject = MenuMarker.keyboardShortcut as NSString
        customItem.image = createSymbolImage("keyboard")
        menu.addItem(customItem)

        // macOS 27 hides menu item images unless asked: every action keeps its symbol.
        menu.keepItemImagesVisible()
    }

    /// 将一个分类添加到菜单
    private static func addCategoryToMenu(
        menu: NSMenu,
        category: (category: String, shortcuts: [SystemShortcut.Shortcut]),
        target: AnyObject,
        action: Selector,
        totalShortcuts: inout Int
    ) {
        let categoryName = SystemShortcut.localizedCategoryName(category.category)
        let categoryMenuItem = NSMenuItem(title: categoryName, action: nil, keyEquivalent: "")

        categoryMenuItem.image = createSymbolImage(SystemShortcut.categorySymbolName(category.category))

        let subMenu = NSMenu(title: categoryName)
        subMenu.autoenablesItems = false
        for shortcut in category.shortcuts {
            let menuKeyEquivalent = shortcut.keyEquivalent

            let shortcutMenuItem = NSMenuItem(
                title: shortcut.localizedName,
                action: action,
                keyEquivalent: menuKeyEquivalent.keyEquivalent
            )
            shortcutMenuItem.keyEquivalentModifierMask = menuKeyEquivalent.modifierMask
            shortcutMenuItem.target = target
            shortcutMenuItem.representedObject = shortcut
            shortcutMenuItem.toolTip = shortcut.localizedDescription ?? shortcut.localizedName
            if shortcut.identifier == SystemShortcut.mouseLeftClick.identifier {
                shortcutMenuItem.isEnabled = false
            }

            shortcutMenuItem.image = createSymbolImage(shortcut.symbolName)

            subMenu.addItem(shortcutMenuItem)
            totalShortcuts += 1
        }

        categoryMenuItem.submenu = subMenu
        menu.addItem(categoryMenuItem)
    }

}
