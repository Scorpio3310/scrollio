//
//  ApplicationGestures.swift
//  Scrollio
//
//  Gestures of an app's own: what an app's entry on the per-app list stores about Gesture
//  Navigation, the switch "Use the general gestures" of the app's page, and which gesture
//  settings a hold begins with for the app in front.
//
//  An app has a whole set of its own or none: everything of the Gestures pane but the
//  button to hold. The five actions (each direction and the click, a recorded key
//  combination with its name and icon), "Invert left and right", the mode (one action per
//  hold or follow the hand), the swipe speed, "Freeze pointer during a gesture" and what a
//  Logitech mouse does ("Let the mouse track the gesture", "Pulse when a gesture locks
//  in"). The button that runs Gesture Navigation is a binding, of Buttons or of the app's
//  own buttons (`ApplicationButtons`); whichever started a hold, it runs the set of the
//  app in front: its own, else the general one.
//
//  Stored with the app's entry, under "gestures", in the names of the general gesture
//  settings (`GestureActions`, `MouseGestureSettings`):
//
//      {"path": …, "inherit": true, "scroll": {…},
//       "gestures": {"inherit": false, "upAction": "custom::15:1179648", "upLabel": {…},
//                    "downAction": "appExpose", "leftAction": "navigateBack", "rightAction": …,
//                    "clickAction": "missionControl", "invertHorizontal": false,
//                    "mode": "discrete", "trackingSpeed": 1, "freezePointer": true,
//                    "deviceTracking": false, "hapticFeedback": true}}
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
//  - "mode", "trackingSpeed", "freezePointer", "deviceTracking" and "hapticFeedback" are
//    written once the set has them: a set the switch makes copies them from the general
//    gestures, as it copies the actions. A set from before they were an app's has none,
//    and one that is missing (or cannot be read: a mode this version does not know, a
//    speed that is no number) is the general value, whatever it is at the time: such a
//    set ran the general ones until now and goes on doing so, until the app's page sets
//    one. Such a set is written as before. A speed is kept in the general range.
//  Do not rename the keys.
//

import Foundation

/// What an app's entry stores about Gesture Navigation.
struct ApplicationGestures: Codable, Equatable {

    /// "Use the general gestures". On: the set is kept and not used.
    var inherit: Bool
    var actions: GestureActions
    var invertHorizontal: Bool
    /// The rest of the Gestures pane, the app's own; nil: the general value counts (a set
    /// from before these were an app's, or a value that cannot be read).
    var mode: MouseGestureMode?
    /// Kept in `MouseGestureSettings.trackingSpeedRange`.
    var trackingSpeed: Double? {
        didSet { trackingSpeed = trackingSpeed.map(MouseGestureSettings.clampedTrackingSpeed) }
    }
    var freezePointer: Bool?
    var deviceTracking: Bool?
    var hapticFeedback: Bool?

    init(inherit: Bool, actions: GestureActions, invertHorizontal: Bool) {
        self.inherit = inherit
        self.actions = actions
        self.invertHorizontal = invertHorizontal
    }

    /// A set that is a copy of `general`, all of it: what the switch starts with, and
    /// where "Reset to Defaults" of the app's page takes the set.
    init(inherit: Bool, copying general: MouseGestureSettings) {
        self.init(inherit: inherit, actions: general.actions, invertHorizontal: general.invertHorizontal)
        mode = general.mode
        trackingSpeed = general.trackingSpeed
        freezePointer = general.freezePointer
        deviceTracking = general.deviceTracking
        hapticFeedback = general.hapticFeedback
    }

    /// `general` with this set in it: the five actions and the invert switch, and every
    /// other value the set has (a missing one stays the general one).
    func settings(over general: MouseGestureSettings) -> MouseGestureSettings {
        var settings = general
        settings.actions = actions
        settings.invertHorizontal = invertHorizontal
        if let mode { settings.mode = mode }
        if let trackingSpeed { settings.trackingSpeed = trackingSpeed }
        if let freezePointer { settings.freezePointer = freezePointer }
        if let deviceTracking { settings.deviceTracking = deviceTracking }
        if let hapticFeedback { settings.hapticFeedback = hapticFeedback }
        return settings
    }

