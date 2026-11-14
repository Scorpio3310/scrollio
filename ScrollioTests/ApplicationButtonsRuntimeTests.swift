//
//  ApplicationButtonsRuntimeTests.swift
//  ScrollioTests
//
//  What a press does when an app's own binding opens the Shortcut Ring or runs Gesture
//  Navigation (the thumb panel in "Figma" opens the ring while Buttons gives it Gesture
//  Navigation; the reverse; a key that opens the ring only in one app; a button that runs
//  Gesture Navigation only in one app): which ring and which gestures, the release, the key
//  tap, the ring's faces, the Logitech divert, the buttons the mouse tracks, the pulses and
//  the pointer freeze. Nothing reaches the Mac: the app in front is a seam, the ring has a
//  screen that only remembers, the executor's posts go to observers, the pointer lock has a
//  recording driver, and under XCTest the Logitech layer has no session.
//

import XCTest
@testable import Scrollio_Debug

private typealias FrontApp = ShortcutRingChoice.FrontApp

private let figmaPath = "/Applications/Figma.app"
private let figma = FrontApp(bundlePath: figmaPath, executablePath: figmaPath + "/Contents/MacOS/Figma")
private let safari = FrontApp(bundlePath: "/Applications/Safari.app", executablePath: "/Applications/Safari.app/Contents/MacOS/Safari")
private let textEdit = FrontApp(
    bundlePath: "/System/Applications/TextEdit.app", executablePath: "/System/Applications/TextEdit.app/Contents/MacOS/TextEdit"
)
/// The MX Master 4's thumb panel (its "Haptic" sense panel, CID 0x01A0).
private let thumbPanel: UInt16 = 2000 + 0x01A0
/// The MX Master gesture button (CID 0x00C3).
private let gestureButton: UInt16 = 1000

private let ringAction = SystemShortcut.shortcutRing.identifier
private let gestureAction = SystemShortcut.mouseGestureNavigation.identifier

private func binding(_ code: UInt16, _ action: String, type: EventType = .mouse, modifiers: UInt = 0) -> ButtonBinding {
    return ButtonBinding(
        triggerEvent: RecordedEvent(type: type, code: code, modifiers: modifiers, deviceFilter: nil),
        systemShortcutName: action,
        isEnabled: true
    )
}

private func opens(_ path: String) -> ShortcutRingPlace {
    return ShortcutRingPlace(openTarget: OpenTargetPayload(path: path, bundleID: nil, arguments: "", kind: .application))
}

/// Figma on the list with `own` as its own buttons; with `ring` a ring of its own (Copy on
/// top), with `gestures` a set of its own (Paste up).
private func figmaEntry(own: [ButtonBinding], ring: Bool = false, gestures: Bool = false) -> Application {
    let application = Application(path: figmaPath)
    application.setOwnButtonBindings(own)
    if ring {
        application.setUsesGeneralRing(false, general: .default)
        application.ring?[0] = ShortcutRingPlace(SystemShortcut.copy)
    }
    if gestures {
        application.setUsesGeneralGestures(false, general: .default)
        var actions = GestureActions.default
        actions.up = GestureAction(SystemShortcut.paste)
        application.setOwnGestures(actions: actions, invertHorizontal: false)
    }
    return application
}

// MARK: - A press

final class ApplicationButtonsPressTests: XCTestCase {

    private var harness: RingHarness!
    private var controller: ShortcutRingController { return harness.controller }
    private var front: FrontApp?
    private var savedBindings: [ButtonBinding] = []
    private var savedApplications: EnhanceArray<Application>!
    private var savedGesture = MouseGestureSettings.default
    private var gestureLines: [String] = []
    private var pulses: [String] = []
    private var pointerAssociations: [Bool] = []

    override func setUp() {
        super.setUp()
        savedBindings = Options.shared.buttons.binding
        savedApplications = Options.shared.application.applications
        savedGesture = Options.shared.gesture
        front = safari
        gestureLines = []
        pulses = []
        pointerAssociations = []
        ShortcutRingController.forgetPreparedFaces()
        ButtonUtils.shared.frontApplication = { [unowned self] in self.front }
        InputProcessor.shared.setTestingMouseGestureFrontApplication { [unowned self] in self.front }
        InputProcessor.shared.setTestingMouseGestureLog { [unowned self] in self.gestureLines.append($0) }
        InputProcessor.shared.setTestingGestureHapticPlayer { [unowned self] cue, code in self.pulses.append("pulse \(cue) \(code)") }
        MouseGesturePointerLock.shared.setTestingDriver(MouseGesturePointerDriver(
            currentLocation: { CGPoint(x: 100, y: 100) },
            setAssociated: { [unowned self] in self.pointerAssociations.append($0) },
            warp: { _ in }
        ))
        MouseInteractionSessionController.shared.setTestingMotionTapHooks()
        MouseInteractionSessionController.shared.clearAllSessions()
        ShortcutExecutor.shared.setTestingMouseEventObserver()
        ShortcutExecutor.shared.setTestingKeyboardShortcutObserver()
        InputProcessor.shared.clearActiveBindings()
        var gesture = MouseGestureSettings.default
        gesture.freezePointer = false
        gesture.hapticFeedback = true
        Options.shared.gesture = gesture
        harness = RingHarness()
        // The ring the app in front has, as the app's choice makes it.
        controller.environment.choice = { [unowned self] general in
            ShortcutRingChoice.make(front: self.front, applications: Options.shared.application.applications, general: general)
        }
        ShortcutRingController.setTestingController(controller)
    }

