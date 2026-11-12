//
//  UpdateCenterTests.swift
//  ScrollioTests
//
//  The updater's own rules (UpdateCenter): which copy updates itself (a feed and a key in
//  the Info.plist, not from a disk image), what the app's Info.plist says, what Scrollio
//  shows while a found update waits (the Dock icon, its badge), the lines of the `app` log,
//  that Sparkle finds the delegate methods under the names it calls, that only the Update
//  folder knows Sparkle, and that the release script and the app agree on the feed.
//
//  No updater is started here: every start is one that must refuse, so nothing asks the
//  network. The Dock is replaced by counters.
//

import XCTest
@testable import Scrollio_Debug

final class UpdateCenterTests: XCTestCase {

    /// 32 bytes, base64: the shape of an Ed25519 public key.
    private static let someKey = Data(repeating: 7, count: 32).base64EncodedString()
    private static let feed = "https://github.com/Scorpio3310/scrollio/releases/latest/download/appcast.xml"

    /// What a center did to the outside.
    private final class World {
        var dockShown = 0
        var dockReleased = 0
        var badges: [String?] = []
        var activations = 0
        var log: [String] = []
    }

    private func makeCenter(_ world: World) -> UpdateCenter {
        let center = UpdateCenter()
        center.showDockIcon = { world.dockShown += 1 }
        center.releaseDockIcon = { world.dockReleased += 1 }
        center.setDockBadge = { world.badges.append($0) }
        center.activateApp = { world.activations += 1 }
        center.log = { world.log.append($0) }
        return center
    }

    private var repositoryRoot: URL {
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ScrollioTests/
            .deletingLastPathComponent()   // the repository
    }

    // MARK: - Which copy updates itself

    func testAFeedAndAKeyMakeAConfiguration() {
        let configuration = UpdateCenter.configuration(info: ["SUFeedURL": " \(Self.feed)\n", "SUPublicEDKey": Self.someKey])
        XCTAssertEqual(configuration?.feedURL.absoluteString, Self.feed)
        XCTAssertEqual(configuration?.publicKey, Self.someKey)
    }

    func testWithoutAFeedOrAKeyThereIsNone() {
        XCTAssertNil(UpdateCenter.configuration(info: [:]))
        XCTAssertNil(UpdateCenter.configuration(info: ["SUFeedURL": "", "SUPublicEDKey": Self.someKey]))
        XCTAssertNil(UpdateCenter.configuration(info: ["SUFeedURL": Self.feed]))
        XCTAssertNil(UpdateCenter.configuration(info: ["SUFeedURL": Self.feed, "SUPublicEDKey": ""]))
        // What an Info.plist holds when the build setting was never set.
        XCTAssertNil(UpdateCenter.configuration(info: ["SUFeedURL": "$(SCROLLIO_UPDATE_FEED)", "SUPublicEDKey": Self.someKey]))
    }

    func testTheFeedMustBeHTTPSWithAHost() {
        for feed in ["http://github.com/a/appcast.xml", "file:///tmp/appcast.xml", "ftp://example.com/a.xml", "https://", "appcast.xml", "https:///appcast.xml"] {
            XCTAssertNil(UpdateCenter.configuration(info: ["SUFeedURL": feed, "SUPublicEDKey": Self.someKey]), feed)
        }
    }

    func testTheKeyMustBe32Bytes() {
        let short = Data(repeating: 1, count: 31).base64EncodedString()
        let long = Data(repeating: 1, count: 64).base64EncodedString()
        for key in [short, long, "not base64 at all!", "SCROLLIO_PUBLIC_KEY_PLACEHOLDER"] {
            XCTAssertNil(UpdateCenter.configuration(info: ["SUFeedURL": Self.feed, "SUPublicEDKey": key]), key)
        }
    }

    func testACopyWithoutAFeedStartsNothing() {
        let world = World()
        let center = makeCenter(world)
        center.start(info: ["SUPublicEDKey": Self.someKey], runsFromWrongPlace: false)
        XCTAssertEqual(center.availability, .builtFromSource)
        XCTAssertEqual(center.status, UpdateStatus(availability: .builtFromSource))
        XCTAssertFalse(center.status.isAvailable)
        XCTAssertFalse(center.status.canCheck)
        XCTAssertNil(center.configuration)
        XCTAssertEqual(world.log.count, 1)
        XCTAssertTrue(world.log[0].hasPrefix("Updates: off, this copy has no update feed"), world.log[0])
        // Its calls do nothing.
        center.checkForUpdates()
        center.setChecksAutomatically(true)
        center.setInstallsAutomatically(true)
        XCTAssertEqual(world.activations, 0)
        XCTAssertEqual(center.status, UpdateStatus(availability: .builtFromSource))
    }

