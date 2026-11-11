//
//  ScrollMomentumPresetTests.swift
//  MosTests
//
//  The "Magic Mouse" preset, Duration staying free with "Simulate trackpad" (Trackpad-style
//  events) on, and the momentum / thumb wheel controls of the Presets & Fast Scrolling popover.
//

import XCTest
@testable import Mos_Debug

final class ScrollMomentumPresetTests: XCTestCase {

    private typealias ID = ScrollTuningSettingsPopover.Identifier

    private var originalScroll: OPTIONS_SCROLL_DEFAULT!
    private var originalTuning: ScrollTuningSettings!

    override func setUp() {
        super.setUp()
        originalScroll = Options.shared.scroll
        originalTuning = Options.shared.scrollTuning
        // A fresh container, so the tests never edit the one they restore.
        Options.shared.scroll = OPTIONS_SCROLL_DEFAULT()
        Options.shared.scrollTuning = .default
    }

    override func tearDown() {
        Options.shared.scroll = originalScroll
        Options.shared.scrollTuning = originalTuning
        originalScroll = nil
        originalTuning = nil
        super.tearDown()
    }

    // MARK: - Preset table

    func testMagicMouse_values() {
        let values = ScrollPreset.magicMouse.values
        XCTAssertEqual(values.step, 33.6)
        XCTAssertEqual(values.speed, 1.8)
        XCTAssertEqual(values.duration, 3.13)
        XCTAssertTrue(values.simulateTrackpad)
        XCTAssertTrue(values.tuning.freeSpinEnabled)
        XCTAssertEqual(values.tuning.freeSpinSmoothness, 1.0)
        XCTAssertEqual(values.tuning.freeSpinSpeed, 1.2)
        XCTAssertEqual(values.tuning.acceleration, 0)
        XCTAssertEqual(values.tuning.momentum, .default)
        XCTAssertEqual(values.tuning.horizontalWheelAction, .scroll)
        XCTAssertEqual(values.step * values.speed, 60.48, accuracy: 1e-9, "60 px per notch")
        // The smoothing of "Smooth": slow notches run into each other instead of starting and stopping.
        XCTAssertEqual(values.duration, ScrollPreset.smooth.values.duration)
    }

    func testClassicPresets_haveNoMomentum() {
        for preset in ScrollPreset.allCases where preset != .magicMouse {
            XCTAssertNil(preset.values.tuning.momentum, "\(preset)")
            XCTAssertEqual(preset.values.tuning.horizontalWheelAction, .scroll, "\(preset)")
        }
        XCTAssertEqual(ScrollPreset.allCases.last, .magicMouse, "the classic presets keep their places in the picker")
    }

    // MARK: - Apply

    func testApplyMagicMouse_turnsOnSimulateTrackpadAndWritesItsDuration() {
        let scroll = OPTIONS_SCROLL_DEFAULT()
        scroll.smooth = false
        scroll.smoothSimTrackpad = true
        scroll.duration = 4.75
        var tuning = ScrollTuningSettings(freeSpinEnabled: false, freeSpinSmoothness: 4, freeSpinSpeed: 3, acceleration: 1)

        ScrollPreset.magicMouse.apply(to: scroll, tuning: &tuning)

        XCTAssertTrue(scroll.smooth)
        XCTAssertTrue(scroll.smoothSimTrackpad)
        XCTAssertEqual(scroll.duration, 3.13)
        XCTAssertEqual(scroll.step, 33.6)
        XCTAssertEqual(scroll.speed, 1.8)
        XCTAssertEqual(tuning, ScrollPreset.magicMouse.values.tuning)
        XCTAssertEqual(tuning.momentum, .default)
    }

    func testApplyClassicPreset_afterMagicMouseTurnsMomentumOff() {
        let scroll = OPTIONS_SCROLL_DEFAULT()
        var tuning = ScrollTuningSettings.default
        ScrollPreset.magicMouse.apply(to: scroll, tuning: &tuning)

        ScrollPreset.balanced.apply(to: scroll, tuning: &tuning)

        XCTAssertNil(tuning.momentum)
        XCTAssertFalse(scroll.smoothSimTrackpad)
        XCTAssertEqual(scroll.duration, 2.0)
        XCTAssertEqual(ScrollPreset.matching(scroll: scroll, tuning: tuning), .balanced)
    }

