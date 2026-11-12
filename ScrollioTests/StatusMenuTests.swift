//
//  StatusMenuTests.swift
//  MosTests
//
//  The menu of the status-bar item (what it lists with and without Accessibility access,
//  with Option held, paused, with batteries, with "Smooth Scrolling in …" for the app in
//  front and how that item decides and changes the app's rule, and what its items do), the
//  run state behind "Pause Scrollio" (AppRunController), the low-battery warnings
//  (BatteryWatcher) and the low battery next to the icon, the names of the windows the menu
//  opens, and the window a reopened app shows. Nothing is shown on screen, no status item is made, no event tap starts and no
//  mouse is asked.
//

import XCTest
@testable import Scrollio_Debug

final class StatusMenuTests: XCTestCase {

    /// One row of the menu as the user reads it.
    private struct Row: Equatable, CustomStringConvertible {
        let title: String
        let shortcut: String
        let enabled: Bool
        let checked: Bool

        static let separator = Row(title: "—")

        init(title: String, shortcut: String = "", enabled: Bool = true, checked: Bool = false) {
            self.title = title
            self.shortcut = shortcut
            self.enabled = enabled
            self.checked = checked
        }

        init(_ item: NSMenuItem) {
            if item.isSeparatorItem {
                self = .separator
                return
            }
            var shortcut = ""
            if !item.keyEquivalent.isEmpty {
                shortcut = "⌘" + item.keyEquivalent.uppercased()
            }
            // AppKit enables an item whose target implements its action (autoenablesItems).
            let enabled = item.action.map { action in (item.target as? NSObject)?.responds(to: action) ?? false } ?? false
            self.init(title: item.title, shortcut: shortcut, enabled: enabled, checked: item.state == .on)
        }

        var description: String {
            return "\(checked ? "✓ " : "")\(title)\(shortcut.isEmpty ? "" : " [\(shortcut)]")\(enabled ? "" : " (disabled)")"
        }
    }

    /// What the items did.
    private final class Calls {
        var log: [String] = []
    }

    private var calls: Calls!
    private var actions: StatusMenuActions!

    override func setUp() {
        super.setUp()
        let calls = Calls()
        self.calls = calls
        let actions = StatusMenuActions()
        actions.showSettings = { calls.log.append("settings") }
        actions.showWelcomeGuide = { calls.log.append("guide") }
        actions.togglePause = { calls.log.append("pause") }
        actions.toggleAppSmoothing = { calls.log.append("smoothing \($0.name)") }
        actions.showScrollMonitor = { calls.log.append("monitor") }
        actions.showDiagnostics = { calls.log.append("diagnostics") }
        actions.showTestToasts = { calls.log.append("toasts") }
        actions.quit = { calls.log.append("quit") }
        self.actions = actions
    }

    override func tearDown() {
        actions = nil
        calls = nil
        super.tearDown()
    }

    private func menu(_ state: StatusMenu.State) -> NSMenu {
        let menu = NSMenu()
        StatusMenu.build(into: menu, state: state, actions: actions)
        return menu
    }

    private func rows(_ state: StatusMenu.State) -> [Row] {
        return menu(state).items.map(Row.init)
    }

    private func state(
        access: Bool = true, paused: Bool = false, diagnostics: Bool = false,
        batteries: [StatusMenu.Battery] = [], appSmoothing: StatusMenu.AppSmoothingItem? = nil
    ) -> StatusMenu.State {
        return StatusMenu.State(
            hasAccess: access, isPaused: paused, showsDiagnostics: diagnostics, batteries: batteries,
            appSmoothing: appSmoothing
        )
    }

    private static let safari = AppSmoothing.App(
        name: "Safari",
        bundlePath: "/Applications/Safari.app",
        executablePath: "/Applications/Safari.app/Contents/MacOS/Safari"
    )

    /// The item for Safari while Scrollio runs.
    private func safariItem(_ rule: AppSmoothing.Rule, smooth: Bool = true, limited: Bool = false) -> StatusMenu.AppSmoothingItem? {
        return StatusMenu.appSmoothingItem(
            front: Self.safari, isScrollio: false, scrollingRuns: true,
            rule: rule, scrollingSmooth: smooth, limitedToListedApps: limited
        )
    }

    private func choose(_ title: String, in menu: NSMenu) throws {
        let item = try XCTUnwrap(menu.items.first { $0.title == title }, "no item \"\(title)\"")
        let action = try XCTUnwrap(item.action)
        XCTAssertTrue(NSApp.sendAction(action, to: item.target, from: item), title)
    }

    func testTheStatusMenuIsAMenuThatBuildsItself() {
        XCTAssertTrue(StatusItemManager.self.isSubclass(of: NSMenu.self))
        XCTAssertTrue(StatusItemManager.self.conforms(to: NSMenuDelegate.self))
    }

    // MARK: - Contents

    func testWithAccess() {
        XCTAssertEqual(rows(state()), [
            Row(title: "Pause Scrollio"),
            Row(title: "Settings…", shortcut: "⌘,"),
            .separator,
            Row(title: "Quit Scrollio", shortcut: "⌘Q"),
        ])
    }

    func testPaused() {
        XCTAssertEqual(rows(state(paused: true)), [
            Row(title: "Resume Scrollio"),
            Row(title: "Settings…", shortcut: "⌘,"),
            .separator,
            Row(title: "Quit Scrollio", shortcut: "⌘Q"),
        ])
    }

    func testWithoutAccess() {
        // Paused or not, batteries or not: only the way to the access and Quit.
        for paused in [false, true] {
            for diagnostics in [false, true] {
                let battery = StatusMenu.Battery(title: "MX Master 4: 75%", symbolName: "battery.75percent")
                XCTAssertEqual(rows(state(access: false, paused: paused, diagnostics: diagnostics, batteries: [battery])), [
                    Row(title: "Allow Accessibility Access…"),
                    .separator,
                    Row(title: "Quit Scrollio", shortcut: "⌘Q"),
                ])
            }
        }
    }

    /// Option (or the debug build) adds the diagnostic windows above Quit; the menu stays.
    func testOptionAddsTheDiagnosticsAboveQuit() {
        XCTAssertEqual(rows(state(diagnostics: true)), [
            Row(title: "Pause Scrollio"),
            Row(title: "Settings…", shortcut: "⌘,"),
            .separator,
            Row(title: "Scroll Monitor"),
            Row(title: "Logitech Diagnostics"),
            Row(title: "Test Toasts"),
            .separator,
            Row(title: "Quit Scrollio", shortcut: "⌘Q"),
        ])
    }

    /// Release build: Option offers Logitech Diagnostics only; Scroll Monitor and Test Toasts
    /// are developer tools of the debug build.
    func testOptionOffersOnlyLogitechDiagnosticsInTheReleaseBuild() {
        var release = state(diagnostics: true)
        release.isDebugBuild = false
        XCTAssertEqual(rows(release), [
            Row(title: "Pause Scrollio"),
            Row(title: "Settings…", shortcut: "⌘,"),
            .separator,
            Row(title: "Logitech Diagnostics"),
            .separator,
            Row(title: "Quit Scrollio", shortcut: "⌘Q"),
        ])
        // Without Option nothing of it, in either build.
        var plain = state()
        plain.isDebugBuild = false
        XCTAssertEqual(rows(plain), rows(state()))
    }

    func testWhichDiagnosticsEachBuildOffers() {
        XCTAssertEqual(StatusMenu.diagnosticItems(isDebugBuild: false), [.diagnostics])
        XCTAssertEqual(StatusMenu.diagnosticItems(isDebugBuild: true), [.scrollMonitor, .diagnostics, .testToasts])
        // These tests run in the debug build.
        XCTAssertTrue(StatusMenu.isDebugBuild)
        XCTAssertTrue(state().isDebugBuild)
    }

    func testOneDisabledBatteryLinePerMouseOnTop() {
        let batteries = StatusMenu.batteries(from: [
            MouseDeviceFixtures.mxMaster4(),
            MouseDeviceFixtures.mxMaster3S(battery: MouseDeviceFixtures.battery(40, charging: .charging)),
        ])
        let built = menu(state(paused: true, batteries: batteries))
        XCTAssertEqual(built.items.map(Row.init), [
            Row(title: "MX Master 4: 75%", enabled: false),
            Row(title: "MX Master 3S: 40%, charging", enabled: false),
            .separator,
            Row(title: "Resume Scrollio"),
            Row(title: "Settings…", shortcut: "⌘,"),
            .separator,
            Row(title: "Quit Scrollio", shortcut: "⌘Q"),
        ])
        XCTAssertNotNil(built.items[0].image, "a battery symbol")
        XCTAssertEqual(built.items[0].tag, StatusMenu.batteryTag)
        XCTAssertNil(built.items[0].action)
    }

