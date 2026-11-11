//
//  ScrollClassicPathTests.swift
//  MosTests
//
//  Smooth scrolling end to end, as the display link runs it. Each wheel event adds
//  max(step, point delta) × speed to a target; the position follows with a lerp whose factor
//  comes from Duration (time-based, 60 Hz reference); ScrollFilter rounds off the start;
//  frames under the dead zone are not posted; "Trackpad-style events" add gesture phases.
//
//  Wheel events go in the way ScrollCore builds them. Frames are recorded instead of posted,
//  and the stop the display link asks for is carried out as the main thread does it.
//

import XCTest
@testable import Mos_Debug

// MARK: - Rig

/// A poster with its own phase machine and dispatch context, driven by a simulated clock.
final class ScrollClassicRig {

    struct Recorded {
        let time: Double
        let frame: ScrollOutgoingFrame
    }

    let poster: ScrollPoster
    let phases = ScrollPhase()
    /// The default Step, and Speed 2.7 (not the default 6.3): the expected values below
    /// depend on it.
    let step = 33.6
    let speed = 2.7
    let duration: Double
    let deadZone: Double
    let frameInterval: Double
    /// Arbitrary start; must be > 0 (0 means "no event yet" in the poster).
    let start = 100.0
    private(set) var now: Double
    private var nextFrame: Double
    private(set) var isRunning = false

    private(set) var recorded: [Recorded] = []
    /// When each stop was asked for (after `start`) and with which phase.
    private(set) var stops: [(time: Double, phase: Phase)] = []
    /// What the system log line of each finished scroll said.
    private(set) var sessions: [ScrollSystemLog.Session] = []

    init(duration: Double = 4.35, rate: Double = 60, trackpadStyle: Bool = false, deadZone: Double = 1) {
        self.duration = duration
        self.deadZone = deadZone
        frameInterval = 1 / rate
        now = start
        nextFrame = start + frameInterval
        poster = ScrollPoster(phases: phases, dispatchContext: ScrollDispatchContext())
        poster.frameRecorderForTests = { [unowned self] frame in
            self.recorded.append(Recorded(time: self.now, frame: frame))
        }
        poster.setConfigForTests(simTrackpadEnabled: trackpadStyle, deadZone: deadZone)
    }

    /// One notch at the default Step and Speed 2.7 (px).
    var notch: Double { return step * speed }

    var transition: Double {
        return OPTIONS_SCROLL_DEFAULT.generateDurationTransition(with: duration)
    }

    /// Runs the display frames due up to `time` (seconds after `start`). A frame that finds the
    /// motion finished asks for the stop, which is then carried out at once.
    func run(until time: Double) {
        let target = start + time
        while nextFrame <= target + 1e-9 {
            now = nextFrame
            nextFrame += frameInterval
            guard isRunning else { continue }
            if let request = poster.displayLinkFrameForTests(frameInterval: frameInterval, now: now) {
                sessions.append(poster.sessionLogForTests)
                stops.append((now - start, request.phase))
                XCTAssertTrue(poster.performRequestedStop(request), "the request is current")
                isRunning = false
            }
        }
        now = target
    }

    /// One vertical wheel event with `pointDelta` px (signed) at `time`, as ScrollCore resolves
    /// it: max(step, |point delta|) × speed (× 5 with dash).
    func wheel(_ pointDelta: Double, at time: Double, dash: Bool = false) {
        let gain = speed * (dash ? 5 : 1)
        let distance = max(step, abs(pointDelta)) * (pointDelta < 0 ? -1 : 1)
        input(distance * gain, notch: step * gain, at: time)
    }

    /// One vertical wheel event that adds `pixels` (already multiplied by speed) at `time`.
    func input(_ pixels: Double, notch: Double? = nil, at time: Double) {
        run(until: time)
        now = start + time
        poster.inputForTests(
            ScrollPosterInput(y: pixels, x: 0, notch: notch ?? self.notch, duration: transition),
            at: start + time
        )
        isRunning = true
    }

