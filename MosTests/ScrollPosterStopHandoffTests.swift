import XCTest
@testable import Mos_Debug

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

    private func input(_ y: Double, momentum: ScrollMomentumSettings? = nil) -> ScrollPosterInput {
        let trans = OPTIONS_SCROLL_DEFAULT.generateDurationTransition(with: 3.13)
        return ScrollPosterInput(
            y: y, x: 0, notch: (y: abs(y), x: 0), duration: trans,
            bypassFilter: ScrollMotion.shouldBypassFilter(freeSpinBlend: 0),
            momentum: momentum
        )
    }

    private func wheel(_ y: Double, momentum: ScrollMomentumSettings? = nil) {
        poster.inputForTests(input(y, momentum: momentum), at: now)
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

    func testOnlyOneRequestIsMadePerWheelInput_classic() throws {
        wheel(40)
        _ = try XCTUnwrap(runUntilStopRequest())
        XCTAssertTrue(runFrames(30).isEmpty)
    }

    /// In precise mode every frame of a finished motion finds it finished again.
    func testOnlyOneRequestIsMadePerWheelInput_precise() throws {
        wheel(40, momentum: .default)
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
        // (A classic gesture does not post the frames under the dead zone: the last few pixels stay unsent.)
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
