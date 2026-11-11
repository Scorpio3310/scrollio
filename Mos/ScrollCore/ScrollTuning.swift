//
//  ScrollTuning.swift
//  Mos
//
//  Stored settings of the fast-scroll tuning (free-spin, acceleration, momentum, what the
//  thumb wheel does), kept as plain data only: the scroll engine no longer reads them.
//  The Scrolling preferences still show them until the rebuilt tab lands; then they go.
//  The Codable code stays as it was, so stored settings keep reading and writing the same.
//

import Foundation

/// What the horizontal (thumb) wheel does.
enum ScrollHorizontalWheelAction: String, Codable, CaseIterable {
    /// Scrolls sideways (today's behaviour).
    case scroll
    /// Posts the wheel as a phased horizontal gesture, so apps run their interactive
    /// back/forward swipe (needs the system's "Swipe between pages" setting).
    case pageSwipe
}

/// Magic Mouse-style momentum for a wheel: after a flick the page glides on and slows down
/// along the system's momentum curve, as modelled by WebKit (MomentumEventDispatcher):
/// velocity × `decayPer8ms` every 8 ms, blending to × `tailDecayPer8ms` below `tailSpeed`,
/// ending under `stopDelta` px per 60 Hz frame.
///
/// Single notches and slow scrolling stay exact: the glide is scaled by a fling gain that is
/// 0 below `minFlingRate` lines/s and 1 from `fullFlingRate`.
struct ScrollMomentumSettings: Codable, Equatable {
    /// Velocity factor per 8 ms (0.975 ≈ a time constant of 316 ms).
    var decayPer8ms: Double
    /// Below this speed (px/s) the decay blends toward `tailDecayPer8ms`.
    var tailSpeed: Double
    /// Velocity factor per 8 ms at standstill (0.91 ≈ 85 ms).
    var tailDecayPer8ms: Double
    /// The glide ends below this many px per 60 Hz frame.
    var stopDelta: Double
    /// Glide speed relative to the measured wheel speed.
    var coastGain: Double
    /// Wheel speed (lines/s) up to which there is no glide.
    var minFlingRate: Double
    /// Wheel speed (lines/s) from which the glide has its full speed.
    var fullFlingRate: Double
    /// A tick against the glide stops it (and scrolls nothing).
    var stopOnReverseTick: Bool
    /// No glide while Cmd, Ctrl or Option is held (zooming and other modified scrolling).
    var noCoastWithModifiers: Bool
    /// Glide after a free-spin too. Off: the spinning wheel has its own inertia.
    var coastInFreeSpin: Bool
    /// Send gesture phases during a free-spin. Off: apps would rubber-band for as long as the wheel spins.
    var phasesInFreeSpin: Bool
    /// Send gesture phases for horizontal scrolling. Off: browsers would take them for back/forward swipes.
    var phasesOnHorizontal: Bool

    static let decayRange: ClosedRange<Double> = 0.5...0.999
    static let tailDecayRange: ClosedRange<Double> = 0.1...0.999
    static let tailSpeedRange: ClosedRange<Double> = 0...5000
    static let stopDeltaRange: ClosedRange<Double> = 0.05...10
    static let coastGainRange: ClosedRange<Double> = 0...4
    static let flingRateRange: ClosedRange<Double> = 0...200

    static let `default` = ScrollMomentumSettings()

    init(
        decayPer8ms: Double = 0.975,
        tailSpeed: Double = 250,
        tailDecayPer8ms: Double = 0.91,
        stopDelta: Double = 0.5,
        coastGain: Double = 1.0,
        minFlingRate: Double = 8,
        fullFlingRate: Double = 16,
        stopOnReverseTick: Bool = true,
        noCoastWithModifiers: Bool = true,
        coastInFreeSpin: Bool = false,
        phasesInFreeSpin: Bool = false,
        phasesOnHorizontal: Bool = false
    ) {
        self.decayPer8ms = decayPer8ms
        self.tailSpeed = tailSpeed
        self.tailDecayPer8ms = tailDecayPer8ms
        self.stopDelta = stopDelta
        self.coastGain = coastGain
        self.minFlingRate = minFlingRate
        self.fullFlingRate = fullFlingRate
        self.stopOnReverseTick = stopOnReverseTick
        self.noCoastWithModifiers = noCoastWithModifiers
        self.coastInFreeSpin = coastInFreeSpin
        self.phasesInFreeSpin = phasesInFreeSpin
        self.phasesOnHorizontal = phasesOnHorizontal
    }

