import XCTest
@testable import Scrollio_Debug

/// Byte layouts behind Gesture Navigation on Logitech mice: setCidReporting flags for raw XY
/// (0x1B04 fn3), the raw XY movement event (0x1B04 event fn1) and the haptic feature
/// (0x19B0). Fake bytes only.
final class LogiGestureProtocolTests: XCTestCase {

    private typealias Change = LogiGestureProtocol.ReportingChange

    private func report(_ function: UInt8, _ payload: [UInt8], featureIndex: UInt8 = 0x09) -> [UInt8] {
        var bytes: [UInt8] = [0x11, 0xFF, featureIndex, function] + payload
        while bytes.count < 20 { bytes.append(0) }
        return bytes
    }

    // MARK: - setCidReporting flags

    func testArmIsDivertPlusRawXYWithBothValidBits() {
        XCTAssertEqual(Change.divertWithRawXY.flags, 0x33)
        XCTAssertEqual(
            LogiGestureProtocol.reportingParams(cid: 0x00C3, flags: Change.divertWithRawXY.flags),
            [0x00, 0xC3, 0x33, 0x00, 0x00]
        )
    }

    func testDisarmClearsDivertAndRawXY() {
        XCTAssertEqual(Change.undivertAndClearRawXY.flags, 0x22)
        XCTAssertEqual(
            LogiGestureProtocol.reportingParams(cid: 0x01A0, flags: Change.undivertAndClearRawXY.flags),
            [0x01, 0xA0, 0x22, 0x00, 0x00]
        )
    }

    func testPlainDivertBytesAreTheOnesScrollioAlwaysSent() {
        XCTAssertEqual(Change.divert.flags, 0x03)
        XCTAssertEqual(Change.undivert.flags, 0x02)
        // The existing entry point still produces them, raw XY bits untouched.
        XCTAssertEqual(
            LogiDeviceSession.controlReportingParamsForTests(connectionMode: .bleDirect, cid: 0x00C3, divert: true),
            [0x00, 0xC3, 0x03, 0x00, 0x00]
        )
        XCTAssertEqual(
            LogiDeviceSession.controlReportingParamsForTests(connectionMode: .receiver, cid: 0x00C3, divert: false),
            [0x00, 0xC3, 0x02, 0x00, 0x00]
        )
    }

    func testKeepingTheDivertWhileClearingRawXY() {
        // Divert on (valid), raw XY off (valid).
        XCTAssertEqual(Change.divertWithoutRawXY.flags, 0x23)
    }

    func testNoChangeEverSetsPersistentOrForcedFlags() {
        for change in Change.allCases {
            XCTAssertEqual(change.flags & 0xCC, 0, "\(change): persist (bits 2-3) and force raw XY (bits 6-7) stay clear")
            XCTAssertEqual(change.flags & 0x02, 0x02, "\(change): the divert bit is always stated")
            XCTAssertEqual(change.diverts, change.flags & 0x01 != 0)
        }
        XCTAssertEqual(Set(Change.allCases.map { $0.flags }).count, Change.allCases.count)
    }

    func testSessionBuildsTheSameParamsForBothTransportsAndNothingWhenUnsupported() {
        for mode in [LogiDeviceSession.ConnectionMode.bleDirect, .receiver] {
            XCTAssertEqual(
                LogiDeviceSession.controlReportingParamsForTests(connectionMode: mode, cid: 0x00C4, flagsByte: 0x33),
                [0x00, 0xC4, 0x33, 0x00, 0x00]
            )
        }
        XCTAssertEqual(
            LogiDeviceSession.controlReportingParamsForTests(connectionMode: .unsupported, cid: 0x00C4, flagsByte: 0x33),
            []
        )
    }

    func testOnlyTheEchoOfTheArmRequestAcknowledgesRawXY() {
        XCTAssertTrue(LogiGestureProtocol.acknowledgesRawXY(flags: 0x33))
        for flags: UInt8 in [0x03, 0x02, 0x23, 0x22, 0x30, 0x13, 0x00] {
            XCTAssertFalse(LogiGestureProtocol.acknowledgesRawXY(flags: flags), String(format: "0x%02X", flags))
        }
    }

    // MARK: - Capability

    func testRawXYCapabilityIsBitZeroOfTheSecondFlagsByte() {
        // The session stores flags1 | flags2 << 8.
        XCTAssertTrue(LogiGestureProtocol.supportsRawXY(controlFlags: 0x0130))
        XCTAssertFalse(LogiGestureProtocol.supportsRawXY(controlFlags: 0x0030))
        XCTAssertFalse(LogiGestureProtocol.supportsRawXY(controlFlags: 0x0230), "force_raw_xy alone is not raw_xy")
    }

