//
//  PreferencesGesturesTests.swift
//  MosTests
//
//  Gestures tab: its rows in the boxes of System Settings, every control writes its own
//  field of Options.shared.gesture and follows the mode rules, the tracking speed, the
//  "Gesture button" row and its way to the Buttons pane, the preview following the
//  settings and the row pointed at, and "Reset to Defaults" with its Undo. The Logitech
//  box has its own tests (LogiGestureSectionTests). "Up and Down follow the hand too": the
//  switch under "Mode", its line, what the Up and Down rows say and why one runs once
//  here, by what can follow the hand on the Mac a test describes (`follow`; never this
//  Mac's own Dock settings). Nothing is shown on screen and no HID device is touched.
//

import XCTest
@testable import Scrollio_Debug

final class PreferencesGesturesTests: XCTestCase {

    private typealias Slot = MouseGestureSettingsControls.Slot

    private var savedGesture = MouseGestureSettings.default
    private var isInteractiveAvailable = true
    private var summary = MouseGestureBindingSummary(hasGestureButton: true, hasLogitechGestureButton: false)
    /// What the connected mice can do: none is connected unless a test says so.
    private var support = MouseGestureDeviceSupport.none
    /// What can follow the hand up and down on the Mac a test describes: macOS 27, every
    /// gesture of the Dock on and Apps too (the owner's own build), unless a test says so.
    private var follow = PreferencesGesturesTests.follows()

    /// A Mac for `follow`: its macOS, whether this build lets Apps follow, the Dock's own
    /// switches and whether macOS lets Scrollio post events.
    static func follows(
        macOS: Int = 27, apps: Bool = true, switches: DockGestureSwitches = .allOn, canPostEvents: Bool = true
    ) -> DockFollowAvailability {
        return DockFollowAvailability(
            swipeIsAvailable: true, canPostEvents: canPostEvents, majorVersion: macOS, switches: switches, appsMayFollow: apps
        )
    }

    private func follows(
        macOS: Int = 27, apps: Bool = true, switches: DockGestureSwitches = .allOn, canPostEvents: Bool = true
    ) -> DockFollowAvailability {
        return Self.follows(macOS: macOS, apps: apps, switches: switches, canPostEvents: canPostEvents)
    }

    override func setUp() {
        super.setUp()
        savedGesture = Options.shared.gesture
        Options.shared.gesture = .default
        isInteractiveAvailable = true
        support = .none
        follow = Self.follows()
        summary = MouseGestureBindingSummary(hasGestureButton: true, hasLogitechGestureButton: false)
    }

    override func tearDown() {
        Options.shared.gesture = savedGesture
        super.tearDown()
    }

    private func makeController() -> GesturesPreferencesViewController {
        let controller = GesturesPreferencesViewController(isInteractiveAvailable: { [weak self] in
            self?.isInteractiveAvailable ?? true
        }, followAvailability: { [weak self] in
            self?.follow ?? Self.follows()
        })
        controller.deviceSource = MouseGestureDeviceSource(support: { [weak self] in self?.support ?? .none }, refresh: {})
        controller.bindingSummary = { [weak self] in
            self?.summary ?? MouseGestureBindingSummary(hasGestureButton: false, hasLogitechGestureButton: false)
        }
        _ = controller.view
        return controller
    }

    /// What the Swipe speed row writes, in the locale the tests run in ("1.5×", "1,5×").
    private func speedText(_ value: Double) -> String {
        return MouseGestureTrackingSpeed.text(value)
    }

    private func send(_ control: NSControl) {
        XCTAssertTrue(control.sendAction(control.action, to: control.target))
    }

    private func toggle(_ control: NSControl, on: Bool) {
        MouseGestureSettingsControls.setOn(on, control)
        send(control)
    }

    private func text(_ key: String) -> String {
        return NSLocalizedString(key, comment: "")
    }

    /// A pull-down shows its first menu item as the title.
    private func title(of popup: NSPopUpButton) -> String? {
        return popup.menu?.items.first?.title
    }

    /// The menu item of `popup` that stores `identifier` ("" is "No Action"). The rows
    /// have the Buttons pane's pull-down: an item holds its listed action, "No Action" none.
    private func item(_ identifier: String, in popup: NSPopUpButton) -> NSMenuItem? {
        let top = popup.menu?.items ?? []
        let nested = top.compactMap(\.submenu).flatMap(\.items)
        if identifier.isEmpty {
            return (popup as? ButtonActionPullDown)?.noActionItem
        }
        return (top + nested).first { item in
            item.action != nil && (item.representedObject as? SystemShortcut.Shortcut)?.identifier == identifier
        }
    }

    private func choose(_ identifier: String, in popup: NSPopUpButton, file: StaticString = #filePath, line: UInt = #line) {
        guard let item = item(identifier, in: popup), let action = item.action else {
            return XCTFail("no menu item for '\(identifier)'", file: file, line: line)
        }
        XCTAssertTrue(NSApp.sendAction(action, to: item.target, from: item), file: file, line: line)
    }

    private func frame(of view: NSView, in controller: NSViewController) -> NSRect {
        return controller.view.convert(view.bounds, from: view)
    }

    // MARK: - Pane

    func testPaneIsTitledGesturesAndAsWideAsScrolling() {
        let controller = makeController()
        XCTAssertEqual(controller.title, "Gestures")
        XCTAssertEqual(GesturesPreferencesViewController.tabIdentifier, "gestures")
        XCTAssertEqual(GesturesPreferencesViewController.paneWidth, PreferencesScrollingViewController.paneWidth)
        XCTAssertEqual(controller.view.frame.width, 520)
        XCTAssertEqual(controller.view.frame.size, controller.view.fittingSize)
    }

    func testThePaneIsAPreviewAndBoxesTopToBottom() {
        let controller = makeController()
        controller.view.layoutSubtreeIfNeeded()
        let shown = controller.sections.filter { !$0.isHidden }
        XCTAssertTrue(shown.first === controller.previewView)
        XCTAssertEqual(controller.previewView.frame.height, GesturePreviewView.preferredHeight)
        // The root view is not flipped: lower on screen is a smaller y.
        let tops = shown.map { frame(of: $0, in: controller).maxY }
        XCTAssertEqual(tops, tops.sorted(by: >))
        for view in shown {
            XCTAssertEqual(frame(of: view, in: controller).minX, 20, accuracy: 0.5)
            XCTAssertEqual(frame(of: view, in: controller).width, 480, accuracy: 0.5)
        }

        // Mode first, then Up, Down, Left, Right, Click, then the switches and the slider.
        let order: [NSView] = [controller.modeRow] + controller.directionRows
            + [controller.invertRow, controller.freezeRow, controller.trackingSpeedRow]
        let rowTops = order.map { frame(of: $0, in: controller).maxY }
        XCTAssertEqual(rowTops, rowTops.sorted(by: >))
        XCTAssertEqual(controller.directionRows.map(\.title), ["Up", "Down", "Left", "Right", "Click"])
        XCTAssertEqual(controller.directionsHintLabel.stringValue, text("gestures-directions-hint"))
    }

    func testRowsUseTheGroupedKit() {
        let controller = makeController()
        controller.view.layoutSubtreeIfNeeded()
        let controls = controller.controls!
        // The two modes across the box, under the title and its line.
        XCTAssertTrue(controller.modeRow.accessory === controls.modeControl)
        XCTAssertEqual(controller.modeRow.placement, .below)
        let mode = controls.modeControl
        XCTAssertEqual(controller.view.convert(mode.alignmentRect(forFrame: mode.frame), from: mode.superview).width, 480 - 20, accuracy: 0.5)
        // Every pop-up on the right edge of its box, all as wide.
        for slot in Slot.allCases {
            let popup = controls.actionPopUp(for: slot)
            XCTAssertTrue(controller.directionRows[slot.rawValue].accessory === popup)
            let rect = controller.view.convert(popup.alignmentRect(forFrame: popup.frame), from: popup.superview)
            XCTAssertEqual(rect.maxX, 520 - 20 - PreferencesGroupedForm.rowHorizontalInset, accuracy: 0.5, slot.name)
            XCTAssertEqual(rect.width, GesturesPreferencesViewController.popUpWidth, accuracy: 0.5, slot.name)
        }
        // Invert and freeze are switches now.
        XCTAssertTrue(controls.invertToggle is NSSwitch)
        XCTAssertTrue(controls.freezeToggle is NSSwitch)
        XCTAssertTrue(controller.invertRow.accessory === controls.invertToggle)
        XCTAssertTrue(controller.freezeRow.accessory === controls.freezeToggle)
        XCTAssertEqual(controller.invertRow.title, "Invert left and right")
        XCTAssertEqual(controller.freezeRow.title, "Freeze pointer during a gesture")
        XCTAssertEqual(controls.invertToggle.accessibilityLabel(), "Invert left and right")
        // The speed sliders of every pane end in "Slow" and "Fast", as System Settings' do.
        XCTAssertEqual(controller.trackingSpeedRow.lowEndLabel?.stringValue, "Slow")
        XCTAssertEqual(controller.trackingSpeedRow.highEndLabel?.stringValue, "Fast")
    }

    func testEveryExplanationIsOnePlainSentence() {
        Options.shared.gesture.mode = .interactive
        let controller = makeController()
        let rows: [PreferencesGroupRow] = [controller.modeRow, controller.invertRow, controller.freezeRow, controller.trackingSpeedRow]
        for row in rows {
            let explanation = row.explanation ?? ""
            XCTAssertFalse(explanation.isEmpty, row.title)
            XCTAssertTrue(explanation.hasSuffix("."), row.title)
            XCTAssertLessThanOrEqual(explanation.count, 80, row.title)
        }
    }

    // MARK: - Controls write Options.shared.gesture

    func testModeControlWritesTheModeAndSaysWhatItDoes() {
        let controller = makeController()
        let mode = controller.controls.modeControl
        XCTAssertEqual(mode.segmentCount, 2)
        XCTAssertEqual(mode.label(forSegment: 0), "One action per hold")
        XCTAssertEqual(mode.label(forSegment: 1), "Follow the hand")
        XCTAssertEqual(mode.selectedSegment, 0)
        XCTAssertEqual(controller.modeRow.explanation, text("gesture-mode-discrete-description"))
        let height = controller.view.frame.height

        mode.selectedSegment = 1
        send(mode)
        XCTAssertEqual(Options.shared.gesture.mode, .interactive)
        XCTAssertEqual(controller.modeRow.explanation, text("gesture-mode-interactive-description"))
        XCTAssertEqual(controller.view.frame.height, height, "the other line takes no more room")

        mode.selectedSegment = 0
        send(mode)
        XCTAssertEqual(Options.shared.gesture.mode, .discrete)
        XCTAssertEqual(controller.modeRow.explanation, text("gesture-mode-discrete-description"))
    }

    func testEachActionPopupWritesItsOwnSetting() {
        let controller = makeController()
        let controls = controller.controls!
        let choices: [(Slot, String)] = [
            (.up, SystemShortcut.copy.identifier),
            (.down, SystemShortcut.paste.identifier),
            (.left, SystemShortcut.navigateBack.identifier),
            (.right, SystemShortcut.navigateForward.identifier),
            (.click, SystemShortcut.mouseMiddleClick.identifier),
        ]
        for (slot, identifier) in choices {
            choose(identifier, in: controls.actionPopUp(for: slot))
        }

        var expected = MouseGestureSettings.default
        expected.upAction = SystemShortcut.copy.identifier
        expected.downAction = SystemShortcut.paste.identifier
        expected.leftAction = SystemShortcut.navigateBack.identifier
        expected.rightAction = SystemShortcut.navigateForward.identifier
        expected.clickAction = SystemShortcut.mouseMiddleClick.identifier
        XCTAssertEqual(Options.shared.gesture, expected)
        XCTAssertEqual(title(of: controls.actionPopUp(for: .up)), SystemShortcut.copy.localizedName)
        XCTAssertEqual(title(of: controls.actionPopUp(for: .click)), SystemShortcut.mouseMiddleClick.localizedName)
    }

    func testNoActionClearsASlot() {
        let controller = makeController()
        let up = controller.controls.actionPopUp(for: .up)
        XCTAssertEqual(title(of: up), SystemShortcut.missionControl.localizedName)

        choose("", in: up)

        XCTAssertEqual(Options.shared.gesture.upAction, "")
        XCTAssertEqual(title(of: up), "No Action")
    }

    func testSwitchesWriteInvertAndFreeze() {
        let controller = makeController()
        let controls = controller.controls!
        XCTAssertFalse(MouseGestureSettingsControls.isOn(controls.invertToggle))
        XCTAssertTrue(MouseGestureSettingsControls.isOn(controls.freezeToggle))

        toggle(controls.invertToggle, on: true)
        XCTAssertTrue(Options.shared.gesture.invertHorizontal)
        toggle(controls.freezeToggle, on: false)
        XCTAssertFalse(Options.shared.gesture.freezePointer)

        var expected = MouseGestureSettings.default
        expected.invertHorizontal = true
        expected.freezePointer = false
        XCTAssertEqual(Options.shared.gesture, expected, "nothing else moved")

        toggle(controls.invertToggle, on: false)
        toggle(controls.freezeToggle, on: true)
        XCTAssertEqual(Options.shared.gesture, .default)
    }

    func testControlsShowStoredSettings() {
        var settings = MouseGestureSettings.default
        settings.mode = .interactive
        settings.upAction = SystemShortcut.copy.identifier
        settings.clickAction = ""
        settings.invertHorizontal = true
        settings.freezePointer = false
        settings.trackingSpeed = 2.2
        Options.shared.gesture = settings

        let controller = makeController()
        let controls = controller.controls!
        XCTAssertEqual(controls.modeControl.selectedSegment, 1)
        XCTAssertEqual(title(of: controls.actionPopUp(for: .up)), SystemShortcut.copy.localizedName)
        XCTAssertEqual(title(of: controls.actionPopUp(for: .click)), "No Action")
        XCTAssertTrue(MouseGestureSettingsControls.isOn(controls.invertToggle))
        XCTAssertFalse(MouseGestureSettingsControls.isOn(controls.freezeToggle))
        // 2.2 lies between two ticks: the knob shows it on the nearer, the label as stored.
        XCTAssertEqual(controller.trackingSpeedSlider.doubleValue, 2.25, accuracy: 1e-9)
        XCTAssertEqual(controller.trackingSpeedRow.valueText, speedText(2.2))
        XCTAssertEqual(Options.shared.gesture.trackingSpeed, 2.2, "shown, not rewritten")
    }

    func testReloadPicksUpChangesMadeElsewhere() {
        let controller = makeController()
        // The popover in the Buttons tab changed the settings meanwhile.
        Options.shared.gesture.mode = .interactive
        Options.shared.gesture.downAction = SystemShortcut.copy.identifier
        Options.shared.gesture.freezePointer = false
        Options.shared.gesture.trackingSpeed = 1.8

        controller.viewWillAppear()

        let controls = controller.controls!
        XCTAssertEqual(controls.modeControl.selectedSegment, 1)
        XCTAssertEqual(title(of: controls.actionPopUp(for: .down)), SystemShortcut.copy.localizedName)
        XCTAssertFalse(MouseGestureSettingsControls.isOn(controls.freezeToggle))
        XCTAssertTrue(controller.trackingSpeedSlider.isEnabled)
        XCTAssertEqual(controller.trackingSpeedSlider.doubleValue, 1.75, accuracy: 1e-9, "the nearest tick")
        XCTAssertEqual(controller.trackingSpeedRow.valueText, speedText(1.8))
        XCTAssertEqual(controller.previewView.scene.gesture.mode, .interactive)
        XCTAssertEqual(controller.previewView.scene.gesture.trackingSpeed, 1.8)
    }

    // MARK: - Tracking speed

    func testTrackingSpeedSliderCoversTheStoredRange() {
        let controller = makeController()
        let slider = controller.trackingSpeedSlider
        XCTAssertEqual(slider.minValue, MouseGestureSettings.trackingSpeedRange.lowerBound)
        XCTAssertEqual(slider.maxValue, MouseGestureSettings.trackingSpeedRange.upperBound)
        XCTAssertEqual(slider.minValue, 0.5)
        XCTAssertEqual(slider.maxValue, 3)
        XCTAssertEqual(slider.doubleValue, 1, accuracy: 1e-9)
        XCTAssertEqual(controller.trackingSpeedRow.valueText, speedText(1))
        // Not "Tracking speed": that is the macOS pointer setting under Mouse.
        XCTAssertEqual(controller.trackingSpeedRow.title, "Swipe speed")
        XCTAssertEqual(slider.accessibilityLabel(), "Swipe speed")
        // A tick every 0.25, and the knob stops only on them.
        XCTAssertEqual(slider.numberOfTickMarks, 11)
        XCTAssertEqual(slider.tickMarkPosition, .below)
        XCTAssertTrue(slider.allowsTickMarkValuesOnly)
        XCTAssertEqual(
            MouseGestureTrackingSpeed.scale.tickValues(in: MouseGestureSettings.trackingSpeedRange),
            [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75, 3]
        )
        XCTAssertEqual(slider.identifier, GesturesPreferencesViewController.Identifier.trackingSpeed)
    }

    func testTrackingSpeedSliderWritesRoundedMultiplier() {
        Options.shared.gesture.mode = .interactive
        let controller = makeController()
        let slider = controller.trackingSpeedSlider

        slider.doubleValue = 1.66
        send(slider)
        XCTAssertEqual(Options.shared.gesture.trackingSpeed, 1.75, accuracy: 1e-9, "the nearest tick")
        XCTAssertEqual(controller.trackingSpeedRow.valueText, speedText(1.75))
        XCTAssertEqual(controller.previewView.scene.gesture.trackingSpeed, 1.75, accuracy: 1e-9)

        slider.doubleValue = 3
        send(slider)
        XCTAssertEqual(Options.shared.gesture.trackingSpeed, 3, accuracy: 1e-9)
        XCTAssertEqual(controller.trackingSpeedRow.valueText, speedText(3))

        // Nothing else moved.
        var expected = MouseGestureSettings.default
        expected.mode = .interactive
        expected.trackingSpeed = 3
        XCTAssertEqual(Options.shared.gesture, expected)
    }

