//
//  KeyboardLayoutLayers.swift
//  Scrollio
//
//  What one keyboard layout types, layer by layer (no modifier, Shift, Command, Shift and
//  Command), and the key that types a character there. For the suggested shortcuts of an
//  app's Shortcut Ring (`ShortcutRingSuggestions`), which store a shortcut as the
//  characters of a US keyboard and become keys only when they fill a ring: on Slovenian
//  or German QWERTZ "z" is the US Y key, "-" the US "/" key, "=" is Shift-0 and "[" needs
//  Option.
//
//  Read once per fill, in Settings: never in the event path. The letters and the zoom keys
//  are found as `KeyboardLayoutKeys` and `AppZoomKeys` find them (their pure parts); the
//  Option layer is never asked (Option changes the character on a Mac, and a shortcut with
//  an Option it did not have is another shortcut).
//

import Carbon.HIToolbox
import Cocoa

struct KeyboardLayoutLayers: Equatable {

    /// Key code → what the key types with no modifier.
    var plain: [CGKeyCode: String]
    /// … with Shift held.
    var shift: [CGKeyCode: String]
    /// … with Command held (what an app compares a ⌘ shortcut with; some layouts change
    /// under Command, "Dvorak - QWERTY ⌘" and the non-Latin ones).
    var command: [CGKeyCode: String]
    /// … with Shift and Command held.
    var commandShift: [CGKeyCode: String]

    // MARK: - Layouts

    /// The US layout's main block: the layout the suggestions are written for, and what a
    /// fill uses when no layout can be read (and under XCTest, so that the tests do not
    /// depend on the Mac's layout).
    static let us: KeyboardLayoutLayers = {
        let keys: [(CGKeyCode, String, String)] = [
            (0, "a", "A"), (1, "s", "S"), (2, "d", "D"), (3, "f", "F"), (4, "h", "H"), (5, "g", "G"),
            (6, "z", "Z"), (7, "x", "X"), (8, "c", "C"), (9, "v", "V"), (11, "b", "B"), (12, "q", "Q"),
            (13, "w", "W"), (14, "e", "E"), (15, "r", "R"), (16, "y", "Y"), (17, "t", "T"),
            (18, "1", "!"), (19, "2", "@"), (20, "3", "#"), (21, "4", "$"), (22, "6", "^"), (23, "5", "%"),
            (24, "=", "+"), (25, "9", "("), (26, "7", "&"), (27, "-", "_"), (28, "8", "*"), (29, "0", ")"),
            (30, "]", "}"), (31, "o", "O"), (32, "u", "U"), (33, "[", "{"), (34, "i", "I"), (35, "p", "P"),
            (37, "l", "L"), (38, "j", "J"), (39, "'", "\""), (40, "k", "K"), (41, ";", ":"), (42, "\\", "|"),
            (43, ",", "<"), (44, "/", "?"), (45, "n", "N"), (46, "m", "M"), (47, ".", ">"), (50, "`", "~"),
        ]
        var plain: [CGKeyCode: String] = [:]
        var shift: [CGKeyCode: String] = [:]
        for (code, unshifted, shifted) in keys {
            plain[code] = unshifted
            shift[code] = shifted
        }
        return KeyboardLayoutLayers(plain: plain, shift: shift, command: plain, commandShift: shift)
    }()

    /// The four layers of an input source (UCKeyTranslate, keys 0–127, no dead keys); nil
    /// for one without layout data.
    static func of(_ source: TISInputSource) -> KeyboardLayoutLayers? {
        let plain = SystemKeyboardLayoutSource.characters(of: source)
        guard !plain.isEmpty else { return nil }
        let shiftState = UInt32(shiftKey >> 8) & 0xFF
        let commandState = SystemKeyboardLayoutSource.commandKeyState
        return KeyboardLayoutLayers(
            plain: plain,
            shift: SystemKeyboardLayoutSource.characters(of: source, modifierKeyState: shiftState),
            command: SystemKeyboardLayoutSource.characters(of: source, modifierKeyState: commandState),
            commandShift: SystemKeyboardLayoutSource.characters(of: source, modifierKeyState: commandState | shiftState)
        )
    }