    func testCapableControlsMustAlsoBeDivertable() {
        let controls = [
            LogiDeviceSession.ControlInfo(cid: 0x0050, taskId: 0x38, flags: 0x0001, isDivertable: false),
            LogiDeviceSession.ControlInfo(cid: 0x0053, taskId: 0x3C, flags: 0x0131, isDivertable: true),
            LogiDeviceSession.ControlInfo(cid: 0x00C3, taskId: 0x9C, flags: 0x0130, isDivertable: true),
            LogiDeviceSession.ControlInfo(cid: 0x00D7, taskId: 0xB4, flags: 0x00A0, isDivertable: true),
            LogiDeviceSession.ControlInfo(cid: 0x00E0, taskId: 0x00, flags: 0x0100, isDivertable: false),
        ]
        XCTAssertEqual(LogiDeviceSession.rawXYCapableCIDs(in: controls), [0x0053, 0x00C3])
    }

    func testRequestedScrollioCodesMapToControlIds() {
        // Gesture button, mode-shift button, MX Master 4 haptic sense panel; plain button 3 has no CID.
        XCTAssertEqual(
            LogiDeviceSession.rawXYRequestCIDs(forScrollioCodes: [1000, 1001, 2000 + 0x01A0, 3]),
            [0x00C3, 0x00C4, 0x01A0]
        )
        XCTAssertEqual(LogiDeviceSession.rawXYRequestCIDs(forScrollioCodes: []), [])
    }

    // MARK: - Raw XY event

    func testRawXYDeltaIsSignedBigEndian() throws {
        let right = try XCTUnwrap(LogiGestureProtocol.rawXYDelta(report(0x10, [0x00, 0x0A, 0x00, 0x00])))
        XCTAssertEqual(right.deltaX, 10)
        XCTAssertEqual(right.deltaY, 0)

        let leftUp = try XCTUnwrap(LogiGestureProtocol.rawXYDelta(report(0x10, [0xFF, 0xF6, 0xFF, 0xFD])))
        XCTAssertEqual(leftUp.deltaX, -10)
        XCTAssertEqual(leftUp.deltaY, -3)

        let large = try XCTUnwrap(LogiGestureProtocol.rawXYDelta(report(0x10, [0x01, 0x2C, 0x80, 0x00])))
        XCTAssertEqual(large.deltaX, 300)
        XCTAssertEqual(large.deltaY, -32768)
    }

    func testRawXYDeltaWorksOnTheReportBufferWithoutCopying() {
        let bytes = report(0x10, [0xFF, 0xFF, 0x00, 0x02])
        let delta = bytes.withUnsafeBufferPointer { LogiGestureProtocol.rawXYDelta($0) }
        XCTAssertEqual(delta?.deltaX, -1)
        XCTAssertEqual(delta?.deltaY, 2)
    }

    func testOnlyFunctionOneWithSoftwareIdZeroIsARawXYEvent() {
        XCTAssertTrue(LogiGestureProtocol.isRawXYEvent(report(0x10, [0, 1, 0, 1])))
        // getCidInfo answer: function 1 with Scrollio's software id.
        XCTAssertFalse(LogiGestureProtocol.isRawXYEvent(report(0x11, [0x00, 0xC3, 0x00, 0x9C])))
        XCTAssertNil(LogiGestureProtocol.rawXYDelta(report(0x11, [0x00, 0xC3, 0x00, 0x9C])))
        // Button event (function 0), reporting notification (function 2), reporting echo (function 3).
        XCTAssertNil(LogiGestureProtocol.rawXYDelta(report(0x00, [0x00, 0xC3])))
        XCTAssertNil(LogiGestureProtocol.rawXYDelta(report(0x20, [0x00, 0xC3, 0x11])))
        XCTAssertNil(LogiGestureProtocol.rawXYDelta(report(0x31, [0x00, 0xC3, 0x33])))
        // A short report cannot carry both deltas.
        XCTAssertNil(LogiGestureProtocol.rawXYDelta([0x10, 0xFF, 0x09, 0x10, 0x00, 0x01, 0x00]))
    }

