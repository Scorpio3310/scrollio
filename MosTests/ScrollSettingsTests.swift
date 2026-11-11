//
//  ScrollSettingsTests.swift
//  MosTests
//
//  The model behind the Scrolling tab: the five Feel presets, the slider ranges, the one
//  direction switch, and the clean-up that runs when settings load.
//

import XCTest
@testable import Mos_Debug

final class ScrollSettingsTests: XCTestCase {

    /// The stored form of scroll options, with the keys in a fixed order so two can be compared.
    private func stored(_ scroll: OPTIONS_SCROLL_DEFAULT) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return String(decoding: try encoder.encode(scroll), as: UTF8.self)
    }

    // MARK: - Feel

    func testFeel_presetsAreTheFiveDurationsInOrder() {
        XCTAssertEqual(ScrollFeel.allCases, [.direct, .quick, .smooth, .glide, .float])
        XCTAssertEqual(ScrollFeel.allCases.map(\.duration), [2.0, 3.13, 3.69, 4.35, 4.6])
        XCTAssertEqual(ScrollFeel.allCases.map(\.rawValue), [0, 1, 2, 3, 4], "the segment of the control")
    }

    func testFeel_smoothIsTheDefaultOfTheModel() {
        XCTAssertEqual(ScrollFeel.default, .smooth)
        XCTAssertEqual(OPTIONS_SCROLL_DEFAULT().duration, 3.69)
        XCTAssertEqual(OPTIONS_SCROLL_DEFAULT().speed, 6.3)
        XCTAssertEqual(OPTIONS_SCROLL_DEFAULT().step, 33.6)
        XCTAssertEqual(OPTIONS_SCROLL_DEFAULT().duration, ScrollFeel.default.duration)
    }

    func testFeel_presetsFitTheGlideTimeSlider() {
        let slider = ScrollSliderSetting.glideTime
        for feel in ScrollFeel.allCases {
            XCTAssertTrue(slider.range.contains(feel.duration), "\(feel)")
            XCTAssertEqual(slider.snapped(feel.duration), feel.duration, "\(feel) lies on the slider's grid")
        }
    }

    func testFeel_matchingNeedsThePresetsDuration() {
        for feel in ScrollFeel.allCases {
            XCTAssertEqual(ScrollFeel.matching(duration: feel.duration), feel)
            XCTAssertEqual(ScrollFeel.matching(duration: feel.duration + 0.005), feel, "within the tolerance")
            XCTAssertEqual(ScrollFeel.matching(duration: feel.duration - 0.005), feel, "within the tolerance")
            XCTAssertNil(ScrollFeel.matching(duration: feel.duration + 0.01), "the next step of the slider is custom")
            XCTAssertNil(ScrollFeel.matching(duration: feel.duration - 0.01))
        }
        let customs: [Double] = [1.0, 2.5, 3.9, 4.75, 5.0, .nan, .infinity]
        for custom in customs {
            XCTAssertNil(ScrollFeel.matching(duration: custom), "\(custom)")
        }
    }

    func testFeel_namesAndHints() {
        XCTAssertEqual(ScrollFeel.allCases.map(\.localizedName), ["Direct", "Quick", "Smooth", "Glide", "Float"])
        let hints: [String] = ScrollFeel.allCases.map(\.localizedHint) + [ScrollFeel.customHint]
        XCTAssertEqual(Set(hints).count, hints.count, "every choice has a line of its own")
        for feel in ScrollFeel.allCases {
            XCTAssertNotEqual(feel.localizedName, "scrolling-feel-\(feel.name)")
            XCTAssertNotEqual(feel.localizedHint, "scrolling-feel-\(feel.name)-hint")
            XCTAssertEqual(ScrollFeel.hint(for: feel), feel.localizedHint)
        }
        XCTAssertEqual(ScrollFeel.hint(for: nil), ScrollFeel.customHint)
        XCTAssertTrue(ScrollFeel.customHint.hasPrefix("Custom"))
    }

    // MARK: - Sliders

    func testSliders_ranges() {
        XCTAssertEqual(ScrollSliderSetting.speed.range, 1...10)
        XCTAssertEqual(ScrollSliderSetting.glideTime.range, 1...5)
        XCTAssertEqual(ScrollSliderSetting.smallestStep.range, 0.01...100)
        let defaults = OPTIONS_SCROLL_DEFAULT()
        XCTAssertTrue(ScrollSliderSetting.speed.range.contains(defaults.speed))
        XCTAssertTrue(ScrollSliderSetting.glideTime.range.contains(defaults.duration))
        XCTAssertTrue(ScrollSliderSetting.smallestStep.range.contains(defaults.step))
    }

    func testSliders_snapToTheirGridAndStayInRange() {
        let speed = ScrollSliderSetting.speed
        XCTAssertEqual(speed.snapped(6.5), 6.5)
        XCTAssertEqual(speed.snapped(2.7), 2.7)
        XCTAssertEqual(speed.snapped(2.74), 2.7)
        XCTAssertEqual(speed.snapped(2.76), 2.8)
        XCTAssertEqual(speed.snapped(0.2), 1)
        XCTAssertEqual(speed.snapped(42), 10)
        XCTAssertEqual(speed.snapped(.nan), 1)
        XCTAssertEqual(speed.snapped(.infinity), 1)

        let glide = ScrollSliderSetting.glideTime
        XCTAssertEqual(glide.snapped(3.694), 3.69)
        XCTAssertEqual(glide.snapped(3.696), 3.7)
        XCTAssertEqual(glide.snapped(0), 1)
        XCTAssertEqual(glide.snapped(9), 5)

        let step = ScrollSliderSetting.smallestStep
        XCTAssertEqual(step.snapped(33.6), 33.6, "the default lies on the grid")
        XCTAssertEqual(step.snapped(33.64), 33.6)
        XCTAssertEqual(step.snapped(0), 0.01)
        XCTAssertEqual(step.snapped(250), 100)
    }

    func testSliders_valueTexts() {
        XCTAssertEqual(ScrollSliderSetting.speed.text(6.5), "6.5")
        XCTAssertEqual(ScrollSliderSetting.speed.text(10), "10.0")
        XCTAssertEqual(ScrollSliderSetting.glideTime.text(3.69), "3.69")
        XCTAssertEqual(ScrollSliderSetting.glideTime.text(2), "2.00")
        XCTAssertEqual(ScrollSliderSetting.smallestStep.text(33.6), "33.6")
        XCTAssertEqual(ScrollSliderSetting.smallestStep.text(0.01), "0.01", "never shown as 0.0")
    }

    // MARK: - Direction

    func testReversesWheel_onTurnsOnTheMainFlagAndBothAxes() {
        let scroll = OPTIONS_SCROLL_DEFAULT()
        scroll.reverse = false
        scroll.reverseVertical = false
        scroll.reverseHorizontal = false
        XCTAssertFalse(scroll.reversesWheel)

        scroll.reversesWheel = true

        XCTAssertTrue(scroll.reverse)
        XCTAssertTrue(scroll.reverseVertical)
        XCTAssertTrue(scroll.reverseHorizontal)
        XCTAssertTrue(scroll.reversesWheel)
    }

    func testReversesWheel_offOnlyTurnsOffTheMainFlag() {
        let scroll = OPTIONS_SCROLL_DEFAULT()
        XCTAssertTrue(scroll.reversesWheel, "the default reverses the wheel")

        scroll.reversesWheel = false

        XCTAssertFalse(scroll.reverse)
        XCTAssertTrue(scroll.reverseVertical)
        XCTAssertTrue(scroll.reverseHorizontal)
        XCTAssertFalse(scroll.reversesWheel)
    }

    func testReversesWheel_readsWhatTheVerticalWheelDoes() {
        // Left over from the per-axis switches of older builds.
        let scroll = OPTIONS_SCROLL_DEFAULT()
        scroll.reverseVertical = false
        XCTAssertFalse(scroll.reversesWheel, "the wheel is not reversed, whatever the main flag says")
        scroll.reversesWheel = true
        XCTAssertTrue(scroll.reverseVertical)

        scroll.reverseHorizontal = false
        XCTAssertTrue(scroll.reversesWheel)
    }

    // MARK: - Clean-up on load

    func testNormalize_turnsBothSmoothAxesOn() {
        let scroll = OPTIONS_SCROLL_DEFAULT()
        scroll.smoothVertical = false
        scroll.smoothHorizontal = false
        ScrollSettingsCleanup.normalize(scroll)
        XCTAssertTrue(scroll.smoothVertical)
        XCTAssertTrue(scroll.smoothHorizontal)
    }

    func testNormalize_keepsSpeedInsideTheSlider() {
        let cases: [(stored: Double, expected: Double)] = [
            (6.5, 6.5), (1, 1), (10, 10), (2.73, 2.73),
            (0.4, 1), (0, 1), (-3, 1), (12, 10), (.infinity, 6.3), (.nan, 6.3),
        ]
        for (stored, expected) in cases {
            let scroll = OPTIONS_SCROLL_DEFAULT()
            scroll.speed = stored
            ScrollSettingsCleanup.normalize(scroll)
            XCTAssertEqual(scroll.speed, expected, "\(stored)")
        }
    }

    func testNormalize_leavesDurationStepAndEverythingElseAsStored() throws {
        let scroll = OPTIONS_SCROLL_DEFAULT()
        scroll.smooth = false
        scroll.reverse = false
        scroll.reverseVertical = false
        scroll.reverseHorizontal = true
        scroll.dash = nil
        scroll.toggle = ScrollHotkey(type: .keyboard, code: KeyCode.controlL)
        scroll.block = ScrollHotkey(type: .mouse, code: 4)
        scroll.step = 50
        scroll.speed = 6.5
        scroll.duration = 3.9
        scroll.deadZone = 2
        scroll.smoothSimTrackpad = true
        let before = try stored(scroll)

        ScrollSettingsCleanup.normalize(scroll)

        XCTAssertEqual(scroll.duration, 3.9, "a Duration that is no preset stays: it is a custom feel")
        XCTAssertEqual(scroll.step, 50, "Step is no longer forced to the default")
        XCTAssertEqual(try stored(scroll), before, "nothing else changes either")
    }

    func testNormalize_changesNothingOnceTheSettingsAreClean() throws {
        let scroll = OPTIONS_SCROLL_DEFAULT()
        scroll.speed = 12
        scroll.smoothVertical = false
        ScrollSettingsCleanup.normalize(scroll)
        let once = try stored(scroll)

        ScrollSettingsCleanup.normalize(scroll)
        XCTAssertEqual(try stored(scroll), once)

        // The defaults are clean to begin with.
        let defaults = OPTIONS_SCROLL_DEFAULT()
        ScrollSettingsCleanup.normalize(defaults)
        XCTAssertEqual(defaults, OPTIONS_SCROLL_DEFAULT())
    }

    func testRun_cleansTheGlobalOptionsAndEveryApplication() {
        let global = OPTIONS_SCROLL_DEFAULT()
        global.speed = 11
        global.smoothVertical = false
        global.duration = 4.9
        global.step = 12

        let own = Application(path: "/Applications/CleanupOwn.app")
        own.inherit = false
        own.scroll.speed = 0.3
        own.scroll.smoothHorizontal = false
        own.scroll.duration = 1.2
        let inheriting = Application(path: "/Applications/CleanupInherit.app")
        inheriting.scroll.speed = 99

        ScrollSettingsCleanup.run(global: global, applications: [own, inheriting], defaults: nil)

        XCTAssertEqual(global.speed, 10)
        XCTAssertTrue(global.smoothVertical)
        XCTAssertEqual(global.duration, 4.9)
        XCTAssertEqual(global.step, 12)
        XCTAssertEqual(own.scroll.speed, 1)
        XCTAssertTrue(own.scroll.smoothHorizontal)
        XCTAssertEqual(own.scroll.duration, 1.2)
        XCTAssertEqual(inheriting.scroll.speed, 10, "an app's own options are cleaned even while it inherits")
        XCTAssertTrue(inheriting.inherit)
    }

    func testRun_removesTheRetiredTrackpadDurationKey() throws {
        XCTAssertEqual(ScrollSettingsCleanup.retiredDefaultsKeys, ["durationForOtherTrackpadState"])
        let suite = "ScrollioTests.cleanup.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(4.5, forKey: "durationForOtherTrackpadState")
        defaults.set(3.69, forKey: OptionItem.Scroll.Duration)

        ScrollSettingsCleanup.run(global: OPTIONS_SCROLL_DEFAULT(), applications: [], defaults: defaults)

        XCTAssertNil(defaults.object(forKey: "durationForOtherTrackpadState"))
        XCTAssertEqual(defaults.double(forKey: OptionItem.Scroll.Duration), 3.69, "the settings in use stay")
    }

    /// An app's own options stored by the build that kept a Duration per state of
    /// "Trackpad-style events": they still load, and the next save no longer writes the key.
    func testPerAppOptions_loadWithTheRetiredKeyAndDropItOnTheNextSave() throws {
        let app = Application(path: "/Applications/Retired.app")
        app.inherit = false
        app.scroll.duration = 4.5
        app.scroll.smoothSimTrackpad = true
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(app)) as? [String: Any])
        var scroll = try XCTUnwrap(object["scroll"] as? [String: Any])
        XCTAssertNil(scroll["durationForOtherTrackpadState"], "today's model does not write the key")
        scroll["durationForOtherTrackpadState"] = 3.13
        object["scroll"] = scroll
        let stored = try JSONSerialization.data(withJSONObject: [object])

        let applications = try EnhanceArray<Application>(withData: stored, matchKey: "path")
        let loaded = try XCTUnwrap(applications.get(by: "/Applications/Retired.app"))
        XCTAssertEqual(loaded.scroll.duration, 4.5, "the Duration in use stays")
        XCTAssertTrue(loaded.scroll.smoothSimTrackpad)

        let saved = try XCTUnwrap(applications.json())
        XCTAssertFalse(try XCTUnwrap(String(data: saved, encoding: .utf8)).contains("durationForOtherTrackpadState"))
    }
}

