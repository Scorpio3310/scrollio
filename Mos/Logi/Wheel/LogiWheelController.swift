//
//  LogiWheelController.swift
//  Mos
//
//  Per-device (per receiver slot) scroll-wheel state machine for SmartShift (0x2110)
//  and SmartShift Enhanced (0x2111). It owns no transport: the session injects a
//  `send` closure and forwards responses, so the logic is testable with fake bytes.
//
//  Rules (the same as for the basic settings, LogiMouseBasicsController):
//  - Reading never needs the switch. A value is written only when the mouse is managed
//    ("Let Scrollio manage this mouse"), the user set that value (non-nil), and a status read
//    since the connect or since the user changed it shows something else (values live in
//    device NVM). A value the user never set is never written.
//  - Decided per value: on connect (or when the switch is turned on) every set value, after
//    a change only the value that changed. A new mode brings the user's sensitivity along
//    (SmartShift needs a threshold); a mouse without one that the user never set gets the
//    factory default. Sensitivity applies only in SmartShift.
//  - Every write is followed by a read-back, and the read-back writes nothing again.
//  - The capabilities read has a reply timeout. A lost reply is asked for again; when
//    the mouse stays silent, the other values are decided without the force, which waits
//    for the capabilities (the next refresh asks again).
//  - Every write decision is one `log` line (the session sends them to LogiSystemLog too):
//    "already set, no write", "writing ...", "not set by the user, left alone". Status reads
//    are logged only when they change.
//  - Main thread only (HID++ callbacks run on the main run loop).
//

import Foundation

final class LogiWheelController {

    typealias Send = (_ functionId: UInt8, _ params: [UInt8]) -> Void
    /// Runs the block on the main queue after the delay.
    typealias Schedule = (_ delay: TimeInterval, _ work: @escaping () -> Void) -> Void

    /// How long the mouse has to answer the capabilities read. Its answers normally take
    /// a few milliseconds; the gesture controller waits the same 2 s for its echoes.
    static let replyTimeout: TimeInterval = 2
    /// Capabilities reads sent in a row without an answer before going on without them.
    static let maxCapabilitiesAttempts = 3

    let feature: LogiWheelFeature
    let featureIndex: UInt8

    private let send: Send
    private let schedule: Schedule
    private let onChange: () -> Void
    private let log: (String) -> Void

    /// 0x2111 getCapabilities result; nil until read (always nil on 0x2110).
    private(set) var capabilities: LogiWheelCapabilities?
    /// Last getRatchetControlMode result; nil until read.
    private(set) var status: LogiWheelStatus?

    /// The wheel values, decided one by one.
    enum Field: CaseIterable, Equatable {
        case mode
        case sensitivity
        case scrollForce
    }

    /// What the user wants; `managedByMos` is the switch.
    private(set) var desired = LogiWheelSettings.default
    var managed: Bool { desired.managedByMos }
    /// Values waiting for a fresh status read before they are decided (written or not).
    private(set) var pendingFields: Set<Field> = []
    /// "SmartShift Toggle" waiting for the current mode.
    private(set) var pendingToggle = false

    private var statusReadOutstanding = false
    private var capabilitiesRequested = false
    private var capabilitiesUnavailable = false
    /// Every capabilities read went unanswered. Unlike `capabilitiesUnavailable` (the mouse
    /// answered with an error or a short reply) this is not final: the next refresh asks again.
    private var capabilitiesTimedOut = false
    /// Identifies the capabilities read a timeout belongs to.
    private var capabilitiesRequestToken = 0
    /// The user's force could not be decided because the capabilities read timed out. Decided
    /// once more if the capabilities arrive after all.
    private var forceWaitsForCapabilities = false
    /// The last status written to the log; a read that brings nothing new is not logged.
    private var loggedStatus: LogiWheelStatus?

    init(
        feature: LogiWheelFeature,
        featureIndex: UInt8,
        send: @escaping Send,
        schedule: @escaping Schedule,
        onChange: @escaping () -> Void,
        log: @escaping (String) -> Void = { _ in }
    ) {
        self.feature = feature
        self.featureIndex = featureIndex
        self.send = send
        self.schedule = schedule
        self.onChange = onChange
        self.log = log
    }

    // MARK: - Derived state

    /// Ratchet force can be tuned (0x2111 with the tunable-torque capability bit).
    var supportsScrollForce: Bool {
        return feature == .smartShiftEnhanced && capabilities?.tunableTorque == true
    }

    /// Torque support is settled (0x2110 has nothing to ask; 0x2111 needs getCapabilities,
    /// or its error, or the give-up after `maxCapabilitiesAttempts` unanswered reads).
    var capabilitiesKnown: Bool {
        return feature.capabilitiesFunction == nil || capabilities != nil
            || capabilitiesUnavailable || capabilitiesTimedOut
    }

