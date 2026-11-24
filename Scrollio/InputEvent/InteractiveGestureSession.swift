//
//  InteractiveGestureSession.swift
//  Mos
//
//  State machine of one gesture-button hold in "follow the hand" mode. Pure: it takes
//  movement and time and returns commands; `InputProcessor` turns the commands into dock
//  swipe events and actions.
//
//  Each of the four directions has a role for the hold, fixed when the button goes down:
//  a channel (a Dock motion the hand drives) or discrete (its action runs once).
//
//      armed ──locks on a channel that begins there──▶ swiping ──release / cancel / watchdog──▶ finished
//        │                                                ▲                                        ▲
//        │                          first direction at 40 pt is a channel                          │
//        └────any other lock────▶ discrete ──release / cancel / watchdog───────────────────────────┘
//
//  - armed: the button is down. Once the pointer has travelled `lockDistance` and one
//    direction clearly dominates, the hold locks.
//  - swiping: the hand drives one Dock motion. Emits `begin` once, then `update` with the
//    cumulative progress, then exactly one of `end` or `cancel`. One hold begins at most one
//    motion and never changes it.
//  - discrete: past the lock without a motion. The first direction at the usual 40 pt
//    decides, whatever the first 8 pt were (the jolt of pressing a thumb button is enough
//    to make those vertical): a discrete direction runs its action once, like the classic
//    mode, and a channel begins with that movement. A hold that barely moved is a click.
//
//  Sideways (the Spaces swipe) begins at the lock and goes on through its start to the
//  Space on the other side. Any other channel begins at the 40 pt, where its direction's
//  action would run, so the jolt of a press or an unsteady click shows the Dock nothing;
//  its progress is one-sided, and behind its start nothing moves.
//

import Cocoa

struct InteractiveGestureSession {

    /// A Dock motion one direction drives while the button is held.
    struct Channel: Equatable {
        var motion: DockSwipeAxis
        /// What moving the hand in this direction does to the motion's progress: +1 or -1.
        var sign: Double
        /// Progress per point of pointer travel, tracking speed included. Positive.
        var progressPerPoint: Double
        /// Largest progress, as a magnitude: one Space sideways
        /// (`DockSwipeGeometry.progressPerSpace`), fully open for the other motions.
        var maximumProgress: Double
        /// What movement back past the start does. false: progress stays 0 there (the
        /// desktop as it was). true: it goes on to the other side, down to
        /// `-maximumProgress` (the Spaces swipe: the Space on the other side comes in).
        var crossesStart: Bool = false
        /// true: the motion begins when the hold locks (`lockDistance`). false: it begins
        /// where a discrete direction runs its action (the recognizer's 40 pt).
        var beginsAtLock: Bool = false
        /// Points the hand may have gone back towards the start inside the velocity window
        /// and still be taken as at rest when the button comes up: the release is `end`
        /// with velocity 0, not `cancel`. Letting go of a thumb button jolts the mouse.
        /// 0: any movement back cancels (the Spaces swipe).
        var reverseTolerance: CGFloat = 0
        /// Largest velocity an `end` carries, either way, in whole motions
        /// (`maximumProgress`) per second. nil: as measured (the Spaces swipe).
        var maximumTravelsPerSecond: Double? = nil

        /// Where the progress may be. A maximum that is no positive number leaves no room.
        var progressRange: ClosedRange<Double> {
            let limit = maximumProgress > 0 ? maximumProgress : 0
            if crossesStart { return -limit...limit }
            return sign < 0 ? -limit...0 : 0...limit
        }
    }

    /// What one direction does in a hold.
    enum Role: Equatable {
        /// Runs the direction's action once, at 40 pt ("No Action" too: its action is empty).
        case discrete
        case channel(Channel)
    }

    struct Roles: Equatable {
        var up: Role
        var down: Role
        var left: Role
        var right: Role

        subscript(direction: MouseGestureDirection) -> Role {
            switch direction {
            case .up: return up
            case .down: return down
            case .left: return left
            case .right: return right
            }
        }
    }

    struct Configuration: Equatable {
        /// What each direction does in this hold.
        var roles: Roles
        /// Travel before the hold locks. Mac Mouse Fix starts at 7 px; 8 keeps a little
        /// more room for an unsteady click.
        var lockDistance: CGFloat = 8
        var dominanceRatio: CGFloat = MouseGestureRecognizer.defaultDominanceRatio
        /// Movement inside this window before the release decides between end and cancel
        /// and gives the release velocity.
        var velocityWindow: TimeInterval = 0.08
        /// A hold older than this is abandoned, in case the button-up was lost.
        var watchdogTimeout: TimeInterval = 10

