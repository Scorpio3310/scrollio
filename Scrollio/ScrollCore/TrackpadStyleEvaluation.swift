//
//  TrackpadStyleEvaluation.swift
//  Scrollio
//
//  EVALUATION SWITCH. Remove this file, and what uses it (`ScrollPoster.usesOldLongTouch`,
//  the old long touch itself, the launch line in AppDelegate), before the one-touch form of
//  "Trackpad-style scrolling" is released.
//

import Foundation

/// Which form "Trackpad-style scrolling" takes for an app that is not Chromium-based, so
/// that the two can be compared on a real Mac:
///
/// - the new form (the default): one touch until the scroll has run out, no glide events;
/// - the old long touch: a touch for as long as the wheel turns (and 0.18 s more), the rest
///   of the scroll as glide events, which AppKit views do not follow.
///
///     defaults write com.nikklemenc.Scrollio trackpadStyleEvaluationOldLongTouch -bool YES
///     defaults delete com.nikklemenc.Scrollio trackpadStyleEvaluationOldLongTouch
///
/// then quit Scrollio and start it again: the value is read once, at launch. It is not a
/// setting: it is in no pane and in no list of the app's settings (`Options`, `OptionItem`),
/// the app never writes it, and it is not part of a settings file. The `app` log says at
/// launch which form is in use, and every scroll's line in the `scroll` log names its form
/// ("one touch" or "long touch").
enum TrackpadStyleEvaluation {

    static let defaultsKey = "trackpadStyleEvaluationOldLongTouch"

    /// Read once, at first use (the launch line asks for it). Never under XCTest: a test
    /// says the form itself (`ScrollPoster.usesOldLongTouch`).
    static let usesOldLongTouch: Bool = {
        guard !AppRuntime.isRunningXCTest else { return false }
        return usesOldLongTouch(in: .standard)
    }()

    static func usesOldLongTouch(in defaults: UserDefaults) -> Bool {
        return defaults.bool(forKey: defaultsKey)
    }

    /// The line for the `app` log at launch.
    static func launchLine(usesOldLongTouch: Bool) -> String {
        let form = usesOldLongTouch
            ? "the old long touch (a touch while the wheel turns, then its glide)"
            : "one touch until the scroll has run out"
        let state = usesOldLongTouch ? "YES" : "not set"
        return "Trackpad-style scrolling, apps that are not Chromium-based: \(form) (evaluation switch \(defaultsKey): \(state))"
    }
}