    override func tearDown() {
        waitForMainQueue()
        InputProcessor.shared.clearActiveBindings()
        ShortcutRingController.setTestingController(nil)
        harness = nil
        ShortcutRingController.forgetPreparedFaces()
        InputProcessor.shared.setTestingMouseGestureFrontApplication(nil)
        InputProcessor.shared.setTestingMouseGestureLog(nil)
        InputProcessor.shared.clearTestingGestureHapticPlayer()
        MouseGesturePointerLock.shared.clearTestingDriver()
        MouseInteractionSessionController.shared.clearAllSessions()
        MouseInteractionSessionController.shared.clearTestingMotionTapHooks()
        ShortcutExecutor.shared.clearTestingMouseEventObserver()
        ShortcutExecutor.shared.clearTestingKeyboardShortcutObserver()
        ButtonUtils.shared.frontApplication = { .current() }
        Options.shared.gesture = savedGesture
        Options.shared.buttons.binding = savedBindings
        Options.shared.application.applications = savedApplications
        ButtonUtils.shared.invalidateCache()
        savedApplications = nil
        super.tearDown()
    }

    private func waitForMainQueue() {
        let done = expectation(description: "main queue")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 1)
    }

    private func set(general: [ButtonBinding], figma: Application) {
        Options.shared.buttons.binding = general
        Options.shared.application.applications = EnhanceArray<Application>(withArray: [figma], matchKey: "path")
        ButtonUtils.shared.invalidateCache()
    }

    private func button(_ phase: InputPhase, _ code: UInt16 = thumbPanel) -> InputEvent {
        return InputEvent(type: .mouse, code: code, modifiers: [], phase: phase, source: .hidPP, device: nil)
    }

    private func process(_ event: InputEvent) -> InputResult {
        return InputProcessor.shared.process(event)
    }

    private func topTitle() -> String? {
        return harness.presenter.shown.last?.face.places[0].title
    }

    /// In Figma the thumb panel opens Figma's own ring, while Buttons gives it Gesture
    /// Navigation: no gesture hold starts, the pulses play on the thumb panel as for a ring
    /// that a general binding opens, the place lit by the hand runs at the release. In
    /// another app the same button runs the general gestures. Figma without a ring of its
    /// own opens the general ring.
    func testInAnAppTheButtonOfGestureNavigationOpensTheAppsRing() {
        let entry = figmaEntry(own: [binding(thumbPanel, ringAction)], ring: true)
        set(general: [binding(thumbPanel, gestureAction)], figma: entry)

        front = figma
        XCTAssertEqual(process(button(.down)), .consumed)
        XCTAssertTrue(controller.isHeld)
        XCTAssertFalse(InputProcessor.shared.hasActiveMouseGestureSessions, "no gesture hold")
        harness.runScheduled()
        XCTAssertEqual(topTitle(), SystemShortcut.copy.localizedName, "Figma's own ring")
        XCTAssertEqual(harness.logLines.first, "Shortcut Ring: opened by a button over HID++, the own ring of the app in front")
        harness.moveHand(by: CGPoint(x: 0, y: -70))
        XCTAssertEqual(controller.session.lit, 0)
        harness.runScheduled()
        XCTAssertTrue(harness.log.contains("pulse lockIn \(thumbPanel)"), "\(harness.log)")
        XCTAssertEqual(process(button(.up)), .consumed)
        harness.runScheduled()
        XCTAssertEqual(Array(harness.log.suffix(2)), ["pulse commit \(thumbPanel)", "run copy"])
        waitForMainQueue()
        XCTAssertEqual(gestureLines, [], "no gesture ran")

        front = safari
        XCTAssertEqual(process(button(.down)), .consumed)
        XCTAssertTrue(InputProcessor.shared.hasActiveMouseGestureSessions)
        XCTAssertFalse(controller.isOpen, "no ring in Safari")
        InputProcessor.shared.handleMouseGestureMovement(deltaX: 0, deltaY: -45)
        XCTAssertEqual(process(button(.up)), .consumed)
        waitForMainQueue()
        XCTAssertEqual(gestureLines, ["Gestures: up ran missionControl"])
        XCTAssertEqual(pulses, ["pulse lockIn \(thumbPanel)"])

        entry.setUsesGeneralRing(true, general: .default)
        front = figma
        harness.tap()
        XCTAssertEqual(topTitle(), SystemShortcut.missionControl.localizedName, "the general ring")
        controller.cancel()
    }

    /// The reverse: Buttons opens the ring with the thumb panel, Figma runs Gesture
    /// Navigation with it. In Figma the hold runs Figma's own gestures (the general ones
    /// once Figma uses them again) and opens no ring; elsewhere the general ring opens.
    func testInAnAppTheButtonOfTheRingRunsTheAppsGestures() {
        let entry = figmaEntry(own: [binding(thumbPanel, gestureAction)], gestures: true)
        set(general: [binding(thumbPanel, ringAction)], figma: entry)

        front = figma
        XCTAssertEqual(process(button(.down)), .consumed)
        XCTAssertFalse(controller.isOpen, "no ring in Figma")
        InputProcessor.shared.handleMouseGestureMovement(deltaX: 0, deltaY: -45)
        XCTAssertEqual(process(button(.up)), .consumed)
        waitForMainQueue()
        XCTAssertEqual(gestureLines, ["Gestures: up ran paste, the app in front has its own gestures"])

        front = safari
        XCTAssertEqual(process(button(.down)), .consumed)
        XCTAssertTrue(controller.isHeld)
        XCTAssertFalse(InputProcessor.shared.hasActiveMouseGestureSessions)
        XCTAssertEqual(process(button(.up)), .consumed)
        controller.cancel()

        gestureLines = []
        entry.setUsesGeneralGestures(true, general: Options.shared.gesture)
        front = figma
        XCTAssertEqual(process(button(.down)), .consumed)
        InputProcessor.shared.handleMouseGestureMovement(deltaX: 0, deltaY: -45)
        XCTAssertEqual(process(button(.up)), .consumed)
        waitForMainQueue()
        XCTAssertEqual(gestureLines, ["Gestures: up ran missionControl"], "the general set")
    }

    /// A button that runs Gesture Navigation only in one app: there a hold, with its pulse
    /// and the pointer kept still as Gestures says; in any other app the press goes on as
    /// the button's own.
    func testAButtonThatRunsGestureNavigationOnlyInOneApp() {
        Options.shared.gesture.freezePointer = true
        set(general: [], figma: figmaEntry(own: [binding(gestureButton, gestureAction)]))

        front = figma
        XCTAssertEqual(process(button(.down, gestureButton)), .consumed)
        XCTAssertTrue(MouseGesturePointerLock.shared.isLocked, "the pointer is kept still, as for Buttons' gesture button")
        InputProcessor.shared.handleMouseGestureMovement(deltaX: 0, deltaY: -45)
        XCTAssertEqual(process(button(.up, gestureButton)), .consumed)
        XCTAssertFalse(MouseGesturePointerLock.shared.isLocked)
        XCTAssertEqual(pointerAssociations, [false, true])
        waitForMainQueue()
        XCTAssertEqual(gestureLines, ["Gestures: up ran missionControl"])
        XCTAssertEqual(pulses, ["pulse lockIn \(gestureButton)"])

        front = safari
        XCTAssertEqual(process(button(.down, gestureButton)), .passthrough)
        XCTAssertEqual(process(button(.up, gestureButton)), .passthrough)
        XCTAssertFalse(InputProcessor.shared.hasActiveMouseGestureSessions)
    }

    /// The release ends what the press started, whatever app came to the front during the
    /// hold: a ring opened by Figma's binding takes its button's up and starts no gesture;
    /// a gesture begun in Safari ends at its up with the set it began with, and no ring
    /// opens.
    func testTheReleaseEndsWhatThePressStartedWhenAnotherAppComesToTheFront() {
        set(general: [binding(thumbPanel, gestureAction)], figma: figmaEntry(own: [binding(thumbPanel, ringAction)]))

        front = figma
        XCTAssertEqual(process(button(.down)), .consumed)
        XCTAssertTrue(controller.isHeld)
        front = safari
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        XCTAssertFalse(controller.isOpen, "another app in front closes the ring, as for any ring")
        XCTAssertEqual(process(button(.up)), .consumed, "its up is the ring's")
        XCTAssertFalse(InputProcessor.shared.hasActiveMouseGestureSessions)
        waitForMainQueue()
        XCTAssertEqual(gestureLines, [])

        front = safari
        XCTAssertEqual(process(button(.down)), .consumed)
        front = figma
        InputProcessor.shared.handleMouseGestureMovement(deltaX: 0, deltaY: -45)
        XCTAssertEqual(process(button(.up)), .consumed)
        XCTAssertFalse(controller.isOpen, "no ring opened")
        XCTAssertFalse(InputProcessor.shared.hasActiveMouseGestureSessions)
        waitForMainQueue()
        XCTAssertEqual(gestureLines, ["Gestures: up ran missionControl"])

        // The ring held open while Figma stays: the release closes the hold, nothing else.
        front = figma
        XCTAssertEqual(process(button(.down)), .consumed)
        XCTAssertEqual(process(button(.up)), .consumed)
        XCTAssertTrue(controller.isOpen, "no movement: the ring stands open")
        XCTAssertFalse(InputProcessor.shared.hasActiveMouseGestureSessions)
        controller.cancel()
    }

    private static let ringKey: UInt16 = 49   // Space
    private static let ringKeyFlags: CGEventFlags = [.maskControl, .maskAlternate]

    private func key(down: Bool, flags: CGEventFlags = ringKeyFlags, repeating: Bool = false) -> InputEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: Self.ringKey, keyDown: down)!
        event.flags = flags
        if repeating {
            event.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        }
        return InputEvent(fromCGEvent: event)
    }

    /// A key that opens the ring only in Figma: the keys tap is needed for it alone; in
    /// Figma it opens the ring, and its repeats and its release stay the ring's when
    /// another app comes to the front; in another app the key is the app's.
    func testAKeyThatOpensTheRingOnlyInOneApp() {
        let ringKey = binding(Self.ringKey, ringAction, type: .keyboard, modifiers: UInt(Self.ringKeyFlags.rawValue))
        set(general: [], figma: figmaEntry(own: []))
        XCTAssertFalse(ButtonUtils.shared.hasKeyboardTriggers)
        XCTAssertFalse(InputProcessor.shared.needsKeyEvents)
        set(general: [], figma: figmaEntry(own: [ringKey]))
        XCTAssertTrue(ButtonUtils.shared.hasKeyboardTriggers, "Figma's own key")
        XCTAssertTrue(InputProcessor.shared.needsKeyEvents)

        front = figma
        XCTAssertEqual(process(key(down: true)), .consumed)
        XCTAssertTrue(controller.isHeld)
        front = safari
        XCTAssertEqual(process(key(down: true, repeating: true)), .consumed)
        XCTAssertEqual(process(key(down: true, flags: [], repeating: true)), .consumed, "a repeat without the modifiers too")
        XCTAssertTrue(controller.isHeld)
        XCTAssertEqual(process(key(down: false)), .consumed)
        XCTAssertTrue(controller.isOpen)
        controller.cancel()

        XCTAssertEqual(process(key(down: true)), .passthrough, "in Safari the key is Safari's")
        XCTAssertEqual(process(key(down: false)), .passthrough)
        XCTAssertFalse(controller.isOpen)
    }

    /// A ring an app's binding opens keeps the pointer still as the switch of the ring
    /// that opens says (here the app's own ring's, the general one off), for the hold alone.
    func testARingAnAppsBindingOpensKeepsThePointerStillAsItsRingsSwitchSays() {
        let entry = figmaEntry(own: [binding(thumbPanel, ringAction)], ring: true)
        entry.setOwnRingFreezePointer(true)
        set(general: [], figma: entry)
        harness.ring.freezePointer = false
        front = figma
        XCTAssertEqual(process(button(.down)), .consumed)
        XCTAssertEqual(harness.pointerLocks, ["lock"])
        XCTAssertEqual(process(button(.up)), .consumed)
        XCTAssertEqual(harness.pointerLocks, ["lock", "unlock"])
        controller.cancel()
    }

    /// A Logitech action on the plain button does not win over a binding of the same button
    /// with modifier keys that the press holds (the bridge used to look at the Logitech
    /// bindings alone, and the plain one matched every press): Buttons gives the mode shift
    /// button SmartShift, Figma ⌥ + mode shift the ring. In Figma ⌥ + mode shift opens the
    /// ring and the plain press is SmartShift; in Safari ⌥ + mode shift is SmartShift. The
    /// same with the general bindings alone: ⌥ + mode shift runs Copy.
    func testABindingWithModifierKeysWinsOverALogitechActionOnThePlainButton() {
        let modeShift: UInt16 = 1001
        let option = UInt(CGEventFlags.maskAlternate.rawValue)
        let smartShift = "logiSmartShiftToggle"
        let bridge = LogiIntegrationBridge.shared
        func press(_ phase: InputPhase, _ flags: CGEventFlags) -> InputEvent {
            return InputEvent(type: .mouse, code: modeShift, modifiers: flags, phase: phase, source: .hidPP, device: nil)
        }
        set(general: [binding(modeShift, smartShift)], figma: figmaEntry(own: [binding(modeShift, ringAction, modifiers: option)]))

        front = figma
        XCTAssertEqual(bridge.dispatchLogiButtonEvent(press(.down, .maskAlternate)), .consumed)
        XCTAssertTrue(controller.isHeld, "Figma's ⌥ + mode shift opens the ring")
        XCTAssertEqual(bridge.dispatchLogiButtonEvent(press(.up, .maskAlternate)), .consumed)
        controller.cancel()
        XCTAssertEqual(bridge.dispatchLogiButtonEvent(press(.down, [])), .logiAction(name: smartShift))
        _ = bridge.dispatchLogiButtonEvent(press(.up, []))

        front = safari
        XCTAssertEqual(bridge.dispatchLogiButtonEvent(press(.down, .maskAlternate)), .logiAction(name: smartShift))
        _ = bridge.dispatchLogiButtonEvent(press(.up, .maskAlternate))
        XCTAssertFalse(controller.isOpen)

        set(general: [binding(modeShift, smartShift), binding(modeShift, SystemShortcut.copy.identifier, modifiers: option)],
            figma: figmaEntry(own: []))
        XCTAssertEqual(bridge.dispatchLogiButtonEvent(press(.down, .maskAlternate)), .consumed, "Copy, not SmartShift")
        _ = bridge.dispatchLogiButtonEvent(press(.up, .maskAlternate))
        XCTAssertEqual(bridge.dispatchLogiButtonEvent(press(.down, [])), .logiAction(name: smartShift))
        _ = bridge.dispatchLogiButtonEvent(press(.up, []))
    }

    /// The back button set up for the ring while the mouse was on its receiver is stored
    /// under its Logitech code; over Bluetooth the same button arrives as the standard
    /// button 3, and it opens the ring all the same: Buttons' ring, and in Figma by Figma's
    /// own binding. Its release is the ring's. Elsewhere Figma's binding is not there.
    func testTheStandardButtonOpensTheRingItsLogitechTwinIsSetUpFor() {
        let logitechBack = LogiCenter.shared.scrollioCode(for: .back)
        func back(_ phase: InputPhase) -> InputEvent { return RingHarness.button(phase, code: 3) }

        set(general: [binding(logitechBack, ringAction)], figma: figmaEntry(own: []))
        XCTAssertEqual(process(back(.down)), .consumed)
        XCTAssertTrue(controller.isHeld, "Buttons' ring")
        XCTAssertEqual(process(back(.up)), .consumed)
        controller.cancel()

        set(general: [], figma: figmaEntry(own: [binding(logitechBack, ringAction)], ring: true))
        front = figma
        XCTAssertEqual(process(back(.down)), .consumed)
        XCTAssertTrue(controller.isHeld)
        harness.runScheduled()
        XCTAssertEqual(topTitle(), SystemShortcut.copy.localizedName, "Figma's own ring")
        XCTAssertEqual(process(back(.up)), .consumed)
        controller.cancel()
        front = safari
        XCTAssertEqual(process(back(.down)), .passthrough, "in Safari the button is Safari's")
        XCTAssertEqual(process(back(.up)), .passthrough)
        XCTAssertFalse(controller.isOpen)
    }
}

