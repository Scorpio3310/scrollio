//
//  LogiMouseBasicsController.swift
//  Mos
//
//  Per-device (per receiver slot) state of the basic mouse settings: battery (0x1004, or
//  0x1000 on the original MX Master 3), pointer speed (0x2201), haptic on/off and strength
//  (0x19B0) and the thumb panel's press force (0x19C0). Like LogiWheelController it owns no
//  transport: the session injects the closures and forwards the reports, so the logic is
//  testable with fake bytes. Byte layouts: LogiBatteryProtocol, LogiPointerSpeedProtocol,
//  LogiHapticSettingsProtocol, LogiPressForceProtocol.
//
//  Rules:
//  - One request at a time: these mice answer one request at a time. Every request waits
//    for its answer, its HID++ error or `replyTimeout`; a read that gets no answer is sent
//    again (`maxReadAttempts` in all), a write is not (its read-back tells the truth).
//  - Reading never needs the switch. On connect (`start`) everything present is read.
//  - A value is written only when the mouse is managed, the user set that value, and a
//    read of it arrived since the connect or since the user changed it, and the snapped or
//    clamped value differs from that read. At most one write per value per connect or
//    change; every write is read back, and when the mouse reports something else (firmware
//    rounding) its value is shown and not fought until the user changes the setting.
//  - Haptic writes start from the last read flags: only the on bit changes, power save and
//    unknown bits survive, and switching off keeps the strength.
//  - Press force is written only when the button is changeable and its range is sane.
//  - An HID++ error on a read makes that basic unavailable for this connection; an error
//    on a write is logged and the read-back follows. Malformed answers are logged, never
//    written from.
//  - Answers nobody here asked for (the debug panel, the DPI buttons, a gesture cue
//    switching haptics on) update the shown state; an unknown write to a value is followed
//    by a read of it.
//  - The battery is read on connect, follows the mouse's battery events, and a refresh
//    reads it again only when the last reading is older than `batteryRefreshInterval`.
//    No timers: nothing is polled.
//  - Every read result that changes and every write decision is one `log` line (the
//    session sends them to LogiSystemLog); answers whose layout is an assumption are logged
//    raw the first time they are seen.
//
//  Main thread only (HID++ callbacks run on the main run loop).
//

import Foundation

final class LogiMouseBasicsController {

    typealias Basic = LogiMouseDeviceState.Basic
    /// Sends one request to the given feature index of this device.
    typealias Send = (_ featureIndex: UInt8, _ functionId: UInt8, _ params: [UInt8]) -> Void
    /// Runs the block on the main queue after the delay.
    typealias Schedule = (_ delay: TimeInterval, _ work: @escaping () -> Void) -> Void

    /// How long the mouse has to answer one request (the wheel and gesture controllers
    /// wait the same 2 s).
    static let replyTimeout: TimeInterval = 2
    /// Sends of one read without an answer before it is given up.
    static let maxReadAttempts = 3
    /// A refresh reads the battery again only when the last reading is older than this.
    static let batteryRefreshInterval: TimeInterval = 5 * 60

    /// Feature indices of one device; nil = the device does not have it.
    struct Features: Equatable {
        struct Battery: Equatable {
            let feature: LogiBatteryFeature
            let index: UInt8
        }

        var battery: Battery?
        var pointerSpeed: UInt8?
        var haptics: UInt8?
        var pressForce: UInt8?

        var isEmpty: Bool { battery == nil && pointerSpeed == nil && haptics == nil && pressForce == nil }

        func index(of basic: Basic) -> UInt8? {
            switch basic {
            case .battery: return battery?.index
            case .pointerSpeed: return pointerSpeed
            case .haptics: return haptics
            case .pressForce: return pressForce
            }
        }

        func basic(forIndex index: UInt8) -> Basic? {
            return Basic.allCases.first { self.index(of: $0) == index }
        }
    }

    let features: Features

    private let send: Send
    private let schedule: Schedule
    private let now: () -> Date
    private let onChange: () -> Void
    private let log: (String) -> Void

