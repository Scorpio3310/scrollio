//
//  ThumbWheelFollower.swift
//  Scrollio
//
//  Switch Desktops with "Follow the wheel" (`ThumbWheelSettings.followsWheel`): the desktops
//  slide with the thumb wheel like a trackpad swipe, as Gestures' "Follow the hand" makes
//  them slide with the hand, and settle when the wheel rests.
//
//  A stroke is the wheel's events until it rests for `ThumbWheelTuning.followRest`. Its
//  first event begins a dock swipe (`DockSwipeSynthesizer`), each event moves it on in the
//  turn's direction (one event is one unit, up to two on a fast turn, × the speed;
//  `followUnitsPerSpace` units are one Space), and the rest ends it. The swipe itself is the
//  one "Follow the hand" runs (`InteractiveGestureSession`, fed with the wheel's units in
//  place of points): at most one Space either way, and the same rule at its end: back at the
//  start it is cancelled, else ended, and macOS settles it on the next desktop or back by
//  where it stands. The end comes when the wheel has rested, so the hand's speed is nothing
//  then: a wheel has no lift-off, its last notch says nothing about where the hand meant to
//  go, and a stroke that went half a desktop or more switches.
//
//  Where the work is done: the tap callback only adds an event's travel up (`add`, a few
//  sums and at most one closure per display frame); the swipe begins, moves and ends on the
//  main queue, at most once per display frame, as a gesture's does (the Dock stutters when
//  swipe events come faster than it draws). The screen (its width does not matter here, the
//  number of Spaces does) is looked at when a swipe begins, on the main queue. The desktop
//  eases toward where the wheel put it (`followEasePerFrame`), so an event is a short slide.
//
//  One swipe at a time: a stroke begins a swipe only while none runs (a gesture hold that
//  follows the hand may be swiping): it then waits for the rest and sends nothing. A
//  gesture that begins a swipe during a stroke takes the Dock over (the synthesizer cancels
//  the wheel's swipe); the stroke sees its swipe is not the one running and sends nothing
//  more. A stop (`cancel`) cancels the swipe at once.
//
//  Main thread only: the tap callback and the main queue.
//

import Cocoa

final class ThumbWheelFollower {

    /// How a stroke ended (the roll's log line counts them).
    enum Outcome: Equatable {
        /// The swipe was ended where it stood: macOS settled it (next desktop, or back).
        case ended
        /// Back at its start: cancelled.
        case wentBack
        /// Another swipe took over, Scrollio stopped, or the settings changed in the middle.
        case interrupted
        /// Another swipe ran when the stroke began: nothing was sent.
        case waited
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
    /// A stroke ended: how, and the furthest its swipe went (a share of one Space).
    var onStrokeEnd: ((Outcome, Double) -> Void)?

    enum State: Equatable {
        case idle
        /// Another swipe ran: the stroke is swallowed until the wheel rests.
        case waiting
        case following
    }

    private(set) var state = State.idle
    /// A stroke is under way (following, or waiting for its rest).
    var isInStroke: Bool { return state != .idle }

