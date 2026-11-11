//
//  PreferencesGesturesTests.swift
//  MosTests
//
//  Gestures tab: its controls write Options.shared.gesture and follow the mode rules,
//  the tracking speed slider, the hint about bound buttons, and the controls it shares
//  with the Gesture Settings popover. The Logitech section has its own tests
//  (LogiGestureSectionTests). Nothing is shown on screen and no HID device is touched.
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

    // MARK: - Pane

    func testPaneIsTitledGesturesAndFitsThePreferencesWidth() {
        let controller = makeController()
        XCTAssertEqual(controller.title, "Gestures")
        XCTAssertEqual(GesturesPreferencesViewController.tabIdentifier, "gestures")
        XCTAssertEqual(controller.view.frame.width, PreferencesForm.contentWidth)
        XCTAssertEqual(controller.view.frame.size, controller.view.fittingSize)
        XCTAssertTrue(GesturesPreferencesViewController.tabImage().isTemplate)
    }

    func testControlsSitOnTheFormGrid() {
        let controller = makeController()
        controller.view.layoutSubtreeIfNeeded()
        let controls = controller.controls!
        let views: [NSView] = [controls.modeControl] + controls.actionPopUps
        for view in views {
            let frame = controller.view.convert(view.alignmentRect(forFrame: view.frame), from: view.superview)
            XCTAssertEqual(frame.minX, 171, accuracy: 0.5, "\(view.identifier?.rawValue ?? "")")
            XCTAssertEqual(frame.maxX, 430, accuracy: 0.5, "\(view.identifier?.rawValue ?? "")")
        }
        XCTAssertEqual(controls.actionPopUps.count, 5)
        // Up, Down, Left, Right, Click from top to bottom (the root view is not flipped).
        let tops = controls.actionPopUps.map { controller.view.convert($0.bounds, from: $0).maxY }
        XCTAssertEqual(tops, tops.sorted(by: >))
    }

    // MARK: - Controls write Options.shared.gesture

    func testModeControlWritesTheMode() {
        let controller = makeController()
        let mode = controller.controls.modeControl
        XCTAssertEqual(mode.segmentCount, 2)
        XCTAssertEqual(mode.label(forSegment: 0), "One action per hold")
        XCTAssertEqual(mode.label(forSegment: 1), "Follow the hand")
        XCTAssertEqual(mode.selectedSegment, 0)

        mode.selectedSegment = 1
        send(mode)
        XCTAssertEqual(Options.shared.gesture.mode, .interactive)

        mode.selectedSegment = 0
        send(mode)
        XCTAssertEqual(Options.shared.gesture.mode, .discrete)
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

    func testCheckboxesWriteInvertAndFreeze() {
        let controller = makeController()
        let controls = controller.controls!
        XCTAssertEqual(controls.invertCheckbox.title, "Invert left and right")
        XCTAssertEqual(controls.freezeCheckbox.title, "Freeze pointer during gesture")
        XCTAssertEqual(controls.invertCheckbox.state, .off)
        XCTAssertEqual(controls.freezeCheckbox.state, .on)

        controls.invertCheckbox.state = .on
        send(controls.invertCheckbox)
        controls.freezeCheckbox.state = .off
        send(controls.freezeCheckbox)

        XCTAssertTrue(Options.shared.gesture.invertHorizontal)
        XCTAssertFalse(Options.shared.gesture.freezePointer)
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
        XCTAssertEqual(controls.invertCheckbox.state, .on)
        XCTAssertEqual(controls.freezeCheckbox.state, .off)
        XCTAssertEqual(controls.trackingSpeedSlider.doubleValue, 2.2, accuracy: 1e-9)
        XCTAssertEqual(controls.trackingSpeedValueLabel.stringValue, "2.2×")
    }

    func testReloadPicksUpChangesMadeElsewhere() {
        let controller = makeController()
        // The popover in the Buttons tab changed the settings meanwhile.
        Options.shared.gesture.mode = .interactive
        Options.shared.gesture.downAction = SystemShortcut.copy.identifier
        Options.shared.gesture.freezePointer = false

        controller.viewWillAppear()

        let controls = controller.controls!
        XCTAssertEqual(controls.modeControl.selectedSegment, 1)
        XCTAssertEqual(title(of: controls.actionPopUp(for: .down)), SystemShortcut.copy.localizedName)
        XCTAssertEqual(controls.freezeCheckbox.state, .off)
        XCTAssertTrue(controls.trackingSpeedSlider.isEnabled)
    }

    // MARK: - Tracking speed

    func testTrackingSpeedSliderCoversTheStoredRange() {
        let controller = makeController()
        let slider = controller.controls.trackingSpeedSlider
        XCTAssertEqual(slider.minValue, MouseGestureSettings.trackingSpeedRange.lowerBound)
        XCTAssertEqual(slider.maxValue, MouseGestureSettings.trackingSpeedRange.upperBound)
        XCTAssertEqual(slider.minValue, 0.5)
        XCTAssertEqual(slider.maxValue, 3)
        XCTAssertEqual(slider.doubleValue, 1, accuracy: 1e-9)
        XCTAssertEqual(controller.controls.trackingSpeedValueLabel.stringValue, "1.0×")
        XCTAssertEqual(slider.accessibilityLabel(), "Tracking Speed")
    }

    func testTrackingSpeedSliderWritesRoundedMultiplier() {
        Options.shared.gesture.mode = .interactive
        let controller = makeController()
        let controls = controller.controls!

        controls.trackingSpeedSlider.doubleValue = 1.74
        send(controls.trackingSpeedSlider)
        XCTAssertEqual(Options.shared.gesture.trackingSpeed, 1.7, accuracy: 1e-9)
        XCTAssertEqual(controls.trackingSpeedValueLabel.stringValue, "1.7×")

        controls.trackingSpeedSlider.doubleValue = 3
        send(controls.trackingSpeedSlider)
        XCTAssertEqual(Options.shared.gesture.trackingSpeed, 3, accuracy: 1e-9)
        XCTAssertEqual(controls.trackingSpeedValueLabel.stringValue, "3.0×")

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
        XCTAssertFalse(controls.trackingSpeedSlider.isEnabled, "one action per hold")

        controls.modeControl.selectedSegment = 1
        send(controls.modeControl)
        XCTAssertTrue(controls.trackingSpeedSlider.isEnabled)

        controls.modeControl.selectedSegment = 0
        send(controls.modeControl)
        XCTAssertFalse(controls.trackingSpeedSlider.isEnabled)
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
            XCTAssertEqual(title(of: controls.actionPopUp(for: slot)), "Desktop follows the hand", slot.name)
        }
        for slot in [Slot.up, .down, .click] {
            XCTAssertTrue(controls.actionPopUp(for: slot).isEnabled, slot.name)
        }
        XCTAssertTrue(controls.invertCheckbox.isEnabled)
        XCTAssertTrue(controls.freezeCheckbox.isEnabled)
        // The stored actions survive for the other mode.
        XCTAssertEqual(Options.shared.gesture.leftAction, SystemShortcut.moveSpaceLeft.identifier)
        XCTAssertEqual(Options.shared.gesture.rightAction, SystemShortcut.moveSpaceRight.identifier)

        controls.modeControl.selectedSegment = 0
        send(controls.modeControl)
        XCTAssertTrue(controls.actionPopUp(for: .left).isEnabled)
        XCTAssertEqual(title(of: controls.actionPopUp(for: .left)), SystemShortcut.moveSpaceLeft.localizedName)
    }

    func testFollowModeCannotBePickedWhereItIsUnavailable() {
        isInteractiveAvailable = false
        Options.shared.gesture.mode = .interactive
        let controller = makeController()
        let controls = controller.controls!

        XCTAssertEqual(controls.modeControl.selectedSegment, 0, "discrete is what runs, so it is shown")
        XCTAssertFalse(controls.modeControl.isEnabled(forSegment: 1))
        XCTAssertEqual(controls.modeNote.stringValue, text("gesture-mode-interactive-unavailable"))
        XCTAssertTrue(controls.actionPopUp(for: .left).isEnabled)
        XCTAssertFalse(controls.trackingSpeedSlider.isEnabled)
        XCTAssertEqual(Options.shared.gesture.mode, .interactive, "the stored choice is kept")

        Options.shared.gesture.mode = .discrete
        controls.modeControl.selectedSegment = 1
        send(controls.modeControl)
        XCTAssertEqual(Options.shared.gesture.mode, .discrete)
        XCTAssertEqual(controls.modeControl.selectedSegment, 0)
    }

    func testModePresentationSaysWhenTrackingSpeedApplies() {
        typealias Presentation = MouseGestureModePresentation
        XCTAssertFalse(Presentation.make(storedMode: .discrete, isInteractiveAvailable: true).isTrackingSpeedEditable)
        XCTAssertTrue(Presentation.make(storedMode: .interactive, isInteractiveAvailable: true).isTrackingSpeedEditable)
        XCTAssertFalse(Presentation.make(storedMode: .interactive, isInteractiveAvailable: false).isTrackingSpeedEditable)
    }

    // MARK: - Bound buttons

    func testHintSaysHowToGestureOrThatNoButtonIsSetUp() {
        summary = MouseGestureBindingSummary(hasGestureButton: false, hasLogitechGestureButton: false)
        let controller = makeController()
        XCTAssertEqual(controller.actionsHintLabel.stringValue, text("gestures-actions-hint-unbound"))

        summary = MouseGestureBindingSummary(hasGestureButton: true, hasLogitechGestureButton: false)
        controller.reload()
        XCTAssertEqual(controller.actionsHintLabel.stringValue, text("gestures-actions-hint"))
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
        XCTAssertEqual(none.actionsHintKey, "gestures-actions-hint-unbound")

        let plain = MouseGestureBindingSummary(
            bindings: [binding(SystemShortcut.mouseGestureNavigation, code: 3), binding(SystemShortcut.copy, code: 1000)],
            isLogitechCode: isLogitech
        )
        XCTAssertEqual(plain, MouseGestureBindingSummary(hasGestureButton: true, hasLogitechGestureButton: false))
        XCTAssertEqual(plain.actionsHintKey, "gestures-actions-hint")

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
        let freeze = try XCTUnwrap(find(ID.freezePointer, in: view) as? NSButton)
        for slot in Slot.allCases {
            XCTAssertNotNil(find(ID.action(slot.name), in: view) as? NSPopUpButton, slot.name)
        }
        XCTAssertNotNil(find(ID.invertHorizontal, in: view) as? NSButton)
        // The popover is the short version: tracking speed is in the tab only.
        XCTAssertNil(find(ID.trackingSpeed, in: view))

        mode.selectedSegment = 1
        send(mode)
        freeze.state = .off
        send(freeze)
        XCTAssertEqual(Options.shared.gesture.mode, .interactive)
        XCTAssertFalse(Options.shared.gesture.freezePointer)

        // The tab shows what the popover changed.
        let controller = makeController()
        XCTAssertEqual(controller.controls.modeControl.selectedSegment, 1)
        XCTAssertEqual(controller.controls.freezeCheckbox.state, .off)
    }

    // MARK: - Strings

    func testEveryLocaleTranslatesTheGesturesTab() {
        let missing = "\u{1}missing"
        let app = Bundle(for: PreferencesTabViewController.self)
        let keys = [
            "gestures-tab-title", "gesture-mode-label", "gesture-options-label",
            "gesture-tracking-speed-label", "gesture-tracking-speed-hint",
            "gestures-actions-hint", "gestures-actions-hint-unbound",
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
            }
        }
    }
}
