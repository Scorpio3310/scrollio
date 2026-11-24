//
//  DockFollowTests.swift
//  ScrollioTests
//
//  "Up and Down follow the hand too", the part that decides: which listed actions have a
//  view of the Dock to open with the hand, the numbers of the two motions and the travel
//  they give, the Dock's own switches for its trackpad gestures (decoded from values a
//  test makes up; the Mac's are never read), on which Mac a view follows, and the one
//  answer to "what does this direction follow". All of it is pure: nothing is posted and
//  nothing of the Mac's settings is looked at.
//  (The events are in DockSwipeSynthesizerTests, the stored switch in
//  MouseGestureInteractiveModeTests, ApplicationGesturesTests and SettingsFileTests.)
//

import XCTest
@testable import Scrollio_Debug

// MARK: - What can follow

final class DockFollowTargetTests: XCTestCase {

    /// Of everything the action menu lists, three actions show a view of the Dock that a
    /// trackpad opens with a gesture. "appExpose" is the F4 key (Launchpad, Apps), not App
    /// Exposé.
    func testOnlyThreeListedActionsHaveATarget() {
        XCTAssertEqual(DockFollowTarget(actionIdentifier: "missionControl"), .missionControl)
        XCTAssertEqual(DockFollowTarget(actionIdentifier: "showDesktop"), .showDesktop)
        XCTAssertEqual(DockFollowTarget(actionIdentifier: "appExpose"), .apps)

        XCTAssertGreaterThan(SystemShortcut.allShortcuts.count, 20, "the listed actions were found")
        let withATarget = SystemShortcut.allShortcuts.keys.filter { DockFollowTarget(actionIdentifier: $0) != nil }
        XCTAssertEqual(withATarget.sorted(), ["appExpose", "missionControl", "showDesktop"])

        let others = [
            "", "moveSpaceLeft", "moveSpaceRight", "copy", "shortcutRing", "mouseGestureNavigation",
            "custom::160:0", "MissionControl", "apps", "launchpad", "com.apple.expose.awake",
        ]
        for other in others {
            XCTAssertNil(DockFollowTarget(actionIdentifier: other), other)
        }
    }

    /// Mission Control is the vertical motion; Show Desktop and Apps are the two ends of
    /// the pinch. Positive progress opens Mission Control and Show Desktop.
    func testEachTargetNamesItsActionItsMotionAndItsSign() {
        XCTAssertEqual(DockFollowTarget.allCases, [.missionControl, .showDesktop, .apps])
        for target in DockFollowTarget.allCases {
            XCTAssertEqual(DockFollowTarget(actionIdentifier: target.actionIdentifier), target)
            XCTAssertNotNil(SystemShortcut.allShortcuts[target.actionIdentifier], "\(target) is a listed action")
            XCTAssertEqual(abs(target.sign), 1, "\(target)")
        }
        XCTAssertEqual(DockFollowTarget.missionControl.actionIdentifier, SystemShortcut.missionControl.identifier)
        XCTAssertEqual(DockFollowTarget.showDesktop.actionIdentifier, SystemShortcut.showDesktop.identifier)
        XCTAssertEqual(DockFollowTarget.apps.actionIdentifier, SystemShortcut.appExpose.identifier)

        XCTAssertEqual(DockFollowTarget.missionControl.axis, .vertical)
        XCTAssertEqual(DockFollowTarget.showDesktop.axis, .pinch)
        XCTAssertEqual(DockFollowTarget.apps.axis, .pinch)
        XCTAssertEqual(DockFollowTarget.missionControl.sign, 1)
        XCTAssertEqual(DockFollowTarget.showDesktop.sign, 1)
        XCTAssertEqual(DockFollowTarget.apps.sign, -1, "the other end of the pinch")
    }

    func testTheTargetOfWhatADirectionRuns() {
        XCTAssertEqual(DockFollowTarget(action: GestureActions.default.up), .missionControl)
        XCTAssertEqual(DockFollowTarget(action: GestureActions.default.down), .apps)
        XCTAssertNil(DockFollowTarget(action: GestureActions.default.left))
        XCTAssertEqual(DockFollowTarget(action: GestureAction(SystemShortcut.showDesktop)), .showDesktop)
        XCTAssertNil(DockFollowTarget(action: .none))
        XCTAssertNil(DockFollowTarget(action: GestureAction(SystemShortcut.copy)))
        // The Mission Control key, recorded as a key combination, is a key press like any other.
        let recorded = GestureAction(action: "custom::160:0", label: ShortcutLabel(name: "Mission Control", icon: nil))
        XCTAssertNotNil(recorded.keys)
        XCTAssertNil(DockFollowTarget(action: recorded))
    }
}

