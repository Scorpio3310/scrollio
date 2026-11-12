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

/// How long the HID++ writes take, and how long the main thread is held by them. A write
/// (`IOHIDDeviceSetReport`) returns only when the device has taken the report: 15 to 29 ms
/// over Bluetooth. The writes run on the session's own queue (`LogiReportWriter`), so the
/// main thread, which serves the event taps, only queues them. This only measures and words
/// the lines; it decides nothing.
///
/// - A write of `slowThreshold` or more (a link that struggles): one line with its duration,
///   what it asked (feature index and function, or the receiver request) and the link, at
///   most one such line every `minimumLineInterval` with the number of slow writes and the
///   longest since the last line.
/// - A write the device refused: one line with the result, limited the same way.
/// - Once per connection, when the first batch of requests is done: the number of writes,
///   their total and the longest on the write queue, and how long the main thread was held
///   to queue them.
///
/// Times are monotonic nanoseconds (`DispatchTime.uptimeNanoseconds`). One per session, main
/// thread only (the writer delivers its outcomes there).
struct LogiWriteTiming {

    /// A write this long means the link struggles (an ordinary Bluetooth write takes 15 to
    /// 29 ms; it no longer holds the main thread, so it is no line's worth by itself).
    static let slowThreshold: UInt64 = 100_000_000
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

    // Refused writes since the last line about them.
    private var failedSinceLine = 0
    private var lastFailureLineAt: UInt64?

    // The first batch.
    private(set) var setupWrites = 0
    private(set) var setupTotal: UInt64 = 0
    private(set) var setupLongest: UInt64 = 0
    private(set) var setupMainThread: UInt64 = 0
    private(set) var setupSummarized = false

    /// The main thread was held for `held` to queue one write.
    mutating func noteQueued(mainThreadHeld held: UInt64) {
        if !setupSummarized {
            setupMainThread += held
        }
    }

    /// The device refused a write (`result` is not success), at `now`.
    /// - Returns: the line to write, if one is due.
    mutating func recordFailure(result: Int32, now: UInt64, request: Request, link: Link) -> String? {
        failedSinceLine += 1
        if let last = lastFailureLineAt, now &- last < Self.minimumLineInterval {
            return nil
        }
        let line = Self.failureLine(result: result, request: request, link: link, count: failedSinceLine)
        failedSinceLine = 0
        lastFailureLineAt = now
        return line
    }

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
        return Self.setupLine(writes: setupWrites, total: setupTotal, longest: setupLongest,
                              mainThread: setupMainThread, link: link)
    }

    static func milliseconds(_ nanoseconds: UInt64) -> String {
        return String(format: "%.1f ms", Double(nanoseconds) / 1_000_000)
    }

    static func slowLine(duration: UInt64, request: Request, link: Link, count: Int, longest: UInt64) -> String {
        return "Slow HID++ write: \(milliseconds(duration)) (\(request.text), \(link.text)); "
            + "\(count) \(count == 1 ? "write" : "writes") of 100 ms or more since the last such line, "
            + "longest \(milliseconds(longest))"
    }

    static func failureLine(result: Int32, request: Request, link: Link, count: Int) -> String {
        return String(format: "HID++ write refused: 0x%08x", UInt32(bitPattern: result))
            + " (\(request.text), \(link.text)); "
            + "\(count) refused \(count == 1 ? "write" : "writes") since the last such line"
    }

    static func setupLine(writes: Int, total: UInt64, longest: UInt64, mainThread: UInt64, link: Link) -> String {
        return "HID++ writes while connecting (\(link.text)): \(writes), \(milliseconds(total)) in total "
            + "on the write queue, longest \(milliseconds(longest)); the main thread was held "
            + "\(milliseconds(mainThread)) to queue them"
    }

    /// The main thread waited `waited` for the queued writes before a device was let go.
    static func drainLine(waited: UInt64, finished: Bool, reason: String) -> String {
        return finished
            ? "Waited \(milliseconds(waited)) for the queued HID++ writes (\(reason))"
            : "The queued HID++ writes did not finish within \(milliseconds(waited)) (\(reason)); going on without them"
    }
}
