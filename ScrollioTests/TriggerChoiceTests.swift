//
//  TriggerChoiceTests.swift
//  ScrollioTests
//
//  The pull-down that chooses the button to hold (Gestures) and what opens the ring
//  (Shortcut Ring) in place: what its menu lists and says, what a choice writes into
//  Buttons' bindings (the one place they are stored), its Undo and Redo, "Record a
//  Button…" and that both panes do the same. No menu is opened, no recorder taps the
//  system's events, nothing is shown on screen and no HID device is touched.
//

import XCTest
@testable import Scrollio_Debug

extension NSPopUpButton {
    /// Sends the action of the item with `identifier`, as a click on it does (the menu is
    /// never opened: it would wait for the user).
    @discardableResult
    func chooseItemForTests(_ identifier: NSUserInterfaceItemIdentifier) -> Bool {
        guard let menu, let index = menu.items.firstIndex(where: { $0.identifier == identifier }) else { return false }
        menu.performActionForItem(at: index)
        return true
    }
}

final class TriggerChoiceTests: XCTestCase {

    private let gestures = SystemShortcut.mouseGestureNavigation.identifier
    private let ring = SystemShortcut.shortcutRing.identifier
    private var savedBindings: [ButtonBinding] = []
    private var savedApplications: EnhanceArray<Application>!

    override func setUp() {
        super.setUp()
        savedBindings = Options.shared.buttons.binding
        savedApplications = Options.shared.application.applications
        Options.shared.buttons.binding = []
        Options.shared.application.applications = EnhanceArray<Application>(withArray: [], matchKey: "path")
    }

    override func tearDown() {
        Options.shared.buttons.binding = savedBindings
        Options.shared.application.applications = savedApplications
        ButtonUtils.shared.invalidateCache()
        super.tearDown()
    }

    // MARK: - Fixtures

    private func logi(_ role: LogiControlRole) -> UInt16 {
        return LogiCenter.shared.scrollioCode(for: role)
    }

    private func event(_ code: UInt16, modifiers: UInt = 0, type: EventType = .mouse) -> RecordedEvent {
        return RecordedEvent(type: type, code: code, modifiers: modifiers, deviceFilter: nil)
    }

    private func binding(_ code: UInt16, _ action: String, modifiers: UInt = 0, type: EventType = .mouse) -> ButtonBinding {
        return ButtonBinding(triggerEvent: event(code, modifiers: modifiers, type: type), systemShortcutName: action, isEnabled: true)
    }

    /// What "+" records for a button of an MX Master 3S: the standard buttons as such, the
    /// others as their Logitech controls.
    private func recordedTrigger(_ part: ButtonsMousePart) -> RecordedEvent {
        switch part {
        case .middle: return event(2)
        case .back: return event(3)
        case .forward: return event(4)
        default: return event(logi(part.logitechRole ?? .gesture))
        }
    }

    /// An MX Master 3S, as the Buttons pane reads it.
    private func source(_ name: String? = "MX Master 3S") -> ButtonsDeviceSource {
        return ButtonsDeviceSource(
            captureStatus: { _ in .normal }, deviceName: { name }, isBusy: { false }, refresh: {},
            warnBluetoothButton: { _ in }, recordedTrigger: { [unowned self] in self.recordedTrigger($0) }
        )
    }

    private func menu(_ rule: ApplicationTriggerRule, titles: [String], bindings: [ButtonBinding]) -> TriggerChoiceMenu {
        return TriggerChoiceMenu.make(
            rule: rule, triggerTitles: titles, bindings: bindings, mouse: .mxMaster3,
            recordedTrigger: recordedTrigger, actionName: { ActionDisplayResolver().actionName(of: $0) }
        )
    }

    // MARK: - The menu

