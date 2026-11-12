import XCTest
@testable import Scrollio_Debug

final class MouseInteractionSessionControllerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        Options.shared.buttons.binding = []
        ButtonUtils.shared.invalidateCache()
        MouseInteractionSessionController.shared.setTestingMotionTapHooks()
        MouseInteractionSessionController.shared.clearAllSessions()
        InputProcessor.shared.clearActiveBindings()
    }

    override func tearDown() {
        InputProcessor.shared.clearActiveBindings()
        MouseInteractionSessionController.shared.clearAllSessions()
        MouseInteractionSessionController.shared.clearTestingMotionTapHooks()
        Options.shared.buttons.binding = []
        ButtonUtils.shared.invalidateCache()
        super.tearDown()
    }

    private func activateVirtualModifiers(_ modifiers: [(code: UInt16, shortcut: String)]) {
        Options.shared.buttons.binding = modifiers.map { modifier in
            let trigger = RecordedEvent(
                type: .mouse,
                code: modifier.code,
                modifiers: 0,
                displayComponents: ["🖱\(modifier.code + 1)"],
                deviceFilter: nil
            )
            return ButtonBinding(
                triggerEvent: trigger,
                systemShortcutName: modifier.shortcut,
                isEnabled: true
            )
        }
        ButtonUtils.shared.invalidateCache()

        for modifier in modifiers {
            let event = InputEvent(
                type: .mouse,
                code: modifier.code,
                modifiers: .init(rawValue: 0),
                phase: .down,
                source: .hidPP,
                device: nil
            )
            XCTAssertEqual(InputProcessor.shared.process(event), .consumed)
        }
    }

    func testSyntheticTargetPriority_leftBeatsRightAndOther() {
        XCTAssertEqual(
            MouseInteractionSessionController.dominantSyntheticTarget(from: [
                .other(buttonNumber: 4),
                .right,
                .left,
            ]),
            .left
        )
        XCTAssertEqual(
            MouseInteractionSessionController.dominantSyntheticTarget(from: [
                .other(buttonNumber: 4),
                .other(buttonNumber: 3),
            ]),
            .other(buttonNumber: 3)
        )
    }

    func testEffectiveTarget_prefersPhysicalLeftOverSyntheticRight() {
        XCTAssertEqual(
            MouseInteractionSessionController.effectiveTarget(
                physical: .left,
                synthetic: .right
            ),
            .left
        )
    }

    func testEffectiveTarget_upgradesMouseMovedToSyntheticLeftDragged() {
        XCTAssertEqual(
            MouseInteractionSessionController.effectiveTarget(
                physical: .none,
                synthetic: .left
            ),
            .left
        )
    }

    func testSessionLifecycle_startsOnFirstMouseSession_andStopsOnLast() {
        var startCount = 0
        var stopCount = 0
        let controller = MouseInteractionSessionController(
            startMotionTap: { startCount += 1 },
            stopMotionTap: { stopCount += 1 }
        )

        XCTAssertFalse(controller.isMotionTapRunning)

        let leftSessionID = controller.beginSession(target: .left)
        XCTAssertTrue(controller.isMotionTapRunning)
        XCTAssertEqual(startCount, 1)
        XCTAssertEqual(stopCount, 0)

        let rightSessionID = controller.beginSession(target: .right)
        XCTAssertTrue(controller.isMotionTapRunning)
        XCTAssertEqual(startCount, 1)
        XCTAssertEqual(stopCount, 0)

        controller.endSession(id: leftSessionID)
        XCTAssertTrue(controller.isMotionTapRunning)
        XCTAssertEqual(stopCount, 0)

        controller.endSession(id: rightSessionID)
        XCTAssertFalse(controller.isMotionTapRunning)
        XCTAssertEqual(stopCount, 1)
    }

    // MARK: - The tap: made on demand, replaced when it stays off, released with the cores

    /// A pointer-movement tap that runs after `start` unless it is stale.
    private final class FakeMotionTap: PointerMotionTap {
        /// False: macOS no longer serves it (kept across a loss of the Accessibility access or
        /// a switch to another user); enabling it changes nothing.
        var runsAfterStart: Bool
        private(set) var running = false
        private(set) var starts = 0
        private(set) var pauses = 0
        private(set) var stops = 0

        init(runsAfterStart: Bool) { self.runsAfterStart = runsAfterStart }

        func start() throws { starts += 1; running = runsAfterStart }
        func pause() { pauses += 1; running = false }
        func stop() { stops += 1; running = false }
        func isRunning() -> Bool { running }
    }

    /// Makes the taps, each started as `Interceptor.init` starts it; whether each runs is
    /// taken from the list in order (true once it is used up).
    private final class FakeMotionTapFactory {
        private var runsAfterStart: [Bool]
        private(set) var made: [FakeMotionTap] = []

        init(_ runsAfterStart: [Bool]) { self.runsAfterStart = runsAfterStart }

        func make() throws -> PointerMotionTap {
            let tap = FakeMotionTap(runsAfterStart: runsAfterStart.isEmpty ? true : runsAfterStart.removeFirst())
            try tap.start()
            made.append(tap)
            return tap
        }
    }

    func testAPausedTapIsStartedAgainNotMadeAgain() {
        let factory = FakeMotionTapFactory([true])
        let controller = MouseInteractionSessionController(makeMotionTap: factory.make)

        let first = controller.beginSession(target: .left)
        XCTAssertTrue(controller.isMotionTapRunning)
        controller.endSession(id: first)
        XCTAssertFalse(controller.isMotionTapRunning)
        XCTAssertEqual(factory.made.first?.pauses, 1)

        _ = controller.beginSession(target: .left)
        XCTAssertTrue(controller.isMotionTapRunning)
        XCTAssertEqual(factory.made.count, 1)
        XCTAssertEqual(factory.made.first?.starts, 2)
    }

    /// The reported failure: after Accessibility was switched off and on, the kept tap no
    /// longer ran, every gesture hold read no movement and kept the pointer frozen. A tap
    /// that is off right after it was started is now dropped and a new one made.
    func testAKeptTapThatStaysOffIsReplaced() {
        let factory = FakeMotionTapFactory([true, true])
        let controller = MouseInteractionSessionController(makeMotionTap: factory.make)
        controller.endSession(id: controller.beginSession(target: .left))
        factory.made[0].runsAfterStart = false

        _ = controller.beginSession(target: .left)

        XCTAssertTrue(controller.isMotionTapRunning)
        XCTAssertEqual(factory.made.count, 2)
        XCTAssertEqual(factory.made[0].stops, 1, "the stale tap is switched off and let go")
        XCTAssertTrue(factory.made[1].isRunning())
        XCTAssertEqual(
            MouseInteractionSessionController.motionTapReplacedLine(droppedKeptTap: true),
            "The pointer movement event tap was off right after it was started (the one kept from an earlier use): "
                + "made a new one, which runs"
        )
    }

    /// A new tap that is off too is made once more; then the controller gives up until the
    /// next use instead of making taps in a loop.
    func testANewTapThatStaysOffIsMadeOnceMoreThenGivenUp() {
        let factory = FakeMotionTapFactory([false, false, true])
        let controller = MouseInteractionSessionController(makeMotionTap: factory.make)

        _ = controller.beginSession(target: .left)
        XCTAssertFalse(controller.isMotionTapRunning)
        XCTAssertEqual(factory.made.count, MouseInteractionSessionController.motionTapAttempts)
        XCTAssertEqual(factory.made.map(\.stops), [1, 1], "no tap that does not run is kept")

        // The next use tries again.
        _ = controller.beginSession(target: .right)
        XCTAssertTrue(controller.isMotionTapRunning)
        XCTAssertEqual(factory.made.count, 3)
    }

    /// The cores stop: the tap is let go, not only paused, and the next use makes a new one.
    func testReleasingLetsTheTapGoAndTheNextUseMakesANewOne() {
        let factory = FakeMotionTapFactory([true, true])
        let controller = MouseInteractionSessionController(makeMotionTap: factory.make)
        _ = controller.beginSession(target: .left)

        controller.releaseMotionTap()
        XCTAssertFalse(controller.isMotionTapRunning)
        XCTAssertEqual(controller.activeSessionCount, 0)
        XCTAssertEqual(factory.made[0].stops, 1)

        // Releasing again, with nothing there, is harmless.
        controller.releaseMotionTap()
        XCTAssertEqual(factory.made[0].stops, 1)

        _ = controller.beginSession(target: .left)
        XCTAssertTrue(controller.isMotionTapRunning)
        XCTAssertEqual(factory.made.count, 2)
    }

    func testRewriteMouseInteractionEvent_withSyntheticLeftConvertsMouseMovedToLeftDragged() {
        let controller = MouseInteractionSessionController(startMotionTap: {}, stopMotionTap: {})
        _ = controller.beginSession(target: .left)

        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: CGPoint(x: 120, y: 60),
            mouseButton: .left
        )!

        controller.rewriteMouseInteractionEvent(event)

        XCTAssertEqual(event.type, .leftMouseDragged)
        XCTAssertEqual(event.getIntegerValueField(.mouseEventButtonNumber), 0)
    }

    func testRewriteMouseInteractionEvent_withSyntheticOtherSetsOtherDraggedAndButtonNumber() {
        let controller = MouseInteractionSessionController(startMotionTap: {}, stopMotionTap: {})
        _ = controller.beginSession(target: .other(buttonNumber: 4))

        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: CGPoint(x: 20, y: 10),
            mouseButton: .left
        )!

        controller.rewriteMouseInteractionEvent(event)

        XCTAssertEqual(event.type, .otherMouseDragged)
        XCTAssertEqual(event.getIntegerValueField(.mouseEventButtonNumber), 4)
    }

    func testRewriteMouseInteractionEvent_prefersHigherPrioritySyntheticLeftOverPhysicalRight() {
        let controller = MouseInteractionSessionController(startMotionTap: {}, stopMotionTap: {})
        _ = controller.beginSession(target: .left)

        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .rightMouseDragged,
            mouseCursorPosition: CGPoint(x: 55, y: 42),
            mouseButton: .right
        )!
        event.setIntegerValueField(.mouseEventButtonNumber, value: 1)

        controller.rewriteMouseInteractionEvent(event)

        XCTAssertEqual(event.type, .leftMouseDragged)
        XCTAssertEqual(event.getIntegerValueField(.mouseEventButtonNumber), 0)
    }

    func testRewriteMouseInteractionEvent_appliesVirtualModifierFlags() {
        activateVirtualModifiers([(code: 6, shortcut: "custom::56:0")])

        let controller = MouseInteractionSessionController(startMotionTap: {}, stopMotionTap: {})
        _ = controller.beginSession(target: .left)

        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: CGPoint(x: 80, y: 44),
            mouseButton: .left
        )!

        controller.rewriteMouseInteractionEvent(event)

        XCTAssertEqual(event.type, .leftMouseDragged)
        XCTAssertTrue(event.flags.contains(.maskShift))
    }

    func testRewriteMouseInteractionEvent_withOnlyVirtualModifiers_preservesMouseMovedAndAppliesFlags() {
        activateVirtualModifiers([(code: 6, shortcut: "custom::58:0")])

        let controller = MouseInteractionSessionController(startMotionTap: {}, stopMotionTap: {})
        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: CGPoint(x: 80, y: 44),
            mouseButton: .left
        )!

        controller.rewriteMouseInteractionEvent(event)

        XCTAssertEqual(event.type, .mouseMoved)
        XCTAssertTrue(event.flags.contains(.maskAlternate))
    }

    func testRewriteMouseInteractionEvent_withOnlyVirtualModifiers_preservesPhysicalDraggedTypeAndAppliesFlags() {
        activateVirtualModifiers([(code: 6, shortcut: "custom::56:0")])

        let controller = MouseInteractionSessionController(startMotionTap: {}, stopMotionTap: {})
        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDragged,
            mouseCursorPosition: CGPoint(x: 80, y: 44),
            mouseButton: .left
        )!

        controller.rewriteMouseInteractionEvent(event)

        XCTAssertEqual(event.type, .leftMouseDragged)
        XCTAssertTrue(event.flags.contains(.maskShift))
    }

    func testRewriteMouseInteractionEvent_withMultipleVirtualModifiers_preservesMouseMovedAndAppliesAllFlags() {
        activateVirtualModifiers([
            (code: 6, shortcut: "custom::58:0"),
            (code: 7, shortcut: "custom::56:0"),
        ])

        let controller = MouseInteractionSessionController(startMotionTap: {}, stopMotionTap: {})
        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: CGPoint(x: 90, y: 30),
            mouseButton: .left
        )!

        controller.rewriteMouseInteractionEvent(event)

        XCTAssertEqual(event.type, .mouseMoved)
        XCTAssertTrue(event.flags.contains(.maskAlternate))
        XCTAssertTrue(event.flags.contains(.maskShift))
    }

    func testRewriteMouseInteractionEvent_combinesPhysicalAndVirtualModifierFlagsOnMouseMoved() {
        activateVirtualModifiers([(code: 6, shortcut: "custom::56:0")])

        let controller = MouseInteractionSessionController(startMotionTap: {}, stopMotionTap: {})
        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: CGPoint(x: 90, y: 30),
            mouseButton: .left
        )!
        event.flags = .maskAlternate

        controller.rewriteMouseInteractionEvent(event)

        XCTAssertEqual(event.type, .mouseMoved)
        XCTAssertTrue(event.flags.contains(.maskAlternate))
        XCTAssertTrue(event.flags.contains(.maskShift))
    }

    func testRewriteMouseInteractionEvent_withMultipleVirtualModifiers_preservesPhysicalDraggedTypeAndAppliesAllFlags() {
        activateVirtualModifiers([
            (code: 6, shortcut: "custom::58:0"),
            (code: 7, shortcut: "custom::56:0"),
        ])

        let controller = MouseInteractionSessionController(startMotionTap: {}, stopMotionTap: {})
        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDragged,
            mouseCursorPosition: CGPoint(x: 100, y: 60),
            mouseButton: .left
        )!
        event.flags = .maskCommand

        controller.rewriteMouseInteractionEvent(event)

        XCTAssertEqual(event.type, .leftMouseDragged)
        XCTAssertTrue(event.flags.contains(.maskAlternate))
        XCTAssertTrue(event.flags.contains(.maskShift))
        XCTAssertTrue(event.flags.contains(.maskCommand))
    }

    func testRewriteMouseInteractionEvent_withSyntheticLeftAndMultipleVirtualModifiers_convertsMouseMovedAndAppliesAllFlags() {
        activateVirtualModifiers([
            (code: 6, shortcut: "custom::58:0"),
            (code: 7, shortcut: "custom::56:0"),
        ])

        let controller = MouseInteractionSessionController(startMotionTap: {}, stopMotionTap: {})
        _ = controller.beginSession(target: .left)

        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: CGPoint(x: 60, y: 22),
            mouseButton: .left
        )!

        controller.rewriteMouseInteractionEvent(event)

        XCTAssertEqual(event.type, .leftMouseDragged)
        XCTAssertTrue(event.flags.contains(.maskAlternate))
        XCTAssertTrue(event.flags.contains(.maskShift))
    }

    func testRefreshMotionTapState_followsSharedVirtualModifierStateWithoutLocalCache() {
        var startCount = 0
        var stopCount = 0
        let controller = MouseInteractionSessionController(
            startMotionTap: { startCount += 1 },
            stopMotionTap: { stopCount += 1 }
        )

        XCTAssertFalse(controller.isMotionTapRunning)

        activateVirtualModifiers([(code: 6, shortcut: "custom::58:0")])
        controller.refreshMotionTapState()
        XCTAssertTrue(controller.isMotionTapRunning)
        XCTAssertEqual(startCount, 1)

        InputProcessor.shared.clearActiveBindings()
        controller.refreshMotionTapState()
        XCTAssertFalse(controller.isMotionTapRunning)
        XCTAssertEqual(stopCount, 1)
    }
}

