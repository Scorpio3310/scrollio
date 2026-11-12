//
//  IntroductionWindowTests.swift
//  MosTests
//
//  The Welcome Guide (IntroductionViewController and the WelcomeGuide* steps): who sees
//  which steps, the one stored value that says it was finished, the Accessibility step
//  following the real permission and the start of the event taps, the feel step storing
//  only the glide time, the bar (Back, dots, the main button) and a window that never
//  changes its size. The permission, the app's run state, System Settings, Finder, the
//  popover and VoiceOver are replaced; nothing is shown on screen (windows are created but
//  never ordered in, except those that take real clicks: AppKit delivers mouse
//  events only to a window that is ordered in, so `GuideEventWindow` is, far off every
//  display, transparent and closed to the real mouse).
//
//  WelcomeGuideRenderTests at the end draws every step off screen, light and dark, when
//  `TEST_RUNNER_SCROLLIO_SHOTS_DIR` is set.
//

import XCTest
@testable import Scrollio_Debug

private func allSubviews(of view: NSView) -> [NSView] {
    return view.subviews.flatMap { [$0] + allSubviews(of: $0) }
}

/// Hidden itself or inside a hidden view.
private func isShown(_ view: NSView) -> Bool {
    return !view.isHiddenOrHasHiddenAncestor
}

/// What the guide is told about the outside world, and what it did to it.
private final class GuideWorld {
    var accessGranted = false
    var run: WelcomeGuideRunState = .stopped
    /// What the event taps do when the guide reports the grant (the recovery's start).
    var runAfterGrant: WelcomeGuideRunState?
    var menuBarIconHidden = false
    var reduceMotion = false
    var mouse: MouseArtworkModel = .generic
    var tryArea: WelcomeGuideTryArea = .smoothed
    let scroll = OPTIONS_SCROLL_DEFAULT()
    /// The event the bar is pressed with (`IntroductionViewController.currentEvent`).
    var currentEvent: NSEvent?
    /// The bar's clock (`IntroductionViewController.uptime`): every reading is a second later,
    /// so presses are never "right after a step change", unless a test holds the clock.
    var uptime: TimeInterval = 1000
    var isClockHeld = false
    /// What the guide did to the outside world, in order.
    var log: [String] = []

    var requests = 0
    var settingsOpened = 0
    var reveals = 0
    var grantsReported = 0
    var appSettingsOpened = 0
    var broughtToFront = 0
    var announcements: [String] = []
    var presentedHelp: [NSPopover] = []

    /// The guide's stored value, in a store of this world's own (a temporary folder that
    /// goes with the world).
    private let store = TestDefaults()
    var defaults: UserDefaults { return store.defaults }
    lazy var progress = WelcomeGuideProgress(defaults: defaults)

    func makeController(flow: WelcomeGuideFlow? = nil, finished: Bool = false) -> IntroductionViewController {
        defaults.set(finished ? WelcomeGuideProgress.currentVersion : WelcomeGuideProgress.notFinished, forKey: WelcomeGuideProgress.key)
        let controller = IntroductionViewController()
        controller.isAccessGranted = { self.accessGranted }
        controller.runState = { self.run }
        controller.requestAccess = { self.requests += 1 }
        controller.openAccessibilitySettings = { self.settingsOpened += 1 }
        controller.revealApplication = { self.reveals += 1 }
        controller.accessWasGranted = {
            self.grantsReported += 1
            if let next = self.runAfterGrant { self.run = next }
        }
        controller.isMenuBarIconHidden = { self.menuBarIconHidden }
        controller.openAppSettings = {
            self.appSettingsOpened += 1
            self.log.append("Preferences")
        }
        controller.prefersReducedMotion = { self.reduceMotion }
        controller.progress = progress
        controller.mouseSource = { self.mouse }
        controller.scrollOptions = { self.scroll }
        controller.tryAreaState = { self.tryArea }
        controller.bringToFront = { _ in self.broughtToFront += 1 }
        controller.announce = { self.announcements.append($0) }
        controller.presentHelp = { popover, _ in self.presentedHelp.append(popover) }
        controller.currentEvent = { self.currentEvent }
        controller.uptime = {
            if !self.isClockHeld { self.uptime += 1 }
            return self.uptime
        }
        if let flow {
            controller.begin(flow)
        }
        _ = controller.view
        return controller
    }

    func tearDown() {
        store.remove()
    }
}

/// A login item whose state the test sets (General's tests use the same seam,
/// `LoginItem.service`).
private final class FakeLoginItem: LoginItemService {
    var status: LoginItemStatus
    /// What registering leaves; nil: nothing changes (it failed, or waits for approval).
    var afterRegister: LoginItemStatus? = .enabled
    /// Called when System Settings › Login Items opens.
    var onOpenSystemSettings: (() -> Void)?
    private(set) var registerCalls = 0
    private(set) var unregisterCalls = 0
    private(set) var openSettingsCalls = 0

    init(status: LoginItemStatus) {
        self.status = status
    }

    func register() throws {
        registerCalls += 1
        if let afterRegister { status = afterRegister }
    }

    func unregister() throws {
        unregisterCalls += 1
        status = .notRegistered
    }

    func openSystemSettings() {
        openSettingsCalls += 1
        onOpenSystemSettings?()
    }

    var calls: Int {
        return registerCalls + unregisterCalls + openSettingsCalls
    }
}

final class IntroductionWindowTests: XCTestCase {

    private var world: GuideWorld!
    private var savedAutoLaunch = false
    private var savedScroll: OPTIONS_SCROLL_DEFAULT!

    override func setUp() {
        super.setUp()
        world = GuideWorld()
        savedAutoLaunch = Options.shared.general.autoLaunch
        savedScroll = Options.shared.scroll
    }

    override func tearDown() {
        world.tearDown()
        world = nil
        LoginItem.service = InertLoginItemService()
        Options.shared.general.autoLaunch = savedAutoLaunch
        LoginItem.service = LoginItem.defaultService
        Options.shared.scroll = savedScroll
        super.tearDown()
    }

    @discardableResult
    private func install(_ status: LoginItemStatus) -> FakeLoginItem {
        let fake = FakeLoginItem(status: status)
        LoginItem.service = fake
        return fake
    }

