//
//  ShortcutRingControllerTests.swift
//  ScrollioTests
//
//  The Shortcut Ring from its trigger to its action: the controller with a screen that
//  only remembers, the hooks in InputProcessor, and the panel's own settings. No panel is
//  ever shown, no event is posted and no timer runs: the tests move the clock themselves.
//

import XCTest
@testable import Scrollio_Debug

/// A screen for the ring that only remembers what it was asked.
final class RingPresenterDouble: ShortcutRingPresenting {
    var onButton: ((Int, Bool, CGPoint) -> Void)?
    var log: (String) -> Void = { _ in }
    private(set) var shown: [(face: ShortcutRingFace, centre: CGPoint, screen: ShortcutRingScreen, lit: Int?, takesClicks: Bool)] = []
    private(set) var lit: [Int?] = []
    private(set) var takesClicks: Bool?
    private(set) var hides = 0

    func show(_ face: ShortcutRingFace, centre: CGPoint, screen: ShortcutRingScreen, lit: Int?, takesClicks: Bool) {
        shown.append((face, centre, screen, lit, takesClicks))
        self.takesClicks = takesClicks
        log("show")
    }

    func light(_ place: Int?) {
        lit.append(place)
    }

    func setTakesClicks(_ takesClicks: Bool) {
        self.takesClicks = takesClicks
    }

    func hide() {
        hides += 1
        log("hide")
    }

    /// The window that stands for the ring's own panel.
    var ownWindow: NSWindow?

    func owns(_ window: NSWindow?) -> Bool {
        return window != nil && window === ownWindow
    }
}

/// A controller whose every need is the test's: the clock, the pointer, the queue.
final class RingHarness {
    let presenter = RingPresenterDouble()
    private(set) var controller: ShortcutRingController!

    var now: TimeInterval = 100
    var pointer = CGPoint(x: 700, y: 500)
    var screen = ShortcutRingScreen(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        usable: CGRect(x: 0, y: 32, width: 1512, height: 950)
    )
    var primaryButtonDown = false
    /// Gestures › Haptic feedback.
    var hapticsAllowed = true
    var ring = ShortcutRingSettings.default
    /// What happened, in order: "show", "hide", "run copy", "pulse lockIn 1000" …
    private(set) var log: [String] = []
    private(set) var motionTapRefreshes = 0
    private(set) var keyTapRefreshes = 0
    private(set) var announced: [String] = []
    /// The lines for the `app` log.
    private(set) var logLines: [String] = []
    private(set) var problems: [String] = []
    /// How often the controller started to hear of clicks in other apps, and which of
    /// those it ended.
    private(set) var clickWatches = 0
    private(set) var stoppedClickWatches: [String] = []
    private var scheduled: [() -> Void] = []
    /// What was asked to run after a delay, with the time it is due.
    private var delayed: [(due: TimeInterval, block: () -> Void)] = []

    /// Runs what was asked to run after a delay and is due by now.
    func runDelayed() {
        let due = delayed.filter { $0.due <= now }
        delayed.removeAll { $0.due <= now }
        due.forEach { $0.block() }
    }

    init() {
        presenter.log = { [unowned self] in self.log.append($0) }
        let environment = ShortcutRingController.Environment(
            now: { [unowned self] in self.now },
            pointerLocation: { [unowned self] in self.pointer },
            screen: { [unowned self] _ in self.screen },
            isPrimaryButtonDown: { [unowned self] in self.primaryButtonDown },
            schedule: { [unowned self] in self.scheduled.append($0) },
            scheduleAfter: { [unowned self] delay, block in self.delayed.append((self.now + delay, block)) },
            makeTimer: { _, _ in nil },
            ring: { [unowned self] in self.ring },
            run: { [unowned self] in self.log.append("run \(ShortcutRingController.logName(of: $0))") },
            allowsHaptics: { [unowned self] in self.hapticsAllowed },
            playHaptic: { [unowned self] cue, code in self.log.append("pulse \(cue) \(code)") },
            announce: { [unowned self] in self.announced.append($0) },
            refreshMotionTap: { [unowned self] in self.motionTapRefreshes += 1 },
            refreshKeyTap: { [unowned self] in self.keyTapRefreshes += 1 },
            log: { [unowned self] in self.logLines.append($0) },
            logProblem: { [unowned self] in self.problems.append($0) },
            watchClicksElsewhere: { [unowned self] _ in
                self.clickWatches += 1
                return "watch \(self.clickWatches)"
            },
            // (weak: a controller that goes with its harness ends its listening on the way)
            stopWatchingClicksElsewhere: { [weak self] in self?.stoppedClickWatches.append($0 as? String ?? "") }
        )
        controller = ShortcutRingController(environment: environment, presenter: presenter)
    }

    /// Runs what was put on the "next turn of the main queue", and what that put there.
    func runScheduled() {
        while !scheduled.isEmpty {
            let blocks = scheduled
            scheduled = []
            blocks.forEach { $0() }
        }
    }

    var hasScheduledWork: Bool {
        return !scheduled.isEmpty
    }

    func clearLog() {
        log = []
    }

    static func button(_ phase: InputPhase, code: UInt16 = 4, overHIDPP: Bool = false) -> InputEvent {
        if overHIDPP {
            return InputEvent(type: .mouse, code: code, modifiers: [], phase: phase, source: .hidPP, device: nil)
        }
        let type: CGEventType = phase == .down ? .otherMouseDown : .otherMouseUp
        let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: CGPoint(x: 700, y: 500), mouseButton: .center)!
        event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(code))
        return InputEvent(fromCGEvent: event)
    }

    /// Press and release without movement: the ring stands open.
    func tap() {
        controller.triggerPressed(by: Self.button(.down))
        controller.triggerReleased(isMadeUp: false)
        runScheduled()
    }

    /// The hand moves by `total` in small steps, `later` after what came before (by
    /// default well after the press).
    func moveHand(by total: CGPoint, after later: TimeInterval = 0.3) {
        now += later
        let steps = max(1, Int((hypot(total.x, total.y) / 8).rounded(.up)))
        for _ in 0..<steps {
            let delta = CGPoint(x: total.x / CGFloat(steps), y: total.y / CGFloat(steps))
            pointer = CGPoint(x: pointer.x + delta.x, y: pointer.y + delta.y)
            controller.pointerMoved(by: delta, to: pointer)
        }
    }

    func place(_ index: Int) -> CGPoint {
        let offset = ShortcutRingGeometry.offset(ofPlace: index)
        let centre = controller.session.centre
        return CGPoint(x: centre.x + offset.x, y: centre.y + offset.y)
    }
}

// MARK: - The controller

final class ShortcutRingControllerTests: XCTestCase {

    private var harness: RingHarness!
    private var controller: ShortcutRingController { return harness.controller }

    override func setUp() {
        super.setUp()
        harness = RingHarness()
    }

    override func tearDown() {
        harness = nil
        super.tearDown()
    }

    /// The press comes inside an event callback: the panel is shown on the next turn of
    /// the main queue, with the stored ring, on the pointer's screen, not taking clicks.
    func testThePressShowsTheRingOnTheNextTurn() {
        controller.triggerPressed(by: RingHarness.button(.down))
        XCTAssertTrue(controller.isOpen)
        XCTAssertTrue(controller.isHeld)
        XCTAssertTrue(harness.presenter.shown.isEmpty, "nothing is shown inside the callback")
        harness.runScheduled()
        let shown = try? XCTUnwrap(harness.presenter.shown.first)
        XCTAssertEqual(harness.presenter.shown.count, 1)
        XCTAssertEqual(shown?.centre, CGPoint(x: 700, y: 500))
        XCTAssertEqual(shown?.screen, harness.screen)
        XCTAssertEqual(shown?.takesClicks, false, "held: a click is not the ring's")
        XCTAssertEqual(shown?.face.places.map { $0.title }.first, SystemShortcut.missionControl.localizedName)
        XCTAssertEqual(shown?.face.filled, Array(repeating: true, count: 8))
    }