// MARK: - ButtonCore's keys tap

/// The keys tap exists only while the keyboard is needed: every transition of
/// `OnDemandKeyTap`, on doubles (a test never makes a real tap).
final class OnDemandKeyTapTests: XCTestCase {

    private final class FakeKeyTap: KeyEventTap {
        /// False: macOS no longer serves it; enabling it changes nothing.
        var runsAfterStart: Bool
        var startThrows = false
        private(set) var running = false
        private(set) var starts = 0
        private(set) var pauses = 0
        private(set) var stops = 0
        private(set) var timeoutRestarts = 0

        init(runsAfterStart: Bool) { self.runsAfterStart = runsAfterStart }

        func start() throws {
            if startThrows { throw Interceptor.InterceptorError.eventTapEnableFailed }
            starts += 1
            running = runsAfterStart
        }
        func pause() { pauses += 1; running = false }
        func stop() { stops += 1; running = false }
        func isRunning() -> Bool { return running }
        func restartAfterTimeout() { timeoutRestarts += 1 }
    }

    /// The world of one keys tap: whether the keyboard is needed, the taps it made, and the
    /// work it put off to the next turn of the main queue.
    private final class Rig {
        var needed = false
        var made: [FakeKeyTap] = []
        /// Whether each next tap runs after it was made; empty: it does.
        var runsAfterStart: [Bool] = []
        var makeThrows = false
        var scheduled: [() -> Void] = []