    // MARK: Results

    /// Frames that move the page.
    var moving: [Recorded] { return recorded.filter { $0.frame.y != 0 || $0.frame.x != 0 } }
    var postedY: Double { return recorded.reduce(0) { $0 + $1.frame.y } }
    /// Time (after `start`) of the last frame that moved the page.
    var lastMovement: Double { return (moving.last?.time ?? start) - start }
    /// Longest time between two consecutive frames that moved the page.
    var longestPause: Double {
        let times = moving.map { $0.time }
        return zip(times.dropFirst(), times).map { $0 - $1 }.max() ?? 0
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

    static func phaseName(scroll: Double, momentum: Double) -> String {
        switch (scroll, momentum) {
        case (1, 0): return "began"
        case (2, 0): return "changed"
        case (4, 0): return "ended"
        case (0, 1): return "momentumBegan"
        case (0, 2): return "momentumChanged"
        case (0, 3): return "momentumEnded"
        default: return "(\(scroll),\(momentum))"
        }
    }
}

// MARK: - Tests

final class ScrollClassicPathTests: XCTestCase {

    /// After the largest frame the page only slows down, and once the frames have fallen under
    /// the dead zone nothing more is posted (no late kick).
    private func assertGlidesOut(_ rig: ScrollClassicRig, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let frames = rig.moving.map { $0.frame.y }
        guard let peak = frames.indices.max(by: { abs(frames[$0]) < abs(frames[$1]) }) else {
            return XCTFail("nothing was posted (\(label))", file: file, line: line)
        }
        for index in (peak + 1)..<frames.count {
            XCTAssertLessThanOrEqual(abs(frames[index]), abs(frames[index - 1]) + 1e-9, "\(label): frame \(index) after the peak", file: file, line: line)
        }
        XCTAssertLessThan(rig.longestPause, 1.5 * rig.frameInterval, "\(label): one run of frames, nothing posted after a pause", file: file, line: line)
    }

    // MARK: One notch

    func testOneNotch_startsAtOnceGlidesOutAndPostsNothingUnderTheDeadZone() throws {
        for duration in [3.9, 4.35, 4.6] {
            let label = "Duration \(duration)"
            let rig = ScrollClassicRig(duration: duration)
            // A line-mode wheel reports 10 px for one line; ScrollCore raises it to one step.
            rig.wheel(10, at: 0)
            rig.run(until: 3)

            // The first display frame already moves: one lerp step, rounded off by the filter.
            let first = try XCTUnwrap(rig.moving.first, label)
            XCTAssertEqual(first.time, rig.start + rig.frameInterval, accuracy: 1e-9, label)
            let expected = rig.notch * rig.transition * ScrollMotion.filterWeight(forTransition: rig.transition)
            XCTAssertEqual(first.frame.y, expected, accuracy: 1e-9, label)
            // ...and it speeds up for a few frames before it slows down.
            let frames = rig.moving.map { $0.frame.y }
            XCTAssertGreaterThan(frames[1], frames[0], label)

            assertGlidesOut(rig, label)
            XCTAssertTrue(rig.moving.allSatisfy { abs($0.frame.y) > rig.deadZone }, label)
            // The exponential tail under one pixel per frame is not posted.
            XCTAssertLessThan(rig.postedY, rig.notch, label)
            XCTAssertGreaterThan(rig.postedY, 0.75 * rig.notch, label)
            XCTAssertEqual(rig.stops.count, 1, label)
            XCTAssertEqual(rig.stops.first?.phase, .MomentumEnd, label)

            // The log line counts what was posted, and only that.
            let session = try XCTUnwrap(rig.sessions.first, label)
            XCTAssertEqual(session.inputs, 1, label)
            XCTAssertEqual(session.inputDistance, rig.notch, accuracy: 1e-9, label)
            XCTAssertEqual(session.frames, rig.moving.count, label)
            XCTAssertEqual(session.largestFrame, frames.max() ?? -1, accuracy: 1e-9, label)
            XCTAssertEqual(session.postedDistance, frames.reduce(0) { $0 + $1.rounded(.towardZero) }, accuracy: 1e-9, label)
            XCTAssertEqual(session.lastFrameAt, rig.moving.last?.time ?? -1, accuracy: 1e-9, label)
            XCTAssertEqual(session.lastInputAt, rig.start, accuracy: 1e-9, label)
        }
    }