    func testApply_keepsTheThumbWheelAction() {
        for preset in ScrollPreset.allCases {
            let scroll = OPTIONS_SCROLL_DEFAULT()
            var tuning = ScrollTuningSettings.default
            tuning.horizontalWheelAction = .pageSwipe
            preset.apply(to: scroll, tuning: &tuning)
            XCTAssertEqual(tuning.horizontalWheelAction, .pageSwipe, "\(preset)")
            XCTAssertEqual(ScrollPreset.matching(scroll: scroll, tuning: tuning), preset, "the thumb wheel is not part of a preset")
        }
    }

    // MARK: - Matching

    func testMatching_magicMouseNeedsItsMomentum() {
        let (scroll, base) = applied(.magicMouse)
        XCTAssertEqual(ScrollPreset.matching(scroll: scroll, tuning: base), .magicMouse)

        var tuning = base
        tuning.momentum = nil
        XCTAssertNil(ScrollPreset.matching(scroll: scroll, tuning: tuning), "momentum off")

        tuning = base
        tuning.momentum?.coastGain = 1.5
        XCTAssertNil(ScrollPreset.matching(scroll: scroll, tuning: tuning), "other momentum values")

        scroll.duration = 4.75
        XCTAssertNil(ScrollPreset.matching(scroll: scroll, tuning: base), "another Duration is not the preset's")
        scroll.duration = 3.13
        scroll.smoothSimTrackpad = false
        XCTAssertNil(ScrollPreset.matching(scroll: scroll, tuning: base), "simulate trackpad off")
    }

    func testMatching_classicPresetsNeedMomentumOff() {
        for preset in ScrollPreset.allCases where preset != .magicMouse {
            let (scroll, base) = applied(preset)
            XCTAssertEqual(ScrollPreset.matching(scroll: scroll, tuning: base), preset)
            var tuning = base
            tuning.momentum = .default
            XCTAssertNil(ScrollPreset.matching(scroll: scroll, tuning: tuning), "\(preset) with momentum is Custom")
        }
    }

    func testApplyGlobal_magicMouseIsTheCurrentPreset() {
        ScrollPreset.magicMouse.apply()
        XCTAssertEqual(ScrollPreset.current, .magicMouse)
        XCTAssertEqual(Options.shared.scroll.duration, 3.13)
        XCTAssertTrue(Options.shared.scroll.smoothSimTrackpad)
        XCTAssertEqual(Options.shared.scrollTuning.momentum, .default)
    }

    // MARK: - Scrolling tab: Duration stays free with trackpad-style events

    func testScrollingTab_keepsTheMagicMouseDuration() {
        ScrollPreset.magicMouse.apply()
        let controller = makeScrollingController()
        controller.syncViewWithOptions()

        XCTAssertEqual(Options.shared.scroll.duration, 3.13, "sync leaves the preset's Duration alone")
        XCTAssertEqual(ScrollPreset.current, .magicMouse)
        XCTAssertEqual(controller.scrollDurationSlider.doubleValue, 3.13, accuracy: 1e-9)
        XCTAssertTrue(controller.scrollDurationSlider.isEnabled)
        XCTAssertTrue(controller.scrollDurationInput.isEnabled)

        controller.setScrollDuration(value: 3.0)
        XCTAssertEqual(Options.shared.scroll.duration, 3.0, "Duration can be changed while momentum is on")
        XCTAssertNil(ScrollPreset.current)
    }