    func testTrackingSpeedValues() throws {
        XCTAssertEqual(MouseGestureTrackingSpeed.step, 0.25)
        XCTAssertEqual(MouseGestureTrackingSpeed.snapped(0.1), 0.5)
        XCTAssertEqual(MouseGestureTrackingSpeed.snapped(9), 3)
        XCTAssertEqual(MouseGestureTrackingSpeed.snapped(1.3), 1.25, accuracy: 1e-9)
        XCTAssertEqual(MouseGestureTrackingSpeed.snapped(1.38), 1.5, accuracy: 1e-9)
        XCTAssertEqual(MouseGestureTrackingSpeed.snapped(.nan), 0.5)
        let english = Locale(identifier: "en_US")
        XCTAssertEqual(MouseGestureTrackingSpeed.text(0.5, locale: english), "0.5×")
        XCTAssertEqual(MouseGestureTrackingSpeed.text(0.75, locale: english), "0.75×")
        XCTAssertEqual(MouseGestureTrackingSpeed.text(1, locale: english), "1.0×")
        XCTAssertEqual(MouseGestureTrackingSpeed.text(1.25, locale: english), "1.25×")
        XCTAssertEqual(MouseGestureTrackingSpeed.text(2.5, locale: english), "2.5×")
        XCTAssertEqual(MouseGestureTrackingSpeed.text(1.3, locale: english), "1.3×", "a stored speed off the ticks")
        // The region's decimal mark, as the Scrolling pane writes its speeds (it was always a dot).
        let slovenian = Locale(identifier: "sl_SI")
        XCTAssertEqual(MouseGestureTrackingSpeed.text(1, locale: slovenian), "1,0×")
        XCTAssertEqual(MouseGestureTrackingSpeed.text(1.25, locale: slovenian), "1,25×")
        XCTAssertEqual(MouseGestureTrackingSpeed.text(2.5, locale: Locale(identifier: "de_DE")), "2,5×")
        XCTAssertEqual(
            MouseGestureTrackingSpeed.text(2.5, locale: slovenian), ScrollingSlider.speed.shownText(for: 2.5, locale: slovenian),
            "the same mark and the same sign as Scrolling › Speed"
        )

        // Every value the slider can show fits the value column of the row.
        let controller = makeController()
        controller.view.layoutSubtreeIfNeeded()
        let label = try XCTUnwrap(controller.trackingSpeedRow.valueLabel)
        for value in MouseGestureTrackingSpeed.scale.tickValues(in: MouseGestureSettings.trackingSpeedRange) {
            controller.trackingSpeedRow.valueText = MouseGestureTrackingSpeed.text(value)
            XCTAssertLessThanOrEqual(label.fittingSize.width, label.frame.width, controller.trackingSpeedRow.valueText)
        }
    }

