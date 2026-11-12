import XCTest
@testable import Scrollio_Debug

/// ScrollCore.enable() when an event tap cannot be created: the core must roll back to
/// "not active". It used to stay active without taps, so every later enable() returned
/// early and scrolling stayed unhandled until the app was restarted.
///
/// The taps come from an injected factory that throws, so no event tap is created here.
final class ScrollCoreEnableTests: XCTestCase {

    private var factoryCalls: [CGEventTapOptions] = []

    override func setUp() {
        super.setUp()
        factoryCalls = []
    }

    private func makeCore(failing error: Interceptor.InterceptorError) -> ScrollCore {
        let core = ScrollCore()
        core.makeInterceptor = { [unowned self] _, _, options in
            self.factoryCalls.append(options)
            throw error
        }
        return core
    }

    func testEnableRollsBackWhenTheTapCannotBeCreated() {
        let core = makeCore(failing: .eventTapCreationFailed)

        core.enable()

        XCTAssertFalse(core.isActive, "a core without taps must not report itself as active")
        XCTAssertNil(core.scrollEventInterceptor)
        XCTAssertNil(core.hotkeyEventInterceptor)
        XCTAssertNil(core.mouseEventInterceptor)
        XCTAssertEqual(factoryCalls, [.defaultTap], "the first failure ends the attempt")
    }

    func testEnableRollsBackWhenTheTapCannotBeStarted() {
        let core = makeCore(failing: .eventTapEnableFailed)

        core.enable()

        XCTAssertFalse(core.isActive)
        XCTAssertNil(core.scrollEventInterceptor)
    }

    /// The point of the rollback: the next enable() tries again instead of returning early.
    func testEnableCanBeRetriedAfterAFailure() {
        let core = makeCore(failing: .eventTapCreationFailed)

        core.enable()
        core.enable()

        XCTAssertEqual(factoryCalls.count, 2)
        XCTAssertFalse(core.isActive)
    }

    /// disable() after a failed enable() has nothing left to undo and must stay harmless.
    func testDisableAfterAFailedEnableIsANoOp() {
        let core = makeCore(failing: .eventTapCreationFailed)

        core.enable()
        core.disable()

        XCTAssertFalse(core.isActive)
        XCTAssertEqual(factoryCalls.count, 1)
    }

    // MARK: - Scroll keys held while the core stops

    /// Sleep, Pause or lost Accessibility access while a scroll key was held: without the
    /// taps its release is never seen, and fast scrolling stayed on (or smoothing paused,
    /// or Shift-to-horizontal on) until that key was pressed again.
    func testDisableForgetsTheScrollKeysThatWereHeld() {
        let saved = (Options.shared.scroll.dash, Options.shared.scroll.toggle, Options.shared.scroll.block)
        Options.shared.scroll.dash = ScrollHotkey(type: .mouse, code: 50)
        Options.shared.scroll.toggle = ScrollHotkey(type: .mouse, code: 60)
        Options.shared.scroll.block = ScrollHotkey(type: .mouse, code: 70)
        defer {
            Options.shared.scroll.dash = saved.0
            Options.shared.scroll.toggle = saved.1
            Options.shared.scroll.block = saved.2
        }
        let core = ScrollCore()
        defer { core.toggleScroll = false }
        XCTAssertTrue(core.handleScrollHotkey(code: 50, isDown: true))
        XCTAssertTrue(core.handleScrollHotkey(code: 60, isDown: true))
        XCTAssertTrue(core.handleScrollHotkey(code: 70, isDown: true))
        XCTAssertTrue(core.dashScroll)
        XCTAssertEqual(core.dashAmplification, 5.0)
        XCTAssertTrue(core.toggleScroll)
        XCTAssertTrue(core.blockSmooth)

        core.isActive = true   // as after enable(); no event tap is created here
        core.disable()

        XCTAssertFalse(core.dashScroll)
        XCTAssertEqual(core.dashAmplification, 1.0)
        XCTAssertFalse(core.toggleScroll)
        XCTAssertFalse(core.blockSmooth)
        XCTAssertFalse(core.dashKeyHeld)
        XCTAssertFalse(core.toggleKeyHeld)
        XCTAssertFalse(core.blockKeyHeld)
        // The releases that come after the wake find nothing held.
        XCTAssertFalse(core.handleScrollHotkey(code: 50, isDown: false))
        XCTAssertFalse(core.handleScrollHotkey(code: 60, isDown: false))
        XCTAssertFalse(core.handleScrollHotkey(code: 70, isDown: false))
    }

