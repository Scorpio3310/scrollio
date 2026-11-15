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
//  (thumb) wheel, with what it sent and what it ran, and for now a trace line next to it
//  for a roll that runs a function (each event's gap and lines; in every build until the
//  wheel is tuned: cut it, or keep it to DEBUG, before the next release). Tests pass on a
//  simulated wheel; this is how to see what happened on the real one.
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
        /// glide's events) instead of one touch until the scroll has run out.
        var flick = false
        /// Trackpad-style as one touch until the scroll has run out (apps that are not
        /// Chromium-based). With `trackpadStyle` and neither this nor `flick`: the old long
        /// touch of the evaluation switch (`TrackpadStyleEvaluation`).
        var oneTouch = false
        /// The switch is on, but the app under the pointer gets no trackpad-style events (Safari).
        var trackpadStyleWithheld = false
        /// The switch is on, but the scroll is mainly sideways and carries no phases.
        var trackpadStyleSideways = false
        /// One touch: what the end watch met and did (`ScrollEndWatch.swift`).
        var endWatch = ScrollEndWatchLog()
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
        /// With "Trackpad-style scrolling": the wheel turned from up-down to sideways or back
        /// (another wheel, Shift, the "scroll sideways" key) while the scroll ran. A sideways
        /// scroll carries no phases, so the running one was closed first.
        case axisChanged = "the wheel turned between up-down and sideways"
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
            if session.trackpadStyleSideways {
                trackpadStyle = "off (a sideways scroll)"
            } else {
                trackpadStyle = session.trackpadStyleWithheld ? "off (not sent to this app)" : "off"
            }
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
        // One touch: a second line with what the end watch met (roles and numbers only).
        if let line = session.endWatch.line {
            logger.notice("\(line, privacy: .public)")
        }
    }

    /// One touch: a hold at a page's end is over. One line with how many wheel events it
    /// took in (nothing was sent for them).
    static func notePageEnd(taken: Int) {
#if DEBUG
        pageEndObserverForTests?(taken)
#endif
        logger.notice("scroll end watch: took in \(taken, privacy: .public) wheel events at the page's end")
    }
#if DEBUG
    static var pageEndObserverForTests: ((Int) -> Void)?
