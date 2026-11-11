//
//  ScrollMomentumTests.swift
//  MosTests
//
//  Magic Mouse-style momentum: the decay curve, the glide after a flick, when there is no
//  glide (single notch, slow scrolling, free-spin, modifiers), the reverse-tick stop, the
//  gesture phases and whole-pixel posting.
//
//  The poster tests feed wheel events the way ScrollCore does (spin tracker → tuning →
//  poster input) and record the frames instead of posting them.
//

import XCTest
@testable import Mos_Debug

// MARK: - Rig

/// A poster with its own phase machine and dispatch context, driven by a simulated clock.
/// Nothing is posted: frames go to the recorder.
final class ScrollMomentumRig {

    struct Recorded {
        let time: Double
        let frame: ScrollOutgoingFrame
    }

    let poster: ScrollPoster
    let phases = ScrollPhase()
    var tracker = ScrollSpinTracker()

    var tuning: ScrollTuningSettings
    var step: Double
    var speed: Double
    var duration: Double
    var simulateTrackpad: Bool
    var modifiersHeld = false

    let frameInterval: Double
    /// Arbitrary start; must be > 0 (0 means "no event yet" in the poster).
    let start = 100.0
    private(set) var now: Double
    private var nextFrame: Double
    private(set) var isRunning = false

    private(set) var recorded: [Recorded] = []
    /// Phase each stop was made with, and when.
    private(set) var stops: [(time: Double, phase: Phase)] = []
    /// Float distance of the finished gestures plus the one in progress (ScrollPoster's `current`).
    private var finishedFloatTotal = 0.0
    private var runningFloatTotal = 0.0

    init(preset: ScrollPreset = .magicMouse, rate: Double = 60) {
        let values = preset.values
        tuning = values.tuning
        step = values.step
        speed = values.speed
        duration = values.duration
        simulateTrackpad = values.simulateTrackpad
        frameInterval = 1 / rate
        now = start
        nextFrame = start + frameInterval
        poster = ScrollPoster(phases: phases, dispatchContext: ScrollDispatchContext())
        poster.frameRecorderForTests = { [unowned self] frame in
            self.recorded.append(Recorded(time: self.now, frame: frame))
        }
        poster.setConfigForTests(simTrackpadEnabled: simulateTrackpad)
    }

    /// px one line scrolls outside free-spin.
    var notch: Double { return step * speed }

    private var transition: Double {
        return OPTIONS_SCROLL_DEFAULT.generateDurationTransition(with: duration)
    }

    /// Runs the display frames due up to `time` (seconds after `start`).
    func run(until time: Double) {
        let target = start + time
        while nextFrame <= target + 1e-9 {
            now = nextFrame
            nextFrame += frameInterval
            guard isRunning else { continue }
            let stopPhase = poster.frameForTests(frameInterval: frameInterval, now: now)
            runningFloatTotal = abs(poster.motionStateForTests.current.y) + abs(poster.motionStateForTests.current.x)
            if let stopPhase = stopPhase {
                poster.stop(stopPhase)
                stops.append((now - start, stopPhase))
                finishedFloatTotal += runningFloatTotal
                runningFloatTotal = 0
                isRunning = false
            }
        }
        now = target
    }

    /// One vertical wheel event of `lines` lines at `time`, resolved as ScrollCore does.
    func wheel(lines: Double, at time: Double) {
        run(until: time)
        let spin = tracker.register(lines: lines, at: start + time)
        let horizontal = tuning.resolve(speed: speed, durationTransition: transition, spin: .idle)
        let vertical = tuning.resolve(speed: speed, durationTransition: transition, spin: spin)
        // A line-mode wheel reports 10 px per line; ScrollCore raises it to at least one step.
        let regular = max(step, abs(lines) * 10) * (lines < 0 ? -1 : 1)
        let y = vertical.verticalDistance(regular: regular, lines: lines, step: step)
        let input = ScrollCore.posterInput(
            y: y, x: 0, step: step, vertical: vertical, horizontal: horizontal,
            spin: spin, momentum: tuning.momentum, modifiersHeld: modifiersHeld
        )
        send(input, at: start + time)
    }

    /// One thumb wheel event of `lines` lines at `time`.
    func thumbWheel(lines: Double, at time: Double, flags: CGEventFlags = []) {
        run(until: time)
        let horizontal = tuning.resolve(speed: speed, durationTransition: transition, spin: .idle)
        let x = max(step, abs(lines) * 10) * (lines < 0 ? -1 : 1)
        let input = ScrollCore.posterInput(
            y: 0, x: x, step: step, vertical: horizontal, horizontal: horizontal,
            momentum: tuning.momentum, modifiersHeld: modifiersHeld,
            pageSwipe: ScrollCore.isPageSwipe(
                action: tuning.horizontalWheelAction, y: 0, x: x, flags: flags, toggleScroll: false
            )
        )
        send(input, at: start + time)
    }

    private func send(_ input: ScrollPosterInput, at eventTime: Double) {
        now = eventTime
        poster.inputForTests(input, at: eventTime)
        isRunning = true
    }

    // MARK: Results

    /// Frames that move the page.
    var moving: [Recorded] { return recorded.filter { $0.frame.y != 0 || $0.frame.x != 0 } }
    var pixelsY: Double { return recorded.reduce(0) { $0 + $1.frame.y } }
    var pixelsX: Double { return recorded.reduce(0) { $0 + $1.frame.x } }
    var floatTotal: Double { return finishedFloatTotal + runningFloatTotal }
    /// Time (after `start`) of the last frame that moved the page.
    var lastMovement: Double { return (moving.last?.time ?? start) - start }
    /// Vertical pixels of every frame that moved the page vertically, with its time after `start`.
    var movementY: [(time: Double, pixels: Double)] {
        return recorded.filter { $0.frame.y != 0 }.map { ($0.time - start, $0.frame.y) }
    }
    /// Longest time between two consecutive frames with vertical movement.
    var longestPauseY: Double {
        let times = movementY.map { $0.time }
        return zip(times.dropFirst(), times).map { $0 - $1 }.max() ?? 0
    }
    func pixelsY(until time: Double) -> Double {
        return recorded.filter { $0.time <= start + time + 1e-9 }.reduce(0) { $0 + $1.frame.y }
    }

    /// (scroll phase, momentum phase) of every frame that carries phases, without repeats.
    var phaseSequence: [String] {
        var names: [String] = []
        for item in recorded {
            guard let scroll = item.frame.scrollPhase, let momentum = item.frame.momentumPhase else { continue }
            let name = Self.phaseName(scroll: scroll, momentum: momentum)
            if names.last != name { names.append(name) }
        }
        return names
    }

    var hasMomentumPhase: Bool {
        return recorded.contains { ($0.frame.momentumPhase ?? 0) != 0 }
    }

    static func phaseName(scroll: Double, momentum: Double) -> String {
        switch (scroll, momentum) {
        case (1, 0): return "began"
        case (2, 0): return "changed"
        case (4, 0): return "ended"
        case (8, 0): return "cancelled"
        case (128, 0): return "mayBegin"
        case (0, 1): return "momentumBegan"
        case (0, 2): return "momentumChanged"
        case (0, 3): return "momentumEnded"
        default: return "(\(scroll),\(momentum))"
        }
    }
}

// MARK: - The curve

final class ScrollMomentumTests: XCTestCase {

    private let settings = ScrollMomentumSettings.default

