import XCTest
@testable import Mos_Debug

/// What the settings are stored under and how a removed item comes back. The redesign of
/// General, Buttons and Apps changed none of it; "Which button is this?" added one optional
/// field to a binding's trigger, on purpose. The keys and values below are frozen, never
/// derive them from production code. ("Show in menu bar" over `hideStatusItem`:
/// PreferencesGeneralTests; bindings: PreferencesButtonsTests
/// .testStoredBindingsLoadAndSaveUnchanged; apps: PreferencesApplicationTests
/// .testStoredAppsLoadAndSaveUnchanged; wheel: LogiWheelSettingsPersistenceTests; Logitech
/// mouse: LogiMouseSettingsPersistenceTests.)
final class StoredDataCanaryTests: XCTestCase {

    func testTheSettingsKeysAreFrozen() {
        XCTAssertEqual(OptionItem.General.OptionsExist, "optionsExist")
        XCTAssertEqual(OptionItem.General.HideStatusItem, "hideStatusItem")
        XCTAssertEqual(
            [OptionItem.Scroll.Smooth, OptionItem.Scroll.Reverse, OptionItem.Scroll.ReverseVertical,
             OptionItem.Scroll.ReverseHorizontal, OptionItem.Scroll.Dash, OptionItem.Scroll.Toggle,
             OptionItem.Scroll.Block, OptionItem.Scroll.Step, OptionItem.Scroll.Speed,
             OptionItem.Scroll.Duration, OptionItem.Scroll.DeadZone, OptionItem.Scroll.SmoothSimTrackpad,
             OptionItem.Scroll.SmoothVertical, OptionItem.Scroll.SmoothHorizontal],
            ["smooth", "reverse", "reverseVertical", "reverseHorizontal", "dash", "toggle", "block",
             "step", "speed", "duration", "deadZone", "smoothSimTrackpad", "smoothVertical", "smoothHorizontal"]
        )
        XCTAssertEqual(OptionItem.Button.Bindings, "buttonBindings")
        XCTAssertEqual(OptionItem.Gesture.Settings, "mouseGestureSettings")
        XCTAssertEqual(OptionItem.MouseWheel.Settings, "logiWheelSettings")
        XCTAssertEqual(OptionItem.MouseBasics.Settings, "logiMouseSettings")
        XCTAssertEqual(OptionItem.Application.Allowlist, "allowlist")
        XCTAssertEqual(OptionItem.Application.Applications, "applications")
        // Window state only, not settings.
        XCTAssertEqual(PreferencesSplitViewController.selectedPaneDefaultsKey, "preferencesSelectedPane")
        XCTAssertEqual(PreferencesScrollingViewController.advancedExpandedDefaultsKey, "scrollingAdvancedExpanded")
        XCTAssertEqual(PreferencesGeneralViewController.advancedExpandedDefaultsKey, "generalAdvancedExpanded")
    }

    // MARK: - A button's place ("Which button is this?")

