import XCTest
@testable import Scrollio_Debug

/// Interceptor keeper 自动重启退避的纯函数测试.
/// 场景背景: 主线程被 TCC 权限弹窗阻塞时, active tap 被系统超时禁用后输入才恢复;
/// keeper 盲目重启会再次冻结输入, 形成用户点不到弹窗的自锁. 冷却窗口用于打破该循环.
final class InterceptorAutoRestartTests: XCTestCase {

    /// Seconds on the throttle's clock (`Interceptor.monotonicNow`), not a date.
    private let now: TimeInterval = 1_000_000

    private func secondsAgo(_ s: TimeInterval) -> TimeInterval {
        return now - s
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
        let later = now + 61
        XCTAssertFalse(Interceptor.isAutoRestartThrottled(history: history, now: later))
    }

    // MARK: - Counting a restart (the keeper's and the one after a tap timeout)

    /// A tap the system turned off for a slow callback is restarted from the callback now,
    /// not at the keeper's next look; both count against the same limit, so a main thread
    /// that keeps timing out cannot freeze input again and again.
    func testRestartsAreAdmittedUpToTheLimitThenRefusedUntilTheWindowPasses() {
        var history: [TimeInterval] = []
        for second in 0..<Interceptor.autoRestartLimit {
            XCTAssertTrue(Interceptor.admitAutoRestart(history: &history, now: now + Double(second)))
        }
        XCTAssertEqual(history.count, Interceptor.autoRestartLimit)

        let refusedAt = now + 10
        XCTAssertFalse(Interceptor.admitAutoRestart(history: &history, now: refusedAt))
        XCTAssertEqual(history.count, Interceptor.autoRestartLimit, "a refused restart is not counted")

        // Once the first ones left the window, a restart is admitted and the old ones are gone.
        let later = now + Interceptor.autoRestartWindow + 0.5
        XCTAssertTrue(Interceptor.admitAutoRestart(history: &history, now: later))
        XCTAssertEqual(history, [now + 1, now + 2, later],
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

    // MARK: - An Interceptor without a real tap (FakeEventTapSystem)

    /// Counts the "Accessibility access lost" notifications while it lives.
    private final class AccessLostCounter {
        private(set) var count = 0
        private var observer: NSObjectProtocol?

        init() {
            observer = NotificationCenter.default.addObserver(forName: .scrollioAccessibilityPermissionLost, object: nil, queue: nil) { [weak self] _ in
                self?.count += 1
            }
        }

        deinit {
            if let observer = observer { NotificationCenter.default.removeObserver(observer) }
        }
    }

    /// `start()` checks the Accessibility access before it switches the tap on: an active
    /// tap of an app without access swallows the events it listens to.
    func testATapIsNotSwitchedOnWithoutAccessibilityAccess() {
        let system = FakeEventTapSystem()
        system.isTrusted = false
        let lost = AccessLostCounter()
        XCTAssertThrowsError(try system.makeInterceptor()) { error in
            XCTAssertEqual(error as? Interceptor.InterceptorError, .eventTapEnableFailed)
        }
        XCTAssertEqual(system.created, 1, "the tap was made")
        XCTAssertFalse(system.switches.contains(true), "and never switched on")
        XCTAssertEqual(lost.count, 1, "the app hears that the access is missing")
    }

    func testATapThatCannotBeMadeThrows() {
        let system = FakeEventTapSystem()
        system.canCreate = false
        XCTAssertThrowsError(try system.makeInterceptor()) { error in
            XCTAssertEqual(error as? Interceptor.InterceptorError, .eventTapCreationFailed)
        }
        XCTAssertEqual(system.switches, [])
    }

    func testStartSwitchesTheTapOnAndStopSwitchesItOff() throws {
        let system = FakeEventTapSystem()
        let interceptor = try system.makeInterceptor()
        XCTAssertTrue(interceptor.isRunning())
        XCTAssertEqual(system.switches, [true])

        interceptor.stop()
        XCTAssertFalse(interceptor.isRunning())
        XCTAssertEqual(system.switches.last, false)
    }

    /// The keeper finds the access gone: the tap is switched off at once, its owner cleans
    /// up, and the app is told. No restart.
    func testTheKeeperSwitchesTheTapOffWhenTheAccessIsGone() throws {
        let system = FakeEventTapSystem()
        let interceptor = try system.makeInterceptor()
        var cleanedUp = 0
        interceptor.onRestart = { cleanedUp += 1 }

        system.isTrusted = false
        let lost = AccessLostCounter()
        interceptor.keeperLook()

        XCTAssertFalse(interceptor.isRunning())
        XCTAssertEqual(cleanedUp, 1)
        XCTAssertEqual(lost.count, 1)
        XCTAssertFalse(interceptor.restartsThrottled)
    }

    /// The keeper finds the tap off (macOS turned it off): it is restarted, which switches
    /// it on again `restartDelay` later.
    func testTheKeeperRestartsATapItFindsOff() throws {
        let system = FakeEventTapSystem()
        let interceptor = try system.makeInterceptor()
        var cleanedUp = 0
        interceptor.onRestart = { cleanedUp += 1 }
        interceptor.keeperLook()
        XCTAssertEqual(cleanedUp, 0, "a tap that runs is left alone")

        system.turnOffAsMacOSDoes()
        XCTAssertFalse(interceptor.isRunning())
        interceptor.keeperLook()

        XCTAssertEqual(cleanedUp, 1, "the owner cleans up")
        XCTAssertFalse(interceptor.isRunning(), "off until the restart's timer fires")
        runMainRunLoop(in: .default, timeout: 3) { interceptor.isRunning() }
        XCTAssertTrue(interceptor.isRunning(), "on again")
        interceptor.stop()
    }

    /// The restart throttle holds: after `autoRestartLimit` restarts within the window the
    /// next one is refused, the tap stays off and the app knows a tap is off.
    func testRestartsBeyondTheLimitAreRefusedAndTheTapStaysOff() throws {
        let system = FakeEventTapSystem()
        let interceptor = try system.makeInterceptor()
        var cleanedUp = 0
        interceptor.onRestart = { cleanedUp += 1 }
        for _ in 0..<Interceptor.autoRestartLimit {
            XCTAssertTrue(interceptor.restartUnlessThrottled())
        }
        XCTAssertEqual(cleanedUp, Interceptor.autoRestartLimit)
        XCTAssertFalse(interceptor.restartsThrottled)
        let switchesBefore = system.switches.count

        XCTAssertFalse(interceptor.restartUnlessThrottled(), "the fourth within a minute")
        XCTAssertFalse(interceptor.restartUnlessThrottled(after: .foundOff))

        XCTAssertTrue(interceptor.restartsThrottled)
        XCTAssertTrue(Interceptor.hasThrottledTap)
        XCTAssertEqual(cleanedUp, Interceptor.autoRestartLimit, "a refused restart does nothing")
        XCTAssertEqual(system.switches.count, switchesBefore, "and touches no tap")

        // Stopped on purpose: off because it should be, not because its restarts are refused.
        interceptor.stop()
        XCTAssertFalse(interceptor.restartsThrottled)
        XCTAssertFalse(Interceptor.hasThrottledTap)
    }

    /// A restart whose owner says "no more" (`shouldRestart`) leaves the tap off.
    func testARestartTheOwnerRefusesLeavesTheTapOff() throws {
        let system = FakeEventTapSystem()
        let interceptor = try system.makeInterceptor()
        interceptor.shouldRestart = { false }
        interceptor.restart()
        runMainRunLoop(in: .default, timeout: Interceptor.restartDelay + 0.3) { false }
        XCTAssertFalse(interceptor.isRunning())
    }

    /// The throttle's clock is never the wall clock: set back, that kept a throttled tap off
    /// for as long as it was set back.
    func testTheThrottlesClockOnlyGoesForward() {
        let first = Interceptor.monotonicNow()
        let second = Interceptor.monotonicNow()
        XCTAssertGreaterThanOrEqual(second, first)
        XCTAssertEqual(first, ProcessInfo.processInfo.systemUptime, accuracy: 1)
        XCTAssertLessThan(first, Date().timeIntervalSinceReferenceDate / 2, "seconds since the Mac started, not a date")
    }
}

// MARK: - A stand-in for the system calls of an event tap

/// Lets a test make an `Interceptor` without a real event tap and without Accessibility
/// access: the "tap" is a plain Mach port that listens to nothing, "enabled" a flag.
final class FakeEventTapSystem {
    var isTrusted = true
    var canCreate = true
    private(set) var created = 0
    private(set) var isOn = false
    /// Every `enable` call, in order (true: switched on).
    private(set) var switches: [Bool] = []

    var system: EventTapSystem {
        return EventTapSystem(
            create: { [self] _, _, _, _, _ in
                guard canCreate else { return nil }
                created += 1
                return CFMachPortCreate(kCFAllocatorDefault, { _, _, _, _ in }, nil, nil)
            },
            enable: { [self] _, enable in
                isOn = enable
                switches.append(enable)
            },
            isEnabled: { [self] _ in isOn },
            isTrusted: { [self] in isTrusted }
        )
    }

    /// macOS turned the tap off (a timeout): no `enable` call of ours.
    func turnOffAsMacOSDoes() {
        isOn = false
    }

    /// An Interceptor on this system. Its callback lets every event through unless one is given.
    func makeInterceptor(mask: CGEventMask = CGEventMask(1 << CGEventType.scrollWheel.rawValue),
                         callback: @escaping CGEventTapCallBack = { _, _, event, _ in Unmanaged.passUnretained(event) },
                         options: CGEventTapOptions = .listenOnly) throws -> Interceptor {
        return try Interceptor(
            event: mask,
            handleBy: callback,
            listenOn: .cgAnnotatedSessionEventTap,
            placeAt: .tailAppendEventTap,
            for: options,
            system: system
        )
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
