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
}
