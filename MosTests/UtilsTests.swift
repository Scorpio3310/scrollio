import XCTest
@testable import Mos_Debug

/// Small helpers in Utils that used to fail on edge cases.
final class UtilsTests: XCTestCase {

    // MARK: - Single instance

    /// The list of running copies includes this process, at any position. Only the other
    /// copies may be asked to quit.
    func testOtherInstancesNeverContainTheOwnProcess() {
        XCTAssertEqual(Utils.otherInstanceProcessIdentifiers(running: [100, 200], own: 100), [200])
        XCTAssertEqual(Utils.otherInstanceProcessIdentifiers(running: [200, 100], own: 100), [200])
        XCTAssertEqual(Utils.otherInstanceProcessIdentifiers(running: [300, 100, 200], own: 100), [300, 200])
    }

    func testNoOtherInstancesWhenOnlyThisProcessRuns() {
        XCTAssertEqual(Utils.otherInstanceProcessIdentifiers(running: [100], own: 100), [])
        XCTAssertEqual(Utils.otherInstanceProcessIdentifiers(running: [], own: 100), [])
    }

    /// A copy that is not in the list yet (still registering) must not hide the others.
    func testOtherInstancesWhenTheOwnProcessIsNotListed() {
        XCTAssertEqual(Utils.otherInstanceProcessIdentifiers(running: [200], own: 100), [200])
    }
}
