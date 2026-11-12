import XCTest
@testable import Scrollio_Debug

/// The "Logitech mouse" box of the Gestures tab: two switches bound to the shared gesture
/// settings. The box shows when a connected mouse can do at least one of them (a switch
/// it cannot do is disabled and says why); without such a mouse a muted line says what
/// is needed. While the mouse has its haptics off because the user switched them off
/// under Mouse, a muted line under the box says so and leads there. Capabilities come from
/// fixtures; no HID device is touched. (The section lived in the Mouse tab before.)
final class LogiGestureSectionTests: XCTestCase {

    private var savedGesture = MouseGestureSettings.default
    private var savedMouse = LogiMouseSettings.default
    private var support = MouseGestureDeviceSupport.none
    private var refreshCount = 0

    override func setUp() {
        super.setUp()
        savedGesture = Options.shared.gesture
        savedMouse = Options.shared.logiMouse
        Options.shared.gesture = .default
        Options.shared.logiMouse = .default
        support = .none
        refreshCount = 0
    }

    override func tearDown() {
        Options.shared.gesture = savedGesture
        Options.shared.logiMouse = savedMouse
        super.tearDown()
    }

    private func makeController() -> GesturesPreferencesViewController {
        let controller = GesturesPreferencesViewController(isInteractiveAvailable: { true })
        controller.deviceSource = MouseGestureDeviceSource(
            support: { [weak self] in self?.support ?? .none },
            refresh: { [weak self] in self?.refreshCount += 1 }
        )
        controller.bindingSummary = { MouseGestureBindingSummary(hasGestureButton: true, hasLogitechGestureButton: true) }
        _ = controller.view
        controller.reload()
        return controller
    }

    private func send(_ control: NSControl) {
        XCTAssertTrue(control.sendAction(control.action, to: control.target))
    }

    private func set(_ toggle: NSSwitch, on: Bool) {
        toggle.state = on ? .on : .off
        send(toggle)
    }

    private func text(_ key: String) -> String {
        return NSLocalizedString(key, comment: "")
    }

    // MARK: - Rules

    func testRulesTable() {
        let none = MouseGestureControlRules(support: .none)
        XCTAssertFalse(none.deviceTrackingEnabled)
        XCTAssertFalse(none.hapticsEnabled)
        XCTAssertEqual(none.deviceTrackingHintKey, "mouse-gesture-device-tracking-unavailable")
        XCTAssertEqual(none.hapticsHintKey, "mouse-gesture-haptics-unavailable")

        // MX Master 3 / 3S: raw XY, no haptic motor.
        let master3 = MouseGestureControlRules(support: MouseGestureDeviceSupport(deviceTracking: true, haptics: false))
        XCTAssertTrue(master3.deviceTrackingEnabled)
        XCTAssertFalse(master3.hapticsEnabled)
        XCTAssertEqual(master3.deviceTrackingHintKey, "mouse-gesture-device-tracking-hint")
        XCTAssertEqual(master3.hapticsHintKey, "mouse-gesture-haptics-unavailable")

        // MX Master 4: both.
        let master4 = MouseGestureControlRules(support: MouseGestureDeviceSupport(deviceTracking: true, haptics: true))
        XCTAssertTrue(master4.deviceTrackingEnabled)
        XCTAssertTrue(master4.hapticsEnabled)
        XCTAssertEqual(master4.hapticsHintKey, "mouse-gesture-haptics-hint")

        // The box shows for a mouse that can do at least one of the two.
        XCTAssertFalse(none.showsOptions)
        XCTAssertTrue(master3.showsOptions)
        XCTAssertTrue(master4.showsOptions)
        XCTAssertTrue(MouseGestureControlRules(support: MouseGestureDeviceSupport(deviceTracking: false, haptics: true)).showsOptions)
    }

    func testOpeningTheTabAsksTheMiceAgain() {
        let controller = makeController()
        XCTAssertEqual(refreshCount, 0)
        controller.viewWillAppear()
        XCTAssertEqual(refreshCount, 1)
    }

