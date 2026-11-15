//
//  AppRunController.swift
//  Mos
//  Whether Scrollio's event handling runs: the scroll and button event taps and the
//  Logitech sessions ("the cores"). One path starts and stops them:
//
//  - start(): at launch (and on resume). With Accessibility access the cores start; without
//    it the Welcome Guide opens and a timer waits for the access. Cores that run already are
//    not started again.
//  - wake(): after waking. The same, but without the access only the timer is armed again:
//    the Welcome Guide opened at launch and opens when the app is reopened, not at every wake.
//  - stop(): when the Mac goes to sleep (and when the app quits).
//  - sessionDidResign() / sessionDidBecomeActive(): fast user switching. While another user
//    has the Mac nothing starts the cores, also not waking up: a Logitech mouse diverted for
//    this account would lose its buttons for the other one.
//  - accessWasLost(): an event tap saw the access turned off while running. The cores stop,
//    a toast says so and a timer waits for the access to come back.
//  - setPaused(_:): "Pause Scrollio" in the status-bar menu. Pausing is stop(); resuming is
//    start(). While paused nothing starts the cores again, also not waking up. The pause is
//    never stored: a relaunch starts unpaused.
//  - pause(for:): the same pause with an end ("Pause For" › "15 Minutes", "1 Hour"). The end
//    is a moment (`pauseEnd`, a whole minute, never later than chosen), not a countdown: a
//    one-shot timer only wakes the check `endPauseIfDue()`, which also runs after a wake,
//    when this user is back and after a change of the clock (`clockDidChange()`), because a
//    timer does not count the time asleep. At its end the pause is over as after "Resume
//    Scrollio", but quietly: no window opens. The end, like the pause, is only in memory.
//  - tryAgainNow(): "Try Again Now" in the status-bar menu: a failed start's next try, now.
//
//  Starting: the event taps first, then the Logitech sessions, and only when every tap runs.
//  A start that fails half-way (a tap could not be created) stops everything again, so no tap
//  stays installed while the cores count as stopped, and the timer tries again.
//  Stopping: the event taps first, then the Logitech sessions, whose teardown gives the mice
//  their buttons back with synchronous HID writes; no active tap waits on this thread then.
//  The pointer-movement tap of gesture holds is made on demand while the cores run; the stop
//  releases it with the event taps, and the next hold makes a new one.
//
//  Every change posts `didChangeNotification`; the status item and the General pane follow it.
//  What starting and stopping does is in `Environment`, so the tests run the rules without
//  event taps, windows or toasts.
//
//  Each start, stop and retry writes one line to the system log (category `app`, see
//  AppSystemLog) with what caused it and how it ended.
//

import Cocoa

final class AppRunController {

    static let shared = AppRunController(environment: .live)

    /// Posted (object: the controller) after the cores started or stopped, or the pause changed.
    static let didChangeNotification = Notification.Name("ScrollioRunStateDidChange")

    /// Between two looks at the permission at launch, while the Welcome Guide is open.
    static let launchRecoveryInterval: TimeInterval = 10
    /// Between two looks at the permission after it was lost at run time.
    static let lostRecoveryInterval: TimeInterval = 2

    /// What starting and stopping does.
    struct Environment {
        var hasAccess: () -> Bool
        /// Starts the cores; false when they do not all run. The controller then calls
        /// `stopCores`, which must undo whatever did start.
        var startCores: () -> Bool
        /// Also gives the Logitech mice back what was diverted (LogiCenter.stop). Safe to call
        /// when nothing runs.
        var stopCores: () -> Void
        var showWelcomeGuide: () -> Void
        var showAccessLostToast: () -> Void
        /// The time, for a pause that ends by itself. A test hands in its own clock.
        var now: () -> Date = { Date() }

        /// One part of the cores, as starting and stopping sees it.
        struct Part {
            let start: () -> Void
            let stop: () -> Void
            /// After `start`: whether it runs (an event tap may fail to be created).
            let isRunning: () -> Bool
        }

        /// The order of starting and stopping. Start: the event taps in order, then the
        /// Logitech sessions, only once every tap runs (false otherwise). Stop: the event taps,
        /// then the taps made on demand while the cores run (`onDemandTaps`, each a release),
        /// then the Logitech sessions.
        ///
        /// A tap made on demand (the pointer-movement tap of gesture holds) does not start with
        /// the cores; it is released when they stop, so the next use makes a new one. Kept
        /// across a loss of the Accessibility access or a switch to another user, it could
        /// stay off for good.
        static func cores(
            eventTaps: [Part],
            onDemandTaps: [() -> Void] = [],
            logitech: Part
        ) -> (start: () -> Bool, stop: () -> Void) {
            let start: () -> Bool = {
                for tap in eventTaps {
                    tap.start()
                    guard tap.isRunning() else { return false }
                }
                logitech.start()
                return true
            }
            let stop: () -> Void = {
                for tap in eventTaps {
                    tap.stop()
                }
                for release in onDemandTaps {
                    release()
                }
                logitech.stop()
            }
            return (start, stop)
        }