    func testOneNotch_longerDurationGlidesLonger() {
        let ends = [3.9, 4.35, 4.6].map { duration -> Double in
            let rig = ScrollClassicRig(duration: duration)
            rig.wheel(10, at: 0)
            rig.run(until: 3)
            return rig.lastMovement
        }
        XCTAssertLessThan(ends[0], ends[1])
        XCTAssertLessThan(ends[1], ends[2])
        XCTAssertGreaterThan(ends[0], 0.25, "even Duration 3.9 glides for a while")
        XCTAssertLessThan(ends[2], 0.8, "and Duration 4.6 is done well within a second")
    }

    // MARK: Several notches

    func testSeveralNotches_addUpToOneGlide() throws {
        let rig = ScrollClassicRig(duration: 4.35)
        for index in 0..<5 { rig.wheel(10, at: Double(index) * 0.05) }
        XCTAssertEqual(rig.poster.motionStateForTests.buffer.y, 5 * rig.notch, accuracy: 1e-9, "steady notches are never cut")
        rig.run(until: 4)

        assertGlidesOut(rig, "five notches")
        XCTAssertLessThan(rig.postedY, 5 * rig.notch)
        XCTAssertGreaterThan(rig.postedY, 5 * rig.notch - 25, "only the tail under the dead zone is missing")
        XCTAssertEqual(rig.stops.count, 1)
        let session = try XCTUnwrap(rig.sessions.first)
        XCTAssertEqual(session.inputs, 5)
        XCTAssertEqual(session.inputDistance, 5 * rig.notch, accuracy: 1e-9)
        XCTAssertEqual(session.lastInputAt - session.startedAt, 0.2, accuracy: 1e-9, "wheel time")
    }

    // MARK: The regression that cost a day

    /// The owner's quick turn of a ratcheted MX Master 4, as measured in the system log:
    /// 5 events within 44 ms of about 430 px each, at Duration 4.5. A free-spin detector took
    /// it for a free-spin, replaced Duration with its own short smoothness and skipped the
    /// filter: the page was dumped out within ~150 ms in frames of up to 800 px, whatever
    /// Duration said. The page has to glide instead.
    func testOwnersQuickBurst_glidesAtTheSetDurationInsteadOfDumping() throws {
        for rate in [60.0, 120.0] {
            let label = "\(rate) Hz"
            let rig = ScrollClassicRig(duration: 4.5, rate: rate)
            for index in 0..<5 { rig.input(428, at: Double(index) * 0.011) }
            rig.run(until: 4)

            let session = try XCTUnwrap(rig.sessions.first, label)
            XCTAssertEqual(session.inputs, 5, label)
            XCTAssertEqual(session.inputDistance, 5 * 428, accuracy: 1e-9, label)
            XCTAssertLessThan(session.largestFrame, 0.35 * 428, "\(label): no frame comes near the size of one input")
            let glide = session.lastFrameAt - session.lastInputAt
            XCTAssertGreaterThan(glide, 0.6, "\(label): the page glides on for several hundred ms")
            XCTAssertLessThan(glide, 2.0, "\(label): and then stops")
            // Everything arrives but the tail under the dead zone.
            XCTAssertGreaterThan(rig.postedY, 5 * 428 - 60, label)
            // Nothing is dumped early: 150 ms after the first event about a quarter is out.
            let early = rig.moving.filter { $0.time - rig.start <= 0.15 }.reduce(0) { $0 + $1.frame.y }
            XCTAssertLessThan(early, 0.35 * 5 * 428, label)
            assertGlidesOut(rig, label)
        }
    }

