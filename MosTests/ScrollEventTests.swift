//
//  ScrollEventTests.swift
//  MosTests
//
//  ScrollEvent 事件解析优先级/reverse/normalize/clear 测试 (Task 8)
//

import XCTest
import Carbon.HIToolbox
@testable import Mos_Debug

final class ScrollEventTests: XCTestCase {

    // MARK: - 辅助: 创建 CGEvent

    /// 创建滚动事件并设置指定轴的值
    private func makeScrollEvent(
        deltaAxis1: Int64 = 0, ptDeltaAxis1: Double = 0.0, fixPtDeltaAxis1: Double = 0.0,
        deltaAxis2: Int64 = 0, ptDeltaAxis2: Double = 0.0, fixPtDeltaAxis2: Double = 0.0
    ) -> CGEvent? {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: 0, wheel3: 0) else {
            return nil
        }
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: deltaAxis1)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: ptDeltaAxis1)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: fixPtDeltaAxis1)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: deltaAxis2)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: ptDeltaAxis2)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: fixPtDeltaAxis2)
        return event
    }

    // MARK: - initEvent: 优先级 (scrollPt > scrollFixPt > scrollFix)

    func testInitEvent_prefersPtOverFixPt() throws {
        // CGEvent scrollWheelEventPointDelta 字段会截断小数部分, 10.5 实际存储为 10.0
        let cgEvent = try XCTUnwrap(makeScrollEvent(deltaAxis1: 3, ptDeltaAxis1: 10.0, fixPtDeltaAxis1: 5.0))
        let scrollEvent = ScrollEvent(with: cgEvent)

        XCTAssertEqual(scrollEvent.Y.usableValue, 10.0, "scrollPt should take priority")
        XCTAssertFalse(scrollEvent.Y.fixed, "scrollPt-based data should not be marked as fixed")
        XCTAssertTrue(scrollEvent.Y.valid)
    }

    func testInitEvent_prefersFixPtOverFix() throws {
        let cgEvent = try XCTUnwrap(makeScrollEvent(deltaAxis1: 3, ptDeltaAxis1: 0.0, fixPtDeltaAxis1: 5.0))
        let scrollEvent = ScrollEvent(with: cgEvent)

        XCTAssertEqual(scrollEvent.Y.usableValue, 5.0, "scrollFixPt should be used when scrollPt is 0")
        XCTAssertTrue(scrollEvent.Y.fixed, "scrollFixPt-based data should be marked as fixed")
        XCTAssertTrue(scrollEvent.Y.valid)
    }

    func testInitEvent_fallsBackToFix() throws {
        let cgEvent = try XCTUnwrap(makeScrollEvent(deltaAxis1: 3, ptDeltaAxis1: 0.0, fixPtDeltaAxis1: 0.0))
        let scrollEvent = ScrollEvent(with: cgEvent)

        XCTAssertEqual(scrollEvent.Y.usableValue, 3.0, "scrollFix should be used as fallback")
        XCTAssertTrue(scrollEvent.Y.fixed, "scrollFix-based data should be marked as fixed")
        XCTAssertTrue(scrollEvent.Y.valid)
    }

    func testInitEvent_allZero_notValid() throws {
        let cgEvent = try XCTUnwrap(makeScrollEvent())
        let scrollEvent = ScrollEvent(with: cgEvent)

        XCTAssertFalse(scrollEvent.Y.valid, "all-zero data should not be valid")
        XCTAssertEqual(scrollEvent.Y.usableValue, 0.0)
    }

    // MARK: - initEvent: X 轴

    func testInitEvent_xAxis_prefersPt() throws {
        let cgEvent = try XCTUnwrap(makeScrollEvent(deltaAxis2: 2, ptDeltaAxis2: 7.0, fixPtDeltaAxis2: 3.0))
        let scrollEvent = ScrollEvent(with: cgEvent)

        XCTAssertEqual(scrollEvent.X.usableValue, 7.0, "X axis scrollPt should take priority")
        XCTAssertFalse(scrollEvent.X.fixed)
        XCTAssertTrue(scrollEvent.X.valid)
    }

    func testInitEvent_xAxis_fallbackToFix() throws {
        let cgEvent = try XCTUnwrap(makeScrollEvent(deltaAxis2: -4))
        let scrollEvent = ScrollEvent(with: cgEvent)

        XCTAssertEqual(scrollEvent.X.usableValue, -4.0)
        XCTAssertTrue(scrollEvent.X.fixed)
        XCTAssertTrue(scrollEvent.X.valid)
    }

    // MARK: - reverse (Y 轴)

    func testReverseY_negatesAllYFields() throws {
        let cgEvent = try XCTUnwrap(makeScrollEvent(deltaAxis1: 5, ptDeltaAxis1: 10.0, fixPtDeltaAxis1: 7.5))
        let scrollEvent = ScrollEvent(with: cgEvent)

        ScrollEvent.reverseY(scrollEvent)

        // usableValue 应该取反
        XCTAssertEqual(scrollEvent.Y.usableValue, -10.0, accuracy: 1e-10)

        // CGEvent 字段也应该取反
        let newDelta = scrollEvent.event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        XCTAssertEqual(newDelta, -5)

        let newPt = scrollEvent.event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        XCTAssertEqual(newPt, -10.0, accuracy: 1e-10)

        let newFixPt = scrollEvent.event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        XCTAssertEqual(newFixPt, -7.5, accuracy: 1e-10)
    }

    func testReverseY_doubleReverse_restoresOriginal() throws {
        let cgEvent = try XCTUnwrap(makeScrollEvent(deltaAxis1: 3, ptDeltaAxis1: 6.0, fixPtDeltaAxis1: 4.5))
        let scrollEvent = ScrollEvent(with: cgEvent)

        ScrollEvent.reverseY(scrollEvent)
        ScrollEvent.reverseY(scrollEvent)

        XCTAssertEqual(scrollEvent.Y.usableValue, 6.0, accuracy: 1e-10, "double reverse should restore original")
    }

    // MARK: - reverse (X 轴)

    func testReverseX_negatesAllXFields() throws {
        let cgEvent = try XCTUnwrap(makeScrollEvent(deltaAxis2: 3, ptDeltaAxis2: 8.0, fixPtDeltaAxis2: 4.0))
        let scrollEvent = ScrollEvent(with: cgEvent)

        ScrollEvent.reverseX(scrollEvent)

        XCTAssertEqual(scrollEvent.X.usableValue, -8.0, accuracy: 1e-10)

        let newDelta = scrollEvent.event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        XCTAssertEqual(newDelta, -3)
    }

    // MARK: - normalize (Y 轴)

    func testNormalizeY_positiveBelowThreshold_clampsUp() throws {
        // CGEvent scrollWheelEventPointDelta 截断小数, 使用 fixPtDelta 来传递小数值
        let cgEvent = try XCTUnwrap(makeScrollEvent(fixPtDeltaAxis1: 0.5))
        let scrollEvent = ScrollEvent(with: cgEvent)

        let threshold = 2.0
        ScrollEvent.normalizeY(scrollEvent, threshold)

        XCTAssertEqual(scrollEvent.Y.usableValue, threshold, accuracy: 1e-10,
            "positive value below threshold should be clamped up to threshold")
    }

    func testNormalizeY_negativeBelowThreshold_clampsDown() throws {
        let cgEvent = try XCTUnwrap(makeScrollEvent(ptDeltaAxis1: -0.5))
        let scrollEvent = ScrollEvent(with: cgEvent)

        let threshold = 2.0
        ScrollEvent.normalizeY(scrollEvent, threshold)

        XCTAssertEqual(scrollEvent.Y.usableValue, -threshold, accuracy: 1e-10,
            "negative value below threshold should be clamped to -threshold")
    }

    func testNormalizeY_aboveThreshold_unchanged() throws {
        let cgEvent = try XCTUnwrap(makeScrollEvent(ptDeltaAxis1: 5.0))
        let scrollEvent = ScrollEvent(with: cgEvent)

        let threshold = 2.0
        ScrollEvent.normalizeY(scrollEvent, threshold)

        XCTAssertEqual(scrollEvent.Y.usableValue, 5.0, accuracy: 1e-10,
            "value above threshold should remain unchanged")
    }

    // MARK: - normalize (X 轴)

    func testNormalizeX_positiveBelowThreshold_clampsUp() throws {
        // CGEvent scrollWheelEventPointDelta 截断小数, 使用 fixPtDelta 来传递小数值
        let cgEvent = try XCTUnwrap(makeScrollEvent(fixPtDeltaAxis2: 0.3))
        let scrollEvent = ScrollEvent(with: cgEvent)

        let threshold = 1.0
        ScrollEvent.normalizeX(scrollEvent, threshold)

        XCTAssertEqual(scrollEvent.X.usableValue, threshold, accuracy: 1e-10)
    }

    // MARK: - clear (Y 轴)

    func testClearY_zerosAllYFields() throws {
        let cgEvent = try XCTUnwrap(makeScrollEvent(deltaAxis1: 5, ptDeltaAxis1: 10.0, fixPtDeltaAxis1: 7.5))
        let scrollEvent = ScrollEvent(with: cgEvent)

        ScrollEvent.clearY(scrollEvent)

        XCTAssertEqual(scrollEvent.Y.scrollFix, 0)
        XCTAssertEqual(scrollEvent.Y.scrollPt, 0.0, accuracy: 1e-10)
        XCTAssertEqual(scrollEvent.Y.scrollFixPt, 0.0, accuracy: 1e-10)
        XCTAssertEqual(scrollEvent.Y.usableValue, 0.0, accuracy: 1e-10)

        // CGEvent 字段也应该被清零
        XCTAssertEqual(scrollEvent.event.getIntegerValueField(.scrollWheelEventDeltaAxis1), 0)
        XCTAssertEqual(scrollEvent.event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1), 0.0, accuracy: 1e-10)
        XCTAssertEqual(scrollEvent.event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1), 0.0, accuracy: 1e-10)
    }

    func testClearY_doesNotAffectXAxis() throws {
        let cgEvent = try XCTUnwrap(makeScrollEvent(deltaAxis1: 5, ptDeltaAxis1: 10.0, deltaAxis2: 3, ptDeltaAxis2: 6.0))
        let scrollEvent = ScrollEvent(with: cgEvent)

        ScrollEvent.clearY(scrollEvent)

        // X 轴不受影响
        XCTAssertEqual(scrollEvent.X.usableValue, 6.0, accuracy: 1e-10, "clearY should not affect X axis")
    }

    // MARK: - clear (X 轴)

    func testClearX_zerosAllXFields() throws {
        let cgEvent = try XCTUnwrap(makeScrollEvent(deltaAxis2: 3, ptDeltaAxis2: 6.0, fixPtDeltaAxis2: 4.0))
        let scrollEvent = ScrollEvent(with: cgEvent)

        ScrollEvent.clearX(scrollEvent)

        XCTAssertEqual(scrollEvent.X.scrollFix, 0)
        XCTAssertEqual(scrollEvent.X.scrollPt, 0.0, accuracy: 1e-10)
        XCTAssertEqual(scrollEvent.X.scrollFixPt, 0.0, accuracy: 1e-10)
        XCTAssertEqual(scrollEvent.X.usableValue, 0.0, accuracy: 1e-10)
    }

    func testClearX_doesNotAffectYAxis() throws {
        let cgEvent = try XCTUnwrap(makeScrollEvent(deltaAxis1: 5, ptDeltaAxis1: 10.0, deltaAxis2: 3, ptDeltaAxis2: 6.0))
        let scrollEvent = ScrollEvent(with: cgEvent)

        ScrollEvent.clearX(scrollEvent)

        XCTAssertEqual(scrollEvent.Y.usableValue, 10.0, accuracy: 1e-10, "clearX should not affect Y axis")
    }

    // MARK: - 负值 scrollFix

    func testInitEvent_negativeDeltaFix() throws {
        let cgEvent = try XCTUnwrap(makeScrollEvent(deltaAxis1: -7))
        let scrollEvent = ScrollEvent(with: cgEvent)

        XCTAssertEqual(scrollEvent.Y.usableValue, -7.0)
        XCTAssertTrue(scrollEvent.Y.fixed)
        XCTAssertTrue(scrollEvent.Y.valid)
    }

    // MARK: - axisData 结构体默认值

    func testAxisData_defaults() {
        let data = axisData()
        XCTAssertEqual(data.scrollFix, 0)
        XCTAssertEqual(data.scrollPt, 0.0)
        XCTAssertEqual(data.scrollFixPt, 0.0)
        XCTAssertFalse(data.fixed)
        XCTAssertFalse(data.valid)
        XCTAssertEqual(data.usableValue, 0.0)
    }

    // MARK: - Trackpad or wheel (values from a trace on the owner's Mac, 2026-11-11)

    private func isTrackpad(_ event: TracedScrollEvent) -> Bool {
        return ScrollEvent.isTrackpad(
            scrollPhase: event.phase, momentumPhase: event.momentum,
            scrollCount: event.count, isContinuous: event.continuous
        )
    }

    /// The regression: a wheel turned while the trackpad's glide ran carries the glide's swipe
    /// count (1 or 2). Taken for trackpad events, these went through raw, unsmoothed and (with
    /// "Reverse" on) the wrong way, until the count went back to 0 and the page jumped back.
    func testWheelEventsDuringATrackpadGlide_areWheelEventsWhateverTheirCount() {
        XCTAssertFalse(isTrackpad(.wheel(count: 1, line: -1, point: -1)))
        XCTAssertFalse(isTrackpad(.wheel(count: 1, line: -1, point: -13)))
        XCTAssertFalse(isTrackpad(.wheel(count: 1, line: -12, point: -130)))
        XCTAssertFalse(isTrackpad(.wheel(count: 2, line: 1, point: 11)))
        XCTAssertFalse(isTrackpad(.wheel(count: 2, line: 13, point: 139)))
    }

    func testOrdinaryWheelEvent_isAWheelEvent() {
        XCTAssertFalse(isTrackpad(.wheel(count: 0, line: -9, point: -95)))
        XCTAssertFalse(isTrackpad(.wheel(count: 0, line: 1, point: 1)))
    }

    /// Every trackpad event in the trace has a touch or a glide phase; all but the "ended"
    /// that comes with a wheel event are continuous.
    func testTrackpadEventsWithAPhase_areTrackpadEvents() {
        for count in [0.0, 1, 2] {
            for phase in [1.0, 2, 4, 8, 128] {
                XCTAssertTrue(isTrackpad(.touch(phase, count: count, point: 22)), "phase \(phase) count \(count)")
            }
            XCTAssertTrue(isTrackpad(.momentum(1, count: count, point: 234)), "count \(count)")
            XCTAssertTrue(isTrackpad(.momentum(2, count: count, point: 99)), "count \(count)")
            XCTAssertTrue(isTrackpad(.momentum(3, count: count)), "count \(count)")
        }
        // The glide's "ended" that comes with the wheel's first event: not continuous.
        XCTAssertTrue(isTrackpad(.wheelMarker(count: 2, line: 1, point: 1)))
        XCTAssertTrue(isTrackpad(.wheelMarker(count: 0, line: 1, point: 1)))
    }

    /// The one trackpad event without a phase (at the end of a touch): continuous, count 1.
    func testPhaseLessContinuousEventWithACount_isATrackpadEvent() {
        XCTAssertTrue(isTrackpad(TracedScrollEvent(phase: 0, momentum: 0, count: 1, continuous: 1)))
        // Without a count it was, and stays, a wheel event (a remote desktop's, for one).
        XCTAssertFalse(isTrackpad(TracedScrollEvent(phase: 0, momentum: 0, count: 0, continuous: 1, line: 3, point: 30)))
    }

    /// The same rule on real events (the fields as the scroll tap reads them).
    func testIsTrackpadWithEvent_readsTheFourFields() throws {
        let wheel = try XCTUnwrap(TracedScrollEvent.wheel(count: 1, line: -1, point: -13).cgEvent())
        XCTAssertEqual(wheel.getIntegerValueField(.scrollWheelEventScrollCount), 1, "the count is set")
        XCTAssertEqual(wheel.getIntegerValueField(.scrollWheelEventIsContinuous), 0)
        XCTAssertFalse(ScrollEvent.isTrackpad(with: wheel))
        XCTAssertFalse(ScrollEvent(with: wheel).isTrackpad())

        XCTAssertTrue(ScrollEvent.isTrackpad(with: try XCTUnwrap(TracedScrollEvent.momentum(2, count: 1, point: 99).cgEvent())))
        XCTAssertTrue(ScrollEvent.isTrackpad(with: try XCTUnwrap(TracedScrollEvent.touch(1, point: 1).cgEvent())))
        XCTAssertTrue(ScrollEvent.isTrackpad(with: try XCTUnwrap(TracedScrollEvent(phase: 0, momentum: 0, count: 1, continuous: 1).cgEvent())))
        XCTAssertFalse(ScrollEvent.isTrackpad(with: try XCTUnwrap(TracedScrollEvent.wheel(count: 0, line: -9, point: -95).cgEvent())))
    }
}

