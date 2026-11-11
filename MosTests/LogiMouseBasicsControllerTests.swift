import XCTest
@testable import Mos_Debug

/// LogiMouseBasicsController against a fake mouse that answers with bytes: what it sends,
/// one request at a time, when it writes, and that it never writes unless the mouse is
/// managed, the user set the value and the mouse reports something else.
final class LogiMouseBasicsControllerTests: XCTestCase {

    typealias Basic = LogiMouseDeviceState.Basic

    // Feature indices as on the owner's MX Master 4 (Solaar dump).
    static let batteryIndex: UInt8 = 0x09
    static let dpiIndex: UInt8 = 0x14
    static let hapticIndex: UInt8 = 0x0B
    static let pressIndex: UInt8 = 0x0C

    static let mxMaster4 = LogiMouseBasicsController.Features(
        battery: .init(feature: .unified, index: batteryIndex),
        pointerSpeed: dpiIndex,
        haptics: hapticIndex,
        pressForce: pressIndex
    )

    struct Sent: Hashable {
        let index: UInt8
        let functionId: UInt8
        let params: [UInt8]
    }

    /// Answers like a mouse: one answer per request, writes change its state.
    final class FakeMouse {
        typealias T = LogiMouseBasicsControllerTests

        var battery: [UInt8] = [0x2D, 0x04, 0x00]                       // 45 %, good, discharging
        var dpiList: [UInt8] = [0x00, 0x00, 0xC8, 0xE0, 0x32, 0x1F, 0x40, 0x00, 0x00]  // 200...8000 / 50
        var dpi = 1000
        var defaultDPI = 1000
        var hapticFlags: UInt8 = 0x00                                    // the owner's: off, 100
        var hapticStrength: UInt8 = 100
        var hapticLevels: UInt8 = 0x00
        var pressInfo: [UInt8] = [0x00, 0x01, 0x13, 0xE1, 0x1A, 0x70, 0x0F, 0xE7]  // changeable 4071...6768, 5089
        var press: UInt16 = 5089
        /// The firmware's rounding of a DPI write.
        var roundDPI: (Int) -> Int = { $0 }
        /// Requests answered with an HID++ error instead.
        var refused: Set<String> = []

        static func key(_ index: UInt8, _ functionId: UInt8) -> String { "\(index)/\(functionId)" }

        /// The payload of the answer, or nil for an error.
        func answer(_ request: Sent) -> [UInt8]? {
            guard !refused.contains(Self.key(request.index, request.functionId)) else { return nil }
            switch (request.index, request.functionId) {
            case (T.batteryIndex, 1): return battery
            case (T.dpiIndex, 1): return dpiList
            case (T.dpiIndex, 2): return [0x00, UInt8(dpi >> 8), UInt8(dpi & 0xFF), UInt8(defaultDPI >> 8), UInt8(defaultDPI & 0xFF)]
            case (T.dpiIndex, 3):
                dpi = roundDPI(Int(request.params[1]) << 8 | Int(request.params[2]))
                return Array(request.params.prefix(3))
            case (T.hapticIndex, 1): return [hapticFlags, hapticStrength, hapticLevels]
            case (T.hapticIndex, 2):
                hapticFlags = request.params[0]
                hapticStrength = request.params[1]
                return [hapticFlags, hapticStrength, hapticLevels]
            case (T.hapticIndex, 4): return []
            case (T.pressIndex, 1): return pressInfo
            case (T.pressIndex, 2): return [UInt8(press >> 8), UInt8(press & 0xFF)]
            case (T.pressIndex, 3):
                press = UInt16(request.params[1]) << 8 | UInt16(request.params[2])
                return []
            default: return []
            }
        }
    }

    private var sent: [Sent] = []
    private var answered = 0
    private var scheduled: [(delay: TimeInterval, work: () -> Void)] = []
    private var changes = 0
    private var logs: [String] = []
    private var clock = Date(timeIntervalSince1970: 1_000_000)
    private var mouse = FakeMouse()

