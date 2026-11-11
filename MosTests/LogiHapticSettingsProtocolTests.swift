import XCTest
@testable import Mos_Debug

/// Haptic settings (0x19B0 getState / setState) byte layouts on fake bytes.
final class LogiHapticSettingsProtocolTests: XCTestCase {

    private func stateReport(_ payload: [UInt8]) -> [UInt8] {
        var bytes: [UInt8] = [0x11, 0xFF, 0x0B, 0x11] + payload
        while bytes.count < 20 { bytes.append(0) }
        return bytes
    }

    func testOwnerMouseState() {
        // The owner's MX Master 4: 11 FF 0B 11 00 64 00 00 ...
        let state = LogiHapticSettingsProtocol.parseState(stateReport([0x00, 0x64, 0x00]))
        XCTAssertEqual(state, LogiHapticSettingsProtocol.State(flags: 0x00, strength: 100, levelsByte: 0x00))
        XCTAssertEqual(state?.isOn, false)
        XCTAssertEqual(LogiHapticSettingsProtocol.hasFewLevels(levelsByte: state?.levelsByte), false)
    }

    func testStateReadsOnlyBitZeroAsOn() {
        XCTAssertEqual(LogiHapticSettingsProtocol.parseState(stateReport([0x03, 40]))?.isOn, true)
        XCTAssertEqual(LogiHapticSettingsProtocol.parseState(stateReport([0x02, 40]))?.isOn, false)
        XCTAssertEqual(LogiHapticSettingsProtocol.parseState(stateReport([0xFE, 40]))?.flags, 0xFE, "unknown bits are kept")
    }

    func testStrengthAboveHundredReadsAsHundred() {
        XCTAssertEqual(LogiHapticSettingsProtocol.parseState(stateReport([0x01, 0xC8]))?.strength, 100)
    }

    func testShortStateIsNil() {
        XCTAssertNil(LogiHapticSettingsProtocol.parseState([0x11, 0xFF, 0x0B, 0x11, 0x01]))
        let noLevels = LogiHapticSettingsProtocol.parseState([0x11, 0xFF, 0x0B, 0x11, 0x01, 50])
        XCTAssertEqual(noLevels?.strength, 50)
        XCTAssertNil(noLevels?.levelsByte)
        XCTAssertNil(LogiHapticSettingsProtocol.hasFewLevels(levelsByte: nil))
    }

    func testFewLevelsIsBitZeroOfTheLevelsByte() {
        XCTAssertEqual(LogiHapticSettingsProtocol.hasFewLevels(levelsByte: 0x01), true)
        XCTAssertEqual(LogiHapticSettingsProtocol.hasFewLevels(levelsByte: 0x34), false)
        XCTAssertEqual(LogiHapticSettingsProtocol.hasFewLevels(levelsByte: 0x00), false)
    }

    // MARK: - setState

    func testSwitchingOnKeepsPowerSave() {
        XCTAssertEqual(LogiHapticSettingsProtocol.setStateParams(readFlags: 0x82, readStrength: 40, on: true, strength: nil), [0x83, 40, 0])
    }

    func testSwitchingOffKeepsPowerSaveAndStrength() {
        XCTAssertEqual(LogiHapticSettingsProtocol.setStateParams(readFlags: 0x83, readStrength: 40, on: false, strength: nil), [0x82, 40, 0])
        XCTAssertEqual(LogiHapticSettingsProtocol.setStateParams(readFlags: 0x03, readStrength: 75, on: false, strength: nil), [0x02, 75, 0],
                       "never Solaar's [0x00, 0x32]")
    }

    func testUnknownBitsAreKept() {
        XCTAssertEqual(LogiHapticSettingsProtocol.setStateParams(readFlags: 0xF0, readStrength: 10, on: true, strength: 20), [0xF1, 20, 0])
    }

    func testStrengthOnlyLeavesTheOnBitAlone() {
        XCTAssertEqual(LogiHapticSettingsProtocol.setStateParams(readFlags: 0x00, readStrength: 100, on: nil, strength: 50), [0x00, 50, 0])
        XCTAssertEqual(LogiHapticSettingsProtocol.setStateParams(readFlags: 0x01, readStrength: 0, on: nil, strength: nil), [0x01, 0, 0],
                       "nothing asked, nothing changed")
    }

    func testSwitchingOnFromZeroUsesTheFallback() {
        XCTAssertEqual(LogiHapticSettingsProtocol.setStateParams(readFlags: 0x00, readStrength: 0, on: true, strength: nil), [0x01, 60, 0])
        XCTAssertEqual(LogiHapticSettingsProtocol.setStateParams(readFlags: 0x00, readStrength: 0, on: true, strength: 30), [0x01, 30, 0])
    }

    func testStrengthIsClamped() {
        XCTAssertEqual(LogiHapticSettingsProtocol.setStateParams(readFlags: 0x01, readStrength: 50, on: nil, strength: 500)[1], 100)
        XCTAssertEqual(LogiHapticSettingsProtocol.setStateParams(readFlags: 0x01, readStrength: 50, on: nil, strength: 0)[1], 1)
    }

    func testNeedsWriteComparesFlagsAndStrength() {
        let state = LogiHapticSettingsProtocol.State(flags: 0x02, strength: 40, levelsByte: 0)
        XCTAssertFalse(LogiHapticSettingsProtocol.needsWrite([0x02, 40, 0], current: state))
        XCTAssertTrue(LogiHapticSettingsProtocol.needsWrite([0x03, 40, 0], current: state))
        XCTAssertTrue(LogiHapticSettingsProtocol.needsWrite([0x02, 41, 0], current: state))
    }

    func testSnapStrength() {
        XCTAssertEqual(LogiHapticSettingsProtocol.snapStrength(60, fewLevels: true), 50)
        XCTAssertEqual(LogiHapticSettingsProtocol.snapStrength(63, fewLevels: true), 75)
        XCTAssertEqual(LogiHapticSettingsProtocol.snapStrength(5, fewLevels: true), 25)
        XCTAssertEqual(LogiHapticSettingsProtocol.snapStrength(60, fewLevels: false), 60)
        XCTAssertEqual(LogiHapticSettingsProtocol.snapStrength(0, fewLevels: false), 1)
    }

    func testGestureSwitchOnUsesTheSameDefinition() {
        for (flags, level) in [(UInt8(0x00), UInt8(100)), (0x02, 40), (0x00, 0), (0x81, 200)] {
            XCTAssertEqual(
                LogiGestureProtocol.hapticSwitchOnParams(flags: flags, level: level),
                LogiHapticSettingsProtocol.setStateParams(readFlags: flags, readStrength: level, on: true, strength: nil)
            )
        }
    }

    func testSamplePulse() {
        XCTAssertEqual(LogiHapticSettingsProtocol.playFunction, 4)
        XCTAssertEqual(LogiHapticSettingsProtocol.playParams(waveform: LogiHapticSettingsProtocol.sampleWaveform), [0x01])
    }
}
