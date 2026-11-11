//
//  ScrollSystemLog.swift
//  Mos
//
//  What smooth scrolling really did, in the system log:
//
//      log show --last 10m --predicate 'subsystem == "com.nikklemenc.Scrollio" AND category == "scroll"'
//
//  One line per finished scroll (never per event), and one line now and then when wheel
//  events are let through unsmoothed, with the reason; one line per roll of the sideways
//  (thumb) wheel, with what it sent and what it ran. Tests pass on a simulated wheel; this
//  is how to see what happened on the real one.
//

import Foundation
import CoreGraphics
import os

enum ScrollSystemLog {

    private static let logger = os.Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Scrollio",
        category: "scroll"
    )

    /// What one scroll (from the first wheel event to the stop) added up to.
    struct Session {
        var inputs = 0
        var inputDistance = 0.0
        var frames = 0
        var postedDistance = 0.0
        var largestFrame = 0.0
        var startedAt: CFTimeInterval = 0
        var lastInputAt: CFTimeInterval = 0
        var lastFrameAt: CFTimeInterval = 0
        /// The Duration factor the wheel events really used (per 60 Hz frame): the global one,
        /// or an app's own. The last event's wins.
        var transition = 0.0
        var trackpadStyle = false

        var isEmpty: Bool { return inputs == 0 }

        /// The Duration (slider value) behind `transition`.
        var duration: Double { return ScrollSystemLog.duration(forTransition: transition) }
    }

    /// Inverse of `OPTIONS_SCROLL_DEFAULT.generateDurationTransition` (1 − √(d / 5.2)); exact
    /// to about 0.002 because the factor is rounded to three decimals.
    static func duration(forTransition transition: Double) -> Double {
        guard transition.isFinite else { return 0 }
        let root = 1 - min(1, max(0, transition))
        return 5.2 * root * root
    }

    static func message(for session: Session, endedWith phase: String) -> String {
        let tau = ScrollMotion.timeConstant(forTransition: session.transition)
        return String(
            format: "scroll: %d wheel events %.0f px in -> %d frames %.0f px out (largest %.1f), wheel %.0f ms, glide after the last event %.0f ms, Duration %.2f (tau %.0f ms), trackpad-style %@, ended %@",
            session.inputs, session.inputDistance, session.frames, session.postedDistance, session.largestFrame,
            (session.lastInputAt - session.startedAt) * 1000,
            max(0, session.lastFrameAt - session.lastInputAt) * 1000,
            session.duration, tau * 1000,
            session.trackpadStyle ? "on" : "off",
            phase
        )
    }

    static func note(_ session: Session, endedWith phase: String) {
        guard !session.isEmpty else { return }
        let message = message(for: session, endedWith: phase)
        logger.notice("\(message, privacy: .public)")
    }

    // MARK: - Wheel events let through unsmoothed

    /// Why ScrollCore let a wheel event through unsmoothed.
    enum PassthroughReason: Int, CaseIterable {
        /// The event looks like a trackpad's (or a Magic Mouse's): never smoothed.
        case trackpad
        /// A remote desktop client sent it already smoothed.
        case remoteSmoothed
        /// Smoothing is off for this event: switched off, paused by a key, an app rule, the
        /// allowlist or Launchpad.
        case smoothingOff
        /// Smoothing is on, but not for this axis.
        case axisNotSmoothed
        /// Smoothing wanted, but there is no display link to post with.
        case noDisplayLink

        var text: String {
            switch self {
            case .trackpad: return "taken for trackpad events"
            case .remoteSmoothed: return "remote desktop, already smoothed"
            case .smoothingOff: return "smoothing is off for this event"
            case .axisNotSmoothed: return "smoothing is on, but not for this axis"
            case .noDisplayLink: return "no display link"
            }
        }
    }

    /// At most one line per reason in this many seconds.
    static let passthroughInterval: CFTimeInterval = 3

    private static var lastPassthroughNote = [CFTimeInterval](repeating: -.infinity, count: PassthroughReason.allCases.count)
    private static var passthroughCounts = [Int](repeating: 0, count: PassthroughReason.allCases.count)

#if DEBUG
    /// Tests: sees every passthrough, logged or not.
    static var passthroughObserverForTests: ((PassthroughReason) -> Void)?
#endif

    /// Main thread (the scroll tap callback), once per event let through: allocates nothing
    /// unless a line is written. `detail` is only evaluated for a line that is written.
    /// - Returns: the line written, or nil while the reason is quiet.
    @discardableResult
    static func notePassthrough(
        _ reason: PassthroughReason,
        now: CFTimeInterval = CFAbsoluteTimeGetCurrent(),
        detail: () -> String = { "" }
    ) -> String? {
#if DEBUG
        passthroughObserverForTests?(reason)
#endif
        let slot = reason.rawValue
        passthroughCounts[slot] += 1
        guard now - lastPassthroughNote[slot] >= passthroughInterval else { return nil }
        lastPassthroughNote[slot] = now
        let count = passthroughCounts[slot]
        passthroughCounts[slot] = 0
        let extra = detail()
        let line = "wheel events let through unsmoothed (\(count)): \(reason.text)\(extra.isEmpty ? "" : " (\(extra))")"
        logger.notice("\(line, privacy: .public)")
        return line
    }

