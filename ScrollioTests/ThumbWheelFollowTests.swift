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
            /// Not the Dock's: the test told the follower the Space changed.
            case spaceChanged
        }
        var calls: [Call] = [] {
            didSet { if calls.isEmpty { times = [] } }
        }
        /// When each call came (seconds after the rig's start).
        var times: [Double] = []
        var clock: () -> Double = { 0 }
        var available = true
        /// Runs after each `end` (a test makes the Space change with it).
        var onEnd: (() -> Void)?
        var updates: [Double] {
            return calls.compactMap { if case .update(let progress) = $0 { return progress } else { return nil } }
        }
        var terminals: [Call] {
            return calls.filter { if case .end = $0 { return true } else { return $0 == .cancel } }
        }
        func record(_ call: Call) {
            calls.append(call)
            times.append(clock())
        }
        func driver() -> DockSwipeDriver {
            return DockSwipeDriver(
                isAvailable: { [unowned self] in self.available },
                begin: { [unowned self] _ in self.record(.begin) },
                update: { [unowned self] in self.record(.update($0)) },
                end: { [unowned self] in
                    self.record(.end($0))
                    self.onEnd?()
                },
                cancel: { [unowned self] in self.record(.cancel) }
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
    /// The scroll tap's callback runs: no swipe's ending may be told to the line then.
    private var insideTapCallback = false

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
        dock.clock = { [unowned self] in self.rig.now - 500 }
        synthesizer = DockSwipeSynthesizer()
        synthesizer.setTestingDriver(dock.driver())
        rig.engine.follower.synthesizer = synthesizer
        rig.engine.follower.screen = { InteractiveGestureScreen(width: 1440, spaceCount: 3, frameDuration: 1.0 / 60.0) }
        let told = rig.engine.follower.onSwipeEnd
        rig.engine.follower.onSwipeEnd = { [unowned self] tag, swipe in
            XCTAssertFalse(self.insideTapCallback, "a swipe's ending told inside the tap callback")
            told?(tag, swipe)
        }
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
    /// when it was swallowed. `busy`: the main queue has been busy, the work due meanwhile
    /// has not run.
    @discardableResult
    private func turn(at time: Double, lines: Int64 = -2, fixed: Double? = nil, busy: Bool = false) throws -> CGEvent? {
        if busy {
            rig.now = max(rig.now, 500 + time)
        } else {
            rig.advance(to: 500 + time)
        }
        let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 0, wheel2: 0, wheel3: 0))
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: lines)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: fixed ?? Double(lines))
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: Double(lines * 10))
        event.setIntegerValueField(.eventSourceUnixProcessID, value: 0)
        event.setIntegerValueField(.eventTargetUnixProcessID, value: 1)
        event.timestamp = ThumbWheelEngineTests.Rig.timestamp(time)
        insideTapCallback = true
        defer { insideTapCallback = false }
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
        // (0.67 of a desktop: the line waits for the Space change, late ones included.)
        rig.advance(to: 504)
        let line = try XCTUnwrap(rig.lines.last)
        XCTAssertTrue(line.follows)
        XCTAssertEqual(line.swipeTally.ended, 1)
        XCTAssertEqual(line.furthestSwipe, 4.0 / 6, accuracy: 1e-9)
        XCTAssertTrue(ScrollSystemLog.thumbWheelMessage(for: line).hasSuffix("switch desktops, following x1.00, travel 4.0: swipes 0.67 ended no change; ticks held 0, dropped 0"),
                      ScrollSystemLog.thumbWheelMessage(for: line))
    }

    /// A lone tick of 0.10 line 0.7 s after a stroke (where the thumb lets go of the wheel)
    /// begins no swipe: the stray-tick filter holds it, and it is dropped.
    func testALoneTickAfterAStrokeBeginsNoSwipe() throws {
        for time in [0, 0.05, 0.1, 0.15] { try turn(at: time) }
        rig.advance(to: 501)
        XCTAssertEqual(dock.calls.filter { $0 == .begin }.count, 1)
        for lines: Int64 in [1, -1] {
            let start = lines > 0 ? 0.15 + 0.7 : 4.0
            rig.advance(to: 500 + start)
            let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 0, wheel2: 0, wheel3: 0))
            event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: lines)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: Double(lines) * 0.1)
            event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: Double(lines))
            event.setIntegerValueField(.eventSourceUnixProcessID, value: 0)
            event.setIntegerValueField(.eventTargetUnixProcessID, value: 1)
            event.timestamp = ThumbWheelEngineTests.Rig.timestamp(start)
            XCTAssertNil(ScrollCore.shared.scrollEventCallBack(CGEventTapProxy(bitPattern: 1)!, .scrollWheel, event, nil), "swallowed")
            rig.advance(to: 500 + start + 2)
            XCTAssertEqual(dock.calls.filter { $0 == .begin }.count, 1, "no swipe for the tick \(lines)")
            XCTAssertEqual(rig.lines.last?.ticksHeld, 1)
            XCTAssertEqual(rig.lines.last?.ticksDropped, 1)
        }
        XCTAssertTrue(rig.performed.isEmpty)
    }

    /// Where the thumb lets go, a pair of ticks the other way 0.7 s after a stroke (+0.10
    /// line, +0.10 0.12 s later) begins no swipe.
    func testALetGoPairAfterAStrokeBeginsNoSwipe() throws {
        for index in 0..<6 { try turn(at: Double(index) * 0.05, lines: -2, fixed: -2.5) }
        rig.advance(to: 500.9)
        XCTAssertEqual(beginCount, 1)
        try turn(at: 0.25 + 0.7, lines: 1, fixed: 0.1)
        try turn(at: 0.25 + 0.82, lines: 1, fixed: 0.1)
        rig.advance(to: 505)
        XCTAssertEqual(beginCount, 1, "\(dock.calls)")
        let pair = try XCTUnwrap(rig.lines.first { $0.events == 2 }, "the pair is a roll of its own")
        XCTAssertEqual(pair.ticksHeld, 2)
        XCTAssertEqual(pair.ticksDropped, 2)
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
        XCTAssertEqual(rig.lines.last?.swipeTally.interrupted, 1)
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

        dock.calls = []
        for time in [3, 3.05, 3.1] { try turn(at: time) }
        rig.advance(to: 505)
        XCTAssertTrue(dock.calls.isEmpty, "Notes in front: the general steps")
        XCTAssertEqual(rig.performed.map(\.action), [.named("moveSpaceRight")])
        XCTAssertEqual(rig.lines.first?.isAppsOwn, true)
    }

    // MARK: Several desktops in one stroke

    /// The Space changes this long after each end of a swipe, as macOS says it.
    private func changeTheSpace(after delay: Double) {
        dock.onEnd = { [unowned self] in
            self.rig.engine.schedule(delay) { [unowned self] in
                self.dock.record(.spaceChanged)
                self.rig.engine.follower.spaceDidChange()
            }
        }
    }

    /// The dock's calls make sense: a swipe begins only while none runs and only once the
    /// Space changed after the last end; updates only while one runs.
    private func assertEveryBeginFollowsASpaceChange(file: StaticString = #filePath, line: UInt = #line) {
        var active = false
        var spaceChanged = true
        for (index, call) in dock.calls.enumerated() {
            switch call {
            case .begin:
                XCTAssertFalse(active, "call \(index): a begin while a swipe runs", file: file, line: line)
                XCTAssertTrue(spaceChanged, "call \(index): a begin before the Space changed", file: file, line: line)
                active = true
                spaceChanged = false
            case .update:
                XCTAssertTrue(active, "call \(index): an update outside a swipe", file: file, line: line)
            case .end, .cancel:
                active = false
            case .spaceChanged:
                spaceChanged = true
            }
        }
    }

    /// One long roll at 0.7× (42 events of 1.5 lines, 50 ms apart): the first swipe ends at
    /// a full Space with no speed once the wheel went a quarter of a Space past it; nothing
    /// begins until the Space changed; then the next begins with the travel kept meanwhile
    /// (a Space at most). Three swipes or more, each begun after a Space change, none while
    /// another runs.
    func testOneLongRollChainsSwipes_eachBegunOnceTheSpaceChanged() throws {
        Options.shared.thumbWheel = ThumbWheelSettings(function: .desktops, speed: 0.7, followsWheel: true)
        changeTheSpace(after: 0.2)
        for index in 0..<42 { try turn(at: Double(index) * 0.05, lines: -1, fixed: -1.5) }
        rig.advance(to: 505)

        let firstEnd = try XCTUnwrap(dock.calls.firstIndex(of: .end(0)))
        XCTAssertEqual(dock.calls[..<firstEnd].filter { $0 == .begin }.count, 1)
        guard case .update(let full)? = dock.calls[..<firstEnd].last else { return XCTFail("\(dock.calls)") }
        XCTAssertEqual(full, Self.space, accuracy: 1e-9, "ended at a full Space")
        // 0.98 of a Space at event 9, 1.5 units past it at event 11 (0.5 s): ended in its frame.
        XCTAssertEqual(dock.times.dropFirst(firstEnd).first ?? 0, 0.5, accuracy: 1.0 / 60 + 1e-6)
        XCTAssertEqual(dock.calls.dropFirst(firstEnd + 1).first, .spaceChanged, "nothing until the Space changed")

        let begins = dock.calls.indices.filter { dock.calls[$0] == .begin }
        guard begins.count >= 3 else { return XCTFail("\(dock.calls)") }
        guard case .update(let first)? = dock.calls.dropFirst(begins[1] + 1).first else { return XCTFail("\(dock.calls)") }
        XCTAssertGreaterThan(first, 0.5 * 2 * 0.7 / 6 * Self.space, "begins with the travel kept: more than two events' worth (eased)")
        XCTAssertLessThanOrEqual(first, Self.space)
        assertEveryBeginFollowsASpaceChange()
        XCTAssertFalse(dock.calls.contains(.cancel))
        XCTAssertTrue(rig.performed.isEmpty)

        let roll = try XCTUnwrap(rig.lines.last)
        XCTAssertEqual(rig.lines.count, 1, "one roll")
        XCTAssertEqual(roll.swipes.count, begins.count)
        XCTAssertEqual(roll.swipes.dropLast().map(\.ending), Array(repeating: .chained, count: begins.count - 1))
        XCTAssertTrue(roll.swipes.dropLast().allSatisfy { ($0.spaceChangedAfter ?? 0) > 0.19 && $0.expectsSwitch }, "\(roll.swipes)")
        XCTAssertEqual(roll.pendingSwipes, 0)
    }

    /// A stroke that reaches a full Space and stops: it ends 150 ms after its last event, not
    /// only at the rest.
    func testAStrokeAtAFullSpaceEndsWhenTheWheelStopsFor150Milliseconds() throws {
        for index in 0..<7 { try turn(at: Double(index) * 0.05) }
        rig.advance(to: 500.3 + 0.149)
        XCTAssertTrue(dock.terminals.isEmpty)
        rig.advance(to: 500.3 + 0.15)
        XCTAssertEqual(dock.terminals, [.end(0)])
        XCTAssertEqual(try XCTUnwrap(dock.updates.last), Self.space, accuracy: 1e-9)
        rig.advance(to: 503)
        XCTAssertEqual(rig.lines.last?.swipes.map(\.ending), [.fullStop])
    }

    /// A stroke that goes part of the way ends at the rest (0.45 s), as before.
    func testAPartialStrokeEndsAtTheRestAsBefore() throws {
        Options.shared.thumbWheel = ThumbWheelSettings(function: .desktops, speed: 0.9, followsWheel: true)
        for index in 0..<4 { try turn(at: Double(index) * 0.05) }
        rig.advance(to: 500.15 + 0.449)
        XCTAssertTrue(dock.terminals.isEmpty)
        rig.advance(to: 500.15 + 0.45)
        XCTAssertEqual(dock.terminals, [.end(0)])
        XCTAssertEqual(try XCTUnwrap(dock.updates.last), 0.6 * Self.space, accuracy: 1e-9)
    }

    /// No Space change within 0.5 s of an end (the last desktop: the Dock let the swipe
    /// bounce back): no swipe begins that way again in the stroke; turning the other way
    /// begins one; the next stroke begins as usual.
    func testNoSpaceChangeInTime_noFurtherSwipeThatWay_theOtherWayBegins() throws {
        var time = 0.0
        while time < 1.2 { try turn(at: time); time += 0.05 }
        rig.advance(to: 501.24)
        XCTAssertEqual(dock.calls.filter { $0 == .begin }.count, 1, "rolled on past the timeout: nothing began")
        XCTAssertEqual(dock.terminals, [.end(0)])
        try turn(at: 1.25, lines: 2)
        try turn(at: 1.3, lines: 2)
        rig.advance(to: 501.32)
        XCTAssertEqual(dock.calls.filter { $0 == .begin }.count, 2, "the other way begins")
        XCTAssertLessThan(try XCTUnwrap(dock.updates.last), 0)
        rig.advance(to: 503)
        try turn(at: 3)
        rig.advance(to: 505)
        XCTAssertEqual(dock.calls.filter { $0 == .begin }.count, 3, "the next stroke begins as usual")
        XCTAssertGreaterThan(try XCTUnwrap(dock.updates.last), 0)
        let first = try XCTUnwrap(rig.lines.first?.swipes.first)
        XCTAssertEqual(first.ending, .chained)
        XCTAssertNil(first.spaceChangedAfter, "no change")
    }

    private var beginCount: Int { return dock.calls.filter { $0 == .begin }.count }

    /// When each swipe ended (seconds after the rig's start).
    private var endTimes: [Double] {
        return dock.calls.indices.filter { if case .end = dock.calls[$0] { return true } else { return false } }.map { dock.times[$0] }
    }

    /// The first update after the `index`th begin (its direction: positive toward "next").
    private func firstUpdate(afterBegin index: Int) throws -> Double {
        let begins = dock.calls.indices.filter { dock.calls[$0] == .begin }
        guard index < begins.count, case .update(let progress)? = dock.calls.dropFirst(begins[index] + 1).first else {
            XCTFail("no update after begin \(index): \(dock.calls)")
            return .nan
        }
        return progress
    }

    /// Two events at the gate after a chained end, then the wheel stops; the Space changes
    /// 200 ms later: a third of a Space could not switch a desktop, nothing begins.
    func testLittleTravelKeptAtTheGate_theWheelStopped_beginsNothing() throws {
        for index in 0..<8 { try turn(at: Double(index) * 0.05) }
        rig.advance(to: 500.38)
        let end = try XCTUnwrap(endTimes.first, "chained in the frame of the eighth event")
        try turn(at: end + 0.02)
        try turn(at: end + 0.04)
        rig.advance(to: 500 + end + 0.24)
        rig.engine.follower.spaceDidChange()
        rig.advance(to: 503)
        XCTAssertEqual(beginCount, 1, "\(dock.calls)")
        XCTAssertFalse(rig.hasPendingWork)
    }

    /// A Space of travel kept at the gate, the wheel stopped, the Space changes 400 ms later
    /// (just before the stroke's rest): the swipe begins and is shown sliding, several
    /// frames, and ends at the full Space 150 ms after its begin, not in the same turn.
    func testAFullSpaceKeptAtTheGate_theWheelStopped_slidesBeforeItEnds() throws {
        for index in 0..<8 { try turn(at: Double(index) * 0.05) }
        rig.advance(to: 500.38)
        let end = try XCTUnwrap(endTimes.first, "chained in the frame of the eighth event")
        for offset in [0.01, 0.02, 0.03] { try turn(at: end + offset, lines: -12) }
        rig.advance(to: 500 + end + 0.43)
        rig.engine.follower.spaceDidChange()
        rig.advance(to: 505)
        let begins = dock.calls.indices.filter { dock.calls[$0] == .begin }
        XCTAssertEqual(begins.count, 2, "\(dock.calls)")
        let secondEnd = try XCTUnwrap(dock.calls.indices.first { $0 > begins[1] && dock.calls[$0] == .end(0) })
        let began = dock.times[begins[1]]
        XCTAssertEqual(began, end + 0.43, accuracy: 1e-6)
        XCTAssertGreaterThanOrEqual(dock.times[secondEnd] - began, 0.15 - 1e-6)
        let slide = dock.calls[(begins[1] + 1)..<secondEnd].compactMap { call -> Double? in
            if case .update(let progress) = call { return progress } else { return nil }
        }
        XCTAssertGreaterThanOrEqual(slide.count, 4, "several frames: \(slide)")
        XCTAssertEqual(slide, slide.sorted())
        XCTAssertEqual(try XCTUnwrap(slide.last), Self.space, accuracy: 1e-9)
        XCTAssertEqual(rig.lines.first?.swipes.map(\.ending).prefix(2), [.chained, .fullStop])
    }

    /// The main queue was busy all through a short stroke (its first frame never ran) and the
    /// next event comes after the rest: the stroke is over, and no swipe begins and ends at
    /// once inside the tap callback; the new stroke begins its own.
    func testAStrokeWhoseFrameNeverRanBeforeItsRest_beginsNoSwipe() throws {
        try turn(at: 0, busy: true)
        try turn(at: 0.6, busy: true)
        XCTAssertTrue(dock.calls.isEmpty, "\(dock.calls)")
        rig.advance(to: 502)
        XCTAssertEqual(beginCount, 1)
        XCTAssertEqual(try XCTUnwrap(dock.updates.last), Self.space / 6, accuracy: 1e-9, "the new stroke's one event")
    }

    /// The main queue was busy: an event finds that the stroke rested, or that a gate timed
    /// out, before their looks ran. The endings that brings are told to the roll's line after
    /// the callback, on the main queue, in order (the setup fails one told inside it).
    func testWhatAnEventEndsIsToldAfterTheTapCallback() throws {
        try turn(at: 0)
        try turn(at: 0.05)
        rig.advance(to: 500.1)
        try turn(at: 0.6, busy: true)
        XCTAssertEqual(dock.terminals, [.end(0)], "the stroke ended in the callback")
        rig.advance(to: 503)
        XCTAssertEqual(rig.lines.first?.swipes.map(ScrollSystemLog.swipeMessage), ["0.33 ended", "0.17 ended"], "the new stroke's too")

        // A swipe that waits as late, and a newer gate that times out while the queue is busy.
        dock.calls = []
        var time = 5.0
        while time < 5.9 { try turn(at: time); time += 0.05 }
        while time < 6.3 { try turn(at: time, lines: 2); time += 0.05 }
        rig.advance(to: 500 + time)
        XCTAssertEqual(endTimes.count, 2)
        try turn(at: 7, lines: 2, busy: true)
        rig.advance(to: 510)
        // (The roll of the event at 7 s is another one: its line does not wait for these.)
        let line = try XCTUnwrap(rig.lines.first { $0.swipes.count == 2 && $0.events > 10 }, "\(rig.lines.map(ScrollSystemLog.followMessage))")
        XCTAssertTrue(ScrollSystemLog.followMessage(for: line).hasPrefix("swipes 1.00 chained no change, 1.00 chained no change"),
                      ScrollSystemLog.followMessage(for: line))
        XCTAssertTrue(rig.lines.contains { ScrollSystemLog.followMessage(for: $0).hasPrefix("swipes 0.17 ended") }, "the roll of the event that found them")
    }

    /// The Space changes 0.55 s after a chained end, after the gate's timeout, while the
    /// stroke rolls on that way: the way is no longer barred, the next swipe begins that
    /// way, and the line says the change came late.
    func testALateSpaceChangeInTheStroke_theNextSwipeBeginsThatWay() throws {
        var time = 0.0
        while time < 0.8 { try turn(at: time); time += 0.05 }
        let end = try XCTUnwrap(endTimes.first)
        var changed = false
        while time < 1.3 {
            if !changed, time > end + 0.55 {
                rig.advance(to: 500 + end + 0.55)
                XCTAssertEqual(beginCount, 1, "timed out: nothing began that way")
                rig.engine.follower.spaceDidChange()
                changed = true
            }
            try turn(at: time)
            time += 0.05
        }
        rig.advance(to: 506)
        XCTAssertTrue(changed)
        XCTAssertGreaterThanOrEqual(beginCount, 2, "\(dock.calls)")
        XCTAssertGreaterThan(try firstUpdate(afterBegin: 1), 0, "that way")
        let line = try XCTUnwrap(rig.lines.first)
        XCTAssertEqual(line.swipes.first?.late, true)
        XCTAssertEqual(line.swipes.first?.spaceChangedAfter ?? 0, 0.55, accuracy: 1e-6)
        XCTAssertTrue(ScrollSystemLog.followMessage(for: line).hasPrefix("swipes 1.00 chained late +550 ms, "),
                      ScrollSystemLog.followMessage(for: line))
    }

    /// An end at the rest (0.65 of a desktop, which macOS settles without speed) waits a
    /// second for its Space change: a change 0.8 s later opens the gate, and the stroke that
    /// waited at it begins its swipe.
    func testAnEndAtTheRestWaitsASecondForItsSpaceChange() throws {
        Options.shared.thumbWheel = ThumbWheelSettings(function: .desktops, speed: 0.65, followsWheel: true)
        for index in 0..<6 { try turn(at: Double(index) * 0.05) }
        rig.advance(to: 500.25 + 0.45)
        XCTAssertEqual(dock.terminals, [.end(0)])
        XCTAssertEqual(try XCTUnwrap(dock.updates.last), 0.65 * Self.space, accuracy: 1e-9)
        let end = try XCTUnwrap(endTimes.first)
        var time = end + 0.3
        while time < end + 0.8 - 1e-6 { try turn(at: time); time += 0.05 }
        rig.advance(to: 500 + end + 0.8)
        XCTAssertEqual(beginCount, 1, "waits at the gate")
        rig.engine.follower.spaceDidChange()
        try turn(at: end + 0.8)
        rig.advance(to: 500 + end + 0.85)
        XCTAssertEqual(beginCount, 2, "the gate opened: no timeout before it")
        rig.advance(to: 506)
        let swipe = try XCTUnwrap(rig.lines.first?.swipes.first)
        XCTAssertFalse(swipe.late)
        XCTAssertEqual(ScrollSystemLog.swipeMessage(swipe), "0.65 ended +800 ms")
    }

    /// The stroke chains right where macOS does not switch (no change in time): right is
    /// barred. It turns left, that swipe switches; once the Space changed right begins again
    /// in the same stroke. The line lists the swipes in order.
    func testABarredWayBeginsAgainOnceTheSpaceChangedTheOtherWay() throws {
        var time = 0.0
        while time < 0.9 { try turn(at: time); time += 0.05 }
        XCTAssertEqual(beginCount, 1)
        while time < 1.3 { try turn(at: time, lines: 2); time += 0.05 }
        rig.advance(to: 500 + time)
        XCTAssertEqual(beginCount, 2)
        XCTAssertLessThan(try firstUpdate(afterBegin: 1), 0)
        let leftEnd = try XCTUnwrap(endTimes.dropFirst().first)
        rig.advance(to: 500 + leftEnd + 0.2)
        rig.engine.follower.spaceDidChange()
        for offset in [0.25, 0.3, 0.35, 0.4] { try turn(at: leftEnd + offset) }
        rig.advance(to: 508)
        XCTAssertEqual(beginCount, 3, "\(dock.calls)")
        XCTAssertGreaterThan(try firstUpdate(afterBegin: 2), 0, "right again")
        let line = try XCTUnwrap(rig.lines.first)
        XCTAssertTrue(ScrollSystemLog.followMessage(for: line).hasPrefix("swipes 1.00 chained no change, 1.00 chained +200 ms, "),
                      ScrollSystemLog.followMessage(for: line))
    }

    /// A change while a swipe waits as late and a newer one waits at its gate is the newer
    /// swipe's, however soon after its end (80 ms: macOS can be that quick): the gate opens
    /// and the stroke goes on; the older swipe is logged "no change". A second change, with
    /// no gate closed, is the older swipe's, late.
    func testAChangeWhileANewerGateIsClosedIsTheNewerSwipes() throws {
        for secondChange in [false, true] {
            let start = secondChange ? 10.0 : 0.0
            dock.calls = []
            for index in 0..<18 { try turn(at: start + Double(index) * 0.05) }
            for index in 18..<26 { try turn(at: start + Double(index) * 0.05, lines: 2) }
            rig.advance(to: 500 + start + 1.3)
            let rightEnd = try XCTUnwrap(endTimes.first)
            let leftEnd = try XCTUnwrap(endTimes.dropFirst().first)
            rig.advance(to: 500 + leftEnd + 0.08)
            rig.engine.follower.spaceDidChange()
            XCTAssertEqual(rig.engine.follower.state, .following, "the newer gate opened")
            var older = "no change"
            if secondChange {
                rig.advance(to: 500 + leftEnd + 0.3)
                rig.engine.follower.spaceDidChange()
                older = "late +\(Int(((leftEnd + 0.3 - rightEnd) * 1000).rounded())) ms"
            }
            rig.advance(to: 506 + start)
            let line = try XCTUnwrap(rig.lines.last)
            XCTAssertTrue(ScrollSystemLog.followMessage(for: line).hasPrefix("swipes 1.00 chained \(older), 1.00 chained +80 ms"),
                          ScrollSystemLog.followMessage(for: line))
        }
    }

    /// A new stroke soon after an end where a switch is expected waits for the Space change,
    /// then begins with its travel; without a change it waits for the timeout and begins
    /// with its travel then (it is not barred: the swipe ended in the stroke before).
    func testANewStrokeSoonAfterASwitchWaitsForTheSpaceChange() throws {
        for index in 0..<4 { try turn(at: Double(index) * 0.05) }
        rig.advance(to: 500.6)
        XCTAssertEqual(dock.terminals, [.end(0)], "0.67 of a desktop, at the rest")
        for time in [0.8, 0.85, 0.9] { try turn(at: time) }
        rig.advance(to: 500.95)
        XCTAssertEqual(dock.calls.filter { $0 == .begin }.count, 1, "waits at the gate")
        rig.engine.follower.spaceDidChange()
        rig.advance(to: 500.95)
        XCTAssertEqual(dock.calls.filter { $0 == .begin }.count, 2)
        guard case .update(let first)? = dock.calls.last else { return XCTFail("\(dock.calls)") }
        XCTAssertEqual(first, 0.5 * 3 / 6 * Self.space, accuracy: 1e-9, "the three events kept, eased")
        rig.advance(to: 504)
        let swipes = rig.lines.flatMap(\.swipes)
        XCTAssertEqual(swipes.first?.spaceChangedAfter ?? 0, 0.35, accuracy: 1e-6, "the first roll's line waited for it")
        XCTAssertEqual(rig.lines.count, 2)

        // No change this time: a second after the end at the rest the gate times out.
        dock.calls = []
        for index in 0..<4 { try turn(at: 5 + Double(index) * 0.05) }
        var time = 5.8
        while time < 6.3 { try turn(at: time); time += 0.05 }
        let end = try XCTUnwrap(endTimes.first)
        rig.advance(to: 500 + end + 0.999)
        XCTAssertEqual(beginCount, 1, "waits at the gate")
        rig.advance(to: 500 + end + 1)
        XCTAssertEqual(beginCount, 2, "the travel kept begins at the timeout")
        XCTAssertGreaterThan(try firstUpdate(afterBegin: 1), 0, "that way")
        rig.advance(to: 509)
        try turn(at: 9)
        rig.advance(to: 511)
        XCTAssertEqual(beginCount, 3, "the next stroke begins as usual")
    }

    /// A gesture begins its swipe while the stroke waits at the gate: the stroke waits for
    /// its rest, never cancels the gesture's swipe and sends it nothing.
    func testAGestureSwipeDuringTheGate_theStrokeWaitsAndLeavesItAlone() throws {
        var time = 0.0
        while time < 0.4 { try turn(at: time); time += 0.05 }
        rig.advance(to: 500.4)
        XCTAssertEqual(dock.terminals, [.end(0)])
        synthesizer.begin(axis: .horizontal)
        synthesizer.update(progress: 0.3)
        let gestures = dock.calls
        while time < 0.9 {
            if abs(time - 0.5) < 1e-9 { rig.engine.follower.spaceDidChange() }
            try turn(at: time)
            time += 0.05
        }
        rig.advance(to: 500.9)
        XCTAssertEqual(dock.calls, gestures, "nothing sent to the gesture's swipe")
        XCTAssertTrue(synthesizer.isActive)
        synthesizer.end(velocity: 0)
        let afterGesture = dock.calls
        while time < 1.2 { try turn(at: time); time += 0.05 }
        rig.advance(to: 503)
        XCTAssertEqual(dock.calls, afterGesture, "the stroke waits for its rest")
        XCTAssertEqual(rig.lines.last?.strokesWaited, 1)
    }

    /// A stroke of chained swipes longer than the swipe's 10 s limit is not cut off: each
    /// swipe has its own start.
    func testALongStrokeOfChainedSwipesIsNotCutOffAfter10Seconds() throws {
        changeTheSpace(after: 0.2)
        for index in 0..<230 { try turn(at: Double(index) * 0.05) }
        rig.advance(to: 520)
        XCTAssertFalse(dock.calls.contains(.cancel), "no swipe cancelled")
        let beginTimes = dock.calls.indices.filter { dock.calls[$0] == .begin }.map { dock.times[$0] }
        XCTAssertGreaterThan(try XCTUnwrap(beginTimes.last), 10.5)
        XCTAssertGreaterThanOrEqual(beginTimes.count, 15)
        assertEveryBeginFollowsASpaceChange()
        let roll = try XCTUnwrap(rig.lines.last)
        XCTAssertEqual(roll.swipes.count, ScrollSystemLog.ThumbWheelRoll.listedSwipes)
        XCTAssertEqual(roll.swipeTally.total, beginTimes.count)
        XCTAssertEqual(roll.unlistedSwipes.total, beginTimes.count - 8)
    }

    /// How long each swipe was open: from its begin to its end or cancel (seconds).
    private var swipeLifetimes: [Double] {
        var lifetimes: [Double] = []
        var began: Double?
        for (index, call) in dock.calls.enumerated() {
            switch call {
            case .begin:
                began = dock.times[index]
            case .end, .cancel:
                if let start = began { lifetimes.append(dock.times[index] - start) }
                began = nil
            case .update, .spaceChanged:
                break
            }
        }
        return lifetimes
    }

    /// A hard roll at 0.7× (40 events of 12 lines, 16 ms apart), the Space changing 250 ms
    /// after each end: every swipe after the first begins with the travel kept at the gate,
    /// half a Space or more on, and the wheel is past the chain point a frame later. None is
    /// ended sooner than 150 ms after its begin: each is shown sliding.
    func testAChainedSwipeIsShownFor150Milliseconds_aHardRoll() throws {
        Options.shared.thumbWheel = ThumbWheelSettings(function: .desktops, speed: 0.7, followsWheel: true)
        changeTheSpace(after: 0.25)
        for index in 0..<40 { try turn(at: Double(index) * 0.016, lines: -12) }
        rig.advance(to: 505)
        XCTAssertGreaterThanOrEqual(beginCount, 3, "\(dock.calls)")
        let lifetimes = swipeLifetimes
        XCTAssertEqual(lifetimes.count, beginCount)
        XCTAssertTrue(lifetimes.allSatisfy { $0 >= ThumbWheelTuning.followFullStopRest - 1e-6 }, "\(lifetimes)")
        assertEveryBeginFollowsASpaceChange()
        XCTAssertEqual(rig.lines.first?.swipes.first?.ending, .chained)
    }

    /// At 1.85×, two small ticks let in by one hard event (−0.10, −0.10, then −12 lines):
    /// a full Space and past the chain point in one frame. The swipe is not begun and ended
    /// in one turn of the main queue: it ends 150 ms after its begin.
    func testAChainedSwipeIsShownFor150Milliseconds_oneHardEvent() throws {
        Options.shared.thumbWheel = ThumbWheelSettings(function: .desktops, speed: 1.85, followsWheel: true)
        try turn(at: 0, lines: -1, fixed: -0.1)
        try turn(at: 0.03, lines: -1, fixed: -0.1)
        try turn(at: 0.05, lines: -12)
        rig.advance(to: 500.05)
        XCTAssertEqual(beginCount, 1)
        XCTAssertTrue(dock.terminals.isEmpty, "begun and ended in one turn: \(dock.calls)")
        rig.advance(to: 500.05 + 0.149)
        XCTAssertTrue(dock.terminals.isEmpty, "\(dock.calls)")
        rig.advance(to: 500.05 + 0.15 + 1.0 / 60)
        XCTAssertEqual(dock.terminals, [.end(0)])
        XCTAssertEqual(try XCTUnwrap(dock.updates.last), Self.space, accuracy: 1e-9)
        XCTAssertTrue(swipeLifetimes.allSatisfy { $0 >= ThumbWheelTuning.followFullStopRest - 1e-6 }, "\(swipeLifetimes)")
    }

    /// The first roll of the two tests below, from `start` on: 5 events of 1 line 80 ms
    /// apart at 0.7× put the desktop 0.58 of the way; it ends at the rest, a switch is
    /// expected, and no Space change comes (the last desktop that way, or macOS let it slide
    /// back). Returns when it ended.
    private func rollToSixTenthsAndRest(from start: Double = 0) throws -> Double {
        Options.shared.thumbWheel = ThumbWheelSettings(function: .desktops, speed: 0.7, followsWheel: true)
        dock.calls = []
        for index in 0..<5 { try turn(at: start + Double(index) * 0.08, lines: -1) }
        rig.advance(to: 500 + start + 0.32 + 0.45)
        XCTAssertEqual(dock.terminals, [.end(0)], "0.58 of a desktop, at the rest")
        XCTAssertEqual(try XCTUnwrap(dock.updates.last), 3.5 / 6 * Self.space, accuracy: 1e-9)
        return try XCTUnwrap(endTimes.first)
    }

    /// The same way again from 200 ms after that end (14 events, 1.1 s of rolling): the new
    /// stroke waits at the gate, and when no Space change came in time it is not barred
    /// (the stroke the swipe ended in was): the travel it kept begins a swipe at the
    /// timeout, a second after the end.
    func testAnEndWithNoSpaceChangeBarsOnlyItsOwnStroke() throws {
        let end = try rollToSixTenthsAndRest()
        for index in 0..<14 {
            if index == 10 { XCTAssertEqual(beginCount, 1, "waits at the gate") }
            try turn(at: end + 0.2 + Double(index) * 0.08, lines: -1)
        }
        rig.advance(to: 506)
        let begins = dock.calls.indices.filter { dock.calls[$0] == .begin }.map { dock.times[$0] }
        guard begins.count >= 2 else { return XCTFail("nothing began in 1.1 s of rolling: \(dock.calls)") }
        XCTAssertEqual(begins[1], end + 1, accuracy: 1e-6, "at the timeout")
        XCTAssertGreaterThan(try firstUpdate(afterBegin: 1), 0, "the same way")
        XCTAssertTrue(rig.lines.contains { $0.swipes.first.map(ScrollSystemLog.swipeMessage) == "0.58 ended no change" },
                      "\(rig.lines.map(ScrollSystemLog.followMessage))")
    }

    /// On the last desktop: 6 events of 4 lines back (0.87 of a Space) after that end, then
    /// the wheel stops. The stroke waits at the gate past its own rest, the travel it kept
    /// begins the swipe back at the timeout, and that swipe is shown sliding for 150 ms
    /// before it ends where the wheel left it. Back from 250 ms after the end: the stroke's
    /// rest falls on the timeout; from 150 ms: before it.
    func testTravelKeptAtAGateSurvivesTheRestUntilTheGateOpens() throws {
        for (start, delay) in [(0.0, 0.25), (10.0, 0.15)] {
            let end = try rollToSixTenthsAndRest(from: start)
            for index in 0..<6 { try turn(at: end + delay + Double(index) * 0.06, lines: 4) }
            rig.advance(to: 500 + end + 0.999)
            XCTAssertEqual(beginCount, 1, "waits at the gate")
            XCTAssertEqual(rig.engine.follower.state, .gated, "past its own rest (back after \(delay) s)")
            rig.advance(to: 500 + end + 1)
            guard beginCount == 2 else {
                XCTFail("nothing began at the timeout (back after \(delay) s): \(dock.calls)")
                continue
            }
            XCTAssertLessThan(try firstUpdate(afterBegin: 1), 0, "back")
            rig.advance(to: 500 + end + 1.149)
            XCTAssertEqual(dock.terminals.count, 1, "shown sliding")
            rig.advance(to: 500 + end + 1.15)
            XCTAssertEqual(dock.terminals, [.end(0), .end(0)])
            XCTAssertEqual(try XCTUnwrap(dock.updates.last), -5.25 / 6 * Self.space, accuracy: 1e-9, "where the wheel left it")
        }
    }

    /// One desktop and a little more: 11 events of 4 lines 60 ms apart at 0.7× (9.6 units).
    /// The swipe chains at the ninth event, the last two events' travel (0.29 of a Space) is
    /// kept at the gate. When the Space changes it begins nothing: a swipe begun with it
    /// could only peek in and slide back. It waits: an event later in the stroke begins the
    /// swipe with it (three events' travel, eased).
    func testLittleTravelKeptAtTheGateWaitsForTheNextEvent() throws {
        Options.shared.thumbWheel = ThumbWheelSettings(function: .desktops, speed: 0.7, followsWheel: true)
        for index in 0..<11 { try turn(at: Double(index) * 0.06, lines: -4) }
        let end = try XCTUnwrap(endTimes.first)
        XCTAssertEqual(end, 0.48, accuracy: 1.0 / 60 + 1e-6, "chained at the ninth event")
        rig.advance(to: 500 + end + 0.25)
        rig.engine.follower.spaceDidChange()
        rig.advance(to: 500.79)
        XCTAssertEqual(beginCount, 1, "0.29 of a Space begins nothing: \(dock.calls)")
        XCTAssertEqual(rig.engine.follower.state, .following, "the stroke goes on")

        try turn(at: 0.8, lines: -4)
        rig.advance(to: 500.8)
        XCTAssertEqual(beginCount, 2, "the next event begins the swipe")
        guard case .update(let first)? = dock.calls.last else { return XCTFail("\(dock.calls)") }
        XCTAssertEqual(first, 0.5 * 3 * 0.875 / 6 * Self.space, accuracy: 1e-9, "with the travel kept")
        rig.advance(to: 503)
        XCTAssertEqual(dock.terminals, [.end(0), .end(0)])
        XCTAssertFalse(rig.hasPendingWork)
    }

    /// A tick the stray-tick filter holds keeps the stroke alive. After two events (a third
    /// of a Space) the wheel turns slowly back, a tick of 0.10 line every 240 ms: the filter
    /// holds every one (too far apart to confirm each other), so none moves the desktop.
    /// But the wheel moves: the stroke rests 0.45 s after the last tick, not before.
    func testAHeldTickKeepsTheStrokeAlive() throws {
        try turn(at: 0)
        try turn(at: 0.05)
        for time in [0.3, 0.54, 0.78, 1.02] { try turn(at: time, lines: 1, fixed: 0.1) }
        rig.advance(to: 501.02 + 0.449)
        XCTAssertTrue(dock.terminals.isEmpty, "rested while the wheel moved: \(dock.calls)")
        XCTAssertEqual(beginCount, 1)
        XCTAssertEqual(try XCTUnwrap(dock.updates.last), 2 * Self.space / 6, accuracy: 1e-9, "a held tick moves nothing")
        rig.advance(to: 501.02 + 0.45)
        XCTAssertEqual(dock.terminals, [.end(0)], "0.45 s after the last tick")
        rig.advance(to: 505)
        XCTAssertEqual(rig.lines.flatMap(\.swipes).map(ScrollSystemLog.swipeMessage), ["0.33 ended"])
        XCTAssertEqual(rig.lines.map(\.ticksHeld), [4])
    }

    /// A follower of its own on the rig's clock and queue, with the fake Dock's swipe, fed
    /// by hand (the engine's own stays idle).
    private func bareFollower() -> ThumbWheelFollower {
        let follower = ThumbWheelFollower(spaceChanges: nil)
        follower.synthesizer = synthesizer
        follower.screen = rig.engine.follower.screen
        follower.schedule = rig.engine.schedule
        follower.clock = rig.engine.clock
        return follower
    }

    /// `touch` moves the rest of a stroke under way and nothing else: it begins no stroke,
    /// it does not put off the full stop of a swipe at a full Space, and a stroke whose rest
    /// has passed (the main queue was busy: its look has not come) is not brought back.
    func testATouchMovesTheRestAndNothingElse() {
        let follower = bareFollower()
        follower.touch(at: 500, seenAt: 500)
        XCTAssertEqual(follower.state, .idle, "no stroke begins with a held tick")
        rig.advance(to: 501)
        XCTAssertTrue(dock.calls.isEmpty)
        XCTAssertFalse(rig.hasPendingWork)

        // At a full Space: the full stop comes 150 ms after the last event that moved it.
        for index in 0..<6 {
            rig.advance(to: 502 + Double(index) * 0.05)
            _ = follower.add(1, at: rig.now, seenAt: rig.now)
        }
        rig.advance(to: 502.35)
        follower.touch(at: 502.35, seenAt: 502.35)
        rig.advance(to: 502.4)
        XCTAssertEqual(dock.terminals, [.end(0)], "the full stop, 150 ms after the sixth event")
        follower.cancel()

        // The rest has passed while the main queue was busy: the stroke is over.
        dock.calls = []
        rig.advance(to: 510)
        _ = follower.add(1, at: 510, seenAt: 510)
        rig.advance(to: 510.1)
        rig.now = 510.6
        follower.touch(at: 510.6, seenAt: 510.6)
        rig.advance(to: 510.6)
        XCTAssertEqual(dock.terminals, [.end(0)], "ended by its rest, not kept alive")
        XCTAssertEqual(follower.state, .idle)
        follower.cancel()
    }

    /// A swipe that waits as late holds back only the later endings of its own roll (their
    /// order in its line): a later roll's swipe is told when it ended, not when the older
    /// swipe's 1.5 s are over.
    func testALaterRollsEndingDoesNotWaitBehindAnOlderLateSwipe() {
        let follower = bareFollower()
        var told: [(tag: Int, swipe: String, at: Double)] = []
        follower.onSwipeEnd = { [unowned self] tag, swipe in
            told.append((tag, ScrollSystemLog.swipeMessage(swipe), self.rig.now - 500))
        }
        // Roll 1: chained at about 0.35 s, no Space change: it waits as late until about 2.35 s.
        for index in 0..<8 {
            rig.advance(to: 500 + Double(index) * 0.05)
            _ = follower.add(1, at: rig.now, seenAt: rig.now, tag: 1)
        }
        rig.advance(to: 501.4)
        XCTAssertEqual(follower.state, .idle)
        XCTAssertTrue(told.isEmpty, "waits for a late change: \(told)")
        // Roll 2: a third of a Space the other way, ended at its rest (1.9 s).
        for time in [501.4, 501.45] {
            rig.advance(to: time)
            _ = follower.add(-1, at: rig.now, seenAt: rig.now, tag: 2)
        }
        rig.advance(to: 502)
        XCTAssertEqual(told.map(\.tag), [2], "\(told)")
        XCTAssertEqual(told.first?.swipe, "0.33 ended")
        XCTAssertEqual(told.first?.at ?? 0, 1.9, accuracy: 1e-6)
        rig.advance(to: 503)
        XCTAssertEqual(told.map(\.tag), [2, 1])
        XCTAssertEqual(told.last?.swipe, "1.00 chained no change")
        follower.cancel()
    }

    /// A stop while the stroke waits at the gate: nothing scheduled runs, nothing is sent
    /// later, a Space change afterwards begins nothing, and the line says so.
    func testAStopAtTheGateRunsNothingLater() throws {
        var time = 0.0
        while time < 0.5 { try turn(at: time); time += 0.05 }
        rig.advance(to: 500.5)
        XCTAssertEqual(dock.terminals, [.end(0)])
        rig.engine.reset()
        let afterStop = dock.calls
        rig.advance(to: 505)
        rig.engine.follower.spaceDidChange()
        rig.advance(to: 506)
        XCTAssertEqual(dock.calls, afterStop)
        XCTAssertEqual(rig.engine.follower.state, .idle)
        XCTAssertFalse(rig.hasPendingWork)
        XCTAssertEqual(rig.lines.flatMap(\.swipes).map(ScrollSystemLog.swipeMessage), ["1.00 chained stopped"],
                       "stopped, not \"no change\": the wait for the Space was cut short")

        // A swipe that waits as late, stopped as well.
        var late = 10.0
        while late < 11 { try turn(at: late); late += 0.05 }
        rig.advance(to: 511.1)
        XCTAssertEqual(rig.engine.follower.state, .following, "timed out, the stroke rolls on")
        rig.engine.reset()
        rig.advance(to: 515)
        XCTAssertEqual(rig.lines.last?.swipes.first.map(ScrollSystemLog.swipeMessage), "1.00 chained stopped")
        XCTAssertFalse(rig.hasPendingWork)
    }

    /// The follower hears of a Space change from the workspace's notification, on the main
    /// queue (here a center of the test's own).
    func testTheSpaceChangeComesFromTheWorkspaceNotification() throws {
        let center = NotificationCenter()
        let follower = ThumbWheelFollower(spaceChanges: center)
        follower.synthesizer = synthesizer
        follower.screen = rig.engine.follower.screen
        follower.schedule = rig.engine.schedule
        follower.clock = rig.engine.clock
        var time = 0.0
        while time < 0.4 {
            rig.advance(to: 500 + time)
            _ = follower.add(1, at: 500 + time, seenAt: 500 + time)
            time += 0.05
        }
        rig.advance(to: 500.4)
        XCTAssertEqual(follower.state, .gated)
        center.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        let deadline = Date().addingTimeInterval(2)
        while follower.state == .gated, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertEqual(follower.state, .following)
        follower.cancel()
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
