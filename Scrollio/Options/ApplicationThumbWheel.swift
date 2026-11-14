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
//  - The speed and "Swap direction": values of the app's own Scrolling settings, used while
//    "Use settings from Scrolling" is off and kept for later while it is on, as the app's
//    other scroll values (`ApplicationThumbWheelScrolling`).
//
//  The function is stored with the app's entry, under "thumbWheel", in the name of the
//  general thumb wheel settings (`ThumbWheelSettings`), only while the app has a function
//  of its own; the speed and the swap inside the app's "scroll", under "thumbWheel", in
//  the same names, only once the app has them:
//
//      {"path": …, "inherit": false,
//       "scroll": {…, "thumbWheel": {"speed": 1.5, "swapsDirection": true}},
//       "thumbWheel": {"function": "zoom"}}
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
//  front, not to the one under the pointer); the turn keeps that app's function, speed and
//  swap until the wheel rests (`ThumbWheelEngine`).
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

/// The thumb wheel's speed and "Swap direction" of an app's own Scrolling settings (inside
/// the app's "scroll"). Each nil: the general value (missing, or not readable).
struct ApplicationThumbWheelScrolling: Codable, Equatable {

    /// Inside `ThumbWheelSettings.speedRange`.
    var speed: Double? {
        didSet {
            if let speed, ThumbWheelSettings.clampedSpeed(speed) != speed {
                self.speed = ThumbWheelSettings.clampedSpeed(speed)
            }
        }
    }
    var swapsDirection: Bool?

    init(speed: Double?, swapsDirection: Bool?) {
        self.speed = speed.map(ThumbWheelSettings.clampedSpeed)
        self.swapsDirection = swapsDirection
    }

    /// What Scrolling › Thumb wheel's "Reset to Defaults" gives: 1×, not swapped.
    static let defaults = ApplicationThumbWheelScrolling(
        speed: ThumbWheelSettings.default.speed, swapsDirection: ThumbWheelSettings.default.swapsDirection
    )

    private enum CodingKeys: String, CodingKey {
        case speed, swapsDirection
    }

    /// Never throws: what cannot be read is the general value, and the app's scroll
    /// settings around it are read as before.
    init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else {
            self.init(speed: nil, swapsDirection: nil)
            return
        }
        self.init(
            speed: (try? c.decodeIfPresent(Double.self, forKey: .speed)) ?? nil,
            swapsDirection: (try? c.decodeIfPresent(Bool.self, forKey: .swapsDirection)) ?? nil
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(speed, forKey: .speed)
        try c.encodeIfPresent(swapsDirection, forKey: .swapsDirection)
    }
}

/// What the app in front has of its own for a turn of the thumb wheel: its function, and
/// while its own Scrolling settings are in use its speed and swap. Each nil: the general
/// one, read at every event as it always was.
struct ThumbWheelOwn: Equatable {
    var function: ThumbWheelFunction?
    var speed: Double?
    var swapsDirection: Bool?

    /// Nothing of its own: the general settings.
    var isNone: Bool {
        return function == nil && speed == nil && swapsDirection == nil
    }

    /// The settings an event goes by: `general` with what is the app's own in it. The
    /// general Speed is set for the general function (how far the wheel scrolls, or how
    /// soon the next step comes): an own function of the other kind runs at the default
    /// speed, unless the app has a speed of its own, which is set for its own function (the
    /// app's page shows both). Swap direction is the hand's: the general one, or the app's.
    func settings(general: ThumbWheelSettings) -> ThumbWheelSettings {
        var settings = general
        if let function, function != general.function {
            settings.function = function
            if (function == .scroll) != (general.function == .scroll) {
                settings.speed = ThumbWheelSettings.defaultSpeed
            }
        }
        if let speed {
            settings.speed = speed
        }
        if let swapsDirection {
            settings.swapsDirection = swapsDirection
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

    /// What the app has of its own for the thumb wheel now: the function, and the speed and
    /// swap only while "Use settings from Scrolling" is off. A look at the entry, nothing
    /// made: a turn's first event asks it.
    var ownThumbWheel: ThumbWheelOwn {
        let scrolling = inherit ? nil : scroll.thumbWheel
        return ThumbWheelOwn(function: ownThumbWheelFunction, speed: scrolling?.speed, swapsDirection: scrolling?.swapsDirection)
    }

    /// The settings a turn of the thumb wheel runs with while the app is in front (what its
    /// page shows): `general` with what is the app's own in it.
    func thumbWheelThatRuns(general: ThumbWheelSettings) -> ThumbWheelSettings {
        return ownThumbWheel.settings(general: general)
    }

    /// Gives the app's own Scrolling settings a thumb wheel speed and swap (the app's
    /// Scrolling part): both are stored, as its page shows them. Nothing happens when
    /// nothing changes.
    func setOwnThumbWheelScrolling(speed: Double, swapsDirection: Bool) {
        let values = ApplicationThumbWheelScrolling(speed: speed, swapsDirection: swapsDirection)
        guard scroll.thumbWheel != values else { return }
        scroll.thumbWheel = values
    }

    /// Before "Use settings from Scrolling" is switched off: an app whose own Scrolling
    /// settings have no thumb wheel values yet gets the speed and swap the wheel runs with
    /// in it now (`general`, with its own function), so switching off changes nothing until
    /// the user does. Values it has are kept. Returns whether they were copied.
    @discardableResult
    func adoptThumbWheelScrollingIfNone(from general: ThumbWheelSettings) -> Bool {
        guard scroll.thumbWheel == nil else { return false }
        let running = ThumbWheelOwn(function: ownThumbWheelFunction).settings(general: general)
        scroll.thumbWheel = ApplicationThumbWheelScrolling(speed: running.speed, swapsDirection: running.swapsDirection)
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
