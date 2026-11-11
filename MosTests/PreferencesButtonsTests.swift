//
//  PreferencesButtonsTests.swift
//  MosTests
//
//  The Buttons pane: what its rows and its card are called, which part of the mouse a
//  button lights (on the card and in each row's picture), how a button the drawing cannot
//  show is found ("That's …"), the notes under the rows, recording a button (stubbed: no event is
//  recorded or posted), removing with Undo (also from another pane), the keyboard focus,
//  what closes with the pane, the action menu, "Checking buttons…", and that stored
//  bindings load and save unchanged. Nothing is shown on screen and no HID device is
//  touched.
//

import XCTest
@testable import Mos_Debug

final class PreferencesButtonsTests: XCTestCase {

    private var savedBindings: [ButtonBinding] = []
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
        Options.shared.buttons.binding = []
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

    func testTheEmptyList() {
        let pane = makePane()
        XCTAssertTrue(pane.rows.isEmpty)
        XCTAssertEqual(pane.list.emptyRow.title, "No buttons yet")
        XCTAssertEqual(pane.list.emptyRow.explanation, "Click + and press a mouse button to give it an action.")
        XCTAssertTrue(pane.list.emptyRow.superview === pane.list.rowsView)
        XCTAssertFalse(pane.list.removeButton.isEnabled)
        XCTAssertEqual(pane.headerView.content.title, "MX Master 4")
        XCTAssertEqual(pane.headerView.content.subtitle, "No buttons set up yet")
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

    func testLogiCenterTellsTheRoleOfAControl() {
        let center = LogiCenter.shared
        XCTAssertEqual(center.controlRole(forMosCode: 1000), .gesture)
        XCTAssertEqual(center.controlRole(forMosCode: 1001), .modeShift)
        XCTAssertEqual(center.controlRole(forMosCode: 1005), .middle)
        XCTAssertEqual(center.controlRole(forMosCode: 1006), .back)
        XCTAssertEqual(center.controlRole(forMosCode: 2000 + 0x0054), .back)
        XCTAssertEqual(center.controlRole(forMosCode: 1007), .forward)
        XCTAssertEqual(center.controlRole(forMosCode: 2000 + 0x01A0), .thumbPanel)
        XCTAssertNil(center.controlRole(forMosCode: 2000 + 0x005B))
        XCTAssertNil(center.controlRole(forMosCode: 3), "a native button is not a Logitech control")
    }

    /// The MX Master 4's thumb panel lights the thumb rest of the drawing, its gesture
    /// button the front side button: two parts.
    func testTheThumbPanelLightsTheThumbPanelOfTheCard() {
        let panel = binding(2000 + 0x01A0, SystemShortcut.mouseGestureNavigation.identifier)
        let gesture = binding(1000, "copy")
        let pane = makePane([binding(3, "copy"), panel, gesture])
        XCTAssertEqual(pane.headerView.artwork.model, .mxMaster4)
        pane.list.select(panel.id)
        XCTAssertEqual(pane.headerView.content, ButtonsHeaderContent(title: "Thumb panel", subtitle: "Gesture Navigation", part: .thumbPanel))
        XCTAssertEqual(pane.headerView.artwork.emphasis, .thumbPanel)
        XCTAssertEqual(pane.headerView.artwork.highlights[.thumbPanel]?.alphaValue, 1)
        XCTAssertEqual(pane.headerView.artwork.highlights[.gesture]?.alphaValue, 0)
        XCTAssertEqual(pane.headerView.artwork.highlights[.back]?.alphaValue, 0)
        pane.list.select(gesture.id)
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

        pane.list.select(pane.rows[0].id)
        XCTAssertEqual(pane.headerView.content, ButtonsHeaderContent(title: "Back button", subtitle: "Gesture Navigation", part: .back))
        XCTAssertEqual(pane.headerView.artwork.emphasis, .back)
        XCTAssertEqual(pane.headerView.artwork.highlights[.back]?.alphaValue, 1)
        XCTAssertEqual(pane.headerView.artwork.highlights[.left]?.alphaValue, 0)

        pane.list.select(pane.rows[1].id)
        XCTAssertEqual(pane.headerView.content.subtitle, "No action")
        XCTAssertEqual(pane.headerView.artwork.emphasis, .forward)

        pane.list.select(pane.rows[2].id)
        XCTAssertEqual(pane.headerView.content, ButtonsHeaderContent(title: "Gesture button", subtitle: "Copy", part: .gesture))

        pane.list.select(nil)
        XCTAssertNil(pane.headerView.artwork.emphasis)
        XCTAssertEqual(pane.headerView.accessibilityLabel(), "MX Master 4, 2 buttons have actions, Not sure which is which? Click + and press a button.")
        XCTAssertFalse(pane.headerView.hintLabel.isHidden)
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

    /// The owner's MX Master 4 over Bluetooth: Gesture Navigation on Button 6, a shortcut on
    /// Button 5, a screenshot on the mode shift button.
    func testEveryRowShowsWhereItsButtonIs() throws {
        let custom = "custom::21:\(UInt64(CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue))"
        let pane = makePane([
            binding(6, SystemShortcut.mouseGestureNavigation.identifier),
            binding(5, custom),
            binding(1001, SystemShortcut.screenshotSelection.identifier),
            binding(40, "copy", modifiers: control | option, type: .keyboard),
        ])
        XCTAssertEqual(pane.rows.map(\.title), ["Button 6", "Button 5", "Mode shift button", "⌃⌥ K"])
        XCTAssertEqual(pane.rows.map(\.picture), [
            .mouse(part: nil, number: 6), .mouse(part: nil, number: 5), .mouse(part: .modeShift, number: nil), .key,
        ])
        XCTAssertEqual(pane.rows.map(\.explanation), [
            "Hold and move the mouse. Set the directions under Gestures.",
            "An extra button on your mouse.",
            nil,
            nil,
        ])
        XCTAssertEqual(pane.rows[1].accessibilityLabel(), "Button 5, An extra button on your mouse.")
        for row in pane.rows {
            let icon = try XCTUnwrap(row.iconView, row.title)
            XCTAssertEqual(icon.image?.size, ButtonsMouseMiniature.size, row.title)
            XCTAssertEqual(icon.image?.isTemplate, false)
        }

        // Another trigger for the same row ("Use Standard Button"): the picture follows.
        let row = pane.rows[1]
        let old = try XCTUnwrap(pane.binding(for: row.binding.id))
        pane.replaceBinding(ButtonBinding(
            id: old.id, triggerEvent: RecordedEvent(type: .mouse, code: 4, modifiers: 0, deviceFilter: nil),
            systemShortcutName: old.systemShortcutName, isEnabled: true, createdAt: old.createdAt
        ))
        XCTAssertTrue(pane.rows[1] === row)
        XCTAssertEqual(row.picture, .mouse(part: .forward, number: nil))
        XCTAssertNil(row.explanation)
    }

    /// A numbered button's row says it is an extra one only when nothing more pressing
    /// is to be said: a problem or what the action needs comes first.
    func testTheExtraButtonNoteComesLast() {
        scrollKeys = [ScrollHotkey(type: .mouse, code: 7)]
        let pane = makePane([binding(5), binding(6, SystemShortcut.mosScrollDash.identifier), binding(7, "copy"), binding(8, "copy"), binding(2000 + 0x005B, "copy")])
        XCTAssertEqual(pane.rows.map(\.explanation), [
            "Choose what this button does.",
            "Works while you hold the button.",
            "Also set under Scrolling\u{A0}›\u{A0}While\u{A0}you\u{A0}hold\u{A0}a\u{A0}key.",
            "An extra button on your mouse.",
            nil,
        ])
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
            for part in ButtonsMousePart.allCases {
                let bounds = try XCTUnwrap(ButtonsMouseMiniature.shape(of: part, mouse: .mxMaster4, in: frame)).bounds
                // The thumb rest's middle is under a side button: a point of the rest's own.
                let middle = part == .thumbPanel
                    ? NSPoint(x: bounds.minX + bounds.width * 0.3, y: bounds.midY + bounds.height * 0.25)
                    : NSPoint(x: bounds.midX, y: bounds.midY)
                let lit = try pixels(of: .mouse(part: part, number: nil), appearance: appearance)
                XCTAssertLessThan(distance(lit(middle), accent), 0.03, "\(part) lit in \(name.rawValue)")
                if accent.saturationComponent > 0.3 {
                    XCTAssertGreaterThan(distance(unlit(middle), accent), 0.2, "\(part) not lit in \(name.rawValue)")
                }
                XCTAssertTrue(ButtonsMouseMiniature.bodyPath(of: .mxMaster4, in: frame).contains(middle),
                              "\(part) is on the mouse")
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
        let pane = makePane([binding(6, SystemShortcut.mouseGestureNavigation.identifier), binding(1001, "copy")])
        pane.list.select(pane.rows[0].id)
        XCTAssertEqual(pane.headerView.content, Content(title: "Button 6", subtitle: "Gesture Navigation", part: nil, hint: place, number: 6))
        XCTAssertFalse(pane.headerView.hintLabel.isHidden)
        XCTAssertEqual(pane.headerView.hintLabel.stringValue, place)
        XCTAssertEqual(pane.headerView.artwork.badge.number, 6)
        XCTAssertEqual(pane.headerView.artwork.badge.alphaValue, 1)
        XCTAssertNil(pane.headerView.artwork.emphasis)
        XCTAssertEqual(pane.headerView.accessibilityLabel(), "Button 6, Gesture Navigation, \(place)")
        pane.list.select(pane.rows[1].id)
        XCTAssertEqual(pane.headerView.content, Content(title: "Mode shift button", subtitle: "Copy", part: .modeShift))
        XCTAssertTrue(pane.headerView.hintLabel.isHidden)
        XCTAssertEqual(pane.headerView.artwork.badge.alphaValue, 0)
        XCTAssertEqual(pane.headerView.artwork.emphasis, .modeShift)
    }

    /// "+" and a listed numbered button: its row flashes and the card answers "That's
    /// Button 6" with its number by the mouse, for as long as a recorded button shows.
    func testPressingAListedNumberedButtonAfterPlusSaysWhichRowItIs() {
        let pane = makePane([binding(3, "copy"), binding(6, SystemShortcut.mouseGestureNavigation.identifier)])
        let recorder = KeyRecorder()
        pane.beginAddingBinding()
        pane.onRecordingStarted(recorder)
        let event = mouseEvent(6)
        XCTAssertFalse(pane.validateRecordedEvent(recorder, event: event))
        pane.onEventRecorded(recorder, didRecordEvent: event, isDuplicate: true)
        XCTAssertEqual(pane.list.selectedID, pane.rows[1].id)
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
        let pane = makePane([binding(2000 + 0x01A0, "copy"), panelAnswer, binding(6)])
        let six = pane.rows[2].binding.id
        XCTAssertEqual(pane.headerView.artwork.model, .mxMaster4)
        XCTAssertEqual(pane.rows.map(\.mouse), [.mxMaster4, .mxMaster4, .mxMaster4])
        XCTAssertEqual(pane.rows.map(\.picture), [
            .mouse(part: .thumbPanel, number: nil), .mouse(part: .thumbPanel, number: nil), .mouse(part: nil, number: 6),
        ])
        XCTAssertEqual(try XCTUnwrap(pane.placeMenu(for: six)).items.compactMap { ($0.representedObject as? ButtonPlaceChoice)?.part },
                       PlacedMousePart.allCases)

        deviceName = "MX Master 3S"
        NotificationCenter.default.post(name: LogiCenter.mouseStateChanged, object: nil)
        XCTAssertEqual(pane.headerView.artwork.model, .mxMaster3)
        XCTAssertEqual(pane.rows.map(\.mouse), [.mxMaster3, .mxMaster3, .mxMaster3])
        XCTAssertEqual(pane.rows.map(\.picture), [
            .mouse(part: nil, number: nil, notDrawn: .thumbPanel), .mouse(part: nil, number: 5, notDrawn: .thumbPanel), .mouse(part: nil, number: 6),
        ])
        XCTAssertEqual(try XCTUnwrap(pane.placeMenu(for: six)).items.compactMap { ($0.representedObject as? ButtonPlaceChoice)?.part },
                       [.gestureButton, .backButton, .forwardButton, .modeShiftButton, .middleButton])
        pane.list.select(pane.rows[1].id)
        XCTAssertEqual(pane.headerView.content.number, 5)
        XCTAssertNil(pane.headerView.artwork.emphasis)
        XCTAssertEqual(Options.shared.buttons.binding[1].triggerEvent.mousePart, .thumbPanel, "the answer is kept")
        XCTAssertEqual(pane.rows[1].title, "Thumb panel (button 5)")

        deviceName = nil
        NotificationCenter.default.post(name: LogiCenter.sessionChanged, object: nil)
        XCTAssertEqual(pane.headerView.artwork.model, .generic)
        XCTAssertEqual(try XCTUnwrap(pane.placeMenu(for: six)).items.compactMap { ($0.representedObject as? ButtonPlaceChoice)?.part },
                       [.backButton, .forwardButton, .middleButton])
    }

    /// A button whose place is known but that the shown mouse does not have (a thumb panel
    /// while an MX Master 3S is connected, a Logitech gesture button on the plain drawing) is
    /// not asked to be found or placed, and its menu keeps the stored answer ticked and
    /// disabled: nothing is lost by accident, and nothing is saved by showing it.
    func testAKnownButtonTheShownMouseLacksIsNotAskedToBeFound() throws {
        let panelAnswer = ButtonBinding(triggerEvent: placed(6, .thumbPanel), systemShortcutName: "copy", isEnabled: true)
        deviceName = "MX Master 3S"
        let pane = makePane([panelAnswer, binding(1000, "copy")])
        let stored = Options.shared.buttons.binding
        let notHere = "The mouse shown doesn't have this button."
        XCTAssertEqual(pane.rows[0].title, "Thumb panel (button 6)")
        XCTAssertEqual(pane.rows[0].picture, .mouse(part: nil, number: 6, notDrawn: .thumbPanel))
        XCTAssertFalse(pane.rows[0].picture.isUnplaced)
        pane.list.select(pane.rows[0].id)
        XCTAssertEqual(pane.headerView.content.hint, notHere)
        XCTAssertEqual(pane.headerView.content.number, 6)

        let menu = try XCTUnwrap(pane.placeMenu(for: pane.rows[0].binding.id))
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
        pane.list.select(pane.rows[1].id)
        XCTAssertEqual(pane.headerView.content.title, "Gesture button")
        XCTAssertEqual(pane.headerView.content.hint, notHere)
        XCTAssertNil(pane.placeMenu(for: pane.rows[1].binding.id), "its place is known: no menu")
        XCTAssertEqual(Options.shared.buttons.binding, stored)
        XCTAssertEqual(Options.shared.buttons.binding.map(\.triggerEvent.mousePart), [.thumbPanel, nil], "the answer is kept")
    }

    /// The owner's MX Master 4 over Bluetooth: Gesture Navigation on Button 6, a shortcut on
    /// Button 5, a screenshot on the mode shift button.
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
        let pane = makePane(ownerBindings())
        let six = pane.rows[0].binding.id
        pane.setPlace(of: pane.rows[1].binding.id, to: .thumbPanel)
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
        XCTAssertNil(pane.placeMenu(for: pane.rows[2].binding.id), "the mode shift button's place is known")
    }

    /// The picture of a numbered button is a button over the row's picture that opens the
    /// menu (and selects the row, so the card shows the button); a right-click on the row
    /// offers the same menu. A known button and a key have neither.
    func testThePictureAndARightClickOpenTheMenu() throws {
        let pane = makePane(ownerBindings() + [binding(40, "copy", modifiers: control | option, type: .keyboard)])
        pane.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(pane.rows.map(\.placeButton.isHidden), [false, false, true, true])
        let row = pane.rows[1]
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
        let menu = try XCTUnwrap(pane.rows[0].menu(for: rightClick))
        XCTAssertEqual(menu.items.first?.title, "Which Button Is This?")
        XCTAssertEqual(pane.list.selectedID, pane.rows[0].id)
        XCTAssertNil(pane.rows[2].menu(for: rightClick), "the mode shift button")
        XCTAssertNil(pane.rows[3].menu(for: rightClick), "a key")

        // Placed, it stays a button: the answer can be changed or taken back.
        pane.setPlace(of: row.binding.id, to: .thumbPanel)
        XCTAssertFalse(pane.rows[1].placeButton.isHidden)
    }

    /// After the answer the button is named and lit as the part, with its number after the
    /// name, wherever a known button is: the row, its picture, the card, the Gestures pane's
    /// line, and the stored trigger holds the answer. "Not on This List" takes it back.
    func testChoosingAPartNamesAndLightsTheButton() throws {
        let pane = makePane(ownerBindings())
        let six = pane.rows[0].binding.id
        let five = pane.rows[1].binding.id
        let gesture = try XCTUnwrap(pane.placeMenu(for: six)?.items.first { ($0.representedObject as? ButtonPlaceChoice)?.part == .gestureButton })
        pane.placeChosen(gesture)
        let panel = try XCTUnwrap(pane.placeMenu(for: five)?.items.first { ($0.representedObject as? ButtonPlaceChoice)?.part == .thumbPanel })
        pane.placeChosen(panel)

        XCTAssertEqual(pane.rows.map(\.title), ["Gesture button (button 6)", "Thumb panel (button 5)", "Mode shift button"])
        XCTAssertEqual(pane.rows.map(\.picture), [
            .mouse(part: .gesture, number: nil), .mouse(part: .thumbPanel, number: nil), .mouse(part: .modeShift, number: nil),
        ])
        XCTAssertEqual(pane.rows.map(\.explanation), ["Hold and move the mouse. Set the directions under Gestures.", nil, nil],
                       "a placed button is no longer just an extra one")
        XCTAssertEqual(pane.rows[1].accessibilityLabel(), "Thumb panel (button 5)")

        pane.list.select(six)
        XCTAssertEqual(pane.headerView.content, ButtonsHeaderContent(title: "Gesture button (button 6)", subtitle: "Gesture Navigation", part: .gesture))
        XCTAssertEqual(pane.headerView.artwork.emphasis, .gesture)
        XCTAssertEqual(pane.headerView.artwork.highlights[.gesture]?.alphaValue, 1)
        XCTAssertEqual(pane.headerView.artwork.badge.alphaValue, 0)
        XCTAssertTrue(pane.headerView.hintLabel.isHidden)

        // Stored: the trigger's place, nothing else.
        let stored = Options.shared.buttons.binding
        XCTAssertEqual(stored.map(\.triggerEvent.mousePart), [.gestureButton, .thumbPanel, nil])
        XCTAssertEqual(stored, ownerBindingsWithIDs(of: stored), "the same triggers and actions")

        // The Gestures pane's "Gesture button" line.
        let summary = MouseGestureBindingSummary(bindings: stored, isLogitechCode: { LogiCenter.shared.isLogiCode($0) })
        XCTAssertEqual(summary.buttonTitles, ["Gesture button (button 6)"])
        XCTAssertEqual(summary.gestureButtonExplanation, "Assigned to Gesture button (button 6).")
        XCTAssertFalse(summary.hasLogitechGestureButton)

        // Modifiers stay in front.
        XCTAssertEqual(ButtonTriggerNaming.title(for: placed(6, .gestureButton, modifiers: option | command)), "⌥⌘ Gesture button (button 6)")

        // "Not on This List": Button 6 again, and the stored trigger as it was.
        let none = try XCTUnwrap(pane.placeMenu(for: six)?.items.last)
        XCTAssertEqual(none.title, "Not on This List")
        pane.placeChosen(none)
        XCTAssertEqual(pane.rows[0].title, "Button 6")
        XCTAssertEqual(pane.rows[0].picture, .mouse(part: nil, number: 6))
        XCTAssertEqual(pane.headerView.content.number, 6)
        XCTAssertEqual(pane.headerView.content.hint, "Click its picture below to say which button it is. Not sure? Click + and press buttons to find it.")
        XCTAssertNil(Options.shared.buttons.binding[0].triggerEvent.mousePart)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: try sortedJSON(Options.shared.buttons.binding)) as? [[String: Any]])
        let trigger = try XCTUnwrap(object[0]["triggerEvent"] as? [String: Any])
        XCTAssertEqual(Set(trigger.keys), ["type", "code", "modifiers"])
    }

