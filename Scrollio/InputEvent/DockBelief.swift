//
//  DockBelief.swift
//  Scrollio
//
//  What Scrollio believes the Dock shows because Scrollio itself put it up.
//
//  The Dock tells nobody which of its views is showing (Mission Control, Show Desktop,
//  Launchpad / Apps), and a swipe has no "toggle": the sign that opens a view does nothing
//  when the view is already there, and the sign that closes it opens its neighbour when it
//  is not. So a hold that follows the hand ("Up and Down follow the hand too") cannot close
//  what it opened by the same move, unless Scrollio remembers what it opened.
//
//  The belief is that memory: the view Scrollio's own last followed swipe, or its own
//  instant toggle, put up. It is one value, kept while the app runs and stored nowhere, and
//  nothing is read from the Dock for it. It may be wrong (the view was left with Esc, a
//  click or a trackpad), so it is only ever used in ways that are safe when it is:
//
//  - the direction whose own view is believed to show runs its action once, as it always
//    did (the instant toggle: the same move again closes the view; had the view gone
//    meanwhile, the toggle opens it, which is what that direction means);
//  - while Mission Control is believed to show, the opposite direction leaves it with the
//    hand, as a trackpad's swipe down does (the one closing sign that does nothing where
//    Mission Control is not showing);
//  - everything else is as without a belief.
//
//  It is dropped after a minute, when another app comes to the front, when the desktop in
//  use changes and when Scrollio stops (sleep, Pause): `InputProcessor` owns the value and
//  those moments. Pure: no clock, no notification, nothing of the system.
//

import Foundation

struct DockBelief: Equatable {

    /// A belief older than this is no belief: a view is not left open for long, and every
    /// way of leaving it that Scrollio does not see makes the belief wrong.
    static let lifetime: TimeInterval = 60

    private var view: DockFollowTarget?
    /// When the view was put up (a monotonic time).
    private var since: TimeInterval = 0

    /// The view believed to show at `now`; nil without one, or when it is too old.
    func view(at now: TimeInterval) -> DockFollowTarget? {
        guard let view, now - since < Self.lifetime, now >= since else { return nil }
        return view
    }

    /// A hold that followed the hand towards `target` was let go and is expected to open
    /// it. The two ends of one motion are a slider with the desktop in the middle (Show
    /// Desktop, the desktop, Apps): a hold towards the other end of the believed view's
    /// own motion steps back to the desktop and shows no view.
    mutating func holdOpened(_ target: DockFollowTarget, at now: TimeInterval) {
        if let showing = view(at: now), showing != target, showing.axis == target.axis {
            drop()
            return
        }
        view = target
        since = now
    }

    /// Scrollio asked the Dock for `target` in one go (by name, or by its key): a toggle.
    /// It closes the view that is believed to show, and puts up any other.
    mutating func toggled(_ target: DockFollowTarget, at now: TimeInterval) {
        if view(at: now) == target {
            drop()
            return
        }
        view = target
        since = now
    }

    /// Nothing is believed any more: a hold left the view with the hand, another app came
    /// to the front, the desktop in use changed, Scrollio stopped.
    mutating func drop() {
        view = nil
        since = 0
    }

    // MARK: - What a hold does about it

    /// What a belief makes of one direction (Up or Down) of a hold.
    enum Move: Equatable {
        /// Nothing: the direction does what its plan says.
        case asPlanned
        /// The direction's own view is believed to show: it runs its action once (the
        /// instant toggle, which closes the view) instead of following the hand.
        case toggle(DockFollowTarget)
        /// Mission Control is believed to show and the other direction opens it with the
        /// hand: this one leaves it with the hand, instead of its own action.
        case leaveMissionControl
    }

    /// What `believed` makes of a direction whose plan is `plan`, while the opposite
    /// direction's is `opposite`. Only a direction that would follow changes: one that
    /// runs once anyway toggles as it is. And Mission Control is only left with the hand
    /// where the opposite direction opens it with the hand on this Mac now: the same
    /// motion, so the Dock takes it.
    static func move(for plan: DockFollowPlan, opposite: DockFollowPlan, believed: DockFollowTarget?) -> Move {
        guard let believed else { return .asPlanned }
        if plan == .follows(believed) {
            return .toggle(believed)
        }
        if believed == .missionControl, opposite == .follows(.missionControl) {
            return .leaveMissionControl
        }
        return .asPlanned
    }
}
