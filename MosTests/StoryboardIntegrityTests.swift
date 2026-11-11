//
//  StoryboardIntegrityTests.swift
//  MosTests
//
//  Every scene of Main.storyboard that the app instantiates exists and loads. A dangling
//  outlet (a property removed from its class while the storyboard still connects it)
//  raises when the nib loads, and an identifier that is gone raises when it is
//  instantiated; both would crash the app the first time the window opens. Nothing is
//  shown on screen: views are loaded, windows are never ordered in.
//

import XCTest
@testable import Mos_Debug

final class StoryboardIntegrityTests: XCTestCase {

    private let bundle = Bundle(for: PreferencesTabViewController.self)

    private var storyboard: NSStoryboard {
        return NSStoryboard(name: "Main", bundle: bundle)
    }

    /// Window controllers the app opens through WindowManager.
    private let windowIdentifiers = [
        WINDOW_IDENTIFIER.preferencesWindowController,
        WINDOW_IDENTIFIER.monitorWindowController,
        WINDOW_IDENTIFIER.introductionWindowController,
    ]

    /// View controllers the app (or the preferences tests) instantiate by identifier, and
    /// the popovers that segues open.
    private let viewIdentifiers = PANEL_IDENTIFIER.list + [
        PANEL_IDENTIFIER.scrollingWithApplication,
        "menuBarIconHint", "allowlistHint", "scrollSmoothDetail", "scrollReverseDetail",
    ]

    /// Identifiers in the compiled storyboard, read from its Info.plist: instantiating a
    /// missing identifier raises an Objective-C exception that would end the whole run.
    private func compiledIdentifiers() throws -> Set<String> {
        let url = try XCTUnwrap(bundle.url(forResource: "Main", withExtension: "storyboardc"))
        let info = try XCTUnwrap(NSDictionary(contentsOf: url.appendingPathComponent("Info.plist")) as? [String: Any])
        let names = try XCTUnwrap(info["NSViewControllerIdentifiersToNibNames"] as? [String: String])
        return Set(names.keys)
    }

    func testEveryIdentifierTheCodeUsesExists() throws {
        let compiled = try compiledIdentifiers()
        for identifier in windowIdentifiers + viewIdentifiers {
            XCTAssertTrue(compiled.contains(identifier), "Main.storyboard has no scene \"\(identifier)\"")
        }
    }

    func testEveryWindowSceneLoadsItsWindowAndContent() throws {
        let compiled = try compiledIdentifiers()
        for identifier in windowIdentifiers where compiled.contains(identifier) {
            let controller = try XCTUnwrap(
                storyboard.instantiateController(withIdentifier: identifier) as? NSWindowController,
                identifier
            )
            XCTAssertNotNil(controller.window, identifier)
            let content = try XCTUnwrap(controller.contentViewController, identifier)
            _ = content.view
            if let intro = content as? IntroductionViewController {
                // viewDidLoad starts a permission poll and an activation observer; stop both
                // before anything can fire.
                intro.accessibilityPermissionsCheckerTimer?.invalidate()
                NotificationCenter.default.removeObserver(intro)
            }
            if let tabs = content as? PreferencesTabViewController {
                for item in tabs.tabViewItems {
                    let pane = try XCTUnwrap(item.viewController, "\(identifier): tab \(item.label)")
                    _ = pane.view
                }
            }
            XCTAssertFalse(controller.window?.isVisible ?? true, identifier)
        }
    }

    func testEveryViewSceneLoadsItsView() throws {
        let compiled = try compiledIdentifiers()
        for identifier in viewIdentifiers where compiled.contains(identifier) {
            let controller = try XCTUnwrap(
                storyboard.instantiateController(withIdentifier: identifier) as? NSViewController,
                identifier
            )
            XCTAssertNotNil(controller.view, identifier)
        }
    }

    func testTheOutletsOfTheLoadedScenesAreConnected() throws {
        let general = try XCTUnwrap(
            storyboard.instantiateController(withIdentifier: PANEL_IDENTIFIER.general) as? PreferencesGeneralViewController
        )
        _ = general.view
        XCTAssertNotNil(general.launchOnLoginCheckBox)
        XCTAssertNotNil(general.hideStatusBarIconCheckBox)

        let monitor = try XCTUnwrap(
            storyboard.instantiateController(withIdentifier: WINDOW_IDENTIFIER.monitorWindowController) as? MonitorWindowController
        )
        let monitorContent = try XCTUnwrap(monitor.contentViewController as? MonitorViewController)
        _ = monitorContent.view
        XCTAssertNotNil(monitorContent.lineChart)
        XCTAssertNotNil(monitorContent.shortcutMenu)
        XCTAssertNotNil(monitorContent.scrollLogTextField)

        let introduction = try XCTUnwrap(
            storyboard.instantiateController(withIdentifier: WINDOW_IDENTIFIER.introductionWindowController) as? IntroductionWindowController
        )
        let introContent = try XCTUnwrap(introduction.contentViewController as? IntroductionViewController)
        _ = introContent.view
        introContent.accessibilityPermissionsCheckerTimer?.invalidate()
        NotificationCenter.default.removeObserver(introContent)
        XCTAssertNotNil(introContent.authButton)
        XCTAssertNotNil(introContent.helpButton)
    }
}