    var mode: LogiWheelMode? { status.flatMap { LogiWheelProtocol.mode(for: $0) } }

    var smartShiftSensitivity: Int? {
        status.flatMap { LogiWheelProtocol.sensitivity(forAutoDisengage: $0.autoDisengage) }
    }

    var scrollForce: Int? {
        guard supportsScrollForce, let torque = status?.torque else { return nil }
        return Int(torque)
    }

    // MARK: - Commands

    /// First contact after discovery: read capabilities + status, then decide every value
    /// the user set, if (and only if) the mouse is managed.
    func start(desired: LogiWheelSettings) {
        self.desired = desired
        pendingFields = desired.managedByMos ? Set(Field.allCases) : []
        forceWaitsForCapabilities = false
        loggedStatus = nil
        log("Connected: \(String(format: "0x%04X", feature.featureId)) at index \(String(format: "0x%02X", featureIndex)); \(desired.managedByMos ? "managed, \(Self.describe(desired))" : "not managed, reading only")")
        refresh()
    }

    /// Re-reads capabilities (once) and status. Decides only what is still pending.
    func refresh() {
        requestCapabilitiesIfNeeded()
        requestStatus()
    }

    /// New settings or a new state of the switch. A value the user changed (or every value,
    /// when the switch was just turned on) is decided after a fresh status read. Turned off,
    /// nothing is written and anything still pending is dropped.
    func apply(_ settings: LogiWheelSettings) {
        let old = desired
        desired = settings
        if settings != old { onChange() }  // what the user set is part of the shown state
        if settings.managedByMos != old.managedByMos {
            log(settings.managedByMos ? "Managed from now on: \(Self.describe(settings))" : "Not managed any more: nothing is written")
        }
        guard settings.managedByMos else {
            pendingFields.removeAll()
            forceWaitsForCapabilities = false
            return
        }
        let turnedOn = !old.managedByMos
        var changed: Set<Field> = []
        if turnedOn || settings.mode != old.mode { changed.insert(.mode) }
        if turnedOn || settings.smartShiftSensitivity != old.smartShiftSensitivity { changed.insert(.sensitivity) }
        if turnedOn || settings.scrollForce != old.scrollForce {
            changed.insert(.scrollForce)
            forceWaitsForCapabilities = false
        }
        guard !changed.isEmpty else { return }
        pendingFields.formUnion(changed)
        refresh()
    }

    /// Flips free-spin <-> ratchet, keeping threshold and torque.
    func toggleMode() {
        pendingToggle = true
        requestStatus()
    }

    // MARK: - Responses

    /// Feeds a response (software id already matched) for this feature index.
    /// Returns true when the function belongs to this feature.
    @discardableResult
    func handleResponse(functionId: UInt8, report: [UInt8]) -> Bool {
        if let capabilitiesFunction = feature.capabilitiesFunction, functionId == capabilitiesFunction {
            capabilitiesRequested = false
            capabilitiesTimedOut = false
            if let caps = LogiWheelProtocol.parseCapabilities(report) {
                capabilities = caps
                log("Capabilities: tunableTorque=\(caps.tunableTorque) defaultAutoDisengage=\(caps.autoDisengageDefault) defaultTorque=\(caps.defaultTorque)")
            } else {
                capabilitiesUnavailable = true
                log("Capabilities: short response")
            }
            onChange()
            // The answer came after the force had to wait for it: decide the force now,
            // behind a fresh status read like any other write.
            if forceWaitsForCapabilities {
                forceWaitsForCapabilities = false
                if supportsScrollForce, managed, desired.scrollForce != nil {
                    pendingFields.insert(.scrollForce)
                    if !statusReadOutstanding { requestStatus() }
                    return true
                }
            }
            if !statusReadOutstanding { flushPendingWork() }
            return true
        }
        if functionId == feature.readStatusFunction {
            statusReadOutstanding = false
            guard let parsed = LogiWheelProtocol.parseStatus(report, feature: feature) else {
                log("Status: short response")
                return true
            }
            if parsed != loggedStatus {
                loggedStatus = parsed
                log("Mouse: \(Self.describe(parsed))")
            }
            status = parsed
            onChange()
            flushPendingWork()
            return true
        }
        if functionId == feature.writeStatusFunction {
            return true  // set ACK; the read-back that follows carries the state
        }
        return false
    }

