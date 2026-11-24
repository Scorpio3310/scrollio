//
//  DockFollow.swift
//  Scrollio
//
//  "Up and Down follow the hand too": what a direction of Gesture Navigation can open with
//  the hand, as the desktops follow it sideways, and whether it does on this Mac.
//
//  Three listed actions show a view of the Dock that a trackpad opens with a gesture of
//  its own (`DockFollowTarget`): Mission Control (the vertical dock swipe), Show Desktop
//  (the spread) and Launchpad / Apps (the pinch, the other end of the spread's motion).
//  In "Follow the hand", with the switch `MouseGestureSettings.actionsFollowHand` on, an
//  Up or Down direction that holds one of them drives that motion with the hand instead of
//  running the action once, where this Mac can do it (`DockFollowAvailability`): the swipe
//  can be built, macOS lets Scrollio post events, the Dock's own switch for that trackpad
//  gesture is not off (`DockGestureSwitches`, read only) and the view is known to follow
//  on this macOS. Everything else runs its action once at the usual distance, as before.
//
//  `MouseGestureSettings.followPlan(for:availability:)` is the one answer to "what does
//  this direction follow": the hold asks it when the button goes down, the Gestures pane
//  when it draws a row. The numbers of the two motions are in `DockFollowTuning`; the
//  events, their signs and the travel are in `DockSwipeSynthesizer.swift`.
//
//  Nothing here posts an event, and nothing is written anywhere: three Booleans of the
//  Dock's settings are read (`docs/privacy.md`), never under XCTest.
//

import Cocoa

// MARK: - What can follow

/// A view of the Dock that a held gesture button can open with the hand.
enum DockFollowTarget: String, CaseIterable, Equatable {
    case missionControl
    case showDesktop
    /// Launchpad, and Apps from macOS 26 on: the listed action "appExpose" (the F4 key).
    /// The stored name is older than its meaning: it is not App Exposé (an app's windows),
    /// which Scrollio lists no action for.
    case apps

    /// The target of a listed action, by its stored name; nil for every other action.
    init?(actionIdentifier: String) {
        switch actionIdentifier {
        case SystemShortcut.missionControl.identifier: self = .missionControl
        case SystemShortcut.showDesktop.identifier: self = .showDesktop
        case SystemShortcut.appExpose.identifier: self = .apps
        default: return nil
        }
    }

    /// The target of what a direction runs. A recorded key combination has none, whatever
    /// keys it sends: its stored name is its keys.
    init?(action: GestureAction) {
        self.init(actionIdentifier: action.action)
    }

    /// The listed action that shows this view in one go (its stored name).
    var actionIdentifier: String {
        switch self {
        case .missionControl: return SystemShortcut.missionControl.identifier
        case .showDesktop: return SystemShortcut.showDesktop.identifier
        case .apps: return SystemShortcut.appExpose.identifier
        }
    }

    /// The Dock's motion that opens it.
    var axis: DockSwipeAxis {
        switch self {
        case .missionControl: return .vertical
        case .showDesktop, .apps: return .pinch
        }
    }

    /// The sign of the progress that opens it, in Scrollio's convention for that motion
    /// (`DockSwipeAxis`): positive opens Mission Control and Show Desktop; Apps is the
    /// other end of the pinch.
    var sign: Double {
        switch self {
        case .missionControl, .showDesktop: return 1
        case .apps: return -1
        }
    }
}

// MARK: - The numbers

/// The numbers of the motions that follow the hand up and down, in one place. None of them
/// is stored; all are first values, to be tuned by hand on a real Mac.
enum DockFollowTuning {
    /// The progress at which a view is whole (the Dock's progress is a fraction, "1.0 =
    /// 100%"). A hold's progress stops there: more than a trackpad can send is never sent.
    static let fullProgress: Double = 1.0
    /// The hand's travel from nothing to whole at Swipe speed 1: this share of the height
    /// of the screen under the pointer…
    static let travelScreenShare: CGFloat = 0.40
    /// …kept within these bounds, in points (a small screen would make the view jump, a
    /// large one would ask for more than a hand on a mouse moves).
    static let travelRange: ClosedRange<CGFloat> = 320...600
    /// Apps gets a shorter travel: Launchpad answers the same pinch less than Show Desktop
    /// answers the spread.
    static let appsTravelFactor: CGFloat = 0.75
    /// What a hand may move back within the release's velocity window and still count as
    /// resting, in points: letting go of a thumb button jolts the mouse. (For the two new
    /// motions only; sideways stays as it is.)
    static let reverseTolerance: CGFloat = 8
    /// The bound of the release velocity, in progress per second: twelve full travels a
    /// second, about what a trackpad can send. A larger one shows as a jolt, most of all
    /// in the pinch. (For the two new motions only.)
    static let maximumVelocity: Double = 12 * fullProgress

    /// The share of the travel a target takes.
    static func travelFactor(for target: DockFollowTarget) -> CGFloat {
        switch target {
        case .missionControl, .showDesktop: return 1
        case .apps: return appsTravelFactor
        }
    }
}
