//
//  LogiUsageBootstrap+ReadAgain.swift
//  Scrollio
//
//  One more re-read of the Logitech buttons' state a few seconds after a re-read whose
//  closing pass wrote a divert again: one the mouse had not taken (no echo) or one it had
//  dropped (`LogiCenter.divertWrittenAgain`). A re-read otherwise starts only when Settings
//  opens, when Buttons comes forward (at most every 10 s) and when a mouse connects, so a
//  write the mouse refused again stayed refused until Settings opened again: a dead button
//  that "works again after I open Settings" (Mos #1048). The follow-up's own re-read never
//  asks for another, so a mouse that refuses every time costs one extra re-read per re-read.
//

import Foundation

extension LogiUsageBootstrap {

    private static var readAgainObservers: [NSObjectProtocol] = []

    /// Follows the re-reads from launch on (AppDelegate). Once.
    static func installReadAgainObserver() {
        guard readAgainObservers.isEmpty else { return }
        let center = NotificationCenter.default
        let readAgain = ButtonsReadAgain.shared
        readAgainObservers = [
            center.addObserver(forName: LogiCenter.divertWrittenAgain, object: nil, queue: .main) { _ in
                readAgain.divertWrittenAgain()
            },
            center.addObserver(forName: LogiCenter.reportingDidComplete, object: nil, queue: .main) { _ in
                readAgain.reReadCompleted()
            },
            center.addObserver(forName: LogiCenter.activityChanged, object: nil, queue: .main) { _ in
                readAgain.activityChanged()
            },
        ]
    }

    #if DEBUG
    /// Tests: takes away what `installReadAgainObserver` put in.
    static func removeReadAgainObserverForTests() {
        readAgainObservers.forEach { NotificationCenter.default.removeObserver($0) }
        readAgainObservers = []
    }
    #endif

    /// When to ask for the follow-up, and that it is asked for once. Main thread only.
    final class ButtonsReadAgain {
        static let shared = ButtonsReadAgain()

        /// After the re-read ends, at least: time for the echo of the write (2 s) and for a
        /// mouse that was busy or waking up.
        static let delay: TimeInterval = 3

        enum Phase: Equatable {
            /// Nothing asked for.
            case idle
            /// The closing pass of a re-read wrote a divert again: the follow-up is asked
            /// for when that re-read ends.
            case wanted
            /// Waiting for its time.
            case scheduled
            /// Asked for; its re-reads run until LogiCenter is no longer busy. What they
            /// write again asks for nothing.
            case running
        }
        private(set) var phase = Phase.idle

        // Seams: tests give their own.
        var request: () -> Void = { LogiCenter.shared.refreshReportingStates() }
        var isBusy: () -> Bool = { LogiCenter.shared.isBusy }
        var lastRequest: () -> Date? = { LogiCenter.shared.lastReportingRefreshRequest }
        var now: () -> Date = { Date() }
        var schedule: (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }

        init() {}

        /// `LogiCenter.divertWrittenAgain`: comes from the pass that ends a re-read, before
        /// that re-read's `reportingDidComplete`.
        func divertWrittenAgain() {
            if phase == .idle {
                phase = .wanted
            }
        }

        /// `LogiCenter.reportingDidComplete`. With two mice the second re-read's end finds
        /// the follow-up scheduled already.
        func reReadCompleted() {
            guard phase == .wanted else { return }
            phase = .scheduled
            schedule(delayFromNow()) { [weak self] in self?.fire() }
        }

        /// `LogiCenter.activityChanged`: once LogiCenter is no longer busy, the follow-up's
        /// re-reads are over.
        func activityChanged() {
            if phase == .running, !isBusy() {
                phase = .idle
            }
        }

        /// How long from now: `delay`, or longer when LogiCenter would still refuse a
        /// re-read (it starts one at most every 10 s, counted from the last request, which
        /// for a re-read Settings started was before this one ended).
        func delayFromNow() -> TimeInterval {
            guard let last = lastRequest() else { return Self.delay }
            let refusedFor = LogiCenter.reportingRefreshMinimumInterval + 0.5 - now().timeIntervalSince(last)
            return max(Self.delay, refusedFor)
        }

        private func fire() {
            guard phase == .scheduled else { return }
            phase = .running
            request()
            // Nothing started (a button is being recorded, no mouse, refused all the same):
            // there is no end to wait for.
            if !isBusy() {
                phase = .idle
            }
        }
    }
}