    /// A window that holds the controller's view and is never shown.
    private func makeWindow(for controller: IntroductionViewController) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: WelcomeGuideLayout.windowSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        addTeardownBlock { window.close() }
        return window
    }

    private func click(_ button: NSButton, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(button.isEnabled, "\(button.title) is disabled", file: file, line: line)
        XCTAssertTrue(isShown(button), "\(button.title) is hidden", file: file, line: line)
        XCTAssertTrue(button.sendAction(button.action, to: button.target), button.title, file: file, line: line)
    }

    private func shownTexts(in view: NSView) -> [String] {
        let views = allSubviews(of: view).filter(isShown)
        return views.compactMap { ($0 as? NSTextField)?.stringValue }.filter { !$0.isEmpty }
            + views.compactMap { ($0 as? NSButton)?.title }.filter { !$0.isEmpty }
    }

    // MARK: - Who sees which steps

    func testTheWholeGuideHasFourStepsAndSkipsAccessWhenScrollioRuns() {
        XCTAssertEqual(WelcomeGuideFlow.full.steps(accessReady: false), [.welcome, .access, .feel, .finish])
        XCTAssertEqual(WelcomeGuideFlow.full.steps(accessReady: true), [.welcome, .feel, .finish])
        XCTAssertEqual(WelcomeGuideFlow.accessOnly.steps(accessReady: false), [.access])
        XCTAssertEqual(WelcomeGuideFlow.accessOnly.steps(accessReady: true), [.access])
        XCTAssertEqual(WelcomeGuideFlow.automatic(guideFinished: false), .full)
        XCTAssertEqual(WelcomeGuideFlow.automatic(guideFinished: true), .accessOnly)
    }

    func testANewInstallationWaitsForTheGuideAndExistingSettingsCountAsFinished() {
        let defaults = world.defaults
        let progress = WelcomeGuideProgress(defaults: defaults)
        defaults.removeObject(forKey: WelcomeGuideProgress.key)

        // Settings from before the guide (an update): finished, silently.
        progress.settleAtLaunch(isNewInstallation: false)
        XCTAssertEqual(defaults.object(forKey: "welcomeGuideCompletedVersion") as? Int, 1)
        XCTAssertFalse(progress.isPending)

        // A new installation: waits, also after a quit half-way (the next launch settles nothing).
        defaults.removeObject(forKey: WelcomeGuideProgress.key)
        progress.settleAtLaunch(isNewInstallation: true)
        XCTAssertEqual(defaults.object(forKey: "welcomeGuideCompletedVersion") as? Int, 0)
        XCTAssertTrue(progress.isPending)
        progress.settleAtLaunch(isNewInstallation: false)
        XCTAssertTrue(progress.isPending, "the second launch of a new user still shows the guide")

        progress.markFinished()
        XCTAssertEqual(defaults.object(forKey: "welcomeGuideCompletedVersion") as? Int, 1)
        XCTAssertTrue(progress.isFinished)
        progress.settleAtLaunch(isNewInstallation: true)
        XCTAssertTrue(progress.isFinished, "a stored value stays")

        // Without a store (the tests' default) nothing is read or written.
        let none = WelcomeGuideProgress(defaults: nil)
        none.settleAtLaunch(isNewInstallation: true)
        none.markFinished()
        XCTAssertFalse(none.isPending)
    }

    func testTheGuideOpensByItselfForANewUserOrWithoutAccessOnly() {
        let defaults = world.defaults
        let progress = WelcomeGuideProgress(defaults: defaults)
        defaults.set(0, forKey: WelcomeGuideProgress.key)
        XCTAssertTrue(IntroductionWindowController.opensAtLaunch(hasAccess: true, progress: progress))
        XCTAssertEqual(IntroductionWindowController.flow(for: .automatic, progress: progress), .full)
        defaults.set(1, forKey: WelcomeGuideProgress.key)
        XCTAssertFalse(IntroductionWindowController.opensAtLaunch(hasAccess: true, progress: progress), "the debug build may open Settings")
        XCTAssertTrue(IntroductionWindowController.opensAtLaunch(hasAccess: false, progress: progress))
        XCTAssertEqual(IntroductionWindowController.flow(for: .automatic, progress: progress), .accessOnly)
        XCTAssertEqual(IntroductionWindowController.flow(for: .byHand, progress: progress), .full)
    }

    func testTheAccessStateFollowsThePermissionAndTheEventTaps() {
        XCTAssertEqual(WelcomeGuideAccessState(granted: false, run: .running), .missing)
        XCTAssertEqual(WelcomeGuideAccessState(granted: true, run: .running), .running)
        XCTAssertEqual(WelcomeGuideAccessState(granted: true, run: .paused), .paused)
        XCTAssertEqual(WelcomeGuideAccessState(granted: true, run: .retrying), .couldNotStart)
        XCTAssertEqual(WelcomeGuideAccessState(granted: true, run: .stopped), .starting)
        XCTAssertEqual(WelcomeGuideAccessState.allReady, [.running, .paused])
    }

    func testTheTryAreaIsSmoothedAsTheEngineDecidesForScrollio() {
        func state(_ running: Bool, _ rule: AppSmoothing.Rule, smooth: Bool = true, limited: Bool = false) -> WelcomeGuideTryArea {
            return WelcomeGuideTryArea.state(running: running, rule: rule, scrollingSmooth: smooth, limitedToListedApps: limited)
        }
        XCTAssertEqual(state(true, .notListed), .smoothed)
        XCTAssertEqual(state(false, .notListed), .notRunning)
        XCTAssertEqual(state(true, .notListed, limited: true), .notInAppList)
        XCTAssertEqual(state(true, .usesScrollingSettings, limited: true), .smoothed)
        XCTAssertEqual(state(true, .notListed, smooth: false), .smoothingOff)
        XCTAssertEqual(state(true, .own(smooth: false)), .smoothingOff)
        XCTAssertEqual(state(true, .own(smooth: true), smooth: false), .smoothed)
    }

    // MARK: - The bar

    func testANewUserStartsOnWelcomeWithContinue() {
        let controller = world.makeController()
        XCTAssertEqual(controller.flow, .full)
        XCTAssertEqual(controller.steps, [.welcome, .access, .feel, .finish])
        XCTAssertEqual(controller.currentStep, .welcome)
        XCTAssertEqual(controller.welcomeStep.titleLabel.stringValue, "Welcome to Scrollio")
        XCTAssertEqual(controller.welcomeStep.textLabel.stringValue, "Smooth scrolling, button actions and gestures for your mouse.")
        XCTAssertEqual(controller.welcomeStep.features.map(\.titleLabel.stringValue), ["Smooth scrolling", "Button actions", "Gestures"])
        XCTAssertNotNil(controller.welcomeStep.iconView.image)

        let primary = controller.primaryButton!
        XCTAssertEqual(primary.title, "Continue")
        XCTAssertTrue(primary.isEnabled)
        XCTAssertEqual(primary.keyEquivalent, "\r", "Return presses it, and AppKit draws it in the accent colour")
        XCTAssertEqual(primary.bezelStyle, .push)
        XCTAssertFalse(isShown(controller.backButton), "nothing to go back to")
        XCTAssertFalse(isShown(controller.secondaryButton))
        XCTAssertEqual(controller.dots.accessibilityLabel(), "Step 1 of 4")
        XCTAssertEqual(controller.backButton.keyEquivalent, "[", "⌘[ goes back, as in Finder and System Settings")
        XCTAssertEqual(controller.backButton.keyEquivalentModifierMask, .command)
        XCTAssertEqual(controller.backButton.title, "Back")

        // Nothing was asked for by merely opening the window.
        XCTAssertEqual(world.requests, 0)
        XCTAssertEqual(world.settingsOpened, 0)
        XCTAssertEqual(world.grantsReported, 0)
    }

    func testContinueAndBackWalkTheStepsAndTheDotsSayWhere() {
        world.runAfterGrant = .running
        let controller = world.makeController()
        click(controller.primaryButton)
        XCTAssertEqual(controller.currentStep, .access)
        XCTAssertEqual(controller.dots.accessibilityLabel(), "Step 2 of 4")
        XCTAssertTrue(isShown(controller.backButton))
        XCTAssertEqual(controller.primaryButton.title, "Open Accessibility Settings")

        click(controller.backButton)
        XCTAssertEqual(controller.currentStep, .welcome)
        click(controller.primaryButton)

        world.accessGranted = true
        controller.accessibilityPermissionsChecker(nil)
        XCTAssertEqual(controller.primaryButton.title, "Continue")
        click(controller.primaryButton)
        XCTAssertEqual(controller.currentStep, .feel)
        XCTAssertEqual(controller.dots.accessibilityLabel(), "Step 3 of 4")
        click(controller.primaryButton)
        XCTAssertEqual(controller.currentStep, .finish)
        XCTAssertEqual(controller.dots.accessibilityLabel(), "Step 4 of 4")
        XCTAssertEqual(controller.primaryButton.title, "Done")
        XCTAssertEqual(controller.secondaryButton.title, "Open Settings")
        XCTAssertTrue(isShown(controller.secondaryButton))

        // Only the step on screen is in the window.
        XCTAssertEqual(controller.pictureHost.subviews.count, 1)
        XCTAssertEqual(controller.contentHost.subviews.count, 1)
        XCTAssertTrue(controller.contentHost.subviews.first === controller.finishStep.content)
    }

    func testWithScrollioRunningTheGuideSkipsTheAccessStep() {
        world.accessGranted = true
        world.run = .running
        let controller = world.makeController(flow: .full, finished: true)
        XCTAssertEqual(controller.steps, [.welcome, .feel, .finish])
        XCTAssertEqual(controller.dots.accessibilityLabel(), "Step 1 of 3")

        // Paused on purpose: nothing to wait for either.
        world.run = .paused
        controller.begin(.full)
        XCTAssertEqual(controller.steps, [.welcome, .feel, .finish])

        // Access, but the event taps could not start: the step says so.
        world.run = .retrying
        controller.begin(.full)
        XCTAssertEqual(controller.steps, [.welcome, .access, .feel, .finish])
    }

    // MARK: - Allow Accessibility (today's behaviour, new look)

    private func makeAccessController(flow: WelcomeGuideFlow = .full) -> IntroductionViewController {
        let controller = world.makeController(flow: flow)
        if controller.currentStep != .access {
            click(controller.primaryButton)
        }
        XCTAssertEqual(controller.currentStep, .access)
        return controller
    }

    func testWithoutAccessItAsksForItAndExplainsWhy() {
        let controller = makeAccessController()
        let step = controller.accessStep
        XCTAssertEqual(controller.accessState, .missing)
        XCTAssertEqual(step.titleLabel.stringValue, "Allow Accessibility access")
        XCTAssertEqual(step.textLabel.stringValue, "Scrollio needs this permission to smooth scrolling and run your buttons and gestures. Nothing leaves your Mac.")
        // Nothing is under way yet: a to-do, no spinner.
        XCTAssertEqual(step.statusBox.titleLabel.stringValue, "Not allowed yet")
        XCTAssertEqual(step.statusBox.detailLabel.stringValue, "Click Open Accessibility Settings, then turn on Scrollio in the list.")
        XCTAssertTrue(step.statusBox.spinner.isHidden)
        XCTAssertFalse(step.statusBox.iconView.isHidden)
        XCTAssertEqual(controller.primaryButton.title, "Open Accessibility Settings")
        XCTAssertTrue(controller.primaryButton.isEnabled)
        XCTAssertTrue(isShown(controller.helpButton))
        XCTAssertEqual(controller.helpButton.title, "Having trouble?")
        XCTAssertFalse(shownTexts(in: controller.view).contains("Skip"), "no way around the permission")
    }

    func testOpenAccessibilitySettingsAsksMacOSAndOpensThePane() {
        let controller = makeAccessController()
        click(controller.primaryButton)
        XCTAssertEqual(world.requests, 1, "the request puts Scrollio into the Accessibility list")
        XCTAssertEqual(world.settingsOpened, 1)
        // Now it waits, with the spinner.
        let status = controller.accessStep.statusBox!
        XCTAssertEqual(status.titleLabel.stringValue, "Waiting for Scrollio to be turned on…")
        XCTAssertTrue(status.detailLabel.stringValue.contains("Open System Settings"))
        XCTAssertFalse(status.spinner.isHidden)
        XCTAssertEqual(controller.accessState, .missing)
        XCTAssertEqual(controller.currentStep, .access, "it waits on the step")
        XCTAssertEqual(controller.primaryButton.title, "Open Accessibility Settings")
    }

    func testThePaneIsTheAccessibilityListOfSystemSettings() {
        XCTAssertEqual(
            IntroductionViewController.accessibilityPaneURL.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
    }

    func testNoPollRunsBeforeTheWindowAppears() {
        let controller = world.makeController()
        XCTAssertNil(controller.accessibilityPermissionsCheckerTimer)
    }

    func testTheGrantStartsTheTapsIsAnnouncedAndBringsScrollioBack() {
        world.runAfterGrant = .running
        let controller = makeAccessController()

        // A tick without a change changes nothing.
        controller.accessibilityPermissionsChecker(nil)
        XCTAssertEqual(world.grantsReported, 0)
        XCTAssertTrue(world.announcements.isEmpty)

        world.accessGranted = true
        controller.accessibilityPermissionsChecker(nil)
        XCTAssertEqual(world.grantsReported, 1, "the app starts its event taps now")
        XCTAssertEqual(controller.accessState, .running, "read after the start")
        XCTAssertEqual(world.announcements, ["Accessibility access is allowed"])
        XCTAssertEqual(world.broughtToFront, 1)
        let status = controller.accessStep.statusBox!
        XCTAssertEqual(status.titleLabel.stringValue, "Allowed")
        XCTAssertEqual(status.detailLabel.stringValue, "Scrollio is running.", "the last step says where Scrollio lives")
        XCTAssertEqual(status.accessibilityLabel(), "Allowed. Scrollio is running.")
        XCTAssertEqual(controller.primaryButton.title, "Continue")
        XCTAssertTrue(controller.primaryButton.isEnabled)
        XCTAssertFalse(isShown(controller.helpButton))
        XCTAssertTrue(controller.accessStep.artwork.isAllowed)

        controller.accessibilityPermissionsChecker(nil)
        controller.accessibilityPermissionsChecker(nil)
        XCTAssertEqual(world.grantsReported, 1)
        XCTAssertEqual(world.announcements.count, 1)
    }

    func testContinueWaitsForTheEventTapsAndSaysWhenTheyCannotStart() {
        world.runAfterGrant = .retrying
        let controller = makeAccessController()
        world.accessGranted = true
        controller.accessibilityPermissionsChecker(nil)
        XCTAssertEqual(controller.accessState, .couldNotStart)
        // Not "Allowed" alone: next to the warning sign and a Continue that is off it read as
        // if everything were in order.
        XCTAssertEqual(controller.accessStep.statusBox.titleLabel.stringValue, "Allowed, but Scrollio hasn't started")
        XCTAssertEqual(
            controller.accessStep.statusBox.detailLabel.stringValue,
            "Scrollio couldn't start yet and keeps trying. If nothing changes, quit Scrollio and open it again."
        )
        XCTAssertEqual(
            controller.accessStep.statusBox.accessibilityLabel(),
            "Allowed, but Scrollio hasn't started. Scrollio couldn't start yet and keeps trying. If nothing changes, quit Scrollio and open it again."
        )
        for state in [WelcomeGuideAccessState.starting, .running, .paused] {
            XCTAssertEqual(WelcomeGuideAccessStep.statusTexts(for: state, context: .init()).title, "Allowed", "\(state)")
        }
        XCTAssertEqual(controller.primaryButton.title, "Continue")
        XCTAssertFalse(controller.primaryButton.isEnabled)
        XCTAssertTrue(controller.primaryButton.sendAction(controller.primaryButton.action, to: controller.primaryButton.target))
        XCTAssertEqual(controller.currentStep, .access, "a click while it is disabled goes nowhere")

        // The retry state comes and goes with AppRunController's notification.
        world.run = .running
        controller.runStateDidChange(nil)
        XCTAssertEqual(controller.accessState, .running)
        XCTAssertTrue(controller.primaryButton.isEnabled)

        // Starting, not yet running: waits too.
        world.run = .stopped
        controller.runStateDidChange(nil)
        XCTAssertEqual(controller.accessState, .starting)
        XCTAssertEqual(controller.accessStep.statusBox.detailLabel.stringValue, "Starting Scrollio…")
        XCTAssertFalse(controller.primaryButton.isEnabled)
    }

    /// The Accessibility step alone says where Scrollio lives (in the whole guide the last step does).
    func testWithAHiddenMenuBarIconItSaysHowToReachTheSettings() {
        world.menuBarIconHidden = true
        world.runAfterGrant = .running
        let controller = makeAccessController(flow: .accessOnly)
        world.accessGranted = true
        controller.accessibilityPermissionsChecker(nil)
        XCTAssertEqual(
            controller.accessStep.statusBox.detailLabel.stringValue,
            "Scrollio is running, but its menu bar icon is hidden. To reach Settings, open Scrollio again."
        )
        world.menuBarIconHidden = false
        world.run = .stopped
        controller.accessibilityPermissionsChecker(nil)
        world.run = .running
        controller.accessibilityPermissionsChecker(nil)
        XCTAssertEqual(controller.accessStep.statusBox.detailLabel.stringValue, "Scrollio is running. Open Settings from its menu bar icon.")
    }

    func testARevokedAccessBringsTheRequestBack() {
        world.runAfterGrant = .running
        let controller = makeAccessController()
        world.accessGranted = true
        controller.accessibilityPermissionsChecker(nil)
        world.accessGranted = false
        world.run = .stopped
        controller.accessibilityPermissionsChecker(nil)
        XCTAssertEqual(controller.accessState, .missing)
        XCTAssertEqual(controller.primaryButton.title, "Open Accessibility Settings")
        XCTAssertTrue(isShown(controller.helpButton))
        XCTAssertFalse(controller.accessStep.artwork.isAllowed)

        world.accessGranted = true
        controller.accessibilityPermissionsChecker(nil)
        XCTAssertEqual(world.grantsReported, 2)
    }

    /// Reporting the grant starts the event taps, and AppRunController posts its change
    /// synchronously: that post comes back into the guide before it has taken the new state.
    /// When the start fails (and AppRunController arms its next try) the guide used to report
    /// the grant again from inside the report, and again: a recursion that only ends when a
    /// start succeeds, or with the stack.
    func testAGrantWhoseFirstStartFailsIsReportedOnce() {
        let controller = makeAccessController()
        var reports = 0
        controller.accessWasGranted = { [unowned controller] in
            reports += 1
            guard reports <= 5 else { return XCTFail("the grant is reported from inside its own report") }
            self.world.run = .retrying
            controller.runStateDidChange(nil)
        }
        world.accessGranted = true
        controller.accessibilityPermissionsChecker(nil)
        XCTAssertEqual(reports, 1)
        XCTAssertEqual(controller.accessState, .couldNotStart)
        XCTAssertEqual(world.announcements, ["Accessibility access is allowed"])
        controller.accessibilityPermissionsChecker(nil)
        XCTAssertEqual(reports, 1, "a later tick reports nothing")
    }

    func testReportingAGrantStartsNothingWhenTheAppIsNotWaitingForOne() throws {
        // What the window calls on a grant: the app delegate fires its recovery timer early.
        // Under test there is none (startup side effects are off), so nothing starts.
        let delegate = try XCTUnwrap(NSApp.delegate as? AppDelegate)
        let scrollWasActive = ScrollCore.shared.isActive
        let buttonsWereActive = ButtonCore.shared.isActive
        delegate.accessibilityPermissionWasGranted()
        XCTAssertEqual(ScrollCore.shared.isActive, scrollWasActive)
        XCTAssertEqual(ButtonCore.shared.isActive, buttonsWereActive)
    }

    func testTheAccessStepAloneEndsWithDone() {
        world.runAfterGrant = .running
        let controller = world.makeController(flow: .accessOnly, finished: true)
        let window = makeWindow(for: controller)
        XCTAssertEqual(controller.steps, [.access])
        XCTAssertFalse(isShown(controller.backButton))
        XCTAssertFalse(isShown(controller.dots), "one step: no dots")
        XCTAssertEqual(controller.primaryButton.title, "Open Accessibility Settings")

        world.accessGranted = true
        controller.accessibilityPermissionsChecker(nil)
        XCTAssertEqual(controller.primaryButton.title, "Done")
        let closed = expectation(forNotification: NSWindow.willCloseNotification, object: window)
        click(controller.primaryButton)
        wait(for: [closed], timeout: 1)
        XCTAssertTrue(world.progress.isFinished)
    }

    // MARK: - Help

    func testHavingTroubleShowsThePlainHelp() throws {
        let controller = makeAccessController()
        XCTAssertFalse(controller.isHelpShown)
        click(controller.helpButton)
        XCTAssertTrue(controller.isHelpShown)
        XCTAssertEqual(world.presentedHelp.count, 1)
        XCTAssertEqual(controller.helpButton.isAccessibilityExpanded(), true)
        let help = try XCTUnwrap(controller.helpContent)
        _ = help.view
        XCTAssertEqual(help.headingLabel.stringValue, "Scrollio is in the list but does not work?")
        for word in ["update", "select Scrollio", "minus", "add it again", "Finder"] {
            XCTAssertTrue(help.textLabel.stringValue.contains(word), "the help does not mention \"\(word)\"")
        }
        XCTAssertEqual(help.finderButton.title, "Show Scrollio in Finder")
        click(help.finderButton)
        XCTAssertEqual(world.reveals, 1)

        click(controller.helpButton)
        XCTAssertFalse(controller.isHelpShown)
        XCTAssertNil(controller.helpContent)
    }

    func testTheHelpOpensByItselfOnceWhenTheUserComesBackWithoutAccess() {
        let controller = makeAccessController()

        // Scrollio becomes active when its window opens: that is not "coming back".
        controller.applicationDidBecomeActive(nil)
        XCTAssertFalse(controller.isHelpShown)

        click(controller.primaryButton)
        controller.applicationDidBecomeActive(nil)
        XCTAssertTrue(controller.isHelpShown)

        // Closed by the user: it does not come back on its own.
        click(controller.helpButton)
        controller.applicationDidBecomeActive(nil)
        XCTAssertFalse(controller.isHelpShown)
    }

    func testTheHelpGoesAwayWithTheGrant() {
        world.runAfterGrant = .running
        let controller = makeAccessController()
        click(controller.helpButton)
        world.accessGranted = true
        controller.applicationDidBecomeActive(nil)
        XCTAssertEqual(controller.accessState, .running)
        XCTAssertFalse(controller.isHelpShown)
        XCTAssertFalse(isShown(controller.helpButton))
    }

    // MARK: - Choose your feel

    private func makeFeelController() -> IntroductionViewController {
        world.accessGranted = true
        world.run = .running
        let controller = world.makeController(flow: .full)
        click(controller.primaryButton)
        XCTAssertEqual(controller.currentStep, .feel)
        return controller
    }

    func testTheFeelStepShowsTheFivePresetsWithTheStoredOneSelected() {
        let controller = makeFeelController()
        let step = controller.feelStep
        XCTAssertEqual(step.titleLabel.stringValue, "Choose how scrolling feels")
        XCTAssertEqual(
            step.textLabel.stringValue,
            "Scroll the page above with your mouse wheel, then pick what feels right. You can change it later in Settings."
        )
        XCTAssertEqual(step.feelButtons.map(\.title), ["Direct", "Quick", "Smooth", "Glide", "Float"])
        XCTAssertEqual(step.feelButtons.map(\.caption), ["Stops at once", "Soft stop", "Like a trackpad", "Longer glide", "Longest glide"])
        XCTAssertEqual(step.feelButtons.filter { $0.state == .on }.map(\.feel), [.smooth], "the default is preselected")
        XCTAssertFalse(isShown(step.hintLabel), "the line under the cards is for a glide time of one's own")
        for button in step.feelButtons {
            XCTAssertEqual(button.accessibilityRole(), .radioButton)
            XCTAssertEqual(button.accessibilityLabel(), button.feel.localizedName)
            XCTAssertEqual(button.accessibilityHelp(), button.caption, "VoiceOver reads the word under the name")
            XCTAssertEqual(button.toolTip, button.feel.localizedHint)
        }
        XCTAssertTrue(controller.primaryButton.isEnabled, "Continue keeps the preselected feel")

        // A custom glide time (set under Advanced): nothing selected, Continue keeps it.
        world.scroll.duration = 3.4
        controller.begin(.full)
        click(controller.primaryButton)
        XCTAssertTrue(step.feelButtons.allSatisfy { $0.state == .off })
        XCTAssertTrue(isShown(step.hintLabel))
        XCTAssertEqual(step.hintLabel.stringValue, "Your own glide time, set in Settings › Scrolling.")
        click(controller.primaryButton)
        XCTAssertEqual(world.scroll.duration, 3.4)
    }

    /// The line for a glide time of one's own takes its room out of the gap between the
    /// cards and the box, so the box under it stays where it is (it moved up by a point).
    func testTheLineForACustomGlideTimeDoesNotMoveTheBox() {
        let controller = makeFeelController()
        _ = makeWindow(for: controller)
        let step = controller.feelStep
        func boxTop() -> CGFloat {
            controller.view.layoutSubtreeIfNeeded()
            return step.reverseBox.convert(step.reverseBox.bounds, to: nil).maxY
        }
        let without = boxTop()
        XCTAssertFalse(isShown(step.hintLabel))

        world.scroll.duration = 3.4
        step.refresh()
        XCTAssertTrue(isShown(step.hintLabel))
        let hintHeight = step.hintLabel.fittingSize.height
        if WelcomeGuideFeelStep.rowToBox >= 2 * WelcomeGuideFeelStep.hintSpacing + hintHeight {
            XCTAssertEqual(boxTop(), without, accuracy: 0.5, "the roomy window: the line fits into the gap")
        }
        // The rule itself, for both windows: the gap is used up, never less than the least room.
        XCTAssertEqual(WelcomeGuideFeelStep.spacingUnderHint(hintHeight: 15), max(6, WelcomeGuideFeelStep.rowToBox - 6 - 15))
        XCTAssertEqual(WelcomeGuideFeelStep.spacingUnderHint(hintHeight: 100), WelcomeGuideFeelStep.hintSpacing)

        ScrollFeel.smooth.apply(to: world.scroll)
        step.refresh()
        XCTAssertEqual(boxTop(), without, accuracy: 0.5)
    }

    func testAPickStoresOnlyThePresetsGlideTime() throws {
        let controller = makeFeelController()
        let step = controller.feelStep
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        func storedOptions() throws -> [String: Any] {
            return try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(world.scroll)) as? [String: Any])
        }
        let before = try storedOptions()
        for feel in [ScrollFeel.direct, .float, .quick, .glide] {
            click(step.feelButtons[feel.rawValue])
            XCTAssertEqual(world.scroll.duration, feel.duration)
            XCTAssertEqual(step.feelButtons.filter { $0.state == .on }.map(\.feel), [feel])
            XCTAssertFalse(isShown(step.hintLabel))
            var after = try storedOptions()
            after["duration"] = before["duration"]
            XCTAssertEqual(after as NSDictionary, before as NSDictionary, "only the glide time changed")
        }
        // The same path as the Scrolling pane's Feel control.
        let other = OPTIONS_SCROLL_DEFAULT()
        ScrollFeel.float.apply(to: other)
        XCTAssertEqual(other.duration, 4.6)
    }

    /// The picture on a card: a mark where the wheel stops and a dot where the page comes to
    /// rest. The owner found the five curves the cards had "very alike": each card's dot now
    /// rests clearly further from the mark than the one before. It is a rank, not a measure,
    /// so the cards must be in the order of their glide times.
    func testEachCardsDotRestsFurtherThanTheOneBefore() throws {
        let feels = ScrollFeel.allCases
        XCTAssertEqual(feels.count, 5)
        let glideTimes = feels.map(\.duration)
        XCTAssertEqual(glideTimes, glideTimes.sorted(), "the cards are in the order of their glide times")

        let dots = feels.map { WelcomeGuideFeelButton.dotX(for: $0) }
        for (earlier, later) in zip(dots, dots.dropFirst()) {
            XCTAssertGreaterThanOrEqual(later - earlier, 12, "\(dots)")
        }
        let radius = WelcomeGuideFeelButton.dotRadius
        XCTAssertGreaterThan(
            try XCTUnwrap(dots.first) - radius, WelcomeGuideFeelButton.trailStart + 2,
            "Direct still shows a little of the trail"
        )
        XCTAssertLessThanOrEqual(try XCTUnwrap(dots.last) + radius, WelcomeGuideFeelButton.pictureSize.width - 2)
    }

    func testWhenTheBoxIsNotSmoothedTheStepSaysWhyAndShowsTheDemo() {
        let controller = makeFeelController()
        let step = controller.feelStep
        XCTAssertEqual(step.artwork.pillText, "Scroll here with your mouse")
        let cases: [(WelcomeGuideTryArea, String)] = [
            (.notRunning, "Not smoothed: Scrollio isn't running"),
            (.notInAppList, "Not smoothed: Scrollio isn't on the app list"),
            (.smoothingOff, "Not smoothed: Smooth scrolling is off"),
        ]
        for (state, line) in cases {
            world.tryArea = state
            controller.accessibilityPermissionsChecker(nil)
            XCTAssertEqual(step.textLabel.stringValue, "Watch the page above, then pick what feels right. You can change it later in Settings.")
            XCTAssertEqual(step.artwork.pillText, line)
            XCTAssertTrue(isShown(step.artwork.pill))
            // One line over the page.
            step.artwork.pill.layoutSubtreeIfNeeded()
            XCTAssertLessThan(step.artwork.pill.frame.height, 24, line)
        }
        // With Reduce Motion the demo stands still too: no "watch".
        world.reduceMotion = true
        controller.accessibilityPermissionsChecker(nil)
        XCTAssertEqual(step.textLabel.stringValue, "Pick what feels right. You can change it later in Settings.")
        world.tryArea = .smoothed
        controller.accessibilityPermissionsChecker(nil)
        XCTAssertEqual(
            step.textLabel.stringValue,
            "Scroll the page above with your mouse wheel, then pick what feels right. You can change it later in Settings."
        )
    }

    private func scrollEvent(phase: Int64, synthetic: Bool) throws -> NSEvent {
        let cg = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -4, wheel2: 0, wheel3: 0))
        cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        if synthetic {
            ScrollUtils.shared.markSyntheticSmoothEvent(cg)
        }
        return try XCTUnwrap(NSEvent(cgEvent: cg))
    }

    func testTheBoxIsARealScrollViewThatTellsATrackpadApart() throws {
        let controller = makeFeelController()
        let picture = controller.feelStep.artwork
        let scrollView = picture.scrollView
        XCTAssertTrue(scrollView.documentView === picture.page)
        XCTAssertGreaterThan(picture.page.frame.height, scrollView.contentSize.height * 5, "a long page")
        XCTAssertEqual(scrollView.contentSize.height, 174, accuracy: 2, "about 180 pt to scroll in")
        XCTAssertEqual(scrollView.accessibilityLabel(), "Sample page to try scrolling on")

        // A wheel (or Scrollio's own smoothed frames, phases and all): the invitation goes.
        scrollView.scrollWheel(with: try scrollEvent(phase: 0, synthetic: false))
        XCTAssertTrue(picture.hasUserScrolled)
        XCTAssertTrue(picture.isDemoPaused, "nothing animates while the user scrolls")
        XCTAssertNil(picture.pillText)
        scrollView.scrollWheel(with: try scrollEvent(phase: 1, synthetic: true))
        XCTAssertFalse(picture.sawTrackpad)

        // A trackpad's own phase, without Scrollio's marker.
        scrollView.scrollWheel(with: try scrollEvent(phase: 1, synthetic: false))
        XCTAssertTrue(picture.sawTrackpad)
        XCTAssertEqual(picture.pillText, "Trackpads and Magic Mouse aren't changed")

        // The next wheel scroll takes the line away; another trackpad scroll brings it back
        // for a while (4 s), then it goes by itself.
        scrollView.scrollWheel(with: try scrollEvent(phase: 0, synthetic: false))
        XCTAssertFalse(picture.sawTrackpad)
        XCTAssertNil(picture.pillText)
        scrollView.scrollWheel(with: try scrollEvent(phase: 2, synthetic: false))
        XCTAssertEqual(picture.pillText, "Trackpads and Magic Mouse aren't changed")
        XCTAssertEqual(WelcomeGuideFeelPicture.trackpadNoteDuration, 4)
        let timer = try XCTUnwrap(picture.trackpadNoteTimer)
        timer.fire()
        XCTAssertNil(picture.pillText)
        XCTAssertTrue(picture.sawTrackpad, "still a trackpad: the line does not come back with every event")
        scrollView.scrollWheel(with: try scrollEvent(phase: 2, synthetic: false))
        XCTAssertNil(picture.pillText)
    }

    func testTheDemoNeverRunsOffScreenAndStopsWithReduceMotion() {
        let controller = makeFeelController()
        _ = makeWindow(for: controller)
        let picture = controller.feelStep.artwork
        XCTAssertFalse(picture.isClockRunning, "the window is not on screen")
        // The demo moves the real page (and only along it).
        picture.show(time: 1.0)
        XCTAssertGreaterThan(picture.scrollView.contentView.bounds.minY, 5)
        XCTAssertEqual(picture.scrollView.contentView.bounds.minX, 0)

        // On screen it runs; with Reduce Motion it does not.
        picture.isWindowVisible = { _ in true }
        picture.updateClock()
        XCTAssertTrue(picture.isClockRunning)
        world.reduceMotion = true
        picture.updateClock()
        XCTAssertFalse(picture.isClockRunning)
    }

    /// Every picture's loop: only while its step shows in a window that can be seen, never
    /// with Reduce Motion (the system says so through a notification, which calls `updateClock`).
    func testEveryPictureStandsStillWithReduceMotion() {
        world.runAfterGrant = .running
        let controller = world.makeController(flow: .full)
        _ = makeWindow(for: controller)
        for step in [WelcomeGuideStep.welcome, .access, .feel, .finish] {
            controller.go(by: controller.steps.firstIndex(of: step)! - controller.index)
            let picture = pictureClock(of: step, in: controller)
            picture.isWindowVisible = { _ in true }
            world.reduceMotion = false
            controller.stepView(for: step).setShown(true)
            XCTAssertTrue(picture.isClockRunning, "\(step)")
            world.reduceMotion = true
            picture.updateClock()
            XCTAssertFalse(picture.isClockRunning, "\(step) moves with Reduce Motion")
            world.reduceMotion = false
            picture.updateClock()
            XCTAssertTrue(picture.isClockRunning, "\(step)")
        }
    }

    private func pictureClock(of step: WelcomeGuideStep, in controller: IntroductionViewController) -> WelcomeGuideAnimatedView {
        switch step {
        case .welcome: return controller.welcomeStep.artwork
        case .access: return controller.accessStep.artwork
        case .feel: return controller.feelStep.artwork
        case .finish: return controller.finishStep.artwork
        }
    }

    /// The demo waits while the pointer is on the page. A step taken out of the window hears
    /// no mouse-exit: when it comes back, the demo plays again.
    func testTheDemoPlaysAgainAfterTheStepWasLeftWithThePointerOnThePage() {
        let controller = makeFeelController()
        _ = makeWindow(for: controller)
        let picture = controller.feelStep.artwork
        picture.isWindowVisible = { _ in true }
        picture.updateClock()
        XCTAssertTrue(picture.isClockRunning)
        picture.scrollView.onHover?(true)
        XCTAssertTrue(picture.isDemoPaused)
        XCTAssertFalse(picture.isClockRunning, "nothing animates while the pointer is on the page")
        controller.go(by: 1)
        controller.go(by: -1)
        XCTAssertEqual(controller.currentStep, .feel)
        XCTAssertFalse(picture.isDemoPaused)
        XCTAssertTrue(picture.isClockRunning, "the demo plays again")
    }

    // MARK: - One press per click, the lifecycle

    /// A press right after a step change (the second click of a double-click) and a held
    /// Return used to act on the step that had just come in under the same button: Continue
    /// then Done, or Open Accessibility Settings. A later click counts whatever its click
    /// count: with a slow double-click speed set in macOS, deliberate clicks on Continue, step
    /// after step in the same place, arrive as a second and a third click.
    func testAPressRightAfterAStepChangeOrAHeldKeyDoesNothing() throws {
        world.accessGranted = true
        world.run = .running
        world.isClockHeld = true
        let controller = world.makeController(flow: .full)
        XCTAssertEqual(controller.steps, [.welcome, .feel, .finish])
        let window = makeWindow(for: controller)
        func mouseUp(clicks: Int) -> NSEvent? {
            return NSEvent.mouseEvent(
                with: .leftMouseUp, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: clicks, pressure: 0
            )
        }
        func returnKey(repeated: Bool) -> NSEvent? {
            return NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: repeated, keyCode: 36
            )
        }
        world.currentEvent = mouseUp(clicks: 1)
        click(controller.primaryButton)
        XCTAssertEqual(controller.currentStep, .feel)
        world.currentEvent = mouseUp(clicks: 2)
        click(controller.primaryButton)
        click(controller.backButton)
        XCTAssertEqual(controller.currentStep, .feel, "the second click of a double-click")
        world.uptime += IntroductionViewController.pressSettleTime - 0.05
        click(controller.primaryButton)
        XCTAssertEqual(controller.currentStep, .feel, "still right after the change")

        world.uptime += 0.1
        world.currentEvent = returnKey(repeated: true)
        click(controller.primaryButton)
        XCTAssertEqual(controller.currentStep, .feel, "a held Return")
        world.currentEvent = mouseUp(clicks: 2)
        click(controller.primaryButton)
        XCTAssertEqual(controller.currentStep, .finish, "a later click counts, whatever its click count")

        world.currentEvent = mouseUp(clicks: 3)
        click(controller.primaryButton)
        click(controller.secondaryButton)
        XCTAssertFalse(world.progress.isFinished, "neither Done nor Open Settings right after the change")
        XCTAssertEqual(world.appSettingsOpened, 0)
        world.uptime += IntroductionViewController.pressSettleTime + 0.01
        click(controller.primaryButton)
        XCTAssertTrue(world.progress.isFinished, "Done, as the third click in the same place")
    }

    /// A real double-click on Continue: one step.
    func testADoubleClickOnContinueTakesOneStep() {
        world.accessGranted = true
        world.run = .running
        let controller = world.makeController(flow: .full)
        _ = makeEventWindow(for: controller)
        let primary = controller.primaryButton!
        realClick(primary, at: middle(of: primary))
        realClick(primary, at: middle(of: primary), clickCount: 2)
        settle(0.6)
        XCTAssertEqual(controller.currentStep, .feel)
        XCTAssertEqual(world.scroll.duration, OPTIONS_SCROLL_DEFAULT().duration)
    }

    /// While the steps change, the incoming step's controls are in place but cannot be seen,
    /// and the main button already means the next step: presses do nothing until the text is in.
    func testAPressWhileTheStepsChangeDoesNothing() {
        world.accessGranted = true
        world.run = .running
        let controller = world.makeController(flow: .full)
        _ = makeEventWindow(for: controller)
        let primary = controller.primaryButton!
        realClick(primary, at: middle(of: primary))
        XCTAssertEqual(controller.currentStep, .feel)
        XCTAssertTrue(controller.isChangingStep)
        let float = controller.feelStep.feelButtons[ScrollFeel.float.rawValue]
        realClick(float, at: NSPoint(x: float.bounds.midX, y: float.bounds.midY))
        realClick(primary, at: middle(of: primary))
        XCTAssertEqual(controller.currentStep, .feel, "Continue again, unseen")
        XCTAssertEqual(world.scroll.duration, ScrollFeel.smooth.duration, "a card that could not be seen yet")

        settle(0.7)
        XCTAssertFalse(controller.isChangingStep)
        realClick(float, at: NSPoint(x: float.bounds.midX, y: float.bounds.midY))
        XCTAssertEqual(world.scroll.duration, ScrollFeel.float.duration)
        realClick(primary, at: middle(of: primary))
        XCTAssertEqual(controller.currentStep, .finish)
    }

    /// The end of a step change comes from an animation's completion handler. When that
    /// call never comes (seen with no display awake), the step still arrives a little after
    /// the animations should have ended: Continue and Back used to stay dead until the
    /// window was reopened.
    func testAStepChangeWhoseAnimationNeverReportsItsEndStillArrives() {
        world.accessGranted = true
        world.run = .running
        for reduceMotion in [false, true] {
            world.reduceMotion = reduceMotion
            let controller = world.makeController(flow: .full)
            _ = makeEventWindow(for: controller)
            // The changes are made; no completion handler is ever called.
            controller.runAnimation = { changes, _ in
                NSAnimationContext.runAnimationGroup { context in changes(context) }
            }
            controller.stepArrivalGrace = 0.05
            let primary = controller.primaryButton!
            realClick(primary, at: middle(of: primary))
            XCTAssertEqual(controller.currentStep, .feel)
            XCTAssertTrue(controller.isChangingStep)
            realClick(primary, at: middle(of: primary))
            XCTAssertEqual(controller.currentStep, .feel, "no press while the steps change")

            let animations = reduceMotion
                ? IntroductionViewController.crossfadeDuration
                : IntroductionViewController.textOutDuration + IntroductionViewController.textInDuration
            settle(animations + controller.stepArrivalGrace + 0.25)
            XCTAssertFalse(controller.isChangingStep, "reduce motion \(reduceMotion)")
            // The step that came is all there, the one that went is gone.
            XCTAssertEqual(controller.feelStep.content.alphaValue, 1)
            XCTAssertEqual(controller.feelStep.picture.alphaValue, 1)
            XCTAssertEqual(controller.feelStep.content.frame.origin, .zero)
            XCTAssertNil(controller.welcomeStep.content.superview)
            XCTAssertNil(controller.welcomeStep.picture.superview)
            realClick(primary, at: middle(of: primary))
            XCTAssertEqual(controller.currentStep, .finish, "Continue works again, reduce motion \(reduceMotion)")
        }
    }

    /// The safety timer belongs to one step change: another change that begins meanwhile
    /// cancels it and gets its own, and a change that arrived leaves none.
    func testTheSafetyTimerOfAStepChangeGoesWithIt() throws {
        world.accessGranted = true
        world.run = .running
        let controller = world.makeController(flow: .full)
        _ = makeEventWindow(for: controller)
        controller.runAnimation = { changes, _ in
            NSAnimationContext.runAnimationGroup { context in changes(context) }
        }
        XCTAssertNil(controller.stepArrivalTimer, "no change, no timer")
        controller.go(by: 1)
        let first = try XCTUnwrap(controller.stepArrivalTimer)
        XCTAssertTrue(first.isValid)
        let length = IntroductionViewController.textOutDuration + IntroductionViewController.textInDuration
        XCTAssertEqual(first.fireDate.timeIntervalSinceNow, length + controller.stepArrivalGrace, accuracy: 0.2)

        controller.go(by: 1)
        XCTAssertEqual(controller.currentStep, .finish)
        XCTAssertFalse(first.isValid, "the abandoned change's timer is cancelled")
        let second = try XCTUnwrap(controller.stepArrivalTimer)
        XCTAssertFalse(second === first)
        XCTAssertTrue(controller.isChangingStep)

        second.fire()
        XCTAssertFalse(controller.isChangingStep)
        XCTAssertNil(controller.stepArrivalTimer)
        XCTAssertEqual(controller.finishStep.content.alphaValue, 1)
        XCTAssertNil(controller.feelStep.content.superview)

        // A change whose animations do report their end leaves no timer either.
        controller.runAnimation = { changes, completion in
            NSAnimationContext.runAnimationGroup { context in changes(context) }
            completion()
        }
        controller.go(by: -1)
        XCTAssertFalse(controller.isChangingStep)
        XCTAssertNil(controller.stepArrivalTimer)
    }

    /// The poll runs while the window shows; AppRunController's change is heard only then.
    func testThePollAndTheRunStateFollowTheWindow() {
        world.accessGranted = true
        world.run = .retrying
        let controller = world.makeController(flow: .full)
        XCTAssertEqual(controller.accessState, .couldNotStart)
        XCTAssertNil(controller.accessibilityPermissionsCheckerTimer)
        world.run = .running
        NotificationCenter.default.post(name: AppRunController.didChangeNotification, object: nil)
        XCTAssertEqual(controller.accessState, .couldNotStart, "not listening before the window appears")

        controller.viewWillAppear()
        XCTAssertNotNil(controller.accessibilityPermissionsCheckerTimer)
        XCTAssertTrue(controller.accessibilityPermissionsCheckerTimer?.isValid ?? false)
        XCTAssertEqual(controller.accessState, .running, "read when it appears")
        world.run = .paused
        NotificationCenter.default.post(name: AppRunController.didChangeNotification, object: nil)
        XCTAssertEqual(controller.accessState, .paused)

        controller.viewWillDisappear()
        XCTAssertNil(controller.accessibilityPermissionsCheckerTimer)
        world.run = .running
        NotificationCenter.default.post(name: AppRunController.didChangeNotification, object: nil)
        XCTAssertEqual(controller.accessState, .paused, "not listening once it is gone")

        controller.viewWillAppear()
        XCTAssertNotNil(controller.accessibilityPermissionsCheckerTimer)
        controller.windowWillClose()
        XCTAssertNil(controller.accessibilityPermissionsCheckerTimer)
        controller.viewWillDisappear()
    }

    /// Only the picture of the step on screen plays, and none once the window closes.
    func testOnlyTheShownStepsPictureMovesAndNoneAfterTheWindowCloses() {
        let controller = world.makeController(flow: .full)
        _ = makeWindow(for: controller)
        XCTAssertEqual(controller.steps, WelcomeGuideStep.allCases)
        for step in WelcomeGuideStep.allCases {
            pictureClock(of: step, in: controller).isWindowVisible = { _ in true }
        }
        controller.viewWillAppear()
        for step in WelcomeGuideStep.allCases {
            controller.go(by: controller.steps.firstIndex(of: step)! - controller.index)
            for other in WelcomeGuideStep.allCases {
                XCTAssertEqual(pictureClock(of: other, in: controller).isClockRunning, other == step, "on \(step): \(other)")
            }
        }
        controller.windowWillClose()
        for step in WelcomeGuideStep.allCases {
            XCTAssertFalse(pictureClock(of: step, in: controller).isClockRunning, "\(step) after close")
        }
        controller.viewWillDisappear()
    }

    /// Allowed while the guide was closed, the event taps not started yet: the run starts them
    /// at once instead of waiting for the app's next try (up to 10 s of "Starting Scrollio…").
    func testARunThatBeginsWithTheAccessButNoEventTapsStartsThemAtOnce() {
        world.accessGranted = true
        world.run = .stopped
        world.runAfterGrant = .running
        let controller = world.makeController(flow: .full)
        XCTAssertEqual(controller.steps, [.welcome, .access, .feel, .finish])
        XCTAssertEqual(controller.accessState, .starting)
        controller.accessibilityPermissionsChecker(nil)
        XCTAssertEqual(world.grantsReported, 1)
        XCTAssertEqual(controller.accessState, .running)
        XCTAssertTrue(world.announcements.isEmpty, "nothing new to announce")
        controller.accessibilityPermissionsChecker(nil)
        XCTAssertEqual(world.grantsReported, 1)
    }

    /// "Allow Accessibility Access…" while a guide without the Accessibility step is open (it
    /// began with the access, which went since): the guide starts again with the step.
    func testAnOpenGuideAsksForTheAccessAgainWhenItWent() {
        world.accessGranted = true
        world.run = .running
        let controller = world.makeController(flow: .full)
        XCTAssertEqual(controller.steps, [.welcome, .feel, .finish])
        controller.go(by: 1)
        XCTAssertNil(IntroductionWindowController.restart(controller, for: .automatic), "the access is still there")
        XCTAssertNil(IntroductionWindowController.restart(controller, for: .byHand))
        world.accessGranted = false
        world.run = .stopped
        XCTAssertEqual(IntroductionWindowController.restart(controller, for: .automatic), .full)
        controller.begin(.full)
        XCTAssertEqual(controller.steps, [.welcome, .access, .feel, .finish])
        XCTAssertNil(IntroductionWindowController.restart(controller, for: .automatic), "it has the step now")
        // By hand the Accessibility step alone becomes the whole guide; the app leaves it alone.
        controller.begin(.accessOnly)
        XCTAssertEqual(IntroductionWindowController.restart(controller, for: .byHand), .full)
        XCTAssertNil(IntroductionWindowController.restart(controller, for: .automatic))
    }

    func testTheAccessPictureStopsOnceTheAccessIsAllowed() {
        world.runAfterGrant = .running
        let controller = makeAccessController()
        _ = makeWindow(for: controller)
        let picture = controller.accessStep.artwork
        picture.isWindowVisible = { _ in true }
        controller.accessStep.setShown(true)
        XCTAssertTrue(picture.isClockRunning)
        world.accessGranted = true
        controller.accessibilityPermissionsChecker(nil)
        XCTAssertFalse(picture.isClockRunning, "no display link for a picture that stands still")
        XCTAssertEqual(picture.shownFrame.switchOn, 1)
        world.accessGranted = false
        world.run = .stopped
        controller.accessibilityPermissionsChecker(nil)
        XCTAssertTrue(picture.isClockRunning, "the loop is back with the request")
    }

    /// "Open at login" may open Login Items for an approval: it comes after the Preferences,
    /// so it is the window in front.
    func testOpenSettingsLeavesLoginItemsInFront() {
        let fake = install(.requiresApproval)
        fake.afterRegister = nil
        fake.onOpenSystemSettings = { self.world.log.append("Login Items") }
        let controller = makeFinishController(finished: true)
        let row = controller.finishStep.loginRow!
        row.toggle.state = .on
        XCTAssertTrue(row.toggle.sendAction(row.toggle.action, to: row.toggle.target))
        click(controller.secondaryButton)
        XCTAssertEqual(world.log, ["Preferences", "Login Items"])
    }

    /// The switch shows what will be set: closing the window on the last step applies it as
    /// Done does, once.
    func testClosingTheWindowOnTheLastStepAppliesOpenAtLoginOnce() {
        let fake = install(.notRegistered)
        let controller = makeFinishController()
        XCTAssertTrue(controller.finishStep.loginRow.isOn, "a new user's switch is on")
        controller.windowWillClose()
        XCTAssertEqual(fake.registerCalls, 1)
        XCTAssertTrue(Options.shared.general.autoLaunch)
        controller.windowWillClose()
        XCTAssertEqual(fake.registerCalls, 1, "once")

        // Done, then the close that follows it: once.
        let other = install(.notRegistered)
        let second = makeFinishController()
        let window = makeWindow(for: second)
        let closed = expectation(forNotification: NSWindow.willCloseNotification, object: window)
        click(second.primaryButton)
        wait(for: [closed], timeout: 1)
        second.windowWillClose()
        XCTAssertEqual(other.registerCalls, 1)
        XCTAssertEqual(other.unregisterCalls, 0)
    }

    /// Back is ⌘[ (as in Finder and System Settings); Esc neither goes back nor closes.
    func testBackIsCommandBracketAndEscDoesNothing() {
        world.accessGranted = true
        world.run = .running
        let controller = world.makeController(flow: .full)
        let window = makeWindow(for: controller)
        controller.go(by: 1)
        XCTAssertEqual(controller.currentStep, .feel)
        var closes = 0
        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: nil
        ) { _ in closes += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        press("\u{1b}", keyCode: 53, in: window)
        controller.cancelOperation(nil)
        XCTAssertEqual(controller.currentStep, .feel)
        XCTAssertEqual(closes, 0)
        press("[", keyCode: 33, modifiers: .command, in: window)
        XCTAssertEqual(controller.currentStep, .welcome)
    }

    /// The title sits at one height on every step (the text slides between them); the rows
    /// under the Welcome and feel titles are as wide as the picture; the three features are
    /// one height, so the box that moves between them keeps its size; nothing comes closer
    /// than 16 pt to the bar.
    func testTheStepsShareOneGrid() throws {
        XCTAssertEqual(WelcomeGuideLayout.metrics, .roomy)
        try assertTheStepsShareOneGrid()
    }

    /// The same rules in the 620 pt window of a screen too short for the roomy one.
    func testTheTightGridOfAShortScreenKeepsTheRules() throws {
        WelcomeGuideLayout.metrics = .tight
        addTeardownBlock { WelcomeGuideLayout.metrics = .roomy }
        XCTAssertEqual(WelcomeGuideLayout.windowSize.height, 620)
        try assertTheStepsShareOneGrid()
    }

    /// The owner found the feel step crammed in 620 pt (its parts 14 to 18 pt apart). The
    /// window is 680 pt tall unless the screen cannot show that whole: then Continue would
    /// lie under the Dock, and the guide keeps the 620 pt it had.
    func testTheWindowIsRoomyUnlessTheScreenIsTooShort() {
        typealias Metrics = WelcomeGuideLayout.Metrics
        XCTAssertEqual(Metrics.roomy.windowHeight, 680)
        XCTAssertEqual(Metrics.tight.windowHeight, 620)
        XCTAssertEqual(Metrics.fitting(visibleHeight: nil), .roomy)
        XCTAssertEqual(Metrics.fitting(visibleHeight: 838), .roomy, "a 13-inch display at its default size")
        XCTAssertEqual(Metrics.fitting(visibleHeight: 696), .roomy)
        XCTAssertEqual(Metrics.fitting(visibleHeight: 695), .tight)
        XCTAssertEqual(Metrics.fitting(visibleHeight: 637), .tight, "a 13-inch display at Larger Text")
    }

    /// The air on the feel step: its sentence, cards, box and the bar stand well apart.
    func testTheFeelStepHasAirBetweenItsParts() throws {
        let controller = world.makeController(flow: .full)
        _ = makeWindow(for: controller)
        controller.go(by: try XCTUnwrap(controller.steps.firstIndex(of: .feel)) - controller.index)
        controller.view.layoutSubtreeIfNeeded()
        let canvas = try XCTUnwrap(controller.contentHost.superview)
        func frame(_ view: NSView) -> NSRect {
            return canvas.convert(view.bounds, from: view)
        }
        let step = controller.feelStep
        let cards = step.feelButtons.map(frame).reduce(NSRect.null) { $0.union($1) }
        let box = frame(step.reverseBox)
        XCTAssertGreaterThanOrEqual(cards.minY - frame(step.textLabel).maxY, 24, "sentence to cards")
        XCTAssertGreaterThanOrEqual(box.minY - cards.maxY, 24, "cards to box")
        XCTAssertGreaterThanOrEqual(WelcomeGuideLayout.barFrame.minY - box.maxY, 40, "box to bar")
        XCTAssertGreaterThanOrEqual(frame(step.titleLabel).minY - WelcomeGuideLayout.pictureFrame.maxY, 36, "picture to title")
    }

    private func assertTheStepsShareOneGrid() throws {
        world.runAfterGrant = .running
        world.mouse = .mxMaster4
        let controller = world.makeController(flow: .full)
        _ = makeWindow(for: controller)
        let canvas = try XCTUnwrap(controller.contentHost.superview)
        let bar = WelcomeGuideLayout.barFrame
        func frame(_ view: NSView) -> NSRect {
            return canvas.convert(view.bounds, from: view)
        }
        func assertClearOfTheBar(_ step: WelcomeGuideStep, _ note: String = "") {
            controller.view.layoutSubtreeIfNeeded()
            let content = controller.stepView(for: step).content
            for view in allSubviews(of: content).filter(isShown) {
                XCTAssertLessThanOrEqual(frame(view).maxY, bar.minY - 16, "\(step)\(note): \(type(of: view)) \(frame(view))")
            }
        }
        var titleTops: [CGFloat] = []
        for step in WelcomeGuideStep.allCases {
            controller.go(by: controller.steps.firstIndex(of: step)! - controller.index)
            controller.view.layoutSubtreeIfNeeded()
            let title: NSTextField
            switch step {
            case .welcome: title = controller.welcomeStep.titleLabel
            case .access: title = controller.accessStep.titleLabel
            case .feel: title = controller.feelStep.titleLabel
            case .finish: title = controller.finishStep.titleLabel
            }
            titleTops.append(frame(title).minY)
            assertClearOfTheBar(step)
            if step == .welcome {
                let features = controller.welcomeStep.features
                let row = features.map(frame).reduce(NSRect.null) { $0.union($1) }
                XCTAssertEqual(row.width, WelcomeGuideLayout.pictureSize.width, accuracy: 0.5)
                XCTAssertEqual(row.minX, WelcomeGuideLayout.pictureFrame.minX, accuracy: 0.5)
                XCTAssertEqual(Set(features.map { frame($0).height }).count, 1, "\(features.map { frame($0) })")
            }
            if step == .feel {
                let row = controller.feelStep.feelButtons.map(frame).reduce(NSRect.null) { $0.union($1) }
                XCTAssertEqual(row.width, WelcomeGuideLayout.pictureSize.width, accuracy: 0.5)
                XCTAssertEqual(row.minX, WelcomeGuideLayout.pictureFrame.minX, accuracy: 0.5)
            }
        }
        XCTAssertEqual(Set(titleTops).count, 1, "\(titleTops)")

        // The feel step with the line for a glide time of one's own.
        world.scroll.duration = 3.4
        controller.go(by: controller.steps.firstIndex(of: .feel)! - controller.index)
        XCTAssertTrue(isShown(controller.feelStep.hintLabel))
        assertClearOfTheBar(.feel, ", custom glide time")
    }


    // MARK: - Real clicks and keys

    /// The guide in a window styled as the real one (IntroductionWindowController.style:
    /// movable by its background, title bar transparent over the content) that AppKit
    /// delivers events to (`GuideEventWindow`). Never key: the first click counts too.
    private func makeEventWindow(for controller: IntroductionViewController) -> NSWindow {
        let window = GuideEventWindow.make(size: WelcomeGuideLayout.windowSize)
        IntroductionWindowController.style(window)
        // Pressed with the events that come out of the application's queue.
        controller.currentEvent = { NSApp.currentEvent }
        // A step change's animations end by a timer here, not by AppKit's display link:
        // with no display awake (a night run, a headless Mac) AppKit does not call an
        // animation's completion handler in time, and the tests of presses during a change
        // failed for that reason alone. The changes are still made inside an animation group.
        controller.runAnimation = { changes, completion in
            var duration: TimeInterval = 0
            NSAnimationContext.runAnimationGroup { context in
                changes(context)
                duration = context.duration
            }
            let timer = Timer(timeInterval: duration, repeats: false) { _ in completion() }
            RunLoop.main.add(timer, forMode: .common)
        }
        window.contentViewController = controller
        window.putOutOfSight()
        addTeardownBlock {
            window.orderOut(nil)
            window.close()
        }
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertTrue(window.isMovableByWindowBackground)
        XCTAssertFalse(window.isKeyWindow)
        return window
    }

    /// Points of `view` (its own coordinates): the middle, and 2 pt inside each edge of
    /// `rect` (the view's bounds unless given: a push button's bezel is smaller).
    private func points(in view: NSView, rect: NSRect? = nil) -> [(String, NSPoint)] {
        let area = rect ?? view.bounds
        return [
            ("middle", NSPoint(x: area.midX, y: area.midY)),
            ("left edge", NSPoint(x: area.minX + 2, y: area.midY)),
            ("right edge", NSPoint(x: area.maxX - 2, y: area.midY)),
            ("top edge", NSPoint(x: area.midX, y: view.isFlipped ? area.minY + 2 : area.maxY - 2)),
            ("bottom edge", NSPoint(x: area.midX, y: view.isFlipped ? area.maxY - 2 : area.minY + 2)),
        ]
    }

    /// The visible bezel of a push button, in its own coordinates.
    private func bezel(of button: NSButton) -> NSRect {
        let alignment = button.alignmentRect(forFrame: button.frame)
        return button.convert(alignment, from: button.superview)
    }

    /// The view AppKit hands a click at `point` of `view` to: it must be `view` or inside
    /// it, and must not let the press drag the window (which moves by its background).
    private func assertTakesTheClick(
        _ view: NSView, at point: NSPoint, _ name: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        guard let frameView = view.window?.contentView?.superview else {
            return XCTFail("\(name): not in a window", file: file, line: line)
        }
        let hit = frameView.hitTest(view.convert(point, to: nil))
        XCTAssertTrue(hit.map { $0 === view || $0.isDescendant(of: view) } ?? false,
                      "\(name): the click goes to \(hit.map { String(describing: type(of: $0)) } ?? "nothing")", file: file, line: line)
        XCTAssertEqual(hit?.mouseDownCanMoveWindow, false, "\(name): a press there drags the window", file: file, line: line)
    }

    /// A click as the mouse makes it: down at the first point of `path` (in `view`'s
    /// coordinates), a drag through the others, up at the last. The events go into the
    /// application's queue and from there to the window, as the run loop hands them on; a
    /// control that tracks the mouse in a loop of its own takes the rest of the click from
    /// the queue itself. With `whilePressed` the rest comes a moment after the down, from a
    /// timer that also runs inside such a loop, and `whilePressed` runs while the button is held.
    private func realClick(
        _ view: NSView, path: [NSPoint], clickCount: Int = 1, whilePressed: (() -> Void)? = nil,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        guard let window = view.window, let first = path.first, let last = path.last else {
            return XCTFail("nothing to click", file: file, line: line)
        }
        func event(_ type: NSEvent.EventType, at point: NSPoint) -> NSEvent {
            return NSEvent.mouseEvent(
                with: type, location: view.convert(point, to: nil), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: clickCount, pressure: type == .leftMouseUp ? 0 : 1
            )!
        }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        var restPosted = false
        var downInProgress = false
        var postedDuringDown = false
        func postRest() {
            whilePressed?()
            for point in path.dropFirst() {
                NSApp.postEvent(event(.leftMouseDragged, at: point), atStart: false)
            }
            NSApp.postEvent(event(.leftMouseUp, at: last), atStart: false)
            restPosted = true
            postedDuringDown = downInProgress
        }
        NSApp.postEvent(event(.leftMouseDown, at: first), atStart: false)
        if whilePressed == nil {
            postRest()
        } else {
            RunLoop.main.add(Timer(timeInterval: 0.02, repeats: false) { _ in postRest() }, forMode: .common)
        }
        let deadline = Date(timeIntervalSinceNow: 3)
        while Date() < deadline {
            guard let next = NSApp.nextEvent(matching: mask, until: Date(timeIntervalSinceNow: 0.05), inMode: .default, dequeue: true) else {
                continue
            }
            downInProgress = next.type == .leftMouseDown
            window.sendEvent(next)
            downInProgress = false
            if next.type == .leftMouseUp {
                return
            }
            // The control tracked the mouse in its own loop and took the up from the queue.
            let upQueued = NSApp.nextEvent(matching: .leftMouseUp, until: .distantPast, inMode: .default, dequeue: false) != nil
            if next.type == .leftMouseDown && (postedDuringDown || (restPosted && !upQueued)) {
                return
            }
        }
        XCTFail("the click never finished", file: file, line: line)
    }

    /// A click at `point` with the pointer moving `move` points toward the middle between
    /// down and up (a hand is never quite still).
    private func realClick(
        _ view: NSView, at point: NSPoint, move: CGFloat = 0, clickCount: Int = 1, whilePressed: (() -> Void)? = nil,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let towardX: CGFloat = point.x <= view.bounds.midX ? 1 : -1
        let towardY: CGFloat = point.y <= view.bounds.midY ? 1 : -1
        let path = move == 0 ? [point] : [point, NSPoint(x: point.x + move * towardX, y: point.y + move * towardY)]
        realClick(view, path: path, clickCount: clickCount, whilePressed: whilePressed, file: file, line: line)
    }

    /// The middle of a push button's bezel.
    private func middle(of button: NSButton) -> NSPoint {
        let rect = bezel(of: button)
        return NSPoint(x: rect.midX, y: rect.midY)
    }

    private func press(_ characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags = [], in window: NSWindow) {
        let arrow = characters.unicodeScalars.first.map { $0.value >= 0xF700 } ?? false
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: arrow ? [.numericPad, .function] : modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
        )!
        window.sendEvent(event)
    }

    private func arrow(_ key: Int) -> String {
        return String(Character(UnicodeScalar(UInt32(key))!))
    }

    /// The feel step in a window that takes real events, its demo running: the clock is on
    /// (no display ticks off screen, so `tick` plays the moments the clock would show).
    private func makeFeelWindow() -> (IntroductionViewController, NSWindow) {
        let controller = makeFeelController()
        let window = makeEventWindow(for: controller)
        let picture = controller.feelStep.artwork
        picture.isWindowVisible = { _ in true }
        picture.updateClock()
        XCTAssertTrue(picture.isClockRunning, "the demo runs")
        return (controller, window)
    }

    private var demoTime: TimeInterval = 0
    /// Where the demo put the page at each moment `tick` played.
    private var demoPagePositions: Set<CGFloat> = []

    /// What happens while the button is held: the demo moves the page, the window's poll ticks.
    private func tick(_ controller: IntroductionViewController) {
        let picture = controller.feelStep.artwork
        for _ in 0..<3 {
            demoTime += 1.0 / 60
            picture.show(time: demoTime)
            demoPagePositions.insert(picture.scrollView.contentView.bounds.minY)
        }
        controller.accessibilityPermissionsChecker(nil)
    }

    /// Lets a change of step finish: 0.2 s with Reduce Motion (a crossfade, nothing moves),
    /// 0.48 s without.
    private func settle(_ seconds: TimeInterval = 0.3) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
    }

    private func chosenFeels(_ step: WelcomeGuideFeelStep) -> [ScrollFeel] {
        return step.feelButtons.filter { $0.state == .on }.map(\.feel)
    }

    /// The owner's report: "clicking a card selects it only sometimes". AppKit's radio cell
    /// took a click only on the title it would draw (47 × 16 pt left of the middle), not on
    /// the name drawn under the picture, the picture or the edges.
    func testAClickAnywhereOnAFeelCardChoosesItWhileTheDemoRuns() {
        let (controller, _) = makeFeelWindow()
        let step = controller.feelStep
        for card in step.feelButtons {
            let size = WelcomeGuideFeelButton.size
            // The drawing: the picture at the top, the name and the word under it (top-left origin).
            let spots = points(in: card) + [
                ("picture", NSPoint(x: size.width / 2 - 20, y: 18)),
                ("name", NSPoint(x: size.width / 2, y: 44)),
                ("caption", NSPoint(x: size.width / 2, y: 60)),
            ]
            for (spot, point) in spots {
                for move in [0, 2] as [CGFloat] {
                    let name = "\(card.feel.name), \(spot), moved \(move) pt"
                    // Another feel first, so that the click has something to change.
                    let other = card.feel == .direct ? ScrollFeel.float : .direct
                    other.apply(to: world.scroll)
                    step.refresh()
                    XCTAssertEqual(chosenFeels(step), [other], name)
                    assertTakesTheClick(card, at: point, name)
                    var pressedWhileHeld = false
                    realClick(card, at: point, move: move) {
                        pressedWhileHeld = card.isHighlighted
                        self.tick(controller)
                    }
                    XCTAssertTrue(pressedWhileHeld, "\(name): no pressed look while the button is held")
                    XCTAssertFalse(card.isHighlighted, name)
                    XCTAssertEqual(chosenFeels(step), [card.feel], name)
                    XCTAssertEqual(world.scroll.duration, card.feel.duration, name)
                    XCTAssertFalse(isShown(step.hintLabel), name)
                }
            }
        }
        XCTAssertTrue(step.artwork.isClockRunning, "the demo still runs")
        XCTAssertGreaterThan(demoPagePositions.count, 10, "the demo moved the page while the cards were pressed")
        XCTAssertEqual(controller.currentStep, .feel)
    }

    /// As a button: the choice is made where the button goes up. Pressed on a card and let
    /// go off it, nothing changes; dragged off and back on, it counts.
    func testAPressThatLeavesTheCardChoosesNothing() {
        let (controller, _) = makeFeelWindow()
        let step = controller.feelStep
        let glide = step.feelButtons[ScrollFeel.glide.rawValue]
        let middle = NSPoint(x: glide.bounds.midX, y: glide.bounds.midY)
        let below = NSPoint(x: middle.x, y: glide.bounds.maxY + 30)
        realClick(glide, path: [middle, below]) {
            self.tick(controller)
        }
        XCTAssertEqual(chosenFeels(step), [.smooth], "released off the card")
        XCTAssertEqual(world.scroll.duration, ScrollFeel.smooth.duration)
        XCTAssertFalse(glide.isHighlighted)

        var pressed = false
        realClick(glide, path: [middle, below, NSPoint(x: middle.x + 3, y: middle.y)]) {
            pressed = glide.isHighlighted
        }
        XCTAssertTrue(pressed, "pressed while the pointer is on it")
        XCTAssertEqual(chosenFeels(step), [.glide], "dragged off and back on")
        XCTAssertEqual(world.scroll.duration, ScrollFeel.glide.duration)

        // Pressed on one card, released on another: neither.
        let quick = step.feelButtons[ScrollFeel.quick.rawValue]
        let float = step.feelButtons[ScrollFeel.float.rawValue]
        let onFloat = quick.convert(NSPoint(x: float.bounds.midX, y: float.bounds.midY), from: float)
        realClick(quick, path: [middle, onFloat])
        XCTAssertEqual(chosenFeels(step), [.glide])
        XCTAssertEqual(world.scroll.duration, ScrollFeel.glide.duration)
    }

    func testTheFeelCardsAreOneRadioGroupForTheKeyboard() throws {
        // Keys go to the focused view of a window whether it shows or not. This one does not:
        // a window that shows without being key (as the event window must) lets no key
        // reach its main button, and the guide's own is key while one types in it.
        let controller = makeFeelController()
        let window = makeWindow(for: controller)
        IntroductionWindowController.style(window)
        controller.view.layoutSubtreeIfNeeded()
        let step = controller.feelStep
        let cards = step.feelButtons
        let group = try XCTUnwrap(cards.first?.superview)
        XCTAssertTrue(cards.allSatisfy { $0.superview === group })
        XCTAssertEqual(group.accessibilityRole(), .radioGroup)
        XCTAssertEqual(group.accessibilityLabel(), "Feel")
        XCTAssertTrue(group.isAccessibilityElement())

        // Tab stops once, at the chosen card (it follows System Settings › Keyboard ›
        // Keyboard navigation, as every control of the window does).
        XCTAssertEqual(cards.filter(\.isGroupEntry).map(\.feel), [.smooth])
        for card in cards where !card.isGroupEntry || !NSApp.isFullKeyboardAccessEnabled {
            XCTAssertFalse(card.canBecomeKeyView, "\(card.feel.name): a second Tab stop")
        }

        // The arrows move the choice and the focus together, and stop at the ends.
        let smooth = cards[ScrollFeel.smooth.rawValue]
        XCTAssertTrue(window.makeFirstResponder(smooth))
        press(arrow(NSRightArrowFunctionKey), keyCode: 124, in: window)
        XCTAssertEqual(chosenFeels(step), [.glide])
        XCTAssertEqual(world.scroll.duration, ScrollFeel.glide.duration)
        XCTAssertTrue(window.firstResponder === cards[ScrollFeel.glide.rawValue])
        XCTAssertEqual(cards.filter(\.isGroupEntry).map(\.feel), [.glide], "Tab now stops at Glide")
        press(arrow(NSDownArrowFunctionKey), keyCode: 125, in: window)
        press(arrow(NSRightArrowFunctionKey), keyCode: 124, in: window)
        XCTAssertEqual(chosenFeels(step), [.float], "the last card stays")
        for _ in 0..<5 {
            press(arrow(NSLeftArrowFunctionKey), keyCode: 123, in: window)
        }
        XCTAssertEqual(chosenFeels(step), [.direct])
        press(arrow(NSUpArrowFunctionKey), keyCode: 126, in: window)
        XCTAssertEqual(chosenFeels(step), [.direct], "the first card stays")
        XCTAssertTrue(window.firstResponder === cards[ScrollFeel.direct.rawValue])
        XCTAssertEqual(world.scroll.duration, ScrollFeel.direct.duration)

        // A custom glide time: nothing chosen, the first card is the stop. Space chooses it.
        world.scroll.duration = 3.4
        step.refresh()
        XCTAssertTrue(chosenFeels(step).isEmpty)
        XCTAssertEqual(cards.filter(\.isGroupEntry).map(\.feel), [.direct])
        press(" ", keyCode: 49, in: window)
        XCTAssertEqual(chosenFeels(step), [.direct])
        XCTAssertEqual(world.scroll.duration, ScrollFeel.direct.duration)

        // Return chooses a focused card that is not chosen yet; on a chosen one it is the
        // window's main button (Continue).
        world.scroll.duration = 3.4
        step.refresh()
        press("\r", keyCode: 36, in: window)
        XCTAssertEqual(chosenFeels(step), [.direct])
        XCTAssertEqual(controller.currentStep, .feel, "the first Return chose")
        press("\r", keyCode: 36, in: window)
        XCTAssertEqual(controller.currentStep, .finish, "the second went on")
        XCTAssertEqual(world.scroll.duration, ScrollFeel.direct.duration)
    }

    func testVoiceOverReadsAndPressesTheFeelCards() {
        let (controller, _) = makeFeelWindow()
        let step = controller.feelStep
        for card in step.feelButtons {
            XCTAssertEqual(card.accessibilityRole(), .radioButton)
            XCTAssertEqual(card.accessibilityLabel(), card.feel.localizedName)
            XCTAssertEqual(card.accessibilityHelp(), card.caption)
            XCTAssertTrue(card.accessibilityParent() as AnyObject? === card.superview, "inside the Feel group")
        }
        let quick = step.feelButtons[ScrollFeel.quick.rawValue]
        XCTAssertTrue(quick.accessibilityPerformPress())
        XCTAssertEqual(chosenFeels(step), [.quick])
        XCTAssertEqual(world.scroll.duration, ScrollFeel.quick.duration)
        XCTAssertEqual((quick.accessibilityValue() as? NSNumber)?.intValue, 1)
        XCTAssertEqual((step.feelButtons[ScrollFeel.smooth.rawValue].accessibilityValue() as? NSNumber)?.intValue, 0)
    }

    /// The page to scroll is a real scroll view: the wheel reaches it where the pointer is,
    /// and a press on it does not drag the window. The window still moves by its background.
    func testTheTryBoxTakesTheWheelAndAPressThereDoesNotDragTheWindow() throws {
        let (controller, window) = makeFeelWindow()
        let picture = controller.feelStep.artwork
        let box = picture.scrollView
        let frameView = try XCTUnwrap(window.contentView?.superview)
        for (spot, point) in points(in: box) {
            let hit = try XCTUnwrap(frameView.hitTest(box.convert(point, to: nil)), spot)
            XCTAssertTrue(hit.isDescendant(of: box), "\(spot): the wheel goes to \(type(of: hit))")
            var view: NSView? = hit
            while let current = view, current !== box.superview {
                XCTAssertFalse(current.mouseDownCanMoveWindow, "\(spot): a press on \(type(of: current)) drags the window")
                view = current.superview
            }
        }
        // AppKit sends the wheel to the view under the pointer, which hands it to its scroll view.
        let middle = box.convert(NSPoint(x: box.bounds.midX, y: box.bounds.midY), to: nil)
        let hit = try XCTUnwrap(frameView.hitTest(middle))
        hit.scrollWheel(with: try scrollEvent(phase: 0, synthetic: false))
        XCTAssertTrue(picture.hasUserScrolled)
        XCTAssertTrue(picture.isDemoPaused)

        // A click in the box changes nothing of the guide.
        realClick(box, at: NSPoint(x: box.bounds.midX, y: box.bounds.midY), move: 2)
        XCTAssertEqual(controller.currentStep, .feel)
        XCTAssertEqual(chosenFeels(controller.feelStep), [.smooth])

        // The background and the text still move the window.
        let title = controller.feelStep.titleLabel!
        for view in [controller.pictureHost!, title] as [NSView] {
            let spot = view === title ? NSPoint(x: title.bounds.midX, y: title.bounds.midY) : NSPoint(x: 6, y: 6)
            let background = try XCTUnwrap(frameView.hitTest(view.convert(spot, to: nil)))
            XCTAssertTrue(background.mouseDownCanMoveWindow, "\(type(of: background)) no longer moves the window")
        }
    }

    /// Every other control of the guide, through real events: in the middle and near each
    /// edge, with a 2 pt move between down and up.
    func testEveryControlOfTheGuideTakesARealClick() throws {
        world.runAfterGrant = .running
        // Steps change by a crossfade: nothing under the pointer slides while it clicks.
        world.reduceMotion = true
        let controller = world.makeController(flow: .full)
        _ = makeEventWindow(for: controller)
        /// A push button is clicked on its bezel, anything else on its bounds.
        func spots(of control: NSControl) -> [(String, NSPoint)] {
            control.window?.contentView?.layoutSubtreeIfNeeded()
            let push = (control as? NSButton).flatMap { $0.isBordered && $0.bezelStyle == .push ? $0 : nil }
            return points(in: control, rect: push.map(bezel(of:)))
        }
        func clickEverywhere(_ control: NSControl, _ name: String, after: (String) -> Void) {
            for index in 0..<5 {
                let (spot, point) = spots(of: control)[index]
                assertTakesTheClick(control, at: point, "\(name), \(spot)")
                realClick(control, at: point, move: 2)
                after("\(name), \(spot)")
            }
        }

        // Continue and Back walk the steps.
        clickEverywhere(controller.primaryButton, "Continue") { spot in
            XCTAssertEqual(controller.currentStep, .access, spot)
            controller.go(by: -1)
            self.settle()
        }
        controller.go(by: 1)
        settle()
        clickEverywhere(controller.backButton, "Back") { spot in
            XCTAssertEqual(controller.currentStep, .welcome, spot)
            controller.go(by: 1)
            self.settle()
        }

        // Open Accessibility Settings, and "Having trouble?" (its help opens and closes).
        XCTAssertEqual(controller.currentStep, .access)
        realClick(controller.primaryButton, at: spots(of: controller.primaryButton)[1].1, move: 2)
        XCTAssertEqual(world.requests, 1)
        XCTAssertEqual(world.settingsOpened, 1)
        var helpShown = false
        clickEverywhere(controller.helpButton, "Having trouble?") { spot in
            helpShown.toggle()
            XCTAssertEqual(controller.isHelpShown, helpShown, spot)
        }

        // The help's own button, as its popover shows it.
        let help = WelcomeGuideHelpViewController(showInFinder: { self.world.reveals += 1 })
        let helpWindow = GuideEventWindow.make(size: help.view.frame.size)
        helpWindow.contentViewController = help
        helpWindow.putOutOfSight()
        addTeardownBlock {
            helpWindow.orderOut(nil)
            helpWindow.close()
        }
        clickEverywhere(help.finderButton, "Show Scrollio in Finder") { _ in }
        XCTAssertEqual(world.reveals, 5)

        // The feel step's switch.
        world.accessGranted = true
        controller.accessibilityPermissionsChecker(nil)
        controller.go(by: 1)
        settle()
        XCTAssertEqual(controller.currentStep, .feel)
        var reversed = world.scroll.reversesWheel
        clickEverywhere(controller.feelStep.reverseRow.toggle, "Reverse wheel direction") { spot in
            reversed.toggle()
            XCTAssertEqual(self.world.scroll.reversesWheel, reversed, spot)
            XCTAssertEqual(controller.feelStep.reverseRow.isOn, reversed, spot)
        }

        // The last step: Open at login, Done and Open Settings (which closes the window).
        controller.go(by: 1)
        settle()
        XCTAssertEqual(controller.currentStep, .finish)
        var opensAtLogin = controller.openAtLoginChoice
        clickEverywhere(controller.finishStep.loginRow.toggle, "Open at login") { spot in
            opensAtLogin.toggle()
            XCTAssertEqual(controller.openAtLoginChoice, opensAtLogin, spot)
        }
        for (spot, point) in spots(of: controller.primaryButton) {
            assertTakesTheClick(controller.primaryButton, at: point, "Done, \(spot)")
        }
        for (spot, point) in spots(of: controller.secondaryButton) {
            assertTakesTheClick(controller.secondaryButton, at: point, "Open Settings, \(spot)")
        }
        install(.notRegistered)
        realClick(controller.secondaryButton, at: spots(of: controller.secondaryButton)[2].1, move: 2)
        XCTAssertEqual(world.appSettingsOpened, 1)
        XCTAssertTrue(world.progress.isFinished)
    }

    // MARK: - The wheel direction

    func testTheFeelStepShowsAndFlipsTheWheelDirectionAsTheScrollingPaneDoes() throws {
        let controller = makeFeelController()
        let step = controller.feelStep
        let row = try XCTUnwrap(step.reverseRow)
        XCTAssertEqual(row.title, "Reverse wheel direction")
        XCTAssertEqual(row.explanation, "Flips the wheel's direction, not the trackpad's.")
        XCTAssertEqual(row.toggle.accessibilityLabel(), "Reverse wheel direction", "VoiceOver names the switch")
        XCTAssertEqual(row.toggle.accessibilityHelp(), "Flips the wheel's direction, not the trackpad's.")
        XCTAssertTrue(row.isOn, "the stored value: the default reverses")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        func stored() throws -> NSDictionary {
            let all = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(world.scroll)) as? [String: Any])
            return all.filter { !$0.key.hasPrefix("reverse") } as NSDictionary
        }
        let others = try stored()

        // Off clears the main flag only (the pane's `reversesWheel`).
        row.toggle.state = .off
        XCTAssertTrue(row.toggle.sendAction(row.toggle.action, to: row.toggle.target))
        XCTAssertFalse(world.scroll.reverse)
        XCTAssertTrue(world.scroll.reverseVertical)
        XCTAssertTrue(world.scroll.reverseHorizontal)
        XCTAssertFalse(row.isOn)

        // Either axis reversed counts as on; on turns everything on.
        world.scroll.reverse = true
        world.scroll.reverseVertical = false
        step.refresh()
        XCTAssertTrue(row.isOn, "the horizontal axis is still reversed")
        world.scroll.reverseHorizontal = false
        step.refresh()
        XCTAssertFalse(row.isOn)
        row.toggle.state = .on
        XCTAssertTrue(row.toggle.sendAction(row.toggle.action, to: row.toggle.target))
        XCTAssertTrue(world.scroll.reverse && world.scroll.reverseVertical && world.scroll.reverseHorizontal)
        XCTAssertEqual(try stored(), others, "nothing but the direction changed")
    }

    /// The engine reads `Options.shared.scroll` at every wheel event: the switch writes there,
    /// through the live seam, and reads it again each time (nothing is kept aside).
    func testTheDirectionGoesToTheOptionsTheEngineReads() {
        Options.shared.scroll = OPTIONS_SCROLL_DEFAULT()
        world.accessGranted = true
        world.run = .running
        let controller = world.makeController(flow: .full)
        controller.scrollOptions = { Options.shared.scroll }
        controller.go(by: 1)
        let step = controller.feelStep
        step.setReversesWheel(false)
        XCTAssertFalse(Options.shared.scroll.reverse)
        let replaced = OPTIONS_SCROLL_DEFAULT()
        Options.shared.scroll = replaced
        step.refresh()
        XCTAssertTrue(step.reverseRow.isOn, "the options as they are now")
        step.setReversesWheel(false)
        XCTAssertFalse(replaced.reverse)
    }

    // MARK: - Open at login

    /// Walks a new user (the guide still to do, Scrollio running) to the last step.
    private func makeFinishController(finished: Bool = false) -> IntroductionViewController {
        world.accessGranted = true
        world.run = .running
        let controller = world.makeController(flow: .full, finished: finished)
        controller.go(by: 2)
        XCTAssertEqual(controller.currentStep, .finish)
        return controller
    }

    func testANewUserLeavesWithOpenAtLoginOnAndNothingIsRegisteredBefore() throws {
        let fake = install(.notRegistered)
        let controller = makeFinishController()
        let window = makeWindow(for: controller)
        let row = try XCTUnwrap(controller.finishStep.loginRow)
        XCTAssertEqual(row.title, "Open at login")
        XCTAssertEqual(row.explanation, "Scrollio starts when you log in to your Mac.")
        XCTAssertEqual(row.toggle.accessibilityLabel(), "Open at login", "VoiceOver names the switch")
        XCTAssertTrue(row.isOn, "on for a new user")
        XCTAssertEqual(fake.calls, 0, "showing the step registers nothing")

        // Back and again: still nothing; the window closed on another step: nothing.
        click(controller.backButton)
        controller.windowWillClose()
        XCTAssertEqual(fake.calls, 0)
        click(controller.primaryButton)
        XCTAssertTrue(controller.finishStep.loginRow.isOn)
        XCTAssertEqual(fake.calls, 0)

        let closed = expectation(forNotification: NSWindow.willCloseNotification, object: window)
        click(controller.primaryButton)
        wait(for: [closed], timeout: 1)
        XCTAssertEqual(fake.registerCalls, 1, "Done registers")
        XCTAssertTrue(Options.shared.general.autoLaunch)
        XCTAssertTrue(world.progress.isFinished)
    }

    func testANewUserCanLeaveItOff() {
        let fake = install(.notRegistered)
        let controller = makeFinishController()
        let row = controller.finishStep.loginRow!
        row.toggle.state = .off
        XCTAssertTrue(row.toggle.sendAction(row.toggle.action, to: row.toggle.target))
        XCTAssertEqual(fake.calls, 0, "the switch alone changes nothing")
        click(controller.primaryButton)
        XCTAssertEqual(fake.calls, 0, "off and not registered: nothing to do")
    }

    func testByHandItShowsTheSystemAndAnUntouchedSwitchChangesNothing() {
        let enabled = install(.enabled)
        var controller = makeFinishController(finished: true)
        XCTAssertTrue(controller.finishStep.loginRow.isOn)
        click(controller.primaryButton)
        XCTAssertEqual(enabled.calls, 0)

        let off = install(.notRegistered)
        controller = makeFinishController(finished: true)
        XCTAssertFalse(controller.finishStep.loginRow.isOn)
        click(controller.secondaryButton)
        XCTAssertEqual(off.calls, 0)
        XCTAssertEqual(world.appSettingsOpened, 1)
    }

    func testTurningItOffRemovesTheRegistrationWhenLeavingWithOpenSettings() {
        let fake = install(.enabled)
        let controller = makeFinishController(finished: true)
        let row = controller.finishStep.loginRow!
        row.toggle.state = .off
        XCTAssertTrue(row.toggle.sendAction(row.toggle.action, to: row.toggle.target))
        XCTAssertEqual(fake.calls, 0)
        click(controller.secondaryButton)
        XCTAssertEqual(fake.unregisterCalls, 1)
        XCTAssertEqual(fake.registerCalls, 0)
        XCTAssertFalse(Options.shared.general.autoLaunch)
        XCTAssertEqual(world.appSettingsOpened, 1)
    }

    /// As General: an item waiting for approval reads as off and says so; left alone it is
    /// kept; turned on, registering cannot enable it and Login Items opens.
    func testWaitingForApprovalIsGeneralsFlow() {
        let fake = install(.requiresApproval)
        fake.afterRegister = nil
        let controller = makeFinishController(finished: true)
        let row = controller.finishStep.loginRow!
        XCTAssertFalse(row.isOn)
        XCTAssertEqual(row.explanation, "Waiting for your approval in System Settings.")
        click(controller.primaryButton)
        XCTAssertEqual(fake.calls, 0, "an untouched switch keeps the waiting registration")

        controller.begin(.full)
        controller.go(by: 2)
        row.toggle.state = .on
        XCTAssertTrue(row.toggle.sendAction(row.toggle.action, to: row.toggle.target))
        click(controller.primaryButton)
        XCTAssertEqual(fake.registerCalls, 1)
        XCTAssertEqual(fake.openSettingsCalls, 1, "System Settings opens on Login Items")
        XCTAssertFalse(Options.shared.general.autoLaunch, "not on until approved")
    }

    func testAFailedRegistrationStillFinishesTheGuideAndTheOptionTellsTheTruth() {
        let fake = install(.notRegistered)
        fake.afterRegister = nil
        let controller = makeFinishController()
        let window = makeWindow(for: controller)
        let closed = expectation(forNotification: NSWindow.willCloseNotification, object: window)
        click(controller.primaryButton)
        wait(for: [closed], timeout: 1)
        XCTAssertEqual(fake.registerCalls, 1)
        XCTAssertTrue(world.progress.isFinished)
        XCTAssertFalse(Options.shared.general.autoLaunch, "General's switch shows it off")
    }

    func testTheAccessStepAloneLeavesTheLoginItemAlone() {
        let fake = install(.notRegistered)
        world.runAfterGrant = .running
        let controller = world.makeController(flow: .accessOnly, finished: false)
        world.accessGranted = true
        controller.accessibilityPermissionsChecker(nil)
        click(controller.primaryButton)
        XCTAssertEqual(fake.calls, 0)
    }

    // MARK: - The last step

    func testDoneMarksTheGuideFinishedAndCloses() {
        world.accessGranted = true
        world.run = .running
        let controller = world.makeController(flow: .full)
        let window = makeWindow(for: controller)
        click(controller.primaryButton)
        click(controller.primaryButton)
        XCTAssertEqual(controller.currentStep, .finish)
        XCTAssertEqual(controller.finishStep.titleLabel.stringValue, "Scrollio is ready")
        XCTAssertEqual(controller.finishStep.textLabel.stringValue, "It runs in the menu bar. Click its icon to open Settings or pause Scrollio.")
        XCTAssertFalse(world.progress.isFinished)
        let closed = expectation(forNotification: NSWindow.willCloseNotification, object: window)
        click(controller.primaryButton)
        wait(for: [closed], timeout: 1)
        XCTAssertTrue(world.progress.isFinished)
        XCTAssertEqual(world.appSettingsOpened, 0)
    }

    func testOpenSettingsOpensThePreferencesThenCloses() {
        world.accessGranted = true
        world.run = .running
        let controller = world.makeController(flow: .full)
        let window = makeWindow(for: controller)
        click(controller.primaryButton)
        click(controller.primaryButton)
        let closed = expectation(forNotification: NSWindow.willCloseNotification, object: window)
        click(controller.secondaryButton)
        wait(for: [closed], timeout: 1)
        XCTAssertEqual(world.appSettingsOpened, 1)
        XCTAssertTrue(world.progress.isFinished)
    }

    /// "Having trouble?": the help in its popover is written in the label colour (the muted
    /// one of a line under a title was too faint to read there), and the link that opens it
    /// is in the accent colour.
    func testTheHelpIsWrittenInTheLabelColour() throws {
        let help = WelcomeGuideHelpViewController(showInFinder: {})
        _ = help.view
        XCTAssertEqual(help.textLabel.textColor, .labelColor)
        XCTAssertEqual(help.headingLabel.textColor, .labelColor)
        let controller = world.makeController(flow: .full)
        _ = controller.view
        let link = try XCTUnwrap(controller.accessStep.helpButton)
        XCTAssertEqual(link.attributedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .controlAccentColor)
    }

    /// The buttons of the last step stand clear of the step dots in the middle of the bar:
    /// a longer title for "Open Settings" ("Open Scrollio Settings") ran into them.
    func testTheLastStepsButtonsStandClearOfTheDots() {
        world.accessGranted = true
        world.run = .running
        let controller = world.makeController(flow: .full)
        _ = makeWindow(for: controller)
        click(controller.primaryButton)
        click(controller.primaryButton)
        XCTAssertEqual(controller.currentStep, .finish)
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertFalse(controller.secondaryButton.isHidden)
        XCTAssertGreaterThanOrEqual(controller.secondaryButton.frame.minX - controller.dots.frame.maxX, 8, "Open Settings and the dots")
        XCTAssertGreaterThanOrEqual(controller.dots.frame.minX - controller.backButton.frame.maxX, 8, "Back and the dots")
        XCTAssertLessThanOrEqual(controller.secondaryButton.frame.maxX, controller.primaryButton.frame.minX)
    }

    func testTheLastStepNamesTheHiddenIconWay() {
        world.menuBarIconHidden = true
        world.accessGranted = true
        world.run = .running
        let controller = world.makeController(flow: .full)
        click(controller.primaryButton)
        click(controller.primaryButton)
        let step = controller.finishStep
        XCTAssertEqual(
            step.textLabel.stringValue,
            "Scrollio is running, but its menu bar icon is hidden. To reach Settings, open Scrollio again."
        )
        // The picture shows no icon and no menu either.
        XCTAssertTrue(step.artwork.isIconHidden)
        XCTAssertEqual(step.artwork.accessibilityLabel(), "The menu bar, with an empty place where Scrollio's icon would be.")

        XCTAssertEqual(step.titleLabel.stringValue, "Scrollio is ready")

        // Paused, it does not say that Scrollio runs: not in the text, and not in the title
        // ("Scrollio is ready" stood over a text that only said where the icon is).
        world.run = .paused
        step.refresh()
        XCTAssertEqual(step.titleLabel.stringValue, "Scrollio is paused")
        XCTAssertEqual(step.textLabel.stringValue, "Scrollio's menu bar icon is hidden. To reach Settings, open Scrollio again.")
        XCTAssertEqual(WelcomeGuideFinishStep.titleKey(iconHidden: true, paused: true), "intro-finish-title-hidden-icon-paused")
        for (hidden, paused) in [(false, false), (false, true), (true, false)] {
            XCTAssertEqual(WelcomeGuideFinishStep.titleKey(iconHidden: hidden, paused: paused), "intro-finish-title", "\(hidden) \(paused)")
        }

        world.menuBarIconHidden = false
        step.refresh()
        XCTAssertFalse(step.artwork.isIconHidden)
        XCTAssertEqual(step.titleLabel.stringValue, "Scrollio is ready", "the icon and its menu are there to resume")
        XCTAssertEqual(step.textLabel.stringValue, "It runs in the menu bar. Click its icon to open Settings or pause Scrollio.")
        XCTAssertEqual(step.artwork.accessibilityLabel(), "The menu bar with Scrollio's icon and its menu open.")
    }

    func testClosingTheWindowFinishesTheGuideOnlyWithTheAccess() {
        let controller = world.makeController(flow: .full)
        controller.windowWillClose()
        XCTAssertFalse(world.progress.isFinished, "without the access it comes back at the next launch")
        world.accessGranted = true
        controller.windowWillClose()
        XCTAssertTrue(world.progress.isFinished)
    }

    func testTheMenuInThePictureIsTheStatusMenus() {
        let titles = WelcomeGuideFinishPicture.menuItems.compactMap { $0?.title }
        XCTAssertEqual(titles, ["Pause Scrollio", "Settings…", "Quit Scrollio"])
        XCTAssertNotNil(NSImage(named: "AppStatusBarIcon"))
        let still = WelcomeGuideFinishPicture.stillFrame
        XCTAssertEqual(still.menu, 1)
        XCTAssertTrue(still.iconSelected)
        XCTAssertEqual(still.rings, [0, 0], "no rings with Reduce Motion")
        let frame = WelcomeGuideFinishPicture.frame(at: 0.5)
        XCTAssertGreaterThan(frame.rings[0], 0)
        XCTAssertEqual(frame.menu, 0)
        XCTAssertEqual(WelcomeGuideFinishPicture.frame(at: 3).menu, 1)
    }

    // MARK: - The pictures

    func testTheWelcomeMouseLightsOnePartAfterTheOther() {
        let controller = world.makeController()
        let picture = controller.welcomeStep.artwork
        picture.model = .mxMaster4
        XCTAssertEqual(picture.phaseCount, 3)
        XCTAssertEqual(picture.frame(at: 0.5).phase, 0)
        XCTAssertGreaterThan(picture.frame(at: 0.7).wheelTurn, 0)
        XCTAssertEqual(picture.frame(at: 2.4).phase, 1)
        XCTAssertEqual(picture.frame(at: 2.4).pressed, [.forward])
        XCTAssertEqual(picture.frame(at: 4.8).phase, 2)
        XCTAssertLessThan(picture.frame(at: 4.8).slide, 0)
        XCTAssertEqual(picture.frame(at: 6.5).phase, 0, "a 6 s loop")
        // The features follow the lit part.
        picture.show(time: 2.4)
        XCTAssertEqual(controller.welcomeStep.features.map(\.isHighlighted), [false, true, false])

        // A mouse without a gesture button: two parts, a 4 s loop.
        picture.model = .generic
        XCTAssertEqual(picture.phaseCount, 2)
        XCTAssertEqual(picture.frame(at: 4.5).phase, 0)

        // Reduce Motion: everything lit, nothing boxed.
        picture.showStill()
        XCTAssertNil(picture.shownFrame.phase)
        XCTAssertEqual(controller.welcomeStep.features.map(\.isHighlighted), [false, false, false])
    }

    func testTheWelcomeStepFollowsTheConnectedMouse() {
        world.mouse = .mxMaster3
        let controller = world.makeController()
        XCTAssertEqual(controller.welcomeStep.artwork.model, .mxMaster3)
        world.mouse = .mxMaster4
        controller.welcomeStep.reloadMouse()
        XCTAssertEqual(controller.welcomeStep.artwork.model, .mxMaster4)
        XCTAssertEqual(controller.welcomeStep.features.map(\.model), [.mxMaster4, .mxMaster4, .mxMaster4])
    }

    func testTheSwitchLoopAndItsStills() {
        let target = WelcomeGuideAccessPicture.pointerTarget
        let early = WelcomeGuideAccessPicture.frame(at: 0.2)
        XCTAssertEqual(early.pointerAlpha, 0)
        XCTAssertEqual(early.switchOn, 0)
        let arrived = WelcomeGuideAccessPicture.frame(at: 1.35)
        XCTAssertEqual(arrived.pointer.x, target.x, accuracy: 2)
        XCTAssertEqual(arrived.pointer.y, target.y, accuracy: 2)
        XCTAssertEqual(WelcomeGuideAccessPicture.frame(at: 2.5).switchOn, 1)
        XCTAssertEqual(WelcomeGuideAccessPicture.frame(at: 4.0).switchOn, 0)
        // The pointer's target is Scrollio's switch, inside the picture.
        XCTAssertTrue(WelcomeGuideAccessPicture.switchRect(inRow: 1).insetBy(dx: -3, dy: -3).contains(target))

        world.reduceMotion = true
        let controller = makeAccessController()
        let picture = controller.accessStep.artwork
        picture.updateClock()
        XCTAssertTrue(picture.shownFrame.ring, "Reduce Motion: a still ring round the switch")
        XCTAssertEqual(picture.shownFrame.pointerAlpha, 0)
        picture.isAllowed = true
        XCTAssertEqual(picture.shownFrame.switchOn, 1)
        XCTAssertFalse(picture.shownFrame.ring)
    }

    func testEveryPictureAndControlHasALabel() {
        world.runAfterGrant = .running
        let controller = world.makeController()
        XCTAssertEqual(controller.welcomeStep.artwork.accessibilityRole(), .image)
        XCTAssertFalse(controller.welcomeStep.artwork.accessibilityLabel()?.isEmpty ?? true)
        XCTAssertEqual(controller.accessStep.artwork.accessibilityRole(), .image)
        XCTAssertTrue(controller.accessStep.artwork.accessibilityLabel()?.contains("Scrollio") ?? false)
        XCTAssertEqual(controller.finishStep.artwork.accessibilityRole(), .image)
        XCTAssertFalse(controller.finishStep.artwork.accessibilityLabel()?.isEmpty ?? true)
        XCTAssertFalse(controller.welcomeStep.iconView.isAccessibilityElement(), "decoration: the title names the app")
        for feature in controller.welcomeStep.features {
            XCTAssertEqual(feature.accessibilityLabel(), feature.titleLabel.stringValue + ", " + feature.detailLabel.stringValue)
        }
        XCTAssertFalse(controller.accessStep.statusBox.accessibilityLabel()?.isEmpty ?? true)
        for step in WelcomeGuideStep.allCases {
            let content = controller.stepView(for: step).content
            for button in allSubviews(of: content).compactMap({ $0 as? NSButton }) {
                XCTAssertFalse((button.accessibilityLabel() ?? button.title).isEmpty, "\(step): a button without a name")
            }
        }
    }

    // MARK: - The window

    /// Every step and state the guide can show.
    private func controllersInEveryState() -> [(String, IntroductionViewController)] {
        var result: [(String, IntroductionViewController)] = []
        let welcome = GuideWorld()
        welcome.mouse = .mxMaster4
        result.append(("welcome", welcome.makeController()))
        for (name, granted, run) in [("waiting", false, WelcomeGuideRunState.stopped), ("allowed", true, .running),
                                     ("could not start", true, .retrying), ("starting", true, .stopped), ("paused", true, .paused)] {
            let access = GuideWorld()
            access.accessGranted = granted
            access.run = run
            let controller = access.makeController(flow: .accessOnly, finished: true)
            result.append((name, controller))
        }
        let help = GuideWorld()
        help.menuBarIconHidden = true
        help.accessGranted = true
        help.run = .running
        let feel = help.makeController(flow: .full)
        feel.go(by: 1)
        result.append(("feel", feel))
        let finish = help.makeController(flow: .full)
        finish.go(by: 2)
        result.append(("finish", finish))
        addTeardownBlock {
            welcome.tearDown()
            help.tearDown()
        }
        return result
    }

    func testTheWindowNeverChangesItsSizeBetweenSteps() {
        world.runAfterGrant = .running
        let controller = world.makeController()
        let window = makeWindow(for: controller)
        let size = window.frame.size
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).size, WelcomeGuideLayout.windowSize)
        click(controller.primaryButton)
        click(controller.helpButton)
        world.accessGranted = true
        controller.accessibilityPermissionsChecker(nil)
        click(controller.primaryButton)
        click(controller.feelButtonsFloat)
        click(controller.primaryButton)
        click(controller.backButton)
        XCTAssertEqual(window.frame.size, size)
        XCTAssertEqual(controller.view.frame.size, WelcomeGuideLayout.windowSize)
        XCTAssertFalse(window.isVisible)
    }

    func testNothingIsCutOffAndEverythingSitsInItsArea() {
        for (name, controller) in controllersInEveryState() {
            let view = controller.view
            XCTAssertEqual(view.frame.size, WelcomeGuideLayout.windowSize, name)
            view.layoutSubtreeIfNeeded()
            let content = controller.contentHost!
            for field in allSubviews(of: content).compactMap({ $0 as? NSTextField }).filter(isShown) {
                guard let cell = field.cell, !field.stringValue.isEmpty else { continue }
                let needed = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: field.bounds.width, height: .greatestFiniteMagnitude))
                XCTAssertLessThanOrEqual(needed.height, field.bounds.height + 0.5, "\(name): \"\(field.stringValue)\" is cut off")
                XCTAssertLessThanOrEqual(needed.width, field.bounds.width + 0.5, "\(name): \"\(field.stringValue)\" is cut off")
                let frame = content.convert(field.bounds, from: field)
                XCTAssertTrue(content.bounds.insetBy(dx: 23.5, dy: -0.5).contains(frame), "\(name): \"\(field.stringValue)\" at \(frame)")
            }
            for button in allSubviews(of: view).compactMap({ $0 as? NSButton }).filter(isShown) where !(button is WelcomeGuideFeelButton) {
                XCTAssertGreaterThanOrEqual(button.frame.width, button.intrinsicContentSize.width - 0.5, "\(name): \(button.title)")
            }
            // The bar's buttons stay on the bar, inside the margins.
            for button in [controller.backButton!, controller.primaryButton!, controller.secondaryButton!] where isShown(button) {
                let frame = view.convert(button.bounds, from: button)
                XCTAssertGreaterThanOrEqual(frame.minX, 23.5, "\(name): \(button.title)")
                XCTAssertLessThanOrEqual(frame.maxX, view.bounds.width - 23.5, "\(name): \(button.title)")
            }
        }
    }

    func testTypeSizesAndColoursFollowTheSystem() {
        let controller = world.makeController()
        XCTAssertEqual(controller.welcomeStep.titleLabel.font?.pointSize, 22)
        XCTAssertEqual(controller.welcomeStep.textLabel.font?.pointSize, NSFont.systemFontSize)
        XCTAssertEqual(controller.accessStep.statusBox.detailLabel.font?.pointSize, PreferencesForm.hintFontSize)
        for step in WelcomeGuideStep.allCases {
            for field in allSubviews(of: controller.stepView(for: step).content).compactMap({ $0 as? NSTextField }) {
                XCTAssertGreaterThanOrEqual(field.font?.pointSize ?? 0, NSFont.smallSystemFontSize, field.stringValue)
                XCTAssertEqual(field.textColor?.type, .catalog, "\(field.stringValue): a fixed colour")
            }
        }
        XCTAssertNil(controller.view.appearance, "no fixed light or dark appearance")
        XCTAssertTrue(controller.view is PreferencesBackgroundView, "the background of the Settings panes")
    }

    // MARK: - The storyboard shell

    func testTheStoryboardWindowIsAShellAroundTheCodeBuiltView() throws {
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: IntroductionViewController.self))
        let windowController = try XCTUnwrap(
            storyboard.instantiateController(withIdentifier: WINDOW_IDENTIFIER.introductionWindowController) as? IntroductionWindowController
        )
        // Loading the storyboard builds the view with the live seams: under XCTest the stored
        // progress is never read (`WelcomeGuideProgress.live` has no store), so the guide counts
        // as finished and the app's own run is the Accessibility step alone.
        let controller = try XCTUnwrap(windowController.contentViewController as? IntroductionViewController)
        let window = try XCTUnwrap(windowController.window)
        addTeardownBlock { windowController.close() }

        XCTAssertEqual(window.title, "Welcome to Scrollio")
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertTrue(window.styleMask.contains(.closable))
        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertFalse(window.styleMask.contains(.resizable), "one fixed size")
        XCTAssertTrue(window.delegate === windowController)
        XCTAssertFalse(windowController.shouldCascadeWindows)
        XCTAssertTrue(window.autorecalculatesKeyViewLoop, "Tab reaches every control")
        XCTAssertTrue(window.isMovableByWindowBackground, "it moves by its background; the controls say they do not")
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).size, WelcomeGuideLayout.windowSize)
        XCTAssertFalse(window.isVisible)
        XCTAssertNil(controller.accessibilityPermissionsCheckerTimer)
        XCTAssertTrue(WelcomeGuideProgress.live.isFinished)
        XCTAssertEqual(controller.flow, IntroductionWindowController.flow(for: .automatic, progress: .live))
        XCTAssertEqual(controller.flow, .accessOnly)
    }

    func testNothingOfTheOldWindowIsLeft() {
        let controller = world.makeController()
        var texts: [String] = []
        for step in WelcomeGuideStep.allCases {
            let content = controller.stepView(for: step).content
            texts += allSubviews(of: content).compactMap { ($0 as? NSTextField)?.stringValue }
        }
        for old in ["Introducing", "Allow Access ", "Not effective", "Authorized", "Open the Accessibility settings", "Step 1:"] {
            XCTAssertFalse(texts.contains { $0.localizedCaseInsensitiveContains(old) }, old)
        }
        for key in ["intro-access-heading", "intro-step-open-settings", "intro-step-accessibility", "intro-status-missing"] {
            XCTAssertEqual(NSLocalizedString(key, comment: ""), key, "\(key) is still in the catalog")
        }
        for name in ["manual-remove", "drag-arrow", "sparkle"] {
            XCTAssertNil(NSImage(named: name), "the picture \(name) is still in the bundle")
        }
    }
}