    /// The Swipe speed slider stands where the Scrolling pane's sliders stand: both panes
    /// use the kit's value column (Scrolling had 34 pt, Gestures 40, so the sliders stood
    /// 6 pt apart from pane to pane).
    func testTheSliderStandsInTheScrollingPanesColumn() throws {
        func left(_ row: PreferencesSliderRow, in view: NSView) -> CGFloat {
            view.layoutSubtreeIfNeeded()
            return view.convert(row.slider.alignmentRect(forFrame: row.slider.frame), from: row.slider.superview).minX
        }
        let gestures = makeController()
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesScrollingViewController.self))
        let scrolling = try XCTUnwrap(
            storyboard.instantiateController(withIdentifier: PANEL_IDENTIFIER.scrolling) as? PreferencesScrollingViewController
        )
        let defaults = TestDefaults.make(for: self)
        defaults.set(true, forKey: PreferencesScrollingViewController.advancedExpandedDefaultsKey)
        scrolling.uiStateDefaults = defaults
        _ = scrolling.view

        let column = left(gestures.trackingSpeedRow, in: gestures.view)
        for row in [scrolling.speedRow!, scrolling.thumbWheelSpeedRow!, scrolling.glideTimeRow!, scrolling.smallestStepRow!] {
            XCTAssertEqual(left(row, in: scrolling.view), column, accuracy: 0.5, row.title)
        }
        XCTAssertEqual(GesturesPreferencesViewController.trackingSpeedValueWidth, PreferencesGroupedForm.sliderValueWidth)
        XCTAssertEqual(gestures.trackingSpeedRow.slider.frame.width, scrolling.speedRow.slider.frame.width, accuracy: 0.5)
    }

    func testAStoredTrackingSpeedOffTheTicksIsShownNotRewritten() {
        Options.shared.gesture.mode = .interactive
        Options.shared.gesture.trackingSpeed = 1.3
        let controller = makeController()
        let slider = controller.trackingSpeedSlider as! PreferencesSlider
        XCTAssertEqual(slider.doubleValue, 1.25, accuracy: 1e-9, "on the nearest tick")
        XCTAssertEqual(controller.trackingSpeedRow.valueText, speedText(1.3))

        controller.viewWillAppear()
        controller.reload()
        XCTAssertEqual(Options.shared.gesture.trackingSpeed, 1.3, "loading and showing it changes nothing")

        // An arrow key moves the knob one tick and writes that tick.
        XCTAssertTrue(slider.moveKnob(by: 1))
        XCTAssertEqual(Options.shared.gesture.trackingSpeed, 1.5, accuracy: 1e-9)
        XCTAssertEqual(controller.trackingSpeedRow.valueText, speedText(1.5))
        XCTAssertTrue(slider.moveKnob(by: -1))
        XCTAssertEqual(Options.shared.gesture.trackingSpeed, 1.25, accuracy: 1e-9)
    }

    // MARK: - Enabling rules

    func testTrackingSpeedIsEditableOnlyInFollowMode() {
        let controller = makeController()
        let controls = controller.controls!
        let row = controller.trackingSpeedRow!
        XCTAssertFalse(row.isEnabled, "one action per hold")
        XCTAssertFalse(controller.trackingSpeedSlider.isEnabled)
        XCTAssertEqual(row.explanation, text("gesture-tracking-speed-hint-discrete"))
        let height = controller.view.frame.height

        controls.modeControl.selectedSegment = 1
        send(controls.modeControl)
        XCTAssertTrue(row.isEnabled)
        XCTAssertTrue(controller.trackingSpeedSlider.isEnabled)
        XCTAssertEqual(row.explanation, text("gesture-tracking-speed-hint"))
        XCTAssertEqual(controller.view.frame.height, height)

        controls.modeControl.selectedSegment = 0
        send(controls.modeControl)
        XCTAssertFalse(controller.trackingSpeedSlider.isEnabled)
        // The stored speed is kept while it does not apply.
        XCTAssertEqual(Options.shared.gesture.trackingSpeed, MouseGestureSettings.defaultTrackingSpeed)
    }

    func testFollowModeHandsLeftAndRightToTheSwipe() {
        let controller = makeController()
        let controls = controller.controls!
        controls.modeControl.selectedSegment = 1
        send(controls.modeControl)

        for slot in [Slot.left, .right] {
            XCTAssertFalse(controls.actionPopUp(for: slot).isEnabled, slot.name)
            XCTAssertFalse(controller.directionRows[slot.rawValue].isEnabled, slot.name)
            XCTAssertEqual(title(of: controls.actionPopUp(for: slot)), "Desktop follows the hand", slot.name)
        }
        for slot in [Slot.up, .down, .click] {
            XCTAssertTrue(controls.actionPopUp(for: slot).isEnabled, slot.name)
            XCTAssertTrue(controller.directionRows[slot.rawValue].isEnabled, slot.name)
        }
        XCTAssertTrue(controls.invertToggle.isEnabled)
        XCTAssertTrue(controls.freezeToggle.isEnabled)
        // The stored actions survive for the other mode.
        XCTAssertEqual(Options.shared.gesture.leftAction, SystemShortcut.moveSpaceLeft.identifier)
        XCTAssertEqual(Options.shared.gesture.rightAction, SystemShortcut.moveSpaceRight.identifier)

        controls.modeControl.selectedSegment = 0
        send(controls.modeControl)
        XCTAssertTrue(controls.actionPopUp(for: .left).isEnabled)
        XCTAssertTrue(controller.directionRows[Slot.left.rawValue].isEnabled)
        XCTAssertEqual(title(of: controls.actionPopUp(for: .left)), SystemShortcut.moveSpaceLeft.localizedName)
    }

    func testFollowModeCannotBePickedWhereItIsUnavailable() {
        isInteractiveAvailable = false
        Options.shared.gesture.mode = .interactive
        let controller = makeController()
        let controls = controller.controls!

        XCTAssertEqual(controls.modeControl.selectedSegment, 0, "discrete is what runs, so it is shown")
        XCTAssertFalse(controls.modeControl.isEnabled(forSegment: 1))
        XCTAssertEqual(controller.modeRow.explanation, text("gesture-mode-interactive-unavailable"))
        XCTAssertTrue(controls.actionPopUp(for: .left).isEnabled)
        XCTAssertFalse(controller.trackingSpeedSlider.isEnabled)
        XCTAssertEqual(Options.shared.gesture.mode, .interactive, "the stored choice is kept")
        XCTAssertEqual(controller.previewView.scene.gesture.mode, .discrete, "the preview shows what runs")

        Options.shared.gesture.mode = .discrete
        controls.modeControl.selectedSegment = 1
        send(controls.modeControl)
        XCTAssertEqual(Options.shared.gesture.mode, .discrete)
        XCTAssertEqual(controls.modeControl.selectedSegment, 0)
    }

    func testModePresentationSaysWhenTrackingSpeedAppliesAndWhatTheModeDoes() {
        typealias Presentation = MouseGestureModePresentation
        XCTAssertFalse(Presentation.make(storedMode: .discrete, isInteractiveAvailable: true).isTrackingSpeedEditable)
        XCTAssertTrue(Presentation.make(storedMode: .interactive, isInteractiveAvailable: true).isTrackingSpeedEditable)
        XCTAssertFalse(Presentation.make(storedMode: .interactive, isInteractiveAvailable: false).isTrackingSpeedEditable)

        XCTAssertEqual(Presentation.make(storedMode: .discrete, isInteractiveAvailable: true).descriptionKey, "gesture-mode-discrete-description")
        XCTAssertEqual(Presentation.make(storedMode: .interactive, isInteractiveAvailable: true).descriptionKey, "gesture-mode-interactive-description")
        XCTAssertEqual(Presentation.make(storedMode: .interactive, isInteractiveAvailable: false).descriptionKey, "gesture-mode-interactive-unavailable")
        XCTAssertEqual(Presentation.make(storedMode: .discrete, isInteractiveAvailable: false).descriptionKey, "gesture-mode-interactive-unavailable")
        XCTAssertEqual(Set(Presentation.descriptionKeys).count, 3)
    }

    // MARK: - Up and Down follow the hand too

    private static let followsOnceElsewhere = "like on a trackpad. Other actions run once."

    /// "Follow the hand" with the switch on, as stored.
    private func followSettings(up: String? = nil, down: String? = nil) -> MouseGestureSettings {
        var settings = MouseGestureSettings.default
        settings.mode = .interactive
        settings.actionsFollowHand = true
        if let up { settings.upAction = up }
        if let down { settings.downAction = down }
        return settings
    }

    /// Under "Mode", in its box, always there: the switch "Up and Down follow the hand too
    /// (Experimental)". Only "Follow the hand" uses it: in "One action per hold" it is
    /// dimmed and says so, and still shows the stored choice. It writes its own value and
    /// nothing else.
    func testTheFollowSwitchSitsUnderModeAndWritesItsOwnSetting() throws {
        let controller = makeController()
        controller.view.layoutSubtreeIfNeeded()
        let row = try XCTUnwrap(controller.followRow)
        let followToggle = controller.controls.followToggle
        XCTAssertEqual(row.title, "Up and Down follow the hand too (Experimental)")
        XCTAssertTrue(row.accessory === followToggle)
        XCTAssertTrue(followToggle is NSSwitch)
        XCTAssertEqual(followToggle.identifier, MouseGestureSettingsControls.Identifier.followActions)
        XCTAssertEqual(followToggle.accessibilityLabel(), "Up and Down follow the hand too (Experimental)")
        XCTAssertTrue(row.superview === controller.modeRow.superview, "in the box of the mode")
        // (The root view is not flipped: lower on screen is a smaller y.)
        XCTAssertLessThan(frame(of: row, in: controller).maxY, frame(of: controller.modeRow, in: controller).minY + 0.5)
        XCTAssertGreaterThan(frame(of: row, in: controller).minY, frame(of: controller.directionRows[0], in: controller).maxY)

        XCTAssertFalse(row.isEnabled, "one action per hold")
        XCTAssertFalse(followToggle.isEnabled)
        XCTAssertFalse(MouseGestureSettingsControls.isOn(followToggle))
        XCTAssertEqual(row.explanation, "Only used in “Follow the hand”.")
        XCTAssertEqual(followToggle.accessibilityHelp(), "Only used in “Follow the hand”.", "VoiceOver gets the line")

        let mode = controller.controls.modeControl
        mode.selectedSegment = 1
        send(mode)
        XCTAssertTrue(row.isEnabled)
        XCTAssertTrue(followToggle.isEnabled)
        XCTAssertFalse(MouseGestureSettingsControls.isOn(followToggle), "off until it is turned on")
        XCTAssertTrue(row.explanation?.hasSuffix(Self.followsOnceElsewhere) == true, row.explanation ?? "nil")

        toggle(followToggle, on: true)
        var expected = MouseGestureSettings.default
        expected.mode = .interactive
        expected.actionsFollowHand = true
        XCTAssertEqual(Options.shared.gesture, expected, "nothing else moved")

        mode.selectedSegment = 0
        send(mode)
        XCTAssertTrue(Options.shared.gesture.actionsFollowHand, "the choice is kept for the mode that uses it")
        XCTAssertTrue(MouseGestureSettingsControls.isOn(followToggle), "and still shows")
        XCTAssertFalse(followToggle.isEnabled)
        XCTAssertEqual(row.explanation, "Only used in “Follow the hand”.")

        mode.selectedSegment = 1
        send(mode)
        toggle(followToggle, on: false)
        expected.actionsFollowHand = false
        XCTAssertEqual(Options.shared.gesture, expected)
    }

    /// The line under the switch names what opens with the hand on this Mac, from what can
    /// follow here: by the macOS, by the build (Apps) and by the Dock's own switches. It
    /// says the same whether the switch is on or off; in "One action per hold", and where
    /// "Follow the hand" cannot run, it says that the switch is not used.
    func testTheSwitchsLineNamesWhatOpensWithTheHandOnThisMac() {
        typealias Follow = MouseGestureFollowPresentation
        let interactive = MouseGestureModePresentation.make(storedMode: .interactive, isInteractiveAvailable: true)
        func hint(_ availability: DockFollowAvailability, _ settings: MouseGestureSettings? = nil) -> String {
            return Follow.make(settings: settings ?? followSettings(), mode: interactive, availability: availability).hint
        }
        func open(_ names: [String]) -> String {
            return "\(InterfaceList.joined(names)) open with your hand, like on a trackpad. Other actions run once."
        }
        // A released build on macOS 27; before macOS 27; the owner's own build on macOS 27.
        XCTAssertEqual(hint(follows(apps: false)), open(["Mission Control", "Show Desktop"]))
        XCTAssertEqual(open(["Mission Control", "Show Desktop"]), "Mission Control and Show Desktop open with your hand, like on a trackpad. Other actions run once.")
        for macOS in [14, 15, 26] {
            XCTAssertEqual(
                hint(follows(macOS: macOS)), "Mission Control opens with your hand, like on a trackpad. Other actions run once.", "macOS \(macOS)"
            )
        }
        XCTAssertEqual(hint(follows()), open(["Mission Control", "Apps", "Show Desktop"]))
        // The Dock's own switch for a gesture is off: that one is left out.
        var switches = DockGestureSwitches.allOn
        switches.missionControl = false
        XCTAssertEqual(hint(follows(apps: false, switches: switches)), "Show Desktop opens with your hand, like on a trackpad. Other actions run once.")
        XCTAssertEqual(hint(follows(switches: switches)), open(["Apps", "Show Desktop"]))
        switches = .allOn
        switches.showDesktop = false
        XCTAssertEqual(hint(follows(switches: switches)), "Mission Control opens with your hand, like on a trackpad. Other actions run once.")
        // Nothing can: the gestures are off, or macOS does not let Scrollio post events.
        let none = "Nothing can open with your hand on this Mac right now. Every action runs once."
        XCTAssertEqual(hint(follows(switches: DockGestureSwitches(missionControl: false, showDesktop: false, launchpad: false))), none)
        XCTAssertEqual(hint(follows(canPostEvents: false)), none)

        // What is stored changes nothing of it: the switch off, other actions.
        var off = followSettings(up: SystemShortcut.copy.identifier)
        off.actionsFollowHand = false
        XCTAssertEqual(hint(follows(apps: false), off), open(["Mission Control", "Show Desktop"]))

        // "One action per hold", and a "Follow the hand" that cannot run here.
        let notUsed = "Only used in “Follow the hand”."
        let discrete = MouseGestureModePresentation.make(storedMode: .discrete, isInteractiveAvailable: true)
        XCTAssertEqual(Follow.make(settings: .default, mode: discrete, availability: follows()).hint, notUsed)
        let unavailable = MouseGestureModePresentation.make(storedMode: .interactive, isInteractiveAvailable: false)
        let shown = Follow.make(settings: followSettings(), mode: unavailable, availability: follows())
        XCTAssertEqual(shown.hint, notUsed)
        XCTAssertFalse(shown.isEditable)
        XCTAssertTrue(shown.isOn, "the stored choice shows")
        XCTAssertEqual(shown.up, .plain, "nothing follows where the mode does not run")
        XCTAssertEqual(shown.down, .plain)
    }

    /// What a row says, purely: a sentence where its action opens with the hand; the
    /// reason where it could and does not on this Mac (by this macOS, or the Dock's own
    /// switch; no words where the reason is not the row's); nothing for any other action,
    /// with the switch off, and in "One action per hold". Apps is a plural, Launchpad is not.
    func testWhatARowSaysAboutFollowingTheHand() {
        typealias Follow = MouseGestureFollowPresentation
        let interactive = MouseGestureModePresentation.make(storedMode: .interactive, isInteractiveAvailable: true)
        func rows(_ settings: MouseGestureSettings, _ availability: DockFollowAvailability) -> [Follow.Row] {
            let shown = Follow.make(settings: settings, mode: interactive, availability: availability)
            XCTAssertEqual(shown.row(for: .up), shown.up)
            XCTAssertEqual(shown.row(for: .down), shown.down)
            XCTAssertEqual(shown.row(for: .left), .plain)
            XCTAssertEqual(shown.row(for: .right), .plain)
            return [shown.up, shown.down]
        }
        let notHere = Follow.Row.runsOnceHere("Runs once. It does not follow the hand on this version of macOS.")
        let gestureOff = Follow.Row.runsOnceHere("Runs once. Its trackpad gesture is off in System Settings.")
        let showDesktop = SystemShortcut.showDesktop.identifier

        // The defaults: Up is Mission Control, Down is Apps.
        XCTAssertEqual(rows(followSettings(), follows()), [.follows("Mission Control follows the hand"), .follows("Apps follow the hand")])
        // A released build: Apps is an action like any other there, on every macOS, so its
        // row says nothing (and never names macOS as the reason).
        XCTAssertEqual(rows(followSettings(), follows(apps: false)), [.follows("Mission Control follows the hand"), .plain])
        XCTAssertEqual(rows(followSettings(up: SystemShortcut.appExpose.identifier), follows(apps: false)), [.plain, .plain])
        for macOS in [14, 15, 26] {
            XCTAssertEqual(
                rows(followSettings(up: showDesktop), follows(macOS: macOS, apps: false)), [notHere, .plain],
                "macOS \(macOS): the sentence is Show Desktop's"
            )
        }
        XCTAssertEqual(
            rows(followSettings(up: showDesktop, down: SystemShortcut.missionControl.identifier), follows()),
            [.follows("Show Desktop follows the hand"), .follows("Mission Control follows the hand")]
        )
        XCTAssertEqual(rows(followSettings(up: showDesktop), follows(macOS: 26, apps: true)), [notHere, notHere])
        XCTAssertEqual(Follow.face(of: .apps, majorVersion: 15), "Launchpad follows the hand")
        XCTAssertEqual(Follow.face(of: .apps, majorVersion: 26), "Apps follow the hand")
        XCTAssertEqual(Follow.face(of: .missionControl, majorVersion: 14), "Mission Control follows the hand")
        XCTAssertEqual(Follow.face(of: .showDesktop, majorVersion: 27), "Show Desktop follows the hand")

        // The Dock's own switch (Apps goes by Show Desktop's since macOS 26).
        var switches = DockGestureSwitches.allOn
        switches.missionControl = false
        XCTAssertEqual(rows(followSettings(), follows(switches: switches)), [gestureOff, .follows("Apps follow the hand")])
        switches = .allOn
        switches.showDesktop = false
        XCTAssertEqual(rows(followSettings(up: showDesktop), follows(switches: switches)), [gestureOff, gestureOff])
        // macOS does not let Scrollio post events: nothing a row could say.
        XCTAssertEqual(rows(followSettings(), follows(canPostEvents: false)), [.plain, .plain])

        // Another action, a recorded key combination, no action.
        XCTAssertEqual(rows(followSettings(up: SystemShortcut.copy.identifier, down: "custom::15:1179648"), follows()), [.plain, .plain])
        XCTAssertEqual(rows(followSettings(up: "", down: SystemShortcut.moveSpaceLeft.identifier), follows()), [.plain, .plain])
        // The switch off; "One action per hold".
        var off = followSettings()
        off.actionsFollowHand = false
        XCTAssertEqual(rows(off, follows()), [.plain, .plain])
        let discrete = MouseGestureModePresentation.make(storedMode: .discrete, isInteractiveAvailable: true)
        var once = followSettings()
        once.mode = .discrete
        let shown = Follow.make(settings: once, mode: discrete, availability: follows())
        XCTAssertEqual([shown.up, shown.down], [.plain, .plain])
        XCTAssertEqual(Follow.Row.plain.face, nil)
        XCTAssertEqual(notHere.face, nil)
        XCTAssertEqual(notHere.note, "Runs once. It does not follow the hand on this version of macOS.")
        XCTAssertEqual(Follow.Row.follows("x").note, nil)
    }

    /// With the switch on, an Up or Down row whose action opens with the hand says so in
    /// place of the action, without its picture, as Left and Right do; it stays a pull-down
    /// with its menu, the tick on the action. Click and every other action stay plain.
    func testRowsThatFollowSayItInPlaceOfTheirAction() throws {
        Options.shared.gesture = followSettings()
        let controller = makeController()
        let controls = controller.controls!
        let up = controls.actionPopUp(for: .up)
        let down = controls.actionPopUp(for: .down)
        let itemCount = up.menu?.items.count

        XCTAssertEqual(title(of: up), "Mission Control follows the hand")
        XCTAssertEqual(title(of: down), "Apps follow the hand")
        for popup in [up, down] {
            XCTAssertNil(popup.menu?.items.first?.image, "a sentence has no picture")
            XCTAssertNil(popup.menu?.items.first?.attributedTitle)
            XCTAssertTrue(popup.isEnabled, "still a choice")
            XCTAssertNil(popup.toolTip)
        }
        XCTAssertTrue(controller.directionRows[Slot.up.rawValue].isEnabled)
        XCTAssertEqual(up.accessibilityLabel(), "Up", "VoiceOver: Up, Mission Control follows the hand")
        XCTAssertEqual(up.shownActionItem?.item.title, SystemShortcut.missionControl.localizedName, "the tick is on the action")
        XCTAssertEqual(down.shownActionItem?.item.title, SystemShortcut.appExpose.localizedName)
        XCTAssertEqual(Options.shared.gesture.upAction, SystemShortcut.missionControl.identifier, "what is stored is the action")
        // Left and Right are the desktops', as before; Click runs once.
        XCTAssertEqual(title(of: controls.actionPopUp(for: .left)), "Desktop follows the hand")
        XCTAssertFalse(controls.actionPopUp(for: .left).isEnabled)
        XCTAssertEqual(title(of: controls.actionPopUp(for: .click)), SystemShortcut.missionControl.localizedName)
        XCTAssertNotNil(controls.actionPopUp(for: .click).menu?.items.first?.image)

        // Another action on Up runs once: the plain face; Show Desktop follows again.
        choose(SystemShortcut.copy.identifier, in: up)
        XCTAssertEqual(title(of: up), SystemShortcut.copy.localizedName)
        XCTAssertNotNil(up.menu?.items.first?.image)
        XCTAssertEqual(up.menu?.items.count, itemCount, "the same menu")
        choose(SystemShortcut.showDesktop.identifier, in: up)
        XCTAssertEqual(Options.shared.gesture.upAction, SystemShortcut.showDesktop.identifier)
        XCTAssertEqual(title(of: up), "Show Desktop follows the hand")
        XCTAssertNil(up.menu?.items.first?.image)

        // The switch off, and "One action per hold": the actions as they are.
        toggle(controls.followToggle, on: false)
        XCTAssertEqual(title(of: up), SystemShortcut.showDesktop.localizedName)
        XCTAssertEqual(title(of: down), SystemShortcut.appExpose.localizedName)
        XCTAssertNotNil(down.menu?.items.first?.image)
        toggle(controls.followToggle, on: true)
        XCTAssertEqual(title(of: down), "Apps follow the hand")
        controls.modeControl.selectedSegment = 0
        send(controls.modeControl)
        XCTAssertEqual(title(of: up), SystemShortcut.showDesktop.localizedName)
        XCTAssertEqual(title(of: down), SystemShortcut.appExpose.localizedName)
    }

    /// The sentence is the pull-down's own: it is still there after the menu opened and
    /// closed without a choice, after the pull-down refreshed itself, and after a recording
    /// that was given up (while it waits for a key the title asks for one).
    func testARowThatFollowsKeepsItsSentenceThroughThePullDownsOwnRefreshes() throws {
        Options.shared.gesture = followSettings()
        let controller = makeController()
        let up = controller.controls.actionPopUp(for: .up)
        let menu = try XCTUnwrap(up.menu)
        XCTAssertEqual(up.face, "Mission Control follows the hand")

        up.menuWillOpen(menu)
        XCTAssertEqual(up.shownActionItem?.item.state, .on)
        up.menuDidClose(menu)
        XCTAssertEqual(title(of: up), "Mission Control follows the hand")
        up.refreshActionDisplay()
        XCTAssertEqual(title(of: up), "Mission Control follows the hand")
        XCTAssertNil(up.menu?.items.first?.image)

        up.beginCustomShortcutSelection(startRecorder: false)
        XCTAssertEqual(title(of: up), text("custom-recording-prompt"))
        up.cancelShortcutRecording()
        XCTAssertEqual(title(of: up), "Mission Control follows the hand")
    }

    /// A row whose action could open with the hand, but does not on this Mac while the
    /// switch is on, shows the action as ever and says why in its tooltip and as VoiceOver's
    /// help: this macOS, or the Dock's own switch for the trackpad gesture. Nothing where
    /// the reason is not the row's, with the switch off, and on a row that follows.
    func testARowThatCannotFollowHereSaysWhyInItsTooltipAndHelp() {
        let notHere = "Runs once. It does not follow the hand on this version of macOS."
        let gestureOff = "Runs once. Its trackpad gesture is off in System Settings."
        Options.shared.gesture = followSettings(down: SystemShortcut.showDesktop.identifier)
        follow = follows(macOS: 26)
        let controller = makeController()
        let controls = controller.controls!
        let up = controls.actionPopUp(for: .up)
        let down = controls.actionPopUp(for: .down)

        XCTAssertEqual(title(of: up), "Mission Control follows the hand")
        XCTAssertNil(up.toolTip)
        XCTAssertNil(up.accessibilityHelp())
        XCTAssertEqual(title(of: down), SystemShortcut.showDesktop.localizedName, "the plain face")
        XCTAssertNotNil(down.menu?.items.first?.image)
        XCTAssertTrue(down.isEnabled)
        XCTAssertEqual(down.toolTip, notHere)
        XCTAssertEqual(down.accessibilityHelp(), notHere)
        XCTAssertEqual(down.accessibilityLabel(), "Down")
        XCTAssertNil(controls.actionPopUp(for: .click).toolTip, "Click never follows and never says so")

        // The Dock's switch for Mission Control is off: Up runs once, Down follows.
        var switches = DockGestureSwitches.allOn
        switches.missionControl = false
        follow = follows(switches: switches)
        controller.reload()
        XCTAssertEqual(title(of: up), SystemShortcut.missionControl.localizedName)
        XCTAssertEqual(up.toolTip, gestureOff)
        XCTAssertEqual(up.accessibilityHelp(), gestureOff)
        XCTAssertEqual(title(of: down), "Show Desktop follows the hand")
        XCTAssertNil(down.toolTip)
        XCTAssertNil(down.accessibilityHelp(), "the help goes with the reason")

        // macOS does not let Scrollio post events: plain, without words.
        follow = follows(canPostEvents: false)
        controller.reload()
        for popup in [up, down] {
            XCTAssertNil(popup.face)
            XCTAssertNil(popup.toolTip)
            XCTAssertNil(popup.accessibilityHelp())
        }

        // The switch off: nothing asks, so nothing is said.
        follow = follows(macOS: 26)
        controller.reload()
        XCTAssertEqual(down.toolTip, notHere)
        toggle(controls.followToggle, on: false)
        XCTAssertNil(down.toolTip)
        XCTAssertNil(down.accessibilityHelp())
        XCTAssertEqual(title(of: up), SystemShortcut.missionControl.localizedName)

        // A released build, the default actions (Down = Apps): no macOS makes Apps follow
        // there, so the row is the action as ever and blames nothing.
        Options.shared.gesture = followSettings()
        for macOS in [27, 26, 15, 14] {
            follow = follows(macOS: macOS, apps: false)
            controller.reload()
            XCTAssertEqual(title(of: up), "Mission Control follows the hand", "macOS \(macOS)")
            XCTAssertEqual(title(of: down), SystemShortcut.appExpose.localizedName, "macOS \(macOS)")
            XCTAssertNotNil(down.menu?.items.first?.image, "macOS \(macOS)")
            XCTAssertNil(down.face, "macOS \(macOS)")
            XCTAssertNil(down.toolTip, "macOS \(macOS)")
            XCTAssertNil(down.accessibilityHelp(), "macOS \(macOS)")
        }
    }

    /// The Dock's own switches were read again and changed (System Settings › Trackpad ›
    /// More Gestures): the pane on screen says at once what opens with the hand now.
    func testThePaneFollowsTheDocksSwitchesWhenTheyChange() {
        Options.shared.gesture = followSettings()
        follow = follows(apps: false)
        let controller = makeController()
        let up = controller.controls.actionPopUp(for: .up)
        XCTAssertEqual(title(of: up), "Mission Control follows the hand")
        XCTAssertEqual(controller.followRow.explanation, "Mission Control and Show Desktop open with your hand, like on a trackpad. Other actions run once.")

        var switches = DockGestureSwitches.allOn
        switches.missionControl = false
        follow = follows(apps: false, switches: switches)
        NotificationCenter.default.post(name: DockGestureSwitches.didChangeNotification, object: nil)

        XCTAssertEqual(title(of: up), SystemShortcut.missionControl.localizedName)
        XCTAssertEqual(up.toolTip, "Runs once. Its trackpad gesture is off in System Settings.")
        XCTAssertEqual(controller.followRow.explanation, "Show Desktop opens with your hand, like on a trackpad. Other actions run once.")
    }

    /// The pane is as tall whatever the mode, the switch, the actions and what can follow
    /// on this Mac: nothing under "Mode" moves.
    func testThePaneKeepsItsHeightWhateverTheModeTheSwitchAndTheDockSay() {
        var switches = DockGestureSwitches.allOn
        switches.missionControl = false
        let macs = [follows(), follows(apps: false), follows(macOS: 26), follows(macOS: 15, switches: switches), follows(canPostEvents: false)]
        var heights: [String: CGFloat] = [:]
        for (index, mac) in macs.enumerated() {
            follow = mac
            Options.shared.gesture = .default
            let controller = makeController()
            let controls = controller.controls!
            heights["mac \(index), one action per hold"] = controller.view.frame.height
            controls.modeControl.selectedSegment = 1
            send(controls.modeControl)
            heights["mac \(index), follow the hand"] = controller.view.frame.height
            toggle(controls.followToggle, on: true)
            heights["mac \(index), the switch on"] = controller.view.frame.height
            choose(SystemShortcut.showDesktop.identifier, in: controls.actionPopUp(for: .up))
            choose(SystemShortcut.copy.identifier, in: controls.actionPopUp(for: .down))
            heights["mac \(index), other actions"] = controller.view.frame.height
            controls.modeControl.selectedSegment = 0
            send(controls.modeControl)
            heights["mac \(index), back in one action per hold"] = controller.view.frame.height
            XCTAssertEqual(controller.view.frame.size, controller.view.fittingSize, "mac \(index)")
        }
        XCTAssertEqual(Set(heights.values).count, 1, "\(heights.sorted { $0.key < $1.key })")
    }

    /// Every line the switch's row can show takes two lines at most where it stands, and
    /// the row keeps room for each of them.
    func testEveryLineOfTheSwitchFitsTwoLines() throws {
        let controller = makeController()
        controller.view.layoutSubtreeIfNeeded()
        let row = try XCTUnwrap(controller.followRow)
        let measure = NSTextField(wrappingLabelWithString: "")
        measure.font = row.explanationLabel.font
        measure.preferredMaxLayoutWidth = row.titleColumnWidth
        func height(_ text: String) -> CGFloat {
            measure.stringValue = text
            return measure.fittingSize.height
        }
        let twoLines = height("One\nTwo")
        XCTAssertGreaterThan(row.titleColumnWidth, 300)
        var lines: Set<String> = []
        for macOS in [14, 15, 26, 27] {
            lines.formUnion(MouseGestureFollowPresentation.hints(majorVersion: macOS))
        }
        XCTAssertGreaterThanOrEqual(lines.count, 9)
        XCTAssertTrue(lines.contains("Only used in “Follow the hand”."))
        XCTAssertTrue(lines.contains("Nothing can open with your hand on this Mac right now. Every action runs once."))
        XCTAssertTrue(lines.contains { $0.hasPrefix(InterfaceList.joined(["Mission Control", "Launchpad", "Show Desktop"])) })
        XCTAssertTrue(lines.contains { $0.hasPrefix(InterfaceList.joined(["Mission Control", "Apps", "Show Desktop"])) })
        for line in lines {
            XCTAssertLessThanOrEqual(height(line), twoLines + 0.5, line)
        }
        XCTAssertEqual(Set(row.reservedExplanations), Set(MouseGestureFollowPresentation.hints(majorVersion: 27)), "the Mac the test describes")
        XCTAssertGreaterThanOrEqual(row.explanationLabel.frame.height, twoLines - 0.5, "room for two lines, also for one")
        // The switch's title is whole.
        XCTAssertGreaterThanOrEqual(row.titleLabel.frame.width + 0.5, row.titleLabel.intrinsicContentSize.width)
    }

    /// The pull-downs of the directions are wide enough for every sentence a row can show
    /// in place of its action: none is cut. Buttons and the Shortcut Ring keep their width.
    func testEverySentenceOfARowFitsItsPullDown() throws {
        Options.shared.gesture = followSettings()
        let controller = makeController()
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(GesturesPreferencesViewController.popUpWidth, 264)
        XCTAssertEqual(ButtonActionPullDown.width(for: .gesture(showsLogiActions: false)), 264)
        XCTAssertEqual(ButtonActionPullDown.width(for: .gesture(showsLogiActions: true)), 264)
        XCTAssertEqual(ButtonActionPullDown.width(for: .binding), 240)
        XCTAssertEqual(ButtonActionPullDown.width(for: .ringPlace), 240)
        var sentences = [MouseGestureSettingsControls.followHorizontalValue]
        for target in DockFollowTarget.allCases {
            for macOS in [15, 26, 27] {
                sentences.append(MouseGestureFollowPresentation.face(of: target, majorVersion: macOS))
            }
        }
        XCTAssertTrue(sentences.contains("Mission Control follows the hand"))
        for slot in Slot.allCases {
            let popup = controller.controls.actionPopUp(for: slot)
            XCTAssertEqual(popup.frame.width, 264, accuracy: 0.5, slot.name)
            let cell = try XCTUnwrap(popup.cell as? NSPopUpButtonCell)
            let font = try XCTUnwrap(popup.font)
            // The rectangle of a title is as wide as its text while the text has room, and
            // as wide as the room when it has not (the text is then cut with "…").
            func isWhole(_ sentence: String) -> Bool {
                popup.face = sentence
                let width = (sentence as NSString).size(withAttributes: [.font: font]).width
                return cell.titleRect(forBounds: popup.bounds).width + 1 >= width
            }
            for sentence in sentences {
                XCTAssertTrue(isWhole(sentence), "\(slot.name): \(sentence)")
            }
            XCTAssertFalse(isWhole("Mission Control follows the hand, and so does every other thing"), "the measure can tell")
        }
        controller.reload()
        controller.view.layoutSubtreeIfNeeded()
        // The titles of the rows keep their room beside the wider pull-downs.
        for row in controller.directionRows {
            XCTAssertGreaterThanOrEqual(row.titleLabel.frame.width + 0.5, row.titleLabel.intrinsicContentSize.width, row.title)
        }
    }

    /// "Swipe speed" is about everything that moves with the hand, the desktops and what
    /// Up and Down open.
    func testSwipeSpeedSaysWhatMovesWithTheHand() {
        let controller = makeController()
        let row = controller.trackingSpeedRow!
        XCTAssertEqual(row.title, "Swipe speed")
        XCTAssertEqual(row.explanation, "Only used in “Follow the hand”.")
        controller.controls.modeControl.selectedSegment = 1
        send(controller.controls.modeControl)
        XCTAssertEqual(row.explanation, "How far the screen moves with your hand.")
        XCTAssertEqual(controller.modeRow.explanation, "Moving sideways slides the desktops with your hand, like a trackpad swipe.", "the mode's own line is as it was")
    }

    /// "Reset to Defaults" turns the switch off with the rest, and Undo brings it back.
    func testResetToDefaultsTurnsTheFollowSwitchOffAndUndoBringsItBack() {
        var settings = MouseGestureSettings.default
        settings.actionsFollowHand = true
        Options.shared.gesture = settings
        let (controller, undo) = makeControllerWithUndo()
        let button = controller.resetToDefaultsButton
        XCTAssertTrue(button.isEnabled, "the switch alone differs from the defaults")

        click(button, undo)
        XCTAssertEqual(Options.shared.gesture, .default)
        XCTAssertFalse(MouseGestureSettingsControls.isOn(controller.controls.followToggle))
        undo.undo()
        XCTAssertTrue(Options.shared.gesture.actionsFollowHand)
        XCTAssertTrue(MouseGestureSettingsControls.isOn(controller.controls.followToggle))
    }

    // MARK: - The gesture button

    func testTheGestureButtonRowNamesTheButtonsOrSaysThereIsNone() {
        summary = MouseGestureBindingSummary(hasGestureButton: false, hasLogitechGestureButton: false)
        let controller = makeController()
        let row = controller.gestureButtonRow!
        XCTAssertEqual(row.title, "Button to hold")
        XCTAssertEqual(row.explanation, "No button yet. Set one up to use gestures.")
        XCTAssertTrue(row.accessory === controller.gestureButtonButton)
        XCTAssertEqual(controller.gestureButtonButton.shownTitle, "Choose")
        XCTAssertTrue(controller.gestureButtonButton.pullsDown, "a pull-down")
        XCTAssertEqual(controller.gestureButtonButton.identifier, GesturesPreferencesViewController.Identifier.gestureButton)
        XCTAssertEqual(controller.gestureButtonButton.accessibilityLabel(), "Button to hold", "named by the row")
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(frame(of: row, in: controller).minY, frame(of: controller.modeRow, in: controller).maxY - 0.5, "first, above the mode")
        XCTAssertTrue(row.superview === controller.modeRow.superview, "in the first box")

        summary = MouseGestureBindingSummary(hasGestureButton: true, hasLogitechGestureButton: true, buttonTitles: ["Back button", "Gesture button"])
        controller.reload()
        XCTAssertFalse(row.isHidden, "always shown")
        XCTAssertEqual(row.explanation, "Back button and Gesture button.")
        XCTAssertEqual(controller.gestureButtonButton.shownTitle, "Multiple", "two buttons: which one stays is chosen in Buttons")
        XCTAssertEqual(controller.view.frame.size, controller.view.fittingSize)
        // The old line under the boxes is gone.
        let texts = controller.view.allSubviewsForTests.compactMap { ($0 as? NSTextField)?.stringValue }
        XCTAssertFalse(texts.contains("Choose the gesture button under Buttons."))
    }

    // MARK: - Folded while no button runs the gestures

    private func rect(_ view: NSView, in controller: NSViewController) -> NSRect {
        return controller.view.convert(view.alignmentRect(forFrame: view.frame), from: view.superview)
    }

    /// No button runs Gesture Navigation: under the first box each section is folded to its
    /// title, the muted lines with it; the preview, the button to hold, the mode and
    /// "Reset to Defaults" stay. With a Logitech mouse its section is one more title.
    func testWithNoButtonEverythingUnderTheFirstBoxIsFoldedUnderItsTitles() throws {
        summary = MouseGestureBindingSummary(hasGestureButton: false, hasLogitechGestureButton: false)
        for connected in [MouseGestureDeviceSupport.none, MouseGestureDeviceSupport(deviceTracking: true, haptics: true, hapticsOffOnMouse: true)] {
            support = connected
            let savedMouse = Options.shared.logiMouse
            defer { Options.shared.logiMouse = savedMouse }
            Options.shared.logiMouse.hapticsOn = false
            let controller = makeController()
            controller.view.layoutSubtreeIfNeeded()

            XCTAssertEqual(controller.foldingSections.map(\.title), ["Directions", "Behavior", "Logitech mouse"])
            for section in controller.foldingSections {
                XCTAssertTrue(section.isCollapsible, section.title)
                XCTAssertFalse(section.showsBody, section.title)
                XCTAssertTrue(section.titleLabel.isHidden, section.title)
                XCTAssertEqual(section.disclosure.label.stringValue, section.title)
            }
            let folded: [NSView] = controller.directionRows + [
                controller.directionsHintLabel, controller.invertRow, controller.freezeRow, controller.trackingSpeedRow,
                controller.deviceTrackingRow, controller.hapticsRow,
            ]
            for view in folded {
                XCTAssertTrue(view.isHiddenOrHasHiddenAncestor)
            }
            XCTAssertTrue(controller.hapticsOffNote.isHidden, "the muted line folds with its box")
            XCTAssertEqual(controller.logitechSection.isHidden, connected == .none, "a Logitech title only with such a mouse")
            for view in [controller.previewView!, controller.gestureButtonRow!, controller.modeRow!, controller.footer!] as [NSView] {
                XCTAssertFalse(view.isHiddenOrHasHiddenAncestor)
            }
            // The titles a section's room apart, the footer as far under the last.
            let titles = controller.foldingSections.filter { !$0.isHidden }.map { rect($0, in: controller) }
            for (upper, lower) in zip(titles, titles.dropFirst()) {
                XCTAssertEqual(upper.minY - lower.maxY, PreferencesGroupedForm.sectionSpacing, accuracy: 0.5)
            }
            XCTAssertEqual(try XCTUnwrap(titles.last).minY - rect(controller.footer, in: controller).maxY,
                           PreferencesGroupedForm.sectionSpacing, accuracy: 0.5)
            XCTAssertEqual(controller.view.frame.size, controller.view.fittingSize)
            XCTAssertFalse(controller.view.hasAmbiguousLayout)
        }
    }

    /// Each title opens its own section, with its muted line, and what opens is edited as
    /// ever; the others stay folded.
    func testEachTitleOpensItsSectionWithItsMutedLineAndItCanBeEdited() throws {
        summary = MouseGestureBindingSummary(hasGestureButton: false, hasLogitechGestureButton: false)
        let controller = makeController()
        controller.foldingSections.forEach { $0.prefersReducedMotion = { true } }
        let folded = controller.view.frame.height

        // No Logitech mouse: "Behavior" opens as the last box, the footer a section's room
        // under it (no line asks for a Logitech mouse).
        XCTAssertTrue(controller.behaviourSection.disclosure.accessibilityPerformPress())
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertTrue(controller.behaviourSection.showsBody)
        XCTAssertFalse(controller.directionsSection.showsBody)
        XCTAssertEqual(rect(controller.behaviourSection, in: controller).minY - rect(controller.footer, in: controller).maxY,
                       PreferencesGroupedForm.sectionSpacing, accuracy: 0.5)
        XCTAssertGreaterThan(controller.view.frame.height, folded)
        XCTAssertEqual(controller.view.frame.size, controller.view.fittingSize)
        toggle(controller.controls.invertToggle, on: !Options.shared.gesture.invertHorizontal)
        XCTAssertNotEqual(Options.shared.gesture.invertHorizontal, MouseGestureSettings.default.invertHorizontal)

        controller.directionsSection.toggle()
        XCTAssertTrue(controller.directionsSection.showsBody)
        XCTAssertFalse(controller.directionRows[0].isHiddenOrHasHiddenAncestor)
        choose(SystemShortcut.copy.identifier, in: controller.controls.actionPopUp(for: .up))
        XCTAssertEqual(Options.shared.gesture.upAction, SystemShortcut.copy.identifier)
        XCTAssertTrue(controller.directionsSection.showsBody, "editing keeps it open")

        // A Logitech mouse with its haptics off under Mouse: its line opens with its box.
        let savedMouse = Options.shared.logiMouse
        defer { Options.shared.logiMouse = savedMouse }
        Options.shared.logiMouse.hapticsOn = false
        support = MouseGestureDeviceSupport(deviceTracking: true, haptics: true, hapticsOffOnMouse: true)
        controller.reload()
        XCTAssertTrue(controller.hapticsOffNote.isHidden, "folded with its box")
        controller.logitechSection.toggle()
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertFalse(controller.hapticsOffNote.isHidden)
        XCTAssertEqual(rect(controller.logitechSection, in: controller).minY - rect(controller.hapticsOffNote, in: controller).maxY,
                       PreferencesGroupedForm.noteSpacing, accuracy: 0.5)
        XCTAssertEqual(controller.view.frame.size, controller.view.fittingSize)

        controller.logitechSection.toggle()
        XCTAssertTrue(controller.hapticsOffNote.isHidden)
        XCTAssertEqual(controller.view.frame.size, controller.view.fittingSize)
    }

    /// Once a button runs the gestures, in Buttons or only in an app, the sections show by
    /// themselves under plain titles; without one again they are folded.
    func testOnceAButtonRunsTheGesturesTheSectionsShowUnderPlainTitles() {
        summary = MouseGestureBindingSummary(hasGestureButton: false, hasLogitechGestureButton: false)
        let controller = makeController()
        let folded = controller.view.frame.height
        let notes = ApplicationTriggers(applicationNames: ["Notes"], triggerTitles: ["Back button"], path: "/System/Applications/Notes.app")
        for runs in [
            MouseGestureBindingSummary(hasGestureButton: true, hasLogitechGestureButton: false, buttonTitles: ["Back button"]),
            MouseGestureBindingSummary(hasGestureButton: false, hasLogitechGestureButton: false, onlyInApps: notes),
        ] {
            summary = runs
            controller.reload()
            for section in controller.foldingSections {
                XCTAssertFalse(section.isCollapsible, section.title)
                XCTAssertTrue(section.showsBody, section.title)
                XCTAssertFalse(section.titleLabel.isHidden, section.title)
                XCTAssertTrue(section.disclosure.isHidden, section.title)
            }
            XCTAssertFalse(controller.directionRows[0].isHiddenOrHasHiddenAncestor)
            XCTAssertFalse(controller.invertRow.isHiddenOrHasHiddenAncestor)
            XCTAssertTrue(controller.logitechSection.isHidden, "no Logitech mouse: no box, and no line about one")
            XCTAssertEqual(controller.view.frame.size, controller.view.fittingSize)
        }

        summary = MouseGestureBindingSummary(hasGestureButton: false, hasLogitechGestureButton: false)
        controller.reload()
        XCTAssertTrue(controller.foldingSections.allSatisfy { $0.isCollapsible && !$0.showsBody })
        XCTAssertEqual(controller.view.frame.height, folded, accuracy: 0.5)
    }

    /// Edit › Undo or Redo of a change made elsewhere (an app's Buttons part, the Buttons
    /// pane) can change which button runs the gestures while the pane shows: the pane
    /// shows it at once, and its button does what it says.
    func testAnUndoThatChangesWhichButtonRunsTheGesturesShowsOnThePane() {
        let none = MouseGestureBindingSummary(hasGestureButton: false, hasLogitechGestureButton: false)
        summary = none
        let controller = makeController()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 900), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        addTeardownBlock { window.close() }
        XCTAssertEqual(controller.gestureButtonRow.explanation, "No button yet. Set one up to use gestures.")

        let notes = ApplicationTriggers(applicationNames: ["Notes"], triggerTitles: ["Back button"], path: "/System/Applications/Notes.app")
        let runs = MouseGestureBindingSummary(hasGestureButton: false, hasLogitechGestureButton: false, onlyInApps: notes)
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        undo.registerUndo(withTarget: self) { [weak undo] test in
            test.summary = runs
            undo?.registerUndo(withTarget: test) { $0.summary = none }
        }
        undo.endUndoGrouping()
        undo.undo()
        XCTAssertEqual(controller.gestureButtonRow.explanation, "Only in Notes: Back button.", "shown at once")
        XCTAssertEqual(controller.gestureButtonButton.shownTitle, "Choose", "nothing of Buttons runs them")
        XCTAssertTrue(controller.foldingSections.allSatisfy { !$0.isCollapsible })
        undo.redo()
        XCTAssertEqual(controller.gestureButtonRow.explanation, "No button yet. Set one up to use gestures.")
        XCTAssertTrue(controller.foldingSections.allSatisfy { $0.isCollapsible })

        // "Show in Buttons" goes where the row says, also when the bindings changed unseen.
        var opened = 0
        controller.openButtonsPane = { opened += 1 }
        controller.openApplicationButtons = { _ in XCTFail("the row says that no button runs them") }
        summary = runs
        XCTAssertTrue(controller.gestureButtonButton.chooseItemForTests(TriggerChooser.Identifier.showInButtons))
        XCTAssertEqual(opened, 1)
    }

    func testTheGestureButtonSummaryNamesEachButtonOnce() {
        func binding(_ code: UInt16, modifiers: UInt = 0) -> ButtonBinding {
            return ButtonBinding(
                triggerEvent: RecordedEvent(type: .mouse, code: code, modifiers: modifiers, deviceFilter: nil),
                systemShortcutName: SystemShortcut.mouseGestureNavigation.identifier
            )
        }
        let option = UInt(CGEventFlags.maskAlternate.rawValue)
        let summary = MouseGestureBindingSummary(
            bindings: [binding(3), binding(4, modifiers: option), binding(3)],
            isLogitechCode: { $0 >= 1000 }
        )
        XCTAssertEqual(summary.buttonTitles, ["Back button", "⌥ Forward button"])
        XCTAssertEqual(summary.gestureButtonExplanation, "Back button and ⌥ Forward button.")
        // An MX Master's own gesture button under the row's title "Button to hold": named once.
        XCTAssertEqual(MouseGestureBindingSummary(hasGestureButton: true, hasLogitechGestureButton: true, buttonTitles: ["Gesture button"])
            .gestureButtonExplanation, "Gesture button.")
        XCTAssertEqual(MouseGestureBindingSummary(bindings: [], isLogitechCode: { _ in false }).gestureButtonExplanation,
                       "No button yet. Set one up to use gestures.")
    }

    func testShowInButtonsLeadsToTheButtonsPaneWithOrWithoutAButton() {
        var opened = 0
        summary = MouseGestureBindingSummary(hasGestureButton: false, hasLogitechGestureButton: false)
        let controller = makeController()
        controller.openButtonsPane = { opened += 1 }
        XCTAssertTrue(controller.gestureButtonButton.chooseItemForTests(TriggerChooser.Identifier.showInButtons))
        XCTAssertEqual(opened, 1)

        summary = MouseGestureBindingSummary(hasGestureButton: true, hasLogitechGestureButton: false, buttonTitles: ["Back button"])
        controller.reload()
        XCTAssertTrue(controller.gestureButtonButton.chooseItemForTests(TriggerChooser.Identifier.showInButtons))
        XCTAssertEqual(opened, 2)
    }

    /// "Show in Buttons" in the window: the Buttons pane opens with the row of the button
    /// that runs Gesture Navigation selected and lit on the card, and nothing is recorded or
    /// changed.
    func testShowInButtonsInTheWindowSelectsTheGestureButtonsRowInButtons() throws {
        let savedBindings = Options.shared.buttons.binding
        defer { Options.shared.buttons.binding = savedBindings }
        func binding(_ code: UInt16, _ shortcut: String) -> ButtonBinding {
            return ButtonBinding(
                triggerEvent: RecordedEvent(type: .mouse, code: code, modifiers: 0, deviceFilter: nil),
                systemShortcutName: shortcut, isEnabled: true
            )
        }
        let copy = binding(4, SystemShortcut.copy.identifier)
        let gesture = binding(3, SystemShortcut.mouseGestureNavigation.identifier)
        Options.shared.buttons.binding = [copy, gesture]

        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesSplitViewController.self))
        let windowController = try XCTUnwrap(
            storyboard.instantiateController(withIdentifier: WINDOW_IDENTIFIER.preferencesWindowController) as? NSWindowController
        )
        defer { windowController.close() }
        let preferences = try XCTUnwrap(windowController.contentViewController as? PreferencesSplitViewController)
        _ = preferences.view
        let gestures = try XCTUnwrap(preferences.controller(for: GesturesPreferencesViewController.tabIdentifier) as? GesturesPreferencesViewController)
        gestures.deviceSource = MouseGestureDeviceSource(support: { .none }, refresh: {})
        gestures.bindingSummary = { MouseGestureBindingSummary(hasGestureButton: true, hasLogitechGestureButton: false, buttonTitles: ["Back button"]) }
        let buttons = try XCTUnwrap(preferences.controller(for: PANEL_IDENTIFIER.buttons) as? PreferencesButtonsViewController)
        buttons.deviceSource = ButtonsDeviceSource(captureStatus: { _ in .normal }, deviceName: { nil }, isBusy: { false }, refresh: {}, warnBluetoothButton: { _ in })
        var recordings = 0
        buttons.startRecording = { _ in recordings += 1 }
        var openedMenus = 0
        buttons.openActionMenu = { _ in openedMenus += 1 }
        XCTAssertTrue(preferences.selectPane(withIdentifier: GesturesPreferencesViewController.tabIdentifier))
        XCTAssertEqual(gestures.gestureButtonButton.shownTitle, "Back button")

        XCTAssertTrue(gestures.gestureButtonButton.chooseItemForTests(TriggerChooser.Identifier.showInButtons))

        XCTAssertEqual(preferences.selectedPaneIdentifier, PANEL_IDENTIFIER.buttons)
        XCTAssertEqual(buttons.list.selectedID, buttons.rowID(forBinding: gesture.id), "the gesture button's row, not the first")
        XCTAssertEqual(buttons.headerView.content.title, "Back button")
        XCTAssertEqual(buttons.headerView.content.subtitle, "Gesture Navigation")
        XCTAssertEqual(buttons.headerView.content.part, .back, "lit on the card")
        XCTAssertEqual(recordings, 0, "nothing is recorded")
        XCTAssertEqual(openedMenus, 0, "no menu opens by itself")
        XCTAssertEqual(Options.shared.buttons.binding, [copy, gesture], "nothing is changed")
    }

    /// "Record a Button…" in the window: the recorder opens at the pull-down, in the pane;
    /// the button pressed gets Gesture Navigation in Buttons, the pane shows it at once, and
    /// the Buttons pane shows it when it opens. Edit › Undo takes it away again.
    func testRecordAButtonInTheWindowRecordsInPlaceAndTheButtonGetsGestureNavigation() throws {
        let savedBindings = Options.shared.buttons.binding
        defer { Options.shared.buttons.binding = savedBindings }
        Options.shared.buttons.binding = []

        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesSplitViewController.self))
        let windowController = try XCTUnwrap(
            storyboard.instantiateController(withIdentifier: WINDOW_IDENTIFIER.preferencesWindowController) as? NSWindowController
        )
        defer { windowController.close() }
        let preferences = try XCTUnwrap(windowController.contentViewController as? PreferencesSplitViewController)
        _ = preferences.view
        let gestures = try XCTUnwrap(preferences.controller(for: GesturesPreferencesViewController.tabIdentifier) as? GesturesPreferencesViewController)
        gestures.deviceSource = MouseGestureDeviceSource(support: { .none }, refresh: {})
        gestures.bindingSummary = { MouseGestureBindingSummary(bindings: Options.shared.buttons.binding, isLogitechCode: { _ in false }) }
        let undo = UndoManager()
        undo.groupsByEvent = false
        gestures.paneUndoManager = undo
        _ = gestures.view
        let chooser = try XCTUnwrap(gestures.triggerChooser)
        chooser.deviceSource = ButtonsDeviceSource(captureStatus: { _ in .normal }, deviceName: { nil }, isBusy: { false }, refresh: {}, warnBluetoothButton: { _ in })
        var recorderAnchors: [NSView] = []
        let recording = expectation(description: "the recorder starts")
        chooser.startRecording = {
            recorderAnchors.append($0)
            recording.fulfill()
        }
        let buttons = try XCTUnwrap(preferences.controller(for: PANEL_IDENTIFIER.buttons) as? PreferencesButtonsViewController)
        buttons.deviceSource = ButtonsDeviceSource(captureStatus: { _ in .normal }, deviceName: { nil }, isBusy: { false }, refresh: {}, warnBluetoothButton: { _ in })
        buttons.startRecording = { _ in XCTFail("not the Buttons pane's recorder") }
        XCTAssertTrue(preferences.selectPane(withIdentifier: GesturesPreferencesViewController.tabIdentifier))
        XCTAssertTrue(gestures.foldingSections.allSatisfy { $0.isCollapsible })

        XCTAssertTrue(gestures.gestureButtonButton.chooseItemForTests(TriggerChooser.Identifier.record))
        wait(for: [recording], timeout: 5)
        XCTAssertEqual(recorderAnchors.count, 1)
        XCTAssertTrue(recorderAnchors.first === gestures.gestureButtonButton, "at the pull-down")
        XCTAssertEqual(preferences.selectedPaneIdentifier, GesturesPreferencesViewController.tabIdentifier, "the pane stays")

        // The user presses the Back button.
        let recorder = KeyRecorder()
        let back = InputEvent(type: .mouse, code: 3, modifiers: [], phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(chooser.waitingHint(recorder, mode: .combination), "Press a mouse button")
        chooser.onRecordingStarted(recorder)
        XCTAssertTrue(chooser.validateRecordedEvent(recorder, event: back))
        chooser.onEventRecorded(recorder, didRecordEvent: back, isDuplicate: false)
        undo.beginUndoGrouping()
        chooser.onRecordingStopped(recorder, didRecord: true)
        undo.endUndoGrouping()

        let added = try XCTUnwrap(Options.shared.buttons.binding.first)
        XCTAssertEqual(Options.shared.buttons.binding.count, 1)
        XCTAssertEqual(added.systemShortcutName, SystemShortcut.mouseGestureNavigation.identifier)
        XCTAssertTrue(added.isEnabled)
        XCTAssertEqual(added.triggerEvent, RecordedEvent(type: .mouse, code: 3, modifiers: 0, deviceFilter: nil))
        XCTAssertEqual(gestures.gestureButtonRow.explanation, "Hold it and move the mouse.", "shown at once")
        XCTAssertEqual(gestures.gestureButtonButton.shownTitle, "Back button")
        XCTAssertTrue(gestures.foldingSections.allSatisfy { $0.showsBody }, "the sections open")
        XCTAssertEqual(undo.undoActionName, "Change Button to Hold")

        XCTAssertTrue(preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.buttons))
        XCTAssertEqual(buttons.buttonBindings, [added], "the one place it is stored")
        undo.undo()
        XCTAssertEqual(Options.shared.buttons.binding, [])
        XCTAssertEqual(buttons.buttonBindings, [], "the Buttons pane on show follows the Undo")
        undo.redo()
        XCTAssertEqual(Options.shared.buttons.binding, [added])
        XCTAssertEqual(buttons.buttonBindings, [added])
    }

    /// A key cannot be the button to hold: the recorder refuses it and says why, and
    /// nothing is stored.
    func testRecordAButtonRefusesAKey() throws {
        let savedBindings = Options.shared.buttons.binding
        defer { Options.shared.buttons.binding = savedBindings }
        Options.shared.buttons.binding = []
        let controller = makeController()
        let chooser = try XCTUnwrap(controller.triggerChooser)
        let recorder = KeyRecorder()
        let key = InputEvent(type: .keyboard, code: 49, modifiers: [.maskControl, .maskAlternate], phase: .down, source: .hidPP, device: nil)
        chooser.onRecordingStarted(recorder)
        XCTAssertFalse(chooser.validateRecordedEvent(recorder, event: key))
        XCTAssertEqual(chooser.refusalHint(recorder, event: key), "Gestures need a mouse button")
        chooser.onEventRecorded(recorder, didRecordEvent: key, isDuplicate: true)
        chooser.onRecordingStopped(recorder, didRecord: false)
        XCTAssertEqual(Options.shared.buttons.binding, [])
    }

    func testLogiActionsAreOfferedOnceALogitechButtonRunsGestures() {
        let controller = makeController()
        let up = controller.controls.actionPopUp(for: .up)
        XCTAssertNil(item(SystemShortcut.logiSmartShiftToggle.identifier, in: up))
        XCTAssertNotNil(item(SystemShortcut.moveSpaceLeft.identifier, in: up))
        XCTAssertNil(item(SystemShortcut.mouseGestureNavigation.identifier, in: up), "a gesture cannot start a gesture")
        XCTAssertNil(item(SystemShortcut.modifierShift.identifier, in: up), "hold-style actions are left out")

        summary = MouseGestureBindingSummary(hasGestureButton: true, hasLogitechGestureButton: true)
        controller.reload()
        XCTAssertNotNil(item(SystemShortcut.logiSmartShiftToggle.identifier, in: up))
        XCTAssertEqual(title(of: up), SystemShortcut.missionControl.localizedName, "the shown action survives the rebuild")
    }

    func testBindingSummary() {
        func binding(_ shortcut: SystemShortcut.Shortcut, code: UInt16, enabled: Bool = true) -> ButtonBinding {
            return ButtonBinding(
                triggerEvent: RecordedEvent(type: .mouse, code: code, modifiers: 0, displayComponents: ["🖱"], deviceFilter: nil),
                systemShortcutName: shortcut.identifier,
                isEnabled: enabled
            )
        }
        let isLogitech: (UInt16) -> Bool = { $0 >= 1000 }

        let none = MouseGestureBindingSummary(bindings: [binding(SystemShortcut.copy, code: 3)], isLogitechCode: isLogitech)
        XCTAssertEqual(none, MouseGestureBindingSummary(hasGestureButton: false, hasLogitechGestureButton: false))

        let plain = MouseGestureBindingSummary(
            bindings: [binding(SystemShortcut.mouseGestureNavigation, code: 3), binding(SystemShortcut.copy, code: 1000)],
            isLogitechCode: isLogitech
        )
        // The picture holds the first of them (TriggerPictureTests has the rest).
        XCTAssertEqual(plain, MouseGestureBindingSummary(
            hasGestureButton: true, hasLogitechGestureButton: false, buttonTitles: ["Back button"],
            picture: TriggerPictureSource(event: binding(SystemShortcut.mouseGestureNavigation, code: 3).triggerEvent)
        ))

        let logitech = MouseGestureBindingSummary(
            bindings: [binding(SystemShortcut.mouseGestureNavigation, code: 1000)],
            isLogitechCode: isLogitech
        )
        XCTAssertEqual(logitech, MouseGestureBindingSummary(
            hasGestureButton: true, hasLogitechGestureButton: true, buttonTitles: ["Gesture button"],
            picture: TriggerPictureSource(event: binding(SystemShortcut.mouseGestureNavigation, code: 1000).triggerEvent)
        ))

        let disabled = MouseGestureBindingSummary(
            bindings: [binding(SystemShortcut.mouseGestureNavigation, code: 1000, enabled: false)],
            isLogitechCode: isLogitech
        )
        XCTAssertEqual(disabled, MouseGestureBindingSummary(hasGestureButton: false, hasLogitechGestureButton: false))

        // A key never starts a gesture.
        let key = ButtonBinding(
            triggerEvent: RecordedEvent(type: .keyboard, code: 40, modifiers: UInt(CGEventFlags.maskCommand.rawValue), deviceFilter: nil),
            systemShortcutName: SystemShortcut.mouseGestureNavigation.identifier,
            isEnabled: true
        )
        XCTAssertEqual(MouseGestureBindingSummary(bindings: [key], isLogitechCode: isLogitech),
                       MouseGestureBindingSummary(hasGestureButton: false, hasLogitechGestureButton: false))

        // Named as the Buttons pane names them: a Logitech Back button next to the standard one says so.
        let twins = MouseGestureBindingSummary(
            bindings: [binding(SystemShortcut.mouseGestureNavigation, code: 3), binding(SystemShortcut.mouseGestureNavigation, code: 1006)],
            isLogitechCode: isLogitech
        )
        XCTAssertEqual(twins.buttonTitles, ["Back button", "Back button (Logitech)"])
    }

    /// The "Gesture button" row counts only bindings that run: the Buttons pane's, and an
    /// app's own (`Application.buttons`), which run while the app is in front.
    func testTheGestureButtonRowCountsOnlyBindingsThatRun() {
        let savedBindings = Options.shared.buttons.binding
        let savedApplications = Options.shared.application.applications
        defer {
            Options.shared.buttons.binding = savedBindings
            Options.shared.application.applications = savedApplications
        }
        let gesture = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, deviceFilter: nil),
            systemShortcutName: SystemShortcut.mouseGestureNavigation.identifier,
            isEnabled: true
        )
        let app = Application(path: "/System/Applications/Calculator.app")
        app.buttons = OPTIONS_BUTTONS_DEFAULT()
        app.buttons?.binding = [gesture]
        Options.shared.application.applications = EnhanceArray<Application>(withArray: [app], matchKey: "path")
        Options.shared.buttons.binding = []

        // An app's own binding runs while the app is in front: the row says where.
        XCTAssertFalse(MouseGestureBindingSummary.current.hasGestureButton, "none of Buttons")
        let controller = makeController()
        controller.bindingSummary = { .current }
        controller.reload()
        XCTAssertEqual(controller.gestureButtonRow.explanation, "Only in Calculator: Back button.")
        XCTAssertEqual(controller.gestureButtonButton.shownTitle, "Choose", "none of Buttons: one can be chosen for every app")
        // The picture shows the app's button, with the app; the pane hands it to the preview.
        XCTAssertEqual(MouseGestureBindingSummary.current.picture,
                       TriggerPictureSource(event: gesture.triggerEvent, onlyInAppPath: "/System/Applications/Calculator.app"))
        XCTAssertEqual(controller.previewView.picture, MouseGestureBindingSummary.current.picture)
        XCTAssertEqual(controller.previewView.deviceCard.picture.appPath, "/System/Applications/Calculator.app")

        Options.shared.buttons.binding = [gesture]
        XCTAssertEqual(MouseGestureBindingSummary.current, MouseGestureBindingSummary(
            hasGestureButton: true, hasLogitechGestureButton: false, buttonTitles: ["Back button"],
            picture: TriggerPictureSource(event: gesture.triggerEvent)
        ))
    }

    // MARK: - The preview

    func testThePreviewShowsTheSettingsInEffect() {
        let controller = makeController()
        let preview = controller.previewView!
        XCTAssertEqual(preview.identifier, GesturesPreferencesViewController.Identifier.preview)
        XCTAssertEqual(preview.scene, GesturePreviewScene(
            gesture: .default, focus: nil, availability: controller.controls.availability
        ), "the picture and the rows go by the same answer on what follows")
        XCTAssertFalse(preview.isTimerRunning, "not shown, not running")

        // Every control that writes a setting changes the scene, and so restarts the demo.
        let controls = controller.controls!
        controls.modeControl.selectedSegment = 1
        send(controls.modeControl)
        XCTAssertEqual(preview.scene.gesture.mode, .interactive)
        XCTAssertEqual(preview.loop.legs.first?.kind, .follow)

        toggle(controls.invertToggle, on: true)
        XCTAssertTrue(preview.scene.gesture.invertHorizontal)
        XCTAssertEqual(preview.loop.legs.first?.shift, -1, "inverted, the slide goes the other way")

        toggle(controls.freezeToggle, on: false)
        XCTAssertFalse(preview.scene.gesture.freezePointer)

        choose(SystemShortcut.copy.identifier, in: controls.actionPopUp(for: .up))
        XCTAssertEqual(preview.scene.gesture.upAction, SystemShortcut.copy.identifier)

        XCTAssertEqual(preview.scene.gesture, Options.shared.gesture)
    }

    func testThePreviewFollowsTheRowPointedAt() {
        let controller = makeController()
        let preview = controller.previewView!
        XCTAssertNil(preview.scene.focus)

        controller.slotHoverChanged(.up, inside: true)
        XCTAssertEqual(preview.scene.focus, .up)
        XCTAssertEqual(preview.loop.legs, [.move(.up, effect: .missionControl)])
        XCTAssertEqual(preview.loopTime, 0)

        // Moving to the next row: the old row's exit may come after the new row's enter.
        controller.slotHoverChanged(.down, inside: true)
        controller.slotHoverChanged(.up, inside: false)
        XCTAssertEqual(preview.scene.focus, .down)

        controller.slotHoverChanged(.down, inside: false)
        XCTAssertNil(preview.scene.focus, "nothing pointed at: left and right in turn")

        // The keyboard focus counts too; the pointer wins.
        controller.slotFocusChanged(.click, focused: true)
        XCTAssertEqual(preview.scene.focus, .click)
        controller.slotHoverChanged(.right, inside: true)
        XCTAssertEqual(preview.scene.focus, .right)
        controller.slotHoverChanged(.right, inside: false)
        XCTAssertEqual(preview.scene.focus, .click)
        controller.slotFocusChanged(.click, focused: false)
        XCTAssertNil(preview.scene.focus)

        // Leaving the tab forgets both.
        controller.slotHoverChanged(.up, inside: true)
        controller.slotFocusChanged(.down, focused: true)
        controller.viewDidDisappear()
        XCTAssertNil(controller.hoveredSlot)
        XCTAssertNil(controller.focusedSlot)
        XCTAssertNil(preview.scene.focus)
    }

    func testDirectionRowsReportThePointerAndThePopUpsTheFocus() throws {
        let controller = makeController()
        for slot in Slot.allCases {
            let row = controller.directionRows[slot.rawValue]
            let area = try XCTUnwrap(row.trackingAreas.first, slot.name)
            XCTAssertTrue(area.owner === controller)
            XCTAssertEqual(area.userInfo?["gestureSlot"] as? Int, slot.rawValue)
            XCTAssertTrue(area.options.contains(.mouseEnteredAndExited))
            XCTAssertTrue(controller.controls.actionPopUp(for: slot) is MouseGestureActionPopUpButton)
        }

        // A focus change of a pop-up reaches the tab.
        let popup = try XCTUnwrap(controller.controls.actionPopUp(for: .down) as? MouseGestureActionPopUpButton)
        popup.onFocusChange?(true)
        XCTAssertEqual(controller.previewView.scene.focus, .down)
        popup.onFocusChange?(false)
        XCTAssertNil(controller.previewView.scene.focus)
    }

    // MARK: - Reset to Defaults

    private let master4 = MouseGestureDeviceSupport(deviceTracking: true, haptics: true)

    /// Every gesture setting off its default (the speed off the slider's ticks too).
    private var changedGesture: MouseGestureSettings {
        return MouseGestureSettings(
            upAction: SystemShortcut.copy.identifier,
            downAction: SystemShortcut.paste.identifier,
            leftAction: SystemShortcut.navigateBack.identifier,
            rightAction: "",
            clickAction: SystemShortcut.mouseMiddleClick.identifier,
            invertHorizontal: true,
            freezePointer: false,
            mode: .interactive,
            trackingSpeed: 2.2,
            deviceTracking: true,
            hapticFeedback: false
        )
    }

    /// A pane whose reset has an Undo to register. The offer lasts until the test ends it.
    private func makeControllerWithUndo() -> (GesturesPreferencesViewController, UndoManager) {
        let controller = makeController()
        let undo = UndoManager()
        undo.groupsByEvent = false
        controller.paneUndoManager = undo
        controller.resetToDefaults.undoOfferDuration = 60
        return (controller, undo)
    }

    /// A click that resets, as one event: its Undo is one group.
    private func click(_ button: NSButton, _ undo: UndoManager) {
        undo.beginUndoGrouping()
        send(button)
        undo.endUndoGrouping()
    }

    /// The button is the Scrolling pane's, in a footer that is the last thing in the pane,
    /// with a section's room above it whatever shows last: "Behavior" (no Logitech
    /// mouse), the Logitech box, or the line under that box.
    func testResetToDefaultsSitsLastUnderWhateverShowsAboveIt() throws {
        let savedMouse = Options.shared.logiMouse
        defer { Options.shared.logiMouse = savedMouse }
        Options.shared.logiMouse = .default
        let controller = makeController()
        let button = controller.resetToDefaultsButton
        XCTAssertEqual(button.title, "Reset to Defaults")
        XCTAssertEqual(button.identifier, GesturesPreferencesViewController.Identifier.reset)
        XCTAssertTrue(controller.sections.last === controller.footer)
        XCTAssertTrue(controller.footer.views.count == 1 && controller.footer.views.first === button)

        func rect(_ view: NSView) -> NSRect {
            return controller.view.convert(view.alignmentRect(forFrame: view.frame), from: view.superview)
        }
        func check(under above: NSView, _ what: String, line: UInt = #line) {
            controller.view.layoutSubtreeIfNeeded()
            XCTAssertFalse(above.isHidden, what, line: line)
            // The root view is not flipped: lower on screen is a smaller y.
            XCTAssertEqual(rect(above).minY - rect(controller.footer).maxY, PreferencesGroupedForm.sectionSpacing, accuracy: 0.5, what, line: line)
            XCTAssertEqual(rect(controller.footer).minY, PreferencesGroupedForm.margin, accuracy: 0.5, what, line: line)
            XCTAssertEqual(rect(button).maxX, rect(controller.trackingSpeedRow).maxX, accuracy: 0.5, what, line: line)
            XCTAssertEqual(controller.view.frame.size, controller.view.fittingSize, what, line: line)
            XCTAssertFalse(controller.view.hasAmbiguousLayout, what, line: line)
        }
        check(under: controller.behaviourSection, "no Logitech mouse: Behavior is the last box")

        support = master4
        controller.reload()
        check(under: controller.logitechSection, "the Logitech box")

        support = MouseGestureDeviceSupport(deviceTracking: true, haptics: true, hapticsOffOnMouse: true)
        Options.shared.logiMouse.hapticsOn = false
        controller.reload()
        check(under: controller.hapticsOffNote, "the line under the Logitech box")
        XCTAssertEqual(rect(controller.logitechSection).minY - rect(controller.hapticsOffNote).maxY,
                       PreferencesGroupedForm.noteSpacing, accuracy: 0.5, "which stays close under its box")

        // Side by side with the Scrolling pane's button.
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesScrollingViewController.self))
        let scrolling = try XCTUnwrap(
            storyboard.instantiateController(withIdentifier: PANEL_IDENTIFIER.scrolling) as? PreferencesScrollingViewController
        )
        scrolling.uiStateDefaults = TestDefaults.make(for: self)
        scrolling.view.layoutSubtreeIfNeeded()
        let model = try XCTUnwrap(scrolling.resetToDefaultsButton)
        let its = scrolling.view.convert(model.alignmentRect(forFrame: model.frame), from: model.superview)
        XCTAssertEqual(button.title, model.title)
        XCTAssertEqual(button.bezelStyle, model.bezelStyle)
        XCTAssertEqual(button.controlSize, model.controlSize)
        XCTAssertEqual(button.font, model.font)
        XCTAssertEqual(rect(button).size.width, its.size.width, accuracy: 0.5)
        XCTAssertEqual(rect(button).size.height, its.size.height, accuracy: 0.5)
        XCTAssertEqual(rect(button).maxX, its.maxX, accuracy: 0.5)
        XCTAssertEqual(rect(button).minY, its.minY, accuracy: 0.5, "as far from the pane's lower edge")
    }

    /// Greyed out while every gesture setting is the default one; each control of the pane
    /// that moves a setting off its default lights it, and back greys it out again.
    func testResetIsOnlyOfferedWhenAGestureSettingDiffers() {
        support = master4
        let controller = makeController()
        let controls = controller.controls!
        let button = controller.resetToDefaultsButton
        XCTAssertFalse(controller.resetToDefaults.hasSettingsToReset)
        XCTAssertFalse(button.isEnabled, "a new installation has nothing to reset")

        let mode = controls.modeControl
        let changes: [(name: String, change: () -> Void, back: () -> Void)] = [
            ("an action", { self.choose(SystemShortcut.copy.identifier, in: controls.actionPopUp(for: .click)) },
             { self.choose(SystemShortcut.missionControl.identifier, in: controls.actionPopUp(for: .click)) }),
            ("no action", { self.choose("", in: controls.actionPopUp(for: .up)) },
             { self.choose(SystemShortcut.missionControl.identifier, in: controls.actionPopUp(for: .up)) }),
            ("invert", { self.toggle(controls.invertToggle, on: true) }, { self.toggle(controls.invertToggle, on: false) }),
            ("freeze", { self.toggle(controls.freezeToggle, on: false) }, { self.toggle(controls.freezeToggle, on: true) }),
            ("the mode", { mode.selectedSegment = 1; self.send(mode) }, { mode.selectedSegment = 0; self.send(mode) }),
            ("the mouse tracks", { self.toggle(controller.deviceTrackingSwitch, on: true) },
             { self.toggle(controller.deviceTrackingSwitch, on: false) }),
            ("haptic feedback", { self.toggle(controller.hapticsSwitch, on: false) }, { self.toggle(controller.hapticsSwitch, on: true) }),
            // (The slider is off in this mode; its action is the pane's all the same.)
            ("the swipe speed", { controller.trackingSpeedSlider.doubleValue = 1.5; self.send(controller.trackingSpeedSlider) },
             { controller.trackingSpeedSlider.doubleValue = 1; self.send(controller.trackingSpeedSlider) }),
        ]
        for item in changes {
            item.change()
            XCTAssertNotEqual(Options.shared.gesture, .default, item.name)
            XCTAssertTrue(button.isEnabled, item.name)
            item.back()
            XCTAssertEqual(Options.shared.gesture, .default, item.name)
            XCTAssertFalse(button.isEnabled, "\(item.name), back")
        }

        // Settings that changed while the pane was away (the Buttons pane, a settings file).
        Options.shared.gesture.downAction = ""
        controller.viewWillAppear()
        XCTAssertTrue(button.isEnabled)
        XCTAssertEqual(button.title, "Reset to Defaults")
    }

    /// The reset is every gesture setting of a new installation, shown at once in the
    /// rows and the preview. The button to hold is a binding of the Buttons pane, and
    /// "Haptic feedback" under Mouse is the Mouse pane's: both stay.
    func testResetPutsBackEveryGestureSettingAndLeavesTheButtonToHold() {
        let savedBindings = Options.shared.buttons.binding
        let savedMouse = Options.shared.logiMouse
        defer {
            Options.shared.buttons.binding = savedBindings
            Options.shared.logiMouse = savedMouse
            ButtonUtils.shared.invalidateCache()
        }
        func binding(_ code: UInt16, _ action: String) -> ButtonBinding {
            return ButtonBinding(
                triggerEvent: RecordedEvent(type: .mouse, code: code, modifiers: 0, deviceFilter: nil),
                systemShortcutName: action, isEnabled: true
            )
        }
        let bindings = [binding(3, SystemShortcut.mouseGestureNavigation.identifier), binding(4, "copy")]
        Options.shared.buttons.binding = bindings
        Options.shared.logiMouse = LogiMouseSettings(hapticsOn: false)
        Options.shared.gesture = changedGesture
        support = master4
        let controller = makeController()
        // The first row reads the stored bindings, as in the window.
        controller.bindingSummary = {
            MouseGestureBindingSummary(bindings: Options.shared.buttons.binding, isLogitechCode: { _ in false })
        }
        controller.reload()
        let controls = controller.controls!
        let held = controller.gestureButtonRow.explanation
        XCTAssertEqual(controller.gestureButtonButton.shownTitle, "Back button")
        XCTAssertEqual(controls.modeControl.selectedSegment, 1)
        XCTAssertEqual(title(of: controls.actionPopUp(for: .up)), SystemShortcut.copy.localizedName)
        XCTAssertEqual(controller.deviceTrackingSwitch.state, .on)
        XCTAssertEqual(controller.hapticsSwitch.state, .off)
        XCTAssertTrue(controller.resetToDefaultsButton.isEnabled)

        send(controller.resetToDefaultsButton)

        // Every setting, by name: what a new installation has.
        let gesture = Options.shared.gesture
        XCTAssertEqual(gesture, .default)
        XCTAssertEqual(gesture.mode, .discrete)
        XCTAssertEqual(gesture.upAction, SystemShortcut.missionControl.identifier)
        XCTAssertEqual(gesture.downAction, SystemShortcut.appExpose.identifier)
        XCTAssertEqual(gesture.leftAction, SystemShortcut.moveSpaceLeft.identifier)
        XCTAssertEqual(gesture.rightAction, SystemShortcut.moveSpaceRight.identifier)
        XCTAssertEqual(gesture.clickAction, SystemShortcut.missionControl.identifier)
        XCTAssertFalse(gesture.invertHorizontal)
        XCTAssertTrue(gesture.freezePointer)
        XCTAssertEqual(gesture.trackingSpeed, 1)
        XCTAssertFalse(gesture.deviceTracking)
        XCTAssertTrue(gesture.hapticFeedback)

        // The rows and the preview follow at once.
        XCTAssertEqual(controls.modeControl.selectedSegment, 0)
        XCTAssertEqual(controller.modeRow.explanation, text("gesture-mode-discrete-description"))
        XCTAssertEqual(Slot.allCases.map { title(of: controls.actionPopUp(for: $0)) }, [
            SystemShortcut.missionControl, SystemShortcut.appExpose, SystemShortcut.moveSpaceLeft,
            SystemShortcut.moveSpaceRight, SystemShortcut.missionControl,
        ].map(\.localizedName))
        XCTAssertTrue(controls.actionPopUp(for: .left).isEnabled, "Left and Right are the user's again")
        XCTAssertTrue(controls.actionPopUp(for: .right).isEnabled)
        XCTAssertFalse(MouseGestureSettingsControls.isOn(controls.invertToggle))
        XCTAssertTrue(MouseGestureSettingsControls.isOn(controls.freezeToggle))
        XCTAssertEqual(controller.trackingSpeedSlider.doubleValue, 1, accuracy: 1e-9)
        XCTAssertEqual(controller.trackingSpeedRow.valueText, speedText(1))
        XCTAssertFalse(controller.trackingSpeedSlider.isEnabled)
        XCTAssertEqual(controller.deviceTrackingSwitch.state, .off)
        XCTAssertEqual(controller.hapticsSwitch.state, .on)
        XCTAssertEqual(controller.previewView.scene.gesture, .default)

        // The button to hold, and the Mouse pane's switch: as they were.
        XCTAssertEqual(Options.shared.buttons.binding, bindings)
        XCTAssertEqual(controller.gestureButtonRow.explanation, held)
        XCTAssertEqual(controller.gestureButtonButton.shownTitle, "Back button")
        XCTAssertEqual(Options.shared.logiMouse, LogiMouseSettings(hapticsOn: false))

        XCTAssertFalse(controller.resetToDefaultsButton.isEnabled, "nothing differs any more")
        XCTAssertEqual(controller.resetToDefaultsButton.title, "Reset to Defaults", "in no window there is no Undo to offer")
        XCTAssertNil(controller.undoTarget)
    }

    /// The two switches of a Logitech mouse are gesture settings too: with no such mouse
    /// connected their box does not show, and the reset still puts them back.
    func testResetCoversTheLogitechSwitchesWhileTheirBoxDoesNotShow() {
        Options.shared.gesture.deviceTracking = true
        Options.shared.gesture.hapticFeedback = false
        let controller = makeController()
        XCTAssertTrue(controller.logitechSection.isHidden)
        XCTAssertTrue(controller.resetToDefaultsButton.isEnabled)
        send(controller.resetToDefaultsButton)
        XCTAssertEqual(Options.shared.gesture, .default)
        XCTAssertFalse(controller.resetToDefaultsButton.isEnabled)
    }

    /// After a reset the button reads "Undo Reset" and brings back exactly the settings
    /// that were there, actions, switches and values; Edit › Undo and Redo ("Reset
    /// Gestures") do the same. A change, or the pane going away, makes it "Reset to
    /// Defaults" again.
    func testAfterAResetTheButtonOffersToUndoItAndUndoBringsBackEverySetting() {
        support = master4
        Options.shared.gesture = changedGesture
        let before = Options.shared.gesture
        let (controller, undo) = makeControllerWithUndo()
        let controls = controller.controls!
        let button = controller.resetToDefaultsButton
        XCTAssertEqual(button.title, "Reset to Defaults")
        XCTAssertTrue(button.isEnabled)
        XCTAssertFalse(controller.resetToDefaults.offersUndo)

        click(button, undo)
        XCTAssertEqual(Options.shared.gesture, .default)
        XCTAssertTrue(controller.resetToDefaults.offersUndo)
        XCTAssertEqual(button.title, "Undo Reset")
        XCTAssertTrue(button.isEnabled, "not greyed out although nothing differs")
        XCTAssertEqual(undo.undoMenuItemTitle, "Undo Reset Gestures")

        // "Undo Reset": every action, switch and value is back, and shown.
        send(button)
        XCTAssertEqual(Options.shared.gesture, before)
        XCTAssertEqual(Options.shared.gesture.rightAction, "")
        XCTAssertEqual(Options.shared.gesture.trackingSpeed, 2.2, "as stored, not moved onto a tick")
        XCTAssertEqual(controls.modeControl.selectedSegment, 1)
        XCTAssertEqual(title(of: controls.actionPopUp(for: .up)), SystemShortcut.copy.localizedName)
        XCTAssertEqual(title(of: controls.actionPopUp(for: .click)), SystemShortcut.mouseMiddleClick.localizedName)
        XCTAssertFalse(controls.actionPopUp(for: .left).isEnabled, "the swipe has Left and Right again")
        XCTAssertTrue(MouseGestureSettingsControls.isOn(controls.invertToggle))
        XCTAssertFalse(MouseGestureSettingsControls.isOn(controls.freezeToggle))
        XCTAssertEqual(controller.trackingSpeedRow.valueText, speedText(2.2))
        XCTAssertEqual(controller.deviceTrackingSwitch.state, .on)
        XCTAssertEqual(controller.hapticsSwitch.state, .off)
        XCTAssertEqual(controller.previewView.scene.gesture, before)
        XCTAssertFalse(controller.resetToDefaults.offersUndo)
        XCTAssertEqual(button.title, "Reset to Defaults")
        XCTAssertTrue(button.isEnabled)
        XCTAssertTrue(undo.canRedo)
        XCTAssertEqual(undo.redoMenuItemTitle, "Redo Reset Gestures")

        // Edit › Redo resets again, Edit › Undo takes that back too.
        undo.redo()
        XCTAssertEqual(Options.shared.gesture, .default)
        XCTAssertEqual(controls.modeControl.selectedSegment, 0)
        XCTAssertFalse(button.isEnabled)
        undo.undo()
        XCTAssertEqual(Options.shared.gesture, before)
        XCTAssertTrue(button.isEnabled)

        // A change after a reset ends the offer: the next click resets, it does not undo.
        click(button, undo)
        XCTAssertTrue(controller.resetToDefaults.offersUndo)
        toggle(controls.invertToggle, on: true)
        XCTAssertFalse(controller.resetToDefaults.offersUndo)
        XCTAssertEqual(button.title, "Reset to Defaults")
        XCTAssertTrue(button.isEnabled)
        click(button, undo)
        XCTAssertEqual(Options.shared.gesture, .default, "a reset")
        XCTAssertTrue(controller.resetToDefaults.offersUndo)

        // The settings changed behind the pane's back: the click still resets.
        Options.shared.gesture.freezePointer = false
        click(button, undo)
        XCTAssertEqual(Options.shared.gesture, .default, "a reset, not an Undo of the one before")

        // The pane goes away: the offer goes with it.
        XCTAssertTrue(controller.resetToDefaults.offersUndo)
        controller.viewDidDisappear()
        XCTAssertFalse(controller.resetToDefaults.offersUndo)
        XCTAssertEqual(button.title, "Reset to Defaults")
        XCTAssertFalse(button.isEnabled)
    }

    /// The offer lasts a moment (eight seconds, as in Scrolling) and ends by itself; the
    /// reset stays under Edit › Undo.
    func testTheUndoOfferEndsByItselfAndEditUndoStillWorks() {
        Options.shared.gesture = changedGesture
        let before = Options.shared.gesture
        XCTAssertEqual(makeController().resetToDefaults.undoOfferDuration, 8)
        XCTAssertEqual(PreferencesScrollingViewController().undoOfferDuration, 8, "the same moment")
        let (controller, undo) = makeControllerWithUndo()
        controller.resetToDefaults.undoOfferDuration = 0.05
        let button = controller.resetToDefaultsButton

        click(button, undo)
        XCTAssertEqual(button.title, "Undo Reset")
        let deadline = Date().addingTimeInterval(10)
        while controller.resetToDefaults.offersUndo, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertFalse(controller.resetToDefaults.offersUndo)
        XCTAssertEqual(button.title, "Reset to Defaults")
        XCTAssertFalse(button.isEnabled, "nothing differs from the defaults")
        XCTAssertEqual(Options.shared.gesture, .default, "the reset stays")

        XCTAssertEqual(undo.undoMenuItemTitle, "Undo Reset Gestures")
        undo.undo()
        XCTAssertEqual(Options.shared.gesture, before)
        XCTAssertTrue(button.isEnabled)
    }

    /// "Only in …" in the pane's row, as it lays it out: long names of apps are cut short
    /// and the line keeps to two lines.
    func testTheOnlyInLineOfTheButtonToHoldKeepsToTwoLines() {
        summary = MouseGestureBindingSummary(
            hasGestureButton: false, hasLogitechGestureButton: false,
            onlyInApps: ApplicationTriggers(
                applicationNames: ["DaVinci Resolve Studio", "Adobe Premiere Pro 2026", "Microsoft Visual Studio Code Insiders", "Final Cut Pro Trial"],
                triggerTitles: ["Thumb panel", "Back button", "Gesture button (button 6)", "Forward button"],
                ownOnly: .gestureNavigation,
                appTriggerTitles: [["Thumb panel"], ["Back button"], ["Gesture button (button 6)"], ["Forward button"]]
            )
        )
        let controller = makeController()
        controller.view.layoutSubtreeIfNeeded()
        let label = controller.gestureButtonRow.explanationLabel
        XCTAssertTrue(label.stringValue.hasPrefix("Only in DaVinci"), label.stringValue)
        XCTAssertTrue(label.stringValue.contains("2 more"), "four apps: two named, the rest counted: \(label.stringValue)")
        XCTAssertGreaterThan(label.frame.width, 200)
        XCTAssertLessThanOrEqual(
            ApplicationPagePart.LineCount(width: label.frame.width, font: PreferencesGroupedForm.explanationFont).of(label.stringValue), 2,
            "\(label.stringValue) in \(label.frame.width) pt"
        )
    }

    /// "Undo Reset" is offered only while a click would do it. After a reset, the choice of
    /// the button to hold is a step Edit › Undo takes back first, and a binding of Buttons:
    /// the gesture settings are still the defaults. The offer ends with it. Regression: the
    /// button went on reading "Undo Reset", and a click did nothing but turn it into a
    /// greyed "Reset to Defaults".
    func testAnotherUndoStepAfterAResetEndsTheUndoOffer() throws {
        Options.shared.gesture = changedGesture
        let before = Options.shared.gesture
        let (controller, undo) = makeControllerWithUndo()
        var bindings: [ButtonBinding] = []
        let chooser = try XCTUnwrap(controller.triggerChooser)
        chooser.bindings = { bindings }
        chooser.store = { bindings = $0 }
        chooser.deviceSource = ButtonsDeviceSource(
            captureStatus: { _ in .normal }, deviceName: { nil }, isBusy: { false }, refresh: {}, warnBluetoothButton: { _ in }
        )
        let button = controller.resetToDefaultsButton
        click(button, undo)
        XCTAssertEqual(button.title, "Undo Reset")

        undo.beginUndoGrouping()
        chooser.choose(RecordedEvent(type: .mouse, code: 3, modifiers: 0, deviceFilter: nil))
        undo.endUndoGrouping()
        XCTAssertEqual(bindings.map(\.systemShortcutName), [SystemShortcut.mouseGestureNavigation.identifier])
        XCTAssertEqual(undo.undoActionName, "Change Button to Hold")
        XCTAssertEqual(Options.shared.gesture, .default, "the gesture settings are untouched")
        XCTAssertFalse(controller.resetToDefaults.offersUndo, "a click would not take the reset back")
        XCTAssertEqual(button.title, "Reset to Defaults")
        XCTAssertFalse(button.isEnabled, "nothing differs from the defaults")

        // Edit › Undo still takes back both, in their order.
        undo.undo()
        XCTAssertTrue(bindings.isEmpty)
        undo.undo()
        XCTAssertEqual(Options.shared.gesture, before)
    }

    // MARK: - Strings

    func testEveryLocaleTranslatesTheGesturesTab() {
        let missing = "\u{1}missing"
        let app = Bundle(for: PreferencesSplitViewController.self)
        let keys = [
            "gestures-tab-title", "gesture-mode-label",
            "gesture-mode-discrete-description", "gesture-mode-interactive-description",
            "gesture-tracking-speed-label", "gesture-tracking-speed-hint", "gesture-tracking-speed-hint-discrete",
            "gesture-tracking-speed-slower", "gesture-tracking-speed-faster",
            "gesture-invert-horizontal-hint", "gesture-freeze-pointer-hint",
            "gestures-gesture-button", "gestures-gesture-button-none",
            "gestures-trigger-choice-record", "gestures-undo-choose-button", "buttons-trigger-choice-choose",
            "buttons-trigger-choice-several", "buttons-trigger-choice-show",
            "gestures-directions-header", "gestures-directions-hint", "gestures-behaviour-header",
            "gesture-freeze-pointer-mouse-holds", "gesture-freeze-pointer-mouse-holds-some",
            "gesture-follow-actions-label", "gesture-follow-actions-hint-discrete", "gesture-follow-actions-hint-none",
            "gesture-follow-apps-value", "gesture-follow-once-macos", "gesture-follow-once-gesture-off",
        ]
        for locale in PreferencesLocalizationTests.locales {
            guard let path = app.path(forResource: locale, ofType: "lproj"), let bundle = Bundle(path: path) else {
                XCTFail("\(locale).lproj is missing")
                continue
            }
            for key in keys {
                let value = bundle.localizedString(forKey: key, value: missing, table: nil)
                XCTAssertNotEqual(value, missing, "\(locale): \(key) missing")
                XCTAssertNotEqual(value, key, "\(locale): \(key) shows the raw key")
                XCTAssertFalse(value.isEmpty, "\(locale): \(key) empty")
                XCTAssertFalse(value.contains("%"), "\(locale): \(key) takes no arguments")
            }
        }
    }
}

