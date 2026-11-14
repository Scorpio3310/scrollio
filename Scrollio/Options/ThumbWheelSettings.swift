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

/// "Reverse direction" of each function: one switch per function, so that, say, Volume can
/// be turned around without turning around Switch Desktops. A bit per function: one copy
/// in the scroll tap allocates nothing.
struct ThumbWheelReversal: Equatable {
    private var bits: UInt8

    /// No function reversed.
    static let none = ThumbWheelReversal(all: false)
    /// Every function reversed.
    static let all = ThumbWheelReversal(all: true)

    /// Every function `reversed`: what one "Swap direction" for all of them was (an entry or
    /// a settings file from before reads that way).
    init(all reversed: Bool) {
        bits = reversed ? Self.allBits : 0
    }

    /// Whether `function` is reversed.
    subscript(function: ThumbWheelFunction) -> Bool {
        get { return bits & Self.bit(function) != 0 }
        set { bits = newValue ? bits | Self.bit(function) : bits & ~Self.bit(function) }
    }

    /// Every function has the same value: the old single switch says it all.
    var isUniform: Bool {
        return bits == 0 || bits == Self.allBits
    }

    private static func bit(_ function: ThumbWheelFunction) -> UInt8 {
        switch function {
        case .scroll: return 1 << 0
        case .zoom: return 1 << 1
        case .tabs: return 1 << 2
        case .desktops: return 1 << 3
        case .backForward: return 1 << 4
        case .volume: return 1 << 5
        }
    }

    private static let allBits: UInt8 = ThumbWheelFunction.allCases.reduce(0) { $0 | bit($1) }

    /// From the stored values: a function's own entry in `byName` (`[rawValue: Bool]`), else
    /// `seed` (the old "Swap direction"), else not reversed.
    init(byName: [String: Bool]?, seed: Bool?) {
        bits = 0
        for function in ThumbWheelFunction.allCases {
            self[function] = byName?[function.rawValue] ?? seed ?? false
        }
    }

    /// Writes every function's value under its name.
    func encode(into container: inout KeyedEncodingContainer<FunctionNameKey>) throws {
        for function in ThumbWheelFunction.allCases {
            try container.encode(self[function], forKey: FunctionNameKey(function))
        }
    }

    /// A function's name as a key of the stored object.
    struct FunctionNameKey: CodingKey {
        let stringValue: String
        var intValue: Int? { return nil }
        init(_ function: ThumbWheelFunction) { stringValue = function.rawValue }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}

/// Stored format: `{"function": String, "speed": Double, "swapsDirection": Bool}`, and only
/// when they say more than that: `"reverseDirection": {"<function>": Bool, …}` (every
/// function, while they differ) and `"followsWheel": true`. A missing, unreadable or
/// unknown value falls back to its default one by one (the others are kept); unknown keys
/// are ignored.
///
/// "swapsDirection" was one switch for every function (1.0.5). It stays, under its name: it
/// is written as the chosen function's "Reverse direction" (so 1.0.5, which ignores the new
/// keys, turns the chosen function the way this version does), and read as the value of
/// every function without an entry of its own in "reverseDirection" (so an entry or a
/// settings file from before gives every function the switch it had). Settings that never
/// set a function apart are written exactly as before.
struct ThumbWheelSettings: Codable, Equatable {
    /// What a turn of the wheel does.
    var function: ThumbWheelFunction
    /// How far one turn goes, as a multiple of what it would be otherwise: sideways distance
    /// while the wheel scrolls, how soon the next step comes for the other functions, how
    /// far the desktop slides while it follows the wheel. Always inside `speedRange`.
    var speed: Double {
        didSet {
            let clamped = Self.clampedSpeed(speed)
            if clamped != speed { speed = clamped }
        }
    }
    /// "Reverse direction" of each function. While the wheel scrolls it turns the wheel
    /// around on top of what "Reverse wheel direction" (or an app's own rule) gives.
    var reverses: ThumbWheelReversal
    /// Switch Desktops' "Follow the wheel": the desktops slide with the wheel like a
    /// trackpad swipe and settle when it rests, instead of one step per stroke. Off by
    /// default; only Switch Desktops reads it.
    var followsWheel: Bool

    /// The chosen function's "Reverse direction" (the one a turn of the wheel uses).
    var swapsDirection: Bool {
        get { return reverses[function] }
        set { reverses[function] = newValue }
    }

    /// Switch Desktops with "Follow the wheel" on: a turn drives a swipe of the desktops.
    var followsWheelNow: Bool {
        return function == .desktops && followsWheel
    }

    static let speedRange: ClosedRange<Double> = 0.25...3.0
    static let defaultSpeed = 1.0

    /// Scrolls sideways at the main wheel's speed, no function reversed, desktops in steps.
    static let `default` = ThumbWheelSettings()

    /// - Parameter swapsDirection: every function's "Reverse direction" (as one switch).
    init(
        function: ThumbWheelFunction = .scroll,
        speed: Double = ThumbWheelSettings.defaultSpeed,
        swapsDirection: Bool = false,
        followsWheel: Bool = false
    ) {
        self.init(function: function, speed: speed, reverses: ThumbWheelReversal(all: swapsDirection), followsWheel: followsWheel)
    }

    init(function: ThumbWheelFunction, speed: Double, reverses: ThumbWheelReversal, followsWheel: Bool) {
        self.function = function
        self.speed = Self.clampedSpeed(speed)
        self.reverses = reverses
        self.followsWheel = followsWheel
    }

    private enum CodingKeys: String, CodingKey {
        case function, speed, swapsDirection, reverseDirection, followsWheel
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let name = (try? c.decodeIfPresent(String.self, forKey: .function)) ?? nil
        let speed = (try? c.decodeIfPresent(Double.self, forKey: .speed)) ?? nil
        let swaps = (try? c.decodeIfPresent(Bool.self, forKey: .swapsDirection)) ?? nil
        let byName = (try? c.decodeIfPresent([String: Bool].self, forKey: .reverseDirection)) ?? nil
        let follows = (try? c.decodeIfPresent(Bool.self, forKey: .followsWheel)) ?? nil
        self.init(
            function: name.flatMap(ThumbWheelFunction.init(rawValue:)) ?? .scroll,
            speed: speed ?? Self.defaultSpeed,
            reverses: ThumbWheelReversal(byName: byName, seed: swaps),
            followsWheel: follows ?? false
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(function, forKey: .function)
        try c.encode(speed, forKey: .speed)
        try c.encode(swapsDirection, forKey: .swapsDirection)
        if !reverses.isUniform {
            var byName = c.nestedContainer(keyedBy: ThumbWheelReversal.FunctionNameKey.self, forKey: .reverseDirection)
            try reverses.encode(into: &byName)
        }
        if followsWheel {
            try c.encode(true, forKey: .followsWheel)
        }
    }

    /// Speed inside `speedRange`; a value that is not a number becomes the default.
    static func clampedSpeed(_ speed: Double) -> Double {
        guard speed.isFinite else { return defaultSpeed }
        return min(speedRange.upperBound, max(speedRange.lowerBound, speed))
    }
}
