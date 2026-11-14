//
//  Application+ScrollingSettings.swift
//  Mos
//  "Use settings from Scrolling" switched on or off for one app on the per-app list, the
//  way the Apps pane does it. The status-bar menu's "Smooth Scrolling in …" uses the same
//  step, so both change an app's rule alike.
//

import Foundation

extension Application {
    /// On: the app follows the Scrolling settings; its own options stay stored for later.
    /// Off: the app's own options, which start as a copy of `scrolling` when they were never
    /// edited (`adoptScrollOptionsIfUnedited`), and the thumb wheel's speed and swap as the
    /// wheel runs with them now when the app has none of its own yet
    /// (`adoptThumbWheelScrollingIfNone`, from `thumbWheel`), so switching off changes
    /// nothing until the user does. Nothing happens when the app is already in that state.
    func setUsesScrollingSettings(
        _ uses: Bool, scrolling: OPTIONS_SCROLL_DEFAULT, thumbWheel: ThumbWheelSettings = Options.shared.thumbWheel
    ) {
        guard inherit != uses else { return }
        if !uses {
            adoptScrollOptionsIfUnedited(from: scrolling)
            adoptThumbWheelScrollingIfNone(from: thumbWheel)
        }
        inherit = uses
    }
}