        init(
            roles: Roles,
            lockDistance: CGFloat = 8,
            dominanceRatio: CGFloat = MouseGestureRecognizer.defaultDominanceRatio,
            velocityWindow: TimeInterval = 0.08,
            watchdogTimeout: TimeInterval = 10
        ) {
            self.roles = roles
            self.lockDistance = lockDistance
            self.dominanceRatio = dominanceRatio
            self.velocityWindow = velocityWindow
            self.watchdogTimeout = watchdogTimeout
        }

        /// The hold whose only motion is the Spaces swipe: sideways follows the hand, up
        /// and down run one action each. Give `roles.up` / `roles.down` a channel afterwards
        /// to let them follow too.
        ///
        /// - progressPerPoint: swipe progress per point of pointer travel, tracking speed
        ///   included (`DockSwipeGeometry.progressPerPoint`).
        /// - maximumProgress: largest progress in either direction: one Space
        ///   (`DockSwipeGeometry.progressPerSpace`). See `advance`.
        /// - invertHorizontal: off: the desktop moves with the hand (moving left brings in
        ///   the Space on the right). On: the opposite.
        init(
            progressPerPoint: Double,
            maximumProgress: Double,
            invertHorizontal: Bool,
            lockDistance: CGFloat = 8,
            dominanceRatio: CGFloat = MouseGestureRecognizer.defaultDominanceRatio,
            velocityWindow: TimeInterval = 0.08,
            watchdogTimeout: TimeInterval = 10
        ) {
            func spaces(_ sign: Double) -> Role {
                .channel(Channel(
                    motion: .horizontal,
                    sign: sign,
                    progressPerPoint: progressPerPoint,
                    maximumProgress: maximumProgress,
                    crossesStart: true,
                    beginsAtLock: true
                ))
            }
            self.init(
                roles: Roles(
                    up: .discrete,
                    down: .discrete,
                    // The desktop follows the hand: moving left pulls in the next Space.
                    left: spaces(invertHorizontal ? -1 : 1),
                    right: spaces(invertHorizontal ? 1 : -1)
                ),
                lockDistance: lockDistance,
                dominanceRatio: dominanceRatio,
                velocityWindow: velocityWindow,
                watchdogTimeout: watchdogTimeout
            )
        }
    }

    enum Command: Equatable {
        case begin(DockSwipeAxis)
        /// Cumulative progress of the motion that began, in that motion's own sense
        /// (sideways: positive = towards the next Space). Inside its channel's range.
        case update(Double)
        /// Let macOS complete or revert; velocity in progress units per second.
        case end(velocity: Double)
        case cancel
        /// Run the action configured for this direction (one whose role is discrete).
        case discrete(MouseGestureDirection)
        /// Run the click action.
        case click

        var isSwipeCommand: Bool {
            switch self {
            case .begin, .update, .end, .cancel: return true
            case .discrete, .click: return false
            }
        }
    }

    enum Phase: Equatable {
        case armed
        case swiping
        /// Past the lock without a motion: the first direction at 40 pt decides.
        case discrete
        case finished
    }

    /// Velocity is never computed over less than this, so two samples that are almost
    /// simultaneous cannot produce an absurd value.
    private static let minimumVelocityInterval: TimeInterval = 1.0 / 60.0

    let configuration: Configuration
    let startTime: TimeInterval

    private(set) var phase = Phase.armed
    /// What the Dock has been told: kept inside the followed channel's range.
    private(set) var progress: Double = 0
    /// The direction whose motion began; nil until one did. It never changes afterwards.
    private(set) var followedDirection: MouseGestureDirection?
    /// That direction's channel.
    private(set) var followedChannel: Channel?
    /// What a point of travel along the followed axis does to the progress: +1 or -1.
    private var followedSense: Double = 0
    /// Where the hand is, without the range. Decides the direction and speed of a release.
    private var handProgress: Double = 0
    /// The same in points of travel, for the reverse tolerance.
    private var handTravel: CGFloat = 0
    /// Recent positions of the hand, oldest first.
    private var samples: [(time: TimeInterval, progress: Double, travel: CGFloat)] = []
    /// Classic recognizer, fed from the first movement: click tolerance and first direction.
    private var recognizer = MouseGestureRecognizer()

    init(configuration: Configuration, startTime: TimeInterval) {
        self.configuration = configuration
        self.startTime = startTime
    }

    // MARK: - Input

    /// Pointer movement (CGEvent deltas: +x right, +y down) at a monotonic time.
    mutating func move(deltaX: CGFloat, deltaY: CGFloat, at time: TimeInterval) -> [Command] {
        guard phase != .finished else { return [] }
        if hasExpired(at: time) { return abandon() }
        guard deltaX != 0 || deltaY != 0 else { return [] }

        let recognized = recognizer.append(deltaX: deltaX, deltaY: deltaY)
        switch phase {
        case .armed:
            return lockIfPossible(deltaX: deltaX, deltaY: deltaY, recognized: recognized, time: time)
        case .swiping:
            return advance(byPoints: alongFollowedAxis(deltaX, deltaY), at: time)
        case .discrete:
            return firstDirectionCommands(deltaX: deltaX, deltaY: deltaY, recognized: recognized, time: time)
        case .finished:
            return []
        }
    }

