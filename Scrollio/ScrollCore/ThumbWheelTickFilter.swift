//
//  ThumbWheelTickFilter.swift
//  Scrollio
//
//  Between a sideways wheel event and what it does (the stepper, or the swipe of "Follow the
//  wheel"), for every function but Scroll Sideways: a small stray tick, or a pair of them,
//  does nothing. The owner's log (2026-11-14/15) shows them where the thumb lets go of the
//  wheel and takes it again: a tick of about 0.1 line the other way inside a roll, or one or
//  two 0.7 to 1 s after a roll (a pair of 0.20 to 0.23 line in all). Without the filter such
//  ticks dropped the travel a roll had carried, at speed 3 stepped the wrong way on their
//  own, and in Follow the wheel began a swipe.
//
//  A small event (less than `tickSmallLines`) waits for more:
//  1. Start: nothing was applied within `tickWindow` and the event is small: it is held.
//  2. Reversal: something was applied within the window and the small event goes against
//     it: it is held.
//  The held events apply, with the one that confirms them, once the events that way within
//  the window (from the first held) make `tickSmallLines` in all, or at the
//  `tickConfirmingEvents`th of them; until then a further one that way is held too. What
//  is confirmed is handed over as one batch with the time of its first held event: the
//  thumb took the wheel then, so the stepper measures its rest there, not at the event
//  that confirmed it.
//  3. Everything else applies at once. Held events are dropped when an event comes the
//     other way, or once the first is older than the window; held travel is never
//     subtracted.
//  The cost: a deliberate turn back, or a slow start with small ticks, acts one or two
//  events later (15 to 300 ms).
//
//  Pure: the time is passed in. ThumbWheelEngine uses it on the main thread.
//

import Foundation

struct ThumbWheelTickFilter: Equatable {

    /// What one event comes to.
    struct Result: Equatable {
        /// Travel to apply now (signed as the event's; 0: nothing).
        var travel: Double
        /// The event is held.
        var held: Bool
        /// Held events this event dropped (an older one that went the other way, or expired).
        var dropped: Int
        /// The event confirmed held ones, and `travel` is theirs and its own: the time of
        /// the first of them. Nil: the event applies alone, is held, or does nothing.
        var heldSince: TimeInterval? = nil

        static let nothing = Result(travel: 0, held: false, dropped: 0)
    }

    /// The held events' travel (0: none held), their lines (unsigned) and number, and the
    /// first one's time.
    private(set) var heldTravel = 0.0
    private(set) var heldLines = 0.0
    private(set) var heldEvents = 0
    private(set) var heldAt: TimeInterval = 0
    /// When an event was last applied (nil: none yet), and its direction (+1, −1).
    private(set) var lastAppliedAt: TimeInterval?
    private(set) var lastAppliedDirection = 0

    var holds: Bool { return heldEvents > 0 }

    /// One event.
    /// - Parameters:
    ///   - travel: its travel toward "next" (the stepper's or the follower's units).
    ///   - lines: its lines (`ThumbWheelStepper.lines`), signed or not: decides "small".
    ///   - time: its own time (s).
    mutating func filter(travel: Double, lines: Double, at time: TimeInterval) -> Result {
        guard travel != 0, travel.isFinite else { return .nothing }
        let direction = travel > 0 ? 1 : -1
        let size = lines.isFinite ? lines.magnitude : .infinity
        var dropped = 0
        if holds {
            let sameWay = (heldTravel > 0) == (direction > 0)
            if time - heldAt > Self.window {
                dropped += dropHeld()
            } else if sameWay {
                heldTravel += travel
                heldLines += size
                heldEvents += 1
                guard heldLines + ThumbWheelTuning.thresholdSlack >= ThumbWheelTuning.tickSmallLines
                    || heldEvents >= ThumbWheelTuning.tickConfirmingEvents else {
                    // Still less than half a line (where the thumb lets go: a pair of ticks).
                    return Result(travel: 0, held: true, dropped: 0)
                }
                // Confirmed: the held events and this one apply.
                let all = heldTravel
                let since = heldAt
                forgetHeld()
                applied(direction, at: time)
                return Result(travel: all, held: false, dropped: 0, heldSince: since)
            } else {
                dropped += dropHeld()
            }
        }
        let recent = lastAppliedAt.map { time - $0 <= Self.window } ?? false
        if size < ThumbWheelTuning.tickSmallLines && (!recent || direction != lastAppliedDirection) {
            heldTravel = travel
            heldLines = size
            heldEvents = 1
            heldAt = time
            return Result(travel: 0, held: true, dropped: dropped)
        }
        applied(direction, at: time)
        return Result(travel: travel, held: false, dropped: dropped)
    }

    /// Drops the held events, if any (the wheel rested: they are older than the window
    /// anyway).
    /// - Returns: how many were dropped.
    @discardableResult
    mutating func dropHeld() -> Int {
        let dropped = heldEvents
        forgetHeld()
        return dropped
    }

    private mutating func forgetHeld() {
        heldTravel = 0
        heldLines = 0
        heldEvents = 0
        heldAt = 0
    }

    /// Forgets everything (a stop, another function).
    /// - Returns: the held events dropped.
    @discardableResult
    mutating func reset() -> Int {
        let dropped = dropHeld()
        lastAppliedAt = nil
        lastAppliedDirection = 0
        return dropped
    }

    private mutating func applied(_ direction: Int, at time: TimeInterval) {
        lastAppliedAt = time
        lastAppliedDirection = direction
    }

    /// "Within the window", with rounding slack.
    private static var window: TimeInterval {
        return ThumbWheelTuning.tickWindow + ThumbWheelTuning.thresholdSlack
    }
}
