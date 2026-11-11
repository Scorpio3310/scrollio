//
//  ScrollMotionTests.swift
//  MosTests
//
//  Frame-rate independent smoothing, the filter, lead cap, landing and event clock.
//

import XCTest
import QuartzCore
@testable import Mos_Debug

final class ScrollMotionTests: XCTestCase {

    private func transition(_ duration: Double) -> Double {
        return OPTIONS_SCROLL_DEFAULT.generateDurationTransition(with: duration)
    }

    private func input(_ y: Double, notch: Double = 90.72, duration: Double, bypass: Bool? = nil) -> ScrollPosterInput {
        let trans = transition(duration)
        return ScrollPosterInput(
            y: y, x: 0, notch: (y: notch, x: 0), duration: trans,
            bypassFilter: bypass ?? ScrollMotion.shouldBypassFilter(freeSpinBlend: 0)
        )
    }

    /// Time until less than 1 px of a 500 px move is left to emit, at `rate` Hz.
    private func settleTime(rate: Double, duration: Double, bypass: Bool) -> (time: Double, emitted: Double) {
        let poster = ScrollPoster()
        poster.applyInputForTests(input(500, duration: duration, bypass: bypass), at: 0)
        let dt = 1 / rate
        var time = 0.0
        var emitted = 0.0
        var settledAt: Double?
        while time < 10 {
            time += dt
            emitted += poster.advanceForTests(frameInterval: dt, now: 0).y
            if settledAt == nil && 500 - emitted < 1 { settledAt = time }
        }
        return (settledAt ?? .infinity, emitted)
    }

    // MARK: - Time-based interpolation

    func testTransition_at60HzIsThePerFrameFactor() {
        for duration in [0.5, 1.5, 3.13, 4.35] {
            let t = transition(duration)
            XCTAssertEqual(ScrollMotion.transition(t, frameInterval: 1.0 / 60.0), t, accuracy: 1e-12)
        }
    }

    func testTransition_twoFramesAt120HzEqualOneAt60Hz() {
        let t = transition(3.13)
        let t120 = ScrollMotion.transition(t, frameInterval: 1.0 / 120.0)
        XCTAssertEqual(1 - (1 - t120) * (1 - t120), t, accuracy: 1e-12)
    }

    func testTransition_clampsLongAndInvalidFrames() {
        let t = transition(3.13)
        XCTAssertEqual(ScrollMotion.transition(t, frameInterval: 0.5), ScrollMotion.transition(t, frameInterval: 3.0 / 60.0))
        XCTAssertEqual(ScrollMotion.transition(t, frameInterval: .nan), t, accuracy: 1e-12)
        XCTAssertEqual(ScrollMotion.transition(0, frameInterval: 1.0 / 60.0), 0)
        XCTAssertEqual(ScrollMotion.transition(1, frameInterval: 1.0 / 144.0), 1)
    }

    func testTimeConstant_matchesDurationSlider() {
        XCTAssertEqual(ScrollMotion.timeConstant(forTransition: transition(3.13)), 0.0657, accuracy: 0.001)
        XCTAssertEqual(ScrollMotion.timeConstant(forTransition: transition(4.35)), 0.187, accuracy: 0.002)
        XCTAssertEqual(ScrollMotion.timeConstant(forTransition: 1), 0)
    }

    func testSettleTime_isTheSameAt60And120And144Hz() {
        for duration in [0.5, 1.5, 3.13, 4.35] {
            for bypass in [false, true] {
                let at60 = settleTime(rate: 60, duration: duration, bypass: bypass)
                let at120 = settleTime(rate: 120, duration: duration, bypass: bypass)
                let at144 = settleTime(rate: 144, duration: duration, bypass: bypass)
                // One 60 Hz frame of sampling, a little more with the filter's own sampling.
                let tolerance = (bypass ? 1.0 : 1.5) / 60.0
                XCTAssertEqual(at120.time, at60.time, accuracy: tolerance, "duration \(duration) bypass \(bypass)")
                XCTAssertEqual(at144.time, at60.time, accuracy: tolerance, "duration \(duration) bypass \(bypass)")
                XCTAssertEqual(at60.emitted, 500, accuracy: 1e-6, "no distance lost")
                XCTAssertEqual(at120.emitted, 500, accuracy: 1e-6, "no distance lost")
            }
        }
    }