    init(
        features: Features,
        send: @escaping Send,
        schedule: @escaping Schedule,
        now: @escaping () -> Date = Date.init,
        onChange: @escaping () -> Void = {},
        log: @escaping (String) -> Void = { _ in }
    ) {
        self.features = features
        self.send = send
        self.schedule = schedule
        self.now = now
        self.onChange = onChange
        self.log = log
    }

    // MARK: - What the user wants

    private(set) var desired = LogiMouseSettings.default
    private(set) var managed = false

    // MARK: - What the mouse reported

    private(set) var battery: LogiMouseDeviceState.Battery?
    private var batteryReadAt: Date?
    private(set) var dpiList: LogiPointerSpeedProtocol.DPIList?
    private(set) var dpi: Int?
    private(set) var defaultDPI: Int?
    private(set) var hapticState: LogiHapticSettingsProtocol.State?
    private(set) var pressForceInfo: LogiPressForceInfo?
    private(set) var pressForce: UInt16?

    /// Basics the mouse refused to read (HID++ error) on this connection.
    private(set) var unavailable: Set<Basic> = []
    /// Basics read since the connect or since the user changed them: only these may be written.
    private var freshlyRead: Set<Basic> = []
    /// Basics decided (written, or found matching, or not writable) since the connect or
    /// since the user changed them: no second write.
    private var settled: Set<Basic> = []
    /// What the last write sent, to compare with its read-back.
    private var writtenDPI: Int?
    private var writtenHaptics: (flags: UInt8, strength: UInt8)?
    private var writtenPressForce: UInt16?
    /// A sample pulse waits until the haptic writes in the queue went out.
    private var samplePending = false
    /// Raw answers already logged once.
    private var loggedRaw: Set<String> = []

    // MARK: - Request queue

    private enum Kind: Equatable {
        case read
        case write
        case play
    }

    private struct Request {
        let basic: Basic
        let functionId: UInt8
        let params: [UInt8]
        let kind: Kind
        let label: String
        var attempt = 1

        func isSameRead(as other: Request) -> Bool {
            return kind == .read && other.kind == .read && basic == other.basic
                && functionId == other.functionId && params == other.params
        }
    }

    private var queue: [Request] = []
    private var inFlight: Request?
    private var requestToken = 0

    /// Nothing waits for an answer and nothing is queued.
    var isIdle: Bool { inFlight == nil && queue.isEmpty }

    // MARK: - Commands

    /// First contact after discovery: reads everything the mouse has, then writes what the
    /// user set (only when `managed`). A controller kept across a rediscovery starts afresh:
    /// a basic the mouse refused before (often while it was still waking up) is asked again.
    func start(desired: LogiMouseSettings, managed: Bool) {
        self.desired = desired
        self.managed = managed
        if !unavailable.isEmpty {
            unavailable.removeAll()
            onChange()
        }
        freshlyRead.removeAll()
        settled.removeAll()
        writtenDPI = nil
        writtenHaptics = nil
        writtenPressForce = nil
        log("Connected: \(describeFeatures()); \(managed ? "managed, \(Self.describe(desired))" : "not managed, reading only")")
        for basic in Basic.allCases {
            enqueueReads(basic, includingStatic: true)
        }
        pump()
    }

    /// Reads the values again (the battery only when its last reading is old). Writes only
    /// what is still undecided since the connect or the last settings change.
    func refresh() {
        for basic in Basic.allCases {
            if basic == .battery, let readAt = batteryReadAt,
               now().timeIntervalSince(readAt) < Self.batteryRefreshInterval {
                continue
            }
            enqueueReads(basic, includingStatic: false)
        }
        pump()
    }

