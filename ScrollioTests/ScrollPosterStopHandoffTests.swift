import XCTest
import os
@testable import Scrollio_Debug

/// How a scroll session ends. The display link thread finds the motion finished, but it
/// does not end the session itself: it asks the main thread, and the request is dropped
/// when a wheel input arrived in the meantime.
///
/// Before, the display link thread called `stop` itself, after giving up the state lock:
/// a wheel tick arriving in that gap was wiped by the reset although its event had already
/// been swallowed, and `stop` touched main-thread state (the display link reference, the
/// running-application cache of ScrollUtils) from the wrong thread.
///
/// Nothing is posted here: frames go to the recorder.
final class ScrollPosterStopHandoffTests: XCTestCase {

    private let frameInterval = 1.0 / 60.0
    private let start = 100.0

    private var phases: ScrollPhase!
    private var poster: ScrollPoster!
    private var frames: [ScrollOutgoingFrame] = []
    private var now = 0.0

    override func setUp() {
        super.setUp()
        phases = ScrollPhase()
        poster = ScrollPoster(phases: phases, dispatchContext: ScrollDispatchContext())
        frames = []
        now = start
        poster.frameRecorderForTests = { [unowned self] frame in
            self.frames.append(frame)
        }
        poster.setConfigForTests(simTrackpadEnabled: false)
    }

    override func tearDown() {
        poster = nil
        phases = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func input(_ y: Double) -> ScrollPosterInput {
        let trans = OPTIONS_SCROLL_DEFAULT.generateDurationTransition(with: 3.13)
        return ScrollPosterInput(y: y, x: 0, notch: abs(y), duration: trans)
    }

    private func wheel(_ y: Double) {
        poster.inputForTests(input(y), at: now)
    }

    /// Runs display frames until one asks for the stop (at most 20 simulated seconds).
    private func runUntilStopRequest(file: StaticString = #filePath, line: UInt = #line) -> ScrollStopRequest? {
        for _ in 0..<1200 {
            now += frameInterval
            if let request = poster.displayLinkFrameForTests(frameInterval: frameInterval, now: now) {
                return request
            }
        }
        XCTFail("the motion never asked to stop", file: file, line: line)
        return nil
    }

    /// Runs `count` more frames and returns the requests they make.
    private func runFrames(_ count: Int) -> [ScrollStopRequest] {
        var requests: [ScrollStopRequest] = []
        for _ in 0..<count {
            now += frameInterval
            if let request = poster.displayLinkFrameForTests(frameInterval: frameInterval, now: now) {
                requests.append(request)
            }
        }
        return requests
    }

    private var movedY: Double { return frames.reduce(0) { $0 + $1.y } }

    private func drainMainQueue() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 2)
    }

    // MARK: - The request

    func testAFinishedMotionAsksForAStopInsteadOfStopping() throws {
        wheel(40)
        let request = try XCTUnwrap(runUntilStopRequest())

        // The frame only asked: the session state is still there.
        XCTAssertNotEqual(poster.motionStateForTests.current.y, 0)

        XCTAssertTrue(poster.performRequestedStop(request))
        XCTAssertEqual(poster.motionStateForTests.current.y, 0)
        XCTAssertEqual(poster.motionStateForTests.buffer.y, 0)
        XCTAssertEqual(phases.phase, .Idle)
    }

    func testOnlyOneRequestIsMadePerWheelInput() throws {
        wheel(40)
        _ = try XCTUnwrap(runUntilStopRequest())
        XCTAssertTrue(runFrames(30).isEmpty)
    }

    // MARK: - A wheel tick after the request

    /// The regression: the tick used to be wiped by the reset of the stop.
    func testAWheelTickAfterTheRequestIsKept() throws {
        wheel(40)
        let request = try XCTUnwrap(runUntilStopRequest())
        let movedBefore = movedY

        // The tick arrives on the main thread before the requested stop runs there.
        wheel(40)
        XCTAssertFalse(poster.performRequestedStop(request), "a stale request must do nothing")

        let state = poster.motionStateForTests
        XCTAssertEqual(state.buffer.y - state.current.y, 40, accuracy: 1.0, "the tick's distance is still to be scrolled")

        // The display link is still running: it scrolls the tick and then asks again.
        let second = try XCTUnwrap(runUntilStopRequest())
        XCTAssertNotEqual(second.inputSequence, request.inputSequence)
        // (Frames under the dead zone are not posted: the last few pixels stay unsent.)
        XCTAssertEqual(movedY - movedBefore, 37, accuracy: 4.0)
        XCTAssertTrue(poster.performRequestedStop(second))
        XCTAssertEqual(poster.motionStateForTests.current.y, 0)
    }

    func testAStaleRequestStaysStaleAfterLaterInputs() throws {
        wheel(40)
        let request = try XCTUnwrap(runUntilStopRequest())
        wheel(40)
        wheel(40)
        _ = runFrames(5)
        XCTAssertFalse(poster.performRequestedStop(request))
        XCTAssertNotEqual(poster.motionStateForTests.buffer.y, 0)
    }

    // MARK: - A stop from the main thread in between

    /// A click or a tap restart stops the session directly. The request that is still on its
    /// way is stale then: nothing is left to stop, and it must change and post nothing.
    /// (It used to run a second stop on the idle session, which moved the dispatch generation
    /// once more and could drop the closing frame the first stop had just queued.)
    func testARequestAfterADirectStopIsHarmless() throws {
        poster.setConfigForTests(simTrackpadEnabled: true)
        wheel(40)
        let request = try XCTUnwrap(runUntilStopRequest())
        poster.stop()
        let framesAfterDirectStop = frames.count

        XCTAssertFalse(poster.performRequestedStop(request), "stale: the scroll was ended meanwhile")
        XCTAssertEqual(frames.count, framesAfterDirectStop)
        XCTAssertEqual(phases.phase, .Idle)
        XCTAssertEqual(poster.motionStateForTests.current.y, 0)
    }

    // MARK: - A stop for TrackingEnd (tap timeout, tap restart)

    /// With trackpad-style events on, a stop for TrackingEnd in a momentum phase sent nothing
    /// (the plan of onManualInputEnded is empty there): a momentum "began" without "ended".
    func testAStopForTrackingEndDuringTheMomentumEndsTheMomentum() {
        poster.setConfigForTests(simTrackpadEnabled: true)
        wheel(200)
        var framesRun = 0
        while phases.phase != .MomentumBegin && phases.phase != .MomentumOngoing && framesRun < 120 {
            now += frameInterval
            _ = poster.displayLinkFrameForTests(frameInterval: frameInterval, now: now)
            framesRun += 1
        }
        XCTAssertTrue(phases.phase == .MomentumBegin || phases.phase == .MomentumOngoing, "\(phases.phase)")
        XCTAssertTrue(frames.contains { $0.momentumPhase == 1 }, "the momentum began")
        let before = frames.count

        poster.stop(.TrackingEnd)

        let sent = frames[before...]
        XCTAssertEqual(sent.map(\.momentumPhase), [3], "one frame: momentum ended")
        XCTAssertEqual(sent.map(\.scrollPhase), [0])
        XCTAssertEqual(sent.map(\.y), [0])
        XCTAssertEqual(phases.phase, .Idle)
    }

    /// While the wheel is still being followed, a stop for TrackingEnd ends the tracking, as
    /// before.
    func testAStopForTrackingEndWhileTrackingEndsTheTracking() {
        poster.setConfigForTests(simTrackpadEnabled: true)
        wheel(40)
        _ = runFrames(2)
        XCTAssertTrue(phases.phase == .TrackingBegin || phases.phase == .TrackingOngoing, "\(phases.phase)")
        let before = frames.count

        poster.stop(.TrackingEnd)

        let sent = frames[before...]
        XCTAssertEqual(sent.map(\.scrollPhase), [4], "one frame: tracking ended")
        XCTAssertEqual(sent.map(\.momentumPhase), [0])
        XCTAssertEqual(phases.phase, .Idle)
    }

    // MARK: - The diagnostics line of a Debug build

    /// The drop counters are cumulative: after the first dropped frame every stop wrote the
    /// same line again. A line is written when they changed.
    func testTheDiagnosticsLineIsWrittenOnlyWhenTheDropsChanged() {
        typealias Drops = ScrollPoster.DropCounts
        XCTAssertFalse(Drops().isLogDue(lastLogged: Drops()), "nothing dropped: no line")
        let one = Drops(byGeneration: 1)
        XCTAssertTrue(one.isLogDue(lastLogged: Drops()))
        XCTAssertFalse(one.isLogDue(lastLogged: one), "the same counts: no second line")
        XCTAssertTrue(Drops(byGeneration: 1, byTTL: 2).isLogDue(lastLogged: one))
        XCTAssertTrue(Drops(byGeneration: 1, snapshotFailures: 1).isLogDue(lastLogged: one))
    }

    // MARK: - Threads

    /// The display link callback, run on a background thread like the real one, leaves the
    /// session alone; the stop happens once the main queue runs.
    func testTheDisplayLinkThreadHandsTheStopToTheMainThread() {
        wheel(40)
        let finished = DispatchSemaphore(value: 0)
        let poster = self.poster!
        let frameInterval = self.frameInterval
        var time = now

        DispatchQueue.global(qos: .userInteractive).async {
            for _ in 0..<1200 {
                time += frameInterval
                poster.displayLinkCallbackForTests(frameInterval: frameInterval, now: time)
            }
            finished.signal()
        }
        // The main thread is busy here, as it can be when the real callback fires.
        XCTAssertEqual(finished.wait(timeout: .now() + 10), .success)

        XCTAssertNotEqual(poster.motionStateForTests.current.y, 0,
                          "the background thread must not have ended the session")
        XCTAssertNotEqual(phases.phase, .Idle)

        drainMainQueue()
        XCTAssertEqual(poster.motionStateForTests.current.y, 0)
        XCTAssertEqual(phases.phase, .Idle)
    }

    /// The same with a tick that reaches the main thread first: the queued stop finds itself
    /// stale and the tick survives.
    func testAQueuedStopIsDroppedWhenATickArrivesFirst() {
        wheel(40)
        let finished = DispatchSemaphore(value: 0)
        let poster = self.poster!
        let frameInterval = self.frameInterval
        var time = now

        DispatchQueue.global(qos: .userInteractive).async {
            for _ in 0..<1200 {
                time += frameInterval
                poster.displayLinkCallbackForTests(frameInterval: frameInterval, now: time)
            }
            finished.signal()
        }
        XCTAssertEqual(finished.wait(timeout: .now() + 10), .success)

        // Still on the main thread, ahead of the queued stop.
        poster.inputForTests(input(40), at: start + 1200 * frameInterval)
        drainMainQueue()

        let state = poster.motionStateForTests
        XCTAssertEqual(state.buffer.y - state.current.y, 40, accuracy: 1.0)
    }
}

/// When a replaced display link runs. A recreated link used to be started always: from the
/// screen-change observer (which runs while paused or asleep too) or the keeper it then ran
/// at the display's rate until the next scroll ended, and that scroll's tryStart, finding it
/// running, skipped following the display under the pointer.
///
/// These use real display links (no session, nothing posted); without a display to make
/// or start one they are skipped.
final class ScrollPosterDisplayLinkTests: XCTestCase {

    private var poster: ScrollPoster!

    override func setUp() {
        super.setUp()
        poster = ScrollPoster(phases: ScrollPhase(), dispatchContext: ScrollDispatchContext())
    }

    override func tearDown() {
        poster.stop()
        poster.stopKeeper()
        poster = nil
        super.tearDown()
    }

    private func requireDisplayLink() throws {
        guard poster.isAvailable else { throw XCTSkip("no display link can be made here") }
    }

    private func requireRunning() throws {
        guard poster.isDisplayLinkRunningForTests else { throw XCTSkip("the display link cannot be started here") }
    }

    func testTheRule() {
        XCTAssertFalse(ScrollPoster.startsRecreatedDisplayLink(replacedWasRunning: false, scrollWaiting: false))
        XCTAssertTrue(ScrollPoster.startsRecreatedDisplayLink(replacedWasRunning: true, scrollWaiting: false))
        XCTAssertTrue(ScrollPoster.startsRecreatedDisplayLink(replacedWasRunning: false, scrollWaiting: true))
    }

    /// A display change while nothing scrolls (or while paused): the new link waits.
    func testAnIdleLinkThatIsReplacedStaysIdle() throws {
        poster.create()
        try requireDisplayLink()
        XCTAssertFalse(poster.isDisplayLinkRunningForTests)
        let replaced = poster.displayLinkForTests

        XCTAssertTrue(poster.recreateDisplayLink())
        XCTAssertTrue(poster.isAvailable)
        XCTAssertTrue(poster.displayLinkForTests !== replaced, "a new link")
        XCTAssertFalse(poster.isDisplayLinkRunningForTests, "nothing would stop it before the next scroll ends")

        // The next wheel event starts it, as before.
        poster.tryStart()
        try requireRunning()
    }

    /// A display change during a glide: the glide goes on with the new link.
    func testALinkReplacedDuringAGlideRuns() throws {
        poster.create()
        try requireDisplayLink()
        poster.tryStart()
        try requireRunning()
        poster.clearRecreateCooldownForTests()
        let replaced = poster.displayLinkForTests

        XCTAssertTrue(poster.recreateDisplayLink())
        XCTAssertTrue(poster.displayLinkForTests !== replaced)
        XCTAssertTrue(poster.isDisplayLinkRunningForTests)
        if let replaced = replaced {
            XCTAssertFalse(replaced.isRunning, "the replaced link is stopped")
        }

        poster.stop()
        XCTAssertFalse(poster.isDisplayLinkRunningForTests)
    }

    /// The keeper finds no link: it makes one and leaves it to the next scroll.
    func testTheKeeperMakesAMissingLinkWithoutStartingIt() throws {
        XCTAssertFalse(poster.isAvailable)
        poster.healthCheckForTests()
        try requireDisplayLink()
        XCTAssertFalse(poster.isDisplayLinkRunningForTests)
    }

    /// A wheel event that finds no link at all: the new link starts at once.
    func testAWheelEventWithoutALinkStartsTheNewOne() throws {
        XCTAssertFalse(poster.isAvailable)
        poster.tryStart()
        try requireDisplayLink()
        let startedByTheWheelEvent = poster.isDisplayLinkRunningForTests
        if !startedByTheWheelEvent, let link = poster.displayLinkForTests,
           link.start() != kCVReturnSuccess {
            throw XCTSkip("the display link cannot be started here")
        }
        XCTAssertTrue(startedByTheWheelEvent)
    }

    // MARK: - With a stand-in for the display (these run with the display off too)

