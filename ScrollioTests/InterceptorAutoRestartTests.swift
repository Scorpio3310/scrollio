import XCTest
@testable import Scrollio_Debug

/// Interceptor keeper 自动重启退避的纯函数测试.
/// 场景背景: 主线程被 TCC 权限弹窗阻塞时, active tap 被系统超时禁用后输入才恢复;
/// keeper 盲目重启会再次冻结输入, 形成用户点不到弹窗的自锁. 冷却窗口用于打破该循环.
final class InterceptorAutoRestartTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func secondsAgo(_ s: TimeInterval) -> Date {
        return now.addingTimeInterval(-s)
    }

    func testNotThrottled_whenHistoryEmpty() {
        XCTAssertFalse(Interceptor.isAutoRestartThrottled(history: [], now: now))
    }

    func testNotThrottled_belowLimitWithinWindow() {
        let history = [secondsAgo(10), secondsAgo(20)]
        XCTAssertFalse(Interceptor.isAutoRestartThrottled(history: history, now: now))
    }

    func testThrottled_atLimitWithinWindow() {
        let history = [secondsAgo(5), secondsAgo(15), secondsAgo(30)]
        XCTAssertTrue(Interceptor.isAutoRestartThrottled(history: history, now: now))
    }

    func testNotThrottled_whenOldEntriesFallOutOfWindow() {
        // 两条已滑出 60s 窗口, 窗口内只剩 1 条 → 放行
        let history = [
            secondsAgo(Interceptor.autoRestartWindow + 1),
            secondsAgo(Interceptor.autoRestartWindow + 30),
            secondsAgo(10),
        ]
        XCTAssertFalse(Interceptor.isAutoRestartThrottled(history: history, now: now))
    }

    func testThrottled_recoversAfterCoolDown() {
        // 冷却前: 3 条都在窗口内 → 拒绝
        let history = [secondsAgo(50), secondsAgo(55), secondsAgo(58)]
        XCTAssertTrue(Interceptor.isAutoRestartThrottled(history: history, now: now))
        // 冷却后: 同一批记录在 61s 后全部滑出窗口 → 恢复
        let later = now.addingTimeInterval(61)
        XCTAssertFalse(Interceptor.isAutoRestartThrottled(history: history, now: later))
    }

    // MARK: - Counting a restart (the keeper's and the one after a tap timeout)

    /// A tap the system turned off for a slow callback is restarted from the callback now,
    /// not at the keeper's next look; both count against the same limit, so a main thread
    /// that keeps timing out cannot freeze input again and again.
    func testRestartsAreAdmittedUpToTheLimitThenRefusedUntilTheWindowPasses() {
        var history: [Date] = []
        for second in 0..<Interceptor.autoRestartLimit {
            XCTAssertTrue(Interceptor.admitAutoRestart(history: &history, now: now.addingTimeInterval(Double(second))))
        }
        XCTAssertEqual(history.count, Interceptor.autoRestartLimit)

        let refusedAt = now.addingTimeInterval(10)
        XCTAssertFalse(Interceptor.admitAutoRestart(history: &history, now: refusedAt))
        XCTAssertEqual(history.count, Interceptor.autoRestartLimit, "a refused restart is not counted")

        // Once the first ones left the window, a restart is admitted and the old ones are gone.
        let later = now.addingTimeInterval(Interceptor.autoRestartWindow + 0.5)
        XCTAssertTrue(Interceptor.admitAutoRestart(history: &history, now: later))
        XCTAssertEqual(history, [now.addingTimeInterval(1), now.addingTimeInterval(2), later],
                       "the entry at 0 s left the window; those at 1 s and 2 s are still in it")
    }

    // MARK: - Keeper replacement

    /// start() and restart() install a new keeper timer. The one it replaces must be
    /// invalidated first, otherwise it stays scheduled and keeps restarting the tap.
    func testReplacingTheKeeperInvalidatesThePreviousTimer() {
        var keeper: Timer?
        let first = Timer(timeInterval: 60, repeats: true) { _ in }
        let second = Timer(timeInterval: 60, repeats: true) { _ in }

        Interceptor.replaceKeeper(&keeper, with: first)
        XCTAssertTrue(keeper === first)
        XCTAssertTrue(first.isValid)

        Interceptor.replaceKeeper(&keeper, with: second)
        XCTAssertTrue(keeper === second)
        XCTAssertFalse(first.isValid, "the replaced keeper must not keep firing")
        XCTAssertTrue(second.isValid)

        Interceptor.replaceKeeper(&keeper, with: nil)
        XCTAssertNil(keeper)
        XCTAssertFalse(second.isValid)
    }

    /// A scheduled keeper that was replaced never fires again.
    func testAReplacedScheduledKeeperDoesNotFire() {
        var keeper: Timer?
        var firstFired = false
        let secondFired = expectation(description: "the current keeper fires")

        Interceptor.replaceKeeper(&keeper, with: Timer.scheduledTimer(withTimeInterval: 0.01, repeats: false) { _ in
            firstFired = true
        })
        Interceptor.replaceKeeper(&keeper, with: Timer.scheduledTimer(withTimeInterval: 0.02, repeats: false) { _ in
            secondFired.fulfill()
        })

        wait(for: [secondFired], timeout: 2)
        XCTAssertFalse(firstFired)
        Interceptor.replaceKeeper(&keeper, with: nil)
    }

    // MARK: - Safety timers while a menu is open

    /// Runs the main run loop in `mode`, as an open menu (`.eventTracking`) or a modal panel
    /// (`.modalPanel`) does, until `done` or the timeout.
    private func runMainRunLoop(in mode: RunLoop.Mode, timeout: TimeInterval, until done: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !done() && Date() < deadline {
            _ = RunLoop.main.run(mode: mode, before: min(deadline, Date().addingTimeInterval(0.05)))
        }
    }

    private func isScheduled(_ timer: Timer, in mode: RunLoop.Mode) -> Bool {
        return CFRunLoopContainsTimer(
            CFRunLoopGetMain(),
            unsafeBitCast(timer, to: CFRunLoopTimer.self),
            CFRunLoopMode(mode.rawValue as CFString)
        )
    }

    /// The keeper of a tap used to wait while the status-bar menu was open: a tap macOS
    /// turned off meanwhile stayed off until the menu closed. A timer from the helper fires
    /// while a menu tracks and while a modal panel runs; a `Timer.scheduledTimer` does not.
    func testASafetyTimerFiresWhileAMenuIsOpen() {
        XCTAssertEqual(CommonModesTimer.mode, .common)
        for mode in [RunLoop.Mode.eventTracking, .modalPanel] {
            var safetyFired = false
            var plainFired = false
            let safety = CommonModesTimer.scheduled(withTimeInterval: 0.01, repeats: false) { _ in safetyFired = true }
            let plain = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: false) { _ in plainFired = true }

            XCTAssertTrue(isScheduled(safety, in: .default), mode.rawValue)
            XCTAssertTrue(isScheduled(safety, in: mode), mode.rawValue)
            XCTAssertFalse(isScheduled(plain, in: mode), mode.rawValue)

            runMainRunLoop(in: mode, timeout: 2) { safetyFired }
            XCTAssertTrue(safetyFired, mode.rawValue)
            XCTAssertFalse(plainFired, "\(mode.rawValue): a default-mode timer waits until the menu closes")
            safety.invalidate()
            plain.invalidate()
        }
    }

    /// The safety timers are made through the helper: the keeper and the restart of every
    /// event tap, the recovery of AppRunController, the keeper and the rate checks of the
    /// display link. None of them may go back to a default-mode `Timer.scheduledTimer`.
    func testTheSafetyTimersAreMadeThroughTheHelper() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()       // ScrollioTests/
            .deletingLastPathComponent()       // project root
        let expected: [(path: String, timers: Int)] = [
            ("Scrollio/Utils/Interceptor.swift", 2),
            ("Scrollio/Managers/AppRunController.swift", 1),
            ("Scrollio/ScrollCore/ScrollPoster.swift", 2),
        ]
        for file in expected {
            let source = try String(contentsOf: root.appendingPathComponent(file.path), encoding: .utf8)
            XCTAssertFalse(source.contains("Timer.scheduledTimer"), "\(file.path) makes a default-mode timer")
            XCTAssertEqual(source.components(separatedBy: "CommonModesTimer.scheduled(").count - 1, file.timers, file.path)
        }
    }
}

