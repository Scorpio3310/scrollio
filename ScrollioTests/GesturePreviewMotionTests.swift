//
//  GesturePreviewMotionTests.swift
//  MosTests
//
//  The script of the Gestures tab's preview (GesturePreviewLoop): which holds a scene
//  plays, that "Follow the hand" moves the desktops in step with the mouse and settles on
//  a whole desktop, that inverting flips the slide, that a discrete action runs once per
//  hold, and that the loop ends on the picture it started with. Pure values: nothing is
//  drawn and no action runs.
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
        XCTAssertEqual(Effect(action: SystemShortcut.moveSpaceLeft.identifier), .space(.left))
        XCTAssertEqual(Effect(action: SystemShortcut.moveSpaceRight.identifier), .space(.right))
        XCTAssertEqual(Effect(action: SystemShortcut.copy.identifier), .pulse(symbolName: SystemShortcut.copy.symbolName))
        XCTAssertEqual(Effect(action: SystemShortcut.mouseMiddleClick.identifier), .pulse(symbolName: SystemShortcut.mouseMiddleClick.symbolName))
        XCTAssertEqual(Effect(action: "somethingUnknown"), .pulse(symbolName: Effect.fallbackSymbol))

        XCTAssertEqual(Effect.space(.left).shift, -1)
        XCTAssertEqual(Effect.space(.right).shift, 1)
        for effect in [Effect.none, .missionControl, .appGrid, .pulse(symbolName: "doc.on.doc")] {
            XCTAssertEqual(effect.shift, 0)
        }
        XCTAssertEqual(Effect.none.duration, 0)
        XCTAssertGreaterThan(Effect.missionControl.duration, 1)
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

        // In "Follow the hand" up, down and click keep their one action per hold.
        let followUp = Loop(scene: scene(mode: .interactive, focus: .up))
        XCTAssertEqual(followUp.legs.map(\.kind), [.move])
        let followLeft = Loop(scene: scene(mode: .interactive, focus: .left))
        XCTAssertEqual(followLeft.legs.first?.kind, .follow)
        XCTAssertEqual(followLeft.legs.first?.direction, .left)
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
