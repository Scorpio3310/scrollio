//
//  MouseGestureRecognizer.swift
//  Mos
//
//  Minimal four-direction recognizer used by the mouse gesture navigation preset.
//

import Cocoa

/// Physical pointer direction. `MouseGestureSettings` maps it to an action.
enum MouseGestureDirection: Equatable {
    case up
    case down
    case left
    case right
}

/// Recognizes at most one direction per button hold.
///
/// Movement accumulates from the button-down position. Once the displacement on one
/// axis passes `activationDistance` and clearly dominates the other axis, that direction
/// commits and every later movement in the same hold is ignored. A new hold starts a
/// new recognizer, so one physical swipe can never cross more than one Space.
struct MouseGestureRecognizer {
    static let defaultActivationDistance: CGFloat = 40
    static let defaultClickTolerance: CGFloat = 10
    static let defaultDominanceRatio: CGFloat = 1.2

    private let activationDistance: CGFloat
    private let clickTolerance: CGFloat
    private let dominanceRatio: CGFloat

    private(set) var displacement = CGPoint.zero
    private(set) var maximumDistanceFromOrigin: CGFloat = 0
    private(set) var recognizedDirection: MouseGestureDirection?

    init(
        activationDistance: CGFloat = defaultActivationDistance,
        clickTolerance: CGFloat = defaultClickTolerance,
        dominanceRatio: CGFloat = defaultDominanceRatio
    ) {
        self.activationDistance = activationDistance
        self.clickTolerance = clickTolerance
        self.dominanceRatio = dominanceRatio
    }

    /// Adds one mouse movement delta and returns the direction when it first commits.
    mutating func append(deltaX: CGFloat, deltaY: CGFloat) -> MouseGestureDirection? {
        displacement.x += deltaX
        displacement.y += deltaY
        maximumDistanceFromOrigin = max(
            maximumDistanceFromOrigin,
            hypot(displacement.x, displacement.y)
        )

        guard recognizedDirection == nil else { return nil }

        let horizontal = abs(displacement.x)
        let vertical = abs(displacement.y)
        guard max(horizontal, vertical) >= activationDistance else { return nil }

        let direction: MouseGestureDirection
        if horizontal >= vertical * dominanceRatio {
            direction = displacement.x < 0 ? .left : .right
        } else if vertical >= horizontal * dominanceRatio {
            // CGEvent mouse delta Y is positive when moving down.
            direction = displacement.y < 0 ? .up : .down
        } else {
            // Diagonal movement: wait until one axis clearly dominates.
            return nil
        }

        recognizedDirection = direction
        return direction
    }

    /// True when the hold ended without a gesture and the pointer barely moved.
    var shouldReplayClick: Bool {
        guard recognizedDirection == nil else { return false }
        return maximumDistanceFromOrigin <= clickTolerance
    }
}