    // MARK: Direction

    /// Turning the wheel back drops what the old direction still had to go and starts from the
    /// new notch; the filter turns the speed around over a few frames instead of in one.
    func testDirectionReversal_dropsTheOldLeadAndTurnsAroundSmoothly() {
        let poster = ScrollPoster()
        let trans = OPTIONS_SCROLL_DEFAULT.generateDurationTransition(with: 4.35)
        let notch = 33.6 * 2.7
        let dt = 1.0 / 60.0
        var time = 0.0
        var output: [Double] = []
        func frames(until end: Double) {
            while time + dt <= end + 1e-9 {
                time += dt
                output.append(poster.advanceForTests(frameInterval: dt).y)
            }
        }
        for index in 0..<3 {
            frames(until: Double(index) * 0.05)
            poster.applyInputForTests(ScrollPosterInput(y: notch, x: 0, notch: notch, duration: trans), at: time)
        }
        frames(until: 0.2)
        let scrolledBefore = poster.motionStateForTests.current.y
        let beforeReversal = output.count
        XCTAssertLessThan(scrolledBefore, 3 * notch - 50, "a good part of the three notches is still ahead")
        poster.applyInputForTests(ScrollPosterInput(y: -notch, x: 0, notch: notch, duration: trans), at: time)
        XCTAssertEqual(poster.motionStateForTests.buffer.y, -notch)
        XCTAssertEqual(poster.motionStateForTests.current.y, 0)
        frames(until: 5)

        let after = Array(output[beforeReversal...])
        XCTAssertGreaterThan(after[0], 0, "the first frame after the reversal still moves the old way, slower")
        XCTAssertLessThan(after[0], output[beforeReversal - 1])
        guard let lowest = after.indices.min(by: { after[$0] < after[$1] }) else { return XCTFail("no frames") }
        for index in 1...lowest {
            XCTAssertLessThan(after[index], after[index - 1], "frame \(index): the speed turns around steadily")
        }
        XCTAssertLessThan(after.firstIndex { $0 < 0 } ?? .max, 8, "moving the new way within a few frames")
        // Nothing is lost on the way: what the old direction had scrolled, then one notch back.
        XCTAssertEqual(output.reduce(0, +), scrolledBefore - notch, accuracy: 1e-6)
    }

    // MARK: Frame rate

    /// The motion takes the same time at 60 and 120 Hz, so the stop comes at the same time.
    /// (What is posted is not quite the same: the dead zone is per frame, so at 120 Hz the
    /// last frames fall under it a little earlier.)
    func testStopTime_isTheSameAt60And120Hz() {
        let scenarios: [(String, (ScrollClassicRig) -> Void)] = [
            ("one notch", { $0.wheel(10, at: 0) }),
            ("five notches", { rig in (0..<5).forEach { rig.wheel(10, at: Double($0) * 0.05) } }),
            ("quick burst", { rig in (0..<5).forEach { rig.input(428, at: Double($0) * 0.011) } }),
        ]
        for (name, drive) in scenarios {
            for duration in [3.9, 4.5] {
                let at60 = ScrollClassicRig(duration: duration, rate: 60)
                let at120 = ScrollClassicRig(duration: duration, rate: 120)
                drive(at60)
                drive(at120)
                at60.run(until: 5)
                at120.run(until: 5)
                let stop60 = at60.stops.first?.time ?? -1
                let stop120 = at120.stops.first?.time ?? -2
                // Within the sampling of a few 60 Hz frames: the stop is checked once per frame,
                // and an input between two frames is counted from the next one.
                XCTAssertEqual(stop120, stop60, accuracy: 3.0 / 60.0, "\(name), Duration \(duration)")
                XCTAssertGreaterThan(stop60, 0.5, "\(name), Duration \(duration)")
            }
        }
    }

    // MARK: Phases