    // MARK: - Filter

    func testFilterBypass_onlyInFreeSpin() {
        XCTAssertFalse(ScrollMotion.shouldBypassFilter(freeSpinBlend: 0))
        XCTAssertFalse(ScrollMotion.shouldBypassFilter(freeSpinBlend: 0.49))
        XCTAssertTrue(ScrollMotion.shouldBypassFilter(freeSpinBlend: 0.5), "free-spin")
        XCTAssertTrue(ScrollMotion.shouldBypassFilter(freeSpinBlend: 1))
    }

    // MARK: - Two equal lags

    private func responseFactor(_ duration: Double) -> Double {
        let tau = ScrollMotion.responseTimeConstant(forTransition: transition(duration))
        return ScrollMotion.factor(timeConstant: tau, frameInterval: 1.0 / 60.0)
    }

    func testResponseTimeConstant_keepsTheClassicLandingTime() {
        // Classic: a lerp of τ, then a 64 ms filter, 95% after about 3 τ + min(τ, 64 ms).
        XCTAssertEqual(ScrollMotion.classicFilterTimeConstant, 0.0638, accuracy: 0.0005)
        let classic = ScrollMotion.timeConstant(forTransition: transition(4.35))
        let response = ScrollMotion.responseTimeConstant(forTransition: transition(4.35))
        XCTAssertEqual(response, 0.132, accuracy: 0.002, "Duration 4.35: two lags of 132 ms")
        XCTAssertEqual(response * ScrollMotion.landingTimeConstants, 3 * classic + 0.0638, accuracy: 0.001)
        XCTAssertLessThan(response, classic, "a shorter tail than the classic lerp")
        XCTAssertGreaterThan(response, ScrollMotion.classicFilterTimeConstant, "a softer start than the classic filter")
        // Short durations: the filter was never longer than the lerp.
        let short = ScrollMotion.timeConstant(forTransition: transition(2.0))
        XCTAssertEqual(ScrollMotion.responseTimeConstant(forTransition: transition(2.0)), 4 * short / 4.744, accuracy: 1e-9)
        XCTAssertEqual(ScrollMotion.responseTimeConstant(forTransition: 1), 0)
    }

    func testFactor_isFrameRateIndependent() {
        let at60 = ScrollMotion.factor(timeConstant: 0.1, frameInterval: 1.0 / 60.0)
        let at120 = ScrollMotion.factor(timeConstant: 0.1, frameInterval: 1.0 / 120.0)
        XCTAssertEqual(1 - (1 - at120) * (1 - at120), at60, accuracy: 1e-12)
        XCTAssertEqual(ScrollMotion.factor(timeConstant: 0, frameInterval: 1.0 / 60.0), 1)
        XCTAssertEqual(ScrollMotion.factor(timeConstant: .nan, frameInterval: 1.0 / 60.0), 1)
    }

    /// The measured landing: 95% of a notch within the classic landing time, whatever the Duration.
    func testNotch_lands95PercentInTheClassicLandingTime() {
        for duration in [2.0, 3.13, 4.35, 4.75] {
            let classic = ScrollMotion.timeConstant(forTransition: transition(duration))
            let landing = 3 * classic + min(classic, ScrollMotion.classicFilterTimeConstant)
            let poster = ScrollPoster()
            poster.applyInputForTests(input(100, duration: duration), at: 0)
            var emitted = 0.0, time = 0.0
            while emitted < 95 && time < 5 {
                time += 1.0 / 240.0
                emitted += poster.advanceForTests(frameInterval: 1.0 / 240.0, now: 0).y
            }
            XCTAssertEqual(time, landing, accuracy: landing * 0.06 + 0.01, "duration \(duration)")
        }
    }

