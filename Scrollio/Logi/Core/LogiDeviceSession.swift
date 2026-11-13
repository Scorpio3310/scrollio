//
//  LogiDeviceSession.swift
//  Mos
//  单个 Logitech 设备的 HID++ 2.0 通信会话
//  实现 Feature Discovery, Button Divert, 事件解析
//  Created by Mos on 2026/3/16.
//  Copyright © 2026 Caldis. All rights reserved.
//

import Cocoa
import IOKit
import IOKit.hid

struct LogiButtonStateDelta: Equatable {
    let pressed: Set<UInt16>
    let released: Set<UInt16>
}

struct LogiButtonStateTracker {
    private(set) var activeCIDs: Set<UInt16> = []

    mutating func update(activeCIDs newActiveCIDs: Set<UInt16>) -> LogiButtonStateDelta {
        let delta = LogiButtonStateDelta(
            pressed: newActiveCIDs.subtracting(activeCIDs),
            released: activeCIDs.subtracting(newActiveCIDs)
        )
        activeCIDs = newActiveCIDs
        return delta
    }

    mutating func releaseActiveCIDs(in cids: Set<UInt16>) -> Set<UInt16> {
        let released = activeCIDs.intersection(cids)
        activeCIDs.subtract(released)
        return released
    }

    mutating func releaseAll() -> Set<UInt16> {
        let released = activeCIDs
        activeCIDs.removeAll()
        return released
    }
}

/// One Logitech HID interface that speaks HID++: a mouse over Bluetooth, or a receiver with
/// up to six devices behind it (one slot each).
///
/// What this session writes to a mouse, and when. Everything else it sends is a read.
///
/// - **Buttons** (SetControlReporting, feature 0x1B04). A button is diverted for a binding
///   and while a button is being recorded, and every button Scrollio diverted is given back
///   when Scrollio pauses or quits. The writes come from a usage pass (`applyUsage`: the
///   bindings, or the recording set), from the gesture controller for the raw XY bit of a
///   button that is diverted anyway, and from `teardown`. `LogiDivertLedger` keeps what is
///   believed diverted, per slot. The left and the right button are never diverted. On a
///   receiver only a slot that is a mouse is written to (`slotIsMouse`).
/// - **Settings** (wheel mode, SmartShift sensitivity, wheel force, pointer speed, haptics,
///   press force). Only `LogiWheelController` and `LogiMouseBasicsController` write them,
///   and only when "Let Scrollio manage this mouse" is on, the user set that value, and the
///   value freshly read from the mouse differs.
/// - **Button actions** (`LogiButtonAction`: SmartShift toggle, pointer speed up and down,
///   Easy-Switch, next pointer speed). The user pressed a button for exactly that, so they
///   write whatever the switch says; each write is one line in the system log.
/// - **A haptic pulse** for a gesture cue or for the Shortcut Ring (a place lights, an
///   action runs; the ring asks for the same two cues, for a button that arrived over
///   HID++), and switching the haptics on for it after a fresh read of their state, unless
///   the user switched them off (`LogiGestureController`).
/// - **The diagnostics window** writes in Debug builds only (`diagnosticsMayWrite`).
///
/// One write goes to a receiver itself, not to a mouse: before its slots are pinged, the
/// bit that makes it report connections and disconnections is switched on if it is off
/// (`LogiReceiverConnectionReports`). It is left on at teardown.
class LogiDeviceSession {

    // MARK: - Public
    let hidDevice: IOHIDDevice
    let deviceInfo: InputDevice
    let usagePage: Int
    let usage: Int
    let transport: String

    // MARK: - Connection Mode
    /// 连接模式: 决定传输格式、device index 策略、divert flags
    enum ConnectionMode {
        /// BLE 直连: long report + ID in payload, devIdx=0xFF, divert flags=0x03
        case bleDirect
        /// USB Receiver (Unifying/Bolt): vendor-specific interface, devIdx=slot(0x01~0x06);
        /// slots are found by enumerateReceiverDevices (ping per slot + register 0xB5).
        case receiver
        /// 未知/不支持
        case unsupported
    }

    private(set) var connectionMode: ConnectionMode = .unsupported

    /// 多设备热插拔: 收到某 slot 的 0x41 该做什么.
    enum ReceiverSlotConnectionAction: Equatable {
        case ignore
        case takeover(UInt8)  // 起该 slot 一次 discovery+divert
        case release(UInt8)   // 释放该 slot 按键状态 + 标记未 init
    }

    /// 接收器模式下, 一个 peripheral(设备)报文应路由到哪个 slot 的状态.
    /// - processCurrent: report[1] 就是当前路由 slot(deviceIndex), 按现状处理
    /// - processScoped(slot): report[1] 是另一个已接管 slot, 临时把路由游标切到它再处理
    /// - drop: 未知 / 未接管 slot, 丢弃(旧 stale-peripheral 过滤语义)
    enum ReceiverReportRoute: Equatable {
        case processCurrent
        case processScoped(UInt8)
        case drop
    }

    // MARK: - HID++ State
    /// 当前路由游标: 出站 report[1] 与 per-slot 计算属性都用它.
    /// 稳态时 = 巡检游标(用户在看哪个 slot); discovery sweep 中 = 正在发现的 slot;
    /// 处理入站 peripheral 报文时临时 = report[1](见 handleInputReport 的 scoped 路由).
    private var deviceIndex: UInt8 = 0x01
    private var isBLE: Bool = false
    private var deviceOpened: Bool = false

    // MARK: - Receiver Multi-Device Takeover State
    /// 已完成 discovery+divert、常驻接管其按键的 slot 集. 入站 peripheral 报文按 report[1]
    /// 命中此集合时被 scoped 路由到对应 slot 处理, 而非旧的"非当前 target 一律 drop".
    private var receiverManagedSlots: Set<UInt8> = []
    /// 启动接管 sweep 的待发现队列(§3.1 串行: 一次只发现一个 slot).
    private var pendingDivertSlots: [UInt8] = []
    /// sweep 结束后路由游标停靠的巡检 slot(prefer-mouse 选定, 最后发现, 负责可选功能探测).
    private var receiverInspectionSlot: UInt8? = nil
    /// 接管 sweep 是否进行中. 区分"sweep 驱动的逐 slot 发现"与手动 rediscover: 前者完成后
    /// 推进队列, 后者按原逻辑(仅巡检 slot 探测可选功能). 也用于抑制 sweep 中的 0x41 抢占 retarget.
    private var receiverSweepActive: Bool = false
    /// 热插拔 takeover 去抖: 用户疯狂快切时, 0x41 连接不立即接管, 等该 slot 稳定在线
    /// receiverTakeoverDebounceDelay 后才 discovery+divert; 窗口内又断开就取消. 一次性(每事件重置),
    /// 非周期轮询, 不违红线(§2). 按 slot 各自去抖.
    private var receiverTakeoverDebounce: [UInt8: DispatchWorkItem] = [:]
    private static let receiverTakeoverDebounceDelay: TimeInterval = 0.4
    /// Slots the running takeover sweep rediscovered (their controllers were dropped). At the
    /// end of the sweep only these may have their wheel / haptic / basic features looked up
    /// and their controllers built again (receiverSweepRebuildSlot).
    private var receiverSweptSlots: Set<UInt8> = []
    /// 已探测过可选功能的 slot: 面板巡检切换时每 slot 只探一次, 避免每次切都重探(拖慢/撞在飞探测).
    /// slot 重新发现(sweep / setTargetSlot)时清除, 以便重探.
    private var receiverOptionalProbedSlots: Set<UInt8> = []
    /// Slots whose discovery showed a device that is not a mouse (a keyboard, a numpad: no
    /// left and right click among its controls). Nothing is written to such a slot, and it
    /// is not discovered again each time the device wakes up and reconnects. Kept until the
    /// session ends or the slot is targeted by hand in the diagnostics window.
    private var receiverNonMouseSlots: Set<UInt8> = []

    // MARK: - Receiver Enumeration State
    private(set) var receiverPairedDevices: [ReceiverPairedDevice] = []
    private var pendingSlotPings: Set<UInt8> = []
    private var receiverEnumPhase: Int = 0  // 0=idle, 1=pinging, 2=querying info
    /// How often each slot was pinged in this enumeration (a slot is pinged again when the
    /// receiver answers "busy").
    private var slotPingAttempts: [UInt8: Int] = [:]
    static let slotPingAttemptLimit = 4
    static let slotPingRetryDelay: TimeInterval = 0.25
    private var slotPingTimeout: DispatchWorkItem?
    static let slotPingPhaseTimeout: TimeInterval = 5.0

    /// The exchange that switches the receiver's connection reports on, before the slots
    /// are pinged (LogiReceiverConnectionReports). The slot pings wait for it, at most
    /// `connectionReportsWait`.
    private var connectionReports = LogiReceiverConnectionReports()
    private var connectionReportsGate: DispatchWorkItem?
    static let connectionReportsWait: TimeInterval = 1.0
    /// 启动枚举后, 巡检游标默认选择推迟到 device-info 到齐/超时再做一次 (prefer-mouse, 不锁最低号).
    private var pendingInitialTargetSelection: Bool = false
    private var pendingDeviceInfoSlots: Set<UInt8> = []
    private static let initialTargetSelectionTimeout: TimeInterval = 1.5

    // MARK: - Report Buffer
    private var reportBufferPtr: UnsafeMutablePointer<UInt8>?
    private static let reportBufferSize = 64

    // MARK: - Async Discovery
    /// getFeature requests waiting for their answer, oldest first (answers come in request
    /// order and carry no feature id). Each has its own timeout in `discoveryTimers`.
    private var pendingDiscovery = LogiFeatureDiscoveryQueue(softwareId: LogiDeviceSession.hidppSoftwareId)
    private var discoveryTimers: [Int: Timer] = [:]
    private static let discoveryTimeout: TimeInterval = 5.0
    /// GetControlCount sent and not answered yet: the slot it went to and how often it was
    /// sent. It has a timeout of its own (`controlCountTimer`).
    private var pendingControlCount: (slot: UInt8, attempt: Int)?
    private var controlCountTimer: Timer?
    /// How long the mouse has to answer GetControlCount. It is the first request after the
    /// feature look-up, and the first write after an idle time took up to 0.7 s over Bluetooth.
    static let controlCountTimeout: TimeInterval = 2.0
    /// GetControlCount is sent this often before the discovery ends without buttons.
    static let controlCountAttempts = 2

    // MARK: - Query Timeouts (防止 Bolt receiver 上 HID++ 响应丢包 / 错误导致 query 链路卡死)
    private var controlInfoQueryTimer: Timer?
    private var reportingQueryTimer: Timer?
    private static let reprogQueryTimeout: TimeInterval = 1.0
    private static let bleControlInfoRetryLimit = 1

    // MARK: - Per-Slot State (按 slot 拆分, 支持接收器多设备并行接管)
    // 接收器一个 HID++ 接口转发 6 个 slot 的设备 (report[1]=deviceIndex 区分). 每个 slot
    // 是一台独立设备, feature/divert/reprog 发现进度各自独立. deviceIndex 作为"当前巡检游标",
    // 下列计算属性透明路由到该游标 slot 的状态; BLE 直连用 0xFF slot, 单目标语义与拆分前一致.
    struct PerSlotState {
        var featureIndex: [UInt16: UInt8] = [:]
        /// What Scrollio believes is diverted on this slot, and the echoes it waits for
        /// (`divertedCIDs`, `lastApplied` and the pending acknowledgements route here).
        var ledger = LogiDivertLedger()
        var discoveredControls: [ControlInfo] = []
        var reprogInitComplete: Bool = false  // init 完成后, function 0 = button event 而非 GetControlCount
        var reprogControlCount: Int = 0
        var reprogQueryIndex: Int = 0
        var reportingQueryIndex: Int = 0      // GetControlReporting 逐按键查询进度
        var controlInfoRetryCounts: [Int: Int] = [:]
        // 按键按下/抬起状态跟踪: 必须按 slot 独立, 否则同型号两只鼠标 (CID 相同) 的
        // 交错报文会互相污染 press/release delta.
        var buttonStateTracker = LogiButtonStateTracker()
    }

    private var slotStates: [UInt8: PerSlotState] = [:]

    private var buttonStateTracker: LogiButtonStateTracker {
        get { slotStates[deviceIndex]?.buttonStateTracker ?? LogiButtonStateTracker() }
        set { slotStates[deviceIndex, default: PerSlotState()].buttonStateTracker = newValue }
    }

    private var featureIndex: [UInt16: UInt8] {
        get { slotStates[deviceIndex]?.featureIndex ?? [:] }
        set { slotStates[deviceIndex, default: PerSlotState()].featureIndex = newValue }
    }
    private var divertedCIDs: Set<UInt16> {
        get { slotStates[deviceIndex]?.ledger.diverted ?? [] }
        set { slotStates[deviceIndex, default: PerSlotState()].ledger.diverted = newValue }
    }
    /// The divert bookkeeping of the cursor slot (see LogiDivertLedger).
    private var divertLedger: LogiDivertLedger {
        get { slotStates[deviceIndex]?.ledger ?? LogiDivertLedger() }
        set { slotStates[deviceIndex, default: PerSlotState()].ledger = newValue }
    }
    private var discoveredControls: [ControlInfo] {
        get { slotStates[deviceIndex]?.discoveredControls ?? [] }
        set { slotStates[deviceIndex, default: PerSlotState()].discoveredControls = newValue }
    }
    private var reprogInitComplete: Bool {
        get { slotStates[deviceIndex]?.reprogInitComplete ?? false }
        set { slotStates[deviceIndex, default: PerSlotState()].reprogInitComplete = newValue }
    }
    private var reprogControlCount: Int {
        get { slotStates[deviceIndex]?.reprogControlCount ?? 0 }
        set { slotStates[deviceIndex, default: PerSlotState()].reprogControlCount = newValue }
    }
    private var reprogQueryIndex: Int {
        get { slotStates[deviceIndex]?.reprogQueryIndex ?? 0 }
        set { slotStates[deviceIndex, default: PerSlotState()].reprogQueryIndex = newValue }
    }
    private var reportingQueryIndex: Int {
        get { slotStates[deviceIndex]?.reportingQueryIndex ?? 0 }
        set { slotStates[deviceIndex, default: PerSlotState()].reportingQueryIndex = newValue }
    }
    private var controlInfoRetryCounts: [Int: Int] {
        get { slotStates[deviceIndex]?.controlInfoRetryCounts ?? [:] }
        set { slotStates[deviceIndex, default: PerSlotState()].controlInfoRetryCounts = newValue }
    }

    /// 握手终态: receiver 枚举完成 / direct 设备 discovery 走到终点(成功或失败).
    /// sidebar 圆点据此判定 Ready vs Initializing; 与 reprogInitComplete 不同 —— 后者不覆盖
    /// "REPROG 不可用"/"GetControlCount=0" 等 discovery 失败分支.
    private var handshakeComplete: Bool = false

    /// 当前是否正在进行 discovery 握手 (setTargetSlot/rediscoverFeatures 触发, 完成/失败后清零).
    /// UI 据此显示 spinner; 和 handshakeComplete 不同 —— 前者表达"飞行中", 后者表达"终态达成".
    private var discoveryInFlight: Bool = false

    struct ControlInfo {
        let cid: UInt16
        let taskId: UInt16
        let flags: UInt16
        let isDivertable: Bool
        // GetControlReporting 查询结果
        // As GetControlReporting answers (Solaar MAPPING_FLAG): bit0 diverted (until the
        // mouse is switched off), bit2 persistently diverted, bit4 raw XY diverted, bit6 raw
        // XY forced. Bits 1, 3 and 5 are the "valid" bits of a set request and read as 0.
        var reportingFlags: UInt8 = 0
        var targetCID: UInt16 = 0       // remap 目标 CID (0 = 自映射)
        var reportingQueried: Bool = false
    }

    struct QueriedControlState {
        let cid: UInt16
        let reportingFlags: UInt8
        let reportingQueried: Bool
    }

    enum ReprogInitFunction0Route: Equatable {
        case divertedButtonEvent
        case getControlCountResponse
        case ignored
    }

    // MARK: - Receiver Paired Device Info
    struct ReceiverPairedDevice {
        let slot: UInt8              // 1-6
        var isConnected: Bool = false
        var protocolMajor: UInt8 = 0
        var protocolMinor: UInt8 = 0
        var wirelessPID: UInt16 = 0
        var deviceType: UInt8 = 0              // register 0xB5 枚举 (部分接收器不返回)
        var hidppDeviceType: UInt8? = nil      // feature 0x0005 getDeviceType 枚举 (权威, 与上面不同)
        var name: String = ""
        var lastError: String? = nil

        var deviceTypeName: String {
            switch deviceType {
            case 0x01: return "Keyboard"
            case 0x02: return "Mouse"
            case 0x03: return "Numpad"
            case 0x04: return "Presenter"
            case 0x08: return "Trackball"
            case 0x09: return "Touchpad"
            default: return deviceType == 0 ? "--" : "0x\(String(format: "%02X", deviceType))"
            }
        }

        /// feature 0x0005 getDeviceType 的类型名 (权威). 原始字节一并显示便于核对枚举映射.
        var hidppDeviceTypeName: String? {
            guard let t = hidppDeviceType else { return nil }
            let name: String
            switch t {
            case 0x00: name = "Keyboard"
            case 0x01: name = "Remote Control"
            case 0x02: name = "Numpad"
            case 0x03: name = "Mouse"
            case 0x04: name = "Touchpad"
            case 0x05: name = "Trackball"
            case 0x06: name = "Presenter"
            case 0x07: name = "Receiver"
            case 0x08: name = "Headset"
            case 0x09: name = "Webcam"
            case 0x0A: name = "Steering Wheel"
            case 0x0B: name = "Joystick"
            case 0x0C: name = "Gamepad"
            case 0x0D: name = "Dock"
            case 0x0E: name = "Speaker"
            case 0x0F: name = "Microphone"
            case 0x10: name = "Illumination Light"
            case 0x11: name = "Programmable Controller"
            case 0x12: name = "Car Sim Pedals"
            case 0x13: name = "Adapter"
            default: name = "Unknown"
            }
            return String(format: "%@ (0x%02X)", name, t)
        }
    }

    // MARK: - Feature Index Cache (按 PID 缓存, 减少重连 discovery 延迟)
    private static let featureCacheKey = "logitechFeatureCache"

    #if DEBUG
    internal static var featureCacheKeyForTests: String { return featureCacheKey }

    internal static func loadCachedFeatureIndexForTests(for productId: UInt16, defaults: UserDefaults) -> [UInt16: UInt8]? {
        return loadCachedFeatureIndex(for: productId, defaults: defaults)
    }

    internal static func saveCachedFeatureIndexForTests(for productId: UInt16, featureMap: [UInt16: UInt8], defaults: UserDefaults) {
        saveCachedFeatureIndex(for: productId, featureMap: featureMap, defaults: defaults)
    }

    internal static func removeCachedFeatureIndexForTests(for productId: UInt16, defaults: UserDefaults) {
        removeCachedFeatureIndex(for: productId, defaults: defaults)
    }
    #endif

    private static func loadCachedFeatureIndex(for productId: UInt16, defaults: UserDefaults = .standard) -> [UInt16: UInt8]? {
        guard let data = defaults.data(forKey: featureCacheKey),
              let cache = try? JSONDecoder().decode([UInt16: [UInt16: UInt8]].self, from: data) else { return nil }
        return cache[productId]
    }

    private static func saveCachedFeatureIndex(for productId: UInt16, featureMap: [UInt16: UInt8], defaults: UserDefaults = .standard) {
        var cache: [UInt16: [UInt16: UInt8]] = [:]
        if let data = defaults.data(forKey: featureCacheKey),
           let existing = try? JSONDecoder().decode([UInt16: [UInt16: UInt8]].self, from: data) {
            cache = existing
        }
        cache[productId] = featureMap
        if let data = try? JSONEncoder().encode(cache) {
            defaults.set(data, forKey: featureCacheKey)
        }
    }

    /// Drops one product's entry; the other products and the stored format stay as they are.
    private static func removeCachedFeatureIndex(for productId: UInt16, defaults: UserDefaults = .standard) {
        guard let data = defaults.data(forKey: featureCacheKey),
              var cache = try? JSONDecoder().decode([UInt16: [UInt16: UInt8]].self, from: data),
              cache.removeValue(forKey: productId) != nil,
              let encoded = try? JSONEncoder().encode(cache) else { return }
        defaults.set(encoded, forKey: featureCacheKey)
    }

    /// HID++ 2.0 errors that say the request went to the wrong place: 0x06 invalid feature
    /// index, 0x07 invalid function id.
    private static let invalidFeatureIndexError: UInt8 = 0x06
    private static let invalidFunctionError: UInt8 = 0x07

    /// Whether an error means the cached feature indices are wrong (the firmware changed
    /// them): 0x06 or 0x07 on an index that came from the cache on this connection, for a
    /// request of this app. `originalFunctionByte` is byte 4 of the error (function << 4 |
    /// software id): an error for another HID++ client's request (Logi Options+) says
    /// nothing about this app's indices.
    static func errorInvalidatesFeatureCache(
        errorCode: UInt8,
        originalFeatureIndex: UInt8,
        originalFunctionByte: UInt8,
        cachedIndices: Set<UInt8>
    ) -> Bool {
        guard errorCode == invalidFeatureIndexError || errorCode == invalidFunctionError else { return false }
        guard originalFunctionByte & 0x0F == hidppSoftwareId else { return false }
        return originalFeatureIndex != 0x00 && cachedIndices.contains(originalFeatureIndex)
    }

    /// The feature indices this connection took from the cache (BLE direct only). An error
    /// that invalidates them drops the product's cache entry (errorInvalidatesFeatureCache).
    private var featureIndicesFromCache: Set<UInt8> = []
    /// The cache entry was dropped on this connection: the indices in hand may be wrong, so
    /// nothing is saved until a fresh discovery (the next connect, or Re-discover).
    private var featureCacheDropped = false
    /// A getFeature went unanswered on this connection. If its answer comes late it is taken
    /// for the next request's (an answer names no feature), so every index found after it
    /// may be off by one request: nothing is saved until a fresh discovery.
    private var featureDiscoveryTimedOut = false

    /// Saves the feature indices of the current slot under the product id (as before), unless
    /// the cache entry was dropped or a getFeature timed out on this connection.
    private func saveFeatureIndexCache() {
        guard !featureCacheDropped, !featureDiscoveryTimedOut else { return }
        Self.saveCachedFeatureIndex(for: deviceInfo.productId, featureMap: featureIndex)
    }

    private func dropFeatureIndexCache(errorCode: UInt8, featureIndex index: UInt8) {
        featureIndicesFromCache.removeAll()
        featureCacheDropped = true
        Self.removeCachedFeatureIndex(for: deviceInfo.productId)
        let message = String(format: "Feature index cache dropped: error 0x%02X on cached index 0x%02X; the next connect looks the features up again", errorCode, index)
        LogiDebugPanel.log("[\(deviceInfo.name)] \(message)")
        LogiSystemLog.note("\(sessionLogTag) \(message)")
    }

    // MARK: - HID++ Constants
    private static let featureReprogV4: UInt16 = 0x1B04
    private static let featureHiResWheel: UInt16 = 0x2121
    private static let featurePointerSpeed: UInt16 = 0x2205
    /// Haptic feedback (MX Master 4 等). internal: Debug 面板需要引用同一常量.
    static let featureHaptic: UInt16 = 0x19B0
    /// SmartShift v2 / enhanced: 提供可调 ratchet torque (即 Logi Options+ 的 Scroll force 齿感力度).
    /// internal: Debug 面板需要引用同一常量.
    static let featureSmartShiftEnhanced: UInt16 = 0x2111
    /// SmartShift v1 (MX Master 3S 等): 模式 + autoDisengage 阈值, 无 torque. 0x2111 存在时优先 0x2111.
    static let featureSmartShift: UInt16 = 0x2110
    /// Force Sensing Button (MX Master 4 压感按钮): 调节按压激活阈值. internal: Debug 面板需引用.
    static let featureForceSensing: UInt16 = 0x19C0
    /// DeviceNameType (0x0005): fn2 getDeviceType 返回权威设备类型枚举. 用于接收器 slot 显示类型
    /// (register 0xB5 在部分接收器失败时的替代). 注: 0x0005 的类型枚举与 register 0xB5 不同.
    static let featureDeviceNameType: UInt16 = 0x0005
    /// Battery: Unified Battery (MX Master 4 / 3S / 3 for Business), Battery Status (original
    /// MX Master 3), Adjustable DPI (pointer speed). See Scrollio/Logi/Basics.
    static let featureUnifiedBattery: UInt16 = LogiBatteryFeature.unifiedFeatureId
    static let featureBatteryStatus: UInt16 = LogiBatteryFeature.legacyFeatureId
    static let featureAdjustableDPI: UInt16 = LogiPointerSpeedProtocol.featureId
    private static let hidppShortReportId: UInt8 = 0x10
    private static let hidppLongReportId: UInt8 = 0x11
    private static let hidppErrorFeatureIdx: UInt8 = 0xFF
    /// Mos 请求报文低 4 位的 software id. 设备响应原样回带; 设备主动事件为 0.
    static let hidppSoftwareId: UInt8 = 0x01

    // HID++ 1.0 sub-IDs (receiver register access)
    private static let hidpp10SetRegister: UInt8 = 0x80
    private static let hidpp10GetRegister: UInt8 = 0x81
    private static let hidpp10GetLongRegister: UInt8 = 0x83
    private static let hidpp10ErrorMsg: UInt8 = 0x8F
    private static let hidpp10DeviceDisconnection: UInt8 = 0x40
    private static let hidpp10DeviceConnection: UInt8 = 0x41

    // HID++ 1.0 error codes (Logitech's HID++ 1.0 specification for receivers, 2.11)
    static let hidpp10ErrorBusy: UInt8 = 0x07

    /// Byte 3 of the slot ping: function 1 (ping) with the software id 0x0A. An error that
    /// answers the ping names it with this byte.
    static let slotPingFunctionByte: UInt8 = 0x1A

    // Receiver registers
    /// HID++ reporting flags (see LogiReceiverConnectionReports).
    private static let receiverReportingFlags: UInt8 = 0x00
    private static let receiverPairingInfo: UInt8 = 0xB5
    private static let pairingInfoDeviceInfo: UInt8 = 0x20
    private static let pairingInfoDeviceName: UInt8 = 0x40

    // Receiver device types (register 0xB5 report[10])
    static let receiverDeviceTypeMouse: UInt8 = 0x02

    private struct ReportingResponse {
        let cid: UInt16
        let reportingFlags: UInt8
        let targetCID: UInt16
    }

    private struct SetControlReportingAck {
        let cid: UInt16
        let flagsByte: UInt8
        let targetCID: UInt16

        var updatesTemporaryDivert: Bool { (flagsByte & 0x02) != 0 }
        var temporaryDivertEnabled: Bool { (flagsByte & 0x01) != 0 }
    }

    private struct PendingControlReportingQuery {
        let sentAt: Date
        let expiresAt: Date
    }

    private static let controlReportingQueryTTL: TimeInterval = 2.0
    private static let divertReassertionDelay: TimeInterval = 0.05

    // MARK: - Init

