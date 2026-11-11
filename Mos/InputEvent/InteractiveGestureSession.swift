//
//  InteractiveGestureSession.swift
//  Mos
//
//  State machine of one gesture-button hold in "follow the hand" mode. Pure: it takes
//  movement and time and returns commands; `InputProcessor` turns the commands into dock
//  swipe events and actions.
//
//      armed ──horizontal lock──▶ swiping ──release / cancel / watchdog──▶ finished
//        │                                                                     ▲
//        └────vertical lock────▶ discrete ──release / cancel / watchdog────────┘
//
//  - armed: the button is down. Once the pointer has travelled `lockDistance` and one axis
//    clearly dominates, the hold locks to that axis.
//  - swiping: sideways movement drives the Spaces swipe. Emits `begin` once, then `update`
//    with the cumulative progress, then exactly one of `end` or `cancel`.
//  - discrete: a vertical hold behaves like the classic mode: the up or down action fires
//    once at the usual 40 pt, and a hold that barely moved is a click.
//

import Cocoa

struct InteractiveGestureSession {

    struct Configuration: Equatable {
        /// Swipe progress per point of pointer travel, tracking speed included
        /// (`DockSwipeGeometry.progressPerPoint`).
        var progressPerPoint: Double
        /// Largest progress in either direction: one Space
        /// (`DockSwipeGeometry.progressPerSpace`). See `advance`.
        var maximumProgress: Double
        /// Off: the desktop moves with the hand (moving left brings in the Space on the
        /// right). On: the opposite.
        var invertHorizontal: Bool
        /// Travel before the hold locks to an axis. Mac Mouse Fix starts at 7 px; 8 keeps a
        /// little more room for an unsteady click.
        var lockDistance: CGFloat = 8
        var dominanceRatio: CGFloat = MouseGestureRecognizer.defaultDominanceRatio
        /// Movement inside this window before the release decides between end and cancel
        /// and gives the release velocity.
        var velocityWindow: TimeInterval = 0.08
        /// A hold older than this is abandoned, in case the button-up was lost.
        var watchdogTimeout: TimeInterval = 10
    }

    enum Command: Equatable {
        case begin(DockSwipeAxis)
        /// Cumulative progress; positive = towards the next Space.
        case update(Double)
        /// Let macOS complete or revert; velocity in progress units per second.
        case end(velocity: Double)
        case cancel
        /// Run the action configured for this direction (up or down only).
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
        case discrete
        case finished
    }

    /// Velocity is never computed over less than this, so two samples that are almost
    /// simultaneous cannot produce an absurd value.
    private static let minimumVelocityInterval: TimeInterval = 1.0 / 60.0

    let configuration: Configuration
    let startTime: TimeInterval

