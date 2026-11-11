//
//  PreferencesGeneralTests.swift
//  MosTests
//
//  The General pane: the card with the app's name and version (what the About pane
//  showed), "Scrollio is paused" with Resume, "Open at login" and its approval row, "Show
//  in menu bar" (the stored "hide" shown the other way round), the Accessibility row, no
//  developer tools, and at the bottom the Welcome Guide, Scrollio on GitHub and the credit
//  line. The login item, the permission, the pause, System Settings, the menu bar icon, the
//  windows and the browser are replaced; nothing is shown on screen and no page is opened.
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
        var resumes = 0
        var welcomeGuidesOpened = 0
        var openedURLs: [URL] = []
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
        pane.resume = {
            world.resumes += 1
            world.paused = false
        }
        pane.showWelcomeGuide = { world.welcomeGuidesOpened += 1 }
        pane.openURL = { world.openedURLs.append($0) }
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
        XCTAssertEqual(pane.welcomeGuideButton.title, "Open…", "it opens a window")
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

    // MARK: - Paused

    /// "Pause Scrollio" is only in the status-bar menu: with the menu bar icon hidden, the
    /// pane is the way back.
    func testWhilePausedTheTopRowSaysSoAndResumes() throws {
        install(.notRegistered)
        let world = World()
        let pane = try makePane(world)
        let content = try XCTUnwrap(pane.pausedSection.superview as? NSStackView)
        XCTAssertTrue(content.arrangedSubviews.first === pane.headerView)
        XCTAssertTrue(content.arrangedSubviews[1] === pane.pausedSection, "right under the card")
        XCTAssertTrue(pane.pausedSection.isHidden, "not while running")
        XCTAssertFalse(shownTexts(pane).contains("Scrollio is paused"))
        let runningHeight = pane.view.frame.height

        // Paused from the menu: the run controller says so.
        world.paused = true
        NotificationCenter.default.post(name: AppRunController.didChangeNotification, object: nil)
        XCTAssertFalse(pane.pausedSection.isHidden)
        XCTAssertEqual(pane.pausedRow.title, "Scrollio is paused")
        XCTAssertEqual(pane.pausedRow.explanation, "Scrolling, buttons and gestures are off until you resume.")
        XCTAssertEqual(pane.resumeButton.title, "Resume")
        XCTAssertTrue(pane.resumeButton.accessibilityTitleUIElement() as? NSTextField === pane.pausedRow.titleLabel)
        XCTAssertGreaterThan(pane.view.frame.height, runningHeight, "the pane makes room for it")
        XCTAssertEqual(pane.view.frame.size, pane.view.fittingSize)

        click(pane.resumeButton)
        XCTAssertEqual(world.resumes, 1)
        XCTAssertTrue(pane.pausedSection.isHidden)
        XCTAssertEqual(pane.view.frame.height, runningHeight, accuracy: 0.5)

        // Paused while the pane was not showing: it shows when the pane appears.
        world.paused = true
        pane.viewWillAppear()
        XCTAssertFalse(pane.pausedSection.isHidden)
    }

    // MARK: - Open at login

    func testOpenAtLoginSaysWhatItDoes() throws {
        install(.notRegistered)
        let pane = try makePane(World())
        XCTAssertEqual(pane.launchOnLoginRow.title, "Open at login")
        XCTAssertEqual(pane.launchOnLoginRow.explanation, "Scrollio starts when you log in to your Mac.")
        XCTAssertTrue(pane.loginApprovalRow.isHidden)
        XCTAssertFalse(shownTexts(pane).contains("Open Login Items…"))
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
        XCTAssertEqual(pane.openLoginItemsButton.title, "Open Login Items…")
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
        XCTAssertEqual(pane.showInMenuBarRow.explanation, "When it's off, open Scrollio again to reach its settings.")
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

    func testWithoutAccessTheRowLeadsToSystemSettings() throws {
        install(.notRegistered)
        let world = World()
        world.access = false
        let pane = try makePane(world)
        XCTAssertEqual(pane.accessibilityStatusLabel.stringValue, "Not allowed")
        XCTAssertEqual(pane.accessibilityStatusIcon.contentTintColor, .systemOrange)
        XCTAssertFalse(pane.openAccessibilitySettingsButton.isHidden)
        XCTAssertEqual(pane.openAccessibilitySettingsButton.title, "Open Settings…")
        XCTAssertEqual(world.accessibilitySettingsOpened, 0, "showing the row opens nothing")

        click(pane.openAccessibilitySettingsButton)
        XCTAssertEqual(world.accessibilitySettingsOpened, 1)
    }

    /// The access was turned off while Scrollio ran, and came back later.
    func testTheAccessibilityRowFollowsThePermission() throws {
        install(.notRegistered)
        let world = World()
        let pane = try makePane(world)
        XCTAssertEqual(pane.accessibilityStatusLabel.stringValue, "Allowed")

        world.access = false
        NotificationCenter.default.post(name: .mosAccessibilityPermissionLost, object: nil)
        XCTAssertEqual(pane.accessibilityStatusLabel.stringValue, "Not allowed")
        XCTAssertFalse(pane.openAccessibilitySettingsButton.isHidden)

        world.access = true
        NotificationCenter.default.post(name: AppRunController.didChangeNotification, object: nil)
        XCTAssertEqual(pane.accessibilityStatusLabel.stringValue, "Allowed")
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
        // The boxes: the card, (paused), startup, permissions, the Welcome Guide, the credit.
        let content = try XCTUnwrap(pane.headerView.superview as? NSStackView)
        XCTAssertEqual(content.arrangedSubviews.filter { $0 is PreferencesGroupSection }.count, 4)
        for removed in ["general-advanced", "general-scroll-monitor", "general-diagnostics", "general-open-window"] {
            XCTAssertEqual(NSLocalizedString(removed, comment: ""), removed, "\(removed) left the catalog")
        }
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
                let status = alignment(pane.accessibilityStatusLabel)
                let explanation = alignment(row.explanationLabel)
                XCTAssertLessThanOrEqual(explanation.maxX, status.minX, name)
                XCTAssertLessThanOrEqual(status.maxX, row.bounds.maxX - PreferencesGroupedForm.rowHorizontalInset + 0.5, name)
            }
        }
    }
}
