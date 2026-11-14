//
//  GestureKeysTests.swift
//  ScrollioTests
//
//  A direction of Gesture Navigation, and its click, can run a key combination the user
//  recorded, with a name and an icon, as a place of the Shortcut Ring can: how it is
//  stored (`GestureActions`), what the Gestures pane offers and shows, and how a gesture
//  runs it and says so in the log. The settings file's part is in `SettingsFileTests`.
//

import XCTest
@testable import Scrollio_Debug

/// ⇧⌘R, as the recorder stores it.
private let shiftCommandR = "custom::15:1179648"
private let shiftCommand = UInt64(CGEventFlags.maskShift.rawValue | CGEventFlags.maskCommand.rawValue)

private func label(_ name: String?, symbol: String? = nil, character: String? = nil) -> ShortcutLabel? {
    let icon: ShortcutLabel.Icon? = symbol.map { .symbol($0) } ?? character.map { .character($0) }
    return ShortcutLabel(name: name, icon: icon)
}

private func json<Value: Encodable>(_ value: Value) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}

private func decoded<Value: Decodable>(_ type: Value.Type, _ text: String) throws -> Value {
    return try JSONDecoder().decode(type, from: Data(text.utf8))
}

// MARK: - Storage

final class GestureActionsStorageTests: XCTestCase {

    /// An entry as every version before wrote it (the keys in the order they were
    /// written, a recorded combination in it as a newer build could leave one).
    private let oldEntry = #"{"upAction":"missionControl","downAction":"custom::15:1179648","leftAction":"","#
        + #""rightAction":"moveSpaceRight","clickAction":"missionControl","invertHorizontal":true,"freezePointer":false,"#
        + #""mode":"discrete","trackingSpeed":1.5,"deviceTracking":false,"hapticFeedback":true}"#

