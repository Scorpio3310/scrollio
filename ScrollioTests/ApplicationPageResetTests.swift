//
//  ApplicationPageResetTests.swift
//  ScrollioTests
//
//  The button at the bottom of an app's Shortcut Ring, Gestures and Buttons parts, named by
//  what it does ("Copy from Shortcut Ring", "Copy from Gestures", "Remove All Buttons"):
//  where each leads (the ring where it started, a copy of the general gestures, no button
//  of the app's own), that the switches stay, that the button is on only while there is
//  something to reset and follows a row's change, that it reads "Undo" for a moment,
//  and that Edit › Undo and Redo outlive the page and show on the part open now, with the
//  list's marks following. (The ring of an app with suggested shortcuts is in
//  ShortcutRingSuggestionFillTests.) Nothing is shown on screen.
//

import XCTest
@testable import Scrollio_Debug

final class ApplicationPageResetTests: XCTestCase {

    private static let calculator = "/System/Applications/Calculator.app"

    private var savedApplications: EnhanceArray<Application>!
    private var savedBindings: [ButtonBinding] = []
    private var savedRing = ShortcutRingSettings.default
    private var savedGesture = MouseGestureSettings.default
    private var savedThumbWheel = ThumbWheelSettings.default
    private var uiDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        savedApplications = Options.shared.application.applications
        savedBindings = Options.shared.buttons.binding
        savedRing = Options.shared.ring
        savedGesture = Options.shared.gesture
        savedThumbWheel = Options.shared.thumbWheel
        Options.shared.application.applications = EnhanceArray<Application>(
            withArray: [], matchKey: "path", forObserver: { Options.shared.markChanged(.application) }
        )
        Options.shared.buttons.binding = []
        Options.shared.ring = .default
        Options.shared.gesture = .default
        ButtonUtils.shared.invalidateCache()
        uiDefaults = TestDefaults.make(for: self)
    }

    override func tearDown() {
        Options.shared.application.applications = savedApplications
        Options.shared.buttons.binding = savedBindings
        Options.shared.ring = savedRing
        Options.shared.gesture = savedGesture
        Options.shared.thumbWheel = savedThumbWheel
        ShortcutRingController.forgetPreparedFaces()
        ButtonUtils.shared.invalidateCache()
        savedApplications = nil
        uiDefaults = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// The Apps pane as the window makes it, with nothing shown on screen.
    private func makePane() -> PreferencesApplicationViewController {
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesSplitViewController.self))
        let pane = storyboard.instantiateController(withIdentifier: PANEL_IDENTIFIER.application) as! PreferencesApplicationViewController
        pane.uiStateDefaults = uiDefaults
        pane.runningApplications = { [] }
        pane.presentMenu = { _, _ in }
        pane.chooseApplications = { _, _ in XCTFail("no open panel was expected") }
        _ = pane.view
        return pane
    }

    private func addCalculator() -> Application {
        let application = Application(path: Self.calculator)
        Options.shared.application.applications.append(application)
        return application
    }

    private func binding(_ code: UInt16, _ action: String) -> ButtonBinding {
        return ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: code, modifiers: 0, deviceFilter: nil),
            systemShortcutName: action,
            isEnabled: true
        )
    }

    private func undoManager() -> UndoManager {
        let undo = UndoManager()
        undo.groupsByEvent = false
        return undo
    }

    /// Clicks the button as a click does, in an undo group of its own.
    private func click(_ button: NSButton, undo: UndoManager, file: StaticString = #filePath, line: UInt = #line) {
        undo.beginUndoGrouping()
        XCTAssertTrue(button.sendAction(button.action, to: button.target), file: file, line: line)
        undo.endUndoGrouping()
    }

    private func marks(in pane: PreferencesApplicationViewController) -> [ApplicationPagePart]? {
        return (pane.list.rows.first as? ApplicationListRow)?.marks
    }

    /// Calculator's page open on `part`, its Undo going to `undo`.
    private func open(
        _ part: ApplicationPagePart, in pane: PreferencesApplicationViewController, undo: UndoManager
    ) throws -> ApplicationDetailViewController {
        pane.openApplication(withID: Self.calculator, part: part)
        let page = try XCTUnwrap(pane.detailController)
        page.ringPart.paneUndoManager = undo
        page.gesturesPart.paneUndoManager = undo
        page.gesturesPart.showsLogiActions = { false }
        page.gesturesPart.isInteractiveAvailable = { false }
        page.buttonsPart.paneUndoManager = undo
        page.buttonsPart.deviceSource = ButtonsDeviceSource(
            captureStatus: { _ in .normal }, deviceName: { "MX Master 3S" }, isBusy: { false }, refresh: {}, warnBluetoothButton: { _ in }
        )
        page.buttonsPart.presentMenu = { _, _ in }
        page.buttonsPart.openActionMenu = { _ in }
        return page
    }

    // MARK: - Scrolling

    /// "Copy from Scrolling" makes the app's own settings a copy of the Scrolling pane's
    /// (its thumb wheel's speed and swap Scrolling › Thumb wheel's), greyed while they are
    /// one; the switch stays off, the Scrolling settings are untouched; "Undo" for a moment,
    /// and Edit › Undo under the app's name. The Scrolling pane keeps "Reset to Defaults".
    func testTheScrollingPartsButtonCopiesTheScrollingSettings() throws {
        let savedScroll = Options.shared.scroll
        addTeardownBlock { Options.shared.scroll = savedScroll }
        let general = OPTIONS_SCROLL_DEFAULT()
        general.speed = 2.5
        general.smoothSimTrackpad = true
        Options.shared.scroll = general
        Options.shared.thumbWheel = ThumbWheelSettings(function: .tabs, speed: 1.5, swapsDirection: true)
        let calculator = addCalculator()
        calculator.setUsesScrollingSettings(false, scrolling: general, thumbWheel: Options.shared.thumbWheel)
        let pane = makePane()
        let undo = undoManager()
        let page = try open(.scrolling, in: pane, undo: undo)
        let settings = try XCTUnwrap(page.scrollingController)
        settings.paneUndoManager = undo
        let button = try XCTUnwrap(settings.resetToDefaultsButton)
        XCTAssertEqual(button.title, "Copy from Scrolling")
        XCTAssertFalse(button.isEnabled, "a copy already: nothing to copy")

        calculator.scroll.speed = 4.5
        calculator.setOwnThumbWheelFunction(.volume)
        settings.syncViewWithOptions()
        XCTAssertTrue(button.isEnabled)
        click(button, undo: undo)
        XCTAssertEqual(calculator.scroll, general, "a copy of the Scrolling settings")
        XCTAssertFalse(calculator.scroll === general, "its own container")
        XCTAssertEqual(calculator.scroll.thumbWheel, ApplicationThumbWheelScrolling(Options.shared.thumbWheel))
        XCTAssertNil(calculator.ownThumbWheelFunction)
        XCTAssertFalse(calculator.inherit, "the switch stays")
        XCTAssertEqual(Options.shared.scroll.speed, 2.5, "the Scrolling settings are untouched")
        XCTAssertEqual(button.title, "Undo")
        XCTAssertEqual(undo.undoActionName, "Copy from Scrolling in Calculator")
        undo.undo()
        XCTAssertEqual(calculator.scroll.speed, 4.5)
        XCTAssertEqual(calculator.ownThumbWheelFunction, .volume)
        XCTAssertEqual(button.title, "Copy from Scrolling")

        // The Scrolling pane keeps its own button.
        let tab = PreferencesScrollingViewController()
        tab.uiStateDefaults = uiDefaults
        _ = tab.view
        XCTAssertEqual(tab.resetToDefaultsButton.title, "Reset to Defaults")
    }

    // MARK: - Shortcut Ring

    /// An app without suggested shortcuts: its own ring goes back to a copy of the general
    /// ring as it is now; the switch stays off, the general ring is untouched. The button
    /// is there with the own ring only, on only while the ring differs from where it
    /// starts, reads "Undo" for a moment and takes the copy back.
    func testTheRingsResetGoesBackToACopyOfTheGeneralRingAndKeepsTheSwitch() throws {
        let calculator = addCalculator()
        let pane = makePane()
        let undo = undoManager()
        let part = try XCTUnwrap(try open(.ring, in: pane, undo: undo).ringPart)
        XCTAssertNil(part.resetFooter.superview, "no own ring, no button")

        part.generalRingRow.toggle.state = .off
        part.generalRingClick(part.generalRingRow.toggle)
        XCTAssertTrue(part.resetToDefaultsButton.isDescendant(of: part.view))
        XCTAssertFalse(part.resetToDefaultsButton.isEnabled, "a copy of the general ring: nothing to reset")
        XCTAssertEqual(part.resetToDefaultsButton.title, "Copy from Shortcut Ring")
        XCTAssertFalse(part.view.hasAmbiguousLayout)

        var general = ShortcutRingSettings.default
        general[1] = ShortcutRingPlace(SystemShortcut.undo)
        Options.shared.ring = general
        calculator.ring?[0] = ShortcutRingPlace(SystemShortcut.copy)
        part.syncViewWithOptions()
        XCTAssertTrue(part.resetToDefaultsButton.isEnabled)
        let edited = try XCTUnwrap(calculator.ownRingPlaces)

        click(part.resetToDefaultsButton, undo: undo)
        XCTAssertEqual(calculator.ownRingPlaces, general.places, "the general ring as it is now")
        XCTAssertFalse(calculator.usesGeneralRing, "the switch stays")
        XCTAssertEqual(Options.shared.ring, general, "the general ring is untouched")
        XCTAssertEqual(part.resetToDefaultsButton.title, "Undo")
        XCTAssertTrue(part.resetToDefaultsButton.isEnabled)
        XCTAssertEqual(undo.undoActionName, "Copy from Shortcut Ring in Calculator", "its own name, not the pane's")

        // "Undo" is Edit › Undo (outside an undo group, as a real click).
        let button = part.resetToDefaultsButton
        XCTAssertTrue(button.sendAction(button.action, to: button.target))
        XCTAssertEqual(calculator.ownRingPlaces, edited)
        XCTAssertEqual(part.resetToDefaultsButton.title, "Copy from Shortcut Ring")
        undo.redo()
        XCTAssertEqual(calculator.ownRingPlaces, general.places)
        XCTAssertFalse(part.resetToDefaultsButton.isEnabled)

        // Back to the general ring: the button goes with the own ring.
        part.generalRingRow.toggle.state = .on
        part.generalRingClick(part.generalRingRow.toggle)
        XCTAssertNil(part.resetFooter.superview)
        XCTAssertFalse(part.hasSettingsToReset)
    }

    /// A row of the own ring changes a place: the button is on at once, without the page
    /// being shown again.
    func testTheRingsButtonFollowsARowsChange() throws {
        let calculator = addCalculator()
        calculator.setUsesGeneralRing(false, general: .default)
        let pane = makePane()
        let part = try XCTUnwrap(try open(.ring, in: pane, undo: undoManager()).ringPart)
        XCTAssertFalse(part.resetToDefaultsButton.isEnabled)
        try XCTUnwrap(part.ringController).setPlace(ShortcutRingPlace(SystemShortcut.find), at: 3)
        XCTAssertTrue(part.resetToDefaultsButton.isEnabled)
        try XCTUnwrap(part.ringController).setPlace(ShortcutRingSettings.default[3], at: 3)
        XCTAssertFalse(part.resetToDefaultsButton.isEnabled)
    }

    /// The reset, then the page closes: Undo and Redo still change the app's ring, and the
    /// page opened again shows each.
    func testUndoOfTheRingsResetWorksAfterThePageClosed() throws {
        let calculator = addCalculator()
        calculator.setUsesGeneralRing(false, general: .default)
        calculator.ring?[2] = ShortcutRingPlace(SystemShortcut.find)
        let edited = try XCTUnwrap(calculator.ownRingPlaces)
        let pane = makePane()
        let undo = undoManager()
        weak var closed: ApplicationRingPartViewController?
        try autoreleasepool {
            let part = try XCTUnwrap(try open(.ring, in: pane, undo: undo).ringPart)
            click(part.resetToDefaultsButton, undo: undo)
            closed = part
            pane.leaveSubpage()
        }
        XCTAssertNil(closed, "the page and its parts are gone")
        undo.undo()
        XCTAssertEqual(calculator.ownRingPlaces, edited)
        let part = try XCTUnwrap(try open(.ring, in: pane, undo: undo).ringPart)
        XCTAssertTrue(part.resetToDefaultsButton.isEnabled)
        undo.redo()
        XCTAssertEqual(calculator.ownRingPlaces, ShortcutRingSettings.default.places)
        XCTAssertFalse(part.resetToDefaultsButton.isEnabled, "the page open now shows the Redo")
        XCTAssertEqual(marks(in: pane), [.ring], "the app keeps its own ring")
    }

    /// The own ring's freeze switch goes back with it, to the general ring's as it is now;
    /// the switch alone turns the button on, and Undo brings it back.
    func testTheRingsResetTakesItsFreezeSwitchToTheGeneralRingsToo() throws {
        let calculator = addCalculator()
        calculator.setUsesGeneralRing(false, general: .default)
        let pane = makePane()
        let undo = undoManager()
        let part = try XCTUnwrap(try open(.ring, in: pane, undo: undo).ringPart)
        XCTAssertFalse(part.resetToDefaultsButton.isEnabled)
        let freeze = try XCTUnwrap(part.ringController?.freezeToggle as? NSSwitch)
        freeze.state = .on
        XCTAssertTrue(freeze.sendAction(freeze.action, to: freeze.target))
        XCTAssertEqual(calculator.ring?.freezePointer, true)
        XCTAssertFalse(Options.shared.ring.freezePointer)
        XCTAssertTrue(part.resetToDefaultsButton.isEnabled, "the switch alone turns it on")

        click(part.resetToDefaultsButton, undo: undo)
        XCTAssertEqual(calculator.ring?.freezePointer, false)
        XCTAssertEqual(calculator.ownRingPlaces, ShortcutRingSettings.default.places)
        XCTAssertEqual(freeze.state, .off, "the row shows it")
        XCTAssertFalse(calculator.usesGeneralRing)
        undo.undo()
        XCTAssertEqual(calculator.ring?.freezePointer, true)
        XCTAssertEqual(freeze.state, .on)
    }

    /// A click on a button that was not yet told that nothing differs any more (the
    /// general ring reset and undone in its pane behind the page's back) resets nothing,
    /// offers no "Undo" and registers no Undo; the button then says so (R3-1 F3).
    /// The same for the gestures.
    func testAClickThatResetsNothingOffersNoUndo() throws {
        let calculator = addCalculator()
        calculator.setUsesGeneralRing(false, general: .default)
        calculator.setUsesGeneralGestures(false, general: .default)
        let pane = makePane()
        let undo = undoManager()
        let ring = try XCTUnwrap(try open(.ring, in: pane, undo: undo).ringPart)
        var edited = ShortcutRingSettings.default
        edited[0] = ShortcutRingPlace(SystemShortcut.find)
        Options.shared.ring = edited
        ring.syncViewWithOptions()
        XCTAssertTrue(ring.resetToDefaultsButton.isEnabled, "the own ring differs from a copy of the general one")
        // The general ring comes back to where the own ring is, and nobody tells the part.
        Options.shared.ring = .default
        click(ring.resetToDefaultsButton, undo: undo)
        XCTAssertEqual(ring.resetToDefaultsButton.title, "Copy from Shortcut Ring")
        XCTAssertFalse(ring.resetToDefaultsButton.isEnabled)
        XCTAssertEqual(undo.undoActionName, "", "nothing was reset, nothing to undo")

        let gestures = try XCTUnwrap(try open(.gestures, in: pane, undo: undo).gesturesPart)
        var general = MouseGestureSettings.default
        general.freezePointer = false
        Options.shared.gesture = general
        gestures.syncViewWithOptions()
        XCTAssertTrue(gestures.resetToDefaultsButton.isEnabled)
        Options.shared.gesture = .default
        click(gestures.resetToDefaultsButton, undo: undo)
        XCTAssertEqual(gestures.resetToDefaultsButton.title, "Copy from Gestures")
        XCTAssertFalse(gestures.resetToDefaultsButton.isEnabled)
        XCTAssertEqual(undo.undoActionName, "")
        XCTAssertEqual(calculator.ownRingPlaces, ShortcutRingSettings.default.places)
    }

    // MARK: - Gestures

    /// The rest of the own set goes back with it: the mode, the speed, the freeze and a
    /// Logitech mouse's two switches, each a copy of the general one as it is now; one of
    /// them alone turns the button on, and Undo brings them back.
    func testTheGesturesResetTakesTheModeSpeedFreezeAndTheMousesSwitchesToo() throws {
        let calculator = addCalculator()
        calculator.setUsesGeneralGestures(false, general: .default)
        let pane = makePane()
        let undo = undoManager()
        let part = try XCTUnwrap(try open(.gestures, in: pane, undo: undo).gesturesPart)
        XCTAssertFalse(part.resetToDefaultsButton.isEnabled)
        let freeze = try XCTUnwrap(part.controls?.freezeToggle as? NSSwitch)
        freeze.state = .off
        XCTAssertTrue(freeze.sendAction(freeze.action, to: freeze.target))
        XCTAssertEqual(calculator.ownGestures?.freezePointer, false)
        XCTAssertTrue(part.resetToDefaultsButton.isEnabled, "one switch turns it on")
        calculator.changeOwnGestures { own in
            own.mode = .interactive
            own.trackingSpeed = 2
            own.deviceTracking = true
            own.hapticFeedback = false
        }
        part.syncViewWithOptions()
        let edited = try XCTUnwrap(calculator.ownGestures)
        var general = MouseGestureSettings.default
        general.trackingSpeed = 1.5
        Options.shared.gesture = general

        click(part.resetToDefaultsButton, undo: undo)
        XCTAssertEqual(calculator.ownGestures, ApplicationGestures(inherit: false, copying: general))
        XCTAssertEqual(Options.shared.gesture, general, "the general gestures are untouched")
        XCTAssertEqual(freeze.state, .on, "the row shows it")
        XCTAssertFalse(part.resetToDefaultsButton.title == "Copy from Gestures" && part.resetToDefaultsButton.isEnabled)
        undo.undo()
        XCTAssertEqual(calculator.ownGestures, edited)
        XCTAssertEqual(freeze.state, .off)
    }

    /// The own set goes back to a copy of the general gestures as they are now: the five
    /// actions with their names and icons, and the invert switch; the switch stays off,
    /// the general gestures are untouched. The button is there with the own set only, on
    /// only while the set differs, and follows a row's change at once.
    func testTheGesturesResetPutsACopyOfTheGeneralGesturesAndKeepsTheSwitch() throws {
        let calculator = addCalculator()
        let pane = makePane()
        let undo = undoManager()
        let part = try XCTUnwrap(try open(.gestures, in: pane, undo: undo).gesturesPart)
        XCTAssertNil(part.resetFooter.superview, "no own set, no button")

        var general = MouseGestureSettings.default
        general.actions.up = GestureAction(action: "custom::15:1179648", label: ShortcutLabel(name: "Reload", icon: .symbol("arrow.clockwise")))
        general.invertHorizontal = true
        Options.shared.gesture = general
        part.generalGesturesSwitch.state = .off
        XCTAssertTrue(part.generalGesturesSwitch.sendAction(part.generalGesturesSwitch.action, to: part.generalGesturesSwitch.target))
        XCTAssertTrue(part.resetToDefaultsButton.isDescendant(of: part.view))
        XCTAssertFalse(part.resetToDefaultsButton.isEnabled, "a copy of the general set: nothing to reset")
        XCTAssertFalse(part.view.hasAmbiguousLayout)

        // A row's change turns it on at once.
        let controls = try XCTUnwrap(part.controls)
        controls.store(GestureAction(SystemShortcut.paste), in: .left)
        XCTAssertTrue(part.resetToDefaultsButton.isEnabled)
        let invert = try XCTUnwrap(controls.invertToggle as? NSSwitch)
        invert.state = .off
        XCTAssertTrue(invert.sendAction(invert.action, to: invert.target))
        let edited = try XCTUnwrap(calculator.ownGestures)

        click(part.resetToDefaultsButton, undo: undo)
        XCTAssertEqual(calculator.ownGestures?.actions, general.actions, "the names and icons too")
        XCTAssertEqual(calculator.ownGestures?.invertHorizontal, true)
        XCTAssertFalse(calculator.usesGeneralGestures, "the switch stays")
        XCTAssertEqual(Options.shared.gesture, general, "the general gestures are untouched")
        XCTAssertNotEqual(part.controls?.actionPopUp(for: .left).menu?.items.first?.title, SystemShortcut.paste.localizedName)
        XCTAssertEqual((part.controls?.invertToggle as? NSSwitch)?.state, .on, "the rows show the reset")
        XCTAssertEqual(part.resetToDefaultsButton.title, "Undo")
        XCTAssertEqual(undo.undoActionName, "Copy from Gestures in Calculator", "its own name, not the pane's")

        undo.undo()
        XCTAssertEqual(calculator.ownGestures, edited)
        XCTAssertEqual(part.resetToDefaultsButton.title, "Copy from Gestures")
        XCTAssertTrue(part.resetToDefaultsButton.isEnabled)
        undo.redo()
        XCTAssertEqual(calculator.ownGestures?.actions, general.actions)

        part.generalGesturesSwitch.state = .on
        XCTAssertTrue(part.generalGesturesSwitch.sendAction(part.generalGesturesSwitch.action, to: part.generalGesturesSwitch.target))
        XCTAssertNil(part.resetFooter.superview, "the button goes with the own set")
        XCTAssertFalse(part.hasSettingsToReset)
    }

    /// The reset, the page closes, the switch goes back on (the set kept for later), then
    /// Edit › Undo: the kept set comes back as it was, and the page opened again shows it
    /// once the switch is off; Redo with the page open shows there.
    func testUndoOfTheGesturesResetOutlivesThePageAndReachesTheKeptSet() throws {
        let calculator = addCalculator()
        calculator.setUsesGeneralGestures(false, general: .default)
        var actions = GestureActions.default
        actions.up = GestureAction(SystemShortcut.copy)
        calculator.setOwnGestures(actions: actions, invertHorizontal: true)
        let edited = try XCTUnwrap(calculator.ownGestures)
        let pane = makePane()
        let undo = undoManager()
        try autoreleasepool {
            let part = try XCTUnwrap(try open(.gestures, in: pane, undo: undo).gesturesPart)
            click(part.resetToDefaultsButton, undo: undo)
            pane.leaveSubpage()
        }
        XCTAssertEqual(calculator.ownGestures?.actions, GestureActions.default)
        calculator.setUsesGeneralGestures(true, general: .default)

        undo.undo()
        XCTAssertEqual(calculator.gestures?.actions, edited.actions, "the set kept for later")
        XCTAssertTrue(calculator.usesGeneralGestures, "the switch is never touched")
        calculator.setUsesGeneralGestures(false, general: .default)
        let part = try XCTUnwrap(try open(.gestures, in: pane, undo: undo).gesturesPart)
        XCTAssertEqual(part.controls?.actionPopUp(for: .up).menu?.items.first?.title, SystemShortcut.copy.localizedName)
        XCTAssertTrue(part.resetToDefaultsButton.isEnabled)
        undo.redo()
        XCTAssertEqual(part.controls?.actionPopUp(for: .up).menu?.items.first?.title, SystemShortcut.missionControl.localizedName)
        XCTAssertFalse(part.resetToDefaultsButton.isEnabled)
    }

    // MARK: - Buttons

    /// Every button of the app's own and its own thumb wheel function go at once; Buttons
    /// is untouched; the list's mark goes. Undo brings them all back in their order, with
    /// the mark; Redo takes them again. The button is always there, on only while the app
    /// has something of its own.
    func testTheButtonsResetRemovesEveryOwnButtonAndTheThumbWheel() throws {
        Options.shared.buttons.binding = [binding(3, SystemShortcut.navigateBack.identifier)]
        let general = Options.shared.buttons.binding
        let calculator = addCalculator()
        let pane = makePane()
        let undo = undoManager()
        let part = try XCTUnwrap(try open(.buttons, in: pane, undo: undo).buttonsPart)
        XCTAssertTrue(part.resetToDefaultsButton.isDescendant(of: part.view))
        XCTAssertFalse(part.resetToDefaultsButton.isEnabled, "nothing of its own")

        calculator.setOwnButtonBindings([binding(3, "copy"), binding(4, "paste")])
        part.reloadRows()
        XCTAssertTrue(part.resetToDefaultsButton.isEnabled)
        part.addOwnThumbWheel()
        calculator.setOwnThumbWheelFunction(.zoom)
        let own = calculator.ownButtonBindings
        part.syncViewWithOptions()
        pane.reloadRows()
        XCTAssertEqual(marks(in: pane), [.buttons])

        click(part.resetToDefaultsButton, undo: undo)
        XCTAssertFalse(calculator.hasOwnButtons)
        XCTAssertNil(calculator.ownThumbWheelFunction)
        XCTAssertNil(calculator.buttons, "nothing is stored")
        XCTAssertTrue(part.rows.isEmpty)
        XCTAssertNil(part.thumbWheelRow)
        XCTAssertEqual(part.noteLabel.stringValue, "Click + to give a button something else to do while Calculator is in front.")
        XCTAssertEqual(Options.shared.buttons.binding, general, "Buttons is untouched")
        XCTAssertEqual(marks(in: pane), [], "the list's mark goes")
        XCTAssertEqual(part.resetToDefaultsButton.title, "Undo")
        XCTAssertEqual(undo.undoActionName, "Remove All Buttons in Calculator", "its own name, with the app's (F30)")

        undo.undo()
        XCTAssertEqual(calculator.ownButtonBindings, own, "every button, in its order")
        XCTAssertEqual(calculator.ownThumbWheelFunction, .zoom)
        XCTAssertEqual(part.rows.map(\.binding.systemShortcutName), ["copy", "paste"])
        XCTAssertNotNil(part.thumbWheelRow)
        XCTAssertEqual(marks(in: pane), [.buttons])
        XCTAssertEqual(part.resetToDefaultsButton.title, "Remove All Buttons")
        XCTAssertTrue(part.resetToDefaultsButton.isEnabled)

        undo.redo()
        XCTAssertFalse(calculator.hasOwnButtonsPart)
        XCTAssertTrue(part.rows.isEmpty)
        XCTAssertFalse(part.resetToDefaultsButton.isEnabled)
    }

    /// The reset, the page closes, a button is given to the app again meanwhile, then
    /// Edit › Undo: the others come back around it (the one added meanwhile stays), the
    /// list's mark follows, and the page opened again shows them; Redo there takes them all.
    func testUndoOfTheButtonsResetOutlivesThePageAndKeepsWhatWasAddedMeanwhile() throws {
        let calculator = addCalculator()
        calculator.setOwnButtonBindings([binding(3, "copy"), binding(4, "paste")])
        let pane = makePane()
        let undo = undoManager()
        weak var closed: ApplicationButtonsViewController?
        try autoreleasepool {
            let part = try XCTUnwrap(try open(.buttons, in: pane, undo: undo).buttonsPart)
            click(part.resetToDefaultsButton, undo: undo)
            closed = part
            pane.leaveSubpage()
        }
        XCTAssertNil(closed, "the page and its parts are gone")
        XCTAssertEqual(marks(in: pane), [])
        calculator.setOwnButtonBindings([binding(4, "find")])

        undo.undo()
        XCTAssertEqual(calculator.ownButtonBindings.map(\.systemShortcutName), ["copy", "find"])
        XCTAssertEqual(marks(in: pane), [.buttons], "the list's mark follows")
        let part = try XCTUnwrap(try open(.buttons, in: pane, undo: undo).buttonsPart)
        XCTAssertEqual(part.rows.map(\.binding.systemShortcutName), ["copy", "find"])
        undo.redo()
        XCTAssertTrue(part.rows.isEmpty, "the page open now shows the Redo")
        XCTAssertFalse(calculator.hasOwnButtons)
        XCTAssertEqual(marks(in: pane), [])
    }

    /// The Buttons part's reset changes what opens the ring with the app in front: an Undo
    /// while the Shortcut Ring part shows says so there.
    func testUndoOfTheButtonsResetShowsOnTheRingPartShownNow() throws {
        Options.shared.buttons.binding = [binding(5, SystemShortcut.shortcutRing.identifier)]
        let calculator = addCalculator()
        calculator.setOwnButtonBindings([binding(5, "copy")])
        let pane = makePane()
        let undo = undoManager()
        let page = try open(.buttons, in: pane, undo: undo)
        click(page.buttonsPart.resetToDefaultsButton, undo: undo)
        page.show(.ring)
        let five = ButtonTriggerNaming.title(for: RecordedEvent(type: .mouse, code: 5, modifiers: 0, deviceFilter: nil))
        XCTAssertEqual(page.ringPart.triggerRow.explanation, "\(five), as everywhere")
        undo.undo()
        XCTAssertEqual(page.ringPart.triggerRow.explanation, "None in Calculator")
        undo.redo()
        XCTAssertEqual(page.ringPart.triggerRow.explanation, "\(five), as everywhere")
    }
}
