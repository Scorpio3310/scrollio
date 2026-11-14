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
//  The set follows the app in front, as the divert does (`refreshButtonUsage`): an app's
//  own bindings can give the button that runs Gesture Navigation in Buttons the Shortcut
//  Ring (which needs the pointer's movement), or run Gesture Navigation on a button of
//  their own. A button that is down keeps what it has until it is up.
//

import Foundation

extension LogiUsageBootstrap {

    /// The set last handed to LogiCenter.
    private static var lastGestureTrackingCodes: Set<UInt16> = []
    /// Buttons whose tracking stays as it was only because they were down when the
    /// bindings that count changed: decided again at their release (`buttonWasReleased`).
    private(set) static var trackingKeptWhileHeld: Set<UInt16> = []

    /// Pushes the current set once and again on every `.gesture` change. Binding and scroll
    /// hotkey changes arrive through `refreshAll`, a change of the app in front through
    /// `frontApplicationChanged`.
    static func installGestureObserver() {
        refreshGestureTracking()
        Options.shared.observe([.gesture]) { _ in
            refreshGestureTracking()
        }
    }

    /// Tells the mice which Logitech buttons they track themselves for the bindings that
    /// count while `front` is in front: the general ones with the app's own merged over them
    /// (`ApplicationButtons`). Without an app of its own in front this is exactly the set of
    /// Buttons. A button that is down keeps its tracking, either way, until it is up: a
    /// tracked hold whose swipe brings another app forward keeps its movement, and a ring
    /// held open keeps the pointer's. LogiCenter writes nothing for a set that did not
    /// change (switching between apps without buttons of their own costs nothing), and a
    /// change goes to the mouse off the main thread with the divert. One line in the `app`
    /// log per change of the set, never which app.
    static func refreshGestureTracking(front: ShortcutRingChoice.FrontApp? = frontApplication()) {
        let general = Options.shared.buttons.binding
        let deviceTracking = Options.shared.gesture.deviceTracking
        let entry = ApplicationButtons.entry(front: front, applications: Options.shared.application.applications)
        let own = entry?.ownButtonBindings ?? []
        let hotkeys = deviceTracking ? scrollHotkeyCodes() : []
        let wanted = gestureTrackingCodes(
            deviceTracking: deviceTracking,
            bindings: ApplicationButtons.merged(general: general, own: own),
            scrollHotkeyCodes: hotkeys
        )
        let codes = trackingCodes(wanted: wanted, last: lastGestureTrackingCodes, held: heldButtonCodes())
        trackingKeptWhileHeld = codes.symmetricDifference(wanted)
        LogiCenter.shared.setGestureTrackingCodes(codes)
        guard codes != lastGestureTrackingCodes else { return }
        lastGestureTrackingCodes = codes
        let byTheAppInFront = !own.isEmpty
            && wanted != gestureTrackingCodes(deviceTracking: deviceTracking, bindings: general, scrollHotkeyCodes: hotkeys)
        log(trackingLine(count: codes.count, byTheAppInFront: byTheAppInFront))
    }

    /// The set to hand over: `wanted`, except for the buttons that are down, which keep
    /// what they had (`last`). Pure.
    static func trackingCodes(wanted: Set<UInt16>, last: Set<UInt16>, held: Set<UInt16>) -> Set<UInt16> {
        return wanted.subtracting(held).union(last.intersection(held))
    }

    /// The line of the `app` log for a new set: how many buttons, and whether the bindings
    /// of the app in front made it differ from that of Buttons (never which app).
    static func trackingLine(count: Int, byTheAppInFront: Bool) -> String {
        let what = count == 0
            ? "Gestures: the mouse tracks no Logitech button's hold itself"
            : "Gestures: the mouse tracks the hold of \(count) Logitech button(s) itself"
        return what + (byTheAppInFront ? ", by the own bindings of the app in front" : "")
    }

    /// The Logitech buttons the mouse should track itself.
    ///
    /// A tracked button freezes the pointer for as long as it is held, whatever it is used
    /// for. So a button qualifies only when Gesture Navigation is all it does: every
    /// enabled binding on it is Gesture Navigation (with or without modifiers) and it is
    /// not a scroll hotkey. Empty while the setting is off. `bindings`: those that count
    /// while an app is in front (an app's own "Default" on a button is another job: the
    /// button is the mouse's there).
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

    /// Logitech buttons used as a scroll hotkey, globally or for any app: never tracked,
    /// whatever app is in front (a hold key of an app's own Scrolling goes by the app the
    /// scroll engine finds for the wheel, which need not be the app in front).
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
