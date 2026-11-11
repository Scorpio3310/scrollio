//
//  ScrollHandover.swift
//  Mos
//
//  Who moves the page when the trackpad and the mouse wheel overlap.
//

import Foundation

/// The trackpad's glide and the wheel do not move the page at the same time.
///
/// Trackpad to wheel: a wheel event with a delta that arrives while the trackpad's glide (its
/// momentum events) runs takes over. The rest of that glide's "changed" events (momentum
/// phase 2) is dropped: two sources would move the page at once, against each other when the
/// directions differ. Its "ended" event goes on, so the app closes the sequence. A new touch
/// or a new glide starts fresh and is never dropped.
///
/// What macOS sends (a trace on the owner's Mac, 2026-11-11): when the wheel turns during the
/// glide, a momentum "ended" event comes at once, carrying the wheel's first delta and not
/// continuous, followed by that wheel event itself; then the glide's "changed" events go on,
/// interleaved with the wheel's, until a real "ended" with no delta. So an "ended" that carries
/// a delta does not end the glide here.
///
/// Wheel to trackpad: `fingerTakesOver(scrollPhase:)`.
///
/// Pure. In the app it lives on `ScrollCore` and is used on the main thread only (the scroll
/// tap's callback); a few comparisons per event, nothing allocated.
struct ScrollHandover: Equatable {

    /// `scrollPhase` of a finger that begins to scroll (kCGScrollPhaseBegan).
    static let scrollBegan = 1.0
    /// `momentumPhase` values (kCGMomentumScrollPhaseBegin, Continue, End).
    static let momentumBegan = 1.0
    static let momentumChanged = 2.0
    static let momentumEnded = 3.0

    enum State: Equatable {
        /// No glide of the trackpad is known to run.
        case idle
        /// The trackpad's glide runs.
        case glide
        /// A wheel event came during the glide; its "changed" events are dropped.
        case wheelTookOver(dropped: Int)
    }

    enum Decision: Equatable {
        case letThrough
        /// Drop the event: the wheel took over this glide.
        case swallow
        /// Let it through; the wheel's takeover of a glide ended with this event, after
        /// `dropped` events (for the one log line per hand-over).
        case letThroughEndingTakeover(dropped: Int)
    }

    private(set) var state: State = .idle

    private var droppedSoFar: Int? {
        if case let .wheelTookOver(dropped) = state { return dropped }
        return nil
    }

    /// One event taken for the trackpad's. `hasDelta`: it carries a scroll delta.
    mutating func trackpadEvent(scrollPhase: Double, momentumPhase: Double, hasDelta: Bool) -> Decision {
        let takeover = droppedSoFar
        if scrollPhase != 0.0 {
            // A touch (may begin, began, changed, ended, cancelled): any glide is over.
            state = .idle
        } else if momentumPhase == Self.momentumBegan {
            state = .glide
        } else if momentumPhase == Self.momentumChanged {
            if let dropped = takeover {
                state = .wheelTookOver(dropped: dropped + 1)
                return .swallow
            }
            state = .glide
            return .letThrough
        } else if momentumPhase == Self.momentumEnded && !hasDelta {
            state = .idle
        } else {
            // The "ended" that comes with a wheel event, or a trackpad event without a phase.
            return .letThrough
        }
        if let dropped = takeover {
            return .letThroughEndingTakeover(dropped: dropped)
        }
        return .letThrough
    }

    /// A wheel event with a delta: during the trackpad's glide it takes over.
    mutating func wheelEvent() {
        if state == .glide {
            state = .wheelTookOver(dropped: 0)
        }
    }

    /// Wheel to trackpad: a finger that begins to scroll on the trackpad stops Scrollio's own
    /// glide from the wheel at once, so only the finger moves the page.
    static func fingerTakesOver(scrollPhase: Double) -> Bool {
        return scrollPhase == scrollBegan
    }
}
