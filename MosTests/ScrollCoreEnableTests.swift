import XCTest
@testable import Mos_Debug

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
        core.handleMosScrollAction(role: .dash, isDown: true)
        core.isActive = true
        core.disable()
        XCTAssertTrue(core.dashScroll)

        core.handleMosScrollAction(role: .dash, isDown: false)
        XCTAssertFalse(core.dashScroll)
        XCTAssertEqual(core.dashAmplification, 1.0)
    }
}