// MARK: - Trackpad and wheel together

/// One scroll event with the fields the hand-over trace writes (vertical only).
struct TracedScrollEvent {
    var phase = 0.0
    var momentum = 0.0
    var count = 0.0
    var continuous = 1.0
    var line: Int64 = 0
    var point = 0.0

    static func touch(_ phase: Double, count: Double = 0, point: Double = 0) -> TracedScrollEvent {
        return TracedScrollEvent(phase: phase, count: count, line: Int64(point / 10), point: point)
    }
    static func momentum(_ momentum: Double, count: Double = 1, point: Double = 0) -> TracedScrollEvent {
        return TracedScrollEvent(momentum: momentum, count: count, line: Int64(point / 10), point: point)
    }
    /// A mouse wheel's event: no phase, not continuous.
    static func wheel(count: Double, line: Int64, point: Double) -> TracedScrollEvent {
        return TracedScrollEvent(count: count, continuous: 0, line: line, point: point)
    }
    /// The glide's "ended" that macOS sends with the wheel's first event during a glide.
    static func wheelMarker(count: Double, line: Int64, point: Double) -> TracedScrollEvent {
        return TracedScrollEvent(momentum: 3, count: count, continuous: 0, line: line, point: point)
    }

    var hasDelta: Bool { return line != 0 || point != 0 }

    func cgEvent() -> CGEvent? {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 0, wheel2: 0, wheel3: 0) else {
            return nil
        }
        event.setDoubleValueField(.scrollWheelEventScrollPhase, value: phase)
        event.setDoubleValueField(.scrollWheelEventMomentumPhase, value: momentum)
        event.setIntegerValueField(.scrollWheelEventScrollCount, value: Int64(count))
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: Int64(continuous))
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: line)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: point)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: point / 10)
        return event
    }
}

/// Who moves the page when the trackpad and the wheel overlap (ScrollHandover), with event
/// sequences from a trace on the owner's Mac (2026-11-11).
final class ScrollHandoverTests: XCTestCase {

