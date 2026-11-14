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

    /// What a name and a typed icon are made of is bounded too, not only what they show:
    /// "R" with any number of accents is one character. A letter keeps its first few
    /// marks, tags stay only in an emoji flag, and a joiner, a tag or a mark by itself is
    /// no icon (nor a name). The emoji of today stay whole.
    func testANameAndAnIconAreBoundedInWhatTheyAreMadeOf() {
        let piled = ShortcutLabel.cleanedName("R" + String(repeating: "\u{0301}", count: 300_000))
        XCTAssertEqual(piled?.count, 1)
        XCTAssertEqual(piled?.unicodeScalars.first, "R")
        XCTAssertEqual(piled?.unicodeScalars.count, ShortcutLabel.maximumScalarsPerCharacter)
        XCTAssertEqual(ShortcutLabel.maximumScalarsPerCharacter, 16)
        if case .character(let icon)? = ShortcutLabel.cleaned(.character("R" + String(repeating: "\u{0301}", count: 3_000))) {
            XCTAssertEqual(icon.unicodeScalars.count, ShortcutLabel.maximumScalarsPerCharacter)
        } else {
            XCTFail("the R is the icon, with its first accents")
        }
        // Every character piled high: the name ends at a character before it is too long.
        let everyOne = ShortcutLabel.cleanedName(String(repeating: "a" + String(repeating: "\u{0301}", count: 30), count: 24))
        XCTAssertEqual(everyOne?.unicodeScalars.count, ShortcutLabel.maximumNameScalars)
        XCTAssertEqual(everyOne?.count, ShortcutLabel.maximumNameScalars / ShortcutLabel.maximumScalarsPerCharacter)

        // The longest emoji (a kiss of two people with their skin tones: ten scalars) and
        // a flag with its tags stay whole, in a name and as the icon.
        let kiss = "\u{1F469}\u{1F3FD}\u{200D}\u{2764}\u{FE0F}\u{200D}\u{1F48B}\u{200D}\u{1F468}\u{1F3FF}"
        XCTAssertEqual(kiss.count, 1)
        XCTAssertEqual(ShortcutLabel.cleanedName("\(kiss) Kiss"), "\(kiss) Kiss")
        XCTAssertEqual(ShortcutLabel.cleaned(.character(kiss)), .character(kiss))
        let scotland = "\u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}"
        XCTAssertEqual(ShortcutLabel.cleanedName("Go \(scotland)")?.unicodeScalars.count, 3 + 7)
        XCTAssertEqual(ShortcutLabel.cleaned(.character(scotland)), .character(scotland))
        // Tags anywhere else are text that is stored and shown nowhere: they go.
        let hidden = String(String.UnicodeScalarView("hidden".unicodeScalars.compactMap { Unicode.Scalar($0.value + 0xE0000) }))
        XCTAssertEqual(ShortcutLabel.cleanedName("Copy" + hidden)?.unicodeScalars.count, 4)
        XCTAssertEqual(ShortcutLabel.cleanedName("\u{1F3F4} Copy" + hidden)?.unicodeScalars.count, 6, "not after a flag's space")

        for invisible in ["\u{200D}", "\u{200C}", "\u{E0041}", "\u{E007F}", "\u{0301}", "\u{FE0F}", "\u{200D}\u{200D} "] {
            let spelled = invisible.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: " ")
            XCTAssertNil(ShortcutLabel.cleaned(.character(invisible)), spelled)
            XCTAssertNil(ShortcutLabel.cleanedName(invisible), spelled)
            XCTAssertTrue(ShortcutIconChoices.matching(invisible).isEmpty, "nothing offered for \(spelled)")
        }
        XCTAssertEqual(ShortcutLabel.cleaned(.character("\u{200D}R")), .character("R"), "the first character that can be seen")
        XCTAssertEqual(ShortcutLabel.cleaned(.character("\u{0301}Rx")), .character("R"))
    }

    /// The Apple logo (⌥⇧K) is a private-use character the system font draws: it stays in
    /// a name, can be the icon, and comes back from a file.
    func testAPrivateUseCharacterStaysInANameAndCanBeTheIcon() throws {
        XCTAssertEqual(ShortcutLabel.cleanedName("\u{F8FF} Menu"), "\u{F8FF} Menu")
        XCTAssertEqual(ShortcutLabel.cleanedName("\u{F8FF}"), "\u{F8FF}")
        XCTAssertEqual(ShortcutLabel.cleaned(.character("\u{F8FF}")), .character("\u{F8FF}"))
        XCTAssertEqual(ShortcutIconChoices.matching("\u{F8FF}").first, .character("\u{F8FF}"), "offered as “Use”")
        let place = try decoded(ShortcutRingPlace.self, #"{"action":"custom::15:1179648","label":{"character":"","name":" Menu"}}"#)
        XCTAssertEqual(place.label, ShortcutLabel(name: "\u{F8FF} Menu", icon: .character("\u{F8FF}")))
        XCTAssertEqual(try json(place), #"{"action":"custom::15:1179648","label":{"character":"\#u{F8FF}","name":"\#u{F8FF} Menu"}}"#)
        // Still no surrogate or unassigned code point.
        XCTAssertEqual(ShortcutLabel.cleanedName("Menu\u{0378}"), "Menu")
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

// MARK: - The ring

final class ShortcutLabelRingTests: XCTestCase {

    private var keys: String {
        return ButtonTriggerNaming.shortcutText(type: .keyboard, code: 15, modifiers: 1_179_648)
    }

    private func face(of label: ShortcutLabel?) -> ShortcutRingFace.Place {
        var ring = ShortcutRingSettings.default
        ring[2] = ShortcutRingPlace(action: shiftCommandR, label: label)
        return ShortcutRingFace(ring, looksOnDisk: false).places[2]
    }

    /// The four cases of a recorded key combination. Nothing set: the keys in the drop
    /// and in the middle, as before. A name: the drop keeps the keys, the middle says
    /// the name with the keys under it. An icon: the drop shows it, the middle the keys
    /// as before. Both: the icon in the drop, the name over the keys in the middle.
    func testTheFaceOfAPlaceInEachOfTheFourCases() {
        let plain = face(of: nil)
        XCTAssertEqual(plain.title, keys)
        XCTAssertEqual(plain.keys, "")
        XCTAssertEqual(plain.glyphs, [keys])
        XCTAssertFalse(plain.glyphIsIcon)
        XCTAssertEqual(plain.symbolName, "keyboard")
        XCTAssertFalse(plain.isEmpty)

        let named = face(of: label("Reload"))
        XCTAssertEqual(named.title, "Reload")
        XCTAssertEqual(named.keys, keys)
        XCTAssertEqual(named.glyphs, [keys], "the drop keeps the keys")
        XCTAssertFalse(named.glyphIsIcon)

        let withIcon = face(of: label(nil, symbol: "arrow.clockwise"))
        XCTAssertEqual(withIcon.title, keys, "the middle shows the keys as before")
        XCTAssertEqual(withIcon.keys, "")
        XCTAssertEqual(withIcon.glyphs, [], "the drop shows the symbol, through the symbols' own drawing")
        XCTAssertEqual(withIcon.symbolName, "arrow.clockwise")
        XCTAssertNil(withIcon.image)

        let both = face(of: label("Reload", symbol: "arrow.clockwise"))
        XCTAssertEqual(both.title, "Reload")
        XCTAssertEqual(both.keys, keys)
        XCTAssertEqual(both.glyphs, [])
        XCTAssertEqual(both.symbolName, "arrow.clockwise")

        // A typed character is drawn as the keys are, in the keys' place.
        let typed = face(of: label("Reload", character: "🔄"))
        XCTAssertEqual(typed.glyphs, ["🔄"])
        XCTAssertTrue(typed.glyphIsIcon)
        XCTAssertEqual(typed.title, "Reload")
        XCTAssertEqual(typed.keys, keys)
    }

    /// A symbol this Mac does not have (a file from a newer macOS) leaves the keys in the
    /// drop: never an empty drop for a place that runs.
    func testASymbolThisMacDoesNotHaveLeavesTheKeysInTheDrop() {
        let unknown = face(of: label("Reload", symbol: "no.such.symbol.anywhere"))
        XCTAssertEqual(unknown.glyphs, [keys])
        XCTAssertEqual(unknown.symbolName, "keyboard")
        XCTAssertEqual(unknown.title, "Reload", "the name does not depend on the symbol")
        XCTAssertFalse(ShortcutRingFace.hasSymbol(named: "no.such.symbol.anywhere"))
        XCTAssertTrue(ShortcutRingFace.hasSymbol(named: "arrow.clockwise"))
    }

    /// The other kinds of places are as they were: nothing under their name.
    func testTheOtherPlacesHaveNothingUnderTheirName() {
        var ring = ShortcutRingSettings.default
        ring[1] = ShortcutRingPlace(
            openTarget: OpenTargetPayload(path: "/System/Applications/Notes.app", bundleID: nil, arguments: "", kind: .application)
        )
        ring[3] = .empty
        for place in ShortcutRingFace(ring, looksOnDisk: false).places {
            XCTAssertEqual(place.keys, "")
            XCTAssertFalse(place.glyphIsIcon)
        }
    }

    /// The middle: the name on one or two lines, the keys on one line under it and
    /// smaller, the two together inside the round drop, on screen and in the pane. A name
    /// of words is shown whole, smaller when it needs to be; only a run of the widest
    /// letters may still be cut.
    func testTheMiddleShowsTheNameOverSmallerKeysWithinItsRoom() {
        let widest = String(repeating: "W", count: ShortcutLabel.maximumNameLength)
        let artificial = [widest, "Wwwwwwwwwwww Wwwwwwwwwww"]
        let words = [
            "Reload", "Reload Without Cache", "Show Developer Tools", "Show Keyboard Shortcuts",
            "Close All Other Windows", "Paste and Match Style", "Find and Replace In File",
        ]
        let names = words + artificial
        let combinations = [keys, "Fn⌃⌥⇧⌘Space", "⌃⌥⇧⌘F19"]
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        let paneScale = ShortcutRingPreviewView.ringScale
        for (what, scale) in [("on screen", CGFloat(1)), ("in the pane", paneScale)] {
            let width = ShortcutRingArtwork.titleWidth * scale
            let size = ShortcutRingArtwork.titleFont.pointSize * scale
            let diameter = ShortcutRingDrops.hubDiameter * scale
            for name in names {
                for combination in combinations {
                    let layout = ShortcutRingArtwork.namedTitleLayout(name, keys: combination, width: width, pointSize: size)
                    let about = "\(name) / \(combination) \(what)"
                    XCTAssertLessThanOrEqual(layout.nameLines, 2, about)
                    XCTAssertGreaterThanOrEqual(layout.nameLines, 1, about)
                    if words.contains(name) {
                        // The whole name, as the text system lays it out at its size, stands
                        // in the room it is drawn in: nothing is cut.
                        let whole = (name as NSString).boundingRect(
                            with: CGSize(width: width, height: 10_000), options: [.usesLineFragmentOrigin],
                            attributes: [
                                .font: NSFont.systemFont(ofSize: layout.namePointSize, weight: .semibold),
                                .paragraphStyle: paragraph,
                            ]
                        )
                        XCTAssertLessThanOrEqual(whole.height, layout.nameHeight, "\(about): nothing is cut")
                        XCTAssertLessThanOrEqual(whole.width, width + 0.5, about)
                    }
                    XCTAssertLessThan(layout.keysPointSize, layout.namePointSize, about)
                    XCTAssertGreaterThanOrEqual(layout.keysPointSize, 6 * scale, about)
                    let keysFont = NSFont.systemFont(ofSize: layout.keysPointSize, weight: .medium)
                    XCTAssertLessThanOrEqual(
                        (combination as NSString).size(withAttributes: [.font: keysFont]).width, width + 0.5, about
                    )
                    // Where the block's top and bottom edges are, the drop is still as
                    // wide as the text may be (as for a listed action's name).
                    let chord = 2 * (pow(diameter / 2, 2) - pow(layout.height / 2 - 2, 2)).squareRoot()
                    XCTAssertGreaterThanOrEqual(chord, width, about)
                    // Never taller than the three lines a long listed name takes.
                    let longest = ShortcutRingArtwork.titleLayout("Screenshot and Recording Options", width: width, pointSize: size)
                    XCTAssertLessThanOrEqual(layout.height, longest.height + 4 * scale, about)
                }
            }
            let short = ShortcutRingArtwork.namedTitleLayout("Reload", keys: keys, width: width, pointSize: size)
            XCTAssertEqual(short.nameLines, 1)
            XCTAssertEqual(short.namePointSize, size, "a short name keeps the size of every other name")
            XCTAssertEqual(short.keysPointSize, size * ShortcutRingArtwork.titleKeysShrink, accuracy: 0.001)
        }
    }

    /// What is drawn in the middle: with keys there is ink under the name, and all of it
    /// stays in the hub's circle.
    func testTheKeysAreDrawnUnderTheNameInsideTheHub() throws {
        let side = Int(ShortcutRingDrops.hubDiameter)
        func inkRows(keys: String) throws -> ClosedRange<Int> {
            let bitmap = try XCTUnwrap(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ))
            let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            ShortcutRingArtwork.drawTitle(
                "Reload", keys: keys, centre: CGPoint(x: CGFloat(side) / 2, y: CGFloat(side) / 2), colour: .black,
                width: ShortcutRingArtwork.titleWidth, pointSize: ShortcutRingArtwork.titleFont.pointSize
            )
            NSGraphicsContext.restoreGraphicsState()
            let data = try XCTUnwrap(bitmap.bitmapData)
            var first = side, last = -1
            for row in 0..<side {
                for column in 0..<side where data[row * bitmap.bytesPerRow + column * 4 + 3] > 40 {
                    first = min(first, row)
                    last = max(last, row)
                    let dx = CGFloat(column) + 0.5 - CGFloat(side) / 2, dy = CGFloat(row) + 0.5 - CGFloat(side) / 2
                    XCTAssertLessThan(hypot(dx, dy), CGFloat(side) / 2, "ink outside the hub")
                }
            }
            return try XCTUnwrap(first <= last ? first...last : nil)
        }
        let alone = try inkRows(keys: "")
        let withKeys = try inkRows(keys: keys)
        // (The bitmap's rows run downwards.)
        XCTAssertLessThan(withKeys.lowerBound, alone.lowerBound, "the name moves up to make room")
        XCTAssertGreaterThan(withKeys.upperBound, alone.upperBound, "the keys stand under it")
        XCTAssertGreaterThan(withKeys.count, alone.count + 6)
    }

    /// The hub of the ring on screen gets the keys with the name, and loses them with it.
    func testTheRingOnScreenPutsTheKeysUnderTheNameInItsHub() {
        let drops = ShortcutRingDropsView(material: .drawn)
        var ring = ShortcutRingSettings.default
        ring[2] = ShortcutRingPlace(action: shiftCommandR, label: label("Reload", symbol: "arrow.clockwise"))
        let face = ShortcutRingFace(ring, looksOnDisk: false)
        drops.face = face
        drops.titleKeys = face.places[2].keys
        drops.title = face.places[2].title
        guard case .name(let title, let under) = drops.contents[ShortcutRingDrops.placeCount].content else {
            return XCTFail("the hub shows a name")
        }
        XCTAssertEqual(title, "Reload")
        XCTAssertEqual(under, keys)
        guard case .place(let place) = drops.contents[2].content else { return XCTFail("the drop shows the place") }
        XCTAssertEqual(place.symbolName, "arrow.clockwise")

        drops.titleKeys = face.places[0].keys
        drops.title = face.places[0].title
        guard case .name(let listed, let nothing) = drops.contents[ShortcutRingDrops.placeCount].content else {
            return XCTFail("the hub shows a name")
        }
        XCTAssertEqual(listed, SystemShortcut.missionControl.localizedName)
        XCTAssertEqual(nothing, "")
    }

    /// A run of a named place: VoiceOver hears the name, the log never does. Its line
    /// stays "a recorded key combination".
    func testTheNameIsSaidAndNeverLogged() {
        let reload = ShortcutRingPlace(action: shiftCommandR, label: label("Reload Secretly", symbol: "arrow.clockwise"))
        XCTAssertEqual(ShortcutRingController.logName(of: reload), "a recorded key combination")
        XCTAssertEqual(ShortcutRingController.logName(of: reload), ShortcutRingController.logName(of: ShortcutRingPlace(action: shiftCommandR)))

        let harness = RingHarness()
        harness.ring[5] = reload
        harness.controller.triggerPressed(by: RingHarness.button(.down))
        harness.runScheduled()
        harness.moveHand(by: CGPoint(x: -50, y: 50))
        XCTAssertEqual(harness.presenter.lit.last, 5)
        harness.runScheduled()
        harness.controller.triggerReleased(isMadeUp: false)
        harness.runScheduled()

        XCTAssertEqual(harness.announced.last, "Reload Secretly")
        XCTAssertEqual(harness.logLines.last, "Shortcut Ring: closed, ran a recorded key combination")
        XCTAssertFalse(harness.logLines.isEmpty)
        for line in harness.logLines + harness.problems + harness.log {
            XCTAssertFalse(line.contains("Reload") || line.contains("Secretly"), line)
            XCTAssertFalse(line.contains("arrow.clockwise") || line.contains("custom::"), line)
        }
    }
}

// MARK: - The rows of the panes

final class ShortcutLabelRowsTests: XCTestCase {

    private var savedRing = ShortcutRingSettings.default
    private var savedBindings: [ButtonBinding] = []
    private var savedGesture = MouseGestureSettings.default

    override func setUp() {
        super.setUp()
        savedRing = Options.shared.ring
        savedBindings = Options.shared.buttons.binding
        savedGesture = Options.shared.gesture
        Options.shared.ring = .default
        Options.shared.buttons.binding = []
    }

    override func tearDown() {
        Options.shared.ring = savedRing
        Options.shared.buttons.binding = savedBindings
        Options.shared.gesture = savedGesture
        super.tearDown()
    }

    private var keys: String {
        return ButtonTriggerNaming.shortcutText(type: .keyboard, code: 15, modifiers: 1_179_648)
    }

    private func shown(_ label: ShortcutLabel?) -> ActionPresentation {
        return ActionDisplayResolver().resolve(state: .customBinding(name: shiftCommandR, label: label))
    }

    /// The colour of the title's part that says `part`.
    private func colour(of part: String, in title: NSAttributedString?) throws -> NSColor? {
        let title = try XCTUnwrap(title)
        let range = (title.string as NSString).range(of: part)
        XCTAssertNotEqual(range.location, NSNotFound, "\(part) in \(title.string)")
        return title.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor
    }

    /// The four cases, as a row's pull-down shows them. Nothing: "⌨ ⇧⌘R" as before. A
    /// name: the name, then the keys in grey. An icon: the icon where the keyboard was,
    /// then the keys as before. Both: the icon, the name, the grey keys.
    func testWhatARowShowsInEachOfTheFourCases() throws {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)

        let plain = shown(nil)
        XCTAssertEqual(plain.kind, .keyCombo)
        XCTAssertEqual(plain.title, keys)
        XCTAssertNil(plain.detail)
        XCTAssertEqual(plain.symbolName, "keyboard")
        XCTAssertNil(plain.glyph)
        XCTAssertEqual(plain.plainTitle, keys)
        XCTAssertNil(plain.attributedTitle(font: font), "nothing grey without a name")

        let named = shown(label("Reload"))
        XCTAssertEqual(named.title, "Reload")
        XCTAssertEqual(named.detail, keys)
        XCTAssertEqual(named.symbolName, "keyboard")
        XCTAssertEqual(named.plainTitle, "Reload  \(keys)")
        let title = named.attributedTitle(font: font)
        XCTAssertEqual(title?.string, "Reload  \(keys)")
        XCTAssertEqual(try colour(of: keys, in: title), .secondaryLabelColor)
        XCTAssertNil(try colour(of: "Reload", in: title), "the name in the control's own colour")

        let withIcon = shown(label(nil, symbol: "arrow.clockwise"))
        XCTAssertEqual(withIcon.title, keys)
        XCTAssertNil(withIcon.detail)
        XCTAssertEqual(withIcon.symbolName, "arrow.clockwise")
        XCTAssertNil(withIcon.attributedTitle(font: font))

        let both = shown(label("Reload", symbol: "arrow.clockwise"))
        XCTAssertEqual(both.title, "Reload")
        XCTAssertEqual(both.detail, keys)
        XCTAssertEqual(both.symbolName, "arrow.clockwise")

        let typed = shown(label("Reload", character: "R"))
        XCTAssertNil(typed.symbolName)
        XCTAssertEqual(typed.glyph, "R")
        XCTAssertNotNil(ShortcutIconSet.image(of: .character("R")))

        // A symbol this Mac does not have: the keyboard, as without an icon.
        XCTAssertEqual(shown(label("Reload", symbol: "no.such.symbol.anywhere")).symbolName, "keyboard")
        XCTAssertNil(ShortcutIconSet.image(of: .symbol("no.such.symbol.anywhere")))
    }

    /// A recorded ⌘C shows as "Copy"; called something by the user, it shows as that.
    func testANameOfTheUsersOwnComesBeforeAListedActionsName() {
        let commandC = "custom::8:1048576"
        let resolver = ActionDisplayResolver()
        XCTAssertEqual(resolver.resolve(state: .customBinding(name: commandC)).title, SystemShortcut.copy.localizedName)
        let named = resolver.resolve(state: .customBinding(name: commandC, label: label("Copy Link")))
        XCTAssertEqual(named.title, "Copy Link")
        XCTAssertEqual(named.kind, .keyCombo)
        XCTAssertNotNil(named.detail)
        // A label never reaches a recorded mouse button's row.
        let click = resolver.resolve(state: .customBinding(name: "custom::mouse:5:0", label: label("Reload", symbol: "star")))
        XCTAssertNil(click.detail)
        XCTAssertEqual(click.symbolName, "computermouse")
    }

    // MARK: Shortcut Ring

    func testTheRowOfAPlaceShowsTheIconTheNameAndTheKeysInGrey() throws {
        var ring = ShortcutRingSettings.default
        ring[2] = ShortcutRingPlace(action: shiftCommandR, label: label("Reload", symbol: "arrow.clockwise"))
        ring[4] = ShortcutRingPlace(action: shiftCommandR, label: label("Reload"))
        ring[6] = ShortcutRingPlace(action: shiftCommandR)
        Options.shared.ring = ring
        let controller = RingPreferencesViewController()
        controller.bindingSummary = { ShortcutRingBindingSummary(triggerTitles: []) }
        _ = controller.view

        let both = try XCTUnwrap(controller.placePopUps[2].menu?.items.first)
        XCTAssertEqual(both.title, "Reload  \(keys)")
        XCTAssertEqual(both.attributedTitle?.string, "Reload  \(keys)")
        XCTAssertEqual(try colour(of: keys, in: both.attributedTitle), .secondaryLabelColor)
        XCTAssertNotNil(both.image)
        XCTAssertEqual(controller.placePopUps[2].binding.label, ring[2].label, "the pull-down holds the place's label")

        let named = try XCTUnwrap(controller.placePopUps[4].menu?.items.first)
        XCTAssertEqual(named.title, "Reload  \(keys)")
        XCTAssertNotNil(named.image, "the keyboard symbol stays")

        let plain = try XCTUnwrap(controller.placePopUps[6].menu?.items.first)
        XCTAssertEqual(plain.title, keys)
        XCTAssertNil(plain.attributedTitle)

        let listed = try XCTUnwrap(controller.placePopUps[0].menu?.items.first)
        XCTAssertEqual(listed.title, SystemShortcut.missionControl.localizedName)
        XCTAssertNil(listed.attributedTitle)

        // The drawing above the rows shows the same place.
        XCTAssertEqual(controller.previewView.face.places[2].symbolName, "arrow.clockwise")
        XCTAssertEqual(controller.previewView.face.places[2].title, "Reload")

        // A row that goes back to an action without a name loses the grey part.
        controller.setPlace(ShortcutRingPlace(SystemShortcut.copy), at: 2)
        XCTAssertEqual(both.title, SystemShortcut.copy.localizedName)
        XCTAssertNil(both.attributedTitle)
        XCTAssertNil(Options.shared.ring[2].label)
    }

    /// An app's own ring: the same rows, with the app's own names.
    func testTheRowOfAnAppsPlaceShowsItsOwnName() throws {
        Options.shared.ring[2] = ShortcutRingPlace(action: shiftCommandR, label: label("Reload", symbol: "arrow.clockwise"))
        let mail = Application(path: "/System/Applications/Mail.app")
        mail.setUsesGeneralRing(false, general: Options.shared.ring)
        mail.ring?[2] = ShortcutRingPlace(action: shiftCommandR, label: label("Reply to All"))
        let controller = RingPreferencesViewController(application: mail)
        _ = controller.view
        XCTAssertEqual(controller.placePopUps[2].menu?.items.first?.title, "Reply to All  \(keys)")
        XCTAssertEqual(Options.shared.ring[2].label?.name, "Reload", "the general ring keeps its own")
    }

    // MARK: Buttons

    func testTheRowOfAButtonShowsTheIconTheNameAndTheKeysInGrey() throws {
        let back = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, deviceFilter: nil),
            systemShortcutName: shiftCommandR, label: label("Reload", symbol: "arrow.clockwise")
        )
        let forward = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 4, modifiers: 0, deviceFilter: nil),
            systemShortcutName: shiftCommandR
        )
        Options.shared.buttons.binding = [back, forward]
        let pane = PreferencesButtonsViewController()
        pane.deviceSource = ButtonsDeviceSource(
            captureStatus: { _ in .normal }, deviceName: { nil }, isBusy: { false }, refresh: {}, warnBluetoothButton: { _ in }
        )
        pane.scrollHoldKeys = { [] }
        pane.startRecording = { _ in }
        pane.stopRecording = {}
        pane.presentOpenTarget = { _, _, _ in }
        pane.openActionMenu = { _ in }
        pane.presentPlaceMenu = { _, _ in }
        pane.showPane = { _ in }
        pane.paneUndoManager = UndoManager()
        _ = pane.view

        let named = try XCTUnwrap(pane.rows.first { $0.binding.id == back.id })
        let title = try XCTUnwrap(named.pullDown.menu?.items.first)
        XCTAssertEqual(title.title, "Reload  \(keys)")
        XCTAssertEqual(title.attributedTitle?.string, "Reload  \(keys)")
        XCTAssertEqual(try colour(of: keys, in: title.attributedTitle), .secondaryLabelColor)
        XCTAssertNotNil(title.image)
        XCTAssertEqual(pane.focus(for: named).action, "Reload", "the card over the list says the name")

        let plain = try XCTUnwrap(pane.rows.first { $0.binding.id == forward.id })
        XCTAssertEqual(plain.pullDown.menu?.items.first?.title, keys)
        XCTAssertNil(plain.pullDown.menu?.items.first?.attributedTitle)
    }

    // MARK: Gestures

    /// A direction and the click of Gesture Navigation take a recorded key combination
    /// with a name and an icon, as a place of the ring does: their rows offer "Keyboard
    /// Shortcut…" and show the icon, the name and the keys in grey; the combination is an
    /// action a gesture runs. (`GestureKeysTests` holds the rest.)
    func testTheRowOfADirectionShowsTheIconTheNameAndTheKeysInGrey() throws {
        var gesture = MouseGestureSettings.default
        gesture.actions.up = GestureAction(action: shiftCommandR, label: label("Reload", symbol: "arrow.clockwise"))
        gesture.actions.down = GestureAction(action: shiftCommandR, label: label("Reload"))
        gesture.actions.click = GestureAction(action: shiftCommandR)
        Options.shared.gesture = gesture
        let controls = MouseGestureSettingsControls(showLogiActions: true, isInteractiveAvailable: { true })
        func markers(_ menu: NSMenu?) -> [String] {
            return (menu?.items ?? []).flatMap { item -> [String] in
                return [item.representedObject as? String].compactMap { $0 } + markers(item.submenu)
            }
        }
        for popUp in controls.actionPopUps {
            XCTAssertEqual(markers(popUp.menu), [ShortcutManager.MenuMarker.keyboardShortcut], "\"Keyboard Shortcut…\" here")
        }

        let both = try XCTUnwrap(controls.actionPopUp(for: .up).menu?.items.first)
        XCTAssertEqual(both.title, "Reload  \(keys)")
        XCTAssertEqual(try colour(of: keys, in: both.attributedTitle), .secondaryLabelColor)
        XCTAssertNotNil(both.image)
        XCTAssertEqual(controls.actionPopUp(for: .up).binding.label, gesture.actions.up.label, "the pull-down holds the label")

        let named = try XCTUnwrap(controls.actionPopUp(for: .down).menu?.items.first)
        XCTAssertEqual(named.title, "Reload  \(keys)")
        XCTAssertNotNil(named.image, "the keyboard symbol stays")

        let plain = try XCTUnwrap(controls.actionPopUp(for: .click).menu?.items.first)
        XCTAssertEqual(plain.title, keys)
        XCTAssertNil(plain.attributedTitle)

        let listed = try XCTUnwrap(controls.actionPopUp(for: .right).menu?.items.first)
        XCTAssertEqual(listed.title, SystemShortcut.moveSpaceRight.localizedName)
        XCTAssertNil(listed.attributedTitle)

        XCTAssertTrue(StoredAction.isKnown(gestureAction: shiftCommandR), "a direction runs a recorded combination")
        XCTAssertNotNil(GestureAction(action: shiftCommandR).resolvedAction)
    }
}