    override func setUp() {
        super.setUp()
        sent = []
        answered = 0
        scheduled = []
        changes = 0
        logs = []
        clock = Date(timeIntervalSince1970: 1_000_000)
        mouse = FakeMouse()
    }

    private func makeController(_ features: LogiMouseBasicsController.Features = mxMaster4) -> LogiMouseBasicsController {
        return LogiMouseBasicsController(
            features: features,
            send: { [unowned self] index, functionId, params in
                self.sent.append(Sent(index: index, functionId: functionId, params: params))
            },
            schedule: { [unowned self] delay, work in self.scheduled.append((delay, work)) },
            now: { [unowned self] in self.clock },
            onChange: { [unowned self] in self.changes += 1 },
            log: { [unowned self] in self.logs.append($0) }
        )
    }

    private func report(_ index: UInt8, _ functionId: UInt8, _ payload: [UInt8], softwareId: UInt8 = 1) -> [UInt8] {
        var bytes: [UInt8] = [0x11, 0xFF, index, functionId << 4 | softwareId] + payload
        while bytes.count < 20 { bytes.append(0) }
        return Array(bytes.prefix(20))
    }

    /// Answers the request sent last, if it has not been answered yet. Returns false when
    /// nothing is waiting.
    @discardableResult
    private func answerNext(_ controller: LogiMouseBasicsController) -> Bool {
        guard answered < sent.count else { return false }
        XCTAssertEqual(sent.count, answered + 1, "one request at a time")
        let request = sent[answered]
        answered += 1
        if let payload = mouse.answer(request) {
            controller.handleResponse(featureIndex: request.index, functionId: request.functionId,
                                      report: report(request.index, request.functionId, payload))
        } else {
            controller.handleError(featureIndex: request.index, functionId: request.functionId, errorCode: 0x05)
        }
        return true
    }

    private func answerAll(_ controller: LogiMouseBasicsController, file: StaticString = #filePath, line: UInt = #line) {
        var guardCount = 0
        while answerNext(controller) {
            guardCount += 1
            if guardCount > 100 { XCTFail("the controller never stops asking", file: file, line: line); return }
        }
    }

    /// Lets every pending reply timeout expire, as the main queue would after the delay.
    private func expireReplyTimeouts() {
        let work = scheduled
        scheduled = []
        work.forEach { $0.work() }
    }

    private var writes: [Sent] {
        sent.filter {
            ($0.index == Self.dpiIndex && $0.functionId == 3)
                || ($0.index == Self.hapticIndex && $0.functionId == 2)
                || ($0.index == Self.pressIndex && $0.functionId == 3)
        }
    }

    private func started(
        _ desired: LogiMouseSettings = .default,
        managed: Bool = false,
        features: LogiMouseBasicsController.Features = mxMaster4
    ) -> LogiMouseBasicsController {
        let controller = makeController(features)
        controller.start(desired: desired, managed: managed)
        answerAll(controller)
        return controller
    }

    // MARK: - Reading

    func testStartReadsEverythingInOrder_oneRequestAtATime() {
        let controller = makeController()
        controller.start(desired: .default, managed: false)
        XCTAssertEqual(sent.count, 1, "the mouse answers one request at a time")
        answerAll(controller)

        XCTAssertEqual(sent, [
            Sent(index: Self.batteryIndex, functionId: 1, params: []),          // getStatus (fn1, not fn0)
            Sent(index: Self.dpiIndex, functionId: 1, params: [0, 0, 0]),        // DPI list
            Sent(index: Self.dpiIndex, functionId: 2, params: [0, 0, 0]),        // current DPI
            Sent(index: Self.hapticIndex, functionId: 1, params: []),            // haptic state
            Sent(index: Self.pressIndex, functionId: 1, params: [0, 0, 0]),      // press force range
            Sent(index: Self.pressIndex, functionId: 2, params: [0, 0, 0]),      // press force
        ])
        XCTAssertEqual(controller.battery, LogiMouseDeviceState.Battery(percent: 45, level: .good, charging: .discharging, isApproximate: false))
        XCTAssertEqual(controller.dpi, 1000)
        XCTAssertEqual(controller.dpiList?.values.count, 157)
        XCTAssertEqual(controller.hapticState, LogiHapticSettingsProtocol.State(flags: 0, strength: 100, levelsByte: 0))
        XCTAssertEqual(controller.pressForce, 5089)
        XCTAssertGreaterThan(changes, 0)
        XCTAssertTrue(controller.isIdle)
    }

