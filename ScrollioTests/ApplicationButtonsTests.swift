//
//  ApplicationButtonsTests.swift
//  ScrollioTests
//
//  Buttons of an app's own, only what differs from Buttons: how they are stored and read
//  (also from entries without them and from values that cannot be read), how a press is
//  resolved (the app in front, once at the down; the general binding of the same trigger
//  replaced, a new one added, "Default" passing through; Scrollio itself staying general;
//  the ring and Gesture Navigation as any other action), the release pairing with its
//  press when the app in front changes meanwhile, the cache following a change of an app,
//  the Logitech buttons that follow the app in front, and the settings file. Nothing
//  reaches the Mac: the app in front is a seam, the executor's posts go to observers.
//

import XCTest
@testable import Scrollio_Debug

final class ApplicationButtonsTests: XCTestCase {

    private static let safari = ShortcutRingChoice.FrontApp(
        bundlePath: "/Applications/Safari.app", executablePath: "/Applications/Safari.app/Contents/MacOS/Safari"
    )
    private static let textEdit = ShortcutRingChoice.FrontApp(
        bundlePath: "/System/Applications/TextEdit.app", executablePath: "/System/Applications/TextEdit.app/Contents/MacOS/TextEdit"
    )

    private var savedBindings: [ButtonBinding] = []
    private var savedApplications: EnhanceArray<Application>!
    private var front: ShortcutRingChoice.FrontApp?
    private var frontLookups = 0
    private var executed: [(CGKeyCode, UInt64)] = []

    override func setUp() {
        super.setUp()
        savedBindings = Options.shared.buttons.binding
        savedApplications = Options.shared.application.applications
        front = Self.textEdit
        frontLookups = 0
        executed = []
        ButtonUtils.shared.frontApplication = { [unowned self] in
            self.frontLookups += 1
            return self.front
        }
        Options.shared.buttons.binding = []
        Options.shared.application.applications = Self.makeStore([])
        ButtonUtils.shared.invalidateCache()
        ShortcutExecutor.shared.setTestingMouseEventObserver()
        ShortcutExecutor.shared.setTestingKeyboardShortcutObserver { [unowned self] code, flags, _ in
            self.executed.append((code, flags))
        }
        ShortcutExecutor.shared.modifierFlagsProvider = InputProcessor.shared
        InputProcessor.shared.clearActiveBindings()
    }

    override func tearDown() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
        InputProcessor.shared.clearActiveBindings()
        ShortcutExecutor.shared.clearTestingMouseEventObserver()
        ShortcutExecutor.shared.clearTestingKeyboardShortcutObserver()
        ButtonUtils.shared.frontApplication = { .current() }
        Options.shared.buttons.binding = savedBindings
        Options.shared.application.applications = savedApplications
        ButtonUtils.shared.invalidateCache()
        savedApplications = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private static func makeStore(_ applications: [Application]) -> EnhanceArray<Application> {
        return EnhanceArray<Application>(
            withArray: applications, matchKey: "path", forObserver: { Options.shared.markChanged(.application) }
        )
    }

    private func binding(_ code: UInt16, _ action: String, modifiers: UInt = 0, type: EventType = .mouse) -> ButtonBinding {
        return ButtonBinding(
            triggerEvent: RecordedEvent(type: type, code: code, modifiers: modifiers, deviceFilter: nil),
            systemShortcutName: action,
            isEnabled: true
        )
    }

    /// Safari on the list with `own` as its own buttons, and `general` in Buttons.
    @discardableResult
    private func set(general: [ButtonBinding], safari own: [ButtonBinding]) -> Application {
        let safari = Application(path: Self.safari.bundlePath!)
        safari.setOwnButtonBindings(own)
        Options.shared.buttons.binding = general
        Options.shared.application.applications = Self.makeStore([safari])
        ButtonUtils.shared.invalidateCache()
        return safari
    }

    private func press(_ code: UInt16, modifiers: CGEventFlags = [], phase: InputPhase = .down, type: EventType = .mouse) -> InputEvent {
        return InputEvent(type: type, code: code, modifiers: modifiers, phase: phase, source: .hidPP, device: nil)
    }

    /// The action a press of `code` goes by with `front` in front.
    private func action(
        _ code: UInt16, modifiers: CGEventFlags = [], type: EventType = .mouse, in front: ShortcutRingChoice.FrontApp?
    ) -> String? {
        self.front = front
        return ButtonUtils.shared.getBestMatchingBinding(for: press(code, modifiers: modifiers, type: type))?.systemShortcutName
    }

    private func shortcut(_ shortcut: SystemShortcut.Shortcut) -> (code: CGKeyCode, flags: UInt64) {
        return SystemShortcut.resolveSystemShortcut(shortcut.identifier) ?? (shortcut.code, UInt64(shortcut.modifiers.rawValue))
    }

    // MARK: - Resolution

