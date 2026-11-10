//
//  LogiWheelTypes.swift
//  Mos
//
//  Public surface for Logitech scroll-wheel hardware settings (SmartShift mode,
//  SmartShift sensitivity, ratchet force). UI and Options use only these types and
//  the LogiCenter methods below; the HID++ work stays inside Mos/Logi.
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

/// User preference, stored in Options (group `.logiWheel`) and applied to every
/// connected Logitech mouse that supports it, but only while `managedByMos` is true.
struct LogiWheelSettings: Codable, Equatable {
    /// Off by default: Mos never writes wheel settings to a device unless the user opts in.
    var managedByMos: Bool
    var mode: LogiWheelMode
    /// 1...100 %, like Logi Options+ "Sensitivity": higher switches to free-spin sooner.
    var smartShiftSensitivity: Int
    /// 1...100 %, like Logi Options+ "Scrolling force" (MX Master 4 class devices only).
    var scrollForce: Int

    static let sensitivityRange: ClosedRange<Int> = 1...100
    static let scrollForceRange: ClosedRange<Int> = 1...100

    static let `default` = LogiWheelSettings(
        managedByMos: false,
        mode: .smartShift,
        smartShiftSensitivity: 50,
        scrollForce: 50
    )

    init(managedByMos: Bool, mode: LogiWheelMode, smartShiftSensitivity: Int, scrollForce: Int) {
        self.managedByMos = managedByMos
        self.mode = mode
        self.smartShiftSensitivity = smartShiftSensitivity
        self.scrollForce = scrollForce
    }

    /// Missing keys fall back to the defaults; out-of-range values are clamped.
    init(from decoder: Decoder) throws {
        let fallback = Self.default
        let c = try decoder.container(keyedBy: CodingKeys.self)
        managedByMos = try c.decodeIfPresent(Bool.self, forKey: .managedByMos) ?? fallback.managedByMos
        mode = (try? c.decodeIfPresent(LogiWheelMode.self, forKey: .mode)) ?? fallback.mode
        let sensitivity = try c.decodeIfPresent(Int.self, forKey: .smartShiftSensitivity) ?? fallback.smartShiftSensitivity
        smartShiftSensitivity = min(max(sensitivity, Self.sensitivityRange.lowerBound), Self.sensitivityRange.upperBound)
        let force = try c.decodeIfPresent(Int.self, forKey: .scrollForce) ?? fallback.scrollForce
        scrollForce = min(max(force, Self.scrollForceRange.lowerBound), Self.scrollForceRange.upperBound)
    }
}

/// What one connected Logitech mouse reports, for display in the Mouse tab.
struct LogiWheelDeviceState: Equatable {
    /// Stable within a run; use it to match rows between refreshes.
    let id: String
    let deviceName: String
    /// SmartShift mode / sensitivity can be read and written.
    let supportsSmartShift: Bool
    /// Ratchet force can be tuned (SmartShift enhanced with tunable torque).
    let supportsScrollForce: Bool
    /// Last values read from the device; nil until read.
    let mode: LogiWheelMode?
    let smartShiftSensitivity: Int?
    let scrollForce: Int?
}

extension LogiCenter {
    /// Posted on the main thread whenever `wheelDeviceStates()` may have changed.
    static let wheelStateChanged = Notification.Name("LogiWheelStateChanged")

    // The wheel methods live in LogiCenter.swift (they need the private session manager):
    //   func wheelDeviceStates() -> [LogiWheelDeviceState]
    //   func refreshWheelStates()
    //   func applyWheelSettings(_ settings: LogiWheelSettings)
}
