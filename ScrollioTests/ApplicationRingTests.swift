//
//  ApplicationRingTests.swift
//  ScrollioTests
//
//  A Shortcut Ring of an app's own: how it is stored with the app's entry and what an
//  entry from before reads as, the switch "Use the general ring", and which ring opens
//  for which app in front.
//  (The app's page is in PreferencesApplicationTests, the settings file in
//  SettingsFileTests.) Nothing is shown and nothing is posted.
//

import XCTest
@testable import Scrollio_Debug

private let notesPath = "/Applications/Notes.app"
private let calculatorPath = "/System/Applications/Calculator.app"
private let calculatorProgram = "/System/Applications/Calculator.app/Contents/MacOS/Calculator"

private func list(_ applications: [Application]) -> EnhanceArray<Application> {
    return EnhanceArray<Application>(withArray: applications, matchKey: "path")
}

/// An app on the list whose own ring is the default one with `action` on top.
private func application(_ path: String, top action: SystemShortcut.Shortcut) -> Application {
    let application = Application(path: path)
    application.setUsesGeneralRing(false, general: .default)
    application.ring?[0] = ShortcutRingPlace(action)
    return application
}

// MARK: - Storage

final class ApplicationRingStorageTests: XCTestCase {

    private func storedKeys(of application: Application) throws -> Set<String> {
        let object = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(application)) as? [String: Any]
        return Set(try XCTUnwrap(object).keys)
    }

    /// An entry from before the ring could be an app's: it uses the general ring, and
    /// nothing is added to what is stored for it.
    func testAnEntryFromBeforeUsesTheGeneralRingAndIsStoredAsBefore() throws {
        let old = try JSONDecoder().decode(
            Application.self, from: Data(#"{"path":"/Applications/Notes.app","displayName":"","inherit":true}"#.utf8)
        )
        XCTAssertNil(old.ring)
        XCTAssertTrue(old.usesGeneralRing)
        XCTAssertNil(old.ownRingPlaces)
        var general = ShortcutRingSettings.default
        general[3] = .empty
        XCTAssertEqual(old.ringThatOpens(general: general), general)
        XCTAssertEqual(try storedKeys(of: old), ["path", "displayName", "inherit", "scroll"])
        XCTAssertEqual(try storedKeys(of: Application(path: notesPath)), ["path", "displayName", "inherit", "scroll"])
    }

    /// The app's own ring is stored with its entry, eight places and the switch and
    /// nothing else, and comes back as it was stored.
    func testAnAppsOwnRingIsStoredWithItsEntryAndComesBack() throws {
        var general = ShortcutRingSettings.default
        general.freezePointer = true
        let notes = Application(path: notesPath)
        notes.setUsesGeneralRing(false, general: general)
        let script = OpenTargetPayload(path: "/Users/someone/bin/sync.sh", bundleID: nil, arguments: "--all", kind: .script)
        notes.ring?[1] = ShortcutRingPlace(openTarget: script)
        notes.ring?[2] = ShortcutRingPlace(action: "custom::40:1179648")
        notes.ring?[6] = .empty

        let data = try XCTUnwrap(list([notes, Application(path: calculatorPath)]).json())
        let stored = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let ring = try XCTUnwrap(stored[0]["ring"] as? [String: Any])
        XCTAssertEqual(Set(ring.keys), ["inherit", "places"], "the freeze switch is the general ring's")
        XCTAssertEqual(ring["inherit"] as? Bool, false)
        XCTAssertEqual((ring["places"] as? [Any])?.count, 8)
        XCTAssertNil(stored[1]["ring"], "an app without a ring of its own stores none")

        let loaded = try EnhanceArray<Application>(withData: data, matchKey: "path")
        let back = try XCTUnwrap(loaded.get(by: notesPath))
        XCTAssertEqual(back.ring, notes.ring)
        XCTAssertFalse(back.usesGeneralRing)
        XCTAssertEqual(back.ownRingPlaces?[1].openTarget, script)
        XCTAssertEqual(back.ownRingPlaces?[0], general[0], "it started as a copy of the general ring")
        // What opens: the app's places, the general ring's freeze switch.
        XCTAssertEqual(back.ringThatOpens(general: general).places, notes.ring?.places)
        XCTAssertTrue(back.ringThatOpens(general: general).freezePointer)
        XCTAssertFalse(back.ringThatOpens(general: .default).freezePointer)
        XCTAssertTrue(try XCTUnwrap(loaded.get(by: calculatorPath)).usesGeneralRing)
    }

    /// Off: a copy of the general ring as it is at that moment, for an app that never had
    /// a ring. On: the app's ring is kept and not used. Off again: it comes back as it
    /// was left, as an app's own scroll settings do.
    func testTheSwitchStartsFromTheGeneralRingAndKeepsTheAppsOwnForLater() {
        var general = ShortcutRingSettings.default
        general[1] = ShortcutRingPlace(SystemShortcut.undo)
        let notes = Application(path: notesPath)
        notes.setUsesGeneralRing(true, general: general)
        XCTAssertNil(notes.ring, "already on: nothing is stored")

        notes.setUsesGeneralRing(false, general: general)
        XCTAssertEqual(notes.ownRingPlaces, general.places)
        notes.ring?[0] = ShortcutRingPlace(SystemShortcut.paste)
        // The general ring changes afterwards: the app's own does not follow.
        general[1] = ShortcutRingPlace(SystemShortcut.copy)
        XCTAssertEqual(notes.ownRingPlaces?[1].action, "undo")
        XCTAssertEqual(notes.ringThatOpens(general: general)[0].action, "paste")

        notes.setUsesGeneralRing(true, general: general)
        XCTAssertTrue(notes.usesGeneralRing)
        XCTAssertNil(notes.ownRingPlaces)
        XCTAssertEqual(notes.ringThatOpens(general: general), general)
        XCTAssertEqual(notes.ring?[0].action, "paste", "kept in storage")

        notes.setUsesGeneralRing(false, general: general)
        XCTAssertEqual(notes.ownRingPlaces?[0].action, "paste", "its own ring as it was left")
        XCTAssertEqual(notes.ownRingPlaces?[1].action, "undo", "not a new copy of the general ring")
    }

    /// A stored ring is read place by place, as the general ring is; what is no ring does
    /// not take the app's entry with it: the app then uses the general ring.
    func testAStoredRingIsReadPlaceByPlaceAndWhatIsNoRingLeavesTheAppItsEntry() throws {
        func entry(_ ring: String) throws -> Application {
            let json = #"{"path":"/Applications/Notes.app","inherit":false,"ring":"# + ring + "}"
            return try JSONDecoder().decode(Application.self, from: Data(json.utf8))
        }
        // A place that cannot be read is empty, a short list is filled up.
        let patchy = try entry(#"{"inherit":false,"places":[{"action":"copy"},7,{"action":"paste"}]}"#)
        XCTAssertEqual(patchy.ownRingPlaces?.map { $0.action }, ["copy", "", "paste", "", "", "", "", ""])
        // A long list is cut to the eight places.
        let nine = Array(repeating: #"{"action":"copy"}"#, count: 9).joined(separator: ",")
        XCTAssertEqual(try entry(#"{"inherit":false,"places":["# + nine + "]}").ownRingPlaces?.count, 8)
        // Without the switch the ring is kept and not used.
        let unsaid = try entry(#"{"places":[{"action":"copy"}]}"#)
        XCTAssertTrue(unsaid.usesGeneralRing)
        XCTAssertEqual(unsaid.ring?[0].action, "copy")
        XCTAssertTrue(try entry(#"{"inherit":"no","places":[]}"#).usesGeneralRing)
        // No list of places, or no object at all: no ring, and the entry is read.
        for broken in [#"{"inherit":false}"#, #"{"inherit":false,"places":"copy"}"#, #""copy""#, "[1,2]", "null"] {
            let application = try entry(broken)
            XCTAssertNil(application.ring, broken)
            XCTAssertTrue(application.usesGeneralRing, broken)
            XCTAssertEqual(application.path, notesPath)
            XCTAssertFalse(application.inherit, "the rest of the entry is as stored")
        }
    }
}

// MARK: - Which ring opens

final class ShortcutRingChoiceTests: XCTestCase {

    private typealias FrontApp = ShortcutRingChoice.FrontApp

    private var general = ShortcutRingSettings.default
    private var applications = list([])

    override func setUp() {
        super.setUp()
        general = .default
        general[7] = ShortcutRingPlace(SystemShortcut.undo)
        general.freezePointer = true
        let usesGeneral = Application(path: "/Applications/Safari.app")
        // A ring of its own that is switched off again.
        let keptForLater = application("/Applications/Mail.app", top: SystemShortcut.paste)
        keptForLater.setUsesGeneralRing(true, general: general)
        applications = list([
            application(notesPath, top: SystemShortcut.copy),
            application(calculatorProgram, top: SystemShortcut.paste),
            usesGeneral, keptForLater,
        ])
    }

    private func choice(_ front: FrontApp?) -> ShortcutRingChoice {
        return ShortcutRingChoice.make(front: front, applications: applications, general: general)
    }

    /// The app in front has a ring of its own: its places open, with the general ring's
    /// freeze switch. The entry is found by the bundle's path, then by the program's, as
    /// the scroll engine finds it.
    func testAnAppWithARingOfItsOwnGetsIt() {
        let notes = choice(FrontApp(bundlePath: notesPath, executablePath: notesPath + "/Contents/MacOS/Notes"))
        XCTAssertTrue(notes.isAppsOwn)
        XCTAssertEqual(notes.ring[0].action, "copy")
        XCTAssertEqual(notes.ring[7], ShortcutRingSettings.default[7], "the app's own place, not the general ring's")
        XCTAssertTrue(notes.ring.freezePointer, "the freeze switch is the general ring's")

        let calculator = choice(FrontApp(bundlePath: calculatorPath, executablePath: calculatorProgram))
        XCTAssertTrue(calculator.isAppsOwn, "stored by its program, as a running app is added")
        XCTAssertEqual(calculator.ring[0].action, "paste")
    }

    func testEveryOtherAppGetsTheGeneralRing() {
        let cases: [(String, FrontApp?)] = [
            ("uses the general ring", FrontApp(bundlePath: "/Applications/Safari.app", executablePath: nil)),
            ("its own ring is switched off", FrontApp(bundlePath: "/Applications/Mail.app", executablePath: nil)),
            ("not on the list", FrontApp(bundlePath: "/Applications/Preview.app", executablePath: "/Applications/Preview.app/Contents/MacOS/Preview")),
            ("no paths", FrontApp(bundlePath: nil, executablePath: nil)),
            ("no app in front", nil),
        ]
        for (name, front) in cases {
            XCTAssertEqual(choice(front), ShortcutRingChoice(ring: general, isAppsOwn: false), name)
        }
    }

    /// With Scrollio itself in front (its Settings) the general ring opens, even when
    /// Scrollio stands on the list with a ring of its own.
    func testScrollioItselfGetsTheGeneralRing() throws {
        let own = try XCTUnwrap(FrontApp.current(NSRunningApplication.current))
        XCTAssertTrue(own.isScrollio)
        let bundle = try XCTUnwrap(own.bundlePath)
        applications = list([application(bundle, top: SystemShortcut.copy)])
        XCTAssertEqual(choice(own), .general(general))
        // The same paths as another process would get the app's ring: it is the process that counts.
        XCTAssertTrue(choice(FrontApp(bundlePath: bundle, executablePath: own.executablePath)).isAppsOwn)
        XCTAssertNil(FrontApp.current(nil))
    }

}