// MARK: - The ring's faces

final class ApplicationButtonsRingFacesTests: XCTestCase {

    private let textEditPath = "/System/Applications/TextEdit.app"
    private var options: Options!
    private var harness: RingHarness?

    override func setUp() {
        super.setUp()
        ShortcutRingController.forgetPreparedFaces()
        options = Options()
        options.defaults = TestDefaults.make(for: self)
    }

    override func tearDown() {
        ShortcutRingController.setTestingController(nil)
        harness = nil
        ShortcutRingController.forgetPreparedFaces()
        options = nil
        super.tearDown()
    }

    private func list(_ applications: [Application]) -> EnhanceArray<Application> {
        return EnhanceArray<Application>(withArray: applications, matchKey: "path")
    }

    /// The faces made at launch when no binding of Buttons opens the ring: the ring of an
    /// app whose own binding opens it (its own ring, or the general one when it has none);
    /// not the ring of an app nothing opens it in, nor of an app whose own binding takes
    /// the ring's button of Buttons away.
    func testTheFacesAtLaunchCountTheAppsOwnBindings() {
        var general = ShortcutRingSettings.default
        general[5] = opens(textEditPath)
        options.ring = general
        let figma = figmaEntry(own: [binding(thumbPanel, ringAction)], ring: true)
        figma.ring?[2] = opens(textEditPath)
        let notes = Application(path: "/Applications/Notes.app")
        notes.setUsesGeneralRing(false, general: .default)
        notes.ring?[3] = opens(textEditPath)
        options.application.applications = list([figma, notes])
        XCTAssertEqual(ShortcutRingController.ringsToPrepareAtLaunch(options: options), [figma.ringThatOpens(general: general)],
                       "only Figma's binding opens a ring: Figma's")

        figma.setUsesGeneralRing(true, general: general)
        XCTAssertEqual(ShortcutRingController.ringsToPrepareAtLaunch(options: options), [general],
                       "Figma without a ring of its own opens the general one")

        // Buttons opens the ring with the thumb panel; Figma gives it Copy.
        figma.setUsesGeneralRing(false, general: general)
        figma.setOwnButtonBindings([binding(thumbPanel, SystemShortcut.copy.identifier)])
        options.buttons.binding = [binding(thumbPanel, ringAction)]
        XCTAssertEqual(
            ShortcutRingController.ringsToPrepareAtLaunch(options: options),
            [general, notes.ringThatOpens(general: general)],
            "Figma's ring cannot open"
        )
        // Of two entries of one path, the one a press finds counts.
        let older = figmaEntry(own: [], ring: true)
        older.ring?[6] = opens(textEditPath)
        options.application.applications = list([older, figma, notes])
        XCTAssertFalse(ShortcutRingController.ringsToPrepareAtLaunch(options: options).contains(older.ringThatOpens(general: general)))
    }

