import XCTest
@testable import Scrollio_Debug

final class LogiConflictDetectorTests: XCTestCase {

    private let cid: UInt16 = 0x0053

    func testNotQueried_unknown() {
        let s = LogiConflictDetector.status(reportingFlags: 0, targetCID: 0, cid: cid, reportingQueried: false, scrollioOwnsDivert: false)
        XCTAssertEqual(s, .unknown)
    }

    func testForeignDivert_flagsNonZero_notScrollio() {
        let s = LogiConflictDetector.status(reportingFlags: 0x01, targetCID: 0, cid: cid, reportingQueried: true, scrollioOwnsDivert: false)
        XCTAssertEqual(s, .foreignDivert)
        XCTAssertTrue(s.isConflict)
    }

    func testScrollioOwned_pureNoForeign() {
        let s = LogiConflictDetector.status(
            reportingFlags: 0,      // no foreign bit
            targetCID: 0,
            cid: cid,
            reportingQueried: true,
            scrollioOwnsDivert: true     // Scrollio owns it cleanly
        )
        XCTAssertEqual(s, .scrollioOwned)
        XCTAssertFalse(s.isConflict)
    }

    func testScrollioOwned_whenTemporaryDivertIsActiveAndScrollioOwnsIt() {
        let s = LogiConflictDetector.status(
            reportingFlags: 0x01,   // tmpDivert is expected after Scrollio owns divert
            targetCID: 0,
            cid: cid,
            reportingQueried: true,
            scrollioOwnsDivert: true
        )
        XCTAssertEqual(s, .scrollioOwned)
        XCTAssertFalse(s.isConflict)
    }

    func testRemapped_targetDiffers() {
        let s = LogiConflictDetector.status(reportingFlags: 0, targetCID: 0x0050, cid: cid, reportingQueried: true, scrollioOwnsDivert: false)
        XCTAssertEqual(s, .remapped)
        XCTAssertTrue(s.isConflict)
    }

    func testForeignBeatsRemap_whenBothPresent() {
        let s = LogiConflictDetector.status(reportingFlags: 0x01, targetCID: 0x0050, cid: cid, reportingQueried: true, scrollioOwnsDivert: false)
        XCTAssertEqual(s, .foreignDivert, "Foreign divert takes precedence over remap when both present")
    }

    func testClear_allZero() {
        let s = LogiConflictDetector.status(reportingFlags: 0, targetCID: 0, cid: cid, reportingQueried: true, scrollioOwnsDivert: false)
        XCTAssertEqual(s, .clear)
        XCTAssertFalse(s.isConflict)
    }

    func testSelfRemap_isClear() {
        let s = LogiConflictDetector.status(reportingFlags: 0, targetCID: cid, cid: cid, reportingQueried: true, scrollioOwnsDivert: false)
        XCTAssertEqual(s, .clear)
    }
}
