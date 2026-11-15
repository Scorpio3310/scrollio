//
//  ThumbWheelFollower.swift
//  Scrollio
//
//  Switch Desktops with "Follow the wheel" (`ThumbWheelSettings.followsWheel`): the desktops
//  slide with the thumb wheel like a trackpad swipe, as Gestures' "Follow the hand" makes
//  them slide with the hand, and settle when the wheel rests. One long roll moves several
//  desktops, as quick trackpad swipes chain.
//
//  A stroke is the wheel's events until it rests for `ThumbWheelTuning.followRest` (a tick
//  the stray-tick filter holds is no event of the stroke, but the wheel moved: the rest
//  counts from it, `touch`). Its first event begins a dock swipe (`DockSwipeSynthesizer`),
//  each event moves it on in the turn's direction (one event is one unit, up to two on a
//  fast turn, × the speed; `followUnitsPerSpace` units are one Space). The swipe itself is
//  the one "Follow the hand" runs (`InteractiveGestureSession`, fed with the wheel's units
//  in place of points): at most one Space either way. A swipe ends in one of three ways:
//  - At a full Space (`followFullShare`) with the wheel still turning that way: once the
//    travel past that point reaches `followChainOverflowUnits`, it ends, at the full Space
//    with no speed ("chained"), so the next desktop can come in this stroke; not sooner
//    than `followFullStopRest` after its begin, so a swipe begun at a full Space (travel
//    kept at the gate, one hard event) is shown sliding, never begun and ended at once.
//  - At a full Space with the wheel still for `followFullStopRest`: it ends then ("full
//    stop"), not only at the rest. A swipe begun after the wheel stopped (with travel kept
//    at the gate) counts that time from its begin, and the rest does not end it sooner
//    either: it is shown sliding before it ends, never begun and ended at once.
//  - At the rest, by the rule of "Follow the hand" (`InteractiveGestureSession.release`):
//    back at the start it is cancelled, else ended, and macOS settles it on the next
//    desktop or back by where it stands (the hand's speed is nothing then: a wheel has no
//    lift-off), so half a desktop or more switches.
//
//  The gate: after an end at half a Space or more (a switch is expected), no swipe begins,
//  in this stroke or a new one, until macOS says the Space changed
//  (`NSWorkspace.activeSpaceDidChangeNotification`, `spaceDidChange`) or the timeout
//  passed (`followSpaceChangeTimeout`; `followSettleSpaceChangeTimeout` after an end at the
//  rest, which macOS settles more slowly, and after an end within
//  `followAfterNoSwitchWindow` of a swipe that brought no switch, a bounce at the end of the
//  row or a slide back, which the Dock is still drawing: it tells the change late then): a
//  swipe begun while the last one settles can catch it and take it back. A stroke at the closed gate does not rest: its travel is kept
//  (`followGatePendingCap` at most) until the gate opens, by the Space change or the
//  timeout, and begins the next swipe then, whether the wheel still turns or not. Short of
//  half a Space it begins nothing, and neither does travel that comes once the gate is open
//  (macOS tells the change some 30 ms after a full end, so the tail of a roll comes then):
//  if the wheel stopped there, the swipe could only slide out and back, the next desktop
//  peeking in. After a gate the stroke's travel is kept until it makes half a Space and
//  begins the swipe then; the rest drops it. When no change came in time, the desktop was
//  the first or the last that way (the Dock let the swipe bounce back): the stroke the
//  swipe ended in begins no swipe that way again (travel the other way does) until it ends
//  or the Space changes after all, so the wheel never sends the Dock into a loop of
//  bounces; a later stroke is not barred, and the travel it kept at the gate begins its
//  swipe. A timed-out gate's swipe waits `followLateSpaceChangeWindow` more as a late
//  record, so a change that comes late is logged as such; a change while a gate is closed
//  is that gate's. The gate's memory outlives the stroke.
//
//  Where the work is done: the tap callback only adds an event's travel up (`add`, a few
//  sums and at most one closure per display frame; a rest or a timeout whose look has not
//  run yet is seen there, and what it ends is told to the roll's line afterwards, on the
//  main queue); the swipe begins, moves and ends on the
//  main queue, at most once per display frame, as a gesture's does (the Dock stutters when
//  swipe events come faster than it draws). The screen (its width does not matter here, the
//  number of Spaces does) is looked at when a swipe begins, on the main queue. The desktop
//  eases toward where the wheel put it (`followEasePerFrame`), so an event is a short slide.
//
//  One swipe at a time: a swipe begins only while none runs (a gesture hold that follows
//  the hand may be swiping): the stroke then waits for the rest and sends nothing. A
//  gesture that begins a swipe during a stroke takes the Dock over (the synthesizer cancels
//  the wheel's swipe); the stroke sees its swipe is not the one running and sends nothing
//  more. A stop (`cancel`) cancels the swipe at once.
//
//  Main thread only: the tap callback and the main queue.
//

