//
//  LogiGestureTypes.swift
//  Mos
//
//  Public surface for what Logitech mice add to Gesture Navigation. The app uses only the
//  LogiCenter members below and the device-neutral types of Scrollio/InputEvent
//  (MouseGestureHapticCue, InputEvent.tracksMovementOnDevice); raw XY diversion and the
//  haptic feature stay inside Scrollio/Logi.
//
//  App -> Logi (LogiCenter.swift, they need the private session manager):
//    func setGestureTrackingCodes(_ codes: Set<UInt16>)
//    func playGestureHaptic(_ cue: MouseGestureHapticCue, forScrollioCode code: UInt16)
//    func supportsGestureDeviceTracking() -> Bool
//    func supportsGestureHaptics() -> Bool
//    func refreshGestureStates()
//
//  Logi -> app (LogiExternalBridge):
//    a button-down with `tracksMovementOnDevice` set, then
//    func handleLogiGestureMovement(code: UInt16, deltaX: Int, deltaY: Int)
//    for every movement sample of that hold, in sensor counts.
//

import Foundation

extension LogiCenter {
    /// Posted on the main thread whenever `supportsGestureDeviceTracking()` or
    /// `supportsGestureHaptics()` may have changed.
    static let gestureStateChanged = Notification.Name("LogiGestureStateChanged")
}
