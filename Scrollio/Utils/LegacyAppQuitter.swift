//
//  LegacyAppQuitter.swift
//  Mos
//
//  Scrollio and the original Mos cannot run side by side: two apps that handle the same
//  mouse events fight each other (both would smooth the same wheel). So Scrollio
//
//  1. quits a running Mos right before its own event taps start (AppRunController: at
//     launch with Accessibility access, on Resume, when the access arrives), and
//  2. while its taps run, quits Mos again whenever it starts (its old login item still
//     launches it at login, after Scrollio). Login items are never changed here.
//
//  Each time it says so with a toast. While Scrollio does nothing (no Accessibility access
//  yet, paused, asleep, another user has the Mac) Mos is left alone: it used to be quit at
//  every launch of Scrollio and every time it started, also then, and nothing said why.
//
//  Nothing of Mos is read or changed: its settings stay where they are.
//
//  Runs from AppDelegate and never under XCTest: tests must not quit other apps. Quitting
//  and waiting takes the apps as parameters, so tests use fakes; Utils.preventMultiRunning
//  uses it for another running copy of Scrollio.
//

import Cocoa

/// A running app as the quitter sees it: NSRunningApplication in the app, fakes in tests.
/// Also another copy of Scrollio (Utils.preventMultiRunning), which is replaced the same way.
protocol LegacyAppHandle: AnyObject {
    var bundleIdentifier: String? { get }
    var processIdentifier: pid_t { get }
    var isTerminated: Bool { get }
    @discardableResult func terminate() -> Bool
    @discardableResult func forceTerminate() -> Bool
}

extension NSRunningApplication: LegacyAppHandle {}

enum LegacyAppQuitter {

    /// Bundle ids of the app this one replaces (release and debug builds).
    static let legacyBundleIdentifiers = ["com.caldis.Mos", "com.caldis.Mos.debug"]

    // MARK: - Launch

    /// False under XCTest, whatever the startup switches say.
    static var isAllowedToRun: Bool {
        return !AppRuntime.isRunningXCTest
    }

    /// Call right before the event taps start: a running copy of the old app is asked to
    /// quit and waited for (at most 3 s, then force-quit and 1 s more).
    static func quitBeforeStarting() {
        terminateLegacyApps()
    }

    /// Tells the user that Mos was quit, and how to use it instead. Tests replace it.
    static var announceQuit: () -> Void = {
        Toast.show(NSLocalizedString("toast-mos-quit", comment: "Toast: Scrollio quit the original Mos app"), style: .info, duration: 8.0)
    }

    /// Whether Scrollio's event taps run (or are just being started): only then is Mos in
    /// the way. Tests replace it.
    static var scrollioHandlesEvents: () -> Bool = { AppRunController.shared.coresActive }

    // MARK: - Quit the old app

    /// True for a running copy of the old app. Never true for this process.
    static func isLegacyInstance(
        bundleIdentifier: String?,
        processIdentifier: pid_t,
        ownProcessIdentifier: pid_t
    ) -> Bool {
        guard processIdentifier != ownProcessIdentifier, let bundleIdentifier = bundleIdentifier else { return false }
        return legacyBundleIdentifiers.contains(bundleIdentifier)
    }

    /// Asks every running copy of the old app to quit and waits (at most `timeout`) until
    /// they are gone. One that ignores the request is force-quit after the wait.
    private static func terminateLegacyApps(timeout: TimeInterval = 3.0) {
        guard isAllowedToRun else { return }
        let ownProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        let targets = legacyBundleIdentifiers
            .flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
            .filter {
                isLegacyInstance(
                    bundleIdentifier: $0.bundleIdentifier,
                    processIdentifier: $0.processIdentifier,
                    ownProcessIdentifier: ownProcessIdentifier
                )
            }
        guard !targets.isEmpty else { return }
        for app in targets {
            AppSystemLog.note("The old Mos app is running (pid \(app.processIdentifier)): asking it to quit")
        }
        let outcome = quitAndWait(targets, timeout: timeout)
        if !outcome.quit.isEmpty || !outcome.forced.isEmpty {
            announceQuit()
        }
        for pid in outcome.forced {
            AppSystemLog.problem("The old Mos app (pid \(pid)) did not quit within \(Int(timeout)) s: forced it to quit")
        }
        for pid in outcome.stillRunning {
            AppSystemLog.problem("The old Mos app (pid \(pid)) still runs after it was forced to quit")
        }
    }

    // MARK: - Quit and wait

    /// What asking running apps to quit came to.
    struct QuitOutcome: Equatable {
        /// Gone within the wait after they were asked.
        var quit: [pid_t] = []
        /// Still there after the wait: force-quit, and gone after that.
        var forced: [pid_t] = []
        /// Still there even after the force-quit and its wait.
        var stillRunning: [pid_t] = []
        /// How long it took, in seconds.
        var waited: TimeInterval = 0
    }

