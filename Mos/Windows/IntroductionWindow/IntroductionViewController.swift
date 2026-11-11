//
//  IntroductionViewController.swift
//  Mos
//  The Welcome Guide, built in code (the storyboard scene is only a shell): one window of
//  600 × 680 pt (620 on a short screen) that never changes its size, with up to four steps (Welcome, Allow
//  Accessibility, Choose how scrolling feels, Scrollio is ready). This controller owns the
//  steps of a run (WelcomeGuideFlow), the bar under them (Back, the dots, the main button),
//  the change from one step to the next, and everything about the permission:
//
//  - the main button of the Accessibility step asks macOS (which adds Scrollio to the
//    Accessibility list, switched off, and may show its own alert) and opens the
//    Accessibility pane of System Settings;
//  - the permission is checked every second while the window shows, and when the app
//    becomes active; when it arrives the app's recovery starts the event taps at once
//    (`accessWasGranted`), VoiceOver is told and Scrollio comes back to the front;
//  - the step may go on once the access is allowed and the event taps run; when they
//    cannot start it says so, and AppRunController keeps trying;
//  - "Having trouble?" shows the help for a stale entry; it opens by itself once when the
//    user comes back from System Settings without the access.
//
//  Done (or Open Settings) marks the guide finished, and so does closing the window once
//  the access is allowed (WelcomeGuideProgress). Leaving the last step (Done, Open Settings,
//  or closing the window there) also applies its "Open at login" switch as it shows, through
//  General's code (LoginItem); nothing is registered before. Return presses the main button,
//  ⌘[ goes back, Esc does nothing (it does not close the guide either); with Reduce Motion
//  the steps change by a short crossfade. The bar takes one press per click: the second
//  click of a double-click, a held key and a press while the steps change do nothing, so
//  no step is skipped unseen.
//
//  Created by Caldis on 15/11/2019.
//  Copyright © 2019 Caldis. All rights reserved.
//

import Cocoa

/// One step as the container shows it: a picture for the top card and the text area.
protocol WelcomeGuideStepView: AnyObject {
    var step: WelcomeGuideStep { get }
    var picture: NSView { get }
    var content: NSView { get }
    /// The step came on screen (its loops and timers may run) or went away.
    func setShown(_ shown: Bool)
}

final class IntroductionViewController: NSViewController, NSPopoverDelegate {

    // MARK: - Seams (tests replace them: no prompt, no other app, no window on screen)

    /// Whether macOS lets Scrollio use the Accessibility API right now.
    var isAccessGranted: () -> Bool = { Utils.isHadAccessibilityPermissions() }
    /// Asks macOS for the permission. It adds Scrollio to the Accessibility list and,
    /// when macOS decides to, shows the system prompt.
    var requestAccess: () -> Void = { Utils.requireAccessibilityPermissions() }
    /// Opens System Settings › Privacy & Security › Accessibility.
    var openAccessibilitySettings: () -> Void = IntroductionViewController.openAccessibilityPane
    /// Selects the app in Finder, so it can be dragged into the Accessibility list.
    var revealApplication: () -> Void = {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }
    /// The permission arrived while the window was open: the app starts its event taps now.
    var accessWasGranted: () -> Void = {
        (NSApp.delegate as? AppDelegate)?.accessibilityPermissionWasGranted()
    }
    /// Whether Scrollio's event taps run (AppRunController).
    var runState: () -> WelcomeGuideRunState = IntroductionViewController.liveRunState
    /// Whether the menu bar icon is hidden (General › Show in menu bar is off).
    var isMenuBarIconHidden: () -> Bool = { Options.shared.general.hideStatusItem }
    /// Opens the Preferences window on Scrolling ("Open Settings" on the last step).
    var openAppSettings: () -> Void = {
        MainMenuManager.showPreferencesWindow(paneIdentifier: PANEL_IDENTIFIER.scrolling)
    }
    /// Accessibility › Display › Reduce motion: steps change by a crossfade, pictures stand still.
    var prefersReducedMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// Whether the guide was finished, and where that is stored.
    var progress = WelcomeGuideProgress.live
    /// The drawing for the connected mouse.
    var mouseSource: () -> MouseArtworkModel = {
        MouseArtworkModel.model(forDeviceName: MousePaneModel.shownMouse()?.deviceName)
    }
    /// The scroll options the feel step picks for (the Scrolling pane's).
    var scrollOptions: () -> OPTIONS_SCROLL_DEFAULT = { Options.shared.scroll }
    /// Whether the scroll engine smooths the feel step's page (Scrollio's own window).
    var tryAreaState: () -> WelcomeGuideTryArea = IntroductionViewController.liveTryAreaState
    /// Brings the guide back to the front (the access arrived while System Settings was).
    var bringToFront: (NSWindow?) -> Void = { window in
        guard let window, window.isVisible else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    /// Tells VoiceOver something that changed out of sight.
    var announce: (String) -> Void = { message in
        NSAccessibility.post(
            element: NSApp as Any, notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue]
        )
    }
    /// Shows the help of "Having trouble?" under its link.
    var presentHelp: (NSPopover, NSView) -> Void = { popover, link in
        popover.show(relativeTo: link.bounds, of: link, preferredEdge: .maxY)
    }
    /// The event a button of the bar is pressed with (a held key).
    var currentEvent: () -> NSEvent? = { NSApp.currentEvent }
    /// The clock the bar measures the time since the last step change with.
    var uptime: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    /// How long after a step change the bar takes no press: the second click of a
    /// double-click lands on the button that now means the next step.
    static let pressSettleTime: TimeInterval = 0.4

