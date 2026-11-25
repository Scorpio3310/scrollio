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
//  Nothing here posts an event, and nothing is written anywhere: four Booleans of the
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
    /// The bound of the release velocity, in whole travels (`fullProgress`) per second:
    /// about what a trackpad can send. A larger one shows as a jolt, most of all in the
    /// pinch. (For the two new motions only.)
    static let maximumTravelsPerSecond: Double = 12

    /// The share of the whole travel a view must have moved, as the Dock was told, for a
    /// hold to count as one that opened it with the hand. Below it a release that is
    /// expected to open is a flick: the hand was fast, but the view had barely moved, and
    /// whether the Dock would finish such a motion is its own secret.
    static let flickFloor: Double = 0.2
    /// macOS tells that the desktop in use changed up to about half a second after a swipe
    /// of the desktops ended. For this long after the end of Scrollio's own swipe of the
    /// desktops (a hold's or the thumb wheel's), such a change is taken for that swipe's:
    /// it takes back no view that is opening and leaves the belief alone.
    static let lateDesktopChange: TimeInterval = 1

    /// The share of the travel a target takes.
    static func travelFactor(for target: DockFollowTarget) -> CGFloat {
        switch target {
        case .missionControl, .showDesktop: return 1
        case .apps: return appsTravelFactor
        }
    }
}

// MARK: - The Dock's own switches

/// The Dock's switches for its trackpad gestures (System Settings › Trackpad › More
/// Gestures). A swipe whose gesture is switched off there is ignored by the Dock, silently,
/// so such a direction must run its action once instead. Read only: Scrollio never writes
/// one of them, never restarts the Dock, and reads nothing else of the Dock's settings.
struct DockGestureSwitches: Equatable {
    var missionControl: Bool
    var showDesktop: Bool
    var launchpad: Bool
    /// The gesture for App Exposé (an app's windows). Scrollio drives nothing towards it;
    /// it is read because it is the other end of Mission Control's motion: where it is on,
    /// the swipe that leaves Mission Control opens App Exposé from the desktop, so
    /// Mission Control is not left with the hand there (`DockBelief.move`).
    var appExpose: Bool

    /// Every gesture Scrollio drives is on, and App Exposé's is off: a Mac on which none
    /// of them was ever changed (macOS ships them so), and what a test run sees.
    static let allOn = DockGestureSwitches(missionControl: true, showDesktop: true, launchpad: true)

    /// The four names in the Dock's settings.
    enum Key: String, CaseIterable {
        case missionControl = "showMissionControlGestureEnabled"
        case showDesktop = "showDesktopGestureEnabled"
        case launchpad = "showLaunchpadGestureEnabled"
        case appExpose = "showAppExposeGestureEnabled"

        /// What a name that is not stored counts as. The three gestures Scrollio drives
        /// are on until someone turns one off; App Exposé's is off until someone turns it on.
        var isOnWhenMissing: Bool {
            switch self {
            case .missionControl, .showDesktop, .launchpad: return true
            case .appExpose: return false
            }
        }
    }

    /// The Dock's settings.
    static let domain = "com.apple.dock"

    init(missionControl: Bool, showDesktop: Bool, launchpad: Bool, appExpose: Bool = false) {
        self.missionControl = missionControl
        self.showDesktop = showDesktop
        self.launchpad = launchpad
        self.appExpose = appExpose
    }

    /// Pure: the four switches from what is stored under their names.
    init(reading value: (Key) -> Any?) {
        func isOn(_ key: Key) -> Bool {
            return Self.isOn(value(key), whenMissing: key.isOnWhenMissing)
        }
        self.init(
            missionControl: isOn(.missionControl),
            showDesktop: isOn(.showDesktop),
            launchpad: isOn(.launchpad),
            appExpose: isOn(.appExpose)
        )
    }

    /// A stored "false" (or the number 0) is off, a stored "true" on. A missing name counts
    /// as `whenMissing` (`Key.isOnWhenMissing`: macOS has the gestures Scrollio drives on
    /// until someone turns one off, and a Mac without a trackpad has no place to do that).
    /// Anything else that is stored counts as on: the values are another app's data and may
    /// be anything. (For App Exposé that is the careful side too: on means "do not leave
    /// Mission Control with the hand".)
    static func isOn(_ value: Any?, whenMissing: Bool = true) -> Bool {
        guard let value else { return whenMissing }
        guard let number = value as? NSNumber else { return true }
        return number.boolValue
    }

