import XCTest
@testable import Scrollio_Debug

final class LogiDivertReconciliationTests: XCTestCase {

    /// The ledger's lines, here instead of the system log.
    private var ledgerLines: [String] = []
    private var realLedgerLog: ((String) -> Void)?

    override func setUp() {
        super.setUp()
        realLedgerLog = LogiDivertLedger.log
        LogiDivertLedger.log = { [weak self] in self?.ledgerLines.append($0) }
    }

    override func tearDown() {
        if let log = realLedgerLog { LogiDivertLedger.log = log }
        super.tearDown()
    }

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

    // MARK: - Recording while the buttons' state is being re-read (LogiDivertLedger)

    private func queried(_ cid: UInt16, diverted: Bool) -> LogiDeviceSession.QueriedControlState {
        return .init(cid: cid, reportingFlags: diverted ? 0x01 : 0x00, reportingQueried: true)
    }

    /// The Buttons pane re-reads the buttons' state (one query after the other) and the user
    /// presses "+" in the middle: every divertable button is diverted for the recorder. The
    /// answers that were asked for before those writes say "not diverted". They used to make
    /// Scrollio forget the buttons it had just diverted, and nothing gave those back any
    /// more: not the end of the recording, not Pause, not Quit.
    func testARecordingThatBeginsDuringAReReadForgetsNoButton() {
        let gesture: UInt16 = 0x00C3, middle: UInt16 = 0x0052, back: UInt16 = 0x0053, modeShift: UInt16 = 0x00C4
        var ledger = LogiDivertLedger()
        ledger.noteWrite(cid: gesture, divert: true)   // the one binding
        ledger.lastApplied = [gesture]

        // The re-read: the gesture and the middle button have answered, the back button's
        // query is on its way.
        ledger.noteQuerySent(cid: gesture)
        ledger.noteQuerySent(cid: middle)
        ledger.noteQuerySent(cid: back)
        var answers = [queried(gesture, diverted: true), queried(middle, diverted: false)]

        // "+": the recording set.
        for cid in [gesture, middle, back, modeShift] {
            ledger.noteWrite(cid: cid, divert: true)
        }
        ledger.lastApplied = [gesture, middle, back, modeShift]

        // The back button's answer was asked for before its write; the mode shift button
        // is asked after it.
        answers.append(queried(back, diverted: false))
        XCTAssertTrue(ledger.answerPredatesAWrite(cid: back))
        ledger.noteQuerySent(cid: modeShift)
        XCTAssertFalse(ledger.answerPredatesAWrite(cid: modeShift))
        answers.append(queried(modeShift, diverted: true))

        XCTAssertEqual(ledger.dropLost(queriedControls: answers), [], "no answer is newer than a write and says 'not diverted'")
        XCTAssertEqual(ledger.diverted, [gesture, middle, back, modeShift])
        XCTAssertEqual(ledger.lastApplied, [gesture, middle, back, modeShift])
        XCTAssertEqual(ledger.toGiveBack, [gesture, middle, back, modeShift], "all four are given back at Pause or Quit")

        // The old rule, which did not know which answers were older than a write, dropped two.
        let old = LogiDeviceSession.reconciledDivertStateForTests(
            lastApplied: [gesture, middle, back, modeShift],
            divertedCIDs: [gesture, middle, back, modeShift],
            queriedControls: answers
        )
        XCTAssertEqual(old.divertedCIDs, [gesture, modeShift])
    }

    /// The rule still does its job: a divert the mouse really dropped (it slept, another app
    /// cleared it) shows in an answer that is newer than Scrollio's write.
    func testADivertTheMouseDroppedIsStillNoticed() {
        var ledger = LogiDivertLedger()
        ledger.noteWrite(cid: 0x00C4, divert: true)
        ledger.noteWrite(cid: 0x00C3, divert: true)
        ledger.lastApplied = [0x00C4, 0x00C3]
        ledger.noteQuerySent(cid: 0x00C4)
        ledger.noteQuerySent(cid: 0x00C3)

        let lost = ledger.dropLost(queriedControls: [queried(0x00C4, diverted: false), queried(0x00C3, diverted: true)])
        XCTAssertEqual(lost, [0x00C4])
        XCTAssertEqual(ledger.diverted, [0x00C3])
        XCTAssertEqual(ledger.lastApplied, [0x00C3])
    }