    /// New settings or a new state of the switch. A value the user changed (or every set
    /// value, when the switch was just turned on) is read again and written if it differs.
    func apply(desired newDesired: LogiMouseSettings, managed newManaged: Bool) {
        let old = desired
        let wasManaged = managed
        desired = newDesired
        managed = newManaged
        let turnedOn = newManaged && !wasManaged
        if newManaged != wasManaged {
            log(newManaged ? "Managed from now on: \(Self.describe(newDesired))" : "Not managed any more: nothing is written")
        }
        guard newManaged else {
            for basic in Basic.allCases where queue.contains(where: { $0.basic == basic && $0.kind == .write }) {
                forgetWrite(basic)
            }
            queue.removeAll { $0.kind == .write }
            if newDesired != old || wasManaged { onChange() }
            return
        }
        var changed: [Basic] = []
        if turnedOn || newDesired.pointerDPI != old.pointerDPI { changed.append(.pointerSpeed) }
        if turnedOn || newDesired.hapticsOn != old.hapticsOn || newDesired.hapticStrength != old.hapticStrength {
            changed.append(.haptics)
        }
        if turnedOn || newDesired.pressForce != old.pressForce { changed.append(.pressForce) }
        for basic in changed {
            settled.remove(basic)
            freshlyRead.remove(basic)
            // A write decided from the old settings that has not gone out is not wanted any
            // more: the read queued behind it decides again from the new ones.
            if queue.contains(where: { $0.basic == basic && $0.kind == .write }) {
                queue.removeAll { $0.basic == basic && $0.kind == .write }
                forgetWrite(basic)
            }
            if hasWish(basic) { enqueueReads(basic, includingStatic: false) }
        }
        if newDesired != old || turnedOn { onChange() }
        pump()
    }

    /// Plays one pulse at the mouse's current strength, after the haptic writes waiting in
    /// the queue. Skipped (and logged) when haptics are off on the mouse.
    func playSample() {
        guard features.haptics != nil, !unavailable.contains(.haptics) else {
            log("Haptics: sample pulse skipped, this mouse has no usable haptic feature")
            return
        }
        samplePending = true
        if hapticState == nil { enqueueReads(.haptics, includingStatic: false) }
        maybePlaySample()
        pump()
    }

    // MARK: - Reports

    /// The session's feature indices that belong to this controller.
    func owns(featureIndex: UInt8) -> Bool {
        return features.basic(forIndex: featureIndex) != nil
    }

    /// An answer (software id matched) on one of this device's basic features. Returns true
    /// when the index belongs to this controller.
    @discardableResult
    func handleResponse(featureIndex: UInt8, functionId: UInt8, report: [UInt8]) -> Bool {
        guard let basic = features.basic(forIndex: featureIndex) else { return false }
        var answered: Request?
        if let request = inFlight, request.basic == basic, request.functionId == functionId {
            answered = request
            inFlight = nil
        }
        switch basic {
        case .battery: handleBatteryAnswer(functionId: functionId, report: report, answered: answered)
        case .pointerSpeed: handlePointerAnswer(functionId: functionId, report: report, answered: answered)
        case .haptics: handleHapticAnswer(functionId: functionId, report: report, answered: answered)
        case .pressForce: handlePressForceAnswer(functionId: functionId, report: report, answered: answered)
        }
        pump()
        return true
    }

    /// A device event (software id 0) on one of this device's basic features. Only the
    /// battery sends any.
    func handleEvent(featureIndex: UInt8, functionId: UInt8, report: [UInt8]) {
        guard let battery = features.battery, featureIndex == battery.index,
              LogiBatteryProtocol.isStatusEvent(functionId: functionId, softwareId: 0) else { return }
        guard let reading = LogiBatteryProtocol.parseStatus(report, feature: battery.feature) else {
            log("Battery: unreadable event \(Self.hex(report))")
            return
        }
        logRawOnce("battery-event", "Battery: first event \(Self.hex(report))")
        updateBattery(reading)
    }

    /// An HID++ 2.0 error for a request on one of this device's basic features.
    func handleError(featureIndex: UInt8, functionId: UInt8, errorCode: UInt8) {
        guard let basic = features.basic(forIndex: featureIndex) else { return }
        let code = String(format: "0x%02X", errorCode)
        guard let request = inFlight, request.basic == basic, request.functionId == functionId else {
            log("\(Self.name(basic)): error \(code) on fn\(functionId) for a request Scrollio is not waiting for, ignored")
            return
        }
        inFlight = nil
        switch request.kind {
        case .read:
            log("\(Self.name(basic)): the mouse refused \(request.label) (error \(code)); not used on this connection")
            unavailable.insert(basic)
            queue.removeAll { $0.basic == basic }
            if basic == .haptics { samplePending = false }
            onChange()
        case .write:
            log("\(Self.name(basic)): the mouse refused \(request.label) (error \(code)); reading back")
        case .play:
            log("Haptics: the mouse refused the sample pulse (error \(code))")
        }
        if basic == .haptics { maybePlaySample() }
        pump()
    }