    // MARK: - State

    /// The run on screen; set by `begin`, or at loading the one the app opens by itself.
    private(set) var flow: WelcomeGuideFlow?
    /// Its steps, and the one shown.
    private(set) var steps: [WelcomeGuideStep] = []
    private(set) var index = 0
    private(set) var accessState: WelcomeGuideAccessState = .missing
    private(set) var isHelpShown = false
    /// "Open Accessibility Settings" was used; the help opens by itself once when the user
    /// comes back and the access is still missing.
    private(set) var didOpenSettings = false
    private var didOfferHelp = false
    private var helpPopover: NSPopover?
    private var transitionGeneration = 0
    /// The grant was reported to the app in this run (`accessWasGranted`).
    private var didReportGrant = false
    /// `refreshAccessState` is running: reporting the grant comes back into it.
    private var isRefreshingAccess = false
    /// When Continue or Back last changed the step, on `uptime`'s clock.
    private var stepChangedAt = -TimeInterval.infinity
    /// Steps are changing: until the incoming text is in, presses do nothing.
    private(set) var isChangingStep = false {
        didSet {
            pictureHost?.takesClicks = !isChangingStep
            contentHost?.takesClicks = !isChangingStep
        }
    }
    /// "Open at login" of the last step: what the user leaves with, and what the system
    /// said when the run began (an untouched switch changes nothing in the system).
    private(set) var openAtLoginChoice = false
    private(set) var openAtLoginAtStart = false

    /// Polls the permission while the window is open.
    private(set) var accessibilityPermissionsCheckerTimer: Timer?

    var currentStep: WelcomeGuideStep? {
        return steps.indices.contains(index) ? steps[index] : nil
    }

    // MARK: - Views (read access for tests)

    private(set) var pictureHost: WelcomeGuideStepHost!
    private(set) var contentHost: WelcomeGuideStepHost!
    private(set) var backButton: NSButton!
    private(set) var primaryButton: NSButton!
    /// "Open Settings", next to Done on the last step.
    private(set) var secondaryButton: NSButton!
    private(set) var dots: WelcomeGuideStepDots!

    private(set) lazy var welcomeStep: WelcomeGuideWelcomeStep = {
        let step = WelcomeGuideWelcomeStep(mouseSource: { [weak self] in self?.mouseSource() ?? .generic })
        step.artwork.prefersReducedMotion = reducedMotion
        return step
    }()