    /// Distance and duration of a glide from `speed` px/s at `rate` Hz, and the position at
    /// each multiple of 0.25 s (a whole number of frames at 60, 120 and 144 Hz).
    private func glide(from speed: Double, rate: Double) -> (distance: Double, duration: Double, samples: [Double]) {
        var momentum = ScrollMomentum()
        momentum.seed(inputSpeed: speed, direction: 1, lineRate: 100, settings: settings)
        let dt = 1 / rate
        var distance = 0.0
        var samples: [Double] = []
        var endedAt: Double?
        let framesPerSample = Int((rate / 4).rounded())
        for frame in 1...Int((3 * rate).rounded()) {
            distance += momentum.advance(interval: dt, settings: settings)
            if endedAt == nil && !momentum.isActive { endedAt = Double(frame) * dt }
            if frame % framesPerSample == 0 { samples.append(distance) }
        }
        return (distance, endedAt ?? .infinity, samples)
    }

    func testDecay_isTheSameAt60And120And144Hz() {
        for speed in [400.0, 1200, 6000] {
            let at60 = glide(from: speed, rate: 60)
            let at120 = glide(from: speed, rate: 120)
            let at144 = glide(from: speed, rate: 144)
            XCTAssertEqual(at120.distance, at60.distance, accuracy: 1e-6, "distance from \(speed)")
            XCTAssertEqual(at144.distance, at60.distance, accuracy: 1e-6, "distance from \(speed)")
            // The glide ends at the same moment; each rate notices it on its next frame.
            XCTAssertEqual(at120.duration, at60.duration, accuracy: 1.0 / 60.0, "duration from \(speed)")
            XCTAssertEqual(at144.duration, at60.duration, accuracy: 1.0 / 60.0, "duration from \(speed)")
            // Not only the end: the position along the way is the same too.
            XCTAssertEqual(at60.samples.count, 12)
            XCTAssertEqual(at120.samples.count, 12)
            XCTAssertEqual(at144.samples.count, 12)
            for (index, position) in at60.samples.enumerated() where at120.samples.count == 12 && at144.samples.count == 12 {
                XCTAssertEqual(at120.samples[index], position, accuracy: 1e-6, "from \(speed) at \(Double(index + 1) / 4) s")
                XCTAssertEqual(at144.samples[index], position, accuracy: 1e-6, "from \(speed) at \(Double(index + 1) / 4) s")
            }
            XCTAssertLessThan(at60.samples[0], at60.distance, "still gliding at 0.25 s")
        }
    }

    func testDecay_frameSplitDoesNotMatter() {
        var whole = ScrollMomentum()
        var split = ScrollMomentum()
        whole.seed(inputSpeed: 2000, direction: -1, lineRate: 100, settings: settings)
        split.seed(inputSpeed: 2000, direction: -1, lineRate: 100, settings: settings)
        let a = whole.advance(interval: 0.05, settings: settings)
        let b = split.advance(interval: 0.013, settings: settings)
            + split.advance(interval: 0.0005, settings: settings)
            + split.advance(interval: 0.0365, settings: settings)
        XCTAssertEqual(a, b, accuracy: 1e-9)
        XCTAssertEqual(whole.velocity, split.velocity, accuracy: 1e-9)
        XCTAssertLessThan(a, 0, "the glide keeps the direction of the wheel")
    }

    func testCoast_distanceAndDurationFromAKnownSpeed() {
        // WebKit's curve from 1200 px/s: about 330 px in 0.8 s.
        let result = glide(from: 1200, rate: 60)
        XCTAssertEqual(result.distance, 328, accuracy: 10)
        XCTAssertEqual(result.duration, 0.80, accuracy: 0.05)
        // Faster flicks glide farther but not much longer.
        let fast = glide(from: 6000, rate: 60)
        XCTAssertEqual(fast.distance, 1830, accuracy: 60)
        XCTAssertEqual(fast.duration, 1.30, accuracy: 0.05)
    }

    func testDecay_twoStages() {
        XCTAssertEqual(ScrollMomentum.decay(speed: 1000, settings: settings), 0.975, accuracy: 1e-12)
        XCTAssertEqual(ScrollMomentum.decay(speed: 250, settings: settings), 0.975, accuracy: 1e-12)
        XCTAssertEqual(ScrollMomentum.decay(speed: 125, settings: settings), 0.9425, accuracy: 1e-12, "half way into the tail")
        XCTAssertEqual(ScrollMomentum.decay(speed: -125, settings: settings), 0.9425, accuracy: 1e-12)
        XCTAssertEqual(ScrollMomentum.decay(speed: 0, settings: settings), 0.91, accuracy: 1e-12)
        XCTAssertEqual(ScrollMomentum.stopSpeed(settings: settings), 30, "0.5 px per 60 Hz frame")
        // 0.975 per 8 ms is a time constant of about 316 ms.
        XCTAssertEqual(-ScrollMomentum.curveStep / log(settings.decayPer8ms), 0.316, accuracy: 0.001)
    }

    func testFlingGain_keepsSlowScrollingExact() {
        XCTAssertEqual(ScrollMomentum.flingGain(lineRate: 0, settings: settings), 0)
        XCTAssertEqual(ScrollMomentum.flingGain(lineRate: 4, settings: settings), 0)
        XCTAssertEqual(ScrollMomentum.flingGain(lineRate: 8, settings: settings), 0)
        XCTAssertEqual(ScrollMomentum.flingGain(lineRate: 12, settings: settings), 0.5, accuracy: 1e-12)
        XCTAssertEqual(ScrollMomentum.flingGain(lineRate: 16, settings: settings), 1)
        XCTAssertEqual(ScrollMomentum.flingGain(lineRate: 100, settings: settings), 1)
        XCTAssertEqual(ScrollMomentum.flingGain(lineRate: .nan, settings: settings), 0)
    }

    func testSeed_scalesWithSpeedGainAndDirection() {
        var momentum = ScrollMomentum()
        momentum.seed(inputSpeed: 1000, direction: -60, lineRate: 12, settings: settings)
        XCTAssertEqual(momentum.velocity, -500, accuracy: 1e-9, "half the fling gain at 12 lines/s")

        momentum.seed(inputSpeed: 1000, direction: 60, lineRate: 6, settings: settings)
        XCTAssertFalse(momentum.isActive, "below the fling range there is no glide")

        var doubled = settings
        doubled.coastGain = 2
        momentum.seed(inputSpeed: 1000, direction: 1, lineRate: 20, settings: doubled)
        XCTAssertEqual(momentum.velocity, 2000, accuracy: 1e-9)

        momentum.seed(inputSpeed: 20, direction: 1, lineRate: 20, settings: settings)
        XCTAssertFalse(momentum.isActive, "slower than the stop speed")
        XCTAssertEqual(momentum.advance(interval: 1.0 / 60.0, settings: settings), 0)
    }

    func testReleaseGap_isTwiceTheLastIntervalWithin50And160Milliseconds() {
        XCTAssertEqual(ScrollMomentum.releaseGap(lastInterval: nil), 0.16, "a single notch")
        XCTAssertEqual(ScrollMomentum.releaseGap(lastInterval: 0.01), 0.05)
        XCTAssertEqual(ScrollMomentum.releaseGap(lastInterval: 0.05), 0.10, accuracy: 1e-12)
        XCTAssertEqual(ScrollMomentum.releaseGap(lastInterval: 0.07), 0.14, accuracy: 1e-12)
        XCTAssertEqual(ScrollMomentum.releaseGap(lastInterval: 0.25), 0.16)
        XCTAssertEqual(ScrollMomentum.releaseGap(lastInterval: .nan), 0.16)
    }

    // MARK: - Sub-pixel carry

