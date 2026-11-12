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
//  - Why a set value differs from the mouse (`LogiMouseDeviceState.Mismatch`) comes from the
//    same bookkeeping: a value waiting for its decision or its read-back, the mouse's answer
//    to the write (acknowledged or an error), what the read-back showed. It is shown only;
//    no write decision reads it. Status reads have no timeout, so a lost answer shows as
//    "still sending" until the next status answer (a refresh) settles it.
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

    /// What the user wants; `managedByScrollio` is the switch.
    private(set) var desired = LogiWheelSettings.default
    var managed: Bool { desired.managedByScrollio }
    /// Values waiting for a fresh status read before they are decided (written or not).
    private(set) var pendingFields: Set<Field> = []
    /// "SmartShift Toggle" waiting for the current mode.
    private(set) var pendingToggle = false
    /// Identifies the press a toggle timeout belongs to.
    private var toggleToken = 0

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

    // MARK: Why a set value differs (display only: no write decision reads these)

    private enum WriteAnswer {
        case waiting
        case acknowledged
        case refused
    }

    private enum Outcome {
        /// The mouse took the user's value or had it already.
        case taken
        case refused
        case unanswered
        case notKept
    }

    /// What became of each value the user set since the connect or since the user changed it.
    private var outcomes: [Field: Outcome] = [:]
    /// The user's values the last write carried, until its read-back arrives.
    private var writtenFields: Set<Field> = []
    private var writeAnswer = WriteAnswer.waiting
    /// Status reads sent and not answered yet, and how many of them went out before that
    /// write: their answers come before its read-back (see `statusAnswered`).
    private var statusReadsInFlight = 0
    private var statusReadsBeforeWrite = 0
    /// The reasons last announced with `onChange`.
    private var announcedMismatches: [Field: LogiMouseDeviceState.Mismatch] = [:]

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
        pendingFields = desired.managedByScrollio ? Set(Field.allCases) : []
        forceWaitsForCapabilities = false
        loggedStatus = nil
        outcomes.removeAll()
        writtenFields.removeAll()
        log("Connected: \(String(format: "0x%04X", feature.featureId)) at index \(String(format: "0x%02X", featureIndex)); \(desired.managedByScrollio ? "managed, \(Self.describe(desired))" : "not managed, reading only")")
        refresh()
    }

    /// Re-reads capabilities (once) and status. Decides only what is still pending.
    func refresh() {
        requestCapabilitiesIfNeeded()
        requestStatus()
        announceMismatchChanges()
    }

    /// New settings or a new state of the switch. A value the user changed (or every value,
    /// when the switch was just turned on) is decided after a fresh status read. Turned off,
    /// nothing is written and anything still pending is dropped.
    func apply(_ settings: LogiWheelSettings) {
        let old = desired
        desired = settings
        if settings != old { onChange() }  // what the user set is part of the shown state
        if settings.managedByScrollio != old.managedByScrollio {
            log(settings.managedByScrollio ? "Managed from now on: \(Self.describe(settings))" : "Not managed any more: nothing is written")
        }
        guard settings.managedByScrollio else {
            pendingFields.removeAll()
            forceWaitsForCapabilities = false
            announceMismatchChanges()
            return
        }
        let turnedOn = !old.managedByScrollio
        var changed: Set<Field> = []
        if turnedOn || settings.mode != old.mode { changed.insert(.mode) }
        if turnedOn || settings.smartShiftSensitivity != old.smartShiftSensitivity { changed.insert(.sensitivity) }
        if turnedOn || settings.scrollForce != old.scrollForce {
            changed.insert(.scrollForce)
            forceWaitsForCapabilities = false
        }
        guard !changed.isEmpty else {
            announceMismatchChanges()
            return
        }
        for field in changed { outcomes.removeValue(forKey: field) }
        pendingFields.formUnion(changed)
        refresh()
    }

    /// Flips free-spin <-> ratchet, keeping threshold and torque.
    /// The press does not stay armed: when the mouse has not answered within
    /// `replyTimeout`, it is dropped. It used to wait for ever, and the wheel mode then
    /// flipped by itself minutes later, when some other read of the wheel was answered (the
    /// status menu opening, the Mouse pane).
    func toggleMode() {
        pendingToggle = true
        toggleToken += 1
        let token = toggleToken
        requestStatus()
        schedule(Self.replyTimeout) { [weak self] in
            guard let self = self, self.pendingToggle, self.toggleToken == token else { return }
            self.pendingToggle = false
            self.log("SmartShift Toggle: no answer from the mouse within \(Int(Self.replyTimeout)) s, the press is dropped")
        }
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
                    announceMismatchChanges()
                    return true
                }
            }
            if !statusReadOutstanding { flushPendingWork() }
            announceMismatchChanges()
            return true
        }
        if functionId == feature.readStatusFunction {
            statusReadOutstanding = false
            guard let parsed = LogiWheelProtocol.parseStatus(report, feature: feature) else {
                log("Status: short response")
                statusAnswered(nil, refused: false)
                announceMismatchChanges()
                return true
            }
            if parsed != loggedStatus {
                loggedStatus = parsed
                log("Mouse: \(Self.describe(parsed))")
            }
            status = parsed
            statusAnswered(parsed, refused: false)
            onChange()
            flushPendingWork()
            announceMismatchChanges()
            return true
        }
        if functionId == feature.writeStatusFunction {
            // Set ACK; the read-back that follows carries the state.
            if !writtenFields.isEmpty, writeAnswer == .waiting { writeAnswer = .acknowledged }
            return true
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
            for field in pendingFields where isSet(field) { outcomes[field] = .refused }
            statusAnswered(nil, refused: true)
            pendingFields.removeAll()
            pendingToggle = false
            onChange()
        } else if functionId == feature.writeStatusFunction {
            if !writtenFields.isEmpty, writeAnswer == .waiting { writeAnswer = .refused }
            onChange()  // the read-back already queued resyncs the state
        }
        announceMismatchChanges()
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
        announceMismatchChanges()
    }

    private func requestStatus() {
        statusReadOutstanding = true
        statusReadsInFlight += 1
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

        for field in fields { outcomes.removeValue(forKey: field) }
        let mouseMode = LogiWheelProtocol.mode(for: status)
        var newMode: LogiWheelMode?
        if fields.contains(.mode) {
            if let wanted = desired.mode {
                if wanted == mouseMode {
                    log("Mode: mouse \(Self.name(mouseMode)), wanted \(Self.name(wanted)); already set, no write")
                    outcomes[.mode] = .taken
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
                    outcomes[.sensitivity] = .taken
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
                        outcomes[.scrollForce] = .taken
                    } else {
                        torque = target
                        log("Scroll force: mouse \(status.torque.map(String.init) ?? "unknown"), wanted \(wanted); writing \(target)")
                    }
                } else if feature == .smartShiftEnhanced, capabilitiesTimedOut {
                    forceWaitsForCapabilities = true
                    outcomes[.scrollForce] = .unanswered
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
        // The user's values this write carries (a factory threshold is not one of them).
        var carried: Set<Field> = []
        if newMode != nil { carried.insert(.mode) }
        if threshold != nil, desired.smartShiftSensitivity != nil { carried.insert(.sensitivity) }
        if torque != nil { carried.insert(.scrollForce) }
        guard LogiWheelProtocol.needsWrite(params, current: status) else {
            for field in carried { outcomes[field] = .taken }
            return nil
        }
        log("Writing \(params.map { String(format: "%02X", $0) }.joined(separator: " ")), then reading back")
        // `write` sends the read-back next: the reads already on their way come before it.
        writtenFields = carried
        writeAnswer = .waiting
        statusReadsBeforeWrite = statusReadsInFlight
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
            mode: value(.mode, onMouse: mode, setByYou: desired.mode),
            smartShiftSensitivity: value(
                .sensitivity,
                onMouse: smartShiftSensitivity,
                setByYou: desired.smartShiftSensitivity.map(LogiWheelProtocol.sensitivityAsKept)
            ),
            scrollForce: value(
                .scrollForce,
                onMouse: scrollForce,
                setByYou: desired.scrollForce.map { Int(LogiWheelProtocol.clampedTorque($0)) }
            )
        )
    }

    private func value<T: Equatable>(_ field: Field, onMouse: T?, setByYou: T?) -> LogiMouseDeviceState.Value<T> {
        let differs = setByYou != nil && setByYou != onMouse
        return LogiMouseDeviceState.Value(onMouse: onMouse, setByYou: setByYou, mismatch: differs ? mismatch(field) : nil)
    }

    // MARK: - Why a set value differs

    private func isSet(_ field: Field) -> Bool {
        switch field {
        case .mode: return desired.mode != nil
        case .sensitivity: return desired.smartShiftSensitivity != nil
        case .scrollForce: return desired.scrollForce != nil
        }
    }

    /// Why the user's value of `field` may not be on the mouse; nil while not managed, while
    /// it is not set, or when nothing is known. Shown only when the values differ.
    private func mismatch(_ field: Field) -> LogiMouseDeviceState.Mismatch? {
        guard managed, isSet(field) else { return nil }
        // Waiting for the status read that decides it, or for the read-back of its write.
        if pendingFields.contains(field) || (writtenFields.contains(field) && statusReadsInFlight > 0) {
            return .sending
        }
        switch outcomes[field] {
        case .taken?: return .changedElsewhere
        case .refused?: return .refused
        case .unanswered?: return .noAnswer
        case .notKept?: return .notKept
        case nil: return nil
        }
    }

    /// A status read was answered (`status` nil: unreadable, or an error when `refused`).
    /// The answer to the read sent right after a write is its read-back: it tells what
    /// became of the values that write carried. Answers come in request order, so it is the
    /// first status answer after the write's own answer; when that answer was lost, the
    /// first one after the reads that went out before the write.
    private func statusAnswered(_ status: LogiWheelStatus?, refused: Bool) {
        statusReadsInFlight = max(0, statusReadsInFlight - 1)
        guard !writtenFields.isEmpty else { return }
        if writeAnswer == .waiting, statusReadsBeforeWrite > 0 {
            statusReadsBeforeWrite -= 1
            return
        }
        let fields = writtenFields
        writtenFields.removeAll()
        for field in fields {
            if let status, mouseHasTheUserValue(field, status: status) {
                outcomes[field] = .taken
                continue
            }
            switch writeAnswer {
            case .refused: outcomes[field] = .refused
            case .acknowledged: outcomes[field] = status == nil ? (refused ? .refused : .unanswered) : .notKept
            case .waiting: outcomes[field] = .unanswered
            }
        }
    }

    private func mouseHasTheUserValue(_ field: Field, status: LogiWheelStatus) -> Bool {
        switch field {
        case .mode:
            return desired.mode == LogiWheelProtocol.mode(for: status)
        case .sensitivity:
            guard let wanted = desired.smartShiftSensitivity,
                  let threshold = LogiWheelProtocol.threshold(status.autoDisengage) else { return false }
            return LogiWheelProtocol.sensitivityMatches(wanted, threshold: threshold)
        case .scrollForce:
            guard let wanted = desired.scrollForce else { return false }
            return status.torque == LogiWheelProtocol.clampedTorque(wanted)
        }
    }

    /// One `onChange` when the reason of any value changed.
    private func announceMismatchChanges() {
        var now: [Field: LogiMouseDeviceState.Mismatch] = [:]
        for field in Field.allCases {
            if let reason = mismatch(field) { now[field] = reason }
        }
        guard now != announcedMismatches else { return }
        announcedMismatches = now
        onChange()
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
