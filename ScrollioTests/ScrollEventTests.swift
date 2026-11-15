//
//  ScrollEventTests.swift
//  MosTests
//
//  ScrollEvent 事件解析优先级/reverse/normalize/clear 测试 (Task 8)
//

import XCTest
import Carbon.HIToolbox
@testable import Scrollio_Debug

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

    // MARK: The glide's "ended" that carries the wheel's delta

    /// C9: when the wheel turns during a trackpad glide, macOS sends a momentum "ended" that
    /// carries the wheel's delta, then the wheel event itself. The first went through as it
    /// came, the second was smoothed: the delta reached the app twice, the first time raw and
    /// unreversed. The "ended" still goes on (it closes the glide), without the delta.
    func testTheEndedThatComesWithTheWheel_goesOnWithoutTheWheelsDelta() throws {
        defer { ScrollCore.shared.handover = ScrollHandover() }
        ScrollCore.shared.handover = ScrollHandover()
        var reasons: [ScrollSystemLog.PassthroughReason] = []
        ScrollSystemLog.passthroughObserverForTests = { reasons.append($0) }
        defer { ScrollSystemLog.passthroughObserverForTests = nil }

        // As in the trace (1 line, 1 px) and with the wheel already spinning (13 lines, 133 px).
        for (line, point) in [(Int64(-1), -1.0), (-13, -133)] {
            let marker = try XCTUnwrap(TracedScrollEvent.wheelMarker(count: 1, line: line, point: point).cgEvent())
            let result = ScrollCore.shared.scrollEventCallBack(CGEventTapProxy(bitPattern: 1)!, .scrollWheel, marker, nil)
            XCTAssertTrue(result?.takeUnretainedValue() === marker, "it goes on: the app closes the glide")
            XCTAssertEqual(marker.getDoubleValueField(.scrollWheelEventMomentumPhase), 3)
            XCTAssertEqual(marker.getIntegerValueField(.scrollWheelEventDeltaAxis1), 0)
            XCTAssertEqual(marker.getDoubleValueField(.scrollWheelEventPointDeltaAxis1), 0)
            XCTAssertEqual(marker.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1), 0)
        }
        XCTAssertEqual(reasons, [], "not a trackpad event that moved the page")

        // A trackpad's own events are continuous: their deltas are never touched.
        for traced in [TracedScrollEvent.momentum(3, point: 4), .momentum(2, point: 22), .touch(2, point: 30)] {
            let event = try XCTUnwrap(traced.cgEvent())
            let result = ScrollCore.shared.scrollEventCallBack(CGEventTapProxy(bitPattern: 1)!, .scrollWheel, event, nil)
            XCTAssertNotNil(result)
            XCTAssertEqual(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1), traced.point)
        }
    }

    func testCarriesTheWheelsDelta_isOnlyTheEndedThatIsNotContinuous() {
        XCTAssertTrue(ScrollHandover.carriesTheWheelsDelta(momentumPhase: 3, isContinuous: 0, hasDelta: true))
        XCTAssertFalse(ScrollHandover.carriesTheWheelsDelta(momentumPhase: 3, isContinuous: 1, hasDelta: true), "a trackpad's own")
        XCTAssertFalse(ScrollHandover.carriesTheWheelsDelta(momentumPhase: 3, isContinuous: 0, hasDelta: false), "the real end of the glide")
        XCTAssertFalse(ScrollHandover.carriesTheWheelsDelta(momentumPhase: 2, isContinuous: 0, hasDelta: true))
        XCTAssertFalse(ScrollHandover.carriesTheWheelsDelta(momentumPhase: 0, isContinuous: 0, hasDelta: true), "a wheel event")
    }
}

// MARK: - The sideways wheel (thumb wheel)

/// The stepper of the thumb wheel's functions: it counts events, not lines (the owner's log of
/// 2026-11-11: macOS accelerates one event of his MX Master 4 from 0.1 to 12 lines).
final class ThumbWheelStepperTests: XCTestCase {

    private func lines(_ line: Int64, _ fixed: Double, _ point: Double) -> Double {
        return ThumbWheelStepper.lines(lineDelta: line, fixedDelta: fixed, pointDelta: point)
    }

    /// Travel toward "next" of an event of `lines` (fixed-point = these, integer rounded).
    private func travel(_ lines: Double, _ function: ThumbWheelFunction, flipped: Bool = false, speed: Double = 1) -> Double {
        return ThumbWheelStepper.travel(
            lineDelta: Int64(lines.rounded()), fixedDelta: lines, pointDelta: (lines * 10).rounded(),
            flipped: flipped, speed: speed, function: function
        )
    }

    /// Feeds one event per element (its lines; negative = toward "next"), `gaps[i]` seconds
    /// before event i (the first at 0; a single gap repeats). Returns the steps of each event.
    private func run(_ stepper: inout ThumbWheelStepper, _ events: [Double], _ function: ThumbWheelFunction,
                     gaps: [Double] = [0.05], speed: Double = 1, start: Double = 0) -> [Int] {
        var time = start
        var steps: [Int] = []
        for (index, lines) in events.enumerated() {
            if index > 0 { time += gaps.count == 1 ? gaps[0] : gaps[index - 1] }
            steps.append(stepper.feed(travel: travel(lines, function, speed: speed), function: function, at: time))
        }
        return steps
    }

    private func total(_ steps: [Int]) -> Int { return steps.reduce(0, +) }

    /// Where the steps came: the 1-based numbers of the events that stepped.
    private func stepAt(_ steps: [Int]) -> [Int] {
        return steps.enumerated().filter { $0.element != 0 }.map { $0.offset + 1 }
    }

    // MARK: The numbers

    func testNumbers_fromTheOwnersLog() {
        XCTAssertEqual(ThumbWheelFunction.volume.stepping, ThumbWheelStepping(first: 2, next: 3, accelerates: true, rest: 0.6))
        XCTAssertEqual(ThumbWheelFunction.zoom.stepping, ThumbWheelStepping(first: 3, next: 5, accelerates: true, rest: 0.6))
        XCTAssertEqual(ThumbWheelFunction.tabs.stepping, ThumbWheelStepping(first: 3, next: 5, accelerates: false, rest: 0.6))
        XCTAssertEqual(ThumbWheelFunction.desktops.stepping, ThumbWheelStepping(first: 3, next: 5, accelerates: false, rest: 0.6))
        XCTAssertEqual(ThumbWheelFunction.backForward.stepping, ThumbWheelStepping(first: 3, next: 12, accelerates: false, rest: 0.3))
        XCTAssertNil(ThumbWheelFunction.scroll.stepping)
        XCTAssertEqual(ThumbWheelTuning.maxStepsPerEvent, 2)
        XCTAssertEqual(ThumbWheelTuning.logRollRest, 0.6)
        XCTAssertEqual(ThumbWheelTuning.pointsPerLine, 10)
    }

    // MARK: Travel of one event

    func testLines_fixedPointFirst_thenTheLineDelta_thenPointsOverTen_withoutACap() {
        XCTAssertEqual(lines(2, 1.25, 30), 1.25)
        XCTAssertEqual(lines(-2, 0, -30), -2)
        XCTAssertEqual(lines(0, 0, -7), -0.7, accuracy: 1e-12)
        XCTAssertEqual(lines(0, 0, 0), 0)
        XCTAssertEqual(lines(12, 12.3, 124), 12.3, "a flick: no cap any more")
        XCTAssertEqual(lines(0, .infinity, 0), 0, "not a number: no travel")
    }

    /// 1 unit up to 2 lines, 1.5 at 6, 2 from 10 lines on; only for a function that accelerates.
    func testUnits_theAccelerationCurve() {
        for (lines, expected) in [(0.1, 1.0), (2, 1), (6, 1.5), (10, 2), (12, 2), (-6, 1.5), (4, 1.25)] {
            XCTAssertEqual(ThumbWheelStepper.units(lines: lines, accelerates: true), expected, accuracy: 1e-12, "\(lines) lines")
            XCTAssertEqual(ThumbWheelStepper.units(lines: lines, accelerates: false), 1, "\(lines) lines, not accelerating")
        }
        XCTAssertEqual(ThumbWheelStepper.units(lines: 0, accelerates: true), 0, "no lines, no travel")
    }

    /// One unit per event, whatever its lines (two at most when the function accelerates);
    /// a negative X delta is "next", "Swap direction" turns it around; × the speed.
    func testTravel_unitsPerEvent_direction_speed() {
        XCTAssertEqual(travel(-0.1, .tabs), 1)
        XCTAssertEqual(travel(-12, .tabs), 1, "tabs do not accelerate")
        XCTAssertEqual(travel(-12, .desktops), 1)
        XCTAssertEqual(travel(-12, .backForward), 1)
        XCTAssertEqual(travel(-12, .volume), 2)
        XCTAssertEqual(travel(-6, .zoom), 1.5)
        XCTAssertEqual(travel(1, .volume), -1, "previous")
        XCTAssertEqual(travel(1, .volume, flipped: true), 1)
        XCTAssertEqual(travel(-1, .tabs, speed: 0.25), 0.25)
        XCTAssertEqual(travel(-1, .tabs, speed: 3), 3)
        XCTAssertEqual(travel(-12, .volume, speed: 3), 6)
        XCTAssertEqual(travel(-12, .volume, speed: 50), 6, "the speed stays inside its range")
        XCTAssertEqual(travel(-3, .scroll), 0, "no steps while the wheel scrolls")
    }

    // MARK: First and next

    func testFirstThenNext() {
        var tabs = ThumbWheelStepper()
        XCTAssertEqual(stepAt(run(&tabs, Array(repeating: -1, count: 13), .tabs)), [3, 8, 13], "first 3, then every 5")
        var volume = ThumbWheelStepper()
        XCTAssertEqual(stepAt(run(&volume, Array(repeating: -1, count: 8), .volume)), [2, 5, 8], "first 2, then every 3")
        var desktops = ThumbWheelStepper()
        XCTAssertEqual(stepAt(run(&desktops, Array(repeating: -1, count: 13), .desktops)), [3, 8, 13], "first 3, then every 5")
        var back = ThumbWheelStepper()
        XCTAssertEqual(stepAt(run(&back, Array(repeating: -1, count: 27), .backForward)), [3, 15, 27], "first 3, then every 12")
        var previous = ThumbWheelStepper()
        XCTAssertEqual(run(&previous, [1, 1, 1], .tabs), [0, 0, -1], "toward previous")
    }

    /// A step uses up its threshold; what is left goes toward the next one.
    func testAStepUsesUpItsThreshold_theRemainderIsCarried() {
        var stepper = ThumbWheelStepper()
        XCTAssertEqual(stepper.feed(travel: 2.5, function: .volume, at: 0), 1)
        XCTAssertEqual(stepper.carried, 0.5, accuracy: 1e-12)
        XCTAssertEqual(stepper.feed(travel: 2.5, function: .volume, at: 0.05), 1, "0.5 + 2.5 reaches the next 3")
        XCTAssertEqual(stepper.carried, 0, accuracy: 1e-12)
        XCTAssertEqual(stepper.feed(travel: 1.75, function: .volume, at: 0.1), 0)
        XCTAssertEqual(stepper.feed(travel: 1.75, function: .volume, at: 0.15), 1)
        XCTAssertEqual(stepper.carried, 0.5, accuracy: 1e-12)
    }

    // MARK: Rest

