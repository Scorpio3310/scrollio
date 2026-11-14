//
//  ApplicationRingTests.swift
//  ScrollioTests
//
//  A Shortcut Ring of an app's own: how it is stored with the app's entry and what an
//  entry from before reads as, the switch "Use the general ring", which ring opens for
//  which app in front, and that the ring that opened stays the ring until it closes.
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

    /// The faces made at launch: the general ring's and each app's own, of those whose
    /// places open an app or a file; none while no button or key opens the ring.
    func testTheFacesMadeAtLaunchAreThoseOfTheRingsThatOpenSomething() {
        let options = Options()
        options.defaults = TestDefaults.make(for: self)
        let textEdit = OpenTargetPayload(path: "/System/Applications/TextEdit.app", bundleID: "com.apple.TextEdit", arguments: "", kind: .application)
        let opens = application(notesPath, top: SystemShortcut.copy)
        opens.ring?[2] = ShortcutRingPlace(openTarget: textEdit)
        let keptForLater = application("/Applications/Mail.app", top: SystemShortcut.copy)
        keptForLater.ring?[2] = ShortcutRingPlace(openTarget: textEdit)
        keptForLater.setUsesGeneralRing(true, general: .default)
        options.application.applications = list([opens, application(calculatorPath, top: SystemShortcut.paste), keptForLater])
        XCTAssertEqual(ShortcutRingController.ringsToPrepareAtLaunch(options: options), [], "nothing opens the ring")

        let trigger = RecordedEvent(type: .mouse, code: 4, modifiers: 0, deviceFilter: nil)
        options.buttons.binding = [
            ButtonBinding(triggerEvent: trigger, systemShortcutName: SystemShortcut.shortcutRing.identifier, isEnabled: true),
        ]
        XCTAssertEqual(ShortcutRingController.ringsToPrepareAtLaunch(options: options), [opens.ringThatOpens(general: .default)])
        var general = ShortcutRingSettings.default
        general[5] = ShortcutRingPlace(openTarget: textEdit)
        options.ring = general
        XCTAssertEqual(
            ShortcutRingController.ringsToPrepareAtLaunch(options: options),
            [general, opens.ringThatOpens(general: general)]
        )

        // An app's own ring starts as a copy of the general one: the same places are one
        // face, made once, and copies never push a ring of other places off the list.
        let copies = (0..<ShortcutRingController.preparedFaceLimit).map { index -> Application in
            let copy = Application(path: "/Applications/Copy \(index).app")
            copy.setUsesGeneralRing(false, general: general)
            return copy
        }
        let last = application("/Applications/Last.app", top: SystemShortcut.paste)
        last.ring?[2] = ShortcutRingPlace(openTarget: textEdit)
        options.application.applications = list([opens] + copies + [last, keptForLater])
        XCTAssertEqual(
            ShortcutRingController.ringsToPrepareAtLaunch(options: options),
            [general, opens.ringThatOpens(general: general), last.ringThatOpens(general: general)]
        )
    }
}

// MARK: - The controller

final class ShortcutRingPerAppControllerTests: XCTestCase {

    private typealias FrontApp = ShortcutRingChoice.FrontApp

    private var harness: RingHarness!
    private var controller: ShortcutRingController { return harness.controller }
    private var front: FrontApp?
    private var applications = list([])

    override func setUp() {
        super.setUp()
        ShortcutRingController.forgetPreparedFaces()
        harness = RingHarness()
        front = nil
        applications = list([
            application(notesPath, top: SystemShortcut.copy),
            application(calculatorPath, top: SystemShortcut.paste),
        ])
        controller.environment.choice = { [unowned self] general in
            ShortcutRingChoice.make(front: self.front, applications: self.applications, general: general)
        }
    }

    override func tearDown() {
        harness = nil
        ShortcutRingController.forgetPreparedFaces()
        super.tearDown()
    }

    private func topTitle() -> String? {
        return harness.presenter.shown.last?.face.places[0].title
    }

    /// The app in front when the trigger goes down decides, and that ring stays until it
    /// closes: another app that comes to the front while the ring is held changes neither
    /// what is shown nor what the chosen place runs. The next ring is the other app's.
    func testTheRingThatOpenedStaysWhenAnotherAppComesToTheFront() {
        front = FrontApp(bundlePath: notesPath, executablePath: nil)
        controller.triggerPressed(by: RingHarness.button(.down))
        harness.runScheduled()
        XCTAssertEqual(topTitle(), SystemShortcut.copy.localizedName)

        front = FrontApp(bundlePath: calculatorPath, executablePath: nil)
        harness.moveHand(by: CGPoint(x: 0, y: -70))
        XCTAssertEqual(harness.presenter.lit.last, 0)
        harness.clearLog()
        controller.triggerReleased(isMadeUp: false)
        harness.runScheduled()
        XCTAssertEqual(harness.log, ["hide", "run copy"], "the place of the ring that opened")
        XCTAssertEqual(harness.presenter.shown.count, 1, "nothing was shown again")

        controller.triggerPressed(by: RingHarness.button(.down))
        harness.runScheduled()
        XCTAssertEqual(topTitle(), SystemShortcut.paste.localizedName, "the app in front now")
        controller.cancel()

        // A ring that stands open stays its app's too, through a second press.
        front = FrontApp(bundlePath: notesPath, executablePath: nil)
        harness.tap()
        front = nil
        harness.pointer = harness.place(0)
        harness.now += 0.5
        controller.tick()
        harness.clearLog()
        harness.presenter.onButton?(0, true, harness.place(0))
        harness.presenter.onButton?(0, false, harness.place(0))
        harness.runScheduled()
        XCTAssertEqual(harness.log, ["hide", "run copy"])
    }

