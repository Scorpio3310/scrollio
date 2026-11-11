//
//  ScrollPreviewMotionTests.swift
//  MosTests
//
//  The maths of the demo at the top of the Scrolling tab: where the little page is after
//  a script of wheel clicks (ScrollPreviewMotion) and the loop the demo plays
//  (ScrollPreviewLoop). The page must move as the scroll engine moves a real one.
//

import XCTest
@testable import Mos_Debug

final class ScrollPreviewMotionTests: XCTestCase {

    private typealias Motion = ScrollPreviewMotion
    private typealias Loop = ScrollPreviewLoop
    private typealias Click = ScrollPreviewMotion.Click

    /// Three clicks towards the hand, 150 ms apart.
    private let burst = [Click(time: 0.1, turn: 1), Click(time: 0.25, turn: 1), Click(time: 0.4, turn: 1)]

    private func scene(
        _ emphasis: ScrollPreviewView.Emphasis = .wheel, smoothing: Bool = true,
        duration: Double = 3.67, speed: Double = 2.7, reversed: Bool = false
    ) -> ScrollPreviewView.Scene {
        var scene = ScrollPreviewView.Scene()
        scene.emphasis = emphasis
        scene.smoothing = smoothing
        scene.duration = duration
        scene.speed = speed
        scene.reversed = reversed
        return scene
    }

    /// Demo points one click moves the page at `speed`.
    private func points(perClickAt speed: Double) -> Double {
        return 33.6 * speed * Motion.pointsPerPixel
    }

    /// When the motion has covered `fraction` of its way.
    private func time(toCover fraction: Double, of motion: Motion) -> Double {
        var time = 0.0
        while time < motion.settleTime, abs(motion.value(at: time) - motion.start) < fraction * abs(motion.end - motion.start) {
            time += 0.001
        }
        return time
    }

    private func assertSame(
        _ a: ScrollPreviewLoop.Frame, _ b: ScrollPreviewLoop.Frame, _ message: String = "",
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(Double(a.offset.x), Double(b.offset.x), accuracy: 1e-6, message, file: file, line: line)
        XCTAssertEqual(Double(a.offset.y), Double(b.offset.y), accuracy: 1e-6, message, file: file, line: line)
        XCTAssertEqual(a.wheelTurn, b.wheelTurn, accuracy: 1e-6, message, file: file, line: line)
        XCTAssertEqual(a.pulse, b.pulse, accuracy: 1e-6, message, file: file, line: line)
        XCTAssertEqual(a.keyDepth, b.keyDepth, accuracy: 1e-6, message, file: file, line: line)
        XCTAssertEqual(a.isAtRest, b.isAtRest, message, file: file, line: line)
    }

    private var allScenes: [ScrollPreviewView.Scene] {
        var scenes: [ScrollPreviewView.Scene] = []
        for emphasis in [ScrollPreviewView.Emphasis.wheel, .faster, .sideways, .paused] {
            for smoothing in [true, false] {
                for reversed in [false, true] {
                    for speed in [1.0, 2.7, 10.0] {
                        for duration in [0.0, 3.67, 5.0] {
                            scenes.append(scene(emphasis, smoothing: smoothing, duration: duration, speed: speed, reversed: reversed))
                        }
                    }
                }
            }
        }
        return scenes
    }

    // MARK: - The scale

    func testTheDefaultSceneIsTheDefaultFeel() {
        let scene = ScrollPreviewView.Scene()
        XCTAssertTrue(scene.smoothing)
        XCTAssertEqual(scene.duration, 3.67)
        XCTAssertEqual(scene.speed, 2.7)
        XCTAssertFalse(scene.reversed)
        XCTAssertEqual(scene.emphasis, .wheel)
    }

