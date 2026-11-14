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
