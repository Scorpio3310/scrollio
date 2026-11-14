//
//  ApplicationButtonsTests.swift
//  ScrollioTests
//
//  Buttons of an app's own, only what differs from Buttons: how they are stored and read
//  (also from entries without them and from values that cannot be read), how a press is
//  resolved (the app in front, once at the down; the general binding of the same trigger
//  replaced, a new one added, "Default" passing through; Scrollio itself and the ring and
//  Gesture Navigation staying general), the release pairing with its press when the app
//  in front changes meanwhile, the cache following a change of an app, the Logitech
//  buttons that follow the app in front, and the settings file. Nothing reaches the Mac:
//  the app in front is a seam, the executor's posts go to observers.
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

    /// What opens the Shortcut Ring and what runs Gesture Navigation stay general: an app's
    /// binding on such a button is not used, and an app's binding cannot open them.
    func testTheRingAndGestureNavigationStayGeneral() {
        let ring = SystemShortcut.shortcutRing.identifier
        let gesture = SystemShortcut.mouseGestureNavigation.identifier
        let command = UInt(CGEventFlags.maskCommand.rawValue)
        set(
            general: [binding(6, ring), binding(7, gesture), binding(3, "copy")],
            safari: [binding(6, "undo"), binding(7, "undo", modifiers: command), binding(3, ring), binding(5, gesture)]
        )
        XCTAssertEqual(action(6, in: Self.safari), ring)
        XCTAssertEqual(action(7, in: Self.safari), gesture)
        XCTAssertEqual(action(7, modifiers: .maskCommand, in: Self.safari), gesture, "the whole button stays general")
        XCTAssertEqual(action(3, in: Self.safari), "copy", "an app cannot open the ring")
        XCTAssertEqual(action(5, in: Self.safari), nil, "nor run Gesture Navigation")
        XCTAssertEqual(
            ApplicationButtons.usable(Options.shared.application.applications.get(by: Self.safari.bundlePath)!.ownButtonBindings,
                                      general: Options.shared.buttons.binding),
            []
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

    /// The Logitech probe goes by the same bindings as InputProcessor: an app's own
    /// Logitech action runs while it is in front, and its "Default" passes through.
    func testTheLogitechProbeSeesTheAppInFront() {
        let gestureButton: UInt16 = 1005
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

    // MARK: - Logitech buttons follow the app in front

    /// A Logitech button no general binding uses is taken from the mouse only while an app
    /// that has its own binding for it is in front; one the app sets to "Default" is the
    /// mouse's there unless another binding of that button still needs it.
    func testTheLogitechButtonsFollowTheAppInFront() {
        let gestureButton: UInt16 = 1005
        let modeShift: UInt16 = 1003
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
            [modeShift, gestureButton], "Gesture Navigation's button stays as Buttons has it"
        )
    }

    /// The registry is told: in the app the button is used, in another app it is not.
    func testTheRegistryFollowsTheAppInFront() {
        let gestureButton: UInt16 = 1005
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
}
