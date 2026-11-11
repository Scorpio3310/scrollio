//
//  ThumbWheelSettings.swift
//  Mos
//
//  What the sideways wheel of a mouse does: the thumb wheel of a Logitech MX Master, or a
//  wheel that tilts. The user's choice, stored in Options (group `.thumbWheel`, UserDefaults
//  key "thumbWheelSettings") and used by the scroll engine for wheel events that move
//  sideways only. It does not touch the mouse: nothing here is written to a device.
//
//  The defaults are what Scrollio did before these settings existed: the wheel scrolls
//  sideways, as fast as the main wheel, in the direction "Reverse wheel direction" gives.
//
//  CONTRACT (shared by the scroll engine, the Scrolling tab and the Buttons tab): do not
//  rename or remove these types, cases, fields or keys without updating every consumer.
//

import Foundation

/// What a turn of the sideways wheel does.
enum ThumbWheelFunction: String, Codable, CaseIterable, Equatable {
    /// Scrolls sideways (the default, and what the wheel does on its own).
    case scroll
    /// Zooms in and out.
    case zoom
    /// Goes to the next or previous tab.
    case tabs
    /// Goes to the desktop (Space) on the right or left.
    case desktops
    /// Goes back or forward in apps that support it.
    case backForward
    /// Turns the volume up or down.
    case volume
}

/// Stored format: `{"function": String, "speed": Double, "swapsDirection": Bool}`. A missing,
/// unreadable or unknown value falls back to its default one by one (the others are kept);
/// unknown keys are ignored.
struct ThumbWheelSettings: Codable, Equatable {
    /// What a turn of the wheel does.
    var function: ThumbWheelFunction
    /// How far one turn goes, as a multiple of what it would be otherwise: sideways distance
    /// while the wheel scrolls, how soon the next step comes for the other functions.
    /// Always inside `speedRange`.
    var speed: Double {
        didSet {
            let clamped = Self.clampedSpeed(speed)
            if clamped != speed { speed = clamped }
        }
    }
    /// Turns the wheel's direction around, on top of what "Reverse wheel direction" (or an
    /// app's own rule) gives. Applies to every function.
    var swapsDirection: Bool

    static let speedRange: ClosedRange<Double> = 0.25...3.0
    static let defaultSpeed = 1.0

    /// Scrolls sideways at the main wheel's speed, direction not swapped.
    static let `default` = ThumbWheelSettings()

    init(
        function: ThumbWheelFunction = .scroll,
        speed: Double = ThumbWheelSettings.defaultSpeed,
        swapsDirection: Bool = false
    ) {
        self.function = function
        self.speed = Self.clampedSpeed(speed)
        self.swapsDirection = swapsDirection
    }

    private enum CodingKeys: String, CodingKey {
        case function, speed, swapsDirection
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let name = (try? c.decodeIfPresent(String.self, forKey: .function)) ?? nil
        let speed = (try? c.decodeIfPresent(Double.self, forKey: .speed)) ?? nil
        let swaps = (try? c.decodeIfPresent(Bool.self, forKey: .swapsDirection)) ?? nil
        self.init(
            function: name.flatMap(ThumbWheelFunction.init(rawValue:)) ?? .scroll,
            speed: speed ?? Self.defaultSpeed,
            swapsDirection: swaps ?? false
        )
    }

    /// Speed inside `speedRange`; a value that is not a number becomes the default.
    static func clampedSpeed(_ speed: Double) -> Double {
        guard speed.isFinite else { return defaultSpeed }
        return min(speedRange.upperBound, max(speedRange.lowerBound, speed))
    }
}
