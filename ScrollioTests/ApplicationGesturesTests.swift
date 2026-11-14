//
//  ApplicationGesturesTests.swift
//  ScrollioTests
//
//  Gestures of an app's own: how they are stored with the app's entry and what an entry
//  from before reads as, the switch "Use the general gestures", which gesture settings a
//  hold begins with for which app in front, and that a hold keeps them until it ends.
//  (The app's page is in ApplicationPageTests, the settings file in SettingsFileTests.)
//  Nothing is shown, and what a gesture runs goes to the executor's observers.
//

import XCTest
@testable import Scrollio_Debug

private let notesPath = "/Applications/Notes.app"
private let calculatorPath = "/System/Applications/Calculator.app"
private let calculatorProgram = "/System/Applications/Calculator.app/Contents/MacOS/Calculator"

private func list(_ applications: [Application]) -> EnhanceArray<Application> {
    return EnhanceArray<Application>(withArray: applications, matchKey: "path")
}

/// An app on the list whose own gestures are the defaults with `action` up.
private func application(_ path: String, up action: SystemShortcut.Shortcut) -> Application {
    let application = Application(path: path)
    application.setUsesGeneralGestures(false, general: .default)
    var actions = GestureActions.default
    actions.up = GestureAction(action)
    application.setOwnGestures(actions: actions, invertHorizontal: false)
    return application
}

// MARK: - Storage

final class ApplicationGesturesStorageTests: XCTestCase {

