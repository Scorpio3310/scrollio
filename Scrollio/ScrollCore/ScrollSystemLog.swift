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
        /// Trackpad-style as a flick (a short touch and its glide, for apps that scroll by the
        /// glide's events) instead of one touch for as long as the wheel turns.
        var flick = false
        /// Trackpad-style as one touch until the scroll has run out (apps that are not
        /// Chromium-based). With `trackpadStyle` and neither this nor `flick`: the old long
        /// touch of the evaluation switch (`TrackpadStyleEvaluation`).
        var oneTouch = false
        /// The switch is on, but the app under the pointer gets no trackpad-style events (Safari).
        var trackpadStyleWithheld = false
        /// How many touches ("began") the scroll was sent as, and how many of its wheel events
        /// went on with a glide instead of beginning a touch (a flick only).
        var touches = 0
        var glideInputs = 0

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

    /// Why a scroll ended, for its line.
    enum EndReason: String {
        /// Its glide ran out (the display link asked for the stop).
        case glidedOut = "glided out"
        case leftClick = "left click"
        case fingerOnTrackpad = "a finger on the trackpad"
        /// The next wheel event went to another app.
        case anotherApp = "the wheel went on in another app"
        /// "Trackpad-style scrolling" (or the app's own setting) was switched on or off while
        /// the scroll ran: it was closed in the form it was sent in.
        case settingChanged = "trackpad-style was switched"
        /// macOS turned the scroll tap off, or the tap was restarted.
        case tapRestarted = "the scroll tap was restarted"
        /// The keeper ended it (`ScrollPoster.healthCheck`; the `app` log says why).
        case keeper = "ended by the keeper"
        /// Scrollio stopped handling scrolling: Pause, sleep, another user, quit.
        case stopped = "stopped"
    }

    static func message(for session: Session, ended reason: EndReason) -> String {
        let tau = ScrollMotion.timeConstant(forTransition: session.transition)
        let trackpadStyle: String
        if !session.trackpadStyle {
            trackpadStyle = session.trackpadStyleWithheld ? "off (not sent to this app)" : "off"
        } else if session.flick {
            trackpadStyle = "on (flick: \(session.touches) touches, \(session.glideInputs) wheel events into a glide)"
        } else if session.oneTouch {
            trackpadStyle = "on (one touch: \(session.touches) touches)"
        } else {
            trackpadStyle = "on (long touch: \(session.touches) touches)"
        }
        return String(
            format: "scroll: %d wheel events %.0f px in -> %d frames %.0f px out (largest %.0f), wheel %.0f ms, glide after the last event %.0f ms, Duration %.2f (tau %.0f ms), trackpad-style %@, ended: %@",
            session.inputs, session.inputDistance, session.frames, session.postedDistance, session.largestFrame,
            (session.lastInputAt - session.startedAt) * 1000,
            max(0, session.lastFrameAt - session.lastInputAt) * 1000,
            session.duration, tau * 1000,
            trackpadStyle,
            reason.rawValue
        )
    }

#if DEBUG
    /// Tests: sees every finished scroll and why it ended.
    static var sessionObserverForTests: ((Session, EndReason) -> Void)?
