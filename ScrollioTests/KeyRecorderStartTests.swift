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

    /// The recording tap skips Scrollio's own events (a key or click it posts while the
    /// recorder is open). It swallowed them, although the comment said "skip".
    func testTheRecordingTapLetsScrolliosOwnEventsThrough() throws {
        let recorder = KeyRecorder()
        var callback: CGEventTapCallBack?
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
}