    /// While the app is in front its binding replaces the general binding of the same
    /// trigger and a binding of a new trigger is added; every other button does what
    /// Buttons says. In any other app all of them do what Buttons says.
    func testTheAppInFrontGoesByItsOwnBindingsAndEveryOtherButtonByButtons() {
        set(
            general: [binding(3, "copy"), binding(4, "paste"), binding(3, "cut", modifiers: UInt(CGEventFlags.maskCommand.rawValue))],
            safari: [binding(3, "undo"), binding(5, "missionControl")]
        )

        XCTAssertEqual(action(3, in: Self.safari), "undo", "the same trigger: the app's")
        XCTAssertEqual(action(4, in: Self.safari), "paste", "a button the app leaves alone: Buttons")
        XCTAssertEqual(action(5, in: Self.safari), "missionControl", "a trigger Buttons does not have: added")
        XCTAssertEqual(action(3, modifiers: .maskCommand, in: Self.safari), "cut", "⌘ and the button is another trigger")

        XCTAssertEqual(action(3, in: Self.textEdit), "copy")
        XCTAssertEqual(action(5, in: Self.textEdit), nil)
        XCTAssertEqual(action(3, in: nil), "copy", "no app in front")
        // Found by the program's path too, as the ring and the scroll engine find an app.
        let byProgram = ShortcutRingChoice.FrontApp(bundlePath: "/elsewhere/Safari.app", executablePath: Self.safari.bundlePath)
        XCTAssertEqual(action(3, in: byProgram), "undo")
    }

    /// Two entries of one path (a settings file written by hand): the press goes by the
    /// entry every other reader finds (`get(by:)`, the last), as the Logitech divert does,
    /// never by the other one's buttons.
    func testOfTwoEntriesOfOnePathThePressGoesByTheOneEveryReaderFinds() {
        let first = Application(path: Self.safari.bundlePath!)
        first.setOwnButtonBindings([binding(3, "undo"), binding(4, "redo")])
        let last = Application(path: Self.safari.bundlePath!)
        last.setOwnButtonBindings([binding(3, "cut")])
        Options.shared.buttons.binding = [binding(3, "copy")]
        Options.shared.application.applications = Self.makeStore([first, last])
        ButtonUtils.shared.invalidateCache()
        XCTAssertTrue(ApplicationButtons.entry(front: Self.safari, applications: Options.shared.application.applications) === last)

        XCTAssertEqual(action(3, in: Self.safari), "cut")
        XCTAssertNil(action(4, in: Self.safari), "the first entry's button is no binding of the app's")

        // The divert and the buttons the mouse tracks go by the same entry: they choose it
        // themselves (the first entry takes mode shift, the last the gesture button).
        let gesture = SystemShortcut.mouseGestureNavigation.identifier
        let savedGesture = Options.shared.gesture
        defer {
            Options.shared.gesture = savedGesture
            Options.shared.buttons.binding = savedBindings
            Options.shared.application.applications = savedApplications
            LogiUsageBootstrap.refreshButtonUsage(front: nil)
            LogiUsageBootstrap.refreshGestureTracking(front: nil)
        }
        first.setOwnButtonBindings([binding(1001, gesture), binding(1000, "undo")])
        last.setOwnButtonBindings([binding(1000, gesture)])
        Options.shared.buttons.binding = []
        Options.shared.gesture.deviceTracking = true
        ButtonUtils.shared.invalidateCache()
        LogiUsageBootstrap.refreshButtonUsage(front: Self.safari)
        XCTAssertTrue(LogiCenter.shared.usages(of: 1000).contains(.buttonBinding), "the divert goes by the same entry")
        XCTAssertFalse(LogiCenter.shared.usages(of: 1001).contains(.buttonBinding))
        LogiUsageBootstrap.refreshGestureTracking(front: Self.safari)
        XCTAssertEqual(LogiSessionManager.shared.gestureTrackingCodes, [1000], "and so does the tracking")
    }

    /// The merge, pure: the general order, each replaced in its place, the new ones after;
    /// one binding per trigger; the trigger includes the modifier keys and the mouse.
    func testTheMergeReplacesInPlaceAndAddsAfter() {
        let command = UInt(CGEventFlags.maskCommand.rawValue)
        let general = [binding(3, "copy"), binding(4, "paste"), binding(3, "cut", modifiers: command)]
        let own = [binding(3, "undo", modifiers: command), binding(6, "redo"), binding(3, "selectAll", modifiers: command)]
        let merged = ApplicationButtons.merged(general: general, own: own)
        XCTAssertEqual(merged.map(\.systemShortcutName), ["copy", "paste", "undo", "redo"])
        XCTAssertEqual(ApplicationButtons.merged(general: general, own: []), general, "none of its own: Buttons as it is")
        let filtered = RecordedEvent(type: .mouse, code: 3, modifiers: 0, deviceFilter: DeviceFilter(vendorId: 0x046D, productId: nil))
        XCTAssertNotEqual(ButtonBindingIdentity(filtered), binding(3, "copy").identity, "a binding for one mouse is another")
        XCTAssertEqual(
            ButtonBindingIdentity(RecordedEvent(type: .mouse, code: 3, modifiers: 0, deviceFilter: nil, mousePart: .backButton)),
            binding(3, "copy").identity, "where the button is said to be does not count"
        )
    }

    /// "Default" in the app: the press passes through there (the button does what it does
    /// by itself) and runs nothing; elsewhere the general action runs.
    func testDefaultInTheAppPassesThePressThrough() {
        set(general: [binding(4, "paste")], safari: [binding(4, "")])

        front = Self.safari
        XCTAssertEqual(InputProcessor.shared.process(press(4)), .passthrough)
        XCTAssertEqual(InputProcessor.shared.process(press(4, phase: .up)), .passthrough)
        XCTAssertTrue(executed.isEmpty)

        front = Self.textEdit
        XCTAssertEqual(InputProcessor.shared.process(press(4)), .consumed)
        _ = InputProcessor.shared.process(press(4, phase: .up))
        XCTAssertEqual(executed.first?.0, shortcut(SystemShortcut.paste).code)
    }