    /// Runs events as the scroll tap does. Each becomes T (taken for trackpad, let through),
    /// S (dropped: the wheel took over that glide) or W (wheel); `ended` holds the drop count
    /// of each takeover that ended.
    private func run(_ events: [TracedScrollEvent], _ handover: inout ScrollHandover) -> (kinds: String, ended: [Int]) {
        var kinds = ""
        var ended: [Int] = []
        for event in events {
            guard ScrollEvent.isTrackpad(scrollPhase: event.phase, momentumPhase: event.momentum, scrollCount: event.count, isContinuous: event.continuous) else {
                if event.hasDelta { handover.wheelEvent() }
                kinds += "W"
                continue
            }
            switch handover.trackpadEvent(scrollPhase: event.phase, momentumPhase: event.momentum, hasDelta: event.hasDelta) {
            case .swallow:
                kinds += "S"
            case .letThrough:
                kinds += "T"
            case .letThroughEndingTakeover(let dropped):
                kinds += "T"
                ended.append(dropped)
            }
        }
        return (kinds, ended)
    }

    /// A swipe with its glide (count 1), then the wheel turned the other way during the glide.
    /// Before, the wheel's events were taken for the trackpad's while the count was set (raw,
    /// the wrong way) and the glide went on under them.
    private let wheelDuringAGlide: [TracedScrollEvent] = [
        .touch(1, point: 1), .touch(2, point: 22), .touch(2, count: 1, point: 93), .touch(4, count: 1),
        .momentum(1, point: 180), .momentum(2, point: 169), .momentum(2, point: 24),
        .wheelMarker(count: 1, line: -1, point: -1),
        .wheel(count: 1, line: -1, point: -1),
        .momentum(2, point: 22),
        .wheel(count: 1, line: -1, point: -13),
        .momentum(2, point: 20),
        .wheel(count: 1, line: -7, point: -80),
        .momentum(2, count: 0, point: 5),
        .wheel(count: 0, line: -12, point: -122),
        .momentum(2, count: 0, point: 5),
        .momentum(2, count: 0, point: 1),
        .momentum(3, count: 0),
        .touch(1, point: 2),
    ]

    func testWheelDuringATrackpadGlide_takesOverAndTheGlideStillEnds() {
        var handover = ScrollHandover()
        let result = run(wheelDuringAGlide, &handover)
        // The touch and the glide up to the wheel go on; the "ended" that comes with the wheel
        // goes on; the wheel's events are wheel events; the rest of the glide is dropped, its
        // real "ended" goes on; the next touch starts fresh.
        XCTAssertEqual(result.kinds, "TTTTTTT" + "T" + "W" + "SWSWSW" + "SS" + "T" + "T")
        XCTAssertEqual(result.ended, [5])
        XCTAssertEqual(handover.state, .idle)
    }

    /// Trackpad alone: nothing is ever dropped (a swipe, its glide, a second swipe at once).
    func testTrackpadAlone_dropsNothing() {
        var handover = ScrollHandover()
        let swipes: [TracedScrollEvent] = [
            .touch(1, point: 1), .touch(2, point: 16), .touch(2, count: 1, point: 37), .touch(4, count: 1),
            .momentum(1, point: 99), .momentum(2, point: 99), .momentum(2, point: 29), .momentum(3),
            .touch(1, count: 2, point: 1), .touch(2, count: 2, point: 239), .touch(4, count: 2),
            .momentum(1, count: 2, point: 234), .momentum(2, count: 2, point: 215),
            // A touch while the glide runs (may begin, cancelled).
            .touch(128), .touch(8),
            TracedScrollEvent(phase: 0, momentum: 0, count: 1, continuous: 1),
        ]
        let result = run(swipes, &handover)
        XCTAssertEqual(result.kinds, String(repeating: "T", count: swipes.count))
        XCTAssertEqual(result.ended, [])
    }

    /// Wheel alone: nothing changes.
    func testWheelAlone_changesNothing() {
        var handover = ScrollHandover()
        let notches = (0..<20).map { _ in TracedScrollEvent.wheel(count: 0, line: -9, point: -95) }
        XCTAssertEqual(run(notches, &handover).kinds, String(repeating: "W", count: notches.count))
        XCTAssertEqual(handover.state, .idle)
    }

    /// The wheel after a glide that ended takes over nothing.
    func testWheelAfterTheGlideEnded_takesOverNothing() {
        var handover = ScrollHandover()
        let events: [TracedScrollEvent] = [
            .momentum(1, point: 99), .momentum(2, point: 29), .momentum(3),
            .wheel(count: 1, line: -1, point: -13),
            .touch(1, point: 1), .touch(2, point: 22), .touch(4), .momentum(1, point: 50), .momentum(2, point: 40),
        ]
        let result = run(events, &handover)
        XCTAssertEqual(result.kinds, "TTTWTTTTT")
        XCTAssertEqual(result.ended, [])
    }

    /// A new touch or a new glide ends the takeover and is never dropped.
    func testANewTouchOrANewGlide_startsFresh() {
        var handover = ScrollHandover()
        let touch = run([
            .momentum(1, point: 99), .momentum(2, point: 90),
            .wheel(count: 1, line: 5, point: 54),
            .momentum(2, point: 80), .momentum(2, point: 70),
            .touch(128), .touch(1, point: 1), .touch(2, point: 20),
        ], &handover)
        XCTAssertEqual(touch.kinds, "TTWSSTTT")
        XCTAssertEqual(touch.ended, [2])

        handover = ScrollHandover()
        let glide = run([
            .momentum(1, point: 99), .wheel(count: 1, line: 5, point: 54), .momentum(2, point: 80),
            .momentum(1, count: 2, point: 234), .momentum(2, count: 2, point: 215),
        ], &handover)
        XCTAssertEqual(glide.kinds, "TWSTT")
        XCTAssertEqual(glide.ended, [1])
    }

    /// The glide's "ended" that comes with the wheel does not end the glide: its "changed"
    /// events go on after it.
    func testTheEndedThatComesWithTheWheel_doesNotEndTheGlide() {
        var handover = ScrollHandover()
        XCTAssertEqual(handover.trackpadEvent(scrollPhase: 0, momentumPhase: 2, hasDelta: true), .letThrough)
        XCTAssertEqual(handover.trackpadEvent(scrollPhase: 0, momentumPhase: 3, hasDelta: true), .letThrough)
        XCTAssertEqual(handover.state, .glide)
        XCTAssertEqual(handover.trackpadEvent(scrollPhase: 0, momentumPhase: 3, hasDelta: false), .letThrough)
        XCTAssertEqual(handover.state, .idle)
    }

    // MARK: The scroll tap

    /// End to end through the scroll tap's callback, with smoothing off: the wheel is let
    /// through raw, and it still takes over (raw, it would move the page against the glide).
    func testScrollTap_dropsTheRestOfAGlideTheWheelTookOver_withSmoothingOff() throws {
        let savedSmooth = Options.shared.scroll.smooth
        defer {
            Options.shared.scroll.smooth = savedSmooth
            ScrollCore.shared.handover = ScrollHandover()
        }
        Options.shared.scroll.smooth = false
        ScrollCore.shared.handover = ScrollHandover()

        var kinds = ""
        for traced in wheelDuringAGlide {
            let event = try XCTUnwrap(traced.cgEvent())
            let result = ScrollCore.shared.scrollEventCallBack(CGEventTapProxy(bitPattern: 1)!, .scrollWheel, event, nil)
            kinds += result == nil ? "x" : "o"
        }
        // o = goes on, x = dropped. The wheel's events go on (smoothing is off).
        XCTAssertEqual(kinds, "ooooooo" + "o" + "o" + "xoxoxo" + "xx" + "o" + "o")
        XCTAssertEqual(ScrollCore.shared.handover.state, .idle)
    }

    // MARK: Wheel to trackpad

    /// A finger that begins to scroll stops Scrollio's glide from the wheel at once; other
    /// touch phases and the trackpad's glide leave it alone.
    func testFingerBeginningToScroll_stopsTheWheelGlide() {
        let poster = ScrollPoster(phases: ScrollPhase(), dispatchContext: ScrollDispatchContext())
        var frames: [ScrollOutgoingFrame] = []
        poster.frameRecorderForTests = { frames.append($0) }
        poster.setConfigForTests(simTrackpadEnabled: false)
        let frameInterval = 1.0 / 60.0
        var now = 100.0
        func runFrames(_ count: Int) -> [ScrollStopRequest] {
            var requests: [ScrollStopRequest] = []
            for _ in 0..<count {
                now += frameInterval
                if let request = poster.displayLinkFrameForTests(frameInterval: frameInterval, now: now) {
                    requests.append(request)
                }
            }
            return requests
        }

        XCTAssertFalse(ScrollCore.stopWheelGlide(forTrackpadScrollPhase: 1, poster: poster), "no glide, nothing to stop")
        let transition = OPTIONS_SCROLL_DEFAULT.generateDurationTransition(with: 3.69)
        poster.inputForTests(ScrollPosterInput(y: 600, x: 0, notch: 90, duration: transition), at: now)
        XCTAssertTrue(runFrames(6).isEmpty)
        XCTAssertTrue(poster.isGliding)
        XCTAssertFalse(frames.isEmpty, "the glide moves the page")

        for phase in [0.0, 2, 4, 8, 128] {
            XCTAssertFalse(ScrollCore.stopWheelGlide(forTrackpadScrollPhase: phase, poster: poster), "phase \(phase)")
        }
        XCTAssertTrue(poster.isGliding)

        XCTAssertTrue(ScrollCore.stopWheelGlide(forTrackpadScrollPhase: 1, poster: poster))
        XCTAssertFalse(poster.isGliding)
        let framesAtTheTouch = frames.count
        XCTAssertTrue(runFrames(60).isEmpty)
        XCTAssertEqual(frames.count, framesAtTheTouch, "nothing more is posted")
        XCTAssertEqual(poster.motionStateForTests.buffer.y, 0)
    }

