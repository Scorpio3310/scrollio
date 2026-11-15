//
//  PreferencesGeneralTests.swift
//  MosTests
//
//  The General pane: the card with the app's name and version (what the About pane
//  showed), the row under it that says whether Scrollio works ("Scrollio is on" with
//  Pause, the status-bar menu's title with its way out), "Open at login" and its approval row, "Show
//  in menu bar" (the stored "hide" shown the other way round), the Accessibility row, no
//  developer tools, "Updates" (the two switches and "Check Now" in a copy that updates
//  itself, one line that says why in every other), "Settings file" (its own tests are in
//  SettingsFileTests.swift), and at the bottom the Welcome Guide, Scrollio on GitHub and
//  the credit line. The login item, the permission, the pause,
//  System Settings, the menu bar icon, the windows, the browser and the updater are
//  replaced; nothing is shown on screen, no page is opened and nothing asks the network.
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

final class PreferencesGeneralTests: XCTestCase {

    /// A login item whose state the test sets.
    private final class FakeLoginItem: LoginItemService {
        var status: LoginItemStatus
        private(set) var registerCalls = 0
        private(set) var unregisterCalls = 0
        private(set) var openSettingsCalls = 0

        init(status: LoginItemStatus) {
            self.status = status
        }

        func register() throws {
            registerCalls += 1
        }

        func unregister() throws {
            unregisterCalls += 1
            status = .notRegistered
        }

        func openSystemSettings() {
            openSettingsCalls += 1
        }
    }

    /// What the pane is told about the outside world, and what it did to it.
    private final class World {
        var access = true
        var menuBarIconHidden = false
        var accessibilitySettingsOpened = 0
        var paused = false
        /// When the pause ends by itself; nil for one until Resume.
        var pauseEnd: Date?
        var pauses = 0
        var resumes = 0
        var startProblem: StatusMenu.StartProblem?
        var tryAgains = 0
        var welcomeGuidesOpened = 0
        var openedURLs: [URL] = []
        /// The updater: a copy built from source unless a test says otherwise.
        var updates = UpdateStatus()
        var updateChecks = 0
        var automaticChecksSet: [Bool] = []
        var automaticInstallSet: [Bool] = []
    }

    private var savedAutoLaunch = false

    override func setUp() {
        super.setUp()
        savedAutoLaunch = Options.shared.general.autoLaunch
    }

    override func tearDown() {
        LoginItem.service = InertLoginItemService()
        Options.shared.general.autoLaunch = savedAutoLaunch
        LoginItem.service = LoginItem.defaultService
        super.tearDown()
    }

    @discardableResult
    private func install(_ status: LoginItemStatus) -> FakeLoginItem {
        let fake = FakeLoginItem(status: status)
        LoginItem.service = fake
        return fake
    }