// MARK: - The numbers and the travel

final class DockFollowTuningTests: XCTestCase {

    private func travel(_ target: DockFollowTarget, height: CGFloat) -> CGFloat {
        return DockSwipeGeometry.followTravel(for: target, screenHeight: height)
    }

    private func perPoint(_ target: DockFollowTarget, height: CGFloat, speed: Double) -> Double {
        return DockSwipeGeometry.followProgressPerPoint(for: target, screenHeight: height, trackingSpeed: speed)
    }

    /// The first values. Changing one is a change of how a hold feels: it is pinned here so
    /// that it is changed on purpose.
    func testTheNumbers() {
        XCTAssertEqual(DockFollowTuning.fullProgress, 1)
        XCTAssertEqual(DockFollowTuning.travelScreenShare, 0.40)
        XCTAssertEqual(DockFollowTuning.travelRange, 320...600)
        XCTAssertEqual(DockFollowTuning.appsTravelFactor, 0.75)
        XCTAssertEqual(DockFollowTuning.travelFactor(for: .missionControl), 1)
        XCTAssertEqual(DockFollowTuning.travelFactor(for: .showDesktop), 1)
        XCTAssertEqual(DockFollowTuning.travelFactor(for: .apps), 0.75)
        XCTAssertEqual(DockFollowTuning.reverseTolerance, 8)
        XCTAssertEqual(DockFollowTuning.maximumTravelsPerSecond, 12)
    }

    /// Travel to a whole view at Swipe speed 1: 40 % of the screen's height, between 320 and
    /// 600 pt, three quarters of it for Apps.
    func testTravelIsAShareOfTheScreenHeightWithinBounds() {
        // A 1512 × 982 screen, and a 2560 × 1440 one.
        for target in [DockFollowTarget.missionControl, .showDesktop] {
            XCTAssertEqual(travel(target, height: 982), 392.8, accuracy: 1e-9, "\(target)")
            XCTAssertEqual(travel(target, height: 1440), 576, accuracy: 1e-9, "\(target)")
            // The bounds.
            XCTAssertEqual(travel(target, height: 600), 320, "\(target): a small screen")
            XCTAssertEqual(travel(target, height: 800), 320, accuracy: 1e-9, "\(target)")
            XCTAssertEqual(travel(target, height: 1500), 600, accuracy: 1e-9, "\(target)")
            XCTAssertEqual(travel(target, height: 2160), 600, "\(target): a large screen")
        }
        XCTAssertEqual(travel(.apps, height: 982), 294.6, accuracy: 1e-9)
        XCTAssertEqual(travel(.apps, height: 1440), 432, accuracy: 1e-9)
        XCTAssertEqual(travel(.apps, height: 600), 240)
        XCTAssertEqual(travel(.apps, height: 2160), 450)

        // A height that is none: still a travel within the bounds.
        for target in DockFollowTarget.allCases {
            let factor = DockFollowTuning.travelFactor(for: target)
            for height in [CGFloat(0), -500, .nan, .infinity, -.infinity, .greatestFiniteMagnitude] {
                let points = travel(target, height: height)
                XCTAssertTrue(points.isFinite, "\(target), \(height)")
                XCTAssertGreaterThanOrEqual(points, 320 * factor, "\(target), \(height)")
                XCTAssertLessThanOrEqual(points, 600 * factor, "\(target), \(height)")
            }
        }
        // The fallback screen and a screen made without a height.
        XCTAssertEqual(InteractiveGestureScreen.defaultHeight, 900)
        XCTAssertEqual(InteractiveGestureEnvironment.fallbackScreen.height, 900)
        XCTAssertEqual(InteractiveGestureScreen(width: 937, spaceCount: nil, frameDuration: 1.0 / 60.0).height, 900)
        XCTAssertEqual(travel(.missionControl, height: InteractiveGestureScreen.defaultHeight), 360, accuracy: 1e-9)
        XCTAssertEqual(travel(.missionControl, height: .nan), 360, accuracy: 1e-9, "counted as the default screen's")
    }

