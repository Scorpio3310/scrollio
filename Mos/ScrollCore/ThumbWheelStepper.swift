//
//  ThumbWheelStepper.swift
//  Mos
//
//  What a turn of the sideways wheel (the thumb wheel of an MX Master, or a wheel that tilts)
//  does when it runs a function instead of scrolling. The wheel's events are counted, not its
//  lines: macOS accelerates a turn so much that the lines of one event (0.1 to 12 on the
//  owner's MX Master 4) say more about macOS than about the thumb. Each event is one unit of
//  travel (up to two for the functions that accelerate, on a fast turn), times the speed
//  setting; a step runs when the travel reaches the function's threshold ("first" after a rest
//  or a change of direction, "next" while the roll goes on), and uses that threshold up.
//
//  Pure: the time is passed in. ThumbWheelEngine uses it on the main thread.
//

import Foundation

/// How one function turns travel into steps.
struct ThumbWheelStepping: Equatable {
    /// Units of travel before the first step after a rest or a change of direction.
    var first: Double
    /// Units of travel before each further step while the roll goes on.
    var next: Double
    /// A fast turn counts for more than one unit per event (`ThumbWheelStepper.units`).
    var accelerates: Bool
    /// A pause this long (s) drops the carried travel; the next step is a "first" one again.
    var rest: TimeInterval
}

/// Every number of the thumb wheel's functions, in one place. They come from the owner's log
/// of 2026-11-11 (his mouse: MX Master 4 over Bluetooth): a slow roll is 5 to 10 events over
/// 0.7 to 1.5 s of 0.1 to 1 line each, a medium one 6 to 10 events in 0.2 to 0.5 s of about 5
/// lines, a flick 8 to 10 events in 0.1 to 0.16 s of 8 to 12 lines, long rolling 20 to 40
/// events over 1.5 to 2 s; gaps inside a slow roll reach 300 to 400 ms. Tune them from the
/// `scroll` log, one "thumb wheel: ..." line per roll (`ScrollSystemLog.thumbWheelMessage`),
/// which gives the travel in units next to the steps.
enum ThumbWheelTuning {
    /// An event with only a point delta: this many points make one line.
    static let pointsPerLine = 10.0
    /// Acceleration of the functions that accelerate: one unit up to this many lines in one
    /// event (a slow or medium turn)...
    static let accelerationFromLines = 2.0
    /// ...rising evenly to 1 + `accelerationExtraUnits` at this many lines (a flick).
    static let accelerationFullAtLines = 10.0
    static let accelerationExtraUnits = 1.0
    /// At most this many steps from one event; the travel of further steps is dropped, not
    /// carried, so a fast turn at speed 3 does not come out in bursts.
    static let maxStepsPerEvent = 2

    /// Volume: a slow roll of 9 events gives 3 steps, a flick of 10 events about 6, long
    /// rolling (35 events) roughly 11 to 16, so a roll no longer runs the whole range (16
    /// steps) at once.
    static let volume = ThumbWheelStepping(first: 2, next: 3, accelerates: true, rest: 0.6)
    /// Zoom: like volume, a little slower (zoom steps are bigger).
    static let zoom = ThumbWheelStepping(first: 3, next: 5, accelerates: true, rest: 0.6)
    /// Tabs: a slow roll of 5 to 9 events gives 1 to 2 tabs, a flick of 10 events 2.
    static let tabs = ThumbWheelStepping(first: 3, next: 5, accelerates: false, rest: 0.6)
    /// Desktops and back / forward: one stroke of 3 to 14 events gives one step, 15 events two;
    /// a second quick stroke after 0.3 s of rest steps again after 3 events.
    static let desktops = ThumbWheelStepping(first: 3, next: 12, accelerates: false, rest: 0.3)
    static let backForward = ThumbWheelStepping(first: 3, next: 12, accelerates: false, rest: 0.3)

    /// Volume's pacing (`ThumbWheelPacer`): at most one step each 50 ms, at most 3 waiting.
    /// From the owner's second log (2026-11-11): at speed 3 two volume key presses per event,
    /// about 100 a second, queued up in the system, and the volume display moved on for seconds
    /// after the hand stopped. 20 steps a second sweep the whole range (16 steps) in under a
    /// second; with 3 waiting the volume stops within 150 ms of the hand. The other functions
    /// have no pacing: their steps feel right at once.
    static let volumePacing = ThumbWheelPacing(interval: 0.05, maxWaiting: 3)

    /// A pause this long (s) ends a roll for the log: its line is written.
    static let logRollRest: TimeInterval = 0.6
    /// During a long roll a log line is written at least this often (s), and at most this
    /// often apart from the line at its end.
    static let logInterval: TimeInterval = 2.0
    /// A roll's line is due but steps still wait to run: the look comes again after at least
    /// this long (s), so it never spins on the main queue.
    static let pendingRecheck: TimeInterval = 0.01
    /// Rounding slack: travel this close under a threshold counts as reaching it (fractions of
    /// a unit added up are not exact in binary).
    static let thresholdSlack = 1e-9
}

extension ThumbWheelFunction {

    /// How the function's travel becomes steps; nil while the wheel scrolls.
    var stepping: ThumbWheelStepping? {
        switch self {
        case .scroll: return nil
        case .volume: return ThumbWheelTuning.volume
        case .zoom: return ThumbWheelTuning.zoom
        case .tabs: return ThumbWheelTuning.tabs
        case .desktops: return ThumbWheelTuning.desktops
        case .backForward: return ThumbWheelTuning.backForward
        }
    }

    /// The function's name in the `scroll` log (English, not localized; not shown in the UI).
    var logName: String {
        switch self {
        case .scroll: return "scroll sideways"
        case .zoom: return "zoom"
        case .tabs: return "switch tabs"
        case .desktops: return "switch desktops"
        case .backForward: return "back and forward"
        case .volume: return "volume"
        }
    }
}