    /// A place moved to the next Space and the trigger was pressed again before the app
    /// there came forward: the ring that opened is still the last app's. When the new app
    /// comes forward inside the quiet moment after the run, that ring closes (its places
    /// are not for this app); a ring that is the new app's too stays, as an echo of the run.
    func testARingPressedBeforeTheNextAppCameForwardClosesWhenItIsNotThatAppsRing() {
        let workspace = NSWorkspace.shared.notificationCenter
        func runRightAndPressAgain() {
            controller.triggerPressed(by: RingHarness.button(.down))
            harness.runScheduled()
            harness.moveHand(by: CGPoint(x: 60, y: 0))
            controller.triggerReleased(isMadeUp: false)
            harness.runScheduled()
            XCTAssertEqual(harness.log.last, "run moveSpaceRight")
            harness.now += 0.3
            harness.pointer = CGPoint(x: 700, y: 500)
            controller.triggerPressed(by: RingHarness.button(.down))
            harness.runScheduled()
        }

        front = FrontApp(bundlePath: notesPath, executablePath: nil)
        runRightAndPressAgain()
        XCTAssertEqual(topTitle(), SystemShortcut.copy.localizedName, "Notes' ring, Notes still in front")
        front = FrontApp(bundlePath: calculatorPath, executablePath: nil)
        workspace.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        XCTAssertFalse(controller.isOpen, "Calculator came forward: Notes' ring closed")

        // Within an app: the echo of the run keeps the ring.
        harness.now += 2
        front = FrontApp(bundlePath: notesPath, executablePath: nil)
        runRightAndPressAgain()
        workspace.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        workspace.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        XCTAssertTrue(controller.isHeld, "the app in front still has this ring")
        controller.cancel()

        // An app without a ring of its own after an app without one: the general ring
        // both times, kept.
        harness.now += 2
        front = FrontApp(bundlePath: "/Applications/Preview.app", executablePath: nil)
        runRightAndPressAgain()
        front = FrontApp(bundlePath: "/Applications/Safari.app", executablePath: nil)
        workspace.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        XCTAssertTrue(controller.isHeld)
        controller.cancel()
    }

    /// The general ring for an app without a ring of its own, and for no app; the log says
    /// when an app's own ring opened, and never which app.
    func testTheLogSaysWhenAnAppsOwnRingOpenedAndNeverNamesTheApp() {
        harness.tap()
        XCTAssertEqual(topTitle(), SystemShortcut.missionControl.localizedName)
        XCTAssertEqual(harness.logLines.first, "Shortcut Ring: opened by a mouse button")
        controller.cancel()

        front = FrontApp(bundlePath: notesPath, executablePath: nil)
        harness.ring.freezePointer = true
        harness.tap()
        XCTAssertEqual(topTitle(), SystemShortcut.copy.localizedName)
        XCTAssertTrue(harness.logLines.contains(
            "Shortcut Ring: opened by a mouse button, the own ring of the app in front, the pointer is kept still while it is held"
        ), "\(harness.logLines)")
        XCTAssertEqual(harness.pointerLocks.first, "lock", "the freeze switch is the general ring's, for an app's ring too")
        controller.cancel()
        XCTAssertFalse(harness.logLines.contains { $0.contains("Notes") || $0.contains(notesPath) })

        front = FrontApp(bundlePath: "/Applications/Preview.app", executablePath: nil)
        harness.ring.freezePointer = false
        harness.tap()
        XCTAssertEqual(topTitle(), SystemShortcut.missionControl.localizedName)
        XCTAssertEqual(harness.logLines.suffix(2).first, "Shortcut Ring: opened by a mouse button")
    }

