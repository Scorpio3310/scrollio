//
//  SystemShortcut.swift
//  Mos
//  系统快捷键组合常量定义
//  Created by 陈标 on 2025/8/28.
//  Copyright © 2025 Caldis. All rights reserved.
//

import Cocoa

enum ActionExecutionMode {
    case trigger
    case stateful
}

/// 系统快捷键组合存储结构
/// 使用 快捷键名称 = (修饰键, 主键) 的方式组织
struct SystemShortcut {

    // MARK: - 快捷键数据结构

    /// 快捷键组合结构
    struct Shortcut: Equatable, Hashable {
        let identifier: String  // 本地化键名(如 "minimizeWindow")
        let code: UInt16
        let modifiers: NSEvent.ModifierFlags
        let executionMode: ActionExecutionMode
        let preserveFlagsOnKeyUp: Bool  // KeyUp 时是否保留修饰键 flags (用于 Command+Tab 等需要保持修饰键的快捷键)
        let descriptionKey: String?  // 菜单描述文本的本地化键 (仅 Logi 动作使用)

        init(
            _ identifier: String,
            _ code: UInt16,
            _ modifiers: NSEvent.ModifierFlags,
            executionMode: ActionExecutionMode = .trigger,
            preserveFlagsOnKeyUp: Bool = false,
            descriptionKey: String? = nil
        ) {
            self.identifier = identifier
            self.code = code
            self.modifiers = modifiers
            self.executionMode = executionMode
            self.preserveFlagsOnKeyUp = preserveFlagsOnKeyUp
            self.descriptionKey = descriptionKey
        }

        /// The letter of a letter shortcut, in lower case ("a" for ⌘A, "z" for ⇧⌘Z); nil for
        /// every other shortcut and for the actions that are no keys. `code` is that
        /// letter's key on the US layout; what is sent is the key that types the letter on
        /// the layout in use (`KeyboardLayoutKeys.keyCode(for:)`). Digits, arrows, Tab,
        /// Space, Esc, Delete and the F-keys are the same keys on every layout.
        var letter: String? {
            return KeyCode.usLetters[code]
        }

        /// 获取本地化描述文本 (用于菜单项下方的灰色说明行)
        var localizedDescription: String? {
            guard let key = descriptionKey else { return nil }
            return NSLocalizedString(key, comment: "")
        }

        /// 获取本地化显示名称
        var localizedName: String {
            let majorVersion = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
            return NSLocalizedString(Self.nameKey(of: identifier, onMacOS: majorVersion), comment: "")
        }

        /// The catalog key of an action's name on macOS `majorVersion`: its identifier, except
        /// for the F4 key (`appExpose`), which opens Launchpad before macOS 26 and Apps, which
        /// replaced Launchpad, from macOS 26 on. Display only: the identifier, what the action
        /// sends and stored bindings stay the same.
        static func nameKey(of identifier: String, onMacOS majorVersion: Int) -> String {
            if identifier == "appExpose", majorVersion >= 26 {
                return "appExposeApps"
            }
            return identifier
        }

