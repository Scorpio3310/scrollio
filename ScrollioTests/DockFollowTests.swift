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
//  Then what a hold makes of it: what Scrollio believes the Dock shows (`DockBelief`), what
//  Up and Down do in one hold and the hold's lines in the log (`DockFollowHold`). The hold
//  itself, with a recording swipe driver, is in MouseGestureInteractiveModeTests.
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
        XCTAssertEqual(DockFollowTuning.lateDesktopChange, 1)
        XCTAssertEqual(DockFollowTuning.flickFloor, 0.2)
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
            "showAppExposeGestureEnabled",
        ])
    }

    /// The gestures Scrollio drives are on until someone turns one off; App Exposé's is
    /// off until someone turns it on (macOS ships them so). A stored value decides for
    /// each alike.
    func testAMissingNameIsOnForTheGesturesScrollioDrivesAndOffForAppExpose() {
        typealias Key = DockGestureSwitches.Key
        XCTAssertEqual(Key.allCases.filter(\.isOnWhenMissing), [.missionControl, .showDesktop, .launchpad])
        XCTAssertFalse(Key.appExpose.isOnWhenMissing)

        XCTAssertFalse(DockGestureSwitches.isOn(nil, whenMissing: false))
        XCTAssertTrue(DockGestureSwitches.isOn(nil, whenMissing: true))
        for whenMissing in [true, false] {
            XCTAssertTrue(DockGestureSwitches.isOn(true, whenMissing: whenMissing))
            XCTAssertFalse(DockGestureSwitches.isOn(false, whenMissing: whenMissing))
            XCTAssertFalse(DockGestureSwitches.isOn(NSNumber(value: 0), whenMissing: whenMissing))
            XCTAssertTrue(DockGestureSwitches.isOn(NSNumber(value: 1), whenMissing: whenMissing))
            // What is no switch at all counts as on: for App Exposé that is the careful side.
            XCTAssertTrue(DockGestureSwitches.isOn(Data(), whenMissing: whenMissing))
        }

        XCTAssertFalse(DockGestureSwitches.allOn.appExpose, "a Mac on which nothing was ever changed")
        XCTAssertFalse(DockGestureSwitches(missionControl: true, showDesktop: true, launchpad: true).appExpose)
        XCTAssertFalse(DockGestureSwitches(reading: { _ in nil }).appExpose)
        XCTAssertTrue(DockGestureSwitches(reading: { $0 == .appExpose ? true : nil }).appExpose)
        XCTAssertEqual(
            DockGestureSwitches(reading: { $0 == .appExpose ? true : nil }),
            DockGestureSwitches(missionControl: true, showDesktop: true, launchpad: true, appExpose: true)
        )
        XCTAssertFalse(DockGestureSwitches(reading: { $0 == .appExpose ? false : true }).appExpose)
        // It governs no target: what follows the hand does not depend on it.
        let on = DockGestureSwitches(missionControl: true, showDesktop: true, launchpad: true, appExpose: true)
        for target in DockFollowTarget.allCases {
            XCTAssertTrue(on.allows(target, majorVersion: 27), "\(target)")
        }
    }

    /// A stored "false" is off, also when it was written as text (`defaults write` without
    /// `-bool` stores "NO" or "false" as a string, and the Dock takes that for off). A
    /// missing name counts as on, and so does what is no switch at all: the values are
    /// another app's data and may be anything.
    func testAStoredFalseIsOffAndEverythingElseCountsAsOn() {
        XCTAssertTrue(DockGestureSwitches.isOn(nil), "a missing name")
        XCTAssertTrue(DockGestureSwitches.isOn(true))
        XCTAssertFalse(DockGestureSwitches.isOn(false))
        XCTAssertTrue(DockGestureSwitches.isOn(kCFBooleanTrue))
        XCTAssertFalse(DockGestureSwitches.isOn(kCFBooleanFalse))
        XCTAssertFalse(DockGestureSwitches.isOn(NSNumber(value: 0)), "written as a number")
        XCTAssertTrue(DockGestureSwitches.isOn(NSNumber(value: 1)))
        for text in ["NO", "no", "No", "false", "FALSE", "False", "0"] {
            XCTAssertFalse(DockGestureSwitches.isOn(text), text)
            XCTAssertFalse(DockGestureSwitches.isOn(text as NSString), text)
            XCTAssertFalse(DockGestureSwitches.isOn(text, whenMissing: false), text)
        }
        for text in ["YES", "yes", "true", "1", "", "off", "nope", "00", " no", "false "] {
            XCTAssertTrue(DockGestureSwitches.isOn(text), "\"\(text)\"")
            XCTAssertTrue(DockGestureSwitches.isOn(text, whenMissing: false), "\"\(text)\"")
        }
        let noSwitch: [Any] = [NSNull(), Date(timeIntervalSince1970: 0), [false], ["on": false], Data()]
        for value in noSwitch {
            XCTAssertTrue(DockGestureSwitches.isOn(value), "\(value)")
        }
        XCTAssertEqual(
            DockGestureSwitches(reading: { $0 == .missionControl ? "NO" : nil }),
            DockGestureSwitches(missionControl: false, showDesktop: true, launchpad: true)
        )
    }

    func testEachSwitchIsReadUnderItsOwnName() {
        var asked: [DockGestureSwitches.Key] = []
        let nothingStored = DockGestureSwitches(reading: { key in
            asked.append(key)
            return nil
        })
        XCTAssertEqual(nothingStored, .allOn, "a Mac that never had a trackpad")
        XCTAssertEqual(Set(asked), Set(DockGestureSwitches.Key.allCases))
        XCTAssertEqual(asked.count, 4, "each once, and nothing else")

        XCTAssertEqual(
            DockGestureSwitches(reading: { $0 == .missionControl ? false : nil }),
            DockGestureSwitches(missionControl: false, showDesktop: true, launchpad: true)
        )
        XCTAssertEqual(
            DockGestureSwitches(reading: { $0 == .showDesktop ? false : true }),
            DockGestureSwitches(missionControl: true, showDesktop: false, launchpad: true, appExpose: true)
        )
        XCTAssertEqual(
            DockGestureSwitches(reading: { $0 == .launchpad ? NSNumber(value: 0) : "yes" }),
            DockGestureSwitches(missionControl: true, showDesktop: true, launchpad: false, appExpose: true)
        )
        XCTAssertEqual(
            DockGestureSwitches(reading: { _ in false }),
            DockGestureSwitches(missionControl: false, showDesktop: false, launchpad: false, appExpose: false)
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
        XCTAssertEqual(reads, 4)
        XCTAssertEqual(DockGestureSwitches.current, DockGestureSwitches(missionControl: true, showDesktop: false, launchpad: true))
        XCTAssertEqual(DockFollowAvailability.live.switches, DockGestureSwitches.current)
        XCTAssertEqual(changes, 1)
        _ = DockGestureSwitches.current
        _ = DockFollowAvailability.live
        XCTAssertEqual(reads, 4, "asking for the answer reads nothing")
        DockGestureSwitches.reload()
        XCTAssertEqual(reads, 8)
        XCTAssertEqual(changes, 1, "the same answer again: nothing changed")

        DockGestureSwitches.read = { _ in nil }
        XCTAssertFalse(DockGestureSwitches.current.showDesktop, "until the next read")
        DockGestureSwitches.reload()
        XCTAssertEqual(DockGestureSwitches.current, .allOn)
        XCTAssertEqual(changes, 2)
    }

    /// The switches are read where the Spaces shortcuts are: when Scrollio starts, and when
    /// it becomes active or System Settings goes to the background. And when the Dock
    /// itself starts: a switch changed from outside System Settings (`defaults write`,
    /// then `killall Dock`) would otherwise count as it was until Scrollio starts again,
    /// since a menu bar app is rarely the active one. Were one of the calls lost, a
    /// gesture switched off would count as on for good and its hold would do nothing,
    /// with no word. Read from the source.
    func testTheSwitchesAreReadAtTheStartAndWhenTheyMayHaveChanged() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Scrollio/AppDelegate.swift"), encoding: .utf8)
        let code = source.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("//") }
        let reads = code.indices.filter { code[$0] == "DockGestureSwitches.reload()" && $0 > 0 }
        XCTAssertEqual(reads.count, 3)
        let before = reads.map { code[$0 - 1] }
        XCTAssertEqual(before.filter { $0 == "SystemShortcut.reloadSystemShortcuts()" }.count, 2, "beside the Spaces shortcuts")
        XCTAssertEqual(
            before.filter { $0 == "guard DockGestureSwitches.reloads(afterLaunchOf: launched?.bundleIdentifier) else { return }" }.count,
            1, "when the Dock starts"
        )
        // The Dock's start is heard: the observer is there, with that method.
        let observer = try XCTUnwrap(code.firstIndex(of: "name: NSWorkspace.didLaunchApplicationNotification,"))
        XCTAssertEqual(code[observer - 1], "selector: #selector(reloadDockGestureSwitchesIfTheDockStarted),")
        XCTAssertTrue(code.contains("@objc func reloadDockGestureSwitchesIfTheDockStarted(notification: NSNotification) {"))
    }

    /// Only the Dock's own start reads them again, not every app's.
    func testOnlyTheDocksStartReadsTheSwitchesAgain() {
        XCTAssertEqual(DockGestureSwitches.domain, "com.apple.dock", "the Dock's bundle identifier is its settings' name")
        XCTAssertTrue(DockGestureSwitches.reloads(afterLaunchOf: "com.apple.dock"))
        for other in ["com.apple.finder", "com.apple.systempreferences", "com.apple.Dock", "com.apple.dock.extra", "", nil] {
            XCTAssertFalse(DockGestureSwitches.reloads(afterLaunchOf: other), "\(String(describing: other))")
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

// MARK: - What Scrollio believes the Dock shows

/// The belief (`DockBelief`): the view Scrollio's own last followed swipe put up. Pure: the
/// times are made up.
final class DockBeliefTests: XCTestCase {

    func testThereIsNoBeliefUntilScrollioOpensAView() {
        let belief = DockBelief()
        XCTAssertNil(belief.view(at: 0))
        XCTAssertNil(belief.view(at: 1_000))
    }

    /// A followed hold that is expected to open a view sets it, and nothing else does: an
    /// instant toggle can only end it (`drop`; `InputProcessor.dockViewWillBeToggled`).
    func testOnlyAFollowedHoldSetsIt() {
        var belief = DockBelief()
        belief.holdOpened(.missionControl, at: 10)
        XCTAssertEqual(belief.view(at: 10), .missionControl)
        XCTAssertEqual(belief.view(at: 40), .missionControl)

        belief.drop()
        XCTAssertNil(belief.view(at: 41), "a toggle ends it")
        belief.drop()
        XCTAssertNil(belief.view(at: 42), "and never sets it")
        belief.holdOpened(.apps, at: 44)
        XCTAssertEqual(belief.view(at: 44), .apps)
    }

    func testItIsDroppedAfterAMinuteAndWhenToldTo() {
        XCTAssertEqual(DockBelief.lifetime, 60)
        var belief = DockBelief()
        belief.holdOpened(.showDesktop, at: 100)
        XCTAssertEqual(belief.view(at: 159.9), .showDesktop)
        XCTAssertNil(belief.view(at: 160), "a minute old")
        XCTAssertNil(belief.view(at: 5_000))
        XCTAssertNil(belief.view(at: 99), "a clock that starts over leaves nothing believed")

        belief.holdOpened(.showDesktop, at: 200)
        XCTAssertEqual(belief.view(at: 200), .showDesktop)

        belief.drop()
        XCTAssertNil(belief.view(at: 200))
        XCTAssertEqual(belief, DockBelief(), "nothing is left of it")
        belief.drop()
        XCTAssertNil(belief.view(at: 201))
    }

    /// Show Desktop, the desktop and Apps are one slider: a hold towards the other end of
    /// the believed view's own motion steps back to the desktop. Another motion's view
    /// simply becomes the belief.
    func testAHoldTowardsTheOtherEndOfTheSameMotionShowsNoView() {
        var belief = DockBelief()
        belief.holdOpened(.showDesktop, at: 1)
        belief.holdOpened(.apps, at: 2)
        XCTAssertNil(belief.view(at: 2), "the windows came back")
        belief.holdOpened(.apps, at: 3)
        XCTAssertEqual(belief.view(at: 3), .apps)
        belief.holdOpened(.showDesktop, at: 4)
        XCTAssertNil(belief.view(at: 4))

        belief.holdOpened(.missionControl, at: 5)
        belief.holdOpened(.showDesktop, at: 6)
        XCTAssertEqual(belief.view(at: 6), .showDesktop, "another motion")
        belief.holdOpened(.showDesktop, at: 50)
        XCTAssertEqual(belief.view(at: 100), .showDesktop, "opened again: believed from then on")

        // An old belief is none: the hold opens its view.
        belief.holdOpened(.apps, at: 500)
        XCTAssertEqual(belief.view(at: 500), .apps)
    }

    // MARK: What a hold does about it

    private typealias Move = DockBelief.Move

    func testWithoutABeliefEveryPlanStands() {
        let plans: [DockFollowPlan] = [
            .follows(.missionControl), .follows(.showDesktop), .follows(.apps),
            .cannotFollow(.missionControl, .gestureOff), .doesNotFollow,
        ]
        for plan in plans {
            for opposite in plans {
                XCTAssertEqual(DockBelief.move(for: plan, opposite: opposite, believed: nil, appExposeGestureIsOn: false), .asPlanned, "\(plan) / \(opposite)")
            }
        }
    }

    /// The same move again closes the view: the direction whose own view is believed to
    /// show runs its instant toggle.
    func testTheDirectionOfTheBelievedViewToggles() {
        for target in DockFollowTarget.allCases {
            XCTAssertEqual(
                DockBelief.move(for: .follows(target), opposite: .doesNotFollow, believed: target, appExposeGestureIsOn: false), .toggle(target), "\(target)"
            )
            XCTAssertEqual(
                DockBelief.move(for: .follows(target), opposite: .follows(target), believed: target, appExposeGestureIsOn: false), .toggle(target),
                "both directions hold it: \(target)"
            )
            // A direction that runs once anyway is the toggle already.
            XCTAssertEqual(
                DockBelief.move(for: .cannotFollow(target, .gestureOff), opposite: .doesNotFollow, believed: target, appExposeGestureIsOn: false), .asPlanned,
                "\(target)"
            )
        }
    }

    /// While Mission Control is believed to show, the direction opposite to the one that
    /// opens it with the hand leaves it with the hand, whatever its own action is.
    func testTheOppositeDirectionLeavesMissionControl() {
        let others: [DockFollowPlan] = [
            .follows(.showDesktop), .follows(.apps), .cannotFollow(.apps, .notOnThisMacOS),
            .cannotFollow(.showDesktop, .gestureOff), .doesNotFollow,
        ]
        for own in others {
            XCTAssertEqual(
                DockBelief.move(for: own, opposite: .follows(.missionControl), believed: .missionControl, appExposeGestureIsOn: false), .leaveMissionControl,
                "\(own)"
            )
        }
    }

    /// Where the trackpad gesture for App Exposé is on, the swipe that leaves Mission
    /// Control would open App Exposé from the desktop (when Mission Control was left
    /// another way meanwhile): there the opposite direction keeps its own plan. The same
    /// move again still toggles.
    func testMissionControlIsNotLeftWhereAppExposeHasItsGesture() {
        let others: [DockFollowPlan] = [
            .follows(.showDesktop), .follows(.apps), .cannotFollow(.apps, .notOnThisMacOS), .doesNotFollow,
        ]
        for own in others {
            XCTAssertEqual(
                DockBelief.move(for: own, opposite: .follows(.missionControl), believed: .missionControl, appExposeGestureIsOn: true),
                .asPlanned, "\(own)"
            )
        }
        XCTAssertEqual(
            DockBelief.move(
                for: .follows(.missionControl), opposite: .doesNotFollow, believed: .missionControl, appExposeGestureIsOn: true
            ),
            .toggle(.missionControl)
        )
        XCTAssertEqual(
            DockBelief.move(for: .doesNotFollow, opposite: .follows(.missionControl), believed: nil, appExposeGestureIsOn: true),
            .asPlanned
        )
    }

    /// Nothing else changes: no other view is ever left by a swipe, and Mission Control
    /// only where its own direction follows on this Mac now (the same motion).
    func testNothingElseChanges() {
        // Mission Control showing, but no direction opens it with the hand.
        XCTAssertEqual(
            DockBelief.move(for: .follows(.showDesktop), opposite: .follows(.apps), believed: .missionControl, appExposeGestureIsOn: false), .asPlanned
        )
        XCTAssertEqual(DockBelief.move(for: .doesNotFollow, opposite: .doesNotFollow, believed: .missionControl, appExposeGestureIsOn: false), .asPlanned)
        XCTAssertEqual(
            DockBelief.move(for: .doesNotFollow, opposite: .cannotFollow(.missionControl, .gestureOff), believed: .missionControl, appExposeGestureIsOn: false),
            .asPlanned, "the Dock would ignore the way back as it ignores the way in"
        )
        // Show Desktop or Apps showing: the opposite direction keeps its own plan.
        for showing in [DockFollowTarget.showDesktop, .apps] {
            for own in [DockFollowPlan.follows(.missionControl), .doesNotFollow, .cannotFollow(.apps, .notOnThisMacOS)] {
                XCTAssertEqual(
                    DockBelief.move(for: own, opposite: .follows(showing), believed: showing, appExposeGestureIsOn: false), .asPlanned, "\(showing) / \(own)"
                )
            }
        }
        XCTAssertEqual(
            DockBelief.move(for: .follows(.apps), opposite: .follows(.showDesktop), believed: .showDesktop, appExposeGestureIsOn: false), .asPlanned,
            "the Dock's own slider brings the windows back"
        )
    }

    /// From a belief, the only closing sign a hold ever sends is the vertical one.
    func testTheOnlyClosingSwipeIsTheVerticalOne() {
        let plans: [DockFollowPlan] = DockFollowTarget.allCases.map { .follows($0) }
            + DockFollowTarget.allCases.map { .cannotFollow($0, .gestureOff) } + [.doesNotFollow]
        for believed in DockFollowTarget.allCases {
            for plan in plans {
                for opposite in plans {
                    for appExpose in [false, true] {
                        let move = DockBelief.move(
                            for: plan, opposite: opposite, believed: believed, appExposeGestureIsOn: appExpose
                        )
                        if move == .leaveMissionControl {
                            XCTAssertEqual(believed, .missionControl)
                            XCTAssertEqual(opposite, .follows(.missionControl))
                            XCTAssertFalse(appExpose)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - What Up and Down do in one hold

/// `DockFollowHold`: the plan of a hold's two directions, the Dock motion each drives, and
/// the hold's lines in the log. Pure.
final class DockFollowHoldTests: XCTestCase {

    private typealias Part = DockFollowHold.Part

    private func mac(
        swipe: Bool = true, post: Bool = true, major: Int = 27, switches: DockGestureSwitches = .allOn, apps: Bool = false
    ) -> DockFollowAvailability {
        return DockFollowAvailability(
            swipeIsAvailable: swipe, canPostEvents: post, majorVersion: major, switches: switches, appsMayFollow: apps
        )
    }

    private func settings(
        mode: MouseGestureMode = .interactive, follow: Bool = true,
        up: String = "missionControl", down: String = "appExpose"
    ) -> MouseGestureSettings {
        var settings = MouseGestureSettings.default
        settings.mode = mode
        settings.actionsFollowHand = follow
        settings.upAction = up
        settings.downAction = down
        return settings
    }

    /// Without the switch, and in "One action per hold", a hold is what it was, whatever
    /// is believed to show.
    func testWithTheSwitchOffBothDirectionsRunOnce() {
        for believed in [DockFollowTarget?.none, .missionControl, .showDesktop, .apps] {
            for off in [settings(follow: false), settings(mode: .discrete), MouseGestureSettings.default] {
                let hold = DockFollowHold(settings: off, availability: mac(), believed: believed)
                XCTAssertEqual(hold, DockFollowHold(up: .once, down: .once), "\(String(describing: believed))")
                XCTAssertNil(hold.up.channel(screenHeight: 1000, trackingSpeed: 1))
                XCTAssertNil(hold.down.channel(screenHeight: 1000, trackingSpeed: 1))
            }
        }
    }

    func testEachDirectionOpensItsViewOrSaysWhyNot() {
        var hold = DockFollowHold(settings: settings(), availability: mac(), believed: nil)
        XCTAssertEqual(hold.up, .opens(.missionControl))
        XCTAssertEqual(hold.down, .onceInstead(.apps, .obstacle(.notOnThisMacOS)), "Apps runs once in an ordinary build")
        XCTAssertEqual(hold[.up], hold.up)
        XCTAssertEqual(hold[.down], hold.down)
        XCTAssertEqual(hold[.left], .once)
        XCTAssertEqual(hold[.right], .once)

        hold = DockFollowHold(settings: settings(up: "showDesktop", down: "copy"), availability: mac(), believed: nil)
        XCTAssertEqual(hold, DockFollowHold(up: .opens(.showDesktop), down: .once))

        let off = DockGestureSwitches(missionControl: false, showDesktop: true, launchpad: true)
        hold = DockFollowHold(settings: settings(down: "showDesktop"), availability: mac(switches: off), believed: nil)
        XCTAssertEqual(hold, DockFollowHold(up: .onceInstead(.missionControl, .obstacle(.gestureOff)), down: .opens(.showDesktop)))

        hold = DockFollowHold(settings: settings(down: "showDesktop"), availability: mac(post: false), believed: nil)
        XCTAssertEqual(hold.up, .onceInstead(.missionControl, .obstacle(.cannotPostEvents)))
        XCTAssertEqual(hold.down, .onceInstead(.showDesktop, .obstacle(.cannotPostEvents)))

        hold = DockFollowHold(settings: settings(down: "showDesktop"), availability: mac(major: 15), believed: nil)
        XCTAssertEqual(hold, DockFollowHold(up: .opens(.missionControl), down: .onceInstead(.showDesktop, .obstacle(.notOnThisMacOS))))
    }

    /// The belief: the same move again runs once (the toggle closes the view), and the
    /// opposite move leaves Mission Control with the hand instead of its own action.
    func testWhatIsBelievedToShowChangesTheHold() {
        var hold = DockFollowHold(settings: settings(), availability: mac(), believed: .missionControl)
        XCTAssertEqual(hold.up, .onceInstead(.missionControl, .showing(.missionControl)))
        XCTAssertEqual(hold.down, .leavesMissionControl, "not Apps")

        hold = DockFollowHold(settings: settings(up: "copy", down: "missionControl"), availability: mac(), believed: .missionControl)
        XCTAssertEqual(hold, DockFollowHold(up: .leavesMissionControl, down: .onceInstead(.missionControl, .showing(.missionControl))))

        hold = DockFollowHold(settings: settings(up: "showDesktop", down: "copy"), availability: mac(), believed: .showDesktop)
        XCTAssertEqual(hold, DockFollowHold(up: .onceInstead(.showDesktop, .showing(.showDesktop)), down: .once))

        // Mission Control was opened by the click; no direction holds it: nothing changes.
        hold = DockFollowHold(settings: settings(up: "showDesktop", down: "copy"), availability: mac(), believed: .missionControl)
        XCTAssertEqual(hold, DockFollowHold(up: .opens(.showDesktop), down: .once))

        // Its trackpad gesture is off: Up toggles as it does anyway, and Down keeps its action.
        let off = DockGestureSwitches(missionControl: false, showDesktop: true, launchpad: true)
        hold = DockFollowHold(settings: settings(), availability: mac(switches: off), believed: .missionControl)
        XCTAssertEqual(hold.up, .onceInstead(.missionControl, .obstacle(.gestureOff)))
        XCTAssertEqual(hold.down, .onceInstead(.apps, .obstacle(.notOnThisMacOS)))
    }

    /// Where the trackpad gesture for App Exposé is on, the opposite move keeps its own
    /// plan while Mission Control is believed to show; the same move again still closes it.
    func testMissionControlIsNotLeftWithTheHandWhereAppExposeHasItsGesture() {
        let appExposeOn = DockGestureSwitches(missionControl: true, showDesktop: true, launchpad: true, appExpose: true)
        var hold = DockFollowHold(
            settings: settings(down: "showDesktop"), availability: mac(switches: appExposeOn), believed: .missionControl
        )
        XCTAssertEqual(hold.up, .onceInstead(.missionControl, .showing(.missionControl)))
        XCTAssertEqual(hold.down, .opens(.showDesktop), "its own plan")

        hold = DockFollowHold(settings: settings(down: "copy"), availability: mac(switches: appExposeOn), believed: .missionControl)
        XCTAssertEqual(hold.down, .once)
        // Off (and where the name is missing): left with the hand.
        hold = DockFollowHold(settings: settings(down: "copy"), availability: mac(), believed: .missionControl)
        XCTAssertEqual(hold.down, .leavesMissionControl)
    }

    /// What the end of a motion does to the belief. A hold that opened a view and is
    /// expected to open it put it up. A hold that left Mission Control ends the belief
    /// unless it was turned back to its start, whatever ended it.
    func testWhatTheEndOfAMotionDoesToTheBelief() {
        typealias Ending = DockFollowedMotion.Ending
        var up = motion()
        up.told(progress: 0.6)
        XCTAssertEqual(up.beliefChange(after: .ended(velocity: 0, expected: true)), .opened(.missionControl))
        XCTAssertEqual(up.beliefChange(after: .ended(velocity: 0, expected: false)), DockFollowedMotion.BeliefChange.none)
        XCTAssertEqual(up.beliefChange(after: .cancelledAtRelease), DockFollowedMotion.BeliefChange.none)
        XCTAssertEqual(up.beliefChange(after: .cancelled(.ringOpened)), DockFollowedMotion.BeliefChange.none)
        var desktop = motion(.down, .opens(.showDesktop), .pinch)
        desktop.told(progress: 0.7)
        XCTAssertEqual(desktop.beliefChange(after: .ended(velocity: 0, expected: true)), .opened(.showDesktop))

        // The belief needs the view to have moved: a fifth of the way, as the Dock was
        // told. A release that was only fast (expected to open at 2 % of the way) is none.
        var flick = motion()
        flick.told(progress: 0.02)
        XCTAssertEqual(flick.beliefChange(after: .ended(velocity: 3, expected: true)), DockFollowedMotion.BeliefChange.none)
        flick.told(progress: 0.19)
        XCTAssertEqual(flick.beliefChange(after: .ended(velocity: 3, expected: true)), DockFollowedMotion.BeliefChange.none)
        XCTAssertFalse(flick.hasMovedTheView)
        flick.told(progress: 0.2)
        XCTAssertTrue(flick.hasMovedTheView)
        XCTAssertEqual(flick.beliefChange(after: .ended(velocity: 3, expected: true)), .opened(.missionControl))
        // Where it was let go counts, not how far it had been.
        flick.told(progress: 0.9)
        flick.told(progress: 0.1)
        XCTAssertFalse(flick.hasMovedTheView)
        XCTAssertEqual(flick.beliefChange(after: .ended(velocity: 3, expected: true)), DockFollowedMotion.BeliefChange.none)
        // Apps, the other end of the pinch: its progress is negative, the share is not.
        var apps = motion(.down, .opens(.apps), .pinch, sign: -1)
        apps.told(progress: -0.5)
        XCTAssertEqual(apps.beliefChange(after: .ended(velocity: -1, expected: true)), .opened(.apps))

        let endings: [Ending] = [
            .ended(velocity: 0, expected: true), .ended(velocity: 0, expected: false), .cancelledAtRelease,
            .cancelled(.noButtonUp), .cancelled(.ringOpened), .cancelled(.takenBack),
        ]
        var leave = motion(.down, .leavesMissionControl, .vertical, sign: -1)
        for ending in endings {
            XCTAssertEqual(leave.beliefChange(after: ending), DockFollowedMotion.BeliefChange.none, "nothing was told: \(ending)")
        }
        leave.told(progress: -0.25)
        for ending in endings {
            XCTAssertEqual(leave.beliefChange(after: ending), .dropped, "part of the way: \(ending)")
        }
        leave.told(progress: 0)
        for ending in endings {
            XCTAssertEqual(leave.beliefChange(after: ending), DockFollowedMotion.BeliefChange.none, "back at its start: \(ending)")
        }
    }

    /// The motion a direction drives: one-sided, whole at 1, with the travel, the room for
    /// the jolt of letting go and the bound of the release velocity of `DockFollowTuning`.
    func testTheChannelOfADirection() throws {
        let up = try XCTUnwrap(Part.opens(.missionControl).channel(screenHeight: 1000, trackingSpeed: 1))
        XCTAssertEqual(up.motion, .vertical)
        XCTAssertEqual(up.sign, 1)
        XCTAssertEqual(up.progressPerPoint, 1.0 / 400, accuracy: 1e-12, "0.40 of the screen's height is the whole view")
        XCTAssertEqual(up.maximumProgress, 1)
        XCTAssertFalse(up.crossesStart)
        XCTAssertFalse(up.beginsAtLock, "it begins where the action would run")
        XCTAssertEqual(up.reverseTolerance, 8)
        XCTAssertEqual(up.maximumTravelsPerSecond, 12)
        XCTAssertEqual(up.progressRange, 0...1)

        let desktop = try XCTUnwrap(Part.opens(.showDesktop).channel(screenHeight: 1000, trackingSpeed: 2))
        XCTAssertEqual(desktop.motion, .pinch)
        XCTAssertEqual(desktop.sign, 1)
        XCTAssertEqual(desktop.progressPerPoint, 2.0 / 400, accuracy: 1e-12, "Swipe speed scales it")

        let apps = try XCTUnwrap(Part.opens(.apps).channel(screenHeight: 1000, trackingSpeed: 1))
        XCTAssertEqual(apps.motion, .pinch)
        XCTAssertEqual(apps.sign, -1, "the other end of the pinch")
        XCTAssertEqual(apps.progressPerPoint, 1.0 / 300, accuracy: 1e-12, "three quarters of the travel")
        XCTAssertEqual(apps.progressRange, -1...0)

        let leave = try XCTUnwrap(Part.leavesMissionControl.channel(screenHeight: 1000, trackingSpeed: 1))
        XCTAssertEqual(leave.motion, .vertical)
        XCTAssertEqual(leave.sign, -1, "the way back of the motion that opens it")
        XCTAssertEqual(leave.progressPerPoint, up.progressPerPoint)
        XCTAssertEqual(leave.maximumProgress, 1)
        XCTAssertEqual(leave.reverseTolerance, 8)
        XCTAssertEqual(leave.maximumTravelsPerSecond, 12)
        XCTAssertEqual(leave.progressRange, -1...0)

        XCTAssertNil(Part.once.channel(screenHeight: 1000, trackingSpeed: 1))
        XCTAssertNil(Part.onceInstead(.missionControl, .wheelSwipeRunning).channel(screenHeight: 1000, trackingSpeed: 1))
    }

    // MARK: The log

    func testTheLineOfADirectionThatRanOnceSaysWhy() {
        typealias Reason = DockFollowHold.Reason
        let reasons: [(Reason, String)] = [
            (.obstacle(.gestureOff), "the Dock's gesture is off"),
            (.obstacle(.notOnThisMacOS), "not on this macOS"),
            (.obstacle(.cannotPostEvents), "cannot post events"),
            (.obstacle(.swipeUnavailable), "the swipe cannot be made on this Mac"),
            (.wheelSwipeRunning, "the wheel's swipe was running"),
            (.showing(.missionControl), "Scrollio had just opened Mission Control"),
            (.showing(.showDesktop), "Scrollio had just opened Show Desktop"),
            (.showing(.apps), "Scrollio had just opened Apps"),
        ]
        for (reason, text) in reasons {
            XCTAssertEqual(reason.logText, text)
        }
        XCTAssertEqual(
            DockFollowHold.ranOnceLine(
                .up, insteadOf: .onceInstead(.missionControl, .obstacle(.gestureOff)), reason: .obstacle(.gestureOff)
            ),
            "Gestures: up did not follow the hand: missionControl, the Dock's gesture is off"
        )
        XCTAssertEqual(
            DockFollowHold.ranOnceLine(.down, insteadOf: .opens(.apps), reason: .wheelSwipeRunning, appsOwn: true),
            "Gestures: down did not follow the hand: appExpose, the wheel's swipe was running, the app in front has its own gestures"
        )
        XCTAssertEqual(
            DockFollowHold.ranOnceLine(.down, insteadOf: .leavesMissionControl, reason: .wheelSwipeRunning),
            "Gestures: down did not follow the hand: leaving missionControl, the wheel's swipe was running"
        )
    }

    private func motion(
        _ direction: MouseGestureDirection = .up, _ part: Part = .opens(.missionControl), _ axis: DockSwipeAxis = .vertical,
        sign: Double = 1, beganAfter: TimeInterval = 0.048
    ) -> DockFollowedMotion {
        return DockFollowedMotion(
            direction: direction, part: part, motion: axis, sign: sign, fullProgress: 1, beganAfter: beganAfter
        )
    }

    func testTheLineOfAMotionThatFollowedTheHand() {
        var up = motion()
        for index in 1...37 {
            up.told(progress: index == 20 ? 0.82 : 0.74)
        }
        XCTAssertEqual(up.updates, 37)
        XCTAssertEqual(up.furthest, 0.82)
        XCTAssertEqual(up.last, 0.74)
        XCTAssertEqual(
            up.line(.ended(velocity: 1.9, expected: false)),
            "Gestures: up followed the hand: missionControl, vertical +, began after 48 ms, 37 updates, "
                + "furthest 0.82, released at 0.74, 1.9/s: ended"
        )
        XCTAssertEqual(
            up.line(.ended(velocity: 1.9, expected: true), appsOwn: true),
            "Gestures: up followed the hand: missionControl, vertical +, began after 48 ms, 37 updates, "
                + "furthest 0.82, released at 0.74, 1.9/s: ended, expected to open, the app in front has its own gestures"
        )
        XCTAssertEqual(
            up.line(.cancelledAtRelease),
            "Gestures: up followed the hand: missionControl, vertical +, began after 48 ms, 37 updates, "
                + "furthest 0.82, released at 0.74: cancelled"
        )
    }

    /// A flick: a hold that opens a view, let go as expected to open while the view has
    /// moved less than a fifth of the way. A hold that leaves Mission Control is never one.
    func testAFlickIsAHoldThatOpensAViewAndBarelyMovedIt() {
        var up = motion()
        XCTAssertTrue(up.isFlickIfReleasedToSwitch, "nothing told yet")
        up.told(progress: 0.19)
        XCTAssertTrue(up.isFlickIfReleasedToSwitch)
        up.told(progress: 0.2)
        XCTAssertFalse(up.isFlickIfReleasedToSwitch, "from the floor on macOS decides")
        up.told(progress: 0.05)
        XCTAssertTrue(up.isFlickIfReleasedToSwitch, "where it was let go counts")

        var apps = motion(.down, .opens(.apps), .pinch, sign: -1)
        apps.told(progress: -0.1)
        XCTAssertTrue(apps.isFlickIfReleasedToSwitch)
        var leave = motion(.down, .leavesMissionControl, .vertical, sign: -1)
        leave.told(progress: -0.1)
        XCTAssertFalse(leave.isFlickIfReleasedToSwitch)

        // Its line, and it leaves nothing believed (its toggle is never believed either).
        up.told(progress: 0.15)
        XCTAssertEqual(
            up.line(.flick(velocity: 9), appsOwn: true),
            "Gestures: up followed the hand: missionControl, vertical +, began after 48 ms, 4 updates, "
                + "furthest 0.20, released at 0.15, 9.0/s: cancelled, a flick: ran once, the app in front has its own gestures"
        )
        XCTAssertTrue(apps.line(.flick(velocity: -2.5)).hasSuffix(", released at 0.10, 2.5/s: cancelled, a flick: ran once"))
        XCTAssertEqual(up.beliefChange(after: .flick(velocity: 9)), DockFollowedMotion.BeliefChange.none)
    }

    /// A motion of negative sign reads the hand's way out as positive too.
    func testTheLineCountsTheHandsWayOut() {
        var apps = motion(.down, .opens(.apps), .pinch, sign: -1, beganAfter: 0.0554)
        apps.told(progress: -0.2)
        XCTAssertEqual(
            apps.line(.ended(velocity: -2.5, expected: true)),
            "Gestures: down followed the hand: appExpose, pinch -, began after 55 ms, 1 update, "
                + "furthest 0.20, released at 0.20, 2.5/s: ended, expected to open"
        )
        var leave = motion(.down, .leavesMissionControl, .vertical, sign: -1, beganAfter: 0.04)
        leave.told(progress: -0.25)
        leave.told(progress: -0.6)
        XCTAssertEqual(
            leave.line(.ended(velocity: 0, expected: true)),
            "Gestures: down followed the hand: leaving missionControl, vertical -, began after 40 ms, 2 updates, "
                + "furthest 0.60, released at 0.60, 0.0/s: ended, expected to close"
        )
    }

    func testTheLineOfAMotionThatWasTakenBackSaysWhy() {
        typealias Interruption = DockFollowedMotion.Interruption
        let texts: [(Interruption, String)] = [
            (.noButtonUp, "no button-up"), (.mouseWentAway, "the mouse went away"),
            (.scrollioStopped, "Scrollio's event taps stopped"), (.screensChanged, "the screens changed"),
            (.displaysSlept, "the displays went to sleep"), (.spaceChanged, "the desktop in use changed"),
            (.ringOpened, "the Shortcut Ring opened"), (.takenBack, "its swipe had been taken back"),
        ]
        var up = motion(beganAfter: 0.04)
        up.told(progress: 0.3)
        for (interruption, text) in texts {
            XCTAssertEqual(
                up.line(.cancelled(interruption)),
                "Gestures: up followed the hand: missionControl, vertical +, began after 40 ms, 1 update, "
                    + "furthest 0.30, at 0.30: cancelled (\(text))"
            )
        }
        XCTAssertEqual(
            DockFollowedMotion.desktopsSwipeTakenBackLine(.screensChanged),
            "Gestures: a swipe of the desktops was taken back (the screens changed)"
        )
        XCTAssertEqual(
            DockFollowedMotion.desktopsSwipeTakenBackLine(.displaysSlept),
            "Gestures: a swipe of the desktops was taken back (the displays went to sleep)"
        )
        // No number of a hold can break the line.
        var odd = motion(beganAfter: .infinity)
        odd.fullProgress = 0
        odd.told(progress: .nan)
        XCTAssertTrue(odd.line(.ended(velocity: .infinity, expected: false)).hasPrefix("Gestures: up followed the hand: "))
    }
}
