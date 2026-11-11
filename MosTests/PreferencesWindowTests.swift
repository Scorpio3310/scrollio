//
//  PreferencesWindowTests.swift
//  MosTests
//
//  The Preferences window as a whole: the sidebar and its panes, how a pane is selected
//  and hosted, and the window's size. (What the About pane showed is on top of General:
//  PreferencesGeneralTests.) Nothing is shown on screen.
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
            ["scrolling", "buttons", "gestures", "mouse", nil, "application", nil, "general"]
        )
        XCTAssertEqual(
            titles(in: sidebar),
            ["Scrolling", "Buttons", "Gestures", "Mouse", nil, "Apps", nil, "General"]
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
        XCTAssertNil(preferences.controller(for: "about"), "About is part of General")
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
        XCTAssertEqual(preferences.selectedPaneIdentifier, "general", "the last row stays selected")
        sidebar.tableView.keyDown(with: up)
        XCTAssertEqual(preferences.selectedPaneIdentifier, "application")
        sidebar.tableView.keyDown(with: up)
        XCTAssertEqual(preferences.selectedPaneIdentifier, "mouse")
        XCTAssertNotNil(sidebar.selectedIdentifier, "a gap is never selected")
    }

    // MARK: - Selecting and remembering

    func testSelectsAPaneByIdentifier() throws {
        let (window, preferences) = try makeWindow()
        XCTAssertTrue(preferences.selectPane(withIdentifier: "general"))
        XCTAssertEqual(preferences.sidebar.selectedIdentifier, "general")
        XCTAssertTrue(preferences.host.currentController is PreferencesGeneralViewController)
        XCTAssertEqual(window.title, "General")
        XCTAssertFalse(preferences.selectPane(withIdentifier: "toolbar"))
        XCTAssertFalse(preferences.selectPane(withIdentifier: "about"), "no pane of its own any more")
        XCTAssertEqual(preferences.selectedPaneIdentifier, "general")
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

        // About, left open before it became the top of General: General. What is
        // remembered stays as it was until another pane is chosen.
        defaults.set("about", forKey: PreferencesSplitViewController.selectedPaneDefaultsKey)
        let (aboutWindow, fourth) = try makeWindow(defaults: defaults)
        XCTAssertEqual(fourth.selectedPaneIdentifier, "general")
        XCTAssertEqual(fourth.sidebar.selectedIdentifier, "general")
        XCTAssertEqual(aboutWindow.title, "General")
        XCTAssertEqual(defaults.string(forKey: PreferencesSplitViewController.selectedPaneDefaultsKey), "about")
    }

    func testTheInitialPaneFollowsWhatIsRemembered() {
        let panes = PreferencesPane.all
        XCTAssertEqual(PreferencesSplitViewController.initialPaneIdentifier(remembered: nil, panes: panes), "scrolling")
        XCTAssertEqual(PreferencesSplitViewController.initialPaneIdentifier(remembered: "mouse", panes: panes), "mouse")
        XCTAssertEqual(PreferencesSplitViewController.initialPaneIdentifier(remembered: "about", panes: panes), "general")
        XCTAssertEqual(PreferencesSplitViewController.initialPaneIdentifier(remembered: "toolbar", panes: panes), "scrolling")
        XCTAssertEqual(PreferencesSplitViewController.initialPaneIdentifier(remembered: "", panes: panes), "scrolling")
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

        // Button actions (code): the same three names as the Scrolling tab, in the Title
        // Case of menu items.
        XCTAssertEqual(SystemShortcut.mosScrollDash.localizedName, "Scroll Faster")
        XCTAssertEqual(SystemShortcut.mosScrollToggle.localizedName, "Scroll Sideways")
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
        general.isAccessGranted = { true }
        _ = general.view
        // Said the positive way; the stored "hide" is shown the other way round.
        XCTAssertEqual(general.showInMenuBarRow.title, "Show in menu bar")
        XCTAssertEqual(general.showInMenuBarSwitch.accessibilityLabel(), "Show in menu bar")
        XCTAssertEqual(general.launchOnLoginRow.title, "Open at login")
        let shown = texts(in: general.view)
        XCTAssertTrue(shown.contains("When it's off, open Scrollio again to reach its settings."))
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

        for controller in [mouse, gestures, scrolling] as [NSViewController] {
            XCTAssertEqual(smallTexts(in: controller.view), [], controller.title ?? "")
        }
    }

    func testHintsOfTheStoryboardPanesMatchTheFormKit() throws {
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesSplitViewController.self))
        let general = try XCTUnwrap(storyboard.instantiateController(withIdentifier: PANEL_IDENTIFIER.general) as? PreferencesGeneralViewController)
        general.isAccessGranted = { true }
        _ = general.view
        XCTAssertEqual(general.showInMenuBarRow.explanationLabel.font?.pointSize, PreferencesForm.hintFontSize)

        let scrolling = try XCTUnwrap(storyboard.instantiateController(withIdentifier: PANEL_IDENTIFIER.scrolling) as? PreferencesScrollingViewController)
        _ = scrolling.view
        XCTAssertEqual(scrolling.feelHintLabel.font?.pointSize, PreferencesForm.hintFontSize)
    }
}