    /// After a change of the settings that makes a ring able to open (here: Figma's own
    /// key), its face is made as at launch: decided on a later turn (a burst of changes
    /// asks once), one place per turn, never while a ring is open, and not again once it
    /// is there.
    func testAfterAChangeTheFaceOfARingOnlyAnAppsBindingOpensIsMade() throws {
        let figma = figmaEntry(own: [], ring: true)
        figma.ring?[2] = opens(textEditPath)
        figma.ring?[4] = opens("/System/Applications/Preview.app")
        options.application.applications = list([figma])

        var turns: [(delay: TimeInterval, block: () -> Void)] = []
        var lookedUp = 0
        func prepare() {
            ShortcutRingController.prepareMissingFaces(options: options, after: { turns.append(($0, $1)) }, makePlace: {
                lookedUp += 1
                return ShortcutRingFace.place($0)
            })
        }
        func nextTurn() {
            guard !turns.isEmpty else { return XCTFail("no turn is due") }
            turns.removeFirst().block()
        }

        prepare()
        nextTurn()
        XCTAssertTrue(turns.isEmpty, "nothing opens a ring yet")

        figma.setOwnButtonBindings([binding(49, ringAction, type: .keyboard, modifiers: UInt(CGEventFlags.maskControl.rawValue))])
        prepare()
        prepare()
        XCTAssertEqual(turns.count, 1, "a burst of changes asks once")
        nextTurn()
        XCTAssertEqual(lookedUp, 0, "nothing in the turn that decides")

        let harness = RingHarness()
        self.harness = harness
        ShortcutRingController.setTestingController(harness.controller)
        harness.controller.triggerPressed(by: RingHarness.button(.down))
        nextTurn()
        XCTAssertEqual(lookedUp, 0, "nothing is looked up while a ring is held")
        XCTAssertEqual(turns.map(\.delay), [ShortcutRingController.launchFaceWait])
        harness.controller.cancel()

        while !turns.isEmpty {
            let before = lookedUp
            nextTurn()
            XCTAssertLessThanOrEqual(lookedUp - before, 1, "one place in a turn")
        }
        XCTAssertEqual(lookedUp, 2)
        let ring = figma.ringThatOpens(general: options.ring)
        XCTAssertNotNil(try XCTUnwrap(ShortcutRingController.preparedFace(for: ring)).places[2].image)

        prepare()
        nextTurn()
        XCTAssertTrue(turns.isEmpty)
        XCTAssertEqual(lookedUp, 2, "a face that is there is not made again")
    }

