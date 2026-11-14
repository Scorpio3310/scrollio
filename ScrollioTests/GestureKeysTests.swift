//
//  GestureKeysTests.swift
//  ScrollioTests
//
//  A direction of Gesture Navigation, and its click, can run a key combination the user
//  recorded, with a name and an icon, as a place of the Shortcut Ring can: how it is
//  stored (`GestureActions`), what the Gestures pane offers and shows, and how a gesture
//  runs it and says so in the log. The settings file's part is in `SettingsFileTests`.
//

import XCTest
@testable import Scrollio_Debug

/// ⇧⌘R, as the recorder stores it.
private let shiftCommandR = "custom::15:1179648"
private let shiftCommand = UInt64(CGEventFlags.maskShift.rawValue | CGEventFlags.maskCommand.rawValue)

private func label(_ name: String?, symbol: String? = nil, character: String? = nil) -> ShortcutLabel? {
    let icon: ShortcutLabel.Icon? = symbol.map { .symbol($0) } ?? character.map { .character($0) }
    return ShortcutLabel(name: name, icon: icon)
}

private func json<Value: Encodable>(_ value: Value) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}

private func decoded<Value: Decodable>(_ type: Value.Type, _ text: String) throws -> Value {
    return try JSONDecoder().decode(type, from: Data(text.utf8))
}

// MARK: - Storage

final class GestureActionsStorageTests: XCTestCase {

    /// An entry as every version before wrote it (the keys in the order they were
    /// written, a recorded combination in it as a newer build could leave one).
    private let oldEntry = #"{"upAction":"missionControl","downAction":"custom::15:1179648","leftAction":"","#
        + #""rightAction":"moveSpaceRight","clickAction":"missionControl","invertHorizontal":true,"freezePointer":false,"#
        + #""mode":"discrete","trackingSpeed":1.5,"deviceTracking":false,"hapticFeedback":true}"#

    /// An entry from before reads as it did and is written back unchanged: the same
    /// keys, the same values, and no label key.
    func testAnEntryFromBeforeReadsAndIsWrittenBackUnchanged() throws {
        let settings = try decoded(MouseGestureSettings.self, oldEntry)
        XCTAssertEqual(settings.downAction, shiftCommandR)
        XCTAssertNil(settings.actions.down.label)
        XCTAssertEqual(settings.leftAction, "")
        XCTAssertTrue(settings.invertHorizontal)
        XCTAssertEqual(settings.trackingSpeed, 1.5)

        let old = try JSONSerialization.jsonObject(with: Data(oldEntry.utf8)) as? NSDictionary
        let written = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? NSDictionary
        XCTAssertEqual(written, old, "the app's own encoder writes back what was there")
        let sortedOld = try JSONSerialization.data(
            withJSONObject: try JSONSerialization.jsonObject(with: Data(oldEntry.utf8)), options: [.sortedKeys]
        )
        XCTAssertEqual(try json(settings), String(decoding: sortedOld, as: UTF8.self))

        // The defaults hold no label either.
        XCTAssertFalse(try json(MouseGestureSettings.default).contains("Label"))
        // A partial entry still takes the default actions.
        XCTAssertEqual(try decoded(MouseGestureSettings.self, #"{"upAction":"copy"}"#).actions.down, GestureAction(SystemShortcut.appExpose))
    }

    /// A direction's name and icon are stored beside its action, and come back.
    func testANameAndAnIconComeBackForADirectionAndTheClick() throws {
        var settings = MouseGestureSettings.default
        settings.actions.up = GestureAction(action: shiftCommandR, label: label("Reload", symbol: "arrow.clockwise"))
        settings.actions.click = GestureAction(action: shiftCommandR, label: label(nil, character: "R"))
        let stored = try json(settings)
        XCTAssertTrue(stored.contains(#""upAction":"custom::15:1179648","upLabel":{"name":"Reload","symbol":"arrow.clockwise"}"#), stored)
        XCTAssertTrue(stored.contains(#""clickAction":"custom::15:1179648","clickLabel":{"character":"R"}"#), stored)
        XCTAssertFalse(stored.contains("downLabel"))

        let back = try decoded(MouseGestureSettings.self, stored)
        XCTAssertEqual(back, settings)
        XCTAssertEqual(back.actions.up.label?.name, "Reload")
        XCTAssertEqual(back.actions.up.keys, GestureAction.Keys(code: 15, modifiers: shiftCommand), "the keys are what they were")
        XCTAssertEqual(back.actions.click.label?.icon, .character("R"))

        // The set by itself is what an app could hold as its own.
        let set = try json(settings.actions)
        XCTAssertEqual(try decoded(GestureActions.self, set), settings.actions)
        XCTAssertEqual(try json(GestureActions.default),
                       #"{"clickAction":"missionControl","downAction":"appExpose","leftAction":"moveSpaceLeft","#
                        + #""rightAction":"moveSpaceRight","upAction":"missionControl"}"#)
    }

    /// An older version reads an entry by its action keys alone: the keys come through,
    /// the labels are not seen.
    func testAnOlderVersionStillReadsTheActionsOfANamedEntry() throws {
        struct EntryBeforeNames: Decodable {
            let upAction: String
            let downAction: String
            let clickAction: String
        }
        var settings = MouseGestureSettings.default
        settings.actions.up = GestureAction(action: shiftCommandR, label: label("Reload", symbol: "arrow.clockwise"))
        let old = try decoded(EntryBeforeNames.self, try json(settings))
        XCTAssertEqual(old.upAction, shiftCommandR)
        XCTAssertEqual(old.downAction, SystemShortcut.appExpose.identifier)
    }

    /// Only a recorded key combination keeps a label: a listed action, a click and no
    /// action never do, however they were stored; another action drops it, the same keys
    /// keep it.
    func testAnActionThatIsNoKeyCombinationDropsALabel() throws {
        let reload = label("Reload", symbol: "arrow.clockwise")
        for action in ["copy", "missionControl", "mouseBackClick", "", "custom::mouse:5:0"] {
            XCTAssertNil(GestureAction(action: action, label: reload).label, action)
        }
        let entry = try decoded(MouseGestureSettings.self, #"{"downAction":"copy","downLabel":{"name":"Paste"},"upLabel":7}"#)
        XCTAssertEqual(entry.actions.down, GestureAction(SystemShortcut.copy))
        XCTAssertEqual(entry.actions.up, GestureAction(SystemShortcut.missionControl), "a label that cannot be read is none")
        XCTAssertFalse(try json(entry).contains("Label"))

        var settings = MouseGestureSettings.default
        settings.actions.up = GestureAction(action: shiftCommandR, label: reload)
        settings.upAction = shiftCommandR
        XCTAssertEqual(settings.actions.up.label, reload, "the same keys keep their name")
        settings.upAction = SystemShortcut.copy.identifier
        XCTAssertNil(settings.actions.up.label)
        XCTAssertEqual(try decoded(MouseGestureSettings.self, try json(settings)).actions.up, GestureAction(SystemShortcut.copy))
    }
}

