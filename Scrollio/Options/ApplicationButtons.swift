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
//    itself. An entry without buttons of its own is stored without the key, as before.
//  - What stays general for every app: what opens the Shortcut Ring and what runs Gesture
//    Navigation. An app's binding on such a button or key, and one whose action is the ring
//    or Gesture Navigation, is not used.
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

    /// Opening the Shortcut Ring and Gesture Navigation stay general: an app does not get
    /// them, and cannot take them from a button.
    static func isGeneralOnly(action name: String) -> Bool {
        return name == SystemShortcut.shortcutRing.identifier
            || name == SystemShortcut.mouseGestureNavigation.identifier
    }

    /// The buttons and keys that stay general: those an enabled general binding opens the
    /// ring or runs Gesture Navigation with, whatever the modifier keys.
    static func generalOnlyTriggers(in general: [ButtonBinding]) -> Set<ButtonBindingTriggerKey> {
        return Set(general.filter { $0.isEnabled && isGeneralOnly(action: $0.systemShortcutName) }.map(\.triggerKey))
    }

    /// The app's bindings that count: one per trigger (the first), none on a button that
    /// stays general, none with an action that stays general.
    static func usable(_ own: [ButtonBinding], general: [ButtonBinding]) -> [ButtonBinding] {
        guard !own.isEmpty else { return [] }
        let kept = generalOnlyTriggers(in: general)
        var result: [ButtonBinding] = []
        for binding in own where !isGeneralOnly(action: binding.systemShortcutName) && !kept.contains(binding.triggerKey) {
            guard !result.contains(where: { $0.identity == binding.identity }) else { continue }
            result.append(binding)
        }
        return result
    }

    /// Whether `binding`, one of the app's own, is used (`usable`).
    static func isUsable(_ binding: ButtonBinding, general: [ButtonBinding]) -> Bool {
        return !isGeneralOnly(action: binding.systemShortcutName)
            && !generalOnlyTriggers(in: general).contains(binding.triggerKey)
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
    /// entry without buttons of its own always was.
    func setOwnButtonBindings(_ bindings: [ButtonBinding]) {
        guard bindings != ownButtonBindings || (bindings.isEmpty && buttons != nil) else { return }
        buttons = bindings.isEmpty ? nil : OPTIONS_BUTTONS_DEFAULT(binding: bindings)
    }

    /// What the entry holds under "buttons", read so that nothing in it takes the entry
    /// with it: a value that cannot be read is no buttons of its own, a binding that cannot
    /// be read is left out by itself.
    static func readOwnButtons<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>, forKey key: Key
    ) -> OPTIONS_BUTTONS_DEFAULT? {
        guard let stored = (try? container.decodeIfPresent(StoredOwnButtons.self, forKey: key)) ?? nil else { return nil }
        let bindings = stored.binding.compactMap(\.binding)
        return bindings.isEmpty ? nil : OPTIONS_BUTTONS_DEFAULT(binding: bindings)
    }
}

/// "buttons" of an app's entry as stored: `{"binding": [...]}`.
private struct StoredOwnButtons: Decodable {
    let binding: [ReadableBinding]

    /// One binding, or nil when it cannot be read (the rest of the list still is).
    struct ReadableBinding: Decodable {
        let binding: ButtonBinding?

        init(from decoder: Decoder) throws {
            binding = try? ButtonBinding(from: decoder)
        }
    }
}
