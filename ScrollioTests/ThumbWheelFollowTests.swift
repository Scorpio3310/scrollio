//
//  ThumbWheelFollowTests.swift
//  ScrollioTests
//
//  The thumb wheel's options: each action's own "Reverse direction" and Switch Desktops'
//  "Follow the wheel", stored, carried by a settings file and run through the scroll tap.
//  The dock swipe is a fake: nothing reaches the Dock.
//

import XCTest
@testable import Scrollio_Debug

private typealias FrontApp = ShortcutRingChoice.FrontApp

// MARK: - Stored

final class ThumbWheelOptionsStoredTests: XCTestCase {

    private func decode(_ json: String) throws -> ThumbWheelSettings {
        return try JSONDecoder().decode(ThumbWheelSettings.self, from: Data(json.utf8))
    }

    private func encode(_ settings: ThumbWheelSettings) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(settings), as: UTF8.self)
    }

    /// An entry (or a file) from before, with its one "Swap direction", gives every action
    /// that value; Follow the wheel is off.
    func testTheOldSwapSeedsEveryActionAndFollowIsOff() throws {
        let old = try decode(#"{"function":"volume","speed":2.5,"swapsDirection":true}"#)
        for function in ThumbWheelFunction.allCases {
            XCTAssertTrue(old.reverses[function], "\(function)")
        }
        XCTAssertFalse(old.followsWheel)
        XCTAssertFalse(try decode(#"{"function":"desktops"}"#).followsWheel, "off by default")
        XCTAssertFalse(ThumbWheelSettings.default.followsWheel)
        XCTAssertEqual(ThumbWheelSettings.default.reverses, .none)
        let notSwapped = try decode(#"{"function":"tabs","swapsDirection":false}"#)
        XCTAssertEqual(notSwapped.reverses, .none)
    }

    /// Settings whose actions all have the same switch, without Follow the wheel, are
    /// written exactly as before; one action set apart writes every action's switch by
    /// name, with "swapsDirection" the chosen action's (what 1.0.5
    /// reads); Follow the wheel only while on. Read back, every value is as it was.
    func testTheStoredFormSaysMoreOnlyWhenItHasMoreToSay() throws {
        XCTAssertEqual(try encode(ThumbWheelSettings(function: .zoom, speed: 1.5, swapsDirection: true)),
                       #"{"function":"zoom","speed":1.5,"swapsDirection":true}"#)
        var settings = ThumbWheelSettings(function: .volume, speed: 2)
        settings.reverses[.volume] = true
        settings.reverses[.desktops] = true
        settings.followsWheel = true
        let plain = try encode(settings)
        XCTAssertEqual(plain, #"{"followsWheel":true,"function":"volume","#
            + #""reverseDirection":{"backForward":false,"desktops":true,"scroll":false,"tabs":false,"volume":true,"zoom":false},"#
            + #""speed":2,"swapsDirection":true}"#)
        XCTAssertEqual(try decode(plain), settings)

        // The chosen action not reversed while another is: 1.0.5 turns it unreversed.
        settings.function = .zoom
        XCTAssertTrue(try encode(settings).contains(#""swapsDirection":false"#))
        XCTAssertEqual(try decode(try encode(settings)), settings)
    }

    /// An action missing in "reverseDirection" takes the old switch; a map that cannot be
    /// read is none (the old switch for all); the stored names are the functions' own.
    func testAMissingOrUnreadableActionTakesTheOldSwitch() throws {
        let partial = try decode(#"{"function":"tabs","swapsDirection":true,"reverseDirection":{"zoom":false}}"#)
        XCTAssertFalse(partial.reverses[.zoom])
        XCTAssertTrue(partial.reverses[.tabs])
        XCTAssertTrue(partial.reverses[.volume])
        let broken = try decode(#"{"function":"tabs","swapsDirection":true,"reverseDirection":{"zoom":"no"},"followsWheel":"yes"}"#)
        XCTAssertEqual(broken.reverses, .all)
        XCTAssertFalse(broken.followsWheel)
        XCTAssertEqual(OptionItem.ThumbWheel.Settings, "thumbWheelSettings", "never renamed")
    }

    /// An app's own values: from before (one swap) every action takes it; a map and the
    /// follow switch are stored only when there; nothing of the app's: the general ones.
    func testAnAppsOwnValuesAreStoredAndSeededTheSameWay() throws {
        func scrolling(_ json: String) throws -> ApplicationThumbWheelScrolling {
            return try JSONDecoder().decode(ApplicationThumbWheelScrolling.self, from: Data(json.utf8))
        }
        XCTAssertEqual(try scrolling(#"{"speed":1.5,"swapsDirection":true}"#),
                       ApplicationThumbWheelScrolling(speed: 1.5, reverses: .all, followsWheel: nil))
        XCTAssertEqual(try scrolling(#"{"speed":1.5}"#), ApplicationThumbWheelScrolling(speed: 1.5, reverses: nil, followsWheel: nil))

        var reverses = ThumbWheelReversal.none
        reverses[.zoom] = true
        let own = ApplicationThumbWheelScrolling(speed: 1, reverses: reverses, followsWheel: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(own)
        XCTAssertEqual(String(decoding: data, as: UTF8.self),
                       #"{"followsWheel":true,"reverseDirection":{"backForward":false,"desktops":false,"scroll":false,"tabs":false,"volume":false,"zoom":true},"speed":1}"#)
        XCTAssertEqual(try JSONDecoder().decode(ApplicationThumbWheelScrolling.self, from: data), own)

        // What runs in the app: its own where it has them, else the general ones.
        let general = ThumbWheelSettings(function: .desktops, speed: 2, swapsDirection: true)
        let mine = ThumbWheelOwn(reverses: reverses, followsWheel: true).settings(general: general)
        XCTAssertFalse(mine.reverses[.desktops])
        XCTAssertTrue(mine.followsWheelNow)
        XCTAssertEqual(mine.speed, 2)
        XCTAssertEqual(ThumbWheelOwn(speed: 1).settings(general: general).reverses, .all, "nothing of its own: the general")
    }

    /// A settings file carries every action's switch and the follow switch, general and an
    /// app's own, and an import puts them back as they were.
    func testTheSettingsFileCarriesThem() throws {
        let source = Options()
        source.defaults = TestDefaults.make(for: self)
        var general = ThumbWheelSettings(function: .desktops, speed: 1.25, followsWheel: true)
        general.reverses[.volume] = true
        source.thumbWheel = general
        let figma = Application(path: "/Applications/Figma.app")
        figma.inherit = false
        var own = ThumbWheelSettings(function: .zoom, swapsDirection: true)
        own.reverses[.tabs] = false
        own.followsWheel = false
        figma.setOwnThumbWheelScrolling(own)
        source.application.applications.append(figma)

        let data = try SettingsFile.export(from: source, now: Date(timeIntervalSince1970: 1_794_476_527)).get()
        let contents = try SettingsFile.read(data).get()
        XCTAssertEqual(contents.thumbWheel, general)
        XCTAssertEqual(contents.leftOutCount, 0)

        let target = Options()
        target.defaults = TestDefaults.make(for: self)
        target.readOptions()
        XCTAssertTrue(SettingsFile.apply(contents, to: target))
        XCTAssertEqual(target.thumbWheel, general)
        let imported = try XCTUnwrap(target.application.applications.get(by: figma.path))
        XCTAssertEqual(imported.scroll.thumbWheel, ApplicationThumbWheelScrolling(own))
        XCTAssertFalse(imported.thumbWheelThatRuns(general: general).followsWheel, "the app's own: off")
        XCTAssertFalse(imported.thumbWheelThatRuns(general: general).reverses[.tabs])
        XCTAssertTrue(imported.thumbWheelThatRuns(general: general).reverses[.volume])
    }
}

// MARK: - Through the scroll tap

final class ThumbWheelFollowTests: XCTestCase {

    private static let figma = "/Applications/Figma.app"
    private static let notes = "/Applications/Notes.app"

    /// The Dock as the wheel's swipe sees it: what it was told, in order.
    final class FakeDock {
        enum Call: Equatable {
            case begin
            case update(Double)
            case end(Double)
            case cancel
        }
        var calls: [Call] = []
        var available = true
        var updates: [Double] {
            return calls.compactMap { if case .update(let progress) = $0 { return progress } else { return nil } }
        }
        var terminals: [Call] {
            return calls.filter { if case .update = $0 { return false } else { return $0 != .begin } }
        }
        func driver() -> DockSwipeDriver {
            return DockSwipeDriver(
                isAvailable: { [unowned self] in self.available },
                begin: { [unowned self] _ in self.calls.append(.begin) },
                update: { [unowned self] in self.calls.append(.update($0)) },
                end: { [unowned self] in self.calls.append(.end($0)) },
                cancel: { [unowned self] in self.calls.append(.cancel) }
            )
        }
    }

    private var rig: ThumbWheelEngineTests.Rig!
    private var dock: FakeDock!
    private var synthesizer: DockSwipeSynthesizer!
    private var savedEngine: ThumbWheelEngine!
    private var savedThumbWheel = ThumbWheelSettings.default
    private var savedSmooth = true
    private var savedAllowlist = false
    private var savedApplications: EnhanceArray<Application>!
    private var front: FrontApp?

    /// Three Spaces: one Space is 1.5 of progress, a unit a quarter of that.
    private static let space = DockSwipeGeometry.progressPerSpace(spaceCount: 3)

    override func setUp() {
        super.setUp()
        savedApplications = Options.shared.application.applications
        savedEngine = ScrollCore.shared.thumbWheelEngine
        savedThumbWheel = Options.shared.thumbWheel
        savedSmooth = Options.shared.scroll.smooth
        savedAllowlist = Options.shared.application.allowlist
        rig = ThumbWheelEngineTests.Rig()
        rig.engine.frontApplication = { [unowned self] in self.front }
        dock = FakeDock()
        synthesizer = DockSwipeSynthesizer()
        synthesizer.setTestingDriver(dock.driver())
        rig.engine.follower.synthesizer = synthesizer
        rig.engine.follower.screen = { InteractiveGestureScreen(width: 1440, spaceCount: 3, frameDuration: 1.0 / 60.0) }
        ScrollCore.shared.thumbWheelEngine = rig.engine
        ScrollCore.shared.handover = ScrollHandover()
        Options.shared.scroll.smooth = false
        Options.shared.application.allowlist = false
        Options.shared.thumbWheel = ThumbWheelSettings(function: .desktops, followsWheel: true)
        ScrollCore.shared.toggleScroll = false
        ScrollCore.shared.blockSmooth = false
        ScrollUtils.shared.treatAsRemoteForTests(sourcePID: nil)
        Options.shared.application.applications = EnhanceArray<Application>(
            withArray: [Application(path: Self.figma), Application(path: Self.notes)], matchKey: "path"
        )
    }

    override func tearDown() {
        synthesizer.clearTestingDriver()
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

    /// A sideways event of `lines` (negative: toward "next") that happened `time` seconds
    /// after the rig's start, through the tap's callback; the event as it went on, or nil
    /// when it was swallowed.
    @discardableResult
    private func turn(at time: Double, lines: Int64 = -2) throws -> CGEvent? {
        rig.advance(to: 500 + time)
        let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 0, wheel2: 0, wheel3: 0))
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: lines)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: Double(lines))
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: Double(lines * 10))
        event.setIntegerValueField(.eventSourceUnixProcessID, value: 0)
        event.setIntegerValueField(.eventTargetUnixProcessID, value: 1)
        event.timestamp = ThumbWheelEngineTests.Rig.timestamp(time)
        return ScrollCore.shared.scrollEventCallBack(CGEventTapProxy(bitPattern: 1)!, .scrollWheel, event, nil)?.takeUnretainedValue()
    }

    // MARK: Follow the wheel

    /// Four slow-ish events toward the next desktop: the first begins the swipe, each moves
    /// it on a sixth of a Space (eased over a few frames, never past where the wheel put
    /// it), nothing runs as a step; when the wheel has rested the desktop is put where the
    /// wheel left it and the swipe ends with no speed: macOS settles it by its position.
    /// The roll's line says so.
    func testAStrokeBeginsMovesAndEndsWhenTheWheelRests() throws {
        for (index, time) in [0, 0.05, 0.1, 0.15].enumerated() {
            XCTAssertNil(try turn(at: time), "event \(index): swallowed")
        }
        rig.advance(to: 500.3)
        XCTAssertEqual(dock.calls.first, .begin)
        XCTAssertEqual(dock.calls.filter { $0 == .begin }.count, 1, "one swipe")
        let updates = dock.updates
        XCTAssertGreaterThan(updates.count, 4, "eased: more frames than events")
        XCTAssertEqual(updates, updates.sorted(), "toward the next desktop only")
        XCTAssertEqual(try XCTUnwrap(updates.last), 4 * Self.space / 6, accuracy: 1e-9, "where the wheel put it, at rest")
        XCTAssertTrue(dock.terminals.isEmpty, "not before the wheel rests")

        rig.advance(to: 501)
        XCTAssertEqual(dock.terminals, [.end(0)])
        XCTAssertTrue(rig.performed.isEmpty, "no step")
        XCTAssertFalse(synthesizer.isActive)
        rig.advance(to: 503)
        let line = try XCTUnwrap(rig.lines.last)
        XCTAssertTrue(line.follows)
        XCTAssertEqual(line.swipesEnded, 1)
        XCTAssertEqual(line.furthestSwipe, 4.0 / 6, accuracy: 1e-9)
        XCTAssertTrue(ScrollSystemLog.thumbWheelMessage(for: line).hasSuffix("switch desktops, following x1.00, travel 4.0: 1 swipe ended (furthest 0.67 of a desktop)"),
                      ScrollSystemLog.thumbWheelMessage(for: line))
    }

    /// Turned back to where it began: the swipe is cancelled (the same rule as Follow the
    /// hand's); turned the other way it slides toward the previous desktop; a long turn
    /// stops at one Space.
    func testBackToTheStartCancelsAndTheOtherWayGoesToThePreviousDesktop() throws {
        try turn(at: 0)
        try turn(at: 0.05)
        try turn(at: 0.1, lines: 2)
        try turn(at: 0.15, lines: 2)
        rig.advance(to: 501)
        XCTAssertEqual(dock.terminals, [.cancel])

        dock.calls = []
        for step in 0..<12 {
            try turn(at: 2 + Double(step) * 0.03, lines: 3)
        }
        rig.advance(to: 503)
        XCTAssertEqual(try XCTUnwrap(dock.updates.last), -Self.space, accuracy: 1e-9, "one Space at most, toward the previous one")
        XCTAssertEqual(dock.terminals, [.end(0)])
    }

    /// "Reverse direction" of Switch Desktops turns the slide around too.
    func testReverseDirectionTurnsTheSlideAround() throws {
        Options.shared.thumbWheel.reverses[.desktops] = true
        try turn(at: 0)
        rig.advance(to: 501)
        XCTAssertLessThan(try XCTUnwrap(dock.updates.last), 0)
    }

    /// Off by default: Switch Desktops runs steps, and no swipe is begun.
    func testOffByDefaultTheDesktopsGoInSteps() throws {
        Options.shared.thumbWheel = ThumbWheelSettings(function: .desktops)
        for time in [0, 0.05, 0.1] { XCTAssertNil(try turn(at: time)) }
        rig.advance(to: 502)
        XCTAssertEqual(rig.performed.map(\.action), [.named("moveSpaceRight")])
        XCTAssertTrue(dock.calls.isEmpty)
    }

    /// Where no swipe can be made, the desktops go in steps.
    func testWithoutASwipeTheDesktopsGoInSteps() throws {
        dock.available = false
        for time in [0, 0.05, 0.1] { XCTAssertNil(try turn(at: time)) }
        rig.advance(to: 502)
        XCTAssertEqual(rig.performed.map(\.action), [.named("moveSpaceRight")])
        XCTAssertTrue(dock.calls.isEmpty)
    }

    /// A gesture's swipe runs: the stroke waits for its rest and sends nothing (no step
    /// either); the gesture's swipe is left alone. The next stroke, once it is over, follows.
    func testAStrokeWaitsWhileAnotherSwipeRuns() throws {
        synthesizer.begin(axis: .horizontal)
        synthesizer.update(progress: 0.3)
        let gestures = dock.calls
        for time in [0, 0.05, 0.1] { XCTAssertNil(try turn(at: time)) }
        rig.advance(to: 501)
        XCTAssertEqual(dock.calls, gestures, "nothing sent to the gesture's swipe")
        XCTAssertTrue(synthesizer.isActive)
        XCTAssertTrue(rig.performed.isEmpty)
        rig.advance(to: 502)
        XCTAssertEqual(rig.lines.last?.strokesWaited, 1)

        synthesizer.end(velocity: 0)
        dock.calls = []
        try turn(at: 3)
        rig.advance(to: 504)
        XCTAssertEqual(dock.calls.first, .begin)
        XCTAssertEqual(dock.terminals, [.end(0)])
    }

    /// A gesture begins its swipe during a stroke: the wheel's swipe is cancelled (by the
    /// synthesizer, once), the stroke sends nothing more, not even at its rest, and the
    /// gesture's swipe goes on.
    func testAGestureTakesOverAndTheStrokeStopsSending() throws {
        try turn(at: 0)
        rig.advance(to: 500.1)
        XCTAssertEqual(dock.calls.first, .begin)
        synthesizer.begin(axis: .horizontal)  // a gesture hold that follows the hand
        let afterTakeOver = dock.calls
        XCTAssertEqual(afterTakeOver.filter { $0 == .cancel }.count, 1, "the wheel's swipe, cancelled by the gesture's begin")
        try turn(at: 0.15)
        try turn(at: 0.2)
        rig.advance(to: 502)
        XCTAssertEqual(dock.calls, afterTakeOver, "nothing more from the wheel")
        XCTAssertTrue(synthesizer.isActive, "the gesture's swipe goes on")
        XCTAssertEqual(rig.lines.last?.swipesInterrupted, 1)
    }

    /// A stop (Pause, sleep, a tap restart) cancels the swipe at once, inside the call.
    func testAStopCancelsTheSwipeAtOnce() throws {
        try turn(at: 0)
        rig.advance(to: 500.1)
        rig.engine.reset()
        XCTAssertEqual(dock.terminals, [.cancel])
        XCTAssertFalse(synthesizer.isActive)
        rig.advance(to: 502)
        XCTAssertEqual(dock.terminals, [.cancel], "nothing scheduled runs after it")
    }

    /// Follow the wheel switched off in the middle of a stroke: the stroke ends there by the
    /// rule, and the next event is a step.
    func testSwitchedOffInTheMiddleTheStrokeEndsAndStepsFollow() throws {
        try turn(at: 0)
        try turn(at: 0.05)
        rig.advance(to: 500.1)
        Options.shared.thumbWheel.followsWheel = false
        try turn(at: 0.15)
        XCTAssertEqual(dock.terminals, [.end(0)])
        try turn(at: 0.2)
        try turn(at: 0.25)
        rig.advance(to: 502)
        XCTAssertEqual(rig.performed.map(\.action), [.named("moveSpaceRight")])
    }

    /// An app's own Follow the wheel (its own Scrolling settings): with it in front the
    /// desktops follow, with another app in front they step; a turn keeps its values when
    /// another app comes to the front in the middle (a swipe brings another desktop).
    func testAnAppsOwnFollowRunsWhileItIsInFrontAndTheTurnKeepsIt() throws {
        Options.shared.thumbWheel = ThumbWheelSettings(function: .desktops)
        let figma = try XCTUnwrap(Options.shared.application.applications.get(by: Self.figma))
        figma.inherit = false
        figma.setOwnThumbWheelScrolling(ThumbWheelSettings(function: .desktops, followsWheel: true))
        front = FrontApp(bundlePath: Self.figma)
        try turn(at: 0)
        front = FrontApp(bundlePath: Self.notes)
        try turn(at: 0.1)
        try turn(at: 0.2)
        rig.advance(to: 502)
        XCTAssertEqual(dock.calls.filter { $0 == .begin }.count, 1)
        XCTAssertEqual(try XCTUnwrap(dock.updates.last), 3 * Self.space / 6, accuracy: 1e-9, "the whole turn followed")
        XCTAssertTrue(rig.performed.isEmpty)
        XCTAssertEqual(rig.lines.first?.isAppsOwn, true)

        dock.calls = []
        for time in [3, 3.05, 3.1] { try turn(at: time) }
        rig.advance(to: 505)
        XCTAssertTrue(dock.calls.isEmpty, "Notes in front: the general steps")
        XCTAssertEqual(rig.performed.map(\.action), [.named("moveSpaceRight")])
    }

    // MARK: Reverse direction, each action its own

    /// For every action: a turn toward "next" runs "next"; with that action's own reverse
    /// it runs "previous"; with every other action reversed it still runs "next". Scroll
    /// Sideways: the event goes on with its X turned around by its own reverse only.
    func testEachActionUsesItsOwnReverse() throws {
        Options.shared.scroll.smooth = false
        let next: [ThumbWheelFunction: ThumbWheelAction] = [
            .zoom: .zoomIn, .tabs: .keys(ThumbWheelAction.nextTab), .desktops: .named("moveSpaceRight"),
            .backForward: .named("navigateForward"), .volume: .volume(.up),
        ]
        let previous: [ThumbWheelFunction: ThumbWheelAction] = [
            .zoom: .zoomOut, .tabs: .keys(ThumbWheelAction.previousTab), .desktops: .named("moveSpaceLeft"),
            .backForward: .named("navigateBack"), .volume: .volume(.down),
        ]
        var start = 0.0
        func firstStep(_ function: ThumbWheelFunction, reverses: ThumbWheelReversal) throws -> ThumbWheelAction? {
            Options.shared.thumbWheel = ThumbWheelSettings(function: function, speed: 1, reverses: reverses, followsWheel: false)
            let ran = rig.performed.count
            for offset in [0, 0.05, 0.1] { try turn(at: start + offset, lines: -12) }
            start += 2
            rig.advance(to: 500 + start)
            return rig.performed.dropFirst(ran).first?.action
        }
        for function in ThumbWheelFunction.allCases where function != .scroll {
            var own = ThumbWheelReversal.none
            own[function] = true
            var others = ThumbWheelReversal.all
            others[function] = false
            XCTAssertEqual(try firstStep(function, reverses: .none), next[function], "\(function)")
            XCTAssertEqual(try firstStep(function, reverses: own), previous[function], "\(function) reversed")
            XCTAssertEqual(try firstStep(function, reverses: others), next[function], "\(function): the others' switches")
        }

        var scrollOwn = ThumbWheelReversal.none
        scrollOwn[.scroll] = true
        var scrollOthers = ThumbWheelReversal.all
        scrollOthers[.scroll] = false
        // (Relative to the event as "Reverse wheel direction" leaves it.)
        func sign(_ reverses: ThumbWheelReversal) throws -> FloatingPointSign {
            Options.shared.thumbWheel = ThumbWheelSettings(function: .scroll, speed: 1, reverses: reverses, followsWheel: false)
            let event = try XCTUnwrap(try turn(at: start, lines: -12), "it scrolls: goes on")
            start += 2
            return event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2).sign
        }
        let plain = try sign(.none)
        XCTAssertNotEqual(try sign(scrollOwn), plain, "Scroll Sideways reversed")
        XCTAssertEqual(try sign(scrollOthers), plain, "the other actions' switches")
    }
}
