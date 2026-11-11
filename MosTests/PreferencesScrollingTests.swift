//
//  PreferencesScrollingTests.swift
//  MosTests
//
//  The Scrolling tab: every control reads and writes the right scroll option, Feel and
//  the glide time slider never disagree, "Advanced" opens, closes and is remembered, the
//  preview follows the options, and the same view edits one app's own options in the
//  per-app popover. Nothing is shown on screen and no key is recorded for real.
//

import XCTest
@testable import Mos_Debug

final class PreferencesScrollingTests: XCTestCase {

    private typealias ID = PreferencesScrollingViewController.Identifier

    private var originalScroll: OPTIONS_SCROLL_DEFAULT!
    private var uiDefaults: UserDefaults!
    private var uiDefaultsSuite = ""

    override func setUp() {
        super.setUp()
        originalScroll = Options.shared.scroll
        // A fresh container, so the tests never edit the one they restore.
        Options.shared.scroll = OPTIONS_SCROLL_DEFAULT()
        uiDefaultsSuite = "ScrollioTests.scrolling.\(UUID().uuidString)"
        uiDefaults = UserDefaults(suiteName: uiDefaultsSuite)
    }

    override func tearDown() {
        Options.shared.scroll = originalScroll
        originalScroll = nil
        uiDefaults.removePersistentDomain(forName: uiDefaultsSuite)
        uiDefaults = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private var storyboard: NSStoryboard {
        return NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesScrollingViewController.self))
    }

    /// The tab as the window makes it: from its storyboard scene, which is a shell.
    private func makeController(target: Application? = nil, advanced: Bool = false) -> PreferencesScrollingViewController {
        let controller = storyboard.instantiateController(withIdentifier: PANEL_IDENTIFIER.scrolling) as! PreferencesScrollingViewController
        uiDefaults.set(advanced, forKey: PreferencesScrollingViewController.advancedExpandedDefaultsKey)
        controller.uiStateDefaults = uiDefaults
        controller.currentTargetApplication = target
        _ = controller.view
        return controller
    }

    private func makeApplication(inherit: Bool) -> Application {
        let application = Application(path: "/Applications/ScrollingTabTest.app")
        application.inherit = inherit
        return application
    }

    private func send(_ control: NSControl, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(control.sendAction(control.action, to: control.target), file: file, line: line)
    }

    private func set(_ checkbox: NSButton, _ on: Bool) {
        checkbox.state = on ? .on : .off
        send(checkbox)
    }

    private func drag(_ slider: NSSlider, to value: Double) {
        slider.doubleValue = value
        send(slider)
    }

    private func choose(_ feel: ScrollFeel, in controller: PreferencesScrollingViewController) {
        controller.feelControl.selectedSegment = feel.rawValue
        send(controller.feelControl)
    }

    private func text(_ key: String) -> String {
        return NSLocalizedString(key, comment: "")
    }

    private func allSubviews(of view: NSView) -> [NSView] {
        return view.subviews.flatMap { [$0] + allSubviews(of: $0) }
    }

    /// Where a view sits in the pane by its alignment rectangle (the root is not flipped).
    private func frame(of view: NSView, in controller: PreferencesScrollingViewController) -> NSRect {
        return controller.view.convert(view.alignmentRect(forFrame: view.frame), from: view.superview)
    }

    // MARK: - Pane

    func testPaneIsTheStoryboardSceneBuiltInCode() {
        let controller = makeController()
        XCTAssertEqual(controller.title, "Scrolling")
        XCTAssertEqual(controller.view.frame.width, PreferencesForm.contentWidth)
        XCTAssertEqual(controller.view.frame.size, controller.view.fittingSize)
        XCTAssertTrue(controller.view is NSVisualEffectView, "the background of every pane")
        XCTAssertEqual(controller.previewView.identifier, ID.preview)
        XCTAssertEqual(controller.scrollSmoothCheckBox.identifier, ID.smooth)
        XCTAssertEqual(controller.feelControl.identifier, ID.feel)
        XCTAssertEqual(controller.scrollSpeedSlider.identifier, ID.speed)
        XCTAssertEqual(controller.scrollReverseCheckBox.identifier, ID.reverse)
        XCTAssertEqual(controller.advancedButton.identifier, ID.advanced)
        XCTAssertEqual(controller.glideTimeSlider.identifier, ID.glideTime)
        XCTAssertEqual(controller.smallestStepSlider.identifier, ID.smallestStep)
        XCTAssertEqual(controller.trackpadEventsCheckBox.identifier, ID.trackpadEvents)
        XCTAssertEqual(controller.keyBindButtons.map(\.identifier), ScrollHoldKey.allCases.map(ID.key))
        XCTAssertEqual(controller.keyClearButtons.map(\.identifier), ScrollHoldKey.allCases.map(ID.keyClear))
        XCTAssertEqual(controller.resetToDefaultsButton.identifier, ID.reset)
    }

    func testControlsComeInTheAgreedOrder() {
        let controller = makeController(advanced: true)
        controller.view.layoutSubtreeIfNeeded()
        var order: [NSView] = [
            controller.previewView, controller.scrollSmoothCheckBox, controller.feelControl,
            controller.scrollSpeedSlider, controller.scrollReverseCheckBox, controller.advancedButton,
            controller.glideTimeSlider, controller.smallestStepSlider, controller.trackpadEventsCheckBox,
        ]
        order.append(contentsOf: controller.keyBindButtons)
        let tops: [CGFloat] = order.map { frame(of: $0, in: controller).maxY }
        XCTAssertEqual(tops, tops.sorted(by: >), "from the top of the pane down")
        XCTAssertEqual(Set(tops).count, tops.count)

        // The preview is the first thing on the tab, full width.
        let preview = frame(of: controller.previewView, in: controller)
        XCTAssertEqual(controller.view.bounds.maxY - preview.maxY, PreferencesForm.margin, accuracy: 0.5)
        XCTAssertEqual(preview.minX, PreferencesForm.margin, accuracy: 0.5)
        XCTAssertEqual(preview.width, PreferencesForm.contentWidth - 2 * PreferencesForm.margin, accuracy: 0.5)
        XCTAssertEqual(preview.height, ScrollPreviewView.preferredHeight, accuracy: 0.5)
        // "Reset to defaults" shares the line of "Advanced", at the right edge, and stays
        // there whether "Advanced" is open or not.
        let advanced = frame(of: controller.advancedButton, in: controller)
        let reset = frame(of: controller.resetToDefaultsButton, in: controller)
        XCTAssertEqual(advanced.minX, PreferencesForm.margin, accuracy: 1)
        XCTAssertEqual(reset.maxX, PreferencesForm.contentWidth - PreferencesForm.margin, accuracy: 1)
        XCTAssertEqual(reset.midY, advanced.midY, accuracy: 1.5)
        XCTAssertGreaterThan(reset.minX, advanced.maxX)
        let fromTop = controller.view.bounds.maxY - reset.maxY

        send(controller.advancedButton)
        controller.view.layoutSubtreeIfNeeded()
        let closedReset = frame(of: controller.resetToDefaultsButton, in: controller)
        XCTAssertEqual(controller.view.bounds.maxY - closedReset.maxY, fromTop, accuracy: 0.5)
        // Closed, that line is the last one of the tab.
        XCTAssertLessThanOrEqual(frame(of: controller.advancedButton, in: controller).minY, PreferencesForm.margin + 4)
    }

    func testTextsOfTheTab() {
        let controller = makeController(advanced: true)
        XCTAssertEqual(controller.scrollSmoothCheckBox.title, "Smooth scrolling")
        XCTAssertEqual(controller.scrollReverseCheckBox.title, "Reverse wheel direction")
        XCTAssertEqual(controller.advancedButton.title, "Advanced")
        XCTAssertEqual(controller.trackpadEventsCheckBox.title, "Trackpad-style events")
        XCTAssertEqual(controller.resetToDefaultsButton.title, "Reset to defaults")

        let shown = allSubviews(of: controller.view).compactMap { ($0 as? NSTextField)?.stringValue }
        let expected = [
            "Feel", "Speed", "Shorter", "Farther", "Glide time", "Smallest step", "While you hold a key",
            "Scroll faster", "Scroll sideways", "Pause smoothing",
            text("scrolling-smooth-hint"), text("scrolling-speed-hint"), text("scrolling-reverse-hint"),
            text("scrolling-glide-time-hint"), text("scrolling-step-hint"), text("scrolling-trackpad-events-hint"),
            text("scrolling-key-faster-hint"), text("scrolling-key-sideways-hint"), text("scrolling-key-pause-hint"),
        ]
        for line in expected {
            XCTAssertTrue(shown.contains(line), "\"\(line)\" is not on the tab")
        }
        // Nothing of the old tab is left.
        for old in ["Step", "Duration", "Dash Key", "Toggle Key", "Block Key", "Presets & Fast Scrolling…", "Preset"] {
            XCTAssertFalse(shown.contains(old), "\"\(old)\" is still on the tab")
        }
        XCTAssertFalse(allSubviews(of: controller.view).contains { $0 is NSStepper || $0 is NSPopUpButton })
    }

    // MARK: - Smooth scrolling

    func testSmoothCheckboxWritesSmooth() {
        let controller = makeController()
        XCTAssertEqual(controller.scrollSmoothCheckBox.state, .on, "on by default")

        set(controller.scrollSmoothCheckBox, false)
        XCTAssertFalse(Options.shared.scroll.smooth)
        set(controller.scrollSmoothCheckBox, true)
        XCTAssertTrue(Options.shared.scroll.smooth)

        Options.shared.scroll.smooth = false
        controller.syncViewWithOptions()
        XCTAssertEqual(controller.scrollSmoothCheckBox.state, .off)
    }

    func testWithoutSmoothingOnlyDirectionAndKeysStayEditable() {
        let controller = makeController(advanced: true)
        let smoothOnly: [NSControl] = [
            controller.feelControl, controller.scrollSpeedSlider, controller.glideTimeSlider,
            controller.smallestStepSlider, controller.trackpadEventsCheckBox,
        ]
        XCTAssertTrue(smoothOnly.allSatisfy(\.isEnabled))

        set(controller.scrollSmoothCheckBox, false)

        XCTAssertTrue(smoothOnly.allSatisfy { !$0.isEnabled })
        XCTAssertTrue(controller.scrollSmoothCheckBox.isEnabled)
        XCTAssertTrue(controller.scrollReverseCheckBox.isEnabled)
        XCTAssertTrue(controller.keyBindButtons.allSatisfy(\.isEnabled))
        XCTAssertTrue(controller.keyClearButtons.allSatisfy(\.isEnabled))
        XCTAssertTrue(controller.advancedButton.isEnabled)
        // What was chosen still shows.
        XCTAssertEqual(controller.feelControl.selectedSegment, ScrollFeel.smooth.rawValue)

        set(controller.scrollSmoothCheckBox, true)
        XCTAssertTrue(smoothOnly.allSatisfy(\.isEnabled))
    }

    // MARK: - Feel and glide time

    func testFeelShowsTheFivePresetsWithSmoothSelected() {
        let controller = makeController()
        let feel = controller.feelControl!
        XCTAssertEqual(feel.segmentCount, 5)
        XCTAssertEqual((0..<5).map { feel.label(forSegment: $0) }, ["Direct", "Quick", "Smooth", "Glide", "Float"])
        XCTAssertEqual(feel.selectedSegment, ScrollFeel.smooth.rawValue)
        XCTAssertEqual(controller.feelHintLabel.stringValue, ScrollFeel.smooth.localizedHint)
        XCTAssertEqual(feel.accessibilityLabel(), "Feel")
    }

    func testEveryFeelRoundTrips() {
        let controller = makeController(advanced: true)
        for feel in ScrollFeel.allCases {
            // Picking it writes its Duration and moves the glide time slider.
            choose(feel, in: controller)
            XCTAssertEqual(Options.shared.scroll.duration, feel.duration, "\(feel)")
            XCTAssertEqual(controller.glideTimeSlider.doubleValue, feel.duration, accuracy: 1e-9, "\(feel)")
            XCTAssertEqual(controller.glideTimeValueLabel.stringValue, ScrollSliderSetting.glideTime.text(feel.duration))
            XCTAssertEqual(controller.feelHintLabel.stringValue, feel.localizedHint, "\(feel)")

            // And a stored Duration of that value selects it again.
            Options.shared.scroll.duration = 1.5
            controller.syncViewWithOptions()
            XCTAssertEqual(controller.feelControl.selectedSegment, -1)
            Options.shared.scroll.duration = feel.duration
            controller.syncViewWithOptions()
            XCTAssertEqual(controller.feelControl.selectedSegment, feel.rawValue, "\(feel)")
        }
    }

    func testFeelOnlyWritesDuration() throws {
        let controller = makeController()
        Options.shared.scroll.speed = 6.5
        let before = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(Options.shared.scroll)) as? [String: AnyHashable])

        choose(.float, in: controller)

        var after = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(Options.shared.scroll)) as? [String: AnyHashable])
        XCTAssertEqual(after["duration"], 4.6 as AnyHashable)
        after["duration"] = before["duration"]
        XCTAssertEqual(after, before)
    }

    func testGlideTimeOffAPresetLeavesFeelWithNothingSelected() {
        let controller = makeController(advanced: true)
        let slider = controller.glideTimeSlider!
        XCTAssertEqual(slider.minValue, 1)
        XCTAssertEqual(slider.maxValue, 5)
        XCTAssertEqual(slider.doubleValue, 3.69, accuracy: 1e-9)

        drag(slider, to: 3.904)

        XCTAssertEqual(Options.shared.scroll.duration, 3.9, "rounded to hundredths")
        XCTAssertEqual(controller.feelControl.selectedSegment, -1)
        XCTAssertEqual(controller.feelHintLabel.stringValue, ScrollFeel.customHint)
        XCTAssertEqual(controller.glideTimeValueLabel.stringValue, "3.90")

        // Back on a preset's value the preset is selected again: the two never disagree.
        drag(slider, to: 4.35)
        XCTAssertEqual(Options.shared.scroll.duration, 4.35)
        XCTAssertEqual(controller.feelControl.selectedSegment, ScrollFeel.glide.rawValue)
        XCTAssertEqual(controller.feelHintLabel.stringValue, ScrollFeel.glide.localizedHint)

        // The ends of the old Duration range.
        drag(slider, to: 0.2)
        XCTAssertEqual(Options.shared.scroll.duration, 1)
        drag(slider, to: 7)
        XCTAssertEqual(Options.shared.scroll.duration, 5)
        XCTAssertEqual(controller.feelControl.selectedSegment, -1)
    }

    func testACustomDurationShowsAsCustomWhenTheTabOpens() {
        Options.shared.scroll.duration = 2.6
        let controller = makeController()
        XCTAssertEqual(controller.feelControl.selectedSegment, -1)
        XCTAssertEqual(controller.feelHintLabel.stringValue, ScrollFeel.customHint)
        XCTAssertEqual(controller.glideTimeSlider.doubleValue, 2.6, accuracy: 1e-9)
    }

    // MARK: - Speed and smallest step

    func testSpeedSliderWritesSpeedOverTheFullRange() {
        let controller = makeController()
        let slider = controller.scrollSpeedSlider!
        XCTAssertEqual(slider.minValue, 1)
        XCTAssertEqual(slider.maxValue, 10, "the old range: the default of 6.3 lies above 5")
        XCTAssertEqual(slider.doubleValue, 6.3, accuracy: 1e-9)
        XCTAssertEqual(controller.scrollSpeedValueLabel.stringValue, "6.3")
        XCTAssertEqual(slider.accessibilityLabel(), "Speed")

        drag(slider, to: 3.14)
        XCTAssertEqual(Options.shared.scroll.speed, 3.1, "rounded to tenths")
        XCTAssertEqual(controller.scrollSpeedValueLabel.stringValue, "3.1")

        drag(slider, to: 10)
        XCTAssertEqual(Options.shared.scroll.speed, 10)
        XCTAssertEqual(controller.scrollSpeedValueLabel.stringValue, "10.0")
        drag(slider, to: 1)
        XCTAssertEqual(Options.shared.scroll.speed, 1)
    }

    func testSmallestStepSliderWritesStep() {
        let controller = makeController(advanced: true)
        let slider = controller.smallestStepSlider!
        XCTAssertEqual(slider.minValue, 0.01)
        XCTAssertEqual(slider.maxValue, 100)
        XCTAssertEqual(slider.doubleValue, 33.6, accuracy: 1e-9)
        XCTAssertEqual(controller.smallestStepValueLabel.stringValue, "33.6")
        XCTAssertEqual(slider.accessibilityLabel(), "Smallest step")

        drag(slider, to: 12.34)
        XCTAssertEqual(Options.shared.scroll.step, 12.3)
        XCTAssertEqual(controller.smallestStepValueLabel.stringValue, "12.3")
        XCTAssertEqual(Options.shared.scroll.duration, 3.69, "nothing else moves")
        XCTAssertEqual(Options.shared.scroll.speed, 6.3)
    }

    // MARK: - Direction

    func testReverseCheckboxTurnsEverythingOnOrTheMainFlagOff() {
        let scroll = Options.shared.scroll
        scroll.reverse = false
        scroll.reverseVertical = false
        scroll.reverseHorizontal = false
        let controller = makeController()
        XCTAssertEqual(controller.scrollReverseCheckBox.state, .off)

        set(controller.scrollReverseCheckBox, true)
        XCTAssertTrue(scroll.reverse)
        XCTAssertTrue(scroll.reverseVertical)
        XCTAssertTrue(scroll.reverseHorizontal)
        XCTAssertEqual(controller.scrollReverseCheckBox.state, .on)

        set(controller.scrollReverseCheckBox, false)
        XCTAssertFalse(scroll.reverse)
        XCTAssertTrue(scroll.reverseVertical, "off only clears the main flag")
        XCTAssertTrue(scroll.reverseHorizontal)
        XCTAssertEqual(controller.scrollReverseCheckBox.state, .off)
    }

    // MARK: - Trackpad-style events

    func testTrackpadStyleEventsIsAPlainSwitchThatLeavesDurationAlone() {
        let controller = makeController(advanced: true)
        XCTAssertEqual(controller.trackpadEventsCheckBox.state, .off, "off by default")

        let durations: [Double] = ScrollFeel.allCases.map(\.duration) + [1.0, 2.6, 5.0]
        for duration in durations {
            Options.shared.scroll.duration = duration
            controller.syncViewWithOptions()

            set(controller.trackpadEventsCheckBox, true)
            XCTAssertTrue(Options.shared.scroll.smoothSimTrackpad)
            XCTAssertEqual(Options.shared.scroll.duration, duration, "on at \(duration)")
            XCTAssertEqual(controller.glideTimeSlider.doubleValue, duration, accuracy: 1e-9)

            set(controller.trackpadEventsCheckBox, false)
            XCTAssertFalse(Options.shared.scroll.smoothSimTrackpad)
            XCTAssertEqual(Options.shared.scroll.duration, duration, "off at \(duration)")
        }
    }

    // MARK: - Keys

    func testKeyRowsShowTheStoredKeysAndClearThem() {
        let controller = makeController(advanced: true)
        XCTAssertEqual(controller.keyBindButtons.map(\.title), ["⌥ Option", "⇧ Shift", "⌘ Command"], "the default keys")
        XCTAssertTrue(controller.keyClearButtons.allSatisfy { $0.isEnabled && $0.alphaValue == 1 })
        XCTAssertTrue(controller.keyClearButtons.allSatisfy { $0.accessibilityLabel() == "Clear key" })

        send(controller.keyClearButtons[ScrollHoldKey.sideways.rawValue])

        XCTAssertNil(Options.shared.scroll.toggle)
        XCTAssertNotNil(Options.shared.scroll.dash)
        XCTAssertNotNil(Options.shared.scroll.block)
        XCTAssertEqual(controller.keyBindButtons.map(\.title), ["⌥ Option", "Disabled", "⌘ Command"])
        let cleared = controller.keyClearButtons[ScrollHoldKey.sideways.rawValue]
        XCTAssertFalse(cleared.isEnabled)
        XCTAssertEqual(cleared.alphaValue, 0, "nothing to clear")

        send(controller.keyClearButtons[ScrollHoldKey.faster.rawValue])
        send(controller.keyClearButtons[ScrollHoldKey.pause.rawValue])
        XCTAssertNil(Options.shared.scroll.dash)
        XCTAssertNil(Options.shared.scroll.block)
    }

    func testARecordedKeyGoesToTheRowThatRecorded() {
        let controller = makeController(advanced: true)
        let recorder = KeyRecorder()
        let stored: [(ScrollHoldKey, UInt16, String)] = [
            (.faster, KeyCode.controlL, "⌃ Control"),
            (.sideways, KeyCode.optionL, "⌥ Option"),
            (.pause, KeyCode.shiftL, "⇧ Shift"),
        ]
        for (key, code, name) in stored {
            controller.recordingKey = key
            let event = InputEvent(type: .keyboard, code: code, modifiers: [], phase: .down, source: .hidPP, device: nil)
            controller.onEventRecorded(recorder, didRecordEvent: event, isDuplicate: false)

            XCTAssertEqual(key.hotkey(in: Options.shared.scroll), ScrollHotkey(type: .keyboard, code: code), "\(key)")
            XCTAssertEqual(controller.keyBindButtons[key.rawValue].title, name)
            XCTAssertNil(controller.recordingKey)
        }
        XCTAssertEqual(Options.shared.scroll.dash, ScrollHotkey(type: .keyboard, code: KeyCode.controlL))
        XCTAssertEqual(Options.shared.scroll.toggle, ScrollHotkey(type: .keyboard, code: KeyCode.optionL))
        XCTAssertEqual(Options.shared.scroll.block, ScrollHotkey(type: .keyboard, code: KeyCode.shiftL))

        // An event that arrives while no row records changes nothing.
        let stray = InputEvent(type: .keyboard, code: KeyCode.commandL, modifiers: [], phase: .down, source: .hidPP, device: nil)
        controller.onEventRecorded(recorder, didRecordEvent: stray, isDuplicate: false)
        XCTAssertEqual(Options.shared.scroll.dash, ScrollHotkey(type: .keyboard, code: KeyCode.controlL))
    }

    func testHoldKeysMapToTheThreeHotkeys() {
        let scroll = OPTIONS_SCROLL_DEFAULT()
        XCTAssertEqual(ScrollHoldKey.allCases, [.faster, .sideways, .pause])
        XCTAssertEqual(ScrollHoldKey.faster.hotkey(in: scroll), scroll.dash)
        XCTAssertEqual(ScrollHoldKey.sideways.hotkey(in: scroll), scroll.toggle)
        XCTAssertEqual(ScrollHoldKey.pause.hotkey(in: scroll), scroll.block)
        // The model's default keys are what every Mac app expects and are not changed here.
        XCTAssertEqual(scroll.dash, ScrollHotkey(type: .keyboard, code: KeyCode.optionL))
        XCTAssertEqual(scroll.toggle, ScrollHotkey(type: .keyboard, code: KeyCode.shiftL))
        XCTAssertEqual(scroll.block, ScrollHotkey(type: .keyboard, code: KeyCode.commandL))
    }

    // MARK: - Advanced

    func testAdvancedIsClosedByDefaultAndHidesItsRows() {
        uiDefaults.removeObject(forKey: PreferencesScrollingViewController.advancedExpandedDefaultsKey)
        let controller = storyboard.instantiateController(withIdentifier: PANEL_IDENTIFIER.scrolling) as! PreferencesScrollingViewController
        controller.uiStateDefaults = uiDefaults
        _ = controller.view

        XCTAssertFalse(controller.isAdvancedExpanded)
        XCTAssertEqual(controller.advancedRows.count, 7, "two sliders, the checkbox, the keys' title and three keys")
        XCTAssertTrue(controller.advancedRows.allSatisfy(\.isHidden))
        // What is always there.
        let alwaysThere: [NSView] = [
            controller.previewView, controller.scrollSmoothCheckBox, controller.feelControl,
            controller.scrollSpeedSlider, controller.scrollReverseCheckBox, controller.advancedButton,
            controller.resetToDefaultsButton,
        ]
        for view in alwaysThere {
            XCTAssertFalse(view.isHiddenOrHasHiddenAncestor)
        }
        XCTAssertFalse(controller.advancedButton.isAccessibilityExpanded())
    }

    func testAdvancedOpensClosesAndIsRemembered() {
        let key = PreferencesScrollingViewController.advancedExpandedDefaultsKey
        let controller = makeController()
        let closedHeight = controller.view.fittingSize.height

        send(controller.advancedButton)

        XCTAssertTrue(controller.isAdvancedExpanded)
        XCTAssertTrue(controller.advancedRows.allSatisfy { !$0.isHidden })
        XCTAssertTrue(uiDefaults.bool(forKey: key))
        XCTAssertTrue(controller.advancedButton.isAccessibilityExpanded())
        let openHeight = controller.view.fittingSize.height
        XCTAssertGreaterThan(openHeight, closedHeight + 200)
        XCTAssertEqual(controller.view.frame.height, openHeight, "the pane follows its content")

        // The next time the tab is made it opens as it was left.
        let again = storyboard.instantiateController(withIdentifier: PANEL_IDENTIFIER.scrolling) as! PreferencesScrollingViewController
        again.uiStateDefaults = uiDefaults
        _ = again.view
        XCTAssertTrue(again.isAdvancedExpanded)
        XCTAssertEqual(again.view.frame.height, openHeight)

        send(controller.advancedButton)
        XCTAssertFalse(controller.isAdvancedExpanded)
        XCTAssertTrue(controller.advancedRows.allSatisfy(\.isHidden))
        XCTAssertFalse(uiDefaults.bool(forKey: key))
        XCTAssertEqual(controller.view.frame.height, closedHeight)
    }

    func testAdvancedStateIsNotAScrollOption() {
        let controller = makeController()
        send(controller.advancedButton)
        XCTAssertEqual(Options.shared.scroll, OPTIONS_SCROLL_DEFAULT())
        XCTAssertFalse(controller.hasSettingsToReset)
    }

    // MARK: - Reset

    func testResetIsOnlyOfferedWhenSomethingDiffers() {
        let controller = makeController()
        XCTAssertFalse(controller.hasSettingsToReset)
        XCTAssertFalse(controller.resetToDefaultsButton.isEnabled)

        choose(.glide, in: controller)

        XCTAssertTrue(controller.hasSettingsToReset)
        XCTAssertTrue(controller.resetToDefaultsButton.isEnabled)
    }

    func testResetRestoresTheDefaultsAndLeavesAdvancedOpen() {
        let controller = makeController(advanced: true)
        let scroll = Options.shared.scroll
        scroll.smooth = false
        scroll.reversesWheel = false
        scroll.speed = 2.0
        scroll.duration = 4.9
        scroll.step = 12
        scroll.smoothSimTrackpad = true
        scroll.dash = nil
        scroll.toggle = ScrollHotkey(type: .keyboard, code: KeyCode.controlL)
        scroll.block = nil
        controller.syncViewWithOptions()
        XCTAssertTrue(controller.resetToDefaultsButton.isEnabled)

        send(controller.resetToDefaultsButton)

        let reset = Options.shared.scroll
        XCTAssertEqual(reset, OPTIONS_SCROLL_DEFAULT())
        XCTAssertTrue(reset.smooth)
        XCTAssertEqual(reset.duration, 3.69)
        XCTAssertEqual(reset.speed, 6.3)
        XCTAssertEqual(reset.step, 33.6)
        XCTAssertFalse(reset.smoothSimTrackpad)
        XCTAssertEqual(controller.feelControl.selectedSegment, ScrollFeel.smooth.rawValue)
        XCTAssertEqual(controller.scrollSpeedSlider.doubleValue, 6.3, accuracy: 1e-9)
        XCTAssertEqual(controller.smallestStepSlider.doubleValue, 33.6, accuracy: 1e-9)
        XCTAssertEqual(controller.trackpadEventsCheckBox.state, .off)
        XCTAssertEqual(controller.scrollReverseCheckBox.state, .on)
        XCTAssertEqual(controller.keyBindButtons.map(\.title), ["⌥ Option", "⇧ Shift", "⌘ Command"])
        XCTAssertFalse(controller.resetToDefaultsButton.isEnabled)
        XCTAssertTrue(controller.isAdvancedExpanded, "reset closes nothing")
        XCTAssertTrue(uiDefaults.bool(forKey: PreferencesScrollingViewController.advancedExpandedDefaultsKey))
    }

    // MARK: - Preview

    func testPreviewFollowsTheOptions() {
        let controller = makeController()
        var expected = ScrollPreviewView.Scene()
        expected.smoothing = true
        expected.duration = 3.69
        expected.speed = 6.3
        expected.reversed = true
        expected.emphasis = .wheel
        XCTAssertEqual(controller.previewView.scene, expected)
        XCTAssertFalse(controller.previewView.isHidden)

        choose(.float, in: controller)
        drag(controller.scrollSpeedSlider, to: 8.5)
        set(controller.scrollReverseCheckBox, false)
        set(controller.scrollSmoothCheckBox, false)

        expected.smoothing = false
        expected.duration = 4.6
        expected.speed = 8.5
        expected.reversed = false
        XCTAssertEqual(controller.previewView.scene, expected)

        send(controller.resetToDefaultsButton)
        XCTAssertEqual(controller.previewView.scene.duration, 3.69)
        XCTAssertTrue(controller.previewView.scene.smoothing)
    }

    func testPreviewPointsOutAKeyWhileItsRowIsHoveredFocusedOrRecording() {
        let controller = makeController(advanced: true)
        XCTAssertEqual(controller.previewView.scene.emphasis, .wheel)

        let expected: [(ScrollHoldKey, ScrollPreviewView.Emphasis)] = [
            (.faster, .faster), (.sideways, .sideways), (.pause, .paused),
        ]
        for (key, emphasis) in expected {
            controller.keyRowHoverChanged(key, inside: true)
            XCTAssertEqual(controller.previewView.scene.emphasis, emphasis, "pointer over \(key)")
            controller.keyRowHoverChanged(key, inside: false)
            XCTAssertEqual(controller.previewView.scene.emphasis, .wheel)

            controller.keyFocusChanged(key, focused: true)
            XCTAssertEqual(controller.previewView.scene.emphasis, emphasis, "focus on \(key)")
            controller.keyFocusChanged(key, focused: false)
            XCTAssertEqual(controller.previewView.scene.emphasis, .wheel)

            controller.recordingKey = key
            XCTAssertEqual(controller.previewView.scene.emphasis, emphasis, "recording \(key)")
            controller.onRecordingStopped(KeyRecorder(), didRecord: false)
            XCTAssertEqual(controller.previewView.scene.emphasis, .wheel)
        }

        // Leaving one row after entering the next keeps the next one.
        controller.keyRowHoverChanged(.faster, inside: true)
        controller.keyRowHoverChanged(.sideways, inside: true)
        controller.keyRowHoverChanged(.faster, inside: false)
        XCTAssertEqual(controller.previewView.scene.emphasis, .sideways)
        // The row that records wins over the pointer.
        controller.recordingKey = .pause
        XCTAssertEqual(controller.previewView.scene.emphasis, .paused)
        controller.recordingKey = nil
        XCTAssertEqual(controller.previewView.scene.emphasis, .sideways)
    }

    func testPreviewOnlyPointsOutKeysWhileAdvancedIsOpen() {
        let controller = makeController(advanced: true)
        controller.keyRowHoverChanged(.faster, inside: true)
        XCTAssertEqual(controller.previewView.scene.emphasis, .faster)

        send(controller.advancedButton)
        XCTAssertFalse(controller.isAdvancedExpanded)
        XCTAssertEqual(controller.previewView.scene.emphasis, .wheel)

        // Closed: nothing a hidden row reports reaches the preview.
        controller.keyRowHoverChanged(.sideways, inside: true)
        controller.keyFocusChanged(.pause, focused: true)
        controller.recordingKey = .faster
        XCTAssertEqual(controller.previewView.scene.emphasis, .wheel)
        XCTAssertEqual(controller.previewEmphasis, .wheel)
    }

    func testKeyRowsReportThePointerThroughTrackingAreas() {
        let controller = makeController(advanced: true)
        let rows = controller.advancedRows.suffix(ScrollHoldKey.allCases.count)
        for row in rows {
            XCTAssertEqual(row.trackingAreas.count, 1)
            let area = row.trackingAreas[0]
            XCTAssertTrue(area.owner === controller)
            XCTAssertTrue(area.options.contains(.mouseEnteredAndExited))
            XCTAssertTrue(area.options.contains(.inVisibleRect))
        }
        // The recorder buttons report the keyboard focus.
        for (index, button) in controller.keyBindButtons.enumerated() {
            let recorder = button as? ScrollKeyRecorderButton
            XCTAssertNotNil(recorder?.onFocusChange)
            recorder?.onFocusChange?(true)
            XCTAssertEqual(controller.previewView.scene.emphasis, ScrollHoldKey.allCases[index].emphasis)
            recorder?.onFocusChange?(false)
        }
        XCTAssertEqual(controller.previewView.scene.emphasis, .wheel)
    }

    // MARK: - Per-app settings

    func testAnAppWithItsOwnSettingsEditsOnlyItsOwn() {
        let application = makeApplication(inherit: false)
        let controller = makeController(target: application, advanced: true)

        set(controller.scrollSmoothCheckBox, false)
        set(controller.scrollSmoothCheckBox, true)
        choose(.direct, in: controller)
        drag(controller.scrollSpeedSlider, to: 4.2)
        set(controller.scrollReverseCheckBox, false)
        drag(controller.smallestStepSlider, to: 20)
        set(controller.trackpadEventsCheckBox, true)
        send(controller.keyClearButtons[ScrollHoldKey.faster.rawValue])

        XCTAssertEqual(application.scroll.duration, 2.0)
        XCTAssertEqual(application.scroll.speed, 4.2)
        XCTAssertFalse(application.scroll.reverse)
        XCTAssertEqual(application.scroll.step, 20)
        XCTAssertTrue(application.scroll.smoothSimTrackpad)
        XCTAssertNil(application.scroll.dash)
        XCTAssertEqual(Options.shared.scroll, OPTIONS_SCROLL_DEFAULT(), "the global options are untouched")
        XCTAssertTrue(controller.hasSettingsToReset)

        send(controller.resetToDefaultsButton)
        XCTAssertEqual(application.scroll, OPTIONS_SCROLL_DEFAULT())
        XCTAssertEqual(Options.shared.scroll, OPTIONS_SCROLL_DEFAULT())
        XCTAssertFalse(controller.resetToDefaultsButton.isEnabled)
    }

    func testAnAppThatInheritsShowsTheGlobalValuesGreyedOut() {
        Options.shared.scroll.speed = 8.5
        Options.shared.scroll.duration = 4.35
        Options.shared.scroll.smoothSimTrackpad = true
        let application = makeApplication(inherit: true)
        application.scroll.speed = 1.5
        let controller = makeController(target: application, advanced: true)

        XCTAssertEqual(controller.scrollSpeedSlider.doubleValue, 8.5, accuracy: 1e-9)
        XCTAssertEqual(controller.feelControl.selectedSegment, ScrollFeel.glide.rawValue)
        XCTAssertEqual(controller.trackpadEventsCheckBox.state, .on)
        var controls: [NSControl] = [
            controller.scrollSmoothCheckBox, controller.feelControl, controller.scrollSpeedSlider,
            controller.scrollReverseCheckBox, controller.glideTimeSlider, controller.smallestStepSlider,
            controller.trackpadEventsCheckBox, controller.resetToDefaultsButton,
        ]
        controls.append(contentsOf: controller.keyBindButtons)
        controls.append(contentsOf: controller.keyClearButtons)
        XCTAssertTrue(controls.allSatisfy { !$0.isEnabled })
        XCTAssertTrue(controller.advancedButton.isEnabled, "looking is always allowed")
        XCTAssertFalse(controller.hasSettingsToReset)

        // The popover's "inherit" switch turns the app's own values on.
        application.inherit = false
        controller.syncViewWithOptions()
        XCTAssertEqual(controller.scrollSpeedSlider.doubleValue, 1.5, accuracy: 1e-9)
        XCTAssertEqual(controller.feelControl.selectedSegment, ScrollFeel.smooth.rawValue)
        XCTAssertTrue(controller.scrollSmoothCheckBox.isEnabled)
        XCTAssertTrue(controller.scrollSpeedSlider.isEnabled)
        XCTAssertTrue(controller.keyBindButtons.allSatisfy(\.isEnabled))
        XCTAssertTrue(controller.hasSettingsToReset)
    }

    func testThePerAppViewHasNoPreview() {
        let global = makeController()
        let perApp = makeController(target: makeApplication(inherit: false))
        XCTAssertFalse(global.previewView.isHidden)
        XCTAssertTrue(perApp.previewView.isHidden)
        XCTAssertEqual(
            global.view.fittingSize.height - perApp.view.fittingSize.height,
            ScrollPreviewView.preferredHeight + PreferencesScrollingViewController.rowSpacing,
            accuracy: 0.5,
            "shorter by the preview and the space under it"
        )
    }

    func testThePerAppPopoverEmbedsTheTabWithItsApplication() throws {
        let application = makeApplication(inherit: false)
        application.scroll.speed = 4.2
        let container = try XCTUnwrap(
            storyboard.instantiateController(withIdentifier: PANEL_IDENTIFIER.scrollingWithApplication)
                as? PreferencesScrollingWithApplicationViewController
        )
        container.updateTargetApplication(with: application)
        _ = container.view
        let tab = try XCTUnwrap(container.children.first as? PreferencesScrollingViewController)
        XCTAssertTrue(tab.isViewLoaded, "the settings load with the popover")
        tab.uiStateDefaults = uiDefaults

        XCTAssertTrue(tab.currentTargetApplication === application)
        XCTAssertEqual(container.preferredContentSize.width, PreferencesForm.contentWidth, "sized before it shows")
        XCTAssertEqual(container.preferredContentSize.height, tab.view.fittingSize.height + 58, accuracy: 0.5)
        XCTAssertEqual(tab.scrollSpeedSlider.doubleValue, 4.2, accuracy: 1e-9)
        XCTAssertTrue(tab.previewView.isHidden)
        XCTAssertEqual(container.inheritGlobalSettingCheckBox.state, .off)

        // The popover is as tall as the app's header and the settings under it, and
        // follows when "Advanced" opens and closes.
        tab.setAdvancedExpanded(false)
        container.fitToContent()
        let closed = container.preferredContentSize
        XCTAssertEqual(closed.width, PreferencesForm.contentWidth)
        XCTAssertEqual(closed.height, tab.view.fittingSize.height + 58, accuracy: 0.5)

        tab.setAdvancedExpanded(true)
        let open = container.preferredContentSize
        XCTAssertEqual(open.height, tab.view.fittingSize.height + 58, accuracy: 0.5)
        XCTAssertGreaterThan(open.height, closed.height + 200)

        tab.setAdvancedExpanded(false)
        XCTAssertEqual(container.preferredContentSize, closed)

        // "Inherit" greys the settings out.
        container.inheritGlobalSettingCheckBox.state = .on
        container.inheritGlobalSettingClick(container.inheritGlobalSettingCheckBox)
        XCTAssertTrue(application.inherit)
        XCTAssertFalse(tab.scrollSpeedSlider.isEnabled)
        XCTAssertEqual(tab.scrollSpeedSlider.doubleValue, 6.3, accuracy: 1e-9, "the global value")
    }

    // MARK: - Layout

    func testRowsSitOnTheFormGrid() {
        let controller = makeController(advanced: true)
        controller.view.layoutSubtreeIfNeeded()
        var controls: [NSView] = [
            controller.scrollSmoothCheckBox, controller.feelControl, controller.scrollSpeedSlider,
            controller.scrollReverseCheckBox, controller.glideTimeSlider, controller.smallestStepSlider,
            controller.trackpadEventsCheckBox,
        ]
        controls.append(contentsOf: controller.keyBindButtons)
        for control in controls {
            let rect = frame(of: control, in: controller)
            XCTAssertEqual(rect.minX, 171, accuracy: 1, "\(control.identifier?.rawValue ?? "")")
            XCTAssertLessThanOrEqual(rect.maxX, 430.5, "\(control.identifier?.rawValue ?? "")")
        }
        // The five presets fill the control column, each wide enough for its name.
        let feel = frame(of: controller.feelControl, in: controller)
        XCTAssertEqual(feel.width, PreferencesForm.controlWidth, accuracy: 1)
        let font = controller.feelControl.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let segmentWidth = PreferencesForm.controlWidth / CGFloat(controller.feelControl.segmentCount)
        for segment in 0..<controller.feelControl.segmentCount {
            let name = controller.feelControl.label(forSegment: segment) ?? ""
            let needed = (name as NSString).size(withAttributes: [.font: font]).width
            XCTAssertLessThan(needed + 8, segmentWidth, "\(name) fits its segment")
        }
        // Row titles end where the label column ends.
        let rowTitles = [
            "Mouse wheel", "Feel", "Speed", "Direction", "Glide time", "Smallest step", "Apps",
            "Scroll faster", "Scroll sideways", "Pause smoothing",
        ]
        let fields: [NSTextField] = allSubviews(of: controller.view).compactMap { $0 as? NSTextField }
        let titles = fields.filter { rowTitles.contains($0.stringValue) }
        XCTAssertEqual(titles.count, rowTitles.count)
        for title in titles {
            XCTAssertEqual(frame(of: title, in: controller).maxX, 156, accuracy: 0.5, title.stringValue)
            XCTAssertEqual(title.alignment, .right)
        }
    }

    func testExplanationsAreShortLinesInTheHintStyle() {
        let controller = makeController(advanced: true)
        controller.view.layoutSubtreeIfNeeded()
        let oneLine = PreferencesForm.makeHint("X").fittingSize.height
        let keys = [
            "scrolling-smooth-hint", "scrolling-speed-hint", "scrolling-reverse-hint",
            "scrolling-glide-time-hint", "scrolling-step-hint",
            "scrolling-key-faster-hint", "scrolling-key-sideways-hint", "scrolling-key-pause-hint",
        ]
        let fields = allSubviews(of: controller.view).compactMap { $0 as? NSTextField }
        for key in keys {
            let field = fields.first { $0.stringValue == text(key) }
            XCTAssertEqual(field?.font?.pointSize, PreferencesForm.hintFontSize, key)
            XCTAssertEqual(field?.textColor, .secondaryLabelColor, key)
            XCTAssertEqual(field?.frame.height ?? 0, oneLine, accuracy: 0.5, "\(key) takes one line")
        }
        // The one explanation with a second sentence takes two lines.
        let trackpad = fields.first { $0.stringValue == text("scrolling-trackpad-events-hint") }
        XCTAssertEqual(trackpad?.frame.height ?? 0, 2 * oneLine, accuracy: 0.5)
        // Every preset's line fits the room kept under the control, so the tab never jumps.
        let lines: [String] = ScrollFeel.allCases.map(\.localizedHint) + [ScrollFeel.customHint]
        for line in lines {
            controller.feelHintLabel.stringValue = line
            controller.view.layoutSubtreeIfNeeded()
            XCTAssertEqual(controller.feelHintLabel.frame.height, oneLine, accuracy: 0.5, line)
        }
    }

    func testPickingAFeelNeverChangesTheHeight() {
        let controller = makeController(advanced: true)
        let height = controller.view.fittingSize.height
        for feel in ScrollFeel.allCases {
            choose(feel, in: controller)
            XCTAssertEqual(controller.view.fittingSize.height, height, "\(feel)")
        }
        drag(controller.glideTimeSlider, to: 2.6)
        XCTAssertEqual(controller.view.fittingSize.height, height, "custom")
    }
}

