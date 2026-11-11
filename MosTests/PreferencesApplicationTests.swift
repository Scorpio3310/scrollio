//
//  PreferencesApplicationTests.swift
//  MosTests
//
//  The Apps pane. Nothing is shown on screen.
//

import XCTest
@testable import Mos_Debug

final class PreferencesApplicationTests: XCTestCase {

    /// Placeholder until the pane's own tests arrive: the storyboard makes the pane.
    func testTheStoryboardMakesTheAppsPane() {
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesSplitViewController.self))
        XCTAssertTrue(storyboard.instantiateController(withIdentifier: PANEL_IDENTIFIER.application) is PreferencesApplicationViewController)
    }
}