        /// 获取 SF Symbol 图标名称 (macOS 11.0+)
        var symbolName: String {
            switch identifier {
                // 功能键
                case "missionControl": return "square.grid.3x2"
                case "appExpose": return "square.grid.3x3"
                case "spotlightSys": return "magnifyingglass.circle"
                case "dictation": return "mic"
                case "doNotDisturb": return "moon"
                case "showDesktop": return "rectangle.on.rectangle"
                case "escapeKey": return "escape"
                // 应用切换
                case "switchApp": return "arrow.right.circle"
                case "switchAppReverse": return "arrow.left.circle"
                // 文档编辑
                case "copy": return "doc.on.doc"
                case "paste": return "doc.on.clipboard"
                case "cut": return "scissors"
                case "undo": return "arrow.uturn.backward"
                case "redo": return "arrow.uturn.forward"
                case "selectAll": return "selection.pin.in.out"
                case "find": return "magnifyingglass"
                case "bold": return "bold"
                case "italic": return "italic"
                case "underline": return "underline"
                // Finder 操作
                case "newFinderWindow": return "macwindow.badge.plus"
                case "moveToTrash": return "trash"
                case "emptyTrash": return "trash.slash"
                case "duplicateFile": return "plus.square.on.square"
                case "getInfo": return "info.circle"
                case "newFolder": return "folder.badge.plus"
                case "goToFolder": return "folder.badge.gearshape"
                case "viewAsIcons": return "square.grid.2x2"
                case "viewAsList": return "list.bullet"
                case "viewAsColumns": return "rectangle.split.3x1"
                case "viewAsGallery": return "square.grid.3x3.fill.square"
                // 系统控制
                case "spotlight": return "magnifyingglass"
                case "characterViewer": return "face.smiling"
                case "forceQuit": return "exclamationmark.triangle"
                case "lockScreen": return "lock.shield"
                case "logout": return "rectangle.portrait.and.arrow.right"
                case "shutdownDialog": return "power"
                case "screenshot": return "camera.viewfinder"
                case "screenshotSelection": return "viewfinder.rectangular"
                case "screenshotAndRecording": return "camera.metering.center.weighted"
                case "moveSpaceLeft": return "arrow.left.to.line"
                case "moveSpaceRight": return "arrow.right.to.line"
                // 窗口管理
                case "minimizeWindow": return "minus.rectangle"
                case "hideApplication": return "eye.slash"
                case "hideOthers": return "eye.slash.circle"
                case "nextWindow": return "arrow.right.square"
                case "closeWindow": return "xmark.rectangle"
                case "closeAllWindows": return "xmark.circle.fill"
                case "quitApp": return "power.circle"
                // 标签与导航
                case "navigateBack": return "chevron.backward"
                case "navigateForward": return "chevron.forward"
                case "nextTab": return "rectangle.on.rectangle"
                case "previousTab": return "rectangle.fill.on.rectangle.fill"
                case "switchTabRight": return "arrow.right.circle"
                case "switchTabLeft": return "arrow.left.circle"
                // 辅助功能
                case "invertColors": return "circle.lefthalf.filled.inverse"
                case "zoomIn": return "plus.magnifyingglass"
                case "zoomOut": return "minus.magnifyingglass"
                // 鼠标按键
                case "mouseLeftClick": return "cursorarrow.click"
                case "mouseRightClick": return "cursorarrow.click.2"
                case "mouseMiddleClick": return "computermouse"
                case "mouseBackClick": return "chevron.backward"
                case "mouseForwardClick": return "chevron.forward"
                case "mouseGestureNavigation": return "arrow.up.and.down.and.arrow.left.and.right"
                case "shortcutRing": return "circle.grid.cross"
                // Mos 鼠标滚动
                case "scrollDash": return "speedometer"
                case "scrollSlow": return "tortoise"
                case "scrollToggle": return "arrow.left.arrow.right"
                case "scrollBlock": return "hand.raised"
                // 修饰键
                case "modifierShift": return "shift"
                case "modifierOption": return "option"
                case "modifierControl": return "control"
                case "modifierCommand": return "command"
                case "modifierFn": return "fn"
                // Logi
                case "logiSmartShiftToggle": return "gearshape.2"
                case "logiDPICycleUp": return "arrow.up.circle"
                case "logiDPICycleDown": return "arrow.down.circle"
                case "logiHost1": return "1.circle"
                case "logiHost2": return "2.circle"
                case "logiHost3": return "3.circle"
                case "logiHiResScrollToggle": return "lines.measurement.vertical"
                case "logiScrollInvertToggle": return "arrow.up.arrow.down"
                case "logiThumbWheelToggle": return "dial.low"
                case "logiPointerSpeedCycle": return "cursorarrow.motionlines"
                // 其他
                default: return "questionmark.circle"
            }
        }

        /// Equatable 协议实现
        static func == (lhs: Shortcut, rhs: Shortcut) -> Bool {
            return lhs.code == rhs.code && lhs.modifiers == rhs.modifiers
        }

        /// Hashable 协议实现
        func hash(into hasher: inout Hasher) {
            hasher.combine(modifiers.rawValue)
            hasher.combine(code)
        }

        /// 获取 NSMenuItem 的 keyEquivalent 和 modifierMask
        var keyEquivalent: (keyEquivalent: String, modifierMask: NSEvent.ModifierFlags) {
            // 对于 Function 键，不设置 keyEquivalent，避免显示问题
            if modifiers.contains(.function) {
                return ("", [])
            }

            // 获取主键字符
            var keyEquivalent = ""
            if let keyName = KeyCode.keyMap[code] {
                // 对于字母键使用小写
                if keyName.count == 1 && keyName.rangeOfCharacter(from: .letters) != nil {
                    keyEquivalent = keyName.lowercased()
                } else {
                    // 对于特殊键（如空格、回车等）保持原样
                    keyEquivalent = keyName
                }
            }

            // 转换修饰键
            var modifierMask: NSEvent.ModifierFlags = []
            if modifiers.contains(.command) {
                modifierMask.insert(.command)
            }
            if modifiers.contains(.shift) {
                modifierMask.insert(.shift)
            }
            if modifiers.contains(.option) {
                modifierMask.insert(.option)
            }
            if modifiers.contains(.control) {
                modifierMask.insert(.control)
            }

            return (keyEquivalent, modifierMask)
        }
    }

    // MARK: - 快捷键
    // 功能键
    static let missionControl = Shortcut("missionControl", 160, .function)
    static let appExpose = Shortcut("appExpose", 131, .function)
    static let spotlightSys = Shortcut("spotlightSys", 177, .function)
    static let dictation = Shortcut("dictation", 176, .function)
    static let doNotDisturb = Shortcut("doNotDisturb", 178, .function)
    static let showDesktop = Shortcut("showDesktop", 103, .function)
    static let escapeKey = Shortcut("escapeKey", KeyCode.escape, [])

