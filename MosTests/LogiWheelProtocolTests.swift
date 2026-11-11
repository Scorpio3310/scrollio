import XCTest
@testable import Mos_Debug

/// Byte layouts and value mappings for SmartShift (0x2110) and SmartShift Enhanced (0x2111).
/// Reports are full HID++ long reports: [0x11, devIdx, featureIdx, fn<<4|swid, payload...].
final class LogiWheelProtocolTests: XCTestCase {

    private func report(functionId: UInt8, payload: [UInt8]) -> [UInt8] {
        var bytes: [UInt8] = [0x11, 0xFF, 0x0E, (functionId << 4) | 0x01] + payload
        while bytes.count < 20 { bytes.append(0) }
        return bytes
    }

    private let smartShiftStatus = LogiWheelStatus(wheelMode: 2, autoDisengage: 16, torque: 50)
    private let freeSpinStatus = LogiWheelStatus(wheelMode: 1, autoDisengage: 16, torque: 50)

    // MARK: - Function numbers

    func testFunctionNumbers_enhancedTableIsShiftedByOne() {
        XCTAssertEqual(LogiWheelFeature.smartShift.readStatusFunction, 0)
        XCTAssertEqual(LogiWheelFeature.smartShift.writeStatusFunction, 1)
        XCTAssertNil(LogiWheelFeature.smartShift.capabilitiesFunction)
        XCTAssertEqual(LogiWheelFeature.smartShiftEnhanced.capabilitiesFunction, 0)
        XCTAssertEqual(LogiWheelFeature.smartShiftEnhanced.readStatusFunction, 1)
        XCTAssertEqual(LogiWheelFeature.smartShiftEnhanced.writeStatusFunction, 2)
        XCTAssertEqual(LogiWheelFeature.smartShift.featureId, 0x2110)
        XCTAssertEqual(LogiWheelFeature.smartShiftEnhanced.featureId, 0x2111)
    }

    // MARK: - Parsing

    func testParseStatus_enhanced_modeThresholdTorque() {
        let status = LogiWheelProtocol.parseStatus(report(functionId: 1, payload: [0x02, 0x10, 72]), feature: .smartShiftEnhanced)
        XCTAssertEqual(status, LogiWheelStatus(wheelMode: 2, autoDisengage: 16, torque: 72))
    }

    func testParseStatus_enhanced_zeroTorqueMeansNotReported() {
        let status = LogiWheelProtocol.parseStatus(report(functionId: 1, payload: [0x01, 0xFF, 0x00]), feature: .smartShiftEnhanced)
        XCTAssertEqual(status, LogiWheelStatus(wheelMode: 1, autoDisengage: 0xFF, torque: nil))
    }

    func testParseStatus_basic_thirdByteIsDefaultNotTorque() {
        // 0x2110 payload[2] = autoDisengageDefault, must not surface as torque
        let status = LogiWheelProtocol.parseStatus(report(functionId: 0, payload: [0x02, 0x0A, 0x10]), feature: .smartShift)
        XCTAssertEqual(status, LogiWheelStatus(wheelMode: 2, autoDisengage: 10, torque: nil))
    }

    func testParseStatus_shortReportsReturnNil() {
        XCTAssertNil(LogiWheelProtocol.parseStatus([0x11, 0xFF, 0x0E, 0x01, 0x02], feature: .smartShift))
        XCTAssertNil(LogiWheelProtocol.parseStatus([0x11, 0xFF, 0x0E, 0x11, 0x02, 0x10], feature: .smartShiftEnhanced))
    }

    func testParseCapabilities() {
        let caps = LogiWheelProtocol.parseCapabilities(report(functionId: 0, payload: [0x01, 0x10, 0x32, 0x40]))
        XCTAssertEqual(caps, LogiWheelCapabilities(tunableTorque: true, autoDisengageDefault: 16, defaultTorque: 50))
        let noTorque = LogiWheelProtocol.parseCapabilities(report(functionId: 0, payload: [0xFE, 0x10, 0x00]))
        XCTAssertEqual(noTorque?.tunableTorque, false, "only bit0 means tunable torque")
        XCTAssertNil(LogiWheelProtocol.parseCapabilities([0x11, 0xFF, 0x0E, 0x01, 0x01]))
    }

    func testModeProjection() {
        XCTAssertEqual(LogiWheelProtocol.mode(for: LogiWheelStatus(wheelMode: 1, autoDisengage: 16, torque: nil)), .freeSpin)
        XCTAssertEqual(LogiWheelProtocol.mode(for: LogiWheelStatus(wheelMode: 1, autoDisengage: 0xFF, torque: nil)), .freeSpin)
        XCTAssertEqual(LogiWheelProtocol.mode(for: LogiWheelStatus(wheelMode: 2, autoDisengage: 0xFF, torque: nil)), .ratchet)
        XCTAssertEqual(LogiWheelProtocol.mode(for: LogiWheelStatus(wheelMode: 2, autoDisengage: 16, torque: nil)), .smartShift)
        XCTAssertNil(LogiWheelProtocol.mode(for: LogiWheelStatus(wheelMode: 0, autoDisengage: 16, torque: nil)))
    }

