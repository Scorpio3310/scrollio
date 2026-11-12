//
//  WelcomeGuideFlow.swift
//  Mos
//  What the Welcome Guide shows and when, without views: its steps, which of them a run
//  shows, the state of the Accessibility step, whether the try area of the feel step is
//  smoothed, and the one stored value that says whether the guide was finished.
//
//  Who sees what:
//  - A new user (no `optionsExist` before the settings were first read) gets the whole
//    guide at launch, until it is finished: Done, Open Settings, or the window closed once
//    the access is allowed. Quitting half-way shows it again at the next launch.
//  - Everyone else (an update: the settings were there before the guide) counts as
//    finished, silently.
//    Without the access the app opens the Accessibility step alone.
//  - General › Welcome Guide and Help › Welcome Guide run the whole guide, the feel the
//    user has chosen selected.
//

import Foundation

/// One step of the guide, in the order they come.
enum WelcomeGuideStep: Int, CaseIterable {
    case welcome
    case access
    case feel
    case finish
}

/// Which steps a run of the guide shows.
enum WelcomeGuideFlow: Equatable {
    /// Welcome, Accessibility (unless Scrollio already runs with it), feel, finish.
    case full
    /// The Accessibility step alone: someone who finished the guide lost the access.
    case accessOnly

    /// - Parameter accessReady: the access is allowed and Scrollio runs (or the user paused
    ///   it): the Accessibility step has nothing to ask.
    func steps(accessReady: Bool) -> [WelcomeGuideStep] {
        switch self {
        case .full:
            return accessReady ? [.welcome, .feel, .finish] : [.welcome, .access, .feel, .finish]
        case .accessOnly:
            return [.access]
        }
    }

    /// The run the app opens by itself (at launch, on resume, for "Allow Accessibility
    /// Access…" and when the app is reopened without the access): the whole guide until it
    /// was finished, then only the Accessibility step.
    static func automatic(guideFinished: Bool) -> WelcomeGuideFlow {
        return guideFinished ? .accessOnly : .full
    }
}

/// Whether Scrollio's event handling runs (AppRunController), as the guide sees it.
enum WelcomeGuideRunState: Equatable {
    /// The event taps run.
    case running
    /// "Pause Scrollio" is on.
    case paused
    /// The access is there but an event tap could not be created; a timer tries again.
    case retrying
    /// Not started (yet): the access is missing, or the start has not happened.
    case stopped
}

/// What the Accessibility step shows.
enum WelcomeGuideAccessState: Equatable {
    /// Not allowed: the step asks for it.
    case missing
    /// Allowed; Scrollio is starting its event handling.
    case starting
    /// Allowed and Scrollio runs.
    case running
    /// Allowed and paused by the user: nothing to wait for.
    case paused
    /// Allowed, but Scrollio couldn't start and is trying again.
    case couldNotStart

    init(granted: Bool, run: WelcomeGuideRunState) {
        guard granted else {
            self = .missing
            return
        }
        switch run {
        case .running: self = .running
        case .paused: self = .paused
        case .retrying: self = .couldNotStart
        case .stopped: self = .starting
        }
    }

    var isGranted: Bool {
        return self != .missing
    }

    /// The guide may go on: the access is there and Scrollio runs (or was paused on purpose).
    var isReady: Bool {
        return self == .running || self == .paused
    }
}

/// Whether the engine smooths the feel step's try area (Scrollio's own window), and why not.
enum WelcomeGuideTryArea: Equatable {
    case smoothed
    /// The event taps do not run (no access yet, paused, could not start).
    case notRunning
    /// "Limit scrolling to these apps" is on and Scrollio is not on the list.
    case notInAppList
    /// "Smooth scrolling" is off for Scrollio's window (globally, or in its own rule).
    case smoothingOff

    /// - Parameters:
    ///   - running: the event taps run.
    ///   - rule: what the per-app list holds for Scrollio.
    static func state(
        running: Bool, rule: AppSmoothing.Rule, scrollingSmooth: Bool, limitedToListedApps: Bool
    ) -> WelcomeGuideTryArea {
        guard running else { return .notRunning }
        let decision = AppSmoothing.decide(rule: rule, scrollingSmooth: scrollingSmooth, limitedToListedApps: limitedToListedApps)
        if decision.isSmoothed { return .smoothed }
        return rule == .notListed && limitedToListedApps ? .notInAppList : .smoothingOff
    }
}

/// The one stored value of the guide (`welcomeGuideCompletedVersion`, an Int):
/// - missing: settings from before the guide existed (settled at launch);
/// - 0: a new user who has not finished the guide;
/// - 1 or more: the version of the guide that was finished.
struct WelcomeGuideProgress {

    static let key = OptionItem.General.WelcomeGuideCompletedVersion
    /// The version of this guide. A later guide that existing users should see once more
    /// raises it.
    static let currentVersion = 1
    static let notFinished = 0

    /// Where the value lives; nil keeps nothing (the tests, unless they give a store).
    let defaults: UserDefaults?

    /// Under XCTest nothing is read or written: the real settings stay untouched.
    static var live: WelcomeGuideProgress {
        return WelcomeGuideProgress(defaults: AppRuntime.isRunningXCTest ? nil : .standard)
    }

    private var stored: Int? {
        return defaults?.object(forKey: Self.key) as? Int
    }

    /// A new user who has not finished the guide yet: the app opens it at launch.
    var isPending: Bool {
        guard let stored else { return false }
        return stored < Self.currentVersion
    }

    var isFinished: Bool {
        return !isPending
    }

    /// At launch, before the settings are read for the first time. A new installation (no
    /// `optionsExist` yet) waits for the guide; settings that existed before the guide
    /// (an update) count as finished. A value already stored stays.
    func settleAtLaunch(isNewInstallation: Bool) {
        guard let defaults, defaults.object(forKey: Self.key) == nil else { return }
        defaults.set(isNewInstallation ? Self.notFinished : Self.currentVersion, forKey: Self.key)
    }

    /// Done, Open Settings, or the window closed with the access allowed.
    func markFinished() {
        guard let defaults else { return }
        if (stored ?? Self.notFinished) < Self.currentVersion {
            defaults.set(Self.currentVersion, forKey: Self.key)
        }
    }
}
