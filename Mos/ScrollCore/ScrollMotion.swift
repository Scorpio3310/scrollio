//
//  ScrollMotion.swift
//  Mos
//
//  Pure maths behind ScrollPoster's per-frame motion:
//  - frame-rate independent smoothing (the Duration factor is defined per 60 Hz frame);
//  - how strong ScrollFilter is and when it is skipped;
//  - how far the smoothed position may trail the wheel (lead cap);
//  - the glide after a flick (momentum), the landing at the end of a precise gesture and
//    the sub-pixel carry for posting whole pixels;
//  - converting CGEvent timestamps to seconds.
//

import Foundation

enum ScrollMotion {

    /// Duration and filter factors are defined per frame at this rate, so existing settings
    /// keep their feel on 60 Hz displays and take the same time on faster ones.
    static let referenceFrameRate = 60.0
    static let referenceFrameInterval = 1.0 / referenceFrameRate
    /// Frame intervals outside this range are clamped. A long frame (display-link stall, wake)
    /// then slows the motion down instead of jumping most of the remaining distance at once.
    static let minimumFrameInterval = 1.0 / 1000.0
    static let maximumFrameInterval = 3.0 / referenceFrameRate

    /// ScrollFilter's per-frame weight at the reference rate for long durations
    /// (a time constant of ~64 ms).
    static let filterWeight = 0.23
    /// Free-spin blend from which the filter is skipped.
    static let filterBypassFreeSpinBlend = 0.5

    static func clampedFrameInterval(_ interval: Double) -> Double {
        guard interval.isFinite else { return referenceFrameInterval }
        return min(maximumFrameInterval, max(minimumFrameInterval, interval))
    }

    /// The factor for a frame of `interval` seconds that has the same time constant as the
    /// per-frame `transition` at 60 Hz: 1 - (1 - transition)^(interval × 60).
    static func transition(_ transition: Double, frameInterval interval: Double) -> Double {
        guard transition.isFinite, transition > 0 else { return 0 }
        guard transition < 1 else { return 1 }
        let frames = clampedFrameInterval(interval) * referenceFrameRate
        return 1 - pow(1 - transition, frames)
    }

    /// Time constant (seconds) of the exponential approach produced by a per-frame
    /// `transition` at 60 Hz. Duration 3.13 → ~66 ms, 4.35 → ~187 ms.
    static func timeConstant(forTransition transition: Double) -> Double {
        guard transition.isFinite, transition < 1 else { return 0 }
        let t = max(transition, 1e-4)
        return -referenceFrameInterval / log(1 - t)
    }

    /// Time constant of the classic filter (`filterWeight` per 60 Hz frame): ~64 ms.
    static let classicFilterTimeConstant = -referenceFrameInterval / log(1 - filterWeight)
    /// Two equal lags of time constant τ in a row (a critically damped response) have covered
    /// 95% of the distance after this many τ.
    static let landingTimeConstants = 4.744
    /// How fast the filter opens up for free-spin and closes again, per 60 Hz frame
    /// (a time constant of ~75 ms): the switch is a short blend, never a step in speed.
    static let filterOpeningRate = 0.2

    /// Time constant of each of the two lags behind smooth scrolling (the lerp toward the target
    /// and ScrollFilter) for the Duration factor `transition`.
    ///
    /// Duration keeps its meaning, how long a scroll takes to land. Classic Mos gets there with
    /// a lerp of time constant τ followed by a fixed 64 ms filter, about 3 τ + min(τ, 64 ms) for
    /// 95% of the distance: the speed jumps up within the filter's 64 ms and then fades for
    /// several τ. A long Duration is soft but floats on and on; a short one is a hop.
    /// The same landing time is used here, split evenly over two equal lags. That is a
    /// critically damped response: the speed rises as gently as it falls, so a scroll can be
    /// soft without a long tail. (At Duration 4.35: 132 ms each instead of 187 ms + 64 ms.)
    static func responseTimeConstant(forTransition transition: Double) -> Double {
        guard transition.isFinite, transition < 1 else { return 0 }
        let classic = timeConstant(forTransition: transition)
        return (3 * classic + min(classic, classicFilterTimeConstant)) / landingTimeConstants
    }

