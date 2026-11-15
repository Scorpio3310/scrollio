import XCTest
@testable import Scrollio_Debug

/// The "Logitech mouse" box of the Gestures tab: two switches bound to the shared gesture
/// settings. The box shows when a connected mouse can do at least one of them (a switch
/// it cannot do is disabled and says why); without such a mouse the pane ends with
/// "Behavior" (no line asks for a Logitech mouse). While the mouse has its haptics off
/// because the user switched them off under Mouse, a muted line under the box says so and
/// leads there. While the mouse tracks every button that runs the gestures, it holds the
/// pointer itself: "Freeze pointer during a gesture" reads on and dimmed, with the reason,
/// and its stored value stays (`MouseGesturePointerHolder`). Capabilities and bindings come
/// from fixtures; no HID device is touched. (The section lived in the Mouse tab before.)
final class LogiGestureSectionTests: XCTestCase {

    private var savedGesture = MouseGestureSettings.default
    private var savedMouse = LogiMouseSettings.default
    private var support = MouseGestureDeviceSupport.none
    private var refreshCount = 0
    /// The bindings a press goes by wherever the pane's gestures run, and the keys of
    /// Scrolling › While you hold a key: what "Freeze pointer" goes by.
    private var bindingSets: [[ButtonBinding]] = []
    private var holdKeys: [ScrollHotkey] = []

    override func setUp() {
        super.setUp()
        savedGesture = Options.shared.gesture
        savedMouse = Options.shared.logiMouse
        Options.shared.gesture = .default
        Options.shared.logiMouse = .default
        support = .none
        refreshCount = 0
        bindingSets = []
        holdKeys = []
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
        controller.gestureBindingSets = { [weak self] in self?.bindingSets ?? [] }
        controller.holdKeysThatCatch = { [weak self] in self?.holdKeys ?? [] }
        _ = controller.view
        controller.reload()
        return controller
    }

    /// The gesture button of an MX Master (a Logitech control) and the standard Back button.
    private static let gestureButton: UInt16 = 1000 + 0x00C3
    private static let backButton: UInt16 = 3

    private func binding(
        _ code: UInt16, _ action: String = SystemShortcut.mouseGestureNavigation.identifier, modifiers: UInt = 0, enabled: Bool = true
    ) -> ButtonBinding {
        let trigger = RecordedEvent(type: .mouse, code: code, modifiers: modifiers, displayComponents: ["Button"], deviceFilter: nil)
        return ButtonBinding(triggerEvent: trigger, systemShortcutName: action, isEnabled: enabled)
    }

    private let master4 = MouseGestureDeviceSupport(deviceTracking: true, haptics: true)

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

