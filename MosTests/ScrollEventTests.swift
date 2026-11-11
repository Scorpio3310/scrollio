//
//  ScrollEventTests.swift
//  MosTests
//
//  ScrollEvent 事件解析优先级/reverse/normalize/clear 测试 (Task 8)
//

import XCTest
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

    // MARK: The log

    func testLog_saysWhatTheHandOverDid() throws {
        XCTAssertEqual(
            ScrollSystemLog.wheelTookOverMessage(droppedMomentumEvents: 5),
            "handover: the wheel took over a trackpad glide: 5 momentum events dropped"
        )
        let event = try XCTUnwrap(TracedScrollEvent.momentum(2, point: 22).cgEvent())
        let line = ScrollHandoverTrace.describe(event, takenForTrackpad: true, swallowed: true, sinceOther: 0.012)
        XCTAssertTrue(line.hasPrefix("handover S +12 ms phase 0 momentum 2 count 1 continuous 1"), line)
    }
}
