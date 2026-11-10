//
//  MouseWheelPresentation.swift
//  Mos
//  Pure helpers for the Mouse tab: where device data comes from, which wheel
//  controls are enabled and how device values are written out. Kept free of views
//  so the rules can be unit tested.
//

import Foundation

/// Where the Mouse tab reads connected devices from. `live` uses LogiCenter;
/// tests and screenshots pass fixtures instead, so no HID device is touched.
struct MouseWheelDeviceSource {
    var deviceStates: () -> [LogiWheelDeviceState]
    var refresh: () -> Void
    var showDiagnostics: () -> Void

    static let live = MouseWheelDeviceSource(
        deviceStates: { LogiCenter.shared.wheelDeviceStates() },
        refresh: { LogiCenter.shared.refreshWheelStates() },
        showDiagnostics: { LogiCenter.shared.showDebugPanel() }
    )
}

/// Which wheel controls can be edited.
struct MouseWheelControlRules: Equatable {
    /// Scroll mode: only while Mos manages the wheel.
    let modeEnabled: Bool
    /// SmartShift sensitivity: only in SmartShift mode, since the other modes ignore it.
    let sensitivityEnabled: Bool
    /// Scrolling force: only when a connected mouse can tune it.
    let scrollForceEnabled: Bool

    init(settings: LogiWheelSettings, devices: [LogiWheelDeviceState]) {
        let managed = settings.managedByMos
        modeEnabled = managed
        sensitivityEnabled = managed && settings.mode == .smartShift
        scrollForceEnabled = managed && devices.contains { $0.supportsScrollForce }
    }
}

/// Text shown in the Mouse tab.
enum MouseWheelText {

    /// Segment order of the scroll mode control.
    static let modes: [LogiWheelMode] = [.smartShift, .ratchet, .freeSpin]

    static func modeName(_ mode: LogiWheelMode) -> String {
        switch mode {
        case .smartShift: return NSLocalizedString("mouse-wheel-mode-smartshift", comment: "")
        case .ratchet: return NSLocalizedString("mouse-wheel-mode-ratchet", comment: "")
        case .freeSpin: return NSLocalizedString("mouse-wheel-mode-free-spin", comment: "")
        }
    }

    private static let percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    /// 40 -> "40%" (spacing follows the user's locale).
    static func percent(_ value: Int) -> String {
        return percentFormatter.string(from: NSNumber(value: Double(value) / 100)) ?? "\(value)%"
    }

    /// What a device lets Mos change, e.g. "SmartShift, Scrolling force".
    static func capabilities(of device: LogiWheelDeviceState) -> String {
        var parts: [String] = []
        if device.supportsSmartShift {
            parts.append(NSLocalizedString("mouse-device-supports-smartshift", comment: ""))
        }
        if device.supportsScrollForce {
            parts.append(NSLocalizedString("mouse-device-supports-scroll-force", comment: ""))
        }
        if parts.isEmpty {
            return NSLocalizedString("mouse-device-supports-none", comment: "")
        }
        return parts.joined(separator: ", ")
    }

    /// The values the mice last reported for one setting, or nil when none did.
    /// One mouse connected: "On the mouse: 40%". Several: "MX Master 3S: 40% · MX Anywhere 3: 55%",
    /// naming each mouse even when only one of them reports the value.
    static func readback(
        _ devices: [LogiWheelDeviceState],
        value: (LogiWheelDeviceState) -> String?
    ) -> String? {
        let reported = devices.compactMap { device -> (name: String, value: String)? in
            guard let text = value(device) else { return nil }
            return (device.deviceName, text)
        }
        guard let first = reported.first else { return nil }
        if devices.count == 1 {
            return String(format: NSLocalizedString("mouse-wheel-readback-one", comment: ""), first.value)
        }
        return reported
            .map { String(format: NSLocalizedString("mouse-wheel-readback-named", comment: ""), $0.name, $0.value) }
            .joined(separator: " · ")
    }

    static func modeReadback(_ devices: [LogiWheelDeviceState]) -> String? {
        return readback(devices) { $0.mode.map(modeName) }
    }

    static func sensitivityReadback(_ devices: [LogiWheelDeviceState]) -> String? {
        return readback(devices) { $0.smartShiftSensitivity.map(percent) }
    }

    static func scrollForceReadback(_ devices: [LogiWheelDeviceState]) -> String? {
        return readback(devices) { $0.scrollForce.map(percent) }
    }
}
