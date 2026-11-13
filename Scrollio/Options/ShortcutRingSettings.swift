//
//  ShortcutRingSettings.swift
//  Scrollio
//
//  What the Shortcut Ring holds: eight places around the pointer, clockwise from the top,
//  each with one action or nothing. The user's choice, stored in Options (group `.ring`,
//  UserDefaults key "shortcutRingSettings") and carried by a settings file.
//
//  A place stores its action as a button of the Buttons pane does (`ButtonBinding`): the
//  action's name, and for "Open App or File…" what to open. It can hold
//
//  - one of the listed keyboard shortcuts (`SystemShortcut`: Copy, Mission Control …),
//    or the Back or the Forward click;
//  - a recorded key combination ("custom::<key>:<modifiers>");
//  - an app, a file or a script to open ("openTarget" with its payload).
//
//  Not in a place: the ring itself and Gesture Navigation, what only means something
//  while held (the modifier keys, the scroll holds), the left, right and middle click
//  (they would click where the hand ended up) and the Logitech actions (they belong to
//  the mouse whose button was pressed). A place whose action is one of those, or a name
//  this version does not know, shows as empty and runs nothing (`runs`).
//  What opens the ring is not in here: it is an action of its own
//  (`SystemShortcut.shortcutRing`), bound in Buttons like any other.
//
//  Stored format:
//
//      {"places": [{"action": "missionControl"}, {"action": ""}, {"action": "custom::40:1179648"},
//                  {"action": "openTarget", "openTarget": {"path": …, "arguments": …, "kind": …}}, …]}
//
//  Read value by value: a missing or unreadable place is an empty one, a list that is too
//  short is filled up with empty places and one that is too long is cut. Only data without
//  a list of places at all gives the default ring. Do not rename the keys.
//

import Foundation

/// One place of the ring: an action, or nothing.
struct ShortcutRingPlace: Codable, Equatable {

    /// The action's stored name, as `ButtonBinding.systemShortcutName`. Empty: nothing.
    /// A name this version does not run (a newer version's) is kept as stored.
    let action: String
    /// What to open; set exactly when `action` is `ButtonBinding.openTargetSentinel`.
    let openTarget: OpenTargetPayload?

    static let empty = ShortcutRingPlace(action: "")

    /// A place whose two fields contradict each other (a name with a target, the "open"
    /// name without one) holds nothing: a binding like that is not read either
    /// (`ButtonBinding.init(from:)`), and it could show one thing and run another.
    init(action: String, openTarget: OpenTargetPayload? = nil) {
        guard (action == ButtonBinding.openTargetSentinel) == (openTarget != nil) else {
            self.action = ""
            self.openTarget = nil
            return
        }
        self.action = action
        self.openTarget = openTarget
    }

    init(_ shortcut: SystemShortcut.Shortcut) {
        self.init(action: shortcut.identifier)
    }

    init(openTarget: OpenTargetPayload) {
        self.init(action: ButtonBinding.openTargetSentinel, openTarget: openTarget)
    }

    var isEmpty: Bool {
        return action.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case action, openTarget
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let action = ((try? c.decodeIfPresent(String.self, forKey: .action)) ?? nil) ?? ""
        let target = (try? c.decodeIfPresent(OpenTargetPayload.self, forKey: .openTarget)) ?? nil
        self.init(action: action, openTarget: target)
    }

    // MARK: What a place runs

    /// What a place holds, as far as this version runs it.
    enum Content: Equatable {
        case nothing
        /// A listed keyboard shortcut, or the Back or Forward click.
        case shortcut(SystemShortcut.Shortcut)
        /// A recorded key combination.
        case keyCombination(code: UInt16, modifiers: UInt64)
        /// An app or a file to open, or a script to run.
        case open(OpenTargetPayload)
    }

    /// The codes from here up stand for actions that are no key (`SystemShortcut`: the
    /// ring itself and Gesture Navigation, the scroll holds, the modifier keys, the
    /// Logitech actions, the mouse clicks).
    private static let firstPlaceholderCode: UInt16 = 0xFFFB

    /// The two clicks a place may hold: they mean "back" and "forward" wherever the
    /// pointer is. (Left, right and middle click where the hand ended up.)
    private static let allowedClicks: Set<String> = [
        SystemShortcut.mouseBackClick.identifier, SystemShortcut.mouseForwardClick.identifier,
    ]

    /// The listed action a place with this name runs: a keyboard shortcut that is not
    /// retired, or the Back or Forward click. Nil for everything else.
    static func shortcut(named action: String) -> SystemShortcut.Shortcut? {
        guard let shortcut = SystemShortcut.getShortcut(named: action),
              shortcut.code < firstPlaceholderCode || allowedClicks.contains(action),
              !SystemShortcut.isRetired(action) else { return nil }
        return shortcut
    }

    /// The key combination a place with this stored name sends: a recorded key with or
    /// without modifiers. Nil for a recorded mouse button (a click) and for a modifier
    /// key by itself (it only means something while held).
    static func keyCombination(named action: String) -> (code: UInt16, modifiers: UInt64)? {
        guard let recorded = ButtonBinding.normalizedCustomBindingDescriptor(from: action),
              recorded.type == .keyboard,
              !KeyCode.modifierKeys.contains(recorded.code) else { return nil }
        return (recorded.code, recorded.modifiers)
    }

    var content: Content {
        if let openTarget { return .open(openTarget) }
        if let shortcut = Self.shortcut(named: action) { return .shortcut(shortcut) }
        if let key = Self.keyCombination(named: action) { return .keyCombination(code: key.code, modifiers: key.modifiers) }
        return .nothing
    }