    /// While a button is being recorded every pass keeps every control diverted (the end of
    /// a re-read used to run a pass for the bindings and give the unbound buttons back under
    /// the recorder), and no re-read is started.
    func testWhileAButtonIsRecordedEveryPassKeepsTheRecordingSet() {
        XCTAssertEqual(LogiDivertLedger.pass(whileRecording: true), .everyControl)
        XCTAssertEqual(LogiDivertLedger.pass(whileRecording: false), .bindings)
        XCTAssertFalse(LogiSessionManager.reportingRefreshMayStart(recording: true))
        XCTAssertTrue(LogiSessionManager.reportingRefreshMayStart(recording: false))
    }

    func testLettingGoGivesBackWhatWasDivertedAndWhatWasWanted() {
        var ledger = LogiDivertLedger()
        ledger.noteWrite(cid: 0x00C3, divert: true)
        ledger.noteWrite(cid: 0x0052, divert: true)
        ledger.noteWrite(cid: 0x0052, divert: false)
        ledger.lastApplied = [0x00C3, 0x00C4]
        XCTAssertEqual(ledger.diverted, [0x00C3])
        XCTAssertEqual(ledger.toGiveBack, [0x00C3, 0x00C4], "one write too many rather than one too few")

        ledger.forgetDiverts()
        XCTAssertEqual(ledger.toGiveBack, [])
    }

    // MARK: - Every mouse of a receiver

    /// A pass over the bindings, the recording set and the give-back at Pause and Quit reach
    /// every mouse a receiver holds, not only the slot the cursor is on.
    func testAPassAndTheGiveBackCoverEveryMouseOfAReceiver() {
        XCTAssertEqual(LogiDeviceSession.usageSlots(connectionMode: .receiver, cursor: 2, managedSlots: [1, 2]), [1, 2])
        XCTAssertEqual(LogiDeviceSession.usageSlots(connectionMode: .receiver, cursor: 3, managedSlots: [1, 2]), [1, 2, 3],
                       "the slot whose discovery just ended is not managed yet")
        XCTAssertEqual(LogiDeviceSession.usageSlots(connectionMode: .bleDirect, cursor: 0xFF, managedSlots: []), [0xFF])

        // The cursor was left on a keyboard (slot 4) by the diagnostics window: the two mice
        // are still given their buttons back.
        XCTAssertEqual(LogiDeviceSession.teardownSlots(known: [1, 2, 4], managed: [1, 2], cursor: 4), [1, 2, 4])
        XCTAssertEqual(LogiDeviceSession.teardownSlots(known: [0xFF], managed: [], cursor: 0xFF), [0xFF])
    }

    // MARK: - Echoes of Scrollio's own writes

    /// A binding removed and put back with Undo: "give back" and "divert" for one control
    /// within the answer time. Both echoes are Scrollio's own. With one remembered write per
    /// control the first echo counted as another app's, and two of those made the toast
    /// "Logi Options+ keeps taking over ..." appear on a Mac without Logi Options+.
    func testGiveBackThenDivertWithinTheAnswerTimeAreBothScrolliosOwn() {
        var ledger = LogiDivertLedger()
        let start = Date(timeIntervalSince1970: 1_000)
        ledger.expectAck(cid: 0x00C4, flags: 0x02, targetCID: 0, now: start)
        ledger.expectAck(cid: 0x00C4, flags: 0x03, targetCID: 0, now: start.addingTimeInterval(0.05))

        let answered = start.addingTimeInterval(0.4)
        XCTAssertTrue(ledger.consumeAck(cid: 0x00C4, flags: 0x02, targetCID: 0, now: answered))
        XCTAssertTrue(ledger.consumeAck(cid: 0x00C4, flags: 0x03, targetCID: 0, now: answered))
        XCTAssertFalse(ledger.consumeAck(cid: 0x00C4, flags: 0x02, targetCID: 0, now: answered), "a third echo is another app's write")
        XCTAssertTrue(ledger.pendingAcks.isEmpty)
    }

    // MARK: - A divert the mouse did not take