    // 应用切换
    // preserveFlagsOnKeyUp: 用于确保 KeyUp 时携带 flag, 才能触发 App Switcher
    // @see https://stackoverflow.com/questions/36375080/cocoa-simulating-commandtab-in-cgevent
    static let switchApp = Shortcut("switchApp", 48, .command, preserveFlagsOnKeyUp: true)
    static let switchAppReverse = Shortcut("switchAppReverse", 48, [.command, .shift], preserveFlagsOnKeyUp: true)

    // 文档编辑
    static let copy = Shortcut("copy", 8, .command)  // Command-C
    static let paste = Shortcut("paste", 9, .command)  // Command-V
    static let cut = Shortcut("cut", 7, .command)  // Command-X
    static let undo = Shortcut("undo", 6, .command)  // Command-Z
    static let redo = Shortcut("redo", 6, [.command, .shift])  // Command-Shift-Z
    static let selectAll = Shortcut("selectAll", 0, .command)  // Command-A
    static let find = Shortcut("find", 3, .command)  // Command-F
    static let bold = Shortcut("bold", 11, .command)  // Command-B
    static let italic = Shortcut("italic", 34, .command)  // Command-I
    static let underline = Shortcut("underline", 32, .command)  // Command-U

    // Finder 操作
    static let newFinderWindow = Shortcut("newFinderWindow", 45, .command)  // Command-N
    static let moveToTrash = Shortcut("moveToTrash", 51, .command)  // Command-Delete
    static let emptyTrash = Shortcut("emptyTrash", 51, [.command, .shift])  // Command-Shift-Delete
    static let duplicateFile = Shortcut("duplicateFile", 2, .command)  // Command-D
    static let getInfo = Shortcut("getInfo", 34, [.command])  // Command-I (Finder only, conflicts with italic)
    static let newFolder = Shortcut("newFolder", 45, [.command, .shift])  // Command-Shift-N
    static let goToFolder = Shortcut("goToFolder", 5, [.command, .shift])  // Command-Shift-G
    static let viewAsIcons = Shortcut("viewAsIcons", 18, .command)  // Command-1
    static let viewAsList = Shortcut("viewAsList", 19, .command)  // Command-2
    static let viewAsColumns = Shortcut("viewAsColumns", 20, .command)  // Command-3
    static let viewAsGallery = Shortcut("viewAsGallery", 21, .command)  // Command-4

    // 系统控制
    static let spotlight = Shortcut("spotlight", 49, .command)  // Command-Space
    static let characterViewer = Shortcut("characterViewer", 49, [.control, .command])  // Control-Command-Space (macOS 10.9+)
    static let forceQuit = Shortcut("forceQuit", 53, [.command, .option])  // Command-Option-Esc
    static let lockScreen = Shortcut("lockScreen", 12, [.command, .control])  // Command-Control-Q
    static let logout = Shortcut("logout", 12, [.command, .shift])  // Command-Shift-Q
    /// Retired (`retiredIdentifiers`): it was sent as Control-Z, a placeholder for
    /// Control-Power. No dialog came up, and the app in front got ⌃Z (in Terminal that
    /// suspends the running command). The entry stays so that a stored binding keeps its
    /// name; nothing is sent for it.
    static let shutdownDialog = Shortcut("shutdownDialog", 6, .control)
    static let screenshot = Shortcut("screenshot", 20, [.command, .shift])  // Command-Shift-3
    static let screenshotSelection = Shortcut("screenshotSelection", 21, [.command, .shift])  // Command-Shift-4
    static let screenshotAndRecording = Shortcut("screenshotAndRecording", 23, [.command, .shift])  // Command-Shift-5
    static let moveSpaceLeft = Shortcut("moveSpaceLeft", 123, [.control, .function])  // Fn-Control-Left
    static let moveSpaceRight = Shortcut("moveSpaceRight", 124, [.control, .function])  // Fn-Control-Right

    // 窗口管理
    static let minimizeWindow = Shortcut("minimizeWindow", 46, .command)  // Command-M
    static let hideApplication = Shortcut("hideApplication", 4, .command)  // Command-H
    static let hideOthers = Shortcut("hideOthers", 4, [.command, .option])  // Command-Option-H
    static let nextWindow = Shortcut("nextWindow", 50, .command)  // Command-`
    static let closeWindow = Shortcut("closeWindow", 13, .command)  // Command-W
    static let closeAllWindows = Shortcut("closeAllWindows", 13, [.command, .option])  // Command-Option-W
    static let quitApp = Shortcut("quitApp", 12, .command)  // Command-Q

    // FIX: Back/Forward - Use Command + Arrow Keys
    // Replaces Brackets (33/30) which are broken on German keyboards.
    static let navigateBack = Shortcut("navigateBack", 123, .command)  // Command-LeftArrow
    static let navigateForward = Shortcut("navigateForward", 124, .command)  // Command-RightArrow
    // Next / Previous Tab: Control-Tab and Control-Shift-Tab, the tab keys of every app with
    // tabs (browsers, Finder, Terminal, window tabs), as the thumb wheel sends them. They
    // were ⇧⌘→ / ⇧⌘←, which select text to the end of the line in a text field and are no
    // tab shortcut in Chrome or Finder. (Before that ⇧⌘] / ⇧⌘[, which are other keys on a
    // German keyboard.)
    static let nextTab = Shortcut("nextTab", 48, .control)  // Control-Tab
    static let previousTab = Shortcut("previousTab", 48, [.control, .shift])  // Control-Shift-Tab
    static let switchTabRight = Shortcut("switchTabRight", 124, [.command, .option])  // Command-Option-Right
    static let switchTabLeft = Shortcut("switchTabLeft", 123, [.command, .option])  // Command-Option-Left

