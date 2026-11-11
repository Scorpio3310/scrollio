//
//  LogiWheelController.swift
//  Mos
//
//  Per-device (per receiver slot) scroll-wheel state machine for SmartShift (0x2110)
//  and SmartShift Enhanced (0x2111). It owns no transport: the session injects a
//  `send` closure and forwards responses, so the logic is testable with fake bytes.
//
//  Rules:
//  - Reads first, writes only for managed settings and only after a fresh status read,
//    and only when something actually differs (values live in device NVM).
//  - Every write is followed by a read-back.
//  - The capabilities read has a reply timeout. A lost reply is asked for again; when
//    the mouse stays silent, managed settings are written without the torque byte
//    instead of waiting for a reply that never comes, and the next refresh asks again.
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
    /// Managed settings waiting for a fresh status read before they are written.
    private(set) var pendingSettings: LogiWheelSettings?
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
    /// Managed settings that went out without the torque byte because the capabilities read
    /// timed out. Applied once more, in full, if the capabilities arrive after all.
    private var settingsAppliedWithoutCapabilities: LogiWheelSettings?

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

    /// First contact after discovery: read capabilities + status, then apply `desired`
    /// if (and only if) it is managed by Mos.
    func start(desired: LogiWheelSettings) {
        pendingSettings = desired.managedByMos ? desired : nil
        settingsAppliedWithoutCapabilities = nil
        refresh()
    }

    /// Re-reads capabilities (once) and status.
    func refresh() {
        requestCapabilitiesIfNeeded()
        requestStatus()
    }

    /// Writes `settings` after a fresh status read. No-op (and drops anything queued)
    /// when the settings are not managed by Mos.
    func apply(_ settings: LogiWheelSettings) {
        settingsAppliedWithoutCapabilities = nil
        guard settings.managedByMos else {
            pendingSettings = nil
            return
        }
        pendingSettings = settings
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
                log("capabilities: tunableTorque=\(caps.tunableTorque) defaultAutoDisengage=\(caps.autoDisengageDefault) defaultTorque=\(caps.defaultTorque)")
            } else {
                capabilitiesUnavailable = true
                log("capabilities: short response")
            }
            onChange()
            // The answer came after the settings had gone out without torque: apply them
            // again, behind a fresh status read like any other write.
            let incomplete = settingsAppliedWithoutCapabilities
            settingsAppliedWithoutCapabilities = nil
            if let incomplete, supportsScrollForce, pendingSettings == nil {
                pendingSettings = incomplete
                requestStatus()
                return true
            }
            if !statusReadOutstanding { flushPendingWork() }
            return true
        }
        if functionId == feature.readStatusFunction {
            statusReadOutstanding = false
            guard let parsed = LogiWheelProtocol.parseStatus(report, feature: feature) else {
                log("status: short response")
                return true
            }
            status = parsed
            log("status: wheelMode=\(parsed.wheelMode) autoDisengage=\(parsed.autoDisengage) torque=\(parsed.torque.map(String.init) ?? "-")")
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
        log(String(format: "error 0x%02X on fn%d", errorCode, functionId))
        if let capabilitiesFunction = feature.capabilitiesFunction, functionId == capabilitiesFunction {
            capabilitiesRequested = false
            capabilitiesUnavailable = true
            onChange()
            if !statusReadOutstanding { flushPendingWork() }
        } else if functionId == feature.readStatusFunction {
            statusReadOutstanding = false
            pendingSettings = nil
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
            log("capabilities: no reply, asking again (\(attempt + 1)/\(Self.maxCapabilitiesAttempts))")
            sendCapabilitiesRequest(capabilitiesFunction, attempt: attempt + 1)
            return
        }
        log("capabilities: no reply, continuing without torque")
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
        if let settings = pendingSettings, capabilitiesKnown {
            pendingSettings = nil
            settingsAppliedWithoutCapabilities = capabilitiesTimedOut ? settings : nil
            let params = LogiWheelProtocol.setParams(
                for: settings,
                feature: feature,
                supportsTorque: supportsScrollForce
            )
            if LogiWheelProtocol.needsWrite(params, current: status) {
                log("apply \(settings.mode.rawValue): params=\(params.map { String(format: "%02X", $0) }.joined(separator: " "))")
                write(params)
                return  // a pending toggle runs after the read-back
            }
            log("apply \(settings.mode.rawValue): device already matches, no write")
        }
        if pendingToggle {
            pendingToggle = false
            let params = LogiWheelProtocol.toggleParams(from: status)
            log("toggle: wheelMode \(status.wheelMode) -> \(params[0])")
            write(params)
        }
    }

    private func write(_ params: [UInt8]) {
        send(feature.writeStatusFunction, params)
        requestStatus()
    }
}
