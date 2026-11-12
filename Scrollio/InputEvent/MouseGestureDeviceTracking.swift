//
//  MouseGestureDeviceTracking.swift
//  Mos
//
//  What a mouse can contribute to Gesture Navigation beyond its button: the movement of the
//  hold (instead of the pointer) and haptic cues. Device-neutral on purpose; the Logitech
//  side lives behind LogiCenter.
//

import Cocoa

/// Where the movement of one gesture-button hold comes from. Decided when the button goes
/// down and never changed during the hold, so no movement is counted twice.
enum MouseGestureMovementSource: Equatable {
    /// Pointer movement seen by the motion event tap (the default).
    case pointer
    /// Movement the mouse reports itself while the button is held. The mouse keeps the
    /// pointer still, so there is nothing to freeze and nothing to read from the event tap.
    case device
}

enum MouseGestureDeviceTracking {
    /// Points of gesture travel per sensor count reported by the mouse.
    ///
    /// THE tuning knob of device tracking. Sensor counts are raw: no pointer acceleration,
    /// and their size follows the mouse's DPI setting. At the 1000 DPI an MX Master ships
    /// with, 0.5 means:
    /// - 2 mm of hand travel reach the 40 pt of a discrete gesture,
    /// - 0.5 mm stays inside the 10 pt click tolerance,
    /// - 77 mm drag the desktop across a 1512 pt wide screen at tracking speed 1.
    /// Raise it if gestures need too much travel, lower it if they trigger too easily.
    static let pointsPerCount: CGFloat = 0.5
}

/// A short pulse a mouse with a haptic motor can play during a gesture.
enum MouseGestureHapticCue: Equatable {
    /// Light: the gesture locked in (a discrete action fired, or the swipe began).
    case lockIn
    /// Stronger: a "follow the hand" swipe was released towards a switch.
    case commit
}
