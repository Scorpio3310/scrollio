//
//  PreferencesButtonsTests.swift
//  MosTests
//
//  The Buttons pane. Nothing is shown on screen.
//

import XCTest
@testable import Mos_Debug

final class PreferencesButtonsTests: XCTestCase {

    /// Placeholder until the pane's own tests arrive: the storyboard makes the pane.
    func testTheStoryboardMakesTheButtonsPane() {
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesSplitViewController.self))
        XCTAssertTrue(storyboard.instantiateController(withIdentifier: PANEL_IDENTIFIER.buttons) is PreferencesButtonsViewController)
    }
}