    func testAFeedWithAnUnusableKeyStartsNothingAndSaysSo() {
        let world = World()
        let center = makeCenter(world)
        center.start(info: ["SUFeedURL": Self.feed, "SUPublicEDKey": "nonsense"], runsFromWrongPlace: false)
        XCTAssertEqual(center.availability, .failed)
        XCTAssertNil(center.configuration)
        XCTAssertEqual(world.log, ["Updates: off, the feed address or the public key in this build's Info.plist is not usable"])
    }

    func testFromADiskImageNothingStarts() {
        let world = World()
        let center = makeCenter(world)
        center.start(info: ["SUFeedURL": Self.feed, "SUPublicEDKey": Self.someKey], runsFromWrongPlace: true)
        XCTAssertEqual(center.availability, .wrongPlace)
        XCTAssertFalse(center.status.isAvailable)
        XCTAssertNil(center.configuration)
        XCTAssertEqual(world.log, ["Updates: off while Scrollio runs from a disk image or a translocated copy"])
    }

    /// A test can hand in a feed and a key that would do: still nothing starts, so no
    /// test run ever asks the network.
    func testUnderTestsNoUpdaterStartsWhateverTheConfiguration() {
        let world = World()
        let center = makeCenter(world)
        center.start(info: ["SUFeedURL": Self.feed, "SUPublicEDKey": Self.someKey], runsFromWrongPlace: false)
        XCTAssertEqual(center.availability, .failed)
        XCTAssertFalse(center.status.isAvailable)
        XCTAssertNil(center.configuration)
        XCTAssertEqual(world.log, ["Updates: off, no updater starts while the tests run"])
    }

    /// The center the app uses leaves the Dock and the front app alone under tests, also
    /// when a test forgets to replace its seams.
    func testTheAppsOwnCenterTouchesNothingUnderTests() {
        let center = UpdateCenter()
        center.log = { _ in }
        let policy = NSApp.activationPolicy()
        let badge = NSApp.dockTile.badgeLabel
        center.updateWillBeShown(version: "9.9.9", userInitiated: false)
        XCTAssertEqual(NSApp.activationPolicy(), policy)
        XCTAssertEqual(NSApp.dockTile.badgeLabel, badge)
        center.updateSessionEnded()
        XCTAssertEqual(NSApp.activationPolicy(), policy)
        XCTAssertFalse(center.mayStart())
    }

    // MARK: - The app's Info.plist