    func testBatteryLines() {
        let fixtures = MouseDeviceFixtures.self
        XCTAssertEqual(StatusMenu.batteries(from: [fixtures.mxMaster4()]), [
            StatusMenu.Battery(title: "MX Master 4: 75%", symbolName: "battery.75percent"),
        ])
        XCTAssertEqual(StatusMenu.batteries(from: [fixtures.mxMaster4(battery: fixtures.battery(100, level: .full, charging: .full))]), [
            StatusMenu.Battery(title: "MX Master 4: 100%, charging", symbolName: "battery.100percent.bolt"),
        ])
        XCTAssertEqual(StatusMenu.batteries(from: [fixtures.mxMaster4(battery: fixtures.battery(8, level: .low))]), [
            StatusMenu.Battery(title: "MX Master 4: 8%", symbolName: "battery.0percent"),
        ])
        // A coarse reading, and a level without a number.
        XCTAssertEqual(StatusMenu.batteries(from: [fixtures.mxMaster4(battery: fixtures.battery(50, approximate: true))]).map(\.title),
                       ["MX Master 4: About 50%"])
        XCTAssertEqual(StatusMenu.batteries(from: [fixtures.mxMaster4(battery: fixtures.battery(nil, level: .low))]).map(\.title),
                       ["MX Master 4: Low"])
        // Nothing reported yet, or nothing known: no line.
        XCTAssertEqual(StatusMenu.batteries(from: [fixtures.mxMaster4(battery: nil)]), [])
        XCTAssertEqual(StatusMenu.batteries(from: [fixtures.mxMaster4(battery: fixtures.battery(nil, level: .unknown))]), [])
        XCTAssertEqual(StatusMenu.batteries(from: []), [])
    }

    func testBatteryLinesUpdateInPlaceWhileTheMenuIsOpen() {
        let before = StatusMenu.batteries(from: [MouseDeviceFixtures.mxMaster4()])
        let built = menu(state(batteries: before))
        let after = StatusMenu.batteries(from: [MouseDeviceFixtures.mxMaster4(battery: MouseDeviceFixtures.battery(74))])
        StatusMenu.updateBatteryItems(in: built, with: after)
        XCTAssertEqual(built.items[0].title, "MX Master 4: 74%")
        XCTAssertEqual(built.items.count, 6)

        // A mouse that came or went waits for the next opening.
        StatusMenu.updateBatteryItems(in: built, with: [])
        XCTAssertEqual(built.items[0].title, "MX Master 4: 74%")
    }

    func testNoIconsNoLeadingSpacesNoRawKeys() {
        let battery = StatusMenu.Battery(title: "MX Master 4: 75%", symbolName: "battery.75percent")
        for access in [true, false] {
            for paused in [true, false] {
                let built = menu(state(access: access, paused: paused, diagnostics: true, batteries: [battery]))
                for item in built.items where !item.isSeparatorItem {
                    XCTAssertEqual(item.title, item.title.trimmingCharacters(in: .whitespaces), item.title)
                    XCTAssertFalse(item.title.contains("-menu-"), "\(item.title) shows the raw key")
                    XCTAssertFalse(item.title.hasPrefix("Debug"), item.title)
                    if item.tag != StatusMenu.batteryTag {
                        XCTAssertNil(item.image, item.title)
                    }
                }
            }
        }
    }

    /// The same words as the app's menu bar.
    func testSettingsAndQuitMatchTheMainMenu() throws {
        let main = MainMenuManager().makeMenus().main
        let application = try XCTUnwrap(main.items.first?.submenu)
        let built = menu(state())
        for identifier in [MainMenuManager.Identifier.settings] {
            let title = try XCTUnwrap(application.items.first { $0.identifier == identifier }?.title)
            XCTAssertTrue(built.items.contains { $0.title == title }, title)
        }
        XCTAssertTrue(application.items.contains { $0.title == "Quit Scrollio" })
    }

    // MARK: - Smooth Scrolling in the app in front

    /// One item for the app in front, in a group of its own above Pause, checked while the
    /// app is smoothed.
    func testTheAppInFrontHasItsSmoothingItemAbovePause() throws {
        let checked = try XCTUnwrap(safariItem(.usesScrollingSettings))
        XCTAssertEqual(rows(state(appSmoothing: checked)), [
            Row(title: "Smooth Scrolling in Safari", checked: true),
            .separator,
            Row(title: "Pause Scrollio"),
            Row(title: "Settings…", shortcut: "⌘,"),
            .separator,
            Row(title: "Quit Scrollio", shortcut: "⌘Q"),
        ])
        // Under the battery lines; unchecked for an app that is not smoothed.
        let battery = StatusMenu.Battery(title: "MX Master 4: 75%", symbolName: "battery.75percent")
        let unchecked = try XCTUnwrap(safariItem(.own(smooth: false)))
        XCTAssertEqual(rows(state(batteries: [battery], appSmoothing: unchecked)), [
            Row(title: "MX Master 4: 75%", enabled: false),
            .separator,
            Row(title: "Smooth Scrolling in Safari"),
            .separator,
            Row(title: "Pause Scrollio"),
            Row(title: "Settings…", shortcut: "⌘,"),
            .separator,
            Row(title: "Quit Scrollio", shortcut: "⌘Q"),
        ])
        // A combination it cannot change sensibly: shown, disabled.
        let disabled = try XCTUnwrap(safariItem(.notListed, smooth: false))
        XCTAssertEqual(rows(state(appSmoothing: disabled)).first, Row(title: "Smooth Scrolling in Safari", enabled: false))
        XCTAssertNil(menu(state(appSmoothing: disabled)).items.first?.action)
        // Without the access only the way to it and Quit, as before.
        XCTAssertEqual(rows(state(access: false, appSmoothing: checked)).map(\.title),
                       ["Allow Accessibility Access…", "—", "Quit Scrollio"])
    }

    /// No item without an app in front (or one without a path), for Scrollio itself, and
    /// while Scrollio does not run its taps.
    func testNoSmoothingItemWithoutAnAppOrWhileScrollioDoesNotRun() {
        func item(front: AppSmoothing.App? = Self.safari, isScrollio: Bool = false, runs: Bool = true) -> StatusMenu.AppSmoothingItem? {
            return StatusMenu.appSmoothingItem(
                front: front, isScrollio: isScrollio, scrollingRuns: runs,
                rule: .usesScrollingSettings, scrollingSmooth: true, limitedToListedApps: false
            )
        }
        XCTAssertNotNil(item())
        XCTAssertNil(item(front: nil))
        XCTAssertNil(item(front: AppSmoothing.App(name: "Ghost", bundlePath: nil, executablePath: nil)))
        XCTAssertNil(item(isScrollio: true))
        XCTAssertNil(item(runs: false), "paused, could not start, or a tap kept off")
        // A program without a bundle, or a bundle without a known program, still counts.
        XCTAssertNotNil(item(front: AppSmoothing.App(name: "tool", bundlePath: nil, executablePath: "/usr/local/bin/tool")))
        XCTAssertNotNil(item(front: AppSmoothing.App(name: "Odd", bundlePath: "/Applications/Odd.app", executablePath: nil)))
        XCTAssertNil(menu(state()).items.first { $0.title.hasPrefix("Smooth Scrolling") })
    }

    /// The live run state of the tests: nothing runs, so no item.
    func testNoSmoothingItemUnderTests() {
        XCTAssertNil(StatusItemManager.liveAppSmoothingItem())
    }

    func testTheNameOfTheRunningAppNamesTheItem() throws {
        let current = NSRunningApplication.current
        let app = StatusItemManager.frontApp(current)
        XCTAssertEqual(app.bundlePath, current.bundleURL?.path)
        XCTAssertEqual(app.executablePath, current.executableURL?.path)
        XCTAssertEqual(app.pathToStore, current.executableURL?.path, "the program's path, as \"+\" stores a running app")
        XCTAssertFalse(app.name.isEmpty)
        let item = try XCTUnwrap(StatusMenu.appSmoothingItem(
            front: app, isScrollio: false, scrollingRuns: true,
            rule: .notListed, scrollingSmooth: true, limitedToListedApps: false
        ))
        XCTAssertEqual(item.title, "Smooth Scrolling in \(app.name)")
    }

    func testChoosingTheSmoothingItemChangesThatApp() throws {
        let item = try XCTUnwrap(safariItem(.own(smooth: true)))
        let built = menu(state(appSmoothing: item))
        try choose("Smooth Scrolling in Safari", in: built)
        XCTAssertEqual(calls.log, ["smoothing Safari"])
        XCTAssertEqual(built.items.first?.representedObject as? AppSmoothing.App, Self.safari)
    }

    // MARK: - Actions

    func testWhatTheItemsDo() throws {
        let full = menu(state(diagnostics: true))
        for (title, call) in [
            ("Pause Scrollio", "pause"), ("Settings…", "settings"), ("Scroll Monitor", "monitor"),
            ("Logitech Diagnostics", "diagnostics"), ("Test Toasts", "toasts"), ("Quit Scrollio", "quit"),
        ] {
            calls.log = []
            try choose(title, in: full)
            XCTAssertEqual(calls.log, [call], title)
        }
        calls.log = []
        try choose("Resume Scrollio", in: menu(state(paused: true)))
        XCTAssertEqual(calls.log, ["pause"])
        calls.log = []
        try choose("Allow Accessibility Access…", in: menu(state(access: false)))
        XCTAssertEqual(calls.log, ["guide"], "the Welcome Guide, not the system prompt")
    }

