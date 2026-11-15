//
//  ThumbWheelFollower.swift
//  Scrollio
//
//  Switch Desktops with "Follow the wheel" (`ThumbWheelSettings.followsWheel`): the desktops
//  slide with the thumb wheel like a trackpad swipe, as Gestures' "Follow the hand" makes
//  them slide with the hand, and settle when the wheel rests. One long roll moves several
//  desktops, as quick trackpad swipes chain.
//
//  A stroke is the wheel's events until it rests for `ThumbWheelTuning.followRest`. Its
//  first event begins a dock swipe (`DockSwipeSynthesizer`), each event moves it on in the
//  turn's direction (one event is one unit, up to two on a fast turn, × the speed;
//  `followUnitsPerSpace` units are one Space). The swipe itself is the one "Follow the hand"
//  runs (`InteractiveGestureSession`, fed with the wheel's units in place of points): at
//  most one Space either way. A swipe ends in one of three ways:
//  - At a full Space (`followFullShare`) with the wheel still turning that way: once the
//    travel past that point reaches `followChainOverflowUnits`, it ends at once, at the full
//    Space with no speed ("chained"), so the next desktop can come in this stroke.
//  - At a full Space with the wheel still for `followFullStopRest`: it ends then ("full
//    stop"), not only at the rest.
//  - At the rest, by the rule of "Follow the hand" (`InteractiveGestureSession.release`):
//    back at the start it is cancelled, else ended, and macOS settles it on the next
//    desktop or back by where it stands (the hand's speed is nothing then: a wheel has no
//    lift-off), so half a desktop or more switches.
//
//  The gate: after an end at half a Space or more (a switch is expected), no swipe begins,
//  in this stroke or a new one, until macOS says the Space changed
//  (`NSWorkspace.activeSpaceDidChangeNotification`, `spaceDidChange`) or
//  `followSpaceChangeTimeout` passed: a swipe begun while the last one settles can catch it
//  and take it back. Travel meanwhile is kept (`followGatePendingCap` at most) and begins
//  the next swipe when the Space changed. When no change came in time, the desktop was the
//  first or the last that way (the Dock let the swipe bounce back): for the rest of the
//  stroke no swipe begins that way (travel the other way does), so the wheel never sends
//  the Dock into a loop of bounces; the next stroke begins as usual. The gate's memory
//  outlives the stroke.
//
//  Where the work is done: the tap callback only adds an event's travel up (`add`, a few
//  sums and at most one closure per display frame); the swipe begins, moves and ends on the
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
        /// Seconds from its end to the Space change; nil: none came within
        /// `followSpaceChangeTimeout` (or none was expected).
        var spaceChangedAfter: TimeInterval?
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
    /// Where the wheel has put the desktop, and where the Dock was told it is (progress).
    private var target = 0.0
    private var shown = 0.0
    private var progressPerSpace = 1.0
    private var furthest = 0.0
    /// Travel the same way since the swipe reached a full Space (units).
    private var overflow = 0.0
    private var frameDuration = InteractiveGestureEnvironment.fallbackScreen.frameDuration
    private var lastFrameAt = -TimeInterval.infinity
    private var frameScheduled = false
    private var restScheduled = false
    private var fullStopScheduled = false
    /// Moves on with each stroke's end: work scheduled for an earlier stroke does nothing.
    private var generation = 0
    /// The tags of the stroke's first event, of its latest, and of the swipe under way.
    private var strokeTag = 0
    private var eventTag = 0
    private var swipeTag = 0
    /// The stroke found another swipe running and sent nothing for that reason.
    private var strokeWaited = false
    /// No swipe begins this way for the rest of the stroke (+1, −1; 0: none).
    private var blockedDirection = 0

    /// The last end where a switch was expected, until the Space changed or the timeout
    /// passed: it outlives the stroke.
    private struct Gate {
        var number: Int
        /// On `clock`.
        var endedAt: TimeInterval
        /// The way the swipe went (+1 toward "next").
        var direction: Int
        var tag: Int
        var swipe: Swipe
    }
    private var gate: Gate?
    private var gateCount = 0

    private let spaceChanges: NotificationCenter?
    private var spaceObserver: NSObjectProtocol?

    /// The notification center macOS tells a change of the Space in use on; none under
    /// XCTest (tests call `spaceDidChange` themselves).
    static var systemSpaceChanges: NotificationCenter? {
        return AppRuntime.isRunningXCTest ? nil : NSWorkspace.shared.notificationCenter
    }

    init(spaceChanges: NotificationCenter? = ThumbWheelFollower.systemSpaceChanges) {
        self.spaceChanges = spaceChanges
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
        if state != .idle, time >= lastEventAt + ThumbWheelTuning.followRest {
            // The rest's look has not come yet (the main queue was busy): the stroke ended.
            finishStroke(at: lastEventAt + ThumbWheelTuning.followRest)
        }
        if let gate, clock() + 1e-9 >= gate.endedAt + ThumbWheelTuning.followSpaceChangeTimeout {
            // The gate's look has not come yet (the main queue was busy): it timed out.
            gateTimedOut()
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

    /// The turn no longer follows the wheel (its settings changed in the middle): the stroke
    /// ends now, by the same rule as at a rest.
    func endStroke(at time: TimeInterval) {
        guard state != .idle else { return }
        finishStroke(at: max(time, lastEventAt))
    }

    /// Scrollio stopped handling the wheel: the swipe is cancelled at once (the main queue
    /// may not run again before the stop is over), the gate forgotten, nothing scheduled runs.
    func cancel() {
        if let gate {
            self.gate = nil
            onSwipeEnd?(gate.tag, gate.swipe)
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
        guard var gate else { return }
        self.gate = nil
        gate.swipe.spaceChangedAfter = max(0, clock() - gate.endedAt)
        onSwipeEnd?(gate.tag, gate.swipe)
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
    /// turning that way ends.
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
            if overflow + ThumbWheelTuning.thresholdSlack >= ThumbWheelTuning.followChainOverflowUnits {
                endAtFullSpace(.chained)
                return
            }
            scheduleFullStopLook()
        }
        if shown != target || pendingTravel != 0 {
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

    private func scheduleFullStopLook() {
        guard !fullStopScheduled else { return }
        fullStopScheduled = true
        let generation = self.generation
        schedule(max(0, lastSeenAt + ThumbWheelTuning.followFullStopRest - clock())) { [weak self] in
            guard let self, self.generation == generation else { return }
            self.fullStopScheduled = false
            self.lookForFullStop()
        }
    }

    /// A swipe at a full Space and the wheel still since `followFullStopRest`: it ends now.
    private func lookForFullStop() {
        guard state == .following, swipeNumber != 0, isAtFullSpace else { return }
        guard clock() + 1e-9 >= lastSeenAt + ThumbWheelTuning.followFullStopRest else {
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
        closeGate(direction: direction, tag: tag, swipe: swipe)
    }

    private func closeGate(direction: Int, tag: Int, swipe: Swipe) {
        if let earlier = gate {
            // (A swipe begins only once the gate opened: not reached.)
            onSwipeEnd?(earlier.tag, earlier.swipe)
        }
        gateCount &+= 1
        let number = gateCount
        gate = Gate(number: number, endedAt: clock(), direction: direction, tag: tag, swipe: swipe)
        schedule(ThumbWheelTuning.followSpaceChangeTimeout) { [weak self] in
            guard let self, self.gate?.number == number else { return }
            self.gateTimedOut()
        }
    }

    /// No Space change came in time: the swipe's ending is final as "no change"; for the rest
    /// of the stroke no swipe begins that way.
    private func gateTimedOut() {
        guard let gate else { return }
        self.gate = nil
        onSwipeEnd?(gate.tag, gate.swipe)
        guard state != .idle else { return }
        blockedDirection = gate.direction
        if state == .gated { openGateForTheStroke() }
    }

    /// The stroke at the gate goes on: it follows again (its kept travel begins a swipe),
    /// or waits for its rest while another swipe runs.
    private func openGateForTheStroke() {
        guard !synthesizer.isActive else {
            state = .waiting
            strokeWaited = true
            pendingTravel = 0
            return
        }
        state = .following
        if pendingTravel != 0 { scheduleFrame() }
    }

    private func scheduleRestLook() {
        guard !restScheduled else { return }
        restScheduled = true
        let generation = self.generation
        schedule(max(0, lastSeenAt + ThumbWheelTuning.followRest - clock())) { [weak self] in
            guard let self, self.generation == generation else { return }
            self.restScheduled = false
            self.lookForRest()
        }
    }

    /// The wheel has rested since its last event: the stroke ends; else look again then.
    private func lookForRest() {
        guard state != .idle else { return }
        if clock() + 1e-9 >= lastSeenAt + ThumbWheelTuning.followRest {
            finishStroke(at: lastEventAt + ThumbWheelTuning.followRest)
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
                    onSwipeEnd?(tag, swipe)
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
        onSwipeEnd?(tag, swipe)
    }

    private func clearSwipe() {
        session = nil
        swipeNumber = 0
        target = 0
        shown = 0
        furthest = 0
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