    /// One click is 33.6 × speed real pixels, shown at a fixed scale.
    func testAClickIsTheEnginesStepTimesTheSpeed() {
        XCTAssertEqual(Motion.clickDistance(for: scene(speed: 1)), 33.6, accuracy: 1e-12)
        XCTAssertEqual(Motion.clickDistance(for: scene(speed: 2.7)), 90.72, accuracy: 1e-12)
        XCTAssertEqual(Motion.clickDistance(for: scene(speed: 10)), 336, accuracy: 1e-12)
        let motion = Motion(scene: scene(speed: 2.7), clicks: [Click(time: 0.1, turn: 1)])
        XCTAssertEqual(motion.end, 90.72 * Motion.pointsPerPixel, accuracy: 1e-9)
    }

    /// The scale leaves both ends of the Speed slider readable: a burst moves the page a
    /// clearly visible distance at speed 1 and still fits into the page at speed 10.
    func testSpeedOneAndSpeedTenAreBothReadable() {
        let slow = Motion(scene: scene(speed: 1), clicks: burst)
        let fast = Motion(scene: scene(speed: 10), clicks: burst)
        XCTAssertGreaterThanOrEqual(slow.end, 6)
        XCTAssertLessThan(fast.end, Motion.travel)
        XCTAssertEqual(fast.end, 10 * slow.end, accuracy: 1e-9)
    }

    func testAHigherSpeedMovesFarther() {
        var last = 0.0
        for speed in [1.0, 2.0, 2.7, 5.0, 7.5, 10.0] {
            let motion = Motion(scene: scene(speed: speed), clicks: burst)
            XCTAssertEqual(motion.end, 3 * points(perClickAt: speed), accuracy: 1e-9, "speed \(speed)")
            XCTAssertGreaterThan(motion.end, last, "speed \(speed)")
            last = motion.end
        }
    }

    // MARK: - Smoothing

    func testALongerDurationLandsLater() {
        var lastSettle = 0.0
        for duration in [1.0, 2.0, 3.0, 3.67, 4.35, 5.0] {
            let motion = Motion(scene: scene(duration: duration), clicks: burst)
            XCTAssertEqual(motion.end, 3 * points(perClickAt: 2.7), accuracy: 1e-9, "the distance does not depend on the duration")
            XCTAssertGreaterThan(motion.settleTime, lastSettle, "duration \(duration)")
            lastSettle = motion.settleTime
        }
        // On the way, the shorter duration is ahead.
        let short = Motion(scene: scene(duration: 2), clicks: burst)
        let long = Motion(scene: scene(duration: 4.5), clicks: burst)
        for time in stride(from: 0.15, through: 1.0, by: 0.05) {
            XCTAssertGreaterThan(short.value(at: time), long.value(at: time), "at \(time) s")
        }
    }

    /// Frame by frame what ScrollPoster does: the target takes the clicks, the position
    /// goes the Duration factor of the way there, the filter rounds the step off.
    func testTheEasedPageFollowsTheEnginesFrameRecipe() {
        for duration in [1.0, 3.67, 4.35] {
            let scene = self.scene(duration: duration)
            let motion = Motion(scene: scene, clicks: burst)
            let interval = Motion.frameInterval
            let factor = OPTIONS_SCROLL_DEFAULT.generateDurationTransition(with: duration)
            let transition = ScrollMotion.transition(factor, frameInterval: interval)
            let weight = ScrollMotion.transition(ScrollMotion.filterWeight(forTransition: factor), frameInterval: interval)
            let filter = ScrollFilter()
            var target = 0.0, position = 0.0, offset = 0.0
            var frame = 0
            while Double(frame + 1) * interval < motion.settleTime {
                frame += 1
                let time = Double(frame) * interval
                target = Double(burst.filter { $0.time <= time }.count) * 90.72
                let step = (target - position) * transition
                position += step
                offset += filter.fill(with: (y: step, x: 0), weight: weight).y * Motion.pointsPerPixel
                XCTAssertEqual(motion.value(at: time), offset, accuracy: 1e-9, "duration \(duration), frame \(frame)")
            }
            XCTAssertGreaterThan(frame, 30)
        }
    }