    private func wheelEvent(targetPID: Int64 = 4242) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0))
        event.setIntegerValueField(.eventTargetUnixProcessID, value: targetPID)
        return event
    }

    private func input(_ y: Double = 211.68) -> ScrollPosterInput {
        return ScrollPosterInput(y: y, x: 0, notch: abs(y), duration: OPTIONS_SCROLL_DEFAULT().durationTransition)
    }

    /// `stop()` ends the display link. (The test with a real link is skipped while the
    /// display is off, and a `stop()` that left the link running went unnoticed there.)
    func testStopEndsTheDisplayLink() throws {
        let display = FakeDisplay(for: poster)
        XCTAssertTrue(poster.create())
        let link = try XCTUnwrap(display.made.first)
        XCTAssertFalse(link.isRunning, "made, not started")
        XCTAssertTrue(poster.tryStart())
        XCTAssertTrue(link.isRunning)
        XCTAssertEqual(link.follows, 1, "tied to the display under the pointer before it runs")

        poster.stop()

        XCTAssertFalse(link.isRunning)
        XCTAssertFalse(poster.isDisplayLinkRunningForTests)
        XCTAssertTrue(poster.isAvailable, "stopped, not thrown away")
        XCTAssertTrue(poster.displayLinkForTests === link)
    }

    /// B5: the new link is made first. When none can be made (the display went off) the link
    /// in use stays, running if it ran. It used to be released before the try.
    func testALinkInUseStaysWhenNoNewOneCanBeMade() throws {
        let display = FakeDisplay(for: poster)
        poster.create()
        poster.tryStart()
        let inUse = try XCTUnwrap(display.made.first)
        XCTAssertTrue(inUse.isRunning)

        display.isOn = false
        poster.clearRecreateCooldownForTests()
        XCTAssertTrue(poster.recreateDisplayLink(), "the cooldown let it try")

        XCTAssertTrue(poster.displayLinkForTests === inUse, "the link in use is still there")
        XCTAssertTrue(inUse.isRunning, "and still runs")
        XCTAssertEqual(inUse.stops, 0)
        XCTAssertTrue(poster.isAvailable)

        // The display is back: the next try replaces it, and the replaced one is stopped.
        display.isOn = true
        poster.clearRecreateCooldownForTests()
        XCTAssertTrue(poster.recreateDisplayLink())
        let replacement = try XCTUnwrap(display.made.last)
        XCTAssertTrue(poster.displayLinkForTests === replacement)
        XCTAssertFalse(inUse.isRunning)
        XCTAssertTrue(replacement.isRunning, "a glide goes on with the new link")
    }

    /// B5: with the display off every try fails. The log gets the first failure and the
    /// first success after it: it used to get an error line per try, one every 5 s.
    func testADisplayLinkThatCannotBeMadeIsLoggedOnceAndOnceWhenItWorksAgain() {
        let display = FakeDisplay(for: poster)
        display.isOn = false

        XCTAssertFalse(poster.create())
        XCTAssertFalse(poster.create())
        XCTAssertFalse(poster.create())
        XCTAssertEqual(display.tries, 3)
        XCTAssertEqual(poster.healthLinesForTests, [
            ScrollPoster.displayLinkFailureLine(result: -6661, keepsTheLinkInUse: false),
        ])
        XCTAssertTrue(poster.healthLinesForTests.first?.contains("wheel events go through unsmoothed") ?? false)
        XCTAssertFalse(poster.isAvailable)

        display.isOn = true
        XCTAssertTrue(poster.create())
        XCTAssertTrue(poster.create())
        XCTAssertEqual(poster.healthLinesForTests.count, 2)
        XCTAssertEqual(poster.healthLinesForTests.last, "ScrollPoster: a display link could be made again, after 3 failed tries")

        // And a new line the next time it fails.
        display.isOn = false
        XCTAssertFalse(poster.create())
        XCTAssertEqual(poster.healthLinesForTests.count, 3)
        XCTAssertTrue(poster.healthLinesForTests.last?.contains("the link in use stays") ?? false)
    }

    /// B5: while no link can be made the keeper tries less and less often (it tried every
    /// 5 s for as long as the display was off).
    func testTheKeeperBacksOffWhileNoLinkCanBeMade() {
        let display = FakeDisplay(for: poster)
        display.isOn = false
        var triedAt: [Double] = []
        // The keeper looks every 5 s, for five minutes.
        for look in 0...60 {
            let before = display.tries
            poster.healthCheckForTests(now: 1_000 + Double(look) * ScrollPoster.keeperInterval)
            if display.tries > before { triedAt.append(Double(look) * ScrollPoster.keeperInterval) }
        }
        XCTAssertEqual(triedAt, [0, 5, 15, 35, 75, 135, 195, 255], "5, 10, 20, 40, then every 60 s")
        XCTAssertEqual(poster.healthLinesForTests.count, 1, "one line for all of them")

        // A display wakes: tried at once, whatever the keeper's wait. Made, not started.
        display.isOn = true
        let before = display.tries
        poster.screensDidWake()
        XCTAssertEqual(display.tries, before + 1)
        XCTAssertTrue(poster.isAvailable)
        XCTAssertFalse(poster.isDisplayLinkRunningForTests, "the next wheel event starts it")
        XCTAssertEqual(poster.healthLinesForTests.count, 2)

        // With a link in place a display that wakes changes nothing.
        poster.screensDidWake()
        XCTAssertEqual(display.tries, before + 1)
    }

    /// B5: a wheel event tries at once after the keeper's failed try (it used to be refused
    /// for 3 s and went through unsmoothed), and wheel events themselves try once per cooldown.
    func testAWheelEventTriesAtOnceAfterTheKeepersFailedTry() {
        let display = FakeDisplay(for: poster)
        display.isOn = false
        poster.healthCheckForTests(now: 1_000)
        XCTAssertEqual(display.tries, 1)

        display.isOn = true
        XCTAssertTrue(poster.tryStart(), "the wheel event's own try is not refused")
        XCTAssertEqual(display.tries, 2)
        XCTAssertTrue(poster.isDisplayLinkRunningForTests)
    }

    func testWheelEventsTryOncePerCooldownWhileNoLinkCanBeMade() {
        let display = FakeDisplay(for: poster)
        display.isOn = false
        for _ in 0..<50 {
            XCTAssertFalse(poster.tryStart())
        }
        XCTAssertEqual(display.tries, 1, "not one try per wheel event")
    }

    /// C1: a wheel event that finds no display link is not taken, and nothing of the poster
    /// is touched. It used to be fed first: the scroll counted as open, with trackpad-style
    /// events a "began" went out that never got its "ended", and the distance waited in the
    /// buffer while the event went through as well.
    func testAWheelEventWithoutADisplayLinkIsNotTakenAndLeavesNothingBehind() throws {
        let display = FakeDisplay(for: poster)
        display.isOn = false
        var frames: [ScrollOutgoingFrame] = []
        poster.frameRecorderForTests = { frames.append($0) }
        poster.setConfigForTests(simTrackpadEnabled: true)

        XCTAssertFalse(poster.smooth(event: try wheelEvent(), input: input()))
        XCTAssertFalse(poster.smooth(event: try wheelEvent(), input: input()))

        XCTAssertFalse(poster.isGliding, "no scroll was opened")
        XCTAssertTrue(poster.sessionLogForTests.isEmpty)
        XCTAssertEqual(poster.motionStateForTests.buffer.y, 0, "no distance waits for a link")
        XCTAssertEqual(frames, [], "no \"began\" without its \"ended\"")

        // The display is back: the next event is smoothed, and only its own distance.
        display.isOn = true
        poster.clearRecreateCooldownForTests()
        XCTAssertTrue(poster.smooth(event: try wheelEvent(), input: input()))
        XCTAssertTrue(poster.isGliding)
        XCTAssertEqual(poster.motionStateForTests.buffer.y, 211.68, accuracy: 1e-9)
        XCTAssertTrue(poster.isDisplayLinkRunningForTests)
    }

    /// C2: a link that exists but cannot be started (its display is gone) and cannot be
    /// replaced does not take the event either. It used to count as "available": the event
    /// was swallowed and nothing was posted.
    func testALinkThatCannotBeStartedDoesNotTakeTheWheelEvent() throws {
        let display = FakeDisplay(for: poster)
        poster.create()
        display.startResult = kCVReturnDisplayLinkNotRunning
        display.made.first?.startResult = kCVReturnDisplayLinkNotRunning

        XCTAssertFalse(poster.smooth(event: try wheelEvent(), input: input()))

        XCTAssertTrue(poster.isAvailable, "a link exists")
        XCTAssertFalse(poster.isDisplayLinkRunningForTests)
        XCTAssertFalse(poster.isGliding)
        XCTAssertEqual(poster.motionStateForTests.buffer.y, 0)

        // A link that starts again takes the next event.
        display.startResult = kCVReturnSuccess
        poster.clearRecreateCooldownForTests()
        XCTAssertTrue(poster.smooth(event: try wheelEvent(), input: input()))
        XCTAssertTrue(poster.isDisplayLinkRunningForTests)
    }

    /// C6: a distance that is no finite number (a stored Step of 1e308 times Speed) is not
    /// taken. It used to be taken: no frame could move toward it, the scroll never ended and
    /// the display link ran on.
    func testAnInputThatIsNotAFiniteNumberIsNotTaken() throws {
        let display = FakeDisplay(for: poster)
        for bad in [Double.infinity, -.infinity, .nan] {
            XCTAssertFalse(ScrollPosterInput(y: bad, x: 0, notch: 211.68, duration: 0.158).isUsable)
            XCTAssertFalse(ScrollPosterInput(y: 10, x: bad, notch: 211.68, duration: 0.158).isUsable)
            XCTAssertFalse(ScrollPosterInput(y: 10, x: 0, notch: bad, duration: 0.158).isUsable)
            XCTAssertFalse(poster.smooth(event: try wheelEvent(), input: ScrollPosterInput(y: bad, x: 0, notch: 211.68, duration: 0.158)))
        }
        XCTAssertTrue(ScrollPosterInput(y: 10, x: -3, notch: 211.68, duration: 0.158).isUsable)
        XCTAssertFalse(poster.isGliding)
        XCTAssertEqual(display.tries, 0, "not even a display link was asked for")
    }

    /// The safety net: a display link that runs on with nothing posted and no wheel event is
    /// stopped by the keeper, whatever kept it running, and an open scroll is ended.
    func testTheKeeperStopsADisplayLinkThatRunsOnWithNothingToDo() throws {
        let display = FakeDisplay(for: poster)
        var ended: [ScrollSystemLog.EndReason] = []
        ScrollSystemLog.sessionObserverForTests = { ended.append($1) }
        defer { ScrollSystemLog.sessionObserverForTests = nil }
        poster.frameRecorderForTests = { _ in }
        poster.setConfigForTests(simTrackpadEnabled: false)
        let start = ScrollPoster.monotonicNow()
        XCTAssertTrue(poster.tryStart())
        let link = try XCTUnwrap(display.made.first)
        // A scroll that can never end: the display link runs, and its frames find nothing to post.
        poster.inputForTests(ScrollPosterInput(y: 0.2, x: 0, notch: 0.2, duration: 0.158), at: start)
        XCTAssertTrue(poster.isGliding)

        // Frames keep coming (the link is not stuck), the last wheel event was 4 s ago: left alone.
        poster.displayLinkCallbackForTests(frameInterval: 1.0 / 60.0, now: start + 3.9)
        poster.healthCheckForTests(now: start + 4)
        XCTAssertTrue(link.isRunning)
        XCTAssertEqual(display.tries, 1)

        // Still nothing 9 s after it: stopped, the scroll ended, one line in the log.
        poster.displayLinkCallbackForTests(frameInterval: 1.0 / 60.0, now: start + 8.9)
        poster.healthCheckForTests(now: start + 9)
        XCTAssertFalse(link.isRunning, "the app idles again")
        XCTAssertFalse(poster.isGliding)
        XCTAssertEqual(ended, [.keeper])
        XCTAssertEqual(poster.healthLinesForTests.count, 1)
        XCTAssertTrue(poster.healthLinesForTests.first?.contains("with nothing posted and no wheel event") ?? false, "\(poster.healthLinesForTests)")
        XCTAssertEqual(display.tries, 1, "stopped, not replaced")
    }

    /// A scroll that posts frames or gets wheel events is never taken for idle.
    func testTheKeeperLeavesAScrollThatPostsAlone() throws {
        let display = FakeDisplay(for: poster)
        poster.frameRecorderForTests = { _ in }
        poster.setConfigForTests(simTrackpadEnabled: false)
        let start = ScrollPoster.monotonicNow()
        XCTAssertTrue(poster.tryStart())
        let link = try XCTUnwrap(display.made.first)
        var now = start
        // A wheel that turns for 20 s, a click every 0.3 s, the keeper looking every 5 s.
        var nextClick = start
        var nextLook = start + ScrollPoster.keeperInterval
        while now < start + 20 {
            now += 1.0 / 60.0
            if now >= nextClick {
                poster.inputForTests(input(), at: now)
                nextClick += 0.3
            }
            poster.displayLinkCallbackForTests(frameInterval: 1.0 / 60.0, now: now)
            if now >= nextLook {
                poster.healthCheckForTests(now: now)
                nextLook += ScrollPoster.keeperInterval
            }
        }
        XCTAssertTrue(link.isRunning)
        XCTAssertTrue(poster.isGliding)
        XCTAssertEqual(poster.healthLinesForTests, [])
        XCTAssertEqual(display.tries, 1)
    }

    /// The keeper's older rule still holds: a link that runs and sends no frame is replaced.
    func testTheKeeperReplacesALinkThatIsStuck() throws {
        let display = FakeDisplay(for: poster)
        let start = ScrollPoster.monotonicNow()
        XCTAssertTrue(poster.tryStart())
        let stuck = try XCTUnwrap(display.made.first)
        poster.clearRecreateCooldownForTests()

        poster.healthCheckForTests(now: start + 3)

        XCTAssertEqual(display.made.count, 2)
        XCTAssertFalse(stuck.isRunning)
        XCTAssertEqual(display.made.last?.isRunning, true, "the replacement runs: the replaced one did")
        XCTAssertTrue(poster.healthLinesForTests.first?.contains("stuck") ?? false)

        // Still no frame and nobody scrolls: the next look stops it for good, instead of
        // putting a new running link in its place every 5 s.
        poster.clearRecreateCooldownForTests()
        poster.healthCheckForTests(now: ScrollPoster.monotonicNow() + 8)
        XCTAssertEqual(display.made.count, 2, "not replaced again")
        XCTAssertEqual(display.made.last?.isRunning, false)
        XCTAssertFalse(poster.isDisplayLinkRunningForTests)
    }

    /// A scroll that is open while its display link does not run gets no frame and never
    /// ends by itself: the keeper ends it.
    func testTheKeeperEndsAScrollWhoseDisplayLinkDoesNotRun() throws {
        let display = FakeDisplay(for: poster)
        poster.frameRecorderForTests = { _ in }
        XCTAssertTrue(poster.smooth(event: try wheelEvent(), input: input()))
        let link = try XCTUnwrap(display.made.first)
        link.isRunning = false   // as a replaced link that could not be started

        poster.healthCheckForTests()

        XCTAssertFalse(poster.isGliding)
        XCTAssertTrue(poster.healthLinesForTests.first?.contains("does not run") ?? false)
    }

    /// C5: two stops in a row. The second finds nothing to end and must not move the
    /// dispatch generation again: it could drop the closing frame the first had just queued.
    func testASecondStopInARowLeavesTheClosingFrameOfTheFirstAlone() throws {
        let context = ScrollDispatchContext()
        let poster = ScrollPoster(phases: ScrollPhase(), dispatchContext: context)
        let display = FakeDisplay(for: poster)
        var posted: [(phase: Double, pid: pid_t)] = []
        let lock = NSLock()
        context.postObserverForTests = { event, pid in
            lock.lock()
            posted.append((event.getDoubleValueField(.scrollWheelEventScrollPhase), pid))
            lock.unlock()
        }
        func generation() throws -> UInt64 {
            context.capture(event: try wheelEvent())
            defer { context.clearContext() }
            return try XCTUnwrap(context.preparePostingSnapshot()).generation
        }
        let before = try generation()
        XCTAssertTrue(poster.smooth(event: try wheelEvent(), input: input()))
        poster.setConfigForTests(simTrackpadEnabled: true, flick: false)
        // A frame: the touch has begun, and what was posted so far has reached the app.
        poster.displayLinkCallbackForTests(frameInterval: 1.0 / 60.0, now: ScrollPoster.monotonicNow())
        context.waitForPostQueueForTests()

        poster.stop(.TrackingEnd, reason: .tapRestarted)   // the tap's restart
        poster.stop(.TrackingEnd, reason: .tapRestarted)   // and its "disabled" event, in the same turn
        poster.stop()

        XCTAssertEqual(try generation(), before + 1, "one scroll ended: one step")
        context.waitForPostQueueForTests()
        lock.lock()
        let phases = posted.map(\.phase)
        lock.unlock()
        XCTAssertEqual(phases.last, 4, "the closing \"ended\" was posted, not dropped")
        XCTAssertEqual(phases.filter { $0 == 4 }.count, 1)
        XCTAssertEqual(context.diagnosticsSnapshot().droppedFramesByGeneration, 0)
        XCTAssertEqual(display.made.first?.isRunning, false)
    }

    /// B2 through the poster's real entry, with events that carry their target: a wheel
    /// event for another process ends the scroll that runs before anything of it is taken.
    /// Every frame of the first scroll goes to the first process, the second scroll is one
    /// of its own, and the display link runs on for it.
    func testAWheelEventForAnotherProcessEndsTheScrollThatRunsFirst() throws {
        let savedApplication = ScrollCore.shared.application
        ScrollCore.shared.application = nil
        defer { ScrollCore.shared.application = savedApplication }
        let context = ScrollDispatchContext()
        let poster = ScrollPoster(phases: ScrollPhase(), dispatchContext: context)
        let display = FakeDisplay(for: poster)
        var posted: [pid_t] = []
        let lock = NSLock()
        context.postObserverForTests = { _, pid in
            lock.lock()
            posted.append(pid)
            lock.unlock()
        }
        func postedSoFar() -> [pid_t] {
            context.waitForPostQueueForTests()
            lock.lock()
            defer { lock.unlock() }
            return posted
        }
        var ended: [ScrollSystemLog.EndReason] = []
        ScrollSystemLog.sessionObserverForTests = { ended.append($1) }
        defer { ScrollSystemLog.sessionObserverForTests = nil }
        var now = ScrollPoster.monotonicNow()
        func frames(_ count: Int) {
            for _ in 0..<count {
                now += 1.0 / 60.0
                poster.displayLinkCallbackForTests(frameInterval: 1.0 / 60.0, now: now)
            }
        }

        XCTAssertTrue(poster.smooth(event: try wheelEvent(targetPID: 100), input: input()))
        frames(6)
        XCTAssertEqual(context.targetPID, 100)
        let inTheFirst = postedSoFar()
        XCTAssertGreaterThan(inTheFirst.count, 3)
        XCTAssertTrue(inTheFirst.allSatisfy { $0 == 100 })
        XCTAssertGreaterThan(poster.motionStateForTests.buffer.y - poster.motionStateForTests.current.y, 50, "its glide still runs")

        XCTAssertTrue(poster.smooth(event: try wheelEvent(targetPID: 200), input: input()))

        XCTAssertEqual(ended, [.anotherApp])
        XCTAssertEqual(context.targetPID, 200)
        XCTAssertEqual(poster.sessionLogForTests.inputs, 1, "a scroll of its own")
        XCTAssertEqual(poster.motionStateForTests.buffer.y, 211.68, accuracy: 1e-9, "with nothing of the first one's glide")
        XCTAssertEqual(display.made.last?.isRunning, true, "the display link runs for it")
        frames(6)
        let all = postedSoFar()
        XCTAssertGreaterThan(all.count, inTheFirst.count + 3)
        XCTAssertTrue(all.dropFirst(inTheFirst.count).allSatisfy { $0 == 200 }, "\(all)")
        XCTAssertEqual(context.diagnosticsSnapshot().droppedFramesByTTL, 0)
        poster.stop()
    }

    /// B1 through the poster's real entry: "Trackpad-style scrolling" is switched off (from
    /// the keyboard) while a touch is open, and the wheel goes on in the same process. The
    /// touch gets its "ended" before any frame of the next event; that event's scroll is one
    /// of its own, without phases. The scroll used to be taken over as it was: frames
    /// without phases followed the "began", and no "ended" ever came.
    func testSwitchingTrackpadStyleOffInMidScrollClosesTheTouchFirst() throws {
        let savedApplication = ScrollCore.shared.application
        let savedSwitch = Options.shared.scroll.smoothSimTrackpad
        ScrollCore.shared.application = nil
        defer {
            ScrollCore.shared.application = savedApplication
            Options.shared.scroll.smoothSimTrackpad = savedSwitch
        }
        let context = ScrollDispatchContext()
        let poster = ScrollPoster(phases: ScrollPhase(), dispatchContext: context)
        poster.trackpadStyleTarget = { _ in .touchOnly }
        let display = FakeDisplay(for: poster)
        var posted: [(scroll: Double, momentum: Double)] = []
        let lock = NSLock()
        context.postObserverForTests = { event, _ in
            lock.lock()
            posted.append((event.getDoubleValueField(.scrollWheelEventScrollPhase), event.getDoubleValueField(.scrollWheelEventMomentumPhase)))
            lock.unlock()
        }
        func postedSoFar() -> [(scroll: Double, momentum: Double)] {
            context.waitForPostQueueForTests()
            lock.lock()
            defer { lock.unlock() }
            return posted
        }
        var ended: [ScrollSystemLog.EndReason] = []
        ScrollSystemLog.sessionObserverForTests = { ended.append($1) }
        defer { ScrollSystemLog.sessionObserverForTests = nil }
        var now = ScrollPoster.monotonicNow()
        func frames(_ count: Int) {
            for _ in 0..<count {
                now += 1.0 / 60.0
                poster.displayLinkCallbackForTests(frameInterval: 1.0 / 60.0, now: now)
            }
        }

        Options.shared.scroll.smoothSimTrackpad = true
        XCTAssertTrue(poster.smooth(event: try wheelEvent(), input: input()))
        frames(4)
        let touch = postedSoFar()
        XCTAssertEqual(touch.first?.scroll, 1, "began")
        XCTAssertEqual(touch.last?.scroll, 2, "the touch is open")

        Options.shared.scroll.smoothSimTrackpad = false
        XCTAssertTrue(poster.smooth(event: try wheelEvent(), input: input()))
        frames(4)

        XCTAssertEqual(ended, [.settingChanged])
        let after = Array(postedSoFar().dropFirst(touch.count))
        XCTAssertEqual(after.prefix(3).map(\.scroll), [4, 128, 8], "the touch got its \"ended\" first, and the tap that follows a forced end")
        XCTAssertGreaterThan(after.count, 5)
        XCTAssertTrue(after.dropFirst(3).allSatisfy { $0.scroll == 0 && $0.momentum == 0 }, "then frames without phases: \(after)")
        XCTAssertEqual(poster.sessionLogForTests.inputs, 1, "a scroll of its own")
        XCTAssertEqual(poster.motionStateForTests.buffer.y, 211.68, accuracy: 1e-9)
        XCTAssertEqual(display.made.last?.isRunning, true, "the display link runs for it")
        poster.stop()
    }

    /// B2: `stop()` waits until its closing frames went out (for its deadline at most; here
    /// the deadline is out of the way). A finger begins to
    /// scroll on the trackpad while the wheel's touch is open: the tap's callback ends the
    /// wheel's scroll and then lets the trackpad's "began" through. The closing "ended" used
    /// to be posted from another queue some time after `stop()` had returned, so nothing
    /// kept it ahead of that "began". The post is slow here (20 ms): without the wait
    /// `stop()` is back long before the frame is out.
    func testAStopReturnsAfterItsClosingFrameWentOut() throws {
        let savedApplication = ScrollCore.shared.application
        let savedSwitch = Options.shared.scroll.smoothSimTrackpad
        ScrollCore.shared.application = nil
        Options.shared.scroll.smoothSimTrackpad = true
        defer {
            ScrollCore.shared.application = savedApplication
            Options.shared.scroll.smoothSimTrackpad = savedSwitch
        }
        let context = ScrollDispatchContext()
        let poster = ScrollPoster(phases: ScrollPhase(), dispatchContext: context)
        poster.trackpadStyleTarget = { _ in .touchOnly }
        _ = FakeDisplay(for: poster)
        var posted: [Double] = []
        let lock = NSLock()
        context.closingFrameDeadline = 10   // the post is slow on purpose
        context.postObserverForTests = { event, _ in
            Thread.sleep(forTimeInterval: 0.02)
            lock.lock()
            posted.append(event.getDoubleValueField(.scrollWheelEventScrollPhase))
            lock.unlock()
        }
        var waits = 0
        context.waitObserverForTests = { waits += 1 }

        XCTAssertTrue(poster.smooth(event: try wheelEvent(), input: input()))
        var now = ScrollPoster.monotonicNow()
        for _ in 0..<2 {
            now += 1.0 / 60.0
            poster.displayLinkCallbackForTests(frameInterval: 1.0 / 60.0, now: now)
        }
        XCTAssertEqual(waits, 0, "no frame of a running scroll is waited for")
        // What was posted so far has reached the app ("began" and two "changed").
        context.waitForPostQueueForTests()

        XCTAssertTrue(ScrollCore.stopWheelGlide(forTrackpadScrollPhase: 1, poster: poster))

        // Read at once, without waiting for the queue.
        lock.lock()
        let phases = posted
        lock.unlock()
        XCTAssertEqual(Array(phases.suffix(3)), [4, 128, 8], "the closing \"ended\" and its tap are out when stop() returns: \(phases)")
        XCTAssertEqual(phases.first, 1)
        XCTAssertEqual(waits, 1)

        // A stop with nothing to close waits for nothing.
        poster.stop()
        XCTAssertEqual(waits, 1)
    }

    /// B2, the other side: without trackpad-style phases a stop queues nothing an app waits
    /// for, and it does not wait on the post queue at all. The queue is blocked here (a post
    /// that does not return until the test lets it): a stop that touched the queue would
    /// hang. This is the switch-off path inside the tap callback, which must stay as it was.
    func testAStopWithoutPhasesDoesNotWaitForTheQueue() throws {
        let savedApplication = ScrollCore.shared.application
        let savedSwitch = Options.shared.scroll.smoothSimTrackpad
        ScrollCore.shared.application = nil
        Options.shared.scroll.smoothSimTrackpad = false
        defer {
            ScrollCore.shared.application = savedApplication
            Options.shared.scroll.smoothSimTrackpad = savedSwitch
        }
        let context = ScrollDispatchContext()
        let poster = ScrollPoster(phases: ScrollPhase(), dispatchContext: context)
        _ = FakeDisplay(for: poster)
        let gate = DispatchSemaphore(value: 0)
        let entered = DispatchSemaphore(value: 0)
        var enteredOnce = false
        context.postObserverForTests = { _, _ in
            if !enteredOnce {
                enteredOnce = true
                entered.signal()
            }
            gate.wait()
        }
        var waits = 0
        context.waitObserverForTests = { waits += 1 }

        XCTAssertTrue(poster.smooth(event: try wheelEvent(), input: input()))
        var now = ScrollPoster.monotonicNow()
        for _ in 0..<3 {
            now += 1.0 / 60.0
            poster.displayLinkCallbackForTests(frameInterval: 1.0 / 60.0, now: now)
        }
        XCTAssertEqual(entered.wait(timeout: .now() + 5), .success, "a post is under way and does not return")

        poster.stop(reason: .leftClick)

        XCTAssertEqual(waits, 0)
        XCTAssertFalse(poster.isGliding)
        for _ in 0..<64 { gate.signal() }
        context.waitForPostQueueForTests()
    }

    // MARK: - With the switch off a wheel event asks nothing new under the lock

    /// The checks trackpad-style adds to a wheel event (does the open touch have to end?)
    /// take the poster's lock. With the switch off none of them runs: the wheel events of a
    /// scroll without phases never enter that check. With one touch every wheel event after
    /// the first does. (The check ran for every wheel event, the switch off included: two
    /// more rounds of the lock that the display link's thread waits on.)
    func testWithTheSwitchOffNoWheelEventAsksAboutATouch() throws {
        func touchChecks(switchOn: Bool) throws -> Int {
            var checks = 0
            try withSettings(switchOn: switchOn) {
                let context = ScrollDispatchContext()
                let poster = ScrollPoster(phases: ScrollPhase(), dispatchContext: context)
                poster.trackpadStyleTarget = { _ in .touchOnly }
                _ = FakeDisplay(for: poster)
                context.postObserverForTests = { _, _ in }
                var now = ScrollPoster.monotonicNow()
                for _ in 0..<3 {
                    XCTAssertTrue(poster.smooth(event: try wheelEvent(), input: input()))
                    for _ in 0..<2 {
                        now += 1.0 / 60.0
                        poster.displayLinkCallbackForTests(frameInterval: 1.0 / 60.0, now: now)
                    }
                }
                XCTAssertEqual(poster.sessionLogForTests.inputs, 3, "one scroll of three wheel events")
                checks = poster.touchChecksForTests
                poster.stop()
                context.waitForPostQueueForTests()
            }
            return checks
        }
        XCTAssertEqual(try touchChecks(switchOn: false), 0, "the switch is off: nothing is asked")
        XCTAssertEqual(try touchChecks(switchOn: true), 2, "one touch: the second and the third wheel event ask")
    }

    // MARK: - The stop's wait for its closing frames has a deadline

    /// A post that does not come back: the stop waits for its closing frame, but only for
    /// its deadline (50 ms), and says so in the `app` log, once, not at every stop. It used
    /// to wait without an end, inside the tap's callback, where an event tap that does not
    /// answer holds up all input. The frames are not lost: they go out, the gestures whole,
    /// when the queue moves again.
    func testAStopWaitsNoLongerThanItsDeadlineAndSaysSoOnce() throws {
        try withSettings(switchOn: true) {
            let context = ScrollDispatchContext()
            let poster = ScrollPoster(phases: ScrollPhase(), dispatchContext: context)
            poster.trackpadStyleTarget = { _ in .touchOnly }
            _ = FakeDisplay(for: poster)
            XCTAssertEqual(context.closingFrameDeadline, 0.05)
            var posted: [Double] = []
            let lock = NSLock()
            let gate = DispatchSemaphore(value: 0)
            let held = DispatchSemaphore(value: 0)
            var holds = true
            context.postObserverForTests = { event, _ in
                lock.lock()
                posted.append(event.getDoubleValueField(.scrollWheelEventScrollPhase))
                let holdNow = holds
                holds = false
                lock.unlock()
                if holdNow {
                    held.signal()
                    gate.wait()
                }
            }
            func stillWaitLines() -> Int {
                return poster.healthLinesForTests.filter { $0 == ScrollPoster.closingFramesStillWaitLine }.count
            }

            XCTAssertTrue(poster.smooth(event: try wheelEvent(), input: input()))
            XCTAssertEqual(held.wait(timeout: .now() + 5), .success, "the post of \"began\" does not come back")
            let before = ProcessInfo.processInfo.systemUptime
            poster.stop(reason: .leftClick)
            let took = ProcessInfo.processInfo.systemUptime - before

            XCTAssertGreaterThan(took, 0.04, "it waited for its closing frame")
            XCTAssertLessThan(took, 2, "and gave up at the deadline")
            XCTAssertFalse(poster.isGliding)
            XCTAssertEqual(stillWaitLines(), 1)

            // The next scroll and its stop find the queue still held: no second line.
            XCTAssertTrue(poster.smooth(event: try wheelEvent(), input: input()))
            poster.stop(reason: .leftClick)
            XCTAssertEqual(stillWaitLines(), 1, "one line while the post hangs, not one per stop")

            // The post comes back: everything that opens or closes a gesture goes out, in order.
            gate.signal()
            context.waitForPostQueueForTests()
            lock.lock()
            let all = posted
            lock.unlock()
            XCTAssertEqual(all, [1, 4, 128, 8, 1, 4, 128, 8], "two whole touches, each ended by a click: its tap follows")
        }
    }

    /// The same over Chrome, the one app whose stop posts a frame with the switch off (its
    /// "ended"). That frame is queued behind the post that does not return, and the stop
    /// still does not wait: the wait is for a scroll with trackpad phases only.
    func testAStopOverChromeWithoutPhasesDoesNotWaitForTheQueue() throws {
        let savedApplication = ScrollCore.shared.application
        let savedSwitch = Options.shared.scroll.smoothSimTrackpad
        ScrollCore.shared.application = nil
        Options.shared.scroll.smoothSimTrackpad = false
        defer {
            ScrollCore.shared.application = savedApplication
            Options.shared.scroll.smoothSimTrackpad = savedSwitch
        }
        let context = ScrollDispatchContext()
        let poster = ScrollPoster(phases: ScrollPhase(), dispatchContext: context)
        poster.isEventTargetingChrome = { _ in true }
        _ = FakeDisplay(for: poster)
        let gate = DispatchSemaphore(value: 0)
        let entered = DispatchSemaphore(value: 0)
        var enteredOnce = false
        var phases: [Double] = []
        let lock = NSLock()
        context.postObserverForTests = { event, _ in
            lock.lock()
            phases.append(event.getDoubleValueField(.scrollWheelEventScrollPhase))
            let first = !enteredOnce
            enteredOnce = true
            lock.unlock()
            if first { entered.signal() }
            gate.wait()
        }
        var waits = 0
        context.waitObserverForTests = { waits += 1 }

        XCTAssertTrue(poster.smooth(event: try wheelEvent(), input: input()))
        var now = ScrollPoster.monotonicNow()
        for _ in 0..<3 {
            now += 1.0 / 60.0
            poster.displayLinkCallbackForTests(frameInterval: 1.0 / 60.0, now: now)
        }
        XCTAssertEqual(entered.wait(timeout: .now() + 5), .success, "a post is under way and does not return")

        let before = ProcessInfo.processInfo.systemUptime
        poster.stop(reason: .leftClick)
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - before, 0.03, "the stop came back at once")

        XCTAssertEqual(waits, 0, "no wait, although Chrome's \"ended\" is queued")
        XCTAssertFalse(poster.isGliding)
        for _ in 0..<64 { gate.signal() }
        context.waitForPostQueueForTests()
        lock.lock()
        XCTAssertEqual(phases.last, 4, "Chrome's \"ended\" went out, in its turn")
        lock.unlock()
    }

    // MARK: - Frames that open or close a gesture are not dropped by a stop

    /// One click as one touch, on the real path, with one slow post: the post of the last
    /// frame that moves the page does not return. The display frames run on and queue the
    /// touch's "ended" behind it; then a click stops the scroll. The stop moved the
    /// generation on and the waiting "ended" was dropped with the frames that only move the
    /// page, and the stop itself queued none (for it the touch had ended): the app got
    /// "began" and never "ended". Every one-touch scroll ends with an "ended" from the
    /// display link's thread, so this was open at every one of them.
    func testTheOneTouchsEndedSurvivesAStopThatComesWhileItWaits() throws {
        try withSettings(switchOn: true) {
            let context = ScrollDispatchContext()
            let poster = ScrollPoster(phases: ScrollPhase(), dispatchContext: context)
            // (The post is held on purpose here: the stop's wait gets time for it.)
            context.closingFrameDeadline = 10
            poster.trackpadStyleTarget = { _ in .touchOnly }
            _ = FakeDisplay(for: poster)
            var posted: [Double] = []
            var changed = 0
            let lock = NSLock()
            let gate = DispatchSemaphore(value: 0)
            let held = DispatchSemaphore(value: 0)
            context.postObserverForTests = { event, _ in
                let phase = event.getDoubleValueField(.scrollWheelEventScrollPhase)
                lock.lock()
                posted.append(phase)
                if phase == 2 { changed += 1 }
                let isTheSlowOne = phase == 2 && changed == 26
                lock.unlock()
                if isTheSlowOne {
                    held.signal()
                    _ = gate.wait(timeout: .now() + 5)
                }
            }

            XCTAssertTrue(poster.smooth(event: try wheelEvent(), input: input()))
            var now = ScrollPoster.monotonicNow()
            var request: ScrollStopRequest?
            for _ in 0..<240 {
                now += 1.0 / 60.0
                if let made = poster.displayLinkFrameForTests(frameInterval: 1.0 / 60.0, now: now) {
                    request = made
                    break
                }
            }
            XCTAssertNotNil(request, "the scroll has run out: its \"ended\" is queued")
            XCTAssertEqual(held.wait(timeout: .now() + 5), .success, "the last moving frame's post is under way")
            XCTAssertTrue(context.hasWaitingGestureFrames, "\"ended\" waits behind it")

            // The slow post returns a moment after the click.
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.02) { gate.signal() }
            poster.stop(reason: .leftClick)

            // Read at once: the stop waited for the frame that closes the gesture.
            lock.lock()
            let all = posted
            lock.unlock()
            XCTAssertEqual(all.filter { $0 == 1 }.count, 1)
            XCTAssertEqual(all.filter { $0 == 4 }.count, 1, "the app got \"began\" and gets \"ended\": \(all)")
            XCTAssertEqual(all.last, 4)
            XCTAssertFalse(context.hasWaitingGestureFrames)
            context.waitForPostQueueForTests()
        }
    }

    /// The same for a flick whose "momentum began" still waits when a click stops the scroll:
    /// the app gets it, without its distance (the scroll was stopped), and then the stop's
    /// "momentum ended". The glide's other frames from before the stop are dropped, as ever.
    func testAWaitingMomentumBeganIsPostedWithoutItsDistanceAfterAStop() throws {
        try withSettings(switchOn: true) {
            let context = ScrollDispatchContext()
            let poster = ScrollPoster(phases: ScrollPhase(), dispatchContext: context)
            // (The post is held on purpose here: the stop's wait gets time for it.)
            context.closingFrameDeadline = 10
            poster.trackpadStyleTarget = { _ in .followsGlide }
            _ = FakeDisplay(for: poster)
            var posted: [(name: String, y: Int64)] = []
            let lock = NSLock()
            let gate = DispatchSemaphore(value: 0)
            let held = DispatchSemaphore(value: 0)
            var holds = true
            context.postObserverForTests = { event, _ in
                let name = ScrollClassicRig.phaseName(scroll: event.getDoubleValueField(.scrollWheelEventScrollPhase),
                                                      momentum: event.getDoubleValueField(.scrollWheelEventMomentumPhase))
                lock.lock()
                posted.append((name, event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)))
                let holdNow = holds && name == "changed"
                if holdNow { holds = false }
                lock.unlock()
                if holdNow {
                    held.signal()
                    _ = gate.wait(timeout: .now() + 5)
                }
            }

            XCTAssertTrue(poster.smooth(event: try wheelEvent(), input: input()))
            var now = ScrollPoster.monotonicNow()
            for _ in 0..<8 {
                now += 1.0 / 60.0
                poster.displayLinkCallbackForTests(frameInterval: 1.0 / 60.0, now: now)
            }
            XCTAssertEqual(held.wait(timeout: .now() + 5), .success, "the first \"changed\" is being posted; the rest waits")

            DispatchQueue.global().asyncAfter(deadline: .now() + 0.02) { gate.signal() }
            poster.stop(reason: .leftClick)

            lock.lock()
            let all = posted
            lock.unlock()
            XCTAssertEqual(all.map(\.name), ["began", "changed", "ended", "momentumBegan", "momentumEnded"], "\(all)")
            XCTAssertEqual(all.first { $0.name == "momentumBegan" }?.y, 0, "the glide's first step is not made after the stop")
            context.waitForPostQueueForTests()
        }
    }

    // MARK: - The real path with "Trackpad-style scrolling" on

    /// One frame as it would be posted: what the app reads on the event.
    private struct PostedFrame {
        var scroll: Double
        var momentum: Double
        var y: Int64
        var timestamp: UInt64
        var pid: pid_t
        var isContinuous: Int64
        var lines: Int64 = 0
        var fixedLines: Double = 0
        var scrollCount: Int64 = 0
        /// Whether the event carries a hardware record (nil: this macOS cannot be asked).
        var hasRecord: Bool?
        /// The sideways point delta, and where the pointer was (global x).
        var x: Int64 = 0
        var pointerX: CGFloat = 0
        var name: String { return ScrollClassicRig.phaseName(scroll: scroll, momentum: momentum) }
        var hasPhase: Bool { return scroll != 0 || momentum != 0 }
    }

    /// The wheel event's own time, and where the clock of the frames' own times starts.
    private static let wheelTime: UInt64 = 1_000_000_000
    private static let firstFrameTime: UInt64 = 5_000_000_000
    private static let wheelScrollCount: Int64 = 3

    /// The default click: every frame that moves the page, with the switch off (pinned by
    /// `ScrollClassicPathTests.testTheDefaultClick_isWhatItWas`). No form changes it.
    private static let defaultClick: [Int64] = [
        7, 13, 15, 16, 16, 16, 15, 14, 12, 11, 10, 9, 8, 7, 6, 5, 5, 4, 3, 3, 2, 2, 2, 2, 1, 1,
    ]

    /// One click of the wheel as the scroll tap hands it over: a CGEvent with a target through
    /// `smooth(event:input:)`, the switch read from the settings (the caller sets them), the
    /// app's kind as given, display frames until the scroll has ended by itself. Returns the
    /// events that would be posted, the scroll's log entry, and how often the kind was asked.
    /// `oldLongTouch`: the evaluation switch (`ScrollPoster.usesOldLongTouch`).
    /// `chrome`: whether the app counts as Chrome itself (it gets an "ended" at a stop with
    /// the switch off).
    /// `takesRecordOff`: what the launch's self-test found (nil: this Mac's own answer).
    private func oneClick(over kind: ScrollUtils.TrackpadStyleTarget, oldLongTouch: Bool = false, chrome: Bool = false,
                          takesRecordOff: Bool? = nil,
                          file: StaticString = #filePath, line: UInt = #line) throws -> (frames: [PostedFrame], session: ScrollSystemLog.Session?, asked: Int) {
        let context = ScrollDispatchContext()
        let poster = ScrollPoster(phases: ScrollPhase(), dispatchContext: context)
        poster.usesOldLongTouch = oldLongTouch
        if let takesRecordOff = takesRecordOff {
            poster.hardwareRecordComesOff = { takesRecordOff }
        }
        poster.isEventTargetingChrome = { _ in chrome }
        var asked = 0
        poster.trackpadStyleTarget = { _ in
            asked += 1
            return kind
        }
        _ = FakeDisplay(for: poster)
        var clock = Self.firstFrameTime
        poster.eventClockForTests = {
            clock += 16_666_667
            return clock
        }
        var posted: [PostedFrame] = []
        let lock = NSLock()
        context.postObserverForTests = { event, pid in
            lock.lock()
            posted.append(PostedFrame(
                scroll: event.getDoubleValueField(.scrollWheelEventScrollPhase),
                momentum: event.getDoubleValueField(.scrollWheelEventMomentumPhase),
                y: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1),
                timestamp: event.timestamp,
                pid: pid,
                isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous),
                lines: event.getIntegerValueField(.scrollWheelEventDeltaAxis1),
                fixedLines: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1),
                scrollCount: event.getIntegerValueField(.scrollWheelEventScrollCount),
                hasRecord: ScrollHardwareRecord.isCarried(by: event)
            ))
            lock.unlock()
        }
        var sessions: [ScrollSystemLog.Session] = []
        ScrollSystemLog.sessionObserverForTests = { session, _ in sessions.append(session) }
        defer { ScrollSystemLog.sessionObserverForTests = nil }

        let wheel = try wheelEvent(targetPID: 4242)
        wheel.timestamp = Self.wheelTime
        // A wheel event that counts as the third of a row of fast ones: AppKit would
        // multiply the deltas of a precise event that carries this count.
        wheel.setIntegerValueField(.scrollWheelEventScrollCount, value: Self.wheelScrollCount)
        // A real wheel event carries a hardware record (its own time, one notch).
        try attachHardwareRecord(to: wheel)
        XCTAssertTrue(poster.smooth(event: wheel, input: input()), file: file, line: line)
        var now = ScrollPoster.monotonicNow()
        for _ in 0..<240 {
            now += 1.0 / 60.0
            if let request = poster.displayLinkFrameForTests(frameInterval: 1.0 / 60.0, now: now) {
                // The frames come here without the 16 ms between them: let the post queue
                // catch up before the stop (it drops what still waits from before it).
                context.waitForPostQueueForTests()
                XCTAssertTrue(poster.performRequestedStop(request), file: file, line: line)
                break
            }
        }
        XCTAssertFalse(poster.isGliding, "the scroll ended by itself", file: file, line: line)
        context.waitForPostQueueForTests()
        lock.lock()
        defer { lock.unlock() }
        XCTAssertTrue(posted.allSatisfy { $0.pid == 4242 }, "every frame goes to the wheel event's process", file: file, line: line)
        XCTAssertTrue(posted.allSatisfy { $0.isContinuous == 1 }, file: file, line: line)
        XCTAssertEqual(posted.filter { $0.y != 0 }.map(\.y), Self.defaultClick, "the motion is the default click's in every form", file: file, line: line)
        return (posted, sessions.last, asked)
    }

    // MARK: A run through the real path on a simulated clock

    /// Wheel events as the scroll tap hands them over (CGEvents with a target, through
    /// `smooth(event:input:)`: the switch read from the settings, the form decided per
    /// event) and display frames at 60 Hz between them, all on one simulated clock. What
    /// would be posted is collected as the app would read it.
    private final class RealRun {
        let context = ScrollDispatchContext()
        let poster: ScrollPoster
        private(set) var asked = 0
        private(set) var sessions: [(session: ScrollSystemLog.Session, reason: ScrollSystemLog.EndReason)] = []
        private var posted: [PostedFrame] = []
        private let lock = NSLock()
        private let base = 5_000.0
        private var now = 5_000.0
        private var nextFrame = 5_000.0 + 1.0 / 60.0
        /// When each posted event was handed over (seconds after the start), event by event.
        private(set) var postedAt: [Double] = []
        /// The Duration (the feel) of the wheel events.
        var duration = OPTIONS_SCROLL_DEFAULT().duration
        /// Called whenever the run's clock has moved on (before a frame, before a wheel event).
        var onTick: (() -> Void)?

        init(over kind: ScrollUtils.TrackpadStyleTarget, oldLongTouch: Bool = false, display: (ScrollPoster) -> Void) {
            let poster = ScrollPoster(phases: ScrollPhase(), dispatchContext: context)
            self.poster = poster
            poster.usesOldLongTouch = oldLongTouch
            poster.isEventTargetingChrome = { _ in false }
            poster.trackpadStyleTarget = { [unowned self] _ in
                self.asked += 1
                return kind
            }
            display(poster)
            poster.eventClockForTests = { [unowned self] in UInt64((self.now * 1e9).rounded()) }
            poster.inputClockForTests = { [unowned self] in self.now }
            context.postObserverForTests = { [unowned self] event, pid in
                self.lock.lock()
                self.posted.append(PostedFrame(
                    scroll: event.getDoubleValueField(.scrollWheelEventScrollPhase),
                    momentum: event.getDoubleValueField(.scrollWheelEventMomentumPhase),
                    y: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1),
                    timestamp: event.timestamp,
                    pid: pid,
                    isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous),
                    lines: event.getIntegerValueField(.scrollWheelEventDeltaAxis1),
                    fixedLines: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1),
                    scrollCount: event.getIntegerValueField(.scrollWheelEventScrollCount),
                    hasRecord: ScrollHardwareRecord.isCarried(by: event),
                    x: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2),
                    pointerX: event.location.x
                ))
                self.postedAt.append(self.now - self.base)
                self.lock.unlock()
            }
            ScrollSystemLog.sessionObserverForTests = { [weak self] session, reason in
                self?.sessions.append((session, reason))
            }
        }

        /// Seconds after the start.
        var time: Double { return now - base }

        /// Runs the display frames due up to `time` (seconds after the start). After each
        /// frame the post queue catches up: the frames come here without real time between
        /// them, and a stop drops what still waits from before it.
        func run(until time: Double) {
            let target = base + time
            while nextFrame <= target + 1e-9 {
                now = nextFrame
                nextFrame += 1.0 / 60.0
                onTick?()
                guard poster.isGliding else { continue }
                let request = poster.displayLinkFrameForTests(frameInterval: 1.0 / 60.0, now: now)
                context.waitForPostQueueForTests()
                if let request = request {
                    poster.performRequestedStop(request)
                    context.waitForPostQueueForTests()
                }
            }
            now = max(now, target)
        }

        /// One wheel event at `time`: `y` and `x` are the distances ScrollCore resolved.
        @discardableResult
        func wheel(at time: Double, y: Double = 211.68, x: Double = 0, pid: Int64 = 4242, pointerX: CGFloat = 400) throws -> Bool {
            run(until: time)
            onTick?()
            let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0))
            event.setIntegerValueField(.eventTargetUnixProcessID, value: pid)
            event.location = CGPoint(x: pointerX, y: 300)
            event.timestamp = 1_000_000_000
            let input = ScrollPosterInput(y: y, x: x, notch: max(abs(y), abs(x)),
                                          duration: OPTIONS_SCROLL_DEFAULT.generateDurationTransition(with: duration))
            let taken = poster.smooth(event: event, input: input)
            context.waitForPostQueueForTests()
            return taken
        }

        /// What was posted so far.
        var frames: [PostedFrame] {
            context.waitForPostQueueForTests()
            lock.lock()
            defer { lock.unlock() }
            return posted
        }

        /// Ends the run: the observer of the scroll log is taken down.
        func finish() -> [PostedFrame] {
            let all = frames
            ScrollSystemLog.sessionObserverForTests = nil
            return all
        }
    }

    /// The run's observer of the scroll log is taken down when the test ends, however it
    /// ends: a test that threw before `finish()` left it pointing at the run, and the next
    /// test that ended a scroll crashed the host.
    private func realRun(over kind: ScrollUtils.TrackpadStyleTarget, oldLongTouch: Bool = false, watch: ScrollEndWatching? = nil) -> RealRun {
        addTeardownBlock { ScrollSystemLog.sessionObserverForTests = nil }
        let run = RealRun(over: kind, oldLongTouch: oldLongTouch) { _ = FakeDisplay(for: $0) }
        if let watch = watch {
            run.poster.endWatch = watch
            if let page = watch as? PageWatch {
                page.sentDown = { [unowned run] in -Double(run.frames.reduce(0) { $0 + $1.y }) }
                page.clock = { [unowned run] in run.time }
                run.onTick = { [unowned page] in page.answerWhatIsDue() }
            }
        }
        return run
    }

    // MARK: The end watch (design v3): a stand-in page

    /// A stand-in for the end watch: a page `range` px long that is `offset` px from its top
    /// and moves by what the run has posted. It answers inside the call, or when the test
    /// says so, or never; it can lose the bar, or have a bar that does not belong to the
    /// page. It counts every call.
    private final class PageWatch: ScrollEndWatching {
        var offset: Double
        let range: Double
        var sentDown: () -> Double = { 0 }
        /// false: the look does not see a bar.
        var seesTheBar = true
        /// false: reads fail.
        var readsWork = true
        /// What the bar says instead of the page's place, if anything.
        var valueInstead: ((Double) -> Double)?
        var answersAtOnce = true
        var neverAnswers = false
        /// Every answer comes this long after it was asked for (the page's place is read
        /// when it comes), as an app that is busy scrolling answers.
        var delay = 0.0
        var clock: () -> Double = { 0 }
        private(set) var looks = 0
        private(set) var reads = 0
        private var waiting: [() -> Void] = []
        private var late: [(due: Double, work: () -> Void)] = []
        /// A page stops at its ends: what was sent past one is not owed back.
        private var clampedOffset: Double?
        private var lastSent = 0.0

        init(offset: Double, range: Double) {
            self.offset = offset
            self.range = range
        }

        var value: Double {
            let sent = sentDown()
            let at = min(range, max(0, (clampedOffset ?? offset) + sent - lastSent))
            clampedOffset = at
            lastSent = sent
            let place = at / range
            return valueInstead?(place) ?? place
        }

        /// The page moves by what was posted since the last time this was asked (a page
        /// stops at its ends as the frames come, not only when it is read).
        func follow() { _ = value }

        /// The page is moved by something else than the wheel (it grew, it was dragged).
        func moveBy(_ pixels: Double) {
            follow()
            clampedOffset = min(range, max(0, (clampedOffset ?? offset) + pixels))
        }

        func look(pid: pid_t, at point: CGPoint, answer: @escaping (ScrollEndReading) -> Void) {
            looks += 1
            deliver { [self] in
                answer(seesTheBar ? ScrollEndReading(value: value, roles: ["AXCell", "AXRow", "AXOutline", "AXScrollArea"], milliseconds: 2)
                                  : .notSeen("a scroll area without a vertical scroll bar", roles: ["AXGroup", "AXScrollArea"], milliseconds: 3))
            }
        }

        func read(answer: @escaping (ScrollEndReading) -> Void) {
            reads += 1
            deliver { [self] in
                answer(readsWork ? ScrollEndReading(value: value, milliseconds: 1) : .notSeen("the bar's value could not be read again", milliseconds: 100))
            }
        }

        private func deliver(_ work: @escaping () -> Void) {
            if neverAnswers { return }
            if delay > 0 {
                late.append((clock() + delay, work))
            } else if answersAtOnce {
                work()
            } else {
                waiting.append(work)
            }
        }

        /// Lets the late answers that are due come in.
        func answerWhatIsDue() {
            follow()
            let now = clock()
            let due = late.filter { $0.due <= now + 1e-9 }
            late.removeAll { $0.due <= now + 1e-9 }
            due.forEach { $0.work() }
        }

        /// Lets the answers that wait come in.
        func answerNow() {
            let all = waiting
            waiting = []
            all.forEach { $0() }
        }
    }

    private func offStream(_ wheels: [(time: Double, y: Double)], until: Double) throws -> (y: [Int64], at: [Double]) {
        var result: ([Int64], [Double]) = ([], [])
        try withSettings(switchOn: false) {
            let run = realRun(over: .touchOnly)
            for wheel in wheels { XCTAssertTrue(try run.wheel(at: wheel.time, y: wheel.y)) }
            run.run(until: until)
            let at = run.postedAt
            let frames = run.finish()
            result = (frames.filter { $0.y != 0 }.map(\.y), zip(frames, at).filter { $0.0.y != 0 }.map { $0.1 })
        }
        return result
    }

    /// Rules 1 and 2: a touch never opens before the answer "seen" is in. Until then the
    /// frames are plain, exactly the switch-off frames; with the answer the touch opens
    /// ("began") and the frames after it are "changed". The motion is the switch-off
    /// scroll's whatever the answer's moment.
    func testEndWatch_theTouchOpensWithTheAnswerAndNotBefore() throws {
        let off = try offStream([(0, -211.68)], until: 3)
        try withSettings(switchOn: true) {
            for framesBefore in [0, 1, 3, 8] {
                let watch = PageWatch(offset: 5_000, range: 60_000)
                watch.answersAtOnce = false
                let run = realRun(over: .touchOnly, watch: watch)
                XCTAssertTrue(try run.wheel(at: 0, y: -211.68))
                run.run(until: Double(framesBefore) / 60.0 + 0.001)
                XCTAssertEqual(watch.looks, 1)
                XCTAssertEqual(run.frames.count, framesBefore, "\(framesBefore) frames before the answer")
                XCTAssertFalse(run.frames.contains { $0.hasPhase }, "no phase on any of them: no \"began\" before the answer")
                XCTAssertTrue(run.frames.allSatisfy { $0.timestamp == 1_000_000_000 && $0.lines == 1 }, "written as with the switch off")
                watch.answerNow()
                XCTAssertEqual(run.frames.last?.name, "began", "the touch opens with the answer")
                watch.answersAtOnce = true
                watch.answerNow()
                run.run(until: 3)
                let at = run.postedAt
                let frames = run.finish()
                XCTAssertNil(brokenGesture(in: frames))
                XCTAssertEqual(frames.filter { $0.y != 0 }.map(\.y), off.y, "the motion is the switch-off scroll's")
                XCTAssertEqual(zip(frames, at).filter { $0.0.y != 0 }.map { $0.1 }, off.at)
                XCTAssertEqual(frames.filter { $0.name == "changed" }.count, 26 - framesBefore)
                XCTAssertEqual(frames.last?.name, "ended")
                XCTAssertGreaterThan(watch.reads, 10, "the bar is read while the touch is open")
                XCTAssertLessThanOrEqual(watch.reads, 60, "once per display frame at most")
                XCTAssertTrue(run.sessions.first?.session.endWatch.line?.hasPrefix("scroll end watch: seen, roles AXCell > AXRow > AXOutline > AXScrollArea, value 0.08") ?? false,
                              run.sessions.first?.session.endWatch.line ?? "")
            }
        }
    }

    /// Rule 2: where the bar is not seen, and where the watch never answers or there is
    /// none, the scroll carries no phases: it is the switch-off scroll, event for event.
    func testEndWatch_notSeen_theScrollIsTheSwitchOffScroll() throws {
        let wheels: [(time: Double, y: Double)] = [(0, -211.68), (0.1, -211.68), (0.9, -211.68)]
        let off = try offStream(wheels, until: 4)
        try withSettings(switchOn: true) {
            for kind in ["no bar", "never answers", "no watch"] {
                let watch = PageWatch(offset: 5_000, range: 60_000)
                watch.seesTheBar = kind != "no bar"
                watch.neverAnswers = kind == "never answers"
                let run = realRun(over: .touchOnly, watch: watch)
                if kind == "no watch" { run.poster.endWatch = nil }
                for wheel in wheels { XCTAssertTrue(try run.wheel(at: wheel.time, y: wheel.y)) }
                run.run(until: 4)
                let at = run.postedAt
                let frames = run.finish()
                XCTAssertFalse(frames.contains { $0.hasPhase }, "\(kind): no phase")
                XCTAssertTrue(frames.allSatisfy { $0.timestamp == 1_000_000_000 && $0.lines == 1 && $0.scrollCount == 0 }, kind)
                XCTAssertEqual(frames.map(\.y), off.y, kind)
                XCTAssertEqual(at, off.at, kind)
                XCTAssertEqual(watch.reads, 0, "\(kind): nothing is read again")
                switch kind {
                case "no bar":
                    // Blind is not for good: a look every quarter of a second while the scroll goes on.
                    XCTAssertTrue((5...9).contains(watch.looks), "\(kind): \(watch.looks) looks for 1.4 s of scrolling: one every quarter second, not one per display frame")
                case "never answers": XCTAssertEqual(watch.looks, 2, "\(kind): one look per scroll")
                default: XCTAssertEqual(watch.looks, 0, kind)
                }
                XCTAssertEqual(run.sessions.map(\.reason), [.glidedOut, .glidedOut], kind)
                let line = run.sessions.first?.session.endWatch.line ?? ""
                switch kind {
                case "no bar": XCTAssertTrue(line.hasPrefix("scroll end watch: not seen (a scroll area without a vertical scroll bar): plain, roles AXGroup > AXScrollArea"), line)
                case "never answers": XCTAssertTrue(line.hasPrefix("scroll end watch: no answer: plain"), line)
                default: XCTAssertTrue(line.hasPrefix("scroll end watch: not seen (no watch): plain"), line)
                }
            }
        }
    }

    /// One read that fails (the owner's log: one answer of Finder's took 100.4 ms and timed
    /// out in mid-fling) does not cost the bar: it is asked again, and the touch goes on.
    /// Two in a row lose it: the touch is ended by force, with its tap, and the scroll goes
    /// on plain. But blind is not for the rest of the scroll: a look is asked again every
    /// quarter of a second, and the touch opens again when the bar is seen. And a touch is
    /// never open for longer than 0.35 s without a reading, whatever the watch does.
    func testEndWatch_aFailedReadIsAskedAgain_andALostBarIsLookedForAgain() throws {
        let wheels = (0..<40).map { (time: Double($0) * 0.05, y: -211.68) }
        let off = try offStream(wheels, until: 5)
        try withSettings(switchOn: true) {
            // One read fails.
            var watch = PageWatch(offset: 20_000, range: 60_000)
            var run = realRun(over: .touchOnly, watch: watch)
            for wheel in wheels.prefix(4) { XCTAssertTrue(try run.wheel(at: wheel.time, y: wheel.y)) }
            watch.readsWork = false
            run.run(until: 0.15 + 1.0 / 60.0 + 0.001)
            watch.readsWork = true
            for wheel in wheels.dropFirst(4) { XCTAssertTrue(try run.wheel(at: wheel.time, y: wheel.y)) }
            run.run(until: 5)
            var frames = run.finish()
            XCTAssertEqual(phaseRuns(frames).map { $0.split(separator: " ")[0] }, ["began", "changed", "ended"], "one touch to the end: the bar was not lost")
            XCTAssertEqual(run.sessions.first?.session.endWatch.lost, 0)

            // Two in a row, then the bar cannot be seen for half a second, then it can.
            watch = PageWatch(offset: 20_000, range: 60_000)
            run = realRun(over: .touchOnly, watch: watch)
            for wheel in wheels.prefix(8) { XCTAssertTrue(try run.wheel(at: wheel.time, y: wheel.y)) }
            run.run(until: 0.4)
            watch.readsWork = false
            watch.seesTheBar = false
            let before = run.frames.count
            for wheel in wheels.dropFirst(8).prefix(12) { XCTAssertTrue(try run.wheel(at: wheel.time, y: wheel.y)) }
            let lost = run.frames.dropFirst(before)
            let ended = try XCTUnwrap(lost.firstIndex { $0.name == "ended" })
            XCTAssertEqual(Array(run.frames[ended...].prefix(3)).map(\.name), ["ended", "mayBegin", "cancelled"], "ended by force, with its tap")
            XCTAssertLessThan(run.postedAt[ended], 0.4 + 3.0 / 60.0, "at the second failed read")
            XCTAssertFalse(run.frames.dropFirst(ended + 3).contains { $0.hasPhase }, "plain while the bar is not seen")
            let looksWhileBlind = watch.looks
            XCTAssertTrue((1...3).contains(looksWhileBlind - 1), "looked for again about every quarter second: \(looksWhileBlind - 1) looks in 0.5 s")
            watch.readsWork = true
            watch.seesTheBar = true
            for wheel in wheels.dropFirst(20) { XCTAssertTrue(try run.wheel(at: wheel.time, y: wheel.y)) }
            run.run(until: 5)
            let at = run.postedAt
            frames = run.finish()
            let again = try XCTUnwrap(frames.lastIndex { $0.name == "began" })
            XCTAssertGreaterThan(again, ended, "the touch opens again")
            XCTAssertLessThan(at[again], 1.0 + 0.3, "within a quarter second of the bar being there again")
            XCTAssertTrue(frames.dropFirst(again + 1).filter { $0.y != 0 }.allSatisfy { $0.name == "changed" }, "and the scroll is a touch again to its end")
            XCTAssertEqual(frames.last?.name, "ended")
            XCTAssertNil(brokenGesture(in: frames))
            XCTAssertEqual(frames.filter { $0.y != 0 }.map(\.y), off.y, "the page moves as with the switch off through all of it")
            let line = run.sessions.first?.session.endWatch.line ?? ""
            XCTAssertTrue(line.contains("started afresh: 0 turns, 1 lost bars, "), line)
            XCTAssertTrue(line.contains("lost the bar: ended the touch, plain until it is seen again") && line.contains("seen again: opened the touch"), line)

            // A watch that stops answering while the touch is open: the touch is ended
            // after 0.35 s without a reading, not left open.
            watch = PageWatch(offset: 20_000, range: 60_000)
            run = realRun(over: .touchOnly, watch: watch)
            for wheel in wheels.prefix(8) { XCTAssertTrue(try run.wheel(at: wheel.time, y: wheel.y)) }
            run.run(until: 0.4)
            watch.neverAnswers = true
            for wheel in wheels.dropFirst(8) { XCTAssertTrue(try run.wheel(at: wheel.time, y: wheel.y)) }
            run.run(until: 5)
            let times = run.postedAt
            frames = run.finish()
            let forced = try XCTUnwrap(frames.firstIndex { $0.name == "ended" })
            XCTAssertEqual(Array(frames[forced...].prefix(3)).map(\.name), ["ended", "mayBegin", "cancelled"])
            XCTAssertGreaterThan(times[forced], 0.4 + 0.3)
            XCTAssertLessThan(times[forced], 0.4 + 0.35 + 3.0 / 60.0, "no longer than 0.35 s (and a frame) without a reading")
            XCTAssertFalse(frames.dropFirst(forced + 3).contains { $0.hasPhase })
            XCTAssertNil(brokenGesture(in: frames))
        }
    }

    /// "The wrong way" is judged against the frames that were sent, over three reads in a
    /// row, in a stretch where every frame went the same way: a bar that runs against the
    /// page (it is not the scrolled view's) is found, the touch is ended by force and the
    /// scroll is plain until the wheel turns. One jump back (a list that loads more rows)
    /// is not that, and neither is anything read around a turn of the wheel.
    func testEndWatch_theWrongWayIsJudgedAgainstTheFramesOverSeveralReads() throws {
        try withSettings(switchOn: true) {
            // A bar that runs the other way.
            var watch = PageWatch(offset: 4_000, range: 8_000)
            watch.valueInstead = { 1 - $0 }
            var run = realRun(over: .touchOnly, watch: watch)
            for index in 0..<30 { XCTAssertTrue(try run.wheel(at: Double(index) * 0.03, y: -211.68)) }
            run.run(until: 0.9)
            var names = run.frames.map(\.name)
            let ended = try XCTUnwrap(names.firstIndex(of: "ended"))
            XCTAssertEqual(Array(names[ended...].prefix(3)), ["ended", "mayBegin", "cancelled"])
            XCTAssertGreaterThan(run.postedAt[ended], 0.2, "not before the frames have gone one way for 0.2 s")
            let looks = watch.looks
            run.run(until: 2)
            XCTAssertEqual(watch.looks, looks, "plain until the wheel turns: no look again by itself")
            XCTAssertFalse(run.frames.dropFirst(ended + 3).contains { $0.hasPhase })
            // The wheel turns: a new look at once.
            XCTAssertTrue(try run.wheel(at: 2.01, y: 211.68))
            XCTAssertEqual(watch.looks, looks + 1)
            run.run(until: 6)
            var frames = run.finish()
            XCTAssertNil(brokenGesture(in: frames))
            XCTAssertTrue(run.sessions.first?.session.endWatch.line?.contains("the value went against the frames over ") ?? false,
                          run.sessions.first?.session.endWatch.line ?? "")

            // One jump back in mid-scroll: the page grew. The touch goes on and still arrives.
            watch = PageWatch(offset: 6_000, range: 8_000)
            run = realRun(over: .touchOnly, watch: watch)
            for index in 0..<10 { XCTAssertTrue(try run.wheel(at: Double(index) * 0.03, y: -211.68)) }
            run.run(until: 0.35)
            watch.moveBy(-1_500)
            for index in 0..<40 { _ = try run.wheel(at: 0.36 + Double(index) * 0.03, y: -211.68) }
            run.run(until: 5)
            frames = run.finish()
            names = frames.map(\.name)
            XCTAssertFalse(names.contains("mayBegin"), "no forced end")
            XCTAssertEqual(names.filter { $0 == "began" }.count, 1)
            XCTAssertTrue(run.sessions.first?.session.endWatch.line?.contains("reached the end and ended at once") ?? false,
                          run.sessions.first?.session.endWatch.line ?? "")
        }
    }

    /// The owner's sequence that stopped the animation (335 wheel events in 9.4 s, up and
    /// down without a pause, in a Finder list about 8,000 px long, while Finder answered
    /// 60 to 100 ms late): the wheel turns every quarter of a second for ten seconds, every
    /// answer comes 80 ms late. The reads lag the frames by a third of the bar's range,
    /// which used to read as "the wrong way": plain for the rest of the scroll, no bounce
    /// at either end. Now a turn starts the judgement afresh: no verdict is ever made, no
    /// stretch of the scroll is plain for long, and whenever a read finds the page at the
    /// end the scroll heads for, the touch ends at once, at both ends, to the last run.
    func testEndWatch_upAndDownWithoutAPause_keepsBouncingAtBothEnds() throws {
        /// The wheel turns every `turnEvery` s for ten seconds over a page 8,000 px long,
        /// every answer 80 ms late; after the last turn it goes on for half a second.
        func upAndDown(turnEvery: Double) throws -> (arrivals: [Bool], runsWithATouch: Int, lines: [String], frames: [PostedFrame]) {
            let watch = PageWatch(offset: 0, range: 8_000)
            watch.delay = 0.08
            let run = realRun(over: .touchOnly, watch: watch)
            var arrivals: [Bool] = []
            var runsWithATouch = 0
            let turns = Int((10 / turnEvery).rounded())
            for turn in 0..<turns {
                let down = turn % 2 == 0
                let from = Double(turn) * turnEvery
                let length = turn == turns - 1 ? turnEvery + 0.5 : turnEvery
                let before = run.frames.count
                var time = from
                while time < from + length - 0.001 {
                    _ = try run.wheel(at: time, y: down ? -830 : 830)
                    time += 0.0125
                }
                run.run(until: from + length - 0.001)
                let ofThisRun = Array(run.frames.dropFirst(before))
                if ofThisRun.contains(where: { $0.name == "changed" }) { runsWithATouch += 1 }
                // An arrival: an "ended" with no tap after it.
                arrivals.append(ofThisRun.indices.contains { ofThisRun[$0].name == "ended" && !($0 + 1 < ofThisRun.count && ofThisRun[$0 + 1].scroll == 128) })
            }
            run.run(until: 16)
            let frames = run.finish()
            return (arrivals, runsWithATouch, run.sessions.compactMap { $0.session.endWatch.line }, frames)
        }
        try withSettings(switchOn: true) {
            // A turn every quarter of a second. With answers 80 ms late a run has two
            // readings (the look's, and one read) before the wheel turns again, so an arrival
            // is seen only when the page is at its end within 170 ms of the turn; later ones
            // are not (the touch stays open through the turn and the page is pulled back by
            // the frames that follow). What must hold: no verdict, no touch ended by force,
            // a touch in every run, and the arrival after the last turn.
            let fast = try upAndDown(turnEvery: 0.25)
            XCTAssertNil(brokenGesture(in: fast.frames))
            XCTAssertFalse(fast.lines.contains { $0.contains("against the frames") }, "no turn is taken for \"the wrong way\"")
            XCTAssertFalse(fast.lines.contains { $0.contains("lost the bar") || $0.contains("no reading") }, "answers 80 ms late do not lose the bar")
            XCTAssertFalse(fast.frames.contains { $0.scroll == 128 }, "no touch is ended by force in the whole ten seconds")
            XCTAssertEqual(fast.runsWithATouch, 40, "every run between two turns has its touch: the scroll is never plain for a whole run")
            XCTAssertEqual(fast.arrivals.last, true, "the wheel goes on after the last turn: that arrival is seen and ends the touch")
            XCTAssertTrue(fast.lines.contains { $0.contains("started afresh: ") && $0.contains(" turns, 0 lost bars") }, "\(fast.lines.prefix(2))")

            // A turn every 0.4 s: the page is at its end before the wheel turns, in every
            // run. Every arrival ends its touch at once, at both ends, to the last one.
            let slower = try upAndDown(turnEvery: 0.4)
            XCTAssertNil(brokenGesture(in: slower.frames))
            XCTAssertFalse(slower.frames.contains { $0.scroll == 128 })
            XCTAssertFalse(slower.lines.contains { $0.contains("against the frames") || $0.contains("lost the bar") })
            let atTheBottom = slower.arrivals.enumerated().filter { $0.offset % 2 == 0 && $0.element }.count
            let atTheTop = slower.arrivals.enumerated().filter { $0.offset % 2 == 1 && $0.element }.count
            XCTAssertGreaterThanOrEqual(atTheBottom, 12, "arrivals at the bottom, of 13 runs into it: \(slower.arrivals)")
            XCTAssertGreaterThanOrEqual(atTheTop, 11, "arrivals at the top, of 12 runs into it")
            XCTAssertEqual(slower.arrivals.last, true, "to the last one")
        }
    }

    /// The owner's third case: a scroll starts with the page at the end it heads for, at a
    /// place where no arrival was seen (a short touch, then plain), and the wheel then turns
    /// inside the same scroll. The turn lifts "plain": a look at once, the touch opens (the
    /// page is not at the end it now heads for), and arriving at the other end ends it at
    /// once. Nothing is taken in at the place that was not proven. Before, the scroll was
    /// plain to its end (75 wheel events, 2.9 s).
    func testEndWatch_aStartAtAnUnprovenEndFollowedByATurn_opensTheTouchAgain() throws {
        try withSettings(switchOn: true) {
            let watch = PageWatch(offset: 0, range: 3_000)
            let run = realRun(over: .touchOnly, watch: watch)
            // Up, into the top the page is at.
            for index in 0..<12 { XCTAssertTrue(try run.wheel(at: Double(index) * 0.03, y: 211.68), "never taken in: not proven") }
            XCTAssertEqual(Array(run.frames.prefix(4)).map(\.name), ["began", "changed", "changed", "ended"])
            let before = run.frames.count
            XCTAssertFalse(run.frames.dropFirst(4).contains { $0.hasPhase }, "the rest plain")
            let looks = watch.looks
            // The wheel turns, without a pause: down.
            XCTAssertTrue(try run.wheel(at: 0.39, y: -211.68))
            XCTAssertEqual(watch.looks, looks + 1, "a look at once")
            XCTAssertEqual(run.frames.dropFirst(before).last?.name, "began", "and the touch opens: the page is not at the bottom")
            for index in 1..<40 { _ = try run.wheel(at: 0.39 + Double(index) * 0.03, y: -211.68) }
            run.run(until: 6)
            let frames = run.finish()
            XCTAssertNil(brokenGesture(in: frames))
            XCTAssertEqual(frames.last?.name, "ended")
            XCTAssertFalse(frames.contains { $0.scroll == 128 })
            XCTAssertEqual(run.sessions.count, 1, "one scroll")
            let line = run.sessions.first?.session.endWatch.line ?? ""
            XCTAssertTrue(line.contains("started afresh: 1 turns, 0 lost bars, "), line)
            XCTAssertTrue(line.contains("the rest plain (this place is not proven)") && line.contains("reached the end and ended at once"), line)
            XCTAssertLessThan(abs(frames.dropFirst(before).reduce(0) { $0 + $1.y }), 3_000 + 700, "the rest of the way down is dropped at the bottom")
        }
    }

    /// A scroll bar that does not count from 0 to 1 is not a reading of where the page is
    /// (review M1). Java Swing gives the raw position: at the top the look read 0, the first
    /// read said 7, which was "at the bottom": the touch ended at once, the rest was dropped
    /// and the wheel events taken in: 150 wheel events sent 7 px, and scrolling down was
    /// dead from then on. Such a bar is "not seen": the page moves as with the switch off.
    func testEndWatch_aBarThatCountsInPixels_isNotSeen() throws {
        let wheels = (0..<150).map { (time: Double($0) * 0.02, y: -211.68) }
        let off = try offStream(wheels, until: 8)
        try withSettings(switchOn: true) {
            for start in [0.0, 300.0] {
                let watch = PageWatch(offset: start, range: 60_000)
                watch.valueInstead = { $0 * 60_000 }
                let run = realRun(over: .touchOnly, watch: watch)
                for wheel in wheels { XCTAssertTrue(try run.wheel(at: wheel.time, y: wheel.y)) }
                run.run(until: 8)
                let frames = run.finish()
                XCTAssertEqual(frames.filter { $0.y != 0 }.map(\.y), off.y, "from \(start) px: every wheel event scrolls, as with the switch off")
                XCTAssertGreaterThan(abs(frames.reduce(0) { $0 + $1.y }), 30_000)
                XCTAssertNil(brokenGesture(in: frames))
                XCTAssertFalse(run.sessions.contains { $0.session.endWatch.line?.contains("reached the end") ?? false })
                XCTAssertTrue(run.sessions.first?.session.endWatch.line?.contains("a scroll bar that does not count from 0 to 1") ?? false,
                              run.sessions.first?.session.endWatch.line ?? "")
            }
        }
        XCTAssertEqual(AccessibilityScrollEndWatch.fromZeroToOne(0.5), 0.5)
        XCTAssertEqual(AccessibilityScrollEndWatch.fromZeroToOne(1.0004), 1)
        XCTAssertEqual(AccessibilityScrollEndWatch.fromZeroToOne(-0.0004), 0)
        XCTAssertNil(AccessibilityScrollEndWatch.fromZeroToOne(7))
        XCTAssertNil(AccessibilityScrollEndWatch.fromZeroToOne(-3))
        XCTAssertNil(AccessibilityScrollEndWatch.fromZeroToOne(.nan))
    }

    /// The watch never looks into Scrollio's own windows (review M2): for its own process
    /// Accessibility sends no message, it runs AppKit's accessibility code on the calling
    /// thread, which here is the watch's queue, while the main thread scrolls the same
    /// views. A wheel event over Scrollio's Settings asks for no look and scrolls as with
    /// the switch off; and the reader itself answers "not seen" for its own pid before any
    /// call, also where it is trusted.
    func testEndWatch_neverLooksIntoScrolliosOwnWindows() throws {
        let own = Int64(getpid())
        try withSettings(switchOn: true) {
            let watch = PageWatch(offset: 3_000, range: 60_000)
            let run = realRun(over: .touchOnly, watch: watch)
            for index in 0..<5 { XCTAssertTrue(try run.wheel(at: Double(index) * 0.05, y: -211.68, pid: own)) }
            run.run(until: 3)
            let frames = run.finish()
            XCTAssertEqual(watch.looks + watch.reads, 0, "no look, no read")
            XCTAssertFalse(frames.contains { $0.hasPhase }, "plain")
            XCTAssertGreaterThan(frames.count, 30)
            XCTAssertTrue(run.sessions.first?.session.endWatch.line?.contains("not seen (Scrollio's own window)") ?? false)
        }
        let reader = AccessibilityScrollEndWatch(isTrusted: { true })
        let answered = expectation(description: "answered")
        reader.look(pid: getpid(), at: CGPoint(x: 10, y: 10)) { reading in
            XCTAssertNil(reading.value)
            XCTAssertEqual(reading.failedAt, "Scrollio's own window")
            XCTAssertEqual(reading.roles, [], "nothing was asked")
            answered.fulfill()
        }
        wait(for: [answered], timeout: 5)
    }

    /// Rule 3: the page reaches the end the scroll heads for. "Ended" goes out at once, with
    /// a time right after the last moving frame (not 0.2 s after it: the app keeps the
    /// page's speed and bounces by itself), no tap (it would stop that bounce), and the
    /// rest of the scroll is dropped. Before, the touch stayed open for as long as the
    /// wheel turned and the tail ran: the page was held past its end for seconds.
    func testEndWatch_arrivingAtThePagesEnd_endsTheTouchAtOnceAndDropsTheRest() throws {
        try withSettings(switchOn: true) {
            for towardBottom in [true, false] {
                // 400 px to go, a spin of 12 clicks (2,500 px) into it.
                let watch = PageWatch(offset: towardBottom ? 59_600 : 400, range: 60_000)
                let run = realRun(over: .touchOnly, watch: watch)
                let label = towardBottom ? "into the bottom" : "into the top"
                for index in 0..<12 { XCTAssertTrue(try run.wheel(at: Double(index) * 0.02, y: towardBottom ? -211.68 : 211.68) || index > 3, label) }
                run.run(until: 3)
                let at = run.postedAt
                let frames = run.finish()
                XCTAssertEqual(frames.last?.name, "ended", label)
                XCTAssertEqual(frames.filter { $0.name == "ended" }.count, 1, label)
                XCTAssertFalse(frames.contains { $0.scroll == 128 || $0.scroll == 8 }, "\(label): no tap")
                XCTAssertNil(brokenGesture(in: frames), label)
                let sent = abs(frames.reduce(0) { $0 + $1.y })
                XCTAssertGreaterThanOrEqual(sent, 400, label)
                XCTAssertLessThan(sent, 700, "\(label): the rest of 2,500 px is dropped (\(sent) px went out)")
                let ended = try XCTUnwrap(frames.last)
                let lastMoving = try XCTUnwrap(frames.last { $0.y != 0 })
                let apart = Double(ended.timestamp - lastMoving.timestamp) / 1e9
                XCTAssertGreaterThan(apart, 0, label)
                XCTAssertLessThan(apart, 0.02, "\(label): right after the last moving frame, so the app holds its speed")
                XCTAssertLessThan(try XCTUnwrap(at.last) - at[at.count - 2], 0.02, label)
                XCTAssertEqual(run.sessions.map(\.reason), [.glidedOut], label)
                XCTAssertLessThan(run.sessions.first?.session.frames ?? 99, 12, label)
                XCTAssertTrue(run.sessions.first?.session.endWatch.line?.contains("reached the end and ended at once") ?? false, label)
                XCTAssertFalse(run.poster.isGliding, label)
            }
        }
    }

    /// Rule 4: with the page at its end and the wheel still turning into it, the wheel
    /// events are taken in and nothing is sent (a new touch would catch the app's bounce and
    /// hold the page stretched; a plain event snaps the bounce off). Only while a fresh
    /// read still says "at that end", in the same place, the same way. Anything else ends
    /// the hold, and the wheel event scrolls as usual.
    func testEndWatch_atTheEndTheWheelStillTurning_isTakenInWhileAFreshReadSaysSo() throws {
        /// The wheel turns into the bottom, an event every 20 ms, until the touch has ended
        /// there and the scroll is over; it goes on turning from the time returned.
        func arrive(_ watch: PageWatch) throws -> (run: RealRun, count: Int, time: Double) {
            let run = realRun(over: .touchOnly, watch: watch)
            var time = 0.0
            while (run.frames.last?.name != "ended" || run.poster.isGliding) && time < 2 {
                _ = try run.wheel(at: time, y: -211.68)
                time += 0.02
            }
            XCTAssertEqual(run.frames.last?.name, "ended")
            XCTAssertFalse(run.poster.isGliding, "the scroll that arrived is over")
            XCTAssertLessThan(time, 0.5)
            return (run, run.frames.count, time)
        }
        var taken: [Int] = []
        ScrollSystemLog.pageEndObserverForTests = { taken.append($0) }
        defer { ScrollSystemLog.pageEndObserverForTests = nil }
        try withSettings(switchOn: true) {
            // The wheel spins on for a second: every event is taken, nothing goes out.
            var (run, count, time) = try arrive(PageWatch(offset: 59_600, range: 60_000))
            for index in 0..<50 {
                XCTAssertTrue(try run.wheel(at: time + Double(index) * 0.02, y: -211.68), "taken in")
            }
            run.run(until: time + 1.2)
            XCTAssertEqual(run.frames.count, count, "nothing was sent for 50 wheel events")
            XCTAssertFalse(run.poster.isGliding, "and no scroll began")
            XCTAssertEqual(run.sessions.count, 1)
            // After a pause of the wheel the read is stale: a fresh start (rule 5), and the log says what the hold took.
            XCTAssertTrue(try run.wheel(at: time + 2, y: -211.68))
            // (50, and the one or two the wheel sent between the arrival and the scroll's end.)
            XCTAssertTrue((50...53).contains(taken.last ?? 0), "\(taken)")
            XCTAssertTrue(run.poster.isGliding, "a scroll of its own")
            run.run(until: time + 4)
            _ = run.finish()

            // Each of these ends the hold; the wheel event then scrolls as usual.
            let ways: [(String, (RealRun, PageWatch, Double) throws -> Bool)] = [
                ("the other way", { run, _, time in try run.wheel(at: time, y: 211.68) }),
                ("31 pt away", { run, _, time in try run.wheel(at: time, y: -211.68, pointerX: 431) }),
                ("another app", { run, _, time in try run.wheel(at: time, y: -211.68, pid: 777) }),
                ("the page left the end", { run, watch, time in
                    watch.moveBy(-5_000)
                    XCTAssertTrue(try run.wheel(at: time, y: -211.68), "this one is still taken: the read that says so is on its way")
                    return try run.wheel(at: time + 0.02, y: -211.68)
                }),
                ("a read fails", { run, watch, time in
                    watch.readsWork = false
                    XCTAssertTrue(try run.wheel(at: time, y: -211.68))
                    watch.readsWork = true
                    return try run.wheel(at: time + 0.02, y: -211.68)
                }),
                ("sideways", { run, _, time in try run.wheel(at: time, y: 0, x: 211.68) }),
            ]
            for (name, event) in ways {
                let watch = PageWatch(offset: 59_600, range: 60_000)
                (run, count, time) = try arrive(watch)
                XCTAssertTrue(try run.wheel(at: time, y: -211.68), name)
                XCTAssertEqual(run.frames.count, count, "\(name): held")
                XCTAssertFalse(run.poster.isGliding, name)
                XCTAssertTrue(try event(run, watch, time + 0.02), "\(name): the wheel event is taken by the poster as usual")
                XCTAssertTrue(run.poster.isGliding, "\(name): a scroll began")
                run.run(until: time + 0.2)
                XCTAssertGreaterThan(run.frames.count, count, "\(name): and scrolls")
                XCTAssertTrue(run.poster.isGliding, name)
                run.run(until: time + 5)
                XCTAssertNil(brokenGesture(in: run.finish()), name)
            }
        }
    }

    /// Rule 5: a scroll that starts with the page already at the end it heads for gets a
    /// short touch: "began", two moving frames, "ended" at once, no tap, so the app makes
    /// one small bounce. Where the place is not proven (no arrival was seen there) the rest
    /// of the scroll goes out plain and no wheel event is ever taken in; where it is proven
    /// the rest is dropped and held. One bounce per fresh start, not one per wheel event.
    func testEndWatch_startingAtTheEnd_isAShortTouchAndOneBounce() throws {
        try withSettings(switchOn: true) {
            // Not proven: the page is at its bottom when the first scroll starts.
            let watch = PageWatch(offset: 60_000, range: 60_000)
            let run = realRun(over: .touchOnly, watch: watch)
            for index in 0..<10 { XCTAssertTrue(try run.wheel(at: Double(index) * 0.03, y: -211.68), "never taken in: the place is not proven") }
            run.run(until: 3)
            var frames = run.finish()
            XCTAssertEqual(Array(frames.prefix(4).map(\.name)), ["began", "changed", "changed", "ended"])
            XCTAssertTrue(frames.prefix(4).dropFirst().prefix(2).allSatisfy { $0.y != 0 })
            XCTAssertLessThan(Double(frames[3].timestamp - frames[2].timestamp) / 1e9, 0.02, "\"ended\" right after the second frame")
            XCTAssertFalse(frames.dropFirst(4).contains { $0.hasPhase }, "the rest plain: one touch, one bounce, whatever the wheel does")
            XCTAssertGreaterThan(frames.dropFirst(4).filter { $0.y != 0 }.count, 20)
            XCTAssertNil(brokenGesture(in: frames))
            XCTAssertTrue(run.sessions.first?.session.endWatch.line?.contains("started at the end: a short touch after 0 ms; the rest plain (this place is not proven)") ?? false,
                          run.sessions.first?.session.endWatch.line ?? "")

            // Proven: the scroll arrived there; after a pause the wheel turns into the end again.
            let proven = PageWatch(offset: 59_600, range: 60_000)
            let second = realRun(over: .touchOnly, watch: proven)
            for index in 0..<8 { _ = try second.wheel(at: Double(index) * 0.02, y: -211.68) }
            second.run(until: 1.5)
            let arrived = second.frames.count
            XCTAssertEqual(second.frames.last?.name, "ended")
            for index in 0..<20 { XCTAssertTrue(try second.wheel(at: 1.5 + Double(index) * 0.02, y: -211.68)) }
            second.run(until: 4)
            frames = second.finish()
            let fresh = Array(frames.dropFirst(arrived))
            XCTAssertEqual(fresh.map(\.name), ["began", "changed", "changed", "ended"], "one short touch for twenty wheel events, the rest dropped and taken in")
            XCTAssertNil(brokenGesture(in: frames))
            XCTAssertTrue(second.sessions.last?.session.endWatch.line?.contains("the rest dropped") ?? false)
        }
    }

    /// Hard rule: with the switch off, and for every scroll that is no one touch (a flick,
    /// Safari and the listed apps, a sideways scroll, the old long touch), the end watch is
    /// never called: no look, no read, per wheel event or per display frame.
    func testEndWatch_isNeverCalledWithoutAOneTouch() throws {
        func calls(switchOn: Bool, over kind: ScrollUtils.TrackpadStyleTarget, oldLongTouch: Bool = false, sideways: Bool = false) throws -> Int {
            var count = 0
            try withSettings(switchOn: switchOn) {
                let watch = PageWatch(offset: 59_900, range: 60_000)
                let run = realRun(over: kind, oldLongTouch: oldLongTouch, watch: watch)
                for index in 0..<6 {
                    XCTAssertTrue(try run.wheel(at: Double(index) * 0.05, y: sideways ? 0 : -211.68, x: sideways ? 211.68 : 0))
                }
                run.run(until: 1)
                XCTAssertTrue(try run.wheel(at: 1.0, y: sideways ? 0 : 211.68, x: sideways ? -211.68 : 0))
                run.poster.stop(reason: .leftClick)
                XCTAssertTrue(try run.wheel(at: 1.1, y: sideways ? 0 : -211.68, x: sideways ? 211.68 : 0))
                run.run(until: 4)
                _ = run.finish()
                count = watch.looks + watch.reads
            }
            return count
        }
        XCTAssertEqual(try calls(switchOn: false, over: .touchOnly), 0, "the switch off")
        XCTAssertEqual(try calls(switchOn: false, over: .followsGlide), 0)
        XCTAssertEqual(try calls(switchOn: true, over: .followsGlide), 0, "a flick")
        XCTAssertEqual(try calls(switchOn: true, over: .safari), 0, "Safari")
        XCTAssertEqual(try calls(switchOn: true, over: .plainScrolling), 0, "a listed app")
        XCTAssertEqual(try calls(switchOn: true, over: .touchOnly, sideways: true), 0, "a sideways scroll")
        XCTAssertEqual(try calls(switchOn: true, over: .touchOnly, oldLongTouch: true), 0, "the old long touch")
        XCTAssertGreaterThan(try calls(switchOn: true, over: .touchOnly), 10, "a one touch: asked")
    }

    /// Hard rule: every "began" gets its "ended", never two phases on one event, the times
    /// never step back, whatever the watch answers and whenever: a watch that answers at
    /// random moments with random values (seen or not, at an end or not, reads that fail),
    /// and one that never answers, under wheel events at random moments, both ways, with a
    /// click now and then. And the worst a wrong answer does is plain frames: the page
    /// moves, or wheel events are taken in only after an arrival was seen.
    func testEndWatch_sweep_aWatchThatAnswersAtRandomAndOneThatNeverDoes() throws {
        var generator = SystemRandomNumberGenerator()
        let seed = UInt64.random(in: 0...UInt64.max, using: &generator)
        var state = seed
        func random() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
        try withSettings(switchOn: true) {
            for round in 0..<150 {
                let never = round % 5 == 4
                let watch = PageWatch(offset: 30_000, range: 60_000)
                watch.neverAnswers = never
                watch.answersAtOnce = false
                var bar = 0.5
                watch.valueInstead = { _ in bar }
                let run = realRun(over: .touchOnly, watch: watch)
                var time = 0.0
                for _ in 0..<40 {
                    time += random() * 0.12
                    let roll = random()
                    if roll < 0.55 {
                        _ = try run.wheel(at: time, y: random() < 0.7 ? -211.68 : 211.68, pointerX: random() < 0.9 ? 400 : 480)
                    } else if roll < 0.62 {
                        run.run(until: time)
                        run.poster.stop(reason: .leftClick)
                    } else {
                        run.run(until: time)
                    }
                    if random() < 0.6 {
                        bar = [0.0, 1.0, random(), random(), bar, bar][Int(random() * 6) % 6]
                        watch.seesTheBar = random() < 0.85
                        watch.readsWork = random() < 0.9
                        watch.answerNow()
                    }
                }
                watch.answerNow()
                run.run(until: time + 6)
                watch.answerNow()
                run.run(until: time + 8)
                let frames = run.finish()
                let label = "seed \(seed), round \(round)\(never ? ", never answers" : "")"
                if let broken = brokenGesture(in: frames) { XCTFail("\(label): \(broken)") }
                XCTAssertFalse(frames.contains { $0.scroll != 0 && $0.momentum != 0 }, "\(label): two phases on one event")
                let times = frames.filter { $0.hasPhase }.map(\.timestamp)
                XCTAssertEqual(times, times.sorted(), "\(label): a time steps back")
                XCTAssertEqual(Set(times).count, times.count, "\(label): two events with one time")
                XCTAssertFalse(run.poster.isGliding, "\(label): every scroll ended")
                if never {
                    XCTAssertFalse(frames.contains { $0.hasPhase }, "\(label): no answer, no phase")
                    XCTAssertEqual(watch.reads, 0, label)
                }
            }
        }
    }

    /// The real reader never works on the caller's thread and never asks where Scrollio is
    /// not trusted: asked on the main thread, both calls come back before the answer, the
    /// answer comes on another thread, and it is "not seen". (With "not trusted" answered
    /// here: a test never messages another app. What the reader does where it is trusted
    /// is run by no test.)
    func testEndWatch_theRealReader_answersOffTheCallersThreadAndNotWhereItIsNotTrusted() {
        var askedTrust = 0
        let reader = AccessibilityScrollEndWatch(isTrusted: {
            askedTrust += 1
            return false
        })
        let looked = expectation(description: "the look answered")
        let read = expectation(description: "the read answered")
        var returned = false
        reader.look(pid: ProcessInfo.processInfo.processIdentifier, at: CGPoint(x: 10, y: 10)) { reading in
            XCTAssertFalse(Thread.isMainThread)
            XCTAssertNil(reading.value)
            XCTAssertEqual(reading.failedAt, "Scrollio is not trusted for Accessibility")
            XCTAssertEqual(reading.roles, [])
            looked.fulfill()
        }
        reader.read { reading in
            XCTAssertFalse(Thread.isMainThread)
            XCTAssertNil(reading.value)
            read.fulfill()
        }
        returned = true
        wait(for: [looked, read], timeout: 5)
        XCTAssertTrue(returned)
        XCTAssertEqual(askedTrust, 1, "asked before anything else, and nothing after it")
        XCTAssertTrue(AccessibilityScrollEndWatch.firstLookLine(trusted: false).contains("not trusted"))
        XCTAssertTrue(AccessibilityScrollEndWatch.firstLookLine(trusted: true).contains("reads the scroll bar under the pointer through Accessibility"))
        XCTAssertTrue(ScrollPoster.isAtEnd(1.0, towardBottom: true) && ScrollPoster.isAtEnd(0.99995, towardBottom: true) && !ScrollPoster.isAtEnd(0.999, towardBottom: true))
        XCTAssertTrue(ScrollPoster.isAtEnd(0.0, towardBottom: false) && !ScrollPoster.isAtEnd(0.001, towardBottom: false) && !ScrollPoster.isAtEnd(1.0, towardBottom: false))
    }



    /// What breaks the rule in a stream of posted events, or nil: every "began" gets its
    /// "ended", a glide follows a touch or nothing does, each gesture is closed before the
    /// next one opens. Events without phases are left out.
    private func brokenGesture(in frames: [PostedFrame]) -> String? {
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
        for (index, frame) in frames.enumerated() where frame.hasPhase {
            if allowed[last]?.contains(frame.name) != true {
                return "\"\(frame.name)\" after \"\(last)\" (event \(index))"
            }
            last = frame.name
        }
        return last == "" || last == "ended" || last == "momentumEnded" || last == "cancelled" ? nil : "ends with \"\(last)\""
    }

    private static let phasedForms: [(name: String, kind: ScrollUtils.TrackpadStyleTarget, oldLongTouch: Bool)] = [
        ("flick", .followsGlide, false), ("one touch", .touchOnly, false), ("old long touch", .touchOnly, true),
    ]

    // MARK: A sideways scroll carries no phases

    /// What counts as mainly sideways: more distance sideways than up-down, or an up-down
    /// event while Scrollio's "scroll sideways" key turns the frames sideways.
    func testIsMainlySideways() {
        XCTAssertTrue(ScrollPoster.isMainlySideways(y: 0, x: 212, sidewaysKey: false), "the thumb wheel, Shift")
        XCTAssertTrue(ScrollPoster.isMainlySideways(y: 0, x: -212, sidewaysKey: false))
        XCTAssertTrue(ScrollPoster.isMainlySideways(y: 40, x: -212, sidewaysKey: false))
        XCTAssertFalse(ScrollPoster.isMainlySideways(y: 212, x: 0, sidewaysKey: false))
        XCTAssertFalse(ScrollPoster.isMainlySideways(y: -212, x: 40, sidewaysKey: false))
        XCTAssertFalse(ScrollPoster.isMainlySideways(y: 212, x: 212, sidewaysKey: false), "as far both ways: not mainly sideways")
        XCTAssertTrue(ScrollPoster.isMainlySideways(y: 212, x: 0, sidewaysKey: true), "the key turns an up-down event sideways")
        XCTAssertFalse(ScrollPoster.isMainlySideways(y: 212, x: 40, sidewaysKey: true), "an event with both is posted as it is")
        XCTAssertFalse(ScrollPoster.isMainlySideways(y: 0, x: 0, sidewaysKey: true))

        // While a scroll runs, an event with both deltas keeps its kind unless the other
        // axis leads two to one.
        XCTAssertFalse(ScrollPoster.isMainlySideways(y: 190, x: 212, sidewaysKey: false, running: false), "an up-down scroll runs: it stays one")
        XCTAssertFalse(ScrollPoster.isMainlySideways(y: 100, x: 200, sidewaysKey: false, running: false))
        XCTAssertTrue(ScrollPoster.isMainlySideways(y: 100, x: 201, sidewaysKey: false, running: false), "more than two to one: it turns")
        XCTAssertTrue(ScrollPoster.isMainlySideways(y: 212, x: 190, sidewaysKey: false, running: true), "a sideways scroll runs: it stays one")
        XCTAssertTrue(ScrollPoster.isMainlySideways(y: 200, x: 101, sidewaysKey: false, running: true))
        XCTAssertFalse(ScrollPoster.isMainlySideways(y: 200, x: 100, sidewaysKey: false, running: true), "two to one: it turns")
        // An event with one delta (an ordinary wheel, the thumb wheel, Shift) is judged the
        // same whatever runs.
        for running in [Bool?.none, true, false] {
            XCTAssertTrue(ScrollPoster.isMainlySideways(y: 0, x: 212, sidewaysKey: false, running: running))
            XCTAssertTrue(ScrollPoster.isMainlySideways(y: 0, x: -1, sidewaysKey: false, running: running))
            XCTAssertFalse(ScrollPoster.isMainlySideways(y: 212, x: 0, sidewaysKey: false, running: running))
            XCTAssertFalse(ScrollPoster.isMainlySideways(y: -1, x: 0, sidewaysKey: false, running: running))
            XCTAssertTrue(ScrollPoster.isMainlySideways(y: 212, x: 0, sidewaysKey: true, running: running))
            XCTAssertFalse(ScrollPoster.isMainlySideways(y: 0, x: 0, sidewaysKey: false, running: running))
        }
    }

    /// A device whose events carry both deltas and wobble about the diagonal (a trackball,
    /// a wheel that tilts while it turns): twelve events 25 ms apart, alternately a little
    /// more up-down and a little more sideways. Decided anew at every event, each flip ended
    /// the scroll with what was left of it (316 of 2,410 px arrived, in 12 scrolls). An
    /// event with both deltas now keeps the running scroll's kind unless the other axis
    /// leads two to one: one scroll, and the page moves exactly as with the switch off.
    func testTheRealPath_aDeviceThatWobblesAboutTheDiagonalKeepsItsScroll() throws {
        func run(switchOn: Bool, over kind: ScrollUtils.TrackpadStyleTarget, firstSideways: Bool) throws -> (frames: [PostedFrame], reasons: [ScrollSystemLog.EndReason]) {
            var result: ([PostedFrame], [ScrollSystemLog.EndReason]) = ([], [])
            try withSettings(switchOn: switchOn) {
                let run = realRun(over: kind)
                for index in 0..<12 {
                    let moreSideways = (index % 2 == 0) == firstSideways
                    XCTAssertTrue(try run.wheel(at: Double(index) * 0.025, y: moreSideways ? 190 : 211.68, x: moreSideways ? 211.68 : 190))
                }
                run.run(until: 5)
                let frames = run.finish()
                result = (frames, run.sessions.map(\.reason))
            }
            return result
        }
        for firstSideways in [false, true] {
            let off = try run(switchOn: false, over: .touchOnly, firstSideways: firstSideways)
            let offY = off.frames.reduce(0) { $0 + $1.y }, offX = off.frames.reduce(0) { $0 + $1.x }
            XCTAssertGreaterThan(offY, 2_300)
            XCTAssertGreaterThan(offX, 2_300)
            for form in Self.phasedForms where !form.oldLongTouch {
                let on = try run(switchOn: true, over: form.kind, firstSideways: firstSideways)
                let label = "\(form.name), the first event more \(firstSideways ? "sideways" : "up-down")"
                XCTAssertEqual(on.reasons, [.glidedOut], "\(label): one scroll, not one per flip")
                XCTAssertEqual(on.frames.reduce(0) { $0 + $1.y }, offY, "\(label): as far up-down as with the switch off")
                XCTAssertEqual(on.frames.reduce(0) { $0 + $1.x }, offX, "\(label): and sideways")
                XCTAssertNil(brokenGesture(in: on.frames), label)
                // The scroll keeps the kind of its first event to the end.
                XCTAssertEqual(on.frames.contains { $0.hasPhase }, !firstSideways, label)
            }
        }
    }

    /// One sideways click, over every kind of app, with the switch on: no posted event
    /// carries a phase, every one keeps the wheel event's time, line delta and hardware
    /// record (the switch-off stream), the app's kind is not even asked, and the log says
    /// why. (With phases a sideways scroll is a swipe to the app: back a page in Chrome and
    /// Firefox, the next tab in iTerm2.)
    func testTheRealPath_aSidewaysScrollCarriesNoPhases() throws {
        try withSettings(switchOn: true) {
            for form in Self.phasedForms {
                let run = realRun(over: form.kind, oldLongTouch: form.oldLongTouch)
                XCTAssertTrue(try run.wheel(at: 0, y: 0, x: 211.68))
                run.run(until: 3)
                let frames = run.finish()
                XCTAssertEqual(frames.filter { $0.x != 0 }.map(\.x), Self.defaultClick, "\(form.name): the default click, sideways")
                XCTAssertTrue(frames.allSatisfy { $0.y == 0 }, form.name)
                XCTAssertFalse(frames.contains { $0.hasPhase }, "\(form.name): no phase")
                XCTAssertTrue(frames.allSatisfy { $0.timestamp == 1_000_000_000 && $0.lines == 1 }, "\(form.name): the wheel event's fields")
                XCTAssertEqual(run.asked, 0, "\(form.name): the kind of the app is not asked")
                XCTAssertEqual(run.sessions.count, 1, form.name)
                XCTAssertEqual(run.sessions.first?.session.trackpadStyle, false, form.name)
                XCTAssertEqual(run.sessions.first?.session.trackpadStyleSideways, true, form.name)
                XCTAssertEqual(run.sessions.first?.session.trackpadStyleWithheld, false, form.name)
            }
            // Scrollio's own "scroll sideways" key: an up-down event whose frames go out sideways.
            let run = realRun(over: .touchOnly)
            run.poster.updateShifting(enable: true)
            XCTAssertTrue(try run.wheel(at: 0))
            run.run(until: 3)
            let frames = run.finish()
            XCTAssertEqual(frames.filter { $0.x != 0 }.map(\.x), Self.defaultClick)
            XCTAssertFalse(frames.contains { $0.hasPhase || $0.y != 0 })
            XCTAssertEqual(run.sessions.first?.session.trackpadStyleSideways, true)
        }
        // With the switch off nothing is new: the log does not call the scroll sideways.
        try withSettings(switchOn: false) {
            let run = realRun(over: .touchOnly)
            XCTAssertTrue(try run.wheel(at: 0, y: 0, x: 211.68))
            run.run(until: 3)
            let frames = run.finish()
            XCTAssertEqual(frames.filter { $0.x != 0 }.map(\.x), Self.defaultClick)
            XCTAssertEqual(run.sessions.first?.session.trackpadStyleSideways, false)
            XCTAssertEqual(ScrollSystemLog.message(for: try XCTUnwrap(run.sessions.first?.session), ended: .glidedOut).contains("trackpad-style off,"), true)
        }
    }

    /// The wheel turns from up-down to sideways and back in mid-scroll (the thumb wheel
    /// during the main wheel's glide, Shift pressed between two clicks), at every moment, in
    /// every form: no event that moves the page sideways carries a phase, every gesture the
    /// app got is whole, and the scroll that was running is closed before the other begins.
    func testTheRealPath_turningSidewaysAndBackLeavesWholeGesturesAndNoSidewaysPhase() throws {
        try withSettings(switchOn: true) {
            var runs = 0
            for form in Self.phasedForms {
                for gap in stride(from: 0.01, through: 0.9, by: 0.03) {
                    for upDownFirst in [true, false] {
                        let run = realRun(over: form.kind, oldLongTouch: form.oldLongTouch)
                        let label = "\(form.name), \(upDownFirst ? "up-down first" : "sideways first"), \(Int((gap * 1000).rounded())) ms apart"
                        var time = 0.0
                        for index in 0..<4 {
                            let sideways = (index % 2 == 0) != upDownFirst
                            XCTAssertTrue(try run.wheel(at: time, y: sideways ? 0 : 211.68, x: sideways ? 211.68 : 0), label)
                            time += gap
                        }
                        run.run(until: time + 3)
                        let frames = run.finish()
                        runs += 1
                        if let broken = brokenGesture(in: frames) {
                            XCTFail("\(label): \(broken)")
                        }
                        XCTAssertFalse(frames.contains { $0.x != 0 && $0.hasPhase }, "\(label): a sideways event with a phase")
                        XCTAssertFalse(frames.contains { $0.x != 0 && $0.y != 0 }, "\(label): one scroll at a time")
                        // (10 ms apart, an up-down scroll can be over before a display frame moved it.)
                        if gap > 0.02 || !upDownFirst {
                            XCTAssertTrue(frames.contains { $0.y != 0 && $0.hasPhase }, "\(label): the up-down scroll has its phases")
                        }
                        XCTAssertFalse(frames.contains { $0.y != 0 && !$0.hasPhase }, "\(label): an up-down event without a phase")
                        XCTAssertFalse(poster(run).isGliding, label)
                        let turned = run.sessions.filter { $0.reason == .axisChanged }.count
                        XCTAssertEqual(turned + run.sessions.filter { $0.reason == .glidedOut }.count, run.sessions.count, "\(label): \(run.sessions.map(\.reason))")
                        XCTAssertFalse(run.sessions.contains { $0.reason == .settingChanged }, label)
                    }
                }
            }
            XCTAssertEqual(runs, 3 * 30 * 2)
        }
    }

    /// The "scroll sideways" key goes down while a scroll with phases glides on, without a
    /// wheel event: its frames would turn sideways with their phases on. The scroll is ended
    /// (its gesture closed) and nothing follows. A scroll without phases goes on, as always.
    func testTheRealPath_theSidewaysKeyInMidScrollEndsAScrollWithPhases() throws {
        try withSettings(switchOn: true) {
            for form in Self.phasedForms {
                let run = realRun(over: form.kind, oldLongTouch: form.oldLongTouch)
                XCTAssertTrue(try run.wheel(at: 0))
                run.run(until: 0.1)
                XCTAssertTrue(run.poster.isGliding, form.name)
                run.poster.updateShifting(enable: true)
                XCTAssertFalse(run.poster.isGliding, "\(form.name): ended")
                run.run(until: 2)
                let frames = run.finish()
                XCTAssertNil(brokenGesture(in: frames), form.name)
                XCTAssertFalse(frames.contains { $0.x != 0 }, "\(form.name): nothing went out sideways")
                XCTAssertEqual(run.sessions.map(\.reason), [.axisChanged], form.name)
            }
        }
        try withSettings(switchOn: false) {
            let run = realRun(over: .touchOnly)
            XCTAssertTrue(try run.wheel(at: 0))
            run.run(until: 0.1)
            run.poster.updateShifting(enable: true)
            XCTAssertTrue(run.poster.isGliding, "off: the scroll goes on, its frames now sideways")
            run.run(until: 2)
            let frames = run.finish()
            XCTAssertEqual(frames.reduce(0) { $0 + $1.y + $1.x }, 205)
            XCTAssertTrue(frames.contains { $0.x != 0 })
            XCTAssertEqual(run.sessions.map(\.reason), [.glidedOut])
        }
    }

    private func poster(_ run: RealRun) -> ScrollPoster { return run.poster }

    // MARK: The flick's held "ended", as posted

    /// A flick whose glide's first frame comes late (a scroll of a few pixels at the longest
    /// glide time): its "ended" waits for that frame. When the wheel then goes on over
    /// another pane, the "ended" goes out first, at the place of the touch it ends, and the
    /// new touch begins at the new place. When the wheel goes on where it was, the "ended"
    /// goes on waiting and goes out with "momentum began".
    func testTheRealPath_flick_aHeldEndedGoesOutAtItsOwnPlace() throws {
        try withSettings(switchOn: true) {
            func untilTheEndedIsHeld(_ run: RealRun) throws -> Double {
                run.duration = 5.0
                XCTAssertTrue(try run.wheel(at: 0, y: 12, pointerX: 400))
                var time = 0.0
                while !run.poster.endedWaitsForGlideForTests && time < 3 {
                    time += 1.0 / 60.0
                    run.run(until: time)
                }
                XCTAssertTrue(run.poster.endedWaitsForGlideForTests, "the touch is over and the glide's first frame has not come")
                XCTAssertEqual(run.frames.map(\.name).filter { $0 == "ended" || $0 == "momentumBegan" }, [], "nothing of the end is out yet")
                return time
            }
            let far = realRun(over: .followsGlide)
            var time = try untilTheEndedIsHeld(far)
            let before = far.frames.count
            XCTAssertTrue(try far.wheel(at: time + 0.004, y: 12, pointerX: 900))
            let closing = try XCTUnwrap(far.frames.dropFirst(before).first)
            XCTAssertEqual(closing.name, "ended")
            XCTAssertEqual(closing.pointerX, 400, "at the place of the touch it ends")
            far.run(until: time + 6)
            let all = far.finish()
            XCTAssertNil(brokenGesture(in: all))
            XCTAssertEqual(all.filter { $0.scroll == 1 }.map(\.pointerX), [400, 900], "two touches, each begun at its place")
            XCTAssertEqual(all.filter { $0.scroll == 4 }.first?.pointerX, 400)

            let near = realRun(over: .followsGlide)
            time = try untilTheEndedIsHeld(near)
            let count = near.frames.count
            XCTAssertTrue(try near.wheel(at: time + 0.004, y: 12, pointerX: 405))
            XCTAssertEqual(near.frames.count, count, "the same place: the \"ended\" goes on waiting")
            near.run(until: time + 6)
            let stream = near.finish()
            XCTAssertNil(brokenGesture(in: stream))
            XCTAssertEqual(stream.filter { $0.scroll == 1 }.count, 1, "one touch")
            let ended = try XCTUnwrap(stream.firstIndex { $0.name == "ended" })
            XCTAssertEqual(stream[ended + 1].name, "momentumBegan", "and goes out with the glide's first frame")
        }
    }

    /// A flick's closing frames go out at the place of the gesture they close, whatever
    /// the wheel does next in the same app. Three cases, each with the next wheel event
    /// 500 pt away:
    /// - while the glide runs (scroll, move to another pane or window, scroll again):
    ///   "momentum ended" used to be a copy of the new event, at the new place;
    /// - while the touch is still open (a scroll of a few pixels at a long glide time: the
    ///   touch lasts until two frames have moved the page): no new touch began, and the
    ///   rest of the first gesture went out at the new place;
    /// - before the first frame has moved the page: "began" goes out at the second place,
    ///   and a later wheel event there adds to the glide (the touch's place was left the
    ///   first one's, so it began a touch of its own).
    func testTheRealPath_flick_closingFramesGoOutAtTheirOwnPlace() throws {
        try withSettings(switchOn: true) {
            // In the glide.
            let glide = realRun(over: .followsGlide)
            XCTAssertTrue(try glide.wheel(at: 0, pointerX: 400))
            glide.run(until: 0.25)
            XCTAssertEqual(glide.frames.last?.name, "momentumChanged")
            var before = glide.frames.count
            XCTAssertTrue(try glide.wheel(at: 0.254, pointerX: 900))
            XCTAssertEqual(glide.frames.dropFirst(before).map(\.name), ["momentumEnded"])
            XCTAssertEqual(glide.frames.dropFirst(before).first?.pointerX, 400, "the glide ends where it ran")
            glide.run(until: 4)
            var all = glide.finish()
            XCTAssertNil(brokenGesture(in: all))
            XCTAssertTrue(all.prefix(before + 1).allSatisfy { $0.pointerX == 400 })
            XCTAssertTrue(all.dropFirst(before + 1).allSatisfy { $0.pointerX == 900 }, "the new gesture, whole, at the new place")
            XCTAssertEqual(all.dropFirst(before + 1).first?.name, "began")
            let moved = all.filter { $0.y != 0 }.map(\.y)
            try withSettings(switchOn: false) {
                let off = realRun(over: .followsGlide)
                XCTAssertTrue(try off.wheel(at: 0, pointerX: 400))
                off.run(until: 0.25)
                XCTAssertTrue(try off.wheel(at: 0.254, pointerX: 900))
                off.run(until: 4)
                XCTAssertEqual(moved, off.finish().filter { $0.y != 0 }.map(\.y), "the motion goes on as with the switch off")
            }

            // In the touch.
            let touch = realRun(over: .followsGlide)
            touch.duration = 5.0
            XCTAssertTrue(try touch.wheel(at: 0, y: 12, pointerX: 400))
            var time = 0.0
            while touch.frames.count < 1 && time < 3 {
                time += 1.0 / 60.0
                touch.run(until: time)
            }
            XCTAssertEqual(touch.frames.map(\.name), ["began"], "the touch is open: one frame has moved the page")
            XCTAssertFalse(touch.poster.endedWaitsForGlideForTests)
            before = touch.frames.count
            XCTAssertTrue(try touch.wheel(at: time + 0.004, y: 12, pointerX: 900))
            XCTAssertEqual(touch.frames.dropFirst(before).map(\.name), ["ended"])
            XCTAssertEqual(touch.frames.dropFirst(before).first?.pointerX, 400, "the touch ends where it began")
            touch.run(until: time + 8)
            all = touch.finish()
            XCTAssertNil(brokenGesture(in: all))
            XCTAssertEqual(all.filter { $0.scroll == 1 }.map(\.pointerX), [400, 900], "and a touch of its own begins at the new place")
            XCTAssertTrue(all.dropFirst(before + 1).allSatisfy { $0.pointerX == 900 })

            // Before the first frame.
            let early = realRun(over: .followsGlide)
            XCTAssertTrue(try early.wheel(at: 0, pointerX: 400))
            XCTAssertTrue(try early.wheel(at: 0.004, pointerX: 900))
            XCTAssertTrue(early.frames.isEmpty, "nothing of the first touch went out, so nothing is closed")
            early.run(until: 0.3)
            XCTAssertTrue(try early.wheel(at: 0.304, pointerX: 900))
            early.run(until: 5)
            all = early.finish()
            XCTAssertNil(brokenGesture(in: all))
            XCTAssertEqual(all.filter { $0.scroll == 1 }.map(\.pointerX), [900], "one touch, at the second place")
            XCTAssertEqual(all.filter { $0.momentum == 3 }.count, 1, "and one glide: the third wheel event added to it")
            XCTAssertEqual(early.sessions.last?.session.glideInputs, 1)
        }
    }

    // MARK: The one touch's end, as posted

    /// What ends a one touch by itself is a display frame: the first one 0.2 s after the
    /// touch's last frame. When no frame comes in that rest (a display link that runs but
    /// does not call: suspected for a display that goes to sleep), the touch stays open
    /// until the keeper's look finds a link with nothing posted and no wheel event for 5 s.
    /// The keeper then ends the scroll: "ended" and the tap go out, and the scroll's line
    /// says who ended it.
    func testTheRealPath_oneTouch_withoutFramesInTheRestTheKeeperEndsItAndTheLogSaysSo() throws {
        try withSettings(switchOn: true) {
            let run = realRun(over: .touchOnly)
            XCTAssertTrue(try run.wheel(at: 0))
            run.run(until: 0.45)
            XCTAssertEqual(run.frames.last?.name, "changed", "the last frame has gone out, the touch rests")
            let before = run.frames.count
            // No display frame from here on. The keeper looks 3 s later: too soon.
            run.poster.healthCheckForTests(now: 5_000 + 0.45 + 3)
            XCTAssertEqual(run.frames.count, before)
            XCTAssertTrue(run.poster.isGliding, "the touch is still open")
            run.poster.healthCheckForTests(now: 5_000 + 0.45 + 5.1)
            XCTAssertFalse(run.poster.isGliding)
            let frames = run.finish()
            XCTAssertEqual(frames.dropFirst(before).map(\.name), ["ended", "mayBegin", "cancelled"])
            XCTAssertNil(brokenGesture(in: frames))
            XCTAssertEqual(run.sessions.map(\.reason), [.keeper])
            let line = ScrollSystemLog.message(for: try XCTUnwrap(run.sessions.first?.session), ended: .keeper)
            XCTAssertTrue(line.hasSuffix("trackpad-style on (one touch: 1 touches), ended: ended by the keeper"), line)
            XCTAssertTrue(run.poster.healthLinesForTests.contains { $0.contains("the keeper stopped a display link") }, "and the app log says why")
        }
    }

    /// A scroll that runs out by itself, through the real path: the posted "ended" carries
    /// a time 0.2 s or more after the last "changed", it is handed over that long after it,
    /// nothing follows it, and the scroll's line in the log comes after it.
    func testTheRealPath_oneTouch_endedComesAFifthOfASecondAfterTheLastFrame() throws {
        try withSettings(switchOn: true) {
            let run = realRun(over: .touchOnly)
            XCTAssertTrue(try run.wheel(at: 0))
            run.run(until: 0.6)
            XCTAssertTrue(run.poster.isGliding, "the scroll stays up while the touch rests")
            XCTAssertEqual(run.frames.last?.name, "changed", "no \"ended\" yet: the last frame went out at 0.433 s")
            XCTAssertTrue(run.sessions.isEmpty)
            run.run(until: 3)
            let at = run.postedAt
            let frames = run.finish()
            XCTAssertEqual(phaseRuns(frames), ["began ×1", "changed ×26", "ended ×1"])
            let ended = try XCTUnwrap(frames.last)
            let lastChanged = try XCTUnwrap(frames.last { $0.y != 0 })
            XCTAssertGreaterThanOrEqual(Double(ended.timestamp - lastChanged.timestamp) / 1e9, 0.2005 - 1e-9)
            XCTAssertLessThan(Double(ended.timestamp - lastChanged.timestamp) / 1e9, 0.2005 + 1.0 / 60.0)
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(at.last) - at[at.count - 2], 0.2)
            XCTAssertEqual(run.sessions.map(\.reason), [.glidedOut])
            XCTAssertFalse(run.poster.isGliding)
        }
    }

    /// A wheel event that comes while the touch rests, through the real path, at every
    /// moment of the rest and after it, at three feels: what moves the page is what moves it
    /// with the switch off, frame for frame (the scroll under the touch may have ended in
    /// between: with the switch off the second click then begins a scroll of its own). In
    /// the rest it is one touch and one scroll; after the "ended" a second touch.
    func testTheRealPath_oneTouch_aWheelEventInTheRestMovesThePageAsWithTheSwitchOff() throws {
        func posted(switchOn: Bool, second: Double, duration: Double) throws -> (frames: [PostedFrame], at: [Double], scrolls: Int) {
            var result: ([PostedFrame], [Double], Int) = ([], [], 0)
            try withSettings(switchOn: switchOn) {
                let run = realRun(over: .touchOnly)
                run.duration = duration
                XCTAssertTrue(try run.wheel(at: 0))
                XCTAssertTrue(try run.wheel(at: second))
                run.run(until: second + 6)
                let at = run.postedAt
                let frames = run.finish()
                result = (frames, at, run.sessions.count)
            }
            return result
        }
        var inTheRest = 0, after = 0
        for duration in [2.0, 3.69, 4.35] {
            for second in stride(from: 0.20, through: 1.3, by: 0.0235) {
                let label = "Duration \(duration), a second click at \(Int((second * 1000).rounded())) ms"
                let on = try posted(switchOn: true, second: second, duration: duration)
                let off = try posted(switchOn: false, second: second, duration: duration)
                let moving = zip(on.frames, on.at).filter { $0.0.y != 0 }
                let movingOff = zip(off.frames, off.at).filter { $0.0.y != 0 }
                XCTAssertEqual(moving.map { $0.0.y }, movingOff.map { $0.0.y }, "\(label): the motion")
                XCTAssertEqual(moving.map { $0.1 }, movingOff.map { $0.1 }, "\(label): its times")
                XCTAssertNil(brokenGesture(in: on.frames), label)
                XCTAssertFalse(on.frames.contains { $0.scroll == 128 || $0.scroll == 8 }, "\(label): no tap, nothing was forced")
                let touches = on.frames.filter { $0.scroll == 1 }.count
                if touches == 1 {
                    inTheRest += 1
                    XCTAssertEqual(on.scrolls, 1, label)
                } else {
                    after += 1
                    XCTAssertEqual(touches, 2, label)
                }
            }
        }
        XCTAssertGreaterThan(inTheRest, 30)
        XCTAssertGreaterThan(after, 30)
    }

    /// A click in mid-scroll, through the real path: what the app reads on the three
    /// closing events. "Ended", then scroll phase 128 and 8, none with a momentum phase or a
    /// distance in any delta field, each with a time of its own, none with the wheel's
    /// hardware record, all to the app that had the touch, and all out when the stop returns.
    func testTheRealPath_oneTouch_aClickPostsEndedAndTheTwoFingerTap() throws {
        try withSettings(switchOn: true) {
            let run = realRun(over: .touchOnly)
            XCTAssertTrue(try run.wheel(at: 0))
            run.run(until: 0.1)
            let before = run.frames.count
            run.poster.stop(reason: .leftClick)
            // (`frames` lets the queue catch up; the wait of the stop itself is held by
            // `testAStopReturnsAfterItsClosingFrameWentOut`.)
            let closing = Array(run.frames.dropFirst(before))
            XCTAssertEqual(closing.map(\.scroll), [4, 128, 8])
            XCTAssertTrue(closing.allSatisfy { $0.momentum == 0 && $0.y == 0 && $0.x == 0 && $0.lines == 0 && $0.fixedLines == 0 })
            XCTAssertTrue(closing.allSatisfy { $0.pid == 4242 && $0.isContinuous == 1 && $0.scrollCount == 0 })
            XCTAssertEqual(closing.map(\.timestamp), closing.map(\.timestamp).sorted())
            XCTAssertEqual(Set(closing.map(\.timestamp)).count, 3)
            XCTAssertGreaterThan(closing[0].timestamp, run.frames[before - 1].timestamp)
            if ScrollHardwareRecord.comesOff {
                XCTAssertTrue(closing.allSatisfy { $0.hasRecord == false })
            }
            run.run(until: 2)
            let frames = run.finish()
            XCTAssertEqual(frames.count, before + 3, "nothing after the tap")
            XCTAssertNil(brokenGesture(in: frames))
            XCTAssertEqual(run.sessions.map(\.reason), [.leftClick])
            XCTAssertEqual(try XCTUnwrap(NSEvent(cgEvent: try tapEvent(phase: 128))).phase, .mayBegin, "128 is \"may begin\" to AppKit")
            XCTAssertEqual(try XCTUnwrap(NSEvent(cgEvent: try tapEvent(phase: 8))).phase, .cancelled, "8 is \"cancelled\"")
        }
    }

    /// An event written as a frame of the tap is, to AppKit, the phase it says.
    private func tapEvent(phase: Double) throws -> CGEvent {
        let event = try wheelEvent()
        var frame = ScrollOutgoingFrame(y: 0, x: 0, scrollPhase: phase, momentumPhase: 0)
        frame.isTrackpadStyle = true
        frame.write(to: event)
        return event
    }

    /// Gives an event a hardware record as a wheel's event has one. Skips the test on a
    /// macOS where the record cannot be made or read (the functions are private).
    private func attachHardwareRecord(to event: CGEvent) throws {
        let calls = try XCTUnwrap(ScrollHardwareRecord.readingCalls, "this macOS has the three functions")
        let record = try XCTUnwrap(calls.createScroll(nil, mach_absolute_time(), 0, 1, 0, 0))
        calls.set(event, record)
        Unmanaged<AnyObject>.fromOpaque(record).release()
        XCTAssertEqual(ScrollHardwareRecord.isCarried(by: event), true)
    }

    /// Sets the Scrolling pane's switch and the entry of the app under the pointer for one
    /// test, and puts both back.
    private func withSettings(switchOn: Bool, application: Application? = nil, _ body: () throws -> Void) rethrows {
        let savedApplication = ScrollCore.shared.application
        let savedSwitch = Options.shared.scroll.smoothSimTrackpad
        ScrollCore.shared.application = application
        Options.shared.scroll.smoothSimTrackpad = switchOn
        defer {
            ScrollCore.shared.application = savedApplication
            Options.shared.scroll.smoothSimTrackpad = savedSwitch
        }
        try body()
    }

    private func phaseRuns(_ frames: [PostedFrame]) -> [String] {
        var runs: [(String, Int)] = []
        for frame in frames {
            if runs.last?.0 == frame.name { runs[runs.count - 1].1 += 1 } else { runs.append((frame.name, 1)) }
        }
        return runs.map { "\($0.0) ×\($0.1)" }
    }

    /// Over a Chromium-based app: a flick. The posted events carry the phases of a short touch
    /// and its glide, and every one its own time (the wheel event's time is on none of them).
    /// Until now the phases and times were only checked on frames before they were written
    /// to an event, with the form set by hand.
    func testTheRealPath_overAChromiumApp_postsAFlickWithItsOwnTimes() throws {
        try withSettings(switchOn: true) {
            let result = try oneClick(over: .followsGlide)
            XCTAssertEqual(phaseRuns(result.frames), [
                "began ×1", "changed ×1", "ended ×1", "momentumBegan ×1", "momentumChanged ×23", "momentumEnded ×1",
            ])
            XCTAssertEqual(result.frames.first?.y, 7, "\"began\" is the first frame that moves the page")
            try assertOwnFields(result.frames)
            XCTAssertEqual(result.asked, 1, "the app's kind is asked once per wheel event")
            XCTAssertEqual(result.session?.trackpadStyle, true)
            XCTAssertEqual(result.session?.flick, true)
            XCTAssertEqual(result.session?.touches, 1)
        }
    }

    /// What every posted event of "Trackpad-style scrolling" reads, in every form: a time of
    /// its own (not the wheel event's, later than the event before it), its own line delta
    /// and fixed-point delta (a tenth of its pixels; the wheel event's said one line on every
    /// frame), and a scroll count of 0 (the wheel event's was 3).
    private func assertOwnFields(_ frames: [PostedFrame], file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertFalse(frames.isEmpty, file: file, line: line)
        let times = frames.map(\.timestamp)
        XCTAssertTrue(times.allSatisfy { $0 > Self.firstFrameTime }, "every frame its own time, none the wheel event's", file: file, line: line)
        XCTAssertEqual(times, times.sorted(), file: file, line: line)
        XCTAssertEqual(Set(times).count, times.count, "no two frames the same time", file: file, line: line)
        XCTAssertTrue(frames.allSatisfy { $0.scrollCount == 0 }, "scroll count 0", file: file, line: line)
        XCTAssertTrue(frames.allSatisfy { abs($0.fixedLines - Double($0.y) / 10) < 0.001 }, "the fixed-point delta is the frame's", file: file, line: line)
        XCTAssertTrue(frames.allSatisfy { abs(Double($0.lines) - Double($0.y) / 10) < 1 }, "the line delta is the frame's", file: file, line: line)
        XCTAssertEqual(Double(frames.reduce(0) { $0 + $1.lines }), Double(frames.reduce(0) { $0 + $1.y }) / 10, accuracy: 1, file: file, line: line)
    }

    /// Over any other app (AppKit, a web view, an app that is not known): one touch until the
    /// scroll has run out. Every frame of the click is a "changed", "ended" follows the last
    /// one, no event carries a glide phase, and every one has its own time and line delta.
    func testTheRealPath_overAnyOtherApp_postsOneTouchToTheEnd() throws {
        try withSettings(switchOn: true) {
            let result = try oneClick(over: .touchOnly)
            XCTAssertEqual(phaseRuns(result.frames), ["began ×1", "changed ×26", "ended ×1"])
            XCTAssertFalse(result.frames.contains { $0.momentum != 0 }, "no glide event")
            try assertOwnFields(result.frames)
            XCTAssertEqual(result.frames.filter { $0.scroll == 2 }.reduce(0) { $0 + $1.y }, 205, "the touch carries the whole click")
            XCTAssertEqual(result.session?.trackpadStyle, true)
            XCTAssertEqual(result.session?.flick, false)
            XCTAssertEqual(result.session?.oneTouch, true)
            XCTAssertEqual(result.session?.touches, 1)
        }
    }

    /// Nothing falls between that "ended" and the "began" that follows. A display frame tries
    /// to run at the moment the far wheel event is being stored: it has to wait until that
    /// event's "began" is out, and then moves the page as the new touch's "changed". The
    /// "ended" and the rest of the wheel event used to be two stretches under the lock: a
    /// frame that ran between them found no touch to belong to, and its distance was lost.
    func testTheRealPath_noDisplayFrameFallsBetweenATouchsEndedAndTheNextBegan() throws {
        try withSettings(switchOn: true) {
            let context = ScrollDispatchContext()
            let poster = ScrollPoster(phases: ScrollPhase(), dispatchContext: context)
            poster.trackpadStyleTarget = { _ in .touchOnly }
            _ = FakeDisplay(for: poster)
            var posted: [(scroll: Double, x: CGFloat, y: Int64)] = []
            let lock = NSLock()
            context.postObserverForTests = { event, _ in
                lock.lock()
                posted.append((event.getDoubleValueField(.scrollWheelEventScrollPhase), event.location.x,
                               event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)))
                lock.unlock()
            }
            func wheel(atX x: CGFloat) throws -> CGEvent {
                let event = try wheelEvent()
                event.location = CGPoint(x: x, y: 300)
                return event
            }
            var now = ScrollPoster.monotonicNow()
            XCTAssertTrue(poster.smooth(event: try wheel(atX: 400), input: input()))
            for _ in 0..<3 {
                now += 1.0 / 60.0
                poster.displayLinkCallbackForTests(frameInterval: 1.0 / 60.0, now: now)
            }
            context.waitForPostQueueForTests()

            // The display link's thread wants a frame while the far event is being stored.
            let frameTime = now + 1.0 / 60.0
            let frameDone = DispatchSemaphore(value: 0)
            var ranWhileTheEventWasStored: Bool?
            context.captureObserverForTests = {
                context.captureObserverForTests = nil
                DispatchQueue.global(qos: .userInteractive).async {
                    poster.displayLinkCallbackForTests(frameInterval: 1.0 / 60.0, now: frameTime)
                    frameDone.signal()
                }
                ranWhileTheEventWasStored = frameDone.wait(timeout: .now() + 0.2) == .success
            }
            XCTAssertTrue(poster.smooth(event: try wheel(atX: 900), input: input()))

            XCTAssertEqual(ranWhileTheEventWasStored, false, "the frame waited for the lock")
            XCTAssertEqual(frameDone.wait(timeout: .now() + 5), .success, "and ran once the event's \"began\" was out")
            context.waitForPostQueueForTests()
            lock.lock()
            let all = posted
            lock.unlock()
            let ended = try XCTUnwrap(all.firstIndex { $0.scroll == 4 })
            XCTAssertEqual(all[ended].x, 400, "the touch ended at its own place")
            XCTAssertEqual(all.dropFirst(ended + 1).prefix(2).map(\.scroll), [128, 8], "the tap after the forced end")
            XCTAssertTrue(all.dropFirst(ended + 1).prefix(2).allSatisfy { $0.x == 400 }, "at the touch's own place")
            // Since the end watch the new touch opens with the answer to its look, which is
            // asked for once the lock is let go: the display frame that waited either follows
            // the "began" as its "changed", or goes out before it, plain. Either way at the
            // new place, and its distance is not lost.
            let after = Array(all.dropFirst(ended + 3))
            XCTAssertTrue(after.map(\.scroll) == [1, 2] || after.map(\.scroll) == [0, 1], "\(after.map(\.scroll))")
            XCTAssertTrue(after.allSatisfy { $0.x == 900 })
            XCTAssertGreaterThan(after.reduce(0) { $0 + $1.y }, 0, "its distance went out")
            context.waitForPostQueueForTests()
            poster.stop()
        }
    }

    /// EVALUATION SWITCH: with it the same apps get the old long touch, a touch until the
    /// wheel has been still for 0.18 s and the rest as its glide: 135 of the click's 205 px
    /// in the touch. Nothing else changes with it: a Chromium app still gets the flick.
    func testTheRealPath_withTheEvaluationSwitch_postsTheOldLongTouch() throws {
        try withSettings(switchOn: true) {
            let result = try oneClick(over: .touchOnly, oldLongTouch: true)
            XCTAssertEqual(phaseRuns(result.frames), [
                "began ×1", "changed ×10", "ended ×1", "momentumBegan ×1", "momentumChanged ×15", "momentumEnded ×1",
            ])
            try assertOwnFields(result.frames)
            XCTAssertEqual(result.frames.filter { $0.scroll == 2 }.reduce(0) { $0 + $1.y }, 135, "what the touch carries of the 205 px")
            XCTAssertEqual(result.session?.trackpadStyle, true)
            XCTAssertEqual(result.session?.flick, false)
            XCTAssertEqual(result.session?.oneTouch, false)

            let flick = try oneClick(over: .followsGlide, oldLongTouch: true)
            XCTAssertEqual(flick.session?.flick, true)
            XCTAssertEqual(phaseRuns(flick.frames).prefix(4), ["began ×1", "changed ×1", "ended ×1", "momentumBegan ×1"])
        }
    }

    /// The one touch ends at its own place. The wheel goes on over another pane of the same
    /// app: the "ended" of the open touch is a copy of the last event at the first place, and
    /// the "began" that follows is the new event's. (Ended after the new event was stored, it
    /// would carry the second pane's place, for a touch that pane never saw begin.)
    func testTheRealPath_theOneTouchEndsAtItsOwnPlace() throws {
        try withSettings(switchOn: true) {
            let context = ScrollDispatchContext()
            let poster = ScrollPoster(phases: ScrollPhase(), dispatchContext: context)
            poster.trackpadStyleTarget = { _ in .touchOnly }
            _ = FakeDisplay(for: poster)
            var posted: [(scroll: Double, x: CGFloat)] = []
            let lock = NSLock()
            context.postObserverForTests = { event, _ in
                lock.lock()
                posted.append((event.getDoubleValueField(.scrollWheelEventScrollPhase), event.location.x))
                lock.unlock()
            }
            func wheel(atX x: CGFloat) throws -> CGEvent {
                let event = try wheelEvent()
                event.location = CGPoint(x: x, y: 300)
                return event
            }
            var now = ScrollPoster.monotonicNow()
            func frames(_ count: Int) {
                for _ in 0..<count {
                    now += 1.0 / 60.0
                    poster.displayLinkCallbackForTests(frameInterval: 1.0 / 60.0, now: now)
                }
            }

            XCTAssertTrue(poster.smooth(event: try wheel(atX: 400), input: input()))
            frames(3)
            XCTAssertTrue(poster.smooth(event: try wheel(atX: 410), input: input()))   // the hand moved a little
            frames(3)
            XCTAssertTrue(poster.smooth(event: try wheel(atX: 900), input: input()))   // another pane
            frames(3)
            // (The frames come here without the 16 ms between them: the post queue catches
            // up before the stop, which drops what still waits from before it.)
            context.waitForPostQueueForTests()
            poster.stop()

            context.waitForPostQueueForTests()
            lock.lock()
            let all = posted
            lock.unlock()
            XCTAssertEqual(all.filter { $0.scroll == 1 }.map(\.x), [400, 900], "two touches: the first place and the far one")
            XCTAssertEqual(all.filter { $0.scroll == 4 }.map(\.x), [410, 900], "each ended where it was")
            let firstEnded = try XCTUnwrap(all.firstIndex { $0.scroll == 4 })
            XCTAssertEqual(all.dropFirst(firstEnded + 1).prefix(3).map(\.scroll), [128, 8, 1], "the tap of the forced end, and the new touch begins right after")
            XCTAssertEqual(all.filter { $0.scroll == 128 }.map(\.x), [410, 900], "each tap where its touch was")
            XCTAssertEqual(all.filter { $0.scroll == 8 }.map(\.x), [410, 900])
            XCTAssertTrue(all.prefix(firstEnded + 3).allSatisfy { $0.x == 400 || $0.x == 410 })
            XCTAssertTrue(all.dropFirst(firstEnded + 3).allSatisfy { $0.x == 900 })
        }
    }

    /// Over Safari: no phase on any posted event and the wheel event's time, exactly the
    /// switch-off stream; the log says the switch is on but nothing was sent to this app.
    func testTheRealPath_overSafari_postsNoPhases() throws {
        try withSettings(switchOn: true) {
            let result = try oneClick(over: .plainScrolling)
            XCTAssertFalse(result.frames.contains { $0.hasPhase })
            XCTAssertTrue(result.frames.allSatisfy { $0.timestamp == Self.wheelTime })
            XCTAssertTrue(result.frames.allSatisfy { $0.scrollCount == Self.wheelScrollCount }, "without phases: the wheel event's scroll count")
            XCTAssertTrue(result.frames.allSatisfy { $0.lines == 1 }, "and its line delta")
            XCTAssertEqual(result.session?.trackpadStyle, false)
            XCTAssertEqual(result.session?.trackpadStyleWithheld, true)
        }
        // The same stream with the switch off, and then the app's kind is not even asked.
        try withSettings(switchOn: false) {
            let off = try oneClick(over: .followsGlide)
            XCTAssertFalse(off.frames.contains { $0.hasPhase })
            XCTAssertTrue(off.frames.allSatisfy { $0.timestamp == Self.wheelTime })
            XCTAssertTrue(off.frames.allSatisfy { $0.scrollCount == Self.wheelScrollCount && $0.lines == 1 }, "off: the wheel event's fields stay")
            XCTAssertEqual(off.asked, 0, "asked only while the switch is on")
            XCTAssertEqual(off.session?.trackpadStyle, false)
            XCTAssertEqual(off.session?.trackpadStyleWithheld, false)
        }
    }

    /// No posted event of "Trackpad-style scrolling" carries the wheel event's hardware
    /// record, in any form: WebKit makes a glide of its own from the record on "momentum
    /// began" and drops the glide it is sent (36 of a flick's 205 px arrived in a WKWebView,
    /// 146 of the old long touch's). Without phases every frame keeps the record, as always.
    /// Where the launch's self-test did not pass, the frames keep it too.
    func testTheRealPath_noFrameWithPhasesCarriesTheWheelsHardwareRecord() throws {
        try XCTSkipUnless(ScrollHardwareRecord.comesOff, "the record is not taken off on this macOS (\(ScrollHardwareRecord.system.outcome))")
        try withSettings(switchOn: true) {
            for (kind, oldLongTouch) in [(ScrollUtils.TrackpadStyleTarget.followsGlide, false), (.touchOnly, false), (.touchOnly, true)] {
                let result = try oneClick(over: kind, oldLongTouch: oldLongTouch)
                XCTAssertTrue(result.frames.allSatisfy { $0.hasPhase }, "\(kind)")
                XCTAssertTrue(result.frames.allSatisfy { $0.hasRecord == false }, "\(kind), old long touch \(oldLongTouch): no frame carries a record")
            }
            let safari = try oneClick(over: .plainScrolling)
            XCTAssertTrue(safari.frames.allSatisfy { $0.hasRecord == true }, "no phases: the wheel event's record stays")

            // The self-test did not pass: as before, every frame keeps the record.
            for kind in [ScrollUtils.TrackpadStyleTarget.followsGlide, .touchOnly] {
                let kept = try oneClick(over: kind, takesRecordOff: false)
                XCTAssertTrue(kept.frames.allSatisfy { $0.hasRecord == true }, "\(kind)")
            }
        }
        try withSettings(switchOn: false) {
            let off = try oneClick(over: .followsGlide, chrome: true)
            XCTAssertEqual(off.frames.last?.name, "ended")
            XCTAssertTrue(off.frames.allSatisfy { $0.hasRecord == true }, "off: every frame keeps the record, Chrome's \"ended\" too")
        }
    }

    /// Over Safari (and the DuckDuckGo browser): the flick, as a Chromium-based app gets it,
    /// and no posted event carries the wheel event's hardware record ("momentum began" least
    /// of all: with a record on it WebKit replaces the glide by its own). Seen on the
    /// owner's screen for Safari. Where the record does not come off (before macOS 27, a
    /// failed self-test): no phases at all, as with the switch off. An app where a wheel
    /// stays a wheel never gets phases.
    func testTheRealPath_overSafari_postsAFlickWithoutTheHardwareRecord() throws {
        try withSettings(switchOn: true) {
            if ScrollHardwareRecord.comesOff {
                let result = try oneClick(over: .safari)
                XCTAssertEqual(phaseRuns(result.frames), [
                    "began ×1", "changed ×1", "ended ×1", "momentumBegan ×1", "momentumChanged ×23", "momentumEnded ×1",
                ])
                XCTAssertTrue(result.frames.allSatisfy { $0.hasRecord == false }, "no event of it carries a record")
                XCTAssertEqual(result.frames.first { $0.name == "momentumBegan" }?.hasRecord, false)
                try assertOwnFields(result.frames)
                XCTAssertEqual(result.session?.flick, true)
            }
            let noRemoval = try oneClick(over: .safari, takesRecordOff: false)
            XCTAssertFalse(noRemoval.frames.contains { $0.hasPhase }, "the record does not come off: no phases")
            XCTAssertTrue(noRemoval.frames.allSatisfy { $0.timestamp == Self.wheelTime }, "the switch-off stream")
            XCTAssertEqual(noRemoval.session?.trackpadStyleWithheld, true)

            let listed = try oneClick(over: .plainScrolling)
            XCTAssertFalse(listed.frames.contains { $0.hasPhase })
        }
    }

    /// With the switch off Chrome gets an "ended" at every stop (from Mos: "only [4, 0] lets
    /// Chrome recover"). It is the one frame with a phase on that path, and it is written as
    /// it always was: the wheel event's time, line delta and scroll count. Nothing of
    /// "Trackpad-style scrolling" is on it.
    func testTheRealPath_switchOff_chromesEndedIsWhatItWas() throws {
        try withSettings(switchOn: false) {
            let result = try oneClick(over: .followsGlide, chrome: true)
            let last = try XCTUnwrap(result.frames.last)
            XCTAssertEqual(last.name, "ended")
            XCTAssertEqual(last.y, 0)
            XCTAssertFalse(result.frames.dropLast().contains { $0.hasPhase }, "no other frame has a phase")
            XCTAssertTrue(result.frames.allSatisfy { $0.timestamp == Self.wheelTime }, "the wheel event's time, on the \"ended\" too")
            XCTAssertTrue(result.frames.allSatisfy { $0.scrollCount == Self.wheelScrollCount && $0.lines == 1 }, "and its scroll count and line delta")
            XCTAssertEqual(result.asked, 0)

            let other = try oneClick(over: .followsGlide)
            XCTAssertFalse(other.frames.contains { $0.hasPhase }, "any other app: no \"ended\"")
        }
    }

    /// An app that keeps its own settings (the Apps pane): its own switch counts, not the
    /// Scrolling pane's. An app that uses the Scrolling pane's settings follows that one.
    func testTheRealPath_anAppsOwnSwitchCounts() throws {
        let own = Application(path: "/Applications/Editor.app")
        own.inherit = false

        own.scroll.smoothSimTrackpad = true
        try withSettings(switchOn: false, application: own) {
            let result = try oneClick(over: .followsGlide)
            XCTAssertTrue(result.frames.contains { $0.hasPhase }, "on for this app, off in the Scrolling pane")
            XCTAssertEqual(result.session?.flick, true)
        }
        own.scroll.smoothSimTrackpad = false
        try withSettings(switchOn: true, application: own) {
            let result = try oneClick(over: .followsGlide)
            XCTAssertFalse(result.frames.contains { $0.hasPhase }, "off for this app, on in the Scrolling pane")
            XCTAssertEqual(result.asked, 0)
        }
        own.inherit = true
        try withSettings(switchOn: true, application: own) {
            let result = try oneClick(over: .touchOnly)
            XCTAssertTrue(result.frames.contains { $0.hasPhase }, "the app uses the Scrolling pane's settings")
        }
    }

    // MARK: - The app's own display link class, on a real CVDisplayLink

    private final class FrameCounter {
        private var lock = os_unfair_lock_s()
        private var frames = 0
        func add() {
            os_unfair_lock_lock(&lock)
            frames += 1
            os_unfair_lock_unlock(&lock)
        }
        var count: Int {
            os_unfair_lock_lock(&lock)
            defer { os_unfair_lock_unlock(&lock) }
            return frames
        }
    }

    /// `ScrollCVDisplayLink` starts, runs and stops a real link. A link for the main display
    /// can be made while the display sleeps (one for the active displays cannot), so this
    /// runs then too: it is the one test of the real class in a run with the display off.
    func testTheRealLinkClassStartsRunsAndStops() throws {
        var made: CVDisplayLink?
        guard CVDisplayLinkCreateWithCGDisplay(CGMainDisplayID(), &made) == kCVReturnSuccess, let cvLink = made else {
            throw XCTSkip("no display link can be made here")
        }
        let counter = FrameCounter()
        CVDisplayLinkSetOutputCallback(cvLink, { _, _, _, _, _, context in
            if let context = context {
                Unmanaged<FrameCounter>.fromOpaque(context).takeUnretainedValue().add()
            }
            return kCVReturnSuccess
        }, Unmanaged.passUnretained(counter).toOpaque())
        let link = ScrollCVDisplayLink(cvLink)
        defer { link.stop() }

        XCTAssertFalse(link.isRunning)
        link.followDisplayUnderPointer()
        guard link.start() == kCVReturnSuccess else {
            throw XCTSkip("the display link cannot be started here")
        }
        XCTAssertTrue(link.isRunning)
        let deadline = Date().addingTimeInterval(3)
        while counter.count < 3 && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        XCTAssertGreaterThanOrEqual(counter.count, 3, "its callback gets the frames")
        XCTAssertGreaterThan(link.nominalHz, 1)

        link.stop()
        XCTAssertFalse(link.isRunning)
        let afterTheStop = counter.count
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertEqual(counter.count, afterTheStop, "no frame after the stop")
    }

    /// The link the app makes: for the active displays, or none with CoreVideo's result.
    func testTheRealLinkIsMadeForTheActiveDisplays_orNotAtAll() {
        let made = ScrollCVDisplayLink.make(output: { _, _, _, _, _, _ in kCVReturnSuccess })
        if let link = made.link {
            XCTAssertEqual(made.result, kCVReturnSuccess)
            XCTAssertFalse(link.isRunning, "made, not started")
        } else {
            XCTAssertNotEqual(made.result, kCVReturnSuccess, "the display is off: -6661")
        }
    }
}

