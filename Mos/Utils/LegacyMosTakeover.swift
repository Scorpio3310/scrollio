//
//  LegacyMosTakeover.swift
//  Mos
//
//  Scrollio replaces the original Mos on this Mac. At launch it
//
//  1. quits a running Mos (two apps smoothing the same wheel fight each other),
//  2. once only, copies Mos's settings into Scrollio's own defaults domain, so the first
//     launch behaves like the app it replaces, and
//  3. while it runs, quits Mos again whenever it starts (its old login item still launches
//     it at login, after Scrollio). Login items are never changed here.
//
//  Runs from AppDelegate before Options.readOptions (which seeds default values) and
//  never under XCTest: tests must not quit other apps or read the real Mos settings.
//  The copying itself takes its UserDefaults as parameters, so tests use throwaway suites.
//

import Cocoa

/// A running app as the takeover sees it: NSRunningApplication in the app, fakes in tests.
protocol LegacyAppHandle: AnyObject {
    var bundleIdentifier: String? { get }
    var processIdentifier: pid_t { get }
    var isTerminated: Bool { get }
    @discardableResult func terminate() -> Bool
    @discardableResult func forceTerminate() -> Bool
}

extension NSRunningApplication: LegacyAppHandle {}

enum LegacyMosTakeover {

    /// Bundle ids of the app this one replaces (release and debug builds).
    static let legacyBundleIdentifiers = ["com.caldis.Mos", "com.caldis.Mos.debug"]
    /// Defaults domain the settings come from.
    static let legacyDefaultsDomain = "com.caldis.Mos"
    /// Set in the new domain once the copy has run (also when there was nothing to copy),
    /// so a later launch never overwrites Scrollio's settings with Mos's again.
    static let migrationFlagKey = "legacyMosDefaultsMigrated"
    /// The Toast component keeps its settings in "<bundle id>.toast".
    static let toastSuiteSuffix = ".toast"

    enum MigrationResult: Equatable {
        case alreadyDone
        case nothingToMigrate
        case migrated(keyCount: Int)
    }

    // MARK: - Launch

    /// False under XCTest, whatever the startup switches say.
    static var isAllowedToRun: Bool {
        return !AppRuntime.isRunningXCTest
    }

    /// Call once at launch, before the options are read and before the event taps start.
    static func runAtLaunch() {
        guard isAllowedToRun else { return }
        terminateLegacyApps()
        let ownDomain = Bundle.main.bundleIdentifier ?? ""
        guard !ownDomain.isEmpty, ownDomain != legacyDefaultsDomain else { return }
        let result = migrateDefaults(
            from: .standard,
            legacyDomain: legacyDefaultsDomain,
            into: .standard,
            legacyToastDomain: legacyDefaultsDomain + toastSuiteSuffix,
            toast: UserDefaults(suiteName: ownDomain + toastSuiteSuffix)
        )
        AppSystemLog.note("Settings of the old Mos app: \(result)")
    }

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
            app.terminate()
        }
        waitForExit(of: targets.map { $0.processIdentifier }, timeout: timeout)
        let survivors = targets.filter { isProcessAlive($0.processIdentifier) }
        guard !survivors.isEmpty else { return }
        for app in survivors {
            AppSystemLog.problem("The old Mos app (pid \(app.processIdentifier)) did not quit within \(Int(timeout)) s: forcing it to quit")
            app.forceTerminate()
        }
        waitForExit(of: survivors.map { $0.processIdentifier }, timeout: 1.0)
    }

    private static func isProcessAlive(_ processIdentifier: pid_t) -> Bool {
        // Signal 0 only checks that the process exists.
        return kill(processIdentifier, 0) == 0 || errno == EPERM
    }

    private static func waitForExit(of processIdentifiers: [pid_t], timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, processIdentifiers.contains(where: isProcessAlive) {
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

    /// Asks `app` to quit when it is a copy of the old app, never this process. One that
    /// ignores the request is force-quit after `forceQuitDelay`; nothing here waits.
    /// - Returns: true when `app` was asked to quit.
    @discardableResult
    static func handleLaunch(
        of app: LegacyAppHandle,
        isAllowed: Bool = isAllowedToRun,
        ownProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier,
        forceQuitDelay: TimeInterval = 3.0
    ) -> Bool {
        guard isAllowed,
              isLegacyInstance(
                bundleIdentifier: app.bundleIdentifier,
                processIdentifier: app.processIdentifier,
                ownProcessIdentifier: ownProcessIdentifier
              ) else { return false }
        AppSystemLog.note("The old Mos app started while Scrollio runs (pid \(app.processIdentifier)): asking it to quit")
        app.terminate()
        DispatchQueue.main.asyncAfter(deadline: .now() + forceQuitDelay) {
            guard !app.isTerminated else { return }
            AppSystemLog.problem("The old Mos app (pid \(app.processIdentifier)) did not quit within \(Int(forceQuitDelay)) s: forcing it to quit")
            app.forceTerminate()
        }
        return true
    }

    // MARK: - Copy the settings

    /// Sparkle and update settings have no meaning here; the status item's saved
    /// visibility would carry a hidden icon over to the new app.
    static func shouldSkip(key: String) -> Bool {
        if key == "updateCheckOnAppStart" || key == "updateIncludingBetaVersion" { return true }
        if key.hasPrefix("SU") || key.hasPrefix("NSWindow Frame SU") { return true }
        if key.hasPrefix("NSStatusItem Visible") { return true }
        return false
    }

    /// Copies the legacy domain into `target` once, and the legacy Toast suite into `toast`.
    /// The status-bar icon is forced visible: with a migrated "hide icon" setting the new
    /// app would start with no way to reach it. `legacy` is only used to read the domains.
    @discardableResult
    static func migrateDefaults(
        from legacy: UserDefaults,
        legacyDomain: String,
        into target: UserDefaults,
        legacyToastDomain: String? = nil,
        toast: UserDefaults? = nil
    ) -> MigrationResult {
        guard !target.bool(forKey: migrationFlagKey) else { return .alreadyDone }
        defer { target.set(true, forKey: migrationFlagKey) }

        let values = (legacy.persistentDomain(forName: legacyDomain) ?? [:]).filter { !shouldSkip(key: $0.key) }
        guard !values.isEmpty else { return .nothingToMigrate }

        for (key, value) in values {
            target.set(value, forKey: key)
        }
        target.set(false, forKey: OptionItem.General.HideStatusItem)

        if let legacyToastDomain = legacyToastDomain, let toast = toast {
            for (key, value) in legacy.persistentDomain(forName: legacyToastDomain) ?? [:] {
                toast.set(value, forKey: key)
            }
        }
        return .migrated(keyCount: values.count)
    }
}
