//
//  LogiHapticSettingsProtocol.swift
//  Mos
//
//  HID++ 2.0 byte layouts of the haptic settings of 0x19B0 (MX Master 4): on/off and
//  strength. The feature is not in the public HID++ documents; Solaar and OpenLogi
//  reverse-engineered it and disagree in places (marked ASSUMPTION). Pure functions, so
//  every byte decision is unit tested without a device. The waveform side (gesture cues)
//  is in LogiGestureProtocol; its "switch on" goes through `setStateParams` here, so there
//  is one definition of a state write.
//
//  Sources: OpenLogi openlogi-hidpp/src/feature/haptic_feedback.rs and
//  openlogi-device/src/write/haptic.rs, Solaar settings_templates.py (Haptic*),
//  the owner's MX Master 4 (system log, 2026-11).
//
//  Layouts (report = [reportId, devIdx, featureIdx, fn<<4 | swid, payload...]):
//
//    fn1 getState  -> payload [flags, strength, levels]
//                     flags bit0 = on, bit1 = power save (set by Logi Options+ for battery
//                     saving; never changed here), other bits unknown and kept as read.
//                     strength 0...100.
//                     levels: ASSUMPTION. Solaar: bit0 = "only four levels" (offer
//                     25/50/75/100). OpenLogi: high nibble step, low nibble count. Both
//                     read 0x00 as "no fixed steps". Kept in `hasFewLevels` only.
//                     Owner's MX Master 4: 11 FF 0B 11 00 64 00 ... = off, 100, levels 0x00.
//    fn2 setState  <- params  [flags, strength, 0], built from the last read state: only
//                     bit0 changes, so power save and the unknown bits survive, and
//                     switching off keeps the strength.
//                     The answer (OpenLogi: the state after the write) is not relied on;
//                     the state is read back with fn1.
//    fn4 play      <- params  [waveformId]
//
//  Traps: "on" with strength 0 is silent, so switching on from 0 uses 60 (the strength
//  Scrollio's gesture cues have always used). Solaar writes [0x00, 0x32] to switch off,
//  which also changes the strength: never do that.
//

import Foundation

enum LogiHapticSettingsProtocol {

    static let featureId: UInt16 = 0x19B0

    static let getStateFunction: UInt8 = 1
    static let setStateFunction: UInt8 = 2
    static let playFunction: UInt8 = 4

    static let onFlag: UInt8 = 0x01
    /// Strength used when switching on a mouse that reports 0.
    static let fallbackStrength: UInt8 = 60
    /// "Damp State Change": the pulse played after the strength changed.
    static let sampleWaveform: UInt8 = 0x01
    /// Strengths offered on mice that report only a few levels.
    static let fewLevelChoices: [Int] = [25, 50, 75, 100]

    struct State: Equatable {
        /// The whole flags byte as read.
        let flags: UInt8
        /// 0...100 (a larger byte is read as 100).
        let strength: UInt8
        /// The third payload byte, nil when the answer is too short to have it.
        let levelsByte: UInt8?

        var isOn: Bool { flags & LogiHapticSettingsProtocol.onFlag != 0 }
    }

    /// getState answer; nil when it is too short to hold flags and strength.
    static func parseState(_ report: [UInt8]) -> State? {
        guard report.count >= 6 else { return nil }
        return State(
            flags: report[4],
            strength: min(report[5], 100),
            levelsByte: report.count >= 7 ? report[6] : nil
        )
    }

    /// ASSUMPTION (Solaar's reading): bit0 of the levels byte = only a few strength levels.
    /// The one place to change when the owner's mouse settles the question.
    static func hasFewLevels(levelsByte: UInt8?) -> Bool? {
        guard let levelsByte else { return nil }
        return levelsByte & 0x01 != 0
    }

    /// 1...100, or the nearest of 25/50/75/100 on a mouse with few levels.
    static func snapStrength(_ strength: Int, fewLevels: Bool) -> Int {
        let clamped = min(max(strength, 1), 100)
        guard fewLevels else { return clamped }
        return fewLevelChoices.min { abs($0 - clamped) < abs($1 - clamped) } ?? clamped
    }

    /// setState parameters from the last read state.
    /// - on: nil keeps the on bit as read; true / false sets or clears only bit0.
    /// - strength: nil keeps the strength as read (also when switching off).
    /// Switching on (on == true) from strength 0 without a strength uses `fallbackStrength`.
    static func setStateParams(readFlags: UInt8, readStrength: UInt8, on: Bool?, strength: Int?) -> [UInt8] {
        var flags = readFlags
        if let on {
            flags = on ? readFlags | onFlag : readFlags & ~onFlag
        }
        var value = min(readStrength, 100)
        if let strength {
            value = UInt8(min(max(strength, 1), 100))
        } else if on == true, value == 0 {
            value = fallbackStrength
        }
        return [flags, value, 0]
    }

    /// True when `params` would change what the mouse reported.
    static func needsWrite(_ params: [UInt8], current: State) -> Bool {
        guard params.count >= 2 else { return false }
        return params[0] != current.flags || params[1] != current.strength
    }

    /// Play parameters for one waveform.
    static func playParams(waveform: UInt8) -> [UInt8] { [waveform] }

    static func describe(_ state: State) -> String {
        let levels = state.levelsByte.map { String(format: "0x%02X", $0) } ?? "-"
        let flags = String(format: "0x%02X", state.flags)
        return "\(state.isOn ? "on" : "off"), strength \(state.strength), flags \(flags), levels \(levels)"
    }
}