    func testScrollingTab_trackpadStyleWithoutMomentumLeavesDurationFree() {
        Options.shared.scroll.duration = 3.13
        let controller = makeScrollingController()
        let description = controller.scrollDurationDescriptionLabel?.stringValue
        XCTAssertFalse(description?.isEmpty ?? true)

        Options.shared.scroll.smoothSimTrackpad = true
        XCTAssertNil(Options.shared.scrollTuning.momentum)
        controller.syncViewWithOptions()

        XCTAssertEqual(Options.shared.scroll.duration, 3.13, "sync does not force a Duration")
        XCTAssertEqual(controller.scrollDurationSlider.doubleValue, 3.13, accuracy: 1e-9)
        XCTAssertTrue(controller.scrollDurationSlider.isEnabled)
        XCTAssertTrue(controller.scrollDurationStepper.isEnabled)
        XCTAssertTrue(controller.scrollDurationInput.isEnabled)
        XCTAssertEqual(controller.scrollDurationDescriptionLabel?.stringValue, description, "no lock message")

        controller.setScrollDuration(value: 1.5)
        XCTAssertEqual(Options.shared.scroll.duration, 1.5)
        XCTAssertEqual(controller.scrollDurationSlider.doubleValue, 1.5, accuracy: 1e-9)
        XCTAssertEqual(controller.scrollDurationInput.stringValue, "1.50")
    }

    func testScrollingTab_perAppTrackpadStyleOnlyFollowsTheInheritRule() {
        let app = Application(path: "/Applications/TrackpadStyle.app")
        app.inherit = false
        app.scroll.smoothSimTrackpad = true
        app.scroll.duration = 2.0
        let controller = makeScrollingController()
        controller.currentTargetApplication = app
        controller.syncViewWithOptions()

        XCTAssertTrue(controller.scrollDurationSlider.isEnabled)
        XCTAssertTrue(controller.scrollDurationStepper.isEnabled)
        XCTAssertTrue(controller.scrollDurationInput.isEnabled)
        XCTAssertEqual(controller.scrollDurationSlider.doubleValue, 2.0, accuracy: 1e-9)
        controller.setScrollDuration(value: 1.0)
        XCTAssertEqual(app.scroll.duration, 1.0)

        app.inherit = true
        controller.syncViewWithOptions()
        XCTAssertFalse(controller.scrollDurationSlider.isEnabled, "inheriting: the global settings apply")
        XCTAssertFalse(controller.scrollDurationStepper.isEnabled)
        XCTAssertFalse(controller.scrollDurationInput.isEnabled)
    }

    func testScrollingTab_resetClearsMomentumAndThumbWheel() {
        ScrollPreset.magicMouse.apply()
        Options.shared.scrollTuning.horizontalWheelAction = .pageSwipe
        let controller = makeScrollingController()
        XCTAssertTrue(controller.hasSettingsToReset)

        controller.resetToDefaultClick(controller.resetToDefaultsButton)

        XCTAssertEqual(Options.shared.scrollTuning, .default)
        XCTAssertNil(Options.shared.scrollTuning.momentum)
        XCTAssertEqual(Options.shared.scrollTuning.horizontalWheelAction, .scroll)
        XCTAssertEqual(Options.shared.scroll, OPTIONS_SCROLL_DEFAULT())
        XCTAssertFalse(controller.hasSettingsToReset)
    }

    func testScrollingTab_thumbWheelAloneCanBeReset() {
        let controller = makeScrollingController()
        XCTAssertFalse(controller.hasSettingsToReset)
        Options.shared.scrollTuning.horizontalWheelAction = .pageSwipe
        XCTAssertTrue(controller.hasSettingsToReset)
    }

    // MARK: - Toggles leave Duration alone

    func testSimulateTrackpadToggle_neverChangesDuration() {
        let toggle = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        let popover = ScrollSmoothDetailSettingsPopoverViewController()
        let momentumStates: [ScrollMomentumSettings?] = [.default, nil]

        for momentum in momentumStates {
            Options.shared.scrollTuning.momentum = momentum
            Options.shared.scroll.duration = 1.5
            toggle.state = .on
            popover.simulateTrackpadToggle(toggle)
            XCTAssertTrue(Options.shared.scroll.smoothSimTrackpad)
            XCTAssertEqual(Options.shared.scroll.duration, 1.5, "on, momentum \(momentum != nil)")
            toggle.state = .off
            popover.simulateTrackpadToggle(toggle)
            XCTAssertFalse(Options.shared.scroll.smoothSimTrackpad)
            XCTAssertEqual(Options.shared.scroll.duration, 1.5, "off, momentum \(momentum != nil)")
        }
    }

