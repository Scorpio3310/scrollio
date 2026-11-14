//
//  ApplicationPageTests.swift
//  ScrollioTests
//
//  An app's page in parts (Scrolling, Buttons, Gestures, Shortcut Ring: one at a time
//  under the app's box, the one shown last remembered for every app, a part that does not
//  exist falling back to Scrolling, the page's height following the part), the marks of
//  the list of apps, the Scrolling part: the switch's box alone while the app uses the
//  Scrolling settings, its own settings and "Reset to Defaults" under it while it does
//  not; the Buttons part: only the app's own rows with what they do
//  everywhere, the "+" menu, changing, recording and removing a row, the Shortcut Ring and
//  Gesture Navigation offered as everything else, "Show Gesture Settings" leading to the
//  Gestures part; the Gestures part: the switch, the app's own five rows and invert switch,
//  the line on the button to hold here; and the Shortcut Ring part's line on what opens
//  the ring here. Nothing is shown on screen: menus and recorders go through seams,
//  windows are never ordered in.
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

    /// The pane takes the height of the part shown, at each change. (A button runs the
    /// gestures and one opens the ring: nothing folds. The app has its own scrolling
    /// settings: they show.)
    func testThePagesHeightFollowsThePartShown() throws {
        Options.shared.buttons.binding = [
            binding(3, SystemShortcut.mouseGestureNavigation.identifier), binding(5, SystemShortcut.shortcutRing.identifier),
        ]
        addApp(Self.calculator, inherit: false)
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

    // MARK: - The Scrolling part

    /// While the app uses the Scrolling settings the part is the switch's box alone, as the
    /// Gestures and Shortcut Ring parts are: no settings, no "Thumb wheel" box, no "Reset
    /// to Defaults". The settings' controller is kept for when the switch goes off.
    func testTheScrollingPartIsTheSwitchAloneWhileTheAppUsesTheScrollingSettings() throws {
        addApp(Self.calculator)
        let pane = makePane()
        pane.openApplication(withID: Self.calculator, part: .scrolling)
        let page = try XCTUnwrap(pane.detailController)
        let part = try XCTUnwrap(page.scrollingPart)
        page.view.layoutSubtreeIfNeeded()

        XCTAssertTrue(part.inheritRow.isOn)
        XCTAssertEqual(part.inheritRow.explanation, "Changes under Scrolling apply to Calculator too.")
        XCTAssertFalse(part.showsSettings)
        XCTAssertEqual(part.view.subviews, [part.inheritSection], "the switch's box alone")
        let controls = allSubviews(of: part.view).filter { $0 is NSControl && !($0 is NSTextField) }
        XCTAssertEqual(controls, [part.inheritRow.toggle], "the switch is the part's only control")
        let settings = try XCTUnwrap(part.scrollingController)
        XCTAssertTrue(settings.parent === part, "kept for when the switch goes off")
        XCTAssertNil(settings.view.superview)
        for view: NSView in [settings.smoothSwitch, settings.thumbWheelSection, settings.keysSection, settings.resetToDefaultsButton] {
            XCTAssertFalse(view.isDescendant(of: page.view))
        }
        let margin = PreferencesGroupedForm.margin
        XCTAssertEqual(part.view.fittingSize.height, part.inheritSection.fittingSize.height + 2 * margin, accuracy: 0.5)
        XCTAssertFalse(page.view.hasAmbiguousLayout)
        XCTAssertEqual(pane.view.frame.height, page.view.fittingSize.height, accuracy: 0.5)
    }

    /// Off: the app's own settings stand under the switch's box, "Reset to Defaults" at
    /// their end, the page measures again once and the list marks the app. On again: they
    /// go, the page measures once more and is as short as before; the values are kept for
    /// later and come back as they were left.
    func testTurningTheScrollingSwitchOffShowsTheSettingsAndOnTakesThemAway() throws {
        let calculator = addApp(Self.calculator)
        let pane = makePane()
        pane.openApplication(withID: Self.calculator, part: .scrolling)
        let page = try XCTUnwrap(pane.detailController)
        let part = try XCTUnwrap(page.scrollingPart)
        let settings = try XCTUnwrap(part.scrollingController)
        var heightChanges = 0
        let original = page.onHeightChange
        page.onHeightChange = {
            heightChanges += 1
            original?()
        }
        let short = pane.view.frame.height

        page.inheritSwitch.state = .off
        send(page.inheritSwitch)
        XCTAssertFalse(calculator.inherit)
        XCTAssertEqual(heightChanges, 1, "the page measures again, once")
        XCTAssertTrue(part.showsSettings)
        XCTAssertEqual(part.inheritRow.explanation, "Calculator keeps its own settings below.")
        let shown: [NSView] = [
            settings.smoothSwitch, settings.feelControl, settings.scrollSpeedSlider, settings.reverseSwitch,
            settings.thumbWheelSection, settings.thumbWheelNote, settings.keysSection, settings.advancedButton,
            settings.resetToDefaultsButton,
        ]
        for view in shown {
            XCTAssertTrue(view.isDescendant(of: page.view))
            XCTAssertFalse(view.isHiddenOrHasHiddenAncestor)
        }
        XCTAssertTrue(settings.smoothSwitch.isEnabled, "the app's own, editable")
        XCTAssertTrue(settings.thumbWheelSpeedSlider.isEnabled)
        XCTAssertGreaterThan(pane.view.frame.height, short + 300)
        XCTAssertEqual(pane.view.frame.height, page.view.fittingSize.height, accuracy: 0.5)
        page.view.layoutSubtreeIfNeeded()
        XCTAssertFalse(page.view.hasAmbiguousLayout)
        XCTAssertEqual((pane.list.rows.first as? ApplicationListRow)?.marks, [.scrolling], "the mark of the list")

        settings.scrollSpeedSlider.doubleValue = 3
        send(settings.scrollSpeedSlider)
        page.inheritSwitch.state = .on
        send(page.inheritSwitch)
        XCTAssertTrue(calculator.inherit)
        XCTAssertEqual(heightChanges, 2)
        XCTAssertFalse(part.showsSettings)
        XCTAssertNil(settings.view.superview)
        XCTAssertEqual(pane.view.frame.height, short, accuracy: 0.5)
        XCTAssertEqual(calculator.scroll.speed, 3, "kept for later")
        XCTAssertEqual((pane.list.rows.first as? ApplicationListRow)?.marks ?? [], [])

        page.inheritSwitch.state = .off
        send(page.inheritSwitch)
        XCTAssertEqual(heightChanges, 3)
        XCTAssertEqual(settings.scrollSpeedSlider.doubleValue, 3, accuracy: 1e-9, "back as it was left")
    }

    /// "Reset to Defaults" is there only while the switch is off, at the end of the app's
    /// own settings. Its Undo still takes the reset back after the switch went on (the
    /// switch stays), and Redo shows on the settings once they are back.
    func testTheScrollingPartsResetIsThereOnlyWhileTheSwitchIsOffAndItsUndoStays() throws {
        let calculator = addApp(Self.calculator, inherit: false)
        calculator.scroll.speed = 4.5
        let pane = makePane()
        pane.openApplication(withID: Self.calculator, part: .scrolling)
        let page = try XCTUnwrap(pane.detailController)
        let settings = try XCTUnwrap(page.scrollingController)
        let undo = UndoManager()
        undo.groupsByEvent = false
        settings.paneUndoManager = undo
        let reset = try XCTUnwrap(settings.resetToDefaultsButton)
        XCTAssertTrue(reset.isDescendant(of: page.view))
        XCTAssertTrue(reset.isEnabled)

        undo.beginUndoGrouping()
        send(reset)
        undo.endUndoGrouping()
        XCTAssertEqual(calculator.scroll, OPTIONS_SCROLL_DEFAULT())
        XCTAssertTrue(settings.offersUndoOfReset)

        page.inheritSwitch.state = .on
        send(page.inheritSwitch)
        XCTAssertFalse(reset.isDescendant(of: page.view), "no Reset while the app uses the Scrolling settings")
        XCTAssertFalse(settings.offersUndoOfReset, "nor its offer")
        undo.undo()
        XCTAssertEqual(calculator.scroll.speed, 4.5, "Edit › Undo still takes the reset back")
        XCTAssertTrue(calculator.inherit, "the switch stays")
        XCTAssertFalse(page.scrollingPart.showsSettings)

        page.inheritSwitch.state = .off
        send(page.inheritSwitch)
        XCTAssertTrue(reset.isDescendant(of: page.view))
        XCTAssertEqual(settings.scrollSpeedSlider.doubleValue, 4.5, accuracy: 1e-9)
        undo.redo()
        XCTAssertEqual(calculator.scroll, OPTIONS_SCROLL_DEFAULT())
        XCTAssertEqual(settings.scrollSpeedSlider.doubleValue, OPTIONS_SCROLL_DEFAULT().speed, accuracy: 1e-9, "Redo shows on the settings")
    }

    /// Undo of a removal while the page of the app added again is open on Scrolling: the
    /// switch goes off as it was, the app's own settings come back under it and the pane
    /// takes the page's new height; Redo takes them away again.
    func testUndoOntoTheOpenPageShowsTheScrollingSettingsAndRefitsThePane() throws {
        let calculator = addApp(Self.calculator, inherit: false)
        calculator.scroll.speed = 4.5
        ApplicationPagePart.scrolling.remember(in: uiDefaults)
        let pane = makePane()
        let window = makeWindow(for: pane)
        let undo = try XCTUnwrap(window.undoManager)
        undo.groupsByEvent = false
        pane.list.select(Self.calculator)
        undo.beginUndoGrouping()
        pane.list.removeButton.performClick(nil)
        undo.endUndoGrouping()
        let again = pane.addApplication(path: Self.calculator, knownPaths: [Self.calculator])
        let page = try XCTUnwrap(pane.detailController)
        XCTAssertTrue(page.application === again)
        XCTAssertEqual(page.shownPart, .scrolling)
        XCTAssertTrue(again.inherit, "an app added anew uses the Scrolling settings")
        XCTAssertFalse(page.scrollingPart.showsSettings)
        let short = pane.view.frame.height

        undo.undo()
        XCTAssertFalse(again.inherit)
        XCTAssertEqual(page.inheritSwitch.state, .off)
        XCTAssertTrue(page.scrollingPart.showsSettings, "the app's own settings")
        XCTAssertEqual(page.scrollingController.scrollSpeedSlider.doubleValue, 4.5, accuracy: 1e-9)
        XCTAssertGreaterThan(pane.view.frame.height, short + 300)
        XCTAssertEqual(pane.view.frame.height, page.view.fittingSize.height, accuracy: 0.5)

        undo.redo()
        XCTAssertTrue(again.inherit)
        XCTAssertEqual(page.inheritSwitch.state, .on)
        XCTAssertFalse(page.scrollingPart.showsSettings)
        XCTAssertEqual(pane.view.frame.height, short, accuracy: 0.5)
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
        for (isEmpty, listsThumbWheel) in [(true, false), (false, false), (false, true)] {
            let text = ApplicationButtonsViewController.note(for: long.displayName!, isEmpty: isEmpty, listsThumbWheel: listsThumbWheel)
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

    /// Undo of a removal while the page of the app added again is open: the page shows the
    /// settings that come back (its own gestures and ring with their rows, its name in the
    /// header and the window's title), and the pane takes the page's new height; Redo too.
    /// (A button runs the gestures: nothing folds.)
    func testUndoOntoTheOpenPageOfTheAppAddedAgainShowsItAndRefitsThePane() throws {
        Options.shared.buttons.binding = [binding(3, SystemShortcut.mouseGestureNavigation.identifier)]
        let calculator = addApp(Self.calculator)
        calculator.displayName = "Numbers"
        calculator.setUsesGeneralGestures(false, general: .default)
        calculator.setUsesGeneralRing(false, general: .default)
        ApplicationPagePart.gestures.remember(in: uiDefaults)
        let pane = makePane()
        let window = makeWindow(for: pane)
        let undo = try XCTUnwrap(window.undoManager)
        undo.groupsByEvent = false
        pane.list.select(Self.calculator)
        undo.beginUndoGrouping()
        pane.list.removeButton.performClick(nil)
        undo.endUndoGrouping()
        let again = pane.addApplication(path: Self.calculator, knownPaths: [Self.calculator])
        let page = try XCTUnwrap(pane.detailController)
        XCTAssertTrue(page.application === again)
        XCTAssertEqual(page.shownPart, .gestures)
        XCTAssertNil(page.gesturesPart.controls)
        let short = pane.view.frame.height
        var titles: [String?] = []
        pane.onSubpageChange = { titles.append(pane.subpageTitle) }

        undo.undo()
        XCTAssertFalse(again.usesGeneralGestures)
        XCTAssertNotNil(page.gesturesPart.controls, "the app's own rows")
        XCTAssertGreaterThan(pane.view.frame.height, short + 200)
        XCTAssertEqual(pane.view.frame.height, page.view.fittingSize.height, accuracy: 0.5)
        XCTAssertEqual(page.headerRow.title, "Numbers")
        XCTAssertEqual(page.title, "Numbers")
        XCTAssertEqual(titles.last, "Numbers", "the window's title follows")
        choose(3, on: page)
        XCTAssertNotNil(page.ringController)
        XCTAssertEqual(pane.view.frame.height, page.view.fittingSize.height, accuracy: 0.5)

        undo.redo()
        XCTAssertTrue(again.usesGeneralRing)
        XCTAssertNil(page.ringController)
        XCTAssertEqual(pane.view.frame.height, page.view.fittingSize.height, accuracy: 0.5)
        XCTAssertEqual(page.headerRow.title, "Calculator")
        XCTAssertEqual(titles.last, "Calculator")
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

    /// A click on a row's chevron opens the page at once; when it is the first click of a
    /// double-click, the second mouse-down lands on the page and reaches nothing there (not
    /// the part's first switch under it). A click that begins on the page goes through,
    /// and so does a double-click there.
    func testTheSecondClickOfADoubleClickThatOpenedThePageReachesNothingOnIt() throws {
        addApp(Self.calculator)
        ApplicationPagePart.ring.remember(in: uiDefaults)
        let pane = makePane()
        let window = makeWindow(for: pane)
        let row = try XCTUnwrap(pane.list.rows.first as? ApplicationListRow)
        row.layoutSubtreeIfNeeded()
        let chevron = try XCTUnwrap(row.chevronView)
        func press(at point: NSPoint, clicks: Int) throws -> NSEvent {
            return try XCTUnwrap(NSEvent.mouseEvent(
                with: .leftMouseDown, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1
            ))
        }
        row.mouseDown(with: try press(at: row.convert(NSPoint(x: chevron.frame.midX, y: chevron.frame.midY), to: nil), clicks: 1))
        let page = try XCTUnwrap(pane.detailController)
        XCTAssertEqual(page.shownPart, .ring)
        let pageView = try XCTUnwrap(page.view as? ApplicationDetailView)
        pane.view.layoutSubtreeIfNeeded()
        let toggle = page.generalRingSwitch
        let onSwitch = toggle.convert(NSPoint(x: toggle.bounds.midX, y: toggle.bounds.midY), to: nil)
        func hit(_ event: NSEvent) -> NSView? {
            pageView.currentEvent = { event }
            return pageView.superview.flatMap { pageView.hitTest($0.convert(event.locationInWindow, from: nil)) }
        }

        let second = try press(at: onSwitch, clicks: 2)
        XCTAssertTrue(hit(second) === pageView, "held back")
        pageView.mouseDown(with: second)
        XCTAssertEqual(toggle.state, .on, "the switch is untouched")
        XCTAssertTrue(hit(try press(at: onSwitch, clicks: 3)) === pageView)
        // A click of the page's own, and a double-click there, reach the switch.
        XCTAssertTrue(hit(try press(at: onSwitch, clicks: 1))?.isDescendant(of: page.generalRingRow) == true)
        XCTAssertTrue(hit(try press(at: onSwitch, clicks: 2))?.isDescendant(of: page.generalRingRow) == true)
    }

    // MARK: - The Buttons part

    /// Only the app's own rows, each a row of the Buttons pane with what the button does
    /// everywhere else under it; "Default" for one that does what it does by itself here.
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
    /// "Record a Button or Key…", then the bindings of Buttons not offered yet, also what
    /// opens the ring or runs Gesture Navigation there.
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
        // The MX Master 3S: wheel button, mode shift button (the ring's in Buttons),
        // forward (the app's own already), back, gesture button.
        XCTAssertEqual(menu.items.first?.isSectionHeader, true)
        XCTAssertEqual(names.first, "Your Mouse")
        XCTAssertTrue(names.contains(ButtonTriggerNaming.title(for: RecordedEvent(type: .mouse, code: 2, modifiers: 0, deviceFilter: nil))))
        XCTAssertTrue(names.contains(ButtonTriggerNaming.title(for: RecordedEvent(type: .mouse, code: 3, modifiers: 0, deviceFilter: nil))))
        XCTAssertTrue(names.contains(ButtonTriggerNaming.title(for: RecordedEvent(type: .mouse, code: 1000, modifiers: 0, deviceFilter: nil))),
                      "a Logitech button no binding of Buttons uses: \(names)")
        XCTAssertTrue(names.contains(ButtonTriggerNaming.title(for: RecordedEvent(type: .mouse, code: 1001, modifiers: 0, deviceFilter: nil))),
                      "the button that opens the ring in Buttons: \(names)")
        XCTAssertFalse(names.contains(ButtonTriggerNaming.title(for: RecordedEvent(type: .mouse, code: 4, modifiers: 0, deviceFilter: nil))))
        XCTAssertTrue(names.contains("Record a Button or Key…"))
        let general = try XCTUnwrap(names.firstIndex(of: "In Buttons"))
        let rest = Array(names[(general + 1)...])
        XCTAssertEqual(rest.count, 3, "⌘ and button 5, button 6 (Gesture Navigation), ⌘ and a key; not the back button nor the mode shift button (offered above): \(rest)")
        let actions = [SystemShortcut.copy, SystemShortcut.mouseGestureNavigation, SystemShortcut.paste].map { ": " + $0.localizedName }
        XCTAssertEqual(rest.map { name in actions.first { name.hasSuffix($0) } }, actions, "\(rest)")
    }

    /// The owner's case: on an MX Master 4 whose thumb panel runs Gesture Navigation in
    /// Buttons and whose forward button opens the ring, "+" offers both under "Your Mouse",
    /// and a key that opens the ring under "In Buttons". Each new row starts with what it
    /// does everywhere, named as the Buttons pane names it.
    func testThePlusMenuOffersTheThumbPanelAndWhatOpensTheRingAndANewRowKeepsItsAction() throws {
        let ring = SystemShortcut.shortcutRing.identifier
        let gestures = SystemShortcut.mouseGestureNavigation.identifier
        let thumbPanel = LogiCenter.shared.scrollioCode(for: .thumbPanel)
        let controlOption = UInt(CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue)
        Options.shared.buttons.binding = [
            binding(thumbPanel, gestures), binding(4, ring), binding(49, ring, modifiers: controlOption, type: .keyboard),
        ]
        let generals = Options.shared.buttons.binding
        let calculator = addApp(Self.calculator)
        var shown: NSMenu?
        let (_, part) = try buttonsPart(menus: { shown = $0 })
        part.deviceSource = mouse("MX Master 4")
        part.reloadRows()
        part.showAddMenu(from: part.list.addButton)
        let names = titles(of: try XCTUnwrap(shown))
        let thumbPanelTitle = ButtonTriggerNaming.title(for: generals[0].triggerEvent)
        XCTAssertEqual(thumbPanelTitle, "Thumb panel")
        let header = try XCTUnwrap(names.firstIndex(of: "Your Mouse"))
        let record = try XCTUnwrap(names.firstIndex(of: "Record a Button or Key…"))
        let mouseItems = Array(names[(header + 1)..<record])
        XCTAssertTrue(mouseItems.contains(thumbPanelTitle), "\(mouseItems)")
        XCTAssertTrue(mouseItems.contains(ButtonTriggerNaming.title(for: generals[1].triggerEvent)), "\(mouseItems)")
        let inButtons = try XCTUnwrap(names.firstIndex(of: "In Buttons"))
        XCTAssertEqual(Array(names[(inButtons + 1)...]),
                       [ButtonTriggerNaming.title(for: generals[2].triggerEvent) + ": " + SystemShortcut.shortcutRing.localizedName])

        for general in generals {
            part.addOwnBinding(for: general.triggerEvent)
        }
        XCTAssertEqual(calculator.ownButtonBindings.map(\.triggerEvent), generals.map(\.triggerEvent))
        XCTAssertEqual(calculator.ownButtonBindings.map(\.systemShortcutName), [gestures, ring, ring], "nothing changes until another is chosen")
        XCTAssertTrue(calculator.ownButtonBindings.allSatisfy(\.isEnabled))
        XCTAssertEqual(Options.shared.buttons.binding, generals)
        for (row, general) in zip(part.rows, generals) {
            // The Buttons pane's pull-down for the general binding names its action.
            let buttonsTitle = try XCTUnwrap(ButtonActionPullDown(binding: general).menu?.items.first?.title)
            XCTAssertEqual(row.explanation, "Everywhere: " + buttonsTitle)
            XCTAssertEqual(row.pullDown.menu?.items.first?.title, buttonsTitle)
            XCTAssertTrue(row.isEnabled)
        }
        XCTAssertEqual(part.rows.first?.explanation, "Everywhere: " + SystemShortcut.mouseGestureNavigation.localizedName)
        XCTAssertEqual(part.rows.last?.explanation, "Everywhere: " + SystemShortcut.shortcutRing.localizedName)
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

    /// A button with modifier keys that Buttons has no binding of its own for runs the
    /// binding without them everywhere: its new row starts with that action, as its
    /// "Everywhere" line says, so nothing changes until another one is chosen.
    func testANewRowForAButtonWithModifierKeysStartsWithWhatItDoesEverywhere() throws {
        Options.shared.buttons.binding = [binding(3, "copy")]
        let calculator = addApp(Self.calculator)
        let (_, part) = try buttonsPart()
        let commandBack = RecordedEvent(type: .mouse, code: 3, modifiers: UInt(CGEventFlags.maskCommand.rawValue), deviceFilter: nil)
        part.addOwnBinding(for: commandBack)
        XCTAssertEqual(calculator.ownButtonBindings.map(\.triggerEvent), [commandBack])
        XCTAssertEqual(calculator.ownButtonBindings.map(\.systemShortcutName), ["copy"])
        XCTAssertEqual(part.rows.first?.explanation, "Everywhere: " + SystemShortcut.copy.localizedName)
    }

    /// A row's pull-down changes the app's binding only; "Default" stores no action (the
    /// button does what it does by itself here); the ring is stored as any other action.
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
        XCTAssertEqual(calculator.ownButtonBindings.first?.systemShortcutName, SystemShortcut.shortcutRing.identifier)
        XCTAssertNil(calculator.ownButtonBindings.first?.label, "a listed action drops the name")
        XCTAssertEqual(part.rows.first?.pullDown.menu?.items.first?.title, SystemShortcut.shortcutRing.localizedName)
        XCTAssertEqual(Options.shared.buttons.binding, general)
    }

    /// A row's menu is the Buttons pane's for its trigger: "Default" first, the Shortcut
    /// Ring, Gesture Navigation for a mouse button (not for a key), "Show Gesture Settings"
    /// while Gesture Navigation is the action, the Logitech actions for a Logitech button,
    /// "Open App or File…" and "Keyboard Shortcut…". Choosing the ring or Gesture
    /// Navigation there stores it, for this app only.
    func testARowsMenuIsTheButtonsPanesMenuAndTakesTheRingAndGestureNavigation() throws {
        let command = UInt(CGEventFlags.maskCommand.rawValue)
        let thumbPanel = LogiCenter.shared.scrollioCode(for: .thumbPanel)
        Options.shared.buttons.binding = [binding(thumbPanel, SystemShortcut.mouseGestureNavigation.identifier)]
        let general = Options.shared.buttons.binding
        let calculator = addApp(Self.calculator)
        calculator.setOwnButtonBindings([
            binding(3, "copy"), binding(thumbPanel, SystemShortcut.missionControl.identifier), binding(40, "paste", modifiers: command, type: .keyboard),
        ])
        let (_, part) = try buttonsPart()
        XCTAssertEqual(part.rows.count, 3)
        func item(_ shortcut: SystemShortcut.Shortcut, of pullDown: ButtonActionPullDown) -> NSMenuItem? {
            return pullDown.menu?.items.first { ($0.representedObject as? SystemShortcut.Shortcut)?.identifier == shortcut.identifier }
        }
        func marker(_ marker: String, of pullDown: ButtonActionPullDown) -> NSMenuItem? {
            return pullDown.menu?.items.first { $0.representedObject as? String == marker }
        }
        for row in part.rows {
            let pullDown = row.pullDown
            let shown = (pullDown.menu?.items ?? []).dropFirst().filter { !$0.isHidden && !$0.isSeparatorItem }
            XCTAssertTrue(shown.first === pullDown.noActionItem, "Default first")
            XCTAssertEqual(pullDown.noActionItem?.title, "Default")
            XCTAssertEqual(item(SystemShortcut.shortcutRing, of: pullDown)?.isHidden, false, "the ring, on every row")
            XCTAssertEqual(marker(ShortcutManager.MenuMarker.openTarget, of: pullDown)?.isHidden, false)
            XCTAssertEqual(marker(ShortcutManager.MenuMarker.keyboardShortcut, of: pullDown)?.isHidden, false)
            XCTAssertEqual(pullDown.gestureSettingsItem?.isHidden, true, "Gesture Navigation is not the action yet")
        }
        let (mouseRow, logitechRow, keyRow) = (part.rows[0].pullDown, part.rows[1].pullDown, part.rows[2].pullDown)
        XCTAssertEqual(mouseRow.gestureNavigationItem?.isHidden, false)
        XCTAssertEqual(logitechRow.gestureNavigationItem?.isHidden, false)
        XCTAssertEqual(keyRow.gestureNavigationItem?.isHidden, true, "a key cannot run Gesture Navigation, as in Buttons")
        let logitechActions = everything(in: logitechRow.menu).compactMap { $0.representedObject as? SystemShortcut.Shortcut }.map(\.identifier)
        XCTAssertTrue(logitechActions.contains(SystemShortcut.logiSmartShiftToggle.identifier), "the Logitech actions on a Logitech button")
        let mouseActions = everything(in: mouseRow.menu).compactMap { $0.representedObject as? SystemShortcut.Shortcut }.map(\.identifier)
        XCTAssertFalse(mouseActions.contains(SystemShortcut.logiSmartShiftToggle.identifier))

        // The ring on the key, Gesture Navigation on the back button.
        keyRow.shortcutSelected(try XCTUnwrap(item(SystemShortcut.shortcutRing, of: keyRow)))
        mouseRow.shortcutSelected(try XCTUnwrap(mouseRow.gestureNavigationItem))
        XCTAssertEqual(calculator.ownButtonBindings.map(\.systemShortcutName),
                       [SystemShortcut.mouseGestureNavigation.identifier, SystemShortcut.missionControl.identifier, SystemShortcut.shortcutRing.identifier])
        XCTAssertTrue(calculator.ownButtonBindings.allSatisfy(\.isEnabled))
        XCTAssertEqual(part.rows[0].pullDown.gestureSettingsItem?.isHidden, false, "Show Gesture Settings, while Gesture Navigation is the action")
        XCTAssertEqual(part.rows[2].pullDown.menu?.items.first?.title, SystemShortcut.shortcutRing.localizedName)
        XCTAssertEqual(Options.shared.buttons.binding, general, "Buttons is not touched")
    }

    /// "Show Gesture Settings" on a row shows the app's own Gestures part, not the Gestures
    /// pane.
    func testShowGestureSettingsOnARowShowsTheAppsGesturesPart() throws {
        let calculator = addApp(Self.calculator)
        calculator.setOwnButtonBindings([binding(3, SystemShortcut.mouseGestureNavigation.identifier)])
        let (page, part) = try buttonsPart()
        XCTAssertEqual(page.shownPart, .buttons)
        let pullDown = try XCTUnwrap(part.rows.first?.pullDown)
        let settings = try XCTUnwrap(pullDown.gestureSettingsItem)
        XCTAssertFalse(settings.isHidden)
        pullDown.shortcutSelected(settings)
        XCTAssertEqual(page.shownPart, .gestures)
        XCTAssertTrue(page.gesturesPart.view.isDescendant(of: page.partContainer))
        XCTAssertEqual(calculator.ownButtonBindings.first?.systemShortcutName, SystemShortcut.mouseGestureNavigation.identifier, "the action stays")
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

    /// "−" in the Buttons part, then the Gestures or Shortcut Ring part, then Edit › Undo
    /// or Redo: the part shown now says what the app's buttons make of the gestures or the
    /// ring after the change, not what they made before.
    func testUndoOfARemovedRowShowsOnTheGesturesAndRingPartsShownNow() throws {
        let gestures = SystemShortcut.mouseGestureNavigation.identifier
        let ringAction = SystemShortcut.shortcutRing.identifier
        let thumbPanel = LogiCenter.shared.scrollioCode(for: .thumbPanel)
        Options.shared.buttons.binding = [binding(thumbPanel, gestures), binding(5, ringAction)]
        let calculator = addApp(Self.calculator)
        calculator.setOwnButtonBindings([binding(thumbPanel, ringAction), binding(5, "copy")])
        let (page, part) = try buttonsPart()
        let undo = try XCTUnwrap(part.paneUndoManager)
        undo.groupsByEvent = false
        func remove(_ index: Int) {
            undo.beginUndoGrouping()
            part.removeOwnBinding(id: calculator.ownButtonBindings[index].id)
            undo.endUndoGrouping()
        }

        // The Gestures part: the thumb panel runs the gestures again once its row is gone.
        let noButton = "While Calculator is in front, no button runs the gestures: see its Buttons part."
        let generalGestures = "While Calculator is in front, the general gestures run."
        remove(0)
        choose(ApplicationPagePart.all.firstIndex(of: .gestures)!, on: page)
        XCTAssertEqual(page.gesturesPart.generalGesturesRow.explanation, generalGestures)
        undo.undo()
        XCTAssertEqual(page.gesturesPart.generalGesturesRow.explanation, noButton, "Undo shows on the part shown now")
        undo.redo()
        XCTAssertEqual(page.gesturesPart.generalGesturesRow.explanation, generalGestures, "and Redo")

        // The Shortcut Ring part: Buttons' ring button does something else here, and back.
        choose(ApplicationPagePart.all.firstIndex(of: .buttons)!, on: page)
        let copyRow = try XCTUnwrap(calculator.ownButtonBindings.firstIndex { $0.systemShortcutName == "copy" })
        remove(copyRow)
        choose(ApplicationPagePart.all.firstIndex(of: .ring)!, on: page)
        let generalRing = "While Calculator is in front, the general ring opens."
        let nothing = "While Calculator is in front, nothing opens the ring: see its Buttons part."
        XCTAssertEqual(page.generalRingRow.explanation, generalRing)
        undo.undo()
        XCTAssertEqual(page.generalRingRow.explanation, nothing)
        undo.redo()
        XCTAssertEqual(page.generalRingRow.explanation, generalRing)
    }

    /// "−" on the page, the page closes and the app's page opens again, then Edit › Undo:
    /// the row shows on the page that is open now, selected, and the pane takes the page's
    /// new height; Redo takes the row off that page again.
    func testUndoOfARemovedRowShowsOnThePageOpenedAgain() throws {
        let calculator = addApp(Self.calculator)
        calculator.setOwnButtonBindings([binding(3, "appExpose"), binding(4, "copy")])
        let removedID = calculator.ownButtonBindings[0].id
        let pane = makePane()
        _ = makeWindow(for: pane)
        let undo = UndoManager()
        undo.groupsByEvent = false
        pane.openApplication(withID: Self.calculator, part: .buttons)
        let first = try XCTUnwrap(pane.detailController?.buttonsPart)
        first.paneUndoManager = undo
        undo.beginUndoGrouping()
        first.removeOwnBinding(id: removedID)
        undo.endUndoGrouping()
        pane.leaveSubpage()
        pane.openApplication(withID: Self.calculator, part: .buttons)
        let page = try XCTUnwrap(pane.detailController)
        let part = try XCTUnwrap(page.buttonsPart)
        XCTAssertFalse(part === first)
        XCTAssertEqual(part.rows.count, 1)
        let short = pane.view.frame.height

        undo.undo()
        XCTAssertEqual(part.rows.map(\.binding.systemShortcutName), ["appExpose", "copy"], "the open page shows the row")
        XCTAssertEqual(part.list.selectedID, AnyHashable(removedID))
        XCTAssertGreaterThan(pane.view.frame.height, short)
        XCTAssertEqual(pane.view.frame.height, page.view.fittingSize.height, accuracy: 0.5)

        undo.redo()
        XCTAssertEqual(part.rows.map(\.binding.systemShortcutName), ["copy"], "the row leaves the open page")
        XCTAssertEqual(calculator.ownButtonBindings.map(\.systemShortcutName), ["copy"])
        XCTAssertEqual(pane.view.frame.height, short, accuracy: 0.5)
    }

    /// "−" on the page, then the app is removed from the list and added again (a new entry,
    /// whose page opens), then two Undos: the first gives the new entry the app's settings,
    /// the second its button, shown on its page, with the list's mark; the entry that was
    /// removed is left alone. Redo takes the button off the new entry again.
    func testUndoOfARemovedRowReachesTheAppAddedAgain() throws {
        let calculator = addApp(Self.calculator)
        calculator.setOwnButtonBindings([binding(3, "appExpose")])
        let pane = makePane()
        let window = makeWindow(for: pane)
        let undo = try XCTUnwrap(window.undoManager)
        undo.groupsByEvent = false
        pane.openApplication(withID: Self.calculator, part: .buttons)
        let first = try XCTUnwrap(pane.detailController?.buttonsPart)
        first.paneUndoManager = undo
        undo.beginUndoGrouping()
        first.removeOwnBinding(id: calculator.ownButtonBindings[0].id)
        undo.endUndoGrouping()
        pane.leaveSubpage()
        pane.list.select(Self.calculator)
        undo.beginUndoGrouping()
        pane.list.removeButton.performClick(nil)
        undo.endUndoGrouping()
        let again = pane.addApplication(path: Self.calculator, knownPaths: [Self.calculator])
        XCTAssertFalse(again === calculator)
        let part = try XCTUnwrap(pane.detailController?.buttonsPart)
        XCTAssertEqual(pane.detailController?.shownPart, .buttons)
        XCTAssertTrue(part.rows.isEmpty)

        undo.undo()
        undo.undo()
        XCTAssertEqual(again.ownButtonBindings.map(\.systemShortcutName), ["appExpose"], "the entry on the list now")
        XCTAssertFalse(calculator.hasOwnButtons, "not the entry that was removed")
        XCTAssertEqual(part.rows.map(\.binding.systemShortcutName), ["appExpose"])
        XCTAssertEqual((pane.list.rows.first as? ApplicationListRow)?.marks, [.buttons])

        undo.redo()
        XCTAssertFalse(again.hasOwnButtons)
        XCTAssertTrue(part.rows.isEmpty)
        XCTAssertEqual((pane.list.rows.first as? ApplicationListRow)?.marks, [])
    }

    /// "Record a Button or Key…": the Buttons pane's recorder; what it caught is added when
    /// it closes. A button the app has already is a duplicate; one that opens the ring or
    /// runs Gesture Navigation in Buttons is taken as any other, and starts with that action.
    func testRecordingTakesAButtonThatOpensTheRingInButtons() throws {
        Options.shared.buttons.binding = [
            binding(6, SystemShortcut.shortcutRing.identifier), binding(7, SystemShortcut.mouseGestureNavigation.identifier),
        ]
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
        for code: UInt16 in [6, 7, 5] {
            XCTAssertTrue(part.validateRecordedEvent(recorder, event: press(code)), "button \(code)")
            XCTAssertNil(part.refusalHint(recorder, event: press(code)), "button \(code)")
        }
        part.onEventRecorded(recorder, didRecordEvent: press(6), isDuplicate: false)
        part.onRecordingStopped(recorder, didRecord: true)
        XCTAssertFalse(part.isRecorderOpen)
        part.onRecordingStarted(recorder)
        part.onEventRecorded(recorder, didRecordEvent: press(5), isDuplicate: false)
        part.onRecordingStopped(recorder, didRecord: true)
        XCTAssertEqual(calculator.ownButtonBindings.map(\.triggerEvent.code), [3, 6, 5])
        XCTAssertEqual(calculator.ownButtonBindings.map(\.systemShortcutName),
                       ["appExpose", SystemShortcut.shortcutRing.identifier, ""],
                       "the ring as everywhere; no action of Buttons: Default")
        XCTAssertFalse(part.isRecorderOpen)
    }

    /// A binding of the app's own on a button that Buttons gave the ring or Gesture
    /// Navigation is used as any other: its row is not dimmed, and says what the button
    /// does everywhere.
    func testARowOnAButtonThatRunsGestureNavigationInButtonsIsNotDimmed() throws {
        let calculator = addApp(Self.calculator)
        calculator.setOwnButtonBindings([binding(3, "appExpose"), binding(4, "copy")])
        Options.shared.buttons.binding = [
            binding(3, SystemShortcut.mouseGestureNavigation.identifier), binding(4, SystemShortcut.shortcutRing.identifier),
        ]
        let (_, part) = try buttonsPart()
        XCTAssertEqual(part.rows.map(\.isEnabled), [true, true])
        XCTAssertEqual(part.rows.map(\.explanation), [
            "Everywhere: " + SystemShortcut.mouseGestureNavigation.localizedName, "Everywhere: " + SystemShortcut.shortcutRing.localizedName,
        ])
    }

    // MARK: - The Gestures part

    /// Calculator's page on its Gestures part, with the menus' Logitech actions off and
    /// the connected mice able to do `mice`.
    private func gesturesPart(
        interactiveAvailable: Bool = false, mice: MouseGestureDeviceSupport = .none
    ) throws -> (PreferencesApplicationViewController, ApplicationGesturesPartViewController) {
        let pane = makePane()
        pane.openApplication(withID: Self.calculator, part: .gestures)
        let part = try XCTUnwrap(pane.detailController?.gesturesPart)
        part.showsLogiActions = { false }
        part.isInteractiveAvailable = { interactiveAvailable }
        part.deviceSource = MouseGestureDeviceSource(support: { mice }, refresh: {})
        part.syncViewWithOptions()
        return (pane, part)
    }

    private func everything(in menu: NSMenu?) -> [NSMenuItem] {
        return (menu?.items ?? []).flatMap { [$0] + everything(in: $0.submenu) }
    }

    /// While the app uses the general gestures the part is the switch alone, which says so.
    func testTheGesturesPartIsTheSwitchAloneWhileTheAppUsesTheGeneralGestures() throws {
        Options.shared.buttons.binding = [binding(3, SystemShortcut.mouseGestureNavigation.identifier)]
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
        Options.shared.buttons.binding = [binding(3, SystemShortcut.mouseGestureNavigation.identifier)]
        let calculator = addApp(Self.calculator)
        Options.shared.gesture.actions.up = GestureAction(SystemShortcut.copy)
        Options.shared.gesture.invertHorizontal = true
        let (pane, part) = try gesturesPart()
        var heightChanges = 0
        pane.detailController?.onHeightChange = { heightChanges += 1 }
        part.generalGesturesSwitch.state = .off
        send(part.generalGesturesSwitch)

        XCTAssertEqual(heightChanges, 1, "the page measures again, once")
        XCTAssertFalse(calculator.usesGeneralGestures)
        XCTAssertEqual(calculator.ownGestures?.actions, Options.shared.gesture.actions)
        XCTAssertEqual(calculator.ownGestures?.invertHorizontal, true)
        XCTAssertEqual(part.generalGesturesRow.explanation, "While Calculator is in front, the gestures below run.")
        let controls = try XCTUnwrap(part.controls)
        XCTAssertEqual(part.directionRows.map(\.title), ["Up", "Down", "Left", "Right", "Click"])
        XCTAssertEqual(part.directionsFold?.title, "Directions")
        XCTAssertEqual(part.directionsFold?.isCollapsible, false, "a button runs the gestures here: a plain title")
        XCTAssertNil(part.directionsSection?.titleLabel, "the box under it has none of its own")
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

    /// While the desktop follows the hand (the app's own mode), Left and Right are dimmed
    /// and say so and the swipe speed applies, as in the Gestures pane; what they hold stays
    /// and comes back in the other mode. The general mode changes nothing here.
    func testFollowingTheHandDimsLeftAndRightAsThePaneDoes() throws {
        let calculator = addApp(Self.calculator)
        calculator.setUsesGeneralGestures(false, general: .default)
        Options.shared.gesture.mode = .interactive
        let (_, part) = try gesturesPart(interactiveAvailable: true)
        let controls = try XCTUnwrap(part.controls)
        let speed = try XCTUnwrap(part.trackingSpeedRow)
        XCTAssertTrue(part.directionRows[MouseGestureSettingsControls.Slot.left.rawValue].isEnabled, "the app's own mode: one action")
        XCTAssertFalse(speed.isEnabled)

        controls.modeControl.selectedSegment = 1
        send(controls.modeControl)
        XCTAssertEqual(calculator.ownGestures?.mode, .interactive)
        for slot in MouseGestureSettingsControls.Slot.allCases {
            XCTAssertEqual(part.directionRows[slot.rawValue].isEnabled, !slot.isHorizontal, slot.name)
            XCTAssertEqual(controls.actionPopUp(for: slot).isEnabled, !slot.isHorizontal, slot.name)
        }
        XCTAssertEqual(controls.actionPopUp(for: .left).menu?.items.first?.title, "Desktop follows the hand")
        XCTAssertEqual(controls.actionPopUp(for: .right).menu?.items.first?.title, MouseGestureSettingsControls.followHorizontalValue)
        XCTAssertTrue(speed.isEnabled, "the speed applies now")
        XCTAssertEqual(part.modeRow?.explanation, NSLocalizedString("gesture-mode-interactive-description", comment: ""))

        Options.shared.gesture.mode = .discrete
        part.syncViewWithOptions()
        XCTAssertFalse(part.directionRows[MouseGestureSettingsControls.Slot.left.rawValue].isEnabled, "the general mode is another")
        calculator.changeOwnGestures { $0.mode = .discrete }
        part.syncViewWithOptions()
        XCTAssertTrue(part.directionRows[MouseGestureSettingsControls.Slot.left.rawValue].isEnabled)
        XCTAssertEqual(controls.actionPopUp(for: .left).menu?.items.first?.title, SystemShortcut.moveSpaceLeft.localizedName)
    }

    /// The app's own set has every row of the Gestures pane but the button to hold, in
    /// the pane's order and made the pane's way: "Mode", then "Directions", "Behavior"
    /// (invert, freeze, speed) and "Logitech mouse" (there while a connected mouse can do
    /// one of its switches, as in the pane), then "Reset to Defaults". Each row changes the
    /// app's set and nothing of the general gestures.
    func testTheAppsSetHasThePanesRowsInItsOrderAndTheyEditTheApp() throws {
        let calculator = addApp(Self.calculator)
        Options.shared.buttons.binding = [binding(3, SystemShortcut.mouseGestureNavigation.identifier)]
        var general = MouseGestureSettings.default
        general.trackingSpeed = 1.5
        Options.shared.gesture = general
        calculator.setUsesGeneralGestures(false, general: general)
        let (pane, part) = try gesturesPart(interactiveAvailable: true, mice: MouseGestureDeviceSupport(deviceTracking: true, haptics: true))
        let controls = try XCTUnwrap(part.controls)

        // The order of the pane, under the switch's box.
        let order: [NSView?] = [
            part.generalSection, part.modeSection, part.directionsFold, part.behaviourFold, part.logitechFold, part.resetFooter,
        ]
        let shown = try order.map { try XCTUnwrap($0) }
        let stack = try XCTUnwrap(part.generalSection.superview as? NSStackView)
        XCTAssertEqual(stack.arrangedSubviews.filter { view in shown.contains { $0 === view } }.count, shown.count)
        let indices = shown.compactMap { view in stack.arrangedSubviews.firstIndex { $0 === view } }
        XCTAssertEqual(indices, indices.sorted())
        XCTAssertEqual([part.directionsFold, part.behaviourFold, part.logitechFold].map { $0?.title }, ["Directions", "Behavior", "Logitech mouse"])
        XCTAssertEqual(part.modeRow?.title, "Mode")
        XCTAssertTrue(controls.modeControl.isDescendant(of: try XCTUnwrap(part.modeRow)))
        let behaviour = try XCTUnwrap(part.behaviourFold?.body as? PreferencesGroupBox)
        XCTAssertEqual(behaviour.rows.map(\.title), ["Invert left and right", "Freeze pointer during a gesture", "Swipe speed"])
        let logitech = try XCTUnwrap(part.logitechFold?.body as? PreferencesGroupBox)
        XCTAssertEqual(logitech.rows.map(\.title), ["Let the mouse track the gesture (Beta)", "Pulse when a gesture locks in"])
        XCTAssertFalse(try XCTUnwrap(part.logitechFold).isHidden)
        XCTAssertEqual(part.trackingSpeedRow?.slider.identifier, MouseGestureSettingsControls.Identifier.trackingSpeed)
        XCTAssertEqual(part.trackingSpeedRow?.valueText, MouseGestureTrackingSpeed.text(1.5))
        XCTAssertEqual(part.freezeRow?.explanation, "The pointer stays where it is while you hold the button.")
        pane.detailController?.view.layoutSubtreeIfNeeded()
        XCTAssertFalse(part.view.hasAmbiguousLayout)

        // Each row writes the app's own value.
        let freeze = try XCTUnwrap(controls.freezeToggle as? NSSwitch)
        freeze.state = .off
        send(freeze)
        controls.modeControl.selectedSegment = 1
        send(controls.modeControl)
        let slider = try XCTUnwrap(part.trackingSpeedRow?.slider)
        slider.doubleValue = 2.6
        send(slider)
        let tracking = try XCTUnwrap(part.deviceTrackingRow?.toggle)
        tracking.state = .on
        send(tracking)
        let haptics = try XCTUnwrap(part.hapticsRow?.toggle)
        haptics.state = .off
        send(haptics)
        let own = try XCTUnwrap(calculator.ownGestures)
        XCTAssertEqual(own.freezePointer, false)
        XCTAssertEqual(own.mode, .interactive)
        XCTAssertEqual(own.trackingSpeed, 2.5, "on a tick")
        XCTAssertEqual(own.deviceTracking, true)
        XCTAssertEqual(own.hapticFeedback, false)
        XCTAssertEqual(part.trackingSpeedRow?.valueText, MouseGestureTrackingSpeed.text(2.5))
        XCTAssertEqual(Options.shared.gesture, general, "the general gestures are untouched")
        XCTAssertTrue(part.resetToDefaultsButton.isEnabled)

        // No mouse that can do either switch: the section goes, as in the pane; the values stay.
        part.deviceSource = MouseGestureDeviceSource(support: { .none }, refresh: {})
        part.syncViewWithOptions()
        XCTAssertTrue(try XCTUnwrap(part.logitechFold).isHidden)
        XCTAssertEqual(calculator.ownGestures?.deviceTracking, true)
        // Only haptics: both rows, the other dimmed with the pane's line.
        part.deviceSource = MouseGestureDeviceSource(support: { MouseGestureDeviceSupport(deviceTracking: false, haptics: true) }, refresh: {})
        part.syncViewWithOptions()
        XCTAssertFalse(try XCTUnwrap(part.logitechFold).isHidden)
        XCTAssertEqual(part.deviceTrackingRow?.isEnabled, false)
        XCTAssertEqual(part.deviceTrackingRow?.explanation, "No connected mouse supports this.")
        XCTAssertEqual(part.hapticsRow?.isEnabled, true)
    }

    /// As in the Gestures pane: while a mouse has its haptics off because they were switched
    /// off under Mouse, the app's own "Logitech mouse" box has the line that says so, with
    /// "Open Mouse", close under the box; it folds with the box (F18).
    func testTheGesturesPartSaysWhenHapticsAreOffUnderMouse() throws {
        let savedHaptics = Options.shared.logiMouse.hapticsOn
        Options.shared.logiMouse.hapticsOn = false
        addTeardownBlock { Options.shared.logiMouse.hapticsOn = savedHaptics }
        Options.shared.buttons.binding = [binding(3, SystemShortcut.mouseGestureNavigation.identifier)]
        let calculator = addApp(Self.calculator)
        calculator.setUsesGeneralGestures(false, general: Options.shared.gesture)
        let hapticsOff = MouseGestureDeviceSupport(deviceTracking: true, haptics: true, hapticsOffOnMouse: true)
        let (pane, part) = try gesturesPart(mice: hapticsOff)
        _ = makeWindow(for: pane)
        let note = try XCTUnwrap(part.hapticsOffNote)
        let fold = try XCTUnwrap(part.logitechFold)
        XCTAssertFalse(note.isHidden)
        XCTAssertEqual(part.hapticsOffLabel?.stringValue, "Haptic feedback is off under Mouse.")
        XCTAssertEqual(part.openMouseButton?.title, "Open Mouse")
        XCTAssertEqual(part.hapticsRow?.isOn, true, "the switch stays as it is")
        var opened = 0
        part.openMousePane = { opened += 1 }
        try XCTUnwrap(part.openMouseButton).performClick(nil)
        XCTAssertEqual(opened, 1)
        pane.view.layoutSubtreeIfNeeded()
        func frame(_ view: NSView) -> NSRect {
            return part.view.convert(view.alignmentRect(forFrame: view.frame), from: view.superview)
        }
        let gap = max(frame(fold).minY - frame(note).maxY, frame(note).minY - frame(fold).maxY)
        XCTAssertEqual(gap, PreferencesGroupedForm.noteSpacing, accuracy: 0.5, "close under the box")
        XCTAssertFalse(part.view.hasAmbiguousLayout)

        // Haptics on under Mouse: no line.
        Options.shared.logiMouse.hapticsOn = true
        part.syncViewWithOptions()
        XCTAssertTrue(note.isHidden)
        // Folded with its box while no button runs the gestures here; it opens with it.
        Options.shared.logiMouse.hapticsOn = false
        Options.shared.buttons.binding = []
        part.syncViewWithOptions()
        XCTAssertTrue(fold.isCollapsible)
        XCTAssertTrue(note.isHidden)
        XCTAssertTrue(fold.disclosure.accessibilityPerformPress())
        XCTAssertFalse(note.isHidden, "opens with its box")
    }

    /// One wording: while no button runs Gesture Navigation with the app in front
    /// (whatever Buttons has), the switch's own line says so, in both states, and there is
    /// no line under the box; the line under the box only names another button than
    /// Buttons' ("Button to hold while … is in front: …"). With the same button as in
    /// Buttons there is neither.
    func testTheGesturesPartSaysWhenTheButtonToHoldIsAnotherHere() throws {
        let gestures = SystemShortcut.mouseGestureNavigation.identifier
        let thumbPanel = LogiCenter.shared.scrollioCode(for: .thumbPanel)
        Options.shared.buttons.binding = [binding(thumbPanel, gestures), binding(3, "copy")]
        let calculator = addApp(Self.calculator)
        let general = ["While Calculator is in front, the general gestures run.", "While Calculator is in front, the gestures below run."]
        let none = "While Calculator is in front, no button runs the gestures: see its Buttons part."
        /// The switch's line in both states, and the line under the box (nil: none).
        func lines() throws -> (switchLines: [String], note: String?) {
            let (_, part) = try gesturesPart()
            let holder = try XCTUnwrap(part.buttonNoteLabel.superview)
            XCTAssertEqual(holder.isHidden, part.buttonNoteLabel.stringValue.isEmpty, "in sight exactly with a line")
            var switchLines = [part.generalGesturesRow.explanation ?? ""]
            part.generalGesturesSwitch.state = part.generalGesturesSwitch.state == .on ? .off : .on
            send(part.generalGesturesSwitch)
            switchLines.append(part.generalGesturesRow.explanation ?? "")
            part.generalGesturesSwitch.state = part.generalGesturesSwitch.state == .on ? .off : .on
            send(part.generalGesturesSwitch)
            return (switchLines, holder.isHidden ? nil : part.buttonNoteLabel.stringValue)
        }
        func check(_ switchLines: [String], _ note: String?, _ message: String, line: UInt = #line) throws {
            let shown = try lines()
            XCTAssertEqual(shown.switchLines, switchLines, message, line: line)
            XCTAssertEqual(shown.note, note, message, line: line)
        }
        try check(general, nil, "the button of Buttons")
        calculator.setOwnButtonBindings([binding(3, "paste")])
        try check(general, nil, "another button changed, not the one that runs the gestures")
        calculator.setOwnButtonBindings([binding(thumbPanel, gestures)])
        try check(general, nil, "the same button, also the app's own")

        calculator.setOwnButtonBindings([binding(thumbPanel, SystemShortcut.shortcutRing.identifier)])
        try check([none, none], nil, "the app's own buttons took it: the switch's line says so, nothing under the box")
        calculator.setOwnButtonBindings([binding(thumbPanel, SystemShortcut.shortcutRing.identifier), binding(3, gestures)])
        let back = ButtonTriggerNaming.title(for: RecordedEvent(type: .mouse, code: 3, modifiers: 0, deviceFilter: nil))
        try check(general, "Button to hold while Calculator is in front: \(back).", "another button")
        // Without a button in Buttons, one of the app's own is another one too.
        Options.shared.buttons.binding = []
        calculator.setOwnButtonBindings([binding(3, gestures)])
        try check(general, "Button to hold while Calculator is in front: \(back).", "only the app's own")
        // A key never runs the gestures; nor does anything, with none anywhere.
        calculator.setOwnButtonBindings([binding(40, gestures, modifiers: UInt(CGEventFlags.maskCommand.rawValue), type: .keyboard)])
        try check([none, none], nil, "a key")
        calculator.setOwnButtonBindings([])
        try check([none, none], nil, "none anywhere")
        XCTAssertTrue(calculator.usesGeneralGestures, "the switch was only tried")

        // The line sits close under the switch's box, and the app's own set keeps its gap.
        Options.shared.buttons.binding = [binding(thumbPanel, gestures)]
        calculator.setOwnButtonBindings([binding(thumbPanel, "copy"), binding(3, gestures)])
        calculator.setUsesGeneralGestures(false, general: Options.shared.gesture)
        let (pane, part) = try gesturesPart()
        _ = makeWindow(for: pane)
        pane.view.layoutSubtreeIfNeeded()
        let holder = try XCTUnwrap(part.buttonNoteLabel.superview)
        // (The own set begins with "Mode", as the pane's first box ends with it.)
        let ownSet = try XCTUnwrap(part.modeSection)
        let section = part.generalSection!
        func gap(_ upper: NSView, _ lower: NSView) -> CGFloat {
            let a = upper.convert(upper.bounds, to: nil), b = lower.convert(lower.bounds, to: nil)
            return a.minY - b.maxY
        }
        XCTAssertFalse(holder.isHidden)
        XCTAssertEqual(gap(section, holder), PreferencesGroupedForm.noteSpacing, accuracy: 0.5)
        XCTAssertEqual(gap(holder, ownSet), PreferencesGroupedForm.sectionSpacing, accuracy: 0.5)
        XCTAssertFalse(part.view.hasAmbiguousLayout)
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
        let gestures = SystemShortcut.mouseGestureNavigation.identifier
        let back = binding(3, gestures)
        let ownBack = Application(path: Self.textEdit)
        ownBack.displayName = long.displayName
        ownBack.setOwnButtonBindings([binding(4, gestures)])
        let notes = [
            ApplicationGesturesPartViewController.buttonNote(for: long, general: [back]) ?? "",
            ApplicationGesturesPartViewController.buttonNote(for: ownBack, general: []) ?? "",
        ]
        long.setOwnButtonBindings([binding(3, "copy")])
        XCTAssertNil(ApplicationGesturesPartViewController.buttonNote(for: long, general: [back]), "none: the switch's line says it")
        let none = ApplicationDetailViewController.generalGesturesExplanation(on: true, name: long.displayName!, hasButton: false)
        XCTAssertEqual(none, ApplicationDetailViewController.generalGesturesExplanation(on: false, name: long.displayName!, hasButton: false))
        let texts = [true, false].map { ApplicationDetailViewController.generalGesturesExplanation(on: $0, name: long.displayName!) }
            + notes + [none]
        XCTAssertEqual(notes[0], "", "the same button as in Buttons: no line")
        for text in texts.filter({ !$0.isEmpty }) {
            XCTAssertTrue(text.contains(long.displayName!))
            XCTAssertTrue(text.hasSuffix("."))
            let height = (text as NSString).boundingRect(
                with: NSSize(width: label.frame.width, height: 1000), options: [.usesLineFragmentOrigin], attributes: [.font: font]
            ).height
            XCTAssertLessThanOrEqual(height, twoLines, text)
        }
        XCTAssertEqual(texts.filter { !$0.isEmpty }.count, 4)
    }

    // MARK: - The Shortcut Ring part

    /// The switch's line counts the app's own buttons: with the app in front the ring opens
    /// by a button of its own only (nothing in Buttons), or nothing opens it because its own
    /// buttons gave what opens it elsewhere another action, or nothing opens it anywhere.
    func testTheRingPartsLineSaysWhatOpensTheRingWithTheAppInFront() throws {
        let ring = SystemShortcut.shortcutRing.identifier
        let calculator = addApp(Self.calculator)
        func lines() throws -> [String] {
            let pane = makePane()
            pane.openApplication(withID: Self.calculator, part: .ring)
            let page = try XCTUnwrap(pane.detailController)
            var result = [page.generalRingRow.explanation ?? ""]
            page.generalRingSwitch.state = page.generalRingSwitch.state == .on ? .off : .on
            send(page.generalRingSwitch)
            result.append(page.generalRingRow.explanation ?? "")
            page.generalRingSwitch.state = page.generalRingSwitch.state == .on ? .off : .on
            send(page.generalRingSwitch)
            return result
        }
        let opens = ["While Calculator is in front, the general ring opens.", "While Calculator is in front, the ring below opens."]
        let nothing = "Nothing opens the ring yet: set up a button or key for it in the Shortcut Ring pane."
        let replaced = "While Calculator is in front, nothing opens the ring: see its Buttons part."

        XCTAssertEqual(try lines(), [nothing, nothing], "nothing anywhere")
        calculator.setOwnButtonBindings([binding(6, ring)])
        XCTAssertEqual(try lines(), opens, "a button that opens the ring only in this app")

        Options.shared.buttons.binding = [binding(6, ring)]
        calculator.setOwnButtonBindings([binding(6, "copy")])
        XCTAssertEqual(try lines(), [replaced, replaced], "the ring's button does something else here")
        let controlSpace = binding(49, ring, modifiers: UInt(CGEventFlags.maskControl.rawValue), type: .keyboard)
        calculator.setOwnButtonBindings([binding(6, "copy"), controlSpace])
        XCTAssertEqual(try lines(), opens, "a key of its own opens it here")
        calculator.setOwnButtonBindings([binding(5, "copy")])
        XCTAssertEqual(try lines(), opens, "Buttons' button opens it here too")
        calculator.setOwnButtonBindings([binding(6, "")])
        XCTAssertEqual(try lines(), [replaced, replaced], "\"Default\" here: the button does what it does by itself")

        // Nothing in Buttons, but another app's own button opens it: not "yet", and not here.
        Options.shared.buttons.binding = []
        calculator.setOwnButtonBindings([])
        addApp(Self.textEdit).setOwnButtonBindings([binding(6, ring)])
        XCTAssertEqual(try lines(), [replaced, replaced], "it opens in TextEdit, not with Calculator in front")
        XCTAssertTrue(calculator.usesGeneralRing, "the switch was only tried")
    }

    /// The box fits the line it shows (as the Gestures part's does): it keeps room only for
    /// the longer of the two lines the switch alternates, not for a two-line line on what
    /// opens the ring, which takes its room only while it shows.
    func testTheRingPartsBoxFitsItsLine() throws {
        Options.shared.buttons.binding = [binding(6, SystemShortcut.shortcutRing.identifier)]
        addApp(Self.calculator)
        let pane = makePane()
        _ = makeWindow(for: pane)
        pane.openApplication(withID: Self.calculator, part: .ring)
        let page = try XCTUnwrap(pane.detailController)
        let font = PreferencesGroupedForm.explanationFont
        let oneLine = ceil(font.ascender - font.descender + font.leading) + 1
        func height() -> CGFloat {
            page.view.layoutSubtreeIfNeeded()
            return page.generalRingRow.explanationLabel.frame.height
        }
        XCTAssertEqual(page.generalRingRow.explanation, "While Calculator is in front, the general ring opens.")
        XCTAssertLessThanOrEqual(height(), oneLine, "no empty line kept")

        Options.shared.buttons.binding = []
        page.syncViewWithOptions()
        XCTAssertEqual(page.generalRingRow.explanation, "Nothing opens the ring yet: set up a button or key for it in the Shortcut Ring pane.")
        XCTAssertGreaterThan(height(), oneLine, "the longer line takes its room")
    }

    /// The switch's lines fit two lines, also for an app with a long name: the box keeps
    /// room for the longer of the two the switch alternates, so switching never moves what
    /// is below.
    func testTheRingSwitchsLinesFitTwoLines() throws {
        let long = addApp(Self.calculator)
        long.displayName = "An Application With A Remarkably Long Name For Its Kind"
        let pane = makePane()
        _ = makeWindow(for: pane)
        pane.openApplication(withID: Self.calculator, part: .ring)
        let page = try XCTUnwrap(pane.detailController)
        page.view.layoutSubtreeIfNeeded()
        let label = page.generalRingRow.explanationLabel
        let font = PreferencesGroupedForm.explanationFont
        let twoLines = 2 * ceil(font.ascender - font.descender + font.leading) + 2
        XCTAssertGreaterThan(label.frame.width, 300)
        let name = long.displayName!
        let texts = [true, false].map { ApplicationDetailViewController.generalRingExplanation(on: $0, name: name) }
            + [ApplicationDetailViewController.RingTrigger.noTrigger, .replacedHere].map {
                ApplicationDetailViewController.generalRingExplanation(on: true, name: name, opens: $0)
            }
        XCTAssertEqual(Set(texts).count, 4)
        XCTAssertEqual(page.generalRingRow.reservedExplanations, Array(texts.prefix(2)), "only the two the switch alternates")
        for text in texts {
            XCTAssertTrue(text.hasSuffix("."))
            let height = (text as NSString).boundingRect(
                with: NSSize(width: label.frame.width, height: 1000), options: [.usesLineFragmentOrigin], attributes: [.font: font]
            ).height
            XCTAssertLessThanOrEqual(height, twoLines, text)
        }
    }

    // MARK: - What opens the ring and runs the gestures, the apps' own buttons counted

    /// One rule for the panes and the parts (`ApplicationTriggerRule`): with an app on the
    /// list in front, Buttons' bindings with the app's own in them, as a press goes by them;
    /// "only in apps" while nothing of Buttons does it.
    func testOneRuleCountsTheAppsOwnButtonsForTheRingAndTheGestures() {
        let ringAction = SystemShortcut.shortcutRing.identifier
        let gestures = SystemShortcut.mouseGestureNavigation.identifier
        let thumbPanel = LogiCenter.shared.scrollioCode(for: .thumbPanel)
        let general = [binding(thumbPanel, gestures), binding(3, "copy")]
        let calculator = addApp(Self.calculator)
        calculator.setOwnButtonBindings([binding(thumbPanel, ringAction)])
        let textEdit = addApp(Self.textEdit)
        textEdit.setOwnButtonBindings([binding(4, "paste")])
        let ring = ApplicationTriggerRule.shortcutRing, gesture = ApplicationTriggerRule.gestureNavigation
        let apps = [calculator, textEdit]

        XCTAssertTrue(ring.bindings(general: general).isEmpty)
        XCTAssertEqual(ring.bindings(general: general, own: calculator.ownButtonBindings).map(\.id), [calculator.ownButtonBindings[0].id])
        XCTAssertTrue(ring.bindings(general: general, own: textEdit.ownButtonBindings).isEmpty)
        XCTAssertEqual(gesture.bindings(general: general).map(\.id), [general[0].id])
        XCTAssertTrue(gesture.bindings(general: general, own: calculator.ownButtonBindings).isEmpty, "the app took it")
        let only = ring.onlyInApps(general: general, applications: apps)
        XCTAssertEqual(only.map(\.application.path), [Self.calculator])
        XCTAssertTrue(gesture.onlyInApps(general: general, applications: apps).isEmpty, "Buttons runs the gestures: not only in apps")
        XCTAssertTrue(ring.onlyInApps(general: general + [binding(5, ringAction)], applications: apps).isEmpty)

        // What runs: an enabled binding; for the ring a button or a key, for the gestures a button.
        let command = UInt(CGEventFlags.maskCommand.rawValue)
        XCTAssertTrue(ring.takes(binding(40, ringAction, modifiers: command, type: .keyboard)))
        XCTAssertFalse(gesture.takes(binding(40, gestures, modifiers: command, type: .keyboard)))
        var disabled = binding(6, ringAction)
        disabled.isEnabled = false
        XCTAssertFalse(ring.takes(disabled))
        textEdit.setOwnButtonBindings([disabled])
        XCTAssertEqual(ring.onlyInApps(general: general, applications: apps).map(\.application.path), [Self.calculator])
    }

    /// The Shortcut Ring pane counts the apps' own buttons: while only an app's own button
    /// opens the ring, its row says where and with what (not "Nothing opens the ring yet"),
    /// and its button reads "Change" and leads to that app's Buttons part, not "Set Up…".
    func testTheRingPaneSaysWhereOnlyAnAppsOwnButtonOpensTheRing() throws {
        let ringAction = SystemShortcut.shortcutRing.identifier
        let thumbPanel = LogiCenter.shared.scrollioCode(for: .thumbPanel)
        Options.shared.buttons.binding = [binding(thumbPanel, SystemShortcut.mouseGestureNavigation.identifier)]
        let calculator = addApp(Self.calculator)
        let textEdit = addApp(Self.textEdit)
        func pane() -> RingPreferencesViewController {
            let pane = RingPreferencesViewController()
            _ = pane.view
            return pane
        }
        XCTAssertEqual(pane().triggerRow.explanation,
                       "Nothing opens the ring yet. A key combination works too, even one that Logi Options+ sends for a button.")
        XCTAssertEqual(pane().triggerButton.title, "Set Up…")
        let key = " A key combination works too."

        calculator.setOwnButtonBindings([binding(thumbPanel, ringAction)])
        let panel = ButtonTriggerNaming.title(for: calculator.ownButtonBindings[0].triggerEvent)
        var ring = pane()
        XCTAssertEqual(ring.triggerRow.explanation, "Only in Calculator: \(panel)." + key)
        XCTAssertEqual(ring.triggerButton.title, "Change")
        var shown: [ApplicationTriggers] = []
        ring.openApplicationButtons = { shown.append($0) }
        ring.openButtonsPane = { _ in XCTFail("not the Buttons pane") }
        ring.triggerButton.performClick(nil)
        XCTAssertEqual(shown.map(\.path), [Self.calculator])
        XCTAssertEqual(shown.first?.bindingID, calculator.ownButtonBindings[0].id)

        let control = UInt(CGEventFlags.maskControl.rawValue)
        textEdit.setOwnButtonBindings([binding(49, ringAction, modifiers: control, type: .keyboard)])
        let space = ButtonTriggerNaming.title(for: textEdit.ownButtonBindings[0].triggerEvent)
        ring = pane()
        // (Each app with its own: the row never reads as if both worked in both, F28.)
        XCTAssertEqual(ring.triggerRow.explanation, "Only in Calculator (\(panel)) and TextEdit (\(space))." + key)
        // The same in both: once, after the apps.
        textEdit.setOwnButtonBindings([binding(thumbPanel, ringAction)])
        XCTAssertEqual(pane().triggerRow.explanation, "Only in Calculator and TextEdit: \(panel)." + key)
        // Each with its own ring too.
        calculator.setUsesGeneralRing(false, general: Options.shared.ring)
        textEdit.setOwnButtonBindings([binding(49, ringAction, modifiers: control, type: .keyboard)])
        textEdit.setUsesGeneralRing(false, general: Options.shared.ring)
        XCTAssertEqual(
            pane().triggerRow.explanation,
            "Only in Calculator (\(panel)) and TextEdit (\(space)), each with its own ring." + key
        )
        calculator.setUsesGeneralRing(true, general: Options.shared.ring)
        textEdit.setUsesGeneralRing(true, general: Options.shared.ring)

        // With a binding of Buttons the row names that one alone, as before.
        Options.shared.buttons.binding.append(binding(5, ringAction))
        ring = pane()
        XCTAssertEqual(ring.bindingSummary().onlyInApps, nil)
        XCTAssertEqual(ring.triggerButton.title, "Change")
        XCTAssertFalse(ring.triggerRow.explanation?.hasPrefix("Only in") ?? true)
    }

    /// While the only apps whose own buttons open the ring (or run the gestures) use their
    /// own ring (or gestures), nothing runs the general settings: the panes fold them as
    /// when nothing opens the ring, and their rows say so; "Change" still leads to the app.
    func testThePanesFoldTheGeneralSettingsWhileOnlyAnAppWithItsOwnUsesTheTrigger() throws {
        let ringAction = SystemShortcut.shortcutRing.identifier
        let gestureAction = SystemShortcut.mouseGestureNavigation.identifier
        let thumbPanel = LogiCenter.shared.scrollioCode(for: .thumbPanel)
        Options.shared.buttons.binding = []
        let calculator = addApp(Self.calculator)
        calculator.setOwnButtonBindings([binding(thumbPanel, ringAction), binding(3, gestureAction)])
        let panel = ButtonTriggerNaming.title(for: calculator.ownButtonBindings[0].triggerEvent)
        let back = ButtonTriggerNaming.title(for: calculator.ownButtonBindings[1].triggerEvent)

        calculator.setUsesGeneralRing(false, general: Options.shared.ring)
        let ring = RingPreferencesViewController()
        _ = ring.view
        let places = try XCTUnwrap(ring.placesSection)
        XCTAssertTrue(places.isCollapsible, "nothing opens the general ring")
        XCTAssertFalse(places.showsBody)
        XCTAssertEqual(ring.triggerRow.explanation, "Only in Calculator, with its own ring: \(panel). A key combination works too.")
        XCTAssertEqual(ring.triggerButton.title, "Change")
        var shown: [ApplicationTriggers] = []
        ring.openApplicationButtons = { shown.append($0) }
        ring.openButtonsPane = { _ in XCTFail("not the Buttons pane") }
        ring.triggerButton.performClick(nil)
        XCTAssertEqual(shown.map(\.path), [Self.calculator])
        // With the general ring on again, it is the one that opens there.
        calculator.setUsesGeneralRing(true, general: Options.shared.ring)
        ring.reload()
        XCTAssertFalse(places.isCollapsible)
        XCTAssertEqual(ring.triggerRow.explanation, "Only in Calculator: \(panel). A key combination works too.")

        calculator.setUsesGeneralGestures(false, general: Options.shared.gesture)
        let gestures = GesturesPreferencesViewController(isInteractiveAvailable: { false })
        gestures.deviceSource = MouseGestureDeviceSource(support: { .none }, refresh: {})
        _ = gestures.view
        gestures.reload()
        XCTAssertTrue(gestures.foldingSections.allSatisfy { $0.isCollapsible && !$0.showsBody }, "nothing runs the general gestures")
        XCTAssertEqual(gestures.gestureButtonRow.explanation, "Only in Calculator, with its own gestures: \(back).")
        XCTAssertEqual(gestures.gestureButtonButton.title, "Change")
        calculator.setUsesGeneralGestures(true, general: Options.shared.gesture)
        gestures.reload()
        XCTAssertTrue(gestures.foldingSections.allSatisfy { !$0.isCollapsible })

        // Two apps, one with the general ring: the general ring opens there.
        calculator.setUsesGeneralRing(false, general: Options.shared.ring)
        let textEdit = addApp(Self.textEdit)
        textEdit.setOwnButtonBindings([binding(thumbPanel, ringAction)])
        ring.reload()
        XCTAssertFalse(places.isCollapsible)
        XCTAssertNil(ring.bindingSummary().onlyInApps?.ownOnly)
        textEdit.setUsesGeneralRing(false, general: Options.shared.ring)
        ring.reload()
        XCTAssertTrue(places.isCollapsible)
        XCTAssertEqual(ring.triggerRow.explanation, "Only in Calculator and TextEdit, each with its own ring: \(panel). A key combination works too.")
    }

    /// The Gestures pane likewise: Gesture Navigation only on an app's own button. The
    /// gesture actions offer the Logitech ones when a Logitech button runs the gestures
    /// with some app in front.
    func testTheGesturesPaneSaysWhereOnlyAnAppsOwnButtonRunsTheGestures() throws {
        let gestures = SystemShortcut.mouseGestureNavigation.identifier
        let thumbPanel = LogiCenter.shared.scrollioCode(for: .thumbPanel)
        Options.shared.buttons.binding = [binding(thumbPanel, SystemShortcut.shortcutRing.identifier)]
        let calculator = addApp(Self.calculator)
        calculator.setOwnButtonBindings([binding(3, gestures)])
        let pane = GesturesPreferencesViewController(isInteractiveAvailable: { false })
        pane.deviceSource = MouseGestureDeviceSource(support: { .none }, refresh: {})
        _ = pane.view
        pane.reload()
        let back = ButtonTriggerNaming.title(for: calculator.ownButtonBindings[0].triggerEvent)
        XCTAssertEqual(pane.gestureButtonRow.explanation, "Only in Calculator: \(back).")
        XCTAssertEqual(pane.gestureButtonButton.title, "Change")
        var shown: [ApplicationTriggers] = []
        pane.openApplicationButtons = { shown.append($0) }
        pane.openButtonsPane = { _ in XCTFail("not the Buttons pane") }
        pane.gestureButtonButton.performClick(nil)
        XCTAssertEqual(shown.map(\.path), [Self.calculator])
        XCTAssertFalse(MouseGestureBindingSummary.current.hasLogitechGestureButton)

        calculator.setOwnButtonBindings([binding(thumbPanel, gestures)])
        XCTAssertTrue(MouseGestureBindingSummary.current.hasLogitechGestureButton, "the app's own Logitech button")
        calculator.setOwnButtonBindings([])
        pane.reload()
        XCTAssertEqual(pane.gestureButtonRow.explanation, "No button yet. Set one up to use gestures.")
        XCTAssertEqual(pane.gestureButtonButton.title, "Set Up…")
    }

    /// An app's Gestures part offers the Logitech actions when the button that runs the
    /// gestures with that app in front is a Logitech one, whatever Buttons' is.
    func testTheGesturesPartOffersLogitechActionsByTheButtonWithTheAppInFront() {
        let gestures = SystemShortcut.mouseGestureNavigation.identifier
        let thumbPanel = LogiCenter.shared.scrollioCode(for: .thumbPanel)
        Options.shared.buttons.binding = [binding(3, gestures)]
        let calculator = addApp(Self.calculator)
        calculator.setOwnButtonBindings([binding(thumbPanel, gestures)])
        let textEdit = addApp(Self.textEdit)
        XCTAssertTrue(ApplicationGesturesPartViewController(application: calculator).showsLogiActions())
        XCTAssertFalse(ApplicationGesturesPartViewController(application: textEdit).showsLogiActions())
        Options.shared.buttons.binding = [binding(thumbPanel, gestures)]
        textEdit.setOwnButtonBindings([binding(thumbPanel, "copy"), binding(3, gestures)])
        XCTAssertFalse(ApplicationGesturesPartViewController(application: textEdit).showsLogiActions(), "the app's own button is not one")
    }

    /// "Change" of the Shortcut Ring pane in the window, while only an app's own button
    /// opens the ring: the Apps pane, that app's page on its Buttons part, the row selected.
    func testChangeInTheRingPaneShowsTheAppsButtonsPartWithTheRowSelected() throws {
        let thumbPanel = LogiCenter.shared.scrollioCode(for: .thumbPanel)
        let calculator = addApp(Self.calculator)
        calculator.setOwnButtonBindings([binding(4, "copy"), binding(thumbPanel, SystemShortcut.shortcutRing.identifier)])
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesSplitViewController.self))
        let preferences = PreferencesSplitViewController(storyboard: storyboard, uiStateDefaults: nil)
        let apps = try XCTUnwrap(preferences.controller(for: PANEL_IDENTIFIER.application) as? PreferencesApplicationViewController)
        apps.uiStateDefaults = uiDefaults
        let ring = try XCTUnwrap(preferences.controller(for: RingPreferencesViewController.tabIdentifier) as? RingPreferencesViewController)
        XCTAssertTrue(preferences.selectPane(withIdentifier: RingPreferencesViewController.tabIdentifier))
        XCTAssertEqual(ring.triggerButton.title, "Change")
        ring.triggerButton.performClick(nil)
        XCTAssertEqual(preferences.selectedPaneIdentifier, PANEL_IDENTIFIER.application)
        let page = try XCTUnwrap(apps.detailController)
        XCTAssertEqual(page.application.path, Self.calculator)
        XCTAssertEqual(page.shownPart, .buttons)
        XCTAssertEqual(page.buttonsPart.list.selectedID, AnyHashable(calculator.ownButtonBindings[1].id))
    }

    // MARK: - Folded while nothing runs them here

    /// The app's own ring while nothing opens the ring with the app in front: its eight rows
    /// under a "Shortcuts" title that folds them, folded; the drawing, the freeze switch and
    /// "Reset to Defaults" in sight, as in the Shortcut Ring pane (F23). A click opens the
    /// rows and all of it can be used; the page measures again each time. Once a button
    /// opens the ring there, "Shortcuts" is a plain title; without one again the rows fold
    /// again. The switch alone (the general ring) has nothing to fold.
    func testTheRingPartFoldsTheOwnRingWhileNothingOpensTheRingHere() throws {
        let calculator = addApp(Self.calculator)
        let pane = makePane()
        _ = makeWindow(for: pane)
        pane.openApplication(withID: Self.calculator, part: .ring)
        let page = try XCTUnwrap(pane.detailController)
        let part = try XCTUnwrap(page.ringPart)
        XCTAssertNil(part.ownRingFold, "the general ring: nothing below the switch")

        var heightChanges = 0
        page.onHeightChange = { heightChanges += 1 }
        page.generalRingSwitch.state = .off
        send(page.generalRingSwitch)
        XCTAssertFalse(calculator.usesGeneralRing)
        let fold = try XCTUnwrap(part.ownRingFold)
        let body = try XCTUnwrap(part.ownRingBody)
        let ring = try XCTUnwrap(part.ringController)
        XCTAssertTrue(fold === ring.placesSection)
        XCTAssertTrue(fold.isDescendant(of: body))
        XCTAssertEqual(fold.title, "Shortcuts")
        XCTAssertTrue(fold.isCollapsible)
        XCTAssertFalse(fold.isExpanded, "folded when it comes")
        XCTAssertTrue(fold.body.isHidden)
        XCTAssertTrue(ring.placeRows[0].isHiddenOrHasHiddenAncestor)
        XCTAssertTrue(ring.view.isDescendant(of: body))
        XCTAssertTrue(part.resetToDefaultsButton.isDescendant(of: body))
        // What the pane keeps outside its fold stays in sight here too.
        XCTAssertFalse(body.isHidden)
        XCTAssertFalse(ring.previewView.isHiddenOrHasHiddenAncestor)
        XCTAssertFalse(try XCTUnwrap(ring.freezeToggle).isHiddenOrHasHiddenAncestor)
        XCTAssertFalse(part.resetToDefaultsButton.isHiddenOrHasHiddenAncestor)
        XCTAssertEqual(fold.disclosure.accessibilityRole(), .disclosureTriangle)
        XCTAssertEqual(fold.disclosure.accessibilityLabel(), "Shortcuts")
        pane.view.layoutSubtreeIfNeeded()
        XCTAssertFalse(part.view.hasAmbiguousLayout)
        let folded = page.view.fittingSize.height

        heightChanges = 0
        XCTAssertTrue(fold.disclosure.accessibilityPerformPress())
        XCTAssertTrue(fold.isExpanded)
        XCTAssertFalse(fold.body.isHidden)
        XCTAssertEqual(heightChanges, 1, "the page measures again")
        XCTAssertGreaterThan(page.view.fittingSize.height, folded)
        // Everything in it can be used.
        try XCTUnwrap(part.ringController).placePopUps[0].onShortcutSelected?(SystemShortcut.paste)
        XCTAssertEqual(calculator.ownRingPlaces?[0].action, "paste")
        XCTAssertTrue(part.resetToDefaultsButton.isEnabled)

        // A button opens the ring: a plain title, the ring right under the switch's box.
        Options.shared.buttons.binding = [binding(5, SystemShortcut.shortcutRing.identifier)]
        part.syncViewWithOptions()
        XCTAssertNil(part.ownRingFold)
        XCTAssertFalse(fold.isCollapsible)
        XCTAssertFalse(fold.titleLabel.isHidden, "Shortcuts")
        XCTAssertFalse(fold.body.isHidden)
        XCTAssertTrue(body.superview === part.view)
        pane.view.layoutSubtreeIfNeeded()
        let ringView = try XCTUnwrap(part.ringController).view
        XCTAssertEqual(ringView.convert(ringView.bounds, to: part.view).maxY, part.ringSection.frame.minY, accuracy: 0.5)
        XCTAssertFalse(part.view.hasAmbiguousLayout)

        // The app's own buttons take it here: folded again.
        calculator.setOwnButtonBindings([binding(5, "copy")])
        part.syncViewWithOptions()
        XCTAssertEqual(part.ownRingFold?.isExpanded, false)
        XCTAssertTrue(fold.body.isHidden)
        XCTAssertTrue(part.ownRingFold === fold)
        XCTAssertFalse(part.resetToDefaultsButton.isHiddenOrHasHiddenAncestor)

        // Back to the general ring: nothing is left below the switch.
        page.generalRingSwitch.state = .on
        send(page.generalRingSwitch)
        XCTAssertNil(part.ownRingFold)
        XCTAssertNil(part.ownRingBody)
        XCTAssertNil(part.ringController)
    }

    /// The own ring folded under "Shortcuts", never opened, and then something starts to
    /// open the ring with the app in front (a binding added in Buttons, or in the app's
    /// Buttons part): the ring and "Reset to Defaults" stand right under the switch's box,
    /// in sight and reachable, not a blank of their height (R3-1 F1).
    func testTheFoldedOwnRingShowsWhenSomethingStartsToOpenTheRing() throws {
        let calculator = addApp(Self.calculator)
        calculator.setUsesGeneralRing(false, general: .default)
        let pane = makePane()
        _ = makeWindow(for: pane)
        pane.openApplication(withID: Self.calculator, part: .ring)
        let part = try XCTUnwrap(pane.detailController?.ringPart)
        let fold = try XCTUnwrap(part.ownRingFold)
        XCTAssertFalse(fold.isExpanded, "folded, and left so")
        XCTAssertTrue(try XCTUnwrap(part.ringController).placeRows[0].isHiddenOrHasHiddenAncestor)
        // A click on a place of the drawing opens the rows, and the page measures again.
        var heightChanges = 0
        pane.detailController?.onHeightChange = { heightChanges += 1 }
        try XCTUnwrap(part.ringController).selectPlace(2)
        XCTAssertTrue(fold.isExpanded)
        XCTAssertEqual(heightChanges, 1)
        fold.setExpanded(false)

        Options.shared.buttons.binding = [binding(5, SystemShortcut.shortcutRing.identifier)]
        part.syncViewWithOptions()
        XCTAssertNil(part.ownRingFold)
        let body = try XCTUnwrap(part.ownRingBody)
        XCTAssertFalse(body.isHidden)
        XCTAssertEqual(body.alphaValue, 1)
        XCTAssertFalse(try XCTUnwrap(part.ringController).view.isHiddenOrHasHiddenAncestor)
        XCTAssertFalse(part.resetToDefaultsButton.isHiddenOrHasHiddenAncestor)
        pane.view.layoutSubtreeIfNeeded()
        let ringView = try XCTUnwrap(part.ringController).view
        XCTAssertEqual(ringView.convert(ringView.bounds, to: part.view).maxY, part.ringSection.frame.minY, accuracy: 0.5)
        XCTAssertFalse(part.view.hasAmbiguousLayout)
    }

    /// "Reset to Defaults" under an app's own ring keeps room for its focus ring (Full
    /// Keyboard Access, Tab to it): no view between it and the part cuts what is drawn
    /// around it, in the open fold or under the switch's box (R3-1 F2).
    func testTheRingPartsResetButtonKeepsRoomForItsFocusRing() throws {
        let calculator = addApp(Self.calculator)
        calculator.setUsesGeneralRing(false, general: .default)
        let pane = makePane()
        _ = makeWindow(for: pane)
        pane.openApplication(withID: Self.calculator, part: .ring)
        let part = try XCTUnwrap(pane.detailController?.ringPart)
        func checkRoom(_ place: String) {
            pane.view.layoutSubtreeIfNeeded()
            let button = part.resetToDefaultsButton
            // The focus ring is drawn about 3 pt outside the button.
            let focus = button.bounds.insetBy(dx: -4, dy: -4)
            var view = button.superview
            while let current = view {
                if current.clipsToBounds {
                    XCTAssertTrue(current.bounds.contains(current.convert(focus, from: button)), "\(place): \(type(of: current)) cuts it")
                }
                if current === part.view { break }
                view = current.superview
            }
        }
        try XCTUnwrap(part.ownRingFold).setExpanded(true)
        checkRoom("in the open fold")
        Options.shared.buttons.binding = [binding(5, SystemShortcut.shortcutRing.identifier)]
        part.syncViewWithOptions()
        XCTAssertNil(part.ownRingFold)
        checkRoom("under the switch's box")
        // The ring's view still reaches no further than the body: a title above it stays
        // uncovered.
        let body = try XCTUnwrap(part.ownRingBody)
        let ringView = try XCTUnwrap(part.ringController).view
        let shown = try XCTUnwrap(ringView.superview).convert(ringView.superview!.bounds, to: body)
        XCTAssertGreaterThanOrEqual(shown.minY, body.bounds.minY - 0.5)
        XCTAssertLessThanOrEqual(shown.maxY, body.bounds.maxY + 0.5)
    }

    /// The app's own gestures while no button runs Gesture Navigation with the app in
    /// front: "Directions" folds the five rows, the invert switch and "Reset to Defaults";
    /// a click opens them, and the page measures again. Once a button runs the gestures
    /// there, "Directions" is a plain title over the set, as before, at the same place.
    func testTheGesturesPartFoldsTheOwnSetWhileNoButtonRunsTheGesturesHere() throws {
        let calculator = addApp(Self.calculator)
        calculator.setUsesGeneralGestures(false, general: Options.shared.gesture)
        let (pane, part) = try gesturesPart()
        _ = makeWindow(for: pane)
        let page = try XCTUnwrap(pane.detailController)
        let fold = try XCTUnwrap(part.directionsFold)
        XCTAssertEqual(fold.title, "Directions")
        XCTAssertEqual(part.foldingSections.map(\.title), ["Directions", "Behavior", "Logitech mouse"])
        for section in part.foldingSections {
            XCTAssertTrue(section.isCollapsible, section.title)
            XCTAssertFalse(section.isExpanded, section.title)
            XCTAssertTrue(section.body.isHidden, section.title)
        }
        XCTAssertTrue(try XCTUnwrap(part.directionsSection).isDescendant(of: fold.body))
        XCTAssertTrue(try XCTUnwrap(part.invertRow).isDescendant(of: try XCTUnwrap(part.behaviourFold).body))
        // "Mode" and "Reset to Defaults" stay in sight, as in the Gestures pane.
        XCTAssertFalse(try XCTUnwrap(part.modeSection).isHiddenOrHasHiddenAncestor)
        XCTAssertFalse(part.resetFooter.isHiddenOrHasHiddenAncestor)
        // Folded, "Mode" stands where a titled section does. (Not checked for an
        // ambiguous layout: the test's window makes the pane taller than the part, which
        // a short part, as the switch alone, does not pin; the unfolded set is checked.)
        pane.view.layoutSubtreeIfNeeded()
        let section = try XCTUnwrap(part.generalSection)
        let mode = try XCTUnwrap(part.modeSection)
        func gap() -> CGFloat {
            return section.convert(section.bounds, to: nil).minY - mode.convert(mode.bounds, to: nil).maxY
        }
        XCTAssertEqual(gap(), PreferencesGroupedForm.sectionSpacing, accuracy: 0.5)
        let folded = page.view.fittingSize.height

        var heightChanges = 0
        page.onHeightChange = { heightChanges += 1 }
        fold.toggle()
        XCTAssertTrue(fold.isExpanded)
        XCTAssertFalse(fold.body.isHidden)
        XCTAssertEqual(heightChanges, 1)
        XCTAssertGreaterThan(page.view.fittingSize.height, folded)
        // Everything in it can be used.
        try XCTUnwrap(part.controls).store(GestureAction(SystemShortcut.paste), in: .down)
        XCTAssertEqual(calculator.ownGestures?.actions.down, GestureAction(SystemShortcut.paste))
        XCTAssertTrue(part.resetToDefaultsButton.isEnabled)

        // A button runs the gestures: a plain title, the set in sight, where a titled
        // section stands.
        Options.shared.buttons.binding = [binding(3, SystemShortcut.mouseGestureNavigation.identifier)]
        part.syncViewWithOptions()
        XCTAssertTrue(part.directionsFold === fold)
        for section in part.foldingSections {
            XCTAssertFalse(section.isCollapsible, section.title)
            XCTAssertFalse(section.titleLabel.isHidden, section.title)
            XCTAssertTrue(section.disclosure.isHidden, section.title)
            XCTAssertFalse(section.body.isHidden, section.title)
        }
        pane.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(gap(), PreferencesGroupedForm.sectionSpacing, accuracy: 0.5)
        XCTAssertFalse(part.view.hasAmbiguousLayout)

        // None again: folded again.
        Options.shared.buttons.binding = []
        part.syncViewWithOptions()
        XCTAssertTrue(fold.isCollapsible)
        XCTAssertFalse(fold.isExpanded)
    }
}
