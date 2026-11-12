import XCTest
@testable import Scrollio_Debug

final class LogiCIDDirectoryTests: XCTestCase {

    /// For each known fixed-ScrollioCode CID, toCID(toScrollioCode(cid)) must round-trip.
    func testRoundTrip_fixedMappings() {
        let fixedPairs: [(cid: UInt16, scrollioCode: UInt16)] = [
            (0x0050, 1003),  // Left
            (0x0051, 1004),  // Right
            (0x0052, 1005),  // Middle
            (0x0053, 1006),  // Back
            (0x0056, 1007),  // Forward
            (0x00C3, 1000),  // Mouse Gesture
            (0x00C4, 1001),  // Smart Shift
            (0x00D7, 1002),  // Virtual Gesture
        ]
        for pair in fixedPairs {
            XCTAssertEqual(LogiCIDDirectory.toScrollioCode(pair.cid), pair.scrollioCode,
                           "CID 0x\(String(pair.cid, radix: 16)) should map to ScrollioCode \(pair.scrollioCode)")
            XCTAssertEqual(LogiCIDDirectory.toCID(pair.scrollioCode), pair.cid,
                           "ScrollioCode \(pair.scrollioCode) should map back to CID 0x\(String(pair.cid, radix: 16))")
        }
    }

    func testGenericFallback_2000PlusCID() {
        // CIDs not in the fixed table use the formula 2000 + CID.
        let cid: UInt16 = 0x1001  // G1 button
        XCTAssertEqual(LogiCIDDirectory.toScrollioCode(cid), 2000 + cid)
    }

    func testIsLogitechCode_threshold() {
        // Scrollio's convention: any code >= 1000 is treated as a Logi code.
        XCTAssertFalse(LogiCIDDirectory.isLogitechCode(999))
        XCTAssertTrue(LogiCIDDirectory.isLogitechCode(1000))
        XCTAssertTrue(LogiCIDDirectory.isLogitechCode(1006))   // Back
        XCTAssertTrue(LogiCIDDirectory.isLogitechCode(3001))   // generic 2000 + 0x1001
    }

    func testNativeMouseButtonCanMapBackToCID() {
        XCTAssertEqual(LogiCIDDirectory.cid(forNativeMouseButton: 3), 0x0053)
        XCTAssertEqual(LogiCIDDirectory.cid(forNativeMouseButton: 4), 0x0056)
        XCTAssertNil(LogiCIDDirectory.cid(forNativeMouseButton: 8))
    }
}