    /// The buttons of the mouse in the order they sit on it, each with what it does now:
    /// the one that does it ticked, one with another action "will be replaced", one
    /// without "Default".
    func testTheMenuListsTheMouseButtonsInTheirOrderWithWhatEachDoes() {
        let bindings = [binding(3, SystemShortcut.copy.identifier), binding(logi(.gesture), gestures)]
        let model = menu(.gestureNavigation, titles: ["Gesture button"], bindings: bindings)
        XCTAssertEqual(model.title, .trigger("Gesture button"))
        XCTAssertTrue(model.offersChoice)
        XCTAssertEqual(model.items.map(\.part), [.middle, .modeShift, .forward, .back, .gesture], "the MX Master 3S's order")
        let back = model.items[3]
        XCTAssertEqual(back.title, "Back button")
        XCTAssertEqual(back.action, SystemShortcut.copy.localizedName)
        XCTAssertTrue(back.replacesAction)
        XCTAssertEqual(back.trigger, event(3), "its row's trigger")
        let gesture = model.items[4]
        XCTAssertTrue(gesture.isChosen)
        XCTAssertFalse(gesture.replacesAction)
        XCTAssertEqual(gesture.trigger, event(logi(.gesture)))
        let forward = model.items[2]
        XCTAssertNil(forward.action, "Default")
        XCTAssertFalse(forward.isChosen)
        XCTAssertEqual(forward.trigger, event(4), "what + records for it")
    }

    func testTheTitleSaysChooseOneOrMultipleAndTwoOfferOnlyShowInButtons() {
        XCTAssertEqual(menu(.shortcutRing, titles: [], bindings: []).title, .choose)
        XCTAssertEqual(menu(.shortcutRing, titles: [], bindings: []).items.count, 5, "every button of the MX Master 3S")
        let two = menu(.shortcutRing, titles: ["Thumb panel", "⌃⌥ Space"], bindings: [binding(3, ring), binding(4, ring)])
        XCTAssertEqual(two.title, .several)
        XCTAssertFalse(two.offersChoice)
        XCTAssertEqual(two.items, [])
        // Without a drawing of its own the mouse has no buttons to list.
        let generic = TriggerChoiceMenu.make(
            rule: .shortcutRing, triggerTitles: [], bindings: [], mouse: .generic,
            recordedTrigger: recordedTrigger, actionName: { _ in nil }
        )
        XCTAssertEqual(generic.items, [])
    }

    // MARK: - What a choice writes

    /// A button without a binding gets one, of what "+" records for it; the binding that
    /// did it goes (one button does it, as the title says).
    func testChoosingAButtonWithoutAnActionMovesItThere() throws {
        let old = binding(logi(.gesture), gestures)
        let copy = binding(4, SystemShortcut.copy.identifier, modifiers: UInt(CGEventFlags.maskAlternate.rawValue))
        let after = try XCTUnwrap(TriggerChoiceEdit.choosing(event(3), for: .gestureNavigation, in: [old, copy], mouse: .mxMaster3))
        XCTAssertEqual(after.count, 2)
        XCTAssertEqual(after[0], copy, "the others stay as they are")
        XCTAssertEqual(after[1].triggerEvent, event(3))
        XCTAssertEqual(after[1].systemShortcutName, gestures)
        XCTAssertTrue(after[1].isEnabled)
        XCTAssertFalse(after.contains { $0.id == old.id }, "the gesture button is Default again")
    }

    /// A button with another action keeps its binding (its id) and gets the action, as its
    /// row in Buttons does; the one that did it is chosen again: nothing changes.
    func testChoosingAButtonWithAnActionReplacesItAndTheChosenOneChangesNothing() throws {
        let back = binding(3, SystemShortcut.copy.identifier)
        let old = binding(4, ring)
        let after = try XCTUnwrap(TriggerChoiceEdit.choosing(event(3), for: .shortcutRing, in: [back, old], mouse: .mxMaster3))
        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(after[0].id, back.id)
        XCTAssertEqual(after[0].systemShortcutName, ring)
        XCTAssertEqual(after[0].createdAt, back.createdAt)
        XCTAssertNil(TriggerChoiceEdit.choosing(event(4), for: .shortcutRing, in: [back, old], mouse: .mxMaster3))
    }

