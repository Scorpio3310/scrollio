//
//  PreferencesApplicationTests.swift
//  MosTests
//
//  The Apps pane: the truthful allowlist switch and its line while the list is empty, the
//  list of apps (rows, "+" menu of running apps, Choose in Finder, the new app's page
//  opened at once, duplicates, remove with undo, also from another pane and after the app
//  was added again), an app's page opened in place of the list and back again, "Use
//  settings from Scrolling" dimming the settings and, switched off, starting from them,
//  and the stored apps loading and saving unchanged. Nothing is shown on screen: the menu,
//  the open panel and the running apps go through seams, windows are never ordered in.
//

import XCTest
@testable import Mos_Debug

final class PreferencesApplicationTests: XCTestCase {

    private var originalApplications: EnhanceArray<Application>!
    private var originalAllowlist = false
    private var originalScroll: OPTIONS_SCROLL_DEFAULT!
    private var uiDefaults: UserDefaults!
    private var uiDefaultsSuite = ""

    private static let calculator = "/System/Applications/Calculator.app"
    private static let calculatorProgram = "/System/Applications/Calculator.app/Contents/MacOS/Calculator"
    private static let textEdit = "/System/Applications/TextEdit.app"
    private static let textEditProgram = "/System/Applications/TextEdit.app/Contents/MacOS/TextEdit"

    override func setUp() {
        super.setUp()
        originalApplications = Options.shared.application.applications
        originalAllowlist = Options.shared.application.allowlist
        originalScroll = Options.shared.scroll
        // Fresh containers, so the tests never edit the ones they restore.
        Options.shared.application.applications = Self.makeStore()
        Options.shared.scroll = OPTIONS_SCROLL_DEFAULT()
        uiDefaultsSuite = "ScrollioTests.apps.\(UUID().uuidString)"
        uiDefaults = UserDefaults(suiteName: uiDefaultsSuite)
        uiDefaults.set(false, forKey: PreferencesScrollingViewController.advancedExpandedDefaultsKey)
    }