// MARK: - The recorder's popover

/// A popover that builds its content and counts as open, without a window.
private final class QuietPopover: KeyPopover {
    private(set) var standsOpen = false

    override var isOpen: Bool {
        return standsOpen
    }

    override func show(at sourceView: NSView, waitingHint: String) {
        announce = { _ in }
        if standsOpen {
            // (Open already: it turns back to asking for keys where it is.)
            super.show(at: sourceView, waitingHint: waitingHint)
        } else {
            testingPrepareContent(waitingHint: waitingHint)
            standsOpen = true
        }
    }

    override func showDetails(at sourceView: NSView, keys: [String], label: ShortcutLabel?) {
        announce = { _ in }
        testingPrepareDetails(keys: keys, label: label)
        standsOpen = true
    }

    override func hide() {
        standsOpen = false
        super.hide()
    }

    func closeAsTheUserDoes() {
        standsOpen = false
        testingCloseAsTheUserDoes()
    }
}

final class ShortcutLabelPopoverTests: XCTestCase {

    private var savedRing = ShortcutRingSettings.default
    private var savedBindings: [ButtonBinding] = []
    private var stored: [(action: String, label: ShortcutLabel?)] = []
    private var recorderStarts = 0
    private var windows: [NSWindow] = []

    override func setUp() {
        super.setUp()
        savedRing = Options.shared.ring
        savedBindings = Options.shared.buttons.binding
        Options.shared.ring = .default
        Options.shared.buttons.binding = []
        stored = []
        recorderStarts = 0
    }

