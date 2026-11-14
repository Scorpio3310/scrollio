//
//  ApplicationRing.swift
//  Scrollio
//
//  A Shortcut Ring of an app's own: what an app's entry on the per-app list stores about
//  the ring, the switch "Use the general ring" of the app's page, and which ring opens
//  for the app in front.
//
//  An app has a whole ring of its own or none: eight places and nothing else. What opens
//  the ring is a binding, of Buttons or of the app's own buttons (`ApplicationButtons`),
//  and whichever opened it, the ring is the one of the app in front: its own, else the
//  general one. "Freeze pointer while the ring is held" is the general ring's for every
//  app.
//
//  Stored with the app's entry, under "ring":
//
//      {"path": …, "inherit": true, "scroll": {…},
//       "ring": {"inherit": false, "places": [{"action": "copy"}, {"action": ""}, …]}}
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
//  Do not rename the keys.
//

import Cocoa

/// What an app's entry stores about the Shortcut Ring.
struct ApplicationRing: Codable, Equatable {

    /// "Use the general ring". On: `places` are kept and not used.
    var inherit: Bool
    /// Always `ShortcutRingSettings.placeCount` places.
    private(set) var places: [ShortcutRingPlace]

    init(inherit: Bool, places: [ShortcutRingPlace]) {
        self.inherit = inherit
        self.places = ShortcutRingSettings.filledUp(places)
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
        case inherit, places
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let stored = try c.decode([ShortcutRingSettings.ReadablePlace].self, forKey: .places)
        let inherits = ((try? c.decodeIfPresent(Bool.self, forKey: .inherit)) ?? nil) ?? true
        self.init(inherit: inherits, places: stored.map { $0.place })
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

    /// The ring that opens while the app is in front: its own places, or the general
    /// ring. The pointer's freeze is the general ring's either way.
    func ringThatOpens(general: ShortcutRingSettings) -> ShortcutRingSettings {
        guard let places = ownRingPlaces else { return general }
        return ShortcutRingSettings(places: places, freezePointer: general.freezePointer)
    }

    /// Off: the app's own ring, which starts as a copy of `general` as it is now when the
    /// app never had one; one it had before comes back as it was left. On: the app's own
    /// ring stays stored for later and is not used. As "Use settings from Scrolling" does
    /// it (`setUsesScrollingSettings`). Nothing happens when the app is already in that
    /// state.
    func setUsesGeneralRing(_ uses: Bool, general: ShortcutRingSettings) {
        guard usesGeneralRing != uses else { return }
        if var own = ring {
            own.inherit = uses
            ring = own
        } else {
            ring = ApplicationRing(inherit: false, places: general.places)
        }
    }
}

// MARK: - Which ring opens

/// The ring that opens at a press of the ring's button or key: the app in front decides
/// (a shortcut goes to the app in front, not to the one under the pointer).
struct ShortcutRingChoice: Equatable {

    let ring: ShortcutRingSettings
    /// The ring is the own one of the app in front (for the log, which never names an app).
    let isAppsOwn: Bool

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
        return ShortcutRingChoice(ring: entry.ringThatOpens(general: general), isAppsOwn: true)
    }
}