/// Renders the tab off screen for a look at it: light and dark, "Advanced" closed and
/// open, the tab and the per-app popover. Only runs when asked to:
/// `TEST_RUNNER_SCROLLIO_SHOTS_DIR=<folder> xcodebuild … test -only-testing:MosTests/PreferencesScrollingRenderTests`.
final class PreferencesScrollingRenderTests: XCTestCase {

    private var originalScroll: OPTIONS_SCROLL_DEFAULT!
    private var uiDefaults: UserDefaults!
    private var uiDefaultsSuite = ""

    override func setUp() {
        super.setUp()
        originalScroll = Options.shared.scroll
        Options.shared.scroll = OPTIONS_SCROLL_DEFAULT()
        uiDefaultsSuite = "ScrollioTests.scrolling-render.\(UUID().uuidString)"
        uiDefaults = UserDefaults(suiteName: uiDefaultsSuite)
    }

    override func tearDown() {
        Options.shared.scroll = originalScroll
        originalScroll = nil
        uiDefaults.removePersistentDomain(forName: uiDefaultsSuite)
        uiDefaults = nil
        super.tearDown()
    }

    func testRenderTheTab() throws {
        guard let folder = ProcessInfo.processInfo.environment["SCROLLIO_SHOTS_DIR"], !folder.isEmpty else {
            throw XCTSkip("set TEST_RUNNER_SCROLLIO_SHOTS_DIR to render the Scrolling tab")
        }
        let directory = URL(fileURLWithPath: folder, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesScrollingViewController.self))
        let key = PreferencesScrollingViewController.advancedExpandedDefaultsKey

