import XCTest
@testable import Scrollio_Debug

final class LogiCenterPublicSurfaceTests: XCTestCase {

    func testIsLogiCode_known() {
        XCTAssertTrue(LogiCenter.shared.isLogiCode(1006))   // Back
        XCTAssertFalse(LogiCenter.shared.isLogiCode(42))    // arbitrary non-Logi
    }

    func testNameForScrollioCode_known() {
        let name = LogiCenter.shared.name(forScrollioCode: 1006)
        XCTAssertNotNil(name)
        XCTAssertFalse(name!.isEmpty)
    }

    /// The MX Master 4's haptic sense panel (CID 0x01A0) is the thumb panel; the gesture
    /// button of the MX Master 3 / 3S (0x00C3) stays the gesture button.
    func testControlRole_thumbPanel() {
        XCTAssertEqual(LogiControlRole(cid: 0x01A0), .thumbPanel)
        XCTAssertEqual(LogiCenter.shared.controlRole(forScrollioCode: 2000 + 0x01A0), .thumbPanel)
        XCTAssertEqual(LogiControlRole(cid: 0x00C3), .gesture)
        XCTAssertEqual(LogiCenter.shared.controlRole(forScrollioCode: 1000), .gesture)
        XCTAssertNil(LogiControlRole(cid: 0x01A3), "another control of the MX Master 4 has no role")
    }

    /// The button on the top of the MX Vertical (CID 0x00FD, Logitech's "DPI switch") is the
    /// pointer speed button: a control of its own, which no standard button stands for. No
    /// mouse drawn so far has it, so it lights nothing yet; the pane calls it as it did
    /// before it had a role. Another control about the pointer speed (0x00ED) has no role.
    func testControlRole_pointerSpeed() {
        let code: UInt16 = 2000 + 0x00FD
        XCTAssertEqual(LogiControlRole(cid: 0x00FD), .pointerSpeed)
        XCTAssertEqual(LogiCenter.shared.controlRole(forScrollioCode: code), .pointerSpeed)
        XCTAssertEqual(LogiCenter.shared.scrollioCode(for: .pointerSpeed), code)
        XCTAssertNil(LogiCenter.shared.nativeMouseButton(forScrollioCode: code))
        XCTAssertNil(LogiControlRole(cid: 0x00ED))

        let trigger = RecordedEvent(type: .mouse, code: code, modifiers: 0, deviceFilter: nil)
        XCTAssertEqual(ButtonsMousePart.part(for: trigger), .pointerSpeed)
        XCTAssertEqual(ButtonsMousePart.pointerSpeed.logitechRole, .pointerSpeed)
        XCTAssertEqual(ButtonTriggerNaming.buttonName(code: code), "Pointer speed button")
        // It is not a place a numbered button can be said to be: the Mac never reports it
        // by a number, so "Which Button Is This?" does not offer it and no stored value is new.
        XCTAssertNil(PlacedMousePart(role: .pointerSpeed))
        XCTAssertNil(PlacedMousePart.known(for: trigger))
        for mouse in [MouseArtworkModel.mxMaster4, .mxMaster3, .generic] {
            XCTAssertFalse(mouse.has(.pointerSpeed), "\(mouse)")
            XCTAssertEqual(ButtonTriggerPicture.make(for: trigger, mouse: mouse), .mouse(part: nil, number: nil, notDrawn: .pointerSpeed), "\(mouse)")
        }
    }

    /// The code of the control of each role: the one its role is read from, so the two agree.
    func testScrollioCodeForRole_isTheControlOfThatRole() {
        let roles: [LogiControlRole] = [.middle, .back, .forward, .gesture, .modeShift, .thumbPanel]
        XCTAssertEqual(roles.map { LogiCenter.shared.scrollioCode(for: $0) }, [1005, 1006, 1007, 1000, 1001, 2000 + 0x01A0])
        for role in roles {
            XCTAssertEqual(LogiCenter.shared.controlRole(forScrollioCode: LogiCenter.shared.scrollioCode(for: role)), role)
        }
        // The standard ones stand for the standard middle, back and forward buttons.
        XCTAssertEqual([LogiControlRole.middle, .back, .forward].map { LogiCenter.shared.nativeMouseButton(forScrollioCode: LogiCenter.shared.scrollioCode(for: $0)) },
                       [2, 3, 4])
    }

    func testActiveSessionsSnapshot_returnsArray() {
        let snapshot = LogiCenter.shared.activeSessionsSnapshot()
        // No assumption about content; just that the call succeeds.
        XCTAssertNotNil(snapshot)
    }

    func testNotificationNamesNonEmpty() {
        XCTAssertFalse(LogiCenter.sessionChanged.rawValue.isEmpty)
        XCTAssertFalse(LogiCenter.reportingDidComplete.rawValue.isEmpty)
        XCTAssertFalse(LogiCenter.activityChanged.rawValue.isEmpty)
        XCTAssertFalse(LogiCenter.conflictChanged.rawValue.isEmpty)
        XCTAssertFalse(LogiCenter.rawButtonEvent.rawValue.isEmpty)
        XCTAssertFalse(LogiCenter.buttonEventRelay.rawValue.isEmpty)
    }
}
