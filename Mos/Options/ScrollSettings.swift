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

    /// A Duration this close to a preset's counts as that preset: the glide time slider moves
    /// in steps of 0.05, so the stop next to a preset (3.15 for 3.13) selects it, and so does
    /// a Duration tuned by feel just beside one (3.687 is Smooth).
    static let matchTolerance = 0.03

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

/// A slider of the Scrolling tab: its range, its tick marks and the grid its values snap to,
/// and how a value is written next to it. Pure.
///
/// A stored value off the grid (a Speed of 6.31 tuned by feel, the default Step of 33.6) is
/// shown as it is and only replaced when the slider is moved.
struct ScrollSliderSetting: Equatable {
    let range: ClosedRange<Double>
    /// The tick marks under the slider and the steps its value moves in.
    let scale: PreferencesSliderScale
    /// Decimals of the value label.
    let decimals: Int
    /// Decimals a value off the grid may keep in the label, so it is not shown as another.
    let maxDecimals: Int

    init(range: ClosedRange<Double>, scale: PreferencesSliderScale, decimals: Int, maxDecimals: Int? = nil) {
        self.range = range
        self.scale = scale
        self.decimals = decimals
        self.maxDecimals = max(decimals, maxDecimals ?? decimals)
    }

    /// `scroll.speed`: how far one click of the wheel moves the page. A tick at every whole
    /// number, values in halves.
    static let speed = ScrollSliderSetting(range: 1...10, scale: .ticks(10, step: 0.5), decimals: 1)
    /// `scroll.duration`: the exact value behind the Feel presets. A tick every 0.5, values
    /// in steps of 0.05; the presets keep their own Durations.
    static let glideTime = ScrollSliderSetting(range: 1...5, scale: .ticks(9, step: 0.05), decimals: 2)
    /// `scroll.step`: the least one click moves the page. A tick every 10 (the lowest is the
    /// range's 0.01), values in whole numbers.
    static let smallestStep = ScrollSliderSetting(range: 0.01...100, scale: .ticks(11, step: 1), decimals: 0, maxDecimals: 2)

    /// Values snap to multiples of this.
    var step: Double {
        return scale.step(in: range)
    }

    /// Rounds `value` to the grid and keeps it inside the range. Anything that is not a
    /// number becomes the lower bound.
    func snapped(_ value: Double) -> Double {
        return scale.snapped(value, in: range)
    }

    /// 6.5 -> "6.5". A value the decimals cannot show (33.6 on the whole-number Step) keeps
    /// up to `maxDecimals`.
    func text(_ value: Double) -> String {
        var digits = decimals
        while digits < maxDecimals, !Self.shows(value, withDecimals: digits) {
            digits += 1
        }
        return String(format: "%.\(digits)f", value)
    }

    private static func shows(_ value: Double, withDecimals digits: Int) -> Bool {
        let scale = pow(10, Double(digits))
        return abs((value * scale).rounded() - value * scale) < 1e-6
    }
}

// MARK: - Direction

extension OPTIONS_SCROLL_DEFAULT {
    /// The one "Reverse wheel direction" switch. The model keeps a main flag and one per
    /// axis (older builds, and settings imported from Mos, had a switch for each). The
    /// switch is on while the engine reverses either axis (`ScrollCore` reverses an axis when
    /// the main flag and that axis's flag are on); on turns everything on, off turns the
    /// main flag off, which stops both axes.
    var reversesWheel: Bool {
        get {
            return reverse && (reverseVertical || reverseHorizontal)
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

    /// UserDefaults keys of scroll settings that no longer exist:
    /// - the Duration that older builds kept for the other state of "Trackpad-style events";
    /// - the fast-scroll tuning (free-spin, acceleration, momentum, what the thumb wheel did),
    ///   which the one-path scroll engine does not have.
    static let retiredDefaultsKeys = ["durationForOtherTrackpadState", "scrollTuning"]

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
