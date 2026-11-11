import XCTest
@testable import Mos_Debug

/// "Follow the hand" end to end inside Mos: settings, the InputProcessor wiring with a
/// recording dock swipe driver, and the mode rules of the gesture controls. No event is ever posted.
final class MouseGestureInteractiveModeTests: XCTestCase {

    private enum SwipeCall: Equatable {
        case begin(DockSwipeAxis)
        case update(Double)
        case end(Double)
        case cancel
    }

    private var swipeCalls: [SwipeCall] = []
    private var isSynthesizerAvailable = true
    private var clock: TimeInterval = 100
    private var screen = InteractiveGestureScreen(width: 937, spaceCount: nil, frameDuration: 1.0 / 60.0)
    /// Flushes the processor asked for; a test runs them when "the next frame" should happen.
    private var scheduledWork: [(delay: TimeInterval, work: () -> Void)] = []

    private var pointerAssociations: [Bool] = []
    private var pointerWarps: [CGPoint] = []
    /// The gesture controls under test; their controls' targets are weak.
    private var retainedControls: [MouseGestureSettingsControls] = []
    private let pointerAnchor = CGPoint(x: 100, y: 100)

    override func setUp() {
        super.setUp()
        Options.shared.buttons.binding = []
        Options.shared.gesture = .default
        swipeCalls = []
        isSynthesizerAvailable = true
        clock = 100
        screen = InteractiveGestureScreen(width: 937, spaceCount: nil, frameDuration: 1.0 / 60.0)
        scheduledWork = []
        pointerAssociations = []
        pointerWarps = []

        let anchor = pointerAnchor
        MouseGesturePointerLock.shared.setTestingDriver(MouseGesturePointerDriver(
            currentLocation: { anchor },
            setAssociated: { [weak self] in self?.pointerAssociations.append($0) },
            warp: { [weak self] in self?.pointerWarps.append($0) }
        ))
        DockSwipeSynthesizer.shared.setTestingDriver(DockSwipeDriver(
            isAvailable: { [weak self] in self?.isSynthesizerAvailable ?? false },
            begin: { [weak self] in self?.swipeCalls.append(.begin($0)) },
            update: { [weak self] in self?.swipeCalls.append(.update($0)) },
            end: { [weak self] in self?.swipeCalls.append(.end($0)) },
            cancel: { [weak self] in self?.swipeCalls.append(.cancel) }
        ))
        InputProcessor.shared.setTestingInteractiveGestureEnvironment(InteractiveGestureEnvironment(
            screen: { [weak self] in self?.screen ?? InteractiveGestureEnvironment.fallbackScreen },
            now: { [weak self] in self?.clock ?? 0 },
            schedule: { [weak self] delay, work in self?.scheduledWork.append((delay, work)) }
        ))
        ButtonUtils.shared.invalidateCache()
        MouseInteractionSessionController.shared.setTestingMotionTapHooks()
        MouseInteractionSessionController.shared.clearAllSessions()
        ShortcutExecutor.shared.setTestingMouseEventObserver()
        ShortcutExecutor.shared.setTestingKeyboardShortcutObserver()
        InputProcessor.shared.clearActiveBindings()
    }

    override func tearDown() {
        // Gesture actions and terminal swipe events are queued; drain them while the test
        // doubles are still installed.
        waitForMainQueue()
        InputProcessor.shared.clearActiveBindings()
        InputProcessor.shared.clearTestingInteractiveGestureEnvironment()
        DockSwipeSynthesizer.shared.clearTestingDriver()
        MouseInteractionSessionController.shared.clearAllSessions()
        MouseInteractionSessionController.shared.clearTestingMotionTapHooks()
        ShortcutExecutor.shared.clearTestingMouseEventObserver()
        ShortcutExecutor.shared.clearTestingKeyboardShortcutObserver()
        MouseGesturePointerLock.shared.clearTestingDriver()
        Options.shared.gesture = .default
        Options.shared.buttons.binding = []
        ButtonUtils.shared.invalidateCache()
        super.tearDown()
    }

    // MARK: - Settings

    func testModeDefaultsToDiscrete() {
        XCTAssertEqual(MouseGestureSettings.default.mode, .discrete)
        XCTAssertEqual(MouseGestureSettings.default.trackingSpeed, 1)
    }

