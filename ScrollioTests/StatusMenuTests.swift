//
//  StatusMenuTests.swift
//  MosTests
//
//  The menu of the status-bar item (what it lists with and without Accessibility access,
//  with Option held, paused (until resumed, or until a time), with batteries, with
//  "Smooth Scrolling in …" for the app in
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
        /// A section header: the title of the group under it.
        let header: Bool

        static let separator = Row(title: "—")

        init(title: String, shortcut: String = "", enabled: Bool = true, checked: Bool = false, header: Bool = false) {
            self.title = title
            self.shortcut = shortcut
            self.enabled = enabled
            self.checked = checked
            self.header = header
        }

        /// The title at the top of the menu while Scrollio does not work.
        static func title(_ text: String) -> Row {
            return Row(title: text, enabled: false, header: true)
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
            // AppKit enables an item whose target implements its action (autoenablesItems),
            // and one that opens a submenu.
            let enabled = item.hasSubmenu
                || item.action.map { action in (item.target as? NSObject)?.responds(to: action) ?? false } ?? false
            self.init(title: item.title, shortcut: shortcut, enabled: enabled, checked: item.state == .on,
                      header: item.isSectionHeader)
        }

        var description: String {
            return "\(header ? "# " : "")\(checked ? "✓ " : "")\(title)\(shortcut.isEmpty ? "" : " [\(shortcut)]")\(enabled ? "" : " (disabled)")"
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
        actions.pause = { calls.log.append("pause \($0)") }
        actions.resume = { calls.log.append("resume") }
        actions.tryAgain = { calls.log.append("try again") }
        actions.openAccessibilitySettings = { calls.log.append("accessibility settings") }
        actions.showMouseSettings = { calls.log.append("mouse") }
        actions.toggleAppSmoothing = { calls.log.append("smoothing \($0.name)") }
        actions.showApplicationSettings = { calls.log.append("app settings \($0.name)") }
        actions.showScrollMonitor = { calls.log.append("monitor") }
        actions.showDiagnostics = { calls.log.append("diagnostics") }
        actions.showTestToasts = { calls.log.append("toasts") }
        actions.checkForUpdates = { calls.log.append("updates") }
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
        batteries: [StatusMenu.Battery] = [], appSmoothing: StatusMenu.AppSmoothingItem? = nil,
        appSettings: StatusMenu.AppSettingsItem? = nil,
        updates: StatusMenu.Updates = .none, startProblem: StatusMenu.StartProblem? = nil,
        pauseEnd: Date? = nil
    ) -> StatusMenu.State {
        return StatusMenu.State(
            hasAccess: access, isPaused: paused, showsDiagnostics: diagnostics, batteries: batteries,
            appSmoothing: appSmoothing, appSettings: appSettings, updates: updates, startProblem: startProblem,
            pauseEnd: pauseEnd
        )
    }

    /// 14:30 on 12 November 2026 in Ljubljana (13:30 UTC): the end of a pause in the tests.
    private static let pauseEnd = Date(timeIntervalSince1970: 1_794_490_200)

    /// The title of a pause that ends at `end`, as the Mac of this run writes the time.
    private static func pausedUntilTitle(_ end: Date) -> String {
        return String(format: NSLocalizedString("status-menu-title-paused-until", comment: ""), StatusMenu.pauseEndText(end))
    }

    private static let pausedTitle = Row.title("Scrollio is paused")
    private static let needsAccessTitle = Row.title("Scrollio needs Accessibility access")
    private static let couldNotStartTitle = Row.title("Scrollio couldn't start and is trying again")

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

    /// While Scrollio works the menu has no title: Pause | Settings | Quit.
    func testWithAccess() {
        XCTAssertEqual(rows(state()), [
            Row(title: "Pause Scrollio"),
            Row(title: "Pause For"),
            .separator,
            Row(title: "Settings…", shortcut: "⌘,"),
            .separator,
            Row(title: "Quit Scrollio", shortcut: "⌘Q"),
        ])
    }

    /// The groups: the batteries | the app in front and Pause | Settings and the check for
    /// updates | Quit.
    func testTheGroups() throws {
        let battery = StatusMenu.Battery(title: "MX Master 4: 75%", symbolName: "battery.75percent")
        let smoothing = try XCTUnwrap(safariItem(.usesScrollingSettings))
        XCTAssertEqual(rows(state(batteries: [battery], appSmoothing: smoothing, updates: .check(enabled: true))), [
            Row(title: "MX Master 4: 75%"),
            .separator,
            Row(title: "Smooth Scrolling in Safari", checked: true),
            Row(title: "Pause Scrollio"),
            Row(title: "Pause For"),
            .separator,
            Row(title: "Settings…", shortcut: "⌘,"),
            Row(title: "Check for Updates…"),
            .separator,
            Row(title: "Quit Scrollio", shortcut: "⌘Q"),
        ])
    }

    // MARK: - Updates

    /// A copy that updates itself offers the check under Settings.
    func testCheckForUpdatesFollowsSettings() throws {
        XCTAssertEqual(rows(state(updates: .check(enabled: true))), [
            Row(title: "Pause Scrollio"),
            Row(title: "Pause For"),
            .separator,
            Row(title: "Settings…", shortcut: "⌘,"),
            Row(title: "Check for Updates…"),
            .separator,
            Row(title: "Quit Scrollio", shortcut: "⌘Q"),
        ])
        try choose("Check for Updates…", in: menu(state(updates: .check(enabled: true))))
        XCTAssertEqual(calls.log, ["updates"])
    }

    /// While a check runs in the background the item is dimmed.
    func testCheckForUpdatesIsDimmedWhileACheckRuns() {
        XCTAssertEqual(rows(state(updates: .check(enabled: false))), [
            Row(title: "Pause Scrollio"),
            Row(title: "Pause For"),
            .separator,
            Row(title: "Settings…", shortcut: "⌘,"),
            Row(title: "Check for Updates…", enabled: false),
            .separator,
            Row(title: "Quit Scrollio", shortcut: "⌘Q"),
        ])
    }

    /// A found update that waits for an answer is the first thing in the menu, above the
    /// batteries; it takes the place of "Check for Updates…".
    func testAWaitingUpdateLeadsTheMenu() throws {
        let battery = StatusMenu.Battery(title: "MX Master 4: 75%", symbolName: "battery.75percent")
        let waiting = state(batteries: [battery], updates: .waiting(version: "1.1.0"))
        XCTAssertEqual(rows(waiting), [
            Row(title: "Update to Scrollio 1.1.0…"),
            .separator,
            Row(title: "MX Master 4: 75%"),
            .separator,
            Row(title: "Pause Scrollio"),
            Row(title: "Pause For"),
            .separator,
            Row(title: "Settings…", shortcut: "⌘,"),
            .separator,
            Row(title: "Quit Scrollio", shortcut: "⌘Q"),
        ])
        try choose("Update to Scrollio 1.1.0…", in: menu(waiting))
        XCTAssertEqual(calls.log, ["updates"], "the same call brings the updater's window to the front")
    }

    /// An update may be what a copy without the access needs.
    func testWithoutAccessTheUpdaterIsStillThere() {
        XCTAssertEqual(rows(state(access: false, updates: .check(enabled: true))), [
            Self.needsAccessTitle,
            Row(title: "Allow Accessibility Access…"),
            .separator,
            Row(title: "Check for Updates…"),
            .separator,
            Row(title: "Quit Scrollio", shortcut: "⌘Q"),
        ])
        // The title and its action first, the waiting update under them.
        XCTAssertEqual(rows(state(access: false, updates: .waiting(version: "2.0"))), [
            Self.needsAccessTitle,
            Row(title: "Allow Accessibility Access…"),
            .separator,
            Row(title: "Update to Scrollio 2.0…"),
            .separator,
            Row(title: "Quit Scrollio", shortcut: "⌘Q"),
        ])
    }

    func testTheMenuReadsTheUpdaterLikeThis() {
        XCTAssertEqual(StatusMenu.updates(from: UpdateStatus()), .none)
        XCTAssertEqual(StatusMenu.updates(from: UpdateStatus(availability: .wrongPlace, canCheck: true)), .none)
        XCTAssertEqual(StatusMenu.updates(from: UpdateStatus(availability: .failed, canCheck: true)), .none)
        XCTAssertEqual(StatusMenu.updates(from: UpdateStatus(availability: .available, canCheck: true)), .check(enabled: true))
        XCTAssertEqual(StatusMenu.updates(from: UpdateStatus(availability: .available, canCheck: false)), .check(enabled: false))
        XCTAssertEqual(
            StatusMenu.updates(from: UpdateStatus(availability: .available, canCheck: true, waitingVersion: "1.1.0")),
            .waiting(version: "1.1.0")
        )
        // The test host was not built by the release script: its live menu has no updater.
        XCTAssertEqual(StatusItemManager.liveState().updates, .none)
    }

    /// Paused: the title, Resume under it, then the rest as always.
    func testPaused() {
        XCTAssertEqual(rows(state(paused: true)), [
            Self.pausedTitle,
            Row(title: "Resume Scrollio"),
            .separator,
            Row(title: "Settings…", shortcut: "⌘,"),
            .separator,
            Row(title: "Quit Scrollio", shortcut: "⌘Q"),
        ])
        // A waiting update under the title's group. No battery lines: a pause stops the
        // Logitech sessions (LogiCenter.stop), so no mouse reports one.
        XCTAssertEqual(rows(state(paused: true, updates: .waiting(version: "1.1.0"))), [
            Self.pausedTitle,
            Row(title: "Resume Scrollio"),
            .separator,
            Row(title: "Update to Scrollio 1.1.0…"),
            .separator,
            Row(title: "Settings…", shortcut: "⌘,"),
            .separator,
            Row(title: "Quit Scrollio", shortcut: "⌘Q"),
        ])
    }

    /// A pause that ends by itself says until when, in the title and in the icon's tooltip
    /// (the title and a full stop); the rest of the menu is a paused menu's.
    func testPausedForATimeSaysUntilWhen() {
        let end = Self.pauseEnd
        XCTAssertEqual(rows(state(paused: true, pauseEnd: end)), [
            Row.title(Self.pausedUntilTitle(end)),
            Row(title: "Resume Scrollio"),
            .separator,
            Row(title: "Settings…", shortcut: "⌘,"),
            .separator,
            Row(title: "Quit Scrollio", shortcut: "⌘Q"),
        ])
        XCTAssertEqual(
            StatusMenu.IconLook(hasAccess: true, coresActive: false, isPaused: true, pauseEnd: end, canPostEvents: true).toolTip,
            Self.pausedUntilTitle(end) + "."
        )
        XCTAssertEqual(StatusMenu.titleText(.paused, pauseEnd: end), Self.pausedUntilTitle(end))
        XCTAssertEqual(StatusMenu.titleText(.paused, pauseEnd: nil), "Scrollio is paused")
        // Only the pause has a time; without the access the menu says only that.
        XCTAssertEqual(StatusMenu.titleText(.needsAccess, pauseEnd: end), "Scrollio needs Accessibility access")
        XCTAssertEqual(StatusMenu.titleText(.couldNotStart, pauseEnd: end), "Scrollio couldn't start and is trying again")
        XCTAssertEqual(rows(state(access: false, paused: true, pauseEnd: end)).first, Self.needsAccessTitle)
        XCTAssertEqual(
            StatusMenu.IconLook(hasAccess: false, coresActive: false, isPaused: true, pauseEnd: end, canPostEvents: true).toolTip,
            "Scrollio needs Accessibility access."
        )

        // The time alone, as the Mac writes it: 24 hours, or 12 with AM and PM (macOS puts
        // a narrow no-break space between them, so the two halves are looked at apart).
        let ljubljana = TimeZone(identifier: "Europe/Ljubljana")!
        XCTAssertEqual(StatusMenu.pauseEndText(end, locale: Locale(identifier: "en_GB"), timeZone: ljubljana), "14:30")
        let american = StatusMenu.pauseEndText(end, locale: Locale(identifier: "en_US"), timeZone: ljubljana)
        XCTAssertTrue(american.hasPrefix("2:30"), american)
        XCTAssertTrue(american.hasSuffix("PM"), american)
        // Another time zone: the same moment, read there.
        XCTAssertEqual(
            StatusMenu.pauseEndText(end, locale: Locale(identifier: "en_GB"), timeZone: TimeZone(identifier: "UTC")!), "13:30"
        )
    }

    /// "Pause Scrollio" pauses at one click, until "Resume Scrollio". Right under it "Pause
    /// For" opens the lengths of a pause that ends by itself; it has no action of its own,
    /// no separator and no key equivalents. Both wherever Pause is offered: while Scrollio
    /// works and under both start problems; never while paused or without the access.
    func testPauseForOffersTwoLengthsUnderPause() throws {
        for (name, shown) in [
            ("on", state()), ("retrying", state(startProblem: .retrying)), ("tap off", state(startProblem: .tapOff)),
        ] {
            let built = menu(shown)
            let index = try XCTUnwrap(built.items.firstIndex { $0.title == "Pause Scrollio" }, name)
            let pause = built.items[index]
            XCTAssertNil(pause.submenu, name)
            XCTAssertEqual(pause.action, #selector(StatusMenuActions.pauseClicked(_:)), name)
            let parent = built.items[index + 1]
            XCTAssertEqual(parent.title, "Pause For", name)
            // Only AppKit's own action of an item that opens a submenu: nothing of ours.
            XCTAssertEqual(parent.action, #selector(NSMenu.submenuAction(_:)), name)
            XCTAssertFalse(parent.target === actions, name)
            let lengths = try XCTUnwrap(parent.submenu, name)
            XCTAssertEqual(lengths.items.map(\.title), ["15 Minutes", "1 Hour"], name)
            XCTAssertEqual(lengths.items.map(\.keyEquivalent), ["", ""], name)
            XCTAssertEqual(lengths.items.map(Row.init), [Row(title: "15 Minutes"), Row(title: "1 Hour")], name)

            calls.log = []
            try choose("Pause Scrollio", in: built)
            try choose("15 Minutes", in: lengths)
            try choose("1 Hour", in: lengths)
            XCTAssertEqual(calls.log, ["pause untilResumed", "pause fifteenMinutes", "pause oneHour"], name)
        }
        for shown in [state(paused: true), state(paused: true, pauseEnd: Self.pauseEnd), state(access: false)] {
            XCTAssertFalse(menu(shown).items.contains { $0.title == "Pause Scrollio" || $0.hasSubmenu })
        }
        XCTAssertEqual(StatusMenu.pauseLengths.map(\.length), [.fifteenMinutes, .oneHour])
        XCTAssertEqual(AppRunController.PauseLength.fifteenMinutes.seconds, 900)
        XCTAssertEqual(AppRunController.PauseLength.oneHour.seconds, 3600)
        XCTAssertNil(AppRunController.PauseLength.untilResumed.seconds)
    }

    /// Each item says what it does. Regression in the making: one "toggle" behind both
    /// items would pause again from "Resume Scrollio" in a menu left open across the end of
    /// a pause that ends by itself.
    func testResumeNeverPauses() throws {
        for shown in [state(paused: true), state(paused: true, pauseEnd: Self.pauseEnd)] {
            let built = menu(shown)
            let resume = try XCTUnwrap(built.items.first { $0.title == "Resume Scrollio" })
            XCTAssertEqual(resume.action, #selector(StatusMenuActions.resumeClicked(_:)))
            calls.log = []
            try choose("Resume Scrollio", in: built)
            XCTAssertEqual(calls.log, ["resume"])
        }
        XCTAssertFalse(actions.responds(to: NSSelectorFromString("togglePauseClicked:")))
        // The app's own actions: Resume on a controller that is not paused changes nothing
        // (the shared one is idle under tests and stays so).
        XCTAssertFalse(AppRunController.shared.isPaused)
        StatusMenuActions().resume()
        XCTAssertFalse(AppRunController.shared.isPaused)
        XCTAssertFalse(AppRunController.shared.coresActive)
    }

    /// A start that failed: the title, "Try Again Now", and Pause (which stops the tries).
    func testCouldNotStartOffersToTryAgainNow() throws {
        XCTAssertEqual(rows(state(startProblem: .retrying)), [
            Self.couldNotStartTitle,
            Row(title: "Try Again Now"),
            Row(title: "Pause Scrollio"),
            Row(title: "Pause For"),
            .separator,
            Row(title: "Settings…", shortcut: "⌘,"),
            .separator,
            Row(title: "Quit Scrollio", shortcut: "⌘Q"),
        ])
        try choose("Try Again Now", in: menu(state(startProblem: .retrying)))
        XCTAssertEqual(calls.log, ["try again"])
    }

    /// An event tap kept off for a while comes back by itself: the title over Pause, no
    /// "Try Again Now" (the wait keeps input usable).
    func testATapKeptOffSaysSoWithoutTryingAgain() {
        let battery = StatusMenu.Battery(title: "MX Master 4: 75%", symbolName: "battery.75percent")
        XCTAssertEqual(rows(state(batteries: [battery], startProblem: .tapOff)), [
            Self.couldNotStartTitle,
            Row(title: "Pause Scrollio"),
            Row(title: "Pause For"),
            .separator,
            Row(title: "MX Master 4: 75%"),
            .separator,
            Row(title: "Settings…", shortcut: "⌘,"),
            .separator,
            Row(title: "Quit Scrollio", shortcut: "⌘Q"),
        ])
    }

    /// Without the right to post events (after some macOS updates the system drops what
    /// Scrollio posts and says nothing) Scrollio runs but smooths nothing: the menu says so,
    /// with the way out (System Settings › Privacy & Security › Accessibility) and Pause.
    func testWithoutTheRightToPostEventsTheMenuSaysItCantSendScrollEvents() throws {
        XCTAssertEqual(StatusMenu.startProblem(coresActive: true, startFailed: false, tapRestartsThrottled: false,
                                               canPostEvents: false), .cannotPostEvents)
        XCTAssertNil(StatusMenu.startProblem(coresActive: false, startFailed: false, tapRestartsThrottled: false,
                                             canPostEvents: false), "not running (paused, asleep): not this")
        XCTAssertEqual(StatusMenu.startProblem(coresActive: false, startFailed: true, tapRestartsThrottled: false,
                                               canPostEvents: false), .retrying)
        XCTAssertEqual(StatusMenu.startProblem(coresActive: true, startFailed: false, tapRestartsThrottled: true,
                                               canPostEvents: false), .tapOff, "a tap kept off first: it comes back by itself")
        XCTAssertEqual(StatusMenu.title(hasAccess: true, isPaused: false, startProblem: .cannotPostEvents), .cannotPostEvents)
        XCTAssertEqual(StatusMenu.title(hasAccess: true, isPaused: true, startProblem: .cannotPostEvents), .paused)
        XCTAssertEqual(StatusMenu.title(hasAccess: false, isPaused: false, startProblem: .cannotPostEvents), .needsAccess)

        XCTAssertEqual(rows(state(startProblem: .cannotPostEvents)), [
            Row.title("Scrollio can't send scroll events"),
            Row(title: "Open Accessibility Settings…"),
            Row(title: "Pause Scrollio"),
            Row(title: "Pause For"),
            .separator,
            Row(title: "Settings…", shortcut: "⌘,"),
            .separator,
            Row(title: "Quit Scrollio", shortcut: "⌘Q"),
        ])
        try choose("Open Accessibility Settings…", in: menu(state(startProblem: .cannotPostEvents)))
        XCTAssertEqual(calls.log, ["accessibility settings"])

        let look = StatusMenu.IconLook(hasAccess: true, coresActive: true, isPaused: false, canPostEvents: false)
        XCTAssertTrue(look.appearsDisabled)
        XCTAssertEqual(look.toolTip, "Scrollio can't send scroll events.")
        // The live menu reads the shared poster: under tests the right is there.
        XCTAssertNil(StatusItemManager.liveState().startProblem)
    }

    /// The title is there only while Scrollio does not work, always first, a section
    /// header; and it says what the icon's tooltip says, in every state (regression: paused
    /// without the access, the menu said "needs access" and the tooltip "paused").
    func testTheTitleOnlyWhileScrollioDoesNotWork() {
        let battery = StatusMenu.Battery(title: "MX Master 4: 75%", symbolName: "battery.75percent")
        // A pause until resumed, and one that ends by itself.
        let pauses: [(paused: Bool, end: Date?)] = [(false, nil), (true, nil), (true, Self.pauseEnd)]
        for access in [true, false] {
            for (paused, end) in pauses {
                for problem in [nil, .retrying, .tapOff, .cannotPostEvents] as [StatusMenu.StartProblem?] {
                    for updates in [StatusMenu.Updates.none, .check(enabled: true), .waiting(version: "1.1.0")] {
                        let shown = state(access: access, paused: paused, diagnostics: true, batteries: [battery],
                                          updates: updates, startProblem: problem, pauseEnd: end)
                        let built = menu(shown)
                        let headers = built.items.filter(\.isSectionHeader)
                        let works = access && !paused && problem == nil
                        let label = "access \(access), paused \(paused) \(String(describing: end)), \(String(describing: problem)), \(updates)"
                        XCTAssertEqual(headers.count, works ? 0 : 1, label)
                        XCTAssertEqual(StatusMenu.title(for: shown) == nil, works, label)
                        guard !works else { continue }
                        XCTAssertTrue(built.items[0].isSectionHeader, label)
                        XCTAssertFalse(built.items[1].isSeparatorItem, "an action under the title: \(label)")
                        let tooltip = StatusMenu.IconLook(
                            hasAccess: access, coresActive: access && problem != .retrying && !paused, isPaused: paused,
                            startFailed: problem == .retrying, tapRestartsThrottled: problem == .tapOff, pauseEnd: end,
                            canPostEvents: problem != .cannotPostEvents
                        ).toolTip
                        XCTAssertEqual(built.items[0].title + ".", tooltip, label)
                        // Without the access the menu offers only the way to it, and says so.
                        if !access {
                            XCTAssertEqual(built.items[0].title, "Scrollio needs Accessibility access", label)
                        }
                    }
                }
            }
        }
    }

    /// "Couldn't start" by the icon's rule: a failed start while the cores are off, or a tap
    /// kept off while they run.
    func testTheStartProblemFollowsTheIconsRule() {
        XCTAssertNil(StatusMenu.startProblem(coresActive: true, startFailed: false, tapRestartsThrottled: false, canPostEvents: true))
        XCTAssertNil(StatusMenu.startProblem(coresActive: false, startFailed: false, tapRestartsThrottled: false, canPostEvents: true),
                     "waiting for the access, asleep or another user: not a start problem")
        XCTAssertNil(StatusMenu.startProblem(coresActive: false, startFailed: false, tapRestartsThrottled: true, canPostEvents: true))
        XCTAssertEqual(StatusMenu.startProblem(coresActive: false, startFailed: true, tapRestartsThrottled: false, canPostEvents: true), .retrying)
        XCTAssertEqual(StatusMenu.startProblem(coresActive: false, startFailed: true, tapRestartsThrottled: true, canPostEvents: true), .retrying)
        XCTAssertEqual(StatusMenu.startProblem(coresActive: true, startFailed: false, tapRestartsThrottled: true, canPostEvents: true), .tapOff)
        // Under tests nothing fails and nothing is throttled: the live menu has no title for it.
        XCTAssertNil(StatusItemManager.liveState().startProblem)
    }

    func testWithoutAccess() {
        // Paused or not, batteries or not: only the way to the access and Quit.
        for paused in [false, true] {
            for diagnostics in [false, true] {
                let battery = StatusMenu.Battery(title: "MX Master 4: 75%", symbolName: "battery.75percent")
                XCTAssertEqual(rows(state(access: false, paused: paused, diagnostics: diagnostics, batteries: [battery])), [
                    Self.needsAccessTitle,
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
            Row(title: "Pause For"),
            .separator,
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
            Row(title: "Pause For"),
            .separator,
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

    /// One line per mouse, in a group of their own at the top (under the title, when there is
    /// one); a click on a line opens Settings › Mouse.
    func testOneBatteryLinePerMouseThatOpensTheMousePane() throws {
        let batteries = StatusMenu.batteries(from: [
            MouseDeviceFixtures.mxMaster4(),
            MouseDeviceFixtures.mxMaster3S(battery: MouseDeviceFixtures.battery(40, charging: .charging)),
        ])
        let built = menu(state(batteries: batteries))
        XCTAssertEqual(built.items.map(Row.init), [
            Row(title: "MX Master 4: 75%"),
            Row(title: "MX Master 3S: 40%, charging"),
            .separator,
            Row(title: "Pause Scrollio"),
            Row(title: "Pause For"),
            .separator,
            Row(title: "Settings…", shortcut: "⌘,"),
            .separator,
            Row(title: "Quit Scrollio", shortcut: "⌘Q"),
        ])
        XCTAssertNotNil(built.items[0].image, "a battery symbol")
        XCTAssertEqual(built.items[0].tag, StatusMenu.batteryTag)
        for title in ["MX Master 4: 75%", "MX Master 3S: 40%, charging"] {
            calls.log = []
            try choose(title, in: built)
            XCTAssertEqual(calls.log, ["mouse"], title)
        }
        // Under the title's group: an event tap kept off is the one title while the Logitech
        // sessions run (paused and a failed start stop them, and the mice with them).
        XCTAssertEqual(rows(state(batteries: batteries, startProblem: .tapOff)).map(\.title), [
            "Scrollio couldn't start and is trying again", "Pause Scrollio", "Pause For", "—",
            "MX Master 4: 75%", "MX Master 3S: 40%, charging", "—",
            "Settings…", "—", "Quit Scrollio",
        ])
    }

    /// The pane a battery line opens is the Mouse pane, by its identifier.
    func testTheMousePaneIsTheOneTheBatteryLinesOpen() {
        XCTAssertEqual(MousePreferencesViewController.tabIdentifier, "mouse")
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
        XCTAssertEqual(built.items.count, 8)

        // A mouse that came or went waits for the next opening.
        StatusMenu.updateBatteryItems(in: built, with: [])
        XCTAssertEqual(built.items[0].title, "MX Master 4: 74%")
    }

    func testNoIconsNoLeadingSpacesNoRawKeys() {
        let battery = StatusMenu.Battery(title: "MX Master 4: 75%", symbolName: "battery.75percent")
        for access in [true, false] {
            for paused in [true, false] {
              for problem in [nil, .retrying, .tapOff] as [StatusMenu.StartProblem?] {
                let built = menu(state(access: access, paused: paused, diagnostics: true, batteries: [battery],
                                       startProblem: problem))
                for item in built.items where !item.isSeparatorItem {
                    XCTAssertEqual(item.title, item.title.trimmingCharacters(in: .whitespaces), item.title)
                    XCTAssertFalse(item.title.contains("-menu-"), "\(item.title) shows the raw key")
                    XCTAssertFalse(item.title.hasPrefix("Debug"), item.title)
                    if item.tag != StatusMenu.batteryTag {
                        XCTAssertNil(item.image, item.title)
                    }
                    XCTAssertFalse(item.title.hasSuffix("."), "no full stop in a menu: \(item.title)")
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

    /// One item for the app in front, in Pause's group above it, checked while the app is
    /// smoothed.
    func testTheAppInFrontHasItsSmoothingItemAbovePause() throws {
        let checked = try XCTUnwrap(safariItem(.usesScrollingSettings))
        XCTAssertEqual(rows(state(appSmoothing: checked)), [
            Row(title: "Smooth Scrolling in Safari", checked: true),
            Row(title: "Pause Scrollio"),
            Row(title: "Pause For"),
            .separator,
            Row(title: "Settings…", shortcut: "⌘,"),
            .separator,
            Row(title: "Quit Scrollio", shortcut: "⌘Q"),
        ])
        // Under the battery lines; unchecked for an app that is not smoothed.
        let battery = StatusMenu.Battery(title: "MX Master 4: 75%", symbolName: "battery.75percent")
        let unchecked = try XCTUnwrap(safariItem(.own(smooth: false)))
        XCTAssertEqual(rows(state(batteries: [battery], appSmoothing: unchecked)), [
            Row(title: "MX Master 4: 75%"),
            .separator,
            Row(title: "Smooth Scrolling in Safari"),
            Row(title: "Pause Scrollio"),
            Row(title: "Pause For"),
            .separator,
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
                       ["Scrollio needs Accessibility access", "Allow Accessibility Access…", "—", "Quit Scrollio"])
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

    // MARK: - Settings for the app in front

    /// "Settings for Safari…" stands under "Smooth Scrolling in Safari", above Pause.
    func testSettingsForTheAppInFrontStandsUnderItsSmoothingItem() throws {
        let smoothing = try XCTUnwrap(safariItem(.usesScrollingSettings))
        let settings = try XCTUnwrap(StatusMenu.appSettingsItem(front: Self.safari, isScrollio: false))
        let battery = StatusMenu.Battery(title: "MX Master 4: 75%", symbolName: "battery.75percent")
        XCTAssertEqual(rows(state(batteries: [battery], appSmoothing: smoothing, appSettings: settings)), [
            Row(title: "MX Master 4: 75%"),
            .separator,
            Row(title: "Smooth Scrolling in Safari", checked: true),
            Row(title: "Settings for Safari…"),
            Row(title: "Pause Scrollio"),
            Row(title: "Pause For"),
            .separator,
            Row(title: "Settings…", shortcut: "⌘,"),
            .separator,
            Row(title: "Quit Scrollio", shortcut: "⌘Q"),
        ])
        // Without the smoothing item (smoothing is off everywhere, say) it is still there.
        XCTAssertEqual(rows(state(appSettings: settings)).prefix(3),
                       [Row(title: "Settings for Safari…"), Row(title: "Pause Scrollio"), Row(title: "Pause For")])
    }

    /// Paused, or unable to start, the app's settings can still be changed: the item stands
    /// alone where the app in front's group is, under the batteries; Pause or Resume stay
    /// under the title.
    func testSettingsForTheAppInFrontAlsoWhileScrollioDoesNotWork() throws {
        let settings = try XCTUnwrap(StatusMenu.appSettingsItem(front: Self.safari, isScrollio: false))
        XCTAssertEqual(rows(state(paused: true, appSettings: settings)), [
            Self.pausedTitle,
            Row(title: "Resume Scrollio"),
            .separator,
            Row(title: "Settings for Safari…"),
            .separator,
            Row(title: "Settings…", shortcut: "⌘,"),
            .separator,
            Row(title: "Quit Scrollio", shortcut: "⌘Q"),
        ])
        let battery = StatusMenu.Battery(title: "MX Master 4: 75%", symbolName: "battery.75percent")
        XCTAssertEqual(rows(state(batteries: [battery], appSettings: settings, startProblem: .retrying)), [
            Self.couldNotStartTitle,
            Row(title: "Try Again Now"),
            Row(title: "Pause Scrollio"),
            Row(title: "Pause For"),
            .separator,
            Row(title: "MX Master 4: 75%"),
            .separator,
            Row(title: "Settings for Safari…"),
            .separator,
            Row(title: "Settings…", shortcut: "⌘,"),
            .separator,
            Row(title: "Quit Scrollio", shortcut: "⌘Q"),
        ])
        // Without the access only the way to it.
        XCTAssertFalse(rows(state(access: false, appSettings: settings)).contains { $0.title.hasPrefix("Settings for") })
    }

    /// Any app in front with a path, but Scrollio itself; whether Scrollio runs or not. The
    /// name is whole, as in "Smooth Scrolling in …".
    func testTheSettingsItemIsForAnyAppButScrollio() throws {
        XCTAssertEqual(StatusMenu.appSettingsItem(front: Self.safari, isScrollio: false)?.title, "Settings for Safari…")
        XCTAssertNil(StatusMenu.appSettingsItem(front: nil, isScrollio: false))
        XCTAssertNil(StatusMenu.appSettingsItem(front: AppSmoothing.App(name: "Ghost", bundlePath: nil, executablePath: nil), isScrollio: false))
        XCTAssertNil(StatusMenu.appSettingsItem(front: Self.safari, isScrollio: true))
        XCTAssertNotNil(StatusMenu.appSettingsItem(front: AppSmoothing.App(name: "tool", bundlePath: nil, executablePath: "/usr/local/bin/tool"), isScrollio: false))
        let long = AppSmoothing.App(
            name: "Microsoft Visual Studio Code Insiders Edition With A Very Long Name",
            bundlePath: "/Applications/Long.app", executablePath: "/Applications/Long.app/Contents/MacOS/Long"
        )
        let smoothing = try XCTUnwrap(StatusMenu.appSmoothingItem(
            front: long, isScrollio: false, scrollingRuns: true, rule: .notListed, scrollingSmooth: true, limitedToListedApps: false
        ))
        let settings = try XCTUnwrap(StatusMenu.appSettingsItem(front: long, isScrollio: false))
        XCTAssertTrue(smoothing.title.hasSuffix(long.name))
        XCTAssertEqual(settings.title, String(format: NSLocalizedString("status-menu-app-settings", comment: ""), long.name))
        // The live menu names the app in front only with the access, and never Scrollio.
        if let live = StatusItemManager.liveAppSettingsItem() {
            XCTAssertNotEqual(live.app.executablePath, NSRunningApplication.current.executableURL?.path)
        }
    }

    /// A click shows the app's settings and changes nothing itself: no app is added.
    func testChoosingSettingsForAnAppShowsItsSettingsAndAddsNothing() throws {
        let stored = Options.shared.application.applications.count
        let settings = try XCTUnwrap(StatusMenu.appSettingsItem(front: Self.safari, isScrollio: false))
        let built = menu(state(appSettings: settings))
        XCTAssertEqual(calls.log, [], "building it does nothing")
        try choose("Settings for Safari…", in: built)
        XCTAssertEqual(calls.log, ["app settings Safari"])
        XCTAssertEqual(built.items.first?.representedObject as? AppSmoothing.App, Self.safari)
        XCTAssertEqual(Options.shared.application.applications.count, stored)
        XCTAssertNil(built.items.first?.image)
    }

    // MARK: - Actions

    func testWhatTheItemsDo() throws {
        let full = menu(state(diagnostics: true))
        for (title, call) in [
("Pause Scrollio", "pause untilResumed"), ("Settings…", "settings"), ("Scroll Monitor", "monitor"),
            ("Logitech Diagnostics", "diagnostics"), ("Test Toasts", "toasts"), ("Quit Scrollio", "quit"),
        ] {
            calls.log = []
            try choose(title, in: full)
            XCTAssertEqual(calls.log, [call], title)
        }
        calls.log = []
        try choose("Resume Scrollio", in: menu(state(paused: true)))
        XCTAssertEqual(calls.log, ["resume"])
        calls.log = []
        try choose("Allow Accessibility Access…", in: menu(state(access: false)))
        XCTAssertEqual(calls.log, ["guide"], "the Welcome Guide, not the system prompt")
        calls.log = []
        try choose("Try Again Now", in: menu(state(startProblem: .retrying)))
        XCTAssertEqual(calls.log, ["try again"])
        calls.log = []
        try choose("MX Master 4: 75%", in: menu(state(batteries: StatusMenu.batteries(from: [MouseDeviceFixtures.mxMaster4()]))))
        XCTAssertEqual(calls.log, ["mouse"])
    }

    func testBuildingTheMenuDoesNothing() {
        _ = menu(state(diagnostics: true, batteries: StatusMenu.batteries(from: [MouseDeviceFixtures.mxMaster4()]),
                       appSmoothing: safariItem(.usesScrollingSettings)))
        _ = menu(state(access: false))
        _ = menu(state(paused: true))
        _ = menu(state(paused: true, pauseEnd: Self.pauseEnd))
        _ = menu(state(startProblem: .retrying))
        _ = menu(state(startProblem: .tapOff))
        _ = menu(state(startProblem: .cannotPostEvents))
        XCTAssertEqual(calls.log, [])
    }

    // MARK: - Icon

    func testTheIconDimsWhilePausedOrWithoutAccess() {
        let running = StatusMenu.IconLook(hasAccess: true, coresActive: true, isPaused: false, canPostEvents: true)
        XCTAssertFalse(running.appearsDisabled)
        XCTAssertNil(running.toolTip)

        let paused = StatusMenu.IconLook(hasAccess: true, coresActive: false, isPaused: true, canPostEvents: true)
        XCTAssertTrue(paused.appearsDisabled)
        XCTAssertEqual(paused.toolTip, "Scrollio is paused.")

        let noAccess = StatusMenu.IconLook(hasAccess: false, coresActive: false, isPaused: false, canPostEvents: true)
        XCTAssertTrue(noAccess.appearsDisabled)
        XCTAssertEqual(noAccess.toolTip, "Scrollio needs Accessibility access.")

        // Regression: paused, then the access taken away: the menu's title says the access
        // is needed, and so does the tooltip (it said "paused").
        let pausedWithoutAccess = StatusMenu.IconLook(hasAccess: false, coresActive: false, isPaused: true, canPostEvents: true)
        XCTAssertTrue(pausedWithoutAccess.appearsDisabled)
        XCTAssertEqual(pausedWithoutAccess.toolTip, "Scrollio needs Accessibility access.")

        // The access back, the cores not started yet: the menu has no title, and the
        // tooltip no longer says the access is needed (it did).
        let accessBack = StatusMenu.IconLook(hasAccess: true, coresActive: false, isPaused: false, canPostEvents: true)
        XCTAssertTrue(accessBack.appearsDisabled)
        XCTAssertNil(accessBack.toolTip)
    }

    /// Regression: with the access allowed but an event tap that could not be created, the
    /// tooltip said the access was needed; with a tap whose restarts were throttled the icon
    /// looked as if everything worked.
    func testTheIconSaysWhenScrollioCouldNotStart() {
        let couldNotStart = "Scrollio couldn't start and is trying again."

        let failedStart = StatusMenu.IconLook(hasAccess: true, coresActive: false, isPaused: false, startFailed: true, canPostEvents: true)
        XCTAssertTrue(failedStart.appearsDisabled)
        XCTAssertEqual(failedStart.toolTip, couldNotStart)

        let throttled = StatusMenu.IconLook(hasAccess: true, coresActive: true, isPaused: false, tapRestartsThrottled: true, canPostEvents: true)
        XCTAssertTrue(throttled.appearsDisabled, "the not-active look while a tap stays off")
        XCTAssertEqual(throttled.toolTip, couldNotStart)

        // Back to normal by itself once the taps run.
        XCTAssertEqual(StatusMenu.IconLook(hasAccess: true, coresActive: true, isPaused: false, startFailed: false, tapRestartsThrottled: false, canPostEvents: true),
                       StatusMenu.IconLook(hasAccess: true, coresActive: true, isPaused: false, canPostEvents: true))

        // With the access, a pause says "paused" whatever else is true.
        XCTAssertEqual(StatusMenu.IconLook(hasAccess: true, coresActive: false, isPaused: true, startFailed: true, tapRestartsThrottled: true, canPostEvents: true).toolTip,
                       "Scrollio is paused.")
        // Without the access the start did not fail: it waits.
        XCTAssertEqual(StatusMenu.IconLook(hasAccess: false, coresActive: false, isPaused: false, startFailed: false, tapRestartsThrottled: true, canPostEvents: true).toolTip,
                       "Scrollio needs Accessibility access.")
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
        /// The clock: 14:00:40 on 12 November 2026 in Ljubljana.
        var now = Date(timeIntervalSince1970: 1_794_488_440)

        /// 14:00:00, the whole minute the clock starts in.
        static let minute = Date(timeIntervalSince1970: 1_794_488_400)
    }

    private var controllers: [AppRunController] = []

    override func tearDown() {
        // No timer may outlive a test: the wait for the access, and a pause's end.
        for controller in controllers {
            controller.setPaused(false)
            controller.stop()
            XCTAssertNil(controller.recoveryTimer)
            XCTAssertNil(controller.pauseTimer)
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
            showAccessLostToast: { world.log.append("toast") },
            now: { world.now }
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
        XCTAssertNil(AppRunController.shared.pauseEnd)
        XCTAssertNil(AppRunController.shared.pauseTimer)
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
        // Nor a pause that ends by itself, nor its end.
        controller.pause(for: .oneHour)
        XCTAssertNotNil(controller.pauseEnd)
        let after = Set(UserDefaults.standard.dictionaryRepresentation().keys)
        XCTAssertEqual(after.subtracting(before), [])
        // A new run starts unpaused, with no end waiting.
        let next = make(world)
        XCTAssertFalse(next.isPaused)
        XCTAssertNil(next.pauseEnd)
        XCTAssertNil(next.pauseTimer)
    }

    // MARK: - A pause that ends by itself

    /// "Pause For" › "15 Minutes": the stop path of a pause, with an end. The timer only
    /// wakes the check: fired before the end the pause stays and the timer is armed again;
    /// at the end Scrollio starts as after "Resume Scrollio", but no window opens.
    func testATimedPauseEndsByItselfAtItsTime() throws {
        let world = World()
        let controller = make(world)
        controller.start()
        world.log = []

        XCTAssertGreaterThan(changes(of: controller) { controller.pause(for: .fifteenMinutes) }, 0)
        XCTAssertTrue(controller.isPaused)
        XCTAssertFalse(controller.coresActive)
        XCTAssertEqual(world.log, ["stop"])
        let end = try XCTUnwrap(controller.pauseEnd)
        XCTAssertEqual(end, World.minute.addingTimeInterval(15 * 60), "14:15:00")
        let timer = try XCTUnwrap(controller.pauseTimer)
        XCTAssertEqual(timer.fireDate.timeIntervalSinceNow, end.timeIntervalSince(world.now), accuracy: 5)
        XCTAssertEqual(timer.timeInterval, 0, "one shot")
        // Also while a menu is open (the status-bar menu, say).
        for mode in [RunLoop.Mode.default, .eventTracking, .modalPanel] {
            XCTAssertTrue(CFRunLoopContainsTimer(
                CFRunLoopGetMain(), unsafeBitCast(timer, to: CFRunLoopTimer.self), CFRunLoopMode(mode.rawValue as CFString)
            ), mode.rawValue)
        }

        // Fired a second early: still paused, and armed again for what is left.
        world.now = end.addingTimeInterval(-1)
        XCTAssertEqual(changes(of: controller) { timer.fire() }, 0)
        XCTAssertTrue(controller.isPaused)
        XCTAssertEqual(controller.pauseEnd, end)
        let again = try XCTUnwrap(controller.pauseTimer)
        XCTAssertFalse(again === timer)
        XCTAssertTrue(again.isValid)
        XCTAssertEqual(world.log, ["stop"])

        // At the end.
        world.now = end
        XCTAssertGreaterThan(changes(of: controller) { again.fire() }, 0)
        XCTAssertFalse(controller.isPaused)
        XCTAssertTrue(controller.coresActive)
        XCTAssertNil(controller.pauseEnd)
        XCTAssertNil(controller.pauseTimer)
        XCTAssertEqual(world.log, ["stop", "start"], "started, and no Welcome Guide")

        // Looked at again later: nothing.
        XCTAssertEqual(changes(of: controller) { controller.endPauseIfDue() }, 0)
        XCTAssertEqual(world.log, ["stop", "start"])
    }

    /// The end hangs on one timer, and macOS may fire the timer of an idle menu bar app
    /// late. So the menu bar menu looks at the clock before it reads the pause: opened
    /// after the end with the timer still waiting, it ends the pause (the cores start) and
    /// does not say "paused until 14:15" after 14:15. Before the end the pause stays.
    func testTheMenuEndsAPauseWhoseTimeIsUpBeforeItReadsIt() throws {
        let world = World()
        let controller = make(world)
        controller.start()
        controller.pause(for: .fifteenMinutes)
        let end = try XCTUnwrap(controller.pauseEnd)
        world.log = []

        world.now = end.addingTimeInterval(-1)
        var state = StatusItemManager.liveState(of: controller)
        XCTAssertTrue(state.isPaused)
        XCTAssertEqual(state.pauseEnd, end)
        XCTAssertEqual(world.log, [])

        // A minute and a half past the end, and the timer has not fired.
        world.now = end.addingTimeInterval(90)
        XCTAssertTrue(controller.isPaused)
        state = StatusItemManager.liveState(of: controller)
        XCTAssertFalse(state.isPaused)
        XCTAssertNil(state.pauseEnd)
        XCTAssertFalse(controller.isPaused)
        XCTAssertTrue(controller.coresActive)
        XCTAssertNil(controller.pauseTimer)
        XCTAssertEqual(world.log, ["start"], "started, and no Welcome Guide")
    }

    /// The live menu reads the shared poster's right to post events. (The UI tests hand the
    /// start problem in; a `liveState` that lost the argument kept them all green.)
    func testTheLiveMenuSaysWhenMacOSDoesNotLetScrollioPostEvents() {
        let world = World()
        let controller = make(world)
        controller.start()
        let poster = ScrollPoster.shared
        let saved = poster.postEventAccess
        defer {
            poster.postEventAccess = saved
            poster.checkPostEventAccess()
            XCTAssertTrue(poster.canPostEvents)
        }
        XCTAssertNil(StatusItemManager.liveState(of: controller).startProblem)

        poster.postEventAccess = { false }
        poster.checkPostEventAccess()
        XCTAssertEqual(StatusItemManager.liveState(of: controller).startProblem, .cannotPostEvents)
        // Paused, the cores do not run: the pause is what the menu says.
        controller.setPaused(true)
        XCTAssertNil(StatusItemManager.liveState(of: controller).startProblem)
    }

    /// Those who show the pause also look from inside the controller's own notification
    /// (the icon, General's row). A look there starts nothing: the change being told may be
    /// a stop for sleep or for quitting, and the cores would run on behind it.
    func testALookAtThePauseFromInsideAStopsNotificationStartsNothing() throws {
        let world = World()
        let controller = make(world)
        controller.start()
        controller.pause(for: .fifteenMinutes)
        let end = try XCTUnwrap(controller.pauseEnd)
        world.now = end.addingTimeInterval(90)
        world.log = []

        let token = NotificationCenter.default.addObserver(
            forName: AppRunController.didChangeNotification, object: controller, queue: nil
        ) { _ in controller.endPauseIfDue() }
        controller.stop(because: .sleep)
        NotificationCenter.default.removeObserver(token)
        XCTAssertEqual(world.log, ["stop"])
        XCTAssertFalse(controller.coresActive, "nothing runs through the sleep")
        XCTAssertTrue(controller.isPaused)

        // The wake ends the pause, as before.
        controller.wake()
        XCTAssertFalse(controller.isPaused)
        XCTAssertTrue(controller.coresActive)
        XCTAssertEqual(world.log, ["stop", "start"])
    }

    /// The end is a moment, the whole minute the chosen length ends in: what the menu
    /// shows ("until 14:15") is when it ends, never later than chosen, up to 59 s sooner.
    func testThePauseEndIsAWholeMinuteNeverLaterThanChosen() {
        let minute = World.minute
        for (seconds, length) in [(0.0, 900.0), (0.4, 900), (1, 900), (40, 900), (59.9, 900), (40, 3600)] {
            let now = minute.addingTimeInterval(seconds)
            let end = AppRunController.pauseEnd(from: now, after: length)
            XCTAssertEqual(end, minute.addingTimeInterval(length), "\(seconds) s past the minute")
            XCTAssertLessThanOrEqual(end.timeIntervalSince(now), length)
            XCTAssertGreaterThan(end.timeIntervalSince(now), length - 60)
        }
    }

    /// The timer does not count the time asleep. A pause whose end passed while the Mac
    /// slept is over at the wake, which starts the cores (once, and without the guide).
    func testATimedPauseThatEndedDuringSleepEndsAtWake() throws {
        let world = World()
        let controller = make(world)
        controller.start()
        controller.pause(for: .fifteenMinutes)
        let end = try XCTUnwrap(controller.pauseEnd)
        world.log = []

        controller.stop(because: .sleep)
        XCTAssertEqual(controller.pauseEnd, end, "sleep leaves the end alone")
        XCTAssertNotNil(controller.pauseTimer)
        world.now = end.addingTimeInterval(3 * 3600)
        controller.wake()
        XCTAssertFalse(controller.isPaused)
        XCTAssertNil(controller.pauseEnd)
        XCTAssertNil(controller.pauseTimer)
        XCTAssertTrue(controller.coresActive)
        XCTAssertEqual(world.log, ["stop", "start"])
    }

    /// Woken before the end: still paused, and the timer is armed again for what is left
    /// of the clock's time.
    func testAnEarlyWakeKeepsTheTimedPause() throws {
        let world = World()
        let controller = make(world)
        controller.start()
        controller.pause(for: .oneHour)
        let end = try XCTUnwrap(controller.pauseEnd)
        let first = try XCTUnwrap(controller.pauseTimer)
        world.log = []

        controller.stop(because: .sleep)
        world.now = end.addingTimeInterval(-600)
        controller.wake()
        XCTAssertTrue(controller.isPaused)
        XCTAssertFalse(controller.coresActive)
        XCTAssertEqual(controller.pauseEnd, end)
        let armed = try XCTUnwrap(controller.pauseTimer)
        XCTAssertFalse(armed === first)
        XCTAssertFalse(first.isValid)
        XCTAssertEqual(armed.fireDate.timeIntervalSinceNow, 600, accuracy: 5)
        XCTAssertEqual(world.log, ["stop"], "nothing started")

        world.now = end
        armed.fire()
        XCTAssertFalse(controller.isPaused)
        XCTAssertTrue(controller.coresActive)
    }

    /// A change of the clock: set past the end, the pause ends now; set back, the end comes
    /// no later than the chosen length counted from the new time, so the pause never gets
    /// longer than chosen. A new time zone alone keeps the moment and says so to the icon
    /// and to General, which read the time again.
    func testTheClockSetForwardEndsThePauseAndSetBackNeverMakesItLonger() throws {
        let world = World()
        let controller = make(world)
        controller.start()
        controller.pause(for: .fifteenMinutes)
        let end = try XCTUnwrap(controller.pauseEnd)

        // Nothing but the time zone changed: the same moment, and a change is posted.
        world.now = world.now.addingTimeInterval(60)
        XCTAssertEqual(changes(of: controller) { controller.clockDidChange() }, 1)
        XCTAssertEqual(controller.pauseEnd, end)
        XCTAssertTrue(controller.isPaused)

        // Set back by two hours: fifteen minutes from the new time, not two hours more.
        world.now = World.minute.addingTimeInterval(-2 * 3600 + 20)
        XCTAssertEqual(changes(of: controller) { controller.clockDidChange() }, 1)
        let earlier = try XCTUnwrap(controller.pauseEnd)
        XCTAssertEqual(earlier, World.minute.addingTimeInterval(-2 * 3600 + 15 * 60))
        XCTAssertTrue(controller.isPaused)
        let timer = try XCTUnwrap(controller.pauseTimer)
        XCTAssertEqual(timer.fireDate.timeIntervalSinceNow, earlier.timeIntervalSince(world.now), accuracy: 5)

        // Set forward past the end: over, and started.
        world.log = []
        world.now = earlier.addingTimeInterval(1)
        XCTAssertGreaterThan(changes(of: controller) { controller.clockDidChange() }, 0)
        XCTAssertFalse(controller.isPaused)
        XCTAssertNil(controller.pauseEnd)
        XCTAssertNil(controller.pauseTimer)
        XCTAssertEqual(world.log, ["start"])

        // Not paused, or paused until resumed: a change of the clock is nothing to it.
        XCTAssertEqual(changes(of: controller) { controller.clockDidChange() }, 0)
        controller.setPaused(true)
        XCTAssertEqual(changes(of: controller) { controller.clockDidChange() }, 0)
        XCTAssertTrue(controller.isPaused)
        XCTAssertNil(controller.pauseTimer)
    }

    /// The end comes while another user has the Mac: the pause is over, and nothing starts
    /// (a Logitech mouse would lose its buttons for the other user) until this one is back.
    func testATimedPauseEndingWhileAnotherUserHasTheMacStartsWhenTheyAreBack() throws {
        let world = World()
        let controller = make(world)
        controller.start()
        controller.pause(for: .fifteenMinutes)
        let end = try XCTUnwrap(controller.pauseEnd)
        controller.sessionDidResign()
        XCTAssertEqual(controller.pauseEnd, end)
        world.log = []

        world.now = end
        try XCTUnwrap(controller.pauseTimer).fire()
        XCTAssertFalse(controller.isPaused)
        XCTAssertNil(controller.pauseEnd)
        XCTAssertFalse(controller.coresActive)
        XCTAssertEqual(world.log, [])

        controller.sessionDidBecomeActive()
        XCTAssertTrue(controller.coresActive)
        XCTAssertEqual(world.log, ["start"])

        // And one whose end passes unseen (the timer late): over when this user is back.
        controller.pause(for: .fifteenMinutes)
        let second = try XCTUnwrap(controller.pauseEnd)
        controller.sessionDidResign()
        world.log = []
        world.now = second.addingTimeInterval(30)
        controller.sessionDidBecomeActive()
        XCTAssertFalse(controller.isPaused)
        XCTAssertTrue(controller.coresActive)
        XCTAssertEqual(world.log, ["start"])
    }

    /// The access taken away during the pause: at the end nothing can start and no window
    /// opens (the Welcome Guide opens at launch and when the app is reopened); the timer
    /// waits for the access, as after a wake.
    func testATimedPauseEndingWithoutAccessOpensNoWindow() throws {
        let world = World()
        let controller = make(world)
        controller.start()
        controller.pause(for: .fifteenMinutes)
        let end = try XCTUnwrap(controller.pauseEnd)
        world.log = []
        world.access = false

        world.now = end
        try XCTUnwrap(controller.pauseTimer).fire()
        XCTAssertFalse(controller.isPaused)
        XCTAssertFalse(controller.coresActive)
        XCTAssertEqual(world.log, [], "no guide, no toast")
        XCTAssertTrue(controller.isWaitingForAccess)
        XCTAssertEqual(controller.recoveryTimer?.timeInterval, AppRunController.launchRecoveryInterval)

        world.access = true
        controller.accessibilityPermissionWasGranted()
        XCTAssertTrue(controller.coresActive)
        XCTAssertEqual(world.log, ["start"])
    }

    /// "Resume Scrollio" ends a pause of either kind, and the wait for its end with it:
    /// the timer of a pause that was resumed must not end a later one.
    func testResumeEndsATimedPauseAndItsTimer() throws {
        let world = World()
        let controller = make(world)
        controller.start()
        controller.pause(for: .oneHour)
        let timer = try XCTUnwrap(controller.pauseTimer)
        world.log = []

        controller.setPaused(false)
        XCTAssertFalse(controller.isPaused)
        XCTAssertNil(controller.pauseEnd)
        XCTAssertNil(controller.pauseTimer)
        XCTAssertFalse(timer.isValid)
        XCTAssertTrue(controller.coresActive)
        XCTAssertEqual(world.log, ["start"])

        // Resume again (a menu left open across the end of a pause): nothing.
        XCTAssertEqual(changes(of: controller) { controller.setPaused(false) }, 0)
        XCTAssertEqual(world.log, ["start"])

        // Paused until resumed afterwards: nothing ends it but Resume.
        controller.setPaused(true)
        world.now = world.now.addingTimeInterval(2 * 3600)
        controller.endPauseIfDue()
        controller.wake()
        XCTAssertTrue(controller.isPaused)
        XCTAssertFalse(controller.coresActive)
    }

    /// Chosen again while paused, the last choice wins: the end is counted from now, or
    /// goes for "Pause Scrollio"; nothing is stopped a second time.
    func testChoosingAgainWhilePausedReplacesTheEnd() throws {
        let world = World()
        let controller = make(world)
        controller.start()
        world.log = []

        controller.pause(for: .fifteenMinutes)
        let first = try XCTUnwrap(controller.pauseEnd)
        let firstTimer = try XCTUnwrap(controller.pauseTimer)
        world.now = world.now.addingTimeInterval(5 * 60)
        XCTAssertEqual(changes(of: controller) { controller.pause(for: .oneHour) }, 1)
        XCTAssertEqual(controller.pauseEnd, first.addingTimeInterval(50 * 60), "an hour from now: 15:05")
        XCTAssertFalse(firstTimer.isValid)
        XCTAssertTrue(controller.isPaused)
        XCTAssertEqual(world.log, ["stop"], "stopped once")

        // The first end passes: the pause goes on until the second.
        world.now = first.addingTimeInterval(1)
        controller.endPauseIfDue()
        XCTAssertTrue(controller.isPaused)

        // "Pause Scrollio" while paused for a time: until resumed, and no timer waits.
        XCTAssertEqual(changes(of: controller) { controller.setPaused(true) }, 1)
        XCTAssertTrue(controller.isPaused)
        XCTAssertNil(controller.pauseEnd)
        XCTAssertNil(controller.pauseTimer)
        XCTAssertEqual(world.log, ["stop"])
        // The same once more changes nothing.
        XCTAssertEqual(changes(of: controller) { controller.pause(for: .untilResumed) }, 0)

        // And a time after "Pause Scrollio".
        XCTAssertEqual(changes(of: controller) { controller.pause(for: .fifteenMinutes) }, 1)
        XCTAssertNotNil(controller.pauseEnd)
        XCTAssertNotNil(controller.pauseTimer)
        XCTAssertEqual(world.log, ["stop"])
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

    /// "Try Again Now" of the status-bar menu: a failed start's next try comes at once, and
    /// a try that fails again keeps the timer.
    func testTryAgainNowTriesAFailedStartAtOnce() {
        let world = World()
        world.tapsStart = false
        let controller = make(world)
        controller.start()
        XCTAssertEqual(changes(of: controller) { controller.tryAgainNow() }, 1)
        XCTAssertEqual(world.log, ["start", "stop", "start", "stop"])
        XCTAssertTrue(controller.isRetryingStart)
        XCTAssertEqual(controller.recoveryTimer?.timeInterval, AppRunController.launchRecoveryInterval)

        world.tapsStart = true
        controller.tryAgainNow()
        XCTAssertEqual(world.log, ["start", "stop", "start", "stop", "start"])
        XCTAssertTrue(controller.coresActive)
        XCTAssertFalse(controller.isRetryingStart)
        XCTAssertNil(controller.recoveryTimer)
    }

    /// Nothing to try while the cores run, while they wait for the access, or while paused.
    func testTryAgainNowDoesNothingOtherwise() {
        let running = World()
        let started = make(running)
        started.start()
        XCTAssertEqual(changes(of: started) { started.tryAgainNow() }, 0)
        XCTAssertEqual(running.log, ["start"])

        let noAccess = World()
        noAccess.access = false
        let waiting = make(noAccess)
        waiting.start()
        noAccess.access = true
        XCTAssertEqual(changes(of: waiting) { waiting.tryAgainNow() }, 0)
        XCTAssertEqual(noAccess.log, ["guide"], "the wait for the access keeps its own timer")
        XCTAssertTrue(waiting.isWaitingForAccess)

        let failing = World()
        failing.tapsStart = false
        let paused = make(failing)
        paused.start()
        paused.setPaused(true)
        failing.log = []
        paused.tryAgainNow()
        XCTAssertEqual(failing.log, [])
        XCTAssertFalse(paused.coresActive)
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

    func testAMouseAtThreeQuartersIsFine() {
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
        // The name the Buttons pane has for the button (the toasts get it through the bridge).
        let name = "Back button"
        let texts = [
            String(format: NSLocalizedString("logi_ble_hidpp_unstable_toast", comment: ""), name),
            String(format: NSLocalizedString("logi_hidpp_contention_toast", comment: ""), name),
            String(format: NSLocalizedString("logi_ble_contention_standard_mouse_alias_toast", comment: ""), name),
            String(format: NSLocalizedString("openTargetScriptNotExecutable", comment: ""), "build.sh"),
        ]
        XCTAssertEqual(texts[0], "Back button may stop working while Logi Options+ runs. Connect the mouse with its Logitech receiver, or quit Logi Options+.")
        XCTAssertEqual(texts[1], "Logi Options+ keeps taking over Back button.")
        XCTAssertEqual(texts[3], "Script \"build.sh\" can't run: it isn't marked as executable.")
        for text in texts {
            for jargon in ["HID++", "BLE", "Bolt", "Unifying", "chmod", "capture"] {
                XCTAssertFalse(text.contains(jargon), "\(jargon) in \(text)")
            }
        }
    }
}

// MARK: - What the Mac tells the app while it runs

/// `AppDelegate.registerObservers`: which notification leads where. The launch code that
/// calls it does not run under XCTest, so nothing noticed a missing or miswired observer
/// (sleep that does not stop the event taps, a lost access nobody hears of). Here the
/// observers are registered on centers of the test's own and lead to a controller whose
/// cores are fakes.
final class AppDelegateObserverTests: XCTestCase {

    private final class World {
        var access = true
        var log: [String] = []
        var now = Date(timeIntervalSince1970: 1_794_488_440)
    }

    private var world: World!
    private var controller: AppRunController!
    private var delegate: AppDelegate!
    private let workspace = NotificationCenter()
    private let app = NotificationCenter()
    private let distributed = NotificationCenter()

    override func setUp() {
        super.setUp()
        let world = World()
        self.world = world
        controller = AppRunController(environment: AppRunController.Environment(
            hasAccess: { world.access },
            startCores: { world.log.append("start"); return true },
            stopCores: { world.log.append("stop") },
            showWelcomeGuide: { world.log.append("guide") },
            showAccessLostToast: { world.log.append("toast") },
            now: { world.now }
        ))
        delegate = AppDelegate()
        delegate.runController = controller
        delegate.registerObservers(workspace: workspace, app: app, distributed: distributed)
        controller.start()
        XCTAssertEqual(world.log, ["start"])
        XCTAssertTrue(controller.coresActive)
        world.log = []
    }

    override func tearDown() {
        // No timer of the controller may outlive a test.
        controller.setPaused(false)
        controller.stop()
        for center in [workspace, app, distributed] {
            center.removeObserver(delegate as Any)
        }
        delegate = nil
        controller = nil
        world = nil
        super.tearDown()
    }

    func testSleepStopsTheCoresAndWakeStartsThem() {
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        XCTAssertEqual(world.log, ["stop"])
        XCTAssertFalse(controller.coresActive)

        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        XCTAssertEqual(world.log, ["stop", "start"])
        XCTAssertTrue(controller.coresActive)
    }

    func testAnotherUserTakingTheMacStopsTheCoresAndComingBackStartsThem() {
        workspace.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        XCTAssertEqual(world.log, ["stop"])
        XCTAssertFalse(controller.isSessionActive)

        // A wake while the other user has the Mac starts nothing.
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        XCTAssertEqual(world.log, ["stop"])

        workspace.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        XCTAssertEqual(world.log, ["stop", "start"])
        XCTAssertTrue(controller.coresActive)
    }

    /// An event tap that finds the access gone posts this; the cores stop at once.
    func testALostAccessStopsTheCores() {
        world.access = false
        app.post(name: .scrollioAccessibilityPermissionLost, object: nil)
        XCTAssertEqual(world.log.first, "stop")
        XCTAssertTrue(world.log.contains("toast"))
        XCTAssertFalse(controller.coresActive)
    }

    /// The Accessibility list of System Settings changed: the access is looked at half a
    /// second later, not at the event taps' next look.
    func testAChangeOfTheAccessibilityListIsLookedAtShortlyAfter() {
        world.access = false
        distributed.post(name: AppDelegate.accessibilityListChangedNotification, object: nil)
        XCTAssertEqual(world.log, [], "not before macOS can answer")

        let looked = expectation(description: "the access was looked at")
        DispatchQueue.main.asyncAfter(deadline: .now() + AppDelegate.accessibilityCheckDelay + 0.1) { looked.fulfill() }
        wait(for: [looked], timeout: 5)
        XCTAssertEqual(world.log.first, "stop")
        XCTAssertFalse(controller.coresActive)
    }

    /// The clock or the time zone of the Mac changed: a pause that ends by itself is
    /// looked at again (over when its time has passed), and the icon and General are told
    /// to read the time again.
    func testAClockOrTimeZoneChangeReachesTheController() throws {
        for name in [Notification.Name.NSSystemClockDidChange, .NSSystemTimeZoneDidChange] {
            controller.pause(for: .fifteenMinutes)
            let end = try XCTUnwrap(controller.pauseEnd, name.rawValue)
            world.log = []

            var changes = 0
            let token = NotificationCenter.default.addObserver(
                forName: AppRunController.didChangeNotification, object: controller, queue: nil
            ) { _ in changes += 1 }
            defer { NotificationCenter.default.removeObserver(token) }
            app.post(name: name, object: nil)
            XCTAssertEqual(changes, 1, name.rawValue)
            XCTAssertTrue(controller.isPaused, name.rawValue)
            XCTAssertEqual(controller.pauseEnd, end, name.rawValue)

            world.now = end.addingTimeInterval(1)
            app.post(name: name, object: nil)
            XCTAssertFalse(controller.isPaused, name.rawValue)
            XCTAssertTrue(controller.coresActive, name.rawValue)
            XCTAssertEqual(world.log, ["start"], name.rawValue)
        }

        // Posted from another thread, it reaches the controller on the main thread.
        controller.pause(for: .fifteenMinutes)
        world.now = try XCTUnwrap(controller.pauseEnd)
        let center = app
        let ended = expectation(forNotification: AppRunController.didChangeNotification, object: controller) { _ in
            return Thread.isMainThread
        }
        DispatchQueue.global().async {
            center.post(name: .NSSystemClockDidChange, object: nil)
        }
        wait(for: [ended], timeout: 5)
        XCTAssertFalse(controller.isPaused)
        XCTAssertTrue(controller.coresActive)
    }

    /// The Welcome Guide reports the grant through the delegate.
    func testTheGrantReportedByTheGuideReachesTheController() {
        world.access = false
        app.post(name: .scrollioAccessibilityPermissionLost, object: nil)
        XCTAssertFalse(controller.coresActive)
        world.log = []

        world.access = true
        delegate.accessibilityPermissionWasGranted()
        XCTAssertEqual(world.log, ["start"])
        XCTAssertTrue(controller.coresActive)
    }
}