// MARK: - Keyboard and accessibility

/// Every pane in its fullest state (bindings with a problem, apps and an app's page,
/// "Advanced" open, a connected mouse): Tab runs through it top to bottom, and every control
/// VoiceOver lands on has a name.
final class PreferencesKeyboardAccessibilityTests: XCTestCase {

    private let app = Bundle(for: PreferencesSplitViewController.self)
    private var savedBindings: [ButtonBinding] = []
    private var savedApplications: EnhanceArray<Application>!
    private var savedScroll: OPTIONS_SCROLL_DEFAULT!

    override func setUp() {
        super.setUp()
        savedBindings = Options.shared.buttons.binding
        savedApplications = Options.shared.application.applications
        savedScroll = Options.shared.scroll
        let trigger = { (code: UInt16) in RecordedEvent(type: .mouse, code: code, modifiers: 0, deviceFilter: nil) }
        Options.shared.buttons.binding = [
            ButtonBinding(triggerEvent: trigger(3), systemShortcutName: SystemShortcut.mouseGestureNavigation.identifier),
            ButtonBinding(triggerEvent: trigger(1000), systemShortcutName: SystemShortcut.copy.identifier),
            ButtonBinding(triggerEvent: trigger(6), systemShortcutName: "", isEnabled: false),
        ]
        let calculator = Application(path: "/System/Applications/Calculator.app")
        calculator.inherit = false
        Options.shared.application.applications = EnhanceArray<Application>(
            withArray: [calculator, Application(path: "/Applications/Safari.app")], matchKey: "path"
        )
    }

    override func tearDown() {
        Options.shared.buttons.binding = savedBindings
        Options.shared.application.applications = savedApplications
        Options.shared.scroll = savedScroll
        super.tearDown()
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "ScrollioTests.preferences-keyboard.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: PreferencesScrollingViewController.advancedExpandedDefaultsKey)
        defaults.set(true, forKey: PreferencesGeneralViewController.advancedExpandedDefaultsKey)
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    /// The window as the app makes it, every pane in its fullest state. Never shown.
    private func makeWindow() throws -> (NSWindow, PreferencesSplitViewController) {
        let storyboard = NSStoryboard(name: "Main", bundle: app)
        let controller = try XCTUnwrap(
            storyboard.instantiateController(withIdentifier: WINDOW_IDENTIFIER.preferencesWindowController) as? PreferencesWindowController
        )
        let window = try XCTUnwrap(controller.window)
        let preferences = PreferencesSplitViewController(storyboard: storyboard, uiStateDefaults: nil)
        let defaults = makeDefaults()
        (preferences.controller(for: PANEL_IDENTIFIER.scrolling) as? PreferencesScrollingViewController)?.uiStateDefaults = defaults
        if let general = preferences.controller(for: PANEL_IDENTIFIER.general) as? PreferencesGeneralViewController {
            general.uiStateDefaults = defaults
            general.isAccessGranted = { false }
            general.isMenuBarIconHidden = { false }
        }
        if let buttons = preferences.controller(for: PANEL_IDENTIFIER.buttons) as? PreferencesButtonsViewController {
            buttons.deviceSource = ButtonsDeviceSource(
                captureStatus: { $0 == 1000 ? .contended : .normal }, deviceName: { "MX Master 4" },
                isBusy: { false }, refresh: {}, warnBluetoothButton: { _ in }
            )
            buttons.startRecording = { _ in }
        }
        (preferences.controller(for: PANEL_IDENTIFIER.application) as? PreferencesApplicationViewController)?.uiStateDefaults = defaults
        if let mouse = preferences.controller(for: MousePreferencesViewController.tabIdentifier) as? MousePreferencesViewController {
            mouse.deviceSource = MouseDeviceSource(deviceStates: { [MouseDeviceFixtures.mxMaster4()] }, refresh: {}, showDiagnostics: {})
            mouse.readbackSettleTime = 0
        }
        controller.contentViewController = preferences
        controller.configure(window, remembersFrame: false)
        window.contentView?.layoutSubtreeIfNeeded()
        addTeardownBlock { controller.close() }
        return (window, preferences)
    }

    /// The pages to look at: every pane, and an app's page under Apps.
    private func eachPage(in preferences: PreferencesSplitViewController, window: NSWindow, _ body: (String, NSView) throws -> Void) throws {
        for pane in preferences.panes {
            XCTAssertTrue(preferences.selectPane(withIdentifier: pane.identifier))
            (preferences.selectedController as? MousePreferencesViewController)?.reloadDevices()
            window.contentView?.layoutSubtreeIfNeeded()
            try body(pane.identifier, try XCTUnwrap(preferences.selectedController?.view))
        }
        XCTAssertTrue(preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.application))
        let apps = try XCTUnwrap(preferences.selectedController as? PreferencesApplicationViewController)
        apps.openApplication(withID: "/System/Applications/Calculator.app")
        window.contentView?.layoutSubtreeIfNeeded()
        try body("app page", apps.view)
    }

