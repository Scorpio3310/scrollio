import XCTest
@testable import Scrollio_Debug

final class LogiDivertReconciliationTests: XCTestCase {

    func testQueriedMissingDivertIsRemovedFromAppliedAndDivertedCIDs() {
        let result = LogiDeviceSession.reconciledDivertStateForTests(
            lastApplied: [0x0053, 0x0056],
            divertedCIDs: [0x0053, 0x0056, 0x0057],
            queriedControls: [
                .init(cid: 0x0053, reportingFlags: 0x00, reportingQueried: true),
                .init(cid: 0x0056, reportingFlags: 0x01, reportingQueried: true)
            ]
        )

        XCTAssertEqual(result.lastApplied, [0x0056])
        XCTAssertEqual(result.divertedCIDs, [0x0056, 0x0057])
    }

    func testStillDivertedCIDIsKept() {
        let result = LogiDeviceSession.reconciledDivertStateForTests(
            lastApplied: [0x0053],
            divertedCIDs: [0x0053],
            queriedControls: [
                .init(cid: 0x0053, reportingFlags: 0x01, reportingQueried: true)
            ]
        )

        XCTAssertEqual(result.lastApplied, [0x0053])
        XCTAssertEqual(result.divertedCIDs, [0x0053])
    }

    func testUnqueriedCIDIsKept() {
        let result = LogiDeviceSession.reconciledDivertStateForTests(
            lastApplied: [0x0053],
            divertedCIDs: [0x0053],
            queriedControls: [
                .init(cid: 0x0053, reportingFlags: 0x00, reportingQueried: false)
            ]
        )

        XCTAssertEqual(result.lastApplied, [0x0053])
        XCTAssertEqual(result.divertedCIDs, [0x0053])
    }

    func testStaleAppliedCIDAbsentFromQueriedControlsIsKept() {
        let result = LogiDeviceSession.reconciledDivertStateForTests(
            lastApplied: [0x0053, 0x9999],
            divertedCIDs: [0x0053, 0x9999],
            queriedControls: [
                .init(cid: 0x0053, reportingFlags: 0x01, reportingQueried: true)
            ]
        )

        XCTAssertEqual(result.lastApplied, [0x0053, 0x9999])
        XCTAssertEqual(result.divertedCIDs, [0x0053, 0x9999])
    }

    func testForeignSetControlReportingAckClearingOwnedDivertRequiresReassertion() {
        let cid = LogiDeviceSession.reassertionCIDForSetControlReportingAckForTests(
            lastApplied: [0x0053],
            divertedCIDs: [0x0053],
            ackBytes: [0x11, 0xFF, 0x09, 0x31, 0x00, 0x53, 0x02, 0x00, 0x00],
            isOwnAck: false
        )

        XCTAssertEqual(cid, 0x0053)
    }

    func testOwnSetControlReportingAckClearingDivertDoesNotRequireReassertion() {
        let cid = LogiDeviceSession.reassertionCIDForSetControlReportingAckForTests(
            lastApplied: [0x0053],
            divertedCIDs: [0x0053],
            ackBytes: [0x11, 0xFF, 0x09, 0x31, 0x00, 0x53, 0x02, 0x00, 0x00],
            isOwnAck: true
        )

        XCTAssertNil(cid)
    }

    func testSetControlReportingAckKeepingDivertDoesNotRequireReassertion() {
        let cid = LogiDeviceSession.reassertionCIDForSetControlReportingAckForTests(
            lastApplied: [0x0053],
            divertedCIDs: [0x0053],
            ackBytes: [0x11, 0xFF, 0x09, 0x31, 0x00, 0x53, 0x03, 0x00, 0x00],
            isOwnAck: false
        )

        XCTAssertNil(cid)
    }

    func testReportingNotificationClearingOwnedDivertRequiresReassertion() {
        let cid = LogiDeviceSession.reassertionCIDForReportingStateForTests(
            lastApplied: [0x0053],
            divertedCIDs: [0x0053],
            bytes: [0x11, 0xFF, 0x09, 0x20, 0x00, 0x53, 0x00, 0x00, 0x00]
        )

        XCTAssertEqual(cid, 0x0053)
    }

    func testReportingNotificationKeepingDivertDoesNotRequireReassertion() {
        let cid = LogiDeviceSession.reassertionCIDForReportingStateForTests(
            lastApplied: [0x0053],
            divertedCIDs: [0x0053],
            bytes: [0x11, 0xFF, 0x09, 0x20, 0x00, 0x53, 0x01, 0x00, 0x00]
        )

        XCTAssertNil(cid)
    }