    private enum CodingKeys: String, CodingKey {
        case inherit, invertHorizontal, mode, trackingSpeed, freezePointer, deviceTracking, hapticFeedback
    }

    init(from decoder: Decoder) throws {
        // The actions are keys of this same object, read as the general entry's are.
        actions = try GestureActions(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        inherit = ((try? c.decodeIfPresent(Bool.self, forKey: .inherit)) ?? nil) ?? true
        invertHorizontal = ((try? c.decodeIfPresent(Bool.self, forKey: .invertHorizontal)) ?? nil) ?? false
        // One value that cannot be read is the general one; it never takes the set with it.
        mode = ((try? c.decodeIfPresent(String.self, forKey: .mode)) ?? nil).flatMap(MouseGestureMode.init(rawValue:))
        trackingSpeed = ((try? c.decodeIfPresent(Double.self, forKey: .trackingSpeed)) ?? nil)
            .map(MouseGestureSettings.clampedTrackingSpeed)
        freezePointer = (try? c.decodeIfPresent(Bool.self, forKey: .freezePointer)) ?? nil
        deviceTracking = (try? c.decodeIfPresent(Bool.self, forKey: .deviceTracking)) ?? nil
        hapticFeedback = (try? c.decodeIfPresent(Bool.self, forKey: .hapticFeedback)) ?? nil
    }

    /// A set without the values of the pane's rest is written as before.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(inherit, forKey: .inherit)
        try actions.encode(to: encoder)
        try c.encode(invertHorizontal, forKey: .invertHorizontal)
        try c.encodeIfPresent(mode, forKey: .mode)
        try c.encodeIfPresent(trackingSpeed, forKey: .trackingSpeed)
        try c.encodeIfPresent(freezePointer, forKey: .freezePointer)
        try c.encodeIfPresent(deviceTracking, forKey: .deviceTracking)
        try c.encodeIfPresent(hapticFeedback, forKey: .hapticFeedback)
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
    /// the app's own set in it (`ApplicationGestures.settings(over:)`), or `general`
    /// itself. The button to hold is a binding either way.
    func gesturesThatRun(general: MouseGestureSettings) -> MouseGestureSettings {
        return ownGestures?.settings(over: general) ?? general
    }

    /// Off: the app's own set, which starts as a copy of `general` as it is now (all of
    /// it) when the app never had one; one it had before comes back as it was left. On:
    /// the app's own set stays stored for later and is not used. As "Use the general ring"
    /// does it (`setUsesGeneralRing`). Nothing happens when the app is already in that
    /// state.
    func setUsesGeneralGestures(_ uses: Bool, general: MouseGestureSettings) {
        guard usesGeneralGestures != uses else { return }
        if var own = gestures {
            own.inherit = uses
            gestures = own
        } else {
            gestures = ApplicationGestures(inherit: false, copying: general)
        }
    }

    /// Changes the app's own set while it is in use (the rows of the app's page). Nothing
    /// happens while the app uses the general gestures, or when nothing changes.
    func setOwnGestures(actions: GestureActions, invertHorizontal: Bool) {
        changeOwnGestures { own in
            own.actions = actions
            own.invertHorizontal = invertHorizontal
        }
    }

    /// Changes values of the app's own set while it is in use (a row of the app's page):
    /// what `change` sets becomes the app's own, the rest stays as it is. Nothing happens
    /// while the app uses the general gestures, or when nothing changes.
    func changeOwnGestures(_ change: (inout ApplicationGestures) -> Void) {
        guard var own = ownGestures else { return }
        let before = own
        change(&own)
        guard own != before else { return }
        gestures = own
    }

    /// Puts `set` into the app's own set, in use or kept for later, all of it but the
    /// switch: "Use the general gestures" stays as it is (as `setOwnRingPlaces` for the
    /// ring: "Reset to Defaults" of the app's page and its Undo). Nothing happens for an app
    /// without a set of its own, or when nothing changes.
    func replaceOwnGestureSet(with set: ApplicationGestures) {
        guard let own = gestures else { return }
        var replaced = set
        replaced.inherit = own.inherit
        guard replaced != own else { return }
        gestures = replaced
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
