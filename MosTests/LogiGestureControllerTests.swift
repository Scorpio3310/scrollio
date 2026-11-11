import XCTest
@testable import Mos_Debug

/// LogiGestureController against recording drivers and fake report bytes: when raw XY is
/// armed and cleared, when a hold counts as tracked by the device, what happens when the
/// mouse does not answer, which movement samples reach the app, and when a haptic pulse
/// may be played. No HID device is involved.
final class LogiGestureControllerTests: XCTestCase {

    private struct Write: Equatable, CustomStringConvertible {
        let cid: UInt16
        let flags: UInt8
        var description: String { String(format: "0x%04X<-0x%02X", cid, flags) }
    }

    private struct Haptic: Equatable {
        let functionId: UInt8
        let params: [UInt8]
    }

    private struct Movement: Equatable {
        let cid: UInt16
        let deltaX: Int
        let deltaY: Int
    }

    private static let gesture: UInt16 = 0x00C3
    private static let modeShift: UInt16 = 0x00C4
    private static let back: UInt16 = 0x0053
    /// A divertable control without the raw_xy capability.
    private static let plain: UInt16 = 0x00D7

    private static let arm = Write(cid: gesture, flags: 0x33)

    /// Every setCidReporting write, in order: the session's own and the controller's.
    private var writes: [Write] = []
    private var haptics: [Haptic] = []
    private var movements: [Movement] = []
    private var timers: [(delay: TimeInterval, work: () -> Void)] = []
    private var changes = 0
    /// What the session remembers as diverted (`lastApplied`).
    private var diverted: Set<UInt16> = []

    override func setUp() {
        super.setUp()
        writes = []
        haptics = []
        movements = []
        timers = []
        changes = 0
        diverted = []
    }

    private func makeController(capable: Set<UInt16> = [gesture, modeShift, back]) -> LogiGestureController {
        let controller = LogiGestureController(
            sendReporting: { [unowned self] cid, flags in self.writes.append(Write(cid: cid, flags: flags)) },
            sendHaptic: { [unowned self] functionId, params in
                self.haptics.append(Haptic(functionId: functionId, params: params))
            },
            deliverMovement: { [unowned self] cid, deltaX, deltaY in
                self.movements.append(Movement(cid: cid, deltaX: deltaX, deltaY: deltaY))
            },
            schedule: { [unowned self] delay, work in self.timers.append((delay, work)) },
            onChange: { [unowned self] in self.changes += 1 }
        )
        controller.setRawXYCapableControls(capable)
        return controller
    }

    /// The part of LogiDeviceSession.applyUsage that touches the controller: store the
    /// request, write the divert diff with the flags the controller picks, then reconcile.
    private func applyUsage(
        _ controller: LogiGestureController,
        bound: Set<UInt16>,
        tracking: Set<UInt16>
    ) {
        controller.setRawXYRequest(tracking)
        for cid in bound.subtracting(diverted).sorted() {
            writes.append(Write(cid: cid, flags: controller.reportingFlags(cid: cid, divert: true)))
        }
        for cid in diverted.subtracting(bound).sorted() {
            writes.append(Write(cid: cid, flags: controller.reportingFlags(cid: cid, divert: false)))
        }
        diverted = bound
        controller.reconcile(diverted: bound)
    }

    /// The mouse echoes a setCidReporting request.
    private func acknowledge(_ controller: LogiGestureController, _ write: Write) {
        controller.handleReportingAcknowledgement(cid: write.cid, flags: write.flags)
    }

    private func armedController() -> LogiGestureController {
        let controller = makeController()
        applyUsage(controller, bound: [Self.gesture], tracking: [Self.gesture])
        acknowledge(controller, Self.arm)
        writes = []
        return controller
    }

    private func fireTimers() {
        let pending = timers
        timers = []
        pending.forEach { $0.work() }
    }

    // MARK: - Arming

