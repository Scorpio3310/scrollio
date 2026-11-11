//
//  ScrollTuningTests.swift
//  MosTests
//
//  Free-spin detection (ScrollSpinTracker), tuning resolution and the settings contract.
//

import XCTest
@testable import Mos_Debug

final class ScrollTuningTests: XCTestCase {

    // MARK: - Helpers

    /// Registers `count` events of `lines` lines, `interval` seconds apart, starting at `start`.
    @discardableResult
    private func spin(_ tracker: inout ScrollSpinTracker, lines: Double, count: Int, interval: Double, start: Double) -> (state: ScrollSpinState, end: Double) {
        var state = tracker.state
        var time = start
        for i in 0..<count {
            time = start + Double(i) * interval
            state = tracker.register(lines: lines, at: time)
        }
        return (state, time)
    }

    private let smooth = OPTIONS_SCROLL_DEFAULT.generateDurationTransition(with: 3.13)

    // MARK: - Tracker: rate in lines per second

    func testTracker_firstEventIsIdle() {
        var tracker = ScrollSpinTracker()
        let state = tracker.register(lines: 1, at: 10)
        XCTAssertEqual(state, .idle)
    }

    func testTracker_measuresLinesPerSecondNotEvents() {
        var tracker = ScrollSpinTracker()
        // 4 lines per event, 50 events/s → 200 lines/s
        let state = spin(&tracker, lines: 4, count: 4, interval: 0.02, start: 0).state
        XCTAssertEqual(state.lineRate, 200, accuracy: 1e-6)
    }

    func testTracker_ratchetSpeedNeverBlends() {
        var tracker = ScrollSpinTracker()
        // A hard ratchet flick: 15 lines/s
        let state = spin(&tracker, lines: 1, count: 20, interval: 1.0 / 15.0, start: 0).state
        XCTAssertEqual(state.lineRate, 15, accuracy: 1e-6)
        XCTAssertEqual(state.freeSpinBlend, 0)
        XCTAssertFalse(state.isFreeSpin)
    }

    // MARK: - Tracker: blend between 20 and 40 lines/s

    func testTracker_blendRampsBetween20And40LinesPerSecond() {
        var tracker = ScrollSpinTracker()
        let at30 = spin(&tracker, lines: 1, count: 6, interval: 1.0 / 30.0, start: 0).state
        XCTAssertEqual(at30.freeSpinBlend, 0.5, accuracy: 1e-6, "smoothstep(0.5)")
        XCTAssertFalse(at30.isFreeSpin)

        tracker.reset()
        let at25 = spin(&tracker, lines: 1, count: 6, interval: 1.0 / 25.0, start: 0).state
        XCTAssertEqual(at25.freeSpinBlend, 0.15625, accuracy: 1e-6, "smoothstep(0.25)")

        tracker.reset()
        let at19 = spin(&tracker, lines: 1, count: 6, interval: 1.0 / 19.0, start: 0).state
        XCTAssertEqual(at19.freeSpinBlend, 0)
    }

    func testTracker_needsTwoIntervalsBeforeBlending() {
        var tracker = ScrollSpinTracker()
        tracker.register(lines: 5, at: 0)
        let second = tracker.register(lines: 5, at: 0.01)
        XCTAssertEqual(second.freeSpinBlend, 0, "one interval is not trusted")
        let third = tracker.register(lines: 5, at: 0.02)
        XCTAssertEqual(third.freeSpinBlend, 1)
    }

    // MARK: - Tracker: latch

