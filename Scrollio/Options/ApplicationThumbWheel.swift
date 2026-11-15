//
//  ApplicationThumbWheel.swift
//  Scrollio
//
//  The thumb wheel of an app's own: what a turn of the sideways wheel does while the app
//  is in front, and how. Two kinds of values, each where its part of the app's page keeps
//  it, as Scrolling › Thumb wheel and the Buttons pane's row share one function:
//
//  - The function: set in the app's Buttons part (its "Thumb wheel" row) and in the app's
//    Scrolling part (Thumb wheel › Action), one value. No switch governs it: it is the
//    app's own whatever "Use settings from Scrolling" says.
//  - Each function's Speed and "Reverse direction" and Switch Desktops' "Follow the
//    wheel": values of the app's own Scrolling settings, used while "Use settings from
//    Scrolling" is off and kept for later while it is on, as the app's other scroll values
//    (`ApplicationThumbWheelScrolling`).
//
//  The function is stored with the app's entry, under "thumbWheel", in the name of the
//  general thumb wheel settings (`ThumbWheelSettings`), only while the app has a function
//  of its own; the speeds, the reverses and the follow switch inside the app's "scroll",
//  under "thumbWheel", in the same names, only once the app has them:
//
//      {"path": …, "inherit": false,
//       "scroll": {…, "thumbWheel": {"speed": 1.5, "swapsDirection": true}},
//       "thumbWheel": {"function": "zoom"}}
//
//  ("speed" alone while every function has the same Speed, as an entry from before stores
//  it: it gives every function that speed. Once they differ, "speeds": {"<function>":
//  Double, …} with every function's, and "speed" stays beside it for a build from before:
//  the speed of the function the app ran when its page last set them. "swapsDirection"
//  when every function has the same "Reverse direction", else "reverseDirection":
//  {"<function>": Bool, …}; "followsWheel" once the app has it.)
//
//  - No "thumbWheel" (every entry from before an app could have one, and every app whose
//    row was taken away with "−"): the wheel does what Buttons and Scrolling say. Such an
//    entry is stored as before.
//  - A "thumbWheel" that cannot be read (no object, no "function" text) is none, and does
//    not take the entry with it. A function this version does not know (a later version's)
//    is kept as stored and not used: the app then turns the wheel as Buttons says, and the
//    name is there again for the version that wrote it. Version 1.0.5 ignores the key.
//  - No "thumbWheel" in "scroll" (every entry from before), or a name missing in it: that
//    value is the general one, as it is now, also while the app's own settings are in
//    use. Such an app turns the wheel exactly as it did before these values existed, and
//    a change in Scrolling › Thumb wheel still reaches it; nothing is stored for it until
//    the app's page changes the value, or "Use settings from Scrolling" is turned off
//    (which copies the values the wheel runs with then). A value that cannot be read is a
//    missing one. Version 1.0.5 ignores the key (and drops it when it saves the list).
//  Do not rename the keys.
//
//  What a turn runs (`ThumbWheelChoice`): the app in front at the turn's first event
//  decides, as for a button (the keys of zoom, tabs and back / forward go to the app in
//  front, not to the one under the pointer); the turn keeps that app's function, speeds,
//  reverses and follow switch until the wheel rests (`ThumbWheelEngine`). An app that has
//  a function of its own and no speeds of its own (it uses the Scrolling settings, or its
//  own date from before) runs it at Scrolling › Thumb wheel's Speed of that function.
//

import Foundation

/// What an app's entry stores about the thumb wheel.
struct ApplicationThumbWheel: Codable, Equatable {

    /// The function while the app is in front; nil for a name this version does not know.
    let function: ThumbWheelFunction?
    /// The name as stored, written back as it was.
    private let storedName: String

    init(function: ThumbWheelFunction) {
        self.function = function
        storedName = function.rawValue
    }

    private enum CodingKeys: String, CodingKey {
        case function
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        storedName = try c.decode(String.self, forKey: .function)
        function = ThumbWheelFunction(rawValue: storedName)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(storedName, forKey: .function)
    }
}

/// Each function's Speed and "Reverse direction" and Switch Desktops' "Follow the wheel" of
/// an app's own Scrolling settings (inside the app's "scroll"). Each nil: the general value
/// (missing, or not readable).
struct ApplicationThumbWheelScrolling: Codable, Equatable {

    /// Each inside `ThumbWheelSettings.speedRange`.
    var speeds: ThumbWheelSpeeds?
    var reverses: ThumbWheelReversal?
    var followsWheel: Bool?
    /// The function whose speed is written as the single "speed" while the speeds differ,
    /// for a build from before each function had its own: the one the app ran when its
    /// page last set the values. Not a value of the app's (`==` does not look at it).
    private var singleSpeedFunction: ThumbWheelFunction = .scroll

