//
//  StatusMenuTests.swift
//  MosTests
//
//  The menu of the status-bar item (what it lists with and without Accessibility access,
//  with Option held, paused, with batteries, and what its items do), the run state behind
//  "Pause Scrollio" (AppRunController), the low-battery warnings (BatteryWatcher), the names
//  of the windows the menu opens, and the window a reopened app shows. Nothing is shown on
//  screen, no status item is made, no event tap starts and no mouse is asked.
//

import XCTest
@testable import Mos_Debug

final class StatusMenuTests: XCTestCase {

    /// One row of the menu as the user reads it.
    private struct Row: Equatable, CustomStringConvertible {
        let title: String
        let shortcut: String
        let enabled: Bool

        static let separator = Row(title: "—")

        init(title: String, shortcut: String = "", enabled: Bool = true) {
            self.title = title
            self.shortcut = shortcut
            self.enabled = enabled
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
            self.init(title: item.title, shortcut: shortcut, enabled: enabled)
        }

        var description: String {
            return "\(title)\(shortcut.isEmpty ? "" : " [\(shortcut)]")\(enabled ? "" : " (disabled)")"
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
        batteries: [StatusMenu.Battery] = []
    ) -> StatusMenu.State {
        return StatusMenu.State(hasAccess: access, isPaused: paused, showsDiagnostics: diagnostics, batteries: batteries)
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
        _ = menu(state(diagnostics: true, batteries: StatusMenu.batteries(from: [MouseDeviceFixtures.mxMaster4()])))
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

    /// A start that fails half-way (an event tap could not be created) stops whatever did
    /// start, so no tap stays installed while the cores count as stopped, and tries again.
    func testAStartThatFailsHalfWayStopsEverythingAndTriesAgain() {
        let world = World()
        world.tapsStart = false
        let controller = make(world)
        controller.start()
        XCTAssertEqual(world.log, ["start", "stop"])
        XCTAssertFalse(controller.coresActive)
        XCTAssertTrue(controller.isWaitingForAccess, "a timer tries again")
        XCTAssertEqual(controller.recoveryTimer?.timeInterval, AppRunController.launchRecoveryInterval)

        // A permission-lost report from the failing tap changes nothing more.
        controller.accessWasLost()
        XCTAssertEqual(world.log, ["start", "stop"])

        world.tapsStart = true
        controller.accessibilityPermissionWasGranted()   // the timer's next look, now
        XCTAssertEqual(world.log, ["start", "stop", "start"])
        XCTAssertTrue(controller.coresActive)
        XCTAssertFalse(controller.isWaitingForAccess)
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

    func testTheToastText() {
        XCTAssertEqual(
            NSLocalizedString("toast-accessibility-lost", comment: ""),
            "Scrollio is paused: Accessibility access was turned off."
        )
    }

    // MARK: - Reopening the app

    /// Opening the app again (also with the menu bar icon hidden) always leads somewhere.
    func testReopeningShowsTheSettingsOrTheWelcomeGuide() {
        XCTAssertEqual(AppDelegate.windowForReopen(hasAccess: true), WINDOW_IDENTIFIER.preferencesWindowController)
        XCTAssertEqual(AppDelegate.windowForReopen(hasAccess: false), WINDOW_IDENTIFIER.introductionWindowController)
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
        XCTAssertTrue(BatteryWatcher.isRecovered(battery(nil, level: .good)))
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
        XCTAssertEqual(NSLocalizedString("mouse-diagnostics-button", comment: ""), "Logitech Diagnostics…")
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