    func testBuildingTheMenuDoesNothing() {
        _ = menu(state(diagnostics: true, batteries: StatusMenu.batteries(from: [MouseDeviceFixtures.mxMaster4()]),
                       appSmoothing: safariItem(.usesScrollingSettings)))
        _ = menu(state(access: false))
        XCTAssertEqual(calls.log, [])
    }

    // MARK: - Icon

    func testTheIconDimsWhilePausedOrWithoutAccess() {
        let running = StatusMenu.IconLook(coresActive: true, isPaused: false)
        XCTAssertFalse(running.appearsDisabled)
        XCTAssertNil(running.toolTip)

        let paused = StatusMenu.IconLook(coresActive: false, isPaused: true)
        XCTAssertTrue(paused.appearsDisabled)
        XCTAssertEqual(paused.toolTip, "Scrollio is paused")

        let noAccess = StatusMenu.IconLook(coresActive: false, isPaused: false)
        XCTAssertTrue(noAccess.appearsDisabled)
        XCTAssertEqual(noAccess.toolTip, "Scrollio needs Accessibility access")
    }

    /// Regression: with the access allowed but an event tap that could not be created, the
    /// tooltip said the access was needed; with a tap whose restarts were throttled the icon
    /// looked as if everything worked.
    func testTheIconSaysWhenScrollioCouldNotStart() {
        let couldNotStart = "Scrollio couldn't start and is trying again."

        let failedStart = StatusMenu.IconLook(coresActive: false, isPaused: false, startFailed: true)
        XCTAssertTrue(failedStart.appearsDisabled)
        XCTAssertEqual(failedStart.toolTip, couldNotStart)

        let throttled = StatusMenu.IconLook(coresActive: true, isPaused: false, tapRestartsThrottled: true)
        XCTAssertTrue(throttled.appearsDisabled, "the not-active look while a tap stays off")
        XCTAssertEqual(throttled.toolTip, couldNotStart)

        // Back to normal by itself once the taps run.
        XCTAssertEqual(StatusMenu.IconLook(coresActive: true, isPaused: false, startFailed: false, tapRestartsThrottled: false),
                       StatusMenu.IconLook(coresActive: true, isPaused: false))

        // A pause says "paused" whatever else is true.
        XCTAssertEqual(StatusMenu.IconLook(coresActive: false, isPaused: true, startFailed: true, tapRestartsThrottled: true).toolTip,
                       "Scrollio is paused")
        // Without the access the start did not fail: it waits.
        XCTAssertEqual(StatusMenu.IconLook(coresActive: false, isPaused: false, startFailed: false, tapRestartsThrottled: true).toolTip,
                       "Scrollio needs Accessibility access")
    }

    /// The live state of the taps: nothing is throttled under tests.
    func testNoTapIsThrottledUnderTests() {
        XCTAssertFalse(Interceptor.hasThrottledTap)
    }
}

// MARK: - Run state: pause, permission

final class AppRunControllerTests: XCTestCase {

    /// The outside world of the controller: the permission, and what it started and showed.
    private final class World {
        var access = true
        /// Whether every event tap can be created.
        var tapsStart = true
        var log: [String] = []
    }

    private var controllers: [AppRunController] = []

    override func tearDown() {
        // No timer may outlive a test.
        for controller in controllers {
            controller.stop()
        }
        controllers = []
        super.tearDown()
    }

    private func make(_ world: World) -> AppRunController {
        let controller = AppRunController(environment: AppRunController.Environment(
            hasAccess: { world.access },
            startCores: { world.log.append("start"); return world.tapsStart },
            stopCores: { world.log.append("stop") },
            showWelcomeGuide: { world.log.append("guide") },
            showAccessLostToast: { world.log.append("toast") }
        ))
        controllers.append(controller)
        return controller
    }

    private func changes(of controller: AppRunController, during work: () -> Void) -> Int {
        var count = 0
        let token = NotificationCenter.default.addObserver(
            forName: AppRunController.didChangeNotification, object: controller, queue: nil
        ) { _ in count += 1 }
        defer { NotificationCenter.default.removeObserver(token) }
        work()
        return count
    }

    func testTheLiveControllerIsIdleUnderTests() {
        // Startup side effects are off: nothing was started, nothing is paused, no timer waits.
        XCTAssertFalse(AppRunController.shared.coresActive)
        XCTAssertFalse(AppRunController.shared.isPaused)
        XCTAssertNil(AppRunController.shared.recoveryTimer)
    }

    func testStartsWithAccess() {
        let world = World()
        let controller = make(world)
        XCTAssertEqual(changes(of: controller) { controller.start() }, 1)
        XCTAssertEqual(world.log, ["start"])
        XCTAssertTrue(controller.coresActive)
        XCTAssertFalse(controller.isWaitingForAccess)
    }

    func testWithoutAccessTheGuideOpensAndATimerWaits() {
        let world = World()
        world.access = false
        let controller = make(world)
        XCTAssertEqual(changes(of: controller) { controller.start() }, 1, "the icon dims at launch")
        XCTAssertEqual(world.log, ["guide"])
        XCTAssertFalse(controller.coresActive)
        XCTAssertTrue(controller.isWaitingForAccess)
        XCTAssertEqual(controller.recoveryTimer?.timeInterval, AppRunController.launchRecoveryInterval)

        // The Welcome Guide saw the grant: the timer's look comes now.
        world.access = true
        XCTAssertEqual(changes(of: controller) { controller.accessibilityPermissionWasGranted() }, 1)
        XCTAssertEqual(world.log, ["guide", "start"])
        XCTAssertTrue(controller.coresActive)
        XCTAssertFalse(controller.isWaitingForAccess)
    }

    /// The wait for the access goes on while the status-bar menu is open or a modal panel
    /// runs: the timer is in the common modes (CommonModesTimer), not only the default one.
    func testTheRecoveryTimerAlsoRunsWhileAMenuIsOpen() throws {
        let world = World()
        world.access = false
        let controller = make(world)
        controller.start()
        let timer = try XCTUnwrap(controller.recoveryTimer)
        for mode in [RunLoop.Mode.default, .eventTracking, .modalPanel] {
            XCTAssertTrue(CFRunLoopContainsTimer(
                CFRunLoopGetMain(),
                unsafeBitCast(timer, to: CFRunLoopTimer.self),
                CFRunLoopMode(mode.rawValue as CFString)
            ), mode.rawValue)
        }
    }

    /// Pause is the stop path: the cores stop (LogiCenter.stop gives the mice their buttons back).
    func testPauseStopsAndResumeStarts() {
        let world = World()
        let controller = make(world)
        controller.start()
        world.log = []

        XCTAssertGreaterThan(changes(of: controller) { controller.setPaused(true) }, 0)
        XCTAssertTrue(controller.isPaused)
        XCTAssertFalse(controller.coresActive)
        XCTAssertEqual(world.log, ["stop"])

        // Pausing twice changes nothing.
        XCTAssertEqual(changes(of: controller) { controller.setPaused(true) }, 0)
        XCTAssertEqual(world.log, ["stop"])

        controller.setPaused(false)
        XCTAssertFalse(controller.isPaused)
        XCTAssertTrue(controller.coresActive)
        XCTAssertEqual(world.log, ["stop", "start"])
    }

    /// Waking up or switching back to the user does not end a pause.
    func testThePauseSurvivesSleepAndSessionSwitches() {
        let world = World()
        let controller = make(world)
        controller.start()
        controller.setPaused(true)
        world.log = []

        controller.stop()      // willSleep / sessionDidResign
        controller.start()     // didWake / sessionDidActive
        XCTAssertTrue(controller.isPaused)
        XCTAssertFalse(controller.coresActive)
        XCTAssertFalse(world.log.contains("start"), "\(world.log)")
        XCTAssertFalse(world.log.contains("guide"), "\(world.log)")
    }

    func testPausingCancelsTheWaitForAccess() {
        let world = World()
        world.access = false
        let controller = make(world)
        controller.start()
        XCTAssertTrue(controller.isWaitingForAccess)

        controller.setPaused(true)
        XCTAssertFalse(controller.isWaitingForAccess)
        world.access = true
        controller.accessibilityPermissionWasGranted()
        XCTAssertFalse(controller.coresActive, "granted while paused: it stays paused")
    }

    func testThePauseIsNotStored() {
        let before = Set(UserDefaults.standard.dictionaryRepresentation().keys)
        let world = World()
        let controller = make(world)
        controller.start()
        controller.setPaused(true)
        let after = Set(UserDefaults.standard.dictionaryRepresentation().keys)
        XCTAssertEqual(after.subtracting(before), [])
        // A new run starts unpaused.
        XCTAssertFalse(make(world).isPaused)
    }

