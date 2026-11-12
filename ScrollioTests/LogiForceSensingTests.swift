import XCTest
@testable import Scrollio_Debug

/// Force Sensing Button (0x19C0) 协议解析与参数编码的纯函数测试.
/// 字节布局对齐 Solaar: fn1 payload = 4x BE UInt16 [changeable, default, max, min],
/// fn2 payload[0:2] = current, SetConfig 参数 = [buttonNumber, currentHi, currentLo].
final class LogiForceSensingTests: XCTestCase {

    // MARK: - GetButtonInfo (fn1) 解析

    func testParseInfo_changeableRangeAndDefault() {
        // changeable=1, default=200(0x00C8), max=500(0x01F4), min=50(0x0032)
        var report = [UInt8](repeating: 0, count: 20)
        report[4] = 0x00; report[5] = 0x01   // changeable UInt16 = 1
        report[6] = 0x00; report[7] = 0xC8   // default = 200
        report[8] = 0x01; report[9] = 0xF4   // max = 500
        report[10] = 0x00; report[11] = 0x32 // min = 50
        XCTAssertEqual(
            LogiDeviceSession.parseForceSensingInfoForTests(report),
            LogiDeviceSession.ForceSensingInfo(changeable: true, minValue: 50, maxValue: 500, defaultValue: 200)
        )
    }

    func testParseInfo_notChangeableReadsBitZero() {
        var report = [UInt8](repeating: 0, count: 20)
        report[4] = 0x00; report[5] = 0x00   // changeable = 0
        report[8] = 0x03; report[9] = 0xE8   // max = 1000
        XCTAssertEqual(LogiDeviceSession.parseForceSensingInfoForTests(report)?.changeable, false)
    }

    func testParseInfo_onlyBitZeroOfChangeableMatters() {
        var report = [UInt8](repeating: 0, count: 20)
        report[4] = 0xFF; report[5] = 0xFE   // UInt16 = 0xFFFE, bit0 = 0
        XCTAssertEqual(LogiDeviceSession.parseForceSensingInfoForTests(report)?.changeable, false)
    }

    func testParseInfo_shortReportReturnsNil() {
        XCTAssertNil(LogiDeviceSession.parseForceSensingInfoForTests([0x11, 0xFF, 0x22, 0x11, 0, 0, 0, 0]))
    }

    // MARK: - GetButtonCurrent (fn2) 解析

    func testParseCurrent_bigEndian() {
        var report = [UInt8](repeating: 0, count: 20)
        report[4] = 0x01; report[5] = 0x2C   // 300
        XCTAssertEqual(LogiDeviceSession.parseForceSensingCurrentForTests(report), 300)
    }

    func testParseCurrent_shortReportReturnsNil() {
        XCTAssertNil(LogiDeviceSession.parseForceSensingCurrentForTests([0x11, 0xFF, 0x22, 0x21, 0x01]))
    }

    // MARK: - SetButtonConfig (fn3) 参数编码

    func testSetCurrentParams_packsButtonAndBigEndianValue() {
        XCTAssertEqual(LogiDeviceSession.forceSensingSetCurrentParamsForTests(number: 0, current: 300), [0x00, 0x01, 0x2C])
    }

    func testSetCurrentParams_nonZeroButtonNumber() {
        XCTAssertEqual(LogiDeviceSession.forceSensingSetCurrentParamsForTests(number: 2, current: 65535), [0x02, 0xFF, 0xFF])
    }

    // MARK: - Clamp

    func testClamp_withinRangeUnchanged() {
        let info = LogiDeviceSession.ForceSensingInfo(changeable: true, minValue: 50, maxValue: 500, defaultValue: 200)
        XCTAssertEqual(LogiDeviceSession.forceSensingClampForTests(300, info: info), 300)
    }

