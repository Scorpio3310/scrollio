//
//  ScrollSettings.swift
//  Mos
//  What the Scrolling tab offers on top of the stored scroll options (OPTIONS_SCROLL_DEFAULT):
//  the five "Feel" presets, the ranges of its sliders, the one switch for the wheel
//  direction, and the clean-up that runs when settings load. No UI in here.
//

import Foundation

// MARK: - Feel

/// The "Feel" presets: how long the page keeps gliding after the wheel stops. A preset is
/// nothing but a named value of `scroll.duration`; any other Duration is valid too and
/// shows as "Custom".
enum ScrollFeel: Int, CaseIterable {
    case direct, quick, smooth, glide, float

    /// The only place that holds the preset numbers (`scroll.duration`).
    /// As time constants at 60 Hz: about 35, 65, 100, 190 and 270 ms.
    var duration: Double {
        switch self {
        case .direct: return 2.0
        case .quick: return 3.13
        case .smooth: return 3.69
        case .glide: return 4.35
        case .float: return 4.6
        }
    }

    /// The feel of new settings and of "Reset to defaults": `OPTIONS_SCROLL_DEFAULT().duration`.
    static let `default` = ScrollFeel.smooth

    /// A stored Duration this close to a preset's counts as that preset.
    static let matchTolerance = 0.005

    /// The preset whose Duration is the given one, or nil for a custom Duration.
    static func matching(duration: Double) -> ScrollFeel? {
        return allCases.first { abs($0.duration - duration) <= matchTolerance + 1e-9 }
    }

    /// Stable name, used in string keys and control identifiers.
    var name: String {
        switch self {
        case .direct: return "direct"
        case .quick: return "quick"
        case .smooth: return "smooth"
        case .glide: return "glide"
        case .float: return "float"
        }
    }

    var localizedName: String {
        return NSLocalizedString("scrolling-feel-\(name)", comment: "")
    }

    /// One plain line that says how the preset feels.
    var localizedHint: String {
        return NSLocalizedString("scrolling-feel-\(name)-hint", comment: "")
    }

    /// The line under the presets while the Duration is none of theirs.
    static var customHint: String {
        return NSLocalizedString("scrolling-feel-custom-hint", comment: "")
    }

    static func hint(for feel: ScrollFeel?) -> String {
        return feel?.localizedHint ?? customHint
    }
}

// MARK: - Sliders

/// A slider of the Scrolling tab: its range, the grid its values snap to and how a value
/// is written next to it. Pure.
struct ScrollSliderSetting: Equatable {
    let range: ClosedRange<Double>
    /// Values snap to multiples of this.
    let step: Double
    /// Decimals of the value label.
    let decimals: Int

    /// `scroll.speed`: how far one click of the wheel moves the page.
    static let speed = ScrollSliderSetting(range: 1...10, step: 0.1, decimals: 1)
    /// `scroll.duration`: the exact value behind the Feel presets.
    static let glideTime = ScrollSliderSetting(range: 1...5, step: 0.01, decimals: 2)
    /// `scroll.step`: the least one click moves the page.
    static let smallestStep = ScrollSliderSetting(range: 0.01...100, step: 0.1, decimals: 1)

    /// Rounds `value` to the grid and keeps it inside the range. Anything that is not a
    /// number becomes the lower bound.
    func snapped(_ value: Double) -> Double {
        guard value.isFinite else { return range.lowerBound }
        let rounded = step > 0 ? (value / step).rounded() * step : value
        // Drop floating-point noise so stored values stay tidy (33.6, not 33.600000000000001).
        let tidy = (rounded * 1_000_000).rounded() / 1_000_000
        return min(range.upperBound, max(range.lowerBound, tidy))
    }

    /// 6.5 -> "6.5". A value below what the decimals can show keeps one more digit.
    func text(_ value: Double) -> String {
        let smallest = pow(10, -Double(decimals))
        let digits = value > 0 && value < smallest ? decimals + 1 : decimals
        return String(format: "%.\(digits)f", value)
    }
}

// MARK: - Direction

extension OPTIONS_SCROLL_DEFAULT {
    /// The one "Reverse wheel direction" switch. The model keeps a main flag and one per
    /// axis (older builds had a switch for each); the switch reads the vertical wheel and
    /// turns everything on, or the main flag off.
    var reversesWheel: Bool {
        get {
            return reverse && reverseVertical
        }
        set {
            if newValue {
                if !reverse { reverse = true }
                if !reverseVertical { reverseVertical = true }
                if !reverseHorizontal { reverseHorizontal = true }
            } else if reverse {
                reverse = false
            }
        }
    }
}

// MARK: - Clean-up on load

/// Brings stored scroll options in line with what the Scrolling tab can show. It runs each
/// time the settings load and changes nothing once they are clean.
///
/// Duration and Step are left as stored: any value is valid ("Custom" feel).
enum ScrollSettingsCleanup {

    /// UserDefaults keys of scroll settings that no longer exist: the Duration that older
    /// builds kept for the other state of "Trackpad-style events".
    static let retiredDefaultsKeys = ["durationForOtherTrackpadState"]

    /// The whole clean-up: the global scroll options, each app's own, and the retired keys
    /// (`defaults` nil leaves the stored keys alone).
    static func run(global: OPTIONS_SCROLL_DEFAULT, applications: [Application], defaults: UserDefaults?) {
        normalize(global)
        for application in applications {
            normalize(application.scroll)
        }
        if let defaults {
            for key in retiredDefaultsKeys {
                defaults.removeObject(forKey: key)
            }
        }
    }

    /// One set of scroll options:
    /// - smoothing has no per-axis switch any more, so both axes follow "Smooth scrolling";
    /// - Speed sits inside the slider's range.
    static func normalize(_ scroll: OPTIONS_SCROLL_DEFAULT) {
        if !scroll.smoothVertical { scroll.smoothVertical = true }
        if !scroll.smoothHorizontal { scroll.smoothHorizontal = true }
        let speed = clampedSpeed(scroll.speed)
        if speed != scroll.speed { scroll.speed = speed }
    }

    /// Speed inside the slider's range; a value that is not a number becomes the default.
    static func clampedSpeed(_ speed: Double) -> Double {
        guard speed.isFinite else { return OPTIONS_SCROLL_DEFAULT().speed }
        let range = ScrollSliderSetting.speed.range
        return min(range.upperBound, max(range.lowerBound, speed))
    }
}