    func testExternalClearReassertsOnlyWhileHIDPPModeIsActive() {
        XCTAssertTrue(LogiDeviceSession.shouldReassertAfterExternalClearForTests(mode: .hidpp))
        XCTAssertFalse(LogiDeviceSession.shouldReassertAfterExternalClearForTests(mode: .contended))
    }

    func testUsageProjectionSkipsCIDsOutsideHIDPPDeliveryMode() {
        let target = LogiDeviceSession.targetCIDsForUsageForTests(
            aggregateScrollioCodes: [1006, 1007],
            divertableCIDs: [0x0053, 0x0056],
            deliveryModeForCID: { cid in
                cid == 0x0053 ? .contended : .hidpp
            }
        )

        XCTAssertEqual(target, [0x0056])
    }

    func testBLEPolicyExcludesNativeBackFromNormalTargets() {
        let target = LogiDeviceSession.targetCIDsForUsageForTests(
            aggregateScrollioCodes: [1006, 1002],
            divertableCIDs: [0x0053, 0x00D7],
            transport: .bleDirect,
            phase: .normal,
            policy: LogiButtonDeliveryPolicy(standardMouseButtonsUseNativeEvents: true),
            deliveryModeForCID: { _ in .hidpp }
        )

        XCTAssertEqual(target, [0x00D7])
    }

    func testBLEPolicyMarksNativeBackForNormalUndivertEvenWhenTargetExcludesIt() {
        let nativeFirst = LogiDeviceSession.nativeFirstCIDsForUsageForTests(
            aggregateScrollioCodes: [1006, 1002],
            divertableCIDs: [0x0053, 0x00D7],
            transport: .bleDirect,
            phase: .normal,
            policy: LogiButtonDeliveryPolicy(standardMouseButtonsUseNativeEvents: true)
        )

        XCTAssertEqual(nativeFirst, [0x0053])
    }

    func testBLEPolicyMarksRecordedNativeSideButtonsForNormalUndivert() {
        let nativeFirst = LogiDeviceSession.nativeFirstCIDsForUsageForTests(
            aggregateScrollioCodes: [3, 4, 2253],
            divertableCIDs: [0x0053, 0x0056, 0x00FD],
            transport: .bleDirect,
            phase: .normal,
            policy: LogiButtonDeliveryPolicy(standardMouseButtonsUseNativeEvents: true)
        )

        XCTAssertEqual(nativeFirst, [0x0053, 0x0056])
    }

    func testReceiverPolicyKeepsNativeBackInNormalTargets() {
        let target = LogiDeviceSession.targetCIDsForUsageForTests(
            aggregateScrollioCodes: [1006, 1002],
            divertableCIDs: [0x0053, 0x00D7],
            transport: .receiver,
            phase: .normal,
            policy: LogiButtonDeliveryPolicy(standardMouseButtonsUseNativeEvents: true),
            deliveryModeForCID: { _ in .hidpp }
        )

        XCTAssertEqual(target, [0x0053, 0x00D7])
    }

    func testRecordingPlannerUndivertsPreviouslyAppliedBLEStandardAlias() {
        let result = LogiDeviceSession.recordingDivertPlanForTests(
            divertableCIDs: [0x0053, 0x00D7],
            lastApplied: [0x0053],
            transport: .bleDirect,
            policy: LogiButtonDeliveryPolicy(standardMouseButtonsUseNativeEvents: true)
        )

        XCTAssertEqual(result.desired, [0x00D7])
        XCTAssertEqual(result.toDivert, [0x00D7])
        XCTAssertEqual(result.toUndivert, [0x0053])
    }

    func testRecordingPlannerProactivelyUndivertsBLEStandardAliasesEvenWhenNotLastApplied() {
        let result = LogiDeviceSession.recordingDivertPlanForTests(
            divertableCIDs: [0x0053, 0x0056, 0x00D7],
            lastApplied: [0x00D7],
            transport: .bleDirect,
            policy: LogiButtonDeliveryPolicy(standardMouseButtonsUseNativeEvents: true)
        )

        XCTAssertEqual(result.desired, [0x00D7])
        XCTAssertEqual(result.toDivert, [])
        XCTAssertEqual(result.toUndivert, [0x0053, 0x0056])
    }

    func testRecordingPlannerKeepsReceiverStandardAlias() {
        let result = LogiDeviceSession.recordingDivertPlanForTests(
            divertableCIDs: [0x0053, 0x00D7],
            lastApplied: [0x0053],
            transport: .receiver,
            policy: LogiButtonDeliveryPolicy(standardMouseButtonsUseNativeEvents: true)
        )

        XCTAssertEqual(result.desired, [0x0053, 0x00D7])
        XCTAssertEqual(result.toDivert, [0x00D7])
        XCTAssertEqual(result.toUndivert, [])
    }

