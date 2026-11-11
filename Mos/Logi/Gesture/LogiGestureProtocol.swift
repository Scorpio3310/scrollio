//
//  LogiGestureProtocol.swift
//  Mos
//
//  HID++ 2.0 byte layouts behind Gesture Navigation on Logitech mice: raw XY diversion
//  (REPROG_CONTROLS_V4, 0x1B04) and haptic pulses (0x19B0). Pure functions only, so every
//  byte decision can be unit tested without a device.
//
//  Sources: x1b04 spec (lekensteyn.nl/files/logitech/x1b04_specialkeysmsebuttons.html),
//  Solaar (hidpp20.py, special_keys.py), logiops, OpenLogi, Mouser. Nothing here has been
//  verified on hardware yet.
//
//  Layouts (report = [reportId, devIdx, featureIdx, fn<<4 | swid, payload...]):
//
//  0x1B04 REPROG_CONTROLS_V4
//    fn1 getCidInfo       -> payload [cid(2), task(2), flags1, pos, group, gmask, flags2]
//                            flags2 bit0 = raw_xy: the control can divert pointer movement.
//                            MX Master 3 / 3S / 4: 0x0052, 0x0053, 0x0056, 0x00C3, 0x00C4;
//                            MX Master 4 also 0x01A0 (haptic sense panel).
//    fn2 getCidReporting  -> payload [cid(2), flags, remap(2)]: bit0 diverted, bit4 raw XY
//    fn3 setCidReporting  <- params  [cid(2), flags, remap(2)]
//                            bit0 divert          bit1 divert valid
//                            bit2 persist         bit3 persist valid     (never set by Mos)
//                            bit4 raw XY          bit5 raw XY valid
//                            bit6 force raw XY    bit7 force valid       (never set by Mos)
//                            A value bit only counts when its valid bit is set; remap 0
//                            keeps the current target. The response echoes the request.
//                            A change takes effect at the next press of the control.
//    event fn0 (swid 0)   -> payload [cid(2) x 4]: the diverted controls held right now
//    event fn1 (swid 0)   -> payload [dx(2), dy(2)]: signed 16-bit big-endian sensor counts,
//                            sent while a control armed for raw XY is held; the firmware
//                            does not move the pointer meanwhile. +x right, +y towards the
//                            user (the direction of a CGEvent delta).
//
//  0x19B0 HAPTIC (MX Master 4)
//    fn0 getCapabilities  -> payload [4 bytes, waveform mask u32 big-endian]: bit n = waveform n
//    fn1 getState         -> payload [flags: bit0 enabled, bit1 power save; intensity 0...100]
//    fn2 setState         <- the same two bytes. Intensity is global, so the gesture cues
//                            never send it.
//    fn4 play             <- params  [waveformId]
//

import Foundation

enum LogiGestureProtocol {

    // MARK: - 0x1B04 control capabilities

    /// `raw_xy` in the control flags of getCidInfo (flags1 | flags2 << 8, as the session stores them).
    static let controlFlagRawXY: UInt16 = 0x0100

    static func supportsRawXY(controlFlags: UInt16) -> Bool {
        return controlFlags & controlFlagRawXY != 0
    }

    // MARK: - 0x1B04 setCidReporting

    static let setReportingFunction: UInt8 = 3

    static let flagDivert: UInt8 = 0x01
    static let flagDivertValid: UInt8 = 0x02
    static let flagRawXY: UInt8 = 0x10
    static let flagRawXYValid: UInt8 = 0x20

    /// Everything Mos ever asks of one control. Temporary flags only: they are gone when the
    /// mouse reconnects, so nothing here can outlive a power cycle.
    enum ReportingChange: Equatable, CaseIterable {
        /// Divert the button, leave raw XY as it is. What Mos has always sent.
        case divert
        /// Give the button back, leave raw XY as it is. What Mos has always sent.
        case undivert
        /// "Arm": divert the button and let the mouse report movement while it is held.
        case divertWithRawXY
        /// Keep the button diverted, pointer movement back to normal.
        case divertWithoutRawXY
        /// "Disarm": give the button back and turn raw XY off.
        case undivertAndClearRawXY

