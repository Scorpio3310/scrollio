//
//  LogiIntegrationBridge.swift
//  Mos
//
//  Production LogiExternalBridge implementation. Routes Logi events to
//  ScrollCore, ButtonUtils, InputProcessor, Toast — keeping Scrollio/Logi/ free
//  of cross-module references (Step 5 lint will enforce this).
//

import Foundation

final class LogiIntegrationBridge: LogiExternalBridge {

    static let shared = LogiIntegrationBridge()
    private init() {}

    /// The Logitech buttons that are down: their press came through here, their release
    /// (or the one Scrollio makes up) has not yet. The divert keeps such a button until it
    /// is up (`LogiUsageBootstrap.refreshButtonUsage`), and so does the mouse's tracking of
    /// its hold (`refreshGestureTracking`). Main thread, as every event here.
    private(set) var heldButtonCodes: Set<UInt16> = []

    func dispatchLogiButtonEvent(_ event: InputEvent) -> LogiDispatchResult {
        if event.phase == .down {
            heldButtonCodes.insert(event.code)
        } else if heldButtonCodes.remove(event.code) != nil {
            LogiUsageBootstrap.buttonWasReleased(event.code)
        }

        // Recording mode: forward to KeyRecorder via the relay notification.
        // Hot-path post #1 (matches §11 cap: rawButtonEvent + buttonEventRelay).
        if LogiCenter.shared.isRecording {
            NotificationCenter.default.post(
                name: LogiCenter.buttonEventRelay,
                object: nil,
                userInfo: ["event": event]
            )
            return .consumed
        }

        // Whose bindings this press goes by (the app in front may have its own), decided
        // once for the probe and InputProcessor alike. A release does not look again.
        let scope = event.phase == .down ? ButtonUtils.shared.scopeOfPress(for: event) : nil

        // Probe for logi* binding; the session executes the action so the
        // hardware action stays scoped to the originating device (no global
        // activeBindings registration). The best binding for the press is chosen first, as
        // InputProcessor chooses it: a Logitech action on the plain button must not win over
        // a binding of the same button with modifier keys that the press holds.
        if let scope,
           let binding = ButtonUtils.shared.getBestMatchingBinding(for: event, scope: scope),
           binding.systemShortcutName.hasPrefix("logi") {
            return .logiAction(name: binding.systemShortcutName)
        }

        // Generic binding via InputProcessor (covers up phase + non-Logi
        // bindings like custom::).
        let result = InputProcessor.shared.process(event, scope: scope)
        if result == .consumed { return .consumed }

        // Unconsumed: fire the relay so KeyRecorder + other observers see it.
        NotificationCenter.default.post(
            name: LogiCenter.buttonEventRelay,
            object: nil,
            userInfo: ["event": event]
        )
        return .unhandled
    }

    func handleLogiScrollHotkey(code: UInt16, phase: InputPhase) {
        _ = ScrollCore.shared.handleScrollHotkey(code: code, isDown: phase == .down)
    }

    func handleLogiGestureMovement(code: UInt16, deltaX: Int, deltaY: Int) {
        InputProcessor.shared.handleDeviceGestureMovement(code: code, countsX: deltaX, countsY: deltaY)
    }

    /// The Buttons pane's own name for the button, so that a toast and the pane agree.
    func logiButtonName(forScrollioCode code: UInt16) -> String? {
        return ButtonTriggerNaming.buttonName(code: code)
    }

    func showLogiToast(_ message: String, severity: LogiToastSeverity) {
        let style: Toast.Style
        switch severity {
        case .info:    style = .info
        case .warning: style = .warning
        case .error:   style = .error
        }
        Toast.show(message, style: style)
    }
}
