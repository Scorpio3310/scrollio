//
//  PreferencesWindowTests.swift
//  MosTests
//
//  The Preferences window as a whole: which tabs it has and in which order, and the
//  About pane that is built in code. Nothing is shown on screen.
//

import XCTest
@testable import Mos_Debug

private func allSubviews(of view: NSView) -> [NSView] {
    return view.subviews.flatMap { [$0] + allSubviews(of: $0) }
}

final class PreferencesTabsTests: XCTestCase {

    private func makeTabs() throws -> PreferencesTabViewController {
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesTabViewController.self))
        let windowController = try XCTUnwrap(
            storyboard.instantiateController(withIdentifier: WINDOW_IDENTIFIER.preferencesWindowController) as? NSWindowController
        )
        let tabs = try XCTUnwrap(windowController.contentViewController as? PreferencesTabViewController)
        _ = tabs.view
        addTeardownBlock { windowController.close() }
        return tabs
    }

    func testTabsAreInOrderWithStableIdentifiers() throws {
        let tabs = try makeTabs()
        XCTAssertEqual(
            tabs.tabViewItems.map { $0.identifier as? String },
            ["general", "scrolling", "buttons", "mouse", "application", "about"]
        )
    }

    func testTabLabels() throws {
        let tabs = try makeTabs()
        XCTAssertEqual(
            tabs.tabViewItems.map(\.label),
            ["General", "Scrolling", "Buttons", "Mouse", "Apps", "About"]
        )
    }

    func testWindowTitleFollowsTheSelectedPane() throws {
        let tabs = try makeTabs()
        let window = try XCTUnwrap(tabs.view.window)

        // What viewWillAppear does for the pane the window opens with.
        tabs.updateWindowTitle()
        XCTAssertEqual(window.title, "General")

        for (index, item) in tabs.tabViewItems.enumerated() {
            tabs.selectedTabViewItemIndex = index
            XCTAssertEqual(window.title, item.label)
        }
        XCTAssertEqual(window.title, "About")
    }

    func testEveryTabHasAnImageAndAController() throws {
        let tabs = try makeTabs()
        for item in tabs.tabViewItems {
            XCTAssertNotNil(item.image, "\(item.label) has no toolbar image")
            XCTAssertNotNil(item.viewController, "\(item.label) has no view controller")
        }
    }

    func testCodeBuiltTabsUseTheirOwnControllers() throws {
        let tabs = try makeTabs()
        let controllers = Dictionary(uniqueKeysWithValues: tabs.tabViewItems.compactMap { item -> (String, NSViewController)? in
            guard let identifier = item.identifier as? String, let controller = item.viewController else { return nil }
            return (identifier, controller)
        })
        XCTAssertTrue(controllers["mouse"] is MousePreferencesViewController)
        XCTAssertTrue(controllers["about"] is AboutPreferencesViewController)
    }
}

final class PreferencesAboutTests: XCTestCase {

    private func makeController() -> AboutPreferencesViewController {
        let controller = AboutPreferencesViewController()
        controller.showWelcomeGuide = {}
        _ = controller.view
        return controller
    }

    func testShowsNameVersionAndCredit() {
        let controller = makeController()
        XCTAssertEqual(controller.title, "About")
        XCTAssertEqual(controller.nameLabel.stringValue, "Scrollio")
        XCTAssertEqual(controller.creditLabel.stringValue, "Based on Mos by Caldis · CC BY-NC 4.0 · modified")
        XCTAssertNotNil(controller.iconView.image)
    }

    func testVersionComesFromTheBundle() throws {
        let version = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        XCTAssertFalse(version.isEmpty)
        let controller = makeController()
        XCTAssertEqual(controller.versionLabel.stringValue, "Version \(version)")
        XCTAssertEqual(AboutPreferencesViewController.versionText(), "Version \(version)")
    }