    // MARK: The log

    /// The two lines the owner's log shows for a hand-over. Diagnosis on his machine reads
    /// them (`log show`, category `scroll`), so their wording is part of the contract.
    func testLog_saysWhatTheHandOverDid() {
        XCTAssertEqual(
            ScrollSystemLog.wheelTookOverMessage(droppedMomentumEvents: 5),
            "handover: the wheel took over a trackpad glide: 5 momentum events dropped"
        )
        XCTAssertEqual(
            ScrollSystemLog.fingerTookOverMessage,
            "handover: a finger on the trackpad took over: the wheel's glide stopped"
        )
    }
}

// MARK: - The sideways wheel (thumb wheel)

/// The stepper of the thumb wheel's functions: how the travel of wheel events becomes steps.
final class ThumbWheelStepperTests: XCTestCase {

    private func lines(_ line: Int64, _ fixed: Double, _ point: Double) -> Double {
        return ThumbWheelStepper.lines(lineDelta: line, fixedDelta: fixed, pointDelta: point)
    }

    /// Travel toward "next" of an event with these line deltas (fixed-point = integer).
    private func travel(_ lines: Double, flipped: Bool = false, speed: Double = 1) -> Double {
        return ThumbWheelStepper.travel(lineDelta: Int64(lines), fixedDelta: lines, pointDelta: lines * 10, flipped: flipped, speed: speed)
    }

    // MARK: Travel of one event

    func testLines_fixedPointFirst_thenTheLineDelta_thenPointsOverTen() {
        XCTAssertEqual(lines(2, 1.25, 30), 1.25)
        XCTAssertEqual(lines(-2, 0, -30), -2)
        XCTAssertEqual(lines(0, 0, -7), -0.7, accuracy: 1e-12)
        XCTAssertEqual(lines(0, 0, 0), 0)
        XCTAssertEqual(ThumbWheelTuning.pointsPerLine, 10)
    }

    func testLines_oneEventCountsForAtMostThreeLines() {
        XCTAssertEqual(ThumbWheelTuning.maxLinesPerEvent, 3)
        XCTAssertEqual(lines(12, 12.4, 140), 3)
        XCTAssertEqual(lines(-9, -9, -95), -3)
        XCTAssertEqual(lines(0, 0, 400), 3)
        XCTAssertEqual(lines(0, .infinity, 0), 0, "not a number: no travel")
    }

    /// A negative X delta shows what lies to the right: that is "next". The direction rules
    /// turn it around (once), and the speed multiplies the capped travel.
    func testTravel_aNegativeXDeltaIsNext_flippedTurnsItAround_speedAfterTheCap() {
        XCTAssertEqual(travel(-1), 1)
        XCTAssertEqual(travel(1), -1)
        XCTAssertEqual(travel(-1, flipped: true), -1)
        XCTAssertEqual(travel(1, flipped: true), 1)
        XCTAssertEqual(travel(-10, speed: 2), 6, "3 lines at most, then × 2")
        XCTAssertEqual(travel(-1, speed: 0.25), 0.25)
        XCTAssertEqual(travel(-1, speed: 50), 3, "the speed stays inside its range")
    }

    // MARK: Functions that repeat

    func testThresholds_zoomAndVolumeOneLine_tabsTwoLines() {
        XCTAssertEqual(ThumbWheelFunction.zoom.stepping, .repeating(linesPerStep: 1))
        XCTAssertEqual(ThumbWheelFunction.volume.stepping, .repeating(linesPerStep: 1))
        XCTAssertEqual(ThumbWheelFunction.tabs.stepping, .repeating(linesPerStep: 2))
        XCTAssertEqual(ThumbWheelFunction.desktops.stepping, .oncePerRoll(lines: 1.5))
        XCTAssertEqual(ThumbWheelFunction.backForward.stepping, .oncePerRoll(lines: 1.5))
        XCTAssertEqual(ThumbWheelFunction.scroll.stepping, .none)

        for function in [ThumbWheelFunction.zoom, .volume] {
            var stepper = ThumbWheelStepper()
            XCTAssertEqual(stepper.feed(travel: 1, function: function, at: 0), 1, "\(function)")
            XCTAssertEqual(stepper.feed(travel: 0.5, function: function, at: 0.05), 0, "\(function)")
            XCTAssertEqual(stepper.feed(travel: 0.5, function: function, at: 0.1), 1, "\(function)")
        }
        var tabs = ThumbWheelStepper()
        XCTAssertEqual(tabs.feed(travel: 1, function: .tabs, at: 0), 0)
        XCTAssertEqual(tabs.feed(travel: 1, function: .tabs, at: 0.05), 1)
        XCTAssertEqual(tabs.feed(travel: -1, function: .tabs, at: 0.1), 0)
        XCTAssertEqual(tabs.feed(travel: -1, function: .tabs, at: 0.15), -1, "previous")
    }

    func testCarry_theRestGoesTowardTheNextStep() {
        var stepper = ThumbWheelStepper()
        XCTAssertEqual(stepper.feed(travel: 0.4, function: .zoom, at: 0), 0)
        XCTAssertEqual(stepper.feed(travel: 0.4, function: .zoom, at: 0.05), 0)
        XCTAssertEqual(stepper.feed(travel: 0.4, function: .zoom, at: 0.1), 1)
        XCTAssertEqual(stepper.carried, 0.2, accuracy: 1e-9)
        XCTAssertEqual(stepper.feed(travel: 0.8, function: .zoom, at: 0.15), 1)
        XCTAssertEqual(stepper.carried, 0, accuracy: 1e-9)
    }

    /// Tenths of a line do not add up to exactly one in binary: ten of them still make a step.
    func testCarry_tenthsOfALineAddUpToAStep() {
        var stepper = ThumbWheelStepper()
        var steps = 0
        for index in 0..<10 {
            steps += stepper.feed(travel: 0.1, function: .zoom, at: Double(index) * 0.01)
        }
        XCTAssertEqual(steps, 1)
        XCTAssertEqual(stepper.carried, 0)
    }

    func testDirectionChange_dropsTheCarriedTravel() {
        var stepper = ThumbWheelStepper()
        XCTAssertEqual(stepper.feed(travel: 0.8, function: .zoom, at: 0), 0)
        // Without the drop: 0.8 − 0.5 − 0.5 = −0.2, no step.
        XCTAssertEqual(stepper.feed(travel: -0.5, function: .zoom, at: 0.05), 0)
        XCTAssertEqual(stepper.carried, -0.5, accuracy: 1e-12)
        XCTAssertEqual(stepper.feed(travel: -0.5, function: .zoom, at: 0.1), -1)
    }

    func testRest_dropsTheCarriedTravel() {
        XCTAssertEqual(ThumbWheelTuning.carryRest, 0.3)
        var stepper = ThumbWheelStepper()
        XCTAssertEqual(stepper.feed(travel: 0.8, function: .zoom, at: 0), 0)
        XCTAssertEqual(stepper.feed(travel: 0.5, function: .zoom, at: 0.31), 0, "after a rest it starts from 0")
        XCTAssertEqual(stepper.feed(travel: 0.4, function: .zoom, at: 0.5), 0)
        XCTAssertEqual(stepper.feed(travel: 0.2, function: .zoom, at: 0.79), 1, "a shorter pause keeps it: 0.5 + 0.4 + 0.2")
    }

    /// macOS accelerates a fast turn: one event counts for three lines at most, so one flick
    /// runs three zoom steps, nine at the highest speed.
    func testCapPerEvent_oneEventRunsAtMostThreeStepsTimesTheSpeed() {
        let flick = ThumbWheelStepper.travel(lineDelta: -12, fixedDelta: -12.5, pointDelta: -140, flipped: false, speed: 1)
        var stepper = ThumbWheelStepper()
        XCTAssertEqual(stepper.feed(travel: flick, function: .zoom, at: 0), 3)
        let fastest = ThumbWheelStepper.travel(lineDelta: -12, fixedDelta: -12.5, pointDelta: -140, flipped: false, speed: ThumbWheelSettings.speedRange.upperBound)
        stepper = ThumbWheelStepper()
        XCTAssertEqual(stepper.feed(travel: fastest, function: .zoom, at: 0), 9)
        stepper = ThumbWheelStepper()
        XCTAssertEqual(stepper.feed(travel: flick, function: .tabs, at: 0), 1)
        XCTAssertEqual(stepper.carried, 1, accuracy: 1e-12)
    }

    /// A higher speed takes less of a turn per step.
    func testSpeed_scalesTheTravel() {
        var tabs = ThumbWheelStepper()
        XCTAssertEqual(tabs.feed(travel: travel(-1, speed: 2), function: .tabs, at: 0), 1, "one line at × 2 is a tab")
        XCTAssertEqual(tabs.feed(travel: travel(-1, speed: 2), function: .tabs, at: 0.05), 1)
        var zoom = ThumbWheelStepper()
        XCTAssertEqual(zoom.feed(travel: travel(-1, speed: 0.5), function: .zoom, at: 0), 0, "one line at × 0.5 is half a step")
        XCTAssertEqual(zoom.feed(travel: travel(-1, speed: 0.5), function: .zoom, at: 0.05), 1)
    }

