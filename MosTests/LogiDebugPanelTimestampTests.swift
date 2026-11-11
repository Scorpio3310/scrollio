import XCTest
@testable import Mos_Debug

/// The HID++ debug log stamps every report. The stamp comes from one shared formatter
/// (creating a DateFormatter per report was the expensive part); its format must not change.
final class LogiDebugPanelTimestampTests: XCTestCase {

    func testTimestampKeepsTheLogFormat() {
        let date = Date(timeIntervalSince1970: 1_700_000_000.123)
        let reference = DateFormatter()
        reference.dateFormat = "HH:mm:ss.SSS"

        XCTAssertEqual(LogiDebugPanel.timestamp(for: date), reference.string(from: date))
    }

    func testTimestampShape() throws {
        let stamp = LogiDebugPanel.timestamp()
        let pattern = try NSRegularExpression(pattern: "^\\d{2}:\\d{2}:\\d{2}\\.\\d{3}$")
        let range = NSRange(location: 0, length: stamp.utf16.count)
        XCTAssertNotNil(pattern.firstMatch(in: stamp, range: range), stamp)
    }

    /// The shared formatter is read from the main thread and from background work alike.
    func testTimestampIsStableUnderConcurrentUse() {
        let date = Date(timeIntervalSince1970: 1_700_000_000.5)
        let expected = LogiDebugPanel.timestamp(for: date)
        let lock = NSLock()
        var mismatches = 0

        DispatchQueue.concurrentPerform(iterations: 200) { _ in
            if LogiDebugPanel.timestamp(for: date) != expected {
                lock.lock()
                mismatches += 1
                lock.unlock()
            }
        }
        XCTAssertEqual(mismatches, 0)
    }
}