        for advanced in [false, true] {
            uiDefaults.set(advanced, forKey: key)
            let state = advanced ? "advanced" : "basic"

            // The defaults: the "Smooth" feel at speed 6.3.
            Options.shared.scroll = OPTIONS_SCROLL_DEFAULT()
            let tab = storyboard.instantiateController(withIdentifier: PANEL_IDENTIFIER.scrolling) as! PreferencesScrollingViewController
            tab.uiStateDefaults = uiDefaults
            try render(tab.view, name: "tab-\(state)", into: directory)

            // A custom glide time, smoothing off, a key cleared.
            Options.shared.scroll.duration = 2.6
            Options.shared.scroll.toggle = nil
            tab.syncViewWithOptions()
            try render(tab.view, name: "tab-\(state)-custom", into: directory)
            Options.shared.scroll.smooth = false
            tab.syncViewWithOptions()
            try render(tab.view, name: "tab-\(state)-smooth-off", into: directory)

            // The per-app popover, with settings of its own and inheriting.
            Options.shared.scroll = OPTIONS_SCROLL_DEFAULT()
            for inherit in [false, true] {
                let application = Application(path: "/System/Applications/Calculator.app")
                application.inherit = inherit
                application.scroll.duration = ScrollFeel.direct.duration
                let container = storyboard.instantiateController(withIdentifier: PANEL_IDENTIFIER.scrollingWithApplication)
                    as! PreferencesScrollingWithApplicationViewController
                container.updateTargetApplication(with: application)
                _ = container.view
                (container.children.first as? PreferencesScrollingViewController)?.uiStateDefaults = uiDefaults
                (container.children.first as? PreferencesScrollingViewController)?.setAdvancedExpanded(advanced)
                container.fitToContent()
                container.view.setFrameSize(container.preferredContentSize)
                try render(container.view, name: "per-app-\(state)\(inherit ? "-inherit" : "")", into: directory)
            }
        }

