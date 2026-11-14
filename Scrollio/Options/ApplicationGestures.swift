//
//  ApplicationGestures.swift
//  Scrollio
//
//  Gestures of an app's own: what an app's entry on the per-app list stores about Gesture
//  Navigation, the switch "Use the general gestures" of the app's page, and which gesture
//  settings a hold begins with for the app in front.
//
//  An app has a whole set of its own or none: the five actions (each direction and the
//  click, a recorded key combination with its name and icon) and "Invert left and right".
//  The button that runs Gesture Navigation is a binding, of Buttons or of the app's own
//  buttons (`ApplicationButtons`); whichever started a hold, it runs the set of the app in
//  front: its own, else the general one. The mode, the swipe speed, "Freeze pointer", the
//  mouse tracking the gesture and its haptic cues are the Gestures pane's for every app.
//
//  Stored with the app's entry, under "gestures", in the names of the general gesture
//  settings (`GestureActions`, `MouseGestureSettings`):
//
//      {"path": …, "inherit": true, "scroll": {…},
//       "gestures": {"inherit": false, "upAction": "custom::15:1179648", "upLabel": {…},
//                    "downAction": "appExpose", "leftAction": "navigateBack", "rightAction": …,
//                    "clickAction": "missionControl", "invertHorizontal": false}}
//
//  - No "gestures" (every entry from before an app could have gestures of its own): the
//    app uses the general gestures. Such an entry is stored as before: nothing is added to
//    it until the switch is first turned off.
//  - "inherit" true: "Use the general gestures" is on; the set is kept for later and not
//    used (as an app's "scroll" is kept while its "inherit" is on). Missing or unreadable:
//    true.
//  - The actions are read as the general ones are: a missing one is the default action, a
//    label that cannot be read is no label. "invertHorizontal" missing or unreadable: off.
//    A "gestures" that cannot be read (no object, an action that is no text) is no set:
//    the entry reads as one without "gestures".
//  Do not rename the keys.
//

import Foundation

/// What an app's entry stores about Gesture Navigation.
struct ApplicationGestures: Codable, Equatable {

    /// "Use the general gestures". On: the set is kept and not used.
    var inherit: Bool
    var actions: GestureActions
    var invertHorizontal: Bool

    init(inherit: Bool, actions: GestureActions, invertHorizontal: Bool) {
        self.inherit = inherit
        self.actions = actions
        self.invertHorizontal = invertHorizontal
    }

    private enum CodingKeys: String, CodingKey {
        case inherit, invertHorizontal
    }

    init(from decoder: Decoder) throws {
        // The actions are keys of this same object, read as the general entry's are.
        actions = try GestureActions(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        inherit = ((try? c.decodeIfPresent(Bool.self, forKey: .inherit)) ?? nil) ?? true
        invertHorizontal = ((try? c.decodeIfPresent(Bool.self, forKey: .invertHorizontal)) ?? nil) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(inherit, forKey: .inherit)
        try actions.encode(to: encoder)
        try c.encode(invertHorizontal, forKey: .invertHorizontal)
    }
}

// MARK: - "Use the general gestures"

extension Application {

    /// "Use the general gestures" of the app's page: on for an app that never had gestures
    /// of its own, and for one whose own set is switched off.
    var usesGeneralGestures: Bool {
        return gestures?.inherit ?? true
    }

    /// The app's own set while it is in use; nil while the app uses the general gestures.
    var ownGestures: ApplicationGestures? {
        guard let gestures, !gestures.inherit else { return nil }
        return gestures
    }

    /// The gesture settings a hold begins with while the app is in front: `general` with
    /// the app's five actions and its "Invert left and right" in it, or `general` itself.
    /// The button, the mode, the speed, the freeze and the mouse's options are the general
    /// ones either way.
    func gesturesThatRun(general: MouseGestureSettings) -> MouseGestureSettings {
        guard let own = ownGestures else { return general }
        var settings = general
        settings.actions = own.actions
        settings.invertHorizontal = own.invertHorizontal
        return settings
    }

    /// Off: the app's own set, which starts as a copy of the actions and the invert switch
    /// of `general` as they are now when the app never had one; one it had before comes
    /// back as it was left. On: the app's own set stays stored for later and is not used.
    /// As "Use the general ring" does it (`setUsesGeneralRing`). Nothing happens when the
    /// app is already in that state.
    func setUsesGeneralGestures(_ uses: Bool, general: MouseGestureSettings) {
        guard usesGeneralGestures != uses else { return }
        if var own = gestures {
            own.inherit = uses
            gestures = own
        } else {
            gestures = ApplicationGestures(inherit: false, actions: general.actions, invertHorizontal: general.invertHorizontal)
        }
    }

    /// Changes the app's own set while it is in use (the rows of the app's page). Nothing
    /// happens while the app uses the general gestures, or when nothing changes.
    func setOwnGestures(actions: GestureActions, invertHorizontal: Bool) {
        guard var own = ownGestures,
              own.actions != actions || own.invertHorizontal != invertHorizontal else { return }
        own.actions = actions
        own.invertHorizontal = invertHorizontal
        gestures = own
    }
}

// MARK: - Which gestures a hold runs

/// The gesture settings a hold of the gesture button begins with: the app in front decides
/// (an action goes to the app in front, not to the one under the pointer), at the press.
struct MouseGestureChoice: Equatable {

    let settings: MouseGestureSettings
    /// The set is the own one of the app in front (for the log, which never names an app).
    let isAppsOwn: Bool

    static func general(_ settings: MouseGestureSettings) -> MouseGestureChoice {
        return MouseGestureChoice(settings: settings, isAppsOwn: false)
    }

    /// Pure: the app in front, the per-app list and the general settings give the settings
    /// of the hold. The app's entry is found as the ring and an app's buttons find it
    /// (`ApplicationButtons.entry`: by the bundle's path, then by the program's). No app in
    /// front, Scrollio itself, an app that is not on the list and one that uses the general
    /// gestures all get the general settings.
    static func make(
        front: ShortcutRingChoice.FrontApp?, applications: EnhanceArray<Application>, general: MouseGestureSettings
    ) -> MouseGestureChoice {
        guard let entry = ApplicationButtons.entry(front: front, applications: applications),
              entry.ownGestures != nil else { return .general(general) }
        return MouseGestureChoice(settings: entry.gesturesThatRun(general: general), isAppsOwn: true)
    }
}
