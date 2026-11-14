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
    /// name in a row, and must read as they are), no space at either end, at most
    /// `maximumNameLength` characters. Nil: nothing left.
    static func cleanedName(_ text: String) -> String? {
        var visible = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
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
                // flag's tags; direction marks and overrides go.
                if scalar == "\u{200C}" || scalar == "\u{200D}" || (0xE0020...0xE007F).contains(scalar.value) {
                    visible.append(scalar)
                }
            case .surrogate, .privateUse, .unassigned:
                break
            default:
                visible.append(scalar)
            }
        }
        let trimmed = String(visible).trimmingCharacters(in: .whitespaces)
        let cut = String(trimmed.prefix(maximumNameLength)).trimmingCharacters(in: .whitespaces)
        return cut.isEmpty ? nil : cut
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
            guard let first = cleanedName(text)?.first else { return nil }
            return .character(String(first))
        }
    }

    /// Whether an action with this stored name can carry a label: a recorded key
    /// combination, and nothing else.
    static func takes(action: String) -> Bool {
        return ButtonBinding.normalizedCustomBindingDescriptor(from: action)?.type == .keyboard
    }

    /// `label` as far as `action` may carry it.
    static func kept(_ label: ShortcutLabel?, for action: String) -> ShortcutLabel? {
        return takes(action: action) ? label : nil
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