    // 辅助功能
    static let invertColors = Shortcut("invertColors", 28, [.command, .option, .control])  // Command-Option-Control-8
    static let zoomIn = Shortcut("zoomIn", 24, [.command, .option])  // Command-Option-=
    static let zoomOut = Shortcut("zoomOut", 27, [.command, .option])  // Command-Option--

    // MARK: - 辅助方法

    /// 所有系统快捷键的集合
    static let allShortcuts: [String: Shortcut] = [
        // 功能键
        "missionControl": missionControl, "appExpose": appExpose,
        "spotlightSys": spotlightSys, "dictation": dictation, "doNotDisturb": doNotDisturb,
        "showDesktop": showDesktop, "escapeKey": escapeKey,
        // 应用切换
        "switchApp": switchApp, "switchAppReverse": switchAppReverse,
        // 文档编辑
        "copy": copy, "paste": paste, "cut": cut, "undo": undo, "redo": redo,
        "selectAll": selectAll, "find": find, "bold": bold, "italic": italic, "underline": underline,
        // Finder 操作
        "newFinderWindow": newFinderWindow, "moveToTrash": moveToTrash, "emptyTrash": emptyTrash,
        "duplicateFile": duplicateFile, "getInfo": getInfo, "newFolder": newFolder, "goToFolder": goToFolder,
        "viewAsIcons": viewAsIcons, "viewAsList": viewAsList, "viewAsColumns": viewAsColumns, "viewAsGallery": viewAsGallery,
        // 系统控制
        "spotlight": spotlight, "characterViewer": characterViewer,
        "forceQuit": forceQuit, "lockScreen": lockScreen, "logout": logout,
        "shutdownDialog": shutdownDialog, "screenshot": screenshot, "screenshotSelection": screenshotSelection,
        "screenshotAndRecording": screenshotAndRecording,
        "moveSpaceLeft": moveSpaceLeft, "moveSpaceRight": moveSpaceRight,
        // 窗口管理
        "minimizeWindow": minimizeWindow, "hideApplication": hideApplication,
        "hideOthers": hideOthers, "nextWindow": nextWindow, "closeWindow": closeWindow,
        "closeAllWindows": closeAllWindows, "quitApp": quitApp,
        // 标签导航
        "navigateBack": navigateBack, "navigateForward": navigateForward,
        "nextTab": nextTab, "previousTab": previousTab,
        "switchTabLeft": switchTabLeft, "switchTabRight": switchTabRight,
        // 辅助功能
        "invertColors": invertColors, "zoomIn": zoomIn, "zoomOut": zoomOut,
        // 鼠标按键
        "mouseLeftClick": mouseLeftClick, "mouseRightClick": mouseRightClick,
        "mouseMiddleClick": mouseMiddleClick, "mouseBackClick": mouseBackClick,
        "mouseForwardClick": mouseForwardClick, "mouseGestureNavigation": mouseGestureNavigation,
        "shortcutRing": shortcutRing,
        // Mos 鼠标滚动
        "scrollDash": scrollDash,
        "scrollSlow": scrollSlow,
        "scrollToggle": scrollToggle,
        "scrollBlock": scrollBlock,
        // 修饰键
        "modifierShift": modifierShift, "modifierOption": modifierOption,
        "modifierControl": modifierControl, "modifierCommand": modifierCommand,
        "modifierFn": modifierFn,
        // Logi
        "logiSmartShiftToggle": logiSmartShiftToggle,
        "logiDPICycleUp": logiDPICycleUp, "logiDPICycleDown": logiDPICycleDown,
        "logiHost1": logiHost1, "logiHost2": logiHost2, "logiHost3": logiHost3,
        "logiHiResScrollToggle": logiHiResScrollToggle,
        "logiScrollInvertToggle": logiScrollInvertToggle,
        "logiThumbWheelToggle": logiThumbWheelToggle,
        "logiPointerSpeedCycle": logiPointerSpeedCycle,
    ]

    /// 根据名称获取快捷键
    static func getShortcut(named: String) -> Shortcut? {
        return allShortcuts[named]
    }

    /// Actions that are no longer offered and send nothing ("Shut Down…", see
    /// `shutdownDialog`). A binding stored with one keeps its name in the list and its button
    /// stays taken; a press runs nothing. A recorded shortcut is never shown as one.
    static let retiredIdentifiers: Set<String> = ["shutdownDialog"]

    static func isRetired(_ identifier: String) -> Bool {
        return retiredIdentifiers.contains(identifier)
    }

