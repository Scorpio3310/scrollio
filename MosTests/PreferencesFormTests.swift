//
//  PreferencesFormTests.swift
//  MosTests
//
//  The layout kit of the preference panes that are built in code: the grid numbers
//  taken from the storyboard panes and the geometry of rows, hints and headers.
//

import XCTest
@testable import Mos_Debug

final class PreferencesFormTests: XCTestCase {

    /// Where a view sits by its alignment rectangle, which is what the grid is defined in
    /// (a text field's frame is 2 pt wider on each side than its text).
    private func alignmentFrame(of view: NSView, in root: NSView) -> NSRect {
        return root.convert(view.alignmentRect(forFrame: view.frame), from: view.superview)
    }

    func testGridMatchesTheStoryboardPanes() {
        XCTAssertEqual(PreferencesForm.contentWidth, 450)
        XCTAssertEqual(PreferencesForm.margin, 20)
        XCTAssertEqual(PreferencesForm.labelWidth, 136)
        XCTAssertEqual(PreferencesForm.columnSpacing, 15)
        XCTAssertEqual(PreferencesForm.controlWidth, 259)
        XCTAssertEqual(PreferencesForm.rowSpacing, 17)
        XCTAssertEqual(PreferencesForm.hintSpacing, 6)
    }

    func testHintsUseOneFontSizeOfAtLeastTenPoints() {
        XCTAssertGreaterThanOrEqual(PreferencesForm.hintFontSize, 10)
        XCTAssertEqual(PreferencesForm.hintFontSize, NSFont.smallSystemFontSize)
        XCTAssertEqual(PreferencesForm.makeHint("Hint").font?.pointSize, PreferencesForm.hintFontSize)
    }

    func testARowPutsTheLabelAndTheControlOnTheGrid() throws {
        let root = PreferencesForm.makeBackground()
        let content = PreferencesForm.installContentStack(in: root)
        let checkbox = PreferencesForm.makeCheckbox(title: "Option", target: nil, action: nil)
        let hint = PreferencesForm.makeHint("What the option does.")
        let (row, label) = PreferencesForm.makeRow(title: "Title", column: PreferencesForm.makeColumn([checkbox, hint]))
        label.firstBaselineAnchor.constraint(equalTo: checkbox.firstBaselineAnchor).isActive = true
        let header = PreferencesForm.makeSectionHeader("Section")
        PreferencesForm.add([row, PreferencesForm.makeSeparator(), header], to: content)
        root.setFrameSize(root.fittingSize)
        root.layoutSubtreeIfNeeded()

        XCTAssertEqual(root.frame.width, PreferencesForm.contentWidth)

        let labelFrame = alignmentFrame(of: label, in: root)
        XCTAssertEqual(labelFrame.minX, 20, accuracy: 0.5)
        XCTAssertEqual(labelFrame.maxX, 156, accuracy: 0.5)
        XCTAssertEqual(label.alignment, .right)
        XCTAssertEqual(label.font?.pointSize, NSFont.smallSystemFontSize)

        let checkboxFrame = alignmentFrame(of: checkbox, in: root)
        XCTAssertEqual(checkboxFrame.minX, 171, accuracy: 0.5)
        XCTAssertLessThanOrEqual(checkboxFrame.maxX, 430.5)

        // The hint sits 6 pt under its control (the root view is not flipped).
        let hintFrame = alignmentFrame(of: hint, in: root)
        XCTAssertEqual(hintFrame.minX, 171, accuracy: 0.5)
        XCTAssertEqual(checkboxFrame.minY - hintFrame.maxY, PreferencesForm.hintSpacing, accuracy: 0.5)

        // A section header starts at the left margin.
        let headerFrame = alignmentFrame(of: header, in: root)
        XCTAssertEqual(headerFrame.minX, 20, accuracy: 0.5)
        XCTAssertEqual(header.font?.pointSize, 13)
    }

    func testHiddenHintsTakeNoRoom() {
        let hint = PreferencesForm.makeHint("")
        PreferencesForm.setHint(hint, nil)
        XCTAssertTrue(hint.isHidden)
        PreferencesForm.setHint(hint, "On the mouse: 40%")
        XCTAssertFalse(hint.isHidden)
        XCTAssertEqual(hint.stringValue, "On the mouse: 40%")
    }

    func testSliderLineKeepsTheValueNextToTheSlider() {
        let line = PreferencesForm.makeSliderLine(
            range: 0.5...3,
            widestValue: "3.0×",
            target: nil,
            action: nil,
            accessibilityLabel: "Tracking speed"
        )
        XCTAssertEqual(line.slider.minValue, 0.5)
        XCTAssertEqual(line.slider.maxValue, 3)
        XCTAssertTrue(line.slider.isContinuous)
        XCTAssertEqual(line.slider.accessibilityLabel(), "Tracking speed")
        line.line.layoutSubtreeIfNeeded()
        XCTAssertEqual(line.slider.frame.width, PreferencesForm.sliderWidth)
        XCTAssertLessThanOrEqual(line.line.fittingSize.width, PreferencesForm.controlWidth)
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