    func testOldSettingsWithoutModeDecodeAsDiscrete() throws {
        // Written by a build that did not know the mode or the tracking speed.
        let json = """
        {"upAction":"missionControl","downAction":"appExpose","leftAction":"","rightAction":"moveSpaceRight",
         "clickAction":"copy","invertHorizontal":true,"freezePointer":false}
        """
        let settings = try JSONDecoder().decode(MouseGestureSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.mode, .discrete)
        XCTAssertEqual(settings.trackingSpeed, 1)
        XCTAssertEqual(settings.leftAction, "")
        XCTAssertEqual(settings.clickAction, "copy")
        XCTAssertTrue(settings.invertHorizontal)
        XCTAssertFalse(settings.freezePointer)
    }

    func testUnknownOrMalformedModeFallsBackToDiscreteWithoutLosingOtherSettings() throws {
        for mode in ["\"holographic\"", "\"\"", "7", "null", "{\"a\":1}", "true"] {
            let json = "{\"leftAction\":\"copy\",\"invertHorizontal\":true,\"mode\":\(mode),\"trackingSpeed\":2}"
            let settings = try JSONDecoder().decode(MouseGestureSettings.self, from: Data(json.utf8))
            XCTAssertEqual(settings.mode, .discrete, "mode \(mode)")
            XCTAssertEqual(settings.leftAction, "copy", "mode \(mode)")
            XCTAssertTrue(settings.invertHorizontal, "mode \(mode)")
            XCTAssertEqual(settings.trackingSpeed, 2, "mode \(mode)")
        }
    }