import Cocoa

final class ThumbWheelFollower {

    /// How a swipe ended (the roll's log line lists them).
    enum Ending: Equatable {
        /// At a full Space, the wheel still turning that way: ended so the next can follow.
        case chained
        /// At a full Space, the wheel still for `followFullStopRest`.
        case fullStop
        /// At the rest, where it stood: macOS settled it (next desktop, or back).
        case ended
        /// Back at its start: cancelled.
        case back
        /// Another swipe took over, Scrollio stopped, the settings changed in the middle, or
        /// the swipe's own time limit.
        case interrupted
    }

    /// One swipe, for the roll's log line.
    struct Swipe: Equatable {
        /// The furthest it went (a share of one Space).
        var furthest: Double
        var ending: Ending
        /// It ended half a Space or more on: a switch was expected (the gate closed).
        var expectsSwitch = false
        /// Seconds from its end to the Space change; nil: none came in time (or none was
        /// expected).
        var spaceChangedAfter: TimeInterval?
        /// The change came after the gate's timeout, while the swipe waited as a late record.
        var late = false
        /// Scrollio stopped (`cancel`) while the swipe waited for its change.
        var stopped = false
    }

    /// What `add` did with an event.
    enum Taken: Equatable {
        /// Not taken: this system cannot make a swipe; the event runs as a step.
        case no
        /// Taken; `newStroke` when it began a stroke.
        case yes(newStroke: Bool)
    }

    /// The swipe the Dock follows, shared with the gesture holds.
    var synthesizer: DockSwipeSynthesizer = .shared
    /// The screen under the pointer when a swipe begins (on the main queue).
    var screen: () -> InteractiveGestureScreen = { InteractiveGestureEnvironment.system.screen() }
    /// Runs work on the main queue after a delay; seconds on a monotonic clock (the engine's).
    var schedule: (TimeInterval, @escaping () -> Void) -> Void = ThumbWheelEngine.scheduleOnMainQueue
    var clock: () -> TimeInterval = { CACurrentMediaTime() }
    /// The roll's line hears of strokes and swipes by the tag their events came with (the
    /// tag of a stroke's first event, of the event that began a swipe): each is pending
    /// until it ended. A stroke ended (and it waited for another swipe all along); a swipe
    /// began; a swipe's ending is final (with the gate: once the Space changed or the
    /// timeout passed).
    var onStrokeEnd: ((_ tag: Int, _ waited: Bool) -> Void)?
    var onSwipeBegin: ((_ tag: Int) -> Void)?
    var onSwipeEnd: ((_ tag: Int, Swipe) -> Void)?

    enum State: Equatable {
        case idle
        /// Another swipe ran: the stroke is swallowed until the wheel rests.
        case waiting
        case following
        /// The last swipe ended where a switch is expected: no swipe begins until the Space
        /// changed or the timeout passed; travel is kept for the next one.
        case gated
    }

    private(set) var state = State.idle
    /// A stroke is under way (following, gated, or waiting for its rest).
    var isInStroke: Bool { return state != .idle }
    /// An event can be taken: a stroke is under way, or a swipe can be made here (else the
    /// desktops go in steps).
    var canFollow: Bool { return state != .idle || synthesizer.isAvailable }