        // The Gestures tab next to it, to compare the grid and the spacing.
        let gestures = GesturesPreferencesViewController(isInteractiveAvailable: { true })
        gestures.deviceSource = MouseGestureDeviceSource(support: { .none }, refresh: {})
        gestures.bindingSummary = { MouseGestureBindingSummary(hasGestureButton: true, hasLogitechGestureButton: false) }
        try render(gestures.view, name: "reference-gestures", into: directory)
    }

    /// Writes `<name>-light.png` and `<name>-dark.png`. The pane's own background is a
    /// behind-window material that draws nothing off screen, so the window colour stands in.
    private func render(_ view: NSView, name: String, into directory: URL) throws {
        for (suffix, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            view.appearance = appearance
            view.layoutSubtreeIfNeeded()
            view.display()
            let bounds = view.bounds
            let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: bounds))
            view.cacheDisplay(in: bounds, to: rep)

            let image = NSImage(size: bounds.size)
            image.addRepresentation(try XCTUnwrap(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * 2), pixelsHigh: Int(bounds.height * 2),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            )))
            let canvas = try XCTUnwrap(image.representations.first as? NSBitmapImageRep)
            canvas.size = bounds.size
            let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: canvas))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            appearance.performAsCurrentDrawingAppearance {
                NSColor.windowBackgroundColor.setFill()
                bounds.fill()
            }
            rep.draw(in: bounds)
            NSGraphicsContext.restoreGraphicsState()

            let png = try XCTUnwrap(canvas.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent("\(name)-\(suffix).png"))
        }
        view.appearance = nil
    }
}
