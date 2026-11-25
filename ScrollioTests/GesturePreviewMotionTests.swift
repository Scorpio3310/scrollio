//
//  GesturePreviewMotionTests.swift
//  MosTests
//
//  The script of the Gestures tab's preview (GesturePreviewLoop): which holds a scene
//  plays, that "Follow the hand" moves the desktops in step with the mouse and settles on
//  a whole desktop, that inverting flips the slide, that a discrete action runs once per
//  hold, and that the loop ends on the picture it started with. With "Up and Down follow
//  the hand too": that a row whose view follows on this Mac opens it as far as the mouse
//  has moved (Mission Control, Show Desktop, the app grid), that every other row keeps its
//  one action per hold, and what the round and the still frame show then. Pure values:
//  nothing is drawn and no action runs.
//

import XCTest
@testable import Scrollio_Debug

final class GesturePreviewMotionTests: XCTestCase {

    private typealias Loop = GesturePreviewLoop
    private typealias Leg = GesturePreviewLeg
    private typealias Effect = GesturePreviewEffect

    private func scene(
        mode: MouseGestureMode = .discrete,
        focus: MouseGestureSettingsControls.Slot? = nil,
        configure: (inout MouseGestureSettings) -> Void = { _ in }
    ) -> GesturePreviewScene {
        var gesture = MouseGestureSettings.default
        gesture.mode = mode
        configure(&gesture)
        return GesturePreviewScene(gesture: gesture, focus: focus)
    }

    /// A Mac on which views of the Dock follow the hand: the swipe can be built, events can
    /// be posted, the Dock's own gestures are on. Apps follows only in a build that lets it.
    private func mac(
        version: Int = 27, apps: Bool = false, swipe: Bool = true, canPost: Bool = true,
        switches: DockGestureSwitches = .allOn
    ) -> DockFollowAvailability {
        return DockFollowAvailability(
            swipeIsAvailable: swipe, canPostEvents: canPost, majorVersion: version, switches: switches, appsMayFollow: apps
        )
    }

    /// "Follow the hand" with "Up and Down follow the hand too" on; without another Mac,
    /// one on which all three views follow.
    private func followScene(
        focus: MouseGestureSettingsControls.Slot? = nil,
        on availability: DockFollowAvailability? = nil,
        configure: (inout MouseGestureSettings) -> Void = { _ in }
    ) -> GesturePreviewScene {
        var gesture = MouseGestureSettings.default
        gesture.mode = .interactive
        gesture.actionsFollowHand = true
        configure(&gesture)
        return GesturePreviewScene(gesture: gesture, focus: focus, availability: availability ?? mac(apps: true))
    }

    /// The three views a row can open with the hand, each on the row and with the action
    /// that opens it, and the number of the frame that draws it.
    private var followedViews: [(name: String, scene: GesturePreviewScene, opened: (Loop.Frame) -> Double)] {
        let showDesktop = SystemShortcut.showDesktop.identifier
        return [
            ("Mission Control, up", followScene(focus: .up), { $0.overview }),
            ("the app grid, down", followScene(focus: .down), { $0.appGrid }),
            ("Show Desktop, up", followScene(focus: .up) { $0.upAction = showDesktop }, { $0.showDesktop }),
            ("Show Desktop, down", followScene(focus: .down) { $0.downAction = showDesktop }, { $0.showDesktop }),
        ]
    }

    /// Frames every `step` seconds over the whole loop.
    private func frames(_ loop: Loop, step: TimeInterval = 0.005) -> [(time: TimeInterval, frame: Loop.Frame)] {
        return stride(from: 0, to: loop.length, by: step).map { ($0, loop.frame(at: $0)) }
    }

