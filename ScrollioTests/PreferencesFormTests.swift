//
//  PreferencesFormTests.swift
//  MosTests
//
//  What the panes built in code share besides the grouped kit: the hint and header type,
//  and snapping a slider value.
//

import XCTest
@testable import Scrollio_Debug

final class PreferencesFormTests: XCTestCase {

    func testHintsUseOneFontSizeOfAtLeastTenPoints() {
        XCTAssertGreaterThanOrEqual(PreferencesForm.hintFontSize, 10)
        XCTAssertEqual(PreferencesForm.hintFontSize, NSFont.smallSystemFontSize)
        XCTAssertEqual(PreferencesForm.hintFont.pointSize, PreferencesForm.hintFontSize)
    }

    func testASectionHeaderIsSemiboldAtTheSystemSize() {
        let font = PreferencesForm.sectionHeaderFont
        XCTAssertEqual(font.pointSize, 13)
        let traits = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
        XCTAssertEqual(traits?[.weight] as? CGFloat ?? 0, NSFont.Weight.semibold.rawValue, accuracy: 0.01)
    }

    func testSnappedClampsToTheRangeAndRoundsToTheStep() {
        XCTAssertEqual(PreferencesForm.snapped(-1, to: 0...1, step: 0.05), 0)
        XCTAssertEqual(PreferencesForm.snapped(9, to: 0...1, step: 0.05), 1)
        XCTAssertEqual(PreferencesForm.snapped(0.42, to: 0...1, step: 0.05), 0.4)
        XCTAssertEqual(PreferencesForm.snapped(0.43, to: 0...1, step: 0.05), 0.45)
        // From the lower bound, without floating-point noise.
        XCTAssertEqual(PreferencesForm.snapped(0.81, to: 0.25...3, step: 0.05), 0.8)
        XCTAssertEqual(PreferencesForm.snapped(1.26, to: 0.5...3, step: 0.1), 1.3)
        // Not a number: the lower bound.
        XCTAssertEqual(PreferencesForm.snapped(.nan, to: 0.25...3, step: 0.05), 0.25)
        XCTAssertEqual(PreferencesForm.snapped(.infinity, to: 0...5, step: 0.05), 0)
        // No step: only clamped.
        XCTAssertEqual(PreferencesForm.snapped(0.123, to: 0...1, step: 0), 0.123)
    }
}
