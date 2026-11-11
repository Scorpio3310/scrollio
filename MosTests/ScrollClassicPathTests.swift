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

    /// `flick`: the app under the pointer scrolls by the events of a glide (Chromium), so
    /// trackpad-style events go out as a short touch and its glide; false: as one long touch.
    init(duration: Double = 4.35, rate: Double = 60, trackpadStyle: Bool = false, deadZone: Double = 1, flick: Bool = true) {
        self.duration = duration
        self.deadZone = deadZone
        frameInterval = 1 / rate
        now = start
        nextFrame = start + frameInterval
        poster = ScrollPoster(phases: phases, dispatchContext: ScrollDispatchContext())
        poster.frameRecorderForTests = { [unowned self] frame in
            self.recorded.append(Recorded(time: self.now, frame: frame))
        }
        // Frame timestamps on the simulated clock, in nanoseconds.
        poster.eventClockForTests = { [unowned self] in UInt64((self.now * 1e9).rounded()) }
        poster.setConfigForTests(simTrackpadEnabled: trackpadStyle, deadZone: deadZone, flick: flick)
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
    func input(_ pixels: Double, notch: Double? = nil, at time: Double, place: ScrollInputPlace? = nil) {
        run(until: time)
        now = start + time
        poster.inputForTests(
            ScrollPosterInput(y: pixels, x: 0, notch: notch ?? self.notch, duration: transition),
            at: start + time,
            place: place
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

    /// Every frame as "phase delta", e.g. "began 0", "changed 7", "momentumEnded 0".
    var stream: [String] {
        return recorded.map { item in
            let name = Self.phaseName(scroll: item.frame.scrollPhase ?? -1, momentum: item.frame.momentumPhase ?? -1)
            return "\(name) \(Int(item.frame.y))"
        }
    }

    /// The phases of all frames, each with the number of frames in a row that carry it.
    var phaseRuns: [String] {
        var runs: [(String, Int)] = []
        for item in recorded {
            let name = Self.phaseName(scroll: item.frame.scrollPhase ?? -1, momentum: item.frame.momentumPhase ?? -1)
            if runs.last?.0 == name { runs[runs.count - 1].1 += 1 } else { runs.append((name, 1)) }
        }
        return runs.map { "\($0.0) ×\($0.1)" }
    }

    /// Time (after `start`) of the first frame with the given phase name.
    func firstTime(of name: String) -> Double? {
        return recorded.first {
            Self.phaseName(scroll: $0.frame.scrollPhase ?? -1, momentum: $0.frame.momentumPhase ?? -1) == name
        }.map { $0.time - start }
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
    ///
    /// Frames are whole pixels with the fraction carried on, so a frame may be one pixel more
    /// than the one before it (2.4 px a frame goes out as 2, 2, 3, 2, 3) but never more. On a
    /// display faster than 60 Hz the last frames come to less than a pixel each: one goes out
    /// every second or third frame, never further apart than a 60 Hz frame and a half.
    private func assertGlidesOut(_ rig: ScrollClassicRig, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let frames = rig.moving.map { $0.frame.y }
        guard let peak = frames.indices.max(by: { abs(frames[$0]) < abs(frames[$1]) }) else {
            return XCTFail("nothing was posted (\(label))", file: file, line: line)
        }
        for index in (peak + 1)..<frames.count {
            XCTAssertLessThanOrEqual(abs(frames[index]), abs(frames[index - 1]) + 1, "\(label): frame \(index) after the peak", file: file, line: line)
        }
        let longestAllowed = 1.5 * max(rig.frameInterval, ScrollMotion.referenceFrameInterval)
        XCTAssertLessThan(rig.longestPause, longestAllowed, "\(label): one run of frames, nothing posted after a pause", file: file, line: line)
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
            // It goes out in whole pixels; its fraction is carried into the next frame.
            let expected = rig.notch * rig.transition * ScrollMotion.filterWeight(forTransition: rig.transition)
            XCTAssertEqual(first.frame.y, expected.rounded(.towardZero), accuracy: 1e-9, label)
            // ...and it speeds up for a few frames before it slows down.
            let frames = rig.moving.map { $0.frame.y }
            XCTAssertGreaterThan(frames[1], frames[0], label)

            assertGlidesOut(rig, label)
            XCTAssertTrue(rig.moving.allSatisfy { $0.frame.y == $0.frame.y.rounded() && abs($0.frame.y) >= 1 }, "\(label): whole pixels")
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
    /// (How far it goes is `testDistance_isTheSameOnFasterDisplays`.)
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

    // MARK: Distance

    /// How far one input goes, per display rate: (posted px, frames that moved).
    private func glide(of pixels: Double, duration: Double, rate: Double) -> (posted: Double, frames: Int, rig: ScrollClassicRig) {
        let rig = ScrollClassicRig(duration: duration, rate: rate)
        rig.input(pixels, notch: pixels, at: 0)
        rig.run(until: 6)
        return (rig.postedY, rig.moving.count, rig)
    }

    /// One click at the owner's settings (Smooth: Duration 3.69, Step 33.6 × Speed 6.3) on a
    /// 60 Hz display. Each frame used to lose its fraction (CoreGraphics drops it), half a
    /// pixel on average: 192 of the 211.68 px went out. With the fraction carried into the
    /// next frame 205 go out, in the same 26 frames; what is missing is the tail under the
    /// dead zone, which is not posted on purpose.
    func testOneClick_losesOnlyTheTailUnderTheDeadZone() throws {
        let click = 33.6 * 6.3
        let result = glide(of: click, duration: 3.69, rate: 60)
        XCTAssertEqual(result.posted, 205)
        XCTAssertEqual(result.frames, 26)
        let frames = result.rig.moving.map { $0.frame.y }
        XCTAssertTrue(frames.allSatisfy { $0 == $0.rounded() && $0 >= 1 }, "whole pixels: \(frames)")
        assertGlidesOut(result.rig, "one click")
        // The log line the owner reads gives exactly what went out.
        let session = try XCTUnwrap(result.rig.sessions.first)
        XCTAssertEqual(session.inputDistance, click, accuracy: 1e-9)
        XCTAssertEqual(session.postedDistance, 205)
        XCTAssertEqual(session.frames, 26)
    }

    /// The same input goes the same distance on a faster display. It used to go less far (a
    /// 120 Hz display has twice the frames, each losing its fraction, and the dead zone was
    /// compared with a frame's own distance, half as long there): 179 px instead of 192 at
    /// the owner's settings, and nothing at all for a slow scroll with a long glide.
    func testDistance_isTheSameOnFasterDisplays() {
        for duration in [2.0, 3.13, 3.69, 4.35, 4.6] {
            for pixels in [33.6, 50.4, 90.72, 211.68] {
                let at60 = glide(of: pixels, duration: duration, rate: 60)
                XCTAssertGreaterThan(at60.posted, 0)
                XCTAssertLessThan(at60.posted, pixels)
                for rate in [120.0, 144.0] {
                    let label = "Duration \(duration), \(pixels) px at \(Int(rate)) Hz"
                    let faster = glide(of: pixels, duration: duration, rate: rate)
                    XCTAssertEqual(faster.posted, at60.posted, accuracy: 1, label)
                    XCTAssertTrue(faster.rig.moving.allSatisfy { $0.frame.y == $0.frame.y.rounded() && $0.frame.y >= 1 }, "\(label): whole pixels")
                    assertGlidesOut(faster.rig, label)
                }
            }
        }
    }

    /// Float (Duration 4.6) at Speed 1: every frame of a 120 Hz display is under a pixel. It
    /// used to post nothing: the wheel event was swallowed and the page did not move.
    func testSlowScrollWithALongGlide_stillMovesOnAFastDisplay() {
        for rate in [120.0, 144.0] {
            let result = glide(of: 33.6, duration: 4.6, rate: rate)
            XCTAssertEqual(result.posted, 14, accuracy: 1, "\(Int(rate)) Hz")
            XCTAssertEqual(result.rig.stops.count, 1, "\(Int(rate)) Hz")
        }
    }

    // MARK: Phases

    // "Trackpad-style events": a wheel scroll goes out as a trackpad flick, a short touch and then
    // its glide. A real flick from the owner's trackpad: began, three "changed" over ~50 ms,
    // ended, then momentum events every frame. Apps treat the two parts differently at a page
    // edge: a touch drags the page past the edge for as long as it lasts, a glide that reaches
    // the edge bounces at once, sized by its speed, and the rest of it is ignored. The touch used
    // to last until the wheel had been still for 0.18 s: a fast scroll into an edge dragged the
    // page most of a screen past it (measured in the owner's recording: up to ~1,400 pt, held
    // while the wheel turned) instead of a bounce of 30 to 170 pt.

    /// One click at the owner's settings (Step 33.6 × Speed 6.3, Duration 3.69), frame by frame.
    /// Before: began, ten "changed" frames (145 of the 205 px), ended at 183 ms, then the glide.
    func testTrackpadStyle_oneClick_isAShortTouchAndThenItsGlide() {
        let rig = ScrollClassicRig(duration: 3.69, trackpadStyle: true)
        rig.input(33.6 * 6.3, notch: 33.6 * 6.3, at: 0)
        rig.run(until: 2)

        XCTAssertEqual(rig.stream, [
            "began 0", "changed 7", "changed 13", "ended 0",
            "momentumBegan 15", "momentumChanged 16", "momentumChanged 16", "momentumChanged 16",
            "momentumChanged 15", "momentumChanged 14", "momentumChanged 12", "momentumChanged 11",
            "momentumChanged 10", "momentumChanged 9", "momentumChanged 8", "momentumChanged 7",
            "momentumChanged 6", "momentumChanged 5", "momentumChanged 5", "momentumChanged 4",
            "momentumChanged 3", "momentumChanged 3", "momentumChanged 2", "momentumChanged 2",
            "momentumChanged 2", "momentumChanged 2", "momentumChanged 1", "momentumChanged 1",
            "momentumEnded 0",
        ])
        // The touch lifts 50 ms after it began, the glide's first frame comes with it.
        XCTAssertEqual(rig.firstTime(of: "ended") ?? -1, 0.05, accuracy: 1e-6)
        XCTAssertEqual(rig.firstTime(of: "momentumBegan") ?? -1, 0.05, accuracy: 1e-6)
        XCTAssertEqual(rig.stops.map(\.phase), [.MomentumEnd])
    }

    /// The owner's quick turn (the system's deltas of 1, 12, 54 and 78 pt within 60 ms): the same
    /// short touch; the ticks after it add to the glide instead of touching again.
    func testTrackpadStyle_quickBurst_isOneTouchAndOneGlide() {
        let rig = ScrollClassicRig(duration: 3.69, trackpadStyle: true)
        for (points, time) in [(1.0, 0.0), (12, 0.024), (54, 0.038), (78, 0.060)] {
            rig.input(max(33.6, points) * 6.3, notch: 33.6 * 6.3, at: time)
        }
        rig.run(until: 3)

        XCTAssertEqual(rig.phaseRuns, [
            "began ×1", "changed ×2", "ended ×1", "momentumBegan ×1", "momentumChanged ×36", "momentumEnded ×1",
        ])
        XCTAssertEqual(Array(rig.stream.prefix(5)), ["began 0", "changed 7", "changed 20", "ended 0", "momentumBegan 40"])
    }

    /// A long spin (27 ticks in 400 ms, up to 690 px a frame): the touch is over after 50 ms and
    /// everything after it, while the wheel still turns, is glide. At an edge it bounces once.
    func testTrackpadStyle_longSpin_isGlideAfterTheFirstFiftyMilliseconds() {
        let rig = ScrollClassicRig(duration: 3.69, trackpadStyle: true)
        for (pixels, time) in Self.spin { rig.input(pixels, notch: 33.6 * 6.3, at: time) }
        rig.run(until: 4)

        XCTAssertEqual(rig.phaseRuns, [
            "began ×1", "changed ×2", "ended ×1", "momentumBegan ×1", "momentumChanged ×64", "momentumEnded ×1",
        ])
        XCTAssertGreaterThan(rig.moving.map { $0.frame.y }.max() ?? 0, 600, "the fast part of the spin is glide")
    }

    /// The wheel keeps turning (a click every 120 ms for 1.3 s), as against an edge: one touch,
    /// then one glide that the clicks keep going. No second "began" reaches a page that bounces.
    func testTrackpadStyle_wheelKeepsTurning_staysOneGlide() {
        let rig = ScrollClassicRig(duration: 3.69, trackpadStyle: true)
        for index in 0..<12 { rig.input(33.6 * 6.3, notch: 33.6 * 6.3, at: Double(index) * 0.12) }
        rig.run(until: 4)

        XCTAssertEqual(rig.phaseRuns, [
            "began ×1", "changed ×2", "ended ×1", "momentumBegan ×1", "momentumChanged ×104", "momentumEnded ×1",
        ])
        XCTAssertEqual(rig.stops.count, 1)
    }

    /// Turning back during the glide starts a new touch, but only with the first frame that moves
    /// the new way: the frames before it still go the old way (toward the edge, the filter turns the
    /// speed around over a few frames) and stay glide, which a bouncing page ignores.
    func testTrackpadStyle_turnBack_startsTheNewTouchWhenTheMotionTurns() {
        let rig = ScrollClassicRig(duration: 3.69, trackpadStyle: true)
        for (points, time) in [(1.0, 0.0), (12, 0.024), (54, 0.038), (78, 0.060)] {
            rig.input(max(33.6, points) * 6.3, notch: 33.6 * 6.3, at: time)
        }
        rig.input(-33.6 * 6.3, notch: 33.6 * 6.3, at: 0.3)
        rig.run(until: 3)

        XCTAssertEqual(rig.phaseRuns, [
            "began ×1", "changed ×2", "ended ×1", "momentumBegan ×1", "momentumChanged ×17", "momentumEnded ×1",
            "began ×1", "changed ×3", "ended ×1", "momentumBegan ×1", "momentumChanged ×20", "momentumEnded ×1",
        ])
        let secondTouch = rig.recorded.lastIndex { $0.frame.scrollPhase == 1 } ?? 0
        let before = rig.recorded[..<secondTouch].filter { $0.frame.y != 0 }
        let after = rig.recorded[secondTouch...].filter { $0.frame.y != 0 }
        XCTAssertTrue(before.allSatisfy { $0.frame.y > 0 }, "the old way until the new touch")
        XCTAssertTrue(after.allSatisfy { $0.frame.y < 0 }, "the new touch and its glide go the new way")
        XCTAssertGreaterThan(rig.recorded[secondTouch].time - rig.start, 0.3 + 1e-6,
                             "the new touch begins after the tick, when the motion has turned")
    }

    /// A tick back and at once forward again (the wheel settles on a detent): the motion never
    /// turns, so no touch begins. It used to begin with the next frame, which still moved toward
    /// the edge: a "began" for a page that may be bouncing there.
    func testTrackpadStyle_turnBackTakenBack_staysOneGlide() {
        let rig = ScrollClassicRig(duration: 3.69, trackpadStyle: true)
        for (points, time) in [(1.0, 0.0), (12, 0.024), (54, 0.038), (78, 0.060)] {
            rig.input(max(33.6, points) * 6.3, notch: 33.6 * 6.3, at: time)
        }
        rig.input(-33.6 * 6.3, notch: 33.6 * 6.3, at: 0.300)
        rig.input(33.6 * 6.3, notch: 33.6 * 6.3, at: 0.310)
        rig.run(until: 3)

        XCTAssertEqual(rig.phaseSequence, ["began", "changed", "ended", "momentumBegan", "momentumChanged", "momentumEnded"])
        XCTAssertTrue(rig.moving.allSatisfy { $0.frame.y > 0 }, "the page never moved back")
        XCTAssertEqual(rig.sessions.last?.touches, 1)
    }

    /// The glide goes on only where its touch began. Apps keep a gesture on the scroller that got
    /// its "began": a tick over another pane, or for another app, begins a touch of its own at
    /// once. The hand that turns the wheel may move the pointer a little.
    func testTrackpadStyle_tickSomewhereElse_beginsItsOwnTouch() {
        let here = ScrollInputPlace(pid: 100, pointer: CGPoint(x: 400, y: 300))
        let cases: [(String, ScrollInputPlace, Bool)] = [
            ("the hand moved the pointer a little", ScrollInputPlace(pid: 100, pointer: CGPoint(x: 406, y: 296)), false),
            ("another pane", ScrollInputPlace(pid: 100, pointer: CGPoint(x: 400, y: 380)), true),
            ("another app under the pointer", ScrollInputPlace(pid: 200, pointer: CGPoint(x: 400, y: 300)), true),
        ]
        let flick = ["began", "changed", "ended", "momentumBegan", "momentumChanged", "momentumEnded"]
        for (name, there, beginsATouch) in cases {
            let rig = ScrollClassicRig(duration: 3.69, trackpadStyle: true)
            rig.input(33.6 * 6.3, notch: 33.6 * 6.3, at: 0, place: here)
            rig.input(33.6 * 6.3, notch: 33.6 * 6.3, at: 0.2, place: there)
            rig.run(until: 3)

            XCTAssertEqual(rig.phaseSequence, beginsATouch ? flick + flick : flick, name)
            XCTAssertEqual(rig.sessions.last?.touches, beginsATouch ? 2 : 1, name)
            XCTAssertEqual(rig.sessions.last?.glideInputs, beginsATouch ? 0 : 1, name)
            if beginsATouch {
                let second = rig.recorded.last { $0.frame.scrollPhase == 1 }
                XCTAssertEqual((second?.time ?? 0) - rig.start, 0.2, accuracy: 1e-6, "\(name): with the tick itself")
            }
        }
    }

    /// The switch can differ per app. A scroll that began in an app with it off goes on in an
    /// app with it on as a touch of its own: that app got no "began" for the glide.
    func testTrackpadStyle_afterAScrollWithTheSwitchOff_beginsATouch() {
        let rig = ScrollClassicRig(duration: 3.69, trackpadStyle: false)
        rig.input(33.6 * 6.3, notch: 33.6 * 6.3, at: 0)
        rig.run(until: 0.25)
        XCTAssertEqual(rig.phases.phase, .MomentumOngoing, "the phase machine runs with the switch off too")
        rig.poster.setConfigForTests(simTrackpadEnabled: true)
        rig.input(33.6 * 6.3, notch: 33.6 * 6.3, at: 0.25, place: ScrollInputPlace(pid: 100, pointer: .zero))
        rig.run(until: 3)

        XCTAssertEqual(Array(rig.phaseSequence.prefix(3)), ["momentumEnded", "began", "changed"])
    }

    /// And the other way: a turn asked for with the switch on is not carried into a scroll with
    /// it off. It used to begin a "touch" there with the next frame: two frames without distance
    /// that the switch-off path does not post.
    func testSwitchOffInTheNextApp_carriesNoTurnOver() {
        let rig = ScrollClassicRig(duration: 3.69, trackpadStyle: true)
        for (points, time) in [(1.0, 0.0), (12, 0.024), (54, 0.038), (78, 0.060)] {
            rig.input(max(33.6, points) * 6.3, notch: 33.6 * 6.3, at: time)
        }
        rig.input(-33.6 * 6.3, notch: 33.6 * 6.3, at: 0.300)
        rig.poster.setConfigForTests(simTrackpadEnabled: false)
        rig.input(33.6 * 6.3, notch: 33.6 * 6.3, at: 0.310)
        rig.run(until: 3)

        // From the tick until the wheel counts as still (0.18 s later) only frames that move the page.
        let afterTheTick = rig.recorded.filter { $0.time - rig.start > 0.310 + 1e-6 && $0.time - rig.start < 0.45 }
        XCTAssertFalse(afterTheTick.isEmpty)
        XCTAssertTrue(afterTheTick.allSatisfy { $0.frame.y != 0 }, "no frame without distance")
        XCTAssertTrue(afterTheTick.allSatisfy { $0.frame.scrollPhase == nil }, "and no phases")
    }

    /// The phases an app gets always make whole gestures, at any Duration, Speed, dead zone and
    /// display rate: "began, changed…, ended", then "momentum began, momentum changed…, momentum
    /// ended" or nothing. A glide whose first frame comes to no whole pixel posts nothing; its
    /// "momentum began" waits for the frame that is posted. It used to be skipped: the app got
    /// "momentum changed" alone and took the glide for a finger that drags the page past the edge.
    /// And a touch that leaves no glide ends after its last frame (frames after "ended" carried
    /// "ended" again, with a distance); a glide of which no frame went out sends nothing at all.
    func testTrackpadStyle_phasesAlwaysMakeWholeGestures() {
        let allowed: [String: Set<String>] = [
            "": ["began"],
            "began": ["changed", "ended"],
            "changed": ["changed", "ended"],
            "ended": ["momentumBegan", "began"],
            "momentumBegan": ["momentumChanged", "momentumEnded"],
            "momentumChanged": ["momentumChanged", "momentumEnded"],
            "momentumEnded": ["began"],
        ]
        // (notches, seconds)
        var spin: [(Double, Double)] = []
        for index in 0..<27 { spin.append((1 + Double(index) * 0.1, Double(index) * 0.015)) }
        var keepsTurning: [(Double, Double)] = []
        for index in 0..<12 { keepsTurning.append((1, Double(index) * 0.12)) }
        let burst: [(Double, Double)] = [(1, 0), (1, 0.024), (1.6, 0.038), (2.3, 0.060)]
        let scenarios: [(String, [(Double, Double)])] = [
            ("click", [(1, 0)]),
            ("burst", burst),
            ("spin", spin),
            ("keeps turning", keepsTurning),
            ("turn back in the glide", burst + [(-1, 0.3)]),
            ("turn back in the touch", [(1, 0), (-1, 0.030)]),
            ("wobble", [(1, 0), (-1, 0.3), (1, 0.31), (-1, 0.32)]),
            ("two clicks", [(1, 0), (1, 0.5)]),
        ]
        var failures: [String] = []
        for duration in [1.0, 2.0, 3.13, 3.69, 5.0] {
            for rate in [60.0, 120.0, 144.0] {
                for speed in [1.0, 6.3] {
                    for deadZone in [1.0, 3.0] {
                        for (name, inputs) in scenarios {
                            let rig = ScrollClassicRig(duration: duration, rate: rate, trackpadStyle: true, deadZone: deadZone)
                            let notch = 33.6 * speed
                            for (notches, time) in inputs { rig.input(notches * notch, notch: notch, at: time) }
                            rig.run(until: 30)  // Duration 5 glides for many seconds

                            var last = ""
                            var broken: String?
                            for item in rig.recorded {
                                let phase = ScrollClassicRig.phaseName(scroll: item.frame.scrollPhase ?? -1, momentum: item.frame.momentumPhase ?? -1)
                                if allowed[last]?.contains(phase) != true {
                                    broken = "\"\(phase)\" after \"\(last)\" at \(Int(((item.time - rig.start) * 1000).rounded())) ms"
                                    break
                                }
                                last = phase
                            }
                            if broken == nil && last != "ended" && last != "momentumEnded" {
                                broken = "ends with \"\(last)\""
                            }
                            if let broken = broken {
                                failures.append("\(name), Duration \(duration), \(Int(rate)) Hz, Speed \(speed), dead zone \(deadZone): \(broken)")
                            }
                        }
                    }
                }
            }
        }
        XCTAssertTrue(failures.isEmpty, "\(failures.count) broken:\n" + failures.prefix(40).joined(separator: "\n"))
    }

    // MARK: Trackpad-style, as one long touch
    //
    // AppKit and UIKit scroll views (Finder, Settings, most apps) follow the touch only. When it
    // ends they compute a glide of their own from its speed and ignore what the momentum events
    // say: in the owner's recording a Finder list moved ~250 pt for 7,225 px posted as a flick.
    // Only an app that scrolls by a glide's events (Chromium) gets the flick; for every other app
    // the touch lasts as long as the wheel turns, the stream trackpad-style events always had.

    /// The touch ends when the wheel has been still for 0.18 s; a tick after that begins a new
    /// one at once. Every frame keeps the wheel event's own time.
    func testTrackpadStyleLongTouch_touchLastsWhileTheWheelTurns() {
        let rig = ScrollClassicRig(duration: 4.35, trackpadStyle: true, flick: false)
        for index in 0..<3 { rig.wheel(10, at: Double(index) * 0.05) }
        // A second scroll while the first still glides.
        rig.wheel(10, at: 0.7)
        rig.run(until: 4)

        XCTAssertEqual(rig.phaseSequence, [
            "began", "changed", "ended", "momentumBegan", "momentumChanged", "momentumEnded",
            "began", "changed", "ended", "momentumBegan", "momentumChanged", "momentumEnded",
        ])
        let ended = rig.recorded.filter { $0.frame.scrollPhase == 4 }.map { $0.time - rig.start }
        XCTAssertEqual(ended.count, 2)
        XCTAssertEqual(ended.first ?? 0, 0.1 + 0.18, accuracy: 1.5 / 60.0)
        XCTAssertEqual(ended.last ?? 0, 0.7 + 0.18, accuracy: 1.5 / 60.0)
        let secondBegan = rig.recorded.last { $0.frame.scrollPhase == 1 }
        XCTAssertEqual((secondBegan?.time ?? 0) - rig.start, 0.7, accuracy: 1e-6, "with the tick itself")
        XCTAssertTrue(rig.recorded.allSatisfy { $0.frame.scrollPhase != nil }, "every frame carries its phase")
        XCTAssertTrue(rig.recorded.allSatisfy { $0.frame.timestamp == nil }, "and the wheel event's own time")
        XCTAssertEqual(rig.stops.count, 1)
    }

    /// What an AppKit list follows is the touch. As a long touch nearly all of a scroll is touch;
    /// as a flick almost none of it is, which is why such a list stopped short.
    func testTrackpadStyleLongTouch_carriesTheScrollInTheTouch() {
        let scenarios: [(String, [(Double, Double)], Double)] = [
            ("click", [(211.68, 0)], 0.65),
            ("spin", Self.spin, 0.85),
        ]
        for (name, inputs, share) in scenarios {
            let longTouch = ScrollClassicRig(duration: 3.69, trackpadStyle: true, flick: false)
            let flick = ScrollClassicRig(duration: 3.69, trackpadStyle: true, flick: true)
            for rig in [longTouch, flick] {
                for (pixels, time) in inputs { rig.input(pixels, notch: 211.68, at: time) }
                rig.run(until: 4)
            }
            func touchShare(_ rig: ScrollClassicRig) -> Double {
                return rig.recorded.filter { $0.frame.scrollPhase == 2 }.reduce(0) { $0 + $1.frame.y } / rig.postedY
            }
            XCTAssertGreaterThan(touchShare(longTouch), share, name)
            XCTAssertLessThan(touchShare(flick), 0.15, name)
            XCTAssertEqual(longTouch.moving.map { $0.frame.y }, flick.moving.map { $0.frame.y }, "\(name): the motion is the same")
        }
    }

    /// A click after the glide has ended is a new flick.
    func testTrackpadStyle_clickAfterTheGlide_isANewFlick() {
        let rig = ScrollClassicRig(duration: 3.69, trackpadStyle: true)
        rig.input(33.6 * 6.3, notch: 33.6 * 6.3, at: 0)
        rig.input(33.6 * 6.3, notch: 33.6 * 6.3, at: 1.2)
        rig.run(until: 3)

        let flick = ["began ×1", "changed ×2", "ended ×1", "momentumBegan ×1", "momentumChanged ×23", "momentumEnded ×1"]
        XCTAssertEqual(rig.phaseRuns, flick + flick)
        XCTAssertEqual(rig.stops.count, 2)
    }

    /// Several clicks while the glide runs (the second batch 0.7 s later) keep one glide going.
    func testTrackpadStyle_postsTheTrackpadPhaseSequence() {
        let rig = ScrollClassicRig(duration: 4.35, trackpadStyle: true)
        for index in 0..<3 { rig.wheel(10, at: Double(index) * 0.05) }
        rig.wheel(10, at: 0.7)
        rig.run(until: 4)

        XCTAssertEqual(rig.phaseSequence, ["began", "changed", "ended", "momentumBegan", "momentumChanged", "momentumEnded"])
        XCTAssertEqual(rig.firstTime(of: "ended") ?? -1, 0.05, accuracy: 1e-6)
        XCTAssertTrue(rig.recorded.allSatisfy { $0.frame.scrollPhase != nil }, "every frame carries its phase")
        XCTAssertEqual(rig.stops.count, 1)
    }

    /// Every frame carries its own time. Apps take a glide's speed from the time between its
    /// events and size the bounce with it; every frame of a wheel tick used to carry that tick's
    /// time, so the glide had no speed (or a wild one when the next tick's time came in).
    func testTrackpadStyle_framesCarryTheirOwnTime() throws {
        let rig = ScrollClassicRig(duration: 3.69, trackpadStyle: true)
        for (points, time) in [(1.0, 0.0), (12, 0.024), (54, 0.038), (78, 0.060)] {
            rig.input(max(33.6, points) * 6.3, notch: 33.6 * 6.3, at: time)
        }
        rig.run(until: 3)

        for item in rig.recorded {
            let timestamp = try XCTUnwrap(item.frame.timestamp)
            XCTAssertEqual(Double(timestamp) / 1e9, item.time, accuracy: 1e-6)
        }
        let glide = rig.moving.filter { $0.frame.momentumPhase == 2 }.compactMap { $0.frame.timestamp }
        for (later, earlier) in zip(glide.dropFirst(), glide) {
            XCTAssertEqual(Double(later - earlier) / 1e9, 1.0 / 60.0, accuracy: 1e-6)
        }

        let plain = ScrollClassicRig(duration: 3.69, trackpadStyle: false)
        plain.input(33.6 * 6.3, at: 0)
        plain.run(until: 2)
        XCTAssertTrue(plain.recorded.allSatisfy { $0.frame.timestamp == nil }, "off: the wheel event's own timestamp stays")
    }

    /// A finger on the trackpad stops the wheel's glide (ScrollHandover): the glide ends with
    /// "momentum ended" and nothing follows it.
    func testTrackpadStyle_fingerTakesOver_endsTheGlide() {
        let rig = ScrollClassicRig(duration: 3.69, trackpadStyle: true)
        rig.input(33.6 * 6.3 * 3, notch: 33.6 * 6.3, at: 0)
        rig.run(until: 0.2)
        XCTAssertEqual(rig.phases.phase, .MomentumOngoing)
        XCTAssertTrue(ScrollCore.stopWheelGlide(forTrackpadScrollPhase: 1, poster: rig.poster))
        let atTheTouch = rig.recorded.count
        XCTAssertEqual(rig.stream.last, "momentumEnded 0")
        rig.run(until: 2)
        XCTAssertEqual(rig.recorded.count, atTheTouch, "nothing more is posted")
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

    /// A free spin of the owner's wheel: 27 events in 400 ms, the system's delta growing from 10 to
    /// 110 pt, at Step 33.6 × Speed 6.3 (px, seconds).
    static let spin: [(Double, Double)] = {
        var inputs: [(Double, Double)] = []
        for index in 0..<27 {
            let points = Double(min(110, 10 + index * 8))
            inputs.append((max(33.6, points) * 6.3, Double(index) * 0.015))
        }
        return inputs
    }()
    /// A click every 120 ms for 1.3 s.
    static let keepsTurning: [(Double, Double)] = {
        var inputs: [(Double, Double)] = []
        for index in 0..<12 { inputs.append((211.68, Double(index) * 0.12)) }
        return inputs
    }()

    /// The touch-and-glide split changes the phases only: in every scenario each frame that moves
    /// the page goes out at the same time with the same delta as without trackpad-style events.
    /// At the owner's Duration (3.69) and dead zone (1). A scroll with the switch on ends when its
    /// glide has run out; with it off, 0.22 s after the last tick at the earliest. At a short
    /// Duration or a larger dead zone the two can lie up to ~0.1 s apart, and a tick in that gap
    /// goes on with one scroll and starts the other anew (a pixel a frame of difference).
    func testTrackpadStyle_keepsEveryFrameOfTheMotion() {
        let scenarios: [(String, [(Double, Double)])] = [
            ("click", [(211.68, 0)]),
            ("burst", [(211.68, 0), (211.68, 0.024), (340.2, 0.038), (491.4, 0.060)]),
            ("spin", Self.spin),
            ("turn back", [(211.68, 0), (211.68, 0.024), (340.2, 0.038), (-211.68, 0.3)]),
            ("keeps turning", Self.keepsTurning),
            ("two flicks", [(211.68, 0), (211.68, 1.2)]),
        ]
        for (name, inputs) in scenarios {
            for rate in [60.0, 120.0] {
                let plain = ScrollClassicRig(duration: 3.69, rate: rate, trackpadStyle: false)
                let phased = ScrollClassicRig(duration: 3.69, rate: rate, trackpadStyle: true)
                for rig in [plain, phased] {
                    for (pixels, time) in inputs { rig.input(pixels, notch: 211.68, at: time) }
                    rig.run(until: 4)
                }
                let label = "\(name) at \(Int(rate)) Hz"
                XCTAssertEqual(plain.moving.map { $0.time }, phased.moving.map { $0.time }, label)
                XCTAssertEqual(plain.moving.map { $0.frame.y }, phased.moving.map { $0.frame.y }, label)
                XCTAssertEqual(plain.stops.map(\.time), phased.stops.map(\.time), label)
            }
        }
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
        XCTAssertEqual(phased.timestamp, 1_234)

        // A frame's own time: nanoseconds, which AppKit gives as seconds of uptime.
        let timed = try XCTUnwrap(template.copy())
        let now = ScrollEventClock.uptimeNanoseconds()
        ScrollOutgoingFrame(y: 4, x: 0, scrollPhase: 0, momentumPhase: 2, timestamp: now).write(to: timed)
        XCTAssertEqual(timed.timestamp, now)
        let nsEvent = try XCTUnwrap(NSEvent(cgEvent: timed))
        XCTAssertEqual(nsEvent.timestamp, Double(now) / 1e9, accuracy: 1e-6)
        XCTAssertEqual(nsEvent.timestamp, ProcessInfo.processInfo.systemUptime, accuracy: 1.0)
        XCTAssertEqual(nsEvent.momentumPhase, .changed)
    }
}

// MARK: - An AppKit scroll view at its top edge

/// The posted frames fed to a real `NSScrollView` at the top of its page, in a window that is
/// never shown, and where its page sits at each moment.
///
/// What this can and cannot show: AppKit's concurrent ("responsive") scrolling needs a visible
/// window, so the page view opts out of it. On the classic path a touch ("began", "changed",
/// "ended") stretches the page past the edge and lets it spring back exactly as an app does, but
/// momentum events are not animated in a window that is not on screen: the glide's bounce is not
/// seen here. So this checks the part that went wrong for a fast scroll: how far the touch drags
/// the page past the edge.
final class ScrollTrackpadStyleScrollViewTests: XCTestCase {

    private final class Page: NSView {
        override var isFlipped: Bool { true }
        override class var isCompatibleWithResponsiveScrolling: Bool { false }
    }

    private struct Fed {
        let time: Double
        let y: Double
        let scrollPhase: Double
        let momentumPhase: Double
    }

    /// Feeds the events at their times (seconds after the start) and returns the top of the visible
    /// rect every few milliseconds (negative: stretched past the top) until `total`, each with the
    /// time it was read at.
    private func positions(feeding events: [Fed], total: Double) throws -> [(time: Double, y: Double)] {
        // Inside the main screen's frame, so that the scroll view has a screen, but never ordered in.
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1000, height: 1000)
        let window = NSWindow(contentRect: NSRect(x: screen.minX + 10, y: screen.minY + 10, width: 400, height: 600),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
        scrollView.verticalScrollElasticity = .allowed
        scrollView.documentView = Page(frame: NSRect(x: 0, y: 0, width: 400, height: 6000))
        window.contentView = scrollView
        XCTAssertFalse(window.isVisible)

        let start = ScrollEventClock.uptimeNanoseconds()
        var nsEvents: [NSEvent] = []
        for event in events {
            let cgEvent = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 0, wheel2: 0, wheel3: 0))
            ScrollOutgoingFrame(y: event.y, x: 0, scrollPhase: event.scrollPhase, momentumPhase: event.momentumPhase,
                                timestamp: start + UInt64(event.time * 1e9)).write(to: cgEvent)
            nsEvents.append(try XCTUnwrap(NSEvent(cgEvent: cgEvent)))
        }
        var samples: [(time: Double, y: Double)] = []
        var next = 0
        let begin = CACurrentMediaTime()
        let feeder = Timer(timeInterval: 0.002, repeats: true) { _ in
            let now = CACurrentMediaTime() - begin
            while next < nsEvents.count && events[next].time <= now {
                scrollView.scrollWheel(with: nsEvents[next])
                next += 1
            }
            samples.append((now, scrollView.contentView.bounds.origin.y))
        }
        RunLoop.main.add(feeder, forMode: .common)
        while CACurrentMediaTime() - begin < total {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        feeder.invalidate()
        XCTAssertEqual(next, events.count, "every event was fed")
        return samples
    }

    private func fed(_ rig: ScrollClassicRig) -> [Fed] {
        return rig.recorded.map {
            Fed(time: $0.time - rig.start, y: $0.frame.y, scrollPhase: $0.frame.scrollPhase ?? 0, momentumPhase: $0.frame.momentumPhase ?? 0)
        }
    }

    /// A fast spin of the wheel with the page at its top. As one touch for as long as the wheel
    /// turned (what was posted before), it drags the page more than half the view past the edge
    /// (measured 356 px of 600); as a short touch and a glide it stretches it a few pixels, and the
    /// page comes back to the edge without a jump.
    func testFastSpinAtTheTop_stretchesThePageLittleAndItComesBackSmoothly() throws {
        let rig = ScrollClassicRig(duration: 3.69, trackpadStyle: true)
        for (pixels, time) in ScrollClassicPathTests.spin { rig.input(pixels, notch: 33.6 * 6.3, at: time) }
        rig.run(until: 2)
        let flick = fed(rig)
        // The same frames as one long touch, as before: "began", then every moving frame "changed"
        // until 0.18 s after the last tick, then "ended" (the glide's tail as momentum).
        let lastTick = ScrollClassicPathTests.spin.last?.1 ?? 0
        var longTouch: [Fed] = []
        var ended = false
        for item in flick where !(item.y == 0 && item.scrollPhase == 4) {
            if item.scrollPhase == 1 { longTouch.append(item); continue }
            if item.time <= lastTick + 0.18 && item.momentumPhase != 3 {
                longTouch.append(Fed(time: item.time, y: item.y, scrollPhase: 2, momentumPhase: 0))
            } else {
                if !ended {
                    longTouch.append(Fed(time: item.time, y: 0, scrollPhase: 4, momentumPhase: 0))
                    longTouch.append(Fed(time: item.time, y: item.y, scrollPhase: 0, momentumPhase: 1))
                    ended = true
                    continue
                }
                longTouch.append(item)
            }
        }

        let before = try positions(feeding: longTouch, total: 1.6)
        let after = try positions(feeding: flick, total: 1.6)

        let stretchBefore = -(before.map(\.y).min() ?? 0)
        let stretchAfter = -(after.map(\.y).min() ?? 0)
        XCTAssertGreaterThan(stretchBefore, 150, "one long touch drags the page far past the edge")
        XCTAssertLessThan(stretchAfter, 20, "the short touch stretches it a little")
        XCTAssertGreaterThan(stretchAfter, 0, "and it does stretch")
        // Back at the edge, monotonically from the deepest point, in small steps. The steps are
        // judged between samples read in a row only: on a busy machine the run loop stalls, and
        // the page is then rightly farther along at the next sample.
        let deepest = after.firstIndex { $0.y == -stretchAfter } ?? 0
        for index in (deepest + 1)..<after.count {
            XCTAssertGreaterThanOrEqual(after[index].y, after[index - 1].y - 0.5, "sample \(index): only back toward the edge")
            if after[index].time - after[index - 1].time < 0.008 {
                XCTAssertLessThanOrEqual(after[index].y - after[index - 1].y, 10, "sample \(index): no jump")
            }
        }
        XCTAssertEqual(after.last?.y ?? -1, 0, accuracy: 0.5, "at rest at the edge")
    }
}

// MARK: - Which apps get a flick

/// "Trackpad-style events" go out as a flick only for an app that scrolls by a glide's events:
/// the Chromium engine, found by the resources it carries in one of the app's frameworks.
final class ScrollGlideFollowerTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("scrollio-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// An app bundle with the given (empty) files.
    private func app(_ name: String, files: [String]) throws -> URL {
        let bundle = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        for file in files {
            let url = bundle.appendingPathComponent(file)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url)
        }
        return bundle
    }

    func testChromiumBasedApps_areFoundByTheEnginesResources() throws {
        // Electron and CEF apps, Dia and Arc: the framework's Resources.
        let electron = try app("Editor.app", files: ["Contents/Frameworks/Electron Framework.framework/Resources/resources.pak"])
        // Chrome keeps them under a version folder that "Current" points to.
        let chrome = try app("Browser.app", files: ["Contents/Frameworks/Browser Framework.framework/Versions/141.0.1/Resources/resources.pak"])
        try FileManager.default.createSymbolicLink(
            atPath: chrome.appendingPathComponent("Contents/Frameworks/Browser Framework.framework/Versions/Current").path,
            withDestinationPath: "141.0.1"
        )
        XCTAssertTrue(ScrollUtils.isChromiumBased(bundleURL: electron))
        XCTAssertTrue(ScrollUtils.isChromiumBased(bundleURL: chrome))
    }

    func testOtherApps_areNotTakenForChromium() throws {
        let plain = try app("Plain.app", files: ["Contents/MacOS/Plain"])
        let native = try app("Native.app", files: [
            "Contents/Frameworks/Sparkle.framework/Resources/Info.plist",
            "Contents/Frameworks/libswiftCore.dylib",
            "Contents/Resources/resources.pak",
        ])
        XCTAssertFalse(ScrollUtils.isChromiumBased(bundleURL: plain))
        XCTAssertFalse(ScrollUtils.isChromiumBased(bundleURL: native))
        XCTAssertFalse(ScrollUtils.isChromiumBased(bundleURL: root.appendingPathComponent("Missing.app")))
        // The Finder is AppKit: its lists follow the touch only.
        XCTAssertFalse(ScrollUtils.isChromiumBased(bundleURL: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")))
    }

    /// Three kinds of apps: Safari gets no trackpad-style events at all (with them it does not
    /// scroll smoothly), a Chromium-based app the flick, everything else the long touch.
    func testTheFormFollowsTheApp() throws {
        let electron = try app("Editor.app", files: ["Contents/Frameworks/Electron Framework.framework/Resources/resources.pak"])
        let plain = try app("Plain.app", files: ["Contents/MacOS/Plain"])
        XCTAssertEqual(ScrollUtils.trackpadStyleTarget(bundleIdentifier: "com.apple.Safari", bundleURL: plain), .plainScrolling)
        XCTAssertEqual(ScrollUtils.trackpadStyleTarget(bundleIdentifier: "com.apple.SafariTechnologyPreview", bundleURL: plain), .plainScrolling)
        XCTAssertEqual(ScrollUtils.trackpadStyleTarget(bundleIdentifier: "com.example.editor", bundleURL: electron), .followsGlide)
        XCTAssertEqual(ScrollUtils.trackpadStyleTarget(bundleIdentifier: "com.apple.finder", bundleURL: plain), .touchOnly)
        XCTAssertEqual(ScrollUtils.trackpadStyleTarget(bundleIdentifier: nil, bundleURL: plain), .touchOnly)
        XCTAssertEqual(ScrollUtils.trackpadStyleTarget(bundleIdentifier: "org.mozilla.firefox", bundleURL: plain), .touchOnly, "not checked on screen")
    }

    /// What the switch comes to for each kind of app. Safari: no phases, exactly as with the
    /// switch off, which is the one way it is known to scroll as it should.
    func testTheSwitchAndTheApp_decideTheForm() {
        func form(_ switchOn: Bool, _ target: ScrollUtils.TrackpadStyleTarget?) -> [Bool] {
            let form = ScrollPoster.trackpadStyleForm(switchOn: switchOn, target: target)
            return [form.phases, form.flick, form.withheld]
        }
        //                                          phases flick  withheld
        XCTAssertEqual(form(true, .plainScrolling), [false, false, true], "Safari")
        XCTAssertEqual(form(true, .followsGlide), [true, true, false], "Chromium")
        XCTAssertEqual(form(true, .touchOnly), [true, false, false], "native apps")
        XCTAssertEqual(form(true, nil), [true, false, false], "an app that is not known")
        for target in [ScrollUtils.TrackpadStyleTarget.plainScrolling, .followsGlide, .touchOnly] {
            XCTAssertEqual(form(false, target), [false, false, false], "the switch is off")
        }
    }
}

// MARK: - The system log

/// The diagnostics the owner reads with `log show` (README, "Diagnostics"): they have to say
/// what really happened, and cost nothing per event.
final class ScrollSystemLogTests: XCTestCase {

    /// macOS 27 hides menu item images unless asked: the action menu keeps its symbols.
    func testActionMenuKeepsItsSymbolsVisible() {
        let menu = NSMenu()
        ShortcutManager.buildShortcutMenu(into: menu, target: self, action: #selector(NSObject.copy))
        var withImage = 0
        func check(_ menu: NSMenu) {
            for item in menu.items {
                if item.image != nil {
                    withImage += 1
                    if #available(macOS 27.0, *) {
                        XCTAssertEqual(item.preferredImageVisibility, .visible, item.title)
                    }
                }
                if let submenu = item.submenu { check(submenu) }
            }
        }
        check(menu)
        XCTAssertGreaterThan(withImage, 40, "categories and actions carry symbols")
    }

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

    func testSessionLine_saysWhichFormOfTrackpadStyleWentOut() {
        var session = ScrollSystemLog.Session()
        session.inputs = 6
        session.touches = 1
        session.glideInputs = 4
        XCTAssertTrue(ScrollSystemLog.message(for: session, endedWith: "MomentumEnd").contains("trackpad-style off, ended"))
        session.trackpadStyleWithheld = true
        XCTAssertTrue(ScrollSystemLog.message(for: session, endedWith: "MomentumEnd").contains("trackpad-style off (not sent to this app), ended"))
        session.trackpadStyleWithheld = false
        session.trackpadStyle = true
        XCTAssertTrue(ScrollSystemLog.message(for: session, endedWith: "MomentumEnd").contains("trackpad-style on (long touch: 1 touches), ended"))
        session.flick = true
        XCTAssertTrue(ScrollSystemLog.message(for: session, endedWith: "MomentumEnd")
            .contains("trackpad-style on (flick: 1 touches, 4 wheel events into a glide), ended"))
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

    /// The thumb wheel's line, one per roll: the tuning of its functions is read from it on the
    /// owner's machine, so its wording is part of the contract.
    func testThumbWheelLine_saysWhatTheWheelSentAndWhatRan() {
        var roll = ScrollSystemLog.ThumbWheelRoll(id: 1, settings: ThumbWheelSettings(function: .tabs), at: 10)
        roll.events = 14
        roll.lastEventAt = 10.62
        roll.longestGap = 0.085
        roll.lines = -9
        roll.fixed = -9.4
        roll.largestFixed = 1.25
        roll.points = -212
        roll.largestPoints = 31
        roll.directionChanges = 1
        roll.stepsNext = 3
        roll.stepsPrevious = 1
        roll.travel = 14
        XCTAssertEqual(
            ScrollSystemLog.thumbWheelMessage(for: roll),
            "thumb wheel: 14 events in 620 ms (longest gap 85 ms), lines -9, fixed -9.40 (largest 1.25), points -212 (largest 31), 1 direction change, not continuous, switch tabs x1.00, travel 14.0: 3 steps next, 1 previous"
        )

        var one = ScrollSystemLog.ThumbWheelRoll(id: 2, settings: .default, at: 5)
        one.add(ThumbWheelEvent(lineDelta: 1, fixedDelta: 1, pointDelta: 10, isContinuous: true), at: 5)
        XCTAssertEqual(
            ScrollSystemLog.thumbWheelMessage(for: one),
            "thumb wheel: 1 event in 0 ms (longest gap 0 ms), lines 1, fixed 1.00 (largest 1.00), points 10 (largest 10), 0 direction changes, continuous, scroll sideways x1.00, travel 0.0: 0 steps"
        )

        var swapped = ScrollSystemLog.ThumbWheelRoll(id: 3, settings: ThumbWheelSettings(function: .volume, speed: 1.5, swapsDirection: true), at: 0)
        swapped.add(ThumbWheelEvent(lineDelta: 2, fixedDelta: 2.25, pointDelta: 24, isContinuous: false), travel: -1.5, at: 0)
        swapped.add(ThumbWheelEvent(lineDelta: -1, fixedDelta: -0.5, pointDelta: -31, isContinuous: true), travel: 1.5, at: 0.05)
        swapped.add(ThumbWheelEvent(lineDelta: -1, fixedDelta: -0.5, pointDelta: -9, isContinuous: false), travel: 1.5, at: 0.08)
        swapped.pendingSteps = 2
        swapped.stepsRan(-1)
        XCTAssertEqual(swapped.pendingSteps, 1, "one still to run: not counted")
        XCTAssertEqual(
            ScrollSystemLog.thumbWheelMessage(for: swapped),
            "thumb wheel: 3 events in 80 ms (longest gap 50 ms), lines 0, fixed 1.25 (largest 2.25), points -16 (largest 31), 1 direction change, partly continuous (1 of 3), volume x1.50 swapped, travel 4.5: 1 step previous"
        )
        swapped.stepsRan(2)
        XCTAssertTrue(ScrollSystemLog.thumbWheelMessage(for: swapped).hasSuffix(": 2 steps next, 1 previous"))
        swapped.pendingSteps = 13
        swapped.stepsDropped(12)
        XCTAssertEqual(swapped.pendingSteps, 1)
        XCTAssertTrue(ScrollSystemLog.thumbWheelMessage(for: swapped).hasSuffix("volume x1.50 swapped, travel 4.5: 2 steps next, 1 previous, 12 dropped"),
                      "the steps the pacer dropped, only when there are any")
        XCTAssertEqual(
            ThumbWheelFunction.allCases.map(\.logName),
            ["scroll sideways", "zoom", "switch tabs", "switch desktops", "back and forward", "volume"]
        )
    }
}
