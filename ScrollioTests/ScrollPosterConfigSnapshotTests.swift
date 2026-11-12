import XCTest
@testable import Scrollio_Debug

final class ScrollPosterConfigSnapshotTests: XCTestCase {

    private var savedSim = false
    private var savedDead = 1.0
    private var savedApp: Application?

    override func setUp() {
        super.setUp()
        savedSim = Options.shared.scroll.smoothSimTrackpad
        savedDead = Options.shared.scroll.deadZone
        savedApp = ScrollCore.shared.application
    }

    override func tearDown() {
        Options.shared.scroll.smoothSimTrackpad = savedSim
        Options.shared.scroll.deadZone = savedDead
        ScrollCore.shared.application = savedApp
        super.tearDown()
    }

    /// 快照捕获后改动 live Options 不应影响已捕获的值 (证明快照而非实时读)
    func testConfigSnapshot_capturesValuesNotLiveReads() {
        ScrollCore.shared.application = nil
        Options.shared.scroll.smoothSimTrackpad = true
        Options.shared.scroll.deadZone = 7.0
        // (The app's own poster reads where trackpad-style works: without an event the
        // scroll counts as a Mac app's, and that switch is off unless chosen.)
        let inMacApps = Options.shared.trackpadStyleInMacApps
        Options.shared.trackpadStyleInMacApps = true
        defer { Options.shared.trackpadStyleInMacApps = inMacApps }

        ScrollPoster.shared.captureConfigSnapshotForTests()

        // 改 live 值, 快照不应跟随
        Options.shared.scroll.smoothSimTrackpad = false
        Options.shared.scroll.deadZone = 1.0

        let snap = ScrollPoster.shared.configSnapshotForTests
        XCTAssertTrue(snap.simTrackpadEnabled, "simTrackpadEnabled 应为捕获时的 true")
        XCTAssertEqual(snap.deadZone, 7.0, "deadZone 应为捕获时的 7.0")
    }

    /// A stored dead zone that is not positive kept the display link running forever: the
    /// snapshot takes the default instead and leaves the stored value alone.
    func testConfigSnapshot_takesTheDefaultForADeadZoneThatIsNotPositive() {
        ScrollCore.shared.application = nil
        for stored in [0.0, -2.0] {
            Options.shared.scroll.deadZone = stored
            ScrollPoster.shared.captureConfigSnapshotForTests()
            XCTAssertEqual(ScrollPoster.shared.configSnapshotForTests.deadZone, 1.0, "\(stored)")
            XCTAssertEqual(Options.shared.scroll.deadZone, stored, "the stored value stays")
        }
        Options.shared.scroll.deadZone = .nan
        ScrollPoster.shared.captureConfigSnapshotForTests()
        XCTAssertEqual(ScrollPoster.shared.configSnapshotForTests.deadZone, 1.0)
    }
}
