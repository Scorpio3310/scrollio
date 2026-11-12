import XCTest
@testable import Scrollio_Debug

/// First-launch takeover from the original Mos: its settings are copied into the new
/// defaults domain once. Every test works on throwaway UserDefaults suites; the real
/// domains of the old and the new app are never read or written here.
final class LegacyMosTakeoverTests: XCTestCase {

    // Suites named by an absolute path live in that file instead of ~/Library/Preferences,
    // so each test gets its own folder in the temporary directory and removes it afterwards.
    private var folder: URL!
    private var legacyName: String { folder.appendingPathComponent("legacy").path }
    private var targetName: String { folder.appendingPathComponent("target").path }
    private var legacyToastName: String { legacyName + LegacyMosTakeover.toastSuiteSuffix }
    private var targetToastName: String { targetName + LegacyMosTakeover.toastSuiteSuffix }
    private var suiteNames: [String] { [legacyName, targetName, legacyToastName, targetToastName] }
    private var legacy: UserDefaults!
    private var target: UserDefaults!
    private var legacyToast: UserDefaults!
    private var targetToast: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScrollioTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        legacy = try XCTUnwrap(UserDefaults(suiteName: legacyName))
        target = try XCTUnwrap(UserDefaults(suiteName: targetName))
        legacyToast = try XCTUnwrap(UserDefaults(suiteName: legacyToastName))
        targetToast = try XCTUnwrap(UserDefaults(suiteName: targetToastName))
    }

    override func tearDown() {
        for name in suiteNames {
            UserDefaults.standard.removePersistentDomain(forName: name)
        }
        legacy = nil
        target = nil
        legacyToast = nil
        targetToast = nil
        try? FileManager.default.removeItem(at: folder)
        folder = nil
        super.tearDown()
    }

    private func migrate() -> LegacyMosTakeover.MigrationResult {
        return LegacyMosTakeover.migrateDefaults(
            from: legacy,
            legacyDomain: legacyName,
            into: target,
            legacyToastDomain: legacyToastName,
            toast: targetToast
        )
    }

    private func targetDomain() -> [String: Any] {
        return target.persistentDomain(forName: targetName) ?? [:]
    }

    // MARK: - Copy

    func testCopiesTheLegacySettingsIntoTheNewDomain() {
        let bindings = Data([0x5B, 0x5D])
        let featureCache = Data([1, 2, 3])
        legacy.set("optionsExist", forKey: "optionsExist")
        legacy.set(true, forKey: "smooth")
        legacy.set(false, forKey: "reverse")
        legacy.set(3.5, forKey: "speed")
        legacy.set(bindings, forKey: "buttonBindings")
        legacy.set(featureCache, forKey: "logitechFeatureCache")
        legacy.set("{{10, 20}, {300, 400}}", forKey: "NSWindow Frame HIDDebug")

        XCTAssertEqual(migrate(), .migrated(keyCount: 7))

        let domain = targetDomain()
        XCTAssertEqual(domain["optionsExist"] as? String, "optionsExist")
        XCTAssertEqual(domain["smooth"] as? Bool, true)
        XCTAssertEqual(domain["reverse"] as? Bool, false)
        XCTAssertEqual(domain["speed"] as? Double, 3.5)
        XCTAssertEqual(domain["buttonBindings"] as? Data, bindings)
        XCTAssertEqual(domain["logitechFeatureCache"] as? Data, featureCache)
        XCTAssertEqual(domain["NSWindow Frame HIDDebug"] as? String, "{{10, 20}, {300, 400}}")
        XCTAssertEqual(domain[LegacyMosTakeover.migrationFlagKey] as? Bool, true)
        // The copied settings, the marker and the visible status-bar icon; nothing else.
        XCTAssertEqual(domain.count, 9)
        XCTAssertEqual(domain["hideStatusItem"] as? Bool, false)
    }

    func testLeavesTheLegacyDomainUntouched() {
        legacy.set(true, forKey: "smooth")
        legacy.set(true, forKey: "hideStatusItem")

        _ = migrate()

        let domain = legacy.persistentDomain(forName: legacyName) ?? [:]
        XCTAssertEqual(Set(domain.keys), ["smooth", "hideStatusItem"])
        XCTAssertEqual(domain["hideStatusItem"] as? Bool, true)
    }

    // MARK: - Once only

    func testRunsOnlyOnce() {
        legacy.set(3.5, forKey: "speed")
        XCTAssertEqual(migrate(), .migrated(keyCount: 1))

        // Later changes on either side stay where they are.
        target.set(1.25, forKey: "speed")
        legacy.set(9.0, forKey: "speed")
        legacy.set(true, forKey: "smooth")

        XCTAssertEqual(migrate(), .alreadyDone)
        XCTAssertEqual(targetDomain()["speed"] as? Double, 1.25)
        XCTAssertNil(targetDomain()["smooth"])
    }

    // MARK: - Skipped keys

    func testSkipsUpdateRelatedKeys() {
        legacy.set(true, forKey: "smooth")
        legacy.set(true, forKey: "updateCheckOnAppStart")
        legacy.set(true, forKey: "updateIncludingBetaVersion")
        legacy.set(Date(timeIntervalSince1970: 0), forKey: "SULastCheckTime")
        legacy.set(true, forKey: "SUEnableAutomaticChecks")
        legacy.set("{{0, 0}, {10, 10}}", forKey: "NSWindow Frame SUUpdateAlert2")

        XCTAssertEqual(migrate(), .migrated(keyCount: 1))

        let domain = targetDomain()
        for key in ["updateCheckOnAppStart", "updateIncludingBetaVersion", "SULastCheckTime",
                    "SUEnableAutomaticChecks", "NSWindow Frame SUUpdateAlert2"] {
            XCTAssertNil(domain[key], key)
        }
        XCTAssertEqual(domain["smooth"] as? Bool, true)
    }

    // MARK: - Status-bar icon

    func testForcesTheStatusBarIconVisible() {
        legacy.set(true, forKey: "hideStatusItem")
        legacy.set(false, forKey: "NSStatusItem Visible Item-0")
        legacy.set(false, forKey: "NSStatusItem VisibleCC Item-0")
        legacy.set(412.0, forKey: "NSStatusItem Preferred Position Item-0")

        XCTAssertEqual(migrate(), .migrated(keyCount: 2))

        let domain = targetDomain()
        XCTAssertEqual(domain["hideStatusItem"] as? Bool, false)
        XCTAssertNil(domain["NSStatusItem Visible Item-0"])
        XCTAssertNil(domain["NSStatusItem VisibleCC Item-0"])
        XCTAssertEqual(domain["NSStatusItem Preferred Position Item-0"] as? Double, 412.0)
    }

    func testWritesTheVisibleIconEvenWhenTheLegacyAppNeverSavedIt() {
        legacy.set(true, forKey: "smooth")

        _ = migrate()

        XCTAssertEqual(targetDomain()["hideStatusItem"] as? Bool, false)
    }

    // MARK: - Nothing to copy

    func testIsANoOpWhenTheLegacyDomainIsEmpty() {
        legacyToast.set(7, forKey: "maxCount")

        XCTAssertEqual(migrate(), .nothingToMigrate)

        // Only the marker is written, so a Mos installed later is not imported over
        // the settings made in the meantime.
        XCTAssertEqual(Set(targetDomain().keys), [LegacyMosTakeover.migrationFlagKey])
        XCTAssertTrue((targetToast.persistentDomain(forName: targetToastName) ?? [:]).isEmpty)
        XCTAssertEqual(migrate(), .alreadyDone)
    }

    func testIsANoOpWhenTheLegacyDomainOnlyHoldsSkippedKeys() {
        legacy.set(true, forKey: "updateCheckOnAppStart")
        legacy.set(false, forKey: "NSStatusItem VisibleCC Item-0")

        XCTAssertEqual(migrate(), .nothingToMigrate)
        XCTAssertEqual(Set(targetDomain().keys), [LegacyMosTakeover.migrationFlagKey])
    }

    // MARK: - Toast suite

    func testCopiesTheToastSuite() {
        legacy.set(true, forKey: "smooth")
        legacyToast.set(120.5, forKey: "positionX")
        legacyToast.set(640.0, forKey: "positionY")
        legacyToast.set(3, forKey: "maxCount")

        _ = migrate()

        let domain = targetToast.persistentDomain(forName: targetToastName) ?? [:]
        XCTAssertEqual(domain["positionX"] as? Double, 120.5)
        XCTAssertEqual(domain["positionY"] as? Double, 640.0)
        XCTAssertEqual(domain["maxCount"] as? Int, 3)
        XCTAssertEqual(domain.count, 3)
    }

    func testWorksWithoutAToastSuite() {
        legacy.set(true, forKey: "smooth")

        XCTAssertEqual(migrate(), .migrated(keyCount: 1))
        XCTAssertTrue((targetToast.persistentDomain(forName: targetToastName) ?? [:]).isEmpty)
    }

    // MARK: - Old app instances

    func testOnlyOtherProcessesOfTheOldAppAreLegacyInstances() {
        let own: pid_t = 100
        XCTAssertTrue(LegacyMosTakeover.isLegacyInstance(bundleIdentifier: "com.caldis.Mos", processIdentifier: 200, ownProcessIdentifier: own))
        XCTAssertTrue(LegacyMosTakeover.isLegacyInstance(bundleIdentifier: "com.caldis.Mos.debug", processIdentifier: 200, ownProcessIdentifier: own))
        // Never itself, even when it carries an old bundle id.
        XCTAssertFalse(LegacyMosTakeover.isLegacyInstance(bundleIdentifier: "com.caldis.Mos", processIdentifier: own, ownProcessIdentifier: own))
        XCTAssertFalse(LegacyMosTakeover.isLegacyInstance(bundleIdentifier: "com.caldis.Mos.debug", processIdentifier: own, ownProcessIdentifier: own))
        // Other apps, including other copies of the new one, are left alone.
        XCTAssertFalse(LegacyMosTakeover.isLegacyInstance(bundleIdentifier: "com.nikklemenc.Scrollio", processIdentifier: 200, ownProcessIdentifier: own))
        XCTAssertFalse(LegacyMosTakeover.isLegacyInstance(bundleIdentifier: "com.nikklemenc.Scrollio.debug", processIdentifier: 200, ownProcessIdentifier: own))
        XCTAssertFalse(LegacyMosTakeover.isLegacyInstance(bundleIdentifier: "com.caldis.MosHelper", processIdentifier: 200, ownProcessIdentifier: own))
        XCTAssertFalse(LegacyMosTakeover.isLegacyInstance(bundleIdentifier: "com.apple.finder", processIdentifier: 200, ownProcessIdentifier: own))
        XCTAssertFalse(LegacyMosTakeover.isLegacyInstance(bundleIdentifier: nil, processIdentifier: 200, ownProcessIdentifier: own))
    }

    // MARK: - The old app started later (its login item)

    private final class FakeApp: LegacyAppHandle {
        let bundleIdentifier: String?
        let processIdentifier: pid_t
        let quitsWhenAsked: Bool
        private(set) var isTerminated = false
        private(set) var terminateCalls = 0
        private(set) var forceTerminateCalls = 0

        init(_ bundleIdentifier: String?, pid: pid_t = 999_999, quitsWhenAsked: Bool = true) {
            self.bundleIdentifier = bundleIdentifier
            self.processIdentifier = pid
            self.quitsWhenAsked = quitsWhenAsked
        }

        func terminate() -> Bool {
            terminateCalls += 1
            if quitsWhenAsked { isTerminated = true }
            return true
        }

        func forceTerminate() -> Bool {
            forceTerminateCalls += 1
            isTerminated = true
            return true
        }
    }

    func testALaterLaunchOfTheOldAppIsQuit() {
        for identifier in LegacyMosTakeover.legacyBundleIdentifiers {
            let app = FakeApp(identifier, pid: 200)
            XCTAssertTrue(LegacyMosTakeover.handleLaunch(of: app, isAllowed: true, ownProcessIdentifier: 100))
            XCTAssertEqual(app.terminateCalls, 1, identifier)
        }
    }

    func testALaterLaunchNeverQuitsItselfOrAnotherApp() {
        let apps = [
            FakeApp("com.caldis.Mos", pid: 100),
            FakeApp("com.nikklemenc.Scrollio", pid: 200),
            FakeApp("com.nikklemenc.Scrollio.debug", pid: 200),
            FakeApp("com.apple.finder", pid: 200),
            FakeApp(nil, pid: 200),
        ]
        for app in apps {
            XCTAssertFalse(LegacyMosTakeover.handleLaunch(of: app, isAllowed: true, ownProcessIdentifier: 100))
            XCTAssertEqual(app.terminateCalls, 0, app.bundleIdentifier ?? "nil")
        }
    }

    func testAnOldAppThatIgnoresTheRequestIsForceQuitLater() {
        let stubborn = FakeApp("com.caldis.Mos", quitsWhenAsked: false)
        let polite = FakeApp("com.caldis.Mos")
        LegacyMosTakeover.handleLaunch(of: stubborn, isAllowed: true, forceQuitDelay: 0.05)
        LegacyMosTakeover.handleLaunch(of: polite, isAllowed: true, forceQuitDelay: 0.05)
        // Nothing waits: the force-quit comes later on the main queue.
        XCTAssertEqual(stubborn.forceTerminateCalls, 0)

        let forced = expectation(for: NSPredicate { _, _ in stubborn.forceTerminateCalls == 1 }, evaluatedWith: nil)
        wait(for: [forced], timeout: 5)
        XCTAssertEqual(polite.forceTerminateCalls, 0)
    }

    func testTheLaunchObserverQuitsTheOldApp() {
        let center = NotificationCenter()
        LegacyMosTakeover.startWatchingLaunches(center: center, isAllowed: true)
        defer { LegacyMosTakeover.stopWatchingLaunches() }
        XCTAssertTrue(LegacyMosTakeover.isWatchingLaunches)

        let mos = FakeApp("com.caldis.Mos")
        let other = FakeApp("com.apple.TextEdit")
        for app in [other, mos] {
            center.post(
                name: NSWorkspace.didLaunchApplicationNotification,
                object: nil,
                userInfo: [NSWorkspace.applicationUserInfoKey: app]
            )
        }
        let quit = expectation(for: NSPredicate { _, _ in mos.terminateCalls == 1 }, evaluatedWith: nil)
        wait(for: [quit], timeout: 5)
        XCTAssertEqual(other.terminateCalls, 0)

        LegacyMosTakeover.stopWatchingLaunches()
        XCTAssertFalse(LegacyMosTakeover.isWatchingLaunches)
        center.post(
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: mos]
        )
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 5)
        XCTAssertEqual(mos.terminateCalls, 1, "no observer after stopping")
    }

    // MARK: - Quit and wait (the old app at launch, another copy of Scrollio)

    /// In the app the process itself is asked; here the fake's state stands for it.
    private let fakeIsAlive: (LegacyAppHandle) -> Bool = { !$0.isTerminated }

    func testAnAppThatQuitsWhenAskedIsNotForced() {
        let polite = FakeApp("com.nikklemenc.Scrollio", pid: 200)
        let outcome = LegacyMosTakeover.quitAndWait([polite], timeout: 3, isAlive: fakeIsAlive)
        XCTAssertEqual(outcome.quit, [200])
        XCTAssertEqual(outcome.forced, [])
        XCTAssertEqual(outcome.stillRunning, [])
        XCTAssertEqual(polite.terminateCalls, 1)
        XCTAssertEqual(polite.forceTerminateCalls, 0)
        XCTAssertLessThan(outcome.waited, 1, "no wait once it is gone")
    }

    func testAnAppThatIgnoresTheRequestIsForcedAfterTheWait() {
        let stubborn = FakeApp("com.nikklemenc.Scrollio", pid: 200, quitsWhenAsked: false)
        let polite = FakeApp("com.nikklemenc.Scrollio", pid: 300)
        let outcome = LegacyMosTakeover.quitAndWait([stubborn, polite], timeout: 0.1, forceTimeout: 0.1, isAlive: fakeIsAlive)
        XCTAssertEqual(outcome.quit, [300])
        XCTAssertEqual(outcome.forced, [200])
        XCTAssertEqual(outcome.stillRunning, [])
        XCTAssertEqual(stubborn.forceTerminateCalls, 1)
        XCTAssertEqual(polite.forceTerminateCalls, 0)
        XCTAssertGreaterThanOrEqual(outcome.waited, 0.1, "the request had its time first")
    }

    func testAnAppThatSurvivesTheForceQuitIsReported() {
        let zombie = FakeApp("com.nikklemenc.Scrollio", pid: 200, quitsWhenAsked: false)
        let outcome = LegacyMosTakeover.quitAndWait([zombie], timeout: 0.05, forceTimeout: 0.05, isAlive: { _ in true })
        XCTAssertEqual(outcome.quit, [])
        XCTAssertEqual(outcome.forced, [])
        XCTAssertEqual(outcome.stillRunning, [200])
    }

    func testNothingToQuitWaitsForNothing() {
        XCTAssertEqual(LegacyMosTakeover.quitAndWait([], isAlive: fakeIsAlive), LegacyMosTakeover.QuitOutcome())
    }

    /// Another copy of Scrollio is waited for before this one starts its taps; this process
    /// is never asked to quit, wherever it is in the list.
    func testAnotherCopyOfScrollioIsWaitedForAndNeverThisOne() {
        let own = FakeApp("com.nikklemenc.Scrollio", pid: 100)
        let other = FakeApp("com.nikklemenc.Scrollio", pid: 200, quitsWhenAsked: false)
        let outcome = Utils.quitOtherInstances([other, own], own: 100, timeout: 0.05, forceTimeout: 0.05, isAlive: fakeIsAlive)
        XCTAssertEqual(own.terminateCalls + own.forceTerminateCalls, 0)
        XCTAssertEqual(other.terminateCalls, 1)
        XCTAssertEqual(outcome.forced, [200])

        XCTAssertEqual(Utils.quitOtherInstances([own], own: 100, isAlive: fakeIsAlive), LegacyMosTakeover.QuitOutcome())
        XCTAssertEqual(own.terminateCalls, 0)
    }

    func testWhatTheLogSaysAboutTheOtherCopy() {
        var outcome = LegacyMosTakeover.QuitOutcome()
        outcome.quit = [200]
        outcome.waited = 0.42
        XCTAssertEqual(Utils.otherInstanceLines(outcome, timeout: 3), [
            "Another copy of Scrollio was running (pid 200): it quit when asked, after 0.4 s; this one starts now",
        ])
        outcome = LegacyMosTakeover.QuitOutcome(quit: [], forced: [200], stillRunning: [300], waited: 4.04)
        XCTAssertEqual(Utils.otherInstanceLines(outcome, timeout: 3), [
            "Another copy of Scrollio (pid 200) did not quit within 3 s: forced it to quit (4.0 s in all); this one starts now",
            "Another copy of Scrollio (pid 300) still runs after it was forced to quit (4.0 s); this one starts anyway",
        ])
    }

    // MARK: - XCTest

    func testTakeoverIsNeverAllowedUnderXCTest() {
        XCTAssertTrue(AppRuntime.isRunningXCTest)
        XCTAssertFalse(LegacyMosTakeover.isAllowedToRun)
    }

    func testTheLaunchWatcherNeverRunsUnderXCTestByDefault() {
        let mos = FakeApp("com.caldis.Mos")
        XCTAssertFalse(LegacyMosTakeover.handleLaunch(of: mos))
        XCTAssertEqual(mos.terminateCalls, 0)

        LegacyMosTakeover.startWatchingLaunches()
        XCTAssertFalse(LegacyMosTakeover.isWatchingLaunches)
    }

    // MARK: - Identity

    func testTheAppDoesNotCarryALegacyIdentity() {
        let identifier = Bundle(for: AppDelegate.self).bundleIdentifier ?? ""
        XCTAssertTrue(identifier.hasPrefix("com.nikklemenc.Scrollio"), identifier)
        XCTAssertFalse(LegacyMosTakeover.legacyBundleIdentifiers.contains(identifier))
        XCTAssertNotEqual(identifier, LegacyMosTakeover.legacyDefaultsDomain)
    }
}