    /// The observer the launch installs hands a change of an app's own buttons to the pass.
    func testAChangeOfAnAppsButtonsReachesThePass() {
        let figma = figmaEntry(own: [], ring: true)
        figma.ring?[2] = opens(textEditPath)
        options.application.applications = list([figma])
        ShortcutRingController.prepareFacesAfterChanges(options: options)
        let ring = figma.ringThatOpens(general: options.ring)

        figma.setOwnButtonBindings([binding(thumbPanel, ringAction)])
        options.markChanged(.application)
        XCTAssertNil(ShortcutRingController.preparedFace(for: ring), "not in the change's own turn")
        let made = expectation(description: "the face is made on later turns")
        func look(_ left: Int) {
            if ShortcutRingController.preparedFace(for: ring) != nil { return made.fulfill() }
            guard left > 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { look(left - 1) }
        }
        look(150)
        wait(for: [made], timeout: 5)
    }
}

// MARK: - The Logitech divert and the buttons the mouse tracks

final class ApplicationButtonsLogitechTests: XCTestCase {

    private var savedBindings: [ButtonBinding] = []
    private var savedApplications: EnhanceArray<Application>!
    private var savedGesture = MouseGestureSettings.default
    private var savedHeld: (() -> Set<UInt16>)!
    private var savedFront: (() -> FrontApp?)!
    private var held: Set<UInt16> = []
    private var lines: [String] = []

