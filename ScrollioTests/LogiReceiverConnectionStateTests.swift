import XCTest
@testable import Scrollio_Debug

final class LogiReceiverConnectionStateTests: XCTestCase {

    func testBLEIsAlwaysSendableForReceiverTargetChecks() {
        XCTAssertTrue(LogiDeviceSession.receiverTargetIsConnectedForTests(
            connectionMode: .bleDirect,
            deviceIndex: 0xFF,
            pairedDevices: []
        ))
    }

    func testKnownDisconnectedReceiverTargetIsNotSendable() {
        XCTAssertFalse(LogiDeviceSession.receiverTargetIsConnectedForTests(
            connectionMode: .receiver,
            deviceIndex: 0x03,
            pairedDevices: [
                .init(slot: 0x03, isConnected: false)
            ]
        ))
    }

    func testUnknownReceiverTargetDefaultsToSendable() {
        XCTAssertTrue(LogiDeviceSession.receiverTargetIsConnectedForTests(
            connectionMode: .receiver,
            deviceIndex: 0x03,
            pairedDevices: []
        ))
    }

    // MARK: - chooseReceiverTargetSlot (Phase 0 prefer-mouse 巡检游标)

    private func device(
        slot: UInt8,
        connected: Bool,
        type: UInt8
    ) -> LogiDeviceSession.ReceiverPairedDevice {
        var d = LogiDeviceSession.ReceiverPairedDevice(slot: slot)
        d.isConnected = connected
        d.deviceType = type
        return d
    }

    func testChooseTargetPrefersMouseOverLowerNumberedKeyboard() {
        // 键盘在更低号 slot, 鼠标在更高号 slot -> 选鼠标 (修复旧的锁最低号 bug)
        XCTAssertEqual(LogiDeviceSession.chooseReceiverTargetSlot(devices: [
            device(slot: 1, connected: true, type: 0x01),  // Keyboard
            device(slot: 3, connected: true, type: 0x02)   // Mouse
        ]), 3)
    }

    func testChooseTargetFallsBackToFirstConnectedWhenNoMouse() {
        XCTAssertEqual(LogiDeviceSession.chooseReceiverTargetSlot(devices: [
            device(slot: 2, connected: true, type: 0x01),  // Keyboard
            device(slot: 4, connected: true, type: 0x01)   // Keyboard
        ]), 2)
    }

    func testChooseTargetFallsBackToFirstConnectedWhenTypesUnknown() {
        // device-info 未到齐 (deviceType 全 0) 时回退首个在线 slot, 不退化
        XCTAssertEqual(LogiDeviceSession.chooseReceiverTargetSlot(devices: [
            device(slot: 2, connected: true, type: 0x00),
            device(slot: 4, connected: true, type: 0x00)
        ]), 2)
    }

    func testChooseTargetSkipsDisconnectedMouse() {
        // 鼠标已断开, 只有键盘在线 -> 回退在线键盘, 不选断开的鼠标
        XCTAssertEqual(LogiDeviceSession.chooseReceiverTargetSlot(devices: [
            device(slot: 1, connected: false, type: 0x02),  // Mouse (disconnected)
            device(slot: 3, connected: true, type: 0x01)    // Keyboard
        ]), 3)
    }

    func testChooseTargetPicksFirstConnectedMouse() {
        XCTAssertEqual(LogiDeviceSession.chooseReceiverTargetSlot(devices: [
            device(slot: 2, connected: true, type: 0x02),  // Mouse
            device(slot: 5, connected: true, type: 0x02)   // Mouse
        ]), 2)
    }

    func testChooseTargetReturnsNilWhenNothingConnected() {
        XCTAssertNil(LogiDeviceSession.chooseReceiverTargetSlot(devices: [
            device(slot: 1, connected: false, type: 0x02),
            device(slot: 2, connected: false, type: 0x01)
        ]))
        XCTAssertNil(LogiDeviceSession.chooseReceiverTargetSlot(devices: []))
    }