    func testSettingOffKeepsTodaysBytes() {
        let controller = makeController()
        applyUsage(controller, bound: [Self.gesture, Self.back], tracking: [])
        XCTAssertEqual(writes, [Write(cid: Self.back, flags: 0x03), Write(cid: Self.gesture, flags: 0x03)])

        applyUsage(controller, bound: [], tracking: [])
        XCTAssertEqual(Array(writes.suffix(2)), [Write(cid: Self.back, flags: 0x02), Write(cid: Self.gesture, flags: 0x02)])
        XCTAssertTrue(timers.isEmpty)
        XCTAssertTrue(controller.armedCIDs.isEmpty)
    }

    func testArmsOnlyRequestedControlsWithTheCapability() {
        let controller = makeController()
        // The gesture button is requested and capable, Back is capable but not requested,
        // the plain control is requested but cannot do it.
        applyUsage(
            controller,
            bound: [Self.gesture, Self.back, Self.plain],
            tracking: [Self.gesture, Self.plain]
        )
        XCTAssertEqual(writes, [
            Write(cid: Self.back, flags: 0x03),
            Write(cid: Self.gesture, flags: 0x33),
            Write(cid: Self.plain, flags: 0x03),
        ])
    }

    func testDeviceWithoutAnyCapableControlIsNeverArmed() {
        let controller = makeController(capable: [])
        XCTAssertFalse(controller.supportsRawXY)
        applyUsage(controller, bound: [Self.gesture], tracking: [Self.gesture])
        XCTAssertEqual(writes, [Write(cid: Self.gesture, flags: 0x03)])
        XCTAssertFalse(controller.buttonDown(cid: Self.gesture))
    }

    func testARequestedControlThatIsNotDivertedGetsNoWrite() {
        let controller = makeController()
        applyUsage(controller, bound: [], tracking: [Self.gesture])
        XCTAssertEqual(writes, [])
        XCTAssertTrue(timers.isEmpty)
    }

    func testAHoldIsOnlyTrackedOnceTheMouseAcknowledged() {
        let controller = makeController()
        applyUsage(controller, bound: [Self.gesture], tracking: [Self.gesture])
        XCTAssertEqual(writes, [Self.arm])

        // Pressed before the echo arrived: this hold stays on the pointer path.
        XCTAssertFalse(controller.buttonDown(cid: Self.gesture))
        controller.buttonUp(cid: Self.gesture)

        acknowledge(controller, Self.arm)
        XCTAssertEqual(controller.armedCIDs, [Self.gesture])
        XCTAssertTrue(controller.buttonDown(cid: Self.gesture))
        XCTAssertTrue(controller.hasTrackedHold)
        controller.buttonUp(cid: Self.gesture)
        XCTAssertFalse(controller.hasTrackedHold)
    }

    func testAnEchoOfADifferentRequestDoesNotArm() {
        let controller = makeController()
        applyUsage(controller, bound: [Self.gesture], tracking: [Self.gesture])
        controller.handleReportingAcknowledgement(cid: Self.gesture, flags: 0x03)
        controller.handleReportingAcknowledgement(cid: Self.modeShift, flags: 0x33)
        XCTAssertTrue(controller.armedCIDs.isEmpty)
        XCTAssertFalse(controller.buttonDown(cid: Self.gesture))
    }

    // MARK: - Setting toggled, binding removed

    func testTurningTheSettingOnArmsAControlThatIsAlreadyDiverted() {
        let controller = makeController()
        applyUsage(controller, bound: [Self.gesture], tracking: [])
        XCTAssertEqual(writes, [Write(cid: Self.gesture, flags: 0x03)])

        applyUsage(controller, bound: [Self.gesture], tracking: [Self.gesture])
        XCTAssertEqual(writes.last, Self.arm)
        XCTAssertEqual(writes.count, 2)

        // Applying the same state again sends nothing, waiting for the echo or after it.
        applyUsage(controller, bound: [Self.gesture], tracking: [Self.gesture])
        acknowledge(controller, Self.arm)
        applyUsage(controller, bound: [Self.gesture], tracking: [Self.gesture])
        XCTAssertEqual(writes.count, 2)
    }