    // MARK: - Stale diverts left by an earlier run

    /// What a connection reads after a crash during key recording: every divertable control
    /// still diverted (0x00C4 also with raw XY), one control unread, one diverted persistently
    /// (never Scrollio's), the bound gesture button wanted.
    private let afterACrash: [LogiDeviceSession.QueriedControlState] = [
        .init(cid: 0x00C3, reportingFlags: 0x01, reportingQueried: true),
        .init(cid: 0x00C4, reportingFlags: 0x11, reportingQueried: true),
        .init(cid: 0x0053, reportingFlags: 0x01, reportingQueried: true),
        .init(cid: 0x0056, reportingFlags: 0x00, reportingQueried: true),
        .init(cid: 0x00D7, reportingFlags: 0x01, reportingQueried: false),
        .init(cid: 0x00C5, reportingFlags: 0x02, reportingQueried: true),
    ]

    func testALeftoverDivertIsGivenBackWhileTheMouseIsManaged() {
        let decision = LogiDeviceSession.staleDivertDecision(
            queriedControls: afterACrash,
            wanted: [0x00C3],
            undivertedAnyway: [],
            managed: true,
            recording: false
        )
        XCTAssertEqual(decision.giveBack, [0x00C4, 0x0053])
        XCTAssertEqual(decision.leftAlone, [])
    }

    /// Without "Let Scrollio manage this mouse" a divert Scrollio does not want may be
    /// another app's: nothing is written, the leftovers are only named in the log.
    func testWhileTheMouseIsNotManagedLeftoversAreLeftAlone() {
        let decision = LogiDeviceSession.staleDivertDecision(
            queriedControls: afterACrash,
            wanted: [0x00C3],
            undivertedAnyway: [],
            managed: false,
            recording: false
        )
        XCTAssertEqual(decision.giveBack, [])
        XCTAssertEqual(decision.leftAlone, [0x00C4, 0x0053])
    }

    /// The ordinary connection: nothing is diverted but what Scrollio wants, so nothing is
    /// added to the writes and no line is logged.
    func testNothingStaleAddsNoWrite() {
        let decision = LogiDeviceSession.staleDivertDecision(
            queriedControls: [
                .init(cid: 0x00C3, reportingFlags: 0x01, reportingQueried: true),
                .init(cid: 0x00C4, reportingFlags: 0x00, reportingQueried: true),
                .init(cid: 0x0053, reportingFlags: 0x00, reportingQueried: true),
            ],
            wanted: [0x00C3],
            undivertedAnyway: [0x0053],
            managed: true,
            recording: false
        )
        XCTAssertEqual(decision, LogiDeviceSession.StaleDivertDecision())
        XCTAssertNil(LogiDeviceSession.staleDivertLine(decision, name: LogiCIDDirectory.name(forCID:)))
    }

    /// A control the usual writes give back anyway (a Bluetooth standard button delivered
    /// natively) is not written twice.
    func testAControlGivenBackAnywayIsNotWrittenTwice() {
        let decision = LogiDeviceSession.staleDivertDecision(
            queriedControls: afterACrash,
            wanted: [0x00C3],
            undivertedAnyway: [0x0053],
            managed: true,
            recording: false
        )
        XCTAssertEqual(decision.giveBack, [0x00C4])
    }

    /// While keys are recorded Scrollio may want every divertable control diverted.
    func testNothingIsTouchedWhileKeysAreRecorded() {
        for managed in [true, false] {
            let decision = LogiDeviceSession.staleDivertDecision(
                queriedControls: afterACrash,
                wanted: [0x00C3],
                undivertedAnyway: [],
                managed: managed,
                recording: true
            )
            XCTAssertEqual(decision, LogiDeviceSession.StaleDivertDecision())
        }
    }

    func testTheStaleDivertLines() {
        let name: (UInt16) -> String = { $0 == 0x00C4 ? "Smart Shift" : "Back" }
        XCTAssertEqual(
            LogiDeviceSession.staleDivertLine(.init(giveBack: [0x00C4, 0x0053]), name: name),
            "Gave back 2 buttons the mouse still had diverted from an earlier run (Scrollio does not use them; "
                + "manage switch on): 0x0053 Back, 0x00C4 Smart Shift"
        )
        XCTAssertEqual(
            LogiDeviceSession.staleDivertLine(.init(leftAlone: [0x00C4]), name: name),
            "Left 1 button diverted that Scrollio does not use (manage switch off: another app may use it; "
                + "a leftover is freed by switching the mouse off and on): 0x00C4 Smart Shift"
        )
    }
}
