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
//
//  Starting: the event taps first, then the Logitech sessions, and only when every tap runs.
//  A start that fails half-way (a tap could not be created) stops everything again, so no tap
//  stays installed while the cores count as stopped, and the timer tries again.
//  Stopping: the event taps first, then the Logitech sessions, whose teardown gives the mice
//  their buttons back with synchronous HID writes; no active tap waits on this thread then.
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

        /// One part of the cores, as starting and stopping sees it.
        struct Part {
            let start: () -> Void
            let stop: () -> Void
            /// After `start`: whether it runs (an event tap may fail to be created).
            let isRunning: () -> Bool
        }

        /// The order of starting and stopping. Start: the event taps in order, then the
        /// Logitech sessions, only once every tap runs (false otherwise). Stop: the event taps,
        /// then the Logitech sessions.
        static func cores(eventTaps: [Part], logitech: Part) -> (start: () -> Bool, stop: () -> Void) {
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
                logitech: Part(start: { LogiCenter.shared.start() },
                               stop: { LogiCenter.shared.stop() },
                               isRunning: { true })
            )
            return Environment(
                hasAccess: { Utils.isHadAccessibilityPermissions() },
                startCores: cores.start,
                stopCores: cores.stop,
                showWelcomeGuide: {
                    WindowManager.shared.showWindow(withIdentifier: WINDOW_IDENTIFIER.introductionWindowController)
                },
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

    /// Pause or resume from the status-bar menu.
    func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        isPaused = paused
        if paused {
            stop(because: .paused)
        } else {
            start(.resume, showingWelcomeGuide: true)
        }
    }

    /// The Welcome Guide saw the permission arrive: the timer's next look, now, so the window
    /// can say that Scrollio is running. Nothing happens when no timer is waiting.
    func accessibilityPermissionWasGranted() {
        recoveryTimer?.fire()
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

    private func postChange() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