    func testHoldMoveAndLetGoRunsThePlaceAfterTheRingIsGone() {
        controller.triggerPressed(by: RingHarness.button(.down))
        harness.runScheduled()
        harness.moveHand(by: CGPoint(x: -50, y: 50))
        XCTAssertEqual(harness.presenter.lit.last, 5)
        harness.clearLog()

        controller.triggerReleased(isMadeUp: false)
        XCTAssertEqual(harness.log, ["hide"], "the ring is taken off the screen at once; nothing has run yet")
        XCTAssertFalse(controller.isOpen)
        harness.runScheduled()
        XCTAssertEqual(harness.log, ["hide", "run copy"])
    }

    /// A press without movement leaves the ring open; the pointer's place lights by where
    /// it is (no event tap: the timer looks), and a click on the panel chooses.
    func testPressThenPointAndClick() {
        harness.tap()
        XCTAssertTrue(controller.isOpen)
        XCTAssertFalse(controller.isHeld)
        XCTAssertEqual(harness.presenter.takesClicks, true, "now the panel takes the mouse")

        harness.pointer = harness.place(3)
        harness.now += 0.5
        controller.tick()
        XCTAssertEqual(harness.presenter.lit.last, 3)

        harness.clearLog()
        harness.presenter.onButton?(0, true, harness.place(3))
        XCTAssertEqual(harness.log, [], "nothing happens while the button is down")
        harness.presenter.onButton?(0, false, harness.place(3))
        XCTAssertEqual(harness.log, ["hide"])
        harness.runScheduled()
        XCTAssertEqual(harness.log, ["hide", "run paste"])
    }

    func testAClickOutsideClosesAndRunsNothing() {
        harness.tap()
        harness.clearLog()
        harness.presenter.onButton?(0, true, CGPoint(x: 1300, y: 200))
        harness.presenter.onButton?(0, false, CGPoint(x: 1300, y: 200))
        harness.runScheduled()
        XCTAssertEqual(harness.log, ["hide"])
        XCTAssertFalse(controller.isOpen)
    }

    func testAnEmptyPlaceRunsNothing() {
        harness.ring[2] = .empty
        controller.triggerPressed(by: RingHarness.button(.down))
        harness.runScheduled()
        XCTAssertEqual(harness.presenter.shown.first?.face.filled[2], false)
        harness.moveHand(by: CGPoint(x: 60, y: 0))
        XCTAssertTrue(harness.presenter.lit.isEmpty, "an empty place does not light")
        controller.triggerReleased(isMadeUp: false)
        harness.runScheduled()
        XCTAssertFalse(harness.log.contains { $0.hasPrefix("run") })
    }

    /// The ring opens with what is stored at that moment, and a change made while it is
    /// open does not change what a place runs.
    func testTheRingIsReadWhenItOpens() {
        harness.ring[2] = ShortcutRingPlace(SystemShortcut.undo)
        controller.triggerPressed(by: RingHarness.button(.down))
        harness.runScheduled()
        harness.ring[2] = ShortcutRingPlace(SystemShortcut.quitApp)
        harness.moveHand(by: CGPoint(x: 60, y: 0))
        controller.triggerReleased(isMadeUp: false)
        harness.runScheduled()
        XCTAssertEqual(harness.log.last, "run undo")

        // The next ring shows the new one.
        harness.pointer = CGPoint(x: 700, y: 500)
        harness.tap()
        XCTAssertEqual(harness.presenter.shown.last?.face.places[2].title, SystemShortcut.quitApp.localizedName)
    }

    func testInTheMiddleOfADragTheRingStaysAway() {
        harness.primaryButtonDown = true
        controller.triggerPressed(by: RingHarness.button(.down))
        harness.runScheduled()
        XCTAssertFalse(controller.isOpen)
        XCTAssertTrue(harness.presenter.shown.isEmpty)
        controller.triggerReleased(isMadeUp: false)
        XCTAssertFalse(controller.isOpen)
    }

    /// A press and a cancel in the same turn: the show that was waiting is dropped.
    func testAShowForARingThatIsGoneIsDropped() {
        controller.triggerPressed(by: RingHarness.button(.down))
        controller.cancel()
        harness.runScheduled()
        XCTAssertTrue(harness.presenter.shown.isEmpty)
        XCTAssertEqual(harness.presenter.hides, 1)
    }

    /// A hand that moved 30 points in the first moments and stopped: its place lights the
    /// moment those are over, by a look of its own, not at the timer's next one (a release
    /// in between would leave the ring open where the place should run).
    func testAHandThatStoppedShortLightsItsPlaceTheMomentTheFirstMomentsAreOver() {
        controller.triggerPressed(by: RingHarness.button(.down))
        harness.runScheduled()
        harness.moveHand(by: CGPoint(x: 0, y: 30), after: 0.1)
        XCTAssertTrue(harness.presenter.lit.isEmpty)
        harness.now += 0.09
        harness.runDelayed()
        XCTAssertTrue(harness.presenter.lit.isEmpty, "not before the fifth of a second is over")
        harness.now += 0.02
        harness.runDelayed()
        XCTAssertEqual(harness.presenter.lit.last, 4, "without a tick of the timer")
        controller.triggerReleased(isMadeUp: false)
        harness.runScheduled()
        XCTAssertEqual(harness.log.last, "run appExpose")

        // The look of a ring that is gone does nothing to the next one.
        harness.pointer = CGPoint(x: 700, y: 500)
        controller.triggerPressed(by: RingHarness.button(.down))
        controller.cancel()
        controller.triggerPressed(by: RingHarness.button(.down))
        harness.now += 0.3
        harness.runDelayed()
        XCTAssertTrue(controller.isHeld)
    }

    // MARK: The taps follow the ring

    /// The pointer-movement tap is asked for exactly while the trigger is held, and the
    /// keys tap (Esc) exactly while a ring is open.
    func testTheMotionTapFollowsTheHoldAndTheKeysTapTheOpenRing() {
        XCTAssertFalse(controller.needsKeys)
        controller.triggerPressed(by: RingHarness.button(.down))
        XCTAssertTrue(controller.isHeld)
        XCTAssertTrue(controller.needsKeys)
        XCTAssertEqual(harness.motionTapRefreshes, 1)
        XCTAssertEqual(harness.keyTapRefreshes, 1)

        controller.triggerReleased(isMadeUp: false)   // nothing lit: it stands open
        XCTAssertFalse(controller.isHeld, "an open ring reads no pointer event")
        XCTAssertTrue(controller.needsKeys)
        XCTAssertEqual(harness.motionTapRefreshes, 2)
        XCTAssertEqual(harness.keyTapRefreshes, 1)

        XCTAssertTrue(controller.escapePressed())
        XCTAssertFalse(controller.isOpen)
        XCTAssertTrue(controller.needsKeys, "until Esc is up")
        XCTAssertTrue(controller.escapeReleased())
        XCTAssertFalse(controller.needsKeys)
        XCTAssertEqual(harness.keyTapRefreshes, 2)
        XCTAssertFalse(controller.escapePressed(), "Esc without a ring is the app's")
    }

    // MARK: Giving up

    func testAnOpenRingClosesAfterTenSecondsWithoutMovement() {
        harness.tap()
        controller.tick()
        harness.clearLog()
        harness.now += 9.5
        controller.tick()
        XCTAssertTrue(controller.isOpen)
        // The pointer moved a little: the ten seconds start again.
        harness.pointer.x += 3
        controller.tick()
        harness.now += 9.5
        controller.tick()
        XCTAssertTrue(controller.isOpen)
        harness.now += 0.6
        controller.tick()
        XCTAssertFalse(controller.isOpen)
        harness.runScheduled()
        XCTAssertEqual(harness.log, ["hide"], "nothing runs")
    }

    func testAHeldRingWhoseReleaseNeverComesClosesAndRunsNothing() {
        controller.triggerPressed(by: RingHarness.button(.down))
        harness.runScheduled()
        harness.moveHand(by: CGPoint(x: 60, y: 0))
        harness.clearLog()
        harness.now += ShortcutRingSession.holdLimit
        controller.tick()
        XCTAssertFalse(controller.isOpen)
        controller.triggerReleased(isMadeUp: false)
        harness.runScheduled()
        XCTAssertEqual(harness.log, ["hide"])
    }