    // MARK: - Snapshot

    var supported: Set<Basic> {
        return Set(Basic.allCases.filter { features.index(of: $0) != nil && !unavailable.contains($0) })
    }

    func deviceState(id: String, deviceName: String, wheel: LogiWheelDeviceState?) -> LogiMouseDeviceState {
        let supported = self.supported
        var pointer: LogiMouseDeviceState.PointerSpeed?
        if supported.contains(.pointerSpeed) {
            let choices = dpiList?.values ?? []
            pointer = LogiMouseDeviceState.PointerSpeed(
                choices: choices,
                dpi: LogiMouseDeviceState.Value(
                    onMouse: dpi,
                    setByYou: desired.pointerDPI.map { LogiPointerSpeedProtocol.snap($0, to: choices) ?? $0 }
                ),
                defaultDPI: defaultDPI
            )
        }
        var haptics: LogiMouseDeviceState.Haptics?
        if supported.contains(.haptics) {
            let few = LogiHapticSettingsProtocol.hasFewLevels(levelsByte: hapticState?.levelsByte)
            haptics = LogiMouseDeviceState.Haptics(
                isOn: LogiMouseDeviceState.Value(onMouse: hapticState?.isOn, setByYou: desired.hapticsOn),
                strength: LogiMouseDeviceState.Value(
                    onMouse: hapticState.map { Int($0.strength) },
                    setByYou: desired.hapticStrength.map {
                        LogiHapticSettingsProtocol.snapStrength($0, fewLevels: few ?? false)
                    }
                ),
                hasFewLevels: few,
                fewLevelChoices: LogiHapticSettingsProtocol.fewLevelChoices
            )
        }
        var press: LogiMouseDeviceState.PressForce?
        if supported.contains(.pressForce) {
            let validInfo = pressForceInfo.flatMap { LogiPressForceProtocol.isValid($0) ? $0 : nil }
            press = LogiMouseDeviceState.PressForce(
                force: LogiMouseDeviceState.Value(
                    onMouse: pressForce.map(Int.init),
                    setByYou: desired.pressForce.map {
                        Int(LogiPressForceProtocol.clamp(UInt16(clamping: $0), info: validInfo))
                    }
                ),
                range: validInfo.map { Int($0.minValue)...Int($0.maxValue) },
                defaultForce: validInfo.map { Int($0.defaultValue) },
                isChangeable: pressForceInfo?.changeable ?? false
            )
        }
        return LogiMouseDeviceState(
            id: id,
            deviceName: deviceName,
            supported: supported,
            managed: managed,
            battery: supported.contains(.battery) ? battery : nil,
            pointerSpeed: pointer,
            haptics: haptics,
            pressForce: press,
            wheel: wheel
        )
    }

    // MARK: - Battery

    private func handleBatteryAnswer(functionId: UInt8, report: [UInt8], answered: Request?) {
        guard let feature = features.battery?.feature, functionId == feature.statusFunction else {
            return  // 0x1004 getCapabilities from the debug panel
        }
        guard let reading = LogiBatteryProtocol.parseStatus(report, feature: feature) else {
            log("Battery: unreadable answer \(Self.hex(report))")
            return
        }
        logRawOnce("battery", "Battery: first answer \(Self.hex(report))")
        updateBattery(reading)
    }

    private func updateBattery(_ reading: LogiMouseDeviceState.Battery) {
        batteryReadAt = now()
        guard reading != battery else { return }
        battery = reading
        log("Battery: \(LogiBatteryProtocol.describe(reading))")
        onChange()
    }

    // MARK: - Pointer speed