    /// Scrollio's own settings in front: every button does what Buttons says, so a binding
    /// can be tried there whatever app it was set for.
    func testScrollioInFrontGoesByButtons() {
        set(general: [binding(3, "copy")], safari: [binding(3, "undo")])
        var scrollio = Self.safari
        scrollio.isScrollio = true
        XCTAssertEqual(action(3, in: scrollio), "copy")
        XCTAssertEqual(ButtonUtils.shared.scopeOfPress(for: press(3)), .general)
    }

    /// Nothing stays general: an app's own binding may open the Shortcut Ring or run
    /// Gesture Navigation, on any button, and may give the button that does one of them in
    /// Buttons something else to do while the app is in front.
    func testAnAppsOwnButtonsMayOpenTheRingAndRunGestureNavigation() {
        let ring = SystemShortcut.shortcutRing.identifier
        let gesture = SystemShortcut.mouseGestureNavigation.identifier
        let command = UInt(CGEventFlags.maskCommand.rawValue)
        let safari = set(
            general: [binding(6, ring), binding(7, gesture), binding(3, "copy")],
            safari: [binding(6, "undo"), binding(7, "undo", modifiers: command), binding(3, ring), binding(5, gesture)]
        )
        XCTAssertEqual(action(6, in: Self.safari), "undo", "the ring's button does something else here")
        XCTAssertEqual(action(6, in: Self.textEdit), ring)
        XCTAssertEqual(action(7, in: Self.safari), gesture, "only the button with ⌘ is the app's own")
        XCTAssertEqual(action(7, modifiers: .maskCommand, in: Self.safari), "undo")
        XCTAssertEqual(action(3, in: Self.safari), ring, "an app's button opens the ring")
        XCTAssertEqual(action(3, in: Self.textEdit), "copy")
        XCTAssertEqual(action(5, in: Self.safari), gesture, "and runs Gesture Navigation")
        XCTAssertNil(action(5, in: Self.textEdit))
        XCTAssertEqual(
            ApplicationButtons.usable(safari.ownButtonBindings, general: Options.shared.buttons.binding).map(\.systemShortcutName),
            ["undo", "undo", ring, gesture]
        )
    }

    /// Without an app that has buttons of its own nothing asks which app is in front; with
    /// one, only a press of a button some app has its own binding on asks, once.
    func testOnlyAPressOfAButtonSomeAppHasItsOwnBindingOnAsksWhichAppIsInFront() {
        Options.shared.buttons.binding = [binding(3, "copy"), binding(4, "paste")]
        Options.shared.application.applications = Self.makeStore([Application(path: Self.safari.bundlePath!)])
        ButtonUtils.shared.invalidateCache()
        front = Self.safari
        _ = InputProcessor.shared.process(press(3))
        _ = InputProcessor.shared.process(press(3, phase: .up))
        XCTAssertEqual(frontLookups, 0, "no app has buttons of its own")

        set(general: [binding(3, "copy"), binding(4, "paste")], safari: [binding(3, "undo")])
        front = Self.safari
        frontLookups = 0
        _ = InputProcessor.shared.process(press(4))
        _ = InputProcessor.shared.process(press(4, phase: .up))
        XCTAssertEqual(frontLookups, 0, "a button no app has its own binding on")
        _ = InputProcessor.shared.process(press(3))
        XCTAssertEqual(frontLookups, 1, "once, at the down")
        _ = InputProcessor.shared.process(press(3, phase: .up))
        XCTAssertEqual(frontLookups, 1, "never at the up")
    }

    /// The release ends what its press started, whatever app came to the front meanwhile:
    /// a modifier the general binding held is let go in the app, and a press the app ran
    /// its own action for releases nothing of the general one.
    func testTheReleaseEndsWhatItsPressStartedWhenTheAppInFrontChangesBetween() {
        let shift = KeyCode.getKeyMask(56).rawValue
        set(general: [binding(3, "custom::56:0")], safari: [binding(3, "copy")])

        front = Self.textEdit
        XCTAssertEqual(InputProcessor.shared.process(press(3)), .consumed)
        XCTAssertNotEqual(InputProcessor.shared.activeModifierFlags & shift, 0, "Shift is held")
        front = Self.safari
        XCTAssertEqual(InputProcessor.shared.process(press(3, phase: .up)), .consumed)
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, 0, "the release let go of Shift")
        XCTAssertTrue(executed.allSatisfy { $0.0 != shortcut(SystemShortcut.copy).code }, "Safari's action never ran")

