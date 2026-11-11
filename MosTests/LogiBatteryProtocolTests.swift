import XCTest
@testable import Mos_Debug

/// Battery byte layouts (0x1004 Unified Battery, 0x1000 Battery Status) on fake bytes.
final class LogiBatteryProtocolTests: XCTestCase {

    private func report(_ featureIndex: UInt8, _ functionByte: UInt8, _ payload: [UInt8]) -> [UInt8] {
        var bytes: [UInt8] = [0x11, 0xFF, featureIndex, functionByte] + payload
        while bytes.count < 20 { bytes.append(0) }
        return bytes
    }

    // MARK: - Function numbers

    func testStatusFunctionDiffersBetweenTheTwoFeatures() {
        XCTAssertEqual(LogiBatteryFeature.unified.statusFunction, 1, "0x1004 fn0 is getCapabilities")
        XCTAssertEqual(LogiBatteryFeature.legacy.statusFunction, 0)
        XCTAssertEqual(LogiBatteryFeature.unified.featureId, 0x1004)
        XCTAssertEqual(LogiBatteryFeature.legacy.featureId, 0x1000)
    }

    func testOnlyFunctionZeroWithSoftwareIdZeroIsAnEvent() {
        XCTAssertTrue(LogiBatteryProtocol.isStatusEvent(functionId: 0, softwareId: 0))
        XCTAssertFalse(LogiBatteryProtocol.isStatusEvent(functionId: 0, softwareId: 1), "an answer to Scrollio")
        XCTAssertFalse(LogiBatteryProtocol.isStatusEvent(functionId: 1, softwareId: 0))
    }

    // MARK: - 0x1004

    func testUnifiedStatus_ownerLikeBytes() {
        // 11 FF 09 11 2D 04 00: 45 %, good, discharging
        let battery = LogiBatteryProtocol.unifiedStatus(report(0x09, 0x11, [0x2D, 0x04, 0x00]))
        XCTAssertEqual(battery, LogiMouseDeviceState.Battery(percent: 45, level: .good, charging: .discharging, isApproximate: false))
    }

    func testUnifiedStatus_percentZeroLeavesOnlyTheLevel() {
        let battery = LogiBatteryProtocol.unifiedStatus(report(0x09, 0x11, [0x00, 0x02, 0x00]))
        XCTAssertNil(battery?.percent)
        XCTAssertEqual(battery?.level, .low)
    }

    func testUnifiedStatus_levels() {
        let levels: [UInt8: LogiMouseDeviceState.Battery.Level] = [1: .critical, 2: .low, 4: .good, 8: .full, 0: .unknown, 3: .unknown, 0x10: .unknown]
        for (byte, level) in levels {
            XCTAssertEqual(LogiBatteryProtocol.unifiedStatus(report(0x09, 0x11, [50, byte, 0]))?.level, level, "level byte \(byte)")
        }
    }

    func testChargingStatusEveryValue() {
        let expected: [LogiMouseDeviceState.Battery.Charging] = [
            .discharging, .charging, .almostFull, .full, .chargingSlowly, .problem, .problem, .problem,
        ]
        for (byte, charging) in expected.enumerated() {
            XCTAssertEqual(LogiBatteryProtocol.unifiedStatus(report(0x09, 0x11, [50, 4, UInt8(byte)]))?.charging, charging, "status \(byte)")
            XCTAssertEqual(LogiBatteryProtocol.legacyStatus(report(0x09, 0x01, [50, 20, UInt8(byte)]))?.charging, charging, "status \(byte)")
        }
        XCTAssertEqual(LogiBatteryProtocol.charging(statusByte: 8), .unknown)
        XCTAssertEqual(LogiBatteryProtocol.charging(statusByte: 0xFF), .unknown)
    }

    func testPercentAboveHundredIsNotShown() {
        XCTAssertNil(LogiBatteryProtocol.unifiedStatus(report(0x09, 0x11, [0xC8, 0x08, 0x00]))?.percent)
    }

    func testShortReportsAreNil() {
        XCTAssertNil(LogiBatteryProtocol.unifiedStatus([0x11, 0xFF, 0x09, 0x11, 0x2D, 0x04]))
        XCTAssertNil(LogiBatteryProtocol.legacyStatus([0x11, 0xFF, 0x09, 0x01]))
        XCTAssertNil(LogiBatteryProtocol.parseStatus([], feature: .unified))
    }

    func testEventAndAnswerShareTheParser() {
        let answer = report(0x09, 0x11, [0x50, 0x04, 0x01])
        let event = report(0x09, 0x00, [0x50, 0x04, 0x01])
        XCTAssertEqual(LogiBatteryProtocol.parseStatus(answer, feature: .unified), LogiBatteryProtocol.parseStatus(event, feature: .unified))
    }

    // MARK: - 0x1000

    func testLegacyStatus_coarseStepIsApproximate() {
        // MX Master 3 dump: "100%, discharging, next level 50%"
        let battery = LogiBatteryProtocol.legacyStatus(report(0x07, 0x01, [100, 50, 0]))
        XCTAssertEqual(battery, LogiMouseDeviceState.Battery(percent: 100, level: .unknown, charging: .discharging, isApproximate: true))
    }

    func testLegacyStatus_zeroWhileChargingIsUnknownPercent() {
        let battery = LogiBatteryProtocol.legacyStatus(report(0x07, 0x01, [0, 0, 1]))
        XCTAssertNil(battery?.percent)
        XCTAssertEqual(battery?.charging, .charging)
    }

    func testLegacyStatus_fullSaysFull() {
        XCTAssertEqual(LogiBatteryProtocol.legacyStatus(report(0x07, 0x01, [0, 0, 3]))?.level, .full)
    }

    func testDescribe() {
        let battery = LogiMouseDeviceState.Battery(percent: 45, level: .good, charging: .discharging, isApproximate: false)
        XCTAssertEqual(LogiBatteryProtocol.describe(battery), "45 %, discharging, level good")
        let coarse = LogiMouseDeviceState.Battery(percent: 50, level: .unknown, charging: .charging, isApproximate: true)
        XCTAssertEqual(LogiBatteryProtocol.describe(coarse), "about 50 %, charging")
    }
}
