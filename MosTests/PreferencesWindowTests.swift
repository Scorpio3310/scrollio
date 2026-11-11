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
            ["general", "scrolling", "buttons", "gestures", "mouse", "application", "about"]
        )
    }

    func testTabLabels() throws {
        let tabs = try makeTabs()
        XCTAssertEqual(
            tabs.tabViewItems.map(\.label),
            ["General", "Scrolling", "Buttons", "Gestures", "Mouse", "Apps", "About"]
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
        XCTAssertTrue(controllers["gestures"] is GesturesPreferencesViewController)
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

/// No text of the Preferences window is smaller than 10 pt (hints were 9 pt).
final class PreferencesTextSizeTests: XCTestCase {

    private func smallTexts(in view: NSView) -> [String] {
        var found: [String] = []
        for subview in allSubviews(of: view) {
            if let field = subview as? NSTextField, !field.stringValue.isEmpty,
               let size = field.font?.pointSize, size < 10 {
                found.append("\(size) pt: \(field.stringValue)")
            } else if let button = subview as? NSButton, !button.title.isEmpty,
                      let size = button.font?.pointSize, size < 10 {
                found.append("\(size) pt: \(button.title)")
            }
        }
        return found
    }

    func testStoryboardPanesAndPopovers() throws {
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesTabViewController.self))
        let identifiers = [
            PANEL_IDENTIFIER.general, PANEL_IDENTIFIER.scrolling, PANEL_IDENTIFIER.buttons,
            PANEL_IDENTIFIER.application, PANEL_IDENTIFIER.scrollingWithApplication,
            "menuBarIconHint", "allowlistHint", "scrollSmoothDetail", "scrollReverseDetail",
        ]
        for identifier in identifiers {
            let controller = try XCTUnwrap(storyboard.instantiateController(withIdentifier: identifier) as? NSViewController)
            XCTAssertEqual(smallTexts(in: controller.view), [], identifier)
        }
    }

    func testPanesBuiltInCode() {
        let mouse = MousePreferencesViewController()
        mouse.deviceSource = MouseWheelDeviceSource(
            deviceStates: {
                [LogiWheelDeviceState(
                    id: "a", deviceName: "MX Master 4", supportsSmartShift: true, supportsScrollForce: true,
                    mode: .smartShift, smartShiftSensitivity: 40, scrollForce: 65
                )]
            },
            refresh: {},
            showDiagnostics: {}
        )
        _ = mouse.view
        mouse.reloadDevices()

        let gestures = GesturesPreferencesViewController(isInteractiveAvailable: { true })
        gestures.deviceSource = MouseGestureDeviceSource(support: { .none }, refresh: {})
        gestures.bindingSummary = { MouseGestureBindingSummary(hasGestureButton: false, hasLogitechGestureButton: false) }

        let about = AboutPreferencesViewController()

        for controller in [mouse, gestures, about] as [NSViewController] {
            XCTAssertEqual(smallTexts(in: controller.view), [], controller.title ?? "")
        }
    }

    func testHintsOfTheStoryboardPanesMatchTheFormKit() throws {
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesTabViewController.self))
        let general = try XCTUnwrap(storyboard.instantiateController(withIdentifier: PANEL_IDENTIFIER.general) as? NSViewController)
        let hint = try XCTUnwrap(allSubviews(of: general.view)
            .compactMap { $0 as? NSTextField }
            .first { $0.stringValue == "Open Scrollio again to show the icon" })
        XCTAssertEqual(hint.font?.pointSize, PreferencesForm.hintFontSize)

        let scrolling = try XCTUnwrap(storyboard.instantiateController(withIdentifier: PANEL_IDENTIFIER.scrolling) as? PreferencesScrollingViewController)
        _ = scrolling.view
        XCTAssertEqual(scrolling.scrollDurationDescriptionLabel?.font?.pointSize, PreferencesForm.hintFontSize)
    }
}

