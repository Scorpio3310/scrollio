//
//  CommonModesTimer.swift
//  Mos
//
//  Safety timers that must also fire while a menu is open: the keepers and restarts of the
//  event taps, the recovery of AppRunController, the keeper and rate checks of the display
//  link. `Timer.scheduledTimer` adds a timer in the default run-loop mode only; while the
//  status-bar menu is open, a pull-down tracks or a modal panel runs, the main run loop runs
//  in another mode and such a timer waits until they close. An event tap that macOS turned
//  off meanwhile stayed off for that long. The common modes include those modes.
//

import Foundation

enum CommonModesTimer {

    /// The run-loop mode every timer made here is added in.
    static let mode: RunLoop.Mode = .common

    /// A timer on the main run loop in the common modes. Call it on the main thread, as
    /// `Timer.scheduledTimer` was called for the timers it replaces.
    static func scheduled(
        withTimeInterval interval: TimeInterval,
        repeats: Bool,
        block: @escaping (Timer) -> Void
    ) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: repeats, block: block)
        RunLoop.main.add(timer, forMode: mode)
        return timer
    }
}