    func testSubpixelCarry_keepsTheSumWithinHalfAPixel() {
        var carry = ScrollSubpixelCarry()
        XCTAssertEqual(carry.take(3.7), 4)
        XCTAssertEqual(carry.take(0.6), 0, "3.7 + 0.6 = 4.3")
        XCTAssertEqual(carry.take(0.6), 1, "4.9")
        var floatSum = 4.9
        var intSum: Int64 = 5
        var value = 17.3
        for _ in 0..<200 {
            value *= 0.93
            floatSum += value
            intSum += carry.take(value)
            XCTAssertLessThanOrEqual(abs(Double(intSum) - floatSum), 0.5 + 1e-9)
        }
        XCTAssertEqual(carry.remainder, floatSum - Double(intSum), accuracy: 1e-9)
    }

    func testSubpixelCarry_slowFramesAddUpInsteadOfVanishing() {
        var carry = ScrollSubpixelCarry()
        var sum: Int64 = 0
        for _ in 0..<10 { sum += carry.take(-0.4) }
        XCTAssertEqual(sum, -4)
        carry.reset()
        XCTAssertEqual(carry.remainder, 0)
        XCTAssertEqual(carry.take(.nan), 0)
        XCTAssertEqual(carry.take(0.4), 0)
    }

    /// An event without distance (a phase change, a frame that is not sent) never moves the
    /// page, also when exactly half a unit is waiting.
    func testSubpixelCarry_zeroNeverProducesOutput() {
        for half in [0.5, -0.5] {
            var carry = ScrollSubpixelCarry()
            XCTAssertEqual(carry.take(half), 0)
            for _ in 0..<5 { XCTAssertEqual(carry.take(0), 0) }
            XCTAssertEqual(carry.remainder, half)
            XCTAssertEqual(carry.take(half), half > 0 ? 1 : -1)
            XCTAssertEqual(carry.remainder, 0)
        }
    }

    // MARK: - Single notch and slow scrolling

    /// One notch is one soft bump: it starts below its top speed, only slows down after the
    /// peak and lands at a steady pixel per frame instead of creeping.
    func testSingleNotch_isOneSoftBumpOfExactly60Pixels() {
        let rig = ScrollMomentumRig()
        XCTAssertEqual(rig.notch, 60.48, accuracy: 1e-9)
        rig.wheel(lines: 1, at: 0)
        rig.run(until: 1)

        XCTAssertEqual(rig.pixelsY, 60, "one notch is 60 px, no glide")
        XCTAssertEqual(rig.pixelsY(until: 0.36), 60, "landed within 360 ms")
        XCTAssertFalse(rig.hasMomentumPhase)
        XCTAssertEqual(rig.phaseSequence, ["began", "changed", "ended"])
        XCTAssertEqual(rig.stops.count, 1)
        XCTAssertEqual(rig.stops.first?.phase, .TrackingEnd)
        XCTAssertLessThan(rig.stops.first?.time ?? .infinity, 0.45)
        XCTAssertEqual(rig.poster.coastVelocityForTests, 0)

        let movement = rig.movementY
        let pixels = movement.map { $0.pixels }
        let peak = pixels.max() ?? 0
        XCTAssertLessThan(pixels.first ?? .infinity, peak, "starts below its top speed: no jump")
        XCTAssertLessThanOrEqual(peak, 8, "the top speed of a 60 px bump")
        let peakIndex = pixels.firstIndex(of: peak) ?? 0
        for index in (peakIndex + 1)..<pixels.count {
            // (Whole pixels: one pixel of rounding either way.)
            XCTAssertLessThanOrEqual(pixels[index], pixels[index - 1] + 1, "frame \(index)")
        }
        XCTAssertLessThanOrEqual(rig.longestPauseY, rig.frameInterval * 1.5, "no frame without movement before the end")
        XCTAssertEqual(Array(pixels.suffix(2)), [1, 1], "lands at a steady pixel per frame")
    }

    /// Slow notches run into each other: the page keeps moving between them instead of
    /// starting and stopping with every notch.
    func testSlowSeries_fourPerSecondRunsTogetherWithNoGlide() {
        let rig = ScrollMomentumRig()
        for index in 0..<4 {
            rig.wheel(lines: 1, at: Double(index) * 0.25)
            XCTAssertEqual(rig.poster.coastVelocityForTests, 0, "notch \(index)")
        }
        rig.run(until: 2)

        XCTAssertEqual(rig.pixelsY, 4 * 60.48, accuracy: 1, "4 × 60 px, nothing more")
        XCTAssertFalse(rig.hasMomentumPhase)
        XCTAssertEqual(rig.phaseSequence, ["began", "changed", "ended"], "one gesture")
        XCTAssertEqual(rig.stops.map { $0.phase }, [.TrackingEnd])
        XCTAssertLessThan(rig.lastMovement, 0.75 + 0.4)
        XCTAssertLessThanOrEqual(rig.longestPauseY, rig.frameInterval * 3.5, "the page does not come to rest between notches")
    }

    /// Up to 8 lines per second nothing glides, however long the wheel turns.
    func testSteadyScrolling_atEightPerSecondHasNoGlide() {
        let rig = ScrollMomentumRig()
        for index in 0..<8 { rig.wheel(lines: 1, at: Double(index) * 0.125) }
        rig.run(until: 3)
        XCTAssertEqual(rig.pixelsY, 8 * 60.48, accuracy: 1)
        XCTAssertFalse(rig.hasMomentumPhase)
        XCTAssertLessThan(rig.lastMovement, 0.875 + 0.4)
    }

    // MARK: - Flick

    func testFlick_fiveNotchesAtTwentyPerSecondGlide() {
        let rig = ScrollMomentumRig()
        let lastTick = 0.2
        for index in 0..<5 { rig.wheel(lines: 1, at: Double(index) * 0.05) }
        XCTAssertEqual(rig.poster.coastVelocityForTests, 60.48 / 0.05, accuracy: 1e-6, "the glide starts at the wheel's speed")
        rig.run(until: 3)

        let plain = 5 * 60.48
        XCTAssertEqual(rig.pixelsY / plain, 1.86, accuracy: 0.08, "travels about 1.86× the plain distance")
        XCTAssertEqual(rig.lastMovement - lastTick, 0.8, accuracy: 0.1, "ends about 0.8 s after the last tick")

        // The page keeps moving between the last notch and the glide: no stall in between.
        let glideSpeed = 60.48 / 0.05
        for item in rig.moving where item.time > rig.start + lastTick && item.time <= rig.start + lastTick + 0.15 {
            XCTAssertGreaterThan(item.frame.y * 60, glideSpeed / 2, "speed at \(item.time - rig.start)")
        }
        // Speed only falls during the glide.
        let glideFrames = rig.moving.filter { ($0.frame.momentumPhase ?? 0) != 0 }.map { $0.frame.y }
        XCTAssertGreaterThan(glideFrames.count, 30)
        for (previous, next) in zip(glideFrames, glideFrames.dropFirst()) {
            XCTAssertLessThanOrEqual(next, previous + 1, "whole pixels: at most one up")
        }
    }

    func testFlick_phasesGoFromGestureToMomentum() {
        let rig = ScrollMomentumRig()
        for index in 0..<5 { rig.wheel(lines: 1, at: Double(index) * 0.05) }
        rig.run(until: 3)

        XCTAssertEqual(rig.phaseSequence, ["began", "changed", "ended", "momentumBegan", "momentumChanged", "momentumEnded"])
        guard let ended = rig.recorded.first(where: { $0.frame.scrollPhase == 4 }),
              let momentumBegan = rig.recorded.first(where: { $0.frame.momentumPhase == 1 }) else {
            return XCTFail("no ended / momentum began event")
        }
        // Released 100 ms (twice the 50 ms interval) after the last tick at 0.2 s.
        XCTAssertEqual(ended.time - rig.start, 0.2 + 0.1, accuracy: 1.5 / 60.0)
        // Chromium only accepts momentum that begins within 100 ms of the gesture's end.
        XCTAssertLessThanOrEqual(momentumBegan.time - ended.time, 0.1)
        XCTAssertEqual(ended.frame.y, 0, "the ended event carries no distance")
        XCTAssertNotEqual(momentumBegan.frame.y, 0)
        XCTAssertEqual(rig.stops.map { $0.phase }, [.MomentumEnd])
        XCTAssertEqual(rig.recorded.last?.frame.momentumPhase, 3)
        XCTAssertEqual(rig.recorded.last?.frame.y, 0)
    }

