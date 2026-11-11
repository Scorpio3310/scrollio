//
//  PreferencesWindowTests.swift
//  MosTests
//
//  The Preferences window as a whole: the sidebar and its panes, how a pane is selected
//  and hosted, the window's size, and the About pane that is built in code. Nothing is
//  shown on screen.
//

import XCTest
@testable import Mos_Debug

private func allSubviews(of view: NSView) -> [NSView] {
    return view.subviews.flatMap { [$0] + allSubviews(of: $0) }
}

final class PreferencesSidebarTests: XCTestCase {

    private let app = Bundle(for: PreferencesSplitViewController.self)

    /// The Preferences window as the app makes it, with its content rebuilt around `defaults`
    /// (nil remembers nothing); `prepare` runs before any pane's view loads. Never shown.
    private func makeWindow(
        defaults: UserDefaults? = nil,
        prepare: (PreferencesSplitViewController) -> Void = { _ in }
    ) throws -> (NSWindow, PreferencesSplitViewController) {
        let storyboard = NSStoryboard(name: "Main", bundle: app)
        let controller = try XCTUnwrap(
            storyboard.instantiateController(withIdentifier: WINDOW_IDENTIFIER.preferencesWindowController) as? PreferencesWindowController
        )
        let window = try XCTUnwrap(controller.window)
        let preferences = PreferencesSplitViewController(storyboard: storyboard, uiStateDefaults: defaults)
        prepare(preferences)
        controller.contentViewController = preferences
        controller.configure(window, remembersFrame: false)
        preferences.updateWindowTitle()
        window.contentView?.layoutSubtreeIfNeeded()
        addTeardownBlock { controller.close() }
        return (window, preferences)
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "ScrollioTests.preferences-window.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    private func titles(in sidebar: PreferencesSidebarViewController) -> [String?] {
        return sidebar.rowIdentifiers.indices.map { row in
            let cell = sidebar.tableView.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView
            return cell?.textField?.stringValue
        }
    }

