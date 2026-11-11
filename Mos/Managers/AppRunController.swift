//
//  AppRunController.swift
//  Mos
//  Whether Scrollio's event handling runs: the scroll and button event taps and the
//  Logitech sessions ("the cores"). One path starts and stops them:
//
//  - start(): at launch and after waking. With Accessibility access the cores start; without
//    it the Welcome Guide opens and a timer waits for the access. Cores that run already are
//    not started again.
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

    init(environment: Environment) {
        self.environment = environment
    }

    deinit {
        recoveryTimer?.invalidate()
    }

    /// The cores do not run because the access is missing (not paused, not merely asleep).
    var isWaitingForAccess: Bool {
        return recoveryTimer != nil
    }

    // MARK: - Lifecycle

    /// Launch, wake, resume. Does nothing while paused, while another user has the Mac, or
    /// when the cores run already.
    func start() {
        defer { postChange() }
        guard !isPaused, isSessionActive else { return }
        guard !coresActive else {
            cancelRecovery()
            return
        }
        if environment.hasAccess() {
            NSLog("Regular Initialization")
            cancelRecovery()
            startCoresOrRetry()
        } else {
            // Not in the Accessibility list (or switched off there): the Welcome Guide
            // explains it, and the timer starts the cores once the access is there.
            environment.showWelcomeGuide()
            scheduleRecovery(every: Self.launchRecoveryInterval)
        }
    }

    /// Mac going to sleep, app quitting.
    func stop() {
        cancelRecovery()
        stopCores()
        postChange()
    }

    /// Another user took the Mac: stop, and stay stopped (also through sleep and wake)
    /// until this session is active again.
    func sessionDidResign() {
        NSLog("Scrollio: another user has the Mac, the event taps stop")
        isSessionActive = false
        stop()
    }

    /// This user is back.
    func sessionDidBecomeActive() {
        NSLog("Scrollio: this user has the Mac again")
        isSessionActive = true
        start()
    }

    /// An event tap found the access gone. Several taps may report it at once: only the
    /// first one while the cores run does anything.
    func accessWasLost() {
        guard coresActive else { return }
        NSLog("Accessibility permission lost at runtime, disabling cores")
        stopCores()
        environment.showAccessLostToast()
        scheduleRecovery(every: Self.lostRecoveryInterval)
        postChange()
    }

    /// Pause or resume from the status-bar menu.
    func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        isPaused = paused
        NSLog(paused ? "Paused by the user" : "Resumed by the user")
        if paused {
            stop()
        } else {
            start()
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
    private func startCoresOrRetry() {
        if environment.startCores() {
            coresActive = true
            return
        }
        NSLog("Scrollio: the event taps could not be started; trying again in %.0f s", Self.launchRecoveryInterval)
        environment.stopCores()
        coresActive = false
        scheduleRecovery(every: Self.launchRecoveryInterval)
    }

    private func stopCores() {
        environment.stopCores()
        coresActive = false
    }

    private func scheduleRecovery(every interval: TimeInterval) {
        recoveryTimer?.invalidate()
        recoveryTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.recoveryTick()
        }
    }

    private func cancelRecovery() {
        recoveryTimer?.invalidate()
        recoveryTimer = nil
    }

    private func recoveryTick() {
        guard !isPaused, isSessionActive, !coresActive, environment.hasAccess() else { return }
        NSLog("First Initialization (Accessibility Authorization Needed)")
        cancelRecovery()
        startCoresOrRetry()
        postChange()
    }

    private func postChange() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