    // MARK: - receiverTakeoverSlots (Phase 2 接管集合; bindings play no part since 2026-11)

    private func device(
        slot: UInt8,
        connected: Bool,
        type: UInt8,
        pid: UInt16
    ) -> LogiDeviceSession.ReceiverPairedDevice {
        var d = LogiDeviceSession.ReceiverPairedDevice(slot: slot)
        d.isConnected = connected
        d.deviceType = type
        d.wirelessPID = pid
        return d
    }

    func testTakeoverSlotsIncludeEveryConnectedMouse() {
        let devices = [
            device(slot: 1, connected: true, type: 0x01, pid: 0xB350),  // Keyboard -> excluded
            device(slot: 2, connected: true, type: 0x02, pid: 0x4082),  // Mouse
            device(slot: 3, connected: false, type: 0x02, pid: 0x4082), // Mouse, disconnected -> excluded
            device(slot: 4, connected: true, type: 0x02, pid: 0x999),   // Mouse without a binding -> included
            device(slot: 5, connected: true, type: 0x02, pid: 0x4082)   // Mouse
        ]
        XCTAssertEqual(LogiDeviceSession.receiverTakeoverSlots(devices: devices), [2, 4, 5])
    }

    /// Regression (launch path): with no Logitech button binding at all the mice were left out,
    /// so a mouse that was not the inspection slot got no Mouse pane, battery or managed values.
    func testTakeoverSlotsDoNotNeedBindings() {
        let devices = [
            device(slot: 2, connected: true, type: 0x02, pid: 0x4082),
            device(slot: 3, connected: true, type: 0x02, pid: 0x4083)
        ]
        XCTAssertEqual(LogiDeviceSession.receiverTakeoverSlots(devices: devices), [2, 3])
    }

    func testDivertSlotsSortedAscending() {
        let devices = [
            device(slot: 5, connected: true, type: 0x02, pid: 0x4082),
            device(slot: 2, connected: true, type: 0x02, pid: 0x4082)
        ]
        XCTAssertEqual(
            LogiDeviceSession.receiverTakeoverSlots(devices: devices),
            [2, 5]
        )
    }

    func testDivertSlotsIncludesUnknownTypeSlots() {
        // 关键回归: 接收器不返回 deviceType (寄存器 0xB5 InvalidSubID) 时类型恒为 0(未知).
        // 未知类型的鼠标必须纳入接管, 否则永不 divert (真实 USB Receiver 上的现象).
        let devices = [
            device(slot: 1, connected: true, type: 0x00, pid: 0x0000),  // 未知(实为键盘, 但类型拿不到)
            device(slot: 4, connected: true, type: 0x00, pid: 0x0000)   // 未知(实为鼠标)
        ]
        XCTAssertEqual(
            LogiDeviceSession.receiverTakeoverSlots(devices: devices),
            [1, 4]
        )
    }

    func testDivertSlotsExcludesKnownKeyboardIncludesUnknownMouse() {
        // 类型部分已知: 键盘(0x01)排除, 未知/鼠标纳入.
        let devices = [
            device(slot: 1, connected: true, type: 0x01, pid: 0x0000),  // Keyboard -> excluded
            device(slot: 4, connected: true, type: 0x00, pid: 0x0000),  // Unknown -> included
            device(slot: 5, connected: true, type: 0x02, pid: 0x0000)   // Mouse -> included
        ]
        XCTAssertEqual(
            LogiDeviceSession.receiverTakeoverSlots(devices: devices),
            [4, 5]
        )
    }

    // MARK: - receiverReportRoute (Phase 2 报文分发)

    func testReportRouteProcessesCurrentSlot() {
        XCTAssertEqual(
            LogiDeviceSession.receiverReportRoute(incomingSlot: 2, currentSlot: 2, managedSlots: [2, 5]),
            .processCurrent
        )
    }