    func testTheMouseTabNoLongerHoldsTheSection() {
        let mouse = MousePreferencesViewController()
        mouse.deviceSource = MouseDeviceSource(deviceStates: { [] }, refresh: {})
        _ = mouse.view
        mouse.reloadDevices()
        let titles = Self.allSubviews(of: mouse.view).compactMap { ($0 as? NSButton)?.title }
        XCTAssertFalse(titles.contains(text("mouse-gesture-device-tracking")))
        XCTAssertFalse(titles.contains(text("mouse-gesture-haptics")))
    }

    private static func allSubviews(of view: NSView) -> [NSView] {
        return view.subviews.flatMap { [$0] + allSubviews(of: $0) }
    }

    // MARK: - Controls

    func testWithoutASupportingMouseALineSaysWhatIsNeeded() {
        Options.shared.gesture.deviceTracking = true
        let controller = makeController()

        XCTAssertTrue(controller.logitechSection.isHidden)
        XCTAssertFalse(controller.logitechNeedsLabel.superview?.isHidden ?? true)
        XCTAssertEqual(controller.logitechNeedsLabel.stringValue, text("gestures-logitech-needs"))
        XCTAssertTrue(controller.logitechNeedsLabel.stringValue.contains("MX Master"))
        // The rules still apply to the hidden switches, and the stored choices stay
        // untouched for when a mouse connects.
        XCTAssertFalse(controller.deviceTrackingSwitch.isEnabled)
        XCTAssertFalse(controller.hapticsSwitch.isEnabled)
        XCTAssertEqual(controller.deviceTrackingRow.explanation, text("mouse-gesture-device-tracking-unavailable"))
        XCTAssertEqual(controller.hapticsRow.explanation, text("mouse-gesture-haptics-unavailable"))
        XCTAssertEqual(controller.deviceTrackingSwitch.state, .on)
        XCTAssertEqual(controller.hapticsSwitch.state, .on)
        XCTAssertTrue(Options.shared.gesture.deviceTracking)
    }

    func testOptionsAreEnabledWithTheirHintWhenAMouseSupportsThem() {
        support = MouseGestureDeviceSupport(deviceTracking: true, haptics: true)
        let controller = makeController()

        XCTAssertFalse(controller.logitechSection.isHidden)
        XCTAssertTrue(controller.logitechNeedsLabel.superview?.isHidden ?? false)
        XCTAssertTrue(controller.deviceTrackingSwitch.isEnabled)
        XCTAssertTrue(controller.hapticsSwitch.isEnabled)
        XCTAssertEqual(controller.deviceTrackingRow.explanation, text("mouse-gesture-device-tracking-hint"))
        XCTAssertEqual(controller.hapticsRow.explanation, text("mouse-gesture-haptics-hint"))
        XCTAssertEqual(controller.deviceTrackingRow.explanation, "Experimental: the mouse holds the pointer still and reports the movement.")
        XCTAssertEqual(controller.hapticsRow.title, "Pulse when a gesture locks in")
        XCTAssertEqual(controller.hapticsRow.explanation, "A short tap from the mouse as the gesture takes hold (MX Master 4).")
        XCTAssertEqual(controller.deviceTrackingSwitch.state, .off, "off by default")
        XCTAssertEqual(controller.hapticsSwitch.state, .on, "on by default")
        XCTAssertEqual(controller.deviceTrackingRow.title, text("mouse-gesture-device-tracking"))
        XCTAssertEqual(controller.hapticsRow.title, text("mouse-gesture-haptics"))
        XCTAssertEqual(controller.deviceTrackingSwitch.accessibilityLabel(), text("mouse-gesture-device-tracking"))
    }

    func testHapticsStayDisabledForAMouseWithoutAMotor() {
        support = MouseGestureDeviceSupport(deviceTracking: true, haptics: false)
        let controller = makeController()

        XCTAssertFalse(controller.logitechSection.isHidden)
        XCTAssertTrue(controller.deviceTrackingSwitch.isEnabled)
        XCTAssertFalse(controller.hapticsSwitch.isEnabled)
        XCTAssertFalse(controller.hapticsRow.isEnabled)
        XCTAssertEqual(controller.hapticsRow.explanation, text("mouse-gesture-haptics-unavailable"))
    }