    func testTrackpadStyle_postsTheTrackpadPhaseSequence() {
        let rig = ScrollClassicRig(duration: 4.35, trackpadStyle: true)
        for index in 0..<3 { rig.wheel(10, at: Double(index) * 0.05) }
        // A second scroll while the first still glides.
        rig.wheel(10, at: 0.7)
        rig.run(until: 4)

        XCTAssertEqual(rig.phaseSequence, [
            "began", "changed", "ended", "momentumBegan", "momentumChanged", "momentumEnded",
            "began", "changed", "ended", "momentumBegan", "momentumChanged", "momentumEnded",
        ])
        // The gesture ends 180 ms after the last tick of each scroll.
        let ended = rig.recorded.filter { $0.frame.scrollPhase == 4 }.map { $0.time - rig.start }
        XCTAssertEqual(ended.count, 2)
        XCTAssertEqual(ended.first ?? 0, 0.1 + 0.18, accuracy: 1.5 / 60.0)
        XCTAssertEqual(ended.last ?? 0, 0.7 + 0.18, accuracy: 1.5 / 60.0)
        XCTAssertTrue(rig.recorded.allSatisfy { $0.frame.scrollPhase != nil }, "every frame carries its phase")
        XCTAssertEqual(rig.stops.count, 1)
    }

    func testWithoutTrackpadStyle_noFrameCarriesPhases() {
        let rig = ScrollClassicRig(duration: 4.35, trackpadStyle: false)
        for index in 0..<3 { rig.wheel(10, at: Double(index) * 0.05) }
        rig.wheel(10, at: 0.7)
        rig.run(until: 4)

        XCTAssertFalse(rig.moving.isEmpty)
        XCTAssertTrue(rig.recorded.allSatisfy { $0.frame.scrollPhase == nil && $0.frame.momentumPhase == nil })
        XCTAssertEqual(rig.stops.count, 1)
        XCTAssertEqual(rig.phases.phase, .Idle, "the phase machine still runs and ends idle")
    }

    func testTrackpadStyle_doesNotChangeTheMotion() {
        let plain = ScrollClassicRig(duration: 4.5, trackpadStyle: false)
        let phased = ScrollClassicRig(duration: 4.5, trackpadStyle: true)
        for rig in [plain, phased] {
            for index in 0..<4 { rig.wheel(10, at: Double(index) * 0.06) }
            rig.run(until: 4)
        }
        XCTAssertEqual(plain.moving.map { $0.frame.y }, phased.moving.map { $0.frame.y })
        XCTAssertEqual(plain.stops.first?.time, phased.stops.first?.time)
    }

    // MARK: Posting

    func testFrame_isWrittenAsAPointDeltaOfTheCopiedEvent() throws {
        let template = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 3, wheel2: 0, wheel3: 0))
        template.timestamp = 1_234
        let event = try XCTUnwrap(template.copy())
        ScrollOutgoingFrame(y: 3.7, x: 0).write(to: event)
        // The fraction is dropped, the line delta and the timestamp of the wheel event stay,
        // phase fields are not touched.
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), 3)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventDeltaAxis1), 3)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventIsContinuous), 1)
        XCTAssertEqual(event.getDoubleValueField(.scrollWheelEventScrollPhase), 0)
        XCTAssertEqual(event.timestamp, 1_234)

        let phased = try XCTUnwrap(template.copy())
        ScrollOutgoingFrame(y: -5, x: 2, scrollPhase: 2, momentumPhase: 0).write(to: phased)
        XCTAssertEqual(phased.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), -5)
        XCTAssertEqual(phased.getIntegerValueField(.scrollWheelEventPointDeltaAxis2), 2)
        XCTAssertEqual(phased.getDoubleValueField(.scrollWheelEventScrollPhase), 2)
        XCTAssertEqual(try XCTUnwrap(NSEvent(cgEvent: phased)).phase, .changed)
    }
}

// MARK: - The system log

