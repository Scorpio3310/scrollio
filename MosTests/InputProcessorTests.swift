import XCTest
@testable import Mos_Debug

final class InputProcessorTests: XCTestCase {

    /// Calls the gesture pointer lock made; the real pointer is never touched in tests.
    private var pointerAssociations: [Bool] = []
    private var pointerWarps: [CGPoint] = []
    private let pointerAnchor = CGPoint(x: 100, y: 100)

    override func setUp() {
        super.setUp()
        Options.shared.buttons.binding = []
        Options.shared.gesture = .default
        pointerAssociations = []
        pointerWarps = []
        let anchor = pointerAnchor
        MouseGesturePointerLock.shared.setTestingDriver(MouseGesturePointerDriver(
            currentLocation: { anchor },
            setAssociated: { [weak self] in self?.pointerAssociations.append($0) },
            warp: { [weak self] in self?.pointerWarps.append($0) }
        ))
        ButtonUtils.shared.invalidateCache()
        MouseInteractionSessionController.shared.setTestingMotionTapHooks()
        MouseInteractionSessionController.shared.clearAllSessions()
        ShortcutExecutor.shared.setTestingMouseEventObserver()
        ShortcutExecutor.shared.setTestingKeyboardShortcutObserver()
        InputProcessor.shared.clearActiveBindings()
        ScrollCore.shared.dashScroll = false
        ScrollCore.shared.dashAmplification = 1.0
        ScrollCore.shared.toggleScroll = false
        ScrollCore.shared.blockSmooth = false
        ScrollCore.shared.dashKeyHeld = false
        ScrollCore.shared.toggleKeyHeld = false
        ScrollCore.shared.blockKeyHeld = false
        ShortcutExecutor.shared.scrollActionPort = ScrollCore.shared
        ShortcutExecutor.shared.modifierFlagsProvider = InputProcessor.shared
    }