    func testRest_dropsTheCarry_andMakesTheNextStepAFirstOne() {
        var tabs = ThumbWheelStepper()
        XCTAssertEqual(run(&tabs, [-1, -1], .tabs), [0, 0])
        XCTAssertEqual(tabs.feed(travel: 1, function: .tabs, at: 0.05 + 0.61), 0, "the two before were dropped")
        XCTAssertEqual(tabs.carried, 1)

        var kept = ThumbWheelStepper()
        XCTAssertEqual(run(&kept, [-1, -1, -1], .tabs, gaps: [0.59]), [0, 0, 1], "a shorter pause keeps the carry")

        var again = ThumbWheelStepper()
        XCTAssertEqual(stepAt(run(&again, [-1, -1, -1, -1, -1, -1], .tabs, gaps: [0.05, 0.05, 0.7, 0.05, 0.05])), [3, 6],
                       "after a rest the next step needs 3 again, not 5")
    }

    /// A batch the stray-tick filter confirmed (held ticks and the event that confirmed them)
    /// began at its first held tick: the rest is measured there, not up to 0.45 s later.
    func testRest_isMeasuredAtTheFirstHeldEventOfAConfirmedBatch() {
        var regrip = ThumbWheelStepper()
        XCTAssertEqual(run(&regrip, [-1, -1], .tabs), [0, 0])
        XCTAssertEqual(regrip.feed(travel: 2, function: .tabs, at: 0.05 + 0.65, heldSince: 0.05 + 0.55), 1,
                       "held 0.55 s after the last event, confirmed at 0.65 s: no rest, 2 + 2 reach the first 3")
        var rested = ThumbWheelStepper()
        XCTAssertEqual(run(&rested, [-1, -1], .tabs), [0, 0])
        XCTAssertEqual(rested.feed(travel: 2, function: .tabs, at: 0.05 + 0.7, heldSince: 0.05 + 0.6), 0, "held from 0.6 s on: a rest")
        XCTAssertEqual(rested.carried, 2)
    }

    /// Each function has its own rest: 0.3 s for back / forward (two quick strokes are two
    /// steps), 0.6 s for the others (a slow roll's gaps reach 0.4 s, a re-grip 0.6 s).
    func testRest_isPerFunction() {
        var back = ThumbWheelStepper()
        XCTAssertEqual(run(&back, [-1, -1, -1], .backForward, gaps: [0.05, 0.35]), [0, 0, 0], "0.35 s is a rest for back / forward")
        var desktops = ThumbWheelStepper()
        XCTAssertEqual(run(&desktops, [-1, -1, -1], .desktops, gaps: [0.05, 0.35]), [0, 0, 1], "not for desktops")
        var tabs = ThumbWheelStepper()
        XCTAssertEqual(run(&tabs, [-1, -1, -1], .tabs, gaps: [0.05, 0.35]), [0, 0, 1], "but not for tabs")
        var strokes = ThumbWheelStepper()
        XCTAssertEqual(stepAt(run(&strokes, Array(repeating: -1, count: 6), .backForward, gaps: [0.05, 0.05, 0.31, 0.05, 0.05])), [3, 6],
                       "a second quick stroke steps again after 3 events")
    }

    // MARK: Direction

    /// A change of direction drops the carry and makes the next step a first one; the event
    /// that turned counts its own travel toward the new direction.
    func testDirectionChange_dropsTheCarry_firstAgain_theTurningEventCounts() {
        var tabs = ThumbWheelStepper()
        XCTAssertEqual(run(&tabs, [-1, -1, 1, 1, 1], .tabs), [0, 0, 0, 0, -1])
        var afterAStep = ThumbWheelStepper()
        XCTAssertEqual(run(&afterAStep, [-1, -1, -1, -1, 1, 1, 1], .tabs), [0, 0, 1, 0, 0, 0, -1],
                       "back the other way needs the first 3, not the next 5")
        XCTAssertEqual(afterAStep.direction, -1)
    }

    // MARK: Limit per event

    func testAtMostTwoStepsPerEvent_theTravelOfFurtherStepsIsDropped() {
        var stepper = ThumbWheelStepper()
        XCTAssertEqual(stepper.feed(travel: 20, function: .volume, at: 0), 2)
        XCTAssertEqual(stepper.carried, 0, accuracy: 1e-12, "20 − 2 − 3 = 15: five more steps' worth, dropped")
        XCTAssertEqual(stepper.feed(travel: 1, function: .volume, at: 0.05), 0, "no burst afterwards")
        XCTAssertEqual(stepper.feed(travel: -13, function: .volume, at: 0.1), -2)
        XCTAssertEqual(stepper.carried, -2, accuracy: 1e-12, "13 − 2 − 3 = 8: two more steps dropped, 2 carried")

        // The fastest flick at speed 3: never more than 2 steps from one event.
        var fast = ThumbWheelStepper()
        let steps = run(&fast, Array(repeating: -12, count: 10), .volume, gaps: [0.015], speed: 3)
        XCTAssertTrue(steps.allSatisfy { $0 <= 2 }, "\(steps)")
    }

    /// A batch the stray-tick filter confirmed gives one step at most, whatever the speed
    /// makes of it; the travel of a further step is dropped, less than a step stays carried.
    func testAConfirmedBatch_givesOneStepAtMost() {
        var batch = ThumbWheelStepper()
        XCTAssertEqual(batch.feed(travel: 9, function: .volume, at: 0.3, heldSince: 0), 1, "9 units: two steps' worth (2 + 3)")
        XCTAssertEqual(batch.carried, 1, accuracy: 1e-12, "9 − 2 = 7: one more step's worth dropped, 1 carried")
        var event = ThumbWheelStepper()
        XCTAssertEqual(event.feed(travel: 9, function: .volume, at: 0.3), 2, "one event's own travel: two, as before")
        var small = ThumbWheelStepper()
        XCTAssertEqual(small.feed(travel: 4, function: .volume, at: 0.3, heldSince: 0), 1)
        XCTAssertEqual(small.carried, 2, accuracy: 1e-12, "a batch of one step loses nothing")
        XCTAssertEqual(ThumbWheelTuning.maxStepsPerConfirmedBatch, 1)
    }

    // MARK: Speed

    func testSpeed_quarterOneAndThree() {
        var quarter = ThumbWheelStepper()
        XCTAssertEqual(stepAt(run(&quarter, Array(repeating: -1, count: 12), .tabs, speed: 0.25)), [12])
        var one = ThumbWheelStepper()
        XCTAssertEqual(stepAt(run(&one, Array(repeating: -1, count: 12), .tabs, speed: 1)), [3, 8])
        var three = ThumbWheelStepper()
        XCTAssertEqual(stepAt(run(&three, Array(repeating: -1, count: 6), .tabs, speed: 3)), [1, 3, 5, 6],
                       "3, then 6 − 5, 1 + 3 + 3 − 5, ...")
    }

    // MARK: Function change

    func testAnotherFunction_startsAfresh() {
        var stepper = ThumbWheelStepper()
        XCTAssertEqual(run(&stepper, [-1, -1], .tabs), [0, 0])
        XCTAssertEqual(stepper.feed(travel: 1, function: .desktops, at: 0.1), 0, "the two tabs' units do not count")
        XCTAssertEqual(stepper.function, .desktops)
        XCTAssertEqual(stepper.carried, 1)
        XCTAssertEqual(stepper.feed(travel: 3, function: .scroll, at: 0.15), 0, "scrolling makes no steps")
    }

    func testReset_forgetsEverything() {
        var stepper = ThumbWheelStepper()
        _ = run(&stepper, [-1, -1, -1, -1], .tabs)
        stepper.reset()
        XCTAssertEqual(stepper, ThumbWheelStepper())
    }

    // MARK: What the numbers were chosen to give (rolls as in the owner's log)

    func testVolume_slowRoll_flick_longRolling() {
        var slow = ThumbWheelStepper()
        let slowRoll = run(&slow, [-0.1, -0.3, -0.5, -1, -0.8, -0.2, -0.6, -1, -0.4], .volume,
                           gaps: [0.1, 0.2, 0.35, 0.3, 0.15, 0.25, 0.3, 0.2])
        XCTAssertEqual(total(slowRoll), 3, "a slow roll of 9 events")

        var flick = ThumbWheelStepper()
        XCTAssertEqual(total(run(&flick, [-8, -9, -10, -11, -12, -12, -11, -10, -9, -8], .volume, gaps: [0.015])), 6,
                       "a flick of 10 events, not the whole range (16)")

        var long = ThumbWheelStepper()
        let pattern: [Double] = [-0.5, -2, -5, -9, -3]
        let rolling = run(&long, (0..<7).flatMap { _ in pattern }, .volume, gaps: [0.05])
        XCTAssertTrue((11...16).contains(total(rolling)), "35 events of long rolling: \(total(rolling))")
        XCTAssertTrue(rolling.allSatisfy { abs($0) <= 1 }, "no jumps: one step per event at speed 1")
    }

    func testTabs_slowRoll_flick() {
        var five = ThumbWheelStepper()
        XCTAssertEqual(total(run(&five, Array(repeating: -0.5, count: 5), .tabs, gaps: [0.2])), 1)
        var nine = ThumbWheelStepper()
        XCTAssertEqual(total(run(&nine, Array(repeating: -0.5, count: 9), .tabs, gaps: [0.15])), 2)
        var flick = ThumbWheelStepper()
        XCTAssertEqual(total(run(&flick, Array(repeating: -12, count: 10), .tabs, gaps: [0.015])), 2)
    }

    /// One long roll moves several desktops: the first after 3 events, each further one after
    /// 5 more (the second no longer needs four times the first).
    func testDesktops_firstAfterThreeEventsEachFurtherAfterFive() {
        for (count, desktops) in [(3, 1), (7, 1), (8, 2), (12, 2), (13, 3)] {
            var stroke = ThumbWheelStepper()
            XCTAssertEqual(total(run(&stroke, Array(repeating: -10, count: count), .desktops, gaps: [0.02])), desktops, "\(count) events")
        }
        var back = ThumbWheelStepper()
        XCTAssertEqual(total(run(&back, Array(repeating: -10, count: 14), .backForward, gaps: [0.02])), 1, "back / forward as before")
        var two = ThumbWheelStepper()
        XCTAssertEqual(total(run(&two, Array(repeating: -0.5, count: 2), .desktops)), 0, "less than a stroke")
    }
}

/// The stray-tick filter: small ticks at a start or against the roll wait until they make half
/// a line or a third comes, and do nothing alone (the owner's log, 2026-11-14/15: ticks of
/// about 0.1 line where the thumb takes the wheel again, pairs where it lets go).
final class ThumbWheelTickFilterTests: XCTestCase {

    private typealias Result = ThumbWheelTickFilter.Result

    func testNumbers() {
        XCTAssertEqual(ThumbWheelTuning.tickSmallLines, 0.5)
        XCTAssertEqual(ThumbWheelTuning.tickWindow, 0.45)
        XCTAssertEqual(ThumbWheelTuning.tickConfirmingEvents, 3)
    }

    /// A small first event is held; the next ones the same way within the window apply with
    /// it once they make half a line in all, or at the third.
    func testStart_smallEventsWaitForHalfALineOrAThird() {
        var filter = ThumbWheelTickFilter()
        XCTAssertEqual(filter.filter(travel: -1, lines: -0.1, at: 10), Result(travel: 0, held: true, dropped: 0))
        XCTAssertTrue(filter.holds)
        XCTAssertEqual(filter.filter(travel: -0.7, lines: -0.2, at: 10.3), Result(travel: 0, held: true, dropped: 0),
                       "0.3 line in two events: still held")
        XCTAssertEqual(filter.filter(travel: -1, lines: -0.1, at: 10.4), Result(travel: -2.7, held: false, dropped: 0, heldSince: 10),
                       "the third applies all, and says since when they were held")
        XCTAssertFalse(filter.holds)
        XCTAssertEqual(filter.filter(travel: -1, lines: -0.1, at: 10.45), Result(travel: -1, held: false, dropped: 0),
                       "inside the roll a small event the same way applies at once")

        var half = ThumbWheelTickFilter()
        _ = half.filter(travel: -1, lines: -0.1, at: 0)
        XCTAssertEqual(half.filter(travel: -1, lines: -0.4, at: 0.1), Result(travel: -2, held: false, dropped: 0, heldSince: 0),
                       "half a line in two events applies both")
    }

