//
//  ApplicationThumbWheelTests.swift
//  ScrollioTests
//
//  The thumb wheel of an app's own (`ApplicationThumbWheel`): how the app's entry stores it
//  and what an entry from before reads as, the settings file and its import sheet, the mark
//  of the list of apps, that it takes nothing from a Logitech mouse; the row of the app's
//  Buttons part ("+", its pull-down, "−" and Undo); and which function a turn runs through
//  the scroll tap (the app in front at the turn's first event, kept until the wheel rests).
//  Nothing is shown on screen and nothing reaches the system: menus go through seams,
//  windows are never ordered in, actions are recorded by the engine's rig.
//

import XCTest
@testable import Scrollio_Debug

private typealias FrontApp = ShortcutRingChoice.FrontApp

// MARK: - The app's entry, the file, the mark

final class ApplicationThumbWheelTests: XCTestCase {

    private func dictionary(_ application: Application) throws -> NSDictionary {
        let data = try JSONEncoder().encode(application)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    private func read(_ text: String) throws -> Application {
        return try JSONDecoder().decode(Application.self, from: Data(text.utf8))
    }

    /// Stored under "thumbWheel" in the general settings' name, only while the app has a
    /// function of its own, and read back as it was; nil stores nothing again.
    func testTheAppsFunctionIsStoredOnItsEntryAndReadBack() throws {
        let notes = Application(path: "/Applications/Notes.app")
        XCTAssertNil(try dictionary(notes)["thumbWheel"], "nothing stored for an app without one")
        for function in ThumbWheelFunction.allCases {
            notes.setOwnThumbWheelFunction(function)
            XCTAssertEqual(try dictionary(notes)["thumbWheel"] as? NSDictionary, ["function": function.rawValue])
            let again = try JSONDecoder().decode(Application.self, from: JSONEncoder().encode(notes))
            XCTAssertEqual(again.ownThumbWheelFunction, function)
            XCTAssertEqual(again.thumbWheel, notes.thumbWheel)
        }
        XCTAssertEqual(ApplicationThumbWheel(function: .zoom), ApplicationThumbWheel(function: .zoom))
        notes.setOwnThumbWheelFunction(nil)
        XCTAssertNil(notes.thumbWheel)
        XCTAssertNil(try dictionary(notes)["thumbWheel"], "given back: stored as an entry without one")
    }

    /// An entry from before (as version 1.0.5 wrote it): the general function, and it is
    /// written back exactly as it was.
    func testAnEntryFromBeforeReadsAsTheGeneralFunctionAndIsStoredAsBefore() throws {
        let older = try read(StoredDataCanaryTests.readableApp)
        XCTAssertNil(older.thumbWheel)
        XCTAssertNil(older.ownThumbWheelFunction)
        XCTAssertFalse(older.hasOwnButtonsPart)
        let original = try JSONSerialization.jsonObject(with: Data(StoredDataCanaryTests.readableApp.utf8)) as? NSDictionary
        XCTAssertEqual(try dictionary(older), original)
    }

    /// What cannot be read takes nothing of the entry with it and is none; a function of a
    /// later version is kept as stored and not used, until the page sets one.
    func testAThumbWheelThatCannotBeReadIsNoneAndALaterVersionsFunctionIsKept() throws {
        for broken in [#""thumbWheel":3"#, #""thumbWheel":{"speed":2}"#, #""thumbWheel":{"function":7}"#, #""thumbWheel":null"#] {
            let entry = try read(#"{"path":"/Applications/A.app","inherit":false,"# + broken + "}")
            XCTAssertEqual(entry.path, "/Applications/A.app", broken)
            XCTAssertFalse(entry.inherit, broken)
            XCTAssertNil(entry.thumbWheel, broken)
        }
        let later = try read(#"{"path":"/Applications/A.app","thumbWheel":{"function":"brightness"}}"#)
        XCTAssertNil(later.ownThumbWheelFunction, "not used")
        XCTAssertFalse(later.hasOwnButtonsPart)
        XCTAssertEqual(try dictionary(later)["thumbWheel"] as? NSDictionary, ["function": "brightness"], "written back as stored")
        later.setOwnThumbWheelFunction(nil)
        XCTAssertNotNil(later.thumbWheel, "nothing to give back: kept")
        later.setOwnThumbWheelFunction(.tabs)
        XCTAssertEqual(try dictionary(later)["thumbWheel"] as? NSDictionary, ["function": "tabs"])
    }

    /// The own function of the app in front, found by its bundle's path or its program's;
    /// any other app, Scrollio itself and no app: the general function. While no app on the
    /// list has one, the app in front is not even asked.
    func testATurnRunsTheOwnFunctionOfTheAppInFrontOnly() {
        let figma = Application(path: "/Applications/Figma.app")
        figma.setOwnThumbWheelFunction(.zoom)
        let tool = Application(path: "/usr/local/bin/tool")
        tool.setOwnThumbWheelFunction(.volume)
        let notes = Application(path: "/Applications/Notes.app")
        let list = EnhanceArray<Application>(withArray: [figma, tool, notes], matchKey: "path")
        var asked = 0
        func choice(_ front: FrontApp?) -> ThumbWheelFunction? {
            return ThumbWheelChoice.ownFunction(front: { asked += 1; return front }, applications: list)
        }
        XCTAssertEqual(choice(FrontApp(bundlePath: figma.path, executablePath: figma.path + "/Contents/MacOS/Figma")), .zoom)
        XCTAssertEqual(choice(FrontApp(bundlePath: nil, executablePath: tool.path)), .volume, "by the program's path")
        XCTAssertNil(choice(FrontApp(bundlePath: notes.path)), "on the list, without one")
        XCTAssertNil(choice(FrontApp(bundlePath: "/Applications/Safari.app")), "not on the list")
        XCTAssertNil(choice(FrontApp(bundlePath: figma.path, isScrollio: true)), "Scrollio's settings in front")
        XCTAssertNil(choice(nil))
        XCTAssertEqual(asked, 6)

        figma.setOwnThumbWheelFunction(nil)
        tool.setOwnThumbWheelFunction(nil)
        asked = 0
        XCTAssertNil(choice(FrontApp(bundlePath: figma.path)))
        XCTAssertEqual(asked, 0, "no app has one: the app in front is not asked")
    }

    /// The Buttons mark of the list counts the thumb wheel ("Default" too: the app's own).
    func testTheButtonsMarkCountsAnAppsOwnThumbWheel() {
        let app = Application(path: "/Applications/Figma.app")
        XCTAssertEqual(ApplicationPagePart.ownSettings(of: app), [])
        app.setOwnThumbWheelFunction(.scroll)
        XCTAssertEqual(ApplicationPagePart.ownSettings(of: app), [.buttons])
        XCTAssertFalse(app.hasOwnButtons, "no button of its own")
        app.setOwnThumbWheelFunction(nil)
        XCTAssertEqual(ApplicationPagePart.ownSettings(of: app), [])
    }

    /// Undo of an app's removal gives the entry added again its thumb wheel too.
    func testTheSettingsUndoMovesBetweenEntriesCarryTheThumbWheel() {
        let app = Application(path: "/Applications/Figma.app")
        app.setOwnThumbWheelFunction(.volume)
        let again = Application(path: "/Applications/Figma.app")
        ApplicationSettings(of: app).apply(to: again)
        XCTAssertEqual(again.ownThumbWheelFunction, .volume)
    }

    /// No function needs the wheel diverted (every one runs from the sideways wheel's events
    /// at the scroll tap): an app's own function takes no Logitech button from the mouse,
    /// and the log line about the apps' own Logitech buttons does not count such an app.
    func testAnAppsOwnThumbWheelTakesNothingFromTheMouse() {
        let general = [ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 1006, modifiers: 0, deviceFilter: nil), systemShortcutName: "copy"
        )]
        let figma = Application(path: "/Applications/Figma.app")
        figma.setOwnThumbWheelFunction(.zoom)
        let list = EnhanceArray<Application>(withArray: [figma], matchKey: "path")
        let isLogiCode: (UInt16) -> Bool = { $0 >= 1000 }
        XCTAssertEqual(LogiUsageBootstrap.ownLogitechButtons(general: general, applications: list, isLogiCode: isLogiCode), .none)
        XCTAssertEqual(
            LogiUsageBootstrap.buttonBindingCodes(general: general, frontAppOwn: figma.ownButtonBindings, isLogiCode: isLogiCode),
            [1006]
        )
    }

    /// The roll's line says when the function was the app's own, never which app.
    func testTheRollsLineSaysWhenTheFunctionWasTheAppsOwn() {
        var roll = ScrollSystemLog.ThumbWheelRoll(id: 1, settings: ThumbWheelSettings(function: .zoom), at: 0)
        roll.add(ThumbWheelEvent(lineDelta: -1, fixedDelta: -1, pointDelta: -10, isContinuous: false), at: 0)
        let general = ScrollSystemLog.thumbWheelMessage(for: roll)
        XCTAssertTrue(general.contains(", zoom x1.00, "), general)
        roll.isAppsOwn = true
        let own = ScrollSystemLog.thumbWheelMessage(for: roll)
        XCTAssertTrue(own.contains(", zoom (the app's own) x1.00, "), own)
        XCTAssertEqual(own.replacingOccurrences(of: " (the app's own)", with: ""), general)
    }

    // MARK: The settings file

    private func ownOptions() -> Options {
        let options = Options()
        options.defaults = TestDefaults.make(for: self)
        return options
    }

    /// Export writes the app's thumb wheel with its entry, a read brings it back, the sheet
    /// lists it with the app's buttons and counts the app, and an import stores it; the
    /// general thumb wheel is another setting. A file from elsewhere: a function this
    /// version does not know is left out and counted, and so is what is no thumb wheel,
    /// while the app stays; a file from before has none.
    func testTheSettingsFileCarriesAnAppsThumbWheel() throws {
        let source = ownOptions()
        let figma = Application(path: "/Applications/Figma.app")
        figma.setOwnThumbWheelFunction(.zoom)
        let notes = Application(path: "/Applications/Notes.app")
        notes.setOwnThumbWheelFunction(.scroll)
        source.application.applications.append(figma)
        source.application.applications.append(notes)
        source.application.applications.append(Application(path: "/Applications/Mail.app"))
        let data = try SettingsFile.export(from: source, now: Date(timeIntervalSince1970: 1_794_476_527)).get()
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entries = try XCTUnwrap((root["settings"] as? [String: Any])?["applications"] as? [[String: Any]])
        XCTAssertEqual(entries.map { $0["thumbWheel"] as? NSDictionary }, [["function": "zoom"], ["function": "scroll"], nil])

        let contents = try SettingsFile.read(data).get()
        XCTAssertEqual(contents.applications?.map(\.ownThumbWheelFunction), [.zoom, .scroll, nil])
        XCTAssertEqual(contents.leftOutCount, 0)
        XCTAssertEqual(SettingsFileText.thumbWheelLines(of: contents), ["Thumb wheel in Figma: Zoom", "Thumb wheel in Notes: Default"])
        let items = SettingsFileText.items(of: contents).map(\.text)
        XCTAssertTrue(items.contains("2 apps with buttons of their own"), "\(items)")

        let target = ownOptions()
        target.readOptions()
        XCTAssertTrue(SettingsFile.apply(contents, to: target))
        XCTAssertEqual(target.application.applications.get(by: figma.path)?.ownThumbWheelFunction, .zoom)
        XCTAssertEqual(target.application.applications.get(by: notes.path)?.ownThumbWheelFunction, .scroll)
        XCTAssertEqual(target.thumbWheel, .default, "the general thumb wheel is another setting")

        let file = Data((#"{"format":"scrollio-settings","formatVersion":1,"settings":{"applications":["#
            + #"{"path":"/Applications/A.app","thumbWheel":{"function":"brightness"}},"#
            + #"{"path":"/Applications/B.app","thumbWheel":"zoom"},"#
            + #"{"path":"/Applications/C.app","thumbWheel":{"function":"tabs"}},"#
            + StoredDataCanaryTests.readableApp + "]}}").utf8)
        let foreign = try SettingsFile.read(file).get()
        XCTAssertEqual(foreign.applications?.map(\.path), ["/Applications/A.app", "/Applications/B.app", "/Applications/C.app", "/Applications/A.app"])
        XCTAssertEqual(foreign.applications?.map(\.ownThumbWheelFunction), [nil, nil, .tabs, nil])
        XCTAssertNil(foreign.applications?.first?.thumbWheel, "a later version's function is not brought in")
        XCTAssertEqual(foreign.unknownActions, 1)
        XCTAssertEqual(foreign.unreadableEntries, 1)
        XCTAssertEqual(SettingsFileText.thumbWheelLines(of: foreign), ["Thumb wheel in C: Switch Tabs"])
    }
}

// MARK: - The app's Buttons part

final class ApplicationThumbWheelPageTests: XCTestCase {

