//
//  ShortcutLabel.swift
//  Scrollio
//
//  What a user calls a key combination they recorded: a name, an icon, or both. "⇧⌘R"
//  says nothing about what it does in the app it is meant for, so the ring and the rows
//  of the panes show the name and the icon, and the keys smaller beside them.
//
//  A label belongs to the one place of a Shortcut Ring or the one binding of a button
//  that holds the combination, not to the combination: ⇧⌘R means one thing in one app's
//  ring and another in the next. Only a recorded key combination takes one (`takes`): a
//  listed shortcut has its own name and symbol, an app to open its own name and icon, and
//  a click needs neither.
//
//  Stored beside the action, under "label", and only when there is one:
//
//      {"action": "custom::15:1179648", "label": {"name": "Reload", "symbol": "arrow.clockwise"}}
//      {"action": "custom::15:1179648", "label": {"character": "R"}}
//
//  An entry from before has no "label" and reads as before; an entry without a label is
//  written as before; an older version ignores "label" and still reads the keys. Read
//  value by value: a label that cannot be read is no label, and never fails the place or
//  the binding it stands in. Do not rename the keys.
//
//  The name is the user's own text: it is shown, said to VoiceOver and written to a
//  settings file, and it never goes into a log.
//

import Foundation

struct ShortcutLabel: Codable, Equatable {

    /// What stands for the combination in a drop of the ring and before its name in a row.
    enum Icon: Equatable {
        /// An SF Symbol, by its name.
        case symbol(String)
        /// One character the user typed: a letter, a sign, an emoji.
        case character(String)
    }

    /// Never empty; nil: no name.
    let name: String?
    let icon: Icon?

    /// The longest name: two lines of the ring's middle hold about this much, and a row
    /// still has room for the keys after it.
    static let maximumNameLength = 24
    /// What one character of a name (or the typed icon) is made of, at most: "R" with any
    /// number of accents is one character. The longest emoji of today (a kiss of two
    /// people with their skin tones) takes 10; a letter keeps its first marks.
    static let maximumScalarsPerCharacter = 16
    /// What a whole name is made of, at most: a name of nothing but long emoji ends at a
    /// character before this.
    static let maximumNameScalars = 128
    /// A symbol's name is letters, digits and dots ("arrow.clockwise", "1.circle").
    static let maximumSymbolNameLength = 64

    /// Nil when nothing is left of `name` and `icon` once they are cleaned: no label.
    init?(name: String?, icon: Icon?) {
        let name = name.flatMap(Self.cleanedName)
        let icon = icon.flatMap(Self.cleaned)
        guard name != nil || icon != nil else { return nil }
        self.name = name
        self.icon = icon
    }