    /// The demo steps at 120 Hz; a 60 Hz display, where the engine's factors apply as they
    /// are, shows the same curve: half-way and nine tenths are reached within one frame.
    func testTheEasedPageKeepsTheEnginesTimingAtSixtyHertz() {
        for duration in [2.5, 3.67, 4.35] {
            let scene = self.scene(duration: duration)
            let motion = Motion(scene: scene, clicks: burst)
            let factor = OPTIONS_SCROLL_DEFAULT.generateDurationTransition(with: duration)
            let weight = ScrollMotion.filterWeight(forTransition: factor)
            let filter = ScrollFilter()
            var target = 0.0, position = 0.0, offset = 0.0
            var reached: [Double: Double] = [:]
            for frame in 1...600 {
                let time = Double(frame) / 60
                target = Double(burst.filter { $0.time <= time }.count) * 90.72
                let step = (target - position) * factor
                position += step
                offset += filter.fill(with: (y: step, x: 0), weight: weight).y * Motion.pointsPerPixel
                for fraction in [0.5, 0.9] where reached[fraction] == nil && offset >= fraction * motion.end {
                    reached[fraction] = time
                }
            }
            for fraction in [0.5, 0.9] {
                guard let engine = reached[fraction] else {
                    XCTFail("the engine never covered \(fraction) at duration \(duration)")
                    continue
                }
                XCTAssertEqual(time(toCover: fraction, of: motion), engine, accuracy: 1.0 / 60, "duration \(duration), \(fraction)")
            }
        }
    }

    func testTheEasedPageNeverJumpsAndNeverTurnsBack() {
        let motion = Motion(scene: scene(), clicks: burst)
        let click = points(perClickAt: 2.7)
        var last = motion.value(at: 0)
        for frame in 1...Int(motion.settleTime * 240) + 10 {
            let value = motion.value(at: Double(frame) / 240)
            XCTAssertGreaterThanOrEqual(value, last - 1e-12)
            XCTAssertLessThan(value - last, click / 4, "more than a quarter click in 4 ms at \(Double(frame) / 240) s")
            last = value
        }
        XCTAssertEqual(last, motion.end, accuracy: 1e-12)
    }

    func testDurationZeroLandsAtOnce() {
        let motion = Motion(scene: scene(duration: 0), clicks: burst)
        XCTAssertEqual(motion.settleTime, 0.4, accuracy: 2 * Motion.frameInterval)
        XCTAssertEqual(motion.end, 3 * points(perClickAt: 2.7), accuracy: 1e-9)
    }

    func testADurationOutsideTheSliderIsClamped() {
        let longest = Motion(scene: scene(duration: 5), clicks: burst)
        let beyond = Motion(scene: scene(duration: 9), clicks: burst)
        XCTAssertEqual(beyond.settleTime, longest.settleTime)
        XCTAssertEqual(beyond.end, longest.end)
        XCTAssertEqual(Motion(scene: scene(duration: -3), clicks: burst).settleTime, Motion(scene: scene(duration: 0), clicks: burst).settleTime)
        let nonsense = Motion(scene: scene(duration: .nan, speed: .infinity), clicks: burst)
        XCTAssertTrue(nonsense.settleTime.isFinite)
        XCTAssertTrue(nonsense.end.isFinite)
    }

    // MARK: - Jumps

    func testSmoothingOffJumpsExactlyOneClickPerClick() {
        let motion = Motion(scene: scene(smoothing: false), clicks: burst)
        let click = points(perClickAt: 2.7)
        XCTAssertEqual(motion.value(at: 0.099), 0)
        XCTAssertEqual(motion.value(at: 0.1), click, accuracy: 1e-12)
        XCTAssertEqual(motion.value(at: 0.249), click, accuracy: 1e-12)
        XCTAssertEqual(motion.value(at: 0.25), 2 * click, accuracy: 1e-12)
        XCTAssertEqual(motion.value(at: 0.399), 2 * click, accuracy: 1e-12)
        XCTAssertEqual(motion.value(at: 0.4), 3 * click, accuracy: 1e-12)
        XCTAssertEqual(motion.value(at: 5), 3 * click, accuracy: 1e-12)
        XCTAssertEqual(motion.settleTime, 0.4)
        XCTAssertEqual(motion.end, 3 * click, accuracy: 1e-12)
    }