    private func descendants(of view: NSView) -> [NSView] {
        return view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    private func isShown(_ view: NSView, in root: NSView) -> Bool {
        var current: NSView? = view
        while let candidate = current, candidate !== root {
            if candidate.isHidden || candidate.alphaValue == 0 { return false }
            current = candidate.superview
        }
        return true
    }

    /// What VoiceOver says a control is called.
    private func name(of control: NSControl) -> String? {
        if let label = control.accessibilityLabel(), !label.isEmpty { return label }
        if let field = control.accessibilityTitleUIElement() as? NSTextField, field.isAccessibilityElement(), !field.stringValue.isEmpty {
            return field.stringValue
        }
        if !(control is NSPopUpButton), let button = control as? NSButton, !button.title.isEmpty {
            return button.title
        }
        return nil
    }

    func testTheWindowKeepsItsKeyViewLoopUpToDate() throws {
        let (window, _) = try makeWindow()
        XCTAssertTrue(window.autorecalculatesKeyViewLoop, "panes come and go: Tab has to reach the controls of the one shown")
    }

    /// Tab goes through the controls of a pane from top to bottom (left to right on one line).
    func testTabRunsThroughEachPaneFromTopToBottom() throws {
        let (window, preferences) = try makeWindow()
        try eachPage(in: preferences, window: window) { identifier, page in
            window.recalculateKeyViewLoop()
            let wanted = descendants(of: page).filter { view in
                guard isShown(view, in: page) else { return false }
                if view is PreferencesListBox { return true }
                // A picture (a row's icon) takes no keyboard focus.
                if let image = view as? NSImageView, !image.isEditable { return false }
                guard let control = view as? NSControl, !(control is NSTextField) else { return false }
                return control.isEnabled && !(view.superview is NSControl)
            }
            var chain: [NSView] = []
            var current: NSView? = preferences.sidebar.tableView
            var steps = 0
            while let view = current?.nextKeyView, steps < 500 {
                if view === preferences.sidebar.tableView { break }
                if wanted.contains(where: { $0 === view }) { chain.append(view) }
                current = view
                steps += 1
            }
            XCTAssertEqual(chain.count, wanted.count, "\(identifier): Tab reaches every control")
            // By their top edges: a list comes before the controls in its rows.
            let frames = chain.map { $0.convert($0.bounds, to: nil) }
            for (above, below) in zip(frames, frames.dropFirst()) {
                let sameLine = abs(above.maxY - below.maxY) < 8
                XCTAssertTrue(sameLine ? above.minX < below.minX : above.maxY > below.maxY,
                              "\(identifier): \(above) before \(below)")
            }
        }
    }

    func testEveryControlHasANameAndEveryPictureIsNamedOrHidden() throws {
        let (window, preferences) = try makeWindow()
        try eachPage(in: preferences, window: window) { identifier, page in
            for view in descendants(of: page) where isShown(view, in: page) {
                if let control = view as? NSControl, !(control is NSTextField), control.isAccessibilityElement() {
                    XCTAssertNotNil(name(of: control), "\(identifier): \(type(of: control)) \(control.identifier?.rawValue ?? "")")
                }
                if let image = view as? NSImageView, image.isAccessibilityElement() {
                    let label = image.accessibilityLabel() ?? image.image?.accessibilityDescription
                    XCTAssertFalse(label?.isEmpty ?? true, "\(identifier): a picture without a name")
                }
                if let list = view as? PreferencesListBox {
                    XCTAssertFalse(list.rowsView.accessibilityLabel()?.isEmpty ?? true, "\(identifier): the list has a name")
                }
            }
        }
    }
}