/// Renders the tab off screen for a look at it: both modes, with and without a mouse that
/// supports the Logitech options, without a gesture button, light and dark; and "Up and Down
/// follow the hand too" in each of its states (`testRenderUpAndDownFollowingTheHand`). Off screen the
/// window's material draws a flat grey and vibrant text is not blended, so text looks a
/// little dimmer than on screen. Only runs when asked to:
/// `TEST_RUNNER_SCROLLIO_SHOTS_DIR=<folder> xcodebuild … test -only-testing:ScrollioTests/PreferencesGesturesRenderTests`.
final class PreferencesGesturesRenderTests: XCTestCase {

    private var savedGesture = MouseGestureSettings.default

    override func setUp() {
        super.setUp()
        savedGesture = Options.shared.gesture
    }

    override func tearDown() {
        Options.shared.gesture = savedGesture
        super.tearDown()
    }

    func testRenderTheTab() throws {
        // Its files are named "tab-…": in a folder of their own.
        let directory = try RenderShots.directory(for: "the Gestures tab", subfolder: "gestures-tab")

        let master4 = MouseGestureDeviceSupport(deviceTracking: true, haptics: true)
        let master3 = MouseGestureDeviceSupport(deviceTracking: true, haptics: false)
        let cases: [(name: String, mode: MouseGestureMode, support: MouseGestureDeviceSupport, bound: Bool, available: Bool)] = [
            ("discrete-no-logitech", .discrete, .none, true, true),
            ("discrete-mx-master-4", .discrete, master4, true, true),
            ("follow-no-logitech", .interactive, .none, true, true),
            ("follow-mx-master-4", .interactive, master4, true, true),
            ("follow-mx-master-3", .interactive, master3, true, true),
            ("unbound-no-logitech", .discrete, .none, false, true),
            ("follow-unavailable", .interactive, .none, true, false),
        ]
        for item in cases {
            var gesture = MouseGestureSettings.default
            gesture.mode = item.mode
            gesture.deviceTracking = item.support.deviceTracking
            Options.shared.gesture = gesture
            let controller = GesturesPreferencesViewController(isInteractiveAvailable: { item.available })
            controller.deviceSource = MouseGestureDeviceSource(support: { item.support }, refresh: {})
            controller.bindingSummary = {
                MouseGestureBindingSummary(
                    hasGestureButton: item.bound,
                    hasLogitechGestureButton: item.support.deviceTracking,
                    buttonTitles: item.bound ? ["Gesture button"] : []
                )
            }
            _ = controller.view
            // The preview still: the desktops half-way, or the action fully shown.
            controller.previewView.prefersReducedMotion = { true }
            controller.previewView.reduceMotionDidChange()
            try render(controller.view, name: "tab-\(item.name)", into: directory)
        }
    }

