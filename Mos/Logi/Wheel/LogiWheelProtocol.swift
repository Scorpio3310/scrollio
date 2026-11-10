//
//  LogiWheelProtocol.swift
//  Mos
//
//  HID++ 2.0 byte layouts and value mappings for the scroll-wheel features
//  SmartShift (0x2110) and SmartShift Enhanced (0x2111). Pure functions only,
//  so every byte decision can be unit tested without a device.
//
//  Sources: x2110 SmartShift spec (lekensteyn.nl/files/logitech/x2110_smartshift.html),
//  Solaar settings_templates.py (SmartShift / SmartShiftEnhanced / ScrollRatchetTorque),
//  OpenLogi openlogi-hidpp/src/feature/smartshift_enhanced.rs, Mouser hid_gesture.py.
//
//  Layouts (report = [reportId, devIdx, featureIdx, fn<<4|swid, payload...]):
//
//  0x2110 SmartShift
//    fn0 getRatchetControlMode  -> payload [wheelMode, autoDisengage, autoDisengageDefault]
//    fn1 setRatchetControlMode  <- params  [wheelMode, autoDisengage, autoDisengageDefault]
//  0x2111 SmartShift Enhanced
//    fn0 getCapabilities        -> payload [caps (bit0 = tunable torque), autoDisengageDefault,
//                                           defaultTorque, maxForce]
//    fn1 getRatchetControlMode  -> payload [wheelMode, autoDisengage, torque]
//    fn2 setRatchetControlMode  <- params  [wheelMode, autoDisengage, torque]
//
//  wheelMode: 1 = free-spin, 2 = ratchet. It is the SETTING, not the live ratchet:
//  while SmartShift has auto-disengaged the wheel it still reads 2.
//  autoDisengage: 0x01...0xFE = disengage above N/4 wheel turns per second,
//  0xFF = never disengage (always ratchet). torque: 1...100 % of max force.
//  In every set request 0 means "leave this field unchanged".
//

import Foundation

/// Which wheel feature a device exposes. Enhanced (0x2111) is preferred when both exist.
enum LogiWheelFeature: Equatable {
    /// 0x2110 SmartShift (e.g. MX Master 3S)
    case smartShift
    /// 0x2111 SmartShift Enhanced with optional tunable torque (e.g. MX Master 4)
    case smartShiftEnhanced

    static let smartShiftFeatureId: UInt16 = 0x2110
    static let smartShiftEnhancedFeatureId: UInt16 = 0x2111

    var featureId: UInt16 {
        switch self {
        case .smartShift: return Self.smartShiftFeatureId
        case .smartShiftEnhanced: return Self.smartShiftEnhancedFeatureId
        }
    }

    /// Function that reads [wheelMode, autoDisengage, ...]. The enhanced feature shifts the
    /// table by one (fn0 = capabilities), so 0x2110 numbers must never be used on 0x2111.
    var readStatusFunction: UInt8 {
        switch self {
        case .smartShift: return 0
        case .smartShiftEnhanced: return 1
        }
    }

    var writeStatusFunction: UInt8 {
        switch self {
        case .smartShift: return 1
        case .smartShiftEnhanced: return 2
        }
    }

    /// getCapabilities exists only on 0x2111.
    var capabilitiesFunction: UInt8? {
        switch self {
        case .smartShift: return nil
        case .smartShiftEnhanced: return 0
        }
    }
}

/// Parsed getRatchetControlMode response.
struct LogiWheelStatus: Equatable {
    /// 1 = free-spin, 2 = ratchet (SmartShift or fixed, see autoDisengage)
    let wheelMode: UInt8
    /// 0x01...0xFE = threshold in quarter turns per second, 0xFF = always ratchet
    let autoDisengage: UInt8
    /// Ratchet torque 1...100 % (0x2111 only); nil on 0x2110 or when the device reports 0
    let torque: UInt8?
}

/// Parsed 0x2111 getCapabilities response.
struct LogiWheelCapabilities: Equatable {
    let tunableTorque: Bool
    let autoDisengageDefault: UInt8
    let defaultTorque: UInt8
}

enum LogiWheelProtocol {

    static let wheelModeFreeSpin: UInt8 = 1
    static let wheelModeRatchet: UInt8 = 2
    /// autoDisengage value that keeps the ratchet engaged (SmartShift off).
    static let autoDisengageNever: UInt8 = 0xFF
    /// "Leave unchanged" in every set request field.
    static let unchanged: UInt8 = 0

    // MARK: - Sensitivity <-> autoDisengage
    //
    // Logi Options+ does not publish how its 1...100 % "Sensitivity" maps to the
    // autoDisengage byte, so Mos uses its own documented, monotonic mapping:
    //
    //   sensitivity   1 %  -> 50  (12.5 turns/s: hardest to trigger, Solaar/OpenLogi/Mouser slider max)
    //   sensitivity  50 %  -> 16  ( 4   turns/s: Logitech factory default, the Mos default)
    //   sensitivity 100 %  ->  8  ( 2   turns/s: OpenLogi floor; lower values free-spin
    //                               during normal scrolling, OpenLogi issue #317)
    //
    // linear between those points, rounded. Higher % = lower threshold = the wheel
    // switches to free-spin sooner, as in Logi Options+. Reading back clamps device
    // values outside 8...50 to 100 % / 1 %; 0xFF (always ratchet) has no sensitivity.

    static let autoDisengageMostSensitive: UInt8 = 8
    static let autoDisengageDefault: UInt8 = 16
    static let autoDisengageLeastSensitive: UInt8 = 50
    private static let sensitivityMidpoint = 50