    override func setUp() {
        super.setUp()
        savedBindings = Options.shared.buttons.binding
        savedApplications = Options.shared.application.applications
        savedGesture = Options.shared.gesture
        savedHeld = LogiUsageBootstrap.heldButtonCodes
        savedFront = LogiUsageBootstrap.frontApplication
        held = []
        lines = []
        LogiUsageBootstrap.heldButtonCodes = { [unowned self] in self.held }
        LogiUsageBootstrap.frontApplication = { safari }
        LogiUsageBootstrap.log = { [unowned self] in self.lines.append($0) }
        InputProcessor.shared.setTestingMouseGestureFrontApplication { safari }
        var gesture = MouseGestureSettings.default
        gesture.deviceTracking = true
        gesture.freezePointer = false
        gesture.clickAction = ""
        Options.shared.gesture = gesture
        Options.shared.buttons.binding = []
        Options.shared.application.applications = EnhanceArray<Application>(withArray: [], matchKey: "path")
        ButtonUtils.shared.invalidateCache()
        // From what an earlier test left to nothing tracked, and to a log that last said so.
        LogiUsageBootstrap.frontApplicationChanged(to: safari)
        LogiUsageBootstrap.refreshGestureTracking(front: safari, afterASettingsChange: true)
        lines = []
    }

    override func tearDown() {
        let drained = expectation(description: "main queue")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
        InputProcessor.shared.clearActiveBindings()
        Options.shared.gesture = savedGesture
        Options.shared.buttons.binding = savedBindings
        Options.shared.application.applications = savedApplications
        ButtonUtils.shared.invalidateCache()
        held = []
        LogiUsageBootstrap.frontApplicationChanged(to: nil)
        LogiUsageBootstrap.heldButtonCodes = savedHeld
        LogiUsageBootstrap.frontApplication = savedFront
        LogiUsageBootstrap.log = { AppSystemLog.note($0) }
        ButtonUtils.shared.frontApplication = { .current() }
        InputProcessor.shared.setTestingMouseGestureFrontApplication(nil)
        savedApplications = nil
        super.tearDown()
    }

    private func set(general: [ButtonBinding], figma: Application) {
        Options.shared.buttons.binding = general
        Options.shared.application.applications = EnhanceArray<Application>(withArray: [figma], matchKey: "path")
        ButtonUtils.shared.invalidateCache()
    }

    private var tracked: Set<UInt16> {
        return LogiSessionManager.shared.gestureTrackingCodes
    }

    /// The divert takes a button whose app binding is the ring or Gesture Navigation while
    /// that app is in front, and keeps the button of Buttons' gestures when the app gives it
    /// the ring; an app's "Default" on it gives it back, as on any button.
    func testTheDivertTakesTheButtonsOfAnAppsRingAndGestures() {
        let isLogi: (UInt16) -> Bool = { LogiCenter.shared.isLogiCode($0) }
        XCTAssertEqual(LogiUsageBootstrap.buttonBindingCodes(
            general: [], frontAppOwn: [binding(thumbPanel, ringAction), binding(gestureButton, gestureAction)], isLogiCode: isLogi
        ), [thumbPanel, gestureButton])
        XCTAssertEqual(LogiUsageBootstrap.buttonBindingCodes(
            general: [binding(thumbPanel, gestureAction)], frontAppOwn: [binding(thumbPanel, ringAction)], isLogiCode: isLogi
        ), [thumbPanel])
        XCTAssertEqual(LogiUsageBootstrap.buttonBindingCodes(
            general: [binding(thumbPanel, gestureAction)], frontAppOwn: [binding(thumbPanel, "")], isLogiCode: isLogi
        ), [])

        set(general: [], figma: figmaEntry(own: [binding(thumbPanel, ringAction)]))
        LogiUsageBootstrap.frontApplicationChanged(to: figma)
        XCTAssertTrue(LogiCenter.shared.usages(of: thumbPanel).contains(.buttonBinding))
        LogiUsageBootstrap.frontApplicationChanged(to: safari)
        XCTAssertFalse(LogiCenter.shared.usages(of: thumbPanel).contains(.buttonBinding))
    }

