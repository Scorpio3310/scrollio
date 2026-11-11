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

    // MARK: - Application name from a path

    /// "50% Off" is not valid percent-encoding; the name used to be force-unwrapped.
    func testParseNameKeepsANameWithAStrayPercentSign() {
        XCTAssertEqual(Utils.parseName(fromPath: "/Applications/50% Off.app"), "50% Off")
        XCTAssertEqual(Utils.parseName(fromPath: "/Applications/100%.app"), "100%")
    }

    func testParseNameStillDecodesPercentEncoding() {
        XCTAssertEqual(Utils.parseName(fromPath: "/Applications/My%20App.app"), "My App")
    }

    /// Only the ".app" extension is removed, not any "app" inside the name.
    func testParseNameRemovesOnlyTheExtension() {
        XCTAssertEqual(Utils.parseName(fromPath: "/Applications/Snapper.app"), "Snapper")
        XCTAssertEqual(Utils.parseName(fromPath: "/Applications/Safari.app"), "Safari")
        XCTAssertEqual(Utils.parseName(fromPath: "/usr/bin/happy"), "happy")
    }
}