    func testClamp_belowMinRaisesToMin() {
        let info = LogiDeviceSession.ForceSensingInfo(changeable: true, minValue: 50, maxValue: 500, defaultValue: 200)
        XCTAssertEqual(LogiDeviceSession.forceSensingClampForTests(10, info: info), 50)
    }

    func testClamp_aboveMaxLowersToMax() {
        let info = LogiDeviceSession.ForceSensingInfo(changeable: true, minValue: 50, maxValue: 500, defaultValue: 200)
        XCTAssertEqual(LogiDeviceSession.forceSensingClampForTests(1000, info: info), 500)
    }

    func testClamp_nilInfoPassesThrough() {
        XCTAssertEqual(LogiDeviceSession.forceSensingClampForTests(9999, info: nil), 9999)
    }

    // MARK: - Feature 目录

    func testFeatureDirectory_containsForceSensing() {
        XCTAssertEqual(HIDPPInfo.featureNames[LogiDeviceSession.featureForceSensing]?.0, "ForceSensing")
    }

    // MARK: - LogiPressForceProtocol (one definition for the debug panel and the Mouse settings)

    /// OpenLogi's MX Master 4 sample: changeable, default 5089, max 6768, min 4071.
    private static let mxMaster4Info: [UInt8] = {
        var report = [UInt8](repeating: 0, count: 20)
        report[0] = 0x11; report[1] = 0xFF; report[2] = 0x0C; report[3] = 0x11
        report[4] = 0x00; report[5] = 0x01
        report[6] = 0x13; report[7] = 0xE1
        report[8] = 0x1A; report[9] = 0x70
        report[10] = 0x0F; report[11] = 0xE7
        return report
    }()

    func testProtocolParsesTheMXMaster4Sample() {
        let info = LogiPressForceProtocol.parseInfo(Self.mxMaster4Info)
        XCTAssertEqual(info, LogiPressForceInfo(changeable: true, minValue: 4071, maxValue: 6768, defaultValue: 5089))
        XCTAssertEqual(info.map(LogiPressForceProtocol.isValid), true)
        XCTAssertEqual(LogiDeviceSession.parseForceSensingInfoForTests(Self.mxMaster4Info), info, "the session uses the same parser")
    }

    func testProtocolRequestsAddressButtonZero() {
        XCTAssertEqual(LogiPressForceProtocol.infoParams(), [0, 0, 0])
        XCTAssertEqual(LogiPressForceProtocol.currentParams(), [0, 0, 0])
        XCTAssertEqual(LogiPressForceProtocol.setParams(value: 6000), [0x00, 0x17, 0x70])
        XCTAssertEqual(LogiPressForceProtocol.infoFunction, 1)
        XCTAssertEqual(LogiPressForceProtocol.currentFunction, 2)
        XCTAssertEqual(LogiPressForceProtocol.setFunction, 3)
    }

    func testInfoValidity() {
        XCTAssertFalse(LogiPressForceProtocol.isValid(LogiPressForceInfo(changeable: true, minValue: 4071, maxValue: 6768, defaultValue: 9000)),
                       "a default outside the range is refused")
        XCTAssertFalse(LogiPressForceProtocol.isValid(LogiPressForceInfo(changeable: true, minValue: 500, maxValue: 50, defaultValue: 200)),
                       "upside-down range")
        XCTAssertFalse(LogiPressForceProtocol.isValid(LogiPressForceInfo(changeable: true, minValue: 0, maxValue: 0, defaultValue: 0)),
                       "all zero")
        XCTAssertTrue(LogiPressForceProtocol.isValid(LogiPressForceInfo(changeable: false, minValue: 50, maxValue: 500, defaultValue: 50)),
                      "validity is about the range; changeable is checked separately")
    }

    func testClampWithUpsideDownRangeLeavesTheValue() {
        let info = LogiPressForceInfo(changeable: true, minValue: 500, maxValue: 50, defaultValue: 200)
        XCTAssertEqual(LogiPressForceProtocol.clamp(9999, info: info), 9999)
    }
}