    func testFlick_fasterFlicksGlideFarther() {
        func distance(interval: Double) -> Double {
            let rig = ScrollMomentumRig()
            for index in 0..<5 { rig.wheel(lines: 1, at: Double(index) * interval) }
            rig.run(until: 4)
            return rig.pixelsY
        }
        let slow = distance(interval: 0.1)      // 10 lines/s: a little glide
        let medium = distance(interval: 0.05)   // 20 lines/s
        let fast = distance(interval: 0.04)     // 25 lines/s
        XCTAssertGreaterThan(slow, 5 * 60.48 - 1)
        XCTAssertLessThan(slow, 5 * 60.48 * 1.15)
        XCTAssertGreaterThan(medium, slow + 100)
        XCTAssertGreaterThan(fast, medium + 30)
    }

    func testFlick_sameDistanceAt60And120Hz() {
        func total(rate: Double) -> (pixels: Double, end: Double) {
            let rig = ScrollMomentumRig(rate: rate)
            for index in 0..<5 { rig.wheel(lines: 1, at: Double(index) * 0.05) }
            rig.run(until: 3)
            return (rig.pixelsY, rig.lastMovement)
        }
        let at60 = total(rate: 60)
        let at120 = total(rate: 120)
        XCTAssertEqual(at120.pixels, at60.pixels, accuracy: at60.pixels * 0.03)
        XCTAssertEqual(at120.end, at60.end, accuracy: 0.05)
    }

    /// A tick in the direction of the glide is ordinary scrolling again: the momentum phase
    /// ends, a new gesture begins, and one slow notch leaves no glide behind.
    func testTickDuringGlide_inTheSameDirectionStartsANewGesture() {
        let rig = ScrollMomentumRig()
        for index in 0..<5 { rig.wheel(lines: 1, at: Double(index) * 0.05) }
        rig.run(until: 0.5)
        XCTAssertNotEqual(rig.poster.coastVelocityForTests, 0)
        let before = rig.pixelsY

        rig.wheel(lines: 1, at: 0.5)
        XCTAssertEqual(rig.poster.coastVelocityForTests, 0, "the glide follows the wheel's current speed")
        rig.run(until: 2)

        // The notch, plus what the glide still eases out over (it is not cut dead).
        XCTAssertGreaterThanOrEqual(rig.pixelsY - before, 60)
        XCTAssertLessThan(rig.pixelsY - before, 60 + 45)
        XCTAssertEqual(rig.phaseSequence, [
            "began", "changed", "ended", "momentumBegan", "momentumChanged", "momentumEnded",
            "began", "changed", "ended",
        ])
    }

    // MARK: - Reverse tick

    func testReverseTick_stopsTheGlideAndScrollsNothing() {
        let rig = ScrollMomentumRig()
        for index in 0..<5 { rig.wheel(lines: 1, at: Double(index) * 0.05) }
        rig.run(until: 0.5)
        XCTAssertGreaterThan(rig.poster.coastVelocityForTests, 300, "gliding")
        let before = rig.recorded.count
        let pixelsBefore = rig.pixelsY

        rig.wheel(lines: -1, at: 0.5)

        // The tick itself produces the end sequence at once: momentum ends, then fingers
        // down and up again, which makes apps drop their own momentum.
        let sequence = rig.recorded[before...].map {
            ScrollMomentumRig.phaseName(scroll: $0.frame.scrollPhase ?? -1, momentum: $0.frame.momentumPhase ?? -1)
        }
        XCTAssertEqual(sequence, ["momentumEnded", "mayBegin", "cancelled"])
        XCTAssertEqual(rig.poster.coastVelocityForTests, 0)
        let state = rig.poster.motionStateForTests
        XCTAssertEqual(state.buffer.y, state.current.y, "nothing left to scroll, the tick is not added")

        rig.run(until: 2)
        XCTAssertEqual(rig.recorded.count, before + 3, "no further events")
        XCTAssertEqual(rig.pixelsY, pixelsBefore, "zero output after the reverse tick")
        XCTAssertEqual(rig.stops.count, 1)
        XCTAssertLessThan(rig.stops.first?.time ?? .infinity, 0.5 + 2.5 / 60.0, "the poster stops on the next frame")
    }

    func testReverseTick_theNextOneScrollsBack() {
        let rig = ScrollMomentumRig()
        for index in 0..<5 { rig.wheel(lines: 1, at: Double(index) * 0.05) }
        rig.run(until: 0.5)
        let glided = rig.pixelsY
        rig.wheel(lines: -1, at: 0.5)
        rig.wheel(lines: -1, at: 0.6)
        rig.run(until: 2)
        XCTAssertEqual(rig.pixelsY - glided, -60, "only the second reverse notch scrolls")
        XCTAssertEqual(Array(rig.phaseSequence.suffix(3)), ["began", "changed", "ended"])
    }

    func testReverseTick_beforeTheReleaseIsAnOrdinaryDirectionChange() {
        let rig = ScrollMomentumRig()
        for index in 0..<5 { rig.wheel(lines: 1, at: Double(index) * 0.05) }
        // 30 ms after the last tick the wheel has not been let go yet (release gap 100 ms).
        rig.wheel(lines: -1, at: 0.23)
        let forward = rig.pixelsY
        XCTAssertEqual(rig.poster.coastVelocityForTests, 0)
        rig.run(until: 2)
        XCTAssertEqual(rig.pixelsY - forward, -60)
        XCTAssertFalse(rig.hasMomentumPhase)
    }

    func testReverseTick_scrollsNormallyWhenTheStopIsTurnedOff() {
        let rig = ScrollMomentumRig()
        rig.tuning.momentum?.stopOnReverseTick = false
        for index in 0..<5 { rig.wheel(lines: 1, at: Double(index) * 0.05) }
        rig.run(until: 0.5)
        let glided = rig.pixelsY
        rig.wheel(lines: -1, at: 0.5)
        rig.run(until: 2)
        XCTAssertEqual(rig.pixelsY - glided, -60)
    }

    // MARK: - Modifiers

    func testModifiers_suppressTheGlide() {
        let rig = ScrollMomentumRig()
        rig.modifiersHeld = true
        for index in 0..<5 {
            rig.wheel(lines: 1, at: Double(index) * 0.05)
            XCTAssertEqual(rig.poster.coastVelocityForTests, 0)
        }
        rig.run(until: 3)
        XCTAssertEqual(rig.pixelsY, 5 * 60.48, accuracy: 1, "the plain distance (zooming stays exact)")
        XCTAssertFalse(rig.hasMomentumPhase)
        XCTAssertEqual(rig.phaseSequence, ["began", "changed", "ended"])
        XCTAssertLessThan(rig.lastMovement, 0.2 + 0.4)
    }

    func testModifiers_pressedDuringAFlickEndTheGlide() {
        let rig = ScrollMomentumRig()
        for index in 0..<4 { rig.wheel(lines: 1, at: Double(index) * 0.05) }
        XCTAssertNotEqual(rig.poster.coastVelocityForTests, 0)
        rig.modifiersHeld = true
        rig.wheel(lines: 1, at: 0.2)
        XCTAssertEqual(rig.poster.coastVelocityForTests, 0)
        rig.run(until: 3)
        XCTAssertEqual(rig.pixelsY, 5 * 60.48, accuracy: 1)
    }

