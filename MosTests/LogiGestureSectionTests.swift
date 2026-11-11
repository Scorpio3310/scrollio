import XCTest
@testable import Mos_Debug

/// The "Logitech" section of the Gestures tab: two checkboxes bound to the shared gesture
/// settings, enabled only when a connected mouse can do what they offer, with a hint that
/// says why not otherwise. Capabilities come from fixtures; no HID device is touched.
/// (The section lived in the Mouse tab before.)
final class LogiGestureSectionTests: XCTestCase {

    private var savedGesture = MouseGestureSettings.default
    private var support = MouseGestureDeviceSupport.none
    private var refreshCount = 0

    override func setUp() {
        super.setUp()
        savedGesture = Options.shared.gesture
        Options.shared.gesture = .default
        support = .none
        refreshCount = 0
    }

    override func tearDown() {
        Options.shared.gesture = savedGesture
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
    }

    func testOpeningTheTabAsksTheMiceAgain() {
        let controller = makeController()
        XCTAssertEqual(refreshCount, 0)
        controller.viewWillAppear()
        XCTAssertEqual(refreshCount, 1)
    }

    func testTheMouseTabNoLongerHoldsTheSection() {
        let mouse = MousePreferencesViewController()
        mouse.deviceSource = MouseWheelDeviceSource(deviceStates: { [] }, refresh: {}, showDiagnostics: {})
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

    func testBothOptionsAreDisabledWithAReasonWhenNoMouseSupportsThem() {
        Options.shared.gesture.deviceTracking = true
        let controller = makeController()

        XCTAssertFalse(controller.deviceTrackingCheckbox.isEnabled)
        XCTAssertFalse(controller.hapticsCheckbox.isEnabled)
        XCTAssertEqual(controller.deviceTrackingHintLabel.stringValue, text("mouse-gesture-device-tracking-unavailable"))
        XCTAssertEqual(controller.hapticsHintLabel.stringValue, text("mouse-gesture-haptics-unavailable"))
        // The stored choices stay visible and untouched for when a mouse connects.
        XCTAssertEqual(controller.deviceTrackingCheckbox.state, .on)
        XCTAssertEqual(controller.hapticsCheckbox.state, .on)
        XCTAssertTrue(Options.shared.gesture.deviceTracking)
    }

    func testOptionsAreEnabledWithTheirHintWhenAMouseSupportsThem() {
        support = MouseGestureDeviceSupport(deviceTracking: true, haptics: true)
        let controller = makeController()

        XCTAssertTrue(controller.deviceTrackingCheckbox.isEnabled)
        XCTAssertTrue(controller.hapticsCheckbox.isEnabled)
        XCTAssertEqual(controller.deviceTrackingHintLabel.stringValue, text("mouse-gesture-device-tracking-hint"))
        XCTAssertEqual(controller.hapticsHintLabel.stringValue, text("mouse-gesture-haptics-hint"))
        XCTAssertEqual(controller.deviceTrackingCheckbox.state, .off, "off by default")
        XCTAssertEqual(controller.hapticsCheckbox.state, .on, "on by default")
        XCTAssertEqual(controller.deviceTrackingCheckbox.title, text("mouse-gesture-device-tracking"))
        XCTAssertEqual(controller.hapticsCheckbox.title, text("mouse-gesture-haptics"))
    }

    func testHapticsStayDisabledForAMouseWithoutAMotor() {
        support = MouseGestureDeviceSupport(deviceTracking: true, haptics: false)
        let controller = makeController()

        XCTAssertTrue(controller.deviceTrackingCheckbox.isEnabled)
        XCTAssertFalse(controller.hapticsCheckbox.isEnabled)
        XCTAssertEqual(controller.hapticsHintLabel.stringValue, text("mouse-gesture-haptics-unavailable"))
    }

    func testCheckboxesWriteTheGestureSettingsAndNothingElse() {
        support = MouseGestureDeviceSupport(deviceTracking: true, haptics: true)
        Options.shared.gesture.mode = .interactive
        Options.shared.gesture.trackingSpeed = 2
        Options.shared.gesture.clickAction = SystemShortcut.copy.identifier
        let controller = makeController()

        controller.deviceTrackingCheckbox.state = .on
        send(controller.deviceTrackingCheckbox)
        XCTAssertTrue(Options.shared.gesture.deviceTracking)

        controller.hapticsCheckbox.state = .off
        send(controller.hapticsCheckbox)
        XCTAssertFalse(Options.shared.gesture.hapticFeedback)

        var expected = MouseGestureSettings.default
        expected.mode = .interactive
        expected.trackingSpeed = 2
        expected.clickAction = SystemShortcut.copy.identifier
        expected.deviceTracking = true
        expected.hapticFeedback = false
        XCTAssertEqual(Options.shared.gesture, expected)

        controller.deviceTrackingCheckbox.state = .off
        send(controller.deviceTrackingCheckbox)
        controller.hapticsCheckbox.state = .on
        send(controller.hapticsCheckbox)
        XCTAssertFalse(Options.shared.gesture.deviceTracking)
        XCTAssertTrue(Options.shared.gesture.hapticFeedback)
    }

    func testControlsShowStoredSettings() {
        support = MouseGestureDeviceSupport(deviceTracking: true, haptics: true)
        Options.shared.gesture.deviceTracking = true
        Options.shared.gesture.hapticFeedback = false
        let controller = makeController()

        XCTAssertEqual(controller.deviceTrackingCheckbox.state, .on)
        XCTAssertEqual(controller.hapticsCheckbox.state, .off)
    }

    func testGestureStateNotificationUpdatesTheEnablingRules() {
        let controller = makeController()
        XCTAssertFalse(controller.deviceTrackingCheckbox.isEnabled)

        // An MX Master 4 connects.
        support = MouseGestureDeviceSupport(deviceTracking: true, haptics: true)
        NotificationCenter.default.post(name: LogiCenter.gestureStateChanged, object: nil)
        XCTAssertTrue(controller.deviceTrackingCheckbox.isEnabled)
        XCTAssertTrue(controller.hapticsCheckbox.isEnabled)
        XCTAssertEqual(controller.gestureSupport, support)
        XCTAssertEqual(controller.hapticsHintLabel.stringValue, text("mouse-gesture-haptics-hint"))

        // It leaves again.
        support = .none
        NotificationCenter.default.post(name: LogiCenter.gestureStateChanged, object: nil)
        XCTAssertFalse(controller.deviceTrackingCheckbox.isEnabled)
        XCTAssertFalse(controller.hapticsCheckbox.isEnabled)
        XCTAssertEqual(controller.deviceTrackingHintLabel.stringValue, text("mouse-gesture-device-tracking-unavailable"))
    }

    func testTheSectionFitsTheTabWidthInBothStates() {
        let controller = makeController()
        XCTAssertEqual(controller.view.frame.width, PreferencesForm.contentWidth)
        XCTAssertEqual(controller.view.frame.size, controller.view.fittingSize)

        support = MouseGestureDeviceSupport(deviceTracking: true, haptics: true)
        controller.reload()
        XCTAssertEqual(controller.view.frame.width, PreferencesForm.contentWidth)
        XCTAssertEqual(controller.view.frame.size, controller.view.fittingSize)
    }

    func testTheSectionSitsUnderALogitechHeader() {
        let controller = makeController()
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(controller.logitechHeaderLabel.stringValue, "Logitech")
        let header = controller.logitechHeaderLabel.convert(controller.logitechHeaderLabel.bounds, to: controller.view)
        let tracking = controller.deviceTrackingCheckbox.convert(controller.deviceTrackingCheckbox.bounds, to: controller.view)
        let haptics = controller.hapticsCheckbox.convert(controller.hapticsCheckbox.bounds, to: controller.view)
        // The root view is not flipped: lower on screen means a smaller y.
        XCTAssertGreaterThan(header.minY, tracking.maxY)
        XCTAssertGreaterThan(tracking.minY, haptics.maxY)
        XCTAssertEqual(tracking.minX, 171, accuracy: 0.5)
    }

    // MARK: - Strings

    private static let locales = PreferencesLocalizationTests.locales

    private static let keys = [
        "gestures-logitech-header", "gestures-logitech-row-label",
        "mouse-gesture-device-tracking", "mouse-gesture-device-tracking-hint",
        "mouse-gesture-device-tracking-unavailable",
        "mouse-gesture-haptics", "mouse-gesture-haptics-hint", "mouse-gesture-haptics-unavailable",
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