    /// A panel covers one screen and takes no focus: when another app comes to the front,
    /// or the Space or the screens change, the ring goes.
    func testAnotherAppASpaceOrAScreenChangeClosesTheRing() {
        let changes: [(NotificationCenter, Notification.Name)] = [
            (NSWorkspace.shared.notificationCenter, NSWorkspace.didActivateApplicationNotification),
            (NSWorkspace.shared.notificationCenter, NSWorkspace.activeSpaceDidChangeNotification),
            (NotificationCenter.default, NSApplication.didChangeScreenParametersNotification),
        ]
        for (center, name) in changes {
            harness.tap()
            XCTAssertTrue(controller.isOpen)
            harness.clearLog()
            center.post(name: name, object: nil)
            XCTAssertFalse(controller.isOpen, name.rawValue)
            harness.runScheduled()
            XCTAssertEqual(harness.log, ["hide"], name.rawValue)
        }
    }

    /// A click that went to another app while the ring stands open (on another screen,
    /// where the panel is not) closes the ring. Clicks elsewhere are heard of only while a
    /// ring stands open.
    func testAClickThatWentToAnotherAppClosesTheRingAndRunsNothing() {
        controller.triggerPressed(by: RingHarness.button(.down))
        XCTAssertEqual(harness.clickWatches, 0, "held: nothing listens to the Mac's clicks")
        controller.clickWentElsewhere()
        XCTAssertTrue(controller.isOpen, "a click during a hold is not the ring's business")
        controller.triggerReleased(isMadeUp: false)
        harness.runScheduled()
        XCTAssertEqual(harness.clickWatches, 1, "the ring stands open: now it does")

        harness.pointer = CGPoint(x: 2400, y: 300)   // on a screen to the right
        harness.clearLog()
        controller.clickWentElsewhere()
        harness.runScheduled()
        XCTAssertFalse(controller.isOpen)
        XCTAssertEqual(harness.log, ["hide"])
        XCTAssertEqual(harness.stoppedClickWatches, ["watch 1"], "and with the ring the listening ends")
        XCTAssertTrue(harness.problems.isEmpty)
    }

    /// The panel should take every click on its screen. If one reaches the app under the
    /// ring all the same, the ring closes without running the place under the pointer
    /// (the app got a click the user meant for the ring), and the log says so, once.
    func testAClickThePanelDidNotTakeClosesTheRingAndIsLogged() {
        for _ in 0..<2 {
            harness.pointer = CGPoint(x: 700, y: 500)
            harness.tap()
            harness.pointer = harness.place(3)
            harness.clearLog()
            controller.clickWentElsewhere()
            harness.runScheduled()
            XCTAssertFalse(controller.isOpen)
            XCTAssertEqual(harness.log, ["hide"], "the place under the pointer does not run")
        }
        XCTAssertEqual(harness.problems.count, 1)
        XCTAssertTrue(harness.problems.first?.contains("the panel did not take it") ?? false)
    }

    /// A place moved to another Space, or opened an app: the notification of that change
    /// can arrive when the next ring is already held (the trigger pressed again to go one
    /// further). For a second after a place ran, such a change does not close a ring.
    func testTheEchoOfWhatAPlaceJustDidDoesNotCloseTheNextRing() {
        let workspace = NSWorkspace.shared.notificationCenter
        controller.triggerPressed(by: RingHarness.button(.down))
        harness.runScheduled()
        harness.moveHand(by: CGPoint(x: 60, y: 0))
        controller.triggerReleased(isMadeUp: false)
        harness.runScheduled()
        XCTAssertEqual(harness.log.last, "run moveSpaceRight")

        harness.now += 0.3
        harness.pointer = CGPoint(x: 700, y: 500)
        controller.triggerPressed(by: RingHarness.button(.down))
        workspace.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        workspace.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        XCTAssertTrue(controller.isHeld, "the Space change of the place that just ran")
        // The screens changing is no such echo.
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        XCTAssertFalse(controller.isOpen)

        // A second later a Space change is the user's again.
        controller.triggerPressed(by: RingHarness.button(.down))
        harness.now += ShortcutRingController.quietAfterRun
        workspace.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        XCTAssertFalse(controller.isOpen)
    }