    func testTurningTheSettingOffKeepsTheDivertAndClearsRawXY() {
        let controller = armedController()
        applyUsage(controller, bound: [Self.gesture], tracking: [])
        XCTAssertEqual(writes, [Write(cid: Self.gesture, flags: 0x23)])
        XCTAssertTrue(controller.armedCIDs.isEmpty)
        XCTAssertFalse(controller.buttonDown(cid: Self.gesture))

        // From here on the control is a plain diverted button again.
        applyUsage(controller, bound: [], tracking: [])
        XCTAssertEqual(writes.last, Write(cid: Self.gesture, flags: 0x02))
    }

    func testRemovingTheBindingDisarmsInOneWrite() {
        let controller = armedController()
        applyUsage(controller, bound: [], tracking: [])
        XCTAssertEqual(writes, [Write(cid: Self.gesture, flags: 0x22)])
        XCTAssertTrue(controller.armedCIDs.isEmpty)
    }

    func testRemovingTheBindingWhileStillArmingAlsoDisarms() {
        let controller = makeController()
        applyUsage(controller, bound: [Self.gesture], tracking: [Self.gesture])
        applyUsage(controller, bound: [], tracking: [])
        XCTAssertEqual(writes, [Self.arm, Write(cid: Self.gesture, flags: 0x22)])

        // The timeout of the abandoned arm request does nothing.
        fireTimers()
        XCTAssertEqual(writes.count, 2)
        XCTAssertTrue(controller.rejectedCIDs.isEmpty)
    }

    func testReassertingAnArmedControlKeepsItArmed() {
        let controller = armedController()
        // Recording mode and the re-assert after an external clear write every bound control again.
        XCTAssertEqual(controller.reportingFlags(cid: Self.gesture, divert: true), 0x33)
        XCTAssertEqual(controller.armedCIDs, [Self.gesture])
        XCTAssertTrue(controller.buttonDown(cid: Self.gesture))
        XCTAssertTrue(timers.count == 1, "only the first arm request started a timeout")
    }

    // MARK: - Fallback to pointer movement

    func testNoAcknowledgementFallsBackToPointerMovement() {
        let controller = makeController()
        applyUsage(controller, bound: [Self.gesture], tracking: [Self.gesture])
        XCTAssertEqual(timers.count, 1)
        XCTAssertEqual(timers.first?.delay, LogiGestureController.acknowledgeTimeout)

        fireTimers()

        // Still diverted, raw XY stated off: the pointer moves, so the motion tap sees it.
        XCTAssertEqual(writes, [Self.arm, Write(cid: Self.gesture, flags: 0x23)])
        XCTAssertEqual(controller.rejectedCIDs, [Self.gesture])
        XCTAssertFalse(controller.buttonDown(cid: Self.gesture))

        // A late echo of the arm request does not bring it back.
        acknowledge(controller, Self.arm)
        XCTAssertFalse(controller.buttonDown(cid: Self.gesture))

        // Later usage passes do not try again by themselves.
        applyUsage(controller, bound: [Self.gesture], tracking: [Self.gesture])
        XCTAssertEqual(writes.count, 2)
    }

    func testAnAcknowledgedRequestIsNotTimedOut() {
        let controller = makeController()
        applyUsage(controller, bound: [Self.gesture], tracking: [Self.gesture])
        acknowledge(controller, Self.arm)
        fireTimers()
        XCTAssertEqual(writes, [Self.arm])
        XCTAssertEqual(controller.armedCIDs, [Self.gesture])
        XCTAssertTrue(controller.rejectedCIDs.isEmpty)
    }

