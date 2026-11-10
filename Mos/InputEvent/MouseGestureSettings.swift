//
//  MouseGestureSettings.swift
//  Mos
//
//  User settings for the Gesture Navigation action: one action per direction plus click,
//  horizontal inversion, pointer freeze and the gesture mode. Shared by every Gesture
//  Navigation binding.
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

    /// Action identifiers use the same names as button bindings (`SystemShortcut` identifiers,
    /// Logi actions, mouse button actions). An empty string means "no action".
    var upAction: String
    var downAction: String
    var leftAction: String
    var rightAction: String
    var clickAction: String
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

    static let `default` = MouseGestureSettings(
        upAction: SystemShortcut.missionControl.identifier,
        downAction: SystemShortcut.appExpose.identifier,
        leftAction: SystemShortcut.moveSpaceLeft.identifier,
        rightAction: SystemShortcut.moveSpaceRight.identifier,
        clickAction: SystemShortcut.missionControl.identifier,
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
        trackingSpeed: Double = MouseGestureSettings.defaultTrackingSpeed
    ) {
        self.upAction = upAction
        self.downAction = downAction
        self.leftAction = leftAction
        self.rightAction = rightAction
        self.clickAction = clickAction
        self.invertHorizontal = invertHorizontal
        self.freezePointer = freezePointer
        self.mode = mode
        self.trackingSpeed = Self.clampedTrackingSpeed(trackingSpeed)
    }

    /// Missing keys fall back to the defaults, so older or partial data still loads.
    init(from decoder: Decoder) throws {
        let fallback = Self.default
        let c = try decoder.container(keyedBy: CodingKeys.self)
        upAction = try c.decodeIfPresent(String.self, forKey: .upAction) ?? fallback.upAction
        downAction = try c.decodeIfPresent(String.self, forKey: .downAction) ?? fallback.downAction
        leftAction = try c.decodeIfPresent(String.self, forKey: .leftAction) ?? fallback.leftAction
        rightAction = try c.decodeIfPresent(String.self, forKey: .rightAction) ?? fallback.rightAction
        clickAction = try c.decodeIfPresent(String.self, forKey: .clickAction) ?? fallback.clickAction
        invertHorizontal = try c.decodeIfPresent(Bool.self, forKey: .invertHorizontal) ?? fallback.invertHorizontal
        freezePointer = try c.decodeIfPresent(Bool.self, forKey: .freezePointer) ?? fallback.freezePointer
        // A missing, unknown or malformed mode or speed must not throw: a failed decode would
        // reset every gesture setting. Data written by a newer build falls back to discrete.
        let storedMode = (try? c.decodeIfPresent(String.self, forKey: .mode)) ?? nil
        mode = storedMode.flatMap(MouseGestureMode.init(rawValue:)) ?? fallback.mode
        let storedSpeed = (try? c.decodeIfPresent(Double.self, forKey: .trackingSpeed)) ?? nil
        trackingSpeed = Self.clampedTrackingSpeed(storedSpeed ?? fallback.trackingSpeed)
    }

    /// Keeps the speed inside `trackingSpeedRange`; a non-finite value becomes the default.
    static func clampedTrackingSpeed(_ value: Double) -> Double {
        guard value.isFinite else { return defaultTrackingSpeed }
        return min(max(value, trackingSpeedRange.lowerBound), trackingSpeedRange.upperBound)
    }

    /// The action identifier for a recognized physical direction, after inversion.
    func actionIdentifier(for direction: MouseGestureDirection) -> String {
        switch direction {
        case .up:
            return upAction
        case .down:
            return downAction
        case .left:
            return invertHorizontal ? rightAction : leftAction
        case .right:
            return invertHorizontal ? leftAction : rightAction
        }
    }
}