    /// The owner's bindings with the ids and dates of `stored`.
    private func ownerBindingsWithIDs(of stored: [ButtonBinding]) -> [ButtonBinding] {
        return zip(ownerBindings(), stored).map { owner, stored in
            ButtonBinding(id: stored.id, triggerEvent: owner.triggerEvent, systemShortcutName: owner.systemShortcutName,
                          isEnabled: owner.isEnabled, createdAt: stored.createdAt)
        }
    }

    /// "+" and a placed button: the card answers with its part lit, no number.
    func testPressingAPlacedButtonAfterPlusSaysItsPart() {
        let pane = makePane(ownerBindings())
        pane.setPlace(of: pane.rows[0].binding.id, to: .gestureButton)
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
        let pane = makePane([
            binding(6, SystemShortcut.mouseGestureNavigation.identifier),
            binding(6, "copy", modifiers: option),
            binding(5, "copy"),
            binding(3, "paste"),
        ])
        pane.setPlace(of: pane.rows[1].binding.id, to: .gestureButton)
        XCTAssertEqual(pane.rows.map(\.title), ["Gesture button (button 6)", "⌥ Gesture button (button 6)", "Button 5", "Back button"])
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
        let removed = pane.rows[1].binding.id
        undo.beginUndoGrouping()
        pane.removeBinding(id: removed)
        undo.endUndoGrouping()
        undo.undo()
        XCTAssertEqual(pane.binding(for: removed)?.triggerEvent.mousePart, .gestureButton)
        XCTAssertEqual(pane.row(for: removed)?.title, "⌥ Gesture button (button 6)")

        // The last row of its number, removed and put back alone, keeps its part too.
        let five = pane.rows[2].binding.id
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
        pane.list.select(pane.rows[0].id)
        _ = pane.placeMenu(for: pane.rows[0].binding.id)
        pane.showPlaceMenu(for: pane.rows[1].binding.id, from: pane.rows[1].placeButton)
        pane.setPlace(of: pane.rows[0].binding.id, to: nil)
        pane.setPlace(of: pane.rows[2].binding.id, to: .backButton)
        XCTAssertEqual(try sortedJSON(Options.shared.buttons.binding), before)
        pane.reload()
        XCTAssertEqual(try sortedJSON(Options.shared.buttons.binding), before)
        XCTAssertEqual(pane.rows.map(\.title), ["Button 6", "Button 5", "Mode shift button"], "a known button cannot be placed")
    }

