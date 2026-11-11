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

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Scrollio",
        category: "logi"
    )

    static func note(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }
}