    /// Where the thumb lets go: a pair of small ticks 0.7 s after a roll (0.20 to 0.23 line in
    /// all) applies nothing, and is dropped once the window passed.
    func testALetGoPairDoesNothing() {
        var filter = ThumbWheelTickFilter()
        _ = filter.filter(travel: -1, lines: -2.5, at: 0)
        XCTAssertEqual(filter.filter(travel: 1, lines: 0.1, at: 0.7), Result(travel: 0, held: true, dropped: 0))
        XCTAssertEqual(filter.filter(travel: 1, lines: 0.13, at: 0.82), Result(travel: 0, held: true, dropped: 0))
        XCTAssertEqual(filter.heldEvents, 2)
        XCTAssertEqual(filter.filter(travel: -1, lines: -2.5, at: 2), Result(travel: -1, held: false, dropped: 2),
                       "both dropped, never applied")
    }

    /// An event of half a line or more applies at once, at a start or against the roll.
    func testALargeEventAppliesAtOnce() {
        var filter = ThumbWheelTickFilter()
        XCTAssertEqual(filter.filter(travel: -1, lines: -0.5, at: 0), Result(travel: -1, held: false, dropped: 0))
        XCTAssertEqual(filter.filter(travel: 1, lines: 2, at: 0.05), Result(travel: 1, held: false, dropped: 0), "a deliberate turn back")
    }

    /// A small event against what was applied within the window is held; the events that
    /// way apply once they make half a line or at the third. An event the roll's way drops
    /// them (never subtracted).
    func testReversal_confirmedByHalfALineOrAThird_droppedByTheRollsWay() {
        var filter = ThumbWheelTickFilter()
        _ = filter.filter(travel: -1, lines: -1, at: 0)
        XCTAssertEqual(filter.filter(travel: 1, lines: 0.1, at: 0.1), Result(travel: 0, held: true, dropped: 0))
        XCTAssertEqual(filter.filter(travel: 1, lines: 0.1, at: 0.2), Result(travel: 0, held: true, dropped: 0))
        XCTAssertEqual(filter.filter(travel: 1, lines: 0.1, at: 0.3), Result(travel: 3, held: false, dropped: 0, heldSince: 0.1))

        var turned = ThumbWheelTickFilter()
        _ = turned.filter(travel: -1, lines: -1, at: 0)
        _ = turned.filter(travel: 1, lines: 0.1, at: 0.1)
        XCTAssertEqual(turned.filter(travel: 1, lines: 2, at: 0.15), Result(travel: 2, held: false, dropped: 0, heldSince: 0.1))

        var stray = ThumbWheelTickFilter()
        _ = stray.filter(travel: -1, lines: -1, at: 0)
        XCTAssertEqual(stray.filter(travel: 1, lines: 0.1, at: 0.1), Result(travel: 0, held: true, dropped: 0))
        XCTAssertEqual(stray.filter(travel: -1, lines: -0.1, at: 0.2), Result(travel: -1, held: false, dropped: 1),
                       "the roll goes on: the tick is dropped, not subtracted")
    }

    /// Held events are dropped once the first is older than the window; the new one is
    /// judged on its own.
    func testAHeldEventExpiresAfterTheWindow() {
        var filter = ThumbWheelTickFilter()
        XCTAssertEqual(filter.filter(travel: -1, lines: -0.1, at: 0), Result(travel: 0, held: true, dropped: 0))
        XCTAssertEqual(filter.filter(travel: -1, lines: -0.1, at: 0.46), Result(travel: 0, held: true, dropped: 1))
        XCTAssertEqual(filter.filter(travel: -1, lines: -0.1, at: 0.6), Result(travel: 0, held: true, dropped: 0))
        XCTAssertEqual(filter.filter(travel: -1, lines: -0.1, at: 0.9), Result(travel: -3, held: false, dropped: 0, heldSince: 0.46),
                       "the third within 0.45 s of the first held")
        XCTAssertEqual(filter.filter(travel: 1, lines: 0.1, at: 1), Result(travel: 0, held: true, dropped: 0))
        XCTAssertEqual(filter.filter(travel: 1, lines: 0.1, at: 1.2), Result(travel: 0, held: true, dropped: 0))
        XCTAssertEqual(filter.filter(travel: 1, lines: 0.1, at: 1.46), Result(travel: 0, held: true, dropped: 2),
                       "two held, both older than the window")
        var late = ThumbWheelTickFilter()
        _ = late.filter(travel: -1, lines: -0.1, at: 0)
        XCTAssertEqual(late.filter(travel: -1, lines: -3, at: 0.5), Result(travel: -1, held: false, dropped: 1),
                       "a large one applies alone")
    }

    /// A held event of the other sign is dropped when a small one comes, which is held in turn.
    func testAHeldEventOfTheOtherSignIsDropped() {
        var filter = ThumbWheelTickFilter()
        _ = filter.filter(travel: -1, lines: -0.1, at: 0)
        XCTAssertEqual(filter.filter(travel: 1, lines: 0.1, at: 0.1), Result(travel: 0, held: true, dropped: 1))
        XCTAssertEqual(filter.heldTravel, 1)
    }

    func testDropHeldAndReset() {
        var filter = ThumbWheelTickFilter()
        XCTAssertEqual(filter.dropHeld(), 0)
        _ = filter.filter(travel: -1, lines: -1, at: 0)
        _ = filter.filter(travel: 1, lines: 0.1, at: 0.1)
        XCTAssertEqual(filter.dropHeld(), 1)
        XCTAssertFalse(filter.holds)
        _ = filter.filter(travel: 1, lines: 0.1, at: 0.15)
        XCTAssertEqual(filter.reset(), 1)
        XCTAssertEqual(filter, ThumbWheelTickFilter())
        XCTAssertEqual(filter.filter(travel: 0, lines: 0, at: 1), .nothing, "no travel: nothing to hold")
    }
}

/// The pacer between the stepper and volume's actions: the system does not keep up with
/// volume keys faster than about 20 a second (the owner's second log, 2026-11-11).
final class ThumbWheelPacerTests: XCTestCase {

    private let volume = ThumbWheelTuning.volumePacing

    private func added(_ runNow: Int, _ dropped: Int) -> ThumbWheelPacer.Added {
        return ThumbWheelPacer.Added(runNow: runNow, dropped: dropped)
    }

    func testNumbers_volumeAndDesktopsArePaced() {
        XCTAssertEqual(volume, ThumbWheelPacing(interval: 0.05, maxWaiting: 3))
        XCTAssertEqual(ThumbWheelFunction.volume.pacing, volume)
        XCTAssertEqual(ThumbWheelTuning.desktopsPacing, ThumbWheelPacing(interval: 0.25, maxWaiting: 1))
        XCTAssertEqual(ThumbWheelFunction.desktops.pacing, ThumbWheelTuning.desktopsPacing)
        for function in [ThumbWheelFunction.scroll, .zoom, .tabs, .backForward] {
            XCTAssertNil(function.pacing, "\(function)")
        }
    }

    func testTheFirstStepRunsAtOnce_andOneAfterTheIntervalToo() {
        var pacer = ThumbWheelPacer()
        XCTAssertEqual(pacer.add(1, pacing: volume, at: 10), added(1, 0))
        XCTAssertNil(pacer.nextRunAt(pacing: volume), "nothing waits: nothing to schedule")
        XCTAssertEqual(pacer.add(1, pacing: volume, at: 10.05), added(1, 0))
        XCTAssertEqual(pacer.add(-1, pacing: volume, at: 10.2), added(-1, 0))
    }

    func testFurtherStepsAreSpacedByTheInterval() {
        var pacer = ThumbWheelPacer()
        XCTAssertEqual(pacer.add(2, pacing: volume, at: 10), added(1, 0))
        XCTAssertEqual(pacer.waiting, 1)
        XCTAssertEqual(pacer.nextRunAt(pacing: volume) ?? 0, 10.05, accuracy: 1e-12)
        XCTAssertEqual(pacer.take(pacing: volume, at: 10.04), 0, "not before the interval")
        XCTAssertEqual(pacer.add(1, pacing: volume, at: 10.045), added(0, 0))
        XCTAssertEqual(pacer.waiting, 2)
        XCTAssertEqual(pacer.take(pacing: volume, at: 10.05), 1)
        XCTAssertEqual(pacer.take(pacing: volume, at: 10.06), 0)
        XCTAssertEqual(pacer.take(pacing: volume, at: 10.1), 1)
        XCTAssertNil(pacer.nextRunAt(pacing: volume), "none waits any more")
        XCTAssertEqual(pacer.take(pacing: volume, at: 11), 0)
    }

    func testAtMostMaxWaiting_moreAreDropped() {
        var pacer = ThumbWheelPacer()
        XCTAssertEqual(pacer.add(2, pacing: volume, at: 0), added(1, 0))
        XCTAssertEqual(pacer.add(2, pacing: volume, at: 0.01), added(0, 0))
        XCTAssertEqual(pacer.waiting, 3)
        XCTAssertEqual(pacer.add(2, pacing: volume, at: 0.02), added(0, 2))
        XCTAssertEqual(pacer.waiting, 3)
        XCTAssertEqual(pacer.add(-5, pacing: ThumbWheelPacing(interval: 0.05, maxWaiting: 1), at: 0.03), added(0, 7),
                       "the 3 of the other direction, and 4 of the 5 new ones")
    }

    /// Turning back drops what waits in the old direction: the new direction is next in line.
    func testTurningBack_dropsTheWaitingSteps_andTheNewOnesAnswer() {
        var pacer = ThumbWheelPacer()
        _ = pacer.add(2, pacing: volume, at: 0)
        _ = pacer.add(2, pacing: volume, at: 0.01)
        XCTAssertEqual(pacer.add(-1, pacing: volume, at: 0.02), added(0, 3))
        XCTAssertEqual(pacer.waiting, -1)
        XCTAssertEqual(pacer.take(pacing: volume, at: 0.05), -1, "the first step that may run is the new direction's")

        XCTAssertEqual(pacer.add(3, pacing: volume, at: 1), added(1, 0))
        XCTAssertEqual(pacer.add(-1, pacing: volume, at: 1.06), added(-1, 2), "after the interval it runs at once")
        XCTAssertEqual(pacer.waiting, 0)
    }