    func testLostAccessStopsOnceShowsTheToastAndWaits() {
        let world = World()
        let controller = make(world)
        controller.start()
        world.log = []
        world.access = false

        XCTAssertEqual(changes(of: controller) {
            // Several event taps report it at once.
            controller.accessWasLost()
            controller.accessWasLost()
        }, 1)
        XCTAssertEqual(world.log, ["stop", "toast"])
        XCTAssertFalse(controller.coresActive)
        XCTAssertTrue(controller.isWaitingForAccess)
        XCTAssertEqual(controller.recoveryTimer?.timeInterval, AppRunController.lostRecoveryInterval)

        // A look without the access changes nothing; with it the cores start again.
        controller.accessibilityPermissionWasGranted()
        XCTAssertFalse(controller.coresActive)
        world.access = true
        controller.accessibilityPermissionWasGranted()
        XCTAssertTrue(controller.coresActive)
        XCTAssertEqual(world.log, ["stop", "toast", "start"])
    }

    func testLostAccessWhilePausedDoesNothing() {
        let world = World()
        let controller = make(world)
        controller.start()
        controller.setPaused(true)
        world.log = []
        controller.accessWasLost()
        XCTAssertEqual(world.log, [])
        XCTAssertFalse(controller.isWaitingForAccess)
    }

    /// A second wake (or a session that becomes active twice) does not start the cores again.
    func testCoresThatRunAreNotStartedAgain() {
        let world = World()
        let controller = make(world)
        controller.start()
        controller.start()
        controller.sessionDidBecomeActive()
        XCTAssertEqual(world.log, ["start"])
        XCTAssertTrue(controller.coresActive)
    }

    /// Fast user switching: the Mac sleeps and wakes while another user has it. Waking must
    /// not start the cores (a Logitech mouse would be diverted to this account and lose its
    /// buttons for the other user); switching back does.
    func testWakingWhileAnotherUserHasTheMacStartsNothing() {
        let world = World()
        let controller = make(world)
        controller.start()
        world.log = []

        controller.sessionDidResign()
        XCTAssertEqual(world.log, ["stop"])
        XCTAssertFalse(controller.coresActive)

        controller.stop()       // willSleep
        controller.start()      // didWake, still the other user's session
        XCTAssertFalse(world.log.contains("start"), "\(world.log)")
        XCTAssertFalse(world.log.contains("guide"), "\(world.log)")
        XCTAssertFalse(controller.coresActive)
        XCTAssertFalse(controller.isWaitingForAccess)

        controller.sessionDidBecomeActive()
        XCTAssertEqual(world.log.last, "start")
        XCTAssertTrue(controller.coresActive)
    }

    /// Resuming in another user's session cannot happen from the menu, but a pause that ends
    /// there must not start anything either; switching back starts.
    func testAPausedSessionSwitchStaysStoppedUntilBoth() {
        let world = World()
        let controller = make(world)
        controller.start()
        controller.setPaused(true)
        controller.sessionDidResign()
        controller.sessionDidBecomeActive()
        XCTAssertFalse(controller.coresActive, "still paused")
        controller.setPaused(false)
        XCTAssertTrue(controller.coresActive)
    }

    /// Without the access every wake opened the Welcome Guide again. It opens at launch (and
    /// when the app is reopened); a wake only arms the timer again.
    func testWithoutAccessAWakeOnlyArmsTheTimerAgain() {
        let world = World()
        world.access = false
        let controller = make(world)
        controller.start()      // launch
        XCTAssertEqual(world.log, ["guide"])

        controller.stop()       // willSleep
        XCTAssertFalse(controller.isWaitingForAccess)
        XCTAssertEqual(changes(of: controller) { controller.wake() }, 1)
        XCTAssertEqual(world.log.filter { $0 == "guide" }.count, 1, "no second Welcome Guide: \(world.log)")
        XCTAssertTrue(controller.isWaitingForAccess, "the timer waits for the access again")
        XCTAssertEqual(controller.recoveryTimer?.timeInterval, AppRunController.launchRecoveryInterval)

        world.access = true
        controller.accessibilityPermissionWasGranted()
        XCTAssertTrue(controller.coresActive)
        XCTAssertEqual(world.log.last, "start")
    }

    /// With the access a wake starts the cores, as before; while paused it does nothing.
    func testAWakeWithAccessStartsTheCores() {
        let world = World()
        let controller = make(world)
        controller.start()
        controller.stop()
        controller.wake()
        XCTAssertEqual(world.log, ["start", "stop", "start"])
        XCTAssertTrue(controller.coresActive)

        controller.setPaused(true)
        controller.stop()
        controller.wake()
        XCTAssertFalse(controller.coresActive, "still paused")
    }

    /// Switching back to this user is a wake too: no Welcome Guide, the timer waits.
    func testWithoutAccessASwitchBackToThisUserOnlyArmsTheTimer() {
        let world = World()
        world.access = false
        let controller = make(world)
        controller.start()
        controller.sessionDidResign()
        controller.sessionDidBecomeActive()
        XCTAssertEqual(world.log.filter { $0 == "guide" }.count, 1, "\(world.log)")
        XCTAssertTrue(controller.isWaitingForAccess)
    }

    /// A start that fails half-way (an event tap could not be created) stops whatever did
    /// start, so no tap stays installed while the cores count as stopped, and tries again.
    func testAStartThatFailsHalfWayStopsEverythingAndTriesAgain() {
        let world = World()
        world.tapsStart = false
        let controller = make(world)
        controller.start()
        XCTAssertEqual(world.log, ["start", "stop"])
        XCTAssertFalse(controller.coresActive)
        XCTAssertTrue(controller.isRetryingStart, "a timer tries again")
        XCTAssertFalse(controller.isWaitingForAccess, "the access is there: the status item must not ask for it")
        XCTAssertEqual(controller.recoveryTimer?.timeInterval, AppRunController.launchRecoveryInterval)

        // A permission-lost report from the failing tap changes nothing more.
        controller.accessWasLost()
        XCTAssertEqual(world.log, ["start", "stop"])

        world.tapsStart = true
        controller.accessibilityPermissionWasGranted()   // the timer's next look, now
        XCTAssertEqual(world.log, ["start", "stop", "start"])
        XCTAssertTrue(controller.coresActive)
        XCTAssertFalse(controller.isWaitingForAccess)
        XCTAssertFalse(controller.isRetryingStart, "back to normal by itself")
    }

    /// A retry that keeps failing goes on trying; when the access goes away meanwhile it
    /// waits for the access instead, and says so.
    func testAFailedStartThatLosesTheAccessWaitsForTheAccess() {
        let world = World()
        world.tapsStart = false
        let controller = make(world)
        controller.start()
        controller.accessibilityPermissionWasGranted()   // a retry that fails again
        XCTAssertEqual(world.log, ["start", "stop", "start", "stop"])
        XCTAssertTrue(controller.isRetryingStart)

        world.access = false
        XCTAssertEqual(changes(of: controller) { controller.accessibilityPermissionWasGranted() }, 1)
        XCTAssertFalse(controller.isRetryingStart)
        XCTAssertTrue(controller.isWaitingForAccess)
        XCTAssertEqual(world.log.count, 4, "no start without the access")
    }

    /// Pausing, sleeping or another user ends the "could not start" state.
    func testStoppingEndsAFailedStart() {
        let world = World()
        world.tapsStart = false
        let controller = make(world)
        controller.start()
        XCTAssertTrue(controller.isRetryingStart)
        controller.setPaused(true)
        XCTAssertFalse(controller.isRetryingStart)
        XCTAssertNil(controller.recoveryTimer)
    }

    /// A start that keeps failing is tried every 10 s; the log gets the first three and then
    /// one in 30, not a line every 10 s for hours.
    func testAFailingStartIsLoggedSparingly() {
        let logged = (1...120).filter(AppRunController.logsFailedStart)
        XCTAssertEqual(logged, [1, 2, 3, 30, 60, 90, 120])
        XCTAssertEqual(
            AppRunController.failedStartLine(trigger: .launch, failedStarts: 1),
            "Could not start (launch): an event tap could not be created although Accessibility access is allowed; "
                + "trying again in 10 s (failed starts in a row: 1)"
        )
    }

    // MARK: - The order of the live cores

    private func parts(_ log: Recorder, failing: String? = nil) -> [AppRunController.Environment.Part] {
        let names: [String] = ["scroll", "button"]
        return names.map { (name: String) -> AppRunController.Environment.Part in
            AppRunController.Environment.Part(
                start: { log.entries.append("\(name) on") },
                stop: { log.entries.append("\(name) off") },
                isRunning: { name != failing }
            )
        }
    }

    private final class Recorder {
        var entries: [String] = []
    }

