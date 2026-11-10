//
//  ScrollTuning.swift
//  Mos
//
//  Fast-scroll tuning on top of the smooth-scroll step/speed/duration:
//  - free-spin: separate speed and smoothness while the wheel spins freely
//    (Logitech MagSpeed free-spin or SmartShift auto-shift), detected from how
//    many wheel lines arrive per second, so no device-specific protocol is needed;
//  - acceleration: the faster the wheel turns, the farther each line scrolls.
//
//  Vertical wheel only: the thumb wheel is horizontal and has no free-spin.
//  Settings are global (Options.shared.scrollTuning), not per app.
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
    /// At acceleration 1 and full wheel speed each line scrolls 1 + 2 = 3× as far.
    static let maximumAccelerationGain = 2.0
    /// Upper bound for acceleration × free-spin speed × dash amplification.
    static let maximumCombinedMultiplier = 8.0

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

    /// Adjusts speed and smoothing for the current wheel state.
    /// - Parameters:
    ///   - speed: regular speed (global or per-app)
    ///   - durationTransition: regular per-frame interpolation factor at 60 Hz (already transformed)
    ///   - spin: vertical wheel state (`.idle` for the horizontal axis)
    ///   - simulateTrackpad: Duration is locked while trackpad simulation is on, so free-spin
    ///     smoothness is not applied then
    ///   - amplification: dash multiplier (1 when dash is not held)
    func resolve(
        speed: Double,
        durationTransition: Double,
        spin: ScrollSpinState,
        simulateTrackpad: Bool = false,
        amplification: Double = 1
    ) -> ScrollTuningResolution {
        let blend = freeSpinEnabled ? Self.clamp(spin.freeSpinBlend, to: 0...1) : 0
        let freeSpinFactor = 1 + (Self.clamp(freeSpinSpeed, to: Self.freeSpinSpeedRange) - 1) * blend
        let combined = accelerationFactor(lineRate: spin.accelerationRate)
            * freeSpinFactor
            * (amplification.isFinite && amplification > 0 ? amplification : 1)
        let multiplier = min(Self.maximumCombinedMultiplier, combined)

        var resolvedDuration = durationTransition
        if blend > 0 && !simulateTrackpad {
            let freeSpinDuration = OPTIONS_SCROLL_DEFAULT.generateDurationTransition(
                with: Self.clamp(freeSpinSmoothness, to: Self.freeSpinSmoothnessRange)
            )
            resolvedDuration = durationTransition + (freeSpinDuration - durationTransition) * blend
        }
        return ScrollTuningResolution(
            multiplier: multiplier,
            speed: speed * multiplier,
            durationTransition: resolvedDuration,
            freeSpinBlend: blend
        )
    }

    /// 1 below `ScrollSpinTracker.accelerationStartRate`, rising along a smoothstep to
    /// 1 + acceleration × maximumAccelerationGain at `accelerationFullRate` (lines/s).
    func accelerationFactor(lineRate: Double) -> Double {
        let amount = Self.clamp(acceleration, to: Self.accelerationRange)
        guard amount > 0, lineRate.isFinite else { return 1 }
        let span = ScrollSpinTracker.accelerationFullRate - ScrollSpinTracker.accelerationStartRate
        let t = Self.smoothstep((lineRate - ScrollSpinTracker.accelerationStartRate) / span)
        return 1 + amount * Self.maximumAccelerationGain * t
    }

    static func smoothstep(_ x: Double) -> Double {
        let t = clamp(x, to: 0...1)
        return t * t * (3 - 2 * t)
    }

    static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return range.lowerBound }
        return min(range.upperBound, max(range.lowerBound, value))
    }
}

/// What the tuning does to one wheel event.
struct ScrollTuningResolution: Equatable {
    /// acceleration × free-spin speed × dash amplification, capped at `maximumCombinedMultiplier`
    let multiplier: Double
    /// speed × multiplier
    let speed: Double
    /// per-frame interpolation factor at 60 Hz
    let durationTransition: Double
    /// 0…1: how much free-spin behaviour applies (0 when free-spin is off)
    let freeSpinBlend: Double

    /// Vertical distance for one event before speed is applied.
    ///
    /// Regular scrolling keeps Mos' rule max(step, |pointDelta|). In free-spin the distance
    /// comes from the line count instead (|DeltaAxis1| × step): pointDelta already carries
    /// macOS scroll acceleration, and multiplying that again by speed made fast spins explode.
    /// The two are blended with the free-spin blend so the switch is gradual.
    /// - Parameters:
    ///   - regular: max(step, |usable delta|) with the event's (possibly reversed) sign
    ///   - lines: line count of the event (DeltaAxis1, sign ignored)
    ///   - step: step setting (px per line)
    func verticalDistance(regular: Double, lines: Double, step: Double) -> Double {
        guard freeSpinBlend > 0, regular != 0, lines.isFinite, lines != 0 else { return regular }
        let lineDistance = abs(lines) * step * (regular < 0 ? -1 : 1)
        return regular + (lineDistance - regular) * freeSpinBlend
    }
}

