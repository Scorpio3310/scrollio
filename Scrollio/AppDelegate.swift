//
//  AppDelegate.swift
//  Mos
//
//  Created by Caldis on 2017/1/10.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

/// Whether the app runs as the host of its tests. Only the debug build can be that: the
/// tests run inside `Scrollio Debug.app`. In the release build both answers are constants and
/// the check is not compiled in. It used to be: any environment variable beginning with
/// "XCTest" (`launchctl setenv XCTestFoo 1`, which any process of the user may do) made the
/// released app start nothing, save no settings and say nothing.
enum AppRuntime {
    static var isRunningXCTest: Bool {
        #if DEBUG
        return isRunningXCTest(environment: ProcessInfo.processInfo.environment) || isXCTestLoaded
        #else
        return false
        #endif
    }

    static var shouldRunAppStartupSideEffects: Bool {
        #if DEBUG
        return shouldRunAppStartupSideEffects(
            environment: ProcessInfo.processInfo.environment,
            isXCTestLoaded: isXCTestLoaded
        )
        #else
        return true
        #endif
    }

    #if DEBUG
    static func isRunningXCTest(environment: [String: String]) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil ||
        environment["XCTestBundlePath"] != nil ||
        environment.keys.contains { $0.hasPrefix("XCTest") }
    }

    static func shouldRunAppStartupSideEffects(
        environment: [String: String],
        isXCTestLoaded: Bool = false
    ) -> Bool {
        let isRunningTests = isRunningXCTest(environment: environment) || isXCTestLoaded
        guard isRunningTests else { return true }
        return environment["SCROLLIO_TEST_ENABLE_APP_STARTUP"] == "1"
    }

    private static var isXCTestLoaded: Bool {
        NSClassFromString("XCTestCase") != nil ||
        NSClassFromString("XCTest.XCTestCase") != nil
    }
    #endif
}

/// Where the app runs from. Opened straight from its disk image, or from Downloads without
/// having been moved (macOS then runs a copy from a random read-only place, "translocated"),
/// everything seems to work, but "Open at login" registers a copy that is gone after the
/// next restart, "Show in Finder" opens a temporary folder and the disk image cannot be
/// ejected. One alert at launch says so.
enum AppLocation {
    /// Whether the app at `bundlePath` should be moved before it is used: a translocated
    /// copy, or one on a volume that cannot be written (a mounted disk image). An app on an
    /// ordinary external disk is left alone. Pure.
    static func shouldBeMoved(bundlePath: String, volumeIsReadOnly: Bool) -> Bool {
        if bundlePath.contains("/AppTranslocation/") { return true }
        return bundlePath.hasPrefix("/Volumes/") && volumeIsReadOnly
    }

    /// The same for the running app.
    static var runningCopyShouldBeMoved: Bool {
        let url = Bundle.main.bundleURL
        let readOnly = (try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly ?? false
        return shouldBeMoved(bundlePath: url.path, volumeIsReadOnly: readOnly)
    }

    /// Shows the alert. Returns true when the user chose to quit.
    static func askToMoveFirst() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("launch-location-title", comment: "Alert at launch from a disk image: title")
        alert.informativeText = NSLocalizedString("launch-location-message", comment: "Alert at launch from a disk image: what to do and why")
        alert.addButton(withTitle: NSLocalizedString("launch-location-quit", comment: "Alert at launch from a disk image: quit (the default)"))
        alert.addButton(withTitle: NSLocalizedString("launch-location-continue", comment: "Alert at launch from a disk image: go on anyway"))
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
}

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    // 防抖定时器: 显示器参数变化通知
    private var screenChangeTimer: Timer?
    /// The controller that sleep, wake, a change of user and a change of the Accessibility
    /// access lead to: the app's own. A test passes one with a fake environment.
    lazy var runController: AppRunController = .shared
    /// Puts the window of a waiting update in front; false when none waits.
    var showWaitingUpdate: () -> Bool = { UpdateCenter.shared.showWaitingUpdate() }