private extension IntroductionViewController {
    var feelButtonsFloat: NSButton {
        return feelStep.feelButtons[ScrollFeel.float.rawValue]
    }
}

/// A window AppKit delivers synthesized mouse and key events to as it does to the guide's
/// own. AppKit hands a mouse-down only to a window that is ordered in, so this one is, but
/// nothing of it can be seen or reached: it lies far off every display (it may: its frame
/// is not moved onto a screen), is fully transparent and lets the real mouse through. It
/// never becomes key or main, so every click is the first click into a window that is not
/// key, and it never touches the frontmost app.
private final class GuideEventWindow: NSWindow {

    static func make(size: NSSize) -> GuideEventWindow {
        let window = GuideEventWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.hasShadow = false
        return window
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }

    override var canBecomeKey: Bool { return false }
    override var canBecomeMain: Bool { return false }

    func putOutOfSight() {
        alphaValue = 0
        ignoresMouseEvents = true
        setFrameOrigin(NSPoint(x: -30_000, y: -30_000))
        orderBack(nil)
    }
}

private extension WelcomeGuideAccessState {
    static var allReady: [WelcomeGuideAccessState] {
        return [WelcomeGuideAccessState.missing, .starting, .running, .paused, .couldNotStart].filter(\.isReady)
    }
}