    /// The same for keyboard scroll keys, which the hotkey tap tracks.
    func testDisableForgetsAHeldKeyboardScrollKey() {
        let core = ScrollCore()
        defer { core.toggleScroll = false }
        core.dashKeyHeld = true
        core.dashScroll = true
        core.dashAmplification = 5.0
        core.blockKeyHeld = true
        core.blockSmooth = true
        core.toggleKeyHeld = true
        core.toggleScroll = true

        core.isActive = true
        core.disable()

        XCTAssertFalse(core.dashScroll)
        XCTAssertEqual(core.dashAmplification, 1.0)
        XCTAssertFalse(core.blockSmooth)
        XCTAssertFalse(core.toggleScroll)
    }

    /// A Scrollio scroll action held through a button binding is counted apart: ButtonCore
    /// releases it when it stops (InputProcessor.clearActiveBindings), not ScrollCore.
    func testDisableLeavesAHeldScrollActionToButtonCore() {
        let core = ScrollCore()
        core.handleScrollAction(role: .dash, isDown: true)
        core.isActive = true
        core.disable()
        XCTAssertTrue(core.dashScroll)

        core.handleScrollAction(role: .dash, isDown: false)
        XCTAssertFalse(core.dashScroll)
        XCTAssertEqual(core.dashAmplification, 1.0)
    }

    // MARK: - With taps that are no taps (FakeEventTapSystem) and a display that is none

    /// The shared poster with a stand-in for the display, for a test that starts a core;
    /// call the result to put everything back.
    private func standInForTheDisplay() -> (display: FakeDisplay, restore: () -> Void) {
        let poster = ScrollPoster.shared
        let savedFactory = poster.makeDisplayLink
        poster.stop()
        poster.dropDisplayLinkForTests()
        poster.clearRecreateCooldownForTests()
        let display = FakeDisplay(for: poster)
        return (display, {
            poster.stop()
            poster.stopKeeper()
            poster.dropDisplayLinkForTests()
            poster.makeDisplayLink = savedFactory
            poster.clearRecreateCooldownForTests()
        })
    }

    /// enable() makes the three taps and the display link; disable() switches every tap off
    /// and lets go of it. (A disable() that left the taps running went unnoticed: an active
    /// tap nobody services freezes the wheel.)
    func testEnableStartsTheThreeTapsAndDisableSwitchesThemOff() {
        let (display, restore) = standInForTheDisplay()
        defer { restore() }
        var systems: [FakeEventTapSystem] = []
        var made: [(interceptor: Interceptor, options: CGEventTapOptions)] = []
        let core = ScrollCore()
        core.makeInterceptor = { mask, callback, options in
            let system = FakeEventTapSystem()
            systems.append(system)
            let interceptor = try system.makeInterceptor(mask: mask, callback: callback, options: options)
            made.append((interceptor, options))
            return interceptor
        }

        core.enable()

        XCTAssertTrue(core.isActive)
        XCTAssertEqual(made.map(\.options), [.defaultTap, .listenOnly, .listenOnly])
        XCTAssertEqual(made.map { $0.interceptor.kind }, [.scroll, .scrollKeys, .leftClick])
        XCTAssertTrue(made.allSatisfy { $0.interceptor.isRunning() })
        XCTAssertTrue(core.scrollEventInterceptor === made.first?.interceptor)
        XCTAssertEqual(display.made.count, 1, "the display link is made")
        XCTAssertEqual(display.made.first?.isRunning, false, "and waits for the first wheel event")

        core.disable()

        XCTAssertFalse(core.isActive)
        XCTAssertTrue(made.allSatisfy { !$0.interceptor.isRunning() }, "every tap is switched off")
        XCTAssertEqual(systems.map(\.switches), [[true, false], [true, false], [true, false]])
        XCTAssertNil(core.scrollEventInterceptor)
        XCTAssertNil(core.hotkeyEventInterceptor)
        XCTAssertNil(core.mouseEventInterceptor)
    }