#endif

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
    /// with, before "Reverse wheel direction" and the thumb wheel's "Reverse direction": the log is how we learn
    /// what a wheel sends, and what the tuning numbers are read from.
    struct ThumbWheelRoll: Equatable {
        /// Tells the rolls apart (the steps of a roll run after its events were counted).
        var id: Int
        /// The settings of the roll's events (a change ends the roll).
        var function: ThumbWheelFunction
        var speed: Double
        /// The function's "Reverse direction".
        var swapsDirection: Bool
        /// Switch Desktops follows the wheel (`ThumbWheelSettings.followsWheelNow`): the roll
        /// drove swipes, not steps.
        var follows = false
        /// The settings are the app in front's own (its function, or its speed and swap:
        /// `ThumbWheelTurn`); the line never names the app.
        var isAppsOwn = false
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
        /// Steps that ran, toward "next" and toward "previous", and how many of them waited
        /// in the pacer first.
        var stepsNext = 0
        var stepsPrevious = 0
        var stepsWaited = 0
        /// Steps the pacer dropped (too many waiting, or waiting in the old direction when the
        /// wheel turned back, or when the roll or the function ended).
        var droppedSteps = 0
        /// Steps decided but not run yet (on the main queue, or waiting in the pacer). Not in
        /// the line: a step that never runs (dropped by a stop) is not counted.
        var pendingSteps = 0
        /// The stray-tick filter (`ThumbWheelTickFilter`): events it held, and held events it
        /// dropped (the other way came, or they grew older than its window).
        var ticksHeld = 0
        var ticksDropped = 0
        /// Follow the wheel: its swipes in order (the first `listedSwipes`), how all of them
        /// ended and of those past the list, the furthest one went (a share of one desktop),
        /// the strokes that waited for another swipe all along, and the strokes and swipes not
        /// ended yet (the line waits for them, as for steps; a swipe ends once its Space
        /// changed or the time for that passed).
        var swipes: [ThumbWheelFollower.Swipe] = []
        var swipeTally = SwipeTally()
        var unlistedSwipes = SwipeTally()
        var furthestSwipe = 0.0
        var strokesWaited = 0
        var pendingSwipes = 0

        /// Swipes listed one by one in the line; the others are summed.
        static let listedSwipes = 8

        /// How many swipes ended each way.
        struct SwipeTally: Equatable {
            var chained = 0
            var fullStop = 0
            var ended = 0
            var back = 0
            var interrupted = 0

            var total: Int { return chained + fullStop + ended + back + interrupted }

            mutating func count(_ ending: ThumbWheelFollower.Ending) {
                switch ending {
                case .chained: chained += 1
                case .fullStop: fullStop += 1
                case .ended: ended += 1
                case .back: back += 1
                case .interrupted: interrupted += 1
                }
            }
        }

        init(id: Int, settings: ThumbWheelSettings, at time: TimeInterval, seenAt: TimeInterval? = nil) {
            self.id = id
            function = settings.function
            speed = settings.speed
            swapsDirection = settings.swapsDirection
            follows = settings.followsWheelNow
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

        /// What the stray-tick filter made of one of the roll's events.
        mutating func ticksFiltered(_ tick: ThumbWheelTickFilter.Result) {
            if tick.held { ticksHeld += 1 }
            ticksDropped += tick.dropped
        }

        /// Steps ran (positive toward "next"); `waited`: in the pacer.
        mutating func stepsRan(_ steps: Int, waited: Bool = false) {
            pendingSteps = max(0, pendingSteps - abs(steps))
            if waited { stepsWaited += abs(steps) }
            if steps > 0 { stepsNext += steps } else { stepsPrevious -= steps }
        }

        /// A stroke of Follow the wheel ended (it was pending).
        mutating func strokeEnded(waited: Bool) {
            pendingSwipes = max(0, pendingSwipes - 1)
            if waited { strokesWaited += 1 }
        }

        /// A swipe's ending is final (it was pending). Main queue: the list grows here, never
        /// in the tap callback.
        mutating func swipeEnded(_ swipe: ThumbWheelFollower.Swipe) {
            pendingSwipes = max(0, pendingSwipes - 1)
            swipeTally.count(swipe.ending)
            if swipes.count < Self.listedSwipes {
                swipes.append(swipe)
            } else {
                unlistedSwipes.count(swipe.ending)
            }
            if swipe.furthest.isFinite { furthestSwipe = max(furthestSwipe, swipe.furthest) }
        }

        /// Steps or swipes are still to come: the line waits for them.
        var isWaiting: Bool {
            return pendingSteps > 0 || pendingSwipes > 0
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
                && follows == settings.followsWheelNow
        }
    }

    /// One line per roll, for example
    /// `thumb wheel: 14 events in 620 ms (longest gap 85 ms), lines -9, fixed -9.40 (largest 1.25), points -212 (largest 31), 1 direction change, not continuous, volume x3.00, travel 56.8: 7 steps next, 6 waited, 15 dropped; ticks held 1, dropped 1`
    /// ("waited": steps the pacer held back, then ran; "dropped": steps it did not run; each
    /// only when there are any; "volume (the app's own) x3.00" when the function was the app
    /// in front's own; "ticks": what the stray-tick filter held, and dropped, of a roll that
    /// runs a function). While Switch Desktops follows the wheel the end lists the swipes
    /// instead of steps (`followMessage`), for example
    /// `switch desktops, following x0.70, travel 29.4: swipes 1.00 chained +240 ms, 0.62 ended no change; ticks held 0, dropped 0`.
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
        let waited = roll.stepsWaited > 0 ? ", \(roll.stepsWaited) waited" : ""
        let dropped = roll.droppedSteps > 0 ? ", \(roll.droppedSteps) dropped" : ""
        let ticks = roll.function == .scroll ? "" : "; ticks held \(roll.ticksHeld), dropped \(roll.ticksDropped)"
        let outcome = (roll.follows ? followMessage(for: roll) : steps + waited + dropped) + ticks
        return String(
            format: "thumb wheel: %ld %@ in %.0f ms (longest gap %.0f ms), lines %lld, fixed %.2f (largest %.2f), points %.0f (largest %.0f), %ld %@, %@, %@ x%.2f%@, travel %.1f: %@",
            roll.events, roll.events == 1 ? "event" : "events",
            max(0, roll.lastEventAt - roll.startedAt) * 1000,
            max(0, roll.longestGap) * 1000,
            roll.lines, roll.fixed, roll.largestFixed, roll.points, roll.largestPoints,
            roll.directionChanges, roll.directionChanges == 1 ? "direction change" : "direction changes",
            continuity,
            (roll.isAppsOwn ? roll.function.logName + " (the app's own)" : roll.function.logName)
                + (roll.follows ? ", following" : ""),
            roll.speed, roll.swapsDirection ? " swapped" : "",
            roll.travel,
            outcome
        )
    }

    /// What the swipes of a roll that followed the wheel did, each in order: how far it went
    /// (a share of one desktop), how it ended, and for an end where a switch was expected the
    /// time to the Space change ("late" when it came after the gate's timeout), or "no
    /// change"; past `ThumbWheelRoll.listedSwipes` they are
    /// summed. For example `swipes 1.00 chained +240 ms, 0.62 ended no change`, `swipes 0.12
    /// back`, `+3 more (2 chained, 1 full stop)`, `1 stroke waited for another swipe`.
    static func followMessage(for roll: ThumbWheelRoll) -> String {
        var parts: [String] = []
        if !roll.swipes.isEmpty {
            parts.append("swipes " + roll.swipes.map(swipeMessage).joined(separator: ", "))
        }
        if roll.unlistedSwipes.total > 0 {
            parts.append("+\(roll.unlistedSwipes.total) more (\(tallyMessage(roll.unlistedSwipes)))")
        }
        if roll.strokesWaited > 0 {
            parts.append("\(roll.strokesWaited) \(roll.strokesWaited == 1 ? "stroke" : "strokes") waited for another swipe")
        }
        if parts.isEmpty { parts.append("no swipe") }
        return parts.joined(separator: ", ")
    }

    static func swipeMessage(_ swipe: ThumbWheelFollower.Swipe) -> String {
        var text = String(format: "%.2f ", swipe.furthest) + swipe.ending.logName
        if swipe.expectsSwitch {
            if let after = swipe.spaceChangedAfter {
                text += String(format: swipe.late ? " late +%.0f ms" : " +%.0f ms", after * 1000)
            } else {
                text += " no change"
            }
        }
        return text
    }

    private static func tallyMessage(_ tally: ThumbWheelRoll.SwipeTally) -> String {
        let kinds: [(Int, ThumbWheelFollower.Ending)] = [
            (tally.chained, .chained), (tally.fullStop, .fullStop), (tally.ended, .ended),
            (tally.back, .back), (tally.interrupted, .interrupted),
        ]
        return kinds.filter { $0.0 > 0 }.map { "\($0.0) \($0.1.logName)" }.joined(separator: ", ")
    }

    /// One event of a roll's trace: the time since the roll's event before it (s; 0 for the
    /// first) and its fixed-point line delta as it arrived.
    struct ThumbWheelTraceEntry: Equatable {
        var gap: TimeInterval
        var fixed: Double
    }

    /// A function roll's trace, one line next to its roll line, to tune the wheel from: each
    /// event as `ms since the one before/fixed-point lines`, the first
    /// `ThumbWheelTuning.traceEntries` of them, for example
    /// `thumb wheel trace: 3 events, ms/fixed 0/-0.10 94/-0.35 101/-1.00`, or
    /// `thumb wheel trace: 150 events (the first 128), ms/fixed ...`. Never names an app.
    static func thumbWheelTraceMessage<Entries: Collection>(entries: Entries, events: Int) -> String
    where Entries.Element == ThumbWheelTraceEntry {
        let shown = entries.prefix(ThumbWheelTuning.traceEntries)
        let count = events > shown.count ? " (the first \(shown.count))" : ""
        let list = shown.map { entry in
            let gap = entry.gap.isFinite ? max(0, entry.gap) * 1000 : 0
            let fixed = entry.fixed.isFinite ? entry.fixed : 0
            return String(format: "%.0f/%.2f", gap, fixed)
        }
        return "thumb wheel trace: \(events) \(events == 1 ? "event" : "events")\(count), ms/fixed " + list.joined(separator: " ")
    }

    /// Main queue, never inside the tap callback.
    static func noteThumbWheelTrace(_ line: String) {
        logger.notice("\(line, privacy: .public)")
    }

    /// Main queue, never inside the tap callback.
    static func noteThumbWheelRoll(_ roll: ThumbWheelRoll) {
        guard roll.events > 0 else { return }
        let line = thumbWheelMessage(for: roll)
        logger.notice("\(line, privacy: .public)")
    }
}
