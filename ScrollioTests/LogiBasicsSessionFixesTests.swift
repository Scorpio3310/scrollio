import XCTest
@testable import Scrollio_Debug

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

    // MARK: - The toggle actions that were removed (0x2121 wheel mode, 0x2150 thumb wheel)

    /// "Toggle Hi-Res Scrolling", "Invert Scrolling" and "Toggle Thumb Wheel" changed a
    /// state of the mouse that nothing showed and nothing put back at Pause or Quit (the
    /// thumb wheel stayed dead). They are gone: a stored binding that names one resolves to
    /// no action, so pressing its button writes nothing and does nothing. (This replaces the
    /// test of the bytes those toggles wrote.)
    func testTheRemovedToggleActionsResolveToNothing() {
        for name in ["logiHiResScrollToggle", "logiScrollInvertToggle", "logiThumbWheelToggle"] {
            XCTAssertNil(LogiButtonAction(name: name), name)
            XCTAssertTrue(LogiButtonAction.removedNames.contains(name), name)
        }
        XCTAssertNil(LogiButtonAction(name: "logiSomethingNobodyKnows"))
        XCTAssertNil(LogiButtonAction(name: ""))
    }

    func testTheActionsThatStayKeepTheirNames() {
        XCTAssertEqual(LogiButtonAction(name: "logiSmartShiftToggle"), .smartShiftToggle)
        XCTAssertEqual(LogiButtonAction(name: "logiDPICycleUp"), .dpiCycleUp)
        XCTAssertEqual(LogiButtonAction(name: "logiDPICycleDown"), .dpiCycleDown)
        XCTAssertEqual(LogiButtonAction(name: "logiHost1"), .host(0))
        XCTAssertEqual(LogiButtonAction(name: "logiHost2"), .host(1))
        XCTAssertEqual(LogiButtonAction(name: "logiHost3"), .host(2))
        XCTAssertEqual(LogiButtonAction(name: "logiPointerSpeedCycle"), .pointerSpeedCycle)
    }

    /// The removed actions are no longer offered in the action list of the Buttons pane.
    func testTheRemovedToggleActionsAreNotOffered() {
        let offered = Set(SystemShortcut.logiActionsCategory.shortcuts.map(\.identifier))
        XCTAssertTrue(offered.isDisjoint(with: LogiButtonAction.removedNames), "\(offered.sorted())")
        for name in offered {
            XCTAssertNotNil(LogiButtonAction(name: name), "\(name) is offered but runs nothing")
        }
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

    // MARK: - Button actions that read before they write

    /// A press whose read got no answer used to stay armed for the whole connection: the
    /// next answer to any read of that value (minutes later, from the Mouse pane) ran it.
    func testAPressThatGotNoAnswerDoesNotRunLater() {
        var pending = LogiPendingActions()
        let pressed = Date(timeIntervalSince1970: 5_000)
        pending.arm(.dpiCurrent, now: pressed)
        XCTAssertTrue(pending.isArmed(.dpiCurrent))
        XCTAssertFalse(pending.take(.dpiCurrent, now: pressed.addingTimeInterval(120)), "two minutes later: not the press's answer")
        XCTAssertFalse(pending.isArmed(.dpiCurrent), "and it waits no longer")

        pending.arm(.pointerSpeed, now: pressed)
        XCTAssertTrue(pending.take(.pointerSpeed, now: pressed.addingTimeInterval(0.3)), "the answer of the press")
        XCTAssertFalse(pending.take(.pointerSpeed, now: pressed.addingTimeInterval(0.4)), "only once")
        XCTAssertFalse(pending.take(.dpiList, now: pressed), "never armed")

        pending.arm(.dpiList, now: pressed)
        pending.cancelAll()
        XCTAssertFalse(pending.take(.dpiList, now: pressed))
        XCTAssertEqual(LogiPendingActions.lifetime, 2)
    }

    // MARK: - Increase / Decrease Pointer Speed

    /// An MX Master lists 200...8000 in steps of 50. One press used to move to the next
    /// value of that list: 1600 to 1650, which nobody feels.
    func testOnePressMovesThePointerSpeedByAStepThatCanBeFelt() {
        let fine = Array(stride(from: 200, through: 8000, by: 50))
        XCTAssertEqual(LogiPointerSpeedProtocol.cycleTarget(from: 1600, up: true, choices: fine), 2000)
        XCTAssertEqual(LogiPointerSpeedProtocol.cycleTarget(from: 1600, up: false, choices: fine), 1200)
        XCTAssertEqual(LogiPointerSpeedProtocol.cycleTarget(from: 1650, up: true, choices: fine), 2000, "from a value between two stops")
        XCTAssertEqual(LogiPointerSpeedProtocol.cycleTarget(from: 1650, up: false, choices: fine), 1600)
        XCTAssertEqual(LogiPointerSpeedProtocol.cycleTarget(from: 4000, up: true, choices: fine), 6000)
        XCTAssertEqual(LogiPointerSpeedProtocol.cycleTarget(from: 8000, up: true, choices: fine), nil, "at the top: nothing is written")
        XCTAssertEqual(LogiPointerSpeedProtocol.cycleTarget(from: 400, up: false, choices: fine), 200, "the mouse's lowest value is a stop")
        XCTAssertEqual(LogiPointerSpeedProtocol.cycleTarget(from: 200, up: false, choices: fine), nil)
        XCTAssertEqual(LogiPointerSpeedProtocol.cycleStops(for: fine), [200, 400, 800, 1000, 1200, 1600, 2000, 2400, 3200, 4000, 6000, 8000])
    }

    func testAShortListIsItsOwnSetOfStops() {
        let presets = [400, 800, 1600, 3200]
        XCTAssertEqual(LogiPointerSpeedProtocol.cycleStops(for: presets), presets)
        XCTAssertEqual(LogiPointerSpeedProtocol.cycleTarget(from: 800, up: true, choices: presets), 1600)
        XCTAssertEqual(LogiPointerSpeedProtocol.cycleTarget(from: 800, up: false, choices: presets), 400)
        XCTAssertEqual(LogiPointerSpeedProtocol.cycleTarget(from: 3200, up: true, choices: presets), nil)
        XCTAssertEqual(LogiPointerSpeedProtocol.cycleTarget(from: 800, up: true, choices: []), nil)
    }

    /// Every stop is a value the mouse accepts (a range that does not hold the round numbers).
    func testEveryStopIsAValueTheMouseAccepts() {
        let odd = Array(stride(from: 250, through: 5250, by: 125))
        let stops = LogiPointerSpeedProtocol.cycleStops(for: odd)
        XCTAssertTrue(stops.allSatisfy(odd.contains), "\(stops)")
        XCTAssertEqual(stops.first, 250)
        XCTAssertEqual(stops.last, 5250)
        XCTAssertEqual(stops, stops.sorted())
    }

    // MARK: - Logitech Diagnostics in a Release build

    /// Without device writes the window keeps the buttons that read or are local. "Re-Divert",
    /// "Undivert All" and "Enumerate" wrote to the mouse in a Release build whatever "Let
    /// Scrollio manage this mouse" said ("Undivert All" also left every Logitech button
    /// binding dead until the next discovery).
    func testWithoutDeviceWritesTheDiagnosticsWindowOffersNoButtonThatChangesTheMouse() {
        XCTAssertEqual(HIDPPFeatureActions.globalActions(offeringWrites: false).map(\.rawValue), ["Re-Discover", "Clear Log"])
        XCTAssertEqual(
            HIDPPFeatureActions.globalActions(offeringWrites: true).map(\.rawValue),
            ["Re-Discover", "Re-Divert", "Undivert All", "Enumerate", "Clear Log"]
        )
        XCTAssertTrue(HIDPPFeatureActions.GlobalAction.undivertAll.changesDevice)
        XCTAssertFalse(HIDPPFeatureActions.GlobalAction.rediscover.changesDevice)
    }

    // MARK: - Toasts

    /// A toast names a button as the Buttons pane does; the name comes in through the bridge.
    func testAToastCallsAButtonWhatTheButtonsPaneCallsIt() {
        let pane: (UInt16) -> String? = { code in
            switch code {
            case 1001: return "Mode shift button"
            case 1006: return "Back button"
            default: return "Button \(code)"
            }
        }
        XCTAssertEqual(LogiToastText.buttonName(forCID: 0x00C4, paneName: pane), "Mode shift button")
        XCTAssertEqual(LogiToastText.buttonName(forCID: 0x0053, paneName: pane), "Back button")
        // A control the directory has no name for is never shown as "Unknown(0x…)".
        XCTAssertFalse(LogiCIDDirectory.hasName(forCID: 0x0FFF))
        XCTAssertNil(LogiToastText.buttonName(forCID: 0x0FFF, paneName: pane))
        XCTAssertNil(LogiToastText.buttonName(forCID: 0x00C4, paneName: { _ in nil }), "the app has no name")
    }

    func testAToastAboutAButtonWithoutANameSaysAButton() {
        let english: [String: String] = [
            "logi_ble_hidpp_unstable_toast": "%@ may stop working while Logi Options+ runs.",
            "logi_hidpp_contention_toast": "Logi Options+ keeps taking over %@.",
            "logi-toast-a-button": "a button",
            "logi-toast-a-button-start": "A button",
        ]
        let localized: (String) -> String = { english[$0] ?? $0 }
        XCTAssertEqual(
            LogiToastText.buttonToast(formatKey: "logi_ble_hidpp_unstable_toast", buttonName: nil, localized: localized),
            "A button may stop working while Logi Options+ runs."
        )
        XCTAssertEqual(
            LogiToastText.buttonToast(formatKey: "logi_hidpp_contention_toast", buttonName: nil, localized: localized),
            "Logi Options+ keeps taking over a button."
        )
        XCTAssertEqual(
            LogiToastText.buttonToast(formatKey: "logi_hidpp_contention_toast", buttonName: "Back button", localized: localized),
            "Logi Options+ keeps taking over Back button."
        )
    }

    /// The texts of the catalog: no raw key, a full stop, the feature in the panes' words.
    func testTheToastTextsOfTheCatalog() {
        XCTAssertEqual(
            LogiToastText.featureNotAvailable(mouse: "MX Master 3S", feature: .haptics),
            "MX Master 3S does not support haptic feedback."
        )
        XCTAssertEqual(
            LogiToastText.featureNotAvailable(mouse: "MX Anywhere 3S", feature: .pointerSpeed),
            "MX Anywhere 3S does not support pointer speed steps."
        )
        for feature in [LogiToastText.MissingFeature.pointerSpeed, .haptics, .wheelForce, .pressForce] {
            let text = NSLocalizedString(feature.catalogKey, comment: "")
            XCTAssertNotEqual(text, feature.catalogKey, "missing in the catalog")
            XCTAssertFalse(text.isEmpty)
        }
        XCTAssertEqual(
            LogiToastText.buttonToast(formatKey: "logi_ble_hidpp_unstable_toast", buttonName: "Mode shift button"),
            "Mode shift button may stop working while Logi Options+ runs. Connect the mouse with its Logitech receiver, or quit Logi Options+."
        )
        XCTAssertEqual(
            LogiToastText.buttonToast(formatKey: "logi_ble_hidpp_unstable_toast", buttonName: nil),
            "A button may stop working while Logi Options+ runs. Connect the mouse with its Logitech receiver, or quit Logi Options+."
        )
        XCTAssertEqual(
            LogiToastText.buttonToast(formatKey: "logi_hidpp_contention_toast", buttonName: nil),
            "Logi Options+ keeps taking over a button."
        )
    }

    /// The bridge of the app answers with the Buttons pane's own names.
    func testTheAppsBridgeNamesButtonsAsTheButtonsPaneDoes() {
        XCTAssertEqual(LogiIntegrationBridge.shared.logiButtonName(forScrollioCode: 1001), ButtonTriggerNaming.buttonName(code: 1001))
        XCTAssertEqual(LogiIntegrationBridge.shared.logiButtonName(forScrollioCode: 1006), ButtonTriggerNaming.buttonName(code: 1006))
        XCTAssertEqual(ButtonTriggerNaming.buttonName(code: 1001), "Mode shift button")
        XCTAssertEqual(ButtonTriggerNaming.buttonName(code: 1006), "Back button")
    }

    // MARK: - The diagnostics log's words for the reporting flags

    func testTheReportingFlagsAreNamedAsTheyAre() {
        XCTAssertEqual(LogiDeviceSession.reportingFlagNames(0x00), [])
        XCTAssertEqual(LogiDeviceSession.reportingFlagNames(0x01), ["divert"])
        XCTAssertEqual(LogiDeviceSession.reportingFlagNames(0x04), ["persistDivert"], "bit 2, which used to be shown as a remap")
        XCTAssertEqual(LogiDeviceSession.reportingFlagNames(0x11), ["divert", "rawXY"])
        XCTAssertEqual(LogiDeviceSession.reportingFlagNames(0x0A), ["0x0A"], "bits without a known meaning by their value")
    }
}