    func testModifierCheck_coversCommandControlAndOption() {
        XCTAssertTrue(ScrollCore.blocksCoast(.maskCommand))
        XCTAssertTrue(ScrollCore.blocksCoast(.maskControl))
        XCTAssertTrue(ScrollCore.blocksCoast([.maskAlternate, .maskShift]))
        XCTAssertFalse(ScrollCore.blocksCoast(.maskShift), "Shift scrolls sideways, it does not zoom")
        XCTAssertFalse(ScrollCore.blocksCoast([]))
    }

    // MARK: - Free-spin

    /// 100 lines/s (2 lines every 20 ms) for one second, then the wheel is stopped.
    private func freeSpin(_ rig: ScrollMomentumRig) -> Double {
        var last = 0.0
        for index in 0..<50 {
            last = Double(index) * 0.02
            rig.wheel(lines: 2, at: last)
        }
        return last
    }

    func testFreeSpin_stopsWithTheWheel() {
        let rig = ScrollMomentumRig()
        let lastTick = freeSpin(rig)
        XCTAssertTrue(rig.tracker.state.isFreeSpin)
        XCTAssertEqual(rig.poster.coastVelocityForTests, 0, "the wheel has its own inertia: no glide on top")
        let atStop = rig.pixelsY
        rig.run(until: 4)

        XCTAssertLessThanOrEqual(rig.lastMovement - lastTick, 0.13 + 1.0 / 60.0, "ends within about 130 ms")
        // What is left after the last tick is what the smoothing still owed, not a glide.
        XCTAssertLessThan(rig.pixelsY - atStop, 0.06 * rig.pixelsY)
        XCTAssertFalse(rig.hasMomentumPhase)
        XCTAssertEqual(rig.stops.map { $0.phase }, [.TrackingEnd])
    }

    func testFreeSpin_hasNoPhasesOnceLatched() {
        let rig = ScrollMomentumRig()
        _ = freeSpin(rig)
        rig.run(until: 4)

        // The gesture that began in ratchet mode is ended when free-spin latches
        // (12 lines: the sixth event, at 0.1 s); from then on events carry no phases.
        XCTAssertEqual(rig.phaseSequence, ["began", "changed", "ended"])
        let ended = rig.recorded.first { $0.frame.scrollPhase == 4 }
        XCTAssertEqual((ended?.time ?? 0) - rig.start, 0.1, accuracy: 1e-6)
        let afterLatch = rig.recorded.filter { $0.time > rig.start + 0.1 + 1e-6 }
        XCTAssertGreaterThan(afterLatch.count, 50)
        XCTAssertTrue(afterLatch.allSatisfy { $0.frame.scrollPhase == nil && $0.frame.momentumPhase == nil })
        XCTAssertTrue(afterLatch.allSatisfy { $0.frame.precise })
    }

    func testFreeSpin_usesFreeSpinSmoothnessAlthoughSimulateTrackpadIsOn() {
        // "Simulate trackpad" (on in this preset) has no say in the smoothing: the free-spin
        // smoothness applies, with momentum and without.
        let tuning = ScrollPreset.magicMouse.values.tuning
        XCTAssertTrue(ScrollPreset.magicMouse.values.simulateTrackpad)
        let spinning = ScrollSpinState(lineRate: 100, freeSpinBlend: 1, isFreeSpin: true, accelerationRate: 100)
        let regular = OPTIONS_SCROLL_DEFAULT.generateDurationTransition(with: 2.5)
        let resolved = tuning.resolve(speed: 1.8, durationTransition: regular, spin: spinning)
        XCTAssertEqual(resolved.durationTransition, OPTIONS_SCROLL_DEFAULT.generateDurationTransition(with: 1.0), accuracy: 1e-12)
        XCTAssertEqual(resolved.speed, 1.8 * 1.2, accuracy: 1e-12)

        var classic = tuning
        classic.momentum = nil
        XCTAssertEqual(classic.resolve(speed: 1.8, durationTransition: regular, spin: spinning), resolved)
    }

    func testFreeSpin_canGlideAndKeepPhasesWhenAsked() {
        let rig = ScrollMomentumRig()
        rig.tuning.momentum?.coastInFreeSpin = true
        rig.tuning.momentum?.phasesInFreeSpin = true
        let lastTick = freeSpin(rig)
        XCTAssertGreaterThan(rig.poster.coastVelocityForTests, 5000)
        rig.run(until: 6)
        XCTAssertTrue(rig.hasMomentumPhase)
        XCTAssertGreaterThan(rig.lastMovement - lastTick, 1.0)
    }

    // MARK: - Horizontal

    func testHorizontal_thumbWheelHasNoPhasesAndNoGlide() {
        let rig = ScrollMomentumRig()
        for index in 0..<8 {
            rig.thumbWheel(lines: 1, at: Double(index) * 0.03)
            XCTAssertEqual(rig.poster.coastVelocityForTests, 0)
        }
        rig.run(until: 3)

        XCTAssertEqual(rig.pixelsX, 8 * 60.48, accuracy: 1, "the plain distance")
        XCTAssertEqual(rig.pixelsY, 0)
        XCTAssertTrue(rig.phaseSequence.isEmpty, "browsers would take phased horizontal scrolling for a back/forward swipe")
        XCTAssertTrue(rig.recorded.allSatisfy { $0.frame.scrollPhase == nil && $0.frame.momentumPhase == nil })
        XCTAssertLessThan(rig.lastMovement, 0.21 + 0.45)
    }

    func testHorizontal_shiftedWheelGlidesWithoutPhases() {
        let rig = ScrollMomentumRig()
        rig.poster.updateShifting(enable: true)
        for index in 0..<5 { rig.wheel(lines: 1, at: Double(index) * 0.05) }
        rig.run(until: 3)
        XCTAssertEqual(rig.pixelsY, 0)
        XCTAssertGreaterThan(rig.pixelsX, 5 * 60.48 * 1.5, "the wheel still glides sideways")
        XCTAssertTrue(rig.phaseSequence.isEmpty)
    }

    func testHorizontal_phasesCanBeTurnedOn() {
        let rig = ScrollMomentumRig()
        rig.tuning.momentum?.phasesOnHorizontal = true
        rig.thumbWheel(lines: 1, at: 0)
        rig.run(until: 1)
        XCTAssertEqual(rig.phaseSequence, ["began", "changed", "ended"])
    }

    func testHorizontal_afterAVerticalGlideEndsItsMomentumPhase() {
        let rig = ScrollMomentumRig()
        for index in 0..<5 { rig.wheel(lines: 1, at: Double(index) * 0.05) }
        rig.run(until: 0.5)
        rig.thumbWheel(lines: 1, at: 0.5)
        XCTAssertEqual(rig.poster.coastVelocityForTests, 0)
        rig.run(until: 2)
        XCTAssertEqual(rig.phaseSequence, ["began", "changed", "ended", "momentumBegan", "momentumChanged", "momentumEnded"])
        XCTAssertEqual(rig.pixelsX, 60, accuracy: 1)
    }

    // MARK: - Thumb wheel as a page swipe

    /// Momentum off, simulate trackpad off: the page swipe is its own switch.
    private func pageSwipeRig() -> ScrollMomentumRig {
        let rig = ScrollMomentumRig(preset: .balanced)
        rig.tuning.horizontalWheelAction = .pageSwipe
        XCTAssertNil(rig.tuning.momentum)
        XCTAssertFalse(rig.simulateTrackpad)
        return rig
    }