    func testReportRouteScopesToOtherManagedSlot() {
        XCTAssertEqual(
            LogiDeviceSession.receiverReportRoute(incomingSlot: 5, currentSlot: 2, managedSlots: [2, 5]),
            .processScoped(5)
        )
    }

    func testReportRouteDropsUnmanagedSlot() {
        XCTAssertEqual(
            LogiDeviceSession.receiverReportRoute(incomingSlot: 4, currentSlot: 2, managedSlots: [2, 5]),
            .drop
        )
    }

    func testReportRouteSingleDeviceDropsNonCurrent() {
        // 单设备: managedSlots = {current}, 其它 slot 一律 drop (与旧 stale 过滤等价)
        XCTAssertEqual(
            LogiDeviceSession.receiverReportRoute(incomingSlot: 3, currentSlot: 1, managedSlots: [1]),
            .drop
        )
    }

    // MARK: - hidppDeviceTypeName (feature 0x0005 getDeviceType 枚举映射)

    func testHidppDeviceTypeNameMapping() {
        func name(_ t: UInt8) -> String? {
            var d = LogiDeviceSession.ReceiverPairedDevice(slot: 1)
            d.hidppDeviceType = t
            return d.hidppDeviceTypeName
        }
        XCTAssertEqual(name(0x00), "Keyboard (0x00)")
        XCTAssertEqual(name(0x03), "Mouse (0x03)")
        XCTAssertEqual(name(0x05), "Trackball (0x05)")
        XCTAssertEqual(name(0x06), "Presenter (0x06)")
        XCTAssertEqual(name(0x99), "Unknown (0x99)")
    }

    func testHidppDeviceTypeNameNilWhenUnknown() {
        let d = LogiDeviceSession.ReceiverPairedDevice(slot: 1)
        XCTAssertNil(d.hidppDeviceTypeName)  // 未查询 -> nil
    }

    // MARK: - controlsLookLikeMouse (类型不可知接收器上据控件识别鼠标)

    func testControlsLookLikeMouseWithLeftAndRight() {
        // 鼠标: 有 Left(0x50) + Right(0x51) + 其它
        XCTAssertTrue(LogiDeviceSession.controlsLookLikeMouse(
            cids: [0x0050, 0x0051, 0x0052, 0x0053, 0x00C3]))
    }

    func testControlsLookLikeKeyboardWithoutLeftRight() {
        // 键盘: media/backlight 类 CID, 无标准 Left/Right
        XCTAssertFalse(LogiDeviceSession.controlsLookLikeMouse(
            cids: [0x00D1, 0x00D2, 0x00E2, 0x00E5, 0x0103]))
    }

    func testControlsLookLikeMouseNeedsBothButtons() {
        XCTAssertFalse(LogiDeviceSession.controlsLookLikeMouse(cids: [0x0050]))
        XCTAssertFalse(LogiDeviceSession.controlsLookLikeMouse(cids: [0x0051]))
        XCTAssertFalse(LogiDeviceSession.controlsLookLikeMouse(cids: []))
    }

    func testReportRouteDropsOutOfRangeSlot() {
        XCTAssertEqual(
            LogiDeviceSession.receiverReportRoute(incomingSlot: 0, currentSlot: 1, managedSlots: [1]),
            .drop
        )
        XCTAssertEqual(
            LogiDeviceSession.receiverReportRoute(incomingSlot: 7, currentSlot: 1, managedSlots: [1]),
            .drop
        )
    }

    // MARK: - receiverSlotConnectionAction (Phase 4 热插拔)

    func testSlotConnectionDisconnectedManagedReleases() {
        // 已接管的 slot 断开 -> 释放其接管状态
        XCTAssertEqual(
            LogiDeviceSession.receiverSlotConnectionAction(
                slot: 4, connected: false, isDivertCandidate: false, alreadyManaged: true),
            .release(4)
        )
    }