    /// The swipe of the stroke; nil until its first look on the main queue.
    private var session: InteractiveGestureSession?
    /// The synthesizer's number of the stroke's swipe; 0 before it began.
    private var swipeNumber = 0
    /// Travel the main queue has not given the swipe yet (units, positive toward "next").
    private var pendingTravel = 0.0
    /// The events' own times of the stroke's first and last event.
    private var firstEventAt: TimeInterval = 0
    private var lastEventAt: TimeInterval = 0
    /// When the callback saw the last event, on `clock`.
    private var lastSeenAt: TimeInterval = 0
    /// Where the wheel has put the desktop, and where the Dock was told it is (progress).
    private var target = 0.0
    private var shown = 0.0
    private var progressPerSpace = 1.0
    private var furthest = 0.0
    private var frameDuration = InteractiveGestureEnvironment.fallbackScreen.frameDuration
    private var lastFrameAt = -TimeInterval.infinity
    private var frameScheduled = false
    private var restScheduled = false
    /// Moves on with each stroke's end: work scheduled for an earlier stroke does nothing.
    private var generation = 0

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
    func add(_ travel: Double, at time: TimeInterval, seenAt: TimeInterval) -> Taken {
        if state != .idle, time >= lastEventAt + ThumbWheelTuning.followRest {
            // The rest's look has not come yet (the main queue was busy): the stroke ended.
            finishStroke(at: lastEventAt + ThumbWheelTuning.followRest)
        }
        var newStroke = false
        if state == .idle {
            guard synthesizer.isAvailable else { return .no }
            newStroke = true
            generation &+= 1
            state = synthesizer.isActive ? .waiting : .following
            session = nil
            swipeNumber = 0
            pendingTravel = 0
            target = 0
            shown = 0
            furthest = 0
            firstEventAt = time
        }
        lastEventAt = time
        lastSeenAt = seenAt
        if state == .following, travel.isFinite {
            pendingTravel += travel
            scheduleFrame()
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
    /// may not run again before the stop is over), nothing scheduled runs.
    func cancel() {
        guard state != .idle else { return }
        let outcome: Outcome
        if state == .following, swipeNumber != 0, synthesizer.isRunning(swipeNumber) {
            synthesizer.cancel()
            outcome = .interrupted
        } else {
            outcome = state == .waiting ? .waited : .interrupted
        }
        endState(outcome)
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

    /// One display frame of the stroke: the travel so far goes to the swipe, and the desktop
    /// eases toward where it should stand.
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
        if shown != target || pendingTravel != 0 {
            scheduleFrame()
        }
    }

    /// Gives the swipe the travel that came since the last frame, beginning it at the
    /// stroke's first; false when the stroke stopped following (another swipe runs, or
    /// took over).
    private func takeTravel() -> Bool {
        if session == nil {
            // Another swipe began since the event was taken: this stroke waits.
            guard !synthesizer.isActive else {
                state = .waiting
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
                    // The first event is the stroke's: no travel is spent on arming.
                    lockDistance: 0
                ),
                startTime: firstEventAt
            )
        } else if swipeNumber != 0, !synthesizer.isRunning(swipeNumber) {
            // A gesture began a swipe of its own (which cancelled this one), or a stop of the
            // gestures cancelled it: nothing more is sent until the wheel rests.
            endInterruptedSwipe()
            return false
        }
        guard pendingTravel != 0, var session else { return true }
        let travel = pendingTravel
        pendingTravel = 0
        let commands = session.move(deltaX: CGFloat(travel), deltaY: 0, at: lastEventAt)
        self.session = session
        for command in commands {
            switch command {
            case .begin(let axis):
                synthesizer.begin(axis: axis)
                swipeNumber = synthesizer.swipeNumber
            case .update(let progress):
                target = progress
                if progressPerSpace > 0 {
                    furthest = max(furthest, abs(progress) / progressPerSpace)
                }
            case .end, .cancel:
                // The session's own limit (a stroke that went on for many seconds): the swipe
                // goes back, the rest of the stroke waits for the rest.
                if synthesizer.isRunning(swipeNumber) { synthesizer.cancel() }
                endInterruptedSwipe()
                return false
            case .discrete, .click:
                break
            }
        }
        return true
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

    /// Ends the stroke at `time` (the events' clock): the travel not given yet goes to the
    /// swipe, the desktop is put where the wheel left it, and the swipe ends by the rule of
    /// "Follow the hand" (`InteractiveGestureSession.release`).
    private func finishStroke(at time: TimeInterval) {
        guard state == .following else {
            endState(.waited)
            return
        }
        guard takeTravel(), var session, swipeNumber != 0 else {
            // Another swipe ran when it would have begun (it waited), the swipe was taken
            // over (already said), or the wheel never moved it (nothing was sent).
            endState(state == .waiting ? .waited : .wentBack)
            return
        }
        let commands = session.release(at: time)
        self.session = session
        var outcome = Outcome.interrupted
        for command in commands {
            switch command {
            case .end(let velocity):
                if shown != target {
                    shown = target
                    synthesizer.update(progress: shown)
                }
                synthesizer.end(velocity: velocity)
                outcome = .ended
            case .cancel:
                synthesizer.cancel()
                outcome = .wentBack
            default:
                break
            }
        }
        endState(outcome)
    }

    /// The swipe is no longer the stroke's: the stroke waits for the rest, sending nothing.
    private func endInterruptedSwipe() {
        let furthest = self.furthest
        session = nil
        swipeNumber = 0
        pendingTravel = 0
        state = .waiting
        // Said once here; the rest then ends the stroke without a second outcome.
        onStrokeEnd?(.interrupted, furthest)
        interruptedOutcomeSent = true
    }

    /// An interrupted stroke has said so already: its rest says nothing more.
    private var interruptedOutcomeSent = false

    private func endState(_ outcome: Outcome) {
        let furthest = self.furthest
        let alreadySaid = interruptedOutcomeSent
        state = .idle
        session = nil
        swipeNumber = 0
        pendingTravel = 0
        target = 0
        shown = 0
        self.furthest = 0
        frameScheduled = false
        restScheduled = false
        interruptedOutcomeSent = false
        generation &+= 1
        if !alreadySaid {
            onStrokeEnd?(outcome, furthest)
        }
    }
}
