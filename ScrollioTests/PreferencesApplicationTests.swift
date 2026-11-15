//
//  PreferencesApplicationTests.swift
//  MosTests
//
//  The Apps pane: the truthful allowlist switch and its line while the list is empty, the
//  list of apps (rows, "+" menu of running apps, Choose in Finder, the new app's page
//  opened at once, duplicates, remove with undo, also from another pane and after the app
//  was added again), an app's page opened in place of the list and back again, "Use
//  settings from Scrolling" dimming the settings and, switched off, starting from them,
//  the page's "Shortcut Ring" section (the general ring, or the app's own with its eight
//  rows), and the stored apps loading and saving unchanged. Nothing is shown on screen: the menu,
//  the open panel and the running apps go through seams, windows are never ordered in.
//

import XCTest
@testable import Scrollio_Debug

final class PreferencesApplicationTests: XCTestCase {

    private var originalApplications: EnhanceArray<Application>!
    private var originalAllowlist = false
    private var originalScroll: OPTIONS_SCROLL_DEFAULT!
    private var uiDefaults: UserDefaults!

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
        uiDefaults = TestDefaults.make(for: self)
        uiDefaults.set(false, forKey: PreferencesScrollingViewController.advancedExpandedDefaultsKey)
    }

    override func tearDown() {
        Options.shared.application.applications = originalApplications
        Options.shared.application.allowlist = originalAllowlist
        Options.shared.scroll = originalScroll
        originalApplications = nil
        originalScroll = nil
        uiDefaults = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// The catalog's text for `key`, with `arguments` put in as the app puts them: the
    /// expected text follows the catalog's wording.
    private static func catalog(_ key: String, _ arguments: String...) -> String {
        return String(format: NSLocalizedString(key, comment: ""), arguments: arguments)
    }

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

    /// Picks `choice` in "Scrolling in …", as a click on its item does.
    private func pick(_ choice: ApplicationScrollingChoice, on page: ApplicationDetailViewController,
                      file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(page.scrollingChoicePopUp.selectItem(withTag: choice.rawValue), file: file, line: line)
        send(page.scrollingChoicePopUp, file: file, line: line)
    }

    private func shownChoice(of page: ApplicationDetailViewController) -> ApplicationScrollingChoice? {
        return ApplicationScrollingChoice(rawValue: page.scrollingChoicePopUp.selectedTag())
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
        XCTAssertEqual(controller.allowlistRow.title, "Change scrolling only in these apps")
        XCTAssertEqual(
            controller.allowlistRow.explanation,
            Self.catalog("apps-limit-hint")
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
        XCTAssertEqual(controller.list.emptyRow.title, "Click + to give an app its own scrolling, buttons, gestures or Shortcut Ring.")
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
        XCTAssertEqual(rows.map(\.explanation), ["Own: scrolling", "Nothing of its own yet", "Nothing of its own yet"])
        for row in rows {
            let icon = try XCTUnwrap(row.iconView, row.title)
            XCTAssertNotNil(icon.image, row.title)
            XCTAssertEqual(icon.image?.isTemplate, false, "an app's own icon, not a symbol")
            XCTAssertNotNil(row.chevronView, "\(row.title) opens a page of its own")
        }
        XCTAssertEqual(rows[0].accessibilityLabel(), "Calculator, Own: scrolling, Own scrolling settings",
                       "then what its marks say")
        XCTAssertEqual(rows[1].toolTip, "TextEdit\nNothing of its own yet\n" + Self.textEdit, "the name, the line, then the app")
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
        XCTAssertEqual(shownChoice(of: page), .sameAsScrolling)

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

    // MARK: - "Settings for Safari…" of the menu bar

    private static let calculatorApp = AppSmoothing.App(name: "Calculator", bundlePath: calculator, executablePath: calculatorProgram)
    private static let textEditApp = AppSmoothing.App(name: "TextEdit", bundlePath: textEdit, executablePath: textEditProgram)

    /// An app on the list: its page, on the part shown last; nothing is added. Found by its
    /// bundle or by its program, as "Smooth Scrolling in …" finds it.
    func testSettingsForAListedAppOpensItsPageOnThePartShownLast() throws {
        let calculator = application(Self.calculator, inherit: true)
        let textEdit = application(Self.textEditProgram, inherit: true)
        Options.shared.application.applications = Self.makeStore([textEdit, calculator])
        ApplicationPagePart.buttons.remember(in: uiDefaults)
        let controller = makeController()
        let window = makeWindow(for: controller)

        controller.showSettings(for: Self.calculatorApp)
        let page = try XCTUnwrap(controller.detailController)
        XCTAssertTrue(page.application === calculator)
        XCTAssertEqual(page.shownPart, .buttons, "the part shown last")
        XCTAssertTrue(window.firstResponder === page.view)
        XCTAssertNil(controller.offeredApplication)

        // Another listed app, by its program: its page instead, on the same part.
        page.show(.ring)
        controller.showSettings(for: Self.textEditApp)
        XCTAssertTrue(controller.detailController?.application === textEdit)
        XCTAssertEqual(controller.detailController?.shownPart, .ring)
        // The page that is open stays as it is.
        let open = try XCTUnwrap(controller.detailController)
        controller.showSettings(for: Self.textEditApp)
        XCTAssertTrue(controller.detailController === open)
        XCTAssertEqual(storedPaths(), [Self.textEditProgram, Self.calculator], "nothing added")
    }

    /// An app that is not on the list: the list with one line at its top that offers to add
    /// it; only its button adds it (one entry, by its program's path as "+" stores a running
    /// app), and its page opens.
    func testSettingsForAnAppNotOnTheListOffersALineThatAddsIt() throws {
        Options.shared.application.applications = Self.makeStore([application(Self.calculator, inherit: true)])
        let controller = makeController()
        _ = makeWindow(for: controller)
        controller.openApplication(withID: Self.calculator)

        controller.showSettings(for: Self.textEditApp)
        XCTAssertNil(controller.detailController, "back to the list")
        XCTAssertTrue(controller.currentPage === controller.listPage)
        XCTAssertEqual(storedPaths(), [Self.calculator], "the menu bar adds nothing")
        XCTAssertEqual(controller.list.rows.map { $0.id as? String }, [PreferencesApplicationViewController.offerRowID, Self.calculator])
        let line = try XCTUnwrap(controller.list.rows.first)
        XCTAssertEqual(line.title, "TextEdit isn't on the list.")
        XCTAssertEqual(line.title, Self.catalog("apps-not-on-list", "TextEdit"))
        XCTAssertNotNil(line.iconView?.image)
        XCTAssertNil(line.chevronView, "nothing to open")
        XCTAssertNil(controller.list.selectedID)
        let add = try XCTUnwrap(line.accessory as? NSButton)
        XCTAssertEqual(add.title, "Add TextEdit")
        XCTAssertEqual(add.identifier, PreferencesApplicationViewController.Identifier.offerAdd)
        XCTAssertEqual(controller.view.frame.height, controller.listPage.fittingSize.height, accuracy: 0.5)

        // Neither Return, a double click nor − does anything with the line.
        controller.list.select(PreferencesApplicationViewController.offerRowID)
        XCTAssertFalse(controller.list.removeButton.isEnabled)
        controller.list.keyDown(with: try key("\r", keyCode: 36))
        controller.removeApplication(withID: PreferencesApplicationViewController.offerRowID)
        XCTAssertNil(controller.detailController)
        XCTAssertEqual(storedPaths(), [Self.calculator])

        // The button adds it once and opens its page.
        add.performClick(nil)
        XCTAssertEqual(storedPaths(), [Self.calculator, Self.textEditProgram])
        let added = try XCTUnwrap(Options.shared.application.applications.get(by: Self.textEditProgram))
        XCTAssertTrue(added.inherit, "nothing of its own, as after \"+\"")
        XCTAssertTrue(controller.detailController?.application === added)
        XCTAssertNil(controller.offeredApplication)
        controller.showList(focusList: false)
        XCTAssertEqual(controller.list.rows.map { $0.id as? String }, [Self.calculator, Self.textEditProgram], "the line is gone")
        controller.addOfferedApplication(add)
        XCTAssertEqual(storedPaths(), [Self.calculator, Self.textEditProgram], "never a second entry")
    }

    /// One line at a time; it goes when the pane is left or when the app gets on the list
    /// another way (the menu bar's "Smooth Scrolling in …", seen when the window becomes key
    /// again; "+"), and its button then adds nothing more.
    func testTheLineIsOneAndGoesWithItsReason() throws {
        let controller = makeController(running: [candidate(Self.textEdit, program: Self.textEditProgram, name: "TextEdit")])
        let window = makeWindow(for: controller)
        controller.showSettings(for: Self.calculatorApp)
        controller.showSettings(for: Self.textEditApp)
        XCTAssertEqual(controller.list.rows.map(\.title), ["TextEdit isn't on the list."], "the empty list's line makes way")

        controller.viewDidDisappear()
        XCTAssertNil(controller.offeredApplication)
        XCTAssertTrue(controller.list.rows.isEmpty)
        XCTAssertEqual(controller.list.emptyRow.title, text("apps-empty"))

        controller.showSettings(for: Self.textEditApp)
        let add = try XCTUnwrap(controller.list.rows.first?.accessory as? NSButton)
        AppSmoothing.addWithSmoothingOff(path: Self.textEditProgram, list: Options.shared.application, scrolling: Options.shared.scroll)
        // Another window becoming key changes nothing here; this pane's window does.
        let other = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: true)
        other.isReleasedWhenClosed = false
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: other)
        XCTAssertNotNil(controller.offeredApplication)
        XCTAssertEqual(controller.list.rows.map { $0.id as? String }, [PreferencesApplicationViewController.offerRowID])
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        XCTAssertNil(controller.offeredApplication)
        XCTAssertEqual(controller.list.rows.map { $0.id as? String }, [Self.textEditProgram])
        controller.addOfferedApplication(add)
        XCTAssertEqual(storedPaths(), [Self.textEditProgram])

        // Added by "+" while the line shows: the line goes with the reload.
        Options.shared.application.applications = Self.makeStore()
        controller.showSettings(for: Self.textEditApp)
        controller.addRunningApplication(try XCTUnwrap(controller.makeAddMenu().items.first))
        controller.showList(focusList: false)
        XCTAssertEqual(controller.list.rows.map { $0.id as? String }, [Self.textEditProgram])
        XCTAssertNil(controller.offeredApplication)

        // A later ask for an app on the list takes the line away too.
        Options.shared.application.applications = Self.makeStore([application(Self.calculator, inherit: true)])
        controller.showSettings(for: Self.textEditApp)
        XCTAssertNotNil(controller.offeredApplication)
        controller.showSettings(for: Self.calculatorApp)
        controller.showList(focusList: false)
        XCTAssertNil(controller.offeredApplication)
        XCTAssertEqual(controller.list.rows.map { $0.id as? String }, [Self.calculator])
    }

    /// A name too long for the line and its button side by side is read once: the button
    /// says "Add" and the line has the room it frees, with the name whole when it fits
    /// there, else cut short at its end; whole in the tooltips and for VoiceOver. A short
    /// name stays whole in both.
    func testALongNameIsReadOnceAndItsButtonSaysAdd() throws {
        let long = AppSmoothing.App(
            name: "Microsoft Visual Studio Code Insiders Edition With A Very Long Name",
            bundlePath: "/Applications/Long Test.app", executablePath: "/Applications/Long Test.app/Contents/MacOS/Long"
        )
        let controller = makeController()
        _ = makeWindow(for: controller)
        controller.showSettings(for: long)
        controller.view.layoutSubtreeIfNeeded()
        let line = try XCTUnwrap(controller.list.rows.first)
        let add = try XCTUnwrap(line.accessory as? NSButton)
        let cut = PreferencesApplicationViewController.offerName(long.name)
        XCTAssertTrue(cut.hasSuffix("…"))
        XCTAssertTrue(long.name.hasPrefix(String(cut.dropLast())))
        XCTAssertEqual(line.title, cut + " isn't on the list.")
        XCTAssertEqual(add.title, "Add", "the name is read once, in the line")
        XCTAssertEqual(add.title, Self.catalog("apps-open-panel-prompt"))
        XCTAssertLessThanOrEqual(line.titleLabel.intrinsicContentSize.width, line.titleLabel.frame.width + 0.5, "not cut again")
        XCTAssertLessThanOrEqual(add.intrinsicContentSize.width, add.frame.width + 0.5, "not cut again")
        XCTAssertLessThanOrEqual(line.titleLabel.frame.maxX, add.frame.minX)
        XCTAssertLessThanOrEqual(add.frame.maxX, line.bounds.maxX)
        XCTAssertGreaterThan(line.titleLabel.frame.width, PreferencesApplicationViewController.boxWidth / 2, "the room the button frees")
        XCTAssertEqual(line.toolTip, long.name + " isn't on the list.", "whole in the tooltip")
        XCTAssertEqual(add.toolTip, "Add " + long.name)
        XCTAssertEqual(add.accessibilityLabel(), "Add " + long.name)

        // Too long for "Add Adobe Illustrator 2026" beside the line, short enough for "Add".
        let adobe = AppSmoothing.App(
            name: "Adobe Illustrator 2026",
            bundlePath: "/Applications/Adobe Test.app", executablePath: "/Applications/Adobe Test.app/Contents/MacOS/Adobe"
        )
        controller.showSettings(for: adobe)
        controller.view.layoutSubtreeIfNeeded()
        let whole = try XCTUnwrap(controller.list.rows.first)
        XCTAssertEqual(whole.title, "Adobe Illustrator 2026 isn't on the list.", "whole")
        XCTAssertLessThanOrEqual(whole.titleLabel.intrinsicContentSize.width, whole.titleLabel.frame.width + 0.5, "not cut")
        let adobeAdd = try XCTUnwrap(whole.accessory as? NSButton)
        XCTAssertEqual(adobeAdd.title, "Add")
        XCTAssertEqual(adobeAdd.toolTip, "Add Adobe Illustrator 2026")
        XCTAssertEqual(adobeAdd.accessibilityLabel(), "Add Adobe Illustrator 2026")

        let safari = PreferencesApplicationViewController.offerTitles("Safari")
        XCTAssertEqual([safari.name, safari.button], ["Safari", "Add Safari"])
        let code = PreferencesApplicationViewController.offerTitles("Visual Studio Code")
        XCTAssertEqual([code.name, code.button], ["Visual Studio Code", "Add Visual Studio Code"])
    }

    /// From the menu bar: the window on Apps, whichever pane it showed, with the app's page
    /// (its name in the title bar) or the line.
    func testTheMenuBarsItemSelectsAppsInTheWindow() throws {
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
        XCTAssertTrue(preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.scrolling))

        PreferencesApplicationViewController.showSettings(for: Self.calculatorApp, in: preferences)
        XCTAssertEqual(preferences.selectedPaneIdentifier, PANEL_IDENTIFIER.application)
        XCTAssertEqual(apps.detailController?.application.path, Self.calculator)
        XCTAssertEqual(window.title, "Calculator")
        XCTAssertTrue(preferences.canGoBack)

        PreferencesApplicationViewController.showSettings(for: Self.textEditApp, in: preferences)
        XCTAssertNil(apps.detailController)
        XCTAssertEqual(window.title, "Apps")
        XCTAssertFalse(preferences.canGoBack)
        XCTAssertEqual(apps.list.rows.first?.title, "TextEdit isn't on the list.")
        XCTAssertEqual(storedPaths(), [Self.calculator])
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
        XCTAssertEqual(controller.list.rows.last?.explanation, "Own: scrolling")
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
        XCTAssertEqual(controller.title, "Apps", "the pane keeps its name")
        XCTAssertEqual(controller.subpageTitle, "Calculator", "the window is named after the app while its page shows")
        // The header: the app's icon, name and what it has of its own (where it is in the
        // tooltip); then its Scrolling settings.
        XCTAssertEqual(page.headerRow.title, "Calculator")
        XCTAssertEqual(page.headerRow.explanation, "Own: scrolling")
        XCTAssertEqual(page.headerRow.toolTip, "Calculator\nOwn: scrolling\n" + Self.calculator)
        XCTAssertEqual(page.headerRow.iconView.frame.size, NSSize(width: 32, height: 32))
        XCTAssertNotNil(page.headerRow.iconView.image)
        // No link back on the page any more (the window's title bar has the back button):
        // no button but "Show in Finder" and the settings' own, and the app's box begins
        // where the first box of every pane does.
        XCTAssertFalse(allSubviews(of: page.view).contains { ($0 as? NSButton)?.title == "Apps" })
        XCTAssertFalse(allSubviews(of: page.view).contains { $0.identifier?.rawValue == "apps-detail-back" })
        XCTAssertTrue(allSubviews(of: page.view).compactMap { $0 as? NSButton }.allSatisfy {
            $0.isDescendant(of: page.scrollingController.view) || $0 === page.scrollingChoicePopUp || $0.title == "Show in Finder"
        })
        XCTAssertEqual(page.view.frame.height - page.headerSection.frame.maxY, PreferencesGroupedForm.margin, accuracy: 0.5)
        XCTAssertEqual(page.headerSection.frame.minX, PreferencesGroupedForm.margin, accuracy: 0.5)
        XCTAssertTrue(page.scrollingController.currentTargetApplication === calculator)
        XCTAssertTrue(page.scrollingController.previewView.isHidden)
        XCTAssertEqual(page.scrollingController.scrollSpeedSlider.doubleValue, 4.2, accuracy: 1e-9)
        // The pane takes the page's height.
        XCTAssertEqual(controller.view.frame.height, page.view.fittingSize.height, accuracy: 0.5)
        XCTAssertGreaterThan(controller.view.frame.height, listHeight)
        // No rename any more.
        XCTAssertFalse(allSubviews(of: page.view).contains { ($0 as? NSTextField)?.isEditable == true })

        controller.leaveSubpage()
        XCTAssertNil(controller.detailController)
        XCTAssertNil(controller.subpageTitle)
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

    func testSameAsScrollingHidesTheSettingsAndUpdatesTheList() throws {
        Options.shared.scroll.speed = 8.5
        let calculator = application(Self.calculator, inherit: false)
        calculator.scroll.speed = 1.5
        Options.shared.application.applications = Self.makeStore([calculator])
        let controller = makeController()
        controller.openApplication(withID: Self.calculator)
        let page = try XCTUnwrap(controller.detailController)
        let scrolling = try XCTUnwrap(page.scrollingController)

        XCTAssertEqual(page.scrollingChoiceRow.title, "Scrolling in Calculator")
        XCTAssertEqual(shownChoice(of: page), .ownSettings)
        XCTAssertEqual(page.scrollingChoicePopUp.titleOfSelectedItem, "Own Settings")
        XCTAssertEqual(page.scrollingChoiceRow.explanation, "Calculator keeps its own settings below.")
        XCTAssertTrue(scrolling.smoothRow.isEnabled)
        XCTAssertTrue(scrolling.speedRow.isEnabled)
        XCTAssertEqual(scrolling.scrollSpeedSlider.doubleValue, 1.5, accuracy: 1e-9)
        XCTAssertTrue(scrolling.view.isDescendant(of: page.view))
        let height = page.view.fittingSize.height
        let switchHeight = page.scrollingChoiceRow.fittingSize.height

        pick(.sameAsScrolling, on: page)
        XCTAssertTrue(calculator.inherit)
        XCTAssertEqual(page.scrollingChoiceRow.explanation, "Changes under Scrolling apply to Calculator too.")
        XCTAssertFalse(scrolling.view.isDescendant(of: page.view), "out of sight while the app uses the Scrolling settings")
        XCTAssertFalse(scrolling.resetToDefaultsButton.isDescendant(of: page.view))
        XCTAssertEqual(calculator.scroll.speed, 1.5, "its own value is kept for later")
        XCTAssertEqual(controller.list.rows.first?.explanation, "Nothing of its own yet")
        XCTAssertEqual(page.scrollingChoiceRow.fittingSize.height, switchHeight, accuracy: 0.5, "the other line takes the same room")
        XCTAssertLessThan(page.view.fittingSize.height, height - 300, "the page is the switch's box under the app's")
        XCTAssertEqual(controller.view.frame.height, page.view.fittingSize.height, accuracy: 0.5, "the pane follows")

        pick(.ownSettings, on: page)
        XCTAssertFalse(calculator.inherit)
        XCTAssertTrue(scrolling.view.isDescendant(of: page.view))
        XCTAssertTrue(scrolling.smoothRow.isEnabled)
        XCTAssertTrue(scrolling.speedRow.isEnabled)
        XCTAssertEqual(scrolling.scrollSpeedSlider.doubleValue, 1.5, accuracy: 1e-9)
        XCTAssertEqual(page.view.fittingSize.height, height, accuracy: 0.5)
        XCTAssertEqual(controller.view.frame.height, height, accuracy: 0.5)
        XCTAssertEqual(controller.list.rows.first?.explanation, "Own: scrolling")
    }

    /// A new app's own options are those of a new installation: taken as they were, Reverse
    /// would come back on and Speed and the keys go to the factory values. Never edited,
    /// Own Settings starts from a copy of the Scrolling settings; edited ones are kept.
    func testOwnSettingsStartsFromTheScrollingSettings() throws {
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
        pick(.ownSettings, on: page)
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
        // Same as Scrolling and Own Settings again: its own options are edited now, so they stay.
        pick(.sameAsScrolling, on: page)
        pick(.ownSettings, on: page)
        XCTAssertEqual(fresh.scroll.speed, 3)

        // Edited earlier: kept, Reverse and all.
        controller.showList(focusList: false)
        controller.openApplication(withID: Self.textEdit)
        page = try XCTUnwrap(controller.detailController)
        pick(.ownSettings, on: page)
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

    /// On a Mac with Natural scrolling off a new entry starts with that Mac's defaults
    /// (Reverse wheel direction off) and counts as unedited; an app whose own direction was
    /// turned on keeps it through "Use settings from Scrolling" on and off, although its
    /// options are then the plain defaults. Regression: they were taken for unedited and
    /// the Scrolling settings' direction was copied over them without a word.
    func testAnAppsOwnDirectionStaysOnAMacWithoutNaturalScrolling() {
        let originalNaturalScrolling = Options.naturalScrollingIsOn
        defer { Options.naturalScrollingIsOn = originalNaturalScrolling }
        Options.naturalScrollingIsOn = { false }
        // The Scrolling settings of a new installation on that Mac.
        let scrolling = OPTIONS_SCROLL_DEFAULT(reverse: false)

        let app = Application(path: Self.calculator)
        XCTAssertEqual(app.scroll, scrolling, "a new entry: this Mac's defaults")
        app.setUsesScrollingSettings(false, scrolling: scrolling)
        XCTAssertFalse(app.scroll.reversesWheel)
        app.scroll.reversesWheel = true
        XCTAssertEqual(app.scroll, OPTIONS_SCROLL_DEFAULT())
        app.setUsesScrollingSettings(true, scrolling: scrolling)
        app.setUsesScrollingSettings(false, scrolling: scrolling)
        XCTAssertTrue(app.scroll.reversesWheel, "the app's own direction")

        // A new entry is unedited: it takes the Scrolling settings.
        scrolling.speed = 8.5
        let fresh = Application(path: Self.textEdit)
        XCTAssertTrue(fresh.adoptScrollOptionsIfUnedited(from: scrolling))
        XCTAssertEqual(fresh.scroll, scrolling)
        XCTAssertFalse(fresh.scroll.reversesWheel)
    }

    /// An entry exactly as 1.0.5 stored it after "+": its own options are that version's
    /// values of a new entry, "reverse" true on every Mac. `speed` is the one value that
    /// differed between releases (6.3 in 1.0.0 and 1.0.1).
    private static func entryStoredByAnOlderVersion(speed: String = "6.5", reverse: Bool = true) throws -> Application {
        let stored = #"{"path":"/System/Applications/Calculator.app/Contents/MacOS/Calculator","displayName":"","inherit":true,"scroll":{"smooth":true,"reverse":\#(reverse),"reverseVertical":true,"reverseHorizontal":true,"dash":{"type":"keyboard","code":58},"toggle":{"type":"keyboard","code":56},"block":{"type":"keyboard","code":55},"step":33.6,"speed":\#(speed),"duration":3.69,"deadZone":1,"smoothSimTrackpad":false,"smoothVertical":true,"smoothHorizontal":true}}"#
        return try JSONDecoder().decode(Application.self, from: Data(stored.utf8))
    }

    /// An app added under 1.0.5 that always followed Scrolling was never edited, also on a
    /// Mac with Natural scrolling off: "Smooth Scrolling in …" of the menu bar and Own
    /// Settings start from the Scrolling settings. Regression: "never edited" compared with
    /// this Mac's new-entry values (Reverse off there), the stored "reverse": true read as
    /// an edit, nothing was copied and the wheel turned round in that app alone.
    func testAnAppAddedByAnOlderVersionIsStillNeverEditedWithoutNaturalScrolling() throws {
        let originalNaturalScrolling = Options.naturalScrollingIsOn
        defer { Options.naturalScrollingIsOn = originalNaturalScrolling }
        Options.naturalScrollingIsOn = { false }
        // The user's Scrolling settings there: the wheel as macOS turns it, a speed of his own.
        let scrolling = OPTIONS_SCROLL_DEFAULT(reverse: false)
        scrolling.speed = 3
        let calculator = AppSmoothing.App(
            name: "Calculator", bundlePath: Self.calculator, executablePath: Self.calculatorProgram
        )

        // The menu bar's item, for 1.0.5's entry and for one of 1.0.0 / 1.0.1 (Speed 6.3).
        for speed in ["6.5", "6.3"] {
            let entry = try Self.entryStoredByAnOlderVersion(speed: speed)
            XCTAssertTrue(entry.scroll.reversesWheel, "as that version stored it")
            let list = OPTIONS_APPLICATION_DEFAULT()
            list.applications = Self.makeStore([entry])
            XCTAssertEqual(
                AppSmoothing.toggle(calculator, list: list, scrolling: scrolling), .ownSettingsWithSmoothingOff, speed
            )
            XCTAssertFalse(entry.scroll.reversesWheel, "the wheel turns as it did (\(speed))")
            XCTAssertEqual(entry.scroll.speed, 3, speed)
            XCTAssertEqual(entry.scrollingChoice, .leftToMacOS, speed)
        }

        // The page's Own Settings: a copy of the Scrolling settings.
        let entry = try Self.entryStoredByAnOlderVersion()
        entry.choose(.ownSettings, from: .sameAsScrolling, scrolling: scrolling)
        XCTAssertEqual(entry.scroll, scrolling)
        XCTAssertFalse(entry.scroll === scrolling)

        // An entry made here before Natural scrolling was switched on in System Settings.
        let earlier = Application(path: Self.textEdit)
        XCTAssertFalse(earlier.scroll.reversesWheel)
        Options.naturalScrollingIsOn = { true }
        XCTAssertTrue(earlier.adoptScrollOptionsIfUnedited(from: scrolling))
        XCTAssertEqual(earlier.scroll, scrolling)

        // Values of its own stay: an older entry that was edited, and one this version
        // gave its own settings (it has thumb wheel values by then), whatever they equal.
        let edited = try Self.entryStoredByAnOlderVersion(speed: "2")
        XCTAssertFalse(edited.adoptScrollOptionsIfUnedited(from: scrolling))
        XCTAssertEqual(edited.scroll.speed, 2)
        XCTAssertTrue(edited.scroll.reversesWheel)
        Options.naturalScrollingIsOn = { false }
        let own = try Self.entryStoredByAnOlderVersion()
        own.setUsesScrollingSettings(false, scrolling: scrolling)
        own.scroll.reversesWheel = true
        own.scroll.speed = 6.5
        own.setUsesScrollingSettings(true, scrolling: scrolling)
        own.setUsesScrollingSettings(false, scrolling: scrolling)
        XCTAssertTrue(own.scroll.reversesWheel, "the app's own direction")
        XCTAssertEqual(own.scroll.speed, 6.5)
    }

    func testThePageFollowsAdvancedAndTheSettingsEditOnlyTheApp() throws {
        let calculator = application(Self.calculator, inherit: false)
        Options.shared.application.applications = Self.makeStore([calculator])
        let controller = makeController()
        controller.openApplication(withID: Self.calculator)
        let page = try XCTUnwrap(controller.detailController)
        let scrolling = try XCTUnwrap(page.scrollingController)
        XCTAssertTrue(scrolling.parent === page.scrollingPart, "in the page's Scrolling part")
        XCTAssertTrue((scrolling.parent as? PreferencesScrollingContainer) === page.scrollingPart)

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
        XCTAssertEqual(header.explanationLabel.frame.height, oneLine.fittingSize.height, accuracy: 1, "one line, shortened at its end")
        XCTAssertEqual(header.toolTip, app.getName() + "\nNothing of its own yet\n" + path, "the whole name and path in the tooltip")
        XCTAssertEqual(header.explanationLabel.toolTip, header.toolTip)
    }

    /// In the window an app's page is a page of its own, as in System Settings: the title
    /// bar names the app and has a back button before the name, in the pane's part of the
    /// toolbar (after the sidebar's separator). The button is the system's: a navigational
    /// toolbar item with the back chevron in the standard bordered button. It is there
    /// only while an app's page shows, and pressing it shows the list.
    func testInTheWindowAnAppsPageHasTheTitleBarsBackButtonAndTheAppsName() throws {
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
        let toolbar = try XCTUnwrap(window.toolbar)
        let back = PreferencesWindowController.backItemIdentifier
        func items() -> [NSToolbarItem.Identifier] { return toolbar.items.map(\.itemIdentifier) }

        // The list of apps: the toolbar as it was, the pane's name. (Every other pane:
        // PreferencesWindowTests.testEveryPaneSitsAtTheTopOfTheColumnCentred.)
        XCTAssertEqual(items(), [.sidebarTrackingSeparator])
        XCTAssertTrue(preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.application))
        XCTAssertFalse(preferences.canGoBack)
        window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertEqual(window.title, "Apps")
        XCTAssertEqual(items(), [.sidebarTrackingSeparator])

        // An app's page: its name, and the back button after the separator.
        apps.openApplication(withID: Self.calculator)
        let page = try XCTUnwrap(apps.detailController)
        XCTAssertEqual(window.title, "Calculator")
        XCTAssertEqual(items(), [.sidebarTrackingSeparator, back])
        XCTAssertTrue(preferences.canGoBack)
        let item = try XCTUnwrap(toolbar.items.last)
        XCTAssertTrue(item.isNavigational, "the system places it before the title")
        XCTAssertTrue(item.isBordered, "the standard toolbar button")
        XCTAssertNil(item.view, "nothing drawn by the app")
        XCTAssertNotNil(item.image)
        XCTAssertEqual(item.image?.accessibilityDescription, "Back")
        XCTAssertEqual(item.label, "Back", "what VoiceOver calls it")
        XCTAssertEqual(item.toolTip, "Back")
        XCTAssertEqual(toolbar.items.filter { $0.isNavigational }.count, 1, "no forward button")
        XCTAssertTrue(window.firstResponder === page.view, "Esc works straight away")
        let document = preferences.host.documentView!
        XCTAssertGreaterThanOrEqual(document.frame.height, page.view.fittingSize.height - 0.5)
        XCTAssertEqual(apps.view.frame.height, page.view.fittingSize.height, accuracy: 0.5)
        // Opening it twice makes no second button.
        windowController.syncBackItem()
        XCTAssertEqual(items(), [.sidebarTrackingSeparator, back])
        // Where the system puts it, in the title bar as it is laid out here (never shown):
        // in the pane's part, right of the sidebar, and before the app's name.
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        let titleBar = try XCTUnwrap(window.contentView?.superview)
        titleBar.layoutSubtreeIfNeeded()
        let chrome = titleBar.subviews.filter { $0 !== window.contentView }.flatMap { [$0] + allSubviews(of: $0) }
        let button = try XCTUnwrap(chrome.compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == "Back" }, "the system's button for the item")
        let name = try XCTUnwrap(chrome.compactMap { $0 as? NSTextField }.first { $0.stringValue == "Calculator" }, "the title")
        let buttonFrame = button.convert(button.bounds, to: nil)
        XCTAssertTrue(button.isBordered)
        XCTAssertGreaterThanOrEqual(buttonFrame.minX, preferences.sidebar.view.frame.width, "right of the sidebar")
        XCTAssertLessThanOrEqual(buttonFrame.maxX, name.convert(name.bounds, to: nil).minX + 0.5, "before the name")

        // Pressed: the list, "Apps", and no button.
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item))
        XCTAssertNil(apps.detailController)
        XCTAssertEqual(window.title, "Apps")
        XCTAssertEqual(items(), [.sidebarTrackingSeparator])
        XCTAssertTrue(window.firstResponder === apps.list, "the list has the focus again")
        XCTAssertEqual(apps.view.frame.height, apps.listPage.fittingSize.height, accuracy: 0.5)

        // ⌘[ and Esc leave the same way.
        apps.openApplication(withID: Self.calculator)
        XCTAssertEqual(items(), [.sidebarTrackingSeparator, back])
        XCTAssertTrue(try XCTUnwrap(apps.detailController).view.performKeyEquivalent(with: try key("[", keyCode: 33, modifiers: .command)))
        XCTAssertEqual(items(), [.sidebarTrackingSeparator])
        XCTAssertEqual(window.title, "Apps")

        // The sidebar leaves an app's page: the button goes with it, the title is the pane's.
        apps.openApplication(withID: Self.calculator)
        XCTAssertEqual(items(), [.sidebarTrackingSeparator, back])
        XCTAssertTrue(preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.scrolling))
        XCTAssertEqual(items(), [.sidebarTrackingSeparator])
        XCTAssertEqual(window.title, "Scrolling")
        XCTAssertFalse(preferences.canGoBack)
        // (In a window on screen the pane hears that it went away; here it is told.)
        apps.viewDidDisappear()
        XCTAssertTrue(preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.application))
        XCTAssertEqual(window.title, "Apps")
        XCTAssertEqual(items(), [.sidebarTrackingSeparator])
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
        XCTAssertEqual(controller.list.rows.map(\.explanation), ["Own: scrolling", "Nothing of its own yet"])

        controller.openApplication(withID: Self.calculatorProgram)
        let scrolling = try XCTUnwrap(controller.detailController?.scrollingController)
        XCTAssertEqual(scrolling.scrollSpeedSlider.doubleValue, 2.5, accuracy: 1e-9)
        XCTAssertEqual(scrolling.feelControl.selectedSegment, ScrollFeel.direct.rawValue)
        XCTAssertEqual(scrolling.reverseSwitch.state, .off)
        XCTAssertEqual(scrolling.trackpadEventsSwitch.state, .on)
        XCTAssertEqual(controller.detailController?.headerRow.explanation, "Own: scrolling")
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

    // MARK: - An app's own Shortcut Ring

    /// The general ring for a test of the page's section, and whether a button opens it
    /// (the part's line says what opens), put back afterwards.
    private func setGeneralRing(_ ring: ShortcutRingSettings, opensWithAButton: Bool = true) {
        let saved = Options.shared.ring
        let savedBindings = Options.shared.buttons.binding
        addTeardownBlock {
            Options.shared.ring = saved
            Options.shared.buttons.binding = savedBindings
            ButtonUtils.shared.invalidateCache()
            ShortcutRingController.forgetPreparedFaces()
        }
        Options.shared.ring = ring
        let trigger = RecordedEvent(type: .mouse, code: 4, modifiers: 0, deviceFilter: nil)
        Options.shared.buttons.binding = opensWithAButton
            ? [ButtonBinding(triggerEvent: trigger, systemShortcutName: SystemShortcut.shortcutRing.identifier, isEnabled: true)]
            : []
        ButtonUtils.shared.invalidateCache()
    }

    /// Without a button or key that opens the ring, the first row says so in both
    /// positions of the switch, with "Set Up…" beside it.
    func testTheRingPartSaysWhenNothingOpensTheRing() throws {
        setGeneralRing(.default, opensWithAButton: false)
        Options.shared.application.applications = Self.makeStore([application(Self.calculator, inherit: true)])
        let controller = makeController()
        controller.openApplication(withID: Self.calculator, part: .ring)
        let page = try XCTUnwrap(controller.detailController)
        XCTAssertEqual(page.ringPart.triggerRow.explanation, "None in Calculator")
        XCTAssertEqual(page.ringPart.triggerButton.title, "Set Up…")
        page.generalRingSwitch.state = .off
        send(page.generalRingSwitch)
        XCTAssertNotNil(page.ringController)
        XCTAssertEqual(page.ringPart.triggerRow.explanation, "None in Calculator")
        XCTAssertEqual(page.generalRingRow.explanation, Self.catalog("apps-detail-ring-general-off", "Calculator"))
    }

    /// While "Change scrolling only in these apps" is on, a muted line under the app's box
    /// says that the app's scrolling changes too (also for an app added only for its
    /// buttons, gestures or ring) and how to leave it to macOS; it fits two lines. Off: no
    /// line, and the control stands where it did.
    func testWithTheLimitOnThePageSaysTheAppsScrollingChangesToo() throws {
        Options.shared.application.applications = Self.makeStore([application(Self.calculator, inherit: true)])
        Options.shared.application.allowlist = false
        let controller = makeController()
        controller.openApplication(withID: Self.calculator, part: .buttons)
        var page = try XCTUnwrap(controller.detailController)
        page.view.layoutSubtreeIfNeeded()
        XCTAssertTrue(page.allowlistNote.isHidden)
        let controlWithout = page.partControl.frame
        XCTAssertEqual(page.headerSection.frame.minY - controlWithout.maxY, PreferencesGroupedForm.boxSpacing, accuracy: 0.5)
        controller.leaveSubpage()

        Options.shared.application.allowlist = true
        controller.openApplication(withID: Self.calculator, part: .buttons)
        page = try XCTUnwrap(controller.detailController)
        page.view.layoutSubtreeIfNeeded()
        let note = try XCTUnwrap(page.allowlistNote)
        XCTAssertFalse(note.isHidden)
        // A new app uses the Scrolling settings: the way to macOS is one choice in its
        // Scrolling part, named as the part names it.
        XCTAssertEqual(note.stringValue, "Calculator is on the list, so Scrollio changes how it scrolls. "
                       + "To leave that to macOS, choose Left to macOS in Calculator › Scrolling.")
        XCTAssertTrue(note.stringValue.contains(NSLocalizedString("apps-detail-scrolling-macos", comment: "")))
        XCTAssertFalse(page.view.hasAmbiguousLayout)
        XCTAssertEqual(page.headerSection.frame.minY - note.frame.maxY, PreferencesGroupedForm.noteSpacing, accuracy: 1)
        XCTAssertEqual(note.frame.minY - page.partControl.frame.maxY, PreferencesGroupedForm.boxSpacing, accuracy: 0.5)
        let font = PreferencesGroupedForm.explanationFont
        let twoLines = 2 * ceil(font.ascender - font.descender + font.leading) + 2
        XCTAssertLessThanOrEqual(note.frame.height, twoLines)
        XCTAssertEqual(controller.view.frame.height, page.view.fittingSize.height, accuracy: 0.5)
    }

    /// The line under the app's box shows while the limit is on and the app is not Left
    /// to macOS (then it scrolls as an app off the list does), for each choice and with the
    /// limit off and on, and takes room on a page that opens only then; a pick on the page
    /// shows or hides it at once and the pane follows.
    func testTheLimitsLineShowsUnlessTheAppIsLeftToMacOS() throws {
        for allowlist in [false, true] {
            for choice in ApplicationScrollingChoice.allCases {
                let calculator = application(Self.calculator, inherit: choice == .sameAsScrolling)
                if choice == .leftToMacOS {
                    calculator.scroll.smooth = false
                    calculator.scroll.reversesWheel = false
                }
                Options.shared.application.applications = Self.makeStore([calculator])
                Options.shared.application.allowlist = allowlist
                let controller = makeController()
                controller.openApplication(withID: Self.calculator, part: .buttons)
                let page = try XCTUnwrap(controller.detailController)
                let shows = allowlist && choice != .leftToMacOS
                XCTAssertEqual(page.allowlistNoteShows, shows, "limit \(allowlist), \(choice)")
                XCTAssertEqual(page.allowlistNote.isHidden, !shows, "limit \(allowlist), \(choice): room only while it shows")
            }
        }

        let calculator = application(Self.calculator, inherit: false)
        Options.shared.application.applications = Self.makeStore([calculator])
        Options.shared.application.allowlist = true
        let controller = makeController()
        controller.openApplication(withID: Self.calculator, part: .scrolling)
        let page = try XCTUnwrap(controller.detailController)
        XCTAssertTrue(page.allowlistNoteShows)
        pick(.leftToMacOS, on: page)
        XCTAssertFalse(page.allowlistNoteShows)
        XCTAssertEqual(page.allowlistNote.alphaValue, 0)
        XCTAssertFalse(page.allowlistNote.isAccessibilityElement(), "not read out while faded out")
        XCTAssertEqual(controller.view.frame.height, page.view.fittingSize.height, accuracy: 0.5)
        pick(.sameAsScrolling, on: page)
        XCTAssertTrue(page.allowlistNoteShows)
        XCTAssertTrue(page.allowlistNote.isAccessibilityElement())
        XCTAssertEqual(controller.view.frame.height, page.view.fittingSize.height, accuracy: 0.5)
    }

    /// With the limit on, a pick never moves the pop-up: the line above the parts keeps its
    /// room while the page stays open and only fades out for Left to macOS and in again
    /// (its distance from the page's top, which stays where it is in the window, is the
    /// same after each pick). A part that opens decides the room afresh: Left to macOS,
    /// then another part, and the room is gone; back on Scrolling another pick brings the
    /// line with its room (it must show), and it stays from then on.
    func testAPickWithTheLimitOnNeverMovesThePopUp() throws {
        let calculator = application(Self.calculator, inherit: false)
        calculator.scroll.speed = 2.5
        Options.shared.application.applications = Self.makeStore([calculator])
        Options.shared.application.allowlist = true
        let controller = makeController()
        _ = makeWindow(for: controller)
        controller.openApplication(withID: Self.calculator, part: .scrolling)
        let page = try XCTUnwrap(controller.detailController)
        let popUp = try XCTUnwrap(page.scrollingChoicePopUp)
        func fromTop(_ view: NSView) -> CGFloat {
            page.view.layoutSubtreeIfNeeded()
            let frame = view.convert(view.bounds, to: page.view)
            return page.view.isFlipped ? frame.minY : page.view.bounds.height - frame.maxY
        }
        let place = fromTop(popUp)
        let control = fromTop(page.partControl)
        let noteRoom = page.allowlistNote.frame.height + PreferencesGroupedForm.noteSpacing
        XCTAssertGreaterThan(noteRoom, 20)
        for choice in [ApplicationScrollingChoice.leftToMacOS, .sameAsScrolling, .leftToMacOS, .ownSettings, .sameAsScrolling, .leftToMacOS, .ownSettings] {
            pick(choice, on: page)
            XCTAssertEqual(page.allowlistNoteShows, choice != .leftToMacOS, "\(choice)")
            XCTAssertEqual(fromTop(popUp), place, accuracy: 0.5, "\(choice): the pop-up stays")
            XCTAssertEqual(fromTop(page.partControl), control, accuracy: 0.5, "\(choice)")
            XCTAssertEqual(controller.view.frame.height, page.view.fittingSize.height, accuracy: 0.5, "\(choice)")
        }

        // Another part opens while the app is left to macOS: no room for a line that does not show.
        pick(.leftToMacOS, on: page)
        page.show(.buttons)
        XCTAssertTrue(page.allowlistNote.isHidden)
        XCTAssertEqual(fromTop(page.partControl), control - noteRoom, accuracy: 1)
        page.show(.scrolling)
        let without = fromTop(popUp)
        XCTAssertLessThan(without, place - 20)
        pick(.ownSettings, on: page)
        XCTAssertTrue(page.allowlistNoteShows, "it must show: it takes its room")
        XCTAssertEqual(fromTop(popUp), place, accuracy: 0.5)
        pick(.leftToMacOS, on: page)
        XCTAssertEqual(fromTop(popUp), place, accuracy: 0.5, "and keeps it")
        XCTAssertEqual(controller.view.frame.height, page.view.fittingSize.height, accuracy: 0.5)
    }

    /// The line goes by what the app really scrolls with, not by the item the pop-up shows:
    /// Same as Scrolling over Scrolling settings that are themselves not smoothed and not
    /// reversed, and Own Settings held over own values that say Left to macOS (smoothing
    /// and the direction switched off by hand), show no line; switched on again, it is
    /// back at once.
    func testTheLimitsLineGoesByWhatTheAppReallyGets() throws {
        Options.shared.application.allowlist = true
        Options.shared.scroll.smooth = false
        Options.shared.scroll.reversesWheel = false
        let calculator = application(Self.calculator, inherit: true)
        Options.shared.application.applications = Self.makeStore([calculator])
        let controller = makeController()
        controller.openApplication(withID: Self.calculator, part: .scrolling)
        var page = try XCTUnwrap(controller.detailController)
        XCTAssertEqual(page.scrollingPart.shownChoice, .sameAsScrolling)
        XCTAssertFalse(ApplicationDetailViewController.showsAllowlistNote(for: calculator))
        XCTAssertFalse(page.allowlistNoteShows, "Same as Scrolling over a Scrolling left to macOS")
        Options.shared.scroll.smooth = true
        XCTAssertTrue(ApplicationDetailViewController.showsAllowlistNote(for: calculator))
        page.syncViewWithOptions()
        XCTAssertTrue(page.allowlistNoteShows)
        controller.leaveSubpage()

        // Own Settings held over values switched to Left to macOS here, by hand.
        calculator.inherit = false
        calculator.scroll.smooth = true
        calculator.scroll.reversesWheel = true
        controller.openApplication(withID: Self.calculator, part: .scrolling)
        page = try XCTUnwrap(controller.detailController)
        let settings = try XCTUnwrap(page.scrollingController)
        XCTAssertTrue(page.allowlistNoteShows)
        settings.smoothSwitch.state = .off
        send(settings.smoothSwitch)
        XCTAssertTrue(page.allowlistNoteShows, "the direction is still reversed")
        settings.reverseSwitch.state = .off
        send(settings.reverseSwitch)
        XCTAssertEqual(page.scrollingPart.shownChoice, .ownSettings, "held while the part shows")
        XCTAssertEqual(calculator.scrollingChoice, .leftToMacOS)
        XCTAssertFalse(page.allowlistNoteShows, "the app scrolls as one off the list")
        settings.smoothSwitch.state = .on
        send(settings.smoothSwitch)
        XCTAssertTrue(page.allowlistNoteShows)
        XCTAssertEqual(controller.view.frame.height, page.view.fittingSize.height, accuracy: 0.5)
    }

    /// Nothing of the choice is stored: a settings file carries what it is worked out from,
    /// and every app reads the same choice after an export and an import.
    func testASettingsFileKeepsEachAppsChoice() throws {
        let paths = [Self.calculator, Self.textEdit, "/Applications/Safari.app"]
        let choices: [ApplicationScrollingChoice] = [.sameAsScrolling, .ownSettings, .leftToMacOS]
        let source = Options()
        source.defaults = TestDefaults.make(for: self)
        source.readOptions()
        for (path, choice) in zip(paths, choices) {
            let entry = Application(path: path)
            entry.scroll.speed = 2.5
            entry.inherit = choice == .sameAsScrolling
            if choice == .leftToMacOS {
                entry.scroll.smooth = false
                entry.scroll.reversesWheel = false
            }
            source.application.applications.append(entry)
        }
        let data = try SettingsFile.export(from: source).get()

        let target = Options()
        target.defaults = TestDefaults.make(for: self)
        target.readOptions()
        XCTAssertTrue(SettingsFile.apply(try SettingsFile.read(data).get(), to: target))
        for (path, choice) in zip(paths, choices) {
            let entry = try XCTUnwrap(target.application.applications.get(by: path), path)
            XCTAssertEqual(entry.scrollingChoice, choice, path)
            XCTAssertEqual(entry.scroll.speed, 2.5, path)
        }
    }

    /// The page's "Shortcut Ring" part. While "Use the general ring" is on (as for every
    /// app until the user turns it off) there is what opens the ring and the switch, and
    /// nothing else: no drawing, no rows, and nothing new is stored for the app.
    func testTheShortcutRingSectionHasOnlyItsSwitchWhileTheAppUsesTheGeneralRing() throws {
        setGeneralRing(.default)
        let calculator = application(Self.calculator, inherit: true)
        Options.shared.application.applications = Self.makeStore([calculator])
        let controller = makeController()
        controller.openApplication(withID: Self.calculator, part: .ring)
        let page = try XCTUnwrap(controller.detailController)

        XCTAssertNil(page.ringSection.titleLabel, "the part's segment names it")
        XCTAssertEqual(page.ringSection.box.visibleRows, [page.ringPart.triggerRow, page.generalRingRow])
        XCTAssertEqual(page.generalRingRow.title, Self.catalog("apps-detail-ring-general"))
        XCTAssertEqual(page.generalRingSwitch.state, .on)
        XCTAssertEqual(page.generalRingSwitch.controlSize, PreferencesGroupedForm.switchControlSize)
        XCTAssertEqual(page.generalRingRow.explanation, Self.catalog("apps-detail-ring-general-on", "Calculator"))
        XCTAssertNil(page.ringController, "no drawing and no rows")
        XCTAssertFalse(allSubviews(of: page.view).contains { $0 is ShortcutRingPreviewView || $0 is ButtonActionPullDown })
        // The section is the part's first box, and the part ends under it.
        page.view.layoutSubtreeIfNeeded()
        XCTAssertFalse(page.view.hasAmbiguousLayout)
        XCTAssertEqual(page.ringPart.view.frame.height - page.ringSection.frame.maxY, PreferencesGroupedForm.margin, accuracy: 0.5)
        XCTAssertEqual(page.ringSection.frame.minY, PreferencesGroupedForm.margin, accuracy: 0.5)
        let stored = try XCTUnwrap(try storedObject()?.firstObject as? NSDictionary)
        XCTAssertEqual(Set(stored.allKeys.compactMap { $0 as? String }), ["path", "displayName", "inherit", "scroll"])
    }

    /// Switched off, the app's ring starts as a copy of the general ring as it is at that
    /// moment, and the page shows it with the pieces of the Shortcut Ring pane: the
    /// drawing, the freeze switch and the eight rows, in the pane's order, without what
    /// opens the ring. A row, the freeze switch too, changes the app's ring and not the
    /// general one. Switched on again the rows go and the app's ring is kept;
    /// off again it comes back as it was left.
    func testSwitchingOffUseTheGeneralRingShowsTheAppsOwnRingWhichItsRowsEdit() throws {
        var general = ShortcutRingSettings.default
        general[1] = ShortcutRingPlace(SystemShortcut.undo)
        general[6] = .empty
        // (A place opens an app: only such a ring keeps a face made at a quiet moment.)
        general[4] = ShortcutRingPlace(openTarget: OpenTargetPayload(
            path: "/System/Applications/TextEdit.app", bundleID: "com.apple.TextEdit", arguments: "", kind: .application
        ))
        setGeneralRing(general)
        let calculator = application(Self.calculator, inherit: true)
        Options.shared.application.applications = Self.makeStore([calculator])
        let controller = makeController()
        controller.openApplication(withID: Self.calculator, part: .ring)
        let page = try XCTUnwrap(controller.detailController)
        var heightChanges = 0
        page.onHeightChange = { heightChanges += 1 }
        let shortHeight = page.view.fittingSize.height

        page.generalRingSwitch.state = .off
        send(page.generalRingSwitch)
        XCTAssertFalse(calculator.usesGeneralRing)
        XCTAssertEqual(calculator.ownRingPlaces, general.places, "a copy of the general ring")
        XCTAssertEqual(page.generalRingRow.explanation, Self.catalog("apps-detail-ring-general-off", "Calculator"))
        XCTAssertEqual(heightChanges, 1)
        let ring = try XCTUnwrap(page.ringController)
        XCTAssertTrue(ring.view.isDescendant(of: page.view))
        XCTAssertTrue(page.ringPart.children.contains(ring))
        XCTAssertEqual(ring.sections.count, 3, "the drawing, the freeze switch and the box of rows")
        let freezeRow = try XCTUnwrap(ring.freezeRow)
        XCTAssertEqual(freezeRow.title, "Freeze pointer while the ring is held")
        XCTAssertTrue(freezeRow.isDescendant(of: ring.sections[1]))
        let freeze = try XCTUnwrap(ring.freezeToggle as? NSSwitch)
        XCTAssertEqual(freeze.state, .off, "a copy of the general ring's switch")
        XCTAssertEqual(ring.placeRows.map(\.title), [
            "Top", "Top right", "Right", "Bottom right", "Bottom", "Bottom left", "Left", "Top left",
        ])
        XCTAssertEqual(ring.placePopUps.map { $0.menu?.items.first?.title }[1], SystemShortcut.undo.localizedName)
        XCTAssertEqual(ring.placePopUps[6].menu?.items.first?.title, "No Action")
        XCTAssertEqual(ring.previewView.face.places[1].title, SystemShortcut.undo.localizedName)
        XCTAssertEqual(ring.previewView.face.filled[6], false)
        // What opens the ring stays in the Shortcut Ring pane, and its reset (the part has
        // its own).
        XCTAssertNil(ring.triggerRow)
        XCTAssertNil(ring.resetToDefaults)
        XCTAssertNil(ring.placesHintLabel)
        page.view.layoutSubtreeIfNeeded()
        XCTAssertFalse(page.view.hasAmbiguousLayout)
        // (Something opens the ring with the app in front: nothing folds, no title.)
        XCTAssertNil(page.ringPart.ownRingFold)
        func frame(_ view: NSView) -> NSRect {
            return view.convert(view.bounds, to: page.ringPart.view)
        }
        XCTAssertEqual(frame(ring.view).maxY, page.ringSection.frame.minY, accuracy: 0.5, "under the switch's box")
        // Then "Reset to Defaults", and the page ends with it.
        let footer = try XCTUnwrap(page.ringPart.resetFooter)
        XCTAssertEqual(frame(footer).maxY, frame(ring.view).minY, accuracy: 0.5, "the ring's margin over the footer")
        XCTAssertEqual(frame(footer).minY, PreferencesGroupedForm.margin, accuracy: 0.5, "the page ends with it")
        XCTAssertEqual(
            page.view.fittingSize.height, shortHeight + ring.view.fittingSize.height + footer.fittingSize.height, accuracy: 0.5
        )

        // A row's pull-down: the app's ring changes, the general ring does not.
        ring.placePopUps[0].onShortcutSelected?(SystemShortcut.paste)
        ring.placePopUps[3].onShortcutSelected?(nil)
        XCTAssertEqual(calculator.ownRingPlaces?[0].action, "paste")
        XCTAssertEqual(calculator.ownRingPlaces?[3], .empty)
        XCTAssertEqual(Options.shared.ring, general, "the general ring is untouched")
        XCTAssertEqual(ring.previewView.face.places[0].title, SystemShortcut.paste.localizedName)
        XCTAssertEqual(ring.placePopUps[0].menu?.items.first?.title, SystemShortcut.paste.localizedName)
        XCTAssertEqual(ring.selectedPlace, 3)
        freeze.state = .on
        send(freeze)
        XCTAssertEqual(calculator.ring?.freezePointer, true)
        XCTAssertTrue(calculator.ringThatOpens(general: general).freezePointer)
        XCTAssertFalse(Options.shared.ring.freezePointer, "the general ring's switch is untouched")
        // The face of the ring on screen is made here, for the ring as it opens for the app.
        XCTAssertTrue(ShortcutRingController.preparedFace?.ring == calculator.ringThatOpens(general: general))
        // The general ring changes later: the app's own does not follow.
        Options.shared.ring[2] = ShortcutRingPlace(SystemShortcut.copy)
        page.syncViewWithOptions()
        XCTAssertEqual(calculator.ownRingPlaces?[2], general[2])
        XCTAssertEqual(ring.placePopUps[2].menu?.items.first?.title, SystemShortcut.moveSpaceRight.localizedName)

        // Stored with the app's entry.
        let stored = try XCTUnwrap(try storedObject()?.firstObject as? NSDictionary)
        let storedRing = try XCTUnwrap(stored["ring"] as? NSDictionary)
        XCTAssertEqual(storedRing["inherit"] as? Bool, false)
        XCTAssertEqual((storedRing["places"] as? NSArray)?.count, 8)
        XCTAssertEqual(storedRing["freezePointer"] as? Bool, true)

        // On again: the rows go, the ring is kept and not used.
        page.generalRingSwitch.state = .on
        send(page.generalRingSwitch)
        XCTAssertTrue(calculator.usesGeneralRing)
        XCTAssertNil(page.ringController)
        XCTAssertNil(ring.view.superview)
        XCTAssertFalse(page.ringPart.children.contains(ring))
        XCTAssertEqual(calculator.ring?[0].action, "paste", "kept in storage")
        XCTAssertEqual(page.view.fittingSize.height, shortHeight, accuracy: 0.5)
        XCTAssertEqual(heightChanges, 2)
        // Off again: the app's ring as it was left, not a new copy.
        page.generalRingSwitch.state = .off
        send(page.generalRingSwitch)
        XCTAssertEqual(calculator.ownRingPlaces?[0].action, "paste")
        XCTAssertEqual(page.ringController?.placePopUps[0].menu?.items.first?.title, SystemShortcut.paste.localizedName)
        XCTAssertEqual(Options.shared.ring[0], general[0])
    }

    /// An app whose own ring is in use opens its page with the rows there; "Open App or
    /// File" of a row goes into the app's ring.
    func testAnAppsPageOpensWithItsOwnRingAndARowCanOpenAnApp() throws {
        setGeneralRing(.default)
        let calculator = application(Self.calculator, inherit: true)
        calculator.setUsesGeneralRing(false, general: .default)
        calculator.ring?[4] = ShortcutRingPlace(SystemShortcut.copy)
        Options.shared.application.applications = Self.makeStore([calculator])
        let controller = makeController()
        controller.openApplication(withID: Self.calculator)
        let page = try XCTUnwrap(controller.detailController)
        XCTAssertEqual(page.generalRingSwitch.state, .off)
        let ring = try XCTUnwrap(page.ringController)
        XCTAssertEqual(ring.placePopUps[4].menu?.items.first?.title, SystemShortcut.copy.localizedName)

        var presented: [OpenTargetPayload?] = []
        ring.presentOpenTarget = { _, _, existing in presented.append(existing) }
        ring.placePopUps[4].onOpenTargetSelectionRequested?()
        let textEdit = OpenTargetPayload(path: Self.textEdit, bundleID: "com.apple.TextEdit", arguments: "", kind: .application)
        try XCTUnwrap(ring.openTargetPopover).onCommit?(textEdit)
        XCTAssertEqual(presented.count, 1)
        XCTAssertEqual(calculator.ownRingPlaces?[4], ShortcutRingPlace(openTarget: textEdit))
        XCTAssertEqual(Options.shared.ring, .default)
        XCTAssertNotNil(ring.previewView.face.places[4].image, "the app's icon in the drawing")

        // Removed and brought back by Undo onto an entry added again: the ring comes along.
        let again = application(Self.calculator, inherit: true)
        ApplicationSettings(of: calculator).apply(to: again)
        XCTAssertEqual(again.ring, calculator.ring)
    }

    /// Both explanations of the switch are plain sentences that fit two lines, also for an
    /// app with a long name, and switching never moves the rows under it.
    func testTheRingSwitchsExplanationsFitTwoLines() throws {
        setGeneralRing(.default)
        let font = PreferencesGroupedForm.explanationFont
        let twoLines = 2 * ceil(font.ascender - font.descender + font.leading) + 2
        let long = application(Self.calculator, inherit: true)
        // (Long enough to need the second line whatever the switch's width is taken to be.)
        long.displayName = "An Application With A Remarkably Long Name For Its Kind"
        Options.shared.application.applications = Self.makeStore([long])
        let controller = makeController()
        controller.openApplication(withID: Self.calculator, part: .ring)
        let page = try XCTUnwrap(controller.detailController)
        page.view.layoutSubtreeIfNeeded()
        let rowHeight = page.generalRingRow.frame.height
        for on in [true, false] {
            page.generalRingSwitch.state = on ? .on : .off
            send(page.generalRingSwitch)
            page.view.layoutSubtreeIfNeeded()
            let label = page.generalRingRow.explanationLabel
            let text = label.stringValue
            XCTAssertTrue(text.hasSuffix("."), text)
            XCTAssertTrue(text.contains("An Application With A Remarkably Long Name For Its Kind"), text)
            XCTAssertGreaterThan(label.frame.width, 200)
            let height = (text as NSString).boundingRect(
                with: NSSize(width: label.frame.width, height: 1000), options: [.usesLineFragmentOrigin], attributes: [.font: font]
            ).height
            XCTAssertLessThanOrEqual(height, twoLines, "\(text) in \(label.frame.width) pt")
            XCTAssertEqual(page.generalRingRow.frame.height, rowHeight, accuracy: 0.5, "the other line takes the same room")
        }
    }
}
