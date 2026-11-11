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
//  never ordered in).
//
//  WelcomeGuideRenderTests at the end draws every step off screen, light and dark, when
//  `TEST_RUNNER_SCROLLIO_SHOTS_DIR` is set.
//

import XCTest
@testable import Mos_Debug

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

    var requests = 0
    var settingsOpened = 0
    var reveals = 0
    var grantsReported = 0
    var appSettingsOpened = 0
    var broughtToFront = 0
    var announcements: [String] = []
    var presentedHelp: [NSPopover] = []

    let defaultsSuite = "ScrollioTests.welcomeGuide.\(UUID().uuidString)"
    lazy var defaults = UserDefaults(suiteName: defaultsSuite)!
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
        controller.openAppSettings = { self.appSettingsOpened += 1 }
        controller.prefersReducedMotion = { self.reduceMotion }
        controller.progress = progress
        controller.mouseSource = { self.mouse }
        controller.scrollOptions = { self.scroll }
        controller.tryAreaState = { self.tryArea }
        controller.bringToFront = { _ in self.broughtToFront += 1 }
        controller.announce = { self.announcements.append($0) }
        controller.presentHelp = { popover, _ in self.presentedHelp.append(popover) }
        if let flow {
            controller.begin(flow)
        }
        _ = controller.view
        return controller
    }

    func tearDown() {
        UserDefaults().removePersistentDomain(forName: defaultsSuite)
    }
}

/// A login item whose state the test sets (General's tests use the same seam,
/// `LoginItem.service`).
private final class FakeLoginItem: LoginItemService {
    var status: LoginItemStatus
    /// What registering leaves; nil: nothing changes (it failed, or waits for approval).
    var afterRegister: LoginItemStatus? = .enabled
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

        // Settings from before the guide (an update, or taken over from Mos): finished, silently.
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
        XCTAssertEqual(controller.welcomeStep.textLabel.stringValue, "Smooth scrolling, gestures and button actions for your mouse.")
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
        XCTAssertEqual(controller.backButton.keyEquivalent, "\u{1b}", "Esc goes back")
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
        XCTAssertTrue(step.textLabel.stringValue.contains("reads your mouse"))
        XCTAssertEqual(step.statusBox.titleLabel.stringValue, "Waiting for Scrollio to be turned on…")
        XCTAssertTrue(step.statusBox.detailLabel.stringValue.contains("Open System Settings"))
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
        XCTAssertEqual(status.detailLabel.stringValue, "Scrollio is running. Open Settings from its menu bar icon.")
        XCTAssertEqual(status.accessibilityLabel(), "Allowed. Scrollio is running. Open Settings from its menu bar icon.")
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
        XCTAssertEqual(controller.accessStep.statusBox.detailLabel.stringValue, "Scrollio couldn't start and is trying again.")
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