    /// The swipe under way; nil until it begins on the main queue.
    private var session: InteractiveGestureSession?
    /// The synthesizer's number of the swipe; 0 before it began.
    private var swipeNumber = 0
    /// Travel the main queue has not given the swipe yet (units, positive toward "next").
    private var pendingTravel = 0.0
    /// The events' own time of the stroke's last event.
    private var lastEventAt: TimeInterval = 0
    /// When the callback saw the last event, on `clock`.
    private var lastSeenAt: TimeInterval = 0
    /// When the wheel last moved in the stroke, on the same two clocks: its last event, or a
    /// tick the stray-tick filter has held since (`touch`). The stroke's rest counts from it.
    private var lastMovedAt: TimeInterval = 0
    private var lastMovedSeenAt: TimeInterval = 0
    /// Where the wheel has put the desktop, and where the Dock was told it is (progress).
    private var target = 0.0
    private var shown = 0.0
    private var progressPerSpace = 1.0
    private var furthest = 0.0
    /// When the swipe under way began, on `clock`.
    private var swipeBeganAt = -TimeInterval.infinity
    /// Travel the same way since the swipe reached a full Space (units).
    private var overflow = 0.0
    private var frameDuration = InteractiveGestureEnvironment.fallbackScreen.frameDuration
    private var lastFrameAt = -TimeInterval.infinity
    private var frameScheduled = false
    private var restScheduled = false
    /// Counts the rest's looks: only the one scheduled last looks (the gate's opening
    /// schedules one anew).
    private var restLook = 0
    private var fullStopScheduled = false
    /// Moves on with each stroke's end: work scheduled for an earlier stroke does nothing.
    private var generation = 0
    /// The tags of the stroke's first event, of its latest, and of the swipe under way.
    private var strokeTag = 0
    private var eventTag = 0
    private var swipeTag = 0
    /// The stroke found another swipe running and sent nothing for that reason.
    private var strokeWaited = false
    /// No swipe begins this way until the stroke ends or the Space changes (+1, −1; 0: none).
    private var blockedDirection = 0
    /// The stroke's next swipe comes after a gate (its last swipe ended at a full Space, or
    /// the stroke began at the closed gate): it begins only once the travel for it makes
    /// half a Space. Less is kept for the stroke's next events and dropped at the rest.
    private var nextSwipeNeedsHalfASpace = false

    /// The last end where a switch was expected, until the Space changed or the timeout
    /// passed: it outlives the stroke.
    private struct Gate {
        var number: Int
        /// On `clock`.
        var endedAt: TimeInterval
        /// How long it waits for the Space change (s).
        var timeout: TimeInterval
        /// The way the swipe went (+1 toward "next").
        var direction: Int
        var tag: Int
        var swipe: Swipe
        /// The stroke the swipe ended in (`generation` then): the only one a timeout bars.
        var stroke: Int
    }
    private var gate: Gate?
    private var gateCount = 0
    /// When the last swipe that brought no switch ended, on `clock`: its gate timed out with
    /// no Space change (it bounced at the end of the row), or it ended short of half a Space
    /// (it slides back). The Dock draws that for a while, and a swipe that ends meanwhile
    /// waits longer for its change (`closeGate`). A Space change forgets it.
    private var endedWithoutSwitchAt = -TimeInterval.infinity
    /// A gate that timed out, for `followLateSpaceChangeWindow` more: a change meanwhile is
    /// its swipe's, late, unless a newer gate is closed (then it is that gate's).
    private var lateRecord: Gate?
    /// Swipe endings of the late record's own roll, told after its, so the roll's line lists
    /// them in order.
    private var queuedEnds: [(tag: Int, swipe: Swipe)] = []
    /// `add` or `endStroke(at:)` runs (the tap callback): endings are told on the main queue.
    private var inTapCallback = false

    private let spaceChanges: NotificationCenter?
    private var spaceObserver: NSObjectProtocol?

    /// The notification center macOS tells a change of the Space in use on; none under
    /// XCTest (tests call `spaceDidChange` themselves).
    static var systemSpaceChanges: NotificationCenter? {
        return AppRuntime.isRunningXCTest ? nil : NSWorkspace.shared.notificationCenter
    }