/// Turns sideways wheel events into steps. Pure value type.
///
/// Direction: travel is counted toward "next": a NEGATIVE X delta of the raw event (its
/// horizontal delta as it arrived at the tap), turned around only by the thumb wheel's "Swap
/// direction". A negative X delta, as a scroll, shows what lies to the right (a positive one
/// moves the content right and shows what lies to the left, as a positive Y delta shows what
/// lies above). "Reverse wheel direction" (global or an app's) and the allowlist play no part:
/// they depend on the app under the pointer, and a function must not. Which physical turn of
/// the thumb wheel gives a negative X delta only the owner's mouse (the `scroll` log) can show.
/// Steps are positive toward "next" (zoom in, the next tab, the desktop on the right,
/// forward, volume up) and negative toward "previous".
struct ThumbWheelStepper: Equatable {

    /// Travel not yet used for a step, in units: positive toward "next".
    private(set) var carried = 0.0
    /// A step ran since the last rest or change of direction: the next one needs `next`.
    private(set) var stepped = false
    /// The direction of the last event (+1 toward "next", −1, 0 before any).
    private(set) var direction = 0
    /// The time of the last event fed (nil before the first, or after a reset).
    private(set) var lastEventAt: TimeInterval?
    /// The function of the last event fed: another one starts afresh.
    private(set) var function: ThumbWheelFunction?

    /// One event's lines, signed as the event's X delta: the fixed-point line delta if it is
    /// not 0, else the integer line delta, else the point delta / `pointsPerLine`.
    static func lines(lineDelta: Int64, fixedDelta: Double, pointDelta: Double) -> Double {
        if fixedDelta != 0, fixedDelta.isFinite {
            return fixedDelta
        } else if lineDelta != 0 {
            return Double(lineDelta)
        } else if pointDelta.isFinite {
            return pointDelta / ThumbWheelTuning.pointsPerLine
        }
        return 0
    }

    /// One event's units of travel, before the speed: 1; for a function that accelerates
    /// 1 + clamp((|lines| − 2) / 8, 0…1): 1 up to 2 lines, 1.5 at 6, 2 from 10 lines on.
    /// An event without lines has none.
    static func units(lines: Double, accelerates: Bool) -> Double {
        guard lines != 0, lines.isFinite else { return 0 }
        guard accelerates else { return 1 }
        let from = ThumbWheelTuning.accelerationFromLines
        let span = ThumbWheelTuning.accelerationFullAtLines - from
        let share = min(1, max(0, (lines.magnitude - from) / span))
        return 1 + share * ThumbWheelTuning.accelerationExtraUnits
    }

    /// One event's travel toward "next", in units × speed; 0 while the wheel scrolls.
    /// - Parameters:
    ///   - lineDelta, fixedDelta, pointDelta: the event's X deltas as they arrived.
    ///   - flipped: X is turned around ("Swap direction").
    ///   - speed: the thumb wheel's speed (more travel per event, so steps come sooner).
    static func travel(lineDelta: Int64, fixedDelta: Double, pointDelta: Double, flipped: Bool,
                       speed: Double, function: ThumbWheelFunction) -> Double {
        guard let stepping = function.stepping else { return 0 }
        let x = lines(lineDelta: lineDelta, fixedDelta: fixedDelta, pointDelta: pointDelta)
        let size = units(lines: x, accelerates: stepping.accelerates) * ThumbWheelSettings.clampedSpeed(speed)
        // A negative X delta (after the flip) is "next".
        let towardNext = flipped ? x > 0 : x < 0
        return towardNext ? size : -size
    }

    /// Feeds one event.
    /// - Parameters:
    ///   - travel: the event's travel toward "next" (`travel(...)`).
    ///   - function: the function the wheel runs now.
    ///   - now: the event's time (s, any monotonic clock).
    /// - Returns: the steps to run: positive toward "next", negative toward "previous", 0 none;
    ///   never more than `maxStepsPerEvent` either way.
    mutating func feed(travel: Double, function: ThumbWheelFunction, at now: TimeInterval) -> Int {
        // Another function (changed in the middle of a roll) starts afresh.
        if function != self.function {
            reset()
            self.function = function
        }
        guard let stepping = function.stepping else { return 0 }
        // A rest drops the carried travel; the next step is a first one again.
        if let last = lastEventAt, now - last >= stepping.rest {
            carried = 0
            stepped = false
        }
        lastEventAt = now
        guard travel != 0, travel.isFinite else { return 0 }
        // A change of direction drops what the other direction had carried; the event that
        // turned counts its own travel toward the new direction.
        let sign = travel > 0 ? 1 : -1
        if direction != 0 && sign != direction {
            carried = 0
            stepped = false
        }
        direction = sign
        carried += travel
        var steps = 0
        var threshold = stepped ? stepping.next : stepping.first
        while carried.magnitude + ThumbWheelTuning.thresholdSlack >= threshold {
            if steps == ThumbWheelTuning.maxStepsPerEvent {
                // The travel of further steps is dropped; less than a step stays carried.
                carried = carried.truncatingRemainder(dividingBy: threshold)
                break
            }
            // A step uses up its threshold; the remainder is carried.
            carried -= Double(sign) * threshold
            steps += 1
            stepped = true
            threshold = stepping.next
        }
        if carried.magnitude < ThumbWheelTuning.thresholdSlack { carried = 0 }
        return steps * sign
    }

    /// Forgets everything: the next event starts a new roll.
    mutating func reset() {
        carried = 0
        stepped = false
        direction = 0
        lastEventAt = nil
        function = nil
    }
}
