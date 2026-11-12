//
//  ThumbWheelPacer.swift
//  Mos
//
//  Between the stepper and the actions: the steps of a function with a pacing run no faster
//  than its interval. The system handles volume keys slowly: two presses per event at speed 3
//  (about 100 a second) queued up, and the volume display moved on for seconds after the hand
//  had stopped (the owner's second log, 2026-11-11). A step runs at once when none ran within
//  the interval, else it waits; one waiting step runs each interval; at most `maxWaiting` wait
//  and more are dropped, so the action stops soon after the hand does.
//
//  Pure: the time is passed in. ThumbWheelEngine uses it on the main thread.
//

import Foundation

/// How fast one function's steps may run.
struct ThumbWheelPacing: Equatable {
    /// At most one step per this many seconds.
    var interval: TimeInterval
    /// At most this many steps wait; more are dropped.
    var maxWaiting: Int
}

extension ThumbWheelFunction {

    /// Nil: the function's steps run at once, as the stepper decides them (zoom, tabs,
    /// desktops and back / forward feel right that way, the owner says).
    var pacing: ThumbWheelPacing? {
        switch self {
        case .volume: return ThumbWheelTuning.volumePacing
        case .scroll, .zoom, .tabs, .desktops, .backForward: return nil
        }
    }
}

/// The steps that wait to run, and when the last one ran. Pure value type.
struct ThumbWheelPacer: Equatable {

    /// Steps waiting to run, signed: positive toward "next".
    private(set) var waiting = 0
    /// When the last step ran (nil before the first).
    private(set) var lastRunAt: TimeInterval?

    struct Added: Equatable {
        /// The step to run now (±1), or 0: it waits.
        var runNow: Int
        /// Steps that will not run: beyond `maxWaiting`, or waiting in the other direction.
        var dropped: Int
    }

    /// Steps the stepper decided at `now` (signed).
    mutating func add(_ steps: Int, pacing: ThumbWheelPacing, at now: TimeInterval) -> Added {
        guard steps != 0 else { return Added(runNow: 0, dropped: 0) }
        let sign = steps > 0 ? 1 : -1
        var dropped = 0
        // Turning back: the steps of the old direction that wait go; the new ones are first.
        if waiting != 0 && (waiting > 0) != (steps > 0) {
            dropped += abs(waiting)
            waiting = 0
        }
        var remaining = abs(waiting) + abs(steps)
        var runNow = 0
        if canRun(pacing, at: now) {
            runNow = sign
            remaining -= 1
            lastRunAt = now
        }
        let kept = min(remaining, max(0, pacing.maxWaiting))
        dropped += remaining - kept
        waiting = kept * sign
        return Added(runNow: runNow, dropped: dropped)
    }

    /// A look at `now`: the step to run (±1) when one waits and the interval has passed, else 0.
    mutating func take(pacing: ThumbWheelPacing, at now: TimeInterval) -> Int {
        guard waiting != 0, canRun(pacing, at: now) else { return 0 }
        let sign = waiting > 0 ? 1 : -1
        waiting -= sign
        lastRunAt = now
        return sign
    }

    /// When the next waiting step may run; nil when none waits (nothing to schedule).
    func nextRunAt(pacing: ThumbWheelPacing) -> TimeInterval? {
        guard waiting != 0, let last = lastRunAt else { return nil }
        return last + pacing.interval
    }

    /// Drops the waiting steps (a stop, another function, the end of a roll).
    /// - Returns: how many were dropped.
    mutating func dropWaiting() -> Int {
        let dropped = abs(waiting)
        waiting = 0
        return dropped
    }

    private func canRun(_ pacing: ThumbWheelPacing, at now: TimeInterval) -> Bool {
        guard let last = lastRunAt else { return true }
        return now - last + ThumbWheelTuning.thresholdSlack >= pacing.interval
    }
}
