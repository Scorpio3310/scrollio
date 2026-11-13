//
//  ShortcutRingController.swift
//  Scrollio
//
//  The Shortcut Ring between its rules (`ShortcutRingSession`, pure), the input side
//  (`InputProcessor`) and the screen (`ShortcutRingPresenting`, the panel).
//
//  What reaches it, and from where:
//
//  - The trigger's press and release: `InputProcessor.process`, for a button or key bound
//    to `SystemShortcut.shortcutRing`. The controller is made at the first such press;
//    for someone who never bound the ring it does not exist (`existing` is nil).
//  - The hand's movement while the trigger is held: the pointer-movement tap, which runs
//    for the length of the hold as it does for a gesture hold
//    (`MouseInteractionSessionController`). Its deltas keep coming when the pointer stands
//    at the edge of a screen.
//  - The pointer over a ring that stands open: no event tap. A timer looks where the
//    pointer is, and stops with the ring. No pointer event of the Mac waits on Scrollio
//    while a ring stands open.
//  - The click that chooses or dismisses: the panel itself takes it. A click that goes
//    to another app all the same (on another screen, where the panel is not; or on this
//    one, should the panel not have taken it), or to a window of Scrollio's own on another
//    screen, closes the ring and runs nothing: while a ring stands open, and only then,
//    two monitors hear of such clicks.
//  - Esc: the keys tap, which is kept running while a ring is open
//    (`InputProcessor.needsKeyEvents`).
//
//  The ring closes and runs nothing when the event taps stop or are restarted
//  (`InputProcessor.clearActiveBindings`), when another button's action runs, when
//  another app comes to the front, the Space or the screens change, after
//  `ShortcutRingSession.holdLimit` of a hold whose release never came and after
//  `idleLimit` without the pointer moving over an open ring. It does not open while the
//  left or the right button is down (a drag).
//
//  What a place that opens an app shows (its name, its icon) takes a look on disk. That
//  never happens in the turn in which a ring is shown: the face is made at a quiet moment
//  (`preparedFace`), and a ring for which none is there yet shows the file's name and a
//  plain symbol once.
//
//  Nothing is drawn and nothing is posted inside an event callback: the panel is shown on
//  the next turn of the main queue, and so is the chosen action, after the panel is gone.
//  A place runs as a button's action runs: resolved by the executor from a binding built
//  from the place, down and then up for what is held (a recorded key, a click).
//  A pulse (`MouseGestureHapticCue`) is played only for a trigger that arrived over HID++,
//  on the mouse it belongs to, and only while Gestures › Haptic feedback is on (the one
//  switch for the pulses of a hold): a light one when a place lights (at most one every
//  `tickSpacing`, the others dropped), a firmer one when an action runs.
//

import Cocoa

final class ShortcutRingController {

    // MARK: The one controller

    /// The controller, once a ring was first asked for. Nil for everyone else: the paths
    /// that ask "is a ring open?" cost them a comparison with nil.
    private(set) static var existing: ShortcutRingController?

    /// The controller, made now if there is none yet.
    static var shared: ShortcutRingController {
        if let existing { return existing }
        let controller = ShortcutRingController()
        existing = controller
        return controller
    }

    // MARK: The face, made at a quiet moment

    /// A ring's face with what it took a look on disk to know (an app's name and icon),
    /// made when no ring was held: by the Settings pane whenever it shows a ring, at
    /// launch for a ring that opens something, and after a ring closed that had to be
    /// shown without it.
    private(set) static var preparedFace: (ring: ShortcutRingSettings, face: ShortcutRingFace)?

    /// Keeps `face` for the next ring that is `ring`.
    static func prepare(_ face: ShortcutRingFace, for ring: ShortcutRingSettings) {
        preparedFace = (ring, face)
    }

    /// At launch: when something opens the ring and a place of it opens an app or a file,
    /// the face is made on a later turn of the main queue, so that the first ring already
    /// has the icons. For everyone else: one pass over the bindings, nothing more.
    static func prepareFaceAtLaunch(options: Options = .shared) {
        let ring = options.ring
        guard ring.opensSomething,
              options.buttons.binding.contains(where: {
                  $0.isEnabled && $0.systemShortcutName == SystemShortcut.shortcutRing.identifier
              }) else { return }
        DispatchQueue.main.async {
            prepare(ShortcutRingFace(ring), for: ring)
        }
    }