#if DEBUG
    static func resetPassthroughForTests() {
        lastPassthroughNote = [CFTimeInterval](repeating: -.infinity, count: PassthroughReason.allCases.count)
        passthroughCounts = [Int](repeating: 0, count: PassthroughReason.allCases.count)
    }
#endif

    // MARK: - Hand-overs between the trackpad and the wheel (ScrollHandover)

    /// Written when the glide the wheel took over has ended: one line per hand-over.
    static func wheelTookOverMessage(droppedMomentumEvents: Int) -> String {
        return "handover: the wheel took over a trackpad glide: \(droppedMomentumEvents) momentum events dropped"
    }

    static let fingerTookOverMessage = "handover: a finger on the trackpad took over: the wheel's glide stopped"

    static func noteWheelTookOverGlide(droppedMomentumEvents: Int) {
        let line = wheelTookOverMessage(droppedMomentumEvents: droppedMomentumEvents)
        logger.notice("\(line, privacy: .public)")
    }

    static func noteFingerTookOverWheelGlide() {
        logger.notice("\(fingerTookOverMessage, privacy: .public)")
    }

    // MARK: - The sideways wheel (ThumbWheelEngine)

    /// What one roll of the sideways wheel (the thumb wheel) added up to: from its first event
    /// until the wheel rested (`ThumbWheelTuning.rollRest`), or `ThumbWheelTuning.logInterval`
    /// of a longer roll. The deltas are those the events arrived with, before "Reverse wheel
    /// direction" and "Swap direction": the log is how we learn what a wheel sends.
    struct ThumbWheelRoll: Equatable {
        /// The settings of the roll's events (a change ends the roll).
        var function: ThumbWheelFunction
        var speed: Double
        var swapsDirection: Bool
        var startedAt: TimeInterval
        var lastEventAt: TimeInterval
        var events = 0
        var continuousEvents = 0
        /// Sums of the integer line delta, the fixed-point line delta and the point delta.
        var lines: Int64 = 0
        var fixed = 0.0
        var points = 0.0
        /// The largest |point delta| of one event.
        var largestPoints = 0.0
        /// Steps that ran (each one action).
        var steps = 0

        init(settings: ThumbWheelSettings, at now: TimeInterval) {
            function = settings.function
            speed = settings.speed
            swapsDirection = settings.swapsDirection
            startedAt = now
            lastEventAt = now
        }

        mutating func add(_ event: ThumbWheelEvent, steps: Int, at now: TimeInterval) {
            events += 1
            if event.isContinuous { continuousEvents += 1 }
            lines = lines &+ event.lineDelta
            if event.fixedDelta.isFinite { fixed += event.fixedDelta }
            if event.pointDelta.isFinite {
                points += event.pointDelta
                largestPoints = max(largestPoints, event.pointDelta.magnitude)
            }
            self.steps += abs(steps)
            lastEventAt = now
        }

        /// The wheel has rested since the last event: the roll is over.
        func hasRested(at now: TimeInterval) -> Bool {
            return now >= lastEventAt + ThumbWheelTuning.rollRest
        }

        /// When its line is due: once the wheel rested, or once the roll has gone on for
        /// `logInterval`, whichever comes first.
        var lineDueAt: TimeInterval {
            return min(lastEventAt + ThumbWheelTuning.rollRest, startedAt + ThumbWheelTuning.logInterval)
        }

        func matches(_ settings: ThumbWheelSettings) -> Bool {
            return function == settings.function && speed == settings.speed && swapsDirection == settings.swapsDirection
        }
    }

    /// One line per roll, for example
    /// `thumb wheel: 14 events in 620 ms, lines -9 (fixed -9.40, points -212, largest 31), not continuous, switch tabs x1.00: 3 steps`.
    static func thumbWheelMessage(for roll: ThumbWheelRoll) -> String {
        let continuity: String
        if roll.continuousEvents == 0 {
            continuity = "not continuous"
        } else if roll.continuousEvents == roll.events {
            continuity = "continuous"
        } else {
            continuity = "partly continuous (\(roll.continuousEvents) of \(roll.events))"
        }
        return String(
            format: "thumb wheel: %ld %@ in %.0f ms, lines %lld (fixed %.2f, points %.0f, largest %.0f), %@, %@ x%.2f%@: %ld %@",
            roll.events, roll.events == 1 ? "event" : "events",
            max(0, roll.lastEventAt - roll.startedAt) * 1000,
            roll.lines, roll.fixed, roll.points, roll.largestPoints,
            continuity,
            roll.function.logName, roll.speed, roll.swapsDirection ? " swapped" : "",
            roll.steps, roll.steps == 1 ? "step" : "steps"
        )
    }

    /// Main queue, never inside the tap callback.
    static func noteThumbWheelRoll(_ roll: ThumbWheelRoll) {
        guard roll.events > 0 else { return }
        let line = thumbWheelMessage(for: roll)
        logger.notice("\(line, privacy: .public)")
    }
}
