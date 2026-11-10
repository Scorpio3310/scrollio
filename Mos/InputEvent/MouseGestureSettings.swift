//
//  MouseGestureSettings.swift
//  Mos
//
//  User settings for the Gesture Navigation action: one action per direction plus click,
//  horizontal inversion and pointer freeze. Shared by every Gesture Navigation binding.
//

import Foundation

struct MouseGestureSettings: Codable, Equatable {
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
        freezePointer: Bool
    ) {
        self.upAction = upAction
        self.downAction = downAction
        self.leftAction = leftAction
        self.rightAction = rightAction
        self.clickAction = clickAction
        self.invertHorizontal = invertHorizontal
        self.freezePointer = freezePointer
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
