//
//  LogiSessionManager+Wheel.swift
//  Mos
//
//  Aggregates scroll-wheel state across sessions for LogiCenter, and fans the
//  user's wheel settings out to every connected device that supports them.
//

import Foundation

extension LogiSessionManager {

    /// Stores `settings` for devices that connect later and hands them to every connected
    /// wheel. A wheel writes only while `settings.managedByScrollio` is true, and only the values
    /// the user set (see LogiWheelController).
    func applyWheelSettings(_ settings: LogiWheelSettings) {
        if settings != wheelSettings {
            LogiSystemLog.note("Wheel settings: \(settings.managedByScrollio ? "managed" : "not managed"), \(LogiWheelController.describe(settings))")
        }
        wheelSettings = settings
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
            return state.withId("\(state.id)#\(count + 1)")
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

extension LogiWheelDeviceState {
    /// The same state under another id (a second mouse of the same model).
    func withId(_ id: String) -> LogiWheelDeviceState {
        return LogiWheelDeviceState(
            id: id,
            deviceName: deviceName,
            supportsSmartShift: supportsSmartShift,
            supportsScrollForce: supportsScrollForce,
            mode: mode,
            smartShiftSensitivity: smartShiftSensitivity,
            scrollForce: scrollForce
        )
    }
}