// MARK: - The app log of the event taps

/// The lines the event taps write to the system log (category `app`): which tap, why it was
/// turned off or restarted, and how often. Nothing here creates a tap.
final class EventTapLogTests: XCTestCase {

    private func mask(_ types: CGEventType...) -> CGEventMask {
        return types.reduce(CGEventMask(0)) { $0 | CGEventMask(1 << $1.rawValue) }
    }

    /// The taps are named by the events they listen to, as ScrollCore, ButtonCore and the
    /// gesture motion tap set them up.
    func testTheTapsAreNamedByTheirEvents() {
        let scrollCore = ScrollCore.shared
        XCTAssertEqual(EventTapKind.of(mask: scrollCore.scrollEventMask), .scroll)
        XCTAssertEqual(EventTapKind.of(mask: scrollCore.hotkeyEventMask), .scrollKeys)
        XCTAssertEqual(EventTapKind.of(mask: scrollCore.mouseLeftEventMask), .leftClick)
        XCTAssertEqual(EventTapKind.of(mask: ButtonCore.shared.dispatchEventMask), .buttons)
        XCTAssertEqual(EventTapKind.of(mask: ButtonCore.shared.keyEventMask), .keys)
        XCTAssertEqual(EventTapKind.of(mask: ButtonCore.shared.dispatchEventMask | ButtonCore.shared.keyEventMask), .buttonsAndKeys)
        // The recorder listens to the modifier keys too; it is not the scroll keys tap.
        XCTAssertEqual(EventTapKind.of(mask: mask(.leftMouseDown) | mask(.rightMouseDown) | mask(.otherMouseDown)
            | mask(.keyDown) | mask(.flagsChanged)), .recorder)
        XCTAssertEqual(EventTapKind.of(mask: MouseInteractionSessionController.motionEventMask), .pointerMovement)
        XCTAssertEqual(EventTapKind.of(mask: mask(.tabletPointer)), .other)
        XCTAssertEqual(EventTapKind.scroll.rawValue, "scroll")
        XCTAssertEqual(EventTapKind.buttonsAndKeys.rawValue, "buttons and keys")
        XCTAssertEqual(EventTapKind.pointerMovement.rawValue, "pointer movement")
    }