    // MARK: Functions that step once per roll

    func testOncePerRoll_oneStepThenNothingUntilTheWheelRested() {
        XCTAssertEqual(ThumbWheelTuning.oncePerRollLines, 1.5)
        XCTAssertEqual(ThumbWheelTuning.rollRest, 0.4)
        for function in [ThumbWheelFunction.desktops, .backForward] {
            var stepper = ThumbWheelStepper()
            XCTAssertEqual(stepper.feed(travel: 1, function: function, at: 0), 0, "\(function)")
            XCTAssertEqual(stepper.feed(travel: 1, function: function, at: 0.05), 1, "\(function)")
            XCTAssertEqual(stepper.feed(travel: 3, function: function, at: 0.1), 0, "\(function): the roll goes on")
            XCTAssertEqual(stepper.feed(travel: -3, function: function, at: 0.2), 0, "\(function): turned back in the same roll")
            XCTAssertEqual(stepper.feed(travel: 3, function: function, at: 0.55), 0, "\(function): a pause shorter than a rest")
            XCTAssertEqual(stepper.feed(travel: -1, function: function, at: 0.96), 0, "\(function): rested, a new roll")
            XCTAssertEqual(stepper.feed(travel: -1, function: function, at: 1.0), -1, "\(function)")
        }
    }

    // MARK: Changes in the middle of a roll

    func testAnotherFunction_startsAfresh() {
        var stepper = ThumbWheelStepper()
        XCTAssertEqual(stepper.feed(travel: 1, function: .tabs, at: 0), 0)
        // Without the reset the tab's line carried would make this a zoom step.
        XCTAssertEqual(stepper.feed(travel: 0.5, function: .zoom, at: 0.05), 0)
        XCTAssertEqual(stepper.function, .zoom)

        stepper = ThumbWheelStepper()
        XCTAssertEqual(stepper.feed(travel: 2, function: .desktops, at: 0), 1)
        XCTAssertEqual(stepper.feed(travel: 2, function: .backForward, at: 0.05), 1, "a new function has not stepped in this roll")
    }

    func testReset_forgetsEverything() {
        var stepper = ThumbWheelStepper()
        _ = stepper.feed(travel: 2, function: .desktops, at: 0)
        _ = stepper.feed(travel: 1, function: .desktops, at: 0.05)
        stepper.reset()
        XCTAssertEqual(stepper, ThumbWheelStepper())
    }
}

/// The thumb wheel in the scroll tap, without the tap: what a step does, when it runs, and the
/// one log line per roll.
final class ThumbWheelEngineTests: XCTestCase {

    /// One action run, as recorded.
    struct Performed: Equatable {
        var action: ThumbWheelAction
        var times: Int
    }

    /// An engine on a simulated clock and main queue: work it schedules runs in `advance`.
    final class Rig {
        let engine = ThumbWheelEngine()
        var now = 500.0
        private(set) var queue: [(due: Double, order: Int, work: () -> Void)] = []
        private var scheduledCount = 0
        private(set) var performed: [Performed] = []
        private(set) var lines: [ScrollSystemLog.ThumbWheelRoll] = []

        init() {
            engine.clock = { [unowned self] in self.now }
            engine.schedule = { [unowned self] delay, work in
                self.scheduledCount += 1
                self.queue.append((self.now + max(0, delay), self.scheduledCount, work))
            }
            engine.perform = { [unowned self] action, times in self.performed.append(Performed(action: action, times: times)) }
            engine.writeLog = { [unowned self] roll in self.lines.append(roll) }
        }

        var hasPendingWork: Bool { return !queue.isEmpty }

        /// Runs the work due up to `time`, in order.
        func advance(to time: Double) {
            while let next = queue.enumerated()
                .filter({ $0.element.due <= time + 1e-9 })
                .min(by: { ($0.element.due, $0.element.order) < ($1.element.due, $1.element.order) }) {
                queue.remove(at: next.offset)
                now = max(now, next.element.due)
                next.element.work()
            }
            now = max(now, time)
        }

        /// One sideways event at `time` (seconds after the rig's start).
        @discardableResult
        func turn(lines: Double, at time: Double, settings: ThumbWheelSettings, flipped: Bool = false, continuous: Bool = false) -> Int {
            advance(to: 500 + time)
            let event = ThumbWheelEvent(lineDelta: Int64(lines), fixedDelta: lines, pointDelta: (lines * 10).rounded(), isContinuous: continuous)
            return engine.handle(event, settings: settings, flipped: flipped)
        }
    }

    // MARK: What a step does

    func testActions_eachFunctionNextAndPrevious() {
        func action(_ function: ThumbWheelFunction, _ next: Bool) -> ThumbWheelAction? {
            return ThumbWheelAction.action(for: function, towardNext: next)
        }
        XCTAssertNil(action(.scroll, true))
        XCTAssertNil(action(.scroll, false))
        XCTAssertEqual(action(.zoom, true), .zoomIn)
        XCTAssertEqual(action(.zoom, false), .zoomOut)
        XCTAssertEqual(action(.tabs, true), .keys(ThumbWheelAction.nextTab))
        XCTAssertEqual(action(.tabs, false), .keys(ThumbWheelAction.previousTab))
        XCTAssertEqual(action(.desktops, true), .named("moveSpaceRight"))
        XCTAssertEqual(action(.desktops, false), .named("moveSpaceLeft"))
        XCTAssertEqual(action(.backForward, true), .named("navigateForward"))
        XCTAssertEqual(action(.backForward, false), .named("navigateBack"))
        XCTAssertEqual(action(.volume, true), .volume(.up))
        XCTAssertEqual(action(.volume, false), .volume(.down))
        // Every named action is one of the action menu's, run as a binding runs it.
        for function in ThumbWheelFunction.allCases {
            for next in [true, false] {
                if case .named(let name)? = action(function, next) {
                    XCTAssertNotNil(SystemShortcut.getShortcut(named: name), name)
                }
            }
        }
    }

    /// Tabs: ⌃⇥ and ⌃⇧⇥ (Tab, key code 48, on every layout); keys of their own, the action
    /// menu's tab actions stay as button bindings use them.
    func testTabs_areControlTabAndControlShiftTab() {
        XCTAssertEqual(ThumbWheelAction.nextTab.code, 48)
        XCTAssertEqual(ThumbWheelAction.nextTab.modifiers, .control)
        XCTAssertEqual(ThumbWheelAction.previousTab.code, 48)
        XCTAssertEqual(ThumbWheelAction.previousTab.modifiers, [.control, .shift])
        XCTAssertNil(SystemShortcut.getShortcut(named: ThumbWheelAction.nextTab.identifier), "not an action of the menu")
        XCTAssertNil(SystemShortcut.getShortcut(named: ThumbWheelAction.previousTab.identifier))
        XCTAssertEqual(SystemShortcut.switchTabRight.code, 124, "the menu's own actions are unchanged")
        XCTAssertEqual(SystemShortcut.switchTabRight.modifiers, [.command, .option])
        XCTAssertEqual(SystemShortcut.nextTab.modifiers, [.command, .shift])
    }

    private func resolved(_ shortcut: SystemShortcut.Shortcut) -> [UInt64] {
        let resolved = SystemShortcut.resolveSystemShortcut(shortcut.identifier)
            ?? (shortcut.code, UInt64(shortcut.modifiers.rawValue))
        return [UInt64(resolved.code), resolved.modifiers]
    }

    /// Keys go through the app's action path (ShortcutExecutor), as a button binding's do;
    /// the executor's test observer receives them instead of the system.
    func testPerformer_runsKeysThroughTheShortcutExecutor() {
        var keys: [[UInt64]] = []
        ShortcutExecutor.shared.setTestingKeyboardShortcutObserver { code, flags, _ in
            keys.append([UInt64(code), flags])
        }
        defer { ShortcutExecutor.shared.clearTestingKeyboardShortcutObserver() }
        let command = UInt64(NSEvent.ModifierFlags.command.rawValue)
        let control = UInt64(NSEvent.ModifierFlags.control.rawValue)
        let shift = UInt64(NSEvent.ModifierFlags.shift.rawValue)
        let performer = ThumbWheelActionPerformer(
            volumeKeys: SystemVolumeKeys(post: { _ in XCTFail("no volume key") }),
            zoomKeys: AppZoomKeys(layout: FakeKeyboardLayout.slovenian)
        )

        performer.perform(ThumbWheelAction.action(for: .tabs, towardNext: true)!, times: 2)
        performer.perform(ThumbWheelAction.action(for: .tabs, towardNext: false)!, times: 1)
        XCTAssertEqual(keys, [[48, control], [48, control], [48, control | shift]])
        keys = []
        performer.perform(.zoomIn, times: 2)
        performer.perform(.zoomOut, times: 1)
        XCTAssertEqual(keys, [[24, command], [24, command], [44, command]], "the layout's \"+\" and \"-\" keys")
        keys = []
        for (function, next) in [(ThumbWheelFunction.desktops, false), (.backForward, true), (.backForward, false)] {
            performer.perform(ThumbWheelAction.action(for: function, towardNext: next)!, times: 1)
        }
        XCTAssertEqual(keys, [
            resolved(SystemShortcut.moveSpaceLeft), resolved(SystemShortcut.navigateForward), resolved(SystemShortcut.navigateBack),
        ])
        keys = []
        performer.perform(.zoomOut, times: 0)
        XCTAssertEqual(keys, [])
    }

