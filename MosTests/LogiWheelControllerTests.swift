import XCTest
@testable import Mos_Debug

/// LogiWheelController against fake response bytes: what it sends, when it writes,
/// and that it never writes unless the settings are managed by Mos.
final class LogiWheelControllerTests: XCTestCase {

    private struct Sent: Equatable {
        let functionId: UInt8
        let params: [UInt8]
    }

    private var sent: [Sent] = []
    private var changes = 0

    override func setUp() {
        super.setUp()
        sent = []
        changes = 0
    }

    private func makeController(_ feature: LogiWheelFeature) -> LogiWheelController {
        return LogiWheelController(
            feature: feature,
            featureIndex: 0x0E,
            send: { [unowned self] functionId, params in
                self.sent.append(Sent(functionId: functionId, params: params))
            },
            onChange: { [unowned self] in self.changes += 1 }
        )
    }

    private func report(functionId: UInt8, payload: [UInt8]) -> [UInt8] {
        var bytes: [UInt8] = [0x11, 0xFF, 0x0E, (functionId << 4) | 0x01] + payload
        while bytes.count < 20 { bytes.append(0) }
        return bytes
    }

    private func settings(
        _ mode: LogiWheelMode,
        sensitivity: Int = 50,
        force: Int = 50,
        managed: Bool = true
    ) -> LogiWheelSettings {
        return LogiWheelSettings(managedByMos: managed, mode: mode, smartShiftSensitivity: sensitivity, scrollForce: force)
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
        XCTAssertNil(wheel.pendingSettings)
        XCTAssertTrue(writes.isEmpty)
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
        XCTAssertEqual(writes, [Sent(functionId: 2, params: [0x01, 0x00, 50])])
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
                                     supportsScrollForce: true, mode: .ratchet, smartShiftSensitivity: nil, scrollForce: 50)
        let states = LogiSessionManager.disambiguatedWheelStates([a, a])
        XCTAssertEqual(states.map { $0.id }, ["046D:B042", "046D:B042#2"])
    }
}
