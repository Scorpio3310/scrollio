//
//  Application+ScrollingSettings.swift
//  Mos
//  "Use settings from Scrolling" switched on or off for one app on the per-app list, the
//  way the Apps pane does it. The status-bar menu's "Smooth Scrolling in …" uses the same
//  step, so both change an app's rule alike.
//
//  The app's Scrolling part offers it as one choice, "Scrolling in Safari": Same as
//  Scrolling, Own Settings or Left to macOS (`ApplicationScrollingChoice`). Nothing of the
//  choice is stored: it is worked out from what is (`inherit`, and the app's own smoothing
//  and direction), and a pick writes those values (`choose(_:from:scrolling:thumbWheel:)`).
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

// MARK: - "Scrolling in Safari": one choice

/// How an app on the per-app list scrolls, as its Scrolling part offers it. Never stored:
/// `of(inherit:scroll:)` works it out from what is.
enum ApplicationScrollingChoice: Int, CaseIterable {
    /// "Use settings from Scrolling" on: the Scrolling pane's settings.
    case sameAsScrolling
    /// The app's own settings.
    case ownSettings
    /// The app's own settings with smoothing and reversing off: the wheel as macOS turns
    /// it, exactly what the engine does for an app that is not on the list while "Change
    /// scrolling only in these apps" is on. Its speeds, feel and keys stay stored.
    case leftToMacOS

    /// The pop-up item's title.
    var titleKey: String {
        switch self {
        case .sameAsScrolling: return "apps-detail-scrolling-same"
        case .ownSettings: return "apps-detail-scrolling-own"
        case .leftToMacOS: return "apps-detail-scrolling-macos"
        }
    }

    /// The line under the row while this is chosen; it takes the app's name.
    var explanationKey: String {
        switch self {
        case .sameAsScrolling: return "apps-detail-inherit-on"
        case .ownSettings: return "apps-detail-inherit-off"
        case .leftToMacOS: return "apps-detail-scrolling-macos-hint"
        }
    }

    /// What is stored says: "Use settings from Scrolling" on is Same as Scrolling; the
    /// app's own settings with smoothing off and the wheel not reversed are Left to macOS;
    /// anything else is Own Settings.
    static func of(inherit: Bool, scroll: OPTIONS_SCROLL_DEFAULT) -> ApplicationScrollingChoice {
        if inherit { return .sameAsScrolling }
        return !scroll.smooth && !scroll.reversesWheel ? .leftToMacOS : .ownSettings
    }
}

extension Application {

    /// The choice what is stored for the app says (`ApplicationScrollingChoice.of`).
    var scrollingChoice: ApplicationScrollingChoice {
        return .of(inherit: inherit, scroll: scroll)
    }

    /// A pick of `choice` while the part shows `shown` (which may be Own Settings over
    /// stored values that say Left to macOS, while the part is on screen). Writes only what
    /// the move needs; nothing for the choice that shows.
    /// - Same as Scrolling: "Use settings from Scrolling" on; the app's own values stay.
    /// - Own Settings, from Same as Scrolling: that switch off, nothing else (as the switch
    ///   did). From Left to macOS: the two things Left to macOS turned off come back,
    ///   smoothing on, with the setter the menu bar's "Smooth Scrolling in …" uses
    ///   (`scroll.smooth`), and the wheel's direction as `scrolling` has it (the app's
    ///   own from before is not kept anywhere; left off, the app would scroll against
    ///   every other app after Own Settings → Left to macOS → Own Settings).
    /// - Left to macOS: that switch off, then smoothing off (the same setter) and the
    ///   wheel not reversed. Speeds, feel and keys stay stored; so does the thumb wheel.
    func choose(
        _ choice: ApplicationScrollingChoice, from shown: ApplicationScrollingChoice,
        scrolling: OPTIONS_SCROLL_DEFAULT, thumbWheel: ThumbWheelSettings = Options.shared.thumbWheel
    ) {
        guard choice != shown else { return }
        switch choice {
        case .sameAsScrolling:
            setUsesScrollingSettings(true, scrolling: scrolling, thumbWheel: thumbWheel)
        case .ownSettings:
            setUsesScrollingSettings(false, scrolling: scrolling, thumbWheel: thumbWheel)
            if shown == .leftToMacOS {
                if !scroll.smooth {
                    scroll.smooth = true
                }
                if scroll.reversesWheel != scrolling.reversesWheel {
                    scroll.reversesWheel = scrolling.reversesWheel
                }
            }
        case .leftToMacOS:
            setUsesScrollingSettings(false, scrolling: scrolling, thumbWheel: thumbWheel)
            if scroll.smooth {
                scroll.smooth = false
            }
            if scroll.reversesWheel {
                scroll.reversesWheel = false
            }
        }
    }
}

/// What a pick of "Scrolling in Safari" can change, for its Undo: "Use settings from
/// Scrolling", every scroll value of the app's own and its thumb wheel's speed, reverses
/// and follow switch (`scroll.thumbWheel`). A copy: later edits do not reach it.
struct ApplicationScrollingSnapshot: Equatable {
    let inherit: Bool
    private let scroll: OPTIONS_SCROLL_DEFAULT

    init(of application: Application) {
        inherit = application.inherit
        scroll = Self.copy(of: application.scroll)
    }

    /// Gives `application` these values: a new container of its own (the copy here stays
    /// as it is, for a Redo after the Undo). Nothing is written when nothing differs.
    func apply(to application: Application) {
        if application.scroll != scroll || application.scroll.thumbWheel != scroll.thumbWheel {
            application.scroll = Self.copy(of: scroll)
        }
        if application.inherit != inherit {
            application.inherit = inherit
        }
    }

    static func == (a: ApplicationScrollingSnapshot, b: ApplicationScrollingSnapshot) -> Bool {
        return a.inherit == b.inherit && a.scroll == b.scroll && a.scroll.thumbWheel == b.scroll.thumbWheel
    }

    /// Every scroll value (as "Copy from Scrolling" copies them) and the thumb wheel's.
    private static func copy(of scroll: OPTIONS_SCROLL_DEFAULT) -> OPTIONS_SCROLL_DEFAULT {
        let copy = Application.scrollingCopy(of: scroll, thumbWheel: .default)
        copy.thumbWheel = scroll.thumbWheel
        return copy
    }
}