    /// The one field the Buttons pane added to a stored binding, deliberately: the trigger's
    /// optional "mousePart", only where the user said where a numbered button is, with
    /// these values. Frozen like the keys above.
    func testATriggersPlaceIsOneOptionalFieldWithFrozenValues() throws {
        XCTAssertEqual(PlacedMousePart.allCases.map(\.rawValue),
                       ["gestureButton", "thumbPanel", "backButton", "forwardButton", "modeShiftButton", "middleButton"])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let plain = RecordedEvent(type: .mouse, code: 6, modifiers: 0, deviceFilter: nil)
        XCTAssertEqual(String(decoding: try encoder.encode(plain), as: UTF8.self),
                       #"{"code":6,"modifiers":0,"type":"mouse"}"#)
        XCTAssertEqual(String(decoding: try encoder.encode(plain.placed(at: .gestureButton)), as: UTF8.self),
                       #"{"code":6,"modifiers":0,"mousePart":"gestureButton","type":"mouse"}"#)
        XCTAssertEqual(String(decoding: try encoder.encode(plain.placed(at: .thumbPanel).placed(at: nil)), as: UTF8.self),
                       #"{"code":6,"modifiers":0,"type":"mouse"}"#, "taken back: as before")
    }

    /// Bindings stored before the field read and write back byte for byte; a binding with a
    /// place comes back with it; a value this version does not know (or of another type)
    /// reads as no place and the binding stays a binding (it is not set aside as unknown).
    func testStoredBindingsRoundTripWithAndWithoutAPlace() throws {
        let old = #"[{"createdAt":700000000,"id":"0B9C2C9E-6C51-4A57-9C2E-8E2B1E4C1A11","isEnabled":true,"#
            + #""systemShortcutName":"mouseGestureNavigation","triggerEvent":{"code":6,"modifiers":0,"type":"mouse"}},"#
            + #"{"createdAt":700000001,"id":"0B9C2C9E-6C51-4A57-9C2E-8E2B1E4C1A12","isEnabled":true,"#
            + #""systemShortcutName":"custom::21:1179648","triggerEvent":{"code":5,"modifiers":524288,"type":"mouse"}}]"#
        let placed = old
            .replacingOccurrences(of: #"{"code":6,"modifiers":0,"type":"mouse"}"#, with: #"{"code":6,"modifiers":0,"mousePart":"gestureButton","type":"mouse"}"#)
            .replacingOccurrences(of: #"{"code":5,"modifiers":524288,"type":"mouse"}"#, with: #"{"code":5,"modifiers":524288,"mousePart":"thumbPanel","type":"mouse"}"#)
        XCTAssertNotEqual(placed, old)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        // Old in, the same out (read the way Options reads them).
        let oldResult = Options.decodeButtonBindingsWithUnknowns(from: Data(old.utf8))
        XCTAssertEqual(oldResult.bindings.count, 2)
        XCTAssertTrue(oldResult.unknownElements.isEmpty)
        XCTAssertEqual(oldResult.bindings.map(\.triggerEvent.mousePart), [nil, nil])
        XCTAssertEqual(String(decoding: try encoder.encode(oldResult.bindings), as: UTF8.self), old)

        // With a place: it comes back, and so do the bytes.
        let placedResult = Options.decodeButtonBindingsWithUnknowns(from: Data(placed.utf8))
        XCTAssertEqual(placedResult.bindings.map(\.triggerEvent.mousePart), [.gestureButton, .thumbPanel])
        XCTAssertTrue(placedResult.unknownElements.isEmpty)
        XCTAssertEqual(String(decoding: try encoder.encode(placedResult.bindings), as: UTF8.self), placed)
        XCTAssertEqual(placedResult.bindings, oldResult.bindings, "the same triggers and actions")

        // A value this version does not know, or of another type: no place, nothing lost.
        for strange in [#""mousePart":"wheelTilt","#, #""mousePart":7,"#, #""mousePart":null,"#] {
            let json = old.replacingOccurrences(of: #"{"code":6,"modifiers":0,"#, with: #"{"code":6,"# + strange + #""modifiers":0,"#)
            XCTAssertNotEqual(json, old)
            let result = Options.decodeButtonBindingsWithUnknowns(from: Data(json.utf8))
            XCTAssertEqual(result.bindings.count, 2, strange)
            XCTAssertTrue(result.unknownElements.isEmpty, strange)
            XCTAssertNil(result.bindings[0].triggerEvent.mousePart, strange)
            XCTAssertEqual(String(decoding: try encoder.encode(result.bindings), as: UTF8.self), old, strange)
        }
    }

    // MARK: - A per-app list with an entry this version cannot read

    /// A stored app with every scroll key, as this version writes it.
    static let readableApp = #"{"displayName":"","inherit":false,"path":"\/Applications\/A.app","#
        + #""scroll":{"block":{"code":55,"type":"keyboard"},"deadZone":1,"duration":3.69,"reverse":true,"#
        + #""reverseHorizontal":true,"reverseVertical":true,"smooth":true,"smoothHorizontal":true,"#
        + #""smoothSimTrackpad":false,"smoothVertical":true,"speed":2.5,"step":33.6,"#
        + #""toggle":{"code":56,"type":"keyboard"}}}"#
    /// One this version cannot read: its scroll options are of a shape it does not know.
    static let unreadableApp = #"{"inherit":false,"path":"\/Applications\/B.app","scroll":{"glide":"later"},"future":[1,2]}"#

    /// One entry this version could not read made the whole stored list be removed. Each
    /// entry is read on its own now: the readable ones load, the others are kept as stored
    /// and saved back after them. A list without such entries is written byte for byte as
    /// before.
    func testAnAppsListWithAnEntryThisVersionCannotReadKeepsEverything() throws {
        let stored = Data(("[" + Self.readableApp + "," + Self.unreadableApp + "]").utf8)
        XCTAssertThrowsError(try JSONDecoder().decode([Application].self, from: stored),
                             "as a whole the list cannot be read")

        let result = try XCTUnwrap(Options.decodeApplicationsWithUnknowns(from: stored))
        XCTAssertEqual(result.applications.map(\.path), ["/Applications/A.app"])
        XCTAssertEqual(result.applications.first?.inherit, false)
        XCTAssertEqual(result.applications.first?.scroll.speed, 2.5)
        XCTAssertEqual(result.applications.first?.scroll.dash, nil)
        XCTAssertEqual(result.unknownElements.count, 1)
        let unreadable = try JSONSerialization.jsonObject(with: Data(Self.unreadableApp.utf8)) as? NSDictionary
        XCTAssertEqual(result.unknownElements.first as? NSDictionary, unreadable, "kept as stored")

        // Saved: the readable app as this version writes it, then the kept entry.
        let known = try JSONEncoder().encode(result.applications)
        let saved = try XCTUnwrap(Options.applicationsDataForSaving(known: known, preservedUnknown: result.unknownElements))
        let savedList = try XCTUnwrap(try JSONSerialization.jsonObject(with: saved) as? [NSDictionary])
        let readable = try JSONSerialization.jsonObject(with: Data(Self.readableApp.utf8)) as? NSDictionary
        XCTAssertEqual(savedList, [readable, unreadable].compactMap { $0 })
        // Read again: the same app, the same kept entry.
        let again = try XCTUnwrap(Options.decodeApplicationsWithUnknowns(from: saved))
        XCTAssertEqual(again.applications.map(\.path), ["/Applications/A.app"])
        XCTAssertEqual(again.unknownElements.first as? NSDictionary, unreadable)

        // Without kept entries the bytes are those of the apps it knows, untouched.
        XCTAssertEqual(Options.applicationsDataForSaving(known: known, preservedUnknown: []), known)
        let readableOnly = Data(("[" + Self.readableApp + "]").utf8)
        XCTAssertEqual(Options.applicationsDataForSaving(known: readableOnly, preservedUnknown: []), readableOnly)

        // B.app added again, readable this time: its kept entry is not stored a second time.
        let readded = Data(("[" + Self.readableApp + "," + Self.readableApp.replacingOccurrences(of: "A.app", with: "B.app") + "]").utf8)
        let once = try XCTUnwrap(Options.applicationsDataForSaving(known: readded, preservedUnknown: result.unknownElements))
        let onceList = try XCTUnwrap(try JSONSerialization.jsonObject(with: once) as? [NSDictionary])
        XCTAssertEqual(onceList.compactMap { $0["path"] as? String }, ["/Applications/A.app", "/Applications/B.app"])
        XCTAssertNil(onceList.last?["future"], "the readable entry wins")

        // Not a list at all: nothing to keep (the list is reset, as before).
        XCTAssertNil(Options.decodeApplicationsWithUnknowns(from: Data(#"{"path":"\/Applications\/A.app"}"#.utf8)))
    }

    /// Undo of "Remove App" puts the very object back where it was (EnhanceArray.insert):
    /// the stored JSON is what it was before the removal, and lookups by path
    /// (what ScrollUtils uses) find every app again.
    func testInsertPutsARemovedAppBackExactlyWhereItWas() throws {
        let a = Application(path: "/Applications/A.app")
        a.inherit = false
        a.scroll.speed = 2.5
        let b = Application(path: "/Applications/B.app")
        b.displayName = "Bee"
        let c = Application(path: "/Applications/C.app")
        var changes = 0
        let store = EnhanceArray<Application>(withArray: [a, b, c], matchKey: "path", forObserver: { changes += 1 })
        let before = try XCTUnwrap(store.json())

        store.remove(at: 1)
        XCTAssertNil(store.get(by: b.path))
        XCTAssertTrue(store.get(by: c.path) === c, "lookups follow the removal")

        changes = 0
        store.insert(b, at: 1)
        XCTAssertEqual(changes, 1, "putting it back is a change that is saved")
        XCTAssertTrue(store.get(by: a.path) === a)
        XCTAssertTrue(store.get(by: b.path) === b)
        XCTAssertTrue(store.get(by: c.path) === c)
        // The same JSON (JSONEncoder's key order varies between runs: compared as objects).
        XCTAssertEqual(
            try JSONSerialization.jsonObject(with: try XCTUnwrap(store.json())) as? NSArray,
            try JSONSerialization.jsonObject(with: before) as? NSArray
        )

        // An index the shorter list no longer has appends; a negative one puts it first.
        store.remove(at: 2)
        store.remove(at: 1)
        store.insert(c, at: 7)
        store.insert(b, at: -1)
        XCTAssertEqual((0..<store.count).compactMap { store.get(by: $0)?.path }, [b.path, a.path, c.path])
    }
}
