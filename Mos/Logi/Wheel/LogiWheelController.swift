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
//  - Main thread only (HID++ callbacks run on the main run loop).
//

import Foundation

final class LogiWheelController {

    typealias Send = (_ functionId: UInt8, _ params: [UInt8]) -> Void

    let feature: LogiWheelFeature
    let featureIndex: UInt8

    private let send: Send
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

    init(
        feature: LogiWheelFeature,
        featureIndex: UInt8,
        send: @escaping Send,
        onChange: @escaping () -> Void,
        log: @escaping (String) -> Void = { _ in }
    ) {
        self.feature = feature
        self.featureIndex = featureIndex
        self.send = send
        self.onChange = onChange
        self.log = log
    }

    // MARK: - Derived state

    /// Ratchet force can be tuned (0x2111 with the tunable-torque capability bit).
    var supportsScrollForce: Bool {
        return feature == .smartShiftEnhanced && capabilities?.tunableTorque == true
    }

    /// Torque support is known (0x2110 has nothing to ask; 0x2111 needs getCapabilities).
    var capabilitiesKnown: Bool {
        return feature.capabilitiesFunction == nil || capabilities != nil || capabilitiesUnavailable
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
            if let caps = LogiWheelProtocol.parseCapabilities(report) {
                capabilities = caps
                log("capabilities: tunableTorque=\(caps.tunableTorque) defaultAutoDisengage=\(caps.autoDisengageDefault) defaultTorque=\(caps.defaultTorque)")
            } else {
                capabilitiesUnavailable = true
                log("capabilities: short response")
            }
            onChange()
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
        send(capabilitiesFunction, [])
    }

    private func requestStatus() {
        statusReadOutstanding = true
        send(feature.readStatusFunction, [])
    }

    private func flushPendingWork() {
        guard let status = status else { return }
        if let settings = pendingSettings, capabilitiesKnown {
            pendingSettings = nil
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