    /// Whether the switch that governs `target` on macOS `majorVersion` is on. Since macOS
    /// 26 there is no switch for Launchpad's successor: the Show Desktop one stands for
    /// both ends of the pinch.
    func allows(_ target: DockFollowTarget, majorVersion: Int) -> Bool {
        switch target {
        case .missionControl: return missionControl
        case .showDesktop: return showDesktop
        case .apps: return majorVersion >= 26 ? showDesktop : launchpad
        }
    }

    // MARK: Reading

    /// Where a name's value comes from; a test gives its own.
    static var read: (Key) -> Any? = DockGestureSwitches.systemValue

    /// One value of the Dock's settings, by name. Nothing else of them is asked for (the
    /// whole domain would hold the Dock's apps and folders).
    static func systemValue(_ key: Key) -> Any? {
        // Under XCTest nothing of the Mac's own settings is read: every switch counts as on.
        guard !AppRuntime.isRunningXCTest else { return nil }
        return CFPreferencesCopyAppValue(key.rawValue as CFString, domain as CFString)
    }

    /// What the switches said when they were last read (`reload`); all on before that.
    /// What is stored is what System Settings wrote, which the running Dock normally
    /// follows; it is a strong hint, not the Dock's own word. Main thread.
    private(set) static var current = DockGestureSwitches.allOn

    /// Posted (no object) when a read found the switches changed: the Gestures pane says
    /// which views open with the hand on this Mac.
    static let didChangeNotification = Notification.Name("ScrollioDockGestureSwitchesDidChange")

    /// Reads the four switches again: when Scrollio starts, when it becomes active and
    /// when System Settings goes to the background, where a switch may just have been
    /// changed (`AppDelegate`, beside the Spaces shortcuts). Never from an event tap's
    /// callback: a hold takes `current`. Main thread.
    static func reload() {
        let found = DockGestureSwitches(reading: read)
        guard found != current else { return }
        current = found
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}

// MARK: - Whether it follows on this Mac

/// Whether a target follows the hand on this Mac now. A value: every input is one of its
/// members, so the answer is a pure table that a test fills in as it likes; `live` reads
/// them from the running app.
struct DockFollowAvailability: Equatable {

    /// Why a target does not follow, the most lasting reason first (the order they are
    /// looked at).
    enum Obstacle: Equatable {
        /// The view is not known to follow on this macOS: it runs once here.
        case notOnThisMacOS
        /// The swipe cannot be built on this Mac (`DockSwipeSynthesizer.isAvailable`):
        /// nothing follows the hand here, the desktops neither.
        case swipeUnavailable
        /// The Dock's own switch for this trackpad gesture is off: it would ignore the swipe.
        case gestureOff
        /// macOS does not let Scrollio post events at the moment.
        case cannotPostEvents
    }

    /// `DockSwipeSynthesizer.shared.isAvailable`.
    var swipeIsAvailable: Bool
    /// `ScrollPoster.shared.canPostEvents`.
    var canPostEvents: Bool
    /// The macOS major version (14, 15, 26, 27 …).
    var majorVersion: Int
    /// The Dock's own switches.
    var switches: DockGestureSwitches
    /// Whether Apps may follow at all in this build (`appsFollowInThisBuild`).
    var appsMayFollow: Bool

    /// The first macOS on which the pinch is driven: a synthesized spread is reported to
    /// show the desktop there (Mac Mouse Fix, the "hid" layout), and it is the macOS it can
    /// be watched on. Below it nobody here could try it (the "fields" layout, with its own
    /// sign and an Apple bug in the release velocity before macOS 26), so Show Desktop runs
    /// once there.
    static let firstPinchMajorVersion = 27

