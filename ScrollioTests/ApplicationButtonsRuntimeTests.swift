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
        // From what an earlier test left to nothing tracked.
        LogiUsageBootstrap.frontApplicationChanged(to: safari)
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

    /// The set handed to the mouse follows the app in front, with one line per change and
    /// never the app's name; switching between apps without buttons of their own changes
    /// nothing and writes nothing.
    func testTheTrackedSetFollowsTheAppInFront() {
        set(general: [binding(thumbPanel, gestureAction)], figma: figmaEntry(own: [binding(thumbPanel, ringAction)]))
        LogiUsageBootstrap.frontApplicationChanged(to: safari)
        XCTAssertEqual(tracked, [thumbPanel])
        LogiUsageBootstrap.frontApplicationChanged(to: figma)
        XCTAssertEqual(tracked, [], "the ring in Figma needs the pointer's movement")
        LogiUsageBootstrap.frontApplicationChanged(to: textEdit)
        XCTAssertEqual(tracked, [thumbPanel])
        XCTAssertEqual(lines, [
            "Gestures: the mouse tracks the hold of 1 Logitech button(s) itself",
            "Gestures: the mouse tracks no Logitech button's hold itself, by the own bindings of the app in front",
            "Gestures: the mouse tracks the hold of 1 Logitech button(s) itself",
        ])
        lines = []
        for _ in 0..<3 {
            LogiUsageBootstrap.frontApplicationChanged(to: safari)
            LogiUsageBootstrap.frontApplicationChanged(to: textEdit)
        }
        XCTAssertEqual(lines, [], "nothing changed")
        XCTAssertEqual(tracked, [thumbPanel])

        // Scrollio itself in front: Buttons.
        var scrollio = figma
        scrollio.isScrollio = true
        LogiUsageBootstrap.frontApplicationChanged(to: scrollio)
        XCTAssertEqual(tracked, [thumbPanel])
        // The setting off: none, wherever.
        Options.shared.gesture.deviceTracking = false
        LogiUsageBootstrap.refreshGestureTracking(front: safari)
        XCTAssertEqual(tracked, [])
        Options.shared.gesture.deviceTracking = true
        LogiUsageBootstrap.refreshGestureTracking(front: safari)
        for line in lines {
            XCTAssertFalse(line.contains("Figma") || line.contains("/"), line)
        }
    }

    /// A button that is down keeps its tracking, either way, until it is up: a tracked hold
    /// whose swipe brings Figma forward keeps its movement, and the ring Figma's thumb
    /// panel holds keeps the pointer's when Safari comes forward. The release decides
    /// again, with one line.
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
        XCTAssertEqual(lines.count, 1)

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
