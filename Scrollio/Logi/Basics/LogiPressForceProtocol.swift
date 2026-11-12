//
//  LogiPressForceProtocol.swift
//  Mos
//
//  HID++ 2.0 byte layouts of FORCE_SENSING_BUTTON (0x19C0): how hard the thumb panel (the
//  "haptic sense panel" of the MX Master 4) has to be pressed. Button 0 only (the MX
//  Master 4 has one). Pure functions, so every byte decision is unit tested without a device.
//
//  Sources: Solaar hidpp20.py (ForceSensingButton), OpenLogi
//  openlogi-hidpp/src/feature/force_sensing_button.rs, openlogi-device/src/write/
//  force_sensing.rs and docs/CONFIGURATION.md, Mouser hid_gesture.py.
//
//  Layouts (report = [reportId, devIdx, featureIdx, fn<<4 | swid, payload...]):
//
//    fn0 getButtonCount   -> payload [count]                                (not used)
//    fn1 getButtonInfo    <- params  [button, 0, 0]
//                         -> payload [flags(2), default(2), max(2), min(2)], big-endian;
//                            flags bit0 = changeable.
//    fn2 getButtonCurrent <- params  [button, 0, 0]
//                         -> payload [current(2)]
//    fn3 setButtonConfig  <- params  [button, value(2)]; acknowledgement only, read back
//                            with fn2.
//
//  Units are raw and differ per unit (one MX Master 4: 4071...6768, default 5089);
//  lower = lighter press. ASSUMPTION until the info of more mice has been read: write
//  only when the button is changeable and the info is sane (min <= default <= max), and
//  clamp to [min, max] of this unit.
//

import Foundation

/// fn1 getButtonInfo of one button.
struct LogiPressForceInfo: Equatable {
    /// The firmware allows the force of this button to be changed.
    let changeable: Bool
    let minValue: UInt16
    let maxValue: UInt16
    let defaultValue: UInt16
}

enum LogiPressForceProtocol {

    static let featureId: UInt16 = 0x19C0
    /// The MX Master 4 has one force sensing button.
    static let button: UInt8 = 0

    static let infoFunction: UInt8 = 1
    static let currentFunction: UInt8 = 2
    static let setFunction: UInt8 = 3

    static func infoParams(button: UInt8 = LogiPressForceProtocol.button) -> [UInt8] { [button, 0, 0] }
    static func currentParams(button: UInt8 = LogiPressForceProtocol.button) -> [UInt8] { [button, 0, 0] }

    /// fn1 answer: four big-endian u16 [flags, default, max, min]; changeable = bit0 of flags.
    static func parseInfo(_ report: [UInt8]) -> LogiPressForceInfo? {
        guard report.count >= 12 else { return nil }
        let flags = u16(report, 4)
        return LogiPressForceInfo(
            changeable: flags & 0x01 != 0,
            minValue: u16(report, 10),
            maxValue: u16(report, 8),
            defaultValue: u16(report, 6)
        )
    }

    /// fn2 answer: the current threshold.
    static func parseCurrent(_ report: [UInt8]) -> UInt16? {
        guard report.count >= 6 else { return nil }
        return u16(report, 4)
    }

    /// fn3 parameters.
    static func setParams(button: UInt8 = LogiPressForceProtocol.button, value: UInt16) -> [UInt8] {
        return [button, UInt8(value >> 8), UInt8(value & 0xFF)]
    }

    /// `value` inside [min, max] of the info; unchanged when the info is unknown or its
    /// range is upside down.
    static func clamp(_ value: UInt16, info: LogiPressForceInfo?) -> UInt16 {
        guard let info, info.maxValue >= info.minValue else { return value }
        return min(max(value, info.minValue), info.maxValue)
    }

    /// A range that can be trusted for writing: min <= default <= max and a non-zero max.
    static func isValid(_ info: LogiPressForceInfo) -> Bool {
        return info.maxValue > 0
            && info.minValue <= info.maxValue
            && info.defaultValue >= info.minValue
            && info.defaultValue <= info.maxValue
    }

    static func describe(_ info: LogiPressForceInfo) -> String {
        return "\(info.minValue)...\(info.maxValue), default \(info.defaultValue), \(info.changeable ? "changeable" : "not changeable")"
    }

    private static func u16(_ report: [UInt8], _ offset: Int) -> UInt16 {
        return UInt16(report[offset]) << 8 | UInt16(report[offset + 1])
    }
}