    /// The speed rises as gently as it falls: the top speed comes one time constant in,
    /// not within the first frames.
    func testNotch_reachesItsTopSpeedOneTimeConstantIn() {
        for duration in [3.13, 4.35, 4.75] {
            let tau = ScrollMotion.responseTimeConstant(forTransition: transition(duration))
            let poster = ScrollPoster()
            poster.applyInputForTests(input(100, duration: duration), at: 0)
            var frames: [Double] = []
            for _ in 0..<240 {
                frames.append(poster.advanceForTests(frameInterval: 1.0 / 120.0, now: 0).y)
            }
            let peakTime = Double((frames.firstIndex(of: frames.max() ?? 0) ?? 0) + 1) / 120.0
            XCTAssertEqual(peakTime, tau, accuracy: 0.02, "duration \(duration)")
        }
    }

    /// Direct settings used to skip the filter: every notch then started with its largest
    /// frame (a jump) and only slowed down. Now the first frame is softened, without a frame of delay.
    func testNotch_startsWithoutAJumpAndWithoutDelay() {
        for duration in [1.0, 2.0, 3.13, 4.35] {
            let factor = responseFactor(duration)
            let poster = ScrollPoster()
            poster.applyInputForTests(input(90.72, duration: duration), at: 0)
            XCTAssertFalse(poster.motionStateForTests.bypassFilter, "duration \(duration)")
            var frames: [Double] = []
            for _ in 0..<12 {
                frames.append(poster.advanceForTests(frameInterval: 1.0 / 60.0, now: 0).y)
            }
            let first = frames[0]
            XCTAssertGreaterThan(first, 0, "moves on the first frame (duration \(duration))")
            XCTAssertEqual(first, 90.72 * factor * factor, accuracy: 1e-9)
            if duration >= 2.0 {
                // (At Duration 1 the whole bump is shorter than two frames.)
                XCTAssertGreaterThan(frames[1], first, "still speeding up on the second frame (duration \(duration))")
            }
        }

        let unfiltered = ScrollPoster()
        unfiltered.applyInputForTests(input(90.72, duration: 1.0, bypass: true), at: 0)
        XCTAssertEqual(unfiltered.advanceForTests(frameInterval: 1.0 / 60.0, now: 0).y, 90.72 * responseFactor(1.0), accuracy: 1e-9,
                       "from standstill an unfiltered motion is unfiltered at once")
    }

    /// Free-spin opens the filter up while the page is moving. That used to be a switch: what
    /// the filter held came out in a burst and the speed jumped. Now it is a short blend.
    func testFilterOpening_whileMovingNeverJumps() {
        let poster = ScrollPoster()
        var now = 100.0
        var frames: [Double] = []
        var total = 0.0
        // Steady scrolling, one notch per frame, filtered...
        for index in 0..<60 {
            let bypass = index >= 30   // ...then the wheel is taken for free-spinning
            poster.applyInputForTests(input(30, duration: 3.13, bypass: bypass), at: now)
            total += 30
            now += 1.0 / 60.0
            frames.append(poster.advanceForTests(frameInterval: 1.0 / 60.0, now: now).y)
        }
        for index in 31..<60 {
            XCTAssertLessThan(frames[index], frames[index - 1] * 1.12 + 0.5, "frame \(index): no burst when the filter opens")
        }
        // ...and back to filtered while still moving.
        for _ in 0..<30 {
            poster.applyInputForTests(input(30, duration: 3.13, bypass: false), at: now)
            total += 30
            now += 1.0 / 60.0
            let frame = poster.advanceForTests(frameInterval: 1.0 / 60.0, now: now).y
            XCTAssertGreaterThan(frame, (frames.last ?? 0) * 0.88 - 0.5, "no dip when the filter closes")
            frames.append(frame)
        }
        for _ in 0..<600 {
            now += 1.0 / 60.0
            frames.append(poster.advanceForTests(frameInterval: 1.0 / 60.0, now: now).y)
        }
        XCTAssertEqual(frames.reduce(0, +), total, accuracy: 0.5, "no distance lost or added by the blend")
    }