    func testTheOnlyButtonIsTheWelcomeGuideLink() {
        var opened = 0
        let controller = makeController()
        controller.showWelcomeGuide = { opened += 1 }

        let buttons = allSubviews(of: controller.view).compactMap { $0 as? NSButton }
        XCTAssertEqual(buttons.count, 1)
        XCTAssertTrue(buttons.first === controller.welcomeGuideButton)
        XCTAssertEqual(controller.welcomeGuideButton.title, "Welcome Guide")
        XCTAssertFalse(controller.welcomeGuideButton.isBordered, "a link, not a push button")

        XCTAssertTrue(controller.welcomeGuideButton.sendAction(
            controller.welcomeGuideButton.action,
            to: controller.welcomeGuideButton.target
        ))
        XCTAssertEqual(opened, 1)
    }

    func testNothingOfTheOldAboutPaneIsLeft() {
        let controller = makeController()
        let removed = ["Home Page", "GitHub", "Contributors", "Donate", "Feed", "Welcome Window", "Buy me a coffee"]
        let views = allSubviews(of: controller.view)
        let texts = views.compactMap { ($0 as? NSTextField)?.stringValue } + views.compactMap { ($0 as? NSButton)?.title }
        for text in texts {
            for word in removed {
                XCTAssertFalse(text.localizedCaseInsensitiveContains(word), "'\(text)' still mentions \(word)")
            }
        }
        // The help button went with them.
        XCTAssertFalse(views.contains { ($0 as? NSButton)?.bezelStyle == .helpButton })
    }

    func testTheStoryboardNoLongerHoldsTheOldScenes() {
        // Instantiating a missing storyboard identifier raises, so the About tab is read
        // from the window instead: it is the controller built in code.
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesTabViewController.self))
        let windowController = storyboard.instantiateController(withIdentifier: WINDOW_IDENTIFIER.preferencesWindowController) as? NSWindowController
        let tabs = windowController?.contentViewController as? PreferencesTabViewController
        let about = tabs?.tabViewItems.first { ($0.identifier as? String) == AboutPreferencesViewController.tabIdentifier }
        XCTAssertTrue(about?.viewController is AboutPreferencesViewController)
        windowController?.close()
        for name in ["AlipayQR", "WechatpayQR", "PaypalLogo", "BuyMeACoffee", "MEOW"] {
            XCTAssertNil(NSImage(named: name), "donation asset \(name) is still in the bundle")
        }
    }

    func testPaneHasThePreferencesWidthAndFitsItsContent() {
        let controller = makeController()
        XCTAssertEqual(controller.view.frame.width, PreferencesForm.contentWidth)
        XCTAssertEqual(controller.view.frame.size, controller.view.fittingSize)
        controller.view.layoutSubtreeIfNeeded()
        for label in [controller.nameLabel!, controller.versionLabel!, controller.creditLabel!] {
            XCTAssertEqual(label.frame.midX, controller.view.bounds.midX, accuracy: 0.5)
            XCTAssertGreaterThanOrEqual(label.frame.minX, 0)
        }
        XCTAssertEqual(controller.iconView.frame.size, NSSize(width: 64, height: 64))
        XCTAssertEqual(controller.iconView.frame.midX, controller.view.bounds.midX, accuracy: 0.5)
    }
}

/// Names the redesign changed. Only what the user reads changed: every identifier that is
/// stored in the settings or used as a key stays as it was.
final class PreferencesNamingTests: XCTestCase {

    private let app = Bundle(for: PreferencesTabViewController.self)

    private func texts(in view: NSView) -> [String] {
        let views = allSubviews(of: view)
        return views.compactMap { ($0 as? NSTextField)?.stringValue } + views.compactMap { ($0 as? NSButton)?.title }
    }

    private func instantiate(_ identifier: String) -> NSViewController? {
        let storyboard = NSStoryboard(name: "Main", bundle: app)
        return storyboard.instantiateController(withIdentifier: identifier) as? NSViewController
    }