#endif

    static func note(_ session: Session, ended reason: EndReason) {
        guard !session.isEmpty else { return }
#if DEBUG
        sessionObserverForTests?(session, reason)
#endif
        let message = message(for: session, ended: reason)
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
        /// Smoothing wanted, but no display link runs to post with (the display is off).
        case noDisplayLink
        /// Smoothing wanted, but Step or Speed is no finite number (a hand-edited setting).
        case unusableSettings

        var text: String {
            switch self {
            case .trackpad: return "taken for trackpad events"
            case .remoteSmoothed: return "remote desktop, already smoothed"
            case .smoothingOff: return "smoothing is off for this event"
            case .axisNotSmoothed: return "smoothing is on, but not for this axis"
            case .noDisplayLink: return "no display link"
            case .unusableSettings: return "Step or Speed is not a finite number"
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
        now: CFTimeInterval = ScrollPoster.monotonicNow(),
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
    /// until the wheel rested (`ThumbWheelTuning.logRollRest`), or `ThumbWheelTuning.logInterval`
    /// of a longer roll. Times are the events' own. The deltas are those the events arrived
    /// with, before "Reverse wheel direction" and "Swap direction": the log is how we learn
    /// what a wheel sends, and what the tuning numbers are read from.
    struct ThumbWheelRoll: Equatable {
        /// Tells the rolls apart (the steps of a roll run after its events were counted).
        var id: Int
        /// The settings of the roll's events (a change ends the roll).
        var function: ThumbWheelFunction
        var speed: Double
        var swapsDirection: Bool
        /// The events' own times of the first and the last event (the line's duration, gaps).
        var startedAt: TimeInterval
        var lastEventAt: TimeInterval
        /// When the callback saw the first and the last event, on the engine's clock: the look
        /// at the roll compares these with the same clock, whatever base the events' times have.
        var firstSeenAt: TimeInterval
        var lastSeenAt: TimeInterval
        var events = 0
        var continuousEvents = 0
        /// Sums of the integer line delta, the fixed-point line delta and the point delta.
        var lines: Int64 = 0
        var fixed = 0.0
        var points = 0.0
        /// The largest |fixed-point delta| and |point delta| of one event.
        var largestFixed = 0.0
        var largestPoints = 0.0
        /// The longest time between two events of the roll (s).
        var longestGap: TimeInterval = 0
        /// The stepper's travel, in units after acceleration and speed, either direction
        /// (0 while the wheel scrolls).
        var travel = 0.0
        /// How often the wheel turned the other way (the sums cancel out then).
        var directionChanges = 0
        /// The sign of the last event that moved (−1, 0 before any, +1).
        var lastDirection = 0
        /// Steps that ran, toward "next" and toward "previous".
        var stepsNext = 0
        var stepsPrevious = 0
        /// Steps the pacer dropped (too many waiting, or waiting in the old direction when the
        /// wheel turned back, or when the roll or the function ended).
        var droppedSteps = 0
        /// Steps decided but not run yet (on the main queue, or waiting in the pacer). Not in
        /// the line: a step that never runs (dropped by a stop) is not counted.
        var pendingSteps = 0

        init(id: Int, settings: ThumbWheelSettings, at time: TimeInterval, seenAt: TimeInterval? = nil) {
            self.id = id
            function = settings.function
            speed = settings.speed
            swapsDirection = settings.swapsDirection
            startedAt = time
            lastEventAt = time
            firstSeenAt = seenAt ?? time
            lastSeenAt = seenAt ?? time
        }

        /// - Parameters:
        ///   - travel: the event's travel in units (signed or not); `time`: its own time;
        ///     `seenAt`: the clock when the callback saw it.
        mutating func add(_ event: ThumbWheelEvent, travel: Double = 0, at time: TimeInterval, seenAt: TimeInterval? = nil) {
            if events > 0 { longestGap = max(longestGap, time - lastEventAt) }
            events += 1
            if travel.isFinite { self.travel += travel.magnitude }
            if event.isContinuous { continuousEvents += 1 }
            lines = lines &+ event.lineDelta
            if event.fixedDelta.isFinite {
                fixed += event.fixedDelta
                largestFixed = max(largestFixed, event.fixedDelta.magnitude)
            }
            if event.pointDelta.isFinite {
                points += event.pointDelta
                largestPoints = max(largestPoints, event.pointDelta.magnitude)
            }
            let travel = ThumbWheelStepper.lines(lineDelta: event.lineDelta, fixedDelta: event.fixedDelta, pointDelta: event.pointDelta)
            let direction = travel > 0 ? 1 : (travel < 0 ? -1 : 0)
            if direction != 0 {
                if lastDirection != 0 && direction != lastDirection { directionChanges += 1 }
                lastDirection = direction
            }
            lastEventAt = time
            lastSeenAt = seenAt ?? time
        }

        /// Steps ran (positive toward "next").
        mutating func stepsRan(_ steps: Int) {
            pendingSteps = max(0, pendingSteps - abs(steps))
            if steps > 0 { stepsNext += steps } else { stepsPrevious -= steps }
        }

        /// Steps the pacer dropped; they were pending.
        mutating func stepsDropped(_ count: Int) {
            guard count > 0 else { return }
            pendingSteps = max(0, pendingSteps - count)
            droppedSteps += count
        }

        /// The wheel has rested before an event at `time` (its own time): the roll is over.
        func hasRested(at time: TimeInterval) -> Bool {
            return time >= lastEventAt + ThumbWheelTuning.logRollRest
        }

        /// When its line is due, on the engine's clock: once no event came for a rest, or once
        /// the roll has gone on for `logInterval`, whichever comes first.
        var lineDueAt: TimeInterval {
            return min(lastSeenAt + ThumbWheelTuning.logRollRest, firstSeenAt + ThumbWheelTuning.logInterval)
        }

        func matches(_ settings: ThumbWheelSettings) -> Bool {
            return function == settings.function && speed == settings.speed && swapsDirection == settings.swapsDirection
        }
    }

    /// One line per roll, for example
    /// `thumb wheel: 14 events in 620 ms (longest gap 85 ms), lines -9, fixed -9.40 (largest 1.25), points -212 (largest 31), 1 direction change, not continuous, volume x3.00, travel 56.8: 7 steps next, 15 dropped`
    /// ("dropped": steps the pacer did not run; only when there are any).
    static func thumbWheelMessage(for roll: ThumbWheelRoll) -> String {
        let continuity: String
        if roll.continuousEvents == 0 {
            continuity = "not continuous"
        } else if roll.continuousEvents == roll.events {
            continuity = "continuous"
        } else {
            continuity = "partly continuous (\(roll.continuousEvents) of \(roll.events))"
        }
        let steps: String
        switch (roll.stepsNext, roll.stepsPrevious) {
        case (0, 0):
            steps = "0 steps"
        case (let next, 0):
            steps = "\(next) \(next == 1 ? "step" : "steps") next"
        case (0, let previous):
            steps = "\(previous) \(previous == 1 ? "step" : "steps") previous"
        case (let next, let previous):
            steps = "\(next) \(next == 1 ? "step" : "steps") next, \(previous) previous"
        }
        let dropped = roll.droppedSteps > 0 ? ", \(roll.droppedSteps) dropped" : ""
        return String(
            format: "thumb wheel: %ld %@ in %.0f ms (longest gap %.0f ms), lines %lld, fixed %.2f (largest %.2f), points %.0f (largest %.0f), %ld %@, %@, %@ x%.2f%@, travel %.1f: %@",
            roll.events, roll.events == 1 ? "event" : "events",
            max(0, roll.lastEventAt - roll.startedAt) * 1000,
            max(0, roll.longestGap) * 1000,
            roll.lines, roll.fixed, roll.largestFixed, roll.points, roll.largestPoints,
            roll.directionChanges, roll.directionChanges == 1 ? "direction change" : "direction changes",
            continuity,
            roll.function.logName, roll.speed, roll.swapsDirection ? " swapped" : "",
            roll.travel,
            steps + dropped
        )
    }

    /// Main queue, never inside the tap callback.
    static func noteThumbWheelRoll(_ roll: ThumbWheelRoll) {
        guard roll.events > 0 else { return }
        let line = thumbWheelMessage(for: roll)
        logger.notice("\(line, privacy: .public)")
    }
}
