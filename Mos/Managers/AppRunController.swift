//
//  AppRunController.swift
//  Mos
//  Whether Scrollio's event handling runs: the scroll and button event taps and the
//  Logitech sessions ("the cores"). One path starts and stops them:
//
//  - start(): at launch, when the user session becomes active again and after waking. With
//    Accessibility access the cores start; without it the Welcome Guide opens and a timer
//    waits for the access.
//  - stop(): when the session resigns or the Mac goes to sleep.
//  - accessWasLost(): an event tap saw the access turned off while running. The cores stop,
//    a toast says so and a timer waits for the access to come back.
//  - setPaused(_:): "Pause Scrollio" in the status-bar menu. Pausing is stop(); resuming is
//    start(). While paused nothing starts the cores again, also not waking up. The pause is
//    never stored: a relaunch starts unpaused.
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
        var startCores: () -> Void
        /// Also gives the Logitech mice back what was diverted (LogiCenter.stop).
        var stopCores: () -> Void
        var showWelcomeGuide: () -> Void
        var showAccessLostToast: () -> Void

        static let live = Environment(
            hasAccess: { Utils.isHadAccessibilityPermissions() },
            startCores: {
                ScrollCore.shared.enable()
                ButtonCore.shared.enable()
                LogiCenter.shared.start()
            },
            stopCores: {
                LogiCenter.shared.stop()
                ScrollCore.shared.disable()
                ButtonCore.shared.disable()
            },
            showWelcomeGuide: {
                WindowManager.shared.showWindow(withIdentifier: WINDOW_IDENTIFIER.introductionWindowController)
            },
            showAccessLostToast: {
                Toast.show(NSLocalizedString("toast-accessibility-lost", comment: ""), style: .warning, duration: 5.0)
            }
        )
    }

    private let environment: Environment

    /// The cores run.
    private(set) var coresActive = false
    /// Paused from the status-bar menu. Only in memory.
    private(set) var isPaused = false
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

    /// Launch, session active, wake, resume. Does nothing while paused.
    func start() {
        defer { postChange() }
        guard !isPaused else { return }
        if environment.hasAccess() {
            NSLog("Regular Initialization")
            cancelRecovery()
            startCores()
        } else {
            // Not in the Accessibility list (or switched off there): the Welcome Guide
            // explains it, and the timer starts the cores once the access is there.
            environment.showWelcomeGuide()
            scheduleRecovery(every: Self.launchRecoveryInterval)
        }
    }

    /// Session resigned, Mac going to sleep.
    func stop() {
        cancelRecovery()
        stopCores()
        postChange()
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

    private func startCores() {
        environment.startCores()
        coresActive = true
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
        guard !isPaused, environment.hasAccess() else { return }
        NSLog("First Initialization (Accessibility Authorization Needed)")
        cancelRecovery()
        startCores()
        postChange()
    }

    private func postChange() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