    /// Progress per point is the speed over the travel: after the travel the view is whole
    /// at speed 1, after half of it at speed 2.
    func testProgressPerPointIsTheSpeedOverTheTravel() {
        for target in DockFollowTarget.allCases {
            for height in [CGFloat(600), 982, 1440, 2160] {
                let points = Double(travel(target, height: height))
                let one = perPoint(target, height: height, speed: 1)
                XCTAssertEqual(one * points, DockFollowTuning.fullProgress, accuracy: 1e-12, "\(target), \(height)")
                XCTAssertEqual(one, 1 / points, accuracy: 1e-15, "\(target), \(height)")
                XCTAssertEqual(perPoint(target, height: height, speed: 2), 2 * one, accuracy: 1e-15, "\(target), \(height)")
                XCTAssertEqual(perPoint(target, height: height, speed: 0.5) * points, 0.5, accuracy: 1e-12, "\(target), \(height)")
                XCTAssertGreaterThan(one, 0, "the direction is the target's sign, not the scale's")
            }
        }
        // The travel table at Swipe speed 0.5, 1, 2 and 3 on a 1512 × 982 screen.
        func pointsToWhole(_ target: DockFollowTarget, speed: Double) -> Double {
            return DockFollowTuning.fullProgress / perPoint(target, height: 982, speed: speed)
        }
        XCTAssertEqual(pointsToWhole(.missionControl, speed: 0.5), 785.6, accuracy: 1e-9)
        XCTAssertEqual(pointsToWhole(.missionControl, speed: 1), 392.8, accuracy: 1e-9)
        XCTAssertEqual(pointsToWhole(.showDesktop, speed: 2), 196.4, accuracy: 1e-9)
        XCTAssertEqual(pointsToWhole(.showDesktop, speed: 3), 392.8 / 3, accuracy: 1e-9)
        XCTAssertEqual(pointsToWhole(.apps, speed: 1), 294.6, accuracy: 1e-9)
        XCTAssertEqual(pointsToWhole(.apps, speed: 3), 98.2, accuracy: 1e-9)

        for height in [CGFloat(0), .nan, .infinity] {
            XCTAssertTrue(perPoint(.missionControl, height: height, speed: 1).isFinite, "\(height)")
            XCTAssertGreaterThan(perPoint(.apps, height: height, speed: 3), 0, "\(height)")
        }
    }

    /// At the fastest Swipe speed on the smallest travel, half way is still no nearer than
    /// the distance at which the one-action gesture runs: the followed form is never more
    /// of a hair trigger than the classic one.
    func testHalfWayIsNeverNearerThanTheOneActionGesture() {
        let fastest = MouseGestureSettings.trackingSpeedRange.upperBound
        for target in DockFollowTarget.allCases {
            let smallest = Double(travel(target, height: 0))
            let halfWay = smallest / fastest / 2
            XCTAssertGreaterThanOrEqual(halfWay, Double(MouseGestureRecognizer.defaultActivationDistance), "\(target)")
        }
    }
}

// MARK: - The Dock's own switches

final class DockGestureSwitchesTests: XCTestCase {

    override func tearDown() {
        // The reader of the app again (which reads nothing under XCTest: all on).
        DockGestureSwitches.read = DockGestureSwitches.systemValue
        DockGestureSwitches.reload()
        super.tearDown()
    }

    /// The Dock's own names. They are another app's: a typo here would read nothing and
    /// count every gesture as on.
    func testTheNamesAreTheDocksOwn() {
        XCTAssertEqual(DockGestureSwitches.domain, "com.apple.dock")
        XCTAssertEqual(DockGestureSwitches.Key.allCases.map(\.rawValue), [
            "showMissionControlGestureEnabled", "showDesktopGestureEnabled", "showLaunchpadGestureEnabled",
        ])
    }

    /// A stored "false" is off. A missing name counts as on, and so does what is no switch
    /// at all: the values are another app's data and may be anything.
    func testAStoredFalseIsOffAndEverythingElseCountsAsOn() {
        XCTAssertTrue(DockGestureSwitches.isOn(nil), "a missing name")
        XCTAssertTrue(DockGestureSwitches.isOn(true))
        XCTAssertFalse(DockGestureSwitches.isOn(false))
        XCTAssertTrue(DockGestureSwitches.isOn(kCFBooleanTrue))
        XCTAssertFalse(DockGestureSwitches.isOn(kCFBooleanFalse))
        XCTAssertFalse(DockGestureSwitches.isOn(NSNumber(value: 0)), "written as a number")
        XCTAssertTrue(DockGestureSwitches.isOn(NSNumber(value: 1)))
        let noSwitch: [Any] = ["NO", "false", "", NSNull(), Date(timeIntervalSince1970: 0), [false], ["on": false], Data()]
        for value in noSwitch {
            XCTAssertTrue(DockGestureSwitches.isOn(value), "\(value)")
        }
    }

