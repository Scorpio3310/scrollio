import XCTest
@testable import Mos_Debug

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
}