    private func logitech(_ log: Recorder) -> AppRunController.Environment.Part {
        return AppRunController.Environment.Part(
            start: { log.entries.append("logi on") },
            stop: { log.entries.append("logi off") },
            isRunning: { true }
        )
    }

    func testTheTapsStartFirstAndTheLogitechSessionsOnlyWhenEveryTapRuns() {
        let log = Recorder()
        let cores = AppRunController.Environment.cores(eventTaps: parts(log), logitech: logitech(log))
        XCTAssertTrue(cores.start())
        XCTAssertEqual(log.entries, ["scroll on", "button on", "logi on"])

        let failing = Recorder()
        let half = AppRunController.Environment.cores(eventTaps: parts(failing, failing: "button"), logitech: logitech(failing))
        XCTAssertFalse(half.start())
        XCTAssertEqual(failing.entries, ["scroll on", "button on"], "no Logitech divert without the button tap")
    }

    /// The Logitech teardown writes to the mice synchronously on the main thread: the event
    /// taps are off before, so no active tap waits for this thread meanwhile.
    func testStoppingTurnsTheTapsOffBeforeTheLogitechSessions() {
        let log = Recorder()
        let cores = AppRunController.Environment.cores(eventTaps: parts(log), logitech: logitech(log))
        cores.stop()
        XCTAssertEqual(log.entries, ["scroll off", "button off", "logi off"])
    }

    /// The pointer-movement tap of gesture holds is made on demand: starting the cores does
    /// not make it, stopping them releases it (after ButtonCore, which ends a hold), so a tap
    /// kept across lost Accessibility access or another user cannot stay off for good.
    func testStoppingReleasesTheTapsMadeOnDemandAfterTheEventTaps() {
        let log = Recorder()
        let cores = AppRunController.Environment.cores(
            eventTaps: parts(log),
            onDemandTaps: [{ log.entries.append("motion released") }],
            logitech: logitech(log)
        )
        XCTAssertTrue(cores.start())
        XCTAssertEqual(log.entries, ["scroll on", "button on", "logi on"])

        log.entries = []
        cores.stop()
        XCTAssertEqual(log.entries, ["scroll off", "button off", "motion released", "logi off"])
    }

    func testTheToastText() {
        XCTAssertEqual(
            NSLocalizedString("toast-accessibility-lost", comment: ""),
            "Scrollio stopped: Accessibility access was turned off. It starts again as soon as you allow it."
        )
    }

    // MARK: - macOS says the Accessibility list changed

    /// The taps' keepers look every 5 s; in that time a tap of a process without the access
    /// is what makes keys and the wheel hang. The notification of macOS brings the look
    /// forward, both ways.
    func testAChangeOfTheAccessibilityListIsLookedAtAtOnce() {
        let world = World()
        let controller = make(world)
        controller.start()
        world.log = []

        // Another app's entry changed: the access is still there, nothing happens.
        XCTAssertEqual(changes(of: controller) { controller.accessibilityListDidChange() }, 0)
        XCTAssertEqual(world.log, [])
        XCTAssertTrue(controller.coresActive)

        // Scrollio's own was switched off: the same stop as when a tap finds it gone.
        world.access = false
        XCTAssertEqual(changes(of: controller) { controller.accessibilityListDidChange() }, 1)
        XCTAssertEqual(world.log, ["stop", "toast"])
        XCTAssertFalse(controller.coresActive)
        XCTAssertTrue(controller.isWaitingForAccess)

        // Still off: one more change of the list starts nothing.
        controller.accessibilityListDidChange()
        XCTAssertEqual(world.log, ["stop", "toast"])

        // Switched on again: the cores start now, not at the timer's next look.
        world.access = true
        controller.accessibilityListDidChange()
        XCTAssertEqual(world.log, ["stop", "toast", "start"])
        XCTAssertTrue(controller.coresActive)
    }

    func testAChangeOfTheAccessibilityListDoesNothingWhilePausedOrAsleep() {
        let world = World()
        let controller = make(world)
        controller.start()
        controller.setPaused(true)
        world.log = []
        world.access = false
        controller.accessibilityListDidChange()
        world.access = true
        controller.accessibilityListDidChange()
        XCTAssertEqual(world.log, [], "paused: nothing starts or stops")
        XCTAssertFalse(controller.coresActive)

        let asleep = make(world)
        asleep.start()
        asleep.stop(because: .sleep)
        world.log = []
        asleep.accessibilityListDidChange()
        XCTAssertEqual(world.log, [], "asleep: no timer waits, nothing starts")
    }

    // MARK: - Reopening the app

    /// Opening the app again (also with the menu bar icon hidden) always leads somewhere.
    func testReopeningShowsTheSettingsOrTheWelcomeGuide() {
        XCTAssertEqual(AppDelegate.windowForReopen(hasAccess: true), WINDOW_IDENTIFIER.preferencesWindowController)
        XCTAssertEqual(AppDelegate.windowForReopen(hasAccess: false), WINDOW_IDENTIFIER.introductionWindowController)
    }
}

// MARK: - Smooth Scrolling in the app in front: the rule and the click

/// What "Smooth Scrolling in …" says for every combination of the app's rule, the global
/// "Smooth scrolling" and "Limit scrolling to these apps", that it says what the scroll engine
/// does, and what a click changes on the per-app list. The settings of the app are swapped for
/// fresh ones and put back; nothing is saved under tests.
final class AppSmoothingTests: XCTestCase {

    private var originalApplications: EnhanceArray<Application>!
    private var originalAllowlist = false
    private var originalScroll: OPTIONS_SCROLL_DEFAULT!

    private static let safari = AppSmoothing.App(
        name: "Safari",
        bundlePath: "/Applications/Safari.app",
        executablePath: "/Applications/Safari.app/Contents/MacOS/Safari"
    )

    override func setUp() {
        super.setUp()
        originalApplications = Options.shared.application.applications
        originalAllowlist = Options.shared.application.allowlist
        originalScroll = Options.shared.scroll
        Options.shared.application.applications = Self.makeStore()
        Options.shared.application.allowlist = false
        Options.shared.scroll = OPTIONS_SCROLL_DEFAULT()
    }

    override func tearDown() {
        Options.shared.application.applications = originalApplications
        Options.shared.application.allowlist = originalAllowlist
        Options.shared.scroll = originalScroll
        originalApplications = nil
        originalScroll = nil
        super.tearDown()
    }

    private static func makeStore(_ applications: [Application] = []) -> EnhanceArray<Application> {
        return EnhanceArray<Application>(
            withArray: applications,
            matchKey: "path",
            forObserver: { Options.shared.markChanged(.application) }
        )
    }

    private static func copy(_ scroll: OPTIONS_SCROLL_DEFAULT) throws -> OPTIONS_SCROLL_DEFAULT {
        return try JSONDecoder().decode(OPTIONS_SCROLL_DEFAULT.self, from: JSONEncoder().encode(scroll))
    }

    /// Scrolling settings that differ from a new entry's in every way a copy would show.
    private static func customScrolling(smooth: Bool = true) -> OPTIONS_SCROLL_DEFAULT {
        let scrolling = OPTIONS_SCROLL_DEFAULT()
        scrolling.smooth = smooth
        scrolling.reversesWheel = false
        scrolling.speed = 8.5
        scrolling.dash = nil
        scrolling.duration = ScrollFeel.glide.duration
        return scrolling
    }

    private func application(_ path: String, inherit: Bool, smooth: Bool = true) -> Application {
        let application = Application(path: path)
        application.inherit = inherit
        application.scroll.smooth = smooth
        return application
    }