    /// Per-frame factor of a lag with `timeConstant` for a frame of `interval` seconds
    /// (1 = no lag at all).
    static func factor(timeConstant: Double, frameInterval interval: Double) -> Double {
        guard timeConstant.isFinite, timeConstant > 0 else { return 1 }
        return 1 - exp(-clampedFrameInterval(interval) / timeConstant)
    }

    /// In free-spin the events arrive about once per frame; smoothing their start would only
    /// add lag, so the filter opens up (see `filterOpeningRate`).
    static func shouldBypassFilter(freeSpinBlend: Double) -> Bool {
        return freeSpinBlend >= filterBypassFreeSpinBlend
    }
}

/// The end of a precise gesture (whole-pixel posting, see ScrollPoster).
///
/// An exponential approach ends in a creep: below one pixel per frame the whole pixels come
/// at irregular, growing intervals. Once the wheel has been let go and the motion has slowed
/// to `speed`, the rest is sent at that steady speed and the motion ends exactly on target.
/// The speed never jumps: the landing takes over where the motion falls below it.
enum ScrollLanding {

    /// px/s: one pixel per 60 Hz frame.
    static let speed = 60.0

    /// - Parameters:
    ///   - output: the distance the smoothing produced for this frame (signed px)
    ///   - remaining: distance still to come after this frame (lead plus what the filter holds)
    ///   - direction: sign of the axis' last wheel input (0 = the last input was on the other axis)
    ///   - interval: frame interval (s)
    /// - Returns: nil while the motion is faster than the landing speed, or when it is already
    ///   at rest; otherwise the distance to send this frame and what remains after it.
    ///   With nothing left in the direction of travel, a leftover `output` (the filter still
    ///   easing out) becomes 0: sending it would overshoot the target. The landing never
    ///   moves against the direction of travel.
    static func step(output: Double, remaining: Double, direction: Double, interval: Double) -> (output: Double, remaining: Double)? {
        let total = output + remaining
        let step = speed * ScrollMotion.clampedFrameInterval(interval)
        guard total.isFinite, abs(output) < step else { return nil }
        guard abs(total) >= negligible, total * direction > 0 else {
            return output == 0 && abs(total) < negligible ? nil : (0, 0)
        }
        let magnitude = min(abs(total), step)
        let landed = total > 0 ? magnitude : -magnitude
        return (landed, total - landed)
    }

    /// Distances below this are rounding noise (px).
    static let negligible = 1e-9
}

/// Bounds the lead (buffer − current: distance received from the wheel but not yet scrolled),
/// so the page stops soon after the wheel does.
///
/// The cap follows the measured input speed: lead ≤ max(2 notches, this event, speed × horizon)
/// with horizon = max(120 ms, 1.5 τ). An exponential follower carries a steady lead of
/// speed × τ (a little more right after each sparse notch), so steady scrolling is never
/// cut and scroll distance stays proportional to wheel travel at any speed. When the wheel
/// slows down, the cap shrinks with it and the leftover glide from the faster part is
/// dropped. A fixed cap in notches would instead limit the top speed to cap/τ and lose
/// distance in free-spin, where one event carries several lines.
///
struct ScrollLeadLimiter {

    static let floorNotches = 2.0
    static let minimumHorizon: TimeInterval = 0.12
    static let horizonPerTimeConstant = 1.5
    /// Input gap that ends the input-speed run: max(minimumTailGap, tailTimeConstants × τ).
    /// Earlier notches have then decayed below 5%, so the two-notch floor alone covers the
    /// next one.
    static let minimumTailGap: TimeInterval = 0.16
    static let tailTimeConstants = 3.0
    /// Intervals shorter than this are treated as this long (coalesced or out-of-order events).
    static let minimumInterval: TimeInterval = 0.0025
    /// Number of recent intervals averaged for the input speed.
    static let speedWindow = 3