    func testDuringDiscoveryMovementIsNotTakenForAControlInfoAnswer() {
        // dx = 195, dy = 156 would read as "CID 0x00C3, task 0x009C" if it were parsed as getCidInfo.
        let movement = report(0x10, [0x00, 0xC3, 0x00, 0x9C])
        XCTAssertEqual(LogiDeviceSession.reprogInitFunction1RouteForTests(movement), .rawXYEvent)

        let controlInfo = report(0x11, [0x00, 0xC3, 0x00, 0x9C, 0x30, 0x00, 0x00, 0x00, 0x01])
        XCTAssertEqual(LogiDeviceSession.reprogInitFunction1RouteForTests(controlInfo), .getControlInfoResponse)
    }

    func testButtonEventsStayOnFunctionZero() {
        // The research: button state keeps arriving as event fn0 while raw XY is on.
        let buttons = report(0x00, [0x00, 0xC3])
        XCTAssertTrue(LogiDeviceSession.isDivertedButtonEventForTests(buttons))
        XCTAssertFalse(LogiGestureProtocol.isRawXYEvent(buttons))
        XCTAssertFalse(LogiDeviceSession.isDivertedButtonEventForTests(report(0x10, [0, 1, 0, 1])))
    }

    func testGetReportingRawXYBit() {
        XCTAssertTrue(LogiGestureProtocol.reportsRawXY(reportingFlags: 0x11))
        XCTAssertFalse(LogiGestureProtocol.reportsRawXY(reportingFlags: 0x01))
        XCTAssertFalse(LogiGestureProtocol.reportsRawXY(reportingFlags: 0x00))
    }

    // MARK: - Haptics

    func testCueWaveforms() {
        XCTAssertEqual(LogiGestureProtocol.waveform(for: .lockIn), 0x04)
        XCTAssertEqual(LogiGestureProtocol.waveform(for: .commit), 0x01)
        // Both are waveforms the debug panel knows by name.
        let known = Set(HIDPPInfo.hapticWaveforms.map { $0.id })
        XCTAssertTrue(known.contains(LogiGestureProtocol.waveform(for: .lockIn)))
        XCTAssertTrue(known.contains(LogiGestureProtocol.waveform(for: .commit)))
    }

    func testHapticFunctionNumbers() {
        XCTAssertEqual(LogiGestureProtocol.hapticCapabilitiesFunction, 0)
        XCTAssertEqual(LogiGestureProtocol.hapticGetStateFunction, 1)
        XCTAssertEqual(LogiGestureProtocol.hapticSetStateFunction, 2)
        XCTAssertEqual(LogiGestureProtocol.hapticPlayFunction, 4)
    }

    func testWaveformMaskMatchesTheSessionParser() {
        var bytes = report(0x01, [], featureIndex: 0x21)
        bytes[8] = 0x08; bytes[9] = 0x00; bytes[10] = 0x7F; bytes[11] = 0xFF
        XCTAssertEqual(LogiGestureProtocol.hapticWaveformMask(bytes), 0x0800_7FFF)
        XCTAssertEqual(
            LogiGestureProtocol.hapticWaveformMask(bytes),
            LogiDeviceSession.parseHapticCapabilitiesMaskForTests(bytes)
        )
        XCTAssertNil(LogiGestureProtocol.hapticWaveformMask([0x11, 0xFF, 0x21, 0x01, 0, 0, 0]))
    }

    func testWaveformSupport() {
        let mask: UInt32 = (1 << 0x04) | (1 << 0x1B)
        XCTAssertTrue(LogiGestureProtocol.supports(waveform: 0x04, mask: mask))
        XCTAssertTrue(LogiGestureProtocol.supports(waveform: 0x1B, mask: mask))
        XCTAssertFalse(LogiGestureProtocol.supports(waveform: 0x01, mask: mask))
        XCTAssertFalse(LogiGestureProtocol.supports(waveform: 40, mask: 0xFFFF_FFFF), "ids past the mask are unsupported")
    }

    func testHapticsEnabledReadsOnlyBitZero() {
        // bit0 enabled, bit1 power save, then the intensity.
        XCTAssertEqual(LogiGestureProtocol.hapticsEnabled(report(0x11, [0x01, 60], featureIndex: 0x21)), true)
        XCTAssertEqual(LogiGestureProtocol.hapticsEnabled(report(0x11, [0x03, 60], featureIndex: 0x21)), true)
        XCTAssertEqual(LogiGestureProtocol.hapticsEnabled(report(0x11, [0x02, 60], featureIndex: 0x21)), false)
        XCTAssertEqual(LogiGestureProtocol.hapticsEnabled(report(0x11, [0x00, 0], featureIndex: 0x21)), false)
        XCTAssertNil(LogiGestureProtocol.hapticsEnabled([0x11, 0xFF, 0x21, 0x11, 0x01]))
    }
}
