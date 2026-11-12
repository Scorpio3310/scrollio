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
        XCTAssertEqual(after.first?.scroll, 4, "the touch got its \"ended\" first")
        XCTAssertGreaterThan(after.count, 3)
        XCTAssertTrue(after.dropFirst().allSatisfy { $0.scroll == 0 && $0.momentum == 0 }, "then frames without phases: \(after)")
        XCTAssertEqual(poster.sessionLogForTests.inputs, 1, "a scroll of its own")
        XCTAssertEqual(poster.motionStateForTests.buffer.y, 211.68, accuracy: 1e-9)
        XCTAssertEqual(display.made.last?.isRunning, true, "the display link runs for it")
        poster.stop()
    }

    /// B2: `stop()` returns only after its closing frames went out. A finger begins to
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
        XCTAssertEqual(phases.last, 4, "the closing \"ended\" is out when stop() returns: \(phases)")
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

    // MARK: - The real path with "Trackpad-style scrolling" on

    /// One frame as it would be posted: what the app reads on the event.
    private struct PostedFrame {
        var scroll: Double
        var momentum: Double
        var y: Int64
        var timestamp: UInt64
        var pid: pid_t
        var isContinuous: Int64
        var name: String { return ScrollClassicRig.phaseName(scroll: scroll, momentum: momentum) }
        var hasPhase: Bool { return scroll != 0 || momentum != 0 }
    }

    /// The wheel event's own time, and where the clock of the frames' own times starts.
    private static let wheelTime: UInt64 = 1_000_000_000
    private static let firstFrameTime: UInt64 = 5_000_000_000

    /// The default click: every frame that moves the page, with the switch off (pinned by
    /// `ScrollClassicPathTests.testTheDefaultClick_isWhatItWas`). No form changes it.
    private static let defaultClick: [Int64] = [
        7, 13, 15, 16, 16, 16, 15, 14, 12, 11, 10, 9, 8, 7, 6, 5, 5, 4, 3, 3, 2, 2, 2, 2, 1, 1,
    ]

    /// One click of the wheel as the scroll tap hands it over: a CGEvent with a target through
    /// `smooth(event:input:)`, the switch read from the settings (the caller sets them), the
    /// app's kind as given, display frames until the scroll has ended by itself. Returns the
    /// events that would be posted, the scroll's log entry, and how often the kind was asked.
    private func oneClick(over kind: ScrollUtils.TrackpadStyleTarget,
                          file: StaticString = #filePath, line: UInt = #line) throws -> (frames: [PostedFrame], session: ScrollSystemLog.Session?, asked: Int) {
        let context = ScrollDispatchContext()
        let poster = ScrollPoster(phases: ScrollPhase(), dispatchContext: context)
        var asked = 0
        poster.trackpadStyleTarget = { _ in
            asked += 1
            return kind
        }
        _ = FakeDisplay(for: poster)
        var clock = Self.firstFrameTime
        poster.eventClockForTests = {
            clock += 16_000_000
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
                isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous)
            ))
            lock.unlock()
        }
        var sessions: [ScrollSystemLog.Session] = []
        ScrollSystemLog.sessionObserverForTests = { session, _ in sessions.append(session) }
        defer { ScrollSystemLog.sessionObserverForTests = nil }

        let wheel = try wheelEvent(targetPID: 4242)
        wheel.timestamp = Self.wheelTime
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
                "began ×1", "changed ×2", "ended ×1", "momentumBegan ×1", "momentumChanged ×23", "momentumEnded ×1",
            ])
            let times = result.frames.map(\.timestamp)
            XCTAssertTrue(times.allSatisfy { $0 > Self.firstFrameTime }, "every frame its own time")
            XCTAssertEqual(times, times.sorted())
            XCTAssertEqual(Set(times).count, times.count, "no two frames the same time")
            XCTAssertEqual(result.asked, 1, "the app's kind is asked once per wheel event")
            XCTAssertEqual(result.session?.trackpadStyle, true)
            XCTAssertEqual(result.session?.flick, true)
            XCTAssertEqual(result.session?.touches, 1)
        }
    }

    /// Over any other app (AppKit, a web view, an app that is not known): one long touch, and
    /// its glide after the wheel has been still for 0.18 s. Every frame keeps the wheel
    /// event's time.
    func testTheRealPath_overAnyOtherApp_postsTheLongTouchWithTheWheelEventsTime() throws {
        try withSettings(switchOn: true) {
            let result = try oneClick(over: .touchOnly)
            XCTAssertEqual(phaseRuns(result.frames), [
                "began ×1", "changed ×10", "ended ×1", "momentumBegan ×1", "momentumChanged ×15", "momentumEnded ×1",
            ])
            XCTAssertTrue(result.frames.allSatisfy { $0.timestamp == Self.wheelTime }, "the wheel event's time on every frame")
            XCTAssertEqual(result.frames.filter { $0.scroll == 2 }.reduce(0) { $0 + $1.y }, 135, "what the touch carries of the 205 px")
            XCTAssertEqual(result.session?.trackpadStyle, true)
            XCTAssertEqual(result.session?.flick, false)
        }
    }

    /// Over Safari: no phase on any posted event and the wheel event's time, exactly the
    /// switch-off stream; the log says the switch is on but nothing was sent to this app.
    func testTheRealPath_overSafari_postsNoPhases() throws {
        try withSettings(switchOn: true) {
            let result = try oneClick(over: .plainScrolling)
            XCTAssertFalse(result.frames.contains { $0.hasPhase })
            XCTAssertTrue(result.frames.allSatisfy { $0.timestamp == Self.wheelTime })
            XCTAssertEqual(result.session?.trackpadStyle, false)
            XCTAssertEqual(result.session?.trackpadStyleWithheld, true)
        }
        // The same stream with the switch off, and then the app's kind is not even asked.
        try withSettings(switchOn: false) {
            let off = try oneClick(over: .followsGlide)
            XCTAssertFalse(off.frames.contains { $0.hasPhase })
            XCTAssertTrue(off.frames.allSatisfy { $0.timestamp == Self.wheelTime })
            XCTAssertEqual(off.asked, 0, "asked only while the switch is on")
            XCTAssertEqual(off.session?.trackpadStyle, false)
            XCTAssertEqual(off.session?.trackpadStyleWithheld, false)
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