    private func handlePointerAnswer(functionId: UInt8, report: [UInt8], answered: Request?) {
        switch functionId {
        case LogiPointerSpeedProtocol.listFunction:
            logRawOnce("dpi-list", "Pointer speed: first DPI list answer \(Self.hex(report))")
            guard let list = LogiPointerSpeedProtocol.parseDPIList(report) else {
                log("Pointer speed: unreadable DPI list \(Self.hex(report)); nothing will be written")
                return
            }
            if list != dpiList {
                dpiList = list
                log("Pointer speed: the mouse accepts \(LogiPointerSpeedProtocol.describe(list))")
                onChange()
            }
            evaluateWrite(.pointerSpeed)
        case LogiPointerSpeedProtocol.getFunction:
            logRawOnce("dpi-current", "Pointer speed: first current DPI answer \(Self.hex(report))")
            guard let parsed = LogiPointerSpeedProtocol.parseCurrent(report) else {
                log("Pointer speed: unreadable current DPI \(Self.hex(report))")
                return
            }
            let changed = parsed.current != dpi || parsed.defaultDPI != defaultDPI
            dpi = parsed.current
            defaultDPI = parsed.defaultDPI
            freshlyRead.insert(.pointerSpeed)
            if let written = writtenDPI {
                writtenDPI = nil
                log(written == parsed.current
                    ? "Pointer speed: the mouse now reports \(written)"
                    : "Pointer speed: wrote \(written), the mouse reports \(parsed.current); keeping the mouse's value, no retry")
            } else if changed {
                log("Pointer speed: mouse \(parsed.current) DPI (default \(parsed.defaultDPI.map(String.init) ?? "none"))")
            }
            if changed { onChange() }
            evaluateWrite(.pointerSpeed)
        case LogiPointerSpeedProtocol.setFunction:
            if answered == nil {
                // Somebody else (the DPI buttons, the debug panel) changed it: follow.
                enqueue(Request(basic: .pointerSpeed, functionId: LogiPointerSpeedProtocol.getFunction,
                                params: LogiPointerSpeedProtocol.getParams(), kind: .read, label: "the current DPI"))
            }
        default:
            break
        }
    }

    // MARK: - Haptics

    private func handleHapticAnswer(functionId: UInt8, report: [UInt8], answered: Request?) {
        switch functionId {
        case LogiHapticSettingsProtocol.getStateFunction:
            logRawOnce("haptic-state", "Haptics: first state answer \(Self.hex(report))")
            guard let state = LogiHapticSettingsProtocol.parseState(report) else {
                log("Haptics: unreadable state \(Self.hex(report))")
                break
            }
            let changed = state != hapticState
            hapticState = state
            freshlyRead.insert(.haptics)
            if let written = writtenHaptics {
                writtenHaptics = nil
                log(written.flags == state.flags && written.strength == state.strength
                    ? "Haptics: the mouse now reports \(LogiHapticSettingsProtocol.describe(state))"
                    : "Haptics: wrote \(String(format: "0x%02X", written.flags))/\(written.strength), the mouse reports \(LogiHapticSettingsProtocol.describe(state)); keeping the mouse's value, no retry")
            } else if changed {
                log("Haptics: mouse \(LogiHapticSettingsProtocol.describe(state))")
            }
            if changed { onChange() }
            evaluateWrite(.haptics)
        case LogiHapticSettingsProtocol.setStateFunction:
            if answered == nil {
                // A gesture cue switched them on, or the debug panel wrote: follow.
                enqueue(Request(basic: .haptics, functionId: LogiHapticSettingsProtocol.getStateFunction,
                                params: [], kind: .read, label: "the haptic state"))
            } else {
                logRawOnce("haptic-set", "Haptics: first answer to a state write \(Self.hex(report))")
            }
        default:
            break  // play acknowledgement, capabilities read by the gesture controller
        }
        maybePlaySample()
    }

    private func maybePlaySample() {
        guard samplePending else { return }
        let busy = inFlight?.basic == .haptics || queue.contains { $0.basic == .haptics }
        guard !busy else { return }
        samplePending = false
        guard let state = hapticState else {
            log("Haptics: sample pulse skipped, the mouse did not report its state")
            return
        }
        guard state.isOn else {
            log("Haptics: sample pulse skipped, haptics are off on the mouse")
            return
        }
        log("Haptics: playing a sample pulse at strength \(state.strength)")
        enqueue(Request(
            basic: .haptics,
            functionId: LogiHapticSettingsProtocol.playFunction,
            params: LogiHapticSettingsProtocol.playParams(waveform: LogiHapticSettingsProtocol.sampleWaveform),
            kind: .play,
            label: "the sample pulse"
        ))
    }