    /// Only a timeout is a problem. A tap that Scrollio switches off itself (Pause, sleep, a
    /// restart, the end of a gesture hold) tells its callback "disabled by user input":
    /// that is not logged. It used to be, as an error, right after every launch.
    func testATapSwitchedOffOnPurposeIsNoProblem() {
        XCTAssertEqual(EventTapDisableLog.problem(for: .tapDisabledByTimeout), .timeout)
        XCTAssertNil(EventTapDisableLog.problem(for: .tapDisabledByUserInput))
        XCTAssertNil(EventTapDisableLog.problem(for: .scrollWheel))
        XCTAssertNil(EventTapDisableLog.problem(for: .keyDown))
    }

    // MARK: Turned off by macOS: at most one line per tap every 10 s

    func testTheFirstTimeIsWrittenAtOnce() {
        var counter = EventTapDisableCounter()
        XCTAssertEqual(counter.note(.timeout, tap: .scroll, now: 100),
                       .log("macOS turned off the scroll event tap: timeout (Scrollio's main thread answered too slowly)"))
        var other = EventTapDisableCounter()
        XCTAssertEqual(other.note(.userInput, tap: .buttonsAndKeys, now: 100),
                       .log("macOS turned off the buttons and keys event tap: user input"))
    }

    func testTimesWithinTheIntervalAreCountedAndFlushedOnce() {
        var counter = EventTapDisableCounter()
        _ = counter.note(.timeout, tap: .scroll, now: 100)
        // The next ones come 2 s and 3 s later: one flush is scheduled, for 10 s after the line.
        XCTAssertEqual(counter.note(.timeout, tap: .scroll, now: 102), .flush(after: 8))
        XCTAssertEqual(counter.note(.userInput, tap: .scroll, now: 103), EventTapDisableCounter.Decision.none)
        XCTAssertEqual(counter.timeouts, 1)
        XCTAssertEqual(counter.userInputs, 1)

        XCTAssertEqual(counter.flush(tap: .scroll, now: 110), .log(
            "macOS turned off the scroll event tap 2 times since the last line: "
                + "1 timeout (Scrollio's main thread answered too slowly), 1 by user input"
        ))
        XCTAssertEqual(counter.timeouts, 0)
        // A second flush has nothing to say.
        XCTAssertEqual(counter.flush(tap: .scroll, now: 111), EventTapDisableCounter.Decision.none)
    }

