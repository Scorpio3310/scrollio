//
//  AppAccent.swift
//  Mos
//
//  The app's accent colour: the purple of its icon, the colour set `AccentColor` in
//  Assets.xcassets (light #5F44B3, dark #7F62D9: a violet, hue 255°), named by the build setting
//  ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME, which puts `NSAccentColorName` in the
//  app's Info.plist. macOS then draws the switches, sliders, pop-ups, selections, focus
//  rings and default buttons in it, and `NSColor.controlAccentColor` returns it, while the
//  user's accent colour in System Settings is "Multicolour". A user who chose a colour of
//  their own keeps it everywhere, in Scrollio too. That is the platform's rule.
//
//  The app's own drawings (the lit parts of the mouse, the previews, the Welcome Guide)
//  use `NSColor.controlAccentColor` for what is lit or selected, so they always agree with
//  the controls next to them.
//

import Foundation

enum AppAccent {

    /// The colour set in Assets.xcassets.
    static let assetName = "AccentColor"

    /// The system's appearance setting that holds the accent colour the user chose in
    /// System Settings. It is absent while the choice is "Multicolour".
    static let systemAccentKey = "AppleAccentColor"

    /// The `app` log's launch line: which accent the user sees. Pure: `systemAccentValue`
    /// is what the defaults hold for `systemAccentKey`, nil when there is none.
    static func logLine(systemAccentValue: Any?) -> String {
        guard systemAccentValue != nil else {
            return "Accent colour: the app's own (purple)"
        }
        return "Accent colour: the user's system choice (the app's purple shows with \"Multicolour\")"
    }

    /// The line for this Mac. This reads the system's appearance setting through the app's
    /// own defaults search list (the global domain is part of it); nothing is written.
    static func liveLogLine(defaults: UserDefaults = .standard) -> String {
        return logLine(systemAccentValue: defaults.object(forKey: systemAccentKey))
    }
}
