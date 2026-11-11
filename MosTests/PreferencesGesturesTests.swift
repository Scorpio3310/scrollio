//
//  PreferencesGesturesTests.swift
//  MosTests
//
//  Gestures tab: its rows in the boxes of System Settings, every control writes its own
//  field of Options.shared.gesture and follows the mode rules, the tracking speed, the
//  line about the gesture button, the controls it shares with the Gesture Settings
//  popover, and the preview following the settings and the row pointed at. The Logitech
//  box has its own tests (LogiGestureSectionTests). Nothing is shown on screen and no HID
//  device is touched.
//

import XCTest
@testable import Mos_Debug

final class PreferencesGesturesTests: XCTestCase {

    private typealias Slot = MouseGestureSettingsControls.Slot

    private var savedGesture = MouseGestureSettings.default
    private var isInteractiveAvailable = true
    private var summary = MouseGestureBindingSummary(hasGestureButton: true, hasLogitechGestureButton: false)

    override func setUp() {
        super.setUp()
        savedGesture = Options.shared.gesture
        Options.shared.gesture = .default
        isInteractiveAvailable = true
        summary = MouseGestureBindingSummary(hasGestureButton: true, hasLogitechGestureButton: false)
    }

    override func tearDown() {
        Options.shared.gesture = savedGesture
        super.tearDown()
    }