    /// The calls `LogiDeviceSession` makes on one slot's ledger, in its order: a write
    /// (`sendControlReporting`: expectAck, then noteWrite), an echo
    /// (`handleSetControlReportingAck`), a re-read of the buttons' state (one
    /// `sendGetControlReporting` per control, then `reconcileAppliedDivertsWithQueriedState`:
    /// dropLost on a copy that is kept only when a control is lost, and one
    /// `recordExternalClear` per lost control), and the pass for the bindings that follows
    /// (`applyUsageToCursorSlot`: what is wanted and not in lastApplied is written, a
    /// control taken over by another app is left out).
    private struct ModelledSlot {
        enum Write: Equatable { case divert(UInt16), giveBack(UInt16) }

        var ledger = LogiDivertLedger()
        let modes: LogiButtonDeliveryModeStore
        var now = Date(timeIntervalSince1970: 1_000)
        private(set) var writes: [Write] = []
        private let productId: UInt16
        private let name: String

        /// `modes`: the manager's store, one for every mouse; `productId` and `name`: which mouse.
        init(modes: LogiButtonDeliveryModeStore = LogiButtonDeliveryModeStore(),
             productId: UInt16 = 0xB034, name: String = "MX Master 3S") {
            self.modes = modes
            self.productId = productId
            self.name = name
        }

        func key(_ cid: UInt16) -> LogiOwnershipKey {
            return LogiOwnershipKey(vendorId: 0x046D, productId: productId, name: name, transport: .receiver, cid: cid)
        }

        mutating func write(_ cid: UInt16, divert: Bool) {
            ledger.expectAck(cid: cid, flags: divert ? 0x03 : 0x02, targetCID: 0, now: now)
            ledger.noteWrite(cid: cid, divert: divert)
            writes.append(divert ? .divert(cid) : .giveBack(cid))
        }

        /// The mouse took a write of Scrollio's and echoed it.
        mutating func echo(_ cid: UInt16, divert: Bool) {
            XCTAssertTrue(ledger.consumeAck(cid: cid, flags: divert ? 0x03 : 0x02, targetCID: 0, now: now))
        }

        mutating func pass(bindings: Set<UInt16>) {
            let target = bindings.filter { modes.mode(for: key($0)) == .hidpp }
            for cid in target.subtracting(ledger.lastApplied).sorted() { write(cid, divert: true) }
            for cid in ledger.lastApplied.subtracting(target).sorted() { write(cid, divert: false) }
            ledger.lastApplied = target
        }

        /// The Buttons pane came forward: every control is asked, the mouse answers what it
        /// has diverted, and a pass for the bindings follows.
        mutating func reRead(controls: [UInt16], divertedOnTheMouse: Set<UInt16>, bindings: Set<UInt16>) {
            for cid in controls { ledger.noteQuerySent(cid: cid) }
            let answers = controls.map {
                LogiDeviceSession.QueriedControlState(
                    cid: $0, reportingFlags: divertedOnTheMouse.contains($0) ? 0x01 : 0x00, reportingQueried: true
                )
            }
            var copy = ledger
            let lost = copy.dropLost(queriedControls: answers)
            if !lost.isEmpty {
                ledger = copy
                for cid in lost.sorted() { modes.recordExternalClear(for: key(cid), at: now) }
            }
            pass(bindings: bindings)
        }
    }

    /// The mouse refuses a divert (asleep, out of range, busy): the write gets no echo, only
    /// a line in the log. The next re-read finds the button not diverted. That used to count
    /// as another app clearing it, and a second re-read within 30 s marked the button as
    /// taken over: a notice, and the button was not diverted again until Pause, sleep or a
    /// reconnect (Mos #1048).
    func testADivertTheMouseDidNotTakeIsWrittenAgainAndIsNotAnotherApps() {
        let gesture: UInt16 = 0x00C3, back: UInt16 = 0x0053
        var slot = ModelledSlot()
        slot.pass(bindings: [gesture])          // refused: no echo
        slot.now += 15
        slot.reRead(controls: [gesture, back], divertedOnTheMouse: [], bindings: [gesture])
        slot.now += 12
        slot.reRead(controls: [gesture, back], divertedOnTheMouse: [], bindings: [gesture])

        XCTAssertEqual(slot.modes.mode(for: slot.key(gesture)), .hidpp, "a write the mouse did not take is not another app's")
        XCTAssertEqual(slot.writes, [.divert(gesture), .divert(gesture), .divert(gesture)], "written again after each re-read")
        XCTAssertEqual(slot.ledger.toGiveBack, [gesture], "given back at Pause all the same")

        // The mouse takes the third write: the next re-read finds it, and nothing is written.
        slot.echo(gesture, divert: true)
        slot.now += 11
        slot.reRead(controls: [gesture, back], divertedOnTheMouse: [gesture], bindings: [gesture])
        XCTAssertEqual(slot.writes.count, 3)
        XCTAssertEqual(slot.ledger.lastApplied, [gesture])
    }

