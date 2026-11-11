//
//  ScrollMotionTests.swift
//  MosTests
//
//  Frame-rate independent smoothing, the filter, lead cap, the tail and the event clock.
//

import XCTest
import QuartzCore
@testable import Mos_Debug

final class ScrollMotionTests: XCTestCase {

    private func transition(_ duration: Double) -> Double {
        return OPTIONS_SCROLL_DEFAULT.generateDurationTransition(with: duration)
    }

    private func input(_ y: Double, notch: Double = 90.72, duration: Double) -> ScrollPosterInput {
        return ScrollPosterInput(y: y, x: 0, notch: notch, duration: transition(duration))
    }

    /// Time until less than 1 px of a 500 px move is left to emit, at `rate` Hz.
    private func settleTime(rate: Double, duration: Double) -> (time: Double, emitted: Double) {
        let poster = ScrollPoster()
        poster.applyInputForTests(input(500, duration: duration), at: 0)
        let dt = 1 / rate
        var time = 0.0
        var emitted = 0.0
        var settledAt: Double?
        while time < 10 {
            time += dt
            emitted += poster.advanceForTests(frameInterval: dt).y
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
        for duration in [0.5, 1.5, 3.13, 4.35, 4.5] {
            let at60 = settleTime(rate: 60, duration: duration)
            let at120 = settleTime(rate: 120, duration: duration)
            let at144 = settleTime(rate: 144, duration: duration)
            // One 60 Hz frame of sampling, a little more with the filter's own sampling.
            let tolerance = 1.5 / 60.0
            XCTAssertEqual(at120.time, at60.time, accuracy: tolerance, "duration \(duration)")
            XCTAssertEqual(at144.time, at60.time, accuracy: tolerance, "duration \(duration)")
            XCTAssertEqual(at60.emitted, 500, accuracy: 1e-6, "no distance lost")
            XCTAssertEqual(at120.emitted, 500, accuracy: 1e-6, "no distance lost")
        }
    }

    // MARK: - Filter

    func testFilterWeight_followsTheSmoothingButNeverSlowerThanClassic() {
        XCTAssertEqual(ScrollMotion.filterWeight(forTransition: transition(4.35)), 0.23, "default keeps the classic filter")
        XCTAssertEqual(ScrollMotion.filterWeight(forTransition: transition(3.13)), 0.23, "Smooth keeps the classic filter")
        XCTAssertEqual(ScrollMotion.filterWeight(forTransition: transition(2.0)), transition(2.0), "Balanced: as fast as its lerp")
        XCTAssertEqual(ScrollMotion.filterWeight(forTransition: transition(1.0)), transition(1.0), "Direct: as fast as its lerp")
        XCTAssertEqual(ScrollMotion.filterWeight(forTransition: 1), 1)
        XCTAssertEqual(ScrollMotion.filterWeight(forTransition: .nan), 0.23)
    }

    /// The page answers the wheel at once, however long it glides afterwards: the top speed
    /// comes within the filter's time, not a whole Duration later.
    func testNotch_answersAtOnceAtLongDurations() {
        for duration in [4.35, 4.5, 4.75] {
            let poster = ScrollPoster()
            poster.applyInputForTests(input(100, duration: duration), at: 0)
            var frames: [Double] = []
            for _ in 0..<240 {
                frames.append(poster.advanceForTests(frameInterval: 1.0 / 120.0).y)
            }
            let peakTime = Double((frames.firstIndex(of: frames.max() ?? 0) ?? 0) + 1) / 120.0
            XCTAssertLessThan(peakTime, 0.14, "duration \(duration)")
        }
    }

    /// Every notch is softened on its first frame (no jump), without a frame of delay.
    func testNotch_startsWithoutAJumpAndWithoutDelay() {
        for duration in [1.0, 2.0, 3.13, 4.35] {
            let trans = transition(duration)
            let poster = ScrollPoster()
            poster.applyInputForTests(input(90.72, duration: duration), at: 0)
            var frames: [Double] = []
            for _ in 0..<12 {
                frames.append(poster.advanceForTests(frameInterval: 1.0 / 60.0).y)
            }
            let first = frames[0]
            XCTAssertGreaterThan(first, 0, "moves on the first frame (duration \(duration))")
            XCTAssertEqual(first, 90.72 * trans * ScrollMotion.filterWeight(forTransition: trans), accuracy: 1e-9)
            if duration >= 2.0 {
                // (At Duration 1 the whole bump is shorter than two frames.)
                XCTAssertGreaterThan(frames[1], first, "still speeding up on the second frame (duration \(duration))")
            }
        }
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

    /// Real frame intervals jitter, so the filter's weight changes from frame to frame. The
    /// catch-up release keeps the distance within a fraction of a pixel anyway (without it,
    /// this run ends about 150 px off). What is left is a little too much, never too little:
    /// the release never turns the motion around to take it back.
    func testJitteryFrames_loseNoDistance() {
        let poster = ScrollPoster()
        let intervals = [1.0 / 60.0, 1.0 / 45.0, 1.0 / 90.0, 1.0 / 60.0, 1.0 / 120.0, 1.0 / 30.0]
        var time = 0.0
        var emitted = 0.0
        for index in 0..<600 {
            if index < 40 && index % 4 == 0 {
                poster.applyInputForTests(input(90.72, duration: 4.35), at: time)
            }
            let dt = intervals[index % intervals.count]
            time += dt
            emitted += poster.advanceForTests(frameInterval: dt).y
        }
        let target = poster.motionStateForTests.buffer.y
        XCTAssertGreaterThan(target, 9 * 90.72)
        XCTAssertEqual(emitted, target, accuracy: 0.1)
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
        for duration in [1.0, 2.0, 3.13, 4.35, 4.75] {
            for interval in [0.008, 0.016, 0.033, 0.05, 0.1, 0.2] {
                let poster = ScrollPoster()
                let frame = 1.0 / 60.0
                var nextFrame = frame
                var events = 0
                var time = 0.0
                while time < 2 {
                    while nextFrame <= time {
                        _ = poster.advanceForTests(frameInterval: frame)
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
                _ = poster.advanceForTests(frameInterval: frame)
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
        let horizon = 1.5 * ScrollMotion.timeConstant(forTransition: transition(4.35))
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
        _ = poster.advanceForTests(frameInterval: 1.0 / 60.0)
        _ = poster.advanceForTests(frameInterval: 1.0 / 60.0)
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
                frames.append(poster.advanceForTests(frameInterval: 1.0 / 60.0).y)
            }
            let peak = frames.firstIndex(of: frames.max() ?? 0) ?? 0
            for index in (peak + 1)..<frames.count {
                XCTAssertLessThanOrEqual(frames[index], frames[index - 1] + 1e-12, "duration \(duration), frame \(index)")
            }
            XCTAssertEqual(frames.reduce(0, +), 90.72, accuracy: 1e-3, "duration \(duration): no distance lost")
        }
    }

    /// The motion keeps its plain exponential ending: it runs on below one pixel per frame
    /// (ScrollPoster does not post those frames, see the dead zone), nothing hurries it home.
    func testTail_runsOnBelowOnePixelPerFrame() {
        let poster = ScrollPoster()
        let start = 100.0
        poster.applyInputForTests(input(90.72, duration: 4.35), at: start)
        var now = start
        var frames: [Double] = []
        while now - start < 3 {
            now += 1.0 / 60.0
            frames.append(poster.advanceForTests(frameInterval: 1.0 / 60.0).y)
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
