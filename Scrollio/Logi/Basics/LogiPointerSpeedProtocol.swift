//
//  LogiPointerSpeedProtocol.swift
//  Mos
//
//  HID++ 2.0 byte layouts of ADJUSTABLE_DPI (0x2201), the pointer speed of the MX Master
//  4, 3S and 3 (none of them has 0x2202 or 0x2205). Sensor 0 only. Pure functions, so
//  every byte decision is unit tested without a device.
//
//  Sources: OpenLogi openlogi-hidpp/src/feature/adjustable_dpi.rs, Solaar
//  settings_templates.py (AdjustableDpi). Nothing here was seen on hardware yet.
//
//  Layouts (report = [reportId, devIdx, featureIdx, fn<<4 | swid, payload...]):
//
//    fn0 getSensorCount    -> payload [count]                          (not used)
//    fn1 getSensorDpiList  <- params  [sensor, 0, 0]
//                          -> payload [sensor, up to 7 big-endian u16 ...]
//                             each u16 is a DPI value, or a range marker 0xE000 | step
//                             (top three bits set) meaning "from the value before to the
//                             value after, in steps of `step`" (the high end is always
//                             valid); 0x0000 ends the list and is absent when the answer
//                             is full. MX Master class: 00C8 E032 1F40 0000 would be
//                             200...8000 in steps of 50 (ASSUMPTION: the actual bytes of
//                             a real mouse were never read for this).
//    fn2 getSensorDpi      <- params  [sensor, 0, 0]
//                          -> payload [sensor, current(2), default(2)]
//                             default is 0 when the mouse has none; a current of 0 means
//                             "the default" (Solaar).
//    fn3 setSensorDpi      <- params  [sensor, dpi(2)]; read back with fn2.
//
//  Never write a value that is not in the list (Solaar validates against it): snap first.
//

import Foundation

enum LogiPointerSpeedProtocol {

    static let featureId: UInt16 = 0x2201
    static let sensor: UInt8 = 0

    static let listFunction: UInt8 = 1
    static let getFunction: UInt8 = 2
    static let setFunction: UInt8 = 3

    /// Top three bits set: a range step, not a DPI value.
    static let rangeMarkerMask: UInt16 = 0xE000
    /// A malformed range must not expand into a huge list.
    static let maxChoices = 2000

    /// The DPI list as the mouse sent it, expanded.
    struct DPIList: Equatable {
        /// Every accepted value, ascending, without duplicates.
        let values: [Int]
        /// The answer ended with 0x0000. A full answer without it may continue on a page
        /// Scrollio does not ask for (no source documents paging for these mice).
        let terminated: Bool
    }

    static func listParams() -> [UInt8] { [sensor, 0, 0] }
    static func getParams() -> [UInt8] { [sensor, 0, 0] }

    /// setSensorDpi parameters, or nil for a value no list can hold.
    static func setParams(dpi: Int) -> [UInt8]? {
        guard dpi > 0, dpi < Int(rangeMarkerMask) else { return nil }
        return [sensor, UInt8(dpi >> 8), UInt8(dpi & 0xFF)]
    }

    /// getSensorDpiList answer. nil when it is short, for another sensor, or malformed
    /// (a marker without a value on both sides, a step of 0, a range that goes down).
    static func parseDPIList(_ report: [UInt8]) -> DPIList? {
        guard report.count >= 7, report[4] == sensor else { return nil }
        var tokens: [UInt16] = []
        var terminated = false
        var offset = 5
        while offset + 1 < report.count {
            let value = UInt16(report[offset]) << 8 | UInt16(report[offset + 1])
            if value == 0 {
                terminated = true
                break
            }
            tokens.append(value)
            offset += 2
        }
        var values: [Int] = []
        var pendingStep: Int?
        for token in tokens {
            if token & rangeMarkerMask == rangeMarkerMask {
                let step = Int(token & ~rangeMarkerMask)
                guard pendingStep == nil, !values.isEmpty, step > 0 else { return nil }
                pendingStep = step
                continue
            }
            let value = Int(token)
            if let step = pendingStep, let low = values.last {
                guard value > low else { return nil }
                var next = low + step
                while next < value {
                    values.append(next)
                    guard values.count <= maxChoices else { return nil }
                    next += step
                }
                pendingStep = nil
            }
            values.append(value)
            guard values.count <= maxChoices else { return nil }
        }
        guard pendingStep == nil, !values.isEmpty else { return nil }
        return DPIList(values: Array(Set(values)).sorted(), terminated: terminated)
    }

    /// getSensorDpi answer: the current DPI (the default when the mouse reports 0) and the
    /// default (nil when the mouse has none). nil when short, for another sensor, or when
    /// neither value is known.
    static func parseCurrent(_ report: [UInt8]) -> (current: Int, defaultDPI: Int?)? {
        guard report.count >= 7, report[4] == sensor else { return nil }
        let current = Int(UInt16(report[5]) << 8 | UInt16(report[6]))
        var defaultDPI: Int?
        if report.count >= 9 {
            let value = Int(UInt16(report[7]) << 8 | UInt16(report[8]))
            defaultDPI = value == 0 ? nil : value
        }
        if current != 0 { return (current, defaultDPI) }
        guard let defaultDPI else { return nil }
        return (defaultDPI, defaultDPI)
    }

    /// The list member nearest to `dpi` (the lower one on a tie); nil for an empty list.
    static func snap(_ dpi: Int, to choices: [Int]) -> Int? {
        return choices.min { lhs, rhs in
            let l = abs(lhs - dpi), r = abs(rhs - dpi)
            return l != r ? l < r : lhs < rhs
        }
    }

    // MARK: - Steps of the "Increase / Decrease Pointer Speed" button actions

    /// The speeds a button steps through on a mouse that accepts a fine range (an MX Master
    /// lists 200...8000 in steps of 50: one step of the list, 1600 to 1650, cannot be felt).
    static let cycleStops: [Int] = [400, 800, 1000, 1200, 1600, 2000, 2400, 3200, 4000, 6000, 8000]

    /// The stops for a mouse with these accepted values: a short list is its own set of
    /// stops (400, 800, 1600, 3200); from a long one, `cycleStops` snapped to the list, with
    /// its lowest and highest value so that both ends can be reached.
    static func cycleStops(for choices: [Int]) -> [Int] {
        let sorted = Array(Set(choices)).sorted()
        guard sorted.count > cycleStops.count, let low = sorted.first, let high = sorted.last else { return sorted }
        let inRange = cycleStops.filter { $0 >= low && $0 <= high }.compactMap { snap($0, to: sorted) }
        return Array(Set(inRange + [low, high])).sorted()
    }

    /// The value one press moves to from `current`: the next stop above or below it. nil at
    /// the end of the scale (nothing is written then). Always a value of `choices`.
    static func cycleTarget(from current: Int, up: Bool, choices: [Int]) -> Int? {
        let stops = cycleStops(for: choices)
        return up ? stops.first(where: { $0 > current }) : stops.last(where: { $0 < current })
    }

    /// Short text for the log: "200...8000 (157 values)" or "400, 800, 1600".
    static func describe(_ list: DPIList) -> String {
        let values = list.values
        let text = values.count <= 8
            ? values.map(String.init).joined(separator: ", ")
            : "\(values.first ?? 0)...\(values.last ?? 0) (\(values.count) values)"
        return list.terminated ? text : text + ", no end marker"
    }
}
