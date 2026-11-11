//
//  LogiBatteryProtocol.swift
//  Mos
//
//  HID++ 2.0 byte layouts of the two battery features. Read only: Scrollio never writes
//  to them. Pure functions, so every byte decision is unit tested without a device.
//
//  Sources: Solaar hidpp20.py (decipher_battery_status / decipher_battery_unified) and
//  notifications.py, OpenLogi openlogi-hidpp/src/feature/unified_battery.rs and
//  battery_status.rs, Mouser hid_gesture.py. Nothing here was seen on hardware yet.
//
//  Layouts (report = [reportId, devIdx, featureIdx, fn<<4 | swid, payload...]):
//
//  0x1004 UNIFIED_BATTERY (MX Master 4, MX Master 3S, MX Master 3 for Business)
//    fn0 getCapabilities -> payload [levels mask, flags]   (not used)
//    fn1 getStatus       -> payload [stateOfCharge %, level, chargingStatus, ...]
//                           level: 1 critical, 2 low, 4 good, 8 full.
//                           Bytes after chargingStatus are not documented anywhere: unused.
//    event fn0 (swid 0)  -> the getStatus payload, sent when the battery changes.
//  0x1000 BATTERY_STATUS (original MX Master 3)
//    fn0 getBatteryLevelStatus -> payload [discharge level %, next level %, status]
//                           level 0 = unknown (the firmware reports 0 while not discharging);
//                           the MX Master 3 reports coarse steps (100, 50, ...).
//    event fn0 (swid 0)  -> the same three bytes.
//
//  Charging status (both): 0 discharging, 1 charging, 2 charging, nearly full, 3 full,
//  4 slow charging, 5 invalid battery, 6 thermal error, 7 other charging error.
//

import Foundation

/// Which battery feature a mouse exposes. 0x1004 is preferred when both exist.
enum LogiBatteryFeature: Equatable {
    case unified
    case legacy

    static let unifiedFeatureId: UInt16 = 0x1004
    static let legacyFeatureId: UInt16 = 0x1000

    var featureId: UInt16 {
        switch self {
        case .unified: return Self.unifiedFeatureId
        case .legacy: return Self.legacyFeatureId
        }
    }

    /// The function that reads the status. 0x1004 fn0 is getCapabilities, not the status.
    var statusFunction: UInt8 {
        switch self {
        case .unified: return 1
        case .legacy: return 0
        }
    }
}

enum LogiBatteryProtocol {

    /// Battery events carry function 0 and software id 0 on both features.
    static let eventFunction: UInt8 = 0

    /// A report on the battery feature index is a battery-changed event.
    static func isStatusEvent(functionId: UInt8, softwareId: UInt8) -> Bool {
        return functionId == eventFunction && softwareId == 0
    }

    /// The status of a getStatus answer or a battery event; nil for a short report.
    static func parseStatus(_ report: [UInt8], feature: LogiBatteryFeature) -> LogiMouseDeviceState.Battery? {
        switch feature {
        case .unified: return unifiedStatus(report)
        case .legacy: return legacyStatus(report)
        }
    }

    /// 0x1004: [stateOfCharge, level, chargingStatus]. A state of charge of 0 means the
    /// mouse reports only the level (Solaar shows the level then).
    static func unifiedStatus(_ report: [UInt8]) -> LogiMouseDeviceState.Battery? {
        guard report.count >= 7 else { return nil }
        return LogiMouseDeviceState.Battery(
            percent: percent(report[4]),
            level: level(unifiedLevelByte: report[5]),
            charging: charging(statusByte: report[6]),
            isApproximate: false
        )
    }

    /// 0x1000: [dischargeLevel, nextLevel, status]. No level byte; the percentage comes in
    /// coarse steps.
    static func legacyStatus(_ report: [UInt8]) -> LogiMouseDeviceState.Battery? {
        guard report.count >= 7 else { return nil }
        let charging = charging(statusByte: report[6])
        return LogiMouseDeviceState.Battery(
            percent: percent(report[4]),
            level: charging == .full ? .full : .unknown,
            charging: charging,
            isApproximate: true
        )
    }

    /// 1...100; 0 (unknown) and anything above 100 (malformed) give nil.
    static func percent(_ byte: UInt8) -> Int? {
        guard byte > 0, byte <= 100 else { return nil }
        return Int(byte)
    }

    static func level(unifiedLevelByte byte: UInt8) -> LogiMouseDeviceState.Battery.Level {
        switch byte {
        case 1: return .critical
        case 2: return .low
        case 4: return .good
        case 8: return .full
        default: return .unknown
        }
    }

    static func charging(statusByte byte: UInt8) -> LogiMouseDeviceState.Battery.Charging {
        switch byte {
        case 0: return .discharging
        case 1: return .charging
        case 2: return .almostFull
        case 3: return .full
        case 4: return .chargingSlowly
        case 5, 6, 7: return .problem
        default: return .unknown
        }
    }

    /// One log line: "45 %, discharging, level good" / "about 50 %, charging".
    static func describe(_ battery: LogiMouseDeviceState.Battery) -> String {
        var parts: [String] = []
        if let percent = battery.percent {
            parts.append(battery.isApproximate ? "about \(percent) %" : "\(percent) %")
        } else {
            parts.append("no percentage")
        }
        parts.append("\(battery.charging)")
        if battery.level != .unknown { parts.append("level \(battery.level)") }
        return parts.joined(separator: ", ")
    }
}