    func testSwitchesWriteTheGestureSettingsAndNothingElse() {
        support = MouseGestureDeviceSupport(deviceTracking: true, haptics: true)
        Options.shared.gesture.mode = .interactive
        Options.shared.gesture.trackingSpeed = 2
        Options.shared.gesture.clickAction = SystemShortcut.copy.identifier
        let controller = makeController()

        set(controller.deviceTrackingSwitch, on: true)
        XCTAssertTrue(Options.shared.gesture.deviceTracking)

        set(controller.hapticsSwitch, on: false)
        XCTAssertFalse(Options.shared.gesture.hapticFeedback)

        var expected = MouseGestureSettings.default
        expected.mode = .interactive
        expected.trackingSpeed = 2
        expected.clickAction = SystemShortcut.copy.identifier
        expected.deviceTracking = true
        expected.hapticFeedback = false
        XCTAssertEqual(Options.shared.gesture, expected)

        set(controller.deviceTrackingSwitch, on: false)
        set(controller.hapticsSwitch, on: true)
        XCTAssertFalse(Options.shared.gesture.deviceTracking)
        XCTAssertTrue(Options.shared.gesture.hapticFeedback)
    }

    func testControlsShowStoredSettings() {
        support = MouseGestureDeviceSupport(deviceTracking: true, haptics: true)
        Options.shared.gesture.deviceTracking = true
        Options.shared.gesture.hapticFeedback = false
        let controller = makeController()

        XCTAssertEqual(controller.deviceTrackingSwitch.state, .on)
        XCTAssertEqual(controller.hapticsSwitch.state, .off)
    }

    func testGestureStateNotificationUpdatesTheEnablingRules() {
        let controller = makeController()
        XCTAssertFalse(controller.deviceTrackingSwitch.isEnabled)
        XCTAssertTrue(controller.logitechSection.isHidden)
        let without = controller.view.frame.height

        // An MX Master 4 connects: the box appears and the tab grows.
        support = MouseGestureDeviceSupport(deviceTracking: true, haptics: true)
        NotificationCenter.default.post(name: LogiCenter.gestureStateChanged, object: nil)
        XCTAssertFalse(controller.logitechSection.isHidden)
        XCTAssertTrue(controller.deviceTrackingSwitch.isEnabled)
        XCTAssertTrue(controller.hapticsSwitch.isEnabled)
        XCTAssertEqual(controller.gestureSupport, support)
        XCTAssertEqual(controller.hapticsRow.explanation, text("mouse-gesture-haptics-hint"))
        XCTAssertGreaterThan(controller.view.frame.height, without)
        XCTAssertEqual(controller.view.frame.size, controller.view.fittingSize)

        // It leaves again.
        support = .none
        NotificationCenter.default.post(name: LogiCenter.gestureStateChanged, object: nil)
        XCTAssertTrue(controller.logitechSection.isHidden)
        XCTAssertFalse(controller.deviceTrackingSwitch.isEnabled)
        XCTAssertFalse(controller.hapticsSwitch.isEnabled)
        XCTAssertEqual(controller.deviceTrackingRow.explanation, text("mouse-gesture-device-tracking-unavailable"))
        XCTAssertEqual(controller.view.frame.height, without)
    }

    func testTheSectionFitsTheTabWidthInBothStates() {
        let controller = makeController()
        XCTAssertEqual(controller.view.frame.width, GesturesPreferencesViewController.paneWidth)
        XCTAssertEqual(controller.view.frame.size, controller.view.fittingSize)

        support = MouseGestureDeviceSupport(deviceTracking: true, haptics: true)
        controller.reload()
        XCTAssertEqual(controller.view.frame.width, GesturesPreferencesViewController.paneWidth)
        XCTAssertEqual(controller.view.frame.size, controller.view.fittingSize)
    }

