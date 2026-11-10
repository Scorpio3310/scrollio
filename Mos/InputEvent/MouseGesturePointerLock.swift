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

final class MouseGesturePointerLock {
    static let shared = MouseGesturePointerLock()

    /// A hold longer than this releases the pointer even if the button-up was lost.
    static let safetyTimeout: TimeInterval = 10
    /// Pointer drift (points) tolerated before warping back to the anchor.
    private static let warpTolerance: CGFloat = 0.5

    private var testDriver: MouseGesturePointerDriver?
    private var driver: MouseGesturePointerDriver {
        if let testDriver { return testDriver }
        return AppRuntime.isRunningXCTest ? .inert : .system
    }

    private(set) var anchor: CGPoint?
    private var safetyWorkItem: DispatchWorkItem?

    var isLocked: Bool { anchor != nil }

    /// Freezes the pointer at its current position. Safe to call while already locked.
    func lock() {
        guard anchor == nil else { return }
        guard let location = driver.currentLocation() else { return }
        anchor = location
        driver.setAssociated(false)

        let workItem = DispatchWorkItem { [weak self] in
            NSLog("MouseGesturePointerLock: safety timeout, releasing pointer")
            self?.unlock()
        }
        safetyWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.safetyTimeout, execute: workItem)
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
    }
    #endif
}