    func testFilterWeight_at60HzIsUnchanged() {
        XCTAssertEqual(ScrollMotion.transition(ScrollFilter.defaultWeight, frameInterval: 1.0 / 60.0), 0.23, accuracy: 1e-12)
        let a = ScrollFilter(), b = ScrollFilter()
        for value in [10.0, 10, 10, -4, 7] {
            let ra = a.fill(with: (y: value, x: value))
            let rb = b.fill(with: (y: value, x: value), weight: ScrollMotion.transition(0.23, frameInterval: 1.0 / 60.0))
            XCTAssertEqual(ra.y, rb.y, accuracy: 1e-12)
        }
    }

    func testFilter_stepResponseTimeIsFrameRateIndependent() {
        func timeTo90Percent(rate: Double) -> Double {
            let filter = ScrollFilter()
            let dt = 1 / rate
            let weight = ScrollMotion.transition(ScrollFilter.defaultWeight, frameInterval: dt)
            var time = 0.0
            while time < 2 {
                time += dt
                // constant velocity of 1000 px/s
                let out = filter.fill(with: (y: 1000 * dt, x: 0), weight: weight)
                if out.y / dt >= 900 { return time }
            }
            return .infinity
        }
        XCTAssertEqual(timeTo90Percent(rate: 120), timeTo90Percent(rate: 60), accuracy: 1.0 / 60.0)
    }

    func testFilterPassThrough_releasesPendingWithoutLoss() {
        let filter = ScrollFilter()
        var input = 0.0, output = 0.0
        for _ in 0..<4 {
            input += 10
            output += filter.fill(with: (y: 10, x: 0)).y
        }
        XCTAssertEqual(filter.pending.y, input - output, accuracy: 1e-9)
        XCTAssertGreaterThan(filter.pending.y, 0)
        for _ in 0..<40 {
            input += 10
            output += filter.passThrough(with: (y: 10, x: 0), catchUp: 0.3).y
        }
        XCTAssertEqual(output, input, accuracy: 1e-3)
    }

    func testFilterPassThrough_withNothingPendingIsIdentityAndResumesSmoothly() {
        let filter = ScrollFilter()
        let out = filter.passThrough(with: (y: 12, x: -3), catchUp: 0.5)
        XCTAssertEqual(out.y, 12)
        XCTAssertEqual(out.x, -3)
        // Re-enabling the filter continues from the last output instead of restarting at 0.
        XCTAssertEqual(filter.fill(with: (y: 12, x: -3)).y, 12, accuracy: 1e-12)
        filter.reset()
        XCTAssertEqual(filter.pending.y, 0)
    }

    // MARK: - Lead cap

    func testLeadCap_values() {
        // No speed yet: two notches, or the event itself if larger
        XCTAssertEqual(ScrollLeadLimiter.cap(notch: 90, distance: 90, inputSpeed: 0, timeConstant: 0.066), 180)
        XCTAssertEqual(ScrollLeadLimiter.cap(notch: 90, distance: -900, inputSpeed: 0, timeConstant: 0.066), 900)
        // 10 000 px/s × max(120 ms, 1.5 τ)
        XCTAssertEqual(ScrollLeadLimiter.cap(notch: 90, distance: 90, inputSpeed: 10_000, timeConstant: 0.066), 1200, accuracy: 1e-9)
        XCTAssertEqual(ScrollLeadLimiter.cap(notch: 90, distance: 90, inputSpeed: 10_000, timeConstant: 0.187), 2805, accuracy: 1e-9)

        XCTAssertEqual(ScrollLeadLimiter.limit(buffer: 1000, current: 100, cap: 300), 400)
        XCTAssertEqual(ScrollLeadLimiter.limit(buffer: -1000, current: -100, cap: 300), -400)
        XCTAssertEqual(ScrollLeadLimiter.limit(buffer: 350, current: 100, cap: 300), 350)
    }

