//
//  ThumbWheelTickFilter.swift
//  Scrollio
//
//  Between a sideways wheel event and what it does (the stepper, or the swipe of "Follow the
//  wheel"), for every function but Scroll Sideways: a single small stray tick does nothing.
//  The owner's log (2026-11-14/15) shows them where the thumb lets go of the wheel and takes
//  it again: a tick of about 0.1 line the other way inside a roll, or a lone one 0.7 to 1 s
//  after a roll. Without the filter such a tick dropped the travel a roll had carried, at
//  speed 3 stepped the wrong way on its own, and in Follow the wheel began a swipe.
//
//  A small event (less than `tickSmallLines`) waits for a second one:
//  1. Start: nothing was applied within `tickWindow` and the event is small: it is held; a
//     second event the same way within the window applies both.
//  2. Reversal: something was applied within the window and the small event goes against
//     it: it is held; a second event that way within the window applies both.
//  3. Everything else applies at once. A held event is dropped when an event comes the
//     other way, or once it is older than the window; held travel is never subtracted.
//  The cost: a deliberate turn back, or a slow start with small ticks, acts one event later
//  (15 to 150 ms).
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

        static let nothing = Result(travel: 0, held: false, dropped: 0)
    }

    /// The held event's travel (0: none held) and its time.
    private(set) var heldTravel = 0.0
    private(set) var heldAt: TimeInterval = 0
    /// When an event was last applied (nil: none yet), and its direction (+1, −1).
    private(set) var lastAppliedAt: TimeInterval?
    private(set) var lastAppliedDirection = 0

    var holds: Bool { return heldTravel != 0 }

    /// One event.
    /// - Parameters:
    ///   - travel: its travel toward "next" (the stepper's or the follower's units).
    ///   - lines: its lines (`ThumbWheelStepper.lines`), signed or not: decides "small".
    ///   - time: its own time (s).
    mutating func filter(travel: Double, lines: Double, at time: TimeInterval) -> Result {
        guard travel != 0, travel.isFinite else { return .nothing }
        let direction = travel > 0 ? 1 : -1
        var dropped = 0
        if holds {
            let sameWay = (heldTravel > 0) == (direction > 0)
            if time - heldAt > Self.window {
                dropped += dropHeld()
            } else if sameWay {
                // The second event confirms the held one: both apply.
                let both = heldTravel + travel
                _ = dropHeld()
                applied(direction, at: time)
                return Result(travel: both, held: false, dropped: 0)
            } else {
                dropped += dropHeld()
            }
        }
        let small = lines.isFinite && lines.magnitude < ThumbWheelTuning.tickSmallLines
        let recent = lastAppliedAt.map { time - $0 <= Self.window } ?? false
        if small && (!recent || direction != lastAppliedDirection) {
            heldTravel = travel
            heldAt = time
            return Result(travel: 0, held: true, dropped: dropped)
        }
        applied(direction, at: time)
        return Result(travel: travel, held: false, dropped: dropped)
    }

    /// Drops the held event, if any (the wheel rested: it is older than the window anyway).
    /// - Returns: how many were dropped (0 or 1).
    @discardableResult
    mutating func dropHeld() -> Int {
        guard holds else { return 0 }
        heldTravel = 0
        heldAt = 0
        return 1
    }

    /// Forgets everything (a stop, another function).
    /// - Returns: the held events dropped (0 or 1).
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
