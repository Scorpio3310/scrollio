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
//  their own, and an app's own gestures have their own "Let the mouse track the gesture"
//  (`ApplicationGestures`). A button that is down keeps what it has until it is up.
//

import Foundation

extension LogiUsageBootstrap {

    /// The set last handed to LogiCenter.
    private static var lastGestureTrackingCodes: Set<UInt16> = []
    /// What the settings make the mice track, as the last line of the log said it (a line
    /// only after a change of the settings, and only when this changes).
    private static var lastLoggedTracking = GestureTracking.none
    /// Buttons whose tracking stays as it was only because they were down when the
    /// bindings that count changed: decided again at their release (`buttonWasReleased`).
    private(set) static var trackingKeptWhileHeld: Set<UInt16> = []
    /// The "Let the mouse track the gesture" switches that were on at the last change of the
    /// settings ("" the Gestures pane's, else an app's path); nil before the first.
    private static var lastTrackingSwitchesOn: Set<String>?

    /// Pushes the current set once and again on every `.gesture` change. Binding and scroll
    /// hotkey changes arrive through `refreshAll`, a change of the app in front through
    /// `frontApplicationChanged`.
    static func installGestureObserver() {
        refreshGestureTracking(afterASettingsChange: true)
        Options.shared.observe([.gesture]) { _ in
            refreshGestureTracking(afterASettingsChange: true)
        }
    }

    /// Tells the mice which Logitech buttons they track themselves for the bindings that
    /// count while `front` is in front: the general ones with the app's own merged over them
    /// (`ApplicationButtons`), by the "Let the mouse track the gesture" that counts there:
    /// the app's own gestures' while they are in use, else the Gestures pane's
    /// (`MouseGestureChoice`, as a hold finds its settings). Without an app of its own in
    /// front this is exactly the set of Buttons. A button that is down keeps its tracking,
    /// either way, until it is up: a
    /// tracked hold whose swipe brings another app forward keeps its movement, and a ring
    /// held open keeps the pointer's. LogiCenter writes nothing for a set that did not
    /// change (switching between apps without buttons of their own costs nothing), and a
    /// change goes to the mouse off the main thread with the divert.
    ///
    /// `afterASettingsChange`: the settings changed (the `Options` path, launch), not the app
    /// in front; only then a line in the `app` log, and only when what the settings make
    /// the mice track is not what the last line said (counts over the list, never which
    /// app): a line per switch of apps kept a trail of the user's switches.
    static func refreshGestureTracking(
        front: ShortcutRingChoice.FrontApp? = frontApplication(), afterASettingsChange: Bool = false
    ) {
        let general = Options.shared.buttons.binding
        let gesture = Options.shared.gesture
        let applications = Options.shared.application.applications
        let entry = ApplicationButtons.entry(front: front, applications: applications)
        let deviceTracking = (entry?.gesturesThatRun(general: gesture) ?? gesture).deviceTracking
        // (The log's count, after a change of the settings, needs them for every app.)
        let needsHotkeys = deviceTracking || afterASettingsChange && tracksSomewhere(gesture: gesture, applications: applications)
        let hotkeys = needsHotkeys ? scrollHotkeyCodes() : []
        let wanted = gestureTrackingCodes(
            deviceTracking: deviceTracking,
            bindings: ApplicationButtons.merged(general: general, own: entry?.ownButtonBindings ?? []),
            scrollHotkeyCodes: hotkeys
        )
        let codes = trackingCodes(wanted: wanted, last: lastGestureTrackingCodes, held: heldButtonCodes())
        trackingKeptWhileHeld = codes.symmetricDifference(wanted)
        LogiCenter.shared.setGestureTrackingCodes(codes)
        // A switch turned on (off and on again) asks the mice once more for a button they
        // refused to track; a switch of apps never does.
        if afterASettingsChange {
            let switchesOn = trackingSwitchesOn(gesture: gesture, applications: applications)
            if let last = lastTrackingSwitchesOn, !switchesOn.isSubset(of: last) {
                LogiCenter.shared.retryRefusedGestureTracking()
            }
            lastTrackingSwitchesOn = switchesOn
        }
        lastGestureTrackingCodes = codes

        guard afterASettingsChange else { return }
        let tracking = gestureTracking(gesture: gesture, general: general, applications: applications, scrollHotkeyCodes: hotkeys)
        guard tracking != lastLoggedTracking else { return }
        lastLoggedTracking = tracking
        log(tracking.line)
    }