    private var lastTime: TimeInterval?
    private var lastSign: Double = 0
    private var distances: [Double] = []
    private var intervals: [Double] = []
    /// Input speed in px/s over the last few events of the current run (0 on the first event).
    private(set) var inputSpeed = 0.0

    /// Records one input event (signed distance in px) and returns the input speed.
    /// - Parameter timeConstant: smoothing time constant τ (s); sets the gap that ends a run
    @discardableResult
    mutating func register(distance: Double, at time: TimeInterval, timeConstant: Double) -> Double {
        guard distance != 0, distance.isFinite else { return inputSpeed }
        let sign: Double = distance > 0 ? 1 : -1
        if let lastTime = lastTime, sign == lastSign, time - lastTime <= Self.tailGap(timeConstant: timeConstant) {
            append(distance: abs(distance), interval: max(time - lastTime, Self.minimumInterval))
            self.lastTime = max(time, lastTime)
        } else {
            distances.removeAll(keepingCapacity: true)
            intervals.removeAll(keepingCapacity: true)
            self.lastTime = time
        }
        lastSign = sign
        let totalInterval = intervals.reduce(0, +)
        inputSpeed = totalInterval > 0 ? distances.reduce(0, +) / totalInterval : 0
        return inputSpeed
    }

    mutating func reset() {
        self = ScrollLeadLimiter()
    }

    private mutating func append(distance: Double, interval: Double) {
        distances.append(distance)
        intervals.append(interval)
        if distances.count > Self.speedWindow {
            distances.removeFirst()
            intervals.removeFirst()
        }
    }

    /// Largest allowed |lead| in px.
    /// - Parameters:
    ///   - notch: distance of one wheel notch at the current speed/multipliers (px)
    ///   - distance: distance this event adds (px); a single event is never cut
    ///   - inputSpeed: measured input speed (px/s)
    ///   - timeConstant: smoothing time constant τ (s)
    static func cap(notch: Double, distance: Double, inputSpeed: Double, timeConstant: Double) -> Double {
        let horizon = max(minimumHorizon, horizonPerTimeConstant * max(timeConstant, 0))
        let speedCap = inputSpeed.isFinite ? max(inputSpeed, 0) * horizon : 0
        return max(floorNotches * abs(notch), abs(distance), speedCap)
    }

    /// `buffer` moved so that |buffer − current| ≤ cap, keeping the direction.
    static func limit(buffer: Double, current: Double, cap: Double) -> Double {
        let lead = buffer - current
        guard cap >= 0, abs(lead) > cap else { return buffer }
        return current + (lead > 0 ? cap : -cap)
    }

    /// Input gap that ends a run. By then an exponential follower has covered ≥ 95% of the lead.
    static func tailGap(timeConstant: Double) -> TimeInterval {
        return max(minimumTailGap, tailTimeConstants * max(timeConstant, 0))
    }
}

/// The glide after a flick: a velocity that decays along the system's momentum curve as
/// modelled by WebKit (MomentumEventDispatcher): × `decayPer8ms` every 8 ms, blending to
/// × `tailDecayPer8ms` below `tailSpeed`, ending under `stopDelta` px per 60 Hz frame.
///
/// The curve is a fixed function of the time since the seed (velocity is constant within each
/// 8 ms step), and a frame covers the part of it that falls into its interval. Distance and
/// duration are therefore the same at any refresh rate.
///
/// ScrollPoster runs it underneath the smoothing: each frame moves at least as far as the
/// glide, so the page keeps its speed when the wheel is let go instead of settling at once.
struct ScrollMomentum {