    /// A divert the mouse echoed and that is gone at the next re-read was cleared by someone
    /// else (Logi Options+): counted as before, and twice within 30 s leaves the button to it.
    func testAnEchoedDivertThatIsGoneStillCountsAsAnotherApps() {
        let gesture: UInt16 = 0x00C3
        var slot = ModelledSlot()
        slot.pass(bindings: [gesture])
        slot.echo(gesture, divert: true)
        slot.now += 15
        slot.reRead(controls: [gesture], divertedOnTheMouse: [], bindings: [gesture])
        XCTAssertEqual(slot.modes.mode(for: slot.key(gesture)), .hidpp)
        XCTAssertEqual(slot.writes, [.divert(gesture), .divert(gesture)], "taken back once")

        slot.echo(gesture, divert: true)
        slot.now += 12
        slot.reRead(controls: [gesture], divertedOnTheMouse: [], bindings: [gesture])
        XCTAssertEqual(slot.modes.mode(for: slot.key(gesture)), .contended)
        XCTAssertEqual(slot.writes.count, 2, "a button another app keeps taking is left to it")
    }

    /// Over Bluetooth an echo can take a few hundred milliseconds, so a query can go out
    /// before it comes. The mouse answers in order: the echo comes before the answer, the
    /// divert counts, and nothing is written twice.
    func testAnEchoStillOnItsWayWhenTheQueryGoesOutKeepsTheDivert() {
        let gesture: UInt16 = 0x00C3
        var slot = ModelledSlot()
        slot.pass(bindings: [gesture])
        slot.ledger.noteQuerySent(cid: gesture)
        slot.echo(gesture, divert: true)
        XCTAssertEqual(slot.ledger.lastApplied, [gesture])

        var copy = slot.ledger
        XCTAssertEqual(copy.dropLost(queriedControls: [queried(gesture, diverted: true)]), [])
        slot.pass(bindings: [gesture])
        XCTAssertEqual(slot.writes, [.divert(gesture)])
    }

    /// Divert, give back and divert again within the answer time (Undo and Redo of a binding,
    /// a recording started, cancelled and started again), and the mouse refuses only the last
    /// divert. The echo of the first divert came while the give-back was still on its way: it
    /// tells the state before the give-back, not that the last divert was taken. It used to
    /// count for the last one, and the next re-read took the refused divert for another app's
    /// clear (two of those within 30 s: "Logi Options+ keeps taking this button over").
    func testAnEchoOfAnEarlierDivertDoesNotVouchForALaterOne() {
        let gesture: UInt16 = 0x00C3
        var slot = ModelledSlot()
        slot.pass(bindings: [gesture])
        slot.pass(bindings: [])
        slot.pass(bindings: [gesture])          // refused: no echo
        slot.echo(gesture, divert: true)
        XCTAssertEqual(slot.ledger.unacknowledged, [gesture], "the give-back is still on its way")
        slot.echo(gesture, divert: false)
        XCTAssertEqual(slot.ledger.unacknowledged, [gesture])

        slot.now += 15
        slot.ledger.noteQuerySent(cid: gesture)
        XCTAssertEqual(slot.ledger.heldBack, [gesture])
        var copy = slot.ledger
        XCTAssertEqual(copy.dropLost(queriedControls: [queried(gesture, diverted: false)]), [], "the mouse's refusal, not another app's doing")

        // All three taken: the echo of the last divert counts.
        var taken = ModelledSlot()
        taken.pass(bindings: [gesture])
        taken.pass(bindings: [])
        taken.pass(bindings: [gesture])
        taken.echo(gesture, divert: true)
        taken.echo(gesture, divert: false)
        taken.echo(gesture, divert: true)
        XCTAssertEqual(taken.ledger.unacknowledged, [])
        XCTAssertTrue(taken.ledger.pendingAcks.isEmpty)
    }