    func testEachSwitchIsReadUnderItsOwnName() {
        var asked: [DockGestureSwitches.Key] = []
        let nothingStored = DockGestureSwitches(reading: { key in
            asked.append(key)
            return nil
        })
        XCTAssertEqual(nothingStored, .allOn, "a Mac that never had a trackpad")
        XCTAssertEqual(Set(asked), Set(DockGestureSwitches.Key.allCases))
        XCTAssertEqual(asked.count, 3, "each once, and nothing else")

        XCTAssertEqual(
            DockGestureSwitches(reading: { $0 == .missionControl ? false : nil }),
            DockGestureSwitches(missionControl: false, showDesktop: true, launchpad: true)
        )
        XCTAssertEqual(
            DockGestureSwitches(reading: { $0 == .showDesktop ? false : true }),
            DockGestureSwitches(missionControl: true, showDesktop: false, launchpad: true)
        )
        XCTAssertEqual(
            DockGestureSwitches(reading: { $0 == .launchpad ? NSNumber(value: 0) : "yes" }),
            DockGestureSwitches(missionControl: true, showDesktop: true, launchpad: false)
        )
        XCTAssertEqual(
            DockGestureSwitches(reading: { _ in false }),
            DockGestureSwitches(missionControl: false, showDesktop: false, launchpad: false)
        )
    }

    /// Mission Control and Show Desktop have their own switch on every macOS. Launchpad had
    /// one until macOS 15; from macOS 26 the Show Desktop switch stands for Apps too.
    func testWhichSwitchGovernsWhichTarget() {
        let noMissionControl = DockGestureSwitches(missionControl: false, showDesktop: true, launchpad: true)
        let noShowDesktop = DockGestureSwitches(missionControl: true, showDesktop: false, launchpad: true)
        let noLaunchpad = DockGestureSwitches(missionControl: true, showDesktop: true, launchpad: false)
        for major in [14, 15, 26, 27, 28] {
            for target in DockFollowTarget.allCases {
                XCTAssertTrue(DockGestureSwitches.allOn.allows(target, majorVersion: major), "\(target), macOS \(major)")
            }
            XCTAssertFalse(noMissionControl.allows(.missionControl, majorVersion: major), "macOS \(major)")
            XCTAssertTrue(noMissionControl.allows(.showDesktop, majorVersion: major), "macOS \(major)")
            XCTAssertTrue(noMissionControl.allows(.apps, majorVersion: major), "macOS \(major)")
            XCTAssertTrue(noShowDesktop.allows(.missionControl, majorVersion: major), "macOS \(major)")
            XCTAssertFalse(noShowDesktop.allows(.showDesktop, majorVersion: major), "macOS \(major)")
            XCTAssertTrue(noLaunchpad.allows(.missionControl, majorVersion: major), "macOS \(major)")
            XCTAssertTrue(noLaunchpad.allows(.showDesktop, majorVersion: major), "macOS \(major)")
        }
        for major in [14, 15, 25] {
            XCTAssertFalse(noLaunchpad.allows(.apps, majorVersion: major), "macOS \(major): Launchpad's own switch")
            XCTAssertTrue(noShowDesktop.allows(.apps, majorVersion: major), "macOS \(major)")
        }
        for major in [26, 27, 28] {
            XCTAssertTrue(noLaunchpad.allows(.apps, majorVersion: major), "macOS \(major): that switch is gone")
            XCTAssertFalse(noShowDesktop.allows(.apps, majorVersion: major), "macOS \(major): Show Desktop's stands for Apps")
        }
    }

