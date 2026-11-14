//
//  ApplicationButtons.swift
//  Scrollio
//
//  Buttons of an app's own: only what differs from Buttons. While the app is in front its
//  bindings count, and every other button does what the Buttons pane says (as Logi
//  Options+ does it).
//
//  Stored with the app's entry, under "buttons" (the field was there, reserved and unused,
//  since the original app; no released version of Scrollio set it: 1.0.0 to 1.0.5 only
//  carried what was there along, for Undo of a removal and through a settings file):
//
//      {"path": …, "inherit": true, "scroll": {…},
//       "buttons": {"binding": [{"triggerEvent": {…}, "systemShortcutName": "copy", …}]}}
//
//  - A binding is the binding of its trigger (`ButtonBindingIdentity`: the kind, the code,
//    the modifier keys and the mouse it is limited to). The app's binding replaces the
//    general binding of the same trigger, and one of a trigger Buttons does not have is
//    added; every other general binding stays.
//  - An action of "" ("Default") is the app's own too: while the app is in front the
//    button does what it does by itself (the press passes through).
//  - No "buttons", an empty list, or a value that cannot be read: no buttons of its own
//    (the entry stays readable). A binding of the list that cannot be read is left out by
//    itself, and kept as stored for the next save (`OwnButtonsWithUnread`). An entry
//    without buttons of its own is stored without the key, as before.
//  - Nothing stays general: an app's binding may open the Shortcut Ring or run Gesture
//    Navigation, and may give a button that opens the ring or runs the gestures in Buttons
//    something else to do while the app is in front.
//  Do not rename the keys.
//

import Cocoa

/// What makes a binding the binding of a button or key: its trigger as a press is matched
/// against it (`RecordedEvent.matchPriority`). Where the user said the button is on the
/// mouse (`mousePart`) does not count.
struct ButtonBindingIdentity: Equatable {
    let type: EventType
    let code: UInt16
    /// The modifier keys only.
    let modifiers: UInt
    let deviceFilter: DeviceFilter?

    init(_ trigger: RecordedEvent) {
        type = trigger.type
        code = trigger.code
        modifiers = trigger.modifiers & UInt(KeyCode.modifiersMask)
        deviceFilter = trigger.deviceFilter
    }
}

extension ButtonBinding {
    var identity: ButtonBindingIdentity {
        return ButtonBindingIdentity(triggerEvent)
    }

    /// The button or key, whatever the modifier keys.
    var triggerKey: ButtonBindingTriggerKey {
        return ButtonBindingTriggerKey(type: triggerEvent.type, code: triggerEvent.code)
    }
}

/// The rules of an app's own buttons. Pure: the input side, the Logitech divert, the app's
/// page and their tests share them.
enum ApplicationButtons {

    /// The app's bindings that count: one per trigger (the first). The Shortcut Ring and
    /// Gesture Navigation count as any other action, on any button.
    static func usable(_ own: [ButtonBinding], general: [ButtonBinding]) -> [ButtonBinding] {
        guard !own.isEmpty else { return [] }
        var result: [ButtonBinding] = []
        for binding in own where !result.contains(where: { $0.identity == binding.identity }) {
            result.append(binding)
        }
        return result
    }

    /// The bindings a press goes by while the app is in front: the general ones in their
    /// order, each replaced by the app's binding of the same trigger, then the app's
    /// bindings of triggers Buttons does not have. Without usable bindings of its own: the
    /// general list itself.
    static func merged(general: [ButtonBinding], own: [ButtonBinding]) -> [ButtonBinding] {
        let own = usable(own, general: general)
        guard !own.isEmpty else { return general }
        var placed = Array(repeating: false, count: own.count)
        var result: [ButtonBinding] = []
        result.reserveCapacity(general.count + own.count)
        for binding in general {
            guard let index = own.firstIndex(where: { $0.identity == binding.identity }) else {
                result.append(binding)
                continue
            }
            // (A second general binding of the same trigger goes with the first.)
            if !placed[index] {
                placed[index] = true
                result.append(own[index])
            }
        }
        for (index, binding) in own.enumerated() where !placed[index] {
            result.append(binding)
        }
        return result
    }

    /// The entry of the app in front, found as the Shortcut Ring and the scroll engine find
    /// it: by the bundle's path, then by the program's. Nil without an app in front, for
    /// Scrollio itself (its settings are in front: every button does what Buttons says, so
    /// they can be tried there) and for an app not on the list.
    static func entry(
        front: ShortcutRingChoice.FrontApp?, applications: EnhanceArray<Application>
    ) -> Application? {
        guard let front, !front.isScrollio else { return nil }
        return applications.get(by: front.bundlePath) ?? applications.get(by: front.executablePath)
    }

    /// What a press of exactly `trigger` does in an app without buttons of its own: the
    /// general binding of the same trigger, else the general binding such a press matches
    /// best (a button bound without modifier keys also runs with them). Nil: none, the
    /// button does what it does by itself.
    static func generalBinding(for trigger: RecordedEvent, in general: [ButtonBinding]) -> ButtonBinding? {
        let identity = ButtonBindingIdentity(trigger)
        if let same = general.first(where: { $0.identity == identity }) {
            return same
        }
        let press = InputEvent(
            type: trigger.type, code: trigger.code, modifiers: CGEventFlags(rawValue: UInt64(trigger.modifiers)),
            phase: .down, source: .hidPP, device: nil
        )
        var best: ButtonBinding?
        var bestPriority = Int.min
        for binding in general where binding.isEnabled && ButtonUtils.isRunnable(binding.triggerEvent) {
            guard let priority = binding.triggerEvent.matchPriority(for: press), priority > bestPriority else { continue }
            best = binding
            bestPriority = priority
        }
        return best
    }
}