    /// 按类别分组的快捷键 (有序数组,顺序即菜单显示顺序)
    /// Grouped by what the actions do, not by how they are sent: "Mission Control & Spaces"
    /// holds what moves the desktop, the other keys of Apple keyboards (Dictation, Do Not
    /// Disturb) and Escape are under System. Only the menus' order and titles: every action
    /// keeps its identifier, and a stored binding finds it in `allShortcuts` as before.
    /// Gesture Navigation is not a key: the action menu lists it on its own, next to "Open…".
    /// Spotlight is listed once, as ⌘Space under System ("Spotlight"): `spotlightSys`
    /// (the Spotlight key of Apple keyboards, "Spotlight (System)") is no longer offered.
    /// A binding stored with it still runs and shows under its own name (`allShortcuts`).
    static let shortcutsByCategory: [(category: String, shortcuts: [Shortcut])] = [
        ("categoryMissionControlAndSpaces", [
            missionControl, appExpose, showDesktop, moveSpaceLeft, moveSpaceRight
        ]),
        ("categoryAppsAndWindows", [
            switchApp, switchAppReverse,
            minimizeWindow, hideApplication, hideOthers, nextWindow, closeWindow, closeAllWindows, quitApp
        ]),
        ("categoryDocumentEditing", [
            copy, paste, cut, undo, redo, selectAll, find, bold, italic, underline
        ]),
        ("categoryFinderActions", [
            newFinderWindow, moveToTrash, emptyTrash, duplicateFile, getInfo, newFolder, goToFolder,
            viewAsIcons, viewAsList, viewAsColumns, viewAsGallery
        ]),
        ("categorySystem", [
            spotlight, dictation, characterViewer, doNotDisturb, escapeKey,
            forceQuit, lockScreen, logout
        ]),
        ("categoryScreenshot", [
            screenshot, screenshotSelection, screenshotAndRecording
        ]),
        ("categoryNavigation", [
            navigateBack, navigateForward, previousTab, nextTab, switchTabLeft, switchTabRight
        ]),
        // Not offered: the Accessibility shortcuts (`invertColors`, `zoomIn`, `zoomOut`),
        // which did not work reliably. A binding stored with one of them still runs and
        // shows under its own name (`allShortcuts`).
    ]

    // MARK: - Mouse Button Actions
    // 鼠标按键动作 (不是键盘快捷键, 由 ShortcutExecutor 特殊处理)
    // 使用 code=0xFFFF 和空修饰键作为占位, 实际执行逻辑在 ShortcutExecutor 中

    static let mouseLeftClick = Shortcut("mouseLeftClick", 0xFFFF, NSEvent.ModifierFlags(rawValue: 0), executionMode: .stateful)
    static let mouseRightClick = Shortcut("mouseRightClick", 0xFFFF, NSEvent.ModifierFlags(rawValue: 1), executionMode: .stateful)
    static let mouseMiddleClick = Shortcut("mouseMiddleClick", 0xFFFF, NSEvent.ModifierFlags(rawValue: 2), executionMode: .stateful)
    static let mouseBackClick = Shortcut("mouseBackClick", 0xFFFF, NSEvent.ModifierFlags(rawValue: 3), executionMode: .stateful)
    static let mouseForwardClick = Shortcut("mouseForwardClick", 0xFFFF, NSEvent.ModifierFlags(rawValue: 4), executionMode: .stateful)
    static let mouseGestureNavigation = Shortcut(
        "mouseGestureNavigation",
        0xFFFB,
        NSEvent.ModifierFlags(rawValue: 0),
        executionMode: .stateful
    )

    /// Opens the Shortcut Ring at the pointer (`ShortcutRingController`). Like Gesture
    /// Navigation it is no key: `InputProcessor` hands the press and the release of its
    /// trigger to the ring, and the action menu lists it on its own. The same placeholder
    /// code as Gesture Navigation, told apart by the modifiers' raw value.
    static let shortcutRing = Shortcut(
        "shortcutRing",
        0xFFFB,
        NSEvent.ModifierFlags(rawValue: 1),
        executionMode: .stateful
    )

    // MARK: - Scroll Actions
    // Mos 鼠标滚动动作 (由 ShortcutExecutor 转发给 ScrollCore, 保留旧的单热键配置不迁移)
    // 使用 code=0xFFFC 作为占位, modifiers.rawValue 区分滚动功能角色

    static let scrollDash = Shortcut("scrollDash", 0xFFFC, NSEvent.ModifierFlags(rawValue: 0), executionMode: .stateful)
    static let scrollToggle = Shortcut("scrollToggle", 0xFFFC, NSEvent.ModifierFlags(rawValue: 1), executionMode: .stateful)
    static let scrollBlock = Shortcut("scrollBlock", 0xFFFC, NSEvent.ModifierFlags(rawValue: 2), executionMode: .stateful)
    static let scrollSlow = Shortcut("scrollSlow", 0xFFFC, NSEvent.ModifierFlags(rawValue: 3), executionMode: .stateful)

    // MARK: - Modifier Key Actions
    // 预定义单修饰键动作 (复用 custom modifier 的 stateful 执行语义)
    // 使用 code=0xFFFD 和空修饰键作为占位, 实际执行逻辑在 ShortcutExecutor 中映射到对应 modifier keyCode

