//
//  PreferencesWindowTests.swift
//  MosTests
//
//  The Preferences window as a whole: the sidebar and its panes, how a pane is selected
//  and hosted, and the window's size. (What the About pane showed is on top of General:
//  PreferencesGeneralTests.) Nothing is shown on screen.
//

import XCTest
@testable import Scrollio_Debug

private func allSubviews(of view: NSView) -> [NSView] {
    return view.subviews.flatMap { [$0] + allSubviews(of: $0) }
}

/// A view that takes the keyboard focus, whatever the Mac's keyboard navigation setting says.
private final class FocusTakingView: NSView {
    override var acceptsFirstResponder: Bool { true }
}

final class PreferencesSidebarTests: XCTestCase {

    private let app = Bundle(for: PreferencesSplitViewController.self)

    /// The Preferences window as the app makes it, with its content rebuilt around `defaults`
    /// (nil remembers nothing); `prepare` runs before any pane's view loads. Never shown.
    private func makeWindow(
        defaults: UserDefaults? = nil,
        paneLiesUnderSidebar: Bool = PreferencesWindowLayout.paneLiesUnderSidebar,
        prepare: (PreferencesSplitViewController) -> Void = { _ in }
    ) throws -> (NSWindow, PreferencesSplitViewController) {
        let storyboard = NSStoryboard(name: "Main", bundle: app)
        let controller = try XCTUnwrap(
            storyboard.instantiateController(withIdentifier: WINDOW_IDENTIFIER.preferencesWindowController) as? PreferencesWindowController
        )
        let window = try XCTUnwrap(controller.window)
        let preferences = PreferencesSplitViewController(
            storyboard: storyboard, uiStateDefaults: defaults, paneLiesUnderSidebar: paneLiesUnderSidebar
        )
        prepare(preferences)
        controller.contentViewController = preferences
        controller.configure(window, remembersFrame: false)
        preferences.updateWindowTitle()
        window.contentView?.layoutSubtreeIfNeeded()
        addTeardownBlock { controller.close() }
        return (window, preferences)
    }

