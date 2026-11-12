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
@testable import Scrollio_Debug

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
    /// The process each recorded frame would be posted to (0: none known), frame by frame.
    private(set) var targets: [pid_t] = []
    /// When each stop was asked for (after `start`) and with which phase.
    private(set) var stops: [(time: Double, phase: Phase)] = []
    /// What the system log line of each finished scroll said.
    private(set) var sessions: [ScrollSystemLog.Session] = []

    /// The three forms trackpad-style events go out in.
    enum Form: String, CaseIterable {
        /// A Chromium-based app: a short touch and its glide.
        case flick
        /// Every other app: one touch until the scroll has run out.
        case oneTouch = "one touch"
        /// The same apps with the evaluation switch: a touch while the wheel turns, then a glide.
        case oldLongTouch = "old long touch"
    }

    convenience init(duration: Double = 4.35, rate: Double = 60, deadZone: Double = 1, form: Form) {
        self.init(duration: duration, rate: rate, trackpadStyle: true, deadZone: deadZone,
                  flick: form == .flick, oldLongTouch: form == .oldLongTouch)
    }

    /// `flick`: the app under the pointer scrolls by the events of a glide (Chromium), so
    /// trackpad-style events go out as a short touch and its glide; false: as one touch until
    /// the scroll has run out, or with `oldLongTouch` (the evaluation switch) as the long
    /// touch that ends 0.18 s after the wheel stopped.
    init(duration: Double = 4.35, rate: Double = 60, trackpadStyle: Bool = false, deadZone: Double = 1, flick: Bool = true, oldLongTouch: Bool = false) {
        self.duration = duration
        self.deadZone = deadZone
        frameInterval = 1 / rate
        now = start
        nextFrame = start + frameInterval
        poster = ScrollPoster(phases: phases, dispatchContext: ScrollDispatchContext())
        poster.frameRecorderForTests = { [unowned self] frame in
            self.recorded.append(Recorded(time: self.now, frame: frame))
        }
        poster.targetRecorderForTests = { [unowned self] _, target in
            self.targets.append(target)
        }
        // Frame timestamps on the simulated clock, in nanoseconds.
        poster.eventClockForTests = { [unowned self] in UInt64((self.now * 1e9).rounded()) }
        poster.setConfigForTests(simTrackpadEnabled: trackpadStyle, deadZone: deadZone, flick: flick, oldLongTouch: oldLongTouch)
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
    /// `targetPID`: the process it goes to (a scroll that runs for another one ends first).
    func input(_ pixels: Double, notch: Double? = nil, at time: Double, place: ScrollInputPlace? = nil, targetPID: pid_t? = nil) {
        run(until: time)
        now = start + time
        poster.inputForTests(
            ScrollPosterInput(y: pixels, x: 0, notch: notch ?? self.notch, duration: transition),
            at: start + time,
            place: place,
            targetPID: targetPID
        )
        isRunning = true
    }

    /// One vertical wheel event with a glide time of its own (the feel was changed between
    /// two wheel events).
    func input(_ pixels: Double, notch: Double, at time: Double, duration: Double) {
        run(until: time)
        now = start + time
        poster.inputForTests(
            ScrollPosterInput(y: pixels, x: 0, notch: notch, duration: OPTIONS_SCROLL_DEFAULT.generateDurationTransition(with: duration)),
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

    /// Every frame as "target: phase delta", e.g. "100: began 0", "200: momentumEnded 0".
    var targetedStream: [String] {
        return zip(targets, stream).map { "\($0): \($1)" }
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
        case (128, 0): return "mayBegin"
        case (8, 0): return "cancelled"
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
    /// A Duration longer than Smooth's glides on under a pixel a frame (its dead zone is
    /// smaller, `ScrollMotion.postingDeadZone`): its last pixels come as far apart as that
    /// speed makes them, and no farther.
    private func assertGlidesOut(_ rig: ScrollClassicRig, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let frames = rig.moving.map { $0.frame.y }
        guard let peak = frames.indices.max(by: { abs(frames[$0]) < abs(frames[$1]) }) else {
            return XCTFail("nothing was posted (\(label))", file: file, line: line)
        }
        for index in (peak + 1)..<frames.count {
            XCTAssertLessThanOrEqual(abs(frames[index]), abs(frames[index - 1]) + 1, "\(label): frame \(index) after the peak", file: file, line: line)
        }
        // The slowest frames that are still posted, in pixels per 60 Hz frame.
        let slowest = ScrollMotion.postingDeadZone(rig.deadZone, transition: rig.transition)
        let framesApart = slowest >= 1 ? 1.5 : 1 / slowest + 1.5
        let longestAllowed = framesApart * max(rig.frameInterval, ScrollMotion.referenceFrameInterval)
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
        // (0.52 s while Float's frames stopped at a pixel a frame, 17 px short; they now go
        // on to where Smooth's stop, 6 px short.)
        XCTAssertLessThan(ends[2], 1.0, "and Duration 4.6 is done within a second")
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
        for duration in [2.0, 3.13, 3.69, 4.35, 4.6, 4.9, 5.0] {
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
    /// used to post nothing: the wheel event was swallowed and the page did not move. Then it
    /// moved 14 or 15 of the click's 33.6 px, and at glide time 5.0 still nothing, at any
    /// display rate: the frames stopped at a pixel a frame, with 17 px (52 at 5.0) left to
    /// go. A long glide now goes on to where Smooth's stops: 27 px, as Smooth's 26.
    func testSlowScrollWithALongGlide_stillMovesOnAFastDisplay() {
        for duration in [4.6, 5.0] {
            for rate in [60.0, 120.0, 144.0] {
                let label = "Duration \(duration) at \(Int(rate)) Hz"
                let result = glide(of: 33.6, duration: duration, rate: rate)
                XCTAssertEqual(result.posted, 27, accuracy: 1, label)
                XCTAssertEqual(result.rig.stops.count, 1, label)
                assertGlidesOut(result.rig, label)
            }
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
    /// "Began" is the first frame that moves the page (it was a frame of its own, without
    /// distance, posted with the wheel event), and "ended" goes out right before the glide's
    /// first frame.
    func testTrackpadStyle_oneClick_isAShortTouchAndThenItsGlide() {
        let rig = ScrollClassicRig(duration: 3.69, trackpadStyle: true)
        rig.input(33.6 * 6.3, notch: 33.6 * 6.3, at: 0)
        rig.run(until: 2)

        XCTAssertEqual(rig.stream, [
            "began 7", "changed 13", "ended 0",
            "momentumBegan 15", "momentumChanged 16", "momentumChanged 16", "momentumChanged 16",
            "momentumChanged 15", "momentumChanged 14", "momentumChanged 12", "momentumChanged 11",
            "momentumChanged 10", "momentumChanged 9", "momentumChanged 8", "momentumChanged 7",
            "momentumChanged 6", "momentumChanged 5", "momentumChanged 5", "momentumChanged 4",
            "momentumChanged 3", "momentumChanged 3", "momentumChanged 2", "momentumChanged 2",
            "momentumChanged 2", "momentumChanged 2", "momentumChanged 1", "momentumChanged 1",
            "momentumEnded 0",
        ])
        // The touch begins with the first display frame after the wheel event and lifts 50 ms
        // after that event; the glide's first frame comes with the "ended".
        XCTAssertEqual(rig.firstTime(of: "began") ?? -1, 1.0 / 60.0, accuracy: 1e-6)
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
            "began ×1", "changed ×1", "ended ×1", "momentumBegan ×1", "momentumChanged ×36", "momentumEnded ×1",
        ])
        XCTAssertEqual(Array(rig.stream.prefix(4)), ["began 7", "changed 20", "ended 0", "momentumBegan 40"])
    }

    /// A long spin (27 ticks in 400 ms, up to 690 px a frame): the touch is over after 50 ms and
    /// everything after it, while the wheel still turns, is glide. At an edge it bounces once.
    func testTrackpadStyle_longSpin_isGlideAfterTheFirstFiftyMilliseconds() {
        let rig = ScrollClassicRig(duration: 3.69, trackpadStyle: true)
        for (pixels, time) in Self.spin { rig.input(pixels, notch: 33.6 * 6.3, at: time) }
        rig.run(until: 4)

        XCTAssertEqual(rig.phaseRuns, [
            "began ×1", "changed ×1", "ended ×1", "momentumBegan ×1", "momentumChanged ×64", "momentumEnded ×1",
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
            "began ×1", "changed ×1", "ended ×1", "momentumBegan ×1", "momentumChanged ×104", "momentumEnded ×1",
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
            "began ×1", "changed ×1", "ended ×1", "momentumBegan ×1", "momentumChanged ×17", "momentumEnded ×1",
            "began ×1", "changed ×2", "ended ×1", "momentumBegan ×1", "momentumChanged ×20", "momentumEnded ×1",
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
                XCTAssertEqual((second?.time ?? 0) - rig.start, 0.2 + 1.0 / 60.0, accuracy: 1e-6, "\(name): with the first frame after the tick")
                XCTAssertNotEqual(second?.frame.y, 0, "\(name): \"began\" moves the page")
            }
        }
    }

    /// The switch goes on while a scroll without phases runs (in the same process: the switch
    /// or the app's own setting was changed). That scroll is ended, and the wheel event begins
    /// a touch of its own: the app got no "began" for the glide that ran, so it gets no
    /// "momentum ended" for it either (it used to get one).
    func testTrackpadStyle_afterAScrollWithTheSwitchOff_beginsATouch() {
        var ended: [ScrollSystemLog.EndReason] = []
        ScrollSystemLog.sessionObserverForTests = { ended.append($1) }
        defer { ScrollSystemLog.sessionObserverForTests = nil }
        let rig = ScrollClassicRig(duration: 3.69, trackpadStyle: false)
        rig.input(33.6 * 6.3, notch: 33.6 * 6.3, at: 0)
        rig.run(until: 0.25)
        XCTAssertEqual(rig.phases.phase, .MomentumOngoing, "the phase machine runs with the switch off too")
        rig.poster.changeFormForTests(simTrackpadEnabled: true)
        XCTAssertEqual(ended, [.settingChanged])
        rig.input(33.6 * 6.3, notch: 33.6 * 6.3, at: 0.25, place: ScrollInputPlace(pid: 100, pointer: .zero))
        rig.run(until: 3)

        XCTAssertEqual(rig.phaseSequence, ["began", "changed", "ended", "momentumBegan", "momentumChanged", "momentumEnded"])
        // The new scroll is the wheel event's own: one click, nothing of the glide that ran.
        let afterTheSwitch = rig.recorded.filter { $0.frame.scrollPhase != nil }.reduce(0) { $0 + $1.frame.y }
        XCTAssertEqual(afterTheSwitch, 205)
    }

    /// And the other way: the switch goes off while a flick's glide runs, with a turn asked
    /// for. The glide is closed in its own form ("momentum ended") before anything goes out
    /// without phases, and the turn is not carried into the scroll that follows. The scroll
    /// used to be taken over as it was: the app never got "momentum ended" (this test passed
    /// on that stream), and before that the turn began a "touch" with the next frame, two
    /// frames without distance that the switch-off path does not post.
    func testSwitchOffInTheNextApp_carriesNoTurnOver() {
        var ended: [ScrollSystemLog.EndReason] = []
        ScrollSystemLog.sessionObserverForTests = { ended.append($1) }
        defer { ScrollSystemLog.sessionObserverForTests = nil }
        let rig = ScrollClassicRig(duration: 3.69, trackpadStyle: true)
        for (points, time) in [(1.0, 0.0), (12, 0.024), (54, 0.038), (78, 0.060)] {
            rig.input(max(33.6, points) * 6.3, notch: 33.6 * 6.3, at: time)
        }
        rig.input(-33.6 * 6.3, notch: 33.6 * 6.3, at: 0.300)
        rig.poster.changeFormForTests(simTrackpadEnabled: false)
        rig.input(33.6 * 6.3, notch: 33.6 * 6.3, at: 0.310)
        rig.run(until: 3)

        // The glide that ran was closed, and nothing with a phase came after that.
        XCTAssertEqual(ended.first, .settingChanged)
        XCTAssertEqual(rig.phaseSequence, ["began", "changed", "ended", "momentumBegan", "momentumChanged", "momentumEnded"])
        let lastPhased = try? XCTUnwrap(rig.recorded.lastIndex { $0.frame.scrollPhase != nil })
        let firstPlain = try? XCTUnwrap(rig.recorded.firstIndex { $0.frame.scrollPhase == nil })
        XCTAssertLessThan(lastPhased ?? .max, firstPlain ?? .min, "closed before the first frame without phases")
        // From the tick until the wheel counts as still (0.18 s later) only frames that move the page.
        let afterTheTick = rig.recorded.filter { $0.time - rig.start > 0.310 + 1e-6 && $0.time - rig.start < 0.45 }
        XCTAssertFalse(afterTheTick.isEmpty)
        XCTAssertTrue(afterTheTick.allSatisfy { $0.frame.y != 0 }, "no frame without distance")
        XCTAssertTrue(afterTheTick.allSatisfy { $0.frame.scrollPhase == nil }, "and no phases")
        // The scroll that follows is the wheel event's own click, the way it turned last.
        XCTAssertEqual(rig.recorded.filter { $0.frame.scrollPhase == nil }.reduce(0) { $0 + $1.frame.y }, 205)
    }

    /// B1: "Trackpad-style scrolling" goes off for the process a scroll runs in (the switch,
    /// the app's own setting or "Reset to Defaults", changed from the keyboard), at any moment
    /// of a touch or a glide, in each form. What the app got with phases is whole gestures:
    /// the running scroll is closed before the first frame without phases.
    func testTrackpadStyle_switchedOffInMidScroll_closesTheGestureFirst() {
        var failures: [String] = []
        var runs = 0
        for form in ScrollClassicRig.Form.allCases {
            for (name, inputs) in Self.gestureScenarios {
                for offAt in stride(from: 0.010, through: 0.9, by: 0.023) {
                    let rig = ScrollClassicRig(duration: 3.69, form: form)
                    let notch = 33.6 * 6.3
                    for (notches, time) in inputs where time <= offAt { rig.input(notches * notch, notch: notch, at: time, targetPID: 100) }
                    rig.run(until: offAt)
                    rig.poster.changeFormForTests(simTrackpadEnabled: false)
                    rig.input(notch, notch: notch, at: offAt, targetPID: 100)
                    rig.run(until: 4)
                    runs += 1
                    let label = "\(form.rawValue): \(name), off at \(Int(offAt * 1000)) ms"
                    if let broken = Self.brokenGesture(in: rig, mayBeEmpty: true, phasedOnly: true) {
                        failures.append("\(label): \(broken)")
                    }
                    if form == .oneTouch, let broken = Self.brokenOneTouchEnd(in: rig) { failures.append("\(label): \(broken)") }
                    let lastPhased = rig.recorded.lastIndex { $0.frame.scrollPhase != nil } ?? -1
                    let firstPlain = rig.recorded.firstIndex { $0.frame.scrollPhase == nil } ?? .max
                    if lastPhased > firstPlain { failures.append("\(label): a phase after a frame without one") }
                }
            }
        }
        XCTAssertEqual(runs, 936)
        XCTAssertTrue(failures.isEmpty, "\(failures.count) broken:\n" + failures.prefix(40).joined(separator: "\n"))
    }

    /// The phases an app gets always make whole gestures, at any Duration, Speed, dead zone and
    /// display rate: "began, changed…, ended", then "momentum began, momentum changed…, momentum
    /// ended" or nothing. A glide whose first frame comes to no whole pixel posts nothing; its
    /// "momentum began" waits for the frame that is posted. It used to be skipped: the app got
    /// "momentum changed" alone and took the glide for a finger that drags the page past the edge.
    /// And a touch that leaves no glide ends after its last frame (frames after "ended" carried
    /// "ended" again, with a distance); a glide of which no frame went out sends nothing at all.
    ///
    /// For every form: the flick, the one touch every app that is not Chromium-based gets,
    /// and the old long touch. The long touch used to be left out here, and broke the rule in
    /// about one run of six: a frame with a distance that carried "ended" after the "ended" (short Durations),
    /// "momentum changed" without a "momentum began", a "momentum ended" for a glide whose
    /// "began" never went out.
    func testTrackpadStyle_phasesAlwaysMakeWholeGestures() {
        var failures: [String] = []
        var runs = 0
        for form in ScrollClassicRig.Form.allCases {
            for duration in [1.0, 2.0, 3.13, 3.69, 4.35, 5.0] {
                for rate in [60.0, 120.0, 144.0] {
                    for speed in [1.0, 6.3] {
                        for deadZone in [1.0, 3.0] {
                            for (name, inputs) in Self.gestureScenarios {
                                let rig = ScrollClassicRig(duration: duration, rate: rate, deadZone: deadZone, form: form)
                                let notch = 33.6 * speed
                                for (notches, time) in inputs { rig.input(notches * notch, notch: notch, at: time) }
                                rig.run(until: 30)  // Duration 5 glides for many seconds
                                runs += 1
                                // A flick has no frame without distance to begin with: a scroll
                                // that moves nothing (it stays under the dead zone) sends nothing.
                                let mayBeEmpty = form == .flick && rig.moving.isEmpty
                                if let broken = Self.brokenGesture(in: rig, mayBeEmpty: mayBeEmpty) {
                                    failures.append("\(form.rawValue): \(name), Duration \(duration), \(Int(rate)) Hz, Speed \(speed), dead zone \(deadZone): \(broken)")
                                }
                                if form == .flick && rig.moving.isEmpty && !rig.recorded.isEmpty {
                                    failures.append("\(form.rawValue): \(name), Duration \(duration), \(Int(rate)) Hz, Speed \(speed), dead zone \(deadZone): frames for a scroll that moves nothing: \(rig.stream)")
                                }
                                if form == .oneTouch, let broken = Self.brokenOneTouchEnd(in: rig) {
                                    failures.append("\(form.rawValue): \(name), Duration \(duration), \(Int(rate)) Hz, Speed \(speed), dead zone \(deadZone): \(broken)")
                                }
                            }
                        }
                    }
                }
            }
        }
        XCTAssertEqual(runs, 1_728)
        XCTAssertTrue(failures.isEmpty, "\(failures.count) broken:\n" + failures.prefix(40).joined(separator: "\n"))
    }

    /// The same when the scroll is stopped from outside at any moment (a left click, a finger
    /// on the trackpad, Pause, the wheel going on in another app): what the app got up to
    /// then, closed by the stop, is whole gestures. A stop in the moment after a touch that
    /// left no glide used to send its "ended" a second time: "began, ended, ended".
    func testTrackpadStyle_aStopAtAnyMomentLeavesWholeGestures() {
        var failures: [String] = []
        var stops = 0
        for form in ScrollClassicRig.Form.allCases {
            for duration in [2.0, 3.69, 5.0] {
                for rate in [60.0, 120.0] {
                    for (name, inputs) in Self.gestureScenarios {
                        for stopAt in stride(from: 0.004, through: 1.2, by: 0.011) {
                            let rig = ScrollClassicRig(duration: duration, rate: rate, form: form)
                            let notch = 33.6 * 6.3
                            for (notches, time) in inputs where time <= stopAt { rig.input(notches * notch, notch: notch, at: time) }
                            rig.run(until: stopAt)
                            rig.poster.stop(reason: .leftClick)
                            stops += 1
                            if let broken = Self.brokenGesture(in: rig, mayBeEmpty: true) {
                                failures.append("\(form.rawValue): \(name), Duration \(duration), \(Int(rate)) Hz, stop at \(Int(stopAt * 1000)) ms: \(broken)")
                            }
                            if form == .oneTouch, let broken = Self.brokenOneTouchEnd(in: rig) {
                                failures.append("\(form.rawValue): \(name), Duration \(duration), \(Int(rate)) Hz, stop at \(Int(stopAt * 1000)) ms: \(broken)")
                            }
                        }
                    }
                }
            }
        }
        XCTAssertEqual(stops, 15_696)
        XCTAssertTrue(failures.isEmpty, "\(failures.count) broken:\n" + failures.prefix(40).joined(separator: "\n"))
    }

    /// And when macOS turns the scroll tap off, or the tap is restarted, at any moment: that
    /// stop asks for the touch's end, not the glide's (`stop(.TrackingEnd)`), and a glide that
    /// runs has to be ended all the same. (Two single moments were tested before.)
    func testTrackpadStyle_aTapRestartAtAnyMomentLeavesWholeGestures() {
        var failures: [String] = []
        var stops = 0
        for form in ScrollClassicRig.Form.allCases {
            for duration in [2.0, 3.69, 5.0] {
                for rate in [60.0, 120.0] {
                    for (name, inputs) in Self.gestureScenarios {
                        for stopAt in stride(from: 0.004, through: 1.2, by: 0.011) {
                            let rig = ScrollClassicRig(duration: duration, rate: rate, form: form)
                            let notch = 33.6 * 6.3
                            for (notches, time) in inputs where time <= stopAt { rig.input(notches * notch, notch: notch, at: time) }
                            rig.run(until: stopAt)
                            rig.poster.stop(.TrackingEnd, reason: .tapRestarted)
                            stops += 1
                            if let broken = Self.brokenGesture(in: rig, mayBeEmpty: true) {
                                failures.append("\(form.rawValue): \(name), Duration \(duration), \(Int(rate)) Hz, stop at \(Int(stopAt * 1000)) ms: \(broken)")
                            }
                            if form == .oneTouch, let broken = Self.brokenOneTouchEnd(in: rig) {
                                failures.append("\(form.rawValue): \(name), Duration \(duration), \(Int(rate)) Hz, stop at \(Int(stopAt * 1000)) ms: \(broken)")
                            }
                        }
                    }
                }
            }
        }
        XCTAssertEqual(stops, 15_696)
        XCTAssertTrue(failures.isEmpty, "\(failures.count) broken:\n" + failures.prefix(40).joined(separator: "\n"))
    }

    /// The first scroll over a Chromium-based app after Scrollio started: the app counts as
    /// touch-only until its bundle was looked into (off the main thread, a moment), so the
    /// scroll begins as one touch and goes on as a flick from the wheel event after the
    /// answer. Whenever the answer comes, the app still gets whole gestures.
    func testTrackpadStyle_theFormChangingDuringAScrollLeavesWholeGestures() {
        var failures: [String] = []
        let place = ScrollInputPlace(pid: 100, pointer: CGPoint(x: 400, y: 300))
        for form in [ScrollClassicRig.Form.oneTouch, .oldLongTouch] {
            for duration in [2.0, 3.69, 5.0] {
                for rate in [60.0, 120.0] {
                    for (name, inputs) in Self.gestureScenarios {
                        // The answer arrives before wheel event number `answerBefore`.
                        for answerBefore in 1..<max(2, min(inputs.count, 6)) {
                            let rig = ScrollClassicRig(duration: duration, rate: rate, form: form)
                            let notch = 33.6 * 6.3
                            for (index, (notches, time)) in inputs.enumerated() {
                                if index == answerBefore {
                                    rig.run(until: time)
                                    rig.poster.setConfigForTests(simTrackpadEnabled: true, flick: true)
                                }
                                // The one touch and the flick know the wheel event's place; the old long touch did not.
                                let knowsThePlace = form == .oneTouch || index >= answerBefore
                                rig.input(notches * notch, notch: notch, at: time, place: knowsThePlace ? place : nil, targetPID: 100)
                            }
                            rig.run(until: 30)
                            if let broken = Self.brokenGesture(in: rig, mayBeEmpty: false) {
                                failures.append("\(form.rawValue), \(name), Duration \(duration), \(Int(rate)) Hz, flick from wheel event \(answerBefore + 1): \(broken)")
                            }
                        }
                    }
                }
            }
        }
        XCTAssertTrue(failures.isEmpty, "\(failures.count) broken:\n" + failures.prefix(40).joined(separator: "\n"))
    }

    /// Wheel turns as (notches, seconds), for the whole-gesture checks.
    /// The other way round: a scroll that runs as a flick (or as the old long touch) goes
    /// on as one touch. No path does that today (an app's kind only changes from not known
    /// to "follows the glide"), but should one ever: the gesture the app has is closed
    /// before the one touch begins. It used to stay open for good: the one touch posts
    /// nothing of the phase machine's, so the glide never got its "momentum ended".
    func testTrackpadStyle_aFlickGoingOnAsOneTouchClosesItsGestureFirst() {
        var failures: [String] = []
        var runs = 0
        let place = ScrollInputPlace(pid: 100, pointer: CGPoint(x: 400, y: 300))
        for form in [ScrollClassicRig.Form.flick, .oldLongTouch] {
            for duration in [2.0, 3.69, 5.0] {
                for rate in [60.0, 120.0] {
                    for (name, inputs) in Self.gestureScenarios {
                        for changeBefore in 1..<max(2, min(inputs.count, 6)) {
                            let rig = ScrollClassicRig(duration: duration, rate: rate, form: form)
                            let notch = 33.6 * 6.3
                            for (index, (notches, time)) in inputs.enumerated() {
                                if index == changeBefore {
                                    rig.run(until: time)
                                    rig.poster.setConfigForTests(simTrackpadEnabled: true, flick: false)
                                }
                                rig.input(notches * notch, notch: notch, at: time, place: place, targetPID: 100)
                            }
                            rig.run(until: 30)
                            runs += 1
                            if let broken = Self.brokenGesture(in: rig, mayBeEmpty: false) {
                                failures.append("\(form.rawValue), \(name), Duration \(duration), \(Int(rate)) Hz, one touch from wheel event \(changeBefore + 1): \(broken)")
                            }
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(runs, 200)
        XCTAssertTrue(failures.isEmpty, "\(failures.count) broken:\n" + failures.prefix(30).joined(separator: "\n"))

        // In the glide: "momentum ended", then the one touch's "began", with the wheel event.
        let rig = ScrollClassicRig(duration: 3.69, form: .flick)
        rig.input(33.6 * 6.3, notch: 33.6 * 6.3, at: 0, place: place, targetPID: 100)
        rig.run(until: 0.25)
        XCTAssertEqual(rig.phases.phase, .MomentumOngoing)
        let before = rig.recorded.count
        rig.poster.setConfigForTests(simTrackpadEnabled: true, flick: false)
        rig.input(33.6 * 6.3, notch: 33.6 * 6.3, at: 0.25, place: place, targetPID: 100)
        XCTAssertEqual(Array(rig.stream.dropFirst(before)), ["momentumEnded 0", "began 0"])
        rig.run(until: 4)
        XCTAssertEqual(rig.stream.last, "ended 0")
        XCTAssertFalse(rig.recorded.dropFirst(before + 1).contains { ($0.frame.momentumPhase ?? 0) != 0 }, "from there on: one touch")
    }

    /// The scroll under a one touch ends when the switch-off scroll does, also after a
    /// wheel event that came while its stop was held for the touch's rest. A click at a
    /// short glide time is over (its stop held, the touch resting) when a click with
    /// Smooth's glide time comes (the feel was changed in between). That click's own scroll
    /// ends 17 ms after its touch's "ended", as with the switch off, not with it. (The wheel
    /// event takes the held stop back. Left standing, the stop was asked for the moment
    /// the second touch ended, before the scroll under it was over.)
    func testTrackpadStyleOneTouch_aWheelEventTakesBackAHeldStop() throws {
        let click = 33.6 * 6.3
        let alone = ScrollClassicRig(duration: 2.0, trackpadStyle: false)
        alone.input(click, notch: click, at: 0)
        alone.run(until: 4)
        let over = try XCTUnwrap(alone.stops.first?.time)
        let touchEnds = alone.lastMovement + 0.2
        XCTAssertLessThan(over, touchEnds - 0.03, "at this glide time the scroll is over while the touch still rests")
        let second = (over + touchEnds) / 2

        let touch = ScrollClassicRig(duration: 2.0, form: .oneTouch)
        let plain = ScrollClassicRig(duration: 2.0, trackpadStyle: false)
        for rig in [touch, plain] {
            rig.input(click, notch: click, at: 0)
            rig.input(click, notch: click, at: second, duration: 3.69)
            rig.run(until: 6)
        }
        XCTAssertEqual(plain.stops.count, 2, "with the switch off the first scroll is over before the second click")
        XCTAssertEqual(touch.stops.count, 1, "the click came in the touch's rest: one scroll")
        XCTAssertEqual(touch.phaseSequence, ["began", "changed", "ended"])
        XCTAssertEqual(touch.moving.map { $0.frame.y }, plain.moving.map { $0.frame.y })
        let ended = touch.firstTime(of: "ended") ?? -1
        XCTAssertLessThan(ended, (plain.stops.last?.time ?? 0) - 1e-6, "the touch ends before the scroll under it is over")
        XCTAssertEqual(touch.stops.last?.time ?? -1, plain.stops.last?.time ?? -2, accuracy: 1e-6, "and the scroll ends when the switch-off one does")
    }

    private static let gestureScenarios: [(String, [(Double, Double)])] = {
        var spin: [(Double, Double)] = []
        for index in 0..<27 { spin.append((1 + Double(index) * 0.1, Double(index) * 0.015)) }
        var keepsTurning: [(Double, Double)] = []
        for index in 0..<12 { keepsTurning.append((1, Double(index) * 0.12)) }
        let burst: [(Double, Double)] = [(1, 0), (1, 0.024), (1.6, 0.038), (2.3, 0.060)]
        return [
            ("click", [(1, 0)]),
            ("burst", burst),
            ("spin", spin),
            ("keeps turning", keepsTurning),
            ("turn back in the glide", burst + [(-1, 0.3)]),
            ("turn back in the touch", [(1, 0), (-1, 0.030)]),
            ("wobble", [(1, 0), (-1, 0.3), (1, 0.31), (-1, 0.32)]),
            ("two clicks", [(1, 0), (1, 0.5)]),
        ]
    }()

    /// What breaks the rule in the frames a rig recorded, or nil: "began, changed…, ended",
    /// then "momentum began, momentum changed…, momentum ended" or nothing, each gesture closed.
    /// `phasedOnly`: frames without phases (a scroll with the switch off) are left out.
    private static func brokenGesture(in rig: ScrollClassicRig, mayBeEmpty: Bool, phasedOnly: Bool = false) -> String? {
        // The tap after a forced end of a one touch: "may begin", then "cancelled", right
        // after an "ended" and nowhere else.
        let allowed: [String: Set<String>] = [
            "": ["began"],
            "began": ["changed", "ended"],
            "changed": ["changed", "ended"],
            "ended": ["momentumBegan", "began", "mayBegin"],
            "mayBegin": ["cancelled"],
            "cancelled": ["began"],
            "momentumBegan": ["momentumChanged", "momentumEnded"],
            "momentumChanged": ["momentumChanged", "momentumEnded"],
            "momentumEnded": ["began"],
        ]
        var last = ""
        for item in rig.recorded {
            if phasedOnly && item.frame.scrollPhase == nil { continue }
            let phase = ScrollClassicRig.phaseName(scroll: item.frame.scrollPhase ?? -1, momentum: item.frame.momentumPhase ?? -1)
            if allowed[last]?.contains(phase) != true {
                return "\"\(phase)\" after \"\(last)\" at \(Int(((item.time - rig.start) * 1000).rounded())) ms"
            }
            if (phase == "mayBegin" || phase == "cancelled" || phase == "ended") && (item.frame.y != 0 || item.frame.x != 0) {
                return "\"\(phase)\" with a distance at \(Int(((item.time - rig.start) * 1000).rounded())) ms"
            }
            last = phase
        }
        if last == "ended" || last == "momentumEnded" || last == "cancelled" || (mayBeEmpty && last == "") {
            return nil
        }
        return "ends with \"\(last)\""
    }

    /// What breaks the one touch's rule for its end in the frames a rig recorded, or nil.
    /// An "ended" either comes by itself, and then its time is 0.2 s or more after the time
    /// of the frame before it (the touch's last "changed", or its "began") and nothing
    /// follows but a new "began"; or it is forced, and then the two-finger tap follows it at
    /// once. So an "ended" that comes sooner than 0.2 s after the touch's last frame always
    /// has its tap. And no frame of the touch carries a glide phase.
    private static func brokenOneTouchEnd(in rig: ScrollClassicRig) -> String? {
        let frames = rig.recorded
        for (index, item) in frames.enumerated() {
            if (item.frame.momentumPhase ?? 0) != 0 { return "a glide event" }
            guard item.frame.scrollPhase == 4 else { continue }
            let at = "at \(Int(((item.time - rig.start) * 1000).rounded())) ms"
            guard index > 0, let stamp = item.frame.timestamp, let before = frames[index - 1].frame.timestamp else {
                return "an \"ended\" without a frame before it or without a time \(at)"
            }
            let rest = Double(stamp - before) / 1e9
            let hasTap = index + 2 < frames.count
                && frames[index + 1].frame.scrollPhase == 128 && frames[index + 2].frame.scrollPhase == 8
            if rest < 0.2 && !hasTap {
                return "\"ended\" \(Int((rest * 1000).rounded())) ms after the touch's last frame, and no tap after it, \(at)"
            }
            if hasTap {
                let first = frames[index + 1], second = frames[index + 2]
                if first.time != item.time || second.time != item.time { return "the tap does not follow its \"ended\" at once \(at)" }
                guard let t1 = first.frame.timestamp, let t2 = second.frame.timestamp, t1 > stamp, t2 > t1 else { return "the tap's times do not go on \(at)" }
            }
        }
        return nil
    }

    // MARK: Trackpad-style, as one touch to the end
    //
    // AppKit and UIKit scroll views (Finder, Settings, most apps) follow the touch only. When it
    // ends they compute a glide of their own from its speed and ignore what the momentum events
    // say: in the owner's recording a Finder list moved ~250 pt for 7,225 px posted as a flick.
    // Only an app that scrolls by a glide's events (Chromium) gets the flick. Every other app
    // gets one touch that lasts until the scroll has run out, and no glide events: whatever of
    // a scroll went out as a glide, such a view never followed.

    /// One click at every feel: "began", every frame of the scroll as "changed", "ended" with
    /// the frame after the last one, and nothing after that. The frames are the switch-off
    /// path's, one for one.
    func testTrackpadStyleOneTouch_theWholeScrollIsTouch() {
        let click = 33.6 * 6.3
        for (feel, duration) in [("Direct", 2.0), ("Quick", 3.13), ("Smooth", 3.69), ("Glide", 4.35), ("Float", 4.6), ("glide time 5.0", 5.0)] {
            let rig = ScrollClassicRig(duration: duration, form: .oneTouch)
            let plain = ScrollClassicRig(duration: duration, trackpadStyle: false)
            for each in [rig, plain] {
                each.input(click, notch: click, at: 0)
                each.run(until: 30)
            }
            XCTAssertEqual(rig.phaseSequence, ["began", "changed", "ended"], feel)
            XCTAssertEqual(rig.stream.first, "began 0", feel)
            XCTAssertEqual(rig.stream.last, "ended 0", feel)
            let inTheTouch = rig.recorded.filter { $0.frame.scrollPhase == 2 }.reduce(0) { $0 + $1.frame.y }
            XCTAssertEqual(inTheTouch, plain.postedY, "\(feel): all of the scroll is touch")
            XCTAssertEqual(rig.moving.map { $0.frame.y }, plain.moving.map { $0.frame.y }, feel)
            XCTAssertEqual(rig.moving.map { $0.time }, plain.moving.map { $0.time }, feel)
            // The finger lifts 0.2 s after the last frame that moved the page (the first
            // display frame whose "ended" carries a time that far after it), and that is all:
            // no tap after an end that came by itself.
            let lift = (rig.firstTime(of: "ended") ?? -1) - rig.lastMovement
            XCTAssertGreaterThanOrEqual(lift, 0.2, feel)
            XCTAssertLessThan(lift, 0.2 + 2.0 / 60.0, feel)
            let ended = rig.recorded.last?.frame.timestamp ?? 0
            let lastChanged = rig.moving.last?.frame.timestamp ?? 0
            XCTAssertGreaterThanOrEqual(Double(ended - lastChanged) / 1e9, 0.2, "\(feel): by the frames' own times")
            XCTAssertNil(Self.brokenOneTouchEnd(in: rig), feel)
            XCTAssertTrue(rig.recorded.allSatisfy { $0.frame.timestamp != nil }, "\(feel): every frame its own time")
            XCTAssertEqual(rig.stops.count, 1, feel)
            XCTAssertEqual(rig.sessions.last?.oneTouch, true, feel)
            XCTAssertEqual(rig.sessions.last?.touches, 1, feel)
        }
    }

    /// Every scroll, not only a click. The one touch is laid over the scroll as it runs with
    /// the switch off, so at every feel, display rate and dead zone, in every gesture, and for
    /// eight clicks at every pace from ten a second to one every 1.6 s: the frames that move
    /// the page are the switch-off path's (times and distances), every one of them a
    /// "changed", no glide event, and each scroll ends at the moment the switch-off one ends.
    /// (It ran at Smooth only. The touch used to end the scroll itself, 0.04 s after its
    /// "ended"; with the switch off a scroll ends 0.13 s after it has arrived, and a click
    /// between the two met a new scroll: at Quick, 120 Hz, a click every 0.425 s, eight
    /// scrolls instead of one and 1,656 px instead of 1,671; 10 of 732 paces differed, at
    /// Direct and Quick.)
    func testTrackpadStyleOneTouch_keepsEveryFrameOfTheMotion() {
        let notch = 33.6 * 6.3
        let here = ScrollInputPlace(pid: 100, pointer: CGPoint(x: 400, y: 300))
        var failures: [String] = []
        var runs = 0
        func compare(_ label: String, duration: Double, rate: Double, deadZone: Double, inputs: [(Double, Double)]) {
            let touch = ScrollClassicRig(duration: duration, rate: rate, deadZone: deadZone, form: .oneTouch)
            let plain = ScrollClassicRig(duration: duration, rate: rate, trackpadStyle: false, deadZone: deadZone)
            for (notches, time) in inputs {
                touch.input(notches * notch, notch: notch, at: time, place: here, targetPID: 100)
                plain.input(notches * notch, notch: notch, at: time, targetPID: 100)
            }
            touch.run(until: 40)
            plain.run(until: 40)
            runs += 1
            let name = "\(label), Duration \(duration), \(Int(rate)) Hz, dead zone \(deadZone)"
            if touch.moving.map({ $0.frame.y }) != plain.moving.map({ $0.frame.y }) {
                failures.append("\(name): \(touch.postedY) px in \(touch.moving.count) frames, switch off \(plain.postedY) px in \(plain.moving.count)")
            } else if touch.moving.map({ $0.time }) != plain.moving.map({ $0.time }) {
                failures.append("\(name): the frames come at other times")
            }
            // The scroll under the touch ends when the switch-off one does. The scroll as
            // the app has it stays up until the touch's "ended" is out, 0.2 s after its last
            // frame: so it never ends sooner than with the switch off, at most that rest (and
            // two frames) after the last frame later, and a wheel event in the rest goes on
            // with it (fewer scrolls then, never more).
            let lastStop = touch.stops.last?.time ?? -1
            let plainLastStop = plain.stops.last?.time ?? -1
            let latest = max(plainLastStop, plain.lastMovement + 0.2005 + 2 / rate) + 1e-6
            if touch.stops.isEmpty || touch.stops.count > plain.stops.count || lastStop < plainLastStop - 1e-6 || lastStop > latest {
                failures.append("\(name): \(touch.stops.count) scrolls, the last ends at \(lastStop); switch off \(plain.stops.count), at \(plainLastStop), last frame at \(plain.lastMovement)")
            }
            if let broken = Self.brokenOneTouchEnd(in: touch) { failures.append("\(name): \(broken)") }
            if !touch.moving.allSatisfy({ $0.frame.scrollPhase == 2 }) { failures.append("\(name): a moving frame that is no \"changed\"") }
            if touch.recorded.contains(where: { ($0.frame.momentumPhase ?? 0) != 0 }) { failures.append("\(name): a glide event") }
            if let broken = Self.brokenGesture(in: touch, mayBeEmpty: false) { failures.append("\(name): \(broken)") }
        }
        var freeSpin: [(Double, Double)] = []
        for index in 0..<100 { freeSpin.append((1, Double(index) * 0.010)) }
        var spinAndBack: [(Double, Double)] = []
        for index in 0..<27 { spinAndBack.append((1 + Double(index) * 0.1, Double(index) * 0.015)) }
        spinAndBack.append((-1, 0.45))
        let scenarios = Self.gestureScenarios + [
            ("free spin, an event every 10 ms", freeSpin),
            ("a click every 0.4 s", (0..<8).map { (1, Double($0) * 0.4) }),
            ("spin, then one click back", spinAndBack),
        ]
        for duration in [2.0, 3.13, 3.69, 4.35, 4.6, 5.0] {
            for rate in [60.0, 120.0, 144.0] {
                for deadZone in [1.0, 3.0] {
                    for (name, inputs) in scenarios {
                        compare(name, duration: duration, rate: rate, deadZone: deadZone, inputs: inputs)
                    }
                }
            }
            for rate in [60.0, 120.0] {
                for gap in stride(from: 0.10, through: 1.60, by: 0.025) {
                    compare("eight clicks, one every \(String(format: "%.3f", gap)) s", duration: duration, rate: rate, deadZone: 1,
                            inputs: (0..<8).map { (1, Double($0) * gap) })
                }
            }
        }
        XCTAssertEqual(runs, 6 * 3 * 2 * 11 + 6 * 2 * 61)
        XCTAssertTrue(failures.isEmpty, "\(failures.count) differ:\n" + failures.prefix(30).joined(separator: "\n"))
    }

    /// A scroll that begins after the last one has ended is a touch of its own; clicks that
    /// follow each other while the frames still run are one touch.
    func testTrackpadStyleOneTouch_aTouchPerScroll() {
        for (name, inputs, touches) in [
            ("a click every 0.4 s", [(211.68, 0.0), (211.68, 0.4), (211.68, 0.8), (211.68, 1.2)], 1),
            ("two scrolls", [(211.68, 0.0), (211.68, 1.2)], 2),
        ] {
            let rig = ScrollClassicRig(duration: 3.69, form: .oneTouch)
            for (pixels, time) in inputs { rig.input(pixels, notch: 211.68, at: time) }
            rig.run(until: 6)
            XCTAssertEqual(rig.recorded.filter { $0.frame.scrollPhase == 1 }.count, touches, name)
            XCTAssertEqual(rig.recorded.filter { $0.frame.scrollPhase == 4 }.count, touches, name)
            XCTAssertEqual(rig.sessions.reduce(0) { $0 + $1.touches }, touches, name)
        }
    }

    /// A wheel event long after the last one, while the touch is still open (its frames run for
    /// 0.73 s after a click at Glide, 1 s at Float, 3 s at glide time 5.0): it goes on with
    /// the touch. Taken for a new scroll by its time alone (0.45 s), it sent a second "began"
    /// into the open touch.
    func testTrackpadStyleOneTouch_aLateWheelEventGoesOnWithTheOpenTouch() {
        let click = 33.6 * 6.3
        for (feel, duration, later) in [("Glide", 4.35, 0.5), ("Float", 4.6, 0.6), ("glide time 5.0", 5.0, 0.5), ("glide time 5.0", 5.0, 2.0)] {
            let rig = ScrollClassicRig(duration: duration, form: .oneTouch)
            let plain = ScrollClassicRig(duration: duration, trackpadStyle: false)
            for each in [rig, plain] {
                each.input(click, notch: click, at: 0)
                each.input(click, notch: click, at: later)
                each.run(until: 30)
            }
            let label = "\(feel), the second click \(later) s later"
            XCTAssertEqual(rig.phaseSequence, ["began", "changed", "ended"], label)
            XCTAssertEqual(rig.recorded.filter { $0.frame.scrollPhase == 1 }.count, 1, "\(label): one \"began\"")
            XCTAssertEqual(rig.sessions.last?.touches, 1, label)
            XCTAssertEqual(rig.postedY, plain.postedY, label)
        }
    }

    /// A fast spin and then one click back, the way a page is stopped. The motion does not
    /// turn at once: what the spin left has to run down first. With a short glide the click
    /// back only brakes; with a long one the page comes to a standstill some time after that
    /// click and then moves back (70 px at Float, 149 at glide time 5.0). That standstill is
    /// not the end of the scroll, and the touch stays open through it. Taken for "the last
    /// frame has gone out", it ended the touch there, and the way back never reached the app.
    func testTrackpadStyleOneTouch_theTouchLastsThroughATurn() {
        for (feel, duration, movesBack) in [("Quick", 3.13, false), ("Smooth", 3.69, false), ("Float", 4.6, true), ("glide time 5.0", 5.0, true)] {
            var inputs = Self.spin
            inputs.append((-211.68, 0.45))
            let plain = ScrollClassicRig(duration: duration, trackpadStyle: false)
            let touch = ScrollClassicRig(duration: duration, form: .oneTouch)
            for rig in [plain, touch] {
                for (pixels, time) in inputs { rig.input(pixels, notch: 211.68, at: time) }
                rig.run(until: 30)
            }
            let back = plain.moving.filter { $0.frame.y < 0 }.reduce(0) { $0 + $1.frame.y }
            XCTAssertEqual(back < -50, movesBack, "\(feel): with the switch off the page moves back \(back) px")
            XCTAssertEqual(touch.moving.map { $0.frame.y }, plain.moving.map { $0.frame.y }, feel)
            XCTAssertEqual(touch.moving.map { $0.time }, plain.moving.map { $0.time }, feel)
            XCTAssertEqual(touch.phaseSequence, ["began", "changed", "ended"], "\(feel): one touch, through the turn")
            XCTAssertTrue(touch.moving.allSatisfy { $0.frame.scrollPhase == 2 }, feel)
        }
    }

    /// The wheel goes on over another pane of the same app while the touch is open: the touch
    /// ends and a new one begins with that wheel event, which takes the motion on (as a flick's
    /// wheel event elsewhere does, and as it is with the switch off). Apps keep a gesture on
    /// the scroller that got its "began": left open, the touch held on to the first pane until
    /// the scroll ran out. A hand that turns the wheel moves the pointer a little: that is the
    /// same place.
    func testTrackpadStyleOneTouch_aWheelEventFarAwayBeginsATouchOfItsOwn() {
        let click = 33.6 * 6.3
        let here = ScrollInputPlace(pid: 100, pointer: CGPoint(x: 400, y: 300))
        let cases: [(String, ScrollInputPlace, Bool)] = [
            ("the hand moved the pointer a little", ScrollInputPlace(pid: 100, pointer: CGPoint(x: 406, y: 296)), false),
            ("another pane", ScrollInputPlace(pid: 100, pointer: CGPoint(x: 400, y: 380)), true),
        ]
        for (name, there, beginsATouch) in cases {
            let rig = ScrollClassicRig(duration: 3.69, form: .oneTouch)
            let plain = ScrollClassicRig(duration: 3.69, trackpadStyle: false)
            // The second click between two display frames.
            rig.input(click, notch: click, at: 0, place: here, targetPID: 100)
            rig.input(click, notch: click, at: 0.105, place: there, targetPID: 100)
            rig.run(until: 3)
            plain.input(click, notch: click, at: 0, targetPID: 100)
            plain.input(click, notch: click, at: 0.105, targetPID: 100)
            plain.run(until: 3)

            XCTAssertEqual(rig.phaseSequence, beginsATouch ? ["began", "changed", "ended", "mayBegin", "cancelled", "began", "changed", "ended"] : ["began", "changed", "ended"], name)
            XCTAssertEqual(rig.sessions.last?.touches, beginsATouch ? 2 : 1, name)
            XCTAssertEqual(rig.moving.map { $0.frame.y }, plain.moving.map { $0.frame.y }, "\(name): the motion goes on")
            if beginsATouch {
                let atTheTick = rig.recorded.filter { abs($0.time - rig.start - 0.105) < 1e-9 }
                XCTAssertEqual(atTheTick.map { ScrollClassicRig.phaseName(scroll: $0.frame.scrollPhase ?? -1, momentum: $0.frame.momentumPhase ?? -1) },
                               ["ended", "mayBegin", "cancelled", "began"], "\(name): with the wheel event itself, and the tap after the forced end")
            }
        }
    }

    // MARK: One touch: how it ends

    /// A scroll that runs out by itself: "ended" is posted 0.2 s after the touch's last
    /// frame, with a time that far after it, at every feel and display rate. AppKit adds a
    /// glide of its own after "ended" from the speed of the touch's last frames, and takes
    /// that speed for stale when "ended" comes 0.2 s after the last one (read in AppKit
    /// 27.2). The "ended" used to follow the last frame at once, with the wheel event's time.
    /// Nothing follows it: no tap after an end that came by itself.
    func testTrackpadStyleOneTouch_endsByItselfAfterARestOfAFifthOfASecond() {
        var checked = 0
        for duration in [1.0, 2.0, 3.13, 3.69, 4.35, 4.6, 5.0] {
            for rate in [50.0, 60.0, 75.0, 100.0, 120.0, 144.0, 165.0, 240.0] {
                for (name, events) in Self.gestureScenarios {
                    let label = "\(name), glide time \(duration), \(Int(rate)) Hz"
                    let rig = ScrollClassicRig(duration: duration, rate: rate, form: .oneTouch)
                    for (clicks, time) in events { rig.input(clicks * 33.6 * 6.3, notch: 33.6 * 6.3, at: time) }
                    rig.run(until: 30)
                    checked += 1
                    XCTAssertEqual(rig.stream.last, "ended 0", label)
                    XCTAssertFalse(rig.recorded.contains { $0.frame.scrollPhase == 128 || $0.frame.scrollPhase == 8 }, "\(label): no tap")
                    guard let ended = rig.recorded.last, let endedStamp = ended.frame.timestamp,
                          let lastMoving = rig.moving.last, let movingStamp = lastMoving.frame.timestamp else {
                        XCTFail(label)
                        continue
                    }
                    let rest = Double(endedStamp - movingStamp) / 1e9
                    XCTAssertGreaterThanOrEqual(rest, 0.2005 - 1e-9, "\(label): by the frames' own times")
                    XCTAssertLessThan(rest, 0.2005 + 1 / rate, "\(label): and no later than the first display frame that allows it")
                    XCTAssertGreaterThanOrEqual(ended.time - lastMoving.time, 0.2, "\(label): posted that long after, too")
                    XCTAssertNil(Self.brokenOneTouchEnd(in: rig), label)
                }
            }
        }
        XCTAssertEqual(checked, 7 * 8 * Self.gestureScenarios.count)
    }

    /// A wheel event that comes while the touch rests goes on with the open touch: no second
    /// "began", and the page moves exactly as with the switch off, whether the scroll under
    /// the touch had already ended there or not (at the short feels it ends before the rest
    /// is over). A wheel event after the "ended" begins a touch of its own.
    func testTrackpadStyleOneTouch_aWheelEventInTheRestGoesOnWithTheOpenTouch() {
        let click = 33.6 * 6.3
        var inTheRest = 0, after = 0, afterTheScrollEnded = 0
        for duration in [1.0, 2.0, 3.13, 3.69, 4.35, 4.6] {
            for rate in [60.0, 120.0] {
                let alone = ScrollClassicRig(duration: duration, rate: rate, form: .oneTouch)
                let aloneOff = ScrollClassicRig(duration: duration, rate: rate, trackpadStyle: false)
                for each in [alone, aloneOff] {
                    each.input(click, notch: click, at: 0)
                    each.run(until: 30)
                }
                let lastFrame = alone.lastMovement
                let endedAt = (alone.firstTime(of: "ended") ?? 0)
                let offEndsAt = aloneOff.stops.first?.time ?? 0
                for later in stride(from: 0.004, through: 0.4, by: 0.0085) {
                    let label = "glide time \(duration), \(Int(rate)) Hz, a second click \(Int((later * 1000).rounded())) ms after the last frame"
                    let touch = ScrollClassicRig(duration: duration, rate: rate, form: .oneTouch)
                    let plain = ScrollClassicRig(duration: duration, rate: rate, trackpadStyle: false)
                    for each in [touch, plain] {
                        each.input(click, notch: click, at: 0)
                        each.input(click, notch: click, at: lastFrame + later)
                        each.run(until: 30)
                    }
                    XCTAssertEqual(touch.moving.map { $0.frame.y }, plain.moving.map { $0.frame.y }, "\(label): the motion")
                    XCTAssertEqual(touch.moving.map { $0.time }, plain.moving.map { $0.time }, "\(label): its times")
                    XCTAssertNil(Self.brokenGesture(in: touch, mayBeEmpty: false), label)
                    XCTAssertNil(Self.brokenOneTouchEnd(in: touch), label)
                    let touches = touch.recorded.filter { $0.frame.scrollPhase == 1 }.count
                    if lastFrame + later < endedAt - 1e-9 {
                        inTheRest += 1
                        if lastFrame + later > offEndsAt { afterTheScrollEnded += 1 }
                        XCTAssertEqual(touches, 1, "\(label): in the rest, one touch")
                        XCTAssertEqual(touch.phaseSequence, ["began", "changed", "ended"], label)
                        XCTAssertEqual(touch.stops.count, 1, label)
                    } else {
                        after += 1
                        XCTAssertEqual(touches, 2, "\(label): after the \"ended\", a touch of its own")
                        XCTAssertEqual(touch.phaseSequence, ["began", "changed", "ended", "began", "changed", "ended"], "\(label): and no tap")
                    }
                }
            }
        }
        XCTAssertGreaterThan(inTheRest, 200)
        XCTAssertGreaterThan(after, 200)
        XCTAssertGreaterThan(afterTheScrollEnded, 20, "the sweep holds wheel events that come after the scroll under the touch has ended")
    }

    /// Every way a touch is ended from outside, while the page moves and while the touch
    /// rests: "ended" at once, and right after it the two-finger tap ("may begin", then
    /// "cancelled", no distance, no glide phase), in the app that had the touch. An app that
    /// computes its own glide stops at that pair (it is what a trackpad sends when two
    /// fingers touch it and lift); "ended" alone, sooner than 0.2 s after the last frame,
    /// leaves it a speed to glide on with.
    func testTrackpadStyleOneTouch_aForcedEndIsFollowedByTheTwoFingerTap() {
        let click = 33.6 * 6.3
        let here = ScrollInputPlace(pid: 100, pointer: CGPoint(x: 400, y: 300))
        let ways: [(String, (ScrollClassicRig, Double) -> Void)] = [
            ("a left click", { rig, _ in rig.poster.stop(reason: .leftClick) }),
            ("a finger on the trackpad", { rig, _ in XCTAssertTrue(ScrollCore.stopWheelGlide(forTrackpadScrollPhase: 1, poster: rig.poster)) }),
            ("Pause", { rig, _ in rig.poster.stop() }),
            ("a restart of the tap", { rig, _ in rig.poster.stop(.TrackingEnd, reason: .tapRestarted) }),
            ("the switch", { rig, _ in rig.poster.changeFormForTests(simTrackpadEnabled: false) }),
            ("the wheel 31 pt away", { rig, time in
                rig.input(click, notch: click, at: time, place: ScrollInputPlace(pid: 100, pointer: CGPoint(x: 431, y: 300)), targetPID: 100)
            }),
            ("the wheel over another app", { rig, time in
                rig.input(click, notch: click, at: time, place: ScrollInputPlace(pid: 200, pointer: CGPoint(x: 400, y: 300)), targetPID: 200)
            }),
        ]
        var checked = 0
        for (way, end) in ways {
            // 0.1 s: the page moves. 0.5 s: the last frame went out at 0.433 s, the touch rests.
            for moment in [0.1, 0.5] {
                let label = "\(way), \(moment < 0.3 ? "while the page moves" : "in the rest")"
                let rig = ScrollClassicRig(duration: 3.69, form: .oneTouch)
                rig.input(click, notch: click, at: 0, place: here, targetPID: 100)
                rig.run(until: moment)
                XCTAssertEqual(rig.recorded.filter { $0.frame.scrollPhase == 4 }.count, 0, "\(label): the touch is open")
                let before = rig.recorded.count
                end(rig, moment)
                checked += 1
                let closing = Array(rig.targetedStream.dropFirst(before).prefix(3))
                XCTAssertEqual(closing, ["100: ended 0", "100: mayBegin 0", "100: cancelled 0"], label)
                let tap = rig.recorded.dropFirst(before).prefix(3)
                XCTAssertTrue(tap.allSatisfy { $0.frame.momentumPhase == 0 && $0.frame.y == 0 && $0.frame.x == 0 && $0.frame.lineY == 0 }, label)
                XCTAssertTrue(tap.allSatisfy { $0.time == rig.start + moment }, "\(label): at once")
                XCTAssertTrue(tap.allSatisfy { $0.frame.opensOrClosesGesture }, "\(label): kept across the stop and waited for")
                let stamps = tap.compactMap { $0.frame.timestamp }
                XCTAssertEqual(stamps, stamps.sorted(), label)
                XCTAssertEqual(Set(stamps).count, 3, "\(label): three times")
                rig.run(until: 3)
                XCTAssertNil(Self.brokenGesture(in: rig, mayBeEmpty: false, phasedOnly: true), label)
                XCTAssertNil(Self.brokenOneTouchEnd(in: rig), label)
                XCTAssertEqual(rig.recorded.filter { $0.frame.scrollPhase == 128 }.count, 1, "\(label): one tap")
            }
        }
        XCTAssertEqual(checked, 14)

        // After an end that came by itself nothing is open: a click then posts nothing.
        let rig = ScrollClassicRig(duration: 3.69, form: .oneTouch)
        rig.input(click, notch: click, at: 0)
        rig.run(until: 0.655)
        XCTAssertEqual(rig.stream.last, "ended 0")
        let count = rig.recorded.count
        rig.poster.stop(reason: .leftClick)
        rig.run(until: 3)
        XCTAssertEqual(rig.recorded.count, count, "nothing after an end by itself: \(rig.stream.suffix(3))")

        // The other forms do not send the tap.
        for form in [ScrollClassicRig.Form.flick, .oldLongTouch] {
            let other = ScrollClassicRig(duration: 3.69, form: form)
            other.input(click, notch: click, at: 0)
            other.run(until: 0.1)
            other.poster.stop(reason: .leftClick)
            XCTAssertFalse(other.recorded.contains { $0.frame.scrollPhase == 128 || $0.frame.scrollPhase == 8 }, form.rawValue)
        }
    }

    // MARK: One touch, the pointer moving while the wheel turns
    //
    // The 30 pt rule ends a touch and begins another whenever a wheel event comes more than
    // 30 pt from where the touch began. The sweeps above pass one place, so it never acted in
    // them. Here the pointer moves by 5, 31 or 200 pt with every wheel event.

    /// The place of wheel event number `index` when the pointer moves `step` pt per event.
    private static func movingPlace(_ index: Int, step: Double) -> ScrollInputPlace {
        return ScrollInputPlace(pid: 100, pointer: CGPoint(x: 400 + Double(index) * step, y: 300))
    }

    private static let movingScenarios: [(String, [(Double, Double)])] = {
        var freeSpin: [(Double, Double)] = []
        for index in 0..<100 { freeSpin.append((1, Double(index) * 0.010)) }
        var spinAndBack: [(Double, Double)] = []
        for index in 0..<27 { spinAndBack.append((1 + Double(index) * 0.1, Double(index) * 0.015)) }
        spinAndBack.append((-1, 0.45))
        return gestureScenarios + [
            ("free spin, an event every 10 ms", freeSpin),
            ("a click every 0.4 s", (0..<8).map { (1, Double($0) * 0.4) }),
            ("spin, then one click back", spinAndBack),
        ]
    }()

    /// However the pointer moves: whole touches, as many "ended" as "began", no glide event,
    /// and the frames that move the page are the switch-off path's, times and distances
    /// (with the switch off the frames follow the pointer too).
    func testTrackpadStyleOneTouch_thePointerMoving_keepsWholeTouchesAndTheMotion() {
        let notch = 33.6 * 6.3
        var failures: [String] = []
        var runs = 0
        var touchesByStep: [Double: Int] = [:]
        for step in [5.0, 31, 200] {
            for duration in [2.0, 3.13, 3.69, 4.35, 4.6, 5.0] {
                for rate in [60.0, 120.0] {
                    for (name, inputs) in Self.movingScenarios {
                        let touch = ScrollClassicRig(duration: duration, rate: rate, form: .oneTouch)
                        let plain = ScrollClassicRig(duration: duration, rate: rate, trackpadStyle: false)
                        for (index, (notches, time)) in inputs.enumerated() {
                            touch.input(notches * notch, notch: notch, at: time, place: Self.movingPlace(index, step: step), targetPID: 100)
                            plain.input(notches * notch, notch: notch, at: time, targetPID: 100)
                        }
                        touch.run(until: 30)
                        plain.run(until: 30)
                        runs += 1
                        let label = "the pointer \(step) pt per wheel event, \(name), Duration \(duration), \(Int(rate)) Hz"
                        if let broken = Self.brokenGesture(in: touch, mayBeEmpty: false) { failures.append("\(label): \(broken)") }
                        if let broken = Self.brokenOneTouchEnd(in: touch) { failures.append("\(label): \(broken)") }
                        let began = touch.recorded.filter { $0.frame.scrollPhase == 1 }.count
                        let ended = touch.recorded.filter { $0.frame.scrollPhase == 4 }.count
                        if began != ended { failures.append("\(label): \(began) began, \(ended) ended") }
                        if touch.recorded.contains(where: { ($0.frame.momentumPhase ?? 0) != 0 }) { failures.append("\(label): a glide event") }
                        if touch.moving.map({ $0.frame.y }) != plain.moving.map({ $0.frame.y }) {
                            failures.append("\(label): \(touch.postedY) px in \(touch.moving.count) frames, switch off \(plain.postedY) px in \(plain.moving.count)")
                        } else if touch.moving.map({ $0.time }) != plain.moving.map({ $0.time }) {
                            failures.append("\(label): the frames come at other times")
                        }
                        if name == "spin" && duration == 3.69 && rate == 60 { touchesByStep[step] = began }
                    }
                }
            }
        }
        XCTAssertEqual(runs, 3 * 6 * 2 * 11)
        XCTAssertTrue(failures.isEmpty, "\(failures.count) broken:\n" + failures.prefix(30).joined(separator: "\n"))
        // The rule did act: a spin of 27 wheel events is one touch while the pointer stays
        // within 30 pt of where the touch began, and a touch per wheel event when it jumps.
        XCTAssertEqual(touchesByStep[5], 4, "5 pt per event: a new touch every seventh event")
        XCTAssertEqual(touchesByStep[31], 27)
        XCTAssertEqual(touchesByStep[200], 27)
    }

    /// The same with a stop at any moment, by a click and by the tap's restart.
    func testTrackpadStyleOneTouch_thePointerMoving_aStopAtAnyMomentLeavesWholeTouches() {
        let notch = 33.6 * 6.3
        var failures: [String] = []
        var stops = 0
        for step in [31.0, 200] {
            for duration in [2.0, 3.69, 5.0] {
                for (name, inputs) in Self.movingScenarios {
                    for stopAt in stride(from: 0.004, through: 1.2, by: 0.011) {
                        for restart in [false, true] {
                            let rig = ScrollClassicRig(duration: duration, form: .oneTouch)
                            for (index, (notches, time)) in inputs.enumerated() where time <= stopAt {
                                rig.input(notches * notch, notch: notch, at: time, place: Self.movingPlace(index, step: step), targetPID: 100)
                            }
                            rig.run(until: stopAt)
                            if restart {
                                rig.poster.stop(.TrackingEnd, reason: .tapRestarted)
                            } else {
                                rig.poster.stop(reason: .leftClick)
                            }
                            stops += 1
                            if let broken = Self.brokenOneTouchEnd(in: rig) {
                                failures.append("the pointer \(step) pt, \(name), Duration \(duration), \(restart ? "a tap restart" : "a click") at \(Int(stopAt * 1000)) ms: \(broken)")
                            }
                            if let broken = Self.brokenGesture(in: rig, mayBeEmpty: true) {
                                failures.append("the pointer \(step) pt, \(name), Duration \(duration), \(restart ? "a tap restart" : "a click") at \(Int(stopAt * 1000)) ms: \(broken)")
                            }
                        }
                    }
                }
            }
        }
        XCTAssertEqual(stops, 2 * 3 * 11 * 109 * 2)
        XCTAssertTrue(failures.isEmpty, "\(failures.count) broken:\n" + failures.prefix(30).joined(separator: "\n"))
    }

    /// And with the app's kind found in mid-scroll (the one touch goes on as a flick): at any
    /// wheel event of a gesture, and at any moment of a click's tail with a second click then.
    func testTrackpadStyleOneTouch_thePointerMoving_theFormChangingToAFlickLeavesWholeGestures() {
        let notch = 33.6 * 6.3
        var failures: [String] = []
        var runs = 0
        for step in [0.0, 31, 200] {
            for duration in [2.0, 3.69, 5.0] {
                for (name, inputs) in Self.movingScenarios {
                    for answerBefore in 1..<max(2, min(inputs.count, 8)) {
                        let rig = ScrollClassicRig(duration: duration, form: .oneTouch)
                        for (index, (notches, time)) in inputs.enumerated() {
                            if index == answerBefore {
                                rig.run(until: time)
                                rig.poster.setConfigForTests(simTrackpadEnabled: true, flick: true)
                            }
                            rig.input(notches * notch, notch: notch, at: time, place: Self.movingPlace(index, step: step), targetPID: 100)
                        }
                        rig.run(until: 30)
                        runs += 1
                        if let broken = Self.brokenGesture(in: rig, mayBeEmpty: false) {
                            failures.append("the pointer \(step) pt, \(name), Duration \(duration), a flick from wheel event \(answerBefore + 1): \(broken)")
                        }
                    }
                }
            }
        }
        for step in [0.0, 200] {
            for duration in [2.0, 3.69, 4.6, 5.0] {
                for second in stride(from: 0.05, through: 3.6, by: 0.013) {
                    let rig = ScrollClassicRig(duration: duration, form: .oneTouch)
                    rig.input(notch, notch: notch, at: 0, place: Self.movingPlace(0, step: step), targetPID: 100)
                    rig.run(until: second)
                    rig.poster.setConfigForTests(simTrackpadEnabled: true, flick: true)
                    rig.input(notch, notch: notch, at: second, place: Self.movingPlace(1, step: step), targetPID: 100)
                    rig.run(until: 30)
                    runs += 1
                    if let broken = Self.brokenGesture(in: rig, mayBeEmpty: false) {
                        failures.append("the pointer \(step) pt, Duration \(duration), a click, the answer and a second click at \(Int(second * 1000)) ms: \(broken)")
                    }
                }
            }
        }
        XCTAssertGreaterThan(runs, 2_500)
        XCTAssertTrue(failures.isEmpty, "\(failures.count) broken:\n" + failures.prefix(30).joined(separator: "\n"))
    }

    // MARK: Trackpad-style, as the old long touch (the evaluation switch)
    //
    // What every app that is not Chromium-based got until the one touch: a touch for as long as
    // the wheel turns, and the rest of the scroll as its glide. Kept behind
    // `TrackpadStyleEvaluation` so the two can be compared on a real Mac; these tests go with it.

    /// The touch ends when the wheel has been still for 0.18 s; a tick after that begins a new
    /// one at once. Every frame keeps the wheel event's own time.
    func testTrackpadStyleLongTouch_touchLastsWhileTheWheelTurns() {
        let rig = ScrollClassicRig(duration: 4.35, form: .oldLongTouch)
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
        XCTAssertTrue(rig.recorded.allSatisfy { $0.frame.timestamp != nil }, "and its own time")
        XCTAssertEqual(rig.stops.count, 1)
    }

    /// What an AppKit list follows is the touch, and the old long touch ends when the wheel has
    /// been still for 0.18 s, whatever the glide time. So the longer the glide, the less of a
    /// scroll is touch: one click at each feel, in px of touch of the px posted. (This used to
    /// be asserted at Smooth only, as "more than 65 %".) The rest goes out as glide events,
    /// which such a list does not follow.
    func testTrackpadStyleLongTouch_whatTheTouchCarriesAtEachGlideTime() {
        let click = 33.6 * 6.3
        //                       Duration  touch  posted
        let expected: [(String, Double, Double, Double)] = [
            ("Direct", 2.0, 203, 209), ("Quick", 3.13, 158, 207), ("Smooth", 3.69, 135, 205),
            ("Glide", 4.35, 92, 205), ("Float", 4.6, 69, 205), ("glide time 5.0", 5.0, 25, 205),
        ]
        for (feel, duration, touch, posted) in expected {
            let rig = ScrollClassicRig(duration: duration, form: .oldLongTouch)
            rig.input(click, notch: click, at: 0)
            rig.run(until: 30)
            let inTheTouch = rig.recorded.filter { $0.frame.scrollPhase == 2 }.reduce(0) { $0 + $1.frame.y }
            XCTAssertEqual(inTheTouch, touch, feel)
            XCTAssertEqual(rig.postedY, posted, feel)
            XCTAssertEqual(rig.firstTime(of: "ended") ?? -1, 11.0 / 60.0, accuracy: 1e-6, "\(feel): the touch ends 0.18 s after the click")
        }
    }

    /// The forms differ in the phases only: every frame that moves the page is the same as a
    /// flick's (which is the switch-off path's, `testTrackpadStyle_keepsEveryFrameOfTheMotion`).
    /// As a flick almost none of a scroll is touch, which is why an AppKit list stopped short
    /// with it.
    func testTrackpadStyleLongTouch_movesThePageAsTheFlickDoes() {
        let scenarios: [(String, [(Double, Double)], Double)] = [
            ("click", [(211.68, 0)], 0.65),
            ("spin", Self.spin, 0.85),
        ]
        for (name, inputs, share) in scenarios {
            let longTouch = ScrollClassicRig(duration: 3.69, form: .oldLongTouch)
            let flick = ScrollClassicRig(duration: 3.69, form: .flick)
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
            XCTAssertEqual(longTouch.moving.map { $0.time }, flick.moving.map { $0.time }, "\(name): at the same times")
        }
    }

    /// A click after the glide has ended is a new flick.
    func testTrackpadStyle_clickAfterTheGlide_isANewFlick() {
        let rig = ScrollClassicRig(duration: 3.69, trackpadStyle: true)
        rig.input(33.6 * 6.3, notch: 33.6 * 6.3, at: 0)
        rig.input(33.6 * 6.3, notch: 33.6 * 6.3, at: 1.2)
        rig.run(until: 3)

        let flick = ["began ×1", "changed ×1", "ended ×1", "momentumBegan ×1", "momentumChanged ×23", "momentumEnded ×1"]
        XCTAssertEqual(rig.phaseRuns, flick + flick)
        XCTAssertEqual(rig.stops.count, 2)
    }

    // MARK: The flick as Chromium and Gecko need it

    /// Scrolls of every size for the flick's sweeps: one wheel event from 1 px to a click at
    /// the owner's Speed, at glide times up to the longest, three display rates, two dead zones.
    private static func flickSweep(_ body: (_ rig: ScrollClassicRig, _ label: String) -> Void) -> Int {
        var runs = 0
        for duration in [1.0, 3.13, 3.69, 4.35, 4.6, 5.0] {
            for rate in [30.0, 60.0, 120.0, 144.0] {
                for deadZone in [0.25, 1.0] {
                    for pixels in [1.0, 2, 3, 4, 6, 8, 10, 12, 16, 24, 33.6, 60, 211.68] {
                        let rig = ScrollClassicRig(duration: duration, rate: rate, deadZone: deadZone, form: .flick)
                        rig.input(pixels, notch: 33.6, at: 0)
                        rig.run(until: 30)
                        runs += 1
                        body(rig, "\(pixels) px, glide time \(duration), \(Int(rate)) Hz, dead zone \(deadZone)")
                    }
                    for (name, events) in gestureScenarios {
                        let rig = ScrollClassicRig(duration: duration, rate: rate, deadZone: deadZone, form: .flick)
                        for (clicks, time) in events { rig.input(clicks * 33.6 * 6.3, notch: 33.6 * 6.3, at: time) }
                        rig.run(until: 30)
                        runs += 1
                        body(rig, "\(name), glide time \(duration), \(Int(rate)) Hz, dead zone \(deadZone)")
                    }
                }
            }
        }
        return runs
    }

    /// "Began" is never a frame without distance: it is the first frame that moves the page,
    /// as a trackpad's "began" carries its first pixel, and every frame of the touch moves
    /// the page. (Gecko picks the scroller for the whole gesture from the first event and
    /// finds none for an event without distance: it then keeps the innermost box under the
    /// pointer, and the page under a box that scrolls only sideways does not move. Chromium
    /// makes the later events of a gesture non-blocking only after a "began" with a distance.)
    /// A scroll that moves nothing sends nothing.
    func testTrackpadStyleFlick_beganIsTheFirstFrameThatMovesThePage() {
        var failures: [String] = []
        let runs = Self.flickSweep { rig, label in
            for item in rig.recorded where item.frame.scrollPhase == 1 || item.frame.scrollPhase == 2 {
                if item.frame.y == 0 {
                    failures.append("\(label): a touch frame without distance at \(Int(((item.time - rig.start) * 1000).rounded())) ms")
                    break
                }
            }
            if rig.moving.isEmpty && !rig.recorded.isEmpty {
                failures.append("\(label): frames for a scroll that moves nothing: \(rig.stream)")
            }
            if let first = rig.recorded.first, first.frame.scrollPhase != 1 {
                failures.append("\(label): begins with \(rig.stream.first ?? "")")
            }
            if let broken = Self.brokenGesture(in: rig, mayBeEmpty: rig.moving.isEmpty) {
                failures.append("\(label): \(broken)")
            }
        }
        XCTAssertEqual(runs, 6 * 4 * 2 * (13 + Self.gestureScenarios.count))
        XCTAssertTrue(failures.isEmpty, "\(failures.count):\n" + failures.prefix(30).joined(separator: "\n"))
    }

    /// "Ended" and "momentum began" go out in one display frame, "ended" first, at every
    /// glide time, rate and size of scroll: Chromium drops a glide whose "momentum began"
    /// comes more than 100 ms after "ended". ("Ended" used to go out when the touch was
    /// over, while "momentum began" waited for the first frame that came to a whole pixel:
    /// for a scroll of a few pixels at a long glide time that was eight frames or more.) An
    /// "ended" with no glide after it is the last frame of its gesture.
    func testTrackpadStyleFlick_endedGoesOutWithMomentumBegan() {
        var failures: [String] = []
        var glides = 0
        var heldAcrossFrames = 0
        let runs = Self.flickSweep { rig, label in
            for (index, item) in rig.recorded.enumerated() where item.frame.scrollPhase == 4 {
                guard index + 1 < rig.recorded.count, rig.recorded[index + 1].frame.momentumPhase == 1 else { continue }
                let next = rig.recorded[index + 1]
                glides += 1
                if next.time != item.time {
                    failures.append("\(label): \"momentum began\" \(Int(((next.time - item.time) * 1000).rounded())) ms after \"ended\"")
                }
                let apart = Double((next.frame.timestamp ?? 0) - (item.frame.timestamp ?? 0)) / 1e9
                if !(apart > 0 && apart < 0.1) {
                    failures.append("\(label): their times are \(apart) s apart")
                }
                if next.frame.y == 0 {
                    failures.append("\(label): a \"momentum began\" without distance")
                }
                // The touch's last frame was more than a display frame before: the "ended" waited.
                if index > 0, item.time - rig.recorded[index - 1].time > rig.frameInterval * 1.5 {
                    heldAcrossFrames += 1
                }
            }
        }
        XCTAssertEqual(runs, 6 * 4 * 2 * (13 + Self.gestureScenarios.count))
        XCTAssertGreaterThan(glides, 500)
        XCTAssertGreaterThan(heldAcrossFrames, 0, "the sweep holds scrolls whose glide's first frame comes late")
        XCTAssertTrue(failures.isEmpty, "\(failures.count):\n" + failures.prefix(30).joined(separator: "\n"))
    }

    /// The touch holds two frames that move the page whenever a glide follows it: an app
    /// takes the speed for a bounce from two frames. On a slow display (or after a late first
    /// frame) 45 ms were over after one.
    func testTrackpadStyleFlick_theTouchHoldsTwoMovingFramesBeforeAGlide() {
        var failures: [String] = []
        var touchesWithAGlide = 0
        let runs = Self.flickSweep { rig, label in
            var inTouch = 0
            for item in rig.recorded {
                switch (item.frame.scrollPhase, item.frame.momentumPhase) {
                case (1, _): inTouch = item.frame.y != 0 ? 1 : 0
                case (2, _): inTouch += item.frame.y != 0 ? 1 : 0
                case (_, 1):
                    touchesWithAGlide += 1
                    if inTouch < 2 { failures.append("\(label): a glide after a touch of \(inTouch) moving frames") }
                default: break
                }
            }
        }
        XCTAssertEqual(runs, 6 * 4 * 2 * (13 + Self.gestureScenarios.count))
        XCTAssertGreaterThan(touchesWithAGlide, 500)
        XCTAssertTrue(failures.isEmpty, "\(failures.count):\n" + failures.prefix(30).joined(separator: "\n"))

        // At 30 Hz: frames at 33 and 67 ms are the touch, the glide begins at 100 ms.
        let slow = ScrollClassicRig(duration: 3.69, rate: 30, form: .flick)
        slow.input(33.6 * 6.3, notch: 33.6 * 6.3, at: 0)
        slow.run(until: 3)
        XCTAssertEqual(Array(slow.phaseRuns.prefix(4)), ["began ×1", "changed ×1", "ended ×1", "momentumBegan ×1"])
        XCTAssertEqual(slow.firstTime(of: "momentumBegan") ?? -1, 0.1, accuracy: 1e-6)
    }

    /// Wheel events that come before the first frame has moved the page (a quick turn, a
    /// display link that starts late) all belong to the one touch that waits: one "began".
    func testTrackpadStyleFlick_wheelEventsBeforeTheFirstFrame_areOneTouch() {
        let rig = ScrollClassicRig(duration: 3.69, form: .flick)
        rig.input(33.6 * 6.3, notch: 33.6 * 6.3, at: 0)
        XCTAssertTrue(rig.recorded.isEmpty, "nothing goes out with the wheel event")
        XCTAssertTrue(rig.phases.beganIsWaiting)
        rig.input(33.6 * 6.3, notch: 33.6 * 6.3, at: 0.004)
        rig.input(33.6 * 6.3, notch: 33.6 * 6.3, at: 0.009)
        XCTAssertTrue(rig.recorded.isEmpty)
        rig.run(until: 4)
        XCTAssertEqual(rig.phaseSequence, ["began", "changed", "ended", "momentumBegan", "momentumChanged", "momentumEnded"])
        XCTAssertEqual(rig.sessions.last?.touches, 1)
        XCTAssertEqual(rig.postedY, 628, accuracy: 12, "all three clicks")

        // A stop before any frame: the app got nothing and gets nothing.
        let stopped = ScrollClassicRig(duration: 3.69, form: .flick)
        stopped.input(33.6 * 6.3, notch: 33.6 * 6.3, at: 0)
        stopped.poster.stop(reason: .leftClick)
        XCTAssertTrue(stopped.recorded.isEmpty, "no \"began\" went out, so no \"ended\" does: \(stopped.stream)")
        stopped.input(33.6 * 6.3, notch: 33.6 * 6.3, at: 0.1)
        stopped.poster.stop(.TrackingEnd, reason: .tapRestarted)
        XCTAssertTrue(stopped.recorded.isEmpty, "\(stopped.stream)")
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
    /// A frame that moves the page carries its display frame's time; one without distance
    /// from a display frame ("ended") a time just after the display frame before.
    func testTrackpadStyle_framesCarryTheirOwnTime() throws {
        let rig = ScrollClassicRig(duration: 3.69, trackpadStyle: true)
        for (points, time) in [(1.0, 0.0), (12, 0.024), (54, 0.038), (78, 0.060)] {
            rig.input(max(33.6, points) * 6.3, notch: 33.6 * 6.3, at: time)
        }
        rig.run(until: 3)

        for item in rig.recorded {
            let timestamp = try XCTUnwrap(item.frame.timestamp)
            if item.frame.y != 0 {
                XCTAssertEqual(Double(timestamp) / 1e9, item.time, accuracy: 1e-6)
            } else {
                XCTAssertLessThanOrEqual(Double(timestamp) / 1e9, item.time + 1e-6)
                XCTAssertGreaterThan(Double(timestamp) / 1e9, item.time - rig.frameInterval)
            }
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

    // MARK: Every frame that carries phases: its time, its line delta, one phase

    /// In every form, at every glide time and display rate: every frame that carries phases
    /// has a time of its own, later than the frame before it, and two frames that move the
    /// page are exactly as far apart in time as their display frames. (As one touch and as
    /// the old long touch every frame carried the wheel event's time: AppKit measured a
    /// speed only between two wheel events and kept it to the end, and then glided on by
    /// itself; Chromium, WebKit and Gecko found no speed for the bounce.)
    func testTrackpadStyle_everyForm_everyFrameHasItsOwnEvenTime() {
        var checked = 0
        for form in ScrollClassicRig.Form.allCases {
            for duration in [1.0, 3.69, 4.6, 5.0] {
                for rate in [60.0, 120.0, 144.0] {
                    for (name, events) in Self.gestureScenarios {
                        let label = "\(form.rawValue), \(name), glide time \(duration), \(Int(rate)) Hz"
                        let rig = ScrollClassicRig(duration: duration, rate: rate, form: form)
                        for (clicks, time) in events { rig.input(clicks * 33.6 * 6.3, notch: 33.6 * 6.3, at: time) }
                        rig.run(until: 8)
                        checked += 1

                        var lastStamp: UInt64 = 0
                        var lastMoving: (stamp: UInt64, time: Double)?
                        for item in rig.recorded {
                            guard let stamp = item.frame.timestamp else {
                                XCTFail("\(label): a frame without a time of its own at \(item.time - rig.start)")
                                break
                            }
                            guard stamp > lastStamp else {
                                XCTFail("\(label): the time does not go on at \(item.time - rig.start)")
                                break
                            }
                            lastStamp = stamp
                            guard item.frame.y != 0 else { continue }
                            if let last = lastMoving {
                                let apart = Double(stamp - last.stamp) / 1e9
                                guard abs(apart - (item.time - last.time)) < 1e-6 else {
                                    XCTFail("\(label): two moving frames \(item.time - last.time) s apart carry times \(apart) s apart")
                                    break
                                }
                            }
                            lastMoving = (stamp, item.time)
                        }
                    }
                }
            }
        }
        XCTAssertEqual(checked, ScrollClassicRig.Form.allCases.count * 4 * 3 * Self.gestureScenarios.count)
    }

    /// The display link's callback runs a little early or late every time; the frames' times
    /// still step by the display's interval, the value each frame's distance was computed
    /// with. (The flick took the clock when a frame was made: 1 ms between two callbacks
    /// after a late one made Chromium's bounce 17 times too large.) After a real stall the
    /// times start again from the clock.
    func testTrackpadStyle_unevenCallbacks_stillGiveEvenTimes() throws {
        for form in ScrollClassicRig.Form.allCases {
            let poster = ScrollPoster(phases: ScrollPhase(), dispatchContext: ScrollDispatchContext())
            var frames: [ScrollOutgoingFrame] = []
            poster.frameRecorderForTests = { frames.append($0) }
            var clock = 100.0
            poster.eventClockForTests = { UInt64((clock * 1e9).rounded()) }
            poster.setConfigForTests(simTrackpadEnabled: true, flick: form == .flick, oldLongTouch: form == .oldLongTouch)
            let transition = OPTIONS_SCROLL_DEFAULT.generateDurationTransition(with: 3.69)
            poster.inputForTests(ScrollPosterInput(y: 33.6 * 6.3 * 4, x: 0, notch: 33.6 * 6.3, duration: transition), at: clock)
            // Callbacks up to 6 ms late, in no order.
            let late = [0.001, 0.006, 0.0, 0.004, 0.002, 0.0055, 0.0005, 0.003]
            for index in 1...20 {
                clock = 100.0 + Double(index) / 60.0 + late[index % late.count]
                _ = poster.displayLinkFrameForTests(frameInterval: 1.0 / 60.0, now: clock)
            }
            let moving = frames.filter { $0.y != 0 }
            XCTAssertGreaterThan(moving.count, 15, form.rawValue)
            for (later, earlier) in zip(moving.dropFirst(), moving) {
                let apart = Double(try XCTUnwrap(later.timestamp) - (try XCTUnwrap(earlier.timestamp))) / 1e9
                XCTAssertEqual(apart, 1.0 / 60.0, accuracy: 1e-6, "\(form.rawValue): one display frame apart, whenever the callbacks ran")
            }
            // The link stalls for 0.2 s: the next frame's time is the clock's again.
            let before = moving.count
            clock = 100.0 + 21.0 / 60.0 + 0.2
            _ = poster.displayLinkFrameForTests(frameInterval: 1.0 / 60.0, now: clock)
            let after = frames.filter { $0.y != 0 }
            XCTAssertEqual(after.count, before + 1, form.rawValue)
            XCTAssertEqual(Double(try XCTUnwrap(after.last?.timestamp)) / 1e9, clock, accuracy: 1e-6, "\(form.rawValue): after a stall, from the clock again")
            poster.stop()
        }
    }

    /// A poster driven callback by callback: every callback's own reading of the clock and
    /// the interval it reports, and what it posted.
    private final class CallbackRun {
        let poster = ScrollPoster(phases: ScrollPhase(), dispatchContext: ScrollDispatchContext())
        var clock = 100.0
        /// Every posted frame, with the callback that made it (-1: the main thread), that
        /// callback's interval and its reading of the clock.
        private(set) var posted: [(frame: ScrollOutgoingFrame, callback: Int, interval: Double, now: Double)] = []
        private var callback = -1
        private var interval = 0.0
        private var callbacks = 0

        init(form: ScrollClassicRig.Form) {
            poster.frameRecorderForTests = { [unowned self] in self.posted.append(($0, self.callback, self.interval, self.clock)) }
            poster.eventClockForTests = { [unowned self] in UInt64((self.clock * 1e9).rounded()) }
            poster.setConfigForTests(simTrackpadEnabled: true, flick: form == .flick, oldLongTouch: form == .oldLongTouch)
        }

        func wheel(_ pixels: Double = 33.6 * 6.3 * 4, at time: Double) {
            clock = time
            let transition = OPTIONS_SCROLL_DEFAULT.generateDurationTransition(with: 3.69)
            poster.inputForTests(ScrollPosterInput(y: pixels, x: 0, notch: 33.6 * 6.3, duration: transition), at: time)
        }

        func frame(at time: Double, interval: Double = 1.0 / 60.0) {
            clock = time
            callback = callbacks
            callbacks += 1
            self.interval = interval
            _ = poster.displayLinkFrameForTests(frameInterval: interval, now: time)
            callback = -1
        }

        var stamps: [UInt64] { return posted.compactMap { $0.frame.timestamp } }
    }

    /// A callback that runs more than a frame late, and a display that changes its rate in
    /// mid-scroll, in every form: the time between two frames that move the page, made by
    /// callbacks that follow each other, is never less than half the interval the later
    /// one's distance was computed with, and never more than the time between the two
    /// callbacks and one interval more. So what an app reads as the speed (distance / step
    /// between the two times) is at most twice the real one. The grid used to be put back
    /// on the clock when it had come more than a frame ahead: the next frame's time fell
    /// before the last one's and came out 1 ms after it, 17 times the speed at 60 Hz.
    func testTrackpadStyle_aLateCallbackOrAChangeOfRate_keepsTheSpeedWithinTwiceTheRealOne() throws {
        typealias Callback = (time: Double, interval: Double)
        func schedule(late: Double, nextAtOnce: Bool) -> [Callback] {
            var out: [Callback] = []
            for index in 1...40 {
                var time = 100.0 + Double(index) / 60.0
                if index == 10 { time += late / 60.0 }
                if index == 11 {
                    if !nextAtOnce && late >= 1 { continue }
                    time = max(time, 100.0 + (10.0 + late) / 60.0 + 0.0002)
                }
                if index == 12 && late >= 2 {
                    if !nextAtOnce { continue }
                    time = max(time, 100.0 + (10.0 + late) / 60.0 + 0.0004)
                }
                out.append((time, 1.0 / 60.0))
            }
            return out
        }
        var rateChange: [Callback] = []
        var time = 100.0
        for index in 0..<50 {
            let interval = (15..<35).contains(index) ? 1.0 / 120.0 : 1.0 / 60.0
            time += interval
            rateChange.append((time, interval))
        }
        // The rate goes up while the grid is ahead of the clock (the callbacks before ran early).
        var rateChangeAhead: [Callback] = []
        time = 100.0
        for index in 0..<50 {
            let interval = (15..<35).contains(index) ? 1.0 / 120.0 : 1.0 / 60.0
            time += index < 15 && index > 0 ? interval * 0.92 : interval
            rateChangeAhead.append((time, interval))
        }
        let cases: [(String, [Callback])] = [
            ("a callback 1.3 frames late, the next at once", schedule(late: 1.3, nextAtOnce: true)),
            ("a callback 1.3 frames late, the next a frame on", schedule(late: 1.3, nextAtOnce: false)),
            ("a callback 2.5 frames late, the next at once", schedule(late: 2.5, nextAtOnce: true)),
            ("a callback 2.5 frames late, the next ones skipped", schedule(late: 2.5, nextAtOnce: false)),
            ("60 Hz to 120 Hz and back", rateChange),
            ("60 Hz to 120 Hz and back, the grid ahead of the clock", rateChangeAhead),
        ]
        for form in ScrollClassicRig.Form.allCases {
            for (name, callbacks) in cases {
                let run = CallbackRun(form: form)
                run.wheel(33.6 * 6.3 * 12, at: 100.0)
                for callback in callbacks { run.frame(at: callback.time, interval: callback.interval) }
                let label = "\(form.rawValue), \(name)"
                let moving = run.posted.filter { $0.frame.y != 0 }
                XCTAssertGreaterThan(moving.count, 25, label)
                var pairs = 0
                for (later, earlier) in zip(moving.dropFirst(), moving) where later.callback == earlier.callback + 1 {
                    pairs += 1
                    let step = Double(try XCTUnwrap(later.frame.timestamp) - (try XCTUnwrap(earlier.frame.timestamp))) / 1e9
                    XCTAssertGreaterThanOrEqual(step, later.interval / 2 - 1e-6, "\(label): a frame of \(later.frame.y) px \(step * 1000) ms after the one before: more than twice its speed")
                    XCTAssertLessThanOrEqual(step, (later.now - earlier.now) + later.interval + 1e-6, "\(label): \(step * 1000) ms")
                }
                XCTAssertGreaterThan(pairs, 20, label)
                XCTAssertEqual(run.stamps, run.stamps.sorted(), label)
                XCTAssertEqual(Set(run.stamps).count, run.stamps.count, label)
                run.poster.stop()
            }
        }
    }

    /// The times never go back from one scroll to the next, in any form: across a click, a
    /// restart of the tap and a change of form, also when the frames before ran a little
    /// ahead of the clock and the next wheel event comes a millisecond after the stop. (A
    /// stop used to forget the last time: the next scroll's "began" could carry a time
    /// before the "ended" or "cancelled" that had just gone out.)
    func testTrackpadStyle_timesNeverGoBackFromOneScrollToTheNext() {
        let ends: [(String, (CallbackRun, ScrollClassicRig.Form) -> Void)] = [
            ("a click", { run, _ in run.poster.stop(reason: .leftClick) }),
            ("a restart of the tap", { run, _ in run.poster.stop(.TrackingEnd, reason: .tapRestarted) }),
            ("the switch off and on", { run, form in
                run.poster.changeFormForTests(simTrackpadEnabled: false)
                run.poster.changeFormForTests(simTrackpadEnabled: true, flick: form == .flick, oldLongTouch: form == .oldLongTouch)
            }),
            ("another form", { run, form in
                run.poster.setConfigForTests(simTrackpadEnabled: true, flick: form != .flick)
            }),
        ]
        for form in ScrollClassicRig.Form.allCases {
            for (name, end) in ends {
                for stopAfter in [3, 6, 9, 14] {
                    let label = "\(form.rawValue), \(name) after \(stopAfter) frames"
                    let run = CallbackRun(form: form)
                    run.wheel(at: 100.0)
                    // Callbacks that run early: the grid comes to be most of a frame ahead of the clock.
                    var time = 100.0
                    for _ in 0..<stopAfter {
                        time += 0.0125
                        run.frame(at: time)
                    }
                    run.clock = time + 0.0005
                    end(run, form)
                    run.wheel(at: time + 0.0015)
                    for _ in 0..<12 {
                        time += 1.0 / 60.0
                        run.frame(at: time)
                    }
                    run.poster.stop()
                    let stamps = run.stamps
                    XCTAssertGreaterThan(stamps.count, 10, label)
                    XCTAssertEqual(stamps.count, run.posted.count, label)
                    for (later, earlier) in zip(stamps.dropFirst(), stamps) where later <= earlier {
                        XCTFail("\(label): a time \(Double(earlier - later) / 1e6) ms before the frame before it")
                        break
                    }
                }
            }
        }
    }

    /// A frame made on the main thread (a stop's closing frames, the tap, the one touch's
    /// "began") carries the clock's time, not a display frame's: no display frame is being
    /// worked off then.
    func testTrackpadStyle_aFrameFromTheMainThreadCarriesTheClocksTime() {
        let run = CallbackRun(form: .oneTouch)
        run.wheel(at: 100.0)
        XCTAssertEqual(run.stamps, [100_000_000_000], "\"began\": the clock at the wheel event")
        for index in 1...5 { run.frame(at: 100.0 + Double(index) / 60.0) }
        run.clock = 100.3
        let before = run.posted.count
        run.poster.stop(reason: .leftClick)
        let closing = run.posted.dropFirst(before).compactMap { $0.frame.timestamp }
        XCTAssertEqual(closing, [100_300_000_000, 100_301_000_000, 100_302_000_000], "\"ended\" and the tap: the clock at the click, each a millisecond on")

        for form in [ScrollClassicRig.Form.flick, .oldLongTouch] {
            let other = CallbackRun(form: form)
            other.wheel(at: 100.0)
            for index in 1...5 { other.frame(at: 100.0 + Double(index) / 60.0) }
            other.clock = 100.3
            let count = other.posted.count
            other.poster.stop(reason: .leftClick)
            XCTAssertEqual(other.posted.dropFirst(count).first?.frame.timestamp, 100_300_000_000, form.rawValue)
        }
    }

    /// A Step that is no sane number (a hand-edited preference: 1e25 is finite, so the event
    /// is taken) gives frames no `Int64` holds. The line delta is then the largest number
    /// there is, and nothing traps: converting it trapped, with the switch on.
    func testAStepThatIsNoSaneNumber_doesNotTrap() {
        XCTAssertEqual(ScrollOutgoingFrame.wholeLines(1e25), .max)
        XCTAssertEqual(ScrollOutgoingFrame.wholeLines(-1e25), .min)
        XCTAssertEqual(ScrollOutgoingFrame.wholeLines(.nan), 0)
        XCTAssertEqual(ScrollOutgoingFrame.wholeLines(.infinity), 0)
        XCTAssertEqual(ScrollOutgoingFrame.wholeLines(3.9), 3)
        XCTAssertEqual(ScrollOutgoingFrame.wholeLines(-2.2), -2)
        XCTAssertEqual(ScrollOutgoingFrame.wholeLines(0), 0)
        for form in ScrollClassicRig.Form.allCases {
            let rig = ScrollClassicRig(duration: 3.69, form: form)
            rig.input(1e25, notch: 1e25, at: 0)
            rig.run(until: 0.5)
            rig.poster.stop()
            XCTAssertTrue(rig.recorded.contains { $0.frame.lineY == .max }, "\(form.rawValue): frames went out")
        }
        XCTAssertNil(ScrollPoster.nanoseconds(.infinity))
        XCTAssertNil(ScrollPoster.nanoseconds(1e300))
        XCTAssertNil(ScrollPoster.nanoseconds(-1))
        XCTAssertEqual(ScrollPoster.nanoseconds(100.5), 100_500_000_000)
    }

    /// Never a touch phase and a momentum phase on one frame: Chromium asserts on such an
    /// event (fatal from Chromium 163, over Chrome's own toolbar and tab strip).
    func testTrackpadStyle_noFrameCarriesATouchPhaseAndAMomentumPhase() {
        for phase in PhaseValueMapping.keys {
            let scroll = PhaseValueMapping[phase]?[.Scroll] ?? -1
            let momentum = PhaseValueMapping[phase]?[.Momentum] ?? -1
            XCTAssertTrue(scroll == 0 || momentum == 0, "\(phase): \(scroll), \(momentum)")
        }
        var frames = 0
        for form in ScrollClassicRig.Form.allCases {
            for duration in [1.0, 3.69, 5.0] {
                for (name, events) in Self.gestureScenarios {
                    let rig = ScrollClassicRig(duration: duration, form: form)
                    for (clicks, time) in events { rig.input(clicks * 33.6 * 6.3, notch: 33.6 * 6.3, at: time) }
                    rig.run(until: 0.2)
                    rig.poster.stop(reason: .leftClick)
                    rig.input(33.6 * 6.3, notch: 33.6 * 6.3, at: 0.25)
                    rig.run(until: 8)
                    for item in rig.recorded {
                        frames += 1
                        guard let scroll = item.frame.scrollPhase, let momentum = item.frame.momentumPhase else {
                            XCTFail("\(form.rawValue), \(name): a frame without phases")
                            continue
                        }
                        if scroll != 0 && momentum != 0 {
                            XCTFail("\(form.rawValue), \(name), glide time \(duration): a frame with touch phase \(scroll) and momentum phase \(momentum)")
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(frames, 5_000)
    }

    /// A frame that carries phases is written with its own line delta and fixed-point delta
    /// (a tenth of its pixels) and a scroll count of 0. It used to keep the wheel event's:
    /// each of a click's 26 frames said "one line" (AppKit's legacy `deltaY`), and a count of
    /// 3 or more would have made AppKit multiply every delta. A frame without phases keeps
    /// all three as they are on the wheel event, as it always did.
    func testFrame_withPhases_carriesItsOwnLineDeltaAndNoScrollCount() throws {
        let template = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 3, wheel2: 2, wheel3: 0))
        template.setIntegerValueField(.scrollWheelEventScrollCount, value: 5)
        XCTAssertEqual(template.getIntegerValueField(.scrollWheelEventScrollCount), 5)
        XCTAssertEqual(template.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1), 3, accuracy: 0.001)

        let phased = try XCTUnwrap(template.copy())
        var frame = ScrollOutgoingFrame(y: -27, x: 4, scrollPhase: 2, momentumPhase: 0)
        frame.isTrackpadStyle = true
        frame.lineY = -2
        frame.lineX = 0
        frame.write(to: phased)
        XCTAssertEqual(phased.getIntegerValueField(.scrollWheelEventScrollCount), 0)
        XCTAssertEqual(phased.getIntegerValueField(.scrollWheelEventDeltaAxis1), -2, "the frame's own lines")
        XCTAssertEqual(phased.getIntegerValueField(.scrollWheelEventDeltaAxis2), 0)
        XCTAssertEqual(phased.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1), -2.7, accuracy: 0.001)
        XCTAssertEqual(phased.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2), 0.4, accuracy: 0.001)
        XCTAssertEqual(phased.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), -27, "the point delta is written last and stays")
        XCTAssertEqual(phased.getIntegerValueField(.scrollWheelEventPointDeltaAxis2), 4)
        let event = try XCTUnwrap(NSEvent(cgEvent: phased))
        XCTAssertEqual(event.scrollingDeltaY, -27)
        XCTAssertEqual(event.scrollingDeltaX, 4)
        XCTAssertTrue(event.hasPreciseScrollingDeltas)

        let plain = try XCTUnwrap(template.copy())
        ScrollOutgoingFrame(y: -27, x: 4).write(to: plain)
        XCTAssertEqual(plain.getIntegerValueField(.scrollWheelEventScrollCount), 5, "without phases: the wheel event's")
        XCTAssertEqual(plain.getIntegerValueField(.scrollWheelEventDeltaAxis1), 3)
        XCTAssertEqual(plain.getIntegerValueField(.scrollWheelEventDeltaAxis2), 2)
        XCTAssertEqual(plain.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1), 3, accuracy: 0.001)

        // The one frame with a phase and the switch off (Chrome's "ended" at a stop): as it was.
        let chromes = try XCTUnwrap(template.copy())
        ScrollOutgoingFrame(y: 0, x: 0, scrollPhase: 4, momentumPhase: 0).write(to: chromes)
        XCTAssertEqual(chromes.getDoubleValueField(.scrollWheelEventScrollPhase), 4)
        XCTAssertEqual(chromes.getIntegerValueField(.scrollWheelEventScrollCount), 5)
        XCTAssertEqual(chromes.getIntegerValueField(.scrollWheelEventDeltaAxis1), 3)
    }

    /// Over a scroll the frames' line deltas add up to a tenth of its pixels, whole lines
    /// with the fraction carried on, in every form; with the switch off no frame has one.
    func testTrackpadStyle_lineDeltasAddUpToATenthOfThePixels() {
        for form in ScrollClassicRig.Form.allCases {
            let rig = ScrollClassicRig(duration: 3.69, form: form)
            for (pixels, time) in Self.spin { rig.input(pixels, notch: 33.6 * 6.3, at: time) }
            rig.run(until: 6)
            let pixels = rig.postedY
            let lines = rig.recorded.reduce(0) { $0 + Double($1.frame.lineY) }
            XCTAssertGreaterThan(pixels, 5_000, form.rawValue)
            XCTAssertEqual(lines, pixels / 10, accuracy: 1, form.rawValue)
            XCTAssertTrue(rig.recorded.allSatisfy { abs(Double($0.frame.lineY) - $0.frame.y / 10) < 1 }, "\(form.rawValue): each frame's lines are its own")
        }
        let plain = ScrollClassicRig(duration: 3.69, trackpadStyle: false)
        for (pixels, time) in Self.spin { plain.input(pixels, notch: 33.6 * 6.3, at: time) }
        plain.run(until: 6)
        XCTAssertTrue(plain.recorded.allSatisfy { $0.frame.lineY == 0 && $0.frame.lineX == 0 && !$0.frame.isTrackpadStyle })
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

    // MARK: The dead zone by Duration

    /// The default click, frame by frame: Feel "Smooth" (Duration 3.69), Step 33.6, Speed 6.3,
    /// dead zone 1, trackpad-style events off. The owner tuned this by hand; a change to the
    /// engine must leave every value of it alone, the time of the stop included.
    func testTheDefaultClick_isWhatItWas() throws {
        let defaults = OPTIONS_SCROLL_DEFAULT()
        XCTAssertEqual(defaults.duration, 3.69)
        XCTAssertEqual(defaults.step, 33.6)
        XCTAssertEqual(defaults.speed, 6.3)
        XCTAssertEqual(defaults.deadZone, 1)
        XCTAssertFalse(defaults.smoothSimTrackpad)
        let click = defaults.step * defaults.speed

        let at60 = glide(of: click, duration: defaults.duration, rate: 60)
        XCTAssertEqual(at60.rig.moving.map { $0.frame.y }, [
            7, 13, 15, 16, 16, 16, 15, 14, 12, 11, 10, 9, 8, 7, 6, 5, 5, 4, 3, 3, 2, 2, 2, 2, 1, 1,
        ])
        XCTAssertEqual(at60.posted, 205)
        // One frame after the other from the first display frame on, none skipped.
        for (index, item) in at60.rig.moving.enumerated() {
            XCTAssertEqual(item.time - at60.rig.start, Double(index + 1) / 60, accuracy: 1e-9, "frame \(index)")
        }
        XCTAssertEqual(at60.rig.stops.map(\.phase), [.MomentumEnd])
        XCTAssertEqual(at60.rig.stops.first?.time ?? -1, 40.0 / 60.0, accuracy: 1e-9, "the scroll ends 0.667 s after the click")
        XCTAssertTrue(at60.rig.recorded.allSatisfy { $0.frame.scrollPhase == nil && $0.frame.timestamp == nil })

        for (rate, frames) in [(120.0, 50), (144.0, 59)] {
            let faster = glide(of: click, duration: defaults.duration, rate: rate)
            XCTAssertEqual(faster.posted, 205, "\(Int(rate)) Hz")
            XCTAssertEqual(faster.frames, frames, "\(Int(rate)) Hz")
            XCTAssertEqual(faster.rig.stops.first?.time ?? -1, 40.0 / 60.0, accuracy: 1.0 / 60.0, "\(Int(rate)) Hz")
        }

        // Both dead zones are the stored one, exactly, at Smooth's factor.
        let transition = defaults.durationTransition
        XCTAssertEqual(transition, ScrollMotion.deadZoneReferenceTransition)
        XCTAssertEqual(ScrollMotion.postingDeadZone(defaults.deadZone, transition: transition), 1)
        XCTAssertEqual(ScrollMotion.arrivalDeadZone(defaults.deadZone, transition: transition), 1)
    }

    /// No Duration loses more of a scroll than Smooth does. The frames of a glide used to stop
    /// at a pixel a frame at every Duration, with (dead zone / Duration factor) pixels left
    /// to go: 6 px at Smooth, 17 at Float, 52 at glide time 5.0. One click at Speed 1 is
    /// 33.6 px: it moved 15 px at Float and nothing at 5.0.
    func testALongGlide_losesNoMoreThanSmoothDoes() {
        for speed in [1.0, 2.0, 3.0, 6.3] {
            let click = 33.6 * speed
            for rate in [60.0, 120.0, 144.0] {
                let smooth = glide(of: click, duration: 3.69, rate: rate)
                let lostAtSmooth = click - smooth.posted
                XCTAssertGreaterThan(lostAtSmooth, 5, "Speed \(speed) at \(Int(rate)) Hz")
                XCTAssertLessThan(lostAtSmooth, 8, "Speed \(speed) at \(Int(rate)) Hz")
                for duration in [3.9, 4.35, 4.6, 4.9, 5.0] {
                    let label = "Duration \(duration), Speed \(speed) at \(Int(rate)) Hz"
                    let long = glide(of: click, duration: duration, rate: rate)
                    XCTAssertLessThanOrEqual(click - long.posted, lostAtSmooth + 1, label)
                    XCTAssertLessThan(long.posted, click, "\(label): never more than the click")
                    XCTAssertTrue(long.rig.moving.allSatisfy { $0.frame.y == $0.frame.y.rounded() && $0.frame.y >= 1 }, "\(label): whole pixels")
                    assertGlidesOut(long.rig, label)
                }
            }
        }
    }

    /// And no Duration keeps a scroll open longer after its last frame than Smooth does (a
    /// quarter of a second). It used to stay open until 1 px was left to go: 0.85 s at Float
    /// and 3.5 s at glide time 5.0, with the display link running and, with trackpad-style
    /// events, the app's glide open and nothing arriving.
    func testALongGlide_endsAsSoonAfterItsLastFrameAsSmoothDoes() {
        for trackpadStyle in [false, true] {
            for duration in [3.69, 3.9, 4.35, 4.6, 4.9, 5.0] {
                for speed in [1.0, 6.3] {
                    for rate in [60.0, 120.0] {
                        let label = "Duration \(duration), Speed \(speed) at \(Int(rate)) Hz, trackpad-style \(trackpadStyle)"
                        let rig = ScrollClassicRig(duration: duration, rate: rate, trackpadStyle: trackpadStyle)
                        rig.input(33.6 * speed, notch: 33.6 * speed, at: 0)
                        rig.run(until: 10)
                        XCTAssertEqual(rig.stops.count, 1, label)
                        let open = (rig.stops.first?.time ?? 99) - rig.lastMovement
                        XCTAssertGreaterThan(open, 0.15, label)
                        XCTAssertLessThan(open, 0.4, label)
                        if trackpadStyle {
                            XCTAssertEqual(rig.stream.last, "momentumEnded 0", label)
                        }
                    }
                }
            }
        }
    }

    // MARK: The wheel goes on in another app

    /// B2, as a flick: the wheel is turned over another app while the first app's glide runs.
    /// The glide's "momentum ended" goes to the app that got the glide, and the new touch
    /// begins in the other one. Both used to go to the new event's app: the first app's glide
    /// never ended, and the second got a "momentum ended" for a glide it never saw.
    func testAnotherApp_flick_endsTheGlideWhereItRan() {
        let rig = ScrollClassicRig(duration: 3.69, trackpadStyle: true)
        let first = ScrollInputPlace(pid: 100, pointer: CGPoint(x: 400, y: 300))
        let second = ScrollInputPlace(pid: 200, pointer: CGPoint(x: 400, y: 300))
        rig.input(33.6 * 6.3, notch: 33.6 * 6.3, at: 0, place: first, targetPID: 100)
        rig.run(until: 0.25)
        XCTAssertEqual(rig.phases.phase, .MomentumOngoing)
        let beforeTheTick = rig.recorded.count
        rig.input(33.6 * 6.3, notch: 33.6 * 6.3, at: 0.25, place: second, targetPID: 200)
        rig.run(until: 3)

        XCTAssertTrue(rig.targets.prefix(beforeTheTick).allSatisfy { $0 == 100 })
        XCTAssertEqual(Array(rig.targetedStream.dropFirst(beforeTheTick).prefix(2)), ["100: momentumEnded 0", "200: began 7"])
        XCTAssertTrue(rig.targets.dropFirst(beforeTheTick + 1).allSatisfy { $0 == 200 }, "everything after it goes to the other app")
        XCTAssertEqual(rig.targetedStream.last, "200: momentumEnded 0")
        // Each app got one whole gesture.
        let flick = ["began", "changed", "ended", "momentumBegan", "momentumChanged", "momentumEnded"]
        XCTAssertEqual(rig.phaseSequence, flick + flick)
    }

    /// B2, as one touch (every app that is not Chromium-based; in both of its forms): the wheel spins on while
    /// the pointer moves to another app. The first app gets its "ended", the other a "began".
    /// The frames used to go on to the other app as "changed" without a "began", and the
    /// first app never got "ended".
    func testAnotherApp_longTouch_endsTheTouchWhereItBegan() {
        for form in [ScrollClassicRig.Form.oneTouch, .oldLongTouch] {
            let rig = ScrollClassicRig(duration: 3.69, form: form)
            let label = form.rawValue
            for index in 0..<4 { rig.input(33.6 * 6.3, notch: 33.6 * 6.3, at: Double(index) * 0.05, targetPID: 100) }
            rig.run(until: 0.2)
            XCTAssertEqual(rig.phases.phase, .TrackingOngoing, "\(label): the touch lasts while the wheel turns")
            let beforeTheTick = rig.recorded.count
            for index in 0..<4 { rig.input(33.6 * 6.3, notch: 33.6 * 6.3, at: 0.2 + Double(index) * 0.05, targetPID: 200) }
            rig.run(until: 3)

            XCTAssertTrue(rig.targets.prefix(beforeTheTick).allSatisfy { $0 == 100 }, label)
            // The one touch is ended by force here: its tap goes to the app that had the touch.
            let closing = form == .oneTouch ? ["100: ended 0", "100: mayBegin 0", "100: cancelled 0"] : ["100: ended 0"]
            XCTAssertEqual(Array(rig.targetedStream.dropFirst(beforeTheTick).prefix(closing.count + 1)), closing + ["200: began 0"], label)
            XCTAssertTrue(rig.targets.dropFirst(beforeTheTick + closing.count).allSatisfy { $0 == 200 }, label)
            let inTheFirstApp = zip(rig.targets, rig.stream).filter { $0.0 == 100 }.map { $0.1.split(separator: " ").first.map(String.init) ?? "" }
            XCTAssertEqual(inTheFirstApp.first, "began", label)
            XCTAssertEqual(inTheFirstApp.last, form == .oneTouch ? "cancelled" : "ended", label)
            XCTAssertEqual(inTheFirstApp.filter { $0 == "began" }.count, 1, label)
            XCTAssertEqual(inTheFirstApp.filter { $0 == "ended" }.count, 1, label)
        }
    }

    /// B2 with the switch off (the default): the rest of the first app's glide is not posted
    /// to the other app. The other app gets its own click, from its beginning, and nothing of
    /// the first one's; the first scroll's line in the log says why it ended.
    func testAnotherApp_theRestOfTheGlideIsNotPostedThere() {
        let click = 33.6 * 6.3
        // What one click alone gives: the default click.
        let alone = ScrollClassicRig(duration: 3.69)
        alone.input(click, notch: click, at: 0)
        alone.run(until: 3)

        var ended: [(inputs: Int, reason: ScrollSystemLog.EndReason)] = []
        ScrollSystemLog.sessionObserverForTests = { ended.append(($0.inputs, $1)) }
        defer { ScrollSystemLog.sessionObserverForTests = nil }
        let rig = ScrollClassicRig(duration: 3.69)
        for index in 0..<3 { rig.input(click, notch: click, at: Double(index) * 0.02, targetPID: 100) }
        rig.run(until: 0.15)
        let inTheFirstApp = rig.postedY
        XCTAssertLessThan(inTheFirstApp, 3 * click - 150, "much of the three clicks is still to come")
        let beforeTheTick = rig.recorded.count
        rig.input(click, notch: click, at: 0.15, targetPID: 200)
        rig.run(until: 3)

        XCTAssertTrue(rig.targets.prefix(beforeTheTick).allSatisfy { $0 == 100 })
        XCTAssertTrue(rig.targets.dropFirst(beforeTheTick).allSatisfy { $0 == 200 })
        // The other app gets exactly what one click alone gives.
        let inTheOtherApp = rig.moving.filter { $0.time - rig.start > 0.15 }.map { $0.frame.y }
        XCTAssertEqual(inTheOtherApp, alone.moving.map { $0.frame.y })
        XCTAssertEqual(rig.postedY - inTheFirstApp, 205)
        XCTAssertEqual(ended.map(\.reason), [.anotherApp, .glidedOut])
        XCTAssertEqual(ended.map(\.inputs), [3, 1])
    }

    /// The same app, another window or pane: nothing ends (as before).
    func testTheSameApp_goesOnWithTheScroll() {
        let click = 33.6 * 6.3
        let rig = ScrollClassicRig(duration: 3.69)
        rig.input(click, notch: click, at: 0, targetPID: 100)
        rig.input(click, notch: click, at: 0.15, targetPID: 100)
        rig.run(until: 3)
        XCTAssertEqual(rig.sessions.count, 1)
        XCTAssertEqual(rig.sessions.first?.inputs, 2)
        XCTAssertTrue(rig.targets.allSatisfy { $0 == 100 })
        XCTAssertGreaterThan(rig.postedY, 2 * click - 10)
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

    /// C1: a web app installed from a Chromium browser ("Install as app") is a bundle of its
    /// own with the browser's loader as its program and no frameworks; its windows live in
    /// that process. It used to count as touch-only.
    func testABrowsersWebApp_isFoundByItsLoader() throws {
        let webApp = try app("Mail.app", files: ["Contents/MacOS/app_mode_loader", "Contents/Resources/app.icns"])
        XCTAssertTrue(ScrollUtils.isChromiumBased(bundleURL: webApp))
        // Another program in that place is not one.
        let other = try app("Other.app", files: ["Contents/MacOS/Other", "Contents/Resources/app_mode_loader"])
        XCTAssertFalse(ScrollUtils.isChromiumBased(bundleURL: other))
    }

    /// A Gecko-based app (Firefox and its rebuilds, Thunderbird) is known by the engine's
    /// library beside its program, and gets the flick as a Chromium-based app does: Gecko
    /// follows every delta, touch and glide alike. (It counted as touch-only.)
    func testGeckoBasedApps_areFoundByTheEnginesLibrary() throws {
        let firefox = try app("Fox.app", files: ["Contents/MacOS/XUL", "Contents/MacOS/fox", "Contents/Resources/application.ini"])
        XCTAssertTrue(ScrollUtils.isGeckoBased(bundleURL: firefox))
        XCTAssertFalse(ScrollUtils.isChromiumBased(bundleURL: firefox))
        XCTAssertTrue(ScrollUtils.scrollsByGlideEvents(bundleURL: firefox))
        // A file of that name anywhere else is not the engine.
        let other = try app("Other.app", files: ["Contents/MacOS/Other", "Contents/Resources/XUL", "Contents/Frameworks/XUL"])
        XCTAssertFalse(ScrollUtils.isGeckoBased(bundleURL: other))
        XCTAssertFalse(ScrollUtils.scrollsByGlideEvents(bundleURL: other))
        // Chromium still counts, and the Finder (AppKit) is neither.
        let electron = try app("Editor.app", files: ["Contents/Frameworks/Electron Framework.framework/Resources/resources.pak"])
        XCTAssertTrue(ScrollUtils.scrollsByGlideEvents(bundleURL: electron))
        XCTAssertFalse(ScrollUtils.scrollsByGlideEvents(bundleURL: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")))
    }

    /// The look into a bundle as it runs off the main thread: a Gecko-based app in an
    /// Applications folder is one that follows the glide, as a Chromium-based one is; the
    /// same bundle anywhere else is not looked into.
    func testTheLook_findsAGeckoBasedAppInAnApplicationsFolder() throws {
        let home = root.resolvingSymlinksInPath().path
        let firefox = try app("Applications/Fox.app", files: ["Contents/MacOS/XUL"])
        let electron = try app("Applications/Editor.app", files: ["Contents/Frameworks/Electron Framework.framework/Resources/resources.pak"])
        let native = try app("Applications/Native.app", files: ["Contents/MacOS/Native"])
        let elsewhere = try app("Documents/Fox.app", files: ["Contents/MacOS/XUL"])
        XCTAssertTrue(ScrollUtils.lookFindsGlideFollower(bundleURL: firefox, homeDirectory: home))
        XCTAssertTrue(ScrollUtils.lookFindsGlideFollower(bundleURL: electron, homeDirectory: home))
        XCTAssertFalse(ScrollUtils.lookFindsGlideFollower(bundleURL: native, homeDirectory: home))
        XCTAssertFalse(ScrollUtils.lookFindsGlideFollower(bundleURL: elsewhere, homeDirectory: home), "never looked into")

        // And the answer of the look makes the app one that gets the flick.
        let utils = ScrollUtils()
        utils.inspectBundle = { url, completion in completion(ScrollUtils.lookFindsGlideFollower(bundleURL: firefox, homeDirectory: home)) }
        let inApplications = URL(fileURLWithPath: "/Applications/Fox.app")
        _ = utils.trackpadStyleTarget(bundleIdentifier: "org.mozilla.firefox", bundleURL: inApplications)
        XCTAssertEqual(utils.trackpadStyleTarget(bundleIdentifier: "org.mozilla.firefox", bundleURL: inApplications), .followsGlide)
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

    /// What the switch comes to for each kind of app. Safari: no phases, exactly as with the
    /// switch off, which is the one way it is known to scroll as it should.
    func testTheSwitchAndTheApp_decideTheForm() {
        func form(_ switchOn: Bool, _ target: ScrollUtils.TrackpadStyleTarget?, oldLongTouch: Bool = false) -> [Bool] {
            let form = ScrollPoster.trackpadStyleForm(switchOn: switchOn, target: target, oldLongTouch: oldLongTouch)
            return [form.phases, form.flick, form.withheld, form.oneTouch]
        }
        //                                          phases flick  withheld oneTouch
        XCTAssertEqual(form(true, .plainScrolling), [false, false, true, false], "apps where a wheel stays a wheel, DuckDuckGo")
        XCTAssertEqual(form(true, .safari), [false, false, true, false], "Safari")
        XCTAssertEqual(form(true, .safari, oldLongTouch: true), [false, false, true, false])
        XCTAssertEqual(form(true, .followsGlide), [true, true, false, false], "Chromium")
        XCTAssertEqual(form(true, .touchOnly), [true, false, false, true], "native apps: one touch to the end")
        XCTAssertEqual(form(true, nil), [true, false, false, true], "an app that is not known")
        // The evaluation switch brings the old long touch back for those apps, and changes nothing else.
        XCTAssertEqual(form(true, .touchOnly, oldLongTouch: true), [true, false, false, false])
        XCTAssertEqual(form(true, nil, oldLongTouch: true), [true, false, false, false])
        XCTAssertEqual(form(true, .followsGlide, oldLongTouch: true), [true, true, false, false])
        XCTAssertEqual(form(true, .plainScrolling, oldLongTouch: true), [false, false, true, false])
        for target in [ScrollUtils.TrackpadStyleTarget.plainScrolling, .safari, .followsGlide, .touchOnly] {
            for oldLongTouch in [false, true] {
                XCTAssertEqual(form(false, target, oldLongTouch: oldLongTouch), [false, false, false, false], "the switch is off")
            }
        }
    }

    /// EVALUATION SWITCH (goes with `TrackpadStyleEvaluation`): with it Safari gets the
    /// flick, and nothing else changes for any other kind of app.
    func testTheSafariSwitch_givesSafariTheFlickAndNobodyElseAnything() {
        func form(_ target: ScrollUtils.TrackpadStyleTarget?, safariFlick: Bool, oldLongTouch: Bool = false, switchOn: Bool = true) -> [Bool] {
            let form = ScrollPoster.trackpadStyleForm(switchOn: switchOn, target: target, oldLongTouch: oldLongTouch, safariFlick: safariFlick)
            return [form.phases, form.flick, form.withheld, form.oneTouch]
        }
        XCTAssertEqual(form(.safari, safariFlick: true), [true, true, false, false], "Safari: a flick")
        XCTAssertEqual(form(.safari, safariFlick: true, oldLongTouch: true), [true, true, false, false])
        XCTAssertEqual(form(.safari, safariFlick: true, switchOn: false), [false, false, false, false], "the switch is off")
        for target in [ScrollUtils.TrackpadStyleTarget.plainScrolling, .followsGlide, .touchOnly, nil] {
            for oldLongTouch in [false, true] {
                XCTAssertEqual(form(target, safariFlick: true, oldLongTouch: oldLongTouch), form(target, safariFlick: false, oldLongTouch: oldLongTouch), "\(String(describing: target))")
            }
        }
    }

    /// An app known as WebKit's never gets a glide whose "momentum began" carries the wheel
    /// event's hardware record: WebKit replaces such a glide by one of its own (36 of a
    /// flick's 205 px arrived in a WKWebView). Whatever the two evaluation switches say and
    /// whether the record comes off here or not: Safari and the DuckDuckGo browser get
    /// either no phases at all, or (Safari, with its switch, where the record comes off) a
    /// flick whose every frame goes out without the record.
    func testAWebKitApp_neverGetsAGlideThatCarriesAHardwareRecord() {
        var checked = 0
        for kind in [ScrollUtils.TrackpadStyleTarget.safari, .plainScrolling] {
            for safariSwitch in [false, true] {
                for oldLongTouch in [false, true] {
                    for recordComesOff in [false, true] {
                        // As `ScrollPoster.configSnapshot` asks.
                        let form = ScrollPoster.trackpadStyleForm(switchOn: true, target: kind, oldLongTouch: oldLongTouch,
                                                                  safariFlick: safariSwitch && recordComesOff)
                        checked += 1
                        let label = "\(kind), Safari switch \(safariSwitch), old long touch \(oldLongTouch), record comes off \(recordComesOff)"
                        if form.phases {
                            XCTAssertEqual(kind, .safari, label)
                            XCTAssertTrue(safariSwitch && recordComesOff, "\(label): phases only where the record comes off")
                            XCTAssertTrue(form.flick, label)
                        } else {
                            XCTAssertTrue(form.withheld, label)
                        }
                    }
                }
            }
        }
        XCTAssertEqual(checked, 16)
    }

    // MARK: B3: nothing is read from disk inside the scroll tap's callback

    /// Collects the looks into bundles a `ScrollUtils` asks for, instead of the disk.
    private final class Looks {
        var asked: [(url: URL, answer: (Bool) -> Void)] = []
        func install(on utils: ScrollUtils) {
            utils.inspectBundle = { [unowned self] url, completion in self.asked.append((url, completion)) }
        }
    }

    /// An app seen for the first time is answered at once, as touch-only, and its bundle is
    /// looked into once, somewhere else; the answer counts from then on. The look used to
    /// happen right there, on the main thread inside the tap's callback.
    func testAnAppSeenForTheFirstTime_isAnsweredAtOnceAndLookedIntoOnce() {
        let utils = ScrollUtils()
        let looks = Looks()
        looks.install(on: utils)
        let editor = URL(fileURLWithPath: "/Applications/Editor.app")

        XCTAssertEqual(utils.trackpadStyleTarget(bundleIdentifier: "com.example.editor", bundleURL: editor), .touchOnly, "at once")
        XCTAssertEqual(looks.asked.map(\.url), [editor], "one look was asked for")
        for _ in 0..<20 {
            XCTAssertEqual(utils.trackpadStyleTarget(bundleIdentifier: "com.example.editor", bundleURL: editor), .touchOnly)
        }
        XCTAssertEqual(looks.asked.count, 1, "not one per wheel event")

        looks.asked.first?.answer(true)
        XCTAssertEqual(utils.trackpadStyleTarget(bundleIdentifier: "com.example.editor", bundleURL: editor), .followsGlide, "from the next scroll on")
        XCTAssertEqual(looks.asked.count, 1)

        // An app that is not Chromium-based stays touch-only, and is not looked into again.
        let native = URL(fileURLWithPath: "/Applications/Native.app")
        XCTAssertEqual(utils.trackpadStyleTarget(bundleIdentifier: "com.example.native", bundleURL: native), .touchOnly)
        looks.asked.last?.answer(false)
        XCTAssertEqual(utils.trackpadStyleTarget(bundleIdentifier: "com.example.native", bundleURL: native), .touchOnly)
        XCTAssertEqual(looks.asked.count, 2)
    }

    /// Safari is known by its name: no look at all.
    func testSafari_isKnownWithoutALook() {
        let utils = ScrollUtils()
        let looks = Looks()
        looks.install(on: utils)
        let safari = URL(fileURLWithPath: "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app")
        XCTAssertEqual(utils.trackpadStyleTarget(bundleIdentifier: "com.apple.Safari", bundleURL: safari), .safari)
        XCTAssertEqual(utils.trackpadStyleTarget(bundleIdentifier: "com.apple.SafariTechnologyPreview", bundleURL: URL(fileURLWithPath: "/Applications/Safari Technology Preview.app")), .safari)
        XCTAssertEqual(looks.asked.count, 0)
    }

    /// A2: every bundle id that begins with `com.apple.Safari` is Safari. A web app made with
    /// "Add to Dock" (`com.apple.Safari.WebApp.<id>`, in the user's Applications folder) is
    /// WebKit in its whole window; it used to count as touch-only and got the form Safari
    /// could not scroll with. The DuckDuckGo browser is WebKit too (ids from its own
    /// repository). No look into any of them.
    func testSafarisWebAppsAndWebKitBrowsers_getPlainScrolling() {
        let utils = ScrollUtils()
        let looks = Looks()
        looks.install(on: utils)
        let plain: [(String, String)] = [
            ("com.apple.Safari.WebApp.5E0C8F6A-0000-4000-8000-1234567890AB", "/Users/someone/Applications/Notes on the web.app"),
            ("com.apple.SafariTechnologyPreview", "/Applications/Safari Technology Preview.app"),
            ("com.duckduckgo.macos.browser", "/Applications/DuckDuckGo.app"),
            ("com.duckduckgo.mobile.ios", "/Applications/DuckDuckGo App Store.app"),
        ]
        for (identifier, path) in plain {
            // Safari's own ids are a kind of their own (an evaluation switch asks for them);
            // without that switch they get what the other WebKit browsers get: no phases.
            let kind: ScrollUtils.TrackpadStyleTarget = identifier.hasPrefix("com.apple.Safari") ? .safari : .plainScrolling
            XCTAssertEqual(utils.trackpadStyleTarget(bundleIdentifier: identifier, bundleURL: URL(fileURLWithPath: path)), kind, identifier)
            XCTAssertTrue(ScrollUtils.getsPlainScrolling(bundleIdentifier: identifier), identifier)
            let form = ScrollPoster.trackpadStyleForm(switchOn: true, target: kind)
            XCTAssertFalse(form.phases, identifier)
            XCTAssertTrue(form.withheld, identifier)
        }
        XCTAssertEqual(looks.asked.count, 0)
        // Not by a name that only contains Safari's, and no other Apple app.
        for identifier in ["com.example.com.apple.Safari", "com.apple.mail", "com.apple.finder", "com.duckduckgo.macos.vpn", "org.mozilla.firefox"] {
            XCTAssertFalse(ScrollUtils.getsPlainScrolling(bundleIdentifier: identifier), identifier)
        }
        XCTAssertEqual(utils.trackpadStyleTarget(bundleIdentifier: "com.apple.mail", bundleURL: URL(fileURLWithPath: "/System/Applications/Mail.app")), .touchOnly)
        XCTAssertEqual(looks.asked.count, 1)
    }

    /// C2: an app that comes to the front is asked for then, so the first scroll in it
    /// already knows. The first scroll over a Chromium-based app used to go out as for an app
    /// that is not known, until the look had answered. Nothing is asked while trackpad-style
    /// events are off for the app.
    /// Apps where a wheel has to stay a wheel (they tell a mouse from a trackpad by the
    /// phase: the wheel then pans a map instead of zooming, orbits a 3D view, or does not
    /// scroll at all) get no phases, known by their bundle id without a look into the
    /// bundle. Only the exact ids: nothing that merely begins the same way.
    func testAppsWhereAWheelMustStayAWheel_getPlainScrolling() {
        let utils = ScrollUtils()
        let looks = Looks()
        looks.install(on: utils)
        let listed: [(String, String)] = [
            ("com.apple.Maps", "/System/Applications/Maps.app"),
            ("com.apple.findmy", "/System/Applications/FindMy.app"),
            ("com.apple.iCal", "/System/Applications/Calendar.app"),
            ("com.apple.ScreenContinuity", "/System/Applications/iPhone Mirroring.app"),
            ("org.blenderfoundation.blender", "/Applications/Blender.app"),
            ("org.godotengine.godot", "/Applications/Godot.app"),
        ]
        XCTAssertEqual(Set(listed.map(\.0)), ScrollUtils.wheelOnlyBundleIdentifiers, "every listed id is tested, and no other is listed")
        for (identifier, path) in listed {
            XCTAssertTrue(ScrollUtils.getsPlainScrolling(bundleIdentifier: identifier), identifier)
            XCTAssertEqual(utils.trackpadStyleTarget(bundleIdentifier: identifier, bundleURL: URL(fileURLWithPath: path)), .plainScrolling, identifier)
            let form = ScrollPoster.trackpadStyleForm(switchOn: true, target: .plainScrolling)
            XCTAssertFalse(form.phases, identifier)
            XCTAssertTrue(form.withheld, identifier)
        }
        XCTAssertEqual(looks.asked.count, 0, "known by name: no look into a bundle")
        for identifier in ["com.apple.Maps.widget", "com.apple.MapsSupport", "com.apple.findmy.FindMyWidget", "com.apple.iCal.CalendarNC",
                           "com.apple.reminders", "com.apple.Notes", "com.apple.finder", "org.blenderfoundation.blender.thumbnailer",
                           "org.godotengine.godot.game", "com.autodesk.fusion360", "com.mcneel.rhinoceros"] {
            XCTAssertFalse(ScrollUtils.getsPlainScrolling(bundleIdentifier: identifier), identifier)
        }
    }

    func testAnAppThatComesToTheFront_isKnownBeforeItsFirstScroll() {
        let utils = ScrollUtils()
        let looks = Looks()
        looks.install(on: utils)
        let editor = URL(fileURLWithPath: "/Applications/Editor.app")

        utils.applicationCameToFront(bundleIdentifier: "com.example.editor", bundleURL: editor, trackpadStyleOn: false)
        utils.applicationCameToFront(bundleIdentifier: "com.example.editor", bundleURL: nil, trackpadStyleOn: true)
        XCTAssertEqual(looks.asked.count, 0, "off for this app, or no bundle: nothing is looked into")

        utils.applicationCameToFront(bundleIdentifier: "com.example.editor", bundleURL: editor, trackpadStyleOn: true)
        XCTAssertEqual(looks.asked.map(\.url), [editor])
        looks.asked.first?.answer(true)

        XCTAssertEqual(utils.trackpadStyleTarget(bundleIdentifier: "com.example.editor", bundleURL: editor), .followsGlide, "the first scroll is a flick")
        utils.applicationCameToFront(bundleIdentifier: "com.example.editor", bundleURL: editor, trackpadStyleOn: true)
        XCTAssertEqual(looks.asked.count, 1, "one look per app, however often it comes to the front")
    }

    /// Whether trackpad-style events are on for an app: its own setting when it keeps its own.
    func testTrackpadStyleIsOn_isTheAppsOwnSettingOrTheGlobalOne() {
        let global = OPTIONS_SCROLL_DEFAULT()
        let app = Application(path: "/Applications/Editor.app")
        for (globalOn, inherit, ownOn, expected) in [
            (true, true, false, true), (false, true, true, false),
            (true, false, false, false), (false, false, true, true),
        ] {
            global.smoothSimTrackpad = globalOn
            app.inherit = inherit
            app.scroll.smoothSimTrackpad = ownOn
            XCTAssertEqual(ScrollPoster.trackpadStyleIsOn(application: app, global: global), expected, "global \(globalOn), inherit \(inherit), own \(ownOn)")
        }
        global.smoothSimTrackpad = true
        XCTAssertTrue(ScrollPoster.trackpadStyleIsOn(application: nil, global: global))
        global.smoothSimTrackpad = false
        XCTAssertFalse(ScrollPoster.trackpadStyleIsOn(application: nil, global: global))
    }

    /// A bundle outside the Applications folders and /System is never looked into: macOS
    /// would ask for the Documents, Desktop or Downloads folder in Scrollio's name, or wait
    /// for a network volume. Such an app stays touch-only, even a Chromium-based one.
    func testABundleOutsideTheApplicationsFolders_isNeverLookedInto() throws {
        let utils = ScrollUtils()
        let looks = Looks()
        looks.install(on: utils)
        // A Chromium-based app in a temporary folder (the look would find the engine).
        let electron = try app("Editor.app", files: ["Contents/Frameworks/Electron Framework.framework/Resources/resources.pak"])
        XCTAssertTrue(ScrollUtils.isChromiumBased(bundleURL: electron))
        let outside = [
            electron,
            URL(fileURLWithPath: "/Users/someone/Documents/Build/Editor.app"),
            URL(fileURLWithPath: "/Users/someone/Desktop/Editor.app"),
            URL(fileURLWithPath: "/Users/someone/Downloads/Editor.app"),
            URL(fileURLWithPath: "/Users/someone/Library/Mobile Documents/com~apple~CloudDocs/Editor.app"),
            URL(fileURLWithPath: "/Volumes/Share/Editor.app"),
            URL(fileURLWithPath: "/private/var/folders/xy/T/AppTranslocation/1234/d/Editor.app"),
        ]
        for url in outside {
            XCTAssertEqual(utils.trackpadStyleTarget(bundleIdentifier: "com.example.editor", bundleURL: url), .touchOnly, url.path)
            XCTAssertEqual(utils.trackpadStyleTarget(bundleIdentifier: "com.example.editor", bundleURL: url), .touchOnly, url.path)
        }
        XCTAssertEqual(looks.asked.count, 0)
    }

    func testMayLookIntoBundle_onlyInTheApplicationsFoldersAndSystem() {
        let home = "/Users/someone"
        func may(_ path: String) -> Bool { return ScrollUtils.mayLookIntoBundle(atPath: path, homeDirectory: home) }
        XCTAssertTrue(may("/Applications/Google Chrome.app"))
        XCTAssertTrue(may("/Applications/Utilities/Terminal.app"))
        XCTAssertTrue(may("/Applications/Setapp/Editor.app"))
        XCTAssertTrue(may("/System/Applications/Notes.app"))
        XCTAssertTrue(may("/System/Library/CoreServices/Finder.app"))
        XCTAssertTrue(may("/Users/someone/Applications/Chrome Apps.localized/Mail.app"))

        XCTAssertFalse(may("/Users/someone/Documents/Editor.app"))
        XCTAssertFalse(may("/Users/someone/Desktop/Editor.app"))
        XCTAssertFalse(may("/Users/someone/Downloads/Editor.app"))
        XCTAssertFalse(may("/Users/other/Applications/Editor.app"), "another user's")
        XCTAssertFalse(may("/Users/someone/ApplicationsOld/Editor.app"))
        XCTAssertFalse(may("/Volumes/Share/Editor.app"))
        XCTAssertFalse(may("/System/Volumes/Data/Users/someone/Documents/Editor.app"), "the data volume leads to every user's folders")
        XCTAssertFalse(may("/Applications/../Users/someone/Documents/Editor.app"))
        XCTAssertFalse(may("/Applications"))
        XCTAssertFalse(may("Applications/Editor.app"))
        XCTAssertFalse(may(""))
    }

    /// The app's own look runs off the main thread and answers on the main queue; a folder
    /// outside the allowed ones is not opened even when asked directly.
    func testTheLookRunsOffTheMainThreadAndAnswersOnTheMainQueue() throws {
        let utils = ScrollUtils()
        // Every look into a bundle says which thread it runs on.
        let lock = NSLock()
        var looksOnTheMainThread: [Bool] = []
        ScrollUtils.lookThreadObserverForTests = { onMain in
            lock.lock()
            looksOnTheMainThread.append(onMain)
            lock.unlock()
        }
        defer { ScrollUtils.lookThreadObserverForTests = nil }
        // The call comes back before the answer: nothing of the look runs inside it (it is
        // made inside the scroll tap's callback).
        var returned = false
        let finder = expectation(description: "the Finder was looked into")
        utils.inspectBundle(URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")) { isChromium in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertTrue(returned, "the answer comes after the call has returned")
            XCTAssertFalse(isChromium, "the Finder is AppKit")
            finder.fulfill()
        }
        let electron = try app("Editor.app", files: ["Contents/Frameworks/Electron Framework.framework/Resources/resources.pak"])
        let outside = expectation(description: "answered without a look")
        utils.inspectBundle(electron) { isChromium in
            XCTAssertTrue(returned)
            XCTAssertFalse(isChromium, "outside the Applications folders: not opened")
            outside.fulfill()
        }
        lock.lock()
        XCTAssertEqual(looksOnTheMainThread.filter { $0 }, [], "no look ran inside the call")
        lock.unlock()
        returned = true
        wait(for: [finder, outside], timeout: 5)
        lock.lock()
        XCTAssertEqual(looksOnTheMainThread, [false, false], "both looks ran, and off the main thread")
        lock.unlock()
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
            let line = ScrollSystemLog.message(for: session, ended: .glidedOut)
            XCTAssertTrue(line.contains(String(format: "Duration %.2f", duration)), line)
        }
    }

    func testSessionLine_saysWhichFormOfTrackpadStyleWentOut() {
        var session = ScrollSystemLog.Session()
        session.inputs = 6
        session.touches = 1
        session.glideInputs = 4
        XCTAssertTrue(ScrollSystemLog.message(for: session, ended: .glidedOut).contains("trackpad-style off, ended"))
        session.trackpadStyleWithheld = true
        XCTAssertTrue(ScrollSystemLog.message(for: session, ended: .glidedOut).contains("trackpad-style off (not sent to this app), ended"))
        session.trackpadStyleWithheld = false
        session.trackpadStyle = true
        XCTAssertTrue(ScrollSystemLog.message(for: session, ended: .glidedOut).contains("trackpad-style on (long touch: 1 touches), ended"))
        session.oneTouch = true
        XCTAssertTrue(ScrollSystemLog.message(for: session, ended: .glidedOut).contains("trackpad-style on (one touch: 1 touches), ended"))
        session.oneTouch = false
        session.flick = true
        XCTAssertTrue(ScrollSystemLog.message(for: session, ended: .glidedOut)
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

    // MARK: A wheel event the poster cannot take, through the scroll tap

    /// The scroll tap with the shared poster on a stand-in for the display, the settings a
    /// wheel event is smoothed with, and no app rule. Call `restore` at the end.
    private func scrollTapWithAStandInDisplay() -> (display: FakeDisplay, restore: () -> Void) {
        let poster = ScrollPoster.shared
        let savedFactory = poster.makeDisplayLink
        let saved = (Options.shared.scroll.smooth, Options.shared.scroll.reverse, Options.shared.scroll.smoothHorizontal,
                     Options.shared.scroll.step, Options.shared.application.allowlist, ScrollCore.posterInputObserverForTests)
        poster.stop()
        poster.dropDisplayLinkForTests()
        poster.clearRecreateCooldownForTests()
        let display = FakeDisplay(for: poster)
        Options.shared.scroll.smooth = true
        Options.shared.scroll.reverse = false
        Options.shared.application.allowlist = false
        ScrollCore.posterInputObserverForTests = nil
        ScrollCore.shared.blockSmooth = false
        ScrollCore.shared.toggleScroll = false
        ScrollCore.shared.handover = ScrollHandover()
        ScrollUtils.shared.treatAsRemoteForTests(sourcePID: nil)
        return (display, {
            poster.stop()
            poster.dropDisplayLinkForTests()
            poster.makeDisplayLink = savedFactory
            poster.clearRecreateCooldownForTests()
            Options.shared.scroll.smooth = saved.0
            Options.shared.scroll.reverse = saved.1
            Options.shared.scroll.smoothHorizontal = saved.2
            Options.shared.scroll.step = saved.3
            Options.shared.application.allowlist = saved.4
            ScrollCore.posterInputObserverForTests = saved.5
        })
    }

    private func wheelEvent(lines y: Int64, x: Int64 = 0) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 0, wheel2: 0, wheel3: 0))
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: y)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Double(y))
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: Double(y * 10))
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: x)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: Double(x))
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: Double(x * 10))
        return event
    }

    private func tap(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        return ScrollCore.shared.scrollEventCallBack(CGEventTapProxy(bitPattern: 1)!, .scrollWheel, event, nil)
    }

    /// C1 through the tap: with no display link (the display is off) the wheel event goes
    /// on as it came and the poster is left alone. It used to be fed to the poster as well.
    func testWheelEventWithoutADisplayLink_goesOnAndThePosterIsLeftAlone() throws {
        let (display, restore) = scrollTapWithAStandInDisplay()
        defer { restore() }
        display.isOn = false
        var reasons: [ScrollSystemLog.PassthroughReason] = []
        ScrollSystemLog.passthroughObserverForTests = { reasons.append($0) }
        let event = try wheelEvent(lines: -2)

        let result = tap(event)

        XCTAssertTrue(result?.takeUnretainedValue() === event, "the event goes on")
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventDeltaAxis1), -2, "with its distance")
        XCTAssertEqual(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1), -20)
        XCTAssertEqual(reasons, [.noDisplayLink])
        XCTAssertFalse(ScrollPoster.shared.isGliding, "the poster was not fed")
        XCTAssertEqual(ScrollPoster.shared.motionStateForTests.buffer.y, 0)
    }

    /// The same with one axis smoothed and the other let through: the axis the poster could
    /// not take stays in the event (it was cleared, and its distance was lost).
    func testWheelEventWithoutADisplayLink_keepsTheAxisThePosterCouldNotTake() throws {
        let (display, restore) = scrollTapWithAStandInDisplay()
        defer { restore() }
        Options.shared.scroll.smoothHorizontal = false
        var reasons: [ScrollSystemLog.PassthroughReason] = []
        ScrollSystemLog.passthroughObserverForTests = { reasons.append($0) }

        display.isOn = false
        let unsmoothed = try wheelEvent(lines: -2, x: 3)
        XCTAssertNotNil(tap(unsmoothed))
        XCTAssertEqual(unsmoothed.getIntegerValueField(.scrollWheelEventDeltaAxis1), -2, "vertical: not taken, so it stays")
        XCTAssertEqual(unsmoothed.getIntegerValueField(.scrollWheelEventDeltaAxis2), 3)
        XCTAssertEqual(reasons, [.axisNotSmoothed, .noDisplayLink])

        // With a display link the poster takes the vertical axis and the event goes on with the other.
        display.isOn = true
        ScrollPoster.shared.clearRecreateCooldownForTests()
        let smoothed = try wheelEvent(lines: -2, x: 3)
        XCTAssertNotNil(tap(smoothed))
        XCTAssertEqual(smoothed.getIntegerValueField(.scrollWheelEventDeltaAxis1), 0, "vertical: the poster posts it")
        XCTAssertEqual(smoothed.getIntegerValueField(.scrollWheelEventDeltaAxis2), 3)
        XCTAssertTrue(ScrollPoster.shared.isGliding)
    }

    /// With a display link the event is swallowed and the poster glides.
    func testWheelEventWithADisplayLink_isTakenByThePoster() throws {
        let (display, restore) = scrollTapWithAStandInDisplay()
        defer { restore() }
        var reasons: [ScrollSystemLog.PassthroughReason] = []
        ScrollSystemLog.passthroughObserverForTests = { reasons.append($0) }

        XCTAssertNil(tap(try wheelEvent(lines: -1)), "swallowed: the poster posts the frames")

        XCTAssertEqual(reasons, [])
        XCTAssertTrue(ScrollPoster.shared.isGliding)
        XCTAssertEqual(ScrollPoster.shared.motionStateForTests.buffer.y, -33.6 * Options.shared.scroll.speed, accuracy: 1e-9)
        XCTAssertEqual(display.made.first?.isRunning, true)
    }

    /// C6 through the tap: a stored Step that is no finite number. The event goes on
    /// unsmoothed and the poster is not fed (it used to take a distance no frame can reach:
    /// nothing moved, the scroll never ended, the display link ran on).
    func testWheelEventWithAStepThatIsNoNumber_goesOnUnsmoothed() throws {
        let (display, restore) = scrollTapWithAStandInDisplay()
        defer { restore() }
        var reasons: [ScrollSystemLog.PassthroughReason] = []
        ScrollSystemLog.passthroughObserverForTests = { reasons.append($0) }
        for step in [Double.infinity, .nan, 1e308] {
            Options.shared.scroll.step = step
            let event = try wheelEvent(lines: -2)
            XCTAssertTrue(tap(event)?.takeUnretainedValue() === event, "Step \(step)")
            XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventDeltaAxis1), -2, "Step \(step)")
        }
        XCTAssertEqual(reasons, [.unusableSettings, .unusableSettings, .unusableSettings])
        XCTAssertFalse(ScrollPoster.shared.isGliding)
        XCTAssertEqual(display.tries, 0)
        XCTAssertEqual(ScrollSystemLog.PassthroughReason.unusableSettings.text, "Step or Speed is not a finite number")
    }

    /// Scrollio's own frames come back to the tap marked: they go on untouched (not smoothed
    /// again, not reversed, not counted).
    func testScrolliosOwnFrames_passTheTapUntouched() throws {
        let (_, restore) = scrollTapWithAStandInDisplay()
        defer { restore() }
        Options.shared.scroll.reverse = true
        var reasons: [ScrollSystemLog.PassthroughReason] = []
        ScrollSystemLog.passthroughObserverForTests = { reasons.append($0) }
        let frame = try wheelEvent(lines: -2)
        ScrollOutgoingFrame(y: -17, x: 0).write(to: frame)
        ScrollUtils.shared.markSyntheticSmoothEvent(frame)

        XCTAssertTrue(tap(frame)?.takeUnretainedValue() === frame)

        XCTAssertEqual(frame.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), -17, "not reversed")
        XCTAssertEqual(frame.getIntegerValueField(.scrollWheelEventDeltaAxis1), -2)
        XCTAssertEqual(reasons, [])
        XCTAssertFalse(ScrollPoster.shared.isGliding, "not smoothed again")
    }

    // MARK: Why a scroll ended

    /// The scroll's line says why it ended. It used to say "ended MomentumEnd" for every
    /// scroll, the ones a click or a finger cut short among them.
    func testSessionLine_saysWhyTheScrollEnded() {
        var session = ScrollSystemLog.Session()
        session.inputs = 1
        session.inputDistance = 211.68
        session.frames = 26
        session.postedDistance = 205
        session.largestFrame = 16
        session.transition = 0.158
        XCTAssertEqual(
            ScrollSystemLog.message(for: session, ended: .glidedOut),
            "scroll: 1 wheel events 212 px in -> 26 frames 205 px out (largest 16), wheel 0 ms, glide after the last event 0 ms, Duration 3.69 (tau 97 ms), trackpad-style off, ended: glided out"
        )
        let reasons: [ScrollSystemLog.EndReason: String] = [
            .glidedOut: "glided out", .leftClick: "left click", .fingerOnTrackpad: "a finger on the trackpad",
            .anotherApp: "the wheel went on in another app", .settingChanged: "trackpad-style was switched",
            .axisChanged: "the wheel turned between up-down and sideways",
            .tapRestarted: "the scroll tap was restarted", .keeper: "ended by the keeper", .stopped: "stopped",
        ]
        for (reason, text) in reasons {
            XCTAssertTrue(ScrollSystemLog.message(for: session, ended: reason).hasSuffix(", ended: \(text)"), text)
        }
    }

    /// Each way a scroll ends gives its own reason.
    func testEveryWayAScrollEnds_isToldApartInTheLog() {
        var ended: [ScrollSystemLog.EndReason] = []
        ScrollSystemLog.sessionObserverForTests = { ended.append($1) }
        defer { ScrollSystemLog.sessionObserverForTests = nil }
        func scroll() -> ScrollClassicRig {
            let rig = ScrollClassicRig(duration: 3.69)
            rig.input(211.68, notch: 211.68, at: 0, targetPID: 100)
            rig.run(until: 0.1)
            return rig
        }
        let glides = scroll()
        glides.run(until: 3)
        XCTAssertTrue(ScrollCore.stopWheelGlide(forTrackpadScrollPhase: 1, poster: scroll().poster))
        scroll().poster.stop(reason: .leftClick)
        scroll().poster.stop(.TrackingEnd, reason: .tapRestarted)
        scroll().poster.stop()
        scroll().input(211.68, notch: 211.68, at: 0.1, targetPID: 200)
        scroll().poster.changeFormForTests(simTrackpadEnabled: true)

        XCTAssertEqual(ended, [.glidedOut, .fingerOnTrackpad, .leftClick, .tapRestarted, .stopped, .anotherApp, .settingChanged])
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

// MARK: - The evaluation switch for the long touch

/// EVALUATION SWITCH: goes with `TrackpadStyleEvaluation` when the one-touch form is released.
/// A default read once at launch brings the old long touch back, so the two forms can be
/// compared on a real Mac. It is not a setting of the app.
final class TrackpadStyleEvaluationTests: XCTestCase {

    func testTheSafariSwitchIsOneDefaultReadAsABoolean() {
        XCTAssertEqual(TrackpadStyleEvaluation.safariFlickDefaultsKey, "trackpadStyleEvaluationSafariFlick")
        let defaults = TestDefaults.make(for: self)
        XCTAssertFalse(TrackpadStyleEvaluation.usesSafariFlick(in: defaults), "not set: no phases for Safari")
        defaults.set(true, forKey: TrackpadStyleEvaluation.safariFlickDefaultsKey)
        XCTAssertTrue(TrackpadStyleEvaluation.usesSafariFlick(in: defaults))
        XCTAssertFalse(TrackpadStyleEvaluation.usesOldLongTouch(in: defaults), "the two are two defaults")
        defaults.set(false, forKey: TrackpadStyleEvaluation.safariFlickDefaultsKey)
        XCTAssertFalse(TrackpadStyleEvaluation.usesSafariFlick(in: defaults))
    }

    func testTheSwitchIsOneDefaultReadAsABoolean() {
        XCTAssertEqual(TrackpadStyleEvaluation.defaultsKey, "trackpadStyleEvaluationOldLongTouch")
        let defaults = TestDefaults.make(for: self)
        XCTAssertFalse(TrackpadStyleEvaluation.usesOldLongTouch(in: defaults), "not set: the new form")
        defaults.set(true, forKey: TrackpadStyleEvaluation.defaultsKey)
        XCTAssertTrue(TrackpadStyleEvaluation.usesOldLongTouch(in: defaults))
        defaults.set(false, forKey: TrackpadStyleEvaluation.defaultsKey)
        XCTAssertFalse(TrackpadStyleEvaluation.usesOldLongTouch(in: defaults))
    }

    /// Under XCTest the real preferences are never read: the new form, whatever this Mac has set.
    func testUnderTestsTheNewFormIsUsed() {
        XCTAssertFalse(TrackpadStyleEvaluation.usesOldLongTouch)
        XCTAssertFalse(ScrollPoster(phases: ScrollPhase(), dispatchContext: ScrollDispatchContext()).usesOldLongTouch)
        XCTAssertFalse(TrackpadStyleEvaluation.usesSafariFlick)
        XCTAssertFalse(ScrollPoster(phases: ScrollPhase(), dispatchContext: ScrollDispatchContext()).usesSafariFlick)
    }

    func testTheLaunchLineSaysWhichFormIsInUse() {
        XCTAssertEqual(
            TrackpadStyleEvaluation.launchLine(usesOldLongTouch: false),
            "Trackpad-style scrolling, apps that are not Chromium-based or Gecko-based: one touch until the scroll has run out (evaluation switch trackpadStyleEvaluationOldLongTouch: not set)"
        )
        XCTAssertEqual(
            TrackpadStyleEvaluation.launchLine(usesOldLongTouch: true),
            "Trackpad-style scrolling, apps that are not Chromium-based or Gecko-based: the old long touch (a touch while the wheel turns, then its glide) (evaluation switch trackpadStyleEvaluationOldLongTouch: YES)"
        )
        XCTAssertEqual(
            TrackpadStyleEvaluation.safariLaunchLine(usesSafariFlick: false),
            "Trackpad-style scrolling, Safari: no phases, as with the switch off (evaluation switch trackpadStyleEvaluationSafariFlick: not set)"
        )
        XCTAssertEqual(
            TrackpadStyleEvaluation.safariLaunchLine(usesSafariFlick: true),
            "Trackpad-style scrolling, Safari: the flick, without the hardware record (no phases where the record does not come off a frame: the line about the hardware record says which) (evaluation switch trackpadStyleEvaluationSafariFlick: YES)"
        )
    }

    /// It is no setting: the app never writes it, and loading the settings (with their
    /// clean-up of retired keys) leaves it where the owner put it.
    func testTheAppNeitherWritesNorRemovesIt() {
        let defaults = TestDefaults.make(for: self)
        let options = Options()
        options.defaults = defaults
        options.scroll.smoothSimTrackpad = true
        options.saveOptions()
        XCTAssertNil(defaults.object(forKey: TrackpadStyleEvaluation.defaultsKey), "saving the settings does not write it")

        defaults.set(true, forKey: TrackpadStyleEvaluation.defaultsKey)
        options.readOptions()
        options.saveOptions()
        XCTAssertEqual(defaults.object(forKey: TrackpadStyleEvaluation.defaultsKey) as? Bool, true, "reading and saving leave it alone")
        XCTAssertFalse(ScrollSettingsCleanup.retiredDefaultsKeys.contains(TrackpadStyleEvaluation.defaultsKey))

        XCTAssertNil(defaults.object(forKey: TrackpadStyleEvaluation.safariFlickDefaultsKey), "nor the one for Safari")
        defaults.set(true, forKey: TrackpadStyleEvaluation.safariFlickDefaultsKey)
        options.readOptions()
        options.saveOptions()
        XCTAssertEqual(defaults.object(forKey: TrackpadStyleEvaluation.safariFlickDefaultsKey) as? Bool, true)
        XCTAssertFalse(ScrollSettingsCleanup.retiredDefaultsKeys.contains(TrackpadStyleEvaluation.safariFlickDefaultsKey))
    }
}
