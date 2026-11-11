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
}