    func testWithAHiddenMenuBarIconItSaysHowToReachTheSettings() {
        world.menuBarIconHidden = true
        world.runAfterGrant = .running
        let controller = makeAccessController()
        world.accessGranted = true
        controller.accessibilityPermissionsChecker(nil)
        XCTAssertEqual(
            controller.accessStep.statusBox.detailLabel.stringValue,
            "Scrollio is running. Its menu bar icon is hidden: open Scrollio again to reach Settings."
        )
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
        XCTAssertEqual(step.textLabel.stringValue, "Scroll in the box with your mouse wheel, then pick what feels right.")
        XCTAssertEqual(step.noteLabel.stringValue, "You can change this anytime in Settings › Scrolling.")
        XCTAssertEqual(step.feelButtons.map(\.title), ["Direct", "Quick", "Smooth", "Glide", "Float"])
        XCTAssertEqual(step.feelButtons.filter { $0.state == .on }.map(\.feel), [.smooth], "the default is preselected")
        XCTAssertEqual(step.hintLabel.stringValue, "Glides a little after you stop, like a trackpad.")
        for button in step.feelButtons {
            XCTAssertEqual(button.accessibilityRole(), .radioButton)
            XCTAssertEqual(button.accessibilityLabel(), button.feel.localizedName)
            XCTAssertEqual(button.accessibilityHelp(), button.feel.localizedHint)
        }
        XCTAssertTrue(controller.primaryButton.isEnabled, "Continue keeps the preselected feel")

        // A custom glide time (set under Advanced): nothing selected, Continue keeps it.
        world.scroll.duration = 3.4
        controller.begin(.full)
        click(controller.primaryButton)
        XCTAssertTrue(step.feelButtons.allSatisfy { $0.state == .off })
        XCTAssertEqual(step.hintLabel.stringValue, "Custom glide time, set under Advanced.")
        click(controller.primaryButton)
        XCTAssertEqual(world.scroll.duration, 3.4)
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
            XCTAssertEqual(step.hintLabel.stringValue, feel.localizedHint)
            var after = try storedOptions()
            after["duration"] = before["duration"]
            XCTAssertEqual(after as NSDictionary, before as NSDictionary, "only the glide time changed")
        }
        // The same path as the Scrolling pane's Feel control.
        let other = OPTIONS_SCROLL_DEFAULT()
        ScrollFeel.float.apply(to: other)
        XCTAssertEqual(other.duration, 4.6)
    }

    func testTheCurvesComeFromTheEngineAndDiffer() {
        let direct = WelcomeGuideFeelButton.curvePoints(duration: ScrollFeel.direct.duration)
        let float = WelcomeGuideFeelButton.curvePoints(duration: ScrollFeel.float.duration)
        XCTAssertEqual(direct.count, float.count)
        // At a quarter of the time Direct is (nearly) there, Float is not.
        let quarter = direct.count / 4
        XCTAssertLessThan(direct[quarter].y, float[quarter].y)
        // Both start at the bottom and stay in the 80 × 28 box.
        for point in direct + float {
            XCTAssertTrue(NSRect(x: 0, y: 0, width: 80, height: 28).contains(point), "\(point)")
        }
        XCTAssertEqual(direct.first?.y ?? 0, 25, accuracy: 0.01)
    }

    func testWhenTheBoxIsNotSmoothedTheStepSaysWhyAndShowsTheDemo() {
        let controller = makeFeelController()
        let step = controller.feelStep
        XCTAssertEqual(step.artwork.pillText, "Scroll here with your mouse")
        let cases: [(WelcomeGuideTryArea, String)] = [
            (.notRunning, "Scrollio isn't running, so this box isn't smoothed."),
            (.notInAppList, "Scrollio isn't in your list of apps, so this box isn't smoothed."),
            (.smoothingOff, "Smooth scrolling is off, so this box isn't smoothed."),
        ]
        for (state, line) in cases {
            world.tryArea = state
            controller.accessibilityPermissionsChecker(nil)
            XCTAssertEqual(step.textLabel.stringValue, "Watch the page in the box, then pick what feels right.")
            XCTAssertEqual(step.artwork.pillText, line)
            XCTAssertTrue(isShown(step.artwork.pill))
        }
        world.tryArea = .smoothed
        controller.accessibilityPermissionsChecker(nil)
        XCTAssertEqual(step.textLabel.stringValue, "Scroll in the box with your mouse wheel, then pick what feels right.")
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
        XCTAssertEqual(picture.pillText, "That was a trackpad or Magic Mouse. Scrollio leaves those as macOS makes them.")
    }

    func testTheDemoNeverRunsOffScreenAndStopsWithReduceMotion() {
        let controller = makeFeelController()
        let picture = controller.feelStep.artwork
        XCTAssertFalse(picture.isClockRunning, "the window is not on screen")
        // The demo moves the real page (and only along it).
        picture.show(time: 1.0)
        XCTAssertGreaterThan(picture.scrollView.contentView.bounds.minY, 5)
        XCTAssertEqual(picture.scrollView.contentView.bounds.minX, 0)
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

        // Back and again, and a window closed without Done: still nothing.
        click(controller.backButton)
        click(controller.primaryButton)
        XCTAssertTrue(controller.finishStep.loginRow.isOn)
        controller.windowWillClose()
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

    func testTheLastStepNamesTheHiddenIconWay() {
        world.menuBarIconHidden = true
        world.accessGranted = true
        world.run = .running
        let controller = world.makeController(flow: .full)
        click(controller.primaryButton)
        click(controller.primaryButton)
        XCTAssertEqual(
            controller.finishStep.textLabel.stringValue,
            "Scrollio is running. Its menu bar icon is hidden: open Scrollio again to reach Settings."
        )
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
        let controller = try XCTUnwrap(windowController.contentViewController as? IntroductionViewController)
        controller.progress = world.progress
        controller.isAccessGranted = { false }
        controller.runState = { .stopped }
        world.defaults.set(1, forKey: WelcomeGuideProgress.key)
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
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).size, WelcomeGuideLayout.windowSize)
        XCTAssertFalse(window.isVisible)
        XCTAssertNil(controller.accessibilityPermissionsCheckerTimer)
        XCTAssertEqual(controller.flow, .accessOnly, "opened by the app for someone who finished the guide")
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

private extension WelcomeGuideAccessState {
    static var allReady: [WelcomeGuideAccessState] {
        return [WelcomeGuideAccessState.missing, .starting, .running, .paused, .couldNotStart].filter(\.isReady)
    }
}

// MARK: - Renders

/// Draws every step of the Welcome Guide off screen, light and dark, the way the window
/// shows it (the window's appearance, the window colour standing in for the materials,
/// which draw nothing off screen). The animated pictures are drawn at a fixed moment of
/// their loop, or as their Reduce Motion still. Only runs when asked to:
/// `TEST_RUNNER_SCROLLIO_SHOTS_DIR=<folder> xcodebuild … test -only-testing:MosTests/WelcomeGuideRenderTests`.
final class WelcomeGuideRenderTests: XCTestCase {

    private var directory: URL!
    private var worlds: [GuideWorld] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        guard let folder = ProcessInfo.processInfo.environment["SCROLLIO_SHOTS_DIR"], !folder.isEmpty else {
            throw XCTSkip("set TEST_RUNNER_SCROLLIO_SHOTS_DIR to render the Welcome Guide")
        }
        directory = URL(fileURLWithPath: folder, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
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
            try write(frameView, rect: frameView.convert(content.bounds, from: content), appearance: appearance,
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
        try render("guide-2-access-waiting") { controller, _ in
            self.toStep(.access, in: controller)
            controller.accessStep.artwork.show(time: 1.1)
        }
        try render("guide-2-access-waiting-switch-on") { controller, _ in
            self.toStep(.access, in: controller)
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
            controller.finishStep.artwork.showStill()
        }
    }

    /// Draws `view` at 2x over the window colour (the materials draw nothing off screen).
    private func write(_ view: NSView, rect: NSRect? = nil, appearance: NSAppearance, to url: URL) throws {
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
        NSGraphicsContext.restoreGraphicsState()
        let png = try XCTUnwrap(canvas.representation(using: .png, properties: [:]))
        try png.write(to: url)
    }
}

/// Counts as the key and main window, so the default button draws in the accent colour.
private final class RenderGuideWindow: NSWindow {
    override var isKeyWindow: Bool { return true }
    override var isMainWindow: Bool { return true }
}
