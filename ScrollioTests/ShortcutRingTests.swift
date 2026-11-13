//
//  ShortcutRingTests.swift
//  ScrollioTests
//
//  The Shortcut Ring's pure parts: what it stores, its geometry and its rules.
//

import XCTest
@testable import Scrollio_Debug

// MARK: - What the ring stores

final class ShortcutRingSettingsTests: XCTestCase {

    private func decoded(_ json: String) throws -> ShortcutRingSettings {
        return try JSONDecoder().decode(ShortcutRingSettings.self, from: Data(json.utf8))
    }

    /// The stored names are persisted identifiers: the key and the action's name.
    func testTheStoredNamesStay() {
        XCTAssertEqual(OptionItem.Ring.Settings, "shortcutRingSettings")
        XCTAssertEqual(SystemShortcut.shortcutRing.identifier, "shortcutRing")
        XCTAssertNotNil(SystemShortcut.getShortcut(named: "shortcutRing"))
    }

    /// The ring's action is no key: it is told from Gesture Navigation, never sent as a
    /// shortcut, known to an import, and in no category (the Gestures menus list those).
    func testTheRingsActionIsNoKeyAndIsKnown() {
        XCTAssertNotEqual(SystemShortcut.shortcutRing, SystemShortcut.mouseGestureNavigation)
        XCTAssertNil(ShortcutExecutor.shared.resolveAction(named: "shortcutRing"))
        let trigger = RecordedEvent(type: .mouse, code: 4, modifiers: 0, deviceFilter: nil)
        XCTAssertTrue(StoredAction.isKnown(ButtonBinding(triggerEvent: trigger, systemShortcutName: "shortcutRing")))
        XCTAssertFalse(StoredAction.isKnown(gestureAction: "shortcutRing"), "a gesture direction cannot open the ring")
        for category in SystemShortcut.shortcutsByCategory {
            XCTAssertFalse(category.shortcuts.contains { $0.identifier == "shortcutRing" }, category.category)
        }
        XCTAssertNil(SystemShortcut.displayShortcut(matchingBindingName: "custom::65531:1"), "no recorded key is shown as the ring")
    }

    func testANewRingHasEightPlacesOfActionsThatRun() {
        let ring = ShortcutRingSettings.default
        XCTAssertEqual(ring.places.count, 8)
        XCTAssertEqual(ring.places.map { $0.action }, [
            "missionControl", "screenshotSelection", "moveSpaceRight", "paste",
            "appExpose", "copy", "moveSpaceLeft", "showDesktop",
        ])
        XCTAssertEqual(ring.filled, Array(repeating: true, count: 8))
    }

    /// At a glance two neighbours of a new ring are never the same kind of picture: the
    /// two grids (Mission Control, Apps) are not side by side, nor are two of the sheets
    /// (Copy, Paste, Show Desktop), and no symbol is there twice.
    func testNoTwoNeighboursOfANewRingLookAlike() {
        let lookAlike: [Set<String>] = [
            ["square.grid.3x2", "square.grid.3x3"],
            ["doc.on.doc", "doc.on.clipboard", "rectangle.on.rectangle"],
            ["arrow.left.to.line", "arrow.right.to.line"],
        ]
        let symbols = ShortcutRingSettings.default.places.map { $0.shortcut?.symbolName ?? "" }
        XCTAssertEqual(Set(symbols).count, 8)
        for place in 0..<8 {
            let neighbour = (place + 1) % 8
            for group in lookAlike {
                XCTAssertFalse(
                    group.contains(symbols[place]) && group.contains(symbols[neighbour]),
                    "\(symbols[place]) next to \(symbols[neighbour])"
                )
            }
        }
        XCTAssertEqual(ShortcutRingSettings.default[0].action, "missionControl", "Mission Control stays on top")
        XCTAssertEqual(ShortcutRingSettings.default[2].action, "moveSpaceRight")
        XCTAssertEqual(ShortcutRingSettings.default[6].action, "moveSpaceLeft")
    }

    private static let keyCombination = ButtonBinding.normalizedCustomBindingName(
        code: 40, modifiers: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue
    )
    private static let notes = OpenTargetPayload(
        path: "/Applications/Notes.app", bundleID: "com.apple.Notes", arguments: "", kind: .application
    )