    /// Only an echo of Scrollio's own write counts: another app's divert of the button, an
    /// echo of Scrollio's that comes too late to be told from another app's, or an echo after
    /// the slot was forgotten, does not make Scrollio believe it diverted it.
    func testOnlyScrolliosOwnEchoCountsADivertAsTaken() {
        let gesture: UInt16 = 0x00C3
        var slot = ModelledSlot()
        slot.pass(bindings: [gesture])
        slot.ledger.noteQuerySent(cid: gesture)
        XCTAssertEqual(slot.ledger.heldBack, [gesture])
        // Another app diverts the button to a target of its own while Scrollio's divert waits.
        XCTAssertFalse(slot.ledger.consumeAck(cid: gesture, flags: 0x03, targetCID: 0x0056, now: slot.now), "another app's write")
        XCTAssertEqual(slot.ledger.lastApplied, [], "not believed applied: the pass after the re-read writes it again")
        XCTAssertEqual(slot.ledger.toGiveBack, [gesture])
        // Scrollio's own echo after the lifetime matches nothing any more.
        slot.now += LogiPendingReportingAcks.lifetime + 1
        XCTAssertFalse(slot.ledger.consumeAck(cid: gesture, flags: 0x03, targetCID: 0, now: slot.now))
        XCTAssertEqual(slot.ledger.lastApplied, [])

        // The slot disconnects (the session forgets what it applied and diverted): an echo
        // that comes after that puts nothing back.
        var forgotten = ModelledSlot()
        forgotten.pass(bindings: [gesture])
        forgotten.ledger.noteQuerySent(cid: gesture)
        XCTAssertEqual(forgotten.ledger.heldBack, [gesture])
        forgotten.ledger.lastApplied.removeAll()
        forgotten.ledger.diverted.removeAll()
        forgotten.echo(gesture, divert: true)
        XCTAssertEqual(forgotten.ledger.lastApplied, [])
        XCTAssertEqual(forgotten.ledger.toGiveBack, [])
    }

    /// A pass between a query and its answer: a binding is added while the buttons' state is
    /// re-read. The held-back divert is written again in that pass; the answer was asked for
    /// before that write, so it counts nothing.
    func testAPassBetweenAQueryAndItsAnswer() {
        let gesture: UInt16 = 0x00C3, back: UInt16 = 0x0053
        var slot = ModelledSlot()
        slot.pass(bindings: [gesture])          // refused: no echo
        slot.now += 15
        slot.ledger.noteQuerySent(cid: gesture)
        XCTAssertEqual(slot.ledger.heldBack, [gesture])

        slot.pass(bindings: [gesture, back])    // before the answer comes
        XCTAssertEqual(slot.writes, [.divert(gesture), .divert(back), .divert(gesture)])
        XCTAssertEqual(slot.ledger.heldBack, [])
        XCTAssertTrue(slot.ledger.answerPredatesAWrite(cid: gesture))
        var copy = slot.ledger
        XCTAssertEqual(copy.dropLost(queriedControls: [queried(gesture, diverted: false)]), [], "older than the write")
        XCTAssertEqual(slot.ledger.lastApplied, [gesture, back])

        // The binding removed instead: the pass gives back what lastApplied has
        // (LogiDeviceSession), so it writes nothing for the held-back button. The ledger
        // still has it, and gives it back at Pause, Quit and sleep.
        var removed = ModelledSlot()
        removed.pass(bindings: [gesture])
        removed.now += 15
        removed.ledger.noteQuerySent(cid: gesture)
        removed.pass(bindings: [])
        XCTAssertEqual(removed.ledger.heldBack, [gesture])
        XCTAssertEqual(removed.ledger.toGiveBack, [gesture])
    }