    /// A click in a window of Scrollio's own (its Settings on another screen) closes an
    /// open ring too; a click on the ring's own panel is the panel's to report.
    func testAClickInAWindowOfScrolliosOwnClosesTheRingButNotOneOnThePanel() {
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: [.borderless], backing: .buffered, defer: true)
        let settings = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: [.borderless], backing: .buffered, defer: true)
        panel.isReleasedWhenClosed = false
        settings.isReleasedWhenClosed = false
        harness.presenter.ownWindow = panel
        harness.tap()
        harness.pointer = CGPoint(x: 2400, y: 300)
        controller.clickWentElsewhere(in: panel)
        XCTAssertTrue(controller.isOpen, "the panel's own click")
        controller.clickWentElsewhere(in: settings)
        XCTAssertFalse(controller.isOpen)
        XCTAssertTrue(harness.problems.isEmpty)
    }

    // MARK: Pulses

    /// Only a button that arrived over HID++ has a mouse to pulse: a light pulse when a
    /// place lights, a firmer one when its action runs.
    func testPulsesForAButtonOverHIDPP() {
        controller.triggerPressed(by: RingHarness.button(.down, code: 1006, overHIDPP: true))
        harness.runScheduled()
        harness.moveHand(by: CGPoint(x: 0, y: -50))
        harness.runScheduled()
        XCTAssertEqual(harness.log.filter { $0.hasPrefix("pulse") }, ["pulse lockIn 1006"])
        harness.now += 0.5
        controller.triggerReleased(isMadeUp: false)
        harness.runScheduled()
        XCTAssertEqual(harness.log.suffix(3), ["hide", "pulse commit 1006", "run missionControl"])
    }

    /// The pulses of a hold have one switch, Gestures › Haptic feedback: with it off the
    /// ring asks no mouse for a pulse (a cue can switch a mouse's haptics on).
    func testNoPulseWhileHapticFeedbackIsOffUnderGestures() {
        harness.hapticsAllowed = false
        controller.triggerPressed(by: RingHarness.button(.down, code: 1006, overHIDPP: true))
        harness.runScheduled()
        harness.moveHand(by: CGPoint(x: 0, y: -50))
        controller.triggerReleased(isMadeUp: false)
        harness.runScheduled()
        XCTAssertEqual(harness.log.last, "run missionControl")
        XCTAssertFalse(harness.log.contains { $0.hasPrefix("pulse") })
    }

    func testNoPulseForAPlainButtonOrAKey() {
        controller.triggerPressed(by: RingHarness.button(.down))
        harness.runScheduled()
        harness.moveHand(by: CGPoint(x: 0, y: -50))
        controller.triggerReleased(isMadeUp: false)
        harness.runScheduled()
        XCTAssertFalse(harness.log.contains { $0.hasPrefix("pulse") })
    }

    /// A sweep round the ring lights eight places within a moment: the pulses do not queue
    /// up behind the hand. One at most every `tickSpacing`; the others are dropped.
    func testLightPulsesAreSpacedAndTheOthersDropped() {
        controller.triggerPressed(by: RingHarness.button(.down, code: 1006, overHIDPP: true))
        harness.runScheduled()
        harness.moveHand(by: CGPoint(x: 0, y: -60))          // top
        for step in [CGPoint(x: 60, y: 0), CGPoint(x: 0, y: 60), CGPoint(x: 0, y: 60)] {
            harness.moveHand(by: step, after: 0.01)           // the whole sweep in a few hundredths
        }
        harness.runScheduled()
        XCTAssertGreaterThan(harness.presenter.lit.count, 2, "several places were lit")
        XCTAssertEqual(harness.log.filter { $0.hasPrefix("pulse") }.count, 1)

        harness.moveHand(by: CGPoint(x: -120, y: 0), after: ShortcutRingController.tickSpacing)
        harness.runScheduled()
        XCTAssertEqual(harness.log.filter { $0.hasPrefix("pulse") }.count, 2, "after the spacing the next place pulses again")
    }

    /// The ring takes no focus, so the lit action is said to VoiceOver.
    func testTheLitActionIsAnnounced() {
        controller.triggerPressed(by: RingHarness.button(.down))
        harness.runScheduled()
        harness.moveHand(by: CGPoint(x: 0, y: -50))
        harness.runScheduled()
        XCTAssertEqual(harness.announced, [SystemShortcut.missionControl.localizedName])
    }

    /// The `app` log gets a few lines per use of the ring, none per pointer event: what
    /// opened it, that it was left open, and how it closed.
    func testTheLogSaysWhatTheRingDid() {
        harness.tap()
        harness.pointer = harness.place(3)
        harness.now += 0.5
        controller.tick()
        harness.presenter.onButton?(0, true, harness.place(3))
        harness.presenter.onButton?(0, false, harness.place(3))
        XCTAssertEqual(harness.logLines, [
            "Shortcut Ring: opened by a mouse button",
            "Shortcut Ring: left open (the trigger was let go with nothing lit)",
            "Shortcut Ring: closed, ran paste",
        ])
        controller.triggerPressed(by: RingHarness.button(.down, code: 1006, overHIDPP: true))
        harness.moveHand(by: CGPoint(x: 0, y: -60))
        harness.moveHand(by: CGPoint(x: 0, y: 55))
        controller.triggerReleased(isMadeUp: false)
        XCTAssertEqual(harness.logLines.suffix(2), ["Shortcut Ring: opened by a button over HID++", "Shortcut Ring: closed, nothing ran"])
    }

    /// A place's shortcut is sent as one press, through the executor the buttons use.
    func testRunningAShortcutSendsItsKey() {
        var sent: [(CGKeyCode, UInt64)] = []
        ShortcutExecutor.shared.setTestingKeyboardShortcutObserver { code, flags, _ in sent.append((code, flags)) }
        defer { ShortcutExecutor.shared.clearTestingKeyboardShortcutObserver() }
        ShortcutRingController.run(ShortcutRingPlace(SystemShortcut.screenshot))
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?.0, SystemShortcut.screenshot.code)
        XCTAssertEqual(sent.first?.1, UInt64(SystemShortcut.screenshot.modifiers.rawValue))
    }

    /// A recorded key combination is pressed and let go: one key down with its modifiers,
    /// then its key up, marked as Scrollio's own so that no tap of the app takes it for
    /// a key the user pressed.
    func testRunningAKeyCombinationPressesAndReleasesIt() {
        let saved = ShortcutExecutor.shared.post
        defer { ShortcutExecutor.shared.post = saved }
        var posted: [CGEvent] = []
        ShortcutExecutor.shared.post = { posted.append($0) }
        let flags = CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue
        ShortcutRingController.run(ShortcutRingPlace(action: ButtonBinding.normalizedCustomBindingName(code: 40, modifiers: flags)))
        XCTAssertEqual(posted.map { $0.type }, [.keyDown, .keyUp])
        XCTAssertEqual(posted.map { $0.getIntegerValueField(.keyboardEventKeycode) }, [40, 40])
        XCTAssertEqual((posted.first?.flags.rawValue ?? 0) & flags, flags)
        for event in posted {
            XCTAssertEqual(event.getIntegerValueField(.eventSourceUserData), ScrollioEventMarker.syntheticCustom)
        }
        // A place that runs nothing posts nothing.
        posted = []
        ShortcutRingController.run(.empty)
        ShortcutRingController.run(ShortcutRingPlace(action: "mouseLeftClick"))
        XCTAssertTrue(posted.isEmpty)
    }

    /// Choosing a place that opens an app goes the way a button's "Open App or File…"
    /// goes (the executor, which opens nothing under XCTest), and the log names the kind
    /// of thing, never its path or the keys of a combination.
    func testAPlaceThatOpensAnAppOrSendsAKeyCombinationRunsAndIsLoggedByItsKind() {
        let notes = OpenTargetPayload(path: "/Applications/Notes.app", bundleID: "com.apple.Notes", arguments: "", kind: .application)
        harness.ring[0] = ShortcutRingPlace(openTarget: notes)
        harness.ring[2] = ShortcutRingPlace(action: "custom::40:1179648")
        controller.triggerPressed(by: RingHarness.button(.down))
        harness.runScheduled()
        XCTAssertEqual(harness.presenter.shown.first?.face.filled, Array(repeating: true, count: 8))
        harness.moveHand(by: CGPoint(x: 0, y: -60))
        controller.triggerReleased(isMadeUp: false)
        harness.runScheduled()
        XCTAssertEqual(harness.log.suffix(2), ["hide", "run an app to open"])
        XCTAssertEqual(harness.logLines.last, "Shortcut Ring: closed, ran an app to open")

        harness.pointer = CGPoint(x: 700, y: 500)
        controller.triggerPressed(by: RingHarness.button(.down))
        harness.runScheduled()
        harness.moveHand(by: CGPoint(x: 60, y: 0))
        controller.triggerReleased(isMadeUp: false)
        harness.runScheduled()
        XCTAssertEqual(harness.log.last, "run a recorded key combination")
        XCTAssertFalse(harness.logLines.contains { $0.contains("Notes") || $0.contains("custom::") })
        XCTAssertEqual(ShortcutRingController.logName(of: ShortcutRingPlace(openTarget: OpenTargetPayload(
            path: "/Users/someone/bin/sync.sh", bundleID: nil, arguments: "", kind: .script
        ))), "a script")
    }
}

// MARK: - Through InputProcessor

final class ShortcutRingInputTests: XCTestCase {

    private var harness: RingHarness!
    private var controller: ShortcutRingController { return harness.controller }
    private var savedBindings: [ButtonBinding] = []

    override func setUp() {
        super.setUp()
        savedBindings = Options.shared.buttons.binding
        Options.shared.buttons.binding = []
        ButtonUtils.shared.invalidateCache()
        MouseInteractionSessionController.shared.setTestingMotionTapHooks()
        ShortcutExecutor.shared.setTestingKeyboardShortcutObserver()
        ShortcutExecutor.shared.setTestingMouseEventObserver()
        InputProcessor.shared.clearActiveBindings()
        harness = RingHarness()
        ShortcutRingController.setTestingController(harness.controller)
    }

    override func tearDown() {
        InputProcessor.shared.clearActiveBindings()
        ShortcutRingController.setTestingController(nil)
        harness = nil
        MouseInteractionSessionController.shared.clearAllSessions()
        MouseInteractionSessionController.shared.clearTestingMotionTapHooks()
        ShortcutExecutor.shared.clearTestingKeyboardShortcutObserver()
        ShortcutExecutor.shared.clearTestingMouseEventObserver()
        Options.shared.buttons.binding = savedBindings
        ButtonUtils.shared.invalidateCache()
        super.tearDown()
    }

    private static let ringKeyFlags: CGEventFlags = [.maskControl, .maskAlternate]
    private static let ringKey: UInt16 = 49   // Space

    private func bind(button: UInt16? = nil, key: Bool = false, others: [(UInt16, String)] = []) {
        var bindings: [ButtonBinding] = []
        if let button {
            bindings.append(ButtonBinding(
                triggerEvent: RecordedEvent(type: .mouse, code: button, modifiers: 0, deviceFilter: nil),
                systemShortcutName: SystemShortcut.shortcutRing.identifier
            ))
        }
        if key {
            bindings.append(ButtonBinding(
                triggerEvent: RecordedEvent(type: .keyboard, code: Self.ringKey, modifiers: UInt(Self.ringKeyFlags.rawValue), deviceFilter: nil),
                systemShortcutName: SystemShortcut.shortcutRing.identifier
            ))
        }
        for (code, action) in others {
            bindings.append(ButtonBinding(
                triggerEvent: RecordedEvent(type: .mouse, code: code, modifiers: 0, deviceFilter: nil),
                systemShortcutName: action
            ))
        }
        Options.shared.buttons.binding = bindings
        ButtonUtils.shared.invalidateCache()
    }

