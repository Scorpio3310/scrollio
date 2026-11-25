//
//  DockFollowHold.swift
//  Scrollio
//
//  One hold of a gesture button with "Up and Down follow the hand too" on: what Up and
//  what Down do in it, decided once, when the button goes down, from the hold's own copy
//  of the settings (the Gestures pane's, or the own set of the app in front), from what
//  this Mac can follow now (`DockFollowAvailability`) and from what Scrollio believes the
//  Dock shows (`DockBelief`). `InputProcessor` turns the answer into the roles of the
//  hold's state machine (`InteractiveGestureSession.Roles`) and into the hold's lines in
//  the log. Left, Right and the click are not in here: they stay what they are.
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
        /// It leaves Mission Control with the hand, instead of its own action
        /// (`DockBelief.Move.leaveMissionControl`).
        case leavesMissionControl
        /// Its action could follow the hand and runs once in this hold instead.
        case onceInstead(DockFollowTarget, Reason)

        /// What it is about, for the log: the view by its action's stored name.
        var logName: String {
            switch self {
            case .once: return "nothing"
            case .opens(let target), .onceInstead(let target, _): return target.actionIdentifier
            case .leavesMissionControl: return "leaving " + DockFollowTarget.missionControl.actionIdentifier
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
            case .leavesMissionControl:
                // The way back of the motion that opens it, over the same travel.
                target = .missionControl
                sign = -DockFollowTarget.missionControl.sign
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
        /// Scrollio believes the view is showing, because a hold of its own just opened
        /// it: the same move again closes it.
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
            // Not "was showing": Scrollio cannot know that, only what it opened itself.
            case .showing(.missionControl): return "Scrollio had just opened Mission Control"
            case .showing(.showDesktop): return "Scrollio had just opened Show Desktop"
            case .showing(.apps): return "Scrollio had just opened Apps"
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

    /// The hold of these settings on a Mac with this availability, while `believed` is
    /// believed to show. With the switch off, or in "One action per hold", both directions
    /// are `.once`, whatever is believed.
    init(settings: MouseGestureSettings, availability: DockFollowAvailability, believed: DockFollowTarget?) {
        let upPlan = settings.followPlan(for: .up, availability: availability)
        let downPlan = settings.followPlan(for: .down, availability: availability)
        // Where the trackpad gesture for App Exposé is on, Mission Control is not left
        // with the hand (the leaving swipe could open App Exposé instead).
        let appExpose = availability.switches.appExpose
        up = Self.part(for: upPlan, opposite: downPlan, believed: believed, appExposeGestureIsOn: appExpose)
        down = Self.part(for: downPlan, opposite: upPlan, believed: believed, appExposeGestureIsOn: appExpose)
    }

    private static func part(
        for plan: DockFollowPlan, opposite: DockFollowPlan, believed: DockFollowTarget?, appExposeGestureIsOn: Bool
    ) -> Part {
        let move = DockBelief.move(
            for: plan, opposite: opposite, believed: believed, appExposeGestureIsOn: appExposeGestureIsOn
        )
        switch move {
        case .toggle(let view):
            return .onceInstead(view, .showing(view))
        case .leaveMissionControl:
            return .leavesMissionControl
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
    /// What the direction did: `.opens` or `.leavesMissionControl`.
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

    // MARK: What it does to the belief

    /// What the end of a motion does to the view Scrollio believes it put up (`DockBelief`).
    enum BeliefChange: Equatable {
        case none
        /// The hold opened this view with the hand.
        case opened(DockFollowTarget)
        /// Nothing is believed to show any more.
        case dropped
    }

    /// What this motion's end does to the belief.
    /// - A hold that opened a view and was let go as expected to open put that view up.
    /// - A hold that left Mission Control ends the belief unless it was turned back to
    ///   where it started (nothing was left then): whatever the Dock made of it, and
    ///   whatever ended it. Had Mission Control not been showing after all, the next move
    ///   is the direction's own action again, instead of nothing for up to a minute.
    /// - Any other end changes nothing.
    func beliefChange(after ending: Ending) -> BeliefChange {
        switch part {
        case .opens(let target):
            if case .ended(_, expected: true) = ending { return .opened(target) }
            return .none
        case .leavesMissionControl:
            return last > 0 ? .dropped : .none
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
        switch ending {
        case .ended(let velocity, let expected):
            var outward = fullProgress > 0 ? velocity * (sign < 0 ? -1 : 1) / fullProgress : 0
            // To the one decimal shown; a hand at rest reads 0.0, never -0.0.
            outward = (outward * 10).rounded() / 10
            if outward == 0 { outward = 0 }
            text += "released at \(share(last)), \(String(format: "%.1f", outward))/s: ended"
            if expected {
                text += part == .leavesMissionControl ? ", expected to close" : ", expected to open"
            }
        case .cancelledAtRelease:
            text += "released at \(share(last)): cancelled"
        case .cancelled(let interruption):
            text += "at \(share(last)): cancelled (\(interruption.logText))"
        }
        return text + (appsOwn ? DockFollowHold.appsOwnTail : "")
    }
}
