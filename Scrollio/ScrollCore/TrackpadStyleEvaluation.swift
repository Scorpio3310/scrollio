//
//  TrackpadStyleEvaluation.swift
//  Scrollio
//
//  EVALUATION SWITCHES. Remove this file, and what uses it (`ScrollPoster.usesOldLongTouch`
//  and the old long touch itself, `ScrollPoster.usesSafariFlick` and
//  `ScrollUtils.TrackpadStyleTarget.safari`'s flick, the launch lines in AppDelegate), before
//  "Trackpad-style scrolling" is released.
//

import Foundation

/// Two switches for comparing forms of "Trackpad-style scrolling" on a real Mac. Each is one
/// default, read once at launch; neither is a setting: they are in no pane and in no list of
/// the app's settings (`Options`, `OptionItem`), the app never writes them, and they are not
/// part of a settings file. The `app` log says at launch what each is, and every scroll's
/// line in the `scroll` log names its form ("flick", "one touch" or "long touch").
///
/// 1. Which form an app that is not Chromium-based or Gecko-based gets:
///    - the new form (the default): one touch until the scroll has run out, no glide events;
///    - the old long touch: a touch for as long as the wheel turns (and 0.18 s more), the
///      rest of the scroll as glide events, which AppKit views do not follow.
///
///        defaults write com.nikklemenc.Scrollio trackpadStyleEvaluationOldLongTouch -bool YES
///        defaults delete com.nikklemenc.Scrollio trackpadStyleEvaluationOldLongTouch
///
/// 2. What Safari (every `com.apple.Safari…` id) gets:
///    - no phases, as with the switch off (the default);
///    - the flick, as Chromium-based apps get it: without the wheel event's hardware
///      record, every frame with its own even time. In a WKWebView that stream was followed
///      in full (205 of 205 px) with a trackpad's bounce at a page end; Safari itself was
///      never seen with it. Only where the record comes off (`ScrollHardwareRecord`):
///      with a record on "momentum began" WebKit replaces the glide by its own.
///
///        defaults write com.nikklemenc.Scrollio trackpadStyleEvaluationSafariFlick -bool YES
///        defaults delete com.nikklemenc.Scrollio trackpadStyleEvaluationSafariFlick
///
/// After either command quit Scrollio and start it again.
enum TrackpadStyleEvaluation {

    static let defaultsKey = "trackpadStyleEvaluationOldLongTouch"
    static let safariFlickDefaultsKey = "trackpadStyleEvaluationSafariFlick"

    /// Read once, at first use (the launch line asks for it). Never under XCTest: a test
    /// says the form itself (`ScrollPoster.usesOldLongTouch`).
    static let usesOldLongTouch: Bool = {
        guard !AppRuntime.isRunningXCTest else { return false }
        return usesOldLongTouch(in: .standard)
    }()

    static func usesOldLongTouch(in defaults: UserDefaults) -> Bool {
        return defaults.bool(forKey: defaultsKey)
    }

    /// Read once, at first use. Never under XCTest (`ScrollPoster.usesSafariFlick`).
    static let usesSafariFlick: Bool = {
        guard !AppRuntime.isRunningXCTest else { return false }
        return usesSafariFlick(in: .standard)
    }()

    static func usesSafariFlick(in defaults: UserDefaults) -> Bool {
        return defaults.bool(forKey: safariFlickDefaultsKey)
    }

    /// The line for the `app` log at launch.
    static func launchLine(usesOldLongTouch: Bool) -> String {
        let form = usesOldLongTouch
            ? "the old long touch (a touch while the wheel turns, then its glide)"
            : "one touch until the scroll has run out"
        let state = usesOldLongTouch ? "YES" : "not set"
        return "Trackpad-style scrolling, apps that are not Chromium-based or Gecko-based: \(form) (evaluation switch \(defaultsKey): \(state))"
    }

    /// The line about Safari for the `app` log at launch. It does not ask whether the
    /// hardware record comes off (that would run the self-test at every launch): where it
    /// does not, Safari gets no phases whatever the switch says, and the line about the
    /// hardware record says which it is.
    static func safariLaunchLine(usesSafariFlick: Bool) -> String {
        let form = usesSafariFlick
            ? "the flick, without the hardware record (no phases where the record does not come off a frame: the line about the hardware record says which)"
            : "no phases, as with the switch off"
        let state = usesSafariFlick ? "YES" : "not set"
        return "Trackpad-style scrolling, Safari: \(form) (evaluation switch \(safariFlickDefaultsKey): \(state))"
    }
}
