import XCTest
@testable import Mos_Debug

/// Session-level pieces of the basic mouse settings work, and the defects found on the way:
/// the HID++ error byte, the diagnostics quick actions, one-byte 0x2121 writes, probing.
final class LogiBasicsSessionFixesTests: XCTestCase {

    // MARK: - HID++ 2.0 error code

    /// Regression: the error code was read from byte 6, which is past it (always 0 here).
    func testErrorCodeIsByteFive() throws {
        // [0x11, devIdx, 0xFF, origFeatureIdx, origFn<<4 | swid, errorCode, 0...]
        var report: [UInt8] = [0x11, 0xFF, 0xFF, 0x14, 0x31, 0x02, 0x00]
        while report.count < 20 { report.append(0) }
        let fields = try XCTUnwrap(LogiDeviceSession.hidpp20ErrorFields(report))
        XCTAssertEqual(fields.featureIndex, 0x14)
        XCTAssertEqual(fields.functionId, 3)
        XCTAssertEqual(fields.errorCode, 0x02, "InvalidArgument, from byte 5")
    }

    func testErrorFieldsOfAShortReportAreNil() {
        XCTAssertNil(LogiDeviceSession.hidpp20ErrorFields([0x11, 0xFF, 0xFF, 0x14, 0x31]))
    }

    // MARK: - Diagnostics quick actions

    /// Functions that write, per feature. A quick action named "Get..." must never be one.
    private static let writeFunctions: [UInt16: Set<UInt8>] = [
        0x1B04: [3], 0x2110: [1], 0x2121: [2], 0x2201: [3], 0x8060: [2], 0x8061: [3],
    ]

    /// Regression: 0x2201 "GetDPIList" sent fn3 with the sensor index alone, a
    /// setSensorDpi(sensor 0, DPI 0).
    func testDPIQuickActionsUseTheRightFunctions() {
        let actions = HIDPPFeatureActions.knownActions[0x2201] ?? []
        XCTAssertEqual(actions.first { $0.name == "GetDPIList" }?.functionId, 1)
        XCTAssertEqual(actions.first { $0.name == "GetDPI" }?.functionId, 2)
        let set = actions.first { $0.name == "SetDPI" }
        XCTAssertEqual(set?.functionId, 3)
        XCTAssertEqual(set?.defaultParams, [0x00, 0x03, 0xE8], "sensor 0, 1000 DPI: never DPI 0")
    }

    /// Regression: 0x1004 "GetStatus" sent fn0, which is getCapabilities.
    func testBatteryQuickActionsUseTheRightFunctions() {
        let actions = HIDPPFeatureActions.knownActions[0x1004] ?? []
        XCTAssertEqual(actions.first { $0.name == "GetStatus" }?.functionId, 1)
        XCTAssertEqual(actions.first { $0.name == "GetCapabilities" }?.functionId, 0)
    }

    func testNoGetterQuickActionSendsAWriteFunction() {
        for (feature, writes) in Self.writeFunctions {
            for action in HIDPPFeatureActions.knownActions[feature] ?? [] where action.name.hasPrefix("Get") {
                XCTAssertFalse(writes.contains(action.functionId),
                               "\(action.name) on \(String(format: "0x%04X", feature)) sends write function \(action.functionId)")
            }
        }
    }

    func testQuickActionFunctionsAreUniquePerFeature() {
        // The panel finds an action by its function number.
        for (feature, actions) in HIDPPFeatureActions.knownActions {
            XCTAssertEqual(Set(actions.map(\.functionId)).count, actions.count, String(format: "0x%04X", feature))
        }
    }

    // MARK: - The panel in a Release build