    /// The tests run in the debug build: a copy that was not built by scripts/release.sh.
    func testTheAppHasTheKeyAndTheSafetySettingsButNoFeed() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        XCTAssertEqual(UpdateCenter.value("SUFeedURL", in: info), "", "only scripts/release.sh gives a build its feed")
        let key = UpdateCenter.value("SUPublicEDKey", in: info)
        XCTAssertEqual(Data(base64Encoded: key)?.count, 32, "SUPublicEDKey is the public key the updates are checked with")
        XCTAssertEqual(info["SUVerifyUpdateBeforeExtraction"] as? Bool, true, "a download is checked before it is opened")
        XCTAssertEqual(info["SUEnableSystemProfiling"] as? Bool, false, "nothing about the Mac is sent with a check")
        XCTAssertNil(info["SUEnableAutomaticChecks"], "the user is asked once whether to check automatically")
        XCTAssertNil(info["SUAutomaticallyUpdate"], "nothing installs itself unless the user chose that")
        XCTAssertNil(info["SUEnableJavaScript"])
        // With the feed the release script writes, this Info.plist is a usable configuration.
        var released = info
        released["SUFeedURL"] = Self.feed
        XCTAssertNotNil(UpdateCenter.configuration(info: released))
    }

    func testTheSharedCenterOfTheTestHostDoesNotUpdateItself() {
        XCTAssertFalse(UpdateCenter.shared.status.isAvailable)
        XCTAssertFalse(UpdateCenter.shared.holdsDockIcon)
    }

    /// The feed is written in one place, the release script; it is the address of the
    /// file "appcast.xml" of the newest release of the repository General links to.
    func testTheReleaseScriptWritesTheFeedOfThisRepository() throws {
        let script = try String(contentsOf: repositoryRoot.appendingPathComponent("scripts/release.sh"), encoding: .utf8)
        let repository = PreferencesGeneralViewController.gitHubURL.absoluteString
        XCTAssertEqual(repository + "/releases/latest/download/appcast.xml", Self.feed)
        XCTAssertTrue(script.contains("UPDATE_FEED=\"\(Self.feed)\""), "scripts/release.sh no longer sets the feed \(Self.feed)")
        XCTAssertTrue(script.contains("SCROLLIO_UPDATE_FEED=\"$UPDATE_FEED\""), "scripts/release.sh no longer passes the feed to the build")
    }

    // MARK: - While an update waits

    func testAnUpdateFoundByAScheduledCheckShowsInTheDockWithABadge() {
        let world = World()
        let center = makeCenter(world)
        var changes = 0
        let observer = NotificationCenter.default.addObserver(forName: UpdateCenter.didChangeNotification, object: center, queue: nil) { _ in changes += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        center.updateWillBeShown(version: "1.1.0", userInitiated: false)
        XCTAssertEqual(center.reminder.waitingVersion, "1.1.0")
        XCTAssertTrue(center.reminder.showsBadge)
        XCTAssertTrue(center.holdsDockIcon)
        XCTAssertEqual(world.dockShown, 1)
        XCTAssertEqual(world.badges, ["1"])
        XCTAssertEqual(changes, 1)

        // The user brings the window to the front: the badge goes, the icon stays.
        center.updateGotAttention()
        XCTAssertEqual(center.reminder.waitingVersion, "1.1.0")
        XCTAssertFalse(center.reminder.showsBadge)
        XCTAssertTrue(center.holdsDockIcon)
        XCTAssertEqual(world.badges, ["1", nil])
        XCTAssertEqual(world.dockReleased, 0)

        // Installed, skipped or postponed.
        center.updateSessionEnded()
        XCTAssertEqual(center.reminder, UpdateReminder())
        XCTAssertFalse(center.holdsDockIcon)
        XCTAssertEqual(world.dockReleased, 1)
        XCTAssertEqual(world.badges, ["1", nil, nil])
        XCTAssertEqual(changes, 2)
    }

    func testAnUpdateTheUserAskedForGetsNoBadge() {
        let world = World()
        let center = makeCenter(world)
        center.updateWillBeShown(version: "2.0.0", userInitiated: true)
        XCTAssertEqual(center.reminder.waitingVersion, "2.0.0")
        XCTAssertFalse(center.reminder.showsBadge)
        XCTAssertEqual(world.dockShown, 1, "the window can be reached with ⌘Tab")
        XCTAssertEqual(world.badges, [nil])
    }

    /// A check that found nothing, or one that failed, also ends a session: the Dock icon
    /// is not Scrollio's to take away then (the settings window may be open).
    func testASessionWithoutAnUpdateLeavesTheDockAlone() {
        let world = World()
        let center = makeCenter(world)
        center.updateSessionEnded()
        XCTAssertEqual(world.dockShown, 0)
        XCTAssertEqual(world.dockReleased, 0)
        XCTAssertEqual(world.badges, [nil])
    }

    func testTheReminderAlone() {
        var reminder = UpdateReminder()
        XCTAssertNil(reminder.waitingVersion)
        XCTAssertFalse(reminder.showsBadge)
        reminder.userLooked()
        XCTAssertEqual(reminder, UpdateReminder())
        reminder.willShow(version: "1.2", userInitiated: false)
        reminder.willShow(version: "1.3", userInitiated: false)
        XCTAssertEqual(reminder.waitingVersion, "1.3", "the newest one found")
        XCTAssertTrue(reminder.showsBadge)
        reminder.sessionEnded()
        XCTAssertEqual(reminder, UpdateReminder())
    }

    // MARK: - The Dock icon

    func testAnOpenOrMinimizedWindowKeepsTheDockIcon() {
        XCTAssertFalse(Utils.hasOpenWindow([]))
        XCTAssertFalse(Utils.hasOpenWindow([nil]))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        XCTAssertFalse(Utils.hasOpenWindow([window, nil]), "a window that was never shown")
    }

    // MARK: - The log

    func testOneLinePerCheck() {
        XCTAssertEqual(UpdateCenter.cycleLogLine(kind: .scheduled, error: nil), "Updates: a scheduled check ended")
        XCTAssertEqual(UpdateCenter.cycleLogLine(kind: .askedFor, error: nil), "Updates: the check the user asked for ended")
        let none = NSError(domain: UpdateCenter.sparkleErrorDomain, code: UpdateCenter.noUpdateErrorCode)
        XCTAssertEqual(UpdateCenter.cycleLogLine(kind: .scheduled, error: none), "Updates: a scheduled check found no newer version")
        let cancelled = NSError(domain: UpdateCenter.sparkleErrorDomain, code: UpdateCenter.installationCanceledErrorCode)
        XCTAssertEqual(
            UpdateCenter.cycleLogLine(kind: .askedFor, error: cancelled),
            "Updates: the check the user asked for ended, the installation was cancelled"
        )
        let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: [NSLocalizedDescriptionKey: "The Internet connection appears to be offline."])
        XCTAssertEqual(
            UpdateCenter.cycleLogLine(kind: .feedOnly, error: offline),
            "Updates: a look at the feed failed: The Internet connection appears to be offline. (NSURLErrorDomain -1009)"
        )
        // The same number in another domain is a failure.
        let other = NSError(domain: "Other", code: UpdateCenter.noUpdateErrorCode, userInfo: [NSLocalizedDescriptionKey: "x"])
        XCTAssertEqual(UpdateCenter.cycleLogLine(kind: .scheduled, error: other), "Updates: a scheduled check failed: x (Other \(UpdateCenter.noUpdateErrorCode))")
    }

    func testSparklesErrorNumbersAreTheOnesItDocuments() {
        XCTAssertEqual(UpdateCenter.sparkleErrorDomain, "SUSparkleErrorDomain")
        XCTAssertEqual(UpdateCenter.noUpdateErrorCode, 1001)
        XCTAssertEqual(UpdateCenter.installationCanceledErrorCode, 4007)
    }

    // MARK: - Sparkle's side

    /// Sparkle's delegate methods are optional: one written under a slightly different
    /// name compiles and is never called. These are the names Sparkle 2 calls.
    func testSparkleFindsTheDelegateMethods() {
        let center = UpdateCenter()
        for name in [
            // SPUUpdaterDelegate
            "feedURLStringForUpdater:",
            "updater:didFindValidUpdate:",
            "updater:willInstallUpdate:",
            "updaterWillRelaunchApplication:",
            "updater:didFinishUpdateCycleForUpdateCheck:error:",
            // SPUStandardUserDriverDelegate
            "supportsGentleScheduledUpdateReminders",
            "standardUserDriverWillHandleShowingUpdate:forUpdate:state:",
            "standardUserDriverDidReceiveUserAttentionForUpdate:",
            "standardUserDriverWillFinishUpdateSession",
        ] {
            XCTAssertTrue(center.responds(to: NSSelectorFromString(name)), name)
        }
        XCTAssertEqual(center.value(forKey: "supportsGentleScheduledUpdateReminders") as? Bool, true)
        XCTAssertTrue(center.conforms(to: try! XCTUnwrap(NSProtocolFromString("SPUUpdaterDelegate"))))
        XCTAssertTrue(center.conforms(to: try! XCTUnwrap(NSProtocolFromString("SPUStandardUserDriverDelegate"))))
    }

    /// Only the Update folder imports Sparkle; the rest of the app sees UpdateStatus.
    func testOnlyTheUpdateFolderKnowsSparkle() throws {
        let sources = repositoryRoot.appendingPathComponent("Scrollio")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var importing: [String] = []
        var seen = 0
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            seen += 1
            let text = try String(contentsOf: file, encoding: .utf8)
            let imports = text.split(separator: "\n").contains { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed == "import Sparkle" || trimmed.hasPrefix("import Sparkle.") || trimmed == "@preconcurrency import Sparkle"
            }
            if imports {
                // The folder and the file ("/tmp" and "/private/tmp" are one place with two names).
                importing.append(file.pathComponents.suffix(2).joined(separator: "/"))
            }
        }
        XCTAssertGreaterThan(seen, 100, "the sources were not found at \(sources.path)")
        XCTAssertEqual(importing, ["Update/UpdateCenter.swift"])
    }
}
