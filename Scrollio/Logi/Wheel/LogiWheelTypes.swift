//
//  LogiWheelTypes.swift
//  Mos
//
//  Public surface for Logitech scroll-wheel hardware settings (SmartShift mode,
//  SmartShift sensitivity, ratchet force). UI and Options use only these types and
//  the LogiCenter methods below; the HID++ work stays inside Scrollio/Logi.
//
//  Writing follows the rule of the basic mouse settings (LogiMouseBasicsTypes): a value is
//  written only when "Let Scrollio manage this mouse" (`managedByMos`) is on, the user has set
//  that value (non-nil here) and the value freshly read from the mouse differs. A value the
//  user never set is never written; the mouse keeps its own.
//
//  CONTRACT (shared by several work packages): do not rename or remove these
//  types, cases, fields or method signatures without updating every consumer.
//

import Foundation

/// How the wheel behaves, matching Logi Options+ "Scroll mode".
enum LogiWheelMode: String, Codable, CaseIterable, Equatable {
    /// Ratchet that switches to free-spin automatically above the sensitivity threshold.
    case smartShift
    /// Always ratchet (auto-shift off).
    case ratchet
    /// Always free-spin.
    case freeSpin
}

/// User preference, stored in Options (group `.logiWheel`, UserDefaults key
/// "logiWheelSettings") and applied to every connected Logitech mouse that supports it, but
/// only while `managedByMos` is true. The wheel values are optional: nil means "not set by the
/// user, leave the mouse's own value", and a value is set only when the user moves that control.
///
/// Stored format: `{"managedByMos": Bool}` plus the keys of the values the user set
/// (`mode`, `smartShiftSensitivity`, `scrollForce`); an unset value has no key. Settings stored
/// before the values were optional always carry all three keys and so load as set by the user.
struct LogiWheelSettings: Codable, Equatable {
    /// "Let Scrollio manage this mouse": the one switch for everything Scrollio writes to a
    /// Logitech mouse, the wheel settings here and the basic settings of LogiMouseSettings
    /// (pointer speed, haptics, press force). Off by default: nothing is written to a device
    /// unless the user opts in. The JSON key keeps its old name.
    var managedByMos: Bool
    var mode: LogiWheelMode?
    /// 1...100 %, like Logi Options+ "Sensitivity": higher switches to free-spin sooner.
    /// Applies only while the wheel is in SmartShift.
    var smartShiftSensitivity: Int?
    /// 1...100 %, like Logi Options+ "Scrolling force" (MX Master 4 class devices only).
    var scrollForce: Int?

    static let sensitivityRange: ClosedRange<Int> = 1...100
    static let scrollForceRange: ClosedRange<Int> = 1...100

    /// The mouse keeps SmartShift sensitivity in coarse steps (up to 6 % at the sensitive end),
    /// so a value within this many percent of the user's is the same choice: not written again,
    /// and no "On the mouse" line.
    static let sensitivityTolerance = 3

    /// The sensitivity a wheel gets when the user chooses SmartShift while the mouse has no
    /// threshold of its own (it was always ratchet) and no sensitivity is set: Logitech's
    /// factory default (4 wheel turns per second). Also what the Mouse tab shows then.
    static let defaultSmartShiftSensitivity = 50

    /// Not managed, nothing set: Scrollio leaves the wheel as the mouse has it.
    static let `default` = LogiWheelSettings()

    init(
        managedByMos: Bool = false,
        mode: LogiWheelMode? = nil,
        smartShiftSensitivity: Int? = nil,
        scrollForce: Int? = nil
    ) {
        self.managedByMos = managedByMos
        self.mode = mode
        self.smartShiftSensitivity = smartShiftSensitivity.map { Self.clamp($0, Self.sensitivityRange) }
        self.scrollForce = scrollForce.map { Self.clamp($0, Self.scrollForceRange) }
    }

    /// Missing, unreadable or wrongly typed values fall back to nil one by one (the others are
    /// kept); a missing switch is off; out-of-range values are clamped; unknown keys are ignored.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let managed = (try? c.decodeIfPresent(Bool.self, forKey: .managedByMos)) ?? nil
        let mode = (try? c.decodeIfPresent(LogiWheelMode.self, forKey: .mode)) ?? nil
        let sensitivity = (try? c.decodeIfPresent(Int.self, forKey: .smartShiftSensitivity)) ?? nil
        let force = (try? c.decodeIfPresent(Int.self, forKey: .scrollForce)) ?? nil
        self.init(managedByMos: managed ?? false, mode: mode, smartShiftSensitivity: sensitivity, scrollForce: force)
    }

    private static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

/// What one connected Logitech mouse reports, for display in the Mouse tab. Each value has
/// the shape of the basic settings (`LogiMouseDeviceState.Value`): what the mouse reports
/// (nil until read) and what the user set (nil = never set).
struct LogiWheelDeviceState: Equatable {
    typealias Value = LogiMouseDeviceState.Value

    /// Stable within a run; use it to match rows between refreshes.
    let id: String
    let deviceName: String
    /// SmartShift mode / sensitivity can be read and written.
    let supportsSmartShift: Bool
    /// Ratchet force can be tuned (SmartShift enhanced with tunable torque).
    let supportsScrollForce: Bool
    let mode: Value<LogiWheelMode>
    /// The mouse's value is nil while it has no threshold (always ratchet). The user's is as
    /// the mouse would take it (the mouse keeps coarse steps).
    let smartShiftSensitivity: Value<Int>
    /// The mouse's value is nil when it cannot tune the force (or has not said yet).
    let scrollForce: Value<Int>
}

extension LogiCenter {
    /// Posted on the main thread whenever `wheelDeviceStates()` may have changed.
    static let wheelStateChanged = Notification.Name("LogiWheelStateChanged")

    // The wheel methods live in LogiCenter.swift (they need the private session manager):
    //   func wheelDeviceStates() -> [LogiWheelDeviceState]
    //   func refreshWheelStates()
    //   func applyWheelSettings(_ settings: LogiWheelSettings)
}