    private func arrowKey(_ key: Int, in window: NSWindow) -> NSEvent {
        let characters = String(Character(UnicodeScalar(key)!))
        return NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.function, .numericPad], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false,
            keyCode: key == NSDownArrowFunctionKey ? 125 : 126
        )!
    }

    // MARK: - The sidebar

    func testTheSidebarListsThePanesInThreeGroups() throws {
        let (_, preferences) = try makeWindow()
        let sidebar = preferences.sidebar
        XCTAssertEqual(
            sidebar.rowIdentifiers,
            ["scrolling", "buttons", "gestures", "mouse", nil, "application", nil, "general", "about"]
        )
        XCTAssertEqual(
            titles(in: sidebar),
            ["Scrolling", "Buttons", "Gestures", "Mouse", nil, "Apps", nil, "General", "About"]
        )
        let table = sidebar.tableView!
        XCTAssertEqual(table.style, .sourceList)
        XCTAssertNil(table.headerView)
        for (row, identifier) in sidebar.rowIdentifiers.enumerated() {
            let height = table.rect(ofRow: row).height
            if identifier == nil {
                XCTAssertEqual(height, PreferencesSidebarViewController.gapHeight)
                XCTAssertNil(table.view(atColumn: 0, row: row, makeIfNecessary: true))
            } else {
                XCTAssertEqual(height, PreferencesSidebarViewController.rowHeight)
                let cell = try XCTUnwrap(table.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView)
                let tile = try XCTUnwrap(cell.imageView?.image, "\(identifier!) has no icon")
                XCTAssertEqual(tile.size, NSSize(width: 20, height: 20))
                XCTAssertFalse(tile.isTemplate, "the tile keeps its colour")
            }
        }
    }

    func testEveryPaneHasItsOwnController() throws {
        let (_, preferences) = try makeWindow()
        XCTAssertTrue(preferences.controller(for: "scrolling") is PreferencesScrollingViewController)
        XCTAssertTrue(preferences.controller(for: "buttons") is PreferencesButtonsViewController)
        XCTAssertTrue(preferences.controller(for: "gestures") is GesturesPreferencesViewController)
        XCTAssertTrue(preferences.controller(for: "mouse") is MousePreferencesViewController)
        XCTAssertTrue(preferences.controller(for: "application") is PreferencesApplicationViewController)
        XCTAssertTrue(preferences.controller(for: "general") is PreferencesGeneralViewController)
        XCTAssertTrue(preferences.controller(for: "about") is AboutPreferencesViewController)
        XCTAssertNil(preferences.controller(for: "no-such-pane"))
    }

    func testSelectingARowShowsItsPaneAndNamesTheWindow() throws {
        let (window, preferences) = try makeWindow()
        let sidebar = preferences.sidebar
        let host = preferences.host
        XCTAssertEqual(preferences.selectedPaneIdentifier, "scrolling")
        let scrolling = try XCTUnwrap(preferences.controller(for: "scrolling"))
        XCTAssertTrue(scrolling.view.superview === host.documentView)
        XCTAssertEqual(window.title, "Scrolling")

        for (row, identifier) in sidebar.rowIdentifiers.enumerated() {
            guard let identifier else { continue }
            // What a click does: the table changes its selection and tells its delegate.
            sidebar.tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            let controller = try XCTUnwrap(preferences.controller(for: identifier))
            XCTAssertEqual(preferences.selectedPaneIdentifier, identifier)
            XCTAssertTrue(host.currentController === controller)
            XCTAssertTrue(controller.parent === host)
            XCTAssertTrue(controller.view.superview === host.documentView, identifier)
            XCTAssertEqual(host.documentView.subviews.count, 1, "only the selected pane is in the column")
            XCTAssertEqual(window.title, controller.title)
        }
        XCTAssertNil(scrolling.view.superview)
    }

    func testTheArrowKeysMoveThroughThePanesAndStepOverTheGaps() throws {
        let (window, preferences) = try makeWindow()
        let sidebar = preferences.sidebar
        XCTAssertTrue(preferences.selectPane(withIdentifier: "mouse"))

        let down = arrowKey(NSDownArrowFunctionKey, in: window)
        let up = arrowKey(NSUpArrowFunctionKey, in: window)
        sidebar.tableView.keyDown(with: down)
        XCTAssertEqual(sidebar.selectedIdentifier, "application")
        XCTAssertEqual(preferences.selectedPaneIdentifier, "application")
        sidebar.tableView.keyDown(with: down)
        XCTAssertEqual(preferences.selectedPaneIdentifier, "general")
        sidebar.tableView.keyDown(with: down)
        sidebar.tableView.keyDown(with: down)
        XCTAssertEqual(preferences.selectedPaneIdentifier, "about", "the last row stays selected")
        sidebar.tableView.keyDown(with: up)
        sidebar.tableView.keyDown(with: up)
        XCTAssertEqual(preferences.selectedPaneIdentifier, "application")
        sidebar.tableView.keyDown(with: up)
        XCTAssertEqual(preferences.selectedPaneIdentifier, "mouse")
        XCTAssertNotNil(sidebar.selectedIdentifier, "a gap is never selected")
    }

    // MARK: - Selecting and remembering

    func testSelectsAPaneByIdentifier() throws {
        let (window, preferences) = try makeWindow()
        XCTAssertTrue(preferences.selectPane(withIdentifier: "about"))
        XCTAssertEqual(preferences.sidebar.selectedIdentifier, "about")
        XCTAssertTrue(preferences.host.currentController is AboutPreferencesViewController)
        XCTAssertEqual(window.title, "About")
        XCTAssertFalse(preferences.selectPane(withIdentifier: "toolbar"))
        XCTAssertEqual(preferences.selectedPaneIdentifier, "about")
    }

    func testRemembersTheLastOpenPane() throws {
        // Persisted names: they never change.
        XCTAssertEqual(PreferencesSplitViewController.selectedPaneDefaultsKey, "preferencesSelectedPane")
        XCTAssertEqual(PreferencesWindowLayout.frameAutosaveName, "PreferencesWindow")
        let defaults = makeDefaults()
        let (_, first) = try makeWindow(defaults: defaults)
        XCTAssertEqual(first.selectedPaneIdentifier, PreferencesSplitViewController.defaultPaneIdentifier)
        XCTAssertNil(defaults.string(forKey: PreferencesSplitViewController.selectedPaneDefaultsKey), "opening writes nothing")

        first.sidebar.tableView.selectRowIndexes(
            IndexSet(integer: try XCTUnwrap(first.sidebar.row(for: "mouse"))),
            byExtendingSelection: false
        )
        XCTAssertEqual(defaults.string(forKey: PreferencesSplitViewController.selectedPaneDefaultsKey), "mouse")
        XCTAssertTrue(first.selectPane(withIdentifier: "general"))
        XCTAssertEqual(defaults.string(forKey: PreferencesSplitViewController.selectedPaneDefaultsKey), "general")

        // The next window opens where the last one was left.
        let (window, second) = try makeWindow(defaults: defaults)
        XCTAssertEqual(second.selectedPaneIdentifier, "general")
        XCTAssertEqual(second.sidebar.selectedIdentifier, "general")
        XCTAssertEqual(window.title, "General")

        // A pane that no longer exists: the default.
        defaults.set("toolbar", forKey: PreferencesSplitViewController.selectedPaneDefaultsKey)
        let (_, third) = try makeWindow(defaults: defaults)
        XCTAssertEqual(third.selectedPaneIdentifier, "scrolling")
    }

    func testTheAppsWindowOpensOnScrollingWhenNothingIsRemembered() throws {
        // Under XCTest the window the storyboard makes remembers nothing.
        let storyboard = NSStoryboard(name: "Main", bundle: app)
        let controller = try XCTUnwrap(
            storyboard.instantiateController(withIdentifier: WINDOW_IDENTIFIER.preferencesWindowController) as? PreferencesWindowController
        )
        defer { controller.close() }
        let preferences = try XCTUnwrap(controller.splitViewController)
        XCTAssertNil(preferences.uiStateDefaults)
        XCTAssertEqual(preferences.selectedPaneIdentifier, "scrolling")
        XCTAssertEqual(controller.window?.title, "Scrolling")
    }

    // MARK: - The window

    func testTheWindowHasAFixedWidthAndAResizableHeight() throws {
        let (window, preferences) = try makeWindow()
        let width = PreferencesWindowLayout.contentWidth(of: preferences.splitView)
        XCTAssertEqual(width, PreferencesWindowLayout.sidebarWidth + PreferencesWindowLayout.contentWidth, accuracy: 1)
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView), "the sidebar runs under the traffic lights")
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.titleVisibility, .visible)
        XCTAssertEqual(window.contentMinSize.width, width)
        XCTAssertEqual(window.contentMaxSize.width, width)
        XCTAssertEqual(window.contentMinSize.height, PreferencesWindowLayout.minimumContentHeight)
        XCTAssertGreaterThan(window.contentMaxSize.height, 10_000)
        let content = window.contentRect(forFrameRect: window.frame).size
        XCTAssertEqual(content, NSSize(width: width, height: PreferencesWindowLayout.defaultContentHeight))

        // No tabs in the toolbar any more: only the separator that puts the title next to the sidebar.
        let toolbar = try XCTUnwrap(window.toolbar)
        XCTAssertEqual(toolbar.items.map(\.itemIdentifier), [.sidebarTrackingSeparator])
        XCTAssertTrue(toolbar.items.first is NSTrackingSeparatorToolbarItem)

        // Laid out as the window will be: the widths the window was given are the ones it keeps.
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).width, width)
        XCTAssertEqual(preferences.sidebar.view.frame.width, PreferencesWindowLayout.sidebarWidth)
        XCTAssertEqual(preferences.host.view.frame.width, PreferencesWindowLayout.contentWidth)
        XCTAssertTrue(preferences.splitViewItems.first?.behavior == .sidebar)
        XCTAssertFalse(preferences.splitViewItems.first?.canCollapse ?? true)
    }

    func testEveryPaneSitsAtTheTopOfTheColumnCentred() throws {
        let (window, preferences) = try makeWindow()
        XCTAssertEqual(PreferencesScrollingViewController.paneWidth, PreferencesWindowLayout.contentWidth)
        for pane in preferences.panes {
            XCTAssertTrue(preferences.selectPane(withIdentifier: pane.identifier))
            window.contentView?.layoutSubtreeIfNeeded()
            let view = try XCTUnwrap(preferences.selectedController?.view)
            let document = preferences.host.documentView!
            XCTAssertLessThanOrEqual(view.frame.width, PreferencesWindowLayout.contentWidth, pane.identifier)
            XCTAssertEqual(view.frame.midX, document.bounds.midX, accuracy: 0.5, pane.identifier)
            XCTAssertEqual(view.frame.minY, 0, pane.identifier)
            XCTAssertEqual(document.frame.width, preferences.host.scrollView.contentSize.width, pane.identifier)
            XCTAssertGreaterThan(view.frame.height, 50, pane.identifier)
        }
        // Every pane fills the 520 pt column, so their boxes and tables share its margins.
        for pane in preferences.panes {
            XCTAssertTrue(preferences.selectPane(withIdentifier: pane.identifier))
            window.contentView?.layoutSubtreeIfNeeded()
            XCTAssertEqual(preferences.selectedController?.view.frame.width, PreferencesWindowLayout.contentWidth, pane.identifier)
            XCTAssertEqual(preferences.selectedController?.view.frame.minX, 0, pane.identifier)
        }
    }

    /// Every text of every pane draws in the plain light or dark appearance, as in System
    /// Settings. In the vibrant appearance of the window's material the dimmed texts were
    /// opaque greys that nothing blended: almost invisible on the boxes.
    func testNoPaneDrawsItsTextsInAVibrantAppearance() throws {
        for (appearance, plain) in [(NSAppearance.Name.aqua, NSAppearance.Name.aqua), (.darkAqua, .darkAqua)] {
            let (window, preferences) = try makeWindow()
            window.appearance = NSAppearance(named: appearance)
            for pane in preferences.panes {
                XCTAssertTrue(preferences.selectPane(withIdentifier: pane.identifier))
                window.contentView?.layoutSubtreeIfNeeded()
                let view = try XCTUnwrap(preferences.selectedController?.view)
                let texts = allSubviews(of: view).compactMap { $0 as? NSTextField }.filter { !$0.stringValue.isEmpty }
                XCTAssertFalse(texts.isEmpty, pane.identifier)
                for text in texts {
                    XCTAssertEqual(text.effectiveAppearance.name, plain, "\(pane.identifier): \(text.stringValue)")
                }
            }
        }

        // An app's page under Apps too.
        let page = ApplicationDetailViewController(application: Application(path: "/System/Applications/Calculator.app"))
        let host = NSView()
        host.appearance = NSAppearance(named: .darkAqua)
        host.addSubview(page.view)
        for text in allSubviews(of: page.view).compactMap({ $0 as? NSTextField }) where !text.stringValue.isEmpty {
            XCTAssertEqual(text.effectiveAppearance.name, .darkAqua, text.stringValue)
        }
    }

    func testATallPaneScrollsInsteadOfResizingTheWindow() throws {
        let scrollingDefaults = makeDefaults()
        scrollingDefaults.set(false, forKey: PreferencesScrollingViewController.advancedExpandedDefaultsKey)
        let (window, preferences) = try makeWindow { preferences in
            (preferences.controller(for: "scrolling") as? PreferencesScrollingViewController)?.uiStateDefaults = scrollingDefaults
        }
        let scrolling = try XCTUnwrap(preferences.selectedController as? PreferencesScrollingViewController)
        let host = preferences.host
        let frame = window.frame
        let visible = host.scrollView.contentSize.height
        XCTAssertFalse(scrolling.isAdvancedExpanded)
        XCTAssertLessThanOrEqual(scrolling.view.frame.height, visible, "the basic pane fits")
        XCTAssertEqual(host.documentView.frame.height, visible)

        scrolling.setAdvancedExpanded(true)
        window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertEqual(window.frame, frame, "the window keeps its size")
        XCTAssertGreaterThan(scrolling.view.frame.height, 850)
        XCTAssertEqual(host.documentView.frame.height, scrolling.view.frame.height)
        XCTAssertGreaterThan(host.documentView.frame.height, visible, "the column scrolls")
        XCTAssertEqual(scrolling.view.frame.minY, 0)

        // Scrolled down: the line under the title bar shows, as in System Settings.
        XCTAssertTrue(host.titlebarSeparator.isHidden)
        host.documentView.scroll(NSPoint(x: 0, y: host.documentView.frame.height - visible))
        XCTAssertTrue(host.scrollView.contentView.bounds.minY > 0)
        XCTAssertFalse(host.titlebarSeparator.isHidden)

        scrolling.setAdvancedExpanded(false)
        window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertEqual(window.frame, frame)
        XCTAssertEqual(host.documentView.frame.height, visible, "and shrinks back")
        XCTAssertEqual(host.scrollView.contentView.bounds.minY, 0)
        XCTAssertTrue(host.titlebarSeparator.isHidden)

        // A taller window shows more of the pane; the pane does not stretch.
        let height = scrolling.view.frame.height
        window.setContentSize(NSSize(width: window.contentRect(forFrameRect: window.frame).width, height: 900))
        window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertEqual(scrolling.view.frame.height, height)
        XCTAssertEqual(host.documentView.frame.height, host.scrollView.contentSize.height)
        XCTAssertGreaterThan(host.scrollView.contentSize.height, visible)
    }

    func testASavedFrameKeepsTheWidthAndFitsTheScreen() {
        let screen = NSRect(x: 0, y: 80, width: 1512, height: 870)
        // Another width (an older version), too short: the width is fixed, the height grows down.
        let old = PreferencesWindowLayout.normalizedFrame(
            NSRect(x: 300, y: 600, width: 450, height: 200), width: 721, minimumHeight: 420, visibleFrame: screen
        )
        XCTAssertEqual(old, NSRect(x: 300, y: 380, width: 721, height: 420))
        // Taller than the screen: as tall as the screen, inside it.
        let tall = PreferencesWindowLayout.normalizedFrame(
            NSRect(x: 300, y: -200, width: 721, height: 1400), width: 721, minimumHeight: 420, visibleFrame: screen
        )
        XCTAssertEqual(tall, NSRect(x: 300, y: 80, width: 721, height: 870))
        // Off the right edge: moved back in.
        let right = PreferencesWindowLayout.normalizedFrame(
            NSRect(x: 1400, y: 200, width: 721, height: 640), width: 721, minimumHeight: 420, visibleFrame: screen
        )
        XCTAssertEqual(right, NSRect(x: 791, y: 200, width: 721, height: 640))
        // Without a screen only the size is fixed.
        let none = PreferencesWindowLayout.normalizedFrame(
            NSRect(x: 10, y: 20, width: 500, height: 300), width: 721, minimumHeight: 420, visibleFrame: nil
        )
        XCTAssertEqual(none, NSRect(x: 10, y: -100, width: 721, height: 420))
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

    func testTheOnlyButtonOpensTheWelcomeGuide() {
        var opened = 0
        let controller = makeController()
        controller.showWelcomeGuide = { opened += 1 }

        let buttons = allSubviews(of: controller.view).compactMap { $0 as? NSButton }
        XCTAssertEqual(buttons.count, 1)
        XCTAssertTrue(buttons.first === controller.welcomeGuideButton)
        // A push button in a row of the grouped kit, named by the row.
        XCTAssertEqual(controller.welcomeGuideRow.title, "Welcome Guide")
        XCTAssertEqual(controller.welcomeGuideButton.title, "Open")
        XCTAssertEqual(controller.welcomeGuideButton.bezelStyle, .push)
        XCTAssertTrue(controller.welcomeGuideRow.controls.contains { $0 === controller.welcomeGuideButton })

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
        // Instantiating a missing storyboard identifier raises, so the About pane is read
        // from the window instead: it is the controller built in code.
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesSplitViewController.self))
        let windowController = storyboard.instantiateController(withIdentifier: WINDOW_IDENTIFIER.preferencesWindowController) as? NSWindowController
        let preferences = windowController?.contentViewController as? PreferencesSplitViewController
        XCTAssertTrue(preferences?.controller(for: AboutPreferencesViewController.tabIdentifier) is AboutPreferencesViewController)
        windowController?.close()
        for name in ["AlipayQR", "WechatpayQR", "PaypalLogo", "BuyMeACoffee", "MEOW"] {
            XCTAssertNil(NSImage(named: name), "donation asset \(name) is still in the bundle")
        }
    }

    func testPaneHasThePreferencesWidthAndFitsItsContent() {
        let controller = makeController()
        XCTAssertEqual(controller.view.frame.width, PreferencesWindowLayout.contentWidth)
        XCTAssertEqual(controller.view.frame.size, controller.view.fittingSize)
        controller.view.layoutSubtreeIfNeeded()
        let root = controller.view
        func frame(_ view: NSView) -> NSRect { root.convert(view.frame, from: view.superview) }
        for label in [controller.nameLabel!, controller.versionLabel!, controller.creditLabel!] {
            XCTAssertEqual(frame(label).midX, root.bounds.midX, accuracy: 0.5)
            XCTAssertGreaterThanOrEqual(frame(label).minX, PreferencesGroupedForm.margin - 2)
        }
        XCTAssertEqual(controller.iconView.frame.size, NSSize(width: 64, height: 64))
        XCTAssertEqual(frame(controller.iconView).midX, root.bounds.midX, accuracy: 0.5)
        // The Welcome Guide sits in a box on the kit's margins.
        XCTAssertEqual(frame(controller.welcomeGuideRow).minX, PreferencesGroupedForm.margin, accuracy: 0.5)
        XCTAssertEqual(frame(controller.welcomeGuideRow).width, PreferencesGroupedForm.boxWidth(paneWidth: root.frame.width), accuracy: 0.5)
    }
}

