//
//  KeyboardLayoutKeys.swift
//  Scrollio
//
//  The letter keys of the keyboard layout in use, for the listed shortcuts and for key names.
//
//  Apps match a ⌘ shortcut by the character its key types, not by where the key is. The
//  listed actions used to be sent as the key codes of the US layout: on a French keyboard
//  (AZERTY) "Select All" pressed ⌘Q and quit the app in front, "Undo" closed the window, and
//  on German "Undo" pressed ⌘Y. So a letter shortcut is sent with the key that types its
//  letter on the layout in use, looked up with Command held (some layouts change under
//  Command: "Dvorak - QWERTY ⌘", and the Cyrillic, Greek or Arabic ones type Latin letters
//  then), and the US key only when the layout has no such key.
//
//  The same lookup names the keys (`KeyCode.name(of:modifiers:)`: on AZERTY the A key read
//  "Q") and tells which listed action a recorded shortcut is (`SystemShortcut.displayShortcut`).
//
//  The layout is read through `KeyboardLayoutSource` (AppZoomKeys.swift), once per layout:
//  its id is compared at each use, which is cheap enough for the button tap's callback, and
//  `warmUp()` at launch keeps the first translation out of it. Main thread only.
//

import Carbon.HIToolbox
import Cocoa

final class KeyboardLayoutKeys {

    /// The app's instance. Under XCTest it has no layout (every answer is the US one), so the
    /// tests do not depend on the keyboard layout of the Mac they run on; a test that is
    /// about a layout sets one (`setTestingLayout`).
    static let shared = KeyboardLayoutKeys(
        layout: AppRuntime.isRunningXCTest ? nil : SystemKeyboardLayoutSource()
    )

    /// What one layout types, as the lookups need it.
    struct Keys: Equatable {
        /// Key code → what the key types with no modifier.
        var plain: [CGKeyCode: String] = [:]
        /// Key code → what it types with Command held.
        var command: [CGKeyCode: String] = [:]
        /// Letter ("a"…"z") → the key that types it with no modifier.
        var plainKeyByLetter: [String: CGKeyCode] = [:]
        /// Letter → the key that types it with Command held.
        var commandKeyByLetter: [String: CGKeyCode] = [:]

        init(plain: [CGKeyCode: String] = [:], command: [CGKeyCode: String] = [:]) {
            self.plain = plain
            self.command = command
            self.plainKeyByLetter = KeyboardLayoutKeys.letterKeys(typing: plain)
            self.commandKeyByLetter = KeyboardLayoutKeys.letterKeys(typing: command)
        }
    }

    private var layout: KeyboardLayoutSource?
    private var cached: (layoutID: String, keys: Keys)?

    init(layout: KeyboardLayoutSource?) {
        self.layout = layout
    }

    // MARK: - Lookups

    /// The key that types `letter` ("a"…"z") on the layout in use, with Command held when
    /// the shortcut has Command; `usKeyCode` when the layout has no such key or there is no
    /// layout. A layout that types the letter only without Command (none of macOS's own does)
    /// is asked without it.
    func keyCode(typing letter: String, withCommand: Bool, usKeyCode: CGKeyCode) -> CGKeyCode {
        guard let keys = currentKeys() else { return usKeyCode }
        if withCommand, let code = keys.commandKeyByLetter[letter] { return code }
        return keys.plainKeyByLetter[letter] ?? usKeyCode
    }

    /// The key a listed shortcut is sent with on the layout in use: for a letter shortcut
    /// (⌘A, ⇧⌘Z) the key that types its letter, for every other its own key. Arrows, Tab,
    /// Space, Esc, Delete, the F-keys and the digit keys are the same keys on every layout.
    func keyCode(for shortcut: SystemShortcut.Shortcut) -> CGKeyCode {
        guard let letter = shortcut.letter else { return shortcut.code }
        return keyCode(typing: letter, withCommand: shortcut.modifiers.contains(.command), usKeyCode: shortcut.code)
    }

    /// What the key `code` is called on the layout in use: what it types (with Command held
    /// when the shortcut has Command), a letter in upper case. nil when there is no layout or
    /// the key types nothing that can be shown; the caller then uses the US name.
    func label(of code: CGKeyCode, withCommand: Bool) -> String? {
        guard let keys = currentKeys() else { return nil }
        if withCommand, let typed = keys.command[code], let label = Self.label(from: typed) { return label }
        return keys.plain[code].flatMap(Self.label(from:))
    }

    /// Reads the layout in use now, so the first shortcut does not translate its keys inside
    /// the button tap's callback. Called at launch.
    func warmUp() {
        _ = currentKeys()
    }

    // MARK: - The layout in use

    /// The keys of the layout in use: translated once per layout, again when its id changes.
    private func currentKeys() -> Keys? {
        guard let layout, let id = layout.currentLayoutID() else { return nil }
        if let cached, cached.layoutID == id { return cached.keys }
        let keys = Keys(plain: layout.currentCharacters(), command: layout.currentCommandCharacters())
        cached = (id, keys)
        return keys
    }

    // MARK: - Pure parts

    /// For each letter a…z the key that types it in `characters`: the US key when that is
    /// one of them (some layouts type a letter on two keys), else the lowest key code. The
    /// keypad is left out, as for the zoom keys.
    static func letterKeys(typing characters: [CGKeyCode: String]) -> [String: CGKeyCode] {
        var candidates: [String: [CGKeyCode]] = [:]
        for (code, typed) in characters where !AppZoomKeys.keypadKeyCodes.contains(code) {
            let letter = typed.lowercased()
            guard KeyCode.usLetterKeyCodes[letter] != nil else { continue }
            candidates[letter, default: []].append(code)
        }
        var result: [String: CGKeyCode] = [:]
        for (letter, codes) in candidates {
            if let usCode = KeyCode.usLetterKeyCodes[letter], codes.contains(usCode) {
                result[letter] = usCode
            } else {
                result[letter] = codes.min()
            }
        }
        return result
    }

    /// What a key types as its name: trimmed, a letter in upper case ("ß" stays: its upper
    /// case is two letters). nil for nothing, white space, control characters and the
    /// private codes of function keys.
    static func label(from typed: String) -> String? {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        for scalar in trimmed.unicodeScalars {
            if CharacterSet.controlCharacters.contains(scalar) { return nil }
            if (0xF700...0xF8FF).contains(scalar.value) { return nil }
        }
        let upper = trimmed.uppercased()
        return upper.count == trimmed.count ? upper : trimmed
    }

    // MARK: - Tests

    #if DEBUG
    /// The layout the lookups read; nil: none (US answers). Forgets what was translated.
    func setTestingLayout(_ layout: KeyboardLayoutSource?) {
        self.layout = layout
        cached = nil
    }
    #endif
}
