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
    /// Whose ring each of `shown` was.
    private(set) var owners: [ShortcutRingOwner] = []
    private(set) var lit: [Int?] = []
    private(set) var takesClicks: Bool?
    private(set) var hides = 0

    func show(
        _ face: ShortcutRingFace, owner: ShortcutRingOwner, centre: CGPoint, screen: ShortcutRingScreen, lit: Int?,
        takesClicks: Bool
    ) {
        shown.append((face, centre, screen, lit, takesClicks))
        owners.append(owner)
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
    /// What the pointer was asked, in order: "lock", "unlock".
    private(set) var pointerLocks: [String] = []
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
    /// How often a place of a face was looked up on disk (an app's name and icon).
    private(set) var placesLookedUp = 0
    /// The apps whose mark was made (`makeAppMark`), by path, in order: no disk is read.
    private(set) var marksMade: [String] = []
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
            makePlace: { [unowned self] in
                self.placesLookedUp += 1
                return ShortcutRingFace.place($0)
            },
            makeAppMark: { [unowned self] path in
                self.marksMade.append(path)
                return RingHarness.mark(named: ShortcutRingAppMark.plainName(ofPath: path))
            },
            run: { [unowned self] in self.log.append("run \(ShortcutRingController.logName(of: $0))") },
            allowsHaptics: { [unowned self] in self.hapticsAllowed },
            playHaptic: { [unowned self] cue, code in self.log.append("pulse \(cue) \(code)") },
            announce: { [unowned self] in self.announced.append($0) },
            refreshMotionTap: { [unowned self] in self.motionTapRefreshes += 1 },
            lockPointer: { [unowned self] in self.pointerLocks.append("lock") },
            unlockPointer: { [unowned self] in self.pointerLocks.append("unlock") },
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

    /// Runs what is on the "next turn of the main queue" now; what that puts there waits
    /// for the turn after.
    func runOneTurn() {
        let blocks = scheduled
        scheduled = []
        blocks.forEach { $0() }
    }

    var hasScheduledWork: Bool {
        return !scheduled.isEmpty
    }

    func clearLog() {
        log = []
    }

    /// An app's mark made without a look on disk: a small square of one colour.
    static func mark(named name: String, colour: NSColor = .systemTeal) -> ShortcutRingAppMark {
        let icon = NSImage(size: NSSize(width: 40, height: 40), flipped: false) { rect in
            colour.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 3, dy: 3), xRadius: 8, yRadius: 8).fill()
            return true
        }
        return ShortcutRingAppMark(icon: icon, name: name)
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
        // No face is left from a test before (this one's own, run again, among them).
        ShortcutRingController.forgetPreparedFaces()
        harness = RingHarness()
    }

    override func tearDown() {
        harness = nil
        ShortcutRingController.forgetPreparedFaces()
        super.tearDown()
    }

    /// The press comes inside an event callback: the panel is shown on the next turn of
    /// the main queue, with the stored ring, on the pointer's screen, taking clicks (held,
    /// a click is the ring's too).
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
        XCTAssertEqual(shown?.takesClicks, true, "held: a click is the ring's")
        XCTAssertEqual(harness.presenter.takesClicks, true)
        XCTAssertEqual(shown?.face.places.map { $0.title }.first, SystemShortcut.missionControl.localizedName)
        XCTAssertEqual(shown?.face.filled, Array(repeating: true, count: 8))
    }

    /// Browsing app pages prepares the face of every ring shown. Rings that open nothing
    /// need none (their face is whole without a look on disk) and never push out the face
    /// of a ring that opens an app.
    func testRingsThatOpenNothingNeverPushOutAFaceWithAnAppsIcon() {
        var opens = ShortcutRingSettings.default
        opens[4] = ShortcutRingPlace(openTarget: OpenTargetPayload(
            path: "/System/Applications/Calculator.app", bundleID: "com.apple.calculator", arguments: "", kind: .application
        ))
        ShortcutRingController.prepare(ShortcutRingFace(opens, looksOnDisk: false), for: opens)
        for index in 0..<(ShortcutRingController.preparedFaceLimit + 3) {
            var ring = ShortcutRingSettings.default
            ring[0] = ShortcutRingPlace(action: "custom::\(index):0")
            ShortcutRingController.prepare(ShortcutRingFace(ring, looksOnDisk: false), for: ring)
        }
        XCTAssertNotNil(ShortcutRingController.preparedFace(for: opens))
        XCTAssertEqual(ShortcutRingController.preparedFaces.count, 1)
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

    // MARK: Freeze pointer while the ring is held

    /// The ring's own switch: the pointer is kept still from the press to the release and
    /// not a moment longer, and the hand's movement chooses as before.
    func testWithTheSwitchOnAHoldKeepsThePointerStillAndLetsItGoAtTheRelease() {
        harness.ring.freezePointer = true
        controller.triggerPressed(by: RingHarness.button(.down))
        XCTAssertEqual(harness.pointerLocks, ["lock"], "from the press on")
        harness.runScheduled()
        harness.moveHand(by: CGPoint(x: -50, y: 50))
        XCTAssertEqual(harness.presenter.lit.last, 5, "the hand still chooses")
        XCTAssertEqual(harness.pointerLocks, ["lock"])
        harness.clearLog()

        controller.triggerReleased(isMadeUp: false)
        XCTAssertEqual(harness.pointerLocks, ["lock", "unlock"], "free again before the action runs")
        XCTAssertEqual(harness.log, ["hide"])
        harness.runScheduled()
        XCTAssertEqual(harness.log, ["hide", "run copy"])
        XCTAssertEqual(harness.logLines.first, "Shortcut Ring: opened by a mouse button, the pointer is kept still while it is held")
    }

    /// Off, as for a new ring: nothing ever asks for the pointer, however the ring is used.
    func testWithTheSwitchOffNothingEverHoldsThePointer() {
        XCTAssertFalse(harness.ring.freezePointer)
        controller.triggerPressed(by: RingHarness.button(.down))
        harness.runScheduled()
        harness.moveHand(by: CGPoint(x: 60, y: 0))
        controller.triggerReleased(isMadeUp: false)
        harness.runScheduled()
        harness.tap()
        controller.cancel()
        XCTAssertEqual(harness.pointerLocks, [])
        XCTAssertEqual(harness.logLines.first, "Shortcut Ring: opened by a mouse button")
    }

    /// Let go with nothing lit: the ring stays open and the pointer is free for the click.
    /// The pointer stood where the press found it, whatever an event says that was made
    /// before the freeze took hold: at a screen's edge, where the ring is drawn away from
    /// the pointer, the place the pointer stands under does not light by itself.
    func testAFrozenHoldLetGoWithNothingLitLeavesTheRingOpenWithAFreePointer() {
        harness.ring.freezePointer = true
        let press = CGPoint(x: 12, y: 500)
        harness.pointer = press
        controller.triggerPressed(by: RingHarness.button(.down, overHIDPP: true))
        harness.runScheduled()
        XCTAssertEqual(ShortcutRingGeometry.target(at: press, centre: controller.session.centre), .place(6),
                       "the ring is drawn to the right of the pointer, which stands under Left")
        harness.now += 0.5
        // One event from before the freeze took hold: it shows the pointer 30 pt further down.
        controller.pointerMoved(by: CGPoint(x: 0, y: 6), to: CGPoint(x: 12, y: 530))
        XCTAssertNil(controller.session.lit)

        controller.triggerReleased(isMadeUp: false)
        XCTAssertTrue(controller.isOpen)
        XCTAssertFalse(controller.isHeld)
        XCTAssertEqual(harness.pointerLocks, ["lock", "unlock"], "the pointer is free for the click")
        XCTAssertEqual(harness.presenter.takesClicks, true)

        harness.now += 0.5
        controller.tick()
        XCTAssertNil(controller.session.lit, "the place under a pointer that never moved does not light")
        harness.pointer = harness.place(3)
        harness.now += 0.1
        controller.tick()
        XCTAssertEqual(controller.session.lit, 3, "moved by the hand, the pointer chooses")
    }

    /// Whatever ends a hold lets the pointer go.
    func testHoweverAFrozenHoldEndsThePointerIsLetGo() {
        let ends: [(String, (RingHarness) -> Void)] = [
            ("Esc", { _ = $0.controller.escapePressed() }),
            ("cancel", { $0.controller.cancel() }),
            ("a release that was made up", { $0.controller.triggerReleased(isMadeUp: true) }),
            ("the hold's limit", {
                $0.now += ShortcutRingSession.holdLimit + 1
                $0.controller.tick()
            }),
        ]
        for (name, end) in ends {
            harness = RingHarness()
            harness.ring.freezePointer = true
            controller.triggerPressed(by: RingHarness.button(.down))
            harness.runScheduled()
            XCTAssertEqual(harness.pointerLocks, ["lock"], name)
            end(harness)
            XCTAssertFalse(controller.isOpen, name)
            XCTAssertEqual(harness.pointerLocks, ["lock", "unlock"], name)
        }
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

    /// What an app's place shows takes a look on disk (the file, Launch Services, the
    /// icon). That never happens in the turn in which a ring is shown, when the taps wait
    /// on the main thread: a ring without a face made beforehand shows the app's file
    /// name and a plain symbol once, the whole face is made after it has closed, and the
    /// next ring has the icon.
    func testNoLookOnDiskInTheTurnARingIsShown() {
        ShortcutRingController.prepare(ShortcutRingFace(.default), for: .default)
        harness.ring[1] = ShortcutRingPlace(openTarget: OpenTargetPayload(
            path: "/System/Applications/Calculator.app", bundleID: "com.apple.calculator", arguments: "", kind: .application
        ))
        controller.triggerPressed(by: RingHarness.button(.down))
        harness.runScheduled()
        let first = harness.presenter.shown.last?.face.places[1]
        XCTAssertEqual(harness.placesLookedUp, 0, "shown without a look on disk")
        XCTAssertEqual(first?.title, "Calculator", "the file's name, without .app")
        XCTAssertNil(first?.image)
        XCTAssertEqual(first?.isEmpty, false)
        XCTAssertEqual(harness.presenter.shown.last?.face.filled, Array(repeating: true, count: 8))

        controller.triggerReleased(isMadeUp: false)   // nothing lit: it stands open
        XCTAssertEqual(harness.placesLookedUp, 0, "not while it stands open either")
        controller.cancel()
        harness.runScheduled()
        XCTAssertEqual(harness.placesLookedUp, 1, "after it closed")

        controller.triggerPressed(by: RingHarness.button(.down))
        harness.runScheduled()
        XCTAssertNotNil(harness.presenter.shown.last?.face.places[1].image, "the next ring has the icon")
        XCTAssertEqual(harness.placesLookedUp, 1)
        controller.cancel()
        harness.runScheduled()
        XCTAssertEqual(harness.placesLookedUp, 1, "a whole face is not made twice")
    }

    /// The face made after a ring closed is made as the faces at launch are: one place
    /// that opens something per turn of the main queue (a cold icon takes a while to draw,
    /// and the taps wait on that queue). A ring that opens meanwhile stops it: nothing is
    /// looked up while it is open, and its close begins the face again.
    func testTheFaceMadeAfterARingClosedIsMadeOnePlacePerTurn() {
        for (index, path) in [(1, "/System/Applications/Calculator.app"), (3, "/System/Applications/TextEdit.app"),
                              (6, "/System/Applications/Preview.app")] {
            harness.ring[index] = ShortcutRingPlace(openTarget: OpenTargetPayload(path: path, bundleID: nil, arguments: "", kind: .application))
        }
        harness.tap()
        XCTAssertNil(harness.presenter.shown.last?.face.places[1].image, "no face was made beforehand")
        controller.cancel()
        harness.runOneTurn()
        XCTAssertEqual(harness.placesLookedUp, 1, "one place in a turn")
        XCTAssertNil(ShortcutRingController.preparedFace(for: harness.ring), "a face is kept only when it is whole")

        controller.triggerPressed(by: RingHarness.button(.down))
        harness.runOneTurn()
        XCTAssertEqual(harness.presenter.shown.count, 2)
        XCTAssertNil(harness.presenter.shown.last?.face.places[3].image)
        controller.triggerReleased(isMadeUp: false)   // nothing lit: it stands open
        harness.runScheduled()
        XCTAssertEqual(harness.placesLookedUp, 1, "nothing is looked up while a ring is open")

        controller.cancel()
        var perTurn: [Int] = []
        while harness.hasScheduledWork {
            let before = harness.placesLookedUp
            harness.runOneTurn()
            perTurn.append(harness.placesLookedUp - before)
        }
        XCTAssertEqual(perTurn, [1, 1, 1], "begun again, one place in a turn")
        let face = ShortcutRingController.preparedFace(for: harness.ring)
        XCTAssertEqual(face?.places.map { $0.image != nil }, [false, true, false, true, false, false, true, false])

        controller.triggerPressed(by: RingHarness.button(.down))
        harness.runScheduled()
        XCTAssertNotNil(harness.presenter.shown.last?.face.places[6].image, "the next ring has the icons")
        controller.cancel()
        harness.runScheduled()
        XCTAssertEqual(harness.placesLookedUp, 4)
    }

    /// The Settings pane makes the face whenever it shows a ring, and hands it on: a ring
    /// changed there is shown with its icons at the first press.
    func testAFaceMadeAtAQuietMomentIsUsedAtThePress() {
        var ring = ShortcutRingSettings.default
        ring[4] = ShortcutRingPlace(openTarget: OpenTargetPayload(
            path: "/System/Applications/Calculator.app", bundleID: "com.apple.calculator", arguments: "", kind: .application
        ))
        ShortcutRingController.prepare(ShortcutRingFace(ring), for: ring)
        harness.ring = ring
        controller.triggerPressed(by: RingHarness.button(.down))
        harness.runScheduled()
        XCTAssertNotNil(harness.presenter.shown.last?.face.places[4].image)
        controller.cancel()
        harness.runScheduled()
        XCTAssertEqual(harness.placesLookedUp, 0)
        // A ring without anything to open needs no look on disk at all.
        XCTAssertFalse(ShortcutRingSettings.default.opensSomething)
        XCTAssertTrue(ring.opensSomething)
        XCTAssertEqual(ShortcutRingFace.plainName(of: OpenTargetPayload(path: "/Users/someone/bin/sync.sh", bundleID: nil, arguments: "", kind: .script)), "sync.sh")
    }

    // MARK: The keyboard layout changes

    /// A ring's face names its keys as the keyboard layout names them, and a place filled
    /// from a suggested shortcut is other keys on another layout, or none. So after a
    /// change of the layout the same ring is worked out again at its next press: its face,
    /// and which of its places run. (It kept the face and the keys of the layout it was
    /// first shown on until its places changed or Scrollio was started again.)
    func testAfterAChangeOfTheKeyboardLayoutTheSameRingIsWorkedOutAgain() {
        let savedLayout = ShortcutRingSuggestions.layout
        let savedLayoutID = ShortcutRingSuggestions.layoutID
        defer {
            ShortcutRingSuggestions.layout = savedLayout
            ShortcutRingSuggestions.layoutID = savedLayoutID
        }
        // Back, ⌘[, as a suggestion fills it on a US keyboard, on top.
        let command = CGEventFlags.maskCommand
        var ring = ShortcutRingSettings.default
        ring[0] = ShortcutRingPlace(
            action: ButtonBinding.normalizedCustomBindingName(code: 33, modifiers: command.rawValue),
            label: ShortcutLabel(name: "Back", icon: nil),
            suggested: .init(keys: .init(character: "[", modifiers: command))
        )
        harness.ring = ring
        ShortcutRingSuggestions.layout = { .us }
        ShortcutRingSuggestions.layoutID = { "US" }
        controller.triggerPressed(by: RingHarness.button(.down))
        harness.runScheduled()
        XCTAssertEqual(harness.presenter.shown.last?.face.places[0].title, "Back")
        XCTAssertEqual(harness.presenter.shown.last?.face.places[0].keys, "⌘[")
        XCTAssertEqual(harness.presenter.shown.last?.face.filled[0], true)
        harness.moveHand(by: CGPoint(x: 0, y: -80))
        XCTAssertEqual(harness.presenter.lit.last, .some(0), "it lights")
        controller.cancel()
        harness.runScheduled()

        // The layout types "[" only with Option now (and "]" too): the place is none there.
        var other = KeyboardLayoutLayers.us
        for code in [CGKeyCode(33), CGKeyCode(30)] {
            other.plain[code] = "š"
            other.shift[code] = "Š"
            other.command[code] = "š"
            other.commandShift[code] = "Š"
        }
        ShortcutRingSuggestions.layout = { other }
        ShortcutRingSuggestions.layoutID = { "another" }
        harness.clearLog()
        let litBefore = harness.presenter.lit.count
        controller.triggerPressed(by: RingHarness.button(.down))
        harness.runScheduled()
        XCTAssertEqual(harness.presenter.shown.count, 2)
        XCTAssertEqual(harness.presenter.shown.last?.face.places[0].isEmpty, true, "an empty place: no name, no keys")
        XCTAssertEqual(harness.presenter.shown.last?.face.places[0].keys, "")
        XCTAssertEqual(harness.presenter.shown.last?.face.filled[0], false)
        XCTAssertEqual(harness.presenter.shown.last?.face.filled[1], true, "the others as they were")
        harness.moveHand(by: CGPoint(x: 0, y: -80))
        XCTAssertFalse(harness.presenter.lit.dropFirst(litBefore).contains(.some(0)), "and it never lights")
        controller.triggerReleased(isMadeUp: false)
        harness.runScheduled()
        XCTAssertFalse(harness.log.contains { $0.hasPrefix("run") }, "nothing is sent")
        controller.cancel()
        harness.runScheduled()

        // Back on the first layout it is itself again.
        ShortcutRingSuggestions.layout = { .us }
        ShortcutRingSuggestions.layoutID = { "US" }
        controller.triggerPressed(by: RingHarness.button(.down))
        harness.runScheduled()
        XCTAssertEqual(harness.presenter.shown.last?.face.places[0].keys, "⌘[")
        XCTAssertEqual(harness.presenter.shown.last?.face.filled[0], true)
    }

    /// A face made at a quiet moment belongs to the layout it was made on: on another one
    /// it is not used (the ring is shown once without its icons and its face made again).
    func testAFaceMadeOnAnotherKeyboardLayoutIsNotUsed() {
        let savedLayoutID = ShortcutRingSuggestions.layoutID
        defer { ShortcutRingSuggestions.layoutID = savedLayoutID }
        var ring = ShortcutRingSettings.default
        ring[4] = ShortcutRingPlace(openTarget: OpenTargetPayload(
            path: "/System/Applications/Calculator.app", bundleID: "com.apple.calculator", arguments: "", kind: .application
        ))
        ShortcutRingSuggestions.layoutID = { "US" }
        ShortcutRingController.prepare(ShortcutRingFace(ring, looksOnDisk: false), for: ring)
        XCTAssertNotNil(ShortcutRingController.preparedFace(for: ring))
        ShortcutRingSuggestions.layoutID = { "another" }
        XCTAssertNil(ShortcutRingController.preparedFace(for: ring))
        XCTAssertTrue(ShortcutRingController.preparedFaces.isEmpty)
        ShortcutRingController.prepare(ShortcutRingFace(ring, looksOnDisk: false), for: ring)
        XCTAssertNotNil(ShortcutRingController.preparedFace(for: ring), "made again there, it is kept")
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

    /// A click that went to another app while the ring stands open (every screen has a
    /// panel that should have taken it: the log says so) closes the ring. Clicks elsewhere
    /// are heard of only while a ring is open: from the press on, one watch for the hold
    /// and the open ring.
    func testAClickThatWentToAnotherAppClosesTheRingAndRunsNothing() {
        XCTAssertEqual(harness.clickWatches, 0, "no ring: nothing listens to the Mac's clicks")
        controller.triggerPressed(by: RingHarness.button(.down))
        XCTAssertEqual(harness.clickWatches, 1, "held: it does")
        controller.triggerReleased(isMadeUp: false)
        harness.runScheduled()
        XCTAssertEqual(harness.clickWatches, 1, "the same watch for the ring that stands open")

        harness.pointer = CGPoint(x: 2400, y: 300)   // on a screen to the right
        harness.clearLog()
        controller.clickWentElsewhere()
        harness.runScheduled()
        XCTAssertFalse(controller.isOpen)
        XCTAssertEqual(harness.log, ["hide"])
        XCTAssertEqual(harness.stoppedClickWatches, ["watch 1"], "and with the ring the listening ends")
        XCTAssertEqual(harness.problems.count, 1, "the panel of that screen should have taken it")
    }

    /// During a hold the pointer (when it is not kept still) can reach another screen.
    /// That screen's panel takes the click there: it is the ring's, and the lit place runs
    /// at its up, once, the trigger's release running nothing more.
    func testAHeldClickOnAnotherScreenIsTheRingsAndRunsTheLitPlace() {
        controller.triggerPressed(by: RingHarness.button(.down))
        harness.runScheduled()
        harness.moveHand(by: CGPoint(x: -50, y: 50))
        XCTAssertEqual(controller.session.lit, 5)
        harness.pointer = CGPoint(x: 2400, y: 300)   // on a screen to the right
        harness.clearLog()
        harness.presenter.onButton?(0, true, harness.pointer)
        harness.presenter.onButton?(0, false, harness.pointer)
        XCTAssertFalse(controller.isOpen)
        controller.triggerReleased(isMadeUp: false)
        harness.runScheduled()
        XCTAssertEqual(harness.log, ["hide", "run copy"], "the lit place runs, once")
        XCTAssertEqual(harness.stoppedClickWatches, ["watch 1"])
    }

    /// The squeeze before the ring is on the screen: the index finger clicks as the thumb
    /// presses the trigger, the panel is not up yet (it is shown a turn after the press),
    /// and the app under the pointer gets the click. That is no panel's fault and no
    /// reason to end the hold: the ring is shown and held, and the hand and the release
    /// choose as ever. (The click closed the ring, which then never appeared.)
    func testAClickBeforeTheRingIsOnTheScreenLeavesTheHoldAsItIs() {
        controller.triggerPressed(by: RingHarness.button(.down))
        controller.clickWentElsewhere()
        XCTAssertTrue(controller.isHeld)
        harness.runScheduled()
        XCTAssertEqual(harness.presenter.shown.count, 1, "the ring is shown")
        XCTAssertTrue(controller.isHeld)
        XCTAssertTrue(harness.problems.isEmpty)

        // The same click is heard of only after the ring was shown (the show was put on
        // the main queue first): it is known by its own time, in the hold's first moments.
        let pressed = harness.now
        harness.now += 0.5
        controller.clickWentElsewhere(at: pressed + 0.03)
        XCTAssertTrue(controller.isHeld, "the squeeze, heard of late")
        XCTAssertTrue(harness.problems.isEmpty)
        harness.moveHand(by: CGPoint(x: -50, y: 50), after: 0)
        controller.triggerReleased(isMadeUp: false)
        harness.runScheduled()
        XCTAssertEqual(harness.log, ["show", "hide", "run copy"], "and the hold ends as ever")

        // A click that was made later in the hold and reached an app is the panel's miss.
        controller.triggerPressed(by: RingHarness.button(.down))
        harness.runScheduled()
        harness.now += 0.5
        controller.clickWentElsewhere(at: harness.now)
        XCTAssertFalse(controller.isOpen)
        XCTAssertEqual(harness.problems.count, 1)

        // A ring that was left open is no hold: before its pointer moved or after, a click
        // elsewhere closes it.
        controller.triggerPressed(by: RingHarness.button(.down))
        controller.triggerReleased(isMadeUp: false)
        XCTAssertTrue(controller.isOpen)
        controller.clickWentElsewhere(at: harness.now)
        XCTAssertFalse(controller.isOpen, "left open before it was shown: a click elsewhere closes it")
        harness.runScheduled()
    }

    // MARK: A click while the trigger is held

    /// The owner's hand on an MX Master 4: the thumb holds the ring's button, the index
    /// finger clicks. The click is the ring's: at its up the lit place runs (with the
    /// pointer kept still, it stands in the middle, on no place) and the pointer is let go
    /// then, not at the down; the trigger's release afterwards runs nothing more.
    func testAClickDuringAHoldRunsTheLitPlaceAtItsUpAndOnlyOnce() {
        harness.ring.freezePointer = true
        controller.triggerPressed(by: RingHarness.button(.down))
        harness.runScheduled()
        harness.moveHand(by: CGPoint(x: -50, y: 50))
        XCTAssertEqual(harness.presenter.lit.last, 5)
        harness.clearLog()

        harness.presenter.onButton?(0, true, CGPoint(x: 700, y: 500))
        XCTAssertEqual(harness.log, [], "nothing happens while the button is down")
        XCTAssertEqual(harness.pointerLocks, ["lock"])
        harness.presenter.onButton?(0, false, CGPoint(x: 700, y: 500))
        XCTAssertEqual(harness.log, ["hide"])
        XCTAssertEqual(harness.pointerLocks, ["lock", "unlock"])
        XCTAssertFalse(controller.isOpen)
        harness.runScheduled()
        XCTAssertEqual(harness.log, ["hide", "run copy"])
        XCTAssertEqual(harness.logLines.last, "Shortcut Ring: closed, ran copy (a click during the hold)")

        controller.triggerReleased(isMadeUp: false)
        harness.runScheduled()
        XCTAssertEqual(harness.log, ["hide", "run copy"], "the release runs nothing more")
        XCTAssertFalse(controller.isOpen)
    }

    /// The trigger let go before the click is up: the ring stays held (the pointer kept
    /// still, the movement still read) until the click's up, which runs the place once.
    func testATriggerLetGoBeforeTheHeldClickIsUpWaitsForTheClick() {
        harness.ring.freezePointer = true
        controller.triggerPressed(by: RingHarness.button(.down))
        harness.runScheduled()
        harness.moveHand(by: CGPoint(x: -50, y: 50))
        harness.clearLog()
        harness.presenter.onButton?(0, true, CGPoint(x: 700, y: 500))
        let refreshes = harness.motionTapRefreshes
        controller.triggerReleased(isMadeUp: false)
        XCTAssertTrue(controller.isHeld)
        XCTAssertEqual(harness.log, [])
        XCTAssertEqual(harness.pointerLocks, ["lock"])
        XCTAssertEqual(harness.motionTapRefreshes, refreshes)
        harness.moveHand(by: CGPoint(x: 60, y: 0))
        harness.presenter.onButton?(0, false, CGPoint(x: 700, y: 500))
        harness.runScheduled()
        XCTAssertEqual(harness.log, ["hide", "run copy"])
        XCTAssertEqual(harness.pointerLocks, ["lock", "unlock"])
        XCTAssertFalse(controller.isOpen)
    }

    /// With nothing lit, or with another button, a click during the hold closes the ring
    /// and runs nothing; the release then neither runs nor leaves a ring open.
    func testAClickDuringAHoldWithNothingLitOrAnotherButtonRunsNothing() {
        for (button, moves) in [(0, false), (1, true)] {
            harness = RingHarness()
            controller.triggerPressed(by: RingHarness.button(.down))
            harness.runScheduled()
            harness.now += 0.3
            if moves {
                harness.moveHand(by: CGPoint(x: -50, y: 50))
            }
            harness.clearLog()
            harness.presenter.onButton?(button, true, CGPoint(x: 700, y: 500))
            harness.presenter.onButton?(button, false, CGPoint(x: 700, y: 500))
            XCTAssertFalse(controller.isOpen, "button \(button)")
            controller.triggerReleased(isMadeUp: false)
            harness.runScheduled()
            XCTAssertEqual(harness.log, ["hide"], "button \(button)")
            XCTAssertFalse(controller.isOpen, "button \(button)")
            XCTAssertEqual(harness.logLines.last, "Shortcut Ring: closed, nothing ran (a click during the hold)")
        }
    }

    /// The squeeze: the index finger clicks as the thumb presses the trigger. A click in
    /// the first fifth of a second is taken and means nothing: the ring stays held, and
    /// the hand and the release choose as before.
    func testAClickInTheFirstMomentsOfAHoldIsTakenAndMeansNothing() {
        controller.triggerPressed(by: RingHarness.button(.down))
        harness.runScheduled()
        harness.now += 0.05
        harness.presenter.onButton?(0, true, CGPoint(x: 700, y: 500))
        harness.presenter.onButton?(0, false, CGPoint(x: 700, y: 500))
        XCTAssertTrue(controller.isHeld)
        XCTAssertEqual(harness.log, ["show"])
        harness.moveHand(by: CGPoint(x: -50, y: 50))
        controller.triggerReleased(isMadeUp: false)
        harness.runScheduled()
        XCTAssertEqual(harness.log, ["show", "hide", "run copy"])
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

    /// A click in a window of Scrollio's own (its Settings, should a panel not have taken
    /// the click) closes an open ring too; a click on the ring's own panel is the panel's
    /// to report.
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

// MARK: - The app's icon in the middle of its own ring

final class ShortcutRingAppMarkTests: XCTestCase {

    private typealias FrontApp = ShortcutRingChoice.FrontApp

    private static let notes = "/System/Applications/Notes.app"
    private static let calculator = "/System/Applications/Calculator.app"
    private static let ringAction = SystemShortcut.shortcutRing.identifier

    private var harness: RingHarness!
    private var controller: ShortcutRingController { return harness.controller }
    private var front: FrontApp?
    private var applications = EnhanceArray<Application>(withArray: [], matchKey: "path")

    private static func list(_ applications: [Application]) -> EnhanceArray<Application> {
        return EnhanceArray<Application>(withArray: applications, matchKey: "path")
    }

    /// An app on the list with a ring of its own (a copy of a new ring).
    private static func ownRing(_ path: String) -> Application {
        let application = Application(path: path)
        application.setUsesGeneralRing(false, general: .default)
        return application
    }

    private static func opensTheRing(code: UInt16 = 4) -> ButtonBinding {
        return ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: code, modifiers: 0, deviceFilter: nil),
            systemShortcutName: ringAction, isEnabled: true
        )
    }

    override func setUp() {
        super.setUp()
        ShortcutRingController.forgetPreparedFaces()
        harness = RingHarness()
        front = nil
        applications = Self.list([Self.ownRing(Self.notes), Application(path: Self.calculator)])
        controller.environment.choice = { [unowned self] general in
            ShortcutRingChoice.make(front: self.front, applications: self.applications, general: general)
        }
    }

    override func tearDown() {
        harness = nil
        ShortcutRingController.forgetPreparedFaces()
        super.tearDown()
    }

    // MARK: Which ring has one

    /// The choice carries the stored path of the app's entry for its own ring only; the
    /// owner of a ring is the general ring, or the app with its mark when one was made.
    func testOnlyAnAppsOwnRingHasAnAppAndItsPathIsTheEntrys() {
        let program = Self.notes + "/Contents/MacOS/Notes"
        let own = ShortcutRingChoice.make(
            front: FrontApp(bundlePath: nil, executablePath: program),
            applications: Self.list([Self.ownRing(program)]), general: .default
        )
        XCTAssertEqual(own.appPath, program, "the entry's path, as stored")
        for front in [FrontApp(bundlePath: Self.calculator, executablePath: nil), FrontApp(bundlePath: "/Applications/Other.app"), nil] {
            let general = ShortcutRingChoice.make(front: front, applications: applications, general: .default)
            XCTAssertNil(general.appPath)
            XCTAssertEqual(ShortcutRingController.owner(of: general), .general)
        }
        XCTAssertNil(ShortcutRingChoice(ring: .default, isAppsOwn: false, appPath: Self.notes).appPath, "never for the general ring")

        XCTAssertEqual(ShortcutRingController.owner(of: own), .app(name: "Notes", icon: nil), "no mark made: the name in its path")
        let mark = RingHarness.mark(named: "Notes (made)")
        ShortcutRingController.prepare(mark, forAppAt: program)
        XCTAssertEqual(ShortcutRingController.owner(of: own), .app(name: "Notes (made)", icon: mark.icon))

        XCTAssertEqual(ShortcutRingAppMark.plainName(ofPath: "/Applications/Safari.app"), "Safari")
        XCTAssertEqual(ShortcutRingAppMark.plainName(ofPath: program), "Notes")
        XCTAssertEqual(ShortcutRingAppMark.plainName(ofPath: "/usr/local/bin/tool"), "tool")
    }

    /// Nothing is loaded when the ring opens: an app's own ring whose mark was not made
    /// shows an empty middle (and is named by its path), its mark is made after it closed,
    /// and the next ring has the icon. The general ring never has one, also when marks of
    /// apps are there.
    /// The panel never becomes key, so VoiceOver hears whose ring opened from the announce
    /// path (round 2 fix Y8): an app's own ring says "Shortcut Ring for Notes" once, when it
    /// shows and before the place it lights; the general ring says nothing of its own.
    func testAnAppsOwnRingIsAnnouncedOnceWhenItShows() {
        front = FrontApp(bundlePath: Self.notes, executablePath: nil)
        controller.triggerPressed(by: RingHarness.button(.down))
        XCTAssertTrue(harness.announced.isEmpty, "not before it shows")
        harness.runScheduled()
        XCTAssertEqual(harness.announced, ["Shortcut Ring for Notes"])
        harness.moveHand(by: CGPoint(x: 0, y: -50))
        harness.runScheduled()
        XCTAssertEqual(harness.announced.count, 2, "then the lit place")
        controller.triggerReleased(isMadeUp: false)
        harness.runScheduled()
        XCTAssertEqual(harness.announced.filter { $0 == "Shortcut Ring for Notes" }.count, 1, "once")

        let before = harness.announced.count
        front = FrontApp(bundlePath: Self.calculator, executablePath: nil)
        controller.triggerPressed(by: RingHarness.button(.down))
        harness.runScheduled()
        XCTAssertEqual(harness.presenter.owners.last, .general)
        XCTAssertEqual(harness.announced.count, before, "the general ring: nothing")
        controller.cancel()
        harness.runScheduled()
    }

    func testNothingIsLoadedAtTheOpenAndTheMarkIsMadeAfterTheRingClosed() {
        front = FrontApp(bundlePath: Self.notes, executablePath: nil)
        controller.triggerPressed(by: RingHarness.button(.down))
        harness.runScheduled()
        XCTAssertEqual(harness.presenter.owners.last, .app(name: "Notes", icon: nil))
        XCTAssertTrue(harness.marksMade.isEmpty, "nothing is loaded at the open")
        controller.triggerReleased(isMadeUp: false)   // nothing lit: it stands open
        harness.runScheduled()
        XCTAssertTrue(harness.marksMade.isEmpty, "nor while it stands open")
        controller.cancel()
        harness.runScheduled()
        XCTAssertEqual(harness.marksMade, [Self.notes], "after it closed")
        XCTAssertNotNil(ShortcutRingController.preparedAppMark(forPath: Self.notes))

        harness.tap()
        XCTAssertNotNil(harness.presenter.owners.last?.hubIcon, "the next ring has the icon")
        controller.cancel()
        harness.runScheduled()
        XCTAssertEqual(harness.marksMade, [Self.notes], "made once")

        // The general ring: the app in front has no ring of its own, or there is none.
        for general in [FrontApp(bundlePath: Self.calculator, executablePath: nil), nil] {
            front = general
            harness.tap()
            XCTAssertEqual(harness.presenter.owners.last, .general)
            XCTAssertNil(harness.presenter.owners.last?.hubIcon)
            controller.cancel()
            harness.runScheduled()
        }
        XCTAssertEqual(harness.marksMade, [Self.notes])
        XCTAssertFalse(harness.logLines.contains { $0.contains("Notes") }, "the log never names the app")
    }

    /// A ring that had to be shown without its places' icons makes its face first, one
    /// place per turn, and the app's mark in a turn of its own after it.
    func testAfterAClosedRingTheFaceComesFirstAndTheMarkInATurnOfItsOwn() throws {
        let notes = try XCTUnwrap(applications.get(by: Self.notes))
        notes.ring?[1] = ShortcutRingPlace(openTarget: OpenTargetPayload(path: Self.calculator, bundleID: nil, arguments: "", kind: .application))
        notes.ring?[3] = ShortcutRingPlace(openTarget: OpenTargetPayload(path: "/System/Applications/TextEdit.app", bundleID: nil, arguments: "", kind: .application))
        front = FrontApp(bundlePath: Self.notes, executablePath: nil)
        harness.tap()
        controller.cancel()
        var perTurn: [String] = []
        while harness.hasScheduledWork {
            let (places, marks) = (harness.placesLookedUp, harness.marksMade.count)
            harness.runOneTurn()
            perTurn.append("\(harness.placesLookedUp - places)/\(harness.marksMade.count - marks)")
        }
        XCTAssertEqual(perTurn, ["1/0", "1/0", "0/1"])
    }

    // MARK: At launch and after a change

    /// The marks are made where the faces are: decided on a later turn, then one app per
    /// turn, never while a ring is open, only for apps whose own ring can open, after the
    /// faces, and not again once they are there. They are dropped when the app leaves the
    /// list.
    func testTheMarksAreMadeOnePerTurnAfterTheFacesAndDroppedWithTheApp() throws {
        let options = Options()
        options.defaults = TestDefaults.make(for: self)
        let notes = Self.ownRing(Self.notes)
        notes.ring?[2] = ShortcutRingPlace(openTarget: OpenTargetPayload(path: Self.calculator, bundleID: nil, arguments: "", kind: .application))
        let maps = Self.ownRing("/System/Applications/Maps.app")
        let preview = Application(path: "/System/Applications/Preview.app")   // the general ring
        options.application.applications = Self.list([notes, maps, preview])

        var turns: [(delay: TimeInterval, block: () -> Void)] = []
        var work: [String] = []
        func prepare() {
            ShortcutRingController.prepareMissingFaces(options: options, after: { turns.append(($0, $1)) }, makePlace: {
                work.append("place \($0.openTarget?.path ?? "")")
                return ShortcutRingFace.place($0, looksOnDisk: false)
            }, makeMark: { path in
                work.append("mark \(path)")
                return RingHarness.mark(named: ShortcutRingAppMark.plainName(ofPath: path))
            })
        }
        func nextTurn() {
            guard !turns.isEmpty else { return XCTFail("no turn is due") }
            turns.removeFirst().block()
        }

        prepare()
        nextTurn()
        XCTAssertTrue(turns.isEmpty, "nothing opens a ring: no mark")
        XCTAssertEqual(ShortcutRingController.appMarksToPrepare(options: options), [])

        options.buttons.binding = [Self.opensTheRing()]
        XCTAssertEqual(ShortcutRingController.appMarksToPrepare(options: options), [Self.notes, maps.path],
                       "the apps whose own ring can open; not the one with the general ring")
        prepare()
        nextTurn()
        XCTAssertTrue(work.isEmpty, "nothing in the turn that decides")

        ShortcutRingController.setTestingController(controller)
        defer { ShortcutRingController.setTestingController(nil) }
        var perTurn: [Int] = []
        var pressed = false
        while !turns.isEmpty {
            // A ring opens after the face is made, before the first mark.
            if work.count == 1, !pressed {
                pressed = true
                controller.triggerPressed(by: RingHarness.button(.down))
            } else if controller.isOpen {
                controller.cancel()
            }
            let before = work.count
            nextTurn()
            perTurn.append(work.count - before)
        }
        XCTAssertEqual(work, ["place \(Self.calculator)", "mark \(Self.notes)", "mark \(maps.path)"], "the face first")
        XCTAssertTrue(perTurn.allSatisfy { $0 <= 1 }, "\(perTurn)")
        XCTAssertTrue(perTurn.contains(0), "a turn found the ring open and waited: \(perTurn)")
        XCTAssertNotNil(ShortcutRingController.preparedAppMark(forPath: Self.notes))
        XCTAssertNotNil(ShortcutRingController.preparedAppMark(forPath: maps.path))
        XCTAssertNil(ShortcutRingController.preparedAppMark(forPath: preview.path))

        prepare()
        nextTurn()
        XCTAssertTrue(turns.isEmpty, "a mark that is there is not made again")
        XCTAssertEqual(work.count, 3)

        // Maps leaves the list: its mark goes at the next pass.
        options.application.applications = Self.list([notes, preview])
        prepare()
        nextTurn()
        XCTAssertNil(ShortcutRingController.preparedAppMark(forPath: maps.path))
        XCTAssertNotNil(ShortcutRingController.preparedAppMark(forPath: Self.notes))
        XCTAssertTrue(turns.isEmpty)
    }

    /// At launch the marks follow the faces of the launch: the pass after a change (asked
    /// for at launch too) waits while the launch's faces are under way, so that no turn
    /// does two things, and then makes only what is still missing.
    func testAtLaunchTheMarksWaitForTheLaunchsFaces() {
        let options = Options()
        options.defaults = TestDefaults.make(for: self)
        var general = ShortcutRingSettings.default
        general[5] = ShortcutRingPlace(openTarget: OpenTargetPayload(path: Self.calculator, bundleID: nil, arguments: "", kind: .application))
        options.ring = general
        let notes = Self.ownRing(Self.notes)
        notes.ring?[2] = ShortcutRingPlace(openTarget: OpenTargetPayload(path: "/System/Applications/TextEdit.app", bundleID: nil, arguments: "", kind: .application))
        options.application.applications = Self.list([notes])
        options.buttons.binding = [Self.opensTheRing()]

        var turns: [(delay: TimeInterval, block: () -> Void)] = []
        var work: [String] = []
        let after: (TimeInterval, @escaping () -> Void) -> Void = { turns.append(($0, $1)) }
        let makePlace: (ShortcutRingPlace) -> ShortcutRingFace.Place = {
            work.append("place")
            return ShortcutRingFace.place($0, looksOnDisk: false)
        }
        ShortcutRingController.prepareFaceAtLaunch(options: options, after: after, makePlace: makePlace)
        ShortcutRingController.prepareMissingFaces(options: options, after: after, makePlace: makePlace, makeMark: { path in
            work.append("mark")
            return RingHarness.mark(named: ShortcutRingAppMark.plainName(ofPath: path))
        })
        var perTurn: [Int] = []
        var guardCount = 0
        while !turns.isEmpty, guardCount < 50 {
            guardCount += 1
            let before = work.count
            turns.removeFirst().block()
            perTurn.append(work.count - before)
        }
        XCTAssertEqual(work, ["place", "place", "mark"], "the launch's two faces, then the mark")
        XCTAssertTrue(perTurn.allSatisfy { $0 <= 1 }, "\(perTurn)")
        XCTAssertNotNil(ShortcutRingController.preparedAppMark(forPath: Self.notes))
        XCTAssertEqual(ShortcutRingController.preparedFaces.count, 2)
    }

    /// At most as many marks as faces are kept, the newest; an app beyond them takes the
    /// oldest one's place.
    func testOnlyTheNewestMarksAreKept() {
        let limit = ShortcutRingController.preparedFaceLimit
        for index in 0..<(limit + 2) {
            ShortcutRingController.prepare(RingHarness.mark(named: "App \(index)"), forAppAt: "/Applications/App \(index).app")
        }
        XCTAssertEqual(ShortcutRingController.preparedAppMarks.count, limit)
        XCTAssertNil(ShortcutRingController.preparedAppMark(forPath: "/Applications/App 0.app"))
        XCTAssertNil(ShortcutRingController.preparedAppMark(forPath: "/Applications/App 1.app"))
        XCTAssertEqual(ShortcutRingController.preparedAppMarks.first?.mark.name, "App \(limit + 1)")
        // The same app again: one mark, the newest.
        ShortcutRingController.prepare(RingHarness.mark(named: "App 5 again"), forAppAt: "/Applications/App 5.app")
        XCTAssertEqual(ShortcutRingController.preparedAppMarks.count, limit)
        XCTAssertEqual(ShortcutRingController.preparedAppMarks.first?.mark.name, "App 5 again")
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

    /// A click during the hold and the trigger's release, in either order: the trigger's
    /// release is the ring's (the app never sees an up without its down), the place runs
    /// once, and while the click is still down after the release the ring is held, its
    /// movement read, until the click's up.
    func testAHeldClickAndTheTriggersReleaseInEitherOrderRunThePlaceOnce() {
        bind(button: 4)
        let click = CGPoint(x: 700, y: 500)
        // The click first, then the trigger's release.
        XCTAssertEqual(process(RingHarness.button(.down)), .consumed)
        harness.runScheduled()
        harness.moveHand(by: CGPoint(x: -50, y: 50))
        harness.presenter.onButton?(0, true, click)
        harness.presenter.onButton?(0, false, click)
        XCTAssertFalse(controller.isOpen)
        XCTAssertFalse(InputProcessor.shared.hasHeldShortcutRing)
        XCTAssertEqual(process(RingHarness.button(.up)), .consumed, "the release of the trigger whose ring a click closed")
        XCTAssertFalse(controller.isOpen, "it neither runs again nor opens a ring")

        // The trigger's release first, then the click's up.
        XCTAssertEqual(process(RingHarness.button(.down)), .consumed)
        harness.runScheduled()
        harness.moveHand(by: CGPoint(x: -50, y: 50))
        harness.presenter.onButton?(0, true, click)
        XCTAssertEqual(process(RingHarness.button(.up)), .consumed)
        XCTAssertTrue(InputProcessor.shared.hasHeldShortcutRing, "held until the click is up")
        harness.presenter.onButton?(0, false, click)
        XCTAssertFalse(controller.isOpen)
        XCTAssertFalse(InputProcessor.shared.hasHeldShortcutRing)
        harness.runScheduled()
        XCTAssertEqual(harness.log.filter { $0.hasPrefix("run") }, ["run copy", "run copy"])
        XCTAssertEqual(process(RingHarness.button(.down)), .consumed, "the next press is a new ring")
        XCTAssertTrue(controller.isHeld)
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

    // MARK: Freeze pointer while the ring is held

    private func motion(deltaX: Double, deltaY: Double, at location: CGPoint) -> CGEvent {
        let event = CGEvent(mouseEventSource: nil, mouseType: .otherMouseDragged, mouseCursorPosition: location, mouseButton: .center)!
        event.setDoubleValueField(.mouseEventDeltaX, value: deltaX)
        event.setDoubleValueField(.mouseEventDeltaY, value: deltaY)
        return event
    }

    /// The harness's ring with the app's own pointer lock and motion tap, and a pointer
    /// that only remembers what it was asked. Returns what it was asked.
    private func useTheRealPointerLock(anchor: CGPoint) -> (associations: () -> [Bool], warps: () -> [CGPoint]) {
        var associations: [Bool] = []
        var warps: [CGPoint] = []
        MouseGesturePointerLock.shared.setTestingDriver(MouseGesturePointerDriver(
            currentLocation: { anchor },
            setAssociated: { associations.append($0) },
            warp: { warps.append($0) }
        ))
        addTeardownBlock { MouseGesturePointerLock.shared.clearTestingDriver() }
        var environment = harness.controller.environment
        environment.lockPointer = { MouseGesturePointerLock.shared.lock(for: .shortcutRing) }
        environment.unlockPointer = { MouseGesturePointerLock.shared.unlock(for: .shortcutRing) }
        environment.refreshMotionTap = { MouseInteractionSessionController.shared.refreshMotionTapState() }
        harness.controller.environment = environment
        return ({ associations }, { warps })
    }

    /// The whole path with the real lock: the press of a ring whose switch is on detaches
    /// the pointer; a motion event that shows it off its place is put back for the apps,
    /// and the event after it, which reports "hand + jump back" (macOS 27), counts as the
    /// hand's movement alone; the release attaches the pointer again.
    func testAFrozenHoldGoesThroughThePointerLockAndCountsOnlyTheHandsMovement() {
        let anchor = CGPoint(x: 700, y: 500)
        let pointer = useTheRealPointerLock(anchor: anchor)
        harness.ring.freezePointer = true
        bind(button: 4)

        XCTAssertEqual(process(RingHarness.button(.down)), .consumed)
        XCTAssertTrue(MouseGesturePointerLock.shared.isLocked)
        XCTAssertEqual(pointer.associations(), [false])
        harness.now += 0.5
        for _ in 0..<2 {
            let drifted = motion(deltaX: -6, deltaY: 0, at: CGPoint(x: 694, y: 500))
            MouseInteractionSessionController.shared.handleMotionTapEventForTests(drifted)
            XCTAssertEqual(drifted.location, anchor, "the apps see the pointer where it was")
            let snappedBack = motion(deltaX: 0, deltaY: 0, at: anchor)
            MouseInteractionSessionController.shared.handleMotionTapEventForTests(snappedBack)
        }
        XCTAssertEqual(pointer.warps(), [anchor, anchor])
        XCTAssertEqual(controller.session.travel, CGPoint(x: -24, y: 0), "four steps of the hand, not two")
        XCTAssertEqual(controller.session.lit, 6)

        XCTAssertEqual(process(RingHarness.button(.up)), .consumed)
        XCTAssertFalse(MouseGesturePointerLock.shared.isLocked)
        XCTAssertEqual(pointer.associations().last, true)
        harness.runScheduled()
        XCTAssertEqual(harness.log.last, "run moveSpaceLeft")
    }

    /// The pointer lock has two owners. A gesture button that is let go does not free a
    /// pointer the ring still holds; the ring's release then does.
    func testAGestureButtonLetGoDoesNotFreeAPointerTheRingStillHolds() {
        let savedGesture = Options.shared.gesture
        var gesture = MouseGestureSettings.default   // "Freeze pointer during a gesture" is on
        gesture.clickAction = ""                     // a hold without movement runs nothing
        Options.shared.gesture = gesture
        addTeardownBlock { Options.shared.gesture = savedGesture }
        let pointer = useTheRealPointerLock(anchor: CGPoint(x: 700, y: 500))
        harness.ring.freezePointer = true
        bind(button: 4, others: [(3, SystemShortcut.mouseGestureNavigation.identifier)])

        XCTAssertEqual(process(RingHarness.button(.down, code: 3)), .consumed)
        XCTAssertEqual(pointer.associations(), [false], "the gesture hold keeps the pointer still")
        XCTAssertEqual(process(RingHarness.button(.down)), .consumed)
        XCTAssertTrue(controller.isHeld)
        XCTAssertEqual(process(RingHarness.button(.up, code: 3)), .consumed)
        XCTAssertTrue(controller.isHeld, "the ring is still held")
        XCTAssertTrue(MouseGesturePointerLock.shared.isLocked, "and so is the pointer")
        XCTAssertEqual(pointer.associations(), [false])

        XCTAssertEqual(process(RingHarness.button(.up)), .consumed)
        XCTAssertFalse(MouseGesturePointerLock.shared.isLocked)
        XCTAssertEqual(pointer.associations(), [false, true])
    }

    /// The same from the lock's side, and the two things that free the pointer whoever
    /// holds it: the safety timeout and the release at launch and quit.
    func testThePointerLockIsFreeWhenNeitherOwnerHoldsIt() {
        let pointer = useTheRealPointerLock(anchor: CGPoint(x: 700, y: 500))
        let lock = MouseGesturePointerLock.shared
        lock.lock()
        lock.lock(for: .shortcutRing)
        lock.unlock(for: .shortcutRing)
        XCTAssertTrue(lock.isLocked, "a gesture hold goes on")
        lock.unlock()
        XCTAssertFalse(lock.isLocked)
        XCTAssertEqual(pointer.associations(), [false, true])

        lock.lock(for: .shortcutRing)
        lock.forceRelease()
        XCTAssertFalse(lock.isLocked)
        lock.lock()
        lock.unlock()
        XCTAssertFalse(lock.isLocked, "nothing is left of the ring's hold")

        lock.setTestingSafetyTimeout(0.02)
        lock.lock()
        lock.lock(for: .shortcutRing)
        let timedOut = expectation(description: "the safety timeout")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { timedOut.fulfill() }
        wait(for: [timedOut], timeout: 2)
        XCTAssertFalse(lock.isLocked, "the timeout frees the pointer for both")
        lock.lock()
        lock.unlock()
        XCTAssertFalse(lock.isLocked)
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
        XCTAssertTrue(panel.ignoresMouseEvents, "until a ring is shown")
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

    /// A ring shown as the controller shows every ring, held or left open: taking clicks.
    private func shown(
        appearance: ShortcutRingAppearance = ShortcutRingAppearance(),
        takesClicks: Bool = true,
        otherScreens: [CGRect] = []
    ) -> (ShortcutRingPanelPresenter, [NSPanel]) {
        let presenter = ShortcutRingPanelPresenter()
        var ordered: [NSPanel] = []
        presenter.orderFront = { ordered.append($0) }
        presenter.appearance = { appearance }
        presenter.after = { _, _ in }
        presenter.otherScreens = { _ in otherScreens }
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
        let drops = try XCTUnwrap(stage.dropsView)
        XCTAssertEqual(drops.frame.midX, 400, accuracy: 0.5)
        XCTAssertEqual(drops.frame.midY, 682, accuracy: 0.5)
        XCTAssertEqual(drops.frame.width, ShortcutRingGeometry.canvasSide)
        XCTAssertEqual(drops.blurView?.state, .active, "a window that is never key would show the inactive grey")
        XCTAssertEqual(stage.eventLocation(of: NSPoint(x: 400, y: 682)), CGPoint(x: 400, y: 300))
        XCTAssertFalse(panel.ignoresMouseEvents, "held or open: the click is the ring's")
        XCTAssertTrue(stage.takesClicks)
    }

    /// While a ring is shown the panel takes the mouse; when it goes, it lets go. Taking
    /// the mouse is the panel's `ignoresMouseEvents` alone: the stage has no fill for it.
    func testAnOpenRingTakesTheMouseAndAHiddenOneLetsGo() throws {
        let (presenter, _) = shown()
        let panel = try XCTUnwrap(presenter.panel)
        let stage = try XCTUnwrap(presenter.stage)
        XCTAssertFalse(panel.ignoresMouseEvents)
        XCTAssertTrue(stage.takesClicks)
        XCTAssertNil(stage.layer?.backgroundColor, "nothing is drawn to take the clicks")
        XCTAssertTrue(stage.acceptsFirstMouse(for: nil), "the first click on a window that is not key counts")
        presenter.setTakesClicks(false)
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertNil(stage.layer?.backgroundColor)
        presenter.setTakesClicks(true)
        XCTAssertFalse(panel.ignoresMouseEvents)
        presenter.hide()
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertFalse(panel.isVisible)
    }

    /// What `view`'s layer tree draws, as premultiplied RGBA bytes (one point, one pixel).
    private func drawn(_ view: NSView) throws -> [UInt8] {
        let width = Int(view.bounds.width), height = Int(view.bounds.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let layer = try XCTUnwrap(view.layer)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            layer.render(in: context)
        }
        return pixels
    }

    /// With a ring open, held or left open, the screen outside the ring's drops is as it
    /// is without a ring: the ring's panel and the panels of the other screens are clear
    /// windows without a shadow, and their stages draw nothing at all, not the faintest
    /// fill. (The stages were filled with 1.5 % black to take the clicks: the whole screen
    /// went a shade darker while a ring was open, and lighter again when it closed.)
    func testWithARingOpenNothingIsDrawnOutsideItsDrops() throws {
        let right = CGRect(x: 1512, y: 0, width: 800, height: 600)
        let (presenter, _) = shown(otherScreens: [right])
        let panel = try XCTUnwrap(presenter.panel)
        let stage = try XCTUnwrap(presenter.stage)
        let cover = try XCTUnwrap(presenter.covers.first)
        for takesClicks in [true, false, true] {
            presenter.setTakesClicks(takesClicks)
            for (window, view) in [(panel, stage), (cover.panel, cover.stage)] {
                XCTAssertEqual(window.backgroundColor, .clear)
                XCTAssertFalse(window.isOpaque)
                XCTAssertFalse(window.hasShadow)
                XCTAssertNil(view.layer?.backgroundColor, "takes clicks: \(takesClicks)")
                XCTAssertNil(view.layer?.contents)
                XCTAssertEqual(view.layer?.borderWidth, 0)
                XCTAssertEqual(view.layer?.shadowOpacity, 0)
                XCTAssertTrue(view.layer?.filters?.isEmpty ?? true)
                XCTAssertTrue(view.layer?.backgroundFilters?.isEmpty ?? true)
                XCTAssertNil(view.layer?.compositingFilter)
            }
            // The other screen's whole panel, and the ring's panel without its drops: not
            // one pixel with any colour or alpha.
            XCTAssertTrue(cover.stage.subviews.isEmpty)
            XCTAssertTrue(try drawn(cover.stage).allSatisfy { $0 == 0 }, "takes clicks: \(takesClicks)")
            let drops = try XCTUnwrap(stage.dropsView)
            XCTAssertEqual(stage.subviews, [drops as NSView], "the drops are all a stage holds")
            drops.isHidden = true
            XCTAssertTrue(try drawn(stage).allSatisfy { $0 == 0 }, "takes clicks: \(takesClicks)")
            drops.isHidden = false
            XCTAssertEqual(drops.frame.width, ShortcutRingGeometry.canvasSide, "and the drops stand in the ring's own square")
            XCTAssertEqual(drops.frame.height, ShortcutRingGeometry.canvasSide)
        }
        // (The drawing above does see a fill: the check is not blind.)
        cover.stage.layer?.backgroundColor = NSColor(white: 0, alpha: 0.015).cgColor
        XCTAssertFalse(try drawn(cover.stage).allSatisfy { $0 == 0 })
        cover.stage.layer?.backgroundColor = nil
        presenter.hide()
    }

    /// The window server's own answer to "which window gets a mouse-down here?"
    /// (`NSWindow.windowNumber(at:belowWindowWithWindowNumber:)`; nothing is clicked): the
    /// ring's panel and another screen's, with nothing drawn in them, get it while they
    /// take clicks, so the app underneath gets none; not once they let go or are gone.
    /// For the length of this test two panels of 4 × 4 points with nothing in them, and
    /// one as large with a fill too faint to see, stand at the bottom left of the main
    /// screen. Skipped where the window server gives no window a click (no display awake).
    func testTheWindowServerGivesTheClearPanelsTheClick() throws {
        guard let main = NSScreen.screens.first else { throw XCTSkip("no screen") }
        let height = ShortcutRingScreens.mainScreenHeight
        func spot(_ index: Int) -> CGRect {
            let cocoa = NSRect(x: main.frame.minX + 300 + CGFloat(index) * 10, y: main.frame.minY + 2, width: 4, height: 4)
            return ShortcutRingScreens.flipped(cocoa, mainScreenHeight: height)
        }
        func gets(_ window: NSWindow, _ spot: CGRect) -> Bool {
            let centre = ShortcutRingScreens.flipped(CGPoint(x: spot.midX, y: spot.midY), mainScreenHeight: height)
            return NSWindow.windowNumber(at: centre, belowWindowWithWindowNumber: 0) == window.windowNumber
        }
        func wait(_ seconds: TimeInterval = 0.05) {
            RunLoop.current.run(until: Date().addingTimeInterval(seconds))
        }
        /// Whether `window` gets (or, `expected` false, no longer gets) the click at `spot`
        /// within a second: the window server hears of a change a moment after it is made.
        func settles(_ window: NSWindow, _ spot: CGRect, gets expected: Bool) -> Bool {
            for _ in 0..<20 {
                if gets(window, spot) == expected { return true }
                wait()
            }
            return false
        }

        // The control: a window that takes clicks by the other rule (its pixels' alpha).
        let control = NSPanel(
            contentRect: ShortcutRingScreens.flipped(spot(2), mainScreenHeight: height),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true
        )
        control.level = .popUpMenu
        control.backgroundColor = .clear
        control.isOpaque = false
        control.hasShadow = false
        control.hidesOnDeactivate = false
        control.isReleasedWhenClosed = false
        let filled = NSView(frame: NSRect(x: 0, y: 0, width: 4, height: 4))
        filled.wantsLayer = true
        filled.layer?.backgroundColor = NSColor(white: 0, alpha: 0.02).cgColor
        control.contentView = filled

        let presenter = ShortcutRingPanelPresenter()
        presenter.orderFront = { $0.orderFrontRegardless() }
        presenter.appearance = { ShortcutRingAppearance(reducesMotion: true) }
        presenter.after = { _, _ in }
        presenter.otherScreens = { _ in [spot(1)] }
        defer {
            presenter.hide()
            control.orderOut(nil)
        }
        // The ring itself stands far outside its 4 × 4 "screen": only clear panel is there.
        presenter.show(
            ShortcutRingFace(.default), centre: CGPoint(x: spot(0).midX, y: spot(0).midY - 3000),
            screen: ShortcutRingScreen(frame: spot(0), usable: spot(0)), lit: nil, takesClicks: true
        )
        control.orderFrontRegardless()
        let panel = try XCTUnwrap(presenter.panel)
        let cover = try XCTUnwrap(presenter.covers.first)
        XCTAssertNil(presenter.stage?.layer?.backgroundColor)
        XCTAssertNil(cover.stage.layer?.backgroundColor)

        var controlIsHit = false
        for _ in 0..<30 where !controlIsHit {
            wait()
            controlIsHit = gets(control, spot(2))
        }
        guard controlIsHit else {
            throw XCTSkip("the window server gives no window of this process a click here (no display awake?)")
        }
        XCTAssertTrue(settles(panel, spot(0), gets: true), "the ring's panel, clear, takes the click")
        XCTAssertTrue(settles(cover.panel, spot(1), gets: true), "and so does the panel of another screen")

        presenter.setTakesClicks(false)
        XCTAssertTrue(settles(panel, spot(0), gets: false), "let go, the click is the app's underneath")
        XCTAssertTrue(settles(cover.panel, spot(1), gets: false))
        presenter.setTakesClicks(true)
        XCTAssertTrue(settles(panel, spot(0), gets: true))
        XCTAssertTrue(settles(cover.panel, spot(1), gets: true))

        presenter.hide()
        XCTAssertTrue(settles(panel, spot(0), gets: false), "gone with the ring")
        XCTAssertTrue(settles(cover.panel, spot(1), gets: false))
    }

    /// A click on the panel reaches the ring in event coordinates, down and up.
    func testAClickOnThePanelIsReportedWhereItWas() throws {
        let (presenter, _) = shown()
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
        let drops = try XCTUnwrap(stage.dropsView)
        XCTAssertNil(drops.hitTest(NSPoint(x: 10, y: 10)), "the drops take no click themselves")
        XCTAssertNil(drops.contents[2].hitTest(NSPoint(x: 5, y: 5)))
        // On the ring and beside it, the view that is hit is the stage, which accepts the
        // first click of a window that is not key.
        XCTAssertTrue(stage.hitTest(NSPoint(x: 400, y: 682)) === stage)
        XCTAssertTrue(stage.hitTest(NSPoint(x: 400 + ShortcutRingGeometry.placeRadius, y: 682)) === stage)
        XCTAssertTrue(stage.hitTest(NSPoint(x: 1200, y: 100)) === stage)
    }

    /// A pointer that is not kept still can carry a held click to another screen. Every
    /// other screen gets a panel of its own that takes that click and reports it to the
    /// ring where it was, shows no ring, and goes with the ring; a ring shown later on one
    /// screen alone takes it away.
    func testEveryOtherScreenHasAPanelThatTakesTheClickAndShowsNoRing() throws {
        let right = CGRect(x: 1512, y: -100, width: 1920, height: 1080)
        let (presenter, ordered) = shown(otherScreens: [right])
        let panel = try XCTUnwrap(presenter.panel)
        XCTAssertEqual(presenter.covers.count, 1)
        let cover = try XCTUnwrap(presenter.covers.first)
        XCTAssertEqual(ordered.count, 2)
        XCTAssertTrue(ordered.contains { $0 === cover.panel })
        XCTAssertEqual(cover.panel.alphaValue, 1)
        let height = ShortcutRingScreens.mainScreenHeight
        XCTAssertEqual(cover.panel.frame, ShortcutRingScreens.flipped(right, mainScreenHeight: height))
        XCTAssertEqual(cover.panel.level, panel.level)
        XCTAssertNil(cover.stage.dropsView, "the ring is drawn on its own screen alone")
        XCTAssertFalse(cover.panel.ignoresMouseEvents)
        XCTAssertTrue(cover.stage.takesClicks)
        XCTAssertNil(cover.stage.layer?.backgroundColor, "as clear as the ring's")
        XCTAssertTrue(presenter.owns(cover.panel), "its clicks are not clicks elsewhere")
        XCTAssertTrue(presenter.owns(panel))

        var reported: [(Int, Bool, CGPoint)] = []
        presenter.onButton = { reported.append(($0, $1, $2)) }
        func event(_ type: NSEvent.EventType) throws -> NSEvent {
            return try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: NSPoint(x: 100, y: 980), modifierFlags: [], timestamp: 0,
                windowNumber: cover.panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            ))
        }
        cover.stage.mouseDown(with: try event(.leftMouseDown))
        cover.stage.mouseUp(with: try event(.leftMouseUp))
        XCTAssertEqual(reported.map { $0.0 }, [0, 0])
        XCTAssertEqual(reported.map { $0.1 }, [true, false])
        // 980 points from the bottom of a screen whose top is at -100 is 0.
        XCTAssertEqual(reported.first?.2, CGPoint(x: 1612, y: 0))

        presenter.setTakesClicks(false)
        XCTAssertTrue(cover.panel.ignoresMouseEvents)
        presenter.setTakesClicks(true)
        presenter.hide()
        XCTAssertTrue(cover.panel.ignoresMouseEvents, "it goes with the ring")
        XCTAssertFalse(cover.panel.isVisible)

        presenter.otherScreens = { _ in [] }
        let screen = ShortcutRingScreen(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), usable: CGRect(x: 0, y: 0, width: 1512, height: 982))
        presenter.show(ShortcutRingFace(.default), centre: CGPoint(x: 400, y: 300), screen: screen, lit: nil, takesClicks: true)
        XCTAssertTrue(cover.panel.ignoresMouseEvents, "one screen: no panel beside the ring's takes clicks")
        XCTAssertFalse(panel.ignoresMouseEvents)
        presenter.hide()
    }

    /// The ring must be seen from the moment it takes clicks: the panel is ordered in at
    /// full alpha, always. (Faded in as a window, it stayed at alpha 0 for two seconds and
    /// more on a Mac whose display slept, while it already took the mouse.) Only the drops
    /// move, and the hub is there, opaque, from the first moment.
    func testThePanelIsNeverFadedAsAWindow() throws {
        for appearance in [ShortcutRingAppearance(), ShortcutRingAppearance(reducesMotion: true)] {
            let (presenter, ordered) = shown(appearance: appearance)
            let panel = try XCTUnwrap(presenter.panel)
            let drops = try XCTUnwrap(presenter.stage?.dropsView)
            XCTAssertEqual(ordered.count, 1)
            XCTAssertEqual(panel.alphaValue, 1, "reducesMotion \(appearance.reducesMotion)")
            XCTAssertEqual(drops.alphaValue, 1)
            XCTAssertFalse(drops.isHidden)
            let hub = try XCTUnwrap(drops.drops?.hub)
            XCTAssertEqual(hub.opacity, 1)
            XCTAssertGreaterThan(hub.diameter, 50)
            presenter.hide()
            XCTAssertEqual(panel.alphaValue, 1)
            XCTAssertFalse(presenter.isMoving, "nothing runs once the ring is gone")
        }
    }

    func testWithReduceMotionTheRingSimplyAppears() throws {
        XCTAssertEqual(ShortcutRingAppearance().openDuration, 0.35, accuracy: 0.001)
        XCTAssertEqual(ShortcutRingAppearance(reducesMotion: true).openDuration, 0)
        let filled = ShortcutRingFace(.default).filled

        let (moving, _) = shown()
        XCTAssertEqual(moving.lastOpenDuration, 0.35, accuracy: 0.001)
        XCTAssertTrue(moving.isMoving)
        XCTAssertEqual(moving.stage?.dropsView?.drops, ShortcutRingDrops.frame(at: 0, filled: filled), "the drops start in the middle")

        let (still, _) = shown(appearance: ShortcutRingAppearance(reducesMotion: true))
        XCTAssertEqual(still.lastOpenDuration, 0)
        XCTAssertFalse(still.isMoving)
        XCTAssertEqual(still.stage?.dropsView?.drops, ShortcutRingDrops.settled(filled: filled), "every drop is in its place")
        XCTAssertEqual(still.panel?.alphaValue, 1)
    }

    func testReduceTransparencyAndIncreaseContrastAreFollowed() throws {
        let (plain, _) = shown(appearance: ShortcutRingAppearance(reducesTransparency: true, increasesContrast: true))
        let drops = try XCTUnwrap(plain.stage?.dropsView)
        XCTAssertEqual(drops.material, .drawn)
        XCTAssertNil(drops.blurView, "no material: plain drops are drawn")
        XCTAssertNil(drops.glassBodies)
        XCTAssertEqual(drops.bodiesView?.style.backdrop, .drawn)
        XCTAssertEqual(drops.bodiesView?.style.increasesContrast, true)

        let (usual, _) = shown()
        XCTAssertEqual(usual.stage?.dropsView?.material, .blur)
        XCTAssertNotNil(usual.stage?.dropsView?.blurView)
        XCTAssertEqual(usual.stage?.dropsView?.bodiesView?.style.backdrop, .material)
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

    /// The name in the hub: one or two lines as it is; a name that needs a third gets it
    /// a little smaller instead of being cut. No offered shortcut needs more, on screen
    /// (the hub is 88 points wide) or in the Settings pane's smaller drawing.
    func testALongNameInTheHubGetsAThirdLineInsteadOfBeingCut() {
        let width = ShortcutRingArtwork.titleWidth
        let size = ShortcutRingArtwork.titleFont.pointSize
        XCTAssertEqual(size, 12)
        XCTAssertEqual(width, ShortcutRingDrops.hubDiameter - 12)
        let short = ShortcutRingArtwork.titleLayout("Copy", width: width, pointSize: size)
        XCTAssertEqual(short.lines, 1)
        XCTAssertEqual(short.pointSize, size)
        let two = ShortcutRingArtwork.titleLayout("Desktop on the Right", width: width, pointSize: size)
        XCTAssertEqual(two.lines, 2)
        XCTAssertEqual(two.pointSize, size)
        let long = ShortcutRingArtwork.titleLayout("Screenshot and Recording Options", width: width, pointSize: size)
        XCTAssertEqual(long.lines, 3)
        XCTAssertLessThan(long.pointSize, size)
        XCTAssertGreaterThanOrEqual(long.pointSize, 10)

        let paneScale = ShortcutRingPreviewView.ringScale
        for (what, width, size, diameter) in [
            ("on screen", width, size, ShortcutRingDrops.hubDiameter),
            ("in the pane", width * paneScale, size * paneScale, ShortcutRingDrops.hubDiameter * paneScale),
        ] {
            for category in SystemShortcut.shortcutsByCategory {
                for shortcut in category.shortcuts where ShortcutRingPlace(shortcut).runs {
                    let name = shortcut.localizedName
                    let layout = ShortcutRingArtwork.titleLayout(name, width: width, pointSize: size)
                    XCTAssertLessThanOrEqual(layout.lines, 3, "\(name) \(what)")
                    let font = NSFont.systemFont(ofSize: layout.pointSize, weight: .semibold)
                    for word in name.split(separator: " ") {
                        XCTAssertLessThanOrEqual(
                            (String(word) as NSString).size(withAttributes: [.font: font]).width, width, "\(word) \(what)"
                        )
                    }
                    // The block of lines stays inside the round drop: where its top and
                    // bottom edges are, the drop is still as wide as the text may be.
                    let chord = 2 * (pow(diameter / 2, 2) - pow(layout.height / 2 - 2, 2)).squareRoot()
                    XCTAssertGreaterThanOrEqual(chord, width, "\(name) \(what): \(layout.lines) lines")
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