/// The preset row at the top of the global Scrolling tab. It shares its popup with the
/// Presets & Fast Scrolling popover and is hidden in per-app scroll settings.
final class PreferencesScrollingPresetRowTests: XCTestCase {

    private var originalScroll: OPTIONS_SCROLL_DEFAULT!
    private var originalTuning: ScrollTuningSettings!

    override func setUp() {
        super.setUp()
        originalScroll = Options.shared.scroll
        originalTuning = Options.shared.scrollTuning
        // A fresh container, so the tests never edit the one they restore.
        Options.shared.scroll = OPTIONS_SCROLL_DEFAULT()
        Options.shared.scrollTuning = .default
    }

    override func tearDown() {
        Options.shared.scroll = originalScroll
        Options.shared.scrollTuning = originalTuning
        originalScroll = nil
        originalTuning = nil
        super.tearDown()
    }

    private func makeController(target: Application? = nil) -> PreferencesScrollingViewController {
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesScrollingViewController.self))
        let controller = storyboard.instantiateController(withIdentifier: PANEL_IDENTIFIER.scrolling) as! PreferencesScrollingViewController
        controller.currentTargetApplication = target
        _ = controller.view
        // As in the window: the pane is as tall as its content.
        controller.view.setFrameSize(controller.view.fittingSize)
        controller.view.layoutSubtreeIfNeeded()
        return controller
    }

    private func choose(_ preset: ScrollPreset, in popUp: NSPopUpButton) {
        popUp.selectItem(withTag: ScrollPreset.allCases.firstIndex(of: preset)!)
        XCTAssertTrue(popUp.sendAction(popUp.action, to: popUp.target))
    }

    func testRowIsTheFirstRowOfTheGlobalTab() throws {
        ScrollPreset.smooth.apply()
        let controller = makeController()
        let popUp = try XCTUnwrap(controller.presetPicker?.popUp)
        let description = try XCTUnwrap(controller.presetDescriptionLabel)

        XCTAssertFalse(popUp.isHidden)
        XCTAssertEqual(
            popUp.itemTitles.filter { !$0.isEmpty },
            ScrollPreset.allCases.map(\.localizedName) + [ScrollPreset.customLocalizedName]
        )
        XCTAssertEqual(popUp.titleOfSelectedItem, "Smooth")
        XCTAssertEqual(description.stringValue, ScrollPreset.smooth.localizedDescription)
        XCTAssertEqual(description.font?.pointSize, PreferencesForm.hintFontSize)
        XCTAssertEqual(popUp.accessibilityLabel(), "Preset")

        // Above "Smooth Scrolling" and on the same grid (the root view is not flipped).
        let root = controller.view
        let popUpFrame = root.convert(popUp.alignmentRect(forFrame: popUp.frame), from: popUp.superview)
        let first = controller.scrollSmoothCheckBox!
        let firstFrame = root.convert(first.alignmentRect(forFrame: first.frame), from: first.superview)
        XCTAssertGreaterThan(popUpFrame.minY, firstFrame.maxY)
        XCTAssertEqual(popUpFrame.minX, firstFrame.minX, accuracy: 0.5)
        XCTAssertEqual(root.bounds.maxY - popUpFrame.maxY, 20, accuracy: 0.5)
    }

    func testChoosingAPresetWritesTheGlobalSettingsAndUpdatesTheTab() throws {
        let controller = makeController()
        let popUp = try XCTUnwrap(controller.presetPicker?.popUp)

        choose(.direct, in: popUp)

        let direct = ScrollPreset.direct.values
        XCTAssertEqual(Options.shared.scroll.step, direct.step)
        XCTAssertEqual(Options.shared.scroll.speed, direct.speed)
        XCTAssertEqual(Options.shared.scroll.duration, direct.duration)
        XCTAssertEqual(Options.shared.scrollTuning, direct.tuning)
        XCTAssertEqual(controller.scrollSpeedSlider.doubleValue, direct.speed, accuracy: 1e-9)
        XCTAssertEqual(controller.scrollDurationSlider.doubleValue, direct.duration, accuracy: 1e-9)
        XCTAssertEqual(popUp.titleOfSelectedItem, "Direct")
        XCTAssertEqual(controller.presetDescriptionLabel?.stringValue, ScrollPreset.direct.localizedDescription)
        XCTAssertEqual(ScrollPreset.current, .direct)
    }

    func testRowFollowsTheValuesOfTheTab() throws {
        ScrollPreset.balanced.apply()
        let controller = makeController()
        let popUp = try XCTUnwrap(controller.presetPicker?.popUp)
        XCTAssertEqual(popUp.titleOfSelectedItem, "Balanced")

        // A value changed by hand: no preset matches any more.
        Options.shared.scroll.speed = 4.4
        controller.syncViewWithOptions()
        XCTAssertEqual(popUp.titleOfSelectedItem, ScrollPreset.customLocalizedName)
        XCTAssertEqual(controller.presetDescriptionLabel?.stringValue, ScrollPresetPicker.customDescription)

        // "Custom" changes nothing.
        let before = Options.shared.scroll.speed
        popUp.selectItem(withTag: ScrollPresetPicker.customTag)
        XCTAssertTrue(popUp.sendAction(popUp.action, to: popUp.target))
        XCTAssertEqual(Options.shared.scroll.speed, before)

        Options.shared.scroll.smooth = false
        controller.syncViewWithOptions()
        XCTAssertEqual(controller.presetDescriptionLabel?.stringValue, ScrollPresetPicker.smoothOffDescription)
    }

    func testResetToDefaultsUpdatesTheRow() throws {
        let controller = makeController()
        let popUp = try XCTUnwrap(controller.presetPicker?.popUp)
        choose(.direct, in: popUp)
        XCTAssertTrue(controller.hasSettingsToReset)

        controller.resetToDefaultClick(controller.resetToDefaultsButton)

        XCTAssertEqual(Options.shared.scroll, OPTIONS_SCROLL_DEFAULT())
        XCTAssertEqual(Options.shared.scrollTuning, .default)
        let expected = ScrollPreset.current?.localizedName ?? ScrollPreset.customLocalizedName
        XCTAssertEqual(popUp.titleOfSelectedItem, expected)
    }

    func testRowIsHiddenInPerAppSettings() throws {
        let application = Application(path: "/Applications/PresetRowTest.app")
        application.inherit = false
        let perApp = makeController(target: application)
        let popUp = try XCTUnwrap(perApp.presetPicker?.popUp)
        XCTAssertTrue(popUp.isHidden)
        XCTAssertEqual(perApp.presetDescriptionLabel?.isHidden, true)

        // The first row keeps its place at the top, 20 pt under the edge.
        let root = perApp.view
        let first = perApp.scrollSmoothCheckBox!
        let firstFrame = root.convert(first.alignmentRect(forFrame: first.frame), from: first.superview)
        XCTAssertEqual(root.bounds.maxY - firstFrame.maxY, 20, accuracy: 0.5)

        // And the global tab is taller by exactly the row.
        let global = makeController()
        XCTAssertGreaterThan(global.view.fittingSize.height, perApp.view.fittingSize.height)
    }

    func testThePopoverUsesTheSamePicker() throws {
        ScrollPreset.smooth.apply()
        let popover = ScrollTuningSettingsPopover()
        let view = popover.makeContentViewController().view
        let popUp = try XCTUnwrap(allSubviews(of: view).compactMap { $0 as? NSPopUpButton }
            .first { $0.identifier == ScrollTuningSettingsPopover.Identifier.preset })
        XCTAssertTrue(popUp.target is ScrollPresetPicker)
        XCTAssertEqual(popUp.titleOfSelectedItem, "Smooth")
    }
}