    #if DEBUG
    /// Tests: puts a controller of their own in the app's place (nil: none, as before the
    /// first ring).
    static func setTestingController(_ controller: ShortcutRingController?) {
        existing?.cancel()
        existing = controller
    }
    #endif

    // MARK: What it needs from the system

    struct Environment {
        /// Monotonic time in seconds.
        var now: () -> TimeInterval
        /// Where the pointer is, in event coordinates.
        var pointerLocation: () -> CGPoint
        /// The screen that holds a point (event coordinates).
        var screen: (CGPoint) -> ShortcutRingScreen
        /// The left or the right button is down.
        var isPrimaryButtonDown: () -> Bool
        /// Runs the block on the next turn of the main queue, never inside the caller.
        var schedule: (@escaping () -> Void) -> Void
        /// Runs the block on the main queue after this many seconds.
        var scheduleAfter: (TimeInterval, @escaping () -> Void) -> Void
        /// A repeating timer, or nil when the caller drives `tick()` itself (tests).
        var makeTimer: (TimeInterval, @escaping () -> Void) -> Timer?
        /// The ring this Mac's settings hold.
        var ring: () -> ShortcutRingSettings
        /// The whole face of a ring, with a look on disk for what it opens. Only called
        /// while no ring is open.
        var makeFace: (ShortcutRingSettings) -> ShortcutRingFace
        /// Runs a place's action.
        var run: (ShortcutRingPlace) -> Void
        /// Whether a ring may ask a mouse for pulses: Gestures › Haptic feedback, the one
        /// switch for the pulses of a hold. (A cue can switch a mouse's haptics on; it is
        /// only asked for while the user has that switch on.)
        var allowsHaptics: () -> Bool
        /// Plays a pulse on the mouse the button with this code was pressed on.
        var playHaptic: (MouseGestureHapticCue, UInt16) -> Void
        /// Says the lit action's name to VoiceOver.
        var announce: (String) -> Void
        /// The held state changed: the pointer-movement tap follows it.
        var refreshMotionTap: () -> Void
        /// Keeps the pointer where it is, and lets it go again: for a hold of a ring whose
        /// "Freeze pointer while the ring is held" is on.
        var lockPointer: () -> Void
        var unlockPointer: () -> Void
        /// Whether the ring needs the keyboard changed: the keys tap follows it.
        var refreshKeyTap: () -> Void
        /// One line of the `app` log: a ring opened, was left open, ran something or
        /// closed. A few lines per use of the ring, never one per pointer event.
        var log: (String) -> Void
        /// Something that should not happen did: a line of the `app` log as a problem.
        var logProblem: (String) -> Void
        /// Starts to hear of mouse-downs that did not go to the ring: those that went to
        /// other apps, and those in windows of Scrollio's own (the handler gets that
        /// window; nil for another app's). The result ends it
        /// (`stopWatchingClicksElsewhere`). Nil: nothing was started (tests).
        var watchClicksElsewhere: (@escaping (NSWindow?) -> Void) -> Any?
        var stopWatchingClicksElsewhere: (Any) -> Void

