import XCTest
@testable import Scrollio_Debug

final class LogiButtonDeliveryModeTests: XCTestCase {

    func testBLEStandardAliasUsesNativeByDefault() {
        let policy = LogiButtonDeliveryPolicy.default

        XCTAssertFalse(policy.shouldUseHIDPPDelivery(
            transport: .bleDirect,
            cid: 0x0053,
            phase: .normal
        ))
    }

    func testBLENonStandardControlUsesHIDPPByDefault() {
        let policy = LogiButtonDeliveryPolicy.default

        XCTAssertTrue(policy.shouldUseHIDPPDelivery(
            transport: .bleDirect,
            cid: 0x00C3,
            phase: .normal
        ))
    }

    func testReceiverStandardAliasStillUsesHIDPP() {
        let policy = LogiButtonDeliveryPolicy.default

        XCTAssertTrue(policy.shouldUseHIDPPDelivery(
            transport: .receiver,
            cid: 0x0053,
            phase: .normal
        ))
    }

    func testInitialModeIsHIDPP() {
        let store = LogiButtonDeliveryModeStore()
        let key = LogiOwnershipKey(
            vendorId: 0x046D,
            productId: 0xB034,
            name: "LIFT",
            transport: .bleDirect,
            cid: 0x0053
        )

        XCTAssertEqual(store.mode(for: key), .hidpp)
    }

    func testRepeatedExternalClearPromotesStandardButtonToContended() {
        let store = LogiButtonDeliveryModeStore(clearWindow: 5, clearThreshold: 2)
        let key = LogiOwnershipKey(
            vendorId: 0x046D,
            productId: 0xB034,
            name: "LIFT",
            transport: .bleDirect,
            cid: 0x0053
        )
        let t0 = Date(timeIntervalSince1970: 100)

        XCTAssertEqual(store.recordExternalClear(for: key, at: t0), .hidpp)
        XCTAssertEqual(store.recordExternalClear(for: key, at: t0.addingTimeInterval(1)), .contended)
    }

    func testRepeatedExternalClearPromotesNonStandardCIDToContended() {
        let store = LogiButtonDeliveryModeStore(clearWindow: 5, clearThreshold: 2)
        let key = LogiOwnershipKey(
            vendorId: 0x046D,
            productId: 0xB034,
            name: "LIFT",
            transport: .bleDirect,
            cid: 0x00C3
        )
        let t0 = Date(timeIntervalSince1970: 100)

        _ = store.recordExternalClear(for: key, at: t0)
        XCTAssertEqual(store.recordExternalClear(for: key, at: t0.addingTimeInterval(1)), .contended)
    }

    func testClearWindowResetsAfterInterval() {
        let store = LogiButtonDeliveryModeStore(clearWindow: 5, clearThreshold: 2)
        let key = LogiOwnershipKey(
            vendorId: 0x046D,
            productId: 0xB034,
            name: "LIFT",
            transport: .bleDirect,
            cid: 0x0053
        )
        let t0 = Date(timeIntervalSince1970: 100)

        XCTAssertEqual(store.recordExternalClear(for: key, at: t0), .hidpp)
        XCTAssertEqual(store.recordExternalClear(for: key, at: t0.addingTimeInterval(6)), .hidpp)
    }

    func testDefaultClearWindowTreatsRecentExternalClearsAsContention() {
        let store = LogiButtonDeliveryModeStore()
        let key = LogiOwnershipKey(
            vendorId: 0x046D,
            productId: 0xB034,
            name: "LIFT",
            transport: .bleDirect,
            cid: 0x0053
        )
        let t0 = Date(timeIntervalSince1970: 100)

        XCTAssertEqual(store.recordExternalClear(for: key, at: t0), .hidpp)
        XCTAssertEqual(store.recordExternalClear(for: key, at: t0.addingTimeInterval(15)), .contended)
    }

    func testDeliveryModeLookupByScrollioCodeUsesActiveMode() {
        let store = LogiButtonDeliveryModeStore()
        let key = LogiOwnershipKey(
            vendorId: 0x046D,
            productId: 0xB034,
            name: "LIFT",
            transport: .bleDirect,
            cid: 0x0053
        )
        let t0 = Date(timeIntervalSince1970: 100)
        _ = store.recordExternalClear(for: key, at: t0)
        _ = store.recordExternalClear(for: key, at: t0.addingTimeInterval(1))

        XCTAssertEqual(store.deliveryMode(forScrollioCode: 1006, matching: [key]), .contended)
        XCTAssertNil(store.deliveryMode(forScrollioCode: 1007, matching: [key]))
    }

    func testDefaultButtonDeliveryPolicyUsesTwoSecondStandardUndivertGuardInterval() {
        XCTAssertEqual(LogiButtonDeliveryPolicy.default.standardButtonUndivertGuardInterval, 2)
    }

    func testDefaultButtonDeliveryPolicyDisablesStandardUndivertGuard() {
        XCTAssertFalse(LogiButtonDeliveryPolicy.default.standardButtonUndivertGuardEnabled)
        XCTAssertTrue(LogiButtonDeliveryPolicy.default.standardMouseButtonsUseNativeEvents)
    }

