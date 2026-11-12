//
//  LogiMouseBasicsTypes.swift
//  Mos
//
//  Public surface for the basic Logitech mouse settings that Logi Options+ shows next to
//  the wheel: battery (read only), pointer speed (DPI), haptic feedback and the thumb
//  panel's press force. The UI and Options use only these types and the LogiCenter
//  methods below; the HID++ work stays inside Scrollio/Logi.
//
//  Writing follows one switch for everything Scrollio writes to a mouse:
//  `LogiWheelSettings.managedByScrollio` ("Let Scrollio manage this mouse"). A value is written
//  only when that switch is on, the user has set the value (non-nil here) and the value
//  freshly read from the mouse differs. Values the user set are written again on every
//  connect. Reading never needs the switch.
//
//  CONTRACT (the Mouse tab is built on it): do not rename or remove these types, cases,
//  fields or method signatures without updating every consumer.
//

import Foundation

/// The user's choices, stored in Options (group `.logiMouse`, UserDefaults key
/// "logiMouseSettings"). Every field is optional: nil means "leave the mouse's own value",
/// and a field is set only when the user moves that control. One set of values for every
/// connected mouse; each mouse snaps or clamps it to what it supports.
struct LogiMouseSettings: Codable, Equatable {
    /// Pointer speed in DPI. Snapped per mouse to the nearest value of its DPI list.
    var pointerDPI: Int?
    /// Haptic feedback on the mouse (MX Master 4). Once false, gesture cues no longer
    /// switch the mouse's haptics on.
    var hapticsOn: Bool?
    /// Haptic strength 1...100 %. Snapped to 25/50/75/100 on mice that report only a few levels.
    var hapticStrength: Int?
    /// Thumb panel press force in the mouse's raw units (lower = lighter press), clamped per
    /// mouse to the range it reports (one MX Master 4 reported 4071...6768).
    var pressForce: Int?

    /// Sanity bounds for decoding; every mouse narrows them further.
    static let pointerDPIRange: ClosedRange<Int> = 1...0xDFFF
    static let hapticStrengthRange: ClosedRange<Int> = 1...100
    static let pressForceRange: ClosedRange<Int> = 0...0xFFFF

    /// Nothing set: Scrollio leaves every value as the mouse has it.
    static let `default` = LogiMouseSettings()

    init(pointerDPI: Int? = nil, hapticsOn: Bool? = nil, hapticStrength: Int? = nil, pressForce: Int? = nil) {
        self.pointerDPI = pointerDPI.map { Self.clamp($0, Self.pointerDPIRange) }
        self.hapticsOn = hapticsOn
        self.hapticStrength = hapticStrength.map { Self.clamp($0, Self.hapticStrengthRange) }
        self.pressForce = pressForce.map { Self.clamp($0, Self.pressForceRange) }
    }

    /// Missing, unreadable or wrongly typed fields fall back to nil one by one (the others
    /// are kept); out-of-range values are clamped; unknown keys are ignored.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let dpi = (try? c.decodeIfPresent(Int.self, forKey: .pointerDPI)) ?? nil
        let on = (try? c.decodeIfPresent(Bool.self, forKey: .hapticsOn)) ?? nil
        let strength = (try? c.decodeIfPresent(Int.self, forKey: .hapticStrength)) ?? nil
        let force = (try? c.decodeIfPresent(Int.self, forKey: .pressForce)) ?? nil
        self.init(pointerDPI: dpi, hapticsOn: on, hapticStrength: strength, pressForce: force)
    }

    private static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

/// What one connected Logitech mouse reports, for the Mouse tab: one entry per mouse, with
/// its wheel state included so the tab does not join two lists. Values are the last ones
/// read from the mouse; nil until read.
struct LogiMouseDeviceState: Equatable {
    /// Stable within a run and equal to the id of `wheel`; use it to match rows between refreshes.
    let id: String
    let deviceName: String
    /// The basics this mouse has. A basic the mouse refused (HID++ error) is left out.
    let supported: Set<Basic>
    /// "Let Scrollio manage this mouse" is on (the same switch for every mouse).
    let managed: Bool
    /// nil: the mouse has no battery feature, or it has not answered yet.
    let battery: Battery?
    /// nil: the mouse has no adjustable DPI (0x2201).
    let pointerSpeed: PointerSpeed?
    /// nil: the mouse has no haptic motor (0x19B0, MX Master 4 only).
    let haptics: Haptics?
    /// nil: the mouse has no force sensing button (0x19C0, MX Master 4 only).
    let pressForce: PressForce?
    /// SmartShift / scroll force of the same mouse; nil when it has no wheel feature.
    let wheel: LogiWheelDeviceState?