    override func tearDown() {
        windows.forEach { $0.contentView = nil }
        windows = []
        Options.shared.ring = savedRing
        Options.shared.buttons.binding = savedBindings
        super.tearDown()
    }

    private let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, deviceFilter: nil)
    private let reload = label("Reload", symbol: "arrow.clockwise")

    private func pressed(_ code: UInt16, _ modifiers: CGEventFlags) -> InputEvent {
        return InputEvent(type: .keyboard, code: code, modifiers: modifiers, phase: .down, source: .hidPP, device: nil)
    }

    private var shiftCommandRPressed: InputEvent {
        return pressed(15, CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue))
    }

    private func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// What typing `text` into `field` tells the editor.
    private func type(_ text: String, into field: NSTextField, of editor: ShortcutLabelEditorView) {
        field.stringValue = text
        editor.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
    }

    private func details(keys: [String] = ["⇧", "⌘", "R"], label: ShortcutLabel? = nil) throws -> (KeyPopover, ShortcutLabelEditorView) {
        let popover = KeyPopover()
        popover.announce = { _ in }
        popover.testingPrepareDetails(keys: keys, label: label)
        return (popover, try XCTUnwrap(popover.labelEditor))
    }

    /// The seams of a pull-down that would open a window or tap the system's events.
    private func quiet(_ pullDown: ButtonActionPullDown) {
        pullDown.makeDetailsPopover = { QuietPopover() }
        pullDown.presentShortcutDetails = { popover, anchor, keys, label in
            popover.showDetails(at: anchor, keys: keys, label: label)
        }
        pullDown.startShortcutRecorder = { [unowned self] _ in self.recorderStarts += 1 }
    }

    /// A pull-down in a window that is never shown (the recorder only starts from a
    /// pull-down that is in a window), with what it tells its pane written down.
    private func makePullDown(_ binding: ButtonBinding, use: ButtonActionPullDown.Use = .binding) -> ButtonActionPullDown {
        let pullDown = ButtonActionPullDown(binding: binding, use: use)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled], backing: .buffered, defer: true
        )
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(pullDown)
        windows.append(window)
        quiet(pullDown)
        pullDown.onCustomShortcutRecorded = { [unowned self] name, label in self.stored.append((name, label)) }
        return pullDown
    }

    private func keyboardShortcutItem(of pullDown: ButtonActionPullDown) throws -> NSMenuItem {
        return try XCTUnwrap(pullDown.menu?.items.first {
            $0.representedObject as? String == ShortcutManager.MenuMarker.keyboardShortcut
        })
    }

    /// The recorder's side of a recording that caught `event`: the delegate hears of it,
    /// and at the end of the moment of feedback is asked whether it keeps the popover.
    private func record(_ event: InputEvent, into pullDown: ButtonActionPullDown, popover: KeyPopover) -> Bool {
        pullDown.onEventRecorded(KeyRecorder(), didRecordEvent: event, isDuplicate: false)
        popover.keyPreview?.update(from: event.displayComponents, status: .recorded)
        return pullDown.takesPopover(KeyRecorder(), popover)
    }

    // MARK: The popover itself

    /// While it waits for keys the popover is what it was: the name and icon are not
    /// there (every key belongs to the recording). Once keys are there, they are.
    func testTheNameAndTheIconComeOnceKeysAreThere() throws {
        let popover = KeyPopover()
        popover.announce = { _ in }
        popover.testingPrepareContent(waitingHint: KeyRecordingMode.adaptive.waitingHint)
        let content = try XCTUnwrap(popover.testingContentView)
        let editor = try XCTUnwrap(popover.labelEditor)
        XCTAssertTrue(editor.isHidden)
        XCTAssertFalse(popover.isShowingDetails)
        XCTAssertTrue(popover.testingWaitingIsVisible)
        XCTAssertTrue(popover.testingHintIsVisible)
        XCTAssertNil(popover.editedLabel)
        let waiting = content.fittingSize
        XCTAssertLessThan(waiting.height, 110, "the waiting popover is as small as before")

        popover.keyPreview.update(from: ["⇧", "⌘", "R"], status: .recorded)
        popover.turnToDetails(label: nil)
        XCTAssertTrue(popover.isShowingDetails)
        XCTAssertFalse(editor.isHidden)
        XCTAssertFalse(popover.testingWaitingIsVisible, "nothing asks for keys any more")
        XCTAssertFalse(popover.testingHintIsVisible, "nor says how to cancel a recording")
        content.layoutSubtreeIfNeeded()
        let size = content.fittingSize
        XCTAssertGreaterThan(size.height, waiting.height + 50)
        XCTAssertEqual(size.width, ShortcutLabelEditorView.width + 32, accuracy: 1)
        XCTAssertFalse(content.hasAmbiguousLayout)
        content.setFrameSize(size)
        content.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(popover.keyPreview.frame.minY, editor.frame.maxY, "the keys stand over the name and the icon")
        XCTAssertTrue(content.bounds.contains(editor.frame))
        XCTAssertFalse(editor.isChoosingIcon, "the symbols open when asked for")
        XCTAssertEqual(editor.nameField.placeholderString, "What these keys do")
        XCTAssertEqual(editor.iconWell.accessibilityLabel(), "Choose Icon")
        XCTAssertEqual(editor.recordAgainButton.title, "Record Again")
        XCTAssertEqual(editor.doneButton.title, "Done")
        XCTAssertEqual(editor.doneButton.keyEquivalent, "\r")
        // The explanation is one line, whole.
        let font = try XCTUnwrap(editor.noteLabel.font)
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        XCTAssertLessThanOrEqual(editor.noteLabel.frame.height, lineHeight + 2, editor.noteLabel.stringValue)
        XCTAssertLessThanOrEqual(
            editor.noteLabel.attributedStringValue.size().width, editor.noteLabel.frame.width + 0.5, "not cut short"
        )
    }

    func testTheNameIsWhatWasTypedCleanedAndNeverTooLong() throws {
        let (popover, editor) = try details()
        XCTAssertNil(popover.editedLabel)
        type("  Reload  ", into: editor.nameField, of: editor)
        XCTAssertEqual(popover.editedLabel, label("Reload"))
        type(String(repeating: "x", count: 40), into: editor.nameField, of: editor)
        XCTAssertEqual(editor.nameField.stringValue.count, ShortcutLabel.maximumNameLength)
        XCTAssertEqual(popover.editedLabel?.name?.count, ShortcutLabel.maximumNameLength)
        // A letter with a pile of accents pasted in is one character: the field keeps
        // what a name keeps of it.
        type("R" + String(repeating: "\u{0301}", count: 3_000), into: editor.nameField, of: editor)
        XCTAssertEqual(editor.nameField.stringValue.unicodeScalars.count, ShortcutLabel.maximumScalarsPerCharacter)
        XCTAssertEqual(popover.editedLabel?.name, editor.nameField.stringValue)
        // Clearing the field takes the name away.
        type("", into: editor.nameField, of: editor)
        XCTAssertNil(popover.editedLabel)
    }

    /// At the limit, a key typed or text pasted inside the name gives way, not the end of
    /// the name (F22): what does not fit of it is left out, and the caret stays after what
    /// was kept.
    func testTypingInsideAFullNameNeverCutsItsEnd() throws {
        let full = "Reload Page Without Cach"
        XCTAssertEqual(full.count, ShortcutLabel.maximumNameLength)
        let (popover, editor) = try details(label: label(full))
        type("Reload XPage Without Cach", into: editor.nameField, of: editor)
        XCTAssertEqual(editor.nameField.stringValue, full, "the key is refused")
        XCTAssertEqual(popover.editedLabel?.name, full)

        type("Reload Page", into: editor.nameField, of: editor)
        type("Reload ABCDEFGHIJKLMNOPQRSTUVPage", into: editor.nameField, of: editor)
        XCTAssertEqual(editor.nameField.stringValue, "Reload ABCDEFGHIJKLMPage", "as much of the paste as fits")
        XCTAssertEqual(
            ShortcutLabelEditorView.fitted("Reload ABCDEFGHIJKLMNOPQRSTUVPage", after: "Reload Page").caret,
            "Reload ABCDEFGHIJKLM".utf16.count
        )
        // Typed at the end, the same as before.
        type("Reload ABCDEFGHIJKLMPageX", into: editor.nameField, of: editor)
        XCTAssertEqual(editor.nameField.stringValue, "Reload ABCDEFGHIJKLMPage")
    }

    func testTheDetailsShowTheNameAndIconThatAreThere() throws {
        let (popover, editor) = try details(label: reload)
        XCTAssertEqual(editor.nameField.stringValue, "Reload")
        XCTAssertEqual(editor.icon, .symbol("arrow.clockwise"))
        XCTAssertNotNil(editor.iconWell.image)
        XCTAssertEqual(editor.iconWell.accessibilityLabel(), "Icon: Reload arrow")
        XCTAssertEqual(popover.editedLabel, reload)

        let (_, typed) = try details(label: label("Reload", character: "🔄"))
        XCTAssertEqual(typed.icon, .character("🔄"))
        XCTAssertNotNil(typed.iconWell.image)
        XCTAssertEqual(typed.iconWell.accessibilityLabel(), "Icon: 🔄")
    }

    /// The icon: a symbol or one character chosen in the chooser, or none.
    func testTheIconIsASymbolOrOneTypedCharacterChosenInTheChooser() throws {
        let (popover, editor) = try details()
        editor.iconWell.performClick(nil)
        let chooser = try XCTUnwrap(editor.chooser)
        XCTAssertTrue(chooser.removeButton.isHidden, "nothing to remove")
        chooser.search("reload")
        chooser.chooseSelected()
        XCTAssertEqual(popover.editedLabel, label(nil, symbol: "arrow.clockwise"))
        XCTAssertFalse(editor.isChoosingIcon, "chosen: the chooser closes")

        editor.iconWell.performClick(nil)
        let again = try XCTUnwrap(editor.chooser)
        XCTAssertFalse(again.removeButton.isHidden)
        again.search("🔄x")
        XCTAssertNil(again.choices.indexPath(of: .character("🔄")), "two characters are a search, not an icon")
        again.search("🔄")
        again.chooseSelected()
        XCTAssertEqual(popover.editedLabel, label(nil, character: "🔄"))

        editor.iconWell.performClick(nil)
        try XCTUnwrap(editor.chooser).removeButton.performClick(nil)
        XCTAssertNil(popover.editedLabel)
        XCTAssertFalse(editor.isChoosingIcon)
    }

    // MARK: The set of symbols

    /// About a hundred symbols in six groups, "Common" first, each group whole rows of the
    /// chooser's eight columns. (The Mac that runs this is newer than macOS 14: that 14
    /// has every name is not asked here.)
    func testEverySymbolOfTheSetIsThereOnceAndCanBeStored() {
        let names = ShortcutIconSet.all.map { $0.name }
        XCTAssertEqual(Set(names).count, names.count, "no symbol twice")
        XCTAssertEqual(names.count, 104)
        XCTAssertEqual(ShortcutIconSet.groups.count, 6)
        XCTAssertEqual(ShortcutIconSet.groups.first?.titleKey, "key-recorder-icon-group-common")
        XCTAssertEqual(ShortcutIconSet.groups.first?.symbols.count, 16)
        for name in ["arrow.clockwise", "arrow.uturn.backward", "square.and.arrow.up", "magnifyingglass", "xmark",
                     "playpause", "speaker.slash", "lock", "star", "trash", "doc.on.doc", "gearshape"] {
            XCTAssertTrue(ShortcutIconSet.groups[0].symbols.contains { $0.name == name }, name)
        }
        for group in ShortcutIconSet.groups {
            XCTAssertEqual(group.symbols.count % ShortcutIconChooserLayout.columns, 0, "\(group.titleKey) ends on a full row")
        }
        for symbol in ShortcutIconSet.all {
            XCTAssertNotNil(NSImage(systemSymbolName: symbol.name, accessibilityDescription: nil), symbol.name)
            XCTAssertEqual(ShortcutLabel.cleaned(.symbol(symbol.name)), .symbol(symbol.name), symbol.name)
            XCTAssertNotNil(ShortcutIconSet.image(of: .symbol(symbol.name)), symbol.name)
        }
        for group in ShortcutIconSet.groups {
            XCTAssertNotEqual(group.title, group.titleKey, "the group's name is in the catalog")
            XCTAssertFalse(group.symbols.isEmpty)
        }
    }

    func testTheSearchFindsASymbolByTheWordsOfItsNameAndByWhatItIsFor() {
        func found(_ query: String) -> [String] {
            return ShortcutIconSet.groups(matching: query).flatMap { $0.symbols }.map { $0.name }
        }
        XCTAssertEqual(found("").count, ShortcutIconSet.all.count)
        XCTAssertEqual(found("   ").count, ShortcutIconSet.all.count)
        XCTAssertTrue(found("clockwise").contains("arrow.clockwise"))
        XCTAssertFalse(found("clockwise").contains("arrow.counterclockwise"), "a word is found by its beginning")
        XCTAssertTrue(found("arrow up").contains("arrow.up"))
        XCTAssertTrue(found("ARROW.UP").contains("arrow.up"))
        XCTAssertTrue(found("undo").contains("arrow.uturn.backward"))
        XCTAssertTrue(found("paste").contains("doc.on.clipboard"))
        XCTAssertTrue(found("sett").contains("gearshape"))
        XCTAssertEqual(found("qqqq"), [])
        XCTAssertEqual(ShortcutIconSet.groups(matching: "gearshape").map { $0.titleKey }, ["key-recorder-icon-group-common"])
        XCTAssertEqual(ShortcutIconSet.groups(matching: "hammer").map { $0.titleKey }, ["key-recorder-icon-group-tools"])
    }

    // MARK: The pull-down: recording, then the name and the icon

    /// A recording that caught a key combination stores the keys as ever, and its
    /// popover stays for the name and the icon, which are stored when it closes.
    func testAfterARecordingThePopoverStaysForTheNameAndTheIcon() throws {
        let pullDown = makePullDown(ButtonBinding(triggerEvent: trigger, systemShortcutName: "copy"))
        pullDown.shortcutSelected(try keyboardShortcutItem(of: pullDown))
        XCTAssertEqual(pullDown.actionState, .recordingPrompt)
        XCTAssertNil(pullDown.detailsPopover, "a row without recorded keys records first")
        spin(0.3)
        XCTAssertEqual(recorderStarts, 1)

        let popover = QuietPopover()
        popover.show(at: pullDown, waitingHint: KeyRecordingMode.adaptive.waitingHint)
        XCTAssertTrue(record(shiftCommandRPressed, into: pullDown, popover: popover))
        XCTAssertEqual(stored.map { $0.action }, [shiftCommandR], "the keys are stored at once")
        XCTAssertNil(stored.last?.label)
        XCTAssertTrue(popover.isShowingDetails)
        XCTAssertTrue(popover.isOpen)
        XCTAssertTrue(pullDown.detailsPopover === popover)
        XCTAssertEqual(pullDown.actionState, .customBinding(name: shiftCommandR, label: nil))

        let editor = try XCTUnwrap(popover.labelEditor)
        type("Reload", into: editor.nameField, of: editor)
        editor.chooseSymbol("arrow.clockwise")
        XCTAssertEqual(stored.count, 1, "nothing more is stored while the popover is open")
        editor.doneButton.performClick(nil)
        XCTAssertFalse(popover.isOpen)
        XCTAssertNil(pullDown.detailsPopover)
        XCTAssertEqual(stored.count, 2)
        XCTAssertEqual(stored.last?.action, shiftCommandR)
        XCTAssertEqual(stored.last?.label, reload)
        XCTAssertEqual(pullDown.binding.label, reload)
        XCTAssertEqual(pullDown.menu?.items.first?.title.hasPrefix("Reload"), true)

        // The moment of feedback passes: nothing is stored a second time.
        spin(KeyRecorder.recordingFeedbackDelay(isDuplicate: false) + 0.2)
        XCTAssertEqual(stored.count, 2)
        XCTAssertEqual(pullDown.binding.label, reload)
    }

    /// Closing the popover in any other way keeps what was typed too; closing it
    /// unchanged stores nothing.
    func testAClickElsewhereKeepsWhatWasTyped() throws {
        let pullDown = makePullDown(ButtonBinding(triggerEvent: trigger, systemShortcutName: shiftCommandR, label: reload))
        pullDown.shortcutSelected(try keyboardShortcutItem(of: pullDown))
        let popover = try XCTUnwrap(pullDown.detailsPopover as? QuietPopover)
        popover.closeAsTheUserDoes()
        XCTAssertTrue(stored.isEmpty, "nothing changed")
        XCTAssertNil(pullDown.detailsPopover)

        pullDown.shortcutSelected(try keyboardShortcutItem(of: pullDown))
        let again = try XCTUnwrap(pullDown.detailsPopover as? QuietPopover)
        let editor = try XCTUnwrap(again.labelEditor)
        type("Reload All", into: editor.nameField, of: editor)
        again.closeAsTheUserDoes()
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.last?.label, label("Reload All", symbol: "arrow.clockwise"))
    }

    /// "Keyboard Shortcut…" on a row that holds recorded keys opens their name and icon
    /// and records nothing; "Record Again" records, and the other keys keep the name and
    /// the icon.
    func testRecordingOtherKeysKeepsTheNameAndTheIcon() throws {
        let pullDown = makePullDown(ButtonBinding(triggerEvent: trigger, systemShortcutName: shiftCommandR, label: reload))
        XCTAssertTrue(pullDown.holdsRecordedKeys)
        pullDown.shortcutSelected(try keyboardShortcutItem(of: pullDown))
        spin(0.3)
        XCTAssertEqual(recorderStarts, 0, "nothing is recorded yet")
        XCTAssertNotEqual(pullDown.actionState, .recordingPrompt)
        let popover = try XCTUnwrap(pullDown.detailsPopover as? QuietPopover)
        XCTAssertTrue(popover.isShowingDetails)
        let editor = try XCTUnwrap(popover.labelEditor)
        XCTAssertEqual(editor.nameField.stringValue, "Reload")
        XCTAssertEqual(editor.icon, .symbol("arrow.clockwise"))

        // The name is changed, then other keys are asked for: what was typed stays.
        type("Reload Page", into: editor.nameField, of: editor)
        editor.recordAgainButton.performClick(nil)
        spin(0.1)
        XCTAssertEqual(recorderStarts, 1)
        XCTAssertEqual(pullDown.actionState, .recordingPrompt)
        XCTAssertEqual(stored.last?.label, label("Reload Page", symbol: "arrow.clockwise"))
        // (What the recorder does with the popover that is open: it asks for keys in it.)
        popover.show(at: pullDown, waitingHint: KeyRecordingMode.adaptive.waitingHint)
        XCTAssertTrue(popover.isOpen)
        XCTAssertFalse(popover.isShowingDetails)
        XCTAssertTrue(editor.isHidden)
        XCTAssertTrue(popover.testingWaitingIsVisible)

        // ⌃⌥⇧⌘J: no listed action has it.
        let allFour = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskAlternate.rawValue
            | CGEventFlags.maskShift.rawValue | CGEventFlags.maskControl.rawValue)
        XCTAssertTrue(record(pressed(38, allFour), into: pullDown, popover: popover))
        XCTAssertEqual(stored.last?.action, "custom::38:1966080")
        XCTAssertEqual(stored.last?.label, label("Reload Page", symbol: "arrow.clockwise"))
        XCTAssertEqual(pullDown.binding.systemShortcutName, "custom::38:1966080")
        XCTAssertTrue(popover.isShowingDetails)
        XCTAssertEqual(editor.nameField.stringValue, "Reload Page")
        XCTAssertEqual(editor.icon, .symbol("arrow.clockwise"))
    }

    /// Clearing the name removes it; with the icon gone too nothing of a label is left,
    /// and the binding is stored as one from before names.
    func testClearingTheNameRemovesIt() throws {
        let pullDown = makePullDown(ButtonBinding(triggerEvent: trigger, systemShortcutName: shiftCommandR, label: reload))
        pullDown.shortcutSelected(try keyboardShortcutItem(of: pullDown))
        var popover = try XCTUnwrap(pullDown.detailsPopover as? QuietPopover)
        var editor = try XCTUnwrap(popover.labelEditor)
        type("", into: editor.nameField, of: editor)
        editor.doneButton.performClick(nil)
        XCTAssertEqual(stored.last?.label, label(nil, symbol: "arrow.clockwise"), "the icon stays")
        XCTAssertNil(pullDown.binding.label?.name)
        XCTAssertNil(pullDown.menu?.items.first?.attributedTitle, "nothing grey without a name")

        pullDown.shortcutSelected(try keyboardShortcutItem(of: pullDown))
        popover = try XCTUnwrap(pullDown.detailsPopover as? QuietPopover)
        editor = try XCTUnwrap(popover.labelEditor)
        editor.iconWell.performClick(nil)
        try XCTUnwrap(editor.chooser).removeButton.performClick(nil)
        popover.closeAsTheUserDoes()
        XCTAssertEqual(stored.count, 2)
        XCTAssertNil(stored.last?.label)
        XCTAssertNil(pullDown.binding.label)
        XCTAssertFalse(try json(pullDown.binding).contains("label"))
    }

    /// What takes no name lets the recorder's popover close, and drops a name that was
    /// there: a recorded combination that is a listed action, a mouse button.
    func testAListedShortcutAndAMouseButtonLetThePopoverClose() throws {
        let pullDown = makePullDown(ButtonBinding(triggerEvent: trigger, systemShortcutName: shiftCommandR, label: reload))
        let popover = QuietPopover()
        popover.show(at: pullDown, waitingHint: "")
        XCTAssertFalse(record(pressed(8, .maskCommand), into: pullDown, popover: popover), "⌘C is Copy")
        XCTAssertEqual(stored.last?.action, "copy")
        XCTAssertNil(stored.last?.label)
        XCTAssertNil(pullDown.binding.label)
        XCTAssertFalse(popover.isShowingDetails)
        XCTAssertNil(pullDown.detailsPopover)
        XCTAssertFalse(pullDown.holdsRecordedKeys)

        // The named keys again, so that the mouse button has a name to drop.
        pullDown.configure(with: ButtonBinding(triggerEvent: trigger, systemShortcutName: shiftCommandR, label: reload))
        XCTAssertEqual(pullDown.binding.label, reload)
        let button = InputEvent(type: .mouse, code: 5, modifiers: [], phase: .down, source: .hidPP, device: nil)
        XCTAssertFalse(record(button, into: pullDown, popover: popover))
        XCTAssertEqual(stored.last?.action, ButtonActionPullDown.bindingName(forRecorded: button))
        XCTAssertNil(stored.last?.label)
        XCTAssertNil(pullDown.binding.label)
        XCTAssertFalse(popover.isShowingDetails)
    }

    /// A popover the user closed during the moment of feedback is not brought back; the
    /// keys are stored all the same.
    func testAPopoverThatIsGoneIsNotBroughtBack() {
        let pullDown = makePullDown(ButtonBinding(triggerEvent: trigger, systemShortcutName: "copy"))
        let popover = QuietPopover()
        popover.show(at: pullDown, waitingHint: "")
        popover.closeAsTheUserDoes()
        XCTAssertFalse(record(shiftCommandRPressed, into: pullDown, popover: popover))
        XCTAssertEqual(stored.map { $0.action }, [shiftCommandR])
        XCTAssertNil(pullDown.detailsPopover)
        XCTAssertFalse(popover.isShowingDetails)
    }

    /// The line under the name says where it shows: a place's name in the Shortcut Ring
    /// and in Settings, a button's or a direction's only in Settings (the ring never shows
    /// it). The same whether the details open on keys that are there or after a recording.
    func testTheNoteSaysWhereTheNameShows() throws {
        let ring = "Shown in the Shortcut Ring and in Settings."
        let settings = "Shown in Settings."
        let named = ButtonBinding(triggerEvent: trigger, systemShortcutName: shiftCommandR, label: reload)
        let uses: [(ButtonActionPullDown.Use, String)] = [
            (.binding, settings), (.ringPlace, ring), (.gesture(showsLogiActions: false), settings),
        ]
        for (use, note) in uses {
            let pullDown = makePullDown(named, use: use)
            pullDown.shortcutSelected(try keyboardShortcutItem(of: pullDown))
            let opened = try XCTUnwrap(pullDown.detailsPopover as? QuietPopover, "\(use)")
            XCTAssertEqual(opened.labelEditor?.noteLabel.stringValue, note, "\(use)")
            opened.closeAsTheUserDoes()

            let recorded = makePullDown(ButtonBinding(triggerEvent: trigger, systemShortcutName: "copy"), use: use)
            let popover = QuietPopover()
            popover.show(at: recorded, waitingHint: "")
            XCTAssertTrue(record(shiftCommandRPressed, into: recorded, popover: popover), "\(use)")
            XCTAssertEqual(popover.labelEditor?.noteLabel.stringValue, note, "\(use)")
            popover.hide()
        }
    }

    // MARK: The panes store it

    func testAPlaceOfTheRingStoresTheNameAndTheIcon() throws {
        let controller = RingPreferencesViewController()
        controller.bindingSummary = { ShortcutRingBindingSummary(triggerTitles: []) }
        controller.startShortcutRecorder = { _ in }
        _ = controller.view
        let popUp = controller.placePopUps[7]
        quiet(popUp)
        let popover = QuietPopover()
        popover.show(at: popUp, waitingHint: "")
        XCTAssertTrue(record(shiftCommandRPressed, into: popUp, popover: popover))
        XCTAssertEqual(Options.shared.ring[7], ShortcutRingPlace(action: shiftCommandR))
        let editor = try XCTUnwrap(popover.labelEditor)
        type("Reload", into: editor.nameField, of: editor)
        editor.chooseSymbol("arrow.clockwise")
        editor.doneButton.performClick(nil)
        XCTAssertEqual(Options.shared.ring[7], ShortcutRingPlace(action: shiftCommandR, label: reload))
        XCTAssertEqual(controller.previewView.face.places[7].title, "Reload")
        XCTAssertEqual(controller.previewView.face.places[7].symbolName, "arrow.clockwise")
        XCTAssertEqual(popUp.menu?.items.first?.title.hasPrefix("Reload"), true)

        // Another action in the place: the name goes with the keys.
        controller.setPlace(ShortcutRingPlace(SystemShortcut.copy), at: 7)
        XCTAssertNil(Options.shared.ring[7].label)
        XCTAssertNil(popUp.binding.label)
    }

    func testAButtonStoresTheNameAndTheIcon() throws {
        let back = ButtonBinding(triggerEvent: trigger, systemShortcutName: shiftCommandR)
        Options.shared.buttons.binding = [back]
        let pane = PreferencesButtonsViewController()
        pane.deviceSource = ButtonsDeviceSource(
            captureStatus: { _ in .normal }, deviceName: { nil }, isBusy: { false }, refresh: {}, warnBluetoothButton: { _ in }
        )
        pane.scrollHoldKeys = { [] }
        pane.startRecording = { _ in }
        pane.stopRecording = {}
        pane.presentOpenTarget = { _, _, _ in }
        pane.openActionMenu = { _ in }
        pane.presentPlaceMenu = { _, _ in }
        pane.showPane = { _ in }
        pane.paneUndoManager = UndoManager()
        _ = pane.view
        let row = try XCTUnwrap(pane.rows.first { $0.binding.id == back.id })
        quiet(row.pullDown)
        row.pullDown.shortcutSelected(try keyboardShortcutItem(of: row.pullDown))
        let popover = try XCTUnwrap(row.pullDown.detailsPopover as? QuietPopover)
        let editor = try XCTUnwrap(popover.labelEditor)
        type("Reload", into: editor.nameField, of: editor)
        editor.iconWell.performClick(nil)
        let chooser = try XCTUnwrap(editor.chooser)
        chooser.search("R")
        chooser.chooseSelected()
        popover.closeAsTheUserDoes()
        let storedBinding = try XCTUnwrap(Options.shared.buttons.binding.first)
        XCTAssertEqual(storedBinding.id, back.id)
        XCTAssertEqual(storedBinding.systemShortcutName, shiftCommandR)
        XCTAssertEqual(storedBinding.label, label("Reload", character: "R"))
        XCTAssertEqual(storedBinding.triggerEvent, back.triggerEvent)
        XCTAssertEqual(pane.rows.first { $0.binding.id == back.id }?.pullDown.menu?.items.first?.title.hasPrefix("Reload"), true)

        // A listed action on the button: the name is gone from what is stored.
        pane.setAction(of: back.id, to: SystemShortcut.copy)
        XCTAssertNil(Options.shared.buttons.binding.first?.label)
    }

    /// "−" while a name is typed in the row's popover: the name goes into the binding
    /// before the row goes, so that Undo brings the row back with it (F21). In the Buttons
    /// pane and in an app's Buttons part.
    func testRemovingARowWhileItsNameIsTypedKeepsTheNameForUndo() throws {
        let back = ButtonBinding(triggerEvent: trigger, systemShortcutName: shiftCommandR, label: reload)
        Options.shared.buttons.binding = [back]
        let pane = PreferencesButtonsViewController()
        pane.deviceSource = ButtonsDeviceSource(
            captureStatus: { _ in .normal }, deviceName: { nil }, isBusy: { false }, refresh: {}, warnBluetoothButton: { _ in }
        )
        pane.scrollHoldKeys = { [] }
        pane.startRecording = { _ in }
        pane.stopRecording = {}
        pane.presentOpenTarget = { _, _, _ in }
        pane.openActionMenu = { _ in }
        pane.presentPlaceMenu = { _, _ in }
        pane.showPane = { _ in }
        let undo = UndoManager()
        undo.groupsByEvent = false
        pane.paneUndoManager = undo
        _ = pane.view
        let row = try XCTUnwrap(pane.rows.first { $0.binding.id == back.id })
        quiet(row.pullDown)
        row.pullDown.shortcutSelected(try keyboardShortcutItem(of: row.pullDown))
        let popover = try XCTUnwrap(row.pullDown.detailsPopover as? QuietPopover)
        let editor = try XCTUnwrap(popover.labelEditor)
        type("Reload All", into: editor.nameField, of: editor)
        undo.beginUndoGrouping()
        pane.list.onRemove?(back.id)
        undo.endUndoGrouping()
        XCTAssertTrue(Options.shared.buttons.binding.isEmpty)
        undo.undo()
        XCTAssertEqual(Options.shared.buttons.binding.first?.label, label("Reload All", symbol: "arrow.clockwise"))

        // An app's own button, the same way.
        let savedApplications = Options.shared.application.applications
        addTeardownBlock { Options.shared.application.applications = savedApplications }
        let notes = Application(path: "/System/Applications/Notes.app")
        notes.setOwnButtonBindings([back])
        Options.shared.application.applications = EnhanceArray<Application>(withArray: [notes], matchKey: "path")
        let part = ApplicationButtonsViewController(application: notes)
        part.paneUndoManager = undo
        part.startRecording = { _ in }
        part.stopRecording = {}
        part.openActionMenu = { _ in }
        _ = part.view
        let own = try XCTUnwrap(part.rows.first { $0.binding.id == back.id })
        quiet(own.pullDown)
        own.pullDown.shortcutSelected(try keyboardShortcutItem(of: own.pullDown))
        let ownPopover = try XCTUnwrap(own.pullDown.detailsPopover as? QuietPopover)
        let ownEditor = try XCTUnwrap(ownPopover.labelEditor)
        type("Reload Page", into: ownEditor.nameField, of: ownEditor)
        undo.beginUndoGrouping()
        part.list.onRemove?(back.id)
        undo.endUndoGrouping()
        XCTAssertTrue(notes.ownButtonBindings.isEmpty)
        undo.undo()
        XCTAssertEqual(notes.ownButtonBindings.first?.label, label("Reload Page", symbol: "arrow.clockwise"))
    }

    // MARK: The recorder hands its popover on

    private final class FakeTap: KeyRecordingTap {
        private(set) var stops = 0
        func stop() { stops += 1 }
    }

    private final class Delegate: KeyRecorderDelegate {
        var keeps = true
        var isNew = true
        var log: [String] = []
        func onRecordingStarted(_ recorder: KeyRecorder) { log.append("started") }
        func onEventRecorded(_ recorder: KeyRecorder, didRecordEvent event: InputEvent, isDuplicate: Bool) {
            log.append(isDuplicate ? "refused" : "recorded")
        }
        func onRecordingStopped(_ recorder: KeyRecorder, didRecord: Bool) { log.append("stopped \(didRecord)") }
        func validateRecordedEvent(_ recorder: KeyRecorder, event: InputEvent) -> Bool { return isNew }
        func takesPopover(_ recorder: KeyRecorder, _ popover: KeyPopover) -> Bool {
            log.append("asked")
            guard keeps else { return false }
            popover.turnToDetails(label: nil)
            return true
        }
    }

    private func startRecorder(_ delegate: Delegate) -> (KeyRecorder, FakeTap, QuietPopover, NSView) {
        let recorder = KeyRecorder()
        let tap = FakeTap()
        let popover = QuietPopover()
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 24, height: 22))
        recorder.delegate = delegate
        recorder.isSecureInputOn = { false }
        recorder.makePopover = { popover }
        recorder.makeEventTap = { _, _ in tap }
        recorder.startRecording(from: anchor, mode: .adaptive)
        addTeardownBlock { [weak self] in
            recorder.stopRecording()
            self?.spin(KeyRecorder.restartDelay + 0.1)
        }
        return (recorder, tap, popover, anchor)
    }

    /// After a recording the recorder asks its delegate once whether it keeps the
    /// popover. Kept: the tap is gone (the keyboard types again), the popover stays open
    /// with the details, and the next recording can start in it at once.
    func testTheRecorderLeavesItsPopoverOpenForTheDelegateThatTakesIt() {
        let delegate = Delegate()
        let (recorder, tap, popover, anchor) = startRecorder(delegate)
        XCTAssertTrue(popover.isOpen)
        NotificationCenter.default.post(name: KeyRecorder.FINISH_NOTI_NAME, object: shiftCommandRPressed)
        XCTAssertEqual(delegate.log, ["started", "recorded"])
        XCTAssertEqual(tap.stops, 0, "the tap stays for the moment of feedback")
        spin(KeyRecorder.recordingFeedbackDelay(isDuplicate: false) + 0.2)
        XCTAssertEqual(delegate.log, ["started", "recorded", "asked", "stopped true"])
        XCTAssertEqual(tap.stops, 1)
        XCTAssertTrue(popover.isOpen, "not closed")
        XCTAssertTrue(popover.isShowingDetails)

        // "Record Again", right away: the same popover asks for keys again.
        recorder.startRecording(from: anchor, mode: .adaptive, in: popover)
        XCTAssertEqual(delegate.log.last, "started")
        XCTAssertTrue(popover.isOpen)
        XCTAssertFalse(popover.isShowingDetails)
        XCTAssertEqual(popover.testingWaitingText, KeyRecordingMode.adaptive.waitingHint)
        // Esc there ends the recording and closes the popover, as ever.
        NotificationCenter.default.post(name: KeyRecorder.CANCEL_NOTI_NAME, object: nil)
        XCTAssertEqual(delegate.log.last, "stopped false")
        XCTAssertFalse(popover.isOpen)
    }

    /// A delegate that does not take it (every other use of the recorder), and a press
    /// that was refused: the popover closes as before.
    func testTheRecorderClosesItsPopoverOtherwise() {
        let plain = Delegate()
        plain.keeps = false
        let (_, _, popover, _) = startRecorder(plain)
        NotificationCenter.default.post(name: KeyRecorder.FINISH_NOTI_NAME, object: shiftCommandRPressed)
        spin(KeyRecorder.recordingFeedbackDelay(isDuplicate: false) + 0.2)
        XCTAssertEqual(plain.log, ["started", "recorded", "asked", "stopped true"])
        XCTAssertFalse(popover.isOpen)

        let refusing = Delegate()
        refusing.isNew = false
        let (_, _, refused, _) = startRecorder(refusing)
        NotificationCenter.default.post(name: KeyRecorder.FINISH_NOTI_NAME, object: shiftCommandRPressed)
        spin(KeyRecorder.recordingFeedbackDelay(isDuplicate: true) + 0.2)
        XCTAssertEqual(refusing.log, ["started", "refused", "stopped true"], "never asked for a refused press")
        XCTAssertFalse(refused.isOpen)
    }
}
