//
//  LogiSystemLog.swift
//  Mos
//
//  Notes that also go to the system log, for things that have to be diagnosed without the
//  HID++ panel open (it keeps its log in memory only):
//
//      log show --last 10m --predicate 'subsystem == "com.nikklemenc.Scrollio"'
//
//  Low volume only: state changes and decisions, never per-event traffic.
//

import Foundation
import os

enum LogiSystemLog {

    private static let logger = os.Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Scrollio",
        category: "logi"
    )

    static func note(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }
}

/// How long the HID++ writes take. Each write (`IOHIDDeviceSetReport`) is synchronous on the
/// main thread, the thread that also serves the event taps; over Bluetooth nobody knew how
/// long one takes. This only measures and words the lines; it decides nothing.
///
/// - A write of `slowThreshold` or more: one line with its duration, what it asked (feature
///   index and function, or the receiver request) and the link, at most one such line every
///   `minimumLineInterval` with the number of slow writes and the longest since the last line.
/// - Once per connection, when the first batch of requests is done: the number of writes,
///   their total and the longest.
///
/// Times are monotonic nanoseconds (`DispatchTime.uptimeNanoseconds`). One per session, main
/// thread only, as the writes.
struct LogiWriteTiming {

    static let slowThreshold: UInt64 = 5_000_000
    static let minimumLineInterval: UInt64 = 1_000_000_000

    /// What a write asked.
    enum Request: Equatable {
        /// HID++ 2.0: feature index and function (0...15).
        case feature(index: UInt8, function: UInt8)
        /// IRoot.Ping of a receiver slot.
        case ping(slot: UInt8)
        /// HID++ 1.0 register read on the receiver.
        case receiverRegister(UInt8, long: Bool)

        var text: String {
            switch self {
            case let .feature(index, function):
                return String(format: "feature index 0x%02X, function %d", index, function)
            case let .ping(slot):
                return String(format: "ping of slot 0x%02X", slot)
            case let .receiverRegister(register, long):
                return String(format: "receiver register 0x%02X ", register) + (long ? "long read" : "read")
            }
        }
    }

    enum Link: Equatable {
        case bluetooth
        case receiver

        var text: String {
            switch self {
            case .bluetooth: return "over Bluetooth"
            case .receiver: return "through a receiver"
            }
        }
    }

    // Slow writes since the last line about them.
    private var slowSinceLine = 0
    private var longestSinceLine: UInt64 = 0
    private var lastSlowLineAt: UInt64?

    // The first batch.
    private(set) var setupWrites = 0
    private(set) var setupTotal: UInt64 = 0
    private(set) var setupLongest: UInt64 = 0
    private(set) var setupSummarized = false

    /// One write that took `duration`, ending at `now`.
    /// - Returns: the line to write, if one is due.
    mutating func record(duration: UInt64, now: UInt64, request: Request, link: Link) -> String? {
        if !setupSummarized {
            setupWrites += 1
            setupTotal += duration
            setupLongest = max(setupLongest, duration)
        }
        guard duration >= Self.slowThreshold else { return nil }
        slowSinceLine += 1
        longestSinceLine = max(longestSinceLine, duration)
        if let last = lastSlowLineAt, now &- last < Self.minimumLineInterval {
            return nil
        }
        let line = Self.slowLine(duration: duration, request: request, link: link,
                                 count: slowSinceLine, longest: longestSinceLine)
        slowSinceLine = 0
        longestSinceLine = 0
        lastSlowLineAt = now
        return line
    }

    /// The first batch of requests is done. Once per connection.
    /// - Returns: the summary line the first time, nil after.
    mutating func finishSetup(link: Link) -> String? {
        guard !setupSummarized else { return nil }
        setupSummarized = true
        return Self.setupLine(writes: setupWrites, total: setupTotal, longest: setupLongest, link: link)
    }

    static func milliseconds(_ nanoseconds: UInt64) -> String {
        return String(format: "%.1f ms", Double(nanoseconds) / 1_000_000)
    }

    static func slowLine(duration: UInt64, request: Request, link: Link, count: Int, longest: UInt64) -> String {
        return "Slow HID++ write: \(milliseconds(duration)) (\(request.text), \(link.text)); "
            + "\(count) \(count == 1 ? "write" : "writes") of 5 ms or more since the last such line, "
            + "longest \(milliseconds(longest))"
    }

    static func setupLine(writes: Int, total: UInt64, longest: UInt64, link: Link) -> String {
        return "HID++ writes while connecting (\(link.text)): \(writes), \(milliseconds(total)) in total, "
            + "longest \(milliseconds(longest))"
    }
}