    /// The pane as the storyboard makes it, with the seams set before its view loads.
    private func makePane(_ world: World) throws -> PreferencesGeneralViewController {
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesGeneralViewController.self))
        let pane = try XCTUnwrap(
            storyboard.instantiateController(withIdentifier: PANEL_IDENTIFIER.general) as? PreferencesGeneralViewController
        )
        pane.isAccessGranted = { world.access }
        pane.openAccessibilitySettings = { world.accessibilitySettingsOpened += 1 }
        pane.isMenuBarIconHidden = { world.menuBarIconHidden }
        pane.setMenuBarIconHidden = { world.menuBarIconHidden = $0 }
        pane.isPaused = { world.paused }
        pane.pause = {
            world.pauses += 1
            world.paused = true
        }
        pane.pauseEnd = { world.pauseEnd }
        pane.resume = {
            world.resumes += 1
            world.paused = false
            world.pauseEnd = nil
        }
        pane.startProblem = { world.startProblem }
        pane.tryAgain = { world.tryAgains += 1 }
        pane.showWelcomeGuide = { world.welcomeGuidesOpened += 1 }
        pane.openURL = { world.openedURLs.append($0) }
        pane.updateStatus = { world.updates }
        pane.checkForUpdates = { world.updateChecks += 1 }
        pane.setChecksForUpdates = {
            world.automaticChecksSet.append($0)
            world.updates.checksAutomatically = $0
            world.updates.canInstallAutomatically = $0
        }
        pane.setInstallsUpdates = {
            world.automaticInstallSet.append($0)
            world.updates.installsAutomatically = $0
        }
        _ = pane.view
        return pane
    }

    private func click(_ button: NSButton) {
        XCTAssertTrue(isShown(button), "\(button.title) is hidden")
        XCTAssertTrue(button.isEnabled, "\(button.title) is disabled")
        XCTAssertTrue(button.sendAction(button.action, to: button.target), button.title)
    }

    private func shownTexts(_ pane: PreferencesGeneralViewController) -> [String] {
        let views = allSubviews(of: pane.view).filter(isShown)
        return views.compactMap { ($0 as? NSTextField)?.stringValue }.filter { !$0.isEmpty }
            + views.compactMap { ($0 as? NSButton)?.title }.filter { !$0.isEmpty }
    }

    func testTheStoryboardMakesTheGeneralPane() {
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesSplitViewController.self))
        XCTAssertTrue(storyboard.instantiateController(withIdentifier: PANEL_IDENTIFIER.general) is PreferencesGeneralViewController)
    }

    // MARK: - The app (what About showed)

    func testTheCardOnTopShowsTheAppItsVersionAndBuild() throws {
        install(.notRegistered)
        let pane = try makePane(World())
        let header = try XCTUnwrap(pane.headerView)
        let content = try XCTUnwrap(header.superview as? NSStackView)
        XCTAssertTrue(content.arrangedSubviews.first === header, "on top")
        XCTAssertEqual(header.nameLabel.stringValue, "Scrollio")
        XCTAssertNotNil(header.iconView.image)
        XCTAssertFalse(header.iconView.isAccessibilityElement(), "the name says the same")

        let version = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        let build = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
        XCTAssertFalse(version.isEmpty)
        XCTAssertFalse(build.isEmpty)
        XCTAssertEqual(header.versionLabel.stringValue, "Version \(version) (\(build))")
        XCTAssertEqual(PreferencesGeneralViewController.versionText(), "Version \(version) (\(build))")
        XCTAssertTrue(header.versionLabel.isSelectable, "the version can be copied")
        XCTAssertTrue(shownTexts(pane).contains("Version \(version) (\(build))"))
        // The window keeps the pane's name.
        XCTAssertEqual(pane.title, "General")
    }

    /// A build installed by scripts/install.sh says which commit it is and when it was
    /// built; any other build shows the line as before. Read through one pure function.
    func testTheVersionLineShowsTheBuildStampWhenThereIsOne() throws {
        let plain: [String: Any] = ["CFBundleShortVersionString": "1.0", "CFBundleVersion": "1"]
        let gb = Locale(identifier: "en_GB")
        let us = Locale(identifier: "en_US")
        typealias Pane = PreferencesGeneralViewController
        XCTAssertEqual(Pane.buildCommitKey, "ScrollioBuildCommit")
        XCTAssertEqual(Pane.buildDateKey, "ScrollioBuildDate")

        // Without the keys, or with them empty (every build but an installed one).
        XCTAssertEqual(Pane.versionText(info: plain, locale: gb), "Version 1.0 (1)")
        var empty = plain
        empty[Pane.buildCommitKey] = ""
        empty[Pane.buildDateKey] = ""
        XCTAssertEqual(Pane.versionText(info: empty, locale: gb), "Version 1.0 (1)")

        // Stamped: the commit and the day in the user's format.
        let stamped: [String: Any] = [
            "CFBundleShortVersionString": "1.0", "CFBundleVersion": "1456",
            Pane.buildCommitKey: "e904756", Pane.buildDateKey: "2026-11-11",
        ]
        XCTAssertEqual(Pane.versionText(info: stamped, locale: gb), "Version 1.0 (1456) · e904756 · 11 Nov 2026")
        XCTAssertEqual(Pane.versionText(info: stamped, locale: us), "Version 1.0 (1456) · e904756 · Nov 11, 2026")
        // Built with uncommitted changes: the "+" stays.
        var dirty = stamped
        dirty[Pane.buildCommitKey] = "e904756+"
        XCTAssertEqual(Pane.versionText(info: dirty, locale: gb), "Version 1.0 (1456) · e904756+ · 11 Nov 2026")
        // The first of a month stays that day in any time zone; a day that is no date is
        // shown as it is; without one, the commit alone.
        var newYear = stamped
        newYear[Pane.buildDateKey] = "2026-01-01"
        XCTAssertEqual(Pane.versionText(info: newYear, locale: us), "Version 1.0 (1456) · e904756 · Jan 1, 2026")
        var odd = stamped
        odd[Pane.buildDateKey] = "yesterday"
        XCTAssertEqual(Pane.versionText(info: odd, locale: gb), "Version 1.0 (1456) · e904756 · yesterday")
        var noDay = stamped
        noDay[Pane.buildDateKey] = nil
        XCTAssertEqual(Pane.versionText(info: noDay, locale: gb), "Version 1.0 (1456) · e904756")

        // The card shows what the bundle says, and still fits on one line.
        install(.notRegistered)
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesGeneralViewController.self))
        let pane = try XCTUnwrap(
            storyboard.instantiateController(withIdentifier: PANEL_IDENTIFIER.general) as? PreferencesGeneralViewController
        )
        pane.isAccessGranted = { true }
        pane.isPaused = { false }
        pane.isMenuBarIconHidden = { false }
        pane.bundleInfo = { dirty }
        pane.view.layoutSubtreeIfNeeded()
        let label = pane.headerView.versionLabel
        XCTAssertEqual(label.stringValue, Pane.versionText(info: dirty))
        XCTAssertGreaterThanOrEqual(label.frame.width, label.intrinsicContentSize.width - 0.5, "not cut off")
        // This test build has no stamp: the line as before.
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: Pane.buildCommitKey) as? String ?? "", "")
    }

    /// The card has the size and the look of the Mouse pane's card.
    func testTheCardHasTheLookOfTheMouseCard() throws {
        install(.notRegistered)
        let pane = try makePane(World())
        pane.view.layoutSubtreeIfNeeded()
        let header = try XCTUnwrap(pane.headerView)
        XCTAssertEqual(GeneralHeaderView.preferredHeight, MouseHeaderView.preferredHeight)
        XCTAssertEqual(GeneralHeaderView.cornerRadius, MouseHeaderView.cornerRadius)
        XCTAssertEqual(GeneralHeaderView.iconColumnWidth, MouseHeaderView.artworkColumnWidth)
        XCTAssertEqual(header.nameLabel.font, MouseHeaderView.nameFont)
        XCTAssertEqual(header.versionLabel.font, MouseHeaderView.detailFont)
        XCTAssertEqual(header.frame.height, GeneralHeaderView.preferredHeight)
        XCTAssertEqual(header.frame.width, PreferencesGroupedForm.boxWidth(paneWidth: PreferencesGeneralViewController.paneWidth))
        XCTAssertEqual(header.iconView.frame.midX, GeneralHeaderView.iconColumnWidth / 2, accuracy: 0.5)
        XCTAssertEqual(header.nameLabel.convert(header.nameLabel.bounds, to: header).minX, GeneralHeaderView.iconColumnWidth, accuracy: 3)
    }

    func testTheWelcomeGuideIsReachableAtTheBottom() throws {
        install(.notRegistered)
        let world = World()
        let pane = try makePane(world)
        XCTAssertEqual(pane.welcomeGuideRow.title, "Welcome Guide")
        XCTAssertEqual(pane.welcomeGuideRow.explanation, "Shows the first-launch steps again, including Accessibility access.")
        XCTAssertEqual(pane.welcomeGuideButton.title, "Open", "it only opens a window: no …")
        XCTAssertEqual(pane.welcomeGuideButton.bezelStyle, .push)
        XCTAssertTrue(pane.welcomeGuideRow.controls.contains { $0 === pane.welcomeGuideButton })
        XCTAssertTrue(pane.welcomeGuideButton.accessibilityTitleUIElement() as? NSTextField === pane.welcomeGuideRow.titleLabel)
        click(pane.welcomeGuideButton)
        XCTAssertEqual(world.welcomeGuidesOpened, 1)
        XCTAssertEqual(world.accessibilitySettingsOpened, 0)
        XCTAssertEqual(world.openedURLs, [])
    }

    /// Under the Welcome Guide, in its box: the repository, opened in the default browser.
    func testScrollioOnGitHubOpensTheRepository() throws {
        install(.notRegistered)
        let world = World()
        let pane = try makePane(world)
        let row = try XCTUnwrap(pane.gitHubRow)
        let button = try XCTUnwrap(pane.gitHubButton)
        XCTAssertEqual(row.title, "Scrollio on GitHub")
        XCTAssertEqual(row.explanation, "Source code and new versions.")
        XCTAssertEqual(button.title, "Open", "it opens no window of Scrollio's")
        XCTAssertEqual(button.bezelStyle, .push)
        XCTAssertTrue(isShown(row))
        XCTAssertTrue(row.controls.contains { $0 === button })
        // The same box, right under the Welcome Guide.
        let box = try XCTUnwrap(row.superview as? NSStackView)
        XCTAssertTrue(pane.welcomeGuideRow.superview === box)
        let rows = box.arrangedSubviews.filter { !$0.isHidden }
        XCTAssertEqual(rows.firstIndex { $0 === row }, try XCTUnwrap(rows.firstIndex { $0 === pane.welcomeGuideRow }) + 1)
        // VoiceOver hears where it goes, not only "Open".
        XCTAssertEqual(button.accessibilityLabel(), "Open Scrollio on GitHub in your web browser")
        XCTAssertTrue(button.accessibilityTitleUIElement() as? NSTextField === row.titleLabel)
        XCTAssertEqual(button.toolTip, "https://github.com/Scorpio3310/scrollio")

        XCTAssertEqual(PreferencesGeneralViewController.gitHubURL.absoluteString, "https://github.com/Scorpio3310/scrollio")
        click(button)
        XCTAssertEqual(world.openedURLs, [URL(string: "https://github.com/Scorpio3310/scrollio")!])
        XCTAssertEqual(world.welcomeGuidesOpened, 0)
        XCTAssertEqual(world.accessibilitySettingsOpened, 0)
    }

    /// The licence (CC BY-NC 4.0) asks for the attribution: it is always on the pane, last.
    func testTheCreditLineIsShownLast() throws {
        for paused in [false, true] {
            install(.requiresApproval)
            let world = World()
            world.paused = paused
            let pane = try makePane(world)
            let credit = try XCTUnwrap(pane.creditLabel)
            XCTAssertEqual(credit.stringValue, "Based on Mos by Caldis, licensed under CC BY-NC 4.0, with changes.")
            XCTAssertTrue(isShown(credit))
            let content = try XCTUnwrap(credit.superview as? NSStackView)
            let shown = content.arrangedSubviews.filter { !$0.isHidden }
            XCTAssertTrue(shown.last === credit, "the last line of the pane")
            let guide = try XCTUnwrap(pane.welcomeGuideRow.superview?.superview?.superview)
            XCTAssertTrue(shown.dropLast().last === guide, "right under the Welcome Guide")
            XCTAssertEqual(credit.textColor, PreferencesGroupedForm.explanationColor(enabled: true))
            XCTAssertGreaterThanOrEqual(credit.font?.pointSize ?? 0, 10)
            // It fits the column and is never cut.
            pane.view.layoutSubtreeIfNeeded()
            XCTAssertGreaterThanOrEqual(credit.frame.height, credit.intrinsicContentSize.height - 0.5)
        }
    }

    /// The links and donations of Mos's About pane did not come along. The one link is
    /// Scrollio's own repository ("Scrollio on GitHub"), not Mos's.
    func testNothingOfTheOldAboutPaneIsLeft() throws {
        install(.notRegistered)
        let pane = try makePane(World())
        let removed = ["Home Page", "Contributors", "Donate", "Feed", "Welcome Window", "Buy me a coffee"]
        for text in shownTexts(pane) {
            for word in removed {
                XCTAssertFalse(text.localizedCaseInsensitiveContains(word), "'\(text)' still mentions \(word)")
            }
        }
        XCTAssertEqual(shownTexts(pane).filter { $0.localizedCaseInsensitiveContains("GitHub") }, ["Scrollio on GitHub"])
        XCTAssertFalse(PreferencesGeneralViewController.gitHubURL.absoluteString.localizedCaseInsensitiveContains("caldis"))
        XCTAssertFalse(allSubviews(of: pane.view).contains { ($0 as? NSButton)?.bezelStyle == .helpButton })
        for name in ["AlipayQR", "WechatpayQR", "PaypalLogo", "BuyMeACoffee", "MEOW"] {
            XCTAssertNil(NSImage(named: name), "donation asset \(name) is still in the bundle")
        }
    }

    // MARK: - Whether Scrollio works

    /// The row under the card is always there: "Scrollio is on" with Pause, and while
    /// paused the menu's title with Resume. With the menu bar icon hidden it is the way to
    /// pause and back.
    func testTheRowUnderTheCardPausesAndResumes() throws {
        install(.notRegistered)
        let world = World()
        let pane = try makePane(world)
        let content = try XCTUnwrap(pane.statusSection.superview as? NSStackView)
        XCTAssertTrue(content.arrangedSubviews.first === pane.headerView)
        XCTAssertTrue(content.arrangedSubviews[1] === pane.statusSection, "right under the card")
        XCTAssertTrue(isShown(pane.statusSection), "while running too")
        XCTAssertEqual(pane.statusSection.box.visibleRows.count, 1, "one row")
        XCTAssertNil(pane.statusSection.titleLabel)
        XCTAssertEqual(pane.statusRow.title, "Scrollio is on")
        XCTAssertNil(pane.statusRow.explanation)
        XCTAssertEqual(pane.statusButton.title, "Pause")
        XCTAssertEqual(pane.statusButton.bezelStyle, .push)
        XCTAssertTrue(pane.statusButton.accessibilityTitleUIElement() as? NSTextField === pane.statusRow.titleLabel)
        XCTAssertEqual(pane.view.frame.size, pane.view.fittingSize)
        let runningHeight = pane.view.frame.height

        click(pane.statusButton)
        XCTAssertEqual(world.pauses, 1)
        XCTAssertEqual(pane.statusRow.title, "Scrollio is paused")
        XCTAssertEqual(pane.statusRow.explanation, "Scrolling, buttons, gestures and the Shortcut Ring are off until you resume.")
        XCTAssertEqual(pane.statusButton.title, "Resume")
        XCTAssertTrue(pane.statusButton.accessibilityTitleUIElement() as? NSTextField === pane.statusRow.titleLabel)
        XCTAssertEqual(pane.statusButton.accessibilityHelp(), pane.statusRow.explanation)
        XCTAssertGreaterThan(pane.view.frame.height, runningHeight, "the pane makes room for the line")
        XCTAssertEqual(pane.view.frame.size, pane.view.fittingSize)
        pane.view.layoutSubtreeIfNeeded()
        XCTAssertFalse(pane.view.hasAmbiguousLayout)

        click(pane.statusButton)
        XCTAssertEqual(world.resumes, 1)
        XCTAssertEqual(world.pauses, 1)
        XCTAssertEqual(pane.statusRow.title, "Scrollio is on")
        XCTAssertEqual(pane.statusButton.title, "Pause")
        XCTAssertEqual(pane.view.frame.height, runningHeight, accuracy: 0.5)
        XCTAssertEqual(world.tryAgains, 0)
        XCTAssertEqual(world.accessibilitySettingsOpened, 0)
    }

    /// The row's title is the status-bar menu's, by the same pure rule and in its order:
    /// the missing access first (also while paused), then the pause, then a start problem.
    func testTheRowSaysWhatTheMenuBarSays() throws {
        typealias Status = PreferencesGeneralViewController.RunStatus
        for access in [true, false] {
            for paused in [false, true] {
                for problem in [nil, StatusMenu.StartProblem.retrying, .tapOff, .cannotPostEvents] {
                    let status = Status(hasAccess: access, isPaused: paused, startProblem: problem)
                    let menu = StatusMenu.title(hasAccess: access, isPaused: paused, startProblem: problem)
                    let name = "access \(access) paused \(paused) \(String(describing: problem))"
                    XCTAssertEqual(status.title, menu, name)
                    XCTAssertEqual(status.titleKey, menu?.key ?? "general-status-on", name)
                    // The icon's tooltip says the same, by the same rule.
                    let look = StatusMenu.IconLook(
                        hasAccess: access, coresActive: problem == .tapOff || problem == .cannotPostEvents, isPaused: paused,
                        startFailed: problem == .retrying, tapRestartsThrottled: problem == .tapOff,
                        canPostEvents: problem != .cannotPostEvents
                    )
                    XCTAssertEqual(look.toolTip == nil, menu == nil, name)
                }
            }
        }
        XCTAssertEqual(Status(hasAccess: false, isPaused: true, startProblem: nil).action, .allowAccess, "the access first")
        XCTAssertEqual(Status(hasAccess: true, isPaused: true, startProblem: .retrying).action, .resume, "then the pause")
        XCTAssertEqual(Status(hasAccess: true, isPaused: false, startProblem: .retrying).action, .tryAgain)
        XCTAssertEqual(Status(hasAccess: true, isPaused: false, startProblem: .tapOff).action, .pause, "it comes back by itself")
        XCTAssertEqual(Status(hasAccess: true, isPaused: false, startProblem: .cannotPostEvents).action, .pause,
                       "the cores run; System Settings is in Permissions")
        XCTAssertEqual(Status(hasAccess: true, isPaused: false, startProblem: nil).action, .pause)

        // The words are the menu's.
        install(.notRegistered)
        let world = World()
        world.paused = true
        let pane = try makePane(world)
        XCTAssertEqual(pane.statusRow.title, NSLocalizedString(StatusMenu.Title.paused.key, comment: ""))
    }

    /// A pause that ends by itself ("Pause For" of the status-bar menu): the row says until
    /// when, in the menu's words, with a line that says "until then" and Resume. Without the
    /// access it says only that. The row's own Pause stays a plain button: until Resume.
    func testTheRowSaysUntilWhen() throws {
        typealias Status = PreferencesGeneralViewController.RunStatus
        let end = Date(timeIntervalSince1970: 1_794_490_200)
        let until = String(format: NSLocalizedString("status-menu-title-paused-until", comment: ""), StatusMenu.pauseEndText(end))

        let timed = Status(hasAccess: true, isPaused: true, startProblem: nil, pauseEnd: end)
        XCTAssertEqual(timed.titleText, until)
        XCTAssertEqual(timed.explanationKey, "general-paused-until-hint")
        XCTAssertEqual(timed.action, .resume)
        let plain = Status(hasAccess: true, isPaused: true, startProblem: nil)
        XCTAssertEqual(plain.titleText, "Scrollio is paused")
        XCTAssertEqual(plain.explanationKey, "general-paused-hint")
        // No time without the access, and none left over once the pause is over.
        let noAccess = Status(hasAccess: false, isPaused: true, startProblem: nil, pauseEnd: end)
        XCTAssertEqual(noAccess.titleText, "Scrollio needs Accessibility access")
        XCTAssertNil(noAccess.explanationKey)
        XCTAssertNil(noAccess.pauseEnd)
        XCTAssertEqual(Status(hasAccess: true, isPaused: false, startProblem: nil, pauseEnd: end).titleText, "Scrollio is on")

        install(.notRegistered)
        let world = World()
        let pane = try makePane(world)
        let runningHeight = pane.view.frame.height
        XCTAssertEqual(pane.statusButton.title, "Pause")
        XCTAssertEqual(pane.statusButton.bezelStyle, .push, "one click, no menu")

        // Paused for a time from the menu bar: the run controller says so.
        world.paused = true
        world.pauseEnd = end
        NotificationCenter.default.post(name: AppRunController.didChangeNotification, object: nil)
        XCTAssertEqual(pane.statusRow.title, until)
        XCTAssertEqual(pane.statusRow.explanation, "Scrolling, buttons, gestures and the Shortcut Ring are off until then.")
        XCTAssertEqual(pane.statusButton.title, "Resume")
        XCTAssertTrue(pane.statusButton.accessibilityTitleUIElement() as? NSTextField === pane.statusRow.titleLabel)
        XCTAssertEqual(pane.statusButton.accessibilityHelp(), pane.statusRow.explanation)
        XCTAssertGreaterThan(pane.view.frame.height, runningHeight, "the pane makes room for the line")
        XCTAssertEqual(pane.view.frame.size, pane.view.fittingSize)
        pane.view.layoutSubtreeIfNeeded()
        XCTAssertFalse(pane.view.hasAmbiguousLayout)
        // The menu bar's title for the same state.
        let menu = NSMenu()
        StatusMenu.build(
            into: menu,
            state: StatusMenu.State(hasAccess: true, isPaused: true, showsDiagnostics: false, batteries: [], pauseEnd: end),
            actions: StatusMenuActions()
        )
        XCTAssertEqual(pane.statusRow.title, menu.items.first?.title)

        // Chosen again with another length, or the time zone changed: the row follows.
        let later = end.addingTimeInterval(45 * 60)
        world.pauseEnd = later
        NotificationCenter.default.post(name: AppRunController.didChangeNotification, object: nil)
        XCTAssertEqual(
            pane.statusRow.title,
            String(format: NSLocalizedString("status-menu-title-paused-until", comment: ""), StatusMenu.pauseEndText(later))
        )
        XCTAssertNotEqual(pane.statusRow.title, until)

        // "Pause Scrollio" while paused for a time: until Resume.
        world.pauseEnd = nil
        NotificationCenter.default.post(name: AppRunController.didChangeNotification, object: nil)
        XCTAssertEqual(pane.statusRow.title, "Scrollio is paused")
        XCTAssertEqual(pane.statusRow.explanation, "Scrolling, buttons, gestures and the Shortcut Ring are off until you resume.")

        // Resume ends a pause of either kind; the end by itself reads the same.
        world.pauseEnd = end
        NotificationCenter.default.post(name: AppRunController.didChangeNotification, object: nil)
        click(pane.statusButton)
        XCTAssertEqual(world.resumes, 1)
        XCTAssertEqual(world.pauses, 0)
        XCTAssertEqual(pane.statusRow.title, "Scrollio is on")
        XCTAssertNil(pane.statusRow.explanation)
        XCTAssertEqual(pane.statusButton.title, "Pause")
        XCTAssertEqual(pane.view.frame.height, runningHeight, accuracy: 0.5)
    }

    /// A start that failed: the menu's title, and "Try Again Now", the menu's item in the
    /// menu's words, tries at once. A tap kept off comes back by itself: Pause, as in the menu.
    func testAStartThatFailedOffersTryAgain() throws {
        install(.notRegistered)
        let world = World()
        world.startProblem = .retrying
        let pane = try makePane(world)
        XCTAssertEqual(pane.statusRow.title, "Scrollio couldn't start and is trying again")
        XCTAssertNil(pane.statusRow.explanation)
        XCTAssertEqual(pane.statusButton.title, "Try Again Now")
        let menu = NSMenu()
        StatusMenu.build(
            into: menu,
            state: StatusMenu.State(
                hasAccess: true, isPaused: false, showsDiagnostics: false, batteries: [], appSmoothing: nil,
                appSettings: nil, updates: .none, startProblem: .retrying
            ),
            actions: StatusMenuActions()
        )
        let item = try XCTUnwrap(menu.items.first { $0.action == #selector(StatusMenuActions.tryAgainClicked(_:)) })
        XCTAssertEqual(pane.statusButton.title, item.title, "the menu's item for the same state")
        XCTAssertTrue(pane.statusButton.accessibilityTitleUIElement() as? NSTextField === pane.statusRow.titleLabel)
        click(pane.statusButton)
        XCTAssertEqual(world.tryAgains, 1)
        XCTAssertEqual(world.pauses, 0)

        world.startProblem = .tapOff
        NotificationCenter.default.post(name: Interceptor.restartThrottleDidChangeNotification, object: nil)
        XCTAssertEqual(pane.statusRow.title, "Scrollio couldn't start and is trying again")
        XCTAssertEqual(pane.statusButton.title, "Pause")
        click(pane.statusButton)
        XCTAssertEqual(world.pauses, 1)
        XCTAssertEqual(world.tryAgains, 1)
        // Paused now: the pause comes before the start problem.
        XCTAssertEqual(pane.statusRow.title, "Scrollio is paused")
        XCTAssertEqual(pane.view.frame.size, pane.view.fittingSize)
    }

    /// Without the right to post events: the menu's title, a line with what to do, and Pause
    /// (the cores run, and the line says to pause before Scrollio is removed from the
    /// Accessibility list); "Open System Settings" is the Permissions row's own. It follows
    /// the poster's notice.
    func testWithoutTheRightToPostEventsTheRowSaysSoAndOffersPause() throws {
        install(.notRegistered)
        let world = World()
        let pane = try makePane(world)
        let runningHeight = pane.view.frame.height
        XCTAssertEqual(pane.statusRow.title, "Scrollio is on")

        world.startProblem = .cannotPostEvents
        NotificationCenter.default.post(name: ScrollPoster.postEventAccessDidChangeNotification, object: nil)
        XCTAssertEqual(pane.statusRow.title, "Scrollio can't send events to apps")
        // More than scrolling stops, and Pause comes before the removal: removing Scrollio
        // from that list while its event taps run can stop the mouse and keyboard.
        XCTAssertEqual(pane.statusRow.explanation, "Scrolling isn't smoothed, and buttons, gestures and the Shortcut Ring may not work. Pause Scrollio, then in Privacy & Security › Accessibility remove it with − and add it again. This usually brings it back.")
        XCTAssertEqual(pane.statusButton.title, "Pause", "the cores run: with the menu bar icon hidden this is the pause")
        XCTAssertEqual(shownButtons(titled: "Open System Settings", in: pane), [pane.openAccessibilitySettingsButton],
                       "one, in Permissions, beside \"Allowed\"")
        XCTAssertGreaterThan(pane.view.frame.height, runningHeight, "the pane makes room for the line")
        XCTAssertEqual(pane.view.frame.size, pane.view.fittingSize)
        click(pane.openAccessibilitySettingsButton)
        XCTAssertEqual(world.accessibilitySettingsOpened, 1)

        // The menu bar's title for the same state.
        let menu = NSMenu()
        StatusMenu.build(
            into: menu,
            state: StatusMenu.State(hasAccess: true, isPaused: false, showsDiagnostics: false, batteries: [],
                                    startProblem: .cannotPostEvents),
            actions: StatusMenuActions()
        )
        XCTAssertEqual(pane.statusRow.title, menu.items.first?.title)

        click(pane.statusButton)
        XCTAssertEqual(world.pauses, 1)
        XCTAssertEqual(world.accessibilitySettingsOpened, 1)
        XCTAssertEqual(pane.statusRow.title, "Scrollio is paused")

        // Given back: on again, and Permissions has no button while the access is there.
        world.paused = false
        world.startProblem = nil
        NotificationCenter.default.post(name: ScrollPoster.postEventAccessDidChangeNotification, object: nil)
        XCTAssertEqual(pane.statusRow.title, "Scrollio is on")
        XCTAssertNil(pane.statusRow.explanation)
        XCTAssertEqual(pane.statusButton.title, "Pause")
        XCTAssertEqual(shownButtons(titled: "Open System Settings", in: pane), [])
    }

    /// Without the access, the row says so first (also while paused) and leads where the
    /// Permissions row leads.
    func testWithoutAccessTheRowUnderTheCardLeadsToSystemSettings() throws {
        install(.notRegistered)
        let world = World()
        world.access = false
        world.paused = true
        let pane = try makePane(world)
        XCTAssertEqual(pane.statusRow.title, "Scrollio needs Accessibility access")
        XCTAssertEqual(pane.statusButton.title, "Open System Settings")
        XCTAssertEqual(pane.statusButton.title, pane.openAccessibilitySettingsButton.title)
        XCTAssertEqual(shownButtons(titled: "Open System Settings", in: pane), [pane.statusButton], "one, under the card")
        click(pane.statusButton)
        XCTAssertEqual(world.accessibilitySettingsOpened, 1)
        XCTAssertEqual(world.resumes, 0, "Resume is not offered without the access")
        XCTAssertEqual(world.pauses, 0)
        XCTAssertEqual(pane.view.frame.size, pane.view.fittingSize)
    }

    /// The row follows what the status item follows: the run controller, the lost access,
    /// a tap kept off, and the window becoming key (back from System Settings).
    func testTheRowFollowsTheRunState() throws {
        install(.notRegistered)
        let world = World()
        let pane = try makePane(world)
        XCTAssertEqual(pane.statusRow.title, "Scrollio is on")

        // Paused from the menu: the run controller says so.
        world.paused = true
        NotificationCenter.default.post(name: AppRunController.didChangeNotification, object: nil)
        XCTAssertEqual(pane.statusRow.title, "Scrollio is paused")
        XCTAssertEqual(pane.view.frame.size, pane.view.fittingSize)

        // Resumed while the pane was not showing: it shows when the pane appears.
        world.paused = false
        pane.viewWillAppear()
        XCTAssertEqual(pane.statusRow.title, "Scrollio is on")

        world.access = false
        NotificationCenter.default.post(name: .scrollioAccessibilityPermissionLost, object: nil)
        XCTAssertEqual(pane.statusRow.title, "Scrollio needs Accessibility access")

        world.access = true
        world.startProblem = .tapOff
        NotificationCenter.default.post(name: Interceptor.restartThrottleDidChangeNotification, object: nil)
        XCTAssertEqual(pane.statusRow.title, "Scrollio couldn't start and is trying again")

        let window = NSWindow(
            contentRect: NSRect(x: -20000, y: -20000, width: 520, height: 300),
            styleMask: [.titled], backing: .buffered, defer: true
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = pane
        defer { window.contentViewController = nil }
        world.startProblem = nil
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        XCTAssertEqual(pane.statusRow.title, "Scrollio is on")
        XCTAssertEqual(pane.statusButton.title, "Pause")
    }

    /// The row looks at the clock before it reads the pause (the end hangs on one timer,
    /// which macOS may fire late in an idle menu bar app): read after the end with the
    /// timer still waiting, the pause is over and the row says Scrollio is on, not "paused
    /// until" a time that has passed.
    func testTheStatusRowEndsAPauseWhoseTimeIsUpBeforeItReadsIt() throws {
        var now = Date(timeIntervalSince1970: 1_794_488_440)
        var log: [String] = []
        let controller = AppRunController(environment: AppRunController.Environment(
            hasAccess: { true },
            startCores: { log.append("start"); return true },
            stopCores: { log.append("stop") },
            showWelcomeGuide: { log.append("guide") },
            showAccessLostToast: {},
            now: { now }
        ))
        addTeardownBlock {
            controller.setPaused(false)
            controller.stop()
        }
        controller.start()
        controller.pause(for: .fifteenMinutes)
        let end = try XCTUnwrap(controller.pauseEnd)
        log = []

        let pane = try makePane(World())
        pane.isPaused = { controller.isPaused }
        pane.pauseEnd = { controller.pauseEnd }
        pane.endPauseIfDue = { controller.endPauseIfDue() }
        pane.refreshRunStatus()
        XCTAssertEqual(pane.runStatus.pauseEnd, end)
        XCTAssertEqual(pane.statusButton.title, "Resume")
        XCTAssertEqual(log, [])

        // A minute past the end, and the timer has not fired.
        now = end.addingTimeInterval(60)
        pane.refreshRunStatus()
        XCTAssertFalse(controller.isPaused)
        XCTAssertEqual(log, ["start"])
        XCTAssertNil(pane.runStatus.pauseEnd)
        XCTAssertEqual(pane.statusRow.title, "Scrollio is on")
        XCTAssertEqual(pane.statusButton.title, "Pause")
    }

    /// The pane as the app makes it reads the run controller: under XCTest nothing runs
    /// and nothing failed, so the row says Scrollio is on (the cores never start in tests).
    func testTheLiveSeamsReadTheRunControllerAndTheStatusItemsRule() throws {
        let pane = PreferencesGeneralViewController()
        XCTAssertFalse(AppRunController.shared.isRetryingStart)
        XCTAssertNil(pane.startProblem())
        XCTAssertEqual(pane.isPaused(), AppRunController.shared.isPaused)
        XCTAssertEqual(pane.pauseEnd(), AppRunController.shared.pauseEnd)
        XCTAssertNil(pane.pauseEnd(), "nothing is paused under tests")
    }

    // MARK: - Open at login

    func testOpenAtLoginSaysWhatItDoes() throws {
        install(.notRegistered)
        let pane = try makePane(World())
        XCTAssertEqual(pane.launchOnLoginRow.title, "Open at login")
        XCTAssertEqual(pane.launchOnLoginRow.explanation, "Scrollio starts when you log in to your Mac.")
        XCTAssertTrue(pane.loginApprovalRow.isHidden)
        XCTAssertFalse(shownTexts(pane).contains("Open Login Items"))
    }

    /// macOS waits for the user to allow the login item in System Settings: the row says so
    /// and a second row leads there.
    func testALoginItemWaitingForApprovalShowsTheWayToSystemSettings() throws {
        let fake = install(.requiresApproval)
        let pane = try makePane(World())

        XCTAssertEqual(pane.launchOnLoginSwitch.state, .off, "it does not open at login yet")
        XCTAssertEqual(pane.launchOnLoginRow.explanation, "Waiting for your approval in System Settings.")
        XCTAssertFalse(pane.loginApprovalRow.isHidden)
        XCTAssertEqual(pane.loginApprovalRow.title, "Approve in System Settings")
        XCTAssertEqual(pane.openLoginItemsButton.title, "Open Login Items")
        XCTAssertEqual(pane.openLoginItemsButton.bezelStyle, .push)
        XCTAssertEqual(fake.openSettingsCalls, 0, "showing the row opens nothing")

        click(pane.openLoginItemsButton)
        XCTAssertEqual(fake.openSettingsCalls, 1)
        XCTAssertEqual(fake.registerCalls, 0)
        XCTAssertEqual(fake.unregisterCalls, 0)
    }

    func testTheApprovalRowFollowsTheSystem() throws {
        let fake = install(.requiresApproval)
        let pane = try makePane(World())
        let waitingHeight = pane.view.fittingSize.height
        XCTAssertFalse(pane.loginApprovalRow.isHidden)

        // Approved in System Settings; the pane appears again.
        fake.status = .enabled
        pane.viewWillAppear()
        XCTAssertTrue(pane.loginApprovalRow.isHidden)
        XCTAssertEqual(pane.launchOnLoginSwitch.state, .on)
        XCTAssertEqual(pane.launchOnLoginRow.explanation, "Scrollio starts when you log in to your Mac.")
        XCTAssertLessThan(pane.view.fittingSize.height, waitingHeight)
        XCTAssertEqual(pane.view.frame.size, pane.view.fittingSize, "the pane keeps its content size")
    }

    func testSwitchingOffAWaitingItemRemovesItAndTheApprovalRow() throws {
        let fake = install(.requiresApproval)
        let pane = try makePane(World())
        pane.launchOnLoginSwitch.state = .off
        pane.launchOnLoginClick(pane.launchOnLoginSwitch)
        XCTAssertEqual(fake.unregisterCalls, 1)
        XCTAssertTrue(pane.loginApprovalRow.isHidden)
    }

    // MARK: - Show in menu bar

    /// The switch shows the stored "hide" the other way round; the key and its meaning stay.
    func testShowInMenuBarIsTheInvertedHideSetting() throws {
        install(.notRegistered)
        let world = World()
        let pane = try makePane(world)
        XCTAssertEqual(pane.showInMenuBarRow.title, "Show in menu bar")
        XCTAssertEqual(
            pane.showInMenuBarRow.explanation,
            "When it's off, open Scrollio again to reach its settings. Pause is also at the top of General."
        )
        XCTAssertEqual(pane.showInMenuBarSwitch.state, .on)

        pane.showInMenuBarSwitch.state = .off
        pane.showInMenuBarClick(pane.showInMenuBarSwitch)
        XCTAssertTrue(world.menuBarIconHidden, "off hides the icon")
        XCTAssertEqual(pane.showInMenuBarSwitch.state, .off)

        pane.showInMenuBarSwitch.state = .on
        pane.showInMenuBarClick(pane.showInMenuBarSwitch)
        XCTAssertFalse(world.menuBarIconHidden)

        // A hidden icon stored earlier shows as off.
        let hiddenWorld = World()
        hiddenWorld.menuBarIconHidden = true
        let hiddenPane = try makePane(hiddenWorld)
        XCTAssertEqual(hiddenPane.showInMenuBarSwitch.state, .off)
    }

    func testTheMenuBarSwitchStoresTheSameKeyAsBefore() {
        // The default seams write the old option, whose key is unchanged.
        XCTAssertEqual(OptionItem.General.HideStatusItem, "hideStatusItem")
        let pane = PreferencesGeneralViewController()
        let saved = Options.shared.general.hideStatusItem
        XCTAssertEqual(pane.isMenuBarIconHidden(), saved)
    }

    // MARK: - Accessibility

    func testTheAccessibilityRowSaysAllowed() throws {
        install(.notRegistered)
        let world = World()
        world.access = true
        let pane = try makePane(world)
        XCTAssertEqual(pane.accessibilityRow.title, "Accessibility")
        XCTAssertEqual(
            pane.accessibilityRow.explanation,
            "Lets Scrollio read the mouse and keyboard to smooth scrolling and run your buttons."
        )
        XCTAssertEqual(pane.accessibilityStatusLabel.stringValue, "Allowed")
        XCTAssertTrue(pane.hasAccess)
        XCTAssertTrue(pane.openAccessibilitySettingsButton.isHidden)
        XCTAssertEqual(pane.accessibilityStatusIcon.contentTintColor, .systemGreen)
        XCTAssertNotNil(pane.accessibilityStatusIcon.image)
        XCTAssertTrue(shownTexts(pane).contains("Permissions"))
    }

    /// Without access the row says "Not allowed." with its orange sign; the way to System
    /// Settings is the row under the card's, once on the pane (its own button stays hidden
    /// while that row offers it).
    func testWithoutAccessTheRowSaysSoAndTheRowUnderTheCardLeadsToSystemSettings() throws {
        install(.notRegistered)
        let world = World()
        world.access = false
        let pane = try makePane(world)
        XCTAssertEqual(pane.accessibilityStatusLabel.stringValue, "Not allowed")
        XCTAssertEqual(pane.accessibilityStatusIcon.contentTintColor, .systemOrange)
        XCTAssertEqual(pane.runStatus.action, .allowAccess)
        XCTAssertTrue(pane.openAccessibilitySettingsButton.isHidden, "the row under the card offers it")
        XCTAssertEqual(shownButtons(titled: "Open System Settings", in: pane), [pane.statusButton])
        // Where it leads, in the words of macOS's own alert (not "Open Settings…", which the
        // Welcome Guide uses for Scrollio's own settings).
        XCTAssertEqual(pane.openAccessibilitySettingsButton.title, "Open System Settings")
        // "Not allowed" is said in the row's line; the orange sign stands alone, so the line
        // keeps room for two lines (it was a narrow column of three).
        XCTAssertTrue(pane.accessibilityStatusLabel.isHidden)
        XCTAssertFalse(pane.accessibilityStatusIcon.isHidden)
        XCTAssertEqual(
            pane.accessibilityRow.explanation,
            "Not allowed. Scrollio needs this to smooth scrolling and run your buttons."
        )
        XCTAssertEqual(pane.openAccessibilitySettingsButton.accessibilityHelp(), pane.accessibilityRow.explanation)
        pane.view.layoutSubtreeIfNeeded()
        let measure = NSTextField(wrappingLabelWithString: "X")
        measure.font = PreferencesForm.hintFont
        XCTAssertLessThanOrEqual(
            pane.accessibilityRow.explanationLabel.frame.height, 2 * measure.fittingSize.height + 0.5, "two lines at most"
        )
        XCTAssertEqual(world.accessibilitySettingsOpened, 0, "showing the row opens nothing")

        click(pane.statusButton)
        XCTAssertEqual(world.accessibilitySettingsOpened, 1)
    }

    /// With access, no "Open System Settings" at all.
    func testWithAccessNoButtonLeadsToSystemSettings() throws {
        install(.notRegistered)
        let world = World()
        let pane = try makePane(world)
        XCTAssertTrue(shownButtons(titled: "Open System Settings", in: pane).isEmpty)
    }

    /// The push buttons titled `title` that show on the pane.
    private func shownButtons(titled title: String, in pane: PreferencesGeneralViewController) -> [NSButton] {
        func buttons(in view: NSView) -> [NSButton] {
            let own = (view as? NSButton).map { [$0] } ?? []
            return own + view.subviews.flatMap(buttons(in:))
        }
        return buttons(in: pane.view).filter { $0.title == title && !$0.isHiddenOrHasHiddenAncestor }
    }

    /// The access was turned off while Scrollio ran, and came back later.
    func testTheAccessibilityRowFollowsThePermission() throws {
        install(.notRegistered)
        let world = World()
        let pane = try makePane(world)
        XCTAssertEqual(pane.accessibilityStatusLabel.stringValue, "Allowed")

        world.access = false
        NotificationCenter.default.post(name: .scrollioAccessibilityPermissionLost, object: nil)
        XCTAssertEqual(pane.accessibilityStatusLabel.stringValue, "Not allowed")
        XCTAssertTrue(pane.accessibilityStatusLabel.isHidden, "said in the row's line")
        XCTAssertEqual(pane.accessibilityRow.explanation?.hasPrefix("Not allowed. "), true)
        XCTAssertTrue(pane.openAccessibilitySettingsButton.isHidden, "the row under the card offers it")
        XCTAssertEqual(pane.statusButton.title, "Open System Settings")

        world.access = true
        NotificationCenter.default.post(name: AppRunController.didChangeNotification, object: nil)
        XCTAssertEqual(pane.accessibilityStatusLabel.stringValue, "Allowed")
        XCTAssertFalse(pane.accessibilityStatusLabel.isHidden)
        XCTAssertEqual(
            pane.accessibilityRow.explanation,
            "Lets Scrollio read the mouse and keyboard to smooth scrolling and run your buttons."
        )
        XCTAssertTrue(pane.openAccessibilitySettingsButton.isHidden)
    }

    func testTheAccessibilityRowIsReadAgainWhenTheWindowBecomesKey() throws {
        install(.notRegistered)
        let world = World()
        world.access = false
        let pane = try makePane(world)
        let window = NSWindow(
            contentRect: NSRect(x: -20000, y: -20000, width: 520, height: 300),
            styleMask: [.titled], backing: .buffered, defer: true
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = pane
        defer { window.contentViewController = nil }

        // Allowed in System Settings; back in the window.
        world.access = true
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        XCTAssertEqual(pane.accessibilityStatusLabel.stringValue, "Allowed")

        // Another window becoming key is none of the pane's business.
        world.access = false
        let other = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        other.isReleasedWhenClosed = false
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: other)
        XCTAssertEqual(pane.accessibilityStatusLabel.stringValue, "Allowed")
    }

    // MARK: - No developer tools

    /// The scroll monitor and the Logitech diagnostics are developer tools: they left the
    /// pane with its "Advanced" box (the status-bar menu lists them while Option is held).
    /// The pane no longer reads or writes the stored "Advanced is open"
    /// (`generalAdvancedExpanded`, kept by name in StoredDataCanaryTests).
    func testThePaneHasNoDeveloperToolsAndNoAdvanced() throws {
        install(.notRegistered)
        let pane = try makePane(World())
        let texts = shownTexts(pane) + allSubviews(of: pane.view).compactMap { ($0 as? NSButton)?.title }
        for word in ["Advanced", "Scroll monitor", "Scroll Monitor", "Diagnostics", "diagnostics", "Toasts"] {
            XCTAssertFalse(texts.contains { $0.contains(word) }, "\(word) in \(texts)")
        }
        XCTAssertFalse(allSubviews(of: pane.view).contains { $0 is PreferencesDisclosureRow })
        XCTAssertEqual(pane.view.frame.size, pane.view.fittingSize)
        // The boxes: the card, whether Scrollio works, startup, permissions, updates, the settings file,
        // the Welcome Guide, the credit.
        let content = try XCTUnwrap(pane.headerView.superview as? NSStackView)
        XCTAssertEqual(content.arrangedSubviews.filter { $0 is PreferencesGroupSection }.count, 6)
        for removed in ["general-advanced", "general-scroll-monitor", "general-diagnostics", "general-open-window"] {
            XCTAssertEqual(NSLocalizedString(removed, comment: ""), removed, "\(removed) left the catalog")
        }
    }

    // MARK: - Updates

    /// A released copy, as the updater reports it.
    private func updating(
        checks: Bool = true, installs: Bool = false, canCheck: Bool = true,
        lastCheck: Date? = nil, waiting: String? = nil
    ) -> UpdateStatus {
        return UpdateStatus(
            availability: .available, canCheck: canCheck, checksAutomatically: checks,
            installsAutomatically: installs, canInstallAutomatically: checks,
            lastCheck: lastCheck, waitingVersion: waiting
        )
    }

    private func shownRows(of section: PreferencesGroupSection) -> [PreferencesGroupRow] {
        return allSubviews(of: section).compactMap { $0 as? PreferencesGroupRow }.filter(isShown)
    }

    /// Built from source (scripts/install.sh, Xcode): one line, no control, nothing to switch.
    func testACopyBuiltFromSourceSaysItDoesNotUpdateItself() throws {
        install(.notRegistered)
        let world = World()
        let pane = try makePane(world)
        let section = try XCTUnwrap(pane.updatesSection)
        XCTAssertTrue(isShown(section))
        XCTAssertEqual(shownRows(of: section).map(\.title), ["Automatic updates"])
        XCTAssertEqual(pane.updatesUnavailableRow.explanation, "This copy was built from source, so it does not update itself.")
        XCTAssertTrue(pane.updatesUnavailableRow.controls.isEmpty)
        for hidden in [pane.updatesAutomaticRow!, pane.updatesInstallRow!, pane.updatesCheckRow!] {
            XCTAssertFalse(isShown(hidden), hidden.title)
        }
        XCTAssertFalse(shownTexts(pane).contains("Check Now"))
        XCTAssertEqual(pane.view.frame.size, pane.view.fittingSize)
        // After the permissions; the settings file and the Welcome Guide follow.
        let content = try XCTUnwrap(pane.headerView.superview as? NSStackView)
        let sections = content.arrangedSubviews.filter { $0 is PreferencesGroupSection && !$0.isHidden }
        XCTAssertTrue(sections.dropLast(2).last === section)
        XCTAssertTrue(sections.dropLast().last === pane.settingsFileSection)
    }

    func testFromADiskImageOrAfterAFailedStartItSaysWhy() throws {
        install(.notRegistered)
        let world = World()
        world.updates = UpdateStatus(availability: .wrongPlace)
        var pane = try makePane(world)
        XCTAssertEqual(
            pane.updatesUnavailableRow.explanation,
            "Scrollio cannot update itself while it runs from a disk image. Move it to the Applications folder and open it from there."
        )
        world.updates = UpdateStatus(availability: .failed)
        pane = try makePane(world)
        XCTAssertEqual(pane.updatesUnavailableRow.explanation, "The updater could not start. New versions are on Scrollio's GitHub page.")
        XCTAssertEqual(pane.view.frame.size, pane.view.fittingSize)
    }

    /// A released copy: the two switches and the check.
    func testAReleasedCopyHasTheSwitchesAndTheCheck() throws {
        install(.notRegistered)
        let world = World()
        world.updates = updating(checks: true, installs: false)
        let pane = try makePane(world)
        XCTAssertEqual(
            shownRows(of: pane.updatesSection).map(\.title),
            ["Check for updates automatically", "Install updates automatically", "Check for updates"]
        )
        XCTAssertFalse(isShown(pane.updatesUnavailableRow))
        XCTAssertEqual(
            pane.updatesAutomaticRow.explanation,
            "Once a day Scrollio asks GitHub whether there is a newer version. None of your settings or data is sent."
        )
        XCTAssertEqual(
            pane.updatesInstallRow.explanation,
            "A new version is downloaded in the background and installed the next time Scrollio quits, for example when your Mac restarts."
        )
        XCTAssertTrue(pane.updatesAutomaticRow.isOn)
        XCTAssertFalse(pane.updatesInstallRow.isOn)
        XCTAssertTrue(pane.updatesInstallRow.isEnabled)
        XCTAssertEqual(pane.updatesCheckRow.explanation, "Not checked yet.")
        XCTAssertEqual(pane.updatesCheckButton.title, "Check Now")
        XCTAssertEqual(pane.updatesCheckButton.bezelStyle, .push)
        XCTAssertEqual(pane.view.frame.size, pane.view.fittingSize)
        pane.view.layoutSubtreeIfNeeded()
        XCTAssertFalse(pane.view.hasAmbiguousLayout)

        click(pane.updatesCheckButton)
        XCTAssertEqual(world.updateChecks, 1)
        XCTAssertEqual(world.openedURLs, [])
        XCTAssertEqual(world.automaticChecksSet, [])
    }

    /// The switches go to the updater, which stores them; the pane shows what it then says.
    func testTheSwitchesGoToTheUpdater() throws {
        install(.notRegistered)
        let world = World()
        world.updates = updating(checks: true, installs: false)
        let pane = try makePane(world)

        pane.updatesInstallRow.toggle.state = .on
        XCTAssertTrue(pane.updatesInstallRow.toggle.sendAction(pane.updatesInstallRow.toggle.action, to: pane.updatesInstallRow.toggle.target))
        XCTAssertEqual(world.automaticInstallSet, [true])
        XCTAssertTrue(pane.updatesInstallRow.isOn)

        // Without the automatic checks nothing can install itself: the second switch dims.
        pane.updatesAutomaticRow.toggle.state = .off
        XCTAssertTrue(pane.updatesAutomaticRow.toggle.sendAction(pane.updatesAutomaticRow.toggle.action, to: pane.updatesAutomaticRow.toggle.target))
        XCTAssertEqual(world.automaticChecksSet, [false])
        XCTAssertFalse(pane.updatesAutomaticRow.isOn)
        XCTAssertFalse(pane.updatesInstallRow.isEnabled)
        // "Check Now" stays: asking by hand needs no switch.
        XCTAssertTrue(pane.updatesCheckButton.isEnabled)
        XCTAssertEqual(world.updateChecks, 0)
    }

    func testTheCheckRowSaysWhenScrollioLastAsked() throws {
        install(.notRegistered)
        let world = World()
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(identifier: "UTC")
        (components.year, components.month, components.day, components.hour, components.minute) = (2026, 11, 12, 8, 12)
        let date = try XCTUnwrap(components.date)
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        XCTAssertEqual(
            PreferencesGeneralViewController.lastCheckText(date, locale: Locale(identifier: "en_GB"), timeZone: utc),
            "Last checked 12 Nov 2026 at 08:12."
        )
        XCTAssertEqual(PreferencesGeneralViewController.lastCheckText(nil), "Not checked yet.")

        world.updates = updating(lastCheck: date)
        let pane = try makePane(world)
        XCTAssertEqual(pane.updatesCheckRow.explanation, PreferencesGeneralViewController.lastCheckText(date))
        XCTAssertTrue(pane.updatesCheckRow.explanation?.hasPrefix("Last checked ") ?? false)
    }

    /// While a check runs in the background another cannot start.
    func testCheckNowIsDimmedWhileACheckRuns() throws {
        install(.notRegistered)
        let world = World()
        world.updates = updating(canCheck: false)
        let pane = try makePane(world)
        XCTAssertFalse(pane.updatesCheckButton.isEnabled)
        XCTAssertTrue(isShown(pane.updatesCheckButton))
    }

    /// A found update that waits: the row names the version and leads to Sparkle's window.
    func testAWaitingUpdateIsNamedAndOpened() throws {
        install(.notRegistered)
        let world = World()
        world.updates = updating(waiting: "1.1.0")
        let pane = try makePane(world)
        XCTAssertEqual(pane.updatesCheckRow.title, "Scrollio 1.1.0 is available")
        XCTAssertEqual(pane.updatesCheckRow.explanation, "See what is new and install it.")
        XCTAssertEqual(pane.updatesCheckButton.title, "Update…")
        XCTAssertTrue(pane.updatesCheckButton.accessibilityTitleUIElement() as? NSTextField === pane.updatesCheckRow.titleLabel)
        click(pane.updatesCheckButton)
        XCTAssertEqual(world.updateChecks, 1)
        XCTAssertEqual(pane.view.frame.size, pane.view.fittingSize)
    }

    /// What the updater changes by itself reaches an open pane: a check that ended, an
    /// update that was found or answered, the answer to Sparkle's own question.
    func testThePaneFollowsTheUpdater() throws {
        install(.notRegistered)
        let world = World()
        world.updates = updating(checks: false)
        let pane = try makePane(world)
        XCTAssertFalse(pane.updatesAutomaticRow.isOn)
        XCTAssertEqual(pane.updatesCheckRow.title, "Check for updates")

        world.updates = updating(checks: true, waiting: "1.2.0")
        NotificationCenter.default.post(name: UpdateCenter.didChangeNotification, object: nil)
        XCTAssertTrue(pane.updatesAutomaticRow.isOn)
        XCTAssertEqual(pane.updatesCheckRow.title, "Scrollio 1.2.0 is available")

        world.updates = updating(checks: true)
        NotificationCenter.default.post(name: UpdateCenter.didChangeNotification, object: nil)
        XCTAssertEqual(pane.updatesCheckRow.title, "Check for updates")
        XCTAssertEqual(pane.updatesCheckButton.title, "Check Now")
        XCTAssertEqual(pane.view.frame.size, pane.view.fittingSize)
    }

    func testTheUpdateControlsAreNamedByTheirRows() throws {
        install(.notRegistered)
        let world = World()
        world.updates = updating()
        let pane = try makePane(world)
        XCTAssertEqual(pane.updatesAutomaticRow.toggle.accessibilityLabel(), "Check for updates automatically")
        XCTAssertEqual(pane.updatesInstallRow.toggle.accessibilityLabel(), "Install updates automatically")
        XCTAssertTrue(pane.updatesCheckButton.accessibilityTitleUIElement() as? NSTextField === pane.updatesCheckRow.titleLabel)
        XCTAssertEqual(pane.updatesAutomaticRow.toggle.controlSize, PreferencesGroupedForm.switchControlSize)
    }

    // MARK: - Kit and wording

    func testEveryControlIsNamedByItsRow() throws {
        install(.requiresApproval)
        let world = World()
        world.access = false
        let pane = try makePane(world)
        XCTAssertEqual(pane.launchOnLoginSwitch.accessibilityLabel(), "Open at login")
        XCTAssertEqual(pane.showInMenuBarSwitch.accessibilityLabel(), "Show in menu bar")
        // Push buttons keep their titles and point at the row's title.
        for (button, row) in [
            (pane.openLoginItemsButton!, pane.loginApprovalRow!),
            (pane.openAccessibilitySettingsButton!, pane.accessibilityRow!),
            (pane.welcomeGuideButton!, pane.welcomeGuideRow!),
            (pane.gitHubButton!, pane.gitHubRow!),
        ] {
            XCTAssertTrue(button.accessibilityTitleUIElement() as? NSTextField === row.titleLabel, button.title)
        }
        XCTAssertEqual(pane.launchOnLoginSwitch.controlSize, PreferencesGroupedForm.switchControlSize)
    }

    func testNoJargonAndNoNegativeSwitch() throws {
        install(.requiresApproval)
        let world = World()
        world.access = false
        let pane = try makePane(world)
        let texts = shownTexts(pane)
        for word in ["Hide", "status bar", "Preferences", "re-run"] {
            XCTAssertFalse(texts.contains { $0.localizedCaseInsensitiveContains(word) }, "\(word) in \(texts)")
        }
    }

    func testThePaneHasTheColumnWidthAndFitsItsContent() throws {
        for status in [LoginItemStatus.notRegistered, .requiresApproval] {
            for access in [true, false] {
                install(status)
                let world = World()
                world.access = access
                let pane = try makePane(world)
                let name = "\(status) access \(access)"
                XCTAssertEqual(pane.view.frame.width, PreferencesWindowLayout.contentWidth, name)
                XCTAssertEqual(pane.view.frame.size, pane.view.fittingSize, name)
                pane.view.layoutSubtreeIfNeeded()
                XCTAssertFalse(pane.view.hasAmbiguousLayout, name)
                // The Accessibility row's text and its status do not overlap, and the status
                // keeps the row's inset (compared by alignment rects, as Auto Layout places them).
                let row = pane.accessibilityRow!
                func alignment(_ view: NSView) -> NSRect {
                    return row.convert(view.alignmentRect(forFrame: view.frame), from: view.superview)
                }
                // Allowed: the check and "Allowed"; not allowed: the sign alone (the row under
                // the card offers "Open System Settings").
                let sign = alignment(pane.accessibilityStatusIcon)
                let status = access ? alignment(pane.accessibilityStatusLabel) : sign
                XCTAssertLessThanOrEqual(sign.maxX, access ? status.minX : sign.maxX, name)
                let explanation = alignment(row.explanationLabel)
                XCTAssertLessThanOrEqual(explanation.maxX, sign.minX, name)
                XCTAssertLessThanOrEqual(explanation.maxX, status.minX, name)
                XCTAssertLessThanOrEqual(status.maxX, row.bounds.maxX - PreferencesGroupedForm.rowHorizontalInset + 0.5, name)
            }
        }
    }
}