        private(set) lazy var tap = OnDemandKeyTap(
            makeTap: { [unowned self] in
                if self.makeThrows { throw Interceptor.InterceptorError.eventTapCreationFailed }
                let tap = FakeKeyTap(runsAfterStart: self.runsAfterStart.isEmpty ? true : self.runsAfterStart.removeFirst())
                try tap.start()
                self.made.append(tap)
                return tap
            },
            isNeeded: { [unowned self] in self.needed },
            schedule: { [unowned self] block in self.scheduled.append(block) },
            makeRetryTimer: nil
        )

        /// The next turn of the main queue.
        func runScheduled() {
            let blocks = scheduled
            scheduled = []
            blocks.forEach { $0() }
        }
    }

    /// The default: no key is bound and no button holds a modifier. The app never makes a
    /// tap on the keyboard at all.
    func testWithoutANeedNoTapIsEverMade() {
        let rig = Rig()
        rig.tap.enable()
        rig.tap.refresh()
        rig.runScheduled()
        XCTAssertEqual(rig.made.count, 0)
        XCTAssertFalse(rig.tap.hasTap)
        XCTAssertFalse(rig.tap.isRunning)
        XCTAssertTrue(rig.scheduled.isEmpty)
    }

    func testTheFirstKeyBindingMakesTheTapAndTheLastRemovedPausesIt() {
        let rig = Rig()
        rig.tap.enable()

        // The first key binding is added.
        rig.needed = true
        rig.tap.refresh()
        XCTAssertEqual(rig.made.count, 1, "at once, not on a later turn")
        XCTAssertTrue(rig.tap.isRunning)
        XCTAssertTrue(rig.made[0].isRunning())
        rig.tap.refresh()
        rig.tap.refresh()
        XCTAssertEqual(rig.made.count, 1)
        XCTAssertEqual(rig.made[0].starts, 1, "already running: nothing is started twice")

        // The last one is removed: paused on the next turn, not inside the call.
        rig.needed = false
        rig.tap.refresh()
        rig.tap.refresh()
        XCTAssertTrue(rig.made[0].isRunning(), "not inside the call: the caller may be the tap's own callback")
        XCTAssertEqual(rig.scheduled.count, 1, "one pause, however often it is asked")
        rig.runScheduled()
        XCTAssertFalse(rig.tap.isRunning)
        XCTAssertFalse(rig.made[0].isRunning())
        XCTAssertEqual(rig.made[0].pauses, 1)
        XCTAssertEqual(rig.made[0].stops, 0, "paused, kept for the next need")
        XCTAssertTrue(rig.tap.hasTap)

        // A key is bound again: the kept tap is started, no new one is made.
        rig.needed = true
        rig.tap.refresh()
        XCTAssertEqual(rig.made.count, 1)
        XCTAssertEqual(rig.made[0].starts, 2)
        XCTAssertTrue(rig.tap.isRunning)
    }