    func testSlotConnectionDisconnectedUnmanagedIgnored() {
        XCTAssertEqual(
            LogiDeviceSession.receiverSlotConnectionAction(
                slot: 4, connected: false, isDivertCandidate: false, alreadyManaged: false),
            .ignore
        )
    }

    func testSlotConnectionReconnectUnmanagedCandidateTakesOver() {
        // 关键: 鼠标关机/切 slot 再回来 -> 未接管 + 候选 -> 重新 discovery+divert
        XCTAssertEqual(
            LogiDeviceSession.receiverSlotConnectionAction(
                slot: 4, connected: true, isDivertCandidate: true, alreadyManaged: false),
            .takeover(4)
        )
    }

    func testSlotConnectionConnectedAlreadyManagedIgnored() {
        // 防振荡: 已接管且在线的 slot 再收到 connected 通知 -> 忽略, 不重复 discovery
        XCTAssertEqual(
            LogiDeviceSession.receiverSlotConnectionAction(
                slot: 4, connected: true, isDivertCandidate: true, alreadyManaged: true),
            .ignore
        )
    }

    func testSlotConnectionConnectedNonCandidateIgnored() {
        // 键盘等非候选设备连接 -> 不接管
        XCTAssertEqual(
            LogiDeviceSession.receiverSlotConnectionAction(
                slot: 1, connected: true, isDivertCandidate: false, alreadyManaged: false),
            .ignore
        )
    }

    func testSlotConnectionOutOfRangeIgnored() {
        XCTAssertEqual(
            LogiDeviceSession.receiverSlotConnectionAction(
                slot: 0, connected: true, isDivertCandidate: true, alreadyManaged: false),
            .ignore
        )
        XCTAssertEqual(
            LogiDeviceSession.receiverSlotConnectionAction(
                slot: 7, connected: false, isDivertCandidate: false, alreadyManaged: true),
            .ignore
        )
    }

    /// Regression (A): a (re)connected mouse-like slot is a takeover candidate whatever the
    /// bindings say; only known keyboards, numpads and presenters are left alone.
    func testReconnectedMouseIsTakenOverWithoutBindings() {
        XCTAssertTrue(LogiDeviceSession.receiverSlotIsTakeoverCandidate(connected: true, deviceType: 0x02))
        XCTAssertTrue(LogiDeviceSession.receiverSlotIsTakeoverCandidate(connected: true, deviceType: 0x00),
                      "receivers that do not report a type (Bolt) still take the mouse over")
        XCTAssertFalse(LogiDeviceSession.receiverSlotIsTakeoverCandidate(connected: true, deviceType: 0x01))
        XCTAssertFalse(LogiDeviceSession.receiverSlotIsTakeoverCandidate(connected: true, deviceType: 0x03))
        XCTAssertFalse(LogiDeviceSession.receiverSlotIsTakeoverCandidate(connected: true, deviceType: 0x04))
        XCTAssertFalse(LogiDeviceSession.receiverSlotIsTakeoverCandidate(connected: false, deviceType: 0x02))

        let candidate = LogiDeviceSession.receiverSlotIsTakeoverCandidate(connected: true, deviceType: 0x02)
        XCTAssertEqual(
            LogiDeviceSession.receiverSlotConnectionAction(
                slot: 2, connected: true, isDivertCandidate: candidate, alreadyManaged: false),
            .takeover(2)
        )
        XCTAssertEqual(
            LogiDeviceSession.receiverPeripheralActivityAction(
                slot: 2, wasConnected: false, isDivertCandidate: candidate, alreadyManaged: false),
            .takeover(2)
        )
    }