    private func key(_ code: UInt16, down: Bool, flags: CGEventFlags = [], repeating: Bool = false) -> InputEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: down)!
        event.flags = flags
        if repeating {
            event.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        }
        return InputEvent(fromCGEvent: event)
    }

    private func process(_ event: InputEvent) -> InputResult {
        return InputProcessor.shared.process(event)
    }

    // MARK: Nobody who has not bound it pays

    /// Without a binding the press passes as before and no ring is ever made.
    func testWithoutABindingNothingHappensAndNoRingIsMade() {
        ShortcutRingController.setTestingController(nil)
        XCTAssertNil(ShortcutRingController.existing)
        XCTAssertEqual(process(RingHarness.button(.down)), .passthrough)
        XCTAssertEqual(process(RingHarness.button(.up)), .passthrough)
        XCTAssertEqual(process(key(53, down: true)), .passthrough, "Esc is the app's")
        XCTAssertEqual(process(key(53, down: false)), .passthrough)
        bind(others: [(4, SystemShortcut.copy.identifier)])
        XCTAssertEqual(process(RingHarness.button(.down)), .consumed)
        XCTAssertEqual(process(RingHarness.button(.up)), .consumed)
        XCTAssertNil(ShortcutRingController.existing, "another action makes no ring either")
        XCTAssertFalse(InputProcessor.shared.hasHeldShortcutRing)
        XCTAssertFalse(InputProcessor.shared.needsKeyEvents)
    }

    // MARK: The three kinds of trigger

    func testAMouseButtonOpensTheRingAndItsPressAndReleaseAreTaken() {
        bind(button: 4)
        XCTAssertEqual(process(RingHarness.button(.down)), .consumed)
        XCTAssertTrue(controller.isHeld)
        XCTAssertTrue(InputProcessor.shared.hasHeldShortcutRing)
        XCTAssertEqual(process(RingHarness.button(.up)), .consumed)
        XCTAssertTrue(controller.isOpen, "no movement: the ring stands open")
        XCTAssertFalse(InputProcessor.shared.hasHeldShortcutRing)
    }

    func testAButtonOverHIDPPOpensTheRingAndAMadeUpReleaseClosesIt() {
        bind(button: 1006)
        XCTAssertEqual(process(RingHarness.button(.down, code: 1006, overHIDPP: true)), .consumed)
        XCTAssertTrue(controller.isHeld)
        harness.runScheduled()
        harness.moveHand(by: CGPoint(x: 60, y: 0))
        harness.clearLog()
        // The mouse went to sleep mid-hold.
        let madeUp = InputEvent(type: .mouse, code: 1006, modifiers: [], phase: .up, source: .hidPP, device: nil, isSyntheticRelease: true)
        XCTAssertEqual(process(madeUp), .consumed)
        harness.runScheduled()
        XCTAssertFalse(controller.isOpen)
        XCTAssertFalse(harness.log.contains { $0.hasPrefix("run") }, "the lit place does not run")
    }

    /// A key combination that is held: its repeats are the ring's, also once the modifiers
    /// are let go (they no longer match the binding and would type into the document), and
    /// so is its release.
    func testAHeldKeyCombinationOpensTheRingAndTypesNothing() {
        bind(key: true)
        XCTAssertEqual(process(key(Self.ringKey, down: true, flags: Self.ringKeyFlags)), .consumed)
        XCTAssertTrue(controller.isHeld)
        XCTAssertEqual(process(key(Self.ringKey, down: true, flags: Self.ringKeyFlags, repeating: true)), .consumed)
        XCTAssertTrue(controller.isHeld, "a repeat neither closes the ring nor opens another")
        // ⌃⌥ are let go first; Space still repeats, now without them.
        XCTAssertEqual(process(key(Self.ringKey, down: true, repeating: true)), .consumed)
        XCTAssertEqual(process(key(Self.ringKey, down: true)), .consumed)
        XCTAssertTrue(controller.isHeld)
        XCTAssertEqual(process(key(Self.ringKey, down: false)), .consumed)
        XCTAssertFalse(controller.isHeld)
        XCTAssertTrue(controller.isOpen)
        // The key is free again.
        XCTAssertEqual(process(key(Self.ringKey, down: true)), .passthrough, "Space alone is a space")
        XCTAssertEqual(process(key(Self.ringKey, down: false)), .passthrough)
    }

    /// A repeat is looked at first: a key held from before it was bound opens nothing.
    func testARepeatNeverOpensTheRing() {
        bind(key: true)
        XCTAssertEqual(process(key(Self.ringKey, down: true, flags: Self.ringKeyFlags, repeating: true)), .consumed)
        XCTAssertFalse(controller.isOpen)
    }

    /// What Logi Options+ can send from a button it manages: a keystroke, down and up at
    /// once. The ring opens and stays open; the same keystroke again closes it.
    func testAKeystrokeSentAsDownAndUpAtOnceOpensAndThenClosesTheRing() {
        bind(key: true)
        XCTAssertEqual(process(key(Self.ringKey, down: true, flags: Self.ringKeyFlags)), .consumed)
        XCTAssertEqual(process(key(Self.ringKey, down: false, flags: Self.ringKeyFlags)), .consumed)
        harness.runScheduled()
        XCTAssertTrue(controller.isOpen)
        XCTAssertEqual(harness.presenter.takesClicks, true)

        XCTAssertEqual(process(key(Self.ringKey, down: true, flags: Self.ringKeyFlags)), .consumed)
        XCTAssertFalse(controller.isOpen)
        XCTAssertEqual(process(key(Self.ringKey, down: false, flags: Self.ringKeyFlags)), .consumed, "the up of the press that closed it")
        XCTAssertFalse(controller.isOpen, "it does not open again")
    }

    // MARK: The hand's movement

    /// While the trigger is held the pointer-movement tap runs and its deltas choose.
    func testTheMotionTapsDeltasChooseWhileHeld() {
        var started = 0, stopped = 0
        MouseInteractionSessionController.shared.setTestingMotionTapHooks(start: { started += 1 }, stop: { stopped += 1 })
        harness = RingHarness()   // one whose taps are the app's
        var environment = harness.controller.environment
        environment.refreshMotionTap = { MouseInteractionSessionController.shared.refreshMotionTapState() }
        harness.controller.environment = environment
        ShortcutRingController.setTestingController(harness.controller)
        bind(button: 4)

        XCTAssertEqual(process(RingHarness.button(.down)), .consumed)
        XCTAssertEqual(started, 1, "the tap is switched on for the hold")
        harness.now += 0.5
        for _ in 0..<8 {
            let motion = CGEvent(mouseEventSource: nil, mouseType: .otherMouseDragged, mouseCursorPosition: CGPoint(x: 700, y: 500), mouseButton: .center)!
            motion.setDoubleValueField(.mouseEventDeltaX, value: 0)
            motion.setDoubleValueField(.mouseEventDeltaY, value: 8)
            MouseInteractionSessionController.shared.handleMotionTapEventForTests(motion)
        }
        XCTAssertEqual(controller.session.lit, 4, "down on the screen is the bottom place")
        harness.now += 0.5
        XCTAssertEqual(process(RingHarness.button(.up)), .consumed)
        XCTAssertEqual(stopped, 1, "and off again with it")
        harness.runScheduled()
        XCTAssertEqual(harness.log.last, "run appExpose")
    }

    // MARK: Esc

    func testEscClosesAnOpenRingAndGoesNoFurther() {
        bind(button: 4)
        XCTAssertFalse(InputProcessor.shared.needsKeyEvents, "a mouse-only user has no keys tap")
        _ = process(RingHarness.button(.down))
        XCTAssertTrue(InputProcessor.shared.needsKeyEvents, "while a ring is open Esc must arrive")
        _ = process(RingHarness.button(.up))
        XCTAssertTrue(InputProcessor.shared.needsKeyEvents)

        XCTAssertEqual(process(key(53, down: true)), .consumed)
        XCTAssertFalse(controller.isOpen)
        XCTAssertEqual(process(key(53, down: false)), .consumed, "its release is the ring's too")
        XCTAssertFalse(InputProcessor.shared.needsKeyEvents)
        XCTAssertEqual(process(key(53, down: true)), .passthrough)
        XCTAssertEqual(process(key(53, down: false)), .passthrough)
        // Another key passes while a ring is open.
        _ = process(RingHarness.button(.down))
        XCTAssertEqual(process(key(0, down: true)), .passthrough)
        XCTAssertTrue(controller.isOpen)
    }

    // MARK: What closes the ring and runs nothing

    func testStoppingTheTapsClosesTheRingAndRunsNothing() {
        bind(button: 4)
        _ = process(RingHarness.button(.down))
        harness.runScheduled()
        harness.moveHand(by: CGPoint(x: 60, y: 0))
        harness.clearLog()
        InputProcessor.shared.clearActiveBindings()
        harness.runScheduled()
        XCTAssertFalse(controller.isOpen)
        XCTAssertEqual(harness.log, ["hide"])
        XCTAssertFalse(InputProcessor.shared.hasHeldShortcutRing)
        // The release that comes after all is not the ring's any more.
        XCTAssertEqual(process(RingHarness.button(.up)), .passthrough)
    }

    func testAnotherButtonsActionClosesTheRing() {
        bind(button: 4, others: [(3, SystemShortcut.copy.identifier)])
        _ = process(RingHarness.button(.down))
        _ = process(RingHarness.button(.up))
        XCTAssertTrue(controller.isOpen)
        harness.clearLog()
        XCTAssertEqual(process(RingHarness.button(.down, code: 3)), .consumed)
        XCTAssertFalse(controller.isOpen)
        harness.runScheduled()
        XCTAssertEqual(harness.log, ["hide"], "the ring ran nothing")
    }

    /// A release that never came: the ring gave up after its limit, and the next press of
    /// the button is a new one, not "the held trigger again".
    func testAfterALostReleaseTheNextPressOpensANewRing() {
        bind(button: 4)
        _ = process(RingHarness.button(.down))
        harness.now += ShortcutRingSession.holdLimit
        controller.tick()
        XCTAssertFalse(controller.isOpen)
        XCTAssertEqual(process(RingHarness.button(.down)), .consumed)
        XCTAssertTrue(controller.isHeld)
        XCTAssertEqual(process(RingHarness.button(.up)), .consumed)
    }

    /// Esc held a moment longer than a tap repeats: every Esc down until its release is
    /// the ring's, or the app in front would get Esc after all (a full-screen video would
    /// leave full screen).
    func testEscHeldAfterItClosedTheRingDoesNotReachTheApp() {
        bind(button: 4)
        _ = process(RingHarness.button(.down))
        _ = process(RingHarness.button(.up))
        XCTAssertTrue(controller.isOpen)
        XCTAssertEqual(process(key(53, down: true)), .consumed)
        XCTAssertFalse(controller.isOpen)
        XCTAssertEqual(process(key(53, down: true, repeating: true)), .consumed)
        XCTAssertEqual(process(key(53, down: true, repeating: true)), .consumed)
        XCTAssertEqual(process(key(53, down: false)), .consumed)
        XCTAssertEqual(process(key(53, down: true)), .passthrough, "the next Esc is the app's")
        XCTAssertEqual(process(key(53, down: false)), .passthrough)
        // An Esc that was held before the ring opened does not close it by repeating.
        _ = process(RingHarness.button(.down))
        XCTAssertEqual(process(key(53, down: true, repeating: true)), .passthrough)
        XCTAssertTrue(controller.isOpen)
    }

    /// Esc closed the ring and its release never came (the keys tap timed out, secure
    /// keyboard entry began): the next press of Esc is a new one and the app's, not one
    /// more Esc that does nothing.
    func testAfterALostEscReleaseTheNextEscIsTheApps() {
        bind(button: 4)
        _ = process(RingHarness.button(.down))
        _ = process(RingHarness.button(.up))
        XCTAssertEqual(process(key(53, down: true)), .consumed)
        XCTAssertTrue(InputProcessor.shared.needsKeyEvents, "its release is awaited")
        XCTAssertEqual(process(key(53, down: true)), .passthrough, "a fresh press: the release was lost")
        XCTAssertFalse(InputProcessor.shared.needsKeyEvents)
        XCTAssertEqual(process(key(53, down: true, repeating: true)), .passthrough)
        XCTAssertEqual(process(key(53, down: false)), .passthrough)
    }

    /// Two triggers bound. The button's release got lost and the ring gave up: the key
    /// trigger still opens a ring (it is "a second trigger during a hold" only while a
    /// ring really is held).
    func testAfterALostReleaseTheOtherTriggerStillWorks() {
        bind(button: 4, key: true)
        _ = process(RingHarness.button(.down))
        harness.now += ShortcutRingSession.holdLimit
        controller.tick()
        XCTAssertFalse(controller.isOpen)
        for attempt in 1...3 {
            XCTAssertEqual(process(key(Self.ringKey, down: true, flags: Self.ringKeyFlags)), .consumed)
            XCTAssertTrue(controller.isOpen, "press \(attempt) of the key trigger")
            XCTAssertEqual(process(key(Self.ringKey, down: false, flags: Self.ringKeyFlags)), .consumed)
            controller.cancel()
        }
    }

    /// A key trigger pressed while a button trigger holds the ring is kept like the ring's
    /// own: its repeats, also once the modifiers are let go, and its release are taken.
    func testASecondKeyTriggerHeldDuringAHoldTypesNothing() {
        bind(button: 4, key: true)
        _ = process(RingHarness.button(.down))
        XCTAssertEqual(process(key(Self.ringKey, down: true, flags: Self.ringKeyFlags)), .consumed)
        XCTAssertEqual(process(key(Self.ringKey, down: true, flags: Self.ringKeyFlags, repeating: true)), .consumed)
        XCTAssertEqual(process(key(Self.ringKey, down: true, repeating: true)), .consumed, "a repeat without the modifiers")
        XCTAssertEqual(process(key(Self.ringKey, down: false)), .consumed, "its key-up")
        XCTAssertTrue(controller.isHeld, "the button still holds the ring")
        XCTAssertEqual(process(RingHarness.button(.up)), .consumed)
        XCTAssertFalse(controller.isHeld)
        XCTAssertEqual(process(key(Self.ringKey, down: true)), .passthrough, "the key is free again")
    }

    /// The taps were restarted while a key held the ring: the ring is gone, but the key
    /// is still down and repeats; until it is up it stays the ring's and types nothing.
    func testAfterTheTapsRestartedTheHeldTriggerKeyTypesNothing() {
        bind(key: true)
        _ = process(key(Self.ringKey, down: true, flags: Self.ringKeyFlags))
        XCTAssertTrue(controller.isHeld)
        InputProcessor.shared.clearActiveBindings()
        XCTAssertFalse(controller.isOpen)
        XCTAssertTrue(InputProcessor.shared.needsKeyEvents, "its key-up must still arrive")
        XCTAssertEqual(process(key(Self.ringKey, down: true, repeating: true)), .consumed)
        XCTAssertEqual(process(key(Self.ringKey, down: false)), .consumed)
        XCTAssertFalse(controller.isOpen)
        // The next real press starts over.
        XCTAssertEqual(process(key(Self.ringKey, down: true, flags: Self.ringKeyFlags)), .consumed)
        XCTAssertTrue(controller.isHeld)
        XCTAssertEqual(process(key(Self.ringKey, down: false)), .consumed)
    }

    /// Two triggers bound, the second pressed while the first is held: it is taken whole
    /// and means nothing; the first one's release still ends the hold.
    func testASecondTriggerDuringAHoldIsTakenAndMeansNothing() {
        bind(button: 4, key: true)
        _ = process(RingHarness.button(.down))
        XCTAssertEqual(process(key(Self.ringKey, down: true, flags: Self.ringKeyFlags)), .consumed)
        XCTAssertTrue(controller.isHeld)
        XCTAssertEqual(process(key(Self.ringKey, down: false, flags: Self.ringKeyFlags)), .consumed)
        XCTAssertTrue(controller.isHeld)
        XCTAssertEqual(process(RingHarness.button(.up)), .consumed)
        XCTAssertFalse(controller.isHeld)
    }
}

