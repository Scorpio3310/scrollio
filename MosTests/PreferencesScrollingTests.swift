//
//  PreferencesScrollingTests.swift
//  MosTests
//
//  The Scrolling tab: every control reads and writes the right scroll option, Feel and
//  the glide time slider never disagree, the keys always show, "Advanced" opens, closes and
//  is remembered, the
//  preview follows the options, the rows sit in the boxes of the grouped form, and the
//  same view edits one app's own options on that app's page under Apps. Nothing is shown
//  on screen and no key is recorded for real.
//

import XCTest
@testable import Mos_Debug

final class PreferencesScrollingTests: XCTestCase {

    private typealias ID = PreferencesScrollingViewController.Identifier

    private var originalScroll: OPTIONS_SCROLL_DEFAULT!
    private var originalThumbWheel = ThumbWheelSettings.default
    private var uiDefaults: UserDefaults!
    private var uiDefaultsSuite = ""

    override func setUp() {
        super.setUp()
        originalScroll = Options.shared.scroll
        originalThumbWheel = Options.shared.thumbWheel
        // A fresh container, so the tests never edit the one they restore.
        Options.shared.scroll = OPTIONS_SCROLL_DEFAULT()
        Options.shared.thumbWheel = .default
        uiDefaultsSuite = "ScrollioTests.scrolling.\(UUID().uuidString)"
        uiDefaults = UserDefaults(suiteName: uiDefaultsSuite)
    }