    func testTheBoxIsTitledLogitechMouseAndComesLast() throws {
        support = MouseGestureDeviceSupport(deviceTracking: true, haptics: true)
        let controller = makeController()
        controller.view.layoutSubtreeIfNeeded()
        let title = try XCTUnwrap(controller.logitechSection.titleLabel)
        XCTAssertEqual(title.stringValue, "Logitech mouse")
        func frame(_ view: NSView) -> NSRect { view.convert(view.bounds, to: controller.view) }
        // The root view is not flipped: lower on screen means a smaller y.
        XCTAssertGreaterThan(frame(title).minY, frame(controller.deviceTrackingRow).maxY)
        XCTAssertGreaterThan(frame(controller.deviceTrackingRow).minY, frame(controller.hapticsRow).maxY - 0.5)
        XCTAssertGreaterThan(frame(controller.trackingSpeedRow).minY, frame(title).maxY, "under the other boxes")
        XCTAssertEqual(frame(controller.deviceTrackingRow).minX, 20, accuracy: 0.5)
        XCTAssertEqual(controller.logitechSection.box.rows.map(\.title), [text("mouse-gesture-device-tracking"), text("mouse-gesture-haptics")])
    }

    // MARK: - Haptics off under Mouse

    private let master4HapticsOff = MouseGestureDeviceSupport(deviceTracking: true, haptics: true, hapticsOffOnMouse: true)

    func testTheHapticsOffRuleNeedsTheMouseOffAndTheUsersOff() {
        let master4 = MouseGestureDeviceSupport(deviceTracking: true, haptics: true)
        // Gesture cues are skipped only when both are off (Scrollio/Logi/Gesture): the mouse
        // reports its haptics off, and the user switched them off under Mouse.
        XCTAssertTrue(MouseGestureControlRules(support: master4HapticsOff, hapticsOnUnderMouse: false).showsHapticsOffNote)
        // Never touched under Mouse: a cue switches the haptics on itself.
        XCTAssertFalse(MouseGestureControlRules(support: master4HapticsOff, hapticsOnUnderMouse: nil).showsHapticsOffNote)
        XCTAssertFalse(MouseGestureControlRules(support: master4HapticsOff, hapticsOnUnderMouse: true).showsHapticsOffNote)
        XCTAssertFalse(MouseGestureControlRules(support: master4HapticsOff).showsHapticsOffNote)
        // The mouse has them on (or has not said yet).
        XCTAssertFalse(MouseGestureControlRules(support: master4, hapticsOnUnderMouse: false).showsHapticsOffNote)
        // No haptic motor: nothing to switch.
        let noMotor = MouseGestureDeviceSupport(deviceTracking: true, haptics: false, hapticsOffOnMouse: true)
        XCTAssertFalse(MouseGestureControlRules(support: noMotor, hapticsOnUnderMouse: false).showsHapticsOffNote)
        XCTAssertFalse(MouseGestureControlRules(support: .none, hapticsOnUnderMouse: false).showsHapticsOffNote)
        // The rest of the rules do not change.
        let off = MouseGestureControlRules(support: master4HapticsOff, hapticsOnUnderMouse: false)
        XCTAssertTrue(off.hapticsEnabled)
        XCTAssertEqual(off.hapticsHintKey, "mouse-gesture-haptics-hint")
    }

