import XCTest
@testable import Mos_Debug

/// Gesture Navigation with a mouse that tracks the hold itself, inside the app: the two new
/// settings, which buttons Mos asks the mouse to track, how movement from the device and
/// from the pointer reach the two gesture modes without being counted twice, the pointer
/// lock, and the haptic cues. Everything runs against recording drivers; no event is posted
/// and no HID device is touched.
final class LogiGestureRoutingTests: XCTestCase {

    private enum SwipeCall: Equatable {
        case begin(DockSwipeAxis)
        case update(Double)
        case end(Double)
        case cancel
    }

    private struct HapticCall: Equatable {
        let cue: MouseGestureHapticCue
        let code: UInt16
    }

    /// The MX Master gesture button (CID 0x00C3).
    private static let gestureButton: UInt16 = 1000
    /// The mode-shift button (CID 0x00C4).
    private static let modeShiftButton: UInt16 = 1001

    private var swipeCalls: [SwipeCall] = []
    private var hapticCalls: [HapticCall] = []
    private var clock: TimeInterval = 100
    /// 937 pt + the 63 pt separator: 1000 pt of travel = one Space = progress 1.
    private var screen = InteractiveGestureScreen(width: 937, spaceCount: nil, frameDuration: 1.0 / 60.0)
    private var scheduledWork: [(delay: TimeInterval, work: () -> Void)] = []
    private var pointerAssociations: [Bool] = []
    private let pointerAnchor = CGPoint(x: 100, y: 100)

