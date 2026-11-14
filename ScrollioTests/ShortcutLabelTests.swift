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
    /// smaller, the two together inside the round drop, on screen and in the pane.
    func testTheMiddleShowsTheNameOverSmallerKeysWithinItsRoom() {
        let widest = String(repeating: "W", count: ShortcutLabel.maximumNameLength)
        let names = ["Reload", "Reload Without Cache", "Paste and Match Style", widest, "Wwwwwwwwwwww Wwwwwwwwwww"]
        let combinations = [keys, "Fn⌃⌥⇧⌘Space", "⌃⌥⇧⌘F19"]
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

    /// The Gestures pane has no recorder: a direction or the click takes a listed action
    /// only, and a recorded key combination stored there runs nothing. So nothing there
    /// can carry a name. When a direction learns to send a recorded combination, its
    /// name and icon have to come with it: this test says where to look.
    func testADirectionOfGestureNavigationTakesNoRecordedCombinationYet() {
        let controls = MouseGestureSettingsControls(showLogiActions: true, isInteractiveAvailable: { true })
        func markers(_ menu: NSMenu?) -> [String] {
            return (menu?.items ?? []).flatMap { item -> [String] in
                return [item.representedObject as? String].compactMap { $0 } + markers(item.submenu)
            }
        }
        for popUp in controls.actionPopUps {
            let offered = markers(popUp.menu)
            XCTAssertFalse(offered.contains(ShortcutManager.MenuMarker.keyboardShortcut), "no \"Keyboard Shortcut…\" here")
            XCTAssertFalse(offered.contains { $0.hasPrefix("custom::") })
        }
        XCTAssertFalse(StoredAction.isKnown(gestureAction: shiftCommandR), "a direction does not run a recorded combination")
        XCTAssertNil(ShortcutExecutor.shared.resolveAction(named: shiftCommandR))
    }
}