    /// The list as it would be stored (key order aside).
    private func storedList() throws -> NSArray {
        let data = try XCTUnwrap(Options.shared.application.applications.json())
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? NSArray)
    }

    private func list(_ applications: [Application] = [], limited: Bool = false) -> OPTIONS_APPLICATION_DEFAULT {
        let list = OPTIONS_APPLICATION_DEFAULT()
        list.applications = Self.makeStore(applications)
        list.allowlist = limited
        return list
    }

    // MARK: - The decision

    func testEveryCombination() {
        typealias D = AppSmoothing.Decision
        for limited in [false, true] {
            for smooth in [true, false] {
                func decide(_ rule: AppSmoothing.Rule) -> D {
                    return AppSmoothing.decide(rule: rule, scrollingSmooth: smooth, limitedToListedApps: limited)
                }
                let context = "global smoothing \(smooth), limited \(limited)"
                // Not on the list: the Scrolling settings, or macOS while the list limits.
                if limited {
                    XCTAssertEqual(decide(.notListed), D(isSmoothed: false, change: nil), context)
                } else if smooth {
                    XCTAssertEqual(decide(.notListed), D(isSmoothed: true, change: .addWithSmoothingOff), context)
                } else {
                    XCTAssertEqual(decide(.notListed), D(isSmoothed: false, change: nil), context)
                }
                // On the list with the Scrolling settings: the global switch, list limited or not.
                XCTAssertEqual(decide(.usesScrollingSettings),
                               smooth ? D(isSmoothed: true, change: .ownSettingsWithSmoothingOff) : D(isSmoothed: false, change: nil),
                               context)
                // Its own settings: only those count, also with smoothing off globally.
                XCTAssertEqual(decide(.own(smooth: true)), D(isSmoothed: true, change: .setOwnSmoothing(false)), context)
                XCTAssertEqual(decide(.own(smooth: false)), D(isSmoothed: false, change: .setOwnSmoothing(true)), context)
            }
        }
    }

    func testTheItemShowsTheDecision() throws {
        func item(_ rule: AppSmoothing.Rule, smooth: Bool = true, limited: Bool = false) throws -> StatusMenu.AppSmoothingItem {
            return try XCTUnwrap(StatusMenu.appSmoothingItem(
                front: Self.safari, isScrollio: false, scrollingRuns: true,
                rule: rule, scrollingSmooth: smooth, limitedToListedApps: limited
            ))
        }
        XCTAssertEqual(try item(.usesScrollingSettings).title, "Smooth Scrolling in Safari")
        XCTAssertEqual(try item(.usesScrollingSettings).app, Self.safari)
        let combinations: [(rule: AppSmoothing.Rule, smooth: Bool, limited: Bool, checked: Bool, enabled: Bool)] = [
            (.notListed, true, false, true, true),
            (.notListed, false, false, false, false),
            (.notListed, true, true, false, false),
            (.usesScrollingSettings, true, true, true, true),
            (.usesScrollingSettings, false, false, false, false),
            (.own(smooth: true), false, false, true, true),
            (.own(smooth: false), true, true, false, true),
        ]
        for (rule, smooth, limited, checked, enabled) in combinations {
            let shown = try item(rule, smooth: smooth, limited: limited)
            XCTAssertEqual(shown.isChecked, checked, "\(rule), global \(smooth), limited \(limited)")
            XCTAssertEqual(shown.isEnabled, enabled, "\(rule), global \(smooth), limited \(limited)")
        }
    }

    func testTheRuleOfAnEntry() {
        XCTAssertEqual(AppSmoothing.rule(of: nil), .notListed)
        XCTAssertEqual(AppSmoothing.rule(of: application("/a", inherit: true, smooth: false)), .usesScrollingSettings)
        XCTAssertEqual(AppSmoothing.rule(of: application("/a", inherit: false, smooth: true)), .own(smooth: true))
        XCTAssertEqual(AppSmoothing.rule(of: application("/a", inherit: false, smooth: false)), .own(smooth: false))
    }

    /// The entry is found as the engine finds it: by the bundle's path, then the program's.
    func testTheEntryIsFoundAsTheEngineFindsIt() throws {
        let current = NSRunningApplication.current
        let app = StatusItemManager.frontApp(current)
        let program = try XCTUnwrap(current.executableURL?.path)
        let bundle = try XCTUnwrap(current.bundleURL?.path)
        for paths in [[program], [bundle], [program, bundle]] {
            Options.shared.application.applications = Self.makeStore(paths.map { application($0, inherit: true) })
            let entry = AppSmoothing.entry(for: app, in: Options.shared.application.applications)
            XCTAssertNotNil(entry, "\(paths)")
            XCTAssertTrue(entry === ScrollUtils.shared.getTargetApplication(from: current), "\(paths)")
        }
        Options.shared.application.applications = Self.makeStore([application("/Applications/Other.app", inherit: true)])
        XCTAssertNil(AppSmoothing.entry(for: app, in: Options.shared.application.applications))
        XCTAssertNil(ScrollUtils.shared.getTargetApplication(from: current))
    }

    /// For every combination the checkmark says what the engine does (ScrollCore: the entry's
    /// rule, else the Scrolling settings unless the list limits), and a click that is offered
    /// turns it the other way while the app stays on the list.
    func testTheCheckmarkSaysWhatTheEngineDoesAndAClickTurnsIt() throws {
        let current = NSRunningApplication.current
        let app = StatusItemManager.frontApp(current)
        let program = try XCTUnwrap(app.executablePath)

        func engineSmooths() -> Bool {
            if let entry = ScrollUtils.shared.getTargetApplication(from: current) {
                return entry.isSmooth(false)
            }
            return !Options.shared.application.allowlist && Options.shared.scroll.smooth
        }

        let rules: [(String, () -> [Application])] = [
            ("not listed", { [] }),
            ("uses Scrolling", { [self.application(program, inherit: true)] }),
            ("own, smooth", { [self.application(program, inherit: false, smooth: true)] }),
            ("own, not smooth", { [self.application(program, inherit: false, smooth: false)] }),
        ]
        for (name, entries) in rules {
            for smooth in [true, false] {
                for limited in [false, true] {
                    let context = "\(name), global smoothing \(smooth), limited \(limited)"
                    Options.shared.application.applications = Self.makeStore(entries())
                    Options.shared.application.allowlist = limited
                    Options.shared.scroll = Self.customScrolling(smooth: smooth)

                    let before = AppSmoothing.decision(for: app, list: Options.shared.application, scrolling: Options.shared.scroll)
                    XCTAssertEqual(before.isSmoothed, engineSmooths(), context)

                    let stored = try storedList()
                    let change = AppSmoothing.toggle(app, list: Options.shared.application, scrolling: Options.shared.scroll)
                    XCTAssertEqual(change, before.change, context)
                    guard change != nil else {
                        XCTAssertEqual(try storedList(), stored, "disabled: nothing changes, \(context)")
                        continue
                    }
                    XCTAssertEqual(engineSmooths(), !before.isSmoothed, context)
                    XCTAssertEqual(Options.shared.application.applications.count, 1, context)
                    let after = AppSmoothing.decision(for: app, list: Options.shared.application, scrolling: Options.shared.scroll)
                    XCTAssertEqual(after.isSmoothed, !before.isSmoothed, context)
                    XCTAssertNotNil(after.change, "it can be turned back, \(context)")
                    XCTAssertTrue(Options.shared.scroll == Self.customScrolling(smooth: smooth), "the Scrolling settings stay, \(context)")
                }
            }
        }
    }

    // MARK: - What a click changes

    /// Not on the list: added as "+" adds a running app, with its own settings copied from
    /// the Scrolling settings and smoothing off; checking again turns only that back on.
    func testAnAppNotOnTheListIsAddedWithItsOwnSettingsAndSmoothingOff() throws {
        let scrolling = Self.customScrolling()
        let list = self.list()
        XCTAssertEqual(AppSmoothing.toggle(Self.safari, list: list, scrolling: scrolling), .addWithSmoothingOff)
        XCTAssertEqual(list.applications.count, 1)
        let added = try XCTUnwrap(list.applications.get(by: 0))
        XCTAssertEqual(added.path, Self.safari.executablePath, "stored by the program's path, as \"+\" does")
        XCTAssertFalse(added.inherit)
        XCTAssertEqual(added.displayName, "")
        XCTAssertNil(added.buttons)
        XCTAssertFalse(added.scroll.smooth)
        XCTAssertFalse(added.scroll === scrolling, "its own container")
        let expected = try Self.copy(scrolling)
        expected.smooth = false
        XCTAssertTrue(added.scroll == expected, "everything else as in the Scrolling settings")

        // Stored as an app the pane adds: the same keys.
        let stored = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(list.applications.json())) as? [[String: Any]])
        XCTAssertEqual(Set(try XCTUnwrap(stored.first).keys), ["path", "displayName", "inherit", "scroll"])

        XCTAssertEqual(AppSmoothing.toggle(Self.safari, list: list, scrolling: scrolling), .setOwnSmoothing(true))
        XCTAssertEqual(list.applications.count, 1, "it stays on the list")
        XCTAssertTrue(added.scroll.smooth)
        XCTAssertFalse(added.inherit)
        XCTAssertTrue(added.scroll == scrolling)
    }

    /// An app found by its bundle's path is not added a second time.
    func testAnAppListedByItsBundleIsNotAddedAgain() throws {
        let entry = application(try XCTUnwrap(Self.safari.bundlePath), inherit: true)
        let list = self.list([entry])
        XCTAssertEqual(AppSmoothing.toggle(Self.safari, list: list, scrolling: Self.customScrolling()), .ownSettingsWithSmoothingOff)
        XCTAssertEqual(list.applications.count, 1)
        XCTAssertFalse(entry.inherit)
        XCTAssertFalse(entry.scroll.smooth)
    }

    /// "Use settings from Scrolling" on, own settings never edited: they become a copy of
    /// the Scrolling settings (in the app's own container), then smoothing goes off.
    func testAnAppUsingTheScrollingSettingsGetsACopyWithSmoothingOff() throws {
        let scrolling = Self.customScrolling()
        let entry = Application(path: try XCTUnwrap(Self.safari.executablePath))
        let own = entry.scroll
        let list = self.list([entry])
        XCTAssertEqual(AppSmoothing.toggle(Self.safari, list: list, scrolling: scrolling), .ownSettingsWithSmoothingOff)
        XCTAssertFalse(entry.inherit)
        XCTAssertTrue(entry.scroll === own)
        let expected = try Self.copy(scrolling)
        expected.smooth = false
        XCTAssertTrue(entry.scroll == expected)
        XCTAssertTrue(scrolling.smooth, "the Scrolling settings stay")
    }

    /// Own settings that were edited are kept, as the Apps pane keeps them.
    func testEditedOwnSettingsAreKept() throws {
        let entry = Application(path: try XCTUnwrap(Self.safari.executablePath))
        entry.scroll.speed = 2
        let list = self.list([entry])
        AppSmoothing.toggle(Self.safari, list: list, scrolling: Self.customScrolling())
        XCTAssertFalse(entry.inherit)
        XCTAssertFalse(entry.scroll.smooth)
        XCTAssertEqual(entry.scroll.speed, 2)
        XCTAssertTrue(entry.scroll.reversesWheel, "the app's own value")
        XCTAssertEqual(entry.scroll.dash, OPTIONS_SCROLL_DEFAULT().dash)
    }

    /// Own settings: only "Smooth scrolling" changes, both ways; the global switch does not matter.
    func testOwnSettingsChangeOnlySmoothing() throws {
        let entry = application(try XCTUnwrap(Self.safari.executablePath), inherit: false, smooth: true)
        entry.scroll.speed = 3
        entry.scroll.reverse = false
        let before = try Self.copy(entry.scroll)
        let list = self.list([entry], limited: true)
        let globallyOff = Self.customScrolling(smooth: false)

        XCTAssertEqual(AppSmoothing.toggle(Self.safari, list: list, scrolling: globallyOff), .setOwnSmoothing(false))
        before.smooth = false
        XCTAssertTrue(entry.scroll == before)
        XCTAssertFalse(entry.inherit)

        XCTAssertEqual(AppSmoothing.toggle(Self.safari, list: list, scrolling: globallyOff), .setOwnSmoothing(true))
        before.smooth = true
        XCTAssertTrue(entry.scroll == before)
        XCTAssertEqual(list.applications.count, 1)
    }

    /// Where the item is disabled a click changes nothing.
    func testADisabledCombinationChangesNothing() throws {
        let off = Self.customScrolling(smooth: false)
        let notListed = list()
        XCTAssertNil(AppSmoothing.toggle(Self.safari, list: notListed, scrolling: off))
        XCTAssertEqual(notListed.applications.count, 0)

        let limited = list(limited: true)
        XCTAssertNil(AppSmoothing.toggle(Self.safari, list: limited, scrolling: Self.customScrolling()))
        XCTAssertEqual(limited.applications.count, 0, "not added: that would start reversing in it too")

        let entry = Application(path: try XCTUnwrap(Self.safari.executablePath))
        let inheriting = list([entry])
        XCTAssertNil(AppSmoothing.toggle(Self.safari, list: inheriting, scrolling: off))
        XCTAssertTrue(entry.inherit)
        XCTAssertTrue(entry.scroll == OPTIONS_SCROLL_DEFAULT())
    }

    // MARK: - The step shared with the Apps pane

    func testUsingTheScrollingSettingsOnAndOff() {
        let scrolling = Self.customScrolling()
        let app = Application(path: "/Applications/Safari.app")
        app.setUsesScrollingSettings(true, scrolling: scrolling)
        XCTAssertTrue(app.inherit)
        XCTAssertTrue(app.scroll == OPTIONS_SCROLL_DEFAULT(), "already on: nothing copied")

        app.setUsesScrollingSettings(false, scrolling: scrolling)
        XCTAssertFalse(app.inherit)
        XCTAssertTrue(app.scroll == scrolling)

        // Already off: the Scrolling settings changed since, the app's own stay.
        let other = Self.customScrolling()
        other.speed = 1.5
        app.setUsesScrollingSettings(false, scrolling: other)
        XCTAssertEqual(app.scroll.speed, 8.5)

        // On again: its own are kept for later.
        app.setUsesScrollingSettings(true, scrolling: other)
        XCTAssertTrue(app.inherit)
        XCTAssertEqual(app.scroll.speed, 8.5)
    }
}