    /// The volume keys are pressed as an Apple keyboard presses them, through a seam: nothing
    /// is posted here and the volume does not change.
    func testVolumeKeys_downAndUpAsTheKeyboardSendsThem() throws {
        var events: [CGEvent] = []
        let performer = ThumbWheelActionPerformer(volumeKeys: SystemVolumeKeys(post: { events.append($0) }))
        performer.perform(.volume(.up), times: 1)
        performer.perform(.volume(.down), times: 2)
        XCTAssertEqual(events.count, 6, "each press: down and up")

        let expected = [0x0A00, 0x0B00, 0x1_0A00, 0x1_0B00, 0x1_0A00, 0x1_0B00]
        for (event, data1) in zip(events, expected) {
            let nsEvent = try XCTUnwrap(NSEvent(cgEvent: event))
            XCTAssertEqual(nsEvent.type, .systemDefined)
            XCTAssertEqual(nsEvent.subtype.rawValue, 8, "the keyboard's special keys")
            XCTAssertEqual(nsEvent.data1, data1)
            XCTAssertEqual(event.getIntegerValueField(.eventSourceUserData), MosEventMarker.syntheticCustom, "marked as Scrollio's own")
        }
        XCTAssertEqual(SystemVolumeKey.up.keyType, 0, "NX_KEYTYPE_SOUND_UP")
        XCTAssertEqual(SystemVolumeKey.down.keyType, 1, "NX_KEYTYPE_SOUND_DOWN")
    }

    // MARK: When steps run

    func testSteps_runOnTheMainQueueAfterTheCallback() {
        let rig = Rig()
        let tabs = ThumbWheelSettings(function: .tabs)
        XCTAssertEqual(rig.turn(lines: -1, at: 0, settings: tabs), 0)
        XCTAssertEqual(rig.turn(lines: -1, at: 0.02, settings: tabs), 1)
        XCTAssertEqual(rig.performed, [], "not inside the callback")
        rig.advance(to: 500.02)
        XCTAssertEqual(rig.performed, [Performed(action: .keys(ThumbWheelAction.nextTab), times: 1)])

        // Swapped (or reversed) the same turn is the previous tab.
        XCTAssertEqual(rig.turn(lines: -2, at: 1, settings: tabs, flipped: true), -1)
        rig.advance(to: 501)
        XCTAssertEqual(rig.performed.last, Performed(action: .keys(ThumbWheelAction.previousTab), times: 1))
    }

    func testSeveralStepsOfOneEvent_runTogether() {
        let rig = Rig()
        XCTAssertEqual(rig.turn(lines: -3, at: 0, settings: ThumbWheelSettings(function: .volume, speed: 2)), 6)
        rig.advance(to: 500)
        XCTAssertEqual(rig.performed, [Performed(action: .volume(.up), times: 6)])
    }

    /// Scrollio's scroll handling stopped (Pause, sleep, lost access): steps already decided
    /// do not run afterwards.
    func testReset_dropsStepsNotYetRun_andWritesTheOpenRollsLine() {
        let rig = Rig()
        XCTAssertEqual(rig.turn(lines: -2, at: 0, settings: ThumbWheelSettings(function: .zoom)), 2)
        rig.engine.reset()
        XCTAssertEqual(rig.lines.count, 1, "the roll so far")
        rig.advance(to: 510)
        XCTAssertEqual(rig.performed, [])
        XCTAssertEqual(rig.engine.stepper, ThumbWheelStepper())
        XCTAssertEqual(rig.lines.count, 1)
        XCTAssertFalse(rig.hasPendingWork)
    }

    func testScroll_runsNoSteps() {
        let rig = Rig()
        for index in 0..<10 {
            XCTAssertEqual(rig.turn(lines: -3, at: Double(index) * 0.02, settings: .default), 0)
        }
        rig.advance(to: 510)
        XCTAssertEqual(rig.performed, [])
    }

    // MARK: The log: one line per roll

    func testLog_oneLineOnceTheWheelRested_nothingPerEvent_nothingLeftRunning() throws {
        let rig = Rig()
        let tabs = ThumbWheelSettings(function: .tabs)
        for index in 0..<5 {
            rig.turn(lines: -1, at: Double(index) * 0.05, settings: tabs, continuous: index == 0)
        }
        rig.advance(to: 500.2 + ThumbWheelTuning.rollRest - 0.01)
        XCTAssertEqual(rig.lines.count, 0, "not before the wheel rested")
        rig.advance(to: 500.2 + ThumbWheelTuning.rollRest)
        let roll = try XCTUnwrap(rig.lines.first)
        XCTAssertEqual(rig.lines.count, 1)
        XCTAssertEqual(roll.events, 5)
        XCTAssertEqual(roll.lines, -5)
        XCTAssertEqual(roll.fixed, -5)
        XCTAssertEqual(roll.points, -50)
        XCTAssertEqual(roll.largestPoints, 10)
        XCTAssertEqual(roll.continuousEvents, 1)
        XCTAssertEqual(roll.steps, 2)
        XCTAssertEqual(roll.function, .tabs)
        XCTAssertEqual(roll.lastEventAt - roll.startedAt, 0.2, accuracy: 1e-9)
        XCTAssertEqual(
            ScrollSystemLog.thumbWheelMessage(for: roll),
            "thumb wheel: 5 events in 200 ms, lines -5 (fixed -5.00, points -50, largest 10), partly continuous (1 of 5), switch tabs x1.00: 2 steps"
        )
        XCTAssertFalse(rig.hasPendingWork, "no timer while the wheel is still")
        XCTAssertNil(rig.engine.roll)
    }

    /// The defaults log as well: it is how we learn what a wheel sends.
    func testLog_atTheDefaultsToo() throws {
        let rig = Rig()
        rig.turn(lines: 1, at: 0, settings: .default)
        rig.advance(to: 501)
        let roll = try XCTUnwrap(rig.lines.first)
        XCTAssertEqual(roll.function, .scroll)
        XCTAssertEqual(roll.events, 1)
    }

    /// A long roll: a line every two seconds, then the last one once the wheel rested.
    func testLog_aLongRollWritesALineEveryTwoSeconds() {
        let rig = Rig()
        for index in 0..<50 {
            rig.turn(lines: -1, at: Double(index) / 10, settings: .default)
        }
        rig.advance(to: 510)
        XCTAssertEqual(rig.lines.map(\.events), [20, 20, 10])
        XCTAssertEqual(rig.lines.map(\.startedAt), [500, 502, 504])
        XCTAssertFalse(rig.hasPendingWork)
    }

    /// A setting changed in the middle of a roll (the function, the speed, the direction):
    /// the roll so far gets its own line, written after the callback.
    func testLog_aSettingChangedInTheMiddleOfARollEndsItsLine() {
        let rig = Rig()
        rig.turn(lines: -1, at: 0, settings: ThumbWheelSettings(function: .tabs))
        rig.turn(lines: -1, at: 0.05, settings: ThumbWheelSettings(function: .tabs))
        rig.turn(lines: -1, at: 0.1, settings: ThumbWheelSettings(function: .zoom))
        XCTAssertEqual(rig.lines.count, 0, "nothing written inside the callback")
        rig.advance(to: 500.1)
        XCTAssertEqual(rig.lines.map(\.function), [.tabs])
        XCTAssertEqual(rig.lines.first?.events, 2)
        rig.turn(lines: -1, at: 0.15, settings: ThumbWheelSettings(function: .zoom, speed: 2))
        rig.advance(to: 510)
        XCTAssertEqual(rig.lines.map(\.function), [.tabs, .zoom, .zoom])
        XCTAssertEqual(rig.lines.map(\.speed), [1, 1, 2])
        XCTAssertFalse(rig.hasPendingWork)
    }
}

/// The sideways wheel through the scroll tap's callback, as the tap runs it. Nothing is
/// posted: smoothed input goes to `ScrollCore.posterInputObserverForTests`, steps to a test
/// engine.
final class ThumbWheelScrollTapTests: XCTestCase {

    private var rig: ThumbWheelEngineTests.Rig!
    private var savedEngine: ThumbWheelEngine!
    private var savedThumbWheel = ThumbWheelSettings.default
    private var savedSmooth = true
    private var savedReverse = true
    private var savedReverseHorizontal = true
    private var savedAllowlist = false
    private var inputs: [ScrollPosterInput] = []

    override func setUp() {
        super.setUp()
        savedEngine = ScrollCore.shared.thumbWheelEngine
        savedThumbWheel = Options.shared.thumbWheel
        savedSmooth = Options.shared.scroll.smooth
        savedReverse = Options.shared.scroll.reverse
        savedReverseHorizontal = Options.shared.scroll.reverseHorizontal
        savedAllowlist = Options.shared.application.allowlist
        rig = ThumbWheelEngineTests.Rig()
        ScrollCore.shared.thumbWheelEngine = rig.engine
        ScrollCore.shared.handover = ScrollHandover()
        ScrollCore.posterInputObserverForTests = { [unowned self] input in self.inputs.append(input) }
        inputs = []
        Options.shared.thumbWheel = .default
        Options.shared.scroll.smooth = true
        Options.shared.scroll.reverse = false
        Options.shared.scroll.reverseHorizontal = true
        Options.shared.application.allowlist = false
    }

    override func tearDown() {
        ScrollCore.posterInputObserverForTests = nil
        ScrollCore.shared.thumbWheelEngine = savedEngine
        ScrollCore.shared.handover = ScrollHandover()
        ScrollCore.shared.toggleScroll = false
        Options.shared.thumbWheel = savedThumbWheel
        Options.shared.scroll.smooth = savedSmooth
        Options.shared.scroll.reverse = savedReverse
        Options.shared.scroll.reverseHorizontal = savedReverseHorizontal
        Options.shared.application.allowlist = savedAllowlist
        ScrollSystemLog.resetPassthroughForTests()
        super.tearDown()
    }