    func testUnmanaged_readsOnly_evenWithEverythingSet() {
        let controller = started(LogiMouseSettings(pointerDPI: 1600, hapticsOn: true, hapticStrength: 30, pressForce: 6000), managed: false)
        XCTAssertEqual(writes, [])
        controller.refresh()
        answerAll(controller)
        XCTAssertEqual(writes, [])
        XCTAssertTrue(logs.contains { $0.contains("not managed, reading only") })
    }

    func testManagedWithNothingSet_readsOnly() {
        _ = started(.default, managed: true)
        XCTAssertEqual(writes, [])
        XCTAssertEqual(sent.count, 6)
    }

    func testLegacyBatteryReadsFunctionZero() {
        let features = LogiMouseBasicsController.Features(battery: .init(feature: .legacy, index: Self.batteryIndex))
        let controller = makeController(features)
        controller.start(desired: .default, managed: false)
        XCTAssertEqual(sent, [Sent(index: Self.batteryIndex, functionId: 0, params: [])])
        controller.handleResponse(featureIndex: Self.batteryIndex, functionId: 0, report: report(Self.batteryIndex, 0, [50, 20, 0]))
        XCTAssertEqual(controller.battery?.percent, 50)
        XCTAssertEqual(controller.battery?.isApproximate, true)
    }

    // MARK: - Writing

    func testWritesOnlyTheFieldThatDiffers_afterItsRead_thenReadsBack() {
        // Haptics already off on the mouse; DPI differs; press force not set.
        let controller = makeController()
        controller.start(desired: LogiMouseSettings(pointerDPI: 1600, hapticsOn: false), managed: true)
        answerNext(controller)  // battery
        answerNext(controller)  // DPI list
        XCTAssertEqual(writes, [], "no write before the current DPI was read")
        answerAll(controller)

        XCTAssertEqual(writes, [Sent(index: Self.dpiIndex, functionId: 3, params: [0x00, 0x06, 0x40])])
        let writeAt = sent.firstIndex(of: writes[0])!
        XCTAssertEqual(sent[writeAt + 1], Sent(index: Self.dpiIndex, functionId: 2, params: [0, 0, 0]), "read back right after")
        XCTAssertEqual(controller.dpi, 1600)
        XCTAssertTrue(logs.contains("Pointer speed: mouse 1000, wanted 1600; writing 1600"))
        XCTAssertTrue(logs.contains { $0.hasPrefix("Haptics:") && $0.contains("already set, no write") })
    }

    func testSnapsToTheNearestValueTheMouseAccepts() {
        _ = started(LogiMouseSettings(pointerDPI: 1234), managed: true)
        XCTAssertEqual(writes, [Sent(index: Self.dpiIndex, functionId: 3, params: [0x00, 0x04, 0xE2])])  // 1250
        XCTAssertTrue(logs.contains { $0.contains("wanted 1234 (nearest it accepts: 1250); writing 1250") })
    }