    // MARK: - Sensitivity mapping

    func testSensitivityToAutoDisengage_anchors() {
        XCTAssertEqual(LogiWheelProtocol.autoDisengage(forSensitivity: 1), 50)
        XCTAssertEqual(LogiWheelProtocol.autoDisengage(forSensitivity: 50), 16)
        XCTAssertEqual(LogiWheelProtocol.autoDisengage(forSensitivity: 100), 8)
    }

    func testSensitivityToAutoDisengage_clampsInput() {
        XCTAssertEqual(LogiWheelProtocol.autoDisengage(forSensitivity: 0), 50)
        XCTAssertEqual(LogiWheelProtocol.autoDisengage(forSensitivity: -20), 50)
        XCTAssertEqual(LogiWheelProtocol.autoDisengage(forSensitivity: 250), 8)
    }

    func testSensitivityToAutoDisengage_higherPercentSwitchesSooner() {
        var previous = LogiWheelProtocol.autoDisengage(forSensitivity: 1)
        for pct in 2...100 {
            let value = LogiWheelProtocol.autoDisengage(forSensitivity: pct)
            XCTAssertLessThanOrEqual(value, previous, "threshold must not rise with sensitivity (pct \(pct))")
            XCTAssertTrue((8...50).contains(value), "pct \(pct) -> \(value) outside the usable band")
            previous = value
        }
    }

    func testAutoDisengageToSensitivity_anchorsAndSpecialValues() {
        XCTAssertEqual(LogiWheelProtocol.sensitivity(forAutoDisengage: 50), 1)
        XCTAssertEqual(LogiWheelProtocol.sensitivity(forAutoDisengage: 16), 50)
        XCTAssertEqual(LogiWheelProtocol.sensitivity(forAutoDisengage: 8), 100)
        XCTAssertNil(LogiWheelProtocol.sensitivity(forAutoDisengage: 0xFF), "always-ratchet has no sensitivity")
        XCTAssertNil(LogiWheelProtocol.sensitivity(forAutoDisengage: 0x00))
        XCTAssertEqual(LogiWheelProtocol.sensitivity(forAutoDisengage: 200), 1, "above the band clamps to 1 %")
        XCTAssertEqual(LogiWheelProtocol.sensitivity(forAutoDisengage: 3), 100, "below the band clamps to 100 %")
    }

    func testRoundTrip_everyThresholdInBandSurvives() {
        for threshold in UInt8(8)...UInt8(50) {
            guard let pct = LogiWheelProtocol.sensitivity(forAutoDisengage: threshold) else {
                return XCTFail("no sensitivity for \(threshold)")
            }
            XCTAssertEqual(LogiWheelProtocol.autoDisengage(forSensitivity: pct), threshold, "threshold \(threshold) -> \(pct) %")
        }
    }

    func testRoundTrip_percentStaysClose() {
        for pct in 1...100 {
            let threshold = LogiWheelProtocol.autoDisengage(forSensitivity: pct)
            guard let back = LogiWheelProtocol.sensitivity(forAutoDisengage: threshold) else {
                return XCTFail("no sensitivity for \(threshold)")
            }
            XCTAssertLessThanOrEqual(abs(back - pct), 4, "pct \(pct) -> \(threshold) -> \(back)")
        }
    }

    // MARK: - SetState encoding

    func testSetParams_enhancedWithTorque_eachMode() {
        XCTAssertEqual(LogiWheelProtocol.setParams(mode: .freeSpin, threshold: nil, torque: 70, current: smartShiftStatus, feature: .smartShiftEnhanced),
                       [0x01, 0x00, 70], "free-spin keeps the stored threshold")
        XCTAssertEqual(LogiWheelProtocol.setParams(mode: .ratchet, threshold: nil, torque: 70, current: smartShiftStatus, feature: .smartShiftEnhanced),
                       [0x02, 0xFF, 70], "ratchet disables auto-disengage")
        XCTAssertEqual(LogiWheelProtocol.setParams(mode: .smartShift, threshold: 16, torque: 70, current: freeSpinStatus, feature: .smartShiftEnhanced),
                       [0x02, 16, 70])
        XCTAssertEqual(LogiWheelProtocol.setParams(mode: .smartShift, threshold: nil, torque: nil, current: freeSpinStatus, feature: .smartShiftEnhanced),
                       [0x02, 0x00, 0x00], "the mouse's own threshold")
    }