    private func makeDefaults() -> UserDefaults {
        return TestDefaults.make(for: self)
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

    /// The stretches of the window's width that lie on the panes' background material at
    /// the height `y` (window coordinates): every material view of that kind shown there,
    /// joined where they touch or overlap. One stretch from edge to edge is one
    /// continuous background; two stretches have a strip of the window's own background
    /// between them.
    private func materialStretches(in window: NSWindow, atHeight y: CGFloat) throws -> [ClosedRange<CGFloat>] {
        let content = try XCTUnwrap(window.contentView)
        let kind = PreferencesForm.makeBackground()
        // What is seen of a view: its frame, cut by every view it sits in (a pane is
        // longer than the scroll view that shows it). Not `visibleRect`: before a window
        // is shown that is wider than the view itself.
        func shownRect(of view: NSView) -> NSRect {
            var rect = view.convert(view.bounds, to: nil)
            var ancestor = view.superview
            while let outer = ancestor {
                rect = rect.intersection(outer.convert(outer.bounds, to: nil))
                ancestor = outer === content ? nil : outer.superview
            }
            return rect
        }
        let shown = ([content] + allSubviews(of: content))
            .compactMap { $0 as? NSVisualEffectView }
            .filter { !$0.isHiddenOrHasHiddenAncestor }
            .filter { $0.material == kind.material && $0.blendingMode == kind.blendingMode && $0.state == kind.state }
            .map(shownRect)
            .filter { $0.width > 0 && $0.minY <= y && y < $0.maxY }
            .sorted { $0.minX < $1.minX }
        var stretches: [ClosedRange<CGFloat>] = []
        for rect in shown {
            if let last = stretches.last, rect.minX <= last.upperBound {
                stretches[stretches.count - 1] = last.lowerBound...max(last.upperBound, rect.maxX)
            } else {
                stretches.append(rect.minX...rect.maxX)
            }
        }
        return stretches
    }

    /// At every height of the window, from its bottom to under the traffic lights, the
    /// material runs from the left edge to the right edge without a gap.
    private func assertTheMaterialFillsTheWindow(_ window: NSWindow, file: StaticString = #filePath, line: UInt = #line) throws {
        window.contentView?.layoutSubtreeIfNeeded()
        let content = try XCTUnwrap(window.contentView).bounds
        XCTAssertGreaterThan(content.height, 100, file: file, line: line)
        for y in stride(from: CGFloat(0.5), to: content.height, by: 1) {
            let stretches = try materialStretches(in: window, atHeight: y)
            guard stretches == [0...content.width] else {
                XCTFail("at height \(y) the material covers \(stretches) of 0...\(content.width)", file: file, line: line)
                return
            }
        }
    }

    /// A view's frame in the window.
    private func frameInWindow(_ view: NSView) -> NSRect {
        return view.convert(view.bounds, to: nil)
    }

    /// The window as macOS 14 and 15 have it: the pane's item beside the sidebar, its
    /// column the whole of its view, nothing of ours added for the sidebar.
    private func assertThePaneLiesBesideTheSidebar(
        _ window: NSWindow, _ preferences: PreferencesSplitViewController, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        window.contentView?.layoutSubtreeIfNeeded()
        let content = try XCTUnwrap(window.contentView).bounds
        let host = preferences.host
        XCTAssertFalse(preferences.paneLiesUnderSidebar, file: file, line: line)
        XCTAssertFalse(host.liesUnderSidebar, file: file, line: line)
        if #available(macOS 26.0, *) {
            XCTAssertTrue(preferences.splitViewItems.allSatisfy { !$0.automaticallyAdjustsSafeAreaInsets }, "no item is put under another", file: file, line: line)
        }
        // Side by side: the host's view starts where the sidebar's column ends and is the pane's column.
        let sidebar = frameInWindow(preferences.sidebar.view)
        let background = frameInWindow(host.view)
        XCTAssertEqual(background.minX, sidebar.maxX, file: file, line: line)
        XCTAssertEqual(background.width, PreferencesWindowLayout.contentWidth, file: file, line: line)
        XCTAssertEqual(background.maxX, content.width, file: file, line: line)
        XCTAssertEqual(host.view.safeAreaInsets.left, 0, file: file, line: line)
        XCTAssertEqual(frameInWindow(host.scrollView).minX, background.minX, file: file, line: line)
        XCTAssertEqual(frameInWindow(host.scrollView).width, background.width, file: file, line: line)
        // The column is tied to the view's own edge, as it always was, not to a safe area.
        let leading = host.view.constraints.filter { $0.firstItem === host.scrollView && $0.firstAttribute == .leading }
        XCTAssertEqual(leading.count, 1, file: file, line: line)
        XCTAssertTrue(leading.first?.secondItem === host.view, file: file, line: line)
        // No material of ours beside the split view (where the controller's view holds the
        // split view; where it is the split view, its subviews are the system's own).
        if preferences.view !== preferences.splitView {
            XCTAssertFalse(preferences.view.subviews.contains { $0 !== preferences.splitView && $0 is NSVisualEffectView }, file: file, line: line)
        }
        XCTAssertEqual(content.width, PreferencesWindowLayout.contentWidth(of: preferences.splitView), file: file, line: line)
    }