    /// A name as it is stored: one line, without control characters and without the
    /// invisible ones that turn the direction of a text around (the keys stand after the
    /// name in a row, and must read as they are), no space at either end, cut as `cut`
    /// does. Nil: nothing left that can be seen.
    static func cleanedName(_ text: String) -> String? {
        var visible = String.UnicodeScalarView()
        // Right after 🏴, and after each tag that follows it: an emoji flag's tags.
        var inFlag = false
        for scalar in text.unicodeScalars {
            let isTag = (0xE0020...0xE007F).contains(scalar.value)
            defer { inFlag = scalar.value == 0x1F3F4 || (inFlag && isTag && scalar.value != 0xE007F) }
            switch scalar.properties.generalCategory {
            case .lineSeparator, .paragraphSeparator:
                visible.append(" ")
            case .control:
                // A line break or a tab that was pasted is a space; the others go.
                if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                    visible.append(" ")
                }
            case .format:
                // What joins the parts of an emoji or of a word stays, and an emoji
                // flag's tags; direction marks, overrides and tags anywhere else (text
                // that is kept and shown nowhere) go.
                if scalar == "\u{200C}" || scalar == "\u{200D}" || (isTag && inFlag) {
                    visible.append(scalar)
                }
            case .surrogate, .unassigned:
                // (Not a private-use character: the system font draws the Apple logo,
                // typed with ⌥⇧K, and it stays.)
                break
            default:
                visible.append(scalar)
            }
        }
        let trimmed = String(visible).trimmingCharacters(in: .whitespaces)
        let name = cut(trimmed).trimmingCharacters(in: .whitespaces)
        return name.contains(where: canBeSeen) ? name : nil
    }

    /// `text` as long as a name may be: at most `maximumNameLength` characters, each of at
    /// most `maximumScalarsPerCharacter` scalars (a letter keeps its first marks), and at
    /// most `maximumNameScalars` in all; it ends at a character.
    static func cut(_ text: String) -> String {
        var kept = String.UnicodeScalarView()
        var characters = 0
        for character in text {
            guard characters < maximumNameLength else { break }
            let scalars = character.unicodeScalars.prefix(maximumScalarsPerCharacter)
            guard kept.count + scalars.count <= maximumNameScalars else { break }
            kept.append(contentsOf: scalars)
            // (A character that was cut short may join the next one: never into one that
            // is too long.)
            if let last = String(kept).last, last.unicodeScalars.count > maximumScalarsPerCharacter {
                kept.removeLast(scalars.count)
                break
            }
            characters += 1
        }
        return String(kept)
    }

    /// Whether `character` shows something by itself: not a space, nor a joiner, a tag, a
    /// variation selector or a mark with nothing before it to stand on.
    private static func canBeSeen(_ character: Character) -> Bool {
        guard !character.isWhitespace, let first = character.unicodeScalars.first else { return false }
        switch first.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark:
            return false
        default:
            return !first.properties.isDefaultIgnorableCodePoint
        }
    }

    /// An icon as it is stored. A symbol: a name of lowercase letters, digits and dots
    /// (whether this Mac has it is the drawing's question, not the store's). A character:
    /// the first one of what was typed that can be seen.
    static func cleaned(_ icon: Icon) -> Icon? {
        switch icon {
        case .symbol(let name):
            let allowed = name.unicodeScalars.allSatisfy { scalar in
                return ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) || scalar == "."
            }
            guard allowed, !name.isEmpty, name.count <= maximumSymbolNameLength else { return nil }
            return .symbol(name)
        case .character(let text):
            guard let first = cleanedName(text)?.first(where: canBeSeen) else { return nil }
            return .character(String(first))
        }
    }

    /// Whether an action with this stored name can carry a label: a recorded key
    /// combination, and nothing else.
    static func takes(action: String) -> Bool {
        return ButtonBinding.normalizedCustomBindingDescriptor(from: action)?.type == .keyboard
    }

    /// `label` as far as `action` may carry it. (Without a label nothing is looked at:
    /// a binding is built from a place each time the place runs.)
    static func kept(_ label: ShortcutLabel?, for action: String) -> ShortcutLabel? {
        guard let label, takes(action: action) else { return nil }
        return label
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case name, symbol, character
    }

    /// Throws when nothing of a label can be read; whoever holds the label reads it with
    /// `try?` and goes on without one.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? nil
        let symbol = (try? c.decodeIfPresent(String.self, forKey: .symbol)) ?? nil
        let character = (try? c.decodeIfPresent(String.self, forKey: .character)) ?? nil
        let icon = symbol.flatMap { Self.cleaned(.symbol($0)) } ?? character.flatMap { Self.cleaned(.character($0)) }
        guard let label = ShortcutLabel(name: name, icon: icon) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath, debugDescription: "A label with neither a name nor an icon"
            ))
        }
        self = label
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(name, forKey: .name)
        switch icon {
        case .symbol(let name)?:
            try c.encode(name, forKey: .symbol)
        case .character(let text)?:
            try c.encode(text, forKey: .character)
        case nil:
            break
        }
    }
}