    /// Which buttons the mouse tracks follows the bindings that count while an app is in
    /// front, by the rule "Gesture Navigation is all it does": the thumb panel of Buttons'
    /// gestures is not tracked where the app gives it the ring, "Default" or a Logitech
    /// action; a button that runs Gesture Navigation only in Figma is tracked there only.
    func testTheTrackedButtonsFollowTheAppsOwnBindings() {
        func codes(general: [ButtonBinding], own: [ButtonBinding]) -> Set<UInt16> {
            return LogiUsageBootstrap.gestureTrackingCodes(
                deviceTracking: true, bindings: ApplicationButtons.merged(general: general, own: own), scrollHotkeyCodes: []
            )
        }
        let buttons = [binding(thumbPanel, gestureAction)]
        XCTAssertEqual(codes(general: buttons, own: []), [thumbPanel])
        XCTAssertEqual(codes(general: buttons, own: [binding(thumbPanel, ringAction)]), [])
        XCTAssertEqual(codes(general: buttons, own: [binding(thumbPanel, "")]), [])
        XCTAssertEqual(codes(general: buttons, own: [binding(thumbPanel, "logiSmartShiftToggle")]), [])
        XCTAssertEqual(codes(general: buttons, own: [binding(gestureButton, SystemShortcut.copy.identifier)]), [thumbPanel])
        XCTAssertEqual(codes(general: [binding(gestureButton, "copy")], own: [binding(gestureButton, gestureAction)]), [gestureButton])
        XCTAssertEqual(
            codes(general: [binding(gestureButton, "copy", modifiers: UInt(CGEventFlags.maskCommand.rawValue))],
                  own: [binding(gestureButton, gestureAction)]),
            [], "⌘ and the button still does something else"
        )
    }

    /// The set handed to the mouse follows the app in front, and switching apps writes no
    /// line, however often (it was a line per switch into and out of an app that changes
    /// the set, a trail of them). A change of the settings writes one when what they make
    /// the mice track, counted over the list, is not what the last line said, whatever app
    /// is in front (the change is made in Scrollio's Settings); never an app's name.
    func testTheTrackedSetFollowsTheAppInFront() {
        set(general: [binding(thumbPanel, gestureAction)], figma: figmaEntry(own: [binding(thumbPanel, ringAction)]))
        LogiUsageBootstrap.frontApplicationChanged(to: safari)
        XCTAssertEqual(tracked, [thumbPanel])
        LogiUsageBootstrap.frontApplicationChanged(to: figma)
        XCTAssertEqual(tracked, [], "the ring in Figma needs the pointer's movement")
        LogiUsageBootstrap.frontApplicationChanged(to: textEdit)
        XCTAssertEqual(tracked, [thumbPanel])
        for _ in 0..<3 {
            LogiUsageBootstrap.frontApplicationChanged(to: figma)
            LogiUsageBootstrap.frontApplicationChanged(to: safari)
            LogiUsageBootstrap.frontApplicationChanged(to: textEdit)
        }
        XCTAssertEqual(lines, [], "switching apps")
        XCTAssertEqual(tracked, [thumbPanel])

        // The change of the settings, with Scrollio itself in front (Buttons' set) and with
        // Figma: one line.
        var scrollio = figma
        scrollio.isScrollio = true
        LogiUsageBootstrap.refreshGestureTracking(front: scrollio, afterASettingsChange: true)
        XCTAssertEqual(tracked, [thumbPanel])
        LogiUsageBootstrap.refreshGestureTracking(front: figma, afterASettingsChange: true)
        XCTAssertEqual(tracked, [])
        XCTAssertEqual(lines, [
            "Gestures: the mouse tracks the hold of 1 Logitech button(s) itself; 1 app(s) change which by their own settings while in front",
        ])
        // The setting off: none, wherever, and one line.
        lines = []
        Options.shared.gesture.deviceTracking = false
        LogiUsageBootstrap.refreshGestureTracking(front: safari, afterASettingsChange: true)
        XCTAssertEqual(tracked, [])
        XCTAssertEqual(lines, ["Gestures: the mouse tracks no Logitech button's hold itself"])
        Options.shared.gesture.deviceTracking = true
        LogiUsageBootstrap.refreshGestureTracking(front: safari, afterASettingsChange: true)
        XCTAssertEqual(tracked, [thumbPanel])
        XCTAssertEqual(lines.count, 2)
        for line in lines {
            XCTAssertFalse(line.contains("Figma") || line.contains("/"), line)
        }
    }