// MARK: - The panel

final class ShortcutRingPanelTests: XCTestCase {

    /// The settings that decide whether the ring is seen at all, and that it never takes
    /// the keyboard from the app in front.
    func testThePanelNeverTakesFocusAndShowsEverywhere() {
        let panel = ShortcutRingPanel.make()
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.styleMask.contains(.titled))
        XCTAssertFalse(panel.hidesOnDeactivate, "a panel's default hides it whenever Scrollio is not the active app")
        XCTAssertEqual(panel.level, .popUpMenu, "above the menu bar, the Dock and open menus")
        XCTAssertTrue(panel.collectionBehavior.isSuperset(of: [.canJoinAllSpaces, .fullScreenAuxiliary]))
        XCTAssertFalse(panel.isOpaque)
        XCTAssertFalse(panel.hasShadow)
        XCTAssertTrue(panel.ignoresMouseEvents, "until the ring stands open")
        XCTAssertFalse(panel.isVisible)
    }

    /// Nothing of the ring makes Scrollio the active app or a window key.
    func testNoSourceOfTheRingActivatesTheAppOrMakesAWindowKey() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let folder = root.appendingPathComponent("Scrollio/Ring", isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".swift") }
        XCTAssertGreaterThanOrEqual(files.count, 5)
        for file in files {
            let code = try String(contentsOf: folder.appendingPathComponent(file), encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.drop(while: { $0 == " " }).hasPrefix("//") }
                .joined(separator: "\n")
            for call in ["activate(", "makeKey", "makeMain", "orderFront(nil)", "makeFirstResponder"] {
                XCTAssertFalse(code.contains(call), "\(file) calls \(call)")
            }
        }
    }

    /// A ring shown by a presenter nobody prepared puts no window on the screen of whoever
    /// runs the tests.
    func testARingPutsNoWindowOnScreenUnderXCTest() throws {
        let presenter = ShortcutRingPanelPresenter()
        presenter.appearance = { ShortcutRingAppearance(reducesMotion: true) }
        let screen = ShortcutRingScreen(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982), usable: CGRect(x: 0, y: 0, width: 1512, height: 982)
        )
        presenter.show(ShortcutRingFace(.default), centre: CGPoint(x: 400, y: 300), screen: screen, lit: nil, takesClicks: true)
        XCTAssertFalse(try XCTUnwrap(presenter.panel).isVisible)
        presenter.hide()
    }

    private func shown(
        appearance: ShortcutRingAppearance = ShortcutRingAppearance(),
        takesClicks: Bool = false
    ) -> (ShortcutRingPanelPresenter, [NSPanel]) {
        let presenter = ShortcutRingPanelPresenter()
        var ordered: [NSPanel] = []
        presenter.orderFront = { ordered.append($0) }
        presenter.appearance = { appearance }
        let screen = ShortcutRingScreen(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            usable: CGRect(x: 0, y: 32, width: 1512, height: 950)
        )
        presenter.show(ShortcutRingFace(.default), centre: CGPoint(x: 400, y: 300), screen: screen, lit: nil, takesClicks: takesClicks)
        return (presenter, ordered)
    }

    func testShowingCoversThePointersScreenAndPutsTheRingAtItsPlace() throws {
        let (presenter, ordered) = shown()
        let panel = try XCTUnwrap(presenter.panel)
        let stage = try XCTUnwrap(presenter.stage)
        XCTAssertEqual(ordered.count, 1)
        XCTAssertTrue(ordered.first === panel)
        XCTAssertEqual(panel.frame.size, CGSize(width: 1512, height: 982))
        // 300 points from the top of the screen is 682 from its bottom.
        XCTAssertEqual(stage.ringCentre, CGPoint(x: 400, y: 682))
        XCTAssertEqual(stage.material.frame.midX, 400, accuracy: 0.5)
        XCTAssertEqual(stage.material.frame.midY, 682, accuracy: 0.5)
        XCTAssertEqual(stage.material.frame.width, ShortcutRingGeometry.outerRadius * 2)
        XCTAssertEqual(stage.material.state, .active, "a window that is never key would show the inactive grey")
        XCTAssertEqual(stage.faceView.frame.midX, 400, accuracy: 0.5)
        XCTAssertEqual(stage.eventLocation(of: NSPoint(x: 400, y: 682)), CGPoint(x: 400, y: 300))
        XCTAssertTrue(panel.ignoresMouseEvents, "held: the mouse goes to what is underneath")
        XCTAssertFalse(stage.takesClicks)
    }

    /// Once the ring stands open the panel takes the mouse; when it goes, it lets go.
    func testAnOpenRingTakesTheMouseAndAHiddenOneLetsGo() throws {
        let (presenter, _) = shown(takesClicks: true)
        let panel = try XCTUnwrap(presenter.panel)
        let stage = try XCTUnwrap(presenter.stage)
        XCTAssertFalse(panel.ignoresMouseEvents)
        XCTAssertTrue(stage.takesClicks)
        XCTAssertNotNil(stage.layer?.backgroundColor, "the clear part is filled, almost invisibly")
        XCTAssertTrue(stage.acceptsFirstMouse(for: nil), "the first click on a window that is not key counts")
        XCTAssertGreaterThan(ShortcutRingStageView.clickFillAlpha, 0.004, "a pixel without alpha lets a click through")
        XCTAssertLessThanOrEqual(ShortcutRingStageView.clickFillAlpha, 0.02)
        presenter.setTakesClicks(false)
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertNil(stage.layer?.backgroundColor)
        presenter.setTakesClicks(true)
        presenter.hide()
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertFalse(panel.isVisible)
    }

    /// A click on the panel reaches the ring in event coordinates, down and up.
    func testAClickOnThePanelIsReportedWhereItWas() throws {
        let (presenter, _) = shown(takesClicks: true)
        let panel = try XCTUnwrap(presenter.panel)
        let stage = try XCTUnwrap(presenter.stage)
        var reported: [(Int, Bool, CGPoint)] = []
        presenter.onButton = { reported.append(($0, $1, $2)) }
        func event(_ type: NSEvent.EventType) throws -> NSEvent {
            return try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: NSPoint(x: 482, y: 682), modifierFlags: [], timestamp: 0,
                windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            ))
        }
        stage.mouseDown(with: try event(.leftMouseDown))
        stage.mouseUp(with: try event(.leftMouseUp))
        stage.rightMouseDown(with: try event(.rightMouseDown))
        stage.rightMouseUp(with: try event(.rightMouseUp))
        XCTAssertEqual(reported.map { $0.0 }, [0, 0, 1, 1])
        XCTAssertEqual(reported.map { $0.1 }, [true, false, true, false])
        XCTAssertEqual(reported.first?.2, CGPoint(x: 482, y: 300))
        XCTAssertNil(stage.faceView.hitTest(NSPoint(x: 10, y: 10)), "the drawing takes no click itself")
        // On the ring and beside it, the view that is hit is the stage, which accepts the
        // first click of a window that is not key.
        XCTAssertTrue(stage.hitTest(NSPoint(x: 400, y: 682)) === stage)
        XCTAssertTrue(stage.hitTest(NSPoint(x: 400 + ShortcutRingGeometry.placeRadius, y: 682)) === stage)
        XCTAssertTrue(stage.hitTest(NSPoint(x: 1200, y: 100)) === stage)
    }

    /// The ring must be seen from the moment it takes clicks: the panel is ordered in at
    /// full alpha, always. (Faded in as a window, it stayed at alpha 0 for two seconds and
    /// more on a Mac whose display slept, while it already took the mouse.) Only layers of
    /// the drawing are animated, and their own values are the final ones.
    func testThePanelIsNeverFadedAsAWindow() throws {
        for appearance in [ShortcutRingAppearance(), ShortcutRingAppearance(reducesMotion: true)] {
            let (presenter, ordered) = shown(appearance: appearance, takesClicks: true)
            let panel = try XCTUnwrap(presenter.panel)
            let stage = try XCTUnwrap(presenter.stage)
            XCTAssertEqual(ordered.count, 1)
            XCTAssertEqual(panel.alphaValue, 1, "reducesMotion \(appearance.reducesMotion)")
            XCTAssertEqual(stage.faceView.layer?.opacity, 1)
            XCTAssertEqual(stage.shadowView.layer?.opacity, 1)
            XCTAssertFalse(stage.faceView.isHidden)
            presenter.hide()
            XCTAssertEqual(panel.alphaValue, 1)
            XCTAssertNil(stage.faceView.layer?.animation(forKey: ShortcutRingPanelPresenter.fadeAnimationKey))
        }
    }

    func testWithReduceMotionTheRingSimplyAppears() throws {
        XCTAssertEqual(ShortcutRingAppearance().openDuration, 0.12, accuracy: 0.001)
        XCTAssertEqual(ShortcutRingAppearance(reducesMotion: true).openDuration, 0)

        let (moving, _) = shown()
        XCTAssertEqual(moving.lastOpenDuration, 0.12, accuracy: 0.001)
        let face = try XCTUnwrap(moving.stage?.faceView.layer)
        XCTAssertNotNil(face.animation(forKey: ShortcutRingPanelPresenter.growAnimationKey))
        let fade = try XCTUnwrap(face.animation(forKey: ShortcutRingPanelPresenter.fadeAnimationKey) as? CABasicAnimation)
        XCTAssertEqual(fade.keyPath, "opacity")
        XCTAssertEqual(fade.duration, 0.12, accuracy: 0.001)
        XCTAssertNotNil(moving.stage?.shadowView.layer?.animation(forKey: ShortcutRingPanelPresenter.fadeAnimationKey))

        let (still, _) = shown(appearance: ShortcutRingAppearance(reducesMotion: true))
        XCTAssertEqual(still.lastOpenDuration, 0)
        XCTAssertNil(still.stage?.faceView.layer?.animation(forKey: ShortcutRingPanelPresenter.growAnimationKey))
        XCTAssertNil(still.stage?.faceView.layer?.animation(forKey: ShortcutRingPanelPresenter.fadeAnimationKey))
        XCTAssertEqual(still.panel?.alphaValue, 1)
    }

    func testReduceTransparencyAndIncreaseContrastAreFollowed() throws {
        let (plain, _) = shown(appearance: ShortcutRingAppearance(reducesTransparency: true, increasesContrast: true))
        let stage = try XCTUnwrap(plain.stage)
        XCTAssertTrue(stage.material.isHidden, "no material: a plain disc is drawn")
        XCTAssertEqual(stage.faceView.style.backdrop, .drawn)
        XCTAssertTrue(stage.faceView.style.increasesContrast)

        let (usual, _) = shown()
        XCTAssertEqual(usual.stage?.material.isHidden, false)
        XCTAssertEqual(usual.stage?.faceView.style.backdrop, .material)
    }

    /// Event coordinates grow downwards from the top of the main screen, AppKit's upwards
    /// from its bottom; a second screen above the main one has negative event y.
    func testScreenCoordinatesAreFlippedAboutTheMainScreen() {
        XCTAssertEqual(ShortcutRingScreens.flipped(CGPoint(x: 10, y: 890), mainScreenHeight: 900), CGPoint(x: 10, y: 10))
        let above = CGRect(x: 0, y: 900, width: 1920, height: 1080)   // AppKit
        XCTAssertEqual(ShortcutRingScreens.flipped(above, mainScreenHeight: 900), CGRect(x: 0, y: -1080, width: 1920, height: 1080))
        let rect = CGRect(x: 40, y: 100, width: 300, height: 200)
        XCTAssertEqual(ShortcutRingScreens.flipped(ShortcutRingScreens.flipped(rect, mainScreenHeight: 900), mainScreenHeight: 900), rect)
    }

    /// The name in the middle: one or two lines as it is; a name that needs a third gets
    /// it a little smaller instead of being cut. No offered shortcut needs more.
    func testALongNameInTheMiddleGetsAThirdLineInsteadOfBeingCut() {
        let width = ShortcutRingGeometry.hubRadius * 2 - 10
        let short = ShortcutRingArtwork.titleLayout("Copy", width: width, pointSize: 13)
        XCTAssertEqual(short.lines, 1)
        XCTAssertEqual(short.pointSize, 13)
        let two = ShortcutRingArtwork.titleLayout("Desktop on the Right", width: width, pointSize: 13)
        XCTAssertEqual(two.lines, 2)
        XCTAssertEqual(two.pointSize, 13)
        let long = ShortcutRingArtwork.titleLayout("Screenshot and Recording Options", width: width, pointSize: 13)
        XCTAssertEqual(long.lines, 3)
        XCTAssertLessThan(long.pointSize, 13)
        XCTAssertGreaterThanOrEqual(long.pointSize, 11)
        XCTAssertLessThan(long.height, ShortcutRingGeometry.hubRadius * 2 - 30, "three lines stay inside the middle")
        for category in SystemShortcut.shortcutsByCategory {
            for shortcut in category.shortcuts where ShortcutRingPlace(shortcut).runs {
                let layout = ShortcutRingArtwork.titleLayout(shortcut.localizedName, width: width, pointSize: 13)
                XCTAssertLessThanOrEqual(layout.lines, 3, shortcut.localizedName)
                let font = NSFont.systemFont(ofSize: layout.pointSize, weight: .semibold)
                for word in shortcut.localizedName.split(separator: " ") {
                    XCTAssertLessThanOrEqual((String(word) as NSString).size(withAttributes: [.font: font]).width, width, String(word))
                }
            }
        }
    }

    /// What stands on a lit place can be read on any accent colour: white on the app's
    /// purple and on blue, dark on the system's yellow.
    func testTheLitPlacesSymbolCanBeReadOnALightAccent() {
        let purple = NSColor(srgbRed: 0x56 / 255, green: 0x3C / 255, blue: 0xA6 / 255, alpha: 1)
        let darkPurple = NSColor(srgbRed: 0x6A / 255, green: 0x4E / 255, blue: 0xC2 / 255, alpha: 1)
        let blue = NSColor(srgbRed: 0, green: 0.48, blue: 1, alpha: 1)
        let yellow = NSColor(srgbRed: 1, green: 0.8, blue: 0, alpha: 1)
        for accent in [purple, darkPurple, blue] {
            XCTAssertEqual(ShortcutRingArtwork.litInk(on: accent), .white)
        }
        XCTAssertNotEqual(ShortcutRingArtwork.litInk(on: yellow), .white)
        XCTAssertLessThan(ShortcutRingArtwork.litInk(on: yellow).usingColorSpace(.sRGB)?.redComponent ?? 1, 0.2)
    }

    /// The drawing: every place has its name and something to show: a listed action its
    /// symbol, an app its icon, a key combination its keys.
    func testEveryPlaceOfTheFaceHasItsNameAndSomethingToShow() {
        var ring = ShortcutRingSettings.default
        ring[1] = ShortcutRingPlace(openTarget: OpenTargetPayload(
            path: "/System/Applications/Calculator.app", bundleID: "com.apple.calculator", arguments: "", kind: .application
        ))
        ring[2] = ShortcutRingPlace(action: "custom::40:1179648")       // ⇧⌘K
        ring[3] = .empty
        ring[4] = ShortcutRingPlace(action: "somethingNewer")
        ring[5] = ShortcutRingPlace(openTarget: OpenTargetPayload(
            path: "/Users/someone/Gone.app", bundleID: nil, arguments: "", kind: .application
        ))
        ring[6] = ShortcutRingPlace(action: "custom::96:786432")        // ⌃⌥F5
        let face = ShortcutRingFace(ring)
        XCTAssertEqual(face.places.count, 8)
        XCTAssertEqual(face.filled, [true, true, true, false, false, true, true, true])
        for place in face.places where !place.isEmpty {
            XCTAssertFalse(place.title.isEmpty)
            XCTAssertNotNil(ShortcutRingArtwork.symbolImage(named: place.symbolName, pointSize: 20, colour: .white), place.symbolName)
        }
        // An app: its icon, and its name for the middle of the ring.
        XCTAssertNotNil(face.places[1].image)
        XCTAssertFalse(face.places[1].title.isEmpty)
        XCTAssertFalse(face.places[1].title.contains("/"), "its name, not its path")
        // A key combination: its keys in the place and in the middle.
        XCTAssertNil(face.places[2].image)
        XCTAssertEqual(face.places[2].glyphs.joined(), face.places[2].title)
        XCTAssertTrue(face.places[2].title.hasPrefix("⇧⌘"), face.places[2].title)
        XCTAssertEqual(face.places[2].glyphs.count, 1, "a letter stands on the modifiers' line")
        // A key whose name is longer than a letter stands under its modifiers.
        XCTAssertEqual(face.places[6].glyphs, ["⌃⌥", "F5"])
        XCTAssertEqual(face.places[6].title, "⌃⌥F5")
        // An app that is gone: a warning sign, and its file's name.
        XCTAssertNil(face.places[5].image)
        XCTAssertEqual(face.places[5].symbolName, "exclamationmark.triangle")
        XCTAssertTrue(face.places[5].title.contains("Gone.app"))
        // A listed action: its symbol, no icon, no keys.
        XCTAssertNil(face.places[0].image)
        XCTAssertTrue(face.places[0].glyphs.isEmpty)
        XCTAssertEqual(ShortcutRingFace(places: []).places.count, 8)
    }
}