        static let live: Environment = {
            let cores = Environment.cores(
                eventTaps: [
                    Part(start: { ScrollCore.shared.enable() },
                         stop: { ScrollCore.shared.disable() },
                         isRunning: { ScrollCore.shared.isActive }),
                    Part(start: { ButtonCore.shared.enable() },
                         stop: { ButtonCore.shared.disable() },
                         isRunning: { ButtonCore.shared.isActive }),
                ],
                // After ButtonCore, whose stop already ended any gesture hold.
                onDemandTaps: [{ MouseInteractionSessionController.shared.releaseMotionTap() }],
                logitech: Part(start: { LogiCenter.shared.start() },
                               stop: { LogiCenter.shared.stop() },
                               isRunning: { true })
            )
            return Environment(
                hasAccess: { Utils.isHadAccessibilityPermissions() },
                startCores: {
                    // The original Mos handles the same mouse events: it is asked to quit
                    // (and waited for) right before Scrollio's taps start, each time they
                    // start. Not at launch as such: while Scrollio does nothing, Mos stays.
                    LegacyAppQuitter.quitBeforeStarting()
                    return cores.start()
                },
                stopCores: cores.stop,
                showWelcomeGuide: { IntroductionWindowController.showAutomatically() },
                showAccessLostToast: {
                    Toast.show(NSLocalizedString("toast-accessibility-lost", comment: ""), style: .warning, duration: 5.0)
                }
            )
        }()
    }

    private let environment: Environment

    /// The cores run.
    private(set) var coresActive = false
    /// Paused from the status-bar menu. Only in memory.
    private(set) var isPaused = false
    /// When the pause ends by itself; nil while not paused, or paused until resumed. Only
    /// in memory, like the pause.
    private(set) var pauseEnd: Date?
    /// Wakes `endPauseIfDue()` at `pauseEnd`. The end is the truth, not this timer: it does
    /// not count the time the Mac was asleep.
    private(set) var pauseTimer: Timer?
    /// The length chosen for the pause that runs, for a change of the clock.
    private var pauseLength: TimeInterval?
    /// This user's session has the Mac (fast user switching). A launch happens in an active session.
    private(set) var isSessionActive = true
    /// Waits for the Accessibility access (at launch, or after it was lost).
    private(set) var recoveryTimer: Timer?
    /// The access is there but the cores did not all start (an event tap could not be
    /// created); the timer tries again. The status item says so instead of "needs access".
    private(set) var isRetryingStart = false
    /// Starts that failed in a row, for the log.
    private var failedStarts = 0

    init(environment: Environment) {
        self.environment = environment
    }

    deinit {
        recoveryTimer?.invalidate()
        pauseTimer?.invalidate()
    }

    /// The cores do not run because the access is missing (not paused, not merely asleep,
    /// not a start that failed with the access there).
    var isWaitingForAccess: Bool {
        return recoveryTimer != nil && !isRetryingStart
    }

    /// What started the cores, for the log.
    enum StartTrigger: String {
        case launch = "launch"
        case resume = "resumed by the user"
        case wake = "the Mac woke up"
        case userBack = "this user has the Mac again"
        case accessAllowed = "Accessibility access allowed"
        case accessBack = "Accessibility access is back"
        case retry = "retry"
        case pauseEnded = "the pause ended"
    }

    /// How long a pause lasts.
    enum PauseLength: Equatable {
        case fifteenMinutes
        case oneHour
        /// "Pause Scrollio": until "Resume Scrollio".
        case untilResumed

        /// nil: no end.
        var seconds: TimeInterval? {
            switch self {
            case .fifteenMinutes: return 15 * 60
            case .oneHour: return 60 * 60
            case .untilResumed: return nil
            }
        }
    }

    /// What stopped them, for the log.
    enum StopReason: String {
        case sleep = "the Mac goes to sleep"
        case quit = "Scrollio quits"
        case otherUser = "another user has the Mac"
        case paused = "paused by the user"
        case other = "stop requested"
    }

    // MARK: - Lifecycle

    /// Launch. Does nothing while paused, while another user has the Mac, or when the cores
    /// run already.
    func start() {
        start(.launch, showingWelcomeGuide: true)
    }

    /// The Mac woke up. Like `start()`, but without the access only the timer is armed again:
    /// every wake opened the Welcome Guide again while the access was missing.
    func wake() {
        // A pause whose end passed while the Mac slept is over: this wake starts the cores.
        _ = clearPauseIfDue()
        start(.wake, showingWelcomeGuide: false)
    }

