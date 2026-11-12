//
//  AppSystemLog.swift
//  Mos
//
//  The app's own health in the system log, category `app`: starting and stopping and why,
//  event taps that could not be created or that macOS turned off, restarts and their
//  throttle, the display link's recovery, watchdogs, and the takeover of other copies.
//
//      log show --last 1h --predicate 'subsystem == "com.nikklemenc.Scrollio" AND category == "app"'
//
//  Low volume only: state changes and failures, never a line per event. The lines about
//  taps turned off by macOS are counted and written at most every 10 s per tap
//  (`EventTapDisableCounter`).
//

import Foundation
import CoreGraphics
import os

enum AppSystemLog {

    // `os.Logger`: the app has a `Logger` class of its own.
    private static let logger = os.Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Scrollio",
        category: "app"
    )

    /// A state change: started, stopped, paused, woke up.
    static func note(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }

    /// Something did not work: a tap that could not be created, a watchdog that fired.
    static func problem(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}

// MARK: - Event taps

/// The event taps by what they listen to, as the log names them.
enum EventTapKind: String, CaseIterable {
    case scroll = "scroll"
    case scrollKeys = "scroll keys"
    case leftClick = "left click"
    /// ButtonCore's tap for the extra mouse buttons.
    case buttons = "buttons"
    /// ButtonCore's tap for the keyboard, made only while a key is bound or a button holds
    /// a modifier.
    case keys = "keys"
    /// One tap for both, as ButtonCore had it before the keyboard got a tap of its own.
    case buttonsAndKeys = "buttons and keys"
    case pointerMovement = "pointer movement"
    /// The key recorder's tap, while a recording runs.
    case recorder = "recorder"
    case other = "other"

    /// The kind of a tap from its event mask (ScrollCore, ButtonCore, the gesture motion
    /// tap and the recorder each listen to their own set of events). The recorder is told
    /// by listening to the left button and to keys at once: its mask has the modifier keys
    /// too, and it used to be named "scroll keys", so "Could not create the scroll keys
    /// event tap" for a recorder that could not start sent a reader to the wrong place.
    static func of(mask: CGEventMask) -> EventTapKind {
        func has(_ type: CGEventType) -> Bool { mask & CGEventMask(1 << type.rawValue) != 0 }
        if has(.scrollWheel) { return .scroll }
        if has(.mouseMoved) || has(.otherMouseDragged) { return .pointerMovement }
        if has(.leftMouseDown) && has(.keyDown) { return .recorder }
        if has(.flagsChanged) { return .scrollKeys }
        if has(.otherMouseDown) && has(.keyDown) { return .buttonsAndKeys }
        if has(.otherMouseDown) { return .buttons }
        if has(.keyDown) { return .keys }
        if has(.leftMouseDown) { return .leftClick }
        return .other
    }
}

/// Counts the times macOS turned one event tap off (`tapDisabledByTimeout`,
/// `tapDisabledByUserInput`) and decides when a line is written: the first time at once,
/// then at most one line every `interval` with the number since the last line. Times that
/// came after a line are written by a flush once the interval has passed, so none is lost.
/// Pure: the caller passes a monotonic clock and schedules the flush.
struct EventTapDisableCounter {

    static let interval: TimeInterval = 10

    enum Reason: Equatable {
        case timeout
        case userInput
    }

    enum Decision: Equatable {
        /// Write this line now.
        case log(String)
        /// Call `flush` after this many seconds.
        case flush(after: TimeInterval)
        /// Nothing to do: counted for a later line.
        case none
    }

    private(set) var timeouts = 0
    private(set) var userInputs = 0
    private var lastLineAt: TimeInterval?
    private var flushPending = false