    private func makeController() -> GesturesPreferencesViewController {
        let controller = GesturesPreferencesViewController(isInteractiveAvailable: { [weak self] in
            self?.isInteractiveAvailable ?? true
        })
        controller.deviceSource = MouseGestureDeviceSource(support: { .none }, refresh: {})
        controller.bindingSummary = { [weak self] in
            self?.summary ?? MouseGestureBindingSummary(hasGestureButton: false, hasLogitechGestureButton: false)
        }
        _ = controller.view
        return controller
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

    /// The menu item of `popup` that stores `identifier` ("" is "No Action").
    private func item(_ identifier: String, in popup: NSPopUpButton) -> NSMenuItem? {
        let top = popup.menu?.items ?? []
        let nested = top.compactMap(\.submenu).flatMap(\.items)
        return (top + nested).first { ($0.representedObject as? String) == identifier && $0.action != nil }
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
        XCTAssertTrue(GesturesPreferencesViewController.tabImage().isTemplate)
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
        XCTAssertEqual(controller.trackingSpeedRow.lowEndLabel?.stringValue, "Slower")
        XCTAssertEqual(controller.trackingSpeedRow.highEndLabel?.stringValue, "Faster")
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
        XCTAssertEqual(controller.trackingSpeedSlider.doubleValue, 2.2, accuracy: 1e-9)
        XCTAssertEqual(controller.trackingSpeedRow.valueText, "2.2×")
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
        XCTAssertEqual(controller.trackingSpeedSlider.doubleValue, 1.8, accuracy: 1e-9)
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
        XCTAssertEqual(controller.trackingSpeedRow.valueText, "1.0×")
        XCTAssertEqual(slider.accessibilityLabel(), "Tracking speed")
        XCTAssertEqual(slider.identifier, GesturesPreferencesViewController.Identifier.trackingSpeed)
    }

    func testTrackingSpeedSliderWritesRoundedMultiplier() {
        Options.shared.gesture.mode = .interactive
        let controller = makeController()
        let slider = controller.trackingSpeedSlider

        slider.doubleValue = 1.74
        send(slider)
        XCTAssertEqual(Options.shared.gesture.trackingSpeed, 1.7, accuracy: 1e-9)
        XCTAssertEqual(controller.trackingSpeedRow.valueText, "1.7×")
        XCTAssertEqual(controller.previewView.scene.gesture.trackingSpeed, 1.7, accuracy: 1e-9)

        slider.doubleValue = 3
        send(slider)
        XCTAssertEqual(Options.shared.gesture.trackingSpeed, 3, accuracy: 1e-9)
        XCTAssertEqual(controller.trackingSpeedRow.valueText, "3.0×")

        // Nothing else moved.
        var expected = MouseGestureSettings.default
        expected.mode = .interactive
        expected.trackingSpeed = 3
        XCTAssertEqual(Options.shared.gesture, expected)
    }

    func testTrackingSpeedValues() {
        XCTAssertEqual(MouseGestureTrackingSpeed.snapped(0.1), 0.5)
        XCTAssertEqual(MouseGestureTrackingSpeed.snapped(9), 3)
        XCTAssertEqual(MouseGestureTrackingSpeed.snapped(1.26), 1.3, accuracy: 1e-9)
        XCTAssertEqual(MouseGestureTrackingSpeed.snapped(.nan), 0.5)
        XCTAssertEqual(MouseGestureTrackingSpeed.text(0.5), "0.5×")
        XCTAssertEqual(MouseGestureTrackingSpeed.text(1), "1.0×")
        XCTAssertEqual(MouseGestureTrackingSpeed.text(2.5), "2.5×")
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

    // MARK: - The gesture button

    func testWithoutAGestureButtonTheFirstBoxSaysSo() {
        summary = MouseGestureBindingSummary(hasGestureButton: false, hasLogitechGestureButton: false)
        let controller = makeController()
        XCTAssertFalse(controller.unboundRow.isHidden)
        XCTAssertEqual(controller.unboundRow.title, text("gestures-unbound-title"))
        XCTAssertEqual(controller.unboundRow.explanation, text("gestures-unbound-hint"))
        XCTAssertTrue(controller.buttonsNoteLabel.isHidden, "said once, in the first box")
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(frame(of: controller.unboundRow, in: controller).minY, frame(of: controller.modeRow, in: controller).maxY - 0.5, "above the mode")

        summary = MouseGestureBindingSummary(hasGestureButton: true, hasLogitechGestureButton: false)
        controller.reload()
        XCTAssertTrue(controller.unboundRow.isHidden)
        XCTAssertFalse(controller.buttonsNoteLabel.isHidden)
        XCTAssertEqual(controller.buttonsNoteLabel.stringValue, "Choose the gesture button under Buttons.")
        XCTAssertEqual(controller.view.frame.size, controller.view.fittingSize)
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
        XCTAssertEqual(plain, MouseGestureBindingSummary(hasGestureButton: true, hasLogitechGestureButton: false))

        let logitech = MouseGestureBindingSummary(
            bindings: [binding(SystemShortcut.mouseGestureNavigation, code: 1000)],
            isLogitechCode: isLogitech
        )
        XCTAssertEqual(logitech, MouseGestureBindingSummary(hasGestureButton: true, hasLogitechGestureButton: true))

        let disabled = MouseGestureBindingSummary(
            bindings: [binding(SystemShortcut.mouseGestureNavigation, code: 1000, enabled: false)],
            isLogitechCode: isLogitech
        )
        XCTAssertEqual(disabled, MouseGestureBindingSummary(hasGestureButton: false, hasLogitechGestureButton: false))
    }

    // MARK: - The preview

    func testThePreviewShowsTheSettingsInEffect() {
        let controller = makeController()
        let preview = controller.previewView!
        XCTAssertEqual(preview.identifier, GesturesPreferencesViewController.Identifier.preview)
        XCTAssertEqual(preview.scene, GesturePreviewScene(gesture: .default, focus: nil))
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

    // MARK: - Shared with the popover

    func testThePopoverShowsTheSameControlsAndStillWorks() throws {
        let popover = MouseGestureSettingsPopover(isInteractiveAvailable: { true })
        let view = popover.makeContentViewController().view

        func find(_ id: NSUserInterfaceItemIdentifier, in view: NSView) -> NSView? {
            if view.identifier == id { return view }
            for subview in view.subviews {
                if let match = find(id, in: subview) { return match }
            }
            return nil
        }
        typealias ID = MouseGestureSettingsControls.Identifier
        let mode = try XCTUnwrap(find(ID.mode, in: view) as? NSSegmentedControl)
        let freeze = try XCTUnwrap(find(ID.freezePointer, in: view) as? NSButton, "the popover keeps its checkboxes")
        for slot in Slot.allCases {
            XCTAssertNotNil(find(ID.action(slot.name), in: view) as? NSPopUpButton, slot.name)
        }
        let invert = try XCTUnwrap(find(ID.invertHorizontal, in: view) as? NSButton)
        XCTAssertEqual(invert.title, "Invert left and right")
        XCTAssertEqual(freeze.title, "Freeze pointer during a gesture")
        XCTAssertEqual((find(ID.modeNote, in: view) as? NSTextField)?.stringValue, text("gesture-mode-interactive-note"))
        // The popover is the short version: tracking speed is in the tab only.
        XCTAssertNil(find(GesturesPreferencesViewController.Identifier.trackingSpeed, in: view))

        mode.selectedSegment = 1
        send(mode)
        freeze.state = .off
        send(freeze)
        XCTAssertEqual(Options.shared.gesture.mode, .interactive)
        XCTAssertFalse(Options.shared.gesture.freezePointer)

        // The tab shows what the popover changed.
        let controller = makeController()
        XCTAssertEqual(controller.controls.modeControl.selectedSegment, 1)
        XCTAssertFalse(MouseGestureSettingsControls.isOn(controller.controls.freezeToggle))
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
            "gestures-unbound-title", "gestures-unbound-hint",
            "gestures-directions-header", "gestures-directions-hint", "gestures-behaviour-header",
            "gestures-logitech-needs", "gestures-buttons-note",
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
/// supports the Logitech options, without a gesture button, light and dark. Off screen the
/// window's material draws a flat grey and vibrant text is not blended, so text looks a
/// little dimmer than on screen. Only runs when asked to:
/// `TEST_RUNNER_GESTURES_SHOTS_DIR=<folder> xcodebuild … test -only-testing:MosTests/PreferencesGesturesRenderTests`.
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
        guard let folder = ProcessInfo.processInfo.environment["GESTURES_SHOTS_DIR"], !folder.isEmpty else {
            throw XCTSkip("set TEST_RUNNER_GESTURES_SHOTS_DIR to render the Gestures tab")
        }
        let directory = URL(fileURLWithPath: folder, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

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
                MouseGestureBindingSummary(hasGestureButton: item.bound, hasLogitechGestureButton: item.support.deviceTracking)
            }
            _ = controller.view
            // The preview still: the desktops half-way, or the action fully shown.
            controller.previewView.prefersReducedMotion = { true }
            controller.previewView.reduceMotionDidChange()
            try render(controller.view, name: "tab-\(item.name)", into: directory)
        }
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