    private func storedKeys(of application: Application) throws -> Set<String> {
        let object = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(application)) as? [String: Any]
        return Set(try XCTUnwrap(object).keys)
    }

    /// An entry from before an app could have gestures of its own: it uses the general
    /// gestures, and nothing is added to what is stored for it.
    func testAnEntryFromBeforeUsesTheGeneralGesturesAndIsStoredAsBefore() throws {
        let old = try JSONDecoder().decode(
            Application.self, from: Data(#"{"path":"/Applications/Notes.app","displayName":"","inherit":true}"#.utf8)
        )
        XCTAssertNil(old.gestures)
        XCTAssertTrue(old.usesGeneralGestures)
        XCTAssertNil(old.ownGestures)
        var general = MouseGestureSettings.default
        general.upAction = SystemShortcut.copy.identifier
        general.invertHorizontal = true
        XCTAssertEqual(old.gesturesThatRun(general: general), general)
        XCTAssertEqual(try storedKeys(of: old), ["path", "displayName", "inherit", "scroll"])
        XCTAssertEqual(try storedKeys(of: Application(path: notesPath)), ["path", "displayName", "inherit", "scroll"])
    }

    /// The app's own set is stored with its entry, in the names of the general gesture
    /// settings (the five actions, a label only where there is one, and the invert switch)
    /// beside the switch, and comes back as it was stored, its recorded keys prepared.
    func testAnAppsOwnGesturesAreStoredWithItsEntryAndComeBack() throws {
        let notes = Application(path: notesPath)
        notes.setUsesGeneralGestures(false, general: .default)
        var actions = GestureActions.default
        let reload = ShortcutLabel(name: "Reload", icon: .symbol("arrow.clockwise"))
        actions.up = GestureAction(action: "custom::15:1179648", label: reload)
        actions.left = GestureAction(SystemShortcut.navigateBack)
        actions.click = .none
        notes.setOwnGestures(actions: actions, invertHorizontal: true)

        let data = try XCTUnwrap(list([notes, Application(path: calculatorPath)]).json())
        let stored = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let gestures = try XCTUnwrap(stored[0]["gestures"] as? [String: Any])
        XCTAssertEqual(Set(gestures.keys), [
            "inherit", "upAction", "upLabel", "downAction", "leftAction", "rightAction", "clickAction", "invertHorizontal",
        ], "the mode, the speed, the freeze and the mouse's options are the general ones")
        XCTAssertEqual(gestures["inherit"] as? Bool, false)
        XCTAssertEqual(gestures["upAction"] as? String, "custom::15:1179648")
        XCTAssertEqual(gestures["leftAction"] as? String, "navigateBack")
        XCTAssertEqual(gestures["clickAction"] as? String, "")
        XCTAssertEqual(gestures["invertHorizontal"] as? Bool, true)
        XCTAssertNil(stored[1]["gestures"], "an app without gestures of its own stores none")

        let loaded = try EnhanceArray<Application>(withData: data, matchKey: "path")
        let back = try XCTUnwrap(loaded.get(by: notesPath))
        XCTAssertEqual(back.gestures, notes.gestures)
        XCTAssertFalse(back.usesGeneralGestures)
        XCTAssertEqual(back.ownGestures?.actions.up.label, reload)
        XCTAssertEqual(back.ownGestures?.actions.up.keys, GestureAction.Keys(code: 15, modifiers: 1179648), "prepared when read")
        XCTAssertTrue(try XCTUnwrap(loaded.get(by: calculatorPath)).usesGeneralGestures)

        // What runs: the app's actions and invert switch, the general rest.
        var general = MouseGestureSettings.default
        general.mode = .interactive
        general.trackingSpeed = 2
        general.freezePointer = false
        general.deviceTracking = true
        general.hapticFeedback = false
        let runs = back.gesturesThatRun(general: general)
        XCTAssertEqual(runs.actions, actions)
        XCTAssertTrue(runs.invertHorizontal)
        XCTAssertEqual(runs.action(for: .right), GestureAction(SystemShortcut.navigateBack), "inverted")
        XCTAssertEqual(runs.mode, .interactive)
        XCTAssertEqual(runs.trackingSpeed, 2)
        XCTAssertFalse(runs.freezePointer)
        XCTAssertTrue(runs.deviceTracking)
        XCTAssertFalse(runs.hapticFeedback)
    }

    /// Off: a copy of the general actions and invert switch as they are at that moment,
    /// for an app that never had a set. On: the app's set is kept and not used. Off again:
    /// it comes back as it was left, as an app's own ring does.
    func testTheSwitchStartsFromTheGeneralGesturesAndKeepsTheAppsOwnForLater() {
        var general = MouseGestureSettings.default
        general.downAction = SystemShortcut.copy.identifier
        general.invertHorizontal = true
        let notes = Application(path: notesPath)
        notes.setUsesGeneralGestures(true, general: general)
        XCTAssertNil(notes.gestures, "already on: nothing is stored")
        var unused = GestureActions.default
        unused.up = .none
        notes.setOwnGestures(actions: unused, invertHorizontal: false)
        XCTAssertNil(notes.gestures, "no set of its own to change")

        notes.setUsesGeneralGestures(false, general: general)
        XCTAssertEqual(notes.ownGestures?.actions, general.actions)
        XCTAssertEqual(notes.ownGestures?.invertHorizontal, true)
        var own = general.actions
        own.up = GestureAction(SystemShortcut.paste)
        notes.setOwnGestures(actions: own, invertHorizontal: false)
        // The general gestures change afterwards: the app's own do not follow.
        general.downAction = SystemShortcut.undo.identifier
        XCTAssertEqual(notes.ownGestures?.actions.down.action, "copy")
        XCTAssertEqual(notes.gesturesThatRun(general: general).actions.up.action, "paste")

        notes.setUsesGeneralGestures(true, general: general)
        XCTAssertTrue(notes.usesGeneralGestures)
        XCTAssertNil(notes.ownGestures)
        XCTAssertEqual(notes.gesturesThatRun(general: general), general)
        XCTAssertEqual(notes.gestures?.actions.up.action, "paste", "kept in storage")

        notes.setUsesGeneralGestures(false, general: general)
        XCTAssertEqual(notes.ownGestures?.actions.up.action, "paste", "its own set as it was left")
        XCTAssertEqual(notes.ownGestures?.actions.down.action, "copy", "not a new copy of the general gestures")
        XCTAssertEqual(notes.ownGestures?.invertHorizontal, false)
    }

    /// A stored set is read as the general gestures are; what is no set does not take the
    /// app's entry with it: the app then uses the general gestures.
    func testAStoredSetIsReadAsTheGeneralOneAndWhatIsNoSetLeavesTheAppItsEntry() throws {
        func entry(_ gestures: String) throws -> Application {
            let json = #"{"path":"/Applications/Notes.app","inherit":false,"gestures":"# + gestures + "}"
            return try JSONDecoder().decode(Application.self, from: Data(json.utf8))
        }
        // A missing action is the default one, a label that cannot be read is none, a
        // missing invert switch is off.
        let patchy = try entry(#"{"inherit":false,"upAction":"copy","downLabel":7,"leftAction":"custom::15:1179648","leftLabel":"x"}"#)
        XCTAssertEqual(patchy.ownGestures?.actions.up, GestureAction(SystemShortcut.copy))
        XCTAssertEqual(patchy.ownGestures?.actions.down, GestureActions.default.down)
        XCTAssertEqual(patchy.ownGestures?.actions.left, GestureAction(action: "custom::15:1179648"))
        XCTAssertEqual(patchy.ownGestures?.actions.click, GestureActions.default.click)
        XCTAssertEqual(patchy.ownGestures?.invertHorizontal, false)
        // Without the switch the set is kept and not used.
        let unsaid = try entry(#"{"upAction":"copy","invertHorizontal":true}"#)
        XCTAssertTrue(unsaid.usesGeneralGestures)
        XCTAssertEqual(unsaid.gestures?.actions.up.action, "copy")
        XCTAssertEqual(unsaid.gestures?.invertHorizontal, true)
        XCTAssertTrue(try entry(#"{"inherit":"no","invertHorizontal":"yes"}"#).usesGeneralGestures)
        XCTAssertEqual(try entry(#"{"inherit":false,"invertHorizontal":"yes"}"#).ownGestures?.invertHorizontal, false)
        // An action that is no text, or no object at all: no set, and the entry is read.
        for broken in [#"{"inherit":false,"upAction":7}"#, #""copy""#, "[1,2]", "null"] {
            let application = try entry(broken)
            XCTAssertNil(application.gestures, broken)
            XCTAssertTrue(application.usesGeneralGestures, broken)
            XCTAssertEqual(application.path, notesPath)
            XCTAssertFalse(application.inherit, "the rest of the entry is as stored")
        }
    }

    /// Undo of an app's removal brings its gestures back with the rest of its settings.
    func testTheSettingsUndoMovesCarryTheGestures() {
        let notes = application(notesPath, up: SystemShortcut.copy)
        let again = Application(path: notesPath)
        ApplicationSettings(of: notes).apply(to: again)
        XCTAssertEqual(again.gestures, notes.gestures)
        XCTAssertFalse(again.usesGeneralGestures)
    }
}

// MARK: - Which gestures a hold runs

final class MouseGestureChoiceTests: XCTestCase {

    private typealias FrontApp = ShortcutRingChoice.FrontApp

    private var general = MouseGestureSettings.default
    private var applications = list([])

    override func setUp() {
        super.setUp()
        general = .default
        general.clickAction = SystemShortcut.undo.identifier
        general.mode = .interactive
        let usesGeneral = Application(path: "/Applications/Safari.app")
        // A set of its own that is switched off again.
        let keptForLater = application("/Applications/Mail.app", up: SystemShortcut.paste)
        keptForLater.setUsesGeneralGestures(true, general: general)
        applications = list([
            application(notesPath, up: SystemShortcut.copy),
            application(calculatorProgram, up: SystemShortcut.paste),
            usesGeneral, keptForLater,
        ])
    }

    private func choice(_ front: FrontApp?) -> MouseGestureChoice {
        return MouseGestureChoice.make(front: front, applications: applications, general: general)
    }

    /// The app in front has gestures of its own: its actions run, with the general mode.
    /// The entry is found by the bundle's path, then by the program's, as the ring's is.
    func testAnAppWithGesturesOfItsOwnGetsThem() {
        let notes = choice(FrontApp(bundlePath: notesPath, executablePath: notesPath + "/Contents/MacOS/Notes"))
        XCTAssertTrue(notes.isAppsOwn)
        XCTAssertEqual(notes.settings.actions.up.action, "copy")
        XCTAssertEqual(notes.settings.actions.click, GestureActions.default.click, "the app's own click, not the general one")
        XCTAssertEqual(notes.settings.mode, .interactive, "the mode is the general one")

        let calculator = choice(FrontApp(bundlePath: calculatorPath, executablePath: calculatorProgram))
        XCTAssertTrue(calculator.isAppsOwn, "stored by its program, as a running app is added")
        XCTAssertEqual(calculator.settings.actions.up.action, "paste")
    }

    func testEveryOtherAppGetsTheGeneralGestures() {
        let cases: [(String, FrontApp?)] = [
            ("uses the general gestures", FrontApp(bundlePath: "/Applications/Safari.app", executablePath: nil)),
            ("its own set is switched off", FrontApp(bundlePath: "/Applications/Mail.app", executablePath: nil)),
            ("not on the list", FrontApp(bundlePath: "/Applications/Preview.app", executablePath: "/Applications/Preview.app/Contents/MacOS/Preview")),
            ("no paths", FrontApp(bundlePath: nil, executablePath: nil)),
            ("no app in front", nil),
        ]
        for (name, front) in cases {
            XCTAssertEqual(choice(front), MouseGestureChoice(settings: general, isAppsOwn: false), name)
        }
    }

    /// With Scrollio itself in front (its Settings) the general gestures run, even when
    /// Scrollio stands on the list with gestures of its own.
    func testScrollioItselfGetsTheGeneralGestures() throws {
        let own = try XCTUnwrap(FrontApp.current(NSRunningApplication.current))
        XCTAssertTrue(own.isScrollio)
        let bundle = try XCTUnwrap(own.bundlePath)
        applications = list([application(bundle, up: SystemShortcut.copy)])
        XCTAssertEqual(choice(own), .general(general))
        // The same paths as another process would get the app's set: it is the process that counts.
        XCTAssertTrue(choice(FrontApp(bundlePath: bundle, executablePath: own.executablePath)).isAppsOwn)
    }
}

// MARK: - A hold

final class ApplicationGesturesHoldTests: XCTestCase {

    private typealias FrontApp = ShortcutRingChoice.FrontApp

    /// ⇧⌘R, as the recorder stores it.
    private static let shiftCommandR = "custom::15:1179648"
    private static let notes = FrontApp(bundlePath: notesPath, executablePath: notesPath + "/Contents/MacOS/Notes")
    private static let textEdit = FrontApp(
        bundlePath: "/System/Applications/TextEdit.app", executablePath: "/System/Applications/TextEdit.app/Contents/MacOS/TextEdit"
    )

    private var savedGesture = MouseGestureSettings.default
    private var savedBindings: [ButtonBinding] = []
    private var savedApplications: EnhanceArray<Application>!
    private var savedPost: ((CGEvent) -> Void)!
    private var posted: [CGEvent] = []
    private var logLines: [String] = []
    private var front: FrontApp?
    private var notes: Application!

    override func setUp() {
        super.setUp()
        savedGesture = Options.shared.gesture
        savedBindings = Options.shared.buttons.binding
        savedApplications = Options.shared.application.applications
        savedPost = ShortcutExecutor.shared.post
        posted = []
        logLines = []
        front = nil
        ShortcutExecutor.shared.post = { [weak self] in self?.posted.append($0) }
        ShortcutExecutor.shared.setTestingMouseEventObserver()
        ShortcutExecutor.shared.setTestingKeyboardShortcutObserver()
        MouseInteractionSessionController.shared.setTestingMotionTapHooks()
        MouseInteractionSessionController.shared.clearAllSessions()
        InputProcessor.shared.setTestingMouseGestureLog { [weak self] in self?.logLines.append($0) }
        InputProcessor.shared.setTestingMouseGestureFrontApplication { [weak self] in self?.front }
        InputProcessor.shared.clearActiveBindings()
        // The pointer stays free: nothing here locks the real one.
        var gesture = MouseGestureSettings.default
        gesture.freezePointer = false
        gesture.hapticFeedback = false
        gesture.upAction = SystemShortcut.copy.identifier
        Options.shared.gesture = gesture
        Options.shared.buttons.binding = [ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            systemShortcutName: SystemShortcut.mouseGestureNavigation.identifier,
            isEnabled: true
        )]
        // Notes: a recorded ⇧⌘R up, Paste on the right, Undo on a click.
        let notes = Application(path: notesPath)
        notes.setUsesGeneralGestures(false, general: gesture)
        var own = gesture.actions
        own.up = GestureAction(action: Self.shiftCommandR, label: ShortcutLabel(name: "Reload Notes", icon: .symbol("arrow.clockwise")))
        own.right = GestureAction(SystemShortcut.paste)
        own.click = GestureAction(SystemShortcut.undo)
        notes.setOwnGestures(actions: own, invertHorizontal: false)
        self.notes = notes
        Options.shared.application.applications = EnhanceArray<Application>(
            withArray: [notes, Application(path: "/Applications/Safari.app")], matchKey: "path"
        )
        ButtonUtils.shared.invalidateCache()
    }

    override func tearDown() {
        waitForMainQueue()
        InputProcessor.shared.clearActiveBindings()
        InputProcessor.shared.setTestingMouseGestureLog(nil)
        InputProcessor.shared.setTestingMouseGestureFrontApplication(nil)
        MouseInteractionSessionController.shared.clearAllSessions()
        MouseInteractionSessionController.shared.clearTestingMotionTapHooks()
        ShortcutExecutor.shared.clearTestingMouseEventObserver()
        ShortcutExecutor.shared.clearTestingKeyboardShortcutObserver()
        ShortcutExecutor.shared.post = savedPost
        Options.shared.gesture = savedGesture
        Options.shared.buttons.binding = savedBindings
        Options.shared.application.applications = savedApplications
        ButtonUtils.shared.invalidateCache()
        savedApplications = nil
        notes = nil
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

    /// One hold: the button goes down with `pressed` in front, `meanwhile` comes to the
    /// front, the hand moves by `delta` (none: a click), the button goes up.
    private func hold(_ pressed: FrontApp?, then meanwhile: FrontApp?, moving delta: CGPoint?) {
        front = pressed
        XCTAssertEqual(InputProcessor.shared.process(button(.down)), .consumed)
        front = meanwhile
        if let delta {
            InputProcessor.shared.handleMouseGestureMovement(deltaX: delta.x, deltaY: delta.y)
        }
        XCTAssertEqual(InputProcessor.shared.process(button(.up)), .consumed)
        waitForMainQueue()
    }

    private static let up = CGPoint(x: 0, y: -45)
    private static let right = CGPoint(x: 45, y: 0)

    /// The app in front at the press decides, and the hold keeps that set to its end:
    /// another app that comes to the front meanwhile changes nothing. The recorded key
    /// combination of the app's set is sent as one of the general set is; the log says the
    /// set was the app's own, and never names the app.
    func testAHoldKeepsTheSetItBeganWithWhenAnotherAppComesToTheFront() {
        hold(Self.notes, then: Self.textEdit, moving: Self.up)
        XCTAssertEqual(posted.map { $0.type }, [.keyDown, .keyUp], "Notes' ⇧⌘R")
        XCTAssertEqual(posted.map { $0.getIntegerValueField(.keyboardEventKeycode) }, [15, 15])
        let shiftCommand = UInt64(CGEventFlags.maskShift.rawValue | CGEventFlags.maskCommand.rawValue)
        XCTAssertEqual((posted.first?.flags.rawValue ?? 0) & shiftCommand, shiftCommand)
        XCTAssertEqual(logLines, ["Gestures: up ran a recorded key combination, the app in front has its own gestures"])

        posted = []
        logLines = []
        hold(Self.textEdit, then: Self.notes, moving: Self.up)
        XCTAssertTrue(posted.isEmpty, "no ⇧⌘R")
        XCTAssertEqual(logLines, ["Gestures: up ran copy"], "the general set, kept while Notes came to the front")

        logLines = []
        hold(Self.notes, then: nil, moving: Self.right)
        hold(Self.notes, then: Self.textEdit, moving: nil)
        hold(nil, then: Self.notes, moving: nil)
        XCTAssertEqual(logLines, [
            "Gestures: right ran paste, the app in front has its own gestures",
            "Gestures: click ran undo, the app in front has its own gestures",
            "Gestures: click ran missionControl",
        ])
        for line in logLines {
            XCTAssertFalse(line.contains("Notes") || line.contains("Reload") || line.contains("/"), line)
        }
    }

    /// An app's "Invert left and right" counts for its holds, the general one for every
    /// other app; with the switch on again the app runs the general set.
    func testTheAppsInvertSwitchCountsAndTheGeneralSwitchTakesItsSetOutOfUse() {
        notes.setOwnGestures(actions: try! XCTUnwrap(notes.ownGestures).actions, invertHorizontal: true)
        hold(Self.notes, then: nil, moving: CGPoint(x: -45, y: 0))
        XCTAssertEqual(logLines, ["Gestures: left ran paste, the app in front has its own gestures"], "moving left runs its Right")

        logLines = []
        hold(Self.textEdit, then: nil, moving: CGPoint(x: -45, y: 0))
        XCTAssertEqual(logLines, ["Gestures: left ran moveSpaceLeft"])

        logLines = []
        notes.setUsesGeneralGestures(true, general: Options.shared.gesture)
        hold(Self.notes, then: nil, moving: Self.up)
        XCTAssertEqual(logLines, ["Gestures: up ran copy"])
    }
}
