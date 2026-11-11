//
//  StatusMenuTests.swift
//  MosTests
//
//  The menu of the status-bar item. Nothing is shown on screen, and no status item is made.
//

import XCTest
@testable import Mos_Debug

final class StatusMenuTests: XCTestCase {

    /// Placeholder until the menu's own tests arrive: the manager is the item's menu and
    /// its delegate. (Making one would put a status item in the menu bar.)
    func testTheStatusMenuIsAMenuThatBuildsItself() {
        XCTAssertTrue(StatusItemManager.self.isSubclass(of: NSMenu.self))
        XCTAssertTrue(StatusItemManager.self.conforms(to: NSMenuDelegate.self))
    }
}