    /// The answer is for the eyes only: the trigger matches and runs as before.
    func testAnAnswerChangesNothingButWhatThePaneShows() {
        let plain = RecordedEvent(type: .mouse, code: 6, modifiers: option, deviceFilter: nil)
        let answered = plain.placed(at: .gestureButton)
        XCTAssertEqual(answered, plain)
        XCTAssertEqual(answered.asScrollHotkey, plain.asScrollHotkey)
        for event in [mouseEvent(6), mouseEvent(6, modifiers: .maskAlternate), mouseEvent(6, modifiers: [.maskAlternate, .maskCommand]), mouseEvent(5, modifiers: .maskAlternate)] {
            XCTAssertEqual(answered.matchesInput(event), plain.matchesInput(event))
            XCTAssertEqual(answered.matchPriority(for: event), plain.matchPriority(for: event))
        }
        let binding = ButtonBinding(triggerEvent: plain, systemShortcutName: "copy")
        XCTAssertEqual(binding.replacingTriggerEvent(answered), binding)
        XCTAssertNil(answered.placed(at: nil).mousePart)
    }

    // MARK: - Rows

    func testRowsSayWhatTheActionNeeds() {
        let pane = makePane([
            binding(3, SystemShortcut.mouseGestureNavigation.identifier),
            binding(4, SystemShortcut.mosScrollToggle.identifier),
            binding(5),
            binding(6, "copy"),
        ])
        XCTAssertEqual(pane.rows.map(\.title), ["Back button", "Forward button", "Button 5", "Button 6"])
        XCTAssertEqual(pane.rows.map(\.explanation), [
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
        XCTAssertEqual(pane.rows[2].accessibilityLabel(), "Button 5, Choose what this button does.")
    }

    func testProblemNotesAreOrangeWithADetailsButton() throws {
        captureStatus = [1000: .conflict(.foreignDivert), 1001: .contended, 1002: .bleHIDPPUnstable, 1006: .standardMouseAliasAvailable]
        scrollKeys = [ScrollHotkey(type: .mouse, code: 5), ScrollHotkey(type: .keyboard, code: 4)]
        let pane = makePane([
            binding(1000, "copy"), binding(1001, "copy"), binding(1002, "copy"), binding(1006, "copy"),
            binding(5, "copy", modifiers: option), binding(4, "copy"),
        ])
        XCTAssertEqual(pane.rows.map(\.explanation), [
            "Another app may use this button.",
            "Logi Options+ keeps taking this button over.",
            "May stop working while Logi Options+ runs.",
            "Can use the standard Back button instead.",
            "Also set under Scrolling\u{A0}›\u{A0}While\u{A0}you\u{A0}hold\u{A0}a\u{A0}key.",
            nil,
        ])
        XCTAssertEqual(pane.rows.map { $0.note?.tone }, [.problem, .problem, .problem, .hint, .problem, nil])
        for row in pane.rows.prefix(5) {
            XCTAssertFalse(row.infoButton.isHidden, row.title)
            XCTAssertEqual(row.infoButton.accessibilityLabel(), "More Info")
        }
        // An orange warning sign before the text, a blue light bulb before the alias hint;
        // the text itself in the colour of any explanation (orange or blue text is too
        // faint to read on a light box).
        let conflict = pane.rows[0].explanationLabel.attributedStringValue
        XCTAssertTrue(conflict.string.hasSuffix("Another app may use this button."))
        XCTAssertTrue(conflict.containsAttachments(in: NSRange(location: 0, length: conflict.length)))
        XCTAssertEqual(conflict.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .systemOrange)
        XCTAssertEqual(conflict.attribute(.foregroundColor, at: conflict.length - 1, effectiveRange: nil) as? NSColor,
                       PreferencesGroupedForm.explanationColor(enabled: true))
        let hint = pane.rows[3].explanationLabel.attributedStringValue
        XCTAssertEqual(hint.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .systemBlue)
        XCTAssertEqual(hint.attribute(.foregroundColor, at: hint.length - 1, effectiveRange: nil) as? NSColor,
                       PreferencesGroupedForm.explanationColor(enabled: true))
        XCTAssertEqual(pane.rows[0].accessibilityLabel(), "Gesture button, Another app may use this button.")

        // The ⓘ explains, in plain words.
        let popover = try XCTUnwrap(pane.showProblem(of: pane.rows[0], relativeTo: pane.rows[0].infoButton))
        _ = popover.view
        XCTAssertEqual(popover.titleLabel.stringValue, "Another app may be using this button")
        XCTAssertFalse(popover.detailLabel.stringValue.contains("HID++"))
        XCTAssertNil(popover.standardButton)
        XCTAssertEqual(pane.problemPopover?.behavior, .transient)
        let scrollKey = try XCTUnwrap(pane.showProblem(of: pane.rows[4], relativeTo: pane.rows[4].infoButton))
        _ = scrollKey.view
        XCTAssertEqual(scrollKey.titleLabel.stringValue, "Also a key under Scrolling")
    }

    /// The ⓘ sits on the title line just before the pull-down, and the note under the title
    /// runs on below it: no problem takes more than two lines.
    func testProblemNotesRunUnderTheInfoButtonInTwoLinesAtMost() throws {
        captureStatus = [1000: .conflict(.foreignDivert), 1001: .contended, 1002: .bleHIDPPUnstable, 1006: .standardMouseAliasAvailable]
        scrollKeys = [ScrollHotkey(type: .mouse, code: 5)]
        let pane = makePane([
            binding(1000, "copy"), binding(1001, "copy"), binding(1002, "copy"), binding(1006, "copy"), binding(5, "copy"),
        ])
        pane.view.layoutSubtreeIfNeeded()
        let oneLine = NSTextField(labelWithString: "Xg")
        oneLine.font = PreferencesGroupedForm.explanationFont
        let lineHeight = oneLine.fittingSize.height
        // Right of the row's picture, left of the pull-down.
        let column = PreferencesButtonsViewController.boxWidth - 2 * PreferencesGroupedForm.rowHorizontalInset
            - PreferencesListRow.imageIconSize - PreferencesListRow.iconSpacing
            - ButtonActionPullDown.width - PreferencesGroupedForm.controlSpacing
        for row in pane.rows {
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
        XCTAssertTrue(try XCTUnwrap(plain.rows.first).infoButton.isHidden)
    }

    func testUseStandardButtonTurnsTheLogitechButtonIntoTheStandardOne() throws {
        captureStatus = [1006: .standardMouseAliasAvailable]
        let pane = makePane([binding(1006, SystemShortcut.navigateBack.identifier)])
        let row = try XCTUnwrap(pane.rows.first)
        let popover = try XCTUnwrap(pane.showProblem(of: row, relativeTo: row.infoButton))
        _ = popover.view
        let button = try XCTUnwrap(popover.standardButton)
        XCTAssertEqual(button.title, "Use Standard Button")

        button.performClick(nil)

        let stored = try XCTUnwrap(Options.shared.buttons.binding.first)
        XCTAssertEqual(stored.triggerEvent.code, 3)
        XCTAssertEqual(stored.systemShortcutName, SystemShortcut.navigateBack.identifier)
        XCTAssertEqual(stored.id, row.binding.id)
        XCTAssertEqual(pane.rows.first?.title, "Back button")
        XCTAssertNil(pane.rows.first?.note, "no hint any more")
    }

    func testBindingsWithoutAnyProblemStayQuietForKeys() {
        captureStatus = [40: .conflict(.foreignDivert)]
        let pane = makePane([binding(40, "copy", modifiers: control, type: .keyboard)])
        XCTAssertNil(pane.rows.first?.note, "a key never asks the mouse")
        XCTAssertEqual(pane.rows.first?.title, "⌃ K")
    }

    // MARK: - Changing an action

    func testChoosingAnActionSavesItAndUpdatesTheRowInPlace() throws {
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
        pane.list.select(pane.rows[0].id)
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
        XCTAssertEqual(pane.list.selectedID, pane.rows[0].id)
        XCTAssertEqual(pane.headerView.content, ButtonsHeaderContent(title: "That's Back button", subtitle: "Copy", part: .back))
        XCTAssertEqual(pane.headerView.artwork.emphasis, .back)
        pane.onRecordingStopped(recorder, didRecord: true)
        flush()
        XCTAssertEqual(Options.shared.buttons.binding.count, 2)
        XCTAssertTrue(openedMenus.isEmpty)
    }

    /// The recorder gives more time while a modifier is held: the pane waits for the
    /// recorder however long it takes, and "Set Up…"'s Gesture Navigation waits with it.
    func testTheRecordingLastsUntilTheRecorderEndsAndKeepsTheActionOfSetUp() throws {
        let pane = makePane()
        let recorder = KeyRecorder()
        pane.beginAddingBinding(action: SystemShortcut.mouseGestureNavigation)
        pane.onRecordingStarted(recorder)

        flush(KeyRecorder.TIMEOUT + 1.5)
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

    /// "Set Up…" and a button that is in the list without an action: it gets Gesture
    /// Navigation. One with an action keeps it and only flashes.
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
        XCTAssertFalse(pane.validateRecordedEvent(recorder, event: key), "refused, as a duplicate is")
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
        XCTAssertTrue(pane.validateRecordedEvent(recorder, event: key))
        pane.onRecordingStopped(recorder, didRecord: false)
    }

    /// A key is not offered Gesture Navigation in its menu; a mouse button is. A key that
    /// has it from before keeps the item, so the menu shows what is set.
    func testAKeyIsNotOfferedGestureNavigation() throws {
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
        XCTAssertEqual(pane.list.selectedID, AnyHashable(unbound.id))
        XCTAssertEqual(pane.rows.first?.explanation, "Hold and move the mouse. Set the directions under Gestures.")
        XCTAssertTrue(openedMenus.isEmpty)

        pane.beginAddingBinding(action: SystemShortcut.mouseGestureNavigation)
        pane.onRecordingStarted(recorder)
        XCTAssertFalse(pane.validateRecordedEvent(recorder, event: mouseEvent(4)), "a duplicate: it has an action")
        pane.onEventRecorded(recorder, didRecordEvent: mouseEvent(4), isDuplicate: true)
        pane.onRecordingStopped(recorder, didRecord: true)
        XCTAssertEqual(Options.shared.buttons.binding.last?.systemShortcutName, "copy", "its own action stays")
        XCTAssertEqual(pane.list.selectedID, AnyHashable(bound.id))

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
        let pane = makePane([binding(1000, "copy"), binding(3, "copy")])

        // "Open App or File…" of the second row.
        let pullDown = pane.rows[1].pullDown
        let openItem = try XCTUnwrap(pullDown.menu?.items.first { $0.representedObject as? String == ShortcutManager.MenuMarker.openTarget })
        pullDown.shortcutSelected(openItem)
        XCTAssertNotNil(pane.openTargetPopover)
        XCTAssertTrue(shownOpenTargets.first === pullDown, "shown at the row's pull-down")
        // The ⓘ of the first row.
        XCTAssertNotNil(pane.showProblem(of: pane.rows[0], relativeTo: pane.rows[0].infoButton))
        XCTAssertNotNil(pane.problemPopover)
        // "Keyboard Shortcut…" waits for a key in the first row.
        pane.rows[0].pullDown.beginCustomShortcutSelection(startRecorder: false)
        XCTAssertEqual(pane.rows[0].pullDown.actionState, .recordingPrompt)
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
        XCTAssertNotEqual(pane.rows[0].pullDown.actionState, .recordingPrompt, "the action shows again")
        XCTAssertEqual(Options.shared.buttons.binding.count, 2, "nothing added")
        XCTAssertEqual(pane.headerView.content.title, "MX Master 4")

        // Nothing to close: nothing is stopped.
        pane.viewWillAppear()
        pane.viewWillDisappear()
        XCTAssertEqual(recorderStops, 1)
    }

    func testAddingABluetoothOnlyLogitechButtonWarnsOnce() {
        captureStatus = [1001: .bleHIDPPUnstable]
        let pane = makePane()
        pane.addBinding(for: RecordedEvent(type: .mouse, code: 1001, modifiers: 0, deviceFilter: nil), action: nil)
        XCTAssertEqual(warnedCodes, [1001])
    }

    // MARK: - Removing, with Undo

    func testMinusRemovesTheSelectedButtonAndUndoPutsItBack() throws {
        let first = binding(3, "copy")
        let second = binding(4, SystemShortcut.mosScrollDash.identifier)
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
        XCTAssertEqual(scrolling.items.map(\.title), ["Scroll Faster", "Scroll Sideways", "Pause Smoothing"])
        let logitech = try XCTUnwrap(menu.items.first { $0.title == "Logitech Mouse" }?.submenu)
        XCTAssertEqual(logitech.items.map(\.title), [
            "Switch Wheel Mode", "Increase Pointer Speed", "Decrease Pointer Speed",
            "Switch to Computer 1", "Switch to Computer 2", "Switch to Computer 3",
            "Toggle Hi-Res Scrolling", "Invert Scrolling", "Toggle Thumb Wheel", "Next Pointer Speed",
        ])
        // The last group: Gesture Navigation, its settings (hidden: not its action), Open
        // App or File…, Keyboard Shortcut….
        let last = Array(menu.items.suffix(4))
        XCTAssertTrue(menu.items[menu.items.count - 5].isSeparatorItem)
        XCTAssertEqual(last.map(\.title), ["Gesture Navigation", "Show Gesture Settings", "Open App or File…", "Keyboard Shortcut…"])
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
        XCTAssertEqual(pane.rows.map(\.title), ["⌥ Back button", "Gesture button", "⌃⌥ K", "Button 5"])
        XCTAssertEqual(pane.rows.map { shown($0.pullDown) }, ["Gesture Navigation", "⌥⌘K", "Calculator", "No Action"])

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