    func testScrollKeysHaveTheSameNamesInBothPlaces() throws {
        // Scrolling tab (storyboard)
        let scrolling = try XCTUnwrap(instantiate(PANEL_IDENTIFIER.scrolling))
        let shown = texts(in: scrolling.view)
        for name in ["Fast Scroll", "Horizontal Scroll", "Pause Smoothing"] {
            XCTAssertTrue(shown.contains(name), "\(name) is not in the Scrolling tab")
        }
        for old in ["Dash Key", "Toggle Key", "Block Key"] {
            XCTAssertFalse(shown.contains(old), "\(old) is still in the Scrolling tab")
        }

        // Button actions (code)
        XCTAssertEqual(SystemShortcut.mosScrollDash.localizedName, "Fast Scroll")
        XCTAssertEqual(SystemShortcut.mosScrollToggle.localizedName, "Horizontal Scroll")
        XCTAssertEqual(SystemShortcut.mosScrollBlock.localizedName, "Pause Smoothing")
    }

    func testScrollKeyIdentifiersAreUnchanged() {
        XCTAssertEqual(SystemShortcut.mosScrollDash.identifier, "mosScrollDash")
        XCTAssertEqual(SystemShortcut.mosScrollToggle.identifier, "mosScrollToggle")
        XCTAssertEqual(SystemShortcut.mosScrollBlock.identifier, "mosScrollBlock")
        XCTAssertEqual(
            SystemShortcut.mosMouseScrollCategory.shortcuts.map(\.identifier),
            ["mosScrollDash", "mosScrollToggle", "mosScrollBlock"]
        )
    }

    func testGlidePresetKeepsItsStoredName() {
        XCTAssertEqual(ScrollPreset.trackpadLike.localizedName, "Glide")
        XCTAssertEqual(ScrollPreset.trackpadLike.rawValue, "trackpadLike")
        XCTAssertEqual(
            ScrollPreset.allCases.map(\.localizedName),
            ["Direct", "Balanced", "Smooth", "Glide", "Magic Mouse"]
        )
    }

    func testTrackpadStyleEventsWording() throws {
        let popover = try XCTUnwrap(instantiate("scrollSmoothDetail") as? ScrollSmoothDetailSettingsPopoverViewController)
        _ = popover.view
        XCTAssertEqual(popover.simulateTrackpadCheckBox?.title, "Trackpad-style events (Beta)")
        XCTAssertEqual(
            NSLocalizedString("scrollDurationLockedMessage", comment: ""),
            "Trackpad-style events lock the duration"
        )
    }

    func testAnUnboundButtonSaysNoActionEverywhere() {
        XCTAssertEqual(NSLocalizedString("unbound", comment: ""), "No Action")
        XCTAssertEqual(NSLocalizedString("gesture-action-none", comment: ""), "No Action")
        XCTAssertEqual(ActionDisplayResolver().resolve(state: .unbound).title, "No Action")

        let menu = NSMenu()
        ShortcutManager.buildShortcutMenu(into: menu, target: self, action: #selector(noop(_:)))
        XCTAssertEqual(menu.items[2].title, "No Action")
        XCTAssertNil(menu.items[2].representedObject)
    }

    @objc private func noop(_ sender: Any?) {}

    func testGeneralTabSaysMenuBar() throws {
        let general = try XCTUnwrap(instantiate(PANEL_IDENTIFIER.general) as? PreferencesGeneralViewController)
        _ = general.view
        XCTAssertEqual(general.hideStatusBarIconCheckBox.title, "Hide Menu Bar Icon")
        let shown = texts(in: general.view)
        XCTAssertTrue(shown.contains("Menu Bar Icon"))
        XCTAssertTrue(shown.contains("Open Scrollio again to show the icon"))
        for text in shown {
            XCTAssertFalse(text.localizedCaseInsensitiveContains("status bar"), text)
            XCTAssertFalse(text.localizedCaseInsensitiveContains("re-run"), text)
        }

        // The "?" popover next to the checkbox.
        let hint = try XCTUnwrap(instantiate("menuBarIconHint"))
        XCTAssertEqual(
            texts(in: hint.view),
            ["While the icon is hidden, open Scrollio again to reach its settings."]
        )
    }
}
