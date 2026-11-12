//
//  LogiUsageBootstrap+Gesture.swift
//  Mos
//
//  Options -> LogiCenter wiring for "let the mouse track the gesture" (Options group
//  .gesture, MouseGestureSettings.deviceTracking). Tells the Logi layer which Logitech
//  buttons should report the movement of their hold themselves (raw XY) instead of moving
//  the pointer. LogiCenter remembers the set for mice that connect later, arms only
//  controls that can do it, and falls back to pointer movement everywhere else.
//

import Foundation

extension LogiUsageBootstrap {

    /// Pushes the current set once and again on every `.gesture` change. Binding and scroll
    /// hotkey changes arrive through `refreshAll`.
    static func installGestureObserver() {
        refreshGestureTracking()
        Options.shared.observe([.gesture]) { _ in
            refreshGestureTracking()
        }
    }

    static func refreshGestureTracking() {
        LogiCenter.shared.setGestureTrackingCodes(
            gestureTrackingCodes(
                deviceTracking: Options.shared.gesture.deviceTracking,
                bindings: Options.shared.buttons.binding,
                scrollHotkeyCodes: scrollHotkeyCodes()
            )
        )
    }

    /// The Logitech buttons the mouse should track itself.
    ///
    /// A tracked button freezes the pointer for as long as it is held, whatever it is used
    /// for. So a button qualifies only when Gesture Navigation is all it does: every
    /// enabled binding on it is Gesture Navigation (with or without modifiers) and it is
    /// not a scroll hotkey. Empty while the setting is off.
    static func gestureTrackingCodes(
        deviceTracking: Bool,
        bindings: [ButtonBinding],
        scrollHotkeyCodes: Set<UInt16>
    ) -> Set<UInt16> {
        guard deviceTracking else { return [] }
        var gestureCodes: Set<UInt16> = []
        var otherCodes: Set<UInt16> = []
        for binding in bindings where binding.isEnabled && binding.triggerEvent.type == .mouse {
            let code = binding.triggerEvent.code
            guard LogiCenter.shared.isLogiCode(code) else { continue }
            if binding.systemShortcutName == SystemShortcut.mouseGestureNavigation.identifier {
                gestureCodes.insert(code)
            } else {
                otherCodes.insert(code)
            }
        }
        return gestureCodes.subtracting(otherCodes).subtracting(scrollHotkeyCodes)
    }

    /// Logitech buttons used as a scroll hotkey, globally or for one app.
    private static func scrollHotkeyCodes() -> Set<UInt16> {
        var codes: Set<UInt16> = []
        for role in ScrollRole.allCases {
            codes.formUnion(globalScrollCodes(role: role))
        }
        let apps = Options.shared.application.applications
        for i in 0..<apps.count {
            guard let app = apps.get(by: i) else { continue }
            for role in ScrollRole.allCases {
                codes.formUnion(appScrollCodes(app: app, role: role))
            }
        }
        return codes
    }
}