    static let modifierShift = Shortcut("modifierShift", 0xFFFD, NSEvent.ModifierFlags(rawValue: 0), executionMode: .stateful)
    static let modifierOption = Shortcut("modifierOption", 0xFFFD, NSEvent.ModifierFlags(rawValue: 1), executionMode: .stateful)
    static let modifierControl = Shortcut("modifierControl", 0xFFFD, NSEvent.ModifierFlags(rawValue: 2), executionMode: .stateful)
    static let modifierCommand = Shortcut("modifierCommand", 0xFFFD, NSEvent.ModifierFlags(rawValue: 3), executionMode: .stateful)
    static let modifierFn = Shortcut("modifierFn", 0xFFFD, NSEvent.ModifierFlags(rawValue: 4), executionMode: .stateful)

    // MARK: - Logi HID++ Actions
    // Logitech 专有动作 (由 ShortcutExecutor 通过 HID++ 协议执行)

    static let logiSmartShiftToggle = Shortcut("logiSmartShiftToggle", 0xFFFE, NSEvent.ModifierFlags(rawValue: 0),
        descriptionKey: "logiSmartShiftToggleDesc")
    static let logiDPICycleUp = Shortcut("logiDPICycleUp", 0xFFFE, NSEvent.ModifierFlags(rawValue: 1),
        descriptionKey: "logiDPICycleUpDesc")
    static let logiDPICycleDown = Shortcut("logiDPICycleDown", 0xFFFE, NSEvent.ModifierFlags(rawValue: 2),
        descriptionKey: "logiDPICycleDownDesc")
    static let logiHost1 = Shortcut("logiHost1", 0xFFFE, NSEvent.ModifierFlags(rawValue: 4),
        descriptionKey: "logiHostSwitchDesc")
    static let logiHost2 = Shortcut("logiHost2", 0xFFFE, NSEvent.ModifierFlags(rawValue: 5),
        descriptionKey: "logiHostSwitchDesc")
    static let logiHost3 = Shortcut("logiHost3", 0xFFFE, NSEvent.ModifierFlags(rawValue: 6),
        descriptionKey: "logiHostSwitchDesc")
    static let logiHiResScrollToggle = Shortcut("logiHiResScrollToggle", 0xFFFE, NSEvent.ModifierFlags(rawValue: 7),
        descriptionKey: "logiHiResScrollToggleDesc")
    static let logiScrollInvertToggle = Shortcut("logiScrollInvertToggle", 0xFFFE, NSEvent.ModifierFlags(rawValue: 8),
        descriptionKey: "logiScrollInvertToggleDesc")
    static let logiThumbWheelToggle = Shortcut("logiThumbWheelToggle", 0xFFFE, NSEvent.ModifierFlags(rawValue: 9),
        descriptionKey: "logiThumbWheelToggleDesc")
    static let logiPointerSpeedCycle = Shortcut("logiPointerSpeedCycle", 0xFFFE, NSEvent.ModifierFlags(rawValue: 10),
        descriptionKey: "logiPointerSpeedCycleDesc")

    /// 鼠标按键动作分类
    static let mouseButtonsCategory: (category: String, shortcuts: [Shortcut]) = (
        "categoryMouseButtons", [
            mouseLeftClick, mouseRightClick, mouseMiddleClick, mouseBackClick, mouseForwardClick
        ]
    )

    /// Mos 鼠标滚动动作分类
    static let mouseScrollCategory: (category: String, shortcuts: [Shortcut]) = (
        "categoryMouseScroll", [
            scrollDash, scrollSlow, scrollToggle, scrollBlock
        ]
    )

    /// 修饰键动作分类
    static let modifierKeysCategory: (category: String, shortcuts: [Shortcut]) = (
        "categoryModifierKeys", [
            modifierShift, modifierOption, modifierControl, modifierCommand, modifierFn
        ]
    )

    /// Logi 专有动作分类
    static let logiActionsCategory: (category: String, shortcuts: [Shortcut]) = (
        "categoryLogiActions", [
            logiSmartShiftToggle, logiDPICycleUp, logiDPICycleDown,
            logiHost1, logiHost2, logiHost3,
            // Not offered any more (the Logitech code runs nothing for them): the hi-res,
            // invert and thumb wheel toggles left the mouse changed after Pause and Quit.
            // Their definitions stay so that a stored binding still shows its name.
            logiPointerSpeedCycle
        ]
    )

    /// 获取分类的本地化名称
    static func localizedCategoryName(_ categoryIdentifier: String) -> String {
        return NSLocalizedString(categoryIdentifier, comment: "")
    }

    /// 获取分类的 SF Symbol 图标名称 (macOS 11.0+)
    static func categorySymbolName(_ categoryIdentifier: String) -> String {
        switch categoryIdentifier {
        case "categoryMissionControlAndSpaces": return "rectangle.3.group"
        case "categoryAppsAndWindows": return "macwindow.on.rectangle"
        case "categoryDocumentEditing": return "doc.text"
        case "categoryFinderActions": return "folder"
        case "categorySystem": return "gearshape"
        case "categoryScreenshot": return "camera.viewfinder"
        case "categoryNavigation": return "arrow.left.and.right"
        case "categoryAccessibility": return "eye"
        case "categoryModifierKeys": return "command"
        case "categoryMouseButtons": return "computermouse"
        case "categoryMouseScroll": return "scroll"
        case "categoryLogiActions": return "computermouse"
        default: return "questionmark.folder"
        }
    }

