//
//  MouseGestureSettings.swift
//  Mos
//
//  User settings for the Gesture Navigation action: one action per direction plus click
//  (`GestureActions`, with the name and icon of a recorded key combination), horizontal
//  inversion, pointer freeze, the gesture mode and what a Logitech mouse may do itself
//  (track the movement, play haptic cues). Shared by every Gesture Navigation binding.
//
//  Stored as one JSON entry (UserDefaults key "mouseGestureSettings"): the actions' keys
//  ("upAction" … "clickAction", and "upLabel" … only where a label is) beside the others.
//

import Foundation

/// How a held gesture button turns movement into actions.
enum MouseGestureMode: String, Codable, Equatable {
    /// One action per hold, once the movement passes the activation distance.
    case discrete
    /// Sideways movement drives an interactive Spaces swipe that follows the hand; up, down
    /// and click keep their discrete actions.
    case interactive
}

struct MouseGestureSettings: Codable, Equatable {
    /// Allowed range of `trackingSpeed`.
    static let trackingSpeedRange: ClosedRange<Double> = 0.5...3
    static let defaultTrackingSpeed: Double = 1

    /// The action of every direction and of the click. Their names are those of button
    /// bindings (`SystemShortcut` identifiers, Logi actions, mouse button actions, a
    /// recorded key combination); an empty one means "no action".
    var actions: GestureActions

    /// The stored names alone. Setting another name drops the label of a recorded key
    /// combination; the same name keeps it.
    var upAction: String {
        get { return actions.up.action }
        set { actions.up = actions.up.replacingAction(with: newValue) }
    }
    var downAction: String {
        get { return actions.down.action }
        set { actions.down = actions.down.replacingAction(with: newValue) }
    }
    var leftAction: String {
        get { return actions.left.action }
        set { actions.left = actions.left.replacingAction(with: newValue) }
    }
    var rightAction: String {
        get { return actions.right.action }
        set { actions.right = actions.right.replacingAction(with: newValue) }
    }
    var clickAction: String {
        get { return actions.click.action }
        set { actions.click = actions.click.replacingAction(with: newValue) }
    }
    /// Swaps the physical left/right movement, so moving left runs `rightAction`.
    var invertHorizontal: Bool
    /// Keeps the pointer in place while the gesture button is held.
    var freezePointer: Bool
    /// `.discrete` is the classic behaviour; `.interactive` needs `DockSwipeSynthesizer`.
    var mode: MouseGestureMode
    /// Interactive mode: desktop travel per unit of pointer travel. 1 moves the desktop as far
    /// as the pointer would have moved. Always within `trackingSpeedRange`.
    var trackingSpeed: Double {
        didSet { trackingSpeed = Self.clampedTrackingSpeed(trackingSpeed) }
    }
    /// "Let the mouse track the gesture" (experimental, off by default): a Logitech control
    /// that can divert raw XY reports the movement over HID++ while it is held and the mouse
    /// keeps the pointer still itself. Anything else keeps reading pointer movement.
    var deviceTracking: Bool
    /// Haptic cues on mice that have them (MX Master 4): a light pulse when a gesture locks
    /// in, a stronger one when a "follow the hand" swipe is released towards a switch.
    var hapticFeedback: Bool

    static let `default` = MouseGestureSettings(
        actions: .default,
        invertHorizontal: false,
        freezePointer: true
    )

    init(
        upAction: String,
        downAction: String,
        leftAction: String,
        rightAction: String,
        clickAction: String,
        invertHorizontal: Bool,
        freezePointer: Bool,
        mode: MouseGestureMode = .discrete,
        trackingSpeed: Double = MouseGestureSettings.defaultTrackingSpeed,
        deviceTracking: Bool = false,
        hapticFeedback: Bool = true
    ) {
        self.init(
            actions: GestureActions(
                up: GestureAction(action: upAction),
                down: GestureAction(action: downAction),
                left: GestureAction(action: leftAction),
                right: GestureAction(action: rightAction),
                click: GestureAction(action: clickAction)
            ),
            invertHorizontal: invertHorizontal,
            freezePointer: freezePointer,
            mode: mode,
            trackingSpeed: trackingSpeed,
            deviceTracking: deviceTracking,
            hapticFeedback: hapticFeedback
        )
    }