    /// "Up and Down follow the hand too" (`follow-hand-<case>-<appearance>.png`), by what
    /// can follow on the Mac each case describes, never this Mac's own Dock settings:
    /// `all-three` (the owner's own build on macOS 27: Mission Control, Apps and Show
    /// Desktop), `release-27` (a released build: Up says it follows, Down is plain "Apps"),
    /// `mixed` (Up = Show Desktop as a sentence, Down = a recorded key combination with its
    /// icon), `before-27` (only Mission Control; Down = Show Desktop plain), `gesture-off`
    /// (the Dock's switch for Mission Control off: Up plain, Down = Show Desktop follows),
    /// `nothing` (no gesture is on), `switch-off` (every row plain, the switch's line the
    /// same), `one-action` ("One action per hold": the switch dimmed with its line) and
    /// `one-action-switch-on` (the stored choice still shows). The pane is as tall in each.
    func testRenderUpAndDownFollowingTheHand() throws {
        let directory = try RenderShots.directory(for: "Up and Down following the hand", subfolder: "gestures-tab")
        let showDesktop = SystemShortcut.showDesktop.identifier
        var missionControlOff = DockGestureSwitches.allOn
        missionControlOff.missionControl = false
        let allOff = DockGestureSwitches(missionControl: false, showDesktop: false, launchpad: false)
        func mac(_ macOS: Int = 27, apps: Bool = false, switches: DockGestureSwitches = .allOn) -> DockFollowAvailability {
            return PreferencesGesturesTests.follows(macOS: macOS, apps: apps, switches: switches)
        }
        let keys = GestureAction(action: "custom::15:1179648", label: ShortcutLabel(name: "Reload", icon: .symbol("arrow.clockwise")))
        typealias Change = (inout MouseGestureSettings) -> Void
        let cases: [(name: String, mac: DockFollowAvailability, change: Change)] = [
            ("all-three", mac(apps: true), { _ in }),
            ("release-27", mac(), { _ in }),
            ("mixed", mac(), { $0.upAction = showDesktop; $0.actions.down = keys }),
            ("before-27", mac(26), { $0.downAction = showDesktop }),
            ("gesture-off", mac(switches: missionControlOff), { $0.downAction = showDesktop }),
            ("nothing", mac(switches: allOff), { _ in }),
            ("switch-off", mac(), { $0.actionsFollowHand = false }),
            ("one-action", mac(), { $0.mode = .discrete; $0.actionsFollowHand = false }),
            ("one-action-switch-on", mac(), { $0.mode = .discrete }),
        ]
        var heights: [String: CGFloat] = [:]
        for item in cases {
            var gesture = MouseGestureSettings.default
            gesture.mode = .interactive
            gesture.actionsFollowHand = true
            item.change(&gesture)
            Options.shared.gesture = gesture
            let controller = GesturesPreferencesViewController(isInteractiveAvailable: { true }, followAvailability: { item.mac })
            controller.deviceSource = MouseGestureDeviceSource(support: { .none }, refresh: {})
            controller.bindingSummary = {
                MouseGestureBindingSummary(hasGestureButton: true, hasLogitechGestureButton: false, buttonTitles: ["Back button"])
            }
            _ = controller.view
            controller.previewView.prefersReducedMotion = { true }
            controller.previewView.reduceMotionDidChange()
            heights[item.name] = controller.view.frame.height
            try render(controller.view, name: "follow-hand-\(item.name)", into: directory)
        }
        XCTAssertEqual(Set(heights.values).count, 1, "\(heights)")
    }

