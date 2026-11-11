import XCTest
@testable import Mos_Debug

/// LogiWheelController against fake response bytes: what it sends, when it writes,
/// that it never writes unless the settings are managed by Mos, and that a value the user
/// never set is never written.
final class LogiWheelControllerTests: XCTestCase {

    private struct Sent: Equatable {
        let functionId: UInt8
        let params: [UInt8]
    }

    private var sent: [Sent] = []
    private var changes = 0
    private var logs: [String] = []
    /// Reply timeouts the controller asked for; a test runs them when "2 s later" should happen.
    private var scheduled: [(delay: TimeInterval, work: () -> Void)] = []

    override func setUp() {
        super.setUp()
        sent = []
        changes = 0
        logs = []
        scheduled = []
    }

    private func makeController(_ feature: LogiWheelFeature) -> LogiWheelController {
        return LogiWheelController(
            feature: feature,
            featureIndex: 0x0E,
            send: { [unowned self] functionId, params in
                self.sent.append(Sent(functionId: functionId, params: params))
            },
            schedule: { [unowned self] delay, work in
                self.scheduled.append((delay, work))
            },
            onChange: { [unowned self] in self.changes += 1 },
            log: { [unowned self] in self.logs.append($0) }
        )
    }

    /// Lets every pending reply timeout expire, as the main queue would after the delay.
    private func expireReplyTimeouts() {
        let work = scheduled
        scheduled = []
        work.forEach { $0.work() }
    }

    private var capabilityReads: [Sent] { sent.filter { $0.functionId == 0 } }

    private func report(functionId: UInt8, payload: [UInt8]) -> [UInt8] {
        var bytes: [UInt8] = [0x11, 0xFF, 0x0E, (functionId << 4) | 0x01] + payload
        while bytes.count < 20 { bytes.append(0) }
        return bytes
    }

    /// The user's settings; a value left out is not set.
    private func settings(
        _ mode: LogiWheelMode? = nil,
        sensitivity: Int? = nil,
        force: Int? = nil,
        managed: Bool = true
    ) -> LogiWheelSettings {
        return LogiWheelSettings(managedByMos: managed, mode: mode, smartShiftSensitivity: sensitivity, scrollForce: force)
    }

