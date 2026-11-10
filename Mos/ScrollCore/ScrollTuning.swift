//
//  ScrollTuning.swift
//  Mos
//
//  Fast-scroll tuning on top of the smooth-scroll step/speed/duration:
//  - free-spin: separate speed and smoothness while the wheel spins freely
//    (Logitech MagSpeed free-spin or SmartShift auto-shift), detected from how
//    fast wheel notches arrive, so no device-specific protocol is needed;
//  - acceleration: the faster the wheel turns, the farther each notch scrolls.
//

import Foundation

struct ScrollTuningSettings: Codable, Equatable {
    /// Use `freeSpinSmoothness` / `freeSpinSpeed` while the wheel spins freely.
    var freeSpinEnabled: Bool
    /// Same scale as the Duration slider (0...5): lower feels more direct.
    var freeSpinSmoothness: Double
    /// Multiplier on the regular speed while spinning freely.
    var freeSpinSpeed: Double
    /// 0 = off, 1 = up to `maximumAccelerationGain` extra distance at full wheel speed.
    var acceleration: Double

    static let freeSpinSmoothnessRange: ClosedRange<Double> = 0...5
    static let freeSpinSpeedRange: ClosedRange<Double> = 0.25...3
    static let accelerationRange: ClosedRange<Double> = 0...1
    /// At acceleration 1 and full wheel speed each notch scrolls 1 + 3 = 4× as far.
    static let maximumAccelerationGain = 3.0

    static let `default` = ScrollTuningSettings(
        freeSpinEnabled: true,
        freeSpinSmoothness: 1.5,
        freeSpinSpeed: 1.0,
        acceleration: 0
    )

    init(freeSpinEnabled: Bool, freeSpinSmoothness: Double, freeSpinSpeed: Double, acceleration: Double) {
        self.freeSpinEnabled = freeSpinEnabled
        self.freeSpinSmoothness = freeSpinSmoothness
        self.freeSpinSpeed = freeSpinSpeed
        self.acceleration = acceleration
    }

    /// Missing keys fall back to the defaults; out-of-range values are clamped.
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
    }

    /// Adjusts the per-event speed and the interpolation factor for the current wheel state.
    /// - Parameters:
    ///   - speed: regular speed (global or per-app)
    ///   - durationTransition: regular per-frame interpolation factor (already transformed)
    func resolve(speed: Double, durationTransition: Double, spin: ScrollSpinState) -> (speed: Double, durationTransition: Double) {
        var resolvedSpeed = speed * accelerationFactor(notchRate: spin.notchRate)
        var resolvedDuration = durationTransition
        if freeSpinEnabled && spin.isFreeSpin {
            resolvedSpeed *= freeSpinSpeed
            resolvedDuration = OPTIONS_SCROLL_DEFAULT.generateDurationTransition(with: freeSpinSmoothness)
        }
        return (resolvedSpeed, resolvedDuration)
    }

    /// 1 below `ScrollSpinTracker.accelerationStartRate`, rising linearly to
    /// 1 + acceleration × maximumAccelerationGain at `accelerationFullRate`.
    func accelerationFactor(notchRate: Double) -> Double {
        guard acceleration > 0 else { return 1 }
        let span = ScrollSpinTracker.accelerationFullRate - ScrollSpinTracker.accelerationStartRate
        let t = Self.clamp((notchRate - ScrollSpinTracker.accelerationStartRate) / span, to: 0...1)
        return 1 + acceleration * Self.maximumAccelerationGain * t
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return range.lowerBound }
        return min(range.upperBound, max(range.lowerBound, value))
    }
}

struct ScrollSpinState: Equatable {
    /// Smoothed wheel events per second in the current direction (0 when idle).
    let notchRate: Double
    let isFreeSpin: Bool

    static let idle = ScrollSpinState(notchRate: 0, isFreeSpin: false)
}

/// Estimates how fast the wheel turns from the spacing of smoothed wheel events.
///
/// A ratcheted wheel stays well below ~30 notches per second even on a hard flick,
/// while a free-spinning MagSpeed wheel delivers far more. Hysteresis keeps the state
/// from flickering while the wheel slows down.
struct ScrollSpinTracker {
    /// Events per second that switch to free-spin, and the rate that switches back.
    static let freeSpinEnterRate = 40.0
    static let freeSpinExitRate = 28.0
    /// Events needed in one direction before free-spin can engage.
    static let minimumEventsForFreeSpin = 4
    /// A gap this long ends the spin.
    static let idleGap: TimeInterval = 0.15
    /// Acceleration ramps between these rates.
    static let accelerationStartRate = 10.0
    static let accelerationFullRate = 60.0
    /// Weight of the newest interval in the moving average.
    private static let smoothing = 0.4

    private var lastTime: TimeInterval?
    private var lastSign = 0
    private var averageInterval: TimeInterval?
    private var eventCount = 0
    private(set) var state = ScrollSpinState.idle

    mutating func register(sign: Int, at time: TimeInterval) -> ScrollSpinState {
        defer {
            lastTime = time
            lastSign = sign
        }
        guard sign != 0 else { return state }
        guard let lastTime,
              sign == lastSign,
              time - lastTime > 0,
              time - lastTime < Self.idleGap else {
            // First event, direction change or pause: start a new spin.
            averageInterval = nil
            eventCount = 1
            state = .idle
            return state
        }

        let interval = time - lastTime
        let average = averageInterval.map { $0 + Self.smoothing * (interval - $0) } ?? interval
        averageInterval = average
        eventCount += 1

        let rate = 1 / average
        let isFreeSpin: Bool
        if state.isFreeSpin {
            isFreeSpin = rate >= Self.freeSpinExitRate
        } else {
            isFreeSpin = eventCount >= Self.minimumEventsForFreeSpin && rate >= Self.freeSpinEnterRate
        }
        state = ScrollSpinState(notchRate: rate, isFreeSpin: isFreeSpin)
        return state
    }

    mutating func reset() {
        self = ScrollSpinTracker()
    }
}