    /// Since macOS 26 the sidebar is glass that floats above what lies under it. Under it,
    /// and under the pane, lies one background: the pane host's material, not the window's
    /// plain background, which made the sidebar almost white next to the grey of the pane.
    /// The split view puts it there (`automaticallyAdjustsSafeAreaInsets`); nothing is
    /// placed by hand.
    func testOneMaterialLiesUnderTheSidebarAndThePane() throws {
        let (window, preferences) = try makeWindow()
        guard #available(macOS 26.0, *) else {
            XCTAssertFalse(PreferencesWindowLayout.paneLiesUnderSidebar, "older systems draw the sidebar's own material")
            try assertThePaneLiesBesideTheSidebar(window, preferences)
            return
        }
        XCTAssertTrue(PreferencesWindowLayout.paneLiesUnderSidebar)
        XCTAssertTrue(preferences.paneLiesUnderSidebar)
        XCTAssertTrue(preferences.host.liesUnderSidebar)
        // The item beside the sidebar may lie under it; the sidebar's own stays as it is.
        XCTAssertEqual(preferences.splitViewItems.map(\.automaticallyAdjustsSafeAreaInsets), [false, true])

        // One view is the background of the whole window, from the top (under the traffic
        // lights) to the bottom and from the left edge to the right: the pane host's.
        window.contentView?.layoutSubtreeIfNeeded()
        let content = try XCTUnwrap(window.contentView).bounds
        let host = preferences.host
        let background = try XCTUnwrap(host.view as? NSVisualEffectView)
        XCTAssertEqual(frameInWindow(background), content)
        let pane = PreferencesForm.makeBackground()
        XCTAssertEqual(background.material, pane.material)
        XCTAssertEqual(background.blendingMode, .behindWindow)
        XCTAssertEqual(background.state, pane.state)
        try assertTheMaterialFillsTheWindow(window)
        // Nothing of ours lies under or beside the split view any more.
        if preferences.view !== preferences.splitView {
            XCTAssertFalse(preferences.view.subviews.contains { $0 !== preferences.splitView && $0 is NSVisualEffectView })
        }