    /// The pause key holds smoothing off: the page jumps although smoothing is on.
    func testPausedJumpsLikeSmoothingOff() {
        let paused = Motion(scene: scene(.paused), clicks: burst)
        let off = Motion(scene: scene(smoothing: false), clicks: burst)
        for time in stride(from: 0.0, through: 1.0, by: 0.01) {
            XCTAssertEqual(paused.value(at: time), off.value(at: time), "at \(time) s")
        }
        XCTAssertFalse(Motion.isEased(scene(.paused)))
        XCTAssertFalse(Motion.isEased(scene(smoothing: false)))
        XCTAssertTrue(Motion.isEased(scene(.faster)))
    }

    // MARK: - The keys

    func testFasterCoversFiveTimesTheDistance() {
        let one = [Click(time: 0.1, turn: 1)]
        let plain = Motion(scene: scene(), clicks: one)
        let faster = Motion(scene: scene(.faster), clicks: one)
        XCTAssertEqual(faster.end, 5 * plain.end, accuracy: 1e-9)

        // A whole burst at the default speed still fits into the page…
        let burstPlain = Motion(scene: scene(), clicks: burst)
        let burstFaster = Motion(scene: scene(.faster), clicks: burst)
        XCTAssertEqual(burstFaster.end, 5 * burstPlain.end, accuracy: 1e-9)
        XCTAssertLessThan(burstFaster.end, Motion.travel)
        // …and at a high speed it stops at the end of the page.
        XCTAssertEqual(Motion(scene: scene(.faster, speed: 10), clicks: burst).end, Motion.travel)
    }

    /// The key multiplies smoothed scrolling only: unsmoothed events pass the engine untouched.
    func testFasterNeedsSmoothing() {
        let off = Motion(scene: scene(.faster, smoothing: false), clicks: burst)
        XCTAssertEqual(off.end, 3 * points(perClickAt: 2.7), accuracy: 1e-12)
    }

    func testSidewaysMovesOnlyX() {
        let sideways = Motion(scene: scene(.sideways), clicks: burst)
        let down = Motion(scene: scene(), clicks: burst)
        for time in stride(from: 0.0, through: 2.0, by: 0.01) {
            let across = sideways.offset(at: time)
            XCTAssertEqual(across.y, 0, "at \(time) s")
            XCTAssertEqual(Double(across.x), down.value(at: time), accuracy: 1e-12, "the same motion on the other axis")
            XCTAssertEqual(down.offset(at: time).x, 0, "at \(time) s")
        }
        XCTAssertGreaterThan(sideways.offset(at: 2).x, 0)
        for emphasis in [ScrollPreviewView.Emphasis.wheel, .faster, .paused] {
            let offset = Motion(scene: scene(emphasis), clicks: burst).offset(at: 2)
            XCTAssertEqual(offset.x, 0)
            XCTAssertGreaterThan(offset.y, 0)
        }
    }

    // MARK: - Direction

    func testReversedGoesTheOtherWayForTheSameTurn() {
        let middle = Motion.travel / 2
        let plain = Motion(scene: scene(), clicks: burst, start: middle)
        let reversed = Motion(scene: scene(reversed: true), clicks: burst, start: middle)
        for time in stride(from: 0.0, through: 2.0, by: 0.01) {
            XCTAssertEqual(reversed.value(at: time) - middle, -(plain.value(at: time) - middle), accuracy: 1e-9, "at \(time) s")
        }
        XCTAssertGreaterThan(plain.end, middle)
        XCTAssertLessThan(reversed.end, middle)
        XCTAssertEqual(Motion.clickDistance(for: scene(reversed: true)), -90.72, accuracy: 1e-12)
    }