    init(spaceChanges: NotificationCenter? = ThumbWheelFollower.systemSpaceChanges) {
        self.spaceChanges = spaceChanges
        queuedEnds.reserveCapacity(ScrollSystemLog.ThumbWheelRoll.listedSwipes)
        spaceObserver = spaceChanges?.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.spaceDidChange()
        }
    }

    deinit {
        if let spaceObserver { spaceChanges?.removeObserver(spaceObserver) }
    }

    // MARK: - The tap callback

    /// One event's travel toward "next" while following: one unit, up to two on a fast turn
    /// (as volume and zoom count), × the speed; turned around by the function's "Reverse
    /// direction" (`flipped`). A negative X delta (after the flip) is "next", the desktop
    /// on the right.
    static func travel(lineDelta: Int64, fixedDelta: Double, pointDelta: Double, flipped: Bool, speed: Double) -> Double {
        let x = ThumbWheelStepper.lines(lineDelta: lineDelta, fixedDelta: fixedDelta, pointDelta: pointDelta)
        let size = ThumbWheelStepper.units(lines: x, accelerates: true) * ThumbWheelSettings.clampedSpeed(speed)
        let towardNext = flipped ? x > 0 : x < 0
        return towardNext ? size : -size
    }

    /// One event of a turn that follows the wheel, in the tap callback.
    /// - Parameters:
    ///   - time: the event's own time; `seenAt`: `clock` when the callback saw it.
    ///   - tag: told back with what the stroke and its swipes did (the engine's roll).
    func add(_ travel: Double, at time: TimeInterval, seenAt: TimeInterval, tag: Int = 0) -> Taken {
        inTapCallback = true
        defer { inTapCallback = false }
        if let gate, clock() + 1e-9 >= gate.endedAt + gate.timeout {
            // The gate's look has not come yet (the main queue was busy): it timed out.
            gateTimedOut()
        }
        if hasRested(before: time) {
            // The rest's look has not come yet (the main queue was busy): the stroke ended.
            finishStroke(at: lastMovedAt + ThumbWheelTuning.followRest)
        }
        var newStroke = false
        if state == .idle {
            guard synthesizer.isAvailable else { return .no }
            newStroke = true
            beginStroke(tag: tag)
        }
        eventTag = tag
        lastEventAt = time
        lastSeenAt = seenAt
        lastMovedAt = time
        lastMovedSeenAt = seenAt
        if travel.isFinite, travel != 0 {
            switch state {
            case .following:
                pendingTravel += travel
                scheduleFrame()
            case .gated:
                let cap = ThumbWheelTuning.followGatePendingCap
                pendingTravel = min(cap, max(-cap, pendingTravel + travel))
            case .waiting, .idle:
                break
            }
        }
        scheduleRestLook()
        return .yes(newStroke: newStroke)
    }

    /// The stroke's rest passed before an event at `time` (its own time). At a closed gate a
    /// stroke has no rest of its own: it waits for the gate (`restDueAt`).
    private func hasRested(before time: TimeInterval) -> Bool {
        guard state != .idle, state != .gated else { return false }
        return time >= lastMovedAt + ThumbWheelTuning.followRest
    }

    /// A tick the stray-tick filter holds, in the tap callback (it reaches neither `add` nor
    /// the swipe): the wheel moves, so a stroke under way does not rest yet. Nothing else:
    /// no travel, no stroke begins with it, and the full stop of a swipe at a full Space is
    /// not put off.
    func touch(at time: TimeInterval, seenAt: TimeInterval) {
        guard state != .idle, !hasRested(before: time) else { return }
        lastMovedAt = time
        lastMovedSeenAt = seenAt
    }

    /// The turn no longer follows the wheel (its settings changed in the middle): the stroke
    /// ends now, by the same rule as at a rest. In the tap callback, as `add`.
    func endStroke(at time: TimeInterval) {
        guard state != .idle else { return }
        inTapCallback = true
        defer { inTapCallback = false }
        finishStroke(at: max(time, lastMovedAt))
    }

    /// Scrollio stopped handling the wheel: the swipe is cancelled at once (the main queue
    /// may not run again before the stop is over), the gate forgotten, nothing scheduled runs.
    func cancel() {
        endedWithoutSwitchAt = -TimeInterval.infinity
        if var record = lateRecord {
            lateRecord = nil
            record.swipe.stopped = true
            tellLate(record)
        }
        if var gate {
            self.gate = nil
            gate.swipe.stopped = true
            tell(gate.tag, gate.swipe)
        }
        guard state != .idle else { return }
        if swipeNumber != 0, synthesizer.isRunning(swipeNumber) {
            synthesizer.cancel()
        }
        reportSwipe(.interrupted)
        endStroke()
    }

    /// macOS changed the Space in use (main queue). The gate opens: a stroke that waited at
    /// it begins its next swipe with the travel it kept, unless another swipe runs.
    func spaceDidChange() {
        // Where the stroke found the first or the last desktop no longer holds: both ways
        // begin again. The Dock switched: it draws no bounce or slide back any more.
        blockedDirection = 0
        endedWithoutSwitchAt = -TimeInterval.infinity
        let now = clock()
        // A change is the closed gate's, however soon after its end (macOS can tell one
        // within 80 ms), and a late record waits on. Only with no gate closed is it the late
        // record's.
        if gate == nil, var record = lateRecord {
            lateRecord = nil
            record.swipe.spaceChangedAfter = max(0, now - record.endedAt)
            record.swipe.late = true
            tellLate(record)
            return
        }
        guard var gate else { return }
        self.gate = nil
        gate.swipe.spaceChangedAfter = max(0, now - gate.endedAt)
        tell(gate.tag, gate.swipe)
        if state == .gated { openGateForTheStroke() }
    }

    // MARK: - The main queue

    private func scheduleFrame() {
        guard !frameScheduled else { return }
        frameScheduled = true
        let generation = self.generation
        // The first movement after a pause goes out on the next main-queue turn; while the
        // wheel keeps turning, frames are one display frame apart.
        let delay = max(0, lastFrameAt + frameDuration - clock())
        schedule(delay) { [weak self] in
            guard let self, self.generation == generation else { return }
            self.frameScheduled = false
            self.frame()
        }
    }

    /// One display frame of the stroke: the travel so far goes to the swipe, the desktop
    /// eases toward where it should stand, and a swipe at a full Space with the wheel still
    /// turning that way ends, once it was shown for `followFullStopRest`.
    private func frame() {
        guard state == .following else { return }
        lastFrameAt = clock()
        guard takeTravel() else { return }
        if swipeNumber != 0, shown != target {
            let share = 1 - pow(1 - ThumbWheelTuning.followEasePerFrame, frameDuration * 60)
            let next = shown + (target - shown) * share
            shown = abs(target - next) < ThumbWheelTuning.followEaseSnap ? target : next
            synthesizer.update(progress: shown)
        }
        if swipeNumber != 0, isAtFullSpace {
            // Not sooner than `followFullStopRest` after its begin: a swipe begun at or near a
            // full Space (travel kept at the gate, one hard event) is shown sliding first. A
            // wheel that stops meanwhile is the full stop's look.
            if overflow + ThumbWheelTuning.thresholdSlack >= ThumbWheelTuning.followChainOverflowUnits,
               clock() + 1e-9 >= swipeBeganAt + ThumbWheelTuning.followFullStopRest {
                endAtFullSpace(.chained)
                return
            }
            scheduleFullStopLook()
        }
        // (Travel kept for a swipe that has not begun waits for the next event's frame.)
        if swipeNumber != 0, shown != target || pendingTravel != 0 {
            scheduleFrame()
        }
    }

    private var isAtFullSpace: Bool {
        return abs(target) + ThumbWheelTuning.thresholdSlack >= ThumbWheelTuning.followFullShare * progressPerSpace
    }

    /// Gives the swipe the travel that came since the last frame, beginning a swipe when
    /// none runs; false when the stroke stopped following (another swipe runs, or took over).
    private func takeTravel() -> Bool {
        if session == nil {
            guard pendingTravel != 0 else { return true }
            if blockedDirection != 0, (pendingTravel > 0) == (blockedDirection > 0) {
                // No Space came after the last swipe this way: none begins that way again
                // in this stroke.
                pendingTravel = 0
                return true
            }
            // Another swipe began since the event was taken: this stroke waits.
            guard !synthesizer.isActive else {
                state = .waiting
                strokeWaited = true
                pendingTravel = 0
                return false
            }
            if nextSwipeNeedsHalfASpace, abs(pendingTravel) + ThumbWheelTuning.thresholdSlack
                < InteractiveGestureSession.switchProgressShare * ThumbWheelTuning.followUnitsPerSpace {
                // After a gate, travel short of half a Space begins nothing: if the wheel
                // stops there (the tail of a roll), the swipe could only slide out and back.
                return true
            }
            nextSwipeNeedsHalfASpace = false
            let screen = self.screen()
            frameDuration = screen.frameDuration > 0 ? screen.frameDuration : InteractiveGestureEnvironment.fallbackScreen.frameDuration
            progressPerSpace = DockSwipeGeometry.progressPerSpace(spaceCount: screen.spaceCount)
            session = InteractiveGestureSession(
                configuration: InteractiveGestureSession.Configuration(
                    progressPerPoint: progressPerSpace / ThumbWheelTuning.followUnitsPerSpace,
                    maximumProgress: progressPerSpace,
                    // A unit toward "next" moves toward the next Space.
                    invertHorizontal: true,
                    // The first event is the swipe's: no travel is spent on arming.
                    lockDistance: 0
                ),
                // Each swipe its own start, so the session's time limit is per swipe and a
                // long stroke of chained swipes is not cut off.
                startTime: eventClockNow()
            )
            swipeTag = eventTag
        } else if swipeNumber != 0, !synthesizer.isRunning(swipeNumber) {
            // A gesture began a swipe of its own (which cancelled this one), or a stop of the
            // gestures cancelled it: nothing more is sent until the wheel rests.
            endInterruptedSwipe()
            return false
        }
        guard pendingTravel != 0, var session else { return true }
        let travel = pendingTravel
        pendingTravel = 0
        let before = target
        let commands = session.move(deltaX: CGFloat(travel), deltaY: 0, at: lastEventAt)
        self.session = session
        for command in commands {
            switch command {
            case .begin(let axis):
                synthesizer.begin(axis: axis)
                swipeNumber = synthesizer.swipeNumber
                swipeBeganAt = clock()
                onSwipeBegin?(swipeTag)
            case .update(let progress):
                target = progress
                if progressPerSpace > 0 {
                    furthest = max(furthest, abs(progress) / progressPerSpace)
                }
            case .end, .cancel:
                // The session's own limit (a swipe that went on for many seconds): it goes
                // back, the rest of the stroke waits for the rest.
                if synthesizer.isRunning(swipeNumber) { synthesizer.cancel() }
                endInterruptedSwipe()
                return false
            case .discrete, .click:
                break
            }
        }
        countOverflow(travel: travel, before: before)
        return true
    }

    /// Travel the same way past a full Space (the session drops it, the count keeps it);
    /// travel back starts the count again.
    private func countOverflow(travel: Double, before: Double) {
        guard swipeNumber != 0, isAtFullSpace else {
            overflow = 0
            return
        }
        let full = ThumbWheelTuning.followFullShare * progressPerSpace
        let perUnit = progressPerSpace / ThumbWheelTuning.followUnitsPerSpace
        if before * target > 0, abs(before) + ThumbWheelTuning.thresholdSlack >= full {
            overflow = (travel > 0) == (target > 0) ? overflow + abs(travel) : 0
        } else if perUnit > 0 {
            // This travel reached a full Space: what went past that point counts.
            overflow = max(0, (abs(before + travel * perUnit) - full) / perUnit)
        }
    }

    /// The events' clock now (`lastEventAt` and the time since the callback saw it): the
    /// session's times are the events' own.
    private func eventClockNow() -> TimeInterval {
        return lastEventAt + max(0, clock() - lastSeenAt)
    }

    /// The wheel still at a full Space since this (on `clock`) ends the swipe: its last
    /// event, or the swipe's begin when it began after it (travel kept at the gate).
    private var stillSince: TimeInterval {
        return max(lastSeenAt, swipeBeganAt)
    }

    private func scheduleFullStopLook() {
        guard !fullStopScheduled else { return }
        fullStopScheduled = true
        let generation = self.generation
        schedule(max(0, stillSince + ThumbWheelTuning.followFullStopRest - clock())) { [weak self] in
            guard let self, self.generation == generation else { return }
            self.fullStopScheduled = false
            self.lookForFullStop()
        }
    }

    /// A swipe at a full Space and the wheel still since `followFullStopRest`: it ends now.
    private func lookForFullStop() {
        guard state == .following, swipeNumber != 0, isAtFullSpace else { return }
        guard clock() + 1e-9 >= stillSince + ThumbWheelTuning.followFullStopRest else {
            scheduleFullStopLook()
            return
        }
        guard takeTravel(), swipeNumber != 0, isAtFullSpace else { return }
        endAtFullSpace(.fullStop)
    }

    /// Ends the swipe at a full Space with no speed (macOS switches), and closes the gate.
    private func endAtFullSpace(_ ending: Ending) {
        if shown != target {
            shown = target
            synthesizer.update(progress: shown)
        }
        synthesizer.end(velocity: 0)
        let direction = target > 0 ? 1 : -1
        let swipe = Swipe(furthest: furthest, ending: ending, expectsSwitch: true)
        let tag = swipeTag
        clearSwipe()
        pendingTravel = 0
        state = .gated
        nextSwipeNeedsHalfASpace = true
        closeGate(direction: direction, tag: tag, swipe: swipe)
    }

    private func closeGate(direction: Int, tag: Int, swipe: Swipe) {
        if let earlier = gate {
            // (A swipe begins only once the gate opened: not reached.)
            tell(earlier.tag, earlier.swipe)
        }
        gateCount &+= 1
        let number = gateCount
        // An end at the rest stood part of the way: macOS settles it without speed, later
        // than a swipe it was handed at a full Space. So is the change of a swipe that ends
        // while the Dock still draws the bounce or the slide back of the one before.
        let endedAt = clock()
        let dockIsBusy = endedAt - endedWithoutSwitchAt < ThumbWheelTuning.followAfterNoSwitchWindow
        let timeout = swipe.ending == .ended || dockIsBusy
            ? ThumbWheelTuning.followSettleSpaceChangeTimeout : ThumbWheelTuning.followSpaceChangeTimeout
        gate = Gate(number: number, endedAt: endedAt, timeout: timeout, direction: direction, tag: tag, swipe: swipe,
                    stroke: generation)
        schedule(timeout) { [weak self] in
            guard let self, self.gate?.number == number else { return }
            self.gateTimedOut()
        }
    }

    /// No Space change came in time. The stroke the swipe ended in begins no swipe that way
    /// again until it ends or the Space changes after all; a later stroke that waits at the
    /// gate is not barred, the travel it kept begins its swipe. The swipe waits as the late
    /// record.
    private func gateTimedOut() {
        guard let gate else { return }
        self.gate = nil
        endedWithoutSwitchAt = gate.endedAt
        keepLate(gate)
        guard state != .idle else { return }
        if gate.stroke == generation { blockedDirection = gate.direction }
        if state == .gated { openGateForTheStroke() }
    }

    /// A timed-out gate's swipe waits `followLateSpaceChangeWindow` more for its change; then
    /// its ending is final as "no change". An older late record's chance is over.
    private func keepLate(_ timedOut: Gate) {
        if let older = lateRecord {
            lateRecord = nil
            tellLate(older)
        }
        lateRecord = timedOut
        let number = timedOut.number
        schedule(ThumbWheelTuning.followLateSpaceChangeWindow) { [weak self] in
            guard let self, let record = self.lateRecord, record.number == number else { return }
            self.lateRecord = nil
            self.tellLate(record)
        }
    }

    /// Tells the roll's line a swipe's ending. One of the late record's own roll waits behind
    /// it, so that roll's line lists its swipes in order; another roll's is told at once (its
    /// line does not wait for an older roll's late swipe).
    private func tell(_ tag: Int, _ swipe: Swipe) {
        if let lateRecord, lateRecord.tag == tag {
            queuedEnds.append((tag, swipe))
        } else {
            deliver(tag, swipe)
        }
    }

    /// Tells the late record's ending (taken off already), then those that waited behind it.
    private func tellLate(_ record: Gate) {
        deliver(record.tag, record.swipe)
        while lateRecord == nil, !queuedEnds.isEmpty {
            let end = queuedEnds.removeFirst()
            deliver(end.tag, end.swipe)
        }
    }

    /// The roll's line lists the swipe (its list grows: never in the tap callback). From
    /// `add` it is told after the callback, on the main queue, in the order told.
    private func deliver(_ tag: Int, _ swipe: Swipe) {
        guard inTapCallback else {
            onSwipeEnd?(tag, swipe)
            return
        }
        schedule(0) { [weak self] in self?.onSwipeEnd?(tag, swipe) }
    }

    /// The stroke at the gate goes on: it follows again (its kept travel begins a swipe,
    /// when it is half a Space or more), or waits for its rest while another swipe runs.
    private func openGateForTheStroke() {
        if synthesizer.isActive {
            state = .waiting
            strokeWaited = true
            pendingTravel = 0
        } else {
            state = .following
        }
        // Travel kept short of half a Space begins nothing (`nextSwipeNeedsHalfASpace`): it
        // waits for the stroke's next events; the rest drops it.
        let begins = state == .following && abs(pendingTravel) + ThumbWheelTuning.thresholdSlack
            >= InteractiveGestureSession.switchProgressShare * ThumbWheelTuning.followUnitsPerSpace
        guard !inTapCallback else {
            // An event found the gate timed out: it is the stroke's next, its frame begins
            // the swipe and its rest is looked for.
            if begins { scheduleFrame() }
            return
        }
        // The swipe begins in this turn of the main queue: the look for the rest may come in
        // the same turn, and would end a stroke it found with no swipe begun. The rest, held
        // back while the gate was closed, is looked for anew.
        if begins { frame() }
        scheduleRestLook(anew: true)
    }

    private func scheduleRestLook(anew: Bool = false) {
        guard anew || !restScheduled else { return }
        restScheduled = true
        restLook &+= 1
        let look = restLook
        let generation = self.generation
        schedule(max(0, restDueAt - clock())) { [weak self] in
            guard let self, self.generation == generation, self.restLook == look else { return }
            self.restScheduled = false
            self.lookForRest()
        }
    }

    /// When the rest ends the stroke, on `clock`: the wheel still for `followRest`, and a
    /// swipe under way shown sliding for `followFullStopRest` at least (one begun with travel
    /// kept at the gate may begin long after the wheel stopped). At a closed gate the stroke
    /// does not rest before the gate's timeout: the travel it kept begins the next swipe
    /// when the gate opens.
    private var restDueAt: TimeInterval {
        let rest = lastMovedSeenAt + ThumbWheelTuning.followRest
        if state == .gated, let gate { return max(rest, gate.endedAt + gate.timeout) }
        guard swipeNumber != 0 else { return rest }
        return max(rest, swipeBeganAt + ThumbWheelTuning.followFullStopRest)
    }

    /// The wheel has rested since it last moved: the stroke ends; else look again then.
    private func lookForRest() {
        guard state != .idle else { return }
        if let gate, clock() + 1e-9 >= gate.endedAt + gate.timeout {
            // The gate's own look is due in this turn too and has not come yet: the gate
            // opens first, so the travel kept is not dropped by a rest.
            gateTimedOut()
        }
        if clock() + 1e-9 >= restDueAt {
            // A swipe at a full Space ends as a full stop (due by then), whichever of the two
            // looks comes first.
            if state == .following, swipeNumber != 0, isAtFullSpace { lookForFullStop() }
            finishStroke(at: lastMovedAt + ThumbWheelTuning.followRest)
        } else {
            scheduleRestLook()
        }
    }

    /// Ends the stroke at `time` (the events' clock). A swipe under way gets the travel not
    /// given yet, the desktop is put where the wheel left it, and it ends by the rule of
    /// "Follow the hand" (`InteractiveGestureSession.release`).
    private func finishStroke(at time: TimeInterval) {
        guard state == .following else {
            endStroke()
            return
        }
        if session == nil {
            // The stroke is over: a swipe begun now would end in the same turn.
            pendingTravel = 0
        }
        guard takeTravel(), var session, swipeNumber != 0 else {
            // No swipe runs: the last one ended (at a full Space, or taken over), another
            // swipe ran when one would have begun, or the wheel never moved one.
            reportSwipe(.interrupted)
            endStroke()
            return
        }
        let commands = session.release(at: time)
        self.session = session
        for command in commands {
            switch command {
            case .end(let velocity):
                if shown != target {
                    shown = target
                    synthesizer.update(progress: shown)
                }
                synthesizer.end(velocity: velocity)
                let expectsSwitch = abs(target) >= InteractiveGestureSession.switchProgressShare * progressPerSpace
                let swipe = Swipe(furthest: furthest, ending: .ended, expectsSwitch: expectsSwitch)
                let direction = target > 0 ? 1 : -1
                let tag = swipeTag
                clearSwipe()
                if expectsSwitch {
                    closeGate(direction: direction, tag: tag, swipe: swipe)
                } else {
                    // Short of half a Space: it slides back, and the Dock draws that.
                    endedWithoutSwitchAt = clock()
                    tell(tag, swipe)
                }
            case .cancel:
                synthesizer.cancel()
                reportSwipe(.back)
            default:
                break
            }
        }
        // A swipe the release did not end (its time limit) was not finished here.
        reportSwipe(.interrupted)
        endStroke()
    }

    /// The swipe is no longer the stroke's: the stroke waits for the rest, sending nothing.
    private func endInterruptedSwipe() {
        reportSwipe(.interrupted)
        pendingTravel = 0
        state = .waiting
    }

    /// Says how the swipe under way ended, if one began, and forgets it.
    private func reportSwipe(_ ending: Ending) {
        guard swipeNumber != 0 else {
            clearSwipe()
            return
        }
        let swipe = Swipe(furthest: furthest, ending: ending)
        let tag = swipeTag
        clearSwipe()
        tell(tag, swipe)
    }

    private func clearSwipe() {
        session = nil
        swipeNumber = 0
        target = 0
        shown = 0
        furthest = 0
        swipeBeganAt = -TimeInterval.infinity
        overflow = 0
    }

    private func endStroke() {
        let tag = strokeTag
        let waited = strokeWaited
        state = .idle
        clearSwipe()
        pendingTravel = 0
        blockedDirection = 0
        strokeWaited = false
        frameScheduled = false
        restScheduled = false
        fullStopScheduled = false
        generation &+= 1
        onStrokeEnd?(tag, waited)
    }

    private func beginStroke(tag: Int) {
        generation &+= 1
        strokeTag = tag
        strokeWaited = false
        blockedDirection = 0
        clearSwipe()
        pendingTravel = 0
        nextSwipeNeedsHalfASpace = gate != nil
        if gate != nil {
            // The last swipe is settling: wait for the Space change (or the timeout).
            state = .gated
        } else if synthesizer.isActive {
            state = .waiting
            strokeWaited = true
        } else {
            state = .following
        }
    }
}

extension ThumbWheelFollower.Ending {
    /// How the roll's log line says it.
    var logName: String {
        switch self {
        case .chained: return "chained"
        case .fullStop: return "full stop"
        case .ended: return "ended"
        case .back: return "back"
        case .interrupted: return "interrupted"
        }
    }
}