// MARK: - The app's entry

extension Application {

    /// The app's own bindings as stored; empty: every button does what Buttons says.
    var ownButtonBindings: [ButtonBinding] {
        return buttons?.binding ?? []
    }

    /// The app has buttons of its own (the mark in the list of apps).
    var hasOwnButtons: Bool {
        return !ownButtonBindings.isEmpty
    }

    /// Stores `bindings` as the app's own. None stores nothing: the entry is written as an
    /// entry without buttons of its own always was. Bindings of the stored list this version
    /// cannot read stay, whatever is stored (they were never shown, so no edit removed them).
    func setOwnButtonBindings(_ bindings: [ButtonBinding]) {
        let unread = (buttons as? OwnButtonsWithUnread)?.unread ?? []
        guard bindings != ownButtonBindings || (bindings.isEmpty && unread.isEmpty && buttons != nil) else { return }
        buttons = Self.ownButtons(bindings, unread: unread)
    }

    private static func ownButtons(_ bindings: [ButtonBinding], unread: [StoredJSON]) -> OPTIONS_BUTTONS_DEFAULT? {
        if !unread.isEmpty {
            return OwnButtonsWithUnread(binding: bindings, unread: unread)
        }
        return bindings.isEmpty ? nil : OPTIONS_BUTTONS_DEFAULT(binding: bindings)
    }

    /// What the entry holds under "buttons", read so that nothing in it takes the entry
    /// with it: a value that cannot be read is no buttons of its own, a binding that cannot
    /// be read is left out by itself, and kept as stored for the next save (of a newer
    /// version, it is there again when that version reads the entry), as the bindings of
    /// Buttons that this version cannot read are.
    static func readOwnButtons<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>, forKey key: Key
    ) -> OPTIONS_BUTTONS_DEFAULT? {
        guard let stored = (try? container.decodeIfPresent(StoredOwnButtons.self, forKey: key)) ?? nil else { return nil }
        return ownButtons(stored.binding.compactMap(\.binding), unread: stored.binding.compactMap(\.unread))
    }
}

/// An app's own buttons with bindings this version cannot read: those it reads in
/// `binding`, the others as they were stored, written back after them (the order of an
/// object's keys aside). Nothing runs them and no pane shows them.
final class OwnButtonsWithUnread: OPTIONS_BUTTONS_DEFAULT {
    let unread: [StoredJSON]

    init(binding: [ButtonBinding], unread: [StoredJSON]) {
        self.unread = unread
        super.init(binding: binding)
    }

    required init(from decoder: Decoder) throws {
        unread = []
        try super.init(from: decoder)
    }

    private enum Keys: String, CodingKey {
        case binding
    }

    override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        var list = container.nestedUnkeyedContainer(forKey: .binding)
        for element in self.binding {
            try list.encode(element)
        }
        for element in unread {
            try list.encode(element)
        }
    }
}

/// "buttons" of an app's entry as stored: `{"binding": [...]}`.
private struct StoredOwnButtons: Decodable {
    let binding: [ReadableBinding]

    /// One binding, or nil when it cannot be read (the rest of the list still is).
    struct ReadableBinding: Decodable {
        let binding: ButtonBinding?
        /// An element that is no binding this version reads, as stored, when it is an object
        /// or a list (what the bindings of Buttons keep too); nil for a binding it reads and
        /// for anything else (a number, a string, null), which is dropped.
        let unread: StoredJSON?

        init(from decoder: Decoder) throws {
            binding = try? ButtonBinding(from: decoder)
            guard binding == nil, let element = try? StoredJSON(from: decoder) else {
                unread = nil
                return
            }
            switch element {
            case .object, .list: unread = element
            default: unread = nil
            }
        }
    }
}

/// A JSON value as it was read, to be written back as it was: a number keeps whether it
/// was whole; the order of an object's keys is not kept.
enum StoredJSON: Codable {
    case null
    case bool(Bool)
    case integer(Int64)
    case number(Double)
    case string(String)
    case list([StoredJSON])
    case object([String: StoredJSON])

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { return nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(from decoder: Decoder) throws {
        if let object = try? decoder.container(keyedBy: Key.self) {
            var values: [String: StoredJSON] = [:]
            for key in object.allKeys {
                values[key.stringValue] = try object.decode(StoredJSON.self, forKey: key)
            }
            self = .object(values)
        } else if var list = try? decoder.unkeyedContainer() {
            var values: [StoredJSON] = []
            while !list.isAtEnd {
                values.append(try list.decode(StoredJSON.self))
            }
            self = .list(values)
        } else {
            let value = try decoder.singleValueContainer()
            if value.decodeNil() {
                self = .null
            } else if let bool = try? value.decode(Bool.self) {
                self = .bool(bool)
            } else if let integer = try? value.decode(Int64.self) {
                self = .integer(integer)
            } else if let number = try? value.decode(Double.self) {
                self = .number(number)
            } else {
                self = .string(try value.decode(String.self))
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .null:
            var value = encoder.singleValueContainer()
            try value.encodeNil()
        case .bool(let bool):
            var value = encoder.singleValueContainer()
            try value.encode(bool)
        case .integer(let integer):
            var value = encoder.singleValueContainer()
            try value.encode(integer)
        case .number(let number):
            var value = encoder.singleValueContainer()
            try value.encode(number)
        case .string(let string):
            var value = encoder.singleValueContainer()
            try value.encode(string)
        case .list(let values):
            var list = encoder.unkeyedContainer()
            for element in values {
                try list.encode(element)
            }
        case .object(let values):
            var object = encoder.container(keyedBy: Key.self)
            for (key, element) in values {
                try object.encode(element, forKey: Key(stringValue: key))
            }
        }
    }
}
