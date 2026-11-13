//
//  PreferencesButtonsTests.swift
//  MosTests
//
//  The Buttons pane: what its rows and its card are called, which part of the mouse a
//  button lights (on the card and in each row's picture), the rows of the connected MX
//  Master's buttons ("Default" until one gets an action) above the other bindings, how a
//  button the drawing cannot show is found ("That's …"), the notes under the rows,
//  recording a button (stubbed: no event is
//  recorded or posted), removing with Undo (also from another pane), the keyboard focus,
//  what closes with the pane, the action menu, "Checking buttons…", and that stored
//  bindings load and save unchanged. Nothing is shown on screen and no HID device is
//  touched.
//

import XCTest
@testable import Scrollio_Debug

final class PreferencesButtonsTests: XCTestCase {

    private var savedBindings: [ButtonBinding] = []
    private var savedThumbWheel = ThumbWheelSettings.default
    private var anchors: [NSView] = []
    private var openedMenus: [NSPopUpButton] = []
    private var shownPanes: [String] = []
    private var captureStatus: [UInt16: ButtonCapturePresentationStatus] = [:]
    private var busy = false
    private var deviceName: String? = "MX Master 4"
    private var scrollKeys: [ScrollHotkey] = []
    private var warnedCodes: [UInt16] = []
    private var recorderStops = 0
    private var shownOpenTargets: [NSView] = []
    private var placeMenus: [(menu: NSMenu, anchor: NSView)] = []

    override func setUp() {
        super.setUp()
        savedBindings = Options.shared.buttons.binding
        savedThumbWheel = Options.shared.thumbWheel
        Options.shared.buttons.binding = []
        Options.shared.thumbWheel = .default
        anchors = []
        openedMenus = []
        shownPanes = []
        captureStatus = [:]
        busy = false
        deviceName = "MX Master 4"
        scrollKeys = []
        warnedCodes = []
        recorderStops = 0
        shownOpenTargets = []
        placeMenus = []
    }

    override func tearDown() {
        Options.shared.buttons.binding = savedBindings
        Options.shared.thumbWheel = savedThumbWheel
        super.tearDown()
    }

    // MARK: - Helpers

    private func makePane(_ bindings: [ButtonBinding] = []) -> PreferencesButtonsViewController {
        Options.shared.buttons.binding = bindings
        let pane = PreferencesButtonsViewController()
        pane.deviceSource = ButtonsDeviceSource(
            captureStatus: { [unowned self] in self.captureStatus[$0] ?? .normal },
            deviceName: { [unowned self] in self.deviceName },
            isBusy: { [unowned self] in self.busy },
            refresh: {},
            warnBluetoothButton: { [unowned self] in self.warnedCodes.append($0) }
        )
        pane.scrollHoldKeys = { [unowned self] in self.scrollKeys }
        pane.startRecording = { [unowned self] anchor in self.anchors.append(anchor) }
        pane.stopRecording = { [unowned self, unowned pane] in
            self.recorderStops += 1
            // As the recorder does: it reports at once that it stopped.
            pane.onRecordingStopped(KeyRecorder(), didRecord: false)
        }
        pane.presentOpenTarget = { [unowned self] _, anchor, _ in self.shownOpenTargets.append(anchor) }
        pane.openActionMenu = { [unowned self] popUp in self.openedMenus.append(popUp) }
        pane.presentPlaceMenu = { [unowned self] menu, anchor in self.placeMenus.append((menu, anchor)) }
        pane.showPane = { [unowned self] identifier in self.shownPanes.append(identifier) }
        pane.paneUndoManager = UndoManager()
        _ = pane.view
        return pane
    }

    private func binding(
        _ code: UInt16,
        _ action: String = "",
        modifiers: UInt = 0,
        type: EventType = .mouse
    ) -> ButtonBinding {
        return ButtonBinding(
            triggerEvent: RecordedEvent(type: type, code: code, modifiers: modifiers, deviceFilter: nil),
            systemShortcutName: action,
            isEnabled: !action.isEmpty
        )
    }

    private func mouseEvent(_ code: UInt16, modifiers: CGEventFlags = []) -> InputEvent {
        return InputEvent(type: .mouse, code: code, modifiers: modifiers, phase: .down, source: .hidPP, device: nil)
    }