    /// HID++ 2.0 error for a request on this feature index.
    func handleError(functionId: UInt8, errorCode: UInt8) {
        log(String(format: "Error 0x%02X on fn%d", errorCode, functionId))
        if let capabilitiesFunction = feature.capabilitiesFunction, functionId == capabilitiesFunction {
            capabilitiesRequested = false
            capabilitiesUnavailable = true
            onChange()
            if !statusReadOutstanding { flushPendingWork() }
        } else if functionId == feature.readStatusFunction {
            statusReadOutstanding = false
            if !pendingFields.isEmpty || pendingToggle {
                log("Status read failed: nothing is written until the next connect or change")
            }
            pendingFields.removeAll()
            pendingToggle = false
            onChange()
        } else if functionId == feature.writeStatusFunction {
            onChange()  // the read-back already queued resyncs the state
        }
    }

    // MARK: - Private

    private func requestCapabilitiesIfNeeded() {
        guard let capabilitiesFunction = feature.capabilitiesFunction,
              capabilities == nil, !capabilitiesUnavailable, !capabilitiesRequested else { return }
        capabilitiesRequested = true
        capabilitiesTimedOut = false
        sendCapabilitiesRequest(capabilitiesFunction, attempt: 1)
    }

    private func sendCapabilitiesRequest(_ capabilitiesFunction: UInt8, attempt: Int) {
        capabilitiesRequestToken += 1
        let token = capabilitiesRequestToken
        send(capabilitiesFunction, [])
        schedule(Self.replyTimeout) { [weak self] in
            self?.capabilitiesReplyTimedOut(capabilitiesFunction, token: token, attempt: attempt)
        }
    }

    /// No reply (and no error) to a capabilities read. Without this the controller waited
    /// forever: `capabilitiesRequested` stayed set, so the read was never repeated, and
    /// managed settings were held back until the mouse reconnected.
    private func capabilitiesReplyTimedOut(_ capabilitiesFunction: UInt8, token: Int, attempt: Int) {
        // An answer, an error or a newer read settled this one.
        guard token == capabilitiesRequestToken, capabilitiesRequested,
              capabilities == nil, !capabilitiesUnavailable else { return }
        if attempt < Self.maxCapabilitiesAttempts {
            log("Capabilities: no reply, asking again (\(attempt + 1)/\(Self.maxCapabilitiesAttempts))")
            sendCapabilitiesRequest(capabilitiesFunction, attempt: attempt + 1)
            return
        }
        log("Capabilities: no reply, deciding without the force")
        capabilitiesRequested = false
        capabilitiesTimedOut = true
        onChange()
        if !statusReadOutstanding { flushPendingWork() }
    }

    private func requestStatus() {
        statusReadOutstanding = true
        send(feature.readStatusFunction, [])
    }

    private func flushPendingWork() {
        guard let status = status else { return }
        if !pendingFields.isEmpty {
            // The force needs to know whether the mouse can tune it; the rest does not.
            let waitsForCapabilities = pendingFields.contains(.scrollForce)
                && desired.scrollForce != nil && !capabilitiesKnown
            if !waitsForCapabilities {
                let fields = pendingFields
                pendingFields.removeAll()
                if let params = decideWrite(fields, status: status) {
                    write(params)
                    return  // a pending toggle runs after the read-back
                }
            }
        }
        if pendingToggle {
            pendingToggle = false
            let params = LogiWheelProtocol.toggleParams(from: status)
            log("SmartShift Toggle: wheelMode \(status.wheelMode) -> \(params[0])")
            write(params)
        }
    }