/// The diagnostics the owner reads with `log show` (README, "Diagnostics"): they have to say
/// what really happened, and cost nothing per event.
final class ScrollSystemLogTests: XCTestCase {

    override func tearDown() {
        ScrollSystemLog.passthroughObserverForTests = nil
        ScrollSystemLog.resetPassthroughForTests()
        super.tearDown()
    }

    /// An app with its own Duration: the line used to give the global Duration instead.
    func testSessionLine_givesTheDurationTheWheelEventsUsed() throws {
        XCTAssertEqual(Options.shared.scroll.duration, OPTIONS_SCROLL_DEFAULT().duration, "the global Duration is the default")
        for duration in [2.0, 4.6] {
            let rig = ScrollClassicRig(duration: duration)
            rig.wheel(10, at: 0)
            rig.run(until: 3)
            let session = try XCTUnwrap(rig.sessions.first)
            XCTAssertEqual(session.duration, duration, accuracy: 0.005)
            let line = ScrollSystemLog.message(for: session, endedWith: "MomentumEnd")
            XCTAssertTrue(line.contains(String(format: "Duration %.2f", duration)), line)
        }
    }

    func testDurationForTransition_invertsTheSliderMapping() {
        for duration in stride(from: 1.0, through: 5.0, by: 0.05) {
            let transition = OPTIONS_SCROLL_DEFAULT.generateDurationTransition(with: duration)
            XCTAssertEqual(ScrollSystemLog.duration(forTransition: transition), duration, accuracy: 0.005, "\(duration)")
        }
    }

    /// Smoothing switched off: the reason used to read "one axis not smoothed", and the
    /// branch meant for this case could never run.
    func testWheelEventWithSmoothingOff_isLoggedAsSmoothingOff() throws {
        let saved = Options.shared.scroll.smooth
        defer { Options.shared.scroll.smooth = saved }
        Options.shared.scroll.smooth = false
        var reasons: [ScrollSystemLog.PassthroughReason] = []
        ScrollSystemLog.passthroughObserverForTests = { reasons.append($0) }
        let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0))
        ScrollEvent.isTrackpadCallCount = ScrollEvent.isTrackpadCallSamplingRate - 1

        let result = ScrollCore.shared.scrollEventCallBack(CGEventTapProxy(bitPattern: 1)!, .scrollWheel, event, nil)

        XCTAssertNotNil(result, "the event goes on unchanged")
        XCTAssertEqual(reasons, [.smoothingOff])
    }

    func testPassthroughReason_saysWhetherSmoothingWasOnAtAll() {
        XCTAssertEqual(ScrollCore.passthroughReason(smoothingEnabled: false), .smoothingOff)
        XCTAssertEqual(ScrollCore.passthroughReason(smoothingEnabled: true), .axisNotSmoothed)
    }

    /// One line per reason every few seconds, with the count of the events it stands for;
    /// the detail is only built for a line that is written.
    func testPassthrough_isRateLimitedPerReasonAndBuildsNothingWhileQuiet() {
        ScrollSystemLog.resetPassthroughForTests()
        var built = 0
        let detail = { () -> String in built += 1; return "x" }

        let first = ScrollSystemLog.notePassthrough(.smoothingOff, now: 100, detail: detail)
        XCTAssertEqual(first, "wheel events let through unsmoothed (1): smoothing is off for this event (x)")
        for step in 1...50 {
            XCTAssertNil(ScrollSystemLog.notePassthrough(.smoothingOff, now: 100 + Double(step) * 0.05, detail: detail))
        }
        XCTAssertEqual(built, 1, "no detail string per event")
        XCTAssertNotNil(ScrollSystemLog.notePassthrough(.trackpad, now: 101), "another reason has its own limit")
        let next = ScrollSystemLog.notePassthrough(.smoothingOff, now: 100 + ScrollSystemLog.passthroughInterval, detail: detail)
        XCTAssertEqual(next, "wheel events let through unsmoothed (51): smoothing is off for this event (x)")
    }
}