    private func flush(_ seconds: TimeInterval = 0.02) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// The pane in a window of its own, inside a container (so it can be taken out, as the
    /// window does when another pane shows). The window's undo manager takes Undo. Never shown.
    private func makeWindow(for pane: PreferencesButtonsViewController) -> (NSWindow, NSView) {
        pane.paneUndoManager = nil
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: PreferencesWindowLayout.contentWidth, height: 600),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: true
        )
        window.isReleasedWhenClosed = false
        let container = NSView(frame: NSRect(x: 0, y: 0, width: PreferencesWindowLayout.contentWidth, height: 600))
        window.contentView = container
        // The pane fills the container, as it fills the window in the app: at the height it
        // comes with (270) two rows do not fit under the header, and each layout pass
        // printed "Unable to simultaneously satisfy constraints".
        pane.view.frame = container.bounds
        pane.view.autoresizingMask = [.width, .height]
        container.addSubview(pane.view)
        pane.view.layoutSubtreeIfNeeded()
        addTeardownBlock { window.close() }
        return (window, container)
    }

    private func key(_ characters: String, keyCode: UInt16) throws -> NSEvent {
        return try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
        ))
    }

    private func titles(_ codes: [UInt16], modifiers: [UInt16: UInt] = [:]) -> [String] {
        let events = codes.map { RecordedEvent(type: .mouse, code: $0, modifiers: modifiers[$0] ?? 0, deviceFilter: nil) }
        return ButtonTriggerNaming.titles(for: events)
    }

    private func text(_ key: String) -> String {
        return NSLocalizedString(key, comment: "")
    }

    /// The rows that show `bindings`, in their order, wherever the pane put them.
    private func rows(of bindings: [ButtonBinding], in pane: PreferencesButtonsViewController) throws -> [ButtonBindingRow] {
        return try bindings.map { try XCTUnwrap(pane.row(for: $0.id), "no row for \($0.triggerEvent)") }
    }

    /// The rows of the MX Master 4's buttons when none has a binding, top to bottom.
    private let mxMaster4Titles = ["Middle button", "Mode shift button", "Gesture button", "Forward button", "Back button", "Thumb panel"]

    private let option = UInt(CGEventFlags.maskAlternate.rawValue)
    private let command = UInt(CGEventFlags.maskCommand.rawValue)
    private let control = UInt(CGEventFlags.maskControl.rawValue)

    // MARK: - The pane

    func testTheStoryboardMakesTheButtonsPane() {
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesSplitViewController.self))
        let pane = storyboard.instantiateController(withIdentifier: PANEL_IDENTIFIER.buttons) as? PreferencesButtonsViewController
        XCTAssertNotNil(pane)
        XCTAssertEqual(pane?.title, "Buttons")
        // Built in code: the scene is a shell.
        XCTAssertNotNil(pane?.view)
        XCTAssertNotNil(pane?.headerView)
        XCTAssertNotNil(pane?.list)
    }

    func testThePaneIsTheCardThenTheList() {
        let pane = makePane([binding(3, "copy")])
        pane.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(pane.view.frame.width, 520)
        XCTAssertEqual(pane.view.frame.size, pane.view.fittingSize)
        let header = pane.view.convert(pane.headerView.bounds, from: pane.headerView)
        let list = pane.view.convert(pane.list.bounds, from: pane.list)
        XCTAssertEqual(header.minX, 20, accuracy: 0.5)
        XCTAssertEqual(header.width, 480, accuracy: 0.5)
        XCTAssertEqual(header.height, MouseHeaderView.preferredHeight, accuracy: 0.5)
        XCTAssertEqual(list.width, 480, accuracy: 0.5)
        XCTAssertGreaterThan(header.minY, list.maxY, "the card is above the list (not flipped)")
        XCTAssertEqual(header.minY - list.maxY, PreferencesGroupedForm.boxSpacing, accuracy: 0.5)
        XCTAssertEqual(pane.list.identifier, PreferencesButtonsViewController.Identifier.list)
        XCTAssertEqual(pane.list.rowsView.accessibilityLabel(), "Buttons")
    }

    func testTheCardHasTheMetricsOfTheMousePanesCard() {
        XCTAssertEqual(ButtonsHeaderView.preferredHeight, 150)
        XCTAssertEqual(ButtonsHeaderView.cornerRadius, 10)
        XCTAssertEqual(ButtonsHeaderView.artworkColumnWidth, 170)
        XCTAssertEqual(ButtonsMouseArtworkView.size, MouseArtworkView.size)
        let header = ButtonsHeaderView()
        XCTAssertEqual(header.titleLabel.font, MouseHeaderView.nameFont)
        XCTAssertEqual(header.subtitleLabel.font, MouseHeaderView.detailFont)
        XCTAssertEqual(Set(header.artwork.highlights.keys), Set(ButtonsMousePart.allCases))
    }

    /// Without a Logitech mouse the list holds only what was added, as it always did.
    func testTheEmptyList() {
        deviceName = nil
        let pane = makePane()
        XCTAssertTrue(pane.rows.isEmpty)
        XCTAssertEqual(pane.list.emptyRow.title, "No buttons yet")
        XCTAssertEqual(pane.list.emptyRow.explanation, "Click + and press a mouse button to give it an action.")
        XCTAssertTrue(pane.list.emptyRow.superview === pane.list.rowsView)
        XCTAssertFalse(pane.list.removeButton.isEnabled)
        XCTAssertEqual(pane.headerView.content.title, "Your mouse")
        XCTAssertEqual(pane.headerView.content.subtitle, "No buttons set up yet")
        // No "Not sure which is which?" between "No buttons set up yet" and "No buttons yet":
        // there is nothing to tell apart, and the empty list says what to do.
        XCTAssertNil(pane.headerView.content.hint)
        XCTAssertTrue(pane.headerView.hintLabel.isHidden)
        XCTAssertEqual(pane.headerView.accessibilityLabel(), "Your mouse, No buttons set up yet")

        // With a row in the list the hint is back.
        pane.addBinding(for: RecordedEvent(type: .mouse, code: 3, modifiers: 0, deviceFilter: nil), action: nil)
        pane.list.select(nil)
        XCTAssertEqual(pane.rows.count, 1)
        XCTAssertEqual(pane.headerView.content.hint, "Not sure which is which? Click + and press a button.")
        XCTAssertFalse(pane.headerView.hintLabel.isHidden)
    }

    // MARK: - The connected mouse's buttons

    /// An item of an action menu (or one of its submenus) by the action's identifier.
    private func item(_ identifier: String, in menu: NSMenu?) -> NSMenuItem? {
        for item in menu?.items ?? [] {
            if (item.representedObject as? SystemShortcut.Shortcut)?.identifier == identifier {
                return item
            }
            if let found = self.item(identifier, in: item.submenu) {
                return found
            }
        }
        return nil
    }

    /// An MX Master 4 with nothing set up: a row for each of its buttons, in the order they
    /// sit on it, each "Default" with what it then does where that is certain. Left and
    /// right clicks are not listed, nothing is stored, the list has no title inside, and
    /// "−" and Delete never remove one.
    func testAnMXMaster4ListsEveryButtonInTheOrderTheySit() throws {
        let pane = makePane()
        let (window, _) = makeWindow(for: pane)
        XCTAssertEqual(ButtonsMousePart.listed(on: .mxMaster4), [.middle, .modeShift, .gesture, .forward, .back, .thumbPanel])
        XCTAssertEqual(pane.rows.map(\.title), mxMaster4Titles)
        XCTAssertEqual(pane.rows.map(\.id), ButtonsMousePart.listed(on: .mxMaster4).map { AnyHashable($0) })
        XCTAssertEqual(pane.rows.map { shown($0.pullDown) }, Array(repeating: "Default", count: 6))
        XCTAssertEqual(pane.rows.map(\.explanation), [
            "Middle click.",
            "Switches the wheel between clicking and spinning freely.",
            "Does what the mouse does on its own.",
            "Goes forward in apps that support it.",
            "Goes back in apps that support it.",
            "Does what the mouse does on its own.",
        ])
        XCTAssertEqual(pane.rows.map { $0.note?.tone }, Array(repeating: ButtonRowNote.Tone.plain as ButtonRowNote.Tone?, count: 6))
        XCTAssertTrue(pane.rows.allSatisfy { $0.isDefault && !$0.isStored && !$0.isRemovable && $0.infoButton.isHidden && $0.placeButton.isHidden })
        XCTAssertEqual(pane.rows.map(\.picture), ButtonsMousePart.listed(on: .mxMaster4).map { ButtonTriggerPicture.mouse(part: $0, number: nil) })
        XCTAssertEqual(pane.rows[4].accessibilityLabel(), "Back button, Goes back in apps that support it.")
        XCTAssertTrue(pane.list.groupTitles.isEmpty)
        XCTAssertNil(pane.list.emptyRow.superview, "never empty")

        // "Default" where other rows offer "No Action".
        let back = pane.rows[4].pullDown
        XCTAssertEqual(back.noActionItem?.title, "Default")
        XCTAssertNil(back.menu?.items.first { $0.title == "No Action" })
        XCTAssertEqual(ButtonActionPullDown(binding: binding(5)).noActionItem?.title, "No Action")

        // The card: no button has an action; a row lights its button and says "Default".
        XCTAssertEqual(pane.headerView.content.subtitle, "No buttons set up yet")
        pane.list.select(ButtonsMousePart.thumbPanel)
        XCTAssertEqual(pane.headerView.content, ButtonsHeaderContent(title: "Thumb panel", subtitle: "Default", part: .thumbPanel))
        XCTAssertEqual(pane.headerView.artwork.emphasis, .thumbPanel)

        // "−" is off on it, and Delete does nothing.
        XCTAssertFalse(pane.list.removeButton.isEnabled)
        window.makeFirstResponder(pane.list)
        pane.list.keyDown(with: try key("\u{7F}", keyCode: 51))
        XCTAssertEqual(pane.list.selectedID, AnyHashable(ButtonsMousePart.thumbPanel))
        XCTAssertEqual(pane.rows.count, 6)
        XCTAssertTrue(Options.shared.buttons.binding.isEmpty, "showing, selecting and Delete store nothing")
    }

    /// An MX Master 3S has no thumb panel and its gesture button in the thumb rest; with no
    /// Logitech mouse the list is what was added, as before. The list follows the mouse,
    /// and nothing is stored for it.
    func testEachMouseListsItsOwnButtonsAndAPlainMouseNone() throws {
        let added = [binding(3, "copy", modifiers: option), binding(40, "copy", modifiers: control, type: .keyboard)]
        deviceName = "MX Master 3S"
        let pane = makePane(added)
        XCTAssertEqual(ButtonsMousePart.listed(on: .mxMaster3), [.middle, .modeShift, .forward, .back, .gesture])
        XCTAssertEqual(pane.rows.map(\.title), ["Middle button", "Mode shift button", "Forward button", "Back button", "Gesture button",
                                                "⌥ Back button", "⌃ K"])
        XCTAssertEqual(pane.rows[4].picture, .mouse(part: .gesture, number: nil))
        XCTAssertEqual(pane.rows[4].explanation, "Does what the mouse does on its own.")
        XCTAssertEqual(pane.list.groupTitles[AnyHashable(added[0].id)]?.title, "Other buttons and keys")
        XCTAssertEqual(pane.list.groupTitles.count, 1)

        deviceName = nil
        NotificationCenter.default.post(name: LogiCenter.mouseStateChanged, object: nil)
        XCTAssertEqual(pane.rows.map(\.title), ["⌥ Back button", "⌃ K"])
        XCTAssertEqual(pane.rows.map(\.id), added.map { AnyHashable($0.id) })
        XCTAssertTrue(pane.rows.allSatisfy(\.isRemovable))
        XCTAssertTrue(pane.list.groupTitles.isEmpty)
        XCTAssertEqual(ButtonsMousePart.listed(on: .generic), [])

        deviceName = "MX Master 4"
        NotificationCenter.default.post(name: LogiCenter.mouseStateChanged, object: nil)
        XCTAssertEqual(pane.rows.map(\.title), mxMaster4Titles + ["⌥ Back button", "⌃ K"])
        XCTAssertEqual(Options.shared.buttons.binding, added)
    }

    // MARK: - The thumb wheel

    /// The list's titles, every row (the thumb wheel's too), top to bottom.
    private func listTitles(_ pane: PreferencesButtonsViewController) -> [String] {
        return pane.list.rows.map(\.title)
    }

    /// The layout: on an MX Master 4, 3 or 3S the thumb wheel has a row of its own kind right
    /// after the mode shift button; any other mouse has none. The buttons' rows and the
    /// other bindings are the same with it as without it.
    func testTheThumbWheelHasARowOfItsOwnAfterTheModeShiftButton() throws {
        let bindings = [binding(1001, "copy"), binding(3, "paste", modifiers: option), binding(40, "copy", modifiers: control, type: .keyboard)]
        let roles: (UInt16) -> LogiControlRole? = { $0 == 1001 ? .modeShift : nil }
        for name in ["MX Master 4", "MX Master 3", "MX Master 3S", "MX Master 3S for Mac"] {
            let mouse = MouseArtworkModel.model(forDeviceName: name)
            let layout = ButtonsListLayout.make(bindings: bindings, mouse: mouse, logitechRole: roles)
            XCTAssertTrue(layout.hasThumbWheel, name)
            XCTAssertTrue(ButtonsListLayout.showsThumbWheel(on: mouse), name)
            let rows = layout.rows
            XCTAssertEqual(rows.filter { $0 == .thumbWheel }.count, 1, name)
            let index = try XCTUnwrap(rows.firstIndex(of: .thumbWheel))
            XCTAssertEqual(rows[index - 1], .part(ButtonsListLayout.PartRow(part: .modeShift, binding: bindings[0])), "\(name): after the mode shift button")
            XCTAssertEqual(rows.count, layout.partRows.count + 1 + layout.others.count)
            XCTAssertEqual(rows.compactMap { if case .part(let row) = $0 { return row } else { return nil } }, layout.partRows)
            XCTAssertEqual(rows.compactMap { if case .other(let binding) = $0 { return binding } else { return nil } }, layout.others)
            XCTAssertEqual(layout.others, [bindings[1], bindings[2]], "\(name): the bindings sit where they did")
        }
        let master4 = ButtonsListLayout.make(bindings: [], mouse: .mxMaster4)
        XCTAssertEqual(master4.rows, [
            .part(.init(part: .middle, binding: nil)), .part(.init(part: .modeShift, binding: nil)), .thumbWheel,
            .part(.init(part: .gesture, binding: nil)), .part(.init(part: .forward, binding: nil)),
            .part(.init(part: .back, binding: nil)), .part(.init(part: .thumbPanel, binding: nil)),
        ])
        let master3 = ButtonsListLayout.make(bindings: [], mouse: .mxMaster3)
        XCTAssertEqual(master3.rows.firstIndex(of: .thumbWheel), 2)

        for name in [nil, "MX Anywhere 3S", "M720 Triathlon", "Lift"] as [String?] {
            let mouse = MouseArtworkModel.model(forDeviceName: name)
            let layout = ButtonsListLayout.make(bindings: bindings, mouse: mouse, logitechRole: roles)
            XCTAssertFalse(layout.hasThumbWheel, name ?? "no mouse")
            XCTAssertFalse(layout.rows.contains(.thumbWheel), name ?? "no mouse")
            XCTAssertEqual(layout.rows, bindings.map(ButtonsListLayout.Row.other), "the bindings as stored")
        }
        // The thumb wheel's row has an id no button or binding has.
        XCTAssertFalse(ButtonsMousePart.allCases.map { AnyHashable($0) }.contains(ButtonsListLayout.thumbWheelRowID))
        XCTAssertEqual(ButtonsListLayout(partRows: [], others: []).hasThumbWheel, false)
    }

    /// An MX Master 4 at the defaults: the row reads "Default", says it scrolls sideways,
    /// lights the thumb wheel in its picture, and offers the six functions; it is no button
    /// row (no recorder, no ⓘ, never removed) and the buttons' rows are as they were.
    func testTheThumbWheelRowReadsDefaultWhileItScrolls() throws {
        let pane = makePane()
        let row = try XCTUnwrap(pane.thumbWheelRow)
        XCTAssertEqual(listTitles(pane), ["Middle button", "Mode shift button", "Thumb wheel", "Gesture button",
                                          "Forward button", "Back button", "Thumb panel"])
        XCTAssertEqual(pane.rows.map(\.title), mxMaster4Titles, "the button rows are the same")
        XCTAssertTrue(pane.list.rows[2] === row)
        XCTAssertEqual(row.id, ButtonsListLayout.thumbWheelRowID)
        XCTAssertEqual(shown(row.pullDown), "Default")
        XCTAssertNil(row.pullDown.menu?.items.first?.image, "no symbol for Default, as on the other rows")
        XCTAssertEqual(row.explanation, "Scrolls sideways.")
        XCTAssertEqual(row.accessibilityLabel(), "Thumb wheel, Scrolls sideways.")
        XCTAssertEqual(row.pullDown.accessibilityLabel(), "Thumb wheel")
        XCTAssertEqual(row.pullDown.accessibilityHelp(), "Scrolls sideways.")
        XCTAssertEqual(row.pullDown.identifier, ButtonsThumbWheelRow.identifier)
        XCTAssertFalse(row.isRemovable)
        XCTAssertNotNil(row.iconView?.image)
        // The pull-down stands where the buttons' pull-downs stand, in the list's own
        // coordinates.
        _ = makeWindow(for: pane)
        pane.view.layoutSubtreeIfNeeded()
        let thumbWheelPullDown = pane.list.convert(row.pullDown.bounds, from: row.pullDown)
        for buttonRow in pane.rows {
            let other = pane.list.convert(buttonRow.pullDown.bounds, from: buttonRow.pullDown)
            XCTAssertEqual(thumbWheelPullDown.minX, other.minX, accuracy: 0.5, buttonRow.title)
            XCTAssertEqual(thumbWheelPullDown.maxX, other.maxX, accuracy: 0.5, buttonRow.title)
        }
        XCTAssertGreaterThan(thumbWheelPullDown.width, 200)
        XCTAssertFalse(row.subviews.contains { $0 is ButtonPlacePictureButton }, "no picture menu")

        let items = row.pullDown.functionItems
        XCTAssertEqual(items.map(\.title), ["Default", "Zoom", "Switch Tabs", "Switch Desktops", "Back and Forward", "Volume"])
        XCTAssertEqual(items.compactMap(ThumbWheelPresentation.function(of:)), ThumbWheelFunction.allCases)
        XCTAssertNil(items[0].image)
        XCTAssertTrue(items.dropFirst().allSatisfy { $0.image?.isTemplate == true }, "the others with their symbols")
        if #available(macOS 27.0, *) {
            XCTAssertTrue(items.dropFirst().allSatisfy { $0.preferredImageVisibility == .visible })
        }
        XCTAssertEqual(items.map(\.state), [.on, .off, .off, .off, .off, .off])
        XCTAssertEqual(items.map(\.toolTip), ThumbWheelFunction.allCases.map(\.localizedHint))
        XCTAssertTrue(row.pullDown.menu?.items[2].isSeparatorItem ?? false, "Default stands apart")

        // Pointed at or selected, the card lights the thumb wheel and says "Default".
        pane.list.select(ButtonsListLayout.thumbWheelRowID)
        XCTAssertEqual(pane.headerView.content, ButtonsHeaderContent(title: "Thumb wheel", subtitle: "Default", part: nil, lightsThumbWheel: true))
        XCTAssertTrue(pane.headerView.artwork.emphasizesThumbWheel)
        XCTAssertNil(pane.headerView.artwork.emphasis)
        XCTAssertFalse(pane.list.removeButton.isEnabled, "the thumb wheel is never removed")
        pane.list.select(ButtonsMousePart.back)
        XCTAssertEqual(pane.headerView.artwork.emphasis, .back)
        XCTAssertFalse(pane.headerView.artwork.emphasizesThumbWheel)
        XCTAssertEqual(pane.headerView.content.subtitle, "Default")
        pane.list.select(nil)
        XCTAssertEqual(pane.headerView.content.subtitle, "No buttons set up yet", "the thumb wheel is no button with an action")
        XCTAssertTrue(Options.shared.buttons.binding.isEmpty, "showing it stores nothing")
    }

    /// Choosing a function stores it in the thumb wheel settings, once, and nothing else:
    /// no binding is made, changed or removed, and the bindings are not saved again.
    func testChoosingAThumbWheelFunctionStoresItAndNoBinding() throws {
        let bindings = [binding(1001, SystemShortcut.screenshotSelection.identifier), binding(5, "copy", modifiers: option), binding(7)]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let before = try encoder.encode(bindings)
        let pane = makePane(bindings)
        let row = try XCTUnwrap(pane.thumbWheelRow)
        var flushed: [Set<OptionsGroup>] = []
        Options.shared.flushPendingSaves()
        Options.shared.onFlushForTests = { flushed.append($0) }
        defer { Options.shared.onFlushForTests = nil }
        var changes = 0
        let observer = ThumbWheelSettingsChange.addObserver { changes += 1 }
        defer { ThumbWheelSettingsChange.removeObserver(observer) }
        Options.shared.thumbWheel = ThumbWheelSettings(function: .scroll, speed: 1.5, swapsDirection: true)
        changes = 0

        let tabs = try XCTUnwrap(row.pullDown.functionItems.first { ThumbWheelPresentation.function(of: $0) == .tabs })
        row.pullDown.functionChosen(tabs)
        XCTAssertEqual(Options.shared.thumbWheel, ThumbWheelSettings(function: .tabs, speed: 1.5, swapsDirection: true))
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(shown(row.pullDown), "Switch Tabs")
        XCTAssertNotNil(row.pullDown.menu?.items.first?.image, "with its symbol")
        XCTAssertEqual(row.explanation, "Switches between tabs.")
        XCTAssertEqual(row.pullDown.functionItems.map(\.state), [.off, .off, .on, .off, .off, .off])
        row.pullDown.functionChosen(tabs)
        XCTAssertEqual(changes, 1, "the function it has is not written again")

        pane.list.select(ButtonsListLayout.thumbWheelRowID)
        XCTAssertEqual(pane.headerView.content, ButtonsHeaderContent(title: "Thumb wheel", subtitle: "Switch Tabs", part: nil, lightsThumbWheel: true))

        let defaultItem = try XCTUnwrap(row.pullDown.functionItems.first)
        row.pullDown.functionChosen(defaultItem)
        XCTAssertEqual(Options.shared.thumbWheel.function, .scroll)
        XCTAssertEqual(shown(row.pullDown), "Default")
        XCTAssertEqual(pane.headerView.content.subtitle, "Default")

        // The bindings: the same values, the same bytes, never saved.
        XCTAssertEqual(try encoder.encode(Options.shared.buttons.binding), before)
        XCTAssertEqual(pane.buttonBindings, bindings)
        Options.shared.flushPendingSaves()
        XCTAssertEqual(flushed, [[.thumbWheel]], "only the thumb wheel is saved")
        XCTAssertEqual(pane.rows.map(\.binding.id).filter { id in bindings.contains { $0.id == id } }.count, 3)
        XCTAssertNil(pane.row(for: ButtonsListLayout.thumbWheelRowID), "it is no binding's row")
        XCTAssertNil(pane.storedBinding(ofRow: ButtonsListLayout.thumbWheelRowID))
    }

    /// The row follows the mouse: an MX Master 3S has it, a mouse without a thumb wheel
    /// (or none) does not, and it comes back with the MX Master; the bindings stay.
    func testTheThumbWheelRowFollowsTheMouse() throws {
        let added = [binding(3, "copy", modifiers: option)]
        deviceName = "MX Master 3S"
        Options.shared.thumbWheel.function = .volume
        let pane = makePane(added)
        let row = try XCTUnwrap(pane.thumbWheelRow)
        XCTAssertEqual(listTitles(pane), ["Middle button", "Mode shift button", "Thumb wheel", "Forward button", "Back button",
                                          "Gesture button", "⌥ Back button"])
        XCTAssertEqual(row.mouse, .mxMaster3)
        XCTAssertEqual(shown(row.pullDown), "Volume")

        deviceName = nil
        NotificationCenter.default.post(name: LogiCenter.mouseStateChanged, object: nil)
        XCTAssertNil(pane.thumbWheelRow)
        XCTAssertEqual(listTitles(pane), ["⌥ Back button"])

        deviceName = "MX Master 4"
        NotificationCenter.default.post(name: LogiCenter.mouseStateChanged, object: nil)
        XCTAssertEqual(pane.thumbWheelRow?.mouse, .mxMaster4)
        XCTAssertEqual(listTitles(pane), ["Middle button", "Mode shift button", "Thumb wheel", "Gesture button", "Forward button",
                                          "Back button", "Thumb panel", "⌥ Back button"])
        XCTAssertEqual(pane.list.groupTitles[AnyHashable(added[0].id)]?.title, "Other buttons and keys")
        XCTAssertEqual(Options.shared.buttons.binding, added)
        XCTAssertEqual(Options.shared.thumbWheel.function, .volume, "nothing is written for showing it")
    }

    /// The keyboard reaches it like any row: ↑ and ↓ select it, Return opens its menu,
    /// Delete does nothing.
    func testTheThumbWheelRowIsReachedByKeyboard() throws {
        let pane = makePane()
        let (window, _) = makeWindow(for: pane)
        let row = try XCTUnwrap(pane.thumbWheelRow)
        window.makeFirstResponder(pane.list)
        pane.list.select(ButtonsMousePart.modeShift)
        pane.list.keyDown(with: try key(String(Character(try XCTUnwrap(UnicodeScalar(NSDownArrowFunctionKey)))), keyCode: 125))
        XCTAssertEqual(pane.list.selectedID, ButtonsListLayout.thumbWheelRowID)
        pane.list.keyDown(with: try key("\r", keyCode: 36))
        XCTAssertEqual(openedMenus.count, 1)
        XCTAssertTrue(openedMenus.first === row.pullDown)
        // Delete and "−" ask for nothing: the row cannot be removed.
        var removals: [AnyHashable] = []
        let remove = pane.list.onRemove
        pane.list.onRemove = { removals.append($0); remove?($0) }
        XCTAssertFalse(row.isRemovable)
        XCTAssertFalse(pane.list.removeButton.isEnabled)
        let listed = pane.list.rows
        pane.list.keyDown(with: try key("\u{7F}", keyCode: 51))
        pane.list.removeButton.performClick(nil)
        XCTAssertEqual(removals, [], "no removal was asked for")
        XCTAssertTrue(pane.thumbWheelRow === row)
        XCTAssertTrue(pane.list.rows.elementsEqual(listed, by: ===), "the list is as it was")
        XCTAssertEqual(pane.list.selectedID, ButtonsListLayout.thumbWheelRowID)
        pane.list.keyDown(with: try key(String(Character(try XCTUnwrap(UnicodeScalar(NSDownArrowFunctionKey)))), keyCode: 125))
        XCTAssertEqual(pane.list.selectedID, AnyHashable(ButtonsMousePart.gesture))
        XCTAssertTrue(Options.shared.buttons.binding.isEmpty)
        XCTAssertEqual(Options.shared.thumbWheel, .default)
    }

    /// `image` drawn at 2x in the light appearance, as PNG bytes: two pictures are the same
    /// drawing when these are equal.
    private func pictureBytes(_ image: NSImage?) throws -> Data {
        let image = try XCTUnwrap(image)
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(image.size.width * 2), pixelsHigh: Int(image.size.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        try XCTUnwrap(NSAppearance(named: .aqua)).performAsCurrentDrawingAppearance {
            image.draw(in: NSRect(origin: .zero, size: image.size))
        }
        NSGraphicsContext.restoreGraphicsState()
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    private func thumbWheelPicture(_ mouse: MouseArtworkModel, highlighted: Bool) throws -> Data {
        return try pictureBytes(ButtonsMouseMiniature.image(lighting: .thumbWheel, mouse: mouse, highlighted: highlighted))
    }

    /// Another MX Master connects in place of the MX Master 4: the same row now shows the
    /// thumb wheel on the MX Master 3S's drawing.
    func testTheThumbWheelRowRedrawsItsPictureForAnotherMouse() throws {
        let pane = makePane()
        let row = try XCTUnwrap(pane.thumbWheelRow)
        XCTAssertEqual(try pictureBytes(row.iconView?.image), try thumbWheelPicture(.mxMaster4, highlighted: false))
        XCTAssertNotEqual(try thumbWheelPicture(.mxMaster4, highlighted: false), try thumbWheelPicture(.mxMaster3, highlighted: false))

        deviceName = "MX Master 3S"
        NotificationCenter.default.post(name: LogiCenter.mouseStateChanged, object: nil)
        XCTAssertTrue(pane.thumbWheelRow === row, "the same row")
        XCTAssertEqual(row.mouse, .mxMaster3)
        XCTAssertEqual(try pictureBytes(row.iconView?.image), try thumbWheelPicture(.mxMaster3, highlighted: false), "redrawn for the 3S")

        deviceName = "MX Master 4"
        NotificationCenter.default.post(name: LogiCenter.mouseStateChanged, object: nil)
        XCTAssertEqual(try pictureBytes(row.iconView?.image), try thumbWheelPicture(.mxMaster4, highlighted: false))
    }

    /// A window that counts as key, so the list's selection is drawn in the accent colour.
    private final class KeyWindow: NSWindow {
        override var isKeyWindow: Bool { return true }
    }

    /// Selected in a key window the row's picture is drawn for the accent-coloured selection
    /// (in white), and as before once the selection goes.
    func testTheThumbWheelRowDrawsItsPictureForTheSelection() throws {
        let pane = makePane()
        let window = KeyWindow(
            contentRect: NSRect(x: 0, y: 0, width: PreferencesWindowLayout.contentWidth, height: 600),
            styleMask: [.titled], backing: .buffered, defer: true
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: PreferencesWindowLayout.contentWidth, height: 600))
        window.contentView?.addSubview(pane.view)
        addTeardownBlock { window.close() }
        XCTAssertTrue(pane.list.isSelectionEmphasized)
        let row = try XCTUnwrap(pane.thumbWheelRow)
        let plain = try thumbWheelPicture(.mxMaster4, highlighted: false)
        let selected = try thumbWheelPicture(.mxMaster4, highlighted: true)
        XCTAssertNotEqual(plain, selected)
        XCTAssertEqual(try pictureBytes(row.iconView?.image), plain)

        pane.list.select(ButtonsListLayout.thumbWheelRowID)
        XCTAssertTrue(row.isHighlighted)
        XCTAssertEqual(try pictureBytes(row.iconView?.image), selected, "white on the selection")
        pane.list.select(ButtonsMousePart.back)
        XCTAssertFalse(row.isHighlighted)
        XCTAssertEqual(try pictureBytes(row.iconView?.image), plain)
    }

    /// A speed off the slider's grid (stored by hand, or by an older build) is shown as it
    /// is: opening the Buttons pane or the Scrolling tab writes nothing.
    func testOpeningEitherPaneWithAnOffGridSpeedWritesNothing() throws {
        let stored = ThumbWheelSettings(function: .tabs, speed: 1.234, swapsDirection: true)
        Options.shared.thumbWheel = stored
        Options.shared.flushPendingSaves()
        var flushed: [Set<OptionsGroup>] = []
        Options.shared.onFlushForTests = { flushed.append($0) }
        defer { Options.shared.onFlushForTests = nil }
        var changes = 0
        let observer = ThumbWheelSettingsChange.addObserver { changes += 1 }
        defer { ThumbWheelSettingsChange.removeObserver(observer) }

        let buttons = PreferencesButtonsViewController()
        buttons.deviceSource = ButtonsDeviceSource(captureStatus: { _ in .normal }, deviceName: { "MX Master 4" }, isBusy: { false }, refresh: {}, warnBluetoothButton: { _ in })
        buttons.scrollHoldKeys = { [] }
        _ = buttons.view
        buttons.viewWillAppear()
        XCTAssertEqual(shown(try XCTUnwrap(buttons.thumbWheelRow).pullDown), "Switch Tabs")

        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesScrollingViewController.self))
        let scrolling = try XCTUnwrap(storyboard.instantiateController(withIdentifier: PANEL_IDENTIFIER.scrolling) as? PreferencesScrollingViewController)
        let uiDefaults = TestDefaults.make(for: self)
        scrolling.uiStateDefaults = uiDefaults
        _ = scrolling.view
        scrolling.viewWillAppear()
        XCTAssertEqual(scrolling.thumbWheelSpeedSlider.doubleValue, 1.234, accuracy: 1e-9, "shown as it is")

        XCTAssertEqual(changes, 0, "nothing written")
        XCTAssertEqual(Options.shared.thumbWheel, stored)
        Options.shared.flushPendingSaves()
        XCTAssertEqual(flushed, [], "nothing saved")
    }

    /// The Buttons pane and Scrolling › Thumb wheel show one stored value: a change on
    /// either shows on the other at once, and showing it writes nothing back.
    func testBothPanesShowTheSameThumbWheel() throws {
        let buttons = makePane()
        let row = try XCTUnwrap(buttons.thumbWheelRow)
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesScrollingViewController.self))
        let scrolling = try XCTUnwrap(storyboard.instantiateController(withIdentifier: PANEL_IDENTIFIER.scrolling) as? PreferencesScrollingViewController)
        // Its UI state ("Advanced") in a store of the test's own.
        let uiDefaults = TestDefaults.make(for: self)
        scrolling.uiStateDefaults = uiDefaults
        _ = scrolling.view
        var changes = 0
        let observer = ThumbWheelSettingsChange.addObserver { changes += 1 }
        defer { ThumbWheelSettingsChange.removeObserver(observer) }

        // Buttons → Scrolling.
        let zoom = try XCTUnwrap(row.pullDown.functionItems.first { ThumbWheelPresentation.function(of: $0) == .zoom })
        row.pullDown.functionChosen(zoom)
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(scrolling.thumbWheelFunctionPopUp.titleOfSelectedItem, "Zoom")
        XCTAssertEqual(scrolling.thumbWheelFunctionRow.explanation, "Zooms the page in and out.")
        XCTAssertEqual(scrolling.thumbWheelSpeedRow.explanation, "Faster means less of a turn for each step.")

        // Scrolling → Buttons.
        let popUp = try XCTUnwrap(scrolling.thumbWheelFunctionPopUp)
        popUp.selectItem(at: try XCTUnwrap(ThumbWheelFunction.allCases.firstIndex(of: .backForward)))
        XCTAssertTrue(popUp.sendAction(popUp.action, to: popUp.target))
        XCTAssertEqual(changes, 2)
        XCTAssertEqual(shown(row.pullDown), "Back and Forward")
        XCTAssertEqual(row.explanation, "Goes back and forward.")
        buttons.list.select(ButtonsListLayout.thumbWheelRowID)
        XCTAssertEqual(buttons.headerView.content.subtitle, "Back and Forward")

        // The speed and the direction are the Scrolling pane's; the row keeps its function.
        scrolling.thumbWheelSwapSwitch.state = .on
        XCTAssertTrue(scrolling.thumbWheelSwapSwitch.sendAction(scrolling.thumbWheelSwapSwitch.action, to: scrolling.thumbWheelSwapSwitch.target))
        XCTAssertEqual(changes, 3)
        XCTAssertEqual(shown(row.pullDown), "Back and Forward")

        // Reset under Scrolling: the row reads "Default" again.
        scrolling.paneUndoManager = UndoManager()
        XCTAssertTrue(scrolling.resetToDefaultsButton.sendAction(scrolling.resetToDefaultsButton.action, to: scrolling.resetToDefaultsButton.target))
        XCTAssertEqual(Options.shared.thumbWheel, .default)
        XCTAssertEqual(shown(row.pullDown), "Default")
        XCTAssertEqual(buttons.headerView.content.subtitle, "Default")
        XCTAssertEqual(changes, 4, "one write for the reset, none from the panes showing it")
        XCTAssertTrue(Options.shared.buttons.binding.isEmpty)
    }

    /// A binding of a button without modifiers is that button's row: a standard button, a
    /// Logitech control, a numbered button said to be there. Two of one button: the one
    /// with an action is the row, the other is below with what tells them apart. The rest
    /// is below, as stored, where "−" works; the card counts every button with an action
    /// (a keyboard shortcut is a key, not a button: it was counted as one).
    func testABindingOfAButtonIsItsRowAndEverythingElseIsBelow() throws {
        let gestureNumber = ButtonBinding(triggerEvent: placed(6, .gestureButton), systemShortcutName: SystemShortcut.mouseGestureNavigation.identifier, isEnabled: true)
        let bindings = [
            binding(1006),
            binding(3, "copy"),
            gestureNumber,
            binding(1001, "paste", modifiers: option),
            binding(2, SystemShortcut.missionControl.identifier),
            binding(2000 + 0x005B, "copy"),
            binding(7, "copy"),
            binding(40, "copy", modifiers: control, type: .keyboard),
        ]
        let pane = makePane(bindings)
        XCTAssertEqual(pane.rows.map(\.title), [
            "Middle button", "Mode shift button", "Gesture button (button 6)", "Forward button", "Back button", "Thumb panel",
            "Back button (Logitech)", "⌥ Mode shift button", "Left Tilt button", "Button 7", "⌃ K",
        ])
        let top = Array(pane.rows.prefix(6))
        XCTAssertEqual(top.map(\.isStored), [true, false, true, false, true, false])
        XCTAssertEqual(top.map(\.isDefault), [false, true, false, true, false, true])
        XCTAssertEqual(top.map { shown($0.pullDown) }, [
            SystemShortcut.missionControl.localizedName, "Default", "Gesture Navigation", "Default", "Copy", "Default",
        ])
        XCTAssertEqual(pane.row(for: ButtonsMousePart.back)?.binding, bindings[1])
        XCTAssertEqual(pane.row(for: ButtonsMousePart.gesture)?.binding, gestureNumber)
        XCTAssertEqual(pane.rows.dropFirst(6).map(\.id), [bindings[0], bindings[3], bindings[5], bindings[6], bindings[7]].map { AnyHashable($0.id) })
        XCTAssertEqual(pane.list.groupTitles.count, 1)
        XCTAssertEqual(pane.list.groupTitles[AnyHashable(bindings[0].id)]?.title, "Other buttons and keys")
        XCTAssertEqual(pane.layout.others, [bindings[0], bindings[3], bindings[5], bindings[6], bindings[7]])

        pane.list.select(bindings[6].id)
        XCTAssertTrue(pane.list.removeButton.isEnabled)
        pane.list.select(ButtonsMousePart.back)
        XCTAssertFalse(pane.list.removeButton.isEnabled, "a button of the mouse is cleared with Default")
        pane.list.select(nil)
        XCTAssertEqual(pane.headerView.content.subtitle, "6 buttons have actions", "the seven with an action, less ⌃ K")
        XCTAssertEqual(PreferencesButtonsViewController.boundButtonCount(in: bindings), 6)
        XCTAssertEqual(Options.shared.buttons.binding, bindings, "nothing is rewritten")

        // "−" below; the Logitech Back button goes and the Back button's row stays.
        pane.list.select(bindings[0].id)
        pane.list.removeButton.performClick(nil)
        XCTAssertEqual(Options.shared.buttons.binding.count, 7)
        XCTAssertEqual(pane.list.groupTitles[AnyHashable(bindings[3].id)]?.title, "Other buttons and keys", "the title moves to the first one below")
    }

    /// Choosing an action on a "Default" row stores that button's binding, as bindings were
    /// always stored, with what "+" would record for the button on this mouse; the row stays
    /// the same view. "Default" on a row with a binding removes it, and Undo puts it back.
    func testADefaultRowStoresItsBindingWhenItGetsAnAction() throws {
        let pane = makePane()
        let undo = try XCTUnwrap(pane.paneUndoManager)
        undo.groupsByEvent = false
        let back = try XCTUnwrap(pane.row(for: ButtonsMousePart.back))
        let menu = try XCTUnwrap(back.pullDown.menu)
        back.pullDown.shortcutSelected(try XCTUnwrap(item("copy", in: menu)))

        XCTAssertEqual(Options.shared.buttons.binding.count, 1)
        let stored = try XCTUnwrap(Options.shared.buttons.binding.first)
        XCTAssertEqual(stored.triggerEvent, RecordedEvent(type: .mouse, code: 3, modifiers: 0, deviceFilter: nil),
                       "the standard Back button: no Logitech session diverts it here")
        XCTAssertEqual(stored.systemShortcutName, "copy")
        XCTAssertTrue(stored.isEnabled)
        XCTAssertTrue(pane.row(for: ButtonsMousePart.back) === back, "the same row")
        XCTAssertTrue(back.pullDown.menu === menu)
        XCTAssertTrue(back.isStored)
        XCTAssertFalse(back.isDefault)
        XCTAssertEqual(shown(back.pullDown), "Copy")
        XCTAssertNil(back.explanation)
        XCTAssertEqual(pane.headerView.content.subtitle, "1 button has an action")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: try sortedJSON(Options.shared.buttons.binding)) as? [[String: Any]])
        XCTAssertEqual(Set(object[0].keys), ["id", "triggerEvent", "systemShortcutName", "isEnabled", "createdAt"])
        XCTAssertEqual(Set((object[0]["triggerEvent"] as? [String: Any] ?? [:]).keys), ["type", "code", "modifiers"])

        // The others: the standard middle and forward buttons, the Logitech controls.
        let expected: [(ButtonsMousePart, UInt16)] = [(.gesture, 1000), (.modeShift, 1001), (.thumbPanel, 2000 + 0x01A0), (.middle, 2), (.forward, 4)]
        for (part, code) in expected {
            let row = try XCTUnwrap(pane.row(for: part))
            row.pullDown.shortcutSelected(try XCTUnwrap(item("paste", in: row.pullDown.menu)))
            XCTAssertEqual(pane.row(for: part)?.binding.triggerEvent, RecordedEvent(type: .mouse, code: code, modifiers: 0, deviceFilter: nil), "\(part)")
            XCTAssertTrue(pane.row(for: part) === row)
        }
        XCTAssertEqual(Options.shared.buttons.binding.map(\.triggerEvent.code), [3, 1000, 1001, 2000 + 0x01A0, 2, 4])
        XCTAssertEqual(pane.rows.count, 6)
        XCTAssertTrue(pane.list.groupTitles.isEmpty)

        // "Default": the binding goes, the row stays; Undo puts it back, Redo removes it.
        let defaultItem = try XCTUnwrap(back.pullDown.noActionItem)
        undo.beginUndoGrouping()
        back.pullDown.shortcutSelected(defaultItem)
        undo.endUndoGrouping()
        XCTAssertFalse(Options.shared.buttons.binding.contains { $0.id == stored.id })
        XCTAssertTrue(pane.row(for: ButtonsMousePart.back) === back)
        XCTAssertTrue(back.isDefault)
        XCTAssertFalse(back.isStored)
        XCTAssertEqual(shown(back.pullDown), "Default")
        XCTAssertEqual(back.explanation, "Goes back in apps that support it.")
        XCTAssertEqual(undo.undoMenuItemTitle, "Undo Remove Button")
        undo.undo()
        XCTAssertEqual(Options.shared.buttons.binding.first, stored, "back where it was, unchanged")
        XCTAssertEqual(shown(back.pullDown), "Copy")
        XCTAssertEqual(pane.list.selectedID, AnyHashable(ButtonsMousePart.back))
        undo.redo()
        XCTAssertFalse(Options.shared.buttons.binding.contains { $0.id == stored.id })

        // "Default" on a row without a binding changes nothing.
        back.pullDown.shortcutSelected(defaultItem)
        XCTAssertEqual(Options.shared.buttons.binding.count, 5)
        XCTAssertEqual(shown(back.pullDown), "Default")
    }

    /// What a "Default" row stores is what "+" records for that button on this mouse: over a
    /// receiver every control is diverted while "+" records (the Logitech code); over
    /// Bluetooth the standard middle, back and forward buttons stay native; a control no
    /// Logitech session reports reaches the Mac as the standard button it is. The gesture
    /// button, the mode shift button and the thumb panel are always their Logitech code.
    func testTheTriggerADefaultRowStoresIsWhatPlusRecords() throws {
        let policy = LogiButtonDeliveryPolicy(standardMouseButtonsUseNativeEvents: true)
        func diagnosis(over transport: LogiTransportIdentity?) -> (UInt16) -> LogiButtonCaptureDiagnosis {
            return { code in
                let native = LogiCenter.shared.nativeMouseButton(forScrollioCode: code)
                guard let transport, let cid = LogiCIDDirectory.toCID(code) else { return .unknown(nativeMouseButton: native) }
                return LogiButtonCaptureDiagnosis(
                    ownership: .scrollioOwned,
                    delivery: .hidpp,
                    ownershipKey: LogiOwnershipKey(vendorId: 0x046D, productId: 0xB042, name: "MX Master 4", transport: transport, cid: cid),
                    nativeMouseButton: native,
                    usesNativeEvents: !policy.shouldUseHIDPPDelivery(transport: transport, cid: cid, phase: .recording)
                )
            }
        }
        let parts: [ButtonsMousePart] = [.middle, .back, .forward, .gesture, .modeShift, .thumbPanel]
        func codes(over transport: LogiTransportIdentity?) -> [UInt16] {
            return parts.map { $0.recordedTrigger(diagnosis: diagnosis(over: transport)).code }
        }
        XCTAssertEqual(codes(over: .receiver), [1005, 1006, 1007, 1000, 1001, 2000 + 0x01A0])
        XCTAssertEqual(codes(over: .bleDirect), [2, 3, 4, 1000, 1001, 2000 + 0x01A0])
        XCTAssertEqual(codes(over: nil), [2, 3, 4, 1000, 1001, 2000 + 0x01A0])
        XCTAssertTrue(parts.allSatisfy { $0.recordedTrigger(diagnosis: diagnosis(over: .receiver)).modifiers == 0 })
        // The same as "+" stores a press of the control while it is diverted.
        let receiver = diagnosis(over: .receiver)
        for code: UInt16 in [1005, 1006, 1007, 1000] {
            let pressed = RecordedEvent(type: .mouse, code: code, modifiers: 0, deviceFilter: nil)
            XCTAssertEqual(pressed.normalizedForButtonBinding(diagnosis: receiver(code)).code, code)
            XCTAssertEqual(pressed.normalizedForButtonBinding(diagnosis: diagnosis(over: .bleDirect)(code)).code,
                           LogiCenter.shared.nativeMouseButton(forScrollioCode: code) ?? code)
        }

        // In the pane, over a receiver: the Back button's row stores the Logitech Back button.
        let pane = makePane()
        pane.deviceSource.recordedTrigger = { $0.recordedTrigger(diagnosis: receiver) }
        pane.reload()
        let back = try XCTUnwrap(pane.row(for: ButtonsMousePart.back))
        XCTAssertEqual(back.title, "Back button")
        XCTAssertEqual(back.explanation, "Goes back in apps that support it.", "not caught while it has no binding")
        back.pullDown.shortcutSelected(try XCTUnwrap(item("copy", in: back.pullDown.menu)))
        XCTAssertEqual(Options.shared.buttons.binding.first?.triggerEvent.code, 1006)
        XCTAssertEqual(back.title, "Back button")
    }

    /// "+" and a button of the mouse: its row is selected and flashes, the card answers
    /// "That's …", nothing is added, with a binding or without. With a modifier it is
    /// another button, added below. Gestures › Set Up… gives a row without a binding
    /// Gesture Navigation, stored for what was pressed.
    func testPlusOnAButtonOfTheMouseFlashesItsRow() throws {
        let pane = makePane([binding(3, "copy")])
        let recorder = KeyRecorder()
        pane.beginAddingBinding()
        pane.onRecordingStarted(recorder)
        let gesture = mouseEvent(1000)
        XCTAssertFalse(pane.validateRecordedEvent(recorder, event: gesture), "the recorder says it is listed")
        pane.onEventRecorded(recorder, didRecordEvent: gesture, isDuplicate: true)
        XCTAssertEqual(pane.list.selectedID, AnyHashable(ButtonsMousePart.gesture))
        XCTAssertEqual(pane.headerView.content, ButtonsHeaderContent(title: "That's Gesture button", subtitle: "Default", part: .gesture))
        pane.onRecordingStopped(recorder, didRecord: true)
        flush()
        XCTAssertEqual(Options.shared.buttons.binding.count, 1)
        XCTAssertEqual(pane.rows.count, 6)
        XCTAssertTrue(openedMenus.isEmpty)

        // The Logitech Back button is the Back button's row too.
        pane.beginAddingBinding()
        pane.onRecordingStarted(recorder)
        XCTAssertFalse(pane.validateRecordedEvent(recorder, event: mouseEvent(1006)))
        pane.onEventRecorded(recorder, didRecordEvent: mouseEvent(1006), isDuplicate: true)
        XCTAssertEqual(pane.headerView.content, ButtonsHeaderContent(title: "That's Back button", subtitle: "Copy", part: .back))
        XCTAssertEqual(pane.list.selectedID, AnyHashable(ButtonsMousePart.back))
        pane.onRecordingStopped(recorder, didRecord: true)
        XCTAssertEqual(Options.shared.buttons.binding.count, 1)

        // With a modifier: another button, added below, its menu opens.
        pane.beginAddingBinding()
        pane.onRecordingStarted(recorder)
        let optionGesture = mouseEvent(1000, modifiers: .maskAlternate)
        XCTAssertTrue(pane.validateRecordedEvent(recorder, event: optionGesture))
        pane.onEventRecorded(recorder, didRecordEvent: optionGesture, isDuplicate: false)
        pane.onRecordingStopped(recorder, didRecord: true)
        flush()
        let added = try XCTUnwrap(Options.shared.buttons.binding.last)
        XCTAssertEqual(pane.rows.last?.title, "⌥ Gesture button")
        XCTAssertEqual(pane.list.selectedID, AnyHashable(added.id))
        XCTAssertEqual(pane.list.groupTitles[AnyHashable(added.id)]?.title, "Other buttons and keys")
        XCTAssertEqual(openedMenus.count, 1)

        // Gestures › Set Up…: the thumb panel without a binding gets Gesture Navigation.
        pane.beginAddingBinding(action: SystemShortcut.mouseGestureNavigation)
        pane.onRecordingStarted(recorder)
        let panel = mouseEvent(2000 + 0x01A0)
        XCTAssertTrue(pane.validateRecordedEvent(recorder, event: panel), "it takes the action")
        pane.onEventRecorded(recorder, didRecordEvent: panel, isDuplicate: false)
        XCTAssertEqual(pane.headerView.content, ButtonsHeaderContent(title: "Thumb panel", subtitle: "Gesture Navigation", part: .thumbPanel))
        pane.onRecordingStopped(recorder, didRecord: true)
        flush()
        let gestureButton = try XCTUnwrap(Options.shared.buttons.binding.last)
        XCTAssertEqual(gestureButton.triggerEvent, RecordedEvent(type: .mouse, code: 2000 + 0x01A0, modifiers: 0, deviceFilter: nil))
        XCTAssertEqual(gestureButton.systemShortcutName, SystemShortcut.mouseGestureNavigation.identifier)
        XCTAssertEqual(pane.row(for: ButtonsMousePart.thumbPanel)?.binding, gestureButton)
        XCTAssertEqual(pane.list.selectedID, AnyHashable(ButtonsMousePart.thumbPanel))
        XCTAssertEqual(openedMenus.count, 1, "the action is set: no menu")
        let summary = MouseGestureBindingSummary(bindings: Options.shared.buttons.binding, isLogitechCode: { LogiCenter.shared.isLogiCode($0) })
        XCTAssertEqual(summary.buttonTitles, ["Thumb panel"], "the Gestures pane's line")
    }

    /// The line under a "Default" row says what the button then does only where that is
    /// certain: a hold key under Scrolling says so; while Scrollio catches its Logitech
    /// control for a binding with modifiers (the plain press then reaches only Scrollio),
    /// nothing; a numbered button said to be there makes no claim beyond its own.
    func testTheDefaultLineSaysOnlyWhatIsCertain() throws {
        scrollKeys = [ScrollHotkey(type: .mouse, code: 1001)]
        let caught = binding(1006, "copy", modifiers: option)
        let middle = ButtonBinding(triggerEvent: placed(8, .middleButton, modifiers: option), systemShortcutName: "copy", isEnabled: true)
        let pane = makePane([caught, binding(4, "copy", modifiers: command), middle])
        func row(_ part: ButtonsMousePart) throws -> ButtonBindingRow {
            return try XCTUnwrap(pane.row(for: part))
        }
        XCTAssertNil(try row(.back).explanation, "the plain press reaches only Scrollio")
        XCTAssertEqual(try row(.forward).explanation, "Goes forward in apps that support it.", "a standard button with ⌘ is not caught")
        XCTAssertEqual(try row(.modeShift).explanation, "Also set under Scrolling\u{A0}›\u{A0}While\u{A0}you\u{A0}hold\u{A0}a\u{A0}key.")
        XCTAssertEqual(try row(.modeShift).note?.tone, .problem)
        XCTAssertFalse(try row(.modeShift).infoButton.isHidden)
        XCTAssertEqual(try row(.middle).title, "Middle button (button 8)")
        XCTAssertEqual(try row(.middle).picture, .mouse(part: .middle, number: nil))
        XCTAssertEqual(try row(.middle).explanation, "Does what the mouse does on its own.")
        XCTAssertTrue(try row(.middle).placeButton.isHidden)

        // Without its action the ⌥ binding catches nothing.
        pane.setAction(of: caught.id, to: nil)
        XCTAssertEqual(try row(.back).explanation, "Goes back in apps that support it.")

        // The middle row stores the number said to be there, without modifiers.
        try row(.middle).pullDown.shortcutSelected(try XCTUnwrap(item("paste", in: try row(.middle).pullDown.menu)))
        let stored = try XCTUnwrap(Options.shared.buttons.binding.last)
        XCTAssertEqual(stored.triggerEvent, RecordedEvent(type: .mouse, code: 8, modifiers: 0, deviceFilter: nil))
        XCTAssertEqual(stored.triggerEvent.mousePart, .middleButton)
        XCTAssertEqual(try row(.middle).title, "Middle button (button 8)")
        XCTAssertFalse(try row(.middle).placeButton.isHidden, "stored, its place can be changed")
    }

    /// A button set to "Default" and given an action again gets the trigger it had, a
    /// numbered one too (an MX Master 4 over Bluetooth may send Button 6 for its gesture
    /// button). Another mouse starts afresh.
    func testADefaultRowGetsBackTheTriggerItHad() throws {
        let six = ButtonBinding(triggerEvent: placed(6, .gestureButton), systemShortcutName: SystemShortcut.mouseGestureNavigation.identifier, isEnabled: true)
        let pane = makePane([six])
        let row = try XCTUnwrap(pane.row(for: ButtonsMousePart.gesture))
        XCTAssertEqual(row.binding, six)
        row.pullDown.shortcutSelected(try XCTUnwrap(row.pullDown.noActionItem))
        XCTAssertTrue(Options.shared.buttons.binding.isEmpty)
        XCTAssertTrue(row.isDefault)
        XCTAssertEqual(row.title, "Gesture button (button 6)")
        XCTAssertEqual(row.explanation, "Does what the mouse does on its own.")

        let gestureItem = try XCTUnwrap(row.pullDown.gestureNavigationItem)
        row.pullDown.shortcutSelected(gestureItem)
        let stored = try XCTUnwrap(Options.shared.buttons.binding.first)
        XCTAssertEqual(stored.triggerEvent, six.triggerEvent)
        XCTAssertEqual(stored.triggerEvent.mousePart, .gestureButton)
        XCTAssertEqual(row.explanation, "Hold and move the mouse. Set the directions under Gestures.")

        // Another mouse: what "+" records for it.
        row.pullDown.shortcutSelected(try XCTUnwrap(row.pullDown.noActionItem))
        deviceName = "MX Master 3S"
        NotificationCenter.default.post(name: LogiCenter.mouseStateChanged, object: nil)
        XCTAssertEqual(pane.row(for: ButtonsMousePart.gesture)?.binding.triggerEvent.code, 1000)
        XCTAssertEqual(pane.row(for: ButtonsMousePart.gesture)?.title, "Gesture button")
    }

    /// "Open App or File…" and "Keyboard Shortcut…" on a "Default" row: nothing is stored
    /// until the app or the keys are chosen, then the button's binding.
    func testADefaultRowTakesAnAppOrAKeyboardShortcut() throws {
        let pane = makePane()
        let forward = try XCTUnwrap(pane.row(for: ButtonsMousePart.forward))
        let openItem = try XCTUnwrap(forward.pullDown.menu?.items.first { $0.representedObject as? String == ShortcutManager.MenuMarker.openTarget })
        forward.pullDown.shortcutSelected(openItem)
        let popover = try XCTUnwrap(pane.openTargetPopover)
        XCTAssertTrue(shownOpenTargets.first === forward.pullDown)
        XCTAssertTrue(Options.shared.buttons.binding.isEmpty, "nothing until it is chosen")
        let calculator = OpenTargetPayload(path: "/System/Applications/Calculator.app", bundleID: "com.apple.calculator", arguments: "", kind: .application)
        popover.onCommit?(calculator)
        XCTAssertNil(pane.openTargetPopover)
        let opens = try XCTUnwrap(Options.shared.buttons.binding.first)
        XCTAssertEqual(opens.openTarget, calculator)
        XCTAssertEqual(opens.triggerEvent.code, 4)
        XCTAssertEqual(shown(forward.pullDown), "Calculator")

        let middle = try XCTUnwrap(pane.row(for: ButtonsMousePart.middle))
        let shortcut = "custom::40:\(UInt64(CGEventFlags.maskCommand.rawValue))"
        middle.pullDown.onCustomShortcutRecorded?(shortcut)
        XCTAssertEqual(Options.shared.buttons.binding.last?.systemShortcutName, shortcut)
        XCTAssertEqual(Options.shared.buttons.binding.last?.triggerEvent.code, 2)
        XCTAssertEqual(shown(middle.pullDown), "⌘K")
    }

    /// A Logitech button that may stop working over Bluetooth warns once when it gets an
    /// action on its row, as when "+" adds it; without an action it says what it does.
    func testAButtonThatMayStopWorkingOverBluetoothWarnsWhenItGetsAnAction() throws {
        captureStatus = [2000 + 0x01A0: .bleHIDPPUnstable]
        let pane = makePane()
        let panel = try XCTUnwrap(pane.row(for: ButtonsMousePart.thumbPanel))
        XCTAssertEqual(panel.explanation, "Does what the mouse does on its own.")
        panel.pullDown.shortcutSelected(try XCTUnwrap(item("copy", in: panel.pullDown.menu)))
        XCTAssertEqual(warnedCodes, [2000 + 0x01A0])
        XCTAssertEqual(panel.explanation, "May stop working while Logi Options+ runs.")
    }

    // MARK: - Names

    func testRowTitlesOfMouseButtons() {
        let names = (0...7).map { ButtonTriggerNaming.title(for: RecordedEvent(type: .mouse, code: $0, modifiers: 0, deviceFilter: nil)) }
        XCTAssertEqual(names, [
            "Left button", "Right button", "Middle button", "Back button", "Forward button",
            "Button 5", "Button 6", "Button 7",
        ])
        // Logitech controls by their role, others by their name.
        func logitech(_ code: UInt16) -> String {
            return ButtonTriggerNaming.title(for: RecordedEvent(type: .mouse, code: code, modifiers: 0, deviceFilter: nil))
        }
        XCTAssertEqual(logitech(1000), "Gesture button")
        XCTAssertEqual(logitech(1002), "Gesture button")
        XCTAssertEqual(logitech(1001), "Mode shift button")
        XCTAssertEqual(logitech(1005), "Middle button")
        XCTAssertEqual(logitech(1006), "Back button")
        XCTAssertEqual(logitech(1007), "Forward button")
        XCTAssertEqual(logitech(2000 + 0x005B), "Left Tilt button")
        // In the words of the other panes: the MX Master 4's haptic sense panel is the Mouse
        // pane's thumb panel, and no "DPI".
        XCTAssertEqual(logitech(2000 + 0x01A0), "Thumb panel")
        XCTAssertEqual(logitech(2000 + 0x00FD), "Pointer speed button")
    }

    /// A Logitech Back, Forward or Middle button reads like the standard one: only when
    /// both are in the list does the Logitech one say so.
    func testALogitechButtonNamedLikeAStandardOneInTheListSaysSo() throws {
        XCTAssertEqual(titles([1006]), ["Back button"], "alone, no word more")
        XCTAssertEqual(titles([3, 1006]), ["Back button", "Back button (Logitech)"])
        XCTAssertEqual(titles([1006, 3]), ["Back button (Logitech)", "Back button"])
        XCTAssertEqual(titles([1007, 4, 1005, 1000, 2000 + 0x0054]),
                       ["Forward button (Logitech)", "Forward button", "Middle button", "Gesture button", "Back button"])
        // Other modifiers: the rows do not read the same.
        XCTAssertEqual(titles([3, 1006], modifiers: [3: option]), ["⌥ Back button", "Back button"])
        XCTAssertEqual(titles([3, 1006], modifiers: [3: option, 1006: option]), ["⌥ Back button", "⌥ Back button (Logitech)"])

        // The plain list; on an MX Master the second one is under the Back button's row.
        deviceName = nil
        let native = binding(3, "copy")
        let logitech = binding(1006, SystemShortcut.mouseGestureNavigation.identifier)
        let pane = makePane([native, logitech])
        XCTAssertEqual(pane.rows.map(\.title), ["Back button", "Back button (Logitech)"])
        pane.list.select(logitech.id)
        XCTAssertEqual(pane.headerView.content.title, "Back button (Logitech)", "the card says what the row says")
        XCTAssertEqual(pane.rows[1].accessibilityLabel(), "Back button (Logitech), Hold and move the mouse. Set the directions under Gestures.")

        // The standard one goes: the Logitech one is the Back button again.
        pane.removeBinding(id: native.id)
        XCTAssertEqual(pane.rows.map(\.title), ["Back button"])
    }

    func testRowTitlesPutModifiersInFrontInMenuOrder() {
        let backWithOptionCommand = RecordedEvent(type: .mouse, code: 3, modifiers: option | command, deviceFilter: nil)
        XCTAssertEqual(ButtonTriggerNaming.title(for: backWithOptionCommand), "⌥⌘ Back button")
        let shiftCommandControl = RecordedEvent(type: .mouse, code: 1000, modifiers: UInt(CGEventFlags.maskShift.rawValue) | command | control, deviceFilter: nil)
        XCTAssertEqual(ButtonTriggerNaming.title(for: shiftCommandControl), "⌃⇧⌘ Gesture button")
    }

    func testRowTitlesOfKeys() {
        let fn = UInt(CGEventFlags.maskSecondaryFn.rawValue)
        XCTAssertEqual(ButtonTriggerNaming.title(for: RecordedEvent(type: .keyboard, code: 40, modifiers: control | option, deviceFilter: nil)), "⌃⌥ K")
        // A function key arrives with Fn set; it is not written.
        XCTAssertEqual(ButtonTriggerNaming.title(for: RecordedEvent(type: .keyboard, code: KeyCode.F5, modifiers: fn, deviceFilter: nil)), "F5")
        XCTAssertEqual(ButtonTriggerNaming.title(for: RecordedEvent(type: .keyboard, code: KeyCode.optionL, modifiers: command, deviceFilter: nil)), "⌥⌘")
        XCTAssertEqual(ButtonTriggerNaming.shortcutText(type: .keyboard, code: 21, modifiers: UInt64(command) | UInt64(CGEventFlags.maskShift.rawValue)), "⇧⌘4")
    }

    // MARK: - The part of the mouse

    func testWhichPartATriggerLights() {
        func part(_ code: UInt16, modifiers: UInt = 0, type: EventType = .mouse) -> ButtonsMousePart? {
            return ButtonsMousePart.part(for: RecordedEvent(type: type, code: code, modifiers: modifiers, deviceFilter: nil))
        }
        XCTAssertEqual(part(0), .left)
        XCTAssertEqual(part(1), .right)
        XCTAssertEqual(part(2), .middle)
        XCTAssertEqual(part(3), .back)
        XCTAssertEqual(part(4), .forward)
        XCTAssertEqual(part(3, modifiers: option | command), .back, "modifiers do not matter")
        XCTAssertNil(part(5))
        XCTAssertEqual(part(1000), .gesture)
        XCTAssertEqual(part(1002), .gesture)
        XCTAssertEqual(part(1001), .modeShift)
        XCTAssertEqual(part(1005), .middle)
        XCTAssertEqual(part(1006), .back)
        XCTAssertEqual(part(1007), .forward)
        XCTAssertEqual(part(2000 + 0x01A0), .thumbPanel, "the MX Master 4's thumb panel, a part of its own")
        XCTAssertNil(part(2000 + 0x005B), "a tilt is not drawn")
        XCTAssertNil(part(40, type: .keyboard), "a key lights nothing")
        XCTAssertNil(part(3, type: .keyboard))

        // A numbered button lights the part the user said it is.
        func lit(_ code: UInt16, _ answer: PlacedMousePart, type: EventType = .mouse) -> ButtonsMousePart? {
            return ButtonsMousePart.part(for: RecordedEvent(type: type, code: code, modifiers: option, deviceFilter: nil, mousePart: answer))
        }
        XCTAssertEqual(lit(6, .gestureButton), .gesture)
        XCTAssertEqual(lit(5, .thumbPanel), .thumbPanel, "on the MX Master 4 not where its gesture button is")
        XCTAssertEqual(lit(7, .backButton), .back)
        XCTAssertEqual(lit(8, .forwardButton), .forward)
        XCTAssertEqual(lit(9, .modeShiftButton), .modeShift)
        XCTAssertEqual(lit(12, .middleButton), .middle)
        // A place stored on a button whose place is known, or on a key, is ignored.
        XCTAssertEqual(lit(3, .gestureButton), .back)
        XCTAssertEqual(lit(1001, .backButton), .modeShift)
        XCTAssertNil(lit(2000 + 0x005B, .backButton), "a Logitech control is not a numbered button")
        XCTAssertNil(lit(6, .gestureButton, type: .keyboard))
    }

    /// Under Reduce Motion a part lights at once, without the fade; otherwise it fades in.
    func testTheLitPartFollowsReduceMotion() {
        let header = ButtonsHeaderView(frame: NSRect(x: 0, y: 0, width: 480, height: ButtonsHeaderView.preferredHeight))
        let window = NSWindow(contentRect: header.frame, styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = header
        addTeardownBlock { window.close() }
        header.prefersReducedMotion = { true }
        header.content = ButtonsHeaderContent(title: "Back button", subtitle: "Copy", part: .back)
        XCTAssertEqual(header.artwork.highlights[.back]?.alphaValue, 1, "no fade under Reduce Motion")
        XCTAssertEqual(header.artwork.highlights[.left]?.alphaValue, 0)
        header.content = ButtonsHeaderContent(title: "Left button", subtitle: "Copy", part: .left)
        XCTAssertEqual(header.artwork.highlights[.back]?.alphaValue, 0)
        XCTAssertEqual(header.artwork.highlights[.left]?.alphaValue, 1)
    }

    /// The card of an MX Master 4 turns its drawing to the thumb side for a row whose part
    /// lights there (a side button, the thumb panel, the thumb wheel) and back from above
    /// for the others and for none: with a turn, and at once under Reduce Motion.
    func testTheCardTurnsTheDrawingToTheRowsPart() {
        let header = ButtonsHeaderView(frame: NSRect(x: 0, y: 0, width: 480, height: ButtonsHeaderView.preferredHeight))
        let window = NSWindow(contentRect: header.frame, styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = header
        addTeardownBlock { window.close() }
        header.mouse = .mxMaster4
        let base = header.artwork.base
        var now: TimeInterval = 10
        base.clock = { now }

        header.prefersReducedMotion = { false }
        header.content = ButtonsHeaderContent(title: "Back button", subtitle: "Copy", part: .back)
        XCTAssertEqual(base.viewpoint, .thumbSide)
        XCTAssertTrue(base.isTurning, "it turns")
        XCTAssertEqual(base.turn, 0)
        now += MouseArtworkTurn.duration
        base.advanceTurn()
        XCTAssertEqual(base.turn, 1)
        XCTAssertFalse(base.isTurning)
        header.content = ButtonsHeaderContent(title: "Thumb wheel", subtitle: "Default", part: nil, lightsThumbWheel: true)
        XCTAssertEqual(base.viewpoint, .thumbSide, "the thumb wheel lights from the thumb side too")
        XCTAssertFalse(base.isTurning, "no turn between two parts of one view")
        header.content = ButtonsHeaderContent(title: "Middle button", subtitle: "Copy", part: .middle)
        XCTAssertEqual(base.viewpoint, .above, "a part of the top turns it back")
        XCTAssertTrue(base.isTurning)
        now += MouseArtworkTurn.duration
        base.advanceTurn()
        XCTAssertEqual(base.turn, 0)

        header.prefersReducedMotion = { true }
        for (content, viewpoint) in [
            (ButtonsHeaderContent(title: "Gesture button", subtitle: "Copy", part: .gesture), MouseArtworkViewpoint.thumbSide),
            (ButtonsHeaderContent(title: "Left button", subtitle: "Copy", part: .left), .above),
            (ButtonsHeaderContent(title: "Thumb panel", subtitle: "Copy", part: .thumbPanel), .thumbSide),
            (ButtonsHeaderContent(title: "Forward button", subtitle: "Copy", part: .forward), .thumbSide),
            (ButtonsHeaderContent(title: "MX Master 4", subtitle: "1 button has an action.", part: nil), .above),
        ] {
            header.content = content
            XCTAssertEqual(base.viewpoint, viewpoint, content.title)
            XCTAssertEqual(base.turn, viewpoint == .thumbSide ? 1 : 0, "at once under Reduce Motion: \(content.title)")
            XCTAssertFalse(base.isTurning, "no animation under Reduce Motion: \(content.title)")
        }

        // An MX Master 3S turns the same way for its side buttons and its thumb wheel. Its
        // gesture button is the thumb rest, which shows from above: no turn for it.
        header.mouse = .mxMaster3
        for (content, viewpoint) in [
            (ButtonsHeaderContent(title: "Back button", subtitle: "Copy", part: .back), MouseArtworkViewpoint.thumbSide),
            (ButtonsHeaderContent(title: "Mode shift button", subtitle: "Copy", part: .modeShift), .above),
            (ButtonsHeaderContent(title: "Gesture button", subtitle: "Copy", part: .gesture), .above),
            (ButtonsHeaderContent(title: "Thumb wheel", subtitle: "Default", part: nil, lightsThumbWheel: true), .thumbSide),
            (ButtonsHeaderContent(title: "MX Master 3S", subtitle: "1 button has an action.", part: nil), .above),
        ] {
            header.content = content
            XCTAssertEqual(base.viewpoint, viewpoint, "MX Master 3S: \(content.title)")
            XCTAssertEqual(base.turn, viewpoint == .thumbSide ? 1 : 0)
        }
        header.prefersReducedMotion = { false }
        header.content = ButtonsHeaderContent(title: "Forward button", subtitle: "Copy", part: .forward)
        XCTAssertTrue(base.isTurning, "the MX Master 3S turns too")
        now += MouseArtworkTurn.duration
        base.advanceTurn()
        XCTAssertEqual(base.turn, 1)

        // The plain mouse: its side buttons are in its one view.
        header.mouse = .generic
        header.content = ButtonsHeaderContent(title: "Back button", subtitle: "Copy", part: .back)
        XCTAssertEqual(base.viewpoint, .above)
        XCTAssertFalse(base.isTurning)
        XCTAssertEqual(base.turn, 0)
    }

    func testLogiCenterTellsTheRoleOfAControl() {
        let center = LogiCenter.shared
        XCTAssertEqual(center.controlRole(forScrollioCode: 1000), .gesture)
        XCTAssertEqual(center.controlRole(forScrollioCode: 1001), .modeShift)
        XCTAssertEqual(center.controlRole(forScrollioCode: 1005), .middle)
        XCTAssertEqual(center.controlRole(forScrollioCode: 1006), .back)
        XCTAssertEqual(center.controlRole(forScrollioCode: 2000 + 0x0054), .back)
        XCTAssertEqual(center.controlRole(forScrollioCode: 1007), .forward)
        XCTAssertEqual(center.controlRole(forScrollioCode: 2000 + 0x01A0), .thumbPanel)
        XCTAssertNil(center.controlRole(forScrollioCode: 2000 + 0x005B))
        XCTAssertNil(center.controlRole(forScrollioCode: 3), "a native button is not a Logitech control")
    }

    /// The MX Master 4's thumb panel lights the thumb rest of the drawing, its gesture
    /// button the front side button: two parts.
    func testTheThumbPanelLightsTheThumbPanelOfTheCard() {
        let panel = binding(2000 + 0x01A0, SystemShortcut.mouseGestureNavigation.identifier)
        let gesture = binding(1000, "copy")
        let pane = makePane([binding(3, "copy"), panel, gesture])
        XCTAssertEqual(pane.headerView.artwork.model, .mxMaster4)
        pane.list.select(pane.rowID(forBinding: panel.id))
        XCTAssertEqual(pane.headerView.content, ButtonsHeaderContent(title: "Thumb panel", subtitle: "Gesture Navigation", part: .thumbPanel))
        XCTAssertEqual(pane.headerView.artwork.emphasis, .thumbPanel)
        XCTAssertEqual(pane.headerView.artwork.highlights[.thumbPanel]?.alphaValue, 1)
        XCTAssertEqual(pane.headerView.artwork.highlights[.gesture]?.alphaValue, 0)
        XCTAssertEqual(pane.headerView.artwork.highlights[.back]?.alphaValue, 0)
        pane.list.select(pane.rowID(forBinding: gesture.id))
        XCTAssertEqual(pane.headerView.artwork.highlights[.gesture]?.alphaValue, 1)
        XCTAssertEqual(pane.headerView.artwork.highlights[.thumbPanel]?.alphaValue, 0)
        let front = MouseArtworkView.shape(of: .gesture, model: .mxMaster4)?.bounds
        let rest = MouseArtworkView.shape(of: .thumbPanel, model: .mxMaster4)?.bounds
        XCTAssertNotNil(front)
        XCTAssertNotNil(rest)
        XCTAssertNotEqual(front, rest, "two shapes")
    }

    // MARK: - The card

    func testTheCardSaysHowManyButtonsHaveActions() {
        typealias Content = ButtonsHeaderContent
        let findHint = "Not sure which is which? Click + and press a button."
        XCTAssertEqual(Content.make(deviceName: nil, boundCount: 0, isRecording: false, focus: nil),
                       Content(title: "Your mouse", subtitle: "No buttons set up yet", part: nil, hint: findHint))
        XCTAssertEqual(Content.make(deviceName: "MX Master 3S", boundCount: 1, isRecording: false, focus: nil),
                       Content(title: "MX Master 3S", subtitle: "1 button has an action", part: nil, hint: findHint))
        XCTAssertEqual(Content.make(deviceName: "", boundCount: 4, isRecording: false, focus: nil),
                       Content(title: "Your mouse", subtitle: "4 buttons have actions", part: nil, hint: findHint))
        let focus = Content.Focus(title: "Back button", action: nil, picture: .mouse(part: .back, number: nil))
        XCTAssertEqual(Content.make(deviceName: nil, boundCount: 4, isRecording: false, focus: focus),
                       Content(title: "Back button", subtitle: "No action", part: .back))
        XCTAssertEqual(Content.make(deviceName: nil, boundCount: 4, isRecording: true, focus: focus),
                       Content(title: "Press a button", subtitle: "Or a key with ⌘, ⌥, ⌃ or ⇧.\nPress Esc to cancel.", part: nil))
    }

    func testTheCardFollowsTheSelectedRowAndCountsOnlyBoundButtons() {
        let pane = makePane([binding(3, SystemShortcut.mouseGestureNavigation.identifier), binding(4), binding(1000, "copy")])
        XCTAssertEqual(pane.headerView.content, ButtonsHeaderContent(
            title: "MX Master 4", subtitle: "2 buttons have actions", part: nil,
            hint: "Not sure which is which? Click + and press a button."
        ))

        pane.list.select(ButtonsMousePart.back)
        XCTAssertEqual(pane.headerView.content, ButtonsHeaderContent(title: "Back button", subtitle: "Gesture Navigation", part: .back))
        XCTAssertEqual(pane.headerView.artwork.emphasis, .back)
        XCTAssertEqual(pane.headerView.artwork.highlights[.back]?.alphaValue, 1)
        XCTAssertEqual(pane.headerView.artwork.highlights[.left]?.alphaValue, 0)

        // A button of the mouse without an action does what it does by itself.
        pane.list.select(ButtonsMousePart.forward)
        XCTAssertEqual(pane.headerView.content.subtitle, "Default")
        XCTAssertEqual(pane.headerView.artwork.emphasis, .forward)

        pane.list.select(ButtonsMousePart.gesture)
        XCTAssertEqual(pane.headerView.content, ButtonsHeaderContent(title: "Gesture button", subtitle: "Copy", part: .gesture))

        pane.list.select(nil)
        XCTAssertNil(pane.headerView.artwork.emphasis)
        XCTAssertEqual(pane.headerView.accessibilityLabel(), "MX Master 4, 2 buttons have actions, Not sure which is which? Click + and press a button.")
        XCTAssertFalse(pane.headerView.hintLabel.isHidden)
    }

    /// "5 buttons have actions" counted keyboard shortcuts too. The card counts buttons: a
    /// mouse button with or without modifier keys, never a key.
    func testTheCardCountsButtonsNotKeys() {
        let key = binding(40, "copy", modifiers: control, type: .keyboard)
        let bindings = [binding(3, "copy"), key, binding(4, "paste", modifiers: option), binding(5)]
        XCTAssertEqual(PreferencesButtonsViewController.boundButtonCount(in: bindings), 2, "⌃ K is a key, button 5 has no action")
        XCTAssertEqual(PreferencesButtonsViewController.boundButtonCount(in: [key]), 0)

        let pane = makePane(bindings)
        XCTAssertEqual(pane.headerView.content.subtitle, "2 buttons have actions")
        deviceName = nil
        let keyOnly = makePane([key])
        XCTAssertEqual(keyOnly.headerView.content.subtitle, "No buttons set up yet", "a key is listed, no button is set up")
        XCTAssertEqual(keyOnly.headerView.content.hint, "Not sure which is which? Click + and press a button.", "the list is not empty")

        typealias Content = ButtonsHeaderContent
        XCTAssertEqual(Content.make(deviceName: nil, boundCount: 0, isRecording: false, listIsEmpty: true, focus: nil),
                       Content(title: "Your mouse", subtitle: "No buttons set up yet", part: nil, hint: nil))
    }

    /// Gestures › Change: the row of the button that runs Gesture Navigation is selected and
    /// lit on the card. A key with that action (it cannot run it) and a disabled binding are
    /// passed over; without a gesture button nothing is selected.
    func testSelectGestureButtonSelectsTheRowThatRunsGestureNavigation() {
        let gestureNavigation = SystemShortcut.mouseGestureNavigation.identifier
        let key = binding(40, gestureNavigation, modifiers: control, type: .keyboard)
        var off = binding(3, gestureNavigation)
        off.isEnabled = false
        let gesture = binding(4, gestureNavigation)
        let bindings = [binding(5, "copy"), key, off, gesture]
        let pane = makePane(bindings)
        XCTAssertEqual(pane.gestureButtonBinding, gesture)
        XCTAssertNil(pane.list.selectedID)

        XCTAssertTrue(pane.selectGestureButton())
        XCTAssertEqual(pane.list.selectedID, pane.rowID(forBinding: gesture.id))
        XCTAssertEqual(pane.list.selectedID, AnyHashable(ButtonsMousePart.forward), "the Forward button's row")
        XCTAssertEqual(pane.headerView.content.title, "Forward button")
        XCTAssertEqual(pane.headerView.content.subtitle, "Gesture Navigation")
        XCTAssertEqual(pane.headerView.content.part, .forward)
        XCTAssertTrue(anchors.isEmpty, "nothing is recorded")
        XCTAssertTrue(openedMenus.isEmpty, "no menu opens")
        XCTAssertEqual(Options.shared.buttons.binding, bindings, "nothing is changed")

        // A gesture button made elsewhere while the pane was away is found too.
        let other = makePane([binding(3, "copy")])
        XCTAssertFalse(other.selectGestureButton(), "no button runs it")
        XCTAssertNil(other.list.selectedID)
        let late = binding(1000, gestureNavigation)
        Options.shared.buttons.binding = [binding(3, "copy"), late]
        XCTAssertTrue(other.selectGestureButton())
        XCTAssertEqual(other.list.selectedID, other.rowID(forBinding: late.id))
        XCTAssertEqual(other.headerView.content.part, .gesture)
    }

    // MARK: - Which button is which

    /// A row's picture lights its part only where the place is certain; a button the Mac
    /// knows by its number shows its number, a key a keyboard.
    func testWhichPictureARowShows() {
        func picture(_ code: UInt16, type: EventType = .mouse) -> ButtonTriggerPicture {
            return ButtonTriggerPicture.make(for: RecordedEvent(type: type, code: code, modifiers: 0, deviceFilter: nil), mouse: .mxMaster4)
        }
        XCTAssertEqual(picture(40, type: .keyboard), .key)
        XCTAssertEqual(picture(5, type: .keyboard), .key, "a key code is no button number")
        XCTAssertEqual(picture(0), .mouse(part: .left, number: nil))
        XCTAssertEqual(picture(3), .mouse(part: .back, number: nil))
        XCTAssertEqual(picture(4), .mouse(part: .forward, number: nil))
        XCTAssertEqual(picture(5), .mouse(part: nil, number: 5), "where Button 5 is, only the mouse can tell")
        XCTAssertEqual(picture(6), .mouse(part: nil, number: 6))
        XCTAssertEqual(picture(1001), .mouse(part: .modeShift, number: nil), "the button behind the wheel, as a Logitech control")
        XCTAssertEqual(picture(1000), .mouse(part: .gesture, number: nil))
        XCTAssertEqual(picture(2000 + 0x01A0), .mouse(part: .thumbPanel, number: nil))
        XCTAssertEqual(picture(2000 + 0x005B), .mouse(part: nil, number: nil), "a Logitech control with a name but no place in the drawing")
        XCTAssertTrue(picture(6).isUnplaced)
        XCTAssertTrue(picture(2000 + 0x005B).isUnplaced)
        XCTAssertFalse(picture(3).isUnplaced)
        XCTAssertFalse(picture(40, type: .keyboard).isUnplaced)

        // Placed, a numbered button shows its part as a known one does, without its number.
        let answered = ButtonTriggerPicture.make(for: RecordedEvent(type: .mouse, code: 6, modifiers: 0, deviceFilter: nil, mousePart: .gestureButton), mouse: .mxMaster4)
        XCTAssertEqual(answered, .mouse(part: .gesture, number: nil))
        XCTAssertFalse(answered.isUnplaced)
        XCTAssertEqual(ButtonTriggerPicture.number(for: RecordedEvent(type: .mouse, code: 6, modifiers: 0, deviceFilter: nil, mousePart: .gestureButton)), 6,
                       "still the button the Mac knows as Button 6")
    }

    /// An MX Master 4 over Bluetooth as its user set it up: Gesture Navigation on Button 6, a
    /// shortcut on Button 5, a screenshot on the mode shift button.
    func testEveryRowShowsWhereItsButtonIs() throws {
        let custom = "custom::21:\(UInt64(CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue))"
        let bindings = [
            binding(6, SystemShortcut.mouseGestureNavigation.identifier),
            binding(5, custom),
            binding(1001, SystemShortcut.screenshotSelection.identifier),
            binding(40, "copy", modifiers: control | option, type: .keyboard),
        ]
        let pane = makePane(bindings)
        // The mouse's buttons first, the mode shift button with its screenshot; then the
        // numbered buttons and the key.
        XCTAssertEqual(pane.rows.map(\.title), mxMaster4Titles + ["Button 6", "Button 5", "⌃⌥ K"])
        XCTAssertEqual(pane.rows.map(\.picture), [
            .mouse(part: .middle, number: nil), .mouse(part: .modeShift, number: nil), .mouse(part: .gesture, number: nil),
            .mouse(part: .forward, number: nil), .mouse(part: .back, number: nil), .mouse(part: .thumbPanel, number: nil),
            .mouse(part: nil, number: 6), .mouse(part: nil, number: 5), .key,
        ])
        let listed = try rows(of: bindings, in: pane)
        XCTAssertEqual(listed.map(\.explanation), [
            "Hold and move the mouse. Set the directions under Gestures.",
            "An extra button on your mouse.",
            nil,
            nil,
        ])
        XCTAssertEqual(listed[1].accessibilityLabel(), "Button 5, An extra button on your mouse.")
        for row in pane.rows {
            let icon = try XCTUnwrap(row.iconView, row.title)
            XCTAssertEqual(icon.image?.size, ButtonsMouseMiniature.size, row.title)
            XCTAssertEqual(icon.image?.isTemplate, false)
        }

        // Another trigger for the same row ("Use Standard Button"): the picture follows.
        let row = listed[1]
        let old = try XCTUnwrap(pane.binding(for: row.binding.id))
        pane.replaceBinding(ButtonBinding(
            id: old.id, triggerEvent: RecordedEvent(type: .mouse, code: 4, modifiers: option, deviceFilter: nil),
            systemShortcutName: old.systemShortcutName, isEnabled: true, createdAt: old.createdAt
        ))
        XCTAssertTrue(pane.row(for: old.id) === row)
        XCTAssertEqual(row.picture, .mouse(part: .forward, number: nil))
        XCTAssertNil(row.explanation)
    }

    /// A numbered button's row says it is an extra one only when nothing more pressing
    /// is to be said: a problem or what the action needs comes first.
    func testTheExtraButtonNoteComesLast() throws {
        scrollKeys = [ScrollHotkey(type: .mouse, code: 7)]
        let bindings = [binding(5), binding(6, SystemShortcut.scrollDash.identifier), binding(7, "copy"), binding(8, "copy"), binding(2000 + 0x005B, "copy")]
        let pane = makePane(bindings)
        XCTAssertEqual(try rows(of: bindings, in: pane).map(\.explanation), [
            "Choose what this button does.",
            "Works while you hold the button.",
            "Also set under Scrolling\u{A0}›\u{A0}While\u{A0}you\u{A0}hold\u{A0}a\u{A0}key.",
            "An extra button on your mouse.",
            nil,
        ])
    }

    /// A row's picture of an MX Master is the view its part lights in: the mouse upright,
    /// seen from above, for the buttons and the wheel; lying across, seen from its thumb
    /// side, for the side buttons, the MX Master 4's gesture button, the thumb panel and the
    /// thumb wheel (the MX Master 3's gesture button is its thumb rest: from above).
    /// Both fit the picture. The plain mouse is always seen from above.
    func testTheRowsPictureIsTheViewItsPartLightsIn() throws {
        let frame = NSRect(origin: .zero, size: ButtonsMouseMiniature.size)
        let side: Set<ButtonsMousePart> = [.back, .forward, .gesture, .thumbPanel]
        for part in ButtonsMousePart.allCases {
            for mouse in [MouseArtworkModel.mxMaster4, .mxMaster3] where mouse.has(part.artworkPart) {
                let body = ButtonsMouseMiniature.bodyPath(of: mouse, lighting: part, in: frame).bounds
                let fromTheSide = side.contains(part) && !(mouse == .mxMaster3 && part == .gesture)
                XCTAssertEqual(body.width > body.height, fromTheSide, "\(mouse) \(part)")
                XCTAssertTrue(frame.contains(body), "\(mouse) \(part): the mouse fits the picture")
                let shape = try XCTUnwrap(ButtonsMouseMiniature.shape(of: part, mouse: mouse, in: frame)).bounds
                XCTAssertTrue(body.insetBy(dx: -1, dy: -1).contains(shape), "\(mouse) \(part) is on the mouse")
            }
            let plain = ButtonsMouseMiniature.bodyPath(of: .generic, lighting: part, in: frame).bounds
            XCTAssertGreaterThan(plain.height, plain.width, "the plain mouse, \(part): from above")
        }
        // A part the MX Master 3 does not have (the thumb panel): from above, nothing lit.
        let missing = ButtonsMouseMiniature.bodyPath(of: .mxMaster3, lighting: .thumbPanel, in: frame).bounds
        XCTAssertGreaterThan(missing.height, missing.width)
        XCTAssertEqual(MouseArtworkModel.mxMaster3.viewpoint(lighting: .thumbWheel), .thumbSide)
        XCTAssertGreaterThan(ButtonsMouseMiniature.bodyPath(of: .mxMaster4, in: frame).bounds.height, frame.height / 2,
                             "nothing lit: from above")
        XCTAssertEqual(MouseArtworkModel.mxMaster4.viewpoint(lighting: .thumbWheel), .thumbSide, "the thumb wheel's row too")
    }

    /// The picture fills the row's part in the accent colour, in light and in dark, and
    /// lights nothing for a button it cannot show.
    func testThePictureFillsTheRowsPartInTheAccentColour() throws {
        let frame = NSRect(origin: .zero, size: ButtonsMouseMiniature.size)
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            // The accent colour as the same drawing gives it back.
            let accent = try pixels(of: nil, appearance: appearance)(NSPoint(x: 12, y: 12))
            let unlit = try pixels(of: .mouse(part: nil, number: nil), appearance: appearance)
            for part in ButtonsMousePart.allCases where MouseArtworkModel.mxMaster4.has(part.artworkPart) {
                let bounds = try XCTUnwrap(ButtonsMouseMiniature.shape(of: part, mouse: .mxMaster4, in: frame)).bounds
                // The thumb panel is not a box: a point well inside it.
                let middle = part == .thumbPanel
                    ? NSPoint(x: bounds.minX + bounds.width * 0.3, y: bounds.midY + bounds.height * 0.25)
                    : NSPoint(x: bounds.midX, y: bounds.midY)
                let lit = try pixels(of: .mouse(part: part, number: nil), appearance: appearance)
                XCTAssertLessThan(distance(lit(middle), accent), 0.03, "\(part) lit in \(name.rawValue)")
                if accent.saturationComponent > 0.3 {
                    XCTAssertGreaterThan(distance(unlit(middle), accent), 0.2, "\(part) not lit in \(name.rawValue)")
                }
                XCTAssertTrue(ButtonsMouseMiniature.bodyPath(of: .mxMaster4, lighting: part, in: frame).contains(middle),
                              "\(part) is on the mouse, in the view that lights it")
            }
        }
    }

    /// The picture drawn at four times its size in sRGB (nil: the accent colour all over);
    /// the colour at a point of the picture (top-left origin, in points).
    private func pixels(of picture: ButtonTriggerPicture?, appearance: NSAppearance) throws -> (NSPoint) -> NSColor {
        let scale = 4
        let size = ButtonsMouseMiniature.size
        let width = Int(size.width) * scale
        let height = Int(size.height) * scale
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        appearance.performAsCurrentDrawingAppearance {
            if let picture {
                ButtonsMouseMiniature.image(for: picture, mouse: .mxMaster4, highlighted: false).draw(in: NSRect(origin: .zero, size: size))
            } else {
                NSColor.controlAccentColor.setFill()
                NSRect(origin: .zero, size: size).fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        let rep = NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage()))
        return { point in
            let color = rep.colorAt(x: Int(point.x * CGFloat(scale)), y: Int(point.y * CGFloat(scale))) ?? .clear
            return color.usingColorSpace(.sRGB) ?? color
        }
    }

    private func distance(_ a: NSColor, _ b: NSColor) -> CGFloat {
        guard let a = a.usingColorSpace(.sRGB), let b = b.usingColorSpace(.sRGB) else { return .infinity }
        return max(abs(a.redComponent - b.redComponent), abs(a.greenComponent - b.greenComponent), abs(a.blueComponent - b.blueComponent))
    }

    /// The card under a button the drawing cannot show: how to find it, and its number by
    /// the mouse; "That's …" when "+" catches a listed button.
    func testTheCardSaysHowToFindAButtonItCannotShow() {
        typealias Content = ButtonsHeaderContent
        let find = "Click + and press buttons on your mouse to find this one."
        // A numbered button can also be said to be a part, at its picture.
        let place = "Click its picture below to say which button it is. Not sure? Click + and press buttons to find it."
        let six = Content.Focus(title: "Button 6", action: "Copy", picture: .mouse(part: nil, number: 6))
        XCTAssertEqual(Content.make(deviceName: "MX Master 4", boundCount: 1, isRecording: false, focus: six),
                       Content(title: "Button 6", subtitle: "Copy", part: nil, hint: place, number: 6))
        var answer = six
        answer.reason = .answer
        XCTAssertEqual(Content.make(deviceName: "MX Master 4", boundCount: 1, isRecording: false, focus: answer),
                       Content(title: "That's Button 6", subtitle: "Copy", part: nil, number: 6))
        let tilt = Content.Focus(title: "Left Tilt button", action: nil, picture: .mouse(part: nil, number: nil))
        XCTAssertEqual(Content.make(deviceName: nil, boundCount: 0, isRecording: false, focus: tilt),
                       Content(title: "Left Tilt button", subtitle: "No action", part: nil, hint: find))
        var recorded = six
        recorded.reason = .recorded
        XCTAssertEqual(Content.make(deviceName: "MX Master 4", boundCount: 1, isRecording: false, focus: recorded),
                       Content(title: "Button 6", subtitle: "Copy", part: nil, number: 6), "just pressed: no need to find it")
        let key = Content.Focus(title: "⌃⌥ K", action: "Copy", picture: .key)
        XCTAssertEqual(Content.make(deviceName: nil, boundCount: 0, isRecording: false, focus: key),
                       Content(title: "⌃⌥ K", subtitle: "Copy", part: nil), "a key needs no finding")
        var back = Content.Focus(title: "Back button", action: "Copy", picture: .mouse(part: .back, number: nil))
        back.reason = .answer
        XCTAssertEqual(Content.make(deviceName: nil, boundCount: 0, isRecording: false, focus: back),
                       Content(title: "That's Back button", subtitle: "Copy", part: .back))

        // In the pane: the selected Button 6, then the mode shift button.
        let sixBinding = binding(6, SystemShortcut.mouseGestureNavigation.identifier)
        let pane = makePane([sixBinding, binding(1001, "copy")])
        pane.list.select(sixBinding.id)
        XCTAssertEqual(pane.headerView.content, Content(title: "Button 6", subtitle: "Gesture Navigation", part: nil, hint: place, number: 6))
        XCTAssertFalse(pane.headerView.hintLabel.isHidden)
        XCTAssertEqual(pane.headerView.hintLabel.stringValue, place)
        XCTAssertEqual(pane.headerView.artwork.badge.number, 6)
        XCTAssertEqual(pane.headerView.artwork.badge.alphaValue, 1)
        XCTAssertNil(pane.headerView.artwork.emphasis)
        XCTAssertEqual(pane.headerView.accessibilityLabel(), "Button 6, Gesture Navigation, \(place)")
        pane.list.select(ButtonsMousePart.modeShift)
        XCTAssertEqual(pane.headerView.content, Content(title: "Mode shift button", subtitle: "Copy", part: .modeShift))
        XCTAssertTrue(pane.headerView.hintLabel.isHidden)
        XCTAssertEqual(pane.headerView.artwork.badge.alphaValue, 0)
        XCTAssertEqual(pane.headerView.artwork.emphasis, .modeShift)
    }

    /// "+" and a listed numbered button: its row flashes and the card answers "That's
    /// Button 6" with its number by the mouse, for as long as a recorded button shows.
    func testPressingAListedNumberedButtonAfterPlusSaysWhichRowItIs() {
        let six = binding(6, SystemShortcut.mouseGestureNavigation.identifier)
        let pane = makePane([binding(3, "copy"), six])
        let recorder = KeyRecorder()
        pane.beginAddingBinding()
        pane.onRecordingStarted(recorder)
        let event = mouseEvent(6)
        XCTAssertFalse(pane.validateRecordedEvent(recorder, event: event))
        pane.onEventRecorded(recorder, didRecordEvent: event, isDuplicate: true)
        XCTAssertEqual(pane.list.selectedID, AnyHashable(six.id))
        XCTAssertEqual(pane.headerView.content, ButtonsHeaderContent(title: "That's Button 6", subtitle: "Gesture Navigation", part: nil, number: 6))
        XCTAssertEqual(pane.headerView.artwork.badge.alphaValue, 1)
        pane.onRecordingStopped(recorder, didRecord: true)
        flush(PreferencesButtonsViewController.recordedPartDuration - 0.5)
        XCTAssertEqual(pane.headerView.content.title, "That's Button 6", "still the answer")
        flush(0.7)
        // Then the card is about the selected row again.
        XCTAssertEqual(pane.headerView.content.title, "Button 6")
        XCTAssertEqual(pane.headerView.content.hint, "Click its picture below to say which button it is. Not sure? Click + and press buttons to find it.")
        XCTAssertEqual(Options.shared.buttons.binding.count, 2)
    }

    // MARK: - Which button is this?

    private func placed(_ code: UInt16, _ part: PlacedMousePart?, modifiers: UInt = 0) -> RecordedEvent {
        return RecordedEvent(type: .mouse, code: code, modifiers: modifiers, deviceFilter: nil, mousePart: part)
    }

    /// The card, every row's picture and "Which Button Is This?" are the connected mouse's,
    /// and follow another mouse connecting. A part the new mouse does not have shows as a
    /// button the drawing cannot show; the stored answer stays.
    func testTheDrawingsFollowTheConnectedMouse() throws {
        let panelAnswer = ButtonBinding(
            triggerEvent: placed(5, .thumbPanel), systemShortcutName: "copy", isEnabled: true
        )
        let panel = binding(2000 + 0x01A0, "copy")
        let bindings = [panel, panelAnswer, binding(6)]
        let pane = makePane(bindings)
        let six = bindings[2].id
        XCTAssertEqual(pane.headerView.artwork.model, .mxMaster4)
        XCTAssertEqual(pane.rows.map(\.mouse), Array(repeating: .mxMaster4, count: 8))
        // The Logitech thumb panel is the thumb panel's row; Button 5, said to be it too, is
        // below.
        XCTAssertEqual(pane.rows.map(\.title), ["Middle button", "Mode shift button", "Gesture button", "Forward button", "Back button",
                                                "Thumb panel", "Thumb panel (button 5)", "Button 6"])
        XCTAssertTrue(pane.row(for: ButtonsMousePart.thumbPanel)?.binding == panel)
        XCTAssertEqual(try rows(of: bindings, in: pane).map(\.picture), [
            .mouse(part: .thumbPanel, number: nil), .mouse(part: .thumbPanel, number: nil), .mouse(part: nil, number: 6),
        ])
        XCTAssertEqual(try XCTUnwrap(pane.placeMenu(for: six)).items.compactMap { ($0.representedObject as? ButtonPlaceChoice)?.part },
                       PlacedMousePart.allCases)

        deviceName = "MX Master 3S"
        NotificationCenter.default.post(name: LogiCenter.mouseStateChanged, object: nil)
        XCTAssertEqual(pane.headerView.artwork.model, .mxMaster3)
        XCTAssertEqual(pane.rows.map(\.mouse), Array(repeating: .mxMaster3, count: 8))
        // The MX Master 3S has no thumb panel: its row goes, the bindings are below.
        XCTAssertEqual(pane.rows.map(\.title), ["Middle button", "Mode shift button", "Forward button", "Back button", "Gesture button",
                                                "Thumb panel", "Thumb panel (button 5)", "Button 6"])
        XCTAssertNil(pane.row(for: ButtonsMousePart.thumbPanel))
        XCTAssertEqual(try rows(of: bindings, in: pane).map(\.picture), [
            .mouse(part: nil, number: nil, notDrawn: .thumbPanel), .mouse(part: nil, number: 5, notDrawn: .thumbPanel), .mouse(part: nil, number: 6),
        ])
        XCTAssertEqual(try XCTUnwrap(pane.placeMenu(for: six)).items.compactMap { ($0.representedObject as? ButtonPlaceChoice)?.part },
                       [.gestureButton, .backButton, .forwardButton, .modeShiftButton, .middleButton])
        pane.list.select(panelAnswer.id)
        XCTAssertEqual(pane.headerView.content.number, 5)
        XCTAssertNil(pane.headerView.artwork.emphasis)
        XCTAssertEqual(Options.shared.buttons.binding[1].triggerEvent.mousePart, .thumbPanel, "the answer is kept")
        XCTAssertEqual(pane.row(for: panelAnswer.id)?.title, "Thumb panel (button 5)")

        deviceName = nil
        NotificationCenter.default.post(name: LogiCenter.sessionChanged, object: nil)
        XCTAssertEqual(pane.headerView.artwork.model, .generic)
        XCTAssertEqual(pane.rows.map(\.title), ["Thumb panel", "Thumb panel (button 5)", "Button 6"], "the plain list")
        XCTAssertTrue(pane.list.groupTitles.isEmpty)
        XCTAssertEqual(try XCTUnwrap(pane.placeMenu(for: six)).items.compactMap { ($0.representedObject as? ButtonPlaceChoice)?.part },
                       [.backButton, .forwardButton, .middleButton])
    }

    /// The card names the mouse the Mouse pane's card names: another mouse with the same
    /// drawing (an MX Master 3 after an MX Master 3S) renames it too.
    func testTheCardFollowsTheShownMousesName() {
        deviceName = "MX Master 3S"
        let pane = makePane([binding(3, "copy")])
        XCTAssertEqual(pane.headerView.content.title, "MX Master 3S")
        XCTAssertEqual(pane.headerView.artwork.model, .mxMaster3)

        deviceName = "MX Master 3"
        NotificationCenter.default.post(name: LogiCenter.mouseStateChanged, object: nil)
        XCTAssertEqual(pane.headerView.content.title, "MX Master 3", "same drawing, another name")
        XCTAssertEqual(pane.headerView.artwork.model, .mxMaster3)

        deviceName = "MX Master 4"
        NotificationCenter.default.post(name: LogiCenter.mouseStateChanged, object: nil)
        XCTAssertEqual(pane.headerView.content.title, "MX Master 4")
        XCTAssertEqual(pane.headerView.artwork.model, .mxMaster4)

        deviceName = nil
        NotificationCenter.default.post(name: LogiCenter.mouseStateChanged, object: nil)
        XCTAssertEqual(pane.headerView.content.title, "Your mouse")
        XCTAssertEqual(pane.headerView.artwork.model, .generic)
        XCTAssertEqual(Options.shared.buttons.binding.count, 1)
    }

    /// A button whose place is known but that the shown mouse does not have (a thumb panel
    /// while an MX Master 3S is connected, a Logitech gesture button on the plain drawing) is
    /// not asked to be found or placed, and its menu keeps the stored answer ticked and
    /// disabled: nothing is lost by accident, and nothing is saved by showing it.
    func testAKnownButtonTheShownMouseLacksIsNotAskedToBeFound() throws {
        let panelAnswer = ButtonBinding(triggerEvent: placed(6, .thumbPanel), systemShortcutName: "copy", isEnabled: true)
        let gesture = binding(1000, "copy")
        deviceName = "MX Master 3S"
        let pane = makePane([panelAnswer, gesture])
        let stored = Options.shared.buttons.binding
        let notHere = "The mouse shown doesn't have this button."
        let panel = try XCTUnwrap(pane.row(for: panelAnswer.id))
        XCTAssertEqual(pane.rows.map(\.title), ["Middle button", "Mode shift button", "Forward button", "Back button", "Gesture button",
                                                "Thumb panel (button 6)"])
        XCTAssertEqual(panel.title, "Thumb panel (button 6)")
        XCTAssertEqual(panel.picture, .mouse(part: nil, number: 6, notDrawn: .thumbPanel))
        XCTAssertFalse(panel.picture.isUnplaced)
        pane.list.select(panel.id)
        XCTAssertEqual(pane.headerView.content.hint, notHere)
        XCTAssertEqual(pane.headerView.content.number, 6)

        let menu = try XCTUnwrap(pane.placeMenu(for: panelAnswer.id))
        let ticked = menu.items.filter { $0.state == .on }
        XCTAssertEqual(ticked.map(\.title), ["Thumb Panel"])
        XCTAssertFalse(try XCTUnwrap(ticked.first).isEnabled, "the stored answer cannot be chosen again here")
        XCTAssertEqual(menu.items.filter { $0.representedObject != nil && !$0.isEnabled }.map(\.title), ["Thumb Panel"])
        XCTAssertEqual(menu.items.last?.title, "Not on This List")
        XCTAssertTrue(try XCTUnwrap(menu.items.last).isEnabled)
        XCTAssertEqual(Options.shared.buttons.binding, stored, "showing it saves nothing")

        // The Logitech gesture button with no Logitech mouse connected: the plain drawing.
        deviceName = nil
        NotificationCenter.default.post(name: LogiCenter.mouseStateChanged, object: nil)
        XCTAssertEqual(pane.headerView.artwork.model, .generic)
        pane.list.select(pane.rowID(forBinding: gesture.id))
        XCTAssertEqual(pane.headerView.content.title, "Gesture button")
        XCTAssertEqual(pane.headerView.content.hint, notHere)
        XCTAssertNil(pane.placeMenu(for: gesture.id), "its place is known: no menu")
        XCTAssertEqual(Options.shared.buttons.binding, stored)
        XCTAssertEqual(Options.shared.buttons.binding.map(\.triggerEvent.mousePart), [.thumbPanel, nil], "the answer is kept")
    }

    /// An MX Master 4 over Bluetooth as its user set it up (the bindings of the Mac the
    /// pane was made on): Gesture Navigation on Button 6, a shortcut on Button 5, a
    /// screenshot on the mode shift button.
    private func ownerBindings() -> [ButtonBinding] {
        let custom = "custom::21:\(UInt64(CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue))"
        return [
            binding(6, SystemShortcut.mouseGestureNavigation.identifier),
            binding(5, custom),
            binding(1001, SystemShortcut.screenshotSelection.identifier),
        ]
    }

    private func sortedJSON(_ bindings: [ButtonBinding]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(bindings)
    }

    /// The menu lists every part an extra button can be, by name, in order; it ticks the
    /// chosen one and marks the ones another button of the list has (still offered). Rows
    /// of the same button number are the button itself. Only a numbered button has it.
    func testWhichButtonIsThisListsThePartsAndMarksTheOnesTaken() throws {
        let list = [
            placed(6, nil),
            placed(5, .thumbPanel),
            RecordedEvent(type: .mouse, code: 1001, modifiers: 0, deviceFilter: nil),
            RecordedEvent(type: .mouse, code: 3, modifiers: option, deviceFilter: nil),
            placed(6, nil, modifiers: option),
            RecordedEvent(type: .keyboard, code: 40, modifiers: control, deviceFilter: nil),
        ]
        let model = try XCTUnwrap(ButtonPlaceMenuModel.make(for: list[0], among: list, mouse: .mxMaster4))
        XCTAssertEqual(model.number, 6)
        XCTAssertEqual(model.items.map(\.part), PlacedMousePart.allCases)
        XCTAssertEqual(model.items.map(\.title), [
            "Gesture Button", "Thumb Panel", "Back Button", "Forward Button", "Mode Shift Button", "Middle Button",
        ])
        XCTAssertEqual(model.items.filter(\.isChosen), [])
        XCTAssertEqual(model.items.map(\.mark), [nil, "Used by button 5", "Already in the list", nil, "Already in the list", nil])

        // From Button 5: its own answer is ticked, not marked.
        let five = try XCTUnwrap(ButtonPlaceMenuModel.make(for: list[1], among: list, mouse: .mxMaster4))
        XCTAssertEqual(five.items.filter(\.isChosen).map(\.part), [.thumbPanel])
        XCTAssertEqual(five.items.map(\.mark), [nil, nil, "Already in the list", nil, "Already in the list", nil])

        // A Logitech gesture button or thumb panel marks its own name.
        let logitech = [placed(6, nil), RecordedEvent(type: .mouse, code: 1000, modifiers: 0, deviceFilter: nil),
                        RecordedEvent(type: .mouse, code: 2000 + 0x01A0, modifiers: 0, deviceFilter: nil),
                        RecordedEvent(type: .mouse, code: 2, modifiers: 0, deviceFilter: nil)]
        XCTAssertEqual(try XCTUnwrap(ButtonPlaceMenuModel.make(for: logitech[0], among: logitech, mouse: .mxMaster4)).items.map(\.mark),
                       ["Already in the list", "Already in the list", nil, nil, nil, "Already in the list"])

        // No menu where the place is known or there is no button.
        for trigger in [
            RecordedEvent(type: .mouse, code: 3, modifiers: 0, deviceFilter: nil),
            RecordedEvent(type: .mouse, code: 0, modifiers: 0, deviceFilter: nil),
            RecordedEvent(type: .mouse, code: 1001, modifiers: 0, deviceFilter: nil),
            RecordedEvent(type: .mouse, code: 2000 + 0x005B, modifiers: 0, deviceFilter: nil),
            RecordedEvent(type: .keyboard, code: 6, modifiers: 0, deviceFilter: nil),
        ] {
            XCTAssertNil(ButtonPlaceMenuModel.make(for: trigger, among: list, mouse: .mxMaster4), "\(trigger)")
        }
    }

    /// The menu as the pane builds it: a section title, each part with its picture, the
    /// chosen one ticked, a mark at the end of a taken one, then "Not on This List" with the
    /// button's number; every item answers to the pane.
    func testThePaneBuildsTheMenuWithPictures() throws {
        let owner = ownerBindings()
        let pane = makePane(owner)
        let six = owner[0].id
        pane.setPlace(of: owner[1].id, to: .thumbPanel)
        let menu = try XCTUnwrap(pane.placeMenu(for: six))
        XCTAssertEqual(menu.items.map(\.title), [
            "Which Button Is This?", "Gesture Button", "Thumb Panel", "Back Button", "Forward Button",
            "Mode Shift Button", "Middle Button", "", "Not on This List",
        ])
        XCTAssertTrue(menu.items[0].isSectionHeader)
        XCTAssertTrue(menu.items[7].isSeparatorItem)
        let answers = menu.items.filter { $0.representedObject != nil }
        XCTAssertEqual(answers.count, 7)
        for item in answers {
            let choice = try XCTUnwrap(item.representedObject as? ButtonPlaceChoice)
            XCTAssertEqual(choice.bindingID, six)
            XCTAssertTrue(item.target === pane, item.title)
            XCTAssertEqual(item.action, #selector(PreferencesButtonsViewController.placeChosen(_:)))
            XCTAssertTrue(item.isEnabled)
            XCTAssertEqual(item.image?.size, ButtonsMouseMiniature.size, item.title)
        }
        XCTAssertEqual(answers.map { ($0.representedObject as? ButtonPlaceChoice)?.part }, PlacedMousePart.allCases + [nil])
        XCTAssertEqual(answers.map(\.state), Array(repeating: NSControl.StateValue.off, count: 7))
        XCTAssertEqual(menu.items.map { $0.badge?.stringValue }, [nil, nil, "Used by button 5", nil, nil, "Already in the list", nil, nil, nil])

        pane.setPlace(of: six, to: .gestureButton)
        let again = try XCTUnwrap(pane.placeMenu(for: six))
        XCTAssertEqual(again.items[1].state, .on, "the answer is ticked")
        XCTAssertEqual(again.items.filter { $0.state == .on }.count, 1)
        XCTAssertNil(pane.placeMenu(for: owner[2].id), "the mode shift button's place is known")
    }

    /// The picture of a numbered button is a button over the row's picture that opens the
    /// menu (and selects the row, so the card shows the button); a right-click on the row
    /// offers the same menu. A known button and a key have neither.
    func testThePictureAndARightClickOpenTheMenu() throws {
        let bindings = ownerBindings() + [binding(40, "copy", modifiers: control | option, type: .keyboard)]
        let pane = makePane(bindings)
        pane.view.layoutSubtreeIfNeeded()
        let listed = try rows(of: bindings, in: pane)
        XCTAssertEqual(listed.map(\.placeButton.isHidden), [false, false, true, true])
        let defaultRow = try XCTUnwrap(pane.row(for: ButtonsMousePart.gesture))
        XCTAssertTrue(defaultRow.placeButton.isHidden, "a button of the mouse without a binding is known")
        let row = listed[1]
        XCTAssertEqual(row.placeButton.toolTip, "Which button is this?")
        XCTAssertEqual(row.placeButton.accessibilityLabel(), "Which button is this?")
        let icon = try XCTUnwrap(row.iconView)
        XCTAssertEqual(row.placeButton.frame, icon.frame.insetBy(dx: -ButtonBindingRow.placeButtonOutset, dy: -ButtonBindingRow.placeButtonOutset))
        let middle = row.convert(NSPoint(x: icon.frame.midX, y: icon.frame.midY), to: row.superview)
        XCTAssertTrue(row.hitTest(middle) === row.placeButton, "the click goes to the picture, not the row")

        row.placeButton.performClick(nil)
        XCTAssertEqual(placeMenus.count, 1)
        XCTAssertTrue(placeMenus.first?.anchor === row.placeButton)
        XCTAssertEqual(placeMenus.first?.menu.items.first?.title, "Which Button Is This?")
        XCTAssertEqual(pane.list.selectedID, row.id)
        XCTAssertEqual(pane.headerView.content.number, 5)

        let rightClick = try XCTUnwrap(NSEvent.mouseEvent(
            with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1
        ))
        let menu = try XCTUnwrap(listed[0].menu(for: rightClick))
        XCTAssertEqual(menu.items.first?.title, "Which Button Is This?")
        XCTAssertEqual(pane.list.selectedID, listed[0].id)
        XCTAssertNil(listed[2].menu(for: rightClick), "the mode shift button")
        XCTAssertNil(listed[3].menu(for: rightClick), "a key")
        XCTAssertNil(defaultRow.menu(for: rightClick), "a button of the mouse without a binding")

        // Placed, it stays a button: the answer can be changed or taken back. Said to be the
        // thumb panel, it is now that button's row.
        pane.setPlace(of: row.binding.id, to: .thumbPanel)
        let panel = try XCTUnwrap(pane.row(for: bindings[1].id))
        XCTAssertEqual(panel.id, AnyHashable(ButtonsMousePart.thumbPanel))
        XCTAssertFalse(panel.placeButton.isHidden)
    }

    /// After the answer the button is named and lit as the part, with its number after the
    /// name, wherever a known button is: the row, its picture, the card, the Gestures pane's
    /// line, and the stored trigger holds the answer. "Not on This List" takes it back.
    func testChoosingAPartNamesAndLightsTheButton() throws {
        let owner = ownerBindings()
        let pane = makePane(owner)
        let six = owner[0].id
        let five = owner[1].id
        let gesture = try XCTUnwrap(pane.placeMenu(for: six)?.items.first { ($0.representedObject as? ButtonPlaceChoice)?.part == .gestureButton })
        pane.placeChosen(gesture)
        let panel = try XCTUnwrap(pane.placeMenu(for: five)?.items.first { ($0.representedObject as? ButtonPlaceChoice)?.part == .thumbPanel })
        pane.placeChosen(panel)

        // They are the rows of those buttons now, nothing is below.
        XCTAssertEqual(pane.rows.map(\.title), ["Middle button", "Mode shift button", "Gesture button (button 6)", "Forward button",
                                                "Back button", "Thumb panel (button 5)"])
        XCTAssertTrue(pane.list.groupTitles.isEmpty)
        let listed = try rows(of: owner, in: pane)
        XCTAssertEqual(listed.map(\.id), [AnyHashable(ButtonsMousePart.gesture), AnyHashable(ButtonsMousePart.thumbPanel),
                                          AnyHashable(ButtonsMousePart.modeShift)])
        XCTAssertEqual(listed.map(\.title), ["Gesture button (button 6)", "Thumb panel (button 5)", "Mode shift button"])
        XCTAssertEqual(listed.map(\.picture), [
            .mouse(part: .gesture, number: nil), .mouse(part: .thumbPanel, number: nil), .mouse(part: .modeShift, number: nil),
        ])
        XCTAssertEqual(listed.map(\.explanation), ["Hold and move the mouse. Set the directions under Gestures.", nil, nil],
                       "a placed button is no longer just an extra one")
        XCTAssertEqual(listed[1].accessibilityLabel(), "Thumb panel (button 5)")

        pane.list.select(pane.rowID(forBinding: six))
        XCTAssertEqual(pane.headerView.content, ButtonsHeaderContent(title: "Gesture button (button 6)", subtitle: "Gesture Navigation", part: .gesture))
        XCTAssertEqual(pane.headerView.artwork.emphasis, .gesture)
        XCTAssertEqual(pane.headerView.artwork.highlights[.gesture]?.alphaValue, 1)
        XCTAssertEqual(pane.headerView.artwork.badge.alphaValue, 0)
        XCTAssertTrue(pane.headerView.hintLabel.isHidden)

        // Stored: the trigger's place, nothing else.
        let stored = Options.shared.buttons.binding
        XCTAssertEqual(stored.map(\.triggerEvent.mousePart), [.gestureButton, .thumbPanel, nil])
        XCTAssertEqual(stored, ownerBindingsWithIDs(of: stored), "the same triggers and actions")

        // The Gestures pane's "Button to hold" line.
        let summary = MouseGestureBindingSummary(bindings: stored, isLogitechCode: { LogiCenter.shared.isLogiCode($0) })
        XCTAssertEqual(summary.buttonTitles, ["Gesture button (button 6)"])
        XCTAssertEqual(summary.gestureButtonExplanation, "Gesture button (button 6).")
        XCTAssertFalse(summary.hasLogitechGestureButton)

        // Modifiers stay in front.
        XCTAssertEqual(ButtonTriggerNaming.title(for: placed(6, .gestureButton, modifiers: option | command)), "⌥⌘ Gesture button (button 6)")

        // "Not on This List": Button 6 again, below, still selected, and the stored trigger
        // as it was.
        let none = try XCTUnwrap(pane.placeMenu(for: six)?.items.last)
        XCTAssertEqual(none.title, "Not on This List")
        pane.placeChosen(none)
        let back = try XCTUnwrap(pane.row(for: six))
        XCTAssertEqual(back.id, AnyHashable(six))
        XCTAssertEqual(pane.list.selectedID, AnyHashable(six), "the selection goes with it")
        XCTAssertEqual(back.title, "Button 6")
        XCTAssertEqual(back.picture, .mouse(part: nil, number: 6))
        XCTAssertEqual(pane.row(for: ButtonsMousePart.gesture)?.isDefault, true)
        XCTAssertEqual(pane.headerView.content.number, 6)
        XCTAssertEqual(pane.headerView.content.hint, "Click its picture below to say which button it is. Not sure? Click + and press buttons to find it.")
        XCTAssertNil(Options.shared.buttons.binding[0].triggerEvent.mousePart)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: try sortedJSON(Options.shared.buttons.binding)) as? [[String: Any]])
        let trigger = try XCTUnwrap(object[0]["triggerEvent"] as? [String: Any])
        XCTAssertEqual(Set(trigger.keys), ["type", "code", "modifiers"])
    }

    /// Those bindings (`ownerBindings`) with the ids and dates of `stored`.
    private func ownerBindingsWithIDs(of stored: [ButtonBinding]) -> [ButtonBinding] {
        return zip(ownerBindings(), stored).map { owner, stored in
            ButtonBinding(id: stored.id, triggerEvent: owner.triggerEvent, systemShortcutName: owner.systemShortcutName,
                          isEnabled: owner.isEnabled, createdAt: stored.createdAt)
        }
    }

    /// "+" and a placed button: the card answers with its part lit, no number.
    func testPressingAPlacedButtonAfterPlusSaysItsPart() {
        let owner = ownerBindings()
        let pane = makePane(owner)
        pane.setPlace(of: owner[0].id, to: .gestureButton)
        let recorder = KeyRecorder()
        pane.beginAddingBinding()
        pane.onRecordingStarted(recorder)
        pane.onEventRecorded(recorder, didRecordEvent: mouseEvent(6), isDuplicate: true)
        XCTAssertEqual(pane.headerView.content, ButtonsHeaderContent(title: "That's Gesture button (button 6)", subtitle: "Gesture Navigation", part: .gesture))
        XCTAssertEqual(pane.headerView.artwork.emphasis, .gesture)
        XCTAssertEqual(pane.headerView.artwork.badge.alphaValue, 0)
        pane.onRecordingStopped(recorder, didRecord: true)
        XCTAssertEqual(Options.shared.buttons.binding.count, 3)
    }

    /// Rows of one button number are one button with other modifiers: an answer for one is
    /// the answer for all, a row added later for that number gets it, and a row removed and
    /// put back with Undo keeps it.
    func testAnAnswerHoldsForEveryRowOfTheButtonNumber() throws {
        let bindings = [
            binding(6, SystemShortcut.mouseGestureNavigation.identifier),
            binding(6, "copy", modifiers: option),
            binding(5, "copy"),
            binding(3, "paste"),
        ]
        let pane = makePane(bindings)
        pane.setPlace(of: bindings[1].id, to: .gestureButton)
        XCTAssertEqual(try rows(of: bindings, in: pane).map(\.title), ["Gesture button (button 6)", "⌥ Gesture button (button 6)", "Button 5", "Back button"])
        XCTAssertEqual(pane.row(for: bindings[0].id)?.id, AnyHashable(ButtonsMousePart.gesture), "now the gesture button's row")
        XCTAssertEqual(Options.shared.buttons.binding.map(\.triggerEvent.mousePart), [.gestureButton, .gestureButton, nil, nil])

        // "+" catches ⌘ Button 6: the card already calls it by its part, and so does its row.
        let recorder = KeyRecorder()
        pane.beginAddingBinding()
        pane.onRecordingStarted(recorder)
        XCTAssertTrue(pane.validateRecordedEvent(recorder, event: mouseEvent(6, modifiers: .maskCommand)))
        pane.onEventRecorded(recorder, didRecordEvent: mouseEvent(6, modifiers: .maskCommand), isDuplicate: false)
        XCTAssertEqual(pane.headerView.content.title, "⌘ Gesture button (button 6)")
        XCTAssertEqual(pane.headerView.content.part, .gesture)
        pane.onRecordingStopped(recorder, didRecord: true)
        let added = try XCTUnwrap(pane.rows.last)
        XCTAssertEqual(added.title, "⌘ Gesture button (button 6)")
        XCTAssertEqual(Options.shared.buttons.binding.last?.triggerEvent.mousePart, .gestureButton)

        // Removed and put back: its part comes back with it.
        let undo = try XCTUnwrap(pane.paneUndoManager)
        undo.groupsByEvent = false
        let removed = bindings[1].id
        undo.beginUndoGrouping()
        pane.removeBinding(id: removed)
        undo.endUndoGrouping()
        undo.undo()
        XCTAssertEqual(pane.binding(for: removed)?.triggerEvent.mousePart, .gestureButton)
        XCTAssertEqual(pane.row(for: removed)?.title, "⌥ Gesture button (button 6)")

        // The last row of its number, removed and put back alone, keeps its part too.
        let five = bindings[2].id
        pane.setPlace(of: five, to: .thumbPanel)
        undo.beginUndoGrouping()
        pane.removeBinding(id: five)
        undo.endUndoGrouping()
        undo.undo()
        XCTAssertEqual(pane.binding(for: five)?.triggerEvent.mousePart, .thumbPanel)

        // "Not on This List" from any row clears the whole button number.
        pane.setPlace(of: added.binding.id, to: nil)
        XCTAssertEqual(Options.shared.buttons.binding.filter { $0.triggerEvent.code == 6 }.map(\.triggerEvent.mousePart), [nil, nil, nil])
        XCTAssertEqual(Options.shared.buttons.binding.first { $0.id == five }?.triggerEvent.mousePart, .thumbPanel, "another number keeps its own")
    }

    /// Stored bindings stay byte for byte as they were until an answer is chosen: loading,
    /// selecting, opening the menu and answering what is already so write nothing new.
    func testBindingsStayAsTheyWereUntilAnAnswerIsChosen() throws {
        let owner = ownerBindings()
        let before = try sortedJSON(owner)
        let pane = makePane(owner)
        let listed = try rows(of: owner, in: pane)
        pane.list.select(listed[0].id)
        _ = pane.placeMenu(for: owner[0].id)
        pane.showPlaceMenu(for: owner[1].id, from: listed[1].placeButton)
        pane.setPlace(of: owner[0].id, to: nil)
        pane.setPlace(of: owner[2].id, to: .backButton)
        // The rows of the mouse's buttons without a binding: shown, selected, pointed at.
        for part in [ButtonsMousePart.middle, .gesture, .thumbPanel] {
            pane.list.select(part)
            _ = pane.row(for: part)?.placeMenu?()
        }
        XCTAssertEqual(try sortedJSON(Options.shared.buttons.binding), before)
        pane.reload()
        XCTAssertEqual(try sortedJSON(Options.shared.buttons.binding), before)
        XCTAssertEqual(try rows(of: owner, in: pane).map(\.title), ["Button 6", "Button 5", "Mode shift button"], "a known button cannot be placed")
    }

    /// The answer is for the eyes only: the trigger matches and runs as before.
    func testAnAnswerChangesNothingButWhatThePaneShows() {
        let plain = RecordedEvent(type: .mouse, code: 6, modifiers: option, deviceFilter: nil)
        let answered = plain.placed(at: .gestureButton)
        XCTAssertEqual(answered, plain)
        for event in [mouseEvent(6), mouseEvent(6, modifiers: .maskAlternate), mouseEvent(6, modifiers: [.maskAlternate, .maskCommand]), mouseEvent(5, modifiers: .maskAlternate)] {
            XCTAssertEqual(answered.matchPriority(for: event), plain.matchPriority(for: event))
        }
        let binding = ButtonBinding(triggerEvent: plain, systemShortcutName: "copy")
        XCTAssertEqual(binding.replacingTriggerEvent(answered), binding)
        XCTAssertNil(answered.placed(at: nil).mousePart)
    }

    // MARK: - Rows

    func testRowsSayWhatTheActionNeeds() throws {
        let bindings = [
            binding(3, SystemShortcut.mouseGestureNavigation.identifier),
            binding(4, SystemShortcut.scrollToggle.identifier),
            binding(5),
            binding(6, "copy"),
        ]
        let pane = makePane(bindings)
        let listed = try rows(of: bindings, in: pane)
        XCTAssertEqual(listed.map(\.title), ["Back button", "Forward button", "Button 5", "Button 6"])
        XCTAssertEqual(listed.map(\.explanation), [
            "Hold and move the mouse. Set the directions under Gestures.",
            "Works while you hold the button.",
            "Choose what this button does.",
            "An extra button on your mouse.",
        ])
        pane.view.layoutSubtreeIfNeeded()
        for row in pane.rows {
            XCTAssertTrue(row.infoButton.isHidden, row.title)
            XCTAssertEqual(row.explanationLabel.textColor, PreferencesGroupedForm.explanationColor(enabled: true))
            XCTAssertTrue(row.pullDown.pullsDown)
            XCTAssertTrue(row.accessory === row.pullDown)
            let width = row.pullDown.alignmentRect(forFrame: row.pullDown.frame).width
            XCTAssertEqual(width, 240, accuracy: 0.5)
        }
        XCTAssertEqual(listed[2].accessibilityLabel(), "Button 5, Choose what this button does.")
    }

    func testProblemNotesAreOrangeWithADetailsButton() throws {
        captureStatus = [1000: .conflict(.foreignDivert), 1001: .contended, 1002: .bleHIDPPUnstable, 1006: .standardMouseAliasAvailable]
        scrollKeys = [ScrollHotkey(type: .mouse, code: 5), ScrollHotkey(type: .keyboard, code: 4)]
        let bindings = [
            binding(1000, "copy"), binding(1001, "copy"), binding(1002, "copy"), binding(1006, "copy"),
            binding(5, "copy", modifiers: option), binding(4, "copy"),
        ]
        let pane = makePane(bindings)
        let listed = try rows(of: bindings, in: pane)
        XCTAssertEqual(listed.map(\.explanation), [
            "Another app may use this button.",
            "Logi Options+ keeps taking this button over.",
            "May stop working while Logi Options+ runs.",
            "Can use the standard Back button instead.",
            "Also set under Scrolling\u{A0}›\u{A0}While\u{A0}you\u{A0}hold\u{A0}a\u{A0}key.",
            nil,
        ])
        XCTAssertEqual(listed.map { $0.note?.tone }, [.problem, .problem, .problem, .hint, .problem, nil])
        for row in listed.prefix(5) {
            XCTAssertFalse(row.infoButton.isHidden, row.title)
            XCTAssertEqual(row.infoButton.accessibilityLabel(), "More Info")
        }
        // An orange warning sign before the text, a light bulb in the accent colour before
        // the alias hint; the text itself in the colour of any explanation (orange or
        // accent-coloured text is too faint to read on a light box).
        let conflict = listed[0].explanationLabel.attributedStringValue
        XCTAssertTrue(conflict.string.hasSuffix("Another app may use this button."))
        XCTAssertTrue(conflict.containsAttachments(in: NSRange(location: 0, length: conflict.length)))
        XCTAssertEqual(conflict.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .systemOrange)
        XCTAssertEqual(conflict.attribute(.foregroundColor, at: conflict.length - 1, effectiveRange: nil) as? NSColor,
                       PreferencesGroupedForm.explanationColor(enabled: true))
        let hint = listed[3].explanationLabel.attributedStringValue
        XCTAssertEqual(hint.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .controlAccentColor)
        XCTAssertEqual(hint.attribute(.foregroundColor, at: hint.length - 1, effectiveRange: nil) as? NSColor,
                       PreferencesGroupedForm.explanationColor(enabled: true))
        XCTAssertEqual(listed[0].accessibilityLabel(), "Gesture button, Another app may use this button.")

        // The ⓘ explains, in plain words.
        let popover = try XCTUnwrap(pane.showProblem(of: listed[0], relativeTo: listed[0].infoButton))
        _ = popover.view
        XCTAssertEqual(popover.titleLabel.stringValue, "Another app may be using this button")
        XCTAssertFalse(popover.detailLabel.stringValue.contains("HID++"))
        XCTAssertNil(popover.standardButton)
        XCTAssertEqual(pane.problemPopover?.behavior, .transient)
        let scrollKey = try XCTUnwrap(pane.showProblem(of: listed[4], relativeTo: listed[4].infoButton))
        _ = scrollKey.view
        XCTAssertEqual(scrollKey.titleLabel.stringValue, "Also a key under Scrolling")
        XCTAssertEqual(
            scrollKey.detailLabel.stringValue,
            "This button is also set under Scrolling › While you hold a key, so holding it does both. Clear one of the two."
        )
        // The explanation is what the popover is for: in the label colour, not the muted one.
        XCTAssertEqual(scrollKey.detailLabel.textColor, .labelColor)
        XCTAssertEqual(popover.detailLabel.textColor, .labelColor)
    }

    /// A key that has Gesture Navigation from before does nothing with it (the input side
    /// passes it through): its row says so as a problem, not "Hold and move the mouse", and
    /// the ⓘ says why. A mouse button with it keeps the plain note. Nothing is saved.
    func testAKeyWithGestureNavigationSaysItCannotRunIt() throws {
        deviceName = nil
        let gesture = SystemShortcut.mouseGestureNavigation.identifier
        let pane = makePane([
            binding(41, gesture, modifiers: UInt(CGEventFlags.maskCommand.rawValue), type: .keyboard),
            binding(3, gesture),
        ])
        let stored = Options.shared.buttons.binding
        XCTAssertEqual(pane.rows.map(\.explanation), [
            "A key cannot run Gesture Navigation. Choose a mouse button.",
            "Hold and move the mouse. Set the directions under Gestures.",
        ])
        XCTAssertEqual(pane.rows.map { $0.note?.tone }, [.problem, .plain])
        XCTAssertFalse(pane.rows[0].infoButton.isHidden)
        XCTAssertTrue(pane.rows[1].infoButton.isHidden)
        let line = pane.rows[0].explanationLabel.attributedStringValue
        XCTAssertTrue(line.containsAttachments(in: NSRange(location: 0, length: line.length)), "after the warning sign")
        XCTAssertEqual(line.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .systemOrange)
        XCTAssertEqual(pane.rows[0].accessibilityLabel(), "\(pane.rows[0].title), A key cannot run Gesture Navigation. Choose a mouse button.")

        let popover = try XCTUnwrap(pane.showProblem(of: pane.rows[0], relativeTo: pane.rows[0].infoButton))
        _ = popover.view
        XCTAssertEqual(popover.titleLabel.stringValue, "Gestures need a mouse button")
        XCTAssertEqual(popover.detailLabel.stringValue, "A key cannot be held while the mouse moves.")
        XCTAssertNil(popover.standardButton)
        pane.problemPopover?.close()
        XCTAssertEqual(Options.shared.buttons.binding, stored)
    }

    /// The ⓘ sits on the title line just before the pull-down, and the note under the title
    /// runs on below it: no problem takes more than two lines.
    func testProblemNotesRunUnderTheInfoButtonInTwoLinesAtMost() throws {
        captureStatus = [1000: .conflict(.foreignDivert), 1001: .contended, 1002: .bleHIDPPUnstable, 1006: .standardMouseAliasAvailable]
        scrollKeys = [ScrollHotkey(type: .mouse, code: 5)]
        let bindings = [
            binding(1000, "copy"), binding(1001, "copy"), binding(1002, "copy"), binding(1006, "copy"), binding(5, "copy"),
        ]
        let pane = makePane(bindings)
        pane.view.layoutSubtreeIfNeeded()
        let oneLine = NSTextField(labelWithString: "Xg")
        oneLine.font = PreferencesGroupedForm.explanationFont
        let lineHeight = oneLine.fittingSize.height
        // Right of the row's picture, left of the pull-down.
        let column = PreferencesButtonsViewController.boxWidth - 2 * PreferencesGroupedForm.rowHorizontalInset
            - PreferencesListRow.imageIconSize - PreferencesListRow.iconSpacing
            - ButtonActionPullDown.width - PreferencesGroupedForm.controlSpacing
        for row in try rows(of: bindings, in: pane) {
            XCTAssertTrue(row.accessory === row.pullDown, row.title)
            XCTAssertFalse(row.infoButton.isHidden, row.title)
            let info = row.infoButton.alignmentRect(forFrame: row.infoButton.frame)
            let pullDown = row.pullDown.alignmentRect(forFrame: row.pullDown.frame)
            XCTAssertEqual(info.maxX, pullDown.minX - ButtonBindingRow.infoSpacing, accuracy: 0.5, row.title)
            XCTAssertEqual(info.midY, pullDown.midY, accuracy: 1, row.title)
            XCTAssertLessThanOrEqual(row.titleLabel.frame.maxX, info.minX, row.title)
            XCTAssertEqual(row.explanationLabel.preferredMaxLayoutWidth, column, accuracy: 0.5, row.title)
            XCTAssertLessThanOrEqual(row.explanationLabel.frame.height, 2 * lineHeight + 1, row.title)
        }
        // Without a problem the ⓘ leaves the title its room.
        let plain = makePane([binding(3, "copy")])
        plain.view.layoutSubtreeIfNeeded()
        XCTAssertTrue(try XCTUnwrap(plain.row(for: ButtonsMousePart.back)).infoButton.isHidden)
    }

    func testUseStandardButtonTurnsTheLogitechButtonIntoTheStandardOne() throws {
        captureStatus = [1006: .standardMouseAliasAvailable]
        let pane = makePane([binding(1006, SystemShortcut.navigateBack.identifier)])
        let row = try XCTUnwrap(pane.row(for: ButtonsMousePart.back))
        let popover = try XCTUnwrap(pane.showProblem(of: row, relativeTo: row.infoButton))
        _ = popover.view
        let button = try XCTUnwrap(popover.standardButton)
        XCTAssertEqual(button.title, "Use Standard Button")

        button.performClick(nil)

        let stored = try XCTUnwrap(Options.shared.buttons.binding.first)
        XCTAssertEqual(stored.triggerEvent.code, 3)
        XCTAssertEqual(stored.systemShortcutName, SystemShortcut.navigateBack.identifier)
        XCTAssertEqual(stored.id, row.binding.id)
        XCTAssertTrue(pane.row(for: ButtonsMousePart.back) === row, "still the Back button's row")
        XCTAssertEqual(row.title, "Back button")
        XCTAssertNil(row.note, "no hint any more")
    }

    func testBindingsWithoutAnyProblemStayQuietForKeys() {
        deviceName = nil
        captureStatus = [40: .conflict(.foreignDivert)]
        let pane = makePane([binding(40, "copy", modifiers: control, type: .keyboard)])
        XCTAssertNil(pane.rows.first?.note, "a key never asks the mouse")
        XCTAssertEqual(pane.rows.first?.title, "⌃ K")
    }

    // MARK: - Changing an action

    /// On the plain list; a button of an MX Master has "Default" instead of "No Action"
    /// (`testADefaultRowStoresItsBindingWhenItGetsAnAction`).
    func testChoosingAnActionSavesItAndUpdatesTheRowInPlace() throws {
        deviceName = nil
        let pane = makePane([binding(3)])
        let row = try XCTUnwrap(pane.rows.first)
        let pullDown = row.pullDown
        let menu = try XCTUnwrap(pullDown.menu)
        let item = try XCTUnwrap(menu.items.first {
            ($0.representedObject as? SystemShortcut.Shortcut)?.identifier == SystemShortcut.mouseGestureNavigation.identifier
        })

        pullDown.shortcutSelected(item)

        let stored = try XCTUnwrap(Options.shared.buttons.binding.first)
        XCTAssertEqual(stored.systemShortcutName, SystemShortcut.mouseGestureNavigation.identifier)
        XCTAssertTrue(stored.isEnabled)
        XCTAssertTrue(pane.rows.first === row, "the row stays, and keeps the keyboard focus")
        XCTAssertTrue(row.pullDown.menu === menu)
        XCTAssertEqual(row.explanation, "Hold and move the mouse. Set the directions under Gestures.")
        XCTAssertEqual(pullDown.gestureSettingsItem?.isHidden, false)

        let showSettings = try XCTUnwrap(pullDown.gestureSettingsItem)
        pullDown.shortcutSelected(showSettings)
        XCTAssertEqual(shownPanes, [GesturesPreferencesViewController.tabIdentifier])

        let noAction = menu.items[2]
        XCTAssertEqual(noAction.title, "No Action")
        pullDown.shortcutSelected(noAction)
        XCTAssertEqual(Options.shared.buttons.binding.first?.systemShortcutName, "")
        XCTAssertEqual(Options.shared.buttons.binding.first?.isEnabled, false)
        XCTAssertEqual(row.explanation, "Choose what this button does.")
    }

    func testReturnOpensTheSelectedRowsMenu() throws {
        let pane = makePane([binding(3, "copy")])
        pane.list.select(pane.rows[0].id)
        let returnKey = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36
        ))
        pane.list.keyDown(with: returnKey)
        XCTAssertEqual(openedMenus.count, 1)
        XCTAssertTrue(openedMenus.first === pane.rows[0].pullDown)
    }

    // MARK: - Adding

    func testPlusRecordsAButtonThatIsAddedSelectedAndItsMenuOpens() throws {
        let pane = makePane([binding(3, "copy")])
        pane.list.addButton.performClick(nil)
        XCTAssertEqual(anchors.count, 1)
        XCTAssertTrue(anchors.first === pane.list.addButton, "the recorder hangs on +")

        let recorder = KeyRecorder()
        pane.onRecordingStarted(recorder)
        XCTAssertTrue(pane.isRecording)
        XCTAssertEqual(pane.headerView.content.title, "Press a button")
        XCTAssertEqual(pane.headerView.content.subtitle, "Or a key with ⌘, ⌥, ⌃ or ⇧.\nPress Esc to cancel.")
        XCTAssertNil(pane.headerView.artwork.emphasis)

        let event = mouseEvent(4, modifiers: .maskAlternate)
        XCTAssertTrue(pane.validateRecordedEvent(recorder, event: event))
        pane.onEventRecorded(recorder, didRecordEvent: event, isDuplicate: false)
        // The card shows the button at once; the row comes when the recorder closes.
        XCTAssertEqual(pane.headerView.content, ButtonsHeaderContent(title: "⌥ Forward button", subtitle: "No action", part: .forward))
        XCTAssertEqual(Options.shared.buttons.binding.count, 1)

        pane.onRecordingStopped(recorder, didRecord: true)
        let stored = Options.shared.buttons.binding
        XCTAssertEqual(stored.count, 2)
        let added = try XCTUnwrap(stored.last)
        XCTAssertEqual(added.triggerEvent, RecordedEvent(type: .mouse, code: 4, modifiers: option, deviceFilter: nil))
        XCTAssertNil(added.triggerEvent.deviceFilter, "no device limit")
        XCTAssertEqual(added.systemShortcutName, "")
        XCTAssertFalse(added.isEnabled)
        XCTAssertEqual(pane.list.selectedID, AnyHashable(added.id))
        XCTAssertEqual(pane.rows.last?.title, "⌥ Forward button")
        XCTAssertTrue(openedMenus.isEmpty, "the menu opens after the recorder has gone")

        flush()
        XCTAssertEqual(openedMenus.count, 1)
        XCTAssertTrue(openedMenus.first === pane.rows.last?.pullDown)
        // The part just recorded stays lit for a moment, whatever is selected.
        pane.list.select(ButtonsMousePart.back)
        XCTAssertEqual(pane.headerView.artwork.emphasis, .forward)
        flush(PreferencesButtonsViewController.recordedPartDuration + 0.1)
        XCTAssertEqual(pane.headerView.artwork.emphasis, .back)
    }

    func testRecordingADuplicateFlashesTheRowItHas() {
        let pane = makePane([binding(3, "copy"), binding(4, "paste")])
        let recorder = KeyRecorder()
        pane.beginAddingBinding()
        pane.onRecordingStarted(recorder)
        let event = mouseEvent(3)
        XCTAssertFalse(pane.validateRecordedEvent(recorder, event: event), "the recorder says Duplicate key")
        pane.onEventRecorded(recorder, didRecordEvent: event, isDuplicate: true)
        XCTAssertEqual(pane.list.selectedID, AnyHashable(ButtonsMousePart.back))
        XCTAssertEqual(pane.headerView.content, ButtonsHeaderContent(title: "That's Back button", subtitle: "Copy", part: .back))
        XCTAssertEqual(pane.headerView.artwork.emphasis, .back)
        pane.onRecordingStopped(recorder, didRecord: true)
        flush()
        XCTAssertEqual(Options.shared.buttons.binding.count, 2)
        XCTAssertTrue(openedMenus.isEmpty)
    }

    /// The recorder gives more time while a modifier is held: the pane waits for the
    /// recorder however long it takes, and "Set Up…"'s Gesture Navigation waits with it.
    /// (The pane once ended the recording itself, a second after the recorder's timeout.
    /// The recorder's own `timeout` is the only place that time can be read from, so a
    /// short one here shows the same in 1.5 s; the test used to wait 11.5 s.)
    func testTheRecordingLastsUntilTheRecorderEndsAndKeepsTheActionOfSetUp() throws {
        let pane = makePane()
        let recorder = KeyRecorder()
        XCTAssertEqual(recorder.timeout, 10, "the app's own")
        recorder.timeout = 0.25
        pane.beginAddingBinding(action: SystemShortcut.mouseGestureNavigation)
        pane.onRecordingStarted(recorder)

        flush(recorder.timeout + 1.25)
        XCTAssertTrue(pane.isRecording, "still recording: only the recorder ends it")
        XCTAssertTrue(pane.isRecorderOpen)
        XCTAssertEqual(pane.headerView.content.title, "Press a button")
        XCTAssertEqual(pane.pendingAction?.identifier, SystemShortcut.mouseGestureNavigation.identifier)

        pane.beginAddingBinding()
        XCTAssertEqual(anchors.count, 1, "+ does not start a second recording meanwhile")

        let event = mouseEvent(3, modifiers: .maskCommand)
        pane.onEventRecorded(recorder, didRecordEvent: event, isDuplicate: false)
        XCTAssertEqual(pane.headerView.content.subtitle, "Gesture Navigation")
        pane.beginAddingBinding()
        XCTAssertEqual(anchors.count, 1, "nor while the recorder shows what it caught")
        XCTAssertEqual(pane.pendingAction?.identifier, SystemShortcut.mouseGestureNavigation.identifier)

        pane.onRecordingStopped(recorder, didRecord: true)
        XCTAssertFalse(pane.isRecorderOpen)
        let added = try XCTUnwrap(Options.shared.buttons.binding.first)
        XCTAssertEqual(added.triggerEvent, RecordedEvent(type: .mouse, code: 3, modifiers: command, deviceFilter: nil))
        XCTAssertEqual(added.systemShortcutName, SystemShortcut.mouseGestureNavigation.identifier)
        XCTAssertTrue(added.isEnabled)
        XCTAssertNil(pane.pendingAction)
    }

    /// Gesture Navigation is held while the mouse moves: a key cannot be the gesture button.
    /// Gestures › Set Up… refuses one, adds nothing and says why; a mouse button still works.
    func testSetUpRefusesAKeyAsTheGestureButton() {
        let pane = makePane()
        let recorder = KeyRecorder()
        let key = InputEvent(type: .keyboard, code: 40, modifiers: .maskCommand, phase: .down, source: .hidPP, device: nil)

        pane.beginAddingBinding(action: SystemShortcut.mouseGestureNavigation)
        pane.onRecordingStarted(recorder)
        XCTAssertEqual(
            pane.headerView.content.subtitle,
            "The mouse button you will hold for gestures.\nPress Esc to cancel.",
            "no \"or a key\" while the gesture button is set up"
        )
        recorder.delegate = pane
        XCTAssertEqual(recorder.waitingHint(for: .combination), "Press a mouse button", "the popover asks for a mouse button only")
        XCTAssertFalse(pane.validateRecordedEvent(recorder, event: key), "refused")
        XCTAssertEqual(pane.refusalHint(recorder, event: key), "Gestures need a mouse button", "not \"Duplicate key\"")
        pane.onEventRecorded(recorder, didRecordEvent: key, isDuplicate: true)
        XCTAssertEqual(pane.headerView.content.title, "Gestures need a mouse button")
        XCTAssertEqual(pane.headerView.content.subtitle, "A key cannot be held while the mouse moves.")
        pane.onRecordingStopped(recorder, didRecord: true)
        flush()
        XCTAssertTrue(Options.shared.buttons.binding.isEmpty, "nothing was added")

        // "+" on its own still takes a key, and says so.
        pane.beginAddingBinding()
        pane.onRecordingStarted(recorder)
        XCTAssertEqual(pane.headerView.content.subtitle, "Or a key with ⌘, ⌥, ⌃ or ⇧.\nPress Esc to cancel.")
        XCTAssertNil(pane.waitingHint(recorder, mode: .combination))
        XCTAssertEqual(recorder.waitingHint(for: .combination), "Press a mouse button,\nor a key with ⌘, ⌥, ⌃ or ⇧")
        XCTAssertTrue(pane.validateRecordedEvent(recorder, event: key))
        XCTAssertNil(pane.refusalHint(recorder, event: key))
        pane.onRecordingStopped(recorder, didRecord: false)

        // A listed button refused while the gesture button is set up is a duplicate.
        let listed = makePane([binding(4, "copy")])
        listed.beginAddingBinding(action: SystemShortcut.mouseGestureNavigation)
        listed.onRecordingStarted(recorder)
        XCTAssertFalse(listed.validateRecordedEvent(recorder, event: mouseEvent(4)))
        XCTAssertNil(listed.refusalHint(recorder, event: mouseEvent(4)), "\"Duplicate key\"")
        listed.onRecordingStopped(recorder, didRecord: false)
    }

    /// A key is not offered Gesture Navigation in its menu; a mouse button is. A key that
    /// has it from before keeps the item, so the menu shows what is set.
    func testAKeyIsNotOfferedGestureNavigation() throws {
        deviceName = nil
        let gesture = SystemShortcut.mouseGestureNavigation.identifier
        let pane = makePane([
            binding(3, "copy"),
            binding(40, "copy", modifiers: UInt(CGEventFlags.maskCommand.rawValue), type: .keyboard),
            binding(41, gesture, modifiers: UInt(CGEventFlags.maskCommand.rawValue), type: .keyboard),
        ])
        let rows = pane.rows
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(try XCTUnwrap(rows[0].pullDown.gestureNavigationItem).isHidden, false, "a mouse button")
        XCTAssertEqual(try XCTUnwrap(rows[1].pullDown.gestureNavigationItem).isHidden, true, "a key")
        XCTAssertEqual(try XCTUnwrap(rows[2].pullDown.gestureNavigationItem).isHidden, false, "a key that has it already")
    }

    /// "Set Up…" and a button that is in the list without an action: it gets Gesture
    /// Navigation. One with an action keeps it and only flashes.
    func testSetUpGivesAListedButtonWithoutAnActionGestureNavigation() throws {
        let unbound = binding(3)
        let bound = binding(4, "copy")
        let pane = makePane([unbound, bound])
        let recorder = KeyRecorder()

        pane.beginAddingBinding(action: SystemShortcut.mouseGestureNavigation)
        pane.onRecordingStarted(recorder)
        XCTAssertTrue(pane.validateRecordedEvent(recorder, event: mouseEvent(3)), "not a duplicate: it takes the action")
        pane.onEventRecorded(recorder, didRecordEvent: mouseEvent(3), isDuplicate: false)
        XCTAssertEqual(pane.headerView.content, ButtonsHeaderContent(title: "Back button", subtitle: "Gesture Navigation", part: .back))
        pane.onRecordingStopped(recorder, didRecord: true)
        flush()
        XCTAssertEqual(Options.shared.buttons.binding.count, 2)
        let updated = try XCTUnwrap(Options.shared.buttons.binding.first)
        XCTAssertEqual(updated.id, unbound.id, "the same binding")
        XCTAssertEqual(updated.systemShortcutName, SystemShortcut.mouseGestureNavigation.identifier)
        XCTAssertTrue(updated.isEnabled)
        XCTAssertEqual(pane.list.selectedID, AnyHashable(ButtonsMousePart.back))
        XCTAssertEqual(pane.row(for: unbound.id)?.explanation, "Hold and move the mouse. Set the directions under Gestures.")
        XCTAssertTrue(openedMenus.isEmpty)

        pane.beginAddingBinding(action: SystemShortcut.mouseGestureNavigation)
        pane.onRecordingStarted(recorder)
        XCTAssertFalse(pane.validateRecordedEvent(recorder, event: mouseEvent(4)), "a duplicate: it has an action")
        pane.onEventRecorded(recorder, didRecordEvent: mouseEvent(4), isDuplicate: true)
        pane.onRecordingStopped(recorder, didRecord: true)
        XCTAssertEqual(Options.shared.buttons.binding.last?.systemShortcutName, "copy", "its own action stays")
        XCTAssertEqual(pane.list.selectedID, AnyHashable(ButtonsMousePart.forward))

        // Without "Set Up…" a listed button without an action stays a duplicate.
        pane.setAction(of: unbound.id, to: nil)
        pane.beginAddingBinding()
        pane.onRecordingStarted(recorder)
        XCTAssertFalse(pane.validateRecordedEvent(recorder, event: mouseEvent(3)))
    }

    func testCancelledRecordingAddsNothing() {
        let pane = makePane()
        let recorder = KeyRecorder()
        pane.beginAddingBinding()
        pane.onRecordingStarted(recorder)
        pane.onRecordingStopped(recorder, didRecord: false)
        flush()
        XCTAssertFalse(pane.isRecording)
        XCTAssertTrue(Options.shared.buttons.binding.isEmpty)
        XCTAssertEqual(pane.headerView.content.subtitle, "No buttons set up yet")
    }

    /// After a button is added the list has the keyboard, with the new row selected.
    func testAfterAddingTheListHasTheKeyboard() throws {
        deviceName = nil
        let pane = makePane([binding(3, "copy")])
        let (window, _) = makeWindow(for: pane)
        let recorder = KeyRecorder()
        pane.beginAddingBinding()
        pane.onRecordingStarted(recorder)
        pane.onEventRecorded(recorder, didRecordEvent: mouseEvent(4), isDuplicate: false)
        pane.onRecordingStopped(recorder, didRecord: true)
        let added = try XCTUnwrap(Options.shared.buttons.binding.last)
        XCTAssertEqual(pane.list.selectedID, AnyHashable(added.id))
        XCTAssertTrue(window.firstResponder === pane.list)
    }

    /// Leaving the pane closes what it opened: the ⓘ popover, "Open App or File", the
    /// recorder of "+" and the one of "Keyboard Shortcut…".
    func testLeavingThePaneClosesItsPopoversAndRecorders() throws {
        captureStatus = [1000: .conflict(.foreignDivert)]
        let bindings = [binding(1000, "copy"), binding(3, "copy")]
        let pane = makePane(bindings)
        let listed = try rows(of: bindings, in: pane)

        // "Open App or File…" of the second row.
        let pullDown = listed[1].pullDown
        let openItem = try XCTUnwrap(pullDown.menu?.items.first { $0.representedObject as? String == ShortcutManager.MenuMarker.openTarget })
        pullDown.shortcutSelected(openItem)
        XCTAssertNotNil(pane.openTargetPopover)
        XCTAssertTrue(shownOpenTargets.first === pullDown, "shown at the row's pull-down")
        // The ⓘ of the first row.
        XCTAssertNotNil(pane.showProblem(of: listed[0], relativeTo: listed[0].infoButton))
        XCTAssertNotNil(pane.problemPopover)
        // "Keyboard Shortcut…" waits for a key in the first row.
        listed[0].pullDown.beginCustomShortcutSelection(startRecorder: false)
        XCTAssertEqual(listed[0].pullDown.actionState, .recordingPrompt)
        // "+" waits for a button.
        pane.beginAddingBinding(action: SystemShortcut.mouseGestureNavigation)
        pane.onRecordingStarted(KeyRecorder())

        pane.viewWillDisappear()

        XCTAssertNil(pane.openTargetPopover)
        XCTAssertNil(pane.problemPopover)
        XCTAssertEqual(recorderStops, 1)
        XCTAssertFalse(pane.isRecording)
        XCTAssertFalse(pane.isRecorderOpen)
        XCTAssertNil(pane.pendingAction)
        XCTAssertNotEqual(listed[0].pullDown.actionState, .recordingPrompt, "the action shows again")
        XCTAssertEqual(Options.shared.buttons.binding.count, 2, "nothing added")
        XCTAssertEqual(pane.headerView.content.title, "MX Master 4")

        // Nothing to close: nothing is stopped.
        pane.viewWillAppear()
        pane.viewWillDisappear()
        XCTAssertEqual(recorderStops, 1)
    }

    func testAddingABluetoothOnlyLogitechButtonWarnsOnce() {
        deviceName = nil
        captureStatus = [1001: .bleHIDPPUnstable]
        let pane = makePane()
        pane.addBinding(for: RecordedEvent(type: .mouse, code: 1001, modifiers: 0, deviceFilter: nil), action: nil)
        XCTAssertEqual(warnedCodes, [1001])
    }

    // MARK: - Removing, with Undo

    func testMinusRemovesTheSelectedButtonAndUndoPutsItBack() throws {
        deviceName = nil
        let first = binding(3, "copy")
        let second = binding(4, SystemShortcut.scrollDash.identifier)
        let third = binding(5)
        let pane = makePane([first, second, third])
        let undo = try XCTUnwrap(pane.paneUndoManager)
        undo.groupsByEvent = false

        pane.list.select(second.id)
        undo.beginUndoGrouping()
        pane.list.removeButton.performClick(nil)
        undo.endUndoGrouping()
        XCTAssertEqual(Options.shared.buttons.binding.map(\.id), [first.id, third.id])
        XCTAssertNil(pane.list.selectedID)
        XCTAssertTrue(undo.canUndo)
        XCTAssertEqual(undo.undoMenuItemTitle, "Undo Remove Button")

        undo.undo()
        XCTAssertEqual(Options.shared.buttons.binding, [first, second, third], "back where it was, unchanged")
        XCTAssertEqual(pane.list.selectedID, AnyHashable(second.id))
        XCTAssertEqual(undo.redoMenuItemTitle, "Redo Remove Button")

        undo.redo()
        XCTAssertEqual(Options.shared.buttons.binding.map(\.id), [first.id, third.id])
    }

    func testDeleteKeyRemovesTooAndAnEmptyListShowsItsRow() throws {
        deviceName = nil
        let only = binding(3, "copy")
        let pane = makePane([only])
        let (window, _) = makeWindow(for: pane)
        pane.list.select(only.id)
        window.makeFirstResponder(pane.list)
        pane.list.keyDown(with: try key("\u{7F}", keyCode: 51))
        XCTAssertTrue(Options.shared.buttons.binding.isEmpty)
        XCTAssertTrue(pane.list.emptyRow.superview === pane.list.rowsView)
    }

    /// Undo runs from the Edit menu while another pane shows (this one is out of the
    /// window then): it puts the button back, and Redo and Undo keep working. Back in the
    /// window an Undo gives the list the keyboard with the row selected.
    func testUndoAndRedoWorkWhileAnotherPaneShows() throws {
        deviceName = nil
        let first = binding(3, "copy")
        let second = binding(4, "paste")
        let pane = makePane([first, second])
        let (window, container) = makeWindow(for: pane)
        let undo = try XCTUnwrap(window.undoManager)
        undo.groupsByEvent = false

        pane.list.select(second.id)
        undo.beginUndoGrouping()
        pane.list.removeButton.performClick(nil)
        undo.endUndoGrouping()
        XCTAssertEqual(Options.shared.buttons.binding, [first])

        // Another pane shows.
        pane.view.removeFromSuperview()
        XCTAssertNil(pane.view.window)
        XCTAssertTrue(undo.canUndo)
        undo.undo()
        XCTAssertEqual(Options.shared.buttons.binding, [first, second], "back")
        XCTAssertTrue(undo.canRedo, "the chain goes on")
        undo.redo()
        XCTAssertEqual(Options.shared.buttons.binding, [first])
        XCTAssertTrue(undo.canUndo)

        // The pane is back.
        container.addSubview(pane.view)
        window.makeFirstResponder(nil)
        undo.undo()
        XCTAssertEqual(Options.shared.buttons.binding, [first, second])
        XCTAssertEqual(pane.list.selectedID, AnyHashable(second.id))
        XCTAssertTrue(window.firstResponder === pane.list, "the list has the keyboard")
        XCTAssertEqual(undo.redoMenuItemTitle, "Redo Remove Button")
    }

    // MARK: - The action menu

    func testTheActionMenuIsGroupedAndNamedPlainly() throws {
        let pullDown = ButtonActionPullDown(binding: binding(1000, "copy"))
        let menu = try XCTUnwrap(pullDown.menu)
        let titles = menu.items.map(\.title)
        XCTAssertEqual(menu.items[2].title, "No Action")
        XCTAssertTrue(menu.items[1].isHidden, "a pull-down shows no separator first")
        XCTAssertTrue(titles.contains("Scrolling"))
        XCTAssertTrue(titles.contains("Logitech Mouse"))
        XCTAssertTrue(titles.contains("Finder"))
        XCTAssertFalse(titles.contains("Mouse Scroll"))
        XCTAssertFalse(titles.contains("Logi Actions"))
        // Every category has a symbol, never a brand tag.
        for item in menu.items where item.submenu != nil {
            let image = try XCTUnwrap(item.image, item.title)
            XCTAssertTrue(image.isTemplate, "\(item.title): an SF Symbol")
        }
        let scrolling = try XCTUnwrap(menu.items.first { $0.title == "Scrolling" }?.submenu)
        XCTAssertEqual(scrolling.items.map(\.title), ["Scroll Faster", "Scroll Slower", "Scroll Sideways", "Pause Smoothing"])
        let logitech = try XCTUnwrap(menu.items.first { $0.title == "Logitech Mouse" }?.submenu)
        XCTAssertEqual(logitech.items.map(\.title), [
            "Switch Wheel Mode", "Increase Pointer Speed", "Decrease Pointer Speed",
            "Switch to Computer 1", "Switch to Computer 2", "Switch to Computer 3",
            // "Toggle Hi-Res Scrolling", "Invert Scrolling" and "Toggle Thumb Wheel" are no
            // longer offered: they left the mouse changed after Pause and Quit.
            "Next Pointer Speed",
        ])
        // The last group: Gesture Navigation, its settings (hidden: not its action), the
        // Shortcut Ring, Open App or File…, Keyboard Shortcut….
        let last = Array(menu.items.suffix(5))
        XCTAssertTrue(menu.items[menu.items.count - 6].isSeparatorItem)
        XCTAssertEqual(last.map(\.title), [
            "Gesture Navigation", "Show Gesture Settings", "Shortcut Ring", "Open App or File…", "Keyboard Shortcut…",
        ])
        XCTAssertTrue(last[1].isHidden)

        // A standard button gets no Logitech actions.
        let standard = ButtonActionPullDown(binding: binding(3, "copy"))
        XCTAssertFalse(standard.menu?.items.contains { $0.title == "Logitech Mouse" } ?? true)
    }

    func testKeyEquivalentsShowOnlyWhileTheMenuIsOpen() throws {
        let pullDown = ButtonActionPullDown(binding: binding(3, "copy"))
        let menu = try XCTUnwrap(pullDown.menu)
        let all = menu.items + menu.items.compactMap(\.submenu).flatMap(\.items)
        XCTAssertTrue(all.allSatisfy { $0.keyEquivalent.isEmpty })
        pullDown.menuWillOpen(menu)
        let copy = try XCTUnwrap(all.first { ($0.representedObject as? SystemShortcut.Shortcut)?.identifier == "copy" })
        XCTAssertEqual(copy.keyEquivalent, "c")
        pullDown.menuDidClose(menu)
        XCTAssertEqual(copy.keyEquivalent, "")
    }

    func testOpenAppOrFileTexts() {
        XCTAssertEqual(text("open-target-title"), "Open App or File")
        XCTAssertEqual(text("open-target-empty-primary"), "Choose an app, file or script")
        XCTAssertEqual(text("open-target-empty-secondary"), "or drag one here")
        XCTAssertEqual(text("open-target-arguments-placeholder"), "Separate with spaces. Put quotes around an argument with spaces.")
        XCTAssertEqual(text("open-target-stale-warning"), "Can't find the app chosen before. Choose it again.")
    }

    // MARK: - "Checking buttons…"

    func testCheckingButtonsShowsWhileBusyAndAtLeastHalfASecond() {
        let pane = makePane([binding(1000, "copy")])
        XCTAssertTrue(pane.list.footerAccessory === pane.busyView)
        XCTAssertTrue(pane.busyView.isHidden)

        busy = true
        pane.syncBusy()
        XCTAssertFalse(pane.busyView.isHidden)
        let label = pane.busyView.arrangedSubviews.compactMap { $0 as? NSTextField }.first
        XCTAssertEqual(label?.stringValue, "Checking buttons…")
        XCTAssertEqual(label?.font?.pointSize, NSFont.smallSystemFontSize)

        busy = false
        pane.syncBusy()
        XCTAssertFalse(pane.busyView.isHidden, "not before half a second")
        flush(PreferencesButtonsViewController.busyMinimumDuration + 0.1)
        XCTAssertTrue(pane.busyView.isHidden)
    }

    // MARK: - Stored bindings

    func testStoredBindingsLoadAndSaveUnchanged() throws {
        // A binding as stored by earlier versions, every kind of action.
        let json = """
        [
          {"id":"0B9C2C9E-6C51-4A57-9C2E-8E2B1E4C1A01","triggerEvent":{"type":"mouse","code":3,"modifiers":524288,"deviceFilter":null},
           "systemShortcutName":"mouseGestureNavigation","isEnabled":true,"createdAt":700000000},
          {"id":"0B9C2C9E-6C51-4A57-9C2E-8E2B1E4C1A02","triggerEvent":{"type":"mouse","code":1000,"modifiers":0},
           "systemShortcutName":"custom::40:1572864","isEnabled":true,"createdAt":700000001},
          {"id":"0B9C2C9E-6C51-4A57-9C2E-8E2B1E4C1A03","triggerEvent":{"type":"keyboard","code":40,"modifiers":786432},
           "systemShortcutName":"openTarget","isEnabled":true,"createdAt":700000002,
           "openTarget":{"path":"/System/Applications/Calculator.app","bundleID":"com.apple.calculator","arguments":"","kind":"application"}},
          {"id":"0B9C2C9E-6C51-4A57-9C2E-8E2B1E4C1A04","triggerEvent":{"type":"mouse","code":5,"modifiers":0},
           "systemShortcutName":"","isEnabled":false,"createdAt":700000003}
        ]
        """
        let decoded = try JSONDecoder().decode([ButtonBinding].self, from: Data(json.utf8))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let before = try encoder.encode(decoded)

        let pane = makePane(decoded)
        XCTAssertEqual(try rows(of: decoded, in: pane).map(\.title), ["⌥ Back button", "Gesture button", "⌃⌥ K", "Button 5"])
        XCTAssertEqual(try rows(of: decoded, in: pane).map { shown($0.pullDown) }, ["Gesture Navigation", "⌥⌘K", "Calculator", "No Action"])
        // Where they are: the gesture button is its row, the rest below in stored order.
        XCTAssertEqual(pane.rows.map(\.title), mxMaster4Titles + ["⌥ Back button", "⌃⌥ K", "Button 5"])
        XCTAssertEqual(pane.row(for: ButtonsMousePart.gesture)?.binding, decoded[1])
        XCTAssertEqual(pane.list.groupTitles[AnyHashable(decoded[0].id)]?.title, "Other buttons and keys")

        // Changing one binding leaves the others byte for byte as they were.
        pane.setAction(of: decoded[3].id, to: SystemShortcut.copy)
        var expected = decoded
        expected[3] = ButtonBinding(id: decoded[3].id, triggerEvent: decoded[3].triggerEvent, systemShortcutName: "copy", isEnabled: true, createdAt: decoded[3].createdAt)
        XCTAssertEqual(try encoder.encode(Options.shared.buttons.binding), try encoder.encode(expected))
        XCTAssertEqual(try encoder.encode(Array(Options.shared.buttons.binding.prefix(3))), try encoder.encode(Array(decoded.prefix(3))))

        // Reloading writes nothing new.
        Options.shared.buttons.binding = decoded
        pane.reload()
        XCTAssertEqual(try encoder.encode(Options.shared.buttons.binding), before)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: before) as? [[String: Any]])
        XCTAssertEqual(Set(object[2].keys), ["id", "triggerEvent", "systemShortcutName", "isEnabled", "createdAt", "openTarget"])
    }

    private func shown(_ pullDown: NSPopUpButton) -> String? {
        return pullDown.menu?.items.first?.title
    }
}