    func testAClickAwayFromTheHandGoesBack() {
        let towards = Motion(scene: scene(), clicks: [Click(time: 0.1, turn: 1)], start: 50)
        let away = Motion(scene: scene(), clicks: [Click(time: 0.1, turn: -1)], start: 50)
        XCTAssertEqual(towards.end - 50, 50 - away.end, accuracy: 1e-9)
        XCTAssertGreaterThan(towards.end, 50)
    }

    /// Without a given start the page rests at the end that leaves room for the first click.
    func testThePageStartsWhereTheFirstClickHasRoom() {
        XCTAssertEqual(Motion(scene: scene(), clicks: burst).start, 0)
        XCTAssertEqual(Motion(scene: scene(reversed: true), clicks: burst).start, Motion.travel)
        XCTAssertEqual(Motion(scene: scene(), clicks: [Click(time: 0, turn: -1)]).start, Motion.travel)
        XCTAssertEqual(Motion(scene: scene(reversed: true), clicks: burst).end, Motion.travel - 3 * points(perClickAt: 2.7), accuracy: 1e-9)
        XCTAssertEqual(Motion(scene: scene(), clicks: []).end, 0)
    }

    // MARK: - The ends of the page

    func testTheOffsetAlwaysStaysInsideTheContent() {
        let scripts: [[Click]] = [
            burst,
            (0..<12).map { Click(time: 0.1 + Double($0) * 0.05, turn: 1) },
            (0..<12).map { Click(time: 0.1 + Double($0) * 0.08, turn: $0 < 6 ? -1 : 1) },
            (0..<8).map { Click(time: 0.1 + Double($0) * 0.3, turn: $0 % 2 == 0 ? 1 : -1) },
        ]
        let range = 0.0...Motion.travel
        for scene in allScenes {
            for script in scripts {
                for start in [nil, 0, 31.5, Motion.travel, -20, 500] as [Double?] {
                    let motion = Motion(scene: scene, clicks: script, start: start)
                    XCTAssertTrue(range.contains(motion.start) && range.contains(motion.end), "\(scene)")
                    var time = 0.0
                    while time < motion.settleTime + 0.5 {
                        let offset = motion.offset(at: time)
                        guard range.contains(Double(offset.x)), range.contains(Double(offset.y)) else {
                            return XCTFail("\(offset) at \(time) s, \(scene), start \(String(describing: start))")
                        }
                        time += 1.0 / 60
                    }
                }
            }
        }
    }

    func testThePageStopsAtItsEnd() {
        let motion = Motion(scene: scene(speed: 10), clicks: (0..<8).map { Click(time: 0.1 + Double($0) * 0.1, turn: 1) })
        XCTAssertEqual(motion.end, Motion.travel)
        XCTAssertEqual(motion.value(at: motion.settleTime + 1), Motion.travel)
        XCTAssertLessThan(motion.value(at: 0.15), Motion.travel)
    }

    // MARK: - The loop

    func testTheLoopIsABurstOutARestAndTheSameBurstBack() {
        let loop = Loop(scene: scene())
        XCTAssertEqual(loop.out.clicks.count, 3)
        XCTAssertEqual(loop.out.clicks.map { $0.turn }, [1, 1, 1])
        XCTAssertEqual(loop.back.clicks.map { $0.turn }, [-1, -1, -1])
        XCTAssertEqual(loop.out.clicks.map { $0.time }, loop.back.clicks.map { $0.time })
        XCTAssertEqual(loop.out.clicks[1].time - loop.out.clicks[0].time, 0.15, accuracy: 1e-12)
        XCTAssertEqual(loop.out.clicks[2].time - loop.out.clicks[1].time, 0.15, accuracy: 1e-12)
        // About a second of rest once the page has arrived, each way.
        XCTAssertEqual(loop.outLength - loop.out.settleTime, 1.0, accuracy: 1e-9)
        XCTAssertEqual(loop.length - loop.outLength - loop.back.settleTime, 1.0, accuracy: 1e-9)
        XCTAssertEqual(loop.back.start, loop.out.end)
    }

