//
//  PreferencesButtonsTests.swift
//  MosTests
//
//  The Buttons pane: what its rows and its card are called, which part of the mouse a
//  button lights, the notes under the rows, recording a button (stubbed: no event is
//  recorded or posted), removing with Undo, the action menu, "Checking buttons…", and that
//  stored bindings load and save unchanged. Nothing is shown on screen and no HID device
//  is touched.
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
        pane.openActionMenu = { [unowned self] popUp in self.openedMenus.append(popUp) }
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
        XCTAssertNil(part(2000 + 0x005B), "a tilt is not drawn")
        XCTAssertNil(part(40, type: .keyboard), "a key lights nothing")
        XCTAssertNil(part(3, type: .keyboard))
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
        XCTAssertNil(center.controlRole(forMosCode: 2000 + 0x005B))
        XCTAssertNil(center.controlRole(forMosCode: 3), "a native button is not a Logitech control")
    }

    // MARK: - The card

    func testTheCardSaysHowManyButtonsHaveActions() {
        typealias Content = ButtonsHeaderContent
        XCTAssertEqual(Content.make(deviceName: nil, boundCount: 0, isRecording: false, focus: nil),
                       Content(title: "Your mouse", subtitle: "No buttons set up yet", part: nil))
        XCTAssertEqual(Content.make(deviceName: "MX Master 3S", boundCount: 1, isRecording: false, focus: nil),
                       Content(title: "MX Master 3S", subtitle: "1 button has an action", part: nil))
        XCTAssertEqual(Content.make(deviceName: "", boundCount: 4, isRecording: false, focus: nil),
                       Content(title: "Your mouse", subtitle: "4 buttons have actions", part: nil))
        let focus = Content.Focus(title: "Back button", action: nil, part: .back)
        XCTAssertEqual(Content.make(deviceName: nil, boundCount: 4, isRecording: false, focus: focus),
                       Content(title: "Back button", subtitle: "No action", part: .back))
        XCTAssertEqual(Content.make(deviceName: nil, boundCount: 4, isRecording: true, focus: focus),
                       Content(title: "Press a button", subtitle: "Or a key with ⌘, ⌥, ⌃ or ⇧.\nPress Esc to cancel.", part: nil))
    }

    func testTheCardFollowsTheSelectedRowAndCountsOnlyBoundButtons() {
        let pane = makePane([binding(3, SystemShortcut.mouseGestureNavigation.identifier), binding(4), binding(1000, "copy")])
        XCTAssertEqual(pane.headerView.content, ButtonsHeaderContent(title: "MX Master 4", subtitle: "2 buttons have actions", part: nil))

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
        XCTAssertEqual(pane.headerView.accessibilityLabel(), "MX Master 4, 2 buttons have actions")
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
            nil,
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
        let column = PreferencesButtonsViewController.boxWidth - 2 * PreferencesGroupedForm.rowHorizontalInset
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
        XCTAssertEqual(pane.headerView.content.title, "Back button")
        pane.onRecordingStopped(recorder, didRecord: true)
        flush()
        XCTAssertEqual(Options.shared.buttons.binding.count, 2)
        XCTAssertTrue(openedMenus.isEmpty)
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
        pane.list.select(only.id)
        let delete = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            characters: "\u{7F}", charactersIgnoringModifiers: "\u{7F}", isARepeat: false, keyCode: 51
        ))
        pane.list.keyDown(with: delete)
        XCTAssertTrue(Options.shared.buttons.binding.isEmpty)
        XCTAssertTrue(pane.list.emptyRow.superview === pane.list.rowsView)
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
