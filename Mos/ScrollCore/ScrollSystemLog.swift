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
        /// The Duration factor the wheel events really used (per 60 Hz frame): the global one,
        /// or an app's own. The last event's wins.
        var transition = 0.0
        var trackpadStyle = false

        var isEmpty: Bool { return inputs == 0 }

        /// The Duration (slider value) behind `transition`.
        var duration: Double { return ScrollSystemLog.duration(forTransition: transition) }
    }

    /// Inverse of `OPTIONS_SCROLL_DEFAULT.generateDurationTransition` (1 − √(d / 5.2)); exact
    /// to about 0.002 because the factor is rounded to three decimals.
    static func duration(forTransition transition: Double) -> Double {
        guard transition.isFinite else { return 0 }
        let root = 1 - min(1, max(0, transition))
        return 5.2 * root * root
    }

    static func message(for session: Session, endedWith phase: String) -> String {
        let tau = ScrollMotion.timeConstant(forTransition: session.transition)
        return String(
            format: "scroll: %d wheel events %.0f px in -> %d frames %.0f px out (largest %.1f), wheel %.0f ms, glide after the last event %.0f ms, Duration %.2f (tau %.0f ms), trackpad-style %@, ended %@",
            session.inputs, session.inputDistance, session.frames, session.postedDistance, session.largestFrame,
            (session.lastInputAt - session.startedAt) * 1000,
            max(0, session.lastFrameAt - session.lastInputAt) * 1000,
            session.duration, tau * 1000,
            session.trackpadStyle ? "on" : "off",
            phase
        )
    }

    static func note(_ session: Session, endedWith phase: String) {
        guard !session.isEmpty else { return }
        let message = message(for: session, endedWith: phase)
        logger.notice("\(message, privacy: .public)")
    }

    // MARK: - Wheel events let through unsmoothed

    /// Why ScrollCore let a wheel event through unsmoothed.
    enum PassthroughReason: Int, CaseIterable {
        /// The event looks like a trackpad's (or a Magic Mouse's): never smoothed.
        case trackpad
        /// A remote desktop client sent it already smoothed.
        case remoteSmoothed
        /// Smoothing is off for this event: switched off, paused by a key, an app rule, the
        /// allowlist or Launchpad.
        case smoothingOff
        /// Smoothing is on, but not for this axis.
        case axisNotSmoothed
        /// Smoothing wanted, but there is no display link to post with.
        case noDisplayLink

        var text: String {
            switch self {
            case .trackpad: return "taken for trackpad events"
            case .remoteSmoothed: return "remote desktop, already smoothed"
            case .smoothingOff: return "smoothing is off for this event"
            case .axisNotSmoothed: return "smoothing is on, but not for this axis"
            case .noDisplayLink: return "no display link"
            }
        }
    }

    /// At most one line per reason in this many seconds.
    static let passthroughInterval: CFTimeInterval = 3

    private static var lastPassthroughNote = [CFTimeInterval](repeating: -.infinity, count: PassthroughReason.allCases.count)
    private static var passthroughCounts = [Int](repeating: 0, count: PassthroughReason.allCases.count)

#if DEBUG
    /// Tests: sees every passthrough, logged or not.
    static var passthroughObserverForTests: ((PassthroughReason) -> Void)?
#endif

    /// Main thread (the scroll tap callback), once per event let through: allocates nothing
    /// unless a line is written. `detail` is only evaluated for a line that is written.
    /// - Returns: the line written, or nil while the reason is quiet.
    @discardableResult
    static func notePassthrough(
        _ reason: PassthroughReason,
        now: CFTimeInterval = CFAbsoluteTimeGetCurrent(),
        detail: () -> String = { "" }
    ) -> String? {
#if DEBUG
        passthroughObserverForTests?(reason)
#endif
        let slot = reason.rawValue
        passthroughCounts[slot] += 1
        guard now - lastPassthroughNote[slot] >= passthroughInterval else { return nil }
        lastPassthroughNote[slot] = now
        let count = passthroughCounts[slot]
        passthroughCounts[slot] = 0
        let extra = detail()
        let line = "wheel events let through unsmoothed (\(count)): \(reason.text)\(extra.isEmpty ? "" : " (\(extra))")"
        logger.notice("\(line, privacy: .public)")
        return line
    }

#if DEBUG
    static func resetPassthroughForTests() {
        lastPassthroughNote = [CFTimeInterval](repeating: -.infinity, count: PassthroughReason.allCases.count)
        passthroughCounts = [Int](repeating: 0, count: PassthroughReason.allCases.count)
    }
#endif
}
