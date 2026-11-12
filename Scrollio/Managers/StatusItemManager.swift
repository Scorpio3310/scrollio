//
//  StatusItemManager.swift
//  Mos
//  The menu bar icon and its menu.
//
//  With Accessibility access, top to bottom: one disabled line per Logitech mouse with its
//  battery ("MX Master 4: 75%"), "Smooth Scrolling in Safari" for the app in front (while the
//  event handling runs; `AppSmoothing`), "Pause Scrollio" or "Resume Scrollio", "Settings…",
//  and "Quit Scrollio". While Option is held (always in the debug build) the diagnostic windows
//  are added above Quit: Logitech Diagnostics in every build, Scroll Monitor and Test
//  Toasts only in the debug build. Without the access: "Allow Accessibility Access…" (the
//  Welcome Guide) and Quit.
//
//  In a copy that updates itself (UpdateCenter) "Check for Updates…" follows "Settings…";
//  while a found update waits for an answer, the menu starts with "Update to Scrollio
//  1.1.0…" instead, which brings the updater's window to the front. Both are there
//  without the access too: an update may be what is needed.
//
//  The icon is dimmed while the event handling does not run: paused, the access is missing,
//  or the access is there but an event tap could not be created or stays off because its
//  restarts are throttled (AppRunController, Interceptor). Its tooltip says which.
//
//  While a Logitech mouse's battery is low and not charging, its percentage stands next to the
//  icon ("8%", "Low" for a mouse that reports only levels), the lowest of several mice, and
//  VoiceOver reads "Scrollio, mouse battery 8%". It follows what LogiCenter reports
//  (`mouseStateChanged`) and goes when the mouse charges, recovers or disconnects.
//
//  What the menu lists is decided by `StatusMenu` from a `StatusMenu.State`, and what its
//  items do is in `StatusMenuActions`, so both are tested without a status item.
//
//  Created by Caldis on 2018/3/7.
//  Copyright © 2018年 Caldis. All rights reserved.
//
import Cocoa

class StatusItemManager: NSMenu, NSMenuDelegate {

    // 状态栏引用
    static let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let item = StatusItemManager.statusItem

    /// What the items do.
    let actions = StatusMenuActions()

    private var isOpen = false
    private var observers: [NSObjectProtocol] = []
    /// How the button places its icon without a battery next to it.
    private var plainImagePosition: NSControl.ImagePosition = .imageOnly