    func testPageSwipe_isAPhasedGestureWithoutMomentum() {
        let rig = pageSwipeRig()
        for index in 0..<8 { rig.thumbWheel(lines: 1, at: Double(index) * 0.03) }
        rig.run(until: 3)

        XCTAssertEqual(rig.phaseSequence, ["began", "changed", "ended"], "apps follow the gesture and decide at its end")
        XCTAssertFalse(rig.hasMomentumPhase)
        XCTAssertEqual(rig.pixelsY, 0)
        XCTAssertEqual(rig.pixelsX, 8 * rig.notch, accuracy: 1, "the wheel's distance, in whole pixels")
        XCTAssertEqual(abs(rig.pixelsX), rig.floatTotal, accuracy: 1)
        XCTAssertTrue(rig.recorded.allSatisfy { $0.frame.precise })
        XCTAssertTrue(rig.recorded.allSatisfy { $0.frame.x == $0.frame.x.rounded() && $0.frame.y == 0 })
        XCTAssertEqual(rig.recorded.first?.frame.scrollPhase, 1)
        XCTAssertEqual(rig.recorded.first?.frame.x, 0, "began carries no distance")
        XCTAssertEqual(rig.recorded.last?.frame.scrollPhase, 4)
        XCTAssertEqual(rig.stops.map { $0.phase }, [.TrackingEnd])
        // Follows the wheel closely: done soon after the last event at 0.21 s.
        XCTAssertLessThan(rig.lastMovement, 0.21 + 0.15)
        XCTAssertLessThan(rig.stops.first?.time ?? .infinity, 0.21 + 0.25)
    }

    func testPageSwipe_turningBackStaysInTheSameGesture() {
        let rig = pageSwipeRig()
        for index in 0..<4 { rig.thumbWheel(lines: 1, at: Double(index) * 0.04) }
        for index in 0..<4 { rig.thumbWheel(lines: -1, at: 0.16 + Double(index) * 0.04) }
        rig.run(until: 3)
        XCTAssertEqual(rig.phaseSequence, ["began", "changed", "ended"], "one gesture: the app can follow it back and cancel")
        XCTAssertTrue(rig.moving.contains { $0.frame.x > 0 })
        XCTAssertTrue(rig.moving.contains { $0.frame.x < 0 })
        XCTAssertEqual(rig.stops.count, 1)
    }

    func testPageSwipe_usesItsOwnDirectSmoothing() {
        // Also when the regular Duration is a long glide.
        let lockedDuration = OPTIONS_SCROLL_DEFAULT.generateDurationTransition(with: 4.75)
        let slow = ScrollTuningResolution(multiplier: 1, speed: 2.7, durationTransition: lockedDuration, freeSpinBlend: 0)
        let swipe = ScrollCore.posterInput(y: 0, x: 33.6, step: 33.6, vertical: slow, horizontal: slow, pageSwipe: true)
        XCTAssertEqual(swipe.duration, ScrollCore.pageSwipeTransition)
        XCTAssertTrue(swipe.bypassFilter)
        XCTAssertTrue(swipe.pageSwipe)
        let scroll = ScrollCore.posterInput(y: 0, x: 33.6, step: 33.6, vertical: slow, horizontal: slow)
        XCTAssertEqual(scroll.duration, lockedDuration)
        XCTAssertFalse(scroll.bypassFilter)
    }

    func testPageSwipe_onlyForThePlainThumbWheel() {
        func isSwipe(_ action: ScrollHorizontalWheelAction, y: Double = 0, x: Double = 60, flags: CGEventFlags = [], toggle: Bool = false) -> Bool {
            return ScrollCore.isPageSwipe(action: action, y: y, x: x, flags: flags, toggleScroll: toggle)
        }
        XCTAssertTrue(isSwipe(.pageSwipe))
        XCTAssertTrue(isSwipe(.pageSwipe, x: -60))
        XCTAssertFalse(isSwipe(.scroll), "the default: the thumb wheel scrolls sideways")
        XCTAssertFalse(isSwipe(.pageSwipe, x: 0))
        XCTAssertFalse(isSwipe(.pageSwipe, y: 60), "not for diagonal input")
        XCTAssertFalse(isSwipe(.pageSwipe, flags: .maskShift), "Shift + wheel is sideways scrolling")
        XCTAssertFalse(isSwipe(.pageSwipe, toggle: true), "so is the toggle key")
    }

    func testPageSwipe_offMeansThumbWheelScrollsAsBefore() {
        let rig = ScrollMomentumRig(preset: .balanced)
        XCTAssertEqual(rig.tuning.horizontalWheelAction, .scroll)
        for index in 0..<8 { rig.thumbWheel(lines: 1, at: Double(index) * 0.03) }
        rig.run(until: 3)
        XCTAssertTrue(rig.recorded.allSatisfy { !$0.frame.precise }, "classic posting")
        XCTAssertTrue(rig.phaseSequence.isEmpty)
    }

    func testPageSwipe_withMomentumOnVerticalStillGlides() {
        let rig = ScrollMomentumRig()
        rig.tuning.horizontalWheelAction = .pageSwipe
        for index in 0..<5 { rig.wheel(lines: 1, at: Double(index) * 0.05) }
        rig.run(until: 0.5)
        XCTAssertNotEqual(rig.poster.coastVelocityForTests, 0)
        // The thumb wheel takes over: the glide's momentum phase ends, the swipe begins.
        rig.thumbWheel(lines: 1, at: 0.5)
        XCTAssertEqual(rig.poster.coastVelocityForTests, 0)
        rig.run(until: 3)
        XCTAssertEqual(rig.phaseSequence, [
            "began", "changed", "ended", "momentumBegan", "momentumChanged", "momentumEnded",
            "began", "changed", "ended",
        ])
        XCTAssertEqual(rig.pixelsX, 60, accuracy: 1)
    }

    // MARK: - Without "simulate trackpad"

    func testMomentum_withoutSimulateTrackpadGlidesWithoutPhases() {
        let rig = ScrollMomentumRig()
        rig.simulateTrackpad = false
        rig.poster.setConfigForTests(simTrackpadEnabled: false)
        for index in 0..<5 { rig.wheel(lines: 1, at: Double(index) * 0.05) }
        rig.run(until: 3)
        XCTAssertEqual(rig.pixelsY / (5 * 60.48), 1.86, accuracy: 0.08)
        XCTAssertTrue(rig.phaseSequence.isEmpty)
        XCTAssertTrue(rig.recorded.allSatisfy { $0.frame.y != 0 }, "no empty events without phases")
    }

    func testMomentum_withoutSimulateTrackpadAReverseTickStillStopsTheGlide() {
        let rig = ScrollMomentumRig()
        rig.simulateTrackpad = false
        rig.poster.setConfigForTests(simTrackpadEnabled: false)
        for index in 0..<5 { rig.wheel(lines: 1, at: Double(index) * 0.05) }
        rig.run(until: 0.5)
        let before = (count: rig.recorded.count, pixels: rig.pixelsY)
        rig.wheel(lines: -1, at: 0.5)
        rig.run(until: 2)
        XCTAssertEqual(rig.recorded.count, before.count, "no phases to send, and nothing scrolls")
        XCTAssertEqual(rig.pixelsY, before.pixels)
        XCTAssertEqual(rig.stops.count, 1)
    }

    // MARK: - Whole pixels