    func testAnErrorFromTheMouseFallsBackToPointerMovement() {
        let controller = makeController()
        applyUsage(controller, bound: [Self.gesture, Self.modeShift], tracking: [Self.gesture])
        writes = []

        controller.handleReportingError()

        XCTAssertEqual(writes, [Write(cid: Self.gesture, flags: 0x23)])
        XCTAssertEqual(controller.rejectedCIDs, [Self.gesture])
        // The timeout that was still pending finds nothing to do.
        fireTimers()
        XCTAssertEqual(writes.count, 1)
    }

    func testAnErrorWithNothingWaitingChangesNothing() {
        let controller = armedController()
        controller.handleReportingError()
        XCTAssertEqual(writes, [])
        XCTAssertEqual(controller.armedCIDs, [Self.gesture])
    }

    func testARejectedControlGetsANewAttemptWhenTheSettingIsTurnedOnAgain() {
        let controller = makeController()
        applyUsage(controller, bound: [Self.gesture], tracking: [Self.gesture])
        fireTimers()
        writes = []

        applyUsage(controller, bound: [Self.gesture], tracking: [])
        XCTAssertEqual(writes, [], "already stated as diverted without raw XY")
        XCTAssertTrue(controller.rejectedCIDs.isEmpty)

        applyUsage(controller, bound: [Self.gesture], tracking: [Self.gesture])
        XCTAssertEqual(writes, [Self.arm])
    }

    // MARK: - Teardown

    func testTeardownDisarmsArmedAndArmingControlsOnly() {
        let controller = makeController()
        applyUsage(
            controller,
            bound: [Self.gesture, Self.modeShift, Self.plain],
            tracking: [Self.gesture, Self.modeShift]
        )
        acknowledge(controller, Self.arm)  // the mode-shift button is still waiting for its echo
        XCTAssertTrue(controller.buttonDown(cid: Self.gesture))
        writes = []

        controller.disarmAll()

        XCTAssertEqual(writes, [Write(cid: Self.gesture, flags: 0x22), Write(cid: Self.modeShift, flags: 0x22)])
        XCTAssertTrue(controller.armedCIDs.isEmpty)
        XCTAssertFalse(controller.hasTrackedHold)

        // The session then gives the remaining diverted controls back with the plain bytes.
        XCTAssertEqual(controller.reportingFlags(cid: Self.plain, divert: false), 0x02)
        // Nothing is armed any more, so a second teardown sends nothing.
        writes = []
        controller.disarmAll()
        fireTimers()
        XCTAssertEqual(writes, [])
    }

    func testTeardownWithoutRawXYSendsNothingItself() {
        let controller = makeController()
        applyUsage(controller, bound: [Self.gesture], tracking: [])
        writes = []
        controller.disarmAll()
        XCTAssertEqual(writes, [])
        XCTAssertEqual(controller.reportingFlags(cid: Self.gesture, divert: false), 0x02)
    }

    // MARK: - Raw XY left on the device

    func testALeftoverIsClearedWhenMosDivertsTheControlWithoutTracking() {
        let controller = makeController()
        // getCidReporting during discovery: diverted + raw XY, from a Mos that died.
        controller.noteDeviceReporting(cid: Self.gesture, reportingFlags: 0x11)
        applyUsage(controller, bound: [Self.gesture], tracking: [])
        XCTAssertEqual(writes, [Write(cid: Self.gesture, flags: 0x23)])

        // Settled: later writes are the plain ones again.
        applyUsage(controller, bound: [], tracking: [])
        XCTAssertEqual(writes.last, Write(cid: Self.gesture, flags: 0x02))
    }

    func testALeftoverIsReArmedWhenTrackingIsWanted() {
        let controller = makeController()
        controller.noteDeviceReporting(cid: Self.gesture, reportingFlags: 0x11)
        applyUsage(controller, bound: [Self.gesture], tracking: [Self.gesture])
        XCTAssertEqual(writes, [Self.arm])
        // Not tracked on the device's word alone: the echo is still required.
        XCTAssertFalse(controller.buttonDown(cid: Self.gesture))
    }