    /// The listed action this place runs; nil for an empty place and for every other
    /// kind of content.
    var shortcut: SystemShortcut.Shortcut? {
        guard case .shortcut(let shortcut) = content else { return nil }
        return shortcut
    }

    /// Whether choosing this place does something.
    var runs: Bool {
        return content != .nothing
    }

    // MARK: As a button's action

    /// The trigger of the stand-in binding below: the left button, which is never a
    /// trigger and cannot be recorded. The binding is never stored with the buttons and
    /// never matched against an event.
    private static let standInTrigger = RecordedEvent(type: .mouse, code: 0, modifiers: 0, deviceFilter: nil)

    /// This place's action as a binding, for the code that shows, names, records and
    /// resolves a button's action (its cache of a recorded key is prepared). A place
    /// that runs nothing gives a binding without an action.
    func asBinding(id: UUID = UUID()) -> ButtonBinding {
        var binding: ButtonBinding
        if runs, let openTarget {
            binding = ButtonBinding(id: id, triggerEvent: Self.standInTrigger, openTarget: openTarget, isEnabled: true)
        } else {
            binding = ButtonBinding(
                id: id, triggerEvent: Self.standInTrigger, systemShortcutName: runs ? action : "", isEnabled: runs
            )
        }
        binding.prepareCustomCache()
        return binding
    }

    /// The action of a binding as a place (the pane's rows use the buttons' pull-down).
    init(actionOf binding: ButtonBinding) {
        self.init(action: binding.systemShortcutName, openTarget: binding.openTarget)
    }

    /// What choosing this place runs, as the executor resolves a button's action; nil
    /// when the place runs nothing.
    var resolvedAction: ResolvedAction? {
        guard runs else { return nil }
        let binding = asBinding()
        return ShortcutExecutor.shared.resolveAction(named: binding.systemShortcutName, binding: binding)
    }
}

/// How the eight places are called, clockwise from the top: the catalog keys of "Top",
/// "Top right" … "Top left".
enum ShortcutRingPlaceName {

    static let keys = [
        "ring-place-top", "ring-place-top-right", "ring-place-right", "ring-place-bottom-right",
        "ring-place-bottom", "ring-place-bottom-left", "ring-place-left", "ring-place-top-left",
    ]

    static func key(of place: Int) -> String {
        return keys.indices.contains(place) ? keys[place] : keys[0]
    }

    static func localized(_ place: Int) -> String {
        return NSLocalizedString(key(of: place), comment: "")
    }
}

/// The ring: `placeCount` places, clockwise from the top.
struct ShortcutRingSettings: Codable, Equatable {

    static let placeCount = 8

    /// Always `placeCount` places.
    private(set) var places: [ShortcutRingPlace]

    /// What a new ring holds: Mission Control on top and Apps at the bottom (as the
    /// gestures' up and down), the desktops left and right, Copy and Paste beside Apps,
    /// a screenshot and Show Desktop beside Mission Control. No two neighbours look alike:
    /// the two grids (Mission Control, Apps) face each other, and so do the two pairs of
    /// sheets (Copy and Paste; Show Desktop is not next to either).
    static let `default` = ShortcutRingSettings(places: [
        ShortcutRingPlace(SystemShortcut.missionControl),       // top
        ShortcutRingPlace(SystemShortcut.screenshotSelection),  // top right
        ShortcutRingPlace(SystemShortcut.moveSpaceRight),       // right
        ShortcutRingPlace(SystemShortcut.paste),                // bottom right
        ShortcutRingPlace(SystemShortcut.appExpose),            // bottom
        ShortcutRingPlace(SystemShortcut.copy),                 // bottom left
        ShortcutRingPlace(SystemShortcut.moveSpaceLeft),        // left
        ShortcutRingPlace(SystemShortcut.showDesktop),          // top left
    ])

    init(places: [ShortcutRingPlace]) {
        self.places = Self.filledUp(places)
    }

    subscript(index: Int) -> ShortcutRingPlace {
        get {
            return places.indices.contains(index) ? places[index] : .empty
        }
        set {
            guard places.indices.contains(index) else { return }
            places[index] = newValue
        }
    }

    /// Which places hold an action that runs.
    var filled: [Bool] {
        return places.map { $0.runs }
    }

    /// A place opens an app or a file or runs a script: showing the ring as the Buttons
    /// pane would takes a look on disk (the file, its name, its icon).
    var opensSomething: Bool {
        return places.contains { $0.openTarget != nil }
    }

    /// Exactly `placeCount` places: cut, or filled up with empty ones.
    static func filledUp(_ places: [ShortcutRingPlace]) -> [ShortcutRingPlace] {
        var result = Array(places.prefix(placeCount))
        while result.count < placeCount {
            result.append(.empty)
        }
        return result
    }

    /// The ring with every place emptied whose action this version does not run. Returns
    /// how many were emptied. For a settings file: a name a later version gives a meaning
    /// must not come in unseen.
    func keepingOnlyWhatRuns() -> (ring: ShortcutRingSettings, emptied: Int) {
        var emptied = 0
        let kept: [ShortcutRingPlace] = places.map { place in
            guard !place.isEmpty, !place.runs else { return place }
            emptied += 1
            return .empty
        }
        return (ShortcutRingSettings(places: kept), emptied)
    }

    private enum CodingKeys: String, CodingKey {
        case places
    }

    /// One place that may not be readable: empty instead of failing the ring.
    private struct ReadablePlace: Decodable {
        let place: ShortcutRingPlace

        init(from decoder: Decoder) throws {
            place = (try? ShortcutRingPlace(from: decoder)) ?? .empty
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let stored = (try? c.decodeIfPresent([ReadablePlace].self, forKey: .places)) ?? nil else {
            self = .default
            return
        }
        self.init(places: stored.map { $0.place })
    }
}