struct ScrollSpinState: Equatable {
    /// Wheel speed in lines per second over the last few events of the current run (0 when idle).
    let lineRate: Double
    /// 0…1 blend toward free-spin: ramps between `freeSpinBlendStartRate` and
    /// `freeSpinEnterRate`, and stays at 1 while free-spin is latched.
    let freeSpinBlend: Double
    /// Free-spin latched: stays until a pause or a direction change.
    let isFreeSpin: Bool
    /// Line rate the acceleration curve uses; frozen at the latch rate while in free-spin
    /// (the spinning wheel already delivers more lines, it needs no extra speed-up).
    let accelerationRate: Double

    init(lineRate: Double, freeSpinBlend: Double, isFreeSpin: Bool, accelerationRate: Double) {
        self.lineRate = lineRate
        self.freeSpinBlend = freeSpinBlend
        self.isFreeSpin = isFreeSpin
        self.accelerationRate = accelerationRate
    }

    /// Lines per second (kept for callers of the draft API).
    var notchRate: Double { return lineRate }

    static let idle = ScrollSpinState(lineRate: 0, freeSpinBlend: 0, isFreeSpin: false, accelerationRate: 0)
}

/// Estimates how fast the vertical wheel turns from the lines per event and the spacing of
/// the events' own timestamps.
///
/// Over Bluetooth the mouse sends at most ~60–125 reports per second, so a fast free-spin
/// packs several lines into one event: the speed is measured in lines per second, not events.
/// A ratcheted wheel stays well below ~30 lines/s even on a hard flick, a free-spinning
/// MagSpeed wheel delivers far more. Free-spin latches until a pause or a direction change, so
/// a wheel that slows down keeps the free-spin smoothness for the rest of its glide.
struct ScrollSpinTracker {
    /// The free-spin blend ramps between these line rates (lines/s).
    static let freeSpinBlendStartRate = 20.0
    static let freeSpinEnterRate = 40.0
    /// Lines needed in one run before free-spin can latch (Mac Mouse Fix: more than 11 ticks).
    static let minimumLinesForLatch = 12.0
    /// Events needed in one run before the rate is trusted (two intervals).
    static let minimumEventsForBlend = 3
    /// A gap this long ends the run (and the latch).
    static let idleGap: TimeInterval = 0.15
    /// Intervals shorter than this are treated as this long (coalesced or out-of-order events).
    static let minimumInterval: TimeInterval = 0.0025
    /// Acceleration ramps between these line rates (lines/s).
    static let accelerationStartRate = 6.0
    static let accelerationFullRate = 60.0
    /// Number of recent intervals averaged for the line rate.
    static let rateWindow = 3

    private var lastTime: TimeInterval?
    private var lastSign: Double = 0
    private var lineWindow: [Double] = []
    private var intervalWindow: [Double] = []
    private var eventCount = 0
    private var runLines = 0.0
    private var latched = false
    private var latchedAccelerationRate = 0.0
    private(set) var state = ScrollSpinState.idle

    /// Registers one vertical wheel event.
    /// - Parameters:
    ///   - lines: signed line count of the event (DeltaAxis1); 0 leaves the state untouched
    ///   - time: event timestamp in seconds (see `ScrollEventClock`)
    @discardableResult
    mutating func register(lines: Double, at time: TimeInterval) -> ScrollSpinState {
        guard lines != 0, lines.isFinite, time.isFinite else { return state }
        let sign: Double = lines > 0 ? 1 : -1
        let magnitude = abs(lines)

        if let lastTime = lastTime, sign == lastSign, time - lastTime <= Self.idleGap {
            let interval = max(time - lastTime, Self.minimumInterval)
            lineWindow.append(magnitude)
            intervalWindow.append(interval)
            if lineWindow.count > Self.rateWindow {
                lineWindow.removeFirst()
                intervalWindow.removeFirst()
            }
            eventCount += 1
            runLines += magnitude
            self.lastTime = max(time, lastTime)
        } else {
            // First event, direction change or pause: start a new run.
            lineWindow.removeAll(keepingCapacity: true)
            intervalWindow.removeAll(keepingCapacity: true)
            eventCount = 1
            runLines = magnitude
            latched = false
            latchedAccelerationRate = 0
            self.lastTime = time
        }
        lastSign = sign

        let totalInterval = intervalWindow.reduce(0, +)
        let rate = totalInterval > 0 ? lineWindow.reduce(0, +) / totalInterval : 0

        var blend = 0.0
        if latched {
            blend = 1
        } else if eventCount >= Self.minimumEventsForBlend {
            let span = Self.freeSpinEnterRate - Self.freeSpinBlendStartRate
            blend = ScrollTuningSettings.smoothstep((rate - Self.freeSpinBlendStartRate) / span)
            if rate >= Self.freeSpinEnterRate && runLines >= Self.minimumLinesForLatch {
                latched = true
                latchedAccelerationRate = rate
                blend = 1
            }
        }
        state = ScrollSpinState(
            lineRate: rate,
            freeSpinBlend: blend,
            isFreeSpin: latched,
            accelerationRate: latched ? latchedAccelerationRate : rate
        )
        return state
    }

    mutating func reset() {
        self = ScrollSpinTracker()
    }
}