    /// Without a mouse that can, the pane ends with "Behavior" and "Reset to Defaults": no
    /// line tells every other user to connect a Logitech mouse.
    func testNoLineAsksForALogitechMouse() {
        Options.shared.gesture.deviceTracking = true
        let controller = makeController()
        controller.view.layoutSubtreeIfNeeded()

        XCTAssertTrue(controller.logitechSection.isHidden)
        XCTAssertTrue(controller.hapticsOffNote.isHidden)
        let shown = controller.sections.filter { !$0.isHidden }
        XCTAssertTrue(shown.last === controller.footer)
        XCTAssertTrue(shown.dropLast().last === controller.behaviourSection, "Behavior is the last box")
        func frame(_ view: NSView) -> NSRect {
            controller.view.convert(view.alignmentRect(forFrame: view.frame), from: view.superview)
        }
        // The root view is not flipped: lower on screen means a smaller y.
        XCTAssertEqual(
            frame(controller.behaviourSection).minY - frame(controller.footer).maxY, PreferencesGroupedForm.sectionSpacing, accuracy: 0.5
        )
        let visibleTexts = Self.allSubviews(of: controller.view)
            .filter { !$0.isHiddenOrHasHiddenAncestor }
            .compactMap { ($0 as? NSTextField)?.stringValue }
        XCTAssertFalse(visibleTexts.contains { $0.contains("Logitech") || $0.contains("MX Master") }, "\(visibleTexts)")
        XCTAssertEqual(text("gestures-logitech-needs"), "gestures-logitech-needs", "the key is gone from the catalog")
        XCTAssertEqual(controller.view.frame.size, controller.view.fittingSize)
        // Freeze is Scrollio's to hold: no mouse tracks anything.
        XCTAssertEqual(controller.pointerHolder, .scrollio)
        XCTAssertTrue(controller.freezeRow.isEnabled)
        XCTAssertEqual(controller.freezeRow.explanation, text("gesture-freeze-pointer-hint"))
        XCTAssertTrue(controller.freezeRow.reservedExplanations.isEmpty, "the row is as it always was")
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
        XCTAssertTrue(controller.deviceTrackingSwitch.isEnabled)
        XCTAssertTrue(controller.hapticsSwitch.isEnabled)
        XCTAssertEqual(controller.deviceTrackingRow.explanation, text("mouse-gesture-device-tracking-hint"))
        XCTAssertEqual(controller.hapticsRow.explanation, text("mouse-gesture-haptics-hint"))
        XCTAssertEqual(controller.deviceTrackingRow.explanation, "The mouse holds the pointer still and reports the movement.")
        XCTAssertEqual(controller.hapticsRow.title, "Pulse when a gesture locks in")
        XCTAssertEqual(controller.hapticsRow.explanation, "A short pulse from the mouse when a gesture locks in (MX Master 4).")
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
        XCTAssertEqual(controller.logitechBox.rows.map(\.title), [text("mouse-gesture-device-tracking"), text("mouse-gesture-haptics")])
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
        XCTAssertEqual(controller.hapticsOffLabel.stringValue, "Haptic feedback is off under Mouse.")
        XCTAssertEqual(controller.openMouseButton.title, NSLocalizedString("gestures-open-mouse", comment: ""))
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

    // MARK: - Who holds the pointer

    private typealias Holder = MouseGesturePointerHolder

    private func holder(
        tracking: Bool = true, canTrack: Bool = true, _ sets: [[ButtonBinding]], holdKeys: [ScrollHotkey] = []
    ) -> Holder {
        return Holder.make(deviceTracking: tracking, mouseCanTrack: canTrack, bindingSets: sets, holdKeys: holdKeys)
    }

    /// A hold the mouse tracks never reads the Freeze switch (`InputProcessor`), and the
    /// mouse is asked to track a Logitech button only while Gesture Navigation is all it
    /// does (`LogiUsageBootstrap.gestureTrackingCodes`).
    func testWhoHoldsThePointerTable() {
        let gesture = Self.gestureButton
        let ring = SystemShortcut.shortcutRing.identifier
        let command = UInt(CGEventFlags.maskCommand.rawValue)

        // "Let the mouse track the gesture" is off, or no connected mouse can.
        XCTAssertEqual(holder(tracking: false, [[binding(gesture)]]), .scrollio)
        XCTAssertEqual(holder(canTrack: false, [[binding(gesture)]]), .scrollio)
        // No button runs the gestures; a plain button is never tracked.
        XCTAssertEqual(holder([[]]), .scrollio)
        XCTAssertEqual(holder([]), .scrollio)
        XCTAssertEqual(holder([[binding(Self.backButton)]]), .scrollio)
        // A Logitech button that only runs the gestures (also with modifier keys).
        XCTAssertEqual(holder([[binding(gesture)]]), .mouse)
        XCTAssertEqual(holder([[binding(gesture), binding(gesture, modifiers: command)]]), .mouse)
        // The same button with a second action, or as a key of While you hold a key.
        XCTAssertEqual(holder([[binding(gesture), binding(gesture, SystemShortcut.copy.identifier, modifiers: command)]]), .scrollio)
        XCTAssertEqual(holder([[binding(gesture)]], holdKeys: [ScrollHotkey(type: .mouse, code: gesture)]), .scrollio)
        XCTAssertEqual(holder([[binding(gesture)]], holdKeys: [ScrollHotkey(type: .keyboard, code: gesture)]), .mouse, "a key is no button")
        // A Logitech button and a plain one.
        XCTAssertEqual(holder([[binding(gesture), binding(Self.backButton)]]), .mouseForSome)
        // A disabled binding runs nothing: it is neither tracked nor in the way.
        XCTAssertEqual(holder([[binding(gesture), binding(Self.backButton, enabled: false)]]), .mouse)
        XCTAssertEqual(holder([[binding(gesture, enabled: false)]]), .scrollio)
        XCTAssertEqual(holder([[binding(gesture), binding(gesture, SystemShortcut.copy.identifier, modifiers: command, enabled: false)]]), .mouse)

        // An app whose own binding gives the button the ring: no gesture runs there, so
        // wherever one runs the mouse holds the pointer.
        let general = [binding(gesture)]
        XCTAssertEqual(holder([general, [binding(gesture, ring)]]), .mouse)
        // An app that adds a button the mouse does not track.
        XCTAssertEqual(holder([general, general + [binding(Self.backButton)]]), .mouseForSome)
        // Only an app's own (Logitech) button runs the gestures.
        XCTAssertEqual(holder([[], [binding(gesture)]]), .mouse)

        // What the switch shows, and the line under it.
        XCTAssertTrue(Holder.mouse.showsFreeze(stored: false))
        XCTAssertFalse(Holder.mouse.isFreezeEditable)
        for other in [Holder.scrollio, .mouseForSome] {
            XCTAssertFalse(other.showsFreeze(stored: false))
            XCTAssertTrue(other.showsFreeze(stored: true))
            XCTAssertTrue(other.isFreezeEditable)
        }
        XCTAssertEqual(
            [Holder.scrollio, .mouse, .mouseForSome].map(\.freezeHintKey), Holder.freezeHintKeys
        )
        XCTAssertEqual(text("gesture-freeze-pointer-mouse-holds"),
                       "The mouse holds the pointer still while “Let the mouse track the gesture” is on.")
        XCTAssertEqual(text("gesture-freeze-pointer-mouse-holds-some"),
                       "For buttons the mouse does not track. It holds the pointer still for the ones it tracks.")
        XCTAssertTrue(text("mouse-gesture-device-tracking").hasPrefix("Let the mouse track the gesture"), "the line names the switch")
    }

    /// The pane's sets: Buttons' bindings, and with the own buttons merged over them for
    /// each listed app that has some and runs the general gestures.
    func testThePanesBindingSetsAreButtonsAndTheAppsThatRunTheseGestures() {
        let general = [binding(Self.gestureButton)]
        let withOwnButton = Application(path: "/Applications/Figma.app")
        withOwnButton.setOwnButtonBindings([binding(Self.backButton)])
        let withOwnGestures = Application(path: "/Applications/Safari.app")
        withOwnGestures.setOwnButtonBindings([binding(Self.backButton)])
        withOwnGestures.setUsesGeneralGestures(false, general: .default)
        let plain = Application(path: "/Applications/Notes.app")

        let sets = Holder.paneBindingSets(general: general, applications: [withOwnButton, withOwnGestures, plain])
        XCTAssertEqual(sets.count, 2)
        XCTAssertEqual(sets.first, general)
        XCTAssertEqual(sets.last?.map(\.triggerEvent.code), [Self.gestureButton, Self.backButton])
    }

    func testFreezeReadsOnAndDimmedWhileTheMouseHoldsThePointer() {
        support = master4
        bindingSets = [[binding(Self.gestureButton)]]
        Options.shared.gesture.deviceTracking = true
        Options.shared.gesture.freezePointer = false
        let controller = makeController()
        let toggle = controller.controls.freezeToggle

        XCTAssertEqual(controller.pointerHolder, .mouse)
        XCTAssertTrue(MouseGestureSettingsControls.isOn(toggle), "the pointer does stay still")
        XCTAssertFalse(toggle.isEnabled)
        XCTAssertFalse(controller.freezeRow.isEnabled)
        XCTAssertEqual(controller.freezeRow.title, "Freeze pointer during a gesture")
        XCTAssertEqual(controller.freezeRow.explanation, text("gesture-freeze-pointer-mouse-holds"))
        XCTAssertEqual(controller.freezeRow.explanationLabel.textColor, PreferencesGroupedForm.explanationColor(enabled: false))
        // VoiceOver hears the switch by its row and the reason as its help.
        XCTAssertEqual(toggle.accessibilityLabel(), "Freeze pointer during a gesture")
        XCTAssertEqual(toggle.accessibilityHelp(), text("gesture-freeze-pointer-mouse-holds"))
        // The preview's pointer stays still, as the switch says.
        XCTAssertTrue(controller.previewScene.gesture.freezePointer)
        // Nothing was stored, and a dimmed switch sends nothing.
        XCTAssertFalse(Options.shared.gesture.freezePointer)
        // The other rows are as ever.
        XCTAssertTrue(controller.invertRow.isEnabled)
        XCTAssertTrue(controller.deviceTrackingSwitch.isEnabled)
        XCTAssertEqual(controller.deviceTrackingSwitch.state, .on)
    }

    func testTheShownFreezeIsNeverStored() {
        support = master4
        bindingSets = [[binding(Self.gestureButton)]]
        Options.shared.gesture.deviceTracking = true
        Options.shared.gesture.freezePointer = false
        let controller = makeController()
        let undo = UndoManager()
        undo.groupsByEvent = false
        controller.paneUndoManager = undo
        let controls = controller.controls!
        XCTAssertTrue(MouseGestureSettingsControls.isOn(controls.freezeToggle))

        // Other rows write their own values; the stored Freeze stays off through each.
        set(try! XCTUnwrap(controls.invertToggle as? NSSwitch), on: true)
        XCTAssertFalse(Options.shared.gesture.freezePointer)
        controls.modeControl.selectedSegment = 1
        send(controls.modeControl)
        XCTAssertEqual(Options.shared.gesture.mode, .interactive)
        XCTAssertFalse(Options.shared.gesture.freezePointer)
        controller.trackingSpeedSlider.doubleValue = 2
        send(controller.trackingSpeedSlider)
        XCTAssertEqual(Options.shared.gesture.trackingSpeed, 2)
        XCTAssertFalse(Options.shared.gesture.freezePointer)
        XCTAssertTrue(MouseGestureSettingsControls.isOn(controls.freezeToggle))
        XCTAssertFalse(controls.freezeToggle.isEnabled)

        // "Reset to Defaults" stores a new installation's values (Freeze on, tracking off):
        // the switch shows the stored value again and can be changed.
        let before = Options.shared.gesture
        undo.beginUndoGrouping()
        send(controller.resetToDefaultsButton)
        undo.endUndoGrouping()
        XCTAssertEqual(Options.shared.gesture, .default)
        XCTAssertEqual(controller.pointerHolder, .scrollio)
        XCTAssertTrue(controls.freezeToggle.isEnabled)
        XCTAssertTrue(MouseGestureSettingsControls.isOn(controls.freezeToggle))
        XCTAssertEqual(controller.freezeRow.explanation, text("gesture-freeze-pointer-hint"))

        // Undo brings back what was stored, Freeze off among it, not what the switch showed.
        undo.undo()
        XCTAssertEqual(Options.shared.gesture, before)
        XCTAssertFalse(Options.shared.gesture.freezePointer)
        XCTAssertEqual(controller.pointerHolder, .mouse)
        XCTAssertTrue(MouseGestureSettingsControls.isOn(controls.freezeToggle))
        XCTAssertFalse(controls.freezeToggle.isEnabled)

        // Tracking off again: the stored value shows, and the switch is a choice again.
        set(controller.deviceTrackingSwitch, on: false)
        XCTAssertEqual(controller.pointerHolder, .scrollio)
        XCTAssertFalse(MouseGestureSettingsControls.isOn(controls.freezeToggle))
        XCTAssertTrue(controls.freezeToggle.isEnabled)
        XCTAssertTrue(controller.freezeRow.isEnabled)
        XCTAssertEqual(controller.freezeRow.explanation, text("gesture-freeze-pointer-hint"))
        XCTAssertFalse(controller.previewScene.gesture.freezePointer)
        set(try! XCTUnwrap(controls.freezeToggle as? NSSwitch), on: true)
        XCTAssertTrue(Options.shared.gesture.freezePointer)

        // The mouse leaves while tracking is on: Scrollio holds the pointer, by the switch.
        Options.shared.gesture.freezePointer = false
        set(controller.deviceTrackingSwitch, on: true)
        XCTAssertEqual(controller.pointerHolder, .mouse)
        support = .none
        NotificationCenter.default.post(name: LogiCenter.gestureStateChanged, object: nil)
        XCTAssertEqual(controller.pointerHolder, .scrollio)
        XCTAssertFalse(MouseGestureSettingsControls.isOn(controls.freezeToggle))
        XCTAssertTrue(controls.freezeToggle.isEnabled)
    }

    func testFreezeStaysAChoiceWhileOnlySomeButtonsAreTracked() {
        support = master4
        bindingSets = [[binding(Self.gestureButton), binding(Self.backButton)]]
        Options.shared.gesture.deviceTracking = true
        Options.shared.gesture.freezePointer = false
        let controller = makeController()
        let toggle = try! XCTUnwrap(controller.controls.freezeToggle as? NSSwitch)

        XCTAssertEqual(controller.pointerHolder, .mouseForSome)
        XCTAssertEqual(toggle.state, .off, "the stored value: it decides for the Back button")
        XCTAssertTrue(toggle.isEnabled)
        XCTAssertTrue(controller.freezeRow.isEnabled)
        XCTAssertEqual(controller.freezeRow.explanation, text("gesture-freeze-pointer-mouse-holds-some"))
        XCTAssertEqual(toggle.accessibilityHelp(), text("gesture-freeze-pointer-mouse-holds-some"))
        XCTAssertFalse(controller.previewScene.gesture.freezePointer)

        set(toggle, on: true)
        XCTAssertTrue(Options.shared.gesture.freezePointer)
        XCTAssertEqual(toggle.state, .on)
        XCTAssertEqual(controller.freezeRow.explanation, text("gesture-freeze-pointer-mouse-holds-some"))

        // The Back button goes (an Undo in Buttons, a change there): only the tracked one is left.
        Options.shared.gesture.freezePointer = false
        bindingSets = [[binding(Self.gestureButton)]]
        controller.reload()
        XCTAssertEqual(controller.pointerHolder, .mouse)
        XCTAssertEqual(toggle.state, .on)
        XCTAssertFalse(toggle.isEnabled)
    }

    /// While a connected mouse can track, the row keeps room for each of its lines, so it
    /// never changes its height under "Let the mouse track the gesture", and each line fits
    /// two lines of the box. Without such a mouse the row is as it always was.
    func testTheFreezeRowKeepsItsHeightInTwoLines() {
        support = master4
        Options.shared.gesture.deviceTracking = true
        let controller = makeController()
        controller.view.layoutSubtreeIfNeeded()
        let row = try! XCTUnwrap(controller.freezeRow)
        XCTAssertEqual(row.reservedExplanations, Holder.freezeHintKeys.map(text))

        let label = row.explanationLabel
        let oneLine = NSTextField(labelWithString: "Ag")
        oneLine.font = label.font
        let lineHeight = oneLine.fittingSize.height
        var heights: [CGFloat] = []
        var paneHeights: [CGFloat] = []
        let cases: [[[ButtonBinding]]] = [[], [[binding(Self.gestureButton)]], [[binding(Self.gestureButton), binding(Self.backButton)]]]
        for sets in cases {
            bindingSets = sets
            controller.reload()
            controller.view.layoutSubtreeIfNeeded()
            XCTAssertEqual(row.explanation, text(controller.pointerHolder.freezeHintKey))
            heights.append(row.frame.height)
            paneHeights.append(controller.view.frame.height)
            let measure = NSTextField(wrappingLabelWithString: label.stringValue)
            measure.font = label.font
            measure.preferredMaxLayoutWidth = label.preferredMaxLayoutWidth
            XCTAssertLessThanOrEqual(measure.fittingSize.height, 2 * lineHeight + 0.5, "\(controller.pointerHolder): two lines at most")
            XCTAssertFalse(controller.view.hasAmbiguousLayout)
        }
        XCTAssertEqual(Set([Holder.scrollio, .mouse, .mouseForSome].map(\.freezeHintKey)).count, 3)
        XCTAssertEqual(Set(heights).count, 1, "\(heights)")
        XCTAssertEqual(Set(paneHeights).count, 1, "\(paneHeights)")

        // Tracking switched off and on again: the same height.
        set(controller.deviceTrackingSwitch, on: false)
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(row.frame.height, heights[0])
        XCTAssertEqual(row.explanation, text("gesture-freeze-pointer-hint"))

        // The mouse leaves: one line, and no room kept for more.
        support = .none
        controller.reload()
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertTrue(row.reservedExplanations.isEmpty)
        XCTAssertLessThan(row.frame.height, heights[0])
        XCTAssertLessThanOrEqual(label.frame.height, lineHeight + 0.5)
        XCTAssertEqual(controller.view.frame.size, controller.view.fittingSize)
    }

    // MARK: - Strings

    private static let locales = PreferencesLocalizationTests.locales

    private static let keys = [
        "gestures-logitech-header", "gesture-freeze-pointer-mouse-holds", "gesture-freeze-pointer-mouse-holds-some",
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
