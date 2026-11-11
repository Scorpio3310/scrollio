//
//  ButtonTriggerNaming.swift
//  Mos
//  What the Buttons pane calls a trigger: "Left button", "⌥⌘ Back button", "Gesture
//  button", "⌃⌥ K", "F5", and the text of a keyboard-shortcut action ("⇧⌘4"). Pure: the
//  pane, the Gestures pane and the tests share the rules. Only the display changes; the
//  stored trigger is never touched.
//

import Cocoa

enum ButtonTriggerNaming {

    /// What a Logitech code is on the mouse, and the name its control has.
    struct Logitech {
        var role: (UInt16) -> LogiControlRole?
        var name: (UInt16) -> String?

        static let live = Logitech(
            role: { LogiCenter.shared.controlRole(forMosCode: $0) },
            name: { LogiCenter.shared.name(forMosCode: $0) }
        )
    }

    // MARK: - Triggers

    /// The row title of a trigger: the modifiers in front, then the button or the key.
    static func title(for event: RecordedEvent, logitech: Logitech = .live) -> String {
        let modifiers = UInt64(event.modifiers)
        switch event.type {
        case .mouse:
            return joined(symbols(modifiers), buttonName(code: event.code, logitech: logitech))
        case .keyboard:
            if KeyCode.modifierKeys.contains(event.code) {
                // A modifier on its own: every modifier held, its own included.
                return symbols(modifiers | KeyCode.getKeyMask(event.code).rawValue, includesFn: true)
            }
            let fn = !impliesFn(event.code)
            return joined(symbols(modifiers, includesFn: fn), keyName(event.code))
        }
    }

    /// "Left button", "Back button", "Button 5"; Logitech: "Gesture button", "Mode shift
    /// button", "Thumb panel", otherwise the control's name and "button".
    static func buttonName(code: UInt16, logitech: Logitech = .live) -> String {
        switch code {
        case 0: return text("buttons-trigger-left")
        case 1: return text("buttons-trigger-right")
        case 2: return text("buttons-trigger-middle")
        case 3: return text("buttons-trigger-back")
        case 4: return text("buttons-trigger-forward")
        default:
            guard LogiCenter.shared.isLogiCode(code) else {
                return String(format: text("buttons-trigger-number"), Int(code))
            }
            switch logitech.role(code) {
            case .gesture?: return text("buttons-trigger-gesture")
            // The MX Master 4's haptic sense panel: the Mouse pane's "thumb panel".
            case .thumbPanel?: return text("buttons-trigger-thumb-panel")
            case .modeShift?: return text("buttons-trigger-mode-shift")
            case .middle?: return text("buttons-trigger-middle")
            case .back?: return text("buttons-trigger-back")
            case .forward?: return text("buttons-trigger-forward")
            case nil:
                let name = logitech.name(code) ?? String(Int(code))
                if let plain = plainLogitechNames[name] {
                    return text(plain)
                }
                return String(format: text("buttons-trigger-logitech"), name)
            }
        }
    }

    /// Logitech's names that the other panes say in plain words: "DPI" is jargon.
    private static let plainLogitechNames: [String: String] = [
        "DPI Switch": "buttons-trigger-pointer-speed",
    ]

    /// The row titles of `events`, in their order. A Logitech control that would read the
    /// same as a standard button of the list says so ("Back button (Logitech)"); every
    /// other title is `title(for:)`.
    static func titles(for events: [RecordedEvent], logitech: Logitech = .live) -> [String] {
        let titles = events.map { title(for: $0, logitech: logitech) }
        let standard = Set(zip(events, titles).filter { !isLogitech($0.0) }.map(\.1))
        return zip(events, titles).map { event, title in
            guard isLogitech(event), standard.contains(title) else { return title }
            return String(format: text("buttons-trigger-logitech-twin"), title)
        }
    }

    /// The title of `event` among the triggers of `list` (which may hold `event` itself).
    static func title(for event: RecordedEvent, among list: [RecordedEvent], logitech: Logitech = .live) -> String {
        let others = list.filter { $0 != event }
        return titles(for: others + [event], logitech: logitech).last ?? title(for: event, logitech: logitech)
    }

    private static func isLogitech(_ event: RecordedEvent) -> Bool {
        return event.type == .mouse && LogiCenter.shared.isLogiCode(event.code)
    }

    // MARK: - Keyboard shortcuts as actions

    /// The text a keyboard-shortcut action shows: modifiers then the key, as macOS menus
    /// write them ("⇧⌘4"), or the modifiers and a button ("⌘ Middle button").
    static func shortcutText(type: EventType, code: UInt16, modifiers: UInt64, logitech: Logitech = .live) -> String {
        switch type {
        case .mouse:
            return joined(symbols(modifiers), buttonName(code: code, logitech: logitech))
        case .keyboard:
            if KeyCode.modifierKeys.contains(code) {
                return symbols(modifiers | KeyCode.getKeyMask(code).rawValue, includesFn: true)
            }
            return symbols(modifiers, includesFn: !impliesFn(code)) + keyName(code)
        }
    }

    // MARK: - Pieces

    /// The modifiers in the order of macOS menus: ⌃ ⌥ ⇧ ⌘, "Fn" in front.
    static func symbols(_ modifiers: UInt64, includesFn: Bool = true) -> String {
        var result = ""
        if modifiers & CGEventFlags.maskControl.rawValue != 0 { result += "⌃" }
        if modifiers & CGEventFlags.maskAlternate.rawValue != 0 { result += "⌥" }
        if modifiers & CGEventFlags.maskShift.rawValue != 0 { result += "⇧" }
        if modifiers & CGEventFlags.maskCommand.rawValue != 0 { result += "⌘" }
        if includesFn, modifiers & CGEventFlags.maskSecondaryFn.rawValue != 0 {
            result = result.isEmpty ? "Fn" : "Fn " + result
        }
        return result
    }

    /// The key's name as the recorder shows it ("K", "F5", "↩").
    static func keyName(_ code: UInt16) -> String {
        return KeyCode.keyMap[code] ?? String(format: text("buttons-trigger-key"), Int(code))
    }

    /// Keys the Mac reports with Fn held whether or not it is: function keys, arrows, Home,
    /// End, Page Up and Down. Fn is not written for them.
    private static func impliesFn(_ code: UInt16) -> Bool {
        let navigation: Set<UInt16> = [115, 116, 119, 121, 131, 160, 176, 177, 178]
        return KeyCode.functionKeys.contains(code) || KeyCode.arrowKeys.contains(code) || navigation.contains(code)
    }

    private static func joined(_ modifiers: String, _ name: String) -> String {
        return modifiers.isEmpty ? name : "\(modifiers) \(name)"
    }

    private static func text(_ key: String) -> String {
        return NSLocalizedString(key, comment: "")
    }
}