    // 运行前预处理
    func applicationWillFinishLaunching(_ notification: Notification) {
        // 必须最早调用: 从 Mos 自身 env 移除 DYLD_INSERT_LIBRARIES / __XPC_DYLD_* 等
        // Xcode 调试器注入的 vars. 这些 vars 会沿 XPC 链路传到 launchservicesd 再传到
        // 任何 Mos 启动的子 App, 导致依赖 AVKit 的 system app (Maps/FindMy/Podcasts)
        // 加载 libViewDebuggerSupport 时找不到符号 → dyld halt. Mos 自身进程已加载完
        // 依赖, unsetenv 不影响自身, 只让之后启动的子进程拿到干净 env.
        ShortcutExecutor.sanitizeOwnLaunchEnvironment()

        // The menu bar shown while one of the app's windows is in front. Building it has no
        // effect outside the process, so the tests get it too.
        MainMenuManager.shared.install()

        guard AppRuntime.shouldRunAppStartupSideEffects else {
            return
        }

        // From a disk image or a translocated copy: say so first, before anything else of
        // the app starts (no event tap runs yet, so the modal alert blocks nothing).
        if AppLocation.runningCopyShouldBeMoved {
            AppSystemLog.note("Running from a disk image or a translocated copy: asking to move the app to Applications first")
            if AppLocation.askToMoveFirst() {
                NSApp.terminate(nil)
                return
            }
        }

        // The original Mos would handle the same mouse events. It is quit when Scrollio's
        // event taps start (AppRunController's cores), not here: while Scrollio does nothing
        // (no Accessibility access yet, paused) Mos is left alone. Its login item (or the
        // user) can start it later: it is quit then too, while the taps run.
        LegacyAppQuitter.startWatchingLaunches()

        // 禁止重复运行, 结束正在运行的实例: another copy is asked to quit and waited for (at
        // most 3 s, then force-quit) before this one starts any event tap or Logitech session.
        Utils.preventMultiRunning(killExist: true)
        
        // DEBUG: 清空用户设置
        // UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
        
        // The Welcome Guide: a new installation is one without settings before they are first
        // read; it then waits for the guide.
        WelcomeGuideProgress.live.settleAtLaunch(
            isNewInstallation: UserDefaults.standard.object(forKey: OptionItem.General.OptionsExist) == nil
        )

        // 读取用户设置
        Options.shared.readOptions()
        // The apps that are left to macOS unless the user says otherwise (Calendar): each
        // is offered once, as an ordinary entry of the Apps list.
        AppsLeftToMacOS.offerLive()
        
        // DEBUG: 直接弹出设置窗口 (not when the Welcome Guide opens at launch)
        #if DEBUG
        if !IntroductionWindowController.opensAtLaunch(hasAccess: Utils.isHadAccessibilityPermissions()) {
            WindowManager.shared.showWindow(withIdentifier: WINDOW_IDENTIFIER.preferencesWindowController)
        }
        #endif

        registerObservers()
    }

