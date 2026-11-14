//
//  ApplicationThumbWheelTests.swift
//  ScrollioTests
//
//  The thumb wheel of an app's own (`ApplicationThumbWheel`): how the app's entry stores it
//  and what an entry from before reads as, the settings file and its import sheet, the mark
//  of the list of apps, that it takes nothing from a Logitech mouse; the row of the app's
//  Buttons part ("+", its pull-down, "−" and Undo); and which function a turn runs through
//  the scroll tap (the app in front at the turn's first event, kept until the wheel rests).
//  Nothing is shown on screen and nothing reaches the system: menus go through seams,
//  windows are never ordered in, actions are recorded by the engine's rig.
//

import XCTest
@testable import Scrollio_Debug

private typealias FrontApp = ShortcutRingChoice.FrontApp

// MARK: - The app's entry, the file, the mark

final class ApplicationThumbWheelTests: XCTestCase {

    private func dictionary(_ application: Application) throws -> NSDictionary {
        let data = try JSONEncoder().encode(application)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    private func read(_ text: String) throws -> Application {
        return try JSONDecoder().decode(Application.self, from: Data(text.utf8))
    }

    /// Stored under "thumbWheel" in the general settings' name, only while the app has a
    /// function of its own, and read back as it was; nil stores nothing again.
    func testTheAppsFunctionIsStoredOnItsEntryAndReadBack() throws {
        let notes = Application(path: "/Applications/Notes.app")
        XCTAssertNil(try dictionary(notes)["thumbWheel"], "nothing stored for an app without one")
        for function in ThumbWheelFunction.allCases {
            notes.setOwnThumbWheelFunction(function)
            XCTAssertEqual(try dictionary(notes)["thumbWheel"] as? NSDictionary, ["function": function.rawValue])
            let again = try JSONDecoder().decode(Application.self, from: JSONEncoder().encode(notes))
            XCTAssertEqual(again.ownThumbWheelFunction, function)
            XCTAssertEqual(again.thumbWheel, notes.thumbWheel)
        }
        XCTAssertEqual(ApplicationThumbWheel(function: .zoom), ApplicationThumbWheel(function: .zoom))
        notes.setOwnThumbWheelFunction(nil)
        XCTAssertNil(notes.thumbWheel)
        XCTAssertNil(try dictionary(notes)["thumbWheel"], "given back: stored as an entry without one")
    }

    /// An entry from before (as version 1.0.5 wrote it): the general function, and it is
    /// written back exactly as it was.
    func testAnEntryFromBeforeReadsAsTheGeneralFunctionAndIsStoredAsBefore() throws {
        let older = try read(StoredDataCanaryTests.readableApp)
        XCTAssertNil(older.thumbWheel)
        XCTAssertNil(older.ownThumbWheelFunction)
        XCTAssertFalse(older.hasOwnButtonsPart)
        let original = try JSONSerialization.jsonObject(with: Data(StoredDataCanaryTests.readableApp.utf8)) as? NSDictionary
        XCTAssertEqual(try dictionary(older), original)
    }

    /// What cannot be read takes nothing of the entry with it and is none; a function of a
    /// later version is kept as stored and not used, until the page sets one.
    func testAThumbWheelThatCannotBeReadIsNoneAndALaterVersionsFunctionIsKept() throws {
        for broken in [#""thumbWheel":3"#, #""thumbWheel":{"speed":2}"#, #""thumbWheel":{"function":7}"#, #""thumbWheel":null"#] {
            let entry = try read(#"{"path":"/Applications/A.app","inherit":false,"# + broken + "}")
            XCTAssertEqual(entry.path, "/Applications/A.app", broken)
            XCTAssertFalse(entry.inherit, broken)
            XCTAssertNil(entry.thumbWheel, broken)
        }
        let later = try read(#"{"path":"/Applications/A.app","thumbWheel":{"function":"brightness"}}"#)
        XCTAssertNil(later.ownThumbWheelFunction, "not used")
        XCTAssertFalse(later.hasOwnButtonsPart)
        XCTAssertEqual(try dictionary(later)["thumbWheel"] as? NSDictionary, ["function": "brightness"], "written back as stored")
        later.setOwnThumbWheelFunction(nil)
        XCTAssertNotNil(later.thumbWheel, "nothing to give back: kept")
        later.setOwnThumbWheelFunction(.tabs)
        XCTAssertEqual(try dictionary(later)["thumbWheel"] as? NSDictionary, ["function": "tabs"])
    }

    /// The own function of the app in front, found by its bundle's path or its program's;
    /// any other app, Scrollio itself and no app: the general function. While no app on the
    /// list has one, the app in front is not even asked.
    func testATurnRunsTheOwnFunctionOfTheAppInFrontOnly() {
        let figma = Application(path: "/Applications/Figma.app")
        figma.setOwnThumbWheelFunction(.zoom)
        let tool = Application(path: "/usr/local/bin/tool")
        tool.setOwnThumbWheelFunction(.volume)
        let notes = Application(path: "/Applications/Notes.app")
        let list = EnhanceArray<Application>(withArray: [figma, tool, notes], matchKey: "path")
        var asked = 0
        func choice(_ front: FrontApp?) -> ThumbWheelFunction? {
            return ThumbWheelChoice.ownFunction(front: { asked += 1; return front }, applications: list)
        }
        XCTAssertEqual(choice(FrontApp(bundlePath: figma.path, executablePath: figma.path + "/Contents/MacOS/Figma")), .zoom)
        XCTAssertEqual(choice(FrontApp(bundlePath: nil, executablePath: tool.path)), .volume, "by the program's path")
        XCTAssertNil(choice(FrontApp(bundlePath: notes.path)), "on the list, without one")
        XCTAssertNil(choice(FrontApp(bundlePath: "/Applications/Safari.app")), "not on the list")
        XCTAssertNil(choice(FrontApp(bundlePath: figma.path, isScrollio: true)), "Scrollio's settings in front")
        XCTAssertNil(choice(nil))
        XCTAssertEqual(asked, 6)

        figma.setOwnThumbWheelFunction(nil)
        tool.setOwnThumbWheelFunction(nil)
        asked = 0
        XCTAssertNil(choice(FrontApp(bundlePath: figma.path)))
        XCTAssertEqual(asked, 0, "no app has one: the app in front is not asked")
    }

    /// The Buttons mark of the list counts the thumb wheel ("Default" too: the app's own).
    func testTheButtonsMarkCountsAnAppsOwnThumbWheel() {
        let app = Application(path: "/Applications/Figma.app")
        XCTAssertEqual(ApplicationPagePart.ownSettings(of: app), [])
        app.setOwnThumbWheelFunction(.scroll)
        XCTAssertEqual(ApplicationPagePart.ownSettings(of: app), [.buttons])
        XCTAssertFalse(app.hasOwnButtons, "no button of its own")
        app.setOwnThumbWheelFunction(nil)
        XCTAssertEqual(ApplicationPagePart.ownSettings(of: app), [])
    }

    /// Undo of an app's removal gives the entry added again its thumb wheel too.
    func testTheSettingsUndoMovesBetweenEntriesCarryTheThumbWheel() {
        let app = Application(path: "/Applications/Figma.app")
        app.setOwnThumbWheelFunction(.volume)
        let again = Application(path: "/Applications/Figma.app")
        ApplicationSettings(of: app).apply(to: again)
        XCTAssertEqual(again.ownThumbWheelFunction, .volume)
    }

    /// No function needs the wheel diverted (every one runs from the sideways wheel's events
    /// at the scroll tap): an app's own function takes no Logitech button from the mouse,
    /// and the log line about the apps' own Logitech buttons does not count such an app.
    func testAnAppsOwnThumbWheelTakesNothingFromTheMouse() {
        let general = [ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 1006, modifiers: 0, deviceFilter: nil), systemShortcutName: "copy"
        )]
        let figma = Application(path: "/Applications/Figma.app")
        figma.setOwnThumbWheelFunction(.zoom)
        let list = EnhanceArray<Application>(withArray: [figma], matchKey: "path")
        let isLogiCode: (UInt16) -> Bool = { $0 >= 1000 }
        XCTAssertEqual(LogiUsageBootstrap.ownLogitechButtons(general: general, applications: list, isLogiCode: isLogiCode), .none)
        XCTAssertEqual(
            LogiUsageBootstrap.buttonBindingCodes(general: general, frontAppOwn: figma.ownButtonBindings, isLogiCode: isLogiCode),
            [1006]
        )
    }

    /// The roll's line says when the function was the app's own, never which app.
    func testTheRollsLineSaysWhenTheFunctionWasTheAppsOwn() {
        var roll = ScrollSystemLog.ThumbWheelRoll(id: 1, settings: ThumbWheelSettings(function: .zoom), at: 0)
        roll.add(ThumbWheelEvent(lineDelta: -1, fixedDelta: -1, pointDelta: -10, isContinuous: false), at: 0)
        let general = ScrollSystemLog.thumbWheelMessage(for: roll)
        XCTAssertTrue(general.contains(", zoom x1.00, "), general)
        roll.isAppsOwn = true
        let own = ScrollSystemLog.thumbWheelMessage(for: roll)
        XCTAssertTrue(own.contains(", zoom (the app's own) x1.00, "), own)
        XCTAssertEqual(own.replacingOccurrences(of: " (the app's own)", with: ""), general)
    }
}

// MARK: - Which function a turn runs, through the scroll tap

final class ThumbWheelTurnTests: XCTestCase {

