//
//  SystemVolumeKeys.swift
//  Mos
//
//  The volume keys of an Apple keyboard, pressed as the keys themselves would be: macOS
//  changes the volume by its own step and shows its volume display. Used by the thumb
//  wheel's "volume" function; it is not an action of the Buttons tab's menu.
//

import Cocoa

/// One volume key.
enum SystemVolumeKey: Equatable {
    case up
    case down

    /// `NX_KEYTYPE_SOUND_UP` and `NX_KEYTYPE_SOUND_DOWN` (IOKit/hidsystem/ev_keymap.h).
    var keyType: Int {
        switch self {
        case .up: return 0
        case .down: return 1
        }
    }

    /// The system-defined event subtype of the keyboard's special keys (`NX_SUBTYPE_AUX_CONTROL_BUTTONS`).
    static let auxControlButtonsSubtype: Int16 = 8
    /// The key state in `data1`: `NX_KEYDOWN` and `NX_KEYUP`.
    static let keyDownState = 0x0A
    static let keyUpState = 0x0B

    /// `data1` of the key's event: the key type, then the state (`keyType << 16 | state << 8`).
    func data1(down: Bool) -> Int {
        return (keyType << 16) | ((down ? Self.keyDownState : Self.keyUpState) << 8)
    }

    /// The key's down or up event, as the keyboard sends it, marked as Scrollio's own
    /// (`ScrollioEventMarker`) like every key it posts.
    func event(down: Bool) -> CGEvent? {
        let state = down ? Self.keyDownState : Self.keyUpState
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: Self.auxControlButtonsSubtype,
            data1: data1(down: down),
            data2: -1
        ), let cgEvent = event.cgEvent else {
            return nil
        }
        cgEvent.setIntegerValueField(.eventSourceUserData, value: ScrollioEventMarker.syntheticCustom)
        return cgEvent
    }
}

/// Presses volume keys. Main thread.
struct SystemVolumeKeys {
    /// Where the events go: to the system. The seam: tests replace it, so nothing is posted
    /// and the volume does not change.
    var post: (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) }

    /// One press: the key goes down and up.
    func press(_ key: SystemVolumeKey) {
        if let down = key.event(down: true) { post(down) }
        if let up = key.event(down: false) { post(up) }
    }
}