    func testSimulateTrackpadToggle_perAppNeverChangesDuration() {
        let toggle = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        let popover = ScrollSmoothDetailSettingsPopoverViewController()
        let app = Application(path: "/Applications/TrackpadStyle.app")
        app.inherit = false
        app.scroll.duration = 2.0
        popover.currentTargetApplication = app
        Options.shared.scroll.duration = 1.5

        toggle.state = .on
        popover.simulateTrackpadToggle(toggle)
        XCTAssertTrue(app.scroll.smoothSimTrackpad)
        XCTAssertEqual(app.scroll.duration, 2.0)
        toggle.state = .off
        popover.simulateTrackpadToggle(toggle)
        XCTAssertFalse(app.scroll.smoothSimTrackpad)
        XCTAssertEqual(app.scroll.duration, 2.0)
        XCTAssertFalse(Options.shared.scroll.smoothSimTrackpad, "the global settings are not touched")
        XCTAssertEqual(Options.shared.scroll.duration, 1.5)
    }

    // MARK: - Popover

    func testPopover_listsMagicMouseAfterTheClassicPresets() {
        let view = ScrollTuningSettingsPopover().makeContentViewController().view
        let picker = popUp(ID.preset, in: view)
        let titles = picker.itemArray.filter { !$0.isSeparatorItem }.map { $0.title }
        XCTAssertEqual(titles, ScrollPreset.allCases.map { $0.localizedName } + [ScrollPreset.customLocalizedName])
        XCTAssertEqual(titles[4], ScrollPreset.magicMouse.localizedName)
    }

    func testPopover_pickingMagicMouseAppliesItAndChecksMomentum() {
        ScrollPreset.balanced.apply()
        let popover = ScrollTuningSettingsPopover()
        var changes = 0
        popover.onSettingsChanged = { changes += 1 }
        let view = popover.makeContentViewController().view
        XCTAssertEqual(checkbox(ID.momentum, in: view).state, .off)

        let picker = popUp(ID.preset, in: view)
        picker.selectItem(withTag: ScrollPreset.allCases.firstIndex(of: .magicMouse)!)
        picker.sendAction(picker.action, to: picker.target)

        XCTAssertEqual(changes, 1)
        XCTAssertEqual(ScrollPreset.current, .magicMouse)
        XCTAssertEqual(Options.shared.scroll.duration, 3.13)
        XCTAssertEqual(checkbox(ID.momentum, in: view).state, .on)
        XCTAssertEqual(label(ID.presetDescription, in: view).stringValue, ScrollPreset.magicMouse.localizedDescription)
        XCTAssertEqual(slider(ID.speed, in: view).doubleValue, 1.2, accuracy: 1e-9)
        XCTAssertEqual(slider(ID.smoothness, in: view).doubleValue, 1.0, accuracy: 1e-9)
    }

    func testPopover_momentumCheckboxTurnsDefaultMomentumOnAndOff() {
        ScrollPreset.balanced.apply()
        let popover = ScrollTuningSettingsPopover()
        var changes = 0
        popover.onSettingsChanged = { changes += 1 }
        let view = popover.makeContentViewController().view
        let momentum = checkbox(ID.momentum, in: view)
        XCTAssertFalse(momentum.toolTip?.isEmpty ?? true)

        momentum.performClick(nil)
        XCTAssertEqual(Options.shared.scrollTuning.momentum, .default)
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(popUp(ID.preset, in: view).titleOfSelectedItem, ScrollPreset.customLocalizedName)
        XCTAssertEqual(Options.shared.scroll.duration, 2.0, "momentum does not touch Duration")

        momentum.performClick(nil)
        XCTAssertNil(Options.shared.scrollTuning.momentum)
        XCTAssertEqual(changes, 2)
        XCTAssertEqual(popUp(ID.preset, in: view).selectedTag(), ScrollPreset.allCases.firstIndex(of: .balanced))
    }