    func testDropWaiting() {
        var pacer = ThumbWheelPacer()
        _ = pacer.add(-3, pacing: volume, at: 0)
        XCTAssertEqual(pacer.dropWaiting(), 2)
        XCTAssertEqual(pacer.waiting, 0)
        XCTAssertNil(pacer.nextRunAt(pacing: volume))
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
        /// When each action ran (seconds after the rig's start).
        private(set) var performedAt: [Double] = []
        private(set) var lines: [ScrollSystemLog.ThumbWheelRoll] = []
        /// The trace lines, as written.
        private(set) var traces: [String] = []

        init() {
            engine.secondsPerTimestampUnit = 1e-9
            engine.clock = { [unowned self] in self.now }
            engine.schedule = { [unowned self] delay, work in
                self.scheduledCount += 1
                self.queue.append((self.now + max(0, delay), self.scheduledCount, work))
            }
            engine.perform = { [unowned self] action, times in
                self.performed.append(Performed(action: action, times: times))
                self.performedAt.append(self.now - 500)
            }
            engine.writeLog = { [unowned self] roll in self.lines.append(roll) }
            engine.writeTrace = { [unowned self] line in self.traces.append(line) }
        }

        var hasPendingWork: Bool { return !queue.isEmpty }

        /// Runs the work due up to `time`, in order. Work that keeps scheduling itself without
        /// time moving on (a busy loop on the main queue) fails the test instead of hanging it.
        func advance(to time: Double, file: StaticString = #filePath, line: UInt = #line) {
            var runsAtThisMoment = 0
            while let next = queue.enumerated()
                .filter({ $0.element.due <= time + 1e-9 })
                .min(by: { ($0.element.due, $0.element.order) < ($1.element.due, $1.element.order) }) {
                queue.remove(at: next.offset)
                runsAtThisMoment = next.element.due > now ? 0 : runsAtThisMoment + 1
                guard runsAtThisMoment < 1_000 else {
                    XCTFail("a busy loop on the main queue at \(now - 500) s", file: file, line: line)
                    queue.removeAll()
                    break
                }
                now = max(now, next.element.due)
                next.element.work()
            }
            now = max(now, time)
        }

        /// The raw timestamp (ns) of a moment `time` seconds after the rig's start.
        static func timestamp(_ time: Double) -> UInt64 {
            return UInt64(((500 + time) * 1e9).rounded())
        }

        /// One sideways event that happened at `time` (seconds after the rig's start, its own
        /// timestamp) and reaches the callback at `processedAt` (the same, unless the main
        /// thread was busy: then the work due in between has not run either).
        @discardableResult
        func turn(lines: Double, at time: Double, settings: ThumbWheelSettings, flipped: Bool = false,
                  continuous: Bool = false, fixed: Double? = nil, processedAt: Double? = nil,
                  timestampOffset: Double = 0) -> Int {
            advance(to: 500 + (processedAt ?? time))
            let event = ThumbWheelEvent(
                lineDelta: Int64(lines), fixedDelta: fixed ?? lines, pointDelta: (lines * 10).rounded(),
                isContinuous: continuous, timestamp: Rig.timestamp(time + timestampOffset)
            )
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

    /// Tabs: ⌃⇥ and ⌃⇧⇥ (Tab, key code 48, on every layout); keys of their own. The action
    /// menu's "Next Tab" and "Previous Tab" send the same keys now (they were ⇧⌘→ / ⇧⌘←,
    /// which select text and are no tab shortcut in Chrome or Finder).
    func testTabs_areControlTabAndControlShiftTab() {
        XCTAssertEqual(ThumbWheelAction.nextTab.code, 48)
        XCTAssertEqual(ThumbWheelAction.nextTab.modifiers, .control)
        XCTAssertEqual(ThumbWheelAction.previousTab.code, 48)
        XCTAssertEqual(ThumbWheelAction.previousTab.modifiers, [.control, .shift])
        XCTAssertNil(SystemShortcut.getShortcut(named: ThumbWheelAction.nextTab.identifier), "not an action of the menu")
        XCTAssertNil(SystemShortcut.getShortcut(named: ThumbWheelAction.previousTab.identifier))
        XCTAssertEqual(SystemShortcut.switchTabRight.code, 124, "the menu's own actions are unchanged")
        XCTAssertEqual(SystemShortcut.switchTabRight.modifiers, [.command, .option])
        XCTAssertEqual(SystemShortcut.nextTab.code, ThumbWheelAction.nextTab.code)
        XCTAssertEqual(SystemShortcut.nextTab.modifiers, ThumbWheelAction.nextTab.modifiers)
        XCTAssertEqual(SystemShortcut.previousTab.code, ThumbWheelAction.previousTab.code)
        XCTAssertEqual(SystemShortcut.previousTab.modifiers, ThumbWheelAction.previousTab.modifiers)
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
            XCTAssertEqual(event.getIntegerValueField(.eventSourceUserData), ScrollioEventMarker.syntheticCustom, "marked as Scrollio's own")
        }
        XCTAssertEqual(SystemVolumeKey.up.keyType, 0, "NX_KEYTYPE_SOUND_UP")
        XCTAssertEqual(SystemVolumeKey.down.keyType, 1, "NX_KEYTYPE_SOUND_DOWN")
    }

    // MARK: When steps run

    func testSteps_runOnTheMainQueueAfterTheCallback() {
        let rig = Rig()
        let tabs = ThumbWheelSettings(function: .tabs)
        XCTAssertEqual(rig.turn(lines: -1, at: 0, settings: tabs), 0)
        XCTAssertEqual(rig.turn(lines: -1, at: 0.02, settings: tabs), 0)
        XCTAssertEqual(rig.turn(lines: -1, at: 0.04, settings: tabs), 1)
        XCTAssertEqual(rig.performed, [], "not inside the callback")
        rig.advance(to: 500.04)
        XCTAssertEqual(rig.performed, [Performed(action: .keys(ThumbWheelAction.nextTab), times: 1)])

        // Swapped the same turn is the previous tab.
        XCTAssertEqual(rig.turn(lines: -2, at: 1, settings: tabs, flipped: true), 0)
        XCTAssertEqual(rig.turn(lines: -2, at: 1.02, settings: tabs, flipped: true), 0)
        XCTAssertEqual(rig.turn(lines: -2, at: 1.04, settings: tabs, flipped: true), -1)
        rig.advance(to: 501.04)
        XCTAssertEqual(rig.performed.last, Performed(action: .keys(ThumbWheelAction.previousTab), times: 1))
    }

    /// A function without pacing (zoom, tabs, back / forward) runs its steps at once,
    /// in the main-queue turn right after the callback, as before the pacer: two steps of one
    /// event in one go.
    func testAFunctionWithoutPacing_runsItsStepsAtOnce() {
        let rig = Rig()
        let zoom = ThumbWheelSettings(function: .zoom, speed: 3)
        XCTAssertEqual(rig.turn(lines: -12, at: 0, settings: zoom), 1, "6 units: the first 3")
        XCTAssertEqual(rig.turn(lines: -12, at: 0.01, settings: zoom), 1, "3 + 6: the next 5")
        XCTAssertEqual(rig.turn(lines: -12, at: 0.02, settings: zoom), 2, "4 + 6: two of 5")
        rig.advance(to: 500.02)
        XCTAssertEqual(rig.performed, [
            Performed(action: .zoomIn, times: 1), Performed(action: .zoomIn, times: 1), Performed(action: .zoomIn, times: 2),
        ])
        XCTAssertEqual(rig.performedAt.map { ($0 * 1000).rounded() }, [0, 10, 20], "each right after its event")
        XCTAssertNil(rig.engine.pacer.nextRunAt(pacing: ThumbWheelTuning.volumePacing))

        for function in [ThumbWheelFunction.tabs, .backForward] {
            let other = Rig()
            let settings = ThumbWheelSettings(function: function, speed: 3)
            XCTAssertEqual(other.turn(lines: -1, at: 0, settings: settings), 1, "\(function)")
            other.advance(to: 500)
            XCTAssertEqual(other.performed.map(\.times), [1], "\(function)")
            XCTAssertEqual(other.performedAt, [0], "\(function): at once")
        }
    }

    /// His x3.00 flick (11 events in 189 ms, 2 volume steps each): at most one step per 50 ms,
    /// the last within 150 ms of the last event, the rest dropped and counted in the line.
    func testVolume_theOwnersFlickAtSpeed3_isPaced() throws {
        let rig = Rig()
        let settings = ThumbWheelSettings(function: .volume, speed: 3)
        var decided = 0
        for index in 0..<11 {
            decided += rig.turn(lines: -12, at: Double(index) * 0.0189, settings: settings)
        }
        XCTAssertEqual(decided, 22)
        rig.advance(to: 510)

        XCTAssertTrue(rig.performed.allSatisfy { $0 == Performed(action: .volume(.up), times: 1) }, "one action per step")
        let times = rig.performedAt
        for (earlier, later) in zip(times, times.dropFirst()) {
            XCTAssertGreaterThanOrEqual(later - earlier, 0.05 - 1e-9, "at most one step per 50 ms: \(times)")
        }
        let lastEvent = 10 * 0.0189
        XCTAssertLessThanOrEqual(try XCTUnwrap(times.last) - lastEvent, 0.15 + 1e-9, "finished soon after the hand stopped")
        XCTAssertEqual(times.map { ($0 * 1000).rounded() }, [0, 50, 100, 150, 200, 250, 300])

        let roll = try XCTUnwrap(rig.lines.first)
        XCTAssertEqual(roll.stepsNext, 7)
        XCTAssertEqual(roll.droppedSteps, 15)
        XCTAssertTrue(ScrollSystemLog.thumbWheelMessage(for: roll).hasSuffix("volume x3.00, travel 66.0: 7 steps next, 6 waited, 15 dropped; ticks held 0, dropped 0"),
                      ScrollSystemLog.thumbWheelMessage(for: roll))
        XCTAssertFalse(rig.hasPendingWork, "nothing scheduled once none wait")
    }

    /// A long roll at x3.00: its line falls due (after 2 s) while volume steps wait. The look
    /// comes again when the next one has run, it does not spin on the main queue meanwhile; the
    /// line is written once the roll's steps have run, after the hand stopped.
    func testVolume_aLongPacedRoll_noBusyLoopWhileStepsWait() throws {
        let rig = Rig()
        let settings = ThumbWheelSettings(function: .volume, speed: 3)
        var decided = 0
        for index in 0..<110 {
            decided += rig.turn(lines: -12, at: Double(index) * 0.02, settings: settings)
        }
        rig.advance(to: 510)
        XCTAssertEqual(rig.lines.count, 1, "steps waited all along: one line, once they ran")
        XCTAssertEqual(rig.lines.reduce(0) { $0 + $1.stepsNext + $1.droppedSteps }, decided, "every step ran or was dropped")
        XCTAssertEqual(rig.lines.reduce(0) { $0 + $1.stepsNext }, rig.performed.count)
        XCTAssertFalse(rig.hasPendingWork)
    }

    /// At x1.00 a roll's steps come no faster than the pacing: every one runs, at its event.
    func testVolume_atSpeed1_everyStepRunsAtItsEvent() throws {
        let rig = Rig()
        var decidedAt: [Double] = []
        for index in 0..<22 {
            let time = Double(index) * 0.0856
            if rig.turn(lines: -5, at: time, settings: ThumbWheelSettings(function: .volume)) != 0 {
                decidedAt.append(time)
            }
        }
        rig.advance(to: 510)
        let roll = try XCTUnwrap(rig.lines.first)
        XCTAssertEqual(roll.stepsNext, 10, "about 30 units: as his 22 events in 1797 ms")
        XCTAssertEqual(roll.droppedSteps, 0)
        XCTAssertEqual(rig.performedAt.map { ($0 * 1000).rounded() }, decidedAt.map { ($0 * 1000).rounded() })
    }

    // MARK: Switch Desktops in steps

    /// Lines of a slow roll as the owner's log has them: 0.1 to 1 line an event.
    private static let slowLines: [Double] = [-0.1, -0.35, -0.6, -1, -0.8, -0.2, -0.45, -0.9, -0.15, -0.7, -1, -0.3]

    /// At 0.7× a one-way roll at 94 ms an event steps at events 5, 12 and 19 (3, then 5 more
    /// each); 17 events are two desktops, not one.
    func testDesktops_atPoint7_aOneWayRollStepsAtEvents5_12_19() throws {
        for (count, expected) in [(22, [5, 12, 19]), (17, [5, 12])] {
            let rig = Rig()
            let settings = ThumbWheelSettings(function: .desktops, speed: 0.7)
            var steppedAt: [Int] = []
            for index in 0..<count {
                let lines = Self.slowLines[index % Self.slowLines.count]
                if rig.turn(lines: lines, at: Double(index) * 0.094, settings: settings) != 0 { steppedAt.append(index + 1) }
            }
            rig.advance(to: 510)
            XCTAssertEqual(steppedAt, expected, "\(count) events")
            XCTAssertEqual(rig.performed.count, expected.count, "\(count) events: every one ran, none dropped")
            XCTAssertEqual(rig.lines.first?.droppedSteps, 0)
        }
    }

    /// Desktops are paced: at most one each 250 ms, one waiting at most. A flick of 12 events
    /// (8.6 lines each, 20 ms apart) at 0.7× is two desktops, the second 250 ms after the
    /// first; a fast roll of 40 events never has more than one waiting, nothing runs later
    /// than 250 ms after the last event, and what is dropped is counted.
    func testDesktops_pacedOneEach250Milliseconds_oneWaitingAtMost() throws {
        let settings = ThumbWheelSettings(function: .desktops, speed: 0.7)
        let flick = Rig()
        for index in 0..<12 { flick.turn(lines: -8.6, at: Double(index) * 0.02, settings: settings) }
        flick.advance(to: 510)
        XCTAssertEqual(flick.performed, Array(repeating: Performed(action: .named("moveSpaceRight"), times: 1), count: 2))
        XCTAssertGreaterThanOrEqual(flick.performedAt[1] - flick.performedAt[0], 0.25 - 1e-9, "\(flick.performedAt)")

        let roll = Rig()
        var decided = 0
        for index in 0..<40 {
            decided += roll.turn(lines: -8.6, at: Double(index) * 0.02, settings: settings)
            XCTAssertLessThanOrEqual(abs(roll.engine.pacer.waiting), 1, "event \(index + 1)")
        }
        roll.advance(to: 510)
        let lastEvent = 39 * 0.02
        XCTAssertLessThanOrEqual(try XCTUnwrap(roll.performedAt.last) - lastEvent, 0.25 + 1e-9, "\(roll.performedAt)")
        for (earlier, later) in zip(roll.performedAt, roll.performedAt.dropFirst()) {
            XCTAssertGreaterThanOrEqual(later - earlier, 0.25 - 1e-9, "\(roll.performedAt)")
        }
        let line = try XCTUnwrap(roll.lines.first)
        XCTAssertEqual(roll.lines.count, 1)
        XCTAssertEqual(line.stepsNext, roll.performed.count)
        XCTAssertGreaterThan(line.droppedSteps, 0)
        XCTAssertEqual(line.stepsNext + line.droppedSteps, decided, "every step ran or was counted as dropped")
        XCTAssertGreaterThan(line.stepsWaited, 0)
        let message = ScrollSystemLog.thumbWheelMessage(for: line)
        XCTAssertTrue(message.hasSuffix("steps next, \(line.stepsWaited) waited, \(line.droppedSteps) dropped; ticks held 0, dropped 0"), message)
        XCTAssertFalse(roll.hasPendingWork)
    }

    // MARK: Stray ticks

    /// 1×, 9 events toward the next desktop and 8 back, all of 0.1 line: two desktops each
    /// way. The first two events of each way are held and applied with the third.
    func testDesktops_smallTicksBothWays_twoEachWay_theFirstOfEachWayHeld() throws {
        let rig = Rig()
        let settings = ThumbWheelSettings(function: .desktops)
        var forward = 0
        for index in 0..<9 {
            forward += rig.turn(lines: -0.1, at: Double(index) * 0.094, settings: settings)
            if index == 0 { XCTAssertTrue(rig.engine.tickFilter.holds, "the first is held") }
        }
        var back = 0
        for index in 9..<17 {
            back += rig.turn(lines: 0.1, at: Double(index) * 0.094, settings: settings)
            if index == 9 { XCTAssertTrue(rig.engine.tickFilter.holds, "the first back is held") }
            if index == 10 { XCTAssertTrue(rig.engine.tickFilter.holds, "the second back is held too") }
            if index == 11 { XCTAssertFalse(rig.engine.tickFilter.holds, "applied with the third") }
        }
        XCTAssertEqual(forward, 2)
        XCTAssertEqual(back, -2)
        rig.advance(to: 510)
        XCTAssertEqual(rig.performed.map(\.action), [
            .named("moveSpaceRight"), .named("moveSpaceRight"), .named("moveSpaceLeft"), .named("moveSpaceLeft"),
        ])
        let line = try XCTUnwrap(rig.lines.first)
        XCTAssertEqual(line.ticksHeld, 4)
        XCTAssertEqual(line.ticksDropped, 0)
    }

    /// 0.7×, a re-grip: 9 events, a pause of 280, 320 or 470 ms with one tick of 0.10 line
    /// the other way in it, 9 more: two desktops every time, the tick dropped.
    func testDesktops_aRegripWithAStrayTick_twoDesktopsWhateverThePause() throws {
        for pause in [0.28, 0.32, 0.47] {
            let rig = Rig()
            let settings = ThumbWheelSettings(function: .desktops, speed: 0.7)
            var steps = 0
            var time = 0.0
            for _ in 0..<9 { steps += rig.turn(lines: -1, at: time, settings: settings); time += 0.094 }
            time -= 0.094
            steps += rig.turn(lines: 0.1, at: time + pause / 2, settings: settings)
            time += pause
            for _ in 0..<9 { steps += rig.turn(lines: -1, at: time, settings: settings); time += 0.094 }
            rig.advance(to: 510)
            XCTAssertEqual(steps, 2, "pause \(pause)")
            XCTAssertEqual(rig.performed.map(\.action), [.named("moveSpaceRight"), .named("moveSpaceRight")], "pause \(pause)")
            XCTAssertEqual(rig.lines.map(\.ticksDropped), [1], "pause \(pause)")
            XCTAssertEqual(rig.lines.map(\.ticksHeld), [1], "pause \(pause)")
        }
    }

    /// 0.7×, events of half a line 94 ms apart in strokes of 4+4+9 and 6+6+5, the thumb taking
    /// the wheel again after 280, 320 or 470 ms (the owner's re-grips take 250 to 580 ms):
    /// as many desktops whatever the gap.
    func testDesktops_aRegripGapDoesNotChangeHowManyDesktopsARollGives() throws {
        for strokes in [[4, 4, 9], [6, 6, 5]] {
            var counts: [Int] = []
            for gap in [0.28, 0.32, 0.47] {
                let rig = Rig()
                let settings = ThumbWheelSettings(function: .desktops, speed: 0.7)
                var time = 0.0
                var steps = 0
                for (index, count) in strokes.enumerated() {
                    if index > 0 { time += gap - 0.094 }
                    for _ in 0..<count {
                        steps += rig.turn(lines: -0.5, at: time, settings: settings)
                        time += 0.094
                    }
                }
                rig.advance(to: 510)
                XCTAssertEqual(rig.performed.count, steps, "\(strokes), gap \(gap): every desktop ran")
                counts.append(steps)
            }
            XCTAssertEqual(counts, [2, 2, 2], "\(strokes)")
        }
    }

    /// 0.7×, a re-grip that begins with a tick of 0.10 line, as the owner's do: 9 events, a
    /// pause, then −0.1, −1, −1, −1. Two desktops after 280 to 580 ms: the pause is measured
    /// to the tick, where the thumb took the wheel again, not to the event that confirms it
    /// 94 ms later (0.52 s then counted as a rest of 0.6 s and dropped what the first
    /// stroke had carried). After 0.62 s it is a rest: the second stroke alone is no desktop.
    func testDesktops_aRegripThatBeginsWithAHeldTick_isARestOnlyFrom600Milliseconds() throws {
        for (pause, desktops) in [(0.28, 2), (0.47, 2), (0.52, 2), (0.58, 2), (0.62, 1)] {
            let rig = Rig()
            let settings = ThumbWheelSettings(function: .desktops, speed: 0.7)
            var steps = 0
            var time = 0.0
            for _ in 0..<9 { steps += rig.turn(lines: -1, at: time, settings: settings); time += 0.094 }
            time += pause - 0.094
            for lines in [-0.1, -1, -1, -1] { steps += rig.turn(lines: lines, at: time, settings: settings); time += 0.094 }
            rig.advance(to: 510)
            XCTAssertEqual(steps, desktops, "pause \(pause)")
            XCTAssertEqual(rig.performed.count, desktops, "pause \(pause): every desktop ran")
        }
    }

    /// Desktops at 3×: three ticks of 0.10 line 150 ms apart are one desktop, with nothing
    /// waiting (they were two, the second 250 ms after the thumb had stopped: the batch the
    /// filter confirms is 9 units, the first step and a next one). At 1× and 2× one, as before.
    func testDesktops_threeSmallTicks_areOneDesktopAtAnySpeed() throws {
        for speed in [1.0, 2.0, 3.0] {
            let rig = Rig()
            let settings = ThumbWheelSettings(function: .desktops, speed: speed)
            var steps = 0
            for time in [0, 0.15, 0.30] { steps += rig.turn(lines: -0.1, at: time, settings: settings) }
            XCTAssertEqual(steps, 1, "x\(speed)")
            XCTAssertEqual(rig.engine.pacer.waiting, 0, "x\(speed): nothing waiting")
            rig.advance(to: 510)
            XCTAssertEqual(rig.performed, [Performed(action: .named("moveSpaceRight"), times: 1)], "x\(speed)")
            XCTAssertEqual(rig.performedAt.map { ($0 * 1000).rounded() }, [300], "x\(speed): with the third tick")
            XCTAssertEqual(rig.lines.first?.droppedSteps, 0, "x\(speed)")
        }
    }

    /// What does not change with it, at 1×, 2× and 3×: a flick (12 events of 8.6 lines 20 ms
    /// apart) and a stroke that begins with a tick of 0.10 line (then 8 events of a line,
    /// 94 ms apart) step at the same events as before: the tick and the event that
    /// confirms it never made more than one step.
    func testDesktops_flicksAndStrokesStepAsBefore_withOneStepPerConfirmedBatch() throws {
        func steppedAt(_ lines: [Double], gap: Double, speed: Double) -> [Int] {
            let rig = Rig()
            let settings = ThumbWheelSettings(function: .desktops, speed: speed)
            var events: [Int] = []
            for (index, lines) in lines.enumerated() {
                let steps = rig.turn(lines: lines, at: Double(index) * gap, settings: settings)
                events += Array(repeating: index + 1, count: abs(steps))
            }
            return events
        }
        let flick = Array(repeating: -8.6, count: 12)
        let stroke = [-0.1] + Array(repeating: -1.0, count: 8)
        XCTAssertEqual(steppedAt(flick, gap: 0.02, speed: 1), [3, 8])
        XCTAssertEqual(steppedAt(flick, gap: 0.02, speed: 2), [2, 4, 7, 9, 12])
        XCTAssertEqual(steppedAt(flick, gap: 0.02, speed: 3), [1, 3, 5, 6, 8, 10, 11])
        XCTAssertEqual(steppedAt(stroke, gap: 0.094, speed: 1), [3, 8])
        XCTAssertEqual(steppedAt(stroke, gap: 0.094, speed: 2), [2, 4, 7, 9])
        XCTAssertEqual(steppedAt(stroke, gap: 0.094, speed: 3), [2, 3, 5, 6, 8])
    }

    /// A roll of 15 lines toward the next desktop, then one tick of 0.10 line the other way
    /// 0.7 s later (where the thumb lets go): no desktop back, at 0.7× and at 3× (where one
    /// tick reaches the first threshold alone).
    func testDesktops_aLoneTickAfterARoll_runsNothing() throws {
        for speed in [0.7, 3.0] {
            let rig = Rig()
            let settings = ThumbWheelSettings(function: .desktops, speed: speed)
            for index in 0..<6 { rig.turn(lines: -2.5, at: Double(index) * 0.05, settings: settings) }
            XCTAssertEqual(rig.turn(lines: 0.1, at: 0.25 + 0.7, settings: settings), 0, "x\(speed)")
            rig.advance(to: 510)
            XCTAssertFalse(rig.performed.contains { $0.action == .named("moveSpaceLeft") }, "x\(speed)")
            let tick = try XCTUnwrap(rig.lines.last)
            XCTAssertEqual(rig.lines.count, 2, "the tick is a roll of its own")
            XCTAssertEqual(tick.events, 1)
            XCTAssertEqual(tick.ticksHeld, 1, "x\(speed)")
            XCTAssertEqual(tick.ticksDropped, 1, "x\(speed)")
            XCTAssertEqual(tick.stepsNext + tick.stepsPrevious, 0)
        }
    }

    /// A roll, then where the thumb lets go a pair of ticks the other way (+0.10 line 0.7 s
    /// after it, +0.10 0.12 s later): nothing runs for it, for volume at 1× nor for desktops
    /// at 1.5× (where the pair reached the first step), and the pair is counted as dropped.
    func testALetGoPairAfterARoll_runsNothing() throws {
        for (function, speed, wrongWay) in [(ThumbWheelFunction.volume, 1.0, ThumbWheelAction.volume(.down)),
                                            (.desktops, 1.5, .named("moveSpaceLeft"))] {
            let rig = Rig()
            let settings = ThumbWheelSettings(function: function, speed: speed)
            for index in 0..<6 { rig.turn(lines: -2.5, at: Double(index) * 0.05, settings: settings) }
            XCTAssertEqual(rig.turn(lines: 0.1, at: 0.25 + 0.7, settings: settings), 0)
            XCTAssertEqual(rig.turn(lines: 0.1, at: 0.25 + 0.82, settings: settings), 0)
            rig.advance(to: 510)
            XCTAssertFalse(rig.performed.isEmpty, "\(function): the roll ran")
            XCTAssertFalse(rig.performed.contains { $0.action == wrongWay }, "\(function): \(rig.performed)")
            let pair = try XCTUnwrap(rig.lines.last)
            XCTAssertEqual(pair.events, 2, "\(function)")
            XCTAssertEqual(pair.ticksHeld, 2, "\(function)")
            XCTAssertEqual(pair.ticksDropped, 2, "\(function)")
        }
    }

    /// Another function starts the filter afresh: what the last one held is dropped and
    /// counted in its line, and does not confirm the new function's small ticks.
    func testAChangeOfFunctionResetsTheFilter() throws {
        let rig = Rig()
        rig.turn(lines: -0.1, at: 0, settings: ThumbWheelSettings(function: .tabs))
        rig.turn(lines: -0.1, at: 0.05, settings: ThumbWheelSettings(function: .tabs))
        XCTAssertEqual(rig.engine.tickFilter.heldEvents, 2)
        let volume = ThumbWheelSettings(function: .volume)
        XCTAssertEqual(rig.turn(lines: -0.3, at: 0.1, settings: volume), 0, "held anew, not a third")
        XCTAssertEqual(rig.engine.tickFilter.heldEvents, 1)
        rig.turn(lines: -0.3, at: 0.15, settings: volume)
        rig.advance(to: 510)
        XCTAssertEqual(rig.performed.map(\.action), [.volume(.up)], "volume's own two events")
        XCTAssertEqual(rig.lines.first?.function, .tabs)
        XCTAssertEqual(rig.lines.first?.ticksDropped, 2)
    }

    /// Volume at 3×: one tick the other way inside a roll that turns it up does not turn it down.
    func testVolume_atSpeed3_aStrayTickInsideARollDoesNotTurnItDown() throws {
        let rig = Rig()
        let settings = ThumbWheelSettings(function: .volume, speed: 3)
        for index in 0..<10 {
            rig.turn(lines: -5, at: Double(index) * 0.05, settings: settings)
            if index == 4 { rig.turn(lines: 0.1, at: Double(index) * 0.05 + 0.02, settings: settings) }
        }
        rig.advance(to: 510)
        XCTAssertFalse(rig.performed.isEmpty)
        XCTAssertTrue(rig.performed.allSatisfy { $0.action == .volume(.up) }, "\(rig.performed)")
        XCTAssertEqual(rig.lines.first?.ticksDropped, 1)
    }

    /// A stop drops a held tick: it does not act afterwards, and it is counted.
    func testReset_dropsAHeldTick() {
        let rig = Rig()
        let settings = ThumbWheelSettings(function: .tabs, speed: 3)
        rig.turn(lines: -0.1, at: 0, settings: settings)
        XCTAssertTrue(rig.engine.tickFilter.holds)
        rig.engine.reset()
        XCTAssertFalse(rig.engine.tickFilter.holds)
        XCTAssertEqual(rig.lines.first?.ticksDropped, 1)
        XCTAssertEqual(rig.turn(lines: -0.1, at: 0.1, settings: settings), 0, "held again: the first one is gone")
        rig.advance(to: 510)
        XCTAssertEqual(rig.performed, [])
    }

    /// A stop (Pause, sleep, lost access) with volume steps waiting: none of them runs, then or
    /// later, and the next turn starts with nothing waiting.
    func testReset_withVolumeStepsWaiting_runsNone() throws {
        let rig = Rig()
        let settings = ThumbWheelSettings(function: .volume, speed: 3)
        rig.turn(lines: -12, at: 0, settings: settings)
        rig.turn(lines: -12, at: 0.01, settings: settings)
        XCTAssertEqual(rig.performed.count, 1, "the first ran at once")
        XCTAssertEqual(rig.engine.pacer.waiting, 3)
        rig.engine.reset()
        XCTAssertEqual(rig.engine.pacer.waiting, 0)
        rig.advance(to: 505)
        XCTAssertEqual(rig.performed.count, 1, "none of the waiting ran")
        XCTAssertEqual(rig.lines.first?.droppedSteps, 3)

        rig.turn(lines: -12, at: 10, settings: settings)
        rig.advance(to: 520)
        XCTAssertEqual(rig.performed.count, 3, "the next turn's own two steps only")
        XCTAssertEqual(rig.lines.last?.droppedSteps, 0)
    }

    /// Scrollio's scroll handling stopped (Pause, sleep, lost access): steps already decided
    /// do not run afterwards.
    func testReset_dropsStepsNotYetRun_andWritesTheOpenRollsLine() {
        let rig = Rig()
        XCTAssertEqual(rig.turn(lines: -12, at: 0, settings: ThumbWheelSettings(function: .volume)), 1)
        rig.engine.reset()
        XCTAssertEqual(rig.lines.count, 1, "the roll so far")
        XCTAssertEqual(rig.lines.first?.stepsNext, 0, "decided, but none ran")
        XCTAssertEqual(rig.lines.first.map(ScrollSystemLog.thumbWheelMessage)?.hasSuffix("volume x1.00, travel 2.0: 0 steps; ticks held 0, dropped 0"), true)
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
        rig.advance(to: 500.2 + ThumbWheelTuning.logRollRest - 0.01)
        XCTAssertEqual(rig.lines.count, 0, "not before the wheel rested")
        rig.advance(to: 500.2 + ThumbWheelTuning.logRollRest)
        let roll = try XCTUnwrap(rig.lines.first)
        XCTAssertEqual(rig.lines.count, 1)
        XCTAssertEqual(roll.events, 5)
        XCTAssertEqual(roll.lines, -5)
        XCTAssertEqual(roll.fixed, -5)
        XCTAssertEqual(roll.points, -50)
        XCTAssertEqual(roll.largestPoints, 10)
        XCTAssertEqual(roll.largestFixed, 1)
        XCTAssertEqual(roll.continuousEvents, 1)
        XCTAssertEqual(roll.stepsNext, 1, "the step that ran: the third event")
        XCTAssertEqual(roll.stepsPrevious, 0)
        XCTAssertEqual(roll.function, .tabs)
        XCTAssertEqual(roll.lastEventAt - roll.startedAt, 0.2, accuracy: 1e-6)
        XCTAssertEqual(roll.longestGap, 0.05, accuracy: 1e-6)
        XCTAssertEqual(
            ScrollSystemLog.thumbWheelMessage(for: roll),
            "thumb wheel: 5 events in 200 ms (longest gap 50 ms), lines -5, fixed -5.00 (largest 1.00), points -50 (largest 10), 0 direction changes, partly continuous (1 of 5), switch tabs x1.00, travel 5.0: 1 step next; ticks held 0, dropped 0"
        )
        XCTAssertFalse(rig.hasPendingWork, "no timer while the wheel is still")
        XCTAssertNil(rig.engine.roll)
    }

    /// Follow the wheel's line lists each swipe: how far it went, how it ended, and after an
    /// end where a switch was expected the time to the Space change or "no change"; past 8
    /// they are summed. Every function's line says what the stray-tick filter held and dropped.
    func testLog_theFollowLineListsEachSwipe_andEveryFunctionLineTheTicks() {
        typealias Swipe = ThumbWheelFollower.Swipe
        var roll = ScrollSystemLog.ThumbWheelRoll(id: 1, settings: ThumbWheelSettings(function: .desktops, speed: 0.7, followsWheel: true), at: 0)
        roll.add(ThumbWheelEvent(lineDelta: -1, fixedDelta: -1.5, pointDelta: -15, isContinuous: false), travel: 0.7, at: 0)
        XCTAssertTrue(ScrollSystemLog.thumbWheelMessage(for: roll).hasSuffix("switch desktops, following x0.70, travel 0.7: no swipe; ticks held 0, dropped 0"),
                      ScrollSystemLog.thumbWheelMessage(for: roll))
        roll.pendingSwipes = 2
        roll.swipeEnded(Swipe(furthest: 1, ending: .chained, expectsSwitch: true, spaceChangedAfter: 0.24))
        roll.swipeEnded(Swipe(furthest: 0.62, ending: .ended, expectsSwitch: true, spaceChangedAfter: nil))
        XCTAssertEqual(roll.pendingSwipes, 0)
        roll.ticksFiltered(ThumbWheelTickFilter.Result(travel: 0, held: true, dropped: 0))
        roll.ticksFiltered(ThumbWheelTickFilter.Result(travel: 0.7, held: false, dropped: 1))
        XCTAssertTrue(ScrollSystemLog.thumbWheelMessage(for: roll).hasSuffix(
            "switch desktops, following x0.70, travel 0.7: swipes 1.00 chained +240 ms, 0.62 ended no change; ticks held 1, dropped 1"
        ), ScrollSystemLog.thumbWheelMessage(for: roll))

        let more = [
            Swipe(furthest: 1, ending: .fullStop, expectsSwitch: true, spaceChangedAfter: 0.18),
            Swipe(furthest: 0.12, ending: .back), Swipe(furthest: 0.4, ending: .interrupted),
            Swipe(furthest: 1, ending: .chained, expectsSwitch: true, spaceChangedAfter: 0.3),
            Swipe(furthest: 1, ending: .chained, expectsSwitch: true, spaceChangedAfter: 0.31),
            Swipe(furthest: 0.35, ending: .ended),
            Swipe(furthest: 1, ending: .chained, expectsSwitch: true), Swipe(furthest: 1, ending: .chained, expectsSwitch: true),
            Swipe(furthest: 0.99, ending: .fullStop, expectsSwitch: true),
        ]
        more.forEach { roll.swipeEnded($0) }
        roll.strokesWaited = 1
        XCTAssertEqual(roll.swipeTally.total, 11)
        XCTAssertEqual(ScrollSystemLog.followMessage(for: roll), [
            "swipes 1.00 chained +240 ms", "0.62 ended no change", "1.00 full stop +180 ms", "0.12 back", "0.40 interrupted",
            "1.00 chained +300 ms", "1.00 chained +310 ms", "0.35 ended", "+3 more (2 chained, 1 full stop)",
            "1 stroke waited for another swipe",
        ].joined(separator: ", "))

        let sideways = ScrollSystemLog.ThumbWheelRoll(id: 2, settings: .default, at: 0)
        XCTAssertFalse(ScrollSystemLog.thumbWheelMessage(for: sideways).contains("ticks"), "Scroll Sideways filters nothing")
    }

    /// One trace line per roll that runs a function, right after its line: each event's gap
    /// (ms) and fixed-point lines, 128 at most; none for Scroll Sideways.
    func testLog_aTraceLinePerFunctionRoll_atMost128Events() throws {
        let rig = Rig()
        let tabs = ThumbWheelSettings(function: .tabs)
        rig.turn(lines: 0, at: 0, settings: tabs, fixed: -0.1)
        rig.turn(lines: 0, at: 0.094, settings: tabs, fixed: -0.35)
        rig.turn(lines: -1, at: 0.195, settings: tabs, fixed: -1)
        rig.advance(to: 501)
        XCTAssertEqual(rig.traces, ["thumb wheel trace: 3 events, ms/fixed 0/-0.10 94/-0.35 101/-1.00"])
        XCTAssertEqual(rig.lines.count, 1)

        rig.turn(lines: -1, at: 2, settings: .default)
        rig.advance(to: 503)
        XCTAssertEqual(rig.lines.count, 2)
        XCTAssertEqual(rig.traces.count, 1, "none for Scroll Sideways")

        let zoom = ThumbWheelSettings(function: .zoom)
        for index in 0..<150 { rig.turn(lines: -1, at: 4 + Double(index) * 0.01, settings: zoom) }
        rig.advance(to: 510)
        XCTAssertEqual(rig.lines.map(\.events), [3, 1, 150])
        let trace = try XCTUnwrap(rig.traces.last)
        XCTAssertTrue(trace.hasPrefix("thumb wheel trace: 150 events (the first 128), ms/fixed 0/-1.00 10/-1.00 "), trace)
        XCTAssertEqual(trace.components(separatedBy: "ms/fixed ").last?.split(separator: " ").count, 128)
        XCTAssertFalse(rig.hasPendingWork)
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
        XCTAssertEqual(rig.lines.map { ($0.startedAt * 10).rounded() / 10 }, [500, 502, 504])
        XCTAssertFalse(rig.hasPendingWork)
    }

    /// A setting changed in the middle of a roll (the function, the speed, the direction):
    /// the roll so far gets its own line, written after the callback.
    func testLog_aSettingChangedInTheMiddleOfARollEndsItsLine() {
        let rig = Rig()
        rig.turn(lines: -1, at: 0, settings: ThumbWheelSettings(function: .tabs))
        rig.turn(lines: -1, at: 0.05, settings: ThumbWheelSettings(function: .tabs))
        rig.turn(lines: -1, at: 0.1, settings: ThumbWheelSettings(function: .tabs))
        rig.turn(lines: -1, at: 0.15, settings: ThumbWheelSettings(function: .zoom))
        XCTAssertEqual(rig.lines.count, 0, "nothing written inside the callback")
        rig.advance(to: 500.15)
        XCTAssertEqual(rig.lines.map(\.function), [.tabs])
        XCTAssertEqual(rig.lines.first?.events, 3)
        rig.turn(lines: -1, at: 0.2, settings: ThumbWheelSettings(function: .zoom, speed: 2))
        rig.advance(to: 510)
        XCTAssertEqual(rig.lines.map(\.function), [.tabs, .zoom, .zoom])
        XCTAssertEqual(rig.lines.map(\.speed), [1, 1, 2])
        XCTAssertEqual(rig.lines.first?.stepsNext, 1, "the tab that ran before its line was written")
        XCTAssertFalse(rig.hasPendingWork)
    }

    /// What the tuning is read from: the largest fixed-point delta (the acceleration depends on
    /// it), the longest gap (the rests depend on it), how often the wheel turned back (the sums
    /// cancel out then), the travel in units, and the steps that ran in each direction.
    func testLog_gapsTurnsBackTravelAndTheStepsOfEachDirection() throws {
        let rig = Rig()
        let volume = ThumbWheelSettings(function: .volume)
        rig.turn(lines: -1, at: 0, settings: volume, fixed: -1.25)
        rig.turn(lines: -1, at: 0.03, settings: volume)
        rig.turn(lines: 1, at: 0.15, settings: volume, fixed: 2.5)
        rig.turn(lines: 1, at: 0.2, settings: volume)
        rig.turn(lines: -2, at: 0.25, settings: volume)
        rig.advance(to: 510)
        let roll = try XCTUnwrap(rig.lines.first)
        XCTAssertEqual(rig.lines.count, 1)
        XCTAssertEqual(roll.directionChanges, 2)
        XCTAssertEqual(roll.longestGap, 0.12, accuracy: 1e-6)
        XCTAssertEqual(roll.largestFixed, 2.5)
        XCTAssertEqual(roll.travel, 5.0625, accuracy: 1e-9, "1 + 1 + 1.0625 (2.5 lines) + 1 + 1")
        XCTAssertEqual(roll.stepsNext, 1, "two units toward next")
        XCTAssertEqual(roll.stepsPrevious, 1, "turned: two more units toward previous; the last turn is one unit")
        XCTAssertEqual(rig.performed.map(\.action), [.volume(.up), .volume(.down)])
        XCTAssertEqual(
            ScrollSystemLog.thumbWheelMessage(for: roll),
            "thumb wheel: 5 events in 250 ms (longest gap 120 ms), lines -2, fixed -0.75 (largest 2.50), points -20 (largest 20), 2 direction changes, not continuous, volume x1.00, travel 5.1: 1 step next, 1 previous; ticks held 0, dropped 0"
        )
    }

    /// Rests are measured between the events' own times. After a stall of the main thread the
    /// events of one roll arrive in a burst: the first must not look like a new roll, or one
    /// roll runs Back (or a desktop switch) twice.
    func testRests_useTheEventsOwnTime_notWhenTheCallbackRuns() {
        let rig = Rig()
        let back = ThumbWheelSettings(function: .backForward)
        var steps = 0
        for index in 0..<3 {
            steps += rig.turn(lines: -1, at: Double(index) * 0.05, settings: back)
        }
        // The main thread stalls for 0.6 s: the next three events reach the callback together.
        for index in 3..<6 {
            steps += rig.turn(lines: -1, at: Double(index) * 0.05, settings: back, processedAt: 0.75)
        }
        XCTAssertEqual(steps, 1, "one roll, one step")
        rig.advance(to: 510)
        XCTAssertEqual(rig.performed, [Performed(action: .named("navigateForward"), times: 1)])
    }

    /// The events' times may have another base than the clock the look at the roll uses: the
    /// line still comes once the wheel rested, and nothing stays scheduled.
    func testLog_theLookUsesTheClockWhateverTheEventsTimes() {
        for offset in [-400.0, 3_600] {
            let rig = Rig()
            for index in 0..<3 {
                rig.turn(lines: -1, at: Double(index) * 0.05, settings: .default, timestampOffset: offset)
            }
            rig.advance(to: 500.1 + ThumbWheelTuning.logRollRest)
            XCTAssertEqual(rig.lines.map(\.events), [3], "offset \(offset)")
            XCTAssertEqual((rig.lines.first?.lastEventAt ?? 0) - (rig.lines.first?.startedAt ?? 0), 0.1, accuracy: 1e-6, "the events' own times")
            XCTAssertFalse(rig.hasPendingWork, "offset \(offset)")
        }
    }

    /// The look at the roll may come late (a busy main thread): an event after the wheel
    /// rested still starts a new roll, two rolls never merge in one line.
    func testLog_twoRollsDoNotMergeWhenTheLookComesLate() {
        let rig = Rig()
        rig.turn(lines: -1, at: 0, settings: .default)
        rig.turn(lines: -1, at: 0.05, settings: .default)
        // Rested for a second by the events' clock; the look scheduled at 0.4 s has not run.
        rig.turn(lines: 1, at: 1.05, settings: .default, processedAt: 0.06)
        rig.advance(to: 510)
        XCTAssertEqual(rig.lines.map(\.events), [2, 1])
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
    private var savedApplications: EnhanceArray<Application>!
    private var inputs: [ScrollPosterInput] = []

    override func setUp() {
        super.setUp()
        savedApplications = Options.shared.application.applications
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
        // No scroll key held, whatever the tests before left.
        ScrollCore.shared.toggleScroll = false
        ScrollCore.shared.blockSmooth = false
        ScrollUtils.shared.treatAsRemoteForTests(sourcePID: nil)
    }

    override func tearDown() {
        ScrollCore.posterInputObserverForTests = nil
        ScrollCore.shared.thumbWheelEngine = savedEngine
        ScrollCore.shared.handover = ScrollHandover()
        ScrollCore.shared.toggleScroll = false
        ScrollCore.shared.blockSmooth = false
        ScrollCore.shared.isActive = false
        ScrollUtils.shared.treatAsRemoteForTests(sourcePID: nil)
        Options.shared.application.applications = savedApplications
        Options.shared.thumbWheel = savedThumbWheel
        Options.shared.scroll.smooth = savedSmooth
        Options.shared.scroll.reverse = savedReverse
        Options.shared.scroll.reverseHorizontal = savedReverseHorizontal
        Options.shared.application.allowlist = savedAllowlist
        ScrollSystemLog.resetPassthroughForTests()
        super.tearDown()
    }

    /// A wheel event as a mouse sends it: no phase, not continuous (unless asked), aimed at no
    /// app (target pid 1) unless a target is given.
    private func wheelEvent(
        line2: Int64 = 0, fixed2: Double = 0, point2: Double = 0,
        line1: Int64 = 0, point1: Double = 0, flags: CGEventFlags = [],
        continuous: Bool = false, sourcePID: Int64 = 0, targetPID: Int64 = 1
    ) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 0, wheel2: 0, wheel3: 0))
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: line1)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: point1)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Double(line1))
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: line2)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: point2)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: fixed2)
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: continuous ? 1 : 0)
        event.setIntegerValueField(.eventSourceUnixProcessID, value: sourcePID)
        event.setIntegerValueField(.eventTargetUnixProcessID, value: targetPID)
        event.flags = flags
        return event
    }

    private func sideways(_ lines: Int64, point: Double? = nil, flags: CGEventFlags = [], continuous: Bool = false,
                          sourcePID: Int64 = 0, targetPID: Int64 = 1) throws -> CGEvent {
        return try wheelEvent(line2: lines, fixed2: Double(lines), point2: point ?? Double(lines * 10), flags: flags,
                              continuous: continuous, sourcePID: sourcePID, targetPID: targetPID)
    }

    /// The tap's callback. Its result is an unretained reference: use it while `event` lives.
    @discardableResult
    private func tap(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        return ScrollCore.shared.scrollEventCallBack(CGEventTapProxy(bitPattern: 1)!, .scrollWheel, event, nil)
    }

    /// The wheel rests (longer than any function's rest): the next turn starts afresh.
    private func rest() {
        rig.advance(to: rig.now + 1)
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
        XCTAssertFalse(goesOn(try sideways(-1)))

        XCTAssertEqual(inputs.count, 0, "no glide starts or changes")
        XCTAssertEqual(ScrollCore.shared.handover.state, .glide, "the trackpad's glide goes on")
        XCTAssertEqual(rig.performed, [], "nothing runs inside the callback")
        rig.advance(to: rig.now)
        XCTAssertEqual(rig.performed, [ThumbWheelEngineTests.Performed(action: .keys(ThumbWheelAction.nextTab), times: 1)])
    }

    /// The function does not depend on "Smooth scrolling", the allowlist or the reverse rule's
    /// absence: every sideways event is swallowed. The direction follows the reverse rule.
    func testAFunction_doesNotDependOnSmoothingTheAllowlistOrReverse() throws {
        Options.shared.thumbWheel = ThumbWheelSettings(function: .volume)
        // "Reverse wheel direction" on: it applies to an app Scrollio handles, not to one
        // outside the allowlist; a function's direction must not change between them.
        // Each turn is one flick (two units: the volume's first step), after a rest.
        Options.shared.scroll.reverse = true
        Options.shared.scroll.smooth = false
        XCTAssertFalse(goesOn(try sideways(-12)), "smoothing off")
        rest()
        Options.shared.application.allowlist = true
        XCTAssertFalse(goesOn(try sideways(-12)), "outside the allowlist: no reverse rule")
        rest()
        Options.shared.application.allowlist = false
        Options.shared.scroll.smooth = true
        XCTAssertFalse(goesOn(try sideways(-12)), "smoothing on, the global reverse rule")
        rest()
        Options.shared.scroll.reverse = false
        XCTAssertFalse(goesOn(try sideways(-12)), "no reverse rule")
        rig.advance(to: rig.now)
        XCTAssertEqual(rig.performed.map(\.action), [.volume(.up), .volume(.up), .volume(.up), .volume(.up)])
        XCTAssertEqual(inputs.count, 0)
    }

    /// The main wheel (vertical), an event with both deltas, a sideways event with Shift held
    /// (macOS and drivers send the main wheel with Shift that way), and the trackpad: none is
    /// a sideways event; they go as before.
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
        rig.advance(to: rig.now + 10)
        XCTAssertEqual(rig.performed, [])
        XCTAssertEqual(rig.lines, [], "and none is in the thumb wheel's log")
    }

    /// With "Reverse wheel direction" on and the allowlist on, an app outside the list gets no
    /// reverse rule. A function's direction must not follow that: the same turn of the thumb
    /// wheel turns the volume the same way over any app. (Found by the review.)
    func testAFunctionsDirection_doesNotDependOnTheAppUnderThePointer() throws {
        Options.shared.thumbWheel = ThumbWheelSettings(function: .volume)
        Options.shared.scroll.reverse = true
        Options.shared.scroll.reverseHorizontal = true
        Options.shared.application.allowlist = false
        XCTAssertFalse(goesOn(try sideways(-12)), "an app Scrollio handles")
        rest()
        Options.shared.application.allowlist = true
        XCTAssertFalse(goesOn(try sideways(-12)), "the same turn over an app outside the allowlist")
        rig.advance(to: rig.now)
        XCTAssertEqual(rig.performed.count, 2)
        XCTAssertEqual(rig.performed.first?.action, rig.performed.last?.action,
                       "the same turn of the thumb wheel: \(rig.performed.map(\.action))")
    }

    // MARK: What a broken engine would change

    /// Scrollio's own "scroll sideways" key does not stop the thumb wheel's function: the main
    /// wheel's events are vertical at the tap, the thumb wheel's stay sideways events.
    func testScrollioHoldKey_leavesTheThumbWheelsFunctionAlone() throws {
        Options.shared.thumbWheel = ThumbWheelSettings(function: .volume)
        let event = try sideways(-12)
        ScrollCore.shared.toggleScroll = true
        let wentOn = goesOn(event)
        ScrollCore.shared.toggleScroll = false
        XCTAssertFalse(wentOn, "swallowed: it runs the function")
        rig.advance(to: rig.now)
        XCTAssertEqual(rig.performed.map(\.action), [.volume(.up)])
    }

    /// "Swap direction" turns a function around; "Reverse wheel direction" does not.
    func testAFunction_swapTurnsItsDirectionAround() throws {
        Options.shared.thumbWheel = ThumbWheelSettings(function: .volume)
        XCTAssertFalse(goesOn(try sideways(-12)))
        rest()
        Options.shared.thumbWheel.swapsDirection = true
        XCTAssertFalse(goesOn(try sideways(-12)))
        rest()
        Options.shared.scroll.reverse = true
        XCTAssertFalse(goesOn(try sideways(-12)))
        rig.advance(to: rig.now)
        XCTAssertEqual(rig.performed.map(\.action), [.volume(.up), .volume(.down), .volume(.down)])
    }

    /// Pause, sleep or lost access (`disable()`): steps decided before it do not run after
    /// it, and the log line counts none.
    func testStop_dropsTheStepsDecidedBeforeIt() throws {
        Options.shared.thumbWheel = ThumbWheelSettings(function: .volume)
        XCTAssertFalse(goesOn(try sideways(-12)))
        ScrollCore.shared.isActive = true   // as after enable(); no event tap is created here
        ScrollCore.shared.disable()
        XCTAssertFalse(ScrollCore.shared.isActive)
        rig.advance(to: rig.now + 10)
        XCTAssertEqual(rig.performed, [])
        XCTAssertEqual(rig.lines.map(\.stepsNext), [0])
    }

    /// An event with both deltas is not a sideways event: "Swap direction", the thumb wheel's
    /// speed and its function leave it exactly as at the defaults, smoothed or let through.
    func testADiagonalEvent_isExactlyAsAtTheDefaults() throws {
        func diagonal() throws -> CGEvent {
            return try wheelEvent(line2: -2, fixed2: -2, point2: -24, line1: -1, point1: -10)
        }
        let settings = [
            ThumbWheelSettings(),
            ThumbWheelSettings(swapsDirection: true),
            ThumbWheelSettings(speed: 3),
            ThumbWheelSettings(function: .tabs, speed: 3, swapsDirection: true),
        ]
        var smoothed: [ScrollPosterInput] = []
        var letThrough: [[Double]] = []
        for setting in settings {
            Options.shared.thumbWheel = setting
            Options.shared.scroll.smooth = true
            inputs = []
            let toSmooth = try diagonal()
            tap(toSmooth)
            smoothed.append(try XCTUnwrap(inputs.last, "\(setting)"))
            Options.shared.scroll.smooth = false
            let event = try diagonal()
            XCTAssertTrue(goesOn(event), "\(setting)")
            letThrough.append(xFields(event))
        }
        for index in 1..<settings.count {
            let label = "\(settings[index])"
            XCTAssertEqual(smoothed[index].x, smoothed[0].x, label)
            XCTAssertEqual(smoothed[index].y, smoothed[0].y, label)
            XCTAssertEqual(smoothed[index].notch, smoothed[0].notch, label)
            XCTAssertEqual(letThrough[index], letThrough[0], label)
        }
        rig.advance(to: rig.now + 10)
        XCTAssertEqual(rig.performed, [])
    }

    /// A remote desktop's smoothed sideways event goes on as before: no function runs, and it
    /// takes a trackpad glide over like any wheel event.
    func testARemoteSmoothedSidewaysEvent_runsNoFunction() throws {
        Options.shared.thumbWheel = ThumbWheelSettings(function: .zoom)
        let remotePID: Int64 = 424_242
        ScrollUtils.shared.treatAsRemoteForTests(sourcePID: pid_t(remotePID))
        XCTAssertEqual(ScrollCore.shared.handover.trackpadEvent(scrollPhase: 0, momentumPhase: 1, hasDelta: true), .letThrough)
        let event = try sideways(-2, continuous: true, sourcePID: remotePID)
        XCTAssertTrue(ScrollUtils.shared.isRemoteSmoothedEvent(event))
        XCTAssertTrue(goesOn(event))
        XCTAssertEqual(ScrollCore.shared.handover.state, .wheelTookOver(dropped: 0))
        rig.advance(to: rig.now + 10)
        XCTAssertEqual(rig.performed, [])
        XCTAssertEqual(rig.lines, [])
    }

    /// Whether an event is continuous reaches the roll as the event says it.
    func testContinuity_reachesTheRollAsTheEventSaysIt() throws {
        tap(try sideways(-1, continuous: false))
        tap(try sideways(-1, continuous: true))
        tap(try sideways(-1, continuous: true))
        let roll = try XCTUnwrap(rig.engine.roll)
        XCTAssertEqual(roll.events, 3)
        XCTAssertEqual(roll.continuousEvents, 2)
    }

    /// With a function set, the main wheel's (vertical) event during a trackpad glide still
    /// takes the glide over: only a sideways event that runs a function leaves it alone.
    func testAVerticalEventDuringATrackpadGlide_takesItOver_withAFunctionSet() throws {
        Options.shared.thumbWheel = ThumbWheelSettings(function: .tabs)
        Options.shared.scroll.smooth = false
        XCTAssertEqual(ScrollCore.shared.handover.trackpadEvent(scrollPhase: 0, momentumPhase: 1, hasDelta: true), .letThrough)
        XCTAssertTrue(goesOn(try wheelEvent(line1: -1, point1: -10)))
        XCTAssertEqual(ScrollCore.shared.handover.state, .wheelTookOver(dropped: 0))
    }

    /// An app's own reverse rule, through the callback (the event aimed at this very app): it
    /// turns the sideways scroll around and "Swap direction" turns it back; a function's
    /// direction does not follow it.
    func testAnAppsOwnReverseRule_turnsTheSidewaysScroll_notAFunction() throws {
        let path = try XCTUnwrap(NSRunningApplication.current.bundleURL?.path)
        let app = Application(path: path)
        app.inherit = false
        app.scroll.smooth = false
        app.scroll.reverse = true
        app.scroll.reverseHorizontal = true
        Options.shared.application.applications = EnhanceArray<Application>(withArray: [app], matchKey: "path")
        let ownPID = Int64(ProcessInfo.processInfo.processIdentifier)

        let overTheApp = try sideways(-2, point: -23, targetPID: ownPID)
        let before = xFields(overTheApp)
        XCTAssertTrue(goesOn(overTheApp))
        XCTAssertTrue(ScrollCore.shared.application === app, "the app's own rule is used")
        XCTAssertEqual(xFields(overTheApp), before.map { -$0 }, "turned around by the app's rule")

        Options.shared.thumbWheel.swapsDirection = true
        let swapped = try sideways(-2, point: -23, targetPID: ownPID)
        XCTAssertTrue(goesOn(swapped))
        XCTAssertEqual(xFields(swapped), before, "and back by Swap direction")

        Options.shared.thumbWheel = ThumbWheelSettings(function: .volume)
        XCTAssertFalse(goesOn(try sideways(-12, targetPID: ownPID)), "over the app")
        rest()
        XCTAssertFalse(goesOn(try sideways(-12)), "over no app")
        rig.advance(to: rig.now)
        XCTAssertEqual(rig.performed.map(\.action), [.volume(.up), .volume(.up)])
    }

    // MARK: The decisions (pure)

    func testSidewaysWheelEvent_horizontalOnly_notRemoteSmoothed_noShift() {
        func sideways(v: Bool, h: Bool, remote: Bool = false, shift: Bool = false) -> Bool {
            return ScrollCore.isSidewaysWheelEvent(hasVerticalDelta: v, hasHorizontalDelta: h, remoteSmoothed: remote, shiftDown: shift)
        }
        XCTAssertTrue(sideways(v: false, h: true))
        XCTAssertFalse(sideways(v: true, h: false), "the main wheel")
        XCTAssertFalse(sideways(v: true, h: true), "both: as before")
        XCTAssertFalse(sideways(v: false, h: false))
        XCTAssertFalse(sideways(v: false, h: true, remote: true))
        XCTAssertFalse(sideways(v: false, h: true, shift: true))
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