    /// The takeover no longer waits for a binding, so it must not divert anything by
    /// itself: with an empty aggregate applyUsage has nothing to divert and nothing native-first
    /// to undivert, on a receiver and over Bluetooth.
    func testEmptyAggregateDivertsNothing() {
        let divertable: Set<UInt16> = [0x0050, 0x0051, 0x0052, 0x0053, 0x0056, 0x00C3, 0x00C4, 0x00D7]
        for transport in [LogiTransportIdentity.receiver, .bleDirect] {
            let policy = LogiButtonDeliveryPolicy(standardMouseButtonsUseNativeEvents: true)
            XCTAssertEqual(LogiDeviceSession.targetCIDsForUsageForTests(
                aggregateScrollioCodes: [], divertableCIDs: divertable,
                transport: transport, phase: .normal, policy: policy,
                deliveryModeForCID: { _ in .hidpp }
            ), [])
            XCTAssertEqual(LogiDeviceSession.nativeFirstCIDsForUsageForTests(
                aggregateScrollioCodes: [], divertableCIDs: divertable,
                transport: transport, phase: .normal, policy: policy
            ), [])
        }
    }

    func testPeripheralActivityTakesOverPreviouslyOfflineSlotOnce() {
        XCTAssertEqual(
            LogiDeviceSession.receiverPeripheralActivityAction(
                slot: 1, wasConnected: false, isDivertCandidate: true, alreadyManaged: false),
            .takeover(1)
        )
        XCTAssertEqual(
            LogiDeviceSession.receiverPeripheralActivityAction(
                slot: 1, wasConnected: true, isDivertCandidate: true, alreadyManaged: false),
            .ignore
        )
    }

    // MARK: - Which Logitech interfaces are spoken to

    /// Only a receiver's vendor-specific interface gets HID++ traffic over USB. Every USB
    /// interface of Logitech with such a usage page used to be taken for a receiver and got
    /// six slot pings at every start: a headset, a webcam, a light, a wired keyboard or mouse.
    func testOnlyAReceiverIsSpokenToOverUSB() {
        // Bolt, Unifying, a Lightspeed receiver: known products.
        for pid: UInt16 in [0xC548, 0xC52B, 0xC547] {
            XCTAssertTrue(LogiDeviceSession.isHIDPPCandidate(isBLE: false, usagePage: 0xFF00, usage: 1, productId: pid))
        }
        // A receiver the list does not have yet: the 0xC5xx block is Logitech's receivers.
        XCTAssertTrue(LogiReceiverCatalog.isReceiver(pid: 0xC5FE))
        XCTAssertTrue(LogiDeviceSession.isHIDPPCandidate(isBLE: false, usagePage: 0xFF00, usage: 1, productId: 0xC5FE))
        // A wired gaming mouse, a wired keyboard, a webcam, a headset, a Litra light.
        for pid: UInt16 in [0xC08B, 0xC33F, 0x085E, 0x0A87, 0xC900] {
            XCTAssertFalse(LogiReceiverCatalog.isReceiver(pid: pid), String(format: "0x%04X", pid))
            for page in [0xFF00, 0xFF43, 0xFFC0] {
                XCTAssertFalse(
                    LogiDeviceSession.isHIDPPCandidate(isBLE: false, usagePage: page, usage: 1, productId: pid),
                    String(format: "0x%04X page 0x%04X", pid, page)
                )
            }
        }
        // A receiver's ordinary mouse and keyboard interfaces are not HID++.
        XCTAssertFalse(LogiDeviceSession.isHIDPPCandidate(isBLE: false, usagePage: 0x0001, usage: 0x0002, productId: 0xC548))
        // Bluetooth: the mouse interface, whatever the product.
        XCTAssertTrue(LogiDeviceSession.isHIDPPCandidate(isBLE: true, usagePage: 0x0001, usage: 0x0002, productId: 0xB034))
        XCTAssertFalse(LogiDeviceSession.isHIDPPCandidate(isBLE: true, usagePage: 0x000C, usage: 0x0001, productId: 0xB034))
    }

    // MARK: - Devices on a receiver that are not mice