    private static let predefinedModifierCodes: [String: UInt16] = [
        "modifierShift": KeyCode.shiftL,
        "modifierOption": KeyCode.optionL,
        "modifierControl": KeyCode.controlL,
        "modifierCommand": KeyCode.commandL,
        "modifierFn": KeyCode.fnL,
    ]

    private static let predefinedMouseButtonCodes: [UInt16: String] = [
        0: "mouseLeftClick",
        1: "mouseRightClick",
        2: "mouseMiddleClick",
        3: "mouseBackClick",
        4: "mouseForwardClick",
    ]

    static func predefinedModifierCode(for identifier: String) -> UInt16? {
        predefinedModifierCodes[identifier]
    }

    static func predefinedModifierShortcut(matchingCustomBinding customBindingName: String) -> Shortcut? {
        guard let payload = ButtonBinding.normalizedCustomBindingDescriptor(from: customBindingName),
              payload.type == .keyboard,
              payload.modifiers == 0 else {
            return nil
        }
        guard let identifier = predefinedModifierCodes.first(where: { $0.value == payload.code })?.key else {
            return nil
        }
        return getShortcut(named: identifier)
    }

    static func predefinedMouseButtonShortcut(matchingCustomBinding customBindingName: String) -> Shortcut? {
        guard let payload = ButtonBinding.normalizedCustomBindingDescriptor(from: customBindingName),
              payload.type == .mouse,
              payload.modifiers == 0 else {
            return nil
        }
        guard let identifier = predefinedMouseButtonCodes[payload.code] else {
            return nil
        }
        return getShortcut(named: identifier)
    }

    static func displayShortcut(matchingBindingName bindingName: String) -> Shortcut? {
        if let directShortcut = getShortcut(named: bindingName) {
            return directShortcut
        }

        if let mouseShortcut = predefinedMouseButtonShortcut(matchingCustomBinding: bindingName) {
            return mouseShortcut
        }

        if let modifierShortcut = predefinedModifierShortcut(matchingCustomBinding: bindingName) {
            return modifierShortcut
        }

        guard let payload = ButtonBinding.normalizedCustomBindingDescriptor(from: bindingName),
              payload.type == .keyboard else {
            return nil
        }

        // A recorded shortcut carries the key of the keyboard layout it was recorded on, so
        // it is compared with the key each listed shortcut has on the layout in use, not
        // with its US key: on AZERTY a recorded ⌘A (the US Q key) was stored and shown as
        // "Quit App", and ⌘Q as "Select All".
        let layoutKeys = KeyboardLayoutKeys.shared
        let matchingShortcuts = allShortcuts.values.filter { shortcut in
            shortcut.code < 0xFFFB &&  // 0xFFFB... are pseudo actions, not recordable key equivalents
            !isRetired(shortcut.identifier) &&
            layoutKeys.keyCode(for: shortcut) == payload.code &&
            shortcut.modifiers.rawValue == payload.modifiers
        }

        guard matchingShortcuts.count == 1 else {
            return nil
        }

        return matchingShortcuts.first
    }
}

// MARK: - System Configuration Resolver

/// 从symbolichotkeys动态解析系统快捷键配置
extension SystemShortcut {

    /// 系统快捷键ID映射表 (symbolichotkeys -> 快捷键名称)
    private static let symbolicHotkeyMapping: [Int: String] = [
        79: "moveSpaceLeft",   // Move left a space (default: Control-Left)
        80: "moveSpaceLeft",   // Move left a space with shift modifier
        81: "moveSpaceRight",  // Move right a space (default: Control-Right)
        82: "moveSpaceRight",  // Move right a space with shift modifier
    ]

    /// What System Settings says about the shortcuts of interest.
    struct SystemShortcutState {
        /// The user's keys of the shortcuts that are switched on.
        var resolved: [String: (code: CGKeyCode, modifiers: UInt64)] = [:]
        /// The actions whose shortcut the user switched off.
        var switchedOff: Set<String> = []
    }

    /// 缓存的已解析快捷键配置
    private static var systemState: SystemShortcutState = {
        loadSystemShortcuts()
    }()

    /// 获取解析后的系统快捷键配置
    /// - Parameter name: 快捷键名称 (如 "moveSpaceLeft")
    /// - Returns: (keyCode, modifiers) 或 nil
    static func resolveSystemShortcut(_ name: String) -> (code: CGKeyCode, modifiers: UInt64)? {
        return systemState.resolved[name]
    }

    /// Whether the user switched the shortcut of this action off in System Settings ›
    /// Keyboard › Keyboard Shortcuts (only the Spaces actions can be). The action cannot
    /// work then: it is the shortcut that moves the Space.
    static func isSwitchedOffInSystemSettings(_ name: String) -> Bool {
        return systemState.switchedOff.contains(name)
    }