    // MARK: - Press force

    private func handlePressForceAnswer(functionId: UInt8, report: [UInt8], answered: Request?) {
        switch functionId {
        case LogiPressForceProtocol.infoFunction:
            logRawOnce("press-info", "Press force: first button info answer \(Self.hex(report))")
            guard let info = LogiPressForceProtocol.parseInfo(report) else {
                log("Press force: unreadable button info \(Self.hex(report))")
                return
            }
            if info != pressForceInfo {
                pressForceInfo = info
                log("Press force: range \(LogiPressForceProtocol.describe(info))\(LogiPressForceProtocol.isValid(info) ? "" : " (unusable: nothing will be written)")")
                onChange()
            }
            evaluateWrite(.pressForce)
        case LogiPressForceProtocol.currentFunction:
            guard let value = LogiPressForceProtocol.parseCurrent(report) else {
                log("Press force: unreadable current value \(Self.hex(report))")
                return
            }
            let changed = value != pressForce
            pressForce = value
            freshlyRead.insert(.pressForce)
            if let written = writtenPressForce {
                writtenPressForce = nil
                log(written == value
                    ? "Press force: the mouse now reports \(value)"
                    : "Press force: wrote \(written), the mouse reports \(value); keeping the mouse's value, no retry")
            } else if changed {
                log("Press force: mouse \(value)")
            }
            if changed { onChange() }
            evaluateWrite(.pressForce)
        case LogiPressForceProtocol.setFunction:
            if answered == nil {
                enqueue(Request(basic: .pressForce, functionId: LogiPressForceProtocol.currentFunction,
                                params: LogiPressForceProtocol.currentParams(), kind: .read, label: "the current press force"))
            }
        default:
            break
        }
    }

    // MARK: - Write decisions

    private func forgetWrite(_ basic: Basic) {
        switch basic {
        case .battery: break
        case .pointerSpeed: writtenDPI = nil
        case .haptics: writtenHaptics = nil
        case .pressForce: writtenPressForce = nil
        }
    }

    private func hasWish(_ basic: Basic) -> Bool {
        switch basic {
        case .battery: return false
        case .pointerSpeed: return desired.pointerDPI != nil
        case .haptics: return desired.hapticsOn != nil || desired.hapticStrength != nil
        case .pressForce: return desired.pressForce != nil
        }
    }

    private func evaluateWrite(_ basic: Basic) {
        guard managed, hasWish(basic), !settled.contains(basic), freshlyRead.contains(basic),
              !unavailable.contains(basic) else { return }
        switch basic {
        case .battery: break
        case .pointerSpeed: decidePointerWrite()
        case .haptics: decideHapticWrite()
        case .pressForce: decidePressForceWrite()
        }
    }

    private func decidePointerWrite() {
        guard let wanted = desired.pointerDPI, let current = dpi else { return }
        settled.insert(.pointerSpeed)
        guard let list = dpiList,
              let target = LogiPointerSpeedProtocol.snap(wanted, to: list.values),
              let params = LogiPointerSpeedProtocol.setParams(dpi: target) else {
            log("Pointer speed: mouse \(current), wanted \(wanted); the DPI list is unknown, not writing")
            return
        }
        let snapped = target == wanted ? "" : " (nearest it accepts: \(target))"
        guard target != current else {
            log("Pointer speed: mouse \(current), wanted \(wanted)\(snapped); already set, no write")
            return
        }
        log("Pointer speed: mouse \(current), wanted \(wanted)\(snapped); writing \(target)")
        writtenDPI = target
        enqueue(Request(basic: .pointerSpeed, functionId: LogiPointerSpeedProtocol.setFunction,
                        params: params, kind: .write, label: "DPI \(target)"))
        enqueue(Request(basic: .pointerSpeed, functionId: LogiPointerSpeedProtocol.getFunction,
                        params: LogiPointerSpeedProtocol.getParams(), kind: .read, label: "the current DPI"))
    }

