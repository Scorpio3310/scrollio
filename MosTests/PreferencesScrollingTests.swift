//
//  PreferencesScrollingTests.swift
//  MosTests
//
//  The Scrolling tab: every control reads and writes the right scroll option, Feel and
//  the glide time slider never disagree, "Advanced" opens, closes and is remembered, the
//  preview follows the options, the rows sit in the boxes of the grouped form, and the
//  same view edits one app's own options in the per-app popover. Nothing is shown on
//  screen and no key is recorded for real.
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

    private func set(_ toggle: NSSwitch, _ on: Bool) {
        toggle.state = on ? .on : .off
        send(toggle)
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
        XCTAssertEqual(controller.view.frame.width, PreferencesScrollingViewController.paneWidth)
        XCTAssertEqual(controller.view.frame.size, controller.view.fittingSize)
        XCTAssertTrue(controller.view is NSVisualEffectView, "the background of every pane")
        XCTAssertEqual(controller.previewView.identifier, ID.preview)
        XCTAssertEqual(controller.smoothSwitch.identifier, ID.smooth)
        XCTAssertEqual(controller.feelControl.identifier, ID.feel)
        XCTAssertEqual(controller.scrollSpeedSlider.identifier, ID.speed)
        XCTAssertEqual(controller.reverseSwitch.identifier, ID.reverse)
        XCTAssertEqual(controller.advancedButton.identifier, ID.advanced)
        XCTAssertEqual(controller.glideTimeSlider.identifier, ID.glideTime)
        XCTAssertEqual(controller.smallestStepSlider.identifier, ID.smallestStep)
        XCTAssertEqual(controller.trackpadEventsSwitch.identifier, ID.trackpadEvents)
        XCTAssertEqual(controller.keyBindButtons.map(\.identifier), ScrollHoldKey.allCases.map(ID.key))
        XCTAssertEqual(controller.keyClearButtons.map(\.identifier), ScrollHoldKey.allCases.map(ID.keyClear))
        XCTAssertEqual(controller.resetToDefaultsButton.identifier, ID.reset)
    }

    func testControlsComeInTheAgreedOrder() {
        let controller = makeController(advanced: true)
        controller.view.layoutSubtreeIfNeeded()
        var order: [NSView] = [
            controller.previewView, controller.smoothSwitch, controller.feelControl,
            controller.scrollSpeedSlider, controller.reverseSwitch, controller.advancedButton,
            controller.glideTimeSlider, controller.smallestStepSlider, controller.trackpadEventsSwitch,
        ]
        order.append(contentsOf: controller.keyBindButtons)
        order.append(controller.resetToDefaultsButton)
        let tops: [CGFloat] = order.map { frame(of: $0, in: controller).maxY }
        XCTAssertEqual(tops, tops.sorted(by: >), "from the top of the pane down")
        XCTAssertEqual(Set(tops).count, tops.count)

        // The preview is the first thing on the tab, as wide as the boxes.
        let margin = PreferencesGroupedForm.margin
        let width = PreferencesScrollingViewController.paneWidth
        let preview = frame(of: controller.previewView, in: controller)
        XCTAssertEqual(controller.view.bounds.maxY - preview.maxY, margin, accuracy: 0.5)
        XCTAssertEqual(preview.minX, margin, accuracy: 0.5)
        XCTAssertEqual(preview.width, width - 2 * margin, accuracy: 0.5)
        XCTAssertEqual(preview.height, ScrollPreviewView.preferredHeight, accuracy: 0.5)

        // "Reset to defaults" is the last thing on the tab, under the boxes at the right edge.
        let reset = frame(of: controller.resetToDefaultsButton, in: controller)
        XCTAssertEqual(reset.maxX, width - margin, accuracy: 1)
        XCTAssertEqual(reset.minY, margin, accuracy: 1)
        let keysBox = frame(of: controller.keysSection.box, in: controller)
        XCTAssertEqual(keysBox.minY - reset.maxY, PreferencesGroupedForm.sectionSpacing, accuracy: 1)

        // Closed, it moves up under the box of "Advanced".
        send(controller.advancedButton)
        controller.view.setFrameSize(controller.view.fittingSize)
        controller.view.layoutSubtreeIfNeeded()
        let closedReset = frame(of: controller.resetToDefaultsButton, in: controller)
        let advancedBox = frame(of: controller.sections[1].box, in: controller)
        XCTAssertEqual(advancedBox.minY - closedReset.maxY, PreferencesGroupedForm.sectionSpacing, accuracy: 1)
        XCTAssertEqual(closedReset.minY, margin, accuracy: 1)
    }

    func testRowsAreGroupedInThreeBoxes() {
        let controller = makeController(advanced: true)
        XCTAssertEqual(controller.sections.count, 3)
        let boxes = controller.sections.map(\.box)
        XCTAssertEqual(boxes[0].rows, [controller.smoothRow, controller.feelRow, controller.speedRow, controller.reverseRow])
        XCTAssertEqual(boxes[1].rows, [
            controller.advancedRow, controller.glideTimeRow, controller.smallestStepRow, controller.trackpadEventsRow,
        ])
        XCTAssertEqual(boxes[2].rows, controller.keyRows)
        XCTAssertEqual(controller.keyRows.count, ScrollHoldKey.allCases.count)

        // Only the keys' box has a title above it, the small title of System Settings.
        XCTAssertNil(controller.sections[0].titleLabel)
        XCTAssertNil(controller.sections[1].titleLabel)
        XCTAssertEqual(controller.keysSection.titleLabel?.stringValue, "While you hold a key")
        XCTAssertTrue(controller.sections[2] === controller.keysSection)

        // Each row is one setting, named by its title; its control is named the same.
        XCTAssertEqual(controller.smoothRow.title, "Smooth scrolling")
        XCTAssertEqual(controller.feelRow.title, "Feel")
        XCTAssertEqual(controller.speedRow.title, "Speed")
        XCTAssertEqual(controller.reverseRow.title, "Reverse wheel direction")
        XCTAssertEqual(controller.glideTimeRow.title, "Glide time")
        XCTAssertEqual(controller.smallestStepRow.title, "Smallest step")
        XCTAssertEqual(controller.trackpadEventsRow.title, "Trackpad-style events")
        XCTAssertEqual(controller.keyRows.map(\.title), ["Scroll faster", "Scroll sideways", "Pause smoothing"])
        XCTAssertEqual(controller.smoothSwitch.accessibilityLabel(), "Smooth scrolling")
        XCTAssertEqual(controller.reverseSwitch.accessibilityLabel(), "Reverse wheel direction")
        XCTAssertEqual(controller.trackpadEventsSwitch.accessibilityLabel(), "Trackpad-style events")
        XCTAssertEqual(controller.glideTimeSlider.accessibilityLabel(), "Glide time")
        XCTAssertEqual(controller.smoothSwitch.accessibilityHelp(), text("scrolling-smooth-hint"))
        for (index, button) in controller.keyBindButtons.enumerated() {
            XCTAssertTrue(button.accessibilityTitleUIElement() as? NSTextField === controller.keyRows[index].titleLabel)
            XCTAssertEqual(button.accessibilityHelp(), text(ScrollHoldKey.allCases[index].hintKey))
        }

        // Feel puts its five presets under its text; the others keep the control on the right.
        XCTAssertEqual(controller.feelRow.placement, .below)
        XCTAssertTrue(controller.feelRow.accessory === controller.feelControl)
        XCTAssertTrue(controller.feelRow.explanationLabel === controller.feelHintLabel)
        XCTAssertEqual(controller.speedRow.lowEndLabel?.stringValue, "Shorter")
        XCTAssertEqual(controller.speedRow.highEndLabel?.stringValue, "Farther")
        XCTAssertNil(controller.glideTimeRow.lowEndLabel)
    }

    func testTextsOfTheTab() {
        let controller = makeController(advanced: true)
        XCTAssertEqual(controller.advancedButton.title, "Advanced")
        XCTAssertEqual(controller.resetToDefaultsButton.title, "Reset to defaults")

        let shown = allSubviews(of: controller.view).compactMap { ($0 as? NSTextField)?.stringValue }
        let expected = [
            "Smooth scrolling", "Feel", "Speed", "Shorter", "Farther", "Reverse wheel direction",
            "Glide time", "Smallest step", "Trackpad-style events", "While you hold a key",
            "Scroll faster", "Scroll sideways", "Pause smoothing",
            text("scrolling-smooth-hint"), text("scrolling-speed-hint"), text("scrolling-reverse-hint"),
            text("scrolling-glide-time-hint"), text("scrolling-step-hint"), text("scrolling-trackpad-events-hint"),
            text("scrolling-key-faster-hint"), text("scrolling-key-sideways-hint"), text("scrolling-key-pause-hint"),
        ]
        for line in expected {
            XCTAssertTrue(shown.contains(line), "\"\(line)\" is not on the tab")
        }
        // Nothing of the old tabs is left: no label column, no checkboxes.
        let old = [
            "Step", "Duration", "Dash Key", "Toggle Key", "Block Key", "Presets & Fast Scrolling…", "Preset",
            "Mouse wheel", "Direction", "Apps",
        ]
        for line in old {
            XCTAssertFalse(shown.contains(line), "\"\(line)\" is still on the tab")
        }
        XCTAssertFalse(allSubviews(of: controller.view).contains { $0 is NSStepper || $0 is NSPopUpButton })
        // The checkboxes became switches: the only buttons left are these.
        let buttons = Set(allSubviews(of: controller.view).compactMap { $0 as? NSButton }.map(ObjectIdentifier.init))
        let expectedButtons = [controller.advancedButton!, controller.resetToDefaultsButton!]
            + controller.keyBindButtons + controller.keyClearButtons
        XCTAssertEqual(buttons, Set(expectedButtons.map(ObjectIdentifier.init)))
        XCTAssertEqual(allSubviews(of: controller.view).compactMap { $0 as? NSSwitch }.count, 3)
    }

    // MARK: - Smooth scrolling

    func testSmoothSwitchWritesSmooth() {
        let controller = makeController()
        XCTAssertEqual(controller.smoothSwitch.state, .on, "on by default")

        set(controller.smoothSwitch, false)
        XCTAssertFalse(Options.shared.scroll.smooth)
        set(controller.smoothSwitch, true)
        XCTAssertTrue(Options.shared.scroll.smooth)

        Options.shared.scroll.smooth = false
        controller.syncViewWithOptions()
        XCTAssertEqual(controller.smoothSwitch.state, .off)
    }

    func testWithoutSmoothingOnlyDirectionAndKeysStayEditable() {
        let controller = makeController(advanced: true)
        let smoothOnly: [NSControl] = [
            controller.feelControl, controller.scrollSpeedSlider, controller.glideTimeSlider,
            controller.smallestStepSlider, controller.trackpadEventsSwitch,
        ]
        XCTAssertTrue(smoothOnly.allSatisfy(\.isEnabled))

        set(controller.smoothSwitch, false)

        XCTAssertTrue(smoothOnly.allSatisfy { !$0.isEnabled })
        // The rows dim with them: title, explanation and the words around the slider.
        let dimmed: [PreferencesGroupRow] = [
            controller.feelRow, controller.speedRow, controller.glideTimeRow,
            controller.smallestStepRow, controller.trackpadEventsRow,
        ]
        for row in dimmed {
            XCTAssertFalse(row.isEnabled, row.title)
            XCTAssertEqual(row.titleLabel.textColor, .tertiaryLabelColor, row.title)
            XCTAssertEqual(row.explanationLabel.textColor, .tertiaryLabelColor, row.title)
        }
        XCTAssertEqual(controller.scrollSpeedValueLabel.textColor, .tertiaryLabelColor)
        XCTAssertEqual(controller.speedRow.lowEndLabel?.textColor, .tertiaryLabelColor)
        XCTAssertTrue(controller.smoothRow.isEnabled)
        XCTAssertEqual(controller.reverseRow.titleLabel.textColor, .labelColor)
        XCTAssertTrue(controller.smoothSwitch.isEnabled)
        XCTAssertTrue(controller.reverseSwitch.isEnabled)
        XCTAssertTrue(controller.keyBindButtons.allSatisfy(\.isEnabled))
        XCTAssertTrue(controller.keyClearButtons.allSatisfy(\.isEnabled))
        XCTAssertTrue(controller.advancedButton.isEnabled)
        // What was chosen still shows.
        XCTAssertEqual(controller.feelControl.selectedSegment, ScrollFeel.smooth.rawValue)

        set(controller.smoothSwitch, true)
        XCTAssertTrue(smoothOnly.allSatisfy(\.isEnabled))
        XCTAssertTrue(dimmed.allSatisfy(\.isEnabled))
        XCTAssertEqual(controller.speedRow.titleLabel.textColor, .labelColor)
        XCTAssertEqual(controller.scrollSpeedValueLabel.textColor, .labelColor)
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

        XCTAssertEqual(Options.shared.scroll.duration, 3.9, "rounded to the 0.05 grid")
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
        // A tick at every whole number; the value moves in halves between them.
        XCTAssertEqual(slider.numberOfTickMarks, 10)
        XCTAssertEqual(slider.tickMarkPosition, .below)
        XCTAssertFalse(slider.allowsTickMarkValuesOnly)

        drag(slider, to: 3.14)
        XCTAssertEqual(Options.shared.scroll.speed, 3, "rounded to halves")
        XCTAssertEqual(controller.scrollSpeedValueLabel.stringValue, "3.0")
        drag(slider, to: 3.3)
        XCTAssertEqual(Options.shared.scroll.speed, 3.5)
        XCTAssertEqual(controller.scrollSpeedValueLabel.stringValue, "3.5")

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
        XCTAssertEqual(slider.numberOfTickMarks, 11, "a tick every 10")
        XCTAssertFalse(slider.allowsTickMarkValuesOnly)

        drag(slider, to: 12.34)
        XCTAssertEqual(Options.shared.scroll.step, 12, "whole numbers")
        XCTAssertEqual(controller.smallestStepValueLabel.stringValue, "12")
        drag(slider, to: 0.3)
        XCTAssertEqual(Options.shared.scroll.step, 0.01, "the far left keeps the range's lowest value")
        XCTAssertEqual(controller.smallestStepValueLabel.stringValue, "0.01")
        drag(slider, to: 12)
        XCTAssertEqual(Options.shared.scroll.duration, 3.69, "nothing else moves")
        XCTAssertEqual(Options.shared.scroll.speed, 6.3)
    }

    // MARK: - Values off the grid

    /// The owner tuned Speed and Duration by feel; the new steps must not move them.
    func testStoredValuesOffTheGridAreShownAndNeverRewritten() throws {
        let scroll = Options.shared.scroll
        scroll.speed = 6.31
        scroll.duration = 3.687
        scroll.step = 33.6
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let before = try encoder.encode(scroll)

        let controller = makeController(advanced: true)
        controller.viewWillAppear()
        controller.setAdvancedExpanded(false)
        controller.setAdvancedExpanded(true)
        controller.syncViewWithOptions()

        XCTAssertEqual(
            String(decoding: try encoder.encode(Options.shared.scroll), as: UTF8.self),
            String(decoding: before, as: UTF8.self),
            "loading and showing writes nothing"
        )
        XCTAssertEqual(controller.scrollSpeedSlider.doubleValue, 6.31, accuracy: 1e-9, "the knob shows the value itself")
        XCTAssertEqual(controller.scrollSpeedValueLabel.stringValue, "6.3")
        XCTAssertEqual(controller.glideTimeSlider.doubleValue, 3.687, accuracy: 1e-9)
        XCTAssertEqual(controller.glideTimeValueLabel.stringValue, "3.69")
        XCTAssertEqual(controller.feelControl.selectedSegment, ScrollFeel.smooth.rawValue, "3.687 reads as Smooth")
        XCTAssertEqual(controller.smallestStepSlider.doubleValue, 33.6, accuracy: 1e-9)
        XCTAssertEqual(controller.smallestStepValueLabel.stringValue, "33.6")

        // The same in the per-app popover, for an app with values of its own.
        let application = makeApplication(inherit: false)
        application.scroll.speed = 6.31
        application.scroll.duration = 3.687
        let perApp = makeController(target: application, advanced: true)
        perApp.syncViewWithOptions()
        XCTAssertEqual(application.scroll.speed, 6.31)
        XCTAssertEqual(application.scroll.duration, 3.687)
        XCTAssertEqual(perApp.scrollSpeedSlider.numberOfTickMarks, 10)
        XCTAssertEqual(perApp.glideTimeSlider.numberOfTickMarks, 9)
        XCTAssertEqual(perApp.smallestStepSlider.numberOfTickMarks, 11)

        // Only a move of the slider writes a value of the grid.
        let speed = try XCTUnwrap(controller.scrollSpeedSlider as? PreferencesSlider)
        XCTAssertTrue(speed.moveKnob(by: 1))
        XCTAssertEqual(Options.shared.scroll.speed, 6.5, "an arrow key goes to the next half")
        XCTAssertEqual(Options.shared.scroll.duration, 3.687, "the other sliders keep their values")
        XCTAssertEqual(Options.shared.scroll.step, 33.6)
        XCTAssertTrue(speed.moveKnob(by: 1))
        XCTAssertEqual(Options.shared.scroll.speed, 7)
    }

    func testEachSliderWritesValuesOfItsGrid() throws {
        let controller = makeController(advanced: true)
        let sliders: [(NSSlider, ScrollSliderSetting, () -> Double)] = [
            (controller.scrollSpeedSlider, .speed, { Options.shared.scroll.speed }),
            (controller.glideTimeSlider, .glideTime, { Options.shared.scroll.duration }),
            (controller.smallestStepSlider, .smallestStep, { Options.shared.scroll.step }),
        ]
        for (slider, setting, stored) in sliders {
            for fraction in stride(from: 0.0, through: 1.0, by: 0.037) {
                drag(slider, to: setting.range.lowerBound + fraction * (setting.range.upperBound - setting.range.lowerBound))
                let value = stored()
                XCTAssertEqual(setting.snapped(value), value, "\(setting.range) \(fraction)")
                XCTAssertEqual(slider.doubleValue, value, accuracy: 1e-9, "the knob sits on the value it wrote")
            }
        }

        // A stop of the glide time slider next to a preset selects that preset.
        drag(controller.glideTimeSlider, to: 3.16)
        XCTAssertEqual(Options.shared.scroll.duration, 3.15)
        XCTAssertEqual(controller.feelControl.selectedSegment, ScrollFeel.quick.rawValue)
        drag(controller.glideTimeSlider, to: 3.7)
        XCTAssertEqual(controller.feelControl.selectedSegment, ScrollFeel.smooth.rawValue)
        drag(controller.glideTimeSlider, to: 3.65)
        XCTAssertEqual(controller.feelControl.selectedSegment, -1, "two steps from Smooth is custom")
        // Picking a preset still writes its own Duration, off the slider's grid.
        choose(.quick, in: controller)
        XCTAssertEqual(Options.shared.scroll.duration, 3.13)
        XCTAssertEqual(controller.glideTimeSlider.doubleValue, 3.13, accuracy: 1e-9)

        // Arrow keys: one step of each slider's grid.
        let glide = try XCTUnwrap(controller.glideTimeSlider as? PreferencesSlider)
        XCTAssertTrue(glide.moveKnob(by: 1))
        XCTAssertEqual(Options.shared.scroll.duration, 3.15)
        XCTAssertTrue(glide.moveKnob(by: -1))
        XCTAssertEqual(Options.shared.scroll.duration, 3.1)
        Options.shared.scroll.step = OPTIONS_SCROLL_DEFAULT().step
        controller.syncViewWithOptions()
        let step = try XCTUnwrap(controller.smallestStepSlider as? PreferencesSlider)
        XCTAssertTrue(step.moveKnob(by: -1))
        XCTAssertEqual(Options.shared.scroll.step, 33, "from the default 33.6 down to the next whole number")
    }

    // MARK: - Direction

    func testReverseSwitchTurnsEverythingOnOrTheMainFlagOff() {
        let scroll = Options.shared.scroll
        scroll.reverse = false
        scroll.reverseVertical = false
        scroll.reverseHorizontal = false
        let controller = makeController()
        XCTAssertEqual(controller.reverseSwitch.state, .off)

        set(controller.reverseSwitch, true)
        XCTAssertTrue(scroll.reverse)
        XCTAssertTrue(scroll.reverseVertical)
        XCTAssertTrue(scroll.reverseHorizontal)
        XCTAssertEqual(controller.reverseSwitch.state, .on)

        set(controller.reverseSwitch, false)
        XCTAssertFalse(scroll.reverse)
        XCTAssertTrue(scroll.reverseVertical, "off only clears the main flag")
        XCTAssertTrue(scroll.reverseHorizontal)
        XCTAssertEqual(controller.reverseSwitch.state, .off)
    }

    // MARK: - Trackpad-style events

    func testTrackpadStyleEventsIsAPlainSwitchThatLeavesDurationAlone() {
        let controller = makeController(advanced: true)
        XCTAssertEqual(controller.trackpadEventsSwitch.state, .off, "off by default")

        let durations: [Double] = ScrollFeel.allCases.map(\.duration) + [1.0, 2.6, 5.0]
        for duration in durations {
            Options.shared.scroll.duration = duration
            controller.syncViewWithOptions()

            set(controller.trackpadEventsSwitch, true)
            XCTAssertTrue(Options.shared.scroll.smoothSimTrackpad)
            XCTAssertEqual(Options.shared.scroll.duration, duration, "on at \(duration)")
            XCTAssertEqual(controller.glideTimeSlider.doubleValue, duration, accuracy: 1e-9)

            set(controller.trackpadEventsSwitch, false)
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
        XCTAssertEqual(controller.advancedRows.count, 4, "two sliders, the switch and the keys' box")
        XCTAssertTrue(controller.advancedRows.last === controller.keysSection)
        XCTAssertTrue(controller.advancedRows.allSatisfy(\.isHidden))
        // The box of "Advanced" shows only its header row, without hairlines.
        XCTAssertEqual(controller.sections[1].box.visibleRows, [controller.advancedRow])
        XCTAssertEqual(controller.sections[1].box.separatorRects, [])
        // What is always there.
        let alwaysThere: [NSView] = [
            controller.previewView, controller.smoothSwitch, controller.feelControl,
            controller.scrollSpeedSlider, controller.reverseSwitch, controller.advancedButton,
            controller.resetToDefaultsButton, controller.sections[0], controller.sections[1],
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
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(controller.sections[1].box.separatorRects.count, 3, "a hairline above each opened row")
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
        XCTAssertEqual(controller.trackpadEventsSwitch.state, .off)
        XCTAssertEqual(controller.reverseSwitch.state, .on)
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
        set(controller.reverseSwitch, false)
        set(controller.smoothSwitch, false)

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
        for row in controller.keyRows {
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

        set(controller.smoothSwitch, false)
        set(controller.smoothSwitch, true)
        choose(.direct, in: controller)
        drag(controller.scrollSpeedSlider, to: 4.4)
        set(controller.reverseSwitch, false)
        drag(controller.smallestStepSlider, to: 20)
        set(controller.trackpadEventsSwitch, true)
        send(controller.keyClearButtons[ScrollHoldKey.faster.rawValue])

        XCTAssertEqual(application.scroll.duration, 2.0)
        XCTAssertEqual(application.scroll.speed, 4.5, "the popover's slider has the tab's steps")
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
        XCTAssertEqual(controller.trackpadEventsSwitch.state, .on)
        var controls: [NSControl] = [
            controller.smoothSwitch, controller.feelControl, controller.scrollSpeedSlider,
            controller.reverseSwitch, controller.glideTimeSlider, controller.smallestStepSlider,
            controller.trackpadEventsSwitch, controller.resetToDefaultsButton,
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
        XCTAssertTrue(controller.smoothSwitch.isEnabled)
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
            ScrollPreviewView.preferredHeight + PreferencesGroupedForm.boxSpacing,
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
        XCTAssertEqual(container.preferredContentSize.width, PreferencesScrollingViewController.paneWidth, "sized before it shows")
        XCTAssertEqual(container.preferredContentSize.height, tab.view.fittingSize.height + 58, accuracy: 0.5)
        XCTAssertEqual(tab.scrollSpeedSlider.doubleValue, 4.2, accuracy: 1e-9)
        XCTAssertTrue(tab.previewView.isHidden)
        XCTAssertEqual(container.inheritGlobalSettingCheckBox.state, .off)
        // The app's header is a box like the settings' boxes.
        let header = try XCTUnwrap(container.view.subviews.compactMap { $0 as? NSBox }.first)
        XCTAssertEqual(header.boxType, .custom)
        XCTAssertEqual(header.cornerRadius, PreferencesGroupedForm.boxCornerRadius)
        XCTAssertEqual(header.borderWidth, 0)
        XCTAssertTrue(header.fillColor === PreferencesGroupedForm.boxFillColor)

        // The popover is as tall as the app's header and the settings under it, and
        // follows when "Advanced" opens and closes.
        tab.setAdvancedExpanded(false)
        container.fitToContent()
        let closed = container.preferredContentSize
        XCTAssertEqual(closed.width, PreferencesScrollingViewController.paneWidth)
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

    func testRowsSitInTheirBoxes() {
        let controller = makeController(advanced: true)
        controller.view.layoutSubtreeIfNeeded()
        let inset = PreferencesGroupedForm.rowHorizontalInset
        let margin = PreferencesGroupedForm.margin
        let boxRight = PreferencesScrollingViewController.paneWidth - margin

        // The boxes span the pane between its margins.
        for section in controller.sections {
            let box = frame(of: section.box, in: controller)
            XCTAssertEqual(box.minX, margin, accuracy: 0.5)
            XCTAssertEqual(box.maxX, boxRight, accuracy: 0.5)
        }
        // Titles start at the box's inset; controls end at it.
        let rows: [PreferencesGroupRow] = controller.sections.flatMap(\.box.rows).filter { !($0 is PreferencesDisclosureRow) }
        for row in rows {
            XCTAssertEqual(frame(of: row.titleLabel, in: controller).minX, margin + inset, accuracy: 0.5, row.title)
        }
        var rightEdges: [NSView] = [
            controller.smoothSwitch, controller.reverseSwitch, controller.trackpadEventsSwitch,
            controller.scrollSpeedValueLabel, controller.glideTimeValueLabel, controller.smallestStepValueLabel,
            controller.feelControl,
        ]
        rightEdges.append(contentsOf: controller.keyClearButtons)
        for view in rightEdges {
            XCTAssertEqual(frame(of: view, in: controller).maxX, boxRight - inset, accuracy: 1, "\(view)")
        }
        // The sliders form one column, and so do the key recorders.
        let sliders = [controller.scrollSpeedSlider!, controller.glideTimeSlider!, controller.smallestStepSlider!]
        let sliderFrames = sliders.map { frame(of: $0, in: controller) }
        XCTAssertEqual(Set(sliderFrames.map { $0.minX.rounded() }).count, 1)
        XCTAssertEqual(Set(sliderFrames.map { $0.width.rounded() }).count, 1)
        XCTAssertEqual(Set(controller.keyBindButtons.map { frame(of: $0, in: controller).minX.rounded() }).count, 1)

        // Each control sits on the line of its title.
        var lines: [(NSView, PreferencesGroupRow)] = []
        lines.append((controller.smoothSwitch, controller.smoothRow))
        lines.append((controller.scrollSpeedSlider, controller.speedRow))
        lines.append((controller.reverseSwitch, controller.reverseRow))
        lines.append((controller.glideTimeSlider, controller.glideTimeRow))
        lines.append((controller.smallestStepSlider, controller.smallestStepRow))
        lines.append((controller.trackpadEventsSwitch, controller.trackpadEventsRow))
        for (button, row) in zip(controller.keyBindButtons, controller.keyRows) {
            lines.append((button, row))
        }
        for (control, row) in lines {
            XCTAssertEqual(frame(of: control, in: controller).midY, frame(of: row.titleLabel, in: controller).midY, accuracy: 1, row.title)
        }

        // The five presets fill the width of the box under the text of "Feel".
        let feel = frame(of: controller.feelControl, in: controller)
        XCTAssertEqual(feel.minX, margin + inset, accuracy: 1)
        XCTAssertLessThan(feel.maxY, frame(of: controller.feelHintLabel, in: controller).minY)

        // The switches are the small ones of System Settings.
        for toggle in [controller.smoothSwitch!, controller.reverseSwitch!, controller.trackpadEventsSwitch!] {
            XCTAssertEqual(toggle.controlSize, PreferencesGroupedForm.switchControlSize)
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
        // Every preset's line fits the room kept for it, so the tab never jumps.
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
/// open, the defaults, a custom glide time and smoothing off, the tab and the per-app
/// popover. Off screen the window's material draws a flat grey and vibrant text is not
/// blended, so text looks a little dimmer than on screen. Only runs when asked to:
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
    /// The appearance is set on a parent, as the window sets it: the pane's material then
    /// gives its content the vibrant appearance it has on screen.
    private func render(_ view: NSView, name: String, into directory: URL) throws {
        let host = NSView(frame: view.frame)
        host.addSubview(view)
        defer { view.removeFromSuperview() }
        for (suffix, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            host.appearance = appearance
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
    }
}