    private func start(_ trigger: StartTrigger, showingWelcomeGuide: Bool) {
        defer { postChange() }
        guard !isPaused, isSessionActive else {
            AppSystemLog.note("Not starting (\(trigger.rawValue)): \(isPaused ? "paused by the user" : "another user has the Mac")")
            return
        }
        guard !coresActive else {
            cancelRecovery()
            return
        }
        if environment.hasAccess() {
            cancelRecovery()
            startCoresOrRetry(trigger)
        } else {
            // Not in the Accessibility list (or switched off there): the Welcome Guide
            // explains it, and the timer starts the cores once the access is there.
            AppSystemLog.note("Not starting (\(trigger.rawValue)): Accessibility access is missing; "
                + "checking again every \(Int(Self.launchRecoveryInterval)) s")
            isRetryingStart = false
            if showingWelcomeGuide {
                environment.showWelcomeGuide()
            }
            scheduleRecovery(every: Self.launchRecoveryInterval)
        }
    }

    /// Mac going to sleep, app quitting.
    func stop(because reason: StopReason = .other) {
        AppSystemLog.note("Stopped (\(reason.rawValue)): "
            + (coresActive ? "the event taps and the Logitech sessions are off" : "they were not running"))
        cancelRecovery()
        isRetryingStart = false
        stopCores()
        postChange()
    }

    /// Another user took the Mac: stop, and stay stopped (also through sleep and wake)
    /// until this session is active again.
    func sessionDidResign() {
        isSessionActive = false
        stop(because: .otherUser)
    }

    /// This user is back. Like a wake: without the access only the timer is armed again.
    func sessionDidBecomeActive() {
        isSessionActive = true
        _ = clearPauseIfDue()
        start(.userBack, showingWelcomeGuide: false)
    }

    /// An event tap found the access gone. Several taps may report it at once: only the
    /// first one while the cores run does anything.
    func accessWasLost() {
        guard coresActive else { return }
        AppSystemLog.problem("Accessibility access was turned off while Scrollio ran: stopped the event taps "
            + "and the Logitech sessions; checking for the access every \(Int(Self.lostRecoveryInterval)) s")
        stopCores()
        environment.showAccessLostToast()
        scheduleRecovery(every: Self.lostRecoveryInterval)
        postChange()
    }

    /// Pause or resume from the status-bar menu. A pause made here has no end ("Pause
    /// Scrollio"); resuming ends any pause, and its timer with it.
    func setPaused(_ paused: Bool) {
        guard paused else {
            guard isPaused else { return }
            isPaused = false
            clearPauseEnd()
            start(.resume, showingWelcomeGuide: true)
            return
        }
        pause(for: .untilResumed)
    }

    /// Pauses for `length`. Chosen again while paused, the last choice wins: the end is
    /// counted from now (or goes, for `.untilResumed`), and nothing is stopped a second time.
    func pause(for length: PauseLength) {
        let endBefore = pauseEnd
        clearPauseEnd()
        if let seconds = length.seconds {
            let end = Self.pauseEnd(from: environment.now(), after: seconds)
            pauseEnd = end
            pauseLength = seconds
            armPauseTimer(until: end)
            AppSystemLog.note("Pausing for at most \(Int(seconds / 60)) min: the pause ends by itself")
        } else if endBefore != nil {
            AppSystemLog.note("The pause no longer ends by itself: paused until resumed")
        }
        if !isPaused {
            isPaused = true
            stop(because: .paused)
        } else if pauseEnd != endBefore {
            postChange()
        }
    }

    /// The end of a pause of `length` seconds made at `now`: the whole minute it falls in,
    /// so the minute the menu shows is the moment it ends, never later than chosen and up
    /// to 59 s sooner. Pure.
    static func pauseEnd(from now: Date, after length: TimeInterval) -> Date {
        let end = now.timeIntervalSince1970 + length
        return Date(timeIntervalSince1970: (end / 60).rounded(.down) * 60)
    }

    /// A timed pause whose end has come is over, as after "Resume Scrollio", but quietly:
    /// the Welcome Guide does not open (without the access only the timer waits for it),
    /// and while another user has the Mac nothing starts until this one is back. Before
    /// the end (the timer fired early, the Mac woke up, the clock changed) the timer is
    /// armed again for what is left. Nothing while not paused, or paused until resumed.
    func endPauseIfDue() {
        if clearPauseIfDue() {
            start(.pauseEnded, showingWelcomeGuide: false)
        }
    }