    func testALeftoverReportedLaterIsClearedByTheNextUsagePass() {
        let controller = makeController()
        applyUsage(controller, bound: [Self.gesture], tracking: [])
        writes = []
        controller.noteDeviceReporting(cid: Self.gesture, reportingFlags: 0x11)
        applyUsage(controller, bound: [Self.gesture], tracking: [])
        XCTAssertEqual(writes, [Write(cid: Self.gesture, flags: 0x23)])
    }

    func testALeftoverOnAControlMosDoesNotDivertIsLeftAlone() {
        let controller = makeController()
        controller.noteDeviceReporting(cid: Self.gesture, reportingFlags: 0x11)
        applyUsage(controller, bound: [Self.back], tracking: [])
        XCTAssertEqual(writes, [Write(cid: Self.back, flags: 0x03)])
        controller.disarmAll()
        XCTAssertEqual(writes.count, 1, "another app may be using raw XY on that control")
    }

    func testRawXYBitsAreNeverStatedForAControlWithoutTheCapability() {
        let controller = makeController()
        // Whatever that bit meant in the answer: the plain control only ever gets the plain bytes.
        controller.noteDeviceReporting(cid: Self.plain, reportingFlags: 0x11)
        applyUsage(controller, bound: [Self.plain], tracking: [Self.plain])
        applyUsage(controller, bound: [Self.plain], tracking: [])
        applyUsage(controller, bound: [], tracking: [])
        XCTAssertEqual(writes, [Write(cid: Self.plain, flags: 0x03), Write(cid: Self.plain, flags: 0x02)])
    }

    func testTheDevicesOwnReportOfAnArmedControlIsNotALeftover() {
        let controller = armedController()
        controller.noteDeviceReporting(cid: Self.gesture, reportingFlags: 0x11)
        applyUsage(controller, bound: [Self.gesture], tracking: [Self.gesture])
        XCTAssertEqual(writes, [])
        XCTAssertEqual(controller.armedCIDs, [Self.gesture])
    }

    func testForgettingAControlLetsTheNextPassArmItAgain() {
        let controller = armedController()
        XCTAssertTrue(controller.buttonDown(cid: Self.gesture))

        // The divert was cleared from outside; the session re-applies the binding.
        controller.forget(cid: Self.gesture)
        XCTAssertFalse(controller.hasTrackedHold)
        diverted = []
        applyUsage(controller, bound: [Self.gesture], tracking: [Self.gesture])
        XCTAssertEqual(writes, [Self.arm])
        XCTAssertFalse(controller.buttonDown(cid: Self.gesture), "tracked again only after the new echo")
    }

    // MARK: - Movement

    func testFirstSampleOfEveryHoldIsDropped() {
        let controller = armedController()

        XCTAssertTrue(controller.buttonDown(cid: Self.gesture))
        controller.handleRawXY(deltaX: 900, deltaY: -700)  // the jump OpenLogi saw
        controller.handleRawXY(deltaX: -4, deltaY: 1)
        controller.handleRawXY(deltaX: -6, deltaY: 0)
        controller.buttonUp(cid: Self.gesture)

        XCTAssertTrue(controller.buttonDown(cid: Self.gesture))
        controller.handleRawXY(deltaX: 500, deltaY: 500)
        controller.handleRawXY(deltaX: 2, deltaY: 3)

        XCTAssertEqual(movements, [
            Movement(cid: Self.gesture, deltaX: -4, deltaY: 1),
            Movement(cid: Self.gesture, deltaX: -6, deltaY: 0),
            Movement(cid: Self.gesture, deltaX: 2, deltaY: 3),
        ])
    }

