//
//  MacPointerSettings.swift
//  Mos
//  The macOS pointer settings of the current user that apply to every mouse, as System
//  Settings › Mouse has them: "Tracking speed" and "Pointer acceleration". The Mouse pane
//  shows them for any mouse, Logitech or not.
//
//  Everything goes through `MacPointerSettings`, a set of read and write closures: the app
//  uses `.system`, tests and renders pass their own, and under XCTest `.standard` is
//  `.inert`, so no test reads or writes the real settings.
//
//  How System Settings › Mouse (macOS 27) changes them, read from its extension: it sets the
//  HID event system property first (`HIDMouseAcceleration`, 16.16 fixed point, or
//  `HIDUseLinearScalingMouseAcceleration`), which takes effect at once, and then stores the
//  user's preference in the global domain (`com.apple.mouse.scaling`, a number, or
//  `com.apple.mouse.linear`, a Boolean), which macOS applies again at the next login.
//  `MacPointerSystem` does the same with public, non-deprecated API: the HID event system's
//  simple client (IOHIDEventSystemClient.h, IOHIDProperties.h) and CFPreferences. A value
//  the event system does not take is not stored, and the controls read back what macOS has.
//

import Foundation
import IOKit.hid
import IOKit.hidsystem

/// What macOS has now. nil: it could not be read; the pane hides that row.
struct MacPointerState: Equatable {
    /// `com.apple.mouse.scaling`: 0 (slow) … 3 (fast).
    var trackingSpeed: Double?
    /// The opposite of `com.apple.mouse.linear`: on unless linear tracking is set.
    var pointerAcceleration: Bool?
}

struct MacPointerSettings {

    var readTrackingSpeed: () -> Double?
    /// true: macOS took the value.
    var writeTrackingSpeed: (Double) -> Bool
    var readPointerAcceleration: () -> Bool?
    /// true: macOS took the value.
    var writePointerAcceleration: (Bool) -> Bool

    func read() -> MacPointerState {
        return MacPointerState(trackingSpeed: readTrackingSpeed(), pointerAcceleration: readPointerAcceleration())
    }

    // MARK: - The scale of System Settings

    /// The stops of System Settings › Mouse › Tracking speed, slow to fast: one tick mark each
    /// (the table in its MouseExtension, macOS 27).
    static let trackingSpeeds: [Double] = [0, 0.125, 0.5, 0.6875, 0.875, 1, 1.5, 2, 2.5, 3]

    /// The stop nearest `value` (the slower one on a tie). A value off the scale, such as
    /// one set with `defaults write`, is shown on its nearest stop and left as it is.
    static func trackingSpeedIndex(nearest value: Double) -> Int {
        var best = 0
        for (index, speed) in trackingSpeeds.enumerated()
        where abs(speed - value) < abs(trackingSpeeds[best] - value) {
            best = index
        }
        return best
    }

    // MARK: - Instances

    /// The real settings in the app, `inert` under XCTest.
    static var standard: MacPointerSettings {
        return AppRuntime.isRunningXCTest ? .inert : .system
    }

    /// The current user's macOS settings.
    static let system = MacPointerSettings(
        readTrackingSpeed: MacPointerSystem.trackingSpeed,
        writeTrackingSpeed: MacPointerSystem.setTrackingSpeed,
        readPointerAcceleration: MacPointerSystem.pointerAcceleration,
        writePointerAcceleration: MacPointerSystem.setPointerAcceleration
    )

    /// The macOS defaults, read only: nothing is ever written.
    static let inert = MacPointerSettings(
        readTrackingSpeed: { 0.6875 },
        writeTrackingSpeed: { _ in false },
        readPointerAcceleration: { true },
        writePointerAcceleration: { _ in false }
    )
}

/// The live settings: the HID event system for what is in effect now, the global
/// preferences of the current user for what macOS applies at login. Main thread only.
enum MacPointerSystem {

