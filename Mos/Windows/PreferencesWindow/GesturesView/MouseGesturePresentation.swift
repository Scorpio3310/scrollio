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
                haptics: LogiCenter.shared.supportsGestureHaptics()
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

    init(support: MouseGestureDeviceSupport) {
        deviceTrackingEnabled = support.deviceTracking
        deviceTrackingHintKey = support.deviceTracking
            ? "mouse-gesture-device-tracking-hint"
            : "mouse-gesture-device-tracking-unavailable"
        hapticsEnabled = support.haptics
        hapticsHintKey = support.haptics
            ? "mouse-gesture-haptics-hint"
            : "mouse-gesture-haptics-unavailable"
    }

    /// The tab shows the Logitech options only when a connected mouse supports at least one
    /// of them; otherwise a line says what they need.
    var showsOptions: Bool {
        return deviceTrackingEnabled || hapticsEnabled
    }
}

/// What the stored button bindings mean for the Gestures tab.
struct MouseGestureBindingSummary: Equatable {
    /// An enabled button is bound to Gesture Navigation, so the settings have an effect.
    var hasGestureButton: Bool
    /// One of those buttons is a Logitech control: Logi actions make sense as gesture actions.
    var hasLogitechGestureButton: Bool
    /// The names of those buttons, as the Buttons pane titles them ("Back button").
    var buttonTitles: [String]

    init(hasGestureButton: Bool, hasLogitechGestureButton: Bool, buttonTitles: [String] = []) {
        self.hasGestureButton = hasGestureButton
        self.hasLogitechGestureButton = hasLogitechGestureButton
        self.buttonTitles = buttonTitles
    }

    init(
        bindings: [ButtonBinding],
        isLogitechCode: (UInt16) -> Bool,
        title: (RecordedEvent) -> String = { ButtonTriggerNaming.title(for: $0) }
    ) {
        let gestureBindings = bindings.filter {
            $0.isEnabled && $0.systemShortcutName == SystemShortcut.mouseGestureNavigation.identifier
        }
        hasGestureButton = !gestureBindings.isEmpty
        hasLogitechGestureButton = gestureBindings.contains {
            $0.triggerEvent.type == .mouse && isLogitechCode($0.triggerEvent.code)
        }
        var titles: [String] = []
        for binding in gestureBindings {
            let name = title(binding.triggerEvent)
            if !titles.contains(name) {
                titles.append(name)
            }
        }
        buttonTitles = titles
    }

    /// The explanation of the Gestures pane's "Gesture button" row: the buttons, joined as
    /// a list ("Back button and Gesture button"), or that there is none yet.
    var gestureButtonExplanation: String {
        guard hasGestureButton else {
            return NSLocalizedString("gestures-gesture-button-none", comment: "")
        }
        return ListFormatter.localizedString(byJoining: buttonTitles)
    }

    /// The summary of the stored bindings, global and per app.
    static var current: MouseGestureBindingSummary {
        var bindings = Options.shared.buttons.binding
        let applications = Options.shared.application.applications
        for index in 0..<applications.count {
            if let perApp = applications.get(by: index)?.buttons?.binding {
                bindings.append(contentsOf: perApp)
            }
        }
        return MouseGestureBindingSummary(bindings: bindings, isLogitechCode: { LogiCenter.shared.isLogiCode($0) })
    }
}