    // 初始化
    override func awakeFromNib() {
        // 设置图标/行为
        item.button?.image = #imageLiteral(resourceName: "AppStatusBarIcon")
        plainImagePosition = item.button?.imagePosition ?? .imageOnly
        // 设置事件响应
        item.menu = self
        item.menu?.delegate = self
        observers = [
            NotificationCenter.default.addObserver(
                forName: AppRunController.didChangeNotification,
                object: AppRunController.shared,
                queue: .main
            ) { [weak self] _ in
                self?.updateIcon()
            },
            // A tap whose restarts are refused stays off: the icon says so until it runs again.
            NotificationCenter.default.addObserver(
                forName: Interceptor.restartThrottleDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.updateIcon()
            },
            // What the mice report (also when one connects, disconnects or the Logitech
            // sessions stop): the battery next to the icon, and the answers to the battery
            // read made when the menu opened.
            NotificationCenter.default.addObserver(
                forName: LogiCenter.mouseStateChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                let mice = LogiCenter.shared.mouseDeviceStates()
                self.show(StatusMenu.batteryBadge(for: mice))
                if self.isOpen {
                    StatusMenu.updateBatteryItems(in: self, with: StatusMenu.batteries(from: mice))
                }
            },
        ]
        show(StatusMenu.batteryBadge(for: LogiCenter.shared.mouseDeviceStates()))
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Dims the icon while Scrollio is paused, waits for the access or could not start, and
    /// says why.
    func updateIcon() {
        let controller = AppRunController.shared
        let look = StatusMenu.IconLook(
            coresActive: controller.coresActive,
            isPaused: controller.isPaused,
            startFailed: controller.isRetryingStart,
            tapRestartsThrottled: Interceptor.hasThrottledTap
        )
        item.button?.appearsDisabled = look.appearsDisabled
        item.button?.toolTip = look.toolTip
    }

    /// The battery of a mouse that runs low next to the icon, and the item's name for VoiceOver.
    func show(_ badge: StatusMenu.BatteryBadge) {
        guard let button = item.button else { return }
        if button.title != badge.title {
            button.title = badge.title
            button.imagePosition = badge.title.isEmpty ? plainImagePosition : .imageLeading
        }
        button.setAccessibilityLabel(badge.accessibilityLabel)
    }

    /// The state the menu is built from, read when it opens.
    static func liveState() -> StatusMenu.State {
        let hasAccess = Utils.isHadAccessibilityPermissions()
        #if DEBUG
        let showsDiagnostics = true
        #else
        let showsDiagnostics = NSEvent.modifierFlags.contains(.option)
        #endif
        return StatusMenu.State(
            hasAccess: hasAccess,
            isPaused: AppRunController.shared.isPaused,
            showsDiagnostics: showsDiagnostics,
            batteries: hasAccess ? StatusMenu.batteries(from: LogiCenter.shared.mouseDeviceStates()) : [],
            appSmoothing: hasAccess ? liveAppSmoothingItem() : nil,
            updates: StatusMenu.updates(from: UpdateCenter.shared.status)
        )
    }

    /// "Smooth Scrolling in …" for the app in front. Opening this menu does not change which
    /// app is in front: Scrollio is a menu-bar app.
    static func liveAppSmoothingItem() -> StatusMenu.AppSmoothingItem? {
        let controller = AppRunController.shared
        let running = NSWorkspace.shared.frontmostApplication
        let front = running.map(frontApp)
        let list = Options.shared.application
        return StatusMenu.appSmoothingItem(
            front: front,
            isScrollio: running?.processIdentifier == ProcessInfo.processInfo.processIdentifier,
            scrollingRuns: controller.coresActive && !controller.isPaused && !Interceptor.hasThrottledTap,
            rule: front.map { AppSmoothing.rule(of: AppSmoothing.entry(for: $0, in: list.applications)) } ?? .notListed,
            scrollingSmooth: Options.shared.scroll.smooth,
            limitedToListedApps: list.allowlist
        )
    }

    /// A running app as the menu names and finds it.
    static func frontApp(_ running: NSRunningApplication) -> AppSmoothing.App {
        let bundle = running.bundleURL?.path
        let program = running.executableURL?.path
        return AppSmoothing.App(
            name: running.localizedName ?? Utils.getApplicationName(fromPath: bundle ?? program),
            bundlePath: bundle,
            executablePath: program
        )
    }
}

/**
 * 菜单响应
 **/
extension StatusItemManager {
    // 打开菜单
    func menuWillOpen(_ menu: NSMenu) {
        isOpen = true
        let state = Self.liveState()
        StatusMenu.build(into: self, state: state, actions: actions)
        // Ask the mice again (the battery at most every few minutes); the answers update the
        // battery lines while the menu is open.
        if state.hasAccess {
            LogiCenter.shared.refreshMouseStates()
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        isOpen = false
    }
}

/**
 * 图标显示
 **/
extension StatusItemManager {
    // 显示状态栏图标
    class func showStatusItem() {
        self.statusItem.isVisible = true
    }
    // 隐藏状态栏图标
    class func hideStatusItem() {
        self.statusItem.isVisible = false
    }
}

// MARK: - Content

/// What the status-bar menu lists, and its items. Building a menu opens nothing.
enum StatusMenu {

    /// What the menu is built from.
    struct State: Equatable {
        /// macOS lets Scrollio use the Accessibility API.
        var hasAccess: Bool
        /// Paused from this menu.
        var isPaused: Bool
        /// Option is held, or the debug build: the diagnostic windows are listed.
        var showsDiagnostics: Bool
        /// One line per Logitech mouse that reports its battery.
        var batteries: [Battery]
        /// "Smooth Scrolling in Safari" for the app in front; nil: no such item.
        var appSmoothing: AppSmoothingItem? = nil
        /// What the menu offers of the updater.
        var updates: Updates = .none
        /// The developer tools (Scroll Monitor, Test Toasts) are offered only in the debug build.
        var isDebugBuild: Bool = StatusMenu.isDebugBuild
    }

    /// This build is the debug build.
    static let isDebugBuild: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    /// The diagnostic windows listed while Option is held: Logitech Diagnostics in every
    /// build, the developer tools only in the debug build.
    static func diagnosticItems(isDebugBuild: Bool) -> [Item] {
        return isDebugBuild ? [.scrollMonitor, .diagnostics, .testToasts] : [.diagnostics]
    }

    /// What the menu offers of the updater.
    enum Updates: Equatable {
        /// This copy does not update itself: nothing.
        case none
        /// "Check for Updates…"; disabled while a check runs in the background.
        case check(enabled: Bool)
        /// "Update to Scrollio 1.1.0…": a found update waits for the user's answer.
        case waiting(version: String)
    }

