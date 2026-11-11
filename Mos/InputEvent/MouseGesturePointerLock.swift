//
//  MouseGesturePointerLock.swift
//  Mos
//
//  Keeps the pointer in place while a Gesture Navigation button is held.
//
//  The pointer is detached from the mouse with CGAssociateMouseAndMouseCursorPosition(false);
//  movement still arrives as event deltas, so gesture recognition keeps working. If the
//  system does not honour the detach for a background app, each motion event warps the
//  pointer back to where the hold started. The lock always re-attaches on release,
//  on cancellation, after a safety timeout and when Mos starts or quits.
//
//  The warp has a side effect on macOS 27 (documented by Mac Mouse Fix): it takes effect a
//  few events late, and the first event back on the anchor then reports the jump as mouse
//  movement. `MouseGestureWarpDeltaCompensator` removes that false delta for callers that
//  follow the hand continuously.
//

import Cocoa

/// The CoreGraphics side effects, replaceable in tests so they never touch the real pointer.
struct MouseGesturePointerDriver {
    var currentLocation: () -> CGPoint?
    var setAssociated: (Bool) -> Void
    var warp: (CGPoint) -> Void

    static let system = MouseGesturePointerDriver(
        currentLocation: { CGEvent(source: nil)?.location },
        setAssociated: { CGAssociateMouseAndMouseCursorPosition($0 ? 1 : 0) },
        warp: { CGWarpMouseCursorPosition($0) }
    )

    /// Used while XCTest runs without an explicit test driver.
    static let inert = MouseGesturePointerDriver(
        currentLocation: { nil },
        setAssociated: { _ in },
        warp: { _ in }
    )
}

/// Recovers the physical mouse movement from motion events seen while the pointer lock
/// falls back to warping. Pure, so it can be tested with plain values.
///
/// Pattern: the pointer drifts off the anchor for one or more events, then one event shows
/// it back on the anchor. On macOS 27 that event's delta is "hand movement + the jump back";
/// on older systems the warp adds nothing. Both readings are tried, and the one closer to
/// the previous event's movement wins, because a hand does not change speed by the whole
/// drift distance between two events.
struct MouseGestureWarpDeltaCompensator {
    /// After the warp the pointer sits on the anchor rounded down to whole points.
    static let anchorTolerance: CGFloat = 1

    private var driftedLocation: CGPoint?
    private var previousDelta = CGPoint.zero

    mutating func reset() {
        driftedLocation = nil
        previousDelta = .zero
    }

    /// - Parameters:
    ///   - delta: the event's reported delta.
    ///   - location: the event's location before the lock rewrites it.
    mutating func physicalDelta(_ delta: CGPoint, location: CGPoint, anchor: CGPoint) -> CGPoint {
        let isOnAnchor = abs(location.x - anchor.x) <= Self.anchorTolerance
            && abs(location.y - anchor.y) <= Self.anchorTolerance
        guard isOnAnchor else {
            driftedLocation = location
            previousDelta = delta
            return delta
        }
        guard let drifted = driftedLocation else {
            previousDelta = delta
            return delta
        }
        driftedLocation = nil

        let jump = CGPoint(x: anchor.x - drifted.x, y: anchor.y - drifted.y)
        let withoutJump = CGPoint(x: delta.x - jump.x, y: delta.y - jump.y)
        let result = Self.distance(withoutJump, previousDelta) < Self.distance(delta, previousDelta)
            ? withoutJump
            : delta
        previousDelta = result
        return result
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        return hypot(a.x - b.x, a.y - b.y)
    }
}

final class MouseGesturePointerLock {
    static let shared = MouseGesturePointerLock()

    /// A hold longer than this releases the pointer even if the button-up was lost.
    static let safetyTimeout: TimeInterval = 10
    /// Pointer drift (points) tolerated before warping back to the anchor.
    private static let warpTolerance: CGFloat = 0.5

    private var testDriver: MouseGesturePointerDriver?
    /// Tests shorten the safety timeout to see it fire for real.
    private var safetyTimeoutOverride: TimeInterval?
    private var driver: MouseGesturePointerDriver {
        if let testDriver { return testDriver }
        return AppRuntime.isRunningXCTest ? .inert : .system
    }

    private(set) var anchor: CGPoint?
    private var safetyWorkItem: DispatchWorkItem?
    private var warpCompensator = MouseGestureWarpDeltaCompensator()

    var isLocked: Bool { anchor != nil }

    /// Freezes the pointer at its current position. Safe to call while already locked: the
    /// anchor stays, and the safety timeout starts over, so a hold that began later is not
    /// released at the first hold's timeout.
    func lock() {
        if anchor == nil {
            guard let location = driver.currentLocation() else { return }
            anchor = location
            warpCompensator.reset()
            driver.setAssociated(false)
        }
        armSafetyTimeout()
    }

    private func armSafetyTimeout() {
        safetyWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            NSLog("MouseGesturePointerLock: safety timeout, releasing pointer")
            self?.unlock()
        }
        safetyWorkItem = workItem
        let timeout = safetyTimeoutOverride ?? Self.safetyTimeout
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: workItem)
    }

    /// Releases the pointer. Safe to call when not locked.
    func unlock() {
        safetyWorkItem?.cancel()
        safetyWorkItem = nil
        guard anchor != nil else { return }
        anchor = nil
        driver.setAssociated(true)
    }

    /// Re-attaches the pointer unconditionally (app launch / quit), in case a previous
    /// run ended while detached.
    func forceRelease() {
        safetyWorkItem?.cancel()
        safetyWorkItem = nil
        anchor = nil
        driver.setAssociated(true)
    }

    /// The physical mouse movement behind a motion event, with the false delta of the warp
    /// fallback removed. Call once per motion event, before `constrain` rewrites the
    /// location. Returns `delta` unchanged while the pointer is not locked.
    func physicalDelta(_ delta: CGPoint, at location: CGPoint) -> CGPoint {
        guard let anchor else { return delta }
        return warpCompensator.physicalDelta(delta, location: location, anchor: anchor)
    }

    /// Called for every motion event while locked: hides the movement from apps and
    /// pulls the pointer back if the detach did not take effect.
    func constrain(_ event: CGEvent) {
        guard let anchor else { return }
        let location = event.location
        event.location = anchor
        guard abs(location.x - anchor.x) > Self.warpTolerance
                || abs(location.y - anchor.y) > Self.warpTolerance else {
            return
        }
        driver.warp(anchor)
        driver.setAssociated(false)
    }

    #if DEBUG
    func setTestingDriver(_ driver: MouseGesturePointerDriver) {
        testDriver = driver
    }

    func clearTestingDriver() {
        forceRelease()
        testDriver = nil
        safetyTimeoutOverride = nil
    }

    /// nil restores the real timeout.
    func setTestingSafetyTimeout(_ timeout: TimeInterval?) {
        safetyTimeoutOverride = timeout
    }
    #endif
}