    init(hidDevice: IOHIDDevice) {
        self.hidDevice = hidDevice
        self.usagePage = IOHIDDeviceGetProperty(hidDevice, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
        self.usage = IOHIDDeviceGetProperty(hidDevice, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
        self.transport = IOHIDDeviceGetProperty(hidDevice, kIOHIDTransportKey as CFString) as? String ?? ""
        self.deviceInfo = InputDevice(
            vendorId: UInt16(IOHIDDeviceGetProperty(hidDevice, kIOHIDVendorIDKey as CFString) as? Int ?? 0),
            productId: UInt16(IOHIDDeviceGetProperty(hidDevice, kIOHIDProductIDKey as CFString) as? Int ?? 0),
            name: IOHIDDeviceGetProperty(hidDevice, kIOHIDProductKey as CFString) as? String ?? "Unknown"
        )
    }

    deinit {
        removeInputReportCallback()
        let device = hidDevice
        let opened = deviceOpened
        let buffer = reportBufferPtr
        if tornDownWithDeviceGone {
            // The device was removed: a write still on its way to it can block for seconds,
            // and the main thread (which serves the event taps) must not wait for it. The
            // device is closed and the buffer freed once the write queue has run empty; the
            // queue lives on until then.
            reportWriter.afterQueued {
                if opened { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }
                buffer?.deallocate()
            }
            return
        }
        // No write may still be on its way when the device is closed (the write queue holds
        // the device, not the session).
        reportWriter.drain(timeout: Self.writeDrainTimeoutAtRelease)
        if opened { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }
        buffer?.deallocate()
    }

    /// Set by `teardown(deviceGone: true)`: `deinit` then does not wait for the write queue.
    private var tornDownWithDeviceGone = false

    /// 是否为 HID++ 候选接口
    var isHIDPPCandidate: Bool {
        return Self.isHIDPPCandidate(isBLE: isBLE, usagePage: usagePage, usage: usage, productId: deviceInfo.productId)
    }

    /// Whether Scrollio talks HID++ to an interface (anything else of Logitech's is left
    /// alone: no session traffic, no report callback).
    /// - Bluetooth: the mouse interface (HID++ shares it).
    /// - USB: a vendor-specific interface of a receiver. Only of a receiver: every USB
    ///   interface of Logitech with such a usage page used to be taken for one and got six
    ///   slot pings at every start (a headset, a webcam, a light, a wired keyboard or mouse).
    static func isHIDPPCandidate(isBLE: Bool, usagePage: Int, usage: Int, productId: UInt16) -> Bool {
        if isBLE {
            return usagePage == 0x0001 && usage == 0x0002
        }
        let vendorPage = usagePage == 0xFF00 || usagePage == 0xFF43 || usagePage == 0xFFC0
        return vendorPage && LogiReceiverCatalog.isReceiver(pid: productId)
    }

    /// CID set last passed to setControlReporting. Diffed against next applyUsage's
    /// projection so we only emit setControlReporting for state changes.
    /// 按 slot 拆分 (存 PerSlotState), 计算属性路由到当前巡检游标 slot.
    internal var lastApplied: Set<UInt16> {
        get { slotStates[deviceIndex]?.ledger.lastApplied ?? [] }
        set { slotStates[deviceIndex, default: PerSlotState()].ledger.lastApplied = newValue }
    }
    private var divertReassertionWorkItem: DispatchWorkItem?
    private let bleStandardButtonUndivertPlanner = LogiBLEStandardButtonUndivertPlanner()
    private var bleStandardUndivertGuardWorkItem: DispatchWorkItem?
    private var bleStandardUndivertGuardGeneration = 0
    private var bleStandardUndivertGuardTargets: Set<UInt16> = []
    private var pendingBLEUndivertGuardQueries: [UInt16: PendingControlReportingQuery] = [:]
    /// The reporting query that runs follows a discovery (a connection, or features found
    /// again), not a refresh for the UI. Only after a discovery are leftover diverts looked for.
    private var reportingQueryFollowsDiscovery = false
    /// Set by `divertBoundControls` around the prime that follows a discovery, to the slot
    /// that was discovered: the pass for that slot also gives back leftover diverts
    /// (`staleDivertDecision`).
    private var staleDivertCheckSlot: UInt8?

    struct RecordingDivertPlan: Equatable {
        let desired: Set<UInt16>
        let toDivert: Set<UInt16>
        let toUndivert: Set<UInt16>
        /// 录制开始时重发 divert=ON 的 CID = desired 全集. lastApplied 只是 Mos 的记账: 设备
        /// 可能已静默丢掉 divert (固件休眠唤醒 / Logi Options+ 清 BLE divert), 只发 toDivert
        /// 会跳过这些键 (MX Master 4 模式切换键 0x00C4 录不到). SetControlReporting 幂等, 重发安全.
        var toAssert: Set<UInt16> { desired }
    }

    private func primeFromRegistry() {
        LogiCenter.shared.registry.primeSession(self)
    }

    /// The slots whose buttons Scrollio handles: over Bluetooth the mouse itself; on a
    /// receiver every mouse it took over, and the slot the cursor is on (the slot whose
    /// discovery just ended is not in `receiverManagedSlots` yet). A pass over a slot that is
    /// not ready, not connected or not a mouse does nothing (the guards of the pass).
    private var usageSlots: [UInt8] {
        return Self.usageSlots(connectionMode: connectionMode, cursor: deviceIndex, managedSlots: receiverManagedSlots)
    }

    static func usageSlots(connectionMode: ConnectionMode, cursor: UInt8, managedSlots: Set<UInt8>) -> [UInt8] {
        guard connectionMode == .receiver else { return [cursor] }
        return managedSlots.union([cursor]).sorted()
    }

    /// Runs `body` once per slot with the cursor on it, and puts the cursor back. Everything
    /// that reads or writes per-slot state (the computed properties, `sendRequest`) follows
    /// the cursor, so this is how one call reaches every mouse of a receiver.
    private func forEachSlot(_ slots: [UInt8], _ body: () -> Void) {
        let saved = deviceIndex
        defer { deviceIndex = saved }
        for slot in slots {
            deviceIndex = slot
            body()
        }
    }

    /// One usage pass over every mouse of this session (see `usageSlots`): the buttons with
    /// a binding are diverted and the others Scrollio diverted are given back, or, while a
    /// button is being recorded, every button that can be diverted stays diverted.
    internal func applyUsage(_ aggregateScrollioCodes: Set<UInt16>) {
        #if DEBUG
        precondition(Thread.isMainThread, "applyUsage main-thread-only")
        #endif
        forEachSlot(usageSlots) {
            applyUsageToCursorSlot(aggregateScrollioCodes)
        }
    }

    private func applyUsageToCursorSlot(_ aggregateScrollioCodes: Set<UInt16>) {
        #if DEBUG
        LogiTrace.log(
            "[Session] applyUsage enter device=\(deviceInfo.name) mode=\(connectionMode) connected=\(currentReceiverTargetIsConnected) reprogInit=\(reprogInitComplete) aggregate=\(LogiTrace.codes(aggregateScrollioCodes)) lastApplied=\(LogiTrace.cids(lastApplied)) diverted=\(LogiTrace.cids(divertedCIDs))",
            device: deviceInfo.name
        )
        #endif
        // Mid-discovery guard: isHIDPPCandidate is a static vendor/product check and is true
        // throughout discovery. If a setUsage fires before divertBoundControls runs, applyUsage
        // would diff against partial discoveredControls. The post-discovery prime catches up.
        guard reprogInitComplete else {
            #if DEBUG
            LogiTrace.log("[Session] applyUsage skipped: reprogInitComplete=false", device: deviceInfo.name)
            #endif
            return
        }
        guard let reprogIdx = featureIndex[Self.featureReprogV4] else {
            #if DEBUG
            LogiTrace.log("[Session] applyUsage skipped: REPROG feature missing", device: deviceInfo.name)
            #endif
            return
        }
        guard currentReceiverTargetIsConnected else {
            #if DEBUG
            LogiTrace.log("[Session] applyUsage skipped: receiver target disconnected", device: deviceInfo.name)
            #endif
            return
        }
        // Buttons are diverted on mice only. (The cursor can rest on a keyboard of the
        // receiver after its row was picked in the diagnostics window.)
        guard slotIsMouse(deviceIndex) else {
            #if DEBUG
            LogiTrace.log("[Session] applyUsage skipped: the slot is not a mouse", device: deviceInfo.name)
            #endif
            return
        }
        // While a button is being recorded every pass keeps the recording set, whoever
        // asked for it: the end of a re-read of the buttons' state (divertBoundControls),
        // the registry after a change, a reassertion. A pass for the bindings here used to
        // give the unbound buttons back while the recorder still waited for a press.
        if LogiDivertLedger.pass(whileRecording: LogiCenter.shared.isRecording) == .everyControl {
            temporarilyDivertAllOnCursorSlot()
            return
        }
        // Project ScrollioCodes -> CIDs, drop unmapped, intersect with divertable CIDs.
        let divertable = Set(discoveredControls.filter { $0.isDivertable }.map { $0.cid })
        let policy = LogiButtonDeliveryPolicy.default
        let transport = LogiTransportIdentity(connectionMode)
        // Gesture Navigation: which of the diverted controls the mouse should track itself.
        // The controller folds raw XY into the reporting flags of the writes below.
        let gesture = gestureController(slot: deviceIndex)
        gesture.setRawXYCapableControls(Self.rawXYCapableCIDs(in: discoveredControls))
        gesture.setRawXYRequest(Self.rawXYRequestCIDs(forScrollioCodes: LogiSessionManager.shared.gestureTrackingCodes))
        #if DEBUG
        let projection = aggregateScrollioCodes.sorted().map { code -> String in
            let cid = LogiCIDDirectory.toCID(code) ?? LogiCIDDirectory.cid(forNativeMouseButton: code)
            let cidLabel = cid.map { String(format: "0x%04X", $0) } ?? "nil"
            let mode = cid.map { LogiSessionManager.shared.deliveryMode(for: self.ownershipKey(forCID: $0)).debugLabel } ?? "none"
            let route = cid.map { policy.shouldUseHIDPPDelivery(transport: transport, cid: $0, phase: .normal) ? "hidpp" : "native" } ?? "none"
            let isDivertable = cid.map { divertable.contains($0) } ?? false
            return "\(code)->\(cidLabel) divertable=\(isDivertable) deliveryMode=\(mode) route=\(route)"
        }.joined(separator: " | ")
        LogiTrace.log("[Session] applyUsage projection \(projection)", device: deviceInfo.name)
        #endif
        let targetCIDs = Self.targetCIDsForUsage(
            aggregateScrollioCodes: aggregateScrollioCodes,
            divertableCIDs: divertable,
            transport: transport,
            phase: .normal,
            policy: policy
        ) { cid in
            LogiSessionManager.shared.deliveryMode(for: self.ownershipKey(forCID: cid))
        }
        let nativeFirstCIDs = Self.nativeFirstCIDsForUsage(
            aggregateScrollioCodes: aggregateScrollioCodes,
            divertableCIDs: divertable,
            transport: transport,
            phase: .normal,
            policy: policy
        )
        let toDivert = targetCIDs.subtracting(self.lastApplied)
        var toUndivert = self.lastApplied.subtracting(targetCIDs).union(nativeFirstCIDs)
        if staleDivertCheckSlot == deviceIndex {
            // Once per discovery: controls the mouse still has diverted from an earlier run.
            // Nothing stale, nothing added: the writes below are the usual ones.
            staleDivertCheckSlot = nil
            let stale = Self.staleDivertDecision(
                queriedControls: queriedControlStates,
                wanted: targetCIDs,
                undivertedAnyway: toUndivert,
                managed: LogiSessionManager.shared.mouseManaged,
                recording: LogiCenter.shared.isRecording
            )
            toUndivert.formUnion(stale.giveBack)
            if let line = Self.staleDivertLine(stale, name: LogiCIDDirectory.name(forCID:)) {
                LogiSystemLog.note("\(logTag(slot: deviceIndex)) \(line)")
            }
        }
        #if DEBUG
        LogiTrace.log(
            "[Session] applyUsage target=\(LogiTrace.cids(targetCIDs)) nativeFirst=\(LogiTrace.cids(nativeFirstCIDs)) toDivert=\(LogiTrace.cids(toDivert)) toUndivert=\(LogiTrace.cids(toUndivert))",
            device: deviceInfo.name
        )
        #endif
        releaseActiveButtonState(for: toUndivert, reason: "usage removed")
        for cid in toDivert {
            setControlReporting(featureIndex: reprogIdx, cid: cid, divert: true)
        }
        for cid in toUndivert {
            setControlReporting(featureIndex: reprogIdx, cid: cid, divert: false)
        }
        self.lastApplied = targetCIDs
        // Controls that stay diverted got no write above: re-state the ones whose raw XY
        // state changed (the setting was toggled while the binding stayed).
        gesture.reconcile(diverted: targetCIDs)
        scheduleBLEStandardUndivertGuard(for: nativeFirstCIDs)
    }

    private static func targetCIDsForUsage(
        aggregateScrollioCodes: Set<UInt16>,
        divertableCIDs: Set<UInt16>,
        transport: LogiTransportIdentity,
        phase: LogiButtonDeliveryPhase,
        policy: LogiButtonDeliveryPolicy,
        deliveryModeForCID: (UInt16) -> LogiButtonDeliveryMode
    ) -> Set<UInt16> {
        let divertableCIDs = LogiButtonDeliveryPolicy.divertCandidates(divertableCIDs)
        return aggregateScrollioCodes.reduce(into: Set<UInt16>()) { acc, code in
            guard let cid = LogiCIDDirectory.toCID(code),
                  divertableCIDs.contains(cid),
                  shouldUseHIDPPDelivery(mode: deliveryModeForCID(cid)),
                  policy.shouldUseHIDPPDelivery(transport: transport, cid: cid, phase: phase) else {
                return
            }
            acc.insert(cid)
        }
    }

    private static func nativeFirstCIDsForUsage(
        aggregateScrollioCodes: Set<UInt16>,
        divertableCIDs: Set<UInt16>,
        transport: LogiTransportIdentity,
        phase: LogiButtonDeliveryPhase,
        policy: LogiButtonDeliveryPolicy
    ) -> Set<UInt16> {
        let divertableCIDs = LogiButtonDeliveryPolicy.divertCandidates(divertableCIDs)
        return aggregateScrollioCodes.reduce(into: Set<UInt16>()) { acc, code in
            guard let cid = LogiCIDDirectory.toCID(code) ?? LogiCIDDirectory.cid(forNativeMouseButton: code),
                  divertableCIDs.contains(cid),
                  !policy.shouldUseHIDPPDelivery(transport: transport, cid: cid, phase: phase) else {
                return
            }
            acc.insert(cid)
        }
    }

    private static func shouldUseHIDPPDelivery(mode: LogiButtonDeliveryMode) -> Bool {
        switch mode {
        case .hidpp:
            return true
        case .contended:
            return false
        }
    }

    private static func recordingDivertPlan(
        divertableCIDs: Set<UInt16>,
        lastApplied: Set<UInt16>,
        transport: LogiTransportIdentity,
        policy: LogiButtonDeliveryPolicy
    ) -> RecordingDivertPlan {
        // Never the left or the right button: see LogiButtonDeliveryPolicy.primaryClickCIDs.
        let divertableCIDs = LogiButtonDeliveryPolicy.divertCandidates(divertableCIDs)
        let desired = divertableCIDs.filter { cid in
            policy.shouldUseHIDPPDelivery(
                transport: transport,
                cid: cid,
                phase: .recording
            )
        }
        let nativeFirst = divertableCIDs.filter { cid in
            !policy.shouldUseHIDPPDelivery(
                transport: transport,
                cid: cid,
                phase: .recording
            )
        }
        return RecordingDivertPlan(
            desired: desired,
            toDivert: desired.subtracting(lastApplied),
            toUndivert: lastApplied.subtracting(desired).union(nativeFirst)
        )
    }

    private func scheduleBLEStandardUndivertGuard(for nativeFirstCIDs: Set<UInt16>) {
        let policy = LogiButtonDeliveryPolicy.default
        guard policy.standardButtonUndivertGuardEnabled else {
            #if DEBUG
            LogiTrace.log("[StandardButtonGuard] skipped: disabled by policy", device: deviceInfo.name)
            #endif
            cancelBLEStandardUndivertGuard()
            return
        }
        guard connectionMode == .bleDirect,
              currentReceiverTargetIsConnected else {
            #if DEBUG
            LogiTrace.log("[StandardButtonGuard] skipped mode=\(connectionMode) connected=\(currentReceiverTargetIsConnected)", device: deviceInfo.name)
            #endif
            cancelBLEStandardUndivertGuard()
            return
        }

        let activeTargets = nativeFirstCIDs.filter { LogiCIDDirectory.nativeMouseButton(forCID: $0) != nil }
        #if DEBUG
        LogiTrace.log("[StandardButtonGuard] planning target=\(LogiTrace.cids(nativeFirstCIDs)) active=\(LogiTrace.cids(activeTargets)) existing=\(LogiTrace.cids(bleStandardUndivertGuardTargets)) interval=\(String(format: "%.2fs", policy.standardButtonUndivertGuardInterval))", device: deviceInfo.name)
        #endif
        guard activeTargets != bleStandardUndivertGuardTargets else { return }

        cancelBLEStandardUndivertGuard()
        guard !activeTargets.isEmpty else { return }

        bleStandardUndivertGuardTargets = activeTargets
        #if DEBUG
        let targets = activeTargets
            .sorted()
            .map { String(format: "0x%04X", $0) }
            .joined(separator: ", ")
        LogiDebugPanel.log("[\(deviceInfo.name)] BLE standard-button undivert guard active every \(String(format: "%.1f", policy.standardButtonUndivertGuardInterval))s for CIDs: \(targets)")
        #endif
        scheduleBLEUndivertGuardTick(
            expectedTargets: activeTargets,
            generation: bleStandardUndivertGuardGeneration,
            interval: policy.standardButtonUndivertGuardInterval
        )
    }

    private func scheduleBLEUndivertGuardTick(
        expectedTargets: Set<UInt16>,
        generation: Int,
        interval: TimeInterval
    ) {
        bleStandardUndivertGuardWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.runBLEStandardUndivertGuard(
                expectedTargets: expectedTargets,
                generation: generation,
                interval: interval
            )
        }
        bleStandardUndivertGuardWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: item)
    }

    private func runBLEStandardUndivertGuard(
        expectedTargets: Set<UInt16>,
        generation: Int,
        interval: TimeInterval
    ) {
        guard generation == bleStandardUndivertGuardGeneration,
              connectionMode == .bleDirect,
              currentReceiverTargetIsConnected else {
            #if DEBUG
            LogiTrace.log(
                "[StandardButtonGuard] tick skipped generation=\(generation) currentGeneration=\(bleStandardUndivertGuardGeneration) mode=\(connectionMode) connected=\(currentReceiverTargetIsConnected)",
                device: deviceInfo.name
            )
            #endif
            return
        }

        let policy = LogiButtonDeliveryPolicy.default
        guard policy.standardButtonUndivertGuardEnabled else {
            cancelBLEStandardUndivertGuard()
            return
        }

        let activeTargets = expectedTargets.filter { LogiCIDDirectory.nativeMouseButton(forCID: $0) != nil }
        guard !activeTargets.isEmpty else {
            cancelBLEStandardUndivertGuard()
            return
        }

        bleStandardUndivertGuardTargets = activeTargets
        sendBLEUndivertGuardReportingQueries(for: activeTargets)
        scheduleBLEUndivertGuardTick(
            expectedTargets: activeTargets,
            generation: generation,
            interval: interval
        )
    }

    private func sendBLEUndivertGuardReportingQueries(for activeTargets: Set<UInt16>) {
        guard reportingQueryTimer == nil else {
            #if DEBUG
            LogiTrace.log("[StandardButtonGuard] reporting query deferred: full reporting refresh in flight", device: deviceInfo.name)
            #endif
            return
        }

        expireStaleBLEUndivertGuardQueries()
        let probes = bleStandardButtonUndivertPlanner.reportingQueryProbes(
            activeTargets: activeTargets,
            reprogFeatureIndex: featureIndex[Self.featureReprogV4]
        )
        guard !probes.isEmpty else {
            #if DEBUG
            LogiTrace.log("[StandardButtonGuard] reporting query skipped: REPROG feature unavailable", device: deviceInfo.name)
            #endif
            return
        }

        let now = Date()
        let probesToSend = probes.filter { probe in
            guard let pending = pendingBLEUndivertGuardQueries[probe.targetCID] else {
                return true
            }
            return pending.expiresAt <= now
        }
        guard !probesToSend.isEmpty else { return }

        #if DEBUG
        let targets = probesToSend
            .map { String(format: "0x%04X", $0.targetCID) }
            .joined(separator: ", ")
        LogiTrace.log("[StandardButtonGuard] query reporting targets=\(targets)", device: deviceInfo.name)
        #endif

        for probe in probesToSend {
            pendingBLEUndivertGuardQueries[probe.targetCID] = PendingControlReportingQuery(
                sentAt: now,
                expiresAt: now.addingTimeInterval(Self.controlReportingQueryTTL)
            )
            sendRequest(
                featureIndex: probe.featureIndex,
                functionId: probe.functionId,
                params: probe.params
            )
            divertLedger.noteQuerySent(cid: probe.targetCID)
        }
    }

    private func expireStaleBLEUndivertGuardQueries(now: Date = Date()) {
        pendingBLEUndivertGuardQueries = pendingBLEUndivertGuardQueries.filter { _, pending in
            pending.expiresAt > now
        }
    }

    #if DEBUG
    internal static func targetCIDsForUsageForTests(
        aggregateScrollioCodes: Set<UInt16>,
        divertableCIDs: Set<UInt16>,
        deliveryModeForCID: (UInt16) -> LogiButtonDeliveryMode
    ) -> Set<UInt16> {
        return targetCIDsForUsage(
            aggregateScrollioCodes: aggregateScrollioCodes,
            divertableCIDs: divertableCIDs,
            transport: .receiver,
            phase: .normal,
            policy: LogiButtonDeliveryPolicy(
                standardMouseButtonsUseNativeEvents: false
            ),
            deliveryModeForCID: deliveryModeForCID
        )
    }

    internal static func targetCIDsForUsageForTests(
        aggregateScrollioCodes: Set<UInt16>,
        divertableCIDs: Set<UInt16>,
        transport: LogiTransportIdentity,
        phase: LogiButtonDeliveryPhase,
        policy: LogiButtonDeliveryPolicy,
        deliveryModeForCID: (UInt16) -> LogiButtonDeliveryMode
    ) -> Set<UInt16> {
        return targetCIDsForUsage(
            aggregateScrollioCodes: aggregateScrollioCodes,
            divertableCIDs: divertableCIDs,
            transport: transport,
            phase: phase,
            policy: policy,
            deliveryModeForCID: deliveryModeForCID
        )
    }

    internal static func nativeFirstCIDsForUsageForTests(
        aggregateScrollioCodes: Set<UInt16>,
        divertableCIDs: Set<UInt16>,
        transport: LogiTransportIdentity,
        phase: LogiButtonDeliveryPhase,
        policy: LogiButtonDeliveryPolicy
    ) -> Set<UInt16> {
        return nativeFirstCIDsForUsage(
            aggregateScrollioCodes: aggregateScrollioCodes,
            divertableCIDs: divertableCIDs,
            transport: transport,
            phase: phase,
            policy: policy
        )
    }

    internal static func recordingDivertPlanForTests(
        divertableCIDs: Set<UInt16>,
        lastApplied: Set<UInt16>,
        transport: LogiTransportIdentity,
        policy: LogiButtonDeliveryPolicy
    ) -> RecordingDivertPlan {
        return recordingDivertPlan(
            divertableCIDs: divertableCIDs,
            lastApplied: lastApplied,
            transport: transport,
            policy: policy
        )
    }
    #endif

    // MARK: - Debug Accessors (for HID++ debug panel)
    var debugFeatureIndex: [UInt16: UInt8] { featureIndex }
    var debugDiscoveredControls: [ControlInfo] { discoveredControls }
    var debugDivertedCIDs: Set<UInt16> { divertedCIDs }

    func ownershipKey(forCID cid: UInt16) -> LogiOwnershipKey {
        return LogiOwnershipKey(
            vendorId: deviceInfo.vendorId,
            productId: deviceInfo.productId,
            name: deviceInfo.name,
            transport: LogiTransportIdentity(connectionMode),
            cid: cid
        )
    }

    func ownershipKeysForKnownControls() -> [LogiOwnershipKey] {
        return discoveredControls.map { ownershipKey(forCID: $0.cid) }
    }

    /// 查询指定 CID 的 ControlInfo (供冲突判定等外部查询使用).
    func control(forCID cid: UInt16) -> ControlInfo? {
        return discoveredControls.first(where: { $0.cid == cid })
    }
    var debugReprogInitComplete: Bool { reprogInitComplete }
    var debugHandshakeComplete: Bool { handshakeComplete }
    var debugDiscoveryInFlight: Bool { discoveryInFlight }
    var debugIsReceiver: Bool { connectionMode == .receiver }
    var debugCurrentReceiverTargetIsConnected: Bool { currentReceiverTargetIsConnected }
    var debugDeviceIndex: UInt8 { deviceIndex }
    var debugIsBLE: Bool { isBLE }
    var debugDeviceOpened: Bool { deviceOpened }
    var debugReceiverPairedDevices: [ReceiverPairedDevice] { receiverPairedDevices }
    var debugConnectionMode: String {
        switch connectionMode {
        case .bleDirect: return "BLE Direct"
        case .receiver: return "Receiver (Unifying/Bolt)"
        case .unsupported: return "Unsupported"
        }
    }

    private var currentReceiverTargetIsConnected: Bool {
        return Self.receiverTargetIsConnected(
            connectionMode: connectionMode,
            deviceIndex: deviceIndex,
            pairedDevices: receiverPairedDevices
        )
    }

    private static func receiverTargetIsConnected(
        connectionMode: ConnectionMode,
        deviceIndex: UInt8,
        pairedDevices: [ReceiverPairedDevice]
    ) -> Bool {
        guard connectionMode == .receiver else { return true }
        guard deviceIndex >= 1 && deviceIndex <= 6 else { return false }
        return pairedDevices.first(where: { $0.slot == deviceIndex })?.isConnected ?? true
    }

    /// 巡检游标默认选择: 优先在线的鼠标 slot, 无鼠标回退首个在线 slot, 全空返回 nil.
    /// 取代 finishPingPhase 旧的"锁编号最低在线 slot"逻辑, 避免锁到键盘/另一只鼠标.
    static func chooseReceiverTargetSlot(devices: [ReceiverPairedDevice]) -> UInt8? {
        let connected = devices.filter { $0.isConnected }
        if let mouse = connected.first(where: { $0.deviceType == receiverDeviceTypeMouse }) {
            return mouse.slot
        }
        return connected.first?.slot
    }

    /// 明确不接管的设备类型: 键盘 / 数字键盘 / 演示器. 其余(鼠标 / 轨迹球 / 触控板 / 未知)
    /// 都纳入接管候选. 关键: 有些接收器(如 Bolt / 较新 USB Receiver)不支持 HID++ 1.0 寄存器
    /// 0xB5 读设备信息(返回 InvalidSubID), deviceType 恒为 0(未知). 此时若按"必须 == Mouse"
    /// 过滤, 鼠标(类型未知)会被错误排除、永不 divert. 故改为"排除已知非鼠标类型", 未知放行.
    private static let receiverNonDivertDeviceTypes: Set<UInt8> = [
        0x01, // Keyboard
        0x03, // Numpad
        0x04, // Presenter
    ]

    /// Whether a receiver slot is taken over (discovered, kept as a session slot): connected
    /// and not a known keyboard / numpad / presenter (an unknown type counts as a mouse, see
    /// receiverNonDivertDeviceTypes). Bindings play no part: the Mouse pane, the battery line
    /// and the managed wheel and basic values need the slot without any Logitech button
    /// binding. Bindings only decide what is diverted (applyUsage diverts nothing for an
    /// empty aggregate).
    static func receiverSlotIsTakeoverCandidate(connected: Bool, deviceType: UInt8, knownNotAMouse: Bool = false) -> Bool {
        return connected && !knownNotAMouse && !receiverNonDivertDeviceTypes.contains(deviceType)
    }

    /// 接管集合: 启动时需要各自 discovery 常驻接管的 slot (receiverSlotIsTakeoverCandidate), 按 slot 升序.
    /// 类型未知的 slot 也会纳入(见 receiverNonDivertDeviceTypes); sweep 后非鼠标 slot 不进
    /// receiverManagedSlots, 其 divert 仍被 applyUsage 按各设备实际 divertable CID 过滤, 不会误伤键盘按键.
    static func receiverTakeoverSlots(devices: [ReceiverPairedDevice]) -> [UInt8] {
        return devices
            .filter { receiverSlotIsTakeoverCandidate(connected: $0.isConnected, deviceType: $0.deviceType) }
            .map { $0.slot }
            .sorted()
    }

    /// 决定接收器 peripheral 报文按 report[1] 路由到哪个 slot.
    /// 单设备时 managedSlots = {currentSlot}, 任何非 current 的 slot 都 drop, 与旧 stale 过滤等价.
    static func receiverReportRoute(
        incomingSlot: UInt8,
        currentSlot: UInt8,
        managedSlots: Set<UInt8>
    ) -> ReceiverReportRoute {
        guard incomingSlot >= 1 && incomingSlot <= 6 else { return .drop }
        if incomingSlot == currentSlot { return .processCurrent }
        if managedSlots.contains(incomingSlot) { return .processScoped(incomingSlot) }
        return .drop
    }

    /// 多设备热插拔(§Phase 4): 某 slot 的 0x41 连接/断开通知该做什么(纯决策).
    /// - 断开: 若该 slot 正被接管 -> release(释放其按键状态 + 标记未 init); 否则 ignore
    /// - 连接: 若已接管 -> ignore(防振荡, "已 init 且在线则忽略"); 否则若是接管候选 -> takeover
    ///   (isDivertCandidate = receiverSlotIsTakeoverCandidate: connected and mouse-like, bindings play no part)
    /// 关键: 鼠标关机 / 按背面键切 Bolt 主机再切回, 重连会丢失 divert 状态, 必须重新
    /// discovery+divert(takeover), 否则其 HID++ 按键不再生效. 全为离散事件驱动, 不违红线(§2).
    static func receiverSlotConnectionAction(
        slot: UInt8,
        connected: Bool,
        isDivertCandidate: Bool,
        alreadyManaged: Bool
    ) -> ReceiverSlotConnectionAction {
        guard slot >= 1 && slot <= 6 else { return .ignore }
        if !connected {
            return alreadyManaged ? .release(slot) : .ignore
        }
        if alreadyManaged { return .ignore }
        guard isDivertCandidate else { return .ignore }
        return .takeover(slot)
    }

    /// 部分接收器不会在休眠设备恢复时发送 0x41; 离线 slot 的真实报文可作为连接证据.
    static func receiverPeripheralActivityAction(
        slot: UInt8,
        wasConnected: Bool,
        isDivertCandidate: Bool,
        alreadyManaged: Bool
    ) -> ReceiverSlotConnectionAction {
        guard !wasConnected else { return .ignore }
        return receiverSlotConnectionAction(
            slot: slot,
            connected: true,
            isDivertCandidate: isDivertCandidate,
            alreadyManaged: alreadyManaged
        )
    }

    // MARK: Finding the devices on a receiver (pure decisions)

    /// Whether a HID++ 1.0 error answers this app's slot ping. An error names the request it
    /// refuses by that request's bytes 2 and 3: for the ping the root feature (0x00) and
    /// `slotPingFunctionByte`. An error for another program's request to the same slot, or
    /// for another request of this app, says nothing about the ping.
    static func hidpp10ErrorAnswersSlotPing(refusedSubId: UInt8, refusedAddress: UInt8) -> Bool {
        return refusedSubId == 0x00 && refusedAddress == slotPingFunctionByte
    }

    enum SlotPingErrorStep: Equatable {
        /// The receiver was busy with another device: this slot is asked again.
        case askAgain(attempt: Int)
        /// No device in the slot, or one that is not connected now.
        case notConnected
    }

    /// What an error to a slot ping means. "Busy" says nothing about the slot: the receiver
    /// was passing a message on to another device (a keyboard on the same receiver, another
    /// program's request) and takes one at a time. It used to count as "no device", so a
    /// mouse in that slot was never looked at. After `slotPingAttemptLimit` pings the slot
    /// is given up like any other that does not answer.
    static func slotPingErrorStep(errorCode: UInt8, attempt: Int) -> SlotPingErrorStep {
        guard errorCode == hidpp10ErrorBusy, attempt < slotPingAttemptLimit else { return .notConnected }
        return .askAgain(attempt: attempt + 1)
    }

    /// Whether a slot that (re)connected may be discovered now. Not while the slots are
    /// still pinged, and not while the first choice of slots is pending: that choice
    /// discovers every connected slot itself, and a second discovery beside it would mix up
    /// the answers (the answer to a feature look-up names neither feature nor request).
    static func receiverTakeoverMayStart(enumPhase: Int, awaitingFirstSelection: Bool) -> Bool {
        return enumPhase != 1 && !awaitingFirstSelection
    }

    /// The queue of slots that wait for their discovery, after a slot's link changed: a slot
    /// that disconnected leaves it. Left queued, it was discovered later although nothing
    /// was there, and while the queue was held it kept its own reconnect from counting.
    static func receiverTakeoverQueue(_ queue: [UInt8], afterLinkOf slot: UInt8, connected: Bool) -> [UInt8] {
        return connected ? queue : queue.filter { $0 != slot }
    }

    /// The slot a "device disconnection" notification names (`10 slot 40 02 …`: the device
    /// was taken off the receiver); nil for any other report.
    static func receiverDisconnectionSlot<Bytes: RandomAccessCollection>(_ report: Bytes) -> UInt8?
    where Bytes.Element == UInt8, Bytes.Index == Int {
        guard report.count >= 4 else { return nil }
        let base = report.startIndex
        guard report[base] == hidppShortReportId,
              report[base + 2] == hidpp10DeviceDisconnection,
              report[base + 3] == 0x02 else { return nil }
        let slot = report[base + 1]
        return slot >= 1 && slot <= 6 ? slot : nil
    }

    /// What the slot pings found, for the system log: the slots by what they answered, e.g.
    /// "connected: 2; not connected (asleep, off or out of range): 1; empty: 3, 4, 5, 6".
    /// No names: a log is pasted into bug reports.
    static func receiverSlotsSummary(_ devices: [ReceiverPairedDevice]) -> String {
        func state(_ device: ReceiverPairedDevice) -> String {
            if device.isConnected { return "connected" }
            switch device.lastError {
            case "UnknownDevice": return "empty"
            case "ResourceError": return "not connected (asleep, off or out of range)"
            case "Busy": return "receiver busy"
            case "Timeout", nil: return "no answer"
            case let other?: return "refused (\(other))"
            }
        }
        var order: [String] = []
        var slots: [String: [UInt8]] = [:]
        for device in devices.sorted(by: { $0.slot < $1.slot }) {
            let key = state(device)
            if slots[key] == nil { order.append(key) }
            slots[key, default: []].append(device.slot)
        }
        // Connected first, empty last, the rest in slot order between them.
        let rank: (String) -> Int = { $0 == "connected" ? 0 : ($0 == "empty" ? 2 : 1) }
        return order
            .enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map { "\($0.element): \(slots[$0.element]!.map { String($0) }.joined(separator: ", "))" }
            .joined(separator: "; ")
    }

    /// What a finished look at the connected slots found, for the system log.
    static func receiverSweepLine(mouseSlots: [UInt8]) -> String {
        guard !mouseSlots.isEmpty else {
            return "Receiver: no mouse among the connected devices (none has a left and a right button Scrollio can read)"
        }
        let slots = mouseSlots.map { String($0) }.joined(separator: ", ")
        return "Receiver: \(mouseSlots.count == 1 ? "mouse in slot" : "mice in slots") \(slots)"
    }

    #if DEBUG
    internal static func receiverTargetIsConnectedForTests(
        connectionMode: ConnectionMode,
        deviceIndex: UInt8,
        pairedDevices: [ReceiverPairedDevice]
    ) -> Bool {
        return receiverTargetIsConnected(
            connectionMode: connectionMode,
            deviceIndex: deviceIndex,
            pairedDevices: pairedDevices
        )
    }
    #endif

    // MARK: - Setup / Teardown

    func setup() {
        isBLE = transport.lowercased().contains("bluetooth")

        // 确定连接模式
        if isBLE {
            connectionMode = .bleDirect
            deviceIndex = 0xFF
        } else if isHIDPPCandidate {
            // A vendor-specific interface of a receiver (isHIDPPCandidate).
            connectionMode = .receiver
            deviceIndex = 0x01  // 临时值, 枚举后会自动更新到实际在线 slot
        } else {
            connectionMode = .unsupported
        }

        let tag = "[\(deviceInfo.name):\(String(format: "0x%04X", usagePage))/\(String(format: "0x%04X", usage))]"
        LogiDebugPanel.log("\(tag) Setup: transport=\(transport), mode=\(connectionMode), devIdx=\(String(format: "0x%02X", deviceIndex)), isCandidate=\(isHIDPPCandidate)")

        // 只对 HID++ 候选接口进行协议通信
        guard isHIDPPCandidate else {
            // No input-report callback either: nothing in it applies to such an interface
            // (it only parses HID++ reports against features this session discovered), and
            // on the ordinary mouse interface of a receiver or a wired mouse it woke the main
            // run loop, which also serves the event taps, for every movement report.
            LogiDebugPanel.log("\(tag) Skipping: not a HID++ candidate interface")
            return
        }

        // 显式打开设备 (IOHIDManagerOpen 可能不够)
        let openResult = IOHIDDeviceOpen(hidDevice, IOOptionBits(kIOHIDOptionsTypeNone))
        if openResult == kIOReturnSuccess {
            deviceOpened = true
            LogiDebugPanel.log("\(tag) IOHIDDeviceOpen: OK")
        } else {
            LogiDebugPanel.log("\(tag) IOHIDDeviceOpen: failed \(String(format: "0x%08x", openResult)), proceeding anyway")
        }

        setupInputReportCallback()

        // 标记初次 discovery 开始 (覆盖 receiver enumeration + BLE direct discovery + 缓存验证),
        // UI 打开 debug panel 时能看到 Initializing spinner.
        setDiscoveryInFlight(true)

        // Receiver 模式: 先枚举 slot, 找到在线设备后自动 target + feature discovery
        if connectionMode == .receiver {
            LogiDebugPanel.log("\(tag) Receiver mode: enumerating paired devices...")
            enumerateReceiverDevices()
            return
        }

        // BLE / 直连模式: 直接 Feature Discovery (尝试缓存, 失败则完整 discovery)
        if let cached = Self.loadCachedFeatureIndex(for: deviceInfo.productId),
           cached[Self.featureReprogV4] != nil {
            validateCachedFeatureIndex(cached, tag: tag)
        } else {
            LogiDebugPanel.log("\(tag) Starting feature discovery for REPROG_CONTROLS_V4 (0x1B04)")
            startFreshDiscovery(tag: tag)
        }
    }