// MARK: - Battery warnings

final class BatteryWatcherTests: XCTestCase {

    private var mice: [LogiMouseDeviceState] = []
    private var toasts: [String] = []
    private var watcher: BatteryWatcher!

    override func setUp() {
        super.setUp()
        mice = []
        toasts = []
        let watcher = BatteryWatcher()
        watcher.deviceStates = { [unowned self] in self.mice }
        watcher.showToast = { [unowned self] in self.toasts.append($0) }
        self.watcher = watcher
    }

    override func tearDown() {
        watcher.stop()
        watcher = nil
        super.tearDown()
    }

    private func battery(_ percent: Int?, level: LogiMouseDeviceState.Battery.Level = .good,
                         charging: LogiMouseDeviceState.Battery.Charging = .discharging) -> LogiMouseDeviceState.Battery {
        return MouseDeviceFixtures.battery(percent, level: level, charging: charging)
    }

    private func report(_ battery: LogiMouseDeviceState.Battery?, id: String = "mx4") {
        mice = [MouseDeviceFixtures.mxMaster4(id: id, battery: battery)]
        watcher.check()
    }

    func testTheOwnersMouseIsFine() {
        report(MouseDeviceFixtures.battery(75))
        XCTAssertEqual(toasts, [])
    }

    func testOnceAtLowOnceAtCritical() {
        report(battery(11))
        XCTAssertEqual(toasts, [])
        report(battery(10, level: .low))
        XCTAssertEqual(toasts, ["MX Master 4 battery is low (10%)."])
        report(battery(9, level: .low))
        report(battery(7, level: .low))
        XCTAssertEqual(toasts.count, 1, "low is said once")
        report(battery(5, level: .critical))
        XCTAssertEqual(toasts.last, "MX Master 4 battery is almost empty (5%). Charge it now.")
        report(battery(4, level: .critical))
        report(battery(2, level: .critical))
        XCTAssertEqual(toasts.count, 2, "critical is said once")
    }

    func testChargingStartsOver() {
        report(battery(9, level: .low))
        XCTAssertEqual(toasts.count, 1)
        report(battery(10, level: .low, charging: .charging))
        XCTAssertEqual(toasts.count, 1, "no warning while charging")
        // Unplugged soon after: it is low again, and said again.
        report(battery(12, level: .low))
        XCTAssertEqual(toasts.count, 2)
    }

    func testAChargeThatWasNotSeenStartsOverToo() {
        report(battery(8, level: .low))
        report(battery(20))
        report(battery(9, level: .low))
        XCTAssertEqual(toasts.count, 1, "under the recovered mark it does not repeat")
        report(battery(90, level: .full))
        report(battery(9, level: .low))
        XCTAssertEqual(toasts.count, 2)
    }

    func testStraightToCriticalIsOneWarning() {
        report(battery(3, level: .critical))
        XCTAssertEqual(toasts, ["MX Master 4 battery is almost empty (3%). Charge it now."])
    }

    func testLevelsWithoutANumber() {
        report(battery(nil, level: .low))
        XCTAssertEqual(toasts, ["MX Master 4 battery is low."])
        report(battery(nil, level: .critical))
        XCTAssertEqual(toasts.last, "MX Master 4 battery is almost empty. Charge it now.")
        // A coarse reading leaves its number out.
        mice = [MouseDeviceFixtures.mxMaster4(id: "other", battery: MouseDeviceFixtures.battery(5, level: .critical, approximate: true))]
        watcher.check()
        XCTAssertEqual(toasts.last, "MX Master 4 battery is almost empty. Charge it now.")
    }

    func testEachMouseIsWatchedOnItsOwn() {
        mice = [
            MouseDeviceFixtures.mxMaster4(battery: battery(8, level: .low)),
            MouseDeviceFixtures.mxMaster3S(battery: battery(9, level: .low)),
        ]
        watcher.check()
        XCTAssertEqual(toasts, ["MX Master 4 battery is low (8%).", "MX Master 3S battery is low (9%)."])
    }

    func testNothingKnownSaysNothing() {
        report(nil)
        report(battery(nil, level: .unknown))
        mice = []
        watcher.check()
        XCTAssertEqual(toasts, [])
    }

    func testRules() {
        XCTAssertEqual(BatteryWatcher.alert(for: battery(75)), BatteryWatcher.Alert.none)
        XCTAssertEqual(BatteryWatcher.alert(for: battery(15, level: .low)), .low, "the mouse's own level counts")
        XCTAssertEqual(BatteryWatcher.alert(for: battery(10)), .low)
        XCTAssertEqual(BatteryWatcher.alert(for: battery(5)), .critical)
        XCTAssertEqual(BatteryWatcher.alert(for: battery(8, level: .critical)), .critical)
        XCTAssertTrue(BatteryWatcher.isCharging(battery(5, charging: .chargingSlowly)))
        XCTAssertFalse(BatteryWatcher.isCharging(battery(5, charging: .problem)))
        XCTAssertTrue(BatteryWatcher.isRecovered(battery(30)))
        XCTAssertFalse(BatteryWatcher.isRecovered(battery(29)))
        XCTAssertFalse(BatteryWatcher.isRecovered(battery(nil, level: .good)), "the step right above low")
        XCTAssertTrue(BatteryWatcher.isRecovered(battery(nil, level: .full)))
    }