    func testPopover_momentumCheckboxLeavesTheTrackpadStyleDurationAlone() {
        ScrollPreset.magicMouse.apply()
        let popover = ScrollTuningSettingsPopover()  // the controls' target; must stay alive
        let view = popover.makeContentViewController().view
        let momentum = checkbox(ID.momentum, in: view)
        XCTAssertEqual(momentum.state, .on)

        momentum.performClick(nil)
        XCTAssertNil(Options.shared.scrollTuning.momentum)
        XCTAssertTrue(Options.shared.scroll.smoothSimTrackpad)
        XCTAssertEqual(Options.shared.scroll.duration, 3.13, "trackpad-style without momentum keeps the preset's Duration")
        let controller = makeScrollingController()
        XCTAssertTrue(controller.scrollDurationSlider.isEnabled)
        XCTAssertEqual(controller.scrollDurationSlider.doubleValue, 3.13, accuracy: 1e-9)

        momentum.performClick(nil)
        XCTAssertEqual(Options.shared.scroll.duration, 3.13)
        XCTAssertEqual(ScrollPreset.current, .magicMouse)
    }

    func testPopover_thumbWheelChoiceIsStoredAndSurvivesPresets() {
        let popover = ScrollTuningSettingsPopover()
        popover.isSwipeBetweenPagesEnabled = { true }
        var changes = 0
        popover.onSettingsChanged = { changes += 1 }
        let view = popover.makeContentViewController().view
        let thumbWheel = popUp(ID.thumbWheel, in: view)
        XCTAssertEqual(thumbWheel.numberOfItems, 2)
        XCTAssertEqual(thumbWheel.selectedTag(), 0, "scroll sideways by default")

        thumbWheel.selectItem(withTag: 1)
        thumbWheel.sendAction(thumbWheel.action, to: thumbWheel.target)
        XCTAssertEqual(Options.shared.scrollTuning.horizontalWheelAction, .pageSwipe)
        XCTAssertEqual(changes, 1)
        // The same choice again is not a change.
        thumbWheel.sendAction(thumbWheel.action, to: thumbWheel.target)
        XCTAssertEqual(changes, 1)

        let picker = popUp(ID.preset, in: view)
        picker.selectItem(withTag: ScrollPreset.allCases.firstIndex(of: .direct)!)
        picker.sendAction(picker.action, to: picker.target)
        XCTAssertEqual(Options.shared.scrollTuning.horizontalWheelAction, .pageSwipe)
        XCTAssertEqual(thumbWheel.selectedTag(), 1)
        XCTAssertEqual(ScrollPreset.current, .direct)
    }

    func testPopover_showsTheHintOnlyWhenPageSwipeCannotWork() {
        var systemSetting = false
        let popover = ScrollTuningSettingsPopover()
        popover.isSwipeBetweenPagesEnabled = { systemSetting }
        let view = popover.makeContentViewController().view
        let thumbWheel = popUp(ID.thumbWheel, in: view)
        let hint = label(ID.thumbWheelHint, in: view)
        XCTAssertFalse(hint.stringValue.isEmpty)
        XCTAssertTrue(isHidden(hint), "scrolling sideways needs no system setting")

        thumbWheel.selectItem(withTag: 1)
        thumbWheel.sendAction(thumbWheel.action, to: thumbWheel.target)
        XCTAssertFalse(isHidden(hint), "page swipe chosen, but the system setting is off")

        systemSetting = true
        thumbWheel.sendAction(thumbWheel.action, to: thumbWheel.target)
        XCTAssertTrue(isHidden(hint))

        thumbWheel.selectItem(withTag: 0)
        thumbWheel.sendAction(thumbWheel.action, to: thumbWheel.target)
        XCTAssertEqual(Options.shared.scrollTuning.horizontalWheelAction, .scroll)
        XCTAssertTrue(isHidden(hint))
    }

