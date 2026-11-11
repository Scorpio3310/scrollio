//
//  PreferencesGroupedFormTests.swift
//  MosTests
//
//  The grouped-form kit (System Settings boxes): the numbers, how rows lay out their
//  title, explanation and control, the hairlines between the rows that show, dimming a
//  row, the accessibility names of its controls, and the spacing of boxes, section
//  titles and the footer in a pane. Nothing is shown on screen.
//

import XCTest
@testable import Mos_Debug

final class PreferencesGroupedFormTests: XCTestCase {

    private typealias Form = PreferencesGroupedForm

    private let paneWidth: CGFloat = 500
    private var boxWidth: CGFloat { Form.boxWidth(paneWidth: paneWidth) }

    /// Where a view sits in `root` by its alignment rectangle (the root is not flipped).
    private func frame(of view: NSView, in root: NSView) -> NSRect {
        return root.convert(view.alignmentRect(forFrame: view.frame), from: view.superview)
    }

    /// A pane with `views` in its content stack, sized and laid out.
    private func makePane(_ views: [NSView]) -> NSView {
        let root = PreferencesForm.makeBackground()
        let content = Form.installContentStack(in: root, paneWidth: paneWidth)
        Form.add(views, to: content)
        root.setFrameSize(root.fittingSize)
        root.layoutSubtreeIfNeeded()
        return root
    }

    private func explanationLineHeight() -> CGFloat {
        let label = NSTextField(wrappingLabelWithString: "X")
        label.font = Form.explanationFont
        return label.fittingSize.height
    }

    private func titleLineHeight() -> CGFloat {
        let label = NSTextField(labelWithString: "X")
        label.font = Form.titleFont
        return label.fittingSize.height
    }

    // MARK: - Numbers

    func testMetricsFollowSystemSettings() {
        XCTAssertEqual(Form.margin, 20)
        XCTAssertEqual(Form.boxCornerRadius, 10)
        XCTAssertEqual(Form.rowHorizontalInset, 10)
        XCTAssertEqual(Form.rowVerticalInset, 10)
        XCTAssertEqual(Form.titleFont.pointSize, 13)
        XCTAssertEqual(Form.explanationFont.pointSize, 11)
        XCTAssertEqual(Form.explanationFont.pointSize, PreferencesForm.hintFontSize)
        XCTAssertEqual(Form.sectionTitleFont.pointSize, 13)
        XCTAssertEqual(Form.boxWidth(paneWidth: 520), 480)
        XCTAssertEqual(Form.titleColor(enabled: true), .labelColor)
        XCTAssertEqual(Form.explanationColor(enabled: true), .secondaryLabelColor)
        XCTAssertEqual(Form.titleColor(enabled: false), .tertiaryLabelColor)
        XCTAssertEqual(Form.explanationColor(enabled: false), .tertiaryLabelColor)
    }

