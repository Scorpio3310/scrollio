//
//  DockFollowHold.swift
//  Scrollio
//
//  One hold of a gesture button with "Up and Down follow the hand too" on: what Up and
//  what Down do in it, decided once, when the button goes down, from the hold's own copy
//  of the settings (the Gestures pane's, or the own set of the app in front), from what
//  this Mac can follow now (`DockFollowAvailability`) and from the view of the Dock that
//  shows, as far as Scrollio knows (`DockBelief`). `InputProcessor` turns the answer into
//  the roles of the hold's state machine (`InteractiveGestureSession.Roles`) and into the
//  hold's lines in the log. Left, Right and the click are not in here: they stay what
//  they are.
//
//  Pure: nothing here posts, reads or stores anything.
//

import Cocoa

struct DockFollowHold: Equatable {

    /// What one direction does in the hold.
    enum Part: Equatable {
        /// Its action once at the usual distance, and nothing asked for more: an action
        /// without a view of the Dock, "No Action", a recorded key combination.
        case once
        /// It opens the view with the hand.
        case opens(DockFollowTarget)
        /// It leaves the view that shows with the hand, instead of its own action
        /// (`DockBelief.Move.leave`): the view the other direction opens.
        case leaves(DockFollowTarget)
        /// Its action could follow the hand and runs once in this hold instead.
        case onceInstead(DockFollowTarget, Reason)

        /// What it is about, for the log: the view by its action's stored name.
        var logName: String {
            switch self {
            case .once: return "nothing"
            case .opens(let target), .onceInstead(let target, _): return target.actionIdentifier
            case .leaves(let view): return "leaving " + view.actionIdentifier
            }
        }

        /// The Dock motion the direction drives, for the hold's state machine; nil: the
        /// direction is discrete. Progress is one-sided and stops at the whole view; the
        /// travel, the room for the jolt of letting go and the bound of the release
        /// velocity are `DockFollowTuning`'s.
        func channel(screenHeight: CGFloat, trackingSpeed: Double) -> InteractiveGestureSession.Channel? {
            let target: DockFollowTarget
            let sign: Double
            switch self {
            case .once, .onceInstead:
                return nil
            case .opens(let opened):
                target = opened
                sign = opened.sign
            case .leaves(let view):
                // The way back of the motion that opens it, over the same travel.
                target = view
                sign = -view.sign
            }
            return InteractiveGestureSession.Channel(
                motion: target.axis,
                sign: sign,
                progressPerPoint: DockSwipeGeometry.followProgressPerPoint(
                    for: target, screenHeight: screenHeight, trackingSpeed: trackingSpeed
                ),
                maximumProgress: DockFollowTuning.fullProgress,
                reverseTolerance: DockFollowTuning.reverseTolerance,
                maximumTravelsPerSecond: DockFollowTuning.maximumTravelsPerSecond
            )
        }
    }

    /// Why a direction whose action could follow the hand ran once.
    enum Reason: Equatable {
        /// This Mac does not follow it now.
        case obstacle(DockFollowAvailability.Obstacle)
        /// The view is taken to show (the Dock said so, or Scrollio itself just opened
        /// it): the same move again closes it.
        case showing(DockFollowTarget)
        /// The thumb wheel's swipe of the desktops was still running when the motion would
        /// have begun; a hold never takes that swipe over for another motion.
        case wheelSwipeRunning

        /// For the log.
        var logText: String {
            switch self {
            case .obstacle(.notOnThisMacOS): return "not on this macOS"
            case .obstacle(.swipeUnavailable): return "the swipe cannot be made on this Mac"
            case .obstacle(.gestureOff): return "the Dock's gesture is off"
            case .obstacle(.cannotPostEvents): return "cannot post events"
            // Not "was showing": for Apps Scrollio only knows what it opened itself.
            case .showing(.missionControl): return "Mission Control was taken to show"
            case .showing(.showDesktop): return "Show Desktop was taken to show"
            case .showing(.apps): return "Apps was taken to show"
            case .wheelSwipeRunning: return "the wheel's swipe was running"
            }
        }
    }

    var up: Part
    var down: Part

    subscript(direction: MouseGestureDirection) -> Part {
        switch direction {
        case .up: return up
        case .down: return down
        case .left, .right: return .once
        }
    }

    init(up: Part, down: Part) {
        self.up = up
        self.down = down
    }

    /// The hold of these settings on a Mac with this availability, while `shown` is taken
    /// to show (`toldByTheDock`: the Dock itself said so). With the switch off, or in "One
    /// action per hold", both directions are `.once`, whatever shows.
    init(
        settings: MouseGestureSettings, availability: DockFollowAvailability, shown: DockFollowTarget?,
        toldByTheDock: Bool = false
    ) {
        let upPlan = settings.followPlan(for: .up, availability: availability)
        let downPlan = settings.followPlan(for: .down, availability: availability)
        // Where the trackpad gesture for App Exposé is on, a Mission Control that is only
        // believed is not left with the hand (the leaving swipe could open App Exposé).
        let appExpose = availability.switches.appExpose
        func part(for plan: DockFollowPlan, opposite: DockFollowPlan) -> Part {
            return Self.part(
                for: plan, opposite: opposite, shown: shown, toldByTheDock: toldByTheDock, appExposeGestureIsOn: appExpose
            )
        }
        up = part(for: upPlan, opposite: downPlan)
        down = part(for: downPlan, opposite: upPlan)
    }

