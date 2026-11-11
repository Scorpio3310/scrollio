//
//  ScrollMotion.swift
//  Mos
//
//  Pure maths behind ScrollPoster's per-frame motion:
//  - frame-rate independent smoothing (the Duration factor is defined per 60 Hz frame);
//  - how strong ScrollFilter is;
//  - how far the smoothed position may trail the wheel (lead cap);
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

    /// ScrollFilter's weight per 60 Hz frame for the Duration factor `transition`.
    ///
    /// The page answers a notch at once (the lerp moves fastest on its first frame) and then
    /// glides out; the filter only rounds that first step off. Its time constant is the
    /// classic 64 ms, or the lerp's own where that is shorter, so direct settings stay direct.
    ///
    /// (A version with two equal lags, soft on both ends, was tried on 2026-11-11 and taken
    /// back out: at long durations the page answered the wheel so late that it felt dead.)
    static func filterWeight(forTransition transition: Double) -> Double {
        guard transition.isFinite else { return filterWeight }
        return min(1, max(filterWeight, transition))
    }
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
/// distance on a fast spin, where one event carries several lines.
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
}