    func testPosting_integerPixelSumEqualsFloatSumWithinOnePixel() {
        let scenarios: [(name: String, drive: (ScrollMomentumRig) -> Void)] = [
            ("single notch", { $0.wheel(lines: 1, at: 0) }),
            ("flick", { rig in (0..<5).forEach { rig.wheel(lines: 1, at: Double($0) * 0.05) } }),
            ("fast flick", { rig in (0..<9).forEach { rig.wheel(lines: 1, at: Double($0) * 0.03) } }),
            ("upward flick", { rig in (0..<5).forEach { rig.wheel(lines: -1, at: Double($0) * 0.05) } }),
            ("free-spin", { rig in (0..<50).forEach { rig.wheel(lines: 2, at: Double($0) * 0.02) } }),
        ]
        for rate in [60.0, 120, 144] {
            for scenario in scenarios {
                let rig = ScrollMomentumRig(rate: rate)
                scenario.drive(rig)
                rig.run(until: 6)
                XCTAssertFalse(rig.isRunning, "\(scenario.name) at \(rate) Hz has ended")
                XCTAssertEqual(abs(rig.pixelsY), rig.floatTotal, accuracy: 1, "\(scenario.name) at \(rate) Hz")
                XCTAssertTrue(rig.recorded.allSatisfy { $0.frame.precise }, scenario.name)
                XCTAssertTrue(rig.recorded.allSatisfy { $0.frame.y == $0.frame.y.rounded() }, "whole pixels")
                // Line deltas follow the pixels: 10 px per line.
                let lines = rig.recorded.reduce(0) { $0 + Double($1.frame.linesY) }
                XCTAssertEqual(lines, rig.pixelsY / 10, accuracy: 0.5 + 1e-9, "\(scenario.name) at \(rate) Hz")
            }
        }
    }

    func testPosting_preciseFrameWritesConsistentFields() throws {
        let template = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 3, wheel2: 0, wheel3: 0))
        XCTAssertEqual(template.getIntegerValueField(.scrollWheelEventDeltaAxis1), 3, "the wheel event carries 3 lines")

        let event = try XCTUnwrap(template.copy())
        ScrollOutgoingFrame(y: 37, x: -4, linesY: 4, linesX: 0, scrollPhase: 2, momentumPhase: 0, precise: true).write(to: event)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), 37)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2), -4)
        XCTAssertEqual(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1), 3.7, accuracy: 1e-4)
        XCTAssertEqual(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2), -0.4, accuracy: 1e-4)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventDeltaAxis1), 4)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventDeltaAxis2), 0)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventIsContinuous), 1)
        XCTAssertEqual(event.getDoubleValueField(.scrollWheelEventScrollPhase), 2)
        let appKit = try XCTUnwrap(NSEvent(cgEvent: event))
        XCTAssertEqual(appKit.scrollingDeltaY, 37)
        XCTAssertEqual(appKit.scrollingDeltaX, -4)
        XCTAssertTrue(appKit.hasPreciseScrollingDeltas)
        XCTAssertEqual(appKit.phase, .changed)

        // A phase-only event (began, ended) carries no distance at all: the template's
        // three lines do not ride along.
        let ended = try XCTUnwrap(template.copy())
        ScrollOutgoingFrame(y: 0, x: 0, scrollPhase: 4, momentumPhase: 0, precise: true).write(to: ended)
        XCTAssertEqual(ended.getIntegerValueField(.scrollWheelEventDeltaAxis1), 0)
        XCTAssertEqual(ended.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1), 0)
        XCTAssertEqual(ended.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), 0)
        XCTAssertEqual(try XCTUnwrap(NSEvent(cgEvent: ended)).phase, .ended)
    }

    func testPosting_classicFrameIsWrittenAsBefore() throws {
        let template = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 3, wheel2: 0, wheel3: 0))
        template.timestamp = 1_234
        let event = try XCTUnwrap(template.copy())
        ScrollOutgoingFrame(y: 3.7, x: 0).write(to: event)
        // Today's behaviour, kept while momentum is off: the fraction is dropped, the line
        // delta and the timestamp of the wheel event stay, phase fields are not touched.
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), 3)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventDeltaAxis1), 3)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventIsContinuous), 1)
        XCTAssertEqual(event.getDoubleValueField(.scrollWheelEventScrollPhase), 0)
        XCTAssertEqual(event.timestamp, 1_234)
    }

    func testPosting_preciseFrameGetsAFreshTimestampInTheTemplatesUnit() throws {
        let template = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0))
        let now: UInt64 = 10_000_000_000
        let nowSeconds = Double(now) * ScrollEventClock.secondsPerTick

        // Template stamped in mach ticks, 100 ms ago.
        let ticks = now - UInt64(0.1 / ScrollEventClock.secondsPerTick)
        template.timestamp = ticks
        var event = try XCTUnwrap(template.copy())
        ScrollOutgoingFrame(y: 1, x: 0, precise: true).write(to: event, now: now)
        XCTAssertEqual(event.timestamp, now)

        // Template stamped in nanoseconds (only distinguishable where a tick is not 1 ns).
        if ScrollEventClock.secondsPerTick > 2e-9 {
            template.timestamp = UInt64((nowSeconds - 0.1) * 1_000_000_000)
            event = try XCTUnwrap(template.copy())
            ScrollOutgoingFrame(y: 1, x: 0, precise: true).write(to: event, now: now)
            XCTAssertEqual(Double(event.timestamp) / 1_000_000_000, nowSeconds, accuracy: 1e-6)
        }

        // An unstamped template stays unstamped (the system stamps it when it is posted).
        XCTAssertEqual(ScrollEventClock.timestamp(now: now, like: 0), 0)
    }

    // MARK: - Momentum off

    func testMomentumOff_inputPathIsTheClassicOne() {
        let rig = ScrollMomentumRig(preset: .balanced)
        XCTAssertNil(rig.tuning.momentum)
        rig.poster.setConfigForTests(simTrackpadEnabled: true)
        for index in 0..<5 { rig.wheel(lines: 1, at: Double(index) * 0.05) }
        XCTAssertEqual(rig.poster.coastVelocityForTests, 0)
        rig.run(until: 3)

        XCTAssertTrue(rig.recorded.allSatisfy { !$0.frame.precise }, "classic posting")
        XCTAssertTrue(rig.moving.contains { $0.frame.y != $0.frame.y.rounded() }, "fractional deltas as before")
        XCTAssertTrue(rig.moving.allSatisfy { abs($0.frame.y) > 1 }, "the dead zone still applies")
        // No glide: the page stops once the smoothing has caught up.
        XCTAssertLessThanOrEqual(rig.floatTotal, 5 * rig.notch + 1e-6)
        XCTAssertGreaterThan(rig.floatTotal, 5 * rig.notch - 2)
        XCTAssertLessThan(rig.lastMovement, 0.2 + 0.35)
        // The classic release: gesture ends 180 ms after the last tick.
        let ended = rig.recorded.first { $0.frame.scrollPhase == 4 }
        XCTAssertEqual((ended?.time ?? 0) - rig.start, 0.2 + 0.18, accuracy: 1.5 / 60.0)
    }
}

// MARK: - Phase machine and settings

final class ScrollMomentumContractTests: XCTestCase {

    // MARK: ScrollPhase.onMomentumCancelled

    func testMomentumCancelled_duringMomentumEndsItThenTouchesAndLifts() {
        let phases = ScrollPhase()
        for start in [Phase.MomentumBegin, .MomentumOngoing] {
            phases.apply(phase: start)
            let plan = phases.onMomentumCancelled()
            XCTAssertEqual(plan.queue.map { $0.0 }, [.MomentumEnd, .Hold, .Leave], "\(start)")
            XCTAssertNil(plan.target)
            XCTAssertEqual(plan.queue.last?.1, .Idle, "idle once the sequence is delivered")
        }
    }