    func testNoDPIWriteWithoutAList() {
        mouse.dpiList = [0x00, 0xE0, 0x32, 0x1F, 0x40, 0x00, 0x00]   // leading marker: malformed
        let controller = started(LogiMouseSettings(pointerDPI: 1600), managed: true)
        XCTAssertEqual(writes, [])
        XCTAssertNil(controller.dpiList)
        XCTAssertTrue(logs.contains { $0.contains("unreadable DPI list") })
        XCTAssertTrue(logs.contains { $0.contains("the DPI list is unknown, not writing") })
    }

    func testFirmwareRoundingIsAcceptedWithoutALoop() {
        mouse.roundDPI = { $0 / 100 * 100 }
        let controller = started(LogiMouseSettings(pointerDPI: 1650), managed: true)
        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(controller.dpi, 1600)
        XCTAssertTrue(logs.contains { $0.contains("wrote 1650, the mouse reports 1600; keeping the mouse's value, no retry") })

        controller.refresh()
        answerAll(controller)
        XCTAssertEqual(writes.count, 1, "no retry until the setting changes")

        let state = controller.deviceState(id: "x", deviceName: "MX", wheel: nil)
        XCTAssertEqual(state.pointerSpeed?.dpi, LogiMouseDeviceState.Value(onMouse: 1600, setByYou: 1650))
        XCTAssertEqual(state.pointerSpeed?.dpi.mouseMatches, false)
    }

    func testEveryConnectWritesAgain() {
        _ = started(LogiMouseSettings(pointerDPI: 1600), managed: true)
        XCTAssertEqual(writes.count, 1)
        mouse.dpi = 1000   // forgot it over a power cycle
        let reconnected = makeController()
        let before = sent.count
        answered = before
        reconnected.start(desired: LogiMouseSettings(pointerDPI: 1600), managed: true)
        answerAll(reconnected)
        XCTAssertEqual(writes.count, 2)
        XCTAssertEqual(mouse.dpi, 1600)
    }

    func testSameControllerStartedAgainWritesAgain() {
        let controller = started(LogiMouseSettings(pointerDPI: 1600), managed: true)
        mouse.dpi = 1000
        controller.start(desired: LogiMouseSettings(pointerDPI: 1600), managed: true)
        answerAll(controller)
        XCTAssertEqual(writes.count, 2)
    }

    func testAMatchingMouseGetsNoWrite() {
        mouse.dpi = 1600
        _ = started(LogiMouseSettings(pointerDPI: 1600), managed: true)
        XCTAssertEqual(writes, [])
        XCTAssertTrue(logs.contains("Pointer speed: mouse 1600, wanted 1600; already set, no write"))
    }

    // MARK: - Settings changes and the switch

    func testAChangedValueIsReadAgainAndWrittenOnce() {
        let controller = started(.default, managed: true)
        let before = sent.count
        controller.apply(desired: LogiMouseSettings(pointerDPI: 800), managed: true)
        XCTAssertEqual(sent.last, Sent(index: Self.dpiIndex, functionId: 2, params: [0, 0, 0]), "a fresh read first")
        answerAll(controller)
        XCTAssertEqual(Array(sent[before...]).filter { $0.functionId == 3 }, [Sent(index: Self.dpiIndex, functionId: 3, params: [0x00, 0x03, 0x20])])

        let afterWrite = sent.count
        controller.apply(desired: LogiMouseSettings(pointerDPI: 800), managed: true)
        answerAll(controller)
        XCTAssertEqual(sent.count, afterWrite, "the same settings again: nothing to do")
    }

    func testTurningTheSwitchOnWritesWhatTheUserSet() {
        let desired = LogiMouseSettings(pointerDPI: 2000, hapticsOn: true)
        let controller = started(desired, managed: false)
        XCTAssertEqual(writes, [])
        controller.apply(desired: desired, managed: true)
        answerAll(controller)
        XCTAssertEqual(writes, [
            Sent(index: Self.dpiIndex, functionId: 3, params: [0x00, 0x07, 0xD0]),
            Sent(index: Self.hapticIndex, functionId: 2, params: [0x01, 100, 0]),
        ])
    }

