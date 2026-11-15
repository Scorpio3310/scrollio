//
//  ApplicationRing.swift
//  Scrollio
//
//  A Shortcut Ring of an app's own: what an app's entry on the per-app list stores about
//  the ring, the switch "Use the general ring" of the app's page, and which ring opens
//  for the app in front.
//
//  An app has a whole ring of its own or none: eight places and "Freeze pointer while the
//  ring is held", everything of the Shortcut Ring pane but what opens the ring. What opens
//  the ring is a binding, of Buttons or of the app's own buttons (`ApplicationButtons`),
//  and whichever opened it, the ring is the one of the app in front: its own, else the
//  general one.
//
//  Stored with the app's entry, under "ring":
//
//      {"path": …, "inherit": true, "scroll": {…},
//       "ring": {"inherit": false, "places": [{"action": "copy"}, {"action": ""}, …],
//                "freezePointer": false}}
//
//  - No "ring" (every entry from before the ring could be an app's): the app uses the
//    general ring. Such an entry is stored as before: nothing is added to it until the
//    switch is first turned off.
//  - "inherit" true: "Use the general ring" is on; the places are kept for later and not
//    used (as an app's "scroll" is kept while its "inherit" is on). Missing or unreadable:
//    true.
//  - "places" is read as the general ring's list is: place by place, one that cannot be
//    read is empty, a short list is filled up and a long one cut. A "ring" without a list
//    of places is not a ring: the entry reads as one without "ring".
//  - "freezePointer" is written once the ring has it: a ring the switch makes copies it
//    from the general ring, as it copies the places. A ring from before it was an app's
//    has none, and one that is missing or no switch is the general ring's, whatever it is
//    at the time: such a ring was held with the general switch until now and goes on so,
//    until the app's page sets one. Such a ring is written as before.
//  Do not rename the keys. Whether the ring was filled from the app's suggested shortcuts
//  is not stored (`startedFromSuggestion`).
//

import Cocoa

/// What an app's entry stores about the Shortcut Ring.
struct ApplicationRing: Codable, Equatable {

    /// "Use the general ring". On: `places` are kept and not used.
    var inherit: Bool
    /// Always `ShortcutRingSettings.placeCount` places.
    private(set) var places: [ShortcutRingPlace]
    /// "Freeze pointer while the ring is held", the app's own; nil: the general ring's (a
    /// ring from before it was an app's, or a value that cannot be read).
    var freezePointer: Bool?
    /// The places were filled from the app's suggested shortcuts (`ShortcutRingSuggestions`:
    /// the switch made the ring with them, or "Reset to Defaults" put them back), whatever
    /// was changed since. Known while the app runs, for the line of the app's Shortcut Ring
    /// part; not stored and not compared (a ring read from the settings or a settings file
    /// does not know it, and its line then goes by what the places are).
    var startedFromSuggestion = false

    init(
        inherit: Bool, places: [ShortcutRingPlace], freezePointer: Bool? = nil, startedFromSuggestion: Bool = false
    ) {
        self.inherit = inherit
        self.places = ShortcutRingSettings.filledUp(places)
        self.freezePointer = freezePointer
        self.startedFromSuggestion = startedFromSuggestion
    }

    /// The stored part: the switch, the places and the freeze switch.
    static func == (a: ApplicationRing, b: ApplicationRing) -> Bool {
        return a.inherit == b.inherit && a.places == b.places && a.freezePointer == b.freezePointer
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

    private enum CodingKeys: String, CodingKey {
        case inherit, places, freezePointer
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let stored = try c.decode([ShortcutRingSettings.ReadablePlace].self, forKey: .places)
        let inherits = ((try? c.decodeIfPresent(Bool.self, forKey: .inherit)) ?? nil) ?? true
        let freezes = (try? c.decodeIfPresent(Bool.self, forKey: .freezePointer)) ?? nil
        self.init(inherit: inherits, places: stored.map { $0.place }, freezePointer: freezes)
    }

    /// A ring without its own freeze switch is written as before.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(inherit, forKey: .inherit)
        try c.encode(places, forKey: .places)
        try c.encodeIfPresent(freezePointer, forKey: .freezePointer)
    }
}

// MARK: - "Use the general ring"

extension Application {

    /// "Use the general ring" of the app's page: on for an app that never had a ring of
    /// its own, and for one whose own ring is switched off.
    var usesGeneralRing: Bool {
        return ring?.inherit ?? true
    }

    /// The places of the app's own ring while it is in use; nil while the app uses the
    /// general ring.
    var ownRingPlaces: [ShortcutRingPlace]? {
        guard let ring, !ring.inherit else { return nil }
        return ring.places
    }

    /// The ring that opens while the app is in front: its own places and freeze switch
    /// (the general ring's while it has none), or the general ring.
    func ringThatOpens(general: ShortcutRingSettings) -> ShortcutRingSettings {
        guard let ring, !ring.inherit else { return general }
        return ShortcutRingSettings(places: ring.places, freezePointer: ring.freezePointer ?? general.freezePointer)
    }