    private func decideHapticWrite() {
        guard let state = hapticState else { return }
        settled.insert(.haptics)
        let few = LogiHapticSettingsProtocol.hasFewLevels(levelsByte: state.levelsByte) ?? false
        let strength = desired.hapticStrength.map { LogiHapticSettingsProtocol.snapStrength($0, fewLevels: few) }
        let params = LogiHapticSettingsProtocol.setStateParams(
            readFlags: state.flags,
            readStrength: state.strength,
            on: desired.hapticsOn,
            strength: strength
        )
        let wanted = "wanted \(desired.hapticsOn.map { $0 ? "on" : "off" } ?? "on/off as is"), strength \(strength.map(String.init) ?? "as is")"
        guard LogiHapticSettingsProtocol.needsWrite(params, current: state) else {
            log("Haptics: mouse \(LogiHapticSettingsProtocol.describe(state)), \(wanted); already set, no write")
            return
        }
        log("Haptics: mouse \(String(format: "0x%02X", state.flags))/\(state.strength), \(wanted); writing \(String(format: "0x%02X", params[0]))/\(params[1]) (other flags kept)")
        writtenHaptics = (params[0], params[1])
        enqueue(Request(basic: .haptics, functionId: LogiHapticSettingsProtocol.setStateFunction,
                        params: params, kind: .write, label: "the haptic state"))
        enqueue(Request(basic: .haptics, functionId: LogiHapticSettingsProtocol.getStateFunction,
                        params: [], kind: .read, label: "the haptic state"))
    }

    private func decidePressForceWrite() {
        guard let wanted = desired.pressForce, let info = pressForceInfo, let current = pressForce else { return }
        settled.insert(.pressForce)
        guard info.changeable else {
            log("Press force: wanted \(wanted); the mouse does not allow changing it, not writing")
            return
        }
        guard LogiPressForceProtocol.isValid(info) else {
            log("Press force: wanted \(wanted); the mouse reported an unusable range (\(LogiPressForceProtocol.describe(info))), not writing")
            return
        }
        let target = LogiPressForceProtocol.clamp(UInt16(clamping: wanted), info: info)
        let clamped = Int(target) == wanted ? "" : " (clamped to \(target), range \(info.minValue)...\(info.maxValue))"
        guard target != current else {
            log("Press force: mouse \(current), wanted \(wanted)\(clamped); already set, no write")
            return
        }
        log("Press force: mouse \(current), wanted \(wanted)\(clamped); writing \(target)")
        writtenPressForce = target
        enqueue(Request(basic: .pressForce, functionId: LogiPressForceProtocol.setFunction,
                        params: LogiPressForceProtocol.setParams(value: target), kind: .write, label: "press force \(target)"))
        enqueue(Request(basic: .pressForce, functionId: LogiPressForceProtocol.currentFunction,
                        params: LogiPressForceProtocol.currentParams(), kind: .read, label: "the current press force"))
    }

    // MARK: - Queue

    /// The reads of one basic. `includingStatic` also reads what does not change while
    /// connected (DPI list, press force range); otherwise those are read only while unknown.
    private func enqueueReads(_ basic: Basic, includingStatic: Bool) {
        guard features.index(of: basic) != nil, !unavailable.contains(basic) else { return }
        switch basic {
        case .battery:
            guard let feature = features.battery?.feature else { return }
            enqueue(Request(basic: .battery, functionId: feature.statusFunction, params: [],
                            kind: .read, label: "the battery status"))
        case .pointerSpeed:
            if includingStatic || dpiList == nil {
                enqueue(Request(basic: .pointerSpeed, functionId: LogiPointerSpeedProtocol.listFunction,
                                params: LogiPointerSpeedProtocol.listParams(), kind: .read, label: "the DPI list"))
            }
            enqueue(Request(basic: .pointerSpeed, functionId: LogiPointerSpeedProtocol.getFunction,
                            params: LogiPointerSpeedProtocol.getParams(), kind: .read, label: "the current DPI"))
        case .haptics:
            enqueue(Request(basic: .haptics, functionId: LogiHapticSettingsProtocol.getStateFunction,
                            params: [], kind: .read, label: "the haptic state"))
        case .pressForce:
            if includingStatic || pressForceInfo == nil {
                enqueue(Request(basic: .pressForce, functionId: LogiPressForceProtocol.infoFunction,
                                params: LogiPressForceProtocol.infoParams(), kind: .read, label: "the press force range"))
            }
            enqueue(Request(basic: .pressForce, functionId: LogiPressForceProtocol.currentFunction,
                            params: LogiPressForceProtocol.currentParams(), kind: .read, label: "the current press force"))
        }
    }