    /// The button was released. `pendingDeltaX` / `pendingDeltaY` is movement that arrived
    /// after the last `move`. While swiping it only informs the end / cancel decision and the velocity:
    /// the terminal event follows at once, so it is not sent as one more update.
    mutating func release(pendingDeltaX: CGFloat = 0, pendingDeltaY: CGFloat = 0, at time: TimeInterval) -> [Command] {
        guard phase != .finished else { return [] }
        if hasExpired(at: time) { return abandon() }

        var commands: [Command] = []
        if phase == .swiping {
            if pendingDeltaX != 0 || pendingDeltaY != 0 {
                _ = recognizer.append(deltaX: pendingDeltaX, deltaY: pendingDeltaY)
                recordHandMovement(byPoints: alongFollowedAxis(pendingDeltaX, pendingDeltaY), at: time)
            }
        } else {
            commands = move(deltaX: pendingDeltaX, deltaY: pendingDeltaY, at: time)
        }

        switch phase {
        case .armed, .discrete:
            // Same rule as the classic mode: no direction recognized and barely moved.
            if recognizer.shouldReplayClick {
                commands.append(.click)
            }
        case .swiping:
            commands.append(terminalCommand(at: time))
        case .finished:
            break
        }
        phase = .finished
        return commands
    }

    /// The hold was interrupted (event tap disabled, sleep, quit). Reverts a running swipe.
    mutating func cancel() -> [Command] {
        return abandon()
    }

    /// Called when the watchdog timer fires; inputs past the timeout have the same effect.
    mutating func expire() -> [Command] {
        return abandon()
    }

    // MARK: - Lock

    private mutating func lockIfPossible(
        deltaX: CGFloat,
        deltaY: CGFloat,
        recognized: MouseGestureDirection?,
        time: TimeInterval
    ) -> [Command] {
        let displacement = recognizer.displacement
        let horizontal = abs(displacement.x)
        let vertical = abs(displacement.y)
        guard max(horizontal, vertical) >= configuration.lockDistance else { return [] }

        let towards: MouseGestureDirection
        if horizontal >= vertical * configuration.dominanceRatio {
            towards = displacement.x < 0 ? .left : .right
        } else if vertical >= horizontal * configuration.dominanceRatio {
            towards = displacement.y < 0 ? .up : .down
        } else {
            // Diagonal: wait until one axis clearly dominates.
            return []
        }

        if case .channel(let channel) = configuration.roles[towards], channel.beginsAtLock {
            return begin(channel, towards: towards, deltaX: deltaX, deltaY: deltaY, time: time)
        }
        phase = .discrete
        return firstDirectionCommands(deltaX: deltaX, deltaY: deltaY, recognized: recognized, time: time)
    }

    /// A hold that began no motion at the lock is decided by its first direction at 40 pt,
    /// whatever its first 8 pt were: a discrete direction runs its action, once (the
    /// recognizer commits one direction per hold, so nothing follows it); a channel begins
    /// its motion.
    ///
    /// That is also the way out for a hold whose first 8 pt were vertical by mistake (the
    /// jolt of the press) and whose hand then went sideways: it did nothing until the
    /// button was released and pressed again, however far it went. It becomes the swipe
    /// from here: nothing ran before.
    private mutating func firstDirectionCommands(
        deltaX: CGFloat,
        deltaY: CGFloat,
        recognized: MouseGestureDirection?,
        time: TimeInterval
    ) -> [Command] {
        guard let recognized else { return [] }
        switch configuration.roles[recognized] {
        case .discrete:
            return [.discrete(recognized)]
        case .channel(let channel):
            return begin(channel, towards: recognized, deltaX: deltaX, deltaY: deltaY, time: time)
        }
    }

    private mutating func begin(
        _ channel: Channel,
        towards direction: MouseGestureDirection,
        deltaX: CGFloat,
        deltaY: CGFloat,
        time: TimeInterval
    ) -> [Command] {
        phase = .swiping
        followedDirection = direction
        followedChannel = channel
        // CGEvent deltas: left and up are negative.
        let alongAxis: Double = direction == .left || direction == .up ? -1 : 1
        followedSense = alongAxis * (channel.sign < 0 ? -1 : 1)
        samples = [(time, 0, 0)]
        // Progress starts with the movement that began the motion, so nothing jumps by the
        // travel spent before it.
        return [.begin(channel.motion)] + advance(byPoints: alongFollowedAxis(deltaX, deltaY), at: time)
    }