    func testALongerDurationMakesALongerLoop() {
        XCTAssertGreaterThan(Loop(scene: scene(duration: 4.35)).length, Loop(scene: scene(duration: 2)).length)
        // A page that jumps rests from the last click (and the release of the key) on.
        let jumping = Loop(scene: scene(smoothing: false))
        XCTAssertGreaterThanOrEqual(jumping.outLength, jumping.out.settleTime + 1.0)
        XCTAssertLessThan(jumping.outLength, 3)
    }

    func testTheLoopReturnsToItsStart() {
        for scene in allScenes {
            let loop = Loop(scene: scene)
            let first = loop.frame(at: 0)
            let last = loop.frame(at: loop.length - 1e-6)
            XCTAssertEqual(Double(last.offset.x), Double(first.offset.x), accuracy: 1e-9, "\(scene)")
            XCTAssertEqual(Double(last.offset.y), Double(first.offset.y), accuracy: 1e-9, "\(scene)")
            XCTAssertEqual(loop.back.end, loop.out.start, accuracy: 1e-9, "\(scene)")
            XCTAssertEqual(last.wheelTurn, 0, accuracy: 1e-9)
            XCTAssertEqual(last.pulse, 0)
            XCTAssertEqual(last.keyDepth, 0)
            XCTAssertTrue(last.isAtRest)
            XCTAssertTrue(first.isAtRest)
            // It moved in between, and the frames repeat from one round to the next
            // (looked at between two clicks: at the instant of a click the flash jumps).
            XCTAssertNotEqual(loop.frame(at: loop.outLength - 0.01).offset, first.offset, "\(scene)")
            let between = Loop.leadIn + 1.5 * Loop.clickInterval
            assertSame(loop.frame(at: loop.length + between), loop.frame(at: between), "\(scene)")
            assertSame(loop.frame(at: 3 * loop.length + loop.outLength + between), loop.frame(at: loop.outLength + between), "\(scene)")
        }
    }

    func testTheLoopStaysInsideTheContentAndRestsBetweenTheBursts() {
        let range = 0.0...Motion.travel
        for scene in allScenes {
            let loop = Loop(scene: scene)
            var time = 0.0
            while time < loop.length {
                let frame = loop.frame(at: time)
                XCTAssertTrue(range.contains(Double(frame.offset.x)) && range.contains(Double(frame.offset.y)), "\(scene) at \(time) s")
                XCTAssertTrue((0.0...1.0).contains(frame.pulse) && (0.0...1.0).contains(frame.keyDepth))
                time += 1.0 / 30
            }
            let arrived = loop.frame(at: loop.out.settleTime + 0.01)
            let beforeBack = loop.frame(at: loop.outLength - 0.01)
            XCTAssertTrue(arrived.isAtRest)
            XCTAssertEqual(arrived.offset, beforeBack.offset, "\(scene)")
        }
    }