        var flags: UInt8 {
            switch self {
            case .divert:                return 0x03
            case .undivert:              return 0x02
            case .divertWithRawXY:       return 0x33
            case .divertWithoutRawXY:    return 0x23
            case .undivertAndClearRawXY: return 0x22
            }
        }

        var diverts: Bool { flags & LogiGestureProtocol.flagDivert != 0 }
    }

    /// setCidReporting parameters. The remap target stays 0 (unchanged).
    static func reportingParams(cid: UInt16, flags: UInt8) -> [UInt8] {
        return [UInt8(cid >> 8), UInt8(cid & 0xFF), flags, 0x00, 0x00]
    }

    /// True when a setCidReporting echo confirms the arm request.
    static func acknowledgesRawXY(flags: UInt8) -> Bool {
        return flags == ReportingChange.divertWithRawXY.flags
    }

    /// True when a getCidReporting answer says raw XY is on for the control.
    static func reportsRawXY(reportingFlags: UInt8) -> Bool {
        return reportingFlags & flagRawXY != 0
    }

    // MARK: - 0x1B04 raw XY event

    /// Byte 3 of a raw XY event: function 1, software id 0. A getCidInfo answer has the same
    /// function number but carries Mos's software id, so the two cannot be mixed up.
    static let rawXYEventFunctionByte: UInt8 = 0x10

    static func isRawXYEvent<Bytes: RandomAccessCollection>(_ report: Bytes) -> Bool
    where Bytes.Element == UInt8, Bytes.Index == Int {
        return report.count >= 8 && report[report.startIndex + 3] == rawXYEventFunctionByte
    }

    /// Movement in sensor counts, or nil when the report is not a raw XY event.
    static func rawXYDelta<Bytes: RandomAccessCollection>(_ report: Bytes) -> (deltaX: Int, deltaY: Int)?
    where Bytes.Element == UInt8, Bytes.Index == Int {
        guard isRawXYEvent(report) else { return nil }
        let base = report.startIndex
        let deltaX = Int16(bitPattern: UInt16(report[base + 4]) << 8 | UInt16(report[base + 5]))
        let deltaY = Int16(bitPattern: UInt16(report[base + 6]) << 8 | UInt16(report[base + 7]))
        return (Int(deltaX), Int(deltaY))
    }

    // MARK: - 0x19B0 haptics

    static let hapticCapabilitiesFunction: UInt8 = 0
    static let hapticGetStateFunction: UInt8 = 1
    /// Never sent by the gesture cues: it would change the user's intensity and power saving.
    static let hapticSetStateFunction: UInt8 = 2
    static let hapticPlayFunction: UInt8 = 4

    /// Waveform ids as OpenLogi uses them: "Subtle Collision" at a gesture threshold and
    /// "Damp State Change" on commit.
    static func waveform(for cue: MouseGestureHapticCue) -> UInt8 {
        switch cue {
        case .lockIn: return 0x04
        case .commit: return 0x01
        }
    }

    /// getCapabilities answer: bit n set = the mouse can play waveform n.
    static func hapticWaveformMask(_ report: [UInt8]) -> UInt32? {
        guard report.count >= 12 else { return nil }
        return UInt32(report[8]) << 24 | UInt32(report[9]) << 16 | UInt32(report[10]) << 8 | UInt32(report[11])
    }

    /// getState answer: whether the user has haptics switched on. Intensity and power saving
    /// are the user's business and are not read.
    static func hapticsEnabled(_ report: [UInt8]) -> Bool? {
        guard report.count >= 6 else { return nil }
        return report[4] & 0x01 != 0
    }

    static func supports(waveform: UInt8, mask: UInt32) -> Bool {
        return waveform < 32 && (mask >> UInt32(waveform)) & 1 != 0
    }
}