    init(
        actions: GestureActions,
        invertHorizontal: Bool,
        freezePointer: Bool,
        mode: MouseGestureMode = .discrete,
        trackingSpeed: Double = MouseGestureSettings.defaultTrackingSpeed,
        deviceTracking: Bool = false,
        hapticFeedback: Bool = true
    ) {
        self.actions = actions
        self.invertHorizontal = invertHorizontal
        self.freezePointer = freezePointer
        self.mode = mode
        self.trackingSpeed = Self.clampedTrackingSpeed(trackingSpeed)
        self.deviceTracking = deviceTracking
        self.hapticFeedback = hapticFeedback
    }

    private enum CodingKeys: String, CodingKey {
        case invertHorizontal, freezePointer, mode, trackingSpeed, deviceTracking, hapticFeedback
    }

    /// Missing keys fall back to the defaults, so older or partial data still loads.
    init(from decoder: Decoder) throws {
        let fallback = Self.default
        // The actions are keys of this same entry (`GestureActions` reads its own).
        actions = try GestureActions(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        invertHorizontal = try c.decodeIfPresent(Bool.self, forKey: .invertHorizontal) ?? fallback.invertHorizontal
        freezePointer = try c.decodeIfPresent(Bool.self, forKey: .freezePointer) ?? fallback.freezePointer
        // A missing, unknown or malformed mode or speed must not throw: a failed decode would
        // reset every gesture setting. Data written by a newer build falls back to discrete.
        let storedMode = (try? c.decodeIfPresent(String.self, forKey: .mode)) ?? nil
        mode = storedMode.flatMap(MouseGestureMode.init(rawValue:)) ?? fallback.mode
        let storedSpeed = (try? c.decodeIfPresent(Double.self, forKey: .trackingSpeed)) ?? nil
        trackingSpeed = Self.clampedTrackingSpeed(storedSpeed ?? fallback.trackingSpeed)
        // Same rule for the two device options: data from an older build has neither key.
        let storedTracking = (try? c.decodeIfPresent(Bool.self, forKey: .deviceTracking)) ?? nil
        deviceTracking = storedTracking ?? fallback.deviceTracking
        let storedHaptics = (try? c.decodeIfPresent(Bool.self, forKey: .hapticFeedback)) ?? nil
        hapticFeedback = storedHaptics ?? fallback.hapticFeedback
    }

    /// The actions first, in the order they were always written, then the rest: an entry
    /// without a label is written as before.
    func encode(to encoder: Encoder) throws {
        try actions.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(invertHorizontal, forKey: .invertHorizontal)
        try c.encode(freezePointer, forKey: .freezePointer)
        try c.encode(mode, forKey: .mode)
        try c.encode(trackingSpeed, forKey: .trackingSpeed)
        try c.encode(deviceTracking, forKey: .deviceTracking)
        try c.encode(hapticFeedback, forKey: .hapticFeedback)
    }

    /// Keeps the speed inside `trackingSpeedRange`; a non-finite value becomes the default.
    static func clampedTrackingSpeed(_ value: Double) -> Double {
        guard value.isFinite else { return defaultTrackingSpeed }
        return min(max(value, trackingSpeedRange.lowerBound), trackingSpeedRange.upperBound)
    }

    /// The action for a recognized physical direction, after inversion.
    func action(for direction: MouseGestureDirection) -> GestureAction {
        switch direction {
        case .up, .down:
            return actions[direction]
        case .left:
            return invertHorizontal ? actions.right : actions.left
        case .right:
            return invertHorizontal ? actions.left : actions.right
        }
    }

    /// The action identifier for a recognized physical direction, after inversion.
    func actionIdentifier(for direction: MouseGestureDirection) -> String {
        return action(for: direction).action
    }
}
