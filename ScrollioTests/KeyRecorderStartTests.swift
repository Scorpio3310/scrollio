import XCTest
@testable import Scrollio_Debug

/// Starting a recording without an event tap (no Accessibility access). The tap is created
/// first now: before, the prompt opened, the delegate heard "started" and every Logitech
/// button was diverted for recording, and since no stop followed, the Logitech recording never
/// ended: every diverted button stayed swallowed (also after reconnecting) until the app quit.
final class KeyRecorderStartTests: XCTestCase {

    private final class Delegate: KeyRecorderDelegate {
        var log: [String] = []
        func onRecordingStarted(_ recorder: KeyRecorder) { log.append("started") }
        func onEventRecorded(_ recorder: KeyRecorder, didRecordEvent event: InputEvent, isDuplicate: Bool) {
            log.append("recorded")
        }
        func onRecordingStopped(_ recorder: KeyRecorder, didRecord: Bool) { log.append("stopped \(didRecord)") }
    }

    func testWithoutAnEventTapNothingStartsAndNoLogitechButtonIsDivertedForRecording() {
        XCTAssertFalse(LogiCenter.shared.isRecording)
        let recorder = KeyRecorder()
        let delegate = Delegate()
        recorder.delegate = delegate
        recorder.hasAccess = { false }
        recorder.makePopover = { Self.quietNotice() }
        var attempts = 0
        recorder.makeEventTap = { _, _ in
            attempts += 1
            throw Interceptor.InterceptorError.eventTapCreationFailed
        }
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 24, height: 22))

        recorder.startRecording(from: anchor, mode: .combination)
        // The Logitech recording used to begin on the next turn of the main queue.
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(delegate.log, ["stopped false"], "the caller hears that nothing was recorded, nothing else")
        XCTAssertFalse(LogiCenter.shared.isRecording, "no Logitech button stays diverted for a recording that never ran")

        // Not stuck: the next click tries again.
        recorder.startRecording(from: anchor, mode: .adaptive)
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(delegate.log, ["stopped false", "stopped false"])
    }

    /// A popover for a notice: it says nothing to VoiceOver. (The anchors of these tests
    /// have no window, so no popover opens on screen.)
    private static func quietNotice() -> KeyPopover {
        let popover = KeyPopover()
        popover.announce = { _ in }
        return popover
    }

    /// Without Accessibility access every recorder did nothing and said nothing: "+", a
    /// row's "Keyboard Shortcut…", "Record a Button…" of Gestures and Shortcut Ring, "Set
    /// Up…" (QA B6, X7). Its popover now opens at the control to say why, in the words of
    /// General's status row and with the way to General; it records nothing, and the
    /// caller still hears that nothing was recorded. Where the access is there and the tap
    /// still could not be made, it says that the recording could not start.
    func testWithoutAccessThePopoverSaysSoInsteadOfNothing() throws {
        let recorder = KeyRecorder()
        let delegate = Delegate()
        var popovers: [KeyPopover] = []
        var said: [String] = []
        var access = false
        recorder.delegate = delegate
        recorder.hasAccess = { access }
        recorder.makePopover = {
            let popover = KeyPopover()
            popover.announce = { said.append($0) }
            popovers.append(popover)
            return popover
        }
        recorder.makeEventTap = { _, _ in throw Interceptor.InterceptorError.eventTapCreationFailed }
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 24, height: 22))

        recorder.startRecording(from: anchor, mode: .combination)
        XCTAssertEqual(delegate.log, ["stopped false"])
        let notice = try XCTUnwrap(popovers.last)
        XCTAssertTrue(notice.isShowingNotice)
        XCTAssertEqual(notice.testingWaitingText, "Scrollio needs Accessibility access")
        XCTAssertEqual(notice.testingWaitingText, NSLocalizedString("status-menu-title-needs-access", comment: ""), "General's and the menu bar's words")
        XCTAssertEqual(notice.testingHintText, "Allow it under General.")
        XCTAssertTrue(notice.testingHintIsVisible)
        XCTAssertTrue(notice.testingWaitingIsVisible)
        XCTAssertTrue(notice.keyPreview.isHidden, "no key slot: nothing is recorded")
        XCTAssertEqual(said, ["Scrollio needs Accessibility access. Allow it under General."], "VoiceOver hears it")
        // The two lines under each other, and no room kept for the key slot.
        let rows = notice.testingRowFrames
        XCTAssertGreaterThan(rows[0].minY, rows[2].maxY, "the small line under the title")
        let asking = KeyPopover()
        asking.testingPrepareContent()
        XCTAssertLessThan(
            try XCTUnwrap(notice.testingContentView).fittingSize.height,
            try XCTUnwrap(asking.testingContentView).fittingSize.height - 10
        )
        asking.hide()
        XCTAssertNotNil(notice.testingBehavior, "it stays until it is closed")
        XCTAssertFalse(LogiCenter.shared.isRecording)

        // The access is there, the tap still could not be made.
        access = true
        recorder.startRecording(from: anchor, mode: .adaptive)
        XCTAssertEqual(delegate.log, ["stopped false", "stopped false"])
        XCTAssertNil(notice.testingBehavior, "the next try closes the notice before it")
        let second = try XCTUnwrap(popovers.last)
        XCTAssertFalse(second === notice)
        XCTAssertEqual(second.testingWaitingText, "Recording couldn't start")
        XCTAssertEqual(second.testingHintText, "Try again in a moment.")

        // A recording that starts shows the recorder, not the notice.
        let tap = FakeTap()
        let recording = QuietPopover()
        recorder.makePopover = { recording }
        recorder.makeEventTap = { _, _ in tap }
        recorder.startRecording(from: anchor, mode: .combination)
        XCTAssertEqual(delegate.log, ["stopped false", "stopped false", "started"])
        XCTAssertFalse(recording.isShowingNotice)
        XCTAssertEqual(recording.testingWaitingText, KeyRecordingMode.combination.waitingHint)
        XCTAssertFalse(recording.keyPreview.isHidden)
        recorder.stopRecording()
        spin(KeyRecorder.restartDelay + 0.1)
    }

    /// The recording tap skips Scrollio's own events (a key or click it posts while the
    /// recorder is open). It swallowed them, although the comment said "skip".
    func testTheRecordingTapLetsScrolliosOwnEventsThrough() throws {
        let recorder = KeyRecorder()
        var callback: CGEventTapCallBack?
        recorder.hasAccess = { false }
        recorder.makePopover = { Self.quietNotice() }
        recorder.makeEventTap = { _, tapCallback in
            callback = tapCallback
            throw Interceptor.InterceptorError.eventTapCreationFailed
        }
        recorder.startRecording(from: NSView(frame: NSRect(x: 0, y: 0, width: 24, height: 22)), mode: .combination)
        let recordingCallback = try XCTUnwrap(callback)
        let proxy = CGEventTapProxy(bitPattern: 1)!

        let own = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: true))
        own.setIntegerValueField(.eventSourceUserData, value: ScrollioEventMarker.syntheticCustom)
        let passed = recordingCallback(proxy, .keyDown, own, nil)
        XCTAssertTrue(passed?.takeUnretainedValue() === own, "let through unchanged")

        // The user's own key is still taken by the recording (handed on, swallowed). The
        // hand-off goes nowhere: no recording runs.
        let users = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: true))
        XCTAssertNil(recordingCallback(proxy, .keyDown, users, nil))
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    // MARK: - A recording that runs (a double for the tap, a popover that is never shown)

    private final class FakeTap: KeyRecordingTap {
        private(set) var stops = 0
        func stop() { stops += 1 }
    }

    /// Builds its content and never opens a window.
    private final class QuietPopover: KeyPopover {
        override func show(at sourceView: NSView, waitingHint: String) {
            announce = { _ in }
            testingPrepareContent(waitingHint: waitingHint)
        }
    }

    private struct Recording {
        let recorder: KeyRecorder
        let delegate: Delegate
        let tap: FakeTap
        let popover: QuietPopover
        let callback: CGEventTapCallBack
    }

    private func startRecording(
        mode: KeyRecordingMode = .combination,
        secureInput: @escaping () -> Bool = { false },
        paused: @escaping () -> Bool = { false },
        timeout: TimeInterval = KeyRecorder().timeout
    ) throws -> Recording {
        let recorder = KeyRecorder()
        let delegate = Delegate()
        let tap = FakeTap()
        let popover = QuietPopover()
        var callback: CGEventTapCallBack?
        recorder.delegate = delegate
        recorder.timeout = timeout
        recorder.isSecureInputOn = secureInput
        recorder.isPaused = paused
        recorder.makePopover = { popover }
        recorder.makeEventTap = { _, tapCallback in
            callback = tapCallback
            return tap
        }
        recorder.startRecording(from: NSView(frame: NSRect(x: 0, y: 0, width: 24, height: 22)), mode: mode)
        addTeardownBlock { [weak self] in
            recorder.stopRecording()
            // Past the moment the recorder counts as stopped, and any Logitech recording ended.
            self?.spin(KeyRecorder.restartDelay + 0.1)
        }
        return Recording(recorder: recorder, delegate: delegate, tap: tap, popover: popover, callback: try XCTUnwrap(callback))
    }

    private func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private func record(_ event: InputEvent) {
        NotificationCenter.default.post(name: KeyRecorder.FINISH_NOTI_NAME, object: event)
    }

    private let f5 = InputEvent(type: .keyboard, code: KeyCode.F5, modifiers: [], phase: .down, source: .hidPP, device: nil)

    /// The timeout, the popover closing and Esc can all end a recording within the half
    /// second it still counts as running: the delegate heard "stopped" twice and the
    /// Logitech recording was ended twice.
    func testASecondStopDoesNothing() throws {
        let recording = try startRecording()
        XCTAssertEqual(recording.delegate.log, ["started"])
        recording.recorder.stopRecording()
        recording.recorder.stopRecording()
        NotificationCenter.default.post(name: KeyRecorder.CANCEL_NOTI_NAME, object: nil)
        XCTAssertEqual(recording.delegate.log, ["started", "stopped false"])
        XCTAssertEqual(recording.tap.stops, 1)
        // A key that arrives after the stop is not recorded.
        record(f5)
        XCTAssertEqual(recording.delegate.log, ["started", "stopped false"])
        spin(KeyRecorder.restartDelay + 0.1)
        XCTAssertFalse(LogiCenter.shared.isRecording)
    }

    /// After a key was recorded the timeout kept running: a key recorded shortly before it
    /// ended the recording twice (once by the timeout, once after the feedback).
    func testTheTimeoutIsOverOnceAKeyWasRecorded() throws {
        let recording = try startRecording(timeout: 0.4)
        spin(0.1)
        record(f5)
        XCTAssertEqual(recording.delegate.log, ["started", "recorded"])
        // Past the timeout (0.4 s) and the feedback (0.7 s after the key).
        spin(1.2)
        XCTAssertEqual(recording.delegate.log, ["started", "recorded", "stopped true"], "stopped once, after the feedback")
        XCTAssertEqual(recording.tap.stops, 1)
    }

    func testARecordingWithoutAKeyStillTimesOut() throws {
        let recording = try startRecording(timeout: 0.2)
        spin(0.5)
        XCTAssertEqual(recording.delegate.log, ["started", "stopped false"])
        XCTAssertEqual(recording.tap.stops, 1)
    }

    /// The popover is transient: it closes when the settings window stops being the key
    /// window. The recording went on then, and its tap swallows every key and click of the
    /// whole Mac.
    func testTheRecordingEndsWhenItsPopoverClosesOrTheAppGoesToTheBackground() throws {
        let recording = try startRecording()
        // Some other popover closes: nothing.
        NotificationCenter.default.post(name: NSPopover.didCloseNotification, object: NSPopover())
        spin(0.05)
        XCTAssertEqual(recording.delegate.log, ["started"])
        // Its own: the system popover whose content holds the recorder's key slot.
        let system = NSPopover()
        system.contentViewController = NSViewController()
        system.contentViewController?.view = try XCTUnwrap(recording.popover.testingContentView)
        XCTAssertTrue(KeyRecorder.isPopover(system, of: recording.popover))
        XCTAssertFalse(KeyRecorder.isPopover(NSPopover(), of: recording.popover))
        NotificationCenter.default.post(name: NSPopover.didCloseNotification, object: system)
        spin(0.05)
        XCTAssertEqual(recording.delegate.log, ["started", "stopped false"])
        XCTAssertEqual(recording.tap.stops, 1)

        let second = try startRecording()
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        spin(0.05)
        XCTAssertEqual(second.delegate.log, ["started", "stopped false"])
        XCTAssertEqual(second.tap.stops, 1)
    }

    /// A left click without a modifier can never be recorded. It was swallowed and the
    /// popover shook, for up to 10 s: now it cancels like Esc and goes on to what was clicked.
    func testAPlainLeftClickCancelsAndGoesOnToWhatWasClicked() throws {
        XCTAssertTrue(KeyRecorder.isCancelClick(type: .leftMouseDown, flags: []))
        XCTAssertTrue(KeyRecorder.isCancelClick(type: .leftMouseDown, flags: .maskSecondaryFn), "Fn is no modifier here")
        XCTAssertFalse(KeyRecorder.isCancelClick(type: .leftMouseDown, flags: .maskAlternate))
        XCTAssertFalse(KeyRecorder.isCancelClick(type: .rightMouseDown, flags: []))
        XCTAssertFalse(KeyRecorder.isCancelClick(type: .otherMouseDown, flags: []))
        XCTAssertFalse(KeyRecorder.isCancelClick(type: .keyDown, flags: []))

        let recording = try startRecording()
        let proxy = CGEventTapProxy(bitPattern: 1)!
        func click(_ type: CGEventType, _ button: CGMouseButton, _ flags: CGEventFlags = []) throws -> CGEvent {
            let event = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: .zero, mouseButton: button))
            event.flags = flags
            return event
        }
        // A left click with a modifier and a right click are still swallowed, refused, and
        // the popover says why.
        XCTAssertNil(recording.callback(proxy, .leftMouseDown, try click(.leftMouseDown, .left, .maskAlternate), nil))
        spin(0.05)
        XCTAssertEqual(recording.delegate.log, ["started"])
        XCTAssertEqual(recording.popover.testingHintText, NSLocalizedString("key-recorder-left-right-refused", comment: ""))
        XCTAssertNil(recording.callback(proxy, .rightMouseDown, try click(.rightMouseDown, .right), nil))
        spin(0.05)
        XCTAssertEqual(recording.delegate.log, ["started"])

        // The plain left click: passed on, and the recording ends.
        let plain = try click(.leftMouseDown, .left)
        XCTAssertTrue(recording.callback(proxy, .leftMouseDown, plain, nil)?.takeUnretainedValue() === plain)
        spin(0.05)
        XCTAssertEqual(recording.delegate.log, ["started", "stopped false"])
    }

    /// While Scrollio is paused its Logitech part is stopped: no button is diverted for the
    /// recording, so the buttons only Scrollio reads from a Logitech mouse (the gesture
    /// button, the thumb panel) never arrive, and the recorder waited them out without a
    /// word (QA B6, X7). Its small line says so now, in two lines at most; a key or a
    /// standard button is recorded as ever, and "Press Esc to cancel" is back once
    /// Scrollio is resumed. Secure keyboard entry, which stops every key, is said first.
    func testThePopoverSaysWhenScrollioIsPaused() throws {
        var paused = true
        let recording = try startRecording(paused: { paused })
        let pausedText = NSLocalizedString("key-recorder-paused", comment: "")
        XCTAssertEqual(pausedText, "Scrollio is paused:\nsome Logitech buttons cannot be recorded now")
        XCTAssertEqual(recording.popover.testingHintText, pausedText)
        XCTAssertTrue(recording.popover.testingHintIsVisible)
        let oneLine = NSTextField(labelWithString: "Xg")
        oneLine.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        XCTAssertLessThanOrEqual(recording.popover.testingRowFrames[2].height, 2 * oneLine.fittingSize.height + 1, "two lines")

        paused = false
        spin(1.3)
        XCTAssertEqual(recording.popover.testingHintText, NSLocalizedString("Press ESC to cancel recording", comment: ""))
        record(f5)
        XCTAssertEqual(recording.delegate.log, ["started", "recorded"], "a key is recorded as ever")

        let both = try startRecording(secureInput: { true }, paused: { true })
        XCTAssertEqual(both.popover.testingHintText, NSLocalizedString("key-recorder-secure-input", comment: ""))
        let neither = try startRecording()
        XCTAssertEqual(neither.popover.testingHintText, NSLocalizedString("Press ESC to cancel recording", comment: ""))
    }

    /// While another app has secure keyboard entry on, no key reaches any tap: the popover
    /// says so instead of waiting silently, and goes back to "Press Esc to cancel" after.
    func testThePopoverSaysWhenKeysCannotArrive() throws {
        var secure = true
        let recording = try startRecording(secureInput: { secure })
        let secureText = NSLocalizedString("key-recorder-secure-input", comment: "")
        XCTAssertNotEqual(secureText, "key-recorder-secure-input")
        XCTAssertEqual(recording.popover.testingHintText, secureText)

        secure = false
        spin(1.3)
        XCTAssertEqual(recording.popover.testingHintText,
                       NSLocalizedString("Press ESC to cancel recording", comment: ""))

        let quiet = try startRecording()
        XCTAssertEqual(quiet.popover.testingHintText, NSLocalizedString("Press ESC to cancel recording", comment: ""))
    }
}