    private func assertClose(_ a: Loop.Frame, _ b: Loop.Frame, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.leg, b.leg, message, file: file, line: line)
        XCTAssertEqual(Double(a.mouseOffset.x), Double(b.mouseOffset.x), accuracy: 1e-6, message, file: file, line: line)
        XCTAssertEqual(Double(a.mouseOffset.y), Double(b.mouseOffset.y), accuracy: 1e-6, message, file: file, line: line)
        XCTAssertEqual(a.buttonDepth, b.buttonDepth, accuracy: 1e-6, message, file: file, line: line)
        XCTAssertEqual(a.desktop, b.desktop, accuracy: 1e-6, message, file: file, line: line)
        XCTAssertEqual(a.overview, b.overview, accuracy: 1e-6, message, file: file, line: line)
        XCTAssertEqual(a.actionsFired, b.actionsFired, message, file: file, line: line)
    }

    // MARK: - Effects of actions

    func testEachActionHasTheEffectItShows() {
        XCTAssertEqual(Effect(action: ""), .none)
        XCTAssertEqual(Effect(action: SystemShortcut.missionControl.identifier), .missionControl)
        XCTAssertEqual(Effect(action: SystemShortcut.appExpose.identifier), .appGrid, "shown as Launchpad")
        XCTAssertEqual(Effect(action: SystemShortcut.showDesktop.identifier), .showDesktop)
        XCTAssertEqual(Effect(action: SystemShortcut.moveSpaceLeft.identifier), .space(.left))
        XCTAssertEqual(Effect(action: SystemShortcut.moveSpaceRight.identifier), .space(.right))
        XCTAssertEqual(Effect(action: SystemShortcut.copy.identifier), .pulse(symbolName: SystemShortcut.copy.symbolName))
        XCTAssertEqual(Effect(action: SystemShortcut.mouseMiddleClick.identifier), .pulse(symbolName: SystemShortcut.mouseMiddleClick.symbolName))
        XCTAssertEqual(Effect(action: "somethingUnknown"), .pulse(symbolName: Effect.fallbackSymbol))

        XCTAssertEqual(Effect.space(.left).shift, -1)
        XCTAssertEqual(Effect.space(.right).shift, 1)
        for effect in [Effect.none, .missionControl, .appGrid, .showDesktop, .pulse(symbolName: "doc.on.doc")] {
            XCTAssertEqual(effect.shift, 0)
        }
        XCTAssertEqual(Effect.none.duration, 0)
        XCTAssertGreaterThan(Effect.missionControl.duration, 1)
        XCTAssertEqual(Effect.showDesktop.duration, Effect.missionControl.duration, "it opens, stays and closes as the overview does")

        // What a hold opens with the hand looks as the action that opens it at once.
        for target in DockFollowTarget.allCases {
            XCTAssertEqual(Effect(opening: target), Effect(action: target.actionIdentifier), "\(target)")
        }
        XCTAssertEqual(Effect(opening: .apps), .appGrid)
    }

    // MARK: - Which holds

    func testWithNothingPointedAtItShowsLeftThenRight() {
        let loop = Loop(scene: scene())
        XCTAssertEqual(loop.legs.map(\.kind), [.move, .move])
        XCTAssertEqual(loop.legs.map(\.direction), [.left, .right])
        XCTAssertEqual(loop.legs.map(\.effect), [.space(.left), .space(.right)])
        XCTAssertEqual(loop.starts, [0, loop.legs[0].length])
        XCTAssertEqual(loop.length, loop.legs[0].length + loop.legs[1].length, accuracy: 1e-9)

        let follow = Loop(scene: scene(mode: .interactive))
        XCTAssertEqual(follow.legs.map(\.kind), [.follow, .follow])
        XCTAssertEqual(follow.legs.map(\.direction), [.left, .right])
        XCTAssertEqual(follow.legs.map(\.shift), [1, -1], "moving left brings in the desktop on the right")
    }

    func testThePointedRowDecidesTheHold() {
        let up = Loop(scene: scene(focus: .up))
        XCTAssertEqual(up.legs, [.move(.up, effect: .missionControl)])

        let down = Loop(scene: scene(focus: .down))
        XCTAssertEqual(down.legs, [.move(.down, effect: .appGrid)])

        let click = Loop(scene: scene(focus: .click))
        XCTAssertEqual(click.legs, [.click(effect: .missionControl)])
        XCTAssertNil(click.legs[0].direction)

        // In "Follow the hand" up, down and click keep their one action per hold while "Up
        // and Down follow the hand too" is off, whatever this Mac could do.
        let followUp = Loop(scene: scene(mode: .interactive, focus: .up))
        XCTAssertEqual(followUp.legs.map(\.kind), [.move])
        var switchOff = scene(mode: .interactive, focus: .up)
        switchOff.availability = mac(apps: true)
        XCTAssertEqual(Loop(scene: switchOff).legs, [.move(.up, effect: .missionControl)])
        let followLeft = Loop(scene: scene(mode: .interactive, focus: .left))
        XCTAssertEqual(followLeft.legs.first?.kind, .follow)
        XCTAssertEqual(followLeft.legs.first?.direction, .left)
    }

    /// With the switch on, a row still runs its action once where it does not follow: an
    /// action with no view to open with the hand, a view this Mac does not open with the
    /// hand, the click, and everything in "One action per hold".
    func testARowThatDoesNotFollowKeepsItsOneActionPerHold() {
        let copy = SystemShortcut.copy.identifier
        XCTAssertEqual(
            Loop(scene: followScene(focus: .up) { $0.upAction = copy }).legs,
            [.move(.up, effect: .pulse(symbolName: SystemShortcut.copy.symbolName))]
        )
        XCTAssertEqual(Loop(scene: followScene(focus: .up) { $0.upAction = "" }).legs, [.move(.up, effect: .none)])
        XCTAssertEqual(Loop(scene: followScene(focus: .down, on: mac())).legs, [.move(.down, effect: .appGrid)],
                       "Apps runs once in a build that does not let it follow")
        XCTAssertEqual(Loop(scene: followScene(focus: .up, on: mac(swipe: false))).legs, [.move(.up, effect: .missionControl)],
                       "the swipe cannot be built")
        XCTAssertEqual(Loop(scene: followScene(focus: .up, on: mac(canPost: false))).legs, [.move(.up, effect: .missionControl)])
        let missionControlOff = DockGestureSwitches(missionControl: false, showDesktop: true, launchpad: true)
        XCTAssertEqual(Loop(scene: followScene(focus: .up, on: mac(switches: missionControlOff))).legs,
                       [.move(.up, effect: .missionControl)], "its trackpad gesture is off")
        let showDesktop = SystemShortcut.showDesktop.identifier
        XCTAssertEqual(Loop(scene: followScene(focus: .down, on: mac(version: 26)) { $0.downAction = showDesktop }).legs,
                       [.move(.down, effect: .showDesktop)], "Show Desktop runs once before macOS 27")
        XCTAssertEqual(Loop(scene: followScene(focus: .click)).legs, [.click(effect: .missionControl)])
        // Left and right are the desktops', whatever their actions are.
        XCTAssertEqual(Loop(scene: followScene(focus: .left) { $0.leftAction = SystemShortcut.missionControl.identifier }).legs.first,
                       .follow(.left, invert: false))

        // "One action per hold": the stored switch means nothing.
        var discrete = followScene(focus: .up)
        discrete.gesture.mode = .discrete
        XCTAssertEqual(Loop(scene: discrete).legs, [.move(.up, effect: .missionControl)])
        discrete.focus = nil
        XCTAssertEqual(Loop(scene: discrete).legs.map(\.direction), [.left, .right])
    }

    /// Without a value handed in, a scene asks this Mac.
    func testASceneAsksThisMacWhatFollowsUnlessItIsTold() {
        XCTAssertEqual(GesturePreviewScene().availability, DockFollowAvailability.live)
        XCTAssertEqual(GesturePreviewScene(gesture: .default, focus: .up).availability, DockFollowAvailability.live)
        let told = GesturePreviewScene(availability: mac(version: 14))
        XCTAssertEqual(told.availability, mac(version: 14))
        XCTAssertNotEqual(told, GesturePreviewScene(availability: mac(version: 27)), "another Mac is another scene: the demo restarts")
    }

    func testWithLeftAndRightInvertedTheOtherHandRunsARowsAction() {
        let loop = Loop(scene: scene(focus: .left) { $0.invertHorizontal = true })
        // The Left row's action (move a Space left) runs when the hand moves right.
        XCTAssertEqual(loop.legs.first?.direction, .right)
        XCTAssertEqual(loop.legs.first?.effect, .space(.left))

        let cycle = Loop(scene: scene { $0.invertHorizontal = true })
        XCTAssertEqual(cycle.legs.map(\.direction), [.left, .right])
        XCTAssertEqual(cycle.legs.map(\.effect), [.space(.right), .space(.left)])
    }

    // MARK: - The turn to the button's side

    /// A mouse drawn in two views turns to the side its held button is on: the turn ends as
    /// the button goes down and the turn back begins when it is up, a quarter of a second
    /// each; the picture is not at rest while it turns.
    func testTheMouseTurnsToTheButtonsSideForEveryHold() {
        let turn = MouseArtworkTurn.duration
        let scenes = [scene(focus: .up), scene(focus: .click), scene(mode: .interactive, focus: .left), scene()]
        for scene in scenes {
            let loop = Loop(scene: scene)
            for (index, leg) in loop.legs.enumerated() {
                let start = loop.starts[index]
                let message = "\(String(describing: scene.focus)) leg \(index)"
                XCTAssertGreaterThanOrEqual(leg.pressTime, turn, "there is time to turn before the press")
                XCTAssertEqual(loop.frame(at: start).sideTurn, 0, message)
                XCTAssertEqual(loop.frame(at: start + leg.pressTime - turn).sideTurn, 0, accuracy: 1e-9, message)
                let turning = loop.frame(at: start + leg.pressTime - turn / 2)
                XCTAssertEqual(turning.sideTurn, 0.5, accuracy: 1e-9, message)
                XCTAssertFalse(turning.isAtRest, "not at rest while it turns: \(message)")
                XCTAssertEqual(turning.buttonDepth, 0, accuracy: 1e-9, "the button is still up: \(message)")
                XCTAssertEqual(loop.frame(at: start + leg.pressTime).sideTurn, 1, accuracy: 1e-9, "turned when the button goes down: \(message)")
                for time in stride(from: leg.pressTime, through: leg.releaseTime + Loop.buttonTravel, by: 0.02) {
                    XCTAssertEqual(loop.frame(at: start + time).sideTurn, 1, accuracy: 1e-9, "turned for the whole hold: \(message)")
                }
                let back = loop.frame(at: start + leg.releaseTime + Loop.buttonTravel + turn / 2)
                XCTAssertEqual(back.sideTurn, 0.5, accuracy: 1e-9, message)
                XCTAssertFalse(back.isAtRest, message)
                XCTAssertEqual(loop.frame(at: start + leg.releaseTime + Loop.buttonTravel + turn).sideTurn, 0, accuracy: 1e-9, message)
                XCTAssertLessThanOrEqual(leg.releaseTime + Loop.buttonTravel + turn, leg.length, "back before the next hold: \(message)")
                XCTAssertEqual(loop.frame(at: start + leg.length - 0.001).sideTurn, 0, accuracy: 1e-9, message)
            }
            XCTAssertEqual(loop.stillFrame.sideTurn, 1, "the still holds the button, turned")
        }
    }

    // MARK: - Follow the hand

    func testFollowProgressIsProportionalToTheMouseMovement() {
        for speed in [0.5, 1, 1.5, 3] {
            let loop = Loop(scene: scene(mode: .interactive, focus: .left) { $0.trackingSpeed = speed })
            let leg = loop.legs[0]
            let travel = Double(loop.followTravel)
            var checked = 0
            for time in stride(from: leg.pressTime, through: leg.releaseTime, by: 0.01) {
                let frame = loop.frame(at: time)
                XCTAssertEqual(frame.mouseOffset.y, 0)
                // Moving left (negative x) moves the desktops towards the next one.
                XCTAssertEqual(frame.swipeProgress, -Double(frame.mouseOffset.x) / travel, accuracy: 1e-9, "speed \(speed) at \(time)")
                XCTAssertEqual(frame.desktop, Loop.wrappedDesktop(frame.swipeProgress), accuracy: 1e-9)
                if time >= leg.pressTime + Loop.buttonTravel {
                    XCTAssertEqual(frame.buttonDepth, 1, accuracy: 1e-9, "held all the way")
                }
                checked += 1
            }
            XCTAssertGreaterThan(checked, 100)
            // Half-way, it stops for a moment.
            let stop = loop.frame(at: (Loop.followFirstStopEnd + Loop.followSecondStart) / 2)
            XCTAssertEqual(stop.swipeProgress, Loop.followFirstStop, accuracy: 1e-9)
            XCTAssertEqual(stop.desktop, 0.5, accuracy: 1e-9)
        }
    }

    func testAHigherTrackingSpeedNeedsLessMouseMovement() {
        XCTAssertEqual(Loop.followTravel(trackingSpeed: 1), 30)
        XCTAssertEqual(Loop.followTravel(trackingSpeed: 2), 15)
        XCTAssertEqual(Loop.followTravel(trackingSpeed: 1.5), 20)
        XCTAssertEqual(Loop.followTravel(trackingSpeed: 0.5), 56, "kept inside the card")
        XCTAssertEqual(Loop.followTravel(trackingSpeed: 3), 14, "still visibly moves")
        XCTAssertEqual(Loop.followTravel(trackingSpeed: .nan), 30)
        XCTAssertEqual(Loop.followTravel(trackingSpeed: 0), 30)

        let slow = Loop(scene: scene(mode: .interactive, focus: .left) { $0.trackingSpeed = 1 })
        let fast = Loop(scene: scene(mode: .interactive, focus: .left) { $0.trackingSpeed = 2 })
        let time = Loop.followRelease
        XCTAssertEqual(slow.frame(at: time).swipeProgress, fast.frame(at: time).swipeProgress, accuracy: 1e-9)
        XCTAssertLessThan(abs(fast.frame(at: time).mouseOffset.x), abs(slow.frame(at: time).mouseOffset.x))
    }

    func testFollowSettlesOnAWholeDesktopAfterTheRelease() {
        let loop = Loop(scene: scene(mode: .interactive))
        let leg = loop.legs[0]
        let released = loop.frame(at: leg.releaseTime)
        XCTAssertEqual(released.swipeProgress, Loop.followReleaseShare, accuracy: 1e-9)

        // The desktops finish the way by themselves, then rest on the next one.
        var previous = released.swipeProgress
        for time in stride(from: leg.releaseTime, through: leg.releaseTime + Loop.followSettle, by: 0.01) {
            let progress = loop.frame(at: time).swipeProgress
            XCTAssertGreaterThanOrEqual(progress, previous - 1e-12)
            previous = progress
        }
        let settled = loop.frame(at: leg.releaseTime + Loop.followSettle + 0.01)
        XCTAssertEqual(settled.swipeProgress, 1, accuracy: 1e-9)
        XCTAssertEqual(settled.desktop, 1, accuracy: 1e-9)
        XCTAssertEqual(settled.buttonDepth, 0, accuracy: 1e-9, "let go")

        // The mouse glides back with the button up: the desktop stays where it settled.
        let back = loop.frame(at: Loop.followReturnEnd + 0.01)
        XCTAssertEqual(back.mouseOffset, .zero)
        XCTAssertEqual(back.desktop, 1, accuracy: 1e-9)
        XCTAssertTrue(back.isAtRest)

        // The second leg comes back to the first desktop.
        let end = loop.frame(at: loop.length - 0.01)
        XCTAssertEqual(end.leg, 1)
        XCTAssertEqual(end.desktop, 0, accuracy: 1e-9)
        XCTAssertEqual(end.swipeProgress, -1, accuracy: 1e-9)
    }

    func testInvertFlipsTheSlide() {
        let plain = Loop(scene: scene(mode: .interactive, focus: .left))
        let inverted = Loop(scene: scene(mode: .interactive, focus: .left) { $0.invertHorizontal = true })
        XCTAssertEqual(plain.legs[0].shift, 1)
        XCTAssertEqual(inverted.legs[0].shift, -1)
        for time in stride(from: 0.5, through: 2.4, by: 0.1) {
            let a = plain.frame(at: time), b = inverted.frame(at: time)
            XCTAssertEqual(a.mouseOffset, b.mouseOffset, "the hand does the same")
            XCTAssertEqual(a.swipeProgress, -b.swipeProgress, accuracy: 1e-9, "the desktops go the other way")
        }
        XCTAssertEqual(inverted.frame(at: Loop.followRelease + Loop.followSettle + 0.05).desktop, 1, accuracy: 1e-9,
                       "one desktop the other way shows the other wallpaper too")

        let right = Loop(scene: scene(mode: .interactive, focus: .right) { $0.invertHorizontal = true })
        XCTAssertEqual(right.legs[0].direction, .right)
        XCTAssertEqual(right.legs[0].shift, 1)
    }

    // MARK: - Up and Down follow the hand too

    func testARowThatFollowsOpensItsViewWithTheHand() {
        let up = Loop(scene: followScene(focus: .up))
        XCTAssertEqual(up.legs, [.follow(.up, opening: .missionControl)])
        let leg = up.legs[0]
        XCTAssertEqual(leg.kind, .follow)
        XCTAssertEqual(leg.direction, .up)
        XCTAssertEqual(leg.effect, .missionControl)
        XCTAssertEqual(leg.shift, 0, "no desktop moves")
        XCTAssertNil(leg.fireTime, "nothing runs at one moment: the view opens with the hand")
        XCTAssertTrue(leg.opensWithTheHand)
        XCTAssertFalse(Leg.follow(.left, invert: false).opensWithTheHand)
        XCTAssertFalse(Leg.move(.up, effect: .missionControl).opensWithTheHand)
        // Press, half-way, a stop, on, let go, as sideways; then the view opens by itself,
        // stays as long as the overview of one action per hold does, and closes.
        XCTAssertEqual(leg.pressTime, Leg.follow(.left, invert: false).pressTime)
        XCTAssertEqual(leg.releaseTime, Leg.follow(.left, invert: false).releaseTime)
        XCTAssertEqual(leg.length, 4.2, accuracy: 1e-9)

        XCTAssertEqual(Loop(scene: followScene(focus: .down)).legs, [.follow(.down, opening: .appGrid)])
        let showDesktop = SystemShortcut.showDesktop.identifier
        XCTAssertEqual(Loop(scene: followScene(focus: .up) { $0.upAction = showDesktop }).legs, [.follow(.up, opening: .showDesktop)])
        // The hand moves the row's way, whatever the row opens.
        XCTAssertEqual(Loop(scene: followScene(focus: .down) { $0.downAction = SystemShortcut.missionControl.identifier }).legs,
                       [.follow(.down, opening: .missionControl)])
        // A release build: Mission Control and Show Desktop, not Apps.
        XCTAssertEqual(Loop(scene: followScene(focus: .up, on: mac())).legs, [.follow(.up, opening: .missionControl)])
        // Before macOS 27: Mission Control only.
        XCTAssertEqual(Loop(scene: followScene(focus: .up, on: mac(version: 14))).legs, [.follow(.up, opening: .missionControl)])
    }

    func testTheViewIsOpenAsFarAsTheHandHasMoved() {
        for (name, scene, opened) in followedViews {
            for speed in [0.5, 1, 1.5, 3] {
                var scene = scene
                scene.gesture.trackingSpeed = speed
                let loop = Loop(scene: scene)
                let leg = loop.legs[0]
                let travel = Double(loop.followVerticalTravel)
                let message = "\(name), speed \(speed)"
                var checked = 0
                for time in stride(from: leg.pressTime, through: leg.releaseTime, by: 0.01) {
                    let frame = loop.frame(at: time)
                    XCTAssertEqual(frame.mouseOffset.x, 0, message)
                    // Up is towards the top of the card (y down).
                    let moved = Double(leg.direction == .up ? -frame.mouseOffset.y : frame.mouseOffset.y)
                    XCTAssertGreaterThanOrEqual(moved, 0, "the hand moves the row's way: \(message)")
                    XCTAssertEqual(opened(frame), moved / travel, accuracy: 1e-9, "\(message) at \(time)")
                    // Nothing else answers: one view, no desktop moves, no action runs.
                    XCTAssertEqual(frame.overview + frame.appGrid + frame.showDesktop, opened(frame), accuracy: 1e-12, message)
                    XCTAssertEqual(frame.desktop, 0, message)
                    XCTAssertEqual(frame.swipeProgress, 0, message)
                    XCTAssertEqual(frame.pulse, 0, message)
                    XCTAssertEqual(frame.actionsFired, 0, message)
                    if time >= leg.pressTime + Loop.buttonTravel {
                        XCTAssertEqual(frame.buttonDepth, 1, accuracy: 1e-9, "held all the way: \(message)")
                    }
                    checked += 1
                }
                XCTAssertGreaterThan(checked, 100)
                // Half-way the hand stops for a moment, and the view stands half open.
                for time in stride(from: Loop.followFirstStopEnd, through: Loop.followSecondStart, by: 0.05) {
                    let stop = loop.frame(at: time)
                    XCTAssertEqual(opened(stop), Loop.followFirstStop, accuracy: 1e-9, message)
                    XCTAssertEqual(Double(abs(stop.mouseOffset.y)), travel * Loop.followFirstStop, accuracy: 1e-9, message)
                }
                XCTAssertTrue(loop.frame(at: (Loop.followFirstStopEnd + Loop.followSecondStart) / 2).isAtRest, "nothing moves at the stop: \(message)")
                XCTAssertFalse(loop.frame(at: (Loop.followFirstStart + Loop.followFirstStopEnd) / 2).isAtRest, message)
            }
        }
    }

    func testTheViewOpensAllTheWayAfterTheReleaseAndClosesAgain() {
        for (name, scene, opened) in followedViews {
            let loop = Loop(scene: scene)
            let leg = loop.legs[0]
            let released = loop.frame(at: leg.releaseTime)
            XCTAssertEqual(opened(released), Loop.followReleaseShare, accuracy: 1e-9, name)

            // It finishes the way by itself.
            var previous = opened(released)
            for time in stride(from: leg.releaseTime, through: leg.releaseTime + Loop.followSettle, by: 0.01) {
                let frame = loop.frame(at: time)
                XCTAssertGreaterThanOrEqual(opened(frame), previous - 1e-12, name)
                previous = opened(frame)
            }
            XCTAssertFalse(loop.frame(at: leg.releaseTime + Loop.followSettle / 2).isAtRest, name)
            let whole = loop.frame(at: leg.releaseTime + Loop.followSettle + 0.01)
            XCTAssertEqual(opened(whole), 1, accuracy: 1e-9, name)
            XCTAssertEqual(whole.buttonDepth, 0, accuracy: 1e-9, "let go: \(name)")

            // The mouse glides back with the button up while the view stays whole.
            let back = loop.frame(at: Loop.followReturnEnd + 0.01)
            XCTAssertEqual(back.mouseOffset, .zero, name)
            XCTAssertEqual(opened(back), 1, accuracy: 1e-9, name)
            XCTAssertTrue(back.isAtRest, name)
            XCTAssertEqual(opened(loop.frame(at: Loop.followCloseStart)), 1, accuracy: 1e-9, name)

            // Then it closes, and the hold ends on the picture it began with.
            XCTAssertEqual(Loop.followCloseStart, Loop.followRelease + Loop.followSettle + Loop.overlayHold, accuracy: 1e-9)
            let closing = loop.frame(at: Loop.followCloseStart + Loop.overlayOut / 2)
            XCTAssertEqual(opened(closing), 0.5, accuracy: 1e-9, name)
            XCTAssertFalse(closing.isAtRest, name)
            let closed = loop.frame(at: Loop.followCloseEnd + 0.001)
            XCTAssertEqual(opened(closed), 0, accuracy: 1e-9, name)
            XCTAssertTrue(closed.isAtRest, name)

            // One opening per hold, and no action runs in it.
            let values = frames(loop).map { opened($0.frame) }
            XCTAssertEqual(values.max() ?? 0, 1, accuracy: 1e-9, name)
            var rises = 0
            for (a, b) in zip(values, values.dropFirst()) where a == 0 && b > 0 {
                rises += 1
            }
            XCTAssertEqual(rises, 1, name)
            XCTAssertTrue(frames(loop).allSatisfy { $0.frame.actionsFired == 0 }, name)
            XCTAssertTrue(values.allSatisfy { $0 >= 0 && $0 <= 1 + 1e-12 }, name)
        }
    }

    func testAHigherSwipeSpeedNeedsLessMovementUpAndDownToo() {
        XCTAssertEqual(Loop.followVerticalTravel(trackingSpeed: 1), 12)
        XCTAssertEqual(Loop.followVerticalTravel(trackingSpeed: 1.2), 10)
        XCTAssertEqual(Loop.followVerticalTravel(trackingSpeed: 0.8), 15)
        XCTAssertEqual(Loop.followVerticalTravel(trackingSpeed: 0.5), 15, "kept inside the card")
        XCTAssertEqual(Loop.followVerticalTravel(trackingSpeed: 3), 8, "still visibly moves")
        XCTAssertEqual(Loop.followVerticalTravel(trackingSpeed: .nan), 12)
        XCTAssertEqual(Loop.followVerticalTravel(trackingSpeed: 0), 12)
        // The longest way: the mouse is let go as far out as one action per hold takes it,
        // which the card has room for (with the arrow ahead of the mouse).
        XCTAssertEqual(Loop.followVerticalTravelRange.upperBound * CGFloat(Loop.followReleaseShare), Loop.verticalReach, accuracy: 1e-9)

        let slow = Loop(scene: followScene(focus: .up) { $0.trackingSpeed = 1 })
        let fast = Loop(scene: followScene(focus: .up) { $0.trackingSpeed = 1.5 })
        let time = Loop.followRelease
        XCTAssertEqual(slow.frame(at: time).overview, fast.frame(at: time).overview, accuracy: 1e-9)
        XCTAssertLessThan(abs(fast.frame(at: time).mouseOffset.y), abs(slow.frame(at: time).mouseOffset.y))
        // Sideways is untouched by it.
        XCTAssertEqual(slow.followTravel, Loop.followTravel(trackingSpeed: 1))
    }

    func testTheFreePointerDriftsUpWithAFollowedHoldToo() {
        let free = Loop(scene: followScene(focus: .up) { $0.freezePointer = false })
        let frame = free.frame(at: Loop.followRelease)
        XCTAssertEqual(frame.pointerOffset.y, frame.mouseOffset.y * Loop.pointerGain)
        XCTAssertLessThan(frame.pointerOffset.y, -8)
        XCTAssertEqual(Loop(scene: followScene(focus: .up)).frame(at: Loop.followRelease).pointerOffset, .zero)
    }

    /// Nothing pointed at: after left and right the round shows what follows the hand up
    /// and down, and only that.
    func testTheRoundTakesInTheDirectionsThatFollow() {
        let all = Loop(scene: followScene())
        XCTAssertEqual(all.legs.map(\.direction), [.left, .right, .up, .down])
        XCTAssertEqual(all.legs.map(\.kind), [.follow, .follow, .follow, .follow])
        XCTAssertEqual(all.legs.map(\.effect), [.none, .none, .missionControl, .appGrid])
        XCTAssertEqual(all.legs.map(\.shift), [1, -1, 0, 0], "it ends on the desktop it began on")
        XCTAssertEqual(all.length, 2 * 3.05 + 2 * 4.2, accuracy: 1e-9)
        XCTAssertEqual(all.legs.count, 4, "nothing plays twice")

        // A release build with the defaults: Mission Control follows, Apps does not.
        let release = Loop(scene: followScene(on: mac()))
        XCTAssertEqual(release.legs.map(\.direction), [.left, .right, .up])
        XCTAssertEqual(release.legs.last, .follow(.up, opening: .missionControl))
        // Show Desktop on Down joins it; Copy on Up leaves.
        let showDesktop = Loop(scene: followScene(on: mac()) {
            $0.upAction = SystemShortcut.copy.identifier
            $0.downAction = SystemShortcut.showDesktop.identifier
        })
        XCTAssertEqual(showDesktop.legs.map(\.direction), [.left, .right, .down])
        XCTAssertEqual(showDesktop.legs.last?.effect, .showDesktop)
        // Nothing follows up or down: left and right, as before.
        let sidewaysOnly = [followScene(on: mac(swipe: false)), scene(mode: .interactive), followScene { $0.upAction = ""; $0.downAction = "" }]
        for scene in sidewaysOnly {
            XCTAssertEqual(Loop(scene: scene).legs.map(\.direction), [.left, .right], "\(scene)")
        }

        // Each hold of the round answers with its own view only.
        for (index, leg) in all.legs.enumerated() {
            let stop = all.frame(at: all.starts[index] + leg.stillTime)
            XCTAssertEqual(stop.leg, index)
            XCTAssertEqual(stop.overview, leg.effect == .missionControl ? 0.5 : 0, accuracy: 1e-9, "leg \(index)")
            XCTAssertEqual(stop.appGrid, leg.effect == .appGrid ? 0.5 : 0, accuracy: 1e-9, "leg \(index)")
            XCTAssertEqual(stop.desktop, leg.effect == .none ? 0.5 : 0, accuracy: 1e-9, "leg \(index)")
        }
    }

    func testALoopWithFollowedDirectionsEndsWhereItStarted() {
        let showDesktop = SystemShortcut.showDesktop.identifier
        let scenes: [GesturePreviewScene] = [
            followScene(), followScene(on: mac()), followScene(focus: .up), followScene(focus: .down),
            followScene(focus: .up) { $0.upAction = showDesktop },
            followScene { $0.downAction = showDesktop; $0.invertHorizontal = true },
            followScene(focus: .down) { $0.freezePointer = false },
            scene(focus: .up) { $0.upAction = showDesktop },
        ]
        for scene in scenes {
            let loop = Loop(scene: scene)
            let start = loop.frame(at: 0)
            let end = loop.frame(at: loop.length - 1e-6)
            let message = "\(scene)"
            XCTAssertEqual(start.desktop, 0, message)
            XCTAssertEqual(end.desktop, start.desktop, accuracy: 1e-6, message)
            XCTAssertEqual(end.mouseOffset, start.mouseOffset, message)
            XCTAssertEqual(end.buttonDepth, 0, accuracy: 1e-9, message)
            for frame in [start, end] {
                XCTAssertEqual(frame.overview, 0, message)
                XCTAssertEqual(frame.appGrid, 0, message)
                XCTAssertEqual(frame.showDesktop, 0, message)
                XCTAssertEqual(frame.pulse, 0, accuracy: 1e-9, message)
                XCTAssertEqual(frame.pointerOffset, .zero, message)
                XCTAssertEqual(frame.sideTurn, 0, accuracy: 1e-9, message)
                XCTAssertTrue(frame.isAtRest, message)
            }
            // Every hold begins on a closed, resting picture, the mouse seen from above.
            for (index, begin) in loop.starts.enumerated() {
                let frame = loop.frame(at: begin)
                XCTAssertEqual(frame.leg, index, message)
                XCTAssertEqual(frame.overview + frame.appGrid + frame.showDesktop, 0, message)
                XCTAssertEqual(frame.mouseOffset, .zero, message)
                XCTAssertEqual(frame.sideTurn, 0, accuracy: 1e-9, message)
                XCTAssertTrue(frame.isAtRest, message)
                let leg = loop.legs[index]
                XCTAssertLessThanOrEqual(leg.releaseTime + Loop.buttonTravel + MouseArtworkTurn.duration, leg.length, message)
            }
            assertClose(loop.frame(at: loop.length + 0.7), loop.frame(at: 0.7), message)
            assertClose(loop.frame(at: -0.3), loop.frame(at: loop.length - 0.3), message)
        }
    }

    /// Reduce Motion: a row that follows shows its view half open under a held, half-moved
    /// mouse; the same row in "One action per hold" shows it whole. The two can be told
    /// apart in one picture.
    func testTheStillFrameOfARowThatFollowsIsTheHalfOpenView() {
        for (name, scene, opened) in followedViews {
            let loop = Loop(scene: scene)
            let still = loop.stillFrame
            XCTAssertEqual(opened(still), 0.5, accuracy: 1e-9, name)
            XCTAssertEqual(still.buttonDepth, 1, accuracy: 1e-9, name)
            XCTAssertEqual(still.arrow, 1, accuracy: 1e-9, name)
            XCTAssertEqual(still.sideTurn, 1, accuracy: 1e-9, name)
            XCTAssertEqual(still.pressPulse, 0, name)
            XCTAssertTrue(still.isAtRest, name)
            let half = loop.followVerticalTravel * 0.5
            XCTAssertEqual(still.mouseOffset.y, scene.focus == .up ? -half : half, accuracy: 1e-9, name)
            XCTAssertEqual(still.mouseOffset.x, 0, name)

            var once = scene
            once.gesture.mode = .discrete
            XCTAssertEqual(opened(Loop(scene: once).stillFrame), 1, accuracy: 1e-9, "one action per hold: \(name)")
        }
        // Nothing pointed at: the first hold of the round, the desktops half-way.
        let round = Loop(scene: followScene()).stillFrame
        XCTAssertEqual(round.desktop, 0.5, accuracy: 1e-9)
        XCTAssertEqual(round.overview, 0)
    }

    /// Show Desktop has a picture of its own in "One action per hold" too: the windows go
    /// away once, stay away a moment and come back.
    func testShowDesktopRunsOnceAsTheOtherViewsDo() {
        let loop = Loop(scene: scene(focus: .up) { $0.upAction = SystemShortcut.showDesktop.identifier })
        XCTAssertEqual(loop.legs, [.move(.up, effect: .showDesktop)])
        let fire = try! XCTUnwrap(loop.legs[0].fireTime)
        XCTAssertEqual(loop.frame(at: fire - 0.001).showDesktop, 0)
        XCTAssertEqual(loop.frame(at: fire + Loop.overlayIn + 0.01).showDesktop, 1, accuracy: 1e-9)
        XCTAssertEqual(loop.frame(at: loop.legs[0].stillTime).showDesktop, 1, accuracy: 1e-9)
        XCTAssertEqual(loop.frame(at: loop.length - 0.01).showDesktop, 0)
        for (_, frame) in frames(loop) {
            XCTAssertEqual(frame.pulse, 0, "no pulse with its symbol any more")
            XCTAssertEqual(frame.overview, 0)
            XCTAssertEqual(frame.appGrid, 0)
        }
        XCTAssertEqual(loop.frame(at: loop.length - 0.01).actionsFired, 1)
    }

    // MARK: - One action per hold

    func testADiscreteActionRunsOncePerHold() {
        for focus in [nil, MouseGestureSettingsControls.Slot.up, .down, .left, .right, .click] {
            let loop = Loop(scene: scene(focus: focus))
            let message = "\(String(describing: focus))"
            var fired = 0
            var firedPerLeg = Array(repeating: 0, count: loop.legs.count)
            for (_, frame) in frames(loop) {
                XCTAssertGreaterThanOrEqual(frame.actionsFired, fired, message)
                if frame.actionsFired > fired {
                    XCTAssertEqual(frame.actionsFired, fired + 1, message)
                    firedPerLeg[frame.leg] += 1
                    fired = frame.actionsFired
                }
            }
            XCTAssertEqual(firedPerLeg, Array(repeating: 1, count: loop.legs.count), message)
            for leg in loop.legs {
                let fire = try! XCTUnwrap(leg.fireTime)
                // It runs while the button is held (Click: as it is let go).
                XCTAssertGreaterThanOrEqual(fire, leg.pressTime, message)
                XCTAssertLessThanOrEqual(fire, leg.releaseTime, message)
            }
        }
    }

    func testTheActionRunsWhenTheMouseHasMovedFarEnough() {
        let loop = Loop(scene: scene(focus: .up))
        let leg = loop.legs[0]
        let fire = try! XCTUnwrap(leg.fireTime)
        let before = loop.frame(at: fire - 0.001)
        let after = loop.frame(at: fire + 0.001)
        XCTAssertEqual(before.actionsFired, 0)
        XCTAssertEqual(after.actionsFired, 1)
        XCTAssertLessThan(after.mouseOffset.y, -Loop.verticalReach / 2, "well on its way up")
        XCTAssertEqual(after.mouseOffset.x, 0)
        XCTAssertEqual(before.overview, 0)

        // Mission Control opens once, stays a moment and closes again before the leg ends.
        let overview = frames(loop).map(\.frame.overview)
        XCTAssertEqual(overview.max() ?? 0, 1, accuracy: 1e-9)
        var rises = 0
        for (a, b) in zip(overview, overview.dropFirst()) where a == 0 && b > 0 {
            rises += 1
        }
        XCTAssertEqual(rises, 1)
        XCTAssertEqual(loop.frame(at: loop.length - 0.01).overview, 0)
    }

    func testEveryEffectShowsOnce() {
        func peak(_ loop: Loop, _ value: (Loop.Frame) -> Double) -> Double {
            return frames(loop).map { value($0.frame) }.max() ?? 0
        }
        let grid = Loop(scene: scene(focus: .down))
        XCTAssertEqual(peak(grid, \.appGrid), 1, accuracy: 1e-9)
        XCTAssertEqual(peak(grid, \.overview), 0)

        let pulse = Loop(scene: scene(focus: .click) { $0.clickAction = SystemShortcut.copy.identifier })
        XCTAssertEqual(peak(pulse, \.pulse), 1, accuracy: 1e-9)
        XCTAssertEqual(pulse.frame(at: pulse.legs[0].stillTime).pulseSymbol, SystemShortcut.copy.symbolName)

        // A Space: the desktop slides once, to the neighbour.
        let space = Loop(scene: scene(focus: .left))
        let fire = try! XCTUnwrap(space.legs[0].fireTime)
        XCTAssertEqual(space.frame(at: fire).desktop, 0, accuracy: 1e-9)
        XCTAssertEqual(space.frame(at: fire + Loop.slideDuration / 2).desktop, 1.5, accuracy: 1e-9, "half-way to the left")
        XCTAssertEqual(space.frame(at: fire + Loop.slideDuration + 0.01).desktop, 1, accuracy: 1e-9)
    }

    func testNoActionRunsNothing() {
        let loop = Loop(scene: scene(focus: .up) { $0.upAction = "" })
        XCTAssertNil(loop.legs[0].fireTime)
        for (_, frame) in frames(loop) {
            XCTAssertEqual(frame.actionsFired, 0)
            XCTAssertEqual(frame.overview, 0)
            XCTAssertEqual(frame.appGrid, 0)
            XCTAssertEqual(frame.pulse, 0)
            XCTAssertEqual(frame.desktop, 0)
        }
        // The hand still moves.
        XCTAssertLessThan(loop.frame(at: Loop.moveEnd).mouseOffset.y, -Loop.verticalReach + 0.01)
    }

    func testAClickDoesNotMoveTheMouse() {
        let loop = Loop(scene: scene(focus: .click))
        for (_, frame) in frames(loop) {
            XCTAssertEqual(frame.mouseOffset, .zero)
            XCTAssertEqual(frame.arrow, 0)
        }
        XCTAssertEqual(loop.frame(at: Loop.pressTime + 0.2).buttonDepth, 1, accuracy: 1e-9)
        XCTAssertEqual(loop.frame(at: Loop.clickRelease + 0.2).buttonDepth, 0, accuracy: 1e-9)
        // A ring when the button goes down and again when it comes up: that is the click.
        XCTAssertGreaterThan(loop.frame(at: Loop.pressTime + 0.01).pressPulse, 0.9)
        XCTAssertGreaterThan(loop.frame(at: Loop.clickRelease + 0.01).pressPulse, 0.9)
        XCTAssertEqual(Loop(scene: scene(focus: .up)).frame(at: Loop.moveRelease + 0.01).pressPulse, 0, "a move has one ring")
    }

    // MARK: - The pointer

    func testTheFrozenPointerStaysAndTheFreeOneDrifts() {
        let frozen = Loop(scene: scene())
        let free = Loop(scene: scene { $0.freezePointer = false })
        for time in stride(from: 0, to: frozen.length, by: 0.05) {
            XCTAssertEqual(frozen.frame(at: time).pointerOffset, .zero)
            let frame = free.frame(at: time)
            XCTAssertEqual(frame.pointerOffset.x, frame.mouseOffset.x * Loop.pointerGain)
            XCTAssertEqual(frame.pointerOffset.y, frame.mouseOffset.y * Loop.pointerGain)
        }
        XCTAssertLessThan(free.frame(at: Loop.moveEnd).pointerOffset.x, -10)
    }

    // MARK: - The loop

    func testTheLoopEndsWhereItStarted() {
        let scenes: [GesturePreviewScene] = [
            scene(), scene(mode: .interactive),
            scene(focus: .left), scene(focus: .right), scene(focus: .up), scene(focus: .down), scene(focus: .click),
            scene(mode: .interactive, focus: .left), scene(mode: .interactive, focus: .right),
            scene(mode: .interactive) { $0.invertHorizontal = true },
            scene { $0.leftAction = SystemShortcut.moveSpaceLeft.identifier; $0.rightAction = SystemShortcut.copy.identifier },
            scene { $0.freezePointer = false },
        ]
        for scene in scenes {
            let loop = Loop(scene: scene)
            let start = loop.frame(at: 0)
            let end = loop.frame(at: loop.length - 1e-6)
            let message = "\(scene)"
            XCTAssertEqual(start.desktop, 0, message)
            XCTAssertEqual(end.desktop, start.desktop, accuracy: 1e-6, message)
            XCTAssertEqual(end.mouseOffset, start.mouseOffset, message)
            XCTAssertEqual(end.buttonDepth, 0, accuracy: 1e-9, message)
            XCTAssertEqual(end.overview, 0, message)
            XCTAssertEqual(end.appGrid, 0, message)
            XCTAssertEqual(end.pulse, 0, accuracy: 1e-9, message)
            XCTAssertEqual(end.pointerOffset, .zero, message)
            XCTAssertTrue(start.isAtRest, message)
            XCTAssertTrue(end.isAtRest, message)
            // Times past the end wrap around.
            assertClose(loop.frame(at: loop.length + 0.7), loop.frame(at: 0.7), message)
            assertClose(loop.frame(at: -0.3), loop.frame(at: loop.length - 0.3), message)
        }
    }

    func testOneSidedSlidesPlayTwiceToComeBack() {
        // One slide changes the wallpaper: the hold plays twice, so the loop comes back to it.
        let follow = Loop(scene: scene(mode: .interactive, focus: .left))
        XCTAssertEqual(follow.legs.count, 2)
        XCTAssertEqual(follow.legs.map(\.shift), [1, 1])
        XCTAssertEqual(follow.frame(at: follow.starts[1]).desktop, 1, accuracy: 1e-9)

        let space = Loop(scene: scene(focus: .left))
        XCTAssertEqual(space.legs.count, 2)
        // An overview changes nothing: once is enough.
        XCTAssertEqual(Loop(scene: scene(focus: .up)).legs.count, 1)
        // Left moves a Space, right does something else: both twice.
        let mixed = Loop(scene: scene { $0.rightAction = SystemShortcut.copy.identifier })
        XCTAssertEqual(mixed.legs.map(\.direction), [.left, .right, .left, .right])
    }

    func testTheArrowShowsWhileTheHeldMouseMoves() {
        let loop = Loop(scene: scene(focus: .right))
        XCTAssertEqual(loop.frame(at: 0.2).arrow, 0, "before the hold")
        XCTAssertEqual(loop.frame(at: Loop.moveEnd).arrow, 1, accuracy: 1e-9)
        XCTAssertEqual(loop.frame(at: Loop.moveEnd).direction, .right)
        XCTAssertEqual(loop.frame(at: Loop.moveReturnStart + 0.1).arrow, 0, "let go")
    }

    func testTheStillFrameShowsTheHoldAtItsClearest() {
        let follow = Loop(scene: scene(mode: .interactive)).stillFrame
        XCTAssertEqual(follow.desktop, 0.5, accuracy: 1e-9, "the desktops half-way")
        XCTAssertEqual(follow.buttonDepth, 1, accuracy: 1e-9)
        XCTAssertEqual(follow.arrow, 1, accuracy: 1e-9)
        XCTAssertEqual(follow.pressPulse, 0)
        XCTAssertTrue(follow.isAtRest)

        // Cause and effect in one picture: the mouse moved with the button held, and the
        // overview open.
        let up = Loop(scene: scene(focus: .up)).stillFrame
        XCTAssertEqual(up.overview, 1, accuracy: 1e-9)
        XCTAssertEqual(up.buttonDepth, 1, accuracy: 1e-9)
        XCTAssertEqual(up.arrow, 1, accuracy: 1e-9)
        XCTAssertEqual(up.mouseOffset.y, -Loop.verticalReach, accuracy: 1e-9)
        XCTAssertTrue(up.isAtRest)
        XCTAssertEqual(Loop(scene: scene(focus: .down)).stillFrame.appGrid, 1, accuracy: 1e-9)
        let click = Loop(scene: scene(focus: .click)).stillFrame
        XCTAssertEqual(click.overview, 1, accuracy: 1e-9)
        XCTAssertEqual(click.buttonDepth, 1, accuracy: 1e-9)
        XCTAssertEqual(click.mouseOffset, .zero)
        let pointer = Loop(scene: scene(focus: .right) { $0.freezePointer = false }).stillFrame
        XCTAssertEqual(pointer.pointerOffset, pointer.mouseOffset, "the free pointer is where the hand took it")
        XCTAssertEqual(Loop(scene: scene(focus: .left)).stillFrame.desktop, 1.5, accuracy: 1e-9)
        let none = Loop(scene: scene(focus: .up) { $0.upAction = "" }).stillFrame
        XCTAssertEqual(none.buttonDepth, 1, accuracy: 1e-9)
        XCTAssertEqual(none.mouseOffset.y, -Loop.verticalReach, accuracy: 1e-9)
    }

    func testWrappedDesktop() {
        XCTAssertEqual(Loop.wrappedDesktop(0), 0)
        XCTAssertEqual(Loop.wrappedDesktop(1), 1)
        XCTAssertEqual(Loop.wrappedDesktop(2), 0)
        XCTAssertEqual(Loop.wrappedDesktop(-1), 1)
        XCTAssertEqual(Loop.wrappedDesktop(-0.25), 1.75)
        XCTAssertEqual(Loop.wrappedDesktop(-1e-12), 0)
        XCTAssertEqual(Loop.wrappedDesktop(.nan), 0)
    }
}
