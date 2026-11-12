//
//  LogiSessionManager+Basics.swift
//  Mos
//
//  Aggregates the basic mouse settings (battery, pointer speed, haptics, press force)
//  across sessions for LogiCenter, and fans the user's choices out to every connected
//  mouse. Nothing is written unless `managed` is on; see LogiMouseBasicsController.
//

import Foundation

extension LogiSessionManager {

    /// How long a sample pulse waits for the settings push that usually follows it (the
    /// Integration layer settles slider drags for 0.25 s). Without a push it plays then.
    static let hapticSampleWaitForSettings: TimeInterval = 0.5

    /// Stores the settings for mice that connect later and hands them to every connected
    /// mouse. A sample pulse waiting for this push plays right behind the writes it causes.
    func applyMouseSettings(_ settings: LogiMouseSettings, managed: Bool) {
        let changed = settings != mouseSettings || managed != mouseManaged
        if changed {
            LogiSystemLog.note("Mouse settings: \(managed ? "managed" : "not managed"), \(LogiMouseBasicsController.describe(settings))")
        }
        mouseSettings = settings
        mouseManaged = managed
        for session in activeSessions where session.isHIDPPCandidate {
            session.applyMouseSettings(settings, managed: managed)
        }
        if hapticSamplePending { flushHapticSample() }
        if changed { notifyMouseStateChanged() }
    }

    /// Whether a gesture cue may switch a mouse's haptics on when it finds them off. Once
    /// the user switched haptics off in these settings it may not (managed or not: the user
    /// said off); while the setting was never touched (nil), cues switch them on as before.
    var gestureCuesMayEnableHaptics: Bool {
        return mouseSettings.hapticsOn != false
    }

    /// Re-reads the basics and the wheels of every connected mouse. Posts
    /// `mouseStateChanged` as answers arrive, or once right away when there is nothing to read.
    func refreshMouseStates() {
        var anyBasics = false
        for session in activeSessions where session.isHIDPPCandidate {
            if session.refreshMouseBasics() { anyBasics = true }
        }
        refreshWheelStates()
        if !anyBasics { notifyMouseStateChanged() }
    }

    /// "Send Again": every connected mouse starts over as on a reconnect (its controllers'
    /// `start`), with the settings stored here: read again, then written only where the
    /// switch is on, the user set the value and the fresh read differs. Without the switch
    /// it is a plain refresh: nothing is written. Posts `mouseStateChanged` right away, so the
    /// tab shows "still sending" while the mice answer.
    func sendMouseSettingsAgain() {
        guard mouseManaged || wheelSettings.managedByMos else {
            LogiSystemLog.note("Send Again: not managed, reading only")
            refreshMouseStates()
            return
        }
        LogiSystemLog.note("Send Again: reading every mouse again, then writing what the user set and it reports differently")
        for session in activeSessions where session.isHIDPPCandidate {
            session.startMouseSettingsAgain(mouse: mouseSettings, managed: mouseManaged, wheel: wheelSettings)
        }
        notifyMouseStateChanged()
    }

    func mouseDeviceStates() -> [LogiMouseDeviceState] {
        let states = activeSessions
            .filter { $0.isHIDPPCandidate }
            .flatMap { $0.mouseDeviceStates() }
            .sorted { ($0.deviceName, $0.id) < ($1.deviceName, $1.id) }
        return Self.disambiguatedMouseStates(states)
    }

    /// Two identical mice share VID:PID; suffix later duplicates so ids stay unique (the
    /// wheel state inside gets the same id).
    static func disambiguatedMouseStates(_ states: [LogiMouseDeviceState]) -> [LogiMouseDeviceState] {
        var seen: [String: Int] = [:]
        return states.map { state in
            let count = seen[state.id, default: 0]
            seen[state.id] = count + 1
            guard count > 0 else { return state }
            let id = "\(state.id)#\(count + 1)"
            let wheel = state.wheel.map { $0.withId(id) }
            return LogiMouseDeviceState(
                id: id,
                deviceName: state.deviceName,
                supported: state.supported,
                managed: state.managed,
                battery: state.battery,
                pointerSpeed: state.pointerSpeed,
                haptics: state.haptics,
                pressForce: state.pressForce,
                wheel: wheel
            )
        }
    }

    /// One pulse at the mouse's current strength on every connected mouse with haptics on.
    /// It waits for the settings push that a strength change sends right after (so it is felt
    /// at the new strength), at most `hapticSampleWaitForSettings`.
    func playHapticSample() {
        hapticSampleToken += 1
        let token = hapticSampleToken
        hapticSamplePending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hapticSampleWaitForSettings) { [weak self] in
            guard let self = self, self.hapticSamplePending, self.hapticSampleToken == token else { return }
            self.flushHapticSample()
        }
    }

    private func flushHapticSample() {
        hapticSamplePending = false
        for session in activeSessions where session.isHIDPPCandidate {
            session.playHapticSample()
        }
    }

    /// Coalesced `LogiCenter.mouseStateChanged`: many answers in one run-loop turn produce
    /// one post, always on the main thread.
    func notifyMouseStateChanged() {
        guard !mouseStateNotificationScheduled else { return }
        mouseStateNotificationScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.mouseStateNotificationScheduled = false
            NotificationCenter.default.post(name: LogiCenter.mouseStateChanged, object: nil)
        }
    }
}