    /// A button that holds a modifier needs the keyboard while it is down. Released and
    /// pressed again before the pause ran (a double press): the tap never goes off.
    func testANeedThatIsBackBeforeThePauseRanKeepsTheTapRunning() {
        let rig = Rig()
        rig.tap.enable()
        rig.needed = true       // the button goes down
        rig.tap.refresh()
        rig.needed = false      // up
        rig.tap.refresh()
        rig.needed = true       // down again, before the main queue turned
        rig.tap.refresh()
        rig.runScheduled()
        XCTAssertTrue(rig.tap.isRunning)
        XCTAssertEqual(rig.made[0].pauses, 0)
        XCTAssertEqual(rig.made[0].starts, 1)

        // Up for good: paused. Down once more: started again at once.
        rig.needed = false
        rig.tap.refresh()
        rig.runScheduled()
        XCTAssertEqual(rig.made[0].pauses, 1)
        rig.needed = true
        rig.tap.refresh()
        XCTAssertTrue(rig.made[0].isRunning())
        XCTAssertEqual(rig.made.count, 1)
    }

    /// Pause, sleep, another user, lost access, quit: the cores stop. The tap is switched off
    /// and let go, nothing is made while they are stopped, and a start makes a new one.
    func testStoppingTheCoresLetsTheTapGoAndStartingThemMakesANewOne() {
        let rig = Rig()
        rig.needed = true
        rig.tap.refresh()
        XCTAssertEqual(rig.made.count, 0, "the cores do not run yet")

        rig.tap.enable()
        XCTAssertEqual(rig.made.count, 1, "started with the cores when a key is bound")
        rig.tap.disable()
        XCTAssertFalse(rig.tap.isRunning)
        XCTAssertFalse(rig.tap.hasTap)
        XCTAssertEqual(rig.made[0].stops, 1)
        XCTAssertFalse(rig.made[0].isRunning())

        // Paused: a binding changes, a button is pressed. Nothing is made.
        rig.tap.refresh()
        rig.tap.retryNow()
        XCTAssertEqual(rig.made.count, 1)

        // Resumed.
        rig.tap.enable()
        XCTAssertEqual(rig.made.count, 2)
        XCTAssertTrue(rig.made[1].isRunning())
        XCTAssertTrue(rig.tap.isRunning)
    }