    override func setUp() {
        super.setUp()
        Options.shared.buttons.binding = []
        Options.shared.gesture = .default
        swipeCalls = []
        hapticCalls = []
        clock = 100
        screen = InteractiveGestureScreen(width: 937, spaceCount: nil, frameDuration: 1.0 / 60.0)
        scheduledWork = []
        pointerAssociations = []

        let anchor = pointerAnchor
        MouseGesturePointerLock.shared.setTestingDriver(MouseGesturePointerDriver(
            currentLocation: { anchor },
            setAssociated: { [weak self] in self?.pointerAssociations.append($0) },
            warp: { _ in }
        ))
        DockSwipeSynthesizer.shared.setTestingDriver(DockSwipeDriver(
            isAvailable: { true },
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
        InputProcessor.shared.setTestingGestureHapticPlayer { [weak self] cue, code in
            self?.hapticCalls.append(HapticCall(cue: cue, code: code))
        }
        ButtonUtils.shared.invalidateCache()
        MouseInteractionSessionController.shared.setTestingMotionTapHooks()
        MouseInteractionSessionController.shared.clearAllSessions()
        ShortcutExecutor.shared.setTestingMouseEventObserver()
        ShortcutExecutor.shared.setTestingKeyboardShortcutObserver()
        InputProcessor.shared.clearActiveBindings()
    }

    override func tearDown() {
        waitForMainQueue()
        InputProcessor.shared.clearActiveBindings()
        InputProcessor.shared.clearTestingGestureHapticPlayer()
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

    func testDefaultsKeepTodaysBehaviour() {
        XCTAssertFalse(MouseGestureSettings.default.deviceTracking, "raw XY is opt-in")
        XCTAssertTrue(MouseGestureSettings.default.hapticFeedback)
        let explicit = MouseGestureSettings(
            upAction: "", downAction: "", leftAction: "", rightAction: "", clickAction: "",
            invertHorizontal: false, freezePointer: true
        )
        XCTAssertFalse(explicit.deviceTracking)
        XCTAssertTrue(explicit.hapticFeedback)
    }

    func testDataFromAnOlderBuildDecodesToTheDefaults() throws {
        // Written by the "follow the hand" build: no device options yet.
        let json = """
        {"upAction":"missionControl","downAction":"appExpose","leftAction":"","rightAction":"moveSpaceRight",
         "clickAction":"copy","invertHorizontal":true,"freezePointer":false,"mode":"interactive","trackingSpeed":2}
        """
        let settings = try JSONDecoder().decode(MouseGestureSettings.self, from: Data(json.utf8))
        XCTAssertFalse(settings.deviceTracking)
        XCTAssertTrue(settings.hapticFeedback)
        XCTAssertEqual(settings.mode, .interactive)
        XCTAssertEqual(settings.trackingSpeed, 2)
        XCTAssertEqual(settings.clickAction, "copy")
        XCTAssertFalse(settings.freezePointer)

        let empty = try JSONDecoder().decode(MouseGestureSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, .default)
    }

    func testMalformedDeviceOptionsFallBackWithoutLosingOtherSettings() throws {
        for value in ["\"yes\"", "1", "null", "{\"a\":1}", "[true]"] {
            let json = "{\"leftAction\":\"copy\",\"mode\":\"interactive\",\"deviceTracking\":\(value),\"hapticFeedback\":\(value)}"
            let settings = try JSONDecoder().decode(MouseGestureSettings.self, from: Data(json.utf8))
            XCTAssertFalse(settings.deviceTracking, value)
            XCTAssertTrue(settings.hapticFeedback, value)
            XCTAssertEqual(settings.leftAction, "copy", value)
            XCTAssertEqual(settings.mode, .interactive, value)
        }
    }

    func testDeviceOptionsRoundTrip() throws {
        var settings = MouseGestureSettings.default
        settings.deviceTracking = true
        settings.hapticFeedback = false
        let data = try JSONEncoder().encode(settings)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["deviceTracking"] as? Bool, true)
        XCTAssertEqual(object["hapticFeedback"] as? Bool, false)
        XCTAssertEqual(try JSONDecoder().decode(MouseGestureSettings.self, from: data), settings)
    }

    // MARK: - Which buttons the mouse is asked to track

    private func binding(_ code: UInt16, _ action: String, modifiers: UInt = 0, enabled: Bool = true) -> ButtonBinding {
        let trigger = RecordedEvent(type: .mouse, code: code, modifiers: modifiers, displayComponents: ["Button"], deviceFilter: nil)
        return ButtonBinding(triggerEvent: trigger, systemShortcutName: action, isEnabled: enabled)
    }

    private var gestureAction: String { SystemShortcut.mouseGestureNavigation.identifier }

    func testNothingIsRequestedWhileTheSettingIsOff() {
        let codes = LogiUsageBootstrap.gestureTrackingCodes(
            deviceTracking: false,
            bindings: [binding(Self.gestureButton, gestureAction)],
            scrollHotkeyCodes: []
        )
        XCTAssertEqual(codes, [])
    }

    func testOnlyLogitechButtonsBoundToGestureNavigationAreRequested() {
        let codes = LogiUsageBootstrap.gestureTrackingCodes(
            deviceTracking: true,
            bindings: [
                binding(Self.gestureButton, gestureAction),
                binding(Self.modeShiftButton, SystemShortcut.missionControl.identifier),
                binding(3, gestureAction),                                  // a plain mouse button
                binding(1006, gestureAction, enabled: false),               // disabled binding
                binding(2000 + 0x01A0, gestureAction),                      // MX Master 4 haptic sense panel
            ],
            scrollHotkeyCodes: []
        )
        XCTAssertEqual(codes, [Self.gestureButton, 2000 + 0x01A0])
    }

    func testAButtonWithAnotherJobIsNotRequested() {
        // Tracking freezes the pointer for every hold of the button, so it must be all the button does.
        let command = UInt(CGEventFlags.maskCommand.rawValue)
        let shared = LogiUsageBootstrap.gestureTrackingCodes(
            deviceTracking: true,
            bindings: [
                binding(Self.gestureButton, gestureAction),
                binding(Self.gestureButton, SystemShortcut.copy.identifier, modifiers: command),
                binding(Self.modeShiftButton, gestureAction),
                binding(Self.modeShiftButton, gestureAction, modifiers: command),
            ],
            scrollHotkeyCodes: []
        )
        XCTAssertEqual(shared, [Self.modeShiftButton])

        let hotkey = LogiUsageBootstrap.gestureTrackingCodes(
            deviceTracking: true,
            bindings: [binding(Self.gestureButton, gestureAction), binding(Self.modeShiftButton, gestureAction)],
            scrollHotkeyCodes: [Self.modeShiftButton]
        )
        XCTAssertEqual(hotkey, [Self.gestureButton])
    }

    // MARK: - Discrete mode

    func testDeviceMovementRunsTheDiscreteActionWithoutPointerLockOrMotionTap() {
        configureGestureBinding(mode: .discrete)
        let executed = recordKeyboardShortcuts()

        XCTAssertEqual(InputProcessor.shared.process(buttonEvent(.down, tracked: true)), .consumed)
        XCTAssertFalse(MouseGesturePointerLock.shared.isLocked, "the mouse keeps the pointer still itself")
        XCTAssertEqual(pointerAssociations, [])
        XCTAssertFalse(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertTrue(InputProcessor.shared.hasActiveMouseGestureSessions)
        XCTAssertFalse(InputProcessor.shared.hasPointerTrackedMouseGestureSessions)

        // 39 pt of travel: not yet.
        moveOnDevice(points: -39, 0)
        waitForMainQueue()
        XCTAssertTrue(executed().isEmpty)
        moveOnDevice(points: -1, 0)
        waitForMainQueue()

        let expected = resolvedShortcut(SystemShortcut.moveSpaceLeft)
        XCTAssertEqual(executed().count, 1)
        XCTAssertEqual(executed().first?.0, expected.code)

        // One action per hold, and the release is no click.
        moveOnDevice(points: -200, 0)
        XCTAssertEqual(InputProcessor.shared.process(buttonEvent(.up)), .consumed)
        waitForMainQueue()
        XCTAssertEqual(executed().count, 1)
        XCTAssertEqual(pointerAssociations, [])
        XCTAssertFalse(InputProcessor.shared.hasActiveMouseGestureSessions)
    }

    func testSensorCountsAreScaledByTheOneConstant() {
        XCTAssertEqual(MouseGestureDeviceTracking.pointsPerCount, 0.5)
        configureGestureBinding(mode: .discrete)
        let executed = recordKeyboardShortcuts()
        let threshold = Int((MouseGestureRecognizer.defaultActivationDistance / MouseGestureDeviceTracking.pointsPerCount).rounded(.up))

        XCTAssertEqual(InputProcessor.shared.process(buttonEvent(.down, tracked: true)), .consumed)
        InputProcessor.shared.handleDeviceGestureMovement(code: Self.gestureButton, countsX: 0, countsY: threshold - 1)
        waitForMainQueue()
        XCTAssertTrue(executed().isEmpty)
        // +y is towards the user: the Down action, like a CGEvent delta.
        InputProcessor.shared.handleDeviceGestureMovement(code: Self.gestureButton, countsX: 0, countsY: 1)
        waitForMainQueue()

        let expected = resolvedShortcut(SystemShortcut.appExpose)
        XCTAssertEqual(executed().count, 1)
        XCTAssertEqual(executed().first?.0, expected.code)
    }

    func testPointerMovementIsIgnoredForADeviceTrackedHold() {
        configureGestureBinding(mode: .discrete)
        let executed = recordKeyboardShortcuts()

        XCTAssertEqual(InputProcessor.shared.process(buttonEvent(.down, tracked: true)), .consumed)
        // Another pointing device moves the pointer meanwhile.
        InputProcessor.shared.handleMouseGestureMovement(deltaX: 300, deltaY: 0)
        let motion = makeMouseMoveEvent(deltaX: 300, deltaY: 0, location: pointerAnchor)
        MouseInteractionSessionController.shared.handleMotionTapEventForTests(motion)
        waitForMainQueue()
        XCTAssertTrue(executed().isEmpty)

        // The hold still decides from the device's movement alone: 300 pt right were not counted.
        moveOnDevice(points: -40, 0)
        waitForMainQueue()
        XCTAssertEqual(executed().first?.0, resolvedShortcut(SystemShortcut.moveSpaceLeft).code)
    }

    func testDeviceMovementIsIgnoredForAPointerTrackedHold() {
        configureGestureBinding(mode: .discrete)
        let executed = recordKeyboardShortcuts()

        // Not armed (setting off, no capability, no acknowledgement): today's path.
        XCTAssertEqual(InputProcessor.shared.process(buttonEvent(.down, tracked: false)), .consumed)
        XCTAssertTrue(MouseGesturePointerLock.shared.isLocked)
        XCTAssertTrue(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertTrue(InputProcessor.shared.hasPointerTrackedMouseGestureSessions)

        moveOnDevice(points: 300, 0)
        waitForMainQueue()
        XCTAssertTrue(executed().isEmpty)

        InputProcessor.shared.handleMouseGestureMovement(deltaX: -45, deltaY: 0)
        XCTAssertEqual(InputProcessor.shared.process(buttonEvent(.up)), .consumed)
        waitForMainQueue()
        XCTAssertEqual(executed().count, 1)
        XCTAssertEqual(executed().first?.0, resolvedShortcut(SystemShortcut.moveSpaceLeft).code)
        XCTAssertFalse(MouseGesturePointerLock.shared.isLocked)
        XCTAssertEqual(pointerAssociations, [false, true])
    }

    func testDeviceMovementForAButtonThatIsNotHeldDoesNothing() {
        configureGestureBinding(mode: .discrete)
        let executed = recordKeyboardShortcuts()
        moveOnDevice(points: -300, 0)
        XCTAssertEqual(InputProcessor.shared.process(buttonEvent(.down, tracked: true)), .consumed)
        InputProcessor.shared.handleDeviceGestureMovement(code: Self.modeShiftButton, countsX: -600, countsY: 0)
        waitForMainQueue()
        XCTAssertTrue(executed().isEmpty)
    }

    func testAClickOnADeviceTrackedHoldStillRunsTheClickAction() {
        configureGestureBinding(mode: .discrete)
        Options.shared.gesture.clickAction = SystemShortcut.copy.identifier
        let executed = recordKeyboardShortcuts()

        XCTAssertEqual(InputProcessor.shared.process(buttonEvent(.down, tracked: true)), .consumed)
        moveOnDevice(points: 3, -2)
        XCTAssertEqual(InputProcessor.shared.process(buttonEvent(.up)), .consumed)
        waitForMainQueue()

        XCTAssertEqual(executed().count, 1)
        XCTAssertEqual(executed().first?.0, resolvedShortcut(SystemShortcut.copy).code)
    }

    func testTwoHoldsEachUseTheirOwnMovementSource() {
        configureGestureBinding(mode: .discrete, codes: [Self.gestureButton, 3])
        Options.shared.gesture.leftAction = SystemShortcut.copy.identifier
        Options.shared.gesture.rightAction = SystemShortcut.paste.identifier
        let executed = recordKeyboardShortcuts()

        XCTAssertEqual(InputProcessor.shared.process(buttonEvent(.down, tracked: true)), .consumed)
        XCTAssertFalse(MouseGesturePointerLock.shared.isLocked)
        XCTAssertEqual(InputProcessor.shared.process(buttonEvent(.down, code: 3)), .consumed)
        XCTAssertTrue(MouseGesturePointerLock.shared.isLocked)
        XCTAssertTrue(MouseInteractionSessionController.shared.isMotionTapRunning)

        // The pointer moves right, the tracked mouse moves left: one action each.
        InputProcessor.shared.handleMouseGestureMovement(deltaX: 45, deltaY: 0)
        moveOnDevice(points: -45, 0)
        waitForMainQueue()
        XCTAssertEqual(
            Set(executed().map { $0.0 }),
            [resolvedShortcut(SystemShortcut.copy).code, resolvedShortcut(SystemShortcut.paste).code]
        )
        XCTAssertEqual(executed().count, 2)

        // The pointer is released with the hold that froze it, not with the tracked one.
        XCTAssertEqual(InputProcessor.shared.process(buttonEvent(.up, code: 3)), .consumed)
        XCTAssertFalse(MouseGesturePointerLock.shared.isLocked)
        XCTAssertFalse(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertTrue(InputProcessor.shared.hasActiveMouseGestureSessions)
        XCTAssertEqual(InputProcessor.shared.process(buttonEvent(.up)), .consumed)
    }

    func testClearActiveBindingsEndsADeviceTrackedHold() {
        configureGestureBinding(mode: .discrete)
        let executed = recordKeyboardShortcuts()
        XCTAssertEqual(InputProcessor.shared.process(buttonEvent(.down, tracked: true)), .consumed)

        InputProcessor.shared.clearActiveBindings()

        XCTAssertFalse(InputProcessor.shared.hasActiveMouseGestureSessions)
        XCTAssertFalse(InputProcessor.shared.hasPointerTrackedMouseGestureSessions)
        moveOnDevice(points: -300, 0)
        XCTAssertEqual(InputProcessor.shared.process(buttonEvent(.up)), .passthrough)
        waitForMainQueue()
        XCTAssertTrue(executed().isEmpty)
    }

    // MARK: - Follow the hand

    func testDeviceMovementDrivesTheSwipe() {
        configureGestureBinding(mode: .interactive)

        XCTAssertEqual(InputProcessor.shared.process(buttonEvent(.down, tracked: true)), .consumed)
        XCTAssertFalse(MouseGesturePointerLock.shared.isLocked)
        XCTAssertFalse(MouseInteractionSessionController.shared.isMotionTapRunning)

        // Samples only add up until the next frame, like motion tap events.
        moveOnDevice(points: -60, 0)
        moveOnDevice(points: -40, 0)
        XCTAssertEqual(swipeCalls, [])
        XCTAssertEqual(scheduledWork.count, 1)
        runScheduledWork()
        assertSwipeCalls([.begin(.horizontal), .update(0.1)])

        advanceFrame()
        moveOnDevice(points: -100, 2)
        runScheduledWork()
        assertSwipeCalls([.begin(.horizontal), .update(0.1), .update(0.2)])

        XCTAssertEqual(InputProcessor.shared.process(buttonEvent(.up)), .consumed)
        waitForMainQueue()
        XCTAssertEqual(swipeCalls.count, 4)
        guard case .end? = swipeCalls.last else { return XCTFail("expected end, got \(swipeCalls)") }
        XCTAssertEqual(pointerAssociations, [])
    }

    func testPointerMovementDoesNotMoveADeviceTrackedSwipe() {
        configureGestureBinding(mode: .interactive)

        XCTAssertEqual(InputProcessor.shared.process(buttonEvent(.down, tracked: true)), .consumed)
        moveOnDevice(points: -100, 0)
        runScheduledWork()
        advanceFrame()

        InputProcessor.shared.handleMouseGestureMovement(deltaX: -500, deltaY: 0, location: pointerAnchor)
        let motion = makeMouseMoveEvent(deltaX: -500, deltaY: 0, location: pointerAnchor)
        MouseInteractionSessionController.shared.handleMotionTapEventForTests(motion)
        XCTAssertTrue(scheduledWork.isEmpty, "nothing was accumulated")
        runScheduledWork()

        assertSwipeCalls([.begin(.horizontal), .update(0.1)])
    }

    func testDeviceMovementDoesNotMoveAPointerTrackedSwipe() {
        configureGestureBinding(mode: .interactive)

        XCTAssertEqual(InputProcessor.shared.process(buttonEvent(.down, tracked: false)), .consumed)
        XCTAssertTrue(MouseGesturePointerLock.shared.isLocked)
        InputProcessor.shared.handleMouseGestureMovement(deltaX: -100, deltaY: 0)
        runScheduledWork()
        advanceFrame()

        moveOnDevice(points: -500, 0)
        XCTAssertTrue(scheduledWork.isEmpty)
        runScheduledWork()

        assertSwipeCalls([.begin(.horizontal), .update(0.1)])
    }

    func testDeviceTrackedVerticalMovementRunsTheDiscreteActionInFollowMode() {
        configureGestureBinding(mode: .interactive)
        Options.shared.gesture.upAction = SystemShortcut.copy.identifier
        let executed = recordKeyboardShortcuts()

        XCTAssertEqual(InputProcessor.shared.process(buttonEvent(.down, tracked: true)), .consumed)
        moveOnDevice(points: 0, -45)
        runScheduledWork()
        waitForMainQueue()

        XCTAssertEqual(executed().count, 1)
        XCTAssertEqual(executed().first?.0, resolvedShortcut(SystemShortcut.copy).code)
        XCTAssertEqual(swipeCalls, [])
    }

    // MARK: - Bridge

    func testBridgeRoutesButtonAndMovementIntoTheGesture() {
        configureGestureBinding(mode: .discrete)
        let executed = recordKeyboardShortcuts()
        let bridge = LogiIntegrationBridge.shared

        XCTAssertEqual(bridge.dispatchLogiButtonEvent(buttonEvent(.down, tracked: true)), .consumed)
        XCTAssertFalse(MouseGesturePointerLock.shared.isLocked)
        let counts = Int(-40 / MouseGestureDeviceTracking.pointsPerCount)
        bridge.handleLogiGestureMovement(code: Self.gestureButton, deltaX: counts, deltaY: 0)
        XCTAssertEqual(bridge.dispatchLogiButtonEvent(buttonEvent(.up)), .consumed)
        waitForMainQueue()

        XCTAssertEqual(executed().count, 1)
        XCTAssertEqual(executed().first?.0, resolvedShortcut(SystemShortcut.moveSpaceLeft).code)
    }

    func testOnlyTheButtonDownCarriesTheTrackingMark() {
        XCTAssertTrue(buttonEvent(.down, tracked: true).tracksMovementOnDevice)
        XCTAssertFalse(buttonEvent(.up).tracksMovementOnDevice)
        let plain = InputEvent(type: .mouse, code: 3, modifiers: [], phase: .down, source: .hidPP, device: nil)
        XCTAssertFalse(plain.tracksMovementOnDevice, "unmarked unless the Logi session says so")
        let cgEvent = CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown, mouseCursorPosition: .zero, mouseButton: .center)!
        XCTAssertFalse(InputEvent(fromCGEvent: cgEvent).tracksMovementOnDevice)
    }

    // MARK: - Haptic cues

    func testDiscreteActionGivesOneLightPulse() {
        configureGestureBinding(mode: .discrete)

        XCTAssertEqual(InputProcessor.shared.process(buttonEvent(.down, tracked: true)), .consumed)
        moveOnDevice(points: -20, 0)
        waitForMainQueue()
        XCTAssertEqual(hapticCalls, [], "nothing before the gesture locks in")
        moveOnDevice(points: -30, 0)
        moveOnDevice(points: -300, 0)
        XCTAssertEqual(InputProcessor.shared.process(buttonEvent(.up)), .consumed)
        waitForMainQueue()

        XCTAssertEqual(hapticCalls, [HapticCall(cue: .lockIn, code: Self.gestureButton)])
    }

    func testPointerTrackedLogitechButtonAlsoGetsThePulse() {
        // The cue belongs to the button's mouse, whatever the movement source.
        configureGestureBinding(mode: .discrete)

        XCTAssertEqual(InputProcessor.shared.process(buttonEvent(.down, tracked: false)), .consumed)
        InputProcessor.shared.handleMouseGestureMovement(deltaX: 0, deltaY: 45)
        XCTAssertEqual(InputProcessor.shared.process(buttonEvent(.up)), .consumed)
        waitForMainQueue()

        XCTAssertEqual(hapticCalls, [HapticCall(cue: .lockIn, code: Self.gestureButton)])
    }

    func testNoPulseWhenHapticFeedbackIsOff() {
        configureGestureBinding(mode: .discrete)
        Options.shared.gesture.hapticFeedback = false

        XCTAssertEqual(InputProcessor.shared.process(buttonEvent(.down, tracked: true)), .consumed)
        moveOnDevice(points: -60, 0)
        XCTAssertEqual(InputProcessor.shared.process(buttonEvent(.up)), .consumed)
        waitForMainQueue()

        XCTAssertEqual(hapticCalls, [])
    }

    func testNoPulseForAButtonThatDoesNotComeFromAMouseOverHIDPP() {
        configureGestureBinding(mode: .discrete, codes: [3])
        let down = CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown, mouseCursorPosition: .zero, mouseButton: .center)!
        down.setIntegerValueField(.mouseEventButtonNumber, value: 3)
        let up = CGEvent(mouseEventSource: nil, mouseType: .otherMouseUp, mouseCursorPosition: .zero, mouseButton: .center)!
        up.setIntegerValueField(.mouseEventButtonNumber, value: 3)

        XCTAssertEqual(InputProcessor.shared.process(InputEvent(fromCGEvent: down)), .consumed)
        InputProcessor.shared.handleMouseGestureMovement(deltaX: -60, deltaY: 0)
        XCTAssertEqual(InputProcessor.shared.process(InputEvent(fromCGEvent: up)), .consumed)
        waitForMainQueue()

        XCTAssertEqual(hapticCalls, [])
    }

    func testNoPulseWhenTheDirectionHasNoAction() {
        configureGestureBinding(mode: .discrete)
        Options.shared.gesture.leftAction = ""

        XCTAssertEqual(InputProcessor.shared.process(buttonEvent(.down, tracked: true)), .consumed)
        moveOnDevice(points: -60, 0)
        XCTAssertEqual(InputProcessor.shared.process(buttonEvent(.up)), .consumed)
        waitForMainQueue()

        XCTAssertEqual(hapticCalls, [])
    }

    func testNoPulseForAPlainClick() {
        configureGestureBinding(mode: .discrete)

        XCTAssertEqual(InputProcessor.shared.process(buttonEvent(.down, tracked: true)), .consumed)
        moveOnDevice(points: 2, 1)
        XCTAssertEqual(InputProcessor.shared.process(buttonEvent(.up)), .consumed)
        waitForMainQueue()

        XCTAssertEqual(hapticCalls, [])
    }

    func testSwipeBeginGivesALightPulseAndAReleasePastHalfwayAStrongerOne() {
        configureGestureBinding(mode: .interactive)

        XCTAssertEqual(InputProcessor.shared.process(buttonEvent(.down, tracked: true)), .consumed)
        moveOnDevice(points: -600, 0)
        runScheduledWork()
        waitForMainQueue()
        XCTAssertEqual(hapticCalls, [HapticCall(cue: .lockIn, code: Self.gestureButton)])

        // The hand rests, then lets go: no speed, but the desktop is 60 % of the way.
        clock += 1
        XCTAssertEqual(InputProcessor.shared.process(buttonEvent(.up)), .consumed)
        waitForMainQueue()
        waitForMainQueue()

        assertSwipeCalls([.begin(.horizontal), .update(0.6), .end(0)])
        XCTAssertEqual(hapticCalls, [
            HapticCall(cue: .lockIn, code: Self.gestureButton),
            HapticCall(cue: .commit, code: Self.gestureButton),
        ])
    }

    func testAFlickGivesTheCommitPulseAndASlowShortSwipeDoesNot() {
        configureGestureBinding(mode: .interactive)

        // A flick: 10 % of the way, released while still moving fast.
        XCTAssertEqual(InputProcessor.shared.process(buttonEvent(.down, tracked: true)), .consumed)
        moveOnDevice(points: -100, 0)
        runScheduledWork()
        clock += 0.01
        XCTAssertEqual(InputProcessor.shared.process(buttonEvent(.up)), .consumed)
        waitForMainQueue()
        waitForMainQueue()
        XCTAssertEqual(hapticCalls.map { $0.cue }, [.lockIn, .commit])

        // The same distance, then a pause before the release: macOS will go back.
        hapticCalls = []
        clock += 5
        XCTAssertEqual(InputProcessor.shared.process(buttonEvent(.down, tracked: true)), .consumed)
        moveOnDevice(points: -100, 0)
        runScheduledWork()
        clock += 1
        XCTAssertEqual(InputProcessor.shared.process(buttonEvent(.up)), .consumed)
        waitForMainQueue()
        waitForMainQueue()
        XCTAssertEqual(hapticCalls.map { $0.cue }, [.lockIn])
    }

    func testACancelledSwipeGivesNoCommitPulse() {
        configureGestureBinding(mode: .interactive)

        XCTAssertEqual(InputProcessor.shared.process(buttonEvent(.down, tracked: true)), .consumed)
        moveOnDevice(points: -700, 0)
        runScheduledWork()
        clock += 0.2
        moveOnDevice(points: 60, 0)
        runScheduledWork()
        clock += 0.01
        XCTAssertEqual(InputProcessor.shared.process(buttonEvent(.up)), .consumed)
        waitForMainQueue()
        waitForMainQueue()

        XCTAssertEqual(swipeCalls.last, .cancel)
        XCTAssertEqual(hapticCalls.map { $0.cue }, [.lockIn], "moving back cancels, however far the desktop was")
    }

    func testVerticalActionInFollowModeGivesTheLightPulse() {
        configureGestureBinding(mode: .interactive)

        XCTAssertEqual(InputProcessor.shared.process(buttonEvent(.down, tracked: true)), .consumed)
        moveOnDevice(points: 0, 45)
        runScheduledWork()
        XCTAssertEqual(InputProcessor.shared.process(buttonEvent(.up)), .consumed)
        waitForMainQueue()

        XCTAssertEqual(hapticCalls, [HapticCall(cue: .lockIn, code: Self.gestureButton)])
    }

    func testSwitchPredictionRule() {
        func session(progressPoints: CGFloat, spaceCount: Int? = nil) -> InteractiveGestureSession {
            var session = InteractiveGestureSession(
                configuration: InteractiveGestureSession.Configuration(
                    progressPerPoint: DockSwipeGeometry.progressPerPoint(screenWidth: 937, spaceCount: spaceCount, trackingSpeed: 1),
                    maximumProgress: DockSwipeGeometry.progressPerSpace(spaceCount: spaceCount),
                    invertHorizontal: false
                ),
                startTime: 0
            )
            _ = session.move(deltaX: -progressPoints, deltaY: 0, at: 0.1)
            return session
        }
        XCTAssertEqual(InteractiveGestureSession.switchProgressShare, 0.5)
        XCTAssertEqual(InteractiveGestureSession.switchSpacesPerSecond, 1)

        // Halfway or further: yes, even at rest.
        XCTAssertTrue(session(progressPoints: 500).isExpectedToSwitch(releaseVelocity: 0))
        XCTAssertFalse(session(progressPoints: 490).isExpectedToSwitch(releaseVelocity: 0))
        // Short of halfway: only when still moving at one Space per second or more.
        XCTAssertTrue(session(progressPoints: 100).isExpectedToSwitch(releaseVelocity: 1))
        XCTAssertFalse(session(progressPoints: 100).isExpectedToSwitch(releaseVelocity: 0.9))
        // Towards the previous Space the signs flip together.
        XCTAssertTrue(session(progressPoints: -100).isExpectedToSwitch(releaseVelocity: -1.5))
        XCTAssertFalse(session(progressPoints: -100).isExpectedToSwitch(releaseVelocity: 1.5))
        // With three Spaces one Space is 1.5 progress: 0.6 is short of halfway, 1.5 / s is one Space per second.
        XCTAssertFalse(session(progressPoints: 400, spaceCount: 3).isExpectedToSwitch(releaseVelocity: 1.4))
        XCTAssertTrue(session(progressPoints: 400, spaceCount: 3).isExpectedToSwitch(releaseVelocity: 1.5))
        // A swipe that never left the origin switches nothing.
        XCTAssertFalse(session(progressPoints: 0).isExpectedToSwitch(releaseVelocity: 9))
    }

    func testTheDefaultHapticPlayerTouchesNoDeviceWithoutASession() {
        // What production installs: with no Logitech session in the test process it must be inert.
        InputProcessor.shared.clearTestingGestureHapticPlayer()
        configureGestureBinding(mode: .discrete)

        XCTAssertEqual(InputProcessor.shared.process(buttonEvent(.down, tracked: true)), .consumed)
        moveOnDevice(points: -60, 0)
        XCTAssertEqual(InputProcessor.shared.process(buttonEvent(.up)), .consumed)
        waitForMainQueue()

        XCTAssertFalse(LogiCenter.shared.supportsGestureHaptics())
        XCTAssertFalse(LogiCenter.shared.supportsGestureDeviceTracking())
    }

    // MARK: - Helpers

    private func configureGestureBinding(mode: MouseGestureMode, codes: [UInt16] = [LogiGestureRoutingTests.gestureButton]) {
        Options.shared.buttons.binding = codes.map { binding($0, gestureAction) }
        Options.shared.gesture.mode = mode
        ButtonUtils.shared.invalidateCache()
    }

    /// A Logitech button event as the device session dispatches it.
    private func buttonEvent(
        _ phase: InputPhase,
        code: UInt16 = LogiGestureRoutingTests.gestureButton,
        tracked: Bool = false
    ) -> InputEvent {
        return InputEvent(
            type: .mouse, code: code, modifiers: [], phase: phase, source: .hidPP, device: nil,
            tracksMovementOnDevice: tracked
        )
    }

    /// Movement the mouse reports for the gesture button, given in points of gesture travel.
    private func moveOnDevice(points x: CGFloat, _ y: CGFloat) {
        InputProcessor.shared.handleDeviceGestureMovement(
            code: Self.gestureButton,
            countsX: Int((x / MouseGestureDeviceTracking.pointsPerCount).rounded()),
            countsY: Int((y / MouseGestureDeviceTracking.pointsPerCount).rounded())
        )
    }

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

    private func runScheduledWork() {
        let work = scheduledWork
        scheduledWork = []
        work.forEach { $0.work() }
    }

    private func advanceFrame() {
        clock += screen.frameDuration
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
}
