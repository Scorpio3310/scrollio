import XCTest
@testable import Scrollio_Debug

/// Tier 3a — real-device bridge round-trip.
/// Validates rawButtonEvent fires when a real Logi button is pressed.
/// Interactive: tester must press the Back button within the timeout window.
/// Default timeout is short so the test SKIPS gracefully in unattended runs.
final class LogiBridgeDeviceTests: LogiDeviceIntegrationBase {

    /// Interactive test: requires a press of the Back button within 30 seconds.
    /// It waits and validates only when asked to, with
    /// `TEST_RUNNER_LOGI_INTERACTIVE_PRESS=1 xcodebuild … -testPlan DebugWithDevice …`
    /// (xcodebuild hands a variable to the tests only with that prefix, and strips it);
    /// otherwise it skips, so unattended runs of the device plan do not hang.
    func testRealButtonPressTriggersRawEvent() throws {
        let interactive = ProcessInfo.processInfo.environment["LOGI_INTERACTIVE_PRESS"] == "1"
        try XCTSkipUnless(interactive, "set TEST_RUNNER_LOGI_INTERACTIVE_PRESS=1 on the xcodebuild command line and press the Back button when prompted")

        // Ensure the bridge is wired (controller's AppDelegate did this for the
        // app process, but tests run in a separate executable — install here).
        if !(LogiCenter.shared.externalBridge is LogiIntegrationBridge) {
            LogiCenter.shared.installBridge(LogiIntegrationBridge.shared)
        }
        LogiCenter.shared.start()

        print("[LogiBridgeDeviceTests] Press the Back button on your Logi device within 30 seconds...")
        let exp = expectation(forNotification: LogiCenter.rawButtonEvent, object: nil) { notif in
            return (notif.userInfo?["scrollioCode"] as? UInt16) == 1006
        }
        let result = XCTWaiter.wait(for: [exp], timeout: 30)
        XCTAssertEqual(result, .completed, "rawButtonEvent for Back (scrollioCode 1006) was not observed within 30s")
    }
}
