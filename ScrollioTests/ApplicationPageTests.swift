//
//  ApplicationPageTests.swift
//  ScrollioTests
//
//  An app's page in parts (Scrolling, Buttons, Gestures, Shortcut Ring: one at a time
//  under the app's box, the one shown last remembered for every app, a part that does not
//  exist falling back to Scrolling, the page's height following the part), the marks of
//  the list of apps, the Buttons part: only the app's own rows with what they do
//  everywhere, the "+" menu, changing, recording and removing a row, and what stays
//  general; and the Gestures part: the switch, the app's own five rows and invert switch.
//  Nothing is shown on screen: menus and recorders go through seams, windows are never
//  ordered in.
//

import XCTest
@testable import Scrollio_Debug

final class ApplicationPageTests: XCTestCase {

    private static let calculator = "/System/Applications/Calculator.app"
    private static let textEdit = "/System/Applications/TextEdit.app"

    private var savedApplications: EnhanceArray<Application>!
    private var savedBindings: [ButtonBinding] = []
    private var savedScroll: OPTIONS_SCROLL_DEFAULT!
    private var savedRing = ShortcutRingSettings.default
    private var savedGesture = MouseGestureSettings.default
    private var uiDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        savedApplications = Options.shared.application.applications
        savedBindings = Options.shared.buttons.binding
        savedScroll = Options.shared.scroll
        savedRing = Options.shared.ring
        savedGesture = Options.shared.gesture
        Options.shared.gesture = .default
        Options.shared.application.applications = Self.makeStore([])
        Options.shared.buttons.binding = []
        Options.shared.scroll = OPTIONS_SCROLL_DEFAULT()
        Options.shared.ring = .default
        ButtonUtils.shared.invalidateCache()
        uiDefaults = TestDefaults.make(for: self)
        uiDefaults.set(false, forKey: PreferencesScrollingViewController.advancedExpandedDefaultsKey)
    }

    override func tearDown() {
        Options.shared.application.applications = savedApplications
        Options.shared.buttons.binding = savedBindings
        Options.shared.scroll = savedScroll
        Options.shared.ring = savedRing
        Options.shared.gesture = savedGesture
        ShortcutRingController.forgetPreparedFaces()
        ButtonUtils.shared.invalidateCache()
        savedApplications = nil
        savedScroll = nil
        uiDefaults = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private static func makeStore(_ applications: [Application]) -> EnhanceArray<Application> {
        return EnhanceArray<Application>(
            withArray: applications, matchKey: "path", forObserver: { Options.shared.markChanged(.application) }
        )
    }

    /// The Apps pane as the window makes it, with nothing shown on screen.
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
    private func addApp(_ path: String, inherit: Bool = true) -> Application {
        let application = Application(path: path)
        application.inherit = inherit
        Options.shared.application.applications.append(application)
        return application
    }

    private func binding(_ code: UInt16, _ action: String, modifiers: UInt = 0, type: EventType = .mouse) -> ButtonBinding {
        return ButtonBinding(
            triggerEvent: RecordedEvent(type: type, code: code, modifiers: modifiers, deviceFilter: nil),
            systemShortcutName: action,
            isEnabled: true
        )
    }

    private func send(_ control: NSControl, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(control.sendAction(control.action, to: control.target), file: file, line: line)
    }

    private func choose(_ index: Int, on page: ApplicationDetailViewController) {
        page.partControl.selectedSegment = index
        send(page.partControl)
    }

    private func allSubviews(of view: NSView) -> [NSView] {
        return view.subviews.flatMap { [$0] + allSubviews(of: $0) }
    }

    /// A mouse for the Buttons part: its name, and what "+" of Buttons records for a part.
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

    /// The Buttons part of Calculator's page, on an MX Master 3S, with menus caught.
    private func buttonsPart(
        menus: ((NSMenu) -> Void)? = nil, actionMenus: ((NSPopUpButton) -> Void)? = nil
    ) throws -> (ApplicationDetailViewController, ApplicationButtonsViewController) {
        let pane = makePane()
        pane.openApplication(withID: Self.calculator, part: .buttons)
        let page = try XCTUnwrap(pane.detailController)
        let part = try XCTUnwrap(page.buttonsPart)
        part.deviceSource = mouse("MX Master 3S")
        part.presentMenu = { menu, _ in menus?(menu) }
        part.openActionMenu = { actionMenus?($0) }
        part.startRecording = { _ in }
        part.stopRecording = {}
        part.presentOpenTarget = { _, _, _ in }
        part.paneUndoManager = UndoManager()
        part.reloadRows()
        return (page, part)
    }

    private func titles(of menu: NSMenu) -> [String] {
        return menu.items.map { $0.isSeparatorItem ? "—" : $0.title }
    }

    // MARK: - The parts

    /// The page shows the app's box, then the control with the four parts in the sidebar's
    /// order, then one part at a time: Scrolling first, with "Use settings from Scrolling"
    /// on top of it.
    func testThePageShowsOnePartAtATimeUnderTheAppsBox() throws {
        addApp(Self.calculator)
        let pane = makePane()
        pane.openApplication(withID: Self.calculator)
        let page = try XCTUnwrap(pane.detailController)
        page.view.layoutSubtreeIfNeeded()

        XCTAssertEqual(page.partControl.segmentCount, 4)
        XCTAssertEqual((0..<4).map { page.partControl.label(forSegment: $0) }, ["Scrolling", "Buttons", "Gestures", "Shortcut Ring"])
        XCTAssertEqual(page.partControl.trackingMode, .selectOne)
        XCTAssertEqual(page.shownPart, .scrolling)
        XCTAssertEqual(page.partControl.selectedSegment, 0)
        XCTAssertEqual(page.headerSection.box.visibleRows.count, 1, "the box holds the app alone")
        XCTAssertTrue(page.scrollingPart.view.isDescendant(of: page.partContainer))
        XCTAssertTrue(page.inheritRow.isDescendant(of: page.scrollingPart.view), "Use settings from Scrolling is Scrolling's")
        XCTAssertNil(page.buttonsPart.view.superview)
        XCTAssertNil(page.gesturesPart.view.superview)
        XCTAssertNil(page.ringPart.view.superview)
        XCTAssertFalse(page.view.hasAmbiguousLayout)
        XCTAssertGreaterThan(page.headerSection.frame.minY, page.partControl.frame.maxY, "the control under the box")
        XCTAssertEqual(page.partControl.frame.midX, page.view.bounds.midX, accuracy: 1)

        choose(1, on: page)
        XCTAssertEqual(page.shownPart, .buttons)
        XCTAssertTrue(page.buttonsPart.view.isDescendant(of: page.partContainer))
        XCTAssertNil(page.scrollingPart.view.superview)
        choose(2, on: page)
        XCTAssertEqual(page.shownPart, .gestures)
        XCTAssertTrue(page.gesturesPart.generalGesturesRow.isDescendant(of: page.partContainer))
        XCTAssertNil(page.gesturesPart.generalSection.titleLabel, "the segment names it")
        choose(3, on: page)
        XCTAssertEqual(page.shownPart, .ring)
        XCTAssertTrue(page.generalRingRow.isDescendant(of: page.partContainer))
        XCTAssertNil(page.ringSection.titleLabel, "the segment names it")
        XCTAssertEqual(page.partContainer.subviews.count, 1)
    }

    /// The part shown last is shown again, on any app's page; one that does not exist
    /// (from another version) is Scrolling.
    func testThePartShownLastIsRememberedForEveryAppAndAMissingOneIsScrolling() throws {
        addApp(Self.calculator)
        addApp(Self.textEdit)
        let pane = makePane()
        pane.openApplication(withID: Self.calculator)
        choose(3, on: try XCTUnwrap(pane.detailController))
        XCTAssertEqual(uiDefaults.string(forKey: ApplicationPagePart.shownDefaultsKey), "ring")
        pane.leaveSubpage()
        pane.openApplication(withID: Self.textEdit)
        XCTAssertEqual(pane.detailController?.shownPart, .ring, "another app opens on the same part")

        uiDefaults.set("keys", forKey: ApplicationPagePart.shownDefaultsKey)
        pane.leaveSubpage()
        pane.openApplication(withID: Self.calculator)
        XCTAssertEqual(pane.detailController?.shownPart, .scrolling)
        XCTAssertEqual(ApplicationPagePart.part(withID: nil), .scrolling)
        XCTAssertEqual(ApplicationPagePart.all.map(\.id), ["scrolling", "buttons", "gestures", "ring"])
    }

    /// The pane takes the height of the part shown, at each change.
    func testThePagesHeightFollowsThePartShown() throws {
        addApp(Self.calculator)
        let pane = makePane()
        pane.openApplication(withID: Self.calculator)
        let page = try XCTUnwrap(pane.detailController)
        var changes = 0
        let original = page.onHeightChange
        page.onHeightChange = {
            changes += 1
            original?()
        }
        let scrolling = pane.view.frame.height
        XCTAssertEqual(scrolling, page.view.fittingSize.height, accuracy: 0.5)

        choose(1, on: page)
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(pane.view.frame.height, page.view.fittingSize.height, accuracy: 0.5)
        XCTAssertLessThan(pane.view.frame.height, scrolling - 200, "an empty Buttons part is short")

        choose(2, on: page)
        let gestures = pane.view.frame.height
        XCTAssertEqual(gestures, page.view.fittingSize.height, accuracy: 0.5)
        page.gesturesPart.generalGesturesSwitch.state = .off
        send(page.gesturesPart.generalGesturesSwitch)
        XCTAssertGreaterThan(pane.view.frame.height, gestures + 200, "the app's own rows under the switch")
        XCTAssertEqual(pane.view.frame.height, page.view.fittingSize.height, accuracy: 0.5)

        choose(3, on: page)
        let ring = pane.view.frame.height
        XCTAssertEqual(ring, page.view.fittingSize.height, accuracy: 0.5)
        page.generalRingSwitch.state = .off
        send(page.generalRingSwitch)
        XCTAssertGreaterThan(pane.view.frame.height, ring + 200, "the app's own ring under the switch")
        XCTAssertEqual(pane.view.frame.height, page.view.fittingSize.height, accuracy: 0.5)

        choose(0, on: page)
        XCTAssertEqual(pane.view.frame.height, scrolling, accuracy: 0.5)
    }

    /// The Buttons part's line under the list is a plain sentence that fits two lines, also
    /// for an app with a long name.
    func testTheButtonsPartsLineFitsTwoLines() throws {
        let long = addApp(Self.calculator)
        long.displayName = "An Application With A Remarkably Long Name For Its Kind"
        let pane = makePane()
        pane.openApplication(withID: Self.calculator, part: .buttons)
        let page = try XCTUnwrap(pane.detailController)
        page.view.layoutSubtreeIfNeeded()
        let label = try XCTUnwrap(page.buttonsPart.noteLabel)
        let font = PreferencesGroupedForm.explanationFont
        let twoLines = 2 * ceil(font.ascender - font.descender + font.leading) + 2
        XCTAssertGreaterThan(label.frame.width, 300)
        for isEmpty in [true, false] {
            let text = ApplicationButtonsViewController.note(for: long.displayName!, isEmpty: isEmpty)
            XCTAssertTrue(text.contains(long.displayName!))
            XCTAssertTrue(text.hasSuffix("."))
            let height = (text as NSString).boundingRect(
                with: NSSize(width: label.frame.width, height: 1000), options: [.usesLineFragmentOrigin], attributes: [.font: font]
            ).height
            XCTAssertLessThanOrEqual(height, twoLines, text)
        }
    }

    // MARK: - The marks of the list

    /// A mark per kind the app has of its own, in the order of the parts, none when nothing
    /// differs; each says what it is to VoiceOver and in its tooltip; computed from the app.
    func testTheListMarksWhatAnAppHasOfItsOwn() throws {
        let plain = addApp(Self.textEdit)
        let own = addApp(Self.calculator, inherit: false)
        own.setOwnButtonBindings([binding(3, "copy")])
        own.setUsesGeneralRing(false, general: .default)
        own.setUsesGeneralGestures(false, general: .default)
        let pane = makePane()
        let rows = pane.list.rows.compactMap { $0 as? ApplicationListRow }
        XCTAssertEqual(rows.count, 2)
        let plainRow = try XCTUnwrap(rows.first { $0.id == AnyHashable(plain.path) })
        let ownRow = try XCTUnwrap(rows.first { $0.id == AnyHashable(own.path) })
        XCTAssertTrue(plainRow.marks.isEmpty)
        XCTAssertTrue(plainRow.markViews.isEmpty)
        XCTAssertEqual(ownRow.marks, [.scrolling, .buttons, .gestures, .ring])
        XCTAssertEqual(ownRow.markViews.map(\.toolTip), ["Own scrolling settings", "Own button settings", "Own gestures", "Own Shortcut Ring"])
        XCTAssertEqual(ownRow.markViews.first?.contentTintColor, .tertiaryLabelColor)
        XCTAssertTrue(ownRow.accessibilityLabel()?.hasSuffix(
            "Own scrolling settings, Own button settings, Own gestures, Own Shortcut Ring"
        ) == true, ownRow.accessibilityLabel() ?? "")
        XCTAssertEqual(ApplicationPagePart.ownSettings(of: plain), [])

        // Only what the app has: buttons alone.
        own.inherit = true
        own.setUsesGeneralRing(true, general: .default)
        own.setUsesGeneralGestures(true, general: .default)
        pane.reloadRows()
        let again = try XCTUnwrap(pane.list.rows.compactMap { $0 as? ApplicationListRow }.first { $0.id == AnyHashable(own.path) })
        XCTAssertEqual(again.marks, [.buttons])
        XCTAssertEqual(again.accessibilityLabel(), "Calculator, Uses your scrolling settings., Own button settings")
    }

    /// A click on a mark opens the app's page on that part; the marks follow a change made
    /// on the page when the list shows again.
    func testAClickOnAMarkOpensThePageOnItsPart() throws {
        let own = addApp(Self.calculator, inherit: false)
        own.setOwnButtonBindings([binding(3, "copy")])
        let pane = makePane()
        let window = makeWindow(for: pane)
        let row = try XCTUnwrap(pane.list.rows.first as? ApplicationListRow)
        row.layoutSubtreeIfNeeded()
        XCTAssertEqual(row.marks, [.scrolling, .buttons])
        let mark = row.markViews[1]
        let middle = row.convert(NSPoint(x: mark.bounds.midX, y: mark.bounds.midY), from: mark)
        XCTAssertEqual(row.mark(at: middle), .buttons)
        XCTAssertFalse(row.isChevronHit(at: middle))
        row.mouseDown(with: try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown, location: row.convert(middle, to: nil), modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        )))
        let page = try XCTUnwrap(pane.detailController)
        XCTAssertEqual(page.shownPart, .buttons)

        // The app's buttons go on the page: back in the list, no mark of buttons.
        page.buttonsPart.paneUndoManager = UndoManager()
        page.buttonsPart.removeOwnBinding(id: own.ownButtonBindings[0].id)
        pane.leaveSubpage()
        XCTAssertEqual((pane.list.rows.first as? ApplicationListRow)?.marks, [.scrolling])
    }

    // MARK: - The Buttons part

    /// Only the app's own rows, each a row of the Buttons pane with what the button does
    /// everywhere else under it; "Default" for one that does what it does by itself here.
    /// The menus have neither the ring nor Gesture Navigation.
    func testTheButtonsPartShowsOnlyTheAppsOwnRowsWithWhatTheyDoEverywhere() throws {
        Options.shared.buttons.binding = [binding(3, "missionControl"), binding(4, "copy"), binding(5, "paste")]
        let calculator = addApp(Self.calculator)
        calculator.setOwnButtonBindings([binding(3, "appExpose"), binding(1000, "")])
        let (_, part) = try buttonsPart()

        XCTAssertEqual(part.rows.count, 2, "the app's own rows only")
        XCTAssertEqual(part.rows.map(\.explanation), ["Everywhere: Mission Control", "Everywhere: Default"])
        XCTAssertEqual(part.rows[0].pullDown.menu?.items.first?.title, SystemShortcut.appExpose.localizedName)
        XCTAssertEqual(part.rows[1].pullDown.menu?.items.first?.title, "Default")
        XCTAssertEqual(part.rows[1].pullDown.noActionItem?.title, "Default")
        XCTAssertTrue(part.rows.allSatisfy { $0.isRemovable && $0.isEnabled })
        XCTAssertTrue(part.rows.allSatisfy { $0.placeButton.isHidden }, "where a button is, Buttons says")
        for row in part.rows {
            let hidden = row.pullDown.menu?.items.filter(\.isHidden).compactMap { $0.representedObject as? SystemShortcut.Shortcut }.map(\.identifier)
            XCTAssertEqual(Set(hidden ?? []), [SystemShortcut.shortcutRing.identifier, SystemShortcut.mouseGestureNavigation.identifier])
        }
        XCTAssertEqual(part.list.rowsView.accessibilityLabel(), "Own buttons")
        XCTAssertEqual(part.noteLabel.stringValue,
                       "These buttons do this while Calculator is in front; every other button does what Buttons says.")
    }

    /// An app without buttons of its own: the list says in one line that every button does
    /// what Buttons says.
    func testAnEmptyButtonsPartSaysEveryButtonDoesWhatButtonsSays() throws {
        Options.shared.buttons.binding = [binding(3, "missionControl")]
        addApp(Self.calculator)
        let (_, part) = try buttonsPart()
        XCTAssertTrue(part.rows.isEmpty)
        XCTAssertEqual(part.list.emptyRow.title, "Every button does what Buttons says.")
        XCTAssertNil(part.list.emptyRow.explanation, "one line")
        XCTAssertEqual(part.noteLabel.stringValue, "Click + to give a button something else to do while Calculator is in front.")
        part.addOwnBinding(for: RecordedEvent(type: .mouse, code: 3, modifiers: 0, deviceFilter: nil))
        XCTAssertEqual(part.noteLabel.stringValue,
                       "These buttons do this while Calculator is in front; every other button does what Buttons says.")
    }

    /// "+": the buttons of the connected mouse the app has no binding of its own for,
    /// "Record a Button or Key…", then the bindings of Buttons not offered yet, never what
    /// opens the ring or runs Gesture Navigation.
    func testThePlusMenuOffersTheMouseRecordingAndTheBindingsOfButtons() throws {
        let command = UInt(CGEventFlags.maskCommand.rawValue)
        Options.shared.buttons.binding = [
            binding(3, "missionControl"), binding(1001, SystemShortcut.shortcutRing.identifier),
            binding(5, "copy", modifiers: command), binding(6, SystemShortcut.mouseGestureNavigation.identifier),
            binding(40, "paste", modifiers: command, type: .keyboard),
        ]
        let calculator = addApp(Self.calculator)
        calculator.setOwnButtonBindings([binding(4, "undo")])
        var shown: NSMenu?
        let (_, part) = try buttonsPart(menus: { shown = $0 })
        part.showAddMenu(from: part.list.addButton)
        let menu = try XCTUnwrap(shown)
        let names = titles(of: menu)
        // The MX Master 3S: wheel button, mode shift button (the ring's: left out),
        // forward (the app's own already), back, gesture button.
        XCTAssertEqual(menu.items.first?.isSectionHeader, true)
        XCTAssertEqual(names.first, "Your Mouse")
        XCTAssertTrue(names.contains(ButtonTriggerNaming.title(for: RecordedEvent(type: .mouse, code: 2, modifiers: 0, deviceFilter: nil))))
        XCTAssertTrue(names.contains(ButtonTriggerNaming.title(for: RecordedEvent(type: .mouse, code: 3, modifiers: 0, deviceFilter: nil))))
        XCTAssertTrue(names.contains(ButtonTriggerNaming.title(for: RecordedEvent(type: .mouse, code: 1000, modifiers: 0, deviceFilter: nil))),
                      "a Logitech button no binding of Buttons uses: \(names)")
        XCTAssertFalse(names.contains(ButtonTriggerNaming.title(for: RecordedEvent(type: .mouse, code: 1001, modifiers: 0, deviceFilter: nil))))
        XCTAssertFalse(names.contains(ButtonTriggerNaming.title(for: RecordedEvent(type: .mouse, code: 4, modifiers: 0, deviceFilter: nil))))
        XCTAssertTrue(names.contains("Record a Button or Key…"))
        let general = try XCTUnwrap(names.firstIndex(of: "In Buttons"))
        let rest = Array(names[(general + 1)...])
        XCTAssertEqual(rest.count, 2, "⌘ and button 5, ⌘ and a key; not the back button (offered above), not the ring's or the gestures': \(rest)")
        XCTAssertTrue(rest.allSatisfy { $0.hasSuffix(": " + SystemShortcut.copy.localizedName) || $0.hasSuffix(": " + SystemShortcut.paste.localizedName) }, "\(rest)")
    }

    /// Choosing a button adds its row with the action it has everywhere (nothing changes
    /// until another is chosen), selected, and its menu opens; Buttons is not touched.
    func testChoosingAButtonAddsItsRowWithTheGeneralActionAndOpensItsMenu() throws {
        Options.shared.buttons.binding = [binding(3, "missionControl")]
        let general = Options.shared.buttons.binding
        let calculator = addApp(Self.calculator)
        var shown: NSMenu?
        var opened: [NSPopUpButton] = []
        let (_, part) = try buttonsPart(menus: { shown = $0 }, actionMenus: { opened.append($0) })
        let window = makeWindow(for: part)
        _ = window
        part.showAddMenu(from: part.list.addButton)
        let back = try XCTUnwrap(shown?.items.first { $0.title == ButtonTriggerNaming.title(for: general[0].triggerEvent) })
        part.addChosen(back)

        XCTAssertEqual(calculator.ownButtonBindings.map(\.systemShortcutName), ["missionControl"])
        XCTAssertEqual(calculator.ownButtonBindings.first?.triggerEvent, general[0].triggerEvent)
        XCTAssertNotEqual(calculator.ownButtonBindings.first?.id, general[0].id, "a binding of its own")
        XCTAssertEqual(Options.shared.buttons.binding, general)
        XCTAssertEqual(part.rows.count, 1)
        XCTAssertEqual(part.list.selectedID, AnyHashable(calculator.ownButtonBindings[0].id))
        let opens = expectation(description: "the row's menu opens")
        DispatchQueue.main.async { opens.fulfill() }
        wait(for: [opens], timeout: 1)
        XCTAssertTrue(opened.first === part.rows.first?.pullDown)

        // A Logitech button without a binding of Buttons: "Default" until one is chosen.
        let gesture = try XCTUnwrap(part.makeAddMenu().items.first {
            $0.title == ButtonTriggerNaming.title(for: RecordedEvent(type: .mouse, code: 1000, modifiers: 0, deviceFilter: nil))
        })
        part.addChosen(gesture)
        XCTAssertEqual(calculator.ownButtonBindings.last?.systemShortcutName, "")
        XCTAssertEqual(calculator.ownButtonBindings.last?.isEnabled, true)
    }

    /// A row's pull-down changes the app's binding only; "Default" stores no action (the
    /// button does what it does by itself here); the ring is refused.
    func testARowsPullDownChangesOnlyTheAppsBinding() throws {
        Options.shared.buttons.binding = [binding(3, "missionControl")]
        let general = Options.shared.buttons.binding
        let calculator = addApp(Self.calculator)
        calculator.setOwnButtonBindings([binding(3, "appExpose")])
        let (_, part) = try buttonsPart()
        let row = try XCTUnwrap(part.rows.first)

        row.pullDown.onShortcutSelected?(SystemShortcut.copy)
        XCTAssertEqual(calculator.ownButtonBindings.map(\.systemShortcutName), ["copy"])
        XCTAssertEqual(part.rows.first?.pullDown.menu?.items.first?.title, SystemShortcut.copy.localizedName)
        row.pullDown.onShortcutSelected?(nil)
        XCTAssertEqual(calculator.ownButtonBindings.first?.systemShortcutName, "")
        XCTAssertEqual(calculator.ownButtonBindings.first?.isEnabled, true)
        XCTAssertEqual(part.rows.first?.pullDown.menu?.items.first?.title, "Default")
        row.pullDown.onCustomShortcutRecorded?("custom::40:1048576", ShortcutLabel(name: "Find", icon: nil))
        XCTAssertEqual(calculator.ownButtonBindings.first?.label?.name, "Find")
        part.setAction(of: row.binding.id, named: SystemShortcut.shortcutRing.identifier)
        XCTAssertEqual(calculator.ownButtonBindings.first?.systemShortcutName, "custom::40:1048576", "the ring stays general")
        XCTAssertEqual(Options.shared.buttons.binding, general)
        XCTAssertTrue(part.rows.first?.pullDown.menu?.items.first { ($0.representedObject as? SystemShortcut.Shortcut)?.identifier == SystemShortcut.shortcutRing.identifier }?.isHidden == true,
                      "hidden again after the pull-down showed the new action")
    }

    /// "−" gives the button back to Buttons (nothing is stored once none is left); Undo
    /// takes it again, Redo gives it back.
    func testRemovingARowGivesTheButtonBackAndUndoTakesItAgain() throws {
        let calculator = addApp(Self.calculator)
        calculator.setOwnButtonBindings([binding(3, "appExpose")])
        let (_, part) = try buttonsPart()
        let undo = try XCTUnwrap(part.paneUndoManager)
        let id = calculator.ownButtonBindings[0].id
        part.list.select(AnyHashable(id))
        undo.beginUndoGrouping()
        part.list.removeButton.performClick(nil)
        undo.endUndoGrouping()
        XCTAssertNil(calculator.buttons)
        XCTAssertTrue(part.rows.isEmpty)
        XCTAssertEqual(undo.undoActionName, "Remove Button")
        undo.undo()
        XCTAssertEqual(calculator.ownButtonBindings.map(\.systemShortcutName), ["appExpose"])
        XCTAssertEqual(part.list.selectedID, AnyHashable(id))
        undo.redo()
        XCTAssertFalse(calculator.hasOwnButtons)
    }

    /// "−" on the page, then the page closes (Esc, the back button, another pane), then
    /// Edit › Undo: the button comes back to the app although the page's part is gone, the
    /// list's mark follows, and Redo takes the button away again.
    func testUndoOfARemovedRowWorksAfterThePageClosed() throws {
        let calculator = addApp(Self.calculator)
        calculator.setOwnButtonBindings([binding(3, "appExpose")])
        let pane = makePane()
        let undo = UndoManager()
        undo.groupsByEvent = false
        weak var closedPart: ApplicationButtonsViewController?
        try autoreleasepool {
            pane.openApplication(withID: Self.calculator, part: .buttons)
            let part = try XCTUnwrap(pane.detailController?.buttonsPart)
            part.paneUndoManager = undo
            undo.beginUndoGrouping()
            part.removeOwnBinding(id: calculator.ownButtonBindings[0].id)
            undo.endUndoGrouping()
            closedPart = part
            pane.leaveSubpage()
        }
        XCTAssertNil(closedPart, "the page and its parts are gone")
        XCTAssertEqual((pane.list.rows.first as? ApplicationListRow)?.marks, [])

        undo.undo()
        XCTAssertEqual(calculator.ownButtonBindings.map(\.systemShortcutName), ["appExpose"])
        XCTAssertEqual((pane.list.rows.first as? ApplicationListRow)?.marks, [.buttons], "the list's mark follows")
        undo.redo()
        XCTAssertFalse(calculator.hasOwnButtons)
        XCTAssertEqual((pane.list.rows.first as? ApplicationListRow)?.marks, [])
    }

    /// "Record a Button or Key…": the Buttons pane's recorder; what it caught is added when
    /// it closes. A button the app has already is a duplicate; what opens the ring is
    /// refused, and the recorder says why.
    func testRecordingAddsAButtonAndRefusesWhatStaysGeneral() throws {
        Options.shared.buttons.binding = [binding(6, SystemShortcut.shortcutRing.identifier)]
        let calculator = addApp(Self.calculator)
        calculator.setOwnButtonBindings([binding(3, "appExpose")])
        var started = 0
        let (_, part) = try buttonsPart()
        part.startRecording = { _ in started += 1 }
        let menu = part.makeAddMenu()
        part.addChosen(try XCTUnwrap(menu.items.first { $0.title == "Record a Button or Key…" }))
        XCTAssertEqual(started, 1)
        let recorder = KeyRecorder()
        func press(_ code: UInt16) -> InputEvent {
            return InputEvent(type: .mouse, code: code, modifiers: [], phase: .down, source: .hidPP, device: nil)
        }
        part.onRecordingStarted(recorder)
        XCTAssertFalse(part.validateRecordedEvent(recorder, event: press(3)), "the app's already")
        XCTAssertNil(part.refusalHint(recorder, event: press(3)), "a duplicate")
        XCTAssertFalse(part.validateRecordedEvent(recorder, event: press(6)))
        XCTAssertEqual(part.refusalHint(recorder, event: press(6)), "This button stays as Buttons sets it")
        XCTAssertTrue(part.validateRecordedEvent(recorder, event: press(5)))
        part.onEventRecorded(recorder, didRecordEvent: press(5), isDuplicate: false)
        part.onRecordingStopped(recorder, didRecord: true)
        XCTAssertEqual(calculator.ownButtonBindings.map(\.triggerEvent.code), [3, 5])
        XCTAssertEqual(calculator.ownButtonBindings.last?.systemShortcutName, "", "no action of Buttons: Default")
        XCTAssertFalse(part.isRecorderOpen)
    }

    /// A binding of the app's own on a button that Buttons later gave the ring stays
    /// stored, dimmed, and is not used.
    func testARowOnAButtonThatNowStaysGeneralIsDimmed() throws {
        let calculator = addApp(Self.calculator)
        calculator.setOwnButtonBindings([binding(3, "appExpose")])
        Options.shared.buttons.binding = [binding(3, SystemShortcut.mouseGestureNavigation.identifier)]
        let (_, part) = try buttonsPart()
        XCTAssertEqual(part.rows.first?.isEnabled, false)
        XCTAssertEqual(part.rows.first?.explanation, "Everywhere: " + SystemShortcut.mouseGestureNavigation.localizedName)
    }

    // MARK: - The Gestures part

    /// Calculator's page on its Gestures part, with the menus' Logitech actions off.
    private func gesturesPart(
        interactiveAvailable: Bool = false
    ) throws -> (PreferencesApplicationViewController, ApplicationGesturesPartViewController) {
        let pane = makePane()
        pane.openApplication(withID: Self.calculator, part: .gestures)
        let part = try XCTUnwrap(pane.detailController?.gesturesPart)
        part.showsLogiActions = { false }
        part.isInteractiveAvailable = { interactiveAvailable }
        part.syncViewWithOptions()
        return (pane, part)
    }

    private func everything(in menu: NSMenu?) -> [NSMenuItem] {
        return (menu?.items ?? []).flatMap { [$0] + everything(in: $0.submenu) }
    }

    /// While the app uses the general gestures the part is the switch alone, which says so.
    func testTheGesturesPartIsTheSwitchAloneWhileTheAppUsesTheGeneralGestures() throws {
        let calculator = addApp(Self.calculator)
        let (_, part) = try gesturesPart()
        XCTAssertTrue(part.generalGesturesRow.isOn)
        XCTAssertEqual(part.generalGesturesRow.explanation, "While Calculator is in front, the general gestures run.")
        XCTAssertNil(part.controls)
        XCTAssertTrue(part.directionRows.isEmpty)
        XCTAssertNil(part.directionsSection)
        XCTAssertNil(part.invertRow)
        XCTAssertFalse(part.view.subviews.flatMap { allSubviews(of: $0) }.contains { $0 is ButtonActionPullDown })
        XCTAssertNil(calculator.gestures, "nothing is stored for it")
    }

    /// Off: the app's own set, a copy of the general actions and invert switch as they are
    /// then, in the five rows of the Gestures pane and the invert switch; the list marks
    /// it. On again: the rows go, the set is kept for later and comes back as it was left.
    func testTurningTheSwitchOffShowsACopyOfTheGeneralGestures() throws {
        let calculator = addApp(Self.calculator)
        Options.shared.gesture.actions.up = GestureAction(SystemShortcut.copy)
        Options.shared.gesture.invertHorizontal = true
        let (pane, part) = try gesturesPart()
        part.generalGesturesSwitch.state = .off
        send(part.generalGesturesSwitch)

        XCTAssertFalse(calculator.usesGeneralGestures)
        XCTAssertEqual(calculator.ownGestures?.actions, Options.shared.gesture.actions)
        XCTAssertEqual(calculator.ownGestures?.invertHorizontal, true)
        XCTAssertEqual(part.generalGesturesRow.explanation, "While Calculator is in front, the gestures below run.")
        let controls = try XCTUnwrap(part.controls)
        XCTAssertEqual(part.directionRows.map(\.title), ["Up", "Down", "Left", "Right", "Click"])
        XCTAssertEqual(part.directionsSection?.titleLabel?.stringValue, "Directions")
        for slot in MouseGestureSettingsControls.Slot.allCases {
            let popup = controls.actionPopUp(for: slot)
            XCTAssertTrue(popup.isDescendant(of: part.directionRows[slot.rawValue]), slot.name)
            XCTAssertTrue(popup.isEnabled, slot.name)
            XCTAssertEqual(popup.use, .gesture(showsLogiActions: false), "the Gestures pane's menu")
        }
        XCTAssertEqual(controls.actionPopUp(for: .up).menu?.items.first?.title, SystemShortcut.copy.localizedName)
        XCTAssertEqual(part.invertRow?.title, "Invert left and right")
        XCTAssertTrue(controls.invertToggle.isDescendant(of: try XCTUnwrap(part.invertRow)))
        XCTAssertEqual((controls.invertToggle as? NSSwitch)?.state, .on)
        XCTAssertFalse(part.view.hasAmbiguousLayout)
        pane.leaveSubpage()
        XCTAssertEqual((pane.list.rows.first as? ApplicationListRow)?.marks, [.gestures], "the mark of the list")

        pane.openApplication(withID: Self.calculator, part: .gestures)
        let again = try XCTUnwrap(pane.detailController?.gesturesPart)
        XCTAssertFalse(again.generalGesturesRow.isOn)
        calculator.setOwnGestures(actions: GestureActions.default, invertHorizontal: false)
        again.generalGesturesSwitch.state = .on
        send(again.generalGesturesSwitch)
        XCTAssertNil(again.controls)
        XCTAssertTrue(again.directionRows.isEmpty)
        XCTAssertTrue(calculator.usesGeneralGestures)
        XCTAssertEqual(calculator.gestures?.actions, GestureActions.default, "kept for later")
        pane.leaveSubpage()
        XCTAssertEqual((pane.list.rows.first as? ApplicationListRow)?.marks, [])

        pane.openApplication(withID: Self.calculator, part: .gestures)
        let third = try XCTUnwrap(pane.detailController?.gesturesPart)
        third.generalGesturesSwitch.state = .off
        send(third.generalGesturesSwitch)
        XCTAssertEqual(calculator.ownGestures?.actions, GestureActions.default, "as it was left, not a new copy")
        XCTAssertEqual(third.controls?.actionPopUp(for: .up).menu?.items.first?.title, SystemShortcut.missionControl.localizedName)
    }

    /// A row of the part changes the app's set and nothing of the general gestures: a
    /// listed action, "Keyboard Shortcut…" with a name and an icon, the invert switch.
    func testARowChangesTheAppsSetNotTheGeneralOne() throws {
        let calculator = addApp(Self.calculator)
        let (_, part) = try gesturesPart()
        part.generalGesturesSwitch.state = .off
        send(part.generalGesturesSwitch)
        let general = Options.shared.gesture
        let controls = try XCTUnwrap(part.controls)

        let down = controls.actionPopUp(for: .down)
        let paste = try XCTUnwrap(everything(in: down.menu).first {
            ($0.representedObject as? SystemShortcut.Shortcut)?.identifier == SystemShortcut.paste.identifier
        })
        down.shortcutSelected(paste)
        XCTAssertEqual(calculator.ownGestures?.actions.down, GestureAction(SystemShortcut.paste))
        XCTAssertEqual(down.menu?.items.first?.title, SystemShortcut.paste.localizedName)

        let up = controls.actionPopUp(for: .up)
        XCTAssertNotNil(everything(in: up.menu).first {
            $0.representedObject as? String == ShortcutManager.MenuMarker.keyboardShortcut
        }, "Keyboard Shortcut…")
        let reload = ShortcutLabel(name: "Reload", icon: .symbol("arrow.clockwise"))
        up.onCustomShortcutRecorded?("custom::15:1179648", reload)
        XCTAssertEqual(calculator.ownGestures?.actions.up, GestureAction(action: "custom::15:1179648", label: reload))
        let keys = ButtonTriggerNaming.shortcutText(
            type: .keyboard, code: 15, modifiers: UInt64(CGEventFlags.maskShift.rawValue | CGEventFlags.maskCommand.rawValue)
        )
        XCTAssertEqual(up.menu?.items.first?.title, "Reload  \(keys)")
        XCTAssertNotNil(up.menu?.items.first?.image)
        // What a direction cannot run is not stored.
        up.onCustomShortcutRecorded?("custom::56:0", nil)
        XCTAssertEqual(calculator.ownGestures?.actions.up.label, reload)

        let invert = try XCTUnwrap(controls.invertToggle as? NSSwitch)
        invert.state = .on
        send(invert)
        XCTAssertEqual(calculator.ownGestures?.invertHorizontal, true)

        XCTAssertEqual(Options.shared.gesture, general, "the general gestures are untouched")
        XCTAssertFalse(calculator.usesGeneralGestures)
    }

    /// While the desktop follows the hand (the general mode), Left and Right are dimmed and
    /// say so, as in the Gestures pane; what they hold stays and comes back in the other mode.
    func testFollowingTheHandDimsLeftAndRightAsThePaneDoes() throws {
        let calculator = addApp(Self.calculator)
        calculator.setUsesGeneralGestures(false, general: .default)
        Options.shared.gesture.mode = .interactive
        let (_, part) = try gesturesPart(interactiveAvailable: true)
        let controls = try XCTUnwrap(part.controls)
        for slot in MouseGestureSettingsControls.Slot.allCases {
            XCTAssertEqual(part.directionRows[slot.rawValue].isEnabled, !slot.isHorizontal, slot.name)
            XCTAssertEqual(controls.actionPopUp(for: slot).isEnabled, !slot.isHorizontal, slot.name)
        }
        XCTAssertEqual(controls.actionPopUp(for: .left).menu?.items.first?.title, "Desktop follows the hand")
        XCTAssertEqual(controls.actionPopUp(for: .right).menu?.items.first?.title, MouseGestureSettingsControls.followHorizontalValue)

        Options.shared.gesture.mode = .discrete
        part.syncViewWithOptions()
        XCTAssertTrue(part.directionRows[MouseGestureSettingsControls.Slot.left.rawValue].isEnabled)
        XCTAssertEqual(controls.actionPopUp(for: .left).menu?.items.first?.title, SystemShortcut.moveSpaceLeft.localizedName)
    }

    /// The switch's line is a plain sentence that fits two lines, also for an app with a
    /// long name.
    func testTheGesturesSwitchsLineFitsTwoLines() throws {
        let long = addApp(Self.calculator)
        long.displayName = "An Application With A Remarkably Long Name For Its Kind"
        let (pane, part) = try gesturesPart()
        pane.detailController?.view.layoutSubtreeIfNeeded()
        let label = part.generalGesturesRow.explanationLabel
        let font = PreferencesGroupedForm.explanationFont
        let twoLines = 2 * ceil(font.ascender - font.descender + font.leading) + 2
        XCTAssertGreaterThan(label.frame.width, 300)
        for on in [true, false] {
            let text = ApplicationDetailViewController.generalGesturesExplanation(on: on, name: long.displayName!)
            XCTAssertTrue(text.contains(long.displayName!))
            XCTAssertTrue(text.hasSuffix("."))
            let height = (text as NSString).boundingRect(
                with: NSSize(width: label.frame.width, height: 1000), options: [.usesLineFragmentOrigin], attributes: [.font: font]
            ).height
            XCTAssertLessThanOrEqual(height, twoLines, text)
        }
    }
}
