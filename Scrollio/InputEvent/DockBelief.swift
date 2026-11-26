//
//  DockBelief.swift
//  Scrollio
//
//  Which view of the Dock is showing, as far as Scrollio knows.
//
//  A swipe has no "toggle": the sign that opens a view does nothing when the view is
//  already there, and the sign that closes it opens its neighbour when it is not. So a hold
//  that follows the hand ("Up and Down follow the hand too") must know what shows before it
//  moves anything: the direction whose view shows closes it, and the opposite direction
//  leaves it with the hand, as a trackpad's opposite gesture does, instead of putting its
//  own view on top.
//
//  Two sources, one value:
//
//  - The Dock's own word (`DockWord`, heard by `DockViewWatch`): it says when Mission
//    Control, an app's windows or the desktop is shown and when that view is left, however
//    it was opened (a hold, a key, a hot corner, the trackpad). A view the Dock named is
//    told: it stays until the Dock says it was left.
//  - What Scrollio did itself, where the Dock says nothing (Apps is not the Dock's own from
//    macOS 26 on, and the word may be missing on some Mac): a hold that opened a view with
//    the hand, and an instant toggle of a view while it was not taken to show, put that
//    view up. Such a view is only believed: it is given up after a minute, when another app
//    comes to the front or the desktop in use changes (`doubt`), and at a click of the
//    main mouse button (`clicked`: a click on a window, on the desktop or beside the panel
//    is how Mission Control and Apps are left), because every way of leaving it that
//    Scrollio does not see makes it wrong.
//
//  A believed view may be wrong (it was left with Esc or a click), so it is only used in
//  ways that cost one odd move at most when it is:
//
//  - the direction whose own view shows runs its action once, as it always did (the
//    instant toggle closes the view; had the view gone meanwhile, the toggle opens it,
//    which is what that direction means);
//  - the opposite direction leaves the view with the hand. Where the view is not showing
//    after all, that motion does nothing (Mission Control) or shows the other end of the
//    pinch (Show Desktop for Apps and the other way round), and the hold ends the belief,
//    so the move after it is the direction's own again. Mission Control that is only
//    believed is not left where the trackpad gesture for App Exposé is on
//    (`DockGestureSwitches.appExpose`): there the leaving swipe would open App Exposé from
//    the desktop. A told Mission Control is left there too: it is known to show;
//  - everything else is as without a view.
//
//  It is one value, kept while the app runs and stored nowhere. `InputProcessor` owns it
//  and the moments that change it. Pure: no clock, no notification, nothing of the system.
//

import Foundation

/// What the Dock says about its own views (its accessibility notifications, `DockViewWatch`).
enum DockWord: Equatable, CaseIterable {
    /// Mission Control is shown.
    case missionControl
    /// The windows of one app are shown (App Exposé): a view Scrollio opens nothing towards.
    case appWindows
    /// The desktop is shown (Show Desktop).
    case desktop
    /// The view was left: none of the three shows any more.
    case left
}

struct DockBelief: Equatable {

    /// A view that is only believed is given up after this long: a view is not left open
    /// for long, and every way of leaving it that Scrollio does not see makes it wrong.
    static let lifetime: TimeInterval = 60

    private var view: DockFollowTarget?
    /// When the view was put up (a monotonic time).
    private var since: TimeInterval = 0
    /// The Dock itself said that `view` shows.
    private var isTold = false

    /// The view taken to show at `now`; nil without one, or when a believed one is too old.
    func view(at now: TimeInterval) -> DockFollowTarget? {
        guard let view else { return nil }
        if isTold { return view }
        guard now - since < Self.lifetime, now >= since else { return nil }
        return view
    }

    /// Whether the view taken to show at `now` is the Dock's own word.
    func isTold(at now: TimeInterval) -> Bool {
        return isTold && view(at: now) != nil
    }

    // MARK: - What changes it

    /// A hold that followed the hand towards `target` was let go and is expected to open
    /// it. The two ends of one motion are a slider with the desktop in the middle (Show
    /// Desktop, the desktop, Apps): a hold towards the other end of the shown view's own
    /// motion steps back to the desktop and shows no view.
    mutating func holdOpened(_ target: DockFollowTarget, at now: TimeInterval) {
        if let showing = view(at: now) {
            if showing == target {
                // Already taken to show (the Dock said so before the button came up).
                if !isTold { since = now }
                return
            }
            if showing.axis == target.axis {
                drop()
                return
            }
        }
        believe(target, at: now)
    }