    // MARK: - Strings

    func testNewStrings_existInEveryLocale() throws {
        let keys = [
            "scroll-preset-magic-mouse", "scroll-preset-magic-mouse-description",
            "scroll-tuning-momentum-checkbox", "scroll-tuning-momentum-tooltip",
            "scroll-tuning-thumb-wheel-label", "scroll-tuning-thumb-wheel-scroll",
            "scroll-tuning-thumb-wheel-page-swipe", "scroll-tuning-thumb-wheel-hint",
        ]
        let locales = PreferencesLocalizationTests.locales
        let missing = "\u{1}missing"
        let app = Bundle(for: PreferencesScrollingViewController.self)
        for locale in locales {
            let path = try XCTUnwrap(app.path(forResource: locale, ofType: "lproj"), "\(locale).lproj")
            let bundle = try XCTUnwrap(Bundle(path: path))
            for key in keys {
                let value = bundle.localizedString(forKey: key, value: missing, table: nil)
                XCTAssertNotEqual(value, missing, "\(locale): \(key) missing")
                XCTAssertNotEqual(value, key, "\(locale): \(key) shows the raw key")
                XCTAssertFalse(value.isEmpty, "\(locale): \(key) empty")
                XCTAssertFalse(value.contains("%"), "\(locale): \(key) has no format specifiers")
            }
        }
    }

    func testPresetNamesAndDescriptions_areDistinct() {
        let names = ScrollPreset.allCases.map { $0.localizedName } + [ScrollPreset.customLocalizedName]
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertNotEqual(ScrollPreset.magicMouse.localizedName, "scroll-preset-magic-mouse")
        XCTAssertNotEqual(ScrollPreset.magicMouse.localizedDescription, "scroll-preset-magic-mouse-description")
    }

    // MARK: - Helpers

    private func applied(_ preset: ScrollPreset) -> (OPTIONS_SCROLL_DEFAULT, ScrollTuningSettings) {
        let scroll = OPTIONS_SCROLL_DEFAULT()
        var tuning = ScrollTuningSettings.default
        preset.apply(to: scroll, tuning: &tuning)
        return (scroll, tuning)
    }

    private func makeScrollingController() -> PreferencesScrollingViewController {
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesScrollingViewController.self))
        let controller = storyboard.instantiateController(withIdentifier: "scrolling") as! PreferencesScrollingViewController
        _ = controller.view
        return controller
    }

    private func popUp(_ id: NSUserInterfaceItemIdentifier, in view: NSView) -> NSPopUpButton {
        find(id, in: view) as! NSPopUpButton
    }

    private func slider(_ id: NSUserInterfaceItemIdentifier, in view: NSView) -> NSSlider {
        find(id, in: view) as! NSSlider
    }

    private func checkbox(_ id: NSUserInterfaceItemIdentifier, in view: NSView) -> NSButton {
        find(id, in: view) as! NSButton
    }

    private func label(_ id: NSUserInterfaceItemIdentifier, in view: NSView) -> NSTextField {
        find(id, in: view) as! NSTextField
    }

    private func isHidden(_ view: NSView) -> Bool {
        view.isHiddenOrHasHiddenAncestor
    }

    private func find(_ id: NSUserInterfaceItemIdentifier, in view: NSView) -> NSView? {
        if view.identifier == id { return view }
        for subview in view.subviews {
            if let match = find(id, in: subview) { return match }
        }
        return nil
    }
}

// MARK: - Test-only shim

/// `ScrollMotionTests` samples the Duration the old "Trackpad-style events" lock forced (4.75)
/// under this name. The app no longer has it; this keeps that file, which is being reworked
/// separately, compiling. Remove it once `ScrollMotionTests` no longer refers to it.
enum ScrollDurationLimits {
    static let simulateTrackpadDefault: Double = 4.75
}
