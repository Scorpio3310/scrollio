//
//  GestureActions.swift
//  Scrollio
//
//  What Gesture Navigation runs: one action for each direction and one for the click of
//  the gesture button. An action is stored as a button's is (`ButtonBinding`): a listed
//  action's name, or a recorded key combination ("custom::<key>:<modifiers>"), which can
//  carry what the user calls it (`ShortcutLabel`), as a place of the Shortcut Ring can.
//
//  One value, so that an app can later hold a set of its own; the general set is part of
//  `MouseGestureSettings` and stored inside its entry, beside its other keys:
//
//      {"upAction": "custom::15:1179648", "upLabel": {"name": "Reload", "symbol": "arrow.clockwise"},
//       "downAction": "appExpose", "leftAction": "moveSpaceLeft", "rightAction": "moveSpaceRight",
//       "clickAction": "missionControl", …}
//
//  A label is written only when there is one, so an entry without one is written as
//  before, and an older version reads the actions and ignores the labels. A missing
//  action is the default one (as before); a label that cannot be read, or one on an action
//  that takes none, is no label. Do not rename the keys.
//
//  What a direction may hold is what a place of the ring may run: a listed action of the
//  Gestures pane, or a recorded key combination with or without modifiers (never a
//  modifier key by itself: it means something only while held). The Back and Forward
//  buttons, recorded, are the listed Back and Forward clicks.
//

import Foundation

/// The action of one direction (or of the click).
struct GestureAction: Equatable {

    /// The stored name, as `ButtonBinding.systemShortcutName`. Empty: nothing. A name this
    /// version does not run is kept as stored and runs nothing.
    let action: String
    /// The name and icon the user gave a recorded key combination; nil for every other
    /// kind of action (`ShortcutLabel.takes`).
    let label: ShortcutLabel?
    /// The keys a recorded key combination sends, read from `action` once, when the value
    /// is made (the settings are read or changed), never while a gesture runs. Nil for
    /// every other kind of action.
    let keys: Keys?

    struct Keys: Equatable {
        let code: UInt16
        let modifiers: UInt64
    }

    static let none = GestureAction(action: "")

    init(action: String, label: ShortcutLabel? = nil) {
        self.action = action
        self.label = ShortcutLabel.kept(label, for: action)
        // As a place of the ring sends it (`ShortcutRingPlace.keyCombination`).
        keys = ShortcutRingPlace.keyCombination(named: action).map { Keys(code: $0.code, modifiers: $0.modifiers) }
    }

    init(_ shortcut: SystemShortcut.Shortcut) {
        self.init(action: shortcut.identifier)
    }

    var isEmpty: Bool {
        return action.isEmpty
    }

    /// The same action with another name: a label only while it stays the same action.
    func replacingAction(with name: String) -> GestureAction {
        return GestureAction(action: name, label: name == action ? label : nil)
    }

    /// What running it does, as the executor resolves an action: a recorded key
    /// combination from its prepared keys, as a place of the ring sends it; any other
    /// action by its name. Nil: it runs nothing.
    var resolvedAction: ResolvedAction? {
        guard !action.isEmpty else { return nil }
        if let keys {
            return .customKey(code: keys.code, modifiers: keys.modifiers)
        }
        return ShortcutExecutor.shared.resolveAction(named: action)
    }

    /// What it ran, for the log: a listed action by its identifier, a recorded key
    /// combination by its kind (never its keys, never its name).
    var logName: String {
        return keys == nil ? action : "a recorded key combination"
    }

    // MARK: As a button's action

    /// The trigger of the stand-in binding below, as a ring's place has one: the left
    /// button, which is never a trigger and cannot be recorded. The binding is never
    /// stored and never matched against an event.
    private static let standInTrigger = RecordedEvent(type: .mouse, code: 0, modifiers: 0, deviceFilter: nil)

    /// This action as a binding, for the code that shows, names and records a button's
    /// action (the pane's pull-downs, the import sheet).
    func asBinding(id: UUID = UUID()) -> ButtonBinding {
        var binding = ButtonBinding(
            id: id, triggerEvent: Self.standInTrigger, systemShortcutName: action, isEnabled: !isEmpty, label: label
        )
        binding.prepareCustomCache()
        return binding
    }

    /// The action of a binding (the pane's rows use the buttons' pull-down).
    init(actionOf binding: ButtonBinding) {
        self.init(action: binding.systemShortcutName, label: binding.label)
    }
}

/// The five actions of Gesture Navigation.
struct GestureActions: Codable, Equatable {

    var up: GestureAction
    var down: GestureAction
    var left: GestureAction
    var right: GestureAction
    var click: GestureAction

    /// Mission Control up and on a click, Apps down, the desktops left and right.
    static let `default` = GestureActions(
        up: GestureAction(SystemShortcut.missionControl),
        down: GestureAction(SystemShortcut.appExpose),
        left: GestureAction(SystemShortcut.moveSpaceLeft),
        right: GestureAction(SystemShortcut.moveSpaceRight),
        click: GestureAction(SystemShortcut.missionControl)
    )

    init(up: GestureAction, down: GestureAction, left: GestureAction, right: GestureAction, click: GestureAction) {
        self.up = up
        self.down = down
        self.left = left
        self.right = right
        self.click = click
    }

    /// The action of a direction as it is stored (before "Invert left and right").
    subscript(direction: MouseGestureDirection) -> GestureAction {
        get {
            switch direction {
            case .up: return up
            case .down: return down
            case .left: return left
            case .right: return right
            }
        }
        set {
            switch direction {
            case .up: up = newValue
            case .down: down = newValue
            case .left: left = newValue
            case .right: right = newValue
            }
        }
    }

    /// All five, up, down, left, right, click.
    var all: [GestureAction] {
        return [up, down, left, right, click]
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case upAction, downAction, leftAction, rightAction, clickAction
        case upLabel, downLabel, leftLabel, rightLabel, clickLabel
    }

    private static let keys: [(action: CodingKeys, label: CodingKeys, path: WritableKeyPath<GestureActions, GestureAction>)] = [
        (.upAction, .upLabel, \.up),
        (.downAction, .downLabel, \.down),
        (.leftAction, .leftLabel, \.left),
        (.rightAction, .rightLabel, \.right),
        (.clickAction, .clickLabel, \.click),
    ]

    /// A missing action is the default one; an action that is no text fails, as it
    /// always did (the gesture settings are then the defaults). A label is read value by
    /// value and never fails anything.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var actions = Self.default
        for key in Self.keys {
            let action = try c.decodeIfPresent(String.self, forKey: key.action) ?? Self.default[keyPath: key.path].action
            let label = (try? c.decodeIfPresent(ShortcutLabel.self, forKey: key.label)) ?? nil
            actions[keyPath: key.path] = GestureAction(action: action, label: label)
        }
        self = actions
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        for key in Self.keys {
            let action = self[keyPath: key.path]
            try c.encode(action.action, forKey: key.action)
            try c.encodeIfPresent(action.label, forKey: key.label)
        }
    }
}
