//
//  AppZoomKeys.swift
//  Mos
//
//  The keys of an app's zoom (⌘+ or ⌘= zooms in, ⌘− zooms out) on the keyboard layout in use.
//  Apps match these by the character a key types, and on many layouts "-" and "+" are on other
//  keys than on the US one (Slovenian and German QWERTZ: "-" where US has "/"): the US key
//  codes would not zoom out there. Used by the thumb wheel's "zoom".
//
//  The layout seam (`KeyboardLayoutSource`) is shared with `KeyboardLayoutKeys`, which finds
//  the keys of the listed letter shortcuts (⌘A, ⌘Z, …) and names keys the same way.
//

import Carbon.HIToolbox
import Cocoa

/// The keyboard layout in use. The seam: tests pass a fake layout.
protocol KeyboardLayoutSource {
    /// Identifies the layout in use (its input source id); nil when there is none. Asked at
    /// every zoom step, so it must be cheap.
    func currentLayoutID() -> String?
    /// What each key of the layout in use types with no modifier (key code → character).
    /// Asked once per layout.
    func currentCharacters() -> [CGKeyCode: String]
    /// The same with Command held: what an app compares a ⌘ shortcut with. Some layouts
    /// change under Command ("Dvorak - QWERTY ⌘", and the Cyrillic, Greek or Arabic ones,
    /// which type Latin letters then). Asked once per layout.
    func currentCommandCharacters() -> [CGKeyCode: String]
}

extension KeyboardLayoutSource {
    /// A layout that does not change under Command.
    func currentCommandCharacters() -> [CGKeyCode: String] { return currentCharacters() }
}

/// The layout macOS types with now (Text Input Sources and UCKeyTranslate). Main thread: the
/// input source functions want it.
struct SystemKeyboardLayoutSource: KeyboardLayoutSource {

    func currentLayoutID() -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else { return nil }
        return Self.id(of: source)
    }

    func currentCharacters() -> [CGKeyCode: String] {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else { return [:] }
        return Self.characters(of: source)
    }

    func currentCommandCharacters() -> [CGKeyCode: String] {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else { return [:] }
        return Self.characters(of: source, modifierKeyState: Self.commandKeyState)
    }

    /// UCKeyTranslate's modifier state for "Command held" (the Carbon modifier bits, shifted).
    static let commandKeyState = UInt32(cmdKey >> 8) & 0xFF

    static func id(of source: TISInputSource) -> String? {
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }

    /// Keys 0–127 of a layout, each translated with no modifier (or with `modifierKeyState`,
    /// see `commandKeyState`) and no dead-key state. Empty for an input source without layout
    /// data.
    static func characters(of source: TISInputSource, modifierKeyState: UInt32 = 0) -> [CGKeyCode: String] {
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return [:] }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return [:] }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        let keyboardType = UInt32(LMGetKbdType())
        var result: [CGKeyCode: String] = [:]
        var characters = [UniChar](repeating: 0, count: 4)
        for code in CGKeyCode(0)..<CGKeyCode(128) {
            var deadKeyState: UInt32 = 0
            var length = 0
            let status = UCKeyTranslate(
                layout, code, UInt16(kUCKeyActionDown), modifierKeyState, keyboardType,
                OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState,
                characters.count, &length, &characters
            )
            guard status == noErr, length > 0 else { continue }
            result[code] = String(utf16CodeUnits: characters, count: length)
        }
        return result
    }
}

/// The key codes of ⌘-zoom on the layout in use: found once per layout, looked up again when
/// the layout changes (its id is compared at each step). Main thread.
final class AppZoomKeys {

    struct Codes: Equatable {
        var zoomIn: CGKeyCode
        var zoomOut: CGKeyCode
    }

    /// The US keys "=" and "-": for a layout that types neither "+"/"=" nor "-" on a key.
    static let usCodes = Codes(zoomIn: CGKeyCode(kVK_ANSI_Equal), zoomOut: CGKeyCode(kVK_ANSI_Minus))

    /// The keypad's keys type "+", "-" and "=" on every layout; the apps' menus show the main
    /// keys, so the keypad is left out.
    static let keypadKeyCodes: Set<CGKeyCode> = Set([
        kVK_ANSI_KeypadDecimal, kVK_ANSI_KeypadMultiply, kVK_ANSI_KeypadPlus, kVK_ANSI_KeypadClear,
        kVK_ANSI_KeypadDivide, kVK_ANSI_KeypadEnter, kVK_ANSI_KeypadMinus, kVK_ANSI_KeypadEquals,
        kVK_ANSI_Keypad0, kVK_ANSI_Keypad1, kVK_ANSI_Keypad2, kVK_ANSI_Keypad3, kVK_ANSI_Keypad4,
        kVK_ANSI_Keypad5, kVK_ANSI_Keypad6, kVK_ANSI_Keypad7, kVK_ANSI_Keypad8, kVK_ANSI_Keypad9,
    ].map { CGKeyCode($0) })

    static let shared = AppZoomKeys()

    private let layout: KeyboardLayoutSource
    private var cached: (layoutID: String, codes: Codes)?

    init(layout: KeyboardLayoutSource = SystemKeyboardLayoutSource()) {
        self.layout = layout
    }

    /// The codes for the layout in use.
    func codes() -> Codes {
        guard let id = layout.currentLayoutID() else { return Self.usCodes }
        if let cached = cached, cached.layoutID == id { return cached.codes }
        // With Command held, as the apps see the keys: on nine of macOS's layouts (Estonian,
        // Serbian, Thai, "Dvorak - QWERTY ⌘", …) "+" and "-" are on other keys then.
        let codes = Self.codes(typing: layout.currentCommandCharacters())
        cached = (id, codes)
        return codes
    }

    /// Zoom in: the key that types "+" (with Command held, no Shift), else the one that types
    /// "="; zoom out: the key that types "-". Each falls back to the US key when the layout
    /// has none. Pure.
    static func codes(typing characters: [CGKeyCode: String]) -> Codes {
        func key(typing wanted: String) -> CGKeyCode? {
            return characters
                .filter { $0.value == wanted && !keypadKeyCodes.contains($0.key) }
                .map(\.key)
                .min()
        }
        return Codes(
            zoomIn: key(typing: "+") ?? key(typing: "=") ?? usCodes.zoomIn,
            zoomOut: key(typing: "-") ?? usCodes.zoomOut
        )
    }
}