    /// The ring takes a key combination, recorded or stored; the gestures never take a key.
    func testAKeyOpensTheRingButNeverRunsTheGestures() throws {
        let control = UInt(CGEventFlags.maskControl.rawValue)
        let space = event(49, modifiers: control, type: .keyboard)
        XCTAssertNil(TriggerChoiceEdit.choosing(space, for: .gestureNavigation, in: [], mouse: .mxMaster3))
        let added = try XCTUnwrap(TriggerChoiceEdit.choosing(space, for: .shortcutRing, in: [], mouse: .mxMaster3))
        XCTAssertEqual(added.map(\.triggerEvent), [space])
        XCTAssertEqual(added.first?.systemShortcutName, ring)
        // A key that is a binding already gets the action in it.
        let stored = binding(49, SystemShortcut.copy.identifier, modifiers: control, type: .keyboard)
        let replaced = try XCTUnwrap(TriggerChoiceEdit.choosing(space, for: .shortcutRing, in: [stored], mouse: .mxMaster3))
        XCTAssertEqual(replaced.map(\.id), [stored.id])
        // A key that cannot run (no modifier, no F-key) is not taken.
        XCTAssertNil(TriggerChoiceEdit.choosing(event(49, type: .keyboard), for: .shortcutRing, in: [], mouse: .mxMaster3))
    }

    // MARK: - Undo

    /// Undo puts back exactly what the choice changed, by id; a change made meanwhile to
    /// another binding stays; Redo does it again.
    func testThePatchUndoesOnlyWhatTheChoiceChanged() throws {
        let back = binding(3, SystemShortcut.copy.identifier)
        let old = binding(logi(.gesture), gestures)
        let middle = binding(2, SystemShortcut.missionControl.identifier)
        let before = [old, back, middle]
        let after = try XCTUnwrap(TriggerChoiceEdit.choosing(event(3), for: .gestureNavigation, in: before, mouse: .mxMaster3))
        let patch = ButtonBindingsPatch(from: before, to: after)
        XCTAssertEqual(patch.removed.map(\.binding), [old])
        XCTAssertEqual(patch.changed.map(\.old), [back])
        XCTAssertTrue(patch.inserted.isEmpty)
        XCTAssertEqual(patch.inverse.applied(to: after), before)
        XCTAssertEqual(patch.applied(to: before), after)
        // Meanwhile the middle button got another action under Buttons: it keeps it.
        var meanwhile = after
        meanwhile[1] = binding(2, SystemShortcut.paste.identifier)
        let undone = patch.inverse.applied(to: meanwhile)
        XCTAssertEqual(undone.map(\.id), [old.id, back.id, meanwhile[1].id])
        XCTAssertEqual(undone[1], back)
        XCTAssertEqual(undone[2].systemShortcutName, SystemShortcut.paste.identifier)
    }

    // MARK: - In the panes

    /// The two panes and their choosers, made as the window makes them.
    private func gesturesPane(undo: UndoManager) -> GesturesPreferencesViewController {
        let pane = GesturesPreferencesViewController(isInteractiveAvailable: { true })
        pane.deviceSource = MouseGestureDeviceSource(support: { .none }, refresh: {})
        pane.paneUndoManager = undo
        _ = pane.view
        pane.triggerChooser.deviceSource = source()
        pane.reload()
        return pane
    }

    private func ringPane(undo: UndoManager) -> RingPreferencesViewController {
        let pane = RingPreferencesViewController()
        pane.paneUndoManager = undo
        _ = pane.view
        pane.triggerChooser?.deviceSource = source()
        pane.reload()
        return pane
    }

    private func undoManager() -> UndoManager {
        let undo = UndoManager()
        undo.groupsByEvent = false
        return undo
    }

    /// A click on an item, as one event: its Undo is one group.
    private func choose(_ identifier: NSUserInterfaceItemIdentifier, in pullDown: NSPopUpButton, _ undo: UndoManager) {
        undo.beginUndoGrouping()
        XCTAssertTrue(pullDown.chooseItemForTests(identifier), "\(identifier.rawValue) is offered")
        undo.endUndoGrouping()
    }