    /// The updater's state as the menu shows it.
    static func updates(from status: UpdateStatus) -> Updates {
        guard status.isAvailable else { return .none }
        if let version = status.waitingVersion {
            return .waiting(version: version)
        }
        return .check(enabled: status.canCheck)
    }

    /// The battery line of one mouse: "MX Master 4: 75%", "MX Master 4: 75%, charging".
    struct Battery: Equatable {
        let title: String
        let symbolName: String
    }

    /// "Smooth Scrolling in Safari", checked while Safari is smoothed; a click changes its
    /// rule (`AppSmoothing.toggle`).
    struct AppSmoothingItem: Equatable {
        let app: AppSmoothing.App
        let title: String
        let isChecked: Bool
        let isEnabled: Bool
    }

    /// The item for the app in front. None without an app in front (or one without a path),
    /// for Scrollio itself, and while Scrollio does not run its event taps (paused, could not
    /// start, a tap kept off): smoothing then is in effect nowhere.
    ///
    /// - Parameters:
    ///   - rule: what the per-app list holds for `front`.
    ///   - scrollingSmooth: "Smooth scrolling" of the Scrolling settings.
    ///   - limitedToListedApps: "Limit scrolling to these apps".
    static func appSmoothingItem(
        front: AppSmoothing.App?, isScrollio: Bool, scrollingRuns: Bool,
        rule: AppSmoothing.Rule, scrollingSmooth: Bool, limitedToListedApps: Bool
    ) -> AppSmoothingItem? {
        guard let front, front.pathToStore != nil, !isScrollio, scrollingRuns else { return nil }
        let decision = AppSmoothing.decide(rule: rule, scrollingSmooth: scrollingSmooth, limitedToListedApps: limitedToListedApps)
        return AppSmoothingItem(
            app: front,
            title: String(format: NSLocalizedString("status-menu-app-smoothing", comment: ""), front.name),
            isChecked: decision.isSmoothed,
            isEnabled: decision.change != nil
        )
    }

    enum Item: Equatable {
        case battery(Battery)
        case appSmoothing(AppSmoothingItem)
        case separator
        case pause
        case resume
        case settings
        case scrollMonitor
        case diagnostics
        case testToasts
        case allowAccess
        case checkForUpdates(enabled: Bool)
        case updateWaiting(version: String)
        case quit
    }

    /// Tag of the battery lines, so they can be updated while the menu is open.
    static let batteryTag = 7_301

    static func items(for state: State) -> [Item] {
        var waiting: [Item] = []
        var check: [Item] = []
        switch state.updates {
        case .none: break
        case .check(let enabled): check = [.checkForUpdates(enabled: enabled)]
        case .waiting(let version): waiting = [.updateWaiting(version: version), .separator]
        }
        guard state.hasAccess else {
            return waiting + [.allowAccess, .separator] + (check.isEmpty ? [] : check + [.separator]) + [.quit]
        }
        var items: [Item] = waiting + state.batteries.map(Item.battery)
        if !state.batteries.isEmpty {
            items.append(.separator)
        }
        if let appSmoothing = state.appSmoothing {
            items += [.appSmoothing(appSmoothing), .separator]
        }
        items += [state.isPaused ? .resume : .pause, .settings] + check + [.separator]
        if state.showsDiagnostics {
            items += diagnosticItems(isDebugBuild: state.isDebugBuild) + [.separator]
        }
        items.append(.quit)
        return items
    }

    /// The battery lines of the connected mice. A mouse that has not reported its battery
    /// (or has none) gets no line.
    static func batteries(from mice: [LogiMouseDeviceState]) -> [Battery] {
        return mice.compactMap { mouse in
            guard let battery = MousePaneModel.battery(mouse.battery) else { return nil }
            let format = NSLocalizedString(battery.isCharging ? "status-menu-battery-charging" : "status-menu-battery", comment: "")
            return Battery(title: String(format: format, mouse.deviceName, battery.text), symbolName: battery.symbolName)
        }
    }

    /// Fills `menu` with the items for `state`; what they do goes to `actions`.
    static func build(into menu: NSMenu, state: State, actions: StatusMenuActions) {
        menu.removeAllItems()
        for item in items(for: state) {
            menu.addItem(makeItem(item, actions: actions))
        }
        // macOS 27 hides menu item images unless asked: the battery lines keep their symbol.
        menu.keepItemImagesVisible()
    }

