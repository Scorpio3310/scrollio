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
        pane.holdKeysThatCatch = { [unowned self] in self.scrollKeys }
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

    /// `body` as one step of Edit › Undo on a manager that groups by hand
    /// (`groupsByEvent` off): a change of a row registers its Undo.
    private func step(_ undo: UndoManager, _ body: () throws -> Void) rethrows {
        undo.beginUndoGrouping()
        defer { undo.endUndoGrouping() }
        try body()
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
    /// sit on it, each "Default", with what it then does in parentheses where that is
    /// certain ("Default (Back)", its sentence in the pull-down's tooltip and no line); the
    /// free Gesture button and Thumb panel say what they are good for. Left and right clicks are not
    /// listed, nothing is stored, the list has no title inside, and "−" and Delete never
    /// remove one.
    func testAnMXMaster4ListsEveryButtonInTheOrderTheySit() throws {
        let pane = makePane()
        let (window, _) = makeWindow(for: pane)
        XCTAssertEqual(ButtonsMousePart.listed(on: .mxMaster4), [.middle, .modeShift, .gesture, .forward, .back, .thumbPanel])
        XCTAssertEqual(pane.rows.map(\.title), mxMaster4Titles)
        XCTAssertEqual(pane.rows.map(\.id), ButtonsMousePart.listed(on: .mxMaster4).map { AnyHashable($0) })
        XCTAssertEqual(pane.rows.map { shown($0.pullDown) }, [
            "Default (Middle Click)", "Default (Switch Wheel Mode)", "Default", "Default (Forward)", "Default (Back)", "Default",
        ])
        XCTAssertEqual(pane.rows.map(\.explanation), [
            nil, nil, "Good for Gestures or the Shortcut Ring.", nil, nil, "Good for Gestures or the Shortcut Ring.",
        ])
        XCTAssertEqual(pane.rows.map(\.pullDown.toolTip), [
            "Middle click.",
            "Switches the wheel between clicking and spinning freely.",
            nil,
            "Goes forward in apps that support it.",
            "Goes back in apps that support it.",
            nil,
        ], "the sentence the line said is the tooltip")
        XCTAssertEqual(pane.rows.map { $0.note?.tone }, [nil, nil, .plain, nil, nil, .plain])
        XCTAssertTrue(pane.rows.allSatisfy { $0.isDefault && !$0.isStored && !$0.isRemovable && $0.infoButton.isHidden && $0.placeButton.isHidden })
        XCTAssertEqual(pane.rows.map(\.picture), ButtonsMousePart.listed(on: .mxMaster4).map { ButtonTriggerPicture.mouse(part: $0, number: nil) })
        XCTAssertEqual(pane.rows[4].accessibilityLabel(), "Back button")
        XCTAssertEqual(pane.rows[4].pullDown.accessibilityHelp(), "Goes back in apps that support it.", "VoiceOver hears it")
        XCTAssertEqual(pane.rows[2].accessibilityLabel(), "Gesture button, Good for Gestures or the Shortcut Ring.")
        XCTAssertTrue(pane.list.groupTitles.isEmpty)
        XCTAssertNil(pane.list.emptyRow.superview, "never empty")

        // "Default (Back)" where the Shortcut Ring's places offer "No Action"; the
        // parenthesis in grey, the plain title the same text for VoiceOver.
        let back = pane.rows[4].pullDown
        XCTAssertEqual(back.noActionItem?.title, "Default (Back)")
        XCTAssertNil(back.menu?.items.first { $0.title == "No Action" })
        XCTAssertEqual(back.menu?.items.first?.title, "Default (Back)")
        let attributed = try XCTUnwrap(back.menu?.items.first?.attributedTitle)
        XCTAssertEqual(attributed.string, "Default (Back)")
        XCTAssertNil(attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil), "Default in the title's own colour")
        XCTAssertEqual(attributed.attribute(.foregroundColor, at: 8, effectiveRange: nil) as? NSColor, .secondaryLabelColor)
        XCTAssertEqual(pane.rows[2].pullDown.noActionItem?.title, "Default")
        XCTAssertNil(pane.rows[2].pullDown.menu?.items.first?.attributedTitle, "nothing in grey")
        XCTAssertNil(pane.rows[2].pullDown.toolTip)
        XCTAssertEqual(ButtonActionPullDown(binding: binding(5)).noActionItem?.title, "Default", "every row of Buttons")
        XCTAssertEqual(ButtonActionPullDown(binding: binding(5), forRingPlace: true).noActionItem?.title, "No Action")

        // The card: no button has an action; a row lights its button and says what its
        // pull-down says.
        XCTAssertEqual(pane.headerView.content.subtitle, "No buttons set up yet")
        pane.list.select(ButtonsMousePart.back)
        XCTAssertEqual(pane.headerView.content, ButtonsHeaderContent(title: "Back button", subtitle: "Default (Back)", part: .back))
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
        XCTAssertEqual(pane.rows[4].explanation, "Good for Gestures or the Shortcut Ring.")
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

        for name in [nil, "MX Anywhere 2S", "M720 Triathlon", "Lift"] as [String?] {
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

    /// An MX Master 4 at the defaults: the row reads "Default (Scroll Sideways)" with no line
    /// under it (the sentence is the pull-down's tooltip), lights the thumb wheel in its
    /// picture, and offers the six functions; it is no button row (no recorder, no ⓘ, never
    /// removed) and the buttons' rows are as they were.
    func testTheThumbWheelRowReadsDefaultWhileItScrolls() throws {
        let pane = makePane()
        let row = try XCTUnwrap(pane.thumbWheelRow)
        XCTAssertEqual(listTitles(pane), ["Middle button", "Mode shift button", "Thumb wheel", "Gesture button",
                                          "Forward button", "Back button", "Thumb panel"])
        XCTAssertEqual(pane.rows.map(\.title), mxMaster4Titles, "the button rows are the same")
        XCTAssertTrue(pane.list.rows[2] === row)
        XCTAssertEqual(row.id, ButtonsListLayout.thumbWheelRowID)
        XCTAssertEqual(shown(row.pullDown), "Default (Scroll Sideways)")
        XCTAssertEqual(row.pullDown.menu?.items.first?.attributedTitle?.attribute(.foregroundColor, at: 8, effectiveRange: nil) as? NSColor,
                       .secondaryLabelColor, "the parenthesis in grey")
        XCTAssertNil(row.pullDown.menu?.items.first?.image, "no symbol for Default, as on the other rows")
        XCTAssertNil(row.explanation, "the title says it")
        XCTAssertEqual(row.pullDown.toolTip, "Scrolls sideways.")
        XCTAssertEqual(row.accessibilityLabel(), "Thumb wheel")
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
        XCTAssertEqual(items.map(\.title), ["Default (Scroll Sideways)", "Zoom", "Switch Tabs", "Switch Desktops", "Back and Forward", "Volume"])
        XCTAssertEqual(items.compactMap(ThumbWheelPresentation.function(of:)), ThumbWheelFunction.allCases)
        XCTAssertNil(items[0].image)
        XCTAssertTrue(items.dropFirst().allSatisfy { $0.image?.isTemplate == true }, "the others with their symbols")
        if #available(macOS 27.0, *) {
            XCTAssertTrue(items.dropFirst().allSatisfy { $0.preferredImageVisibility == .visible })
        }
        XCTAssertEqual(items.map(\.state), [.on, .off, .off, .off, .off, .off])
        XCTAssertEqual(items.map(\.toolTip), ThumbWheelFunction.allCases.map(\.localizedHint))
        XCTAssertTrue(row.pullDown.menu?.items[2].isSeparatorItem ?? false, "Default stands apart")

        // Pointed at or selected, the card lights the thumb wheel and says what the row says.
        pane.list.select(ButtonsListLayout.thumbWheelRowID)
        XCTAssertEqual(pane.headerView.content, ButtonsHeaderContent(
            title: "Thumb wheel", subtitle: "Default (Scroll Sideways)", part: nil, lightsThumbWheel: true
        ))
        XCTAssertTrue(pane.headerView.artwork.emphasizesThumbWheel)
        XCTAssertNil(pane.headerView.artwork.emphasis)
        XCTAssertFalse(pane.list.removeButton.isEnabled, "the thumb wheel is never removed")
        pane.list.select(ButtonsMousePart.back)
        XCTAssertEqual(pane.headerView.artwork.emphasis, .back)
        XCTAssertFalse(pane.headerView.artwork.emphasizesThumbWheel)
        XCTAssertEqual(pane.headerView.content.subtitle, "Default (Back)")
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
        XCTAssertEqual(shown(row.pullDown), "Default (Scroll Sideways)")
        XCTAssertNil(row.explanation)
        XCTAssertEqual(pane.headerView.content.subtitle, "Default (Scroll Sideways)")

        // The bindings: the same values, the same bytes, never saved.
        XCTAssertEqual(try encoder.encode(Options.shared.buttons.binding), before)
        XCTAssertEqual(pane.buttonBindings, bindings)
        Options.shared.flushPendingSaves()
        XCTAssertEqual(flushed, [[.thumbWheel]], "only the thumb wheel is saved")
        XCTAssertEqual(pane.rows.map(\.binding.id).filter { id in bindings.contains { $0.id == id } }.count, 3)
        XCTAssertNil(pane.row(for: ButtonsListLayout.thumbWheelRowID), "it is no binding's row")
        XCTAssertNil(pane.storedBinding(ofRow: ButtonsListLayout.thumbWheelRowID))
    }

    /// Edit › Undo of a function chosen on the thumb wheel's row ("Undo Change Action", as
    /// a button row's) puts back the one it had, and Redo chooses it again; the bindings
    /// stay. Regression: the change had no Undo, so ⌘Z undid an older, other change.
    func testUndoPutsBackTheThumbWheelsFunction() throws {
        let bindings = [binding(3, "copy")]
        let pane = makePane(bindings)
        let row = try XCTUnwrap(pane.thumbWheelRow)
        let undo = try XCTUnwrap(pane.paneUndoManager)
        undo.groupsByEvent = false
        XCTAssertEqual(Options.shared.thumbWheel.function, .scroll)
        XCTAssertFalse(undo.canUndo)

        let tabs = try XCTUnwrap(row.pullDown.functionItems.first { ThumbWheelPresentation.function(of: $0) == .tabs })
        undo.beginUndoGrouping()
        row.pullDown.functionChosen(tabs)
        undo.endUndoGrouping()
        XCTAssertEqual(Options.shared.thumbWheel.function, .tabs)
        XCTAssertEqual(undo.undoMenuItemTitle, "Undo Change Action")

        undo.undo()
        XCTAssertEqual(Options.shared.thumbWheel.function, .scroll)
        XCTAssertEqual(shown(row.pullDown), "Default (Scroll Sideways)", "the row follows")
        XCTAssertEqual(undo.redoMenuItemTitle, "Redo Change Action")
        undo.redo()
        XCTAssertEqual(Options.shared.thumbWheel.function, .tabs)
        XCTAssertEqual(shown(row.pullDown), "Switch Tabs")
        XCTAssertEqual(undo.undoMenuItemTitle, "Undo Change Action")
        XCTAssertEqual(Options.shared.buttons.binding, bindings, "no binding is touched")
    }

    /// The row's menu ends with "Show in Scrolling" (after a separator, with its symbol,
    /// never ticked): it opens the Scrolling pane and changes nothing.
    func testTheThumbWheelRowsMenuOpensItsSettings() throws {
        let pane = makePane([])
        let row = try XCTUnwrap(pane.thumbWheelRow)
        Options.shared.thumbWheel = ThumbWheelSettings(function: .volume)
        pane.syncThumbWheel()
        let menu = try XCTUnwrap(row.pullDown.menu)
        let item = try XCTUnwrap(row.pullDown.settingsItem)
        XCTAssertTrue(menu.items.last === item, "last")
        XCTAssertTrue(menu.items[menu.items.count - 2].isSeparatorItem)
        XCTAssertEqual(item.title, "Show in Scrolling")
        XCTAssertNotNil(item.image)
        XCTAssertNil(ThumbWheelPresentation.function(of: item), "it picks no function")
        XCTAssertEqual(row.pullDown.functionItems.count, ThumbWheelFunction.allCases.count)

        shownPanes = []
        let before = Options.shared.thumbWheel
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item))
        XCTAssertEqual(shownPanes, [PANEL_IDENTIFIER.scrolling])
        XCTAssertEqual(Options.shared.thumbWheel, before, "nothing changes")
        XCTAssertEqual(shown(row.pullDown), "Volume")
        XCTAssertEqual(item.state, .off)

        // One tick, the function's, never beside it on "Show in Scrolling": AppKit does not
        // tick the item a click chose (it does so only while the mouse tracks the menu, which
        // a test cannot do: the setting is checked), and choosing it through the menu leaves
        // the one tick.
        XCTAssertEqual((row.pullDown.cell as? NSPopUpButtonCell)?.altersStateOfSelectedItem, false)
        menu.performActionForItem(at: menu.index(of: item))
        XCTAssertEqual(shownPanes, [PANEL_IDENTIFIER.scrolling, PANEL_IDENTIFIER.scrolling])
        let ticked = menu.items.filter { $0.state == .on }
        XCTAssertEqual(ticked.count, 1, ticked.map(\.title).description)
        XCTAssertEqual(ticked.first.flatMap(ThumbWheelPresentation.function(of:)), .volume)
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
        scrolling.thumbWheelReverseSwitch.state = .on
        XCTAssertTrue(scrolling.thumbWheelReverseSwitch.sendAction(scrolling.thumbWheelReverseSwitch.action, to: scrolling.thumbWheelReverseSwitch.target))
        XCTAssertEqual(changes, 3)
        XCTAssertEqual(shown(row.pullDown), "Back and Forward")

        // Reset under Scrolling: the row reads "Default (Scroll Sideways)" again.
        scrolling.paneUndoManager = UndoManager()
        XCTAssertTrue(scrolling.resetToDefaultsButton.sendAction(scrolling.resetToDefaultsButton.action, to: scrolling.resetToDefaultsButton.target))
        XCTAssertEqual(Options.shared.thumbWheel, .default)
        XCTAssertEqual(shown(row.pullDown), "Default (Scroll Sideways)")
        XCTAssertEqual(buttons.headerView.content.subtitle, "Default (Scroll Sideways)")
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
        // (The mode shift button: "⌥ Mode shift button" keeps its Logitech control with
        // Scrollio, so its plain press does nothing.)
        XCTAssertEqual(top.map { shown($0.pullDown) }, [
            SystemShortcut.missionControl.localizedName, "No Action", "Gesture Navigation", "Default (Forward)", "Copy", "Default",
        ])
        XCTAssertEqual(pane.row(for: ButtonsMousePart.back)?.binding, bindings[1])
        XCTAssertEqual(pane.row(for: ButtonsMousePart.gesture)?.binding, gestureNumber)
        XCTAssertEqual(pane.rows.dropFirst(6).map(\.id), [bindings[0], bindings[3], bindings[5], bindings[6], bindings[7]].map { AnyHashable($0.id) })
        XCTAssertEqual(pane.list.groupTitles.count, 1)
        XCTAssertEqual(pane.list.groupTitles[AnyHashable(bindings[0].id)]?.title, "Other buttons and keys")
        XCTAssertEqual(pane.layout.others, [bindings[0], bindings[3], bindings[5], bindings[6], bindings[7]])

        pane.list.select(bindings[6].id)
        XCTAssertTrue(pane.list.removeButton.isEnabled)
        XCTAssertEqual(pane.list.removeButton.accessibilityLabel(), "Remove")
        XCTAssertNil(pane.list.removeButton.toolTip)
        pane.list.select(ButtonsMousePart.back)
        XCTAssertTrue(pane.list.removeButton.isEnabled, "a button of the mouse with an action: − clears it")
        XCTAssertEqual(pane.list.removeButton.accessibilityLabel(), "Clear Action")
        XCTAssertEqual(pane.list.removeButton.toolTip, "Clear Action")
        pane.list.select(ButtonsMousePart.modeShift)
        XCTAssertFalse(pane.list.removeButton.isEnabled, "nothing to clear on a Default row")
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
        try step(undo) { back.pullDown.shortcutSelected(try XCTUnwrap(item("copy", in: menu))) }

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
            try step(undo) { row.pullDown.shortcutSelected(try XCTUnwrap(item("paste", in: row.pullDown.menu))) }
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
        XCTAssertEqual(shown(back.pullDown), "Default (Back)")
        XCTAssertNil(back.explanation)
        XCTAssertEqual(back.pullDown.toolTip, "Goes back in apps that support it.")
        XCTAssertEqual(undo.undoMenuItemTitle, "Undo Clear Action")
        undo.undo()
        XCTAssertEqual(Options.shared.buttons.binding.first, stored, "back where it was, unchanged")
        XCTAssertEqual(shown(back.pullDown), "Copy")
        XCTAssertEqual(pane.list.selectedID, AnyHashable(ButtonsMousePart.back))
        undo.redo()
        XCTAssertFalse(Options.shared.buttons.binding.contains { $0.id == stored.id })

        // "Default" on a row without a binding changes nothing.
        back.pullDown.shortcutSelected(defaultItem)
        XCTAssertEqual(Options.shared.buttons.binding.count, 5)
        XCTAssertEqual(shown(back.pullDown), "Default (Back)")
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
        XCTAssertEqual(shown(back.pullDown), "Default (Back)", "not caught while it has no binding")
        XCTAssertNil(back.explanation)
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

    /// The recorder's line about a listed button says what is so (QA B1): "Already has an
    /// action" only of a row that has one; of a "Default" row, which has none, "Already in
    /// the list". It said "Already has an action" of both, under a card that answered
    /// "That's Gesture button / Default".
    func testTheRecorderSaysAlreadyInTheListOfARowWithoutAnAction() {
        let pane = makePane([binding(3, "copy"), binding(5)])
        let recorder = KeyRecorder()
        pane.beginAddingBinding()
        pane.onRecordingStarted(recorder)
        XCTAssertEqual(text("buttons-recorder-in-list"), "Already in the list")
        // A button of the mouse without a binding.
        XCTAssertFalse(pane.validateRecordedEvent(recorder, event: mouseEvent(1000)))
        XCTAssertEqual(pane.refusalHint(recorder, event: mouseEvent(1000)), "Already in the list")
        // A stored row without an action.
        XCTAssertFalse(pane.validateRecordedEvent(recorder, event: mouseEvent(5)))
        XCTAssertEqual(pane.refusalHint(recorder, event: mouseEvent(5)), "Already in the list")
        // A row with an action: the popover's own "Already has an action".
        XCTAssertFalse(pane.validateRecordedEvent(recorder, event: mouseEvent(3)))
        XCTAssertNil(pane.refusalHint(recorder, event: mouseEvent(3)))
        // A new button: nothing to say.
        XCTAssertNil(pane.refusalHint(recorder, event: mouseEvent(6)))
        pane.onRecordingStopped(recorder, didRecord: false)
    }

    /// "+" has its Undo (QA B2): ⌘Z right after it takes the new row away, and Redo adds it
    /// again. It registered none: ⌘Z undid an older change in another pane, and a row added
    /// with "+" could never be undone (the first Undo only took its action away).
    func testPlusCanBeUndoneAndRedone() throws {
        deviceName = nil
        let first = binding(3, "copy")
        let pane = makePane([first])
        let (window, _) = makeWindow(for: pane)
        let undo = try XCTUnwrap(window.undoManager)
        undo.groupsByEvent = false
        let recorder = KeyRecorder()
        pane.beginAddingBinding()
        pane.onRecordingStarted(recorder)
        pane.onEventRecorded(recorder, didRecordEvent: mouseEvent(4, modifiers: .maskAlternate), isDuplicate: false)
        step(undo) { pane.onRecordingStopped(recorder, didRecord: true) }
        let added = try XCTUnwrap(Options.shared.buttons.binding.last)
        XCTAssertEqual(Options.shared.buttons.binding.map(\.id), [first.id, added.id])
        XCTAssertTrue(undo.canUndo)
        XCTAssertEqual(undo.undoMenuItemTitle, "Undo Add Button")

        undo.undo()
        XCTAssertEqual(Options.shared.buttons.binding, [first], "the new row is gone")
        XCTAssertEqual(pane.rows.count, 1)
        XCTAssertEqual(undo.redoMenuItemTitle, "Redo Add Button")
        undo.redo()
        XCTAssertEqual(Options.shared.buttons.binding.map(\.id), [first.id, added.id])
        XCTAssertEqual(pane.list.selectedID, AnyHashable(added.id), "back, and selected")
        XCTAssertEqual(undo.undoMenuItemTitle, "Undo Add Button")

        // An action chosen in the menu that opened is its own step, before the row's.
        let row = try XCTUnwrap(pane.row(for: added.id))
        try step(undo) { row.pullDown.shortcutSelected(try XCTUnwrap(item("copy", in: row.pullDown.menu))) }
        XCTAssertEqual(undo.undoMenuItemTitle, "Undo Change Action")
        undo.undo()
        XCTAssertEqual(Options.shared.buttons.binding.last?.systemShortcutName, "")
        undo.undo()
        XCTAssertEqual(Options.shared.buttons.binding, [first])
        flush()
    }

    /// The new row's menu opens from the run loop, not from a block of the main queue (QA
    /// B5): a menu runs until it closes, and a run loop that starts inside a block of the
    /// main queue does not serve that queue, so gesture actions and the thumb wheel's steps
    /// waited for the menu to close.
    func testTheNewRowsMenuOpensWhereTheMainQueueGoesOn() {
        let pane = makePane([binding(3, "copy")])
        var served: [Bool] = []
        pane.openActionMenu = { _ in
            // As a menu does: a run loop of its own until it closes.
            var ran = false
            DispatchQueue.main.async { ran = true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            served.append(ran)
        }
        let recorder = KeyRecorder()
        pane.beginAddingBinding()
        pane.onRecordingStarted(recorder)
        pane.onEventRecorded(recorder, didRecordEvent: mouseEvent(4, modifiers: .maskAlternate), isDuplicate: false)
        pane.onRecordingStopped(recorder, didRecord: true)
        flush(0.3)
        XCTAssertEqual(served, [true], "the menu opened once, and the main queue went on behind it")
    }

    /// A "Default" row says what the button then does ("Default (Back)") only where that is
    /// certain: while Scrollio catches its Logitech control for a binding with modifiers (the
    /// plain press then reaches only Scrollio and does nothing), "No Action" and why; a
    /// Logitech hold key under Scrolling has its line, and keeps the button with Scrollio
    /// too; a numbered button said to be there makes no claim beyond its own.
    func testTheDefaultLineSaysOnlyWhatIsCertain() throws {
        scrollKeys = [ScrollHotkey(type: .mouse, code: 1001)]
        let caught = binding(1006, "copy", modifiers: option)
        let middle = ButtonBinding(triggerEvent: placed(8, .middleButton, modifiers: option), systemShortcutName: "copy", isEnabled: true)
        let pane = makePane([caught, binding(4, "copy", modifiers: command), middle])
        func row(_ part: ButtonsMousePart) throws -> ButtonBindingRow {
            return try XCTUnwrap(pane.row(for: part))
        }
        XCTAssertEqual(
            try row(.back).explanation, "Scrollio keeps it for another row, so a press does nothing.",
            "the plain press reaches only Scrollio"
        )
        XCTAssertEqual(shown(try row(.back).pullDown), "No Action")
        XCTAssertNil(try row(.back).pullDown.toolTip)
        XCTAssertEqual(shown(try row(.forward).pullDown), "Default (Forward)", "a standard button with ⌘ is not caught")
        XCTAssertNil(try row(.forward).explanation)
        XCTAssertEqual(try row(.modeShift).explanation, "Also set under Scrolling\u{A0}›\u{A0}While\u{A0}you\u{A0}hold\u{A0}a\u{A0}key.")
        XCTAssertEqual(shown(try row(.modeShift).pullDown), "No Action", "the mouse is asked for it: it does not switch the wheel")
        XCTAssertEqual(try row(.modeShift).note?.tone, .problem)
        XCTAssertFalse(try row(.modeShift).infoButton.isHidden)
        XCTAssertEqual(try row(.middle).title, "Middle button (button 8)")
        XCTAssertEqual(try row(.middle).picture, .mouse(part: .middle, number: nil))
        XCTAssertEqual(try row(.middle).explanation, "Does what the mouse does on its own.")
        XCTAssertEqual(shown(try row(.middle).pullDown), "Default")
        XCTAssertTrue(try row(.middle).placeButton.isHidden)

        // Without its action the ⌥ binding catches nothing.
        pane.setAction(of: caught.id, to: nil)
        XCTAssertEqual(shown(try row(.back).pullDown), "Default (Back)")
        XCTAssertEqual(try row(.back).pullDown.toolTip, "Goes back in apps that support it.")

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
        XCTAssertEqual(row.explanation, "Good for Gestures or the Shortcut Ring.", "a numbered button there passes through too")

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
        middle.pullDown.onCustomShortcutRecorded?(shortcut, nil)
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
        XCTAssertEqual(panel.explanation, "Good for Gestures or the Shortcut Ring.")
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
                       Content(title: "Back button", subtitle: "Default", part: .back), "a row says what its pull-down says")
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
        XCTAssertEqual(pane.headerView.content.subtitle, "Default (Forward)")
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

    /// "Use Standard Button" has its own Undo ("Undo Which Button"): ⌘Z takes the
    /// conversion back first, the merged row with it, and the row's older change of action
    /// afterwards. Regression: it had none, and the older Undo, which puts back the row's
    /// whole binding, took the standard button back to the Logitech one unseen.
    func testUseStandardButtonHasItsOwnUndoBeforeTheRowsOlderChange() throws {
        deviceName = nil
        let logiBack = binding(1006, "copy")
        let nativeBack = binding(3)
        let other = binding(5, "paste")
        let pane = makePane([nativeBack, logiBack, other])
        let undo = try XCTUnwrap(pane.paneUndoManager)
        undo.groupsByEvent = false
        let missionControl = SystemShortcut.missionControl.identifier

        undo.beginUndoGrouping()
        pane.setAction(of: logiBack.id, to: SystemShortcut.missionControl)
        undo.endUndoGrouping()
        undo.beginUndoGrouping()
        pane.useStandardButton(for: logiBack.id)
        undo.endUndoGrouping()
        let converted = try XCTUnwrap(pane.binding(for: logiBack.id))
        XCTAssertEqual(converted.triggerEvent.code, 3, "the standard Back button")
        XCTAssertEqual(converted.systemShortcutName, missionControl)
        XCTAssertNil(pane.binding(for: nativeBack.id), "the Back button's own binding merged into it")
        XCTAssertEqual(undo.undoMenuItemTitle, "Undo Which Button")

        undo.undo()
        XCTAssertEqual(Options.shared.buttons.binding.map(\.id), [nativeBack.id, logiBack.id, other.id], "the merged row is back")
        let back = try XCTUnwrap(pane.binding(for: logiBack.id))
        XCTAssertEqual(back.triggerEvent.code, 1006, "the conversion is taken back first")
        XCTAssertEqual(back.systemShortcutName, missionControl, "the newer action stays")
        XCTAssertEqual(undo.undoMenuItemTitle, "Undo Change Action")
        undo.undo()
        XCTAssertEqual(Options.shared.buttons.binding, [nativeBack, logiBack, other])

        undo.redo()
        undo.redo()
        XCTAssertEqual(Options.shared.buttons.binding.map(\.id), [logiBack.id, other.id])
        XCTAssertEqual(pane.binding(for: logiBack.id)?.triggerEvent.code, 3)
        XCTAssertEqual(pane.binding(for: logiBack.id)?.systemShortcutName, missionControl)
    }

    /// A numbered button's row says it is an extra one only when nothing more pressing
    /// is to be said: a problem or what the action needs comes first.
    func testTheExtraButtonNoteComesLast() throws {
        scrollKeys = [ScrollHotkey(type: .mouse, code: 7)]
        let bindings = [binding(5), binding(6, SystemShortcut.scrollDash.identifier), binding(7, "copy"), binding(8, "copy"), binding(2000 + 0x005B, "copy")]
        let pane = makePane(bindings)
        XCTAssertEqual(try rows(of: bindings, in: pane).map(\.explanation), [
            "Does what the mouse does on its own.",
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
                       Content(title: "Left Tilt button", subtitle: "Default", part: nil, hint: find))
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
        let undo = try XCTUnwrap(pane.paneUndoManager)
        undo.groupsByEvent = false
        step(undo) { pane.setPlace(of: bindings[1].id, to: .gestureButton) }
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
        // ("+" has its Undo, so it is a step of its own, as an event makes it.)
        step(undo) { pane.onRecordingStopped(recorder, didRecord: true) }
        let added = try XCTUnwrap(pane.rows.last)
        XCTAssertEqual(added.title, "⌘ Gesture button (button 6)")
        XCTAssertEqual(Options.shared.buttons.binding.last?.triggerEvent.mousePart, .gestureButton)

        // Removed and put back: its part comes back with it.
        let removed = bindings[1].id
        undo.beginUndoGrouping()
        pane.removeBinding(id: removed)
        undo.endUndoGrouping()
        undo.undo()
        XCTAssertEqual(pane.binding(for: removed)?.triggerEvent.mousePart, .gestureButton)
        XCTAssertEqual(pane.row(for: removed)?.title, "⌥ Gesture button (button 6)")

        // The last row of its number, removed and put back alone, keeps its part too.
        let five = bindings[2].id
        step(undo) { pane.setPlace(of: five, to: .thumbPanel) }
        undo.beginUndoGrouping()
        pane.removeBinding(id: five)
        undo.endUndoGrouping()
        undo.undo()
        XCTAssertEqual(pane.binding(for: five)?.triggerEvent.mousePart, .thumbPanel)

        // "Not on This List" from any row clears the whole button number.
        step(undo) { pane.setPlace(of: added.binding.id, to: nil) }
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
            "Does what the mouse does on its own.",
            "An extra button on your mouse.",
        ])
        XCTAssertEqual(shown(listed[2].pullDown), "Default", "a numbered button without an action")
        pane.view.layoutSubtreeIfNeeded()
        for row in pane.rows {
            XCTAssertTrue(row.infoButton.isHidden, row.title)
            XCTAssertEqual(row.explanationLabel.textColor, PreferencesGroupedForm.explanationColor(enabled: true))
            XCTAssertTrue(row.pullDown.pullsDown)
            XCTAssertTrue(row.accessory === row.pullDown)
            let width = row.pullDown.alignmentRect(forFrame: row.pullDown.frame).width
            XCTAssertEqual(width, 240, accuracy: 0.5)
        }
        XCTAssertEqual(listed[2].accessibilityLabel(), "Button 5, Does what the mouse does on its own.")
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

    /// On an MX Master 4 the Shortcut Ring and Gesture Navigation pulse only for the
    /// Logitech control: the hint that offers the standard button says it gets no pulse
    /// (in two lines at most); for another action, or on a mouse without haptics, the hint
    /// stays as it is.
    func testTheStandardButtonHintSaysItGetsNoPulseForTheRingOnAnMXMaster4() throws {
        captureStatus = [1006: .standardMouseAliasAvailable]
        let plain = "Can use the standard Back button instead."
        let noPulse = "Can use the standard Back button (no pulse)."
        func hint(_ action: String) throws -> ButtonBindingRow {
            let bindings = [binding(1006, action)]
            let pane = makePane(bindings)
            pane.view.layoutSubtreeIfNeeded()
            return try XCTUnwrap(try rows(of: bindings, in: pane).first)
        }
        let oneLine = NSTextField(labelWithString: "Xg")
        oneLine.font = PreferencesGroupedForm.explanationFont
        let ring = try hint(SystemShortcut.shortcutRing.identifier)
        XCTAssertEqual(ring.explanation, noPulse)
        XCTAssertEqual(ring.note?.tone, .hint)
        XCTAssertLessThanOrEqual(ring.explanationLabel.frame.height, 2 * oneLine.fittingSize.height + 1)
        XCTAssertEqual(try hint(SystemShortcut.mouseGestureNavigation.identifier).explanation, noPulse)
        XCTAssertEqual(try hint("copy").explanation, plain, "no pulse either way")
        deviceName = "MX Master 3S"
        XCTAssertEqual(try hint(SystemShortcut.shortcutRing.identifier).explanation, plain, "a mouse without haptics")
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

    /// On the plain list: "Default" keeps the binding without an action (a button of an MX
    /// Master loses it, `testADefaultRowStoresItsBindingWhenItGetsAnAction`), and says what
    /// the standard Back button then does.
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
        XCTAssertEqual(showSettings.title, "Show in Gestures")
        pullDown.shortcutSelected(showSettings)
        XCTAssertEqual(shownPanes, [GesturesPreferencesViewController.tabIdentifier])

        // The Shortcut Ring: "Show in Shortcut Ring" under it shows the Shortcut Ring pane.
        XCTAssertEqual(pullDown.ringSettingsItem?.isHidden, true)
        let ring = try XCTUnwrap(menu.items.first {
            ($0.representedObject as? SystemShortcut.Shortcut)?.identifier == SystemShortcut.shortcutRing.identifier
        })
        pullDown.shortcutSelected(ring)
        XCTAssertEqual(pullDown.gestureSettingsItem?.isHidden, true)
        let showRing = try XCTUnwrap(pullDown.ringSettingsItem)
        XCTAssertFalse(showRing.isHidden)
        XCTAssertEqual(showRing.title, "Show in Shortcut Ring")
        XCTAssertEqual(menu.index(of: showRing), menu.index(of: ring) + 1, "right under the Shortcut Ring")
        shownPanes = []
        pullDown.shortcutSelected(showRing)
        XCTAssertEqual(shownPanes, [RingPreferencesViewController.tabIdentifier])
        XCTAssertEqual(Options.shared.buttons.binding.first?.systemShortcutName, SystemShortcut.shortcutRing.identifier, "nothing changes")

        let noAction = menu.items[2]
        XCTAssertEqual(noAction.title, "Default (Back)")
        XCTAssertTrue(noAction === pullDown.noActionItem)
        pullDown.shortcutSelected(noAction)
        XCTAssertEqual(Options.shared.buttons.binding.first?.systemShortcutName, "")
        XCTAssertEqual(Options.shared.buttons.binding.first?.isEnabled, false)
        XCTAssertEqual(shown(pullDown), "Default (Back)")
        XCTAssertNil(row.explanation, "the pull-down says it")
        XCTAssertEqual(pullDown.toolTip, "Goes back in apps that support it.")
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
        XCTAssertEqual(pane.headerView.content, ButtonsHeaderContent(title: "⌥ Forward button", subtitle: "Default", part: .forward))
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

    // MARK: - Changing a row, with Undo

    /// A wrong click in a row's menu is no longer for good: Edit › Undo ("Undo Change
    /// Action") puts the action before back, selects the row and gives the list the
    /// keyboard, also while another pane shows (the pane is the target, as for a
    /// removal); Redo makes the change again. "No Action" is a change like any other.
    func testChangingAnActionCanBeUndoneAndRedone() throws {
        deviceName = nil
        let first = binding(3, "copy")
        let second = binding(4, "paste")
        let pane = makePane([first, second])
        let (window, container) = makeWindow(for: pane)
        let undo = try XCTUnwrap(window.undoManager)
        undo.groupsByEvent = false
        let row = try XCTUnwrap(pane.row(for: second.id))

        try step(undo) { row.pullDown.shortcutSelected(try XCTUnwrap(item("selectAll", in: row.pullDown.menu))) }
        XCTAssertEqual(Options.shared.buttons.binding.map(\.systemShortcutName), ["copy", "selectAll"])
        XCTAssertEqual(undo.undoMenuItemTitle, "Undo Change Action")
        pane.list.select(first.id)
        window.makeFirstResponder(nil)

        undo.undo()
        XCTAssertEqual(Options.shared.buttons.binding, [first, second], "the binding as it was, in its place")
        XCTAssertEqual(shown(row.pullDown), "Paste")
        XCTAssertEqual(pane.list.selectedID, AnyHashable(second.id), "the changed row is selected")
        XCTAssertTrue(window.firstResponder === pane.list, "the list has the keyboard")
        XCTAssertEqual(undo.redoMenuItemTitle, "Redo Change Action")
        undo.redo()
        XCTAssertEqual(Options.shared.buttons.binding.map(\.systemShortcutName), ["copy", "selectAll"])

        // "No Action", then Undo while another pane shows.
        try step(undo) { row.pullDown.shortcutSelected(try XCTUnwrap(row.pullDown.noActionItem)) }
        XCTAssertEqual(Options.shared.buttons.binding[1].isEnabled, false)
        XCTAssertEqual(undo.undoMenuItemTitle, "Undo Change Action")
        pane.view.removeFromSuperview()
        undo.undo()
        XCTAssertEqual(Options.shared.buttons.binding[1].systemShortcutName, "selectAll")
        XCTAssertTrue(Options.shared.buttons.binding[1].isEnabled)
        container.addSubview(pane.view)
        undo.undo()
        XCTAssertEqual(Options.shared.buttons.binding, [first, second])

        // Choosing the action the row has already changes nothing and asks for no Undo (a
        // manager that groups by itself: it opens a group only for what is registered).
        let quiet = UndoManager()
        pane.paneUndoManager = quiet
        row.pullDown.shortcutSelected(try XCTUnwrap(item("paste", in: row.pullDown.menu)))
        XCTAssertFalse(quiet.canUndo)
    }

    /// A button of the mouse that read "Default" and got an action: Undo makes it "Default"
    /// again (its binding goes, the row stays and is selected), Redo gives it the action
    /// back with the same binding.
    func testADefaultRowGivenAnActionIsDefaultAgainWithUndo() throws {
        let pane = makePane()
        let undo = try XCTUnwrap(pane.paneUndoManager)
        undo.groupsByEvent = false
        let back = try XCTUnwrap(pane.row(for: ButtonsMousePart.back))
        try step(undo) { back.pullDown.shortcutSelected(try XCTUnwrap(item("copy", in: back.pullDown.menu))) }
        let stored = try XCTUnwrap(Options.shared.buttons.binding.first)
        XCTAssertEqual(undo.undoMenuItemTitle, "Undo Change Action")

        undo.undo()
        XCTAssertTrue(Options.shared.buttons.binding.isEmpty)
        XCTAssertTrue(pane.row(for: ButtonsMousePart.back) === back, "the same row")
        XCTAssertTrue(back.isDefault)
        XCTAssertEqual(shown(back.pullDown), "Default (Back)")
        XCTAssertEqual(pane.list.selectedID, AnyHashable(ButtonsMousePart.back))
        undo.redo()
        XCTAssertEqual(Options.shared.buttons.binding, [stored])
        XCTAssertEqual(shown(back.pullDown), "Copy")
        XCTAssertEqual(pane.list.selectedID, AnyHashable(ButtonsMousePart.back))
    }

    /// "−" and Delete on a button of the mouse with an action clear it ("Clear Action"):
    /// the row stays and reads "Default"; Undo gives the action back. On a "Default" row
    /// "−" is off and Delete does nothing; the other rows are still removed.
    func testMinusAndDeleteClearAButtonOfTheMouse() throws {
        let other = binding(5, "paste", modifiers: option)
        let backBinding = binding(3, "copy")
        let pane = makePane([backBinding, other])
        let (window, _) = makeWindow(for: pane)
        let undo = try XCTUnwrap(window.undoManager)
        undo.groupsByEvent = false
        let back = try XCTUnwrap(pane.row(for: ButtonsMousePart.back))
        XCTAssertTrue(back.isRemovable)
        pane.list.select(ButtonsMousePart.back)
        XCTAssertTrue(pane.list.removeButton.isEnabled)
        XCTAssertEqual(pane.list.removeButton.accessibilityLabel(), "Clear Action")

        step(undo) { pane.list.removeButton.performClick(nil) }
        XCTAssertEqual(Options.shared.buttons.binding, [other], "only its binding goes")
        XCTAssertTrue(pane.row(for: ButtonsMousePart.back) === back)
        XCTAssertTrue(back.isDefault)
        XCTAssertFalse(back.isRemovable)
        XCTAssertEqual(pane.list.selectedID, AnyHashable(ButtonsMousePart.back), "still selected")
        XCTAssertFalse(pane.list.removeButton.isEnabled, "nothing left to clear")
        XCTAssertEqual(undo.undoMenuItemTitle, "Undo Clear Action")

        undo.undo()
        XCTAssertEqual(Options.shared.buttons.binding, [backBinding, other], "back in its place")
        XCTAssertEqual(shown(back.pullDown), "Copy")
        XCTAssertTrue(pane.list.removeButton.isEnabled)

        // Delete, while the list has the keyboard.
        window.makeFirstResponder(pane.list)
        try step(undo) { pane.list.keyDown(with: try key("\u{7F}", keyCode: 51)) }
        XCTAssertEqual(Options.shared.buttons.binding, [other])
        XCTAssertEqual(undo.undoMenuItemTitle, "Undo Clear Action")
        let quiet = UndoManager()
        pane.paneUndoManager = quiet
        pane.list.keyDown(with: try key("\u{7F}", keyCode: 51))
        XCTAssertEqual(Options.shared.buttons.binding, [other], "a Default row: Delete does nothing")
        XCTAssertFalse(quiet.canUndo, "and asks for no Undo")
        pane.paneUndoManager = nil
        undo.undo()
        XCTAssertEqual(Options.shared.buttons.binding, [backBinding, other])

        // Any other row is removed, as before.
        pane.list.select(other.id)
        XCTAssertEqual(pane.list.removeButton.accessibilityLabel(), "Remove")
        step(undo) { pane.list.removeButton.performClick(nil) }
        XCTAssertEqual(Options.shared.buttons.binding, [backBinding])
        XCTAssertEqual(undo.undoMenuItemTitle, "Undo Remove Button")
    }

    /// The name or icon of a row's recorded keys changed: "Undo Rename" puts the one
    /// before back. Other keys recorded are a change of the action.
    func testRenamingRecordedKeysCanBeUndone() throws {
        deviceName = nil
        let keys = "custom::40:1048576"
        let find = ShortcutLabel(name: "Find", icon: nil)
        let original = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 5, modifiers: 0, deviceFilter: nil),
            systemShortcutName: keys, isEnabled: true, label: find
        )
        let pane = makePane([original])
        let undo = try XCTUnwrap(pane.paneUndoManager)
        undo.groupsByEvent = false
        let row = try XCTUnwrap(pane.row(for: original.id))

        step(undo) { row.pullDown.onCustomShortcutRecorded?(keys, ShortcutLabel(name: "Search", icon: nil)) }
        XCTAssertEqual(Options.shared.buttons.binding.first?.label?.name, "Search")
        XCTAssertEqual(undo.undoMenuItemTitle, "Undo Rename")
        step(undo) { row.pullDown.onCustomShortcutRecorded?("custom::41:1048576", ShortcutLabel(name: "Search", icon: nil)) }
        XCTAssertEqual(undo.undoMenuItemTitle, "Undo Change Action")

        undo.undo()
        XCTAssertEqual(Options.shared.buttons.binding.first?.systemShortcutName, keys)
        undo.undo()
        XCTAssertEqual(Options.shared.buttons.binding, [original])
        XCTAssertEqual(Options.shared.buttons.binding.first?.label, find)
        XCTAssertEqual(pane.list.selectedID, AnyHashable(original.id))
        XCTAssertEqual(undo.redoMenuItemTitle, "Redo Rename")
    }

    /// "Which Button Is This?": Undo ("Undo Which Button") puts every row of the button
    /// number back where it was said to be, with the row it was asked of selected.
    func testWhichButtonCanBeUndone() throws {
        let gesture = binding(6, SystemShortcut.mouseGestureNavigation.identifier)
        let withOption = binding(6, "copy", modifiers: option)
        let five = binding(5, "copy")
        let pane = makePane([gesture, withOption, five])
        let undo = try XCTUnwrap(pane.paneUndoManager)
        undo.groupsByEvent = false

        step(undo) { pane.setPlace(of: withOption.id, to: .gestureButton) }
        XCTAssertEqual(Options.shared.buttons.binding.map(\.triggerEvent.mousePart), [.gestureButton, .gestureButton, nil])
        XCTAssertEqual(pane.row(for: gesture.id)?.id, AnyHashable(ButtonsMousePart.gesture))
        XCTAssertEqual(undo.undoMenuItemTitle, "Undo Which Button")
        pane.list.select(nil)

        undo.undo()
        XCTAssertEqual(Options.shared.buttons.binding.map(\.triggerEvent.mousePart), [nil, nil, nil])
        XCTAssertEqual(pane.row(for: gesture.id)?.id, AnyHashable(gesture.id), "below again, as a numbered button")
        XCTAssertEqual(pane.list.selectedID, AnyHashable(withOption.id))
        undo.redo()
        XCTAssertEqual(Options.shared.buttons.binding.map(\.triggerEvent.mousePart), [.gestureButton, .gestureButton, nil])
        XCTAssertEqual(undo.undoMenuItemTitle, "Undo Which Button")
    }

    /// The change a row's Undo holds touches only its own bindings: one removed meanwhile
    /// stays removed, one added meanwhile stays, and a binding to put back whose trigger is
    /// in the list again stays out.
    func testARowChangeTouchesOnlyItsOwnBindings() throws {
        let a = binding(3, "copy")
        let b = binding(4, "paste")
        let changedA = ButtonBinding(id: a.id, triggerEvent: a.triggerEvent, systemShortcutName: "selectAll", isEnabled: true, createdAt: a.createdAt)
        let sameTrigger: (ButtonBinding, ButtonBinding) -> Bool = { $0.triggerEvent == $1.triggerEvent }

        let change = ButtonRowChange(kind: .action, states: [.init(id: a.id, binding: a, index: 0)])
        let added = binding(5, "copy")
        let result = try XCTUnwrap(change.applied(to: [changedA, b, added], sameTrigger: sameTrigger))
        XCTAssertEqual(result.bindings, [a, b, added])
        XCTAssertEqual(result.replaced, [.init(id: a.id, binding: changedA, index: 0)])
        XCTAssertNil(change.applied(to: [a, b], sameTrigger: sameTrigger), "nothing to change")

        // Put back (a cleared button), unless its trigger is there again.
        let back = ButtonRowChange(kind: .clear, states: [.init(id: a.id, binding: a, index: 0)])
        XCTAssertEqual(try XCTUnwrap(back.applied(to: [b], sameTrigger: sameTrigger)).bindings, [a, b])
        let again = binding(3, "undo")
        XCTAssertNil(back.applied(to: [b, again], sameTrigger: sameTrigger), "recorded again meanwhile: that one stays")

        // Taken out (an action given to a Default row), its Redo puts it back.
        let out = ButtonRowChange(kind: .action, states: [.init(id: a.id, binding: nil, index: 1)])
        let removed = try XCTUnwrap(out.applied(to: [b, a], sameTrigger: sameTrigger))
        XCTAssertEqual(removed.bindings, [b])
        XCTAssertEqual(removed.replaced, [.init(id: a.id, binding: a, index: 1)])

        // Where a numbered button is counts, though `==` leaves it out.
        let placed = a.replacingTriggerEvent(a.triggerEvent.placed(at: .gestureButton))
        XCTAssertEqual(placed, a)
        XCTAssertFalse(ButtonRowChange.isSame(placed, a))
        XCTAssertNotNil(ButtonRowChange(kind: .whichButton, states: [.init(id: a.id, binding: a, index: 0)])
            .applied(to: [placed], sameTrigger: sameTrigger))

        // What a change is called.
        let labelled = ButtonBinding(triggerEvent: a.triggerEvent, systemShortcutName: "custom::40:1048576", isEnabled: true, label: ShortcutLabel(name: "Find", icon: nil))
        XCTAssertEqual(ButtonRowChange.Kind.of(labelled, to: labelled.labelled(nil)), .rename)
        XCTAssertEqual(ButtonRowChange.Kind.of(a, to: changedA), .action)
        XCTAssertEqual(ButtonRowChange.Kind.rename.actionName, "Rename")
    }

    // MARK: - The action menu

    func testTheActionMenuIsGroupedAndNamedPlainly() throws {
        let pullDown = ButtonActionPullDown(binding: binding(1000, "copy"))
        let menu = try XCTUnwrap(pullDown.menu)
        let titles = menu.items.map(\.title)
        XCTAssertEqual(menu.items[2].title, "Default", "a row of Buttons: the button does what it does by itself")
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
        // The last group: Gesture Navigation and "Show in Gestures", the Shortcut Ring and
        // "Show in Shortcut Ring" (both hidden: not the action), Open App or File…,
        // Keyboard Shortcut….
        let last = Array(menu.items.suffix(6))
        XCTAssertTrue(menu.items[menu.items.count - 7].isSeparatorItem)
        XCTAssertEqual(last.map(\.title), [
            "Gesture Navigation", "Show in Gestures", "Shortcut Ring", "Show in Shortcut Ring",
            "Open App or File…", "Keyboard Shortcut…",
        ])
        XCTAssertTrue(last[1].isHidden)
        XCTAssertTrue(last[3].isHidden)

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
        XCTAssertEqual(try rows(of: decoded, in: pane).map { shown($0.pullDown) }, ["Gesture Navigation", "⌥⌘K", "Calculator", "Default"])
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

    // MARK: - "Default" on every row (round 2, 23)

    /// A row without an action reads "Default" where its press passes through, in its
    /// pull-down, its menu and on the card: what the button then does in parentheses only
    /// where that is certain (a standard button pressed by itself), its sentence in the
    /// tooltip and no line; a button whose effect is not certain says "Does what the mouse
    /// does on its own."; a key "Does what the key does on its own.". Where the press does
    /// not pass through it reads "No Action": ⌥ Forward runs the action of its twin under
    /// the Logitech code, and the plain Logitech Forward is caught for ⌥ and does nothing.
    /// A plain mouse (no drawing) and an MX Master's "Other buttons and keys" alike;
    /// nothing is stored by showing it.
    func testEveryRowWithoutAnActionReadsDefault() throws {
        deviceName = nil
        // (⌥ and the Logitech Forward button keep that control with Scrollio.)
        let caught = binding(1007, "copy", modifiers: option)
        let bindings = [
            binding(3), binding(4, modifiers: option), binding(6), binding(40, modifiers: control, type: .keyboard),
            binding(1007), caught, binding(2, "copy"),
        ]
        let pane = makePane(bindings)
        let listed = try rows(of: bindings, in: pane)
        XCTAssertEqual(listed.map { shown($0.pullDown) }, [
            "Default (Back)", "No Action", "Default", "Default", "No Action", "Copy", "Copy",
        ])
        XCTAssertEqual(listed.map { $0.pullDown.noActionItem?.title }, [
            "Default (Back)", "No Action", "Default", "Default", "No Action", "Default", "Default (Middle Click)",
        ], "the item says what choosing it gives")
        XCTAssertEqual(listed.map(\.explanation), [
            nil,
            "A press runs Copy.",
            "Does what the mouse does on its own.",
            "Does what the key does on its own.",
            "Scrollio keeps it for another row, so a press does nothing.",
            nil,
            nil,
        ])
        XCTAssertEqual(listed.map(\.pullDown.toolTip), ["Goes back in apps that support it.", nil, nil, nil, nil, nil, nil])
        XCTAssertNil(listed[4].pullDown.toolTip, "the Logitech Forward button is caught for ⌥: no claim")
        XCTAssertEqual(listed.map(\.defaultTitle), ["Default (Back)", "No Action", "Default", "Default", "No Action", nil, nil])
        for (row, expected) in zip(listed.prefix(5), ["Default (Back)", "No Action", "Default", "Default", "No Action"]) {
            pane.list.select(row.id)
            XCTAssertEqual(pane.headerView.content.subtitle, expected, row.title)
        }
        XCTAssertEqual(Options.shared.buttons.binding, bindings, "showing stores nothing")

        // A row that gets "Default" keeps its binding without an action, and says so.
        let middle = listed[6]
        middle.pullDown.shortcutSelected(try XCTUnwrap(middle.pullDown.noActionItem))
        XCTAssertEqual(Options.shared.buttons.binding.last?.systemShortcutName, "")
        XCTAssertEqual(shown(middle.pullDown), "Default (Middle Click)")
        XCTAssertEqual(middle.pullDown.toolTip, "Middle click.")
        XCTAssertEqual(middle.pullDown.accessibilityHelp(), "Middle click.")
    }

    /// What "Default" names, by trigger (`ButtonsMousePart.defaultEffect`): the standard
    /// middle, back and forward buttons and the mode shift button pressed by themselves;
    /// nothing for a key, modifier keys, a numbered button (also one said to be on a part),
    /// another part, or a control caught for another binding, except that an app's own
    /// "Default" sends the standard button even then (not the mode shift's switch).
    func testDefaultNamesWhatTheButtonDoesOnlyWhereThatIsCertain() {
        func title(
            _ code: UInt16, modifiers: UInt = 0, type: EventType = .mouse, caught: Bool = false, own: Bool = false,
            placed: PlacedMousePart? = nil
        ) -> String {
            let trigger = RecordedEvent(type: type, code: code, modifiers: modifiers, deviceFilter: nil, mousePart: placed)
            return ButtonsMousePart.defaultTitle(effect: ButtonsMousePart.defaultEffect(of: trigger, isCaught: caught, isAppsOwn: own))
        }
        let logi = { LogiCenter.shared.scrollioCode(for: $0) }
        XCTAssertEqual(title(2), "Default (Middle Click)")
        XCTAssertEqual(title(3), "Default (Back)")
        XCTAssertEqual(title(4), "Default (Forward)")
        XCTAssertEqual(title(logi(.back)), "Default (Back)")
        XCTAssertEqual(title(logi(.modeShift)), "Default (Switch Wheel Mode)")
        XCTAssertEqual(title(logi(.gesture)), "Default")
        XCTAssertEqual(title(logi(.thumbPanel)), "Default")
        XCTAssertEqual(title(3, modifiers: option), "Default", "the app gets the press with ⌥")
        XCTAssertEqual(title(6), "Default", "a numbered button")
        XCTAssertEqual(title(6, placed: .backButton), "Default", "said to be Back, it still sends its number")
        XCTAssertEqual(title(40, modifiers: control, type: .keyboard), "Default", "a key")
        XCTAssertEqual(title(logi(.back), caught: true), "Default", "the plain press reaches only Scrollio")
        XCTAssertEqual(title(logi(.back), caught: true, own: true), "Default (Back)", "an app's own Default sends Back")
        XCTAssertEqual(title(logi(.modeShift), caught: true, own: true), "Default", "never the mode shift's switch")
        XCTAssertEqual(ButtonsMousePart.pointerSpeed.defaultEffectKey, nil, "known from Logitech's description only")
    }

    // MARK: - "Default" only where a press passes through (round 2 fix Y1, Y2, Y5)

    /// A row without an action says what a press of it really does, by the input side's
    /// ranking and its catch of a Logitech control: ⌥ Back while plain Back runs Mission
    /// Control runs Mission Control (a button bound without modifier keys runs with them,
    /// the binding without an action is skipped): "No Action", "A press runs Mission
    /// Control."; ⌥ Gesture and the plain gesture button while ⌃ Gesture runs Copy reach
    /// only Scrollio and run nothing: "No Action", "Scrollio keeps it …".
    func testADefaultRowSaysWhatAPressOfItReallyDoes() throws {
        let gesture = LogiCenter.shared.scrollioCode(for: .gesture)
        let plainBack = binding(3, SystemShortcut.missionControl.identifier)
        let optionBack = binding(3, modifiers: option)
        let controlGesture = binding(gesture, SystemShortcut.copy.identifier, modifiers: control)
        let optionGesture = binding(gesture, modifiers: option)
        let bindings = [plainBack, optionBack, controlGesture, optionGesture]

        // The input side's ranking: ⌥ Back goes by the plain binding.
        let press = InputEvent(type: .mouse, code: 3, modifiers: .maskAlternate, phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(ButtonUtils.bestMatch(among: bindings, for: press)?.id, plainBack.id)

        let pane = makePane(bindings)
        let listed = try rows(of: [optionBack, optionGesture], in: pane)
        XCTAssertEqual(listed.map { shown($0.pullDown) }, ["No Action", "No Action"])
        XCTAssertEqual(listed.map { $0.pullDown.noActionItem?.title }, ["No Action", "No Action"])
        XCTAssertEqual(listed.map(\.explanation), [
            "A press runs Mission Control.",
            "Scrollio keeps it for another row, so a press does nothing.",
        ])
        XCTAssertEqual(listed.map(\.pullDown.toolTip), [nil, nil])
        XCTAssertEqual(listed.map(\.note?.tone), [.plain, .plain])
        // Each line fits the row's two lines.
        pane.view.layoutSubtreeIfNeeded()
        let oneLine = NSTextField(labelWithString: "Xg")
        oneLine.font = PreferencesGroupedForm.explanationFont
        for row in listed {
            XCTAssertLessThanOrEqual(row.explanationLabel.frame.height, 2 * oneLine.fittingSize.height + 1, row.explanation ?? "")
        }

        // The gesture button's own row (no binding): caught for ⌃, its plain press does
        // nothing either. The Back button's row has its action.
        let gestureRow = try XCTUnwrap(pane.row(for: AnyHashable(ButtonsMousePart.gesture)))
        XCTAssertEqual(shown(gestureRow.pullDown), "No Action")
        XCTAssertEqual(gestureRow.explanation, "Scrollio keeps it for another row, so a press does nothing.")
        XCTAssertEqual(shown(try XCTUnwrap(pane.row(for: AnyHashable(ButtonsMousePart.back))).pullDown), "Mission Control")

        // ⌃ Gesture's own "Default" item: what choosing it gives (nothing then catches it).
        XCTAssertEqual(try XCTUnwrap(pane.row(for: controlGesture.id)).pullDown.noActionItem?.title, "Default")

        // Without ⌃ Gesture's action the gesture button is the mouse's again: "Default".
        try XCTUnwrap(pane.row(for: controlGesture.id)).pullDown.shortcutSelected(
            try XCTUnwrap(pane.row(for: controlGesture.id)?.pullDown.noActionItem)
        )
        XCTAssertEqual(shown(gestureRow.pullDown), "Default")
        XCTAssertEqual(gestureRow.explanation, "Good for Gestures or the Shortcut Ring.", "it passes through again")
        XCTAssertEqual(shown(try XCTUnwrap(pane.row(for: optionGesture.id)).pullDown), "Default")
    }

    /// A Logitech key under Scrolling › While you hold a key keeps its button with Scrollio
    /// (the mouse is asked for it): its row without an action is no "Default (Back)" but
    /// "No Action". A standard one only listens: "(Back)" stays.
    func testAHoldKeyOnTheLogitechButtonCatchesIt() throws {
        let back = LogiCenter.shared.scrollioCode(for: .back)
        scrollKeys = [ScrollHotkey(type: .mouse, code: back)]
        let pane = makePane()
        let row = try XCTUnwrap(pane.row(for: AnyHashable(ButtonsMousePart.back)))
        XCTAssertEqual(shown(row.pullDown), "No Action")
        XCTAssertEqual(row.note?.kind, .alsoScrollKey, "the line says where the button went")
        XCTAssertNil(row.pullDown.toolTip)

        scrollKeys = [ScrollHotkey(type: .mouse, code: 3)]
        pane.reload()
        XCTAssertEqual(shown(row.pullDown), "Default (Back)")
        XCTAssertEqual(row.note?.kind, .alsoScrollKey)

        // The keys of every app with Scrolling settings of its own count: the mouse is asked
        // for all of them.
        let scroll = OPTIONS_SCROLL_DEFAULT()
        scroll.dash = ScrollHotkey(type: .mouse, code: back)
        let own = Application(path: "/Applications/Safari.app")
        own.inherit = false
        own.scroll.slow = ScrollHotkey(type: .mouse, code: 1006)
        let following = Application(path: "/Applications/Notes.app")
        following.scroll.block = ScrollHotkey(type: .mouse, code: 1007)
        let keys = ButtonDefaultOutcome.holdKeysThatCatch(
            general: scroll, applications: EnhanceArray(withArray: [own, following], matchKey: "path")
        )
        XCTAssertEqual(
            keys.filter { $0.type == .mouse }.map(\.code), [back, 1006], "not an app that uses the Scrolling settings"
        )
    }

    /// VoiceOver's help of a row's pull-down follows the row, which is reused: the sentence
    /// of "Default (Back)" while it has no line, nothing once it has an action, the
    /// sentence again at "Default"; the thumb wheel's row: the sentence of "Default (Scroll
    /// Sideways)", then the line of the function chosen (round 2 fix Y7: already so; the
    /// row's line resets the help whenever it is set).
    func testThePullDownsHelpFollowsTheReusedRow() throws {
        let pane = makePane()
        let back = try XCTUnwrap(pane.row(for: AnyHashable(ButtonsMousePart.back)))
        XCTAssertEqual(back.pullDown.accessibilityHelp(), "Goes back in apps that support it.")
        pane.setAction(ofRow: AnyHashable(ButtonsMousePart.back), to: SystemShortcut.copy)
        XCTAssertTrue(pane.row(for: AnyHashable(ButtonsMousePart.back)) === back, "the same row")
        XCTAssertNil(back.explanation)
        XCTAssertNil(back.pullDown.accessibilityHelp())
        pane.setAction(ofRow: AnyHashable(ButtonsMousePart.back), to: nil)
        XCTAssertEqual(back.pullDown.accessibilityHelp(), "Goes back in apps that support it.")

        let wheel = try XCTUnwrap(pane.thumbWheelRow)
        let sideways = try XCTUnwrap(wheel.pullDown.accessibilityHelp())
        pane.setThumbWheelFunction(.zoom)
        XCTAssertTrue(pane.thumbWheelRow === wheel)
        XCTAssertNotEqual(wheel.pullDown.accessibilityHelp(), sideways)
        XCTAssertEqual(wheel.pullDown.accessibilityHelp(), wheel.explanation)
    }

    /// A key without an action passes its press through: "Default", "Does what the key does
    /// on its own.", not a call to choose something.
    func testAKeyWithoutAnActionSaysItDoesWhatItDoes() throws {
        let key = binding(40, modifiers: control, type: .keyboard)
        let pane = makePane([key])
        let row = try XCTUnwrap(pane.row(for: key.id))
        XCTAssertEqual(shown(row.pullDown), "Default")
        XCTAssertEqual(row.explanation, "Does what the key does on its own.")
        XCTAssertEqual(row.note?.kind, .noAction)
        XCTAssertEqual(row.note?.tone, .plain)
    }

    // MARK: - "Show in Buttons" lands on the row its line names (Q13)

    /// `selectBinding(id:)` selects the row of a stored binding (a button of the mouse: its
    /// part's row), lights it on the card and gives the list the keyboard. An app's
    /// Gestures part whose line names the second of two buttons that run the gestures (the
    /// app gave the first something else) leads there, not to the first.
    func testShowInButtonsSelectsTheRowTheAppsLineNames() throws {
        let gestures = SystemShortcut.mouseGestureNavigation.identifier
        let first = binding(3, gestures)
        let second = binding(1000, gestures)
        let pane = makePane([first, second])
        let (window, _) = makeWindow(for: pane)
        XCTAssertTrue(pane.selectBinding(id: second.id))
        XCTAssertEqual(pane.list.selectedID, AnyHashable(ButtonsMousePart.gesture))
        XCTAssertEqual(pane.headerView.content.title, "Gesture button")
        XCTAssertTrue(window.firstResponder === pane.list)
        XCTAssertFalse(pane.selectBinding(id: UUID()), "Buttons has no such binding")
        XCTAssertEqual(pane.list.selectedID, AnyHashable(ButtonsMousePart.gesture))
        pane.selectGestureButton()
        XCTAssertEqual(pane.list.selectedID, AnyHashable(ButtonsMousePart.back), "the first, as before")

        let calculator = Application(path: "/System/Applications/Calculator.app")
        calculator.setOwnButtonBindings([binding(3, "copy")])
        let row = ApplicationTriggerRow.make(.gestureNavigation, application: calculator, general: [first, second])
        XCTAssertEqual(row.destination, .buttonsPane)
        XCTAssertEqual(row.buttonsBindingID, second.id, "the one the line names")
        // The app's own binding of the same trigger and action: Buttons' binding is its row.
        calculator.setOwnButtonBindings([binding(3, gestures)])
        XCTAssertEqual(ApplicationTriggerRow.make(.gestureNavigation, application: calculator, general: [first, second]).buttonsBindingID, first.id)
        calculator.setOwnButtonBindings([])
        XCTAssertEqual(ApplicationTriggerRow.make(.shortcutRing, application: calculator, general: [binding(4, SystemShortcut.shortcutRing.identifier)]).destination,
                       .buttonsPane)
    }

    // MARK: - What a free Gesture button and Thumb panel are good for (round 4, D2)

    private var gesturesAction: String { SystemShortcut.mouseGestureNavigation.identifier }
    private var ringAction: String { SystemShortcut.shortcutRing.identifier }

    /// The lines of the Gesture button's and the Thumb panel's rows on an MX Master 4.
    private func freeLines(_ pane: PreferencesButtonsViewController) -> [String?] {
        return [ButtonsMousePart.gesture, .thumbPanel].map { pane.row(for: $0)?.explanation }
    }

    /// While nothing of Buttons runs the gestures or opens the ring, the free Gesture
    /// button and Thumb panel name what they are good for: only what no button does yet,
    /// then the old line. A line only: plain, no sign, no ⓘ, "Default" stays and nothing
    /// is stored.
    func testAFreeGestureButtonAndThumbPanelSayWhatTheyAreGoodFor() throws {
        let both = "Good for Gestures or the Shortcut Ring."
        let pane = makePane()
        let (window, _) = makeWindow(for: pane)
        XCTAssertEqual(freeLines(pane), [both, both])
        XCTAssertEqual(text("buttons-default-good-for-both"), both)
        XCTAssertTrue(both.contains(text("gestures-tab-title")) && both.contains(text("ring-tab-title")), "the sidebar's names")
        for part in [ButtonsMousePart.gesture, .thumbPanel] {
            let row = try XCTUnwrap(pane.row(for: part))
            XCTAssertEqual(row.note?.kind, .goodFor([.gestures, .ring]))
            XCTAssertEqual(row.note?.tone, .plain)
            XCTAssertEqual(row.note?.hasDetails, false)
            XCTAssertTrue(row.infoButton.isHidden, "no ⓘ")
            XCTAssertEqual(row.explanationLabel.stringValue, both, "plain text: no light bulb before it")
            XCTAssertEqual(row.explanationLabel.textColor, PreferencesGroupedForm.explanationColor(enabled: true))
            XCTAssertEqual(shown(row.pullDown), "Default")
            XCTAssertNil(row.pullDown.toolTip)
            XCTAssertTrue(row.isDefault && !row.isStored)
        }
        XCTAssertEqual(pane.row(for: ButtonsMousePart.gesture)?.accessibilityLabel(), "Gesture button, \(both)")
        XCTAssertEqual(pane.row(for: ButtonsMousePart.thumbPanel)?.accessibilityLabel(), "Thumb panel, \(both)")
        // The line fits the row (one line of the two it may take).
        window.contentView?.layoutSubtreeIfNeeded()
        let oneLine = NSTextField(labelWithString: "Xg")
        oneLine.font = PreferencesGroupedForm.explanationFont
        let label = try XCTUnwrap(pane.row(for: ButtonsMousePart.gesture)).explanationLabel
        XCTAssertLessThanOrEqual(label.frame.height, 2 * oneLine.fittingSize.height + 1)
        XCTAssertTrue(Options.shared.buttons.binding.isEmpty, "showing the line stores nothing")

        // Something opens the ring already (a button, or a key): only Gestures is named.
        XCTAssertEqual(freeLines(makePane([binding(3, ringAction)])), ["Good for Gestures.", "Good for Gestures."])
        XCTAssertEqual(
            freeLines(makePane([binding(40, ringAction, modifiers: control, type: .keyboard)])),
            ["Good for Gestures.", "Good for Gestures."], "a key that opens the ring counts as taken"
        )
        // A button runs the gestures already: only the ring.
        let ringOnly = makePane([binding(3, gesturesAction)])
        XCTAssertEqual(freeLines(ringOnly), ["Good for the Shortcut Ring.", "Good for the Shortcut Ring."])
        XCTAssertEqual(ringOnly.row(for: ButtonsMousePart.thumbPanel)?.note?.kind, .goodFor(.ring))
        // A key cannot run the gestures: they still want a button.
        XCTAssertEqual(freeLines(makePane([binding(40, gesturesAction, type: .keyboard), binding(3, ringAction)])),
                       ["Good for Gestures.", "Good for Gestures."])
        // Both have their button: the line every such button had.
        let neither = makePane([binding(3, gesturesAction), binding(4, ringAction)])
        XCTAssertEqual(freeLines(neither), ["Does what the mouse does on its own.", "Does what the mouse does on its own."])
        XCTAssertEqual(neither.row(for: ButtonsMousePart.gesture)?.note?.kind, .defaultAction)

        // The Gesture button takes the gestures: its own line, and the Thumb panel names the ring.
        let gesture = LogiCenter.shared.scrollioCode(for: .gesture)
        let taken = makePane([binding(gesture, gesturesAction)])
        XCTAssertEqual(freeLines(taken), ["Hold and move the mouse. Set the directions under Gestures.", "Good for the Shortcut Ring."])

        // The three lines and what they name.
        XCTAssertEqual(ButtonRowNote.Uses([.gestures, .ring]).lineKey, "buttons-default-good-for-both")
        XCTAssertEqual(ButtonRowNote.Uses.gestures.lineKey, "buttons-default-good-for-gestures")
        XCTAssertEqual(ButtonRowNote.Uses.ring.lineKey, "buttons-default-good-for-ring")
        XCTAssertNil(ButtonRowNote.Uses([]).lineKey)
        XCTAssertEqual(text("buttons-default-good-for-gestures"), "Good for Gestures.")
        XCTAssertEqual(text("buttons-default-good-for-ring"), "Good for the Shortcut Ring.")
    }

    /// The hint is only for a row whose press passes through to the mouse with no certain
    /// effect (`ButtonDefaultOutcome`): not for a row with an action, one Scrollio keeps
    /// for another row, a key of While you hold a key, another part, or a row under "Other
    /// buttons and keys".
    func testTheHintIsOnlyForARowThatPassesThrough() throws {
        let gesture = LogiCenter.shared.scrollioCode(for: .gesture)
        let free: ButtonRowNote.Uses = [.gestures, .ring]
        let trigger = RecordedEvent(type: .mouse, code: gesture, modifiers: 0, deviceFilter: nil)
        func kind(
            _ part: ButtonsMousePart, _ outcome: ButtonDefaultOutcome, keys: [ScrollHotkey] = [], free: ButtonRowNote.Uses = [.gestures, .ring]
        ) -> ButtonRowNote.Kind? {
            return ButtonRowNote.makeDefault(for: part, trigger: trigger, scrollHoldKeys: keys, outcome: outcome, free: free)?.kind
        }
        XCTAssertEqual(kind(.gesture, .passes(nil)), .goodFor(free))
        XCTAssertEqual(kind(.thumbPanel, .passes(nil)), .goodFor(free))
        XCTAssertEqual(kind(.gesture, .passes(nil), free: []), .defaultAction, "nothing is free: the old line")
        XCTAssertEqual(kind(.gesture, .caught), .doesNothing)
        XCTAssertEqual(kind(.gesture, .runs(binding(3, "copy"))), .runsAnother)
        XCTAssertEqual(kind(.gesture, .passes(nil), keys: [ScrollHotkey(type: .mouse, code: gesture)]), .alsoScrollKey)
        XCTAssertEqual(kind(.pointerSpeed, .passes(nil)), .defaultAction, "it does something useful by itself")
        XCTAssertEqual(kind(.middle, .passes(nil)), .defaultAction, "a numbered button on another part")
        XCTAssertNil(kind(.back, .passes(.back)), "Default (Back) has no line")
        XCTAssertEqual(
            ButtonRowNote.makeDefault(for: .gesture, trigger: trigger, scrollHoldKeys: [], outcome: .passes(nil))?.kind, .defaultAction,
            "without the argument (an app's rows never pass it) the old line"
        )

        // In the pane. With an action: the action's own line, or none.
        let withAction = makePane([binding(gesture, "copy")])
        XCTAssertNil(withAction.row(for: ButtonsMousePart.gesture)?.explanation)
        XCTAssertEqual(withAction.row(for: ButtonsMousePart.thumbPanel)?.explanation, "Good for Gestures or the Shortcut Ring.")

        // "⌥ Gesture button" has an action: Scrollio keeps the control, the plain press does
        // nothing. Its row says so, and the ⌥ row under "Other buttons and keys" has no hint.
        let optionGesture = binding(gesture, "copy", modifiers: option)
        let caught = makePane([optionGesture])
        let caughtRow = try XCTUnwrap(caught.row(for: ButtonsMousePart.gesture))
        XCTAssertEqual(shown(caughtRow.pullDown), "No Action")
        XCTAssertEqual(caughtRow.explanation, "Scrollio keeps it for another row, so a press does nothing.")
        XCTAssertEqual(caught.row(for: ButtonsMousePart.thumbPanel)?.explanation, "Good for Gestures or the Shortcut Ring.")

        // A row under "Other buttons and keys" without an action keeps its line.
        let other = binding(gesture, modifiers: option)
        let withOther = makePane([other])
        XCTAssertEqual(try XCTUnwrap(withOther.row(for: other.id)).note?.kind, .defaultAction)
        XCTAssertEqual(withOther.row(for: ButtonsMousePart.gesture)?.explanation, "Good for Gestures or the Shortcut Ring.")

        // The Gesture button is a key of Scrolling › While you hold a key: that line, with its sign.
        scrollKeys = [ScrollHotkey(type: .mouse, code: gesture)]
        let scrollKey = makePane()
        let scrollRow = try XCTUnwrap(scrollKey.row(for: ButtonsMousePart.gesture))
        XCTAssertEqual(scrollRow.note?.kind, .alsoScrollKey)
        XCTAssertEqual(scrollRow.note?.tone, .problem)
        XCTAssertEqual(scrollKey.row(for: ButtonsMousePart.thumbPanel)?.note?.kind, .goodFor(free))
    }

    /// A mouse without those buttons gets no such line: an MX Anywhere 3 and the MX
    /// Vertical (whose top button keeps the old line), a plain mouse (no rows of its own),
    /// and an app's Buttons part, whose rows say what the button does in other apps.
    func testNoHintOnAMouseWithoutThoseButtons() throws {
        func isHint(_ row: ButtonBindingRow) -> Bool {
            if case .goodFor = row.note?.kind { return true }
            return false
        }
        deviceName = "MX Anywhere 3"
        let anywhere = makePane()
        XCTAssertEqual(anywhere.rows.compactMap(\.part), [.middle, .modeShift, .forward, .back])
        XCTAssertEqual(anywhere.rows.map(\.explanation), [nil, nil, nil, nil])

        deviceName = "MX Vertical"
        let vertical = makePane()
        XCTAssertEqual(vertical.rows.compactMap(\.part), [.middle, .pointerSpeed, .forward, .back])
        XCTAssertEqual(vertical.rows.map(\.explanation), [nil, "Does what the mouse does on its own.", nil, nil])
        XCTAssertFalse(vertical.rows.contains(where: isHint))

        deviceName = nil
        let plain = makePane([binding(5), binding(6, "copy")])
        XCTAssertTrue(plain.rows.allSatisfy { $0.part == nil })
        XCTAssertFalse(plain.rows.contains(where: isHint))
        XCTAssertEqual(plain.rows.first?.explanation, "Does what the mouse does on its own.")

        // An app's own "Default" on the Gesture button of an MX Master 4.
        Options.shared.buttons.binding = []
        let gesture = LogiCenter.shared.scrollioCode(for: .gesture)
        let notes = Application(path: "/System/Applications/Notes.app")
        notes.setOwnButtonBindings([ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: gesture, modifiers: 0, deviceFilter: nil), systemShortcutName: "", isEnabled: true
        )])
        let part = ApplicationButtonsViewController(application: notes)
        part.deviceSource = ButtonsDeviceSource(
            captureStatus: { _ in .normal }, deviceName: { "MX Master 4" }, isBusy: { false }, refresh: {}, warnBluetoothButton: { _ in }
        )
        part.holdKeysThatCatch = { [] }
        part.presentMenu = { _, _ in }
        part.openActionMenu = { _ in }
        part.startRecording = { _ in }
        part.stopRecording = {}
        part.presentOpenTarget = { _, _, _ in }
        part.paneUndoManager = UndoManager()
        _ = part.view
        XCTAssertEqual(part.rows.count, 1)
        XCTAssertEqual(part.rows.first?.note?.kind, .everywhere)
        XCTAssertFalse(part.rows.contains(where: isHint))
    }

    /// The line follows what the other rows do: the Thumb panel gets the ring, the Gesture
    /// button's line names only Gestures; Undo names both again, Redo one.
    func testTheHintFollowsUndo() throws {
        let pane = makePane()
        let undo = try XCTUnwrap(pane.paneUndoManager)
        undo.groupsByEvent = false
        let gestureRow = try XCTUnwrap(pane.row(for: ButtonsMousePart.gesture))
        let panel = try XCTUnwrap(pane.row(for: ButtonsMousePart.thumbPanel))
        XCTAssertEqual(freeLines(pane), ["Good for Gestures or the Shortcut Ring.", "Good for Gestures or the Shortcut Ring."])

        try step(undo) { panel.pullDown.shortcutSelected(try XCTUnwrap(item(ringAction, in: panel.pullDown.menu))) }
        XCTAssertEqual(Options.shared.buttons.binding.map(\.systemShortcutName), [ringAction])
        XCTAssertEqual(gestureRow.explanation, "Good for Gestures.", "the other row's line is derived again")
        XCTAssertEqual(gestureRow.accessibilityLabel(), "Gesture button, Good for Gestures.")
        XCTAssertNotEqual(panel.explanation, "Good for Gestures.")
        XCTAssertFalse(gestureRow.isStored, "the hint assigned nothing")

        undo.undo()
        XCTAssertTrue(Options.shared.buttons.binding.isEmpty)
        XCTAssertEqual(freeLines(pane), ["Good for Gestures or the Shortcut Ring.", "Good for Gestures or the Shortcut Ring."])
        undo.redo()
        XCTAssertEqual(gestureRow.explanation, "Good for Gestures.")

        // The Gesture button takes the gestures: nothing is left to name.
        try step(undo) { gestureRow.pullDown.shortcutSelected(try XCTUnwrap(item(gesturesAction, in: gestureRow.pullDown.menu))) }
        XCTAssertEqual(gestureRow.explanation, "Hold and move the mouse. Set the directions under Gestures.")
        undo.undo()
        XCTAssertEqual(gestureRow.explanation, "Good for Gestures.")
    }
}
