//
//  MouseGesturePresentation.swift
//  Mos
//  Pure helpers for the Gestures tab: what the connected mice can do for Gesture
//  Navigation, which Logitech options are shown and enabled and what the stored button
//  bindings mean for the tab. Kept free of views so the rules can be unit tested.
//  Also who keeps the pointer still during a hold (`MouseGesturePointerHolder`): what
//  "Freeze pointer during a gesture" shows while the mouse tracks the gesture itself.
//

import Foundation

/// What at least one connected mouse can do for Gesture Navigation.
struct MouseGestureDeviceSupport: Equatable {
    /// A button can report the movement of its hold itself (and keep the pointer still).
    var deviceTracking: Bool
    /// The mouse has a haptic motor.
    var haptics: Bool
    /// A connected mouse with a haptic motor reports its haptics switched off.
    var hapticsOffOnMouse: Bool = false

    static let none = MouseGestureDeviceSupport(deviceTracking: false, haptics: false)
}

/// Where the Gestures tab reads what the connected mice can do. `live` uses LogiCenter;
/// tests and screenshots pass fixtures instead, so no HID device is touched.
struct MouseGestureDeviceSource {
    var support: () -> MouseGestureDeviceSupport
    /// Asks the mice again; the answer arrives as `LogiCenter.gestureStateChanged`.
    var refresh: () -> Void

    static let live = MouseGestureDeviceSource(
        support: {
            MouseGestureDeviceSupport(
                deviceTracking: LogiCenter.shared.supportsGestureDeviceTracking(),
                haptics: LogiCenter.shared.supportsGestureHaptics(),
                hapticsOffOnMouse: LogiCenter.shared.mouseDeviceStates().contains { $0.haptics?.isOn.onMouse == false }
            )
        },
        refresh: { LogiCenter.shared.refreshGestureStates() }
    )
}

/// Which Logitech gesture options can be edited, and the hint under each. An option no
/// connected mouse supports is disabled and says so; its stored value is kept for when
/// one connects.
struct MouseGestureControlRules: Equatable {
    let deviceTrackingEnabled: Bool
    let deviceTrackingHintKey: String
    let hapticsEnabled: Bool
    let hapticsHintKey: String
    /// "Haptic feedback is off under Mouse.": the mouse has its haptics off and the user
    /// switched them off under Mouse. A gesture cue then never switches them on again, so
    /// the pulse is skipped (Scrollio/Logi/Gesture); the line says where to change that.
    let showsHapticsOffNote: Bool

    /// - Parameter hapticsOnUnderMouse: "Haptic feedback" of the Mouse pane as the user set
    ///   it (`Options.shared.logiMouse.hapticsOn`); nil while it was never touched.
    init(support: MouseGestureDeviceSupport, hapticsOnUnderMouse: Bool? = nil) {
        deviceTrackingEnabled = support.deviceTracking
        deviceTrackingHintKey = support.deviceTracking
            ? "mouse-gesture-device-tracking-hint"
            : "mouse-gesture-device-tracking-unavailable"
        hapticsEnabled = support.haptics
        hapticsHintKey = support.haptics
            ? "mouse-gesture-haptics-hint"
            : "mouse-gesture-haptics-unavailable"
        showsHapticsOffNote = support.haptics && support.hapticsOffOnMouse && hapticsOnUnderMouse == false
    }

    /// The tab shows the Logitech options only when a connected mouse supports at least one
    /// of them; otherwise a line says what they need.
    var showsOptions: Bool {
        return deviceTrackingEnabled || hapticsEnabled
    }
}