    /// An MX Master 4 class wheel (0x2111, tunable torque) that has answered with `status`.
    private func connectedEnhanced(
        _ desired: LogiWheelSettings,
        status: [UInt8],
        tunableTorque: Bool = true
    ) -> LogiWheelController {
        let wheel = makeController(.smartShiftEnhanced)
        wheel.start(desired: desired)
        wheel.handleResponse(functionId: 0, report: report(functionId: 0, payload: [tunableTorque ? 0x01 : 0x00, 0x10, 0x32]))
        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: status))
        return wheel
    }

    private var writes: [Sent] { sent.filter { $0.functionId == 2 } }

    // MARK: - Reading

    func testStartUnmanaged_readsCapabilitiesAndStatus_neverWrites() {
        let wheel = makeController(.smartShiftEnhanced)
        wheel.start(desired: settings(.ratchet, managed: false))
        XCTAssertEqual(sent, [Sent(functionId: 0, params: []), Sent(functionId: 1, params: [])])

        wheel.handleResponse(functionId: 0, report: report(functionId: 0, payload: [0x01, 0x10, 0x32]))
        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: [0x02, 0x10, 0x48]))

        XCTAssertEqual(sent.count, 2, "unmanaged settings must never produce a write")
        XCTAssertEqual(wheel.mode, .smartShift)
        XCTAssertEqual(wheel.smartShiftSensitivity, 50)
        XCTAssertEqual(wheel.scrollForce, 72)
        XCTAssertTrue(wheel.supportsScrollForce)
        XCTAssertGreaterThanOrEqual(changes, 2)
    }

    func testDefaultSettingsAreUnmanaged_noWrite() {
        let wheel = makeController(.smartShiftEnhanced)
        wheel.start(desired: .default)
        wheel.handleResponse(functionId: 0, report: report(functionId: 0, payload: [0x01, 0x10, 0x32]))
        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: [0x01, 0x10, 0x48]))
        XCTAssertTrue(writes.isEmpty)
    }

    func testBasicFeature_readsFn0_hasNoCapabilities_noScrollForce() {
        let wheel = makeController(.smartShift)
        wheel.start(desired: .default)
        XCTAssertEqual(sent, [Sent(functionId: 0, params: [])])
        wheel.handleResponse(functionId: 0, report: report(functionId: 0, payload: [0x01, 0x0A, 0x10]))
        XCTAssertEqual(wheel.mode, .freeSpin)
        XCTAssertFalse(wheel.supportsScrollForce)
        XCTAssertNil(wheel.scrollForce)
    }

    func testWithoutTunableTorque_scrollForceIsHidden() {
        let wheel = makeController(.smartShiftEnhanced)
        wheel.start(desired: .default)
        wheel.handleResponse(functionId: 0, report: report(functionId: 0, payload: [0x00, 0x10, 0x32]))
        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: [0x02, 0xFF, 0x48]))
        XCTAssertFalse(wheel.supportsScrollForce)
        XCTAssertNil(wheel.scrollForce)
        XCTAssertEqual(wheel.mode, .ratchet)
        XCTAssertNil(wheel.smartShiftSensitivity)
    }

    // MARK: - Apply on connect

    func testStartManaged_writesAfterFreshStatus_thenReadsBack() {
        let wheel = makeController(.smartShiftEnhanced)
        wheel.start(desired: settings(.smartShift, sensitivity: 50, force: 70))
        wheel.handleResponse(functionId: 0, report: report(functionId: 0, payload: [0x01, 0x10, 0x32]))
        XCTAssertTrue(writes.isEmpty, "must wait for the status read before writing")

        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: [0x01, 0x20, 0x1E]))
        XCTAssertEqual(Array(sent.suffix(2)), [
            Sent(functionId: 2, params: [0x02, 16, 70]),
            Sent(functionId: 1, params: []),
        ])

        wheel.handleResponse(functionId: 2, report: report(functionId: 2, payload: [0x02, 16, 70]))
        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: [0x02, 16, 70]))
        XCTAssertEqual(writes.count, 1, "read-back must not trigger another write")
        XCTAssertEqual(wheel.mode, .smartShift)
        XCTAssertEqual(wheel.scrollForce, 70)
    }

    func testStartManaged_deviceAlreadyMatches_noWrite() {
        let wheel = makeController(.smartShiftEnhanced)
        wheel.start(desired: settings(.ratchet, force: 40))
        wheel.handleResponse(functionId: 0, report: report(functionId: 0, payload: [0x01, 0x10, 0x32]))
        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: [0x02, 0xFF, 40]))
        XCTAssertTrue(writes.isEmpty)
    }

    func testStartManaged_basicFeature_writesFn1WithoutTorque() {
        let wheel = makeController(.smartShift)
        wheel.start(desired: settings(.ratchet, force: 90))
        wheel.handleResponse(functionId: 0, report: report(functionId: 0, payload: [0x02, 0x10, 0x10]))
        XCTAssertEqual(sent, [
            Sent(functionId: 0, params: []),
            Sent(functionId: 1, params: [0x02, 0xFF, 0x00]),
            Sent(functionId: 0, params: []),
        ])
    }

    func testStatusBeforeCapabilities_waitsForCapabilities() {
        let wheel = makeController(.smartShiftEnhanced)
        wheel.start(desired: settings(.freeSpin, force: 60))
        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: [0x02, 0x10, 0x32]))
        XCTAssertTrue(writes.isEmpty, "torque support unknown yet")
        wheel.handleResponse(functionId: 0, report: report(functionId: 0, payload: [0x01, 0x10, 0x32]))
        XCTAssertEqual(writes, [Sent(functionId: 2, params: [0x01, 0x00, 60])])
    }

    func testCapabilitiesError_appliesWithoutTorque() {
        let wheel = makeController(.smartShiftEnhanced)
        wheel.start(desired: settings(.ratchet, force: 60))
        wheel.handleError(functionId: 0, errorCode: 0x02)
        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: [0x01, 0x10, 0x32]))
        XCTAssertEqual(writes, [Sent(functionId: 2, params: [0x02, 0xFF, 0x00])])
    }

    func testStatusReadError_dropsPendingSettings() {
        let wheel = makeController(.smartShiftEnhanced)
        wheel.start(desired: settings(.ratchet))
        wheel.handleResponse(functionId: 0, report: report(functionId: 0, payload: [0x01, 0x10, 0x32]))
        wheel.handleError(functionId: 1, errorCode: 0x05)
        XCTAssertTrue(wheel.pendingFields.isEmpty)
        XCTAssertTrue(writes.isEmpty)
    }

    // MARK: - Lost capabilities reply

    func testCapabilitiesRead_armsAReplyTimeout() {
        let wheel = makeController(.smartShiftEnhanced)
        wheel.start(desired: .default)
        XCTAssertEqual(scheduled.map { $0.delay }, [LogiWheelController.replyTimeout])
        XCTAssertFalse(wheel.capabilitiesKnown)
    }

    func testBasicFeature_hasNoCapabilitiesRead_andNoTimeout() {
        let wheel = makeController(.smartShift)
        wheel.start(desired: settings(.ratchet))
        XCTAssertTrue(scheduled.isEmpty)
    }

    /// The regression: one lost reply used to hold managed writes back until reconnect.
    func testLostCapabilitiesReply_isAskedAgain_thenTheWriteGoesOut() {
        let wheel = makeController(.smartShiftEnhanced)
        wheel.start(desired: settings(.freeSpin, force: 60))
        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: [0x02, 0x10, 0x32]))
        XCTAssertTrue(writes.isEmpty, "torque support unknown yet")

        expireReplyTimeouts()
        XCTAssertEqual(capabilityReads.count, 2, "the read is repeated")
        XCTAssertTrue(writes.isEmpty)

        wheel.handleResponse(functionId: 0, report: report(functionId: 0, payload: [0x01, 0x10, 0x32]))
        XCTAssertEqual(writes, [Sent(functionId: 2, params: [0x01, 0x00, 60])])
        XCTAssertTrue(wheel.supportsScrollForce)
    }

    func testCapabilitiesNeverAnswered_managedWriteGoesOutWithoutTorque() {
        let wheel = makeController(.smartShiftEnhanced)
        wheel.start(desired: settings(.ratchet, force: 60))
        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: [0x01, 0x10, 0x32]))

        for _ in 0..<LogiWheelController.maxCapabilitiesAttempts { expireReplyTimeouts() }

        XCTAssertEqual(capabilityReads.count, LogiWheelController.maxCapabilitiesAttempts)
        XCTAssertTrue(scheduled.isEmpty, "no further read is waiting")
        XCTAssertTrue(wheel.capabilitiesKnown)
        XCTAssertFalse(wheel.supportsScrollForce)
        XCTAssertEqual(writes, [Sent(functionId: 2, params: [0x02, 0xFF, 0x00])])
        XCTAssertTrue(wheel.pendingFields.isEmpty)
    }

    func testCapabilitiesNeverAnswered_statusArrivingLater_stillWrites() {
        let wheel = makeController(.smartShiftEnhanced)
        wheel.start(desired: settings(.ratchet, force: 60))
        for _ in 0..<LogiWheelController.maxCapabilitiesAttempts { expireReplyTimeouts() }
        XCTAssertTrue(writes.isEmpty, "still waiting for the status read")

        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: [0x01, 0x10, 0x32]))
        XCTAssertEqual(writes, [Sent(functionId: 2, params: [0x02, 0xFF, 0x00])])
    }

    func testAnsweredCapabilities_timeoutDoesNothing() {
        let wheel = makeController(.smartShiftEnhanced)
        wheel.start(desired: settings(.freeSpin, force: 60))
        wheel.handleResponse(functionId: 0, report: report(functionId: 0, payload: [0x01, 0x10, 0x32]))
        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: [0x02, 0x10, 0x32]))
        let before = sent

        expireReplyTimeouts()

        XCTAssertEqual(sent, before)
        XCTAssertTrue(scheduled.isEmpty)
        XCTAssertTrue(wheel.supportsScrollForce)
    }

    func testCapabilitiesError_timeoutDoesNothing() {
        let wheel = makeController(.smartShiftEnhanced)
        wheel.start(desired: settings(.ratchet, force: 60))
        wheel.handleError(functionId: 0, errorCode: 0x02)
        let before = sent

        expireReplyTimeouts()

        XCTAssertEqual(sent, before)
        XCTAssertTrue(scheduled.isEmpty)
    }

    /// A timeout only speaks for the read it was armed for.
    func testStaleTimeoutOfAnEarlierRead_isIgnored() {
        let wheel = makeController(.smartShiftEnhanced)
        wheel.start(desired: .default)
        let first = scheduled[0].work

        first()
        XCTAssertEqual(capabilityReads.count, 2)
        first()
        XCTAssertEqual(capabilityReads.count, 2, "the first read's timeout fired twice")
    }

    func testUnmanaged_timeoutsNeverWrite() {
        let wheel = makeController(.smartShiftEnhanced)
        wheel.start(desired: settings(.ratchet, managed: false))
        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: [0x01, 0x10, 0x32]))

        for _ in 0..<LogiWheelController.maxCapabilitiesAttempts { expireReplyTimeouts() }

        XCTAssertTrue(writes.isEmpty)
        XCTAssertEqual(wheel.mode, .freeSpin)
    }

    func testAfterGivingUp_theNextRefreshAsksAgain_andLateCapabilitiesCompleteTheWrite() {
        let wheel = makeController(.smartShiftEnhanced)
        wheel.start(desired: settings(.ratchet, force: 60))
        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: [0x01, 0x10, 0x32]))
        for _ in 0..<LogiWheelController.maxCapabilitiesAttempts { expireReplyTimeouts() }
        XCTAssertEqual(writes, [Sent(functionId: 2, params: [0x02, 0xFF, 0x00])])
        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: [0x02, 0xFF, 0x32]))
        sent.removeAll()

        wheel.refresh()
        XCTAssertEqual(sent, [Sent(functionId: 0, params: []), Sent(functionId: 1, params: [])])
        XCTAssertFalse(wheel.capabilitiesKnown, "asked again, so unknown again until answered")
        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: [0x02, 0xFF, 0x32]))
        XCTAssertTrue(writes.isEmpty)

        // The mouse answers this time and can tune the force: the force that could not be
        // written before goes out now, after a fresh status read, and only the force.
        wheel.handleResponse(functionId: 0, report: report(functionId: 0, payload: [0x01, 0x10, 0x32]))
        XCTAssertEqual(sent.last, Sent(functionId: 1, params: []))
        XCTAssertTrue(writes.isEmpty, "must wait for the fresh status read")
        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: [0x02, 0xFF, 0x32]))
        XCTAssertEqual(writes, [Sent(functionId: 2, params: [0x02, 0x00, 60])])
    }

    func testLateCapabilitiesWithoutTunableTorque_writeNothingMore() {
        let wheel = makeController(.smartShiftEnhanced)
        wheel.start(desired: settings(.ratchet, force: 60))
        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: [0x01, 0x10, 0x32]))
        for _ in 0..<LogiWheelController.maxCapabilitiesAttempts { expireReplyTimeouts() }
        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: [0x02, 0xFF, 0x32]))
        XCTAssertEqual(writes.count, 1)

        wheel.handleResponse(functionId: 0, report: report(functionId: 0, payload: [0x00, 0x10, 0x32]))
        XCTAssertEqual(writes.count, 1)
        XCTAssertTrue(wheel.pendingFields.isEmpty)
    }

    // MARK: - Apply while connected

    func testApplyUnmanaged_sendsNothing() {
        let wheel = makeController(.smartShiftEnhanced)
        wheel.start(desired: .default)
        wheel.handleResponse(functionId: 0, report: report(functionId: 0, payload: [0x01, 0x10, 0x32]))
        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: [0x02, 0x10, 0x32]))
        let before = sent.count
        wheel.apply(settings(.freeSpin, managed: false))
        XCTAssertEqual(sent.count, before)
    }

    func testApplyManaged_rereadsThenWrites() {
        let wheel = makeController(.smartShiftEnhanced)
        wheel.start(desired: .default)
        wheel.handleResponse(functionId: 0, report: report(functionId: 0, payload: [0x01, 0x10, 0x32]))
        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: [0x02, 0x10, 0x32]))
        sent.removeAll()

        wheel.apply(settings(.freeSpin, force: 50))
        XCTAssertEqual(sent, [Sent(functionId: 1, params: [])], "capabilities are cached; only a fresh status read")
        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: [0x02, 0x10, 0x32]))
        XCTAssertEqual(writes, [Sent(functionId: 2, params: [0x01, 0x00, 0x00])], "the mouse already has force 50")
    }

    func testApply_latestSettingsWin() {
        let wheel = makeController(.smartShiftEnhanced)
        wheel.start(desired: .default)
        wheel.handleResponse(functionId: 0, report: report(functionId: 0, payload: [0x01, 0x10, 0x32]))
        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: [0x02, 0x10, 0x32]))
        wheel.apply(settings(.smartShift, sensitivity: 1, force: 20))
        wheel.apply(settings(.smartShift, sensitivity: 100, force: 80))
        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: [0x02, 0x10, 0x32]))
        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: [0x02, 0x10, 0x32]))
        XCTAssertEqual(writes, [Sent(functionId: 2, params: [0x02, 8, 80])])
    }

    // MARK: - SmartShift Toggle action

    func testToggle_enhanced_readsFn1_writesFn2_modeOnly() {
        let wheel = makeController(.smartShiftEnhanced)
        wheel.toggleMode()
        XCTAssertEqual(sent, [Sent(functionId: 1, params: [])])
        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: [0x02, 0x10, 0x32]))
        XCTAssertEqual(Array(sent.suffix(2)), [
            Sent(functionId: 2, params: [0x01, 0x00, 0x00]),
            Sent(functionId: 1, params: []),
        ])
        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: [0x01, 0x10, 0x32]))
        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(wheel.mode, .freeSpin)
    }

    func testToggle_basic_readsFn0_writesFn1() {
        let wheel = makeController(.smartShift)
        wheel.toggleMode()
        wheel.handleResponse(functionId: 0, report: report(functionId: 0, payload: [0x01, 0x10, 0x10]))
        XCTAssertEqual(sent, [
            Sent(functionId: 0, params: []),
            Sent(functionId: 1, params: [0x02, 0x00, 0x00]),
            Sent(functionId: 0, params: []),
        ])
    }

    func testSetAck_isConsumed_withoutWrites() {
        let wheel = makeController(.smartShiftEnhanced)
        XCTAssertTrue(wheel.handleResponse(functionId: 2, report: report(functionId: 2, payload: [0x02, 0x10, 0x32])))
        XCTAssertFalse(wheel.handleResponse(functionId: 5, report: report(functionId: 5, payload: [])))
        XCTAssertTrue(sent.isEmpty)
    }

    // MARK: - Manager / LogiCenter

    func testManagerStoresSettings_unmanagedIsNoOp() {
        let manager = LogiSessionManager()
        XCTAssertFalse(manager.wheelSettings.managedByMos, "default never manages the device")
        XCTAssertEqual(manager.wheelSettings, LogiWheelSettings(), "and sets nothing")
        let unmanaged = settings(.freeSpin, managed: false)
        manager.applyWheelSettings(unmanaged)
        XCTAssertEqual(manager.wheelSettings, unmanaged, "kept so devices connecting later stay untouched")
        let managed = settings(.ratchet, force: 30)
        manager.applyWheelSettings(managed)
        XCTAssertEqual(manager.wheelSettings, managed, "replayed to devices that connect later")
        XCTAssertTrue(manager.wheelDeviceStates().isEmpty)
    }

    func testLogiCenterWheelAPI_routesToManager_andRefreshPostsWhenNoDevices() {
        let manager = LogiSessionManager()
        let registry = UsageRegistry(sessionProvider: { [] })
        let center = LogiCenter(manager: manager, registry: registry)
        let managed = settings(.smartShift, sensitivity: 70)
        center.applyWheelSettings(managed)
        XCTAssertEqual(manager.wheelSettings, managed)
        XCTAssertTrue(center.wheelDeviceStates().isEmpty)

        let posted = expectation(forNotification: LogiCenter.wheelStateChanged, object: nil) { _ in
            Thread.isMainThread
        }
        center.refreshWheelStates()
        wait(for: [posted], timeout: 2)
    }

    func testDuplicateDeviceIdsAreDisambiguated() {
        let a = LogiWheelDeviceState(id: "046D:B042", deviceName: "MX Master 4", supportsSmartShift: true,
                                     supportsScrollForce: true, mode: .init(onMouse: .ratchet, setByYou: nil),
                                     smartShiftSensitivity: .init(onMouse: nil, setByYou: nil),
                                     scrollForce: .init(onMouse: 50, setByYou: 70))
        let states = LogiSessionManager.disambiguatedWheelStates([a, a])
        XCTAssertEqual(states.map { $0.id }, ["046D:B042", "046D:B042#2"])
        XCTAssertEqual(states[1].scrollForce, a.scrollForce, "only the id changes")
        XCTAssertEqual(states[1].mode, a.mode)
    }

    // MARK: - Unset values are never written (regressions)

    /// The regression: "Let Scrollio manage this mouse" turned on before the mouse had
    /// reported wrote the stored defaults (SmartShift / 50 / 50) to it.
    func testSwitchOnBeforeTheMouseReported_writesNothing() {
        let wheel = makeController(.smartShiftEnhanced)
        wheel.start(desired: .default)
        wheel.apply(LogiWheelSettings(managedByMos: true))
        XCTAssertNil(wheel.status, "nothing reported yet")

        wheel.handleResponse(functionId: 0, report: report(functionId: 0, payload: [0x01, 0x10, 0x32]))
        // Far from the old defaults: ratchet, force 100.
        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: [0x02, 0xFF, 100]))
        wheel.refresh()
        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: [0x02, 0xFF, 100]))

        XCTAssertTrue(writes.isEmpty)
        XCTAssertEqual(wheel.mode, .ratchet)
        XCTAssertEqual(wheel.scrollForce, 100)
    }

    /// The regression: with two mice, the second got the first one's values.
    func testTwoMiceNeverExchangeValues() {
        var sentA: [Sent] = []
        var sentB: [Sent] = []
        func controller(_ record: @escaping (Sent) -> Void) -> LogiWheelController {
            return LogiWheelController(
                feature: .smartShiftEnhanced, featureIndex: 0x0E,
                send: { record(Sent(functionId: $0, params: $1)) },
                schedule: { _, _ in }, onChange: {}
            )
        }
        let a = controller { sentA.append($0) }
        let b = controller { sentB.append($0) }
        let switchedOn = LogiWheelSettings(managedByMos: true)
        for (wheel, status) in [(a, [UInt8]([0x02, 0xFF, 100])), (b, [0x01, 0x0C, 30])] {
            wheel.start(desired: switchedOn)
            wheel.handleResponse(functionId: 0, report: report(functionId: 0, payload: [0x01, 0x10, 0x32]))
            wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: status))
        }
        XCTAssertTrue(sentA.filter { $0.functionId == 2 }.isEmpty, "each mouse keeps its own values")
        XCTAssertTrue(sentB.filter { $0.functionId == 2 }.isEmpty)

        // The user sets one value: each mouse gets that value and keeps everything else.
        let force = LogiWheelSettings(managedByMos: true, scrollForce: 70)
        for (wheel, status) in [(a, [UInt8]([0x02, 0xFF, 100])), (b, [0x01, 0x0C, 30])] {
            wheel.apply(force)
            wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: status))
        }
        XCTAssertEqual(sentA.filter { $0.functionId == 2 }, [Sent(functionId: 2, params: [0x02, 0x00, 70])], "A stays ratchet")
        XCTAssertEqual(sentB.filter { $0.functionId == 2 }, [Sent(functionId: 2, params: [0x01, 0x00, 70])], "B stays free-spin")
    }

    func testAnUnsetValueIsNeverWritten() {
        // Only the mode is set: the force and the threshold stay as the mouse has them.
        _ = connectedEnhanced(settings(.ratchet), status: [0x02, 0x10, 30])
        XCTAssertEqual(writes, [Sent(functionId: 2, params: [0x02, 0xFF, 0x00])])
        sent.removeAll()

        // Only the force is set: the mode byte repeats the mouse's own, the threshold is untouched.
        _ = connectedEnhanced(settings(force: 70), status: [0x01, 0x20, 30])
        XCTAssertEqual(writes, [Sent(functionId: 2, params: [0x01, 0x00, 70])])
        sent.removeAll()

        // Nothing set: nothing written, however far the mouse is from any default.
        let wheel = connectedEnhanced(settings(), status: [0x01, 0x30, 1])
        wheel.refresh()
        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: [0x02, 0xFF, 100]))
        wheel.apply(settings())
        XCTAssertTrue(writes.isEmpty)
        wheel.toggleMode()
        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: [0x02, 0xFF, 100]))
        XCTAssertEqual(writes, [Sent(functionId: 2, params: [0x01, 0x00, 0x00])], "only the SmartShift Toggle the user asked for")
    }

    func testASetValueIsWrittenOnce_andNotAgainWhenTheMouseHasIt() {
        let desired = settings(.smartShift, sensitivity: 70, force: 70)
        let wheel = connectedEnhanced(desired, status: [0x02, 0x10, 50])
        XCTAssertEqual(writes, [Sent(functionId: 2, params: [0x02, 13, 70])])
        XCTAssertEqual(sent.last, Sent(functionId: 1, params: []), "read back")

        wheel.handleResponse(functionId: 2, report: report(functionId: 2, payload: [0x02, 13, 70]))
        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: [0x02, 13, 70]))
        wheel.refresh()
        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: [0x02, 13, 70]))
        XCTAssertEqual(writes.count, 1, "the read-back and a refresh write nothing")

        // The same settings again write nothing and ask nothing.
        let before = sent
        wheel.apply(desired)
        XCTAssertEqual(sent, before)

        // Reconnected with the values already on the mouse: read, nothing written.
        wheel.start(desired: desired)
        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: [0x02, 13, 70]))
        XCTAssertEqual(writes.count, 1)
        XCTAssertTrue(logs.contains { $0.hasPrefix("Mode:") && $0.hasSuffix("already set, no write") })
        XCTAssertTrue(logs.contains { $0.hasPrefix("SmartShift sensitivity:") && $0.hasSuffix("already set, no write") })
        XCTAssertTrue(logs.contains { $0.hasPrefix("Scroll force:") && $0.hasSuffix("already set, no write") })
    }

    /// The owner's settings from before the values were optional: everything already on the mouse.
    func testTheOwnersStoredSettingsWriteNothingToHisMouse() {
        let stored = LogiWheelSettings(managedByMos: true, mode: .smartShift, smartShiftSensitivity: 51, scrollForce: 100)
        _ = connectedEnhanced(stored, status: [0x02, 0x10, 100])
        XCTAssertTrue(writes.isEmpty)
    }

    func testAChangeDecidesOnlyTheValueThatChanged() {
        // The mouse was switched to free-spin by its own button; the user then changes the force.
        let wheel = connectedEnhanced(settings(.smartShift, force: 50), status: [0x02, 0x10, 50])
        XCTAssertTrue(writes.isEmpty)
        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: [0x01, 0x10, 50]))
        wheel.apply(settings(.smartShift, force: 80))
        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: [0x01, 0x10, 50]))
        XCTAssertEqual(writes, [Sent(functionId: 2, params: [0x01, 0x00, 80])], "the mode is left as the mouse has it")
    }

    func testTurningTheSwitchOffAndOnDecidesEverySetValueAgain() {
        let desired = settings(force: 70)
        let wheel = connectedEnhanced(desired, status: [0x02, 0x10, 70])
        XCTAssertTrue(writes.isEmpty)
        // Logi Options+ changes the force while Scrollio does not manage the mouse.
        var off = desired
        off.managedByMos = false
        wheel.apply(off)
        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: [0x02, 0x10, 40]))
        XCTAssertTrue(writes.isEmpty, "not managed: nothing written")

        wheel.apply(desired)
        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: [0x02, 0x10, 40]))
        XCTAssertEqual(writes, [Sent(functionId: 2, params: [0x02, 0x00, 70])])
    }

    // MARK: - Mode and sensitivity

    func testSmartShiftOnAMouseWithoutAThreshold_getsTheFactoryDefaultUnlessTheUserSetOne() {
        _ = connectedEnhanced(settings(.smartShift), status: [0x02, 0xFF, 50])
        XCTAssertEqual(writes, [Sent(functionId: 2, params: [0x02, 16, 0x00])])
        XCTAssertTrue(logs.contains { $0.contains("writing the default 16 (50 %)") })
        sent.removeAll()

        _ = connectedEnhanced(settings(.smartShift, sensitivity: 100), status: [0x02, 0xFF, 50])
        XCTAssertEqual(writes, [Sent(functionId: 2, params: [0x02, 8, 0x00])])
    }

    func testANewModeBringsTheSetSensitivityAlong() {
        // Free-spin keeps an old threshold (16 = 50 %); the user wants SmartShift at 100 %.
        let wheel = connectedEnhanced(settings(.freeSpin, sensitivity: 100), status: [0x02, 0x10, 50])
        XCTAssertEqual(writes, [Sent(functionId: 2, params: [0x01, 0x00, 0x00])], "free-spin: the sensitivity waits")
        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: [0x01, 0x10, 50]))

        wheel.apply(settings(.smartShift, sensitivity: 100))
        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: [0x01, 0x10, 50]))
        XCTAssertEqual(writes.last, Sent(functionId: 2, params: [0x02, 8, 0x00]))
    }

    func testSensitivityAppliesOnlyInSmartShift() {
        let wheel = connectedEnhanced(settings(sensitivity: 80), status: [0x02, 0xFF, 50])
        XCTAssertTrue(writes.isEmpty, "a threshold would switch the ratchet mouse to SmartShift")
        XCTAssertTrue(logs.contains { $0.contains("applies only in SmartShift") })

        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: [0x02, 0x10, 50]))
        wheel.apply(settings(sensitivity: 90))
        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: [0x02, 0x10, 50]))
        XCTAssertEqual(writes, [Sent(functionId: 2, params: [0x02, 10, 0x00])], "in SmartShift it is written")
    }

    func testSensitivityWithinTheCoarseStepsOfTheMouseIsNotWrittenAgain() {
        // Threshold 17 reads back as 49 %: the same choice as 51 % (threshold 16).
        _ = connectedEnhanced(settings(sensitivity: 51), status: [0x02, 17, 50])
        XCTAssertTrue(writes.isEmpty)
        // 60 % is threshold 14; the mouse at 17 is 49 %: written.
        _ = connectedEnhanced(settings(sensitivity: 60), status: [0x02, 17, 50])
        XCTAssertEqual(writes, [Sent(functionId: 2, params: [0x02, 14, 0x00])])
    }

    // MARK: - Log and state

    func testEveryDecisionIsLogged() {
        _ = connectedEnhanced(settings(force: 70), status: [0x02, 0x10, 50])
        XCTAssertTrue(logs.contains { $0.hasPrefix("Connected:") && $0.contains("managed, user set scroll force 70") })
        XCTAssertTrue(logs.contains("Mode: not set by the user, left alone (mouse SmartShift)"))
        XCTAssertTrue(logs.contains("SmartShift sensitivity: not set by the user, left alone"))
        XCTAssertTrue(logs.contains("Scroll force: mouse 50, wanted 70; writing 70"))
        XCTAssertTrue(logs.contains { $0.hasPrefix("Writing 02 00 46") })

        logs.removeAll()
        _ = connectedEnhanced(settings(managed: false), status: [0x02, 0x10, 50])
        XCTAssertTrue(logs.contains { $0.hasSuffix("not managed, reading only") })
        XCTAssertFalse(logs.contains { $0.contains("writing") || $0.contains("Writing") })
    }

    func testAStatusIsLoggedOnlyWhenItChanges() {
        let wheel = connectedEnhanced(settings(managed: false), status: [0x02, 0x10, 50])
        let statusLines = { self.logs.filter { $0.hasPrefix("Mouse:") }.count }
        XCTAssertEqual(statusLines(), 1)
        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: [0x02, 0x10, 50]))
        XCTAssertEqual(statusLines(), 1)
        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: [0x01, 0x10, 50]))
        XCTAssertEqual(statusLines(), 2)
    }

    // MARK: - Why a set value differs

    private func forceValue(_ wheel: LogiWheelController) -> LogiMouseDeviceState.Value<Int> {
        return wheel.deviceState(id: "mx4", deviceName: "MX Master 4").scrollForce
    }

    private func status(_ wheel: LogiWheelController, _ payload: [UInt8]) {
        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: payload))
    }

    private func acknowledge(_ wheel: LogiWheelController) {
        wheel.handleResponse(functionId: 2, report: report(functionId: 2, payload: writes.last?.params ?? []))
    }

    func testUntilTheReadBackArrivesTheValueIsStillSending() {
        let wheel = makeController(.smartShiftEnhanced)
        wheel.start(desired: settings(force: 70))
        XCTAssertEqual(forceValue(wheel).mismatch, .sending, "waiting for the read that decides it")
        wheel.handleResponse(functionId: 0, report: report(functionId: 0, payload: [0x01, 0x10, 0x32]))
        status(wheel, [0x02, 0x10, 50])
        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(forceValue(wheel), .init(onMouse: 50, setByYou: 70, mismatch: .sending))
        acknowledge(wheel)
        XCTAssertEqual(forceValue(wheel).mismatch, .sending)
        status(wheel, [0x02, 0x10, 70])
        XCTAssertEqual(forceValue(wheel), .init(onMouse: 70, setByYou: 70))
    }

    func testARefusedWriteSaysSo() {
        let wheel = connectedEnhanced(settings(force: 70), status: [0x02, 0x10, 50])
        wheel.handleError(functionId: 2, errorCode: 0x02)
        status(wheel, [0x02, 0x10, 50])
        XCTAssertEqual(forceValue(wheel), .init(onMouse: 50, setByYou: 70, mismatch: .refused))
        XCTAssertEqual(writes.count, 1, "no retry")
    }

    func testAWriteWithoutAnAnswerSaysTheMouseDidNotAnswer() {
        let wheel = connectedEnhanced(settings(force: 70), status: [0x02, 0x10, 50])
        status(wheel, [0x02, 0x10, 50])  // the read-back; the write itself was never answered
        XCTAssertEqual(forceValue(wheel).mismatch, .noAnswer)
    }

    func testAnAnsweredWriteTheMouseDidNotKeepSaysSo() {
        let wheel = connectedEnhanced(settings(force: 70), status: [0x02, 0x10, 50])
        acknowledge(wheel)
        status(wheel, [0x02, 0x10, 50])
        XCTAssertEqual(forceValue(wheel).mismatch, .notKept)
    }

    /// A status read that went out before the write (a refresh as the tab appears) is
    /// answered before the write: it is not taken for the read-back.
    func testAReadSentBeforeTheWriteIsNotItsReadBack() {
        let wheel = makeController(.smartShiftEnhanced)
        wheel.start(desired: settings(force: 70))
        wheel.refresh()
        wheel.handleResponse(functionId: 0, report: report(functionId: 0, payload: [0x01, 0x10, 0x32]))
        status(wheel, [0x02, 0x10, 50])
        XCTAssertEqual(writes.count, 1)
        status(wheel, [0x02, 0x10, 50])  // the refresh's answer
        XCTAssertEqual(forceValue(wheel).mismatch, .sending, "the read-back is still to come")
        acknowledge(wheel)
        status(wheel, [0x02, 0x10, 70])
        XCTAssertEqual(forceValue(wheel), .init(onMouse: 70, setByYou: 70))
        XCTAssertEqual(writes.count, 1)
    }

    /// The mouse had the user's mode; its own button (or Logi Options+) changed it: said so,
    /// not fought. Starting again ("Send Again", as a reconnect) writes the mode back.
    func testAValueChangedLaterSaysSo_andStartingAgainWritesItBack() {
        let desired = settings(.ratchet, force: 70)
        let wheel = connectedEnhanced(desired, status: [0x02, 0xFF, 70])
        XCTAssertTrue(writes.isEmpty)
        status(wheel, [0x01, 0xFF, 70])
        XCTAssertEqual(wheel.deviceState(id: "mx4", deviceName: "MX Master 4").mode,
                       .init(onMouse: .freeSpin, setByYou: .ratchet, mismatch: .changedElsewhere))
        XCTAssertTrue(writes.isEmpty, "not fought")

        wheel.start(desired: desired)
        XCTAssertEqual(wheel.deviceState(id: "mx4", deviceName: "MX Master 4").mode.mismatch, .sending)
        status(wheel, [0x01, 0xFF, 70])
        XCTAssertEqual(writes.count, 1)
        XCTAssertNil(forceValue(wheel).mismatch, "the force was on the mouse all along")
    }

    func testUnmanagedThereIsNoReason() {
        let wheel = connectedEnhanced(settings(.ratchet, force: 70, managed: false), status: [0x02, 0x10, 50])
        let state = wheel.deviceState(id: "mx4", deviceName: "MX Master 4")
        XCTAssertNil(state.mode.mismatch)
        XCTAssertNil(state.scrollForce.mismatch)
        XCTAssertTrue(writes.isEmpty)
    }

    func testDeviceStateHasTheShapeOfTheBasics() {
        let wheel = connectedEnhanced(settings(.ratchet, sensitivity: 51, force: 150), status: [0x02, 0x10, 100])
        wheel.handleResponse(functionId: 1, report: report(functionId: 1, payload: [0x02, 0x10, 100]))
        let state = wheel.deviceState(id: "mx4", deviceName: "MX Master 4")
        XCTAssertEqual(state.mode.onMouse, .smartShift)
        XCTAssertEqual(state.mode.setByYou, .ratchet)
        XCTAssertEqual(state.mode.source, .user)
        XCTAssertFalse(state.mode.mouseMatches)
        XCTAssertEqual(state.smartShiftSensitivity.setByYou, 50, "51 % as the mouse keeps it")
        XCTAssertTrue(state.smartShiftSensitivity.mouseMatches)
        XCTAssertEqual(state.scrollForce.setByYou, 100, "clamped")
        XCTAssertTrue(state.scrollForce.mouseMatches)

        let unset = connectedEnhanced(settings(), status: [0x01, 0x10, 30])
            .deviceState(id: "mx4", deviceName: "MX Master 4")
        XCTAssertEqual(unset.mode, .init(onMouse: .freeSpin, setByYou: nil))
        XCTAssertEqual(unset.mode.source, .mouse)
        XCTAssertTrue(unset.mode.mouseMatches)
        XCTAssertEqual(unset.scrollForce, .init(onMouse: 30, setByYou: nil))
    }
}