    init(speeds: ThumbWheelSpeeds?, reverses: ThumbWheelReversal?, followsWheel: Bool?) {
        self.speeds = speeds
        self.reverses = reverses
        self.followsWheel = followsWheel
    }

    /// What an app's settings take of `settings`: the speeds, the reverses, the follow
    /// switch.
    init(_ settings: ThumbWheelSettings) {
        self.init(speeds: settings.speeds, reverses: settings.reverses, followsWheel: settings.followsWheel)
        singleSpeedFunction = settings.function
    }

    /// What Scrolling › Thumb wheel's "Reset to Defaults" gives: 1× for every function,
    /// nothing reversed, desktops in steps.
    static let defaults = ApplicationThumbWheelScrolling(ThumbWheelSettings.default)

    static func == (a: ApplicationThumbWheelScrolling, b: ApplicationThumbWheelScrolling) -> Bool {
        return a.speeds == b.speeds && a.reverses == b.reverses && a.followsWheel == b.followsWheel
    }

    private enum CodingKeys: String, CodingKey {
        case speed, speeds, swapsDirection, reverseDirection, followsWheel
    }

    /// Never throws: what cannot be read is the general value, and the app's scroll
    /// settings around it are read as before. "speed" (one Speed for every function, as an
    /// entry from before stores it) gives every function without an entry of its own in
    /// "speeds" its value, and "swapsDirection" (one switch for every function) every
    /// function without one in "reverseDirection".
    init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else {
            self.init(speeds: nil, reverses: nil, followsWheel: nil)
            return
        }
        let speed = (try? c.decodeIfPresent(Double.self, forKey: .speed)) ?? nil
        let speedByName = (try? c.decodeIfPresent([String: Double].self, forKey: .speeds)) ?? nil
        let swaps = (try? c.decodeIfPresent(Bool.self, forKey: .swapsDirection)) ?? nil
        let byName = (try? c.decodeIfPresent([String: Bool].self, forKey: .reverseDirection)) ?? nil
        let speeds = speed == nil && speedByName == nil ? nil : ThumbWheelSpeeds(byName: speedByName, seed: speed)
        self.init(
            speeds: speeds,
            reverses: swaps == nil && byName == nil ? nil : ThumbWheelReversal(byName: byName, seed: swaps),
            followsWheel: (try? c.decodeIfPresent(Bool.self, forKey: .followsWheel)) ?? nil
        )
        // The single "speed" is written back as it was: any function with that speed says it.
        if let speeds, let speed {
            let stored = ThumbWheelSettings.clampedSpeed(speed)
            singleSpeedFunction = ThumbWheelFunction.allCases.first { speeds[$0] == stored } ?? .scroll
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let speeds {
            try c.encode(speeds[singleSpeedFunction], forKey: .speed)
            if !speeds.isUniform {
                var byName = c.nestedContainer(keyedBy: ThumbWheelReversal.FunctionNameKey.self, forKey: .speeds)
                try speeds.encode(into: &byName)
            }
        }
        if let reverses {
            if reverses.isUniform {
                try c.encode(reverses[.scroll], forKey: .swapsDirection)
            } else {
                var byName = c.nestedContainer(keyedBy: ThumbWheelReversal.FunctionNameKey.self, forKey: .reverseDirection)
                try reverses.encode(into: &byName)
            }
        }
        try c.encodeIfPresent(followsWheel, forKey: .followsWheel)
    }
}

/// What the app in front has of its own for a turn of the thumb wheel: its function, and
/// while its own Scrolling settings are in use its speeds, reverses and follow switch. Each
/// nil: the general one, read at every event as it always was.
struct ThumbWheelOwn: Equatable {
    var function: ThumbWheelFunction?
    var speeds: ThumbWheelSpeeds?
    var reverses: ThumbWheelReversal?
    var followsWheel: Bool?

    init(function: ThumbWheelFunction? = nil, speeds: ThumbWheelSpeeds? = nil, reverses: ThumbWheelReversal? = nil, followsWheel: Bool? = nil) {
        self.function = function
        self.speeds = speeds
        self.reverses = reverses
        self.followsWheel = followsWheel
    }

    /// Nothing of its own: the general settings.
    var isNone: Bool {
        return function == nil && speeds == nil && reverses == nil && followsWheel == nil
    }

    /// The settings an event goes by: `general` with what is the app's own in it. Each
    /// function has a Speed and a "Reverse direction" of its own, so an own function runs
    /// at that function's speed and direction: the app's where it has speeds or reverses
    /// of its own, else the ones Scrolling › Thumb wheel has for that function. The follow
    /// switch is the general one or the app's.
    func settings(general: ThumbWheelSettings) -> ThumbWheelSettings {
        var settings = general
        if let function {
            settings.function = function
        }
        if let speeds {
            settings.speeds = speeds
        }
        if let reverses {
            settings.reverses = reverses
        }
        if let followsWheel {
            settings.followsWheel = followsWheel
        }
        return settings
    }
}