    /// Follows what the Mac tells the app while it runs: another user takes the Mac or gives
    /// it back, sleep and wake, a change of the displays, a loss or a change of the
    /// Accessibility access, a change of the macOS keyboard shortcuts. The three centers
    /// are parameters so that a test can post to its own and see where each one leads:
    /// under XCTest the launch code that calls this does not run.
    func registerObservers(
        workspace: NotificationCenter = NSWorkspace.shared.notificationCenter,
        app: NotificationCenter = .default,
        distributed: NotificationCenter = DistributedNotificationCenter.default()
    ) {
        // 监听用户切换, 在切换用户 session 时停止运行
        workspace.addObserver(
            self,
            selector: #selector(AppDelegate.sessionDidActive),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
        workspace.addObserver(
            self,
            selector: #selector(AppDelegate.sessionDidResign),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        // 监听系统休眠/唤醒 (a wake while another user has the Mac starts nothing)
        workspace.addObserver(
            self,
            selector: #selector(AppDelegate.willSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        workspace.addObserver(
            self,
            selector: #selector(AppDelegate.didWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        // 监听显示器参数变化 (热插拔/分辨率/显示器休眠唤醒), 延迟重建 CVDisplayLink
        app.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.screenChangeTimer?.invalidate()
            self?.screenChangeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
                ScrollPoster.shared.recreateDisplayLink()
            }
        }
        // 监听辅助功能权限在运行时被撤销
        app.addObserver(
            self,
            selector: #selector(handleAccessibilityPermissionLost),
            name: .scrollioAccessibilityPermissionLost,
            object: nil
        )
        // The user's System Settings shortcuts (Spaces): read again when they may have changed
        app.addObserver(
            self,
            selector: #selector(reloadSystemShortcutsIfNeeded),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        workspace.addObserver(
            self,
            selector: #selector(reloadSystemShortcutsIfNeeded),
            name: NSWorkspace.didDeactivateApplicationNotification,
            object: nil
        )
        // The Accessibility list of System Settings changed (any app's entry): look at the
        // access now, not at the keepers' next look up to 5 s later. A tap of a process
        // without access is what makes keys and the wheel hang meanwhile.
        distributed.addObserver(
            self,
            selector: #selector(accessibilityListDidChange),
            name: Self.accessibilityListChangedNotification,
            object: nil
        )
    }

    /// Posted by macOS (to every process) when the Accessibility list changes.
    static let accessibilityListChangedNotification = Notification.Name("com.apple.accessibility.api")
    /// The answer of `AXIsProcessTrusted` follows the notification with a short delay.
    static let accessibilityCheckDelay: TimeInterval = 0.5

    @objc func accessibilityListDidChange(notification: NSNotification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.accessibilityCheckDelay) { [weak self] in
            self?.runController.accessibilityListDidChange()
        }
    }
    // 运行后启动滚动处理
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        guard AppRuntime.shouldRunAppStartupSideEffects else { return }
        // Which accent colour the user sees: the app's purple, or their own choice.
        AppSystemLog.note(AppAccent.liveLogLine())
        // EVALUATION SWITCH (removed with `TrackpadStyleEvaluation`): which form of
        // "Trackpad-style scrolling" apps that are not Chromium-based get in this run.
        AppSystemLog.note(TrackpadStyleEvaluation.launchLine(usesOldLongTouch: TrackpadStyleEvaluation.usesOldLongTouch))
        // The self-test for taking the wheel event's hardware record off a trackpad-style
        // frame (a private call) runs here, with its line in the log, only for a user who
        // has "Trackpad-style scrolling" on, in the Scrolling pane or for some app. With it
        // off everywhere nothing asks for it, here or at a wheel event; switched on later,
        // the first wheel event with phases asks.
        let applications = Options.shared.application.applications
        let isOnSomewhere = ScrollPoster.trackpadStyleIsOnSomewhere(
            global: Options.shared.scroll,
            applications: (0..<applications.count).compactMap { applications.get(by: $0) }
        )
        if isOnSomewhere {
            _ = ScrollHardwareRecord.comesOff
        }
        // What Safari and the DuckDuckGo browser get, and why (it hangs on the self-test).
        AppSystemLog.note(ScrollHardwareRecord.webKitLine(isOnSomewhere ? ScrollHardwareRecord.system.outcome : nil))
        // Read now what the first press of a button would otherwise read inside the button
        // tap's callback: the user's Spaces shortcuts (another app's preferences) and the
        // keys of the keyboard layout in use.
        SystemShortcut.reloadSystemShortcuts()
        KeyboardLayoutKeys.shared.warmUp()
        // 上次运行若在手势冻结指针时退出, 先恢复指针与鼠标的关联
        MouseGesturePointerLock.shared.forceRelease()
        LogiCenter.shared.installBridge(LogiIntegrationBridge.shared)
        Self.connectParts()
        LogiUsageBootstrap.installOptionsObservers()
        LogiUsageBootstrap.refreshAll()
        // A Shortcut Ring that opens an app shows its icon from the first ring on.
        ShortcutRingController.prepareFaceAtLaunch()
        BatteryWatcher.shared.start()
        AppRunController.shared.start()
        // New versions: only a released copy has an update feed and starts the updater.
        UpdateCenter.shared.start()
        // A new user meets the Welcome Guide (without the access AppRunController opened it).
        if WelcomeGuideProgress.live.isPending {
            IntroductionWindowController.showAutomatically()
        }
    }

    /// Connects the parts that know each other only through a protocol: the actions a
    /// button runs reach the scroll engine ("Scroll faster" and the other hold functions)
    /// and read the modifiers the buttons hold. Without the first line those actions do
    /// nothing; a function of its own so that a test can call it and see that they arrive.
    static func connectParts() {
        ShortcutExecutor.shared.scrollActionPort = ScrollCore.shared
        ShortcutExecutor.shared.modifierFlagsProvider = InputProcessor.shared
    }

    /// The window a reopened app shows (Finder, Spotlight, the Dock): the settings, or the
    /// Welcome Guide while Accessibility access is missing. Reopening always leads somewhere,
    /// also with the menu bar icon hidden.
    static func windowForReopen(hasAccess: Bool) -> String {
        return hasAccess ? WINDOW_IDENTIFIER.preferencesWindowController : WINDOW_IDENTIFIER.introductionWindowController
    }

    // 用户双击打开应用程序
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else {
            return true
        }
        // While an update waits, Scrollio is in the Dock for it: a click on that icon
        // leads to the update, not to the settings.
        if showWaitingUpdate() {
            return false
        }
        let identifier = Self.windowForReopen(hasAccess: Utils.isHadAccessibilityPermissions())
        if identifier == WINDOW_IDENTIFIER.introductionWindowController {
            IntroductionWindowController.showAutomatically()
        } else {
            WindowManager.shared.showWindow(withIdentifier: identifier)
        }
        return false
    }
    
    // 关闭前停止滚动处理
    func applicationWillTerminate(_ aNotification: Notification) {
        guard AppRuntime.shouldRunAppStartupSideEffects else { return }
        MouseGesturePointerLock.shared.forceRelease()
        // The same stop as sleep: the event taps, then the Logitech mice get their buttons back.
        AppRunController.shared.stop(because: .quit)
        // 写入尚未 flush 的脏配置组
        Options.shared.flushPendingSaves()
    }

    /// The Welcome Guide saw the permission arrive. The recovery timer would notice
    /// at its next tick, up to 10 s later; this is that tick, now, so the window can say
    /// that Scrollio is running. Nothing to do when no timer is waiting.
    func accessibilityPermissionWasGranted() {
        runController.accessibilityPermissionWasGranted()
    }

    // 在切换用户或休眠时停止滚动处理, 回来时再启动 (暂停中则保持暂停)
    @objc func sessionDidActive(notification: NSNotification) {
        runController.sessionDidBecomeActive()
    }
    @objc func sessionDidResign(notification: NSNotification) {
        runController.sessionDidResign()
    }
    @objc func willSleep(notification: NSNotification) {
        runController.stop(because: .sleep)
    }
    @objc func didWake(notification: NSNotification) {
        runController.wake()
    }
    @objc func reloadSystemShortcutsIfNeeded(notification: NSNotification) {
        let deactivated = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        guard SystemShortcut.reloadsSystemShortcuts(
            after: notification.name,
            deactivatedBundleIdentifier: deactivated?.bundleIdentifier
        ) else { return }
        SystemShortcut.reloadSystemShortcuts()
    }
    // 辅助功能权限在运行时被撤销 (可能由多个 Interceptor 同时触发, 此方法必须幂等)
    @objc func handleAccessibilityPermissionLost() {
        runController.accessWasLost()
    }
}