/// `Options.readOptions()` runs the clean-up on what it has just read, for the global
/// options and for each app's own.
final class ScrollSettingsLoadTests: XCTestCase {

    private let defaults = UserDefaults.standard
    private var defaultsSnapshots: [(key: String, original: Any?)] = []
    private var originalScroll: OPTIONS_SCROLL_DEFAULT!
    private var originalApplications: EnhanceArray<Application>!

    override func setUp() {
        super.setUp()
        originalScroll = Options.shared.scroll
        originalApplications = Options.shared.application.applications
        // A fresh container, so loading never edits the one that is restored.
        Options.shared.scroll = OPTIONS_SCROLL_DEFAULT()
    }

    override func tearDown() {
        for snapshot in defaultsSnapshots {
            if let original = snapshot.original {
                defaults.set(original, forKey: snapshot.key)
            } else {
                defaults.removeObject(forKey: snapshot.key)
            }
        }
        defaultsSnapshots.removeAll()
        Options.shared.scroll = originalScroll
        Options.shared.application.applications = originalApplications
        originalScroll = nil
        originalApplications = nil
        super.tearDown()
    }

    private func store(_ value: Any, forKey key: String) {
        defaultsSnapshots.append((key: key, original: defaults.object(forKey: key)))
        defaults.set(value, forKey: key)
    }