    private static let calculator = "/System/Applications/Calculator.app"

    private var savedApplications: EnhanceArray<Application>!
    private var savedBindings: [ButtonBinding] = []
    private var savedThumbWheel = ThumbWheelSettings.default
    private var uiDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        savedApplications = Options.shared.application.applications
        savedBindings = Options.shared.buttons.binding
        savedThumbWheel = Options.shared.thumbWheel
        Options.shared.application.applications = EnhanceArray<Application>(
            withArray: [], matchKey: "path", forObserver: { Options.shared.markChanged(.application) }
        )
        Options.shared.buttons.binding = []
        Options.shared.thumbWheel = .default
        ButtonUtils.shared.invalidateCache()
        uiDefaults = TestDefaults.make(for: self)
        ApplicationPagePart.buttons.remember(in: uiDefaults)
    }

    override func tearDown() {
        Options.shared.application.applications = savedApplications
        Options.shared.buttons.binding = savedBindings
        Options.shared.thumbWheel = savedThumbWheel
        ButtonUtils.shared.invalidateCache()
        savedApplications = nil
        uiDefaults = nil
        super.tearDown()
    }

    private func makePane() -> PreferencesApplicationViewController {
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesSplitViewController.self))
        let controller = storyboard.instantiateController(withIdentifier: PANEL_IDENTIFIER.application) as! PreferencesApplicationViewController
        controller.uiStateDefaults = uiDefaults
        controller.runningApplications = { [] }
        controller.presentMenu = { _, _ in }
        controller.chooseApplications = { _, _ in XCTFail("no open panel was expected") }
        _ = controller.view
        return controller
    }

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

    @discardableResult
    private func addCalculator() -> Application {
        let application = Application(path: Self.calculator)
        Options.shared.application.applications.append(application)
        return application
    }

    private func mouse(_ name: String?) -> ButtonsDeviceSource {
        var source = ButtonsDeviceSource(
            captureStatus: { _ in .normal }, deviceName: { name }, isBusy: { false }, refresh: {}, warnBluetoothButton: { _ in }
        )
        source.recordedTrigger = { part in
            let codes: [ButtonsMousePart: UInt16] = [.middle: 2, .back: 3, .forward: 4, .gesture: 1000, .modeShift: 1001]
            return RecordedEvent(type: .mouse, code: codes[part] ?? 1009, modifiers: 0, deviceFilter: nil)
        }
        return source
    }

    /// The Buttons part of Calculator's page on `mouseName`, with menus caught.
    private func buttonsPart(
        mouse mouseName: String? = "MX Master 3S", pane: PreferencesApplicationViewController? = nil,
        menus: ((NSMenu) -> Void)? = nil, actionMenus: ((NSPopUpButton) -> Void)? = nil
    ) throws -> ApplicationButtonsViewController {
        let pane = pane ?? makePane()
        pane.openApplication(withID: Self.calculator, part: .buttons)
        let part = try XCTUnwrap(pane.detailController?.buttonsPart)
        part.deviceSource = mouse(mouseName)
        part.presentMenu = { menu, _ in menus?(menu) }
        part.openActionMenu = { actionMenus?($0) }
        part.startRecording = { _ in }
        part.stopRecording = {}
        part.presentOpenTarget = { _, _, _ in }
        part.paneUndoManager = UndoManager()
        part.reloadRows()
        return part
    }

    private func titles(of menu: NSMenu) -> [String] {
        return menu.items.map { $0.isSeparatorItem ? "—" : $0.title }
    }

    private func title(_ part: ButtonsMousePart, on controller: ApplicationButtonsViewController) -> String {
        return ButtonTriggerNaming.title(for: controller.trigger(for: part))
    }

    /// "+" lists "Thumb wheel" in the mouse's section where the Buttons pane lists it (after
    /// the mode shift button), only with a mouse that has one, and only while the app has
    /// no function of its own for it.
    func testThePlusMenuOffersTheThumbWheelOnlyWithAThumbWheelMouseAndOnce() throws {
        let calculator = addCalculator()
        let part = try buttonsPart()
        var names = titles(of: part.makeAddMenu())
        let modeShift = try XCTUnwrap(names.firstIndex(of: title(.modeShift, on: part)))
        XCTAssertEqual(names[modeShift + 1], "Thumb wheel", "\(names)")
        XCTAssertEqual(names.filter { $0 == "Thumb wheel" }.count, 1)

        // The mode shift button is the app's own already: right after the middle button.
        calculator.setOwnButtonBindings([ButtonBinding(triggerEvent: part.trigger(for: .modeShift), systemShortcutName: "copy")])
        part.reloadRows()
        names = titles(of: part.makeAddMenu())
        XCTAssertEqual(names.firstIndex(of: "Thumb wheel"), try XCTUnwrap(names.firstIndex(of: title(.middle, on: part))) + 1, "\(names)")

        // Every button of the mouse is the app's own: the section holds the wheel alone.
        calculator.setOwnButtonBindings(ButtonsMousePart.listed(on: part.mouse).map {
            ButtonBinding(triggerEvent: part.trigger(for: $0), systemShortcutName: "copy")
        })
        part.reloadRows()
        names = titles(of: part.makeAddMenu())
        XCTAssertEqual(Array(names.prefix(3)), ["Your Mouse", "Thumb wheel", "—"], "\(names)")
        XCTAssertEqual(part.makeAddMenu().items.first?.isSectionHeader, true)

        // Once the app has it: not again.
        calculator.setOwnButtonBindings([])
        part.addOwnThumbWheel()
        XCTAssertFalse(titles(of: part.makeAddMenu()).contains("Thumb wheel"))

        // A mouse without a thumb wheel, and no mouse: not offered.
        calculator.setOwnThumbWheelFunction(nil)
        for other in ["MX Anywhere 3S", "MX Vertical", nil] {
            let without = try buttonsPart(mouse: other)
            XCTAssertFalse(titles(of: without.makeAddMenu()).contains("Thumb wheel"), other ?? "no mouse")
        }
    }

    /// Choosing it adds the row first in the list, with the function the wheel has
    /// everywhere and a line that names it; the row is selected and its menu opens.
    /// Buttons and Scrolling › Thumb wheel are not touched.
    func testChoosingTheThumbWheelAddsItsRowWithTheGeneralFunctionAndOpensItsMenu() throws {
        Options.shared.thumbWheel = ThumbWheelSettings(function: .tabs, speed: 2)
        let calculator = addCalculator()
        calculator.setOwnButtonBindings([ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, deviceFilter: nil), systemShortcutName: "copy"
        )])
        var opened: [NSPopUpButton] = []
        var shown: NSMenu?
        let part = try buttonsPart(menus: { shown = $0 }, actionMenus: { opened.append($0) })
        _ = makeWindow(for: part)
        part.showAddMenu(from: part.list.addButton)
        let item = try XCTUnwrap(shown?.items.first { $0.title == "Thumb wheel" })
        XCTAssertTrue(item.target === part)
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item))

        XCTAssertEqual(calculator.ownThumbWheelFunction, .tabs)
        XCTAssertEqual(Options.shared.thumbWheel, ThumbWheelSettings(function: .tabs, speed: 2))
        let row = try XCTUnwrap(part.thumbWheelRow)
        XCTAssertTrue(part.list.rows.first === row, "first in the list")
        XCTAssertEqual(part.list.rows.count, 2)
        XCTAssertEqual(row.title, "Thumb wheel")
        XCTAssertEqual(row.function, .tabs)
        XCTAssertEqual(row.explanation, "Everywhere: Switch Tabs")
        XCTAssertEqual(row.accessibilityLabel(), "Thumb wheel, Everywhere: Switch Tabs")
        XCTAssertTrue(row.isRemovable)
        XCTAssertEqual(part.list.selectedID, ButtonsListLayout.thumbWheelRowID)
        let opens = expectation(description: "the row's menu opens")
        DispatchQueue.main.async { opens.fulfill() }
        wait(for: [opens], timeout: 1)
        XCTAssertTrue(opened.first === row.pullDown)

        // Chosen again (from a menu made before): the row is there already.
        part.addOwnThumbWheel()
        XCTAssertEqual(part.list.rows.count, 2)
        // Return on the row opens its menu too.
        part.list.onOpen?(ButtonsListLayout.thumbWheelRowID)
        XCTAssertTrue(opened.last === row.pullDown)
    }

    /// The row's pull-down changes the app's function only; the line under it follows the
    /// general one; the row stays the same view. With the thumb wheel alone the note says
    /// what the rows do, not how to add one.
    func testTheRowsPullDownChangesTheAppsFunctionNotTheGeneralOne() throws {
        let calculator = addCalculator()
        calculator.setOwnThumbWheelFunction(.zoom)
        let part = try buttonsPart()
        let row = try XCTUnwrap(part.thumbWheelRow)
        XCTAssertEqual(row.explanation, "Everywhere: Default")
        XCTAssertEqual(part.noteLabel.stringValue, ApplicationButtonsViewController.note(for: "Calculator"))

        let volume = try XCTUnwrap(row.pullDown.functionItems.first { ThumbWheelPresentation.function(of: $0) == .volume })
        row.pullDown.functionChosen(volume)
        XCTAssertEqual(calculator.ownThumbWheelFunction, .volume)
        XCTAssertEqual(Options.shared.thumbWheel, .default, "Buttons and Scrolling keep theirs")
        XCTAssertTrue(part.thumbWheelRow === row)
        XCTAssertEqual(row.function, .volume)

        let scroll = try XCTUnwrap(row.pullDown.functionItems.first { ThumbWheelPresentation.function(of: $0) == .scroll })
        row.pullDown.functionChosen(scroll)
        XCTAssertEqual(calculator.ownThumbWheelFunction, .scroll, "\"Default\" is the app's own: it scrolls here")
        XCTAssertEqual(row.pullDown.menu?.items.first?.title, "Default")

        Options.shared.thumbWheel.function = .desktops
        part.syncViewWithOptions()
        XCTAssertEqual(row.explanation, "Everywhere: Switch Desktops")
        XCTAssertEqual(calculator.ownThumbWheelFunction, .scroll)
    }

    /// "−" gives the wheel back to Buttons (nothing stored); Undo takes it again with its
    /// function, selected; Redo gives it back.
    func testRemovingTheRowGivesTheWheelBackAndUndoTakesItAgain() throws {
        let calculator = addCalculator()
        calculator.setOwnThumbWheelFunction(.volume)
        let part = try buttonsPart()
        let undo = try XCTUnwrap(part.paneUndoManager)
        undo.groupsByEvent = false
        part.list.select(ButtonsListLayout.thumbWheelRowID)
        XCTAssertTrue(part.list.removeButton.isEnabled)
        undo.beginUndoGrouping()
        part.list.removeButton.performClick(nil)
        undo.endUndoGrouping()
        XCTAssertNil(calculator.thumbWheel)
        XCTAssertNil(part.thumbWheelRow)
        XCTAssertTrue(part.list.rows.isEmpty)
        XCTAssertEqual(undo.undoActionName, "Remove Thumb Wheel")

        undo.undo()
        XCTAssertEqual(calculator.ownThumbWheelFunction, .volume)
        XCTAssertNotNil(part.thumbWheelRow)
        XCTAssertEqual(part.list.selectedID, ButtonsListLayout.thumbWheelRowID)
        undo.redo()
        XCTAssertNil(calculator.thumbWheel)
        XCTAssertNil(part.thumbWheelRow)
    }

    /// "−", the page closes, then Edit › Undo: the wheel comes back to the app although the
    /// page is gone, the list's mark follows; Redo takes it away again.
    func testUndoOfTheRemovedRowWorksAfterThePageClosedAndTheMarkFollows() throws {
        let calculator = addCalculator()
        calculator.setOwnThumbWheelFunction(.zoom)
        let pane = makePane()
        XCTAssertEqual((pane.list.rows.first as? ApplicationListRow)?.marks, [.buttons], "the Buttons mark counts the wheel")
        let undo = UndoManager()
        undo.groupsByEvent = false
        weak var closedPart: ApplicationButtonsViewController?
        try autoreleasepool {
            let part = try buttonsPart(pane: pane)
            part.paneUndoManager = undo
            undo.beginUndoGrouping()
            part.removeOwnThumbWheel()
            undo.endUndoGrouping()
            closedPart = part
            pane.leaveSubpage()
        }
        XCTAssertNil(closedPart, "the page and its parts are gone")
        XCTAssertEqual((pane.list.rows.first as? ApplicationListRow)?.marks, [])

        undo.undo()
        XCTAssertEqual(calculator.ownThumbWheelFunction, .zoom)
        XCTAssertEqual((pane.list.rows.first as? ApplicationListRow)?.marks, [.buttons])
        undo.redo()
        XCTAssertNil(calculator.thumbWheel)
        XCTAssertEqual((pane.list.rows.first as? ApplicationListRow)?.marks, [])
    }
}

