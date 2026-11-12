//
//  ToastTiming.swift
//  Mos
//  How long a toast stays on screen. Pure: the toast manager and its tests share it.
//
//  A toast that names no duration stays as long as its text takes to read: a short
//  confirmation three seconds, a warning that says what to do up to ten. While the pointer
//  is over a toast its time stands still, and when the pointer leaves there is always a
//  moment left, so a toast is never taken away from under the reader.
//

import Foundation

enum ToastTiming {

    /// The shortest and the longest a toast stays when its caller names no duration.
    static let minimumDuration: TimeInterval = 3
    static let maximumDuration: TimeInterval = 10
    /// The time to notice a toast, before any reading.
    static let noticeTime: TimeInterval = 1.5
    /// A calm reading pace (about 200 words a minute).
    static let charactersPerSecond: Double = 17
    /// The least a toast still stays after the pointer left it.
    static let minimumAfterHover: TimeInterval = 1.5

    /// How long `message` stays without a duration of its own: the time to notice it and to
    /// read it, between `minimumDuration` and `maximumDuration`. A sentence of 92 characters
    /// gets about 7 seconds.
    static func readingDuration(for message: String) -> TimeInterval {
        let reading = noticeTime + Double(message.count) / charactersPerSecond
        return min(maximumDuration, max(minimumDuration, reading))
    }
}

/// A toast's time on screen: it runs down while the pointer is elsewhere and stands still
/// while the pointer is over the toast.
struct ToastCountdown: Equatable {

    /// What is left, as of the last start or stop.
    private(set) var remaining: TimeInterval
    /// When it last started to run; nil while it stands still.
    private(set) var runningSince: Date?

    /// Starts running at `now`.
    init(duration: TimeInterval, now: Date) {
        remaining = max(0, duration)
        runningSince = now
    }

    var isPaused: Bool {
        return runningSince == nil
    }

    /// The pointer came over the toast: the time stands still at what is left.
    mutating func pause(now: Date) {
        guard let since = runningSince else { return }
        remaining = max(0, remaining - now.timeIntervalSince(since))
        runningSince = nil
    }

    /// The pointer left: the time runs again, with at least `ToastTiming.minimumAfterHover`
    /// left. Returns what is left; nil when it was running all along (nothing to restart).
    mutating func resume(now: Date) -> TimeInterval? {
        guard isPaused else { return nil }
        remaining = max(remaining, ToastTiming.minimumAfterHover)
        runningSince = now
        return remaining
    }
}