    /// `color` resolved in the appearance `name`, as plain sRGB components.
    private func resolve(_ color: NSColor, in name: NSAppearance.Name) -> (white: CGFloat, alpha: CGFloat) {
        var result: (CGFloat, CGFloat) = (-1, -1)
        NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
            let rgb = color.usingColorSpace(.sRGB)!
            result = (rgb.redComponent, rgb.alphaComponent)
        }
        return result
    }

    func testBoxColoursAreTheSystemsOutsideVibrancy() {
        // The panes stand on an NSVisualEffectView: their content draws in a vibrant
        // appearance, where the system fill is an opaque grey meant for blending.
        let root = PreferencesForm.makeBackground()
        let content = NSView()
        root.addSubview(content)
        let host = NSView()
        host.addSubview(root)
        host.appearance = NSAppearance(named: .darkAqua)
        XCTAssertEqual(content.effectiveAppearance.name, .vibrantDark)

        // The box takes the system's tertiary fill of the plain appearance instead.
        for (plain, vibrant) in [(NSAppearance.Name.aqua, NSAppearance.Name.vibrantLight), (.darkAqua, .vibrantDark)] {
            let system = resolve(.tertiarySystemFill, in: plain)
            let fill = resolve(Form.boxFillColor, in: plain)
            let fillInVibrancy = resolve(Form.boxFillColor, in: vibrant)
            XCTAssertEqual(fill.white, system.white, accuracy: 0.001)
            XCTAssertEqual(fill.alpha, system.alpha, accuracy: 0.001)
            XCTAssertEqual(fillInVibrancy.white, fill.white, accuracy: 0.001, "\(vibrant.rawValue)")
            XCTAssertEqual(fillInVibrancy.alpha, fill.alpha, accuracy: 0.001, "\(vibrant.rawValue)")
            XCTAssertLessThan(fill.alpha, 0.1, "a tint, not a solid grey")
            let line = resolve(Form.hairlineColor, in: vibrant)
            let separator = resolve(.separatorColor, in: plain)
            XCTAssertEqual(line.alpha, separator.alpha, accuracy: 0.001)
        }
        // Dark: a lighter box; light: a darker one.
        XCTAssertEqual(resolve(Form.boxFillColor, in: .darkAqua).white, 1, accuracy: 0.001)
        XCTAssertEqual(resolve(Form.boxFillColor, in: .aqua).white, 0, accuracy: 0.001)
    }

    func testAStoryboardBoxCanTakeTheLookOfTheKit() {
        let box = NSBox()
        Form.styleAsGroupBox(box)
        XCTAssertEqual(box.boxType, .custom)
        XCTAssertEqual(box.cornerRadius, Form.boxCornerRadius)
        XCTAssertEqual(box.borderWidth, 0)
        XCTAssertTrue(box.fillColor === Form.boxFillColor)
    }

    // MARK: - Rows

    func testASwitchRowPutsTheSwitchOnTheTitleLineAtTheRightEdge() {
        let row = PreferencesSwitchRow(title: "Tap to click", explanation: "Tap with one finger", target: nil, action: nil)
        let box = PreferencesGroupBox(width: boxWidth, rows: [row])
        let root = makePane([box])

        let title = frame(of: row.titleLabel, in: root)
        let explanation = frame(of: row.explanationLabel, in: root)
        let toggle = frame(of: row.toggle, in: root)
        let boxFrame = frame(of: box, in: root)
        XCTAssertEqual(title.minX - boxFrame.minX, Form.rowHorizontalInset, accuracy: 0.5)
        XCTAssertEqual(boxFrame.maxX - toggle.maxX, Form.rowHorizontalInset, accuracy: 0.5)
        XCTAssertEqual(toggle.midY, title.midY, accuracy: 0.5, "centred on the title line")
        XCTAssertEqual(boxFrame.maxY - title.maxY, Form.rowVerticalInset, accuracy: 0.5)

        // The explanation under the title, small and secondary, inside the title column.
        XCTAssertEqual(explanation.minX, title.minX, accuracy: 0.5)
        XCTAssertEqual(title.minY - explanation.maxY, Form.explanationSpacing, accuracy: 0.5)
        XCTAssertEqual(row.explanationLabel.font?.pointSize, 11)
        XCTAssertEqual(row.explanationLabel.textColor, .secondaryLabelColor)
        XCTAssertEqual(row.titleLabel.font?.pointSize, 13)
        XCTAssertEqual(row.titleLabel.textColor, .labelColor)
        XCTAssertLessThanOrEqual(explanation.maxX, toggle.minX - Form.controlSpacing + 0.5)
        XCTAssertEqual(explanation.minY - boxFrame.minY, Form.rowVerticalInset, accuracy: 0.5)

        // Title, explanation and the padding make the row's height.
        XCTAssertEqual(
            row.frame.height,
            2 * Form.rowVerticalInset + titleLineHeight() + Form.explanationSpacing + explanationLineHeight(),
            accuracy: 0.5
        )
        XCTAssertEqual(row.toggle.controlSize, Form.switchControlSize)
    }

    func testAnExplanationWrapsInsideTheTitleColumn() {
        let long = String(repeating: "A long explanation of what the setting does. ", count: 4)
        let row = PreferencesSwitchRow(title: "Title", explanation: long, target: nil, action: nil)
        let root = makePane([PreferencesGroupBox(width: boxWidth, rows: [row])])

        XCTAssertEqual(row.explanationLabel.preferredMaxLayoutWidth, row.titleColumnWidth, accuracy: 0.5)
        XCTAssertGreaterThan(row.explanationLabel.frame.height, 2 * explanationLineHeight() - 1, "it wraps")
        XCTAssertLessThanOrEqual(
            frame(of: row.explanationLabel, in: root).maxX,
            frame(of: row.toggle, in: root).minX - Form.controlSpacing + 0.5
        )
        // The title column is the row's content without the control.
        XCTAssertEqual(
            row.titleColumnWidth,
            boxWidth - 2 * Form.rowHorizontalInset - row.toggle.frame.width - Form.controlSpacing,
            accuracy: 0.5
        )
    }

    func testARowWithoutExplanationIsOneLineAndGrowsWhenItGetsOne() {
        let row = PreferencesSwitchRow(title: "Title", target: nil, action: nil)
        XCTAssertNil(row.explanation)
        XCTAssertTrue(row.explanationLabel.isHidden)
        let box = PreferencesGroupBox(width: boxWidth, rows: [row])
        _ = makePane([box])
        XCTAssertEqual(row.frame.height, 2 * Form.rowVerticalInset + titleLineHeight(), accuracy: 0.5)

        row.explanation = "Now with a line under the title."
        XCTAssertFalse(row.explanationLabel.isHidden)
        XCTAssertEqual(row.explanation, "Now with a line under the title.")
        XCTAssertEqual(
            row.fittingSize.height,
            2 * Form.rowVerticalInset + titleLineHeight() + Form.explanationSpacing + explanationLineHeight(),
            accuracy: 0.5
        )
        row.explanation = nil
        XCTAssertEqual(row.fittingSize.height, 2 * Form.rowVerticalInset + titleLineHeight(), accuracy: 0.5)
    }

    func testATallControlKeepsATitleOnlyRowCentred() {
        let button = NSButton(title: "⌥ Option", target: nil, action: nil)
        button.bezelStyle = .push
        let row = PreferencesGroupRow(title: "Scroll faster", accessory: button)
        let root = makePane([PreferencesGroupBox(width: boxWidth, rows: [row])])

        let title = frame(of: row.titleLabel, in: root)
        let control = frame(of: button, in: root)
        let rowFrame = frame(of: row, in: root)
        XCTAssertEqual(control.midY, title.midY, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(control.minY - rowFrame.minY, Form.controlMinimumInset - 0.5)
        XCTAssertGreaterThanOrEqual(rowFrame.maxY - control.maxY, Form.controlMinimumInset - 0.5)
        XCTAssertEqual(rowFrame.maxY - title.maxY, rowFrame.minY.distance(to: title.minY), accuracy: 0.5, "title in the middle")
    }

    func testASliderRowHasItsEndsUnderTheSliderAndItsValueBesideIt() throws {
        let row = PreferencesSliderRow(
            title: "Tracking speed",
            explanation: "How fast the pointer moves.",
            range: 1...10,
            ends: (low: "Slow", high: "Fast"),
            target: nil,
            action: nil
        )
        row.valueText = "6.3"
        let root = makePane([PreferencesGroupBox(width: boxWidth, rows: [row])])

        XCTAssertEqual(row.slider.minValue, 1)
        XCTAssertEqual(row.slider.maxValue, 10)
        XCTAssertTrue(row.slider.isContinuous)
        XCTAssertEqual(row.slider.accessibilityLabel(), "Tracking speed")
        XCTAssertEqual(row.slider.accessibilityHelp(), "How fast the pointer moves.")
        XCTAssertEqual(row.valueText, "6.3")

        let slider = frame(of: row.slider, in: root)
        let title = frame(of: row.titleLabel, in: root)
        let low = frame(of: try XCTUnwrap(row.lowEndLabel), in: root)
        let high = frame(of: try XCTUnwrap(row.highEndLabel), in: root)
        let value = frame(of: try XCTUnwrap(row.valueLabel), in: root)
        XCTAssertEqual(slider.width, Form.sliderWidth, accuracy: 0.5)
        XCTAssertEqual(slider.midY, title.midY, accuracy: 0.5)
        XCTAssertEqual(low.minX, slider.minX, accuracy: 0.5)
        XCTAssertEqual(high.maxX, slider.maxX, accuracy: 0.5)
        XCTAssertLessThan(low.maxY, slider.minY + 0.5, "under the slider")
        XCTAssertEqual(value.midY, slider.midY, accuracy: 1)
        XCTAssertEqual(value.minX - slider.maxX, Form.sliderValueSpacing, accuracy: 1)
        XCTAssertEqual(frame(of: row, in: root).maxX - value.maxX, Form.rowHorizontalInset, accuracy: 1)
        XCTAssertGreaterThanOrEqual(low.minY - frame(of: row, in: root).minY, Form.rowVerticalInset - 0.5)

        // Without a value or ends the slider itself reaches the right edge.
        let plain = PreferencesSliderRow(title: "Click", range: 0...2, showsValue: false, target: nil, action: nil)
        let plainRoot = makePane([PreferencesGroupBox(width: boxWidth, rows: [plain])])
        XCTAssertNil(plain.valueLabel)
        XCTAssertNil(plain.lowEndLabel)
        XCTAssertEqual(
            frame(of: plain, in: plainRoot).maxX - frame(of: plain.slider, in: plainRoot).maxX,
            Form.rowHorizontalInset,
            accuracy: 0.5
        )
    }

    func testAStackedRowPutsItsControlUnderTheTextAcrossTheBox() {
        let control = NSSegmentedControl(labels: ["One", "Two", "Three"], trackingMode: .selectOne, target: nil, action: nil)
        let row = PreferencesGroupRow(title: "Feel", explanation: "Short.", accessory: control, placement: .below)
        row.reservedExplanations = ["Short.", "A longer line, still one line."]
        let root = makePane([PreferencesGroupBox(width: boxWidth, rows: [row])])

        let rowFrame = frame(of: row, in: root)
        let controlFrame = frame(of: control, in: root)
        let explanation = frame(of: row.explanationLabel, in: root)
        XCTAssertEqual(controlFrame.minX - rowFrame.minX, Form.rowHorizontalInset, accuracy: 0.5)
        XCTAssertEqual(rowFrame.maxX - controlFrame.maxX, Form.rowHorizontalInset, accuracy: 0.5)
        XCTAssertEqual(explanation.minY - controlFrame.maxY, Form.stackedControlSpacing, accuracy: 0.5)
        XCTAssertEqual(controlFrame.minY - rowFrame.minY, Form.rowVerticalInset, accuracy: 0.5)
        XCTAssertEqual(row.titleColumnWidth, boxWidth - 2 * Form.rowHorizontalInset, accuracy: 0.5)
        XCTAssertEqual(control.accessibilityLabel(), "Feel")

        // Another explanation of the reserved ones never changes the height.
        let height = row.fittingSize.height
        row.explanation = "A longer line, still one line."
        XCTAssertEqual(row.fittingSize.height, height, accuracy: 0.5)
        // Without an explanation the control moves up under the title.
        row.reservedExplanations = []
        row.explanation = nil
        root.setFrameSize(root.fittingSize)
        root.layoutSubtreeIfNeeded()
        XCTAssertEqual(
            frame(of: row.titleLabel, in: root).minY - frame(of: control, in: root).maxY,
            Form.stackedControlSpacing,
            accuracy: 0.5
        )
    }

    func testDisablingARowDimsItsTextsWithItsControls() {
        let slider = PreferencesSliderRow(title: "Speed", explanation: "How far.", range: 0...1, ends: (low: "Low", high: "High"), target: nil, action: nil)
        let toggle = PreferencesSwitchRow(title: "Smooth", explanation: "Even.", target: nil, action: nil)
        for row in [slider, toggle] as [PreferencesGroupRow] {
            XCTAssertTrue(row.isEnabled)
            row.isEnabled = false
            XCTAssertTrue(row.controls.allSatisfy { !$0.isEnabled }, row.title)
            XCTAssertEqual(row.titleLabel.textColor, .tertiaryLabelColor)
            XCTAssertEqual(row.explanationLabel.textColor, .tertiaryLabelColor)
            row.isEnabled = true
            XCTAssertTrue(row.controls.allSatisfy(\.isEnabled), row.title)
            XCTAssertEqual(row.titleLabel.textColor, .labelColor)
            XCTAssertEqual(row.explanationLabel.textColor, .secondaryLabelColor)
        }
        slider.isEnabled = false
        XCTAssertEqual(slider.valueLabel?.textColor, .tertiaryLabelColor)
        XCTAssertEqual(slider.lowEndLabel?.textColor, .tertiaryLabelColor)
        XCTAssertEqual(slider.highEndLabel?.textColor, .tertiaryLabelColor)
        XCTAssertFalse(slider.slider.isEnabled)
    }

    func testControlsAreNamedByTheirRow() {
        let toggle = PreferencesSwitchRow(title: "Smooth scrolling", explanation: "Even movement.", target: nil, action: nil)
        XCTAssertEqual(toggle.controls, [toggle.toggle])
        XCTAssertEqual(toggle.toggle.accessibilityLabel(), "Smooth scrolling")
        XCTAssertEqual(toggle.toggle.accessibilityHelp(), "Even movement.")
        toggle.explanation = "Changed."
        XCTAssertEqual(toggle.toggle.accessibilityHelp(), "Changed.")

        // A button that shows a title of its own keeps it and points at the row's title.
        let recorder = NSButton(title: "⌘ Command", target: nil, action: nil)
        let clear = NSButton(title: "", target: nil, action: nil)
        clear.setAccessibilityLabel("Clear key")
        let line = NSStackView(views: [recorder, clear])
        let row = PreferencesGroupRow(title: "Pause smoothing", explanation: "Exact steps.", accessory: line, centeredOn: recorder, controls: [recorder])
        XCTAssertEqual(row.controls, [recorder])
        XCTAssertTrue(recorder.accessibilityTitleUIElement() as? NSTextField === row.titleLabel)
        XCTAssertEqual(recorder.accessibilityHelp(), "Exact steps.")
        XCTAssertEqual(clear.accessibilityLabel(), "Clear key", "only the named controls are renamed")
        row.isEnabled = false
        XCTAssertFalse(recorder.isEnabled)
        XCTAssertTrue(clear.isEnabled, "the caller decides about controls it did not name")
    }

    // MARK: - Box

    func testABoxDrawsHairlinesOnlyBetweenTheRowsThatShow() {
        let rows = (1...3).map { PreferencesSwitchRow(title: "Row \($0)", target: nil, action: nil) }
        let box = PreferencesGroupBox(width: boxWidth, rows: rows)
        let root = makePane([box])
        XCTAssertTrue(box.isFlipped)
        /// The top of a row in the box's (flipped) coordinates.
        func top(of row: NSView) -> CGFloat {
            return box.convert(row.bounds, from: row).minY
        }
        XCTAssertEqual(box.rows, rows)
        XCTAssertEqual(box.frame.width, boxWidth)
        XCTAssertTrue(rows.allSatisfy { $0.contentWidth == boxWidth })

        var lines = box.separatorRects
        XCTAssertEqual(lines.count, 2)
        for (line, row) in zip(lines, rows.dropFirst()) {
            XCTAssertEqual(line.minX, Form.rowHorizontalInset)
            XCTAssertEqual(line.maxX, boxWidth - Form.rowHorizontalInset, accuracy: 0.01)
            XCTAssertEqual(line.minY, top(of: row), accuracy: 0.5, "on top of the row")
            XCTAssertLessThanOrEqual(line.height, 1, "a hairline")
        }

        let rowHeight = rows[0].frame.height
        rows[1].isHidden = true
        root.setFrameSize(root.fittingSize)
        root.layoutSubtreeIfNeeded()
        lines = box.separatorRects
        XCTAssertEqual(box.visibleRows, [rows[0], rows[2]])
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].minY, top(of: rows[2]), accuracy: 0.5)
        XCTAssertEqual(lines[0].minY, rowHeight, accuracy: 0.5)
        XCTAssertEqual(box.frame.height, 2 * rowHeight, accuracy: 0.5, "a hidden row takes no room")

        rows[0].isHidden = true
        root.setFrameSize(root.fittingSize)
        root.layoutSubtreeIfNeeded()
        XCTAssertEqual(box.separatorRects, [], "nothing above the first row that shows")

        // A row added later gets the box's width.
        let late = PreferencesSwitchRow(title: "Late", target: nil, action: nil)
        box.addRow(late)
        XCTAssertEqual(late.contentWidth, boxWidth)
        XCTAssertEqual(box.rows.last, late)
    }

    // MARK: - Disclosure

    func testADisclosureRowShowsAndHidesWhatItReveals() {
        final class Target: NSObject {
            var clicks = 0
            @objc func toggle(_ sender: NSButton) { clicks += 1 }
        }
        let target = Target()
        let header = PreferencesDisclosureRow(title: "Advanced", target: target, action: #selector(Target.toggle(_:)))
        let hidden = PreferencesSwitchRow(title: "Inside", target: nil, action: nil)
        let section = PreferencesGroupSection(title: "Below", width: boxWidth, rows: [PreferencesSwitchRow(title: "Key", target: nil, action: nil)])
        let box = PreferencesGroupBox(width: boxWidth, rows: [header, hidden])
        header.revealedViews = [hidden, section]
        _ = makePane([box, section])

        XCTAssertFalse(header.isExpanded)
        XCTAssertTrue(hidden.isHidden)
        XCTAssertTrue(section.isHidden)
        XCTAssertFalse(header.button.isAccessibilityExpanded())
        XCTAssertEqual(header.button.title, "Advanced")
        XCTAssertTrue(header.titleLabel.isHidden, "the button carries the title")
        XCTAssertEqual(header.frame.height, 2 * Form.rowVerticalInset + titleLineHeight(), accuracy: 0.5)
        XCTAssertEqual(header.button.frame.height, header.frame.height, accuracy: 0.5, "the whole row is the button")
        let closedImage = header.button.image

        header.isExpanded = true
        XCTAssertFalse(hidden.isHidden)
        XCTAssertFalse(section.isHidden)
        XCTAssertTrue(header.button.isAccessibilityExpanded())
        XCTAssertFalse(header.button.image === closedImage, "the chevron turns")

        // The button only reports the click; its owner decides.
        XCTAssertTrue(header.button.sendAction(header.button.action, to: header.button.target))
        XCTAssertEqual(target.clicks, 1)
        XCTAssertTrue(header.isExpanded)
    }

    // MARK: - Pane

    func testAPaneSpacesBoxesSectionTitlesAndTheFooter() throws {
        let first = PreferencesGroupSection(width: boxWidth, rows: [PreferencesSwitchRow(title: "One", target: nil, action: nil)])
        let second = PreferencesGroupSection(width: boxWidth, rows: [PreferencesSwitchRow(title: "Two", target: nil, action: nil)])
        let titled = PreferencesGroupSection(title: "While you hold a key", width: boxWidth, rows: [
            PreferencesSwitchRow(title: "Three", target: nil, action: nil),
        ])
        let button = Form.makePushButton(title: "Reset to defaults", target: nil, action: nil)
        let footer = PreferencesGroupFooter(trailing: [button])
        let root = makePane([first, second, titled, footer])

        XCTAssertEqual(root.frame.width, paneWidth)
        let one = frame(of: first, in: root)
        let two = frame(of: second, in: root)
        let three = frame(of: titled, in: root)
        let foot = frame(of: footer, in: root)
        XCTAssertEqual(root.bounds.maxY - one.maxY, Form.margin, accuracy: 0.5)
        XCTAssertEqual(one.minX, Form.margin, accuracy: 0.5)
        XCTAssertEqual(one.width, boxWidth, accuracy: 0.5)
        XCTAssertEqual(one.minY - two.maxY, Form.boxSpacing, accuracy: 0.5)
        XCTAssertEqual(two.minY - three.maxY, Form.sectionSpacing, accuracy: 0.5)
        XCTAssertEqual(three.minY - foot.maxY, Form.sectionSpacing, accuracy: 0.5)
        XCTAssertEqual(foot.minY, Form.margin, accuracy: 0.5)

        // The section title: small, bold, over the box at the rows' inset.
        let title = try XCTUnwrap(titled.titleLabel)
        XCTAssertEqual(title.font, Form.sectionTitleFont)
        XCTAssertEqual(frame(of: title, in: root).minX, Form.margin + Form.rowHorizontalInset, accuracy: 0.5)
        XCTAssertEqual(frame(of: title, in: root).minY - frame(of: titled.box, in: root).maxY, Form.sectionTitleSpacing, accuracy: 0.5)
        XCTAssertNil(first.titleLabel)

        // The footer's button is a regular push button at the right edge.
        XCTAssertEqual(frame(of: button, in: root).maxX, paneWidth - Form.margin, accuracy: 1)
        XCTAssertEqual(button.bezelStyle, .push)
        XCTAssertEqual(button.controlSize, .regular)
    }
}