    /// A wheel event as a mouse sends it: no phase, not continuous, aimed at no app.
    private func wheelEvent(
        line2: Int64 = 0, fixed2: Double = 0, point2: Double = 0,
        line1: Int64 = 0, point1: Double = 0, flags: CGEventFlags = []
    ) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 0, wheel2: 0, wheel3: 0))
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: line1)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: point1)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Double(line1))
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: line2)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: point2)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: fixed2)
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 0)
        event.setIntegerValueField(.eventTargetUnixProcessID, value: 1)
        event.flags = flags
        return event
    }

    private func sideways(_ lines: Int64, point: Double? = nil, flags: CGEventFlags = []) throws -> CGEvent {
        return try wheelEvent(line2: lines, fixed2: Double(lines), point2: point ?? Double(lines * 10), flags: flags)
    }

    /// The tap's callback. Its result is an unretained reference: use it while `event` lives.
    @discardableResult
    private func tap(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        return ScrollCore.shared.scrollEventCallBack(CGEventTapProxy(bitPattern: 1)!, .scrollWheel, event, nil)
    }

    /// Whether the tap lets the event go on (false: swallowed).
    private func goesOn(_ event: CGEvent) -> Bool {
        return tap(event) != nil
    }

    /// The X fields of an event: line, fixed-point, point.
    private func xFields(_ event: CGEvent) -> [Double] {
        return [
            Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2)),
            event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2),
            event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2),
        ]
    }

    // MARK: The defaults change nothing

    /// At the defaults (scroll, × 1, not swapped) the poster gets exactly what it got before
    /// the thumb wheel had settings, value for value: the formula of before, written out here.
    func testAtTheDefaults_aSmoothedSidewaysEventGivesThePosterWhatItGaveBefore() throws {
        let step = Options.shared.scroll.step
        let speed = Options.shared.scroll.speed
        let duration = Options.shared.scroll.durationTransition
        let dash = ScrollCore.shared.dashAmplification
        let samples: [(line: Int64, fixed: Double, point: Double)] = [
            (1, 1, 10), (-1, -1, -10), (1, 0.25, 3), (-3, -3.5, -39), (12, 12.25, 140), (0, 0.5, 0), (2, 0, 0), (-7, 0, 0), (0, 0, 5),
        ]
        var count = 0
        for reverse in [false, true] {
            Options.shared.scroll.reverse = reverse
            for sample in samples {
                let event = try wheelEvent(line2: sample.line, fixed2: sample.fixed, point2: sample.point)
                // Before: the point delta, else the fixed-point one, else the line delta;
                // turned around by "Reverse wheel direction"; at least one Step; × Speed × dash.
                let point = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
                let fixed = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
                var usable = point != 0 ? point : (fixed != 0 ? fixed : Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2)))
                if reverse { usable = -usable }
                let distance = usable > 0 ? max(usable.magnitude, step) : -max(usable.magnitude, step)
                let gain = speed * dash
                inputs = []

                tap(event)
                count += 1

                let label = "\(sample), reverse \(reverse)"
                let input = try XCTUnwrap(inputs.first, label)
                XCTAssertEqual(inputs.count, 1, label)
                XCTAssertEqual(input.x, distance * gain, label)
                XCTAssertEqual(input.y, 0.0 * gain, label)
                XCTAssertEqual(input.notch, step * gain, label)
                XCTAssertEqual(input.duration, duration, label)
            }
        }
        XCTAssertEqual(rig.performed, [])
        XCTAssertEqual(rig.engine.roll?.events, count, "every sideways event is in the log line")
    }

    /// Smoothing off: the event goes on as before, turned around only by the reverse rule.
    func testAtTheDefaults_anUnsmoothedSidewaysEventGoesOnAsBefore() throws {
        Options.shared.scroll.smooth = false
        for reverse in [false, true] {
            Options.shared.scroll.reverse = reverse
            let event = try wheelEvent(line2: -2, fixed2: -2.5, point2: -27)
            let before = xFields(event)
            let result = tap(event)
            XCTAssertTrue(result?.takeUnretainedValue() === event, "reverse \(reverse)")
            XCTAssertEqual(xFields(event), before.map { reverse ? -$0 : $0 }, "reverse \(reverse)")
        }
        XCTAssertEqual(inputs.count, 0)
    }

    // MARK: Speed and direction while it scrolls

    func testSpeed_scalesTheDistanceAndTheNotchOfASmoothedSidewaysEvent() throws {
        tap(try sideways(-3))
        let atOne = try XCTUnwrap(inputs.last)
        Options.shared.thumbWheel.speed = 2.5
        tap(try sideways(-3))
        let faster = try XCTUnwrap(inputs.last)
        XCTAssertEqual(faster.x, atOne.x * 2.5, accuracy: 1e-9)
        XCTAssertEqual(faster.notch, atOne.notch * 2.5, accuracy: 1e-9)
        XCTAssertEqual(faster.duration, atOne.duration)

        // Not the main wheel's events.
        tap(try wheelEvent(line1: -3, point1: -30))
        let vertical = try XCTUnwrap(inputs.last)
        Options.shared.thumbWheel.speed = 1
        tap(try wheelEvent(line1: -3, point1: -30))
        XCTAssertEqual(vertical.y, try XCTUnwrap(inputs.last).y)
        XCTAssertEqual(vertical.notch, try XCTUnwrap(inputs.last).notch)

        // Not an event let through unsmoothed.
        Options.shared.thumbWheel.speed = 3
        Options.shared.scroll.smooth = false
        let event = try sideways(-3)
        let before = xFields(event)
        tap(event)
        XCTAssertEqual(xFields(event), before)
    }

    /// "Swap direction" turns the sideways wheel around once more, after the reverse rule,
    /// smoothed or let through.
    func testSwap_turnsTheSidewaysWheelAroundAfterTheReverseRule() throws {
        Options.shared.thumbWheel.swapsDirection = true
        tap(try sideways(-2))
        XCTAssertGreaterThan(try XCTUnwrap(inputs.last).x, 0, "swapped: −2 lines scroll the other way")

        Options.shared.scroll.smooth = false
        for reverse in [false, true] {
            Options.shared.scroll.reverse = reverse
            let event = try sideways(-2, point: -23)
            let before = xFields(event)
            tap(event)
            XCTAssertEqual(xFields(event), before.map { reverse ? $0 : -$0 }, "reverse \(reverse): one flip, or two that cancel")
        }
        // The main wheel is not swapped.
        Options.shared.scroll.reverse = false
        let vertical = try wheelEvent(line1: -2, point1: -20)
        tap(vertical)
        XCTAssertEqual(vertical.getIntegerValueField(.scrollWheelEventDeltaAxis1), -2)
    }

    // MARK: A function

    /// Tabs: the sideways event is swallowed, it reaches no poster and no app, the trackpad's
    /// glide that runs is not taken over, and the step runs after the callback.
    func testAFunction_swallowsTheSidewaysEvent_andItsStepRunsAfterTheCallback() throws {
        Options.shared.thumbWheel = ThumbWheelSettings(function: .tabs)
        XCTAssertEqual(ScrollCore.shared.handover.trackpadEvent(scrollPhase: 0, momentumPhase: 1, hasDelta: true), .letThrough)
        XCTAssertEqual(ScrollCore.shared.handover.state, .glide)

        XCTAssertFalse(goesOn(try sideways(-1)))
        XCTAssertFalse(goesOn(try sideways(-1)))

        XCTAssertEqual(inputs.count, 0, "no glide starts or changes")
        XCTAssertEqual(ScrollCore.shared.handover.state, .glide, "the trackpad's glide goes on")
        XCTAssertEqual(rig.performed, [], "nothing runs inside the callback")
        rig.advance(to: rig.now)
        XCTAssertEqual(rig.performed, [ThumbWheelEngineTests.Performed(action: .keys(ThumbWheelAction.nextTab), times: 1)])
    }

    /// The function does not depend on "Smooth scrolling", the allowlist or the reverse rule's
    /// absence: every sideways event is swallowed. The direction follows the reverse rule.
    func testAFunction_doesNotDependOnSmoothingOrTheAllowlist() throws {
        Options.shared.thumbWheel = ThumbWheelSettings(function: .zoom)
        Options.shared.scroll.smooth = false
        XCTAssertFalse(goesOn(try sideways(-1)))
        Options.shared.application.allowlist = true
        XCTAssertFalse(goesOn(try sideways(-1)))
        Options.shared.application.allowlist = false
        Options.shared.scroll.smooth = true
        Options.shared.scroll.reverse = true
        XCTAssertFalse(goesOn(try sideways(-1)))
        rig.advance(to: rig.now)
        XCTAssertEqual(rig.performed.map(\.action), [
            .zoomIn, .zoomIn, .zoomOut,
        ])
        XCTAssertEqual(inputs.count, 0)
    }

    /// The main wheel (vertical), an event with both deltas, the main wheel turned sideways
    /// with a hold key, and the trackpad: none is a sideways event; they go as before.
    func testOtherEvents_areNotSidewaysEvents() throws {
        Options.shared.thumbWheel = ThumbWheelSettings(function: .tabs)
        Options.shared.scroll.smooth = false
        // The trackpad's glide, moving sideways.
        let trackpad = try XCTUnwrap(TracedScrollEvent.momentum(2, point: 0).cgEvent())
        trackpad.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: -4)
        trackpad.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: -40)
        trackpad.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -4)
        let others: [(String, CGEvent)] = [
            ("vertical", try wheelEvent(line1: -3, point1: -30)),
            ("both", try wheelEvent(line2: -3, fixed2: -3, point2: -30, line1: -1, point1: -10)),
            ("Shift held", try sideways(-3, flags: .maskShift)),
            ("trackpad", trackpad),
        ]
        for (label, event) in others {
            XCTAssertTrue(goesOn(event), label)
        }
        let withHoldKey = try sideways(-3)
        ScrollCore.shared.toggleScroll = true
        let passedOn = goesOn(withHoldKey)
        ScrollCore.shared.toggleScroll = false
        XCTAssertTrue(passedOn, "Scrollio's hold key turns the main wheel sideways")
        rig.advance(to: rig.now + 10)
        XCTAssertEqual(rig.performed, [])
        XCTAssertEqual(rig.lines, [], "and none is in the thumb wheel's log")
    }

    // MARK: The decisions (pure)

    func testSidewaysWheelEvent_horizontalOnly_notRemoteSmoothed_noHoldKey() {
        func sideways(v: Bool, h: Bool, remote: Bool = false, hold: Bool = false) -> Bool {
            return ScrollCore.isSidewaysWheelEvent(hasVerticalDelta: v, hasHorizontalDelta: h, remoteSmoothed: remote, holdKeyDown: hold)
        }
        XCTAssertTrue(sideways(v: false, h: true))
        XCTAssertFalse(sideways(v: true, h: false), "the main wheel")
        XCTAssertFalse(sideways(v: true, h: true), "both: as before")
        XCTAssertFalse(sideways(v: false, h: false))
        XCTAssertFalse(sideways(v: false, h: true, remote: true))
        XCTAssertFalse(sideways(v: false, h: true, hold: true))
    }

    func testFlipsHorizontal_swapTurnsAroundOnceMore() {
        XCTAssertFalse(ScrollCore.flipsHorizontal(reverseRule: false, swapsSideways: false))
        XCTAssertTrue(ScrollCore.flipsHorizontal(reverseRule: true, swapsSideways: false))
        XCTAssertTrue(ScrollCore.flipsHorizontal(reverseRule: false, swapsSideways: true))
        XCTAssertFalse(ScrollCore.flipsHorizontal(reverseRule: true, swapsSideways: true))
    }

    /// With the sideways speed 1 the poster's input is the formula of before for any values.
    func testPosterInput_atSidewaysSpeedOneIsTheFormulaOfBefore() {
        for step in [1.0, 33.6, 50] {
            for speed in [0.7, 2.7, 6.3, 9.9] {
                for dash in [1.0, 5.0] {
                    for (y, x) in [(0.0, 33.6), (0, -217.3), (88.1, 0), (-33.6, 12.5)] {
                        let input = ScrollCore.posterInput(smoothedY: y, smoothedX: x, step: step, speed: speed, dash: dash, sidewaysSpeed: 1, duration: 0.2)
                        let gain = speed * dash
                        XCTAssertEqual(input.y, y * gain)
                        XCTAssertEqual(input.x, x * gain)
                        XCTAssertEqual(input.notch, step * gain)
                        XCTAssertEqual(input.duration, 0.2)
                    }
                }
            }
        }
    }
}