// MARK: - A stand-in for the display

/// A display link that is none: it runs when started, and counts what was asked of it.
// MARK: - The hardware record of a frame

/// What the stand-in functions of `testASelfTestThatFails_keepsTheRecord` remember (a C
/// function pointer cannot capture).
private enum ScrollHardwareRecordStandIns {
    static var firstRead: CGEvent?
    static var attachedTo: CGEvent?
}

/// Offline: events are built and read, nothing is posted.
final class ScrollHardwareRecordTests: XCTestCase {

    /// On the macOS the removal was run on, the launch's self-test passes; on an older one
    /// it is not tried.
    func testThisMac_passesTheSelfTestOrDoesNotTry() {
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        if major >= ScrollHardwareRecord.testedFromMacOS {
            XCTAssertEqual(ScrollHardwareRecord.system.outcome, .comesOff)
            XCTAssertTrue(ScrollHardwareRecord.comesOff)
        } else {
            XCTAssertEqual(ScrollHardwareRecord.system.outcome, .notTried(macOS: major))
            XCTAssertFalse(ScrollHardwareRecord.comesOff)
        }
    }

    /// The record comes off a copy; the event it was copied from keeps its own (copies share
    /// one record object, so it is never changed in place).
    func testTheRecordComesOffACopyAndStaysOnTheOriginal() throws {
        try XCTSkipUnless(ScrollHardwareRecord.comesOff, "\(ScrollHardwareRecord.system.outcome)")
        let calls = try XCTUnwrap(ScrollHardwareRecord.readingCalls)
        let wheel = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0))
        XCTAssertEqual(ScrollHardwareRecord.isCarried(by: wheel), false, "a made event has none")
        let record = try XCTUnwrap(calls.createScroll(nil, mach_absolute_time(), 0, 1, 0, 0))
        calls.set(wheel, record)
        Unmanaged<AnyObject>.fromOpaque(record).release()
        let frame = try XCTUnwrap(wheel.copy())
        XCTAssertEqual(ScrollHardwareRecord.isCarried(by: frame), true, "a copy carries the record")

        ScrollHardwareRecord.remove(from: frame)
        XCTAssertEqual(ScrollHardwareRecord.isCarried(by: frame), false)
        XCTAssertEqual(ScrollHardwareRecord.isCarried(by: wheel), true, "the wheel event keeps its own")
        XCTAssertEqual(frame.getIntegerValueField(.scrollWheelEventDeltaAxis1), 1, "nothing else of the event changes")
        XCTAssertEqual(frame.timestamp, wheel.timestamp)
    }

    /// A macOS older than the one it was run on: nothing is looked up or called.
    func testAnOlderMacOS_isNotTried() {
        var looked = 0
        let found = ScrollHardwareRecord.prepare(macOSMajor: 26) {
            looked += 1
            return ScrollHardwareRecord.load()
        }
        XCTAssertEqual(found.outcome, .notTried(macOS: 26))
        XCTAssertNil(found.calls)
        XCTAssertEqual(looked, 0)
    }

    /// A function that is missing: named, and nothing is used.
    func testAMissingFunction_isNamed() {
        let loaded = ScrollHardwareRecord.load { library, name in
            name == "CGEventCopyIOHIDEvent" ? nil : ScrollHardwareRecord.systemResolver(library, name)
        }
        XCTAssertNil(loaded.calls)
        XCTAssertEqual(loaded.missing, "CGEventCopyIOHIDEvent")
        let found = ScrollHardwareRecord.prepare(macOSMajor: 27) { loaded }
        XCTAssertEqual(found.outcome, .missing("CGEventCopyIOHIDEvent"))
        XCTAssertNil(found.calls)
    }

    /// A step of the self-test that fails: the removal is not used. (A setter that does not
    /// take a record off, as an older macOS might: the record stays.)
    func testASelfTestThatFails_keepsTheRecord() throws {
        let real = try XCTUnwrap(ScrollHardwareRecord.load().calls)
        let ignoresNULL: ScrollHardwareRecord.SetRecord = { event, record in
            guard let record = record else { return }
            ScrollHardwareRecord.load().calls?.set(event, record)
        }
        let stays = ScrollHardwareRecord.Calls(set: ignoresNULL, copy: real.copy, createScroll: real.createScroll)
        XCTAssertEqual(ScrollHardwareRecord.check(stays), .failed("the record stayed on the event it was taken off"))
        let found = ScrollHardwareRecord.prepare(macOSMajor: 27) { (stays, nil) }
        XCTAssertNil(found.calls, "not used")

        let readsNothing: ScrollHardwareRecord.CopyRecord = { _ in nil }
        let blind = ScrollHardwareRecord.Calls(set: real.set, copy: readsNothing, createScroll: real.createScroll)
        XCTAssertEqual(ScrollHardwareRecord.check(blind), .failed("a record attached to an event could not be read back"))

        // A copy that does not carry the record of the event it was copied from: the
        // reader answers for the first event it is asked about, and for no other.
        ScrollHardwareRecordStandIns.firstRead = nil
        let readsTheOriginalOnly: ScrollHardwareRecord.CopyRecord = { event in
            if ScrollHardwareRecordStandIns.firstRead == nil { ScrollHardwareRecordStandIns.firstRead = event }
            guard ScrollHardwareRecordStandIns.firstRead === event else { return nil }
            return ScrollHardwareRecord.load().calls?.copy(event)
        }
        let notOnACopy = ScrollHardwareRecord.Calls(set: real.set, copy: readsTheOriginalOnly, createScroll: real.createScroll)
        XCTAssertEqual(ScrollHardwareRecord.check(notOnACopy), .failed("a copy of the event did not carry its record"))
        ScrollHardwareRecordStandIns.firstRead = nil

        // A setter that takes the record off the original too (it changes the shared
        // record in place): the step that guards "the wheel event keeps its own".
        ScrollHardwareRecordStandIns.attachedTo = nil
        let stripsTheOriginalToo: ScrollHardwareRecord.SetRecord = { event, record in
            guard let calls = ScrollHardwareRecord.load().calls else { return }
            if record != nil {
                ScrollHardwareRecordStandIns.attachedTo = event
                calls.set(event, record)
            } else {
                calls.set(event, nil)
                if let original = ScrollHardwareRecordStandIns.attachedTo { calls.set(original, nil) }
            }
        }
        let inPlace = ScrollHardwareRecord.Calls(set: stripsTheOriginalToo, copy: real.copy, createScroll: real.createScroll)
        XCTAssertEqual(ScrollHardwareRecord.check(inPlace), .failed("taking the record off a copy took it off the event it was copied from"))
        XCTAssertNil(ScrollHardwareRecord.prepare(macOSMajor: 27) { (inPlace, nil) }.calls, "not used")
        ScrollHardwareRecordStandIns.attachedTo = nil

        let makesNothing: ScrollHardwareRecord.CreateScrollRecord = { _, _, _, _, _, _ in nil }
        let empty = ScrollHardwareRecord.Calls(set: real.set, copy: real.copy, createScroll: makesNothing)
        XCTAssertEqual(ScrollHardwareRecord.check(empty), .failed("no hardware record could be made"))
    }

    /// The `app` log says once what the launch found; every outcome but a pass is a problem line.
    func testTheLaunchLine_saysWhatWasFound() {
        let passed = ScrollHardwareRecord.launchLine(.comesOff)
        XCTAssertFalse(passed.isProblem)
        XCTAssertTrue(passed.text.contains("is taken off every frame that carries phases"))
        for outcome in [ScrollHardwareRecord.Outcome.notTried(macOS: 15), .missing("SLEventSetIOHIDEvent"), .failed("a step")] {
            let line = ScrollHardwareRecord.launchLine(outcome)
            // Not tried on an older macOS is by design, no fault: a note. The other two are problems.
            XCTAssertEqual(line.isProblem, outcome != .notTried(macOS: 15), "\(outcome)")
            XCTAssertTrue(line.text.contains("keep the wheel event's hardware record, as before"), line.text)
            var notes: [String] = [], problems: [String] = []
            ScrollHardwareRecord.announce(outcome, note: { notes.append($0) }, problem: { problems.append($0) })
            XCTAssertEqual(notes, line.isProblem ? [] : [line.text], "\(outcome)")
            XCTAssertEqual(problems, line.isProblem ? [line.text] : [], "\(outcome)")
        }
        var notes: [String] = [], problems: [String] = []
        ScrollHardwareRecord.announce(.comesOff, note: { notes.append($0) }, problem: { problems.append($0) })
        XCTAssertEqual(notes, [passed.text])
        XCTAssertEqual(problems, [])
        XCTAssertTrue(ScrollHardwareRecord.launchLine(.notTried(macOS: 15)).text.contains("on macOS 15 it is not tried"))
        XCTAssertTrue(ScrollHardwareRecord.launchLine(.missing("SLEventSetIOHIDEvent")).text.contains("macOS has no SLEventSetIOHIDEvent here"))
        XCTAssertTrue(ScrollHardwareRecord.launchLine(.failed("a step")).text.contains("failed (a step)"))
    }
}

final class FakeScrollDisplayLink: ScrollDisplayLink {
    var isRunning = false
    var startResult: CVReturn = kCVReturnSuccess
    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var follows = 0
    var nominalHz = 60.0
    var followedDisplayHz = 60.0

    func start() -> CVReturn {
        starts += 1
        if startResult == kCVReturnSuccess { isRunning = true }
        return startResult
    }

    func stop() {
        stops += 1
        isRunning = false
    }

    func followDisplayUnderPointer() {
        follows += 1
    }
}

/// Makes the display links of a poster. `isOn` false: none can be made, as while the display
/// is off (CoreVideo's -6661).
final class FakeDisplay {
    var isOn = true
    /// What a link made from now on answers to `start()`.
    var startResult: CVReturn = kCVReturnSuccess
    private(set) var made: [FakeScrollDisplayLink] = []
    private(set) var tries = 0

    init(for poster: ScrollPoster) {
        // The poster keeps its display alive.
        poster.makeDisplayLink = { [self] in
            self.tries += 1
            guard self.isOn else { return (nil, -6661) }
            let link = FakeScrollDisplayLink()
            link.startResult = self.startResult
            self.made.append(link)
            return (link, kCVReturnSuccess)
        }
    }
}