    static func autoDisengage(forSensitivity sensitivity: Int) -> UInt8 {
        let range = LogiWheelSettings.sensitivityRange
        let pct = min(max(sensitivity, range.lowerBound), range.upperBound)
        let least = Double(autoDisengageLeastSensitive)
        let mid = Double(autoDisengageDefault)
        let most = Double(autoDisengageMostSensitive)
        let value: Double
        if pct <= sensitivityMidpoint {
            let t = Double(pct - range.lowerBound) / Double(sensitivityMidpoint - range.lowerBound)
            value = least - t * (least - mid)
        } else {
            let t = Double(pct - sensitivityMidpoint) / Double(range.upperBound - sensitivityMidpoint)
            value = mid - t * (mid - most)
        }
        return UInt8(value.rounded())
    }

    /// nil when the byte carries no threshold (0 = invalid, 0xFF = SmartShift off).
    static func sensitivity(forAutoDisengage value: UInt8) -> Int? {
        guard value != unchanged, value != autoDisengageNever else { return nil }
        let range = LogiWheelSettings.sensitivityRange
        if value >= autoDisengageLeastSensitive { return range.lowerBound }
        if value <= autoDisengageMostSensitive { return range.upperBound }
        let least = Double(autoDisengageLeastSensitive)
        let mid = Double(autoDisengageDefault)
        let most = Double(autoDisengageMostSensitive)
        let v = Double(value)
        let pct: Double
        if v >= mid {
            pct = Double(range.lowerBound) + (least - v) / (least - mid) * Double(sensitivityMidpoint - range.lowerBound)
        } else {
            pct = Double(sensitivityMidpoint) + (mid - v) / (mid - most) * Double(range.upperBound - sensitivityMidpoint)
        }
        return min(max(Int(pct.rounded()), range.lowerBound), range.upperBound)
    }

    // MARK: - Mode / torque projection

    static func mode(for status: LogiWheelStatus) -> LogiWheelMode? {
        switch status.wheelMode {
        case wheelModeFreeSpin:
            return .freeSpin
        case wheelModeRatchet:
            return status.autoDisengage == autoDisengageNever ? .ratchet : .smartShift
        default:
            return nil
        }
    }

    static func clampedTorque(_ value: Int) -> UInt8 {
        let range = LogiWheelSettings.scrollForceRange
        return UInt8(min(max(value, range.lowerBound), range.upperBound))
    }

    // MARK: - Parsing (full report bytes, payload starts at index 4)

    static func parseStatus(_ report: [UInt8], feature: LogiWheelFeature) -> LogiWheelStatus? {
        guard report.count >= 6 else { return nil }
        let torque: UInt8?
        switch feature {
        case .smartShift:
            torque = nil
        case .smartShiftEnhanced:
            guard report.count >= 7 else { return nil }
            torque = report[6] == 0 ? nil : min(report[6], 100)
        }
        return LogiWheelStatus(wheelMode: report[4], autoDisengage: report[5], torque: torque)
    }

    static func parseCapabilities(_ report: [UInt8]) -> LogiWheelCapabilities? {
        guard report.count >= 7 else { return nil }
        return LogiWheelCapabilities(
            tunableTorque: report[4] & 0x01 != 0,
            autoDisengageDefault: report[5],
            defaultTorque: report[6]
        )
    }

    // MARK: - Set request encoding

    /// setRatchetControlMode parameters for the user's settings.
    /// - freeSpin:   [1, unchanged, torque?]
    /// - ratchet:    [2, 0xFF, torque?]   (auto-disengage disabled)
    /// - smartShift: [2, threshold(sensitivity), torque?]
    /// 0x2110 gets a third byte 0 (autoDisengageDefault unchanged). On 0x2111 the torque
    /// byte is written only when the device reports tunable torque, otherwise 0 (unchanged).
    /// The mode byte is always explicit: MX Master 4 ignores torque writes without it.
    static func setParams(
        for settings: LogiWheelSettings,
        feature: LogiWheelFeature,
        supportsTorque: Bool
    ) -> [UInt8] {
        let modeByte: UInt8
        let disengageByte: UInt8
        switch settings.mode {
        case .freeSpin:
            modeByte = wheelModeFreeSpin
            disengageByte = unchanged
        case .ratchet:
            modeByte = wheelModeRatchet
            disengageByte = autoDisengageNever
        case .smartShift:
            modeByte = wheelModeRatchet
            disengageByte = autoDisengage(forSensitivity: settings.smartShiftSensitivity)
        }
        let thirdByte: UInt8
        switch feature {
        case .smartShift:
            thirdByte = unchanged
        case .smartShiftEnhanced:
            thirdByte = supportsTorque ? clampedTorque(settings.scrollForce) : unchanged
        }
        return [modeByte, disengageByte, thirdByte]
    }

    /// Parameters that flip free-spin <-> ratchet and keep threshold and torque
    /// (the "SmartShift Toggle" action, like the mode-shift button).
    static func toggleParams(from status: LogiWheelStatus) -> [UInt8] {
        let newMode = status.wheelMode == wheelModeRatchet ? wheelModeFreeSpin : wheelModeRatchet
        return [newMode, unchanged, unchanged]
    }

    /// True when writing `params` would change anything on a device reporting `status`.
    /// Avoids needless writes: the firmware keeps these values in non-volatile memory.
    static func needsWrite(_ params: [UInt8], current status: LogiWheelStatus?) -> Bool {
        guard let status = status else { return true }
        if params.count > 0, params[0] != unchanged, params[0] != status.wheelMode { return true }
        if params.count > 1, params[1] != unchanged, params[1] != status.autoDisengage { return true }
        if params.count > 2, params[2] != unchanged, params[2] != (status.torque ?? 0) { return true }
        return false
    }
}