    /// The layout macOS types with now. Main thread (the input source functions want it).
    static func current() -> KeyboardLayoutLayers? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else { return nil }
        return of(source)
    }

    // MARK: - Lookups

    /// The key that types `character` in `layer`: the lowest key code, the keypad left out
    /// (the apps' menus show the main keys). Nil when no key types it.
    static func key(typing character: String, in layer: [CGKeyCode: String]) -> CGKeyCode? {
        return layer
            .filter { $0.value == character && !AppZoomKeys.keypadKeyCodes.contains($0.key) }
            .map(\.key)
            .min()
    }

    /// The key a shortcut with `character` (a US key's unshifted character) and `modifiers`
    /// is sent with on this layout, and the modifiers it is sent with: the same ones, Shift
    /// added when the layout types the character only with Shift, Shift taken away when the
    /// layout types without Shift what the US shortcut typed with it (⇧⌘. is ⌘> on US, and
    /// ">" has a key of its own elsewhere). Nil when the layout types the character only
    /// with Option, or not at all: the shortcut cannot be sent as itself there.
    ///
    /// - A letter: the key that types it, with Command held when the shortcut has Command
    ///   (`KeyboardLayoutKeys`); the US key when the layout has none.
    /// - A digit: the key that types it without Shift (its US key where that types it;
    ///   Hungarian's "0" is left of 1); its US key where no key does (AZERTY types the
    ///   digits with Shift, and ⌘1 is the US key there, as for the listed shortcuts).
    /// - ⌘= and ⌘- (zoom): the keys `AppZoomKeys` finds, "+" before "=" without Shift,
    ///   where the layout has them under Command alone; else as any other sign (its
    ///   fallback, the US key, types another character there: "^" on Swiss, "x" on
    ///   Turkish F).
    /// - Any other sign: the key that types it (with Shift as said).
    /// - Never ⌘ or ⇧⌘ with the key that is "`" on US (`windowSwitchingKeyCode`) unless
    ///   the shortcut is that key on US too: those are macOS's "Move focus to next window"
    ///   and back, and a sent shortcut goes through them. On ISO German or Slovenian that
    ///   key types "<" and ">", so ⇧⌘, and ⇧⌘. (zoom in Notes) would switch windows.
    func key(for character: String, modifiers: CGEventFlags) -> (code: CGKeyCode, modifiers: CGEventFlags)? {
        guard let key = resolvedKey(for: character, modifiers: modifiers) else { return nil }
        let switchesWindows: [CGEventFlags] = [.maskCommand, [.maskShift, .maskCommand]]
        if key.code == Self.windowSwitchingKeyCode, switchesWindows.contains(key.modifiers),
           Self.us.plain[Self.windowSwitchingKeyCode] != character {
            return nil
        }
        return key
    }

    /// The key macOS's "Move focus to next window" is on (⌘ with it; ⇧⌘ goes back): "`"
    /// left of 1 on US, beside the left Shift on ISO keyboards.
    static let windowSwitchingKeyCode: CGKeyCode = 50

    private func resolvedKey(for character: String, modifiers: CGEventFlags) -> (code: CGKeyCode, modifiers: CGEventFlags)? {
        let withCommand = modifiers.contains(.maskCommand)
        let unshiftedLayer = withCommand && !command.isEmpty ? command : plain
        // (Under Command many layouts drop Shift's characters, US among them: ⇧⌘. reads
        // "." there. So the Shift layer without Command is asked too.)
        let shiftedLayers = withCommand ? [commandShift, shift] : [shift]

        if let usCode = KeyCode.usLetterKeyCodes[character] {
            let code = KeyboardLayoutKeys.letterKeys(typing: unshiftedLayer)[character]
                ?? KeyboardLayoutKeys.letterKeys(typing: plain)[character]
                ?? usCode
            return (code, modifiers)
        }
        if let digit = Self.usDigitKeyCodes[character] {
            guard unshiftedLayer[digit] != character, let code = Self.key(typing: character, in: unshiftedLayer) else {
                return (digit, modifiers)
            }
            return (code, modifiers)
        }
        if modifiers == .maskCommand, character == "=" || character == "-" {
            let zoom = AppZoomKeys.codes(typing: unshiftedLayer)
            let code = character == "=" ? zoom.zoomIn : zoom.zoomOut
            let zooms: Set<String> = character == "=" ? ["+", "="] : ["-"]
            if let typed = unshiftedLayer[code], zooms.contains(typed) {
                return (code, modifiers)
            }
        }

        var wanted = character
        var sent = modifiers
        if modifiers.contains(.maskShift), let shifted = Self.usShifted[character] {
            wanted = shifted
            sent.remove(.maskShift)
        }
        if let code = Self.key(typing: wanted, in: unshiftedLayer) {
            return (code, sent)
        }
        for layer in shiftedLayers {
            if let code = Self.key(typing: wanted, in: layer) {
                return (code, sent.union(.maskShift))
            }
        }
        return nil
    }

    /// What a US sign key types with Shift ("=" → "+", "." → ">").
    static let usShifted: [String: String] = {
        var shifted: [String: String] = [:]
        for (code, character) in us.plain where us.shift[code] != nil && KeyCode.usLetterKeyCodes[character] == nil {
            shifted[character] = us.shift[code]
        }
        return shifted
    }()

    /// The digit keys of the main block.
    static let usDigitKeyCodes: [String: CGKeyCode] = [
        "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26, "8": 28, "9": 25, "0": 29,
    ]
}
