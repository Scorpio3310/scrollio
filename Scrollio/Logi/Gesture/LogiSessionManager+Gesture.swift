//
//  LogiSessionManager+Gesture.swift
//  Mos
//
//  Gesture Navigation across sessions, for LogiCenter: which Logitech buttons should be
//  tracked by the mouse itself (raw XY), which device a held button belongs to (so a haptic
//  cue goes to that mouse and no other), and what the connected mice can do.
//

import Foundation

/// The device a button was last pressed on: one session, and on a receiver one slot of it.
struct LogiGestureHoldOwner {
    weak var session: LogiDeviceSession?
    let slot: UInt8
}

extension LogiSessionManager {

    /// Stores the request for devices that connect later. Returns false when nothing changed.
    @discardableResult
    func setGestureTrackingCodes(_ codes: Set<UInt16>) -> Bool {
        guard codes != gestureTrackingCodes else { return false }
        gestureTrackingCodes = codes
        return true
    }

    /// Called for every diverted button-down, before the event is dispatched.
    func noteButtonPress(scrollioCode: UInt16, session: LogiDeviceSession, slot: UInt8) {
        gestureHoldOwners[scrollioCode] = LogiGestureHoldOwner(session: session, slot: slot)
    }

    /// Plays the cue on the mouse the button was last pressed on. Returns whether a pulse
    /// was sent: false without such a mouse, without haptics, or with haptics switched off.
    @discardableResult
    func playGestureHaptic(_ cue: MouseGestureHapticCue, forScrollioCode code: UInt16) -> Bool {
        guard let owner = gestureHoldOwners[code] else {
            LogiSystemLog.note("Haptic cue \(cue) skipped: no mouse owns button code \(code)")
            return false
        }
        guard let session = owner.session else {
            gestureHoldOwners[code] = nil
            LogiSystemLog.note("Haptic cue \(cue) skipped: the mouse of button code \(code) is gone")
            return false
        }
        return session.playGestureHaptic(cue, slot: owner.slot)
    }

    var supportsGestureDeviceTracking: Bool {
        return activeSessions.contains { $0.isHIDPPCandidate && $0.supportsGestureRawXY }
    }

    var supportsGestureHaptics: Bool {
        return activeSessions.contains { $0.isHIDPPCandidate && $0.supportsGestureHaptics }
    }

    /// Re-reads whether haptics are switched on; the user can change that outside Scrollio.
    func refreshGestureStates() {
        for session in activeSessions where session.isHIDPPCandidate {
            session.refreshGestureHaptics()
        }
    }

    /// Coalesced `LogiCenter.gestureStateChanged`, always on the main thread.
    func notifyGestureStateChanged() {
        guard !gestureStateNotificationScheduled else { return }
        gestureStateNotificationScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.gestureStateNotificationScheduled = false
            NotificationCenter.default.post(name: LogiCenter.gestureStateChanged, object: nil)
        }
    }
}