    /// A slot whose discovery showed a keyboard is not a takeover candidate again when the
    /// keyboard wakes up and reconnects: it used to be discovered like a mouse each time.
    func testASlotKnownNotToBeAMouseIsNotTakenOverAgain() {
        XCTAssertTrue(LogiDeviceSession.receiverSlotIsTakeoverCandidate(connected: true, deviceType: 0x00))
        XCTAssertFalse(LogiDeviceSession.receiverSlotIsTakeoverCandidate(connected: true, deviceType: 0x00, knownNotAMouse: true))
        XCTAssertFalse(LogiDeviceSession.receiverSlotIsTakeoverCandidate(connected: true, deviceType: 0x02, knownNotAMouse: true))

        let candidate = LogiDeviceSession.receiverSlotIsTakeoverCandidate(connected: true, deviceType: 0x00, knownNotAMouse: true)
        XCTAssertEqual(
            LogiDeviceSession.receiverSlotConnectionAction(slot: 3, connected: true, isDivertCandidate: candidate, alreadyManaged: false),
            .ignore
        )
        XCTAssertEqual(
            LogiDeviceSession.receiverPeripheralActivityAction(slot: 3, wasConnected: false, isDivertCandidate: candidate, alreadyManaged: false),
            .ignore
        )
    }

    /// "Not a mouse" is remembered only when every control answered: a mouse whose left or
    /// right click got lost on the way is looked at again when it reconnects.
    func testNotAMouseIsRememberedOnlyFromACompleteListOfControls() {
        XCTAssertTrue(LogiDeviceSession.nonMouseSlotIsRemembered(controlsFound: 12, controlsReported: 12))
        XCTAssertFalse(LogiDeviceSession.nonMouseSlotIsRemembered(controlsFound: 7, controlsReported: 9))
        XCTAssertFalse(LogiDeviceSession.nonMouseSlotIsRemembered(controlsFound: 0, controlsReported: 0))
    }

    // MARK: - The saved feature table

    /// The saved feature indices of a Bluetooth mouse are used only when the mouse confirms
    /// the buttons feature and the saved feature with the highest index. A feature more or
    /// less in the mouse's table (another firmware) moves the last index at least.
    func testTheSavedFeatureTableIsCheckedWithTwoLookUps() {
        let saved: [UInt16: UInt8] = [0x0005: 0x03, 0x1004: 0x09, 0x1B04: 0x0A, 0x19B0: 0x0B, 0x2111: 0x11, 0x2201: 0x14]
        let probes = LogiDeviceSession.featureCacheProbes(saved)
        XCTAssertEqual(probes.map(\.featureId), [0x1B04, 0x2201])
        XCTAssertEqual(probes.map(\.index), [0x0A, 0x14])

        // After a firmware update put one feature in front of the buttons feature, the
        // mouse answers 0x0B for 0x1B04: not the saved 0x0A.
        XCTAssertNotEqual(probes[0].index, 0x0B)

        // Only the buttons feature saved: one look-up. Without it: nothing to check.
        XCTAssertEqual(LogiDeviceSession.featureCacheProbes([0x1B04: 0x0A]).map(\.featureId), [0x1B04])
        XCTAssertTrue(LogiDeviceSession.featureCacheProbes([0x2201: 0x14]).isEmpty)
        // The buttons feature is itself the last one.
        XCTAssertEqual(LogiDeviceSession.featureCacheProbes([0x0005: 0x03, 0x1B04: 0x0A]).map(\.featureId), [0x1B04])
    }

    // MARK: - GetControlCount without an answer

    /// GetControlCount is sent once more, then the discovery ends without buttons. It used
    /// to wait for the whole connection ("Checking buttons…" for ever; on a receiver no
    /// other slot was discovered).
    func testAControlCountWithoutAnswerIsAskedOnceMoreAndThenGivenUp() {
        XCTAssertEqual(LogiDeviceSession.controlCountFailureStep(attempt: 1), .sendAgain(attempt: 2))
        XCTAssertEqual(LogiDeviceSession.controlCountFailureStep(attempt: 2), .endDiscovery)
        XCTAssertEqual(LogiDeviceSession.controlCountAttempts, 2)
        XCTAssertGreaterThan(LogiDeviceSession.controlCountTimeout, 0.7, "the first write after an idle time took up to 0.7 s")
    }