    override func tearDown() {
        Options.shared.application.applications = originalApplications
        Options.shared.application.allowlist = originalAllowlist
        Options.shared.scroll = originalScroll
        originalApplications = nil
        originalScroll = nil
        uiDefaults.removePersistentDomain(forName: uiDefaultsSuite)
        uiDefaults = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private static func makeStore(_ applications: [Application] = []) -> EnhanceArray<Application> {
        return EnhanceArray<Application>(
            withArray: applications,
            matchKey: "path",
            forObserver: { Options.shared.markChanged(.application) }
        )
    }

    private func text(_ key: String) -> String {
        return NSLocalizedString(key, comment: "")
    }

    /// The pane as the window makes it (its storyboard scene is a shell), with fixed running
    /// apps and a menu that is caught instead of shown.
    private func makeController(
        running: [ApplicationCandidate] = [],
        menus: ((NSMenu) -> Void)? = nil
    ) -> PreferencesApplicationViewController {
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesSplitViewController.self))
        let controller = storyboard.instantiateController(withIdentifier: PANEL_IDENTIFIER.application) as! PreferencesApplicationViewController
        controller.uiStateDefaults = uiDefaults
        controller.runningApplications = { running }
        controller.presentMenu = { menu, _ in menus?(menu) }
        controller.chooseApplications = { _, _ in XCTFail("no open panel was expected") }
        _ = controller.view
        return controller
    }

    /// The pane in a window of its own (for the undo manager and the first responder). Never shown.
    private func makeWindow(for controller: NSViewController) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: PreferencesWindowLayout.contentWidth, height: 600),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: true
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.contentView?.layoutSubtreeIfNeeded()
        addTeardownBlock { window.close() }
        return window
    }

    /// The pane in a container of a window (so it can be taken out, as the window does when
    /// another pane shows). Never shown.
    private func makeContainedWindow(for controller: NSViewController) -> (NSWindow, NSView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: PreferencesWindowLayout.contentWidth, height: 600),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: true
        )
        window.isReleasedWhenClosed = false
        let container = NSView(frame: NSRect(x: 0, y: 0, width: PreferencesWindowLayout.contentWidth, height: 600))
        window.contentView = container
        container.addSubview(controller.view)
        addTeardownBlock { window.close() }
        return (window, container)
    }

    /// Removes the app of row `id` as "−" does, in an undo group of its own.
    private func remove(_ id: String, in controller: PreferencesApplicationViewController, undo: UndoManager) {
        controller.list.select(id)
        undo.beginUndoGrouping()
        controller.list.removeButton.performClick(nil)
        undo.endUndoGrouping()
    }

    private func storedObject() throws -> NSArray? {
        return try JSONSerialization.jsonObject(with: try XCTUnwrap(Options.shared.application.applications.json())) as? NSArray
    }

    private func candidate(_ bundle: String, program: String, name: String) -> ApplicationCandidate {
        return ApplicationCandidate(path: program, knownPaths: [bundle, program], name: name, icon: NSWorkspace.shared.icon(forFile: bundle))
    }

    private func application(_ path: String, inherit: Bool) -> Application {
        let application = Application(path: path)
        application.inherit = inherit
        return application
    }

    private func storedPaths() -> [String] {
        let stored = Options.shared.application.applications
        return (0..<stored.count).compactMap { stored.get(by: $0)?.path }
    }

    private func send(_ control: NSControl, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(control.sendAction(control.action, to: control.target), file: file, line: line)
    }

    private func key(_ characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        return try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
        ))
    }

    private func allSubviews(of view: NSView) -> [NSView] {
        return view.subviews.flatMap { [$0] + allSubviews(of: $0) }
    }

    // MARK: - Pane

    func testThePaneIsTheStoryboardSceneBuiltInCode() {
        let controller = makeController()
        XCTAssertEqual(controller.title, "Apps", "the window keeps its title")
        XCTAssertEqual(controller.view.frame.width, PreferencesWindowLayout.contentWidth)
        XCTAssertEqual(controller.view.frame.size, controller.view.fittingSize)
        XCTAssertTrue(controller.currentPage === controller.listPage)
        XCTAssertNil(controller.detailController)
        // Nothing of the old table is left.
        let views = allSubviews(of: controller.view)
        XCTAssertFalse(views.contains { $0 is NSTableView })
        XCTAssertFalse(views.contains { ($0 as? NSTextField)?.stringValue == "Only in listed apps" })
    }

    func testTheAllowlistSwitchSaysWhatItLimitsAndWritesTheAllowlist() {
        Options.shared.application.allowlist = false
        let controller = makeController()
        XCTAssertEqual(controller.allowlistRow.title, "Limit scrolling to these apps")
        XCTAssertEqual(
            controller.allowlistRow.explanation,
            "Apps not in the list scroll the way macOS does. Buttons and gestures still work everywhere."
        )
        XCTAssertEqual(controller.allowlistSwitch.state, .off)
        XCTAssertEqual(controller.allowlistSwitch.identifier, PreferencesApplicationViewController.Identifier.allowlist)

        controller.allowlistSwitch.state = .on
        send(controller.allowlistSwitch)
        XCTAssertTrue(Options.shared.application.allowlist)
        controller.allowlistSwitch.state = .off
        send(controller.allowlistSwitch)
        XCTAssertFalse(Options.shared.application.allowlist)

        // Set elsewhere: the pane shows it when it appears again.
        Options.shared.application.allowlist = true
        controller.viewWillAppear()
        XCTAssertEqual(controller.allowlistSwitch.state, .on)
        XCTAssertEqual(storedPaths(), [], "the switch leaves the list alone")
    }

    /// The limit on with no app on the list switches smoothing and reversing off in every
    /// app: a muted line under the switch says so, only then.
    func testTheLimitWithAnEmptyListSaysEveryAppScrollsTheWayMacOSDoes() throws {
        Options.shared.application.allowlist = false
        let controller = makeController()
        let note = try XCTUnwrap(controller.allowlistEmptyNote)
        XCTAssertTrue(note.isHidden, "the limit is off")
        let offHeight = controller.view.frame.height

        controller.allowlistSwitch.state = .on
        send(controller.allowlistSwitch)
        XCTAssertFalse(note.isHidden)
        XCTAssertEqual(controller.allowlistEmptyLabel.stringValue, "No apps on the list yet: every app scrolls the way macOS does.")
        XCTAssertEqual(controller.allowlistEmptyLabel.identifier, PreferencesApplicationViewController.Identifier.allowlistEmpty)
        XCTAssertEqual(controller.allowlistEmptyLabel.textColor, PreferencesGroupedForm.explanationColor(enabled: true))
        XCTAssertGreaterThan(controller.view.frame.height, offHeight, "the pane makes room for it")
        XCTAssertEqual(controller.view.frame.size, controller.view.fittingSize)
        // Right under the switch's box, above the list.
        let content = try XCTUnwrap(note.superview as? NSStackView)
        XCTAssertEqual(content.arrangedSubviews.firstIndex(of: note), 1)
        XCTAssertTrue(content.arrangedSubviews[0] === controller.allowlistSection)
        XCTAssertEqual(content.customSpacing(after: controller.allowlistSection), PreferencesGroupedForm.noteSpacing)

        // An app on the list: the line goes; removed again, it comes back.
        controller.addApplication(path: Self.calculator, knownPaths: [Self.calculator])
        controller.showList(focusList: false)
        XCTAssertTrue(note.isHidden)
        XCTAssertEqual(content.customSpacing(after: controller.allowlistSection), PreferencesGroupedForm.sectionSpacing)
        controller.removeApplication(withID: Self.calculator)
        XCTAssertFalse(note.isHidden)

        // Off again, or switched off elsewhere: gone.
        controller.allowlistSwitch.state = .off
        send(controller.allowlistSwitch)
        XCTAssertTrue(note.isHidden)
        XCTAssertEqual(controller.view.frame.height, offHeight, accuracy: 0.5)
        Options.shared.application.allowlist = true
        controller.viewWillAppear()
        XCTAssertFalse(note.isHidden)
        XCTAssertEqual(storedPaths(), [], "the line changes nothing")

        XCTAssertTrue(PreferencesApplicationViewController.showsAllowlistEmptyNote(allowlist: true, applicationCount: 0))
        XCTAssertFalse(PreferencesApplicationViewController.showsAllowlistEmptyNote(allowlist: true, applicationCount: 1))
        XCTAssertFalse(PreferencesApplicationViewController.showsAllowlistEmptyNote(allowlist: false, applicationCount: 0))
    }

    func testAnEmptyListSaysHowToAddAnApp() {
        let controller = makeController()
        XCTAssertTrue(controller.list.rows.isEmpty)
        XCTAssertEqual(controller.list.emptyRow.title, "No apps yet")
        XCTAssertEqual(controller.list.emptyRow.explanation, "Click + to give an app its own scrolling settings.")
        XCTAssertFalse(controller.list.removeButton.isEnabled)
        XCTAssertEqual(controller.listSection.titleLabel?.stringValue, "Apps")
    }

    func testRowsShowTheIconTheNameAndWhetherTheAppHasItsOwnSettings() throws {
        let own = application(Self.calculator, inherit: false)
        let inheriting = application(Self.textEditProgram, inherit: true)
        let renamed = application("/Applications/Renamed Test.app", inherit: true)
        renamed.displayName = "My Renamed App"
        Options.shared.application.applications = Self.makeStore([own, inheriting, renamed])

        let controller = makeController()
        let rows = controller.list.rows
        XCTAssertEqual(rows.map { $0.id as? String }, [Self.calculator, Self.textEditProgram, "/Applications/Renamed Test.app"])
        XCTAssertEqual(rows.map(\.title), ["Calculator", "TextEdit", "My Renamed App"])
        XCTAssertEqual(rows.map(\.explanation), ["Uses its own scrolling settings", "Uses your scrolling settings", "Uses your scrolling settings"])
        for row in rows {
            let icon = try XCTUnwrap(row.iconView, row.title)
            XCTAssertNotNil(icon.image, row.title)
            XCTAssertEqual(icon.image?.isTemplate, false, "an app's own icon, not a symbol")
            XCTAssertNotNil(row.chevronView, "\(row.title) opens a page of its own")
        }
        XCTAssertEqual(rows[0].accessibilityLabel(), "Calculator, Uses its own scrolling settings")
        XCTAssertEqual(rows[1].toolTip, "TextEdit\n" + Self.textEditProgram, "the name, then the path")
    }

    // MARK: - Adding

    func testPlusOffersTheRunningAppsThenChooseInFinder() throws {
        Options.shared.application.applications = Self.makeStore([application(Self.calculator, inherit: true)])
        var shown: [NSMenu] = []
        let controller = makeController(running: [
            candidate(Self.calculator, program: Self.calculatorProgram, name: "Calculator"),
            candidate(Self.textEdit, program: Self.textEditProgram, name: "TextEdit"),
        ], menus: { shown.append($0) })

        controller.list.addButton.performClick(nil)
        let menu = try XCTUnwrap(shown.first, "+ shows a menu")
        XCTAssertEqual(menu.items.map(\.title), ["Calculator", "TextEdit", "", "Choose in Finder…"])
        XCTAssertTrue(menu.items[2].isSeparatorItem)
        // On the list already: off, with a checkmark.
        XCTAssertFalse(menu.items[0].isEnabled)
        XCTAssertEqual(menu.items[0].state, .on)
        XCTAssertTrue(menu.items[1].isEnabled)
        XCTAssertEqual(menu.items[1].state, .off)
        for item in menu.items.prefix(2) {
            XCTAssertEqual(item.image?.size, NSSize(width: 16, height: 16), item.title)
        }
        XCTAssertEqual(menu.items[3].identifier, PreferencesApplicationViewController.Identifier.chooseInFinder)
        XCTAssertTrue(menu.items[3].isEnabled)

        // Picking a running app adds it by its program's path, as the pane always stored
        // running apps, selects it and opens its page: adding alone changes nothing.
        menu.performActionForItem(at: 1)
        XCTAssertEqual(storedPaths(), [Self.calculator, Self.textEditProgram])
        XCTAssertEqual(controller.list.selectedID, AnyHashable(Self.textEditProgram))
        let added = try XCTUnwrap(Options.shared.application.applications.get(by: Self.textEditProgram))
        XCTAssertTrue(added.inherit, "a new app starts with the Scrolling settings")
        XCTAssertEqual(controller.list.rows.last?.title, "TextEdit")
        let page = try XCTUnwrap(controller.detailController, "the new app's page opens")
        XCTAssertTrue(page.application === added)
        XCTAssertTrue(controller.currentPage === page.view)
        XCTAssertEqual(page.inheritSwitch.state, .on)

        // Back on the list, the same app picked again: it blinks, no page opens.
        controller.showList(focusList: false)
        controller.addRunningApplication(try XCTUnwrap(controller.makeAddMenu().items.first { $0.title == "TextEdit" }))
        XCTAssertNil(controller.detailController)
        XCTAssertEqual(storedPaths(), [Self.calculator, Self.textEditProgram])
    }

    /// The page opens in the window with the keyboard on it, as a double-click opens it.
    func testAnAppAddedInTheWindowOpensItsPageWithTheKeyboardOnIt() throws {
        let controller = makeController(running: [candidate(Self.textEdit, program: Self.textEditProgram, name: "TextEdit")])
        let window = makeWindow(for: controller)
        controller.addRunningApplication(try XCTUnwrap(controller.makeAddMenu().items.first))
        let page = try XCTUnwrap(controller.detailController)
        XCTAssertTrue(window.firstResponder === page.view, "Esc goes back to the list straight away")
        XCTAssertEqual(controller.view.frame.height, page.view.fittingSize.height, accuracy: 0.5)
    }

    func testWithoutRunningAppsThePlusMenuOnlyOffersFinder() throws {
        var shown: [NSMenu] = []
        let controller = makeController(running: [], menus: { shown.append($0) })
        controller.list.addButton.performClick(nil)
        XCTAssertEqual(try XCTUnwrap(shown.first).items.map(\.title), ["Choose in Finder…"])
    }

    func testChooseInFinderAddsTheChosenAppsByTheirBundles() throws {
        var shown: [NSMenu] = []
        let controller = makeController(menus: { shown.append($0) })
        controller.chooseApplications = { _, completion in
            completion([URL(fileURLWithPath: Self.calculator), URL(fileURLWithPath: Self.textEdit)])
        }
        controller.list.addButton.performClick(nil)
        let menu = try XCTUnwrap(shown.first)
        menu.performActionForItem(at: menu.indexOfItem(withTitle: "Choose in Finder…"))

        XCTAssertEqual(storedPaths(), [Self.calculator, Self.textEdit])
        XCTAssertEqual(controller.list.selectedID, AnyHashable(Self.textEdit), "the last new app is selected")
        XCTAssertEqual(controller.detailController?.application.path, Self.textEdit, "and its page opens")

        // Cancelled: nothing changes.
        controller.chooseApplications = { _, completion in completion([]) }
        controller.chooseInFinderClick(nil)
        XCTAssertEqual(storedPaths(), [Self.calculator, Self.textEdit])
    }

    func testTheFinderPanelOnlyChoosesAppsFromApplications() {
        let panel = PreferencesApplicationViewController.makeOpenPanel()
        XCTAssertEqual(panel.allowedContentTypes, [.application])
        XCTAssertTrue(panel.allowsMultipleSelection)
        XCTAssertFalse(panel.canChooseDirectories)
        XCTAssertTrue(panel.canChooseFiles)
        XCTAssertEqual(panel.directoryURL?.path, "/Applications")
        XCTAssertEqual(panel.prompt, "Add")
    }

    func testAddingAnAppThatIsListedSelectsItInsteadOfAddingItAgain() {
        // Stored by its program (picked while running) and by its bundle (chosen in Finder).
        Options.shared.application.applications = Self.makeStore([
            application(Self.calculatorProgram, inherit: false),
            application(Self.textEdit, inherit: true),
        ])
        let controller = makeController()
        controller.list.select(nil)

        // Chosen in Finder, while it is stored by its program.
        controller.addApplications(at: [URL(fileURLWithPath: Self.calculator)])
        XCTAssertEqual(storedPaths(), [Self.calculatorProgram, Self.textEdit])
        XCTAssertEqual(controller.list.selectedID, AnyHashable(Self.calculatorProgram))

        // Picked while running, while it is stored by its bundle.
        let textEdit = controller.addApplication(path: Self.textEditProgram, knownPaths: [Self.textEdit, Self.textEditProgram])
        XCTAssertEqual(textEdit.path, Self.textEdit)
        XCTAssertEqual(storedPaths(), [Self.calculatorProgram, Self.textEdit])
        XCTAssertEqual(controller.list.selectedID, AnyHashable(Self.textEdit))
        XCTAssertNil(controller.detailController, "nothing was added: the list stays")
    }

    // MARK: - Removing

    func testRemovingAnAppCanBeUndoneWithItsSettingsAndRedone() throws {
        let calculator = application(Self.calculator, inherit: false)
        calculator.scroll.speed = 2.5
        calculator.scroll.dash = nil
        let textEdit = application(Self.textEdit, inherit: true)
        Options.shared.application.applications = Self.makeStore([calculator, textEdit])
        let before = try XCTUnwrap(Options.shared.application.applications.json())

        let controller = makeController()
        let window = makeWindow(for: controller)
        let undo = try XCTUnwrap(window.undoManager)
        undo.groupsByEvent = false

        controller.list.select(Self.calculator)
        XCTAssertTrue(controller.list.removeButton.isEnabled)
        undo.beginUndoGrouping()
        controller.list.removeButton.performClick(nil)
        undo.endUndoGrouping()

        XCTAssertEqual(storedPaths(), [Self.textEdit])
        XCTAssertEqual(controller.list.rows.map { $0.id as? String }, [Self.textEdit])
        XCTAssertNil(controller.list.selectedID)
        XCTAssertTrue(undo.canUndo)
        XCTAssertEqual(undo.undoActionName, "Remove App")
        XCTAssertEqual(undo.undoMenuItemTitle, "Undo Remove App")

        undo.undo()
        XCTAssertEqual(storedPaths(), [Self.calculator, Self.textEdit], "back in its place")
        let restored = try XCTUnwrap(Options.shared.application.applications.get(by: Self.calculator))
        XCTAssertTrue(restored === calculator, "the same app, with its own settings")
        XCTAssertEqual(restored.scroll.speed, 2.5)
        XCTAssertFalse(restored.inherit)
        XCTAssertEqual(controller.list.selectedID, AnyHashable(Self.calculator))
        XCTAssertEqual(
            try JSONSerialization.jsonObject(with: try XCTUnwrap(Options.shared.application.applications.json())) as? NSArray,
            try JSONSerialization.jsonObject(with: before) as? NSArray,
            "stored as before the removal"
        )

        XCTAssertTrue(undo.canRedo)
        undo.redo()
        XCTAssertEqual(storedPaths(), [Self.textEdit])
        undo.undo()
        XCTAssertEqual(storedPaths(), [Self.calculator, Self.textEdit])
    }

    /// Earlier builds let Finder add an app that was on the list already: both entries
    /// show, each row opens and removes its own.
    func testAnAppStoredTwiceShowsTwoRowsThatEachHandleTheirOwn() throws {
        let first = application(Self.calculator, inherit: true)
        let second = application(Self.calculator, inherit: false)
        Options.shared.application.applications = Self.makeStore([first, second])
        let controller = makeController()
        let ids = controller.list.rows.compactMap { $0.id as? String }
        XCTAssertEqual(ids, [Self.calculator, Self.calculator + "#2"])
        XCTAssertTrue(controller.application(forRowID: ids[1]) === second)

        controller.openApplication(withID: ids[1])
        XCTAssertTrue(controller.detailController?.application === second)
        controller.showList(focusList: false)
        XCTAssertEqual(controller.list.selectedID, AnyHashable(ids[1]))

        controller.removeApplication(withID: ids[1])
        XCTAssertEqual(controller.applications.count, 1)
        XCTAssertTrue(controller.applications.first === first)
    }

    func testTheDeleteKeyRemovesTheSelectedApp() throws {
        Options.shared.application.applications = Self.makeStore([application(Self.calculator, inherit: true)])
        let controller = makeController()
        let window = makeWindow(for: controller)
        controller.list.select(Self.calculator)
        window.makeFirstResponder(controller.list)
        controller.list.keyDown(with: try key("\u{7F}", keyCode: 51))
        XCTAssertEqual(storedPaths(), [])
        XCTAssertTrue(controller.list.rows.isEmpty)
    }

    /// Removed, then added again (a fresh entry), then Undo: no second entry for the app;
    /// the removed settings go onto the entry that is there, and Redo takes them off again.
    func testUndoAfterTheAppWasAddedAgainPutsItsSettingsOnTheEntryThatIsThere() throws {
        let calculator = application(Self.calculator, inherit: false)
        calculator.scroll.speed = 2.5
        calculator.displayName = "Numbers"
        let textEdit = application(Self.textEdit, inherit: true)
        Options.shared.application.applications = Self.makeStore([calculator, textEdit])
        let before = try storedObject()

        let controller = makeController()
        let window = makeWindow(for: controller)
        let undo = try XCTUnwrap(window.undoManager)
        undo.groupsByEvent = false
        remove(Self.calculator, in: controller, undo: undo)
        XCTAssertEqual(storedPaths(), [Self.textEdit])

        // Added again, chosen in Finder: a new entry with the Scrolling settings, its page
        // open; back to the list.
        controller.addApplications(at: [URL(fileURLWithPath: Self.calculator)])
        let again = try XCTUnwrap(Options.shared.application.applications.get(by: Self.calculator))
        XCTAssertFalse(again === calculator)
        XCTAssertTrue(again.inherit)
        XCTAssertEqual(storedPaths(), [Self.textEdit, Self.calculator])
        XCTAssertTrue(controller.detailController?.application === again)
        controller.showList(focusList: false)

        window.makeFirstResponder(nil)
        undo.undo()
        XCTAssertEqual(storedPaths(), [Self.textEdit, Self.calculator], "one entry for the app, where it is")
        XCTAssertEqual(controller.list.rows.count, 2)
        XCTAssertTrue(Options.shared.application.applications.get(by: Self.calculator) === again)
        XCTAssertFalse(again.inherit, "the removed entry's settings")
        XCTAssertEqual(again.scroll.speed, 2.5)
        XCTAssertEqual(again.displayName, "Numbers")
        XCTAssertEqual(controller.list.rows.last?.explanation, "Uses its own scrolling settings")
        XCTAssertEqual(controller.list.selectedID, AnyHashable(Self.calculator))
        XCTAssertTrue(window.firstResponder === controller.list)
        XCTAssertEqual(Set((try storedObject() ?? []).compactMap { $0 as? NSDictionary }),
                       Set((before ?? []).compactMap { $0 as? NSDictionary }),
                       "stored as before the removal, in another order")

        XCTAssertEqual(undo.redoMenuItemTitle, "Redo Remove App")
        undo.redo()
        XCTAssertTrue(again.inherit, "the settings it had")
        XCTAssertEqual(again.scroll.speed, OPTIONS_SCROLL_DEFAULT().speed)
        XCTAssertEqual(again.displayName, "")
        XCTAssertEqual(storedPaths(), [Self.textEdit, Self.calculator])
        undo.undo()
        XCTAssertFalse(again.inherit)
        XCTAssertEqual(storedPaths(), [Self.textEdit, Self.calculator])
    }

    /// The same when the app came back under its other path (picked while running, by its
    /// program, after it was stored by its bundle).
    func testUndoFindsTheAppAddedAgainUnderItsProgram() throws {
        let calculator = application(Self.calculator, inherit: false)
        Options.shared.application.applications = Self.makeStore([calculator])
        let controller = makeController()
        let window = makeWindow(for: controller)
        let undo = try XCTUnwrap(window.undoManager)
        undo.groupsByEvent = false
        remove(Self.calculator, in: controller, undo: undo)
        let again = controller.addApplication(path: Self.calculatorProgram, knownPaths: [Self.calculator, Self.calculatorProgram])

        undo.undo()
        XCTAssertEqual(storedPaths(), [Self.calculatorProgram])
        XCTAssertFalse(again.inherit)
        XCTAssertEqual(PreferencesApplicationViewController.knownPaths(forStoredPath: Self.calculatorProgram),
                       [Self.calculatorProgram, Self.calculator])
        XCTAssertEqual(PreferencesApplicationViewController.knownPaths(forStoredPath: Self.calculator),
                       [Self.calculator, Self.calculatorProgram])
        XCTAssertEqual(PreferencesApplicationViewController.knownPaths(forStoredPath: "/usr/local/bin/tool"), ["/usr/local/bin/tool"])
    }

    /// Undo from the Edit menu while another pane shows (the pane is out of the window):
    /// the app comes back, and Redo and Undo keep working.
    func testUndoAndRedoWorkWhileAnotherPaneShows() throws {
        let calculator = application(Self.calculator, inherit: false)
        Options.shared.application.applications = Self.makeStore([calculator, application(Self.textEdit, inherit: true)])
        let controller = makeController()
        let (window, container) = makeContainedWindow(for: controller)
        let undo = try XCTUnwrap(window.undoManager)
        undo.groupsByEvent = false
        remove(Self.calculator, in: controller, undo: undo)
        XCTAssertEqual(storedPaths(), [Self.textEdit])

        controller.view.removeFromSuperview()
        XCTAssertNil(controller.view.window)
        undo.undo()
        XCTAssertEqual(storedPaths(), [Self.calculator, Self.textEdit])
        XCTAssertTrue(Options.shared.application.applications.get(by: Self.calculator) === calculator)
        XCTAssertTrue(undo.canRedo, "the chain goes on")
        undo.redo()
        XCTAssertEqual(storedPaths(), [Self.textEdit])

        container.addSubview(controller.view)
        undo.undo()
        XCTAssertEqual(storedPaths(), [Self.calculator, Self.textEdit])
        XCTAssertEqual(controller.list.selectedID, AnyHashable(Self.calculator))
        XCTAssertTrue(window.firstResponder === controller.list, "the list has the keyboard")
    }

    // MARK: - An app's page

    func testOpeningAnAppShowsItsPageInsteadOfTheListAndBackComesBack() throws {
        let calculator = application(Self.calculator, inherit: false)
        calculator.scroll.speed = 4.2
        Options.shared.application.applications = Self.makeStore([application(Self.textEdit, inherit: true), calculator])
        let controller = makeController()
        let listHeight = controller.view.frame.height

        // Return on the selected row opens it.
        controller.list.select(Self.calculator)
        controller.list.keyDown(with: try key("\r", keyCode: 36))
        let page = try XCTUnwrap(controller.detailController)
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertTrue(page.application === calculator)
        XCTAssertTrue(page.parent === controller)
        XCTAssertTrue(controller.currentPage === page.view)
        XCTAssertTrue(page.view.isDescendant(of: controller.view))
        XCTAssertFalse(controller.listPage.isDescendant(of: controller.view))
        XCTAssertEqual(controller.title, "Apps", "the window title stays")
        // The header: the app's icon, name and where it is; then its Scrolling settings.
        XCTAssertEqual(page.headerRow.title, "Calculator")
        XCTAssertEqual(page.headerRow.explanation, Self.calculator)
        XCTAssertEqual(page.headerRow.toolTip, "Calculator\n" + Self.calculator)
        XCTAssertEqual(page.headerRow.iconView.frame.size, NSSize(width: 32, height: 32))
        XCTAssertNotNil(page.headerRow.iconView.image)
        XCTAssertEqual(page.backButton.title, "Apps")
        XCTAssertEqual(page.backButton.accessibilityLabel(), "Back to Apps")
        XCTAssertFalse(page.backButton.isBordered)
        XCTAssertTrue(page.scrollingController.currentTargetApplication === calculator)
        XCTAssertTrue(page.scrollingController.previewView.isHidden)
        XCTAssertEqual(page.scrollingController.scrollSpeedSlider.doubleValue, 4.2, accuracy: 1e-9)
        // The pane takes the page's height.
        XCTAssertEqual(controller.view.frame.height, page.view.fittingSize.height, accuracy: 0.5)
        XCTAssertGreaterThan(controller.view.frame.height, listHeight)
        // No rename any more.
        XCTAssertFalse(allSubviews(of: page.view).contains { ($0 as? NSTextField)?.isEditable == true })

        page.backButton.performClick(nil)
        XCTAssertNil(controller.detailController)
        XCTAssertNil(page.parent)
        XCTAssertTrue(controller.currentPage === controller.listPage)
        XCTAssertTrue(controller.listPage.isDescendant(of: controller.view))
        XCTAssertFalse(page.view.isDescendant(of: controller.view))
        XCTAssertEqual(controller.list.selectedID, AnyHashable(Self.calculator), "the app stays selected")
        XCTAssertEqual(controller.view.frame.height, listHeight, accuracy: 0.5)
    }

    func testEscapeCommandBracketAndLeavingThePaneGoBackToTheList() throws {
        Options.shared.application.applications = Self.makeStore([application(Self.calculator, inherit: true)])
        let controller = makeController()

        controller.openApplication(withID: Self.calculator)
        try XCTUnwrap(controller.detailController).view.keyDown(with: try key("\u{1b}", keyCode: 53))
        XCTAssertNil(controller.detailController, "Esc")

        controller.openApplication(withID: Self.calculator)
        let page = try XCTUnwrap(controller.detailController)
        XCTAssertFalse(page.view.performKeyEquivalent(with: try key("[", keyCode: 33)), "[ alone does nothing")
        XCTAssertNotNil(controller.detailController)
        XCTAssertTrue(page.view.performKeyEquivalent(with: try key("[", keyCode: 33, modifiers: .command)))
        XCTAssertNil(controller.detailController, "⌘[")

        controller.openApplication(withID: Self.calculator)
        try XCTUnwrap(controller.detailController).cancelOperation(nil)
        XCTAssertNil(controller.detailController, "Esc passed on as a command")

        controller.openApplication(withID: Self.calculator)
        controller.viewDidDisappear()
        XCTAssertNil(controller.detailController, "leaving the pane")
        XCTAssertTrue(controller.currentPage === controller.listPage)
    }

    func testAClickOnTheChevronOpensTheApp() throws {
        Options.shared.application.applications = Self.makeStore([application(Self.calculator, inherit: true)])
        let controller = makeController()
        let window = makeWindow(for: controller)
        let row = try XCTUnwrap(controller.list.rows.first as? ApplicationListRow)
        let chevron = try XCTUnwrap(row.chevronView)
        let middle = NSPoint(x: chevron.frame.midX, y: chevron.frame.midY)
        XCTAssertTrue(row.isChevronHit(at: middle))
        XCTAssertFalse(row.isChevronHit(at: NSPoint(x: row.bounds.midX, y: row.bounds.midY)))

        // A click on the row's texts only selects it.
        let title = row.convert(NSPoint(x: row.titleLabel.frame.midX, y: row.titleLabel.frame.midY), to: nil)
        row.mouseDown(with: try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown, location: title, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        )))
        XCTAssertEqual(controller.list.selectedID, AnyHashable(Self.calculator))
        XCTAssertNil(controller.detailController)

        row.mouseDown(with: try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown, location: row.convert(middle, to: nil), modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        )))
        XCTAssertNotNil(controller.detailController)
    }

    func testUseSettingsFromScrollingDimsTheSettingsAndUpdatesTheList() throws {
        Options.shared.scroll.speed = 8.5
        let calculator = application(Self.calculator, inherit: false)
        calculator.scroll.speed = 1.5
        Options.shared.application.applications = Self.makeStore([calculator])
        let controller = makeController()
        controller.openApplication(withID: Self.calculator)
        let page = try XCTUnwrap(controller.detailController)
        let scrolling = try XCTUnwrap(page.scrollingController)

        XCTAssertEqual(page.inheritRow.title, "Use settings from Scrolling")
        XCTAssertEqual(page.inheritSwitch.state, .off)
        XCTAssertEqual(page.inheritRow.explanation, "Calculator keeps its own settings below.")
        XCTAssertEqual(page.inheritSwitch.controlSize, PreferencesGroupedForm.switchControlSize)
        XCTAssertTrue(scrolling.smoothRow.isEnabled)
        XCTAssertTrue(scrolling.speedRow.isEnabled)
        XCTAssertEqual(scrolling.scrollSpeedSlider.doubleValue, 1.5, accuracy: 1e-9)
        let height = page.view.fittingSize.height

        page.inheritSwitch.state = .on
        send(page.inheritSwitch)
        XCTAssertTrue(calculator.inherit)
        XCTAssertEqual(page.inheritRow.explanation, "Changes under Scrolling apply to Calculator too.")
        let rows: [PreferencesGroupRow] = [scrolling.smoothRow, scrolling.feelRow, scrolling.speedRow, scrolling.reverseRow]
            + scrolling.keyRows
        XCTAssertTrue(rows.allSatisfy { !$0.isEnabled }, "dimmed while the app uses the Scrolling settings")
        XCTAssertFalse(scrolling.resetToDefaultsButton.isEnabled)
        XCTAssertEqual(scrolling.scrollSpeedSlider.doubleValue, 8.5, accuracy: 1e-9, "the Scrolling pane's value")
        XCTAssertEqual(calculator.scroll.speed, 1.5, "its own value is kept for later")
        XCTAssertEqual(controller.list.rows.first?.explanation, "Uses your scrolling settings")
        XCTAssertEqual(page.view.fittingSize.height, height, accuracy: 0.5, "the other line takes the same room")

        page.inheritSwitch.state = .off
        send(page.inheritSwitch)
        XCTAssertFalse(calculator.inherit)
        XCTAssertTrue(rows.allSatisfy(\.isEnabled))
        XCTAssertEqual(scrolling.scrollSpeedSlider.doubleValue, 1.5, accuracy: 1e-9)
        XCTAssertEqual(controller.list.rows.first?.explanation, "Uses its own scrolling settings")
    }

    /// A new app's own options are those of a new installation: switched off as they were,
    /// Reverse would come back on and Speed and the keys go to the factory values. Never
    /// edited, they start as a copy of the Scrolling settings; edited ones are kept.
    func testSwitchingOffUseSettingsFromScrollingStartsFromTheScrollingSettings() throws {
        Options.shared.scroll.reversesWheel = false
        Options.shared.scroll.speed = 8.5
        Options.shared.scroll.dash = nil
        Options.shared.scroll.duration = ScrollFeel.glide.duration
        let fresh = application(Self.calculator, inherit: true)
        let edited = application(Self.textEdit, inherit: true)
        edited.scroll.speed = 2
        Options.shared.application.applications = Self.makeStore([fresh, edited])
        let controller = makeController()

        controller.openApplication(withID: Self.calculator)
        var page = try XCTUnwrap(controller.detailController)
        page.inheritSwitch.state = .off
        send(page.inheritSwitch)
        XCTAssertFalse(fresh.inherit)
        XCTAssertEqual(fresh.scroll, Options.shared.scroll, "the wheel scrolls on as before")
        XCTAssertFalse(fresh.scroll === Options.shared.scroll, "a copy: the app's own container")
        XCTAssertFalse(fresh.scroll.reversesWheel)
        let scrolling = try XCTUnwrap(page.scrollingController)
        XCTAssertEqual(scrolling.reverseSwitch.state, .off)
        XCTAssertEqual(scrolling.scrollSpeedSlider.doubleValue, 8.5, accuracy: 1e-9)
        XCTAssertEqual(scrolling.feelControl.selectedSegment, ScrollFeel.glide.rawValue)
        XCTAssertTrue(scrolling.speedRow.isEnabled)
        // Its own from now on: a change stays with the app.
        scrolling.scrollSpeedSlider.doubleValue = 3
        send(scrolling.scrollSpeedSlider)
        XCTAssertEqual(fresh.scroll.speed, 3)
        XCTAssertEqual(Options.shared.scroll.speed, 8.5)
        // On and off again: its own options are edited now, so they stay.
        page.inheritSwitch.state = .on
        send(page.inheritSwitch)
        page.inheritSwitch.state = .off
        send(page.inheritSwitch)
        XCTAssertEqual(fresh.scroll.speed, 3)

        // Edited earlier: kept, Reverse and all.
        controller.showList(focusList: false)
        controller.openApplication(withID: Self.textEdit)
        page = try XCTUnwrap(controller.detailController)
        page.inheritSwitch.state = .off
        send(page.inheritSwitch)
        XCTAssertEqual(edited.scroll.speed, 2)
        XCTAssertTrue(edited.scroll.reversesWheel, "the app's own value")
        XCTAssertEqual(edited.scroll.dash, OPTIONS_SCROLL_DEFAULT().dash)

        // Stored as before: the same keys, the copied values.
        let stored = try XCTUnwrap(try storedObject()?.firstObject as? NSDictionary)
        XCTAssertEqual(Set(stored.allKeys.compactMap { $0 as? String }), ["path", "displayName", "inherit", "scroll"])
        XCTAssertEqual((stored["scroll"] as? NSDictionary)?["reverse"] as? Bool, false)
    }

    /// Every scroll option is copied (each one set to a value of its own here).
    func testAdoptingTheScrollingSettingsCopiesEveryOption() {
        let global = OPTIONS_SCROLL_DEFAULT()
        global.smooth = false
        global.reverse = false
        global.reverseVertical = false
        global.reverseHorizontal = false
        global.dash = ScrollHotkey(type: .mouse, code: 4)
        global.toggle = nil
        global.block = ScrollHotkey(type: .keyboard, code: KeyCode.controlL)
        global.step = 12
        global.speed = 2.5
        global.duration = ScrollFeel.float.duration
        global.deadZone = 0.5
        global.smoothSimTrackpad = true
        global.smoothVertical = false
        global.smoothHorizontal = false
        let app = Application(path: Self.calculator)
        let own = app.scroll
        XCTAssertTrue(app.adoptScrollOptionsIfUnedited(from: global))
        XCTAssertEqual(app.scroll, global)
        XCTAssertTrue(app.scroll === own, "the same container, new values")
        XCTAssertFalse(app.adoptScrollOptionsIfUnedited(from: OPTIONS_SCROLL_DEFAULT()), "edited now: kept")
        XCTAssertEqual(app.scroll, global)
        // Global settings that are the defaults: nothing to copy.
        XCTAssertFalse(Application(path: Self.textEdit).adoptScrollOptionsIfUnedited(from: OPTIONS_SCROLL_DEFAULT()))
    }

    func testThePageFollowsAdvancedAndTheSettingsEditOnlyTheApp() throws {
        let calculator = application(Self.calculator, inherit: false)
        Options.shared.application.applications = Self.makeStore([calculator])
        let controller = makeController()
        controller.openApplication(withID: Self.calculator)
        let page = try XCTUnwrap(controller.detailController)
        let scrolling = try XCTUnwrap(page.scrollingController)
        XCTAssertTrue(scrolling.parent === page)
        XCTAssertTrue((scrolling.parent as? PreferencesScrollingContainer) === page)

        let closed = controller.view.frame.height
        scrolling.setAdvancedExpanded(true)
        XCTAssertGreaterThan(controller.view.frame.height, closed + 150, "the pane grows with Advanced")
        XCTAssertEqual(controller.view.frame.height, controller.view.fittingSize.height, accuracy: 0.5)
        scrolling.setAdvancedExpanded(false)
        XCTAssertEqual(controller.view.frame.height, closed, accuracy: 0.5)

        scrolling.scrollSpeedSlider.doubleValue = 3
        send(scrolling.scrollSpeedSlider)
        XCTAssertEqual(calculator.scroll.speed, 3)
        XCTAssertEqual(Options.shared.scroll, OPTIONS_SCROLL_DEFAULT(), "the Scrolling pane's settings are untouched")
        send(scrolling.resetToDefaultsButton)
        XCTAssertEqual(calculator.scroll, OPTIONS_SCROLL_DEFAULT())
    }

    func testTheAppsPathIsShownWithATildeAndWithoutTheProgramInside() {
        let home = NSHomeDirectory()
        XCTAssertEqual(ApplicationDetailViewController.displayPath(for: Self.calculatorProgram), Self.calculator)
        XCTAssertEqual(ApplicationDetailViewController.displayPath(for: Self.calculator), Self.calculator)
        XCTAssertEqual(ApplicationDetailViewController.displayPath(for: home + "/Applications/Tool.app"), "~/Applications/Tool.app")
        XCTAssertEqual(
            ApplicationDetailViewController.displayPath(for: "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app/Contents/MacOS/Simulator"),
            "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app"
        )
        XCTAssertEqual(ApplicationDetailViewController.displayPath(for: "/usr/local/bin/tool"), "/usr/local/bin/tool")
    }

    func testALongNameAndPathStayOnOneLineInsideTheBox() throws {
        let path = "/Applications/" + String(repeating: "A Folder With A Long Name/", count: 8) + "An App With A Long Name.app"
        let app = application(path, inherit: true)
        app.displayName = String(repeating: "Long Name ", count: 12)
        let page = ApplicationDetailViewController(application: app, uiStateDefaults: uiDefaults)
        page.view.setFrameSize(page.view.fittingSize)
        page.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(page.view.frame.width, ApplicationDetailViewController.paneWidth, accuracy: 0.5)

        let header = try XCTUnwrap(page.headerRow)
        let row = header.convert(header.bounds, to: page.view)
        let oneLine = NSTextField(labelWithString: "Ag")
        oneLine.font = header.explanationLabel.font
        for label in [header.titleLabel, header.explanationLabel] {
            // The text's edge: the alignment rectangle, not the frame with its padding.
            let text = header.convert(label.alignmentRect(forFrame: label.frame), to: page.view)
            XCTAssertLessThanOrEqual(text.maxX, row.maxX - PreferencesGroupedForm.rowHorizontalInset + 0.5)
        }
        XCTAssertEqual(header.explanationLabel.frame.height, oneLine.fittingSize.height, accuracy: 1, "one line, shortened in the middle")
        XCTAssertEqual(header.toolTip, app.getName() + "\n" + path, "the whole name and path in the tooltip")
        XCTAssertEqual(header.explanationLabel.toolTip, header.toolTip)
    }

    func testInTheWindowThePageKeepsTheTitleAndTheColumnFollowsItsHeight() throws {
        Options.shared.application.applications = Self.makeStore([application(Self.calculator, inherit: false)])
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesSplitViewController.self))
        let windowController = try XCTUnwrap(
            storyboard.instantiateController(withIdentifier: WINDOW_IDENTIFIER.preferencesWindowController) as? PreferencesWindowController
        )
        let window = try XCTUnwrap(windowController.window)
        let preferences = PreferencesSplitViewController(storyboard: storyboard, uiStateDefaults: nil)
        let apps = try XCTUnwrap(preferences.controller(for: PANEL_IDENTIFIER.application) as? PreferencesApplicationViewController)
        apps.uiStateDefaults = uiDefaults
        windowController.contentViewController = preferences
        windowController.configure(window, remembersFrame: false)
        addTeardownBlock { windowController.close() }
        XCTAssertTrue(preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.application))
        window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertEqual(window.title, "Apps")

        apps.openApplication(withID: Self.calculator)
        let page = try XCTUnwrap(apps.detailController)
        XCTAssertEqual(window.title, "Apps")
        XCTAssertTrue(window.firstResponder === page.view, "Esc works straight away")
        let document = preferences.host.documentView!
        XCTAssertGreaterThanOrEqual(document.frame.height, page.view.fittingSize.height - 0.5)
        XCTAssertEqual(apps.view.frame.height, page.view.fittingSize.height, accuracy: 0.5)

        page.backButton.performClick(nil)
        XCTAssertEqual(window.title, "Apps")
        XCTAssertTrue(window.firstResponder === apps.list, "the list has the focus again")
        XCTAssertEqual(apps.view.frame.height, apps.listPage.fittingSize.height, accuracy: 0.5)
    }

    // MARK: - Stored apps

    /// What earlier builds stored loads, shows and works as it did, and looking through the
    /// pane (opening an app's page, going back) writes nothing different.
    func testStoredAppsLoadAndSaveUnchanged() throws {
        let own = Application(path: Self.calculatorProgram)
        own.inherit = false
        own.displayName = ""
        own.scroll.smooth = true
        own.scroll.speed = 2.5
        own.scroll.duration = ScrollFeel.direct.duration
        own.scroll.reverse = false
        own.scroll.dash = nil
        own.scroll.smoothSimTrackpad = true
        let inheriting = Application(path: Self.textEdit)
        inheriting.displayName = "Editor"
        let stored = try JSONEncoder().encode([own, inheriting])
        let storedObject = try JSONSerialization.jsonObject(with: stored) as? NSArray
        let first = try XCTUnwrap(storedObject?.firstObject as? NSDictionary)
        XCTAssertEqual(Set(first.allKeys.compactMap { $0 as? String }), ["path", "displayName", "inherit", "scroll"],
                       "the stored keys of an app are unchanged")

        Options.shared.application.applications = try EnhanceArray<Application>(
            withData: stored, matchKey: "path", forObserver: { Options.shared.markChanged(.application) }
        )
        let controller = makeController()
        XCTAssertEqual(controller.list.rows.map(\.title), ["Calculator", "Editor"])
        XCTAssertEqual(controller.list.rows.map(\.explanation), ["Uses its own scrolling settings", "Uses your scrolling settings"])

        controller.openApplication(withID: Self.calculatorProgram)
        let scrolling = try XCTUnwrap(controller.detailController?.scrollingController)
        XCTAssertEqual(scrolling.scrollSpeedSlider.doubleValue, 2.5, accuracy: 1e-9)
        XCTAssertEqual(scrolling.feelControl.selectedSegment, ScrollFeel.direct.rawValue)
        XCTAssertEqual(scrolling.reverseSwitch.state, .off)
        XCTAssertEqual(scrolling.trackpadEventsSwitch.state, .on)
        XCTAssertEqual(controller.detailController?.headerRow.explanation, Self.calculator)
        controller.showList(focusList: false)
        controller.openApplication(withID: Self.textEdit)
        controller.viewDidDisappear()
        controller.viewWillAppear()

        let saved = try XCTUnwrap(Options.shared.application.applications.json())
        XCTAssertEqual(
            try JSONSerialization.jsonObject(with: saved) as? NSArray,
            storedObject,
            "nothing stored changed"
        )
        // The scroll engine finds both, by the program and by the bundle.
        let loaded = try EnhanceArray<Application>(withData: saved, matchKey: "path")
        XCTAssertNotNil(loaded.get(by: Self.calculatorProgram))
        XCTAssertNotNil(loaded.get(by: Self.textEdit))
    }
}