    func testTurningTheSwitchOffDropsWritesThatHaveNotGoneOut() {
        let controller = makeController()
        controller.start(desired: LogiMouseSettings(pointerDPI: 1600, hapticsOn: true), managed: true)
        answerNext(controller)  // battery
        answerNext(controller)  // list
        answerNext(controller)  // current: the DPI write is queued behind the haptic read
        controller.apply(desired: LogiMouseSettings(pointerDPI: 1600, hapticsOn: true), managed: false)
        answerAll(controller)
        XCTAssertEqual(writes, [])
        XCTAssertTrue(logs.contains("Not managed any more: nothing is written"))
    }

    func testClearingAValueWritesNothing() {
        let controller = started(LogiMouseSettings(pointerDPI: 1600), managed: true)
        let before = writes.count
        controller.apply(desired: .default, managed: true)
        answerAll(controller)
        XCTAssertEqual(writes.count, before)
    }

    // MARK: - Haptics

    func testHapticOnKeepsPowerSaveAndStrength() {
        mouse.hapticFlags = 0x02
        mouse.hapticStrength = 40
        _ = started(LogiMouseSettings(hapticsOn: true), managed: true)
        XCTAssertEqual(writes, [Sent(index: Self.hapticIndex, functionId: 2, params: [0x03, 40, 0])])
        XCTAssertEqual(mouse.hapticFlags, 0x03)
    }

    func testHapticOffKeepsPowerSaveAndStrength() {
        mouse.hapticFlags = 0x83
        mouse.hapticStrength = 75
        _ = started(LogiMouseSettings(hapticsOn: false), managed: true)
        XCTAssertEqual(writes, [Sent(index: Self.hapticIndex, functionId: 2, params: [0x82, 75, 0])])
        XCTAssertEqual(mouse.hapticStrength, 75, "switching off never resets the strength")
    }

    func testHapticStrengthOnlyLeavesTheMouseOff() {
        // The owner's mouse: 00 64 00 (off, 100).
        _ = started(LogiMouseSettings(hapticStrength: 30), managed: true)
        XCTAssertEqual(writes, [Sent(index: Self.hapticIndex, functionId: 2, params: [0x00, 30, 0])])
    }

    func testFewLevelMiceGetASnappedStrength() {
        mouse.hapticFlags = 0x01
        mouse.hapticLevels = 0x01
        let controller = started(LogiMouseSettings(hapticStrength: 60), managed: true)
        XCTAssertEqual(writes, [Sent(index: Self.hapticIndex, functionId: 2, params: [0x01, 50, 0])])
        let haptics = controller.deviceState(id: "x", deviceName: "MX", wheel: nil).haptics
        XCTAssertEqual(haptics?.hasFewLevels, true)
        XCTAssertEqual(haptics?.strength.setByYou, 50)
    }

    func testAShortHapticStateIsNeverWrittenFrom() {
        let controller = makeController()
        controller.start(desired: LogiMouseSettings(hapticsOn: true), managed: true)
        for _ in 0..<3 { answerNext(controller) }  // battery, list, current
        let request = sent[answered]
        XCTAssertEqual(request, Sent(index: Self.hapticIndex, functionId: 1, params: []))
        answered += 1
        controller.handleResponse(featureIndex: Self.hapticIndex, functionId: 1, report: [0x11, 0xFF, Self.hapticIndex, 0x11, 0x01])
        answerAll(controller)
        XCTAssertEqual(writes, [])
        XCTAssertTrue(logs.contains { $0.hasPrefix("Haptics: unreadable state") })
    }