    /// Writes `<name>-light.png` and `<name>-dark.png`, as the Scrolling render does.
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

private extension NSView {
    /// Every view under this one.
    var allSubviewsForTests: [NSView] {
        return subviews + subviews.flatMap(\.allSubviewsForTests)
    }
}

// MARK: - Undo of a direction

/// Edit › Undo and Redo of a direction of Gesture Navigation, the pane's and an app's own:
/// the action as it was (with the name and icon of its keys), named as Buttons names it;
/// the Gestures pane, or the app's page on its Gestures part, comes forward with the row
/// selected, also from another pane and after the page closed. The window as the app makes
/// it, never shown.
final class GestureDirectionUndoTests: XCTestCase {

    private static let calculator = "/System/Applications/Calculator.app"
    /// A recorded key combination (⌘S as the settings store it).
    private static let keys = "custom::1:1048576"

    private var savedApplications: EnhanceArray<Application>!
    private var savedBindings: [ButtonBinding] = []
    private var savedGesture = MouseGestureSettings.default
    private var uiDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        savedApplications = Options.shared.application.applications
        savedBindings = Options.shared.buttons.binding
        savedGesture = Options.shared.gesture
        Options.shared.application.applications = EnhanceArray<Application>(
            withArray: [], matchKey: "path", forObserver: { Options.shared.markChanged(.application) }
        )
        Options.shared.buttons.binding = []
        Options.shared.gesture = .default
        ButtonUtils.shared.invalidateCache()
        uiDefaults = TestDefaults.make(for: self)
    }