/// Names the redesign changed. Only what the user reads changed: every identifier that is
/// stored in the settings or used as a key stays as it was.
final class PreferencesNamingTests: XCTestCase {

    private let app = Bundle(for: PreferencesSplitViewController.self)

    private func texts(in view: NSView) -> [String] {
        let views = allSubviews(of: view)
        return views.compactMap { ($0 as? NSTextField)?.stringValue } + views.compactMap { ($0 as? NSButton)?.title }
    }

    private func instantiate(_ identifier: String) -> NSViewController? {
        let storyboard = NSStoryboard(name: "Main", bundle: app)
        return storyboard.instantiateController(withIdentifier: identifier) as? NSViewController
    }

    func testScrollKeyNames() throws {
        // Scrolling tab (built in code): what holding the key does, in plain words.
        let scrolling = try XCTUnwrap(instantiate(PANEL_IDENTIFIER.scrolling))
        let shown = texts(in: scrolling.view)
        for name in ["Scroll faster", "Scroll sideways", "Pause smoothing"] {
            XCTAssertTrue(shown.contains(name), "\(name) is not in the Scrolling tab")
        }
        for old in ["Dash Key", "Toggle Key", "Block Key"] {
            XCTAssertFalse(shown.contains(old), "\(old) is still in the Scrolling tab")
        }

        // Button actions (code): the same three names as the Scrolling tab.
        XCTAssertEqual(SystemShortcut.mosScrollDash.localizedName, "Scroll faster")
        XCTAssertEqual(SystemShortcut.mosScrollToggle.localizedName, "Scroll sideways")
        XCTAssertEqual(SystemShortcut.mosScrollBlock.localizedName, "Pause smoothing")
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

    func testTrackpadStyleEventsWording() throws {
        let scrolling = try XCTUnwrap(instantiate(PANEL_IDENTIFIER.scrolling) as? PreferencesScrollingViewController)
        _ = scrolling.view
        XCTAssertEqual(scrolling.trackpadEventsRow.title, "Trackpad-style events")
        XCTAssertEqual(scrolling.trackpadEventsSwitch.accessibilityLabel(), "Trackpad-style events")
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
        XCTAssertEqual(general.hideStatusBarIconRow.title, "Hide menu bar icon")
        XCTAssertEqual(general.hideStatusBarIconSwitch.accessibilityLabel(), "Hide menu bar icon")
        XCTAssertEqual(general.launchOnLoginRow.title, "Open at login")
        let shown = texts(in: general.view)
        // What the "?" popover said is the row's explanation now.
        XCTAssertTrue(shown.contains("While the icon is hidden, open Scrollio again to reach its settings."))
        for text in shown {
            XCTAssertFalse(text.localizedCaseInsensitiveContains("status bar"), text)
            XCTAssertFalse(text.localizedCaseInsensitiveContains("re-run"), text)
        }
        XCTAssertFalse(allSubviews(of: general.view).contains { ($0 as? NSButton)?.bezelStyle == .helpButton })
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
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesSplitViewController.self))
        let identifiers = [
            PANEL_IDENTIFIER.general, PANEL_IDENTIFIER.scrolling, PANEL_IDENTIFIER.buttons,
            PANEL_IDENTIFIER.application,
        ]
        for identifier in identifiers {
            let controller = try XCTUnwrap(storyboard.instantiateController(withIdentifier: identifier) as? NSViewController)
            XCTAssertEqual(smallTexts(in: controller.view), [], identifier)
        }
        // An app's page, which replaced the per-app popover.
        let page = ApplicationDetailViewController(application: Application(path: "/System/Applications/Calculator.app"))
        XCTAssertEqual(smallTexts(in: page.view), [], "app page")
    }

    func testPanesBuiltInCode() {
        let mouse = MousePreferencesViewController()
        mouse.deviceSource = MouseDeviceSource(
            deviceStates: { [MouseDeviceFixtures.mxMaster4()] },
            refresh: {},
            showDiagnostics: {}
        )
        _ = mouse.view
        mouse.reloadDevices()

        let gestures = GesturesPreferencesViewController(isInteractiveAvailable: { true })
        gestures.deviceSource = MouseGestureDeviceSource(support: { .none }, refresh: {})
        gestures.bindingSummary = { MouseGestureBindingSummary(hasGestureButton: false, hasLogitechGestureButton: false) }

        let about = AboutPreferencesViewController()

        // The Scrolling tab with "Advanced" open, so every row is looked at.
        let scrolling = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesSplitViewController.self))
            .instantiateController(withIdentifier: PANEL_IDENTIFIER.scrolling) as! PreferencesScrollingViewController
        let suite = "ScrollioTests.text-size.\(UUID().uuidString)"
        let uiDefaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { uiDefaults.removePersistentDomain(forName: suite) }
        uiDefaults.set(true, forKey: PreferencesScrollingViewController.advancedExpandedDefaultsKey)
        scrolling.uiStateDefaults = uiDefaults
        _ = scrolling.view
        XCTAssertTrue(scrolling.isAdvancedExpanded)

        for controller in [mouse, gestures, about, scrolling] as [NSViewController] {
            XCTAssertEqual(smallTexts(in: controller.view), [], controller.title ?? "")
        }
    }

    func testHintsOfTheStoryboardPanesMatchTheFormKit() throws {
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesSplitViewController.self))
        let general = try XCTUnwrap(storyboard.instantiateController(withIdentifier: PANEL_IDENTIFIER.general) as? PreferencesGeneralViewController)
        _ = general.view
        XCTAssertEqual(general.hideStatusBarIconRow.explanationLabel.font?.pointSize, PreferencesForm.hintFontSize)

        let scrolling = try XCTUnwrap(storyboard.instantiateController(withIdentifier: PANEL_IDENTIFIER.scrolling) as? PreferencesScrollingViewController)
        _ = scrolling.view
        XCTAssertEqual(scrolling.feelHintLabel.font?.pointSize, PreferencesForm.hintFontSize)
    }
}