    /// The curve's step (WebKit models the system curve at 125 Hz).
    static let curveStep: TimeInterval = 0.008
    /// Wheel pause that counts as letting go: twice the last interval between two wheel
    /// events, within these bounds. A fast flick is released sooner than slow scrolling.
    static let releaseGapRange: ClosedRange<TimeInterval> = 0.05...0.16

    /// Signed glide velocity in px/s; 0 = no glide.
    private(set) var velocity = 0.0
    /// Time left in the current curve step; 0 = the next step starts (and decays) first.
    private var stepRemainder: TimeInterval = 0

    var isActive: Bool { return velocity != 0 }

    /// 0 up to `minFlingRate` lines/s, 1 from `fullFlingRate`, a smoothstep in between.
    static func flingGain(lineRate: Double, settings: ScrollMomentumSettings) -> Double {
        guard lineRate.isFinite else { return 0 }
        let span = settings.fullFlingRate - settings.minFlingRate
        guard span > 0 else { return lineRate >= settings.fullFlingRate ? 1 : 0 }
        return ScrollTuningSettings.smoothstep((lineRate - settings.minFlingRate) / span)
    }

    /// Speed (px/s) below which the glide ends: `stopDelta` px per 60 Hz frame.
    static func stopSpeed(settings: ScrollMomentumSettings) -> Double {
        return max(0, settings.stopDelta) * ScrollMotion.referenceFrameRate
    }

    /// Velocity factor of one 8 ms step at `speed` px/s.
    static func decay(speed: Double, settings: ScrollMomentumSettings) -> Double {
        guard settings.tailSpeed > 0 else { return settings.decayPer8ms }
        let weak = max(0, (settings.tailSpeed - abs(speed)) / settings.tailSpeed)
        return settings.decayPer8ms - (settings.decayPer8ms - settings.tailDecayPer8ms) * weak
    }

    /// See `releaseGapRange`. Without a previous event (a single notch) the longest gap applies.
    static func releaseGap(lastInterval: TimeInterval?) -> TimeInterval {
        guard let interval = lastInterval, interval.isFinite else { return releaseGapRange.upperBound }
        return min(releaseGapRange.upperBound, max(releaseGapRange.lowerBound, 2 * interval))
    }

    /// Starts (or replaces) the glide from one wheel event.
    /// - Parameters:
    ///   - inputSpeed: how fast the wheel currently scrolls, px/s (`ScrollLeadLimiter.inputSpeed`)
    ///   - direction: sign of the event's distance
    ///   - lineRate: wheel speed in lines/s, for the fling gain
    /// A wheel speed below the fling range (a single notch, slow scrolling) leaves no glide.
    mutating func seed(inputSpeed: Double, direction: Double, lineRate: Double, settings: ScrollMomentumSettings) {
        let gain = max(0, settings.coastGain) * Self.flingGain(lineRate: lineRate, settings: settings)
        let speed = inputSpeed.isFinite ? max(0, inputSpeed) * gain : 0
        guard direction != 0, speed >= Self.stopSpeed(settings: settings) else {
            cancel()
            return
        }
        velocity = direction > 0 ? speed : -speed
        stepRemainder = 0
    }

    /// Distance (signed px) the glide covers in the next `interval` seconds; 0 once it has ended.
    mutating func advance(interval: TimeInterval, settings: ScrollMomentumSettings) -> Double {
        guard velocity != 0, interval.isFinite, interval > 0 else { return 0 }
        let stopSpeed = Self.stopSpeed(settings: settings)
        var remaining = interval
        var distance = 0.0
        while remaining > 1e-12 {
            if stepRemainder <= 1e-12 {
                velocity *= Self.decay(speed: velocity, settings: settings)
                guard abs(velocity) >= stopSpeed else {
                    cancel()
                    break
                }
                stepRemainder = Self.curveStep
            }
            let slice = min(remaining, stepRemainder)
            distance += velocity * slice
            remaining -= slice
            stepRemainder -= slice
        }
        return distance
    }