    /// The cores stop between "no longer needed" and the pause: the pause that was put off
    /// finds nothing to do and touches nothing.
    func testAPauseThatWasPutOffDoesNothingAfterTheCoresStopped() {
        let rig = Rig()
        rig.tap.enable()
        rig.needed = true
        rig.tap.refresh()
        rig.needed = false
        rig.tap.refresh()
        rig.tap.disable()
        rig.runScheduled()
        XCTAssertEqual(rig.made[0].pauses, 0)
        XCTAssertEqual(rig.made[0].stops, 1)

        // And after a new start the put-off pause of before is gone: a fresh tap keeps running.
        rig.needed = true
        rig.tap.enable()
        rig.runScheduled()
        XCTAssertTrue(rig.made[1].isRunning())
    }

    /// A tap kept across a loss of the access can be off for good: one that is off right
    /// after it was started is replaced once.
    func testATapThatIsOffRightAfterItsStartIsReplacedOnce() {
        let rig = Rig()
        rig.tap.enable()
        rig.needed = true
        rig.tap.refresh()
        rig.needed = false
        rig.tap.refresh()
        rig.runScheduled()
        // The kept tap went stale meanwhile.
        rig.made[0].runsAfterStart = false
        rig.needed = true
        rig.tap.refresh()
        XCTAssertEqual(rig.made.count, 2)
        XCTAssertEqual(rig.made[0].stops, 1, "the stale one is let go")
        XCTAssertTrue(rig.made[1].isRunning())
        XCTAssertTrue(rig.tap.isRunning)
    }