    /// The set to hand over: `wanted`, except for the buttons that are down, which keep
    /// what they had (`last`). Pure.
    static func trackingCodes(wanted: Set<UInt16>, last: Set<UInt16>, held: Set<UInt16>) -> Set<UInt16> {
        return wanted.subtracting(held).union(last.intersection(held))
    }

    /// What the settings make the mice track: how many Logitech buttons with the bindings of
    /// Buttons, and how many apps on the list change that set with bindings or gestures of
    /// their own while they are in front (never which).
    struct GestureTracking: Equatable {
        static let none = GestureTracking(buttons: 0, apps: 0)

        var buttons: Int
        var apps: Int

        /// The `app` log's line (counts only).
        var line: String {
            let what = buttons == 0
                ? "Gestures: the mouse tracks no Logitech button's hold itself"
                : "Gestures: the mouse tracks the hold of \(buttons) Logitech button(s) itself"
            return apps == 0 ? what : what + "; \(apps) app(s) change which by their own settings while in front"
        }
    }

    /// `GestureTracking` for the list: each entry that a press finds for its path (the last
    /// of two entries of one path, `ApplicationButtons.entry`) against `general`, with the
    /// tracking switch that counts while it is in front (its own gestures', else
    /// `gesture`'s).
    static func gestureTracking(
        gesture: MouseGestureSettings,
        general: [ButtonBinding],
        applications: EnhanceArray<Application>,
        scrollHotkeyCodes hotkeys: Set<UInt16>
    ) -> GestureTracking {
        let generalCodes = gestureTrackingCodes(deviceTracking: gesture.deviceTracking, bindings: general, scrollHotkeyCodes: hotkeys)
        var apps = 0
        for index in 0..<applications.count {
            guard let entry = applications.get(by: index), entry.hasOwnButtons || entry.ownGestures != nil,
                  applications.get(by: entry.path) === entry else { continue }
            let codes = gestureTrackingCodes(
                deviceTracking: entry.gesturesThatRun(general: gesture).deviceTracking,
                bindings: ApplicationButtons.merged(general: general, own: entry.ownButtonBindings),
                scrollHotkeyCodes: hotkeys
            )
            if codes != generalCodes { apps += 1 }
        }
        return GestureTracking(buttons: generalCodes.count, apps: apps)
    }

    /// The "Let the mouse track the gesture" switches that are on: "" for the Gestures
    /// pane's, an app's path for its own gestures'.
    static func trackingSwitchesOn(gesture: MouseGestureSettings, applications: EnhanceArray<Application>) -> Set<String> {
        var switches: Set<String> = gesture.deviceTracking ? [""] : []
        for index in 0..<applications.count {
            guard let entry = applications.get(by: index), entry.ownGestures?.deviceTracking == true else { continue }
            switches.insert(entry.path)
        }
        return switches
    }

    /// "Let the mouse track the gesture" is on in the Gestures pane or for an app's own
    /// gestures in use: only then are the scroll hotkeys looked up.
    private static func tracksSomewhere(gesture: MouseGestureSettings, applications: EnhanceArray<Application>) -> Bool {
        guard !gesture.deviceTracking else { return true }
        for index in 0..<applications.count where applications.get(by: index)?.ownGestures?.deviceTracking == true {
            return true
        }
        return false
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