    /// The menu in the pane: the title item, "Your Mouse", the five buttons with what each
    /// does in grey (the plain title holds it all, for VoiceOver), "Record a Button…" and
    /// "Show in Buttons".
    func testTheGesturesMenuSaysWhatEachButtonDoesInGrey() throws {
        Options.shared.buttons.binding = [binding(3, SystemShortcut.copy.identifier)]
        let pane = gesturesPane(undo: undoManager())
        let items = try XCTUnwrap(pane.gestureButtonButton.menu?.items)
        XCTAssertEqual(items.map(\.title), [
            "Choose",
            "Your Mouse",
            "Middle button — Default",
            items[3].title,
            items[4].title,
            "Back button — \(SystemShortcut.copy.localizedName), will be replaced",
            items[6].title,
            "",
            "Record a Button…",
            "",
            "Show in Buttons",
        ])
        XCTAssertTrue(items[7].isSeparatorItem)
        let back = items[5]
        XCTAssertEqual(back.identifier, TriggerChooser.Identifier.item(.back))
        let attributed = try XCTUnwrap(back.attributedTitle)
        let nameColour = attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        let detailColour = attributed.attribute(.foregroundColor, at: attributed.length - 1, effectiveRange: nil) as? NSColor
        XCTAssertEqual(nameColour, .labelColor)
        XCTAssertEqual(detailColour, .secondaryLabelColor, "what it does now, in grey")
        XCTAssertFalse(items.contains { $0.state == .on }, "nothing does it yet")
    }

    /// Same in both panes: a choice writes the binding into Buttons, the row, the title
    /// and the picture show it at once and the folded sections open; Edit › Undo puts back
    /// what was there, Redo does it again.
    func testChoosingAButtonInEitherPaneWritesItShowsItAtOnceAndUndoes() throws {
        for rule in [ApplicationTriggerRule.gestureNavigation, .shortcutRing] {
            let back = binding(3, SystemShortcut.copy.identifier)
            Options.shared.buttons.binding = [back]
            let undo = undoManager()
            let gesturesController = rule == .gestureNavigation ? gesturesPane(undo: undo) : nil
            let ringController = rule == .shortcutRing ? ringPane(undo: undo) : nil
            let pullDown: TriggerChoicePullDown = try XCTUnwrap(gesturesController?.gestureButtonButton ?? ringController?.triggerButton)
            let explanation = { gesturesController?.gestureButtonRow.explanation ?? ringController?.triggerRow.explanation }
            let folded = { gesturesController?.foldingSections.allSatisfy(\.isCollapsible) ?? ringController?.placesSection?.isCollapsible }
            let picture = { gesturesController?.previewView.picture ?? ringController?.triggerCard?.source }
            XCTAssertEqual(pullDown.shownTitle, "Choose", "\(rule)")
            XCTAssertEqual(folded(), true)

            choose(TriggerChooser.Identifier.item(.back), in: pullDown, undo)
            XCTAssertEqual(Options.shared.buttons.binding.map(\.id), [back.id], "the Back button's binding")
            XCTAssertEqual(Options.shared.buttons.binding.first?.systemShortcutName, rule.action.identifier)
            XCTAssertEqual(pullDown.shownTitle, "Back button")
            XCTAssertTrue(explanation()?.hasPrefix("Back button.") ?? false, explanation() ?? "")
            XCTAssertEqual(folded(), false, "the sections open")
            XCTAssertEqual(picture(), TriggerPictureSource(event: event(3)), "the picture lights it at once")
            XCTAssertEqual(pullDown.menu?.item(withIdentifierForTests: TriggerChooser.Identifier.item(.back))?.state, .on)
            XCTAssertEqual(undo.undoActionName, rule == .shortcutRing ? "Change What Opens the Ring" : "Change Button to Hold")

            // Another button: it does it now, and the Back button has its action no more
            // (Default: its binding goes, as Default in Buttons takes it).
            choose(TriggerChooser.Identifier.item(.forward), in: pullDown, undo)
            XCTAssertEqual(Options.shared.buttons.binding.map(\.triggerEvent), [event(4)])
            XCTAssertEqual(pullDown.shownTitle, "Forward button")

            undo.undo()
            XCTAssertEqual(Options.shared.buttons.binding.map(\.id), [back.id])
            XCTAssertEqual(Options.shared.buttons.binding.first?.systemShortcutName, rule.action.identifier)
            XCTAssertEqual(pullDown.shownTitle, "Back button", "the pane follows the Undo")
            undo.undo()
            XCTAssertEqual(Options.shared.buttons.binding, [back], "as it was")
            XCTAssertEqual(pullDown.shownTitle, "Choose")
            XCTAssertEqual(folded(), true)
            undo.redo()
            XCTAssertEqual(Options.shared.buttons.binding.first?.systemShortcutName, rule.action.identifier)
            undo.redo()
            XCTAssertEqual(Options.shared.buttons.binding.map(\.triggerEvent), [event(4)])
            XCTAssertFalse(undo.canRedo)
        }
    }