    private static func part(
        for plan: DockFollowPlan, opposite: DockFollowPlan, shown: DockFollowTarget?, toldByTheDock: Bool,
        appExposeGestureIsOn: Bool
    ) -> Part {
        let move = DockBelief.move(
            for: plan, opposite: opposite, shown: shown, isTold: toldByTheDock, appExposeGestureIsOn: appExposeGestureIsOn
        )
        switch move {
        case .toggle(let view):
            return .onceInstead(view, .showing(view))
        case .leave(let view):
            return .leaves(view)
        case .asPlanned:
            switch plan {
            case .follows(let target): return .opens(target)
            case .cannotFollow(let target, let obstacle): return .onceInstead(target, .obstacle(obstacle))
            case .doesNotFollow: return .once
            }
        }
    }

    // MARK: - The log

    /// The line of a direction that could follow the hand (`part`: what it would have
    /// done) and ran once instead; the line of the action itself follows it
    /// (`InputProcessor.mouseGestureRunLine`). The view by its action's stored name; never
    /// an app's name.
    static func ranOnceLine(
        _ direction: MouseGestureDirection, insteadOf part: Part, reason: Reason, appsOwn: Bool = false
    ) -> String {
        return "Gestures: \(InputProcessor.MouseGesturePart.direction(direction).logName) did not follow the hand: "
            + "\(part.logName), \(reason.logText)" + (appsOwn ? Self.appsOwnTail : "")
    }

    fileprivate static let appsOwnTail = ", the app in front has its own gestures"
}

// MARK: - A motion that followed the hand

/// The numbers of one motion a hold drove with the hand up or down, for its one line in
/// the log. Counted in plain numbers while the hold runs; the text is made once, after the
/// motion's last event went out.
struct DockFollowedMotion: Equatable {

    /// How the motion ended.
    enum Ending: Equatable {
        /// The button came up: macOS completes or reverts, from where it was and how fast.
        /// `expected`: Scrollio expects the view to open (or to be left), which is what the
        /// stronger haptic cue and the belief go by.
        case ended(velocity: Double, expected: Bool)
        /// The button came up at the start, or with the hand heading back.
        case cancelledAtRelease
        /// A flick (`isFlickIfReleasedToSwitch`): the motion was taken back and the
        /// direction's action ran once instead. `velocity` as in `ended`.
        case flick(velocity: Double)
        /// Something else took the motion back.
        case cancelled(Interruption)
    }

    /// What took a motion back before its button came up.
    enum Interruption: Equatable {
        /// The hold was older than its limit: its button-up never came.
        case noButtonUp
        /// The mouse went away mid-hold (a made-up release).
        case mouseWentAway
        /// Scrollio's event taps stopped or started over (sleep, Pause, quit, a tap that
        /// macOS switched off).
        case scrollioStopped
        case screensChanged
        case displaysSlept
        case spaceChanged
        case ringOpened
        /// Its swipe was no longer the one running when its last event was due: the Dock
        /// had been asked for a view in one go meanwhile, or the swipe had been taken back.
        case takenBack

        var logText: String {
            switch self {
            case .noButtonUp: return "no button-up"
            case .mouseWentAway: return "the mouse went away"
            case .scrollioStopped: return "Scrollio's event taps stopped"
            case .screensChanged: return "the screens changed"
            case .displaysSlept: return "the displays went to sleep"
            case .spaceChanged: return "the desktop in use changed"
            case .ringOpened: return "the Shortcut Ring opened"
            case .takenBack: return "its swipe had been taken back"
            }
        }
    }

    /// The line of a swipe of the desktops that was taken back (the screens changed, the
    /// displays went to sleep): a hold's or the thumb wheel's. The desktops' swipe writes
    /// no other line.
    static func desktopsSwipeTakenBackLine(_ interruption: Interruption) -> String {
        return "Gestures: a swipe of the desktops was taken back (\(interruption.logText))"
    }

    var direction: MouseGestureDirection
    /// What the direction did: `.opens` or `.leaves`.
    var part: DockFollowHold.Part
    var motion: DockSwipeAxis
    /// +1 or -1: what the hand's way out does to the motion's progress.
    var sign: Double
    /// The whole motion (`DockFollowTuning.fullProgress`), for the shares below.
    var fullProgress: Double
    /// From the press to the begin, in seconds.
    var beganAfter: TimeInterval
    var updates = 0
    /// The largest progress told, as a magnitude.
    var furthest: Double = 0
    /// The last progress told, as a magnitude.
    var last: Double = 0

    mutating func told(progress: Double) {
        updates += 1
        last = abs(progress)
        furthest = max(furthest, last)
    }