    func testATapThatCannotRunIsTriedAgainWhileItIsNeeded() {
        let rig = Rig()
        rig.runsAfterStart = [false, false]
        rig.tap.enable()
        rig.needed = true
        rig.tap.refresh()
        XCTAssertEqual(rig.made.count, 2, "the first and one replacement")
        XCTAssertFalse(rig.tap.isRunning)
        XCTAssertFalse(rig.tap.hasTap)

        // The retry (every 5 s in the app) gets one that runs.
        rig.tap.retryNow()
        XCTAssertEqual(rig.made.count, 3)
        XCTAssertTrue(rig.tap.isRunning)
        // Running: a retry makes nothing more.
        rig.tap.retryNow()
        XCTAssertEqual(rig.made.count, 3)

        // A tap that cannot be made at all: not running, and no retry once it is not needed.
        let failing = Rig()
        failing.makeThrows = true
        failing.tap.enable()
        failing.needed = true
        failing.tap.refresh()
        XCTAssertFalse(failing.tap.isRunning)
        failing.needed = false
        failing.makeThrows = false
        failing.tap.retryNow()
        XCTAssertEqual(failing.made.count, 0)
        failing.needed = true
        failing.tap.refresh()
        XCTAssertEqual(failing.made.count, 1)
        XCTAssertTrue(failing.tap.isRunning)
    }

    /// The kept tap cannot be started (no Accessibility access any more): it is let go, and
    /// the next need makes a new one.
    func testAKeptTapThatCannotBeStartedIsLetGo() {
        let rig = Rig()
        rig.tap.enable()
        rig.needed = true
        rig.tap.refresh()
        rig.needed = false
        rig.tap.refresh()
        rig.runScheduled()
        rig.made[0].startThrows = true
        rig.needed = true
        rig.tap.refresh()
        XCTAssertFalse(rig.tap.isRunning)
        XCTAssertFalse(rig.tap.hasTap)
        XCTAssertEqual(rig.made[0].stops, 1)
        rig.tap.retryNow()
        XCTAssertEqual(rig.made.count, 2)
        XCTAssertTrue(rig.tap.isRunning)
    }

