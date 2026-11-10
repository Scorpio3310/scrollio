//
//  InteractiveGestureEnvironment.swift
//  Mos
//
//  What the interactive gesture needs from the system: the screen under the pointer, a
//  clock and a way to run work on a later main-queue turn. Replaceable in tests.
//

import Cocoa

struct InteractiveGestureScreen: Equatable {
    /// Width in points.
    var width: CGFloat
    /// Spaces on this display; nil when unknown.
    var spaceCount: Int?
    /// Duration of one display refresh.
    var frameDuration: TimeInterval
}

struct InteractiveGestureEnvironment {
    /// The screen under the pointer.
    var screen: () -> InteractiveGestureScreen
    /// Monotonic time in seconds.
    var now: () -> TimeInterval
    /// Runs the block on the main queue after the delay; 0 means the next main-queue turn.
    /// The block must never run inside the caller's stack: callers are event tap callbacks.
    var schedule: (TimeInterval, @escaping () -> Void) -> Void

    static let fallbackScreen = InteractiveGestureScreen(width: 1440, spaceCount: nil, frameDuration: 1.0 / 60.0)

    static let system = InteractiveGestureEnvironment(
        screen: { systemScreen() },
        now: { ProcessInfo.processInfo.systemUptime },
        schedule: { delay, work in
            if delay <= 0 {
                DispatchQueue.main.async(execute: work)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            }
        }
    )

    private static func systemScreen() -> InteractiveGestureScreen {
        let location = NSEvent.mouseLocation
        let screens = NSScreen.screens
        guard let screen = screens.first(where: { NSMouseInRect(location, $0.frame, false) })
                ?? NSScreen.main ?? screens.first else {
            return fallbackScreen
        }

        var frameDuration = fallbackScreen.frameDuration
        if #available(macOS 12.0, *), screen.maximumFramesPerSecond > 0 {
            frameDuration = 1.0 / TimeInterval(screen.maximumFramesPerSecond)
        }
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        return InteractiveGestureScreen(
            width: screen.frame.width,
            spaceCount: displayID.flatMap { DockSwipeGeometry.spaceCount(forDisplay: $0) },
            frameDuration: frameDuration
        )
    }
}