    /// Three preference keys that nothing documented used to change what is written to a
    /// mouse (the guard on, its interval, the standard buttons diverted over Bluetooth).
    /// They are no longer read: a value stored under them changes nothing. (This replaces
    /// the test that a stored key switches the guard on.)
    func testTheOldHiddenPreferenceKeysNoLongerChangeThePolicy() {
        let stored: [String: Any] = [
            "LogiBLEStandardUndivertGuardEnabled": true,
            "LogiBLEStandardUndivertGuardInterval": 0.001,
            "LogiBLEStandardButtonsNativeFirst": false,
        ]
        // In memory only (the argument domain, which every read of the app's preferences
        // looks at first): a reader would see the values, and nothing is written to the
        // debug app's real preferences.
        let defaults = UserDefaults.standard
        let arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defaults.removeVolatileDomain(forName: UserDefaults.argumentDomain)
        defaults.setVolatileDomain(arguments.merging(stored) { _, new in new }, forName: UserDefaults.argumentDomain)
        defer {
            defaults.removeVolatileDomain(forName: UserDefaults.argumentDomain)
            defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        }
        XCTAssertTrue(defaults.bool(forKey: "LogiBLEStandardUndivertGuardEnabled"), "a reader of the preferences would see it")
        XCTAssertEqual(defaults.double(forKey: "LogiBLEStandardUndivertGuardInterval"), 0.001)

        let policy = LogiButtonDeliveryPolicy.default
        XCTAssertFalse(policy.standardButtonUndivertGuardEnabled)
        XCTAssertEqual(policy.standardButtonUndivertGuardInterval, 2)
        XCTAssertTrue(policy.standardMouseButtonsUseNativeEvents)
    }

    /// Whoever builds a policy cannot make the guard write faster than twice a second.
    func testTheGuardIntervalHasAFloor() {
        let policy = LogiButtonDeliveryPolicy(
            standardMouseButtonsUseNativeEvents: true,
            standardButtonUndivertGuardEnabled: true,
            standardButtonUndivertGuardInterval: 0.001
        )
        XCTAssertEqual(policy.standardButtonUndivertGuardInterval, LogiButtonDeliveryPolicy.minimumGuardInterval)
        XCTAssertEqual(LogiButtonDeliveryPolicy.minimumGuardInterval, 0.5)
    }

    /// Pause, sleep and Quit end every connection: what was found "taken over by another
    /// app" on it is forgotten, so the button is diverted again at the next start.
    func testStoppingForgetsTheContendedControls() {
        let store = LogiButtonDeliveryModeStore(clearWindow: 30, clearThreshold: 2)
        let key = LogiOwnershipKey(vendorId: 0x046D, productId: 0xB034, name: "MX", transport: .bleDirect, cid: 0x00C4)
        let t0 = Date(timeIntervalSince1970: 100)
        _ = store.recordExternalClear(for: key, at: t0)
        XCTAssertFalse(store.removeAll(), "one count is no contention yet")
        _ = store.recordExternalClear(for: key, at: t0.addingTimeInterval(1))
        XCTAssertEqual(store.mode(for: key), .hidpp, "the count started again after removeAll")
        _ = store.recordExternalClear(for: key, at: t0.addingTimeInterval(2))
        XCTAssertEqual(store.mode(for: key), .contended)

        XCTAssertTrue(store.removeAll())
        XCTAssertEqual(store.mode(for: key), .hidpp)
        XCTAssertEqual(store.recordExternalClear(for: key, at: t0.addingTimeInterval(3)), .hidpp, "the count starts at one again")
    }

    func testDiagnosisSessionPreferenceFollowsCurrentTransport() {
        let connectedReceiverRank = LogiSessionManager.diagnosisSessionRankForTests(
            transport: .receiver,
            receiverTargetConnected: true
        )
        let bleRank = LogiSessionManager.diagnosisSessionRankForTests(
            transport: .bleDirect,
            receiverTargetConnected: true
        )
        let disconnectedReceiverRank = LogiSessionManager.diagnosisSessionRankForTests(
            transport: .receiver,
            receiverTargetConnected: false
        )
        let unsupportedRank = LogiSessionManager.diagnosisSessionRankForTests(
            transport: .unsupported,
            receiverTargetConnected: false
        )

        XCTAssertLessThan(connectedReceiverRank, bleRank)
        XCTAssertLessThan(bleRank, disconnectedReceiverRank)
        XCTAssertLessThan(disconnectedReceiverRank, unsupportedRank)
    }

    func testStandardButtonUndivertPlannerClearsOnlyActiveTemporarilyDivertedTargets() {
        let planner = LogiBLEStandardButtonUndivertPlanner()

        let targets = planner.undivertTargets(
            activeNativeFirstCIDs: [0x0053, 0x0056],
            reportingFlagsByCID: [
                0x0053: 0x01,
                0x0056: 0x00,
                0x00FD: 0x01,
            ]
        )

        XCTAssertEqual(targets, [0x0053])
    }

    func testStandardButtonUndivertPlannerBuildsTargetedReportingQueries() {
        let planner = LogiBLEStandardButtonUndivertPlanner()

        let probes = planner.reportingQueryProbes(
            activeTargets: [0x00FD, 0x00D7],
            reprogFeatureIndex: 0x09
        )

        XCTAssertEqual(probes.map(\.targetCID), [0x00D7, 0x00FD])
        XCTAssertEqual(probes.map(\.featureIndex), [0x09, 0x09])
        XCTAssertEqual(probes.map(\.functionId), [2, 2])
        XCTAssertEqual(probes.map(\.params), [
            [0x00, 0xD7],
            [0x00, 0xFD],
        ])
    }

    func testStandardButtonUndivertPlannerDoesNotBuildReportingQueriesWithoutReprogFeature() {
        let planner = LogiBLEStandardButtonUndivertPlanner()

        let probes = planner.reportingQueryProbes(
            activeTargets: [0x00FD],
            reprogFeatureIndex: nil
        )

        XCTAssertTrue(probes.isEmpty)
    }

    func testDefaultRecordingStillDispatchesHIDPPRecordingEvents() {
        let manager = LogiSessionManager()

        manager.temporarilyDivertAll()

        XCTAssertTrue(manager.isRecording)
    }
}