    override func tearDown() {
        Options.shared.application.applications = savedApplications
        Options.shared.buttons.binding = savedBindings
        Options.shared.gesture = savedGesture
        ButtonUtils.shared.invalidateCache()
        savedApplications = nil
        uiDefaults = nil
        super.tearDown()
    }

    private struct Window {
        let window: NSWindow
        let preferences: PreferencesSplitViewController
        let undo: UndoManager
        let gestures: GesturesPreferencesViewController
        let apps: PreferencesApplicationViewController
    }

    /// The window's panes (nothing remembered, no mouse, no button that runs the gestures),
    /// in a window of their own whose undo manager takes a group per step.
    private func makeWindow() throws -> Window {
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesSplitViewController.self))
        let preferences = PreferencesSplitViewController(storyboard: storyboard, uiStateDefaults: nil)
        let gestures = try XCTUnwrap(
            preferences.controller(for: GesturesPreferencesViewController.tabIdentifier) as? GesturesPreferencesViewController
        )
        gestures.deviceSource = MouseGestureDeviceSource(support: { .none }, refresh: {})
        gestures.bindingSummary = { MouseGestureBindingSummary(hasGestureButton: false, hasLogitechGestureButton: false) }
        let apps = try XCTUnwrap(preferences.controller(for: PANEL_IDENTIFIER.application) as? PreferencesApplicationViewController)
        apps.uiStateDefaults = uiDefaults
        apps.runningApplications = { [] }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: true
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = preferences
        addTeardownBlock { window.close() }
        let undo = try XCTUnwrap(window.undoManager)
        undo.groupsByEvent = false
        return Window(window: window, preferences: preferences, undo: undo, gestures: gestures, apps: apps)
    }

    /// One user action: one group on the undo manager.
    private func step(_ undo: UndoManager, _ body: () throws -> Void) rethrows {
        undo.beginUndoGrouping()
        defer { undo.endUndoGrouping() }
        try body()
    }

    private func label(_ name: String) throws -> ShortcutLabel {
        return try XCTUnwrap(ShortcutLabel(name: name, icon: .symbol("square.and.arrow.down")))
    }

    /// The pane: Undo puts back the keys with their name and icon, selects the row (its
    /// pull-down has the keyboard) and the preview shows that direction; Redo makes the
    /// change again. A new name alone is a rename.
    func testUndoPutsBackADirectionWithItsNameAndIconAndRedoChangesItAgain() throws {
        let saved = GestureAction(action: Self.keys, label: try label("Save All"))
        Options.shared.gesture.actions.up = saved
        let w = try makeWindow()
        XCTAssertTrue(w.preferences.selectPane(withIdentifier: GesturesPreferencesViewController.tabIdentifier))
        w.gestures.directionsSection.setExpanded(true)
        let popUp = w.gestures.controls.actionPopUp(for: .up)
        XCTAssertEqual(popUp.binding.label, saved.label)

        try step(w.undo) { popUp.onShortcutSelected?(SystemShortcut.paste) }
        XCTAssertEqual(Options.shared.gesture.actions.up, GestureAction(SystemShortcut.paste))
        XCTAssertEqual(w.undo.undoMenuItemTitle, "Undo Change Action")
        w.window.makeFirstResponder(nil)

        w.undo.undo()
        XCTAssertEqual(Options.shared.gesture.actions.up, saved, "the keys with their name and icon")
        XCTAssertEqual(popUp.binding.label, saved.label, "the row shows them")
        XCTAssertTrue(w.window.firstResponder === popUp, "the row's pull-down has the keyboard")
        XCTAssertEqual(w.gestures.focusedSlot, .up, "the preview shows that direction")
        XCTAssertEqual(w.undo.redoMenuItemTitle, "Redo Change Action")

        w.undo.redo()
        XCTAssertEqual(Options.shared.gesture.actions.up, GestureAction(SystemShortcut.paste))
        XCTAssertEqual(popUp.binding.systemShortcutName, SystemShortcut.paste.identifier)
        w.undo.undo()
        XCTAssertEqual(Options.shared.gesture.actions.up, saved)

        // Only another name for the same keys.
        let renamed = GestureAction(action: Self.keys, label: try label("Keep"))
        try step(w.undo) { popUp.onCustomShortcutRecorded?(Self.keys, renamed.label) }
        XCTAssertEqual(Options.shared.gesture.actions.up, renamed)
        XCTAssertEqual(w.undo.undoMenuItemTitle, "Undo Rename", "as Buttons calls it")
        w.undo.undo()
        XCTAssertEqual(Options.shared.gesture.actions.up, saved)
        XCTAssertEqual(w.undo.redoMenuItemTitle, "Redo Rename")
    }

    /// From another pane: Gestures comes forward, its folded directions open and the row is
    /// selected.
    func testUndoFromAnotherPaneShowsGesturesWithTheRowSelected() throws {
        let w = try makeWindow()
        XCTAssertTrue(w.preferences.selectPane(withIdentifier: GesturesPreferencesViewController.tabIdentifier))
        let directions = try XCTUnwrap(w.gestures.directionsSection)
        XCTAssertTrue(directions.isCollapsible, "no button runs the gestures: the directions fold")
        directions.setExpanded(true)
        let popUp = w.gestures.controls.actionPopUp(for: .click)
        try step(w.undo) { popUp.onShortcutSelected?(nil) }
        XCTAssertEqual(Options.shared.gesture.actions.click, GestureAction.none)
        directions.setExpanded(false)

        XCTAssertTrue(w.preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.general))
        XCTAssertNil(w.gestures.view.window, "the pane is out of the window")
        w.undo.undo()
        XCTAssertEqual(Options.shared.gesture.actions.click, GestureActions.default.click)
        XCTAssertEqual(w.preferences.selectedPaneIdentifier, GesturesPreferencesViewController.tabIdentifier)
        XCTAssertTrue(directions.showsBody, "the directions open")
        XCTAssertTrue(w.window.firstResponder === popUp)
        XCTAssertEqual(popUp.binding.systemShortcutName, GestureActions.default.click.action)
    }

    /// Left while the desktops follow the hand: the row shows the swipe and takes no choice,
    /// so Undo puts the value back and brings nothing forward. Up, which takes a choice in
    /// that mode, still comes forward.
    func testUndoOfASidewaysDirectionWhileFollowingTheHandBringsNothingForward() throws {
        var driver = DockSwipeDriver.inert
        driver.isAvailable = { true }
        DockSwipeSynthesizer.shared.setTestingDriver(driver)
        addTeardownBlock { DockSwipeSynthesizer.shared.clearTestingDriver() }
        let w = try makeWindow()
        XCTAssertTrue(w.preferences.selectPane(withIdentifier: GesturesPreferencesViewController.tabIdentifier))
        w.gestures.directionsSection.setExpanded(true)
        let left = w.gestures.controls.actionPopUp(for: .left)
        let up = w.gestures.controls.actionPopUp(for: .up)
        XCTAssertTrue(left.isEnabled, "taps: the sideways rows take a choice")
        try step(w.undo) { left.onShortcutSelected?(SystemShortcut.paste) }
        try step(w.undo) { up.onShortcutSelected?(SystemShortcut.copy) }
        XCTAssertEqual(Options.shared.gesture.actions.left, GestureAction(SystemShortcut.paste))
        Options.shared.gesture.mode = .interactive
        w.gestures.reload()
        XCTAssertFalse(left.isEnabled, "the swipe owns sideways movement")

        XCTAssertTrue(w.preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.general))
        w.undo.undo()
        XCTAssertEqual(Options.shared.gesture.actions.up, GestureActions.default.up)
        XCTAssertEqual(w.preferences.selectedPaneIdentifier, GesturesPreferencesViewController.tabIdentifier, "Up comes forward")
        XCTAssertTrue(w.window.firstResponder === up)

        XCTAssertTrue(w.preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.general))
        w.undo.undo()
        XCTAssertEqual(Options.shared.gesture.actions.left, GestureActions.default.left, "the value is back")
        XCTAssertEqual(w.preferences.selectedPaneIdentifier, PANEL_IDENTIFIER.general, "nothing comes forward")
        w.undo.redo()
        XCTAssertEqual(Options.shared.gesture.actions.left, GestureAction(SystemShortcut.paste))
        XCTAssertEqual(w.preferences.selectedPaneIdentifier, PANEL_IDENTIFIER.general)
    }

    /// An app's own gestures, after its page closed and while General shows: Apps comes
    /// forward with the app's page on its Gestures part, the row selected; Redo too. The
    /// general gestures are never touched.
    func testUndoOfAnAppsDirectionAfterItsPageClosedOpensThePageWithTheRowSelected() throws {
        let calculator = Application(path: Self.calculator)
        Options.shared.application.applications.append(calculator)
        calculator.setUsesGeneralGestures(false, general: Options.shared.gesture)
        let w = try makeWindow()
        XCTAssertTrue(w.preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.application))
        w.apps.openApplication(withID: try XCTUnwrap(w.apps.rowID(for: calculator)), part: .gestures)
        let controls = try XCTUnwrap(w.apps.detailController?.gesturesPart.controls)
        try step(w.undo) { controls.actionPopUp(for: .down).onShortcutSelected?(SystemShortcut.paste) }
        XCTAssertEqual(calculator.ownGestures?.actions.down, GestureAction(SystemShortcut.paste))
        XCTAssertEqual(w.undo.undoMenuItemTitle, "Undo Change Action")

        w.apps.showList(focusList: false)
        XCTAssertNil(w.apps.detailController, "the page closed")
        XCTAssertTrue(w.preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.general))
        w.undo.undo()
        XCTAssertEqual(calculator.ownGestures?.actions.down, GestureActions.default.down)
        XCTAssertEqual(Options.shared.gesture, .default, "the general gestures are untouched")
        XCTAssertEqual(w.preferences.selectedPaneIdentifier, PANEL_IDENTIFIER.application)
        let page = try XCTUnwrap(w.apps.detailController)
        XCTAssertTrue(page.application === calculator)
        XCTAssertEqual(page.shownPart, .gestures)
        let part = try XCTUnwrap(page.gesturesPart)
        let shown = try XCTUnwrap(part.controls)
        XCTAssertEqual(shown.actionPopUp(for: .down).binding.systemShortcutName, GestureActions.default.down.action)
        XCTAssertEqual(part.directionsFold?.showsBody, true, "its folded rows open")
        XCTAssertTrue(w.window.firstResponder === shown.actionPopUp(for: .down))

        w.undo.redo()
        XCTAssertEqual(calculator.ownGestures?.actions.down, GestureAction(SystemShortcut.paste))
        XCTAssertEqual(shown.actionPopUp(for: .down).binding.systemShortcutName, SystemShortcut.paste.identifier, "the page on show follows")
        XCTAssertEqual(Options.shared.gesture, .default)
    }

    /// A direction of an app's own gestures, changed, then "Use settings from Gestures" is
    /// on again: the set is kept for later and its part shows the switch alone. Undo and
    /// Redo still reach the kept set, and nothing comes forward, from another pane or on
    /// the app's page. Regression: the app's Gestures part came forward with nothing
    /// changed in sight.
    func testUndoOfADirectionOfASetKeptForLaterBringsNothingForward() throws {
        let calculator = Application(path: Self.calculator)
        Options.shared.application.applications.append(calculator)
        calculator.setUsesGeneralGestures(false, general: Options.shared.gesture)
        let w = try makeWindow()
        XCTAssertTrue(w.preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.application))
        w.apps.openApplication(withID: try XCTUnwrap(w.apps.rowID(for: calculator)), part: .gestures)
        let page = try XCTUnwrap(w.apps.detailController)
        let controls = try XCTUnwrap(page.gesturesPart.controls)
        try step(w.undo) { controls.actionPopUp(for: .up).onShortcutSelected?(SystemShortcut.paste) }
        calculator.setUsesGeneralGestures(true, general: Options.shared.gesture)
        page.gesturesPart.syncViewWithOptions()

        // On the app's page, another part on show: it stays.
        page.show(.scrolling)
        w.undo.undo()
        XCTAssertEqual(calculator.gestures?.actions.up, GestureActions.default.up, "the kept set has its direction back")
        XCTAssertTrue(calculator.usesGeneralGestures)
        XCTAssertEqual(page.shownPart, .scrolling, "the part on show stays")

        // From another pane, the page closed: nothing comes forward.
        w.apps.showList(focusList: false)
        XCTAssertTrue(w.preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.general))
        w.undo.redo()
        XCTAssertEqual(calculator.gestures?.actions.up, GestureAction(SystemShortcut.paste))
        XCTAssertEqual(w.preferences.selectedPaneIdentifier, PANEL_IDENTIFIER.general, "nothing comes forward")
        XCTAssertNil(w.apps.detailController)
        XCTAssertEqual(Options.shared.gesture, .default, "the general gestures are untouched")
    }

    // MARK: - Undo of a step of the whole pane or part, shown where it acts too

    /// "Undo Reset Gestures" from another pane (⌘Z after a slider elsewhere, which
    /// registers nothing): Gestures comes forward and shows the settings that are back;
    /// Redo too. The reset itself, clicked on the pane, moves nothing.
    func testUndoOfTheGesturesResetFromAnotherPaneShowsGestures() throws {
        Options.shared.gesture.actions.up = GestureAction(SystemShortcut.paste)
        let edited = Options.shared.gesture
        let w = try makeWindow()
        XCTAssertTrue(w.preferences.selectPane(withIdentifier: GesturesPreferencesViewController.tabIdentifier))
        step(w.undo) { w.gestures.resetToDefaults.click(nil) }
        XCTAssertEqual(Options.shared.gesture, .default)
        XCTAssertEqual(w.undo.undoMenuItemTitle, "Undo Reset Gestures")
        XCTAssertEqual(w.preferences.selectedPaneIdentifier, GesturesPreferencesViewController.tabIdentifier)

        XCTAssertTrue(w.preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.general))
        w.undo.undo()
        XCTAssertEqual(Options.shared.gesture, edited)
        XCTAssertEqual(w.preferences.selectedPaneIdentifier, GesturesPreferencesViewController.tabIdentifier, "the pane comes forward")
        XCTAssertEqual(
            w.gestures.controls.actionPopUp(for: .up).binding.systemShortcutName, SystemShortcut.paste.identifier, "and shows them"
        )

        XCTAssertTrue(w.preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.general))
        w.undo.redo()
        XCTAssertEqual(Options.shared.gesture, .default)
        XCTAssertEqual(w.preferences.selectedPaneIdentifier, GesturesPreferencesViewController.tabIdentifier, "Redo too")
    }

    /// "Undo Change Button to Hold" from another pane: the Back button has its action
    /// again and nothing runs the gestures, and Gestures comes forward with its row saying
    /// so; Redo too.
    func testUndoOfTheButtonToHoldFromAnotherPaneShowsGestures() throws {
        let back = RecordedEvent(type: .mouse, code: 3, modifiers: 0, deviceFilter: nil)
        let copy = ButtonBinding(triggerEvent: back, systemShortcutName: SystemShortcut.copy.identifier, isEnabled: true)
        Options.shared.buttons.binding = [copy]
        let w = try makeWindow()
        w.gestures.bindingSummary = { .current }
        XCTAssertTrue(w.preferences.selectPane(withIdentifier: GesturesPreferencesViewController.tabIdentifier))
        let chooser = try XCTUnwrap(w.gestures.triggerChooser)
        chooser.deviceSource = ButtonsDeviceSource(
            captureStatus: { _ in .normal }, deviceName: { nil }, isBusy: { false }, refresh: {}, warnBluetoothButton: { _ in }
        )
        step(w.undo) { chooser.choose(back) }
        XCTAssertEqual(Options.shared.buttons.binding.first?.systemShortcutName, SystemShortcut.mouseGestureNavigation.identifier)
        XCTAssertEqual(w.undo.undoMenuItemTitle, "Undo Change Button to Hold")
        let name = ButtonTriggerNaming.title(for: back)
        XCTAssertEqual(w.gestures.gestureButtonButton.shownTitle, name)

        XCTAssertTrue(w.preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.scrolling))
        w.undo.undo()
        XCTAssertEqual(Options.shared.buttons.binding, [copy], "Back is Copy again")
        XCTAssertEqual(w.preferences.selectedPaneIdentifier, GesturesPreferencesViewController.tabIdentifier, "the pane comes forward")
        XCTAssertEqual(w.gestures.gestureButtonButton.shownTitle, "Choose", "its row says that no button runs the gestures")

        XCTAssertTrue(w.preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.scrolling))
        w.undo.redo()
        XCTAssertEqual(Options.shared.buttons.binding.first?.systemShortcutName, SystemShortcut.mouseGestureNavigation.identifier)
        XCTAssertEqual(w.preferences.selectedPaneIdentifier, GesturesPreferencesViewController.tabIdentifier, "Redo too")
        XCTAssertEqual(w.gestures.gestureButtonButton.shownTitle, name)
    }

    /// "Copy from Gestures" under an app's own set, undone after its page closed and while
    /// General shows, and redone while the page shows another part: Apps comes forward with
    /// the app's page on its Gestures part. A set kept for later (the switch on again)
    /// takes the Undo too, and nothing comes forward: the part would show the switch alone.
    func testUndoOfCopyFromGesturesShowsTheAppsGesturesPartUnlessTheSetIsKeptForLater() throws {
        let calculator = Application(path: Self.calculator)
        Options.shared.application.applications.append(calculator)
        calculator.setUsesGeneralGestures(false, general: Options.shared.gesture)
        var actions = GestureActions.default
        actions.up = GestureAction(SystemShortcut.paste)
        calculator.setOwnGestures(actions: actions, invertHorizontal: true)
        let edited = try XCTUnwrap(calculator.ownGestures)
        let w = try makeWindow()
        XCTAssertTrue(w.preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.application))
        w.apps.openApplication(withID: try XCTUnwrap(w.apps.rowID(for: calculator)), part: .gestures)
        let part = try XCTUnwrap(w.apps.detailController?.gesturesPart)
        step(w.undo) { part.resetToDefaults.click(nil) }
        XCTAssertEqual(calculator.ownGestures?.actions, GestureActions.default)
        XCTAssertEqual(w.undo.undoMenuItemTitle, "Undo Copy from Gestures in Calculator")

        w.apps.showList(focusList: false)
        XCTAssertTrue(w.preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.general))
        w.undo.undo()
        XCTAssertEqual(calculator.ownGestures, edited)
        XCTAssertEqual(w.preferences.selectedPaneIdentifier, PANEL_IDENTIFIER.application, "Apps comes forward")
        let page = try XCTUnwrap(w.apps.detailController)
        XCTAssertTrue(page.application === calculator)
        XCTAssertEqual(page.shownPart, .gestures)
        XCTAssertEqual(
            page.gesturesPart.controls?.actionPopUp(for: .up).binding.systemShortcutName, SystemShortcut.paste.identifier,
            "the page shows the set that is back"
        )

        page.show(.buttons)
        w.undo.redo()
        XCTAssertEqual(calculator.ownGestures?.actions, GestureActions.default)
        XCTAssertEqual(page.shownPart, .gestures, "Redo shows its part too")

        // Kept for later: the Undo reaches it, out of sight as the set is.
        calculator.setUsesGeneralGestures(true, general: Options.shared.gesture)
        w.apps.showList(focusList: false)
        XCTAssertTrue(w.preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.general))
        w.undo.undo()
        XCTAssertEqual(calculator.gestures?.actions, edited.actions, "the kept set is back as it was")
        XCTAssertTrue(calculator.usesGeneralGestures)
        XCTAssertEqual(w.preferences.selectedPaneIdentifier, PANEL_IDENTIFIER.general, "nothing comes forward")
    }

    /// The pane in a window of its own (no window's panes): Undo and Redo go to that
    /// window's undo manager and show on the pane. Out of any window nothing asks for one.
    func testThePaneInAWindowOfItsOwnTakesUndoAndShowsIt() throws {
        let pane = GesturesPreferencesViewController()
        pane.deviceSource = MouseGestureDeviceSource(support: { .none }, refresh: {})
        pane.bindingSummary = { MouseGestureBindingSummary(hasGestureButton: true, hasLogitechGestureButton: false, buttonTitles: ["Back button"]) }
        _ = pane.view
        pane.controls.actionPopUp(for: .up).onShortcutSelected?(SystemShortcut.copy)
        XCTAssertEqual(Options.shared.gesture.actions.up, GestureAction(SystemShortcut.copy), "stored, with nothing to undo it")

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 800), styleMask: [.titled], backing: .buffered, defer: true
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = pane
        addTeardownBlock { window.close() }
        let undo = try XCTUnwrap(window.undoManager)
        undo.groupsByEvent = false
        XCTAssertFalse(undo.canUndo)
        try step(undo) { pane.controls.actionPopUp(for: .up).onShortcutSelected?(SystemShortcut.paste) }
        undo.undo()
        XCTAssertEqual(Options.shared.gesture.actions.up, GestureAction(SystemShortcut.copy))
        XCTAssertEqual(pane.controls.actionPopUp(for: .up).binding.systemShortcutName, SystemShortcut.copy.identifier)
        XCTAssertTrue(window.firstResponder === pane.controls.actionPopUp(for: .up))
        XCTAssertFalse(undo.canUndo)
        undo.redo()
        XCTAssertEqual(Options.shared.gesture.actions.up, GestureAction(SystemShortcut.paste))
    }
}