    func testALineUnderTheBoxSaysHapticsAreOffUnderMouse() throws {
        support = master4HapticsOff
        Options.shared.logiMouse.hapticsOn = false
        let controller = makeController()
        controller.view.layoutSubtreeIfNeeded()

        XCTAssertFalse(controller.logitechSection.isHidden)
        XCTAssertFalse(controller.hapticsOffNote.isHidden)
        XCTAssertTrue(controller.logitechNeedsLabel.superview?.isHidden ?? false)
        XCTAssertEqual(controller.hapticsOffLabel.stringValue, "Haptic feedback is off under Mouse.")
        XCTAssertEqual(controller.openMouseButton.title, "Open Mouse")
        XCTAssertEqual(controller.openMouseButton.controlSize, .small)
        XCTAssertEqual(controller.hapticsOffLabel.textColor, PreferencesGroupedForm.explanationColor(enabled: true))
        // The switch stays as it is: the line only says where the haptics are off.
        XCTAssertTrue(controller.hapticsSwitch.isEnabled)
        XCTAssertEqual(controller.hapticsSwitch.state, .on)
        XCTAssertEqual(controller.hapticsRow.explanation, text("mouse-gesture-haptics-hint"))

        // Right under the box, the line at the rows' inset and the button in the switches'
        // column (compared by alignment rects, as Auto Layout places them).
        func frame(_ view: NSView) -> NSRect {
            controller.view.convert(view.alignmentRect(forFrame: view.frame), from: view.superview)
        }
        let box = frame(controller.logitechSection)
        let note = frame(controller.hapticsOffNote)
        // The root view is not flipped: lower on screen means a smaller y.
        XCTAssertEqual(box.minY - note.maxY, PreferencesGroupedForm.noteSpacing, accuracy: 0.5)
        XCTAssertEqual(frame(controller.hapticsOffLabel).minX, frame(controller.hapticsRow.titleLabel).minX, accuracy: 0.5)
        XCTAssertEqual(frame(controller.openMouseButton).maxX, frame(controller.hapticsSwitch).maxX, accuracy: 0.5)
        XCTAssertLessThan(frame(controller.hapticsOffLabel).maxX, frame(controller.openMouseButton).minX)
        XCTAssertEqual(frame(controller.hapticsOffLabel).midY, frame(controller.openMouseButton).midY, accuracy: 1)
        XCTAssertEqual(controller.view.frame.size, controller.view.fittingSize)
        XCTAssertFalse(controller.view.hasAmbiguousLayout)
    }

    func testTheLineShowsOnlyWhenBothAreOff() {
        // The mouse has its haptics off, but the user never switched them off here.
        support = master4HapticsOff
        let controller = makeController()
        XCTAssertTrue(controller.hapticsOffNote.isHidden)
        let without = controller.view.frame.height

        Options.shared.logiMouse.hapticsOn = false
        controller.reload()
        XCTAssertFalse(controller.hapticsOffNote.isHidden)
        XCTAssertGreaterThan(controller.view.frame.height, without, "the pane makes room for it")

        // The mouse switched them on again (Logi Options+, or a managed mouse took the
        // user's choice): it reports so, and the line goes.
        support = MouseGestureDeviceSupport(deviceTracking: true, haptics: true)
        NotificationCenter.default.post(name: LogiCenter.mouseStateChanged, object: nil)
        XCTAssertTrue(controller.hapticsOffNote.isHidden)
        XCTAssertEqual(controller.view.frame.height, without, accuracy: 0.5)

        // Switched on under Mouse: no line, whatever the mouse says.
        support = master4HapticsOff
        Options.shared.logiMouse.hapticsOn = true
        controller.viewWillAppear()
        XCTAssertTrue(controller.hapticsOffNote.isHidden)

        // The mouse leaves: no box, no line.
        Options.shared.logiMouse.hapticsOn = false
        support = .none
        NotificationCenter.default.post(name: LogiCenter.gestureStateChanged, object: nil)
        XCTAssertTrue(controller.logitechSection.isHidden)
        XCTAssertTrue(controller.hapticsOffNote.isHidden)
        XCTAssertFalse(controller.logitechNeedsLabel.superview?.isHidden ?? true)
    }

    func testOpenMouseShowsTheMousePane() throws {
        support = master4HapticsOff
        Options.shared.logiMouse.hapticsOn = false
        var opened = 0
        let controller = makeController()
        controller.openMousePane = { opened += 1 }
        XCTAssertTrue(controller.openMouseButton.sendAction(controller.openMouseButton.action, to: controller.openMouseButton.target))
        XCTAssertEqual(opened, 1)
        // Nothing is written: the line only leads to Mouse.
        XCTAssertEqual(Options.shared.logiMouse.hapticsOn, false)
        XCTAssertTrue(Options.shared.gesture.hapticFeedback)
    }

