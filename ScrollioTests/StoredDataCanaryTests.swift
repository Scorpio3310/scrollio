import XCTest
@testable import Scrollio_Debug

/// What the settings are stored under and how a removed item comes back. The redesign of
/// General, Buttons and Apps changed none of it; "Which button is this?" added one optional
/// field to a binding's trigger, on purpose, and the Welcome Guide one Int of its own. The
/// keys and values below are frozen, never derive them from production code. ("Show in
/// menu bar" over `hideStatusItem`:
/// PreferencesGeneralTests; bindings: PreferencesButtonsTests
/// .testStoredBindingsLoadAndSaveUnchanged; apps: PreferencesApplicationTests
/// .testStoredAppsLoadAndSaveUnchanged; wheel: LogiWheelSettingsPersistenceTests; Logitech
/// mouse: LogiMouseSettingsPersistenceTests.)
final class StoredDataCanaryTests: XCTestCase {

    func testTheSettingsKeysAreFrozen() {
        XCTAssertEqual(OptionItem.General.OptionsExist, "optionsExist")
        XCTAssertEqual(OptionItem.General.HideStatusItem, "hideStatusItem")
        XCTAssertEqual(OptionItem.General.WelcomeGuideCompletedVersion, "welcomeGuideCompletedVersion")
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
        XCTAssertEqual(OptionItem.ThumbWheel.Settings, "thumbWheelSettings")
        XCTAssertEqual(OptionItem.Application.Allowlist, "allowlist")
        XCTAssertEqual(OptionItem.Application.Applications, "applications")
        // Window state only, not settings.
        XCTAssertEqual(PreferencesSplitViewController.selectedPaneDefaultsKey, "preferencesSelectedPane")
        XCTAssertEqual(PreferencesScrollingViewController.advancedExpandedDefaultsKey, "scrollingAdvancedExpanded")
        XCTAssertEqual(PreferencesGeneralViewController.advancedExpandedDefaultsKey, "generalAdvancedExpanded")
    }

    // MARK: - The Welcome Guide

