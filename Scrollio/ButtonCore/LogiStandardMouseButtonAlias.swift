//
//  LogiStandardMouseButtonAlias.swift
//  Mos
//

import Cocoa

/// Standard HID++ mouse controls that can be treated as stable macOS mouse
/// button triggers.
enum LogiStandardMouseButtonAlias {
    static func nativeButtonCode(forScrollioCode code: UInt16) -> UInt16? {
        return LogiCenter.shared.nativeMouseButton(forScrollioCode: code)
    }

    /// The Logitech code of the standard middle, back or forward button (2, 3, 4): the same
    /// button as the Buttons pane stores it while the mouse is on its receiver (the control
    /// is diverted there). Over Bluetooth the button arrives as the standard one. Nil for
    /// every other button.
    static func logitechCode(forNativeButton button: UInt16) -> UInt16? {
        return logitechCodesByNativeButton[button]
    }

    private static let logitechCodesByNativeButton: [UInt16: UInt16] = {
        var codes: [UInt16: UInt16] = [:]
        for role in [LogiControlRole.middle, .back, .forward] {
            let code = LogiCenter.shared.scrollioCode(for: role)
            if let native = LogiCenter.shared.nativeMouseButton(forScrollioCode: code) {
                codes[native] = code
            }
        }
        return codes
    }()

    static func convertedRecordedEvent(from event: RecordedEvent) -> RecordedEvent? {
        guard event.type == .mouse else {
            return nil
        }
        guard let nativeCode = nativeButtonCode(forScrollioCode: event.code) else {
            return nil
        }

        return RecordedEvent(
            type: .mouse,
            code: nativeCode,
            modifiers: event.modifiers,
            deviceFilter: nil
        )
    }

    static func convertedBinding(from binding: ButtonBinding) -> ButtonBinding? {
        guard let nativeTrigger = convertedRecordedEvent(from: binding.triggerEvent) else {
            return nil
        }
        return binding.replacingTriggerEvent(nativeTrigger)
    }
}
