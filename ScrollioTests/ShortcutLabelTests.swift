//
//  ShortcutLabelTests.swift
//  ScrollioTests
//
//  A recorded key combination can carry a name and an icon (`ShortcutLabel`): how they
//  are stored with a place of the Shortcut Ring and with a button's binding, what the
//  ring and the rows of the panes show for them, how the recorder's popover sets them,
//  and that a settings file carries them.
//

import XCTest
@testable import Scrollio_Debug

/// ⇧⌘R, as the recorder stores it.
private let shiftCommandR = "custom::15:1179648"

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

final class ShortcutLabelStorageTests: XCTestCase {

    private let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, deviceFilter: nil)

    /// A binding as a version before names wrote it.
    private let oldBinding = """
        {"createdAt":721692000,"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","isEnabled":true,\
        "systemShortcutName":"custom::15:1179648","triggerEvent":{"code":3,"modifiers":0,"type":"mouse"}}
        """

    // MARK: A place

    /// A place from before names: it reads as it did, and what is written back is the
    /// same text.
    func testAPlaceFromBeforeReadsAndIsWrittenBackUnchanged() throws {
        let old = #"{"action":"custom::15:1179648"}"#
        let place = try decoded(ShortcutRingPlace.self, old)
        XCTAssertEqual(place.action, shiftCommandR)
        XCTAssertNil(place.label)
        XCTAssertEqual(place, ShortcutRingPlace(action: shiftCommandR))
        XCTAssertEqual(try json(place), old)
        // A whole ring, with a listed action and empty places beside it.
        let ring = #"{"freezePointer":true,"places":[{"action":"missionControl"},{"action":""},"#
            + #"{"action":"custom::15:1179648"},{"action":""},{"action":""},{"action":""},{"action":""},{"action":""}]}"#
        XCTAssertEqual(try json(try decoded(ShortcutRingSettings.self, ring)), ring)
    }

    func testANameAndAnIconComeBackForAPlace() throws {
        let named = ShortcutRingPlace(action: shiftCommandR, label: label("Reload", symbol: "arrow.clockwise"))
        let stored = try json(named)
        XCTAssertEqual(stored, #"{"action":"custom::15:1179648","label":{"name":"Reload","symbol":"arrow.clockwise"}}"#)
        let back = try decoded(ShortcutRingPlace.self, stored)
        XCTAssertEqual(back, named)
        XCTAssertEqual(back.label?.name, "Reload")
        XCTAssertEqual(back.label?.icon, .symbol("arrow.clockwise"))
        XCTAssertEqual(back.content, .keyCombination(code: 15, modifiers: 1_179_648), "the keys are what they were")

        let typed = ShortcutRingPlace(action: shiftCommandR, label: label(nil, character: "🔄"))
        XCTAssertEqual(try json(typed), #"{"action":"custom::15:1179648","label":{"character":"🔄"}}"#)
        XCTAssertEqual(try decoded(ShortcutRingPlace.self, try json(typed)), typed)

        let onlyName = ShortcutRingPlace(action: shiftCommandR, label: label("Reload"))
        XCTAssertEqual(try json(onlyName), #"{"action":"custom::15:1179648","label":{"name":"Reload"}}"#)
        XCTAssertNotEqual(onlyName, ShortcutRingPlace(action: shiftCommandR), "a name is a change of the place")
    }

    /// A version from before names reads a place by "action" and "openTarget" alone: the
    /// keys come through, the label is not seen.
    func testAnOlderVersionStillReadsTheKeysOfANamedPlace() throws {
        struct PlaceBeforeNames: Decodable {
            let action: String
            let openTarget: OpenTargetPayload?
        }
        let stored = try json(ShortcutRingPlace(action: shiftCommandR, label: label("Reload", symbol: "arrow.clockwise")))
        let old = try decoded(PlaceBeforeNames.self, stored)
        XCTAssertEqual(old.action, shiftCommandR)
        XCTAssertNil(old.openTarget)
    }

    /// A place of an app's own ring is the same place: it carries its label with the
    /// app's entry, and the same keys can be called something else in the next app.
    func testANameAndAnIconComeBackForAnAppsPlace() throws {
        let notes = Application(path: "/System/Applications/Notes.app")
        notes.setUsesGeneralRing(false, general: .default)
        notes.ring?[2] = ShortcutRingPlace(action: shiftCommandR, label: label("Reload", symbol: "arrow.clockwise"))
        let mail = Application(path: "/System/Applications/Mail.app")
        mail.setUsesGeneralRing(false, general: .default)
        mail.ring?[2] = ShortcutRingPlace(action: shiftCommandR, label: label("Reply to All", character: "↩"))

        let notesBack = try JSONDecoder().decode(Application.self, from: try JSONEncoder().encode(notes))
        let mailBack = try JSONDecoder().decode(Application.self, from: try JSONEncoder().encode(mail))
        XCTAssertEqual(notesBack.ring?[2].label, label("Reload", symbol: "arrow.clockwise"))
        XCTAssertEqual(mailBack.ring?[2].label, label("Reply to All", character: "↩"))
        XCTAssertEqual(notesBack.ring?[2].action, mailBack.ring?[2].action)
        XCTAssertNil(notesBack.ring?[0].label, "Mission Control has its own name")
    }

    // MARK: A button's binding

    func testABindingFromBeforeReadsAndIsWrittenBackUnchanged() throws {
        let binding = try decoded(ButtonBinding.self, oldBinding)
        XCTAssertEqual(binding.systemShortcutName, shiftCommandR)
        XCTAssertNil(binding.label)
        XCTAssertEqual(try json(binding), oldBinding)
        XCTAssertEqual(Options.decodeButtonBindings(from: Data("[\(oldBinding)]".utf8)), [binding])
    }

    func testANameAndAnIconComeBackForABinding() throws {
        let named = ButtonBinding(
            triggerEvent: trigger, systemShortcutName: shiftCommandR, label: label("Reload", symbol: "arrow.clockwise")
        )
        let stored = try json(named)
        XCTAssertTrue(stored.contains(#""label":{"name":"Reload","symbol":"arrow.clockwise"}"#), stored)
        let back = try decoded(ButtonBinding.self, stored)
        XCTAssertEqual(back, named)
        XCTAssertEqual(back.label, label("Reload", symbol: "arrow.clockwise"))
        XCTAssertNotEqual(named, named.labelled(nil), "a name is a change of the binding")
        XCTAssertEqual(named.labelled(nil).systemShortcutName, shiftCommandR)
        // The label stays with the action when the binding gets another trigger, and
        // through the list of bindings as it is stored.
        let moved = named.replacingTriggerEvent(RecordedEvent(type: .mouse, code: 4, modifiers: 0, deviceFilter: nil))
        XCTAssertEqual(moved.label, named.label)
        XCTAssertEqual(Options.decodeButtonBindings(from: try JSONEncoder().encode([named])), [named])
    }

    func testAnOlderVersionStillReadsTheKeysOfANamedBinding() throws {
        struct BindingBeforeNames: Decodable {
            let id: UUID
            let triggerEvent: RecordedEvent
            let systemShortcutName: String
            let isEnabled: Bool
            let createdAt: Date
            let openTarget: OpenTargetPayload?
        }
        let named = ButtonBinding(triggerEvent: trigger, systemShortcutName: shiftCommandR, label: label("Reload"))
        let old = try decoded(BindingBeforeNames.self, try json(named))
        XCTAssertEqual(old.systemShortcutName, shiftCommandR)
        XCTAssertEqual(old.id, named.id)
        XCTAssertNil(old.openTarget)
    }

    // MARK: What takes a label

    /// Only a recorded key combination takes a name and an icon: a listed shortcut, an
    /// app to open, a click and an empty place never do, however they were made or stored.
    func testOnlyARecordedKeyCombinationTakesANameAndAnIcon() throws {
        let reload = label("Reload", symbol: "arrow.clockwise")
        XCTAssertTrue(ShortcutLabel.takes(action: shiftCommandR))
        for action in ["copy", "missionControl", "mouseBackClick", "", "custom::mouse:3:0", "openTarget", "shortcutRing"] {
            XCTAssertFalse(ShortcutLabel.takes(action: action), action)
            XCTAssertNil(ShortcutRingPlace(action: action, label: reload).label, action)
            XCTAssertNil(ButtonBinding(triggerEvent: trigger, systemShortcutName: action, label: reload).label, action)
        }
        let notes = OpenTargetPayload(path: "/System/Applications/Notes.app", bundleID: nil, arguments: "", kind: .application)
        XCTAssertNil(ShortcutRingPlace(action: "openTarget", openTarget: notes, label: reload).label)
        XCTAssertNil(ButtonBinding(triggerEvent: trigger, openTarget: notes).labelled(reload).label)

        // Stored with one all the same (a file written by hand): read without it, and
        // written back without it.
        let place = try decoded(ShortcutRingPlace.self, #"{"action":"copy","label":{"name":"Reload"}}"#)
        XCTAssertEqual(place, ShortcutRingPlace(action: "copy"))
        XCTAssertEqual(try json(place), #"{"action":"copy"}"#)
        let stored = oldBinding
            .replacingOccurrences(of: #""systemShortcutName":"custom::15:1179648""#, with: #""label":{"name":"Reload"},"systemShortcutName":"copy""#)
        let binding = try decoded(ButtonBinding.self, stored)
        XCTAssertEqual(binding.systemShortcutName, "copy")
        XCTAssertNil(binding.label)
        XCTAssertFalse(try json(binding).contains("label"))
    }

    /// Changing a place's action to something that takes no label drops the label: the
    /// pane builds the place anew from what the pull-down holds.
    func testAPlaceBuiltFromABindingKeepsTheLabelOnlyForItsKeys() {
        let reload = label("Reload", symbol: "arrow.clockwise")
        let place = ShortcutRingPlace(action: shiftCommandR, label: reload)
        XCTAssertEqual(place.asBinding().label, reload)
        XCTAssertEqual(ShortcutRingPlace(actionOf: place.asBinding()), place)
        let binding = place.asBinding()
        let copy = ButtonBinding(id: binding.id, triggerEvent: binding.triggerEvent, systemShortcutName: "copy", label: binding.label)
        XCTAssertNil(ShortcutRingPlace(actionOf: copy).label)
    }

    // MARK: What a label holds

    func testANameIsOneShortLineOfWhatCanBeSeen() {
        XCTAssertEqual(ShortcutLabel.cleanedName("  Reload  "), "Reload")
        XCTAssertEqual(ShortcutLabel.cleanedName("Reload\nWithout\tCache"), "Reload Without Cache")
        XCTAssertEqual(ShortcutLabel.cleanedName("Re\u{0007}load\u{0000}"), "Reload")
        XCTAssertEqual(ShortcutLabel.cleanedName("\u{202E}Reload\u{2066}"), "Reload", "nothing turns the row's text around")
        XCTAssertEqual(ShortcutLabel.cleanedName("👨‍👩‍👧 Family"), "👨‍👩‍👧 Family", "an emoji stays whole")
        XCTAssertNil(ShortcutLabel.cleanedName(" \n\t "))
        XCTAssertNil(ShortcutLabel.cleanedName(""))
        let long = String(repeating: "Reload the page ", count: 4)
        XCTAssertEqual(ShortcutLabel.cleanedName(long)?.count, ShortcutLabel.maximumNameLength)
        XCTAssertEqual(ShortcutLabel.maximumNameLength, 24)
        XCTAssertEqual(ShortcutLabel.cleanedName(long), "Reload the page Reload t")
        XCTAssertEqual(ShortcutLabel.cleanedName(String(repeating: "a", count: 23) + " b"), String(repeating: "a", count: 23))
    }

    func testAnIconIsASymbolsNameOrOneCharacter() {
        XCTAssertEqual(ShortcutLabel.cleaned(.symbol("arrow.clockwise")), .symbol("arrow.clockwise"))
        XCTAssertEqual(ShortcutLabel.cleaned(.symbol("1.circle.fill")), .symbol("1.circle.fill"))
        XCTAssertNil(ShortcutLabel.cleaned(.symbol("")))
        XCTAssertNil(ShortcutLabel.cleaned(.symbol("Arrow Clockwise")))
        XCTAssertNil(ShortcutLabel.cleaned(.symbol("../../etc/passwd")))
        XCTAssertNil(ShortcutLabel.cleaned(.symbol(String(repeating: "a", count: 65))))
        XCTAssertEqual(ShortcutLabel.cleaned(.character("R")), .character("R"))
        XCTAssertEqual(ShortcutLabel.cleaned(.character(" Rx")), .character("R"), "the first character that can be seen")
        XCTAssertEqual(ShortcutLabel.cleaned(.character("👨‍👩‍👧!")), .character("👨‍👩‍👧"))
        XCTAssertNil(ShortcutLabel.cleaned(.character(" \n")))
    }

    func testALabelWithNothingInItIsNoLabel() throws {
        XCTAssertNil(ShortcutLabel(name: nil, icon: nil))
        XCTAssertNil(ShortcutLabel(name: "   ", icon: .symbol("not a symbol")))
        XCTAssertEqual(ShortcutLabel(name: "  Reload ", icon: nil)?.name, "Reload")
        XCTAssertEqual(ShortcutRingPlace(action: shiftCommandR, label: label("  ")), ShortcutRingPlace(action: shiftCommandR))
    }

    /// A label that cannot be read never costs the place or the binding its keys.
    func testALabelThatCannotBeReadLeavesTheKeys() throws {
        for damaged in [#""label":7"#, #""label":{}"#, #""label":{"name":7,"symbol":["a"]}"#, #""label":{"name":""}"#, #""label":null"#] {
            let place = try decoded(ShortcutRingPlace.self, "{\"action\":\"custom::15:1179648\",\(damaged)}")
            XCTAssertEqual(place, ShortcutRingPlace(action: shiftCommandR), damaged)
            let stored = oldBinding.replacingOccurrences(of: #""isEnabled":true"#, with: "\(damaged),\"isEnabled\":true")
            let binding = try decoded(ButtonBinding.self, stored)
            XCTAssertEqual(binding.systemShortcutName, shiftCommandR, damaged)
            XCTAssertNil(binding.label, damaged)
        }
        // What can be read of a label is kept: a name beside an icon that is none.
        let half = try decoded(ShortcutRingPlace.self, #"{"action":"custom::15:1179648","label":{"name":"Reload","symbol":"NOT ONE"}}"#)
        XCTAssertEqual(half.label, label("Reload"))
        // A symbol comes before a character when a file holds both.
        let both = try decoded(ShortcutRingPlace.self, #"{"action":"custom::15:1179648","label":{"character":"R","symbol":"star"}}"#)
        XCTAssertEqual(both.label?.icon, .symbol("star"))
    }
}