    override func tearDown() {
        // Gesture actions post asynchronously; drain them while the test observers are still
        // installed, so a late action neither leaks into the next test nor posts a real key.
        waitForMainQueue()
        InputProcessor.shared.clearActiveBindings()
        ScrollCore.shared.dashScroll = false
        ScrollCore.shared.dashAmplification = 1.0
        ScrollCore.shared.toggleScroll = false
        ScrollCore.shared.blockSmooth = false
        ScrollCore.shared.dashKeyHeld = false
        ScrollCore.shared.toggleKeyHeld = false
        ScrollCore.shared.blockKeyHeld = false
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

    func testMouseGestureRecognizerRecognizesCardinalDirections() {
        let cases: [(CGFloat, CGFloat, MouseGestureDirection, String)] = [
            (-45, 0, .left, SystemShortcut.moveSpaceLeft.identifier),
            (45, 0, .right, SystemShortcut.moveSpaceRight.identifier),
            (0, -45, .up, SystemShortcut.missionControl.identifier),
            (0, 45, .down, SystemShortcut.appExpose.identifier),
        ]

        for (deltaX, deltaY, expectedDirection, expectedShortcut) in cases {
            var recognizer = MouseGestureRecognizer()
            let direction = recognizer.append(deltaX: deltaX, deltaY: deltaY)
            XCTAssertEqual(direction, expectedDirection)
            XCTAssertEqual(
                direction.map { MouseGestureSettings.default.actionIdentifier(for: $0) },
                expectedShortcut
            )
        }
    }

    // MARK: - Gesture settings

    func testGestureSettingsInvertHorizontalSwapsOnlyLeftAndRight() {
        var settings = MouseGestureSettings.default
        settings.invertHorizontal = true

        XCTAssertEqual(settings.actionIdentifier(for: .left), SystemShortcut.moveSpaceRight.identifier)
        XCTAssertEqual(settings.actionIdentifier(for: .right), SystemShortcut.moveSpaceLeft.identifier)
        XCTAssertEqual(settings.actionIdentifier(for: .up), SystemShortcut.missionControl.identifier)
        XCTAssertEqual(settings.actionIdentifier(for: .down), SystemShortcut.appExpose.identifier)
    }

    func testGestureSettingsDecodeFillsMissingFieldsWithDefaults() throws {
        let data = Data(#"{"upAction":"copy","invertHorizontal":true}"#.utf8)
        let settings = try JSONDecoder().decode(MouseGestureSettings.self, from: data)

        var expected = MouseGestureSettings.default
        expected.upAction = "copy"
        expected.invertHorizontal = true
        XCTAssertEqual(settings, expected)
    }

    func testGestureSettingsRoundTripThroughJSON() throws {
        var settings = MouseGestureSettings.default
        settings.leftAction = ""
        settings.clickAction = SystemShortcut.navigateBack.identifier
        settings.freezePointer = false
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(MouseGestureSettings.self, from: data), settings)
    }

    func testGestureNavigationRunsConfiguredDirectionAction() {
        configureGestureBinding()
        Options.shared.gesture.upAction = SystemShortcut.copy.identifier
        let executed = recordKeyboardShortcuts()

        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down)), .consumed)
        InputProcessor.shared.handleMouseGestureMovement(deltaX: 0, deltaY: -45)
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .up)), .consumed)
        waitForMainQueue()

        let expected = resolvedShortcut(SystemShortcut.copy)
        XCTAssertEqual(executed().count, 1)
        XCTAssertEqual(executed().first?.0, expected.code)
        XCTAssertEqual(executed().first?.1, expected.flags)
    }

    func testGestureNavigationInvertedHorizontalRunsOppositeSpaceAction() {
        configureGestureBinding()
        Options.shared.gesture.invertHorizontal = true
        let executed = recordKeyboardShortcuts()

        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down)), .consumed)
        InputProcessor.shared.handleMouseGestureMovement(deltaX: -45, deltaY: 0)
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .up)), .consumed)
        waitForMainQueue()

        let expected = resolvedShortcut(SystemShortcut.moveSpaceRight)
        XCTAssertEqual(executed().count, 1)
        XCTAssertEqual(executed().first?.0, expected.code)
        XCTAssertEqual(executed().first?.1, expected.flags)
    }

    func testGestureNavigationEmptyDirectionActionDoesNothing() {
        configureGestureBinding()
        Options.shared.gesture.leftAction = ""
        let executed = recordKeyboardShortcuts()

        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down)), .consumed)
        InputProcessor.shared.handleMouseGestureMovement(deltaX: -45, deltaY: 0)
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .up)), .consumed)
        waitForMainQueue()

        XCTAssertTrue(executed().isEmpty)
    }

    func testGestureNavigationClickRunsConfiguredClickAction() {
        configureGestureBinding()
        Options.shared.gesture.clickAction = SystemShortcut.copy.identifier
        let executed = recordKeyboardShortcuts()

        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down)), .consumed)
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .up)), .consumed)
        waitForMainQueue()

        let expected = resolvedShortcut(SystemShortcut.copy)
        XCTAssertEqual(executed().count, 1)
        XCTAssertEqual(executed().first?.0, expected.code)
        XCTAssertEqual(executed().first?.1, expected.flags)
    }

    func testGestureNavigationStatefulActionPressesAndReleases() {
        configureGestureBinding()
        Options.shared.gesture.rightAction = SystemShortcut.mouseBackClick.identifier
        var postedTypes: [CGEventType] = []
        ShortcutExecutor.shared.setTestingMouseEventObserver { postedTypes.append($0.type) }

        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down)), .consumed)
        InputProcessor.shared.handleMouseGestureMovement(deltaX: 45, deltaY: 0)
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .up)), .consumed)
        waitForMainQueue()

        XCTAssertEqual(postedTypes, [.otherMouseDown, .otherMouseUp])
    }

    // MARK: - Gesture pointer freeze

    func testGestureNavigationFreezesPointerOnlyWhileHeld() {
        configureGestureBinding()

        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down)), .consumed)
        XCTAssertTrue(MouseGesturePointerLock.shared.isLocked)
        XCTAssertEqual(MouseGesturePointerLock.shared.anchor, pointerAnchor)
        XCTAssertEqual(pointerAssociations, [false])

        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .up)), .consumed)
        XCTAssertFalse(MouseGesturePointerLock.shared.isLocked)
        XCTAssertEqual(pointerAssociations, [false, true])
    }

    func testGestureNavigationDoesNotFreezePointerWhenDisabled() {
        configureGestureBinding()
        Options.shared.gesture.freezePointer = false

        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down)), .consumed)
        XCTAssertFalse(MouseGesturePointerLock.shared.isLocked)
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .up)), .consumed)
        XCTAssertTrue(pointerAssociations.isEmpty)
    }

    func testGestureNavigationCancellationReleasesPointer() {
        configureGestureBinding()

        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down)), .consumed)
        InputProcessor.shared.clearActiveBindings()

        XCTAssertFalse(MouseGesturePointerLock.shared.isLocked)
        XCTAssertEqual(pointerAssociations, [false, true])
    }

    func testGesturePointerLockKeepsMotionAtAnchorAndWarpsBackOnDrift() {
        configureGestureBinding()
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down)), .consumed)

        let atAnchor = makeMouseMoveEvent(deltaX: 3, deltaY: 0, location: pointerAnchor)
        MouseGesturePointerLock.shared.constrain(atAnchor)
        XCTAssertTrue(pointerWarps.isEmpty)

        let drifted = makeMouseMoveEvent(deltaX: 40, deltaY: 0, location: CGPoint(x: 140, y: 100))
        MouseGesturePointerLock.shared.constrain(drifted)
        XCTAssertEqual(drifted.location, pointerAnchor)
        XCTAssertEqual(pointerWarps, [pointerAnchor])
        XCTAssertEqual(drifted.getDoubleValueField(.mouseEventDeltaX), 40)

        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .up)), .consumed)
        let afterRelease = makeMouseMoveEvent(deltaX: 40, deltaY: 0, location: CGPoint(x: 180, y: 100))
        MouseGesturePointerLock.shared.constrain(afterRelease)
        XCTAssertEqual(afterRelease.location, CGPoint(x: 180, y: 100))
        XCTAssertEqual(pointerWarps.count, 1)
    }

    /// "Freeze pointer" in the discrete mode when the detach is not honoured (macOS 27): the
    /// event back on the anchor reports "hand + jump back". Without the compensation two
    /// 15 pt steps would count as 15 + 0 + 15 + 0 = 30 pt, below the gesture distance.
    func testDiscreteModeCountsThePhysicalMovementWhenThePointerIsWarpedBack() {
        configureGestureBinding()
        let executed = recordKeyboardShortcuts()
        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(fromCGEvent: makeOtherMouseEvent(.otherMouseDown))),
            .consumed
        )
        XCTAssertTrue(MouseGesturePointerLock.shared.isLocked)

        for _ in 0..<2 {
            let drifted = makeMouseMoveEvent(deltaX: -15, deltaY: 0, location: CGPoint(x: 85, y: 100))
            _ = MouseInteractionSessionController.shared.handleMotionTapEventForTests(drifted)
            let snappedBack = makeMouseMoveEvent(deltaX: 0, deltaY: 0, location: pointerAnchor)
            _ = MouseInteractionSessionController.shared.handleMotionTapEventForTests(snappedBack)
        }
        waitForMainQueue()

        let expected = resolvedShortcut(SystemShortcut.moveSpaceLeft)
        XCTAssertEqual(executed().count, 1, "60 pt of hand movement is a gesture")
        XCTAssertEqual(executed().first?.0, expected.code)
        XCTAssertEqual(pointerWarps.count, 2)
        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(fromCGEvent: makeOtherMouseEvent(.otherMouseUp))),
            .consumed
        )
    }

    /// Two overlapping holds: the second one starts the safety timeout over, so the pointer
    /// is not released at the first hold's timeout while the second is still held, and is
    /// still released at the second one's.
    func testPointerLockSafetyTimeoutStartsOverForEachLock() {
        let lock = MouseGesturePointerLock.shared
        lock.setTestingSafetyTimeout(0.4)
        lock.lock()
        XCTAssertTrue(lock.isLocked)

        let secondHold = expectation(description: "second hold begins")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            lock.lock()
            secondHold.fulfill()
        }
        wait(for: [secondHold], timeout: 5)

        let pastFirstTimeout = expectation(description: "the first timeout would have fired")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { pastFirstTimeout.fulfill() }
        wait(for: [pastFirstTimeout], timeout: 5)
        XCTAssertTrue(lock.isLocked, "0.5 s after the first lock, 0.25 s after the second")
        XCTAssertEqual(pointerAssociations, [false], "the second lock did not detach again")

        let released = expectation(for: NSPredicate { _, _ in !lock.isLocked }, evaluatedWith: nil)
        wait(for: [released], timeout: 5)
        XCTAssertEqual(pointerAssociations, [false, true])
    }

    func testMouseGestureRecognizerKeepsVerticalGesturesOneShot() {
        var up = MouseGestureRecognizer()
        XCTAssertEqual(up.append(deltaX: 0, deltaY: -45), .up)
        XCTAssertNil(up.append(deltaX: 0, deltaY: -100))

        var down = MouseGestureRecognizer()
        XCTAssertEqual(down.append(deltaX: 0, deltaY: 45), .down)
        XCTAssertNil(down.append(deltaX: 0, deltaY: 100))
    }

    func testMouseGestureRecognizerOnlyRecognizesOneDirectionPerHold() {
        var recognizer = MouseGestureRecognizer()

        XCTAssertEqual(recognizer.append(deltaX: 45, deltaY: 0), .right)
        XCTAssertNil(recognizer.append(deltaX: 200, deltaY: 0))
        XCTAssertNil(recognizer.append(deltaX: -400, deltaY: 0))
        XCTAssertNil(recognizer.append(deltaX: -200, deltaY: 0))
        XCTAssertNil(recognizer.append(deltaX: -40, deltaY: 0))
        XCTAssertEqual(recognizer.recognizedDirection, .right)
        XCTAssertFalse(recognizer.shouldReplayClick)
    }

    func testMouseGestureRecognizerThresholds() {
        var diagonal = MouseGestureRecognizer()
        XCTAssertNil(diagonal.append(deltaX: 35, deltaY: 35))
        XCTAssertEqual(diagonal.append(deltaX: 20, deltaY: 0), .right)

        var click = MouseGestureRecognizer()
        _ = click.append(deltaX: 4, deltaY: 3)
        XCTAssertTrue(click.shouldReplayClick)

        var ambiguous = MouseGestureRecognizer()
        _ = ambiguous.append(deltaX: 20, deltaY: 20)
        XCTAssertFalse(ambiguous.shouldReplayClick)

        var reversed = MouseGestureRecognizer()
        _ = reversed.append(deltaX: 20, deltaY: 0)
        _ = reversed.append(deltaX: -20, deltaY: 0)
        XCTAssertFalse(reversed.shouldReplayClick)
    }

    func testGestureNavigationTapRunsMissionControlForNativeMouseButton() {
        configureGestureBinding()
        var replayCount = 0
        var executedShortcuts: [(CGKeyCode, UInt64)] = []
        ShortcutExecutor.shared.setTestingMouseEventObserver { _ in replayCount += 1 }
        ShortcutExecutor.shared.setTestingKeyboardShortcutObserver { code, flags, _ in
            executedShortcuts.append((code, flags))
        }

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(fromCGEvent: makeOtherMouseEvent(.otherMouseDown))),
            .consumed
        )
        XCTAssertTrue(InputProcessor.shared.hasActiveMouseGestureSessions)
        XCTAssertTrue(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(fromCGEvent: makeOtherMouseEvent(.otherMouseUp))),
            .consumed
        )
        waitForMainQueue()

        let expected = resolvedShortcut(SystemShortcut.missionControl)
        XCTAssertEqual(executedShortcuts.count, 1)
        XCTAssertEqual(executedShortcuts.first?.0, expected.code)
        XCTAssertEqual(executedShortcuts.first?.1, expected.flags)
        XCTAssertEqual(replayCount, 0)
        XCTAssertFalse(InputProcessor.shared.hasActiveMouseGestureSessions)
        XCTAssertFalse(MouseInteractionSessionController.shared.isMotionTapRunning)
    }

    func testGestureNavigationTapRunsMissionControlForHighNumberedNativeMouseButton() {
        configureGestureBinding(code: 21)
        var replayCount = 0
        var executedShortcuts: [(CGKeyCode, UInt64)] = []
        ShortcutExecutor.shared.setTestingMouseEventObserver { _ in replayCount += 1 }
        ShortcutExecutor.shared.setTestingKeyboardShortcutObserver { code, flags, _ in
            executedShortcuts.append((code, flags))
        }

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(fromCGEvent: makeOtherMouseEvent(.otherMouseDown, buttonNumber: 21))),
            .consumed
        )
        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(fromCGEvent: makeOtherMouseEvent(.otherMouseUp, buttonNumber: 21))),
            .consumed
        )
        waitForMainQueue()

        let expected = resolvedShortcut(SystemShortcut.missionControl)
        XCTAssertEqual(executedShortcuts.count, 1)
        XCTAssertEqual(executedShortcuts.first?.0, expected.code)
        XCTAssertEqual(executedShortcuts.first?.1, expected.flags)
        XCTAssertEqual(replayCount, 0)
    }

    func testGestureNavigationRecognizedMovementSuppressesClickAndSurvivesDuplicateDown() {
        configureGestureBinding()
        var replayCount = 0
        var executedShortcuts: [(CGKeyCode, UInt64)] = []
        ShortcutExecutor.shared.setTestingMouseEventObserver { _ in replayCount += 1 }
        ShortcutExecutor.shared.setTestingKeyboardShortcutObserver { code, flags, _ in
            executedShortcuts.append((code, flags))
        }
        let down = gestureInputEvent(phase: .down)

        XCTAssertEqual(InputProcessor.shared.process(down), .consumed)
        InputProcessor.shared.handleMouseGestureMovement(deltaX: 35, deltaY: 0)
        XCTAssertEqual(InputProcessor.shared.process(down), .consumed)
        InputProcessor.shared.handleMouseGestureMovement(deltaX: 10, deltaY: 0)
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .up)), .consumed)
        waitForMainQueue()

        let expected = resolvedShortcut(SystemShortcut.moveSpaceRight)
        XCTAssertEqual(executedShortcuts.count, 1)
        XCTAssertEqual(executedShortcuts.first?.0, expected.code)
        XCTAssertEqual(executedShortcuts.first?.1, expected.flags)
        XCTAssertEqual(replayCount, 0)
        XCTAssertFalse(InputProcessor.shared.hasActiveMouseGestureSessions)
        XCTAssertFalse(MouseInteractionSessionController.shared.isMotionTapRunning)
    }

    func testGestureNavigationReceivesNativeMouseDeltaThroughMotionController() {
        configureGestureBinding()
        var executedShortcuts: [(CGKeyCode, UInt64)] = []

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(fromCGEvent: makeOtherMouseEvent(.otherMouseDown))),
            .consumed
        )

        let motion = makeMouseMoveEvent(deltaX: -45, deltaY: 0)
        var returnedFromMotionCallback = false
        ShortcutExecutor.shared.setTestingKeyboardShortcutObserver { code, flags, _ in
            XCTAssertTrue(returnedFromMotionCallback)
            executedShortcuts.append((code, flags))
        }
        MouseInteractionSessionController.shared.handleMotionTapEventForTests(motion)
        XCTAssertTrue(executedShortcuts.isEmpty)
        returnedFromMotionCallback = true

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(fromCGEvent: makeOtherMouseEvent(.otherMouseUp))),
            .consumed
        )
        waitForMainQueue()

        let expected = resolvedShortcut(SystemShortcut.moveSpaceLeft)
        XCTAssertEqual(executedShortcuts.count, 1)
        XCTAssertEqual(executedShortcuts.first?.0, expected.code)
        XCTAssertEqual(executedShortcuts.first?.1, expected.flags)
    }

    func testGestureNavigationContinuousHorizontalMovementOnlySwitchesOnce() {
        configureGestureBinding()
        var executedShortcuts: [(CGKeyCode, UInt64)] = []
        let firstAction = expectation(description: "initial horizontal gesture")
        let unexpectedRepeat = expectation(description: "continuous swipe must not repeat")
        unexpectedRepeat.isInverted = true
        ShortcutExecutor.shared.setTestingKeyboardShortcutObserver { code, flags, _ in
            executedShortcuts.append((code, flags))
            if executedShortcuts.count == 1 {
                firstAction.fulfill()
            } else {
                unexpectedRepeat.fulfill()
            }
        }

        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down)), .consumed)
        InputProcessor.shared.handleMouseGestureMovement(deltaX: 45, deltaY: 0)
        InputProcessor.shared.handleMouseGestureMovement(deltaX: 200, deltaY: 0)

        wait(for: [firstAction], timeout: 1)
        wait(for: [unexpectedRepeat], timeout: 0.25)
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .up)), .consumed)
        waitForMainQueue()

        let expected = resolvedShortcut(SystemShortcut.moveSpaceRight)
        XCTAssertEqual(executedShortcuts.count, 1)
        XCTAssertEqual(executedShortcuts[0].0, expected.code)
        XCTAssertEqual(executedShortcuts[0].1, expected.flags)
    }

    func testGestureNavigationDoesNotRepeatAfterPauseWithoutReleasingButton() {
        configureGestureBinding()
        var executedShortcuts: [(CGKeyCode, UInt64)] = []
        let firstAction = expectation(description: "initial horizontal gesture")
        let unexpectedRepeat = expectation(description: "same hold must not repeat after a pause")
        unexpectedRepeat.isInverted = true
        ShortcutExecutor.shared.setTestingKeyboardShortcutObserver { code, flags, _ in
            executedShortcuts.append((code, flags))
            if executedShortcuts.count == 1 {
                firstAction.fulfill()
            } else {
                unexpectedRepeat.fulfill()
            }
        }

        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down)), .consumed)
        InputProcessor.shared.handleMouseGestureMovement(deltaX: 45, deltaY: 0)
        InputProcessor.shared.handleMouseGestureMovement(deltaX: 40, deltaY: 0)

        wait(for: [firstAction], timeout: 1)
        wait(for: [unexpectedRepeat], timeout: 0.25)
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .up)), .consumed)
        waitForMainQueue()

        let expected = resolvedShortcut(SystemShortcut.moveSpaceRight)
        XCTAssertEqual(executedShortcuts.count, 1)
        XCTAssertEqual(executedShortcuts[0].0, expected.code)
        XCTAssertEqual(executedShortcuts[0].1, expected.flags)
    }

    func testGestureNavigationDoesNotReverseAfterGestureCommitsUntilRelease() {
        configureGestureBinding()
        var executedShortcuts: [(CGKeyCode, UInt64)] = []
        let firstAction = expectation(description: "initial horizontal gesture")
        let unexpectedReversal = expectation(description: "same hold must not reverse")
        unexpectedReversal.isInverted = true
        ShortcutExecutor.shared.setTestingKeyboardShortcutObserver { code, flags, _ in
            executedShortcuts.append((code, flags))
            if executedShortcuts.count == 1 {
                firstAction.fulfill()
            } else {
                unexpectedReversal.fulfill()
            }
        }

        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down)), .consumed)
        InputProcessor.shared.handleMouseGestureMovement(deltaX: 45, deltaY: 0)
        wait(for: [firstAction], timeout: 1)

        InputProcessor.shared.handleMouseGestureMovement(deltaX: -200, deltaY: 0)
        wait(for: [unexpectedReversal], timeout: 0.25)

        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .up)), .consumed)
        waitForMainQueue()

        let initial = resolvedShortcut(SystemShortcut.moveSpaceRight)
        XCTAssertEqual(executedShortcuts.count, 1)
        XCTAssertEqual(executedShortcuts[0].0, initial.code)
        XCTAssertEqual(executedShortcuts[0].1, initial.flags)
    }

    func testGestureNavigationLogiGestureButtonTapRunsMissionControl() {
        configureGestureBinding(code: 1000)
        var executedShortcuts: [(CGKeyCode, UInt64)] = []
        ShortcutExecutor.shared.setTestingKeyboardShortcutObserver { code, flags, _ in
            executedShortcuts.append((code, flags))
        }

        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down, code: 1000)), .consumed)
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .up, code: 1000)), .consumed)
        waitForMainQueue()

        let expected = resolvedShortcut(SystemShortcut.missionControl)
        XCTAssertEqual(executedShortcuts.count, 1)
        XCTAssertEqual(executedShortcuts.first?.0, expected.code)
        XCTAssertEqual(executedShortcuts.first?.1, expected.flags)
    }

    func testGestureNavigationDoesNotExecutePlaceholderAsKeyboardShortcut() {
        XCTAssertNil(
            ShortcutExecutor.shared.resolveAction(
                named: SystemShortcut.mouseGestureNavigation.identifier
            )
        )
        configureGestureBinding(type: .keyboard, code: 6)
        let down = InputEvent(
            type: .keyboard,
            code: 6,
            modifiers: [],
            phase: .down,
            source: .hidPP,
            device: nil
        )

        XCTAssertEqual(InputProcessor.shared.process(down), .passthrough)
        XCTAssertFalse(InputProcessor.shared.hasActiveMouseGestureSessions)
        XCTAssertFalse(MouseInteractionSessionController.shared.isMotionTapRunning)
    }

    func testGestureNavigationCancellationDoesNotReplayClick() {
        configureGestureBinding()
        var replayCount = 0
        var shortcutCount = 0
        ShortcutExecutor.shared.setTestingMouseEventObserver { _ in replayCount += 1 }
        ShortcutExecutor.shared.setTestingKeyboardShortcutObserver { _, _, _ in shortcutCount += 1 }

        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down)), .consumed)
        InputProcessor.shared.clearActiveBindings()
        waitForMainQueue()

        XCTAssertFalse(InputProcessor.shared.hasActiveMouseGestureSessions)
        XCTAssertEqual(replayCount, 0)
        XCTAssertEqual(shortcutCount, 0)
    }

    // MARK: - Gesture hold watchdog (a lost button-up)

    func testDiscreteHoldWatchdogReleasesTheMotionTapAndThePointer() {
        configureGestureBinding()
        let executed = recordKeyboardShortcuts()

        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down)), .consumed)
        XCTAssertTrue(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertTrue(MouseGesturePointerLock.shared.isLocked)

        // The button-up never arrives.
        InputProcessor.shared.fireMouseGestureWatchdogsForTests()

        XCTAssertFalse(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertFalse(InputProcessor.shared.hasPointerTrackedMouseGestureSessions)
        XCTAssertFalse(MouseGesturePointerLock.shared.isLocked)
        XCTAssertEqual(pointerAssociations, [false, true])

        // Movement no longer counts towards a gesture of the abandoned hold.
        InputProcessor.shared.handleMouseGestureMovement(deltaX: 45, deltaY: 0)
        waitForMainQueue()
        XCTAssertTrue(executed().isEmpty)
    }

    func testDiscreteHoldWatchdogLetsTheNextPressStartOver() {
        configureGestureBinding()
        let executed = recordKeyboardShortcuts()

        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down)), .consumed)
        InputProcessor.shared.handleMouseGestureMovement(deltaX: 20, deltaY: 0)
        InputProcessor.shared.fireMouseGestureWatchdogsForTests()

        // The next press is a fresh hold, not a swallowed "duplicate down": it starts from
        // zero travel (the 20 pt above are gone) and fires its action like any other.
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down)), .consumed)
        XCTAssertTrue(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertTrue(MouseGesturePointerLock.shared.isLocked)
        InputProcessor.shared.handleMouseGestureMovement(deltaX: -30, deltaY: 0)
        waitForMainQueue()
        XCTAssertTrue(executed().isEmpty, "30 pt is below the gesture distance")
        InputProcessor.shared.handleMouseGestureMovement(deltaX: -15, deltaY: 0)
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .up)), .consumed)
        waitForMainQueue()

        let expected = resolvedShortcut(SystemShortcut.moveSpaceLeft)
        XCTAssertEqual(executed().count, 1)
        XCTAssertEqual(executed().first?.0, expected.code)
        XCTAssertFalse(InputProcessor.shared.hasActiveMouseGestureSessions)
        XCTAssertFalse(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertFalse(MouseGesturePointerLock.shared.isLocked)
    }

    func testLateButtonUpAfterTheWatchdogIsSwallowedWithoutAClick() {
        configureGestureBinding()
        var replayCount = 0
        ShortcutExecutor.shared.setTestingMouseEventObserver { _ in replayCount += 1 }
        let executed = recordKeyboardShortcuts()

        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down)), .consumed)
        InputProcessor.shared.fireMouseGestureWatchdogsForTests()

        // A hold that was merely long: its button-up still belongs to Mos, and it must not
        // run the click action (Mission Control) ten seconds after the press.
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .up)), .consumed)
        waitForMainQueue()

        XCTAssertTrue(executed().isEmpty)
        XCTAssertEqual(replayCount, 0)
        XCTAssertFalse(InputProcessor.shared.hasActiveMouseGestureSessions)
        XCTAssertFalse(MouseInteractionSessionController.shared.isMotionTapRunning)
    }

    func testWatchdogAbandonsOnlyItsOwnHoldWhenTwoGestureButtonsAreHeld() {
        configureGestureBinding()
        let second = RecordedEvent(type: .mouse, code: 4, modifiers: 0, displayComponents: ["🖱5"], deviceFilter: nil)
        Options.shared.buttons.binding.append(ButtonBinding(
            triggerEvent: second,
            systemShortcutName: SystemShortcut.mouseGestureNavigation.identifier,
            isEnabled: true
        ))
        ButtonUtils.shared.invalidateCache()
        let executed = recordKeyboardShortcuts()

        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down, code: 3)), .consumed)
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down, code: 4)), .consumed)
        InputProcessor.shared.fireMouseGestureWatchdogsForTests(code: 3)

        // Button 4 is still held: the tap and the pointer lock stay for it.
        XCTAssertTrue(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertTrue(MouseGesturePointerLock.shared.isLocked)
        InputProcessor.shared.handleMouseGestureMovement(deltaX: 45, deltaY: 0)
        waitForMainQueue()
        XCTAssertEqual(executed().count, 1, "only the live hold recognizes the movement")

        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .up, code: 4)), .consumed)
        XCTAssertFalse(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertFalse(MouseGesturePointerLock.shared.isLocked)
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .up, code: 3)), .consumed)
        waitForMainQueue()
        XCTAssertEqual(executed().count, 1)
        XCTAssertFalse(InputProcessor.shared.hasActiveMouseGestureSessions)
    }

    func testWatchdogAbandonsAHoldTheMouseTracksItself() {
        configureGestureBinding(code: 1000)
        let executed = recordKeyboardShortcuts()
        let down = InputEvent(
            type: .mouse, code: 1000, modifiers: [], phase: .down, source: .hidPP, device: nil,
            tracksMovementOnDevice: true
        )
        let threshold = Int((MouseGestureRecognizer.defaultActivationDistance / MouseGestureDeviceTracking.pointsPerCount).rounded(.up)) + 1

        XCTAssertEqual(InputProcessor.shared.process(down), .consumed)
        InputProcessor.shared.fireMouseGestureWatchdogsForTests()
        InputProcessor.shared.handleDeviceGestureMovement(code: 1000, countsX: threshold, countsY: 0)
        waitForMainQueue()
        XCTAssertTrue(executed().isEmpty, "raw XY of an abandoned hold is ignored")

        // The next press is tracked again.
        XCTAssertEqual(InputProcessor.shared.process(down), .consumed)
        InputProcessor.shared.handleDeviceGestureMovement(code: 1000, countsX: threshold, countsY: 0)
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .up, code: 1000)), .consumed)
        waitForMainQueue()
        XCTAssertEqual(executed().count, 1)
    }

    /// Button 3 alone is Gesture Navigation; with ⌘ it holds Shift (a virtual modifier).
    private func configureGestureAndCommandShiftBindings() {
        configureGestureBinding()
        let withCommand = RecordedEvent(
            type: .mouse, code: 3, modifiers: UInt(CGEventFlags.maskCommand.rawValue),
            displayComponents: ["⌘", "🖱4"], deviceFilter: nil
        )
        Options.shared.buttons.binding.append(ButtonBinding(
            triggerEvent: withCommand, systemShortcutName: "custom::56:0", isEnabled: true
        ))
        ButtonUtils.shared.invalidateCache()
    }

    private func commandEvent(phase: InputPhase) -> InputEvent {
        return InputEvent(type: .mouse, code: 3, modifiers: .maskCommand, phase: phase, source: .hidPP, device: nil)
    }

    func testAPressAfterAnAbandonedHoldKeepsItsOwnButtonUp() {
        configureGestureAndCommandShiftBindings()

        // A gesture hold whose button-up was lost.
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down)), .consumed)
        InputProcessor.shared.fireMouseGestureWatchdogsForTests()

        // The next press of the same button, with ⌘, holds Shift.
        XCTAssertEqual(InputProcessor.shared.process(commandEvent(phase: .down)), .consumed)
        XCTAssertNotEqual(InputProcessor.shared.activeModifierFlags, 0)

        // Its up releases Shift instead of being swallowed by the stale hold.
        XCTAssertEqual(InputProcessor.shared.process(commandEvent(phase: .up)), .consumed)
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, 0)
        XCTAssertFalse(InputProcessor.shared.hasActiveMouseGestureSessions)
    }

    func testAnUpPrefersTheBindingPressedWhileTheAbandonedHoldWasStillLive() {
        configureGestureAndCommandShiftBindings()

        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down)), .consumed)
        XCTAssertEqual(InputProcessor.shared.process(commandEvent(phase: .down)), .consumed)
        XCTAssertNotEqual(InputProcessor.shared.activeModifierFlags, 0)
        InputProcessor.shared.fireMouseGestureWatchdogsForTests()

        XCTAssertEqual(InputProcessor.shared.process(commandEvent(phase: .up)), .consumed)
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, 0)
        XCTAssertFalse(InputProcessor.shared.hasActiveMouseGestureSessions)
    }

    func testAnUnboundPressAfterAnAbandonedHoldPassesItsUpThrough() {
        configureGestureBinding()
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down)), .consumed)
        InputProcessor.shared.fireMouseGestureWatchdogsForTests()

        // The binding is gone by the next press: down and up both belong to the app.
        Options.shared.buttons.binding = []
        ButtonUtils.shared.invalidateCache()
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down)), .passthrough)
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .up)), .passthrough)
        XCTAssertFalse(InputProcessor.shared.hasActiveMouseGestureSessions)
    }

    /// The real timer, with a short timeout: pressing the button arms the watchdog.
    func testDiscreteHoldWatchdogFiresByItselfAfterTheTimeout() {
        configureGestureBinding()
        InputProcessor.shared.setTestingMouseGestureHoldTimeout(0.05)
        defer { InputProcessor.shared.setTestingMouseGestureHoldTimeout(nil) }

        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down)), .consumed)
        XCTAssertTrue(MouseInteractionSessionController.shared.isMotionTapRunning)

        let abandoned = expectation(for: NSPredicate { _, _ in
            !MouseInteractionSessionController.shared.isMotionTapRunning
        }, evaluatedWith: nil)
        wait(for: [abandoned], timeout: 5)
        XCTAssertFalse(InputProcessor.shared.hasPointerTrackedMouseGestureSessions)
        XCTAssertFalse(MouseGesturePointerLock.shared.isLocked)
    }

    /// A released hold takes its watchdog with it: the timer of an earlier press must not
    /// abandon a later one.
    func testWatchdogOfAReleasedHoldDoesNotTouchTheNextPress() {
        configureGestureBinding()
        InputProcessor.shared.setTestingMouseGestureHoldTimeout(0.05)
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down)), .consumed)
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .up)), .consumed)
        InputProcessor.shared.setTestingMouseGestureHoldTimeout(nil)

        // Second press with the real (10 s) timeout, held past the first press's timer.
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down)), .consumed)
        let firstTimerWindowPassed = expectation(description: "the first timer would have fired")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { firstTimerWindowPassed.fulfill() }
        wait(for: [firstTimerWindowPassed], timeout: 5)

        XCTAssertTrue(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertTrue(InputProcessor.shared.hasPointerTrackedMouseGestureSessions)
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .up)), .consumed)
    }

    func testProcess_downEvent_consumedWhenBindingMatches() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "custom::56:0", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let event = InputEvent(type: .mouse, code: 3, modifiers: CGEventFlags(rawValue: 0),
                               phase: .down, source: .hidPP, device: nil)
        let result = InputProcessor.shared.process(event)
        XCTAssertEqual(result, .consumed)
    }

    func testProcess_upEvent_consumedViaActiveBindings() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "custom::56:0", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: CGEventFlags(rawValue: 0),
                                   phase: .down, source: .hidPP, device: nil)
        _ = InputProcessor.shared.process(downEvent)

        let upEvent = InputEvent(type: .mouse, code: 3, modifiers: CGEventFlags(rawValue: 0),
                                 phase: .up, source: .hidPP, device: nil)
        let result = InputProcessor.shared.process(upEvent)
        XCTAssertEqual(result, .consumed)
    }

    func testProcess_logiStandardButtonEventDoesNotMatchNativeMouseBinding() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "custom::56:0", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let event = InputEvent(
            type: .mouse,
            code: 1006,
            modifiers: CGEventFlags(rawValue: 0),
            phase: .down,
            source: .hidPP,
            device: nil
        )

        XCTAssertEqual(InputProcessor.shared.process(event), .passthrough)
    }

    func testProcess_nativeMouseButtonMatchesNativeMouseBinding() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        var observedTypes: [CGEventType] = []
        ShortcutExecutor.shared.setTestingMouseEventObserver { event in
            observedTypes.append(event.type)
        }

        let downEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .otherMouseDown,
            mouseCursorPosition: CGPoint(x: 40, y: 40),
            mouseButton: .center
        )!
        downEvent.setIntegerValueField(.mouseEventButtonNumber, value: 3)

        let upEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .otherMouseUp,
            mouseCursorPosition: CGPoint(x: 40, y: 40),
            mouseButton: .center
        )!
        upEvent.setIntegerValueField(.mouseEventButtonNumber, value: 3)

        XCTAssertEqual(InputProcessor.shared.process(InputEvent(fromCGEvent: downEvent)), .consumed)
        XCTAssertEqual(InputProcessor.shared.process(InputEvent(fromCGEvent: upEvent)), .consumed)
        XCTAssertEqual(observedTypes, [.leftMouseDown, .leftMouseUp])
    }

    func testProcess_upEvent_passthroughWithoutPriorDown() {
        let event = InputEvent(type: .mouse, code: 99, modifiers: CGEventFlags(rawValue: 0),
                               phase: .up, source: .hidPP, device: nil)
        let result = InputProcessor.shared.process(event)
        XCTAssertEqual(result, .passthrough)
    }

    func testProcess_upEvent_matchesDespiteModifierChange() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: UInt(CGEventFlags.maskCommand.rawValue),
                                    displayComponents: ["⌘", "🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "custom::56:0", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .maskCommand,
                                   phase: .down, source: .hidPP, device: nil)
        _ = InputProcessor.shared.process(downEvent)

        // Up with ⌘ already released (modifiers = 0)
        let upEvent = InputEvent(type: .mouse, code: 3, modifiers: CGEventFlags(rawValue: 0),
                                 phase: .up, source: .hidPP, device: nil)
        let result = InputProcessor.shared.process(upEvent)
        XCTAssertEqual(result, .consumed)
    }

    func testSystemShortcutExecutionModes_mouseActionsStateful_nonMouseTrigger() {
        XCTAssertEqual(SystemShortcut.mouseLeftClick.executionMode, .stateful)
        XCTAssertEqual(SystemShortcut.logiSmartShiftToggle.executionMode, .trigger)
    }

    func testProcess_upEvent_passthroughForTriggerShortcut() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "logiSmartShiftToggle", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)

        let upEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                 phase: .up, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(upEvent), .passthrough)
    }

    func testProcess_upEvent_consumedForStatefulMouseShortcut() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)

        let upEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                 phase: .up, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(upEvent), .consumed)
    }

    func testProcess_statefulMouseShortcut_doesNotSetVirtualModifierFlags() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, 0)
    }

    func testProcess_statefulMouseShortcut_startsAndStopsMouseInteractionSession() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)
        XCTAssertTrue(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertEqual(MouseInteractionSessionController.shared.activeSessionCount, 1)

        let upEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                 phase: .up, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(upEvent), .consumed)
        XCTAssertFalse(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertEqual(MouseInteractionSessionController.shared.activeSessionCount, 0)
    }

    func testProcess_virtualModifierShortcut_startsAndStopsMotionTapForMouseInteractionPropagation() {
        let trigger = RecordedEvent(type: .mouse, code: 6, modifiers: 0, displayComponents: ["🖱7"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "custom::58:0", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = InputEvent(type: .mouse, code: 6, modifiers: .init(rawValue: 0),
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)
        XCTAssertTrue(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, CGEventFlags.maskAlternate.rawValue)

        let upEvent = InputEvent(type: .mouse, code: 6, modifiers: .init(rawValue: 0),
                                 phase: .up, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(upEvent), .consumed)
        XCTAssertFalse(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, 0)
    }

    func testProcess_predefinedModifierShortcut_usesStatefulModifierFlow() {
        let trigger = RecordedEvent(type: .mouse, code: 6, modifiers: 0, displayComponents: ["🖱7"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "modifierOption", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = InputEvent(type: .mouse, code: 6, modifiers: .init(rawValue: 0),
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)
        XCTAssertTrue(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, CGEventFlags.maskAlternate.rawValue)

        let upEvent = InputEvent(type: .mouse, code: 6, modifiers: .init(rawValue: 0),
                                 phase: .up, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(upEvent), .consumed)
        XCTAssertFalse(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, 0)
    }

    func testResolveAction_predefinedModifierShortcut_mapsToCustomModifierKey() {
        guard let action = ShortcutExecutor.shared.resolveAction(named: "modifierShift") else {
            return XCTFail("Expected predefined modifier shortcut to resolve")
        }

        switch action {
        case .customKey(let code, let modifiers):
            XCTAssertEqual(code, KeyCode.shiftL)
            XCTAssertEqual(modifiers, 0)
        default:
            XCTFail("Expected predefined modifier shortcut to reuse custom modifier execution")
        }
    }

    func testResolveAction_escapeShortcut_mapsToSystemShortcut() {
        guard let action = ShortcutExecutor.shared.resolveAction(named: "escapeKey") else {
            return XCTFail("Expected escape shortcut to resolve")
        }

        switch action {
        case .systemShortcut(let identifier):
            XCTAssertEqual(identifier, "escapeKey")
        default:
            XCTFail("Expected escape shortcut to use the system shortcut execution path")
        }
    }

    func testResolveAction_mosScrollActionsAreStateful() {
        for identifier in ["mosScrollDash", "mosScrollToggle", "mosScrollBlock"] {
            guard let action = ShortcutExecutor.shared.resolveAction(named: identifier) else {
                return XCTFail("Expected \(identifier) action to resolve")
            }

            XCTAssertEqual(action.executionMode, .stateful)
        }
    }

    func testProcess_mosScrollDash_downAndUpControlsDashState() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mosScrollDash", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)
        XCTAssertTrue(ScrollCore.shared.dashScroll)
        XCTAssertEqual(ScrollCore.shared.dashAmplification, 5.0)

        let upEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                 phase: .up, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(upEvent), .consumed)
        XCTAssertFalse(ScrollCore.shared.dashScroll)
        XCTAssertEqual(ScrollCore.shared.dashAmplification, 1.0)
    }

    func testProcess_mosScrollMiddleTapWithoutScroll_replaysOriginalMouseClick() {
        let trigger = RecordedEvent(type: .mouse, code: 2, modifiers: 0, displayComponents: ["🖱M"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mosScrollDash", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        var observedEvents: [(type: CGEventType, buttonNumber: Int64, userData: Int64)] = []
        ShortcutExecutor.shared.setTestingMouseEventObserver { event in
            observedEvents.append((
                event.type,
                event.getIntegerValueField(.mouseEventButtonNumber),
                event.getIntegerValueField(.eventSourceUserData)
            ))
        }

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 2, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertTrue(ScrollCore.shared.dashScroll)

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 2, modifiers: .init(rawValue: 0), phase: .up, source: .hidPP, device: nil)),
            .consumed
        )

        XCTAssertEqual(observedEvents.map(\.type), [.otherMouseDown, .otherMouseUp])
        XCTAssertEqual(observedEvents.map(\.buttonNumber), [2, 2])
        XCTAssertEqual(observedEvents.map(\.userData), [MosEventMarker.syntheticCustom, MosEventMarker.syntheticCustom])
        XCTAssertFalse(ScrollCore.shared.dashScroll)
    }

    func testProcess_mosScrollMiddleTapWithScrollUse_doesNotReplayOriginalMouseClick() {
        let trigger = RecordedEvent(type: .mouse, code: 2, modifiers: 0, displayComponents: ["🖱M"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mosScrollDash", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        var observedEvents: [CGEventType] = []
        ShortcutExecutor.shared.setTestingMouseEventObserver { event in
            observedEvents.append(event.type)
        }

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 2, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
            .consumed
        )
        InputProcessor.shared.markMosScrollActionSessionsUsedForScroll()

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 2, modifiers: .init(rawValue: 0), phase: .up, source: .hidPP, device: nil)),
            .consumed
        )

        XCTAssertTrue(observedEvents.isEmpty)
        XCTAssertFalse(ScrollCore.shared.dashScroll)
    }

    func testScrollCore_scrollWheelWhileMosScrollHeldSuppressesTapReplay() {
        let trigger = RecordedEvent(type: .mouse, code: 2, modifiers: 0, displayComponents: ["🖱M"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mosScrollDash", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        var observedEvents: [CGEventType] = []
        ShortcutExecutor.shared.setTestingMouseEventObserver { event in
            observedEvents.append(event.type)
        }

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 2, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
            .consumed
        )

        guard let scrollEvent = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0) else {
            return XCTFail("Expected scroll wheel event to be creatable")
        }
        ScrollEvent.isTrackpadCallCount = ScrollEvent.isTrackpadCallSamplingRate - 1
        _ = ScrollCore.shared.scrollEventCallBack(CGEventTapProxy(bitPattern: 1)!, .scrollWheel, scrollEvent, nil)

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 2, modifiers: .init(rawValue: 0), phase: .up, source: .hidPP, device: nil)),
            .consumed
        )

        XCTAssertTrue(observedEvents.isEmpty)
        XCTAssertFalse(ScrollCore.shared.dashScroll)
    }

    func testScrollCore_scrollWheelReleasesCGMosScrollSessionWhenPhysicalButtonIsNoLongerDown() {
        let trigger = RecordedEvent(type: .mouse, code: 2, modifiers: 0, displayComponents: ["🖱M"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mosScrollDash", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .otherMouseDown,
            mouseCursorPosition: CGPoint(x: 40, y: 40),
            mouseButton: .center
        )!
        downEvent.setIntegerValueField(.mouseEventButtonNumber, value: 2)

        XCTAssertEqual(InputProcessor.shared.process(InputEvent(fromCGEvent: downEvent)), .consumed)
        XCTAssertTrue(ScrollCore.shared.dashScroll)

        guard let scrollEvent = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0) else {
            return XCTFail("Expected scroll wheel event to be creatable")
        }
        ScrollEvent.isTrackpadCallCount = ScrollEvent.isTrackpadCallSamplingRate - 1
        _ = ScrollCore.shared.scrollEventCallBack(CGEventTapProxy(bitPattern: 1)!, .scrollWheel, scrollEvent, nil)

        XCTAssertFalse(ScrollCore.shared.dashScroll)
        XCTAssertEqual(ScrollCore.shared.dashAmplification, 1.0)
    }

    func testProcess_mosScrollCGMouseTapWithPointerMove_doesNotReplayOriginalMouseClick() {
        let trigger = RecordedEvent(type: .mouse, code: 2, modifiers: 0, displayComponents: ["🖱M"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mosScrollDash", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        var observedEvents: [CGEventType] = []
        ShortcutExecutor.shared.setTestingMouseEventObserver { event in
            observedEvents.append(event.type)
        }

        let downEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .otherMouseDown,
            mouseCursorPosition: CGPoint(x: 40, y: 40),
            mouseButton: .center
        )!
        downEvent.setIntegerValueField(.mouseEventButtonNumber, value: 2)

        let upEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .otherMouseUp,
            mouseCursorPosition: CGPoint(x: 70, y: 40),
            mouseButton: .center
        )!
        upEvent.setIntegerValueField(.mouseEventButtonNumber, value: 2)

        XCTAssertEqual(InputProcessor.shared.process(InputEvent(fromCGEvent: downEvent)), .consumed)
        XCTAssertEqual(InputProcessor.shared.process(InputEvent(fromCGEvent: upEvent)), .consumed)

        XCTAssertTrue(observedEvents.isEmpty)
        XCTAssertFalse(ScrollCore.shared.dashScroll)
    }

    func testProcess_logiButtonCanTriggerMosScrollToggle() {
        let trigger = RecordedEvent(
            type: .mouse,
            code: 1007,
            modifiers: 0,
            displayComponents: ["[Logi]", "Forward"],
            deviceFilter: nil
        )
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mosScrollToggle", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 1007, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertTrue(ScrollCore.shared.toggleScroll)

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 1007, modifiers: .init(rawValue: 0), phase: .up, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertFalse(ScrollCore.shared.toggleScroll)
    }

    func testProcess_logiMosScrollForwardTapWithoutScroll_replaysForwardButton() {
        let trigger = RecordedEvent(
            type: .mouse,
            code: 1007,
            modifiers: 0,
            displayComponents: ["[Logi]", "Forward"],
            deviceFilter: nil
        )
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mosScrollToggle", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        var observedEvents: [(type: CGEventType, buttonNumber: Int64)] = []
        ShortcutExecutor.shared.setTestingMouseEventObserver { event in
            observedEvents.append((event.type, event.getIntegerValueField(.mouseEventButtonNumber)))
        }

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 1007, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 1007, modifiers: .init(rawValue: 0), phase: .up, source: .hidPP, device: nil)),
            .consumed
        )

        XCTAssertEqual(observedEvents.map(\.type), [.otherMouseDown, .otherMouseUp])
        XCTAssertEqual(observedEvents.map(\.buttonNumber), [4, 4])
        XCTAssertFalse(ScrollCore.shared.toggleScroll)
    }

    // MARK: - Synthetic releases (the mouse went away mid-hold)

    private func syntheticRelease(code: UInt16 = 3) -> InputEvent {
        return InputEvent(
            type: .mouse, code: code, modifiers: [], phase: .up, source: .hidPP, device: nil,
            isSyntheticRelease: true
        )
    }

    func testSyntheticReleaseFlagOnlyExistsOnAnUp() {
        let down = InputEvent(
            type: .mouse, code: 3, modifiers: [], phase: .down, source: .hidPP, device: nil,
            isSyntheticRelease: true
        )
        XCTAssertFalse(down.isSyntheticRelease)
        XCTAssertTrue(syntheticRelease().isSyntheticRelease)
        XCTAssertFalse(gestureInputEvent(phase: .up).isSyntheticRelease)
        XCTAssertFalse(InputEvent(fromCGEvent: makeOtherMouseEvent(.otherMouseUp)).isSyntheticRelease)
    }

    func testSyntheticReleaseOfAGestureHoldRunsNoClickAndReleasesEverything() {
        configureGestureBinding()
        var replayCount = 0
        ShortcutExecutor.shared.setTestingMouseEventObserver { _ in replayCount += 1 }
        let executed = recordKeyboardShortcuts()

        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down)), .consumed)
        InputProcessor.shared.handleMouseGestureMovement(deltaX: 3, deltaY: 0)
        XCTAssertTrue(MouseGesturePointerLock.shared.isLocked)

        // A hold that barely moved would run the click action (Mission Control) on a real up.
        XCTAssertEqual(InputProcessor.shared.process(syntheticRelease()), .consumed)
        waitForMainQueue()

        XCTAssertTrue(executed().isEmpty, "no click action for an interrupted hold")
        XCTAssertEqual(replayCount, 0)
        XCTAssertFalse(InputProcessor.shared.hasActiveMouseGestureSessions)
        XCTAssertFalse(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertFalse(MouseGesturePointerLock.shared.isLocked)
        XCTAssertEqual(pointerAssociations, [false, true])

        // The next real press and release work as usual.
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down)), .consumed)
        InputProcessor.shared.handleMouseGestureMovement(deltaX: -45, deltaY: 0)
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .up)), .consumed)
        waitForMainQueue()
        XCTAssertEqual(executed().count, 1)
    }

    func testSyntheticReleaseOfAMosScrollHoldDoesNotReplayTheClick() {
        let trigger = RecordedEvent(type: .mouse, code: 1007, modifiers: 0, displayComponents: ["[Logi]", "Forward"], deviceFilter: nil)
        Options.shared.buttons.binding = [ButtonBinding(triggerEvent: trigger, systemShortcutName: "mosScrollToggle", isEnabled: true)]
        ButtonUtils.shared.invalidateCache()
        var observed: [CGEventType] = []
        ShortcutExecutor.shared.setTestingMouseEventObserver { observed.append($0.type) }

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 1007, modifiers: [], phase: .down, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertTrue(ScrollCore.shared.toggleScroll)
        XCTAssertEqual(InputProcessor.shared.process(syntheticRelease(code: 1007)), .consumed)

        XCTAssertEqual(observed, [], "an interrupted hold is not a tap")
        XCTAssertFalse(ScrollCore.shared.toggleScroll, "the hold itself is still unwound")
    }

    func testSyntheticReleaseStillReleasesAVirtualModifier() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        Options.shared.buttons.binding = [ButtonBinding(triggerEvent: trigger, systemShortcutName: "custom::56:0", isEnabled: true)]
        ButtonUtils.shared.invalidateCache()

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 3, modifiers: [], phase: .down, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertNotEqual(InputProcessor.shared.activeModifierFlags, 0)
        XCTAssertEqual(InputProcessor.shared.process(syntheticRelease()), .consumed)
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, 0)
    }

    func testProcess_mosScrollBlock_downAndUpControlsBlockState() {
        let trigger = RecordedEvent(type: .mouse, code: 5, modifiers: 0, displayComponents: ["🖱6"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mosScrollBlock", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 5, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertTrue(ScrollCore.shared.blockSmooth)

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 5, modifiers: .init(rawValue: 0), phase: .up, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertFalse(ScrollCore.shared.blockSmooth)
    }

    func testProcess_multipleMosScrollDashTriggers_releaseOneKeepsDashActive() {
        let firstTrigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let secondTrigger = RecordedEvent(type: .mouse, code: 4, modifiers: 0, displayComponents: ["🖱5"], deviceFilter: nil)
        let firstBinding = ButtonBinding(triggerEvent: firstTrigger, systemShortcutName: "mosScrollDash", isEnabled: true)
        let secondBinding = ButtonBinding(triggerEvent: secondTrigger, systemShortcutName: "mosScrollDash", isEnabled: true)
        Options.shared.buttons.binding = [firstBinding, secondBinding]
        ButtonUtils.shared.invalidateCache()

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertTrue(ScrollCore.shared.dashScroll)

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 4, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertTrue(ScrollCore.shared.dashScroll)

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0), phase: .up, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertTrue(ScrollCore.shared.dashScroll)

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 4, modifiers: .init(rawValue: 0), phase: .up, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertFalse(ScrollCore.shared.dashScroll)
    }

    func testProcess_mosScrollBindingDoesNotLatchWhenLegacyScrollHotkeySeesOnlyDown() {
        struct Case {
            let shortcutName: String
            let configureLegacyHotkey: (ScrollHotkey) -> Void
            let isRoleActive: () -> Bool
        }

        let originalDash = Options.shared.scroll.dash
        let originalToggle = Options.shared.scroll.toggle
        let originalBlock = Options.shared.scroll.block
        defer {
            Options.shared.scroll.dash = originalDash
            Options.shared.scroll.toggle = originalToggle
            Options.shared.scroll.block = originalBlock
        }

        let cases: [Case] = [
            Case(
                shortcutName: "mosScrollDash",
                configureLegacyHotkey: { Options.shared.scroll.dash = $0 },
                isRoleActive: { ScrollCore.shared.dashScroll }
            ),
            Case(
                shortcutName: "mosScrollToggle",
                configureLegacyHotkey: { Options.shared.scroll.toggle = $0 },
                isRoleActive: { ScrollCore.shared.toggleScroll }
            ),
            Case(
                shortcutName: "mosScrollBlock",
                configureLegacyHotkey: { Options.shared.scroll.block = $0 },
                isRoleActive: { ScrollCore.shared.blockSmooth }
            ),
        ]

        for testCase in cases {
            InputProcessor.shared.clearActiveBindings()
            ScrollCore.shared.dashScroll = false
            ScrollCore.shared.dashAmplification = 1.0
            ScrollCore.shared.toggleScroll = false
            ScrollCore.shared.blockSmooth = false
            ScrollCore.shared.dashKeyHeld = false
            ScrollCore.shared.toggleKeyHeld = false
            ScrollCore.shared.blockKeyHeld = false
            Options.shared.scroll.dash = nil
            Options.shared.scroll.toggle = nil
            Options.shared.scroll.block = nil

            let trigger = RecordedEvent(type: .mouse, code: 2, modifiers: 0, displayComponents: ["🖱M"], deviceFilter: nil)
            let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: testCase.shortcutName, isEnabled: true)
            Options.shared.buttons.binding = [binding]
            ButtonUtils.shared.invalidateCache()
            testCase.configureLegacyHotkey(ScrollHotkey(type: .mouse, code: 2))

            let legacyDownEvent = CGEvent(
                mouseEventSource: nil,
                mouseType: .otherMouseDown,
                mouseCursorPosition: CGPoint(x: 40, y: 40),
                mouseButton: .center
            )!
            legacyDownEvent.setIntegerValueField(.mouseEventButtonNumber, value: 2)
            _ = ScrollCore.shared.hotkeyEventCallBack(CGEventTapProxy(bitPattern: 1)!, .otherMouseDown, legacyDownEvent, nil)

            XCTAssertEqual(
                InputProcessor.shared.process(InputEvent(type: .mouse, code: 2, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
                .consumed
            )
            XCTAssertTrue(testCase.isRoleActive(), "\(testCase.shortcutName) should be active while held")

            XCTAssertEqual(
                InputProcessor.shared.process(InputEvent(type: .mouse, code: 2, modifiers: .init(rawValue: 0), phase: .up, source: .hidPP, device: nil)),
                .consumed
            )
            XCTAssertFalse(testCase.isRoleActive(), "\(testCase.shortcutName) should release even if the legacy hotkey tap missed up")
        }
    }

    func testProcess_mouseSessionRemainsActiveAfterVirtualModifierReleasesUntilMouseUp() {
        let modifierTrigger = RecordedEvent(type: .mouse, code: 6, modifiers: 0, displayComponents: ["🖱7"], deviceFilter: nil)
        let mouseTrigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let modifierBinding = ButtonBinding(triggerEvent: modifierTrigger, systemShortcutName: "custom::58:0", isEnabled: true)
        let mouseBinding = ButtonBinding(triggerEvent: mouseTrigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        Options.shared.buttons.binding = [modifierBinding, mouseBinding]
        ButtonUtils.shared.invalidateCache()

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertTrue(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertEqual(MouseInteractionSessionController.shared.activeSessionCount, 1)

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 6, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, CGEventFlags.maskAlternate.rawValue)
        XCTAssertTrue(MouseInteractionSessionController.shared.isMotionTapRunning)

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 6, modifiers: .init(rawValue: 0), phase: .up, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, 0)
        XCTAssertTrue(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertEqual(MouseInteractionSessionController.shared.activeSessionCount, 1)

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0), phase: .up, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertFalse(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertEqual(MouseInteractionSessionController.shared.activeSessionCount, 0)
    }

    func testProcess_virtualModifierKeepsMotionTapRunningAfterMouseSessionEndsUntilModifierUp() {
        let modifierTrigger = RecordedEvent(type: .mouse, code: 6, modifiers: 0, displayComponents: ["🖱7"], deviceFilter: nil)
        let mouseTrigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let modifierBinding = ButtonBinding(triggerEvent: modifierTrigger, systemShortcutName: "custom::58:0", isEnabled: true)
        let mouseBinding = ButtonBinding(triggerEvent: mouseTrigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        Options.shared.buttons.binding = [modifierBinding, mouseBinding]
        ButtonUtils.shared.invalidateCache()

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 6, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertTrue(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertEqual(MouseInteractionSessionController.shared.activeSessionCount, 1)

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0), phase: .up, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertTrue(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertEqual(MouseInteractionSessionController.shared.activeSessionCount, 0)
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, CGEventFlags.maskAlternate.rawValue)

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 6, modifiers: .init(rawValue: 0), phase: .up, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertFalse(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, 0)
    }

    func testProcess_multipleVirtualModifiers_applyToMappedMouseEvents() {
        let shiftTrigger = RecordedEvent(type: .mouse, code: 6, modifiers: 0, displayComponents: ["🖱7"], deviceFilter: nil)
        let optionTrigger = RecordedEvent(type: .mouse, code: 7, modifiers: 0, displayComponents: ["🖱8"], deviceFilter: nil)
        let leftTrigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)

        let shiftBinding = ButtonBinding(triggerEvent: shiftTrigger, systemShortcutName: "custom::56:0", isEnabled: true)
        let optionBinding = ButtonBinding(triggerEvent: optionTrigger, systemShortcutName: "custom::58:0", isEnabled: true)
        let leftBinding = ButtonBinding(triggerEvent: leftTrigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        Options.shared.buttons.binding = [shiftBinding, optionBinding, leftBinding]
        ButtonUtils.shared.invalidateCache()

        var observedEvents: [(type: CGEventType, flags: CGEventFlags)] = []
        ShortcutExecutor.shared.setTestingMouseEventObserver { event in
            observedEvents.append((event.type, event.flags))
        }

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 6, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 7, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, CGEventFlags.maskShift.rawValue | CGEventFlags.maskAlternate.rawValue)

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0), phase: .up, source: .hidPP, device: nil)),
            .consumed
        )

        XCTAssertEqual(observedEvents.map(\.type), [.leftMouseDown, .leftMouseUp])
        XCTAssertTrue(observedEvents.allSatisfy { event in
            event.flags.contains(.maskShift) && event.flags.contains(.maskAlternate)
        })
    }

    func testProcess_statefulMouseShortcut_preservesPhysicalModifierFlagsOnSyntheticMouseEvents() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: UInt(CGEventFlags.maskShift.rawValue), displayComponents: ["⇧", "🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        var observedEvents: [(type: CGEventType, flags: CGEventFlags)] = []
        ShortcutExecutor.shared.setTestingMouseEventObserver { event in
            observedEvents.append((event.type, event.flags))
        }

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .maskShift,
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)

        let upEvent = InputEvent(type: .mouse, code: 3, modifiers: .maskShift,
                                 phase: .up, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(upEvent), .consumed)

        XCTAssertEqual(observedEvents.map(\.type), [.leftMouseDown, .leftMouseUp])
        XCTAssertTrue(observedEvents.allSatisfy { $0.flags.contains(.maskShift) })
    }

    func testProcess_mouseTriggerWithoutModifiers_matchesWhenAdditionalModifiersHeld() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        var observedTypes: [CGEventType] = []
        ShortcutExecutor.shared.setTestingMouseEventObserver { event in
            observedTypes.append(event.type)
        }

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .maskShift,
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)

        let upEvent = InputEvent(type: .mouse, code: 3, modifiers: .maskShift,
                                 phase: .up, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(upEvent), .consumed)

        XCTAssertEqual(observedTypes, [.leftMouseDown, .leftMouseUp])
    }

    func testProcess_mouseTriggerPrefersExactModifierBindingOverBaseBinding() {
        let baseTrigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let exactTrigger = RecordedEvent(type: .mouse, code: 3, modifiers: UInt(CGEventFlags.maskShift.rawValue), displayComponents: ["⇧", "🖱4"], deviceFilter: nil)
        let baseBinding = ButtonBinding(triggerEvent: baseTrigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        let exactBinding = ButtonBinding(triggerEvent: exactTrigger, systemShortcutName: "mouseRightClick", isEnabled: true)
        Options.shared.buttons.binding = [baseBinding, exactBinding]
        ButtonUtils.shared.invalidateCache()

        var observedTypes: [CGEventType] = []
        ShortcutExecutor.shared.setTestingMouseEventObserver { event in
            observedTypes.append(event.type)
        }

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .maskShift,
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)

        let upEvent = InputEvent(type: .mouse, code: 3, modifiers: .maskShift,
                                 phase: .up, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(upEvent), .consumed)

        XCTAssertEqual(observedTypes, [.rightMouseDown, .rightMouseUp])
    }

    func testProcess_repeatedDownForSameTrigger_replacesPreviousMouseInteractionSession() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)
        XCTAssertEqual(MouseInteractionSessionController.shared.activeSessionCount, 1)

        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)
        XCTAssertEqual(MouseInteractionSessionController.shared.activeSessionCount, 1)
    }

    func testClearActiveBindings_clearsVirtualModifierFlags() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "custom::56:0", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, KeyCode.getKeyMask(56).rawValue)

        InputProcessor.shared.clearActiveBindings()
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, 0)
    }

    func testClearActiveBindings_clearsActiveMouseInteractionSessions() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)
        XCTAssertEqual(MouseInteractionSessionController.shared.activeSessionCount, 1)

        InputProcessor.shared.clearActiveBindings()
        XCTAssertFalse(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertEqual(MouseInteractionSessionController.shared.activeSessionCount, 0)
    }

    func testButtonCore_passthroughKeyboardEvent_appliesVirtualModifierFlags() {
        let modifierTrigger = RecordedEvent(type: .mouse, code: 6, modifiers: 0, displayComponents: ["🖱7"], deviceFilter: nil)
        let modifierBinding = ButtonBinding(triggerEvent: modifierTrigger, systemShortcutName: "custom::56:0", isEnabled: true)
        Options.shared.buttons.binding = [modifierBinding]
        ButtonUtils.shared.invalidateCache()

        let modifierDown = InputEvent(type: .mouse, code: 6, modifiers: .init(rawValue: 0),
                                      phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(modifierDown), .consumed)
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, CGEventFlags.maskShift.rawValue)

        let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: 0,
            keyDown: true
        )!

        let proxy = CGEventTapProxy(bitPattern: 1)!
        let output = ButtonCore.shared.buttonEventCallBack(proxy, .keyDown, event, nil)

        XCTAssertNotNil(output)
        XCTAssertTrue(event.flags.contains(.maskShift))
    }

    func testCGEventExtensions_otherMouseDraggedIsRecognizedForDiagnostics() {
        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .otherMouseDragged,
            mouseCursorPosition: CGPoint(x: 120, y: 80),
            mouseButton: .center
        )!
        event.setIntegerValueField(.mouseEventButtonNumber, value: 3)

        XCTAssertFalse(event.isMouseEvent)
        XCTAssertTrue(event.isMouseDragEvent)
        XCTAssertTrue(event.isMouseInteractionEvent)
        XCTAssertEqual(event.mouseCode, 3)
        XCTAssertEqual(event.eventTypeName, "otherMouseDragged")
    }

    func testCGEventExtensions_mouseMovedIsRecognizedForDiagnostics() {
        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: CGPoint(x: 12, y: 34),
            mouseButton: .left
        )!

        XCTAssertFalse(event.isMouseEvent)
        XCTAssertFalse(event.isMouseDragEvent)
        XCTAssertTrue(event.isMouseMoveEvent)
        XCTAssertTrue(event.isMouseInteractionEvent)
        XCTAssertEqual(event.eventTypeName, "mouseMoved")
    }

    func testInputEventFromCGEvent_otherMouseDraggedPreservesMouseCode() {
        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .otherMouseDragged,
            mouseCursorPosition: CGPoint(x: 90, y: 45),
            mouseButton: .center
        )!
        event.setIntegerValueField(.mouseEventButtonNumber, value: 3)

        let inputEvent = InputEvent(fromCGEvent: event)
        XCTAssertEqual(inputEvent.type, .mouse)
        XCTAssertEqual(inputEvent.code, 3)
    }

    func testMonitorLogStore_previewShowsNewestLinesWithoutDroppingExportHistory() {
        let store = MonitorLogStore(previewLineLimit: 2)

        store.append("first", to: .buttonEvent)
        store.append("second", to: .buttonEvent)
        store.append("third", to: .buttonEvent)

        XCTAssertEqual(store.previewText(for: .buttonEvent), "third\nsecond")
        XCTAssertEqual(store.exportText(for: .buttonEvent), "first\nsecond\nthird")
    }

    func testMonitorLogStore_clearChannelRemovesPreviewAndHistory() {
        let store = MonitorLogStore(previewLineLimit: 3)

        store.append("one", to: .buttonEvent)
        store.append("two", to: .buttonEvent)
        store.clear(.buttonEvent)

        XCTAssertEqual(store.previewText(for: .buttonEvent), "")
        XCTAssertEqual(store.exportText(for: .buttonEvent), "")
    }

    func testMonitorButtonEventLogLine_includesMouseModifierFlags() {
        let controller = MonitorViewController()

        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: CGPoint(x: 32, y: 48),
            mouseButton: .left
        )!
        event.flags = [.maskShift, .maskCommand]
        event.setIntegerValueField(.mouseEventDeltaX, value: 4)
        event.setIntegerValueField(.mouseEventDeltaY, value: -2)
        event.setIntegerValueField(.eventSourceUserData, value: 42)

        let rendered = controller.buttonEventLogLine(for: event)
        XCTAssertTrue(rendered.contains("mods:[⇧ ⌘]"))
        XCTAssertTrue(rendered.contains("flags:0x"))
        XCTAssertTrue(rendered.contains("userData: 42"))
    }

    func testMonitorButtonEventLogLine_includesFlagsChangedPhaseAndModifierFlags() {
        let controller = MonitorViewController()

        let event = CGEvent(source: nil)!
        event.type = .flagsChanged
        event.setIntegerValueField(.keyboardEventKeycode, value: Int64(KeyCode.optionL))
        event.flags = [.maskAlternate, .maskShift]

        let rendered = controller.buttonEventLogLine(for: event)
        XCTAssertTrue(rendered.contains("flagsChanged"))
        XCTAssertTrue(rendered.contains("phase: down"))
        XCTAssertTrue(rendered.contains("mods:[⇧ ⌥]"))
        XCTAssertTrue(rendered.contains("flags:0x"))
    }

    func testMonitorButtonEventLogLine_includesKeyDownModifiersAndKeyName() {
        let controller = MonitorViewController()

        let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: 0,
            keyDown: true
        )!
        event.flags = [.maskCommand, .maskShift]

        let rendered = controller.buttonEventLogLine(for: event)
        XCTAssertTrue(rendered.contains("keyDown"))
        XCTAssertTrue(rendered.contains("key:"))
        XCTAssertTrue(rendered.contains("keyCode: 0"))
        XCTAssertTrue(rendered.contains("mods:[⇧ ⌘]"))
        XCTAssertTrue(rendered.contains("flags:0x"))
    }

    func testButtonUtilsIndex_returnsOnlyMatchingTypeAndCodeCandidates() {
        let matchingTrigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let matchingWithDifferentModifiers = RecordedEvent(type: .mouse, code: 3, modifiers: UInt(CGEventFlags.maskCommand.rawValue), displayComponents: ["⌘", "🖱4"], deviceFilter: nil)
        let wrongTypeTrigger = RecordedEvent(type: .keyboard, code: 3, modifiers: 0, displayComponents: ["F"], deviceFilter: nil)
        let wrongCodeTrigger = RecordedEvent(type: .mouse, code: 4, modifiers: 0, displayComponents: ["🖱5"], deviceFilter: nil)

        let matchingBinding = ButtonBinding(triggerEvent: matchingTrigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        let matchingWithDifferentModifiersBinding = ButtonBinding(triggerEvent: matchingWithDifferentModifiers, systemShortcutName: "custom::56:0", isEnabled: true)
        let wrongTypeBinding = ButtonBinding(triggerEvent: wrongTypeTrigger, systemShortcutName: "mouseRightClick", isEnabled: true)
        let wrongCodeBinding = ButtonBinding(triggerEvent: wrongCodeTrigger, systemShortcutName: "mouseMiddleClick", isEnabled: true)

        Options.shared.buttons.binding = [
            matchingBinding,
            matchingWithDifferentModifiersBinding,
            wrongTypeBinding,
            wrongCodeBinding,
        ]
        ButtonUtils.shared.invalidateCache()

        let candidates = ButtonUtils.shared.getButtonBindings(for: .mouse, code: 3)

        XCTAssertEqual(
            Set(candidates.map(\.id)),
            Set([matchingBinding.id, matchingWithDifferentModifiersBinding.id])
        )
    }

    func testButtonCore_dispatchEventMask_excludesPrimaryMouseButtons() {
        let core = ButtonCore.shared

        func contains(_ type: CGEventType, in mask: CGEventMask) -> Bool {
            let typeMask = CGEventMask(1 << type.rawValue)
            return mask & typeMask != 0
        }

        XCTAssertFalse(contains(.leftMouseDown, in: core.dispatchEventMask))
        XCTAssertFalse(contains(.leftMouseUp, in: core.dispatchEventMask))
        XCTAssertFalse(contains(.rightMouseDown, in: core.dispatchEventMask))
        XCTAssertFalse(contains(.rightMouseUp, in: core.dispatchEventMask))
        XCTAssertTrue(contains(.otherMouseDown, in: core.dispatchEventMask))
        XCTAssertTrue(contains(.otherMouseUp, in: core.dispatchEventMask))
        XCTAssertTrue(contains(.keyDown, in: core.dispatchEventMask))
        XCTAssertTrue(contains(.keyUp, in: core.dispatchEventMask))
    }

    func testButtonCore_dispatchTapRunsBeforeNativeMouseButtonShortcuts() {
        XCTAssertEqual(
            ButtonCore.shared.dispatchEventTapLocation.rawValue,
            CGEventTapLocation.cgSessionEventTap.rawValue
        )
    }

    private func configureGestureBinding(type: EventType = .mouse, code: UInt16 = 3) {
        let trigger = RecordedEvent(
            type: type,
            code: code,
            modifiers: 0,
            displayComponents: [type == .mouse ? "🖱4" : "Z"],
            deviceFilter: nil
        )
        Options.shared.buttons.binding = [
            ButtonBinding(
                triggerEvent: trigger,
                systemShortcutName: SystemShortcut.mouseGestureNavigation.identifier,
                isEnabled: true
            )
        ]
        ButtonUtils.shared.invalidateCache()
    }

    private func gestureInputEvent(phase: InputPhase, code: UInt16 = 3) -> InputEvent {
        return InputEvent(
            type: .mouse,
            code: code,
            modifiers: [],
            phase: phase,
            source: .hidPP,
            device: nil
        )
    }

    private func resolvedShortcut(_ shortcut: SystemShortcut.Shortcut) -> (code: CGKeyCode, flags: UInt64) {
        return SystemShortcut.resolveSystemShortcut(shortcut.identifier)
            ?? (shortcut.code, UInt64(shortcut.modifiers.rawValue))
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

    /// Captures keyboard shortcuts posted by ShortcutExecutor; call the result to read them.
    private func recordKeyboardShortcuts() -> () -> [(CGKeyCode, UInt64)] {
        var executed: [(CGKeyCode, UInt64)] = []
        ShortcutExecutor.shared.setTestingKeyboardShortcutObserver { code, flags, _ in
            executed.append((code, flags))
        }
        return { executed }
    }

    private func makeMouseMoveEvent(
        deltaX: Double,
        deltaY: Double,
        location: CGPoint = CGPoint(x: 40, y: 40)
    ) -> CGEvent {
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

}