    /// Nothing given changes nothing: the mode byte repeats the mouse's own (MX Master 4
    /// ignores a torque write without it), the rest says "unchanged".
    func testSetParams_withoutAModeRepeatsTheMouseMode() {
        XCTAssertEqual(LogiWheelProtocol.setParams(mode: nil, threshold: nil, torque: 70, current: freeSpinStatus, feature: .smartShiftEnhanced),
                       [0x01, 0x00, 70])
        XCTAssertEqual(LogiWheelProtocol.setParams(mode: nil, threshold: 8, torque: nil, current: smartShiftStatus, feature: .smartShiftEnhanced),
                       [0x02, 8, 0x00])
        let nothing = LogiWheelProtocol.setParams(mode: nil, threshold: nil, torque: nil, current: smartShiftStatus, feature: .smartShiftEnhanced)
        XCTAssertFalse(LogiWheelProtocol.needsWrite(nothing, current: smartShiftStatus))
        XCTAssertEqual(LogiWheelProtocol.setParams(mode: nil, threshold: nil, torque: 70,
                                                   current: LogiWheelStatus(wheelMode: 7, autoDisengage: 16, torque: 50), feature: .smartShiftEnhanced),
                       [0x00, 0x00, 70], "an unknown mode byte is not repeated")
    }

    func testSetParams_basic_neverSendsTorque() {
        XCTAssertEqual(LogiWheelProtocol.setParams(mode: .ratchet, threshold: nil, torque: 90, current: smartShiftStatus, feature: .smartShift),
                       [0x02, 0xFF, 0x00])
        XCTAssertEqual(LogiWheelProtocol.setParams(mode: .freeSpin, threshold: nil, torque: nil, current: smartShiftStatus, feature: .smartShift),
                       [0x01, 0x00, 0x00])
    }

    func testClampedTorque() {
        XCTAssertEqual(LogiWheelProtocol.clampedTorque(150), 100)
        XCTAssertEqual(LogiWheelProtocol.clampedTorque(0), 1)
    }

    func testThresholdAndSensitivityHelpers() {
        XCTAssertNil(LogiWheelProtocol.threshold(0xFF), "always ratchet")
        XCTAssertNil(LogiWheelProtocol.threshold(0))
        XCTAssertEqual(LogiWheelProtocol.threshold(16), 16)
        XCTAssertEqual(LogiWheelProtocol.sensitivityAsKept(51), 50)
        XCTAssertEqual(LogiWheelProtocol.sensitivityAsKept(72), 75)
        XCTAssertTrue(LogiWheelProtocol.sensitivityMatches(51, threshold: 16), "the same byte")
        XCTAssertTrue(LogiWheelProtocol.sensitivityMatches(51, threshold: 17), "49 %: within the tolerance")
        XCTAssertFalse(LogiWheelProtocol.sensitivityMatches(60, threshold: 17))
        XCTAssertEqual(LogiWheelProtocol.autoDisengage(forSensitivity: LogiWheelSettings.defaultSmartShiftSensitivity),
                       LogiWheelProtocol.autoDisengageDefault, "the default sensitivity is the factory threshold")
    }

    func testToggleParams_flipModeOnly() {
        XCTAssertEqual(LogiWheelProtocol.toggleParams(from: LogiWheelStatus(wheelMode: 2, autoDisengage: 16, torque: 50)), [0x01, 0x00, 0x00])
        XCTAssertEqual(LogiWheelProtocol.toggleParams(from: LogiWheelStatus(wheelMode: 1, autoDisengage: 16, torque: 50)), [0x02, 0x00, 0x00])
    }

    func testNeedsWrite() {
        let current = LogiWheelStatus(wheelMode: 2, autoDisengage: 16, torque: 50)
        XCTAssertTrue(LogiWheelProtocol.needsWrite([0x02, 16, 50], current: nil))
        XCTAssertFalse(LogiWheelProtocol.needsWrite([0x02, 16, 50], current: current))
        XCTAssertFalse(LogiWheelProtocol.needsWrite([0x02, 16, 0x00], current: current), "0 = unchanged")
        XCTAssertTrue(LogiWheelProtocol.needsWrite([0x02, 20, 50], current: current))
        XCTAssertTrue(LogiWheelProtocol.needsWrite([0x02, 16, 60], current: current))
        XCTAssertTrue(LogiWheelProtocol.needsWrite([0x01, 0x00, 0x00], current: current))
        XCTAssertTrue(LogiWheelProtocol.needsWrite([0x02, 16, 50], current: LogiWheelStatus(wheelMode: 2, autoDisengage: 16, torque: nil)))
    }
}