    /// One time the tap was turned off.
    mutating func note(_ reason: Reason, tap: EventTapKind, now: TimeInterval) -> Decision {
        switch reason {
        case .timeout: timeouts += 1
        case .userInput: userInputs += 1
        }
        if let wait = remaining(now: now) {
            guard !flushPending else { return .none }
            flushPending = true
            return .flush(after: wait)
        }
        // A flush that is still scheduled finds nothing, or waits again.
        return .log(takeLine(tap: tap, now: now))
    }

    /// The scheduled flush: the line for the times counted since the last line.
    mutating func flush(tap: EventTapKind, now: TimeInterval) -> Decision {
        guard flushPending else { return .none }
        guard timeouts + userInputs > 0 else {
            flushPending = false
            return .none
        }
        if let wait = remaining(now: now) {
            return .flush(after: wait)
        }
        flushPending = false
        return .log(takeLine(tap: tap, now: now))
    }

    /// Seconds until the next line may be written; nil when it may be written now.
    private func remaining(now: TimeInterval) -> TimeInterval? {
        guard let lastLineAt else { return nil }
        let elapsed = now - lastLineAt
        return elapsed >= Self.interval ? nil : Self.interval - elapsed
    }

    private mutating func takeLine(tap: EventTapKind, now: TimeInterval) -> String {
        let line = Self.line(tap: tap, timeouts: timeouts, userInputs: userInputs)
        timeouts = 0
        userInputs = 0
        lastLineAt = now
        return line
    }

    static func line(tap: EventTapKind, timeouts: Int, userInputs: Int) -> String {
        let timeoutText = "timeout (Scrollio's main thread answered too slowly)"
        switch (timeouts, userInputs) {
        case (1, 0):
            return "macOS turned off the \(tap.rawValue) event tap: \(timeoutText)"
        case (0, 1):
            return "macOS turned off the \(tap.rawValue) event tap: user input"
        default:
            let total = timeouts + userInputs
            return "macOS turned off the \(tap.rawValue) event tap \(total) times since the last line: "
                + "\(timeouts) \(timeouts == 1 ? "timeout" : "timeouts") (Scrollio's main thread answered too slowly), "
                + "\(userInputs) by user input"
        }
    }
}

/// The live counters, one per tap. Called from the taps' callbacks only when macOS turned a
/// tap off, never for an ordinary event.
enum EventTapDisableLog {

    private static let lock = NSLock()
    private static var counters: [EventTapKind: EventTapDisableCounter] = [:]

    /// Why a "turned off" event is a problem worth a line; nil when it is none.
    ///
    /// Only a timeout is: macOS gave up on the tap because Scrollio's main thread answered
    /// too slowly. `tapDisabledByUserInput` is what a tap's callback gets whenever the tap
    /// is switched off with `CGEvent.tapEnable(tap:enable: false)`, and that is Scrollio
    /// itself every time it pauses a tap: Pause, sleep, a restart, the end of a gesture
    /// hold. Logged as a problem it read "macOS turned off the pointer movement event tap:
    /// user input" right after every launch.
    static func problem(for type: CGEventType) -> EventTapDisableCounter.Reason? {
        return type == .tapDisabledByTimeout ? .timeout : nil
    }

    /// `type` is the event type the tap's callback got; only a timeout is logged.
    static func note(_ tap: EventTapKind, _ type: CGEventType) {
        guard let reason = problem(for: type) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        let decision = counters[tap, default: EventTapDisableCounter()].note(reason, tap: tap, now: now)
        lock.unlock()
        carryOut(decision, tap: tap)
    }

    private static func flush(_ tap: EventTapKind) {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        let decision = counters[tap, default: EventTapDisableCounter()].flush(tap: tap, now: now)
        lock.unlock()
        carryOut(decision, tap: tap)
    }

    private static func carryOut(_ decision: EventTapDisableCounter.Decision, tap: EventTapKind) {
        switch decision {
        case .log(let line):
            AppSystemLog.problem(line)
        case .flush(let after):
            DispatchQueue.main.asyncAfter(deadline: .now() + after) { flush(tap) }
        case .none:
            break
        }
    }
}