    func testLeadLimiter_measuresInputSpeedPerRun() {
        var limiter = ScrollLeadLimiter()
        let tau = 0.066  // gap that ends a run: 3 τ = 0.198 s
        XCTAssertEqual(limiter.register(distance: 100, at: 0, timeConstant: tau), 0)
        XCTAssertEqual(limiter.register(distance: 100, at: 0.01, timeConstant: tau), 10_000, accuracy: 1e-6)
        XCTAssertEqual(limiter.register(distance: 100, at: 0.02, timeConstant: tau), 10_000, accuracy: 1e-6)
        XCTAssertEqual(limiter.register(distance: -100, at: 0.03, timeConstant: tau), 0, "direction change starts a new run")
        XCTAssertEqual(limiter.register(distance: -100, at: 0.04, timeConstant: tau), 10_000, accuracy: 1e-6)
        XCTAssertEqual(limiter.register(distance: -100, at: 0.25, timeConstant: tau), 0, "a pause starts a new run")
        // A slow Duration keeps notches 0.2 s apart in one run.
        XCTAssertEqual(limiter.register(distance: -100, at: 0.45, timeConstant: 0.37), 500, accuracy: 1e-6)
    }

    /// Steady scrolling at any rate and Duration is never cut: the buffer holds every event.
    func testLeadCap_neverCutsSteadyScrolling() {
        let notch = 33.6 * 2.7
        for duration in [1.0, 2.0, 3.13, 4.35, ScrollDurationLimits.simulateTrackpadDefault] {
            for interval in [0.008, 0.016, 0.033, 0.05, 0.1, 0.2] {
                let poster = ScrollPoster()
                let frame = 1.0 / 60.0
                var nextFrame = frame
                var events = 0
                var time = 0.0
                while time < 2 {
                    while nextFrame <= time {
                        _ = poster.advanceForTests(frameInterval: frame, now: nextFrame)
                        nextFrame += frame
                    }
                    poster.applyInputForTests(input(notch, notch: notch, duration: duration), at: time)
                    events += 1
                    time += interval
                }
                XCTAssertEqual(poster.motionStateForTests.buffer.y, Double(events) * notch, accuracy: 1e-6,
                               "duration \(duration) interval \(interval)")
            }
        }
    }

    /// A fast spin followed by a slow notch: the leftover glide of the fast part is dropped.
    func testLeadCap_slowingWheelDropsLeftoverGlide() {
        let notch = 33.6 * 2.7
        let poster = ScrollPoster()
        let frame = 1.0 / 60.0
        var nextFrame = frame
        var time = 0.0
        func advance(to t: Double) {
            while nextFrame <= t {
                _ = poster.advanceForTests(frameInterval: frame, now: nextFrame)
                nextFrame += frame
            }
        }
        while time < 0.5 {  // 200 events/s ≈ 18 000 px/s
            advance(to: time)
            poster.applyInputForTests(input(notch, notch: notch, duration: 4.35), at: time)
            time += 0.005
        }
        let lastFast = time - 0.005
        advance(to: lastFast + 0.12)
        let before = poster.motionStateForTests
        let uncappedLead = before.buffer.y - before.current.y + notch
        poster.applyInputForTests(input(notch, notch: notch, duration: 4.35), at: lastFast + 0.12)
        let after = poster.motionStateForTests
        let lead = after.buffer.y - after.current.y
        // speed over the last 3 intervals (5 ms, 5 ms, 120 ms) × the horizon of 1.5 time constants
        let horizon = 1.5 * ScrollMotion.responseTimeConstant(forTransition: transition(4.35))
        XCTAssertGreaterThan(horizon, ScrollLeadLimiter.minimumHorizon)
        let expectedCap = 3 * notch / 0.13 * horizon
        XCTAssertEqual(lead, expectedCap, accuracy: 1e-6)
        XCTAssertLessThan(lead, uncappedLead)
    }

    func testLeadCap_neverCutsASingleEvent() {
        let poster = ScrollPoster()
        poster.applyInputForTests(input(5000, notch: 90, duration: 3.13), at: 0)
        XCTAssertEqual(poster.motionStateForTests.buffer.y, 5000)
    }