    /// A read keeps its answer: a hold takes it without reading anything. A read that
    /// finds a change says so once (the pane's line follows it); one that finds none is silent.
    func testAReloadReadsThroughTheSeamKeepsTheAnswerAndSaysWhenItChanged() {
        var reads = 0
        DockGestureSwitches.read = { key in
            reads += 1
            return key == .showDesktop ? false : nil
        }
        var changes = 0
        let observer = NotificationCenter.default.addObserver(
            forName: DockGestureSwitches.didChangeNotification, object: nil, queue: nil
        ) { _ in changes += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        XCTAssertEqual(DockGestureSwitches.current, .allOn, "nothing is read until someone asks")
        XCTAssertEqual(reads, 0)

        DockGestureSwitches.reload()
        XCTAssertEqual(reads, 3)
        XCTAssertEqual(DockGestureSwitches.current, DockGestureSwitches(missionControl: true, showDesktop: false, launchpad: true))
        XCTAssertEqual(DockFollowAvailability.live.switches, DockGestureSwitches.current)
        XCTAssertEqual(changes, 1)
        _ = DockGestureSwitches.current
        _ = DockFollowAvailability.live
        XCTAssertEqual(reads, 3, "asking for the answer reads nothing")
        DockGestureSwitches.reload()
        XCTAssertEqual(reads, 6)
        XCTAssertEqual(changes, 1, "the same answer again: nothing changed")

        DockGestureSwitches.read = { _ in nil }
        XCTAssertFalse(DockGestureSwitches.current.showDesktop, "until the next read")
        DockGestureSwitches.reload()
        XCTAssertEqual(DockGestureSwitches.current, .allOn)
        XCTAssertEqual(changes, 2)
    }

    /// The switches are read where the Spaces shortcuts are: when Scrollio starts, and when
    /// it becomes active or System Settings goes to the background. Were one of the two
    /// calls lost, a gesture switched off in System Settings would count as on for good and
    /// its hold would do nothing, with no word. Read from the source.
    func testTheSwitchesAreReadAtTheStartAndWhenTheyMayHaveChanged() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Scrollio/AppDelegate.swift"), encoding: .utf8)
        let code = source.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("//") }
        let reads = code.indices.filter { code[$0] == "DockGestureSwitches.reload()" }
        XCTAssertEqual(reads.count, 2)
        for read in reads where read > 0 {
            XCTAssertEqual(code[read - 1], "SystemShortcut.reloadSystemShortcuts()", "beside the Spaces shortcuts")
        }
    }

    /// Nothing of the Mac's own settings is read while the tests run, and nothing of the
    /// Dock's is ever written. Read from the source (calling the reader to see that it
    /// reads nothing would be the very read if the line were ever lost): the one call
    /// stands right under the line that leaves under XCTest, and the file holds no call
    /// that writes a preference or restarts anything.
    func testTheDocksSettingsAreNotReadUnderXCTestAndNeverWritten() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Scrollio/InputEvent/DockFollow.swift"), encoding: .utf8)
        let lines = source.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let code = lines.filter { !$0.hasPrefix("//") }

        let calls = code.indices.filter { code[$0].contains("CFPreferencesCopyAppValue(") }
        XCTAssertEqual(calls.count, 1, "one place reads the Dock's settings")
        if let call = calls.first, call > 0 {
            XCTAssertEqual(code[call - 1], "guard !AppRuntime.isRunningXCTest else { return nil }")
            XCTAssertEqual(code[call], "return CFPreferencesCopyAppValue(key.rawValue as CFString, domain as CFString)")
        }
        for writes in ["CFPreferencesSet", "CFPreferencesAppSynchronize", "CFPreferencesSynchronize", ".set(", "persistentDomain",
                       "setPersistentDomain", "killall", "Process("] {
            XCTAssertFalse(code.contains { $0.contains(writes) }, "\(writes) in DockFollow.swift")
        }
        // The seam the app starts with is that reader, so the cached answer of a test run is "all on".
        XCTAssertEqual(DockGestureSwitches(reading: { _ in nil }), .allOn)
    }
}

// MARK: - Whether it follows on this Mac

final class DockFollowAvailabilityTests: XCTestCase {

    override func tearDown() {
        DockSwipeSynthesizer.shared.clearTestingDriver()
        super.tearDown()
    }

    private func availability(
        swipe: Bool = true, post: Bool = true, major: Int = 27, switches: DockGestureSwitches = .allOn, apps: Bool = false
    ) -> DockFollowAvailability {
        return DockFollowAvailability(
            swipeIsAvailable: swipe, canPostEvents: post, majorVersion: major, switches: switches, appsMayFollow: apps
        )
    }

    /// Mission Control follows on every macOS Scrollio runs on; Show Desktop from macOS 27
    /// (the pinch is unverified below); Apps nowhere in an ordinary build.
    func testTheTableOfMacOSVersions() {
        XCTAssertEqual(DockFollowAvailability.firstPinchMajorVersion, 27)
        for major in [14, 15, 26] {
            let mac = availability(major: major)
            XCTAssertNil(mac.obstacle(to: .missionControl), "macOS \(major)")
            XCTAssertEqual(mac.obstacle(to: .showDesktop), .notOnThisMacOS, "macOS \(major)")
            XCTAssertEqual(mac.obstacle(to: .apps), .notOnThisMacOS, "macOS \(major)")
            XCTAssertEqual(mac.targetsThatFollow, [.missionControl], "macOS \(major)")
            XCTAssertEqual(availability(major: major, apps: true).obstacle(to: .apps), .notOnThisMacOS, "macOS \(major)")
        }
        for major in [27, 28, 30] {
            let mac = availability(major: major)
            XCTAssertTrue(mac.follows(.missionControl), "macOS \(major)")
            XCTAssertTrue(mac.follows(.showDesktop), "macOS \(major)")
            XCTAssertEqual(mac.obstacle(to: .apps), .notOnThisMacOS, "macOS \(major): a release keeps Apps instant")
            XCTAssertEqual(mac.targetsThatFollow, [.missionControl, .showDesktop], "macOS \(major)")
            // The owner's own build.
            XCTAssertTrue(availability(major: major, apps: true).follows(.apps), "macOS \(major)")
            XCTAssertEqual(availability(major: major, apps: true).targetsThatFollow, [.missionControl, .showDesktop, .apps])
        }
        XCTAssertTrue(DockFollowAvailability.isKnownToFollow(.missionControl, majorVersion: 14, appsMayFollow: false))
        XCTAssertFalse(DockFollowAvailability.isKnownToFollow(.showDesktop, majorVersion: 26, appsMayFollow: true))
        XCTAssertTrue(DockFollowAvailability.isKnownToFollow(.showDesktop, majorVersion: 27, appsMayFollow: false))
        XCTAssertFalse(DockFollowAvailability.isKnownToFollow(.apps, majorVersion: 27, appsMayFollow: false))
        XCTAssertTrue(DockFollowAvailability.isKnownToFollow(.apps, majorVersion: 27, appsMayFollow: true))
    }