    func testSamplePulsePlaysAfterTheStrengthWasWritten() {
        mouse.hapticFlags = 0x01
        mouse.hapticStrength = 60
        let controller = started(.default, managed: true)
        let before = sent.count
        controller.apply(desired: LogiMouseSettings(hapticStrength: 20), managed: true)
        controller.playSample()
        answerAll(controller)
        XCTAssertEqual(Array(sent[before...]), [
            Sent(index: Self.hapticIndex, functionId: 1, params: []),
            Sent(index: Self.hapticIndex, functionId: 2, params: [0x01, 20, 0]),
            Sent(index: Self.hapticIndex, functionId: 1, params: []),
            Sent(index: Self.hapticIndex, functionId: 4, params: [0x01]),
        ])
    }

    func testSamplePulseIsSkippedWhileHapticsAreOff() {
        let controller = started(.default, managed: true)   // owner's mouse: off
        let before = sent.count
        controller.playSample()
        answerAll(controller)
        XCTAssertEqual(sent.count, before)
        XCTAssertTrue(logs.contains("Haptics: sample pulse skipped, haptics are off on the mouse"))
    }

    func testAGestureSwitchOnIsFollowed() {
        let controller = started(.default, managed: false)
        let before = sent.count
        // Not asked by this controller: the gesture controller's setState answer.
        controller.handleResponse(featureIndex: Self.hapticIndex, functionId: 2,
                                  report: report(Self.hapticIndex, 2, [0x01, 100, 0]))
        XCTAssertEqual(Array(sent[before...]), [Sent(index: Self.hapticIndex, functionId: 1, params: [])], "reads the new state")
        mouse.hapticFlags = 0x01
        answerAll(controller)
        XCTAssertEqual(controller.hapticState?.isOn, true)
    }

    // MARK: - Press force

    func testPressForceIsClampedToTheMousesRange() {
        _ = started(LogiMouseSettings(pressForce: 7000), managed: true)
        XCTAssertEqual(writes, [Sent(index: Self.pressIndex, functionId: 3, params: [0x00, 0x1A, 0x70])])  // 6768
        XCTAssertEqual(mouse.press, 6768)
        XCTAssertTrue(logs.contains { $0.contains("clamped to 6768, range 4071...6768") })
    }

    func testPressForceIsNotWrittenWhenNotChangeable() {
        mouse.pressInfo = [0x00, 0x00, 0x13, 0xE1, 0x1A, 0x70, 0x0F, 0xE7]
        _ = started(LogiMouseSettings(pressForce: 6000), managed: true)
        XCTAssertEqual(writes, [])
        XCTAssertTrue(logs.contains { $0.contains("does not allow changing it") })
    }

    func testPressForceIsNotWrittenWithAnUnusableRange() {
        mouse.pressInfo = [0x00, 0x01, 0x30, 0x00, 0x1A, 0x70, 0x0F, 0xE7]   // default 12288 outside 4071...6768
        let controller = started(LogiMouseSettings(pressForce: 6000), managed: true)
        XCTAssertEqual(writes, [])
        XCTAssertNil(controller.deviceState(id: "x", deviceName: "MX", wheel: nil).pressForce?.range)
    }

    // MARK: - Errors and timeouts

    func testAnErrorOnAReadStopsThatFeatureOnly() {
        mouse.refused = [FakeMouse.key(Self.dpiIndex, 1)]
        let controller = started(LogiMouseSettings(pointerDPI: 1600, hapticsOn: true), managed: true)
        XCTAssertFalse(sent.contains { $0.index == Self.dpiIndex && $0.functionId == 2 }, "the rest of DPI is not asked")
        XCTAssertFalse(controller.supported.contains(.pointerSpeed))
        XCTAssertEqual(writes, [Sent(index: Self.hapticIndex, functionId: 2, params: [0x01, 100, 0])], "the others go on")
        let state = controller.deviceState(id: "x", deviceName: "MX", wheel: nil)
        XCTAssertNil(state.pointerSpeed)
        XCTAssertNotNil(state.battery)
        XCTAssertTrue(logs.contains { $0.contains("refused the DPI list (error 0x05)") })
    }