    /// The preference keys System Settings writes (MachineSettings' `MouseScalingKey` and
    /// `UseLinearAccelerationKey`).
    static let trackingSpeedPreferenceKey = "com.apple.mouse.scaling"
    static let linearPreferenceKey = "com.apple.mouse.linear"
    /// The HID event system properties behind them.
    static let trackingSpeedProperty = kIOHIDMouseAccelerationType
    static let linearProperty = kIOHIDUseLinearScalingMouseAccelerationKey

    // MARK: Pure parts (unit tested)

    /// 1.5 -> 98304: the HID event system keeps accelerations in 16.16 fixed point.
    static func fixedPoint(_ value: Double) -> Int32 {
        return Int32((value * 65536).rounded())
    }

    static func double(fromFixedPoint value: Int) -> Double {
        return Double(value) / 65536
    }

    /// What is in effect (the event system), else what is stored; nil when neither is a number.
    /// `defaults write -g com.apple.mouse.scaling 2` without `-float` stores text: read too.
    static func trackingSpeed(property: Any?, preference: Any?) -> Double? {
        if let fixed = number(property) {
            return double(fromFixedPoint: fixed.intValue)
        }
        if let stored = number(preference) {
            return stored.doubleValue
        }
        if let text = preference as? String, let value = Double(text.trimmingCharacters(in: .whitespaces)) {
            return value
        }
        return nil
    }

    /// Acceleration is on unless linear tracking is set, in the event system or stored; on is
    /// also what macOS does when neither says anything.
    static func pointerAcceleration(property: Any?, preference: Any?) -> Bool {
        if let linear = property as? NSNumber {
            return linear.intValue == 0
        }
        if let linear = preference as? NSNumber {
            return !linear.boolValue
        }
        if let text = preference as? String {
            return !["1", "yes", "true"].contains(text.lowercased())
        }
        return true
    }

    /// A number that is not a Boolean (`NSNumber` bridges both).
    private static func number(_ value: Any?) -> NSNumber? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFNumberGetTypeID() else { return nil }
        return number
    }

    // MARK: Live

    /// The HID event system's simple client (public since macOS 10.13): it reads and sets the
    /// properties of the event system for the whole session, as System Settings does.
    private static let client: IOHIDEventSystemClient = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)

    private static func property(_ key: String) -> Any? {
        return IOHIDEventSystemClientCopyProperty(client, key as CFString)
    }

    private static func preference(_ key: String) -> Any? {
        return CFPreferencesCopyValue(
            key as CFString, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost
        )
    }

    /// Sets an event system property and reads it back: true only if the event system took it.
    private static func setProperty(_ key: String, _ value: NSNumber) -> Bool {
        guard IOHIDEventSystemClientSetProperty(client, key as CFString, value) else { return false }
        return (property(key) as? NSNumber)?.intValue == value.intValue
    }

    /// Stores `value` where `defaults write -g` would and System Settings does.
    private static func store(_ key: String, _ value: CFPropertyList) {
        CFPreferencesSetValue(
            key as CFString, value, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost
        )
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    static func trackingSpeed() -> Double? {
        return trackingSpeed(property: property(trackingSpeedProperty), preference: preference(trackingSpeedPreferenceKey))
    }

    static func setTrackingSpeed(_ value: Double) -> Bool {
        guard setProperty(trackingSpeedProperty, NSNumber(value: fixedPoint(value))) else { return false }
        store(trackingSpeedPreferenceKey, NSNumber(value: value))
        return true
    }

    static func pointerAcceleration() -> Bool? {
        return pointerAcceleration(property: property(linearProperty), preference: preference(linearPreferenceKey))
    }

    static func setPointerAcceleration(_ on: Bool) -> Bool {
        let linear = !on
        guard setProperty(linearProperty, NSNumber(value: Int8(linear ? 1 : 0))) else { return false }
        store(linearPreferenceKey, NSNumber(value: linear))
        return true
    }
}