    /// Apps follows only in a build made with SCROLLIO_TRACE (the owner's installed copy).
    /// The build the tests run in is not one, and neither is a release: there the flag is
    /// off, and the live answer carries it.
    func testAppsFollowsInNoBuildWithoutTheTraceCondition() {
        XCTAssertFalse(DockFollowAvailability.appsFollowInThisBuild)
        XCTAssertFalse(DockFollowAvailability.live.appsMayFollow)
        XCTAssertFalse(DockFollowAvailability.live.follows(.apps))
    }

    func testEachObstacleKeepsATargetFromFollowing() {
        for target in [DockFollowTarget.missionControl, .showDesktop] {
            XCTAssertNil(availability().obstacle(to: target), "\(target)")
            XCTAssertEqual(availability(swipe: false).obstacle(to: target), .swipeUnavailable, "\(target)")
            XCTAssertEqual(availability(post: false).obstacle(to: target), .cannotPostEvents, "\(target)")
            XCTAssertFalse(availability(swipe: false).follows(target), "\(target)")
            XCTAssertFalse(availability(post: false).follows(target), "\(target)")
        }
        XCTAssertEqual(availability(swipe: false).targetsThatFollow, [])
        XCTAssertEqual(availability(post: false, apps: true).targetsThatFollow, [])

        // The Dock's switch of a gesture keeps that gesture's view from following, no other.
        let noMissionControl = DockGestureSwitches(missionControl: false, showDesktop: true, launchpad: true)
        XCTAssertEqual(availability(switches: noMissionControl).obstacle(to: .missionControl), .gestureOff)
        XCTAssertNil(availability(switches: noMissionControl).obstacle(to: .showDesktop))
        XCTAssertEqual(availability(major: 15, switches: noMissionControl).obstacle(to: .missionControl), .gestureOff)
        XCTAssertEqual(availability(switches: noMissionControl).targetsThatFollow, [.showDesktop])

        let noShowDesktop = DockGestureSwitches(missionControl: true, showDesktop: false, launchpad: true)
        XCTAssertEqual(availability(switches: noShowDesktop).obstacle(to: .showDesktop), .gestureOff)
        XCTAssertNil(availability(switches: noShowDesktop).obstacle(to: .missionControl))
        XCTAssertEqual(availability(switches: noShowDesktop, apps: true).obstacle(to: .apps), .gestureOff,
                       "from macOS 26 the Show Desktop switch stands for Apps")
        XCTAssertEqual(availability(switches: noShowDesktop, apps: true).targetsThatFollow, [.missionControl])

        let noLaunchpad = DockGestureSwitches(missionControl: true, showDesktop: true, launchpad: false)
        XCTAssertNil(availability(switches: noLaunchpad, apps: true).obstacle(to: .apps), "that switch is gone on macOS 27")
    }

    /// With more than one thing in the way, the most lasting one is named.
    func testTheMostLastingObstacleIsNamed() {
        let nothing = DockGestureSwitches(missionControl: false, showDesktop: false, launchpad: false)
        let hopeless = availability(swipe: false, post: false, major: 26, switches: nothing)
        XCTAssertEqual(hopeless.obstacle(to: .showDesktop), .notOnThisMacOS)
        XCTAssertEqual(hopeless.obstacle(to: .apps), .notOnThisMacOS)
        XCTAssertEqual(hopeless.obstacle(to: .missionControl), .swipeUnavailable)
        XCTAssertEqual(availability(post: false, switches: nothing).obstacle(to: .missionControl), .gestureOff)
        XCTAssertEqual(availability(post: false).obstacle(to: .missionControl), .cannotPostEvents)
    }