/// What the stored button bindings mean for the Gestures tab.
struct MouseGestureBindingSummary: Equatable {
    /// An enabled mouse button of the Buttons pane is bound to Gesture Navigation, so the
    /// settings have an effect in every app.
    var hasGestureButton: Bool
    /// A button that runs the gestures is a Logitech control, in the Buttons pane or with
    /// an app in front: Logi actions make sense as gesture actions.
    var hasLogitechGestureButton: Bool
    /// The names of the Buttons pane's buttons, as that pane titles them ("Back button").
    var buttonTitles: [String]
    /// With none of those: the apps whose own buttons run the gestures while they are in
    /// front (nil: none does).
    var onlyInApps: ApplicationTriggers?
    /// The trigger the preview's mouse holds: the first of the row's (`TriggerPictureSource`).
    var picture: TriggerPictureSource

    init(
        hasGestureButton: Bool, hasLogitechGestureButton: Bool, buttonTitles: [String] = [],
        onlyInApps: ApplicationTriggers? = nil, picture: TriggerPictureSource = .none
    ) {
        self.hasGestureButton = hasGestureButton
        self.hasLogitechGestureButton = hasLogitechGestureButton
        self.buttonTitles = buttonTitles
        self.onlyInApps = hasGestureButton ? nil : onlyInApps
        self.picture = picture
    }

    /// - Parameters:
    ///   - bindings: the Buttons pane's bindings (`Options.shared.buttons.binding`).
    ///   - applications: the apps on the list, whose own bindings count while they are in
    ///     front (`ApplicationTriggerRule`).
    ///   - titles: what the Buttons pane calls the triggers of `bindings`, in order.
    init(
        bindings: [ButtonBinding],
        applications: [Application] = [],
        isLogitechCode: (UInt16) -> Bool,
        titles: ([RecordedEvent]) -> [String] = { ButtonTriggerNaming.titles(for: $0) }
    ) {
        let rule = ApplicationTriggerRule.gestureNavigation
        let gestureBindings = rule.bindings(general: bindings)
        hasGestureButton = !gestureBindings.isEmpty
        let inApps = applications.map { rule.bindings(general: bindings, own: $0.ownButtonBindings) }
        hasLogitechGestureButton = (gestureBindings + inApps.joined()).contains { isLogitechCode($0.triggerEvent.code) }
        var names: [String] = []
        for (binding, name) in zip(bindings, titles(bindings.map(\.triggerEvent))) where rule.takes(binding) {
            if !names.contains(name) {
                names.append(name)
            }
        }
        buttonTitles = names
        let onlyInApps = ApplicationTriggers(rule.onlyInApps(general: bindings, applications: applications), titles: titles)
        self.onlyInApps = onlyInApps
        picture = TriggerPictureSource.make(rule: rule, general: bindings, onlyInApps: onlyInApps)
    }

    /// The explanation of the Gestures pane's "Button to hold" row: the buttons, joined as
    /// a list ("Back button and Gesture button."); or in which apps only and with which
    /// ("Only in Figma: Back button."); or that there is none yet. The row's title is not
    /// "Gesture button": under it an MX Master's own "Gesture button" would read twice.
    var gestureButtonExplanation: String {
        if hasGestureButton {
            let buttons = InterfaceList.joined(buttonTitles)
            return String(format: NSLocalizedString("gestures-gesture-button-bound", comment: ""), buttons)
        }
        if let onlyInApps {
            return String(format: NSLocalizedString("gestures-gesture-button-bound", comment: ""), onlyInApps.text)
        }
        return NSLocalizedString("gestures-gesture-button-none", comment: "")
    }

    /// The summary of the bindings that run: the Buttons pane's, and those an app's own
    /// bindings make while it is in front.
    static var current: MouseGestureBindingSummary {
        return MouseGestureBindingSummary(
            bindings: Options.shared.buttons.binding,
            applications: ApplicationTriggerRule.storedApplications,
            isLogitechCode: { LogiCenter.shared.isLogiCode($0) }
        )
    }
}