    /// Missing keys fall back to the defaults; out-of-range values are clamped.
    init(from decoder: Decoder) throws {
        let fallback = Self.default
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func number(_ key: CodingKeys, _ fallback: Double, _ range: ClosedRange<Double>) throws -> Double {
            ScrollTuningSettings.clamp(try c.decodeIfPresent(Double.self, forKey: key) ?? fallback, to: range)
        }
        func flag(_ key: CodingKeys, _ fallback: Bool) throws -> Bool {
            try c.decodeIfPresent(Bool.self, forKey: key) ?? fallback
        }
        decayPer8ms = try number(.decayPer8ms, fallback.decayPer8ms, Self.decayRange)
        tailSpeed = try number(.tailSpeed, fallback.tailSpeed, Self.tailSpeedRange)
        tailDecayPer8ms = try number(.tailDecayPer8ms, fallback.tailDecayPer8ms, Self.tailDecayRange)
        stopDelta = try number(.stopDelta, fallback.stopDelta, Self.stopDeltaRange)
        coastGain = try number(.coastGain, fallback.coastGain, Self.coastGainRange)
        minFlingRate = try number(.minFlingRate, fallback.minFlingRate, Self.flingRateRange)
        fullFlingRate = max(minFlingRate, try number(.fullFlingRate, fallback.fullFlingRate, Self.flingRateRange))
        stopOnReverseTick = try flag(.stopOnReverseTick, fallback.stopOnReverseTick)
        noCoastWithModifiers = try flag(.noCoastWithModifiers, fallback.noCoastWithModifiers)
        coastInFreeSpin = try flag(.coastInFreeSpin, fallback.coastInFreeSpin)
        phasesInFreeSpin = try flag(.phasesInFreeSpin, fallback.phasesInFreeSpin)
        phasesOnHorizontal = try flag(.phasesOnHorizontal, fallback.phasesOnHorizontal)
    }
}

struct ScrollTuningSettings: Codable, Equatable {
    /// Use `freeSpinSmoothness` / `freeSpinSpeed` while the wheel spins freely.
    var freeSpinEnabled: Bool
    /// Same scale as the Duration slider (0...5): lower feels more direct.
    var freeSpinSmoothness: Double
    /// Multiplier on the regular speed while spinning freely.
    var freeSpinSpeed: Double
    /// 0 = off, 1 = the strongest acceleration.
    var acceleration: Double
    /// Glide after a flick. nil = off: scrolling and posting stay exactly as without it.
    var momentum: ScrollMomentumSettings?
    /// What the thumb wheel does. `.scroll` = today's behaviour.
    var horizontalWheelAction: ScrollHorizontalWheelAction

    static let freeSpinSmoothnessRange: ClosedRange<Double> = 0...5
    static let freeSpinSpeedRange: ClosedRange<Double> = 0.25...3
    static let accelerationRange: ClosedRange<Double> = 0...1

    static let `default` = ScrollTuningSettings(
        freeSpinEnabled: true,
        freeSpinSmoothness: 1.5,
        freeSpinSpeed: 1.0,
        acceleration: 0
    )

    init(
        freeSpinEnabled: Bool, freeSpinSmoothness: Double, freeSpinSpeed: Double, acceleration: Double,
        momentum: ScrollMomentumSettings? = nil,
        horizontalWheelAction: ScrollHorizontalWheelAction = .scroll
    ) {
        self.freeSpinEnabled = freeSpinEnabled
        self.freeSpinSmoothness = freeSpinSmoothness
        self.freeSpinSpeed = freeSpinSpeed
        self.acceleration = acceleration
        self.momentum = momentum
        self.horizontalWheelAction = horizontalWheelAction
    }

    private enum CodingKeys: String, CodingKey {
        case freeSpinEnabled, freeSpinSmoothness, freeSpinSpeed, acceleration, momentum, horizontalWheelAction
    }

    /// The two newer fields are only written when they differ from "off", so settings without
    /// them stay readable by (and identical to those of) builds that do not know them.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(freeSpinEnabled, forKey: .freeSpinEnabled)
        try c.encode(freeSpinSmoothness, forKey: .freeSpinSmoothness)
        try c.encode(freeSpinSpeed, forKey: .freeSpinSpeed)
        try c.encode(acceleration, forKey: .acceleration)
        try c.encodeIfPresent(momentum, forKey: .momentum)
        if horizontalWheelAction != .scroll {
            try c.encode(horizontalWheelAction, forKey: .horizontalWheelAction)
        }
    }

    /// Missing keys fall back to the defaults; out-of-range values are clamped.
    /// Stored settings from before momentum decode to `momentum == nil` and `.scroll`;
    /// an unreadable momentum block or an unknown wheel action also falls back to those.
    init(from decoder: Decoder) throws {
        let fallback = Self.default
        let c = try decoder.container(keyedBy: CodingKeys.self)
        freeSpinEnabled = try c.decodeIfPresent(Bool.self, forKey: .freeSpinEnabled) ?? fallback.freeSpinEnabled
        freeSpinSmoothness = Self.clamp(
            try c.decodeIfPresent(Double.self, forKey: .freeSpinSmoothness) ?? fallback.freeSpinSmoothness,
            to: Self.freeSpinSmoothnessRange
        )
        freeSpinSpeed = Self.clamp(
            try c.decodeIfPresent(Double.self, forKey: .freeSpinSpeed) ?? fallback.freeSpinSpeed,
            to: Self.freeSpinSpeedRange
        )
        acceleration = Self.clamp(
            try c.decodeIfPresent(Double.self, forKey: .acceleration) ?? fallback.acceleration,
            to: Self.accelerationRange
        )
        momentum = try? c.decodeIfPresent(ScrollMomentumSettings.self, forKey: .momentum)
        let action = try? c.decodeIfPresent(String.self, forKey: .horizontalWheelAction)
        horizontalWheelAction = action.flatMap(ScrollHorizontalWheelAction.init(rawValue:)) ?? fallback.horizontalWheelAction
    }

    static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return range.lowerBound }
        return min(range.upperBound, max(range.lowerBound, value))
    }
}