    mutating func cancel() {
        velocity = 0
        stepRemainder = 0
    }
}

/// Turns fractional per-frame distances into whole numbers without losing the fractions:
/// the part that is not sent is added to the next value. The sum of the returned values
/// stays within half a unit of the sum of the inputs.
///
/// Scroll events carry whole pixels (CoreGraphics drops the fraction of a point delta), so
/// without the carry every frame loses up to a pixel and slow frames scroll nothing at all.
struct ScrollSubpixelCarry {

    private(set) var remainder = 0.0

    mutating func take(_ value: Double) -> Int64 {
        guard value.isFinite else { return 0 }
        let total = remainder + value
        // Nearest whole number, with exactly one half staying behind: a value of 0 then
        // never produces output (and never flips a waiting half back and forth).
        let magnitude = (abs(total) - 0.5).rounded(.up)
        let whole = total < 0 ? -magnitude : magnitude
        guard abs(whole) < 1e15 else {
            remainder = 0
            return 0
        }
        remainder = total - whole
        return Int64(whole)
    }

    mutating func reset() {
        remainder = 0
    }
}

/// Converts CGEvent timestamps to seconds on the CACurrentMediaTime clock.
///
/// The CGEventTimestamp header says nanoseconds, but events from the HID system carry
/// mach_absolute_time ticks. On Intel a tick is 1 ns, on Apple Silicon 125/3 ns (24 MHz),
/// so ticks must be scaled with mach_timebase_info. Synthetic events can carry real
/// nanoseconds (some tools set them that way); read as ticks those lie in the future, which
/// is used to tell them apart. A zero timestamp falls back to the current time.
enum ScrollEventClock {

    private static let timebase: (numer: Double, denom: Double) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        guard info.numer > 0, info.denom > 0 else { return (1, 1) }
        return (Double(info.numer), Double(info.denom))
    }()

    /// Seconds per mach tick.
    static var secondsPerTick: Double {
        return timebase.numer / timebase.denom / 1_000_000_000
    }

    /// Allowed clock skew when deciding whether a timestamp lies in the future (50 ms).
    private static let futureTolerance: Double = 0.05

    /// - Parameters:
    ///   - timestamp: CGEvent.timestamp
    ///   - now: mach_absolute_time() at the time of reading
    /// - Returns: seconds on the mach clock, or nil if the timestamp is unusable.
    static func seconds(fromTimestamp timestamp: UInt64, now: UInt64) -> TimeInterval? {
        guard timestamp != 0 else { return nil }
        let nowSeconds = Double(now) * secondsPerTick
        let asTicks = Double(timestamp) * secondsPerTick
        if asTicks <= nowSeconds + futureTolerance {
            return asTicks
        }
        let asNanoseconds = Double(timestamp) / 1_000_000_000
        if asNanoseconds <= nowSeconds + futureTolerance {
            return asNanoseconds
        }
        return nil
    }

    static func seconds(fromTimestamp timestamp: UInt64) -> TimeInterval {
        let now = mach_absolute_time()
        return seconds(fromTimestamp: timestamp, now: now) ?? Double(now) * secondsPerTick
    }

    /// The current time as a CGEvent timestamp in the unit `original` uses (mach ticks or
    /// nanoseconds, told apart as in `seconds(fromTimestamp:now:)`), for events that are posted
    /// later than the event they were copied from. Apps derive scroll velocity from event
    /// timestamps, so every posted frame needs its own. 0 stays 0 (the system stamps it).
    static func timestamp(now: UInt64, like original: UInt64) -> UInt64 {
        guard original != 0 else { return 0 }
        let nowSeconds = Double(now) * secondsPerTick
        if Double(original) * secondsPerTick <= nowSeconds + futureTolerance {
            return now
        }
        return UInt64(nowSeconds * 1_000_000_000)
    }
}