    /// An app's own gestures carry their own "Let the mouse track the gesture": the set
    /// handed to the mouse while the app is in front follows that switch, another app and
    /// Scrollio itself get Buttons' set by the general switch, a button that is down keeps
    /// its tracking until it is up, and the log counts such an app (never which).
    func testTheAppsOwnTrackingSwitchCountsWhileItIsInFront() {
        // Figma's own gestures, a copy of the defaults: the mouse does not track there.
        let figmaApp = figmaEntry(own: [], gestures: true)
        XCTAssertEqual(figmaApp.ownGestures?.deviceTracking, false)
        set(general: [binding(thumbPanel, gestureAction)], figma: figmaApp)
        LogiUsageBootstrap.frontApplicationChanged(to: safari)
        XCTAssertEqual(tracked, [thumbPanel], "the general switch, on")
        LogiUsageBootstrap.frontApplicationChanged(to: figma)
        XCTAssertEqual(tracked, [], "Figma's own switch, off")
        var scrollio = figma
        scrollio.isScrollio = true
        LogiUsageBootstrap.frontApplicationChanged(to: scrollio)
        XCTAssertEqual(tracked, [thumbPanel], "Scrollio itself: the general switch")

        // A hold that began in Safari keeps its tracking while Figma comes forward.
        LogiUsageBootstrap.frontApplicationChanged(to: safari)
        held = [thumbPanel]
        LogiUsageBootstrap.frontApplicationChanged(to: figma)
        XCTAssertEqual(tracked, [thumbPanel], "still down: still tracked")
        held = []
        LogiUsageBootstrap.frontApplication = { figma }
        LogiUsageBootstrap.buttonWasReleased(thumbPanel)
        waitForMainQueue()
        XCTAssertEqual(tracked, [])

        // The other way round: the general switch off, Figma's on.
        lines = []
        Options.shared.gesture.deviceTracking = false
        figmaApp.changeOwnGestures { $0.deviceTracking = true }
        LogiUsageBootstrap.refreshGestureTracking(front: figma, afterASettingsChange: true)
        XCTAssertEqual(tracked, [thumbPanel])
        LogiUsageBootstrap.frontApplicationChanged(to: textEdit)
        XCTAssertEqual(tracked, [])
        XCTAssertEqual(lines, [
            "Gestures: the mouse tracks no Logitech button's hold itself; 1 app(s) change which by their own settings while in front",
        ])
    }

    /// A button that is down keeps its tracking, either way, until it is up: a tracked hold
    /// whose swipe brings Figma forward keeps its movement, and the ring Figma's thumb
    /// panel holds keeps the pointer's when Safari comes forward. The release decides
    /// again.
    func testAButtonThatIsDownKeepsItsTrackingUntilItIsUp() {
        set(general: [binding(thumbPanel, gestureAction)], figma: figmaEntry(own: [binding(thumbPanel, ringAction)]))
        LogiUsageBootstrap.frontApplicationChanged(to: safari)
        lines = []

        held = [thumbPanel]
        LogiUsageBootstrap.frontApplicationChanged(to: figma)
        XCTAssertEqual(tracked, [thumbPanel], "still down: still tracked")
        XCTAssertEqual(LogiUsageBootstrap.trackingKeptWhileHeld, [thumbPanel])
        XCTAssertEqual(lines, [])
        held = []
        LogiUsageBootstrap.frontApplication = { figma }
        LogiUsageBootstrap.buttonWasReleased(thumbPanel)
        XCTAssertEqual(tracked, [thumbPanel], "decided on the next turn")
        waitForMainQueue()
        XCTAssertEqual(tracked, [])
        XCTAssertEqual(LogiUsageBootstrap.trackingKeptWhileHeld, [])
        XCTAssertEqual(lines, [], "the release follows the app in front: no line")

        held = [thumbPanel]
        LogiUsageBootstrap.frontApplicationChanged(to: safari)
        XCTAssertEqual(tracked, [], "the ring's hold keeps the pointer's movement")
        held = []
        LogiUsageBootstrap.frontApplication = { safari }
        LogiUsageBootstrap.buttonWasReleased(thumbPanel)
        waitForMainQueue()
        XCTAssertEqual(tracked, [thumbPanel])

        // A button that is down and whose tracking stays the same is no reason for a pass.
        held = [thumbPanel]
        LogiUsageBootstrap.frontApplicationChanged(to: textEdit)
        XCTAssertEqual(LogiUsageBootstrap.trackingKeptWhileHeld, [])
        held = []
    }

    /// The whole way through the bridge: a tracked hold of Buttons' gesture panel in
    /// Safari, Figma (whose own binding opens the ring with it) comes forward in the middle
    /// of the hold, the release comes over HID++; only then does the mouse stop tracking it.
    func testThroughTheBridgeTheReleaseHandsOverTheTracking() {
        LogiUsageBootstrap.heldButtonCodes = { LogiIntegrationBridge.shared.heldButtonCodes }
        set(general: [binding(thumbPanel, gestureAction)], figma: figmaEntry(own: [binding(thumbPanel, ringAction)]))
        ButtonUtils.shared.frontApplication = { safari }
        LogiUsageBootstrap.frontApplicationChanged(to: safari)
        XCTAssertEqual(tracked, [thumbPanel])
        let bridge = LogiIntegrationBridge.shared
        let down = InputEvent(type: .mouse, code: thumbPanel, modifiers: [], phase: .down, source: .hidPP, device: nil,
                              tracksMovementOnDevice: true)
        let up = InputEvent(type: .mouse, code: thumbPanel, modifiers: [], phase: .up, source: .hidPP, device: nil)

        XCTAssertEqual(bridge.dispatchLogiButtonEvent(down), .consumed)
        XCTAssertTrue(InputProcessor.shared.hasActiveMouseGestureSessions)
        ButtonUtils.shared.frontApplication = { figma }
        LogiUsageBootstrap.frontApplication = { figma }
        LogiUsageBootstrap.frontApplicationChanged(to: figma)
        XCTAssertEqual(tracked, [thumbPanel])
        XCTAssertEqual(bridge.dispatchLogiButtonEvent(up), .consumed)
        XCTAssertFalse(InputProcessor.shared.hasActiveMouseGestureSessions)
        waitForMainQueue()
        XCTAssertEqual(tracked, [])
    }

    private func waitForMainQueue() {
        let done = expectation(description: "main queue")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 1)
    }
}