    func testATimeAfterTheIntervalIsWrittenAtOnce() {
        var counter = EventTapDisableCounter()
        _ = counter.note(.timeout, tap: .scroll, now: 100)
        XCTAssertEqual(counter.note(.timeout, tap: .scroll, now: 110), .log(
            "macOS turned off the scroll event tap: timeout (Scrollio's main thread answered too slowly)"
        ))
    }

    /// A line written by a new time just before the scheduled flush: the flush must not write
    /// a second line within 10 s, it waits for the rest of the interval.
    func testAFlushNeverWritesWithinTheIntervalOfAnotherLine() {
        var counter = EventTapDisableCounter()
        _ = counter.note(.timeout, tap: .scroll, now: 100)
        XCTAssertEqual(counter.note(.timeout, tap: .scroll, now: 101), .flush(after: 9))
        // The flush is late; a time at 110 writes the line itself (2 times).
        guard case .log(let line) = counter.note(.timeout, tap: .scroll, now: 110) else {
            return XCTFail("a line is due at 110")
        }
        XCTAssertTrue(line.contains("2 times since the last line: 2 timeouts"), line)
        XCTAssertEqual(counter.note(.timeout, tap: .scroll, now: 111), EventTapDisableCounter.Decision.none,
                       "the flush from 101 is still scheduled")
        XCTAssertEqual(counter.flush(tap: .scroll, now: 112), .flush(after: 8))
        XCTAssertEqual(counter.flush(tap: .scroll, now: 120), .log(
            "macOS turned off the scroll event tap: timeout (Scrollio's main thread answered too slowly)"
        ))
    }

    func testOnlyTheTwoTurnedOffTypesAreCounted() {
        // Anything else is ignored before a counter is touched; this must not log or crash.
        EventTapDisableLog.note(.scroll, .scrollWheel)
        EventTapDisableLog.note(.buttonsAndKeys, .otherMouseDown)
    }

    // MARK: Restarts and their throttle

    func testRestartAndThrottleLines() {
        XCTAssertEqual(
            Interceptor.restartLine(kind: .scroll, cause: .timeout, restartsInWindow: 2),
            "Restarting the scroll event tap: macOS turned it off after a timeout (restart 2 of 3 allowed within 60 s)"
        )
        XCTAssertEqual(
            Interceptor.restartLine(kind: .buttonsAndKeys, cause: .foundOff, restartsInWindow: 1),
            "Restarting the buttons and keys event tap: the keeper found it off (restart 1 of 3 allowed within 60 s)"
        )
        XCTAssertEqual(
            Interceptor.throttledLine(kind: .scroll),
            "Not restarting the scroll event tap: it was restarted 3 times within 60 s. It stays off until that "
                + "time has passed, so input stays usable; the keeper tries again every 5 s"
        )
    }

    /// The status item asks whether any tap is throttled; the set changes only once per tap.
    func testTheThrottledTapsAreCountedOncePerTap() {
        var taps = Interceptor.ThrottledTaps()
        let first = ObjectIdentifier(NSObject.self)
        let second = ObjectIdentifier(NSString.self)
        XCTAssertTrue(taps.isEmpty)
        XCTAssertTrue(taps.set(true, for: first))
        XCTAssertFalse(taps.set(true, for: first), "no second change for the same tap")
        XCTAssertTrue(taps.set(true, for: second))
        XCTAssertTrue(taps.set(false, for: first))
        XCTAssertFalse(taps.isEmpty)
        XCTAssertFalse(taps.set(false, for: first))
        XCTAssertTrue(taps.set(false, for: second))
        XCTAssertTrue(taps.isEmpty)
    }
}