    private(set) var phase = Phase.armed
    /// What the Dock has been told: saturated at `maximumProgress`.
    private(set) var progress: Double = 0
    /// Where the hand is, without saturation. Decides the direction and speed of a release.
    private var handProgress: Double = 0
    /// Recent `(time, handProgress)` pairs, oldest first.
    private var samples: [(time: TimeInterval, progress: Double)] = []
    /// Classic recognizer, fed from the first movement: click tolerance and vertical actions.
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
            return lockAxisIfPossible(deltaX: deltaX, recognized: recognized, time: time)
        case .swiping:
            return advance(byPoints: deltaX, at: time)
        case .discrete:
            return discreteCommands(for: recognized)
        case .finished:
            return []
        }
    }

    /// The button was released. `pendingDelta` is movement that arrived after the last
    /// `move`. While swiping it only informs the end / cancel decision and the velocity:
    /// the terminal event follows at once, so it is not sent as one more update.
    mutating func release(pendingDeltaX: CGFloat = 0, pendingDeltaY: CGFloat = 0, at time: TimeInterval) -> [Command] {
        guard phase != .finished else { return [] }
        if hasExpired(at: time) { return abandon() }

        var commands: [Command] = []
        if phase == .swiping {
            if pendingDeltaX != 0 || pendingDeltaY != 0 {
                _ = recognizer.append(deltaX: pendingDeltaX, deltaY: pendingDeltaY)
                recordHandMovement(byPoints: pendingDeltaX, at: time)
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

    // MARK: - Axis lock

    private mutating func lockAxisIfPossible(
        deltaX: CGFloat,
        recognized: MouseGestureDirection?,
        time: TimeInterval
    ) -> [Command] {
        let horizontal = abs(recognizer.displacement.x)
        let vertical = abs(recognizer.displacement.y)
        guard max(horizontal, vertical) >= configuration.lockDistance else { return [] }

        if horizontal >= vertical * configuration.dominanceRatio {
            phase = .swiping
            samples = [(time, 0)]
            // Progress starts with the movement that crossed the threshold, so the desktop
            // does not jump by the travel spent on arming.
            return [.begin(.horizontal)] + advance(byPoints: deltaX, at: time)
        }
        if vertical >= horizontal * configuration.dominanceRatio {
            phase = .discrete
            return discreteCommands(for: recognized)
        }
        // Diagonal: wait until one axis clearly dominates.
        return []
    }

    /// Only up and down have actions here; sideways belongs to the swipe.
    private func discreteCommands(for recognized: MouseGestureDirection?) -> [Command] {
        guard let recognized, recognized == .up || recognized == .down else { return [] }
        return [.discrete(recognized)]
    }

    // MARK: - Swipe

    private func progressStep(forPoints points: CGFloat) -> Double {
        // The desktop follows the hand: moving left (negative x) pulls in the next Space.
        let direction: Double = configuration.invertHorizontal ? 1 : -1
        return Double(points) * direction * configuration.progressPerPoint
    }

    private mutating func recordHandMovement(byPoints points: CGFloat, at time: TimeInterval) {
        handProgress += progressStep(forPoints: points)
        samples.append((time, handProgress))
        // Keep the window plus the one sample that tells where the hand was when it opened.
        let windowStart = time - configuration.velocityWindow
        while samples.count >= 2, samples[1].time <= windowStart {
            samples.removeFirst()
        }
    }

    /// Progress saturates at one Space in either direction. One hold therefore crosses at
    /// most one Space, and at the first or last Space the over-swipe stays within what a
    /// trackpad can produce: swiping much further than that can wedge the Dock. Movement
    /// past the limit is dropped, not stored, so turning back responds at once.
    private mutating func advance(byPoints points: CGFloat, at time: TimeInterval) -> [Command] {
        recordHandMovement(byPoints: points, at: time)
        let limit = configuration.maximumProgress
        let next = min(max(progress + progressStep(forPoints: points), -limit), limit)
        guard next != progress else { return [] }
        progress = next
        return [.update(progress)]
    }

    private func terminalCommand(at time: TimeInterval) -> Command {
        let windowStart = time - configuration.velocityWindow
        // Where the hand was when the window opened; the lock point if the swipe is younger.
        let baseline = samples.last { $0.time <= windowStart } ?? samples.first ?? (time, handProgress)
        let recentMovement = handProgress - baseline.progress

        // Back at the origin, or heading back towards it: return to the starting Space.
        if progress == 0 || recentMovement * progress < 0 {
            return .cancel
        }
        let elapsed = min(configuration.velocityWindow, time - baseline.time)
        return .end(velocity: recentMovement / max(elapsed, Self.minimumVelocityInterval))
    }

    // MARK: - Release outcome

    /// A released swipe that covered this share of one Space ...
    static let switchProgressShare: Double = 0.5
    /// ... or was still moving towards the next Space this fast (Spaces per second) is
    /// expected to switch.
    static let switchSpacesPerSecond: Double = 1

    /// Whether a swipe released with `end(velocity:)` is expected to switch Spaces. Only the
    /// haptic "commit" cue depends on it: macOS makes the real decision from the same two
    /// values, with thresholds of its own.
    ///
    /// Rule: the desktop is at least halfway to the next Space, or the hand was still moving
    /// towards it at one Space per second or more.
    func isExpectedToSwitch(releaseVelocity: Double) -> Bool {
        let space = configuration.maximumProgress
        guard progress != 0, space > 0 else { return false }
        let towardsSwitch: Double = progress > 0 ? 1 : -1
        let share = abs(progress) / space
        let spacesPerSecond = releaseVelocity * towardsSwitch / space
        return share >= Self.switchProgressShare || spacesPerSecond >= Self.switchSpacesPerSecond
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
