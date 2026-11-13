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
//    one, should the panel not have taken it) closes the ring and runs nothing: while a
//    ring stands open, and only then, a monitor hears of such clicks.
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
//  Nothing is drawn and nothing is posted inside an event callback: the panel is shown on
//  the next turn of the main queue, and so is the chosen action, after the panel is gone.
//  A pulse (`MouseGestureHapticCue`) is played only for a trigger that arrived over HID++,
//  on the mouse it belongs to: a light one when a place lights (at most one every
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
        /// A repeating timer, or nil when the caller drives `tick()` itself (tests).
        var makeTimer: (TimeInterval, @escaping () -> Void) -> Timer?
        /// The ring this Mac's settings hold.
        var ring: () -> ShortcutRingSettings
        /// Runs a place's shortcut.
        var run: (SystemShortcut.Shortcut) -> Void
        /// Plays a pulse on the mouse the button with this code was pressed on.
        var playHaptic: (MouseGestureHapticCue, UInt16) -> Void
        /// Says the lit action's name to VoiceOver.
        var announce: (String) -> Void
        /// The held state changed: the pointer-movement tap follows it.
        var refreshMotionTap: () -> Void
        /// Whether the ring needs the keyboard changed: the keys tap follows it.
        var refreshKeyTap: () -> Void
        /// One line of the `app` log: a ring opened, was left open, ran something or
        /// closed. A few lines per use of the ring, never one per pointer event.
        var log: (String) -> Void
        /// Something that should not happen did: a line of the `app` log as a problem.
        var logProblem: (String) -> Void
        /// Starts to hear of mouse-downs that went to other apps; the result ends it
        /// (`stopWatchingClicksElsewhere`). Nil: nothing was started (tests).
        var watchClicksElsewhere: (@escaping () -> Void) -> Any?
        var stopWatchingClicksElsewhere: (Any) -> Void

        static let system = Environment(
            now: { ProcessInfo.processInfo.systemUptime },
            pointerLocation: { ShortcutRingScreens.pointerLocation() },
            screen: { ShortcutRingScreens.screen(containing: $0) },
            isPrimaryButtonDown: { NSEvent.pressedMouseButtons & 0b11 != 0 },
            schedule: { DispatchQueue.main.async(execute: $0) },
            makeTimer: { interval, block in
                // Under XCTest no timer runs; a test calls `tick()`.
                guard !AppRuntime.isRunningXCTest else { return nil }
                return CommonModesTimer.scheduled(withTimeInterval: interval, repeats: true) { _ in block() }
            },
            ring: { Options.shared.ring },
            run: { ShortcutRingController.run($0) },
            playHaptic: { cue, code in LogiCenter.shared.playGestureHaptic(cue, forScrollioCode: code) },
            announce: { ShortcutRingController.announce($0) },
            refreshMotionTap: { MouseInteractionSessionController.shared.refreshMotionTapState() },
            refreshKeyTap: { ButtonCore.shared.keyTap.refresh() },
            log: { AppSystemLog.note($0) },
            logProblem: { AppSystemLog.problem($0) },
            watchClicksElsewhere: { handler in
                // Under XCTest nothing listens to the Mac's clicks.
                guard !AppRuntime.isRunningXCTest else { return nil }
                return NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { _ in
                    handler()
                }
            },
            stopWatchingClicksElsewhere: { NSEvent.removeMonitor($0) }
        )
    }

    /// Between two light pulses; a place that lights sooner gets none.
    static let tickSpacing: TimeInterval = 0.1
    /// How often the pointer is looked at while the ring stands open.
    static let pointerInterval: TimeInterval = 1.0 / 60.0
    /// How often a held ring is checked against its limit.
    static let holdCheckInterval: TimeInterval = 0.5

    var environment: Environment
    let presenter: ShortcutRingPresenting

    // MARK: State

    private(set) var session = ShortcutRingSession()
    /// The ring as it was when it opened: what is shown and what a place runs.
    private var ring = ShortcutRingSettings.default
    private var face: ShortcutRingFace?
    /// The screen the ring opened on.
    private var screen = ShortcutRingScreen(frame: .zero, usable: .zero)
    /// The button to name when asking for a pulse: set for a trigger that arrived over
    /// HID++, nil otherwise.
    private var hapticCode: UInt16?
    /// What opened the ring, for the log.
    private var openedBy = ""
    private var lastTick = -TimeInterval.infinity
    /// Drops a show that was scheduled for a ring that is gone.
    private var showGeneration = 0
    private var timer: Timer?
    private var timerPhase = ShortcutRingSession.Phase.closed
    private var lastPolledPointer: CGPoint?
    private var wasHeld = false
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

    // MARK: The trigger (InputProcessor)

    /// The ring's trigger went down. Never a key's auto-repeat.
    func triggerPressed(by event: InputEvent) {
        assertMainThread()
        if !session.isOpen {
            // In the middle of a drag the ring stays away.
            guard !environment.isPrimaryButtonDown() else { return }
            let stored = environment.ring()
            if stored != ring || face == nil {
                ring = stored
                face = nil
            }
            if case .hidPP = event.source {
                hapticCode = event.code
            } else {
                hapticCode = nil
            }
            openedBy = Self.kind(of: event)
        }
        let pointer = Self.pointerLocation(of: event) ?? environment.pointerLocation()
        if !session.isOpen {
            screen = environment.screen(pointer)
        }
        perform(session.triggerPressed(
            at: environment.now(), pointer: pointer, screen: screen.usable, filled: ring.filled
        ))
    }

    /// The trigger came up; `isMadeUp` for a release Scrollio made up itself.
    func triggerReleased(isMadeUp: Bool) {
        assertMainThread()
        perform(session.triggerReleased(at: environment.now(), isMadeUp: isMadeUp))
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
        perform(session.pointerMoved(by: delta, to: location, at: environment.now()))
    }

    /// One look of the timer: where the pointer is over an open ring, and whether the
    /// ring's time is up.
    func tick() {
        guard session.isOpen else {
            stopTimer()
            return
        }
        let now = environment.now()
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
    func clickWentElsewhere() {
        assertMainThread()
        guard session.phase == .latched else { return }
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
        let names: [(NotificationCenter, Notification.Name)] = [
            (workspace, NSWorkspace.activeSpaceDidChangeNotification),
            (workspace, NSWorkspace.didActivateApplicationNotification),
            (NotificationCenter.default, NSApplication.didChangeScreenParametersNotification),
        ]
        for (center, name) in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self, self.session.isOpen else { return }
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
                // Not inside the event callback this runs in: a panel is made and shown
                // on the main queue's next turn.
                environment.schedule { [weak self] in
                    guard let self, self.showGeneration == generation, self.session.isOpen else { return }
                    let face = self.face ?? ShortcutRingFace(self.ring)
                    self.face = face
                    self.presenter.show(
                        face, centre: centre, screen: self.screen,
                        lit: self.session.lit, takesClicks: self.session.phase == .latched
                    )
                }
                environment.log("Shortcut Ring: opened by \(openedBy)")
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
                guard let shortcut = ring[place].shortcut else { continue }
                ran = shortcut.identifier
                if let code = hapticCode {
                    lastTick = environment.now()
                    let play = environment.playHaptic
                    environment.schedule { play(.commit, code) }
                }
                // After the panel is gone, and after this callback has returned.
                let run = environment.run
                environment.schedule { run(shortcut) }
            }
        }
        if closed {
            environment.log(ran.map { "Shortcut Ring: closed, ran \($0)" } ?? "Shortcut Ring: closed, nothing ran")
        }
        followTheSession()
    }

    private func placeWasLit(_ place: Int) {
        let now = environment.now()
        if let code = hapticCode, now - lastTick >= Self.tickSpacing {
            lastTick = now
            let play = environment.playHaptic
            environment.schedule { play(.lockIn, code) }
        }
        if let title = face?.places[place].title ?? ring[place].shortcut?.localizedName {
            let announce = environment.announce
            environment.schedule { announce(title) }
        }
    }

    /// Brings the taps, the panel and the timer in line with the session.
    private func followTheSession() {
        let phase = session.phase
        let held = phase == .held
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
                clickWatch = environment.watchClicksElsewhere { [weak self] in
                    self?.clickWentElsewhere()
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

    /// Runs a shortcut as one press, as a direction of Gesture Navigation runs its action.
    static func run(_ shortcut: SystemShortcut.Shortcut) {
        guard let action = ShortcutExecutor.shared.resolveAction(named: shortcut.identifier) else { return }
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