    func testMovementWithoutATrackedHoldIsIgnored() {
        let controller = armedController()
        controller.handleRawXY(deltaX: 5, deltaY: 5)
        controller.handleRawXY(deltaX: 5, deltaY: 5)

        XCTAssertTrue(controller.buttonDown(cid: Self.gesture))
        controller.buttonUp(cid: Self.gesture)
        controller.handleRawXY(deltaX: 5, deltaY: 5)
        controller.handleRawXY(deltaX: 5, deltaY: 5)

        XCTAssertEqual(movements, [])
    }

    func testAHoldThatIsNotTrackedGetsNoMovement() {
        let controller = makeController()
        applyUsage(controller, bound: [Self.gesture], tracking: [])
        XCTAssertFalse(controller.buttonDown(cid: Self.gesture))
        controller.handleRawXY(deltaX: 5, deltaY: 5)
        controller.handleRawXY(deltaX: 5, deltaY: 5)
        XCTAssertEqual(movements, [])
    }

    func testZeroMovementIsNotDelivered() {
        let controller = armedController()
        XCTAssertTrue(controller.buttonDown(cid: Self.gesture))
        controller.handleRawXY(deltaX: 0, deltaY: 0)  // first sample
        controller.handleRawXY(deltaX: 0, deltaY: 0)
        controller.handleRawXY(deltaX: 0, deltaY: -1)
        XCTAssertEqual(movements, [Movement(cid: Self.gesture, deltaX: 0, deltaY: -1)])
    }