    /// The second or third tap cannot be started (the access went in between): the taps
    /// already made are switched off again, none is left running behind a core that is off.
    func testATapThatFailsLater_leavesNoEarlierTapRunning() {
        let (_, restore) = standInForTheDisplay()
        defer { restore() }
        var systems: [FakeEventTapSystem] = []
        let core = ScrollCore()
        core.makeInterceptor = { mask, callback, options in
            let system = FakeEventTapSystem()
            system.isTrusted = systems.count < 2   // the third finds the access gone
            systems.append(system)
            return try system.makeInterceptor(mask: mask, callback: callback, options: options)
        }

        core.enable()

        XCTAssertFalse(core.isActive)
        XCTAssertEqual(systems.count, 3)
        XCTAssertEqual(systems.map(\.isOn), [false, false, false])
        XCTAssertNil(core.scrollEventInterceptor)
    }

    /// macOS turned the scroll tap off after a timeout: the tap's own callback restarts it
    /// (it goes on again `Interceptor.restartDelay` later), instead of leaving the wheel raw
    /// until the keeper's next look. Without this the wheel stayed unsmoothed for up to 5 s.
    func testATimeoutOfTheScrollTapRestartsIt() throws {
        let (_, restore) = standInForTheDisplay()
        defer { restore() }
        let saved = ScrollCore.shared.scrollEventInterceptor
        defer { ScrollCore.shared.scrollEventInterceptor = saved }
        let system = FakeEventTapSystem()
        let tap = try system.makeInterceptor(options: .defaultTap)
        var cleanedUp = 0
        tap.onRestart = { cleanedUp += 1 }
        ScrollCore.shared.scrollEventInterceptor = tap
        defer { tap.stop() }
        let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0))

        system.turnOffAsMacOSDoes()
        let result = ScrollCore.shared.scrollEventCallBack(CGEventTapProxy(bitPattern: 1)!, .tapDisabledByTimeout, event, nil)

        XCTAssertTrue(result?.takeUnretainedValue() === event)
        XCTAssertEqual(cleanedUp, 1, "the restart ends the scroll session through the tap's owner")
        XCTAssertFalse(tap.isRunning(), "off until the restart's timer fires")
        let deadline = Date().addingTimeInterval(3)
        while !tap.isRunning() && Date() < deadline {
            _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        XCTAssertTrue(tap.isRunning(), "on again")

        // Switched off by the user's input (secure input and the like): no restart from here.
        let switchesBefore = system.switches.count
        _ = ScrollCore.shared.scrollEventCallBack(CGEventTapProxy(bitPattern: 1)!, .tapDisabledByUserInput, event, nil)
        XCTAssertEqual(system.switches.count, switchesBefore)
        XCTAssertEqual(cleanedUp, 1)
    }

    // MARK: - Scrollio's own events

    /// The scroll tap also sees the frames Scrollio posts itself; they carry a mark. Such
    /// an event passes as it is and is not smoothed a second time. With the mark ignored
    /// every posted frame would feed the smoothing again, and only a test of the Welcome
    /// Guide noticed.
    func testAnEventScrollioPostedItselfPassesTheScrollTapAndIsNotSmoothedAgain() throws {
        var inputs = 0
        ScrollCore.posterInputObserverForTests = { _ in inputs += 1 }
        defer { ScrollCore.posterInputObserverForTests = nil }
        let proxy = CGEventTapProxy(bitPattern: 1)!
        func wheelEvent() throws -> CGEvent {
            return try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 3, wheel2: 0, wheel3: 0))
        }

        // The control: the same event without the mark is taken for smoothing.
        _ = ScrollCore.shared.scrollEventCallBack(proxy, .scrollWheel, try wheelEvent(), nil)
        try XCTSkipIf(inputs == 0, "smoothing is off for the app in front, so there is nothing to tell apart")
        XCTAssertEqual(inputs, 1)

        let own = try wheelEvent()
        ScrollUtils.shared.markSyntheticSmoothEvent(own)
        XCTAssertTrue(ScrollUtils.shared.isSyntheticSmoothEvent(own))
        let result = ScrollCore.shared.scrollEventCallBack(proxy, .scrollWheel, own, nil)

        XCTAssertEqual(inputs, 1, "not smoothed again")
        XCTAssertTrue(result?.takeUnretainedValue() === own, "it passes")
        XCTAssertEqual(own.getIntegerValueField(.scrollWheelEventDeltaAxis1), 3, "unchanged")
    }
}
