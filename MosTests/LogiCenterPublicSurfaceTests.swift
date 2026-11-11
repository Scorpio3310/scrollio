import XCTest
@testable import Mos_Debug

final class LogiCenterPublicSurfaceTests: XCTestCase {

    func testIsLogiCode_known() {
        XCTAssertTrue(LogiCenter.shared.isLogiCode(1006))   // Back
        XCTAssertFalse(LogiCenter.shared.isLogiCode(42))    // arbitrary non-Logi
    }

    func testNameForMosCode_known() {
        let name = LogiCenter.shared.name(forMosCode: 1006)
        XCTAssertNotNil(name)
        XCTAssertFalse(name!.isEmpty)
    }

    /// The MX Master 4's haptic sense panel (CID 0x01A0) is the thumb panel; the gesture
    /// button of the MX Master 3 / 3S (0x00C3) stays the gesture button.
    func testControlRole_thumbPanel() {
        XCTAssertEqual(LogiControlRole(cid: 0x01A0), .thumbPanel)
        XCTAssertEqual(LogiCenter.shared.controlRole(forMosCode: 2000 + 0x01A0), .thumbPanel)
        XCTAssertEqual(LogiControlRole(cid: 0x00C3), .gesture)
        XCTAssertEqual(LogiCenter.shared.controlRole(forMosCode: 1000), .gesture)
        XCTAssertNil(LogiControlRole(cid: 0x01A3), "another control of the MX Master 4 has no role")
    }

    func testActiveSessionsSnapshot_returnsArray() {
        let snapshot = LogiCenter.shared.activeSessionsSnapshot()
        // No assumption about content; just that the call succeeds.
        XCTAssertNotNil(snapshot)
    }

    func testNotificationNamesNonEmpty() {
        XCTAssertFalse(LogiCenter.sessionChanged.rawValue.isEmpty)
        XCTAssertFalse(LogiCenter.discoveryStateChanged.rawValue.isEmpty)
        XCTAssertFalse(LogiCenter.reportingDidComplete.rawValue.isEmpty)
        XCTAssertFalse(LogiCenter.activityChanged.rawValue.isEmpty)
        XCTAssertFalse(LogiCenter.conflictChanged.rawValue.isEmpty)
        XCTAssertFalse(LogiCenter.rawButtonEvent.rawValue.isEmpty)
        XCTAssertFalse(LogiCenter.buttonEventRelay.rawValue.isEmpty)
    }
}