    /// Regression: a battery that reports only a level (no percentage) and hovers between
    /// low and good warned again at every dip. Only full or charging starts over.
    func testALevelOnlyBatteryAtTheLowEdgeWarnsOnce() {
        report(battery(nil, level: .low))
        report(battery(nil, level: .good))
        report(battery(nil, level: .low))
        report(battery(nil, level: .good))
        report(battery(nil, level: .low))
        XCTAssertEqual(toasts, ["MX Master 4 battery is low."])
        report(battery(nil, level: .low, charging: .charging))
        report(battery(nil, level: .low))
        XCTAssertEqual(toasts.count, 2, "charging starts over")
        report(battery(nil, level: .full))
        report(battery(nil, level: .low))
        XCTAssertEqual(toasts.count, 3, "full starts over")
    }

    /// It follows the mice's reports; it never asks them anything itself.
    func testItFollowsTheMouseStateNotification() {
        watcher.start()
        XCTAssertTrue(watcher.isWatching)
        mice = [MouseDeviceFixtures.mxMaster4(battery: battery(6, level: .low))]
        NotificationCenter.default.post(name: LogiCenter.mouseStateChanged, object: nil)
        XCTAssertEqual(toasts, ["MX Master 4 battery is low (6%)."])
        watcher.stop()
        XCTAssertFalse(watcher.isWatching)
        mice = [MouseDeviceFixtures.mxMaster4(battery: battery(4, level: .critical))]
        NotificationCenter.default.post(name: LogiCenter.mouseStateChanged, object: nil)
        XCTAssertEqual(toasts.count, 1)
    }

    func testTheSharedWatcherIsIdleUnderTests() {
        XCTAssertFalse(BatteryWatcher.shared.isWatching, "started only with the app's startup side effects")
    }
}

// MARK: - Low battery next to the icon

/// What stands next to the status icon for a list of mouse states, and what VoiceOver reads
/// for the item. No status item is made.
final class StatusItemBatteryBadgeTests: XCTestCase {

    private typealias Badge = StatusMenu.BatteryBadge

    private func battery(_ percent: Int?, level: LogiMouseDeviceState.Battery.Level = .good,
                         charging: LogiMouseDeviceState.Battery.Charging = .discharging,
                         approximate: Bool = false) -> LogiMouseDeviceState.Battery {
        return MouseDeviceFixtures.battery(percent, level: level, charging: charging, approximate: approximate)
    }

    private func badge(_ batteries: LogiMouseDeviceState.Battery?...) -> Badge {
        let mice = batteries.enumerated().map { index, battery in
            MouseDeviceFixtures.mxMaster4(id: "mouse\(index)", battery: battery)
        }
        return StatusMenu.batteryBadge(for: mice)
    }

    private let plain = Badge(title: "", accessibilityLabel: "Scrollio")

    func testNothingWhileNoMouseRunsLow() {
        XCTAssertEqual(StatusMenu.batteryBadge(for: []), plain)
        XCTAssertEqual(Badge.plain, plain)
        XCTAssertEqual(badge(battery(75)), plain)
        XCTAssertEqual(badge(battery(11)), plain, "just above the low mark")
        XCTAssertEqual(badge(nil), plain, "not reported yet")
        XCTAssertEqual(badge(battery(nil, level: .unknown)), plain)
        XCTAssertEqual(badge(battery(nil, level: .good)), plain)
    }

    func testALowMouseShowsItsPercentage() {
        XCTAssertEqual(badge(battery(8, level: .low)), Badge(title: "8%", accessibilityLabel: "Scrollio, mouse battery 8%"))
        XCTAssertEqual(badge(battery(10)).title, "10%", "at the low mark")
        XCTAssertEqual(badge(battery(3, level: .critical)).title, "3%")
        XCTAssertEqual(badge(battery(15, level: .low)).title, "15%", "the mouse's own level counts, as for the warnings")
        // A charging problem is not charging.
        XCTAssertEqual(badge(battery(8, level: .low, charging: .problem)).title, "8%")
    }

    /// Charging, or charged again: it goes.
    func testChargingOrRecoveredShowsNothing() {
        for charging: LogiMouseDeviceState.Battery.Charging in [.charging, .chargingSlowly, .almostFull, .full] {
            XCTAssertEqual(badge(battery(8, level: .low, charging: charging)), plain, "\(charging)")
        }
        XCTAssertEqual(badge(battery(nil, level: .critical, charging: .charging)), plain)
        XCTAssertEqual(badge(battery(40)), plain)
    }

    /// A mouse that reports only a level, or coarse steps: a word, not a number.
    func testWithoutAnExactNumberItSaysLow() {
        let low = Badge(title: "Low", accessibilityLabel: "Scrollio, mouse battery low")
        XCTAssertEqual(badge(battery(nil, level: .low)), low)
        XCTAssertEqual(badge(battery(nil, level: .critical)), low)
        XCTAssertEqual(badge(battery(5, level: .critical, approximate: true)), low)
    }

    /// Several mice: the emptiest one that is not charging.
    func testTheLowestOfSeveralMice() {
        XCTAssertEqual(badge(battery(9, level: .low), battery(6, level: .low)).title, "6%")
        XCTAssertEqual(badge(battery(75), battery(7, level: .low)).title, "7%")
        XCTAssertEqual(badge(battery(4, level: .critical, charging: .charging), battery(9, level: .low)).title, "9%",
                       "the charging one does not count")
        XCTAssertEqual(badge(battery(nil, level: .critical), battery(8, level: .low)).title, "Low", "almost empty first")
        XCTAssertEqual(badge(battery(4, level: .critical), battery(nil, level: .critical)).title, "4%", "a number first")
        XCTAssertEqual(badge(battery(nil, level: .low), battery(9, level: .low)).title, "9%")
        XCTAssertEqual(badge(nil, battery(75), battery(nil, level: .unknown)), plain)
    }

    /// One mouse going through a day: the badge follows each report, and leaves when the
    /// mouse charges or disconnects.
    func testItFollowsTheReports() {
        XCTAssertEqual(badge(battery(12)).title, "")
        XCTAssertEqual(badge(battery(10, level: .low)).title, "10%")
        XCTAssertEqual(badge(battery(9, level: .low)).title, "9%")
        XCTAssertEqual(badge(battery(9, level: .low, charging: .charging)).title, "", "plugged in")
        XCTAssertEqual(badge(battery(9, level: .low)).title, "9%", "unplugged while still low")
        XCTAssertEqual(StatusMenu.batteryBadge(for: []).title, "", "disconnected")
    }
}

// MARK: - Window names

/// The diagnostic windows are named like the items that open them.
final class SecondaryWindowNamingTests: XCTestCase {

    func testTheScrollMonitorWindow() throws {
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: MonitorWindowController.self))
        let controller = try XCTUnwrap(
            storyboard.instantiateController(withIdentifier: WINDOW_IDENTIFIER.monitorWindowController) as? MonitorWindowController
        )
        let window = try XCTUnwrap(controller.window)
        addTeardownBlock { controller.close() }
        XCTAssertEqual(window.title, "Scroll Monitor")
        XCTAssertFalse(window.isVisible)
    }

    func testTheNamesOfTheDiagnostics() {
        XCTAssertEqual(NSLocalizedString("logitech-diagnostics-title", comment: ""), "Logitech Diagnostics")
        XCTAssertEqual(NSLocalizedString("scroll-monitor-title", comment: ""), "Scroll Monitor")
    }

    func testToastsWithoutJargon() {
        let name = "Back"
        let texts = [
            String(format: NSLocalizedString("logi_ble_hidpp_unstable_toast", comment: ""), name),
            String(format: NSLocalizedString("logi_hidpp_contention_toast", comment: ""), name),
            String(format: NSLocalizedString("logi_ble_contention_standard_mouse_alias_toast", comment: ""), name),
            String(format: NSLocalizedString("openTargetScriptNotExecutable", comment: ""), "build.sh"),
        ]
        XCTAssertEqual(texts[0], "Back may stop working while Logi Options+ runs. The receiver is more reliable.")
        XCTAssertEqual(texts[1], "Logi Options+ keeps taking over Back.")
        XCTAssertEqual(texts[3], "Script \"build.sh\" can't run: it isn't marked as executable.")
        for text in texts {
            for jargon in ["HID++", "BLE", "Bolt", "Unifying", "chmod", "capture"] {
                XCTAssertFalse(text.contains(jargon), "\(jargon) in \(text)")
            }
        }
    }
}