    /// Apps follows the hand only in a build made with SCROLLIO_TRACE, which
    /// `scripts/install.sh` passes for the owner's own installed copy, so that it can be
    /// seen on a real Mac whether the Apps view tracks a pinch at all (Launchpad's
    /// successor is no view of the Dock's own, and the one public report calls it laggy).
    /// A release, a debug build and the tests keep Apps instant.
    static let appsFollowInThisBuild: Bool = {
        #if SCROLLIO_TRACE
        return true
        #else
        return false
        #endif
    }()

    /// The table of macOS versions: Mission Control on every macOS Scrollio runs on, Show
    /// Desktop from `firstPinchMajorVersion`, Apps there too and only where a build lets it.
    static func isKnownToFollow(_ target: DockFollowTarget, majorVersion: Int, appsMayFollow: Bool) -> Bool {
        switch target {
        case .missionControl: return true
        case .showDesktop: return majorVersion >= firstPinchMajorVersion
        case .apps: return appsMayFollow && majorVersion >= firstPinchMajorVersion
        }
    }

    /// What keeps `target` from following the hand; nil: it follows.
    func obstacle(to target: DockFollowTarget) -> Obstacle? {
        guard Self.isKnownToFollow(target, majorVersion: majorVersion, appsMayFollow: appsMayFollow) else {
            return .notOnThisMacOS
        }
        guard swipeIsAvailable else { return .swipeUnavailable }
        guard switches.allows(target, majorVersion: majorVersion) else { return .gestureOff }
        guard canPostEvents else { return .cannotPostEvents }
        return nil
    }

    func follows(_ target: DockFollowTarget) -> Bool {
        return obstacle(to: target) == nil
    }

    /// The targets that follow the hand, in the order of `DockFollowTarget.allCases` (for
    /// the pane's line about what opens with the hand on this Mac).
    var targetsThatFollow: [DockFollowTarget] {
        return DockFollowTarget.allCases.filter(follows)
    }

    /// The answer for this Mac at this moment. Cheap enough for the press of a gesture
    /// button (no read of anything outside the process: the Dock's switches are the cached
    /// ones). Under XCTest the swipe is unavailable unless a test gave the synthesizer a
    /// driver, and the switches are all on; a test of the table makes its own value.
    /// Main thread.
    static var live: DockFollowAvailability {
        return DockFollowAvailability(
            swipeIsAvailable: DockSwipeSynthesizer.shared.isAvailable,
            canPostEvents: ScrollPoster.shared.canPostEvents,
            majorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
            switches: DockGestureSwitches.current,
            appsMayFollow: appsFollowInThisBuild
        )
    }
}

// MARK: - What a direction follows

/// What a direction of a hold does about following the hand.
enum DockFollowPlan: Equatable {
    /// It drives the target's motion with the hand.
    case follows(DockFollowTarget)
    /// The settings ask for it (the mode, the switch, an action with a target), but this
    /// Mac does not do it now: the direction runs its action once, as before. The obstacle
    /// is for the pane's help and for the log.
    case cannotFollow(DockFollowTarget, DockFollowAvailability.Obstacle)
    /// Nothing asks for it: the direction runs its action once, as before (sideways, which
    /// is the desktops' in "Follow the hand"; "One action per hold"; the switch off; an
    /// action without a view to open).
    case doesNotFollow

    /// The target that follows; nil for both ways of running once.
    var target: DockFollowTarget? {
        if case .follows(let target) = self { return target }
        return nil
    }
}

extension MouseGestureSettings {

    /// What `direction` follows with these settings on a Mac with this availability: the
    /// one place that says so, for the hold (asked once, when the button goes down) and for
    /// the pane's rows. Only Up and Down can follow; Left and Right stay what they are in
    /// "Follow the hand", the desktops. For an app's own set, ask the settings that run in
    /// the app (`Application.gesturesThatRun`).
    func followPlan(for direction: MouseGestureDirection, availability: DockFollowAvailability) -> DockFollowPlan {
        guard actionsFollowNow, direction == .up || direction == .down,
              let target = DockFollowTarget(action: action(for: direction)) else {
            return .doesNotFollow
        }
        if let obstacle = availability.obstacle(to: target) {
            return .cannotFollow(target, obstacle)
        }
        return .follows(target)
    }
}