    private(set) lazy var accessStep: WelcomeGuideAccessStep = {
        let step = WelcomeGuideAccessStep(target: self, helpAction: #selector(helpButtonClicked(_:)))
        step.artwork.prefersReducedMotion = reducedMotion
        step.statusBox.prefersReducedMotion = reducedMotion
        step.show(accessState, context: accessContext)
        return step
    }()

    /// What the Accessibility step's status line depends on besides the state.
    private var accessContext: WelcomeGuideAccessStep.Context {
        let index = steps.firstIndex(of: .access)
        return WelcomeGuideAccessStep.Context(
            menuBarIconHidden: isMenuBarIconHidden(),
            stepFollows: index.map { $0 < steps.count - 1 } ?? false,
            settingsOpened: didOpenSettings
        )
    }

    private func showAccessState() {
        accessStep.show(accessState, context: accessContext)
    }

    private(set) lazy var feelStep: WelcomeGuideFeelStep = {
        let step = WelcomeGuideFeelStep(
            scrollOptions: { [weak self] in self?.scrollOptions() ?? Options.shared.scroll },
            tryAreaState: { [weak self] in self?.tryAreaState() ?? .notRunning },
            mouseSource: { [weak self] in self?.mouseSource() ?? .generic }
        )
        step.artwork.prefersReducedMotion = reducedMotion
        return step
    }()

    private(set) lazy var finishStep: WelcomeGuideFinishStep = {
        let step = WelcomeGuideFinishStep(
            isMenuBarIconHidden: { [weak self] in self?.isMenuBarIconHidden() ?? false },
            isPaused: { [weak self] in self?.runState() == .paused },
            opensAtLogin: { [weak self] in self?.openAtLoginChoice ?? false },
            loginItemWaitsForApproval: { LoginItem.service.status == .requiresApproval },
            target: self, loginAction: #selector(openAtLoginClicked(_:))
        )
        step.artwork.prefersReducedMotion = reducedMotion
        return step
    }()

    /// The seam, for the pictures: they may outlive the controller by a moment (a window
    /// that is torn down after it).
    private var reducedMotion: () -> Bool {
        return { [weak self] in
            self?.prefersReducedMotion() ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
    }

    /// "Having trouble?" of the Accessibility step.
    var helpButton: NSButton {
        return accessStep.helpButton
    }

    func stepView(for step: WelcomeGuideStep) -> WelcomeGuideStepView {
        switch step {
        case .welcome: return welcomeStep
        case .access: return accessStep
        case .feel: return feelStep
        case .finish: return finishStep
        }
    }

    private var shownStepView: WelcomeGuideStepView?

    // MARK: - Lifecycle

    override func loadView() {
        let size = WelcomeGuideLayout.windowSize
        let root = PreferencesForm.makeBackground()
        root.frame = NSRect(origin: .zero, size: size)
        let canvas = WelcomeGuideFlippedView(frame: root.bounds)
        canvas.autoresizingMask = [.width, .height]
        canvas.wantsLayer = true
        root.addSubview(canvas)

        let pictures = WelcomeGuideStepHost(frame: WelcomeGuideLayout.pictureFrame)
        let contents = WelcomeGuideStepHost(frame: WelcomeGuideLayout.contentFrame)
        contents.clipsToBounds = false
        pictures.clipsToBounds = false
        // The Welcome step's icon lies on the picture's edge: the text area on top.
        canvas.addSubview(pictures)
        canvas.addSubview(contents)
        pictureHost = pictures
        contentHost = contents

        let back = NSButton(title: WelcomeGuideText.localized("intro-back-button"), target: self, action: #selector(backButtonClicked(_:)))
        back.bezelStyle = .push
        back.controlSize = .large
        // ⌘[ as Back in Finder, Safari and System Settings; Esc means cancel on the Mac.
        back.keyEquivalent = "["
        back.keyEquivalentModifierMask = .command
        let primary = NSButton(title: WelcomeGuideText.localized("intro-continue-button"), target: self, action: #selector(primaryButtonClicked(_:)))
        primary.bezelStyle = .push
        primary.controlSize = .large
        primary.keyEquivalent = "\r"
        let secondary = NSButton(title: WelcomeGuideText.localized("intro-open-app-settings-button"), target: self, action: #selector(secondaryButtonClicked(_:)))
        secondary.bezelStyle = .push
        secondary.controlSize = .large
        let dots = WelcomeGuideStepDots(frame: .zero)
        for view in [back, primary, secondary, dots] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            canvas.addSubview(view)
        }
        let bar = WelcomeGuideLayout.barFrame
        NSLayoutConstraint.activate([
            back.leadingAnchor.constraint(equalTo: canvas.leadingAnchor, constant: bar.minX),
            back.centerYAnchor.constraint(equalTo: canvas.topAnchor, constant: bar.midY),
            back.widthAnchor.constraint(greaterThanOrEqualToConstant: 96),
            primary.trailingAnchor.constraint(equalTo: canvas.leadingAnchor, constant: bar.maxX),
            primary.centerYAnchor.constraint(equalTo: back.centerYAnchor),
            primary.widthAnchor.constraint(greaterThanOrEqualToConstant: 96),
            secondary.trailingAnchor.constraint(equalTo: primary.leadingAnchor, constant: -10),
            secondary.centerYAnchor.constraint(equalTo: back.centerYAnchor),
            secondary.widthAnchor.constraint(greaterThanOrEqualToConstant: 96),
            dots.centerXAnchor.constraint(equalTo: canvas.centerXAnchor),
            dots.centerYAnchor.constraint(equalTo: back.centerYAnchor),
            dots.heightAnchor.constraint(equalToConstant: 12),
        ])
        backButton = back
        primaryButton = primary
        secondaryButton = secondary
        self.dots = dots

        view = root
        accessState = WelcomeGuideAccessState(granted: isAccessGranted(), run: runState())
        if flow == nil {
            flow = WelcomeGuideFlow.automatic(guideFinished: progress.isFinished)
            steps = flow!.steps(accessReady: accessState.isReady)
            index = 0
            prepareOpenAtLogin()
        }
        show(stepAt: index, direction: 1, animated: false)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshAccessState()
        startPolling()
        NotificationCenter.default.addObserver(
            self, selector: #selector(applicationDidBecomeActive(_:)),
            name: NSApplication.didBecomeActiveNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(runStateDidChange(_:)),
            name: AppRunController.didChangeNotification, object: nil
        )
        shownStepView?.setShown(true)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        stopPolling()
        NotificationCenter.default.removeObserver(self, name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: AppRunController.didChangeNotification, object: nil)
        shownStepView?.setShown(false)
    }

    // MARK: - The run

    /// Starts a run at its first step. The whole guide skips the Accessibility step when
    /// Scrollio already runs with the access.
    func begin(_ flow: WelcomeGuideFlow) {
        self.flow = flow
        accessState = WelcomeGuideAccessState(granted: isAccessGranted(), run: runState())
        steps = flow.steps(accessReady: accessState.isReady)
        index = 0
        prepareOpenAtLogin()
        didOpenSettings = false
        didOfferHelp = false
        didReportGrant = false
        setHelpShown(false)
        if isViewLoaded {
            show(stepAt: 0, direction: -1, animated: true)
        }
    }

    /// The next step (Continue) or the one before (Back).
    func go(by offset: Int) {
        let target = index + offset
        guard steps.indices.contains(target) else { return }
        setHelpShown(false)
        stepChangedAt = uptime()
        show(stepAt: target, direction: offset > 0 ? 1 : -1, animated: true)
    }

    private var isLastStep: Bool {
        return index == steps.count - 1
    }

    private func show(stepAt newIndex: Int, direction: CGFloat, animated: Bool) {
        guard steps.indices.contains(newIndex) else { return }
        let previous = shownStepView
        let next = stepView(for: steps[newIndex])
        index = newIndex
        shownStepView = next
        transitionGeneration += 1
        let generation = transitionGeneration
        isChangingStep = false

        // What an unfinished change left behind goes now.
        for host in [pictureHost!, contentHost!] {
            for subview in host.subviews where subview !== previous?.picture && subview !== previous?.content
                && subview !== next.picture && subview !== next.content {
                subview.removeFromSuperview()
            }
        }
        if previous !== next {
            previous?.setShown(false)
        }
        next.picture.frame = pictureHost.bounds
        next.picture.alphaValue = 1
        next.content.frame = contentHost.bounds
        next.content.alphaValue = 1
        if next.picture.superview !== pictureHost { pictureHost.addSubview(next.picture) }
        if next.content.superview !== contentHost { contentHost.addSubview(next.content) }
        if next === accessStep {
            showAccessState()
        }
        // Loops start only in a window that shows; the step's content is brought up to date.
        next.setShown(true)
        updateBar()
        view.window?.recalculateKeyViewLoop()

        guard let previous, previous !== next else { return }
        // Each part of the step that goes leaves when its own animation ends (unless another
        // change began meanwhile, which clears what is left).
        let removePicture = { [weak self] in
            guard let self, generation == self.transitionGeneration else { return }
            previous.picture.removeFromSuperview()
            previous.picture.alphaValue = 1
        }
        let removeContent = { [weak self] in
            guard let self, generation == self.transitionGeneration else { return }
            previous.content.removeFromSuperview()
            previous.content.alphaValue = 1
            previous.content.setFrameOrigin(.zero)
        }
        guard animated, view.window?.isVisible == true else {
            removePicture()
            removeContent()
            return
        }
        // Until the incoming text is in, a press goes nowhere: a second click on the button
        // that now means something else, or a control that cannot be seen yet.
        isChangingStep = true
        let arrived = { [weak self] in
            guard let self, generation == self.transitionGeneration else { return }
            self.isChangingStep = false
        }
        if prefersReducedMotion() {
            next.picture.alphaValue = 0
            next.content.alphaValue = 0
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                next.picture.animator().alphaValue = 1
                next.content.animator().alphaValue = 1
                previous.picture.animator().alphaValue = 0
                previous.content.animator().alphaValue = 0
            }, completionHandler: {
                removePicture()
                removeContent()
                arrived()
            })
            return
        }
        // The picture crossfades in place; the text leaves to one side and the next comes
        // in from the other (mirrored for Back).
        next.picture.alphaValue = 0
        next.content.alphaValue = 0
        next.content.setFrameOrigin(NSPoint(x: 24 * direction, y: 0))
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            next.picture.animator().alphaValue = 1
            previous.picture.animator().alphaValue = 0
        }, completionHandler: removePicture)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 1, 1)
            previous.content.animator().alphaValue = 0
            previous.content.animator().setFrameOrigin(NSPoint(x: -24 * direction, y: 0))
        }, completionHandler: { [weak self] in
            guard let self, generation == self.transitionGeneration else { return }
            removeContent()
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
                next.content.animator().alphaValue = 1
                next.content.animator().setFrameOrigin(.zero)
            }, completionHandler: arrived)
        })
    }

    /// Back, the dots and the buttons for the step on screen.
    private func updateBar() {
        guard isViewLoaded, let step = currentStep else { return }
        backButton.isHidden = index == 0
        dots.isHidden = steps.count < 2
        dots.set(current: index, of: steps.count)
        secondaryButton.isHidden = step != .finish
        switch step {
        case .welcome, .feel:
            primaryButton.title = WelcomeGuideText.localized("intro-continue-button")
            primaryButton.isEnabled = true
        case .access:
            if accessState == .missing {
                primaryButton.title = WelcomeGuideText.localized("intro-open-settings-button")
                primaryButton.isEnabled = true
            } else {
                primaryButton.title = WelcomeGuideText.localized(isLastStep ? "intro-done-button" : "intro-continue-button")
                primaryButton.isEnabled = accessState.isReady
            }
        case .finish:
            primaryButton.title = WelcomeGuideText.localized("intro-done-button")
            primaryButton.isEnabled = true
        }
    }

    // MARK: - The permission

    /// Reads the permission and the event taps and shows them. Returns the state it found.
    @discardableResult
    func refreshAccessState() -> WelcomeGuideAccessState {
        // Reporting the grant starts the event taps, and AppRunController posts its change
        // synchronously: that post comes back here before `accessState` is updated. Answered
        // with the state as it stands, it cannot report the grant again (a start that keeps
        // failing would otherwise recurse until the stack runs out).
        guard !isRefreshingAccess else { return accessState }
        isRefreshingAccess = true
        defer { isRefreshingAccess = false }
        let granted = isAccessGranted()
        let arrived = granted && !accessState.isGranted
        // The recovery timer's next look, now: the event taps start before the state is read.
        // Also once per run when the access was there before the guide but the taps have not
        // started yet (allowed while the guide was closed): no waiting for the timer.
        if arrived || (granted && !didReportGrant && runState() == .stopped) {
            didReportGrant = true
            accessWasGranted()
        }
        let found = WelcomeGuideAccessState(granted: granted, run: runState())
        guard found != accessState else { return found }
        accessState = found
        if found.isGranted {
            setHelpShown(false)
        }
        if isViewLoaded {
            showAccessState()
            if steps.contains(.feel) {
                feelStep.refreshTryArea()
            }
            updateBar()
        }
        if arrived {
            announce(WelcomeGuideText.localized("intro-status-granted"))
            bringToFront(view.window)
        }
        return found
    }

    private func startPolling() {
        stopPolling()
        accessibilityPermissionsCheckerTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            self?.accessibilityPermissionsChecker(timer)
        }
    }

    private func stopPolling() {
        accessibilityPermissionsCheckerTimer?.invalidate()
        accessibilityPermissionsCheckerTimer = nil
    }

    /// One tick of the poll: the status follows the permission and the event taps, both
    /// ways, and the feel step's page whether it is smoothed.
    func accessibilityPermissionsChecker(_ timer: Timer?) {
        refreshAccessState()
        if currentStep == .feel {
            feelStep.refreshTryArea()
        }
    }

    @objc func runStateDidChange(_ notification: Notification?) {
        refreshAccessState()
    }

    /// Back in Scrollio. If the user went to System Settings from here and the access is
    /// still missing, the help opens by itself, once.
    @objc func applicationDidBecomeActive(_ notification: Notification?) {
        guard refreshAccessState() == .missing, didOpenSettings, !didOfferHelp, currentStep == .access else { return }
        didOfferHelp = true
        setHelpShown(true)
    }

    // MARK: - Help

    /// Shows or hides the help under "Having trouble?".
    func setHelpShown(_ shown: Bool) {
        guard shown != isHelpShown else { return }
        isHelpShown = shown
        guard isViewLoaded else { return }
        accessStep.helpButton.setAccessibilityExpanded(shown)
        if shown {
            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = !prefersReducedMotion()
            popover.delegate = self
            popover.contentViewController = WelcomeGuideHelpViewController(showInFinder: { [weak self] in
                self?.revealApplication()
            })
            helpPopover = popover
            presentHelp(popover, accessStep.helpButton)
        } else {
            let popover = helpPopover
            helpPopover = nil
            popover?.close()
        }
    }

    /// The help shown, or nil.
    var helpContent: WelcomeGuideHelpViewController? {
        return helpPopover?.contentViewController as? WelcomeGuideHelpViewController
    }

    func popoverDidClose(_ notification: Notification) {
        guard (notification.object as? NSPopover) === helpPopover else { return }
        helpPopover = nil
        isHelpShown = false
        accessStep.helpButton.setAccessibilityExpanded(false)
    }

    // MARK: - Actions

    /// A key held down repeats: not a press of its own.
    ///
    /// A click is never judged by its click count: macOS counts clicks by the user's
    /// double-click speed, and with a slow one every deliberate click on Continue, step after
    /// step in the same place, arrives as a second, third, fourth click.
    static func isRepeatedPress(_ event: NSEvent?) -> Bool {
        guard let event, event.type == .keyDown else { return false }
        return event.isARepeat
    }

    /// Whether a press of the bar counts: not while the steps change or right after (the
    /// second click of a double-click), not a held key.
    private var takesPress: Bool {
        return !isChangingStep
            && uptime() - stepChangedAt >= Self.pressSettleTime
            && !Self.isRepeatedPress(currentEvent())
    }

    @objc func primaryButtonClicked(_ sender: Any?) {
        guard takesPress, let step = currentStep else { return }
        switch step {
        case .access where accessState == .missing:
            didOpenSettings = true
            showAccessState()
            // The request puts Scrollio into the Accessibility list; the pane shows the list.
            requestAccess()
            openAccessibilitySettings()
        case .access:
            guard accessState.isReady else { return }
            if isLastStep {
                finish()
            } else {
                go(by: 1)
            }
        case .finish:
            finish()
        case .welcome, .feel:
            go(by: 1)
        }
    }

    /// "Open Settings": the Preferences on Scrolling, then the guide closes (the app keeps
    /// its Dock icon). The Preferences come first: "Open at login" may open Login Items for an
    /// approval, which must stay in front.
    @objc func secondaryButtonClicked(_ sender: Any?) {
        guard takesPress else { return }
        progress.markFinished()
        openAppSettings()
        applyOpenAtLogin()
        view.window?.close()
    }

    @objc func openAtLoginClicked(_ sender: NSSwitch) {
        openAtLoginChoice = sender.state == .on
    }

    /// A new user's switch starts on; run by hand it shows what the system says.
    private func prepareOpenAtLogin() {
        openAtLoginAtStart = LoginItem.isEnabled
        openAtLoginChoice = progress.isPending ? true : openAtLoginAtStart
        if isViewLoaded && steps.contains(.finish) {
            finishStep.refresh()
        }
    }

    /// Leaving the last step (Done, Open Settings, or the window closed there): the switch
    /// is applied as it shows, as General applies its own (`chooseOpenAtLogin`: on registers,
    /// and opens Login Items when macOS wants an approval; off removes the registration).
    /// Only a choice that differs from what the system said at the start, and only once;
    /// when registering fails the guide still finishes, and General shows what the system says.
    private func applyOpenAtLogin() {
        guard currentStep == .finish, openAtLoginChoice != openAtLoginAtStart else { return }
        PreferencesGeneralViewController.chooseOpenAtLogin(openAtLoginChoice)
        openAtLoginAtStart = openAtLoginChoice
    }

    @objc func backButtonClicked(_ sender: Any?) {
        guard takesPress else { return }
        go(by: -1)
    }

    /// Esc: the guide has nothing to cancel, and it is not closed by a key.
    override func cancelOperation(_ sender: Any?) {}

    @objc func helpButtonClicked(_ sender: Any?) {
        didOfferHelp = true
        setHelpShown(!isHelpShown)
    }

    private func finish() {
        progress.markFinished()
        applyOpenAtLogin()
        view.window?.close()
    }

    /// The window closes (its close button, Done, Open Settings): with the access allowed
    /// the guide counts as finished, so it does not come back by itself. Closed on the last
    /// step, its "Open at login" switch counts as the user left it.
    func windowWillClose() {
        applyOpenAtLogin()
        if isAccessGranted() {
            progress.markFinished()
        }
        setHelpShown(false)
        stopPolling()
        shownStepView?.setShown(false)
    }

    // MARK: - The live world

    static func liveRunState() -> WelcomeGuideRunState {
        let controller = AppRunController.shared
        if controller.coresActive { return .running }
        if controller.isPaused { return .paused }
        if controller.isRetryingStart { return .retrying }
        return .stopped
    }

    /// Scrollio's own window as the scroll engine sees it: looked up on the per-app list by
    /// the bundle's path, then by the program's.
    static func liveTryAreaState() -> WelcomeGuideTryArea {
        let scrollio = AppSmoothing.App(
            name: Bundle.main.bundleURL.deletingPathExtension().lastPathComponent,
            bundlePath: Bundle.main.bundlePath, executablePath: Bundle.main.executablePath
        )
        let list = Options.shared.application
        return WelcomeGuideTryArea.state(
            running: AppRunController.shared.coresActive,
            rule: AppSmoothing.rule(of: AppSmoothing.entry(for: scrollio, in: list.applications)),
            scrollingSmooth: Options.shared.scroll.smooth,
            limitedToListedApps: list.allowlist
        )
    }

    /// System Settings › Privacy & Security › Accessibility.
    static let accessibilityPaneURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    /// Also the "Open Settings…" of General › Permissions.
    static func openAccessibilityPane() {
        NSWorkspace.shared.open(accessibilityPaneURL)
    }
}