    /// 重新加载系统快捷键配置
    static func reloadSystemShortcuts() {
        systemState = loadSystemShortcuts()
    }

    #if DEBUG
    /// What the lookups answer, for a test; nil reads the system again (nothing under XCTest).
    static func setTestingSystemShortcutState(_ state: SystemShortcutState?) {
        systemState = state ?? loadSystemShortcuts()
    }
    #endif

    /// System Settings, where the user changes these shortcuts.
    static let systemSettingsBundleIdentifier = "com.apple.systempreferences"

    /// Whether the cache is read again after this notification (AppDelegate): Scrollio became
    /// active (its settings opened), or System Settings went to the background, where a
    /// shortcut may just have been changed. The cache used to be read once, so a change was
    /// ignored until the next launch. Never read from an event tap callback.
    static func reloadsSystemShortcuts(after name: Notification.Name, deactivatedBundleIdentifier: String? = nil) -> Bool {
        switch name {
        case NSApplication.didBecomeActiveNotification:
            return true
        case NSWorkspace.didDeactivateApplicationNotification:
            return deactivatedBundleIdentifier == systemSettingsBundleIdentifier
        default:
            return false
        }
    }

    /// The failure is written once per run, not at every reload.
    private static var didLogUnreadableSymbolicHotKeys = false

    /// 从系统配置加载快捷键
    private static func loadSystemShortcuts() -> SystemShortcutState {
        // Under XCTest nothing of the Mac's own settings is read: the tests must not depend
        // on the shortcuts of whoever runs them.
        guard !AppRuntime.isRunningXCTest else { return SystemShortcutState() }
        // 读取系统快捷键配置
        guard let symbolicHotkeys = UserDefaults.standard.persistentDomain(forName: "com.apple.symbolichotkeys"),
              let hotkeys = symbolicHotkeys["AppleSymbolicHotKeys"] as? [String: Any] else {
            if !didLogUnreadableSymbolicHotKeys {
                didLogUnreadableSymbolicHotKeys = true
                AppSystemLog.problem("Could not read the keyboard shortcuts of System Settings: "
                    + "the Spaces actions use the standard keys (Control-Left, Control-Right)")
            }
            return SystemShortcutState()
        }
        return SystemShortcutState(
            resolved: resolvedShortcuts(fromSymbolicHotKeys: hotkeys),
            switchedOff: switchedOffShortcuts(fromSymbolicHotKeys: hotkeys)
        )
    }

    /// The actions whose main shortcut (79: move left a space, 81: move right a space) is
    /// there and switched off. A missing entry is not "off": macOS then uses its default.
    /// Pure: the values are another app's data and may be anything.
    static func switchedOffShortcuts(fromSymbolicHotKeys hotkeys: [String: Any]) -> Set<String> {
        var switchedOff: Set<String> = []
        for hotkeyID in [79, 81] {
            guard let name = symbolicHotkeyMapping[hotkeyID],
                  let config = hotkeys[String(hotkeyID)] as? [String: Any],
                  let enabled = config["enabled"] as? Bool,
                  !enabled else { continue }
            switchedOff.insert(name)
        }
        return switchedOff
    }

    /// The shortcuts of interest in `AppleSymbolicHotKeys` (the dictionary of
    /// com.apple.symbolichotkeys). Pure: the values are another app's data and may be anything.
    static func resolvedShortcuts(fromSymbolicHotKeys hotkeys: [String: Any]) -> [String: (code: CGKeyCode, modifiers: UInt64)] {
        var resolved: [String: (code: CGKeyCode, modifiers: UInt64)] = [:]

        // 解析每个感兴趣的快捷键
        for (hotkeyID, shortcutName) in symbolicHotkeyMapping {
            guard let hotkeyConfig = hotkeys[String(hotkeyID)] as? [String: Any],
                  let enabled = hotkeyConfig["enabled"] as? Bool,
                  enabled,
                  let value = hotkeyConfig["value"] as? [String: Any],
                  let parameters = value["parameters"] as? [Any],
                  parameters.count >= 3 else {
                continue
            }

            // 提取参数
            // parameters[0]: Unicode character (65535 for non-printable)
            // parameters[1]: Virtual key code
            // parameters[2]: Modifier flags
            // These come from System Settings' preferences: a value that is no key code or
            // no flag set (negative, too large) is skipped, not trapped on.
            guard let keyCode = (parameters[1] as? Int).flatMap({ CGKeyCode(exactly: $0) }),
                  let modifiers = (parameters[2] as? Int).flatMap({ UInt64(exactly: $0) }) else {
                continue
            }

            // 只保存主快捷键(ID较小的),避免重复
            // Hotkey 79/81 是主快捷键, 80/82 是带额外修饰键的变体
            if hotkeyID == 79 || hotkeyID == 81 {
                if resolved[shortcutName] == nil {
                    resolved[shortcutName] = (keyCode, modifiers)
                }
            }
        }

        return resolved
    }
}
