//
//  ApplicationThumbWheel.swift
//  Scrollio
//
//  The thumb wheel of an app's own: what a turn of the sideways wheel does while the app
//  is in front, set in the app's Buttons part (its "Thumb wheel" row). Only the function:
//  the speed and "Swap direction" are those of Scrolling › Thumb wheel for every app.
//
//  Stored with the app's entry, under "thumbWheel", in the name of the general thumb wheel
//  settings (`ThumbWheelSettings`), only while the app has a function of its own:
//
//      {"path": …, "inherit": true, "scroll": {…}, "thumbWheel": {"function": "zoom"}}
//
//  - No "thumbWheel" (every entry from before an app could have one, and every app whose
//    row was taken away with "−"): the wheel does what Buttons and Scrolling say. Such an
//    entry is stored as before.
//  - A "thumbWheel" that cannot be read (no object, no "function" text) is none, and does
//    not take the entry with it. A function this version does not know (a later version's)
//    is kept as stored and not used: the app then turns the wheel as Buttons says, and the
//    name is there again for the version that wrote it. Version 1.0.5 ignores the key.
//  Do not rename the keys.
//
//  Which function a turn runs (`ThumbWheelChoice`): the app in front at the turn's first
//  event decides, as for a button (the keys of zoom, tabs and back / forward go to the app
//  in front, not to the one under the pointer); the turn keeps that app's function until
//  the wheel rests (`ThumbWheelEngine`).
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

// MARK: - The app's entry

extension Application {

    /// What a turn of the thumb wheel does while the app is in front, when the app has a
    /// function of its own; nil: what Buttons (and Scrolling › Thumb wheel) say.
    var ownThumbWheelFunction: ThumbWheelFunction? {
        return thumbWheel?.function
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

// MARK: - Which function a turn runs

/// Whose function a turn of the thumb wheel runs. Pure: the engine and its tests share it.
enum ThumbWheelChoice {

    /// The own function of the app in front; nil: the general function. The app's entry is
    /// found as the buttons, the ring and the gestures find it (`ApplicationButtons.entry`:
    /// by the bundle's path, then by the program's): no app in front, Scrollio itself (its
    /// settings are in front: the wheel does what Buttons says, so it can be tried there),
    /// an app not on the list and one without a function of its own get the general one.
    ///
    /// Asked once per turn. While no app on the list has a function of its own (the common
    /// case) only the list is looked at, and `front` is never asked.
    static func ownFunction(
        front: () -> ShortcutRingChoice.FrontApp?, applications: EnhanceArray<Application>
    ) -> ThumbWheelFunction? {
        guard someApp(in: applications) else { return nil }
        return ApplicationButtons.entry(front: front(), applications: applications)?.ownThumbWheelFunction
    }

    /// Some app on the list has a function of its own: a look at each entry, nothing made.
    private static func someApp(in applications: EnhanceArray<Application>) -> Bool {
        for index in 0..<applications.count where applications.get(by: index)?.ownThumbWheelFunction != nil {
            return true
        }
        return false
    }
}