    private static let figma = "/Applications/Figma.app"
    private static let notes = "/Applications/Notes.app"

    private var rig: ThumbWheelEngineTests.Rig!
    private var savedEngine: ThumbWheelEngine!
    private var savedThumbWheel = ThumbWheelSettings.default
    private var savedSmooth = true
    private var savedAllowlist = false
    private var savedApplications: EnhanceArray<Application>!
    /// The app in front, as the engine is told it; how often it was asked.
    private var front: FrontApp?
    private var asked = 0

    override func setUp() {
        super.setUp()
        savedApplications = Options.shared.application.applications
        savedEngine = ScrollCore.shared.thumbWheelEngine
        savedThumbWheel = Options.shared.thumbWheel
        savedSmooth = Options.shared.scroll.smooth
        savedAllowlist = Options.shared.application.allowlist
        rig = ThumbWheelEngineTests.Rig()
        rig.engine.frontApplication = { [unowned self] in
            self.asked += 1
            return self.front
        }
        ScrollCore.shared.thumbWheelEngine = rig.engine
        ScrollCore.shared.handover = ScrollHandover()
        // Not smoothed: a sideways event that scrolls goes on, one that runs a function is
        // swallowed.
        Options.shared.scroll.smooth = false
        Options.shared.application.allowlist = false
        Options.shared.thumbWheel = .default
        ScrollCore.shared.toggleScroll = false
        ScrollCore.shared.blockSmooth = false
        ScrollUtils.shared.treatAsRemoteForTests(sourcePID: nil)
        let figma = Application(path: Self.figma)
        figma.setOwnThumbWheelFunction(.volume)
        Options.shared.application.applications = EnhanceArray<Application>(
            withArray: [figma, Application(path: Self.notes)], matchKey: "path"
        )
    }