    /// Asks each app to quit and waits (at most `timeout`) until they are gone. One that
    /// ignores the request is force-quit after the wait, and waited for once more (at most
    /// `forceTimeout`). Blocks the calling thread: call it before any event tap runs.
    /// `isAlive` is the seam for tests; the app asks the process itself (an
    /// NSRunningApplication's `isTerminated` is not updated while the main thread waits).
    static func quitAndWait(
        _ apps: [LegacyAppHandle],
        timeout: TimeInterval = 3.0,
        forceTimeout: TimeInterval = 1.0,
        isAlive: (LegacyAppHandle) -> Bool = { isProcessAlive($0.processIdentifier) }
    ) -> QuitOutcome {
        var outcome = QuitOutcome()
        guard !apps.isEmpty else { return outcome }
        let started = ProcessInfo.processInfo.systemUptime
        for app in apps {
            app.terminate()
        }
        waitForExit(of: apps, timeout: timeout, isAlive: isAlive)
        let survivors = apps.filter(isAlive)
        outcome.quit = apps.filter { app in !survivors.contains { $0 === app } }.map(\.processIdentifier)
        if !survivors.isEmpty {
            for app in survivors {
                app.forceTerminate()
            }
            waitForExit(of: survivors, timeout: forceTimeout, isAlive: isAlive)
            let stubborn = survivors.filter(isAlive)
            outcome.forced = survivors.filter { app in !stubborn.contains { $0 === app } }.map(\.processIdentifier)
            outcome.stillRunning = stubborn.map(\.processIdentifier)
        }
        outcome.waited = ProcessInfo.processInfo.systemUptime - started
        return outcome
    }

    static func isProcessAlive(_ processIdentifier: pid_t) -> Bool {
        // Signal 0 only checks that the process exists.
        return kill(processIdentifier, 0) == 0 || errno == EPERM
    }

    private static func waitForExit(of apps: [LegacyAppHandle], timeout: TimeInterval, isAlive: (LegacyAppHandle) -> Bool) {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline, apps.contains(where: isAlive) {
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    // MARK: - Quit the old app when it starts later

    private static var launchObserver: NSObjectProtocol?
    private static var launchObserverCenter: NotificationCenter?

    static var isWatchingLaunches: Bool {
        return launchObserver != nil
    }

    /// Quits the old app each time it launches while this app runs. Never under XCTest
    /// (`isAllowed`); tests pass their own notification center.
    static func startWatchingLaunches(
        center: NotificationCenter = NSWorkspace.shared.notificationCenter,
        isAllowed: Bool = isAllowedToRun
    ) {
        guard isAllowed, launchObserver == nil else { return }
        launchObserverCenter = center
        launchObserver = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? LegacyAppHandle else { return }
            handleLaunch(of: app, isAllowed: isAllowed)
        }
    }

    static func stopWatchingLaunches() {
        if let launchObserver, let launchObserverCenter {
            launchObserverCenter.removeObserver(launchObserver)
        }
        launchObserver = nil
        launchObserverCenter = nil
    }

    /// Asks `app` to quit when it is a copy of the old app, never this process, and only
    /// while Scrollio's event taps run (`isActive`): a paused Scrollio, or one that still
    /// waits for Accessibility access, leaves it alone. One that ignores the request is
    /// force-quit after `forceQuitDelay`; nothing here waits. The user is told (`announce`).
    /// - Returns: true when `app` was asked to quit.
    @discardableResult
    static func handleLaunch(
        of app: LegacyAppHandle,
        isAllowed: Bool = isAllowedToRun,
        ownProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier,
        forceQuitDelay: TimeInterval = 3.0,
        isActive: Bool = scrollioHandlesEvents(),
        announce: () -> Void = announceQuit
    ) -> Bool {
        guard isAllowed,
              isLegacyInstance(
                bundleIdentifier: app.bundleIdentifier,
                processIdentifier: app.processIdentifier,
                ownProcessIdentifier: ownProcessIdentifier
              ) else { return false }
        guard isActive else {
            AppSystemLog.note("The old Mos app started (pid \(app.processIdentifier)) while Scrollio's event taps are off: left running")
            return false
        }
        AppSystemLog.note("The old Mos app started while Scrollio runs (pid \(app.processIdentifier)): asking it to quit")
        app.terminate()
        announce()
        DispatchQueue.main.asyncAfter(deadline: .now() + forceQuitDelay) {
            guard !app.isTerminated else { return }
            AppSystemLog.problem("The old Mos app (pid \(app.processIdentifier)) did not quit within \(Int(forceQuitDelay)) s: forcing it to quit")
            app.forceTerminate()
        }
        return true
    }
}
