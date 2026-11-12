//
//  ScrollSettingsTests.swift
//  MosTests
//
//  The model behind the Scrolling tab: the five Feel presets, the slider ranges, the one
//  direction switch, and the clean-up that runs when settings load.
//

import XCTest
@testable import Scrollio_Debug

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
            // The slider's stop next to a preset (3.15 for Quick's 3.13) selects that preset.
            XCTAssertEqual(ScrollFeel.matching(duration: slider.snapped(feel.duration)), feel, "\(feel)")
        }
        // Three presets lie on the 0.05 grid; Quick and Smooth keep their own Durations.
        XCTAssertEqual(ScrollFeel.allCases.filter { slider.snapped($0.duration) == $0.duration }, [.direct, .glide, .float])
    }

    func testFeel_matchingAllowsThreeHundredthsEitherSide() {
        XCTAssertEqual(ScrollFeel.matchTolerance, 0.03)
        for feel in ScrollFeel.allCases {
            XCTAssertEqual(ScrollFeel.matching(duration: feel.duration), feel)
            XCTAssertEqual(ScrollFeel.matching(duration: feel.duration + 0.03), feel, "within the tolerance")
            XCTAssertEqual(ScrollFeel.matching(duration: feel.duration - 0.03), feel, "within the tolerance")
            XCTAssertNil(ScrollFeel.matching(duration: feel.duration + 0.04), "two slider steps away is custom")
            XCTAssertNil(ScrollFeel.matching(duration: feel.duration - 0.04))
        }
        // The owner's Duration, tuned by feel, still reads as Smooth.
        XCTAssertEqual(ScrollFeel.matching(duration: 3.687), .smooth)
        XCTAssertEqual(ScrollFeel.matching(duration: 3.15), .quick)
        XCTAssertEqual(ScrollFeel.matching(duration: 3.7), .smooth)
        XCTAssertNil(ScrollFeel.matching(duration: 3.65))
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

    func testSliders_ticksAndSteps() {
        let speed = ScrollSliderSetting.speed
        XCTAssertEqual(speed.scale, .ticks(10, step: 0.5))
        XCTAssertEqual(speed.scale.tickValues(in: speed.range), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10], "a tick at every whole number")
        XCTAssertEqual(speed.step, 0.5)

        let glide = ScrollSliderSetting.glideTime
        XCTAssertEqual(glide.scale, .ticks(9, step: 0.05))
        XCTAssertEqual(glide.scale.tickValues(in: glide.range), [1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5, 5])
        XCTAssertEqual(glide.step, 0.05)

        let step = ScrollSliderSetting.smallestStep
        XCTAssertEqual(step.scale, .ticks(11, step: 1))
        XCTAssertEqual(step.scale.tickValues(in: step.range).count, 11)
        XCTAssertEqual(step.scale.tickValues(in: step.range).dropFirst().map { $0.rounded() }, [10, 20, 30, 40, 50, 60, 70, 80, 90, 100])
        XCTAssertEqual(step.step, 1)
    }

    func testSliders_snapToTheirGridAndStayInRange() {
        let speed = ScrollSliderSetting.speed
        XCTAssertEqual(speed.snapped(6.5), 6.5)
        XCTAssertEqual(speed.snapped(6.31), 6.5)
        XCTAssertEqual(speed.snapped(6.24), 6)
        XCTAssertEqual(speed.snapped(2.76), 3)
        XCTAssertEqual(speed.snapped(0.2), 1)
        XCTAssertEqual(speed.snapped(42), 10)
        XCTAssertEqual(speed.snapped(.nan), 1)
        XCTAssertEqual(speed.snapped(.infinity), 1)

        let glide = ScrollSliderSetting.glideTime
        XCTAssertEqual(glide.snapped(3.687), 3.7)
        XCTAssertEqual(glide.snapped(3.674), 3.65)
        XCTAssertEqual(glide.snapped(3.13), 3.15)
        XCTAssertEqual(glide.snapped(4.35), 4.35)
        XCTAssertEqual(glide.snapped(0), 1)
        XCTAssertEqual(glide.snapped(9), 5)

        let step = ScrollSliderSetting.smallestStep
        XCTAssertEqual(step.snapped(33.6), 34, "the default is off the whole-number grid")
        XCTAssertEqual(step.snapped(33.4), 33)
        XCTAssertEqual(step.snapped(0.4), 0.01, "the lowest stop is the range's own")
        XCTAssertEqual(step.snapped(0.6), 1)
        XCTAssertEqual(step.snapped(250), 100)
    }

    func testSliders_valueTexts() {
        XCTAssertEqual(ScrollSliderSetting.speed.text(6.5), "6.5")
        XCTAssertEqual(ScrollSliderSetting.speed.text(10), "10.0")
        XCTAssertEqual(ScrollSliderSetting.speed.text(6.31), "6.3")
        XCTAssertEqual(ScrollSliderSetting.glideTime.text(3.69), "3.69")
        XCTAssertEqual(ScrollSliderSetting.glideTime.text(3.687), "3.69")
        XCTAssertEqual(ScrollSliderSetting.glideTime.text(2), "2.00")
        XCTAssertEqual(ScrollSliderSetting.smallestStep.text(34), "34", "whole numbers on the whole-number grid")
        XCTAssertEqual(ScrollSliderSetting.smallestStep.text(100), "100")
        XCTAssertEqual(ScrollSliderSetting.smallestStep.text(33.6), "33.6", "a value off the grid is not shown as another")
        XCTAssertEqual(ScrollSliderSetting.smallestStep.text(0.01), "0.01", "never shown as 0")
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

    func testReversesWheel_isOnWhileEitherAxisIsReversed() {
        // Left over from the per-axis switches of older builds: the main flag on, only one
        // axis on.
        let scroll = OPTIONS_SCROLL_DEFAULT()
        scroll.reverseVertical = false
        scroll.reverseHorizontal = true
        XCTAssertTrue(scroll.reversesWheel, "the horizontal wheel is reversed, so the switch shows on")

        scroll.reverseVertical = true
        scroll.reverseHorizontal = false
        XCTAssertTrue(scroll.reversesWheel, "the vertical wheel is reversed, so the switch shows on")

        scroll.reverseVertical = false
        XCTAssertFalse(scroll.reversesWheel, "neither axis is reversed, whatever the main flag says")
        scroll.reversesWheel = true
        XCTAssertTrue(scroll.reverseVertical)
        XCTAssertTrue(scroll.reverseHorizontal)
    }

    func testReversesWheel_offStopsBothAxesOfOlderSettings() {
        // From an older build: the main flag on, vertical off, horizontal on.
        let scroll = OPTIONS_SCROLL_DEFAULT()
        scroll.reverse = true
        scroll.reverseVertical = false
        scroll.reverseHorizontal = true
        XCTAssertTrue(scroll.reversesWheel)

        scroll.reversesWheel = false

        // What ScrollCore reverses: the main flag and the axis's flag.
        XCTAssertFalse(scroll.reverse && scroll.reverseVertical)
        XCTAssertFalse(scroll.reverse && scroll.reverseHorizontal)
        XCTAssertFalse(scroll.reversesWheel)
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

    func testRun_removesTheRetiredKeys() throws {
        // Canary: the stored names of retired settings (never reuse them for something else).
        XCTAssertEqual(ScrollSettingsCleanup.retiredDefaultsKeys, ["durationForOtherTrackpadState", "scrollTuning"])
        let suite = "ScrollioTests.cleanup.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(4.5, forKey: "durationForOtherTrackpadState")
        // The fast-scroll tuning as the last build that had it stored it.
        let tuning = #"{"freeSpinEnabled":true,"freeSpinSmoothness":1.5,"freeSpinSpeed":1,"acceleration":0}"#
        defaults.set(Data(tuning.utf8), forKey: "scrollTuning")
        defaults.set(3.69, forKey: OptionItem.Scroll.Duration)
        defaults.set(6.3, forKey: OptionItem.Scroll.Speed)
        defaults.set(Data(#"{"managedByScrollio":true}"#.utf8), forKey: OptionItem.MouseWheel.Settings)

        ScrollSettingsCleanup.run(global: OPTIONS_SCROLL_DEFAULT(), applications: [], defaults: defaults)

        XCTAssertNil(defaults.object(forKey: "durationForOtherTrackpadState"))
        XCTAssertNil(defaults.object(forKey: "scrollTuning"))
        XCTAssertEqual(defaults.double(forKey: OptionItem.Scroll.Duration), 3.69, "the settings in use stay")
        XCTAssertEqual(defaults.double(forKey: OptionItem.Scroll.Speed), 6.3)
        XCTAssertNotNil(defaults.data(forKey: OptionItem.MouseWheel.Settings))

        ScrollSettingsCleanup.run(global: OPTIONS_SCROLL_DEFAULT(), applications: [], defaults: defaults)
        XCTAssertEqual(defaults.double(forKey: OptionItem.Scroll.Duration), 3.69, "a second run changes nothing")
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

    /// One per-app entry this version cannot read used to make the whole list be removed
    /// from the settings at launch.
    func testReadOptions_keepsTheAppsListWhenOneEntryCannotBeRead() throws {
        let stored = Data(("[" + StoredDataCanaryTests.readableApp + "," + StoredDataCanaryTests.unreadableApp + "]").utf8)
        store("optionsExist", forKey: OptionItem.General.OptionsExist)
        store(stored, forKey: OptionItem.Application.Applications)

        Options.shared.readOptions()

        let apps = Options.shared.application.applications
        XCTAssertEqual(apps.count, 1)
        XCTAssertNotNil(apps.get(by: "/Applications/A.app"))
        XCTAssertEqual(defaults.data(forKey: OptionItem.Application.Applications), stored, "nothing was removed")
    }

    /// A scroll key stored as a bare number (the form of the original app before 2026) is
    /// not read as a key code any more: 0, that app's "Disabled", became the A key for all
    /// three hold functions, and a number that is no key code once crashed the app at every
    /// launch. Scrollio never wrote that form. The default key is used and nothing is
    /// rewritten.
    func testReadOptions_aScrollKeyStoredAsANumberIsNotAKeyCode() {
        store("optionsExist", forKey: OptionItem.General.OptionsExist)
        store(0, forKey: OptionItem.Scroll.Dash)
        store(70_000, forKey: OptionItem.Scroll.Toggle)
        store(58, forKey: OptionItem.Scroll.Block)

        Options.shared.readOptions()

        XCTAssertEqual(Options.shared.scroll.dash, OPTIONS_SCROLL_DEFAULT().dash, "not the A key (key code 0)")
        XCTAssertNotEqual(Options.shared.scroll.dash, ScrollHotkey(type: .keyboard, code: 0))
        XCTAssertEqual(Options.shared.scroll.toggle, OPTIONS_SCROLL_DEFAULT().toggle)
        XCTAssertEqual(Options.shared.scroll.block, OPTIONS_SCROLL_DEFAULT().block)
        XCTAssertEqual(defaults.object(forKey: OptionItem.Scroll.Dash) as? Int, 0, "the stored value is not rewritten")
        XCTAssertEqual(defaults.object(forKey: OptionItem.Scroll.Block) as? Int, 58)
    }

    /// A settings file without "smooth" or "reverse" read both as off (`bool(forKey:)`),
    /// while every newer key next to them fell back to its default.
    func testReadOptions_aMissingSmoothOrReverseIsTheDefault() {
        store("optionsExist", forKey: OptionItem.General.OptionsExist)
        for key in [OptionItem.Scroll.Smooth, OptionItem.Scroll.Reverse] {
            // Remembered first, so tearDown puts back what the test host had.
            defaultsSnapshots.append((key: key, original: defaults.object(forKey: key)))
            defaults.removeObject(forKey: key)
        }

        Options.shared.readOptions()

        XCTAssertTrue(Options.shared.scroll.smooth)
        XCTAssertTrue(Options.shared.scroll.reverse)
        XCTAssertEqual(OPTIONS_SCROLL_DEFAULT().smooth, true)

        // A stored "off" is still off.
        store(false, forKey: OptionItem.Scroll.Smooth)
        store(false, forKey: OptionItem.Scroll.Reverse)
        Options.shared.readOptions()
        XCTAssertFalse(Options.shared.scroll.smooth)
        XCTAssertFalse(Options.shared.scroll.reverse)
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

/// Stored values the sliders cannot give, guarded where the engine uses them; what is stored
/// is never rewritten. A Duration of 5.2 or more (or not a number) gave a factor of 0 or
/// less: nothing moved and the display link never stopped. A dead zone that is not positive
/// kept the display link running forever.
final class ScrollSettingsUsableValuesTests: XCTestCase {

    private func transition(_ duration: Double) -> Double {
        return OPTIONS_SCROLL_DEFAULT.generateDurationTransition(with: duration)
    }

    /// The formula as it was, for every Duration the slider can give.
    private func unguarded(_ duration: Double) -> Double {
        return Double(round(1000 * (1 - (duration / 5.2).squareRoot())) / 1000)
    }

    func testEveryDurationOnTheSliderKeepsItsFactor() {
        let range = ScrollSliderSetting.glideTime.range
        for duration in stride(from: range.lowerBound, through: range.upperBound, by: 0.01) {
            XCTAssertEqual(transition(duration), unguarded(duration), "\(duration)")
        }
        for feel in ScrollFeel.allCases {
            XCTAssertEqual(transition(feel.duration), unguarded(feel.duration), "\(feel)")
        }
        XCTAssertEqual(OPTIONS_SCROLL_DEFAULT.minimumDurationTransition, unguarded(range.upperBound),
                       "the floor is the factor of the slider's longest Duration")
    }

    func testADurationBeyondTheSliderGlidesLikeTheLongest() {
        for stored in [5.05, 5.2, 6.0, 100, -1, .nan, .infinity] {
            XCTAssertEqual(transition(stored), OPTIONS_SCROLL_DEFAULT.minimumDurationTransition, "\(stored)")
        }
        let scroll = OPTIONS_SCROLL_DEFAULT()
        scroll.duration = 6.0
        XCTAssertEqual(scroll.durationTransition, OPTIONS_SCROLL_DEFAULT.minimumDurationTransition)
        XCTAssertEqual(scroll.duration, 6.0, "the stored value stays")
    }

    /// With the factor of a stored Duration 6 a scroll moves and ends.
    func testAScrollWithADurationBeyondTheSliderEnds() {
        let poster = ScrollPoster(phases: ScrollPhase(), dispatchContext: ScrollDispatchContext())
        var moved = 0.0
        poster.frameRecorderForTests = { moved += $0.y }
        poster.setConfigForTests(simTrackpadEnabled: false)
        var now = 100.0
        poster.inputForTests(ScrollPosterInput(y: 100, x: 0, notch: 100, duration: transition(6.0)), at: now)

        var request: ScrollStopRequest?
        for _ in 0..<(60 * 60) {
            now += 1.0 / 60.0
            request = poster.displayLinkFrameForTests(frameInterval: 1.0 / 60.0, now: now)
            if request != nil { break }
        }
        XCTAssertNotNil(request, "the display link is asked to stop")
        XCTAssertGreaterThan(moved, 0, "the page moves")
    }

    func testADeadZoneThatIsNotPositiveGivesTheDefault() {
        XCTAssertEqual(OPTIONS_SCROLL_DEFAULT().deadZone, OPTIONS_SCROLL_DEFAULT.defaultDeadZone)
        for stored in [0.0, -1.0, -.infinity, .nan, .infinity] {
            XCTAssertEqual(OPTIONS_SCROLL_DEFAULT.usableDeadZone(stored), 1.0, "\(stored)")
        }
        for stored in [0.25, 1.0, 2.0, 7.0] {
            XCTAssertEqual(OPTIONS_SCROLL_DEFAULT.usableDeadZone(stored), stored)
        }
    }
}

/// The thumb wheel's settings (`ThumbWheelSettings`, `Options.thumbWheel`): stored as JSON
/// under "thumbWheelSettings", read tolerantly value by value.
final class ThumbWheelSettingsTests: XCTestCase {

    private func decode(_ json: String) -> ThumbWheelSettings {
        return Options.decodeThumbWheelSettings(Data(json.utf8))
    }

    /// The defaults are what the app did before the settings existed.
    func testDefaults_scrollSidewaysAtTheMainWheelsSpeed_notSwapped() {
        let settings = ThumbWheelSettings.default
        XCTAssertEqual(settings.function, .scroll)
        XCTAssertEqual(settings.speed, 1.0)
        XCTAssertFalse(settings.swapsDirection)
        XCTAssertEqual(settings, ThumbWheelSettings())
        XCTAssertEqual(ThumbWheelSettings.defaultSpeed, 1.0)
        XCTAssertEqual(ThumbWheelSettings.speedRange, 0.25...3.0)
        XCTAssertEqual(ThumbWheelFunction.allCases, [.scroll, .zoom, .tabs, .desktops, .backForward, .volume])
        XCTAssertEqual(ThumbWheelFunction.allCases.map(\.rawValue), ["scroll", "zoom", "tabs", "desktops", "backForward", "volume"], "stored names")
    }

    func testSpeed_staysInsideItsRange() {
        XCTAssertEqual(ThumbWheelSettings(speed: 10).speed, 3.0)
        XCTAssertEqual(ThumbWheelSettings(speed: 0.1).speed, 0.25)
        XCTAssertEqual(ThumbWheelSettings(speed: -2).speed, 0.25)
        XCTAssertEqual(ThumbWheelSettings(speed: 1.75).speed, 1.75)
        XCTAssertEqual(ThumbWheelSettings(speed: .nan).speed, 1.0, "not a number: the default")
        XCTAssertEqual(ThumbWheelSettings(speed: .infinity).speed, 1.0)
        var settings = ThumbWheelSettings()
        settings.speed = 7
        XCTAssertEqual(settings.speed, 3.0, "a later change is kept in range too")
        settings.speed = 0
        XCTAssertEqual(settings.speed, 0.25)
        settings.speed = -.infinity
        XCTAssertEqual(settings.speed, 1.0)
    }

    /// Each value on its own: a missing, unreadable or unknown one falls back to its default,
    /// the others are kept; unknown keys are ignored.
    func testDecoding_isTolerantValueByValue() {
        XCTAssertEqual(decode(#"{"function":"volume","speed":2.5,"swapsDirection":true}"#),
                       ThumbWheelSettings(function: .volume, speed: 2.5, swapsDirection: true))
        XCTAssertEqual(decode(#"{"function":"swipe","speed":2.5,"swapsDirection":true}"#),
                       ThumbWheelSettings(function: .scroll, speed: 2.5, swapsDirection: true), "an unknown function")
        XCTAssertEqual(decode(#"{"function":"tabs","speed":"fast","swapsDirection":true}"#),
                       ThumbWheelSettings(function: .tabs, speed: 1, swapsDirection: true), "a speed that is no number")
        XCTAssertEqual(decode(#"{"function":"tabs","speed":9,"swapsDirection":1}"#),
                       ThumbWheelSettings(function: .tabs, speed: 3, swapsDirection: false), "out of range; not a Bool")
        XCTAssertEqual(decode(#"{"function":3,"speed":0.5}"#),
                       ThumbWheelSettings(function: .scroll, speed: 0.5, swapsDirection: false))
        XCTAssertEqual(decode(#"{"swapsDirection":true,"later":"a key of a newer version"}"#),
                       ThumbWheelSettings(swapsDirection: true))
        XCTAssertEqual(decode("{}"), .default)
        XCTAssertEqual(decode(#"{"function":null,"speed":null,"swapsDirection":null}"#), .default)
    }

    /// The Options helper: missing or unreadable data gives the defaults.
    func testOptionsDecodeHelper_missingOrUnreadableDataGivesTheDefaults() {
        XCTAssertEqual(Options.decodeThumbWheelSettings(nil), .default)
        XCTAssertEqual(Options.decodeThumbWheelSettings(Data()), .default)
        XCTAssertEqual(Options.decodeThumbWheelSettings(Data("not json".utf8)), .default)
        XCTAssertEqual(decode("[1, 2]"), .default)
        XCTAssertEqual(decode(#""zoom""#), .default)
        XCTAssertEqual(decode(#"{"function":"zoom"}"#), ThumbWheelSettings(function: .zoom))
    }

    /// What is stored reads back as it was, under three frozen keys.
    func testRoundTrip_andTheStoredForm() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        for function in ThumbWheelFunction.allCases {
            for (speed, swaps) in [(0.25, false), (1.0, true), (2.75, true), (3.0, false)] {
                let settings = ThumbWheelSettings(function: function, speed: speed, swapsDirection: swaps)
                let data = try encoder.encode(settings)
                XCTAssertEqual(Options.decodeThumbWheelSettings(data), settings)
            }
        }
        let stored = String(decoding: try encoder.encode(ThumbWheelSettings(function: .backForward, speed: 1.5, swapsDirection: true)), as: UTF8.self)
        XCTAssertEqual(stored, #"{"function":"backForward","speed":1.5,"swapsDirection":true}"#)
        XCTAssertEqual(OptionItem.ThumbWheel.Settings, "thumbWheelSettings")
        XCTAssertFalse(ScrollSettingsCleanup.retiredDefaultsKeys.contains(OptionItem.ThumbWheel.Settings), "a new key, not a retired one")
    }
}