        // The column is where it was: from the sidebar's column to the window's right edge,
        // 520 pt. Where it starts is the system's word (the safe area), not a number of ours.
        let sidebar = frameInWindow(preferences.sidebar.view)
        let column = frameInWindow(host.scrollView)
        XCTAssertEqual(column.minX, background.safeAreaInsets.left)
        XCTAssertEqual(column.minX, sidebar.maxX)
        XCTAssertEqual(column.width, PreferencesWindowLayout.contentWidth)
        XCTAssertEqual(column.maxX, content.width)
        XCTAssertEqual(content.width, PreferencesWindowLayout.contentWidth(of: preferences.splitView))
        let shownPane = try XCTUnwrap(preferences.selectedController?.view)
        XCTAssertEqual(frameInWindow(shownPane).minX, column.minX)
        XCTAssertEqual(frameInWindow(shownPane).width, PreferencesWindowLayout.contentWidth)
        // The line under the title bar belongs to the column, it does not run under the sidebar.
        XCTAssertEqual(frameInWindow(host.titlebarSeparator).minX, column.minX)
        XCTAssertEqual(frameInWindow(host.titlebarSeparator).maxX, content.width)
        // The sidebar is above the pane's item: a click on a row is the list's, one in the column the pane's.
        let contentView = try XCTUnwrap(window.contentView)
        let table = preferences.sidebar.tableView!
        let row = table.convert(table.rect(ofRow: 0), to: nil)
        let hitInSidebar = try XCTUnwrap(contentView.hitTest(contentView.convert(NSPoint(x: row.midX, y: row.midY), from: nil)))
        XCTAssertTrue(hitInSidebar === table || hitInSidebar.isDescendant(of: table))
        let hitInColumn = try XCTUnwrap(contentView.hitTest(contentView.convert(NSPoint(x: column.midX, y: column.midY), from: nil)))
        XCTAssertTrue(hitInColumn.isDescendant(of: host.scrollView))
    }

    /// The line of 1.0.1 on macOS 26. That system sets the sidebar's glass 8 pt in
    /// from the window's edge, so the pane starts at 208 pt, not at the 200 pt that the
    /// material under the sidebar was given then: 8 pt of the window's own background
    /// showed between them, from the top of the window to its bottom. Here the sidebar's
    /// column is made 8 pt wider than `sidebarWidth`, as that system makes it; nothing may
    /// be left uncovered, and the column follows.
    func testNoStripShowsBesideASidebarColumnTheSystemMadeWider() throws {
        guard #available(macOS 26.0, *) else { return }
        let sidebarColumn = PreferencesWindowLayout.sidebarWidth + 8
        let (window, preferences) = try makeWindow { preferences in
            _ = preferences.view
            preferences.splitViewItems[0].minimumThickness = sidebarColumn
            preferences.splitViewItems[0].maximumThickness = sidebarColumn
        }
        window.contentView?.layoutSubtreeIfNeeded()
        // The window as macOS 26 lays it out: 728 pt wide, the pane from 208 pt on.
        let content = try XCTUnwrap(window.contentView).bounds
        XCTAssertEqual(content.width, sidebarColumn + PreferencesWindowLayout.contentWidth)
        let pane = try XCTUnwrap(preferences.selectedController?.view)
        XCTAssertEqual(frameInWindow(pane).minX, sidebarColumn)
        XCTAssertEqual(frameInWindow(pane).maxX, content.width)
        XCTAssertEqual(frameInWindow(preferences.host.scrollView).minX, sidebarColumn)
        XCTAssertEqual(frameInWindow(preferences.host.scrollView).width, PreferencesWindowLayout.contentWidth)

        XCTAssertEqual(frameInWindow(preferences.host.view), content)
        try assertTheMaterialFillsTheWindow(window)
    }

    /// The window keeps its width when it grows or shrinks: the background follows its height.
    func testTheBackgroundFollowsTheWindowsHeight() throws {
        guard #available(macOS 26.0, *) else { return }
        let (window, preferences) = try makeWindow()
        let width = window.contentRect(forFrameRect: window.frame).width
        for height in [CGFloat(900), PreferencesWindowLayout.minimumContentHeight] {
            window.setContentSize(NSSize(width: width, height: height))
            window.contentView?.layoutSubtreeIfNeeded()
            XCTAssertEqual(frameInWindow(preferences.host.view), NSRect(x: 0, y: 0, width: width, height: height))
            XCTAssertEqual(frameInWindow(preferences.host.scrollView).width, PreferencesWindowLayout.contentWidth)
            try assertTheMaterialFillsTheWindow(window)
        }
    }

    /// Before macOS 26 none of this runs: the sidebar draws its own material, the pane's
    /// item lies beside it and its column is its view, as in every version so far. Built
    /// here the way those systems build it (the switch is `paneLiesUnderSidebar`, which
    /// is false there), whatever system the tests run on.
    func testWithoutAFloatingSidebarThePaneLiesBesideIt() throws {
        let (window, preferences) = try makeWindow(paneLiesUnderSidebar: false)
        try assertThePaneLiesBesideTheSidebar(window, preferences)
        // A pane host on its own (a test's window, no sidebar) is the same either way.
        XCTAssertEqual(PreferencesPaneHostViewController().liesUnderSidebar, PreferencesWindowLayout.paneLiesUnderSidebar)
        if #available(macOS 26.0, *) {
            XCTAssertTrue(PreferencesWindowLayout.paneLiesUnderSidebar)
        } else {
            XCTAssertFalse(PreferencesWindowLayout.paneLiesUnderSidebar)
        }
    }

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

    func testAButtonThatSwitchesPanesLeavesTheFocusOnTheSidebar() throws {
        let (window, preferences) = try makeWindow()
        XCTAssertTrue(preferences.selectPane(withIdentifier: "gestures"))
        // A control of the pane has the keyboard focus, as "Open Mouse" has when it is
        // pressed with the keyboard.
        let focused = FocusTakingView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        try XCTUnwrap(preferences.selectedController).view.addSubview(focused)
        XCTAssertTrue(window.makeFirstResponder(focused))

        XCTAssertTrue(preferences.selectPane(withIdentifier: "mouse"))

        XCTAssertNil(focused.window, "the control went away with its pane")
        XCTAssertTrue(window.firstResponder === preferences.sidebar.tableView, "Tab goes on from the sidebar, not from the start")

        // Focus that is still in the window stays where it is.
        let other = FocusTakingView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        try XCTUnwrap(window.contentView).addSubview(other)
        XCTAssertTrue(window.makeFirstResponder(other))
        XCTAssertTrue(preferences.selectPane(withIdentifier: "general"))
        XCTAssertTrue(window.firstResponder === other)
    }

    func testSelectingThePaneOnShowScrollsItToTheTop() throws {
        let scrollingDefaults = makeDefaults()
        scrollingDefaults.set(true, forKey: PreferencesScrollingViewController.advancedExpandedDefaultsKey)
        let (window, preferences) = try makeWindow { preferences in
            (preferences.controller(for: "scrolling") as? PreferencesScrollingViewController)?.uiStateDefaults = scrollingDefaults
        }
        window.contentView?.layoutSubtreeIfNeeded()
        let host = preferences.host
        XCTAssertEqual(preferences.selectedPaneIdentifier, "scrolling")
        let visible = host.scrollView.contentSize.height
        XCTAssertGreaterThan(host.documentView.frame.height, visible, "the open pane is taller than the window")
        host.documentView.scroll(NSPoint(x: 0, y: host.documentView.frame.height - visible))
        XCTAssertGreaterThan(host.scrollView.contentView.bounds.minY, 0)
        XCTAssertFalse(host.titlebarSeparator.isHidden)

        // "About Scrollio" while General is open, or any other way to the pane on show.
        XCTAssertTrue(preferences.selectPane(withIdentifier: "scrolling"))

        XCTAssertEqual(host.scrollView.contentView.bounds.minY, 0)
        XCTAssertTrue(host.titlebarSeparator.isHidden)
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
        XCTAssertEqual(preferences.host.scrollView.frame.width, PreferencesWindowLayout.contentWidth)
        XCTAssertTrue(preferences.splitViewItems.first?.behavior == .sidebar)
        XCTAssertFalse(preferences.splitViewItems.first?.canCollapse ?? true)
        // The divider between two fixed widths takes no drag, and the pointer does not offer one.
        let divider = NSRect(x: PreferencesWindowLayout.sidebarWidth - 1, y: 0, width: 1, height: 640)
        XCTAssertEqual(
            preferences.splitView(preferences.splitView, effectiveRect: divider.insetBy(dx: -2, dy: 0), forDrawnRect: divider, ofDividerAt: 0),
            .zero
        )
        XCTAssertEqual(preferences.splitViewItems.map(\.minimumThickness), preferences.splitViewItems.map(\.maximumThickness))
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
        // The keys and the thumb wheel always show, so the pane with "Advanced" closed is
        // taller than the default window. Its budget: at most 1000 pt. A fixed window whose
        // column (under the title bar) holds the budget fits it, and not the open pane.
        let budget: CGFloat = 1000
        let closedHeight = scrolling.view.fittingSize.height
        XCTAssertLessThanOrEqual(closedHeight, budget, "the tab with Advanced closed stays within its budget")
        let width = window.contentRect(forFrameRect: window.frame).width
        window.setContentSize(NSSize(width: width, height: 1060))
        window.contentView?.layoutSubtreeIfNeeded()
        let frame = window.frame
        let visible = host.scrollView.contentSize.height
        XCTAssertGreaterThanOrEqual(visible, budget, "the column holds the budget")
        XCTAssertFalse(scrolling.isAdvancedExpanded)
        XCTAssertLessThanOrEqual(scrolling.view.frame.height, visible, "the pane fits")
        XCTAssertEqual(host.documentView.frame.height, visible)

        scrolling.setAdvancedExpanded(true)
        window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertEqual(window.frame, frame, "the window keeps its size")
        XCTAssertGreaterThan(scrolling.view.frame.height, closedHeight)
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
        window.setContentSize(NSSize(width: width, height: 1200))
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

/// Names the redesign changed. Only what the user reads changed: the identifiers that are
/// stored in the settings or used as keys are frozen below.
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
        XCTAssertEqual(SystemShortcut.scrollDash.localizedName, "Scroll Faster")
        XCTAssertEqual(SystemShortcut.scrollToggle.localizedName, "Scroll Sideways")
        XCTAssertEqual(SystemShortcut.scrollBlock.localizedName, "Pause Smoothing")
    }

    func testScrollActionIdentifiersAreFrozen() {
        XCTAssertEqual(SystemShortcut.scrollDash.identifier, "scrollDash")
        XCTAssertEqual(SystemShortcut.scrollToggle.identifier, "scrollToggle")
        XCTAssertEqual(SystemShortcut.scrollBlock.identifier, "scrollBlock")
        XCTAssertEqual(
            SystemShortcut.mouseScrollCategory.shortcuts.map(\.identifier),
            ["scrollDash", "scrollToggle", "scrollBlock"]
        )
    }

    func testTrackpadStyleEventsWording() throws {
        let scrolling = try XCTUnwrap(instantiate(PANEL_IDENTIFIER.scrolling) as? PreferencesScrollingViewController)
        _ = scrolling.view
        // "scrolling", not "events" (a developer's word).
        XCTAssertEqual(scrolling.trackpadEventsRow.title, "Trackpad-style scrolling (Beta)")
        XCTAssertEqual(scrolling.trackpadEventsSwitch.accessibilityLabel(), "Trackpad-style scrolling (Beta)")
        // The switch does nothing in Safari (ScrollUtils.TrackpadStyleTarget.plainScrolling):
        // the line says so, so it is not taken for broken there.
        XCTAssertEqual(
            scrolling.trackpadEventsRow.explanation,
            "Apps treat the wheel like a trackpad and bounce at the ends of a page. Safari stays as it is. Turn off if an app scrolls oddly."
        )
    }

    /// The actions that switch desktops say "desktop", as the rest of the app does, and do
    /// not read as "move this space" ("Move Space Left").
    func testSwitchingDesktopsIsNamedByTheDesktop() {
        XCTAssertEqual(SystemShortcut.moveSpaceLeft.localizedName, "Desktop on the Left")
        XCTAssertEqual(SystemShortcut.moveSpaceRight.localizedName, "Desktop on the Right")
        XCTAssertEqual(NSLocalizedString("thumb-wheel-function-desktops", comment: ""), "Switch Desktops")
        // The identifiers are stored: they stay.
        XCTAssertEqual(SystemShortcut.moveSpaceLeft.identifier, "moveSpaceLeft")
        XCTAssertEqual(SystemShortcut.moveSpaceRight.identifier, "moveSpaceRight")
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
            refresh: {}
        )
        _ = mouse.view
        mouse.reloadDevices()

        let gestures = GesturesPreferencesViewController(isInteractiveAvailable: { true })
        gestures.deviceSource = MouseGestureDeviceSource(support: { .none }, refresh: {})
        gestures.bindingSummary = { MouseGestureBindingSummary(hasGestureButton: false, hasLogitechGestureButton: false) }

        // The Scrolling tab with "Advanced" open, so every row is looked at.
        let scrolling = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesSplitViewController.self))
            .instantiateController(withIdentifier: PANEL_IDENTIFIER.scrolling) as! PreferencesScrollingViewController
        let uiDefaults = TestDefaults.make(for: self)
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
        let defaults = TestDefaults.make(for: self)
        defaults.set(true, forKey: PreferencesScrollingViewController.advancedExpandedDefaultsKey)
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
            mouse.deviceSource = MouseDeviceSource(deviceStates: { [MouseDeviceFixtures.mxMaster4()] }, refresh: {})
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
