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