    /// The clock or the time zone of the Mac changed. The end is never later than the
    /// chosen length counted from now, so a clock set back does not make a pause longer
    /// than chosen; set past the end, the pause ends now. A new time zone keeps the moment
    /// and changes how it reads: the status item and General read it again.
    func clockDidChange() {
        guard isPaused, let end = pauseEnd, let length = pauseLength else { return }
        pauseEnd = min(end, Self.pauseEnd(from: environment.now(), after: length))
        if clearPauseIfDue() {
            start(.pauseEnded, showingWelcomeGuide: false)
        } else {
            postChange()
        }
    }

    /// "Try Again Now" in the status-bar menu: a start that failed with the access there is
    /// tried at once, as the timer would try it. Nothing otherwise (waiting for the access,
    /// paused, running).
    func tryAgainNow() {
        guard isRetryingStart else { return }
        recoveryTimer?.fire()
    }

    /// The Welcome Guide saw the permission arrive: the timer's next look, now, so the window
    /// can say that Scrollio is running. Nothing happens when no timer is waiting.
    func accessibilityPermissionWasGranted() {
        recoveryTimer?.fire()
    }

    /// macOS said that the Accessibility list changed (AppDelegate, a moment after the
    /// notification). While the cores run and the access is gone: the same as an event tap
    /// finding it gone, only up to 5 s sooner. While they wait for the access: the timer's
    /// next look, now. Anything else: nothing.
    func accessibilityListDidChange() {
        if coresActive {
            if !environment.hasAccess() {
                accessWasLost()
            }
        } else {
            recoveryTimer?.fire()
        }
    }

    // MARK: - Private

    /// Starts the cores. When they do not all start, whatever did is stopped again and the
    /// timer tries again later.
    private func startCoresOrRetry(_ trigger: StartTrigger) {
        if environment.startCores() {
            coresActive = true
            isRetryingStart = false
            AppSystemLog.note("Started (\(trigger.rawValue)): the event taps and the Logitech sessions run"
                + (failedStarts > 0 ? " (after \(failedStarts) failed \(failedStarts == 1 ? "start" : "starts"))" : ""))
            failedStarts = 0
            return
        }
        failedStarts += 1
        if Self.logsFailedStart(failedStarts) {
            AppSystemLog.problem(Self.failedStartLine(trigger: trigger, failedStarts: failedStarts))
        }
        environment.stopCores()
        coresActive = false
        isRetryingStart = true
        scheduleRecovery(every: Self.launchRecoveryInterval)
    }

    /// A start that keeps failing is tried every 10 s: the first three failures are written,
    /// then one in 30 (every 5 minutes).
    static func logsFailedStart(_ failedStarts: Int) -> Bool {
        return failedStarts <= 3 || failedStarts % 30 == 0
    }

    static func failedStartLine(trigger: StartTrigger, failedStarts: Int) -> String {
        return "Could not start (\(trigger.rawValue)): an event tap could not be created although Accessibility "
            + "access is allowed; trying again in \(Int(launchRecoveryInterval)) s (failed starts in a row: \(failedStarts))"
    }

    private func stopCores() {
        environment.stopCores()
        coresActive = false
    }

    private func scheduleRecovery(every interval: TimeInterval) {
        recoveryTimer?.invalidate()
        // Also while a menu is open (CommonModesTimer).
        recoveryTimer = CommonModesTimer.scheduled(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.recoveryTick()
        }
    }

    private func cancelRecovery() {
        recoveryTimer?.invalidate()
        recoveryTimer = nil
    }

    private func recoveryTick() {
        guard !isPaused, isSessionActive, !coresActive else { return }
        guard environment.hasAccess() else {
            if isRetryingStart {
                // The access went away while a failed start waited: now it waits for the access.
                isRetryingStart = false
                postChange()
            }
            return
        }
        let trigger: StartTrigger
        if isRetryingStart {
            trigger = .retry
        } else {
            trigger = recoveryTimer?.timeInterval == Self.lostRecoveryInterval ? .accessBack : .accessAllowed
        }
        cancelRecovery()
        startCoresOrRetry(trigger)
        postChange()
    }

    /// True when a timed pause was due and is over now (the caller starts the cores).
    /// Before its end the timer is armed again for what is left.
    private func clearPauseIfDue() -> Bool {
        guard isPaused, let end = pauseEnd else { return false }
        guard environment.now() >= end else {
            armPauseTimer(until: end)
            return false
        }
        AppSystemLog.note("The pause's time is up: Scrollio is no longer paused")
        isPaused = false
        clearPauseEnd()
        return true
    }

    private func clearPauseEnd() {
        pauseTimer?.invalidate()
        pauseTimer = nil
        pauseEnd = nil
        pauseLength = nil
    }

    private func armPauseTimer(until end: Date) {
        pauseTimer?.invalidate()
        // One shot, also while a menu is open (CommonModesTimer).
        let interval = max(0, end.timeIntervalSince(environment.now()))
        pauseTimer = CommonModesTimer.scheduled(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.endPauseIfDue()
        }
    }

    private func postChange() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
