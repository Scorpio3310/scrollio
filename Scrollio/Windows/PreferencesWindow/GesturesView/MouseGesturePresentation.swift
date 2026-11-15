//
//  MouseGesturePresentation.swift
//  Mos
//  Pure helpers for the Gestures tab: what the connected mice can do for Gesture
//  Navigation, which Logitech options are shown and enabled and what the stored button
//  bindings mean for the tab. Kept free of views so the rules can be unit tested.
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