    override func tearDown() {
        ScrollCore.shared.thumbWheelEngine = savedEngine
        ScrollCore.shared.handover = ScrollHandover()
        ScrollCore.shared.isActive = false
        ScrollUtils.shared.treatAsRemoteForTests(sourcePID: nil)
        Options.shared.application.applications = savedApplications
        Options.shared.thumbWheel = savedThumbWheel
        Options.shared.scroll.smooth = savedSmooth
        Options.shared.application.allowlist = savedAllowlist
        ScrollSystemLog.resetPassthroughForTests()
        super.tearDown()
    }

    /// A sideways event of a flick (twelve lines: one step of volume) that happened `time`
    /// seconds after the rig's start, through the tap's callback. Whether it went on.
    private func turn(at time: Double, lines: Int64 = -12) throws -> Bool {
        rig.advance(to: 500 + time)
        let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 0, wheel2: 0, wheel3: 0))
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: lines)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: Double(lines))
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: Double(lines * 10))
        event.setIntegerValueField(.eventSourceUnixProcessID, value: 0)
        event.setIntegerValueField(.eventTargetUnixProcessID, value: 1)
        event.timestamp = ThumbWheelEngineTests.Rig.timestamp(time)
        return ScrollCore.shared.scrollEventCallBack(CGEventTapProxy(bitPattern: 1)!, .scrollWheel, event, nil) != nil
    }

    /// Figma (its own: volume) in front: the turn turns the volume; Notes (none of its own)
    /// in front: it scrolls, as Buttons says; Scrollio's settings in front, even over
    /// Figma's path: it scrolls; no app in front: it scrolls.
    func testATurnInTheAppUsesItsFunctionElsewhereTheGeneralOne() throws {
        front = FrontApp(bundlePath: Self.figma)
        XCTAssertFalse(try turn(at: 0), "Figma's own: swallowed, it runs volume")
        front = FrontApp(bundlePath: Self.notes)
        XCTAssertTrue(try turn(at: 1), "Notes: scrolls")
        front = FrontApp(bundlePath: Self.figma, isScrollio: true)
        XCTAssertTrue(try turn(at: 2), "Scrollio in front: scrolls")
        front = nil
        XCTAssertTrue(try turn(at: 3), "no app in front: scrolls")
        rig.advance(to: 510)
        XCTAssertEqual(rig.performed.map(\.action), [.volume(.up)])
        XCTAssertEqual(asked, 4, "once per turn")
        XCTAssertEqual(rig.lines.map(\.isAppsOwn), [true, false, false, false], "the log says when it was the app's own")
        XCTAssertEqual(rig.lines.map(\.function), [.volume, .scroll, .scroll, .scroll])
    }

    /// The general function set to something else: an app without its own runs it, Figma
    /// its own.
    func testTheGeneralFunctionRunsWhereTheAppInFrontHasNone() throws {
        Options.shared.thumbWheel = ThumbWheelSettings(function: .volume, swapsDirection: true)
        Options.shared.application.applications.get(by: Self.figma)?.setOwnThumbWheelFunction(.scroll)
        front = FrontApp(bundlePath: Self.notes)
        XCTAssertFalse(try turn(at: 0), "Notes: the general volume")
        front = FrontApp(bundlePath: Self.figma)
        XCTAssertTrue(try turn(at: 1), "Figma's own \"Default\": it scrolls there")
        rig.advance(to: 510)
        XCTAssertEqual(rig.performed.map(\.action), [.volume(.down)], "swapped: the general speed and swap stay")
    }

    /// A turn keeps the function it began with until the wheel rests, whatever comes to the
    /// front meanwhile (a step of "switch desktops" brings another app forward); the first
    /// event after a rest looks again.
    func testATurnKeepsItsFunctionAcrossAnAppSwitchUntilTheWheelRests() throws {
        front = FrontApp(bundlePath: Self.figma)
        XCTAssertFalse(try turn(at: 0))
        front = FrontApp(bundlePath: Self.notes)
        XCTAssertFalse(try turn(at: 0.3), "the same turn: still Figma's volume")
        XCTAssertFalse(try turn(at: 0.8), "0.5 s apart: still the same turn")
        XCTAssertEqual(asked, 1)
        XCTAssertTrue(try turn(at: 1.5), "after a rest: Notes in front, it scrolls")
        front = FrontApp(bundlePath: Self.figma)
        XCTAssertTrue(try turn(at: 1.7), "the turn began in Notes: it scrolls on")
        XCTAssertFalse(try turn(at: 2.5), "after a rest: Figma's own again")
        XCTAssertEqual(asked, 3, "once per turn")
        rig.advance(to: 510)
        XCTAssertEqual(rig.performed.map(\.action).filter { $0 == .volume(.up) }.isEmpty, false)
    }

    /// While no app on the list has a function of its own, a turn never asks which app is in
    /// front, and the wheel does what it did before.
    func testWithoutAnAppsOwnFunctionTheAppInFrontIsNeverAsked() throws {
        Options.shared.application.applications.get(by: Self.figma)?.setOwnThumbWheelFunction(nil)
        front = FrontApp(bundlePath: Self.figma)
        XCTAssertTrue(try turn(at: 0))
        XCTAssertTrue(try turn(at: 2))
        XCTAssertEqual(asked, 0)
        XCTAssertNotNil(rig.engine.turn)
        XCTAssertNil(rig.engine.turn?.ownFunction)
    }

    /// A stop (Pause, sleep, an import) forgets the turn: the next event looks again.
    func testAStopForgetsTheTurn() throws {
        front = FrontApp(bundlePath: Self.figma)
        XCTAssertFalse(try turn(at: 0))
        rig.engine.reset()
        XCTAssertNil(rig.engine.turn)
        front = FrontApp(bundlePath: Self.notes)
        XCTAssertTrue(try turn(at: 0.1), "a new turn: Notes in front")
    }
}