// MARK: - The zoom keys of the layout in use

/// A keyboard layout for tests: its id and what its keys type with no modifier (the keys
/// around the zoom keys and the keypad, as the real layouts have them).
final class FakeKeyboardLayout: KeyboardLayoutSource {
    var id: String?
    var characters: [CGKeyCode: String]
    /// How often the layout's keys were translated.
    private(set) var translations = 0

    init(id: String?, characters: [CGKeyCode: String]) {
        self.id = id
        self.characters = characters
    }

    func currentLayoutID() -> String? { return id }

    func currentCharacters() -> [CGKeyCode: String] {
        translations += 1
        return characters
    }

    private static let keypad: [CGKeyCode: String] = [69: "+", 78: "-", 81: "="]

    static var us: FakeKeyboardLayout {
        return FakeKeyboardLayout(id: "com.apple.keylayout.US", characters: keypad.merging([0: "a", 24: "=", 27: "-", 30: "]", 44: "/"]) { $1 })
    }
    /// QWERTZ: "+" on the US "=" key, "/" on the US "-" key, "-" on the US "/" key.
    static var slovenian: FakeKeyboardLayout {
        return FakeKeyboardLayout(id: "com.apple.keylayout.Slovenian", characters: keypad.merging([0: "a", 24: "+", 27: "/", 30: "đ", 44: "-"]) { $1 })
    }
    /// QWERTZ: a dead "´" on the US "=" key, "ß" on the US "-" key, "+" on the US "]" key.
    static var german: FakeKeyboardLayout {
        return FakeKeyboardLayout(id: "com.apple.keylayout.German", characters: keypad.merging([0: "a", 24: "´", 27: "ß", 30: "+", 44: "-"]) { $1 })
    }
    /// AZERTY: "-" on the US "=" key, ")" on the US "-" key, "=" on the US "/" key, no "+".
    static var french: FakeKeyboardLayout {
        return FakeKeyboardLayout(id: "com.apple.keylayout.French", characters: keypad.merging([0: "q", 24: "-", 27: ")", 30: "$", 44: "="]) { $1 })
    }
}

/// ⌘ with the keys that type "+" (else "=") and "-" on the layout in use: zoom works on any
/// keyboard layout, not only the US one.
final class AppZoomKeysTests: XCTestCase {

    private func codes(_ layout: FakeKeyboardLayout) -> AppZoomKeys.Codes {
        return AppZoomKeys(layout: layout).codes()
    }

    func testUSLayout_givesTheKeysOfBefore() {
        XCTAssertEqual(AppZoomKeys.usCodes, AppZoomKeys.Codes(zoomIn: 24, zoomOut: 27))
        XCTAssertEqual(codes(.us), AppZoomKeys.Codes(zoomIn: 24, zoomOut: 27), "\"=\" and \"-\", not the keypad's")
    }

    func testOtherLayouts_giveTheirOwnKeys() {
        XCTAssertEqual(codes(.slovenian), AppZoomKeys.Codes(zoomIn: 24, zoomOut: 44))
        XCTAssertEqual(codes(.german), AppZoomKeys.Codes(zoomIn: 30, zoomOut: 44))
        XCTAssertEqual(codes(.french), AppZoomKeys.Codes(zoomIn: 44, zoomOut: 24), "no \"+\" without Shift: \"=\"")
    }

    func testALayoutWithoutTheCharacters_fallsBackToTheUSKeys() {
        let letters = FakeKeyboardLayout(id: "letters", characters: [0: "a", 24: "ä", 27: "ö"])
        XCTAssertEqual(codes(letters), AppZoomKeys.usCodes)
        let onlyTheKeypad = FakeKeyboardLayout(id: "keypad", characters: [69: "+", 78: "-", 81: "="])
        XCTAssertEqual(codes(onlyTheKeypad), AppZoomKeys.usCodes, "the keypad is left out")
        let onlyMinus = FakeKeyboardLayout(id: "minus", characters: [44: "-"])
        XCTAssertEqual(codes(onlyMinus), AppZoomKeys.Codes(zoomIn: 24, zoomOut: 44), "each key on its own")
        XCTAssertEqual(codes(FakeKeyboardLayout(id: "empty", characters: [:])), AppZoomKeys.usCodes)
        let none = FakeKeyboardLayout(id: nil, characters: FakeKeyboardLayout.slovenian.characters)
        XCTAssertEqual(codes(none), AppZoomKeys.usCodes, "no layout in use")
        XCTAssertEqual(none.translations, 0)
    }

    /// The 128 keys are translated once per layout, not at every step; a change of layout is
    /// noticed by its id.
    func testTheAnswerIsKeptPerLayout_andALayoutChangeIsNoticed() {
        let layout = FakeKeyboardLayout.us
        let keys = AppZoomKeys(layout: layout)
        for _ in 0..<5 {
            XCTAssertEqual(keys.codes(), AppZoomKeys.Codes(zoomIn: 24, zoomOut: 27))
        }
        XCTAssertEqual(layout.translations, 1)

        layout.id = FakeKeyboardLayout.slovenian.id
        layout.characters = FakeKeyboardLayout.slovenian.characters
        XCTAssertEqual(keys.codes(), AppZoomKeys.Codes(zoomIn: 24, zoomOut: 44))
        XCTAssertEqual(keys.codes(), AppZoomKeys.Codes(zoomIn: 24, zoomOut: 44))
        XCTAssertEqual(layout.translations, 2)
    }

    /// The real translation (UCKeyTranslate) of installed layouts, picked by id: the layout
    /// the Mac types with does not matter.
    func testInstalledLayouts_translateAsTheFakesSay() throws {
        func installed(_ id: String) throws -> TISInputSource {
            let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
            guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as NSArray?,
                  let first = list.firstObject else {
                throw XCTSkip("\(id) is not installed")
            }
            return first as! TISInputSource
        }
        for fake in [FakeKeyboardLayout.us, .slovenian, .german, .french] {
            let id = try XCTUnwrap(fake.id)
            let source = try installed(id)
            XCTAssertEqual(SystemKeyboardLayoutSource.id(of: source), id)
            let characters = SystemKeyboardLayoutSource.characters(of: source)
            for (code, character) in fake.characters {
                XCTAssertEqual(characters[code], character, "\(id) key \(code)")
            }
            XCTAssertEqual(AppZoomKeys.codes(typing: characters), codes(fake), id)
        }
    }
}