    /// While two of Buttons' buttons do it, nothing can be chosen here: the menu offers
    /// "Show in Buttons" only.
    func testWithTwoButtonsBothPanesOfferOnlyShowInButtons() throws {
        let undo = undoManager()
        Options.shared.buttons.binding = [binding(3, gestures), binding(4, gestures), binding(2, ring), binding(logi(.gesture), ring)]
        let gesturesController = gesturesPane(undo: undo)
        let ringController = ringPane(undo: undo)
        for pullDown in [gesturesController.gestureButtonButton, try XCTUnwrap(ringController.triggerButton)] {
            XCTAssertEqual(pullDown.shownTitle, "Multiple")
            XCTAssertEqual(pullDown.menu?.items.map(\.title), ["Multiple", "Show in Buttons"])
        }
    }

    /// "Record a Button or Key…" in the Shortcut Ring pane: the recorder opens at the
    /// pull-down; a key combination pressed opens the ring from then on.
    func testRecordAButtonOrKeyInTheRingPaneTakesAKey() throws {
        let undo = undoManager()
        let pane = ringPane(undo: undo)
        let chooser = try XCTUnwrap(pane.triggerChooser)
        var anchors: [NSView] = []
        let recording = expectation(description: "the recorder starts")
        chooser.startRecording = {
            anchors.append($0)
            recording.fulfill()
        }
        XCTAssertEqual(pane.triggerButton.menu?.item(withIdentifierForTests: TriggerChooser.Identifier.record)?.title, "Record a Button or Key…")
        XCTAssertTrue(pane.triggerButton.chooseItemForTests(TriggerChooser.Identifier.record))
        wait(for: [recording], timeout: 5)
        XCTAssertTrue(anchors.first === pane.triggerButton, "in place")

        let recorder = KeyRecorder()
        let key = InputEvent(type: .keyboard, code: 49, modifiers: [.maskControl, .maskAlternate], phase: .down, source: .hidPP, device: nil)
        XCTAssertNil(chooser.waitingHint(recorder, mode: .combination), "the recorder's own: a button or a key")
        chooser.onRecordingStarted(recorder)
        XCTAssertTrue(chooser.validateRecordedEvent(recorder, event: key))
        chooser.onEventRecorded(recorder, didRecordEvent: key, isDuplicate: false)
        undo.beginUndoGrouping()
        chooser.onRecordingStopped(recorder, didRecord: true)
        undo.endUndoGrouping()
        let stored = try XCTUnwrap(Options.shared.buttons.binding.first)
        XCTAssertEqual(stored.triggerEvent.type, .keyboard)
        XCTAssertEqual(stored.systemShortcutName, ring)
        XCTAssertEqual(pane.triggerRow.explanation?.hasPrefix(pane.triggerButton.shownTitle), true)
        undo.undo()
        XCTAssertEqual(Options.shared.buttons.binding, [])
    }

    /// A recording that is closed without a press (Esc, the pane went away) chooses nothing.
    func testARecordingThatCaughtNothingChoosesNothing() throws {
        let pane = ringPane(undo: undoManager())
        let chooser = try XCTUnwrap(pane.triggerChooser)
        let recorder = KeyRecorder()
        chooser.onRecordingStarted(recorder)
        XCTAssertTrue(chooser.isRecorderOpen)
        chooser.onRecordingStopped(recorder, didRecord: false)
        XCTAssertFalse(chooser.isRecorderOpen)
        XCTAssertEqual(Options.shared.buttons.binding, [])
    }
}

private extension NSMenu {
    func item(withIdentifierForTests identifier: NSUserInterfaceItemIdentifier) -> NSMenuItem? {
        return items.first { $0.identifier == identifier }
    }
}