        executed = []
        front = Self.safari
        XCTAssertEqual(InputProcessor.shared.process(press(3)), .consumed)
        XCTAssertEqual(executed.map(\.0), [shortcut(SystemShortcut.copy).code])
        front = Self.textEdit
        _ = InputProcessor.shared.process(press(3, phase: .up))
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, 0, "no Shift from the general binding")
    }

    /// A key the system repeats, as it sends it (`keyboardEventAutorepeat`).
    private func key(_ code: CGKeyCode, flags: CGEventFlags, down: Bool = true, repeating: Bool = false) -> InputEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
        event.flags = flags
        if repeating {
            event.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        }
        return InputEvent(fromCGEvent: event)
    }

    /// A held key's repeats belong to its press: they go by the bindings the press went by,
    /// whatever app that press brought to the front. Safari's own ⌘Q runs Copy and TextEdit
    /// comes forward while ⌘Q is held: the repeats are swallowed, not handed to TextEdit
    /// (where ⌘Q would quit it). The other way round, a general ⌘Q pressed in TextEdit keeps
    /// its repeats when Safari, whose ⌘Q is "Default", comes forward. The next press asks
    /// the app in front again.
    func testAHeldKeysRepeatsGoByItsPressWhenAnotherAppComesToTheFront() {
        let q: CGKeyCode = 12
        let command = UInt(CGEventFlags.maskCommand.rawValue)
        set(general: [], safari: [binding(q, "copy", modifiers: command, type: .keyboard)])

        front = Self.safari
        XCTAssertEqual(InputProcessor.shared.process(key(q, flags: .maskCommand)), .consumed)
        XCTAssertEqual(executed.map(\.0), [shortcut(SystemShortcut.copy).code])
        front = Self.textEdit
        frontLookups = 0
        XCTAssertEqual(InputProcessor.shared.process(key(q, flags: .maskCommand, repeating: true)), .consumed,
                       "a repeat of Safari's press never reaches TextEdit")
        XCTAssertEqual(InputProcessor.shared.process(key(q, flags: .maskCommand, repeating: true)), .consumed)
        XCTAssertEqual(executed.count, 1, "a trigger action runs once per press")
        XCTAssertEqual(frontLookups, 0, "a repeat does not ask which app is in front")
        _ = InputProcessor.shared.process(key(q, flags: .maskCommand, down: false))
        XCTAssertEqual(InputProcessor.shared.process(key(q, flags: .maskCommand)), .passthrough,
                       "the next press goes by the app in front")
        _ = InputProcessor.shared.process(key(q, flags: .maskCommand, down: false))

        executed = []
        set(general: [binding(q, "copy", modifiers: command, type: .keyboard)], safari: [binding(q, "", modifiers: command, type: .keyboard)])
        front = Self.textEdit
        XCTAssertEqual(InputProcessor.shared.process(key(q, flags: .maskCommand)), .consumed)
        front = Self.safari
        XCTAssertEqual(InputProcessor.shared.process(key(q, flags: .maskCommand, repeating: true)), .consumed,
                       "Safari's \"Default\" does not take the repeats of a press made in TextEdit")
        XCTAssertEqual(executed.count, 1)
        _ = InputProcessor.shared.process(key(q, flags: .maskCommand, down: false))
    }

    /// The Logitech probe goes by the same bindings as InputProcessor: an app's own
    /// Logitech action runs while it is in front, and its "Default" passes through.
    func testTheLogitechProbeSeesTheAppInFront() {
        let gestureButton: UInt16 = 1000
        set(general: [binding(gestureButton, "copy")], safari: [binding(gestureButton, "logiSmartShiftToggle")])
        let bridge = LogiIntegrationBridge.shared
        let down = InputEvent(type: .mouse, code: gestureButton, modifiers: [], phase: .down, source: .hidPP, device: nil)
        let up = InputEvent(type: .mouse, code: gestureButton, modifiers: [], phase: .up, source: .hidPP, device: nil)

        front = Self.safari
        XCTAssertEqual(bridge.dispatchLogiButtonEvent(down), .logiAction(name: "logiSmartShiftToggle"))
        _ = bridge.dispatchLogiButtonEvent(up)
        front = Self.textEdit
        frontLookups = 0
        XCTAssertEqual(bridge.dispatchLogiButtonEvent(down), .consumed)
        XCTAssertEqual(frontLookups, 1, "the probe and InputProcessor share one look")
        _ = bridge.dispatchLogiButtonEvent(up)
        XCTAssertEqual(frontLookups, 1)
        XCTAssertEqual(executed.map(\.0), [shortcut(SystemShortcut.copy).code])
    }

    /// A back button set up while the mouse was on its receiver is stored under its Logitech
    /// code; over Bluetooth the same button arrives as the standard button 3. A standard
    /// press that has no binding of its own goes by its Logitech twin's, in Buttons and in an
    /// app's own; a standard binding that takes the press still wins (nothing changes for
    /// it), an app's "Default" of the standard button too; a button without a twin finds
    /// nothing, and a Logitech press still goes by the Logitech bindings alone.
    func testAStandardButtonWithoutABindingGoesByItsLogitechTwin() {
        let logitechBack = LogiCenter.shared.scrollioCode(for: .back)
        let command = UInt(CGEventFlags.maskCommand.rawValue)
        set(general: [binding(logitechBack, "copy")], safari: [])
        XCTAssertEqual(action(3, in: Self.textEdit), "copy", "Buttons' back button, set up over the receiver")
        XCTAssertEqual(action(3, modifiers: .maskCommand, in: Self.textEdit), "copy")
        XCTAssertNil(action(5, in: Self.textEdit), "button 5 has no Logitech twin")

        set(general: [binding(logitechBack, "copy")], safari: [binding(logitechBack, "undo")])
        XCTAssertEqual(action(3, in: Self.safari), "undo", "Safari's own, set up over the receiver")
        XCTAssertEqual(action(3, in: Self.textEdit), "copy")
        set(general: [], safari: [binding(logitechBack, "undo")])
        XCTAssertEqual(action(3, in: Self.safari), "undo", "only Safari's")
        XCTAssertNil(action(3, in: Self.textEdit))

        set(general: [binding(3, "paste"), binding(logitechBack, "copy")], safari: [])
        XCTAssertEqual(action(3, in: Self.textEdit), "paste", "the standard binding wins")
        set(general: [binding(3, "paste", modifiers: command), binding(logitechBack, "copy")], safari: [])
        XCTAssertEqual(action(3, modifiers: .maskCommand, in: Self.textEdit), "paste")
        XCTAssertEqual(action(3, in: Self.textEdit), "copy", "a press the ⌘ binding does not take")
        set(general: [binding(logitechBack, "copy")], safari: [binding(3, "")])
        XCTAssertEqual(action(3, in: Self.safari), "", "Safari's own \"Default\" of the standard button")
        set(general: [binding(3, "paste")], safari: [])
        XCTAssertNil(action(logitechBack, in: Self.textEdit))
    }

    /// The standard number (recorded over Bluetooth) and the Logitech code (recorded on the
    /// receiver) of middle, back and forward are one trigger: an app's binding under one
    /// code takes the place of Buttons' binding under the other, on either connection;
    /// "Everywhere: …" finds Buttons' binding under the other code; the app keeps one
    /// binding per button; its binding under the standard number gives back the Logitech
    /// button Buttons diverts under the other code (the press then comes as the standard
    /// button); and a standard press ranks the bindings under the two codes together (the
    /// one with the press's modifier keys wins).
    func testTheStandardNumberAndTheLogitechCodeOfAButtonAreOneTrigger() {
        let logitechBack = LogiCenter.shared.scrollioCode(for: .back)
        let command = UInt(CGEventFlags.maskCommand.rawValue)
        let isLogi: (UInt16) -> Bool = { LogiCenter.shared.isLogiCode($0) }
        XCTAssertEqual(binding(3, "copy").identity, binding(logitechBack, "undo").identity)
        XCTAssertNotEqual(binding(3, "copy", modifiers: command).identity, binding(logitechBack, "undo").identity)
        XCTAssertNotEqual(binding(5, "copy").identity, binding(logitechBack, "undo").identity)

        // Buttons under the Logitech code, the app's own under the standard number.
        set(general: [binding(logitechBack, "copy")], safari: [binding(3, "undo")])
        XCTAssertEqual(action(3, in: Self.safari), "undo", "over Bluetooth, and on the receiver once the button is given back")
        XCTAssertEqual(
            LogiUsageBootstrap.buttonBindingCodes(general: [binding(logitechBack, "copy")], frontAppOwn: [binding(3, "undo")], isLogiCode: isLogi),
            [], "given back to the mouse while Safari is in front"
        )
        XCTAssertEqual(action(3, in: Self.textEdit), "copy")
        XCTAssertEqual(action(logitechBack, in: Self.textEdit), "copy")
        XCTAssertEqual(
            ApplicationButtons.generalBinding(for: binding(3, "").triggerEvent, in: Options.shared.buttons.binding)?.systemShortcutName,
            "copy", "Everywhere: what Back does in Buttons"
        )
        XCTAssertEqual(
            ApplicationButtons.generalBinding(for: binding(3, "", modifiers: command).triggerEvent,
                                              in: Options.shared.buttons.binding)?.systemShortcutName,
            "copy", "with ⌘ too"
        )
        XCTAssertEqual(
            ApplicationButtons.usable([binding(3, "undo"), binding(logitechBack, "redo")], general: []).map(\.systemShortcutName),
            ["undo"], "one binding per button"
        )

        // The reverse: Buttons under the standard number, the app's own under the Logitech code.
        set(general: [binding(3, "copy")], safari: [binding(logitechBack, "undo")])
        XCTAssertEqual(action(3, in: Self.safari), "undo", "over Bluetooth the app's own, not Buttons' standard binding")
        XCTAssertEqual(action(logitechBack, in: Self.safari), "undo")
        XCTAssertEqual(action(3, in: Self.textEdit), "copy")
        set(general: [binding(3, "copy")], safari: [binding(logitechBack, "")])
        XCTAssertEqual(action(3, in: Self.safari), "", "the app's own Default")

        // Its "Default" gives the button back to the mouse while it is in front.
        XCTAssertEqual(
            LogiUsageBootstrap.buttonBindingCodes(general: [binding(logitechBack, "copy")], frontAppOwn: [binding(3, "")], isLogiCode: isLogi),
            [], "the app's Default of the standard number"
        )
        XCTAssertEqual(
            LogiUsageBootstrap.buttonBindingCodes(general: [binding(logitechBack, "copy")], frontAppOwn: [], isLogiCode: isLogi),
            [logitechBack]
        )

        // Ranked together: ⌘ + Back in Buttons, plain Back in the app.
        set(general: [binding(3, "paste", modifiers: command)], safari: [binding(logitechBack, "undo")])
        XCTAssertEqual(action(3, modifiers: .maskCommand, in: Self.safari), "paste", "the binding with ⌘ matches better")
        XCTAssertEqual(action(3, in: Self.safari), "undo")
        set(general: [binding(3, "paste")], safari: [binding(logitechBack, "undo", modifiers: command)])
        XCTAssertEqual(action(3, modifiers: .maskCommand, in: Self.safari), "undo", "the app's ⌘ + Back under the Logitech code")
    }

    /// A change of an app's own buttons is seen at the next press without anyone asking for
    /// it (the cache follows the per-app list as it follows Buttons).
    func testAChangeOfAnAppsButtonsIsSeenAtTheNextPress() {
        let safari = set(general: [binding(3, "copy")], safari: [])
        XCTAssertEqual(action(3, in: Self.safari), "copy")
        safari.setOwnButtonBindings([binding(3, "undo")])
        XCTAssertEqual(action(3, in: Self.safari), "undo")
        safari.setOwnButtonBindings([])
        XCTAssertEqual(action(3, in: Self.safari), "copy")
        XCTAssertNil(safari.buttons, "none stored")
    }

    /// The key tap runs when any app has a key of its own, not only when Buttons has one.
    func testTheKeyTapIsNeededForAnAppsOwnKey() {
        set(general: [binding(3, "copy")], safari: [])
        XCTAssertFalse(ButtonUtils.shared.hasKeyboardTriggers)
        let key = binding(40, "undo", modifiers: UInt(CGEventFlags.maskCommand.rawValue), type: .keyboard)
        set(general: [binding(3, "copy")], safari: [key])
        XCTAssertTrue(ButtonUtils.shared.hasKeyboardTriggers)
        XCTAssertEqual(action(40, modifiers: .maskCommand, type: .keyboard, in: Self.safari), "undo")
        XCTAssertNil(action(40, modifiers: .maskCommand, type: .keyboard, in: Self.textEdit))
        // A plain letter is no trigger for an app either.
        set(general: [], safari: [binding(40, "undo", type: .keyboard)])
        XCTAssertFalse(ButtonUtils.shared.hasKeyboardTriggers)
        XCTAssertNil(action(40, type: .keyboard, in: Self.safari))
    }

    /// "Everywhere: …": the general binding of the same trigger, else the one such a press
    /// matches best, else none.
    func testWhatTheButtonDoesEverywhere() {
        let command = UInt(CGEventFlags.maskCommand.rawValue)
        let general = [binding(3, "copy"), binding(4, "paste", modifiers: command)]
        XCTAssertEqual(ApplicationButtons.generalBinding(for: binding(3, "").triggerEvent, in: general)?.systemShortcutName, "copy")
        XCTAssertEqual(
            ApplicationButtons.generalBinding(for: binding(3, "", modifiers: command).triggerEvent, in: general)?.systemShortcutName,
            "copy", "a button bound without modifier keys runs with them too"
        )
        XCTAssertNil(ApplicationButtons.generalBinding(for: binding(4, "").triggerEvent, in: general))
    }

    // MARK: - Storage

    /// Own buttons are stored under "buttons" with the app; an app without them is stored
    /// as before, with no key; they come back as they were.
    func testOwnButtonsAreStoredWithTheAppAndComeBack() throws {
        let safari = Application(path: Self.safari.bundlePath!)
        let plain = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(safari)) as? [String: Any]
        XCTAssertEqual(Set(try XCTUnwrap(plain).keys), ["path", "displayName", "inherit", "scroll"])

        let own = [binding(3, "undo"), binding(4, "")]
        safari.setOwnButtonBindings(own)
        let data = try JSONEncoder().encode(safari)
        let stored = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let buttons = try XCTUnwrap(stored["buttons"] as? [String: Any])
        XCTAssertEqual(Array(buttons.keys), ["binding"])
        XCTAssertEqual((buttons["binding"] as? [Any])?.count, 2)
        let read = try JSONDecoder().decode(Application.self, from: data)
        XCTAssertEqual(read.ownButtonBindings, own)
        XCTAssertTrue(read.hasOwnButtons)

        safari.setOwnButtonBindings([])
        XCTAssertNil(safari.buttons)
        let again = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(safari)) as? [String: Any]
        XCTAssertNil(again?["buttons"], "no key once there are none")
    }

    /// An entry from before (no "buttons", as every released version wrote it) has none;
    /// a value that cannot be read is none and keeps the entry; a binding that cannot be
    /// read is left out by itself.
    func testOldEntriesAndValuesThatCannotBeReadHaveNoButtonsOfTheirOwn() throws {
        let older = try JSONDecoder().decode(Application.self, from: Data(StoredDataCanaryTests.readableApp.utf8))
        XCTAssertFalse(older.hasOwnButtons)
        XCTAssertNil(older.buttons)

        for value in [#"7"#, #""buttons""#, #"{"binding":"no"}"#, #"{"binding":[]}"#, #"{"other":[]}"#] {
            let entry = #"{"path":"/Applications/A.app","inherit":false,"buttons":"# + value + "}"
            let read = try JSONDecoder().decode(Application.self, from: Data(entry.utf8))
            XCTAssertEqual(read.path, "/Applications/A.app", value)
            XCTAssertFalse(read.inherit, value)
            XCTAssertNil(read.buttons, value)
        }

        let good = String(data: try JSONEncoder().encode(binding(3, "undo")), encoding: .utf8)!
        let entry = #"{"path":"/Applications/A.app","buttons":{"binding":[{"id":"x"},"# + good + #",42]}}"#
        let read = try JSONDecoder().decode(Application.self, from: Data(entry.utf8))
        XCTAssertEqual(read.ownButtonBindings.map(\.systemShortcutName), ["undo"])
    }

    /// A binding of an app's own that this version cannot read (a newer version's: a kind
    /// of trigger it does not know) is kept as stored and written back after the readable
    /// ones at the next save, as Buttons keeps such bindings: after an edit of the app's
    /// buttons and after all of them were removed too. A number in the list is dropped, as
    /// Buttons drops one. Nothing runs it.
    func testAnOwnBindingThisVersionCannotReadIsKeptForTheNextSave() throws {
        let good = String(data: try JSONEncoder().encode(binding(3, "undo")), encoding: .utf8)!
        let newer = #"{"triggerEvent":{"type":"pedal","code":7,"modifiers":0},"systemShortcutName":"copy","isEnabled":true}"#
        let entry = #"{"path":"/Applications/A.app","buttons":{"binding":["# + good + "," + newer + #",42]}}"#
        let read = try JSONDecoder().decode(Application.self, from: Data(entry.utf8))
        XCTAssertEqual(read.ownButtonBindings.map(\.systemShortcutName), ["undo"])

        func stored(_ application: Application) throws -> [[String: Any]] {
            let object = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(application)) as? [String: Any]
            let buttons = try XCTUnwrap(object?["buttons"] as? [String: Any], "the buttons are stored")
            return try XCTUnwrap(buttons["binding"] as? [[String: Any]])
        }
        func isTheNewerOne(_ element: [String: Any]?) -> Bool {
            return (element?["triggerEvent"] as? [String: Any])?["type"] as? String == "pedal"
                && element?["systemShortcutName"] as? String == "copy"
        }
        var list = try stored(read)
        XCTAssertEqual(list.count, 2, "the readable one, then the newer one")
        XCTAssertEqual(list.first?["systemShortcutName"] as? String, "undo")
        XCTAssertTrue(isTheNewerOne(list.last))

        read.setOwnButtonBindings([binding(4, "paste")])
        list = try stored(read)
        XCTAssertEqual(list.map { $0["systemShortcutName"] as? String }, ["paste", "copy"])
        XCTAssertTrue(isTheNewerOne(list.last), "an edit of the app's buttons keeps it")

        read.setOwnButtonBindings([])
        XCTAssertFalse(read.hasOwnButtons)
        list = try stored(read)
        XCTAssertEqual(list.count, 1)
        XCTAssertTrue(isTheNewerOne(list.first), "removing every binding the page shows keeps it")

        let again = try JSONDecoder().decode(Application.self, from: try JSONEncoder().encode(read))
        XCTAssertTrue(again.ownButtonBindings.isEmpty)
        XCTAssertTrue(isTheNewerOne(try stored(again).first), "and so on, save after save")

        // It never runs: the app has no buttons of its own for the input side.
        Options.shared.buttons.binding = [binding(3, "copy")]
        Options.shared.application.applications = Self.makeStore([again])
        ButtonUtils.shared.invalidateCache()
        let a = ShortcutRingChoice.FrontApp(bundlePath: "/Applications/A.app", executablePath: nil)
        XCTAssertEqual(action(3, in: a), "copy")
    }

    /// A settings file carries an app's own buttons; the sheet before an import says how
    /// many apps have some, and lists each with its app, "Default" for one without action.
    func testTheSettingsFileCarriesAnAppsOwnButtons() throws {
        let options = Options()
        options.defaults = TestDefaults.make(for: self)
        let notes = Application(path: "/Applications/Notes.app")
        notes.setOwnButtonBindings([binding(3, "undo"), binding(4, "")])
        options.application.applications.append(notes)
        options.application.applications.append(Application(path: "/Applications/Mail.app"))
        let data = try SettingsFile.export(from: options, now: Date(timeIntervalSinceReferenceDate: 800_000_000)).get()

        let contents = try SettingsFile.read(data).get()
        XCTAssertEqual(contents.applications?.first?.ownButtonBindings, notes.ownButtonBindings)
        XCTAssertEqual(contents.applications?.last?.hasOwnButtons, false)
        let items = SettingsFileText.items(of: contents).map(\.text)
        XCTAssertTrue(items.contains("1 app with buttons of its own"), "\(items)")
        let lines = SettingsFileText.actionLines(of: contents)
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].hasSuffix(" in Notes: Undo"), lines[0])
        XCTAssertTrue(lines[1].hasSuffix(" in Notes: Default"), lines[1])
        XCTAssertEqual(SettingsFileText.counted(3, "general-settings-import-app-buttons"), "3 apps with buttons of their own")
    }

    // MARK: - Logitech buttons follow the app in front

    /// A Logitech button no general binding uses is taken from the mouse only while an app
    /// that has its own binding for it is in front; one the app sets to "Default" is the
    /// mouse's there unless another binding of that button still needs it.
    func testTheLogitechButtonsFollowTheAppInFront() {
        let gestureButton: UInt16 = 1000
        let modeShift: UInt16 = 1001
        let isLogi: (UInt16) -> Bool = { $0 >= 1000 }
        let command = UInt(CGEventFlags.maskCommand.rawValue)
        let general = [binding(modeShift, "copy"), binding(3, "paste")]

        XCTAssertEqual(LogiUsageBootstrap.buttonBindingCodes(general: general, frontAppOwn: [], isLogiCode: isLogi), [modeShift])
        XCTAssertEqual(
            LogiUsageBootstrap.buttonBindingCodes(general: general, frontAppOwn: [binding(gestureButton, "undo")], isLogiCode: isLogi),
            [modeShift, gestureButton], "taken while the app is in front"
        )
        XCTAssertEqual(
            LogiUsageBootstrap.buttonBindingCodes(general: general, frontAppOwn: [binding(modeShift, "")], isLogiCode: isLogi),
            [], "given back while the app is in front"
        )
        XCTAssertEqual(
            LogiUsageBootstrap.buttonBindingCodes(
                general: general + [binding(modeShift, "cut", modifiers: command)],
                frontAppOwn: [binding(modeShift, "")], isLogiCode: isLogi
            ),
            [modeShift], "⌘ and the button still needs it"
        )
        XCTAssertEqual(
            LogiUsageBootstrap.buttonBindingCodes(
                general: general + [binding(gestureButton, SystemShortcut.mouseGestureNavigation.identifier)],
                frontAppOwn: [binding(gestureButton, "")], isLogiCode: isLogi
            ),
            [modeShift], "Gesture Navigation's button is given back too: nothing stays general"
        )
    }

    /// The registry is told: in the app the button is used, in another app it is not.
    func testTheRegistryFollowsTheAppInFront() {
        let gestureButton: UInt16 = 1000
        set(general: [], safari: [binding(gestureButton, "undo")])
        defer {
            Options.shared.application.applications = Self.makeStore([])
            LogiUsageBootstrap.refreshButtonUsage(front: nil)
        }
        LogiUsageBootstrap.refreshButtonUsage(front: Self.safari)
        XCTAssertTrue(LogiCenter.shared.usages(of: gestureButton).contains(.buttonBinding))
        LogiUsageBootstrap.refreshButtonUsage(front: Self.textEdit)
        XCTAssertFalse(LogiCenter.shared.usages(of: gestureButton).contains(.buttonBinding), "given back to the mouse")
        var scrollio = Self.safari
        scrollio.isScrollio = true
        LogiUsageBootstrap.refreshButtonUsage(front: scrollio)
        XCTAssertFalse(LogiCenter.shared.usages(of: gestureButton).contains(.buttonBinding), "Scrollio in front: Buttons")
    }

    /// A Logitech button that is down when another app comes to the front stays with
    /// Scrollio until it is up (Safari's own action on it ran at the press, and brought
    /// TextEdit forward): only then is it given back to the mouse.
    func testALogitechButtonDownWhileAnotherAppComesForwardIsGivenBackOnlyWhenItIsUp() {
        let gestureButton: UInt16 = 1000
        set(general: [], safari: [binding(gestureButton, "copy")])
        let savedFront = LogiUsageBootstrap.frontApplication
        LogiUsageBootstrap.frontApplication = { Self.textEdit }
        defer {
            LogiUsageBootstrap.frontApplication = savedFront
            Options.shared.application.applications = Self.makeStore([])
            LogiUsageBootstrap.refreshButtonUsage(front: nil)
        }
        let bridge = LogiIntegrationBridge.shared
        let down = InputEvent(type: .mouse, code: gestureButton, modifiers: [], phase: .down, source: .hidPP, device: nil)
        let up = InputEvent(type: .mouse, code: gestureButton, modifiers: [], phase: .up, source: .hidPP, device: nil)
        LogiUsageBootstrap.refreshButtonUsage(front: Self.safari)

        front = Self.safari
        XCTAssertEqual(bridge.dispatchLogiButtonEvent(down), .consumed)
        XCTAssertEqual(executed.map(\.0), [shortcut(SystemShortcut.copy).code])
        LogiUsageBootstrap.refreshButtonUsage(front: Self.textEdit)
        XCTAssertTrue(LogiCenter.shared.usages(of: gestureButton).contains(.buttonBinding), "still down: still Scrollio's")
        LogiUsageBootstrap.refreshButtonUsage(front: Self.textEdit)
        XCTAssertTrue(LogiCenter.shared.usages(of: gestureButton).contains(.buttonBinding))

        front = Self.textEdit
        _ = bridge.dispatchLogiButtonEvent(up)
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
        XCTAssertFalse(LogiCenter.shared.usages(of: gestureButton).contains(.buttonBinding), "up: given back to the mouse")
    }

    /// Switching apps writes no line about the Logitech buttons, however often (it was a
    /// line per switch, a trail of them); a change of the settings writes one when what the
    /// apps' own bindings change, counted over the list, is not what the last line said,
    /// whatever app is in front: the change is made in Scrollio's Settings, so Scrollio is.
    func testOnlyAChangeOfTheSettingsWritesALineAboutTheLogitechButtons() {
        let gestureButton: UInt16 = 1000
        let modeShift: UInt16 = 1001
        var scrollio = Self.safari
        scrollio.isScrollio = true
        var lines: [String] = []
        LogiUsageBootstrap.log = { lines.append($0) }
        defer {
            LogiUsageBootstrap.log = { AppSystemLog.note($0) }
            Options.shared.application.applications = Self.makeStore([])
            LogiUsageBootstrap.refreshButtonUsage(front: nil)
        }
        // From what an earlier test left to nothing of the apps' own.
        LogiUsageBootstrap.refreshButtonUsage(front: scrollio, afterASettingsChange: true)
        lines = []

        set(general: [binding(modeShift, "copy")], safari: [binding(gestureButton, "undo")])
        for _ in 0..<3 {
            LogiUsageBootstrap.refreshButtonUsage(front: Self.safari)
            LogiUsageBootstrap.refreshButtonUsage(front: Self.textEdit)
        }
        XCTAssertEqual(lines, [], "switching apps")

        LogiUsageBootstrap.refreshButtonUsage(front: scrollio, afterASettingsChange: true)
        LogiUsageBootstrap.refreshButtonUsage(front: Self.textEdit, afterASettingsChange: true)
        LogiUsageBootstrap.refreshButtonUsage(front: Self.safari, afterASettingsChange: true)
        XCTAssertEqual(lines, [
            "Buttons: 1 app(s) have their own binding for a Logitech button: 1 Logitech button(s) taken from the mouse "
                + "and 0 given back while such an app is in front",
        ], "one line, with Scrollio in front as with any other app")

        // TextEdit takes the same button, and leaves the mode shift button to the mouse.
        let textEdit = Application(path: Self.textEdit.bundlePath!)
        textEdit.setOwnButtonBindings([binding(gestureButton, "redo"), binding(modeShift, "")])
        Options.shared.application.applications.append(textEdit)
        lines = []
        LogiUsageBootstrap.refreshButtonUsage(front: scrollio, afterASettingsChange: true)
        XCTAssertEqual(lines, [
            "Buttons: 2 app(s) have their own binding for a Logitech button: 1 Logitech button(s) taken from the mouse "
                + "and 1 given back while such an app is in front",
        ])

        Options.shared.application.applications = Self.makeStore([])
        lines = []
        LogiUsageBootstrap.refreshButtonUsage(front: scrollio, afterASettingsChange: true)
        XCTAssertEqual(lines, [
            "Buttons: no app has its own binding for a Logitech button: the Logitech buttons are as Buttons sets them in every app",
        ])
    }
}