    /// The wheel turns one way out and the other way back, whatever the page does with it.
    func testTheWheelTurnsWithTheClicks() {
        let loop = Loop(scene: scene())
        let first = Loop.leadIn
        XCTAssertEqual(loop.frame(at: first - 0.01).wheelTurn, 0)
        XCTAssertEqual(loop.frame(at: first - 0.01).pulse, 0)
        XCTAssertEqual(loop.frame(at: first).pulse, 1, accuracy: 1e-9)
        let turning = loop.frame(at: first + Loop.tickDuration / 3).wheelTurn
        XCTAssertGreaterThan(turning, 0)
        XCTAssertLessThan(turning, 1)
        XCTAssertEqual(loop.frame(at: first + Loop.tickDuration).wheelTurn, 1, accuracy: 1e-9)
        XCTAssertEqual(loop.frame(at: Loop.lastClickTime + Loop.tickDuration).wheelTurn, 3, accuracy: 1e-9)
        XCTAssertEqual(loop.frame(at: loop.outLength - 0.01).wheelTurn, 3, accuracy: 1e-9)
        XCTAssertEqual(loop.frame(at: loop.outLength + first + Loop.tickDuration).wheelTurn, 2, accuracy: 1e-9)
        XCTAssertEqual(loop.frame(at: loop.outLength + Loop.lastClickTime + Loop.tickDuration).wheelTurn, 0, accuracy: 1e-9)

        let reversed = Loop(scene: scene(reversed: true))
        XCTAssertEqual(reversed.length, loop.length, accuracy: 1e-9)
        for time in stride(from: 0.0, through: loop.length, by: 0.05) {
            XCTAssertEqual(reversed.frame(at: time).wheelTurn, loop.frame(at: time).wheelTurn, accuracy: 1e-9, "at \(time) s")
        }
        // The same turn, the page the other way: down from the top, or up from the bottom.
        XCTAssertEqual(loop.frame(at: 0).offset.y, 0)
        XCTAssertGreaterThan(loop.frame(at: loop.outLength - 0.01).offset.y, 0)
        XCTAssertEqual(Double(reversed.frame(at: 0).offset.y), Motion.travel)
        XCTAssertLessThan(Double(reversed.frame(at: reversed.outLength - 0.01).offset.y), Motion.travel)
    }

    func testTheKeyIsHeldWhileTheWheelTurns() {
        for emphasis in [ScrollPreviewView.Emphasis.faster, .sideways, .paused] {
            let loop = Loop(scene: scene(emphasis))
            XCTAssertTrue(Loop.showsKey(loop.scene))
            XCTAssertEqual(loop.frame(at: 0).keyDepth, 0)
            for leg in [0, loop.outLength] {
                for click in loop.out.clicks {
                    XCTAssertEqual(loop.frame(at: leg + click.time).keyDepth, 1, accuracy: 1e-9, "\(emphasis)")
                }
                XCTAssertEqual(loop.frame(at: leg + Loop.leadIn - 0.02).keyDepth, 1, accuracy: 1e-9, "pressed before the first click")
                XCTAssertEqual(loop.frame(at: leg + Loop.lastClickTime + Loop.keyHold + Loop.keyTravel + 0.01).keyDepth, 0, accuracy: 1e-9, "let go after the last")
            }
        }
        let plain = Loop(scene: scene())
        XCTAssertFalse(Loop.showsKey(plain.scene))
        for time in stride(from: 0.0, through: plain.length, by: 0.05) {
            XCTAssertEqual(plain.frame(at: time).keyDepth, 0)
        }
    }

    /// Reduce Motion: the page half-way, the wheel still, the key (if any) held.
    func testTheStillFrame() {
        let plain = Loop(scene: scene()).stillFrame
        XCTAssertEqual(plain.offset, CGPoint(x: 0, y: Motion.travel / 2))
        XCTAssertEqual(plain.wheelTurn, 0)
        XCTAssertEqual(plain.pulse, 0)
        XCTAssertEqual(plain.keyDepth, 0)
        XCTAssertTrue(plain.isAtRest)

        let sideways = Loop(scene: scene(.sideways)).stillFrame
        XCTAssertEqual(sideways.offset, CGPoint(x: Motion.travel / 2, y: 0))
        XCTAssertEqual(sideways.keyDepth, 1)
        XCTAssertEqual(Loop(scene: scene(.faster)).stillFrame.keyDepth, 1)
        XCTAssertEqual(Loop(scene: scene(.paused)).stillFrame.keyDepth, 1)
    }
}