    func testDirectionReversal_restartsFromTheNewEvent() {
        let poster = ScrollPoster()
        poster.applyInputForTests(input(300, duration: 3.13), at: 0)
        _ = poster.advanceForTests(frameInterval: 1.0 / 60.0, now: 0.016)
        _ = poster.advanceForTests(frameInterval: 1.0 / 60.0, now: 0.033)
        poster.applyInputForTests(input(-90, duration: 3.13), at: 0.04)
        let state = poster.motionStateForTests
        XCTAssertEqual(state.buffer.y, -90)
        XCTAssertEqual(state.current.y, 0)
    }

    // MARK: - Tail

    /// A late "finish the tail" step used to push a few pixels out long after the page had
    /// come to rest (a visible twitch after every short scroll). After its peak the motion
    /// only ever slows down.
    func testSingleNotch_onlySlowsDownAfterItsPeak_noLateKick() {
        for duration in [1.0, 2.0, 3.13, 4.35] {
            let poster = ScrollPoster()
            let start = 100.0
            poster.applyInputForTests(input(90.72, duration: duration), at: start)
            var now = start
            var frames: [Double] = []
            while now - start < 3 {
                now += 1.0 / 60.0
                frames.append(poster.advanceForTests(frameInterval: 1.0 / 60.0, now: now).y)
            }
            let peak = frames.firstIndex(of: frames.max() ?? 0) ?? 0
            for index in (peak + 1)..<frames.count {
                XCTAssertLessThanOrEqual(frames[index], frames[index - 1] + 1e-12, "duration \(duration), frame \(index)")
            }
            XCTAssertEqual(frames.reduce(0, +), 90.72, accuracy: 1e-3, "duration \(duration): no distance lost")
        }
    }

    // MARK: - Landing

    func testLanding_leavesFastMotionAlone() {
        XCTAssertNil(ScrollLanding.step(output: 5, remaining: 40, direction: 1, interval: 1.0 / 60.0))
        XCTAssertNil(ScrollLanding.step(output: 1, remaining: 40, direction: 1, interval: 1.0 / 60.0), "exactly the landing speed")
        XCTAssertNil(ScrollLanding.step(output: 0, remaining: 0, direction: 1, interval: 1.0 / 60.0), "already at rest")
        XCTAssertNil(ScrollLanding.step(output: 0, remaining: 0, direction: 0, interval: 1.0 / 60.0), "already at rest")
    }

    func testLanding_holdsOnePixelPer60HzFrameAndEndsOnTarget() {
        var remaining = 3.6
        var output = 0.4
        var sent: [Double] = []
        while let step = ScrollLanding.step(output: output, remaining: remaining, direction: 1, interval: 1.0 / 60.0) {
            sent.append(step.output)
            remaining = step.remaining
            output = 0
        }
        XCTAssertEqual(sent.count, 4)
        XCTAssertEqual(sent[0], 1, accuracy: 1e-12)
        XCTAssertEqual(sent[1], 1, accuracy: 1e-12)
        XCTAssertEqual(sent[2], 1, accuracy: 1e-12)
        XCTAssertEqual(sent[3], 1, accuracy: 1e-9)
        XCTAssertEqual(sent.reduce(0, +), 4.0, accuracy: 1e-9, "everything that was left, nothing more")
        XCTAssertEqual(remaining, 0, accuracy: 1e-9)
    }

    func testLanding_onTargetTheLeftoverOutputIsNotSent() {
        // The filter still eases out although everything has been sent: no overshoot.
        let done = ScrollLanding.step(output: 0.3, remaining: -0.3, direction: 1, interval: 1.0 / 60.0)
        XCTAssertEqual(done?.output, 0)
        XCTAssertEqual(done?.remaining, 0)
    }

