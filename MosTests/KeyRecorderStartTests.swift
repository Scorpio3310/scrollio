import XCTest
@testable import Mos_Debug

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
}