    func testTheRingSurvivesBeingStored() throws {
        var ring = ShortcutRingSettings.default
        ring[1] = .empty
        ring[2] = ShortcutRingPlace(SystemShortcut.undo)
        ring[3] = ShortcutRingPlace(action: Self.keyCombination)
        ring[5] = ShortcutRingPlace(openTarget: Self.notes)
        let data = try JSONEncoder().encode(ring)
        XCTAssertEqual(try JSONDecoder().decode(ShortcutRingSettings.self, from: data), ring)

        // The format: one object with "places", each place an object with its action's
        // name as a button stores it, and what to open only where something is opened.
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Array(object.keys), ["places"])
        let places = try XCTUnwrap(object["places"] as? [[String: Any]])
        XCTAssertEqual(places.count, 8)
        XCTAssertEqual(places.map { $0["action"] as? String }, [
            "missionControl", "", "undo", Self.keyCombination, "appExpose", "openTarget", "moveSpaceLeft", "showDesktop",
        ])
        XCTAssertEqual(Self.keyCombination, "custom::40:1179648")
        for (index, place) in places.enumerated() where index != 5 {
            XCTAssertEqual(place.count, 1, "place \(index) has only its action")
        }
        let target = try XCTUnwrap(places[5]["openTarget"] as? [String: Any])
        XCTAssertEqual(target["path"] as? String, "/Applications/Notes.app")
        XCTAssertEqual(target["kind"] as? String, "application")
    }

    func testMissingOrUnreadableDataGivesTheDefaultRing() throws {
        XCTAssertEqual(Options.decodeShortcutRingSettings(nil), .default)
        XCTAssertEqual(Options.decodeShortcutRingSettings(Data("not json".utf8)), .default)
        XCTAssertEqual(Options.decodeShortcutRingSettings(Data("[1, 2]".utf8)), .default)
        XCTAssertEqual(try decoded("{}"), .default)
        XCTAssertEqual(try decoded(#"{"places": "none"}"#), .default)
    }

    /// One place that cannot be read does not take the others with it, and the ring always
    /// has eight places.
    func testABadPlaceIsEmptyAndTheListIsCutOrFilledUp() throws {
        let short = try decoded(#"{"places": [{"action": "copy"}, 7, {"action": 3}, {"other": true}]}"#)
        XCTAssertEqual(short.places.count, 8)
        XCTAssertEqual(short[0].action, "copy")
        XCTAssertTrue(short.places.dropFirst().allSatisfy { $0.isEmpty })

        let places = Array(repeating: #"{"action": "paste"}"#, count: 12).joined(separator: ",")
        let long = try decoded(#"{"places": ["# + places + "]}")
        XCTAssertEqual(long.places.count, 8)
        XCTAssertTrue(long.places.allSatisfy { $0.action == "paste" })
        XCTAssertEqual(long[40], .empty, "a place that is not there is empty")
    }

    /// What a place can hold: a listed keyboard shortcut, the Back or Forward click, a
    /// recorded key combination, an app, a file or a script. Not: the ring itself, what is
    /// only held, the left, right and middle click, a Logitech action, a recorded mouse
    /// button, a retired or unknown action.
    func testWhatAPlaceRunsAndWhatItDoesNot() {
        for name in ["copy", "missionControl", "screenshot", "navigateBack", "escapeKey", "spotlightSys", "mouseBackClick", "mouseForwardClick"] {
            XCTAssertTrue(ShortcutRingPlace(action: name).runs, name)
            XCTAssertEqual(ShortcutRingPlace(action: name).shortcut?.identifier, name)
        }
        let combination = ShortcutRingPlace(action: Self.keyCombination)
        XCTAssertEqual(combination.content, .keyCombination(code: 40, modifiers: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue))
        XCTAssertNil(combination.shortcut)
        XCTAssertEqual(ShortcutRingPlace(action: "custom::49:0").content, .keyCombination(code: 49, modifiers: 0), "a key without modifiers")
        XCTAssertEqual(ShortcutRingPlace(openTarget: Self.notes).content, .open(Self.notes))

        let others = [
            "", "shortcutRing", "mouseGestureNavigation", "modifierShift", "scrollDash", "scrollSlow",
            "mouseLeftClick", "mouseRightClick", "mouseMiddleClick", "logiSmartShiftToggle", "logiHost2",
            "shutdownDialog", "somethingNewer",
            "custom::mouse:3:0",     // a recorded mouse button: a click
            "custom::56:0",          // Shift by itself: only means something while held
            "custom::55:131072",     // ⇧ with ⌘ as the key: modifiers only
        ]
        for name in others {
            XCTAssertFalse(ShortcutRingPlace(action: name).runs, name)
            XCTAssertEqual(ShortcutRingPlace(action: name).content, .nothing, name)
            XCTAssertNil(ShortcutRingPlace(action: name).resolvedAction, name)
        }
    }

    /// A name with a target, or the "open" name without one, could show one thing and run
    /// another: such a place holds nothing, as such a binding is not read.
    func testAPlaceWhoseFieldsContradictEachOtherHoldsNothing() throws {
        let target = #"{"path": "/bin/sh", "arguments": "-c true", "kind": "script"}"#
        let ring = try decoded(#"{"places": [{"action": "copy", "openTarget": "# + target + #"}, {"action": "openTarget"}, "#
            + #"{"action": "openTarget", "openTarget": "# + target + #"}, {"action": "openTarget", "openTarget": {"path": 7}}]}"#)
        XCTAssertTrue(ring[0].isEmpty)
        XCTAssertNil(ring[0].openTarget)
        XCTAssertTrue(ring[1].isEmpty)
        XCTAssertEqual(ring[2].openTarget?.path, "/bin/sh")
        XCTAssertEqual(ring[2].openTarget?.kind, .script)
        XCTAssertTrue(ring[3].isEmpty, "a target that cannot be read")
        XCTAssertEqual(ring.filled, [false, false, true, false, false, false, false, false])
    }

    /// A place runs through a binding built from it, as a button's action is resolved: a
    /// recorded key combination and what to open are in the binding, not in the name.
    func testAPlaceResolvesToWhatAButtonWouldRun() {
        guard case .systemShortcut(let identifier)? = ShortcutRingPlace(SystemShortcut.copy).resolvedAction else {
            return XCTFail("Copy is a system shortcut")
        }
        XCTAssertEqual(identifier, "copy")

        guard case .customKey(let code, let modifiers)? = ShortcutRingPlace(action: Self.keyCombination).resolvedAction else {
            return XCTFail("a recorded key combination is a key")
        }
        XCTAssertEqual(code, 40)
        XCTAssertEqual(modifiers, CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue)

        guard case .openTarget(let opened)? = ShortcutRingPlace(openTarget: Self.notes).resolvedAction else {
            return XCTFail("an app to open is an open target")
        }
        XCTAssertEqual(opened, Self.notes)

        guard case .mouseButton(let kind)? = ShortcutRingPlace(SystemShortcut.mouseBackClick).resolvedAction else {
            return XCTFail("the Back click is a mouse button")
        }
        XCTAssertEqual(kind, .back)

        // The stand-in binding: the place's action, a trigger that is never matched.
        let binding = ShortcutRingPlace(action: Self.keyCombination).asBinding()
        XCTAssertEqual(binding.systemShortcutName, Self.keyCombination)
        XCTAssertEqual(binding.cachedCustomCode, 40)
        XCTAssertFalse(ButtonUtils.isRunnable(binding.triggerEvent), "the stand-in trigger can never fire")
        XCTAssertEqual(ShortcutRingPlace(actionOf: binding), ShortcutRingPlace(action: Self.keyCombination))
        XCTAssertEqual(ShortcutRingPlace(action: "mouseLeftClick").asBinding().systemShortcutName, "", "what does not run shows as no action")
    }

    /// The menu of a place offers what a place runs and nothing else.
    func testThePlacesMenuOffersWhatRuns() {
        let menu = NSMenu()
        let target = NSObject()
        ShortcutManager.buildShortcutMenu(
            into: menu, target: target, action: NSSelectorFromString("noop:"), showLogiActions: true,
            showsGestureSettings: true, forRingPlace: true
        )
        var offered: [SystemShortcut.Shortcut] = []
        func collect(_ menu: NSMenu) {
            for item in menu.items {
                if let shortcut = item.representedObject as? SystemShortcut.Shortcut { offered.append(shortcut) }
                if let submenu = item.submenu { collect(submenu) }
            }
        }
        collect(menu)
        XCTAssertGreaterThan(offered.count, 40)
        for shortcut in offered {
            XCTAssertTrue(ShortcutRingPlace(shortcut).runs, shortcut.identifier)
        }
        let names = Set(offered.map { $0.identifier })
        XCTAssertTrue(names.isSuperset(of: ["copy", "missionControl", "mouseBackClick", "mouseForwardClick"]))
        for place in ShortcutRingSettings.default.places {
            XCTAssertTrue(names.contains(place.action), place.action)
        }
        let titles = menu.items.map { $0.title }
        for absent in ["Modifier Keys", "Scrolling", "Logitech Mouse", "Gesture Navigation", "Show Gesture Settings", "Shortcut Ring"] {
            XCTAssertFalse(titles.contains(absent), absent)
        }
        XCTAssertEqual(Array(titles.suffix(2)), ["Open App or File…", "Keyboard Shortcut…"])
    }

    /// A name of a newer version stays stored at launch and runs nothing; a settings file
    /// brings none in.
    func testAnUnknownActionIsKeptAsStoredAndEmptiedForAFile() throws {
        let ring = try decoded(#"{"places": [{"action": "somethingNewer"}, {"action": "copy"}, {"action": "mouseLeftClick"}]}"#)
        XCTAssertEqual(ring[0].action, "somethingNewer")
        XCTAssertEqual(ring.filled, [false, true, false, false, false, false, false, false])
        let kept = ring.keepingOnlyWhatRuns()
        XCTAssertEqual(kept.emptied, 2)
        var mine = ShortcutRingSettings.default
        mine[1] = ShortcutRingPlace(action: Self.keyCombination)
        mine[2] = ShortcutRingPlace(openTarget: Self.notes)
        XCTAssertEqual(mine.keepingOnlyWhatRuns().emptied, 0, "a key combination and an app run")
        XCTAssertEqual(mine.keepingOnlyWhatRuns().ring, mine)
        XCTAssertEqual(kept.ring.places.map { $0.action }, ["", "copy", "", "", "", "", "", ""])
        XCTAssertEqual(ShortcutRingSettings.default.keepingOnlyWhatRuns().emptied, 0)
    }

    func testOptionsStoreAndReadTheRing() {
        let options = Options()
        options.defaults = TestDefaults.make(for: self)
        options.readOptions()
        XCTAssertEqual(options.ring, .default, "nothing stored: the default ring")

        var ring = ShortcutRingSettings.default
        ring[0] = ShortcutRingPlace(SystemShortcut.undo)
        ring[4] = .empty
        options.ring = ring
        options.flushPendingSaves()
        XCTAssertNotNil(options.defaults.data(forKey: "shortcutRingSettings"))

        let again = Options()
        again.defaults = options.defaults
        again.readOptions()
        XCTAssertEqual(again.ring, ring)
    }

    func testChangingTheRingTellsItsObserversOnly() {
        let options = Options()
        options.defaults = TestDefaults.make(for: self)
        var told: [OptionsGroup] = []
        options.observe(Set(OptionsGroup.allCases)) { told.append($0) }
        var ring = options.ring
        ring[2] = .empty
        options.ring = ring
        XCTAssertEqual(told, [.ring])
    }
}

// MARK: - Geometry

final class ShortcutRingGeometryTests: XCTestCase {

    private typealias Geometry = ShortcutRingGeometry

    /// Up, right, down, left and the four diagonals, with y growing downwards as in events.
    func testADirectionMeansItsPlaceClockwiseFromTheTop() {
        let far: CGFloat = 60
        let directions: [(CGPoint, Int)] = [
            (CGPoint(x: 0, y: -far), 0), (CGPoint(x: far, y: -far), 1), (CGPoint(x: far, y: 0), 2),
            (CGPoint(x: far, y: far), 3), (CGPoint(x: 0, y: far), 4), (CGPoint(x: -far, y: far), 5),
            (CGPoint(x: -far, y: 0), 6), (CGPoint(x: -far, y: -far), 7),
        ]
        for (offset, place) in directions {
            XCTAssertEqual(Geometry.place(forOffset: offset), place, "\(offset)")
        }
    }

    func testOnlyTheDirectionCountsNotTheDistance() {
        for distance in [Geometry.deadZone, 40, 118, 400, 5000] as [CGFloat] {
            XCTAssertEqual(Geometry.place(forOffset: CGPoint(x: distance, y: 0)), 2)
            XCTAssertEqual(Geometry.place(forOffset: CGPoint(x: -distance * 0.7, y: -distance * 0.75)), 7)
        }
    }

    func testNothingInsideTheDeadZoneOrForNoNumber() {
        XCTAssertNil(Geometry.place(forOffset: .zero))
        XCTAssertNil(Geometry.place(forOffset: CGPoint(x: Geometry.deadZone - 1, y: 0)))
        XCTAssertNil(Geometry.place(forOffset: CGPoint(x: 10, y: -10)))
        XCTAssertNil(Geometry.place(forOffset: CGPoint(x: CGFloat.nan, y: 50)))
        XCTAssertNil(Geometry.place(forOffset: CGPoint(x: CGFloat.infinity, y: 50)))
    }

    /// Each place owns 45 degrees around its middle.
    func testAPlaceOwnsItsEighthOfTheCircle() {
        for place in 0..<8 {
            for degrees in stride(from: -22.0, through: 22.0, by: 11.0) {
                let angle = Geometry.angle(ofPlace: place) + CGFloat(degrees) * .pi / 180
                let offset = CGPoint(x: sin(angle) * 70, y: -cos(angle) * 70)
                XCTAssertEqual(Geometry.place(forOffset: offset), place, "place \(place) at \(degrees)°")
            }
        }
    }

    /// A hand that rests on the border between two places keeps the place it has.
    func testTheLitPlaceHoldsALittlePastItsBorder() {
        func offset(degrees: CGFloat) -> CGPoint {
            let angle = degrees * .pi / 180
            return CGPoint(x: sin(angle) * 70, y: -cos(angle) * 70)
        }
        // The border between top (0) and top right (1) is at 22.5°.
        XCTAssertEqual(Geometry.place(forOffset: offset(degrees: 24)), 1)
        XCTAssertEqual(Geometry.place(forOffset: offset(degrees: 24), current: 0), 0)
        XCTAssertEqual(Geometry.place(forOffset: offset(degrees: 21), current: 1), 1)
        XCTAssertEqual(Geometry.place(forOffset: offset(degrees: 30), current: 0), 1, "well past the border it changes")
        // And across the top, where the angle wraps around.
        XCTAssertEqual(Geometry.place(forOffset: offset(degrees: -24), current: 0), 0)
        XCTAssertEqual(Geometry.place(forOffset: offset(degrees: -30), current: 0), 7)
        XCTAssertNil(Geometry.place(forOffset: CGPoint(x: 3, y: 0), current: 2), "the dead zone lets go")
    }

    func testThePlacesStandOnTheirDirections() {
        XCTAssertEqual(Geometry.offset(ofPlace: 0).x, 0, accuracy: 0.001)
        XCTAssertEqual(Geometry.offset(ofPlace: 0).y, -Geometry.placeRadius, accuracy: 0.001)
        XCTAssertEqual(Geometry.offset(ofPlace: 2).x, Geometry.placeRadius, accuracy: 0.001)
        XCTAssertEqual(Geometry.offset(ofPlace: 4).y, Geometry.placeRadius, accuracy: 0.001)
        for place in 0..<8 {
            XCTAssertEqual(Geometry.place(forOffset: Geometry.offset(ofPlace: place)), place)
        }
    }

    // MARK: The hold way

    func testTheHandsMovementAddsUp() {
        var travel = CGPoint.zero
        for _ in 0..<5 {
            travel = Geometry.travel(travel, movedBy: CGPoint(x: 6, y: -2))
        }
        XCTAssertEqual(travel.x, 30, accuracy: 0.001)
        XCTAssertEqual(travel.y, -10, accuracy: 0.001)
        XCTAssertEqual(Geometry.travel(travel, movedBy: CGPoint(x: CGFloat.nan, y: 1)), travel)
    }

    /// Pushed against the edge of a screen for a long while, the hand needs no more than
    /// the limit and the dead zone to reach the opposite place.
    func testTheMovementIsKeptWithinItsLimit() {
        var travel = CGPoint.zero
        for _ in 0..<200 {
            travel = Geometry.travel(travel, movedBy: CGPoint(x: -25, y: 0))
        }
        XCTAssertEqual(travel.x, -Geometry.travelLimit, accuracy: 0.001)
        XCTAssertEqual(Geometry.place(forOffset: travel), 6)

        var steps = 0
        while Geometry.place(forOffset: travel) != 2 {
            travel = Geometry.travel(travel, movedBy: CGPoint(x: 10, y: 0))
            steps += 1
            XCTAssertLessThan(steps, 100)
        }
        XCTAssertLessThanOrEqual(CGFloat(steps) * 10, Geometry.travelLimit + Geometry.deadZone + 10)
    }

    // MARK: The click way

    func testAPointIsTheMiddleAPlaceOrOutside() {
        let centre = CGPoint(x: 500, y: 400)
        XCTAssertEqual(Geometry.target(at: centre, centre: centre), .middle)
        XCTAssertEqual(Geometry.target(at: CGPoint(x: 500 + Geometry.hubRadius - 2, y: 400), centre: centre), .middle)
        // On a place's circle, between the places and the edge, and a little past the edge.
        XCTAssertEqual(Geometry.target(at: CGPoint(x: 500, y: 400 - Geometry.placeRadius), centre: centre), .place(0))
        XCTAssertEqual(Geometry.target(at: CGPoint(x: 500 + Geometry.outerRadius, y: 400), centre: centre), .place(2))
        XCTAssertEqual(Geometry.target(at: CGPoint(x: 500, y: 400 + Geometry.reach - 1), centre: centre), .place(4))
        XCTAssertEqual(Geometry.target(at: CGPoint(x: 500, y: 400 + Geometry.reach + 1), centre: centre), .outside)
        XCTAssertEqual(Geometry.target(at: CGPoint(x: 900, y: 900), centre: centre), .outside)
        XCTAssertEqual(Geometry.target(at: CGPoint(x: CGFloat.nan, y: 0), centre: centre), .outside)
    }

    // MARK: Near the edge of a screen

    func testAwayFromTheEdgesTheRingStandsAtThePointer() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let pointer = CGPoint(x: 700, y: 500)
        XCTAssertEqual(Geometry.centre(forPointer: pointer, in: screen), pointer)
    }

    /// At an edge and in a corner the whole ring stays on the screen.
    func testNearAnEdgeTheWholeRingStaysOnItsScreen() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1512, height: 982),
            // A second screen to the left of and above the main one.
            CGRect(x: -1920, y: -300, width: 1920, height: 1080),
        ]
        for screen in screens {
            let pointers = [
                CGPoint(x: screen.minX, y: screen.minY), CGPoint(x: screen.maxX - 1, y: screen.minY),
                CGPoint(x: screen.minX, y: screen.maxY - 1), CGPoint(x: screen.maxX - 1, y: screen.maxY - 1),
                CGPoint(x: screen.midX, y: screen.minY + 3), CGPoint(x: screen.maxX - 40, y: screen.midY),
            ]
            for pointer in pointers {
                let centre = Geometry.centre(forPointer: pointer, in: screen)
                let ring = CGRect(
                    x: centre.x - Geometry.outerRadius, y: centre.y - Geometry.outerRadius,
                    width: Geometry.outerRadius * 2, height: Geometry.outerRadius * 2
                )
                XCTAssertTrue(screen.contains(ring), "\(pointer) on \(screen): \(ring)")
            }
        }
        // Only the axis that needs it moves.
        let top = Geometry.centre(forPointer: CGPoint(x: 700, y: 2), in: screens[0])
        XCTAssertEqual(top.x, 700)
        XCTAssertEqual(top.y, Geometry.outerRadius + Geometry.screenMargin)
    }

    func testAScreenTooSmallGetsTheRingInItsMiddle() {
        let screen = CGRect(x: 100, y: 100, width: 150, height: 150)
        XCTAssertEqual(Geometry.centre(forPointer: CGPoint(x: 110, y: 240), in: screen), CGPoint(x: 175, y: 175))
    }

    /// The ring draws inside its canvas, and the free middle is inside the places.
    func testTheSizesFit() {
        XCTAssertLessThanOrEqual(Geometry.placeRadius + Geometry.placeDiameter / 2, Geometry.outerRadius)
        XCTAssertLessThan(Geometry.deadZone, Geometry.hubRadius)
        XCTAssertGreaterThan(Geometry.canvasSide, Geometry.outerRadius * 2)
        XCTAssertGreaterThan(Geometry.reach, Geometry.outerRadius)
        // Two neighbours do not touch.
        let first = Geometry.offset(ofPlace: 0), second = Geometry.offset(ofPlace: 1)
        XCTAssertGreaterThan(hypot(first.x - second.x, first.y - second.y), Geometry.placeDiameter + 4)
    }
}

// MARK: - The rules

final class ShortcutRingSessionTests: XCTestCase {

    private typealias Command = ShortcutRingSession.Command

    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let start = CGPoint(x: 700, y: 500)
    private let allFilled = Array(repeating: true, count: 8)
    /// The trigger goes down at this time.
    private let pressed: TimeInterval = 10

    private func opened(at pointer: CGPoint? = nil, filled: [Bool]? = nil) -> ShortcutRingSession {
        var session = ShortcutRingSession()
        let commands = session.triggerPressed(at: pressed, pointer: pointer ?? start, screen: screen, filled: filled ?? allFilled)
        XCTAssertEqual(commands.count, 1)
        return session
    }

    /// A ring left open by a press without movement.
    private func latched(at pointer: CGPoint? = nil, filled: [Bool]? = nil) -> ShortcutRingSession {
        var session = opened(at: pointer, filled: filled)
        _ = session.triggerReleased(at: pressed + 0.05)
        XCTAssertEqual(session.phase, .latched)
        return session
    }

    /// Moves the hand in steps of at most 8 points, as a mouse does, well after the press.
    @discardableResult
    private func move(_ session: inout ShortcutRingSession, by total: CGPoint, at time: TimeInterval? = nil) -> [Command] {
        var commands: [Command] = []
        let steps = max(1, Int((hypot(total.x, total.y) / 8).rounded(.up)))
        var location = CGPoint(x: start.x + session.travel.x, y: start.y + session.travel.y)
        for _ in 0..<steps {
            let delta = CGPoint(x: total.x / CGFloat(steps), y: total.y / CGFloat(steps))
            location = CGPoint(x: location.x + delta.x, y: location.y + delta.y)
            commands += session.pointerMoved(by: delta, to: location, at: time ?? pressed + 0.5)
        }
        return commands
    }

    private func place(_ index: Int, of session: ShortcutRingSession) -> CGPoint {
        let offset = ShortcutRingGeometry.offset(ofPlace: index)
        return CGPoint(x: session.centre.x + offset.x, y: session.centre.y + offset.y)
    }

    // MARK: Opening

    func testThePressOpensTheRingAtThePointer() {
        var session = ShortcutRingSession()
        XCTAssertFalse(session.needsKeys)
        let commands = session.triggerPressed(at: 1, pointer: start, screen: screen, filled: allFilled)
        XCTAssertEqual(commands, [.open(centre: start)])
        XCTAssertEqual(session.phase, .held)
        XCTAssertNil(session.lit)
        XCTAssertTrue(session.needsKeys, "Esc is the ring's while it is open")
    }

    /// Two triggers can be bound, and a down can come twice: the ring that is held open
    /// stays as it is.
    func testAnotherPressWhileHeldChangesNothing() {
        var session = opened()
        move(&session, by: CGPoint(x: 60, y: 0))
        XCTAssertEqual(session.triggerPressed(at: pressed + 1, pointer: start, screen: screen, filled: allFilled), [])
        XCTAssertEqual(session.phase, .held)
        XCTAssertEqual(session.lit, 2)
    }

    // MARK: The hold way

    func testMovingPastTheDeadZoneLightsThePlaceOfTheDirection() {
        var session = opened()
        XCTAssertEqual(move(&session, by: CGPoint(x: 0, y: -15)), [], "inside the dead zone nothing lights")
        XCTAssertEqual(move(&session, by: CGPoint(x: 0, y: -20)), [.light(0)])
        XCTAssertEqual(session.lit, 0)
        // Around to the right: the top right place, then the right one.
        XCTAssertEqual(move(&session, by: CGPoint(x: 60, y: 30)), [.light(1), .light(2)])
    }

    func testLettingGoRunsTheLitPlaceAfterTheRingHasClosed() {
        var session = opened()
        move(&session, by: CGPoint(x: -50, y: 50))
        XCTAssertEqual(session.lit, 5)
        XCTAssertEqual(session.triggerReleased(at: pressed + 0.9), [.close, .run(5)])
        XCTAssertEqual(session.phase, .closed)
        XCTAssertFalse(session.needsKeys)
    }

    /// No clock tells a hold from a press: a press that lasted long and lit nothing leaves
    /// the ring open, as a short one does.
    func testLettingGoWithNothingEverLitLeavesTheRingOpenHoweverLongThePress() {
        for held in [0.0, 0.05, 0.3, 0.45, 3.0] {
            var session = opened()
            XCTAssertEqual(session.triggerReleased(at: pressed + held), [], "\(held) s")
            XCTAssertEqual(session.phase, .latched, "\(held) s")
        }
        // Also after a little movement that lit nothing.
        var session = opened()
        move(&session, by: CGPoint(x: 9, y: -6))
        XCTAssertEqual(session.triggerReleased(at: pressed + 2), [])
        XCTAssertEqual(session.phase, .latched)
    }

    func testBackInTheMiddleAfterAPlaceWasLitClosesAndRunsNothing() {
        var session = opened()
        move(&session, by: CGPoint(x: 40, y: 0))
        XCTAssertEqual(move(&session, by: CGPoint(x: -38, y: 0)), [.light(nil)])
        XCTAssertEqual(session.triggerReleased(at: pressed + 1), [.close])
        XCTAssertEqual(session.phase, .closed)
    }

    func testAnEmptyPlaceNeverLightsAndRunsNothing() {
        var filled = allFilled
        filled[2] = false
        var session = opened(filled: filled)
        XCTAssertEqual(move(&session, by: CGPoint(x: 60, y: 0)), [])
        XCTAssertNil(session.lit)
        // Nothing was ever lit: the ring stays open.
        XCTAssertEqual(session.triggerReleased(at: pressed + 1), [])
        XCTAssertEqual(session.phase, .latched)

        // From a lit place on to the empty one: let go there closes, and runs nothing.
        var other = opened(filled: filled)
        move(&other, by: CGPoint(x: 0, y: -50))
        XCTAssertEqual(other.lit, 0)
        move(&other, by: CGPoint(x: 80, y: 50))
        XCTAssertNil(other.lit)
        XCTAssertEqual(other.triggerReleased(at: pressed + 1), [.close])
    }

    // MARK: The jerk of the press

    /// A thumb that presses a stiff button pushes the mouse. What moves in the first
    /// moments is not the hand choosing.
    func testTheMovementOfTheFirstMomentsIsNotCounted() {
        var session = opened()
        XCTAssertEqual(move(&session, by: CGPoint(x: 30, y: 0), at: pressed + 0.02), [])
        XCTAssertEqual(session.travel, .zero)
        XCTAssertEqual(move(&session, by: CGPoint(x: 30, y: 0), at: pressed + 0.05), [.light(2)])
    }

    /// A release right after the press chooses only when the hand went far.
    func testAQuickReleaseChoosesOnlyBeyondTwiceTheDeadZone() {
        // Pushed 25 points to the right and let go at once: "Right" was lit, nothing runs,
        // and the ring stays open.
        var jerk = opened()
        XCTAssertEqual(move(&jerk, by: CGPoint(x: 25, y: 0), at: pressed + 0.06), [.light(2)])
        XCTAssertEqual(jerk.triggerReleased(at: pressed + 0.12), [.light(nil)])
        XCTAssertEqual(jerk.phase, .latched)

        // A flick of 60 points in the same time is a choice.
        var flick = opened()
        move(&flick, by: CGPoint(x: 60, y: 0), at: pressed + 0.06)
        XCTAssertEqual(flick.triggerReleased(at: pressed + 0.12), [.close, .run(2)])

        // The same 25 points held for a moment longer are a choice too.
        var slow = opened()
        move(&slow, by: CGPoint(x: 25, y: 0), at: pressed + 0.06)
        XCTAssertEqual(slow.triggerReleased(at: pressed + 0.25), [.close, .run(2)])
    }

    // MARK: The edge of a screen

    /// At the left edge the pointer cannot move left, but the hand's movement arrives; the
    /// ring is drawn away from the pointer and the direction of the hand still chooses.
    func testAtTheEdgeOfTheScreenTheHandStillChooses() {
        var session = ShortcutRingSession()
        let pointer = CGPoint(x: 0, y: 500)
        let commands = session.triggerPressed(at: pressed, pointer: pointer, screen: screen, filled: allFilled)
        let inset = ShortcutRingGeometry.outerRadius + ShortcutRingGeometry.screenMargin
        XCTAssertEqual(commands, [.open(centre: CGPoint(x: inset, y: 500))], "the ring stands inside the screen")
        var lit: [Command] = []
        for _ in 0..<6 {
            // The pointer stays where it is; the mouse reports its movement.
            lit += session.pointerMoved(by: CGPoint(x: -8, y: 0), to: pointer, at: pressed + 0.5)
        }
        XCTAssertEqual(lit, [.light(6)])
        XCTAssertEqual(session.triggerReleased(at: pressed + 1), [.close, .run(6)])
    }

    /// The ring was drawn to the right of the pointer, whose place is over "Left". Held,
    /// that lights nothing: only the hand's movement does.
    func testARingDrawnAwayFromThePointerLightsNothingByItself() {
        var session = ShortcutRingSession()
        _ = session.triggerPressed(at: pressed, pointer: CGPoint(x: 2, y: 500), screen: screen, filled: allFilled)
        XCTAssertNil(session.lit)
        XCTAssertEqual(session.pointerMoved(by: CGPoint(x: 0, y: 1), to: CGPoint(x: 2, y: 501), at: pressed + 0.5), [])
        // Let go: the ring stays open, and now the place under the pointer is lit.
        XCTAssertEqual(session.triggerReleased(at: pressed + 0.6), [.light(6)])
        XCTAssertEqual(session.phase, .latched)
    }

    // MARK: The click way

    /// What a keystroke sent by another app looks like: down and up in the same moment.
    func testDownAndUpAtOnceLeavesTheRingOpen() {
        var session = opened()
        XCTAssertEqual(session.triggerReleased(at: pressed), [])
        XCTAssertEqual(session.phase, .latched)
        XCTAssertTrue(session.needsKeys)
    }

    func testThePointerLightsThePlaceItIsOver() {
        var session = latched()
        XCTAssertEqual(session.pointerMoved(by: .zero, to: place(3, of: session), at: 11), [.light(3)])
        XCTAssertEqual(session.pointerMoved(by: .zero, to: place(4, of: session), at: 11), [.light(4)])
        XCTAssertEqual(session.pointerMoved(by: .zero, to: session.centre, at: 11), [.light(nil)])
        XCTAssertEqual(session.pointerMoved(by: .zero, to: CGPoint(x: 1400, y: 900), at: 11), [])
    }

    func testAClickOnAPlaceRunsItWhenTheButtonComesUp() {
        var session = latched()
        _ = session.pointerMoved(by: .zero, to: place(1, of: session), at: 11)
        XCTAssertEqual(session.buttonPressed(0, at: place(1, of: session)), [])
        XCTAssertEqual(session.phase, .latched, "nothing runs while the button is down")
        XCTAssertEqual(session.buttonReleased(0), [.close, .run(1)])
        XCTAssertEqual(session.phase, .closed)
    }

    /// The pointer need not have moved first (a ring at the edge of a screen stands under it).
    func testAClickLightsAndChoosesWithoutAMoveBefore() {
        var session = latched()
        XCTAssertEqual(session.buttonPressed(0, at: place(6, of: session)), [.light(6)])
        XCTAssertEqual(session.buttonReleased(0), [.close, .run(6)])
    }

    func testAClickOutsideOrInTheMiddleClosesWhenItComesUpAndRunsNothing() {
        for point in [CGPoint(x: 1300, y: 200), start] {
            var session = latched()
            XCTAssertEqual(session.buttonPressed(0, at: point), [])
            XCTAssertEqual(session.phase, .latched)
            XCTAssertEqual(session.buttonReleased(0), [.close])
            XCTAssertEqual(session.phase, .closed)
            XCTAssertEqual(session.buttonReleased(0), [], "a release without its press means nothing")
        }
    }

    func testAClickOnAnEmptyPlaceDoesNothing() {
        var filled = allFilled
        filled[0] = false
        var session = latched(filled: filled)
        XCTAssertEqual(session.buttonPressed(0, at: place(0, of: session)), [])
        XCTAssertEqual(session.buttonReleased(0), [])
        XCTAssertEqual(session.phase, .latched, "the ring stays open")
    }

    func testAnyOtherButtonClosesTheRing() {
        var session = latched()
        XCTAssertEqual(session.buttonPressed(1, at: place(2, of: session)), [])
        XCTAssertEqual(session.buttonReleased(1), [.close])
    }

    func testAPlaceWhoseClickIsDownStaysChosenWhileThePointerMoves() {
        var session = latched()
        _ = session.buttonPressed(0, at: place(2, of: session))
        XCTAssertEqual(session.pointerMoved(by: .zero, to: place(4, of: session), at: 11), [])
        XCTAssertEqual(session.buttonReleased(0), [.close, .run(2)])
    }

    /// While the trigger is held, a click is not the ring's.
    func testAClickDuringAHoldMeansNothingToTheRing() {
        var session = opened()
        XCTAssertEqual(session.buttonPressed(0, at: start), [])
        XCTAssertEqual(session.buttonReleased(0), [])
        XCTAssertEqual(session.phase, .held)
    }

    func testEscClosesAndItsReleaseIsSwallowedToo() {
        var session = latched()
        let down = session.escapePressed()
        XCTAssertEqual(down.answer, .swallow)
        XCTAssertEqual(down.commands, [.close])
        XCTAssertTrue(session.needsKeys, "its release is still to come")
        XCTAssertEqual(session.escapeReleased(), .swallow)
        XCTAssertFalse(session.needsKeys)
        XCTAssertEqual(session.escapePressed().answer, .pass, "Esc without a ring is the app's")
        XCTAssertEqual(session.escapeReleased(), .pass)
    }

    func testEscAlsoEndsAHoldAndItsReleaseThenDoesNothing() {
        var session = opened()
        move(&session, by: CGPoint(x: 50, y: 0))
        XCTAssertEqual(session.escapePressed().commands, [.close])
        XCTAssertEqual(session.triggerReleased(at: pressed + 1), [])
    }

    func testTheTriggerAgainClosesAnOpenRingAndItsReleaseDoesNothing() {
        var session = latched()
        _ = session.pointerMoved(by: .zero, to: place(2, of: session), at: 11)
        XCTAssertEqual(session.triggerPressed(at: 12, pointer: start, screen: screen, filled: allFilled), [.close])
        XCTAssertEqual(session.phase, .closed)
        XCTAssertEqual(session.triggerReleased(at: 12.05), [])
        XCTAssertEqual(session.phase, .closed, "it does not open again")
    }

    // MARK: Giving up

    /// The mouse went away mid-hold: the release is made up, and nothing runs.
    func testAMadeUpReleaseClosesAndRunsNothing() {
        var session = opened()
        move(&session, by: CGPoint(x: 0, y: 60))
        XCTAssertEqual(session.lit, 4)
        XCTAssertEqual(session.triggerReleased(at: pressed + 1, isMadeUp: true), [.close])
        // Also with nothing lit: the ring does not stay open without its mouse.
        var still = opened()
        XCTAssertEqual(still.triggerReleased(at: pressed + 1, isMadeUp: true), [.close])
        XCTAssertEqual(still.phase, .closed)
    }

    func testAHoldWhoseReleaseNeverComesClosesAfterItsLimit() {
        var session = opened()
        move(&session, by: CGPoint(x: 0, y: 60))
        XCTAssertEqual(session.timePassed(to: pressed + ShortcutRingSession.holdLimit - 0.1), [])
        XCTAssertEqual(session.timePassed(to: pressed + ShortcutRingSession.holdLimit), [.close])
        XCTAssertEqual(session.triggerReleased(at: pressed + 60), [], "a late release runs nothing")
    }

    func testAnOpenRingClosesAfterTenSecondsWithoutThePointerMoving() {
        XCTAssertEqual(ShortcutRingSession.idleLimit, 10)
        var session = latched()
        XCTAssertEqual(session.timePassed(to: pressed + 9), [])
        // The pointer moved: the time starts again.
        _ = session.pointerMoved(by: .zero, to: place(1, of: session), at: pressed + 9)
        XCTAssertEqual(session.timePassed(to: pressed + 18.9), [])
        XCTAssertEqual(session.timePassed(to: pressed + 19), [.close])
        XCTAssertEqual(session.timePassed(to: pressed + 40), [])
    }

    func testCancelClosesAndWaitsForNothing() {
        var session = latched()
        _ = session.buttonPressed(0, at: place(2, of: session))
        XCTAssertEqual(session.cancel(), [.close])
        XCTAssertFalse(session.needsKeys)
        XCTAssertEqual(session.cancel(), [], "a closed ring has nothing to close")
        XCTAssertEqual(session.buttonReleased(0), [])
    }

    /// Whatever happens, the ring is closed before anything runs.
    func testCloseAlwaysComesBeforeRun() {
        var held = opened()
        move(&held, by: CGPoint(x: 0, y: 60))
        var clicked = latched()
        _ = clicked.buttonPressed(0, at: place(7, of: clicked))
        for commands in [held.triggerReleased(at: pressed + 1), clicked.buttonReleased(0)] {
            let close = commands.firstIndex(of: .close)
            let run = commands.firstIndex { if case .run = $0 { return true } else { return false } }
            XCTAssertNotNil(close)
            XCTAssertNotNil(run)
            XCTAssertLessThan(close ?? 9, run ?? 0)
        }
    }
}