    func testMomentumCancelled_whileTrackingJustEndsTheGesture() {
        let phases = ScrollPhase()
        for start in [Phase.TrackingBegin, .TrackingOngoing] {
            phases.apply(phase: start)
            let plan = phases.onMomentumCancelled()
            XCTAssertEqual(plan.queue.map { $0.0 }, [.TrackingEnd], "\(start)")
            XCTAssertNil(plan.target)
        }
    }

    func testMomentumCancelled_otherwiseDoesNothing() {
        let phases = ScrollPhase()
        for start in [Phase.Idle, .Hold, .TrackingEnd, .MomentumEnd, .Leave] {
            phases.apply(phase: start)
            let plan = phases.onMomentumCancelled()
            XCTAssertTrue(plan.queue.isEmpty, "\(start)")
            XCTAssertNil(plan.target, "\(start)")
        }
    }

    func testPhaseValues_ofTheEndSequence() {
        XCTAssertEqual(PhaseValueMapping[.MomentumEnd]?[.Momentum], 3)
        XCTAssertEqual(PhaseValueMapping[.Hold]?[.Scroll], 128, "may begin")
        XCTAssertEqual(PhaseValueMapping[.Leave]?[.Scroll], 8, "cancelled")
    }

    // MARK: Settings

    func testDefaults_areOff() {
        XCTAssertNil(ScrollTuningSettings.default.momentum)
        XCTAssertEqual(ScrollTuningSettings.default.horizontalWheelAction, .scroll)
        let four = ScrollTuningSettings(freeSpinEnabled: true, freeSpinSmoothness: 1, freeSpinSpeed: 1, acceleration: 0)
        XCTAssertNil(four.momentum)
        XCTAssertEqual(four.horizontalWheelAction, .scroll)
    }

    func testMomentumDefaults() {
        let m = ScrollMomentumSettings.default
        XCTAssertEqual(m.decayPer8ms, 0.975)
        XCTAssertEqual(m.tailSpeed, 250)
        XCTAssertEqual(m.tailDecayPer8ms, 0.91)
        XCTAssertEqual(m.stopDelta, 0.5)
        XCTAssertEqual(m.coastGain, 1.0)
        XCTAssertEqual(m.minFlingRate, 8)
        XCTAssertEqual(m.fullFlingRate, 16)
        XCTAssertTrue(m.stopOnReverseTick)
        XCTAssertTrue(m.noCoastWithModifiers)
        XCTAssertFalse(m.coastInFreeSpin)
        XCTAssertFalse(m.phasesInFreeSpin)
        XCTAssertFalse(m.phasesOnHorizontal)
    }

    func testDecoding_settingsFromBeforeMomentum() throws {
        let old = #"{"freeSpinEnabled":false,"freeSpinSmoothness":2.5,"freeSpinSpeed":0.7,"acceleration":0.3}"#
        let settings = try JSONDecoder().decode(ScrollTuningSettings.self, from: Data(old.utf8))
        XCTAssertNil(settings.momentum)
        XCTAssertEqual(settings.horizontalWheelAction, .scroll)
        XCTAssertFalse(settings.freeSpinEnabled)
        XCTAssertEqual(settings.freeSpinSmoothness, 2.5)
        XCTAssertEqual(settings.freeSpinSpeed, 0.7)
        XCTAssertEqual(settings.acceleration, 0.3)
        // And they are written back unchanged: no new keys while both stay off.
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["freeSpinEnabled", "freeSpinSmoothness", "freeSpinSpeed", "acceleration"])
    }

    func testEncoding_roundTripsMomentumAndWheelAction() throws {
        var settings = ScrollPreset.magicMouse.values.tuning
        settings.horizontalWheelAction = .pageSwipe
        settings.momentum?.coastGain = 1.5
        settings.momentum?.phasesOnHorizontal = true
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(ScrollTuningSettings.self, from: data), settings)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["horizontalWheelAction"] as? String, "pageSwipe")
        XCTAssertNotNil(object["momentum"] as? [String: Any])
    }

    func testDecoding_partialMomentumFallsBackToDefaultsAndClamps() throws {
        let json = #"{"momentum":{"coastGain":99,"decayPer8ms":2,"minFlingRate":20,"fullFlingRate":10,"stopOnReverseTick":false,"future":1}}"#
        let settings = try JSONDecoder().decode(ScrollTuningSettings.self, from: Data(json.utf8))
        let momentum = try XCTUnwrap(settings.momentum)
        XCTAssertEqual(momentum.coastGain, ScrollMomentumSettings.coastGainRange.upperBound)
        XCTAssertEqual(momentum.decayPer8ms, ScrollMomentumSettings.decayRange.upperBound)
        XCTAssertEqual(momentum.minFlingRate, 20)
        XCTAssertEqual(momentum.fullFlingRate, 20, "never below the minimum")
        XCTAssertFalse(momentum.stopOnReverseTick)
        XCTAssertEqual(momentum.tailSpeed, 250)
        XCTAssertEqual(momentum.tailDecayPer8ms, 0.91)
        XCTAssertEqual(momentum.stopDelta, 0.5)
        XCTAssertTrue(momentum.noCoastWithModifiers)
        XCTAssertEqual(settings.freeSpinEnabled, ScrollTuningSettings.default.freeSpinEnabled)

        let empty = try JSONDecoder().decode(ScrollTuningSettings.self, from: Data(#"{"momentum":{}}"#.utf8))
        XCTAssertEqual(empty.momentum, .default, "an empty block is momentum with default values")
    }

    func testDecoding_unreadableValuesTurnTheFeatureOffInsteadOfFailing() throws {
        let json = #"{"acceleration":0.5,"momentum":"yes","horizontalWheelAction":"teleport"}"#
        let settings = try JSONDecoder().decode(ScrollTuningSettings.self, from: Data(json.utf8))
        XCTAssertNil(settings.momentum)
        XCTAssertEqual(settings.horizontalWheelAction, .scroll)
        XCTAssertEqual(settings.acceleration, 0.5, "the rest is still read")

        let nulls = try JSONDecoder().decode(ScrollTuningSettings.self, from: Data(#"{"momentum":null,"horizontalWheelAction":7}"#.utf8))
        XCTAssertNil(nulls.momentum)
        XCTAssertEqual(nulls.horizontalWheelAction, .scroll)
    }

    func testPosterInput_carriesTheWheelStateAndMomentum() {
        let vertical = ScrollTuningResolution(multiplier: 1.2, speed: 2.16, durationTransition: 0.561, freeSpinBlend: 1)
        let horizontal = ScrollTuningResolution(multiplier: 1, speed: 1.8, durationTransition: 0.307, freeSpinBlend: 0)
        let spin = ScrollSpinState(lineRate: 90, freeSpinBlend: 1, isFreeSpin: true, accelerationRate: 60)
        let input = ScrollCore.posterInput(
            y: 67.2, x: 0, step: 33.6, vertical: vertical, horizontal: horizontal,
            spin: spin, momentum: .default, modifiersHeld: true
        )
        XCTAssertEqual(input.momentum, .default)
        XCTAssertEqual(input.lineRate, 90)
        XCTAssertTrue(input.isFreeSpin)
        XCTAssertTrue(input.modifiersHeld)
        XCTAssertFalse(input.pageSwipe)

        let plain = ScrollCore.posterInput(y: 33.6, x: 0, step: 33.6, vertical: horizontal, horizontal: horizontal)
        XCTAssertNil(plain.momentum)
        XCTAssertEqual(plain.lineRate, 0)
        XCTAssertFalse(plain.isFreeSpin)
        XCTAssertFalse(plain.modifiersHeld)
    }
}