        static let system = Environment(
            now: { ProcessInfo.processInfo.systemUptime },
            pointerLocation: { ShortcutRingScreens.pointerLocation() },
            screen: { ShortcutRingScreens.screen(containing: $0) },
            isPrimaryButtonDown: { NSEvent.pressedMouseButtons & 0b11 != 0 },
            schedule: { DispatchQueue.main.async(execute: $0) },
            scheduleAfter: { delay, block in DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: block) },
            makeTimer: { interval, block in
                // Under XCTest no timer runs; a test calls `tick()`.
                guard !AppRuntime.isRunningXCTest else { return nil }
                return CommonModesTimer.scheduled(withTimeInterval: interval, repeats: true) { _ in block() }
            },
            ring: { Options.shared.ring },
            makeFace: { ShortcutRingFace($0) },
            run: { ShortcutRingController.run($0) },
            allowsHaptics: { Options.shared.gesture.hapticFeedback },
            playHaptic: { cue, code in LogiCenter.shared.playGestureHaptic(cue, forScrollioCode: code) },
            announce: { ShortcutRingController.announce($0) },
            refreshMotionTap: { MouseInteractionSessionController.shared.refreshMotionTapState() },
            lockPointer: { MouseGesturePointerLock.shared.lock(for: .shortcutRing) },
            unlockPointer: { MouseGesturePointerLock.shared.unlock(for: .shortcutRing) },
            refreshKeyTap: { ButtonCore.shared.keyTap.refresh() },
            log: { AppSystemLog.note($0) },
            logProblem: { AppSystemLog.problem($0) },
            watchClicksElsewhere: { handler in
                // Under XCTest nothing listens to the Mac's clicks.
                guard !AppRuntime.isRunningXCTest else { return nil }
                let downs: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
                // Clicks in other apps, and clicks in Scrollio's own windows (its Settings
                // on another screen): the global monitor does not hear of the second kind.
                let monitors: [Any?] = [
                    NSEvent.addGlobalMonitorForEvents(matching: downs) { _ in handler(nil) },
                    NSEvent.addLocalMonitorForEvents(matching: downs) { event in
                        handler(event.window)
                        return event
                    },
                ]
                return monitors.compactMap { $0 }
            },
            stopWatchingClicksElsewhere: { watch in
                for monitor in watch as? [Any] ?? [] {
                    NSEvent.removeMonitor(monitor)
                }
            }
        )
    }

    /// Between two light pulses; a place that lights sooner gets none.
    static let tickSpacing: TimeInterval = 0.1
    /// For this long after a place's action was started, a change of Space or of the app
    /// in front does not close a ring: it is what that action did ("Move right a space",
    /// an app that opens), and it may arrive when the next ring is already held.
    static let quietAfterRun: TimeInterval = 1.0
    /// How often the pointer is looked at while the ring stands open.
    static let pointerInterval: TimeInterval = 1.0 / 60.0
    /// How often a held ring is looked at: its limit, and a hand that stopped between the
    /// dead zone and twice of it in the first moments, whose place lights when those are
    /// over although no movement arrives any more.
    static let holdCheckInterval: TimeInterval = 0.1

    var environment: Environment
    let presenter: ShortcutRingPresenting

    // MARK: State

    private(set) var session = ShortcutRingSession()
    /// The ring as it was when it opened: what is shown and what a place runs.
    private var ring = ShortcutRingSettings.default
    /// Which of its places run something, worked out when the ring changes, not per press.
    private var filled = ShortcutRingSettings.default.filled
    private var face: ShortcutRingFace?
    /// `face` knows everything (an app's name and icon); false while it was made without
    /// a look on disk, for a ring that had to be shown before a whole face was there.
    private var faceIsComplete = false
    /// The screen the ring opened on.
    private var screen = ShortcutRingScreen(frame: .zero, usable: .zero)
    /// The button to name when asking for a pulse: set for a trigger that arrived over
    /// HID++, nil otherwise.
    private var hapticCode: UInt16?
    /// What opened the ring, for the log.
    private var openedBy = ""
    private var lastTick = -TimeInterval.infinity
    /// When a place's action was last started.
    private var lastRun = -TimeInterval.infinity
    /// Drops a show that was scheduled for a ring that is gone.
    private var showGeneration = 0
    private var timer: Timer?
    private var timerPhase = ShortcutRingSession.Phase.closed
    private var lastPolledPointer: CGPoint?
    private var wasHeld = false
    /// This hold keeps the pointer still (the ring's own switch).
    private var holdsPointer = false
    /// Where the pointer stood when the trigger went down.
    private var pressPointer = CGPoint.zero
    private var neededKeys = false
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    /// Hears of clicks that went to other apps, while a ring stands open.
    private var clickWatch: Any?
    /// The line about a click the panel did not take is written once per run.
    private var didLogMissedClick = false

    init(environment: Environment = .system, presenter: ShortcutRingPresenting = ShortcutRingPanelPresenter()) {
        self.environment = environment
        self.presenter = presenter
        presenter.onButton = { [weak self] button, isDown, location in
            self?.button(button, isDown: isDown, at: location)
        }
        observeWhatClosesTheRing()
    }

    deinit {
        timer?.invalidate()
        if let clickWatch {
            environment.stopWatchingClicksElsewhere(clickWatch)
        }
        for observer in observers {
            observer.center.removeObserver(observer.token)
        }
    }

    // MARK: What others ask

    var isOpen: Bool {
        return session.isOpen
    }

    /// The trigger is down and the hand's movement chooses: the pointer-movement tap is
    /// needed.
    var isHeld: Bool {
        return session.phase == .held
    }

    /// Esc is the ring's: the keys tap is needed.
    var needsKeys: Bool {
        return session.needsKeys
    }

    /// Esc closed the ring and is not up yet: until then every Esc down (its repeats) is
    /// the ring's too.
    var awaitsEscapeRelease: Bool {
        return session.needsKeys && !session.isOpen
    }

    // MARK: The trigger (InputProcessor)

    /// The ring's trigger went down. Never a key's auto-repeat.
    func triggerPressed(by event: InputEvent) {
        assertMainThread()
        if !session.isOpen {
            // In the middle of a drag the ring stays away.
            guard !environment.isPrimaryButtonDown() else { return }
            let stored = environment.ring()
            if stored != ring {
                ring = stored
                filled = stored.filled
                face = nil
                faceIsComplete = false
            }
            if case .hidPP = event.source, environment.allowsHaptics() {
                hapticCode = event.code
            } else {
                hapticCode = nil
            }
            openedBy = Self.kind(of: event)
        }
        let pointer = Self.pointerLocation(of: event) ?? environment.pointerLocation()
        if !session.isOpen {
            screen = environment.screen(pointer)
            pressPointer = pointer
        }
        perform(session.triggerPressed(
            at: environment.now(), pointer: pointer, screen: screen.usable, filled: filled
        ))
    }

    /// The trigger came up; `isMadeUp` for a release Scrollio made up itself.
    func triggerReleased(isMadeUp: Bool) {
        assertMainThread()
        releasing = true
        perform(session.triggerReleased(at: environment.now(), isMadeUp: isMadeUp))
        releasing = false
    }

    // MARK: TEMPORARY DIAGNOSTIC (2026-11-13)
    //
    // Mission Control and Show Desktop do not work when a held ring runs them: the Dock's
    // own log shows it entering the other of the two modes and leaving it 1 to 2 ms later.
    // Chosen with a click they work, and so does the same key from a gesture. What differs
    // at that moment is not in the code, so the input state is written to the `app` log:
    // while the ring is held, when it runs, and shortly after. Show Desktop from a held
    // ring is sent 0.15 s late and Mission Control at once, to see whether the moment of
    // the release is the cause. To be removed with the fix.

    private var releasing = false
    private var didLogHeldInput = false
    private static let diagnosesRuns = !AppRuntime.isRunningXCTest
    private static let diagnosticDelay: TimeInterval = 0.15

    /// Modifier keys and mouse buttons as the hardware and the session have them, and how
    /// long ago the last key and the last modifier change were. No key is named.
    static func inputStateLine() -> String {
        func buttons(_ state: CGEventSourceStateID) -> String {
            return (0..<8).map {
                CGEventSource.buttonState(state, button: unsafeBitCast(UInt32($0), to: CGMouseButton.self)) ? "1" : "0"
            }.joined()
        }
        func since(_ state: CGEventSourceStateID, _ type: CGEventType) -> String {
            return String(format: "%.0f", CGEventSource.secondsSinceLastEventType(state, eventType: type) * 1000)
        }
        return String(
            format: "modifiers hid 0x%llX session 0x%llX; buttons hid %@ session %@; ms since key down hid %@ session %@, "
                + "key up hid %@ session %@, modifier change hid %@ session %@, button down hid %@ session %@, moved hid %@",
            CGEventSource.flagsState(.hidSystemState).rawValue,
            CGEventSource.flagsState(.combinedSessionState).rawValue,
            buttons(.hidSystemState), buttons(.combinedSessionState),
            since(.hidSystemState, .keyDown), since(.combinedSessionState, .keyDown),
            since(.hidSystemState, .keyUp), since(.combinedSessionState, .keyUp),
            since(.hidSystemState, .flagsChanged), since(.combinedSessionState, .flagsChanged),
            since(.hidSystemState, .otherMouseDown), since(.combinedSessionState, .otherMouseDown),
            since(.hidSystemState, .mouseMoved)
        )
    }

    /// What kind of trigger an event is, for the log.
    private static func kind(of event: InputEvent) -> String {
        if case .hidPP = event.source { return "a button over HID++" }
        return event.type == .keyboard ? "a key" : "a mouse button"
    }

    /// Where the pointer was when a mouse button's event was made; nil for a key and for
    /// a button that arrived over HID++.
    private static func pointerLocation(of event: InputEvent) -> CGPoint? {
        guard event.type == .mouse, case .cgEvent(let cgEvent) = event.source else { return nil }
        return cgEvent.location
    }

    // MARK: The pointer (the motion tap while held, the timer while open)

    /// The mouse moved while the trigger is held. Runs inside the motion tap's callback.
    func pointerMoved(by delta: CGPoint, to location: CGPoint) {
        guard session.phase == .held else { return }
        // A pointer that is kept still stands where the press found it, whatever an event
        // says that was made before the freeze took hold: a ring that is then left open
        // must not take that event's place for the pointer's, and light what it is under.
        let stands = holdsPointer ? pressPointer : location
        perform(session.pointerMoved(by: delta, to: stands, at: environment.now()))
    }

    /// One look of the timer: where the pointer is over an open ring, and whether the
    /// ring's time is up.
    func tick() {
        guard session.isOpen else {
            stopTimer()
            return
        }
        let now = environment.now()
        if Self.diagnosesRuns, session.phase == .held, !didLogHeldInput {
            didLogHeldInput = true
            environment.log("Ring diagnostic: while held: \(Self.inputStateLine())")
        }
        if session.phase == .latched {
            let pointer = environment.pointerLocation()
            if pointer != lastPolledPointer {
                lastPolledPointer = pointer
                perform(session.pointerMoved(by: .zero, to: pointer, at: now))
            }
        }
        perform(session.timePassed(to: now))
    }

    // MARK: Clicks (the panel) and Esc (the keys tap)

    private func button(_ button: Int, isDown: Bool, at location: CGPoint) {
        assertMainThread()
        if isDown {
            perform(session.buttonPressed(button, at: location))
        } else {
            perform(session.buttonReleased(button))
        }
    }

    /// A mouse button went down and the click went to another app, while a ring stands
    /// open: the ring closes and runs nothing. On another screen that is how a click
    /// beside the ring looks. On the ring's own screen the panel should have taken the
    /// click: it did not, the app underneath got it, and choosing a shortcut on top of
    /// that would act on a click the user did not make there; the log says so.
    func clickWentElsewhere(in window: NSWindow? = nil) {
        assertMainThread()
        // A click on the ring's own panel is the ring's (the panel reports it itself).
        guard session.phase == .latched, !presenter.owns(window) else { return }
        if screen.frame.contains(environment.pointerLocation()), !didLogMissedClick {
            didLogMissedClick = true
            environment.logProblem("Shortcut Ring: a click on the ring's screen went to the app under it "
                + "(the panel did not take it); the ring closed without running anything")
        }
        cancel()
    }

    /// Esc went down. True: it was the ring's and goes no further.
    func escapePressed() -> Bool {
        let result = session.escapePressed()
        perform(result.commands)
        return result.answer == .swallow
    }

    /// Esc came up. True: its press closed the ring, so its release is the ring's too.
    func escapeReleased() -> Bool {
        let swallowed = session.escapeReleased() == .swallow
        followTheSession()
        return swallowed
    }

    // MARK: Giving up

    /// Closes the ring, if one is open, and runs nothing.
    func cancel() {
        perform(session.cancel())
    }

    private func observeWhatClosesTheRing() {
        let workspace = NSWorkspace.shared.notificationCenter
        // (center, name, whether it can be the late echo of what a place just did)
        let names: [(NotificationCenter, Notification.Name, Bool)] = [
            (workspace, NSWorkspace.activeSpaceDidChangeNotification, true),
            (workspace, NSWorkspace.didActivateApplicationNotification, true),
            (NotificationCenter.default, NSApplication.didChangeScreenParametersNotification, false),
        ]
        for (center, name, followsARun) in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self, self.session.isOpen else { return }
                if followsARun, self.environment.now() - self.lastRun < Self.quietAfterRun { return }
                self.cancel()
            }
            observers.append((center, token))
        }
    }

    // MARK: Carrying out what the rules say

    private func perform(_ commands: [ShortcutRingSession.Command]) {
        guard !commands.isEmpty else {
            followTheSession()
            return
        }
        var closed = false
        var ran: String?
        for command in commands {
            switch command {
            case .open(let centre):
                showGeneration += 1
                let generation = showGeneration
                lastPolledPointer = nil
                didLogHeldInput = false
                // Not inside the event callback this runs in: a panel is made and shown
                // on the main queue's next turn.
                environment.schedule { [weak self] in
                    guard let self, self.showGeneration == generation, self.session.isOpen else { return }
                    let face = self.faceForShowing()
                    self.presenter.show(
                        face, centre: centre, screen: self.screen,
                        lit: self.session.lit, takesClicks: self.session.phase == .latched
                    )
                }
                // A hand that stopped between the dead zone and twice of it lights its
                // place the moment the first moments are over, not at the timer's next look.
                environment.scheduleAfter(ShortcutRingSession.quickRelease + 0.005) { [weak self] in
                    guard let self, self.showGeneration == generation, self.session.phase == .held else { return }
                    self.perform(self.session.timePassed(to: self.environment.now()))
                }
                environment.log("Shortcut Ring: opened by \(openedBy)"
                    + (ring.freezePointer ? ", the pointer is kept still while it is held" : ""))
            case .light(let place):
                presenter.light(place)
                if let place {
                    placeWasLit(place)
                }
            case .close:
                showGeneration += 1
                presenter.hide()
                closed = true
            case .run(let place):
                let chosen = ring[place]
                guard chosen.runs else { continue }
                ran = Self.logName(of: chosen)
                lastRun = environment.now()
                if let code = hapticCode {
                    lastTick = environment.now()
                    let play = environment.playHaptic
                    environment.schedule { play(.commit, code) }
                }
                // After the panel is gone, and after this callback has returned.
                let run = environment.run
                guard Self.diagnosesRuns else {
                    environment.schedule { run(chosen) }
                    continue
                }
                // TEMPORARY DIAGNOSTIC (see above).
                let name = Self.logName(of: chosen)
                let late = releasing && chosen.shortcut?.identifier == SystemShortcut.showDesktop.identifier
                let log = environment.log
                log("Ring diagnostic: \(name) chosen by \(releasing ? "letting go" : "a click")"
                    + "\(late ? ", sent 0.15 s late" : ""): \(Self.inputStateLine())")
                let send = {
                    log("Ring diagnostic: \(name) is sent now: \(Self.inputStateLine())")
                    run(chosen)
                }
                if late {
                    environment.scheduleAfter(Self.diagnosticDelay, send)
                } else {
                    environment.schedule(send)
                }
                environment.scheduleAfter((late ? Self.diagnosticDelay : 0) + 0.06) {
                    log("Ring diagnostic: 60 ms after \(name) was sent: \(Self.inputStateLine())")
                }
            }
        }
        if closed {
            environment.log(ran.map { "Shortcut Ring: closed, ran \($0)" } ?? "Shortcut Ring: closed, nothing ran")
            if !faceIsComplete {
                completeFaceLater()
            }
        }
        followTheSession()
    }

    /// The face for a ring that is being shown now, without a look on disk: the one made
    /// at a quiet moment if there is one for this ring, else names and plain symbols.
    private func faceForShowing() -> ShortcutRingFace {
        if let face { return face }
        if let prepared = Self.preparedFace, prepared.ring == ring {
            face = prepared.face
            faceIsComplete = true
            return prepared.face
        }
        let quick = ShortcutRingFace(ring, looksOnDisk: false)
        face = quick
        faceIsComplete = !ring.opensSomething
        return quick
    }

    /// After a ring that was shown without its icons has closed (and after its action was
    /// started): the whole face is made, for the next ring.
    private func completeFaceLater() {
        let wanted = ring
        environment.schedule { [weak self] in
            guard let self, !self.session.isOpen, self.ring == wanted, !self.faceIsComplete else { return }
            let whole = self.environment.makeFace(wanted)
            self.face = whole
            self.faceIsComplete = true
            Self.prepare(whole, for: wanted)
        }
    }

    private func placeWasLit(_ place: Int) {
        let now = environment.now()
        if let code = hapticCode, now - lastTick >= Self.tickSpacing {
            lastTick = now
            let play = environment.playHaptic
            environment.schedule { play(.lockIn, code) }
        }
        // (The face is made when the ring is shown; a place that lights before that, in
        // the same turn as the press, is not announced.)
        if let title = face?.places[place].title {
            let announce = environment.announce
            environment.schedule { announce(title) }
        }
    }

    /// Brings the taps, the panel and the timer in line with the session.
    private func followTheSession() {
        let phase = session.phase
        let held = phase == .held
        // The pointer is kept still for the hold alone: it is let go the moment the hold
        // ends, however it ends, so a ring that stays open has a pointer to click with.
        let freezes = held && ring.freezePointer
        if freezes != holdsPointer {
            holdsPointer = freezes
            if freezes {
                environment.lockPointer()
            } else {
                environment.unlockPointer()
            }
        }
        if held != wasHeld {
            wasHeld = held
            environment.refreshMotionTap()
        }
        let keys = session.needsKeys
        if keys != neededKeys {
            neededKeys = keys
            environment.refreshKeyTap()
        }
        guard phase != timerPhase else { return }
        timerPhase = phase
        stopTimer()
        if phase == .latched {
            if clickWatch == nil {
                clickWatch = environment.watchClicksElsewhere { [weak self] window in
                    self?.clickWentElsewhere(in: window)
                }
            }
        } else if let watch = clickWatch {
            clickWatch = nil
            environment.stopWatchingClicksElsewhere(watch)
        }
        switch phase {
        case .closed:
            break
        case .held:
            presenter.setTakesClicks(false)
            startTimer(every: Self.holdCheckInterval)
        case .latched:
            presenter.setTakesClicks(true)
            startTimer(every: Self.pointerInterval)
            environment.log("Shortcut Ring: left open (the trigger was let go with nothing lit)")
        }
    }

    private func startTimer(every interval: TimeInterval) {
        timer = environment.makeTimer(interval) { [weak self] in
            self?.tick()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: The system's side

    /// What a place ran, for the log: a listed action by its identifier, anything else by
    /// its kind (never a key the user chose, never a path).
    static func logName(of place: ShortcutRingPlace) -> String {
        switch place.content {
        case .nothing: return "nothing"
        case .shortcut(let shortcut): return shortcut.identifier
        case .keyCombination: return "a recorded key combination"
        case .open(let target):
            switch target.kind {
            case .application: return "an app to open"
            case .file: return "a file to open"
            case .script: return "a script"
            }
        }
    }

    /// Runs a place's action as one press, as a direction of Gesture Navigation runs its
    /// action: through the executor, resolved from a binding built from the place (a
    /// recorded key combination and what to open are read from the binding, not from the
    /// name), down and then up for an action that is held (a key, a click).
    static func run(_ place: ShortcutRingPlace) {
        guard let action = place.resolvedAction else { return }
        let result = ShortcutExecutor.shared.execute(action: action, phase: .down)
        if action.executionMode == .stateful {
            ShortcutExecutor.shared.execute(action: action, phase: .up, mouseSessionID: result.mouseSessionID)
        }
    }

    /// The ring takes no focus, so VoiceOver would never say what is lit: it is announced.
    /// Nothing happens without VoiceOver.
    static func announce(_ text: String) {
        guard NSWorkspace.shared.isVoiceOverEnabled, let app = NSApp else { return }
        NSAccessibility.post(element: app, notification: .announcementRequested, userInfo: [
            .announcement: text,
            .priority: NSAccessibilityPriorityLevel.medium.rawValue,
        ])
    }
}