    /// Scrollio asks the Dock for `target` in one go (a toggle, from a button, a gesture
    /// or the Shortcut Ring): it closes the view when that view is taken to show, and puts
    /// it up otherwise. Believed only: where the view was opened elsewhere and the Dock did
    /// not say so, the toggle closed it, and the belief is wrong until the next move.
    mutating func toggled(_ target: DockFollowTarget, at now: TimeInterval) {
        if view(at: now) == target {
            drop()
        } else {
            believe(target, at: now)
        }
    }

    /// The Dock said something about its views.
    mutating func dockSaid(_ word: DockWord, at now: TimeInterval) {
        switch word {
        case .missionControl:
            tell(.missionControl, at: now)
        case .desktop:
            tell(.showDesktop, at: now)
        case .appWindows:
            // A view Scrollio has no part in: none of its own shows.
            drop()
        case .left:
            // None of the Dock's three views shows. Apps is not among them (the Dock says
            // nothing about it), so a believed Apps stays.
            if view != .apps { drop() }
        }
    }

    /// A hold left the shown view with the hand. `completed`: it was let go as expected to
    /// close the view. A hold that was not (it fell back, or was taken back) leaves a told
    /// view as it is, since the Dock says when that one is gone; a believed view ends
    /// either way, whatever the Dock made of the hold: had it not been showing after all,
    /// the next move is the direction's own again, instead of nothing for up to a minute.
    mutating func holdLeft(completed: Bool, at now: TimeInterval) {
        if completed || !isTold(at: now) {
            drop()
        }
    }

    /// Something happened that makes a believed view unlikely (another app came to the
    /// front, the desktop in use changed, Scrollio stopped looking). A told view stays:
    /// the Dock says when it is left.
    mutating func doubt() {
        if !isTold {
            drop()
        }
    }

    /// The main mouse button was pressed somewhere outside Scrollio. In Mission Control a
    /// click chooses a window or the desktop, and beside Apps it closes the panel (on an
    /// app in it, it starts the app): either way the view is gone, with no app coming to
    /// the front where the same app stays there. So a believed Mission Control or Apps
    /// ends. Show Desktop stays: a click on a file on the desktop is what it is for. And a
    /// told view stays: the Dock says when it is left.
    mutating func clicked(at now: TimeInterval) {
        guard !isTold, let showing = view(at: now), showing != .showDesktop else { return }
        drop()
    }

    /// Nothing is taken to show any more.
    mutating func drop() {
        view = nil
        since = 0
        isTold = false
    }

    private mutating func believe(_ target: DockFollowTarget, at now: TimeInterval) {
        view = target
        since = now
        isTold = false
    }

    private mutating func tell(_ target: DockFollowTarget, at now: TimeInterval) {
        view = target
        since = now
        isTold = true
    }

    // MARK: - What a hold does about it

    /// What the shown view makes of one direction (Up or Down) of a hold.
    enum Move: Equatable {
        /// Nothing: the direction does what its plan says.
        case asPlanned
        /// The direction's own view shows: it runs its action once (the instant toggle,
        /// which closes the view) instead of following the hand.
        case toggle(DockFollowTarget)
        /// The view that the other direction opens with the hand shows: this one leaves
        /// it with the hand, instead of its own action.
        case leave(DockFollowTarget)
    }

    /// What `shown` makes of a direction whose plan is `plan`, while the opposite
    /// direction's is `opposite`. A view is only left with the hand where the opposite
    /// direction opens it with the hand on this Mac now (the same motion, so the Dock takes
    /// it). `isTold`: the Dock itself said the view shows. Mission Control that is only
    /// believed is not left where the Dock's trackpad gesture for App Exposé is on: the
    /// leaving swipe opens App Exposé when Mission Control is not showing after all, so the
    /// direction keeps its own plan there.
    static func move(
        for plan: DockFollowPlan, opposite: DockFollowPlan, shown: DockFollowTarget?, isTold: Bool = false,
        appExposeGestureIsOn: Bool
    ) -> Move {
        guard let shown else { return .asPlanned }
        if plan == .follows(shown) {
            return .toggle(shown)
        }
        guard opposite == .follows(shown) else { return .asPlanned }
        if shown == .missionControl, !isTold, appExposeGestureIsOn {
            return .asPlanned
        }
        return .leave(shown)
    }
}