    /// Decides `fields` against the freshly read `status`, one log line each. Returns the
    /// set request when anything has to change, nil when nothing is written.
    private func decideWrite(_ requested: Set<Field>, status: LogiWheelStatus) -> [UInt8]? {
        guard managed else { return nil }
        var fields = requested
        // A new mode brings the user's sensitivity along: SmartShift needs a threshold.
        if fields.contains(.mode) { fields.insert(.sensitivity) }

        let mouseMode = LogiWheelProtocol.mode(for: status)
        var newMode: LogiWheelMode?
        if fields.contains(.mode) {
            if let wanted = desired.mode {
                if wanted == mouseMode {
                    log("Mode: mouse \(Self.name(mouseMode)), wanted \(Self.name(wanted)); already set, no write")
                } else {
                    newMode = wanted
                    log("Mode: mouse \(Self.name(mouseMode)), wanted \(Self.name(wanted)); writing \(Self.name(wanted))")
                }
            } else {
                log("Mode: not set by the user, left alone (mouse \(Self.name(mouseMode)))")
            }
        }

        let resultingMode = newMode ?? mouseMode
        let mouseThreshold = LogiWheelProtocol.threshold(status.autoDisengage)
        let onMouse = mouseThreshold.map { "mouse \(Self.percent(forThreshold: $0)) (threshold \($0))" }
            ?? "mouse has no threshold (always ratchet)"
        var threshold: UInt8?
        if fields.contains(.sensitivity) {
            if let wanted = desired.smartShiftSensitivity {
                let target = LogiWheelProtocol.autoDisengage(forSensitivity: wanted)
                if resultingMode != .smartShift {
                    log("SmartShift sensitivity: wanted \(wanted) %; applies only in SmartShift and the wheel is in \(Self.name(resultingMode)), left alone")
                } else if let current = mouseThreshold, LogiWheelProtocol.sensitivityMatches(wanted, threshold: current) {
                    log("SmartShift sensitivity: \(onMouse), wanted \(wanted) %; already set, no write")
                } else {
                    threshold = target
                    log("SmartShift sensitivity: \(onMouse), wanted \(wanted) %; writing threshold \(target)")
                }
            } else if newMode == .smartShift, mouseThreshold == nil {
                let fallback = LogiWheelSettings.defaultSmartShiftSensitivity
                let fallbackThreshold = LogiWheelProtocol.autoDisengage(forSensitivity: fallback)
                threshold = fallbackThreshold
                log("SmartShift sensitivity: not set by the user, but SmartShift needs a threshold and the mouse has none; writing the default \(fallbackThreshold) (\(fallback) %)")
            } else {
                log("SmartShift sensitivity: not set by the user, left alone")
            }
        }

        var torque: UInt8?
        if fields.contains(.scrollForce) {
            if let wanted = desired.scrollForce {
                let target = LogiWheelProtocol.clampedTorque(wanted)
                if supportsScrollForce {
                    if status.torque == target {
                        log("Scroll force: mouse \(target), wanted \(wanted); already set, no write")
                    } else {
                        torque = target
                        log("Scroll force: mouse \(status.torque.map(String.init) ?? "unknown"), wanted \(wanted); writing \(target)")
                    }
                } else if feature == .smartShiftEnhanced, capabilitiesTimedOut {
                    forceWaitsForCapabilities = true
                    log("Scroll force: wanted \(wanted); the mouse has not said whether it can tune it, waiting for that")
                } else {
                    log("Scroll force: wanted \(wanted); this mouse cannot tune it, not writing")
                }
            } else {
                log("Scroll force: not set by the user, left alone")
            }
        }

        let params = LogiWheelProtocol.setParams(
            mode: newMode, threshold: threshold, torque: torque, current: status, feature: feature
        )
        guard LogiWheelProtocol.needsWrite(params, current: status) else { return nil }
        log("Writing \(params.map { String(format: "%02X", $0) }.joined(separator: " ")), then reading back")
        return params
    }

    // MARK: - Snapshot

    /// What the Mouse tab shows for this wheel: what the mouse reports and what the user set.
    func deviceState(id: String, deviceName: String) -> LogiWheelDeviceState {
        return LogiWheelDeviceState(
            id: id,
            deviceName: deviceName,
            supportsSmartShift: true,
            supportsScrollForce: supportsScrollForce,
            mode: .init(onMouse: mode, setByYou: desired.mode),
            smartShiftSensitivity: .init(
                onMouse: smartShiftSensitivity,
                setByYou: desired.smartShiftSensitivity.map(LogiWheelProtocol.sensitivityAsKept)
            ),
            scrollForce: .init(
                onMouse: scrollForce,
                setByYou: desired.scrollForce.map { Int(LogiWheelProtocol.clampedTorque($0)) }
            )
        )
    }

    // MARK: - Log text

    static func describe(_ settings: LogiWheelSettings) -> String {
        var parts: [String] = []
        if let mode = settings.mode { parts.append("mode \(name(mode))") }
        if let sensitivity = settings.smartShiftSensitivity { parts.append("SmartShift sensitivity \(sensitivity) %") }
        if let force = settings.scrollForce { parts.append("scroll force \(force)") }
        return parts.isEmpty ? "no wheel value set by the user" : "user set " + parts.joined(separator: ", ")
    }

    static func describe(_ status: LogiWheelStatus) -> String {
        let threshold = LogiWheelProtocol.threshold(status.autoDisengage)
            .map { "threshold \($0) (\(percent(forThreshold: $0)))" } ?? "no threshold"
        return "\(name(LogiWheelProtocol.mode(for: status))) (wheelMode \(status.wheelMode)), \(threshold), torque \(status.torque.map(String.init) ?? "-")"
    }

    static func name(_ mode: LogiWheelMode?) -> String {
        switch mode {
        case .smartShift?: return "SmartShift"
        case .ratchet?: return "ratchet"
        case .freeSpin?: return "free-spin"
        case nil: return "unknown"
        }
    }

    private static func percent(forThreshold threshold: UInt8) -> String {
        return LogiWheelProtocol.sensitivity(forAutoDisengage: threshold).map { "\($0) %" } ?? "-"
    }

    private func write(_ params: [UInt8]) {
        send(feature.writeStatusFunction, params)
        requestStatus()
    }
}