    func testTracker_latchesAfterEnoughLinesAndHoldsWhileSlowingDown() {
        var tracker = ScrollSpinTracker()
        // 2 lines every 20 ms = 100 lines/s; latch once 12 lines are in the run (6th event)
        var result = spin(&tracker, lines: 2, count: 5, interval: 0.02, start: 0)
        XCTAssertEqual(result.state.freeSpinBlend, 1)
        XCTAssertFalse(result.state.isFreeSpin, "10 lines are not enough to latch")
        result = spin(&tracker, lines: 2, count: 1, interval: 0.02, start: result.end + 0.02)
        XCTAssertTrue(result.state.isFreeSpin)

        // The wheel slows down to 8 lines/s: still free-spin (no exit at a lower rate)
        result = spin(&tracker, lines: 1, count: 5, interval: 0.125, start: result.end + 0.125)
        XCTAssertEqual(result.state.lineRate, 8, accuracy: 1e-6)
        XCTAssertTrue(result.state.isFreeSpin)
        XCTAssertEqual(result.state.freeSpinBlend, 1)
    }

    func testTracker_pauseEndsFreeSpin() {
        var tracker = ScrollSpinTracker()
        let latched = spin(&tracker, lines: 3, count: 6, interval: 0.01, start: 0)
        XCTAssertTrue(latched.state.isFreeSpin)
        let afterPause = tracker.register(lines: 3, at: latched.end + ScrollSpinTracker.idleGap + 0.01)
        XCTAssertEqual(afterPause, .idle)
    }

    func testTracker_directionChangeEndsFreeSpin() {
        var tracker = ScrollSpinTracker()
        let latched = spin(&tracker, lines: 3, count: 6, interval: 0.01, start: 0)
        XCTAssertTrue(latched.state.isFreeSpin)
        let reversed = tracker.register(lines: -3, at: latched.end + 0.01)
        XCTAssertEqual(reversed, .idle)
        XCTAssertFalse(tracker.state.isFreeSpin)
    }

    func testTracker_freezesAccelerationRateWhileLatched() {
        var tracker = ScrollSpinTracker()
        let latched = spin(&tracker, lines: 3, count: 6, interval: 0.02, start: 0)  // 150 lines/s
        XCTAssertTrue(latched.state.isFreeSpin)
        XCTAssertEqual(latched.state.accelerationRate, 150, accuracy: 1e-6)
        let faster = spin(&tracker, lines: 6, count: 4, interval: 0.01, start: latched.end + 0.01).state
        XCTAssertGreaterThan(faster.lineRate, 500)
        XCTAssertEqual(faster.accelerationRate, 150, accuracy: 1e-6)
    }

    // MARK: - Tracker: interval clamp and sign 0

    func testTracker_clampsIntervalsOfCoalescedEvents() {
        var tracker = ScrollSpinTracker()
        tracker.register(lines: 1, at: 1)
        tracker.register(lines: 1, at: 1)
        let state = tracker.register(lines: 1, at: 1)
        XCTAssertEqual(state.lineRate, 2 / (2 * ScrollSpinTracker.minimumInterval), accuracy: 1e-6)
        XCTAssertTrue(state.lineRate.isFinite)
    }

    func testTracker_clampsBackwardTimestamps() {
        var tracker = ScrollSpinTracker()
        tracker.register(lines: 1, at: 1.0)
        let state = tracker.register(lines: 1, at: 0.99)
        XCTAssertEqual(state.lineRate, 1 / ScrollSpinTracker.minimumInterval, accuracy: 1e-6)
        // The newest time stays 1.0, so the next interval is measured from there.
        let next = tracker.register(lines: 1, at: 1.1)
        XCTAssertEqual(next.lineRate, 2 / (ScrollSpinTracker.minimumInterval + 0.1), accuracy: 1e-6)
    }

    func testTracker_zeroLinesLeaveStateAndTimingUntouched() {
        var tracker = ScrollSpinTracker()
        tracker.register(lines: 1, at: 0)
        let before = tracker.register(lines: 1, at: 0.02)
        XCTAssertEqual(tracker.register(lines: 0, at: 0.10), before)
        // Same run continues, measured from 0.02 (not from the ignored event at 0.10)
        let after = tracker.register(lines: 1, at: 0.14)
        XCTAssertEqual(after.lineRate, 2 / 0.14, accuracy: 1e-6)
    }

    // MARK: - Resolve