// MARK: - Which function a turn runs, through the scroll tap

final class ThumbWheelTurnTests: XCTestCase {

    private static let figma = "/Applications/Figma.app"
    private static let notes = "/Applications/Notes.app"

    private var rig: ThumbWheelEngineTests.Rig!
    private var savedEngine: ThumbWheelEngine!
    private var savedThumbWheel = ThumbWheelSettings.default
    private var savedSmooth = true
    private var savedAllowlist = false
    private var savedApplications: EnhanceArray<Application>!
    /// The app in front, as the engine is told it; how often it was asked.
    private var front: FrontApp?
    private var asked = 0

    override func setUp() {
        super.setUp()
        savedApplications = Options.shared.application.applications
        savedEngine = ScrollCore.shared.thumbWheelEngine
        savedThumbWheel = Options.shared.thumbWheel
        savedSmooth = Options.shared.scroll.smooth
        savedAllowlist = Options.shared.application.allowlist
        rig = ThumbWheelEngineTests.Rig()
        rig.engine.frontApplication = { [unowned self] in
            self.asked += 1
            return self.front
        }
        ScrollCore.shared.thumbWheelEngine = rig.engine
        ScrollCore.shared.handover = ScrollHandover()
        // Not smoothed: a sideways event that scrolls goes on, one that runs a function is
        // swallowed.
        Options.shared.scroll.smooth = false
        Options.shared.application.allowlist = false
        Options.shared.thumbWheel = .default
        ScrollCore.shared.toggleScroll = false
        ScrollCore.shared.blockSmooth = false
        ScrollUtils.shared.treatAsRemoteForTests(sourcePID: nil)
        let figma = Application(path: Self.figma)
        figma.setOwnThumbWheelFunction(.volume)
        Options.shared.application.applications = EnhanceArray<Application>(
            withArray: [figma, Application(path: Self.notes)], matchKey: "path"
        )
    }