    // MARK: - Motion

    /// Only movement along the followed direction's axis counts once a motion began.
    private func alongFollowedAxis(_ deltaX: CGFloat, _ deltaY: CGFloat) -> CGFloat {
        switch followedDirection {
        case .up, .down: return deltaY
        case .left, .right, nil: return deltaX
        }
    }

    private func progressStep(forPoints points: CGFloat) -> Double {
        guard let channel = followedChannel else { return 0 }
        return Double(points) * followedSense * channel.progressPerPoint
    }

    private mutating func recordHandMovement(byPoints points: CGFloat, at time: TimeInterval) {
        handProgress += progressStep(forPoints: points)
        handTravel += points * CGFloat(followedSense)
        samples.append((time, handProgress, handTravel))
        // Keep the window plus the one sample that tells where the hand was when it opened.
        let windowStart = time - configuration.velocityWindow
        while samples.count >= 2, samples[1].time <= windowStart {
            samples.removeFirst()
        }
    }

    /// Progress stays inside the channel's range. Sideways that is one Space in either
    /// direction: one hold crosses at most one Space, and at the first or last Space the
    /// over-swipe stays within what a trackpad can produce (swiping much further than that
    /// can wedge the Dock). Movement past either end of the range is dropped, not stored,
    /// so turning back responds at once: at the far end, and behind the start of a motion
    /// that does not cross it.
    private mutating func advance(byPoints points: CGFloat, at time: TimeInterval) -> [Command] {
        recordHandMovement(byPoints: points, at: time)
        guard let range = followedChannel?.progressRange else { return [] }
        let next = min(max(progress + progressStep(forPoints: points), range.lowerBound), range.upperBound)
        guard next != progress else { return [] }
        progress = next
        return [.update(progress)]
    }

    private func terminalCommand(at time: TimeInterval) -> Command {
        let windowStart = time - configuration.velocityWindow
        // Where the hand was when the window opened; where the motion began if it is younger.
        let baseline = samples.last { $0.time <= windowStart } ?? samples.first ?? (time, handProgress, handTravel)
        let recentMovement = handProgress - baseline.progress

        // At the start: as it was before the hold.
        guard progress != 0 else { return .cancel }
        if recentMovement * progress < 0 {
            // Heading back towards the start: as it was before the hold, unless the channel
            // takes so little travel back for the jolt of letting go.
            let tolerance = followedChannel?.reverseTolerance ?? 0
            guard tolerance > 0, abs(handTravel - baseline.travel) <= tolerance else { return .cancel }
            return .end(velocity: 0)
        }
        let elapsed = min(configuration.velocityWindow, time - baseline.time)
        return .end(velocity: bounded(recentMovement / max(elapsed, Self.minimumVelocityInterval)))
    }

    private func bounded(_ velocity: Double) -> Double {
        guard let channel = followedChannel, let perSecond = channel.maximumTravelsPerSecond else { return velocity }
        let limit = perSecond * channel.maximumProgress
        // A bound that is no number from 0 up bounds nothing.
        guard limit >= 0 else { return velocity }
        return min(max(velocity, -limit), limit)
    }

    // MARK: - Release outcome

    /// A released swipe that covered this share of one Space ...
    static let switchProgressShare: Double = 0.5
    /// ... or was still moving towards the next Space this fast (Spaces per second) is
    /// expected to switch.
    static let switchSpacesPerSecond: Double = 1

    /// Whether a swipe released with `end(velocity:)` is expected to switch Spaces, or to
    /// open what another motion opens. Only cues depend on it: macOS makes the real
    /// decision from the same two values, with thresholds of its own.
    ///
    /// Rule: the motion is at least halfway to its full progress, or the hand was still
    /// moving that way at one whole motion (one Space) per second or more. "That way" is
    /// the sign of the progress, so it reads the same for a channel of negative sign.
    func isExpectedToSwitch(releaseVelocity: Double) -> Bool {
        let whole = followedChannel?.maximumProgress ?? 0
        guard progress != 0, whole > 0 else { return false }
        let towardsSwitch: Double = progress > 0 ? 1 : -1
        let share = abs(progress) / whole
        let wholesPerSecond = releaseVelocity * towardsSwitch / whole
        return share >= Self.switchProgressShare || wholesPerSecond >= Self.switchSpacesPerSecond
    }

    // MARK: - Abandon

    private func hasExpired(at time: TimeInterval) -> Bool {
        return time - startTime >= configuration.watchdogTimeout
    }

    private mutating func abandon() -> [Command] {
        guard phase != .finished else { return [] }
        let wasSwiping = phase == .swiping
        phase = .finished
        return wasSwiping ? [.cancel] : []
    }
}