    override func tearDown() {
        Options.shared.scroll = originalScroll
        Options.shared.thumbWheel = originalThumbWheel
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

    /// What the Speed slider writes, in the locale the tests run in ("6.3×", "6,3×").
    private func speedText(_ value: Double) -> String {
        return ScrollingSlider.speed.shownText(for: value)
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
        XCTAssertEqual(controller.thumbWheelFunctionPopUp.identifier, ID.thumbWheelFunction)
        XCTAssertEqual(controller.thumbWheelFunctionRow.explanationLabel.identifier, ID.thumbWheelFunctionHint)
        XCTAssertEqual(controller.thumbWheelSpeedSlider.identifier, ID.thumbWheelSpeed)
        XCTAssertEqual(controller.thumbWheelSwapSwitch.identifier, ID.thumbWheelSwap)
        XCTAssertEqual(controller.thumbWheelNote.identifier, ID.thumbWheelNote)
        XCTAssertEqual(controller.keyBindButtons.map(\.identifier), ScrollHoldKey.allCases.map(ID.key))
        XCTAssertEqual(controller.keyClearButtons.map(\.identifier), ScrollHoldKey.allCases.map(ID.keyClear))
        XCTAssertEqual(controller.resetToDefaultsButton.identifier, ID.reset)
    }

    func testControlsComeInTheAgreedOrder() throws {
        let controller = makeController(advanced: true)
        controller.view.layoutSubtreeIfNeeded()
        var order: [NSView] = [
            controller.previewView, controller.smoothSwitch, controller.feelControl,
            controller.scrollSpeedSlider, controller.reverseSwitch,
        ]
        // The thumb wheel and the line under its box under the main box, then the keys,
        // "Advanced" last.
        order.append(contentsOf: [
            controller.thumbWheelFunctionPopUp, controller.thumbWheelSpeedSlider, controller.thumbWheelSwapSwitch,
            controller.thumbWheelNote,
        ] as [NSView])
        order.append(contentsOf: controller.keyBindButtons)
        order.append(contentsOf: [
            controller.advancedButton, controller.glideTimeSlider, controller.smallestStepSlider,
            controller.trackpadEventsSwitch,
        ] as [NSView])
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
        let advancedBox = frame(of: controller.advancedSection.box, in: controller)
        XCTAssertEqual(advancedBox.minY - reset.maxY, PreferencesGroupedForm.sectionSpacing, accuracy: 1)
        // "Thumb wheel" under the main box and "While you hold a key" under its line, both
        // titles a section's gap under what is above them; the line close under its box;
        // "Advanced" a box's gap under the keys.
        let basicBox = frame(of: controller.sections[0].box, in: controller)
        let keysBox = frame(of: controller.keysSection.box, in: controller)
        let keysTitle = frame(of: try XCTUnwrap(controller.keysSection.titleLabel), in: controller)
        let thumbWheelTitle = frame(of: try XCTUnwrap(controller.thumbWheelSection.titleLabel), in: controller)
        let thumbWheelBox = frame(of: controller.thumbWheelSection.box, in: controller)
        let note = frame(of: try XCTUnwrap(controller.thumbWheelNote.superview), in: controller)
        XCTAssertEqual(basicBox.minY - thumbWheelTitle.maxY, PreferencesGroupedForm.sectionSpacing, accuracy: 1)
        XCTAssertEqual(thumbWheelTitle.minY - thumbWheelBox.maxY, PreferencesGroupedForm.sectionTitleSpacing, accuracy: 1)
        XCTAssertEqual(thumbWheelBox.minY - note.maxY, PreferencesGroupedForm.noteSpacing, accuracy: 1)
        XCTAssertEqual(note.minY - keysTitle.maxY, PreferencesGroupedForm.sectionSpacing, accuracy: 1)
        XCTAssertEqual(keysTitle.minY - keysBox.maxY, PreferencesGroupedForm.sectionTitleSpacing, accuracy: 1)
        XCTAssertEqual(keysBox.minY - advancedBox.maxY, PreferencesGroupedForm.boxSpacing, accuracy: 1)

        // Closed, it moves up under the box of "Advanced", which stays under the keys.
        send(controller.advancedButton)
        controller.view.setFrameSize(controller.view.fittingSize)
        controller.view.layoutSubtreeIfNeeded()
        let closedReset = frame(of: controller.resetToDefaultsButton, in: controller)
        let closedAdvancedBox = frame(of: controller.advancedSection.box, in: controller)
        XCTAssertEqual(closedAdvancedBox.minY - closedReset.maxY, PreferencesGroupedForm.sectionSpacing, accuracy: 1)
        XCTAssertEqual(closedReset.minY, margin, accuracy: 1)
        let closedKeysBox = frame(of: controller.keysSection.box, in: controller)
        XCTAssertEqual(closedKeysBox.minY - closedAdvancedBox.maxY, PreferencesGroupedForm.boxSpacing, accuracy: 1)
    }

    func testRowsAreGroupedInFourBoxes() {
        let controller = makeController(advanced: true)
        XCTAssertEqual(controller.sections.count, 4)
        let boxes = controller.sections.map(\.box)
        XCTAssertEqual(boxes[0].rows, [controller.smoothRow, controller.feelRow, controller.speedRow, controller.reverseRow])
        XCTAssertEqual(boxes[1].rows, [controller.thumbWheelFunctionRow, controller.thumbWheelSpeedRow, controller.thumbWheelSwapRow])
        XCTAssertEqual(boxes[2].rows, controller.keyRows)
        XCTAssertEqual(boxes[3].rows, [
            controller.advancedRow, controller.glideTimeRow, controller.smallestStepRow, controller.trackpadEventsRow,
        ])
        XCTAssertEqual(controller.keyRows.count, ScrollHoldKey.allCases.count)

        // The keys' box and the thumb wheel's have a title above them, the small title of
        // System Settings.
        XCTAssertNil(controller.sections[0].titleLabel)
        XCTAssertNil(controller.advancedSection.titleLabel)
        XCTAssertEqual(controller.keysSection.titleLabel?.stringValue, "While you hold a key")
        XCTAssertEqual(controller.thumbWheelSection.titleLabel?.stringValue, "Thumb wheel")
        XCTAssertTrue(controller.sections[1] === controller.thumbWheelSection)
        XCTAssertTrue(controller.sections[2] === controller.keysSection)
        XCTAssertTrue(controller.sections[3] === controller.advancedSection)
        XCTAssertEqual(controller.thumbWheelFunctionRow.title, "Action")
        XCTAssertEqual(controller.thumbWheelSpeedRow.title, "Speed")
        XCTAssertEqual(controller.thumbWheelSwapRow.title, "Swap direction")
        XCTAssertEqual(controller.thumbWheelFunctionPopUp.accessibilityLabel(), "Action")
        XCTAssertEqual(controller.thumbWheelFunctionPopUp.accessibilityHelp(), "Scrolls sideways.")
        XCTAssertEqual(controller.thumbWheelSpeedSlider.accessibilityLabel(), "Speed")
        XCTAssertEqual(controller.thumbWheelSwapSwitch.accessibilityLabel(), "Swap direction")
        XCTAssertEqual(controller.thumbWheelSwapSwitch.accessibilityHelp(), "Turns the thumb wheel the other way.")
        XCTAssertEqual(controller.thumbWheelSpeedRow.lowEndLabel?.stringValue, "Slow")
        XCTAssertEqual(controller.thumbWheelSpeedRow.highEndLabel?.stringValue, "Fast")
        XCTAssertEqual(controller.thumbWheelSwapSwitch.controlSize, PreferencesGroupedForm.switchControlSize)

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
        XCTAssertEqual(controller.speedRow.lowEndLabel?.stringValue, "Slow")
        XCTAssertEqual(controller.speedRow.highEndLabel?.stringValue, "Fast")
        XCTAssertEqual(controller.glideTimeRow.lowEndLabel?.stringValue, "Shorter")
        XCTAssertEqual(controller.glideTimeRow.highEndLabel?.stringValue, "Longer")
        XCTAssertEqual(controller.smallestStepRow.lowEndLabel?.stringValue, "Smaller")
        XCTAssertEqual(controller.smallestStepRow.highEndLabel?.stringValue, "Larger")
    }

    func testTextsOfTheTab() {
        let controller = makeController(advanced: true)
        XCTAssertEqual(controller.advancedButton.title, "Advanced")
        XCTAssertEqual(controller.resetToDefaultsButton.title, "Reset to Defaults")

        let shown = allSubviews(of: controller.view).compactMap { ($0 as? NSTextField)?.stringValue }
        let expected = [
            "Smooth scrolling", "Feel", "Speed", "Slow", "Fast", "Reverse wheel direction",
            "Glide time", "Shorter", "Longer", "Smallest step", "Smaller", "Larger",
            "Trackpad-style events", "While you hold a key",
            "Scroll faster", "Scroll sideways", "Pause smoothing",
            text("scrolling-smooth-hint"), text("scrolling-speed-hint"), text("scrolling-reverse-hint"),
            text("scrolling-glide-time-hint"), text("scrolling-step-hint"), text("scrolling-trackpad-events-hint"),
            text("scrolling-key-faster-hint"), text("scrolling-key-sideways-hint"), text("scrolling-key-pause-hint"),
            "Thumb wheel", "Action", "Scrolls sideways.", "How far a turn scrolls sideways.",
            "Swap direction", "Turns the thumb wheel the other way.",
            "For the sideways wheel: an MX Master's thumb wheel, or a wheel that tilts.",
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
        XCTAssertFalse(allSubviews(of: controller.view).contains { $0 is NSStepper })
        // The one pop-up is the thumb wheel's.
        XCTAssertEqual(allSubviews(of: controller.view).compactMap { $0 as? NSPopUpButton }, [controller.thumbWheelFunctionPopUp])
        // The checkboxes became switches: the only buttons left are these.
        let buttons = Set(allSubviews(of: controller.view).compactMap { $0 as? NSButton }.map(ObjectIdentifier.init))
        let expectedButtons = [controller.advancedButton!, controller.resetToDefaultsButton!, controller.thumbWheelFunctionPopUp!]
            + controller.keyBindButtons + controller.keyClearButtons
        XCTAssertEqual(buttons, Set(expectedButtons.map(ObjectIdentifier.init)))
        XCTAssertEqual(allSubviews(of: controller.view).compactMap { $0 as? NSSwitch }.count, 4)
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
        // The thumb wheel stays editable: an app with its own settings may still smooth it.
        XCTAssertTrue(controller.thumbWheelSpeedRow.isEnabled)
        XCTAssertTrue(controller.thumbWheelSpeedSlider.isEnabled)
        XCTAssertEqual(controller.thumbWheelSpeedRow.explanation, "Applies where Smooth scrolling is on.")
        XCTAssertTrue(controller.thumbWheelFunctionPopUp.isEnabled)
        XCTAssertTrue(controller.thumbWheelSwapSwitch.isEnabled)
        // What was chosen still shows.
        XCTAssertEqual(controller.feelControl.selectedSegment, ScrollFeel.smooth.rawValue)

        set(controller.smoothSwitch, true)
        XCTAssertTrue(smoothOnly.allSatisfy(\.isEnabled))
        XCTAssertTrue(dimmed.allSatisfy(\.isEnabled))
        XCTAssertTrue(controller.thumbWheelSpeedSlider.isEnabled)
        XCTAssertEqual(controller.thumbWheelSpeedRow.explanation, "How far a turn scrolls sideways.")
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
            XCTAssertEqual(controller.glideTimeValueLabel.stringValue, "", "no number")
            XCTAssertEqual(controller.glideTimeSlider.accessibilityValueDescription(), ScrollingSlider.glideTime.spokenValue(for: feel.duration))
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
        XCTAssertEqual(controller.glideTimeValueLabel.stringValue, "")
        XCTAssertEqual(controller.glideTimeSlider.accessibilityValueDescription(), ScrollingSlider.glideTime.spokenValue(for: 3.9))

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
        XCTAssertEqual(controller.scrollSpeedValueLabel.stringValue, speedText(6.3))
        XCTAssertTrue(speedText(6.3).hasSuffix("×"), "a factor")
        XCTAssertEqual(slider.accessibilityValueDescription(), speedText(6.3))
        XCTAssertEqual(slider.accessibilityLabel(), "Speed")
        // A tick at every whole number; the value moves in halves between them.
        XCTAssertEqual(slider.numberOfTickMarks, 10)
        XCTAssertEqual(slider.tickMarkPosition, .below)
        XCTAssertFalse(slider.allowsTickMarkValuesOnly)

        drag(slider, to: 3.14)
        XCTAssertEqual(Options.shared.scroll.speed, 3, "rounded to halves")
        XCTAssertEqual(controller.scrollSpeedValueLabel.stringValue, speedText(3))
        drag(slider, to: 3.3)
        XCTAssertEqual(Options.shared.scroll.speed, 3.5)
        XCTAssertEqual(controller.scrollSpeedValueLabel.stringValue, speedText(3.5))

        drag(slider, to: 10)
        XCTAssertEqual(Options.shared.scroll.speed, 10)
        XCTAssertEqual(controller.scrollSpeedValueLabel.stringValue, speedText(10))
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(
            controller.scrollSpeedValueLabel.fittingSize.width, controller.scrollSpeedValueLabel.frame.width,
            "the longest value fits its column"
        )
        drag(slider, to: 1)
        XCTAssertEqual(Options.shared.scroll.speed, 1)
    }

    func testSmallestStepSliderWritesStep() {
        let controller = makeController(advanced: true)
        let slider = controller.smallestStepSlider!
        XCTAssertEqual(slider.minValue, 0.01)
        XCTAssertEqual(slider.maxValue, 100)
        XCTAssertEqual(slider.doubleValue, 33.6, accuracy: 1e-9)
        XCTAssertEqual(controller.smallestStepValueLabel.stringValue, "", "no number: the ends say which way is which")
        XCTAssertEqual(slider.accessibilityValueDescription(), ScrollingSlider.smallestStep.spokenValue(for: 33.6))
        XCTAssertEqual(slider.accessibilityLabel(), "Smallest step")
        XCTAssertEqual(slider.numberOfTickMarks, 11, "a tick every 10")
        XCTAssertFalse(slider.allowsTickMarkValuesOnly)

        drag(slider, to: 12.34)
        XCTAssertEqual(Options.shared.scroll.step, 12, "whole numbers")
        XCTAssertEqual(slider.accessibilityValueDescription(), ScrollingSlider.smallestStep.spokenValue(for: 12))
        drag(slider, to: 0.3)
        XCTAssertEqual(Options.shared.scroll.step, 0.01, "the far left keeps the range's lowest value")
        XCTAssertEqual(slider.accessibilityValueDescription(), ScrollingSlider.smallestStep.spokenValue(for: 0.01))
        drag(slider, to: 12)
        XCTAssertEqual(Options.shared.scroll.duration, 3.69, "nothing else moves")
        XCTAssertEqual(Options.shared.scroll.speed, 6.3)
    }

    /// Speed shows its factor in the user's locale; Glide time and Smallest step show no
    /// number, and VoiceOver reads how far along each of them the knob is.
    func testOnlySpeedShowsANumberAndItFollowsTheLocale() {
        let english = Locale(identifier: "en_US")
        let slovenian = Locale(identifier: "sl_SI")
        XCTAssertEqual(ScrollingSlider.speed.shownText(for: 6.3, locale: english), "6.3×")
        XCTAssertEqual(ScrollingSlider.speed.shownText(for: 10, locale: english), "10.0×")
        XCTAssertEqual(ScrollingSlider.speed.shownText(for: 1, locale: english), "1.0×")
        XCTAssertEqual(ScrollingSlider.speed.shownText(for: 6.31, locale: english), "6.3×", "the slider's one decimal")
        XCTAssertEqual(ScrollingSlider.speed.shownText(for: 6.3, locale: slovenian), "6,3×", "a decimal comma")
        XCTAssertEqual(ScrollingSlider.speed.shownText(for: 7.5, locale: Locale(identifier: "de_DE")), "7,5×")
        XCTAssertEqual(ScrollingSlider.speed.spokenValue(for: 6.3, locale: english), "6.3×", "VoiceOver reads what is shown")

        for slider in [ScrollingSlider.glideTime, .smallestStep] {
            let range = slider.setting.range
            for value in [range.lowerBound, (range.lowerBound + range.upperBound) / 2, range.upperBound] {
                XCTAssertEqual(slider.shownText(for: value, locale: english), "", "\(slider) shows no number")
            }
        }
        XCTAssertEqual(ScrollingSlider.glideTime.spokenValue(for: 1, locale: english), "0%")
        XCTAssertEqual(ScrollingSlider.glideTime.spokenValue(for: 3.69, locale: english), "67%")
        XCTAssertEqual(ScrollingSlider.glideTime.spokenValue(for: 5, locale: english), "100%")
        XCTAssertEqual(ScrollingSlider.smallestStep.spokenValue(for: 33.6, locale: english), "34%")
        XCTAssertEqual(ScrollingSlider.smallestStep.spokenValue(for: 250, locale: english), "100%", "kept on the slider")
        XCTAssertEqual(ScrollingSlider.smallestStep.spokenValue(for: .nan, locale: english), "0%")
        XCTAssertTrue(ScrollingSlider.glideTime.spokenValue(for: 3.69, locale: slovenian).hasPrefix("67"))
        XCTAssertEqual(ScrollingSlider.allCases.map(\.setting), [.speed, .glideTime, .smallestStep])
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
        XCTAssertEqual(controller.scrollSpeedValueLabel.stringValue, speedText(6.3))
        XCTAssertEqual(controller.glideTimeSlider.doubleValue, 3.687, accuracy: 1e-9)
        XCTAssertEqual(controller.glideTimeValueLabel.stringValue, "")
        XCTAssertEqual(controller.feelControl.selectedSegment, ScrollFeel.smooth.rawValue, "3.687 reads as Smooth")
        XCTAssertEqual(controller.smallestStepSlider.doubleValue, 33.6, accuracy: 1e-9)
        XCTAssertEqual(controller.smallestStepValueLabel.stringValue, "")

        // The same for an app with values of its own.
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
        XCTAssertEqual(controller.keyBindButtons.map(\.title), ["⌥", "⇧", "⌘"], "the default keys, named as the Buttons pane names them")
        XCTAssertTrue(controller.keyClearButtons.allSatisfy { $0.isEnabled && $0.alphaValue == 1 })
        XCTAssertEqual(
            controller.keyClearButtons.map { $0.accessibilityLabel() },
            ["Clear key for Scroll faster", "Clear key for Scroll sideways", "Clear key for Pause smoothing"],
            "VoiceOver tells the three apart"
        )
        XCTAssertTrue(controller.keyClearButtons.allSatisfy { $0.isAccessibilityElement() })

        send(controller.keyClearButtons[ScrollHoldKey.sideways.rawValue])

        XCTAssertNil(Options.shared.scroll.toggle)
        XCTAssertNotNil(Options.shared.scroll.dash)
        XCTAssertNotNil(Options.shared.scroll.block)
        XCTAssertEqual(controller.keyBindButtons.map(\.title), ["⌥", "None", "⌘"])
        let cleared = controller.keyClearButtons[ScrollHoldKey.sideways.rawValue]
        XCTAssertFalse(cleared.isEnabled)
        XCTAssertEqual(cleared.alphaValue, 0, "nothing to clear")
        XCTAssertFalse(cleared.isAccessibilityElement(), "a hidden button is not in the accessibility tree")
        XCTAssertTrue(controller.keyClearButtons[ScrollHoldKey.faster.rawValue].isAccessibilityElement())

        send(controller.keyClearButtons[ScrollHoldKey.faster.rawValue])
        send(controller.keyClearButtons[ScrollHoldKey.pause.rawValue])
        XCTAssertNil(Options.shared.scroll.dash)
        XCTAssertNil(Options.shared.scroll.block)
        XCTAssertFalse(controller.keyClearButtons.contains { $0.isAccessibilityElement() })

        // A key again: the button is back in the tree.
        Options.shared.scroll.dash = ScrollHotkey(type: .keyboard, code: KeyCode.optionL)
        controller.syncViewWithOptions()
        XCTAssertTrue(controller.keyClearButtons[ScrollHoldKey.faster.rawValue].isAccessibilityElement())
    }

    func testARecordedKeyGoesToTheRowThatRecorded() {
        let controller = makeController(advanced: true)
        let recorder = KeyRecorder()
        let stored: [(ScrollHoldKey, UInt16, String)] = [
            (.faster, KeyCode.controlL, "⌃"),
            (.sideways, KeyCode.optionL, "⌥"),
            (.pause, KeyCode.shiftL, "⇧"),
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

    func testHoldKeysAreNamedAsTheButtonsPaneNamesTriggers() {
        let unnamed = ButtonTriggerNaming.Logitech(role: { _ in nil }, name: { _ in nil })
        let names = PreferencesScrollingViewController.holdKeyTitles(for: [
            ScrollHotkey(type: .keyboard, code: KeyCode.controlL),
            ScrollHotkey(type: .keyboard, code: 40),
            ScrollHotkey(type: .mouse, code: 2),
            ScrollHotkey(type: .mouse, code: 3),
            ScrollHotkey(type: .mouse, code: 5),
            ScrollHotkey(type: .mouse, code: 1234),
            nil,
        ], logitech: unnamed)
        XCTAssertEqual(names, ["⌃", "K", "Middle button", "Back button", "Button 5", "1234 button", "None"])
        XCTAssertFalse(names.contains { $0.isEmpty || $0.contains("🖱") }, "no empty title, no mouse emoji")
        for (index, hotkey) in [ScrollHotkey(type: .mouse, code: 3), ScrollHotkey(type: .mouse, code: 5)].enumerated() {
            let event = RecordedEvent(type: hotkey.type, code: hotkey.code, modifiers: 0, deviceFilter: nil)
            XCTAssertEqual(names[3 + index], ButtonTriggerNaming.title(for: event), "the Buttons pane's name")
        }

        // A Logitech Back button next to the standard one says which it is, as in the Buttons pane.
        let back = ButtonTriggerNaming.Logitech(role: { _ in .back }, name: { _ in "Back" })
        XCTAssertEqual(
            PreferencesScrollingViewController.holdKeyTitles(for: [
                ScrollHotkey(type: .mouse, code: 3), nil, ScrollHotkey(type: .mouse, code: 1234),
            ], logitech: back),
            ["Back button", "None", "Back button (Logitech)"]
        )
    }

    func testKeyRowsNameAModifierAMouseButtonAndNoKey() {
        let controller = makeController(advanced: true)
        let scroll = Options.shared.scroll
        scroll.dash = ScrollHotkey(type: .keyboard, code: KeyCode.optionL)
        scroll.toggle = ScrollHotkey(type: .mouse, code: 3)
        scroll.block = nil
        controller.syncViewWithOptions()

        XCTAssertEqual(controller.keyBindButtons.map(\.title), ["⌥", "Back button", "None"])
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

    // MARK: - Thumb wheel

    /// Counts the changes of the thumb wheel settings (what both panes hear) until the test ends.
    private func countThumbWheelChanges() -> () -> Int {
        var count = 0
        let observer = ThumbWheelSettingsChange.addObserver { count += 1 }
        addTeardownBlock { ThumbWheelSettingsChange.removeObserver(observer) }
        return { count }
    }

    private func choose(_ function: ThumbWheelFunction, in controller: PreferencesScrollingViewController) {
        let popUp = controller.thumbWheelFunctionPopUp!
        popUp.selectItem(at: ThumbWheelFunction.allCases.firstIndex(of: function)!)
        send(popUp)
    }

    func testThumbWheelPopUpOffersTheSixFunctionsAndSaysWhatEachDoes() {
        let controller = makeController()
        let popUp = controller.thumbWheelFunctionPopUp!
        XCTAssertFalse(popUp.pullsDown)
        XCTAssertEqual(popUp.itemTitles, ["Scroll Sideways", "Zoom", "Switch Tabs", "Switch Desktops", "Back and Forward", "Volume"])
        XCTAssertEqual(popUp.itemArray.compactMap(ThumbWheelPresentation.function(of:)), ThumbWheelFunction.allCases)
        XCTAssertTrue(popUp.itemArray.allSatisfy { $0.image?.isTemplate == true }, "a symbol each, in the text's colour")
        if #available(macOS 27.0, *) {
            XCTAssertTrue(popUp.itemArray.allSatisfy { $0.preferredImageVisibility == .visible }, "macOS 27 keeps them")
        }
        XCTAssertEqual(popUp.indexOfSelectedItem, 0, "scrolls sideways by default")
        XCTAssertEqual(controller.thumbWheelFunctionRow.explanation, "Scrolls sideways.")

        let lines: [ThumbWheelFunction: String] = [
            .scroll: "Scrolls sideways.", .zoom: "Zooms the page in and out.", .tabs: "Switches between tabs.",
            .desktops: "Switches between desktops.", .backForward: "Goes back and forward.",
            .volume: "Turns the volume up and down.",
        ]
        let height = controller.view.fittingSize.height
        for function in ThumbWheelFunction.allCases.reversed() {
            choose(function, in: controller)
            XCTAssertEqual(Options.shared.thumbWheel.function, function)
            XCTAssertEqual(controller.thumbWheelFunctionRow.explanation, lines[function])
            XCTAssertEqual(controller.thumbWheelFunctionPopUp.accessibilityHelp(), lines[function], "VoiceOver reads the line")
            XCTAssertEqual(controller.view.fittingSize.height, height, "\(function): the tab never jumps")
        }
    }

    /// Choosing a function writes the function only, once; choosing the one there writes
    /// nothing. The scroll options are not touched.
    func testChoosingAThumbWheelFunctionWritesOnlyTheFunction() {
        let controller = makeController()
        Options.shared.thumbWheel = ThumbWheelSettings(function: .scroll, speed: 1.4, swapsDirection: true)
        let changes = countThumbWheelChanges()

        choose(.desktops, in: controller)
        XCTAssertEqual(Options.shared.thumbWheel, ThumbWheelSettings(function: .desktops, speed: 1.4, swapsDirection: true))
        XCTAssertEqual(changes(), 1)
        choose(.desktops, in: controller)
        XCTAssertEqual(changes(), 1, "the same function is not written again")
        XCTAssertEqual(Options.shared.scroll, OPTIONS_SCROLL_DEFAULT())
        XCTAssertTrue(controller.resetToDefaultsButton.isEnabled, "the thumb wheel is off its defaults")
    }

    /// The speed: 0.25× to 3× on a grid of 0.05, shown and spoken as "1.25×", written only
    /// when the knob moved, never moved by a refresh while it is dragged.
    func testThumbWheelSpeedSnapsShowsItsFactorAndWritesOnlyWhenMoved() {
        let controller = makeController()
        let slider = controller.thumbWheelSpeedSlider as! PreferencesSlider
        let row = controller.thumbWheelSpeedRow!
        XCTAssertEqual(slider.minValue, 0.25)
        XCTAssertEqual(slider.maxValue, 3.0)
        XCTAssertEqual(slider.numberOfTickMarks, 12, "a tick every quarter")
        XCTAssertEqual(slider.doubleValue, 1.0, accuracy: 1e-9)
        XCTAssertEqual(row.valueText, ThumbWheelPresentation.speedText(1.0))
        XCTAssertEqual(slider.accessibilityValueDescription(), ThumbWheelPresentation.speedText(1.0))
        let changes = countThumbWheelChanges()

        drag(slider, to: 1.27)
        XCTAssertEqual(Options.shared.thumbWheel.speed, 1.25, accuracy: 1e-9, "on the grid of 0.05")
        XCTAssertEqual(row.valueText, ThumbWheelPresentation.speedText(1.25))
        XCTAssertEqual(slider.accessibilityValueDescription(), ThumbWheelPresentation.speedText(1.25))
        XCTAssertEqual(changes(), 1)
        drag(slider, to: 1.26)
        XCTAssertEqual(changes(), 1, "the same value is not written again")
        drag(slider, to: 0)
        XCTAssertEqual(Options.shared.thumbWheel.speed, 0.25)
        drag(slider, to: 9)
        XCTAssertEqual(Options.shared.thumbWheel.speed, 3.0)
        XCTAssertEqual(Options.shared.thumbWheel.function, .scroll, "only the speed")
        XCTAssertFalse(Options.shared.thumbWheel.swapsDirection)

        // The arrow keys and VoiceOver move it a step of the grid.
        Options.shared.thumbWheel.speed = 1.0
        XCTAssertTrue(slider.moveKnob(by: 1))
        XCTAssertEqual(Options.shared.thumbWheel.speed, 1.05, accuracy: 1e-9)

        // A value off the grid (set elsewhere) is shown as it is; a press that does not move
        // the knob writes nothing.
        Options.shared.thumbWheel.speed = 1.234
        XCTAssertEqual(slider.doubleValue, 1.234, accuracy: 1e-9)
        let before = changes()
        slider.beginTracking()
        slider.endTracking()
        XCTAssertEqual(changes(), before)
        XCTAssertEqual(Options.shared.thumbWheel.speed, 1.234, accuracy: 1e-9)

        // While the knob is dragged a refresh leaves it where the hand is.
        slider.beginTracking()
        slider.doubleValue = 2.0
        Options.shared.thumbWheel.swapsDirection = true
        XCTAssertEqual(slider.doubleValue, 2.0, accuracy: 1e-9)
        slider.endTracking()
        XCTAssertEqual(Options.shared.thumbWheel.speed, 2.0, accuracy: 1e-9, "let go: the move is written")
    }

    func testThumbWheelSpeedIsWrittenWithTwoDecimalsInTheUsersLocale() {
        XCTAssertEqual(ThumbWheelPresentation.speedText(1.25, locale: Locale(identifier: "en_US")), "1.25×")
        XCTAssertEqual(ThumbWheelPresentation.speedText(1.0, locale: Locale(identifier: "en_US")), "1.00×")
        XCTAssertEqual(ThumbWheelPresentation.speedText(3.0, locale: Locale(identifier: "en_US")), "3.00×")
        XCTAssertEqual(ThumbWheelPresentation.speedText(1.25, locale: Locale(identifier: "sl_SI")), "1,25×")
        XCTAssertEqual(ThumbWheelPresentation.speedSetting.snapped(1.274), 1.25)
        XCTAssertEqual(ThumbWheelPresentation.speedSetting.snapped(1.276), 1.3)
        XCTAssertEqual(ThumbWheelPresentation.speedSetting.range, ThumbWheelSettings.speedRange)
    }

    /// The line under Speed follows the function, and while the wheel scrolls with "Smooth
    /// scrolling" off it says where the speed still applies; every line takes one line, so
    /// the row is as tall as the main Speed row and never jumps. The slider is never off.
    func testThumbWheelSpeedLineFollowsTheFunctionAndSmoothing() {
        let controller = makeController()
        let row = controller.thumbWheelSpeedRow!
        controller.view.layoutSubtreeIfNeeded()
        let height = controller.view.fittingSize.height
        let rowHeight = row.frame.height
        let measure = NSTextField(wrappingLabelWithString: "X")
        measure.font = PreferencesForm.hintFont
        let oneLine = measure.fittingSize.height
        XCTAssertEqual(rowHeight, controller.speedRow.frame.height, accuracy: 0.5)
        XCTAssertEqual(row.explanation, "How far a turn scrolls sideways.")
        XCTAssertEqual(row.explanationLabel.frame.height, oneLine, accuracy: 0.5)

        func check(_ line: String, _ label: String) {
            controller.view.layoutSubtreeIfNeeded()
            XCTAssertEqual(row.explanation, line, label)
            XCTAssertEqual(controller.thumbWheelSpeedSlider.accessibilityHelp(), line, "\(label): VoiceOver reads the line")
            XCTAssertEqual(row.explanationLabel.frame.height, oneLine, accuracy: 0.5, "\(label): one line")
            XCTAssertEqual(row.frame.height, rowHeight, accuracy: 0.5, "\(label): the row keeps its height")
            XCTAssertEqual(controller.view.fittingSize.height, height, "\(label): the tab never jumps")
            XCTAssertTrue(row.isEnabled, label)
            XCTAssertTrue(controller.thumbWheelSpeedSlider.isEnabled, label)
            XCTAssertEqual(row.titleLabel.textColor, .labelColor, label)
        }
        choose(.tabs, in: controller)
        check("How little of a turn each step needs.", "tabs")
        set(controller.smoothSwitch, false)
        check("How little of a turn each step needs.", "tabs without smoothing")
        choose(.scroll, in: controller)
        check("Applies where Smooth scrolling is on.", "scroll without smoothing")
        XCTAssertEqual(row.valueText, ThumbWheelPresentation.speedText(1.0), "the value still shows")
        set(controller.smoothSwitch, true)
        check("How far a turn scrolls sideways.", "scroll")

        XCTAssertEqual(ThumbWheelPresentation.speedHintKey(for: .scroll, smoothing: true), "scrolling-thumb-wheel-speed-hint-scroll")
        XCTAssertEqual(ThumbWheelPresentation.speedHintKey(for: .scroll, smoothing: false), "scrolling-thumb-wheel-speed-hint-smoothing-off")
        for function in ThumbWheelFunction.allCases where function != .scroll {
            for smoothing in [true, false] {
                XCTAssertEqual(ThumbWheelPresentation.speedHintKey(for: function, smoothing: smoothing), "scrolling-thumb-wheel-speed-hint-steps")
            }
        }
    }

    func testThumbWheelSwapSwitchWritesSwapsDirection() {
        let controller = makeController()
        XCTAssertEqual(controller.thumbWheelSwapSwitch.state, .off)
        let changes = countThumbWheelChanges()
        set(controller.thumbWheelSwapSwitch, true)
        XCTAssertEqual(Options.shared.thumbWheel, ThumbWheelSettings(function: .scroll, speed: 1.0, swapsDirection: true))
        set(controller.thumbWheelSwapSwitch, true)
        XCTAssertEqual(changes(), 1, "a state it has is not written again")
        set(controller.thumbWheelSwapSwitch, false)
        XCTAssertEqual(Options.shared.thumbWheel, .default)
        XCTAssertEqual(Options.shared.scroll, OPTIONS_SCROLL_DEFAULT(), "nothing else")
    }

    /// A change made elsewhere (the Buttons pane) shows at once, and showing it writes
    /// nothing back.
    func testAThumbWheelChangeElsewhereShowsWithoutBeingWrittenBack() {
        let controller = makeController()
        let changes = countThumbWheelChanges()
        Options.shared.thumbWheel = ThumbWheelSettings(function: .volume, speed: 2.5, swapsDirection: true)
        XCTAssertEqual(changes(), 1, "only the change itself")
        XCTAssertEqual(controller.thumbWheelFunctionPopUp.indexOfSelectedItem, ThumbWheelFunction.allCases.firstIndex(of: .volume))
        XCTAssertEqual(controller.thumbWheelFunctionRow.explanation, "Turns the volume up and down.")
        XCTAssertEqual(controller.thumbWheelSpeedSlider.doubleValue, 2.5, accuracy: 1e-9)
        XCTAssertEqual(controller.thumbWheelSpeedRow.valueText, ThumbWheelPresentation.speedText(2.5))
        XCTAssertEqual(controller.thumbWheelSwapSwitch.state, .on)
        XCTAssertTrue(controller.resetToDefaultsButton.isEnabled)
        Options.shared.thumbWheel.function = .zoom
        XCTAssertEqual(changes(), 2)
        XCTAssertEqual(controller.thumbWheelFunctionPopUp.titleOfSelectedItem, "Zoom")
        XCTAssertEqual(Options.shared.thumbWheel, ThumbWheelSettings(function: .zoom, speed: 2.5, swapsDirection: true))
    }

    /// "Reset to Defaults" also gives the thumb wheel its defaults, and Undo brings back
    /// what it had; Redo resets it again.
    func testResetAlsoResetsTheThumbWheelAndUndoBringsItBack() {
        let controller = makeController()
        let undo = UndoManager()
        undo.groupsByEvent = false
        controller.paneUndoManager = undo
        let changed = ThumbWheelSettings(function: .tabs, speed: 1.5, swapsDirection: true)
        Options.shared.thumbWheel = changed
        XCTAssertTrue(controller.hasSettingsToReset, "the thumb wheel alone counts")
        XCTAssertTrue(controller.resetToDefaultsButton.isEnabled)

        undo.beginUndoGrouping()
        send(controller.resetToDefaultsButton)
        undo.endUndoGrouping()
        XCTAssertEqual(Options.shared.thumbWheel, .default)
        XCTAssertEqual(controller.thumbWheelFunctionPopUp.indexOfSelectedItem, 0)
        XCTAssertEqual(controller.thumbWheelSwapSwitch.state, .off)
        XCTAssertFalse(controller.resetToDefaultsButton.isEnabled)
        XCTAssertEqual(undo.undoMenuItemTitle, "Undo Reset Scrolling")

        undo.undo()
        XCTAssertEqual(Options.shared.thumbWheel, changed)
        XCTAssertEqual(controller.thumbWheelFunctionPopUp.titleOfSelectedItem, "Switch Tabs")
        XCTAssertEqual(controller.thumbWheelSpeedSlider.doubleValue, 1.5, accuracy: 1e-9)
        XCTAssertEqual(controller.thumbWheelSwapSwitch.state, .on)
        XCTAssertTrue(controller.resetToDefaultsButton.isEnabled)

        undo.redo()
        XCTAssertEqual(Options.shared.thumbWheel, .default)
        undo.undo()
        XCTAssertEqual(Options.shared.thumbWheel, changed)

        // With scroll options changed too, one reset and one Undo cover both.
        Options.shared.scroll.speed = 2.0
        undo.beginUndoGrouping()
        send(controller.resetToDefaultsButton)
        undo.endUndoGrouping()
        XCTAssertEqual(Options.shared.scroll, OPTIONS_SCROLL_DEFAULT())
        XCTAssertEqual(Options.shared.thumbWheel, .default)
        undo.undo()
        XCTAssertEqual(Options.shared.scroll.speed, 2.0)
        XCTAssertEqual(Options.shared.thumbWheel, changed)
    }

    /// An app's page has no thumb wheel: its reset and its Undo leave the thumb wheel
    /// alone, and the thumb wheel's settings do not make the app's reset available.
    func testAnAppsPageLeavesTheThumbWheelAlone() {
        let changed = ThumbWheelSettings(function: .zoom, speed: 0.5, swapsDirection: true)
        Options.shared.thumbWheel = changed
        let application = makeApplication(inherit: false)
        let undo = UndoManager()
        undo.groupsByEvent = false
        let controller = makeController(target: application, advanced: true)
        controller.paneUndoManager = undo
        XCTAssertTrue(controller.thumbWheelSection.isHidden)
        XCTAssertFalse(controller.hasSettingsToReset, "the app's own options are the defaults")
        XCTAssertFalse(controller.resetToDefaultsButton.isEnabled)

        application.scroll.speed = 4.5
        controller.syncViewWithOptions()
        undo.beginUndoGrouping()
        send(controller.resetToDefaultsButton)
        undo.endUndoGrouping()
        XCTAssertEqual(application.scroll, OPTIONS_SCROLL_DEFAULT())
        XCTAssertEqual(Options.shared.thumbWheel, changed, "not the app's")
        undo.undo()
        XCTAssertEqual(application.scroll.speed, 4.5)
        XCTAssertEqual(Options.shared.thumbWheel, changed)

        // A change from elsewhere keeps the group hidden on the page.
        Options.shared.thumbWheel = .default
        XCTAssertTrue(controller.thumbWheelSection.isHidden)
    }

    /// A reset with the thumb wheel at its defaults writes the scroll options only: the
    /// thumb wheel is neither changed nor saved, and neither is it by the Undo.
    func testResetLeavesTheThumbWheelUnwrittenWhenItIsAtItsDefaults() {
        let controller = makeController()
        let undo = UndoManager()
        undo.groupsByEvent = false
        controller.paneUndoManager = undo
        Options.shared.scroll.speed = 2.0
        controller.syncViewWithOptions()
        Options.shared.flushPendingSaves()
        var flushed: [Set<OptionsGroup>] = []
        Options.shared.onFlushForTests = { flushed.append($0) }
        defer { Options.shared.onFlushForTests = nil }
        let changes = countThumbWheelChanges()

        undo.beginUndoGrouping()
        send(controller.resetToDefaultsButton)
        undo.endUndoGrouping()
        XCTAssertEqual(Options.shared.scroll, OPTIONS_SCROLL_DEFAULT())
        XCTAssertEqual(changes(), 0, "the thumb wheel is not written")
        Options.shared.flushPendingSaves()
        XCTAssertEqual(flushed, [[.scroll]], "only the scroll options are saved")

        undo.undo()
        XCTAssertEqual(Options.shared.scroll.speed, 2.0)
        XCTAssertEqual(changes(), 0, "nor by the Undo")
        XCTAssertEqual(Options.shared.thumbWheel, .default)
    }

    /// Every Scrolling tab and app page listens for thumb wheel changes while it exists and
    /// stops when it goes: opening and closing pages leaves no listener behind.
    func testScrollingTabsAndAppPagesLeaveNoThumbWheelObserverBehind() {
        let before = ThumbWheelSettingsChange.observerCount
        weak var lastTab: PreferencesScrollingViewController?
        weak var lastPage: ApplicationDetailViewController?
        autoreleasepool {
            var pages: [ApplicationDetailViewController] = []
            for _ in 0..<3 {
                let page = ApplicationDetailViewController(application: makeApplication(inherit: false), uiStateDefaults: uiDefaults)
                _ = page.view
                pages.append(page)
            }
            let tab = makeController()
            XCTAssertEqual(ThumbWheelSettingsChange.observerCount, before + 4, "one per tab while it exists")
            lastTab = tab
            lastPage = pages.last
            Options.shared.thumbWheel.function = .zoom
            XCTAssertEqual(tab.thumbWheelFunctionPopUp.titleOfSelectedItem, "Zoom")
        }
        XCTAssertNil(lastTab, "the tab is gone")
        XCTAssertNil(lastPage, "the pages are gone")
        XCTAssertEqual(ThumbWheelSettingsChange.observerCount, before, "and so are their observers")
        Options.shared.thumbWheel = .default
    }

    /// The accessibility group that names `view` (its nearest ancestor that is an
    /// accessibility group), nil when none does.
    private func accessibilityGroup(of view: NSView) -> NSView? {
        var current = view.superview
        while let candidate = current {
            if candidate.isAccessibilityElement(), candidate.accessibilityRole() == .group {
                return candidate
            }
            current = candidate.superview
        }
        return nil
    }

    /// VoiceOver tells the two "Speed" sliders apart: the thumb wheel's controls are in a
    /// group named "Thumb wheel" (with the line under its box as help), the main wheel's are
    /// not. The name is the group's, so setting a row's line (which names its controls again)
    /// cannot take it away.
    func testTheThumbWheelControlsAreInAGroupNamedThumbWheel() {
        let controller = makeController()
        let section = controller.thumbWheelSection!
        XCTAssertTrue(section.isAccessibilityElement())
        XCTAssertEqual(section.accessibilityRole(), .group)
        XCTAssertEqual(section.accessibilityLabel(), "Thumb wheel")
        XCTAssertEqual(section.accessibilityHelp(), controller.thumbWheelNote.stringValue)
        XCTAssertEqual(section.titleLabel?.isAccessibilityElement(), false, "the title is the group's name, not read twice")
        for control in [controller.thumbWheelFunctionPopUp!, controller.thumbWheelSpeedSlider!, controller.thumbWheelSwapSwitch!] as [NSControl] {
            XCTAssertTrue(accessibilityGroup(of: control) === section, "\(control)")
        }
        XCTAssertNil(accessibilityGroup(of: controller.scrollSpeedSlider), "the main wheel's Speed is in no such group")
        XCTAssertEqual(controller.thumbWheelSpeedSlider.accessibilityLabel(), "Speed")

        // Choosing a function relabels the row's controls; the group keeps its name.
        choose(.zoom, in: controller)
        Options.shared.scroll.smooth = false
        controller.syncViewWithOptions()
        XCTAssertEqual(section.accessibilityLabel(), "Thumb wheel")
        XCTAssertTrue(accessibilityGroup(of: controller.thumbWheelSpeedSlider) === section)
    }

    /// With "Smooth scrolling" off an app with settings of its own may still smooth the thumb
    /// wheel, at this speed (it has no per-app speed): the slider stays on, and while the
    /// wheel scrolls its line says where the speed applies.
    func testTheThumbWheelSpeedStaysOnWhileSmoothingIsOff() {
        let saved = Options.shared.application.applications
        addTeardownBlock { Options.shared.application.applications = saved }
        let application = makeApplication(inherit: false)
        application.scroll.smooth = true
        Options.shared.application.applications = EnhanceArray<Application>(withArray: [application], matchKey: "path")
        Options.shared.scroll.smooth = false
        XCTAssertTrue(application.isSmooth(false), "the app's own rule smooths it")

        let controller = makeController()
        XCTAssertEqual(Options.shared.thumbWheel.function, .scroll)
        XCTAssertTrue(controller.thumbWheelSpeedSlider.isEnabled, "the speed still applies in the app with smoothing on")
        XCTAssertTrue(controller.thumbWheelSpeedRow.isEnabled)
        XCTAssertEqual(controller.thumbWheelSpeedRow.explanation, "Applies where Smooth scrolling is on.")
        drag(controller.thumbWheelSpeedSlider, to: 1.5)
        XCTAssertEqual(Options.shared.thumbWheel.speed, 1.5, accuracy: 1e-9, "and it can be set")
    }

    // MARK: - Advanced

    func testAdvancedIsClosedByDefaultAndHidesItsRows() {
        uiDefaults.removeObject(forKey: PreferencesScrollingViewController.advancedExpandedDefaultsKey)
        let controller = storyboard.instantiateController(withIdentifier: PANEL_IDENTIFIER.scrolling) as! PreferencesScrollingViewController
        controller.uiStateDefaults = uiDefaults
        _ = controller.view

        XCTAssertFalse(controller.isAdvancedExpanded)
        let opened: [NSView] = [controller.glideTimeRow, controller.smallestStepRow, controller.trackpadEventsRow]
        XCTAssertEqual(controller.advancedRows, opened, "two sliders and the switch")
        XCTAssertTrue(controller.advancedRows.allSatisfy(\.isHidden))
        // The box of "Advanced" shows only its header row, without hairlines.
        XCTAssertEqual(controller.advancedSection.box.visibleRows, [controller.advancedRow])
        XCTAssertEqual(controller.advancedSection.box.separatorRects, [])
        // What is always there: the keys too, which work from the first launch.
        var alwaysThere: [NSView] = [
            controller.previewView, controller.smoothSwitch, controller.feelControl,
            controller.scrollSpeedSlider, controller.reverseSwitch, controller.advancedButton,
            controller.resetToDefaultsButton, controller.sections[0], controller.advancedSection,
            controller.keysSection,
        ]
        alwaysThere.append(contentsOf: controller.keyBindButtons)
        alwaysThere.append(contentsOf: controller.keyRows)
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
        XCTAssertEqual(controller.advancedSection.box.separatorRects.count, 3, "a hairline above each opened row")
        XCTAssertTrue(uiDefaults.bool(forKey: key))
        XCTAssertTrue(controller.advancedButton.isAccessibilityExpanded())
        XCTAssertFalse(controller.keysSection.isHidden, "the keys show either way")
        let openHeight = controller.view.fittingSize.height
        XCTAssertGreaterThan(openHeight, closedHeight + 150)
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
        XCTAssertFalse(controller.keysSection.isHidden)
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
        XCTAssertEqual(controller.keyBindButtons.map(\.title), ["⌥", "⇧", "⌘"])
        XCTAssertFalse(controller.resetToDefaultsButton.isEnabled)
        XCTAssertTrue(controller.isAdvancedExpanded, "reset closes nothing")
        XCTAssertTrue(uiDefaults.bool(forKey: PreferencesScrollingViewController.advancedExpandedDefaultsKey))
    }

    /// "Reset to Defaults" asks nothing: Edit › Undo ("Undo Reset Scrolling") brings back
    /// every value it changed, the direction and the three keys too, and Redo resets again.
    func testResetCanBeUndoneAndRedone() throws {
        let controller = makeController(advanced: true)
        let undo = UndoManager()
        undo.groupsByEvent = false
        controller.paneUndoManager = undo
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
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let before = String(decoding: try encoder.encode(scroll), as: UTF8.self)
        controller.syncViewWithOptions()
        let titlesBefore = controller.keyBindButtons.map(\.title)

        undo.beginUndoGrouping()
        send(controller.resetToDefaultsButton)
        undo.endUndoGrouping()
        XCTAssertEqual(Options.shared.scroll, OPTIONS_SCROLL_DEFAULT())
        XCTAssertTrue(undo.canUndo)
        XCTAssertEqual(undo.undoMenuItemTitle, "Undo Reset Scrolling")

        undo.undo()
        XCTAssertEqual(String(decoding: try encoder.encode(Options.shared.scroll), as: UTF8.self), before, "every value is back")
        XCTAssertEqual(controller.smoothSwitch.state, .off, "and shown")
        XCTAssertEqual(controller.reverseSwitch.state, .off)
        XCTAssertEqual(controller.scrollSpeedSlider.doubleValue, 2.0, accuracy: 1e-9)
        XCTAssertEqual(controller.glideTimeSlider.doubleValue, 4.9, accuracy: 1e-9)
        XCTAssertEqual(controller.smallestStepSlider.doubleValue, 12, accuracy: 1e-9)
        XCTAssertEqual(controller.trackpadEventsSwitch.state, .on)
        XCTAssertEqual(controller.keyBindButtons.map(\.title), titlesBefore)
        XCTAssertTrue(controller.resetToDefaultsButton.isEnabled)
        XCTAssertTrue(undo.canRedo)
        XCTAssertEqual(undo.redoMenuItemTitle, "Redo Reset Scrolling")

        undo.redo()
        XCTAssertEqual(Options.shared.scroll, OPTIONS_SCROLL_DEFAULT(), "reset again")
        XCTAssertFalse(controller.resetToDefaultsButton.isEnabled)
        XCTAssertTrue(undo.canUndo, "the chain goes on")
        undo.undo()
        XCTAssertEqual(String(decoding: try encoder.encode(Options.shared.scroll), as: UTF8.self), before)

        // In the window, the window's undo manager takes it.
        controller.paneUndoManager = nil
        XCTAssertNil(controller.undoTarget, "no window, no Undo")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 600), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(controller.view)
        XCTAssertTrue(controller.undoTarget === window.undoManager)
        controller.view.removeFromSuperview()
        window.close()
    }

    /// On an app's page the reset and its Undo touch that app's own options only, and the
    /// Undo still works once the page (and its controller) is gone.
    func testResetOnAnAppsPageCanBeUndoneAfterThePageIsGone() {
        let application = makeApplication(inherit: false)
        application.scroll.speed = 4.5
        application.scroll.reversesWheel = false
        application.scroll.dash = nil
        let undo = UndoManager()
        undo.groupsByEvent = false
        autoreleasepool {
            let controller = makeController(target: application, advanced: true)
            controller.paneUndoManager = undo
            undo.beginUndoGrouping()
            send(controller.resetToDefaultsButton)
            undo.endUndoGrouping()
            XCTAssertEqual(application.scroll, OPTIONS_SCROLL_DEFAULT())
        }

        undo.undo()
        XCTAssertEqual(application.scroll.speed, 4.5)
        XCTAssertFalse(application.scroll.reverse)
        XCTAssertNil(application.scroll.dash)
        XCTAssertEqual(Options.shared.scroll, OPTIONS_SCROLL_DEFAULT(), "the Scrolling settings are not touched")
        undo.redo()
        XCTAssertEqual(application.scroll, OPTIONS_SCROLL_DEFAULT())
    }

    // MARK: - Preview

    /// A refresh leaves only the knob the user is dragging alone; every other knob shows
    /// its stored value at once, and the dragged one too once it is let go.
    func testARefreshLeavesOnlyTheDraggedKnobAlone() {
        let controller = makeController(advanced: true)
        let speed = controller.scrollSpeedSlider as! PreferencesSlider
        speed.beginTracking()
        drag(speed, to: 8)
        XCTAssertEqual(Options.shared.scroll.speed, 8)

        Options.shared.scroll.speed = 3
        Options.shared.scroll.duration = 1.5
        controller.syncViewWithOptions()
        XCTAssertEqual(speed.doubleValue, 8, accuracy: 1e-9, "under the pointer")
        XCTAssertEqual(controller.glideTimeSlider.doubleValue, 1.5, accuracy: 1e-9, "not being dragged")

        // Let go: the slider's last action stores where it was left, and the knob shows it.
        speed.endTracking()
        XCTAssertFalse(speed.isTracking)
        XCTAssertEqual(Options.shared.scroll.speed, 8)
        XCTAssertEqual(speed.doubleValue, 8, accuracy: 1e-9)
        Options.shared.scroll.speed = 3
        controller.syncViewWithOptions()
        XCTAssertEqual(speed.doubleValue, 3, accuracy: 1e-9)
    }

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

    /// The preview shows the vertical wheel: only the horizontal axis reversed (settings
    /// from older builds or Mos) leaves it running the normal way, while the switch is on.
    func testPreviewIsReversedOnlyWhenTheVerticalWheelIs() {
        Options.shared.scroll.reverse = true
        Options.shared.scroll.reverseVertical = false
        Options.shared.scroll.reverseHorizontal = true
        let controller = makeController()
        XCTAssertTrue(controller.reverseRow.isOn, "the switch: either axis")
        XCTAssertFalse(controller.previewView.scene.reversed, "the preview: the vertical wheel")

        Options.shared.scroll.reverseVertical = true
        Options.shared.scroll.reverseHorizontal = false
        controller.syncViewWithOptions()
        XCTAssertTrue(controller.previewView.scene.reversed)

        Options.shared.scroll.reverse = false
        Options.shared.scroll.reverseVertical = true
        controller.syncViewWithOptions()
        XCTAssertFalse(controller.previewView.scene.reversed, "the main flag off stops both axes")
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

    /// The keys always show: the preview points out the key of the row under the pointer,
    /// focused or recording, whether "Advanced" is open or not.
    func testPreviewPointsOutTheKeysWithAdvancedClosedOrOpen() {
        let controller = makeController(advanced: false)
        XCTAssertFalse(controller.isAdvancedExpanded)
        controller.keyRowHoverChanged(.faster, inside: true)
        XCTAssertEqual(controller.previewView.scene.emphasis, .faster)
        controller.keyRowHoverChanged(.faster, inside: false)
        controller.keyFocusChanged(.pause, focused: true)
        XCTAssertEqual(controller.previewView.scene.emphasis, .paused)
        controller.recordingKey = .sideways
        XCTAssertEqual(controller.previewEmphasis, .sideways)

        // Opening and closing "Advanced" leaves it as it is.
        send(controller.advancedButton)
        XCTAssertTrue(controller.isAdvancedExpanded)
        XCTAssertEqual(controller.previewView.scene.emphasis, .sideways)
        send(controller.advancedButton)
        XCTAssertEqual(controller.previewView.scene.emphasis, .sideways)

        controller.recordingKey = nil
        controller.keyFocusChanged(.pause, focused: false)
        XCTAssertEqual(controller.previewView.scene.emphasis, .wheel)
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
        XCTAssertEqual(application.scroll.speed, 4.5, "the app's slider has the tab's steps")
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

        // The page's "Use settings from Scrolling" switch turns the app's own values on.
        application.inherit = false
        controller.syncViewWithOptions()
        XCTAssertEqual(controller.scrollSpeedSlider.doubleValue, 1.5, accuracy: 1e-9)
        XCTAssertEqual(controller.feelControl.selectedSegment, ScrollFeel.smooth.rawValue)
        XCTAssertTrue(controller.smoothSwitch.isEnabled)
        XCTAssertTrue(controller.scrollSpeedSlider.isEnabled)
        XCTAssertTrue(controller.keyBindButtons.allSatisfy(\.isEnabled))
        XCTAssertTrue(controller.hasSettingsToReset)
    }

    func testThePerAppViewHasNoPreviewAndNoThumbWheel() {
        let global = makeController()
        let perApp = makeController(target: makeApplication(inherit: false))
        XCTAssertFalse(global.previewView.isHidden)
        XCTAssertTrue(perApp.previewView.isHidden)
        XCTAssertFalse(global.thumbWheelSection.isHiddenOrHasHiddenAncestor)
        XCTAssertFalse(global.thumbWheelNote.isHiddenOrHasHiddenAncestor)
        XCTAssertTrue(perApp.thumbWheelSection.isHidden, "the thumb wheel has no settings of an app's own")
        XCTAssertTrue(perApp.thumbWheelNote.isHiddenOrHasHiddenAncestor)
        global.view.layoutSubtreeIfNeeded()
        let thumbWheel = global.thumbWheelSection.frame.height
        let note = global.thumbWheelNote.superview?.frame.height ?? 0
        XCTAssertGreaterThan(thumbWheel, 100)
        XCTAssertGreaterThan(note, 10)
        // Without the thumb wheel the keys and "Advanced" are a box's gap apart, as they
        // were before the group existed.
        XCTAssertEqual(
            global.view.fittingSize.height - perApp.view.fittingSize.height,
            ScrollPreviewView.preferredHeight + PreferencesGroupedForm.boxSpacing
                + PreferencesGroupedForm.sectionSpacing + thumbWheel + PreferencesGroupedForm.noteSpacing + note,
            accuracy: 0.5,
            "shorter by the preview, the thumb wheel and their spaces"
        )
        // On the page the keys' title sits a section's gap under the main box and "Advanced"
        // a box's gap under the keys, as before the thumb wheel existed.
        perApp.view.layoutSubtreeIfNeeded()
        let basic = perApp.view.convert(perApp.sections[0].box.frame, from: perApp.sections[0])
        let keysTitle = perApp.view.convert(perApp.keysSection.titleLabel!.frame, from: perApp.keysSection)
        let keys = perApp.view.convert(perApp.keysSection.box.frame, from: perApp.keysSection)
        let advanced = perApp.view.convert(perApp.advancedSection.box.frame, from: perApp.advancedSection)
        XCTAssertEqual(basic.minY - keysTitle.maxY, PreferencesGroupedForm.sectionSpacing, accuracy: 0.5)
        XCTAssertEqual(keys.minY - advanced.maxY, PreferencesGroupedForm.boxSpacing, accuracy: 0.5)
    }

    func testAnAppsPageEmbedsTheTabWithItsApplication() throws {
        let application = makeApplication(inherit: false)
        application.scroll.speed = 4.2
        let page = ApplicationDetailViewController(application: application, uiStateDefaults: uiDefaults)
        var heightChanges = 0
        page.onHeightChange = { heightChanges += 1 }
        _ = page.view
        let tab = try XCTUnwrap(page.scrollingController)
        XCTAssertTrue(page.children.first === tab)
        XCTAssertTrue(tab.isViewLoaded, "the settings load with the page")
        XCTAssertTrue(tab.view.isDescendant(of: page.view))

        XCTAssertTrue(tab.currentTargetApplication === application)
        XCTAssertEqual(page.view.fittingSize.width, PreferencesScrollingViewController.paneWidth)
        XCTAssertEqual(tab.scrollSpeedSlider.doubleValue, 4.2, accuracy: 1e-9)
        XCTAssertTrue(tab.previewView.isHidden)
        XCTAssertEqual(page.inheritSwitch.state, .off)
        // "Use settings from Scrolling" is a switch row in the app's box, as in the boxes under it.
        XCTAssertEqual(page.inheritSwitch.controlSize, PreferencesGroupedForm.switchControlSize)
        XCTAssertEqual(page.inheritRow.title, "Use settings from Scrolling")
        XCTAssertEqual(page.headerSection.box.rows.count, 2)
        XCTAssertTrue(page.headerSection.box.rows.first === page.headerRow)

        // The page is as tall as the app's box and the settings under it, and follows
        // when "Advanced" opens and closes.
        page.view.layoutSubtreeIfNeeded()
        let header = page.view.fittingSize.height - tab.view.fittingSize.height
        XCTAssertGreaterThan(header, 100)
        tab.setAdvancedExpanded(false)
        let closed = page.view.fittingSize.height
        let changes = heightChanges
        tab.setAdvancedExpanded(true)
        XCTAssertEqual(heightChanges, changes + 1, "the page hears of it")
        let open = page.view.fittingSize.height
        XCTAssertEqual(open, tab.view.fittingSize.height + header, accuracy: 0.5)
        XCTAssertGreaterThan(open, closed + 150)
        tab.setAdvancedExpanded(false)
        XCTAssertEqual(page.view.fittingSize.height, closed, accuracy: 0.5)

        // "Use settings from Scrolling" greys the settings out.
        page.inheritSwitch.state = .on
        page.inheritClick(page.inheritSwitch)
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
            controller.feelControl, controller.thumbWheelFunctionPopUp, controller.thumbWheelSwapSwitch,
        ]
        rightEdges.append(contentsOf: controller.keyClearButtons)
        rightEdges.append(contentsOf: [controller.thumbWheelSpeedRow.valueLabel].compactMap { $0 })
        for view in rightEdges {
            XCTAssertEqual(frame(of: view, in: controller).maxX, boxRight - inset, accuracy: 1, "\(view)")
        }
        // The sliders form one column (the thumb wheel's too), and so do the key recorders.
        let sliders = [
            controller.scrollSpeedSlider!, controller.glideTimeSlider!, controller.smallestStepSlider!,
            controller.thumbWheelSpeedSlider!,
        ]
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
        lines.append((controller.thumbWheelFunctionPopUp, controller.thumbWheelFunctionRow))
        lines.append((controller.thumbWheelSpeedSlider, controller.thumbWheelSpeedRow))
        lines.append((controller.thumbWheelSwapSwitch, controller.thumbWheelSwapRow))
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
        let measure = NSTextField(wrappingLabelWithString: "X")
        measure.font = PreferencesForm.hintFont
        let oneLine = measure.fittingSize.height
        let keys = [
            "scrolling-smooth-hint", "scrolling-speed-hint", "scrolling-reverse-hint",
            "scrolling-glide-time-hint", "scrolling-step-hint",
            "scrolling-key-faster-hint", "scrolling-key-sideways-hint", "scrolling-key-pause-hint",
            "thumb-wheel-function-scroll-hint", "scrolling-thumb-wheel-speed-hint-scroll", "scrolling-thumb-wheel-swap-hint",
            "scrolling-thumb-wheel-note",
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
/// open, the defaults, a custom glide time and smoothing off, the tab and an app's page
/// under Apps. Off screen the window's material draws a flat grey and vibrant text is not
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

            // Three kinds of hold key: a modifier, a mouse button, none.
            if advanced {
                Options.shared.scroll = OPTIONS_SCROLL_DEFAULT()
                Options.shared.scroll.dash = ScrollHotkey(type: .keyboard, code: KeyCode.optionL)
                Options.shared.scroll.toggle = ScrollHotkey(type: .mouse, code: 3)
                Options.shared.scroll.block = nil
                tab.syncViewWithOptions()
                try render(tab.view, name: "tab-advanced-keys", into: directory)
            }

            // An app's page, with settings of its own and inheriting.
            Options.shared.scroll = OPTIONS_SCROLL_DEFAULT()
            for inherit in [false, true] {
                let application = Application(path: "/System/Applications/Calculator.app")
                application.inherit = inherit
                application.scroll.duration = ScrollFeel.direct.duration
                let page = ApplicationDetailViewController(application: application, uiStateDefaults: uiDefaults)
                // On the pane's background, as the Apps pane shows it.
                let pane = PreferencesForm.makeBackground()
                pane.addSubview(page.view)
                NSLayoutConstraint.activate([
                    page.view.topAnchor.constraint(equalTo: pane.topAnchor),
                    page.view.bottomAnchor.constraint(equalTo: pane.bottomAnchor),
                    page.view.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
                    page.view.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
                ])
                pane.setFrameSize(pane.fittingSize)
                try render(pane, name: "per-app-\(state)\(inherit ? "-inherit" : "")", into: directory)
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