    override func tearDown() {
        ScrollCore.shared.thumbWheelEngine = savedEngine
        ScrollCore.shared.handover = ScrollHandover()
        ScrollCore.shared.isActive = false
        ScrollUtils.shared.treatAsRemoteForTests(sourcePID: nil)
        Options.shared.application.applications = savedApplications
        Options.shared.thumbWheel = savedThumbWheel
        Options.shared.scroll.smooth = savedSmooth
        Options.shared.application.allowlist = savedAllowlist
        ScrollSystemLog.resetPassthroughForTests()
        super.tearDown()
    }

    /// A sideways event of a flick (twelve lines: one step of volume) that happened `time`
    /// seconds after the rig's start, through the tap's callback. Whether it went on.
    private func turn(at time: Double, lines: Int64 = -12) throws -> Bool {
        rig.advance(to: 500 + time)
        let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 0, wheel2: 0, wheel3: 0))
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: lines)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: Double(lines))
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: Double(lines * 10))
        event.setIntegerValueField(.eventSourceUnixProcessID, value: 0)
        event.setIntegerValueField(.eventTargetUnixProcessID, value: 1)
        event.timestamp = ThumbWheelEngineTests.Rig.timestamp(time)
        return ScrollCore.shared.scrollEventCallBack(CGEventTapProxy(bitPattern: 1)!, .scrollWheel, event, nil) != nil
    }

    /// Figma (its own: volume) in front: the turn turns the volume; Notes (none of its own)
    /// in front: it scrolls, as Buttons says; Scrollio's settings in front, even over
    /// Figma's path: it scrolls; no app in front: it scrolls.
    func testATurnInTheAppUsesItsFunctionElsewhereTheGeneralOne() throws {
        front = FrontApp(bundlePath: Self.figma)
        XCTAssertFalse(try turn(at: 0), "Figma's own: swallowed, it runs volume")
        front = FrontApp(bundlePath: Self.notes)
        XCTAssertTrue(try turn(at: 1), "Notes: scrolls")
        front = FrontApp(bundlePath: Self.figma, isScrollio: true)
        XCTAssertTrue(try turn(at: 2), "Scrollio in front: scrolls")
        front = nil
        XCTAssertTrue(try turn(at: 3), "no app in front: scrolls")
        rig.advance(to: 510)
        XCTAssertEqual(rig.performed.map(\.action), [.volume(.up)])
        XCTAssertEqual(asked, 4, "once per turn")
        XCTAssertEqual(rig.lines.map(\.isAppsOwn), [true, false, false, false], "the log says when it was the app's own")
        XCTAssertEqual(rig.lines.map(\.function), [.volume, .scroll, .scroll, .scroll])
    }

    /// The general function set to something else: an app without its own runs it, Figma
    /// its own.
    func testTheGeneralFunctionRunsWhereTheAppInFrontHasNone() throws {
        Options.shared.thumbWheel = ThumbWheelSettings(function: .volume, swapsDirection: true)
        Options.shared.application.applications.get(by: Self.figma)?.setOwnThumbWheelFunction(.scroll)
        front = FrontApp(bundlePath: Self.notes)
        XCTAssertFalse(try turn(at: 0), "Notes: the general volume")
        front = FrontApp(bundlePath: Self.figma)
        XCTAssertTrue(try turn(at: 1), "Figma's own \"Default\": it scrolls there")
        rig.advance(to: 510)
        XCTAssertEqual(rig.performed.map(\.action), [.volume(.down)], "swapped: the general speed and swap stay")
    }

    /// Scrolling's Speed is set for its function: how far the wheel scrolls, or how soon the
    /// next step comes. An app's function of the other kind runs at the default speed (a
    /// general Volume at 3× made Figma's own sideways scroll three times as far); one of the
    /// same kind takes it. Swap direction is the hand's, and stays as set.
    func testAnAppsFunctionOfTheOtherKindRunsAtTheDefaultSpeed() {
        func settings(own: ThumbWheelFunction?, general: ThumbWheelSettings) -> ThumbWheelSettings {
            return ThumbWheelTurn(ownFunction: own, lastEventAt: 0).settings(general: general)
        }
        let volume = ThumbWheelSettings(function: .volume, speed: 3, swapsDirection: true)
        XCTAssertEqual(settings(own: .scroll, general: volume), ThumbWheelSettings(function: .scroll, speed: 1, swapsDirection: true))
        let slowScroll = ThumbWheelSettings(function: .scroll, speed: 0.25)
        XCTAssertEqual(settings(own: .zoom, general: slowScroll), ThumbWheelSettings(function: .zoom, speed: 1))
        XCTAssertEqual(settings(own: .tabs, general: volume), ThumbWheelSettings(function: .tabs, speed: 3, swapsDirection: true),
                       "steps, as the general function: its speed")
        XCTAssertEqual(settings(own: .volume, general: volume), volume)
        XCTAssertEqual(settings(own: nil, general: slowScroll), slowScroll)
    }

    /// A turn keeps the function it began with until the wheel rests, whatever comes to the
    /// front meanwhile (a step of "switch desktops" brings another app forward); the first
    /// event after a rest looks again.
    func testATurnKeepsItsFunctionAcrossAnAppSwitchUntilTheWheelRests() throws {
        front = FrontApp(bundlePath: Self.figma)
        XCTAssertFalse(try turn(at: 0))
        front = FrontApp(bundlePath: Self.notes)
        XCTAssertFalse(try turn(at: 0.3), "the same turn: still Figma's volume")
        XCTAssertFalse(try turn(at: 0.8), "0.5 s apart: still the same turn")
        XCTAssertEqual(asked, 1)
        XCTAssertTrue(try turn(at: 1.5), "after a rest: Notes in front, it scrolls")
        front = FrontApp(bundlePath: Self.figma)
        XCTAssertTrue(try turn(at: 1.7), "the turn began in Notes: it scrolls on")
        XCTAssertFalse(try turn(at: 2.5), "after a rest: Figma's own again")
        XCTAssertEqual(asked, 3, "once per turn")
        rig.advance(to: 510)
        XCTAssertEqual(rig.performed.map(\.action).filter { $0 == .volume(.up) }.isEmpty, false)
    }

    /// While no app on the list has a function of its own, a turn never asks which app is in
    /// front, and the wheel does what it did before.
    func testWithoutAnAppsOwnFunctionTheAppInFrontIsNeverAsked() throws {
        Options.shared.application.applications.get(by: Self.figma)?.setOwnThumbWheelFunction(nil)
        front = FrontApp(bundlePath: Self.figma)
        XCTAssertTrue(try turn(at: 0))
        XCTAssertTrue(try turn(at: 2))
        XCTAssertEqual(asked, 0)
        XCTAssertNotNil(rig.engine.turn)
        XCTAssertNil(rig.engine.turn?.ownFunction)
    }

    /// A stop (Pause, sleep, an import) forgets the turn: the next event looks again.
    func testAStopForgetsTheTurn() throws {
        front = FrontApp(bundlePath: Self.figma)
        XCTAssertFalse(try turn(at: 0))
        rig.engine.reset()
        XCTAssertNil(rig.engine.turn)
        front = FrontApp(bundlePath: Self.notes)
        XCTAssertTrue(try turn(at: 0.1), "a new turn: Notes in front")
    }
}