    func testResolve_idleKeepsRegularSettings() {
        let settings = ScrollTuningSettings.default
        let r = settings.resolve(speed: 2.7, durationTransition: smooth, spin: .idle)
        XCTAssertEqual(r.multiplier, 1)
        XCTAssertEqual(r.speed, 2.7, accuracy: 1e-12)
        XCTAssertEqual(r.durationTransition, smooth)
        XCTAssertEqual(r.freeSpinBlend, 0)
    }

    func testResolve_dashAloneIsUnchanged() {
        let r = ScrollTuningSettings.default.resolve(speed: 2.7, durationTransition: smooth, spin: .idle, amplification: 5)
        XCTAssertEqual(r.multiplier, 5)
        XCTAssertEqual(r.speed, 13.5, accuracy: 1e-12)
    }

    func testResolve_freeSpinUsesFreeSpinSpeedAndSmoothness() {
        let settings = ScrollTuningSettings(freeSpinEnabled: true, freeSpinSmoothness: 1.5, freeSpinSpeed: 0.7, acceleration: 0)
        let spinning = ScrollSpinState(lineRate: 120, freeSpinBlend: 1, isFreeSpin: true, accelerationRate: 120)
        let r = settings.resolve(speed: 2.7, durationTransition: smooth, spin: spinning)
        XCTAssertEqual(r.multiplier, 0.7, accuracy: 1e-12)
        XCTAssertEqual(r.durationTransition, OPTIONS_SCROLL_DEFAULT.generateDurationTransition(with: 1.5), accuracy: 1e-12)
        XCTAssertEqual(r.freeSpinBlend, 1)
    }

    func testResolve_partialBlendInterpolates() {
        let settings = ScrollTuningSettings(freeSpinEnabled: true, freeSpinSmoothness: 1.5, freeSpinSpeed: 0.5, acceleration: 0)
        let half = ScrollSpinState(lineRate: 30, freeSpinBlend: 0.5, isFreeSpin: false, accelerationRate: 30)
        let r = settings.resolve(speed: 2.0, durationTransition: smooth, spin: half)
        XCTAssertEqual(r.multiplier, 0.75, accuracy: 1e-12)
        let freeSpinDuration = OPTIONS_SCROLL_DEFAULT.generateDurationTransition(with: 1.5)
        XCTAssertEqual(r.durationTransition, (smooth + freeSpinDuration) / 2, accuracy: 1e-12)
    }

    /// The long Duration "Trackpad-style events" used to force gets the free-spin smoothness
    /// like any other Duration (there is no trackpad-style exception any more).
    func testResolve_longDurationStillGetsFreeSpinSmoothness() {
        let settings = ScrollTuningSettings(freeSpinEnabled: true, freeSpinSmoothness: 1.5, freeSpinSpeed: 0.7, acceleration: 0)
        let spinning = ScrollSpinState(lineRate: 120, freeSpinBlend: 1, isFreeSpin: true, accelerationRate: 120)
        let long = OPTIONS_SCROLL_DEFAULT.generateDurationTransition(with: 4.75)
        let r = settings.resolve(speed: 2.7, durationTransition: long, spin: spinning)
        XCTAssertEqual(r.durationTransition, OPTIONS_SCROLL_DEFAULT.generateDurationTransition(with: 1.5), accuracy: 1e-12)
        XCTAssertEqual(r.multiplier, 0.7, accuracy: 1e-12)
    }

    func testResolve_freeSpinDisabledIgnoresBlend() {
        let settings = ScrollTuningSettings(freeSpinEnabled: false, freeSpinSmoothness: 0.5, freeSpinSpeed: 3, acceleration: 0)
        let spinning = ScrollSpinState(lineRate: 120, freeSpinBlend: 1, isFreeSpin: true, accelerationRate: 120)
        let r = settings.resolve(speed: 2.7, durationTransition: smooth, spin: spinning)
        XCTAssertEqual(r.multiplier, 1)
        XCTAssertEqual(r.durationTransition, smooth)
        XCTAssertEqual(r.freeSpinBlend, 0)
    }

