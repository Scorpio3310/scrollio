import XCTest
@testable import Scrollio_Debug

/// "Follow the hand" end to end inside Scrollio: settings, the InputProcessor wiring with a
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

    // MARK: - Settings: "Up and Down follow the hand too"

    /// The names of the gesture entry as 1.1.1 writes it.
    private static let entryNamesFromBefore: Set<String> = [
        "upAction", "downAction", "leftAction", "rightAction", "clickAction",
        "invertHorizontal", "freezePointer", "mode", "trackingSpeed", "deviceTracking", "hapticFeedback",
    ]

    private func storedObject(of settings: MouseGestureSettings) throws -> [String: Any] {
        let data = try JSONEncoder().encode(settings)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// What 1.1.1 reads of a gesture entry: its decoder's names and fallbacks, kept here as
    /// they were (`MouseGestureSettings.init(from:)` of v1.1.1), so that a newer entry can be
    /// shown to read there as its own.
    private struct EntryAsVersion111Reads: Decodable, Equatable {
        var upAction: String
        var downAction: String
        var invertHorizontal: Bool
        var freezePointer: Bool
        var mode: String
        var trackingSpeed: Double
        var deviceTracking: Bool
        var hapticFeedback: Bool

        private enum CodingKeys: String, CodingKey {
            case upAction, downAction, invertHorizontal, freezePointer, mode, trackingSpeed, deviceTracking, hapticFeedback
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            upAction = try c.decodeIfPresent(String.self, forKey: .upAction) ?? "missionControl"
            downAction = try c.decodeIfPresent(String.self, forKey: .downAction) ?? "appExpose"
            invertHorizontal = try c.decodeIfPresent(Bool.self, forKey: .invertHorizontal) ?? false
            freezePointer = try c.decodeIfPresent(Bool.self, forKey: .freezePointer) ?? true
            let storedMode = (try? c.decodeIfPresent(String.self, forKey: .mode)) ?? nil
            mode = storedMode.flatMap { ["discrete", "interactive"].contains($0) ? $0 : nil } ?? "discrete"
            trackingSpeed = ((try? c.decodeIfPresent(Double.self, forKey: .trackingSpeed)) ?? nil) ?? 1
            deviceTracking = ((try? c.decodeIfPresent(Bool.self, forKey: .deviceTracking)) ?? nil) ?? false
            hapticFeedback = ((try? c.decodeIfPresent(Bool.self, forKey: .hapticFeedback)) ?? nil) ?? true
        }
    }

    func testTheDefaultsHaveTheFollowSwitchOff() {
        XCTAssertFalse(MouseGestureSettings.default.actionsFollowHand)
        XCTAssertFalse(MouseGestureSettings.default.actionsFollowNow)
        XCTAssertEqual(MouseGestureSettings.default.mode, .discrete)
        XCTAssertFalse(
            MouseGestureSettings(
                upAction: "", downAction: "", leftAction: "", rightAction: "", clickAction: "",
                invertHorizontal: false, freezePointer: false, mode: .interactive
            ).actionsFollowHand,
            "an initialiser that does not name it leaves it off"
        )
    }

    /// The update changes nothing for anybody: an entry from 1.1.1 with "Follow the hand" on
    /// reads with the switch off and every other value as stored, and is written with the
    /// same eleven names.
    func testAnEntryFromBeforeHasTheFollowSwitchOffAndIsWrittenAsBefore() throws {
        let json = """
        {"upAction":"missionControl","downAction":"appExpose","leftAction":"navigateBack","rightAction":"navigateForward",
         "clickAction":"showDesktop","invertHorizontal":true,"freezePointer":false,"mode":"interactive",
         "trackingSpeed":1.75,"deviceTracking":true,"hapticFeedback":false}
        """
        let settings = try JSONDecoder().decode(MouseGestureSettings.self, from: Data(json.utf8))
        XCTAssertFalse(settings.actionsFollowHand)
        XCTAssertFalse(settings.actionsFollowNow)
        XCTAssertEqual(settings.mode, .interactive)
        XCTAssertEqual(settings.trackingSpeed, 1.75)
        XCTAssertEqual(settings.leftAction, "navigateBack")
        XCTAssertEqual(settings.clickAction, "showDesktop")
        XCTAssertTrue(settings.invertHorizontal)
        XCTAssertFalse(settings.freezePointer)
        XCTAssertTrue(settings.deviceTracking)
        XCTAssertFalse(settings.hapticFeedback)

        let written = try storedObject(of: settings)
        XCTAssertEqual(Set(written.keys), Self.entryNamesFromBefore, "written as before")
        let before = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? NSDictionary)
        XCTAssertEqual(written as NSDictionary, before, "and with the same values")
    }

    /// One JSON boolean, "actionsFollowHand", written only while the switch is on.
    func testTheFollowSwitchRoundTripsAndIsWrittenOnlyWhileOn() throws {
        var settings = MouseGestureSettings.default
        settings.mode = .interactive
        settings.actionsFollowHand = true
        XCTAssertTrue(settings.actionsFollowNow)
        let on = try storedObject(of: settings)
        XCTAssertEqual(Set(on.keys), Self.entryNamesFromBefore.union(["actionsFollowHand"]))
        let stored = try XCTUnwrap(on["actionsFollowHand"] as? NSNumber)
        XCTAssertEqual(CFGetTypeID(stored), CFBooleanGetTypeID(), "a JSON boolean")
        XCTAssertTrue(stored.boolValue)
        XCTAssertEqual(try JSONDecoder().decode(MouseGestureSettings.self, from: try JSONEncoder().encode(settings)), settings)

        settings.actionsFollowHand = false
        XCTAssertEqual(Set(try storedObject(of: settings).keys), Self.entryNamesFromBefore, "off: the name is not written")
        XCTAssertEqual(try JSONDecoder().decode(MouseGestureSettings.self, from: try JSONEncoder().encode(settings)), settings)

        // A stored "false" (another program's file) is off like a missing name.
        let explicit = try JSONDecoder().decode(
            MouseGestureSettings.self, from: Data(#"{"mode":"interactive","actionsFollowHand":false}"#.utf8)
        )
        XCTAssertFalse(explicit.actionsFollowHand)
        XCTAssertEqual(explicit.mode, .interactive)
        XCTAssertEqual(Set(try storedObject(of: explicit).keys), Self.entryNamesFromBefore)

        // The switch is kept while the mode is "One action per hold", where it is not used.
        var discrete = MouseGestureSettings.default
        discrete.actionsFollowHand = true
        XCTAssertFalse(discrete.actionsFollowNow, "only used in \"Follow the hand\"")
        let back = try JSONDecoder().decode(MouseGestureSettings.self, from: try JSONEncoder().encode(discrete))
        XCTAssertTrue(back.actionsFollowHand)
        XCTAssertEqual(back.mode, .discrete)
    }

    func testAFollowSwitchThatIsNoBooleanIsOffAndTakesNothingWithIt() throws {
        for value in ["\"yes\"", "\"true\"", "1", "0.5", "null", "{}", "[]", "[true]"] {
            let json = "{\"upAction\":\"copy\",\"invertHorizontal\":true,\"mode\":\"interactive\",\"trackingSpeed\":2,"
                + "\"actionsFollowHand\":\(value)}"
            let settings = try JSONDecoder().decode(MouseGestureSettings.self, from: Data(json.utf8))
            XCTAssertFalse(settings.actionsFollowHand, "switch \(value)")
            XCTAssertEqual(settings.mode, .interactive, "switch \(value)")
            XCTAssertEqual(settings.upAction, "copy", "switch \(value)")
            XCTAssertTrue(settings.invertHorizontal, "switch \(value)")
            XCTAssertEqual(settings.trackingSpeed, 2, "switch \(value)")
        }
    }

    /// An older version reads a newer entry as its own, whatever the switch says: the mode
    /// is still "interactive", the actions keep their names, nothing else differs. (It
    /// ignores the name it does not know; the switch is gone once it writes the entry.)
    func testTheFollowSwitchNeverChangesWhatAnOlderVersionReads() throws {
        var settings = MouseGestureSettings.default
        settings.mode = .interactive
        settings.trackingSpeed = 2.5
        settings.upAction = SystemShortcut.showDesktop.identifier
        let off = try JSONEncoder().encode(settings)
        settings.actionsFollowHand = true
        let on = try JSONEncoder().encode(settings)

        let readOff = try JSONDecoder().decode(EntryAsVersion111Reads.self, from: off)
        let readOn = try JSONDecoder().decode(EntryAsVersion111Reads.self, from: on)
        XCTAssertEqual(readOn, readOff)
        XCTAssertEqual(readOn.mode, "interactive")
        XCTAssertEqual(readOn.trackingSpeed, 2.5)
        XCTAssertEqual(readOn.upAction, "showDesktop")
        XCTAssertEqual(readOn.downAction, "appExpose")

        var withoutTheSwitch = try storedObject(of: settings)
        withoutTheSwitch.removeValue(forKey: "actionsFollowHand")
        settings.actionsFollowHand = false
        XCTAssertEqual(withoutTheSwitch as NSDictionary, try storedObject(of: settings) as NSDictionary)
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

    // MARK: - Up and Down follow the hand too
    //
    // The hold with the switch "Up and Down follow the hand too" on: a direction whose
    // action shows a view of the Dock drives that view's motion with the hand instead of
    // running once. The swipe driver records, the Dock is never asked for real, and what
    // follows on "this Mac" is a value the test makes (never the Mac the tests run on).

    /// What reached the Dock, or was about to, in order: the swipe's calls, the settling of
    /// the swipe before an instant toggle, the toggle by name, a key.
    private enum DockVoice: Equatable {
        case swipe(SwipeCall)
        case settle
        case toggle(DockMode)
        case key(CGKeyCode)

        var isSwipe: Bool {
            if case .swipe = self { return true }
            return false
        }
    }

    private var dockVoices: [DockVoice] = []
    /// The voices that are no swipe call: what a hold asked of the Dock in one go.
    private var instantVoices: [DockVoice] { dockVoices.filter { !$0.isSwipe } }
    private var gestureLog: [String] = []
    private var hapticCues: [MouseGestureHapticCue] = []
    /// How often a hold asked what follows on this Mac.
    private var availabilityQuestions = 0

    /// A Mac on which Mission Control and Show Desktop follow: macOS 27, an ordinary build.
    private func mac(
        swipe: Bool = true, post: Bool = true, major: Int = 27, switches: DockGestureSwitches = .allOn, apps: Bool = false
    ) -> DockFollowAvailability {
        return DockFollowAvailability(
            swipeIsAvailable: swipe, canPostEvents: post, majorVersion: major, switches: switches, appsMayFollow: apps
        )
    }

    /// "Follow the hand" on the screen of a Mac made up here, with recorders for everything
    /// a hold can do to the Dock. The screen is 1000 pt high, so 400 pt of travel are the
    /// whole of Mission Control or Show Desktop at Swipe speed 1, and 300 pt the whole of Apps.
    private func configureFollowing(
        up: String = "missionControl", down: String = "appExpose", on availability: DockFollowAvailability? = nil,
        follow: Bool = true, mode: MouseGestureMode = .interactive
    ) {
        configureGestureBinding(mode: mode)
        Options.shared.gesture.actionsFollowHand = follow
        Options.shared.gesture.upAction = up
        Options.shared.gesture.downAction = down
        screen.height = 1000
        dockVoices = []
        gestureLog = []
        hapticCues = []
        availabilityQuestions = 0

        DockSwipeSynthesizer.shared.setTestingDriver(DockSwipeDriver(
            isAvailable: { [weak self] in self?.isSynthesizerAvailable ?? false },
            begin: { [weak self] in self?.record(.begin($0)) },
            update: { [weak self] in self?.record(.update($0)) },
            end: { [weak self] in self?.record(.end($0)) },
            cancel: { [weak self] in self?.record(.cancel) },
            settle: { [weak self] in self?.dockVoices.append(.settle) }
        ))
        let answer = availability ?? mac()
        InputProcessor.shared.setTestingFollowAvailability { [weak self] in
            self?.availabilityQuestions += 1
            return answer
        }
        InputProcessor.shared.setTestingMouseGestureLog { [weak self] in self?.gestureLog.append($0) }
        InputProcessor.shared.setTestingGestureHapticPlayer { [weak self] cue, _ in self?.hapticCues.append(cue) }
        let toggleBefore = ShortcutExecutor.shared.toggleDockMode
        ShortcutExecutor.shared.toggleDockMode = { [weak self] mode in
            self?.dockVoices.append(.toggle(mode))
            return true
        }
        ShortcutExecutor.shared.setTestingKeyboardShortcutObserver { [weak self] code, _, _ in
            self?.dockVoices.append(.key(code))
        }
        addTeardownBlock { [weak self] in
            // What is still queued runs while the recorders are in place.
            self?.drainMainQueue()
            InputProcessor.shared.clearActiveBindings()
            InputProcessor.shared.setTestingFollowAvailability(nil)
            InputProcessor.shared.setTestingMouseGestureLog(nil)
            InputProcessor.shared.clearTestingGestureHapticPlayer()
            ShortcutExecutor.shared.toggleDockMode = toggleBefore
        }
    }

    private func record(_ call: SwipeCall) {
        swipeCalls.append(call)
        dockVoices.append(.swipe(call))
    }

    /// Asks for another answer to "what follows on this Mac" from the next hold on.
    private func setFollowAvailability(_ availability: DockFollowAvailability) {
        InputProcessor.shared.setTestingFollowAvailability { [weak self] in
            self?.availabilityQuestions += 1
            return availability
        }
    }

    /// A hold's last swipe event waits one turn of the main queue, and its line in the log
    /// is written one turn after that.
    private func drainMainQueue() {
        waitForMainQueue()
        waitForMainQueue()
    }

    private func pressGestureButton() {
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .down)), .consumed)
    }

    /// The hand moves, and the frame that hands the movement on runs.
    private func moveHand(_ deltaX: CGFloat, _ deltaY: CGFloat) {
        advanceFrame()
        InputProcessor.shared.handleMouseGestureMovement(deltaX: deltaX, deltaY: deltaY)
        runScheduledWork()
    }

    /// The button comes up after the hand rested (`pause` seconds since its last movement).
    private func releaseGestureButton(after pause: TimeInterval = 0.2) {
        clock += pause
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .up)), .consumed)
        drainMainQueue()
    }

    /// One whole hold: press, the movements (one frame each), a rest, release.
    private func hold(_ movements: [(CGFloat, CGFloat)], rest: TimeInterval = 0.2) {
        pressGestureButton()
        for movement in movements {
            moveHand(movement.0, movement.1)
        }
        releaseGestureButton(after: rest)
    }

    /// Opens Mission Control with the hand (Up, past half), so that Scrollio believes it
    /// shows; then forgets what was recorded.
    private func openMissionControlWithTheHand(file: StaticString = #filePath, line: UInt = #line) {
        hold([(0, -240)])
        XCTAssertEqual(InputProcessor.shared.believedDockView, .missionControl, file: file, line: line)
        swipeCalls = []
        dockVoices = []
        gestureLog = []
        hapticCues = []
    }

    // MARK: A direction follows

    func testAHoldWhoseUpIsMissionControlFollowsTheHandAndRunsNoAction() {
        configureFollowing()

        pressGestureButton()
        clock += 0.048 - screen.frameDuration
        advanceFrame()
        // Movement only accumulates until the next frame; below 40 pt nothing is shown.
        InputProcessor.shared.handleMouseGestureMovement(deltaX: 0, deltaY: -100)
        XCTAssertEqual(swipeCalls, [])
        runScheduledWork()
        // The motion begins where the action would have run, with the movement that got there.
        assertSwipeCalls([.begin(.vertical), .update(0.25)])
        XCTAssertTrue(MouseGesturePointerLock.shared.isLocked)

        moveHand(0, -100)
        // Sideways no longer counts, and going back undoes.
        moveHand(-300, 0)
        moveHand(0, 20)
        assertSwipeCalls([.begin(.vertical), .update(0.25), .update(0.5), .update(0.45)])
        moveHand(0, -20)

        // The release is handled inside the button tap callback: the terminal event waits.
        clock += 0.2
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .up)), .consumed)
        XCTAssertEqual(swipeCalls.count, 5)
        XCTAssertFalse(MouseGesturePointerLock.shared.isLocked)
        drainMainQueue()

        assertSwipeCalls([.begin(.vertical), .update(0.25), .update(0.5), .update(0.45), .update(0.5), .end(0)])
        XCTAssertEqual(instantVoices, [], "a hold that follows asks the Dock for nothing in one go: no toggle, no key")
        XCTAssertEqual(gestureLog, [
            "Gestures: up followed the hand: missionControl, vertical +, began after 48 ms, 4 updates, "
                + "furthest 0.50, released at 0.50, 0.0/s: ended, expected to open",
        ])
        XCTAssertEqual(hapticCues, [.lockIn, .commit], "a light pulse as the motion begins, the stronger one as it is let go to open")
        XCTAssertEqual(availabilityQuestions, 1, "asked once, when the button went down")
        XCTAssertFalse(InputProcessor.shared.hasActiveMouseGestureSessions)
        XCTAssertFalse(DockSwipeSynthesizer.shared.isActive)
    }

    func testAFollowedMotionIsOneSidedAndStopsAtTheWholeView() {
        configureFollowing()

        pressGestureButton()
        moveHand(0, -100)
        moveHand(0, -2000)
        moveHand(0, 40)
        // Back through the start and far beyond: the desktop as it was, no other motion,
        // and Down's own action (Apps) does not run.
        moveHand(0, 3000)
        moveHand(0, -40)
        assertSwipeCalls([.begin(.vertical), .update(0.25), .update(1), .update(0.9), .update(0), .update(0.1)])
        moveHand(0, 400)
        releaseGestureButton()

        assertSwipeCalls([
            .begin(.vertical), .update(0.25), .update(1), .update(0.9), .update(0), .update(0.1), .update(0), .cancel,
        ])
        XCTAssertEqual(instantVoices, [])
        XCTAssertEqual(gestureLog, [
            "Gestures: up followed the hand: missionControl, vertical +, began after 17 ms, 6 updates, "
                + "furthest 1.00, released at 0.00: cancelled",
        ])
        XCTAssertEqual(hapticCues, [.lockIn], "no stronger pulse for a motion that went back")
        XCTAssertNil(InputProcessor.shared.believedDockView)
    }

    func testAReleaseWhileMovingEndsWithTheHandsSpeedWithinItsBound() {
        configureFollowing()

        // 0.45 of the view in the 60 ms since the motion began: 7.5 views a second.
        pressGestureButton()
        clock = 101
        InputProcessor.shared.handleMouseGestureMovement(deltaX: 0, deltaY: -100)
        runScheduledWork()
        clock = 101.03
        InputProcessor.shared.handleMouseGestureMovement(deltaX: 0, deltaY: -40)
        runScheduledWork()
        clock = 101.06
        InputProcessor.shared.handleMouseGestureMovement(deltaX: 0, deltaY: -40)
        runScheduledWork()
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .up)), .consumed)
        drainMainQueue()
        assertSwipeCalls([.begin(.vertical), .update(0.25), .update(0.35), .update(0.45), .end(7.5)])
        XCTAssertEqual(hapticCues, [.lockIn, .commit], "short of half, but still on its way at more than a view a second")
        XCTAssertEqual(gestureLog, [
            "Gestures: up followed the hand: missionControl, vertical +, began after 1000 ms, 3 updates, "
                + "furthest 0.45, released at 0.45, 7.5/s: ended, expected to open",
        ])

        // A flick that arrives with the release is one whole swipe, and no faster than a
        // trackpad sends: 12 views a second. (Long after the first hold: nothing is
        // believed to show any more.)
        swipeCalls = []
        clock = 200
        pressGestureButton()
        clock = 200.001
        InputProcessor.shared.handleMouseGestureMovement(deltaX: 0, deltaY: -200)
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .up)), .consumed)
        XCTAssertEqual(swipeCalls, [], "nothing is posted inside the callbacks")
        drainMainQueue()
        assertSwipeCalls([.begin(.vertical), .update(0.5), .end(12)])
        XCTAssertEqual(instantVoices, [])
    }

    func testEachViewDrivesItsOwnMotionAndSign() {
        // Show Desktop: the spread, the positive end of the pinch.
        configureFollowing(up: "showDesktop", down: "missionControl")
        hold([(0, -100)])
        assertSwipeCalls([.begin(.pinch), .update(0.25), .end(0)])
        swipeCalls = []
        InputProcessor.shared.surroundingsChanged(.anotherApplicationCameToFront)
        hold([(0, 100)])
        assertSwipeCalls([.begin(.vertical), .update(0.25), .end(0)])

        // Apps follows only where a build lets it: the other end of the pinch, over three
        // quarters of the travel.
        swipeCalls = []
        gestureLog = []
        setFollowAvailability(mac(apps: true))
        Options.shared.gesture.downAction = "appExpose"
        Options.shared.gesture.trackingSpeed = 2
        hold([(0, 60)])
        assertSwipeCalls([.begin(.pinch), .update(-0.4), .end(0)])
        XCTAssertEqual(gestureLog, [
            "Gestures: down followed the hand: appExpose, pinch -, began after 17 ms, 1 update, "
                + "furthest 0.40, released at 0.40, 0.0/s: ended",
        ])
        XCTAssertEqual(instantVoices, [])
    }

    /// A hold the mouse tracks itself (a Logitech control that reports its own movement)
    /// drives the same motion: its counts are the hand's movement, half a point each, and
    /// Scrollio does not freeze the pointer for it.
    func testAHoldTheMouseTracksItselfFollowsTheHandTheSameWay() {
        configureFollowing()
        let down = InputEvent(
            type: .mouse, code: 3, modifiers: [], phase: .down, source: .hidPP, device: nil, tracksMovementOnDevice: true
        )
        XCTAssertEqual(InputProcessor.shared.process(down), .consumed)
        XCTAssertFalse(MouseGesturePointerLock.shared.isLocked)

        advanceFrame()
        InputProcessor.shared.handleDeviceGestureMovement(code: 3, countsX: 0, countsY: -200)
        XCTAssertEqual(swipeCalls, [], "nothing is posted from the report's callback")
        runScheduledWork()
        advanceFrame()
        InputProcessor.shared.handleDeviceGestureMovement(code: 3, countsX: 6, countsY: -280)
        runScheduledWork()
        // The pointer's own movement is not this hold's.
        InputProcessor.shared.handleMouseGestureMovement(deltaX: 0, deltaY: -500)
        runScheduledWork()
        releaseGestureButton()

        assertSwipeCalls([.begin(.vertical), .update(0.25), .update(0.6), .end(0)])
        XCTAssertEqual(instantVoices, [])
        XCTAssertEqual(hapticCues, [.lockIn, .commit])
        XCTAssertEqual(InputProcessor.shared.believedDockView, .missionControl)
    }

    /// The pointer freeze can add a false movement when it has to put the pointer back; it
    /// is taken out of a motion up as it is out of the desktops' swipe.
    func testThePointerFreezesFalseMovementIsTakenOutOfAMotionUpToo() {
        configureFollowing()
        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(fromCGEvent: makeOtherMouseEvent(.otherMouseDown))),
            .consumed
        )

        // The detach is not honoured: the pointer drifts 60 pt up and is put back.
        let drifted = makeMouseMoveEvent(deltaX: 0, deltaY: -60, location: CGPoint(x: 100, y: 40))
        MouseInteractionSessionController.shared.handleMotionTapEventForTests(drifted)
        XCTAssertEqual(pointerWarps, [pointerAnchor])
        // The next event is back where the pointer was and reports "hand (-60) + jump (+60)".
        let snappedBack = makeMouseMoveEvent(deltaX: 0, deltaY: 0, location: pointerAnchor)
        MouseInteractionSessionController.shared.handleMotionTapEventForTests(snappedBack)
        XCTAssertEqual(swipeCalls, [], "nothing is posted from the tap's callback")
        runScheduledWork()

        // The hand moved 120 pt in all; without the compensation the view would show half.
        assertSwipeCalls([.begin(.vertical), .update(0.3)])
    }

    func testSidewaysIsTheDesktopsWhateverUpAndDownFollow() {
        configureFollowing(up: "missionControl", down: "showDesktop")
        Options.shared.gesture.leftAction = "missionControl"

        // The press jolts the mouse down 9 pt; the hand then goes left.
        pressGestureButton()
        moveHand(0, 9)
        moveHand(-100, 0)
        moveHand(-100, 0)
        releaseGestureButton()

        assertSwipeCalls([.begin(.horizontal), .update(0.1), .update(0.2), .end(0)])
        XCTAssertEqual(instantVoices, [])
        XCTAssertEqual(gestureLog, [], "the desktops write no line, as before")
        XCTAssertNil(InputProcessor.shared.believedDockView)

        // A press that barely moves is still the click, and shows the Dock no motion.
        swipeCalls = []
        dockVoices = []
        hold([(0, -9)])
        XCTAssertEqual(swipeCalls, [])
        XCTAssertEqual(dockVoices, [.settle, .toggle(.missionControl)])
        XCTAssertEqual(gestureLog, ["Gestures: click ran missionControl"])
    }

    /// The roles come from the hold's own copy of the settings: the own set of the app in
    /// front decides, both ways.
    func testAnAppsOwnSetDecidesWhetherItsHoldFollows() {
        configureFollowing(follow: false)
        let applicationsBefore = Options.shared.application.applications
        addTeardownBlock {
            InputProcessor.shared.setTestingMouseGestureFrontApplication(nil)
            Options.shared.application.applications = applicationsBefore
        }
        let notesPath = "/Applications/Notes.app"
        let notes = Application(path: notesPath)
        var own = Options.shared.gesture
        own.actionsFollowHand = true
        notes.setUsesGeneralGestures(false, general: own)
        Options.shared.application.applications = EnhanceArray<Application>(withArray: [notes], matchKey: "path")
        var front: ShortcutRingChoice.FrontApp? = ShortcutRingChoice.FrontApp(
            bundlePath: notesPath, executablePath: notesPath + "/Contents/MacOS/Notes"
        )
        InputProcessor.shared.setTestingMouseGestureFrontApplication { front }

        // The app's own switch is on, the pane's is off: in the app the hold follows.
        hold([(0, -100)])
        assertSwipeCalls([.begin(.vertical), .update(0.25), .end(0)])
        XCTAssertEqual(instantVoices, [])
        XCTAssertEqual(gestureLog, [
            "Gestures: up followed the hand: missionControl, vertical +, began after 17 ms, 1 update, "
                + "furthest 0.25, released at 0.25, 0.0/s: ended, the app in front has its own gestures",
        ])

        // In other apps the pane's set runs: once.
        front = nil
        swipeCalls = []
        dockVoices = []
        gestureLog = []
        hold([(0, -100)])
        XCTAssertEqual(swipeCalls, [])
        XCTAssertEqual(dockVoices, [.settle, .toggle(.missionControl)])
        XCTAssertEqual(gestureLog, ["Gestures: up ran missionControl"])
        InputProcessor.shared.surroundingsChanged(.anotherApplicationCameToFront)

        // The other way round: the pane's switch on, the app's own off.
        Options.shared.gesture.actionsFollowHand = true
        var off = Options.shared.gesture
        off.actionsFollowHand = false
        let quiet = Application(path: notesPath)
        quiet.setUsesGeneralGestures(false, general: off)
        Options.shared.application.applications = EnhanceArray<Application>(withArray: [quiet], matchKey: "path")
        front = ShortcutRingChoice.FrontApp(bundlePath: notesPath, executablePath: notesPath + "/Contents/MacOS/Notes")
        swipeCalls = []
        dockVoices = []
        gestureLog = []
        hold([(0, -100)])
        XCTAssertEqual(swipeCalls, [])
        XCTAssertEqual(dockVoices, [.settle, .toggle(.missionControl)])
        XCTAssertEqual(gestureLog, ["Gestures: up ran missionControl, the app in front has its own gestures"])
        InputProcessor.shared.surroundingsChanged(.anotherApplicationCameToFront)

        front = nil
        swipeCalls = []
        hold([(0, -100)])
        assertSwipeCalls([.begin(.vertical), .update(0.25), .end(0)])
    }

    // MARK: A direction that cannot follow runs once

    func testEachObstacleMakesTheDirectionRunOnceAndTheLogSaysWhy() {
        let missionControlOff = DockGestureSwitches(missionControl: false, showDesktop: true, launchpad: true)
        let showDesktopOff = DockGestureSwitches(missionControl: true, showDesktop: false, launchpad: true)
        let cases: [(up: String, mac: DockFollowAvailability, mode: DockMode, reason: String)] = [
            ("missionControl", mac(switches: missionControlOff), .missionControl, "the Dock's gesture is off"),
            ("showDesktop", mac(switches: showDesktopOff), .showDesktop, "the Dock's gesture is off"),
            ("showDesktop", mac(major: 26), .showDesktop, "not on this macOS"),
            ("missionControl", mac(post: false), .missionControl, "cannot post events"),
            ("missionControl", mac(swipe: false), .missionControl, "the swipe cannot be made on this Mac"),
        ]
        configureFollowing()
        for (up, availability, mode, reason) in cases {
            Options.shared.gesture.upAction = up
            setFollowAvailability(availability)
            swipeCalls = []
            dockVoices = []
            gestureLog = []
            hapticCues = []

            pressGestureButton()
            moveHand(0, -45)
            // The action ran at the usual 40 pt; nothing more happens in this hold.
            moveHand(0, -300)
            moveHand(0, 600)
            releaseGestureButton()

            XCTAssertEqual(swipeCalls, [], reason)
            XCTAssertEqual(dockVoices, [.settle, .toggle(mode)], "once, by name: \(reason)")
            XCTAssertEqual(gestureLog, [
                "Gestures: up did not follow the hand: \(up), \(reason)",
                "Gestures: up ran \(up)",
            ])
            XCTAssertEqual(hapticCues, [.lockIn], reason)
            // What the toggle put up is forgotten before the next case.
            InputProcessor.shared.surroundingsChanged(.anotherApplicationCameToFront)
        }
    }

    /// Apps runs once in every ordinary build, by its key as before.
    func testAppsRunsOnceByItsKeyWhereItDoesNotFollow() {
        configureFollowing()

        hold([(0, 45), (0, 300)])

        XCTAssertEqual(swipeCalls, [])
        XCTAssertEqual(dockVoices, [.settle, .key(resolvedShortcut(SystemShortcut.appExpose).code)])
        XCTAssertEqual(gestureLog, [
            "Gestures: down did not follow the hand: appExpose, not on this macOS",
            "Gestures: down ran appExpose",
        ])
    }

    /// An action without a view of the Dock is what it was: once, and no line about following.
    func testAnActionWithoutAViewRunsOnceAndSaysNothingAboutFollowing() {
        configureFollowing(up: SystemShortcut.copy.identifier, down: "")

        hold([(0, -45), (0, -300)])
        hold([(0, 45)])

        XCTAssertEqual(swipeCalls, [])
        XCTAssertEqual(dockVoices, [.key(resolvedShortcut(SystemShortcut.copy).code)], "no view of the Dock: nothing to settle")
        XCTAssertEqual(gestureLog, ["Gestures: up ran copy"])
    }

    // MARK: The switch off: as 1.1.1

    func testWithTheSwitchOffAHoldIsWhatItWas() {
        configureFollowing(follow: false)

        hold([(0, -100), (0, -300)])
        XCTAssertEqual(swipeCalls, [])
        XCTAssertEqual(dockVoices, [.settle, .toggle(.missionControl)])
        XCTAssertEqual(gestureLog, ["Gestures: up ran missionControl"], "no line about following")

        // Scrollio opened Mission Control itself, and still Down is its own action.
        XCTAssertEqual(InputProcessor.shared.believedDockView, .missionControl)
        dockVoices = []
        gestureLog = []
        hold([(0, 100)])
        XCTAssertEqual(swipeCalls, [])
        XCTAssertEqual(dockVoices, [.settle, .key(resolvedShortcut(SystemShortcut.appExpose).code)])
        XCTAssertEqual(gestureLog, ["Gestures: down ran appExpose"])

        hold([(-100, 0)])
        assertSwipeCalls([.begin(.horizontal), .update(0.1), .end(0)])
        XCTAssertEqual(availabilityQuestions, 0, "nobody asks what follows on this Mac")
    }

    func testOneActionPerHoldNeverFollowsWhateverTheSwitchSays() {
        configureFollowing(mode: .discrete)
        XCTAssertTrue(Options.shared.gesture.actionsFollowHand)

        pressGestureButton()
        InputProcessor.shared.handleMouseGestureMovement(deltaX: 0, deltaY: -100)
        XCTAssertTrue(scheduledWork.isEmpty)
        releaseGestureButton()

        XCTAssertEqual(swipeCalls, [])
        XCTAssertEqual(dockVoices, [.settle, .toggle(.missionControl)])
        XCTAssertEqual(gestureLog, ["Gestures: up ran missionControl"])
        XCTAssertEqual(availabilityQuestions, 0)
    }

    // MARK: What shows already (the belief)

    func testTheSameMoveAgainClosesWhatScrollioOpened() {
        configureFollowing()
        openMissionControlWithTheHand()

        // Up again: its instant toggle at the usual 40 pt, no motion.
        hold([(0, -45), (0, -300)])
        XCTAssertEqual(swipeCalls, [])
        XCTAssertEqual(dockVoices, [.settle, .toggle(.missionControl)])
        XCTAssertEqual(gestureLog, [
            "Gestures: up did not follow the hand: missionControl, Mission Control was showing",
            "Gestures: up ran missionControl",
        ])
        XCTAssertNil(InputProcessor.shared.believedDockView, "the toggle closed it")

        // And once more: it opens with the hand again.
        dockVoices = []
        hold([(0, -100)])
        assertSwipeCalls([.begin(.vertical), .update(0.25), .end(0)])
        XCTAssertEqual(instantVoices, [])
    }

    func testTheOppositeMoveLeavesMissionControlWithTheHand() {
        configureFollowing()
        openMissionControlWithTheHand()

        // Down is Apps; while Mission Control shows it is the trackpad's swipe down instead.
        pressGestureButton()
        moveHand(0, 100)
        moveHand(0, 140)
        moveHand(0, -2000)
        moveHand(0, 240)
        releaseGestureButton()
        assertSwipeCalls([.begin(.vertical), .update(-0.25), .update(-0.6), .update(0), .update(-0.6), .end(0)])
        XCTAssertEqual(instantVoices, [], "not Apps, and no toggle")
        XCTAssertEqual(gestureLog, [
            "Gestures: down followed the hand: leaving missionControl, vertical -, began after 17 ms, 4 updates, "
                + "furthest 0.60, released at 0.60, 0.0/s: ended, expected to close",
        ])
        XCTAssertEqual(hapticCues, [.lockIn, .commit])
        XCTAssertNil(InputProcessor.shared.believedDockView, "it was left")

        // Now Down is Apps again.
        dockVoices = []
        swipeCalls = []
        hold([(0, 100)])
        XCTAssertEqual(swipeCalls, [])
        XCTAssertEqual(dockVoices, [.settle, .key(resolvedShortcut(SystemShortcut.appExpose).code)])
    }

    func testLeavingMissionControlOnlyPartWayKeepsItBelieved() {
        configureFollowing()
        openMissionControlWithTheHand()

        hold([(0, 100)])
        assertSwipeCalls([.begin(.vertical), .update(-0.25), .end(0)])
        XCTAssertEqual(InputProcessor.shared.believedDockView, .missionControl, "a quarter of the way: it stays")

        swipeCalls = []
        hold([(0, 100), (0, -100)])
        assertSwipeCalls([.begin(.vertical), .update(-0.25), .update(0), .cancel])
        XCTAssertEqual(InputProcessor.shared.believedDockView, .missionControl)
        XCTAssertEqual(instantVoices, [])
    }

    func testAHoldThatIsNotExpectedToOpenLeavesNothingBelieved() {
        configureFollowing()

        hold([(0, -100)])
        assertSwipeCalls([.begin(.vertical), .update(0.25), .end(0)])
        XCTAssertNil(InputProcessor.shared.believedDockView, "a quarter of the way, at rest")
        XCTAssertEqual(hapticCues, [.lockIn])

        swipeCalls = []
        hold([(0, -100)])
        assertSwipeCalls([.begin(.vertical), .update(0.25), .end(0)])
    }

    /// Scrollio's own instant toggle counts like its swipe: the click (Mission Control by
    /// default) puts the view up, and Up then closes it at once.
    func testAnInstantToggleOfScrolliosIsBelievedToo() {
        configureFollowing()

        hold([])
        XCTAssertEqual(dockVoices, [.settle, .toggle(.missionControl)])
        XCTAssertEqual(InputProcessor.shared.believedDockView, .missionControl)

        dockVoices = []
        hold([(0, -100)])
        XCTAssertEqual(swipeCalls, [])
        XCTAssertEqual(dockVoices, [.settle, .toggle(.missionControl)])
        XCTAssertNil(InputProcessor.shared.believedDockView)

        // A toggle from anywhere in Scrollio (a button, the Shortcut Ring) counts.
        ShortcutExecutor.shared.executeOnePress(.systemShortcut(identifier: "showDesktop"))
        XCTAssertEqual(InputProcessor.shared.believedDockView, .showDesktop)
        ShortcutExecutor.shared.executeOnePress(.systemShortcut(identifier: "showDesktop"))
        XCTAssertNil(InputProcessor.shared.believedDockView)
        ShortcutExecutor.shared.executeOnePress(.systemShortcut(identifier: "appExpose"))
        XCTAssertEqual(InputProcessor.shared.believedDockView, .apps)
    }

    func testTheBeliefIsDroppedByEachOfItsTriggers() {
        configureFollowing()
        let triggers: [(name: String, happen: () -> Void)] = [
            ("a minute passed", { [unowned self] in self.clock += 60 }),
            ("another app came to the front", { InputProcessor.shared.surroundingsChanged(.anotherApplicationCameToFront) }),
            ("the desktop in use changed", { InputProcessor.shared.surroundingsChanged(.activeSpaceChanged) }),
            ("Scrollio stopped (sleep, Pause)", { InputProcessor.shared.clearActiveBindings() }),
        ]
        for trigger in triggers {
            openMissionControlWithTheHand()
            trigger.happen()
            XCTAssertNil(InputProcessor.shared.believedDockView, trigger.name)

            // Up opens with the hand again instead of toggling.
            hold([(0, -100)])
            assertSwipeCalls([.begin(.vertical), .update(0.25), .end(0)])
            XCTAssertEqual(instantVoices, [], trigger.name)
            swipeCalls = []
        }

        // What does not drop it: time short of a minute, a change of the screens.
        openMissionControlWithTheHand()
        clock += 59
        InputProcessor.shared.surroundingsChanged(.screenParametersChanged)
        InputProcessor.shared.surroundingsChanged(.displaysWentToSleep)
        XCTAssertEqual(InputProcessor.shared.believedDockView, .missionControl)
    }

    // MARK: One voice to the Dock

    func testEveryInstantDockToggleOfScrolliosSettlesTheSwipeFirst() {
        configureFollowing()
        let appsKey = resolvedShortcut(SystemShortcut.appExpose).code

        ShortcutExecutor.shared.executeOnePress(.systemShortcut(identifier: "missionControl"))
        XCTAssertEqual(dockVoices, [.settle, .toggle(.missionControl)])
        dockVoices = []
        ShortcutExecutor.shared.executeOnePress(.systemShortcut(identifier: "showDesktop"))
        XCTAssertEqual(dockVoices, [.settle, .toggle(.showDesktop)])
        dockVoices = []
        ShortcutExecutor.shared.executeOnePress(.systemShortcut(identifier: "appExpose"))
        XCTAssertEqual(dockVoices, [.settle, .key(appsKey)])

        // Where the Dock cannot be asked by name, the key is sent: settled first as well.
        dockVoices = []
        ShortcutExecutor.shared.toggleDockMode = { _ in false }
        ShortcutExecutor.shared.executeOnePress(.systemShortcut(identifier: "missionControl"))
        XCTAssertEqual(dockVoices.count, 2)
        XCTAssertEqual(dockVoices.first, .settle)

        // Nothing else settles: the desktops' keys, a shortcut of an app.
        dockVoices = []
        ShortcutExecutor.shared.executeOnePress(.systemShortcut(identifier: SystemShortcut.copy.identifier))
        ShortcutExecutor.shared.executeOnePress(.systemShortcut(identifier: SystemShortcut.moveSpaceLeft.identifier))
        XCTAssertFalse(dockVoices.contains(.settle))
    }

    /// A toggle from elsewhere while a hold drives a motion: the motion goes back first, the
    /// hold sends nothing more, and its release cannot end a swipe that began after it.
    func testAToggleFromElsewhereTakesTheHoldsMotionBackFirst() {
        configureFollowing()

        pressGestureButton()
        moveHand(0, -240)
        ShortcutExecutor.shared.executeOnePress(.systemShortcut(identifier: "showDesktop"))
        XCTAssertEqual(dockVoices, [
            .swipe(.begin(.vertical)), .swipe(.update(0.6)), .swipe(.cancel), .settle, .toggle(.showDesktop),
        ])

        moveHand(0, -100)
        // The thumb wheel begins a swipe of its own meanwhile.
        DockSwipeSynthesizer.shared.begin(axis: .horizontal)
        releaseGestureButton()

        assertSwipeCalls([.begin(.vertical), .update(0.6), .cancel, .begin(.horizontal)])
        XCTAssertTrue(DockSwipeSynthesizer.shared.isActive, "the wheel's swipe goes on")
        XCTAssertEqual(gestureLog, [
            "Gestures: up followed the hand: missionControl, vertical +, began after 17 ms, 1 update, "
                + "furthest 0.60, at 0.60: cancelled (its swipe had been taken back)",
        ])
        XCTAssertEqual(InputProcessor.shared.believedDockView, .showDesktop, "the toggle's view, not the hold's")
        XCTAssertEqual(hapticCues, [.lockIn])
        DockSwipeSynthesizer.shared.cancel()
    }

    /// A hold never sends both a swipe and the instant form: after the motion began no
    /// action runs, and after an action ran no motion begins.
    func testAHoldNeverSendsBothASwipeAndTheInstantForm() {
        let missionControlOff = DockGestureSwitches(missionControl: false, showDesktop: true, launchpad: true)
        configureFollowing(up: "missionControl", down: "showDesktop", on: mac(switches: missionControlOff))

        // Up runs once; Down's motion does not begin afterwards.
        hold([(0, -45), (0, 600)])
        XCTAssertEqual(swipeCalls, [])
        XCTAssertEqual(dockVoices, [.settle, .toggle(.missionControl)])

        // Down follows; Up's action does not run afterwards, and the release is no click.
        InputProcessor.shared.surroundingsChanged(.anotherApplicationCameToFront)
        dockVoices = []
        hold([(0, 100), (0, -600)])
        assertSwipeCalls([.begin(.pinch), .update(0.25), .update(0), .cancel])
        XCTAssertEqual(instantVoices, [])
    }

    /// The thumb wheel's swipe of the desktops, or its tail while the wheel rests, is never
    /// taken over for another motion: the direction runs its action once.
    func testAHoldNeverTakesTheWheelsSwipeOverForAnotherMotion() {
        configureFollowing()
        // "Follow the wheel" drives the desktops.
        DockSwipeSynthesizer.shared.begin(axis: .horizontal)
        DockSwipeSynthesizer.shared.update(progress: 0.5)

        pressGestureButton()
        moveHand(0, -100)
        XCTAssertEqual(dockVoices, [.swipe(.begin(.horizontal)), .swipe(.update(0.5))], "no vertical begin, nothing taken over")
        waitForMainQueue()
        // The action runs once instead. It is a toggle of the Dock, so the swipe that runs
        // is settled first: one voice.
        XCTAssertEqual(dockVoices, [
            .swipe(.begin(.horizontal)), .swipe(.update(0.5)), .swipe(.cancel), .settle, .toggle(.missionControl),
        ])
        moveHand(0, -300)
        releaseGestureButton()

        XCTAssertEqual(dockVoices.count, 5, "the rest of the hold does nothing")
        XCTAssertEqual(gestureLog, [
            "Gestures: up did not follow the hand: missionControl, the wheel's swipe was running",
            "Gestures: up ran missionControl",
        ])
        XCTAssertEqual(hapticCues, [.lockIn])

        // Sideways still takes the wheel's swipe over, as before.
        swipeCalls = []
        DockSwipeSynthesizer.shared.begin(axis: .horizontal)
        hold([(-100, 0)])
        assertSwipeCalls([.begin(.horizontal), .cancel, .begin(.horizontal), .update(0.1), .end(0)])
    }

    /// The same when the motion would begin with the release itself.
    func testAFlickDuringTheWheelsSwipeRunsOnceToo() {
        configureFollowing()
        DockSwipeSynthesizer.shared.begin(axis: .horizontal)

        pressGestureButton()
        advanceFrame()
        InputProcessor.shared.handleMouseGestureMovement(deltaX: 0, deltaY: -200)
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .up)), .consumed)
        drainMainQueue()

        XCTAssertEqual(dockVoices, [.swipe(.begin(.horizontal)), .swipe(.cancel), .settle, .toggle(.missionControl)])
        XCTAssertEqual(gestureLog, [
            "Gestures: up did not follow the hand: missionControl, the wheel's swipe was running",
            "Gestures: up ran missionControl",
        ])
    }

    // MARK: Nothing stuck

    func testEveryAbnormalEndOfAFollowedMotionIsACancelAtOnce() {
        configureFollowing()
        let harness = RingHarness()
        addTeardownBlock { ShortcutRingController.setTestingController(nil) }
        let syntheticRelease = InputEvent(
            type: .mouse, code: 3, modifiers: [], phase: .up, source: .hidPP, device: nil, isSyntheticRelease: true
        )
        let ends: [(reason: String, happen: () -> Void)] = [
            ("no button-up", { InputProcessor.shared.fireInteractiveGestureWatchdogForTests() }),
            ("the mouse went away", { XCTAssertEqual(InputProcessor.shared.process(syntheticRelease), .consumed) }),
            ("Scrollio's event taps stopped", { InputProcessor.shared.clearActiveBindings() }),
            ("the screens changed", { InputProcessor.shared.surroundingsChanged(.screenParametersChanged) }),
            ("the displays went to sleep", { InputProcessor.shared.surroundingsChanged(.displaysWentToSleep) }),
            ("the desktop in use changed", { InputProcessor.shared.surroundingsChanged(.activeSpaceChanged) }),
            ("the Shortcut Ring opened", { [unowned self] in
                XCTAssertEqual(InputProcessor.shared.process(self.gestureInputEvent(phase: .down, code: 4)), .consumed)
            }),
        ]
        for end in ends {
            // The gesture button, and a second button that opens the Shortcut Ring.
            configureGestureBinding(mode: .interactive)
            Options.shared.buttons.binding.append(ButtonBinding(
                triggerEvent: RecordedEvent(type: .mouse, code: 4, modifiers: 0, deviceFilter: nil),
                systemShortcutName: SystemShortcut.shortcutRing.identifier,
                isEnabled: true
            ))
            ButtonUtils.shared.invalidateCache()
            ShortcutRingController.setTestingController(harness.controller)
            swipeCalls = []
            dockVoices = []
            gestureLog = []
            hapticCues = []

            pressGestureButton()
            moveHand(0, -240)
            end.happen()

            // Synchronous: sleep and quit cannot wait for the main queue.
            assertSwipeCalls([.begin(.vertical), .update(0.6), .cancel])
            XCTAssertFalse(DockSwipeSynthesizer.shared.isActive, end.reason)

            // Late movement and the button-up change nothing: no end, no click, no action.
            moveHand(0, -100)
            _ = InputProcessor.shared.process(gestureInputEvent(phase: .up))
            _ = InputProcessor.shared.process(gestureInputEvent(phase: .up, code: 4))
            drainMainQueue()
            XCTAssertEqual(swipeCalls.count, 3, end.reason)
            XCTAssertEqual(instantVoices, [], end.reason)
            XCTAssertEqual(gestureLog, [
                "Gestures: up followed the hand: missionControl, vertical +, began after 17 ms, 1 update, "
                    + "furthest 0.60, at 0.60: cancelled (\(end.reason))",
            ])
            XCTAssertEqual(hapticCues, [.lockIn], end.reason)
            XCTAssertNil(InputProcessor.shared.believedDockView, "a motion that was taken back opened nothing: \(end.reason)")

            ShortcutRingController.setTestingController(nil)
            InputProcessor.shared.clearActiveBindings()
        }
    }

    /// A change of the desktop in use takes back a motion towards a view; the desktops'
    /// own swipe goes on (its own switch of desktops is such a change). A change of the
    /// screens, and the displays going to sleep, take back whatever runs.
    func testTheDesktopsSwipeGoesOnThroughAChangeOfTheDesktopButNotOfTheScreens() {
        configureFollowing()

        pressGestureButton()
        moveHand(-100, 0)
        InputProcessor.shared.surroundingsChanged(.activeSpaceChanged)
        InputProcessor.shared.surroundingsChanged(.anotherApplicationCameToFront)
        assertSwipeCalls([.begin(.horizontal), .update(0.1)])
        moveHand(-100, 0)
        InputProcessor.shared.surroundingsChanged(.screenParametersChanged)
        assertSwipeCalls([.begin(.horizontal), .update(0.1), .update(0.2), .cancel])
        moveHand(-100, 0)
        releaseGestureButton()
        XCTAssertEqual(swipeCalls.count, 4)

        swipeCalls = []
        pressGestureButton()
        moveHand(-100, 0)
        InputProcessor.shared.surroundingsChanged(.displaysWentToSleep)
        assertSwipeCalls([.begin(.horizontal), .update(0.1), .cancel])
        releaseGestureButton()
        XCTAssertEqual(swipeCalls.count, 3)
        XCTAssertEqual(gestureLog, [], "the desktops write no line")
    }

    /// A motion whose button is up and whose last event still waits for the main queue is
    /// taken back as well, and the event that waited is not sent after it.
    func testAMotionThatWasLetGoIsStillTakenBackBeforeItsLastEventGoesOut() {
        configureFollowing()

        pressGestureButton()
        moveHand(0, -240)
        clock += 0.2
        XCTAssertEqual(InputProcessor.shared.process(gestureInputEvent(phase: .up)), .consumed)
        InputProcessor.shared.surroundingsChanged(.activeSpaceChanged)
        assertSwipeCalls([.begin(.vertical), .update(0.6), .cancel])
        drainMainQueue()

        XCTAssertEqual(swipeCalls.count, 3, "no end after the cancel")
        XCTAssertEqual(gestureLog, [
            "Gestures: up followed the hand: missionControl, vertical +, began after 17 ms, 1 update, "
                + "furthest 0.60, at 0.60: cancelled (its swipe had been taken back)",
        ])
        XCTAssertNil(InputProcessor.shared.believedDockView)
        XCTAssertEqual(hapticCues, [.lockIn])
    }

    func testTheWatchdogOfAFollowedHoldLetsTheNextPressStartOver() {
        configureFollowing()

        pressGestureButton()
        moveHand(0, -100)
        InputProcessor.shared.fireInteractiveGestureWatchdogForTests()
        assertSwipeCalls([.begin(.vertical), .update(0.25), .cancel])
        XCTAssertFalse(MouseGesturePointerLock.shared.isLocked)

        swipeCalls = []
        hold([(0, -100)])
        assertSwipeCalls([.begin(.vertical), .update(0.25), .end(0)])
    }

    // MARK: - Mode rules of the gesture controls

    func testModePresentationRules() {
        typealias Presentation = MouseGestureModePresentation
        XCTAssertEqual(
            Presentation.make(storedMode: .discrete, isInteractiveAvailable: true),
            Presentation(selectedMode: .discrete, isInteractiveSelectable: true, areHorizontalActionsEditable: true)
        )
        XCTAssertEqual(
            Presentation.make(storedMode: .interactive, isInteractiveAvailable: true),
            Presentation(selectedMode: .interactive, isInteractiveSelectable: true, areHorizontalActionsEditable: false)
        )
        // Unavailable: Scrollio runs discrete whatever is stored, and the controls say so.
        XCTAssertEqual(
            Presentation.make(storedMode: .interactive, isInteractiveAvailable: false),
            Presentation(selectedMode: .discrete, isInteractiveSelectable: false, areHorizontalActionsEditable: true)
        )
        XCTAssertEqual(
            Presentation.make(storedMode: .discrete, isInteractiveAvailable: false),
            Presentation(selectedMode: .discrete, isInteractiveSelectable: false, areHorizontalActionsEditable: true)
        )
    }

    func testControlsFollowModeDisablesOnlyLeftAndRight() {
        let view = makeControlsView(isInteractiveAvailable: { true })
        let mode = modeControl(in: view)

        XCTAssertEqual(mode.selectedSegment, 0)
        XCTAssertTrue(mode.isEnabled(forSegment: 1))
        XCTAssertEqual(mode.label(forSegment: 0), NSLocalizedString("gesture-mode-discrete", comment: ""))
        XCTAssertEqual(mode.label(forSegment: 1), NSLocalizedString("gesture-mode-interactive", comment: ""))
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
        let invert = find(MouseGestureSettingsControls.Identifier.invertHorizontal, in: view) as! NSSwitch
        XCTAssertTrue(invert.isEnabled)
        invert.state = .on
        invert.sendAction(invert.action, to: invert.target)
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

    func testControlsDisableFollowWhenUnavailable() {
        Options.shared.gesture.mode = .interactive
        let view = makeControlsView(isInteractiveAvailable: { false })
        let mode = modeControl(in: view)

        XCTAssertEqual(mode.selectedSegment, 0, "Scrollio runs discrete, so discrete is shown")
        XCTAssertFalse(mode.isEnabled(forSegment: 1))
        XCTAssertTrue(mode.isEnabled(forSegment: 0))
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

    /// The gesture controls, in a view of their own.
    private func makeControlsView(isInteractiveAvailable: (() -> Bool)? = nil) -> NSView {
        let controls = isInteractiveAvailable.map {
            MouseGestureSettingsControls(showLogiActions: false, isInteractiveAvailable: $0)
        } ?? MouseGestureSettingsControls(showLogiActions: false)
        retainedControls.append(controls)
        let view = NSView()
        for control in [controls.modeControl, controls.invertToggle, controls.freezeToggle] + controls.actionPopUps {
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

    private func actionPopUp(_ direction: String, in view: NSView) -> NSPopUpButton {
        find(MouseGestureSettingsControls.Identifier.action(direction), in: view) as! NSPopUpButton
    }

    /// A pull-down shows its first menu item as the title.
    private func popUpTitle(_ direction: String, in view: NSView) -> String? {
        actionPopUp(direction, in: view).menu?.items.first?.title
    }
}