    /// An entry from before reads as it did and is written back unchanged: the same
    /// keys, the same values, and no label key.
    func testAnEntryFromBeforeReadsAndIsWrittenBackUnchanged() throws {
        let settings = try decoded(MouseGestureSettings.self, oldEntry)
        XCTAssertEqual(settings.downAction, shiftCommandR)
        XCTAssertNil(settings.actions.down.label)
        XCTAssertEqual(settings.leftAction, "")
        XCTAssertTrue(settings.invertHorizontal)
        XCTAssertEqual(settings.trackingSpeed, 1.5)

        let old = try JSONSerialization.jsonObject(with: Data(oldEntry.utf8)) as? NSDictionary
        let written = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? NSDictionary
        XCTAssertEqual(written, old, "the app's own encoder writes back what was there")
        let sortedOld = try JSONSerialization.data(
            withJSONObject: try JSONSerialization.jsonObject(with: Data(oldEntry.utf8)), options: [.sortedKeys]
        )
        XCTAssertEqual(try json(settings), String(decoding: sortedOld, as: UTF8.self))

        // The defaults hold no label either.
        XCTAssertFalse(try json(MouseGestureSettings.default).contains("Label"))
        // A partial entry still takes the default actions.
        XCTAssertEqual(try decoded(MouseGestureSettings.self, #"{"upAction":"copy"}"#).actions.down, GestureAction(SystemShortcut.appExpose))
    }

    /// A direction's name and icon are stored beside its action, and come back.
    func testANameAndAnIconComeBackForADirectionAndTheClick() throws {
        var settings = MouseGestureSettings.default
        settings.actions.up = GestureAction(action: shiftCommandR, label: label("Reload", symbol: "arrow.clockwise"))
        settings.actions.click = GestureAction(action: shiftCommandR, label: label(nil, character: "R"))
        let stored = try json(settings)
        XCTAssertTrue(stored.contains(#""upAction":"custom::15:1179648","upLabel":{"name":"Reload","symbol":"arrow.clockwise"}"#), stored)
        XCTAssertTrue(stored.contains(#""clickAction":"custom::15:1179648","clickLabel":{"character":"R"}"#), stored)
        XCTAssertFalse(stored.contains("downLabel"))

        let back = try decoded(MouseGestureSettings.self, stored)
        XCTAssertEqual(back, settings)
        XCTAssertEqual(back.actions.up.label?.name, "Reload")
        XCTAssertEqual(back.actions.up.keys, GestureAction.Keys(code: 15, modifiers: shiftCommand), "the keys are what they were")
        XCTAssertEqual(back.actions.click.label?.icon, .character("R"))

        // The set by itself is what an app could hold as its own.
        let set = try json(settings.actions)
        XCTAssertEqual(try decoded(GestureActions.self, set), settings.actions)
        XCTAssertEqual(try json(GestureActions.default),
                       #"{"clickAction":"missionControl","downAction":"appExpose","leftAction":"moveSpaceLeft","#
                        + #""rightAction":"moveSpaceRight","upAction":"missionControl"}"#)
    }

    /// An older version reads an entry by its action keys alone: the keys come through,
    /// the labels are not seen.
    func testAnOlderVersionStillReadsTheActionsOfANamedEntry() throws {
        struct EntryBeforeNames: Decodable {
            let upAction: String
            let downAction: String
            let clickAction: String
        }
        var settings = MouseGestureSettings.default
        settings.actions.up = GestureAction(action: shiftCommandR, label: label("Reload", symbol: "arrow.clockwise"))
        let old = try decoded(EntryBeforeNames.self, try json(settings))
        XCTAssertEqual(old.upAction, shiftCommandR)
        XCTAssertEqual(old.downAction, SystemShortcut.appExpose.identifier)
    }

    /// Only a recorded key combination keeps a label: a listed action, a click and no
    /// action never do, however they were stored; another action drops it, the same keys
    /// keep it.
    func testAnActionThatIsNoKeyCombinationDropsALabel() throws {
        let reload = label("Reload", symbol: "arrow.clockwise")
        for action in ["copy", "missionControl", "mouseBackClick", "", "custom::mouse:5:0"] {
            XCTAssertNil(GestureAction(action: action, label: reload).label, action)
        }
        let entry = try decoded(MouseGestureSettings.self, #"{"downAction":"copy","downLabel":{"name":"Paste"},"upLabel":7}"#)
        XCTAssertEqual(entry.actions.down, GestureAction(SystemShortcut.copy))
        XCTAssertEqual(entry.actions.up, GestureAction(SystemShortcut.missionControl), "a label that cannot be read is none")
        XCTAssertFalse(try json(entry).contains("Label"))

        var settings = MouseGestureSettings.default
        settings.actions.up = GestureAction(action: shiftCommandR, label: reload)
        settings.upAction = shiftCommandR
        XCTAssertEqual(settings.actions.up.label, reload, "the same keys keep their name")
        settings.upAction = SystemShortcut.copy.identifier
        XCTAssertNil(settings.actions.up.label)
        XCTAssertEqual(try decoded(MouseGestureSettings.self, try json(settings)).actions.up, GestureAction(SystemShortcut.copy))
    }

    /// A direction runs what a place of the ring runs, resolved the same way: a recorded
    /// key combination from keys read once, never a modifier key by itself or a recorded
    /// mouse button.
    func testADirectionRunsWhatAPlaceOfTheRingRuns() {
        let keys = GestureAction(action: shiftCommandR)
        XCTAssertEqual(keys.keys, GestureAction.Keys(code: 15, modifiers: shiftCommand))
        guard case .customKey(let code, let modifiers)? = keys.resolvedAction,
              case .customKey(let ringCode, let ringModifiers)? = ShortcutRingPlace(action: shiftCommandR).resolvedAction else {
            return XCTFail("a recorded combination is sent as a key")
        }
        XCTAssertEqual(code, ringCode)
        XCTAssertEqual(modifiers, ringModifiers)

        for nothing in ["custom::56:0", "custom::mouse:5:0", "teleport"] {
            XCTAssertNil(GestureAction(action: nothing).keys, nothing)
            XCTAssertNil(GestureAction(action: nothing).resolvedAction, nothing)
            XCTAssertFalse(StoredAction.isKnown(gestureAction: nothing), nothing)
            XCTAssertFalse(ShortcutRingPlace(action: nothing).runs, nothing)
        }
        XCTAssertTrue(StoredAction.isKnown(gestureAction: shiftCommandR))
        XCTAssertTrue(StoredAction.isKnown(gestureAction: SystemShortcut.mouseBackClick.identifier))
        // Version 1.0.5 resolves a direction by its name alone (the same code as here):
        // a recorded combination is nothing to it, so it runs nothing and nothing else.
        XCTAssertNil(ShortcutExecutor.shared.resolveAction(named: shiftCommandR))
        XCTAssertNotNil(GestureAction(SystemShortcut.copy).resolvedAction)
        XCTAssertNil(GestureAction.none.resolvedAction)
    }
}

// MARK: - Running it

final class GestureKeysRunTests: XCTestCase {

    private var savedGesture = MouseGestureSettings.default
    private var savedBindings: [ButtonBinding] = []
    private var savedPost: ((CGEvent) -> Void)!
    private var posted: [CGEvent] = []
    private var logLines: [String] = []

    override func setUp() {
        super.setUp()
        savedGesture = Options.shared.gesture
        savedBindings = Options.shared.buttons.binding
        savedPost = ShortcutExecutor.shared.post
        posted = []
        logLines = []
        ShortcutExecutor.shared.post = { [weak self] in self?.posted.append($0) }
        ShortcutExecutor.shared.setTestingMouseEventObserver()
        ShortcutExecutor.shared.setTestingKeyboardShortcutObserver()
        MouseInteractionSessionController.shared.setTestingMotionTapHooks()
        MouseInteractionSessionController.shared.clearAllSessions()
        InputProcessor.shared.setTestingMouseGestureLog { [weak self] in self?.logLines.append($0) }
        InputProcessor.shared.clearActiveBindings()
        // The pointer stays free: nothing here locks the real one.
        var gesture = MouseGestureSettings.default
        gesture.freezePointer = false
        gesture.hapticFeedback = false
        Options.shared.gesture = gesture
        Options.shared.buttons.binding = [ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            systemShortcutName: SystemShortcut.mouseGestureNavigation.identifier,
            isEnabled: true
        )]
        ButtonUtils.shared.invalidateCache()
    }

    override func tearDown() {
        waitForMainQueue()
        InputProcessor.shared.clearActiveBindings()
        InputProcessor.shared.setTestingMouseGestureLog(nil)
        MouseInteractionSessionController.shared.clearAllSessions()
        MouseInteractionSessionController.shared.clearTestingMotionTapHooks()
        ShortcutExecutor.shared.clearTestingMouseEventObserver()
        ShortcutExecutor.shared.clearTestingKeyboardShortcutObserver()
        ShortcutExecutor.shared.post = savedPost
        Options.shared.gesture = savedGesture
        Options.shared.buttons.binding = savedBindings
        ButtonUtils.shared.invalidateCache()
        super.tearDown()
    }

    private func button(_ phase: InputPhase) -> InputEvent {
        return InputEvent(type: .mouse, code: 3, modifiers: [], phase: phase, source: .hidPP, device: nil)
    }

    private func waitForMainQueue() {
        let done = expectation(description: "main queue")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 1)
    }

    private func described(_ events: [CGEvent]) -> [String] {
        return events.map { event in
            "\(event.type.rawValue) \(event.getIntegerValueField(.keyboardEventKeycode)) "
                + "\(event.flags.rawValue & shiftCommand) \(event.getIntegerValueField(.eventSourceUserData))"
        }
    }

    /// Up with a named ⇧⌘R: one press of ⇧⌘R through the executor, the events a place
    /// of the ring sends for the same keys, and one line in the log that says what kind
    /// of thing ran, never its name or its keys.
    func testADirectionWithARecordedCombinationSendsItAsAPlaceOfTheRingDoes() {
        Options.shared.gesture.actions.up = GestureAction(action: shiftCommandR, label: label("Reload Secretly", symbol: "arrow.clockwise"))

        XCTAssertEqual(InputProcessor.shared.process(button(.down)), .consumed)
        InputProcessor.shared.handleMouseGestureMovement(deltaX: 0, deltaY: -45)
        XCTAssertEqual(InputProcessor.shared.process(button(.up)), .consumed)
        waitForMainQueue()

        XCTAssertEqual(posted.map { $0.type }, [.keyDown, .keyUp])
        XCTAssertEqual(posted.map { $0.getIntegerValueField(.keyboardEventKeycode) }, [15, 15])
        XCTAssertEqual((posted.first?.flags.rawValue ?? 0) & shiftCommand, shiftCommand)
        for event in posted {
            XCTAssertEqual(event.getIntegerValueField(.eventSourceUserData), ScrollioEventMarker.syntheticCustom)
        }
        let sentByTheGesture = described(posted)
        posted = []
        ShortcutRingController.run(ShortcutRingPlace(action: shiftCommandR))
        XCTAssertEqual(sentByTheGesture, described(posted), "the same keys, the same modifiers, the same marker")

        XCTAssertEqual(logLines, ["Gestures: up ran a recorded key combination"])
        for line in logLines {
            XCTAssertFalse(line.contains("Reload") || line.contains("Secretly") || line.contains("arrow"), line)
            XCTAssertFalse(line.contains("custom::") || line.contains("15"), line)
        }
    }

    /// The click of the gesture button with a recorded combination sends it too; a listed
    /// action is logged by its identifier.
    func testTheClickWithARecordedCombinationSendsIt() {
        Options.shared.gesture.actions.click = GestureAction(action: shiftCommandR)
        XCTAssertEqual(InputProcessor.shared.process(button(.down)), .consumed)
        XCTAssertEqual(InputProcessor.shared.process(button(.up)), .consumed)
        waitForMainQueue()
        XCTAssertEqual(posted.map { $0.type }, [.keyDown, .keyUp])
        XCTAssertEqual(logLines, ["Gestures: click ran a recorded key combination"])

        posted = []
        logLines = []
        Options.shared.gesture.actions.click = GestureAction(SystemShortcut.copy)
        XCTAssertEqual(InputProcessor.shared.process(button(.down)), .consumed)
        XCTAssertEqual(InputProcessor.shared.process(button(.up)), .consumed)
        waitForMainQueue()
        XCTAssertEqual(logLines, ["Gestures: click ran copy"])
    }

    /// What a direction cannot run sends nothing and leaves no line: a modifier key by
    /// itself, stored by hand.
    func testAModifierKeyByItselfSendsNothing() {
        Options.shared.gesture.actions.up = GestureAction(action: "custom::56:0")
        XCTAssertEqual(InputProcessor.shared.process(button(.down)), .consumed)
        InputProcessor.shared.handleMouseGestureMovement(deltaX: 0, deltaY: -45)
        XCTAssertEqual(InputProcessor.shared.process(button(.up)), .consumed)
        waitForMainQueue()
        XCTAssertTrue(posted.isEmpty)
        XCTAssertTrue(logLines.isEmpty)
    }

    /// The line itself, for each part of a gesture.
    func testTheLogLineNamesTheKindNeverTheName() {
        let named = GestureAction(action: shiftCommandR, label: label("Open Secret Vault"))
        XCTAssertEqual(InputProcessor.mouseGestureRunLine(named, part: .direction(.left)), "Gestures: left ran a recorded key combination")
        XCTAssertEqual(InputProcessor.mouseGestureRunLine(GestureAction(SystemShortcut.missionControl), part: .click),
                       "Gestures: click ran missionControl")
        XCTAssertEqual(named.logName, GestureAction(action: shiftCommandR).logName)
    }
}

// MARK: - The pane

/// A popover that builds its content and counts as open, without a window.
private final class StillPopover: KeyPopover {
    private(set) var standsOpen = false

    override var isOpen: Bool {
        return standsOpen
    }

    override func show(at sourceView: NSView, waitingHint: String) {
        announce = { _ in }
        testingPrepareContent(waitingHint: waitingHint)
        standsOpen = true
    }

    override func showDetails(at sourceView: NSView, keys: [String], label: ShortcutLabel?) {
        announce = { _ in }
        testingPrepareDetails(keys: keys, label: label)
        standsOpen = true
    }

    override func hide() {
        standsOpen = false
        super.hide()
    }
}

final class GestureKeysPaneTests: XCTestCase {

    typealias Slot = MouseGestureSettingsControls.Slot

    private var savedGesture = MouseGestureSettings.default
    private var logitech = false

    override func setUp() {
        super.setUp()
        savedGesture = Options.shared.gesture
        Options.shared.gesture = .default
        logitech = false
    }

    override func tearDown() {
        Options.shared.gesture = savedGesture
        super.tearDown()
    }

    private var keys: String {
        return ButtonTriggerNaming.shortcutText(type: .keyboard, code: 15, modifiers: shiftCommand)
    }

    private func makeController() -> GesturesPreferencesViewController {
        let controller = GesturesPreferencesViewController(isInteractiveAvailable: { true })
        controller.deviceSource = MouseGestureDeviceSource(support: { .none }, refresh: {})
        controller.bindingSummary = { [weak self] in
            MouseGestureBindingSummary(hasGestureButton: true, hasLogitechGestureButton: self?.logitech ?? false)
        }
        _ = controller.view
        controller.controls.startShortcutRecorder = { _ in }
        for popUp in controller.controls.actionPopUps {
            popUp.makeDetailsPopover = { StillPopover() }
            popUp.presentShortcutDetails = { popover, anchor, keys, label in
                popover.showDetails(at: anchor, keys: keys, label: label)
            }
        }
        return controller
    }

    private func everything(in menu: NSMenu?) -> [NSMenuItem] {
        return (menu?.items ?? []).flatMap { [$0] + everything(in: $0.submenu) }
    }

    private func pressed(_ code: UInt16, _ modifiers: CGEventFlags) -> InputEvent {
        return InputEvent(type: .keyboard, code: code, modifiers: modifiers, phase: .down, source: .hidPP, device: nil)
    }

    private var shiftCommandRPressed: InputEvent {
        return pressed(15, CGEventFlags(rawValue: shiftCommand))
    }

    /// The recorder's side of a recording that caught `event`.
    private func record(_ event: InputEvent, into pullDown: ButtonActionPullDown, popover: KeyPopover) -> Bool {
        pullDown.onEventRecorded(KeyRecorder(), didRecordEvent: event, isDuplicate: false)
        popover.keyPreview?.update(from: event.displayComponents, status: .recorded)
        return pullDown.takesPopover(KeyRecorder(), popover)
    }

    private func type(_ text: String, into field: NSTextField, of editor: ShortcutLabelEditorView) {
        field.stringValue = text
        editor.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
    }

    /// Every direction and the click offer "Keyboard Shortcut…" after the pane's own
    /// actions, which are all still there and nothing more: no "Open App or File…", no
    /// Gesture Navigation, no Shortcut Ring, no modifier keys or scroll holds.
    func testEveryDirectionAndTheClickOfferKeyboardShortcutBesideTheirOwnActions() {
        let controller = makeController()
        for showsLogitech in [false, true] {
            logitech = showsLogitech
            controller.reload()
            let own = MouseGestureSettingsControls.actionCategories(showLogiActions: showsLogitech).flatMap { $0.shortcuts.map(\.identifier) }
            for slot in Slot.allCases {
                let items = everything(in: controller.controls.actionPopUp(for: slot).menu)
                let listed = items.compactMap { ($0.representedObject as? SystemShortcut.Shortcut)?.identifier }
                let markers = items.compactMap { $0.representedObject as? String }
                XCTAssertEqual(listed, own, "\(slot.name), Logitech \(showsLogitech)")
                XCTAssertEqual(markers, [ShortcutManager.MenuMarker.keyboardShortcut], slot.name)
                XCTAssertEqual(items.last?.representedObject as? String, ShortcutManager.MenuMarker.keyboardShortcut)
                XCTAssertNotNil(items.first { $0.representedObject == nil && $0.action != nil }, "No Action")
            }
        }
    }

    /// "Keyboard Shortcut…" in a row: the keys are stored at once, the popover stays for
    /// the name and the icon, which are stored when it closes; the row then shows the
    /// icon, the name and the keys in grey, and the preview the icon.
    func testARowRecordsStoresAndShowsANamedCombination() throws {
        let controller = makeController()
        let up = controller.controls.actionPopUp(for: .up)
        let popover = StillPopover()
        popover.show(at: up, waitingHint: "")
        XCTAssertTrue(record(shiftCommandRPressed, into: up, popover: popover))
        XCTAssertEqual(Options.shared.gesture.actions.up, GestureAction(action: shiftCommandR), "the keys are stored at once")
        XCTAssertTrue(popover.isShowingDetails)

        let editor = try XCTUnwrap(popover.labelEditor)
        type("Reload", into: editor.nameField, of: editor)
        editor.chooseSymbol("arrow.clockwise")
        editor.doneButton.performClick(nil)
        let reload = label("Reload", symbol: "arrow.clockwise")
        XCTAssertEqual(Options.shared.gesture.actions.up, GestureAction(action: shiftCommandR, label: reload))

        let title = try XCTUnwrap(up.menu?.items.first)
        XCTAssertEqual(title.title, "Reload  \(keys)")
        XCTAssertEqual(title.attributedTitle?.string, "Reload  \(keys)")
        let range = ((title.attributedTitle?.string ?? "") as NSString).range(of: keys)
        XCTAssertEqual(title.attributedTitle?.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor,
                       .secondaryLabelColor)
        XCTAssertNotNil(title.image)

        // The preview shows the icon when the row is pointed at.
        controller.slotHoverChanged(.up, inside: true)
        XCTAssertEqual(GesturePreviewLoop.legs(for: controller.previewView.scene).first?.effect, .pulse(symbolName: "arrow.clockwise"))

        // "Keyboard Shortcut…" again: the name and the icon, nothing recorded.
        let item = try XCTUnwrap(everything(in: up.menu).first {
            $0.representedObject as? String == ShortcutManager.MenuMarker.keyboardShortcut
        })
        up.shortcutSelected(item)
        let details = try XCTUnwrap(up.detailsPopover)
        XCTAssertTrue(details.isShowingDetails)
        XCTAssertEqual(details.labelEditor?.nameField.stringValue, "Reload")
        details.hide()

        // A listed action in its place: the name goes with the keys.
        let copy = try XCTUnwrap(everything(in: up.menu).first {
            ($0.representedObject as? SystemShortcut.Shortcut)?.identifier == SystemShortcut.copy.identifier
        })
        up.shortcutSelected(copy)
        XCTAssertEqual(Options.shared.gesture.actions.up, GestureAction(SystemShortcut.copy))
        XCTAssertEqual(up.menu?.items.first?.title, SystemShortcut.copy.localizedName)
        XCTAssertNil(up.menu?.items.first?.attributedTitle)
    }

    /// "Keyboard Shortcut…" on a row that holds keys: the popover with their name, typed
    /// and not confirmed with Done.
    private func typeName(_ name: String, into pullDown: ButtonActionPullDown) throws -> KeyPopover {
        pullDown.makeDetailsPopover = { StillPopover() }
        pullDown.presentShortcutDetails = { popover, anchor, keys, label in
            popover.showDetails(at: anchor, keys: keys, label: label)
        }
        let item = try XCTUnwrap(everything(in: pullDown.menu).first {
            $0.representedObject as? String == ShortcutManager.MenuMarker.keyboardShortcut
        })
        pullDown.shortcutSelected(item)
        let details = try XCTUnwrap(pullDown.detailsPopover)
        let editor = try XCTUnwrap(details.labelEditor)
        type(name, into: editor.nameField, of: editor)
        return details
    }

    /// A name typed in the popover is kept when the click that closes the popover is
    /// "Reset to Defaults", whenever the popover reports its close: editing ends before
    /// the reset takes what it can give back, so Undo brings the keys back with the name.
    func testANameTypedBeforeResetToDefaultsComesBackWithUndo() throws {
        Options.shared.gesture.actions.up = GestureAction(action: shiftCommandR)
        let controller = makeController()
        let undo = UndoManager()
        undo.groupsByEvent = false
        controller.paneUndoManager = undo
        let details = try typeName("Reload", into: controller.controls.actionPopUp(for: .up))

        undo.beginUndoGrouping()
        controller.resetToDefaultsButton.performClick(nil)
        undo.endUndoGrouping()
        details.hide()
        XCTAssertEqual(Options.shared.gesture, .default)
        undo.undo()
        XCTAssertEqual(Options.shared.gesture.actions.up, GestureAction(action: shiftCommandR, label: label("Reload")))
    }

    /// On an app's page the same for "Use the general gestures": the name typed into a row
    /// of the app's own set is in that set when it comes back.
    func testANameTypedBeforeUseTheGeneralGesturesIsKeptInTheAppsSet() throws {
        let notes = Application(path: "/System/Applications/Notes.app")
        notes.setUsesGeneralGestures(false, general: .default)
        var actions = GestureActions.default
        actions.up = GestureAction(action: shiftCommandR)
        notes.setOwnGestures(actions: actions, invertHorizontal: false)
        let part = ApplicationGesturesPartViewController(application: notes)
        part.showsLogiActions = { false }
        _ = part.view
        let details = try typeName("Reload", into: try XCTUnwrap(part.controls).actionPopUp(for: .up))

        part.generalGesturesSwitch.state = .on
        XCTAssertTrue(part.generalGesturesSwitch.sendAction(part.generalGesturesSwitch.action, to: part.generalGesturesSwitch.target))
        details.hide()
        XCTAssertTrue(notes.usesGeneralGestures)
        XCTAssertEqual(notes.gestures?.actions.up, GestureAction(action: shiftCommandR, label: label("Reload")), "kept for later with its name")
        XCTAssertEqual(Options.shared.gesture, .default, "the general gestures are untouched")
    }

    /// The same in the Shortcut Ring: its pane's "Reset to Defaults" and an app's "Use the
    /// general ring" keep a name typed into a place's popover.
    func testANameTypedBeforeTheRingIsResetOrItsAppUsesTheGeneralRingIsKept() throws {
        let savedRing = Options.shared.ring
        addTeardownBlock {
            Options.shared.ring = savedRing
            ShortcutRingController.forgetPreparedFaces()
        }
        var ring = ShortcutRingSettings.default
        ring[0] = ShortcutRingPlace(action: shiftCommandR)
        Options.shared.ring = ring
        let pane = RingPreferencesViewController()
        pane.bindingSummary = { ShortcutRingBindingSummary(triggerTitles: ["Thumb panel"]) }
        _ = pane.view
        let undo = UndoManager()
        undo.groupsByEvent = false
        pane.paneUndoManager = undo
        let details = try typeName("Reload", into: pane.placePopUps[0])
        undo.beginUndoGrouping()
        pane.resetToDefaultsButton.performClick(nil)
        undo.endUndoGrouping()
        details.hide()
        XCTAssertEqual(Options.shared.ring, .default)
        undo.undo()
        XCTAssertEqual(Options.shared.ring[0], ShortcutRingPlace(action: shiftCommandR, label: label("Reload")))

        let notes = Application(path: "/System/Applications/Notes.app")
        notes.setUsesGeneralRing(false, general: ring)
        let part = ApplicationRingPartViewController(application: notes)
        _ = part.view
        let own = try typeName("Reload", into: try XCTUnwrap(part.ringController).placePopUps[0])
        part.generalRingRow.toggle.state = .on
        XCTAssertTrue(part.generalRingRow.toggle.sendAction(part.generalRingRow.toggle.action, to: part.generalRingRow.toggle.target))
        own.hide()
        XCTAssertTrue(notes.usesGeneralRing)
        XCTAssertEqual(notes.ring?[0], ShortcutRingPlace(action: shiftCommandR, label: label("Reload")), "kept for later with its name")
    }

    /// Keys without a name show as keys; a recorded listed shortcut is that action; what
    /// a direction cannot run is refused when it is pressed, with the gesture's own words.
    func testWhatARowTakesAndRefuses() throws {
        let controller = makeController()
        let click = controller.controls.actionPopUp(for: .click)
        let popover = StillPopover()
        popover.show(at: click, waitingHint: "")
        XCTAssertTrue(record(shiftCommandRPressed, into: click, popover: popover))
        popover.hide()
        XCTAssertEqual(Options.shared.gesture.actions.click, GestureAction(action: shiftCommandR))
        XCTAssertEqual(click.menu?.items.first?.title, keys)
        XCTAssertNil(click.menu?.items.first?.attributedTitle)

        XCTAssertFalse(record(pressed(8, .maskCommand), into: click, popover: StillPopover()), "⌘C is Copy")
        XCTAssertEqual(Options.shared.gesture.actions.click, GestureAction(SystemShortcut.copy))

        let recorder = KeyRecorder()
        let middle = InputEvent(type: .mouse, code: 2, modifiers: [], phase: .down, source: .hidPP, device: nil)
        let shift = InputEvent(type: .keyboard, code: 56, modifiers: .maskShift, phase: .down, source: .hidPP, device: nil)
        let back = InputEvent(type: .mouse, code: 3, modifiers: [], phase: .down, source: .hidPP, device: nil)
        for refused in [middle, shift] {
            XCTAssertFalse(click.validateRecordedEvent(recorder, event: refused))
            XCTAssertEqual(click.refusalHint(recorder, event: refused), "A gesture takes a shortcut or a key")
        }
        XCTAssertTrue(click.validateRecordedEvent(recorder, event: back), "the Back button is the Back click")
        XCTAssertTrue(click.validateRecordedEvent(recorder, event: shiftCommandRPressed))
        XCTAssertEqual(click.waitingHint(recorder, mode: .adaptive), "Press a shortcut or a key")
    }

    /// While the desktop follows the hand, Left and Right say so, whatever they hold.
    func testFollowingTheHandCoversANamedCombinationOnTheSides() {
        Options.shared.gesture.actions.left = GestureAction(action: shiftCommandR, label: label("Reload"))
        Options.shared.gesture.mode = .interactive
        let controller = makeController()
        let left = controller.controls.actionPopUp(for: .left)
        XCTAssertFalse(left.isEnabled)
        XCTAssertEqual(left.menu?.items.first?.title, "Desktop follows the hand")
        XCTAssertNil(left.menu?.items.first?.attributedTitle)
        XCTAssertNil(left.menu?.items.first?.image)

        controller.controls.modeControl.selectedSegment = 0
        _ = controller.controls.modeControl.sendAction(controller.controls.modeControl.action, to: controller.controls.modeControl.target)
        XCTAssertTrue(left.isEnabled)
        XCTAssertEqual(left.menu?.items.first?.title, "Reload  \(keys)", "the stored combination is the row's again")
    }

    /// The preview shows a recorded combination by its icon, else by its keys.
    func testThePreviewShowsTheIconOrTheKeys() {
        XCTAssertEqual(GesturePreviewEffect(action: GestureAction(action: shiftCommandR, label: label("Reload", symbol: "arrow.clockwise"))),
                       .pulse(symbolName: "arrow.clockwise"))
        XCTAssertEqual(GesturePreviewEffect(action: GestureAction(action: shiftCommandR, label: label(nil, character: "R"))),
                       .pulseText("R"))
        XCTAssertEqual(GesturePreviewEffect(action: GestureAction(action: shiftCommandR, label: label("Reload"))), .pulseText(keys))
        XCTAssertEqual(GesturePreviewEffect(action: GestureAction(action: shiftCommandR)), .pulseText(keys))
        XCTAssertEqual(GesturePreviewEffect(action: GestureAction(action: shiftCommandR, label: label(nil, symbol: "no.such.symbol.anywhere"))),
                       .pulseText(keys))
        XCTAssertEqual(GesturePreviewEffect(action: GestureAction(action: "custom::8:1048576")), .pulse(symbolName: SystemShortcut.copy.symbolName),
                       "the keys of Copy without a name are Copy")
        XCTAssertEqual(GesturePreviewEffect(action: GestureAction(SystemShortcut.missionControl)), .missionControl)

        var scene = GesturePreviewScene()
        scene.gesture.actions.click = GestureAction(action: shiftCommandR)
        scene.focus = .click
        let loop = GesturePreviewLoop(scene: scene)
        let still = loop.frame(at: loop.legs[0].stillTime)
        XCTAssertEqual(still.pulse, 1, accuracy: 1e-9)
        XCTAssertEqual(still.pulseText, keys)
        XCTAssertNil(still.pulseSymbol)
    }
}