    func testInteractiveModeRoundTripsAsAString() throws {
        var settings = MouseGestureSettings.default
        settings.mode = .interactive
        settings.trackingSpeed = 1.5
        let data = try JSONEncoder().encode(settings)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["mode"] as? String, "interactive")
        XCTAssertEqual(object["trackingSpeed"] as? Double, 1.5)
        XCTAssertEqual(try JSONDecoder().decode(MouseGestureSettings.self, from: data), settings)
    }

    func testTrackingSpeedIsClampedEverywhere() throws {
        func decodedSpeed(_ raw: String) throws -> Double {
            let json = "{\"mode\":\"interactive\",\"trackingSpeed\":\(raw)}"
            let settings = try JSONDecoder().decode(MouseGestureSettings.self, from: Data(json.utf8))
            XCTAssertEqual(settings.mode, .interactive, "speed \(raw)")
            return settings.trackingSpeed
        }
        XCTAssertEqual(try decodedSpeed("10"), 3)
        XCTAssertEqual(try decodedSpeed("0.1"), 0.5)
        XCTAssertEqual(try decodedSpeed("-4"), 0.5)
        XCTAssertEqual(try decodedSpeed("2.25"), 2.25)
        XCTAssertEqual(try decodedSpeed("\"fast\""), 1, "a malformed speed falls back to the default")
        XCTAssertEqual(try decodedSpeed("null"), 1)

        var settings = MouseGestureSettings.default
        settings.trackingSpeed = 99
        XCTAssertEqual(settings.trackingSpeed, 3)
        settings.trackingSpeed = .nan
        XCTAssertEqual(settings.trackingSpeed, 1)
        XCTAssertEqual(
            MouseGestureSettings(
                upAction: "", downAction: "", leftAction: "", rightAction: "", clickAction: "",
                invertHorizontal: false, freezePointer: false, mode: .interactive, trackingSpeed: 0
            ).trackingSpeed,
            0.5
        )
    }

    // MARK: - Follow mode drives the swipe

    func testFollowModeDrivesBeginUpdateEnd() {
        configureGestureBinding(mode: .interactive)
        let executed = recordKeyboardShortcuts()

        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down)), .consumed)
        XCTAssertTrue(MouseGesturePointerLock.shared.isLocked)

        // Movement only accumulates until the next frame.
        InputProcessor.shared.handleMouseGestureMovement(deltaX: -100, deltaY: 0)
        XCTAssertEqual(swipeCalls, [])
        XCTAssertEqual(scheduledWork.count, 1)
        runScheduledWork()
        assertSwipeCalls([.begin(.horizontal), .update(0.1)])

        // Several mouse events inside one frame become one update.
        advanceFrame()
        InputProcessor.shared.handleMouseGestureMovement(deltaX: -30, deltaY: 1)
        InputProcessor.shared.handleMouseGestureMovement(deltaX: -30, deltaY: -1)
        InputProcessor.shared.handleMouseGestureMovement(deltaX: -40, deltaY: 0)
        XCTAssertEqual(scheduledWork.count, 1)
        runScheduledWork()
        assertSwipeCalls([.begin(.horizontal), .update(0.1), .update(0.2)])

        // The release is handled inside the button tap callback: the terminal event waits.
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .up)), .consumed)
        XCTAssertEqual(swipeCalls.count, 3)
        XCTAssertFalse(MouseGesturePointerLock.shared.isLocked)
        waitForMainQueue()

        XCTAssertEqual(swipeCalls.count, 4)
        guard case .end(let velocity)? = swipeCalls.last else {
            return XCTFail("expected end, got \(swipeCalls)")
        }
        XCTAssertGreaterThan(velocity, 0, "still moving towards the next Space")
        XCTAssertTrue(executed().isEmpty, "sideways movement must not run the Left / Right actions")
        XCTAssertFalse(InputProcessor.shared.hasActiveMouseGestureSessions)
        XCTAssertFalse(DockSwipeSynthesizer.shared.isActive)
    }

    func testFollowModeMovingBackCancels() {
        configureGestureBinding(mode: .interactive)

        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down)), .consumed)
        InputProcessor.shared.handleMouseGestureMovement(deltaX: -300, deltaY: 0)
        runScheduledWork()
        clock += 0.2
        InputProcessor.shared.handleMouseGestureMovement(deltaX: 60, deltaY: 0)
        runScheduledWork()
        clock += 0.01
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .up)), .consumed)
        waitForMainQueue()

        assertSwipeCalls([.begin(.horizontal), .update(0.3), .update(0.24), .cancel])
    }

    func testFollowModeInvertHorizontalFlipsTheSwipe() {
        configureGestureBinding(mode: .interactive)
        Options.shared.gesture.invertHorizontal = true

        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down)), .consumed)
        InputProcessor.shared.handleMouseGestureMovement(deltaX: -100, deltaY: 0)
        runScheduledWork()

        assertSwipeCalls([.begin(.horizontal), .update(-0.1)])
    }

    func testFollowModeScalesWithTrackingSpeedAndSpaceCount() {
        configureGestureBinding(mode: .interactive)
        Options.shared.gesture.trackingSpeed = 2
        screen.spaceCount = 3 // one Space = 1.5 progress

        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down)), .consumed)
        InputProcessor.shared.handleMouseGestureMovement(deltaX: -100, deltaY: 0)
        runScheduledWork()
        advanceFrame()
        // Far past one Space: stops at one Space.
        InputProcessor.shared.handleMouseGestureMovement(deltaX: -2000, deltaY: 0)
        runScheduledWork()

        assertSwipeCalls([.begin(.horizontal), .update(0.3), .update(1.5)])
    }

    func testClearActiveBindingsMidSwipeCancelsAtOnceAndReleasesThePointer() {
        configureGestureBinding(mode: .interactive)

        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down)), .consumed)
        InputProcessor.shared.handleMouseGestureMovement(deltaX: -100, deltaY: 0)
        runScheduledWork()
        XCTAssertTrue(DockSwipeSynthesizer.shared.isActive)
        XCTAssertTrue(MouseGesturePointerLock.shared.isLocked)

        InputProcessor.shared.clearActiveBindings()

        // Synchronous: sleep and quit cannot wait for the main queue.
        assertSwipeCalls([.begin(.horizontal), .update(0.1), .cancel])
        XCTAssertFalse(DockSwipeSynthesizer.shared.isActive)
        XCTAssertFalse(MouseGesturePointerLock.shared.isLocked)
        XCTAssertEqual(pointerAssociations, [false, true])
        XCTAssertFalse(InputProcessor.shared.hasActiveMouseGestureSessions)

        // Late movement, a stale frame and the orphaned button-up change nothing.
        InputProcessor.shared.handleMouseGestureMovement(deltaX: -100, deltaY: 0)
        runScheduledWork()
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .up)), .passthrough)
        waitForMainQueue()
        XCTAssertEqual(swipeCalls.count, 3)
    }

    func testClearActiveBindingsAfterReleaseDoesNotSendASecondTerminal() {
        configureGestureBinding(mode: .interactive)

        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down)), .consumed)
        InputProcessor.shared.handleMouseGestureMovement(deltaX: -100, deltaY: 0)
        runScheduledWork()
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .up)), .consumed)
        // The end is still queued when the cancel path runs.
        InputProcessor.shared.clearActiveBindings()
        waitForMainQueue()

        assertSwipeCalls([.begin(.horizontal), .update(0.1), .cancel])
    }

    func testFollowModeVerticalMovementRunsTheDiscreteAction() {
        configureGestureBinding(mode: .interactive)
        Options.shared.gesture.upAction = SystemShortcut.copy.identifier
        let executed = recordKeyboardShortcuts()

        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down)), .consumed)
        InputProcessor.shared.handleMouseGestureMovement(deltaX: 0, deltaY: -45)
        runScheduledWork()
        waitForMainQueue()

        let expected = resolvedShortcut(SystemShortcut.copy)
        XCTAssertEqual(executed().count, 1)
        XCTAssertEqual(executed().first?.0, expected.code)
        XCTAssertEqual(executed().first?.1, expected.flags)

        // Sideways afterwards neither swipes nor runs Left / Right; the release is no click.
        advanceFrame()
        InputProcessor.shared.handleMouseGestureMovement(deltaX: -300, deltaY: 0)
        runScheduledWork()
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .up)), .consumed)
        waitForMainQueue()

        XCTAssertEqual(executed().count, 1)
        XCTAssertEqual(swipeCalls, [])
    }

    func testFollowModeClickStillRunsTheClickAction() {
        configureGestureBinding(mode: .interactive)
        Options.shared.gesture.clickAction = SystemShortcut.copy.identifier
        let executed = recordKeyboardShortcuts()

        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down)), .consumed)
        InputProcessor.shared.handleMouseGestureMovement(deltaX: 2, deltaY: -1)
        runScheduledWork()
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .up)), .consumed)
        waitForMainQueue()

        let expected = resolvedShortcut(SystemShortcut.copy)
        XCTAssertEqual(executed().count, 1)
        XCTAssertEqual(executed().first?.0, expected.code)
        XCTAssertEqual(executed().first?.1, expected.flags)
        XCTAssertEqual(swipeCalls, [])
    }

    func testReleaseBeforeTheFirstFrameStillFormsOneWholeSwipe() {
        configureGestureBinding(mode: .interactive)

        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down)), .consumed)
        InputProcessor.shared.handleMouseGestureMovement(deltaX: -100, deltaY: 0)
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .up)), .consumed)
        XCTAssertEqual(swipeCalls, [], "nothing is posted inside the callbacks")
        waitForMainQueue()

        XCTAssertEqual(swipeCalls.count, 3)
        XCTAssertEqual(Array(swipeCalls.prefix(1)), [.begin(.horizontal)])
        guard case .end? = swipeCalls.last else { return XCTFail("expected end, got \(swipeCalls)") }

        // The frame that was scheduled for that movement finds nothing left to do.
        runScheduledWork()
        XCTAssertEqual(swipeCalls.count, 3)
    }

    // MARK: - Frame pacing

    func testMovementIsFlushedAtMostOncePerDisplayFrame() {
        configureGestureBinding(mode: .interactive)
        screen.frameDuration = 0.010

        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down)), .consumed)

        // First movement after a pause: next main-queue turn.
        InputProcessor.shared.handleMouseGestureMovement(deltaX: -20, deltaY: 0)
        XCTAssertEqual(scheduledWork.count, 1)
        XCTAssertEqual(scheduledWork[0].delay, 0)
        runScheduledWork()
        XCTAssertEqual(swipeCalls.count, 2)

        // 4 ms later the hand is still moving: the next flush waits for the rest of the frame.
        clock += 0.004
        InputProcessor.shared.handleMouseGestureMovement(deltaX: -20, deltaY: 0)
        clock += 0.002
        InputProcessor.shared.handleMouseGestureMovement(deltaX: -20, deltaY: 0)
        XCTAssertEqual(scheduledWork.count, 1, "one pending flush, however many events arrive")
        XCTAssertEqual(scheduledWork[0].delay, 0.006, accuracy: 1e-9)
        XCTAssertEqual(swipeCalls.count, 2)

        clock += 0.004
        runScheduledWork()
        assertSwipeCalls([.begin(.horizontal), .update(0.02), .update(0.06)])
    }

    func testMotionTapCallbackNeverDrivesTheSwipeDirectly() {
        configureGestureBinding(mode: .interactive)
        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(fromCGEvent: makeOtherMouseEvent(.otherMouseDown))),
            .consumed
        )

        let motion = makeMouseMoveEvent(deltaX: -100, deltaY: 0, location: pointerAnchor)
        MouseInteractionSessionController.shared.handleMotionTapEventForTests(motion)
        XCTAssertEqual(swipeCalls, [], "posting from the tap callback can time the tap out")

        runScheduledWork()
        assertSwipeCalls([.begin(.horizontal), .update(0.1)])
    }

    func testPointerFreezeWarpDeltaIsCompensated() {
        configureGestureBinding(mode: .interactive)
        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(fromCGEvent: makeOtherMouseEvent(.otherMouseDown))),
            .consumed
        )

        // The detach is not honoured: the pointer drifts 10 pt left and is warped back.
        let drifted = makeMouseMoveEvent(deltaX: -10, deltaY: 0, location: CGPoint(x: 90, y: 100))
        MouseInteractionSessionController.shared.handleMotionTapEventForTests(drifted)
        XCTAssertEqual(pointerWarps, [pointerAnchor])
        // macOS 27: the next event is back on the anchor and reports "hand (-10) + jump (+10)".
        let snappedBack = makeMouseMoveEvent(deltaX: 0, deltaY: 0, location: pointerAnchor)
        MouseInteractionSessionController.shared.handleMotionTapEventForTests(snappedBack)
        runScheduledWork()

        // The hand moved 20 pt in all; without the compensation the swipe would show 10.
        assertSwipeCalls([.begin(.horizontal), .update(0.02)])
    }

    // MARK: - Fallbacks

    func testDiscreteModeNeverTouchesTheSynthesizer() {
        configureGestureBinding(mode: .discrete)
        let executed = recordKeyboardShortcuts()

        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down)), .consumed)
        InputProcessor.shared.handleMouseGestureMovement(deltaX: -45, deltaY: 0)
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .up)), .consumed)
        waitForMainQueue()

        let expected = resolvedShortcut(SystemShortcut.moveSpaceLeft)
        XCTAssertEqual(executed().count, 1)
        XCTAssertEqual(executed().first?.0, expected.code)
        XCTAssertEqual(swipeCalls, [])
        XCTAssertTrue(scheduledWork.isEmpty)
    }

    func testFollowModeFallsBackToDiscreteWhenTheSynthesizerIsUnavailable() {
        configureGestureBinding(mode: .interactive)
        isSynthesizerAvailable = false
        let executed = recordKeyboardShortcuts()

        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down)), .consumed)
        InputProcessor.shared.handleMouseGestureMovement(deltaX: -45, deltaY: 0)
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .up)), .consumed)
        waitForMainQueue()

        let expected = resolvedShortcut(SystemShortcut.moveSpaceLeft)
        XCTAssertEqual(executed().count, 1)
        XCTAssertEqual(executed().first?.0, expected.code)
        XCTAssertEqual(swipeCalls, [])
    }

    // MARK: - Watchdog

    func testWatchdogCancelsTheSwipeAndTheNextPressStartsOver() {
        configureGestureBinding(mode: .interactive)

        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down)), .consumed)
        InputProcessor.shared.handleMouseGestureMovement(deltaX: -100, deltaY: 0)
        runScheduledWork()

        InputProcessor.shared.fireInteractiveGestureWatchdogForTests()
        assertSwipeCalls([.begin(.horizontal), .update(0.1), .cancel])

        // The button-up was lost: movement no longer drags the desktop.
        advanceFrame()
        InputProcessor.shared.handleMouseGestureMovement(deltaX: -100, deltaY: 0)
        runScheduledWork()
        XCTAssertEqual(swipeCalls.count, 3)

        // A new press of the same button is a fresh hold, not a duplicate down.
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down)), .consumed)
        advanceFrame()
        InputProcessor.shared.handleMouseGestureMovement(deltaX: -50, deltaY: 0)
        runScheduledWork()
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .up)), .consumed)
        waitForMainQueue()

        XCTAssertEqual(swipeCalls.count, 6)
        XCTAssertEqual(Array(swipeCalls[3...4]), [.begin(.horizontal), .update(0.05)])
        guard case .end? = swipeCalls.last else { return XCTFail("expected end, got \(swipeCalls)") }
    }

    // MARK: - Synthetic release (the mouse went away mid-hold)

    func testSyntheticReleaseRevertsTheSwipeInsteadOfCommittingIt() {
        configureGestureBinding(mode: .interactive)

        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down)), .consumed)
        InputProcessor.shared.handleMouseGestureMovement(deltaX: -300, deltaY: 0)
        runScheduledWork()
        XCTAssertEqual(swipeCalls.first, .begin(.horizontal))

        // A real release here would end the swipe with a velocity and may switch Spaces.
        let synthetic = InputEvent(
            type: .mouse, code: 3, modifiers: [], phase: .up, source: .hidPP, device: nil,
            isSyntheticRelease: true
        )
        XCTAssertEqual(InputProcessor.shared.process(synthetic), .consumed)
        waitForMainQueue()

        XCTAssertEqual(swipeCalls.last, .cancel)
        XCTAssertFalse(swipeCalls.contains { if case .end = $0 { return true } else { return false } })
        XCTAssertFalse(InputProcessor.shared.hasActiveMouseGestureSessions)
        XCTAssertFalse(MouseGesturePointerLock.shared.isLocked)
        XCTAssertFalse(MouseInteractionSessionController.shared.isMotionTapRunning)
    }

    // MARK: - Mode rules of the gesture controls

    func testModePresentationRules() {
        typealias Presentation = MouseGestureModePresentation
        XCTAssertEqual(
            Presentation.make(storedMode: .discrete, isInteractiveAvailable: true),
            Presentation(selectedMode: .discrete, isInteractiveSelectable: true, areHorizontalActionsEditable: true, noteKey: "gesture-mode-interactive-note")
        )
        XCTAssertEqual(
            Presentation.make(storedMode: .interactive, isInteractiveAvailable: true),
            Presentation(selectedMode: .interactive, isInteractiveSelectable: true, areHorizontalActionsEditable: false, noteKey: "gesture-mode-interactive-note")
        )
        // Unavailable: Mos runs discrete whatever is stored, and the controls say so.
        XCTAssertEqual(
            Presentation.make(storedMode: .interactive, isInteractiveAvailable: false),
            Presentation(selectedMode: .discrete, isInteractiveSelectable: false, areHorizontalActionsEditable: true, noteKey: "gesture-mode-interactive-unavailable")
        )
        XCTAssertEqual(
            Presentation.make(storedMode: .discrete, isInteractiveAvailable: false),
            Presentation(selectedMode: .discrete, isInteractiveSelectable: false, areHorizontalActionsEditable: true, noteKey: "gesture-mode-interactive-unavailable")
        )
    }

    func testControlsFollowModeDisablesOnlyLeftAndRight() {
        let view = makeControlsView(isInteractiveAvailable: { true })
        let mode = modeControl(in: view)

        XCTAssertEqual(mode.selectedSegment, 0)
        XCTAssertTrue(mode.isEnabled(forSegment: 1))
        XCTAssertEqual(mode.label(forSegment: 0), NSLocalizedString("gesture-mode-discrete", comment: ""))
        XCTAssertEqual(mode.label(forSegment: 1), NSLocalizedString("gesture-mode-interactive", comment: ""))
        XCTAssertEqual(note(in: view).stringValue, NSLocalizedString("gesture-mode-interactive-note", comment: ""))
        for direction in ["up", "down", "left", "right", "click"] {
            XCTAssertTrue(actionPopUp(direction, in: view).isEnabled, direction)
        }
        XCTAssertEqual(popUpTitle("left", in: view), SystemShortcut.moveSpaceLeft.localizedName)

        mode.selectedSegment = 1
        mode.sendAction(mode.action, to: mode.target)

        XCTAssertEqual(Options.shared.gesture.mode, .interactive)
        let followValue = NSLocalizedString("gesture-follow-horizontal-value", comment: "")
        XCTAssertNotEqual(followValue, "gesture-follow-horizontal-value")
        for direction in ["left", "right"] {
            XCTAssertFalse(actionPopUp(direction, in: view).isEnabled, direction)
            XCTAssertEqual(popUpTitle(direction, in: view), followValue, direction)
        }
        for direction in ["up", "down", "click"] {
            XCTAssertTrue(actionPopUp(direction, in: view).isEnabled, direction)
        }
        // The stored Left / Right actions survive for the discrete mode.
        XCTAssertEqual(Options.shared.gesture.leftAction, SystemShortcut.moveSpaceLeft.identifier)
        XCTAssertEqual(Options.shared.gesture.rightAction, SystemShortcut.moveSpaceRight.identifier)

        // "Invert left and right" keeps working in follow mode.
        let invert = find(MouseGestureSettingsControls.Identifier.invertHorizontal, in: view) as! NSButton
        XCTAssertTrue(invert.isEnabled)
        invert.performClick(nil)
        XCTAssertTrue(Options.shared.gesture.invertHorizontal)

        mode.selectedSegment = 0
        mode.sendAction(mode.action, to: mode.target)

        XCTAssertEqual(Options.shared.gesture.mode, .discrete)
        XCTAssertTrue(actionPopUp("left", in: view).isEnabled)
        XCTAssertTrue(actionPopUp("right", in: view).isEnabled)
        XCTAssertEqual(popUpTitle("left", in: view), SystemShortcut.moveSpaceLeft.localizedName)
        XCTAssertEqual(popUpTitle("right", in: view), SystemShortcut.moveSpaceRight.localizedName)
    }

    func testControlsOpenInFollowModeWhenStored() {
        Options.shared.gesture.mode = .interactive
        let view = makeControlsView(isInteractiveAvailable: { true })

        XCTAssertEqual(modeControl(in: view).selectedSegment, 1)
        XCTAssertFalse(actionPopUp("left", in: view).isEnabled)
        XCTAssertFalse(actionPopUp("right", in: view).isEnabled)
        XCTAssertTrue(actionPopUp("click", in: view).isEnabled)
    }

    func testControlsDisableFollowWithAHintWhenUnavailable() {
        Options.shared.gesture.mode = .interactive
        let view = makeControlsView(isInteractiveAvailable: { false })
        let mode = modeControl(in: view)

        XCTAssertEqual(mode.selectedSegment, 0, "Mos runs discrete, so discrete is shown")
        XCTAssertFalse(mode.isEnabled(forSegment: 1))
        XCTAssertTrue(mode.isEnabled(forSegment: 0))
        let hint = NSLocalizedString("gesture-mode-interactive-unavailable", comment: "")
        XCTAssertNotEqual(hint, "gesture-mode-interactive-unavailable")
        XCTAssertEqual(note(in: view).stringValue, hint)
        XCTAssertTrue(actionPopUp("left", in: view).isEnabled)
        XCTAssertTrue(actionPopUp("right", in: view).isEnabled)
        XCTAssertEqual(Options.shared.gesture.mode, .interactive, "the stored choice is kept for when it works again")

        // Even a forced selection cannot switch the mode on.
        Options.shared.gesture.mode = .discrete
        mode.selectedSegment = 1
        mode.sendAction(mode.action, to: mode.target)
        XCTAssertEqual(Options.shared.gesture.mode, .discrete)
        XCTAssertEqual(mode.selectedSegment, 0)
    }

    func testControlsUseTheSynthesizerAvailabilityByDefault() {
        isSynthesizerAvailable = false
        var view = makeControlsView()
        XCTAssertFalse(modeControl(in: view).isEnabled(forSegment: 1))

        isSynthesizerAvailable = true
        view = makeControlsView()
        XCTAssertTrue(modeControl(in: view).isEnabled(forSegment: 1))
    }

    // MARK: - Helpers

    private func assertSwipeCalls(_ expected: [SwipeCall], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(swipeCalls.count, expected.count, "\(swipeCalls)", file: file, line: line)
        for (actual, wanted) in zip(swipeCalls, expected) {
            switch (actual, wanted) {
            case (.update(let a), .update(let b)):
                XCTAssertEqual(a, b, accuracy: 1e-9, "\(swipeCalls)", file: file, line: line)
            case (.end(let a), .end(let b)):
                XCTAssertEqual(a, b, accuracy: 1e-6, "\(swipeCalls)", file: file, line: line)
            default:
                XCTAssertEqual(actual, wanted, "\(swipeCalls)", file: file, line: line)
            }
        }
    }

    /// Runs the flushes the processor scheduled, as the main queue would.
    private func runScheduledWork() {
        let work = scheduledWork
        scheduledWork = []
        work.forEach { $0.work() }
    }

    private func advanceFrame() {
        clock += screen.frameDuration
    }

    private func configureGestureBinding(mode: MouseGestureMode, code: UInt16 = 3) {
        let trigger = RecordedEvent(
            type: .mouse,
            code: code,
            modifiers: 0,
            displayComponents: ["🖱4"],
            deviceFilter: nil
        )
        Options.shared.buttons.binding = [
            ButtonBinding(
                triggerEvent: trigger,
                systemShortcutName: SystemShortcut.mouseGestureNavigation.identifier,
                isEnabled: true
            )
        ]
        Options.shared.gesture.mode = mode
        ButtonUtils.shared.invalidateCache()
    }

    private func gestureInputEvent(phase: InputPhase, code: UInt16 = 3) -> InputEvent {
        return InputEvent(type: .mouse, code: code, modifiers: [], phase: phase, source: .hidPP, device: nil)
    }

    private func resolvedShortcut(_ shortcut: SystemShortcut.Shortcut) -> (code: CGKeyCode, flags: UInt64) {
        return SystemShortcut.resolveSystemShortcut(shortcut.identifier)
            ?? (shortcut.code, UInt64(shortcut.modifiers.rawValue))
    }

    private func recordKeyboardShortcuts() -> () -> [(CGKeyCode, UInt64)] {
        var executed: [(CGKeyCode, UInt64)] = []
        ShortcutExecutor.shared.setTestingKeyboardShortcutObserver { code, flags, _ in
            executed.append((code, flags))
        }
        return { executed }
    }

    private func makeOtherMouseEvent(_ type: CGEventType, buttonNumber: Int64 = 3) -> CGEvent {
        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: CGPoint(x: 40, y: 40),
            mouseButton: .center
        )!
        event.setIntegerValueField(.mouseEventButtonNumber, value: buttonNumber)
        return event
    }

    private func makeMouseMoveEvent(deltaX: Double, deltaY: Double, location: CGPoint) -> CGEvent {
        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: location,
            mouseButton: .center
        )!
        event.setDoubleValueField(.mouseEventDeltaX, value: deltaX)
        event.setDoubleValueField(.mouseEventDeltaY, value: deltaY)
        return event
    }

    private func waitForMainQueue() {
        let queuedWorkFinished = expectation(description: "main queue work finished")
        DispatchQueue.main.async {
            queuedWorkFinished.fulfill()
        }
        wait(for: [queuedWorkFinished], timeout: 1)
    }

    /// The gesture controls with checkboxes, in a view of their own.
    private func makeControlsView(isInteractiveAvailable: (() -> Bool)? = nil) -> NSView {
        let controls = isInteractiveAvailable.map {
            MouseGestureSettingsControls(showLogiActions: false, toggleStyle: .checkboxes, isInteractiveAvailable: $0)
        } ?? MouseGestureSettingsControls(showLogiActions: false, toggleStyle: .checkboxes)
        retainedControls.append(controls)
        let view = NSView()
        for control in [controls.modeControl, controls.modeNote, controls.invertToggle, controls.freezeToggle] + controls.actionPopUps {
            view.addSubview(control)
        }
        return view
    }

    private func find(_ id: NSUserInterfaceItemIdentifier, in view: NSView) -> NSView? {
        if view.identifier == id { return view }
        for subview in view.subviews {
            if let match = find(id, in: subview) { return match }
        }
        return nil
    }

    private func modeControl(in view: NSView) -> NSSegmentedControl {
        find(MouseGestureSettingsControls.Identifier.mode, in: view) as! NSSegmentedControl
    }

    private func note(in view: NSView) -> NSTextField {
        find(MouseGestureSettingsControls.Identifier.modeNote, in: view) as! NSTextField
    }

    private func actionPopUp(_ direction: String, in view: NSView) -> NSPopUpButton {
        find(MouseGestureSettingsControls.Identifier.action(direction), in: view) as! NSPopUpButton
    }

    /// A pull-down shows its first menu item as the title.
    private func popUpTitle(_ direction: String, in view: NSView) -> String? {
        actionPopUp(direction, in: view).menu?.items.first?.title
    }
}