    /// Adds a request. A read already waiting (or on its way) is not asked twice, unless a
    /// write of the same value goes out in between: a read-back must follow its write.
    private func enqueue(_ request: Request) {
        if request.kind == .read {
            let lastWrite = queue.lastIndex { $0.basic == request.basic && $0.kind == .write }
            let start = lastWrite.map { $0 + 1 } ?? queue.startIndex
            if queue[start...].contains(where: { $0.isSameRead(as: request) }) { return }
            if lastWrite == nil, let inFlight, inFlight.isSameRead(as: request) { return }
        }
        queue.append(request)
    }

    /// Sends the next request when none is waiting for its answer.
    private func pump() {
        while inFlight == nil, !queue.isEmpty {
            let request = queue.removeFirst()
            guard let index = features.index(of: request.basic), !unavailable.contains(request.basic) else { continue }
            if request.kind == .write, !managed { continue }
            transmit(request, index: index)
        }
    }

    private func transmit(_ request: Request, index: UInt8) {
        inFlight = request
        requestToken += 1
        let token = requestToken
        send(index, request.functionId, request.params)
        schedule(Self.replyTimeout) { [weak self] in
            self?.replyTimedOut(token: token)
        }
    }

    private func replyTimedOut(token: Int) {
        guard token == requestToken, var request = inFlight,
              let index = features.index(of: request.basic) else { return }
        if request.kind == .read, request.attempt < Self.maxReadAttempts {
            request.attempt += 1
            log("\(Self.name(request.basic)): no answer to \(request.label), asking again (\(request.attempt)/\(Self.maxReadAttempts))")
            transmit(request, index: index)
            return
        }
        inFlight = nil
        switch request.kind {
        case .read: log("\(Self.name(request.basic)): no answer to \(request.label), giving up until the next refresh")
        case .write: log("\(Self.name(request.basic)): no answer to the write of \(request.label), reading back")
        case .play: log("Haptics: no answer to the sample pulse")
        }
        if request.basic == .haptics { maybePlaySample() }
        pump()
    }

    // MARK: - Logging

    private func logRawOnce(_ key: String, _ line: String) {
        guard !loggedRaw.contains(key) else { return }
        loggedRaw.insert(key)
        log(line)
    }

    private func describeFeatures() -> String {
        var parts: [String] = []
        if let battery = features.battery {
            parts.append(String(format: "battery 0x%04X at 0x%02X", battery.feature.featureId, battery.index))
        }
        if let index = features.pointerSpeed { parts.append(String(format: "DPI at 0x%02X", index)) }
        if let index = features.haptics { parts.append(String(format: "haptics at 0x%02X", index)) }
        if let index = features.pressForce { parts.append(String(format: "press force at 0x%02X", index)) }
        return parts.isEmpty ? "no basic features" : parts.joined(separator: ", ")
    }

    static func describe(_ settings: LogiMouseSettings) -> String {
        var parts: [String] = []
        if let dpi = settings.pointerDPI { parts.append("DPI \(dpi)") }
        if let on = settings.hapticsOn { parts.append("haptics \(on ? "on" : "off")") }
        if let strength = settings.hapticStrength { parts.append("haptic strength \(strength)") }
        if let force = settings.pressForce { parts.append("press force \(force)") }
        return parts.isEmpty ? "nothing set by the user" : "user set " + parts.joined(separator: ", ")
    }

    static func name(_ basic: Basic) -> String {
        switch basic {
        case .battery: return "Battery"
        case .pointerSpeed: return "Pointer speed"
        case .haptics: return "Haptics"
        case .pressForce: return "Press force"
        }
    }

    static func hex(_ bytes: [UInt8]) -> String {
        return bytes.prefix(20).map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