    /// macOS turned the tap off (a timeout) and the tap restarts itself: only when the
    /// keyboard is still needed. When it is not, the tap counts as paused, so the next need
    /// starts it again.
    func testARestartAfterATimeoutOnlyWhenTheKeyboardIsStillNeeded() {
        let rig = Rig()
        rig.tap.enable()
        rig.needed = true
        rig.tap.refresh()
        rig.tap.restartAfterTimeout()
        XCTAssertEqual(rig.made[0].timeoutRestarts, 1)
        XCTAssertTrue(rig.tap.isStillNeededAtRestart())
        XCTAssertTrue(rig.tap.isRunning)

        rig.needed = false
        XCTAssertFalse(rig.tap.isStillNeededAtRestart())
        XCTAssertFalse(rig.tap.isRunning)
        rig.needed = true
        rig.tap.refresh()
        XCTAssertEqual(rig.made[0].starts, 2, "started again by the next need")
        XCTAssertTrue(rig.tap.isRunning)

        // Stopped cores never restart it.
        rig.tap.disable()
        XCTAssertFalse(rig.tap.isStillNeededAtRestart())
    }

    /// The app's own tap: off under XCTest (the cores never start), whatever is bound.
    func testTheAppsKeysTapIsNeverMadeUnderXCTest() {
        XCTAssertFalse(ButtonCore.shared.isActive)
        XCTAssertFalse(ButtonCore.shared.keyTap.isEnabled)
        ButtonCore.shared.keyTap.refresh()
        XCTAssertFalse(ButtonCore.shared.keyTap.hasTap)
    }
}

/// ButtonCore's own part around its two event taps, on doubles: the start and the stop, and
/// what its callbacks do when macOS turns a tap off. (What the keys tap does with its need
/// is OnDemandKeyTapTests'; what a button or key event does is InputProcessorTests'.)
/// Each of these was found unprotected by breaking the code: no restart after a timeout,
/// and a stop that released nothing, both went unnoticed.
final class ButtonCoreTapTests: XCTestCase {

    private final class FakeTap: KeyEventTap {
        var starts = 0
        var pauses = 0
        var stops = 0
        var timeoutRestarts = 0
        private var running = true
        func start() throws { starts += 1; running = true }
        func pause() { pauses += 1; running = false }
        func stop() { stops += 1; running = false }
        func isRunning() -> Bool { return running }
        func restartAfterTimeout() { timeoutRestarts += 1 }
    }

    private struct CannotMakeTap: Error {}

    private let core = ButtonCore.shared
    private var originalMakeButtonsTap: ((ButtonCore) throws -> KeyEventTap)!
    private var originalKeyTap: OnDemandKeyTap!
    private var originalOnInvalidate: (() -> Void)?
    private var originalBindings: [ButtonBinding] = []
    private var buttonTaps: [FakeTap] = []
    private var keyTaps: [FakeTap] = []
    private var keyboardNeeded = false

    override func setUp() {
        super.setUp()
        XCTAssertFalse(core.isActive, "the cores never start under XCTest")
        originalMakeButtonsTap = core.makeButtonsTap
        originalKeyTap = core.keyTap
        originalOnInvalidate = ButtonUtils.shared.onInvalidate
        originalBindings = Options.shared.buttons.binding
        buttonTaps = []
        keyTaps = []
        keyboardNeeded = false
        core.makeButtonsTap = { [unowned self] _ in
            let tap = FakeTap()
            self.buttonTaps.append(tap)
            return tap
        }
        core.keyTap = OnDemandKeyTap(
            makeTap: { [unowned self] in
                let tap = FakeTap()
                self.keyTaps.append(tap)
                return tap
            },
            isNeeded: { [unowned self] in self.keyboardNeeded },
            schedule: { $0() },
            makeRetryTimer: nil
        )
        ShortcutExecutor.shared.setTestingMouseEventObserver()
        ShortcutExecutor.shared.setTestingKeyboardShortcutObserver()
        InputProcessor.shared.clearActiveBindings()
    }

    override func tearDown() {
        core.disable()
        core.dispatchInterceptor = nil
        core.makeButtonsTap = originalMakeButtonsTap
        core.keyTap = originalKeyTap
        ButtonUtils.shared.onInvalidate = originalOnInvalidate
        InputProcessor.shared.clearActiveBindings()
        ShortcutExecutor.shared.clearTestingMouseEventObserver()
        ShortcutExecutor.shared.clearTestingKeyboardShortcutObserver()
        Options.shared.buttons.binding = originalBindings
        ButtonUtils.shared.invalidateCache()
        super.tearDown()
    }