    /// A Release build's diagnostics panel reads and shows: it offers no request that changes
    /// a device. ("SetReporting" with its default parameters diverts the left button; "Func 0"
    /// on Device Reset reconfigures the mouse.)
    func testWithoutDeviceWritesThePanelOffersOnlyReads() {
        for (feature, actions) in HIDPPFeatureActions.knownActions {
            let label = String(format: "0x%04X", feature)
            let offered = HIDPPFeatureActions.actions(for: feature, offeringWrites: false)
            XCTAssertTrue(offered.allSatisfy(\.isReadOnly), label)
            XCTAssertFalse(offered.contains { $0.name.hasPrefix("Set") }, label)
            XCTAssertEqual(offered.count, actions.filter(\.isReadOnly).count, "\(label): every read stays")
            // With writes (a Debug build) the whole list is there.
            XCTAssertEqual(HIDPPFeatureActions.actions(for: feature, offeringWrites: true).count, actions.count, label)
        }
        // The left-button divert in particular.
        XCTAssertFalse(HIDPPFeatureActions.actions(for: 0x1B04, offeringWrites: false).contains { $0.name == "SetReporting" })
        XCTAssertTrue(HIDPPFeatureActions.actions(for: 0x1B04, offeringWrites: true).contains { $0.name == "SetReporting" })
        // A feature without a list (Device Reset, Persistent Remap, Onboard Profiles): no
        // "Func N" buttons at all without writes, all sixteen with them.
        for feature: UInt16 in [0x1802, 0x1C00, 0x8100] {
            XCTAssertNil(HIDPPFeatureActions.knownActions[feature])
            XCTAssertTrue(HIDPPFeatureActions.actions(for: feature, offeringWrites: false).isEmpty)
            XCTAssertEqual(HIDPPFeatureActions.actions(for: feature, offeringWrites: true).count, 16)
        }
        // Every action is named so that the rule can tell reads from writes.
        let names = Set(HIDPPFeatureActions.knownActions.values.flatMap { $0 }.map(\.name))
        XCTAssertTrue(names.allSatisfy { $0.hasPrefix("Get") || $0.hasPrefix("Set") || $0 == "Ping" }, "\(names.sorted())")
        #if DEBUG
        XCTAssertTrue(HIDPPFeatureActions.offersDeviceWrites, "the tests run a Debug build")
        #endif
    }

    // MARK: - 0x2121 writes

    /// Regression: the hi-res / invert toggles sent only the mode byte, zeroing bytes 1-2.
    func testHiResWheelToggleSendsBytesOneAndTwoBack() {
        var report: [UInt8] = [0x11, 0xFF, 0x0F, 0x11, 0x0A, 0x12, 0x34]
        while report.count < 20 { report.append(0) }
        XCTAssertEqual(LogiDeviceSession.hiResWheelModeParams(toggling: LogiDeviceSession.hiResWheelResolutionBit, in: report),
                       [0x08, 0x12, 0x34])
        XCTAssertEqual(LogiDeviceSession.hiResWheelModeParams(toggling: LogiDeviceSession.hiResWheelInvertBit, in: report),
                       [0x0E, 0x12, 0x34], "the analytics bit 3 and the target bit stay as read")
        XCTAssertNil(LogiDeviceSession.hiResWheelModeParams(toggling: 0x02, in: [0x11, 0xFF, 0x0F, 0x11, 0x0A]))
    }

    // MARK: - Probing and features

    func testProbeIncludesBatteryAndDPI() {
        let probe = LogiDeviceSession.optionalProbeFeaturesForTests
        XCTAssertTrue(probe.contains(0x1004))
        XCTAssertTrue(probe.contains(0x1000), "the original MX Master 3 has only 0x1000")
        XCTAssertTrue(probe.contains(0x2201))
        XCTAssertTrue(probe.contains(0x19B0))
        XCTAssertTrue(probe.contains(0x19C0))
        XCTAssertLessThan(probe.firstIndex(of: 0x1004)!, probe.firstIndex(of: 0x1000)!, "0x1004 first, so 0x1000 can be skipped")
        XCTAssertEqual(Set(probe).count, probe.count)
    }

    func testFeaturesFromIndices_unifiedBatteryWins() {
        let features = LogiDeviceSession.mouseBasicsFeatures(from: [0x1004: 0x09, 0x1000: 0x07, 0x2201: 0x14, 0x19B0: 0x0B, 0x19C0: 0x0C, 0x1B04: 0x05])
        XCTAssertEqual(features.battery, .init(feature: .unified, index: 0x09))
        XCTAssertEqual(features.pointerSpeed, 0x14)
        XCTAssertEqual(features.haptics, 0x0B)
        XCTAssertEqual(features.pressForce, 0x0C)
    }

    func testFeaturesFromIndices_legacyBatteryAndNothingElse() {
        let features = LogiDeviceSession.mouseBasicsFeatures(from: [0x1000: 0x07, 0x1B04: 0x05])
        XCTAssertEqual(features.battery, .init(feature: .legacy, index: 0x07))
        XCTAssertNil(features.pointerSpeed)
        XCTAssertFalse(features.isEmpty)
        XCTAssertTrue(LogiDeviceSession.mouseBasicsFeatures(from: [0x1B04: 0x05]).isEmpty)
    }

    func testFeatureDirectoryNamesTheNewFeatures() {
        XCTAssertEqual(HIDPPInfo.featureNames[LogiDeviceSession.featureUnifiedBattery]?.0, "UnifiedBattery")
        XCTAssertEqual(HIDPPInfo.featureNames[LogiDeviceSession.featureBatteryStatus]?.0, "BatteryStatus")
        XCTAssertEqual(HIDPPInfo.featureNames[LogiDeviceSession.featureAdjustableDPI]?.0, "AdjustableDPI")
    }
}
