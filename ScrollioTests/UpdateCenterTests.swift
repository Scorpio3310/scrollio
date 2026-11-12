//
//  UpdateCenterTests.swift
//  ScrollioTests
//
//  The updater's own rules (UpdateCenter): which copy updates itself (a feed and a key in
//  the Info.plist, not from a disk image), what the app's Info.plist says, what Scrollio
//  shows while a found update waits (the Dock icon, its badge), the lines of the `app` log,
//  that Sparkle finds the delegate methods under the names it calls, that only the Update
//  folder knows Sparkle, that the release script and the app agree on the feed, and that
//  Sparkle's alerts ("You're up to date!") open so that the main queue keeps running.
//
//  No updater is started here: every start is one that must refuse, so nothing asks the
//  network. The Dock is replaced by counters, and no alert opens: what an open alert is
//  to the main thread, a run loop in the modal panel mode, is run without a window.
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

    /// A window that says what the test wants about itself; it is never shown.
    private final class FakeWindow: NSWindow {
        var shown = false
        var minimized = false
        override var isVisible: Bool { return shown }
        override var isMiniaturized: Bool { return minimized }
    }

    private func makeWindow(shown: Bool = false, minimized: Bool = false) -> FakeWindow {
        let window = FakeWindow(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.shown = shown
        window.minimized = minimized
        return window
    }

    /// When the updater lets the Dock icon go, an open settings window keeps it.
    func testAnOpenOrMinimizedWindowKeepsTheDockIcon() {
        XCTAssertFalse(Utils.hasOpenWindow([]))
        XCTAssertFalse(Utils.hasOpenWindow([nil]))
        XCTAssertFalse(Utils.hasOpenWindow([makeWindow(), nil]), "a window that was closed, or never shown")
        XCTAssertTrue(Utils.hasOpenWindow([makeWindow(shown: true)]))
        XCTAssertTrue(Utils.hasOpenWindow([nil, makeWindow(), makeWindow(minimized: true)]), "a minimized window is still open")
    }

    /// The last settings window that closes takes Scrollio out of the Dock, unless an
    /// update waits: its window must stay reachable with ⌘Tab.
    func testTheLastWindowLeavesTheDockOnlyWhenNoUpdateWaits() {
        XCTAssertTrue(Utils.closingWindowLeavesDock(managedWindows: 1, heldByUpdater: false))
        XCTAssertFalse(Utils.closingWindowLeavesDock(managedWindows: 1, heldByUpdater: true))
        XCTAssertFalse(Utils.closingWindowLeavesDock(managedWindows: 2, heldByUpdater: false), "another window of the app is open")
        XCTAssertFalse(Utils.closingWindowLeavesDock(managedWindows: 2, heldByUpdater: true))
        // What the app asks: the test host has no update waiting.
        XCTAssertFalse(Utils.dockIconIsHeld())
        let center = makeCenter(World())
        XCTAssertFalse(center.holdsDockIcon)
        center.updateWillBeShown(version: "1.0.2", userInitiated: true)
        XCTAssertTrue(center.holdsDockIcon)
        center.updateGotAttention()
        XCTAssertTrue(center.holdsDockIcon, "until the update is answered")
        center.updateSessionEnded()
        XCTAssertFalse(center.holdsDockIcon)
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
            "allowedSystemProfileKeysForUpdater:",
            "updater:didFindValidUpdate:",
            "updater:willInstallUpdate:",
            "updaterWillRelaunchApplication:",
            "updater:didFinishUpdateCycleForUpdateCheck:error:",
            // SPUStandardUserDriverDelegate
            "supportsGentleScheduledUpdateReminders",
            "standardUserDriverWillHandleShowingUpdate:forUpdate:state:",
            "standardUserDriverDidReceiveUserAttentionForUpdate:",
            "standardUserDriverWillFinishUpdateSession",
            "standardUserDriverWillShowModalAlert",
        ] {
            XCTAssertTrue(center.responds(to: NSSelectorFromString(name)), name)
        }
        XCTAssertEqual(center.value(forKey: "supportsGentleScheduledUpdateReminders") as? Bool, true)
        // Nothing of Sparkle's system profile may be sent, whatever the preferences say.
        let profileKeys = center.perform(NSSelectorFromString("allowedSystemProfileKeysForUpdater:"), with: nil)?.takeUnretainedValue() as? [String]
        XCTAssertEqual(profileKeys, [])
        XCTAssertTrue(center.conforms(to: try! XCTUnwrap(NSProtocolFromString("SPUUpdaterDelegate"))))
        XCTAssertTrue(center.conforms(to: try! XCTUnwrap(NSProtocolFromString("SPUStandardUserDriverDelegate"))))
    }

    // MARK: - Sparkle's windows, with its alerts opened from the run loop

    /// Everything Sparkle asks of its windows is answered by `UpdateWindows`, under the
    /// names Sparkle calls (the last one is optional: without it "Update to Scrollio …"
    /// could not bring a waiting update's window to the front).
    func testUpdateWindowsAnswersEverythingSparkleAsksOfItsWindows() {
        for name in [
            "showUpdatePermissionRequest:reply:",
            "showUserInitiatedUpdateCheckWithCancellation:",
            "showUpdateFoundWithAppcastItem:state:reply:",
            "showUpdateReleaseNotesWithDownloadData:",
            "showUpdateReleaseNotesFailedToDownloadWithError:",
            "showUpdateNotFoundWithError:acknowledgement:",
            "showUpdaterError:acknowledgement:",
            "showDownloadInitiatedWithCancellation:",
            "showDownloadDidReceiveExpectedContentLength:",
            "showDownloadDidReceiveDataOfLength:",
            "showDownloadDidStartExtractingUpdate",
            "showExtractionReceivedProgress:",
            "showReadyToInstallAndRelaunch:",
            "showInstallingUpdateWithApplicationTerminated:retryTerminatingApplication:",
            "showUpdateInstalledAndRelaunched:acknowledgement:",
            "dismissUpdateInstallation",
            "showUpdateInFocus",
        ] {
            XCTAssertTrue(UpdateWindows.instancesRespond(to: NSSelectorFromString(name)), name)
        }
        XCTAssertTrue(UpdateWindows.conforms(to: try! XCTUnwrap(NSProtocolFromString("SPUUserDriver"))))
    }

    /// Sparkle says "nothing newer", "failed" and "installed" with an alert that is modal
    /// for the whole app. The updater calls its windows inside a block of the main queue,
    /// and an alert opened there stops that queue until it is closed (the test after the
    /// next shows it). `UpdateWindows` hands each of the three to Sparkle's windows from
    /// the run loop and nowhere else, and the updater gets `UpdateWindows` and nothing
    /// else.
    func testTheThreeAlertsReachSparklesWindowsOnlyFromTheRunLoop() throws {
        let code = try codeOfUpdateCenter()
        for call in [
            "showUpdateNotFoundWithError(error, acknowledgement: acknowledgement)",
            "showUpdaterError(error, acknowledgement: acknowledgement)",
            "showUpdateInstalledAndRelaunched(relaunched, acknowledgement: acknowledgement)",
        ] {
            let name = String(call.prefix { $0 != "(" })
            let handedOver = "Self.fromTheRunLoop { [standard] in\n            standard.\(call)\n        }"
            XCTAssertEqual(code.components(separatedBy: handedOver).count - 1, 1, "\(name) is not handed to Sparkle's windows from the run loop")
            XCTAssertEqual(code.components(separatedBy: "standard.\(name)(").count - 1, 1, "\(name) reaches Sparkle's windows a second way")
        }
        // The way from the run loop is a timer in the common modes, and nothing in
        // UpdateWindows goes through the main queue.
        let windows = try XCTUnwrap(code.range(of: "final class UpdateWindows").flatMap { start in
            code.range(of: "final class UpdateCenter", range: start.upperBound..<code.endIndex).map { String(code[start.lowerBound..<$0.lowerBound]) }
        })
        XCTAssertTrue(windows.contains("_ = CommonModesTimer.scheduled(withTimeInterval: 0, repeats: false) { _ in work() }"))
        XCTAssertFalse(windows.contains("DispatchQueue"), "a block of the main queue is where an alert must not open")
        // The updater is given UpdateWindows, not Sparkle's own windows.
        XCTAssertTrue(code.contains("SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: windows, delegate: self)"))
        XCTAssertEqual(code.components(separatedBy: "SPUUpdater(hostBundle:").count - 1, 1)
        XCTAssertFalse(code.contains("SPUStandardUpdaterController("), "it would hand Sparkle's windows to the updater directly")
        // No alert of Scrollio's own in this file.
        XCTAssertFalse(code.contains("runModal"))
    }

    /// UpdateCenter.swift without its comment lines: a comment may name what the code must not do.
    private func codeOfUpdateCenter() throws -> String {
        return try String(contentsOf: repositoryRoot.appendingPathComponent("Scrollio/Update/UpdateCenter.swift"), encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.drop(while: { $0 == " " || $0 == "\t" }).hasPrefix("//") }
            .joined(separator: "\n")
    }

    // MARK: - An alert leaves the main queue running

    /// When a piece of work ran, seen from an alert.
    private enum Moment: String {
        case beforeItOpened, whileItWasOpen, afterItWasClosed
    }

    /// What an open alert is to the main thread. `NSAlert.runModal` runs the main run loop
    /// in the modal panel mode until the alert is closed; this does the same and shows
    /// nothing. (The real alert was measured with a throwaway app on 2026-11-12, macOS
    /// 27.2: opened through `UpdateWindows`, a block queued on the main queue when it
    /// opened ran at once; opened by Sparkle's windows directly, 1.5 s later, after the
    /// alert was closed.)
    private final class AlertStandIn {
        private var isOpen = false
        private var wasClosed = false

        var moment: Moment {
            if wasClosed { return .afterItWasClosed }
            return isOpen ? .whileItWasOpen : .beforeItOpened
        }

        /// Stays open until `done` says so, at most `limit` seconds.
        func runModal(until done: () -> Bool, limit: TimeInterval = 5, opened: () -> Void) {
            isOpen = true
            opened()
            let mode = CFRunLoopMode(RunLoop.Mode.modalPanel.rawValue as CFString)
            let end = CFAbsoluteTimeGetCurrent() + limit
            while !done() && CFAbsoluteTimeGetCurrent() < end {
                CFRunLoopRunInMode(mode, 0.01, true)
            }
            isOpen = false
            wasClosed = true
        }
    }

    /// A mach port source on the main run loop in the common modes: what an event tap is
    /// to the run loop (`Interceptor` adds its tap's source there). `send` is an event
    /// that arrives, from another thread as the system's do.
    private final class PortSource {
        var served: () -> Void = {}
        private var port: CFMachPort?
        private var source: CFRunLoopSource?

        init() {
            var context = CFMachPortContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
            port = CFMachPortCreate(nil, { _, _, _, info in
                guard let info else { return }
                Unmanaged<PortSource>.fromOpaque(info).takeUnretainedValue().served()
            }, &context, nil)
            source = port.flatMap { CFMachPortCreateRunLoopSource(nil, $0, 0) }
            if let source {
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            }
        }

        func send() {
            guard let port else { return }
            let name = CFMachPortGetPort(port)
            DispatchQueue.global().async {
                var message = mach_msg_header_t()
                message.msgh_bits = UInt32(MACH_MSG_TYPE_MAKE_SEND)
                message.msgh_size = mach_msg_size_t(MemoryLayout<mach_msg_header_t>.size)
                message.msgh_remote_port = name
                message.msgh_local_port = mach_port_t(MACH_PORT_NULL)
                mach_msg(&message, MACH_SEND_MSG, message.msgh_size, 0, mach_port_t(MACH_PORT_NULL), MACH_MSG_TIMEOUT_NONE, mach_port_t(MACH_PORT_NULL))
            }
        }

        func remove() {
            if let source {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            if let port {
                CFMachPortInvalidate(port)
            }
            source = nil
            port = nil
        }
    }

    /// Lets the main queue run what waits in it.
    private func drainTheMainQueue() {
        let drained = expectation(description: "the main queue ran")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { drained.fulfill() }
        wait(for: [drained], timeout: 5)
    }

    /// The rule the update dialogs must keep: while one is open, the main queue keeps
    /// running and the event taps keep being served. An alert opened the way
    /// `UpdateWindows` opens Sparkle's holds nothing back: not the blocks of the main
    /// queue (button actions, gesture follow-ups, the thumb wheel, the Logitech answers),
    /// not the timers in the common modes (the timeout that frees a held pointer, the
    /// keepers of the event taps), not a port source like an event tap's, and not the
    /// work that was queued in the same turn of the run loop.
    func testAnAlertOpenedFromTheRunLoopLeavesTheMainQueueRunning() throws {
        let alert = AlertStandIn()
        let port = PortSource()
        defer { port.remove() }
        var ran: [String: Moment] = [:]
        port.served = { ran["an event tap's source"] = alert.moment }
        let whileOpen = ["a block of the main queue", "a later block of the main queue", "a timer in the common modes", "an event tap's source"]
        let closed = expectation(description: "the alert was closed")

        UpdateWindows.fromTheRunLoop {
            alert.runModal(until: { whileOpen.allSatisfy { ran[$0] != nil } }, opened: {
                DispatchQueue.main.async { ran["a block of the main queue"] = alert.moment }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { ran["a later block of the main queue"] = alert.moment }
                _ = CommonModesTimer.scheduled(withTimeInterval: 0.05, repeats: false) { _ in ran["a timer in the common modes"] = alert.moment }
                port.send()
            })
            closed.fulfill()
        }
        XCTAssertEqual(alert.moment, .beforeItOpened, "the call returns at once; the alert opens in a later turn of the run loop")
        // Queued in the same turn, behind the alert.
        let sameTurn = ["a block of the main queue, same turn", "a timer, same turn", "a block of the run loop, same turn"]
        DispatchQueue.main.async { ran["a block of the main queue, same turn"] = alert.moment }
        _ = CommonModesTimer.scheduled(withTimeInterval: 0, repeats: false) { _ in ran["a timer, same turn"] = alert.moment }
        RunLoop.main.perform(inModes: [.common]) { ran["a block of the run loop, same turn"] = alert.moment }

        wait(for: [closed], timeout: 10)
        drainTheMainQueue()
        for work in whileOpen {
            XCTAssertEqual(ran[work], .whileItWasOpen, "\(work) waited for the alert")
        }
        for work in sameTurn {
            let moment = try XCTUnwrap(ran[work], "\(work) never ran")
            XCTAssertNotEqual(moment, .afterItWasClosed, "\(work) waited for the alert")
        }
        // The event taps' sources are in the common modes, as the port source above.
        let interceptor = try String(contentsOf: repositoryRoot.appendingPathComponent("Scrollio/Utils/Interceptor.swift"), encoding: .utf8)
        XCTAssertTrue(interceptor.contains("CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)"))
    }

    /// The trap itself, so that the test above cannot pass by accident. The same alert
    /// opened inside a block of the main queue, which is where the updater calls its
    /// windows, holds every other block of that queue until it is closed; timers and
    /// event taps go on. (Should a later macOS serve the queue there, this test fails and
    /// the detour through the run loop is no longer needed.)
    func testAnAlertOpenedInsideABlockOfTheMainQueueHoldsTheQueue() {
        let alert = AlertStandIn()
        let port = PortSource()
        defer { port.remove() }
        var ran: [String: Moment] = [:]
        port.served = { ran["an event tap's source"] = alert.moment }
        let closed = expectation(description: "the alert was closed")

        DispatchQueue.main.async {
            // Open for as long as the queue would need many times over.
            let end = CFAbsoluteTimeGetCurrent() + 0.4
            alert.runModal(until: { CFAbsoluteTimeGetCurrent() >= end }, opened: {
                DispatchQueue.main.async { ran["a block of the main queue"] = alert.moment }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { ran["a later block of the main queue"] = alert.moment }
                _ = CommonModesTimer.scheduled(withTimeInterval: 0.05, repeats: false) { _ in ran["a timer in the common modes"] = alert.moment }
                port.send()
            })
            closed.fulfill()
        }
        wait(for: [closed], timeout: 10)
        drainTheMainQueue()
        XCTAssertEqual(ran["a block of the main queue"], .afterItWasClosed)
        XCTAssertEqual(ran["a later block of the main queue"], .afterItWasClosed)
        XCTAssertEqual(ran["a timer in the common modes"], .whileItWasOpen)
        XCTAssertEqual(ran["an event tap's source"], .whileItWasOpen)
    }

    /// When an alert is about to open, Scrollio comes to the front (the check took a
    /// moment; the user may be in another app). The Dock is left alone: a menu bar app
    /// that becomes a Dock app at that moment gets its alert on the desktop Space, out of
    /// sight for someone in a full-screen app.
    func testAnAlertBringsScrollioToTheFrontAndLeavesTheDockAlone() {
        let world = World()
        let center = makeCenter(world)
        center.alertWillOpen()
        XCTAssertEqual(world.activations, 1)
        // As Sparkle says it.
        center.perform(NSSelectorFromString("standardUserDriverWillShowModalAlert"))
        XCTAssertEqual(world.activations, 2)
        XCTAssertEqual(world.dockShown, 0)
        XCTAssertEqual(world.dockReleased, 0)
        XCTAssertEqual(world.badges, [])
        XCTAssertFalse(center.holdsDockIcon)
        XCTAssertEqual(center.reminder, UpdateReminder())
        // While an update waits, its Dock icon stays through an alert (a failed download).
        center.updateWillBeShown(version: "1.0.2", userInitiated: true)
        center.alertWillOpen()
        XCTAssertTrue(center.holdsDockIcon)
        XCTAssertEqual(world.dockShown, 1)
        XCTAssertEqual(world.dockReleased, 0)
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
