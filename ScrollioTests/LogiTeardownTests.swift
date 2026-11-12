import XCTest
@testable import Scrollio_Debug

/// Which Logitech interfaces get a session (`LogiSessionManager.shouldAttachSession`).
/// These three tests were the whole of "LogiTeardownTests" and test nothing of teardown.
final class LogiSessionAttachTests: XCTestCase {

    // MARK: - Keyboard interface skip (issue #948)

    /// A Logitech keyboard interface must NOT get a session attached. Attaching
    /// one registers an input-report callback that keeps the keyboard's HID
    /// endpoint active, so it never sleeps and its backlight stays on (#948).
    /// `shouldAttachSession` gates session creation in `deviceConnected`.
    func test_shouldAttachSession_skipsKeyboardInterface() {
        // Generic Desktop (0x0001) Keyboard (0x0006) — e.g. MX Mechanical.
        XCTAssertFalse(
            LogiSessionManager.shouldAttachSession(usagePage: 0x0001, usage: 0x0006),
            "Keyboard interfaces must be skipped so the device can sleep / dim its backlight"
        )
    }

    func test_shouldAttachSession_attachesMouseAndHIDPPInterfaces() {
        // Generic Desktop Mouse (0x0002) — BLE HID++ candidate.
        XCTAssertTrue(LogiSessionManager.shouldAttachSession(usagePage: 0x0001, usage: 0x0002))
        // Vendor-specific HID++ interfaces (USB receiver / Bolt / Unifying).
        XCTAssertTrue(LogiSessionManager.shouldAttachSession(usagePage: 0xFF00, usage: 0x0000))
        XCTAssertTrue(LogiSessionManager.shouldAttachSession(usagePage: 0xFF43, usage: 0x0000))
        XCTAssertTrue(LogiSessionManager.shouldAttachSession(usagePage: 0xFFC0, usage: 0x0000))
        // Consumer Control interface some Logi devices also expose.
        XCTAssertTrue(LogiSessionManager.shouldAttachSession(usagePage: 0x000C, usage: 0x0001))
    }

    /// Regression guard: the skip must be keyboard-specific, not a blanket drop
    /// of the whole Generic Desktop usage page (which would also drop BLE mice).
    func test_shouldAttachSession_doesNotBlanketDropGenericDesktop() {
        // Generic Desktop Pointer (0x0001) must still attach.
        XCTAssertTrue(LogiSessionManager.shouldAttachSession(usagePage: 0x0001, usage: 0x0001),
                      "Pointer (Generic Desktop) must still attach")
    }
}

/// What ends the Logitech sessions when the process is ended from outside. (The give-back
/// itself, the synthetic `.up` that teardown, setTargetSlot, rediscoverFeatures and
/// LogiCenter.stop send before clearing per-session state, needs a LogiDeviceSession,
/// which needs a real IOHIDDevice: the rules of what is given back are
/// LogiDivertReconciliationTests', the rest is the real-device test LogiBridgeDeviceTests'.)
final class LogiTeardownTests: XCTestCase {

    // MARK: - Ending Scrollio with a signal

    /// `kill` and `killall Scrollio` end a process without applicationWillTerminate, so the
    /// mice kept their buttons diverted. A watched signal asks for the ordinary quit on the
    /// main thread; when the process is still there after the grace time, the last resort
    /// runs (in the app: the signal's default action). Tried with SIGUSR2, not SIGTERM.
    func testAWatchedSignalAsksForTheOrdinaryQuitAndThenTheLastResort() {
        let watcher = LogiTerminationSignal()
        let quit = expectation(description: "the ordinary quit is asked for")
        let lastResort = expectation(description: "the last resort after the grace time")
        var lastResortSignal: Int32?
        watcher.install(
            signal: SIGUSR2,
            grace: 0.2,
            graceful: {
                XCTAssertTrue(Thread.isMainThread)
                quit.fulfill()
            },
            lastResort: { number in
                lastResortSignal = number
                lastResort.fulfill()
            }
        )
        addTeardownBlock { watcher.uninstall() }
        XCTAssertTrue(watcher.isInstalled)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            kill(getpid(), SIGUSR2)
        }
        wait(for: [quit, lastResort], timeout: 10, enforceOrder: true)
        XCTAssertEqual(lastResortSignal, SIGUSR2)
    }

    func testTheTestHostDoesNotWatchSIGTERM() {
        XCTAssertFalse(LogiTerminationSignal.shared.isInstalled, "under XCTest LogiCenter.start() installs nothing")
        XCTAssertEqual(LogiTerminationSignal.defaultGrace, 4, "longer than the 2 s the give-back waits for a mouse")
    }
}
