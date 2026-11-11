//
//  ScrollPreset.swift
//  Mos
//
//  Scroll presets for the "Presets & Fast Scrolling" popover. A preset sets the global
//  smooth-scroll step / speed / duration and the fast-scroll tuning (free-spin,
//  acceleration and momentum) in one go. Presets only touch global settings, never
//  per-app ones, and leave the thumb wheel action alone.
//

import Foundation

/// Everything a preset writes.
struct ScrollPresetValues: Equatable {
    var step: Double
    var speed: Double
    /// Same scale as the Duration slider (0...5).
    var duration: Double
    /// Turn on "Trackpad-style events". `duration` applies either way.
    var simulateTrackpad: Bool
    var tuning: ScrollTuningSettings
}

enum ScrollPreset: String, CaseIterable {
    case direct
    case balanced
    case smooth
    case trackpadLike
    case magicMouse

    // MARK: - Tuning table

    /// The only place that holds preset numbers. Retune presets here; the popover and
    /// the matching logic read from this table.
    var values: ScrollPresetValues {
        switch self {
        case .direct:
            return ScrollPresetValues(
                step: 33.6, speed: 2.0, duration: 1.0, simulateTrackpad: false,
                tuning: ScrollTuningSettings(freeSpinEnabled: true, freeSpinSmoothness: 0.5, freeSpinSpeed: 0.8, acceleration: 0)
            )
        case .balanced:
            return ScrollPresetValues(
                step: 33.6, speed: 2.7, duration: 2.0, simulateTrackpad: false,
                tuning: ScrollTuningSettings(freeSpinEnabled: true, freeSpinSmoothness: 1.0, freeSpinSpeed: 0.8, acceleration: 0)
            )
        case .smooth:
            return ScrollPresetValues(
                step: 33.6, speed: 2.7, duration: 3.13, simulateTrackpad: false,
                tuning: ScrollTuningSettings(freeSpinEnabled: true, freeSpinSmoothness: 1.5, freeSpinSpeed: 0.7, acceleration: 0)
            )
        case .trackpadLike:
            return ScrollPresetValues(
                step: 33.6, speed: 2.7, duration: 4.35, simulateTrackpad: false,
                tuning: ScrollTuningSettings(freeSpinEnabled: true, freeSpinSmoothness: 2.5, freeSpinSpeed: 1.0, acceleration: 0.3)
            )
        case .magicMouse:
            // 60 px per notch as one soft bump of about 300 ms (the smoothing of "Smooth"), so
            // slow notches run into each other instead of starting and stopping; a flick glides
            // on (momentum) and apps get trackpad phases, so they bounce at the edges.
            // Estimates to tune on hardware.
            return ScrollPresetValues(
                step: 33.6, speed: 1.8, duration: 3.13, simulateTrackpad: true,
                tuning: ScrollTuningSettings(
                    freeSpinEnabled: true, freeSpinSmoothness: 1.0, freeSpinSpeed: 1.2, acceleration: 0,
                    momentum: .default
                )
            )
        }
    }

    // MARK: - Names

    var localizedName: String {
        switch self {
        case .direct: return NSLocalizedString("scroll-preset-direct", comment: "")
        case .balanced: return NSLocalizedString("scroll-preset-balanced", comment: "")
        case .smooth: return NSLocalizedString("scroll-preset-smooth", comment: "")
        case .trackpadLike: return NSLocalizedString("scroll-preset-trackpad-like", comment: "")
        case .magicMouse: return NSLocalizedString("scroll-preset-magic-mouse", comment: "")
        }
    }

    /// One short, qualitative line (no numbers: the values may be retuned).
    var localizedDescription: String {
        switch self {
        case .direct: return NSLocalizedString("scroll-preset-direct-description", comment: "")
        case .balanced: return NSLocalizedString("scroll-preset-balanced-description", comment: "")
        case .smooth: return NSLocalizedString("scroll-preset-smooth-description", comment: "")
        case .trackpadLike: return NSLocalizedString("scroll-preset-trackpad-like-description", comment: "")
        case .magicMouse: return NSLocalizedString("scroll-preset-magic-mouse-description", comment: "")
        }
    }

    static var customLocalizedName: String {
        NSLocalizedString("scroll-preset-custom", comment: "")
    }

    // MARK: - Apply

    /// Writes the preset to the given scroll options and tuning. Turns smooth scrolling on.
    /// The thumb wheel action is not part of a preset and is kept.
    func apply(to scroll: OPTIONS_SCROLL_DEFAULT, tuning: inout ScrollTuningSettings) {
        let values = self.values
        scroll.smooth = true
        scroll.smoothSimTrackpad = values.simulateTrackpad
        scroll.duration = values.duration
        scroll.step = values.step
        scroll.speed = values.speed
        let horizontalWheelAction = tuning.horizontalWheelAction
        tuning = values.tuning
        tuning.horizontalWheelAction = horizontalWheelAction
    }

    /// Writes the preset to the global settings (`Options.shared.scroll` and `.scrollTuning`).
    func apply() {
        var tuning = Options.shared.scrollTuning
        apply(to: Options.shared.scroll, tuning: &tuning)
        Options.shared.scrollTuning = tuning
    }

    // MARK: - Matching

    /// Values this close count as equal; the main sliders show two decimals.
    static let matchTolerance = 0.005

    /// True when applying this preset would not change anything that matters.
    func matches(scroll: OPTIONS_SCROLL_DEFAULT, tuning: ScrollTuningSettings) -> Bool {
        let values = self.values
        guard scroll.smooth,
              scroll.smoothSimTrackpad == values.simulateTrackpad,
              Self.isClose(scroll.step, values.step),
              Self.isClose(scroll.speed, values.speed),
              Self.isClose(scroll.duration, values.duration),
              Self.isClose(tuning.acceleration, values.tuning.acceleration),
              tuning.freeSpinEnabled == values.tuning.freeSpinEnabled,
              tuning.momentum == values.tuning.momentum else {
            return false
        }
        // Free-spin values only matter while free-spin has its own settings.
        guard values.tuning.freeSpinEnabled else { return true }
        return Self.isClose(tuning.freeSpinSmoothness, values.tuning.freeSpinSmoothness)
            && Self.isClose(tuning.freeSpinSpeed, values.tuning.freeSpinSpeed)
    }

    /// The preset the given settings match, or nil for "Custom".
    static func matching(scroll: OPTIONS_SCROLL_DEFAULT, tuning: ScrollTuningSettings) -> ScrollPreset? {
        allCases.first { $0.matches(scroll: scroll, tuning: tuning) }
    }

    /// The preset the global settings match, or nil for "Custom".
    static var current: ScrollPreset? {
        matching(scroll: Options.shared.scroll, tuning: Options.shared.scrollTuning)
    }

    private static func isClose(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) <= matchTolerance + 1e-9
    }
}
