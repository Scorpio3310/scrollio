import XCTest
@testable import Mos_Debug

/// What the settings are stored under and how a removed item comes back. The redesign of
/// General, Buttons and Apps changed none of it: the keys and values below are frozen, never
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