    /// The live answer is read from the running app: the synthesizer (inert under XCTest
    /// until a test gives it a driver), the right to post events, the macOS version, the
    /// Dock's switches as last read, the build's flag.
    func testTheLiveAnswerIsReadFromTheRunningApp() {
        DockSwipeSynthesizer.shared.clearTestingDriver()
        XCTAssertFalse(DockFollowAvailability.live.swipeIsAvailable, "the inert driver of the tests")
        XCTAssertEqual(DockFollowAvailability.live.targetsThatFollow, [], "nothing follows in a test that did not ask")

        DockSwipeSynthesizer.shared.setTestingDriver(DockSwipeDriver(
            isAvailable: { true }, begin: { _ in }, update: { _ in }, end: { _ in }, cancel: {}
        ))
        let live = DockFollowAvailability.live
        XCTAssertTrue(live.swipeIsAvailable)
        XCTAssertEqual(live.canPostEvents, ScrollPoster.shared.canPostEvents)
        XCTAssertEqual(live.majorVersion, ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
        XCTAssertEqual(live.switches, DockGestureSwitches.current)
        XCTAssertEqual(live.appsMayFollow, DockFollowAvailability.appsFollowInThisBuild)
    }
}

// MARK: - What a direction follows

final class DockFollowPlanTests: XCTestCase {

    private let directions: [MouseGestureDirection] = [.up, .down, .left, .right]

    /// A Mac on which Mission Control and Show Desktop follow (macOS 27, an ordinary build).
    private func mac(
        swipe: Bool = true, post: Bool = true, major: Int = 27, switches: DockGestureSwitches = .allOn, apps: Bool = false
    ) -> DockFollowAvailability {
        return DockFollowAvailability(
            swipeIsAvailable: swipe, canPostEvents: post, majorVersion: major, switches: switches, appsMayFollow: apps
        )
    }

    private func settings(
        mode: MouseGestureMode = .interactive, follow: Bool = true,
        up: String = "missionControl", down: String = "showDesktop"
    ) -> MouseGestureSettings {
        var settings = MouseGestureSettings.default
        settings.mode = mode
        settings.actionsFollowHand = follow
        settings.upAction = up
        settings.downAction = down
        return settings
    }

    /// Only "Follow the hand" with the switch on follows. Without the switch a hold is
    /// exactly what it was: Up and Down run once.
    func testOnlyFollowTheHandWithTheSwitchOnFollows() {
        for direction in directions {
            XCTAssertEqual(settings(mode: .discrete, follow: true).followPlan(for: direction, availability: mac()), .doesNotFollow)
            XCTAssertEqual(settings(mode: .discrete, follow: false).followPlan(for: direction, availability: mac()), .doesNotFollow)
            XCTAssertEqual(settings(mode: .interactive, follow: false).followPlan(for: direction, availability: mac()), .doesNotFollow)
            XCTAssertEqual(MouseGestureSettings.default.followPlan(for: direction, availability: mac()), .doesNotFollow)
        }
        let on = settings()
        XCTAssertEqual(on.followPlan(for: .up, availability: mac()), .follows(.missionControl))
        XCTAssertEqual(on.followPlan(for: .down, availability: mac()), .follows(.showDesktop))
        XCTAssertEqual(on.followPlan(for: .up, availability: mac()).target, .missionControl)
        XCTAssertNil(DockFollowPlan.doesNotFollow.target)
        XCTAssertNil(DockFollowPlan.cannotFollow(.showDesktop, .gestureOff).target)

        // The other way round: the direction does not matter, the action does.
        let swapped = settings(up: "showDesktop", down: "missionControl")
        XCTAssertEqual(swapped.followPlan(for: .up, availability: mac()), .follows(.showDesktop))
        XCTAssertEqual(swapped.followPlan(for: .down, availability: mac()), .follows(.missionControl))
        let same = settings(up: "missionControl", down: "missionControl")
        XCTAssertEqual(same.followPlan(for: .up, availability: mac()), .follows(.missionControl))
        XCTAssertEqual(same.followPlan(for: .down, availability: mac()), .follows(.missionControl))
    }

    /// The default actions: Up is Mission Control and follows; Down is Apps, which runs
    /// once in every ordinary build.
    func testWithTheDefaultActionsUpFollowsAndAppsRunsOnce() {
        var defaults = MouseGestureSettings.default
        defaults.mode = .interactive
        defaults.actionsFollowHand = true
        XCTAssertEqual(defaults.followPlan(for: .up, availability: mac()), .follows(.missionControl))
        XCTAssertEqual(defaults.followPlan(for: .down, availability: mac()), .cannotFollow(.apps, .notOnThisMacOS))
        XCTAssertEqual(defaults.followPlan(for: .down, availability: mac(apps: true)), .follows(.apps), "the owner's own build")
        XCTAssertEqual(defaults.followPlan(for: .down, availability: mac(major: 26, apps: true)), .cannotFollow(.apps, .notOnThisMacOS))
    }