// MARK: - Renders

/// Draws every step of the Welcome Guide off screen, light and dark, the way the window
/// shows it (the window's appearance, the window colour standing in for the materials,
/// which draw nothing off screen). The animated pictures are drawn at a fixed moment of
/// their loop, or as their Reduce Motion still. The accent colour of the drawings is the
/// app's own purple (`ForcedAppAccent`, PreferencesWindowRenderTests). Only runs when asked to:
/// `TEST_RUNNER_SCROLLIO_SHOTS_DIR=<folder> xcodebuild … test -only-testing:ScrollioTests/WelcomeGuideRenderTests`.
final class WelcomeGuideRenderTests: XCTestCase {

    private var directory: URL!
    private var worlds: [GuideWorld] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = try RenderShots.directory(for: "the Welcome Guide")
        // The drawings in the app's own purple, whatever accent this Mac's user chose.
        try ForcedAppAccent.install()
    }

    override func tearDown() {
        ForcedAppAccent.uninstall()
        worlds.forEach { $0.tearDown() }
        worlds = []
        super.tearDown()
    }

    /// A guide in a window of its own (never shown) in `appearance`, prepared by `prepare`.
    private func render(
        _ name: String,
        configure: (GuideWorld) -> Void = { _ in },
        flow: WelcomeGuideFlow = .full,
        finished: Bool = false,
        prepare: (IntroductionViewController, GuideWorld) -> Void
    ) throws {
        for (suffix, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let world = GuideWorld()
            worlds.append(world)
            configure(world)
            let controller = world.makeController(flow: flow, finished: finished)
            let window = RenderGuideWindow(
                contentRect: NSRect(origin: .zero, size: WelcomeGuideLayout.windowSize),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: true
            )
            window.isReleasedWhenClosed = false
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.appearance = NSAppearance(named: appearanceName)
            window.contentViewController = controller
            addTeardownBlock { window.close() }
            prepare(controller, world)
            let content = try XCTUnwrap(window.contentView)
            content.layoutSubtreeIfNeeded()
            let frameView = content.superview ?? content
            frameView.layoutSubtreeIfNeeded()
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            // AppKit draws the keyboard focus ring on screen only: it is drawn here as it would be.
            try write(frameView, rect: frameView.convert(content.bounds, from: content), appearance: appearance,
                      focused: window.firstResponder as? WelcomeGuideFeelButton,
                      to: directory.appendingPathComponent("\(name)-\(suffix).png"))
        }
    }

    private func toStep(_ step: WelcomeGuideStep, in controller: IntroductionViewController) {
        guard let target = controller.steps.firstIndex(of: step) else { return XCTFail("no \(step) step") }
        controller.go(by: target - controller.index)
    }

    func testRenderWelcome() throws {
        try render("guide-1-welcome-mx-master-4", configure: { $0.mouse = .mxMaster4 }) { controller, _ in
            controller.welcomeStep.artwork.show(time: 0.62)
        }
        try render("guide-1-welcome-generic", configure: { $0.mouse = .generic }) { controller, _ in
            controller.welcomeStep.artwork.show(time: 2.42)
        }
        try render("guide-1-welcome-mx-master-3-gesture", configure: { $0.mouse = .mxMaster3 }) { controller, _ in
            controller.welcomeStep.artwork.show(time: 4.8)
        }
        try render("guide-1-welcome-reduce-motion", configure: { $0.mouse = .mxMaster4; $0.reduceMotion = true }) { controller, _ in
            controller.welcomeStep.artwork.showStill()
        }
    }

    func testRenderAccess() throws {
        try render("guide-2-access-todo") { controller, _ in
            self.toStep(.access, in: controller)
            controller.accessStep.artwork.show(time: 1.1)
        }
        try render("guide-2-access-waiting") { controller, _ in
            self.toStep(.access, in: controller)
            controller.primaryButtonClicked(nil)
            controller.accessStep.artwork.show(time: 1.1)
        }
        try render("guide-2-access-waiting-switch-on") { controller, _ in
            self.toStep(.access, in: controller)
            controller.primaryButtonClicked(nil)
            controller.accessStep.artwork.show(time: 2.2)
        }
        try render("guide-2-access-allowed", configure: { $0.runAfterGrant = .running }) { controller, world in
            self.toStep(.access, in: controller)
            world.accessGranted = true
            controller.accessibilityPermissionsChecker(nil)
        }
        try render("guide-2-access-could-not-start", configure: { $0.runAfterGrant = .retrying }) { controller, world in
            self.toStep(.access, in: controller)
            world.accessGranted = true
            controller.accessibilityPermissionsChecker(nil)
        }
        try render("guide-2-access-reduce-motion", configure: { $0.reduceMotion = true }) { controller, _ in
            self.toStep(.access, in: controller)
            controller.accessStep.artwork.updateClock()
        }
        try render("guide-2-access-only-waiting", flow: .accessOnly, finished: true) { controller, _ in
            controller.accessStep.artwork.show(time: 1.1)
        }
        try render("guide-2-access-only-allowed", configure: { $0.runAfterGrant = .running }, flow: .accessOnly, finished: true) { controller, world in
            world.accessGranted = true
            controller.accessibilityPermissionsChecker(nil)
        }
        // The help, in its popover's material.
        for (suffix, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            let help = WelcomeGuideHelpViewController(showInFinder: {})
            let view = help.view
            let outer = NSView(frame: view.frame)
            outer.appearance = appearance
            let material = NSVisualEffectView(frame: view.frame)
            material.material = .popover
            outer.addSubview(material)
            material.addSubview(view)
            view.setFrameOrigin(.zero)
            view.layoutSubtreeIfNeeded()
            try write(outer, appearance: appearance, to: directory.appendingPathComponent("guide-2-access-help-\(suffix).png"))
        }
    }

    func testRenderFeel() throws {
        for feel in [ScrollFeel.direct, .smooth, .float] {
            try render("guide-3-feel-\(feel.name)", configure: { $0.accessGranted = true; $0.run = .running }) { controller, world in
                self.toStep(.feel, in: controller)
                controller.feelStep.choose(feel)
                controller.feelStep.artwork.show(time: 0.75)
                XCTAssertEqual(world.scroll.duration, feel.duration)
            }
        }
        // Glide held down (Smooth chosen), and Quick focused from the keyboard.
        try render("guide-3-feel-pressed", configure: { $0.accessGranted = true; $0.run = .running }) { controller, _ in
            self.toStep(.feel, in: controller)
            controller.feelStep.feelButtons[ScrollFeel.glide.rawValue].isHighlighted = true
            controller.feelStep.artwork.show(time: 0.75)
        }
        try render("guide-3-feel-focused", configure: { $0.accessGranted = true; $0.run = .running }) { controller, _ in
            self.toStep(.feel, in: controller)
            let quick = controller.feelStep.feelButtons[ScrollFeel.quick.rawValue]
            quick.choose()
            XCTAssertTrue(quick.window?.makeFirstResponder(quick) ?? false)
            controller.feelStep.artwork.show(time: 0.75)
        }
        try render("guide-3-feel-reversed-off", configure: {
            $0.accessGranted = true
            $0.run = .running
            $0.scroll.reverse = false
        }) { controller, _ in
            self.toStep(.feel, in: controller)
            controller.feelStep.artwork.show(time: 0.75)
        }
        try render("guide-3-feel-not-in-list", configure: {
            $0.accessGranted = true
            $0.run = .running
            $0.tryArea = .notInAppList
        }) { controller, _ in
            self.toStep(.feel, in: controller)
            controller.feelStep.artwork.show(time: 0.75)
        }
        try render("guide-3-feel-custom-not-running", configure: {
            $0.accessGranted = true
            $0.run = .paused
            $0.tryArea = .notRunning
            $0.scroll.duration = 3.4
        }) { controller, _ in
            self.toStep(.feel, in: controller)
        }
    }

    func testRenderFinish() throws {
        try render("guide-4-finish", configure: { $0.accessGranted = true; $0.run = .running }) { controller, _ in
            self.toStep(.finish, in: controller)
            controller.finishStep.artwork.show(time: 3)
        }
        try render("guide-4-finish-pulse", configure: { $0.accessGranted = true; $0.run = .running }) { controller, _ in
            self.toStep(.finish, in: controller)
            controller.finishStep.artwork.show(time: 0.75)
        }
        try render("guide-4-finish-login-on", configure: { $0.accessGranted = true; $0.run = .running }) { controller, _ in
            self.toStep(.finish, in: controller)
            controller.finishStep.artwork.showStill()
            XCTAssertTrue(controller.finishStep.loginRow.isOn)
        }
        try render("guide-4-finish-login-off", configure: { $0.accessGranted = true; $0.run = .running },
                   finished: true) { controller, _ in
            self.toStep(.finish, in: controller)
            controller.finishStep.artwork.showStill()
            XCTAssertFalse(controller.finishStep.loginRow.isOn)
        }
        try render("guide-4-finish-hidden-icon", configure: {
            $0.accessGranted = true
            $0.run = .running
            $0.menuBarIconHidden = true
        }) { controller, _ in
            self.toStep(.finish, in: controller)
            controller.finishStep.artwork.show(time: 0.75)
        }
        try render("guide-4-finish-hidden-icon-paused", configure: {
            $0.accessGranted = true
            $0.run = .paused
            $0.menuBarIconHidden = true
        }) { controller, _ in
            self.toStep(.finish, in: controller)
            controller.finishStep.artwork.showStill()
        }
    }

    /// The README's picture (`readme-welcome-guide-<appearance>.png`, copied by hand to
    /// `assets/readme/`): the feel step with an MX Master 4, Smooth chosen. Rendered with
    /// the README's other pictures (`PreferencesWindowRenderTests.testRenderReadmePictures`).
    func testRenderReadmePicture() throws {
        try render("readme-welcome-guide", configure: {
            $0.accessGranted = true
            $0.run = .running
            $0.mouse = .mxMaster4
        }) { controller, _ in
            self.toStep(.feel, in: controller)
            controller.feelStep.choose(.smooth)
            controller.feelStep.artwork.show(time: 0.75)
        }
    }

    /// Draws `view` at 2x over the window colour (the materials draw nothing off screen).
    private func write(
        _ view: NSView, rect: NSRect? = nil, appearance: NSAppearance, focused: NSView? = nil, to url: URL
    ) throws {
        view.display()
        let area = rect ?? view.bounds
        let bounds = NSRect(origin: .zero, size: area.size)
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: area))
        view.cacheDisplay(in: area, to: rep)

        let canvas = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * 2), pixelsHigh: Int(bounds.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        canvas.size = bounds.size
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: canvas))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        appearance.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            bounds.fill()
        }
        rep.draw(in: bounds)
        if let focused {
            let frame = view.convert(focused.bounds, from: focused).offsetBy(dx: -area.minX, dy: -area.minY)
            appearance.performAsCurrentDrawingAppearance {
                NSGraphicsContext.saveGraphicsState()
                let transform = NSAffineTransform()
                transform.translateX(by: frame.minX, yBy: frame.minY)
                transform.concat()
                NSFocusRingPlacement.only.set()
                focused.drawFocusRingMask()
                NSGraphicsContext.restoreGraphicsState()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        let png = try XCTUnwrap(canvas.representation(using: .png, properties: [:]))
        try png.write(to: url)
    }
}

/// Counts as the key and main window of the active app, so the default button, the switches
/// and the window's buttons draw as on screen (`hasKeyAppearance`: see `RenderWindow` in
/// PreferencesWindowRenderTests).
private final class RenderGuideWindow: NSWindow {
    override var isKeyWindow: Bool { return true }
    override var isMainWindow: Bool { return true }
    @objc(hasKeyAppearance) func renderHasKeyAppearance() -> Bool { return true }
}
