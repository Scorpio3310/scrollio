//
//  PreferencesHistory.swift
//  Scrollio
//  The places a Settings window showed, in the order it showed them: what View › Back and
//  View › Forward step through. Pure, kept in memory by the window's
//  PreferencesSplitViewController and gone with it; nothing of it is stored or logged.
//

import Foundation

/// A place of the Settings window: a pane, or a page inside one (an app's page in Apps).
struct PreferencesPlace: Equatable {
    /// The pane's identifier (`PreferencesPane.identifier`).
    let pane: String
    /// The page open inside the pane, as the pane names it
    /// (`PreferencesPaneWithSubpage.subpageToken`: the open app's stored path); nil for the
    /// pane's first page. Never stored and never logged.
    let page: String?

    init(pane: String, page: String? = nil) {
        self.pane = pane
        self.page = page
    }

    /// The first page of this place's pane (Apps: the list).
    var list: PreferencesPlace {
        return PreferencesPlace(pane: pane)
    }
}

struct PreferencesHistory: Equatable {

    enum Direction: Int {
        case back = -1
        case forward = 1
    }

    /// The most places kept; older ones are forgotten first.
    static let limit = 100

    /// The places, oldest first. A page always has its pane's first page right before it.
    private(set) var places: [PreferencesPlace] = []
    /// Where in `places` the window is.
    private(set) var position = 0

    /// The place on show; nil before the first visit.
    var current: PreferencesPlace? {
        return places.indices.contains(position) ? places[position] : nil
    }

    /// The window shows `place` now, by anything but a step.
    ///
    /// The place on show again changes nothing. Leaving a page for its pane's first page,
    /// which is the entry before it, is one step back, so Forward opens the page again
    /// (the title bar's back button, Esc and the page's own ⌘[ all end here). Anything else
    /// drops what was ahead and adds the place; a page gets its pane's first page before
    /// it, so Back from a page is always that first page, also after a jump from elsewhere.
    mutating func visit(_ place: PreferencesPlace) {
        if let current {
            guard place != current else { return }
            if current.page != nil, place == current.list, position > 0, places[position - 1] == place {
                position -= 1
                return
            }
            places.removeSubrange((position + 1)...)
        }
        if place.page != nil, places.last != place.list {
            places.append(place.list)
        }
        places.append(place)
        // The oldest go first; a page never stands first (its way back would be gone).
        var dropped = max(0, places.count - Self.limit)
        while dropped > 0, dropped < places.count - 1, places[dropped].page != nil {
            dropped += 1
        }
        places.removeFirst(dropped)
        position = places.count - 1
    }

    /// Where a step that way ends: the nearest entry that still exists (`exists`: a page
    /// whose app left the list does not) and is not the place on show. Nil: no step that way.
    /// Entries are never deleted, so a page whose app comes back is found again.
    func destination(_ direction: Direction, exists: (PreferencesPlace) -> Bool) -> Int? {
        guard let current else { return nil }
        var index = position + direction.rawValue
        while places.indices.contains(index) {
            if places[index] != current, exists(places[index]) {
                return index
            }
            index += direction.rawValue
        }
        return nil
    }

    func canStep(_ direction: Direction, exists: (PreferencesPlace) -> Bool) -> Bool {
        return destination(direction, exists: exists) != nil
    }

    /// Steps that way and says which place to show; nil (and nothing changes) when there is
    /// none. What the window then shows is not visited again.
    mutating func step(_ direction: Direction, exists: (PreferencesPlace) -> Bool) -> PreferencesPlace? {
        guard let index = destination(direction, exists: exists) else { return nil }
        position = index
        return places[index]
    }
}