// MARK: - The app's entry

extension Application {

    /// What a turn of the thumb wheel does while the app is in front, when the app has a
    /// function of its own; nil: what Buttons (and Scrolling › Thumb wheel) say.
    var ownThumbWheelFunction: ThumbWheelFunction? {
        return thumbWheel?.function
    }

    /// What the app has of its own for the thumb wheel now: the function, and the speeds,
    /// reverses and follow switch only while "Use settings from Scrolling" is off. A look at
    /// the entry, nothing made: a turn's first event asks it.
    var ownThumbWheel: ThumbWheelOwn {
        let scrolling = inherit ? nil : scroll.thumbWheel
        return ThumbWheelOwn(
            function: ownThumbWheelFunction, speeds: scrolling?.speeds,
            reverses: scrolling?.reverses, followsWheel: scrolling?.followsWheel
        )
    }

    /// The settings a turn of the thumb wheel runs with while the app is in front (what its
    /// page shows): `general` with what is the app's own in it.
    func thumbWheelThatRuns(general: ThumbWheelSettings) -> ThumbWheelSettings {
        return ownThumbWheel.settings(general: general)
    }

    /// Gives the app's own Scrolling settings the thumb wheel speeds, reverses and follow
    /// switch of `settings` (the app's Scrolling part): all of them are stored, every
    /// function's, as its page shows them. Nothing happens when nothing changes.
    func setOwnThumbWheelScrolling(_ settings: ThumbWheelSettings) {
        let values = ApplicationThumbWheelScrolling(settings)
        guard scroll.thumbWheel != values else { return }
        scroll.thumbWheel = values
    }

    /// Before "Use settings from Scrolling" is switched off: an app whose own Scrolling
    /// settings have no thumb wheel values yet gets the speeds, reverses and follow switch
    /// the wheel runs with in it now (the general ones, every function's), so switching
    /// off changes nothing until the user does. Values it has are kept. Returns whether
    /// they were copied.
    @discardableResult
    func adoptThumbWheelScrollingIfNone(from general: ThumbWheelSettings) -> Bool {
        guard scroll.thumbWheel == nil else { return false }
        let running = ThumbWheelOwn(function: ownThumbWheelFunction).settings(general: general)
        scroll.thumbWheel = ApplicationThumbWheelScrolling(running)
        return true
    }

    /// The Buttons part of the app's page has something of the app's own: a button or key,
    /// or the thumb wheel (the mark in the list of apps).
    var hasOwnButtonsPart: Bool {
        return hasOwnButtons || ownThumbWheelFunction != nil
    }

    /// Gives the app a function of its own (its row), or with nil gives the thumb wheel back
    /// to Buttons: nothing is stored then, as for an entry from before. Nothing happens when
    /// nothing changes; a function this version does not know stays until another is set.
    func setOwnThumbWheelFunction(_ function: ThumbWheelFunction?) {
        guard ownThumbWheelFunction != function else { return }
        thumbWheel = function.map(ApplicationThumbWheel.init(function:))
    }

}

// MARK: - What a turn runs

/// Whose thumb wheel settings a turn runs. Pure: the engine and its tests share it.
enum ThumbWheelChoice {

    /// What the app in front has of its own (`Application.ownThumbWheel`); nil: nothing, the
    /// general settings. The app's entry is found as the buttons, the ring and the gestures
    /// find it (`ApplicationButtons.entry`: by the bundle's path, then by the program's): no
    /// app in front, Scrollio itself (its settings are in front: the wheel does what Buttons
    /// and Scrolling say, so they can be tried there), an app not on the list and one with
    /// nothing of its own get the general settings.
    ///
    /// Asked once per turn. While no app on the list has anything of its own (the common
    /// case) only the list is looked at, and `front` is never asked.
    static func own(
        front: () -> ShortcutRingChoice.FrontApp?, applications: EnhanceArray<Application>
    ) -> ThumbWheelOwn? {
        guard someApp(in: applications),
              let own = ApplicationButtons.entry(front: front(), applications: applications)?.ownThumbWheel,
              !own.isNone else { return nil }
        return own
    }

    /// Some app on the list has something of its own: a look at each entry, nothing made.
    private static func someApp(in applications: EnhanceArray<Application>) -> Bool {
        for index in 0..<applications.count {
            if let application = applications.get(by: index), !application.ownThumbWheel.isNone {
                return true
            }
        }
        return false
    }
}