    /// Updates the battery lines in place while the menu is open. A mouse that came or went
    /// shows the next time the menu opens.
    static func updateBatteryItems(in menu: NSMenu, with batteries: [Battery]) {
        let lines = menu.items.filter { $0.tag == batteryTag }
        guard lines.count == batteries.count else { return }
        for (line, battery) in zip(lines, batteries) {
            line.title = battery.title
            line.image = NSImage(systemSymbolName: battery.symbolName, accessibilityDescription: nil)
        }
    }

    static func makeItem(_ item: Item, actions: StatusMenuActions) -> NSMenuItem {
        func action(_ key: String, _ selector: Selector, shortcut: String = "") -> NSMenuItem {
            let menuItem = NSMenuItem(title: NSLocalizedString(key, comment: ""), action: selector, keyEquivalent: shortcut)
            menuItem.target = actions
            return menuItem
        }
        switch item {
        case .battery(let battery):
            // No action: AppKit shows it disabled.
            let line = NSMenuItem(title: battery.title, action: nil, keyEquivalent: "")
            line.image = NSImage(systemSymbolName: battery.symbolName, accessibilityDescription: nil)
            line.tag = batteryTag
            return line
        case .appSmoothing(let appSmoothing):
            // Without an action AppKit shows it disabled.
            let toggle = NSMenuItem(
                title: appSmoothing.title,
                action: appSmoothing.isEnabled ? #selector(StatusMenuActions.appSmoothingClicked(_:)) : nil,
                keyEquivalent: ""
            )
            toggle.target = actions
            toggle.isEnabled = appSmoothing.isEnabled
            toggle.state = appSmoothing.isChecked ? .on : .off
            toggle.representedObject = appSmoothing.app
            return toggle
        case .separator:
            return .separator()
        case .pause:
            return action("status-menu-pause", #selector(StatusMenuActions.togglePauseClicked(_:)))
        case .resume:
            return action("status-menu-resume", #selector(StatusMenuActions.togglePauseClicked(_:)))
        case .settings:
            return action("main-menu-settings", #selector(StatusMenuActions.settingsClicked(_:)), shortcut: ",")
        case .scrollMonitor:
            return action("scroll-monitor-title", #selector(StatusMenuActions.scrollMonitorClicked(_:)))
        case .diagnostics:
            return action("logitech-diagnostics-title", #selector(StatusMenuActions.diagnosticsClicked(_:)))
        case .testToasts:
            return action("status-menu-test-toasts", #selector(StatusMenuActions.testToastsClicked(_:)))
        case .allowAccess:
            return action("status-menu-allow-access", #selector(StatusMenuActions.allowAccessClicked(_:)))
        case .checkForUpdates(let enabled):
            // Without an action AppKit shows it disabled.
            let check = action("main-menu-check-for-updates", #selector(StatusMenuActions.checkForUpdatesClicked(_:)))
            if !enabled {
                check.action = nil
            }
            return check
        case .updateWaiting(let version):
            let update = action("status-menu-update-waiting", #selector(StatusMenuActions.checkForUpdatesClicked(_:)))
            update.title = String(format: NSLocalizedString("status-menu-update-waiting", comment: ""), version)
            return update
        case .quit:
            return action("main-menu-quit", #selector(StatusMenuActions.quitClicked(_:)), shortcut: "q")
        }
    }

    /// What stands next to the menu bar icon: the battery of a Logitech mouse that runs low.
    struct BatteryBadge: Equatable {
        /// "8%", "Low"; empty while no mouse runs low.
        let title: String
        /// The status item for VoiceOver: "Scrollio", "Scrollio, mouse battery 8%".
        let accessibilityLabel: String

        /// Nothing next to the icon.
        static var plain: BatteryBadge {
            return BatteryBadge(title: "", accessibilityLabel: NSLocalizedString("status-item-accessibility", comment: ""))
        }
    }

    /// The badge for the connected mice: the lowest battery that is low and not charging.
    /// Low is BatteryWatcher's rule, the one of the warnings: 10 % or less, or the mouse's
    /// own "low" or "critical". A mouse that reports only a level (or coarse steps, whose
    /// number the warnings leave out too) shows "Low".
    static func batteryBadge(for mice: [LogiMouseDeviceState]) -> BatteryBadge {
        let low = mice.compactMap(\.battery).filter { battery in
            !BatteryWatcher.isCharging(battery) && BatteryWatcher.alert(for: battery) > BatteryWatcher.Alert.none
        }
        guard let lowest = low.min(by: isEmptier) else { return .plain }
        if let percent = lowest.percent, !lowest.isApproximate {
            let text = MouseText.percent(percent)
            return BatteryBadge(
                title: text,
                accessibilityLabel: String(format: NSLocalizedString("status-item-accessibility-battery", comment: ""), text)
            )
        }
        return BatteryBadge(
            title: NSLocalizedString("status-item-battery-low", comment: ""),
            accessibilityLabel: NSLocalizedString("status-item-accessibility-battery-low", comment: "")
        )
    }

    /// `a` is emptier than `b`: almost empty before low, then the smaller number; a battery
    /// without a number after one with.
    private static func isEmptier(_ a: LogiMouseDeviceState.Battery, than b: LogiMouseDeviceState.Battery) -> Bool {
        let alertA = BatteryWatcher.alert(for: a)
        let alertB = BatteryWatcher.alert(for: b)
        if alertA != alertB {
            return alertA > alertB
        }
        switch (a.percent, b.percent) {
        case let (percentA?, percentB?): return percentA < percentB
        case (.some, nil): return true
        default: return false
        }
    }

    /// How the menu bar icon looks.
    struct IconLook: Equatable {
        let appearsDisabled: Bool
        let toolTip: String?

        /// - Parameters:
        ///   - startFailed: the access is there but the cores did not all start; a timer
        ///     tries again (AppRunController.isRetryingStart).
        ///   - tapRestartsThrottled: an event tap is off and its restarts are refused for a
        ///     while (Interceptor.hasThrottledTap); the cores count as running meanwhile.
        init(coresActive: Bool, isPaused: Bool, startFailed: Bool = false, tapRestartsThrottled: Bool = false) {
            if isPaused {
                appearsDisabled = !coresActive
                toolTip = NSLocalizedString("status-item-paused", comment: "")
            } else if (!coresActive && startFailed) || (coresActive && tapRestartsThrottled) {
                appearsDisabled = true
                toolTip = NSLocalizedString("status-item-could-not-start", comment: "")
            } else if !coresActive {
                appearsDisabled = true
                toolTip = NSLocalizedString("status-item-needs-access", comment: "")
            } else {
                appearsDisabled = false
                toolTip = nil
            }
        }
    }
}

/// What the items of the status-bar menu do. Tests replace the closures.
final class StatusMenuActions: NSObject {

    var showSettings: () -> Void = { MainMenuManager.showPreferencesWindow(paneIdentifier: nil) }
    /// The Welcome Guide, as the app opens it (the Accessibility step alone once the guide
    /// was finished).
    var showWelcomeGuide: () -> Void = { IntroductionWindowController.showAutomatically() }
    var togglePause: () -> Void = {
        AppRunController.shared.setPaused(!AppRunController.shared.isPaused)
    }
    var showScrollMonitor: () -> Void = {
        WindowManager.shared.showWindow(withIdentifier: WINDOW_IDENTIFIER.monitorWindowController)
    }
    /// "Smooth Scrolling in …": decided again with the settings as they are, then changed.
    var toggleAppSmoothing: (AppSmoothing.App) -> Void = { app in
        AppSmoothing.toggle(app, list: Options.shared.application, scrolling: Options.shared.scroll)
    }
    var showDiagnostics: () -> Void = { LogiCenter.shared.showDebugPanel() }
    var showTestToasts: () -> Void = { Toast.showTestPanel() }
    /// "Check for Updates…", and "Update to Scrollio …" (the same call brings a waiting
    /// update's window to the front).
    var checkForUpdates: () -> Void = { UpdateCenter.shared.checkForUpdates() }
    var quit: () -> Void = { NSApp.terminate(nil) }

    @objc func settingsClicked(_ sender: Any?) { showSettings() }
    @objc func allowAccessClicked(_ sender: Any?) { showWelcomeGuide() }
    @objc func togglePauseClicked(_ sender: Any?) { togglePause() }
    @objc func appSmoothingClicked(_ sender: Any?) {
        guard let app = (sender as? NSMenuItem)?.representedObject as? AppSmoothing.App else { return }
        toggleAppSmoothing(app)
    }
    @objc func scrollMonitorClicked(_ sender: Any?) { showScrollMonitor() }
    @objc func diagnosticsClicked(_ sender: Any?) { showDiagnostics() }
    @objc func testToastsClicked(_ sender: Any?) { showTestToasts() }
    @objc func checkForUpdatesClicked(_ sender: Any?) { checkForUpdates() }
    @objc func quitClicked(_ sender: Any?) { quit() }
}