    /// The one value the Welcome Guide added, deliberately: an Int under
    /// "welcomeGuideCompletedVersion", 0 while a new user has not finished the guide, 1 once
    /// it was finished (written once, silently, for settings that existed before the guide).
    /// It is the only thing the guide stores (its feel step goes through the Scrolling
    /// pane's own path); `readOptions` and the saves never read or write it.
    func testTheWelcomeGuideStoresOneIntUnderAFrozenKey() throws {
        let store = TestDefaults.makeStore(for: self)
        let defaults = store.defaults
        let suite = store.suiteName
        let progress = WelcomeGuideProgress(defaults: defaults)

        progress.settleAtLaunch(isNewInstallation: true)
        XCTAssertEqual(defaults.persistentDomain(forName: suite) as NSDictionary?, ["welcomeGuideCompletedVersion": 0])
        progress.markFinished()
        XCTAssertEqual(defaults.persistentDomain(forName: suite) as NSDictionary?, ["welcomeGuideCompletedVersion": 1])

        defaults.removePersistentDomain(forName: suite)
        progress.settleAtLaunch(isNewInstallation: false)
        XCTAssertEqual(defaults.persistentDomain(forName: suite) as NSDictionary?, ["welcomeGuideCompletedVersion": 1])
        XCTAssertEqual(WelcomeGuideProgress.currentVersion, 1)
        XCTAssertEqual(WelcomeGuideProgress.notFinished, 0)
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

/// The saving of the settings, into a store of the test's own (`Options.defaults`): what
/// each value is written under, and that what this version cannot read survives a save.
/// The keys below are frozen literals, never taken from production code.
final class StoredSettingsSaveTests: XCTestCase {

    private func makeOptions() -> (Options, UserDefaults) {
        let defaults = TestDefaults.make(for: self)
        let options = Options()
        options.defaults = defaults
        return (options, defaults)
    }

    /// Every scroll setting under its own key (speed and step saved under each other's key
    /// went unnoticed by every test), and read back as it was saved.
    func testEveryScrollSettingIsSavedUnderItsOwnKeyAndReadBack() throws {
        let (options, defaults) = makeOptions()
        options.scroll.smooth = false
        options.scroll.reverse = false
        options.scroll.reverseVertical = false
        options.scroll.reverseHorizontal = false
        options.scroll.dash = ScrollHotkey(type: .keyboard, code: 61)
        options.scroll.toggle = nil
        options.scroll.block = ScrollHotkey(type: .mouse, code: 4)
        options.scroll.step = 44.5
        options.scroll.speed = 7.25
        options.scroll.duration = 2.75
        options.scroll.deadZone = 1.5
        options.scroll.smoothSimTrackpad = true

        options.saveOptions()

        XCTAssertEqual(defaults.string(forKey: "optionsExist"), "optionsExist")
        XCTAssertEqual(defaults.object(forKey: "smooth") as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: "reverse") as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: "reverseVertical") as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: "reverseHorizontal") as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: "step") as? Double, 44.5)
        XCTAssertEqual(defaults.object(forKey: "speed") as? Double, 7.25)
        XCTAssertEqual(defaults.object(forKey: "duration") as? Double, 2.75)
        XCTAssertEqual(defaults.object(forKey: "deadZone") as? Double, 1.5)
        XCTAssertEqual(defaults.object(forKey: "smoothSimTrackpad") as? Bool, true)
        XCTAssertEqual(defaults.object(forKey: "smoothVertical") as? Bool, true)
        XCTAssertEqual(defaults.object(forKey: "smoothHorizontal") as? Bool, true)
        let dash = try JSONDecoder().decode(ScrollHotkey.self, from: try XCTUnwrap(defaults.data(forKey: "dash")))
        XCTAssertEqual(dash, ScrollHotkey(type: .keyboard, code: 61))
        XCTAssertNil(defaults.object(forKey: "toggle"), "a key the user removed is stored as no key")
        let block = try JSONDecoder().decode(ScrollHotkey.self, from: try XCTUnwrap(defaults.data(forKey: "block")))
        XCTAssertEqual(block, ScrollHotkey(type: .mouse, code: 4))

        let read = Options()
        read.defaults = defaults
        read.readOptions()
        XCTAssertFalse(read.scroll.smooth)
        XCTAssertFalse(read.scroll.reverse)
        XCTAssertFalse(read.scroll.reverseVertical)
        XCTAssertFalse(read.scroll.reverseHorizontal)
        XCTAssertEqual(read.scroll.dash, ScrollHotkey(type: .keyboard, code: 61))
        XCTAssertNil(read.scroll.toggle)
        XCTAssertEqual(read.scroll.block, ScrollHotkey(type: .mouse, code: 4))
        XCTAssertEqual(read.scroll.step, 44.5)
        XCTAssertEqual(read.scroll.speed, 7.25)
        XCTAssertEqual(read.scroll.duration, 2.75)
        XCTAssertEqual(read.scroll.deadZone, 1.5)
        XCTAssertTrue(read.scroll.smoothSimTrackpad)
    }

    /// The other groups, each under its own key, and read back.
    func testTheOtherGroupsAreSavedUnderTheirOwnKeysAndReadBack() throws {
        let (options, defaults) = makeOptions()
        options.application.allowlist = true
        var gesture = MouseGestureSettings.default
        gesture.invertHorizontal.toggle()
        gesture.trackingSpeed = 2.5
        options.gesture = gesture
        var wheel = LogiWheelSettings.default
        wheel.managedByScrollio = true
        wheel.smartShiftSensitivity = 37
        options.logiWheel = wheel
        var thumbWheel = ThumbWheelSettings.default
        thumbWheel.function = .zoom
        thumbWheel.speed = 2
        thumbWheel.swapsDirection = true
        options.thumbWheel = thumbWheel

        options.saveOptions()

        XCTAssertEqual(defaults.object(forKey: "allowlist") as? Bool, true)
        XCTAssertEqual(try JSONDecoder().decode(MouseGestureSettings.self, from: try XCTUnwrap(defaults.data(forKey: "mouseGestureSettings"))), gesture)
        XCTAssertEqual(try JSONDecoder().decode(LogiWheelSettings.self, from: try XCTUnwrap(defaults.data(forKey: "logiWheelSettings"))), wheel)
        XCTAssertEqual(try JSONDecoder().decode(ThumbWheelSettings.self, from: try XCTUnwrap(defaults.data(forKey: "thumbWheelSettings"))), thumbWheel)
        XCTAssertNotNil(defaults.data(forKey: "logiMouseSettings"))
        XCTAssertNotNil(defaults.data(forKey: "buttonBindings"))
        XCTAssertNotNil(defaults.data(forKey: "applications"))

        let read = Options()
        read.defaults = defaults
        read.readOptions()
        XCTAssertTrue(read.application.allowlist)
        XCTAssertEqual(read.gesture, gesture)
        XCTAssertEqual(read.logiWheel, wheel)
        XCTAssertTrue(read.logiMouseManaged)
        XCTAssertEqual(read.thumbWheel, thumbWheel)
        XCTAssertEqual(read.logiMouse, options.logiMouse)
    }

    /// Bindings and per-app entries that a newer version stored and this one cannot read
    /// are written back at a save (dropping them went unnoticed by every test): a user who
    /// goes back to an older version and forward again keeps them.
    func testWhatThisVersionCannotReadSurvivesASave() throws {
        let (options, defaults) = makeOptions()
        let known = #"{"id":"11111111-1111-1111-1111-111111111111","triggerEvent":{"type":"mouse","code":3,"modifiers":0,"#
            + #""displayComponents":["🖱4"],"deviceFilter":null},"systemShortcutName":"copy","isEnabled":true,"createdAt":0}"#
        let future = #"{"id":"22222222-2222-2222-2222-222222222222","futureTrigger":{"kind":"chord","keys":[1,2]},"schema":9}"#
        defaults.set("optionsExist", forKey: "optionsExist")
        defaults.set(Data(("[" + known + "," + future + "]").utf8), forKey: "buttonBindings")
        defaults.set(Data(("[" + StoredDataCanaryTests.readableApp + "," + StoredDataCanaryTests.unreadableApp + "]").utf8), forKey: "applications")

        options.readOptions()
        XCTAssertEqual(options.buttons.binding.map(\.systemShortcutName), ["copy"])
        XCTAssertEqual(options.application.applications.count, 1)

        // The user adds a binding, and everything is saved.
        let trigger = RecordedEvent(type: .mouse, code: 4, modifiers: 0, displayComponents: ["🖱5"], deviceFilter: nil)
        options.buttons.binding.append(ButtonBinding(triggerEvent: trigger, systemShortcutName: "paste", isEnabled: true))
        options.saveOptions()

        let bindings = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(defaults.data(forKey: "buttonBindings"))) as? [[String: Any]])
        XCTAssertEqual(bindings.count, 3)
        XCTAssertEqual(bindings.compactMap { $0["systemShortcutName"] as? String }, ["copy", "paste"])
        let kept = try XCTUnwrap(bindings.last)
        let stored = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(future.utf8)) as? [String: Any])
        XCTAssertEqual(kept as NSDictionary, stored as NSDictionary, "the binding of a newer version, as it was stored")

        let apps = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(defaults.data(forKey: "applications"))) as? [[String: Any]])
        XCTAssertEqual(apps.compactMap { $0["path"] as? String }, ["/Applications/A.app", "/Applications/B.app"])
        XCTAssertEqual(apps.last?["future"] as? [Int], [1, 2])
    }

    /// The way the app saves while it runs: a change marks its group, and the next flush
    /// writes that group and no other.
    func testAChangeIsWrittenAtTheNextFlushAndOnlyItsGroup() {
        let defaults = TestDefaults.make(for: self)
        let options = Options.shared
        options.flushPendingSaves()   // what earlier tests left pending goes nowhere
        let speed = options.scroll.speed
        options.defaults = defaults
        defer {
            options.defaults = .standard
            options.scroll.speed = speed
        }

        options.scroll.speed = 3.25
        XCTAssertNil(defaults.object(forKey: "speed"), "not before the flush")
        options.flushPendingSaves()

        XCTAssertEqual(defaults.object(forKey: "speed") as? Double, 3.25)
        XCTAssertEqual(defaults.string(forKey: "optionsExist"), "optionsExist")
        XCTAssertNil(defaults.object(forKey: "buttonBindings"), "a group that did not change is not written")
        XCTAssertNil(defaults.object(forKey: "applications"))
        XCTAssertNil(defaults.object(forKey: "mouseGestureSettings"))
    }
}
