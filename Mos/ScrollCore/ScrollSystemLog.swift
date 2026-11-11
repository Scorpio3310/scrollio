//
//  ScrollSystemLog.swift
//  Mos
//
//  What smooth scrolling really did, in the system log:
//
//      log show --last 10m --predicate 'subsystem == "com.nikklemenc.Scrollio" AND category == "scroll"'
//
//  One line per finished scroll (never per event), and one line now and then when wheel
//  events are let through unsmoothed, with the reason. Tests pass on a simulated wheel; this
//  is how to see what happened on the real one.
//

import Foundation
import os

enum ScrollSystemLog {

    private static let logger = os.Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Scrollio",
        category: "scroll"
    )

    /// What one scroll (from the first wheel event to the stop) added up to.
    struct Session {
        var inputs = 0
        var inputDistance = 0.0
        var frames = 0
        var postedDistance = 0.0
        var largestFrame = 0.0
        var startedAt: CFTimeInterval = 0
        var lastInputAt: CFTimeInterval = 0
        var lastFrameAt: CFTimeInterval = 0
        var duration = 0.0
        var trackpadStyle = false
        var precise = false
        var freeSpinInputs = 0

        var isEmpty: Bool { return inputs == 0 }
    }

    static func note(_ session: Session, endedWith phase: String, now: CFTimeInterval) {
        guard !session.isEmpty else { return }
        let tau = ScrollMotion.timeConstant(forTransition: OPTIONS_SCROLL_DEFAULT.generateDurationTransition(with: session.duration))
        let message = String(
            format: "scroll: %d wheel events %.0f px in -> %d frames %.0f px out (largest %.1f), wheel %.0f ms, glide after the last event %.0f ms, Duration %.2f (tau %.0f ms), trackpad-style %@, %@%@, ended %@",
            session.inputs, session.inputDistance, session.frames, session.postedDistance, session.largestFrame,
            (session.lastInputAt - session.startedAt) * 1000,
            max(0, session.lastFrameAt - session.lastInputAt) * 1000,
            session.duration, tau * 1000,
            session.trackpadStyle ? "on" : "off",
            session.precise ? "precise" : "classic",
            session.freeSpinInputs > 0 ? ", free-spin \(session.freeSpinInputs)" : "",
            phase
        )
        logger.notice("\(message, privacy: .public)")
    }

    // MARK: - Wheel events let through unsmoothed

    private static var lastPassthroughNote: [String: CFTimeInterval] = [:]
    private static var passthroughCounts: [String: Int] = [:]

    /// Main thread (the scroll tap callback). At most one line per reason every few seconds.
    static func notePassthrough(_ reason: String, now: CFTimeInterval = CFAbsoluteTimeGetCurrent()) {
        passthroughCounts[reason, default: 0] += 1
        if let last = lastPassthroughNote[reason], now - last < 3 { return }
        lastPassthroughNote[reason] = now
        let count = passthroughCounts[reason] ?? 0
        passthroughCounts[reason] = 0
        logger.notice("wheel events let through unsmoothed (\(count, privacy: .public)): \(reason, privacy: .public)")
    }

    static func note(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }
}