    func testOpenMouseSelectsTheMousePaneInTheWindow() throws {
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesSplitViewController.self))
        let preferences = PreferencesSplitViewController(storyboard: storyboard, uiStateDefaults: nil)
        let gestures = try XCTUnwrap(preferences.controller(for: GesturesPreferencesViewController.tabIdentifier) as? GesturesPreferencesViewController)
        gestures.deviceSource = MouseGestureDeviceSource(support: { [weak self] in self?.support ?? .none }, refresh: {})
        gestures.bindingSummary = { MouseGestureBindingSummary(hasGestureButton: true, hasLogitechGestureButton: true) }
        (preferences.controller(for: MousePreferencesViewController.tabIdentifier) as? MousePreferencesViewController)?
            .deviceSource = MouseDeviceSource(deviceStates: { [] }, refresh: {})
        support = master4HapticsOff
        Options.shared.logiMouse.hapticsOn = false
        XCTAssertTrue(preferences.selectPane(withIdentifier: GesturesPreferencesViewController.tabIdentifier))
        XCTAssertFalse(gestures.hapticsOffNote.isHidden)

        XCTAssertTrue(gestures.openMouseButton.sendAction(gestures.openMouseButton.action, to: gestures.openMouseButton.target))
        XCTAssertEqual(preferences.selectedPaneIdentifier, MousePreferencesViewController.tabIdentifier)
        XCTAssertEqual(preferences.sidebar.selectedIdentifier, MousePreferencesViewController.tabIdentifier)
    }

    // MARK: - Strings

    private static let locales = PreferencesLocalizationTests.locales

    private static let keys = [
        "gestures-logitech-header", "gestures-logitech-needs",
        "mouse-gesture-device-tracking", "mouse-gesture-device-tracking-hint",
        "mouse-gesture-device-tracking-unavailable",
        "mouse-gesture-haptics", "mouse-gesture-haptics-hint", "mouse-gesture-haptics-unavailable",
        "gestures-haptics-off-under-mouse", "gestures-open-mouse",
    ]

    func testEveryLocaleTranslatesTheGestureSection() {
        let missing = "\u{1}missing"
        let app = Bundle(for: PreferencesSplitViewController.self)
        for locale in Self.locales {
            guard let path = app.path(forResource: locale, ofType: "lproj"), let bundle = Bundle(path: path) else {
                XCTFail("\(locale).lproj is missing")
                continue
            }
            for key in Self.keys {
                let value = bundle.localizedString(forKey: key, value: missing, table: nil)
                XCTAssertNotEqual(value, missing, "\(locale): \(key) missing")
                XCTAssertNotEqual(value, key, "\(locale): \(key) shows the raw key")
                XCTAssertFalse(value.isEmpty, "\(locale): \(key) empty")
                XCTAssertFalse(value.contains("%"), "\(locale): \(key) takes no arguments")
            }
        }
    }

    /// "Haptic feedback" is the Mouse pane's switch (the mouse's own); the Gestures switch
    /// has a name of its own, and the line under it names the Mouse pane's switch.
    func testOnlyTheMousePaneCallsItsSwitchHapticFeedback() {
        XCTAssertEqual(text("mouse-haptics"), "Haptic feedback")
        XCTAssertNotEqual(text("mouse-gesture-haptics"), text("mouse-haptics"))
        XCTAssertFalse(text("mouse-gesture-haptics").localizedCaseInsensitiveContains("haptic feedback"))
        XCTAssertTrue(text("gestures-haptics-off-under-mouse").hasPrefix(text("mouse-haptics")))
        XCTAssertTrue(text("gestures-haptics-off-under-mouse").contains(text("mouse-tab-title")))
        XCTAssertTrue(text("gestures-open-mouse").hasSuffix(text("mouse-tab-title")))
    }

    func testHapticHintsNameTheMouseThatHasThem() {
        let app = Bundle(for: PreferencesSplitViewController.self)
        for locale in Self.locales {
            guard let path = app.path(forResource: locale, ofType: "lproj"), let bundle = Bundle(path: path) else { continue }
            for key in ["mouse-gesture-haptics-hint", "mouse-gesture-haptics-unavailable"] {
                XCTAssertTrue(
                    bundle.localizedString(forKey: key, value: "", table: nil).contains("MX Master 4"),
                    "\(locale): \(key)"
                )
            }
        }
    }
}