    /// The view moved at least `DockFollowTuning.flickFloor` of the way, as the Dock was
    /// last told.
    var hasMovedTheView: Bool {
        return fullProgress > 0 && last / fullProgress >= DockFollowTuning.flickFloor
    }

    /// Whether a release that is expected to switch is a flick: the view has moved less
    /// than `DockFollowTuning.flickFloor` of the way, so only the hand's speed says "open"
    /// (or "close"). The motion is then taken back and the view's own action runs once
    /// instead (`toggledByAFlick`): the instant toggle opens the view, as the direction
    /// did before it could follow the hand, and closes the one a hold was leaving.
    var isFlickIfReleasedToSwitch: Bool {
        switch part {
        case .opens, .leaves: return !hasMovedTheView
        case .once, .onceInstead: return false
        }
    }

    /// The direction whose action a flick runs once: the hold's own where it opens a
    /// view, the other one where it leaves the view that direction opens.
    var toggledByAFlick: MouseGestureDirection {
        guard case .leaves = part else { return direction }
        return direction == .up ? .down : .up
    }

    // MARK: What it does to the belief

    /// What the end of a motion does to the view that is taken to show (`DockBelief`).
    enum BeliefChange: Equatable {
        case none
        /// The hold opened this view with the hand.
        case opened(DockFollowTarget)
        /// The hold left the shown view with the hand. `completed`: it was let go as
        /// expected to close it (`DockBelief.holdLeft`).
        case left(completed: Bool)
    }

    /// What this motion's end does to the belief.
    /// - A hold that opened a view and was let go as expected to open put that view up,
    ///   if the view had moved (`hasMovedTheView`): a release that is expected to open
    ///   only because the hand was fast, at a few hundredths of the way, may well fall
    ///   back, and a wrong belief costs more than none.
    /// - A hold that left a view ends a belief unless it was turned back to where it
    ///   started (nothing was left then): whatever the Dock made of it, and whatever ended
    ///   it. Had the view not been showing after all, the next move is the direction's own
    ///   action again, instead of nothing for up to a minute. (A view the Dock named stays
    ///   unless the hold was let go as expected to close it: `DockBelief.holdLeft`.)
    /// - Any other end changes nothing. A flick's own toggle changes the belief by itself.
    func beliefChange(after ending: Ending) -> BeliefChange {
        switch part {
        case .opens(let target):
            if case .ended(_, expected: true) = ending, hasMovedTheView { return .opened(target) }
            return .none
        case .leaves:
            guard last > 0 else { return .none }
            switch ending {
            case .flick: return .none
            case .ended(_, expected: true): return .left(completed: true)
            case .ended, .cancelledAtRelease, .cancelled: return .left(completed: false)
            }
        case .once, .onceInstead:
            return .none
        }
    }

    private func share(_ progress: Double) -> String {
        return String(format: "%.2f", fullProgress > 0 ? progress / fullProgress : 0)
    }

    /// The line. Progress as a share of the whole motion, and the speed in whole motions
    /// per second, both counted the hand's way out (the motion and its sign say which way
    /// that is for the Dock). The view by its action's stored name; never an app's name.
    func line(_ ending: Ending, appsOwn: Bool = false) -> String {
        let motionName: String
        switch motion {
        case .horizontal: motionName = "horizontal"
        case .vertical: motionName = "vertical"
        case .pinch: motionName = "pinch"
        }
        let milliseconds = beganAfter.isFinite ? Int((min(max(beganAfter, 0), 3600) * 1000).rounded()) : 0
        var text = "Gestures: \(InputProcessor.MouseGesturePart.direction(direction).logName) followed the hand: "
            + "\(part.logName), \(motionName) \(sign < 0 ? "-" : "+"), "
            + "began after \(milliseconds) ms, "
            + "\(updates) update\(updates == 1 ? "" : "s"), furthest \(share(furthest)), "
        /// The hand's speed outwards, to the one decimal shown; a hand at rest reads 0.0,
        /// never -0.0.
        func speed(_ velocity: Double) -> String {
            var outward = fullProgress > 0 ? velocity * (sign < 0 ? -1 : 1) / fullProgress : 0
            outward = (outward * 10).rounded() / 10
            if outward == 0 { outward = 0 }
            return String(format: "%.1f", outward)
        }
        switch ending {
        case .ended(let velocity, let expected):
            text += "released at \(share(last)), \(speed(velocity))/s: ended"
            if expected {
                if case .leaves = part {
                    text += ", expected to close"
                } else {
                    text += ", expected to open"
                }
            }
        case .flick(let velocity):
            text += "released at \(share(last)), \(speed(velocity))/s: cancelled, a flick: ran once"
        case .cancelledAtRelease:
            text += "released at \(share(last)): cancelled"
        case .cancelled(let interruption):
            text += "at \(share(last)): cancelled (\(interruption.logText))"
        }
        return text + (appsOwn ? DockFollowHold.appsOwnTail : "")
    }
}