    /// A side button that stands for Shift, held.
    private func holdAModifierButton() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        Options.shared.buttons.binding = [ButtonBinding(triggerEvent: trigger, systemShortcutName: "custom::56:0", isEnabled: true)]
        ButtonUtils.shared.invalidateCache()
        let down = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(down), .consumed)
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, KeyCode.getKeyMask(56).rawValue)
    }

    func testEnablingMakesTheButtonsTapAndTheKeysTapOnlyWhenTheKeyboardIsNeeded() {
        core.enable()
        XCTAssertTrue(core.isActive)
        XCTAssertEqual(buttonTaps.count, 1)
        XCTAssertTrue(core.dispatchInterceptor === buttonTaps[0])
        XCTAssertTrue(core.keyTap.isEnabled)
        XCTAssertTrue(keyTaps.isEmpty, "no key is bound: nothing listens to the keyboard")

        core.enable()
        XCTAssertEqual(buttonTaps.count, 1, "a second enable makes no second tap")

        // A binding changes: the keys tap follows it from the moment the core runs.
        keyboardNeeded = true
        ButtonUtils.shared.invalidateCache()
        XCTAssertEqual(keyTaps.count, 1)
        XCTAssertTrue(core.keyTap.isRunning)
    }

    /// A stop releases what the buttons hold and leaves no tap behind: a modifier a side
    /// button stood for stayed down after Pause or sleep otherwise, and "never leave a tap
    /// installed while the cores count as stopped" is the rule of AGENTS.md.
    func testDisablingStopsBothTapsAndReleasesWhatIsHeld() {
        keyboardNeeded = true
        core.enable()
        XCTAssertEqual(keyTaps.count, 1)
        holdAModifierButton()

        core.disable()

        XCTAssertFalse(core.isActive)
        XCTAssertNil(core.dispatchInterceptor)
        XCTAssertEqual(buttonTaps[0].stops, 1, "the buttons tap is stopped")
        XCTAssertEqual(keyTaps[0].stops, 1, "the keys tap is stopped and let go")
        XCTAssertFalse(core.keyTap.hasTap)
        XCTAssertFalse(core.keyTap.isEnabled)
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, 0, "the held modifier is released")

        core.disable()
        XCTAssertEqual(buttonTaps[0].stops, 1, "a second stop does nothing")
    }

    func testACoreWhoseTapCannotBeMadeDoesNotCountAsRunning() {
        core.makeButtonsTap = { _ in throw CannotMakeTap() }
        core.enable()
        XCTAssertFalse(core.isActive)
        XCTAssertNil(core.dispatchInterceptor)
        XCTAssertFalse(core.keyTap.isEnabled, "no keys tap without the buttons tap")
    }

    /// macOS turns a tap off when a callback took too long. The callback that hears of it
    /// switches the tap on again at once (through the tap's throttle) and releases what was
    /// held; "disabled by user input" (the app's own stop) restarts nothing.
    func testTheButtonsTapIsSwitchedOnAgainRightAfterATimeout() throws {
        let proxy = CGEventTapProxy(bitPattern: 1)!
        let event = try XCTUnwrap(CGEvent(source: nil))
        core.enable()
        holdAModifierButton()

        XCTAssertNotNil(core.buttonEventCallBack(proxy, .tapDisabledByTimeout, event, nil), "the event itself passes")
        XCTAssertEqual(buttonTaps[0].timeoutRestarts, 1)
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, 0, "what was held is released")

        holdAModifierButton()
        XCTAssertNotNil(core.buttonEventCallBack(proxy, .tapDisabledByUserInput, event, nil))
        XCTAssertEqual(buttonTaps[0].timeoutRestarts, 1, "the app's own stop restarts nothing")
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, 0)
    }

    func testTheKeysTapIsSwitchedOnAgainRightAfterATimeout() throws {
        let proxy = CGEventTapProxy(bitPattern: 1)!
        let event = try XCTUnwrap(CGEvent(source: nil))
        keyboardNeeded = true
        core.enable()
        XCTAssertEqual(keyTaps.count, 1)

        XCTAssertNotNil(core.keyEventCallBack(proxy, .tapDisabledByTimeout, event, nil))
        XCTAssertEqual(keyTaps[0].timeoutRestarts, 1)
        XCTAssertEqual(buttonTaps[0].timeoutRestarts, 0, "each callback restarts its own tap")

        XCTAssertNotNil(core.keyEventCallBack(proxy, .tapDisabledByUserInput, event, nil))
        XCTAssertEqual(keyTaps[0].timeoutRestarts, 1, "its own pause restarts nothing")
    }
}
