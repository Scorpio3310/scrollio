//
//  LogiUsageBootstrap+Basics.swift
//  Mos
//
//  Options -> LogiCenter wiring for the basic Logitech mouse settings (Options group
//  .logiMouse: pointer speed, haptics, press force). The switch that allows writing is
//  the wheel's "Let Scrollio manage this mouse" (`logiWheel.managedByScrollio`), so `.logiWheel`
//  changes are pushed too. LogiCenter remembers the latest values and replays them whenever
//  a mouse (re)connects, so this only has to push changes.
//

import Foundation

extension LogiUsageBootstrap {

    /// Slider drags fire many Options changes; write only the settled value.
    static let mouseApplyDelay: TimeInterval = 0.25

    private static var pendingMouseApply: DispatchWorkItem?

    /// Pushes the stored settings once (mice that connect later pick them up) and again on
    /// every `.logiMouse` or `.logiWheel` change.
    static func installMouseObserver() {
        pushMouseSettings()
        Options.shared.observe([.logiMouse, .logiWheel]) { _ in
            scheduleMouseApply()
        }
    }

    static func pushMouseSettings() {
        LogiCenter.shared.applyMouseSettings(
            Options.shared.logiMouse,
            managed: Options.shared.logiWheel.managedByScrollio
        )
    }

    private static func scheduleMouseApply() {
        pendingMouseApply?.cancel()
        let item = DispatchWorkItem {
            pendingMouseApply = nil
            pushMouseSettings()
        }
        pendingMouseApply = item
        DispatchQueue.main.asyncAfter(deadline: .now() + mouseApplyDelay, execute: item)
    }
}
