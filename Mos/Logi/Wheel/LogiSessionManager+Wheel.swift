//
//  LogiSessionManager+Wheel.swift
//  Mos
//
//  Aggregates scroll-wheel state across sessions for LogiCenter, and fans the
//  user's wheel settings out to every connected device that supports them.
//

import Foundation

extension LogiSessionManager {

    /// Stores `settings` for devices that connect later, and writes them to every
    /// connected wheel when (and only when) `settings.managedByMos` is true.
    func applyWheelSettings(_ settings: LogiWheelSettings) {
        wheelSettings = settings
        guard settings.managedByMos else { return }
        for session in activeSessions where session.isHIDPPCandidate {
            session.applyWheelSettings(settings)
        }
    }

    /// Re-reads every connected wheel. Posts `wheelStateChanged` as answers arrive,
    /// or once right away when there is nothing to read.
    func refreshWheelStates() {
        var anyWheel = false
        for session in activeSessions where session.isHIDPPCandidate {
            if session.refreshWheelStates() { anyWheel = true }
        }
        if !anyWheel { notifyWheelStateChanged() }
    }

    func wheelDeviceStates() -> [LogiWheelDeviceState] {
        let states = activeSessions
            .filter { $0.isHIDPPCandidate }
            .flatMap { $0.wheelDeviceStates() }
            .sorted { ($0.deviceName, $0.id) < ($1.deviceName, $1.id) }
        return Self.disambiguatedWheelStates(states)
    }

    /// Two identical mice share VID:PID; suffix later duplicates so ids stay unique.
    static func disambiguatedWheelStates(_ states: [LogiWheelDeviceState]) -> [LogiWheelDeviceState] {
        var seen: [String: Int] = [:]
        return states.map { state in
            let count = seen[state.id, default: 0]
            seen[state.id] = count + 1
            guard count > 0 else { return state }
            return LogiWheelDeviceState(
                id: "\(state.id)#\(count + 1)",
                deviceName: state.deviceName,
                supportsSmartShift: state.supportsSmartShift,
                supportsScrollForce: state.supportsScrollForce,
                mode: state.mode,
                smartShiftSensitivity: state.smartShiftSensitivity,
                scrollForce: state.scrollForce
            )
        }
    }

    /// Coalesced `LogiCenter.wheelStateChanged`: many responses in one run-loop turn
    /// produce one post, always on the main thread.
    func notifyWheelStateChanged() {
        // The mouse states carry the wheel state too.
        notifyMouseStateChanged()
        guard !wheelStateNotificationScheduled else { return }
        wheelStateNotificationScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.wheelStateNotificationScheduled = false
            NotificationCenter.default.post(name: LogiCenter.wheelStateChanged, object: nil)
        }
    }
}
