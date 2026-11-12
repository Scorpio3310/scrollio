import XCTest
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
    /// way then repeats a stop on an idle session, which must change and post nothing.
    func testARequestAfterADirectStopIsHarmless() throws {
        poster.setConfigForTests(simTrackpadEnabled: true)
        wheel(40)
        let request = try XCTUnwrap(runUntilStopRequest())
        poster.stop()
        let framesAfterDirectStop = frames.count

        XCTAssertTrue(poster.performRequestedStop(request))
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
            XCTAssertFalse(CVDisplayLinkIsRunning(replaced), "the replaced link is stopped")
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
           CVDisplayLinkStart(link) != kCVReturnSuccess {
            throw XCTSkip("the display link cannot be started here")
        }
        XCTAssertTrue(startedByTheWheelEvent)
    }
}
