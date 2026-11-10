//
//  LogiUsageBootstrap+Wheel.swift
//  Mos
//
//  Options -> LogiCenter wiring for the Logitech scroll-wheel settings (Options group
//  .logiWheel). LogiCenter remembers the latest settings and replays them whenever a
//  supporting device (re)connects, so this only has to push changes. Nothing is written
//  to a device unless the user turned on `managedByMos`.
//

import Foundation

extension LogiUsageBootstrap {

    /// Slider drags fire many Options changes; write only the settled value.
    static let wheelApplyDelay: TimeInterval = 0.25

    private static var pendingWheelApply: DispatchWorkItem?

    /// Pushes the stored settings once (devices that connect later pick them up) and
    /// re-pushes on every `.logiWheel` change.
    static func installWheelObserver() {
        LogiCenter.shared.applyWheelSettings(Options.shared.logiWheel)
        Options.shared.observe([.logiWheel]) { _ in
            scheduleWheelApply()
        }
    }

    private static func scheduleWheelApply() {
        pendingWheelApply?.cancel()
        let item = DispatchWorkItem {
            pendingWheelApply = nil
            LogiCenter.shared.applyWheelSettings(Options.shared.logiWheel)
        }
        pendingWheelApply = item
        DispatchQueue.main.asyncAfter(deadline: .now() + wheelApplyDelay, execute: item)
    }
}