    /// A divert the mouse refuses every time is written again at every re-read and the button
    /// does what it does without Scrollio. After the third refusal in a row one `logi` line
    /// says so (the toast of 1.1.0 is gone); an echo or a give-back starts the count again.
    func testADivertTheMouseKeepsRefusingIsNamedOnceInTheLog() {
        let gesture: UInt16 = 0x00C3
        var slot = ModelledSlot()
        slot.pass(bindings: [gesture])          // refused, and every write after it
        for _ in 0..<2 {
            slot.now += 12
            slot.reRead(controls: [gesture], divertedOnTheMouse: [], bindings: [gesture])
        }
        XCTAssertEqual(ledgerLines, [], "two refusals in a row are no line's worth yet")
        slot.now += 12
        slot.reRead(controls: [gesture], divertedOnTheMouse: [], bindings: [gesture])
        XCTAssertEqual(ledgerLines, [LogiDivertLedger.keepsRefusingLine(cid: gesture, times: 3)])
        XCTAssertTrue(ledgerLines.first?.contains("0x00C3 Gesture") ?? false, "\(ledgerLines)")
        slot.now += 12
        slot.reRead(controls: [gesture], divertedOnTheMouse: [], bindings: [gesture])
        XCTAssertEqual(ledgerLines.count, 1, "one line, not one per re-read")
        XCTAssertEqual(slot.writes.count, 5, "written again all the same")

        // The mouse takes it: the count starts again.
        slot.echo(gesture, divert: true)
        slot.now += 12
        slot.reRead(controls: [gesture], divertedOnTheMouse: [gesture], bindings: [gesture])
        slot.write(gesture, divert: false)
        slot.write(gesture, divert: true)       // refused again, three times
        slot.ledger.lastApplied = [gesture]
        for _ in 0..<3 {
            slot.now += 12
            slot.reRead(controls: [gesture], divertedOnTheMouse: [], bindings: [gesture])
        }
        XCTAssertEqual(ledgerLines.count, 2)

        // A give-back in between starts it again too.
        var givenBack = ModelledSlot()
        givenBack.pass(bindings: [gesture])
        for _ in 0..<2 {
            givenBack.now += 12
            givenBack.reRead(controls: [gesture], divertedOnTheMouse: [], bindings: [gesture])
        }
        givenBack.pass(bindings: [])
        givenBack.pass(bindings: [gesture])
        for _ in 0..<2 {
            givenBack.now += 12
            givenBack.reRead(controls: [gesture], divertedOnTheMouse: [], bindings: [gesture])
        }
        XCTAssertEqual(ledgerLines.count, 2)
    }

    /// Two mice on one receiver, both with a gesture button. The session keeps a ledger per
    /// slot and gives an echo to the slot the report names: the second mouse's echo does not
    /// vouch for the first mouse's divert, which that mouse refused. Reading the second
    /// mouse (the cursor slot) writes nothing; the first one, when its slot is read, is held
    /// back and written again, and never counts as another app's.
    func testTwoMiceOfAReceiverKeepTheirOwnEchoes() {
        let gesture: UInt16 = 0x00C3
        let modes = LogiButtonDeliveryModeStore()
        var first = ModelledSlot(modes: modes)
        var second = ModelledSlot(modes: modes, productId: 0xB023, name: "MX Master 3")
        first.pass(bindings: [gesture])         // refused: no echo
        second.pass(bindings: [gesture])
        second.echo(gesture, divert: true)
        XCTAssertEqual(first.ledger.unacknowledged, [gesture])
        XCTAssertEqual(second.ledger.unacknowledged, [])

        second.now += 15
        second.reRead(controls: [gesture], divertedOnTheMouse: [gesture], bindings: [gesture])
        XCTAssertEqual(second.writes, [.divert(gesture)])

        for _ in 0..<2 {
            first.now += 12
            first.reRead(controls: [gesture], divertedOnTheMouse: [], bindings: [gesture])
        }
        XCTAssertEqual(first.writes, [.divert(gesture), .divert(gesture), .divert(gesture)])
        XCTAssertEqual(modes.mode(for: first.key(gesture)), .hidpp)
        XCTAssertEqual(modes.mode(for: second.key(gesture)), .hidpp)
    }

    func testAnEchoThatDiffersOrComesTooLateIsNotScrollios() {
        var ledger = LogiDivertLedger()
        let start = Date(timeIntervalSince1970: 1_000)
        ledger.expectAck(cid: 0x00C4, flags: 0x03, targetCID: 0, now: start)
        XCTAssertFalse(ledger.consumeAck(cid: 0x00C4, flags: 0x02, targetCID: 0, now: start), "another app gave the button back")
        XCTAssertFalse(ledger.consumeAck(cid: 0x00C3, flags: 0x03, targetCID: 0, now: start), "another control")
        XCTAssertTrue(ledger.consumeAck(cid: 0x00C4, flags: 0x03, targetCID: 0, now: start.addingTimeInterval(1)))

        ledger.expectAck(cid: 0x00C4, flags: 0x03, targetCID: 0, now: start)
        let late = start.addingTimeInterval(LogiPendingReportingAcks.lifetime + 0.5)
        XCTAssertFalse(ledger.consumeAck(cid: 0x00C4, flags: 0x03, targetCID: 0, now: late))
    }