    /// Off: the app's own ring, which starts as the app's suggested shortcuts when
    /// `suggested` has them (`ShortcutRingSuggestions`), else as a copy of `general`'s
    /// places as they are now, with `general`'s freeze switch either way, when the app
    /// never had one; one it had before comes back as it was left.
    /// On: the app's own ring stays stored for later and is not used. As "Use settings from
    /// Scrolling" does it (`setUsesScrollingSettings`). Nothing happens when the app is
    /// already in that state.
    func setUsesGeneralRing(_ uses: Bool, general: ShortcutRingSettings, suggested: [ShortcutRingPlace]? = nil) {
        guard usesGeneralRing != uses else { return }
        if var own = ring {
            own.inherit = uses
            ring = own
        } else {
            ring = ApplicationRing(
                inherit: false, places: suggested ?? general.places, freezePointer: general.freezePointer,
                startedFromSuggestion: suggested != nil
            )
        }
    }

    /// Puts `places` into the app's own ring, in use or kept for later; "Use the general
    /// ring" and the freeze switch stay as they are. Nothing happens for an app without a
    /// ring of its own. `startedFromSuggestion`: whether they are the app's suggested
    /// shortcuts (nil: as the ring was).
    func setOwnRingPlaces(_ places: [ShortcutRingPlace], startedFromSuggestion: Bool? = nil) {
        guard let own = ring else { return }
        ring = ApplicationRing(
            inherit: own.inherit, places: places, freezePointer: own.freezePointer,
            startedFromSuggestion: startedFromSuggestion ?? own.startedFromSuggestion
        )
    }

    /// Puts `places` and `freezePointer` into the app's own ring, in use or kept for later;
    /// "Use the general ring" stays as it is ("Reset to Defaults" of the app's page and its
    /// Undo). `startedFromSuggestion`: whether the places are the app's suggested shortcuts
    /// (nil: as the ring was). Nothing happens for an app without a ring of its own, or when
    /// nothing changes.
    func replaceOwnRing(places: [ShortcutRingPlace], freezePointer: Bool?, startedFromSuggestion: Bool? = nil) {
        guard let own = ring else { return }
        let replaced = ApplicationRing(
            inherit: own.inherit, places: places, freezePointer: freezePointer,
            startedFromSuggestion: startedFromSuggestion ?? own.startedFromSuggestion
        )
        guard replaced != own || replaced.startedFromSuggestion != own.startedFromSuggestion else { return }
        ring = replaced
    }

    /// "Freeze pointer while the ring is held" of the app's own ring while it is in use
    /// (its row on the app's page). Nothing happens while the app uses the general ring,
    /// or when nothing changes.
    func setOwnRingFreezePointer(_ freezes: Bool) {
        guard var own = ring, !own.inherit, own.freezePointer != freezes else { return }
        own.freezePointer = freezes
        ring = own
    }
}

// MARK: - Which ring opens

/// The ring that opens at a press of the ring's button or key: the app in front decides
/// (a shortcut goes to the app in front, not to the one under the pointer).
struct ShortcutRingChoice: Equatable {

    let ring: ShortcutRingSettings
    /// The ring is the own one of the app in front (for the log, which never names an app).
    let isAppsOwn: Bool
    /// The stored path of that app's entry, for its icon in the ring's middle (looked up
    /// among the icons made at a quiet moment, never on disk); nil for the general ring.
    /// Never written to the log.
    let appPath: String?

    init(ring: ShortcutRingSettings, isAppsOwn: Bool, appPath: String? = nil) {
        self.ring = ring
        self.isAppsOwn = isAppsOwn
        self.appPath = isAppsOwn ? appPath : nil
    }

    /// The app in front, as far as the choice needs it.
    struct FrontApp: Equatable {
        var bundlePath: String?
        var executablePath: String?
        /// Scrollio itself (its Settings are in front): always the general ring.
        var isScrollio = false

        /// The app in front now. Read when the ring's trigger goes down, inside the event
        /// callback: what `NSWorkspace` and the running app already hold, as the scroll
        /// path reads it for every wheel event; nothing on disk, no Launch Services query.
        static func current(
            _ application: NSRunningApplication? = NSWorkspace.shared.frontmostApplication
        ) -> FrontApp? {
            guard let application else { return nil }
            return FrontApp(
                bundlePath: application.bundleURL?.path,
                executablePath: application.executableURL?.path,
                isScrollio: application.processIdentifier == ProcessInfo.processInfo.processIdentifier
            )
        }
    }

    static func general(_ ring: ShortcutRingSettings) -> ShortcutRingChoice {
        return ShortcutRingChoice(ring: ring, isAppsOwn: false)
    }

    /// Pure: the app in front, the per-app list and the general ring give the ring.
    /// The app's entry is found as the scroll engine finds it
    /// (`ScrollUtils.getTargetApplication`): by the bundle's path, then by the program's.
    /// No app in front, Scrollio itself, an app that is not on the list and one that uses
    /// the general ring all get the general ring.
    static func make(
        front: FrontApp?, applications: EnhanceArray<Application>, general: ShortcutRingSettings
    ) -> ShortcutRingChoice {
        guard let front, !front.isScrollio,
              let entry = applications.get(by: front.bundlePath) ?? applications.get(by: front.executablePath),
              entry.ownRingPlaces != nil else { return .general(general) }
        return ShortcutRingChoice(ring: entry.ringThatOpens(general: general), isAppsOwn: true, appPath: entry.path)
    }
}