    func testReportBytesReachTheHoldWithTheirSign() throws {
        let controller = armedController()
        XCTAssertTrue(controller.buttonDown(cid: Self.gesture))
        let samples: [[UInt8]] = [
            [0x11, 0xFF, 0x09, 0x10, 0x00, 0x00, 0x00, 0x00, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            [0x11, 0xFF, 0x09, 0x10, 0xFF, 0xEC, 0x00, 0x05, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        ]
        for bytes in samples {
            let delta = try XCTUnwrap(LogiGestureProtocol.rawXYDelta(bytes))
            controller.handleRawXY(deltaX: delta.deltaX, deltaY: delta.deltaY)
        }
        XCTAssertEqual(movements, [Movement(cid: Self.gesture, deltaX: -20, deltaY: 5)])
    }

    func testTwoTrackedButtonsEachDropTheirOwnFirstSample() {
        let controller = makeController()
        applyUsage(controller, bound: [Self.gesture, Self.modeShift], tracking: [Self.gesture, Self.modeShift])
        acknowledge(controller, Self.arm)
        acknowledge(controller, Write(cid: Self.modeShift, flags: 0x33))

        XCTAssertTrue(controller.buttonDown(cid: Self.gesture))
        controller.handleRawXY(deltaX: 1, deltaY: 0)
        XCTAssertTrue(controller.buttonDown(cid: Self.modeShift))
        controller.handleRawXY(deltaX: 2, deltaY: 0)
        controller.handleRawXY(deltaX: 3, deltaY: 0)
        controller.buttonUp(cid: Self.gesture)
        controller.handleRawXY(deltaX: 4, deltaY: 0)

        XCTAssertEqual(movements, [
            Movement(cid: Self.gesture, deltaX: 2, deltaY: 0),
            Movement(cid: Self.gesture, deltaX: 3, deltaY: 0),
            Movement(cid: Self.modeShift, deltaX: 3, deltaY: 0),
            Movement(cid: Self.modeShift, deltaX: 4, deltaY: 0),
        ])
    }

    func testAHoldInProgressStaysTrackedWhenTheSettingIsTurnedOff() {
        let controller = armedController()
        XCTAssertTrue(controller.buttonDown(cid: Self.gesture))
        controller.handleRawXY(deltaX: 9, deltaY: 9)

        // The mouse applies the change at the next press, so this hold keeps reporting.
        applyUsage(controller, bound: [Self.gesture], tracking: [])
        controller.handleRawXY(deltaX: -3, deltaY: 0)
        XCTAssertEqual(movements, [Movement(cid: Self.gesture, deltaX: -3, deltaY: 0)])

        controller.buttonUp(cid: Self.gesture)
        XCTAssertFalse(controller.buttonDown(cid: Self.gesture))
    }

    func testADuplicateButtonDownStartsTheHoldOver() {
        let controller = armedController()
        XCTAssertTrue(controller.buttonDown(cid: Self.gesture))
        controller.handleRawXY(deltaX: 9, deltaY: 9)
        XCTAssertTrue(controller.buttonDown(cid: Self.gesture))
        controller.handleRawXY(deltaX: 7, deltaY: 7)
        controller.handleRawXY(deltaX: 1, deltaY: 1)
        XCTAssertEqual(movements, [Movement(cid: Self.gesture, deltaX: 1, deltaY: 1)])
    }

    // MARK: - Capabilities

    func testCapabilityChangesAreAnnounced() {
        let controller = makeController(capable: [])
        XCTAssertEqual(changes, 0)
        controller.setRawXYCapableControls([Self.gesture])
        XCTAssertTrue(controller.supportsRawXY)
        XCTAssertEqual(changes, 1)
        controller.setRawXYCapableControls([Self.gesture, Self.back])
        controller.setRawXYCapableControls([Self.gesture, Self.back])
        XCTAssertEqual(changes, 1, "still supported: nothing new to show")
    }

    // MARK: - Haptics

    private func hapticReport(functionId: UInt8, payload: [UInt8]) -> [UInt8] {
        var bytes: [UInt8] = [0x11, 0xFF, 0x21, (functionId << 4) | 0x01] + payload
        while bytes.count < 20 { bytes.append(0) }
        return bytes
    }

    /// Mask with every known waveform (bits 0...14 and 27), like an MX Master 4.
    private static let allWaveforms: [UInt8] = [0, 0, 0, 0, 0x08, 0x00, 0x7F, 0xFF]

    private func hapticController(
        enabledFlags: UInt8 = 0x01,
        waveforms: [UInt8] = allWaveforms
    ) -> LogiGestureController {
        let controller = makeController()
        controller.setHapticFeature(index: 0x21)
        controller.handleHapticResponse(functionId: 0, report: hapticReport(functionId: 0, payload: waveforms))
        controller.handleHapticResponse(functionId: 1, report: hapticReport(functionId: 1, payload: [enabledFlags, 60]))
        haptics = []
        return controller
    }

    func testFindingTheHapticFeatureReadsCapabilitiesAndState() {
        let controller = makeController()
        XCTAssertFalse(controller.supportsHaptics)
        let changesBefore = changes

        controller.setHapticFeature(index: 0x21)

        XCTAssertTrue(controller.supportsHaptics)
        XCTAssertEqual(changes, changesBefore + 1)
        XCTAssertEqual(haptics, [Haptic(functionId: 0, params: []), Haptic(functionId: 1, params: [])])
        XCTAssertNil(controller.hapticsEnabled)

        // The same index again changes nothing and asks nothing.
        controller.setHapticFeature(index: 0x21)
        XCTAssertEqual(haptics.count, 2)
    }

    func testCuesPlayTheirWaveformWhenHapticsAreOn() {
        let controller = hapticController()
        XCTAssertTrue(controller.play(.lockIn))
        XCTAssertTrue(controller.play(.commit))
        XCTAssertEqual(haptics, [Haptic(functionId: 4, params: [0x04]), Haptic(functionId: 4, params: [0x01])])
    }

    func testPowerSavingDoesNotBlockTheCue() {
        // bit0 enabled + bit1 power save: still the user's choice to have haptics on.
        let controller = hapticController(enabledFlags: 0x03)
        XCTAssertTrue(controller.play(.lockIn))
    }

    func testNoPulseWithoutTheHapticFeature() {
        let controller = makeController()
        XCTAssertFalse(controller.play(.lockIn))
        XCTAssertFalse(controller.play(.commit))
        controller.refreshHaptics()
        XCTAssertEqual(haptics, [])
    }

    func testNoPulseWhenTheUserSwitchedHapticsOff() {
        let controller = hapticController(enabledFlags: 0x00)
        XCTAssertEqual(controller.hapticsEnabled, false)
        XCTAssertFalse(controller.play(.lockIn))
        XCTAssertFalse(controller.play(.commit))
        XCTAssertEqual(haptics, [], "neither played nor switched back on")
    }

    func testNoPulseForAWaveformTheMouseDoesNotList() {
        // Only waveform 1.
        let controller = hapticController(waveforms: [0, 0, 0, 0, 0x00, 0x00, 0x00, 0x02])
        XCTAssertFalse(controller.play(.lockIn))
        XCTAssertTrue(controller.play(.commit))
        XCTAssertEqual(haptics, [Haptic(functionId: 4, params: [0x01])])
    }

    func testUnknownStateIsAskedForAgainInsteadOfPlayingBlind() {
        let controller = makeController()
        controller.setHapticFeature(index: 0x21)
        // Only the capabilities answer arrived.
        controller.handleHapticResponse(functionId: 0, report: hapticReport(functionId: 0, payload: Self.allWaveforms))
        haptics = []

        XCTAssertFalse(controller.play(.lockIn))
        XCTAssertEqual(haptics, [Haptic(functionId: 1, params: [])])

        controller.handleHapticResponse(functionId: 1, report: hapticReport(functionId: 1, payload: [0x01, 60]))
        XCTAssertTrue(controller.play(.lockIn))
    }

    func testStateFollowsWhatTheMouseReportsLater() {
        let controller = hapticController()
        controller.refreshHaptics()
        XCTAssertEqual(haptics, [Haptic(functionId: 1, params: [])], "the waveform list is read once")
        controller.handleHapticResponse(functionId: 1, report: hapticReport(functionId: 1, payload: [0x00, 60]))
        XCTAssertFalse(controller.play(.lockIn))
    }

    func testNothingTheControllerSendsCanChangeIntensityOrPowerSaving() {
        let controller = hapticController()
        controller.refreshHaptics()
        _ = controller.play(.lockIn)
        _ = controller.play(.commit)
        controller.handleHapticResponse(functionId: 4, report: hapticReport(functionId: 4, payload: [0x04]))
        controller.setHapticFeature(index: nil)
        controller.setHapticFeature(index: 0x22)

        XCTAssertFalse(haptics.isEmpty)
        for request in haptics {
            XCTAssertTrue([0, 1, 4].contains(request.functionId), "function \(request.functionId)")
            XCTAssertNotEqual(request.functionId, LogiGestureProtocol.hapticSetStateFunction)
        }
    }

    func testLosingTheFeatureForgetsItsState() {
        let controller = hapticController()
        controller.setHapticFeature(index: nil)
        XCTAssertFalse(controller.supportsHaptics)
        XCTAssertNil(controller.hapticsEnabled)
        XCTAssertFalse(controller.play(.lockIn))
        XCTAssertEqual(haptics, [])
    }

    // MARK: - Manager

    func testManagerPlaysNothingForAButtonNoMouseOwns() {
        let manager = LogiSessionManager()
        XCTAssertFalse(manager.playGestureHaptic(.lockIn, forMosCode: 1000))
        XCTAssertFalse(manager.supportsGestureDeviceTracking)
        XCTAssertFalse(manager.supportsGestureHaptics)
    }

    func testManagerStoresTheTrackingRequestAndReportsChanges() {
        let manager = LogiSessionManager()
        XCTAssertTrue(manager.gestureTrackingCodes.isEmpty)
        XCTAssertTrue(manager.setGestureTrackingCodes([1000]))
        XCTAssertFalse(manager.setGestureTrackingCodes([1000]), "unchanged: nothing to re-apply")
        XCTAssertEqual(manager.gestureTrackingCodes, [1000])
        XCTAssertTrue(manager.setGestureTrackingCodes([]))
    }
}
