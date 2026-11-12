import XCTest
@testable import Scrollio_Debug

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
        // A wheel event a test sends through the scroll tap's callback stops here: without
        // an observer it went on to the shared scroll poster, which made and started a real
        // display link and left a glide running across the following tests.
        ScrollCore.posterInputObserverForTests = { _ in }
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
        ScrollCore.posterInputObserverForTests = nil
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

    /// The cores stop (sleep, another user, lost Accessibility access, Pause) while a gesture
    /// button is held: the pointer-movement tap is let go, and the hold still ends cleanly.
    func testReleasingTheMotionTapMidHoldEndsTheHoldAndFreesThePointer() {
        configureGestureBinding()
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down)), .consumed)
        XCTAssertTrue(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertTrue(MouseGesturePointerLock.shared.isLocked)

        MouseInteractionSessionController.shared.releaseMotionTap()

        XCTAssertFalse(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertFalse(InputProcessor.shared.hasActiveMouseGestureSessions)
        XCTAssertFalse(InputProcessor.shared.hasPointerTrackedMouseGestureSessions)
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

        // A hold that was merely long: its button-up still belongs to Scrollio, and it must not
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

    /// Where the Buttons pane says a numbered button is (`mousePart`) is display only: the
    /// binding runs for the same button and modifiers as without it, and for no other.
    func testProcess_placedNumberedButtonMatchesAsBefore() {
        let trigger = RecordedEvent(type: .mouse, code: 6, modifiers: 0, deviceFilter: nil, mousePart: .gestureButton)
        Options.shared.buttons.binding = [ButtonBinding(triggerEvent: trigger, systemShortcutName: "custom::56:0", isEnabled: true)]
        ButtonUtils.shared.invalidateCache()

        func press(_ code: UInt16) -> InputResult {
            let down = InputProcessor.shared.process(InputEvent(type: .mouse, code: code, modifiers: CGEventFlags(rawValue: 0),
                                                                 phase: .down, source: .hidPP, device: nil))
            _ = InputProcessor.shared.process(InputEvent(type: .mouse, code: code, modifiers: CGEventFlags(rawValue: 0),
                                                         phase: .up, source: .hidPP, device: nil))
            return down
        }
        XCTAssertEqual(press(6), .consumed)
        XCTAssertEqual(press(5), .passthrough, "the gesture button's place does not make another button match")
        XCTAssertEqual(press(3), .passthrough)
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

    func testResolveAction_scrollActionsAreStateful() {
        for identifier in ["scrollDash", "scrollToggle", "scrollBlock"] {
            guard let action = ShortcutExecutor.shared.resolveAction(named: identifier) else {
                return XCTFail("Expected \(identifier) action to resolve")
            }

            XCTAssertEqual(action.executionMode, .stateful)
        }
    }

    func testProcess_scrollDash_downAndUpControlsDashState() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "scrollDash", isEnabled: true)
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

    func testProcess_scrollActionMiddleTapWithoutScroll_replaysOriginalMouseClick() {
        let trigger = RecordedEvent(type: .mouse, code: 2, modifiers: 0, displayComponents: ["🖱M"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "scrollDash", isEnabled: true)
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
        XCTAssertEqual(observedEvents.map(\.userData), [ScrollioEventMarker.syntheticCustom, ScrollioEventMarker.syntheticCustom])
        XCTAssertFalse(ScrollCore.shared.dashScroll)
    }

    func testProcess_scrollActionMiddleTapWithScrollUse_doesNotReplayOriginalMouseClick() {
        let trigger = RecordedEvent(type: .mouse, code: 2, modifiers: 0, displayComponents: ["🖱M"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "scrollDash", isEnabled: true)
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
        InputProcessor.shared.markScrollActionSessionsUsedForScroll()

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 2, modifiers: .init(rawValue: 0), phase: .up, source: .hidPP, device: nil)),
            .consumed
        )

        XCTAssertTrue(observedEvents.isEmpty)
        XCTAssertFalse(ScrollCore.shared.dashScroll)
    }

    func testScrollCore_scrollWheelWhileScrollActionHeldSuppressesTapReplay() {
        let trigger = RecordedEvent(type: .mouse, code: 2, modifiers: 0, displayComponents: ["🖱M"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "scrollDash", isEnabled: true)
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
        _ = ScrollCore.shared.scrollEventCallBack(CGEventTapProxy(bitPattern: 1)!, .scrollWheel, scrollEvent, nil)

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 2, modifiers: .init(rawValue: 0), phase: .up, source: .hidPP, device: nil)),
            .consumed
        )

        XCTAssertTrue(observedEvents.isEmpty)
        XCTAssertFalse(ScrollCore.shared.dashScroll)
    }

    func testScrollCore_scrollWheelReleasesCGScrollActionSessionWhenPhysicalButtonIsNoLongerDown() {
        let trigger = RecordedEvent(type: .mouse, code: 2, modifiers: 0, displayComponents: ["🖱M"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "scrollDash", isEnabled: true)
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
        _ = ScrollCore.shared.scrollEventCallBack(CGEventTapProxy(bitPattern: 1)!, .scrollWheel, scrollEvent, nil)

        XCTAssertFalse(ScrollCore.shared.dashScroll)
        XCTAssertEqual(ScrollCore.shared.dashAmplification, 1.0)
    }

    func testProcess_scrollActionCGMouseTapWithPointerMove_doesNotReplayOriginalMouseClick() {
        let trigger = RecordedEvent(type: .mouse, code: 2, modifiers: 0, displayComponents: ["🖱M"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "scrollDash", isEnabled: true)
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

    func testProcess_logiButtonCanTriggerScrollToggle() {
        let trigger = RecordedEvent(
            type: .mouse,
            code: 1007,
            modifiers: 0,
            displayComponents: ["[Logi]", "Forward"],
            deviceFilter: nil
        )
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "scrollToggle", isEnabled: true)
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

    func testProcess_logiScrollActionForwardTapWithoutScroll_replaysForwardButton() {
        let trigger = RecordedEvent(
            type: .mouse,
            code: 1007,
            modifiers: 0,
            displayComponents: ["[Logi]", "Forward"],
            deviceFilter: nil
        )
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "scrollToggle", isEnabled: true)
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

    func testSyntheticReleaseOfAScrollActionHoldDoesNotReplayTheClick() {
        let trigger = RecordedEvent(type: .mouse, code: 1007, modifiers: 0, displayComponents: ["[Logi]", "Forward"], deviceFilter: nil)
        Options.shared.buttons.binding = [ButtonBinding(triggerEvent: trigger, systemShortcutName: "scrollToggle", isEnabled: true)]
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

    func testProcess_scrollBlock_downAndUpControlsBlockState() {
        let trigger = RecordedEvent(type: .mouse, code: 5, modifiers: 0, displayComponents: ["🖱6"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "scrollBlock", isEnabled: true)
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

    func testProcess_multipleScrollDashTriggers_releaseOneKeepsDashActive() {
        let firstTrigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let secondTrigger = RecordedEvent(type: .mouse, code: 4, modifiers: 0, displayComponents: ["🖱5"], deviceFilter: nil)
        let firstBinding = ButtonBinding(triggerEvent: firstTrigger, systemShortcutName: "scrollDash", isEnabled: true)
        let secondBinding = ButtonBinding(triggerEvent: secondTrigger, systemShortcutName: "scrollDash", isEnabled: true)
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

    func testProcess_scrollActionBindingDoesNotLatchWhenLegacyScrollHotkeySeesOnlyDown() {
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
                shortcutName: "scrollDash",
                configureLegacyHotkey: { Options.shared.scroll.dash = $0 },
                isRoleActive: { ScrollCore.shared.dashScroll }
            ),
            Case(
                shortcutName: "scrollToggle",
                configureLegacyHotkey: { Options.shared.scroll.toggle = $0 },
                isRoleActive: { ScrollCore.shared.toggleScroll }
            ),
            Case(
                shortcutName: "scrollBlock",
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

    /// The store keeps the newest lines only: it used to grow for as long as the window was open.
    func testMonitorLogStore_dropsTheOldestLinesPastItsLimit() {
        let store = MonitorLogStore(previewLineLimit: 2, lineLimit: 100)
        for index in 0..<1_000 {
            store.append("line \(index)", to: .buttonEvent)
        }
        XCTAssertLessThanOrEqual(store.lineCount(for: .buttonEvent), 110, "the limit and a tenth")
        XCTAssertGreaterThanOrEqual(store.lineCount(for: .buttonEvent), 100)
        XCTAssertEqual(store.previewText(for: .buttonEvent), "line 999\nline 998", "the newest are kept")
        XCTAssertFalse(store.exportText(for: .buttonEvent).contains("line 0\n"), "the oldest are gone")
    }

    /// The Monitor window asks for mouse events and modifier changes, never for ordinary keys:
    /// it must not be able to log what is typed.
    func testMonitorTap_doesNotAskForOrdinaryKeys() {
        let mask = MonitorViewController().buttonEventMask
        XCTAssertEqual(mask & CGEventMask(1 << CGEventType.keyDown.rawValue), 0)
        XCTAssertEqual(mask & CGEventMask(1 << CGEventType.keyUp.rawValue), 0)
        XCTAssertNotEqual(mask & CGEventMask(1 << CGEventType.flagsChanged.rawValue), 0, "modifiers, to debug hold keys")
        XCTAssertNotEqual(mask & CGEventMask(1 << CGEventType.otherMouseDown.rawValue), 0)
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
        // The keyboard has a tap of its own, made only while it is needed.
        XCTAssertFalse(contains(.keyDown, in: core.dispatchEventMask))
        XCTAssertFalse(contains(.keyUp, in: core.dispatchEventMask))
        XCTAssertEqual(core.keyEventMask, CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue))
    }

    func testButtonCore_dispatchTapRunsBeforeNativeMouseButtonShortcuts() {
        XCTAssertEqual(
            ButtonCore.shared.dispatchEventTapLocation.rawValue,
            CGEventTapLocation.cgSessionEventTap.rawValue
        )
    }

    // MARK: - Where a synthesized click lands

    /// Cocoa and CoreGraphics coordinates both hang on the primary display. The conversion
    /// used the key window's screen (`NSScreen.main`): with that window on a display of
    /// another height, every synthesized click landed off by the difference.
    func testASynthesizedClickIsPlacedFromThePrimaryDisplay() {
        // Primary display 1440 x 900 at the origin; a 1920 x 1080 display above it
        // (Cocoa y 900...1980), which would have been NSScreen.main with a window there.
        let onTheSecondDisplay = NSPoint(x: 300, y: 1500)
        XCTAssertEqual(ShortcutExecutor.cgEventLocation(fromCocoa: onTheSecondDisplay, primaryScreenHeight: 900),
                       CGPoint(x: 300, y: -600))
        XCTAssertNotEqual(ShortcutExecutor.cgEventLocation(fromCocoa: onTheSecondDisplay, primaryScreenHeight: 1080),
                          CGPoint(x: 300, y: -600), "measured from the other display it was 180 pt off")
        // On the primary display: its top left is (0, 0) in CoreGraphics.
        XCTAssertEqual(ShortcutExecutor.cgEventLocation(fromCocoa: NSPoint(x: 10, y: 890), primaryScreenHeight: 900),
                       CGPoint(x: 10, y: 10))
    }

    // MARK: - A held keyboard trigger (auto-repeat)

    private func keyEvent(_ code: CGKeyCode, down: Bool, flags: CGEventFlags, repeating: Bool = false) -> InputEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
        event.flags = flags
        if repeating {
            event.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        }
        return InputEvent(fromCGEvent: event)
    }

    private func bindKey(_ code: UInt16, flags: CGEventFlags, to action: String) {
        let trigger = RecordedEvent(type: .keyboard, code: code, modifiers: UInt(flags.rawValue),
                                    displayComponents: ["⌃ ⌥", "F"], deviceFilter: nil)
        Options.shared.buttons.binding = [ButtonBinding(triggerEvent: trigger, systemShortcutName: action, isEnabled: true)]
        ButtonUtils.shared.invalidateCache()
    }

    func testAnInputEventKnowsAnAutoRepeat() {
        XCTAssertFalse(keyEvent(3, down: true, flags: []).isAutoRepeat)
        XCTAssertTrue(keyEvent(3, down: true, flags: [], repeating: true).isAutoRepeat)
        XCTAssertFalse(keyEvent(3, down: false, flags: [], repeating: true).isAutoRepeat, "only a keyDown repeats")
        XCTAssertFalse(InputEvent(type: .keyboard, code: 3, modifiers: [], phase: .down, source: .hidPP, device: nil).isAutoRepeat)
    }

    /// A held keyboard trigger repeats its keyDown, and a trigger action ran again for every
    /// repeat (a key bound to the shortcut it is itself ran in a loop).
    func testAHeldKeyboardTriggerRunsItsActionOncePerPress() {
        let flags: CGEventFlags = [.maskControl, .maskAlternate]
        bindKey(3, flags: flags, to: SystemShortcut.copy.identifier)
        let executed = recordKeyboardShortcuts()

        XCTAssertEqual(InputProcessor.shared.process(keyEvent(3, down: true, flags: flags)), .consumed)
        for _ in 0..<5 {
            XCTAssertEqual(InputProcessor.shared.process(keyEvent(3, down: true, flags: flags, repeating: true)), .consumed,
                           "the repeat is swallowed")
        }
        XCTAssertEqual(executed().count, 1)
        _ = InputProcessor.shared.process(keyEvent(3, down: false, flags: flags))

        XCTAssertEqual(InputProcessor.shared.process(keyEvent(3, down: true, flags: flags)), .consumed)
        XCTAssertEqual(executed().count, 2, "the next press runs it again")
    }

    /// A key bound to a click: holding it holds the button (a drag), instead of releasing and
    /// pressing it again on every repeat.
    func testAHeldKeyboardTriggerHoldsItsMouseButton() {
        let flags: CGEventFlags = [.maskControl, .maskAlternate]
        bindKey(3, flags: flags, to: "mouseLeftClick")
        var observedTypes: [CGEventType] = []
        ShortcutExecutor.shared.setTestingMouseEventObserver { observedTypes.append($0.type) }

        XCTAssertEqual(InputProcessor.shared.process(keyEvent(3, down: true, flags: flags)), .consumed)
        for _ in 0..<3 {
            XCTAssertEqual(InputProcessor.shared.process(keyEvent(3, down: true, flags: flags, repeating: true)), .consumed)
        }
        XCTAssertEqual(InputProcessor.shared.process(keyEvent(3, down: false, flags: flags)), .consumed)

        XCTAssertEqual(observedTypes, [.leftMouseDown, .leftMouseUp])
    }

    /// A key without a binding repeats for the app in front, as always.
    func testTheRepeatOfAnUnboundKeyPassesThrough() {
        XCTAssertEqual(InputProcessor.shared.process(keyEvent(3, down: true, flags: [])), .passthrough)
        XCTAssertEqual(InputProcessor.shared.process(keyEvent(3, down: true, flags: [], repeating: true)), .passthrough)
    }

    /// Only a plain key as the action keeps repeating with its trigger (as before): a mouse
    /// button, a modifier or a Scrollio scroll action stays held.
    func testOnlyAPlainKeyActionRepeatsWithItsTrigger() {
        XCTAssertTrue(InputProcessor.repeatsWhileHeld(.customKey(code: 125, modifiers: 0)))
        XCTAssertTrue(InputProcessor.repeatsWhileHeld(.customKey(code: 8, modifiers: CGEventFlags.maskCommand.rawValue)))
        XCTAssertFalse(InputProcessor.repeatsWhileHeld(.customKey(code: KeyCode.shiftL, modifiers: 0)))
        XCTAssertFalse(InputProcessor.repeatsWhileHeld(.mouseButton(kind: .left)))
        XCTAssertFalse(InputProcessor.repeatsWhileHeld(.customMouseButton(buttonNumber: 5, modifiers: 0)))
        XCTAssertFalse(InputProcessor.repeatsWhileHeld(.scrollAction(role: .dash)))
    }

    // MARK: - Shortcuts Scrollio posts are marked as its own

    func testShortcutKeyEventsAreMarkedAsScrolliosOwn() throws {
        let command = CGEventFlags.maskCommand.rawValue
        let down = try XCTUnwrap(ShortcutExecutor.shortcutKeyEvent(code: 8, flags: command, keyDown: true,
                                                                   preserveFlagsOnKeyUp: false, source: nil))
        let up = try XCTUnwrap(ShortcutExecutor.shortcutKeyEvent(code: 8, flags: command, keyDown: false,
                                                                 preserveFlagsOnKeyUp: false, source: nil))
        XCTAssertEqual(down.type, .keyDown)
        XCTAssertEqual(up.type, .keyUp)
        XCTAssertEqual(down.keyCode, 8)
        XCTAssertEqual(up.keyCode, 8)
        XCTAssertEqual(down.getIntegerValueField(.eventSourceUserData), ScrollioEventMarker.syntheticCustom)
        XCTAssertEqual(up.getIntegerValueField(.eventSourceUserData), ScrollioEventMarker.syntheticCustom)
        XCTAssertTrue(down.flags.contains(.maskCommand))
        XCTAssertFalse(up.flags.contains(.maskCommand), "the key up carries the flags only when asked to")
        let keptUp = try XCTUnwrap(ShortcutExecutor.shortcutKeyEvent(code: 48, flags: command, keyDown: false,
                                                                     preserveFlagsOnKeyUp: true, source: nil))
        XCTAssertTrue(keptUp.flags.contains(.maskCommand))
        XCTAssertEqual(keptUp.getIntegerValueField(.eventSourceUserData), ScrollioEventMarker.syntheticCustom)
    }

    /// What the mark is for: the button tap lets a posted shortcut through untouched. Before,
    /// a keyboard trigger bound to the shortcut it is itself ran again for its own output.
    func testTheButtonTapLetsAPostedShortcutThroughWithoutRunningABinding() throws {
        bindKey(8, flags: .maskCommand, to: SystemShortcut.copy.identifier)
        let executed = recordKeyboardShortcuts()
        let posted = try XCTUnwrap(ShortcutExecutor.shortcutKeyEvent(code: 8, flags: CGEventFlags.maskCommand.rawValue,
                                                                     keyDown: true, preserveFlagsOnKeyUp: false, source: nil))

        let proxy = CGEventTapProxy(bitPattern: 1)!
        XCTAssertNotNil(ButtonCore.shared.buttonEventCallBack(proxy, .keyDown, posted, nil))
        XCTAssertEqual(executed().count, 0)
    }

    // MARK: - The user's System Settings shortcuts are read again

    /// They were read once, so a shortcut changed in System Settings (Move left a space)
    /// was ignored until the next launch.
    func testTheSystemShortcutsAreReadAgainWhenTheyMayHaveChanged() {
        XCTAssertTrue(SystemShortcut.reloadsSystemShortcuts(after: NSApplication.didBecomeActiveNotification),
                      "Scrollio became active: its settings opened")
        XCTAssertTrue(SystemShortcut.reloadsSystemShortcuts(
            after: NSWorkspace.didDeactivateApplicationNotification,
            deactivatedBundleIdentifier: "com.apple.systempreferences"
        ), "System Settings went to the background")
        XCTAssertFalse(SystemShortcut.reloadsSystemShortcuts(
            after: NSWorkspace.didDeactivateApplicationNotification,
            deactivatedBundleIdentifier: "com.apple.Safari"
        ))
        XCTAssertFalse(SystemShortcut.reloadsSystemShortcuts(after: NSWorkspace.didDeactivateApplicationNotification))
        XCTAssertFalse(SystemShortcut.reloadsSystemShortcuts(after: NSApplication.didResignActiveNotification))
    }

    /// The Spaces shortcuts are read from System Settings' preferences, another app's data:
    /// a value that is no key code or no flag set is skipped. It used to trap, at launch and
    /// every time Scrollio became active.
    func testSystemShortcuts_skipValuesThatAreNoKeyCode() {
        func entry(_ parameters: [Any], enabled: Bool = true) -> [String: Any] {
            return ["enabled": enabled, "value": ["parameters": parameters, "type": "standard"]]
        }
        let good = SystemShortcut.resolvedShortcuts(fromSymbolicHotKeys: [
            "79": entry([65535, 123, 8650752]),
            "81": entry([65535, 124, 8650752]),
        ])
        XCTAssertEqual(good["moveSpaceLeft"]?.code, 123)
        XCTAssertEqual(good["moveSpaceLeft"]?.modifiers, 8650752)
        XCTAssertEqual(good["moveSpaceRight"]?.code, 124)

        let bad = SystemShortcut.resolvedShortcuts(fromSymbolicHotKeys: [
            "79": entry([65535, -1, 8650752]),          // no key code
            "81": entry([65535, 70_000, 8650752]),      // too large for one
            "80": entry([65535, 123, -5]),              // no flag set (the variant is not used anyway)
            "82": entry(["x", "y", "z"]),
        ])
        XCTAssertTrue(bad.isEmpty)
        XCTAssertTrue(SystemShortcut.resolvedShortcuts(fromSymbolicHotKeys: ["79": entry([65535, 123, 8650752], enabled: false)]).isEmpty)
        XCTAssertTrue(SystemShortcut.resolvedShortcuts(fromSymbolicHotKeys: ["79": "nonsense", "81": 4]).isEmpty)
    }

    // MARK: - The release of a native button that ran a trigger action

    private func bindNativeButton3(to action: String) {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        Options.shared.buttons.binding = [ButtonBinding(triggerEvent: trigger, systemShortcutName: action, isEnabled: true)]
        ButtonUtils.shared.invalidateCache()
    }

    private func nativeButton3(_ type: CGEventType) -> InputEvent {
        return InputEvent(fromCGEvent: makeOtherMouseEvent(type))
    }

    /// The press was swallowed but the release went on to the app under the pointer: a
    /// mouse-up without a mouse-down.
    func testTheReleaseOfANativeButtonThatRanATriggerActionIsSwallowed() {
        bindNativeButton3(to: SystemShortcut.missionControl.identifier)
        let executed = recordKeyboardShortcuts()

        XCTAssertEqual(InputProcessor.shared.process(nativeButton3(.otherMouseDown)), .consumed)
        XCTAssertEqual(executed().count, 1)
        XCTAssertEqual(InputProcessor.shared.process(nativeButton3(.otherMouseUp)), .consumed)
        XCTAssertEqual(executed().count, 1, "the release runs nothing")
        // Only that one release: the next is the app's again.
        XCTAssertEqual(InputProcessor.shared.process(nativeButton3(.otherMouseUp)), .passthrough)
    }

    /// Pause, sleep or a tap restart while the button is down: no entry stays behind.
    func testClearingForgetsASwallowedTriggerPress() {
        bindNativeButton3(to: SystemShortcut.missionControl.identifier)
        _ = recordKeyboardShortcuts()
        XCTAssertEqual(InputProcessor.shared.process(nativeButton3(.otherMouseDown)), .consumed)

        InputProcessor.shared.clearActiveBindings()

        XCTAssertEqual(InputProcessor.shared.process(nativeButton3(.otherMouseUp)), .passthrough)
    }

    /// A release that never came is forgotten at the button's next press, whatever that press
    /// does, so it cannot swallow a release that belongs to the app.
    func testANewPressForgetsATriggerPressWhoseReleaseWasLost() {
        bindNativeButton3(to: SystemShortcut.missionControl.identifier)
        _ = recordKeyboardShortcuts()
        XCTAssertEqual(InputProcessor.shared.process(nativeButton3(.otherMouseDown)), .consumed)

        Options.shared.buttons.binding = []
        ButtonUtils.shared.invalidateCache()
        XCTAssertEqual(InputProcessor.shared.process(nativeButton3(.otherMouseDown)), .passthrough)
        XCTAssertEqual(InputProcessor.shared.process(nativeButton3(.otherMouseUp)), .passthrough)
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

    // MARK: - The pointer-movement tap's own pause

    private func bind(_ bindings: [(button: UInt16, action: String)]) {
        Options.shared.buttons.binding = bindings.map { binding in
            ButtonBinding(
                triggerEvent: RecordedEvent(type: .mouse, code: binding.button, modifiers: 0, deviceFilter: nil),
                systemShortcutName: binding.action,
                isEnabled: true
            )
        }
        ButtonUtils.shared.invalidateCache()
    }

    private func nativeButton(_ number: Int64, _ type: CGEventType) -> InputEvent {
        return InputEvent(fromCGEvent: makeOtherMouseEvent(type, buttonNumber: number))
    }

    /// After every use the app pauses the pointer-movement tap, and the tap's callback then
    /// gets "disabled by user input". That was treated like a timeout: every held action was
    /// released. A button held for "scroll fast" lost its hold as soon as another button,
    /// bound to a click, was released, and its own release then went to the app as an up
    /// without a down.
    func testTheMotionTapsOwnPauseDoesNotEndOtherHeldActions() throws {
        bind([(3, "scrollDash"), (4, "mouseMiddleClick")])
        let pauseEvent = try XCTUnwrap(CGEvent(source: nil))

        XCTAssertEqual(InputProcessor.shared.process(nativeButton(3, .otherMouseDown)), .consumed)
        XCTAssertTrue(ScrollCore.shared.dashScroll)
        XCTAssertEqual(InputProcessor.shared.process(nativeButton(4, .otherMouseDown)), .consumed)
        XCTAssertTrue(MouseInteractionSessionController.shared.isMotionTapRunning, "the click's drag needs the tap")
        XCTAssertEqual(InputProcessor.shared.process(nativeButton(4, .otherMouseUp)), .consumed)
        XCTAssertFalse(MouseInteractionSessionController.shared.isMotionTapRunning, "paused again")

        // What the paused tap's callback gets.
        let passed = MouseInteractionSessionController.shared.handleMotionTapEventForTests(type: .tapDisabledByUserInput, event: pauseEvent)
        XCTAssertNotNil(passed)
        XCTAssertTrue(ScrollCore.shared.dashScroll, "button 3 is still down: its hold goes on")
        XCTAssertEqual(InputProcessor.shared.process(nativeButton(3, .otherMouseUp)), .consumed,
                       "and its release is still its own, not an up without a down for the app")
        XCTAssertFalse(ScrollCore.shared.dashScroll)

        // A timeout is still a failure: everything held is released.
        XCTAssertEqual(InputProcessor.shared.process(nativeButton(3, .otherMouseDown)), .consumed)
        XCTAssertTrue(ScrollCore.shared.dashScroll)
        MouseInteractionSessionController.shared.handleMotionTapEventForTests(type: .tapDisabledByTimeout, event: pauseEvent)
        XCTAssertFalse(ScrollCore.shared.dashScroll)
    }

    // MARK: - Actions that are none, triggers that cannot run

    /// An unknown action counted as a shortcut: the press and the release were swallowed and
    /// nothing was sent, so the button lost its own function too.
    func testABindingWithAnActionThisVersionDoesNotKnowLeavesTheButtonAlone() {
        let executed = recordKeyboardShortcuts()
        for action in ["actionOfANewerVersion", "logiActionOfANewerVersion"] {
            bindNativeButton3(to: action)
            XCTAssertEqual(InputProcessor.shared.process(nativeButton3(.otherMouseDown)), .passthrough, action)
            XCTAssertEqual(InputProcessor.shared.process(nativeButton3(.otherMouseUp)), .passthrough, action)
        }
        XCTAssertEqual(executed().count, 0)
    }

    /// "Shut Down…" is retired: a stored binding keeps the button, and sends nothing (it
    /// sent Control-Z).
    func testAStoredShutDownBindingSendsNothing() {
        bindNativeButton3(to: "shutdownDialog")
        let executed = recordKeyboardShortcuts()
        XCTAssertEqual(InputProcessor.shared.process(nativeButton3(.otherMouseDown)), .consumed)
        XCTAssertEqual(InputProcessor.shared.process(nativeButton3(.otherMouseUp)), .consumed)
        XCTAssertEqual(executed().count, 0)
    }

    /// The rule "a key needs a modifier, unless it is an F-key" lived in the recorder only.
    /// A binding is data: one written into the settings with a plain key as its trigger ran
    /// its action (a script, a file) at the next press of that key.
    func testAKeyWithoutAModifierIsNoTriggerUnlessItIsAnFKey() {
        let executed = recordKeyboardShortcuts()
        // Space, a letter, Return: stored, listed, never matched.
        for code: UInt16 in [49, 40, 36] {
            bindKey(code, flags: [], to: SystemShortcut.copy.identifier)
            XCTAssertEqual(Options.shared.buttons.binding.count, 1, "the binding stays stored")
            XCTAssertEqual(InputProcessor.shared.process(keyEvent(CGKeyCode(code), down: true, flags: [])), .passthrough)
            XCTAssertEqual(InputProcessor.shared.process(keyEvent(CGKeyCode(code), down: false, flags: [])), .passthrough)
            XCTAssertFalse(ButtonUtils.shared.hasKeyboardTriggers)
        }
        XCTAssertEqual(executed().count, 0)
        // An F-key alone, and a key with a modifier, as the recorder takes them.
        bindKey(KeyCode.F5, flags: [], to: SystemShortcut.copy.identifier)
        XCTAssertEqual(InputProcessor.shared.process(keyEvent(CGKeyCode(KeyCode.F5), down: true, flags: [])), .consumed)
        XCTAssertTrue(ButtonUtils.shared.hasKeyboardTriggers)
        bindKey(40, flags: .maskControl, to: SystemShortcut.copy.identifier)
        XCTAssertEqual(InputProcessor.shared.process(keyEvent(40, down: true, flags: .maskControl)), .consumed)
        XCTAssertEqual(executed().count, 2)

        func trigger(_ type: EventType, _ code: UInt16, _ flags: CGEventFlags = []) -> RecordedEvent {
            return RecordedEvent(type: type, code: code, modifiers: UInt(flags.rawValue), deviceFilter: nil)
        }
        XCTAssertFalse(ButtonUtils.isRunnable(trigger(.keyboard, 40)))
        XCTAssertFalse(ButtonUtils.isRunnable(trigger(.keyboard, 40, .maskSecondaryFn)), "Fn is no modifier of the rule")
        XCTAssertFalse(ButtonUtils.isRunnable(trigger(.keyboard, KeyCode.shiftL, .maskShift)), "a modifier key alone")
        XCTAssertTrue(ButtonUtils.isRunnable(trigger(.keyboard, 40, .maskShift)))
        XCTAssertTrue(ButtonUtils.isRunnable(trigger(.keyboard, KeyCode.F13)))
        // The left and right buttons are never a trigger; every other button is.
        XCTAssertFalse(ButtonUtils.isRunnable(trigger(.mouse, 0, .maskAlternate)))
        XCTAssertFalse(ButtonUtils.isRunnable(trigger(.mouse, 1, .maskCommand)))
        XCTAssertTrue(ButtonUtils.isRunnable(trigger(.mouse, 2)))
        XCTAssertTrue(ButtonUtils.isRunnable(trigger(.mouse, 1006)), "a Logitech button")
    }

    /// "⌥ + left click" could be recorded, got a row and an action, and never ran: no event
    /// tap of the app sees the left and right buttons.
    func testTheLeftAndRightButtonsAreNeverRecordedAsATrigger() {
        func click(_ code: UInt16, _ flags: CGEventFlags) -> InputEvent {
            return InputEvent(type: .mouse, code: code, modifiers: flags, phase: .down, source: .hidPP, device: nil)
        }
        XCTAssertFalse(click(0, .maskAlternate).isRecordable)
        XCTAssertFalse(click(1, .maskCommand).isRecordable)
        XCTAssertFalse(click(0, []).isRecordable)
        XCTAssertTrue(click(2, []).isRecordable)
        XCTAssertTrue(click(3, .maskShift).isRecordable)
        let mask = ButtonCore.shared.dispatchEventMask
        XCTAssertEqual(mask & CGEventMask(1 << CGEventType.leftMouseDown.rawValue), 0)
        XCTAssertEqual(mask & CGEventMask(1 << CGEventType.rightMouseDown.rawValue), 0)

        // The recorder says why, instead of only shaking.
        let leftRight = NSLocalizedString("key-recorder-left-right-refused", comment: "")
        XCTAssertEqual(KeyRecorder.refusalReason(for: click(0, .maskAlternate), mode: .combination), leftRight)
        XCTAssertEqual(KeyRecorder.refusalReason(for: click(1, []), mode: .combination), leftRight)
        XCTAssertEqual(KeyRecorder.refusalReason(for: click(1, []), mode: .singleKey), leftRight)
        XCTAssertEqual(KeyRecorder.refusalReason(for: click(0, .maskShift), mode: .adaptive),
                       NSLocalizedString("key-recorder-left-refused", comment: ""))
        XCTAssertNil(KeyRecorder.refusalReason(for: click(1, []), mode: .adaptive), "the right button can be sent")
        XCTAssertNil(KeyRecorder.refusalReason(for: click(3, []), mode: .combination))
        XCTAssertNil(KeyRecorder.refusalReason(for: keyEvent(3, down: true, flags: []), mode: .combination), "an ordinary wrong key")
        XCTAssertNotEqual(leftRight, "key-recorder-left-right-refused")
    }

    /// A gesture set to one of the "Logitech Mouse" actions runs it (seven of the ten did
    /// nothing from a gesture).
    func testAGestureRunsALogitechAction() {
        configureGestureBinding()
        Options.shared.gesture.upAction = "logiHost2"
        var performed: [String] = []
        let original = ShortcutExecutor.shared.logiActionPerformer
        ShortcutExecutor.shared.logiActionPerformer = { performed.append($0) }
        defer { ShortcutExecutor.shared.logiActionPerformer = original }

        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down)), .consumed)
        InputProcessor.shared.handleMouseGestureMovement(deltaX: 0, deltaY: -45)
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .up)), .consumed)
        waitForMainQueue()
        XCTAssertEqual(performed, ["logiHost2"])
    }

    // MARK: - When the keyboard is needed at all

    /// ButtonCore's keys tap exists only while this is true: a key is bound, a button holds
    /// a modifier, or an action started by a key is still held.
    func testTheKeyboardIsNeededOnlyForKeyBindingsAndHeldModifiers() {
        // Nothing bound (the default), or only mouse buttons: no keyboard.
        XCTAssertFalse(InputProcessor.shared.needsKeyEvents)
        bind([(3, SystemShortcut.missionControl.identifier), (4, "mouseMiddleClick")])
        XCTAssertFalse(InputProcessor.shared.needsKeyEvents)
        XCTAssertEqual(InputProcessor.shared.process(nativeButton(4, .otherMouseDown)), .consumed)
        XCTAssertFalse(InputProcessor.shared.needsKeyEvents, "a held click is no reason")
        XCTAssertEqual(InputProcessor.shared.process(nativeButton(4, .otherMouseUp)), .consumed)

        // The first key binding, and the last one removed or switched off.
        bindKey(40, flags: .maskControl, to: SystemShortcut.copy.identifier)
        XCTAssertTrue(InputProcessor.shared.needsKeyEvents)
        var binding = Options.shared.buttons.binding[0]
        binding.isEnabled = false
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()
        XCTAssertFalse(InputProcessor.shared.needsKeyEvents, "switched off")
        Options.shared.buttons.binding = []
        ButtonUtils.shared.invalidateCache()
        XCTAssertFalse(InputProcessor.shared.needsKeyEvents)

        // A modifier held through a mouse button: the keys typed meanwhile must carry it.
        bind([(3, "modifierShift")])
        XCTAssertFalse(InputProcessor.shared.needsKeyEvents)
        XCTAssertEqual(InputProcessor.shared.process(nativeButton(3, .otherMouseDown)), .consumed)
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, CGEventFlags.maskShift.rawValue)
        XCTAssertTrue(InputProcessor.shared.needsKeyEvents)
        XCTAssertEqual(InputProcessor.shared.process(nativeButton(3, .otherMouseUp)), .consumed)
        XCTAssertFalse(InputProcessor.shared.needsKeyEvents)
    }

    /// A binding changed while its key is down: the key-up must still arrive, or the held
    /// action would stay held. The keyboard stays needed until then.
    func testAKeyHeldWhileItsBindingIsRemovedKeepsTheKeyboardUntilItsRelease() {
        let flags: CGEventFlags = [.maskControl, .maskAlternate]
        bindKey(3, flags: flags, to: "scrollDash")
        XCTAssertEqual(InputProcessor.shared.process(keyEvent(3, down: true, flags: flags)), .consumed)
        XCTAssertTrue(ScrollCore.shared.dashScroll)

        Options.shared.buttons.binding = []
        ButtonUtils.shared.invalidateCache()
        XCTAssertFalse(ButtonUtils.shared.hasKeyboardTriggers)
        XCTAssertTrue(InputProcessor.shared.needsKeyEvents, "the key is still down")

        // The release comes without its modifiers and without a binding: still its own.
        XCTAssertEqual(InputProcessor.shared.process(keyEvent(3, down: false, flags: [])), .consumed)
        XCTAssertFalse(ScrollCore.shared.dashScroll)
        XCTAssertFalse(InputProcessor.shared.needsKeyEvents)
    }

    /// The keys tap handles keys like the one tap did: a bound key runs its action, another
    /// key passes with the modifiers a button holds, and both directions of a held key come
    /// back the same way.
    func testTheKeysTapHandlesKeysAsTheOneTapDid() throws {
        let proxy = CGEventTapProxy(bitPattern: 1)!
        let callback = ButtonCore.shared.keyEventCallBack
        let flags: CGEventFlags = [.maskControl, .maskAlternate]
        Options.shared.buttons.binding = [
            ButtonBinding(triggerEvent: RecordedEvent(type: .keyboard, code: 3, modifiers: UInt(flags.rawValue), deviceFilter: nil),
                          systemShortcutName: "scrollDash", isEnabled: true),
            ButtonBinding(triggerEvent: RecordedEvent(type: .mouse, code: 6, modifiers: 0, deviceFilter: nil),
                          systemShortcutName: "modifierShift", isEnabled: true),
        ]
        ButtonUtils.shared.invalidateCache()

        func key(_ code: CGKeyCode, down: Bool, _ flags: CGEventFlags = []) throws -> CGEvent {
            let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down))
            event.flags = flags
            return event
        }
        // The bound key: its press and its release are both swallowed.
        XCTAssertNil(callback(proxy, .keyDown, try key(3, down: true, flags), nil))
        XCTAssertTrue(ScrollCore.shared.dashScroll)
        XCTAssertNil(callback(proxy, .keyUp, try key(3, down: false), nil))
        XCTAssertFalse(ScrollCore.shared.dashScroll)
        // Any other key: both directions pass, untouched.
        let plainDown = try key(0, down: true)
        let plainUp = try key(0, down: false)
        XCTAssertTrue(callback(proxy, .keyDown, plainDown, nil)?.takeUnretainedValue() === plainDown)
        XCTAssertTrue(callback(proxy, .keyUp, plainUp, nil)?.takeUnretainedValue() === plainUp)
        XCTAssertFalse(plainDown.flags.contains(.maskShift))
        // While a button holds Shift, both directions carry it.
        let holdShift = InputEvent(type: .mouse, code: 6, modifiers: [], phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(holdShift), .consumed)
        let shiftedDown = try key(0, down: true)
        let shiftedUp = try key(0, down: false)
        XCTAssertNotNil(callback(proxy, .keyDown, shiftedDown, nil))
        XCTAssertNotNil(callback(proxy, .keyUp, shiftedUp, nil))
        XCTAssertTrue(shiftedDown.flags.contains(.maskShift))
        XCTAssertTrue(shiftedUp.flags.contains(.maskShift))
        // A key the app posted itself passes unseen.
        let own = try key(3, down: true, flags)
        own.setIntegerValueField(.eventSourceUserData, value: ScrollioEventMarker.syntheticCustom)
        XCTAssertNotNil(callback(proxy, .keyDown, own, nil))
        XCTAssertFalse(ScrollCore.shared.dashScroll)
    }

    /// The keys tap is paused whenever the keyboard is no longer needed, and its callback
    /// then gets "disabled by user input". That must not end what the buttons hold (the same
    /// mistake as the pointer-movement tap's pause). A timeout still does.
    func testTheKeysTapsOwnPauseDoesNotEndHeldActions() throws {
        let proxy = CGEventTapProxy(bitPattern: 1)!
        let event = try XCTUnwrap(CGEvent(source: nil))
        bind([(3, "scrollDash")])
        XCTAssertEqual(InputProcessor.shared.process(nativeButton(3, .otherMouseDown)), .consumed)
        XCTAssertTrue(ScrollCore.shared.dashScroll)

        XCTAssertNotNil(ButtonCore.shared.keyEventCallBack(proxy, .tapDisabledByUserInput, event, nil))
        XCTAssertTrue(ScrollCore.shared.dashScroll)
        XCTAssertEqual(InputProcessor.shared.process(nativeButton(3, .otherMouseUp)), .consumed)

        XCTAssertEqual(InputProcessor.shared.process(nativeButton(3, .otherMouseDown)), .consumed)
        XCTAssertNotNil(ButtonCore.shared.keyEventCallBack(proxy, .tapDisabledByTimeout, event, nil))
        XCTAssertFalse(ScrollCore.shared.dashScroll, "a timeout releases everything held")
    }

    // MARK: - Held actions whose release never came

    private final class Hardware {
        var buttonsDown: Set<Int64> = []
        var keysDown: Set<UInt16> = []
        var secureInput = false

        var probe: InputProcessor.HeldInputProbe {
            return InputProcessor.HeldInputProbe(
                isMouseButtonDown: { [unowned self] in self.buttonsDown.contains($0) },
                isKeyDown: { [unowned self] in self.keysDown.contains($0) },
                isSecureInputOn: { [unowned self] in self.secureInput }
            )
        }
    }

    /// A button bound to a modifier whose release got lost kept the modifier on for every
    /// key typed afterwards, until the button was pressed again.
    func testAHeldActionWhoseButtonIsUpIsReleasedAfterTwoLooks() {
        let hardware = Hardware()
        InputProcessor.shared.setTestingHeldInputProbe(hardware.probe)
        defer { InputProcessor.shared.setTestingHeldInputProbe(nil) }
        bind([(3, "modifierShift")])

        XCTAssertFalse(InputProcessor.shared.isHeldActionTimerRunning, "nothing held, no timer")
        hardware.buttonsDown = [3]
        XCTAssertEqual(InputProcessor.shared.process(nativeButton(3, .otherMouseDown)), .consumed)
        XCTAssertTrue(InputProcessor.shared.isHeldActionTimerRunning)
        // Held for real: any number of looks changes nothing.
        for _ in 0..<5 { InputProcessor.shared.checkHeldActions() }
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, CGEventFlags.maskShift.rawValue)

        // The button is up and its release never came. One look is not enough (a real
        // release arrives within milliseconds of the button going up) ...
        hardware.buttonsDown = []
        InputProcessor.shared.checkHeldActions()
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, CGEventFlags.maskShift.rawValue)
        // ... the second releases the modifier.
        InputProcessor.shared.checkHeldActions()
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, 0)
        XCTAssertFalse(InputProcessor.shared.needsKeyEvents)
        XCTAssertFalse(InputProcessor.shared.isHeldActionTimerRunning)
        // A release that arrives after all is the swallowed press's: the app never gets an
        // up without a down. Only that one.
        XCTAssertEqual(InputProcessor.shared.process(nativeButton(3, .otherMouseUp)), .consumed)
        XCTAssertEqual(InputProcessor.shared.process(nativeButton(3, .otherMouseUp)), .passthrough)
    }

    /// A look between the button going up and its release arriving must not take the
    /// release away: the real release ends the hold as always.
    func testAReleaseThatArrivesAfterOneLookIsAnOrdinaryRelease() {
        let hardware = Hardware()
        InputProcessor.shared.setTestingHeldInputProbe(hardware.probe)
        defer { InputProcessor.shared.setTestingHeldInputProbe(nil) }
        bind([(3, "modifierShift")])
        hardware.buttonsDown = [3]
        XCTAssertEqual(InputProcessor.shared.process(nativeButton(3, .otherMouseDown)), .consumed)
        hardware.buttonsDown = []
        InputProcessor.shared.checkHeldActions()
        XCTAssertEqual(InputProcessor.shared.process(nativeButton(3, .otherMouseUp)), .consumed)
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, 0)
        // The next press starts clean: one look with the button up does not release it.
        hardware.buttonsDown = [3]
        XCTAssertEqual(InputProcessor.shared.process(nativeButton(3, .otherMouseDown)), .consumed)
        hardware.buttonsDown = []
        InputProcessor.shared.checkHeldActions()
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, CGEventFlags.maskShift.rawValue)
        XCTAssertEqual(InputProcessor.shared.process(nativeButton(3, .otherMouseUp)), .consumed)
    }

    /// A key is judged only while another app has secure keyboard entry on (only then can
    /// its key-up not arrive), and a Logitech button over HID++ never: the Mac cannot be
    /// asked about it.
    func testAHeldKeyIsOnlyJudgedWhileSecureKeyboardEntryIsOn() {
        let hardware = Hardware()
        InputProcessor.shared.setTestingHeldInputProbe(hardware.probe)
        defer { InputProcessor.shared.setTestingHeldInputProbe(nil) }
        let flags: CGEventFlags = [.maskControl, .maskAlternate]
        bindKey(3, flags: flags, to: "scrollDash")

        // Without secure keyboard entry a key is never judged, whatever its state reads.
        XCTAssertEqual(InputProcessor.shared.process(keyEvent(3, down: true, flags: flags)), .consumed)
        for _ in 0..<3 { InputProcessor.shared.checkHeldActions() }
        XCTAssertTrue(ScrollCore.shared.dashScroll)
        // A password field opens while the key is down ...
        hardware.secureInput = true
        hardware.keysDown = [3]
        for _ in 0..<3 { InputProcessor.shared.checkHeldActions() }
        XCTAssertTrue(ScrollCore.shared.dashScroll, "still down")
        // ... and the key is let go: no key-up reaches any tap.
        hardware.keysDown = []
        InputProcessor.shared.checkHeldActions()
        InputProcessor.shared.checkHeldActions()
        XCTAssertFalse(ScrollCore.shared.dashScroll)

        XCTAssertTrue(InputProcessor.hasLostItsRelease(.mouseButton(3), probe: hardware.probe))
        let idle = Hardware()
        XCTAssertFalse(InputProcessor.hasLostItsRelease(.key(3), probe: idle.probe), "secure input off")

        // A Logitech button that arrives over HID++ is not judged.
        hardware.secureInput = false
        bind([(1006, "modifierShift")])
        let logiDown = InputEvent(type: .mouse, code: 1006, modifiers: [], phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(logiDown), .consumed)
        XCTAssertFalse(InputProcessor.shared.isHeldActionTimerRunning)
        for _ in 0..<3 { InputProcessor.shared.checkHeldActions() }
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, CGEventFlags.maskShift.rawValue)
    }

}