    /// A face belongs to the places it was made for: the ring of one app is never shown
    /// with another's, and each ring keeps its own face (an app's icon in a place) while
    /// other rings were shown in between.
    func testAFaceIsNeverShownForAnotherAppsRing() throws {
        let textEdit = OpenTargetPayload(path: "/System/Applications/TextEdit.app", bundleID: "com.apple.TextEdit", arguments: "", kind: .application)
        let notes = try XCTUnwrap(applications.get(by: notesPath))
        notes.ring?[2] = ShortcutRingPlace(openTarget: textEdit)
        let calculator = try XCTUnwrap(applications.get(by: calculatorPath))
        calculator.ring?[2] = ShortcutRingPlace(openTarget: OpenTargetPayload(
            path: calculatorPath, bundleID: "com.apple.calculator", arguments: "", kind: .application
        ))
        // The app's page made the face of the first app's ring; nobody made the second's.
        let notesRing = notes.ringThatOpens(general: harness.ring)
        ShortcutRingController.prepare(ShortcutRingFace(notesRing), for: notesRing)

        func open(_ path: String?) -> ShortcutRingFace.Place? {
            front = path.map { FrontApp(bundlePath: $0, executablePath: nil) }
            controller.triggerPressed(by: RingHarness.button(.down))
            harness.runScheduled()
            let place = harness.presenter.shown.last?.face.places[2]
            controller.cancel()
            harness.runScheduled()
            return place
        }
        XCTAssertNotNil(open(notesPath)?.image, "made at a quiet moment")
        XCTAssertEqual(harness.wholeFacesMade, 0)

        let second = open(calculatorPath)
        XCTAssertEqual(second?.title, "Calculator")
        XCTAssertNil(second?.image, "its own face is not there yet; the other app's is not taken for it")
        XCTAssertEqual(harness.wholeFacesMade, 1, "made after that ring closed")

        XCTAssertEqual(open(nil)?.title, SystemShortcut.moveSpaceRight.localizedName, "the general ring")
        XCTAssertNotNil(open(notesPath)?.image, "the first app's face was kept")
        XCTAssertNotNil(open(calculatorPath)?.image, "and the second app's is there now")
        XCTAssertEqual(harness.wholeFacesMade, 1)
        // The general ring's freeze switch changes no face.
        harness.ring.freezePointer = true
        XCTAssertNotNil(open(notesPath)?.image)
        XCTAssertEqual(harness.wholeFacesMade, 1)
        // Only a few faces are kept, the newest ones.
        for index in 0..<(ShortcutRingController.preparedFaceLimit + 3) {
            var ring = ShortcutRingSettings.default
            ring[0] = ShortcutRingPlace(action: "custom::\(index):0")
            ShortcutRingController.prepare(ShortcutRingFace(ring, looksOnDisk: false), for: ring)
        }
        XCTAssertEqual(ShortcutRingController.preparedFaces.count, ShortcutRingController.preparedFaceLimit)
        XCTAssertNil(ShortcutRingController.preparedFace(for: notesRing))
    }

    /// At launch the faces are made one ring per turn of the main queue (the event taps
    /// wait on it too), the general ring last, so that it is the newest; and never while
    /// a ring is open: a turn that finds one open tries again a little later.
    func testTheFacesAtLaunchAreMadeOneRingPerTurnAndNeverWhileARingIsOpen() throws {
        let options = Options()
        options.defaults = TestDefaults.make(for: self)
        let textEdit = OpenTargetPayload(path: "/System/Applications/TextEdit.app", bundleID: "com.apple.TextEdit", arguments: "", kind: .application)
        var general = ShortcutRingSettings.default
        general[5] = ShortcutRingPlace(openTarget: textEdit)
        options.ring = general
        let notes = application(notesPath, top: SystemShortcut.copy)
        notes.ring?[2] = ShortcutRingPlace(openTarget: textEdit)
        options.application.applications = list([notes])
        options.buttons.binding = [ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 4, modifiers: 0, deviceFilter: nil),
            systemShortcutName: SystemShortcut.shortcutRing.identifier, isEnabled: true
        )]
        let notesRing = notes.ringThatOpens(general: general)

        var turns: [(delay: TimeInterval, block: () -> Void)] = []
        func nextTurn() {
            guard !turns.isEmpty else { return XCTFail("no turn is due") }
            turns.removeFirst().block()
        }
        ShortcutRingController.prepareFaceAtLaunch(options: options, after: { turns.append(($0, $1)) })
        XCTAssertEqual(turns.map(\.delay), [0], "nothing in the launch's own turn")
        XCTAssertTrue(ShortcutRingController.preparedFaces.isEmpty)

        ShortcutRingController.setTestingController(controller)
        defer { ShortcutRingController.setTestingController(nil) }
        controller.triggerPressed(by: RingHarness.button(.down))
        XCTAssertTrue(controller.isOpen)
        nextTurn()
        XCTAssertTrue(ShortcutRingController.preparedFaces.isEmpty, "not while a ring is held")
        XCTAssertEqual(turns.map(\.delay), [ShortcutRingController.launchFaceWait])
        controller.cancel()
        XCTAssertFalse(controller.isOpen)
        nextTurn()

        XCTAssertEqual(turns.map(\.delay), [0])
        nextTurn()
        XCTAssertEqual(ShortcutRingController.preparedFaces.map(\.ring), [notesRing], "one ring in a turn")
        XCTAssertNotNil(ShortcutRingController.preparedFace(for: notesRing)?.places[2].image)
        XCTAssertEqual(turns.map(\.delay), [0])
        nextTurn()
        XCTAssertEqual(ShortcutRingController.preparedFaces.map(\.ring), [general, notesRing], "the general ring is the newest")
        XCTAssertTrue(turns.isEmpty)
    }
}