    enum Basic: CaseIterable, Equatable, Hashable {
        case battery
        case pointerSpeed
        case haptics
        case pressForce
    }

    /// Where a shown value comes from.
    enum Source: Equatable {
        /// The user has not set it in Scrollio: the value is the mouse's own.
        case mouse
        /// The user set it in Scrollio.
        case user
    }

    /// Why the mouse reports another value than the user set, as far as Scrollio knows it.
    /// Display only: worked out from the controllers' own bookkeeping while running, never
    /// stored, and no write decision reads it.
    enum Mismatch: Equatable {
        /// Scrollio is still sending the user's value: a write (or the read that decides it)
        /// is queued or waits for the mouse's answer.
        case sending
        /// The mouse answered with an error (HID++) when Scrollio sent it, or read it to send it.
        case refused
        /// The mouse did not answer the write, or the read before it.
        case noAnswer
        /// The mouse answered the write but reported another value right after (firmware
        /// rounding, or it ignored it).
        case notKept
        /// The mouse had the user's value (took it, or had it already) and reported another
        /// one later: changed on the mouse itself or by another app.
        case changedElsewhere
    }

    /// One setting: what the mouse reports and what the user set.
    struct Value<T: Equatable>: Equatable {
        /// Last value read from the mouse; nil until read.
        let onMouse: T?
        /// The user's choice as this mouse would take it (snapped or clamped); nil = never set.
        let setByYou: T?
        /// Why `onMouse` is not `setByYou`. nil while they match, while nothing is set, while
        /// the mouse is not managed (Scrollio sends nothing), or when the reason is not known.
        let mismatch: Mismatch?

        init(onMouse: T?, setByYou: T?, mismatch: Mismatch? = nil) {
            self.onMouse = onMouse
            self.setByYou = setByYou
            self.mismatch = mismatch
        }

        var source: Source { setByYou == nil ? .mouse : .user }
        /// The mouse has the user's choice, or there is none to have.
        var mouseMatches: Bool { setByYou == nil || setByYou == onMouse }
    }

    struct Battery: Equatable {
        /// 0...100, nil when the mouse reports only a level (or 0, meaning unknown).
        let percent: Int?
        let level: Level
        let charging: Charging
        /// The mouse reports coarse steps (0x1000 Battery Status, original MX Master 3):
        /// show "about 50 %", not "50 %".
        let isApproximate: Bool

        enum Level: Equatable {
            case critical
            case low
            case good
            case full
            /// Not reported (0x1000) or a value no source documents.
            case unknown
        }

        enum Charging: Equatable {
            case discharging
            case charging
            case chargingSlowly
            /// Charging, nearly full.
            case almostFull
            case full
            /// Invalid battery, thermal error or another charging error.
            case problem
            case unknown
        }
    }

    struct PointerSpeed: Equatable {
        /// Every DPI value the mouse accepts, ascending; empty until the list was read.
        let choices: [Int]
        let dpi: Value<Int>
        /// The mouse's factory value, when it reports one.
        let defaultDPI: Int?
    }

    struct Haptics: Equatable {
        let isOn: Value<Bool>
        /// Strength 0...100 %.
        let strength: Value<Int>
        /// True when the mouse reports only a few strength levels; nil until read.
        /// (Which byte says so is an assumption, see LogiHapticSettingsProtocol.)
        let hasFewLevels: Bool?
        /// The strengths to offer when `hasFewLevels` is true, ascending.
        let fewLevelChoices: [Int]
    }

    struct PressForce: Equatable {
        /// Raw units of this mouse; lower = lighter press.
        let force: Value<Int>
        /// nil until read, or when the mouse reported an unusable range.
        let range: ClosedRange<Int>?
        let defaultForce: Int?
        /// The mouse allows the force of this button to be changed.
        let isChangeable: Bool
    }
}

extension LogiCenter {
    /// Posted on the main thread, coalesced, whenever `mouseDeviceStates()` may have changed
    /// (including the wheel state inside it).
    static let mouseStateChanged = Notification.Name("LogiMouseStateChanged")

    // The methods live in LogiCenter.swift (they need the private session manager):
    //   func mouseDeviceStates() -> [LogiMouseDeviceState]
    //   func refreshMouseStates()
    //   func applyMouseSettings(_ settings: LogiMouseSettings, managed: Bool)
    //   func playHapticSample()
    //   func sendMouseSettingsAgain()
}
