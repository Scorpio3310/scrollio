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
        XCTAssertEqual(DockFollowTuning.maximumVelocity, 12)
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