    func testReadOptions_cleansWhatItRead() throws {
        let app = Application(path: "/Applications/LoadCleanup.app")
        app.inherit = false
        app.scroll.speed = 0.2
        app.scroll.smoothVertical = false
        app.scroll.duration = 4.9
        app.scroll.step = 12

        store("optionsExist", forKey: OptionItem.General.OptionsExist)
        store(12.0, forKey: OptionItem.Scroll.Speed)
        store(false, forKey: OptionItem.Scroll.SmoothVertical)
        store(false, forKey: OptionItem.Scroll.SmoothHorizontal)
        store(3.9, forKey: OptionItem.Scroll.Duration)
        store(50.0, forKey: OptionItem.Scroll.Step)
        store(try JSONEncoder().encode([app]), forKey: OptionItem.Application.Applications)

        Options.shared.readOptions()

        let global = Options.shared.scroll
        XCTAssertEqual(global.speed, 10, "clamped into the slider's range")
        XCTAssertTrue(global.smoothVertical)
        XCTAssertTrue(global.smoothHorizontal)
        XCTAssertEqual(global.duration, 3.9, "a custom Duration is kept")
        XCTAssertEqual(global.step, 50, "a custom Step is kept")

        let loaded = try XCTUnwrap(Options.shared.application.applications.get(by: "/Applications/LoadCleanup.app"))
        XCTAssertEqual(loaded.scroll.speed, 1)
        XCTAssertTrue(loaded.scroll.smoothVertical)
        XCTAssertEqual(loaded.scroll.duration, 4.9)
        XCTAssertEqual(loaded.scroll.step, 12)
    }

    func testReadOptions_keepsSettingsThatAreInRange() {
        // Speed 6.3 with the "Smooth" feel: inside every range, so nothing moves.
        store("optionsExist", forKey: OptionItem.General.OptionsExist)
        store(6.3, forKey: OptionItem.Scroll.Speed)
        store(3.69, forKey: OptionItem.Scroll.Duration)
        store(33.6, forKey: OptionItem.Scroll.Step)

        Options.shared.readOptions()

        XCTAssertEqual(Options.shared.scroll.speed, 6.3)
        XCTAssertEqual(Options.shared.scroll.duration, 3.69)
        XCTAssertEqual(Options.shared.scroll.step, 33.6)
        XCTAssertEqual(ScrollFeel.matching(duration: Options.shared.scroll.duration), .smooth)
    }
}
