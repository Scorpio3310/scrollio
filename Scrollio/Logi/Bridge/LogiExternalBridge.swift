// Scrollio/Logi/LogiExternalBridge.swift
import Foundation

/// Outward-facing contract from Logi to integrations. Step 2 introduces stubs
/// (only handleLogiScrollHotkey called; dispatchLogiButtonEvent and showLogiToast
/// added in Step 4 alongside production wiring). Lives inside Scrollio/Logi/ but is
/// `internal` access — same Xcode target as InputEvent / InputPhase, which it
/// references; making it `public` would force those types public too.
internal protocol LogiExternalBridge: AnyObject {
    func dispatchLogiButtonEvent(_ event: InputEvent) -> LogiDispatchResult
    func handleLogiScrollHotkey(code: UInt16, phase: InputPhase)
    func showLogiToast(_ message: String, severity: LogiToastSeverity)
    /// Movement of a held button the mouse tracks itself (raw XY), in sensor counts: +x
    /// right, +y towards the user. Only sent for a hold whose button-down event had
    /// `tracksMovementOnDevice` set, about 125 times a second. Hot path.
    func handleLogiGestureMovement(code: UInt16, deltaX: Int, deltaY: Int)
}

internal enum LogiDispatchResult: Equatable {
    case consumed
    case unhandled
    case logiAction(name: String)
}

internal enum LogiToastSeverity {
    case info, warning, error
}
