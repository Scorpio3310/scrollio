//
//  PreferencesGroupedFormTests.swift
//  MosTests
//
//  The grouped-form kit (System Settings boxes): the numbers, how rows lay out their
//  title, explanation and control, the hairlines between the rows that show, dimming a
//  row, the accessibility names of its controls, the spacing of boxes, section titles
//  and the footer in a pane, and the list (PreferencesListBox): its rows, selection,
//  mouse, keyboard, footer, empty row, hairlines and accessibility. Nothing is shown on
//  screen.
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
        // Inside an NSVisualEffectView content draws in a vibrant appearance, where the
        // system fill is an opaque grey meant for blending. The box never takes it, even
        // where a pane would leave its content vibrant.
        let root = PreferencesForm.makeBackground(plainContent: false)
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

    /// The panes draw their content in the plain appearance, as System Settings does. In
    /// the vibrant one of the material a dimmed row's text was an opaque dark grey that
    /// nothing blended: on a dark box it almost disappeared.
    func testAPaneDrawsItsContentInThePlainAppearance() {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: paneWidth, height: 200))
        let root = PreferencesForm.makeBackground()
        host.addSubview(root)
        let content = Form.installContentStack(in: root, paneWidth: paneWidth)
        let row = PreferencesSwitchRow(title: "Strength", explanation: "Off while haptics are off.", target: nil, action: nil)
        row.isEnabled = false
        Form.add([PreferencesGroupSection(width: boxWidth, rows: [row])], to: content)

        for (window, plain) in [(NSAppearance.Name.aqua, NSAppearance.Name.aqua), (.darkAqua, .darkAqua), (.vibrantDark, .darkAqua)] {
            host.appearance = NSAppearance(named: window)
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(row.titleLabel.effectiveAppearance.name, plain, "in \(window.rawValue)")
            XCTAssertEqual(row.toggle.effectiveAppearance.name, plain, "in \(window.rawValue)")
            // Dimmed: the tertiary label colour of that appearance, a tint of the text colour
            // over the box (the vibrant one is an opaque grey, alpha 1).
            let title = resolve(row.titleLabel.textColor!, in: row.titleLabel.effectiveAppearance.name)
            let tertiary = resolve(.tertiaryLabelColor, in: plain)
            XCTAssertEqual(title.white, tertiary.white, accuracy: 0.001)
            XCTAssertEqual(title.alpha, tertiary.alpha, accuracy: 0.001)
            XCTAssertLessThan(title.alpha, 0.5)
        }

        // A pane that is not in the Preferences window keeps the material's vibrancy.
        let vibrant = PreferencesForm.makeBackground(plainContent: false)
        let label = NSTextField(labelWithString: "Welcome")
        vibrant.addSubview(label)
        host.addSubview(vibrant)
        host.appearance = NSAppearance(named: .darkAqua)
        XCTAssertEqual(label.effectiveAppearance.name, .vibrantDark)
    }

    /// Light stays light and dark stays dark; high contrast stays high contrast. (An
    /// appearance only reports high contrast while the system's setting is on, so here it
    /// may come back as the plain one.)
    func testThePlainAppearanceMatchesLightDarkAndHighContrast() throws {
        for (window, plain, highContrast) in [
            (NSAppearance.Name.vibrantLight, NSAppearance.Name.aqua, NSAppearance.Name.accessibilityHighContrastAqua),
            (.vibrantDark, .darkAqua, .accessibilityHighContrastDarkAqua),
            (.aqua, .aqua, .accessibilityHighContrastAqua),
            (.darkAqua, .darkAqua, .accessibilityHighContrastDarkAqua),
            (.accessibilityHighContrastVibrantDark, .darkAqua, .accessibilityHighContrastDarkAqua),
            (.accessibilityHighContrastAqua, .aqua, .accessibilityHighContrastAqua),
        ] {
            let appearance = try XCTUnwrap(NSAppearance(named: window))
            let reportsHighContrast = appearance.name.rawValue.contains("Accessibility")
            let expected = reportsHighContrast ? highContrast : plain
            XCTAssertEqual(PreferencesBackgroundView.plainAppearance(matching: appearance)?.name, expected, window.rawValue)
        }
    }

    /// Increase Contrast: the boxes get an outline and the preview cards a clear edge, as
    /// System Settings outlines its boxes.
    func testBoxesAndCardsAreOutlinedUnderIncreaseContrast() throws {
        let box = PreferencesGroupBox(width: 300, rows: [PreferencesGroupRow(title: "Row")])
        let list = PreferencesListBox(width: 300, emptyTitle: "Nothing yet")
        for view in [box, list] as [NSView] {
            view.appearance = NSAppearance(named: .aqua)
        }
        XCTAssertFalse(box.drawsOutline)
        XCTAssertFalse(list.drawsOutline)
        XCTAssertLessThan(resolve(ScrollPreviewPalette.cardEdge, in: .aqua).alpha, 0.1)
        XCTAssertLessThan(resolve(ScrollPreviewPalette.cardEdge, in: .darkAqua).alpha, 0.1)

        for name in [NSAppearance.Name.accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            // Some systems hand out the plain appearance while Increase Contrast is off.
            guard appearance.name.rawValue.contains("Accessibility") else { continue }
            box.appearance = appearance
            list.appearance = appearance
            XCTAssertTrue(box.drawsOutline, name.rawValue)
            XCTAssertTrue(list.drawsOutline, name.rawValue)
            XCTAssertGreaterThanOrEqual(resolve(ScrollPreviewPalette.cardEdge, in: name).alpha, 0.4, name.rawValue)
        }
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

    // MARK: - Tick marks and steps

    /// Counts the actions a control sends and remembers the value of the last one.
    private final class ActionRecorder: NSObject {
        var values: [Double] = []
        @objc func changed(_ sender: NSSlider) {
            values.append(sender.doubleValue)
        }
    }

    private func arrowKey(_ key: NSEvent.SpecialKey, keyCode: UInt16) throws -> NSEvent {
        let characters = String(Character(try XCTUnwrap(UnicodeScalar(key.rawValue))))
        return try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.numericPad, .function], timestamp: 0,
            windowNumber: 0, context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: keyCode
        ))
    }

    func testAScaleThatStopsOnlyOnItsTicks() {
        let scale = PreferencesSliderScale.ticksOnly(11)
        let range: ClosedRange<Double> = 0.5...3
        XCTAssertTrue(scale.stopsOnTicksOnly)
        XCTAssertEqual(scale.tickValues(in: range), [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75, 3])
        XCTAssertEqual(scale.step(in: range), 0.25)
        XCTAssertEqual(scale.snapped(1.3, in: range), 1.25)
        XCTAssertEqual(scale.snapped(1.38, in: range), 1.5)
        XCTAssertEqual(scale.snapped(-4, in: range), 0.5)
        XCTAssertEqual(scale.snapped(.nan, in: range), 0.5)
        // The knob shows a value between two ticks on the nearer one.
        XCTAssertEqual(scale.knobPosition(for: 1.3, in: range), 1.25)
        // One arrow key: the next tick, from a tick or from between two.
        XCTAssertEqual(scale.stepped(from: 1.25, by: 1, in: range), 1.5)
        XCTAssertEqual(scale.stepped(from: 1.25, by: -1, in: range), 1)
        XCTAssertEqual(scale.stepped(from: 1.3, by: 1, in: range), 1.5)
        XCTAssertEqual(scale.stepped(from: 1.3, by: -1, in: range), 1.25)
        XCTAssertEqual(scale.stepped(from: 3, by: 1, in: range), 3, "stays at the end")
        XCTAssertEqual(scale.stepped(from: 0.5, by: -1, in: range), 0.5)
        // A slider over indexes (the pointer speed's rungs).
        XCTAssertEqual(PreferencesSliderScale.ticksOnly(12).tickValues(in: 0...11), (0...11).map(Double.init))
    }

    func testAScaleWhoseValueMovesInFinerSteps() {
        let scale = PreferencesSliderScale.ticks(10, step: 0.5)
        let range: ClosedRange<Double> = 1...10
        XCTAssertFalse(scale.stopsOnTicksOnly)
        XCTAssertEqual(scale.tickValues(in: range), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
        XCTAssertEqual(scale.step(in: range), 0.5)
        XCTAssertEqual(scale.snapped(6.31, in: range), 6.5)
        XCTAssertEqual(scale.snapped(6.2, in: range), 6)
        XCTAssertEqual(scale.snapped(0, in: range), 1)
        // A stored value off the grid shows where it is.
        XCTAssertEqual(scale.knobPosition(for: 6.31, in: range), 6.31)
        XCTAssertEqual(scale.knobPosition(for: 42, in: range), 10)
        XCTAssertEqual(scale.stepped(from: 6.31, by: 1, in: range), 6.5)
        XCTAssertEqual(scale.stepped(from: 6.31, by: -1, in: range), 6)
        XCTAssertEqual(scale.stepped(from: 6.5, by: 1, in: range), 7)
        XCTAssertEqual(scale.stepped(from: 6.5, by: -2, in: range), 5.5)
        // Whole multiples of the step, so a range that starts off the grid still gets them.
        let step = PreferencesSliderScale.ticks(11, step: 1)
        XCTAssertEqual(step.snapped(12.34, in: 0.01...100), 12)
        XCTAssertEqual(step.snapped(0.2, in: 0.01...100), 0.01)
        XCTAssertEqual(step.stepped(from: 0.01, by: 1, in: 0.01...100), 1)
        XCTAssertEqual(step.stepped(from: 1, by: -1, in: 0.01...100), 0.01)
        // Tidy values, not floating-point noise.
        XCTAssertEqual(PreferencesSliderScale.ticks(9, step: 0.05).snapped(3.687, in: 1...5), 3.7)
        XCTAssertEqual(PreferencesSliderScale.ticks(9, step: 0.05).stepped(from: 3.7, by: -1, in: 1...5), 3.65)
    }

    func testASliderRowGetsTickMarksUnderItsTrack() {
        let fine = PreferencesSliderRow(title: "Speed", range: 1...10, scale: .ticks(10, step: 0.5), ends: (low: "Slow", high: "Fast"), target: nil, action: nil)
        XCTAssertEqual(fine.slider.numberOfTickMarks, 10)
        XCTAssertEqual(fine.slider.tickMarkPosition, .below)
        XCTAssertFalse(fine.slider.allowsTickMarkValuesOnly)
        XCTAssertEqual(fine.scale, .ticks(10, step: 0.5))

        let stops = PreferencesSliderRow(title: "Click", range: 0...100, scale: .ticksOnly(11), target: nil, action: nil)
        XCTAssertEqual(stops.slider.numberOfTickMarks, 11)
        XCTAssertEqual(stops.slider.tickMarkPosition, .below)
        XCTAssertTrue(stops.slider.allowsTickMarkValuesOnly)

        // A scale can change later (the Mouse tab learns the mouse's range), or go.
        stops.scale = .ticksOnly(5)
        XCTAssertEqual(stops.slider.numberOfTickMarks, 5)
        stops.scale = nil
        XCTAssertEqual(stops.slider.numberOfTickMarks, 0)
        XCTAssertFalse(stops.slider.allowsTickMarkValuesOnly)
        XCTAssertNil(PreferencesSliderRow(title: "Plain", range: 0...1, target: nil, action: nil).scale)
    }

    func testTickMarksLeaveTheRowAsItWas() throws {
        func makeRow(_ scale: PreferencesSliderScale?) -> PreferencesSliderRow {
            let row = PreferencesSliderRow(
                title: "Tracking speed", explanation: "How fast the pointer moves.", range: 1...10,
                scale: scale, ends: (low: "Slow", high: "Fast"), target: nil, action: nil
            )
            row.valueText = "6.3"
            return row
        }
        let plain = makeRow(nil)
        let ticked = makeRow(.ticks(10, step: 0.5))
        let switchRow = PreferencesSwitchRow(title: "Tap to click", explanation: "Tap with one finger.", target: nil, action: nil)
        let root = makePane([PreferencesGroupBox(width: boxWidth, rows: [plain, ticked, switchRow])])

        let plainRow = frame(of: plain, in: root)
        let tickedRow = frame(of: ticked, in: root)
        XCTAssertEqual(tickedRow.height, plainRow.height, accuracy: 0.5, "the ticks take no extra height")
        XCTAssertEqual(tickedRow.height, frame(of: switchRow, in: root).height, accuracy: 0.5, "as tall as a row with one line of explanation")

        let slider = frame(of: ticked.slider, in: root)
        let low = frame(of: try XCTUnwrap(ticked.lowEndLabel), in: root)
        let high = frame(of: try XCTUnwrap(ticked.highEndLabel), in: root)
        let value = frame(of: try XCTUnwrap(ticked.valueLabel), in: root)
        XCTAssertEqual(slider.midY, frame(of: ticked.titleLabel, in: root).midY, accuracy: 0.5, "the track on the title line")
        // The ticks are drawn inside the slider's frame, under the track; the words sit below it.
        XCTAssertEqual(slider.minY - low.maxY, Form.sliderEndsSpacing, accuracy: 0.5)
        XCTAssertEqual(high.minY, low.minY, accuracy: 0.5)
        XCTAssertEqual(low.minX, slider.minX, accuracy: 0.5)
        XCTAssertEqual(high.maxX, slider.maxX, accuracy: 0.5)
        XCTAssertEqual(value.midY, slider.midY, accuracy: 1)
        XCTAssertEqual(tickedRow.maxX - value.maxX, Form.rowHorizontalInset, accuracy: 1)
        XCTAssertEqual(frame(of: plain.valueLabel!, in: root).minX, value.minX, accuracy: 0.5, "the values line up")
    }

    func testArrowKeysMoveTheKnobOneStepAndSendTheAction() throws {
        let recorder = ActionRecorder()
        let row = PreferencesSliderRow(
            title: "Speed", range: 1...10, scale: .ticks(10, step: 0.5),
            target: recorder, action: #selector(ActionRecorder.changed(_:))
        )
        let slider = row.slider
        row.showValue(6.31)
        XCTAssertEqual(slider.doubleValue, 6.31, accuracy: 1e-9, "shown where it is")
        XCTAssertEqual(recorder.values, [], "showing sends nothing")

        slider.keyDown(with: try arrowKey(.rightArrow, keyCode: 124))
        XCTAssertEqual(recorder.values, [6.5])
        slider.keyDown(with: try arrowKey(.upArrow, keyCode: 126))
        XCTAssertEqual(recorder.values, [6.5, 7])
        slider.keyDown(with: try arrowKey(.leftArrow, keyCode: 123))
        slider.keyDown(with: try arrowKey(.downArrow, keyCode: 125))
        XCTAssertEqual(recorder.values, [6.5, 7, 6.5, 6])
        XCTAssertTrue(slider.accessibilityPerformIncrement())
        XCTAssertTrue(slider.accessibilityPerformDecrement())
        XCTAssertEqual(recorder.values, [6.5, 7, 6.5, 6, 6.5, 6])

        // At an end nothing more is sent; a slider that is off does not move.
        slider.doubleValue = 10
        slider.keyDown(with: try arrowKey(.rightArrow, keyCode: 124))
        XCTAssertEqual(recorder.values.count, 6)
        row.isEnabled = false
        slider.doubleValue = 5
        slider.keyDown(with: try arrowKey(.rightArrow, keyCode: 124))
        XCTAssertEqual(recorder.values.count, 6)
        XCTAssertEqual(slider.doubleValue, 5)

        // A slider that stops on its ticks moves from tick to tick.
        let stops = PreferencesSliderRow(
            title: "Click", range: 0...100, scale: .ticksOnly(11),
            target: recorder, action: #selector(ActionRecorder.changed(_:))
        )
        stops.showValue(72)
        XCTAssertEqual(stops.slider.doubleValue, 70, "between two ticks: on the nearer")
        stops.slider.keyDown(with: try arrowKey(.rightArrow, keyCode: 124))
        XCTAssertEqual(recorder.values.last, 80)
    }

    /// The slider knows when the user drags its own knob, and sends its action once more
    /// when it is let go, no longer tracking.
    func testASliderKnowsWhenItsKnobIsDragged() {
        let target = ActionCounter()
        let row = PreferencesSliderRow(title: "Speed", range: 0...10, scale: .ticks(11, step: 1), target: target, action: #selector(ActionCounter.act(_:)))
        let slider = row.slider
        XCTAssertFalse(slider.isTracking)
        XCTAssertFalse(row.isTracking)

        slider.beginTracking()
        XCTAssertTrue(row.isTracking)
        slider.doubleValue = 4.4
        XCTAssertTrue(slider.sendAction(slider.action, to: slider.target))
        XCTAssertEqual(target.trackingStates, [true])

        slider.endTracking()
        XCTAssertFalse(row.isTracking)
        XCTAssertEqual(target.trackingStates, [true, false], "let go: the action once more")
        XCTAssertEqual(target.values.last ?? -1, 4, accuracy: 1e-9)

        // Ending twice, or without a drag, sends nothing.
        slider.endTracking()
        XCTAssertEqual(target.trackingStates.count, 2)
        // An arrow key is a move outside a drag.
        XCTAssertTrue(slider.moveKnob(by: 1))
        XCTAssertEqual(target.trackingStates.last, false)
    }

    /// A press that does not move the knob changes nothing: no action goes out, so a stored
    /// value that is not on the scale is not rewritten (and nothing is passed on to a mouse).
    func testAPressThatDoesNotMoveTheKnobSendsNothing() {
        let target = ActionCounter()
        let row = PreferencesSliderRow(title: "Speed", range: 1...10, scale: .ticks(10, step: 0.5), target: target, action: #selector(ActionCounter.act(_:)))
        let slider = row.slider
        row.showValue(6.3)
        XCTAssertEqual(slider.doubleValue, 6.3, accuracy: 1e-9)

        // AppKit sends on the press and again when the button goes up, the knob where it was.
        slider.beginTracking()
        XCTAssertFalse(slider.sendAction(slider.action, to: slider.target))
        slider.endTracking()
        XCTAssertTrue(target.values.isEmpty, "nothing went out")
        XCTAssertEqual(slider.doubleValue, 6.3, accuracy: 1e-12, "not moved onto 6.5")
        XCTAssertFalse(slider.isTracking)

        // A knob that stops only on its marks shows 1.4 on the mark at 1: a press leaves 1.4 stored.
        let stops = PreferencesSliderRow(title: "Level", range: 0...4, scale: .ticksOnly(5), target: target, action: #selector(ActionCounter.act(_:)))
        stops.showValue(1.4)
        stops.slider.beginTracking()
        XCTAssertFalse(stops.slider.sendAction(stops.slider.action, to: stops.slider.target))
        stops.slider.endTracking()
        XCTAssertTrue(target.values.isEmpty)

        // Moved away and brought back in one drag: every move went out, the last one too.
        slider.beginTracking()
        slider.doubleValue = 7.2
        XCTAssertTrue(slider.sendAction(slider.action, to: slider.target))
        slider.doubleValue = 6.3
        XCTAssertTrue(slider.sendAction(slider.action, to: slider.target))
        slider.endTracking()
        XCTAssertEqual(target.values, [7, 6.5, 6.5])
        XCTAssertEqual(target.trackingStates, [true, true, false])
    }

    /// AppKit works the value out again from the knob's position when it is pressed: less
    /// than a point of travel is not a move.
    func testAPressMayShiftTheValueByLessThanAPointOfTravel() {
        XCTAssertEqual(PreferencesSlider.pressTolerance(span: 9, width: 200), 9.0 / 180 * 0.75, accuracy: 1e-12)
        XCTAssertEqual(PreferencesSlider.pressTolerance(span: 9, width: 0), 9e-9, accuracy: 1e-15, "no size yet: float noise only")
        XCTAssertEqual(PreferencesSlider.pressTolerance(span: 0, width: 200), 0)

        let target = ActionCounter()
        let row = PreferencesSliderRow(title: "Speed", range: 1...10, scale: .ticks(10, step: 0.5), target: target, action: #selector(ActionCounter.act(_:)))
        let slider = row.slider
        slider.frame = NSRect(x: 0, y: 0, width: 200, height: 24)
        row.showValue(6.3)
        slider.beginTracking()
        slider.doubleValue = 6.3 + 0.02   // under a point of travel (0.05 per point here)
        XCTAssertFalse(slider.sendAction(slider.action, to: slider.target))
        slider.endTracking()
        XCTAssertTrue(target.values.isEmpty)
        XCTAssertEqual(slider.doubleValue, 6.3, accuracy: 1e-12, "back exactly where it was")

        slider.beginTracking()
        slider.doubleValue = 6.3 + 0.06   // more than a point: a move
        XCTAssertTrue(slider.sendAction(slider.action, to: slider.target))
        slider.endTracking()
        XCTAssertEqual(target.values, [6.5, 6.5])
    }

    /// A slider that is off sends nothing, whatever happens to its knob.
    func testASliderThatIsOffSendsNothingWhenLetGo() {
        let target = ActionCounter()
        let row = PreferencesSliderRow(title: "Speed", range: 1...10, scale: .ticks(10, step: 0.5), target: target, action: #selector(ActionCounter.act(_:)))
        let slider = row.slider
        row.showValue(6.3)
        slider.beginTracking()
        slider.isEnabled = false
        slider.doubleValue = 8
        slider.endTracking()
        XCTAssertTrue(target.values.isEmpty)
        XCTAssertEqual(slider.doubleValue, 6.3, accuracy: 1e-12)
        XCTAssertFalse(slider.moveKnob(by: 1), "nor by an arrow key")
    }

    /// VoiceOver reads the value as it is written next to the slider.
    func testTheSliderSpeaksTheWrittenValue() {
        let row = PreferencesSliderRow(title: "Pointer speed", range: 0...11, scale: .ticksOnly(12), target: nil, action: nil)
        row.valueText = "1000 DPI"
        XCTAssertEqual(row.slider.accessibilityValueDescription(), "1000 DPI")
        row.valueText = ""
        XCTAssertNil(row.slider.accessibilityValueDescription())
    }

    func testADragDeliversValuesOfTheScale() {
        let recorder = ActionRecorder()
        let row = PreferencesSliderRow(
            title: "Speed", range: 1...10, scale: .ticks(10, step: 0.5),
            target: recorder, action: #selector(ActionRecorder.changed(_:))
        )
        for (dragged, delivered) in [(6.31, 6.5), (6.74, 6.5), (6.76, 7), (1.2, 1), (9.9, 10)] {
            row.slider.doubleValue = dragged
            XCTAssertTrue(row.slider.sendAction(row.slider.action, to: row.slider.target))
            XCTAssertEqual(recorder.values.last, delivered, "\(dragged)")
            XCTAssertEqual(row.slider.doubleValue, delivered, "the knob jumps with it")
        }

        // Without a scale the slider is as before: any value.
        let plain = PreferencesSliderRow(title: "Plain", range: 0...1, target: recorder, action: #selector(ActionRecorder.changed(_:)))
        plain.slider.doubleValue = 0.123
        XCTAssertTrue(plain.slider.sendAction(plain.slider.action, to: plain.slider.target))
        XCTAssertEqual(recorder.values.last, 0.123)
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

        // A pop-up shows its value: it is named by the row, also in a list, whose row
        // speaks for its title (VoiceOver: "Back button, Copy, pop-up button").
        let popUp = NSPopUpButton(frame: .zero, pullsDown: true)
        popUp.addItem(withTitle: "Copy")
        let listRow = PreferencesListRow(id: 1, title: "Back button", accessory: popUp)
        XCTAssertEqual(popUp.accessibilityLabel(), "Back button")
        XCTAssertFalse(listRow.titleLabel.isAccessibilityElement())
        listRow.title = "⌥ Back button"
        XCTAssertEqual(popUp.accessibilityLabel(), "⌥ Back button")
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

    // MARK: - List

    /// A list of rows "a", "b", "c" (texts "Row a" …) in a pane, laid out.
    private func makeList(
        ids: [String] = ["a", "b", "c"],
        explanation: String? = nil,
        emptyExplanation: String? = "Click + to add one."
    ) -> (list: PreferencesListBox, root: NSView) {
        let list = PreferencesListBox(
            width: boxWidth,
            rows: ids.map { PreferencesListRow(id: $0, title: "Row \($0)", explanation: explanation) },
            emptyTitle: "Nothing yet",
            emptyExplanation: emptyExplanation
        )
        let root = makePane([list])
        return (list, root)
    }

    /// Records what a list reports.
    private final class ListRecorder {
        var selected: [AnyHashable?] = []
        var removed: [AnyHashable] = []
        var opened: [AnyHashable] = []
        var hovered: [AnyHashable?] = []
        var added: [NSButton] = []

        init(_ list: PreferencesListBox) {
            list.onSelect = { [unowned self] in self.selected.append($0) }
            list.onRemove = { [unowned self] in self.removed.append($0) }
            list.onOpen = { [unowned self] in self.opened.append($0) }
            list.onHover = { [unowned self] in self.hovered.append($0) }
            list.onAdd = { [unowned self] in self.added.append($0) }
        }
    }

    /// A window that says whether it is key as the test wants. Never shown. A key nobody
    /// takes is noted instead of beeping.
    private final class TestWindow: NSWindow {
        var key = false
        private(set) var unhandledKeys = 0
        override var isKeyWindow: Bool { return key }
        override func keyDown(with event: NSEvent) {
            unhandledKeys += 1
        }
    }

    /// A control of a row that can have the keyboard (a pull-down does with Full Keyboard
    /// Access on).
    private final class FocusableControl: NSControl {
        override var acceptsFirstResponder: Bool { return true }
        override var intrinsicContentSize: NSSize { return NSSize(width: 40, height: 20) }
    }

    private func makeWindow(with root: NSView, key: Bool = false) -> TestWindow {
        let window = TestWindow(contentRect: root.frame, styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.key = key
        window.contentView = root
        root.layoutSubtreeIfNeeded()
        addTeardownBlock { window.close() }
        return window
    }

    private func key(_ characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        return try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
        ))
    }

    private func arrow(_ key: Int) throws -> NSEvent {
        let characters = String(Character(try XCTUnwrap(UnicodeScalar(key))))
        return try self.key(characters, keyCode: key == NSUpArrowFunctionKey ? 126 : 125, modifiers: [.numericPad, .function])
    }

    private func mouse(_ type: NSEvent.EventType, at point: NSPoint, in window: NSWindow, clicks: Int = 1) throws -> NSEvent {
        if type == .mouseEntered || type == .mouseExited {
            return try XCTUnwrap(NSEvent.enterExitEvent(
                with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, trackingNumber: 0, userData: nil
            ))
        }
        return try XCTUnwrap(NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: clicks, pressure: 1
        ))
    }

    /// Where a view's frame sits in `root` (buttons and image views: the frame, not the
    /// alignment rectangle).
    private func rawFrame(of view: NSView, in root: NSView) -> NSRect {
        return root.convert(view.frame, from: view.superview)
    }

    /// The middle of `view`, in the coordinates of `row`'s superview (what hitTest takes).
    private func point(of view: NSView, for row: NSView) -> NSPoint {
        return view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: row.superview)
    }

    func testAListRowPutsItsIconBeforeItsTextsAndItsChevronAtTheEdge() throws {
        let popUp = NSPopUpButton(frame: .zero, pullsDown: true)
        popUp.addItem(withTitle: "Copy")
        popUp.widthAnchor.constraint(equalToConstant: 240).isActive = true
        let symbol = PreferencesListRow(id: 1, title: "Back button", explanation: "Choose what this button does.", icon: .symbol("computermouse"), accessory: popUp)
        let app = PreferencesListRow(id: 2, title: "Calculator", explanation: "Own scrolling settings", icon: .image(NSImage(size: NSSize(width: 64, height: 64))), showsChevron: true)
        let plain = PreferencesListRow(id: 3, title: "Plain")
        let list = PreferencesListBox(width: boxWidth, rows: [symbol, app, plain], emptyTitle: "Nothing")
        let root = makePane([list])
        let box = frame(of: list, in: root)

        // A symbol: 20 pt, the texts after it.
        let symbolIcon = rawFrame(of: try XCTUnwrap(symbol.iconView), in: root)
        XCTAssertEqual(symbolIcon.size, NSSize(width: 20, height: 20))
        XCTAssertEqual(symbolIcon.minX - box.minX, Form.rowHorizontalInset, accuracy: 0.5)
        XCTAssertEqual(frame(of: symbol.titleLabel, in: root).minX - symbolIcon.maxX, PreferencesListRow.iconSpacing, accuracy: 0.5)
        XCTAssertEqual(frame(of: symbol.explanationLabel, in: root).minX, frame(of: symbol.titleLabel, in: root).minX, accuracy: 0.5)
        XCTAssertEqual(symbolIcon.midY, frame(of: symbol, in: root).midY, accuracy: 0.5, "in the middle of the row")
        XCTAssertEqual(symbol.iconView?.contentTintColor, .secondaryLabelColor)
        XCTAssertEqual(box.maxX - frame(of: popUp, in: root).maxX, Form.rowHorizontalInset, accuracy: 0.5, "the control at the edge")
        XCTAssertEqual(frame(of: popUp, in: root).midY, frame(of: symbol.titleLabel, in: root).midY, accuracy: 0.5)
        XCTAssertNil(symbol.chevronView)

        // An app's icon: 24 pt; the chevron at the right edge, in the tertiary colour.
        let appIcon = rawFrame(of: try XCTUnwrap(app.iconView), in: root)
        XCTAssertEqual(appIcon.size, NSSize(width: 24, height: 24))
        XCTAssertEqual(frame(of: app.titleLabel, in: root).minX - appIcon.maxX, PreferencesListRow.iconSpacing, accuracy: 0.5)
        let chevron = rawFrame(of: try XCTUnwrap(app.chevronView), in: root)
        XCTAssertEqual(box.maxX - chevron.maxX, Form.rowHorizontalInset, accuracy: 0.5)
        XCTAssertEqual(chevron.midY, frame(of: app, in: root).midY, accuracy: 0.5)
        XCTAssertEqual(app.chevronView?.contentTintColor, .tertiaryLabelColor)
        XCTAssertEqual(
            app.titleColumnWidth,
            boxWidth - 2 * Form.rowHorizontalInset - 24 - PreferencesListRow.iconSpacing - PreferencesListRow.chevronWidth - PreferencesListRow.chevronSpacing,
            accuracy: 0.5
        )

        // Without an icon the texts start at the rows' inset, as in a box.
        XCTAssertNil(plain.iconView)
        XCTAssertEqual(frame(of: plain.titleLabel, in: root).minX - box.minX, Form.rowHorizontalInset, accuracy: 0.5)
        XCTAssertEqual(plain.frame.height, 2 * Form.rowVerticalInset + titleLineHeight(), accuracy: 0.5)

        // The box is as tall as its rows and the footer: nothing scrolls inside it.
        let rowsHeight = [symbol, app, plain].map(\.frame.height).reduce(0, +)
        XCTAssertEqual(list.frame.height, rowsHeight + PreferencesListBox.footerHeight, accuracy: 0.5)
        XCTAssertTrue(list.isFlipped)
        XCTAssertEqual(list.rows, [symbol, app, plain])
        XCTAssertTrue(list.rows.allSatisfy { $0.contentWidth == boxWidth })
    }

    func testAListKeepsItsSelectionByIDAcrossNewRows() {
        let (list, root) = makeList()
        let recorder = ListRecorder(list)
        XCTAssertNil(list.selectedID)
        XCTAssertFalse(list.removeButton.isEnabled, "− is off while nothing is selected")
        XCTAssertTrue(list.addButton.isEnabled)

        list.select("b")
        XCTAssertEqual(list.selectedID, "b")
        XCTAssertTrue(list.selectedRow === list.rows[1])
        XCTAssertEqual(list.rows.map(\.isSelected), [false, true, false])
        XCTAssertTrue(list.removeButton.isEnabled)
        XCTAssertEqual(recorder.selected, ["b"])
        list.select("b")
        XCTAssertEqual(recorder.selected, ["b"], "no change, no call")

        // New row objects with the same ids: "b" stays selected, nothing is reported.
        list.setRows(["c", "b", "a"].map { PreferencesListRow(id: $0, title: "New \($0)") })
        root.layoutSubtreeIfNeeded()
        XCTAssertEqual(list.selectedID, "b")
        XCTAssertEqual(list.selectedRow?.title, "New b")
        XCTAssertEqual(list.rows.map(\.isSelected), [false, true, false])
        XCTAssertEqual(recorder.selected, ["b"])

        // Without "b": nothing is selected, and the owner hears it.
        list.setRows(["c", "a"].map { PreferencesListRow(id: $0, title: "Row \($0)") })
        XCTAssertNil(list.selectedID)
        XCTAssertEqual(recorder.selected, ["b", nil])
        XCTAssertFalse(list.removeButton.isEnabled)
        XCTAssertTrue(list.rows.allSatisfy { !$0.isSelected })

        // An id the list does not have selects nothing; ids of any hashable type.
        list.select("a")
        list.select("zzz")
        XCTAssertNil(list.selectedID)
        XCTAssertEqual(recorder.selected, ["b", nil, "a", nil])
        list.setRows([PreferencesListRow(id: 7, title: "Seven"), PreferencesListRow(id: URL(fileURLWithPath: "/Applications/Safari.app"), title: "Safari")])
        list.select(URL(fileURLWithPath: "/Applications/Safari.app"))
        XCTAssertEqual(list.selectedRow?.title, "Safari")
        XCTAssertNil(list.row(withID: "7"), "7 the number, not the text")
        XCTAssertNotNil(list.row(withID: 7))
    }

    func testAClickOnARowSelectsItAndADoubleClickOpensIt() throws {
        let popUp = NSPopUpButton(frame: .zero, pullsDown: true)
        popUp.addItem(withTitle: "Copy")
        let info = NSButton(image: try XCTUnwrap(NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)), target: nil, action: nil)
        info.isBordered = false
        let accessory = NSStackView(views: [info, popUp])
        let rows = [
            PreferencesListRow(id: "a", title: "Row a", explanation: "First.", icon: .symbol("star"), accessory: accessory, centeredOn: popUp, controls: [popUp]),
            PreferencesListRow(id: "b", title: "Row b", showsChevron: true),
        ]
        let list = PreferencesListBox(width: boxWidth, rows: rows, emptyTitle: "Nothing")
        let root = makePane([list])
        let window = makeWindow(with: root)
        let recorder = ListRecorder(list)
        let row = rows[0]

        // The texts, the icon and the empty part of the accessory belong to the row; its
        // controls keep their clicks.
        XCTAssertTrue(row.hitTest(point(of: row.titleLabel, for: row)) === row)
        XCTAssertTrue(row.hitTest(point(of: row.explanationLabel, for: row)) === row)
        XCTAssertTrue(row.hitTest(point(of: try XCTUnwrap(row.iconView), for: row)) === row)
        XCTAssertTrue(row.hitTest(point(of: popUp, for: row)) === popUp)
        XCTAssertTrue(row.hitTest(point(of: info, for: row)) === info)
        XCTAssertTrue(rows[1].hitTest(point(of: try XCTUnwrap(rows[1].chevronView), for: rows[1])) === rows[1])
        popUp.isEnabled = false
        XCTAssertTrue(row.hitTest(point(of: popUp, for: row)) === row, "a control that is off gives the click to the row")
        popUp.isEnabled = true

        // A click selects the row and puts the keyboard on the list.
        let middle = row.convert(NSPoint(x: row.bounds.midX, y: row.bounds.midY), to: nil)
        row.mouseDown(with: try mouse(.leftMouseDown, at: middle, in: window))
        XCTAssertEqual(list.selectedID, "a")
        XCTAssertTrue(window.firstResponder === list)
        XCTAssertEqual(recorder.selected, ["a"])
        XCTAssertEqual(recorder.opened, [])

        // The second click of a double click opens it.
        row.mouseDown(with: try mouse(.leftMouseDown, at: middle, in: window, clicks: 2))
        XCTAssertEqual(recorder.opened, ["a"])
        XCTAssertEqual(recorder.selected, ["a"])
    }

    func testTheKeyboardMovesRemovesAndOpens() throws {
        let (list, root) = makeList()
        let window = makeWindow(with: root)
        XCTAssertTrue(window.makeFirstResponder(list))
        let recorder = ListRecorder(list)
        XCTAssertTrue(list.acceptsFirstResponder)
        let down = try arrow(NSDownArrowFunctionKey)
        let up = try arrow(NSUpArrowFunctionKey)

        // From nothing: ↓ the first row, ↑ the last.
        list.keyDown(with: down)
        XCTAssertEqual(list.selectedID, "a")
        list.select(nil)
        list.keyDown(with: up)
        XCTAssertEqual(list.selectedID, "c")
        list.keyDown(with: down)
        XCTAssertEqual(list.selectedID, "c", "stays at the end")
        list.keyDown(with: up)
        list.keyDown(with: up)
        list.keyDown(with: up)
        XCTAssertEqual(list.selectedID, "a", "stays at the top")
        XCTAssertEqual(recorder.selected, ["a", nil, "c", "b", "a"])

        // Delete and Forward Delete ask to remove the selected row; Return and Enter open it.
        list.keyDown(with: try key("\u{7F}", keyCode: 51))
        list.keyDown(with: try key(String(Character(try XCTUnwrap(UnicodeScalar(NSDeleteFunctionKey)))), keyCode: 117, modifiers: [.function]))
        list.keyDown(with: try key("\u{7F}", keyCode: 51, modifiers: [.command]))
        XCTAssertEqual(recorder.removed, ["a", "a", "a"])
        list.keyDown(with: try key("\r", keyCode: 36))
        list.keyDown(with: try key("\u{3}", keyCode: 76))
        XCTAssertEqual(recorder.opened, ["a", "a"])
        XCTAssertEqual(list.rows.count, 3, "the owner removes rows, not the list")

        // With nothing selected Delete does nothing.
        list.select(nil)
        list.keyDown(with: try key("\u{7F}", keyCode: 51))
        XCTAssertEqual(recorder.removed.count, 3)
    }

    /// Delete pressed in a control of a row (its pull-down) reaches the list through the
    /// responder chain: it removes nothing, and goes on. Only the list itself removes.
    func testDeleteInAControlOfARowRemovesNothing() throws {
        let control = FocusableControl(frame: NSRect(x: 0, y: 0, width: 40, height: 20))
        control.translatesAutoresizingMaskIntoConstraints = false
        let rows = [
            PreferencesListRow(id: "a", title: "Row a", accessory: control, controls: [control]),
            PreferencesListRow(id: "b", title: "Row b"),
        ]
        let list = PreferencesListBox(width: boxWidth, rows: rows, emptyTitle: "Nothing")
        let window = makeWindow(with: makePane([list]))
        let recorder = ListRecorder(list)
        list.select("a")
        let delete = try key("\u{7F}", keyCode: 51)

        XCTAssertTrue(window.makeFirstResponder(control))
        control.keyDown(with: delete)
        XCTAssertEqual(recorder.removed, [], "the row's control has the keyboard")
        XCTAssertEqual(window.unhandledKeys, 1, "passed on")
        list.keyDown(with: try key(String(Character(try XCTUnwrap(UnicodeScalar(NSDeleteFunctionKey)))), keyCode: 117, modifiers: [.function]))
        XCTAssertEqual(recorder.removed, [])

        // Nothing has the keyboard, or the window is gone: nothing either.
        window.makeFirstResponder(nil)
        list.keyDown(with: delete)
        XCTAssertEqual(recorder.removed, [])

        XCTAssertTrue(window.makeFirstResponder(list))
        list.keyDown(with: delete)
        XCTAssertEqual(recorder.removed, ["a"])
    }

    func testTheFooterHasAddAndRemoveAndRoomOnTheRight() throws {
        let (list, root) = makeList()
        let recorder = ListRecorder(list)
        let box = frame(of: list, in: root)
        let footer = frame(of: list.footerView, in: root)
        let add = rawFrame(of: list.addButton, in: root)
        let remove = rawFrame(of: list.removeButton, in: root)

        // Inside the box, at its bottom, 28 pt; + and − at its left, 24 × 22 each.
        XCTAssertEqual(footer.height, PreferencesListBox.footerHeight, accuracy: 0.5)
        XCTAssertEqual(footer.minY, box.minY, accuracy: 0.5)
        XCTAssertEqual(footer.width, box.width, accuracy: 0.5)
        XCTAssertEqual(add.size, PreferencesListBox.footerButtonSize)
        XCTAssertEqual(remove.size, PreferencesListBox.footerButtonSize)
        XCTAssertEqual(add.minX - box.minX, PreferencesListBox.footerButtonInset, accuracy: 0.5)
        XCTAssertEqual(remove.minX - add.maxX, 1, accuracy: 0.5, "room for the hairline between them")
        XCTAssertEqual(add.midY, footer.midY, accuracy: 0.5)
        XCTAssertEqual(remove.midY, footer.midY, accuracy: 0.5)
        for (button, symbol) in [(list.addButton, "plus"), (list.removeButton, "minus")] {
            XCTAssertFalse(button.isBordered)
            XCTAssertEqual(button.imagePosition, .imageOnly)
            XCTAssertNotNil(button.image, symbol)
            XCTAssertEqual(button.title, "")
        }

        // + reports itself (to anchor a menu on); − the selected row, and only then.
        XCTAssertTrue(list.addButton.sendAction(list.addButton.action, to: list.addButton.target))
        XCTAssertEqual(recorder.added.count, 1)
        XCTAssertTrue(recorder.added.first === list.addButton)
        XCTAssertFalse(list.removeButton.isEnabled)
        list.select("c")
        XCTAssertTrue(list.removeButton.isEnabled)
        XCTAssertTrue(list.removeButton.sendAction(list.removeButton.action, to: list.removeButton.target))
        XCTAssertEqual(recorder.removed, ["c"])

        // A view on the right: at the rows' inset from the edge, centred in the bar.
        let busy = NSTextField(labelWithString: "Checking…")
        list.footerAccessory = busy
        root.layoutSubtreeIfNeeded()
        XCTAssertTrue(busy.superview === list.footerView)
        XCTAssertEqual(frame(of: list, in: root).maxX - frame(of: busy, in: root).maxX, Form.rowHorizontalInset, accuracy: 0.5)
        XCTAssertEqual(frame(of: busy, in: root).midY, frame(of: list.footerView, in: root).midY, accuracy: 0.5)
        list.footerAccessory = nil
        XCTAssertNil(busy.superview)
    }

    func testAListWithoutRowsShowsItsEmptyRow() throws {
        let (list, root) = makeList(ids: [])
        let recorder = ListRecorder(list)
        let empty = list.emptyRow
        XCTAssertTrue(empty.superview === list.rowsView)
        XCTAssertEqual(list.rowsView.arrangedSubviews, [empty])
        XCTAssertEqual(empty.title, "Nothing yet")
        XCTAssertEqual(empty.explanation, "Click + to add one.")

        // Centred, in the secondary colour (readable: it says what to do), with more room
        // than a row.
        let box = frame(of: list, in: root)
        let title = frame(of: empty.titleLabel, in: root)
        let explanation = frame(of: empty.explanationLabel, in: root)
        XCTAssertEqual(title.midX, box.midX, accuracy: 1)
        XCTAssertEqual(explanation.midX, box.midX, accuracy: 1)
        XCTAssertEqual(empty.titleLabel.textColor, .secondaryLabelColor)
        XCTAssertEqual(empty.explanationLabel.textColor, .secondaryLabelColor)
        XCTAssertEqual(empty.titleLabel.font, Form.titleFont)
        XCTAssertEqual(empty.explanationLabel.font, Form.explanationFont)
        XCTAssertEqual(frame(of: empty, in: root).maxY - title.maxY, PreferencesListBox.emptyRowVerticalInset, accuracy: 0.5)
        XCTAssertEqual(explanation.minY - frame(of: empty, in: root).minY, PreferencesListBox.emptyRowVerticalInset, accuracy: 0.5)

        // It cannot be selected, by key or in code, and the pointer over it is over no row.
        list.keyDown(with: try arrow(NSDownArrowFunctionKey))
        list.select("a")
        XCTAssertNil(list.selectedID)
        XCTAssertEqual(recorder.selected, [])
        XCTAssertFalse(list.removeButton.isEnabled)
        XCTAssertNil(list.rowID(at: list.convert(NSPoint(x: empty.bounds.midX, y: empty.bounds.midY), from: empty)))
        XCTAssertEqual(list.separatorRects, [])

        // Rows replace it, and it comes back when they go.
        list.setRows([PreferencesListRow(id: "a", title: "Row a")])
        XCTAssertNil(empty.superview)
        list.setRows([])
        XCTAssertTrue(empty.superview === list.rowsView)
        empty.explanation = nil
        XCTAssertTrue(empty.explanationLabel.isHidden)
        XCTAssertEqual(empty.accessibilityLabel(), "Nothing yet")
    }

    func testAListDrawsHairlinesBetweenItsRowsButNotNextToTheSelection() throws {
        let (list, root) = makeList(explanation: "Explained.")
        let rows = list.rows
        func top(of row: NSView) -> CGFloat {
            return list.convert(row.bounds, from: row).minY
        }

        var lines = list.separatorRects
        XCTAssertEqual(lines.count, 2)
        for (line, row) in zip(lines, rows.dropFirst()) {
            XCTAssertEqual(line.minX, Form.rowHorizontalInset)
            XCTAssertEqual(line.maxX, boxWidth - Form.rowHorizontalInset, accuracy: 0.01)
            XCTAssertEqual(line.minY, top(of: row), accuracy: 0.5)
            XCTAssertLessThanOrEqual(line.height, 1)
        }
        XCTAssertNil(list.selectionRect)

        // The selection: inset in its row, rounded like the box; the lines next to it go.
        list.select("b")
        let selection = try XCTUnwrap(list.selectionRect)
        let row = list.convert(rows[1].bounds, from: rows[1])
        XCTAssertEqual(selection, row.insetBy(dx: PreferencesListBox.selectionInset, dy: PreferencesListBox.selectionInset))
        XCTAssertEqual(PreferencesListBox.selectionCornerRadius, Form.boxCornerRadius - PreferencesListBox.selectionInset)
        XCTAssertEqual(list.separatorRects, [])
        list.select("a")
        lines = list.separatorRects
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].minY, top(of: rows[2]), accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(list.selectionRect).minY, PreferencesListBox.selectionInset, accuracy: 0.5, "the first row's selection is inset from the box's top")

        // The footer's line runs across the whole box; a short one stands between + and −.
        let footerLine = list.footerSeparatorRect
        XCTAssertEqual(footerLine.minX, 0)
        XCTAssertEqual(footerLine.width, boxWidth, accuracy: 0.01)
        XCTAssertEqual(footerLine.minY, list.convert(list.footerView.bounds, from: list.footerView).minY, accuracy: 0.5)
        let divider = list.footerDividerRect
        XCTAssertEqual(divider.minX, list.convert(list.addButton.bounds, from: list.addButton).maxX, accuracy: 0.5)
        XCTAssertEqual(divider.height, PreferencesListBox.footerDividerHeight)
        XCTAssertLessThanOrEqual(divider.width, 1)
        XCTAssertEqual(divider.midY, list.convert(list.footerView.bounds, from: list.footerView).midY, accuracy: 0.5)
        _ = root
    }

    func testTheSelectionIsEmphasizedOnlyWhileTheWindowIsKey() throws {
        let popUp = NSPopUpButton(frame: .zero, pullsDown: true)
        popUp.addItem(withTitle: "Copy")
        let rows = [
            PreferencesListRow(id: "a", title: "Row a", explanation: "First.", icon: .symbol("star"), accessory: popUp, showsChevron: true),
            PreferencesListRow(id: "b", title: "Row b", explanation: "Second."),
        ]
        let list = PreferencesListBox(width: boxWidth, rows: rows, emptyTitle: "Nothing")
        let root = makePane([list])
        let window = makeWindow(with: root, key: true)
        root.appearance = NSAppearance(named: .aqua)
        XCTAssertTrue(list.isSelectionEmphasized)
        list.select("a")
        let row = rows[0]

        // On the accent colour: the texts, the symbol and the chevron turn white, the
        // controls draw as on a dark box.
        XCTAssertTrue(row.isHighlighted)
        XCTAssertFalse(rows[1].isHighlighted)
        let white = NSColor.alternateSelectedControlTextColor
        XCTAssertEqual(resolve(try XCTUnwrap(row.titleLabel.textColor), in: .aqua).white, 1, accuracy: 0.001)
        XCTAssertEqual(resolve(try XCTUnwrap(row.titleLabel.textColor), in: .aqua).alpha, 1, accuracy: 0.001)
        XCTAssertEqual(resolve(try XCTUnwrap(row.explanationLabel.textColor), in: .aqua).white, 1, accuracy: 0.001)
        XCTAssertEqual(resolve(try XCTUnwrap(row.explanationLabel.textColor), in: .aqua).alpha, 0.85, accuracy: 0.001)
        XCTAssertEqual(row.iconView?.contentTintColor, white)
        XCTAssertEqual(row.chevronView?.contentTintColor, white)
        XCTAssertEqual(popUp.effectiveAppearance.name, .darkAqua)
        XCTAssertEqual(rows[1].titleLabel.textColor, .labelColor)

        // The window goes behind another: a grey selection, the usual colours.
        window.key = false
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        XCTAssertFalse(list.isSelectionEmphasized)
        XCTAssertTrue(row.isSelected)
        XCTAssertFalse(row.isHighlighted)
        XCTAssertEqual(row.titleLabel.textColor, .labelColor)
        XCTAssertEqual(row.explanationLabel.textColor, .secondaryLabelColor)
        XCTAssertEqual(row.iconView?.contentTintColor, .secondaryLabelColor)
        XCTAssertEqual(row.chevronView?.contentTintColor, .tertiaryLabelColor)
        XCTAssertNil(popUp.appearance)
        XCTAssertNotNil(list.selectionRect, "still selected")

        // Back in front; a dimmed row stays dimmed, readable on the selection too.
        window.key = true
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        XCTAssertTrue(row.isHighlighted)
        row.isEnabled = false
        XCTAssertEqual(resolve(try XCTUnwrap(row.titleLabel.textColor), in: .aqua).white, 1, accuracy: 0.001)
        XCTAssertEqual(resolve(try XCTUnwrap(row.titleLabel.textColor), in: .aqua).alpha, 0.5, accuracy: 0.001)
        XCTAssertFalse(popUp.isEnabled)
        list.select("b")
        XCTAssertEqual(row.titleLabel.textColor, .tertiaryLabelColor)
        XCTAssertEqual(row.iconView?.contentTintColor, .tertiaryLabelColor)

        // The rows draw in the plain appearance of the pane, not the vibrant one.
        XCTAssertEqual(row.titleLabel.effectiveAppearance.name, .aqua)
        XCTAssertEqual(PreferencesListBox.selectionColor.usingColorSpace(.sRGB)?.alphaComponent, 1)
    }

    func testTheListReportsTheRowUnderThePointer() throws {
        let (list, root) = makeList()
        let window = makeWindow(with: root)
        let recorder = ListRecorder(list)
        func middle(of view: NSView) -> NSPoint {
            return view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
        }
        list.mouseEntered(with: try mouse(.mouseEntered, at: middle(of: list.rows[0]), in: window))
        list.mouseMoved(with: try mouse(.mouseMoved, at: middle(of: list.rows[0]), in: window))
        list.mouseMoved(with: try mouse(.mouseMoved, at: middle(of: list.rows[2]), in: window))
        list.mouseMoved(with: try mouse(.mouseMoved, at: middle(of: list.footerView), in: window))
        list.mouseMoved(with: try mouse(.mouseMoved, at: middle(of: list.rows[1]), in: window))
        list.mouseExited(with: try mouse(.mouseExited, at: .zero, in: window))
        XCTAssertEqual(recorder.hovered, ["a", "c", nil, "b", nil], "once per change")
        XCTAssertNil(list.hoveredID)
        XCTAssertEqual(recorder.selected, [], "hovering selects nothing")
    }

    func testAListSpeaksAsAListOfSelectableRows() throws {
        let (list, _) = makeList(explanation: "Explained.")
        let recorder = ListRecorder(list)
        let rows = list.rows
        let rowsView = list.rowsView
        XCTAssertTrue(rowsView.isAccessibilityElement())
        XCTAssertEqual(rowsView.accessibilityRole(), .list)
        XCTAssertEqual((rowsView.accessibilityChildren() as? [PreferencesListRow]) ?? [], rows)
        XCTAssertEqual((rowsView.accessibilityRows() as? [PreferencesListRow]) ?? [], rows)
        XCTAssertEqual((rowsView.accessibilitySelectedRows() as? [PreferencesListRow]) ?? [], [])

        // A row: named by its title and explanation; the texts are not read twice.
        let row = rows[1]
        XCTAssertTrue(row.isAccessibilityElement())
        XCTAssertEqual(row.accessibilityRole(), .row)
        XCTAssertEqual(row.accessibilityLabel(), "Row b, Explained.")
        XCTAssertEqual(row.accessibilityIndex(), 1)
        XCTAssertFalse(row.titleLabel.isAccessibilityElement())
        XCTAssertFalse(row.explanationLabel.isAccessibilityElement())
        row.explanation = nil
        XCTAssertEqual(row.accessibilityLabel(), "Row b")

        // VoiceOver selects through the row or through the list.
        XCTAssertFalse(row.isAccessibilitySelected())
        row.setAccessibilitySelected(true)
        XCTAssertEqual(list.selectedID, "b")
        XCTAssertTrue(row.isAccessibilitySelected())
        XCTAssertEqual((rowsView.accessibilitySelectedRows() as? [PreferencesListRow]) ?? [], [row])
        rowsView.setAccessibilitySelectedRows([rows[2]])
        XCTAssertEqual(list.selectedID, "c")
        row.setAccessibilitySelected(false)
        XCTAssertEqual(list.selectedID, "c", "unselecting another row changes nothing")
        XCTAssertTrue(rows[0].accessibilityPerformPress())
        XCTAssertEqual(list.selectedID, "a")
        XCTAssertEqual(recorder.selected, ["b", "c", "a"])
        XCTAssertEqual(recorder.opened, [], "a row without a chevron only selects")

        // A row that opens a page opens when pressed.
        let drill = PreferencesListRow(id: "d", title: "Calculator", showsChevron: true)
        list.setRows([drill])
        XCTAssertTrue(drill.accessibilityPerformPress())
        XCTAssertEqual(recorder.opened, ["d"])

        // The footer's buttons and the list's title.
        XCTAssertEqual(list.addButton.accessibilityLabel(), "Add")
        XCTAssertEqual(list.removeButton.accessibilityLabel(), "Remove")
        let section = PreferencesListSection(title: "Apps", list: list)
        XCTAssertEqual(rowsView.accessibilityLabel(), "Apps")
        XCTAssertEqual(section.titleLabel?.stringValue, "Apps")

        // Empty: the list holds the empty row, which reads its texts.
        list.setRows([])
        XCTAssertEqual(rowsView.accessibilityChildren()?.count, 1)
        XCTAssertTrue(rowsView.accessibilityChildren()?.first as? PreferencesListEmptyRow === list.emptyRow)
        XCTAssertEqual(list.emptyRow.accessibilityRole(), .staticText)
        XCTAssertEqual(list.emptyRow.accessibilityLabel(), "Nothing yet, Click + to add one.")
        XCTAssertEqual((rowsView.accessibilityRows() as? [PreferencesListRow]) ?? [], [])
    }

    func testAListSectionSitsInThePaneLikeATitledBox() throws {
        let first = PreferencesGroupSection(width: boxWidth, rows: [PreferencesSwitchRow(title: "Limit", target: nil, action: nil)])
        let list = PreferencesListBox(width: boxWidth, rows: [PreferencesListRow(id: 1, title: "Calculator")], emptyTitle: "No apps yet")
        let section = PreferencesListSection(title: "Apps", list: list)
        let untitled = PreferencesListBox(width: boxWidth, emptyTitle: "No buttons yet")
        let root = makePane([first, section, untitled])

        let title = try XCTUnwrap(section.titleLabel)
        XCTAssertEqual(title.font, Form.sectionTitleFont)
        XCTAssertEqual(frame(of: first, in: root).minY - frame(of: section, in: root).maxY, Form.sectionSpacing, accuracy: 0.5)
        XCTAssertEqual(frame(of: title, in: root).minX, Form.margin + Form.rowHorizontalInset, accuracy: 0.5)
        XCTAssertEqual(frame(of: title, in: root).minY - frame(of: list, in: root).maxY, Form.sectionTitleSpacing, accuracy: 0.5)
        XCTAssertEqual(frame(of: list, in: root).width, boxWidth, accuracy: 0.5)
        XCTAssertEqual(frame(of: section, in: root).minY - frame(of: untitled, in: root).maxY, Form.boxSpacing, accuracy: 0.5, "an untitled list is spaced like a box")
        XCTAssertNil(PreferencesListSection(list: PreferencesListBox(width: boxWidth, emptyTitle: "x")).titleLabel)
    }

    func testFlashingARowSelectsItAndBlinksItsSelection() {
        let (list, _) = makeList()
        list.flash("b")
        XCTAssertEqual(list.selectedID, "b")
        XCTAssertNotNil(list.selectionRect)
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        /// Runs the main queue for `seconds`.
        func wait(_ seconds: TimeInterval) {
            let done = expectation(description: "\(seconds) s")
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { done.fulfill() }
            self.wait(for: [done], timeout: seconds + 2)
        }

        wait(0.18)
        XCTAssertNil(list.selectionRect, "blinked off")
        XCTAssertEqual(list.selectedRow?.isSelected, false)
        XCTAssertEqual(list.selectedID, "b", "still the selection")
        wait(0.6)
        XCTAssertNotNil(list.selectionRect, "on again at the end")
        XCTAssertEqual(list.selectedRow?.isSelected, true)

        // Another selection during a blink shows at once and ends the blink.
        list.flash("b")
        wait(0.18)
        XCTAssertNil(list.selectionRect)
        list.select("c")
        XCTAssertNotNil(list.selectionRect)
        XCTAssertEqual(list.selectedRow?.isSelected, true)
        wait(0.5)
        XCTAssertEqual(list.selectedID, "c")
        XCTAssertNotNil(list.selectionRect)
        XCTAssertEqual(list.rows.map(\.isSelected), [false, false, true])
    }
}

/// Records what a slider's action saw.
private final class ActionCounter: NSObject {
    private(set) var trackingStates: [Bool] = []
    private(set) var values: [Double] = []

    @objc func act(_ sender: PreferencesSlider) {
        trackingStates.append(sender.isTracking)
        values.append(sender.doubleValue)
    }
}
