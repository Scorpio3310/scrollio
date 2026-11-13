//
//  ShortcutRingSettings.swift
//  Scrollio
//
//  What the Shortcut Ring holds: eight places around the pointer, clockwise from the top,
//  each with one action or nothing. The user's choice, stored in Options (group `.ring`,
//  UserDefaults key "shortcutRingSettings") and carried by a settings file.
//
//  A place holds the name of one of the listed keyboard shortcuts (`SystemShortcut`: Copy,
//  Mission Control, a screenshot …), as a direction of Gesture Navigation does. Not in a
//  place in this version: a recorded key combination, an app or a file to open, a mouse
//  click (it would click where the hand ended up), a Logitech action (it belongs to the
//  mouse whose button was pressed), and what only means something while held. So nothing
//  a ring holds can start a program, and a settings file may carry it.
//  What opens the ring is not in here: it is an action of its own
//  (`SystemShortcut.shortcutRing`), bound in Buttons like any other.
//
//  Stored format:
//
//      {"places": [{"action": "missionControl"}, {"action": ""}, {"action": "copy"}, …]}
//
//  Read value by value: a missing or unreadable place is an empty one, a list that is too
//  short is filled up with empty places and one that is too long is cut. Only data without
//  a list of places at all gives the default ring. A place is an object so that a later
//  version can add to it. Do not rename the keys.
//

import Foundation

/// One place of the ring: an action, or nothing.
struct ShortcutRingPlace: Codable, Equatable {

    /// The action's name, a `SystemShortcut` identifier. Empty: nothing. A name this
    /// version does not run (a newer version's) is kept as stored and does nothing.
    let action: String

    static let empty = ShortcutRingPlace(action: "")

    init(action: String) {
        self.action = action
    }

    init(_ shortcut: SystemShortcut.Shortcut) {
        self.init(action: shortcut.identifier)
    }

    var isEmpty: Bool {
        return action.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case action
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        action = ((try? c.decodeIfPresent(String.self, forKey: .action)) ?? nil) ?? ""
    }

    // MARK: What a place runs

    /// The codes from here up stand for actions that are no key (`SystemShortcut`: the
    /// ring itself and Gesture Navigation, the scroll holds, the modifier keys, the
    /// Logitech actions, the mouse clicks).
    private static let firstPlaceholderCode: UInt16 = 0xFFFB

    /// The shortcut a place with this name runs: a listed keyboard shortcut that is not
    /// retired. Nil for everything else, the empty name included.
    static func shortcut(named action: String) -> SystemShortcut.Shortcut? {
        guard let shortcut = SystemShortcut.getShortcut(named: action),
              shortcut.code < firstPlaceholderCode,
              !SystemShortcut.isRetired(action) else { return nil }
        return shortcut
    }

    /// The shortcut this place runs; nil for an empty place and for a name that is no
    /// keyboard shortcut of this version.
    var shortcut: SystemShortcut.Shortcut? {
        return Self.shortcut(named: action)
    }

    /// Whether choosing this place does something.
    var runs: Bool {
        return shortcut != nil
    }

    /// What the pane's menus offer, in their order: the categories of keyboard shortcuts.
    static var offeredCategories: [(category: String, shortcuts: [SystemShortcut.Shortcut])] {
        return SystemShortcut.shortcutsByCategory
            .map { (category: $0.category, shortcuts: $0.shortcuts.filter { shortcut(named: $0.identifier) != nil }) }
            .filter { !$0.shortcuts.isEmpty }
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
