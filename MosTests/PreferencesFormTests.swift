//
//  PreferencesFormTests.swift
//  MosTests
//
//  What the panes built in code share besides the grouped kit: the metrics, the hint type,
//  the column and the section header, and snapping a slider value.
//

import XCTest
@testable import Mos_Debug

final class PreferencesFormTests: XCTestCase {

    func testMetrics() {
        XCTAssertEqual(PreferencesForm.contentWidth, 450)
        XCTAssertEqual(PreferencesForm.rowSpacing, 17)
        XCTAssertEqual(PreferencesForm.hintSpacing, 6)
    }

    func testHintsUseOneFontSizeOfAtLeastTenPoints() {
        XCTAssertGreaterThanOrEqual(PreferencesForm.hintFontSize, 10)
        XCTAssertEqual(PreferencesForm.hintFontSize, NSFont.smallSystemFontSize)
        XCTAssertEqual(PreferencesForm.hintFont.pointSize, PreferencesForm.hintFontSize)
    }

    func testAColumnStacksItsLinesAndASectionHeaderIsSemibold() {
        let header = PreferencesForm.makeSectionHeader("Section")
        let line = NSTextField(labelWithString: "What the section is about.")
        let column = PreferencesForm.makeColumn([header, line])
        column.setFrameSize(column.fittingSize)
        column.layoutSubtreeIfNeeded()
        XCTAssertEqual(column.orientation, .vertical)
        XCTAssertEqual(column.spacing, PreferencesForm.hintSpacing)
        XCTAssertEqual(header.minX(in: column), line.minX(in: column), accuracy: 0.5)
        XCTAssertEqual(header.font, PreferencesForm.sectionHeaderFont)
        XCTAssertEqual(header.font?.pointSize, 13)
        XCTAssertEqual(header.accessibilityRole(), .staticText)
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

private extension NSView {
    /// The left edge of the view's alignment rectangle in `ancestor`.
    func minX(in ancestor: NSView) -> CGFloat {
        return ancestor.convert(alignmentRect(forFrame: frame), from: superview).minX
    }
}