    // MARK: - The device's own name (feature 0x0005)

    private func nameReport(function: UInt8, payload: [UInt8]) -> [UInt8] {
        var bytes: [UInt8] = [0x11, 0x02, 0x03, (function << 4) | 0x01] + payload
        while bytes.count < 20 { bytes.append(0) }
        return bytes
    }

    /// A mouse on a receiver was shown under the receiver's name ("USB Receiver"): the name
    /// is read from the mouse itself, the length first and then the characters in pieces.
    func testTheNameIsReadFromTheDeviceInPieces() {
        var read = LogiDeviceNameRead()
        let name = "MX Master 3S For Mac"   // 20 characters: two pieces of at most 16
        XCTAssertEqual(read.handleLength(nameReport(function: 0, payload: [UInt8(name.utf8.count)])), .requestPiece(from: 0))
        XCTAssertEqual(read.handlePiece(nameReport(function: 1, payload: Array(name.utf8.prefix(16)))), .requestPiece(from: 16))
        XCTAssertEqual(read.handlePiece(nameReport(function: 1, payload: Array(name.utf8.dropFirst(16)))), .finished(name))
    }

    func testAShortNameArrivesInOnePiece() {
        var read = LogiDeviceNameRead()
        XCTAssertEqual(read.handleLength(nameReport(function: 0, payload: [12])), .requestPiece(from: 0))
        XCTAssertEqual(read.handlePiece(nameReport(function: 1, payload: Array("MX Master 3S".utf8))), .finished("MX Master 3S"))
    }

    func testANameAnswerThatMakesNoSenseEndsTheRead() {
        var read = LogiDeviceNameRead()
        XCTAssertEqual(read.handleLength(nameReport(function: 0, payload: [0])), .failed, "no length")
        XCTAssertEqual(read.handleLength(nameReport(function: 0, payload: [200])), .failed, "longer than any name")
        XCTAssertEqual(read.handleLength([0x11, 0x02, 0x03]), .failed, "short report")
        XCTAssertEqual(read.handlePiece(nameReport(function: 1, payload: Array("MX".utf8))), .failed, "a piece nobody asked for")

        var empty = LogiDeviceNameRead()
        XCTAssertEqual(empty.handleLength(nameReport(function: 0, payload: [5])), .requestPiece(from: 0))
        XCTAssertEqual(empty.handlePiece(nameReport(function: 1, payload: [])), .failed, "an empty piece must not be asked for again for ever")

        var control = LogiDeviceNameRead()
        XCTAssertEqual(control.handleLength(nameReport(function: 0, payload: [3])), .requestPiece(from: 0))
        XCTAssertEqual(control.handlePiece(nameReport(function: 1, payload: [0x4D, 0x07, 0x58])), .failed, "no control characters")
    }

    /// Through a receiver the mouse is called by its own name; over Bluetooth by the name
    /// macOS has for it (what the user sees in the Bluetooth settings).
    func testWhatTheInterfaceCallsTheMouse() {
        XCTAssertEqual(LogiDeviceSession.displayName(connectionMode: .receiver, modelName: "MX Master 3S", interfaceName: "USB Receiver"), "MX Master 3S")
        XCTAssertEqual(LogiDeviceSession.displayName(connectionMode: .receiver, modelName: nil, interfaceName: "USB Receiver"), "USB Receiver")
        XCTAssertEqual(LogiDeviceSession.displayName(connectionMode: .bleDirect, modelName: "MX Anywhere 3S", interfaceName: "Anna's MX Anywhere"), "Anna's MX Anywhere")
    }