    func testAnErrorOnAWriteIsFollowedByTheReadBack() {
        mouse.refused = [FakeMouse.key(Self.dpiIndex, 3)]
        let controller = started(LogiMouseSettings(pointerDPI: 1600), managed: true)
        let writeAt = sent.firstIndex { $0.index == Self.dpiIndex && $0.functionId == 3 }!
        XCTAssertEqual(sent[writeAt + 1], Sent(index: Self.dpiIndex, functionId: 2, params: [0, 0, 0]))
        XCTAssertTrue(controller.supported.contains(.pointerSpeed))
        XCTAssertEqual(controller.dpi, 1000)
        XCTAssertEqual(writes.count, 1, "no retry")
    }

    func testAnErrorForSomebodyElsesRequestIsIgnored() {
        let controller = started(.default, managed: false)
        controller.handleError(featureIndex: Self.hapticIndex, functionId: 2, errorCode: 0x02)
        XCTAssertTrue(controller.supported.contains(.haptics))
    }

    func testANotAnsweredReadIsAskedAgainThenGivenUp() {
        let controller = makeController()
        controller.start(desired: .default, managed: false)
        XCTAssertEqual(sent.count, 1)
        expireReplyTimeouts()
        expireReplyTimeouts()
        XCTAssertEqual(sent.count, 3, "three sends of the battery read")
        XCTAssertEqual(Set(sent), [Sent(index: Self.batteryIndex, functionId: 1, params: [])])
        expireReplyTimeouts()
        XCTAssertEqual(sent.count, 4)
        XCTAssertEqual(sent.last, Sent(index: Self.dpiIndex, functionId: 1, params: [0, 0, 0]), "on to the next read")
        XCTAssertTrue(logs.contains { $0.contains("no answer to the battery status, giving up") })
    }

    func testALateTimeoutOfAnAnsweredRequestDoesNothing() {
        let controller = makeController()
        controller.start(desired: .default, managed: false)
        answered = 0
        answerNext(controller)  // battery answered; DPI list on its way
        let count = sent.count
        scheduled.first?.work()  // the battery's timeout fires late
        XCTAssertEqual(sent.count, count)
    }

    // MARK: - Battery

    func testABatteryEventUpdatesTheState() {
        let controller = started()
        let changesBefore = changes
        controller.handleEvent(featureIndex: Self.batteryIndex, functionId: 0,
                               report: report(Self.batteryIndex, 0, [0x2E, 0x04, 0x01], softwareId: 0))
        XCTAssertEqual(controller.battery?.percent, 46)
        XCTAssertEqual(controller.battery?.charging, .charging)
        XCTAssertEqual(changes, changesBefore + 1)
        XCTAssertTrue(logs.contains("Battery: 46 %, charging, level good"))
    }

    func testTheSameBatteryValueIsNotLoggedAgain() {
        let controller = started()
        let count = logs.count
        let changesBefore = changes
        controller.handleEvent(featureIndex: Self.batteryIndex, functionId: 0,
                               report: report(Self.batteryIndex, 0, [0x2D, 0x04, 0x00], softwareId: 0))
        XCTAssertFalse(logs[count...].contains { $0.hasPrefix("Battery: 45") })
        XCTAssertEqual(changes, changesBefore, "nothing new to show")
    }

    func testRefreshReadsTheBatteryOnlyWhenItIsOld() {
        let controller = started()
        let before = sent.count
        controller.refresh()
        answerAll(controller)
        XCTAssertFalse(sent[before...].contains { $0.index == Self.batteryIndex }, "read moments ago")
        XCTAssertTrue(sent[before...].contains { $0.index == Self.dpiIndex && $0.functionId == 2 })
        XCTAssertFalse(sent[before...].contains { $0.index == Self.dpiIndex && $0.functionId == 1 }, "the list is known")

        clock += LogiMouseBasicsController.batteryRefreshInterval
        let later = sent.count
        controller.refresh()
        answerAll(controller)
        XCTAssertTrue(sent[later...].contains { $0.index == Self.batteryIndex })
    }