/// Who keeps the pointer still while a button that runs Gesture Navigation is held, by the
/// settings (what Scrollio asks of the mouse, `LogiUsageBootstrap.gestureTrackingCodes`;
/// whether the mouse took it is known only to the Logitech layer). A hold the mouse tracks
/// never reads "Freeze pointer during a gesture": the mouse reports the movement itself and
/// the pointer stays where it is (`InputProcessor`). So the switch must not read off, as if
/// the pointer moved, while every such button is tracked. Pure.
enum MouseGesturePointerHolder: Equatable {
    /// Scrollio, by the switch: the mouse tracks no button that runs the gestures.
    case scrollio
    /// The mouse, whatever the switch says: it tracks every button that runs the gestures.
    case mouse
    /// The mouse for the buttons it tracks; for the others the switch decides.
    case mouseForSome

    /// - Parameters:
    ///   - deviceTracking: "Let the mouse track the gesture" that counts for the sets.
    ///   - mouseCanTrack: a connected mouse can track a button's hold itself
    ///     (`MouseGestureDeviceSupport.deviceTracking`).
    ///   - bindingSets: the bindings a press goes by, one set per case: the Buttons pane's,
    ///     and those of each app whose own buttons count (`ApplicationButtons.merged`).
    ///   - holdKeys: the keys of Scrolling › While you hold a key the mouse is asked for
    ///     (`ButtonDefaultOutcome.holdKeysThatCatch`): such a button is never tracked.
    static func make(
        deviceTracking: Bool, mouseCanTrack: Bool, bindingSets: [[ButtonBinding]], holdKeys: [ScrollHotkey]
    ) -> MouseGesturePointerHolder {
        guard deviceTracking, mouseCanTrack else { return .scrollio }
        let holdCodes = Set(holdKeys.filter { $0.type == .mouse }.map(\.code))
        var tracked = false
        var untracked = false
        for bindings in bindingSets {
            let codes = LogiUsageBootstrap.gestureTrackingCodes(deviceTracking: true, bindings: bindings, scrollHotkeyCodes: holdCodes)
            for binding in bindings where ApplicationTriggerRule.gestureNavigation.takes(binding) {
                if codes.contains(binding.triggerEvent.code) {
                    tracked = true
                } else {
                    untracked = true
                }
            }
        }
        guard tracked else { return .scrollio }
        return untracked ? .mouseForSome : .mouse
    }

    /// What the switch shows for the stored value: on while the mouse holds the pointer.
    /// Never stored.
    func showsFreeze(stored: Bool) -> Bool {
        return self == .mouse || stored
    }

    /// The switch can be changed: its value decides something.
    var isFreezeEditable: Bool {
        return self != .mouse
    }

    /// The line under "Freeze pointer during a gesture".
    var freezeHintKey: String {
        switch self {
        case .scrollio: return "gesture-freeze-pointer-hint"
        case .mouse: return "gesture-freeze-pointer-mouse-holds"
        case .mouseForSome: return "gesture-freeze-pointer-mouse-holds-some"
        }
    }

    /// Every line `freezeHintKey` can be, so the row can keep room for the longest while a
    /// connected mouse can track (`MouseGestureRows.show`).
    static let freezeHintKeys = [
        "gesture-freeze-pointer-hint", "gesture-freeze-pointer-mouse-holds", "gesture-freeze-pointer-mouse-holds-some",
    ]

    /// The binding sets the Gestures pane's switch is about: the Buttons pane's (every app
    /// without buttons of its own), and for each listed app with buttons of its own that
    /// runs the general gestures, those with its own merged over them. An app that runs its
    /// own gestures has its own switch (its Gestures part).
    static func paneBindingSets(
        general: [ButtonBinding] = Options.shared.buttons.binding,
        applications: [Application] = ApplicationTriggerRule.storedApplications
    ) -> [[ButtonBinding]] {
        return [general] + applications
            .filter { $0.hasOwnButtons && $0.usesGeneralGestures }
            .map { ApplicationButtons.merged(general: general, own: $0.ownButtonBindings) }
    }
}