    func testLanding_neverMovesAgainstTheDirectionOfTravel() {
        // More was sent than came in (rounding, a change of settings mid-motion): stop, do not go back.
        let overshot = ScrollLanding.step(output: 0, remaining: -2, direction: 1, interval: 1.0 / 60.0)
        XCTAssertEqual(overshot?.output, 0)
        XCTAssertEqual(overshot?.remaining, 0)
        let stillEasing = ScrollLanding.step(output: 0.4, remaining: -2, direction: 1, interval: 1.0 / 60.0)
        XCTAssertEqual(stillEasing?.output, 0)
        // The last input was on the other axis: what this axis still holds is dropped.
        let otherAxis = ScrollLanding.step(output: 0.4, remaining: 1.2, direction: 0, interval: 1.0 / 60.0)
        XCTAssertEqual(otherAxis?.output, 0)
        XCTAssertEqual(otherAxis?.remaining, 0)
    }

    func testLanding_keepsTheDirectionAndTheSpeedAtAnyFrameRate() {
        let down = ScrollLanding.step(output: -0.2, remaining: -7, direction: -1, interval: 1.0 / 60.0)
        XCTAssertEqual(down?.output ?? 0, -1, accuracy: 1e-12)
        XCTAssertEqual(down?.remaining ?? 0, -6.2, accuracy: 1e-12)
        let fast = ScrollLanding.step(output: 0.2, remaining: 7, direction: 1, interval: 1.0 / 120.0)
        XCTAssertEqual(fast?.output ?? 0, 0.5, accuracy: 1e-12, "60 px/s at 120 Hz")
        XCTAssertNil(ScrollLanding.step(output: 0.6, remaining: 7, direction: 1, interval: 1.0 / 120.0), "faster than 60 px/s at 120 Hz")
    }

    func testLanding_classicGesturesNeverLand() {
        // Momentum off: frames under the dead zone are not posted at all, so the motion keeps
        // the plain exponential ending.
        let poster = ScrollPoster()
        let start = 100.0
        poster.applyInputForTests(input(90.72, duration: 4.35), at: start)
        var now = start
        var frames: [Double] = []
        while now - start < 3 {
            now += 1.0 / 60.0
            frames.append(poster.advanceForTests(frameInterval: 1.0 / 60.0, now: now).y)
        }
        let slow = frames.filter { $0 > 0 && $0 < 0.99 }
        XCTAssertGreaterThan(slow.count, 20, "the exponential tail runs on below one pixel per frame")
    }

    func testTailGap_isLongerForSlowDurations() {
        XCTAssertEqual(ScrollLeadLimiter.tailGap(timeConstant: 0.02), ScrollLeadLimiter.minimumTailGap)
        XCTAssertEqual(ScrollLeadLimiter.tailGap(timeConstant: 0.187), 0.561, accuracy: 1e-9)
    }

    // MARK: - Event clock

    func testEventClock_readsMachTicks() {
        let now: UInt64 = 10_000_000_000
        let ts = now - 1_000
        let seconds = ScrollEventClock.seconds(fromTimestamp: ts, now: now)
        XCTAssertEqual(seconds ?? -1, Double(ts) * ScrollEventClock.secondsPerTick, accuracy: 1e-12)
    }

    func testEventClock_acceptsNanosecondTimestamps() {
        let now: UInt64 = 10_000_000_000
        let nowSeconds = Double(now) * ScrollEventClock.secondsPerTick
        let nanoseconds = UInt64(nowSeconds * 1_000_000_000)
        let seconds = ScrollEventClock.seconds(fromTimestamp: nanoseconds, now: now)
        XCTAssertEqual(seconds ?? -1, nowSeconds, accuracy: 1e-6)
    }

    func testEventClock_rejectsZeroAndFutureTimestamps() {
        XCTAssertNil(ScrollEventClock.seconds(fromTimestamp: 0, now: 1_000))
        XCTAssertNil(ScrollEventClock.seconds(fromTimestamp: UInt64.max / 2, now: 1_000_000))
        XCTAssertEqual(ScrollEventClock.seconds(fromTimestamp: 0), CACurrentMediaTime(), accuracy: 0.05, "falls back to now")
    }
}
