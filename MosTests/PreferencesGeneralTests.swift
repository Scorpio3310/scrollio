//
//  PreferencesGeneralTests.swift
//  MosTests
//
//  The General pane: "Open at login" and its approval row, "Show in menu bar" (the stored
//  "hide" shown the other way round), the Accessibility row and "Advanced". The login item,
//  the permission, System Settings, the menu bar icon and the windows are replaced; nothing
//  is shown on screen.
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
        var monitorsOpened = 0
        var diagnosticsOpened = 0
    }

    private var savedAutoLaunch = false
    private var suite = ""
    private var uiDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        savedAutoLaunch = Options.shared.general.autoLaunch
        suite = "ScrollioTests.general.\(UUID().uuidString)"
        uiDefaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        LoginItem.service = InertLoginItemService()
        Options.shared.general.autoLaunch = savedAutoLaunch
        LoginItem.service = LoginItem.defaultService
        uiDefaults.removePersistentDomain(forName: suite)
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
        pane.openScrollMonitor = { world.monitorsOpened += 1 }
        pane.openDiagnostics = { world.diagnosticsOpened += 1 }
        pane.uiStateDefaults = uiDefaults
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

    // MARK: - Advanced

    func testAdvancedIsClosedByDefaultAndRemembersItsState() throws {
        install(.notRegistered)
        let world = World()
        let pane = try makePane(world)
        XCTAssertFalse(pane.isAdvancedExpanded)
        XCTAssertEqual(pane.advancedRow.button.title, "Advanced")
        XCTAssertTrue(pane.scrollMonitorRow.isHidden)
        XCTAssertTrue(pane.diagnosticsRow.isHidden)
        let closedHeight = pane.view.fittingSize.height

        click(pane.advancedRow.button)
        XCTAssertTrue(pane.isAdvancedExpanded)
        XCTAssertFalse(pane.scrollMonitorRow.isHidden)
        XCTAssertFalse(pane.diagnosticsRow.isHidden)
        XCTAssertTrue(uiDefaults.bool(forKey: PreferencesGeneralViewController.advancedExpandedDefaultsKey))
        XCTAssertEqual(PreferencesGeneralViewController.advancedExpandedDefaultsKey, "generalAdvancedExpanded")
        XCTAssertGreaterThan(pane.view.fittingSize.height, closedHeight)
        XCTAssertEqual(pane.view.frame.size, pane.view.fittingSize)

        // A pane made later opens with it.
        let again = try makePane(world)
        XCTAssertTrue(again.isAdvancedExpanded)
        XCTAssertFalse(again.scrollMonitorRow.isHidden)
        XCTAssertEqual(again.view.frame.size, again.view.fittingSize)
    }

    func testAdvancedOpensTheDiagnosticWindows() throws {
        install(.notRegistered)
        let world = World()
        uiDefaults.set(true, forKey: PreferencesGeneralViewController.advancedExpandedDefaultsKey)
        let pane = try makePane(world)

        XCTAssertEqual(pane.scrollMonitorRow.title, "Scroll monitor")
        XCTAssertEqual(pane.scrollMonitorRow.explanation, "A live chart of wheel events. Scrolling is slower while it's open.")
        XCTAssertEqual(pane.diagnosticsRow.title, "Logitech diagnostics")
        XCTAssertEqual(pane.diagnosticsRow.explanation, "Technical details of connected Logitech mice, for troubleshooting.")
        XCTAssertEqual(pane.scrollMonitorButton.title, "Open…")
        XCTAssertEqual(pane.diagnosticsButton.title, "Open…")

        click(pane.scrollMonitorButton)
        XCTAssertEqual(world.monitorsOpened, 1)
        XCTAssertEqual(world.diagnosticsOpened, 0)
        click(pane.diagnosticsButton)
        XCTAssertEqual(world.diagnosticsOpened, 1)
    }

    // MARK: - Kit and wording

    func testEveryControlIsNamedByItsRow() throws {
        install(.requiresApproval)
        uiDefaults.set(true, forKey: PreferencesGeneralViewController.advancedExpandedDefaultsKey)
        let world = World()
        world.access = false
        let pane = try makePane(world)
        XCTAssertEqual(pane.launchOnLoginSwitch.accessibilityLabel(), "Open at login")
        XCTAssertEqual(pane.showInMenuBarSwitch.accessibilityLabel(), "Show in menu bar")
        // Push buttons keep their titles and point at the row's title.
        for (button, row) in [
            (pane.openLoginItemsButton!, pane.loginApprovalRow!),
            (pane.openAccessibilitySettingsButton!, pane.accessibilityRow!),
            (pane.scrollMonitorButton!, pane.scrollMonitorRow!),
            (pane.diagnosticsButton!, pane.diagnosticsRow!),
        ] {
            XCTAssertTrue(button.accessibilityTitleUIElement() as? NSTextField === row.titleLabel, button.title)
        }
        XCTAssertEqual(pane.launchOnLoginSwitch.controlSize, PreferencesGroupedForm.switchControlSize)
    }

    func testNoJargonAndNoNegativeSwitch() throws {
        install(.requiresApproval)
        uiDefaults.set(true, forKey: PreferencesGeneralViewController.advancedExpandedDefaultsKey)
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