    func testResolve_capsCombinedMultiplier() {
        let settings = ScrollTuningSettings(freeSpinEnabled: true, freeSpinSmoothness: 1.5, freeSpinSpeed: 3, acceleration: 1)
        let spinning = ScrollSpinState(lineRate: 200, freeSpinBlend: 1, isFreeSpin: true, accelerationRate: 200)
        // 3 (acceleration) × 3 (free-spin speed) × 5 (dash) = 45
        let r = settings.resolve(speed: 2.7, durationTransition: smooth, spin: spinning, amplification: 5)
        XCTAssertEqual(r.multiplier, ScrollTuningSettings.maximumCombinedMultiplier)
        XCTAssertEqual(r.speed, 2.7 * ScrollTuningSettings.maximumCombinedMultiplier, accuracy: 1e-12)
    }

    func testAccelerationFactor_smoothstepBetween6And60LinesPerSecond() {
        let settings = ScrollTuningSettings(freeSpinEnabled: true, freeSpinSmoothness: 1.5, freeSpinSpeed: 1, acceleration: 1)
        XCTAssertEqual(settings.accelerationFactor(lineRate: 0), 1)
        XCTAssertEqual(settings.accelerationFactor(lineRate: 6), 1)
        XCTAssertEqual(settings.accelerationFactor(lineRate: 33), 2, accuracy: 1e-12, "half way: 1 + 2 × 0.5")
        XCTAssertEqual(settings.accelerationFactor(lineRate: 60), 3, accuracy: 1e-12)
        XCTAssertEqual(settings.accelerationFactor(lineRate: 600), 3, accuracy: 1e-12)
        let off = ScrollTuningSettings.default
        XCTAssertEqual(off.accelerationFactor(lineRate: 60), 1)
    }

    // MARK: - Free-spin distance from line count

    func testVerticalDistance_usesLineCountInFreeSpin() {
        let full = ScrollTuningResolution(multiplier: 1, speed: 2.7, durationTransition: 0.4, freeSpinBlend: 1)
        // macOS-accelerated pointDelta 420 px for a 5-line event → 5 × 33.6
        XCTAssertEqual(full.verticalDistance(regular: -420, lines: 5, step: 33.6), -168, accuracy: 1e-9)
        XCTAssertEqual(full.verticalDistance(regular: 420, lines: -5, step: 33.6), 168, accuracy: 1e-9, "sign follows the (reversed) regular value")

        let half = ScrollTuningResolution(multiplier: 1, speed: 2.7, durationTransition: 0.4, freeSpinBlend: 0.5)
        XCTAssertEqual(half.verticalDistance(regular: 420, lines: 5, step: 33.6), 294, accuracy: 1e-9)

        let none = ScrollTuningResolution(multiplier: 1, speed: 2.7, durationTransition: 0.4, freeSpinBlend: 0)
        XCTAssertEqual(none.verticalDistance(regular: 420, lines: 5, step: 33.6), 420)
    }

