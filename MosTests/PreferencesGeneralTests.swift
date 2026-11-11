//
//  PreferencesGeneralTests.swift
//  MosTests
//
//  The General pane. Nothing is shown on screen.
//

import XCTest
@testable import Mos_Debug

final class PreferencesGeneralTests: XCTestCase {

    /// Placeholder until the pane's own tests arrive: the storyboard makes the pane.
    func testTheStoryboardMakesTheGeneralPane() {
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesSplitViewController.self))
        XCTAssertTrue(storyboard.instantiateController(withIdentifier: PANEL_IDENTIFIER.general) is PreferencesGeneralViewController)
    }
}