    // MARK: - Others on the same features

    func testADPIChangeFromElsewhereIsFollowed() {
        let controller = started(.default, managed: false)
        let before = sent.count
        // The DPI buttons' setSensorDpi answer, not asked by this controller.
        controller.handleResponse(featureIndex: Self.dpiIndex, functionId: 3, report: report(Self.dpiIndex, 3, [0x00, 0x04, 0xB0]))
        XCTAssertEqual(Array(sent[before...]), [Sent(index: Self.dpiIndex, functionId: 2, params: [0, 0, 0])])
        mouse.dpi = 1200
        answerAll(controller)
        XCTAssertEqual(controller.dpi, 1200)
    }

    func testAnUnaskedReadOfTheSameValueUpdatesTheState() {
        let controller = started()
        controller.handleResponse(featureIndex: Self.dpiIndex, functionId: 2, report: report(Self.dpiIndex, 2, [0x00, 0x03, 0x20, 0x03, 0xE8]))
        XCTAssertEqual(controller.dpi, 800)
    }

    func testReportsOnOtherIndicesAreNotClaimed() {
        let controller = started()
        XCTAssertFalse(controller.handleResponse(featureIndex: 0x0E, functionId: 1, report: report(0x0E, 1, [1, 2, 3])))
        XCTAssertFalse(controller.owns(featureIndex: 0x0E))
        XCTAssertTrue(controller.owns(featureIndex: Self.pressIndex))
    }

    // MARK: - Snapshot

    func testSnapshotSaysWhereEachValueComesFrom() {
        let controller = started(LogiMouseSettings(pointerDPI: 1600, hapticStrength: 30), managed: false)
        let state = controller.deviceState(id: "046D:B042", deviceName: "MX Master 4", wheel: nil)
        XCTAssertEqual(state.supported, Set(Basic.allCases))
        XCTAssertFalse(state.managed)
        XCTAssertEqual(state.pointerSpeed?.dpi, LogiMouseDeviceState.Value(onMouse: 1000, setByYou: 1600))
        XCTAssertEqual(state.pointerSpeed?.dpi.source, .user)
        XCTAssertEqual(state.pointerSpeed?.defaultDPI, 1000)
        XCTAssertEqual(state.pointerSpeed?.choices.first, 200)
        XCTAssertEqual(state.haptics?.isOn, LogiMouseDeviceState.Value(onMouse: false, setByYou: nil))
        XCTAssertEqual(state.haptics?.isOn.source, .mouse)
        XCTAssertEqual(state.haptics?.strength, LogiMouseDeviceState.Value(onMouse: 100, setByYou: 30))
        XCTAssertEqual(state.haptics?.hasFewLevels, false)
        XCTAssertEqual(state.pressForce?.range, 4071...6768)
        XCTAssertEqual(state.pressForce?.defaultForce, 5089)
        XCTAssertEqual(state.pressForce?.isChangeable, true)
        XCTAssertEqual(state.pressForce?.force, LogiMouseDeviceState.Value(onMouse: 5089, setByYou: nil))
        XCTAssertEqual(state.battery?.percent, 45)
    }

    func testSnapshotOfAMouseWithoutHapticsOrPressForce() {
        let features = LogiMouseBasicsController.Features(
            battery: .init(feature: .unified, index: Self.batteryIndex),
            pointerSpeed: Self.dpiIndex
        )
        let controller = started(features: features)
        let state = controller.deviceState(id: "046D:B034", deviceName: "MX Master 3S", wheel: nil)
        XCTAssertEqual(state.supported, [.battery, .pointerSpeed])
        XCTAssertNil(state.haptics)
        XCTAssertNil(state.pressForce)
        XCTAssertFalse(sent.contains { $0.index == Self.hapticIndex || $0.index == Self.pressIndex })
    }
}