    func testLineDelta_prefersIntegerLines() throws {
        func axis(fix: Int64, fixPt: Double, pt: Double) throws -> axisData {
            let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 0, wheel2: 0, wheel3: 0))
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: fix)
            event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: pt)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: fixPt)
            return ScrollEvent(with: event).Y
        }
        XCTAssertEqual(try axis(fix: 3, fixPt: 7.5, pt: 75).lineDelta, 3)
        XCTAssertEqual(try axis(fix: -2, fixPt: -6, pt: -60).lineDelta, -2)
        XCTAssertEqual(try axis(fix: 0, fixPt: 0.5, pt: 5).lineDelta, 0.5, accuracy: 1e-4)
        XCTAssertEqual(try axis(fix: 0, fixPt: 0, pt: 20).lineDelta, 2, accuracy: 1e-9)
    }

    // MARK: - Poster input from ScrollCore

    func testPosterInput_appliesPerAxisSpeedAndFreeSpinBypass() {
        let vertical = ScrollTuningResolution(multiplier: 0.7, speed: 1.89, durationTransition: 0.463, freeSpinBlend: 1)
        let horizontal = ScrollTuningResolution(multiplier: 1, speed: 2.7, durationTransition: smooth, freeSpinBlend: 0)
        let input = ScrollCore.posterInput(y: 168, x: 33.6, step: 33.6, vertical: vertical, horizontal: horizontal)
        XCTAssertEqual(input.y, 168 * 1.89, accuracy: 1e-9)
        XCTAssertEqual(input.x, 33.6 * 2.7, accuracy: 1e-9)
        XCTAssertEqual(input.notch.y, 33.6 * 1.89, accuracy: 1e-9)
        XCTAssertEqual(input.notch.x, 33.6 * 2.7, accuracy: 1e-9)
        XCTAssertEqual(input.duration, 0.463)
        XCTAssertTrue(input.bypassFilter)

        let thumbOnly = ScrollCore.posterInput(y: 0, x: 33.6, step: 33.6, vertical: vertical, horizontal: horizontal)
        XCTAssertEqual(thumbOnly.duration, smooth)
        XCTAssertFalse(thumbOnly.bypassFilter, "Duration 3.13 keeps the filter outside free-spin")
    }

    // MARK: - Settings contract

    func testSettings_encodesExactlyTheFourContractFields() throws {
        let data = try JSONEncoder().encode(ScrollTuningSettings.default)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["freeSpinEnabled", "freeSpinSmoothness", "freeSpinSpeed", "acceleration"])
    }

    func testSettings_decodingIsTolerant() throws {
        let partial = try JSONDecoder().decode(ScrollTuningSettings.self, from: Data(#"{"freeSpinSpeed": 9, "acceleration": -1, "future": 1}"#.utf8))
        XCTAssertEqual(partial.freeSpinEnabled, ScrollTuningSettings.default.freeSpinEnabled)
        XCTAssertEqual(partial.freeSpinSmoothness, ScrollTuningSettings.default.freeSpinSmoothness)
        XCTAssertEqual(partial.freeSpinSpeed, 3)
        XCTAssertEqual(partial.acceleration, 0)
    }

    func testPresetValuesStayWithinRanges() {
        // Presets shipped by the UI package (Duration in 60 Hz terms).
        let presets: [(duration: Double, settings: ScrollTuningSettings)] = [
            (1.0, ScrollTuningSettings(freeSpinEnabled: true, freeSpinSmoothness: 0.5, freeSpinSpeed: 0.8, acceleration: 0)),
            (2.0, ScrollTuningSettings(freeSpinEnabled: true, freeSpinSmoothness: 1.0, freeSpinSpeed: 0.8, acceleration: 0)),
            (3.13, ScrollTuningSettings(freeSpinEnabled: true, freeSpinSmoothness: 1.5, freeSpinSpeed: 0.7, acceleration: 0)),
            (4.35, ScrollTuningSettings(freeSpinEnabled: true, freeSpinSmoothness: 2.5, freeSpinSpeed: 1.0, acceleration: 0.3)),
        ]
        let spinning = ScrollSpinState(lineRate: 300, freeSpinBlend: 1, isFreeSpin: true, accelerationRate: 300)
        for preset in presets {
            let regular = OPTIONS_SCROLL_DEFAULT.generateDurationTransition(with: preset.duration)
            let r = preset.settings.resolve(speed: 2.7, durationTransition: regular, spin: spinning, amplification: 5)
            XCTAssertLessThanOrEqual(r.multiplier, ScrollTuningSettings.maximumCombinedMultiplier)
            XCTAssertGreaterThan(r.durationTransition, regular, "free-spin is more direct than the regular Duration")
            XCTAssertTrue(ScrollMotion.shouldBypassFilter(freeSpinBlend: r.freeSpinBlend))
        }
    }
}