    /// Sideways is the desktops' in "Follow the hand", whatever Left and Right hold.
    func testLeftAndRightNeverFollow() {
        var sideways = settings()
        sideways.leftAction = "missionControl"
        sideways.rightAction = "showDesktop"
        for invert in [false, true] {
            sideways.invertHorizontal = invert
            XCTAssertEqual(sideways.followPlan(for: .left, availability: mac()), .doesNotFollow, "invert \(invert)")
            XCTAssertEqual(sideways.followPlan(for: .right, availability: mac()), .doesNotFollow, "invert \(invert)")
            XCTAssertEqual(sideways.followPlan(for: .up, availability: mac()), .follows(.missionControl), "invert \(invert)")
            XCTAssertEqual(sideways.followPlan(for: .down, availability: mac()), .follows(.showDesktop), "invert \(invert)")
        }
    }

    func testAnActionWithoutAViewToOpenRunsOnce() {
        for action in ["copy", "", "moveSpaceLeft", "custom::160:0", "shortcutRing", "a name of a later version"] {
            let other = settings(up: action, down: "missionControl")
            XCTAssertEqual(other.followPlan(for: .up, availability: mac()), .doesNotFollow, action)
            XCTAssertEqual(other.followPlan(for: .down, availability: mac()), .follows(.missionControl), "\(action): the other direction still follows")
        }
    }

    /// What the settings ask for and this Mac does not do now runs once, with the reason.
    func testWhatThisMacDoesNotDoRunsOnceWithItsReason() {
        let on = settings()
        XCTAssertEqual(on.followPlan(for: .up, availability: mac(major: 26)), .follows(.missionControl))
        XCTAssertEqual(on.followPlan(for: .down, availability: mac(major: 26)), .cannotFollow(.showDesktop, .notOnThisMacOS))

        let noMissionControl = DockGestureSwitches(missionControl: false, showDesktop: true, launchpad: true)
        XCTAssertEqual(on.followPlan(for: .up, availability: mac(switches: noMissionControl)), .cannotFollow(.missionControl, .gestureOff))
        XCTAssertEqual(on.followPlan(for: .down, availability: mac(switches: noMissionControl)), .follows(.showDesktop))

        XCTAssertEqual(on.followPlan(for: .up, availability: mac(post: false)), .cannotFollow(.missionControl, .cannotPostEvents))
        XCTAssertEqual(on.followPlan(for: .down, availability: mac(swipe: false)), .cannotFollow(.showDesktop, .swipeUnavailable))

        // Whatever is in the way: without the switch nothing is said about it.
        let off = settings(follow: false)
        XCTAssertEqual(off.followPlan(for: .up, availability: mac(swipe: false, post: false, major: 14)), .doesNotFollow)
    }

    /// An app's own set decides for the app: ask the settings that run in it.
    func testAnAppsOwnSetDecidesForItsHolds() {
        let general = settings()
        let notes = Application(path: "/Applications/Notes.app")
        XCTAssertEqual(notes.gesturesThatRun(general: general).followPlan(for: .up, availability: mac()), .follows(.missionControl),
                       "no set of its own: the general one")

        notes.setUsesGeneralGestures(false, general: general)
        XCTAssertEqual(notes.gesturesThatRun(general: .default).followPlan(for: .up, availability: mac()), .follows(.missionControl),
                       "its own copy")
        notes.changeOwnGestures { $0.actionsFollowHand = false }
        XCTAssertEqual(notes.gesturesThatRun(general: general).followPlan(for: .up, availability: mac()), .doesNotFollow)
        notes.changeOwnGestures { own in
            own.actionsFollowHand = true
            own.mode = .discrete
        }
        XCTAssertEqual(notes.gesturesThatRun(general: general).followPlan(for: .up, availability: mac()), .doesNotFollow,
                       "the app's own mode is \"One action per hold\"")
        notes.changeOwnGestures { own in
            own.mode = .interactive
            own.actions.up = GestureAction(SystemShortcut.copy)
        }
        XCTAssertEqual(notes.gesturesThatRun(general: general).followPlan(for: .up, availability: mac()), .doesNotFollow)
        XCTAssertEqual(notes.gesturesThatRun(general: general).followPlan(for: .down, availability: mac()), .follows(.showDesktop))
    }
}