    private func setupInputReportCallback() {
        reportBufferPtr = .allocate(capacity: Self.reportBufferSize)
        reportBufferPtr!.initialize(repeating: 0, count: Self.reportBufferSize)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            hidDevice, reportBufferPtr!, Self.reportBufferSize, Self.inputReportCallback, context
        )
        inputReportCallbackRegistered = true
    }

    private var inputReportCallbackRegistered = false

    /// Takes the callback off the device (a nil callback unregisters). The callback holds the
    /// session unretained and writes into `reportBufferPtr`: a report delivered after the
    /// session was freed would have used freed memory.
    private func removeInputReportCallback() {
        guard inputReportCallbackRegistered, let buffer = reportBufferPtr else { return }
        inputReportCallbackRegistered = false
        IOHIDDeviceRegisterInputReportCallback(hidDevice, buffer, Self.reportBufferSize, nil, nil)
    }

    /// Lets go of the device: every button Scrollio diverted, on every slot, is given back
    /// (and raw XY switched off), then the session forgets everything it knew.
    ///
    /// - Parameter deviceGone: the device was removed (switched off, out of range, the
    ///   receiver unplugged). Nothing can be given back then, and a write to a device that
    ///   is gone can block for seconds: nothing is queued and nothing is waited for. The
    ///   event taps run during a removal, so a wait here would hold up the input of the
    ///   whole system.
    func teardown(deviceGone: Bool = false) {
        LogiDebugPanel.log("[\(deviceInfo.name)] Teardown\(deviceGone ? " (device removed)" : "")")
        tornDownWithDeviceGone = deviceGone
        pendingInitialTargetSelection = false
        pendingDeviceInfoSlots.removeAll()
        // Nothing of an enumeration under way may fire into a session that was torn down.
        receiverEnumPhase = 0
        pendingSlotPings.removeAll()
        slotPingTimeout?.cancel()
        slotPingTimeout = nil
        connectionReportsGate?.cancel()
        connectionReportsGate = nil
        connectionReports.cancel()
        let managedSlots = receiverManagedSlots
        receiverManagedSlots.removeAll()
        pendingDivertSlots.removeAll()
        receiverInspectionSlot = nil
        receiverSweptSlots.removeAll()
        receiverOptionalProbedSlots.removeAll()
        receiverNonMouseSlots.removeAll()
        receiverTakeoverDebounce.values.forEach { $0.cancel() }
        receiverTakeoverDebounce.removeAll()
        dropAllWheelControllers()
        dropAllMouseBasicsControllers()
        dropAllPendingDiscoveries()
        controlInfoQueryTimer?.invalidate()
        controlInfoQueryTimer = nil
        reportingQueryTimer?.invalidate()
        reportingQueryTimer = nil
        cancelControlCountWait()
        deviceNameReads.removeAll()
        pendingActions.cancelAll()
        cancelDivertReassertion()
        cancelBLEStandardUndivertGuard()
        // Every slot with state, not only the one the cursor is on: on a receiver with two
        // mice (or with the cursor left on a keyboard by the diagnostics window) the other
        // mouse used to keep its buttons diverted after Pause and Quit.
        let slots = Self.teardownSlots(known: Set(slotStates.keys), managed: managedSlots, cursor: deviceIndex)
        forEachSlot(slots) {
            releaseAllActiveButtonState(reason: "teardown")
        }
        // Raw XY first, on every slot: a control left armed would keep freezing the pointer
        // while it is held, with nobody listening to its movement.
        if !deviceGone {
            disarmAllGestureControllers()
        }
        forEachSlot(slots) {
            if !deviceGone, let reprogIdx = featureIndex[Self.featureReprogV4] {
                for cid in divertLedger.toGiveBack.sorted() {
                    setControlReporting(featureIndex: reprogIdx, cid: cid, divert: false)
                }
            }
            controlInfoRetryCounts.removeAll()
            divertLedger = LogiDivertLedger()
            discoveredControls.removeAll()
        }
        dropAllGestureControllers()
        cancelDivertReassertion()
        // timer 已清零, 此时 isActivityInProgress 只剩 discoveryInFlight 一个分量;
        // 走 setter 让 Manager 重算聚合 busy, 防止 session 销毁后 UI spinner 卡住.
        setDiscoveryInFlight(false)
        // No report may reach this session any more: the callback holds it unretained, and
        // a session that was torn down is never used again.
        removeInputReportCallback()
        guard !deviceGone else { return }
        // The requests above that give the mouse its buttons back are queued: wait for them
        // here, before the device is closed or the app exits. On this path (Pause, Quit,
        // sleep: LogiSessionManager.stop) the event taps are off by now (AppRunController
        // stops them first), so waiting holds up nobody's input.
        drainWrites(reason: "teardown", timeout: Self.writeDrainTimeoutAtTeardown)
    }

    /// The slots teardown visits: every slot it has state for, every slot it took over, and
    /// the cursor slot.
    static func teardownSlots(known: Set<UInt8>, managed: Set<UInt8>, cursor: UInt8) -> [UInt8] {
        return known.union(managed).union([cursor]).sorted()
    }

    // MARK: - Input Report Callback

    static let inputReportCallback: IOHIDReportCallback = { context, result, sender, type, reportID, report, reportLength in
        guard let context = context else { return }
        let session = Unmanaged<LogiDeviceSession>.fromOpaque(context).takeUnretainedValue()
        let buffer = UnsafeBufferPointer(start: report, count: reportLength)
        session.handleInputReport(buffer)
    }

    // MARK: - HID++ Send

    /// 构造 HID++ 2.0 long request: [0x11, devIdx, featureIdx, fn<<4 | swid, params(≤16)...].
    /// functionId 是 0...15 的函数号 (不是已左移的 0x10/0x20): 传入已左移的值会在 UInt8 里溢出
    /// 成 fn0, 设备执行错误的函数 (历史 bug: HiRes/ScrollInvert/ThumbWheel/PointerSpeed 动作).
    /// 越界值返回 nil, 调用方不发送.
    static func hidppLongRequest(deviceIndex: UInt8, featureIndex: UInt8, functionId: UInt8, params: [UInt8]) -> [UInt8]? {
        guard functionId <= 0x0F else { return nil }
        var report = [UInt8](repeating: 0, count: 20)
        report[0] = hidppLongReportId
        report[1] = deviceIndex
        report[2] = featureIndex
        report[3] = (functionId << 4) | hidppSoftwareId
        for (i, p) in params.prefix(16).enumerated() { report[4 + i] = p }
        return report
    }

    /// 发送 HID++ 请求
    /// BLE 直连: long report (20 bytes) + report ID in payload (hidapi 兼容)
    /// Receiver: 同样的 long report, report[1] = slot
    /// functionId: 函数号 0...15 (见 hidppLongRequest)
    private func sendRequest(featureIndex: UInt8, functionId: UInt8, params: [UInt8] = []) {
        let report: [UInt8]

        switch connectionMode {
        case .bleDirect, .receiver:
            guard let built = Self.hidppLongRequest(
                deviceIndex: deviceIndex, featureIndex: featureIndex, functionId: functionId, params: params
            ) else {
                assertionFailure("HID++ functionId must be 0...15, got \(functionId)")
                LogiDebugPanel.log(device: deviceInfo.name, type: .error, message: "Not sent: invalid HID++ function id \(functionId) for feature index \(featureIndex)")
                return
            }
            report = built

        case .unsupported:
            LogiDebugPanel.log(device: deviceInfo.name, type: .warning, message: "Cannot send: unsupported connection mode")
            return
        }

        let hex = report.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " ")
        let decoded = decodeRequest(featureIndex: featureIndex, functionId: functionId, params: params)
        LogiDebugPanel.log(device: deviceInfo.name, type: .tx, message: "TX: \(hex)...", decoded: decoded)
        queueReport(report, .feature(index: featureIndex, function: functionId))
    }

    // MARK: - Writes (off the main thread, see LogiReportWriter)

    /// How long teardown waits for the queued writes (the requests that give the mouse its
    /// buttons back): about ten of them at 15 to 29 ms each over Bluetooth, so this is ample
    /// and still bounds a device that does not answer.
    static let writeDrainTimeoutAtTeardown: TimeInterval = 2.0
    static let writeDrainTimeoutAtRelease: TimeInterval = 1.0

    /// Every output report of this session goes out through this writer, in the order it was
    /// queued. The device call (`IOHIDDeviceSetReport`) takes 15 to 29 ms over Bluetooth and
    /// used to run on the main thread, holding up the event taps: it runs on the writer's
    /// queue now. The writer keeps the device; the session keeps the writer.
    private(set) lazy var reportWriter: LogiReportWriter = {
        let device = hidDevice
        return LogiReportWriter(label: "com.nikklemenc.Scrollio.logi.write") { report in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(report[0]), report, report.count)
        }
    }()

    private var writeTiming = LogiWriteTiming()

    private var writeLink: LogiWriteTiming.Link {
        return connectionMode == .bleDirect ? .bluetooth : .receiver
    }

    /// Queues an output report and returns at once. When the device has taken it (or refused
    /// it), the time it took and a refusal go to the `logi` log, on the main thread.
    private func queueReport(_ report: [UInt8], _ request: LogiWriteTiming.Request) {
        let link = writeLink
        let queueStarted = DispatchTime.now().uptimeNanoseconds
        reportWriter.write(report) { [weak self] outcome in
            guard let self = self else { return }
            let now = DispatchTime.now().uptimeNanoseconds
            if outcome.result != kIOReturnSuccess {
                let failure = String(format: "HID++ write refused: 0x%08x (%@)", UInt32(bitPattern: outcome.result), request.text)
                LogiDebugPanel.log(device: self.deviceInfo.name, type: .error, message: failure)
                if let line = self.writeTiming.recordFailure(result: outcome.result, now: now, request: request, link: link) {
                    LogiSystemLog.note("\(self.sessionLogTag) \(line)")
                }
            }
            if let line = self.writeTiming.record(duration: outcome.duration, now: now, request: request, link: link) {
                LogiSystemLog.note("\(self.sessionLogTag) \(line)")
            }
        }
        writeTiming.noteQueued(mainThreadHeld: DispatchTime.now().uptimeNanoseconds &- queueStarted)
    }

    /// Waits for the writes still queued, and says so when that held the main thread.
    private func drainWrites(reason: String, timeout: TimeInterval) {
        let started = DispatchTime.now().uptimeNanoseconds
        let finished = reportWriter.drain(timeout: timeout)
        let waited = DispatchTime.now().uptimeNanoseconds &- started
        guard !finished || waited >= 5_000_000 else { return }
        LogiSystemLog.note("\(sessionLogTag) \(LogiWriteTiming.drainLine(waited: waited, finished: finished, reason: reason))")
    }

    /// The diagnostics panel's own requests (Debug builds): through the same queue, so that
    /// two writes never reach the device at once. `completion` runs on the main thread.
    func writeReportForDebug(_ report: [UInt8], completion: @escaping (IOReturn) -> Void) {
        reportWriter.write(report) { outcome in
            completion(outcome.result)
        }
    }

    /// The discovery ran out. The first time on this connection (for a receiver: after the
    /// last slot of its takeover sweep), the summary of the writes so far.
    private func noteSetupWritesDone() {
        guard !(receiverSweepActive && !pendingDivertSlots.isEmpty) else { return }
        // Once the writes queued so far have gone out and were counted.
        reportWriter.afterQueued { [weak self] in
            guard let self = self, let line = self.writeTiming.finishSetup(link: self.writeLink) else { return }
            LogiSystemLog.note("\(self.sessionLogTag) \(line)")
        }
    }

    // MARK: - Feature Discovery

    /// The look-ups that show whether a saved feature table still fits the mouse: the
    /// buttons feature (0x1B04) and the saved feature with the highest index, each with the
    /// index the mouse has to answer. The table is saved per product id, and a mouse of
    /// that product with another firmware (an update, a second mouse of the model) can have
    /// a feature more or less; the table is in the order of the feature ids, so that moves
    /// every later index, the last one included. A ping, which the saved table used to be
    /// trusted after, says nothing about that.
    static func featureCacheProbes(_ cached: [UInt16: UInt8]) -> [(featureId: UInt16, index: UInt8)] {
        guard let reprogIndex = cached[featureReprogV4] else { return [] }
        var probes = [(featureId: featureReprogV4, index: reprogIndex)]
        // The highest index; of two features saved with the same index (a broken table) the
        // lower id, so that the choice does not depend on the order of the dictionary.
        if let last = cached.max(by: { ($0.value, $1.key) < ($1.value, $0.key) }), last.key != featureReprogV4 {
            probes.append((featureId: last.key, index: last.value))
        }
        return probes
    }

    /// Uses the saved feature table only when the mouse confirms it (`featureCacheProbes`);
    /// otherwise the entry is dropped and the features are looked up afresh. Until then no
    /// saved index is in use: nothing is sent to an index the mouse did not just confirm.
    /// Each look-up has the getFeature timeout, so a lost answer ends in a fresh discovery
    /// instead of a session that stays "initializing".
    private func validateCachedFeatureIndex(_ cached: [UInt16: UInt8], tag: String) {
        let probes = Self.featureCacheProbes(cached)
        LogiDebugPanel.log("\(tag) Checking the saved feature table (\(cached.count) features) with \(probes.count) look-up(s)")
        checkNextCacheProbe(probes[...], cached: cached, tag: tag)
    }

    private func checkNextCacheProbe(
        _ remaining: ArraySlice<(featureId: UInt16, index: UInt8)>,
        cached: [UInt16: UInt8],
        tag: String
    ) {
        guard let probe = remaining.first else {
            LogiDebugPanel.log("\(tag) Saved feature table confirmed")
            featureIndex = cached
            featureIndicesFromCache = Set(cached.values)
            if let reprogIdx = cached[Self.featureReprogV4] {
                sendGetControlCount(featureIndex: reprogIdx)
            }
            return
        }
        discoverFeature(featureId: probe.featureId) { [weak self] index in
            guard let self = self else { return }
            guard index == probe.index else {
                let found = index.map { String(format: "0x%02X", $0) } ?? "no answer or not present"
                let message = String(format: "Saved feature table dropped: feature 0x%04X was saved at index 0x%02X, the mouse says %@; looking the features up afresh", probe.featureId, probe.index, found)
                LogiDebugPanel.log("\(tag) \(message)")
                LogiSystemLog.note("\(self.logTag(slot: self.deviceIndex)) \(message)")
                Self.removeCachedFeatureIndex(for: self.deviceInfo.productId)
                self.startFreshDiscovery(tag: tag)
                return
            }
            self.checkNextCacheProbe(remaining.dropFirst(), cached: cached, tag: tag)
        }
    }

    private func startFreshDiscovery(tag: String) {
        discoverFeature(featureId: Self.featureReprogV4) { [weak self] index in
            guard let self = self else { return }
            guard let index = index else {
                LogiDebugPanel.log("\(tag) REPROG_CONTROLS_V4 not available")
                // Discovery 走到终点但未命中 REPROG, 仍算握手完成 (Mos 能做的已经做完).
                self.markHandshakeComplete()
                NotificationCenter.default.post(name: LogiSessionManager.reportingQueryDidCompleteNotification, object: nil)
                LogiSessionManager.shared.recomputeAndNotifyActivityState()
                // 该 slot 无 REPROG(不可 divert), 但仍需推进接管 sweep 到下一个 slot.
                self.receiverSlotDiscoveryDidFinish(didDivert: false)
                return
            }
            self.featureIndex[Self.featureReprogV4] = index
            LogiDebugPanel.log("\(tag) REPROG_CONTROLS_V4 at index \(String(format: "0x%02X", index))")
            // 缓存 feature index
            self.saveFeatureIndexCache()
            self.sendGetControlCount(featureIndex: index)
        }
    }

    /// 置 handshake 终态并通知 sidebar 刷新.
    /// 同一 session 多次调用安全 (仅在首次 false→true 过渡时 post).
    private func markHandshakeComplete() {
        setDiscoveryInFlight(false)
        guard !handshakeComplete else { return }
        handshakeComplete = true
        NotificationCenter.default.post(name: LogiSessionManager.sessionChangedNotification, object: nil)
        probeOptionalFeatures()
    }

    /// discoveryInFlight 切换 + 通知. idempotent: 只在状态变化时 post.
    private func setDiscoveryInFlight(_ flag: Bool) {
        guard discoveryInFlight != flag else { return }
        discoveryInFlight = flag
        if !flag { noteSetupWritesDone() }
        NotificationCenter.default.post(name: LogiSessionManager.discoveryStateDidChangeNotification, object: nil)
        LogiSessionManager.shared.recomputeAndNotifyActivityState()
    }

    /// 任一阶段 (discovery / reporting query) 正在进行; UI 据此驱动 activity spinner.
    var isActivityInProgress: Bool {
        return discoveryInFlight || reportingQueryTimer != nil
    }

    /// 供 UI hover popover 读取的 session 级活动快照. 无活动时返回 nil.
    /// 只读投影, 不改变任何内部状态; 读线程与 HID++ 回调一致 (main).
    var activityStatus: SessionActivityStatus? {
        // reporting query 比 discovery 后发生, 信息更细 (可给出进度), 优先展示.
        if reportingQueryTimer != nil {
            let total = discoveredControls.count
            // reportingQueryIndex 是下一个待发的索引; 展示用 index+1 更贴近"正在查第几个"
            let current = min(reportingQueryIndex + 1, max(total, 1))
            return SessionActivityStatus(
                phase: .reportingQuery,
                deviceName: deviceInfo.name,
                progress: total > 0 ? (current, total) : nil
            )
        }
        if discoveryInFlight {
            return SessionActivityStatus(
                phase: .discovery,
                deviceName: deviceInfo.name,
                progress: nil
            )
        }
        return nil
    }

    private func discoverFeature(featureId: UInt16, completion: @escaping (UInt8?) -> Void) {
        let params: [UInt8] = [UInt8(featureId >> 8), UInt8(featureId & 0xFF)]
        sendRequest(featureIndex: 0x00, functionId: 0, params: params)
        let token = pendingDiscovery.append(deviceIndex: deviceIndex, featureId: featureId, completion: completion)

        // Its own timeout: a request that is never answered fails alone, the others wait on.
        discoveryTimers[token] = Timer.scheduledTimer(withTimeInterval: Self.discoveryTimeout, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.discoveryTimers[token] = nil
            guard let entry = self.pendingDiscovery.remove(token: token) else { return }
            LogiDebugPanel.log("[\(self.deviceInfo.name)] Feature discovery timed out for \(String(format: "0x%04X", entry.featureId))")
            self.featureDiscoveryTimedOut = true
            entry.completion(nil)
        }
    }

    /// Ends one getFeature request: stops its timeout, then hands the result on.
    private func finishDiscovery(_ entry: LogiFeatureDiscoveryQueue.Entry, featureIndex: UInt8?) {
        discoveryTimers.removeValue(forKey: entry.token)?.invalidate()
        entry.completion(featureIndex)
    }

    /// Forgets every getFeature request without calling back (teardown, a new discovery):
    /// a late answer then finds nobody waiting and is ignored.
    private func dropAllPendingDiscoveries() {
        discoveryTimers.values.forEach { $0.invalidate() }
        discoveryTimers.removeAll()
        pendingDiscovery.removeAll()
    }

    // MARK: - REPROG_CONTROLS_V4 Flow

    private func sendGetControlCount(featureIndex: UInt8, attempt: Int = 1) {
        LogiDebugPanel.log("[\(deviceInfo.name)] Sending GetControlCount\(attempt > 1 ? " (attempt \(attempt))" : "")")
        sendRequest(featureIndex: featureIndex, functionId: 0)
        let slot = deviceIndex
        pendingControlCount = (slot, attempt)
        controlCountTimer?.invalidate()
        controlCountTimer = Timer.scheduledTimer(withTimeInterval: Self.controlCountTimeout, repeats: false) { [weak self] _ in
            self?.controlCountDidFail(slot: slot, reason: "no answer")
        }
    }

    private func cancelControlCountWait() {
        controlCountTimer?.invalidate()
        controlCountTimer = nil
        pendingControlCount = nil
    }

    /// What a GetControlCount without an answer (or with an error for an answer) leads to.
    enum ControlCountFailureStep: Equatable {
        case sendAgain(attempt: Int)
        case endDiscovery
    }

    static func controlCountFailureStep(attempt: Int) -> ControlCountFailureStep {
        return attempt < controlCountAttempts ? .sendAgain(attempt: attempt + 1) : .endDiscovery
    }

    /// GetControlCount was not answered in time, or the mouse refused it. Sent once more;
    /// then the discovery ends like "no buttons feature": the session is no longer
    /// "initializing" (the Buttons pane stops saying "Checking buttons…") and a receiver
    /// goes on to its next slot. It used to wait for the answer for the whole connection.
    private func controlCountDidFail(slot: UInt8, reason: String) {
        guard let pending = pendingControlCount, pending.slot == slot else { return }
        cancelControlCountWait()
        // A slot is discovered with the cursor on it. If the cursor is elsewhere, that
        // discovery was replaced (a slot picked in the diagnostics window): nothing to end.
        guard deviceIndex == slot else { return }
        if case .sendAgain(let attempt) = Self.controlCountFailureStep(attempt: pending.attempt),
           let idx = featureIndex[Self.featureReprogV4] {
            LogiDebugPanel.log(device: deviceInfo.name, type: .warning, message: "GetControlCount: \(reason), asking again")
            sendGetControlCount(featureIndex: idx, attempt: attempt)
            return
        }
        let message = "GetControlCount: \(reason); this connection goes on without the mouse's Logitech buttons (they work as plain buttons) until it reconnects"
        LogiDebugPanel.log(device: deviceInfo.name, type: .warning, message: message)
        LogiSystemLog.note("\(logTag(slot: slot)) \(message)")
        markHandshakeComplete()
        NotificationCenter.default.post(name: LogiSessionManager.reportingQueryDidCompleteNotification, object: nil)
        LogiSessionManager.shared.recomputeAndNotifyActivityState()
        receiverSlotDiscoveryDidFinish(didDivert: false)
    }

    private func sendGetControlInfo(featureIndex: UInt8, index: Int) {
        LogiDebugPanel.log("[\(deviceInfo.name)] Sending GetControlInfo(\(index))")
        sendRequest(featureIndex: featureIndex, functionId: 1, params: [UInt8(index)])
        scheduleControlInfoTimeout(index: index)
    }

    private func scheduleControlInfoTimeout(index: Int) {
        controlInfoQueryTimer?.invalidate()
        controlInfoQueryTimer = Timer.scheduledTimer(withTimeInterval: Self.reprogQueryTimeout, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            let retryCount = self.controlInfoRetryCounts[index] ?? 0
            if Self.shouldRetryControlInfoTimeout(
                connectionMode: self.connectionMode,
                retryCount: retryCount
            ), let idx = self.featureIndex[Self.featureReprogV4] {
                self.controlInfoRetryCounts[index] = retryCount + 1
                LogiDebugPanel.log(
                    "[\(self.deviceInfo.name)] GetControlInfo[\(index)] timed out, retrying (\(retryCount + 1)/\(Self.bleControlInfoRetryLimit))"
                )
                self.sendGetControlInfo(featureIndex: idx, index: index)
                return
            }

            self.controlInfoRetryCounts.removeValue(forKey: index)
            // 跳过 = 该控件不会进入 discoveredControls, 永远无法 divert / 录制. 以 warning 记录.
            LogiDebugPanel.log(
                device: self.deviceInfo.name,
                type: .warning,
                message: "GetControlInfo[\(index)] timed out, skipping: this control cannot be diverted or recorded until the device reconnects or features are re-discovered"
            )
            self.advanceControlInfoQuery()
        }
    }

    /// 推进 controlInfo 查询 (正常响应 / 错误 / 超时 都调此方法)
    private func advanceControlInfoQuery() {
        controlInfoQueryTimer?.invalidate()
        controlInfoQueryTimer = nil
        controlInfoRetryCounts.removeValue(forKey: reprogQueryIndex)
        reprogQueryIndex += 1
        if reprogQueryIndex < reprogControlCount, let idx = featureIndex[Self.featureReprogV4] {
            sendGetControlInfo(featureIndex: idx, index: reprogQueryIndex)
        } else if !slotIsMouse(deviceIndex) {
            // Not a mouse (a keyboard on the receiver): its discovery ends here.
            finishDiscoveryOfNonMouseSlot()
        } else {
            // ControlInfo 全部获取完毕, 开始逐个查询 reporting 状态
            startReportingQuery()
        }
    }

    /// Whether Scrollio treats a slot as a mouse: over Bluetooth always (only the mouse
    /// interface gets a session), on a receiver when its controls have a left and a right
    /// click (`controlsLookLikeMouse`: the receiver is not asked what its devices are).
    private func slotIsMouse(_ slot: UInt8) -> Bool {
        return connectionMode != .receiver || slotLooksLikeMouse(slot)
    }

    /// A receiver slot whose controls show that it is not a mouse. "Let Scrollio manage this
    /// mouse" and the bindings are about mice: nothing is written to this device. Its
    /// reporting state is not even read (that halves the requests a keyboard gets), no
    /// divert is set or cleared on it (the leftover check used to clear the diverts another
    /// app holds on a keyboard), and it gets no wheel, haptic or settings controller.
    private func finishDiscoveryOfNonMouseSlot() {
        let slot = deviceIndex
        // Remembered only when every control answered: a mouse whose left or right click got
        // lost on the way is looked at again when it reconnects.
        if Self.nonMouseSlotIsRemembered(controlsFound: discoveredControls.count, controlsReported: reprogControlCount) {
            receiverNonMouseSlots.insert(slot)
        }
        divertLedger.forgetDiverts()
        reprogInitComplete = false
        handshakeComplete = true
        setDiscoveryInFlight(false)
        LogiDebugPanel.log("[\(deviceInfo.name)] Slot \(slot) is not a mouse (no left and right click among its \(discoveredControls.count) controls): left alone")
        NotificationCenter.default.post(name: LogiSessionManager.reportingQueryDidCompleteNotification, object: nil)
        LogiSessionManager.shared.recomputeAndNotifyActivityState()
        if receiverSweepActive {
            receiverSlotDiscoveryDidFinish(didDivert: false)
        } else {
            // The diagnostics window asked for this slot: its features are listed (read only).
            probeOptionalFeatures()
            pumpPendingDivertQueue()
        }
    }

    static func nonMouseSlotIsRemembered(controlsFound: Int, controlsReported: Int) -> Bool {
        return controlsReported > 0 && controlsFound >= controlsReported
    }

    private func setControlReporting(featureIndex: UInt8, cid: UInt16, divert: Bool) {
        // The slot's gesture controller picks the flags: the plain divert bytes (0x03 / 0x02)
        // unless raw XY is wanted on this control or has to be cleared from it.
        let flagsByte = gestureController(slot: deviceIndex).reportingFlags(cid: cid, divert: divert)
        sendControlReporting(
            featureIndex: featureIndex,
            cid: cid,
            flagsByte: flagsByte,
            updateLocalState: true,
            debugSource: "setControlReporting"
        )
    }

    private func sendControlReporting(
        featureIndex: UInt8,
        cid: UInt16,
        flagsByte: UInt8,
        updateLocalState: Bool,
        debugSource: String
    ) {
        let params = Self.controlReportingParams(
            connectionMode: connectionMode,
            cid: cid,
            flagsByte: flagsByte
        )
        guard !params.isEmpty else { return }
        let divert = flagsByte & LogiGestureProtocol.flagDivert != 0
        recordPendingSetControlReportingAck(cid: cid, params: params)
        sendRequest(featureIndex: featureIndex, functionId: 3,
                         params: params)
        // The ledger learns of every write: what is diverted, and that whatever
        // GetControlReporting said about this control (or is about to say, for a query
        // already on its way) is older than this write.
        divertLedger.noteWrite(cid: cid, divert: divert, countsAsDiverted: updateLocalState)
        // 方案 B: 不再本地改写 reportingFlags.
        // reportingFlags 永远反映 "GetControlReporting 响应的真值" (设备层状态, Mos 接管前).
        // Mos 自己的 divert 视角由 divertedCIDs 集合唯一表达, 避免污染冲突判定的依据.
        LogiDebugPanel.log("[\(deviceInfo.name)] CID \(String(format: "0x%04X", cid)) divert=\(divert ? "ON" : "OFF")")
        #if DEBUG
        LogiTrace.log(
            "[Session] \(debugSource) cid=\(String(format: "0x%04X", cid)) divert=\(divert) params=\(params.map { String(format: "%02X", $0) }.joined(separator: " ")) localState=\(updateLocalState ? "updated" : "preserved") diverted=\(LogiTrace.cids(divertedCIDs))",
            device: deviceInfo.name
        )
        #endif
    }

    private func recordPendingSetControlReportingAck(cid: UInt16, params: [UInt8]) {
        guard params.count >= 5 else { return }
        let targetCID = (UInt16(params[3]) << 8) | UInt16(params[4])
        // A list per control (LogiPendingReportingAcks): "give back" and "divert" for one
        // control can both be on their way.
        divertLedger.expectAck(cid: cid, flags: params[2], targetCID: targetCID, now: Date())
        #if DEBUG
        LogiTrace.log(
            "[Session] pending SetReporting ACK cid=\(String(format: "0x%04X", cid)) flags=\(String(format: "0x%02X", params[2])) target=\(String(format: "0x%04X", targetCID))",
            device: deviceInfo.name
        )
        #endif
    }

    private func consumePendingSetControlReportingAck(_ ack: SetControlReportingAck) -> Bool {
        let own = divertLedger.consumeAck(cid: ack.cid, flags: ack.flagsByte, targetCID: ack.targetCID, now: Date())
        #if DEBUG
        LogiTrace.log(
            "[Session] SetReporting ACK \(own ? "consumed" : "not ours") cid=\(String(format: "0x%04X", ack.cid)) flags=\(String(format: "0x%02X", ack.flagsByte)) target=\(String(format: "0x%04X", ack.targetCID))",
            device: deviceInfo.name
        )
        #endif
        return own
    }

    private static func controlReportingParams(
        connectionMode: ConnectionMode,
        cid: UInt16,
        divert: Bool
    ) -> [UInt8] {
        // HID++ Xvalid: bit0=divert value, bit1=divert valid.
        let change: LogiGestureProtocol.ReportingChange = divert ? .divert : .undivert
        return controlReportingParams(connectionMode: connectionMode, cid: cid, flagsByte: change.flags)
    }

    /// flagsByte: 见 LogiGestureProtocol.ReportingChange (divert 与 raw XY 的 value/valid 位).
    private static func controlReportingParams(
        connectionMode: ConnectionMode,
        cid: UInt16,
        flagsByte: UInt8
    ) -> [UInt8] {
        switch connectionMode {
        case .bleDirect, .receiver:
            // targetCID=0x0000: 不改变现有 remap 目标; BLE/Bolt 默认保持同一策略.
            return LogiGestureProtocol.reportingParams(cid: cid, flags: flagsByte)
        case .unsupported:
            return []
        }
    }

    #if DEBUG
    internal static func controlReportingParamsForTests(
        connectionMode: ConnectionMode,
        cid: UInt16,
        divert: Bool
    ) -> [UInt8] {
        return controlReportingParams(connectionMode: connectionMode, cid: cid, divert: divert)
    }
    #endif

    // MARK: - Debug Operations (interactive divert control)

    func rediscoverFeatures() {
        cancelInflightDiscovery()
        featureIndex.removeAll()
        featureIndicesFromCache.removeAll()
        featureCacheDropped = false  // a fresh discovery: what it finds may be saved again
        featureDiscoveryTimedOut = false
        resetOptionalProbeState()
        resetHapticDiscoveryState()
        resetScrollForceDiscoveryState()
        resetForceSensingState()
        discoveredControls.removeAll()
        reprogInitComplete = false
        handshakeComplete = false  // 允许 markHandshakeComplete 再次 post sessionChanged 以刷右侧面板
        reprogControlCount = 0
        reprogQueryIndex = 0
        reportingQueryIndex = 0
        controlInfoRetryCounts.removeAll()
        releaseAllActiveButtonState(reason: "rediscover")
        lastApplied.removeAll()
        divertedCIDs.removeAll()
        dropGestureController(slot: deviceIndex)
        LogiDebugPanel.log("[\(deviceInfo.name)] Re-discovering features...")
        setDiscoveryInFlight(true)
        // 复用 startFreshDiscovery 的完整握手流程: 成功走 sendGetControlCount,
        // REPROG 不可用分支会 markHandshakeComplete(), 避免卡在 initializing.
        startFreshDiscovery(tag: "[\(deviceInfo.name)]")
    }

    /// 取消所有正在进行的 discovery/query timer 与 pending callback.
    /// 用途: 用户连续切 slot 或手动 rediscover 时, 防止上一轮响应/超时推进
    /// advance...() 流程, 避免错误把新 target 标为 ready.
    /// 只清 dict 不主动触发 callback(nil): 旧响应到达时找不到 callback 自然被忽略,
    /// 避免触发 markHandshakeComplete 造成 ready→init 的 UI 闪烁.
    private func cancelInflightDiscovery() {
        dropAllPendingDiscoveries()
        controlInfoQueryTimer?.invalidate(); controlInfoQueryTimer = nil
        reportingQueryTimer?.invalidate(); reportingQueryTimer = nil
        cancelControlCountWait()
        controlInfoRetryCounts.removeAll()
        cancelDivertReassertion()
        cancelBLEStandardUndivertGuard()
        forgetPendingAcksOnEverySlot()
    }

    private func forgetPendingAcksOnEverySlot() {
        for slot in Array(slotStates.keys) {
            slotStates[slot]?.ledger.forgetPendingAcks()
        }
    }

    private func cancelDivertReassertion() {
        divertReassertionWorkItem?.cancel()
        divertReassertionWorkItem = nil
    }

    private func cancelBLEStandardUndivertGuard() {
        #if DEBUG
        if bleStandardUndivertGuardWorkItem != nil || !bleStandardUndivertGuardTargets.isEmpty {
            LogiTrace.log("[StandardButtonGuard] cancel generation=\(bleStandardUndivertGuardGeneration) targets=\(LogiTrace.cids(bleStandardUndivertGuardTargets))", device: deviceInfo.name)
        }
        #endif
        bleStandardUndivertGuardGeneration += 1
        bleStandardUndivertGuardWorkItem?.cancel()
        bleStandardUndivertGuardWorkItem = nil
        bleStandardUndivertGuardTargets.removeAll()
        pendingBLEUndivertGuardQueries.removeAll()
    }

    /// The writes below this line that only the diagnostics window asks for (its sliders,
    /// "Play Waveform", "Divert", "Re-Divert", "Undivert All") are refused in a build that
    /// does not offer device writes: a Release build of the window reads and shows.
    private var diagnosticsMayWrite: Bool {
        return HIDPPFeatureActions.offersDeviceWrites
    }

    func redivertAllControls() {
        // The diagnostics window's own write: never in a Release build (diagnosticsMayWrite).
        guard diagnosticsMayWrite else { return }
        releaseAllActiveButtonState(reason: "redivert")
        cancelBLEStandardUndivertGuard()
        reprogInitComplete = true
        divertedCIDs.removeAll()
        lastApplied.removeAll()
        primeFromRegistry()
        LogiDebugPanel.log("[\(deviceInfo.name)] Re-synced divert with bindings")
    }

    func undivertAllControls() {
        // The diagnostics window's own write: never in a Release build (diagnosticsMayWrite).
        guard diagnosticsMayWrite else { return }
        releaseAllActiveButtonState(reason: "undivert all")
        cancelBLEStandardUndivertGuard()
        guard currentReceiverTargetIsConnected else {
            lastApplied.removeAll()
            divertedCIDs.removeAll()
            reprogInitComplete = false
            LogiDebugPanel.log("[\(deviceInfo.name)] Cleared local divert state; receiver target disconnected")
            return
        }
        guard let idx = featureIndex[Self.featureReprogV4] else {
            lastApplied.removeAll()
            reprogInitComplete = false
            LogiDebugPanel.log("[\(deviceInfo.name)] Cleared local divert state; REPROG feature unavailable")
            return
        }
        for cid in divertedCIDs {
            setControlReporting(featureIndex: idx, cid: cid, divert: false)
        }
        lastApplied.removeAll()
        reprogInitComplete = false
        LogiDebugPanel.log("[\(deviceInfo.name)] Undiverted all controls")
    }

    func toggleDivert(cid: UInt16) {
        // The diagnostics window's own write: never in a Release build (diagnosticsMayWrite).
        guard diagnosticsMayWrite else { return }
        guard let idx = featureIndex[Self.featureReprogV4] else { return }
        guard currentReceiverTargetIsConnected else { return }
        let currentlyDiverted = divertedCIDs.contains(cid)
        setControlReporting(featureIndex: idx, cid: cid, divert: !currentlyDiverted)
    }

    // MARK: - Receiver Slot Targeting

    /// 切换目标 slot (debug 面板交互/自动选择)
    func setTargetSlot(slot: UInt8) {
        guard connectionMode == .receiver, slot >= 1, slot <= 6 else { return }
        // 手动/主动 target 覆盖启动时的默认巡检游标选择, 取消 pending 的自动选择,
        // 防止 device-info 到齐/超时后的回调覆盖此次显式选择.
        pendingInitialTargetSelection = false
        cancelInflightDiscovery()
        deviceIndex = slot
        receiverOptionalProbedSlots.remove(slot)  // 完整重发现 -> 可选功能允许重探
        receiverNonMouseSlots.remove(slot)        // picked by hand: looked at again
        // 重置 feature 状态, 等待新一轮 discovery
        featureIndex.removeAll()
        resetOptionalProbeState()  // 新 slot 是另一台设备, 探测守卫与所有缓存状态必须清零
        resetHapticDiscoveryState()
        resetScrollForceDiscoveryState()
        resetForceSensingState()
        discoveredControls.removeAll()
        reprogInitComplete = false
        handshakeComplete = false  // 允许 markHandshakeComplete 再次 post, 使 sidebar/panels 刷新回 loading/ready 切换
        reprogControlCount = 0
        reprogQueryIndex = 0
        reportingQueryIndex = 0
        releaseAllActiveButtonState(reason: "target slot changed")
        lastApplied.removeAll()
        divertedCIDs.removeAll()
        dropGestureController(slot: slot)
        setDiscoveryInFlight(true)
        LogiDebugPanel.log("[\(deviceInfo.name)] Target slot changed to \(slot)")
    }

    /// 面板巡检切换: slot 已发现过且当前空闲时, 只切游标 + 刷新可选功能上下文, 不重跑 REPROG 发现
    /// (控件已缓存在 slotState). 否则回退完整 setTargetSlot + rediscoverFeatures.
    /// 接管已由 sweep 常驻, 点击只为"看哪个 slot 的 features", 无需重发现.
    func inspectSlot(_ slot: UInt8) {
        guard connectionMode == .receiver, slot >= 1, slot <= 6 else { return }
        // 判"是否已发现过"用 discoveredControls 而非 reprogInitComplete: 非鼠标 slot(键盘)
        // 被排除出接管集时 reprogInitComplete 置了 false, 但其控件已发现过、可直接读缓存.
        // 关键: idle 不参与"轻/重"决策 —— 已发现的 slot 永远走轻量, 即使此刻正好有别的 slot
        // 的可选功能探测在飞(否则会每次撞上探测链而误判成"需重发现"). idle 只用来门控本次探测.
        let discovered = !(slotStates[slot]?.discoveredControls.isEmpty ?? true)
        guard discovered else {
            setTargetSlot(slot: slot)
            rediscoverFeatures()
            return
        }
        // 轻量切换: 控件已缓存, 只切游标读缓存, 永不重跑 REPROG.
        pendingInitialTargetSelection = false
        deviceIndex = slot
        setDiscoveryInFlight(false)
        // 可选功能每个 slot 只探一次, 且仅在空闲时(避免每次切都重探; 本接收器 getFeature 可能
        // 超时, 重探会拖慢并让后续点击撞上在飞探测). 未探过 + 空闲才 reset+探.
        let idle = !receiverSweepActive && pendingDiscovery.isEmpty
            && controlInfoQueryTimer == nil && reportingQueryTimer == nil
        if idle && !receiverOptionalProbedSlots.contains(slot) {
            receiverOptionalProbedSlots.insert(slot)
            resetOptionalProbeState()
            resetHapticDiscoveryState()
            resetScrollForceDiscoveryState()
            resetForceSensingState()
            probeOptionalFeatures()
        }
        LogiDebugPanel.log("[\(deviceInfo.name)] Inspecting slot \(slot) (cached, no REPROG rediscover)")
        NotificationCenter.default.post(name: LogiSessionManager.sessionChangedNotification, object: nil)
    }

    /// The diagnostics window was closed. If it left the cursor on a device that is not a
    /// mouse (a keyboard's row was picked), the cursor goes back to a mouse: what follows
    /// the cursor (the re-read of the buttons' state, an action a gesture runs) is about
    /// the mouse. Nothing is sent.
    func endSlotInspection() {
        let idle = !receiverSweepActive && pendingDiscovery.isEmpty && pendingControlCount == nil
            && controlInfoQueryTimer == nil && reportingQueryTimer == nil
        guard connectionMode == .receiver,
              let slot = Self.cursorAfterInspection(
                  cursor: deviceIndex,
                  cursorIsMouse: slotIsMouse(deviceIndex),
                  mouseSlots: receiverManagedSlots.sorted().filter { slotLooksLikeMouse($0) },
                  idle: idle
              ) else { return }
        deviceIndex = slot
        LogiDebugPanel.log("[\(deviceInfo.name)] Diagnostics closed: cursor back on the mouse in slot \(slot)")
    }

    /// Where the cursor goes when the diagnostics window closes; nil: it stays. It only
    /// moves off a device that is not a mouse, onto the lowest slot that holds one, and
    /// never in the middle of a discovery (a slot is discovered with the cursor on it).
    static func cursorAfterInspection(cursor: UInt8, cursorIsMouse: Bool, mouseSlots: [UInt8], idle: Bool) -> UInt8? {
        guard idle, !cursorIsMouse, let mouse = mouseSlots.min(), mouse != cursor else { return nil }
        return mouse
    }

    // MARK: - Receiver Device Enumeration

    /// 枚举 receiver 上的配对设备 (ping 所有 slot + 查询设备信息)
    func enumerateReceiverDevices() {
        guard connectionMode == .receiver else { return }
        receiverPairedDevices = (1...6).map { ReceiverPairedDevice(slot: UInt8($0)) }
        pendingSlotPings.removeAll()
        slotPingAttempts.removeAll()
        slotPingTimeout?.cancel()
        slotPingTimeout = nil
        receiverEnumPhase = 1
        LogiDebugPanel.log("[\(deviceInfo.name)] Enumerating receiver slots 1-6...")
        // The receiver's connection reports first, then the slots: so nothing connects
        // unseen between a slot's ping and the moment the reports are on.
        switchOnReceiverConnectionReports()
    }

    // MARK: - The receiver's connection reports (register 0x00)

    /// Reads the receiver's reporting flags and switches "wireless notifications" on when
    /// they are off; the slot pings follow (why: LogiReceiverConnectionReports). The flag
    /// stays on at teardown: another program may count on it, and it changes nothing for
    /// the devices.
    private func switchOnReceiverConnectionReports() {
        connectionReports.start()
        connectionReportsGate?.cancel()
        let gate = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.carryOut(self.connectionReports.waitedLongEnough())
        }
        connectionReportsGate = gate
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.connectionReportsWait, execute: gate)
        sendReceiverRegisterGet(register: Self.receiverReportingFlags, isLong: false)
    }

    private func carryOut(_ step: LogiReceiverConnectionReports.Step) {
        switch step {
        case .nothing:
            break
        case .write(let value):
            sendReceiverRegisterSet(register: Self.receiverReportingFlags, value: value)
        case .pingSlots(let outcome):
            noteConnectionReports(outcome)
            sendSlotPings()
        case .note(let outcome):
            noteConnectionReports(outcome)
        }
    }

    private func noteConnectionReports(_ outcome: String) {
        let message = "Receiver connection reports: \(outcome)"
        LogiDebugPanel.log("[\(deviceInfo.name)] \(message)")
        LogiSystemLog.note("\(sessionLogTag) \(message)")
    }

    /// The slot pings of an enumeration, when the exchange about the connection reports
    /// says so (it says so once).
    private func sendSlotPings() {
        connectionReportsGate?.cancel()
        connectionReportsGate = nil
        guard connectionMode == .receiver, receiverEnumPhase == 1 else { return }

        for slot: UInt8 in 1...6 {
            slotPingAttempts[slot] = 1
            pingReceiverSlot(slot)
        }

        // 超时: 5秒后自动完成 ping 阶段
        let timeout = DispatchWorkItem { [weak self] in
            guard let self = self, self.receiverEnumPhase == 1 else { return }
            // 未响应的 slot 标记为未连接 (a slot the receiver was busy for keeps "Busy")
            for slot in self.pendingSlotPings {
                if let idx = self.receiverPairedDevices.firstIndex(where: { $0.slot == slot }),
                   self.receiverPairedDevices[idx].lastError == nil {
                    self.receiverPairedDevices[idx].lastError = "Timeout"
                }
            }
            self.pendingSlotPings.removeAll()
            self.finishPingPhase()
        }
        slotPingTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.slotPingPhaseTimeout, execute: timeout)
    }

    /// Ping 特定 receiver slot (发送 IRoot.Ping)
    func pingReceiverSlot(_ slot: UInt8) {
        guard connectionMode == .receiver else { return }

        // HID++ 2.0 IRoot.Ping via short report
        // [0x10, devIdx, 0x00(IRoot), 0x1A(func=1,swId=0x0A), 0x00, 0x00, slot(pingData)]
        var report = [UInt8](repeating: 0, count: 7)
        report[0] = Self.hidppShortReportId
        report[1] = slot
        report[2] = 0x00  // IRoot feature index
        report[3] = 0x1A  // function=1(ping), swId=0x0A
        report[4] = 0x00
        report[5] = 0x00
        report[6] = slot  // ping data for matching

        pendingSlotPings.insert(slot)

        let hex = report.map { String(format: "%02X", $0) }.joined(separator: " ")
        LogiDebugPanel.log(device: deviceInfo.name, type: .tx, message: "TX: \(hex)",
                                  decoded: "IRoot.Ping(slot=\(slot))")
        queueReport(report, .ping(slot: slot))
    }

    /// 查询 receiver slot 的设备信息 (register 0xB5)
    func queryReceiverDeviceInfo(slot: UInt8) {
        guard connectionMode == .receiver else { return }
        let entityIdx = slot - 1  // register 0xB5 使用 0-based index

        // 查询设备类型和 wireless PID
        sendReceiverRegisterGet(register: Self.receiverPairingInfo, isLong: true,
                                params: [entityIdx, Self.pairingInfoDeviceInfo])

        // 延迟 100ms 查询设备名称 (避免请求堆积)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.sendReceiverRegisterGet(register: Self.receiverPairingInfo, isLong: true,
                                          params: [entityIdx, Self.pairingInfoDeviceName])
        }
    }

    /// 发送 HID++ 1.0 register GET 请求 (target: receiver 0xFF)
    private func sendReceiverRegisterGet(register: UInt8, isLong: Bool, params: [UInt8] = []) {
        var report: [UInt8]
        let subId: UInt8

        if isLong {
            report = [UInt8](repeating: 0, count: 20)
            report[0] = Self.hidppLongReportId
            subId = Self.hidpp10GetLongRegister
        } else {
            report = [UInt8](repeating: 0, count: 7)
            report[0] = Self.hidppShortReportId
            subId = Self.hidpp10GetRegister
        }

        report[1] = 0xFF  // receiver device index
        report[2] = subId
        report[3] = register
        for (i, p) in params.enumerated() {
            if 4 + i < report.count { report[4 + i] = p }
        }

        let hex = report.prefix(min(report.count, 20)).map { String(format: "%02X", $0) }.joined(separator: " ")
        let regName = register == Self.receiverPairingInfo ? "PairingInfo" : "0x\(String(format: "%02X", register))"
        let paramsHex = params.map { String(format: "%02X", $0) }.joined(separator: " ")
        LogiDebugPanel.log(device: deviceInfo.name, type: .tx, message: "TX: \(hex)",
                                  decoded: "\(isLong ? "GET_LONG" : "GET")_REGISTER(\(regName), [\(paramsHex)])")
        queueReport(report, .receiverRegister(register, long: isLong))
    }

    /// HID++ 1.0 register SET on the receiver itself (a short register: three value bytes).
    private func sendReceiverRegisterSet(register: UInt8, value: [UInt8]) {
        var report = [UInt8](repeating: 0, count: 7)
        report[0] = Self.hidppShortReportId
        report[1] = 0xFF  // receiver device index
        report[2] = Self.hidpp10SetRegister
        report[3] = register
        for (i, byte) in value.prefix(3).enumerated() {
            report[4 + i] = byte
        }

        let hex = report.map { String(format: "%02X", $0) }.joined(separator: " ")
        let valueHex = value.prefix(3).map { String(format: "%02X", $0) }.joined(separator: " ")
        LogiDebugPanel.log(device: deviceInfo.name, type: .tx, message: "TX: \(hex)",
                                  decoded: "SET_REGISTER(0x\(String(format: "%02X", register)), [\(valueHex)])")
        queueReport(report, .receiverRegisterWrite(register))
    }

    // MARK: - Receiver Response Handlers

    /// 处理 HID++ 1.0 错误响应 (sub-ID 0x8F)
    private func handleHIDPP10Error(_ report: UnsafeBufferPointer<UInt8>) {
        let devIdx = report[1]
        let errorCode = report.count > 5 ? report[5] : 0

        let hidpp10ErrorNames: [UInt8: String] = [
            0x00: "Success", 0x01: "InvalidSubID", 0x02: "InvalidAddress",
            0x03: "InvalidValue", 0x04: "ConnectFailed", 0x05: "TooManyDevices",
            0x06: "AlreadyExists", 0x07: "Busy", 0x08: "UnknownDevice",
            0x09: "ResourceError", 0x0A: "RequestUnavailable", 0x0B: "InvalidParamValue",
        ]
        let errorName = hidpp10ErrorNames[errorCode] ?? "0x\(String(format: "%02X", errorCode))"

        // 更新 receiver slot 状态 (如果是 ping 错误). Only an error that names the ping: one
        // for another request to the slot (another program's, say) is not the ping's answer.
        if devIdx >= 1 && devIdx <= 6 && pendingSlotPings.contains(devIdx), report.count > 4,
           Self.hidpp10ErrorAnswersSlotPing(refusedSubId: report[3], refusedAddress: report[4]) {
            let slotIndex = receiverPairedDevices.firstIndex(where: { $0.slot == devIdx })
            switch Self.slotPingErrorStep(errorCode: errorCode, attempt: slotPingAttempts[devIdx] ?? 1) {
            case .askAgain(let attempt):
                // The slot stays pending and is pinged again a moment later, when the
                // receiver has passed on the message it was busy with.
                slotPingAttempts[devIdx] = attempt
                if let idx = slotIndex {
                    receiverPairedDevices[idx].lastError = errorName
                }
                LogiDebugPanel.log(device: deviceInfo.name, type: .info,
                    message: "Slot \(devIdx): receiver busy, ping \(attempt) of \(Self.slotPingAttemptLimit) follows")
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.slotPingRetryDelay) { [weak self] in
                    guard let self = self, self.receiverEnumPhase == 1,
                          self.pendingSlotPings.contains(devIdx) else { return }
                    self.pingReceiverSlot(devIdx)
                }
            case .notConnected:
                pendingSlotPings.remove(devIdx)
                if let idx = slotIndex {
                    receiverPairedDevices[idx].isConnected = false
                    receiverPairedDevices[idx].lastError = errorName
                }
                checkPingPhaseComplete()
            }
        }

        // The receiver refused the read or the write of its own reporting flags.
        if devIdx == 0xFF, report.count > 4, report[4] == Self.receiverReportingFlags,
           report[3] == Self.hidpp10GetRegister || report[3] == Self.hidpp10SetRegister {
            carryOut(connectionReports.refused(errorName: errorName))
        }

        // GetControlCount of this app refused for the slot being discovered (the device went
        // out of range): the same as no answer, without waiting for the timeout.
        if report.count > 4, pendingControlCount?.slot == devIdx,
           let reprogIdx = slotStates[devIdx]?.featureIndex[Self.featureReprogV4],
           report[3] == reprogIdx, report[4] == Self.hidppSoftwareId {
            controlCountDidFail(slot: devIdx, reason: "HID++ 1.0 error \(errorName)")
        }

        // A getFeature of this app refused for this slot (e.g. the device is out of range):
        // only the oldest request to that slot fails. Errors for other requests (the slot
        // pings, the receiver's own registers at 0xFF) leave the discoveries alone.
        if report.count > 4,
           let entry = pendingDiscovery.takeRefused(
               deviceIndex: devIdx,
               originalFeatureIndex: report[3],
               originalFunctionByte: report[4]
           ) {
            finishDiscovery(entry, featureIndex: nil)
        }
    }

    /// 处理 ping 响应 (device slot 回复 IRoot.Ping)
    private func handleSlotPingResponse(devIdx: UInt8, report: UnsafeBufferPointer<UInt8>) {
        pendingSlotPings.remove(devIdx)
        let protMajor = report[4]
        let protMinor = report[5]

        if let idx = receiverPairedDevices.firstIndex(where: { $0.slot == devIdx }) {
            receiverPairedDevices[idx].isConnected = true
            receiverPairedDevices[idx].protocolMajor = protMajor
            receiverPairedDevices[idx].protocolMinor = protMinor
            receiverPairedDevices[idx].lastError = nil
        }

        LogiDebugPanel.log(device: deviceInfo.name, type: .info,
            message: "Slot \(devIdx): device connected (HID++ \(protMajor).\(protMinor))")
        checkPingPhaseComplete()
    }

    /// 检查 ping 阶段是否完成
    private func checkPingPhaseComplete() {
        guard pendingSlotPings.isEmpty && receiverEnumPhase == 1 else { return }
        finishPingPhase()
    }

    /// 完成 ping 阶段, 进入 info 查询阶段
    private func finishPingPhase() {
        slotPingTimeout?.cancel()
        slotPingTimeout = nil
        receiverEnumPhase = 2
        let connectedSlots = receiverPairedDevices.filter { $0.isConnected }
        LogiDebugPanel.log("[\(deviceInfo.name)] Ping complete: \(connectedSlots.count)/6 slots connected")
        // What was found, in the system log: "my mouse is not seen" can then be read from
        // a log the user sends, without the diagnostics window.
        LogiSystemLog.note("\(sessionLogTag) Receiver slots: \(Self.receiverSlotsSummary(receiverPairedDevices))")

        guard !connectedSlots.isEmpty else {
            receiverEnumPhase = 0
            // Nothing is connected, so nothing that was queued while the slots were pinged
            // can be discovered.
            if !receiverSweepActive {
                pendingDivertSlots.removeAll()
            }
            LogiDebugPanel.log("[\(deviceInfo.name)] No devices found on receiver")
            // 无设备 -> 不会进 peripheral discovery, 此处必须清 inflight 防止 spinner 一直转.
            setDiscoveryInFlight(false)
            // Receiver dongle 本身的握手 = slot ping 完成.
            handshakeComplete = true
            NotificationCenter.default.post(name: LogiSessionManager.sessionChangedNotification, object: nil)
            return
        }

        // Left as it was, because no receiver was at hand to try a change on: these requests
        // very likely do not have the format a Unifying or a Bolt receiver reads (the
        // review of 2026-11-12 found in Solaar one parameter byte, 0x20 + n - 1 or 0x50 + n;
        // these ask for sub-registers 0x00 to 0x05), so the kind and the name of a device
        // probably never arrive and the selection below waits its 1.5 s. Nothing depends on
        // the answers any more: what a slot holds is told from its controls
        // (controlsLookLikeMouse) and a mouse's name is read from the mouse itself (feature
        // 0x0005, requestDeviceNameIfNeeded). With a receiver on the desk: if the diagnostics
        // log never shows "Slot N info", delete the requests and the wait.
        // 查询已连接设备的详细信息 (register 0xB5, 可能在 Bolt receiver 上失败).
        // 巡检游标默认选择需要 deviceType 才能 prefer-mouse, 因此推迟到 device-info 到齐
        // (或超时) 后再选一次, 避免像旧逻辑那样锁到编号最低的 slot (可能是键盘/另一只鼠标).
        pendingInitialTargetSelection = true
        pendingDeviceInfoSlots = Set(connectedSlots.map { $0.slot })
        for dev in connectedSlots {
            queryReceiverDeviceInfo(slot: dev.slot)
        }

        // 超时兜底: device-info 始终不回 (如 Bolt register 失败) 时,
        // chooseReceiverTargetSlot 在无类型信息下回退首个在线 slot, 不退化.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.initialTargetSelectionTimeout) { [weak self] in
            guard let self = self, self.pendingInitialTargetSelection else { return }
            LogiDebugPanel.log("[\(self.deviceInfo.name)] Device-info wait timed out; selecting target with known types")
            self.selectInitialReceiverTargetAndDiscover()
        }

        // Receiver dongle 本身的握手 = slot ping 完成. discovery 保持 inflight 直到选定 target.
        handshakeComplete = true
        NotificationCenter.default.post(name: LogiSessionManager.sessionChangedNotification, object: nil)
    }

    /// device-info 到齐或超时后, 选定巡检游标并启动 feature discovery (只执行一次).
    private func selectInitialReceiverTargetAndDiscover() {
        guard pendingInitialTargetSelection else { return }
        pendingInitialTargetSelection = false
        pendingDeviceInfoSlots.removeAll()

        guard let inspectionSlot = Self.chooseReceiverTargetSlot(devices: receiverPairedDevices) else {
            // 选择窗口内全部断开 -> 无目标, 清 inflight 防止 spinner 卡住.
            receiverEnumPhase = 0
            // Nothing is connected, so nothing that was queued while the choice was pending
            // can be discovered (as in finishPingPhase).
            if !receiverSweepActive {
                pendingDivertSlots.removeAll()
            }
            LogiDebugPanel.log("[\(deviceInfo.name)] No connected devices at target selection")
            setDiscoveryInFlight(false)
            NotificationCenter.default.post(name: LogiSessionManager.sessionChangedNotification, object: nil)
            return
        }

        // 接管集合: 已连接 + 像鼠标的 slot 各自 discovery 常驻接管, 与有无按键绑定无关
        // (Mouse pane / battery / managed values 也需要它); 绑定只决定 applyUsage divert 什么.
        let divertSlots = Self.receiverTakeoverSlots(devices: receiverPairedDevices)

        // 巡检 slot 始终发现(面板要显示其 features)且排最后, 让路由游标最终停靠它;
        // 其余接管 slot 在前, 只做 discovery+divert, 不做可选功能探测(§4.3).
        receiverInspectionSlot = inspectionSlot
        var queue = divertSlots.filter { $0 != inspectionSlot }
        queue.append(inspectionSlot)

        let selected = receiverPairedDevices.first(where: { $0.slot == inspectionSlot })
        LogiDebugPanel.log("[\(deviceInfo.name)] Takeover sweep: divert=\(divertSlots) inspection=\(inspectionSlot)(\(selected?.deviceTypeName ?? "--")) queue=\(queue)")
        startReceiverDivertSweep(queue: queue)
        NotificationCenter.default.post(name: LogiSessionManager.sessionChangedNotification, object: nil)
    }

    // MARK: - Receiver Divert Sweep (§3.1 串行逐 slot 发现)

    /// 启动接管 sweep: 逐 slot 串行 discovery+divert. 一次只发现一个 slot,
    /// 满足 IRoot 发现响应不带 featureId 的串行约束(§3.1).
    private func startReceiverDivertSweep(queue: [UInt8]) {
        receiverSweepActive = true
        pendingDivertSlots = queue
        discoverNextSweepSlot()
    }

    /// 取队首 slot 开始其 discovery; 队空则收尾.
    private func discoverNextSweepSlot() {
        guard !pendingDivertSlots.isEmpty else {
            finishReceiverSweep()
            return
        }
        let slot = pendingDivertSlots.removeFirst()
        deviceIndex = slot
        receiverSweptSlots.insert(slot)
        receiverOptionalProbedSlots.remove(slot)  // 全新发现 -> 可选功能允许重探
        // 全新发现: 清该 slot 的 per-slot 发现状态(startup 本为默认, 显式清以支持 Phase 4 重扫).
        featureIndex.removeAll()
        dropWheelController(slot: slot)
        dropGestureController(slot: slot)
        dropMouseBasicsController(slot: slot)
        discoveredControls.removeAll()
        reprogInitComplete = false
        reprogControlCount = 0
        reprogQueryIndex = 0
        reportingQueryIndex = 0
        controlInfoRetryCounts.removeAll()
        setDiscoveryInFlight(true)
        let selected = receiverPairedDevices.first(where: { $0.slot == slot })
        let tag = "[\(deviceInfo.name):slot\(slot)]"
        LogiDebugPanel.log("\(tag) Sweep discovery (\(selected?.deviceTypeName ?? "--")); \(pendingDivertSlots.count) slot(s) queued after")
        startFreshDiscovery(tag: tag)
    }

    /// 单 slot discovery 走到终点(divert 成功 / 无 REPROG / 0 控件)时调用.
    /// 巡检 slot 完成时探测其可选功能(§4.3, 与队列顺序无关); 队列还有 slot 则发现下一个,
    /// 否则收尾. 手动 rediscover(sweep 未激活)不进此路径. 全部离散事件驱动, 无周期活动.
    private func receiverSlotDiscoveryDidFinish(didDivert: Bool) {
        // 非 sweep 发现终点(无 REPROG / 0 控件的手动 rediscover)也要排空热插拔队列.
        guard receiverSweepActive else { pumpPendingDivertQueue(); return }
        let slot = deviceIndex
        // 防快速切换(flap)竞态: 若该 slot 在发现过程中已断开, 不标记 managed, 否则重连时会被
        // "已 managed -> ignore" 挡住而不再重新 divert. 断开后重连会由 0x41 重新触发 takeover.
        let stillConnected = receiverPairedDevices.first(where: { $0.slot == slot })?.isConnected ?? false
        if didDivert && stillConnected {
            // 只接管像鼠标的 slot (有标准 Left/Right 点击); 键盘/数字键盘/演示器不进接管集 (计划 §8).
            // 类型不可知的接收器上据实际发现的控件判定. 非鼠标撤销 applyUsage 可能下发的 divert,
            // 恢复其原生功能 (通常 divertedCIDs 为空, 即无操作).
            if slotLooksLikeMouse(slot) {
                receiverManagedSlots.insert(slot)
            } else {
                undivertCurrentSlotControls(reason: "not a mouse")
            }
        }
        if !pendingDivertSlots.isEmpty {
            discoverNextSweepSlot()
        } else {
            finishReceiverSweep()
        }
    }

    /// 撤销当前游标 slot 上已下发的 divert, 恢复其原生功能. 用于把非鼠标 slot 排除出接管集.
    private func undivertCurrentSlotControls(reason: String) {
        let toUndivert = divertedCIDs
        if let idx = featureIndex[Self.featureReprogV4] {
            for cid in toUndivert {
                setControlReporting(featureIndex: idx, cid: cid, divert: false)
            }
        }
        lastApplied.removeAll()
        divertedCIDs.removeAll()
        reprogInitComplete = false
        if !toUndivert.isEmpty {
            LogiDebugPanel.log("[\(deviceInfo.name)] Slot \(deviceIndex) excluded from takeover (\(reason)); undiverted \(toUndivert.count) control(s)")
        }
    }

    /// 该 slot 已发现的控件是否像鼠标: 有标准 Left(0x50)+Right(0x51)点击, 键盘没有.
    private func slotLooksLikeMouse(_ slot: UInt8) -> Bool {
        guard let controls = slotStates[slot]?.discoveredControls else { return false }
        return Self.controlsLookLikeMouse(cids: Set(controls.map { $0.cid }))
    }

    /// 纯判定: 一组已发现的 CID 是否像鼠标. 用于类型不可知的接收器(寄存器 0xB5 返 InvalidSubID,
    /// deviceType 恒为 0): sweep 后据实际控件把巡检游标落到真正的鼠标, 无需额外 HID++ 流量.
    static func controlsLookLikeMouse(cids: Set<UInt16>) -> Bool {
        return cids.contains(0x0050) && cids.contains(0x0051)  // Left + Right click
    }

    /// After a takeover sweep: the slot whose wheel, haptic and basic features are looked up
    /// again and whose controllers are built anew. That is the cursor slot, and only when
    /// this sweep rediscovered it (which dropped its controllers). A sweep of another slot
    /// (a keyboard waking on the same receiver) leaves the cursor's controllers alone:
    /// starting them again would read and write its wheel and basic values again. nil while
    /// the optional probe has not run yet (it builds them at the end of its chain).
    static func receiverSweepRebuildSlot(cursor: UInt8, sweptSlots: Set<UInt8>, probeAlreadyRan: Bool) -> UInt8? {
        guard probeAlreadyRan, sweptSlots.contains(cursor) else { return nil }
        return cursor
    }

    private func finishReceiverSweep() {
        receiverSweepActive = false
        // 巡检游标: 优先落到真正的鼠标(据发现的控件判定, 键盘无 Left/Right); 无鼠标回退预选 slot.
        // 修类型不可知接收器上"游标回退到键盘, 面板默认显示键盘"的问题.
        let mouseSlot = receiverManagedSlots.sorted().first(where: { slotLooksLikeMouse($0) })
        deviceIndex = mouseSlot ?? receiverInspectionSlot ?? deviceIndex
        // 在最终巡检的那台(鼠标)探测可选功能(haptic/scrollForce 等). 移到此处(而非逐 slot)
        // 才能只探测巡检的鼠标而非 sweep 最后一个 slot. probeOptionalFeatures 自带 once 守卫.
        let probeAlreadyRan = optionalProbeSent
        let sweptSlots = receiverSweptSlots
        receiverSweptSlots.removeAll()
        // Only a mouse is asked for its optional features here. With no mouse on the
        // receiver the cursor rests on another device (a keyboard): that one is asked only
        // when the user picks it in the diagnostics window (inspectSlot).
        let cursorIsMouse = slotIsMouse(deviceIndex)
        if cursorIsMouse {
            receiverOptionalProbedSlots.insert(deviceIndex)  // 巡检游标那台已探, inspectSlot 不重探
            probeOptionalFeatures()
        }
        if cursorIsMouse, let slot = Self.receiverSweepRebuildSlot(
            cursor: deviceIndex, sweptSlots: sweptSlots, probeAlreadyRan: probeAlreadyRan
        ) {
            // 热插拔重连: 探测链不会再跑 (once 守卫), 但该 slot 的 featureIndex 已被清空.
            // 按需补发现滚轮 feature, 让托管设置在重连后重放.
            // 同理补发现 haptic feature (手势触觉提示), 排在滚轮之后保持 getFeature 串行.
            // Then the basic settings (battery, DPI, press force), still one getFeature at a time.
            // Only for the cursor slot when this sweep rediscovered it: a keyboard waking on
            // the same receiver must not make the mouse's values be read and written again.
            discoverWheelFeatureIfNeeded(slot: slot) { [weak self] in
                self?.discoverGestureHapticFeatureIfNeeded(slot: slot) { [weak self] in
                    self?.discoverMouseBasicsFeaturesIfNeeded(slot: slot)
                }
            }
        }
        LogiDebugPanel.log("[\(deviceInfo.name)] Takeover sweep complete: managed=\(receiverManagedSlots.sorted()) cursor=\(deviceIndex)\(mouseSlot != nil ? " (mouse)" : "")")
        LogiSystemLog.note("\(sessionLogTag) \(Self.receiverSweepLine(mouseSlots: receiverManagedSlots.sorted()))")
        NotificationCenter.default.post(name: LogiSessionManager.sessionChangedNotification, object: nil)
        // sweep 结束后再排空一次: 消费其间因 0x41 新入队的 slot.
        pumpPendingDivertQueue()
    }

    /// The slot (1...6) a pairing-information answer names by its 0-based index; nil for
    /// anything else.
    static func pairingInfoSlot(entityIndex: UInt8) -> UInt8? {
        return entityIndex < 6 ? entityIndex + 1 : nil
    }

    /// 处理 receiver register 响应
    private func handleReceiverRegisterResponse(_ report: UnsafeBufferPointer<UInt8>) {
        let register = report[3]

        if register == Self.receiverReportingFlags && report[2] == Self.hidpp10GetRegister {
            carryOut(connectionReports.flagsRead([report[4], report[5], report[6]]))
            return
        }

        if register == Self.receiverPairingInfo {
            let entityIdx = report[4]  // 0-based
            let infoType = report[5]
            // A byte of the report: checked before it is counted with. 0xFF + 1 trapped
            // here, and any program that reads this register (Solaar, Logi Options+) can
            // make the receiver send such an answer.
            guard let slot = Self.pairingInfoSlot(entityIndex: entityIdx) else { return }

            guard let idx = receiverPairedDevices.firstIndex(where: { $0.slot == slot }) else { return }

            if infoType == Self.pairingInfoDeviceInfo && report.count > 10 {
                // [entityIdx, 0x20, destId, reportInterval, wirelessPID_hi, wirelessPID_lo, deviceType, ...]
                receiverPairedDevices[idx].wirelessPID = (UInt16(report[8]) << 8) | UInt16(report[9])
                receiverPairedDevices[idx].deviceType = report[10]
                LogiDebugPanel.log(device: deviceInfo.name, type: .info,
                    message: "Slot \(slot) info: type=\(receiverPairedDevices[idx].deviceTypeName) wirelessPID=\(String(format: "0x%04X", receiverPairedDevices[idx].wirelessPID))")
                // 巡检游标默认选择等待 device-info: 该 slot 类型已知, 若全部到齐则立即选定.
                if pendingInitialTargetSelection {
                    pendingDeviceInfoSlots.remove(slot)
                    if pendingDeviceInfoSlots.isEmpty {
                        selectInitialReceiverTargetAndDiscover()
                    }
                }
            } else if infoType == Self.pairingInfoDeviceName && report.count > 7 {
                // [entityIdx, 0x40, nameLen, char0, char1, ...]
                let nameLen = min(Int(report[6]), report.count - 7)
                if nameLen > 0 {
                    let nameBytes = Array(report[7..<(7 + nameLen)])
                    receiverPairedDevices[idx].name = String(bytes: nameBytes, encoding: .utf8) ?? ""
                    LogiDebugPanel.log(device: deviceInfo.name, type: .info,
                        message: "Slot \(slot) name: \"\(receiverPairedDevices[idx].name)\"")
                }
            }

            NotificationCenter.default.post(name: LogiSessionManager.sessionChangedNotification, object: nil)
        }
    }

    /// 处理设备连接/断开通知 (sub-ID 0x41)
    private func handleDeviceConnectionNotification(_ report: UnsafeBufferPointer<UInt8>) {
        let devIdx = report[1]
        let protocolType = report.count > 3 ? report[3] : 0
        let devInfo = report.count > 4 ? report[4] : 0
        let connected = (devInfo & 0x40) == 0  // bit 6 = 0: link established

        LogiDebugPanel.log(device: deviceInfo.name, type: .info,
            message: "Device \(connected ? "connected" : "disconnected") on slot \(devIdx) (protocol=\(String(format: "0x%02X", protocolType)))")

        if devIdx >= 1 && devIdx <= 6 {
            applyReceiverSlotLink(slot: devIdx, connected: connected, source: "the receiver says so")
        }
    }

    /// Device disconnection (sub-ID 0x40): the device was taken off the receiver. The
    /// notification used to be taken for a report of the device itself, which marked an
    /// offline slot as connected and had it discovered.
    private func handleDeviceDisconnectionNotification(slot: UInt8) {
        LogiDebugPanel.log(device: deviceInfo.name, type: .info,
            message: "Device taken off the receiver in slot \(slot)")
        applyReceiverSlotLink(slot: slot, connected: false, source: "taken off the receiver")
    }

    /// A slot (1...6) connected or disconnected, as the receiver reports it.
    private func applyReceiverSlotLink(slot devIdx: UInt8, connected: Bool, source: String) {
        let wasConnected = receiverPairedDevices.first(where: { $0.slot == devIdx })?.isConnected
        if let idx = receiverPairedDevices.firstIndex(where: { $0.slot == devIdx }) {
            receiverPairedDevices[idx].isConnected = connected
        } else {
            // 自动追加 (如果枚举尚未运行)
            var dev = ReceiverPairedDevice(slot: devIdx)
            dev.isConnected = connected
            receiverPairedDevices.append(dev)
            receiverPairedDevices.sort { $0.slot < $1.slot }
        }
        if wasConnected != connected {
            LogiSystemLog.note("\(logTag(slot: devIdx)) \(connected ? "Connected" : "Disconnected") (\(source))")
        }
        // A slot that disconnected does not wait for a discovery any more.
        pendingDivertSlots = Self.receiverTakeoverQueue(pendingDivertSlots, afterLinkOf: devIdx, connected: connected)

        // 多设备热插拔(Phase 4): 每个 slot 的 0x41 各自决策, 不再单目标抢占式 retarget.
        // Taken over whatever the bindings say (they only decide what applyUsage diverts).
        let dev = receiverPairedDevices.first(where: { $0.slot == devIdx })
        let isDivertCandidate = Self.receiverSlotIsTakeoverCandidate(
            connected: connected, deviceType: dev?.deviceType ?? 0,
            knownNotAMouse: receiverNonMouseSlots.contains(devIdx)
        )
        let action = Self.receiverSlotConnectionAction(
            slot: devIdx,
            connected: connected,
            isDivertCandidate: isDivertCandidate,
            alreadyManaged: receiverManagedSlots.contains(devIdx)
        )
        LogiDebugPanel.log(
            "[\(deviceInfo.name)] SlotConnection slot=\(devIdx) connected=\(connected) candidate=\(isDivertCandidate) managed=\(receiverManagedSlots.contains(devIdx)) -> \(action)"
        )

        switch action {
        case .ignore:
            break
        case .takeover(let slot):
            scheduleReceiverSlotTakeover(slot: slot)
        case .release(let slot):
            cancelReceiverSlotTakeoverDebounce(slot: slot)
            handleReceiverSlotRelease(slot: slot)
        }
        NotificationCenter.default.post(name: LogiSessionManager.sessionChangedNotification, object: nil)
    }

    /// 初始枚举时设备可能仍在休眠且之后不补发 0x41. 第一条真实 peripheral 报文将 slot
    /// 标记为在线并直接复用现有 takeover 队列; 已在线 slot 的后续报文不会重复触发.
    private func handleReceiverPeripheralActivity(slot: UInt8) -> Bool {
        guard slot >= 1 && slot <= 6, handshakeComplete, receiverEnumPhase != 1 else { return false }

        guard let idx = receiverPairedDevices.firstIndex(where: { $0.slot == slot }) else { return false }
        let wasConnected = receiverPairedDevices[idx].isConnected
        guard !wasConnected else { return false }

        receiverPairedDevices[idx].isConnected = true
        receiverPairedDevices[idx].lastError = nil

        let device = receiverPairedDevices.first(where: { $0.slot == slot })
        let isDivertCandidate = Self.receiverSlotIsTakeoverCandidate(
            connected: true, deviceType: device?.deviceType ?? 0,
            knownNotAMouse: receiverNonMouseSlots.contains(slot)
        )
        let action = Self.receiverPeripheralActivityAction(
            slot: slot,
            wasConnected: wasConnected,
            isDivertCandidate: isDivertCandidate,
            alreadyManaged: receiverManagedSlots.contains(slot)
        )
        LogiDebugPanel.log(
            "[\(deviceInfo.name)] Inferred slot \(slot) connection from peripheral activity; candidate=\(isDivertCandidate) -> \(action)"
        )
        LogiSystemLog.note("\(logTag(slot: slot)) Connected (its first report; the receiver had not said so)")
        NotificationCenter.default.post(name: LogiSessionManager.sessionChangedNotification, object: nil)

        if case .takeover(let takeoverSlot) = action {
            scheduleReceiverSlotTakeover(slot: takeoverSlot)
            return true
        }
        return false
    }

    /// 去抖调度 takeover: 每次 0x41 连接重置定时器, 该 slot 稳定在线 debounce 窗口后才真正接管.
    /// 疯狂快切期间连接/断开成对到达, 定时器被反复取消, 一次发现都不触发.
    private func scheduleReceiverSlotTakeover(slot: UInt8) {
        receiverTakeoverDebounce[slot]?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.receiverTakeoverDebounce[slot] = nil
            // 去抖窗口结束时仍在线且仍未接管才真正 takeover.
            let connected = self.receiverPairedDevices.first(where: { $0.slot == slot })?.isConnected ?? false
            guard connected, !self.receiverManagedSlots.contains(slot) else { return }
            self.handleReceiverSlotTakeover(slot: slot)
        }
        receiverTakeoverDebounce[slot] = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.receiverTakeoverDebounceDelay, execute: item)
    }

    private func cancelReceiverSlotTakeoverDebounce(slot: UInt8) {
        receiverTakeoverDebounce[slot]?.cancel()
        receiverTakeoverDebounce[slot] = nil
    }

    /// 某接管 slot 断开: 只释放该 slot 的按键状态并标记未 init, 不动别的 slot.
    private func handleReceiverSlotRelease(slot: UInt8) {
        receiverManagedSlots.remove(slot)
        pendingDivertSlots.removeAll { $0 == slot }
        // scoped 到该 slot 释放其 per-slot 状态 (buttonStateTracker/divertedCIDs/lastApplied 均按 slot).
        let saved = deviceIndex
        deviceIndex = slot
        releaseAllActiveButtonState(reason: "slot \(slot) disconnected")
        reprogInitComplete = false
        lastApplied.removeAll()
        divertedCIDs.removeAll()
        deviceIndex = saved
        dropWheelController(slot: slot)
        dropGestureController(slot: slot)
        dropMouseBasicsController(slot: slot)
        LogiDebugPanel.log("[\(deviceInfo.name)] Slot \(slot) disconnected; released takeover state (managed=\(receiverManagedSlots.sorted()))")
    }

    /// 某 divert 候选 slot(重新)连接: 入接管队列并尝试排空.
    private func handleReceiverSlotTakeover(slot: UInt8) {
        // 已排队 / 正在发现该 slot -> 不重复. A slot that is queued already is not queued twice,
        // but the queue is looked at again: an entry that was held while the first choice of
        // slots was pending, and that nothing came back for, used to keep its slot from
        // ever being discovered (every later reconnect ended here).
        if pendingDivertSlots.contains(slot) {
            pumpPendingDivertQueue()
            return
        }
        if receiverSweepActive && deviceIndex == slot { return }
        pendingDivertSlots.append(slot)
        LogiDebugPanel.log("[\(deviceInfo.name)] Slot \(slot) (re)connected; queued for takeover")
        pumpPendingDivertQueue()
    }

    /// 排空接管队列: 若有待接管 slot 且当前无发现在飞, 起 sweep 逐个消费(§3.1 串行).
    /// 必须在每个发现/上报查询终点调用, 保证热插拔期间入队的 slot 最终一定被处理 ——
    /// 不能只靠 receiverSweepActive, 否则"入队时正好有非 sweep 发现在飞"的 slot 会被永久搁置
    /// (真机复现: mx4 重连时被 queued 后从未 discovery, 拇指键退回原生鼠标键).
    private func pumpPendingDivertQueue() {
        guard !receiverSweepActive, !pendingDivertSlots.isEmpty else { return }
        // Held until the first choice of slots was made: it discovers every connected slot
        // itself (a slot queued here is connected, so it is among them).
        guard Self.receiverTakeoverMayStart(
            enumPhase: receiverEnumPhase, awaitingFirstSelection: pendingInitialTargetSelection
        ) else { return }
        // getFeature 在飞用 pendingDiscovery(权威集)判定, 不用超时 timer ——
        // 旧的共享 discoveryTimer 曾因完成后漏置 nil 变成"已失效但非 nil"永远误判在飞, 把 pump 毒死(见 29f3bd1).
        let anyDiscoveryInFlight = !pendingDiscovery.isEmpty
            || controlInfoQueryTimer != nil || reportingQueryTimer != nil
        guard !anyDiscoveryInFlight else { return }
        LogiDebugPanel.log("[\(deviceInfo.name)] Draining takeover queue \(pendingDivertSlots)")
        receiverSweepActive = true
        discoverNextSweepSlot()
    }

    // MARK: - Report Decoding (for debug panel)

    private func decodeRequest(featureIndex: UInt8, functionId: UInt8, params: [UInt8]) -> String {
        if featureIndex == 0x00 && functionId == 0 && params.count >= 2 {
            let featId = (UInt16(params[0]) << 8) | UInt16(params[1])
            let name = HIDPPInfo.featureNames[featId]?.0 ?? "0x\(String(format: "%04X", featId))"
            return "IRoot.GetFeature(\(name))"
        }
        if featureIndex == 0x00 && functionId == 1 {
            return "IRoot.Ping (GetProtocolVersion)"
        }
        if let reprogIdx = self.featureIndex[Self.featureReprogV4], featureIndex == reprogIdx {
            switch functionId {
            case 0: return "REPROG.GetControlCount()"
            case 1:
                let idx = params.first.map { "\($0)" } ?? "?"
                return "REPROG.GetControlInfo(index=\(idx))"
            case 2:
                if params.count >= 2 {
                    let cid = (UInt16(params[0]) << 8) | UInt16(params[1])
                    return "REPROG.GetControlReporting(CID=\(String(format: "0x%04X", cid)) \(LogiCIDDirectory.name(forCID: cid)))"
                }
                return "REPROG.GetControlReporting"
            case 3:
                if params.count >= 3 {
                    let cid = (UInt16(params[0]) << 8) | UInt16(params[1])
                    let cidName = LogiCIDDirectory.name(forCID: cid)
                    let divert = params[2] & 0x01 != 0
                    return "REPROG.SetControlReporting(CID=\(String(format: "0x%04X", cid)) \(cidName), divert=\(divert ? "ON" : "OFF")\(Self.rawXYDescription(flagsByte: params[2])))"
                }
                return "REPROG.SetControlReporting"
            default: return "REPROG.func\(functionId)"
            }
        }
        if let hapticIdx = self.featureIndex[Self.featureHaptic], featureIndex == hapticIdx {
            switch functionId {
            case 0: return "HAPTIC.GetCapabilities()"
            case 1: return "HAPTIC.GetState()"
            case 2:
                if params.count >= 2 {
                    return "HAPTIC.SetState(\(params[0] & 0x01 != 0 ? "on" : "off"), level=\(params[1]))"
                }
                return "HAPTIC.SetState"
            case 4:
                let name = params.first.flatMap { id in
                    HIDPPInfo.hapticWaveforms.first(where: { $0.id == id })?.name
                } ?? "?"
                return "HAPTIC.PlayWaveform(\(name))"
            default: return "HAPTIC.func\(functionId)"
            }
        }
        return "Feature[0x\(String(format: "%02X", featureIndex))].func\(functionId)"
    }

    /// The flags of a GetControlReporting answer in words, for the diagnostics log. Bit 2
    /// is the persistent divert and bit 4 raw XY (they used to be shown as "tmpRemap" and
    /// not at all); a bit without a known meaning is shown by its value.
    static func reportingFlagNames(_ flags: UInt8) -> [String] {
        let names: [(UInt8, String)] = [
            (0x01, "divert"), (0x04, "persistDivert"), (0x10, "rawXY"), (0x40, "forceRawXY"),
        ]
        var parts = names.filter { flags & $0.0 != 0 }.map { $0.1 }
        let unknown = flags & ~names.reduce(0) { $0 | $1.0 }
        if unknown != 0 { parts.append(String(format: "0x%02X", unknown)) }
        return parts
    }

    /// ", rawXY=ON/OFF" when the flags byte states the raw XY bit, else nothing.
    private static func rawXYDescription(flagsByte: UInt8) -> String {
        guard flagsByte & LogiGestureProtocol.flagRawXYValid != 0 else { return "" }
        return flagsByte & LogiGestureProtocol.flagRawXY != 0 ? ", rawXY=ON" : ", rawXY=OFF"
    }

    private func decodeReport(_ report: UnsafeBufferPointer<UInt8>) -> String {
        guard report.count >= 7 else { return "short report" }
        let devIdx = report[1]
        let featIdx = report[2]
        let funcId = report[3] >> 4
        let softwareId = report[3] & 0x0F

        // HID++ 1.0 error (sub-ID 0x8F)
        if connectionMode == .receiver && featIdx == Self.hidpp10ErrorMsg {
            let errorSubId = report[3]
            let errorCode = report.count > 5 ? report[5] : 0
            let hidpp10ErrNames: [UInt8: String] = [
                0x01: "InvalidSubID", 0x02: "InvalidAddress", 0x03: "InvalidValue",
                0x04: "ConnectFailed", 0x05: "TooManyDevices", 0x06: "AlreadyExists",
                0x07: "Busy", 0x08: "UnknownDevice", 0x09: "ResourceError",
            ]
            let errName = hidpp10ErrNames[errorCode] ?? "0x\(String(format: "%02X", errorCode))"
            return "HID++ 1.0 ERROR: dev=\(String(format: "0x%02X", devIdx)) subId=\(String(format: "0x%02X", errorSubId)) err=\(errName)"
        }

        // HID++ 1.0 register response from receiver
        if connectionMode == .receiver && devIdx == 0xFF &&
           (featIdx == Self.hidpp10GetRegister || featIdx == Self.hidpp10GetLongRegister) {
            let regAddr = report[3]
            let regName: String
            switch regAddr {
            case Self.receiverPairingInfo: regName = "PairingInfo"
            case 0x00: regName = "Notifications"
            case 0x02: regName = "ConnectionState"
            default: regName = "0x\(String(format: "%02X", regAddr))"
            }
            return "Register \(featIdx == Self.hidpp10GetLongRegister ? "GET_LONG" : "GET"): \(regName)"
        }

        if connectionMode == .receiver && devIdx == 0xFF && featIdx == Self.hidpp10SetRegister {
            return "Register SET taken: \(report[3] == Self.receiverReportingFlags ? "Notifications" : "0x\(String(format: "%02X", report[3]))")"
        }

        if connectionMode == .receiver, let slot = Self.receiverDisconnectionSlot(report) {
            return "DeviceDisconnection: slot=\(slot) taken off the receiver"
        }

        // Device connection notification (sub-ID 0x41)
        if connectionMode == .receiver && featIdx == Self.hidpp10DeviceConnection {
            let devInfo = report.count > 4 ? report[4] : 0
            let connected = (devInfo & 0x40) == 0
            return "DeviceConnection: slot=\(devIdx) \(connected ? "CONNECTED" : "DISCONNECTED")"
        }

        if featIdx == Self.hidppErrorFeatureIdx {
            let errCode = report.count > 6 ? report[6] : 0
            let errName = HIDPPInfo.errorNames[errCode] ?? "0x\(String(format: "%02X", errCode))"
            return "HID++ ERROR: \(errName)"
        }
        if featIdx == 0x00 {
            if funcId == 0 {
                let idx = report[4]
                return idx == 0 ? "IRoot: feature not found" : "IRoot: feature at index 0x\(String(format: "%02X", idx))"
            }
            if funcId == 1 {
                return "IRoot: protocol \(report[4]).\(report[5])"
            }
        }
        if let reprogIdx = featureIndex[Self.featureReprogV4], featIdx == reprogIdx {
            if funcId == 0 && softwareId == 0x00 {
                var cids: [String] = []
                var offset = 4
                while offset + 1 < report.count {
                    let cid = (UInt16(report[offset]) << 8) | UInt16(report[offset + 1])
                    if cid == 0 { break }
                    let name = LogiCIDDirectory.name(forCID: cid)
                    cids.append("\(String(format: "0x%04X", cid))(\(name))")
                    offset += 2
                }
                return cids.isEmpty ? "BUTTON EVENT: all released" : "BUTTON EVENT: \(cids.joined(separator: " + "))"
            }
            if funcId == 0 && softwareId == 0x01 {
                return reprogInitComplete
                    ? "REPROG.ControlCount response = \(report[4])"
                    : "REPROG.ControlCount = \(report[4])"
            }
            if !reprogInitComplete && funcId == 0 {
                return "REPROG.func0 swid=\(softwareId) ignored during init"
            }
            if let delta = LogiGestureProtocol.rawXYDelta(report) {
                return "RAW XY: dx=\(delta.deltaX) dy=\(delta.deltaY)"
            }
            if funcId == 1 {
                let cid = (UInt16(report[4]) << 8) | UInt16(report[5])
                let name = LogiCIDDirectory.name(forCID: cid)
                return "REPROG.ControlInfo: CID=\(String(format: "0x%04X", cid)) (\(name))"
            }
            if funcId == 2 && report.count >= 9 {
                let cid = (UInt16(report[4]) << 8) | UInt16(report[5])
                let rFlags = report[6]
                let tCID = (UInt16(report[7]) << 8) | UInt16(report[8])
                let cidName = LogiCIDDirectory.name(forCID: cid)
                let parts = Self.reportingFlagNames(rFlags)
                let fStr = parts.isEmpty ? "none" : parts.joined(separator: ",")
                let tStr = tCID != cid && tCID != 0 ? " -> \(LogiCIDDirectory.name(forCID: tCID))" : ""
                return "REPROG.GetReporting(\(cidName)): \(fStr)\(tStr)"
            }
            if funcId == 3 {
                if let ack = Self.parseSetControlReportingAck(report) {
                    let cidName = LogiCIDDirectory.name(forCID: ack.cid)
                    let divert = ack.temporaryDivertEnabled ? "ON" : "OFF"
                    return "REPROG.SetControlReporting ACK: CID=\(String(format: "0x%04X", ack.cid)) (\(cidName)) divert=\(divert)\(Self.rawXYDescription(flagsByte: ack.flagsByte))"
                }
                return "REPROG.SetControlReporting ACK"
            }
        }
        // Haptic responses
        if let hapticIdx = featureIndex[Self.featureHaptic], featIdx == hapticIdx {
            switch funcId {
            case 0:
                if let mask = Self.parseHapticCapabilitiesMask(report) {
                    let count = HIDPPInfo.hapticWaveforms.filter { (mask >> UInt32($0.id)) & 1 != 0 }.count
                    return "HAPTIC.Capabilities: \(count) waveforms, mask=0x\(String(format: "%08X", mask))"
                }
                return "HAPTIC.Capabilities"
            case 1:
                if let s = Self.parseHapticState(report) {
                    return "HAPTIC.State: \(s.enabled ? "on" : "off"), level=\(s.level)\(s.fourLevelsOnly ? " (4-level)" : "")"
                }
                return "HAPTIC.State"
            case 2: return "HAPTIC.SetState ACK"
            case 4: return "HAPTIC.PlayWaveform ACK"
            default: return "HAPTIC.func\(funcId) response"
            }
        }
        // Scroll Force (0x2111) responses
        if let sfIdx = featureIndex[Self.featureSmartShiftEnhanced], featIdx == sfIdx {
            switch funcId {
            case 0:
                if let tunable = Self.parseScrollForceTunableTorque(report) {
                    return "ScrollForce.Capabilities: tunable torque \(tunable ? "yes" : "no")"
                }
                return "ScrollForce.Capabilities"
            case 1:
                if let status = Self.parseScrollForceStatus(report) {
                    return "ScrollForce.Status: mode=\(status.mode), torque=\(status.torque)"
                }
                return "ScrollForce.Status"
            case 2: return "ScrollForce.SetState ACK"
            default: return "ScrollForce.func\(funcId) response"
            }
        }
        // Force Sensing (0x19C0) responses
        if let fsIdx = featureIndex[Self.featureForceSensing], featIdx == fsIdx {
            switch funcId {
            case 0: return "ForceSensing.ButtonCount"
            case 1:
                if let info = Self.parseForceSensingInfo(report) {
                    return "ForceSensing.Info: changeable=\(info.changeable), range=\(info.minValue)-\(info.maxValue), default=\(info.defaultValue)"
                }
                return "ForceSensing.Info"
            case 2:
                if let current = Self.parseForceSensingCurrent(report) {
                    return "ForceSensing.Current: \(current)"
                }
                return "ForceSensing.Current"
            case 3: return "ForceSensing.SetConfig ACK"
            default: return "ForceSensing.func\(funcId) response"
            }
        }

        // SmartShift or other feature notifications
        if let name = findFeatureName(forIndex: featIdx) {
            return "\(name) notification (func=\(funcId))"
        }
        return "Feature[0x\(String(format: "%02X", featIdx))].func\(funcId)"
    }

    private func findFeatureName(forIndex idx: UInt8) -> String? {
        for (featId, featIdx) in featureIndex {
            if featIdx == idx {
                return HIDPPInfo.featureNames[featId]?.0
            }
        }
        return nil
    }

    // MARK: - Logi Action Execution

    private var pendingDPICycle: (featureIndex: UInt8, direction: Direction)? = nil
    private var pendingDPIListQuery: (featureIndex: UInt8, direction: Direction)? = nil
    private var dpiSteps: [UInt16] = []  // 从设备查询, 不硬编码 (LogiPointerSpeedProtocol.parseDPIList)
    /// The button actions that read before they write, and until when each may still run
    /// (LogiPendingActions): an answer that comes later than that runs nothing.
    private var pendingActions = LogiPendingActions()

    /// SmartShift 切换 (free-spin <-> ratchet, 保留阈值与 torque).
    /// 走滚轮控制器: 0x2111 (MX Master 4 只有它) 读 fn1 写 fn2, 0x2110 读 fn0 写 fn1.
    func executeSmartShiftToggle() {
        let slot = deviceIndex
        if let wheel = wheelControllers[slot] {
            wheel.toggleMode()
            return
        }
        discoverWheelFeatureIfNeeded(slot: slot) { [weak self] in
            guard let self = self else { return }
            guard let wheel = self.wheelControllers[slot] else {
                LogiDebugPanel.log("[\(self.deviceInfo.name)] SmartShift feature not supported (no 0x2110 / 0x2111)")
                return
            }
            wheel.toggleMode()
        }
    }

    /// DPI 循环
    func executeDPICycle(direction: Direction) {
        let dpiFeatureId = Self.featureAdjustableDPI
        if let idx = featureIndex[dpiFeatureId] {
            cycleDPI(featureIndex: idx, direction: direction)
        } else {
            discoverFeature(featureId: dpiFeatureId) { [weak self] idx in
                guard let self = self, let idx = idx else {
                    LogiDebugPanel.log("[\(self?.deviceInfo.name ?? "?")] AdjustableDPI feature not supported")
                    return
                }
                self.featureIndex[dpiFeatureId] = idx
                self.cycleDPI(featureIndex: idx, direction: direction)
            }
        }
    }

    private func cycleDPI(featureIndex: UInt8, direction: Direction) {
        if dpiSteps.isEmpty {
            // 先查询设备支持的 DPI 列表
            // getSensorDpiList: function 1, param sensorIdx=0
            // 响应: byte[4]=sensorIdx, byte[5-6]=dpiStep, byte[7-8]=dpi1, byte[9-10]=dpi2, ...
            // 如果 dpiStep > 0: 范围模式 (min~max, 步进 dpiStep)
            // 如果 dpiStep == 0: 列表中的每个值都是一个档位
            sendRequest(featureIndex: featureIndex, functionId: 1, params: [0x00])
            pendingDPIListQuery = (featureIndex, direction)
            pendingActions.arm(.dpiList, now: Date())
        } else {
            // 已有 DPI 列表, 直接查询当前值并切换
            // getSensorDpi: function 2, param sensorIdx=0
            sendRequest(featureIndex: featureIndex, functionId: 2, params: [0x00])
            pendingDPICycle = (featureIndex, direction)
            pendingActions.arm(.dpiCurrent, now: Date())
        }
    }

    // MARK: - ChangeHost

    /// 切换到指定主机 (0-based index)
    func executeChangeHost(hostIndex: UInt8) {
        let changeHostFeatureId: UInt16 = 0x1814
        if let idx = featureIndex[changeHostFeatureId] {
            switchToHost(featureIndex: idx, hostIndex: hostIndex)
        } else {
            discoverFeature(featureId: changeHostFeatureId) { [weak self] idx in
                guard let self = self, let idx = idx else {
                    LogiDebugPanel.log("[\(self?.deviceInfo.name ?? "?")] ChangeHost feature not supported")
                    return
                }
                self.featureIndex[changeHostFeatureId] = idx
                self.switchToHost(featureIndex: idx, hostIndex: hostIndex)
            }
        }
    }

    /// One system-log line for a write a Logitech button action makes. These actions write
    /// whatever "Let Scrollio manage this mouse" says (the user pressed the button for it),
    /// like the SmartShift Toggle, which the wheel controller logs.
    private func noteActionWrite(_ what: String) {
        let managed = LogiSessionManager.shared.mouseManaged ? "on" : "off"
        LogiSystemLog.note("\(logTag(slot: deviceIndex)) Button action: \(what) (manage switch \(managed))")
    }

    private func switchToHost(featureIndex: UInt8, hostIndex: UInt8) {
        LogiDebugPanel.log("[\(deviceInfo.name)] Switching to host \(hostIndex + 1)")
        noteActionWrite("Easy-Switch to host \(hostIndex + 1)")
        // setHost: function 1, param = target host index (0-based)
        sendRequest(featureIndex: featureIndex, functionId: 1, params: [hostIndex])
        // 注意: 切换后设备会断开连接, session 会被清理
    }

    // MARK: - Pointer Speed Action
    //
    // "Toggle Hi-Res Scrolling", "Invert Scrolling" and "Toggle Thumb Wheel" are gone
    // (LogiButtonAction). Each flipped a state of the mouse (0x2121 wheel mode, 0x2150 thumb
    // wheel reporting) that nothing in Scrollio showed, and nothing put it back when
    // Scrollio paused or quit: "Toggle Thumb Wheel" diverted the thumb wheel to HID++,
    // where nobody listens, so the wheel stayed dead until the mouse was switched off and
    // on. A stored binding that names one of them does nothing.

    /// 指针速度循环 (0.5x → 1x → 1.5x → 2x → 0.5x)
    private func executePointerSpeedCycle() {
        if let idx = featureIndex[Self.featurePointerSpeed] {
            pendingActions.arm(.pointerSpeed, now: Date())
            sendRequest(featureIndex: idx, functionId: 0, params: [])  // getPointerSpeed
        } else {
            discoverFeature(featureId: Self.featurePointerSpeed) { [weak self] idx in
                guard let self = self, let idx = idx else {
                    self?.showFeatureNotAvailable(.pointerSpeed)
                    return
                }
                self.featureIndex[Self.featurePointerSpeed] = idx
                self.pendingActions.arm(.pointerSpeed, now: Date())
                self.sendRequest(featureIndex: idx, functionId: 0, params: [])
            }
        }
    }

    // MARK: - Haptic (0x19B0)

    /// Haptic state / capabilities 响应抵达或本地缓存更新时发出. object = 本 session.
    static let hapticStateDidChangeNotification = Notification.Name("LogiHapticStateDidChange")

    struct HapticState: Equatable {
        let enabled: Bool
        let level: UInt8          // 0-100
        let fourLevelsOnly: Bool  // 设备仅支持 Off/25/50/75/100 五档
    }

    /// 最近一次 GetState (fn1) 解析结果; 未查询过为 nil
    private(set) var hapticState: HapticState? = nil
    /// The same answer with the whole flags byte, so the diagnostics slider can write from it.
    private var hapticRawState: LogiHapticSettingsProtocol.State? = nil
    /// GetCapabilities (fn0) 返回的波形支持位掩码 (bit n = waveform ID n); 未查询过为 nil
    private(set) var hapticWaveformMask: UInt32? = nil

    var debugHapticState: HapticState? { hapticState }
    var debugHapticWaveformMask: UInt32? { hapticWaveformMask }

    // MARK: - Optional Feature Probing (串行)

    /// 面板可选功能探测清单. 前三个有专属 context (haptic / scroll force / force sensing),
    /// 其余仅需在 FEATURES 表列出 + 命名/通用 action. 顺序无关紧要, 但必须逐个串行探测.
    private static let optionalProbeFeatures: [UInt16] = [
        featureDeviceNameType,     // 0x0005 (查权威设备类型, 见 probeNextOptionalFeature)
        featureHaptic,             // 0x19B0
        featureSmartShiftEnhanced, // 0x2111
        featureSmartShift,         // 0x2110 (MX Master 3S 等无 0x2111 的滚轮)
        featureHiResWheel,         // 0x2121 (ratchetSwitch 事件: 模式切换键)
        featureForceSensing,       // 0x19C0
        featureUnifiedBattery,     // 0x1004 (battery for the Mouse tab)
        featureBatteryStatus,      // 0x1000 (original MX Master 3; skipped when 0x1004 exists)
        featureAdjustableDPI,      // 0x2201 (pointer speed for the Mouse tab)
        0x8060, 0x8061,            // Report Rate / Extended Report Rate
        0x2202,                    // Extended Adjustable DPI
        0x2001,                    // Left/Right Swap
        0x2006,                    // Pointer Axis Orientation
        0x2130,                    // LowRes Wheel
        0x2230,                    // Angle Snapping
        0x2240,                    // Surface Tuning
        0x2250, 0x2251,            // XY Stats / Wheel Stats
        0x1010,                    // Charging Control
        0x1802,                    // Device Reset
        0x1C00,                    // Persistent Remappable Action
        0x8100,                    // Onboard Profiles
    ]
    private var optionalProbeSent = false
    private var optionalProbeIndex = 0

    #if DEBUG
    internal static var optionalProbeFeaturesForTests: [UInt16] { optionalProbeFeatures }
    #endif

    /// 握手完成后探测一批可选 feature, 让 Debug 面板 FEATURES 表能列出它们.
    /// 串行 (一次一个): IRoot getFeature 响应不带 featureId, 按请求顺序匹配 pendingDiscovery
    /// (LogiFeatureDiscoveryQueue); 一次一个让丢失的响应只影响它自己那一项.
    private func probeOptionalFeatures() {
        guard !optionalProbeSent else { return }
        optionalProbeSent = true
        optionalProbeIndex = 0
        probeNextOptionalFeature()
    }

    private func probeNextOptionalFeature() {
        while optionalProbeIndex < Self.optionalProbeFeatures.count {
            let fid = Self.optionalProbeFeatures[optionalProbeIndex]
            optionalProbeIndex += 1
            // One battery feature is enough: 0x1000 is only looked for without 0x1004.
            if fid == Self.featureBatteryStatus, featureIndex[Self.featureUnifiedBattery] != nil,
               featureIndex[fid] == nil {
                continue
            }
            if featureIndex[fid] != nil {
                // 缓存已含: 无需探测, 直接发对应通知让 UI 补行/建 context, 继续下一个
                postOptionalFeatureNotification(fid)
                if fid == Self.featureDeviceNameType {
                    requestDeviceTypeIfNeeded()
                    requestDeviceNameIfNeeded()
                }
                continue
            }
            discoverFeature(featureId: fid) { [weak self] idx in
                guard let self = self else { return }
                if let idx = idx {
                    self.featureIndex[fid] = idx
                    self.saveFeatureIndexCache()
                    LogiDebugPanel.log("[\(self.deviceInfo.name)] feature \(String(format: "0x%04X", fid)) at index \(String(format: "0x%02X", idx))")
                    self.postOptionalFeatureNotification(fid)
                    if fid == Self.featureDeviceNameType {
                        self.requestDeviceTypeIfNeeded()
                        self.requestDeviceNameIfNeeded()
                    }
                }
                self.probeNextOptionalFeature()  // 串行: 本次 discovery 完成后再发下一个
            }
            return
        }
        // 可选功能探测链走完(pendingDiscovery 此刻已空): 建立滚轮控制器 (读状态, 托管时写入).
        // 放在链尾而非发现 0x2111 时: 避免滚轮读写与后续 getFeature 交错.
        // Only for a mouse: a keyboard that is alone on a receiver has a battery feature too,
        // and used to appear in the Mouse pane and the menu as a mouse.
        if slotIsMouse(deviceIndex) {
            resolveWheelController(slot: deviceIndex)
            resolveGestureHaptics(slot: deviceIndex)
            resolveMouseBasicsController(slot: deviceIndex)
        }
        // 排空热插拔期间入队的 slot.
        // 探测链较长(~18 个 feature, 含超时), 期间设备重连很常见, 必须在此排空避免搁置.
        pumpPendingDivertQueue()
    }

    /// 当前巡检 slot 的权威类型(0x0005)未知时, 发 getDeviceType(fn2). 响应在 handleInputReport 解析.
    /// fire-and-forget: getDeviceType 是 fn2 响应, 不占用 getFeature 的 pendingDiscovery, 不阻塞探测链.
    /// 纯显示用, 不影响接管/divert(那条路径用 slotLooksLikeMouse 的控件判定).
    private func requestDeviceTypeIfNeeded() {
        guard connectionMode == .receiver,
              let idx = featureIndex[Self.featureDeviceNameType] else { return }
        let slot = deviceIndex
        guard let devIdx = receiverPairedDevices.firstIndex(where: { $0.slot == slot }),
              receiverPairedDevices[devIdx].hidppDeviceType == nil else { return }
        sendRequest(featureIndex: idx, functionId: 2)  // getDeviceType
    }

    /// 每个 feature 发现后发对应通知: 有专属 context 的走各自通知 (面板据此补行 + 建 context),
    /// 其余统一走 auxiliary 通知 (面板仅刷新 FEATURES 表).
    private func postOptionalFeatureNotification(_ fid: UInt16) {
        switch fid {
        case Self.featureHaptic:
            NotificationCenter.default.post(name: Self.hapticStateDidChangeNotification, object: self)
        case Self.featureSmartShiftEnhanced:
            NotificationCenter.default.post(name: Self.scrollForceStateDidChangeNotification, object: self)
        case Self.featureForceSensing:
            NotificationCenter.default.post(name: Self.forceSensingStateDidChangeNotification, object: self)
        default:
            NotificationCenter.default.post(name: Self.auxiliaryFeaturesDidChangeNotification, object: self)
        }
    }

    private func resetOptionalProbeState() {
        optionalProbeSent = false
        optionalProbeIndex = 0
    }

    /// 查询 capabilities (fn0) + 当前状态 (fn1); 响应在 handleInputReport 解析后发通知
    func hapticRefreshInfo() {
        withHapticFeature { [weak self] idx in
            self?.sendRequest(featureIndex: idx, functionId: 0)
            self?.sendRequest(featureIndex: idx, functionId: 1)
        }
    }

    /// 播放固件预置波形 (fn4). 波形内容 (时长/频率) 由固件内置, 协议无参数可调.
    func hapticPlay(waveformId: UInt8) {
        // The diagnostics window's own write: never in a Release build (diagnosticsMayWrite).
        guard diagnosticsMayWrite else { return }
        withHapticFeature { [weak self] idx in
            self?.sendRequest(featureIndex: idx, functionId: 4, params: [waveformId])
        }
    }

    /// Diagnostics strength slider (fn2 setState, the mouse's global state; 0 = off). Built
    /// from the last state read: only the on bit changes, so power saving and unknown flags
    /// survive, and 0 switches off without touching the strength. (It used to send Solaar's
    /// [0x01, level] / [0x00, 0x32], which cleared power saving and reset the strength.)
    /// Without a state read nothing is written: the state is read instead. Read back after.
    func hapticSetLevel(_ level: UInt8) {
        // The diagnostics window's own write: never in a Release build (diagnosticsMayWrite).
        guard diagnosticsMayWrite else { return }
        guard let current = hapticRawState else {
            LogiDebugPanel.log("[\(deviceInfo.name)] HAPTIC: state unknown, reading it before any write")
            hapticRefreshInfo()
            return
        }
        let params = Self.hapticSetLevelParams(level, current: current)
        withHapticFeature { [weak self] idx in
            guard let self = self else { return }
            self.sendRequest(featureIndex: idx, functionId: 2, params: params)
            self.sendRequest(featureIndex: idx, functionId: 1)
        }
    }

    /// fn0 GetCapabilities 响应: payload[4..7] = 波形支持位掩码 (BE), 即 report bytes [8..11]
    private static func parseHapticCapabilitiesMask(_ report: UnsafeBufferPointer<UInt8>) -> UInt32? {
        guard report.count >= 12 else { return nil }
        return (UInt32(report[8]) << 24) | (UInt32(report[9]) << 16)
             | (UInt32(report[10]) << 8) | UInt32(report[11])
    }

    /// fn1 GetState 响应 (LogiHapticSettingsProtocol): byte[4] bit0 = 开关, byte[5] = 强度 0-100,
    /// byte[6] = levels (bit0 = 四档设备, an assumption from Solaar)
    private static func parseHapticState(_ report: UnsafeBufferPointer<UInt8>) -> HapticState? {
        guard report.count >= 7, let state = LogiHapticSettingsProtocol.parseState(Array(report)) else { return nil }
        return HapticState(
            enabled: state.isOn,
            level: state.strength,
            fourLevelsOnly: LogiHapticSettingsProtocol.hasFewLevels(levelsByte: state.levelsByte) ?? false
        )
    }

    /// fn2 SetState parameters of the diagnostics slider: level 0 switches off and keeps the
    /// strength, any other level switches on at that strength; other flags stay as read.
    static func hapticSetLevelParams(_ level: UInt8, current: LogiHapticSettingsProtocol.State) -> [UInt8] {
        return LogiHapticSettingsProtocol.setStateParams(
            readFlags: current.flags,
            readStrength: current.strength,
            on: level > 0,
            strength: level > 0 ? Int(level) : nil
        )
    }

    /// rediscover / 切 slot 会清空 featureIndex, haptic 的探测守卫与缓存状态必须一并复位,
    /// 否则 Haptic 行永久消失 (probe 不再发) 或跨设备读到脏 state.
    private func resetHapticDiscoveryState() {
        hapticState = nil
        hapticRawState = nil
        hapticWaveformMask = nil
    }

    private func withHapticFeature(_ body: @escaping (UInt8) -> Void) {
        if let idx = featureIndex[Self.featureHaptic] {
            body(idx)
        } else {
            discoverFeature(featureId: Self.featureHaptic) { [weak self] idx in
                guard let self = self, let idx = idx else {
                    self?.showFeatureNotAvailable(.haptics)
                    return
                }
                self.featureIndex[Self.featureHaptic] = idx
                self.saveFeatureIndexCache()
                body(idx)
            }
        }
    }

    /// The toast "<mouse> does not support <what>.", with the mouse's own name (not the
    /// receiver's) and the feature in the words of the panes (LogiToastText).
    private func showFeatureNotAvailable(_ feature: LogiToastText.MissingFeature) {
        let message = LogiToastText.featureNotAvailable(mouse: deviceName(slot: deviceIndex), feature: feature)
        LogiDebugPanel.log("[\(deviceInfo.name)] \(feature): feature not available")
        LogiCenter.shared.externalBridge.showLogiToast(message, severity: .warning)
    }

    // MARK: - Scroll Force / Ratchet Torque (0x2111 SmartShift Enhanced)

    /// SmartShift v2 capabilities / status 响应抵达或本地缓存更新时发出. object = 本 session.
    static let scrollForceStateDidChangeNotification = Notification.Name("LogiScrollForceStateDidChange")

    struct ScrollForceStatus: Equatable {
        let mode: UInt8    // 1=freewheel, 2=ratchet, 0=未知
        let torque: UInt8  // 齿感力度 0-100
    }

    /// GetCapabilities (fn0) 返回: 设备是否支持可调 torque; 未查询过为 nil
    private(set) var scrollForceTunableTorque: Bool? = nil
    /// 最近一次 GetStatus (fn1) 解析结果; 未查询过为 nil
    private(set) var scrollForceStatus: ScrollForceStatus? = nil

    var debugScrollForceTunableTorque: Bool? { scrollForceTunableTorque }
    var debugScrollForceStatus: ScrollForceStatus? { scrollForceStatus }

    /// 查询 capabilities (fn0) + 当前状态 (fn1); 响应在 handleInputReport 解析后发通知
    func scrollForceRefreshInfo() {
        withScrollForceFeature { [weak self] idx in
            self?.sendRequest(featureIndex: idx, functionId: 0)
            self?.sendRequest(featureIndex: idx, functionId: 1)
        }
    }

    /// 设置齿感力度 (fn2 SetState). 只改 torque, mode/autoDisengage 用 0=不变;
    /// MX Master 4 需带回当前 mode 才生效, 故取最近读到的 mode. 写后回读 fn1 校准 UI.
    func scrollForceSetTorque(_ torque: UInt8) {
        // The diagnostics window's own write: never in a Release build (diagnosticsMayWrite).
        guard diagnosticsMayWrite else { return }
        let mode = scrollForceStatus?.mode ?? 0
        let params = Self.scrollForceSetTorqueParams(torque: torque, mode: mode)
        withScrollForceFeature { [weak self] idx in
            guard let self = self else { return }
            self.sendRequest(featureIndex: idx, functionId: 2, params: params)
            self.sendRequest(featureIndex: idx, functionId: 1)
        }
    }

    /// fn0 GetCapabilities 响应: report[4] bit0 = 支持可调 torque
    private static func parseScrollForceTunableTorque(_ report: UnsafeBufferPointer<UInt8>) -> Bool? {
        guard report.count >= 5 else { return nil }
        return report[4] & 0x01 != 0
    }

    /// fn1 GetStatus 响应: report[4] = wheelMode, report[6] = torque (byte[5] 为 autoDisengage 阈值, 跳过)
    private static func parseScrollForceStatus(_ report: UnsafeBufferPointer<UInt8>) -> ScrollForceStatus? {
        guard report.count >= 7 else { return nil }
        return ScrollForceStatus(mode: report[4], torque: report[6])
    }

    /// fn2 SetState 参数编码: [mode, autoDisengage, torque]. mode/autoDisengage=0 表示不改变
    /// (Solaar 约定 write_prefix_bytes=[0x00,0x00]); torque clamp 到 1-100.
    private static func scrollForceSetTorqueParams(torque: UInt8, mode: UInt8) -> [UInt8] {
        return [mode, 0x00, min(max(torque, 1), 100)]
    }

    /// rediscover / 切 slot 会清空 featureIndex, scroll force 的探测守卫与缓存状态必须一并复位,
    /// 否则该行永久消失 (probe 不再发) 或跨设备读到脏 state.
    private func resetScrollForceDiscoveryState() {
        scrollForceTunableTorque = nil
        scrollForceStatus = nil
        // 同一 slot 的 featureIndex 被清空 / 重探: 滚轮控制器随之失效, 探测结束后重建
        dropWheelController(slot: deviceIndex)
    }

    private func withScrollForceFeature(_ body: @escaping (UInt8) -> Void) {
        if let idx = featureIndex[Self.featureSmartShiftEnhanced] {
            body(idx)
        } else {
            discoverFeature(featureId: Self.featureSmartShiftEnhanced) { [weak self] idx in
                guard let self = self, let idx = idx else {
                    self?.showFeatureNotAvailable(.wheelForce)
                    return
                }
                self.featureIndex[Self.featureSmartShiftEnhanced] = idx
                self.saveFeatureIndexCache()
                body(idx)
            }
        }
    }

    // MARK: - Scroll Wheel Settings (0x2110 SmartShift / 0x2111 SmartShift Enhanced)
    //
    // 每个 slot 一个 LogiWheelController (BLE 直连 slot = 0xFF). 协议字节与映射见
    // Scrollio/Logi/Wheel/LogiWheelProtocol.swift. 建立时机: 可选功能探测链走完 (含缓存命中),
    // receiver 重连 slot 的 sweep 结束, 或 SmartShift Toggle 按需发现. 建立即读状态,
    // 且仅当 LogiSessionManager.wheelSettings.managedByScrollio 时写入用户设过的值 (重连后自动重放).

    private var wheelControllers: [UInt8: LogiWheelController] = [:]
    private var wheelRefreshWorkItems: [UInt8: DispatchWorkItem] = [:]
    /// ratchetSwitch 事件合并窗口: 连续切换只重读一次
    private static let wheelRefreshDelay: TimeInterval = 0.3

    /// 按 slot 已发现的 feature index 建立/保留滚轮控制器. 0x2111 优先 (MX Master 4 只有它).
    private func resolveWheelController(slot: UInt8) {
        let indices = slotStates[slot]?.featureIndex ?? [:]
        let feature: LogiWheelFeature
        let index: UInt8
        if let idx = indices[Self.featureSmartShiftEnhanced] {
            feature = .smartShiftEnhanced
            index = idx
        } else if let idx = indices[Self.featureSmartShift] {
            feature = .smartShift
            index = idx
        } else {
            dropWheelController(slot: slot)
            return
        }
        let desired = LogiSessionManager.shared.wheelSettings
        if let existing = wheelControllers[slot], existing.feature == feature, existing.featureIndex == index {
            existing.start(desired: desired)
            return
        }
        let name = deviceInfo.name
        let slotText = String(format: "0x%02X", slot)
        let controller = LogiWheelController(
            feature: feature,
            featureIndex: index,
            send: { [weak self] functionId, params in
                self?.sendWheelRequest(slot: slot, featureIndex: index, functionId: functionId, params: params)
            },
            schedule: { delay, work in
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            },
            onChange: {
                LogiSessionManager.shared.notifyWheelStateChanged()
            },
            log: { [weak self] message in
                LogiDebugPanel.log(device: name, type: .info, message: "[Wheel slot \(slotText)] \(message)")
                LogiSystemLog.note("\(self?.logTag(slot: slot) ?? "[Logitech mouse]") Wheel: \(message)")
            }
        )
        wheelControllers[slot] = controller
        LogiDebugPanel.log("[\(name)] Wheel feature \(String(format: "0x%04X", feature.featureId)) at index \(String(format: "0x%02X", index)) (slot \(String(format: "0x%02X", slot)), managedByScrollio=\(desired.managedByScrollio))")
        LogiSessionManager.shared.notifyWheelStateChanged()
        controller.start(desired: desired)
    }

    private func dropWheelController(slot: UInt8) {
        wheelRefreshWorkItems.removeValue(forKey: slot)?.cancel()
        guard wheelControllers.removeValue(forKey: slot) != nil else { return }
        LogiSessionManager.shared.notifyWheelStateChanged()
    }

    private func dropAllWheelControllers() {
        wheelRefreshWorkItems.values.forEach { $0.cancel() }
        wheelRefreshWorkItems.removeAll()
        guard !wheelControllers.isEmpty else { return }
        wheelControllers.removeAll()
        LogiSessionManager.shared.notifyWheelStateChanged()
    }

    /// 滚轮请求总是发往控制器所属 slot (receiver 巡检游标可能已移到别的 slot).
    private func sendWheelRequest(slot: UInt8, featureIndex: UInt8, functionId: UInt8, params: [UInt8]) {
        let saved = deviceIndex
        deviceIndex = slot
        sendRequest(featureIndex: featureIndex, functionId: functionId, params: params)
        deviceIndex = saved
    }

    private func scheduleWheelStatusRefresh(slot: UInt8) {
        guard wheelControllers[slot] != nil else { return }
        wheelRefreshWorkItems[slot]?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.wheelRefreshWorkItems[slot] = nil
            self.wheelControllers[slot]?.refresh()
        }
        wheelRefreshWorkItems[slot] = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.wheelRefreshDelay, execute: item)
    }

    /// 当前路由 slot 尚无滚轮 feature index 时按需串行发现 0x2111, 再 0x2110.
    /// 另有 getFeature 在飞时不发 (IRoot 响应不带 featureId, 并发会张冠李戴), 直接回调.
    private func discoverWheelFeatureIfNeeded(slot: UInt8, completion: @escaping () -> Void) {
        guard deviceIndex == slot else { completion(); return }
        if featureIndex[Self.featureSmartShiftEnhanced] != nil || featureIndex[Self.featureSmartShift] != nil {
            resolveWheelController(slot: slot)
            completion()
            return
        }
        guard pendingDiscovery.isEmpty else {
            LogiDebugPanel.log("[\(deviceInfo.name)] Wheel feature discovery deferred: another discovery in flight")
            completion()
            return
        }
        discoverFeature(featureId: Self.featureSmartShiftEnhanced) { [weak self] idx in
            guard let self = self else { return }
            if let idx = idx {
                self.recordWheelFeatureIndex(Self.featureSmartShiftEnhanced, index: idx, slot: slot)
                self.resolveWheelController(slot: slot)
                completion()
                self.pumpPendingDivertQueue()
                return
            }
            self.discoverFeature(featureId: Self.featureSmartShift) { [weak self] idx in
                guard let self = self else { return }
                if let idx = idx {
                    self.recordWheelFeatureIndex(Self.featureSmartShift, index: idx, slot: slot)
                }
                self.resolveWheelController(slot: slot)
                completion()
                self.pumpPendingDivertQueue()
            }
        }
    }

    private func recordWheelFeatureIndex(_ featureId: UInt16, index: UInt8, slot: UInt8) {
        slotStates[slot, default: PerSlotState()].featureIndex[featureId] = index
        if deviceIndex == slot {
            saveFeatureIndexCache()
        }
    }

    // MARK: Wheel API (LogiSessionManager -> LogiCenter)

    /// Hands the settings to every wheel. Each controller writes only while managed, and only
    /// the values the user set; it has to see the switch go off too, so that turning it on
    /// again decides every set value afresh.
    func applyWheelSettings(_ settings: LogiWheelSettings) {
        for slot in wheelControllers.keys.sorted() {
            wheelControllers[slot]?.apply(settings)
        }
    }

    /// 重读所有 slot 的滚轮状态. 返回是否有可读的滚轮.
    @discardableResult
    func refreshWheelStates() -> Bool {
        for slot in wheelControllers.keys.sorted() {
            wheelControllers[slot]?.refresh()
        }
        return !wheelControllers.isEmpty
    }

    func wheelDeviceStates() -> [LogiWheelDeviceState] {
        return wheelControllers.keys.sorted().compactMap { wheelDeviceState(slot: $0) }
    }

    private func wheelDeviceState(slot: UInt8) -> LogiWheelDeviceState? {
        guard let wheel = wheelControllers[slot] else { return nil }
        return wheel.deviceState(id: deviceId(slot: slot), deviceName: deviceName(slot: slot))
    }

    /// Tells two units of one model apart, the same at every connection: the serial number
    /// macOS has for the device (over Bluetooth its address), else its location id. Only
    /// used to order twins (LogiSessionManager.orderedForDisambiguation); it is never shown,
    /// stored or logged.
    private(set) lazy var twinOrderKey: String = {
        if let serial = IOHIDDeviceGetProperty(hidDevice, kIOHIDSerialNumberKey as CFString) as? String, !serial.isEmpty {
            return serial
        }
        if let location = IOHIDDeviceGetProperty(hidDevice, kIOHIDLocationIDKey as CFString) as? Int {
            return String(format: "%08X", location)
        }
        return ""
    }()

    /// 稳定 id: BLE = VID:PID; receiver = VID:receiverPID:slot:wirelessPID. 跨重连不变,
    /// 同型号重复时由 LogiSessionManager 追加序号. Wheel and mouse states share it.
    private func deviceId(slot: UInt8) -> String {
        if connectionMode == .receiver {
            let wpid = receiverPairedDevices.first(where: { $0.slot == slot })?.wirelessPID ?? 0
            return String(format: "%04X:%04X:%d:%04X", deviceInfo.vendorId, deviceInfo.productId, Int(slot), wpid)
        }
        return String(format: "%04X:%04X", deviceInfo.vendorId, deviceInfo.productId)
    }

    /// What the interface calls the mouse. Through a receiver: the name the receiver has
    /// for it if it gave one, else the name read from the mouse itself (feature 0x0005),
    /// and the receiver's own name only until one of those arrived (a mouse on a receiver
    /// used to be shown as "USB Receiver"). Over Bluetooth: the name macOS has for it (what
    /// the user sees in the Bluetooth settings).
    private func deviceName(slot: UInt8) -> String {
        return Self.displayName(
            connectionMode: connectionMode,
            pairingName: receiverPairedDevices.first(where: { $0.slot == slot })?.name,
            modelName: modelNames[slot],
            interfaceName: deviceInfo.name
        )
    }

    static func displayName(connectionMode: ConnectionMode, pairingName: String? = nil, modelName: String?, interfaceName: String) -> String {
        guard connectionMode == .receiver else { return interfaceName }
        if let pairingName = pairingName, !pairingName.isEmpty { return pairingName }
        if let modelName = modelName, !modelName.isEmpty { return modelName }
        return interfaceName
    }

    // MARK: - The device's own name (feature 0x0005)

    /// The model name each slot's device reported (LogiDeviceNameRead); absent until read.
    private var modelNames: [UInt8: String] = [:]
    /// Name reads under way, per slot.
    private var deviceNameReads: [UInt8: LogiDeviceNameRead] = [:]

    /// Starts reading the cursor slot's name from the device (function 0, then function 1
    /// in pieces). Reading only; the answers come in through handleDeviceNameResponse.
    private func requestDeviceNameIfNeeded() {
        let slot = deviceIndex
        guard modelNames[slot] == nil, deviceNameReads[slot] == nil,
              currentReceiverTargetIsConnected,
              let idx = featureIndex[Self.featureDeviceNameType] else { return }
        deviceNameReads[slot] = LogiDeviceNameRead()
        sendRequest(featureIndex: idx, functionId: LogiDeviceNameRead.lengthFunction)
    }

    /// An answer of this app on feature 0x0005, function 0 or 1, for the cursor slot.
    private func handleDeviceNameResponse(functionId: UInt8, report: UnsafeBufferPointer<UInt8>) {
        let slot = deviceIndex
        guard var read = deviceNameReads[slot], let idx = featureIndex[Self.featureDeviceNameType] else { return }
        let step = functionId == LogiDeviceNameRead.lengthFunction ? read.handleLength(report) : read.handlePiece(report)
        switch step {
        case .requestPiece(let index):
            deviceNameReads[slot] = read
            sendRequest(featureIndex: idx, functionId: LogiDeviceNameRead.nameFunction, params: [index])
        case .finished(let name):
            deviceNameReads[slot] = nil
            modelNames[slot] = name
            // The diagnostics window lists the slot under this name too, unless the
            // receiver gave one.
            if let pairedIndex = receiverPairedDevices.firstIndex(where: { $0.slot == slot }),
               receiverPairedDevices[pairedIndex].name.isEmpty {
                receiverPairedDevices[pairedIndex].name = name
            }
            LogiDebugPanel.log(device: deviceInfo.name, type: .info, message: "Slot \(String(format: "0x%02X", slot)) name from the device: \"\(name)\"")
            // The Mouse pane, the menu and the diagnostics window show the name.
            NotificationCenter.default.post(name: LogiSessionManager.sessionChangedNotification, object: nil)
            LogiSessionManager.shared.notifyWheelStateChanged()
        case .failed:
            deviceNameReads[slot] = nil
            LogiDebugPanel.log(device: deviceInfo.name, type: .warning, message: "Slot \(String(format: "0x%02X", slot)): the device's name could not be read")
        }
    }

    // MARK: - Names in the system log

    /// The name a `logi` line of the system log carries for a slot: the model name the
    /// device reports, and a neutral label until that was read. Never the name macOS has for
    /// a Bluetooth device: the user can change that one ("Anna's MX Anywhere"), and a log
    /// pasted into a bug report would publish it.
    static func logName(connectionMode: ConnectionMode, modelName: String?, interfaceName: String, productId: UInt16) -> String {
        if let modelName = modelName, !modelName.isEmpty { return modelName }
        switch connectionMode {
        case .bleDirect:
            return String(format: "Logitech mouse %04X", productId)
        case .receiver, .unsupported:
            // A receiver's own product name comes from its USB descriptor.
            return interfaceName
        }
    }

    private func logName(slot: UInt8) -> String {
        return Self.logName(
            connectionMode: connectionMode,
            modelName: modelNames[slot],
            interfaceName: deviceInfo.name,
            productId: deviceInfo.productId
        )
    }

    /// "[MX Master 4 slot 0xFF]": what a system-log line about one mouse starts with.
    private func logTag(slot: UInt8) -> String {
        return "[\(logName(slot: slot)) slot \(String(format: "0x%02X", slot))]"
    }

    /// What a system-log line about the link (the writes of this session) starts with: the
    /// mouse over Bluetooth, the receiver otherwise.
    private var sessionLogTag: String {
        return "[\(logName(slot: connectionMode == .receiver ? 0x00 : deviceIndex))]"
    }

    // MARK: - Gesture Navigation (raw XY 0x1B04 + haptic cues 0x19B0)
    //
    // One LogiGestureController per slot (BLE direct slot = 0xFF), created on first use.
    // Byte layouts: Scrollio/Logi/Gesture/LogiGestureProtocol.swift. The controller decides the
    // reporting flags of every control this session diverts (setControlReporting), so raw
    // XY is armed together with the divert when applyUsage runs and cleared with it. It is
    // dropped whenever the slot is discovered anew or disconnects: the mouse forgets its
    // temporary flags then, too.

    private var gestureControllers: [UInt8: LogiGestureController] = [:]

    private func gestureController(slot: UInt8) -> LogiGestureController {
        if let existing = gestureControllers[slot] { return existing }
        let name = deviceInfo.name
        let controller = LogiGestureController(
            sendReporting: { [weak self] cid, flags in
                self?.sendGestureReporting(slot: slot, cid: cid, flagsByte: flags)
            },
            sendHaptic: { [weak self] functionId, params in
                self?.sendGestureHapticRequest(slot: slot, functionId: functionId, params: params)
            },
            deliverMovement: { cid, deltaX, deltaY in
                LogiCenter.shared.externalBridge.handleLogiGestureMovement(
                    code: LogiCIDDirectory.toScrollioCode(cid), deltaX: deltaX, deltaY: deltaY
                )
            },
            schedule: { delay, work in
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            },
            onChange: {
                LogiSessionManager.shared.notifyGestureStateChanged()
            },
            log: { [weak self] message in
                LogiDebugPanel.log(device: name, type: .info, message: "[Gesture slot \(String(format: "0x%02X", slot))] \(message)")
                LogiSystemLog.note("\(self?.logTag(slot: slot) ?? "[Logitech mouse]") \(message)")
            },
            // Once the user switched haptics off in the Mouse settings, a cue never switches
            // them back on; while that setting was never touched, cues switch them on as before.
            mayEnableHaptics: {
                LogiSessionManager.shared.gestureCuesMayEnableHaptics
            }
        )
        gestureControllers[slot] = controller
        return controller
    }

    private func dropGestureController(slot: UInt8) {
        guard gestureControllers.removeValue(forKey: slot) != nil else { return }
        LogiSessionManager.shared.notifyGestureStateChanged()
    }

    private func dropAllGestureControllers() {
        guard !gestureControllers.isEmpty else { return }
        gestureControllers.removeAll()
        LogiSessionManager.shared.notifyGestureStateChanged()
    }

    /// Teardown: undivert + raw XY off (0x22) for every control Scrollio armed, on every slot.
    private func disarmAllGestureControllers() {
        for slot in gestureControllers.keys.sorted() {
            gestureControllers[slot]?.disarmAll()
        }
    }

    /// Reporting writes the controller starts itself (reconcile, fallback, disarm) always
    /// go to its own slot; the receiver cursor may point elsewhere.
    private func sendGestureReporting(slot: UInt8, cid: UInt16, flagsByte: UInt8) {
        let saved = deviceIndex
        deviceIndex = slot
        defer { deviceIndex = saved }
        guard currentReceiverTargetIsConnected,
              let reprogIdx = featureIndex[Self.featureReprogV4] else { return }
        sendControlReporting(
            featureIndex: reprogIdx,
            cid: cid,
            flagsByte: flagsByte,
            updateLocalState: true,
            debugSource: "gestureReporting"
        )
    }

    private func sendGestureHapticRequest(slot: UInt8, functionId: UInt8, params: [UInt8]) {
        let saved = deviceIndex
        deviceIndex = slot
        defer { deviceIndex = saved }
        guard currentReceiverTargetIsConnected,
              let hapticIdx = featureIndex[Self.featureHaptic] else { return }
        sendRequest(featureIndex: hapticIdx, functionId: functionId, params: params)
    }

    /// Fast path of handleInputReport. True when the report was raw XY movement of a hold
    /// this session tracks; nothing is allocated or logged for it.
    private func handleTrackedRawXYMovement(_ report: UnsafeBufferPointer<UInt8>) -> Bool {
        guard report[3] == LogiGestureProtocol.rawXYEventFunctionByte else { return false }
        let slot = connectionMode == .receiver ? report[1] : deviceIndex
        guard let controller = gestureControllers[slot], controller.hasTrackedHold,
              let reprogIdx = slotStates[slot]?.featureIndex[Self.featureReprogV4], report[2] == reprogIdx,
              let delta = LogiGestureProtocol.rawXYDelta(report) else { return false }
        controller.handleRawXY(deltaX: delta.deltaX, deltaY: delta.deltaY)
        return true
    }

    /// Raw XY movement nobody asked for: no tracked hold on this slot (armed by another
    /// app, left over from a Scrollio that died, or the arm echo is still on its way).
    private func handleUntrackedRawXYEvent(_ report: UnsafeBufferPointer<UInt8>) {
        guard let delta = LogiGestureProtocol.rawXYDelta(report) else { return }
        LogiDebugPanel.log(device: deviceInfo.name, type: .info,
            message: "Raw XY event without a tracked hold ignored (dx=\(delta.deltaX), dy=\(delta.deltaY))")
    }

    /// Hands the haptic feature index of a slot to its controller, which then reads the
    /// waveform list and whether haptics are switched on.
    private func resolveGestureHaptics(slot: UInt8) {
        let index = slotStates[slot]?.featureIndex[Self.featureHaptic]
        guard index != nil || gestureControllers[slot] != nil else { return }
        gestureController(slot: slot).setHapticFeature(index: index)
    }

    /// A slot that reconnected lost its feature indices and the optional probe does not run
    /// twice: look the haptic feature up on demand. Skipped while another getFeature is in
    /// flight (IRoot answers carry no feature id). `completion` runs in every case, after
    /// the lookup when there is one.
    private func discoverGestureHapticFeatureIfNeeded(slot: UInt8, completion: @escaping () -> Void = {}) {
        guard deviceIndex == slot else { completion(); return }
        if featureIndex[Self.featureHaptic] != nil {
            resolveGestureHaptics(slot: slot)
            completion()
            return
        }
        guard pendingDiscovery.isEmpty else { completion(); return }
        discoverFeature(featureId: Self.featureHaptic) { [weak self] idx in
            guard let self = self else { return }
            if let idx = idx {
                self.slotStates[slot, default: PerSlotState()].featureIndex[Self.featureHaptic] = idx
            }
            self.resolveGestureHaptics(slot: slot)
            completion()
            self.pumpPendingDivertQueue()
        }
    }

    /// Divertable controls that can report raw XY (getCidInfo flags2 bit0).
    static func rawXYCapableCIDs(in controls: [ControlInfo]) -> Set<UInt16> {
        return Set(controls.filter {
            $0.isDivertable && LogiGestureProtocol.supportsRawXY(controlFlags: $0.flags)
        }.map { $0.cid })
    }

    /// Scrollio codes -> CIDs. Codes without a Logitech control (plain mouse buttons) drop out.
    static func rawXYRequestCIDs(forScrollioCodes codes: Set<UInt16>) -> Set<UInt16> {
        return Set(codes.compactMap { LogiCIDDirectory.toCID($0) })
    }

    // MARK: Gesture API (LogiSessionManager -> LogiCenter)

    var supportsGestureRawXY: Bool {
        return gestureControllers.values.contains { $0.supportsRawXY }
    }

    var supportsGestureHaptics: Bool {
        return gestureControllers.values.contains { $0.supportsHaptics }
    }

    func refreshGestureHaptics() {
        for slot in gestureControllers.keys.sorted() {
            gestureControllers[slot]?.refreshHaptics()
        }
    }

    @discardableResult
    func playGestureHaptic(_ cue: MouseGestureHapticCue, slot: UInt8) -> Bool {
        guard let controller = gestureControllers[slot] else {
            LogiSystemLog.note("\(sessionLogTag) Haptic cue \(cue) skipped: nothing known about slot \(String(format: "0x%02X", slot)) (known: \(gestureControllers.keys.sorted().map { String(format: "0x%02X", $0) }))")
            return false
        }
        return controller.play(cue)
    }

    // MARK: - Basic mouse settings (battery 0x1004 / 0x1000, DPI 0x2201, haptics 0x19B0, press force 0x19C0)
    //
    // One LogiMouseBasicsController per slot (BLE direct slot = 0xFF), built like the wheel
    // controllers: at the end of the optional probe chain (cache hits included) and after a
    // receiver slot reconnected. It reads on connect and writes only what the user set while
    // LogiSessionManager.mouseManaged is on. Byte layouts and rules: Scrollio/Logi/Basics/*.

    private var basicsControllers: [UInt8: LogiMouseBasicsController] = [:]

    /// The basics a slot has, from its feature indices. 0x1004 wins over 0x1000.
    static func mouseBasicsFeatures(from indices: [UInt16: UInt8]) -> LogiMouseBasicsController.Features {
        var features = LogiMouseBasicsController.Features()
        if let index = indices[featureUnifiedBattery] {
            features.battery = .init(feature: .unified, index: index)
        } else if let index = indices[featureBatteryStatus] {
            features.battery = .init(feature: .legacy, index: index)
        }
        features.pointerSpeed = indices[featureAdjustableDPI]
        features.haptics = indices[featureHaptic]
        features.pressForce = indices[featureForceSensing]
        return features
    }

    private func resolveMouseBasicsController(slot: UInt8) {
        let features = Self.mouseBasicsFeatures(from: slotStates[slot]?.featureIndex ?? [:])
        guard !features.isEmpty else {
            dropMouseBasicsController(slot: slot)
            return
        }
        let manager = LogiSessionManager.shared
        if let existing = basicsControllers[slot], existing.features == features {
            existing.start(desired: manager.mouseSettings, managed: manager.mouseManaged)
            return
        }
        let name = deviceName(slot: slot)
        let slotText = String(format: "0x%02X", slot)
        let controller = LogiMouseBasicsController(
            features: features,
            send: { [weak self] index, functionId, params in
                self?.sendMouseBasicsRequest(slot: slot, featureIndex: index, functionId: functionId, params: params)
            },
            schedule: { delay, work in
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            },
            onChange: {
                LogiSessionManager.shared.notifyMouseStateChanged()
            },
            log: { [weak self] message in
                LogiDebugPanel.log(device: name, type: .info, message: "[Basics slot \(slotText)] \(message)")
                LogiSystemLog.note("\(self?.logTag(slot: slot) ?? "[Logitech mouse]") \(message)")
            }
        )
        basicsControllers[slot] = controller
        manager.notifyMouseStateChanged()
        controller.start(desired: manager.mouseSettings, managed: manager.mouseManaged)
    }

    private func dropMouseBasicsController(slot: UInt8) {
        guard basicsControllers.removeValue(forKey: slot) != nil else { return }
        LogiSessionManager.shared.notifyMouseStateChanged()
    }

    private func dropAllMouseBasicsControllers() {
        guard !basicsControllers.isEmpty else { return }
        basicsControllers.removeAll()
        LogiSessionManager.shared.notifyMouseStateChanged()
    }

    /// Requests always go to the controller's own slot; the receiver cursor may point elsewhere.
    private func sendMouseBasicsRequest(slot: UInt8, featureIndex: UInt8, functionId: UInt8, params: [UInt8]) {
        let saved = deviceIndex
        deviceIndex = slot
        defer { deviceIndex = saved }
        guard currentReceiverTargetIsConnected else { return }
        sendRequest(featureIndex: featureIndex, functionId: functionId, params: params)
    }

    /// A reconnected receiver slot lost its feature indices and the optional probe does not
    /// run twice: look the basics up on demand, one getFeature at a time (0x19B0 was looked
    /// up just before, for the gesture cues). Skipped while another getFeature is in flight.
    private func discoverMouseBasicsFeaturesIfNeeded(slot: UInt8) {
        guard deviceIndex == slot else { return }
        var missing = [Self.featureUnifiedBattery, Self.featureBatteryStatus, Self.featureAdjustableDPI, Self.featureForceSensing]
            .filter { featureIndex[$0] == nil }
        if featureIndex[Self.featureUnifiedBattery] != nil {
            missing.removeAll { $0 == Self.featureBatteryStatus }
        }
        guard !missing.isEmpty, pendingDiscovery.isEmpty else {
            resolveMouseBasicsController(slot: slot)
            return
        }
        discoverNextMouseBasicsFeature(missing, slot: slot)
    }

    private func discoverNextMouseBasicsFeature(_ remaining: [UInt16], slot: UInt8) {
        guard let featureId = remaining.first else {
            resolveMouseBasicsController(slot: slot)
            pumpPendingDivertQueue()
            return
        }
        var rest = Array(remaining.dropFirst())
        discoverFeature(featureId: featureId) { [weak self] idx in
            guard let self = self else { return }
            if let idx = idx {
                self.slotStates[slot, default: PerSlotState()].featureIndex[featureId] = idx
                if featureId == Self.featureUnifiedBattery {
                    rest.removeAll { $0 == Self.featureBatteryStatus }
                }
            }
            self.discoverNextMouseBasicsFeature(rest, slot: slot)
        }
    }

    // MARK: Basics API (LogiSessionManager -> LogiCenter)

    func applyMouseSettings(_ settings: LogiMouseSettings, managed: Bool) {
        for slot in basicsControllers.keys.sorted() {
            basicsControllers[slot]?.apply(desired: settings, managed: managed)
        }
    }

    /// "Send Again" (LogiCenter.sendMouseSettingsAgain): every slot's basics and wheel start
    /// over the way a reconnect starts a kept controller (`resolveMouseBasicsController`,
    /// `resolveWheelController`): everything is read again, then a value is written only
    /// where the mouse is managed, the user set it and the fresh read differs.
    func startMouseSettingsAgain(mouse: LogiMouseSettings, managed: Bool, wheel: LogiWheelSettings) {
        for slot in basicsControllers.keys.sorted() {
            basicsControllers[slot]?.start(desired: mouse, managed: managed)
        }
        for slot in wheelControllers.keys.sorted() {
            wheelControllers[slot]?.start(desired: wheel)
        }
    }

    /// Re-reads the basics of every slot. Returns whether any slot has them.
    @discardableResult
    func refreshMouseBasics() -> Bool {
        for slot in basicsControllers.keys.sorted() {
            basicsControllers[slot]?.refresh()
        }
        return !basicsControllers.isEmpty
    }

    /// Plays the sample pulse on every slot with a haptic motor.
    func playHapticSample() {
        for slot in basicsControllers.keys.sorted() where basicsControllers[slot]?.features.haptics != nil {
            basicsControllers[slot]?.playSample()
        }
    }

    /// One entry per slot that has basics or a wheel, the wheel state inside.
    func mouseDeviceStates() -> [LogiMouseDeviceState] {
        let slots = Set(basicsControllers.keys).union(wheelControllers.keys).sorted()
        let managed = LogiSessionManager.shared.mouseManaged
        return slots.map { slot in
            let id = deviceId(slot: slot)
            let name = deviceName(slot: slot)
            let wheel = wheelDeviceState(slot: slot)
            if let basics = basicsControllers[slot] {
                return basics.deviceState(id: id, deviceName: name, wheel: wheel)
            }
            return LogiMouseDeviceState(
                id: id, deviceName: name, supported: [], managed: managed,
                battery: nil, pointerSpeed: nil, haptics: nil, pressForce: nil, wheel: wheel
            )
        }
    }

    // MARK: - Force Sensing Button (0x19C0)

    /// Force sensing info / current 响应抵达或缓存更新时发出. object = 本 session.
    static let forceSensingStateDidChangeNotification = Notification.Name("LogiForceSensingStateDidChange")
    /// 无专属 context 的可选 feature 被发现时发出, 面板据此刷新 FEATURES 表. object = 本 session.
    static let auxiliaryFeaturesDidChangeNotification = Notification.Name("LogiAuxiliaryFeaturesDidChange")

    /// 只操作第 0 号压感按钮 (MX Master 4 仅一颗).
    private static let forceSensingButtonNumber: UInt8 = 0

    /// fn1 GetButtonInfo 解析结果 (Scrollio/Logi/Basics/LogiPressForceProtocol.swift).
    typealias ForceSensingInfo = LogiPressForceInfo

    /// fn1 GetButtonInfo 解析结果; 未查询过为 nil
    private(set) var forceSensingInfo: ForceSensingInfo? = nil
    /// fn2 GetButtonCurrent 当前力度; 未查询过为 nil
    private(set) var forceSensingCurrent: UInt16? = nil

    var debugForceSensingInfo: ForceSensingInfo? { forceSensingInfo }
    var debugForceSensingCurrent: UInt16? { forceSensingCurrent }

    /// 查询按钮能力 (fn1: changeable/min/max/default) + 当前力度 (fn2); 响应解析后发通知
    func forceSensingRefreshInfo() {
        withForceSensingFeature { [weak self] idx in
            self?.sendRequest(featureIndex: idx, functionId: 1, params: [Self.forceSensingButtonNumber])
            self?.sendRequest(featureIndex: idx, functionId: 2, params: [Self.forceSensingButtonNumber])
        }
    }

    /// 设置按压激活阈值 (fn3 SetButtonConfig). clamp 到设备上报的 min/max, 写后回读 fn2 校准 UI.
    func forceSensingSetCurrent(_ value: UInt16) {
        // The diagnostics window's own write: never in a Release build (diagnosticsMayWrite).
        guard diagnosticsMayWrite else { return }
        let clamped = Self.forceSensingClamp(value, info: forceSensingInfo)
        let params = Self.forceSensingSetCurrentParams(number: Self.forceSensingButtonNumber, current: clamped)
        withForceSensingFeature { [weak self] idx in
            guard let self = self else { return }
            self.sendRequest(featureIndex: idx, functionId: 3, params: params)
            self.sendRequest(featureIndex: idx, functionId: 2, params: [Self.forceSensingButtonNumber])
        }
    }

    // Byte layouts: LogiPressForceProtocol (shared with the Mouse settings controller).

    private static func parseForceSensingInfo(_ report: UnsafeBufferPointer<UInt8>) -> ForceSensingInfo? {
        return LogiPressForceProtocol.parseInfo(Array(report))
    }

    private static func parseForceSensingCurrent(_ report: UnsafeBufferPointer<UInt8>) -> UInt16? {
        return LogiPressForceProtocol.parseCurrent(Array(report))
    }

    private static func forceSensingSetCurrentParams(number: UInt8, current: UInt16) -> [UInt8] {
        return LogiPressForceProtocol.setParams(button: number, value: current)
    }

    private static func forceSensingClamp(_ value: UInt16, info: ForceSensingInfo?) -> UInt16 {
        return LogiPressForceProtocol.clamp(value, info: info)
    }

    private func resetForceSensingState() {
        forceSensingInfo = nil
        forceSensingCurrent = nil
        // The slot's feature indices are cleared or probed anew: its basics controller goes
        // with them and is built again at the end of the probe chain.
        dropMouseBasicsController(slot: deviceIndex)
    }

    private func withForceSensingFeature(_ body: @escaping (UInt8) -> Void) {
        if let idx = featureIndex[Self.featureForceSensing] {
            body(idx)
        } else {
            discoverFeature(featureId: Self.featureForceSensing) { [weak self] idx in
                guard let self = self, let idx = idx else {
                    self?.showFeatureNotAvailable(.pressForce)
                    return
                }
                self.featureIndex[Self.featureForceSensing] = idx
                self.saveFeatureIndexCache()
                body(idx)
            }
        }
    }

    // MARK: - Report Parsing

    /// HID++ 2.0 error report [0x11, devIdx, 0xFF, origFeatureIdx, origFn<<4 | swid, errorCode, ...]:
    /// the feature index and function of the refused request and the error code. The code is
    /// byte 5 (OpenLogi protocol/v20.rs, Solaar); it used to be read from byte 6, so every
    /// logged code was wrong. nil for a report too short to hold them.
    static func hidpp20ErrorFields<Bytes: RandomAccessCollection>(_ report: Bytes) -> (featureIndex: UInt8, functionId: UInt8, errorCode: UInt8)?
    where Bytes.Element == UInt8, Bytes.Index == Int {
        guard report.count >= 6 else { return nil }
        let base = report.startIndex
        return (report[base + 3], report[base + 4] >> 4, report[base + 5])
    }

    private static func isGetControlReportingQueryResponse(_ report: UnsafeBufferPointer<UInt8>) -> Bool {
        guard report.count >= 9 else { return false }
        let functionId = report[3] >> 4
        let softwareId = report[3] & 0x0F
        return functionId == 2 && softwareId == 0x01
    }

    private static func parseReportingResponse(_ report: UnsafeBufferPointer<UInt8>) -> ReportingResponse? {
        guard isGetControlReportingQueryResponse(report) else { return nil }
        let cid = (UInt16(report[4]) << 8) | UInt16(report[5])
        let targetCID = (UInt16(report[7]) << 8) | UInt16(report[8])
        return ReportingResponse(cid: cid, reportingFlags: report[6], targetCID: targetCID)
    }

    private static func isReportingStateNotification(_ report: UnsafeBufferPointer<UInt8>) -> Bool {
        guard report.count >= 9 else { return false }
        let functionId = report[3] >> 4
        let softwareId = report[3] & 0x0F
        return functionId == 2 && softwareId == 0x00
    }

    private static func parseReportingStateNotification(_ report: UnsafeBufferPointer<UInt8>) -> ReportingResponse? {
        guard isReportingStateNotification(report) else { return nil }
        let cid = (UInt16(report[4]) << 8) | UInt16(report[5])
        let targetCID = (UInt16(report[7]) << 8) | UInt16(report[8])
        return ReportingResponse(cid: cid, reportingFlags: report[6], targetCID: targetCID)
    }

    private static func isSetControlReportingAck(_ report: UnsafeBufferPointer<UInt8>) -> Bool {
        guard report.count >= 9 else { return false }
        let functionId = report[3] >> 4
        let softwareId = report[3] & 0x0F
        return functionId == 3 && softwareId == 0x01
    }

    private static func parseSetControlReportingAck(_ report: UnsafeBufferPointer<UInt8>) -> SetControlReportingAck? {
        guard isSetControlReportingAck(report) else { return nil }
        let cid = (UInt16(report[4]) << 8) | UInt16(report[5])
        let targetCID = (UInt16(report[7]) << 8) | UInt16(report[8])
        return SetControlReportingAck(cid: cid, flagsByte: report[6], targetCID: targetCID)
    }

    private static func isDivertedButtonEvent(_ report: UnsafeBufferPointer<UInt8>) -> Bool {
        guard report.count >= 4 else { return false }
        let functionId = report[3] >> 4
        let softwareId = report[3] & 0x0F
        return functionId == 0 && softwareId == 0x00
    }

    private static func reprogInitFunction0Route(_ report: UnsafeBufferPointer<UInt8>) -> ReprogInitFunction0Route {
        guard report.count >= 4 else { return .ignored }
        let functionId = report[3] >> 4
        guard functionId == 0 else { return .ignored }

        switch report[3] & 0x0F {
        case 0x00:
            return .divertedButtonEvent
        case 0x01:
            return .getControlCountResponse
        default:
            return .ignored
        }
    }

    enum ReprogInitFunction1Route: Equatable {
        case getControlInfoResponse
        case rawXYEvent
    }

    /// init 阶段 REPROG function 1 的路由: software id 0 是设备主动上报的 raw XY 位移事件,
    /// 其余 (Mos 自己的 swid) 才是 GetControlInfo 响应. 混淆会把位移字节当成一个控件记下来.
    private static func reprogInitFunction1Route(_ report: UnsafeBufferPointer<UInt8>) -> ReprogInitFunction1Route {
        return LogiGestureProtocol.isRawXYEvent(report) ? .rawXYEvent : .getControlInfoResponse
    }

    /// GetControlInfo 响应的 CID 已记录过 (迟到的重复响应). CID 0 是空槽位, 不按重复处理.
    static func isDuplicateControlInfo(cid: UInt16, known: [UInt16]) -> Bool {
        return cid != 0 && known.contains(cid)
    }

    private static func shouldRetryControlInfoTimeout(
        connectionMode: ConnectionMode,
        retryCount: Int
    ) -> Bool {
        return connectionMode == .bleDirect && retryCount < bleControlInfoRetryLimit
    }

    private static func isIRootPingResponse(_ report: UnsafeBufferPointer<UInt8>) -> Bool {
        guard report.count >= 4 else { return false }
        let featureIdx = report[2]
        let functionId = report[3] >> 4
        let softwareId = report[3] & 0x0F
        return featureIdx == 0x00 && functionId == 1 && softwareId == 0x01
    }

    private static func reassertionCIDForSetControlReportingAck(
        lastApplied: Set<UInt16>,
        divertedCIDs: Set<UInt16>,
        ack: SetControlReportingAck,
        isOwnAck: Bool
    ) -> UInt16? {
        guard !isOwnAck,
              lastApplied.contains(ack.cid) || divertedCIDs.contains(ack.cid),
              ack.updatesTemporaryDivert,
              !ack.temporaryDivertEnabled else {
            return nil
        }
        return ack.cid
    }

    private static func reassertionCIDForReportingState(
        lastApplied: Set<UInt16>,
        divertedCIDs: Set<UInt16>,
        state: ReportingResponse
    ) -> UInt16? {
        guard lastApplied.contains(state.cid) || divertedCIDs.contains(state.cid),
              (state.reportingFlags & 0x01) == 0 else {
            return nil
        }
        return state.cid
    }

    #if DEBUG
    internal static func isGetControlReportingQueryResponseForTests(_ bytes: [UInt8]) -> Bool {
        return bytes.withUnsafeBufferPointer { report in
            isGetControlReportingQueryResponse(report)
        }
    }

    internal static func isDivertedButtonEventForTests(_ bytes: [UInt8]) -> Bool {
        return bytes.withUnsafeBufferPointer { report in
            isDivertedButtonEvent(report)
        }
    }

    internal static func reprogInitFunction0RouteForTests(_ bytes: [UInt8]) -> ReprogInitFunction0Route {
        return bytes.withUnsafeBufferPointer { report in
            reprogInitFunction0Route(report)
        }
    }

    internal static func reprogInitFunction1RouteForTests(_ bytes: [UInt8]) -> ReprogInitFunction1Route {
        return bytes.withUnsafeBufferPointer { report in
            reprogInitFunction1Route(report)
        }
    }

    internal static func controlReportingParamsForTests(
        connectionMode: ConnectionMode,
        cid: UInt16,
        flagsByte: UInt8
    ) -> [UInt8] {
        return controlReportingParams(connectionMode: connectionMode, cid: cid, flagsByte: flagsByte)
    }

    internal static func shouldRetryControlInfoTimeoutForTests(
        connectionMode: ConnectionMode,
        retryCount: Int
    ) -> Bool {
        return shouldRetryControlInfoTimeout(
            connectionMode: connectionMode,
            retryCount: retryCount
        )
    }

    internal static func isIRootPingResponseForTests(_ bytes: [UInt8]) -> Bool {
        return bytes.withUnsafeBufferPointer { report in
            isIRootPingResponse(report)
        }
    }

    internal static func reportingResponseForTests(_ bytes: [UInt8], matchesExpectedCID expectedCID: UInt16) -> Bool {
        return bytes.withUnsafeBufferPointer { report in
            parseReportingResponse(report)?.cid == expectedCID
        }
    }

    internal static func setControlReportingAckForTests(
        _ bytes: [UInt8]
    ) -> (cid: UInt16, flagsByte: UInt8, targetCID: UInt16)? {
        return bytes.withUnsafeBufferPointer { report in
            guard let ack = parseSetControlReportingAck(report) else { return nil }
            return (ack.cid, ack.flagsByte, ack.targetCID)
        }
    }

    internal static func reportingStateNotificationForTests(
        _ bytes: [UInt8]
    ) -> (cid: UInt16, reportingFlags: UInt8, targetCID: UInt16)? {
        return bytes.withUnsafeBufferPointer { report in
            guard let state = parseReportingStateNotification(report) else { return nil }
            return (state.cid, state.reportingFlags, state.targetCID)
        }
    }

    internal static func reassertionCIDForSetControlReportingAckForTests(
        lastApplied: Set<UInt16>,
        divertedCIDs: Set<UInt16>,
        ackBytes: [UInt8],
        isOwnAck: Bool
    ) -> UInt16? {
        return ackBytes.withUnsafeBufferPointer { report in
            guard let ack = parseSetControlReportingAck(report) else { return nil }
            return reassertionCIDForSetControlReportingAck(
                lastApplied: lastApplied,
                divertedCIDs: divertedCIDs,
                ack: ack,
                isOwnAck: isOwnAck
            )
        }
    }

    internal static func reassertionCIDForReportingStateForTests(
        lastApplied: Set<UInt16>,
        divertedCIDs: Set<UInt16>,
        bytes: [UInt8]
    ) -> UInt16? {
        return bytes.withUnsafeBufferPointer { report in
            guard let state = parseReportingStateNotification(report) else { return nil }
            return reassertionCIDForReportingState(
                lastApplied: lastApplied,
                divertedCIDs: divertedCIDs,
                state: state
            )
        }
    }

    internal static func parseHapticCapabilitiesMaskForTests(_ bytes: [UInt8]) -> UInt32? {
        return bytes.withUnsafeBufferPointer { report in
            parseHapticCapabilitiesMask(report)
        }
    }

    internal static func parseHapticStateForTests(_ bytes: [UInt8]) -> HapticState? {
        return bytes.withUnsafeBufferPointer { report in
            parseHapticState(report)
        }
    }


    internal static func parseScrollForceTunableTorqueForTests(_ bytes: [UInt8]) -> Bool? {
        return bytes.withUnsafeBufferPointer { report in
            parseScrollForceTunableTorque(report)
        }
    }

    internal static func parseScrollForceStatusForTests(_ bytes: [UInt8]) -> ScrollForceStatus? {
        return bytes.withUnsafeBufferPointer { report in
            parseScrollForceStatus(report)
        }
    }

    internal static func scrollForceSetTorqueParamsForTests(torque: UInt8, mode: UInt8) -> [UInt8] {
        return scrollForceSetTorqueParams(torque: torque, mode: mode)
    }

    internal static func parseForceSensingInfoForTests(_ bytes: [UInt8]) -> ForceSensingInfo? {
        return bytes.withUnsafeBufferPointer { report in
            parseForceSensingInfo(report)
        }
    }

    internal static func parseForceSensingCurrentForTests(_ bytes: [UInt8]) -> UInt16? {
        return bytes.withUnsafeBufferPointer { report in
            parseForceSensingCurrent(report)
        }
    }

    internal static func forceSensingSetCurrentParamsForTests(number: UInt8, current: UInt16) -> [UInt8] {
        return forceSensingSetCurrentParams(number: number, current: current)
    }

    internal static func forceSensingClampForTests(_ value: UInt16, info: ForceSensingInfo?) -> UInt16 {
        return forceSensingClamp(value, info: info)
    }

    #endif

    private func handleBLEUndivertGuardReportingResponseIfNeeded(
        _ report: UnsafeBufferPointer<UInt8>
    ) -> Bool {
        guard let response = Self.parseReportingResponse(report),
              let pending = pendingBLEUndivertGuardQueries.removeValue(forKey: response.cid) else {
            return false
        }

        let elapsed = Date().timeIntervalSince(pending.sentAt)
        updateDiscoveredControlReportingState(response, markQueried: true)
        #if DEBUG
        LogiTrace.log(
            "[StandardButtonGuard] RX GetControlReporting cid=\(String(format: "0x%04X", response.cid)) flags=\(String(format: "0x%02X", response.reportingFlags)) target=\(String(format: "0x%04X", response.targetCID)) after=\(String(format: "%.3fs", elapsed)) active=\(LogiTrace.cids(bleStandardUndivertGuardTargets))",
            device: deviceInfo.name
        )
        #endif

        _ = handleStandardButtonGuardState(response, reason: "standard-button guard GetControlReporting")
        return true
    }

    private func handleStandardButtonGuardState(_ state: ReportingResponse, reason: String) -> Bool {
        let targets = bleStandardButtonUndivertPlanner.undivertTargets(
            activeNativeFirstCIDs: bleStandardUndivertGuardTargets,
            reportingFlagsByCID: [state.cid: state.reportingFlags]
        )
        guard targets.contains(state.cid) else {
            #if DEBUG
            LogiTrace.log("[StandardButtonGuard] state did not require OFF cid=\(String(format: "0x%04X", state.cid)) flags=\(String(format: "0x%02X", state.reportingFlags))", device: deviceInfo.name)
            #endif
            return false
        }

        enforceStandardButtonGuard(cid: state.cid, reason: reason)
        return true
    }

    private func enforceStandardButtonGuard(cid: UInt16, reason: String) {
        guard connectionMode == .bleDirect,
              currentReceiverTargetIsConnected,
              bleStandardUndivertGuardTargets.contains(cid),
              let reprogIdx = featureIndex[Self.featureReprogV4] else {
            return
        }

        #if DEBUG
        LogiTrace.log("[StandardButtonGuard] \(reason) -> SetControlReporting OFF cid=\(String(format: "0x%04X", cid))", device: deviceInfo.name)
        LogiDebugPanel.log("[\(deviceInfo.name)] Standard-button guard cleared divert for \(String(format: "0x%04X", cid))")
        #endif
        setControlReporting(featureIndex: reprogIdx, cid: cid, divert: false)
    }

    private func updateDiscoveredControlReportingState(
        _ response: ReportingResponse,
        markQueried: Bool
    ) {
        guard let idx = discoveredControls.firstIndex(where: { $0.cid == response.cid }) else {
            return
        }
        discoveredControls[idx].reportingFlags = response.reportingFlags
        discoveredControls[idx].targetCID = response.targetCID
        if markQueried {
            discoveredControls[idx].reportingQueried = true
        }
        gestureController(slot: deviceIndex).noteDeviceReporting(cid: response.cid, reportingFlags: response.reportingFlags)
    }

    func handleInputReport(_ report: UnsafeBufferPointer<UInt8>) {
        guard report.count >= 7 else { return }
        guard report[0] == Self.hidppShortReportId || report[0] == Self.hidppLongReportId else { return }

        // Raw XY movement of a tracked hold arrives about 125 times a second: route it
        // before anything is formatted, logged or decoded.
        if handleTrackedRawXYMovement(report) { return }

        let hex = report.prefix(min(report.count, 20)).map { String(format: "%02X", $0) }.joined(separator: " ")
        let featureIdx = report[2]
        let functionId = report[3] >> 4
        // 响应回带 Mos 的 software id; 设备主动事件 (如 0x2121 ratchetSwitch) swid=0
        let isOwnResponse = (report[3] & 0x0F) == Self.hidppSoftwareId
        let rxDecoded = decodeReport(report)
        let isError = featureIdx == Self.hidppErrorFeatureIdx ||
            (connectionMode == .receiver && featureIdx == Self.hidpp10ErrorMsg)
        let rxType: LogEntryType = isError ? .error : .rx
        LogiDebugPanel.log(device: deviceInfo.name, type: rxType, message: "RX: \(hex)", decoded: rxDecoded)

        // 入站 peripheral 报文可能来自另一个已接管 slot(非当前路由游标). 若是, 临时把 deviceIndex
        // scoped 到 report[1] 处理该 slot 的状态, 函数退出时 defer 还原. 报文处理是同步的, 中途无
        // 定时器插入, 故 save/restore 安全. 详见 receiverReportRoute.
        var scopedSlotRestore: UInt8? = nil
        defer { if let saved = scopedSlotRestore { deviceIndex = saved } }

        // Receiver mode: route HID++ 1.0 responses first
        if connectionMode == .receiver {
            let devIdx = report[1]

            // HID++ 1.0 error (sub-ID 0x8F)
            if featureIdx == Self.hidpp10ErrorMsg {
                handleHIDPP10Error(report)
                return
            }

            // HID++ 1.0 register response from receiver (device index 0xFF)
            if devIdx == 0xFF && (featureIdx == Self.hidpp10GetRegister || featureIdx == Self.hidpp10GetLongRegister) {
                handleReceiverRegisterResponse(report)
                return
            }

            // The receiver took a register write (this app writes only its reporting flags).
            if devIdx == 0xFF && featureIdx == Self.hidpp10SetRegister {
                if report[3] == Self.receiverReportingFlags {
                    carryOut(connectionReports.writeTaken())
                }
                return
            }

            // Device disconnection notification (sub-ID 0x40): taken off the receiver
            if let slot = Self.receiverDisconnectionSlot(report) {
                handleDeviceDisconnectionNotification(slot: slot)
                return
            }

            // Device connection notification (sub-ID 0x41)
            if featureIdx == Self.hidpp10DeviceConnection {
                handleDeviceConnectionNotification(report)
                return
            }

            // Ping response from device behind receiver (IRoot function 1)
            if devIdx >= 1 && devIdx <= 6 && featureIdx == 0x00 && functionId == 1 && pendingSlotPings.contains(devIdx) {
                handleSlotPingResponse(devIdx: devIdx, report: report)
                return
            }

            // 部分接收器不会为初始扫描时休眠的设备补发 0x41. 第一条真实报文足以证明 slot 在线;
            // takeover 启动后丢弃该条尚无可靠 feature 映射的报文, 后续报文走正常路由.
            if handleReceiverPeripheralActivity(slot: devIdx) {
                return
            }

            // Peripheral(设备)报文按 report[1] 路由. 0xFF(register)/pending ping 已在上面处理.
            // 当前游标 slot 直接处理; 其它已接管 slot scoped 处理; 未知/未接管 slot drop.
            if devIdx >= 1 && devIdx <= 6 {
                switch Self.receiverReportRoute(
                    incomingSlot: devIdx,
                    currentSlot: deviceIndex,
                    managedSlots: receiverManagedSlots
                ) {
                case .processCurrent:
                    break
                case .processScoped(let slot):
                    scopedSlotRestore = deviceIndex
                    deviceIndex = slot
                case .drop:
                    LogiDebugPanel.log("[\(deviceInfo.name)] Report from slot \(devIdx) (current target=\(deviceIndex)) dropped (unmanaged)")
                    return
                }
            }
        }

        // HID++ 2.0 Error report
        if featureIdx == Self.hidppErrorFeatureIdx {
            let fields = Self.hidpp20ErrorFields(report)
            let originalFeatureIdx = fields?.featureIndex ?? 0
            let originalFuncId = fields?.functionId ?? 0
            let errorCode = fields?.errorCode ?? 0
            // Byte 4 of an error is function << 4 | software id of the refused request.
            let isOwnErrorRequest = report.count > 4 && report[4] & 0x0F == Self.hidppSoftwareId
            LogiDebugPanel.log("[\(deviceInfo.name)] HID++ Error: feat=\(String(format: "0x%02X", originalFeatureIdx)) func=\(originalFuncId) err=\(String(format: "0x%02X", errorCode))")

            // A cached index the mouse does not know (firmware update): drop the product's
            // cache entry so that the next connect looks the features up again.
            if Self.errorInvalidatesFeatureCache(
                errorCode: errorCode,
                originalFeatureIndex: originalFeatureIdx,
                originalFunctionByte: report.count > 4 ? report[4] : 0,
                cachedIndices: featureIndicesFromCache
            ) {
                dropFeatureIndexCache(errorCode: errorCode, featureIndex: originalFeatureIdx)
            }

            // Only an error for a getFeature of this app (IRoot fn0, own software id) fails a
            // discovery, and only the oldest one waiting for this device: answers and errors
            // come in request order. Errors for other features (a refused wheel SetState), a
            // ping or another client's request leave the discoveries alone.
            if report.count > 4,
               let entry = pendingDiscovery.takeRefused(
                   deviceIndex: report[1],
                   originalFeatureIndex: originalFeatureIdx,
                   originalFunctionByte: report[4]
               ) {
                finishDiscovery(entry, featureIndex: nil)
            }

            // 滚轮 feature (0x2110/0x2111) 的错误交给该 slot 的滚轮控制器
            if let wheel = wheelControllers[deviceIndex], originalFeatureIdx == wheel.featureIndex {
                wheel.handleError(functionId: originalFuncId, errorCode: errorCode)
            }

            // Battery / DPI / haptics / press force: the slot's basics controller
            if let basics = basicsControllers[deviceIndex], basics.owns(featureIndex: originalFeatureIdx) {
                basics.handleError(featureIndex: originalFeatureIdx, functionId: originalFuncId, errorCode: errorCode)
            }

            // REPROG_V4 query 错误: 跳过该 CID 继续下一个, 防止 Bolt receiver 上 query 链路卡死
            if let reprogIdx = featureIndex[Self.featureReprogV4],
               originalFeatureIdx == reprogIdx {
                switch originalFuncId {
                case 0 where pendingControlCount?.slot == deviceIndex && isOwnErrorRequest && scopedSlotRestore == nil:  // GetControlCount
                    controlCountDidFail(slot: deviceIndex, reason: String(format: "error 0x%02X", errorCode))
                case 1 where !reprogInitComplete:  // GetControlInfo
                    LogiDebugPanel.log("[\(deviceInfo.name)] GetControlInfo[\(reprogQueryIndex)] returned error, skipping")
                    advanceControlInfoQuery()
                case 2 where reportingQueryTimer != nil:  // GetControlReporting
                    LogiDebugPanel.log("[\(deviceInfo.name)] GetControlReporting[\(reportingQueryIndex)] returned error, skipping")
                    advanceReportingQuery()
                case LogiGestureProtocol.setReportingFunction:  // SetControlReporting: 等待中的 raw XY arm 视为被拒
                    gestureControllers[deviceIndex]?.handleReportingError()
                default:
                    break
                }
            }
            return
        }

        // IRoot response
        if featureIdx == 0x00 {
            // Only fn0 with this app's software id answers a getFeature (a late ping answer
            // is fn1, another client's answer has its own id); see LogiFeatureDiscoveryQueue.
            if let (entry, discoveredIndex) = pendingDiscovery.takeAnswer(report) {
                LogiDebugPanel.log("[\(deviceInfo.name)] IRoot response: \(String(format: "0x%04X", entry.featureId)) at index \(discoveredIndex.map { String(format: "0x%02X", $0) } ?? "none")")
                finishDiscovery(entry, featureIndex: discoveredIndex)
            }
            return
        }

        // REPROG_CONTROLS_V4
        if let reprogIdx = featureIndex[Self.featureReprogV4], featureIdx == reprogIdx {
            if Self.isGetControlReportingQueryResponse(report),
               handleBLEUndivertGuardReportingResponseIfNeeded(report) {
                return
            }

            if reportingQueryTimer != nil,
               Self.isGetControlReportingQueryResponse(report) {
                handleGetControlReportingResponse(report)
                return
            }

            if Self.isSetControlReportingAck(report) {
                handleSetControlReportingAck(report)
                return
            }

            if reprogInitComplete {
                // init 完成后: function 0 是按键事件; function 2/3 可能是状态通知或 ACK.
                if Self.isDivertedButtonEvent(report) {
                    handleDivertedButtonEvent(report)
                } else if Self.isReportingStateNotification(report) {
                    handleReportingStateNotification(report)
                } else if LogiGestureProtocol.isRawXYEvent(report) {
                    handleUntrackedRawXYEvent(report)
                }
                // 其他 function 1 / function 2 等忽略
            } else {
                // init 阶段: 按 function ID 路由
                switch functionId {
                case 0:
                    switch Self.reprogInitFunction0Route(report) {
                    case .divertedButtonEvent:
                        #if DEBUG
                        LogiTrace.log("[Session] init-phase REPROG func0 routed as button event", device: deviceInfo.name)
                        #endif
                        handleDivertedButtonEvent(report)
                    case .getControlCountResponse:
                        handleGetControlCountResponse(report)
                    case .ignored:
                        #if DEBUG
                        let softwareId = report[3] & 0x0F
                        LogiTrace.log(
                            "[Session] init-phase REPROG func0 ignored swid=\(String(format: "0x%02X", softwareId))",
                            device: deviceInfo.name
                        )
                        #endif
                    }
                case 1:
                    switch Self.reprogInitFunction1Route(report) {
                    case .getControlInfoResponse:
                        handleGetControlInfoResponse(report)
                    case .rawXYEvent:
                        // A control armed before this discovery is being held: its movement
                        // shares function 1 with GetControlInfo but is no answer to it.
                        handleUntrackedRawXYEvent(report)
                    }
                // Redundant fallback: normal reporting queries have a timer and route above.
                case 2 where Self.isGetControlReportingQueryResponse(report):
                    handleGetControlReportingResponse(report)
                default: break  // ACK 等直接忽略, 不当作 button event
                }
            }
            return
        }

        // DeviceNameType (0x0005) fn2 getDeviceType 响应: report[4] = 权威设备类型枚举.
        // 纯显示用: 存到当前 slot 的 hidppDeviceType, 刷新 sidebar. (deviceIndex 此刻已 scoped 到该 slot.)
        if isOwnResponse, let dntIdx = featureIndex[Self.featureDeviceNameType], featureIdx == dntIdx,
           functionId == LogiDeviceNameRead.lengthFunction || functionId == LogiDeviceNameRead.nameFunction {
            handleDeviceNameResponse(functionId: functionId, report: report)
            return
        }
        if let dntIdx = featureIndex[Self.featureDeviceNameType], featureIdx == dntIdx, functionId == 2 {
            if report.count > 4,
               let devIdx = receiverPairedDevices.firstIndex(where: { $0.slot == deviceIndex }) {
                receiverPairedDevices[devIdx].hidppDeviceType = report[4]
                LogiDebugPanel.log(device: deviceInfo.name, type: .info,
                    message: "Slot \(deviceIndex) device type: \(receiverPairedDevices[devIdx].hidppDeviceTypeName ?? "--")")
                NotificationCenter.default.post(name: LogiSessionManager.sessionChangedNotification, object: nil)
            }
            return
        }

        // Basic mouse settings: the slot's controller gets its answers on the battery, DPI,
        // haptic and press force features, and the battery events. No return: haptic and
        // force sensing answers go on to the blocks below (gesture cues, debug panel), DPI
        // answers to the DPI cycle action.
        if let basics = basicsControllers[deviceIndex], basics.owns(featureIndex: featureIdx) {
            if isOwnResponse {
                basics.handleResponse(featureIndex: featureIdx, functionId: functionId, report: Array(report))
            } else {
                basics.handleEvent(featureIndex: featureIdx, functionId: functionId,
                                   softwareId: report[3] & 0x0F, report: Array(report))
            }
        }

        // Haptic (0x19B0) responses: fn0=GetCapabilities, fn1=GetState; fn2/fn4 仅为 ACK
        if let hapticIdx = featureIndex[Self.featureHaptic], featureIdx == hapticIdx {
            // Gesture cues keep their own per-slot copy of "enabled" and the waveform mask.
            if isOwnResponse {
                gestureControllers[deviceIndex]?.handleHapticResponse(functionId: functionId, report: Array(report))
            }
            switch functionId {
            case 0:
                guard let mask = Self.parseHapticCapabilitiesMask(report) else { break }
                hapticWaveformMask = mask
                let names = HIDPPInfo.hapticWaveforms
                    .filter { (mask >> UInt32($0.id)) & 1 != 0 }
                    .map { $0.name }
                LogiDebugPanel.log("[\(deviceInfo.name)] HAPTIC capabilities: \(names.count) waveforms [\(names.joined(separator: ", "))]")
                NotificationCenter.default.post(name: Self.hapticStateDidChangeNotification, object: self)
            case 1:
                guard let state = Self.parseHapticState(report) else { break }
                hapticState = state
                hapticRawState = LogiHapticSettingsProtocol.parseState(Array(report))
                LogiDebugPanel.log("[\(deviceInfo.name)] HAPTIC state: \(state.enabled ? "on" : "off"), level=\(state.level)\(state.fourLevelsOnly ? " (4-level device)" : "")")
                NotificationCenter.default.post(name: Self.hapticStateDidChangeNotification, object: self)
            default:
                break  // SetState / PlayWaveform 的 ACK
            }
            return
        }

        // Scroll wheel (0x2110 / 0x2111): 本 slot 的滚轮控制器解析模式/阈值/torque.
        // 0x2111 的报文继续落到下面的 Scroll Force 块, 让 Debug 面板状态保持同步.
        if isOwnResponse, let wheel = wheelControllers[deviceIndex], featureIdx == wheel.featureIndex {
            wheel.handleResponse(functionId: functionId, report: Array(report))
            if wheel.feature == .smartShift { return }
        }

        // HiResWheel (0x2121) ratchetSwitch 事件 (event 1, swid 0): 模式切换键改了滚轮模式.
        // data[0] = 1 ratchet / 0 free-spin (Solaar notifications.py). 不信任事件本身
        // (SmartShift 自动脱开时语义未确认), 合并后从 0x2110/0x2111 重读权威状态.
        if !isOwnResponse, functionId == 1,
           let hiresIdx = featureIndex[Self.featureHiResWheel], featureIdx == hiresIdx {
            LogiDebugPanel.log("[\(deviceInfo.name)] Wheel ratchet switch event: \(report[4] == 1 ? "ratchet" : "free-spin")")
            scheduleWheelStatusRefresh(slot: deviceIndex)
            return
        }

        // Scroll Force (0x2111) responses: fn0=Capabilities, fn1=Status; fn2 仅为 ACK
        if let scrollForceIdx = featureIndex[Self.featureSmartShiftEnhanced], featureIdx == scrollForceIdx {
            switch functionId {
            case 0:
                guard let tunable = Self.parseScrollForceTunableTorque(report) else { break }
                scrollForceTunableTorque = tunable
                LogiDebugPanel.log("[\(deviceInfo.name)] ScrollForce capabilities: tunable torque \(tunable ? "supported" : "unsupported")")
                NotificationCenter.default.post(name: Self.scrollForceStateDidChangeNotification, object: self)
            case 1:
                guard let status = Self.parseScrollForceStatus(report) else { break }
                scrollForceStatus = status
                LogiDebugPanel.log("[\(deviceInfo.name)] ScrollForce status: mode=\(status.mode), torque=\(status.torque)")
                NotificationCenter.default.post(name: Self.scrollForceStateDidChangeNotification, object: self)
            default:
                break  // SetState 的 ACK
            }
            return
        }

        // Force Sensing (0x19C0) responses: fn1=ButtonInfo, fn2=Current; fn3 仅为 ACK
        if let forceSensingIdx = featureIndex[Self.featureForceSensing], featureIdx == forceSensingIdx {
            switch functionId {
            case 1:
                guard let info = Self.parseForceSensingInfo(report) else { break }
                forceSensingInfo = info
                LogiDebugPanel.log("[\(deviceInfo.name)] ForceSensing info: changeable=\(info.changeable), range=\(info.minValue)-\(info.maxValue), default=\(info.defaultValue)")
                NotificationCenter.default.post(name: Self.forceSensingStateDidChangeNotification, object: self)
            case 2:
                guard let current = Self.parseForceSensingCurrent(report) else { break }
                forceSensingCurrent = current
                LogiDebugPanel.log("[\(deviceInfo.name)] ForceSensing current: \(current)")
                NotificationCenter.default.post(name: Self.forceSensingStateDidChangeNotification, object: self)
            default:
                break  // ButtonCount / SetConfig 的 ACK
            }
            return
        }

        // DPI list response (getSensorDpiList, function 1)
        if isOwnResponse, let listQuery = pendingDPIListQuery, featureIdx == listQuery.featureIndex && functionId == 1 {
            pendingDPIListQuery = nil
            guard pendingActions.take(.dpiList, now: Date()) else {
                LogiDebugPanel.log("[\(deviceInfo.name)] DPI list arrived too late for the button press; DPI cycle skipped")
                return
            }
            // Same parser as the pointer speed setting: ranges with a step, plain lists and a
            // mix of both (the inline parser here handled only one range or one plain list).
            if let list = LogiPointerSpeedProtocol.parseDPIList(Array(report)) {
                dpiSteps = list.values.compactMap { UInt16(exactly: $0) }
                LogiDebugPanel.log("[\(deviceInfo.name)] DPI list: \(LogiPointerSpeedProtocol.describe(list))")
            } else {
                dpiSteps.removeAll()
                LogiDebugPanel.log("[\(deviceInfo.name)] DPI list unreadable; DPI cycle skipped")
                return
            }

            // 继续: 查询当前 DPI 并执行切换
            sendRequest(featureIndex: listQuery.featureIndex, functionId: 2, params: [0x00])
            pendingDPICycle = (listQuery.featureIndex, listQuery.direction)
            pendingActions.arm(.dpiCurrent, now: Date())
            return
        }

        // DPI response (pending cycle)
        if isOwnResponse, let dpiInfo = pendingDPICycle, featureIdx == dpiInfo.featureIndex && functionId == 2 {
            pendingDPICycle = nil
            // An answer that comes long after the press (the mouse did not answer then, and
            // now another read of the DPI is answered) must not change the pointer speed.
            guard pendingActions.take(.dpiCurrent, now: Date()) else {
                LogiDebugPanel.log("[\(deviceInfo.name)] DPI arrived too late for the button press; DPI cycle skipped")
                return
            }
            // byte[4]=sensorIdx, byte[5-6]=currentDPI, byte[7-8]=default (big-endian; 0 = default)
            guard let parsed = LogiPointerSpeedProtocol.parseCurrent(Array(report)),
                  let curDPI = UInt16(exactly: parsed.current) else {
                LogiDebugPanel.log("[\(deviceInfo.name)] DPI unreadable; DPI cycle skipped")
                return
            }

            // The next stop (LogiPointerSpeedProtocol.cycleTarget), not the next value of
            // the mouse's list: an MX Master lists 200...8000 in steps of 50, and one press
            // from 1600 to 1650 cannot be felt.
            let target = LogiPointerSpeedProtocol.cycleTarget(
                from: Int(curDPI), up: dpiInfo.direction == .up, choices: dpiSteps.map(Int.init)
            )
            let newDPI = target.flatMap { UInt16(exactly: $0) } ?? curDPI

            if newDPI != curDPI {
                LogiDebugPanel.log("[\(deviceInfo.name)] DPI: \(curDPI) -> \(newDPI)")
                // setSensorDpi: function 3, params: sensorIdx(1) + dpi(2)
                if let params = LogiPointerSpeedProtocol.setParams(dpi: Int(newDPI)) {
                    sendRequest(featureIndex: dpiInfo.featureIndex, functionId: LogiPointerSpeedProtocol.setFunction, params: params)
                    noteActionWrite("DPI \(dpiInfo.direction == .up ? "up" : "down") \(curDPI) -> \(newDPI)")
                }
            } else {
                LogiDebugPanel.log("[\(deviceInfo.name)] DPI: \(curDPI) (already at limit)")
            }
            return
        }

        // PointerSpeed response
        if let speedIdx = featureIndex[Self.featurePointerSpeed], featureIdx == speedIdx {
            if functionId == 0 && isOwnResponse && pendingActions.take(.pointerSpeed, now: Date()) {  // getPointerSpeed (fn0) 响应
                let currentHi = report[4]
                let currentLo = report[5]
                let currentSpeed = (UInt16(currentHi) << 8) | UInt16(currentLo)

                // Cycle through presets: 0.5x(128) → 1x(256) → 1.5x(384) → 2x(512→clamped to 511) → 0.5x
                let presets: [UInt16] = [0x0080, 0x0100, 0x0180, 0x01FF]
                let nextSpeed: UInt16
                if let idx = presets.firstIndex(where: { $0 > currentSpeed }) {
                    nextSpeed = presets[idx]
                } else {
                    nextSpeed = presets[0]  // Wrap around to 0.5x
                }

                sendRequest(featureIndex: speedIdx, functionId: 1,  // setPointerSpeed (fn1)
                            params: [UInt8(nextSpeed >> 8), UInt8(nextSpeed & 0xFF)])
                let speedStr = String(format: "%.1fx", Double(nextSpeed) / 256.0)
                LogiDebugPanel.log("[\(deviceInfo.name)] PointerSpeed: \(speedStr)")
                noteActionWrite("pointer speed \(String(format: "0x%04X", currentSpeed)) -> \(speedStr)")
                return
            }
        }
    }

    private func handleGetControlCountResponse(_ report: UnsafeBufferPointer<UInt8>) {
        // Only the answer this slot waits for: a second answer (the first request's, late,
        // after it was sent again) would restart the control queries in the middle.
        guard pendingControlCount?.slot == deviceIndex else {
            LogiDebugPanel.log(device: deviceInfo.name, type: .warning, message: "GetControlCount answer nobody waits for ignored")
            return
        }
        cancelControlCountWait()
        reprogControlCount = Int(report[4])
        reprogQueryIndex = 0
        controlInfoRetryCounts.removeAll()
        discoveredControls.removeAll()
        LogiDebugPanel.log("[\(deviceInfo.name)] GetControlCount = \(reprogControlCount)")
        if reprogControlCount > 0, let idx = featureIndex[Self.featureReprogV4] {
            sendGetControlInfo(featureIndex: idx, index: 0)
        } else {
            // 设备声明 0 个可编程控件: discovery 走到终点, 记为握手完成.
            markHandshakeComplete()
            NotificationCenter.default.post(name: LogiSessionManager.reportingQueryDidCompleteNotification, object: nil)
            LogiSessionManager.shared.recomputeAndNotifyActivityState()
            // 无可 divert 控件, 但仍需推进接管 sweep 到下一个 slot.
            receiverSlotDiscoveryDidFinish(didDivert: false)
        }
    }

    private func handleGetControlInfoResponse(_ report: UnsafeBufferPointer<UInt8>) {
        guard report.count >= 11 else { return }
        let cid = (UInt16(report[4]) << 8) | UInt16(report[5])
        let taskId = (UInt16(report[6]) << 8) | UInt16(report[7])
        let flags1 = report[8]
        let flags2: UInt8 = report.count > 12 ? report[12] : 0
        let flags = UInt16(flags1) | (UInt16(flags2) << 8)
        // Solaar: bit 4 = reprogrammable (0x10), bit 5 = divertable (0x20)
        let isDivertable = (flags & 0x20) != 0

        // 超时重试后原请求的迟到响应会与重试响应各到一次: 第二个不是"下一个索引"的答案,
        // 忽略且不推进, 否则同一控件被记两次且查询索引错位.
        if Self.isDuplicateControlInfo(cid: cid, known: discoveredControls.map { $0.cid }) {
            LogiDebugPanel.log(
                device: deviceInfo.name,
                type: .warning,
                message: "GetControlInfo duplicate response for CID \(String(format: "0x%04X", cid)) ignored (late reply after a retry)"
            )
            return
        }

        discoveredControls.append(ControlInfo(cid: cid, taskId: taskId, flags: flags, isDivertable: isDivertable))
        LogiDebugPanel.log("[\(deviceInfo.name)] Control[\(reprogQueryIndex)]: CID=\(String(format: "0x%04X", cid)) flags=\(String(format: "0x%04X", flags)) divertable=\(isDivertable)")

        advanceControlInfoQuery()
    }

    // MARK: - GetControlReporting Query (function 2)

    /// 重跑 GetControlReporting 循环,刷新所有 control 的 reportingFlags / targetCID.
    /// 用于 UI 轮询冲突状态时调用(通过 LogiSessionManager.refreshReportingStates 节流).
    /// 不重新发现 feature / control,开销小(只是 N 个 HID++ 请求).
    /// 前提:初始 discovery 必须已完成;否则无 featureIndex / discoveredControls,直接跳过.
    /// 进行中(timer 未 nil)也跳过,避免 reportingQueryIndex 被重置导致错位.
    func refreshReportingState() {
        guard connectionMode != .unsupported,
              currentReceiverTargetIsConnected,
              !discoveredControls.isEmpty,
              featureIndex[Self.featureReprogV4] != nil else { return }
        // Only a mouse: the re-read ends in a usage pass (divertBoundControls), and with the
        // cursor resting on a keyboard it used to mark that keyboard as ready for diverts.
        guard slotIsMouse(deviceIndex) else { return }
        if reportingQueryTimer != nil { return }
        LogiDebugPanel.log("[\(deviceInfo.name)] Refreshing reporting state (throttled)")
        startReportingQuery(afterDiscovery: false)
    }

    /// 开始逐个查询按键的 reporting 状态
    /// - Parameter afterDiscovery: false for a refresh of the UI; only a query that ends a
    ///   discovery looks for leftover diverts.
    private func startReportingQuery(afterDiscovery: Bool = true) {
        reportingQueryFollowsDiscovery = afterDiscovery
        pendingBLEUndivertGuardQueries.removeAll()
        reportingQueryIndex = 0
        for index in discoveredControls.indices {
            discoveredControls[index].reportingQueried = false
        }
        guard !discoveredControls.isEmpty, let idx = featureIndex[Self.featureReprogV4] else {
            divertBoundControls()
            // 镜像 advanceReportingQuery 正常终态: 即使 controls 为空也必须 post,
            // 否则 Self-Test Wizard 的 "wait reportingDidComplete" 会无限挂起.
            NotificationCenter.default.post(name: LogiSessionManager.reportingQueryDidCompleteNotification, object: nil)
            LogiSessionManager.shared.recomputeAndNotifyActivityState()
            return
        }
        LogiDebugPanel.log("[\(deviceInfo.name)] Querying reporting state for \(discoveredControls.count) controls...")
        sendGetControlReporting(featureIndex: idx, controlIndex: 0)
        // timer 刚被创建, 通知 Manager 汇总 activity 状态 (幂等, 无变化时不 post)
        LogiSessionManager.shared.recomputeAndNotifyActivityState()
    }

    private func sendGetControlReporting(featureIndex: UInt8, controlIndex: Int) {
        guard controlIndex < discoveredControls.count else { return }
        let cid = discoveredControls[controlIndex].cid
        // GetControlReporting: function 2, params: CID(2)
        sendRequest(featureIndex: featureIndex, functionId: 2,
                    params: [UInt8(cid >> 8), UInt8(cid & 0xFF)])
        divertLedger.noteQuerySent(cid: cid)
        scheduleReportingTimeout(index: controlIndex)
    }

    private func scheduleReportingTimeout(index: Int) {
        reportingQueryTimer?.invalidate()
        reportingQueryTimer = Timer.scheduledTimer(withTimeInterval: Self.reprogQueryTimeout, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            LogiDebugPanel.log("[\(self.deviceInfo.name)] GetControlReporting[\(index)] timed out, skipping")
            self.advanceReportingQuery()
        }
    }

    /// 推进 reporting 查询 (正常响应 / 错误 / 超时 都调此方法)
    private func advanceReportingQuery() {
        reportingQueryTimer?.invalidate()
        reportingQueryTimer = nil
        reportingQueryIndex += 1
        if reportingQueryIndex < discoveredControls.count, let reprogIdx = featureIndex[Self.featureReprogV4] {
            sendGetControlReporting(featureIndex: reprogIdx, controlIndex: reportingQueryIndex)
        } else {
            LogiDebugPanel.log("[\(deviceInfo.name)] Reporting query complete")
            divertBoundControls()
            // 先让 divertBoundControls 置 reprogInitComplete=true / handshakeComplete=true, 再通知
            // 观察者, 避免 main-queue observer 在状态翻转前就读到 stale 值.
            NotificationCenter.default.post(name: LogiSessionManager.reportingQueryDidCompleteNotification, object: nil)
            // reportingQueryTimer 此时已 nil, 若 discoveryInFlight 也为 false 则 activity 真正结束.
            LogiSessionManager.shared.recomputeAndNotifyActivityState()
        }
    }

    private func handleGetControlReportingResponse(_ report: UnsafeBufferPointer<UInt8>) {
        guard let response = Self.parseReportingResponse(report) else { return }
        let expectedCID = reportingQueryIndex < discoveredControls.count
            ? discoveredControls[reportingQueryIndex].cid
            : nil
        let matchesExpectedCID = expectedCID == response.cid

        updateDiscoveredControlReportingState(response, markQueried: matchesExpectedCID)

        let cidName = LogiCIDDirectory.name(forCID: response.cid)
        let flagParts = Self.reportingFlagNames(response.reportingFlags)
        let flagStr = flagParts.isEmpty ? "none" : flagParts.joined(separator: ",")
        let targetStr = response.targetCID != response.cid && response.targetCID != 0
            ? " -> \(String(format: "0x%04X", response.targetCID))(\(LogiCIDDirectory.name(forCID: response.targetCID)))"
            : ""
        LogiDebugPanel.log("[\(deviceInfo.name)] Reporting[\(cidName)]: flags=\(flagStr)\(targetStr)")

        guard matchesExpectedCID else {
            let expected = expectedCID.map { String(format: "0x%04X", $0) } ?? "none"
            LogiDebugPanel.log("[\(deviceInfo.name)] Stale GetControlReporting response for 0x\(String(format: "%04X", response.cid)) dropped (expected \(expected))")
            return
        }

        // 继续查询下一个 (或完成)
        advanceReportingQuery()
    }

    private func handleSetControlReportingAck(_ report: UnsafeBufferPointer<UInt8>) {
        guard let ack = Self.parseSetControlReportingAck(report) else { return }
        let isOwnAck = consumePendingSetControlReportingAck(ack)
        // An echoed arm request (0x33) makes the next press of the control device-tracked.
        gestureControllers[deviceIndex]?.handleReportingAcknowledgement(cid: ack.cid, flags: ack.flagsByte)
        #if DEBUG
        LogiTrace.log(
            "[Session] handle SetReporting ACK cid=\(String(format: "0x%04X", ack.cid)) flags=\(String(format: "0x%02X", ack.flagsByte)) target=\(String(format: "0x%04X", ack.targetCID)) own=\(isOwnAck) lastApplied=\(LogiTrace.cids(lastApplied)) diverted=\(LogiTrace.cids(divertedCIDs))",
            device: deviceInfo.name
        )
        #endif
        guard let cid = Self.reassertionCIDForSetControlReportingAck(
            lastApplied: lastApplied,
            divertedCIDs: divertedCIDs,
            ack: ack,
            isOwnAck: isOwnAck
        ) else {
            #if DEBUG
            LogiTrace.log("[Session] SetReporting ACK did not imply external clear", device: deviceInfo.name)
            #endif
            return
        }

        handleExternallyClearedDivert(cid: cid, reason: "SetControlReporting ACK")
    }

    private func handleReportingStateNotification(_ report: UnsafeBufferPointer<UInt8>) {
        guard let state = Self.parseReportingStateNotification(report) else { return }
        updateDiscoveredControlReportingState(state, markQueried: true)
        #if DEBUG
        LogiTrace.log(
            "[Session] reporting notification cid=\(String(format: "0x%04X", state.cid)) flags=\(String(format: "0x%02X", state.reportingFlags)) target=\(String(format: "0x%04X", state.targetCID)) lastApplied=\(LogiTrace.cids(lastApplied)) diverted=\(LogiTrace.cids(divertedCIDs))",
            device: deviceInfo.name
        )
        #endif
        if handleStandardButtonGuardState(state, reason: "native-first reporting notification") {
            return
        }
        guard let cid = Self.reassertionCIDForReportingState(
                lastApplied: lastApplied,
                divertedCIDs: divertedCIDs,
                state: state
              ) else {
            #if DEBUG
            LogiTrace.log("[Session] reporting notification did not imply external clear", device: deviceInfo.name)
            #endif
            return
        }

        handleExternallyClearedDivert(cid: cid, reason: "reporting notification")
    }

    private func handleExternallyClearedDivert(cid: UInt16, reason: String) {
        #if DEBUG
        LogiTrace.log(
            "[Session] external clear detected reason=\(reason) cid=\(String(format: "0x%04X", cid)) before lastApplied=\(LogiTrace.cids(lastApplied)) diverted=\(LogiTrace.cids(divertedCIDs))",
            device: deviceInfo.name
        )
        #endif
        lastApplied.remove(cid)
        divertedCIDs.remove(cid)
        releaseActiveButtonState(for: [cid], reason: "divert cleared externally")
        gestureControllers[deviceIndex]?.forget(cid: cid)
        let mode = LogiSessionManager.shared.recordExternalClear(for: ownershipKey(forCID: cid))
        guard Self.shouldReassertAfterExternalClear(mode: mode) else {
            LogiDebugPanel.log("[\(deviceInfo.name)] External \(reason) cleared divert for \(String(format: "0x%04X", cid)); reassert suspended (\(mode.debugLabel))")
            return
        }
        LogiDebugPanel.log("[\(deviceInfo.name)] External \(reason) cleared divert for \(String(format: "0x%04X", cid)); scheduling reassert")
        scheduleDivertReassertion()
    }

    private static func shouldReassertAfterExternalClear(mode: LogiButtonDeliveryMode) -> Bool {
        return shouldUseHIDPPDelivery(mode: mode)
    }

    #if DEBUG
    internal static func shouldReassertAfterExternalClearForTests(mode: LogiButtonDeliveryMode) -> Bool {
        return shouldReassertAfterExternalClear(mode: mode)
    }
    #endif

    private func scheduleDivertReassertion() {
        guard divertReassertionWorkItem == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.divertReassertionWorkItem = nil
            self.reassertDesiredDiverts()
        }
        divertReassertionWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.divertReassertionDelay, execute: item)
    }

    private func reassertDesiredDiverts() {
        #if DEBUG
        LogiTrace.log("[Session] reassertDesiredDiverts recording=\(LogiCenter.shared.isRecording)", device: deviceInfo.name)
        #endif
        // One pass over every mouse of this session; the pass itself skips a slot that is
        // not ready or not connected, and keeps the recording set while a button is recorded.
        primeFromRegistry()
    }

    /// 初始化完成后: 按 binding 状态 divert 对应按键.
    /// 不再扫全部 divertable 控件 - 避免覆盖 Logitech Options+ 等第三方进程的 divert 设置.
    /// Stale diverts: a run that ended without giving the buttons back (a crash, also during
    /// key recording, which diverts every divertable control) leaves them diverted on the
    /// mouse (tmpDivert lasts until the mouse is switched off). After a discovery the prime
    /// below gives back each control the query found diverted that Scrollio does not want,
    /// but only while "Let Scrollio manage this mouse" is on: that switch tells the user not
    /// to run Logi Options+ at the same time, so such a divert is a leftover. While it is off
    /// they are left alone and logged (`staleDivertDecision`).
    /// The left and the right button are the exception: found diverted, they are given back
    /// whatever the switch says (Scrollio never diverts them, and a diverted click that no
    /// program handles is a dead button).
    /// While a button is being recorded the prime keeps the recording set instead
    /// (`applyUsageToCursorSlot`).
    private func divertBoundControls() {
        // Never for a slot that is not a mouse (its discovery ends before the reporting
        // query; this is the second lock on the same door).
        guard slotIsMouse(deviceIndex) else {
            finishDiscoveryOfNonMouseSlot()
            return
        }
        reconcileAppliedDivertsWithQueriedState()
        reprogInitComplete = true
        handshakeComplete = true
        setDiscoveryInFlight(false)
        #if DEBUG
        LogiTrace.log("[Session] divertBoundControls prime registry discovered=\(discoveredControls.count)", device: deviceInfo.name)
        #endif
        staleDivertCheckSlot = reportingQueryFollowsDiscovery ? deviceIndex : nil
        reportingQueryFollowsDiscovery = false
        primeFromRegistry()
        staleDivertCheckSlot = nil
        LogiDebugPanel.log("[\(deviceInfo.name)] Init complete, listening for button events")
        // 正常 init 终点直接赋值 handshakeComplete, 不经过 markHandshakeComplete.
        // sweep 中: 由 receiverSlotDiscoveryDidFinish 决定推进下一个 slot 还是(巡检 slot)探测可选功能;
        // 非 sweep(BLE / 手动 rediscover): 直接探测可选功能(probeOptionalFeatures 自带 once 守卫).
        if receiverSweepActive {
            receiverSlotDiscoveryDidFinish(didDivert: true)
        } else {
            probeOptionalFeatures()
            // 非 sweep 发现(refresh / 手动 rediscover)完成: 排空热插拔期间入队的 slot.
            pumpPendingDivertQueue()
        }
    }

    private var queriedControlStates: [QueriedControlState] {
        return discoveredControls.map {
            QueriedControlState(
                cid: $0.cid,
                reportingFlags: $0.reportingFlags,
                reportingQueried: $0.reportingQueried
            )
        }
    }

    private func reconcileAppliedDivertsWithQueriedState() {
        // Only an answer newer than Scrollio's last write for a control can show that the
        // mouse dropped its divert (LogiDivertLedger.dropLost). Answers from before a write
        // (a recording that began while the buttons' state was being re-read) used to make
        // Scrollio forget buttons it had just diverted; nothing gave those back any more.
        var ledger = divertLedger
        let lostCIDs = ledger.dropLost(queriedControls: queriedControlStates)
        guard !lostCIDs.isEmpty else { return }

        releaseActiveButtonState(for: lostCIDs, reason: "divert lost")
        divertLedger = ledger
        for cid in lostCIDs.sorted() {
            gestureControllers[deviceIndex]?.forget(cid: cid)
            let mode = LogiSessionManager.shared.recordExternalClear(for: ownershipKey(forCID: cid))
            LogiDebugPanel.log(
                "[\(deviceInfo.name)] Reconciled lost divert state for CID \(String(format: "0x%04X", cid)); delivery=\(mode.debugLabel)"
            )
        }
    }

    private static func reconciledDivertState(
        lastApplied: Set<UInt16>,
        divertedCIDs: Set<UInt16>,
        queriedControls: [QueriedControlState]
    ) -> (lastApplied: Set<UInt16>, divertedCIDs: Set<UInt16>, lostCIDs: Set<UInt16>) {
        var ledger = LogiDivertLedger()
        ledger.lastApplied = lastApplied
        ledger.diverted = divertedCIDs
        let lostCIDs = ledger.dropLost(queriedControls: queriedControls)
        return (lastApplied: ledger.lastApplied, divertedCIDs: ledger.diverted, lostCIDs: lostCIDs)
    }

    /// What one discovery does with the controls the mouse reports diverted although Scrollio
    /// does not want them diverted.
    struct StaleDivertDecision: Equatable {
        /// Given back now (SetControlReporting, divert off).
        var giveBack: Set<UInt16> = []
        /// Left as they are: "Let Scrollio manage this mouse" is off, so they may belong to
        /// another app (Logi Options+).
        var leftAlone: Set<UInt16> = []
    }

    /// Pure: the controls that GetControlReporting found temporarily diverted (bit 0) and
    /// that are neither wanted nor given back by the usual writes anyway. While keys are
    /// recorded Scrollio may want every divertable control: nothing is touched then.
    static func staleDivertDecision(
        queriedControls: [QueriedControlState],
        wanted: Set<UInt16>,
        undivertedAnyway: Set<UInt16>,
        managed: Bool,
        recording: Bool
    ) -> StaleDivertDecision {
        let temporaryDivert: UInt8 = 0x01
        let stale = Set(queriedControls.compactMap { control -> UInt16? in
            guard control.reportingQueried,
                  control.reportingFlags & temporaryDivert != 0,
                  !wanted.contains(control.cid),
                  !undivertedAnyway.contains(control.cid) else {
                return nil
            }
            return control.cid
        })
        // The left and the right button are given back whatever the switch says and also
        // while a button is recorded: Scrollio never diverts them (LogiButtonDeliveryPolicy
        // .primaryClickCIDs), and a diverted click that no program handles is a dead button.
        let primary = stale.intersection(LogiButtonDeliveryPolicy.primaryClickCIDs)
        guard !recording else { return StaleDivertDecision(giveBack: primary) }
        return managed
            ? StaleDivertDecision(giveBack: stale)
            : StaleDivertDecision(giveBack: primary, leftAlone: stale.subtracting(primary))
    }

    /// The one `logi` line of a discovery that found stale diverts; nil when it found none.
    static func staleDivertLine(_ decision: StaleDivertDecision, name: (UInt16) -> String) -> String? {
        func count(_ cids: Set<UInt16>) -> String {
            return cids.count == 1 ? "1 button" : "\(cids.count) buttons"
        }
        func names(_ cids: Set<UInt16>) -> String {
            return cids.sorted().map { String(format: "0x%04X ", $0) + name($0) }.joined(separator: ", ")
        }
        var parts: [String] = []
        if !decision.giveBack.isEmpty {
            let cids = decision.giveBack
            // With the switch off only the left and the right button are ever given back.
            let reason = cids.isSubset(of: LogiButtonDeliveryPolicy.primaryClickCIDs)
                ? "the left and the right button are given back whatever the switch says"
                : "manage switch on"
            parts.append("Gave back \(count(cids)) the mouse still had diverted from an earlier run "
                + "(Scrollio does not use \(cids.count == 1 ? "it" : "them"); \(reason)): \(names(cids))")
        }
        if !decision.leftAlone.isEmpty {
            let cids = decision.leftAlone
            parts.append("Left \(count(cids)) diverted that Scrollio does not use (manage switch off: another app may "
                + "use \(cids.count == 1 ? "it" : "them"); a leftover is freed by switching the mouse off and on): \(names(cids))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: ". ")
    }

    #if DEBUG
    internal static func reconciledDivertStateForTests(
        lastApplied: Set<UInt16>,
        divertedCIDs: Set<UInt16>,
        queriedControls: [QueriedControlState]
    ) -> (lastApplied: Set<UInt16>, divertedCIDs: Set<UInt16>) {
        let result = reconciledDivertState(
            lastApplied: lastApplied,
            divertedCIDs: divertedCIDs,
            queriedControls: queriedControls
        )
        return (lastApplied: result.lastApplied, divertedCIDs: result.divertedCIDs)
    }
    #endif

    /// Recording: every button that can be diverted is diverted, on every mouse of this
    /// session (see `usageSlots`).
    func temporarilyDivertAll() {
        forEachSlot(usageSlots) {
            temporarilyDivertAllOnCursorSlot()
        }
    }

    private func temporarilyDivertAllOnCursorSlot() {
        // A slot whose controls are not all known yet gets its recording set when its
        // discovery ends (divertBoundControls primes, and the pass sees the recording). A
        // slot that is not a mouse never gets here with `reprogInitComplete` set.
        guard reprogInitComplete else { return }
        guard let idx = featureIndex[Self.featureReprogV4] else { return }
        guard currentReceiverTargetIsConnected else { return }
        // Recording never diverts the keys of a device that is not a mouse.
        guard slotIsMouse(deviceIndex) else { return }
        let divertable = Set(discoveredControls.filter { $0.isDivertable }.map { $0.cid })
        let plan = Self.recordingDivertPlan(
            divertableCIDs: divertable,
            lastApplied: lastApplied,
            transport: LogiTransportIdentity(connectionMode),
            policy: LogiButtonDeliveryPolicy.default
        )
        #if DEBUG
        LogiTrace.log(
            "[Session] temporarilyDivertAll divertable=\(LogiTrace.cids(divertable)) desired=\(LogiTrace.cids(plan.desired)) toDivert=\(LogiTrace.cids(plan.toDivert)) toUndivert=\(LogiTrace.cids(plan.toUndivert)) beforeLastApplied=\(LogiTrace.cids(lastApplied))",
            device: deviceInfo.name
        )
        #endif
        releaseActiveButtonState(for: plan.toUndivert, reason: "recording uses native mouse events")
        for cid in plan.toAssert.sorted() {
            setControlReporting(featureIndex: idx, cid: cid, divert: true)
        }
        for cid in plan.toUndivert.sorted() {
            setControlReporting(featureIndex: idx, cid: cid, divert: false)
        }
        // Sync lastApplied with the recording target set so restoreDivertToBindings'
        // applyUsage diff (toUndivert = lastApplied - targetCIDs) can correctly
        // compute toUndivert for recording-only HID++ CIDs after recording ends.
        self.lastApplied = plan.desired
        LogiDebugPanel.log("[\(deviceInfo.name)] Temporarily diverted \(plan.desired.count)/\(divertable.count) controls (recording mode; re-asserted \(plan.toAssert.subtracting(plan.toDivert).count) already-applied)")
    }

    /// Recording ended (the manager cleared its flag first): back to the buttons that have
    /// a binding, on every mouse of this session.
    func restoreDivertToBindings() {
        #if DEBUG
        LogiTrace.log("[Session] restoreDivertToBindings via registry", device: deviceInfo.name)
        #endif
        primeFromRegistry()
    }

    private func handleDivertedButtonEvent(_ report: UnsafeBufferPointer<UInt8>) {
        var activeCIDs: Set<UInt16> = []
        var offset = 4
        while offset + 1 < report.count {
            let cid = (UInt16(report[offset]) << 8) | UInt16(report[offset + 1])
            if cid == 0 { break }
            activeCIDs.insert(cid)
            offset += 2
        }
        #if DEBUG
        let previousCIDs = buttonStateTracker.activeCIDs
        LogiDebugPanel.log(
            device: deviceInfo.name,
            type: .buttonEvent,
            message: "Button RAW: active=\(debugCIDList(activeCIDs)) previous=\(debugCIDList(previousCIDs)) report=\(debugReportBytes(report))"
        )
        #endif
        let delta = buttonStateTracker.update(activeCIDs: activeCIDs)
        #if DEBUG
        LogiDebugPanel.log(
            device: deviceInfo.name,
            type: .buttonEvent,
            message: "Button DELTA: pressed=\(debugCIDList(delta.pressed)) released=\(debugCIDList(delta.released)) now=\(debugCIDList(buttonStateTracker.activeCIDs))"
        )
        #endif
        for cid in delta.pressed {
            let cidName = LogiCIDDirectory.name(forCID: cid)
            LogiDebugPanel.log(device: deviceInfo.name, type: .buttonEvent, message: "Button DOWN: CID \(String(format: "0x%04X", cid)) (\(cidName))")
            dispatchButtonEvent(cid: cid, isDown: true)
        }
        for cid in delta.released {
            let cidName = LogiCIDDirectory.name(forCID: cid)
            LogiDebugPanel.log(device: deviceInfo.name, type: .buttonEvent, message: "Button UP: CID \(String(format: "0x%04X", cid)) (\(cidName))")
            dispatchButtonEvent(cid: cid, isDown: false)
        }
    }

    #if DEBUG
    private func debugCIDList(_ cids: Set<UInt16>) -> String {
        guard !cids.isEmpty else { return "[]" }
        let values = cids.sorted().map { cid in
            "\(String(format: "0x%04X", cid))(\(LogiCIDDirectory.name(forCID: cid)))"
        }
        return "[\(values.joined(separator: ","))]"
    }

    private func debugReportBytes(_ report: UnsafeBufferPointer<UInt8>) -> String {
        report.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private func debugDispatchResultLabel(_ result: LogiDispatchResult) -> String {
        switch result {
        case .consumed:
            return "consumed"
        case .unhandled:
            return "unhandled"
        case .logiAction(let name):
            return "logiAction(\(name))"
        }
    }
    #endif

    // MARK: - Event Dispatch

    /// Emit synthetic releases when Scrollio changes divert/session ownership and a
    /// physical release may never arrive. Route through normal dispatch so
    /// mouse mappings, virtual modifiers, and the scroll actions all unwind together.
    private func releaseAllActiveButtonState(reason: String) {
        emitSyntheticButtonReleases(
            for: buttonStateTracker.releaseAll(),
            reason: reason
        )
    }

    private func releaseActiveButtonState(for cids: Set<UInt16>, reason: String) {
        emitSyntheticButtonReleases(
            for: buttonStateTracker.releaseActiveCIDs(in: cids),
            reason: reason
        )
    }

    private func emitSyntheticButtonReleases(for cids: Set<UInt16>, reason: String) {
        for cid in cids.sorted() {
            let cidName = LogiCIDDirectory.name(forCID: cid)
            LogiDebugPanel.log(
                device: deviceInfo.name,
                type: .buttonEvent,
                message: "Synthetic Button UP: CID \(String(format: "0x%04X", cid)) (\(cidName)) [\(reason)]"
            )
            dispatchButtonEvent(cid: cid, isDown: false, isSyntheticRelease: true)
        }
    }

    private func dispatchButtonEvent(cid: UInt16, isDown: Bool, isSyntheticRelease: Bool = false) {
        let currentFlags = CGEventSource.flagsState(.combinedSessionState)
        // Armed for raw XY: the mouse keeps the pointer still during this hold and reports
        // its movement over HID++ (handleTrackedRawXYMovement).
        var tracksMovementOnDevice = false
        if isDown {
            tracksMovementOnDevice = gestureControllers[deviceIndex]?.buttonDown(cid: cid) ?? false
        } else {
            gestureControllers[deviceIndex]?.buttonUp(cid: cid)
        }
        let event = InputEvent(
            type: .mouse,
            code: LogiCIDDirectory.toScrollioCode(cid),
            modifiers: currentFlags,
            phase: isDown ? .down : .up,
            source: .hidPP,
            device: deviceInfo,
            tracksMovementOnDevice: tracksMovementOnDevice,
            isSyntheticRelease: isSyntheticRelease
        )
        if isDown {
            // Haptic cues for this hold go to this device (and this receiver slot) only.
            LogiSessionManager.shared.noteButtonPress(scrollioCode: event.code, session: self, slot: deviceIndex)
        }

        // Always-fired raw event (deterministic for wizard + debug observers)
        NotificationCenter.default.post(
            name: LogiCenter.rawButtonEvent,
            object: nil,
            userInfo: [
                "event": event,
                "scrollioCode": event.code,
                "cid": cid,
                "phase": isDown ? "down" : "up",
            ])

        let bridge = LogiCenter.shared.externalBridge

        if LogiCenter.shared.isRecording {
            let result = bridge.dispatchLogiButtonEvent(event)
            #if DEBUG
            LogiDebugPanel.log(
                device: deviceInfo.name,
                type: .buttonEvent,
                message: "Button DISPATCH: CID \(String(format: "0x%04X", cid)) code=\(event.code) phase=\(isDown ? "down" : "up") recording result=\(debugDispatchResultLabel(result))"
            )
            #endif
            return
        }

        // Side path: scroll hotkey fires regardless of binding outcome.
        bridge.handleLogiScrollHotkey(code: event.code, phase: event.phase)

        // Main routing.
        let result = bridge.dispatchLogiButtonEvent(event)
        #if DEBUG
        LogiDebugPanel.log(
            device: deviceInfo.name,
            type: .buttonEvent,
            message: "Button DISPATCH: CID \(String(format: "0x%04X", cid)) code=\(event.code) phase=\(isDown ? "down" : "up") result=\(debugDispatchResultLabel(result))"
        )
        #endif
        switch result {
        case .logiAction(let name) where event.phase == .down:
            executeLogiAction(name)
        case .consumed, .unhandled, .logiAction:
            break
        }
    }

    /// 在当前 session 上执行 Logi 动作
    /// Also the entry point for an action that comes from outside this mouse's own buttons
    /// (`LogiSessionManager.executeLogiAction(named:)`).
    func executeLogiAction(_ name: String) {
        guard let action = LogiButtonAction(name: name) else {
            // Unknown, or one of the actions that were removed: the binding does nothing.
            let removed = LogiButtonAction.removedNames.contains(name)
            LogiDebugPanel.log("[\(deviceInfo.name)] \(removed ? "Removed" : "Unknown") Logi action: \(name)")
            if removed {
                LogiSystemLog.note("\(logTag(slot: deviceIndex)) Button action \(name) was removed from Scrollio: the binding does nothing")
            }
            return
        }
        switch action {
        case .smartShiftToggle:
            executeSmartShiftToggle()
        case .dpiCycleUp:
            executeDPICycle(direction: .up)
        case .dpiCycleDown:
            executeDPICycle(direction: .down)
        case .host(let index):
            executeChangeHost(hostIndex: index)
        case .pointerSpeedCycle:
            executePointerSpeedCycle()
        }
    }
}
