//
//  ThumbWheelStepper.swift
//  Mos
//
//  What a turn of the sideways wheel (the thumb wheel of an MX Master, or a wheel that tilts)
//  does when it runs a function instead of scrolling: the travel of its wheel events is added
//  up, and each time it passes a threshold one step runs (zoom in, the next tab, ...).
//
//  Pure: the time is passed in. ThumbWheelEngine uses it on the main thread.
//

import Foundation

/// Every number of the thumb wheel's functions, in one place. They are first guesses: nobody
/// has yet seen what the owner's thumb wheel sends. Tune them from the `scroll` log, which has
/// one "thumb wheel: ..." line per roll (`ScrollSystemLog.thumbWheelMessage`).
enum ThumbWheelTuning {
    /// An event with only a point delta: this many points make one line.
    static let pointsPerLine = 10.0
    /// One event counts for at most this many lines, before the speed: macOS accelerates fast
    /// turns, and one flick must not run a dozen steps.
    static let maxLinesPerEvent = 3.0
    /// Lines of travel per step, for the functions that repeat while the wheel turns.
    static let zoomLinesPerStep = 1.0
    static let tabsLinesPerStep = 2.0
    static let volumeLinesPerStep = 1.0
    /// Lines of travel before the one step of a roll (desktops, back and forward).
    static let oncePerRollLines = 1.5
    /// A pause this long (s) drops the travel carried toward the next step.
    static let carryRest: TimeInterval = 0.3
    /// A pause this long (s) ends a roll: a function that steps once per roll can step again,
    /// and the roll's log line is written.
    static let rollRest: TimeInterval = 0.4
    /// During a long roll a log line is written at least this often (s), and at most this
    /// often apart from the line at its end.
    static let logInterval: TimeInterval = 2.0
    /// Rounding slack: travel this close under a threshold counts as reaching it (tenths of a
    /// line added up are not exact in binary).
    static let thresholdSlack = 1e-9
}

extension ThumbWheelFunction {

    /// How the travel of the wheel becomes steps.
    enum Stepping: Equatable {
        /// No steps: the wheel scrolls.
        case none
        /// One step each time the travel passes this many lines; the rest is carried.
        case repeating(linesPerStep: Double)
        /// One step when the travel passes this many lines, then none until the wheel rested.
        case oncePerRoll(lines: Double)
    }

    var stepping: Stepping {
        switch self {
        case .scroll: return .none
        case .zoom: return .repeating(linesPerStep: ThumbWheelTuning.zoomLinesPerStep)
        case .tabs: return .repeating(linesPerStep: ThumbWheelTuning.tabsLinesPerStep)
        case .volume: return .repeating(linesPerStep: ThumbWheelTuning.volumeLinesPerStep)
        case .desktops, .backForward: return .oncePerRoll(lines: ThumbWheelTuning.oncePerRollLines)
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

/// Turns the travel of sideways wheel events into steps. Pure value type.
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

    /// Travel not yet used for a step, in lines: positive toward "next".
    private(set) var carried = 0.0
    /// A function that steps once per roll has stepped in this roll.
    private(set) var steppedThisRoll = false
    /// The time of the last event fed (nil before the first, or after a reset).
    private(set) var lastEventAt: TimeInterval?
    /// The function of the last event fed: another one starts afresh.
    private(set) var function: ThumbWheelFunction?

    /// One event's travel in lines, signed as the event's X delta: the fixed-point line delta
    /// if it is not 0, else the integer line delta, else the point delta / `pointsPerLine`; at
    /// most `maxLinesPerEvent` either way.
    static func lines(lineDelta: Int64, fixedDelta: Double, pointDelta: Double) -> Double {
        let lines: Double
        if fixedDelta != 0, fixedDelta.isFinite {
            lines = fixedDelta
        } else if lineDelta != 0 {
            lines = Double(lineDelta)
        } else if pointDelta.isFinite {
            lines = pointDelta / ThumbWheelTuning.pointsPerLine
        } else {
            lines = 0
        }
        let cap = ThumbWheelTuning.maxLinesPerEvent
        return min(cap, max(-cap, lines))
    }

    /// One event's travel toward "next", in lines × speed.
    /// - Parameters:
    ///   - lineDelta, fixedDelta, pointDelta: the event's X deltas as they arrived.
    ///   - flipped: X is turned around ("Swap direction").
    ///   - speed: the thumb wheel's speed (more travel per turn, so steps come sooner).
    static func travel(lineDelta: Int64, fixedDelta: Double, pointDelta: Double, flipped: Bool, speed: Double) -> Double {
        let x = lines(lineDelta: lineDelta, fixedDelta: fixedDelta, pointDelta: pointDelta)
        // A negative X delta (after the flip) is "next".
        let towardNext = flipped ? x : -x
        return towardNext * ThumbWheelSettings.clampedSpeed(speed)
    }

    /// Feeds one event.
    /// - Parameters:
    ///   - travel: the event's travel toward "next" (`travel(...)`).
    ///   - function: the function the wheel runs now.
    ///   - now: the event's time (s, any monotonic clock).
    /// - Returns: the steps to run: positive toward "next", negative toward "previous", 0 none.
    mutating func feed(travel: Double, function: ThumbWheelFunction, at now: TimeInterval) -> Int {
        // Another function (changed in the middle of a roll) starts afresh.
        if function != self.function {
            reset()
            self.function = function
        }
        // A rest drops the carried travel; a longer one ends the roll.
        if let last = lastEventAt {
            let pause = now - last
            if pause >= ThumbWheelTuning.rollRest { steppedThisRoll = false }
            if pause >= ThumbWheelTuning.carryRest { carried = 0 }
        }
        lastEventAt = now
        guard travel != 0, travel.isFinite else { return 0 }
        // A change of direction drops what the other direction had carried.
        if carried != 0 && (carried > 0) != (travel > 0) {
            carried = 0
        }
        switch function.stepping {
        case .none:
            return 0
        case .repeating(let linesPerStep):
            carried += travel
            let whole = ((carried.magnitude + ThumbWheelTuning.thresholdSlack) / linesPerStep).rounded(.towardZero)
            guard whole >= 1 else { return 0 }
            let steps = carried > 0 ? whole : -whole
            carried -= steps * linesPerStep
            if carried.magnitude < ThumbWheelTuning.thresholdSlack { carried = 0 }
            return Int(steps)
        case .oncePerRoll(let lines):
            guard !steppedThisRoll else { return 0 }
            carried += travel
            guard carried.magnitude + ThumbWheelTuning.thresholdSlack >= lines else { return 0 }
            let step = carried > 0 ? 1 : -1
            carried = 0
            steppedThisRoll = true
            return step
        }
    }

    /// Forgets everything: the next event starts a new roll.
    mutating func reset() {
        carried = 0
        steppedThisRoll = false
        lastEventAt = nil
        function = nil
    }
}
