//
//  AppDelegate.swift
//  Mos
//
//  Created by Caldis on 2017/1/10.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

enum AppRuntime {
    static var isRunningXCTest: Bool {
        isRunningXCTest(environment: ProcessInfo.processInfo.environment) || isXCTestLoaded
    }

    static func isRunningXCTest(environment: [String: String]) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil ||
        environment["XCTestBundlePath"] != nil ||
        environment.keys.contains { $0.hasPrefix("XCTest") }
    }

    static var shouldRunAppStartupSideEffects: Bool {
        shouldRunAppStartupSideEffects(
            environment: ProcessInfo.processInfo.environment,
            isXCTestLoaded: isXCTestLoaded
        )
    }

    static func shouldRunAppStartupSideEffects(
        environment: [String: String],
        isXCTestLoaded: Bool = false
    ) -> Bool {
        let isRunningTests = isRunningXCTest(environment: environment) || isXCTestLoaded
        guard isRunningTests else { return true }
        return environment["MOS_TEST_ENABLE_APP_STARTUP"] == "1"
    }

    private static var isXCTestLoaded: Bool {
        NSClassFromString("XCTestCase") != nil ||
        NSClassFromString("XCTest.XCTestCase") != nil
    }
}

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    // 防抖定时器: 显示器参数变化通知
    private var screenChangeTimer: Timer?

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
            NSLog("Running under XCTest; skipping app startup side effects")
            return
        }

        // Takeover from the original Mos: quit it if it is running and, on the first launch,
        // copy its settings. Must come before readOptions, which seeds the defaults.
        LegacyMosTakeover.runAtLaunch()
        // Its login item (or the user) can start it again later: quit it each time.
        LegacyMosTakeover.startWatchingLaunches()

        // 禁止重复运行, 结束正在运行的实例
        Utils.preventMultiRunning(killExist: true)
        
        // DEBUG: 清空用户设置
        // UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
        
        // 读取用户设置
        Options.shared.readOptions()
        
        // DEBUG: 直接弹出设置窗口
        #if DEBUG
        WindowManager.shared.showWindow(withIdentifier: WINDOW_IDENTIFIER.preferencesWindowController)
        #endif

        // 监听用户切换, 在切换用户 session 时停止运行
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(AppDelegate.sessionDidActive),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(AppDelegate.sessionDidResign),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        // 监听系统休眠/唤醒 (a wake while another user has the Mac starts nothing)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(AppDelegate.willSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(AppDelegate.didWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        // 监听显示器参数变化 (热插拔/分辨率/显示器休眠唤醒), 延迟重建 CVDisplayLink
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.screenChangeTimer?.invalidate()
            self?.screenChangeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
                ScrollPoster.shared.recreateDisplayLink()
            }
        }
        // 监听辅助功能权限在运行时被撤销
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAccessibilityPermissionLost),
            name: .mosAccessibilityPermissionLost,
            object: nil
        )
        // The user's System Settings shortcuts (Spaces): read again when they may have changed
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reloadSystemShortcutsIfNeeded),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(reloadSystemShortcutsIfNeeded),
            name: NSWorkspace.didDeactivateApplicationNotification,
            object: nil
        )
    }
    // 运行后启动滚动处理
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        guard AppRuntime.shouldRunAppStartupSideEffects else { return }
        // 上次运行若在手势冻结指针时退出, 先恢复指针与鼠标的关联
        MouseGesturePointerLock.shared.forceRelease()
        LogiCenter.shared.installBridge(LogiIntegrationBridge.shared)
        ShortcutExecutor.shared.scrollActionPort = ScrollCore.shared
        ShortcutExecutor.shared.modifierFlagsProvider = InputProcessor.shared
        LogiUsageBootstrap.installOptionsObservers()
        LogiUsageBootstrap.refreshAll()
        BatteryWatcher.shared.start()
        AppRunController.shared.start()
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
        let identifier = Self.windowForReopen(hasAccess: Utils.isHadAccessibilityPermissions())
        WindowManager.shared.showWindow(withIdentifier: identifier)
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

    /// The Introduction window saw the permission arrive. The recovery timer would notice
    /// at its next tick, up to 10 s later; this is that tick, now, so the window can say
    /// that Scrollio is running. Nothing to do when no timer is waiting.
    func accessibilityPermissionWasGranted() {
        AppRunController.shared.accessibilityPermissionWasGranted()
    }

    // 在切换用户或休眠时停止滚动处理, 回来时再启动 (暂停中则保持暂停)
    @objc func sessionDidActive(notification: NSNotification) {
        AppRunController.shared.sessionDidBecomeActive()
    }
    @objc func sessionDidResign(notification: NSNotification) {
        AppRunController.shared.sessionDidResign()
    }
    @objc func willSleep(notification: NSNotification) {
        AppRunController.shared.stop(because: .sleep)
    }
    @objc func didWake(notification: NSNotification) {
        AppRunController.shared.wake()
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
        AppRunController.shared.accessWasLost()
    }
}