    /// The system log never carries the name macOS has for a Bluetooth mouse: the user can
    /// change that one, and a log pasted into a bug report would publish it.
    func testTheSystemLogNamesTheModelNotTheUsersNameForTheMouse() {
        XCTAssertEqual(
            LogiDeviceSession.logName(connectionMode: .bleDirect, modelName: "MX Anywhere 3S", interfaceName: "Anna's MX Anywhere", productId: 0xB037),
            "MX Anywhere 3S"
        )
        XCTAssertEqual(
            LogiDeviceSession.logName(connectionMode: .bleDirect, modelName: nil, interfaceName: "Anna's MX Anywhere", productId: 0xB037),
            "Logitech mouse B037", "until the mouse has said what it is"
        )
        XCTAssertEqual(
            LogiDeviceSession.logName(connectionMode: .receiver, modelName: nil, interfaceName: "USB Receiver", productId: 0xC548),
            "USB Receiver", "a receiver's name comes from its USB descriptor"
        )
        XCTAssertEqual(
            LogiDeviceSession.logName(connectionMode: .receiver, modelName: "MX Master 3S", interfaceName: "USB Receiver", productId: 0xC548),
            "MX Master 3S"
        )
    }

    // MARK: - The cursor after the diagnostics window

    /// Picking a keyboard's row in Logitech Diagnostics moved the receiver's cursor there
    /// and left it. When the window closes, the cursor goes back to a mouse.
    func testClosingTheDiagnosticsWindowPutsTheCursorBackOnAMouse() {
        XCTAssertEqual(LogiDeviceSession.cursorAfterInspection(cursor: 3, cursorIsMouse: false, mouseSlots: [2, 1], idle: true), 1)
        XCTAssertNil(LogiDeviceSession.cursorAfterInspection(cursor: 2, cursorIsMouse: true, mouseSlots: [1, 2], idle: true),
                     "on a mouse: stays where the user looked last")
        XCTAssertNil(LogiDeviceSession.cursorAfterInspection(cursor: 3, cursorIsMouse: false, mouseSlots: [], idle: true),
                     "no mouse on the receiver")
        XCTAssertNil(LogiDeviceSession.cursorAfterInspection(cursor: 3, cursorIsMouse: false, mouseSlots: [1], idle: false),
                     "a slot is discovered with the cursor on it")
    }

    // MARK: - A receiver's answers

    /// The slot of a pairing-information answer is a byte of the report: 0xFF + 1 used to
    /// trap, and any HID++ program that reads the register can make a receiver send it.
    func testASlotFromAReceiverReportIsCheckedBeforeItIsUsed() {
        XCTAssertEqual(LogiDeviceSession.pairingInfoSlot(entityIndex: 0), 1)
        XCTAssertEqual(LogiDeviceSession.pairingInfoSlot(entityIndex: 5), 6)
        XCTAssertNil(LogiDeviceSession.pairingInfoSlot(entityIndex: 6))
        XCTAssertNil(LogiDeviceSession.pairingInfoSlot(entityIndex: 0x20), "pairing information as Solaar asks for it")
        XCTAssertNil(LogiDeviceSession.pairingInfoSlot(entityIndex: 0xFF))
    }

    /// The name the receiver has for a mouse comes first; the name read from the mouse is
    /// what shows when the receiver gave none.
    func testTheReceiversNameForAMouseComesBeforeTheMousesOwn() {
        XCTAssertEqual(
            LogiDeviceSession.displayName(connectionMode: .receiver, pairingName: "MX Master 3", modelName: "MX Master 3S", interfaceName: "USB Receiver"),
            "MX Master 3"
        )
        XCTAssertEqual(
            LogiDeviceSession.displayName(connectionMode: .receiver, pairingName: "", modelName: "MX Master 3S", interfaceName: "USB Receiver"),
            "MX Master 3S"
        )
        XCTAssertEqual(
            LogiDeviceSession.displayName(connectionMode: .receiver, pairingName: nil, modelName: nil, interfaceName: "USB Receiver"),
            "USB Receiver"
        )
    }
}
