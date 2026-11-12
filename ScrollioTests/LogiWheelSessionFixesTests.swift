import XCTest
@testable import Scrollio_Debug

/// Session-level fixes shipped with the wheel work: request encoding (function ids),
/// feature probing, error routing, and recording-mode divert re-assertion.
final class LogiWheelSessionFixesTests: XCTestCase {

    // MARK: - HID++ request encoding

    func testLongRequest_functionNibbleAndSoftwareId() {
        let fn1 = LogiDeviceSession.hidppLongRequest(deviceIndex: 0xFF, featureIndex: 0x0E, functionId: 1, params: [0x02, 0x10, 0x32])
        XCTAssertEqual(fn1?.count, 20)
        XCTAssertEqual(fn1?[0], 0x11)
        XCTAssertEqual(fn1?[1], 0xFF)
        XCTAssertEqual(fn1?[2], 0x0E)
        XCTAssertEqual(fn1?[3], 0x11, "fn1 | swid 1")
        XCTAssertEqual(Array(fn1?[4...6] ?? []), [0x02, 0x10, 0x32])

        let fn2 = LogiDeviceSession.hidppLongRequest(deviceIndex: 0x02, featureIndex: 0x0E, functionId: 2, params: [])
        XCTAssertEqual(fn2?[1], 0x02)
        XCTAssertEqual(fn2?[3], 0x21)
    }

    func testLongRequest_rejectsPreShiftedFunctionIds() {
        // 0x10 / 0x20 used to be passed as "function 1/2" and overflowed to fn0 on the wire
        XCTAssertNil(LogiDeviceSession.hidppLongRequest(deviceIndex: 0xFF, featureIndex: 0x0F, functionId: 0x10, params: []))
        XCTAssertNil(LogiDeviceSession.hidppLongRequest(deviceIndex: 0xFF, featureIndex: 0x0F, functionId: 0x20, params: []))
        XCTAssertNotNil(LogiDeviceSession.hidppLongRequest(deviceIndex: 0xFF, featureIndex: 0x0F, functionId: 0x0F, params: []))
    }

    func testLongRequest_truncatesParamsToSixteenBytes() {
        let report = LogiDeviceSession.hidppLongRequest(deviceIndex: 0xFF, featureIndex: 0x01, functionId: 0, params: Array(repeating: 0xAB, count: 20))
        XCTAssertEqual(report?.count, 20)
        XCTAssertEqual(report?.last, 0xAB)
    }

    // MARK: - Feature probing

    func testOptionalProbe_includesBothWheelFeaturesAndHiResWheel() {
        let probe = LogiDeviceSession.optionalProbeFeaturesForTests
        XCTAssertTrue(probe.contains(0x2111))
        XCTAssertTrue(probe.contains(0x2110), "MX Master 3S exposes only 0x2110")
        XCTAssertTrue(probe.contains(0x2121), "ratchetSwitch events need the HiResWheel index")
        XCTAssertEqual(Set(probe).count, probe.count, "each feature probed once")
    }

    // MARK: - Error routing

    func testOnlyIRootErrorsCancelFeatureDiscovery() {
        XCTAssertTrue(LogiFeatureDiscoveryQueue.errorRefusesGetFeature(originalFeatureIndex: 0x00, originalFunctionByte: 0x01, softwareId: 0x01))
        XCTAssertFalse(LogiFeatureDiscoveryQueue.errorRefusesGetFeature(originalFeatureIndex: 0x0E, originalFunctionByte: 0x21, softwareId: 0x01),
                       "a rejected wheel SetState must not abort an in-flight getFeature")
    }

    // MARK: - GetControlInfo duplicates

    func testDuplicateControlInfoDetection() {
        XCTAssertTrue(LogiDeviceSession.isDuplicateControlInfo(cid: 0x00C4, known: [0x0050, 0x00C4]))
        XCTAssertFalse(LogiDeviceSession.isDuplicateControlInfo(cid: 0x00C4, known: [0x0050, 0x0051]))
        XCTAssertFalse(LogiDeviceSession.isDuplicateControlInfo(cid: 0x0000, known: [0x0000]))
    }

    // MARK: - Recording re-assert

    func testRecordingPlan_reassertsAlreadyAppliedControls() {
        // 0x00C4 (mode-shift button) is in lastApplied but the device may have dropped it
        let plan = LogiDeviceSession.recordingDivertPlanForTests(
            divertableCIDs: [0x00C3, 0x00C4],
            lastApplied: [0x00C4],
            transport: .bleDirect,
            policy: LogiButtonDeliveryPolicy(standardMouseButtonsUseNativeEvents: true)
        )
        XCTAssertEqual(plan.toDivert, [0x00C3])
        XCTAssertEqual(plan.toAssert, [0x00C3, 0x00C4])
    }

    func testRecordingPlan_reassertNeverIncludesNativeFirstButtons() {
        let plan = LogiDeviceSession.recordingDivertPlanForTests(
            divertableCIDs: [0x0053, 0x00C4],
            lastApplied: [0x0053, 0x00C4],
            transport: .bleDirect,
            policy: LogiButtonDeliveryPolicy(standardMouseButtonsUseNativeEvents: true)
        )
        XCTAssertEqual(plan.toAssert, [0x00C4])
        XCTAssertEqual(plan.toUndivert, [0x0053])
    }
}