    // MARK: - The left and the right button

    /// A mouse that lets its left button be diverted (the MX Master line does not): Scrollio
    /// never diverts it, not for a binding that names it and not while recording. A click
    /// that only Scrollio receives would be a dead left button.
    func testTheLeftAndTheRightButtonAreNeverDiverted() {
        let policy = LogiButtonDeliveryPolicy(standardMouseButtonsUseNativeEvents: true)
        let divertable: Set<UInt16> = [0x0050, 0x0051, 0x0052, 0x00C4]
        XCTAssertEqual(LogiCIDDirectory.toCID(1003), 0x0050)
        XCTAssertEqual(LogiCIDDirectory.toCID(1004), 0x0051)

        for transport in [LogiTransportIdentity.receiver, .bleDirect] {
            XCTAssertEqual(LogiDeviceSession.targetCIDsForUsageForTests(
                aggregateScrollioCodes: [1003, 1004, 1001], divertableCIDs: divertable,
                transport: transport, phase: .normal, policy: policy,
                deliveryModeForCID: { _ in .hidpp }
            ), [0x00C4], "\(transport)")
        }

        let receiver = LogiDeviceSession.recordingDivertPlanForTests(
            divertableCIDs: divertable, lastApplied: [0x0050], transport: .receiver, policy: policy
        )
        XCTAssertEqual(receiver.desired, [0x0052, 0x00C4])
        XCTAssertEqual(receiver.toAssert, [0x0052, 0x00C4])
        XCTAssertEqual(receiver.toUndivert, [0x0050], "a left button an earlier version diverted is given back")

        let bluetooth = LogiDeviceSession.recordingDivertPlanForTests(
            divertableCIDs: divertable, lastApplied: [], transport: .bleDirect, policy: policy
        )
        XCTAssertEqual(bluetooth.desired, [0x00C4])
        XCTAssertFalse(bluetooth.toUndivert.contains(0x0050))
        XCTAssertEqual(LogiButtonDeliveryPolicy.divertCandidates(divertable), [0x0052, 0x00C4])
    }

    /// A left or right button the mouse still has diverted from an earlier run is given back
    /// at the next connection whatever the manage switch says, also while a button is recorded.
    func testALeftoverDivertOfTheLeftButtonIsAlwaysGivenBack() {
        let found = [queried(0x0050, diverted: true), queried(0x00C4, diverted: true)]
        let unmanaged = LogiDeviceSession.staleDivertDecision(
            queriedControls: found, wanted: [], undivertedAnyway: [], managed: false, recording: false
        )
        XCTAssertEqual(unmanaged.giveBack, [0x0050])
        XCTAssertEqual(unmanaged.leftAlone, [0x00C4])

        let recording = LogiDeviceSession.staleDivertDecision(
            queriedControls: found, wanted: [], undivertedAnyway: [], managed: false, recording: true
        )
        XCTAssertEqual(recording.giveBack, [0x0050])
        XCTAssertEqual(recording.leftAlone, [])

        let managed = LogiDeviceSession.staleDivertDecision(
            queriedControls: found, wanted: [], undivertedAnyway: [], managed: true, recording: false
        )
        XCTAssertEqual(managed.giveBack, [0x0050, 0x00C4])

        let line = LogiDeviceSession.staleDivertLine(unmanaged, name: { $0 == 0x0050 ? "Left Click" : "Smart Shift" })
        XCTAssertEqual(
            line,
            "Gave back 1 button the mouse still had diverted from an earlier run (Scrollio does not use it; "
                + "the left and the right button are given back whatever the switch says): 0x0050 Left Click. "
                + "Left 1 button diverted that Scrollio does not use (manage switch off: another app may use it; "
                + "a leftover is freed by switching the mouse off and on): 0x00C4 Smart Shift"
        )
    }
}
