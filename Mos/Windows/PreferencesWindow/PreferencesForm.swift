//
//  PreferencesForm.swift
//  Mos
//  Layout kit for the preference panes that are built in code. It repeats the grid of
//  the storyboard panes (450 pt wide, 20 pt margins, a right-aligned label column and a
//  control column that starts at x = 171), so every pane lines up with the others.
//

import Cocoa

enum PreferencesForm {

    // MARK: - Grid

    /// Width of every preferences pane.
    static let contentWidth: CGFloat = 450
    /// Between the pane's edges and its content.
    static let margin: CGFloat = 20
    /// Right-aligned row titles on the left, controls to their right.
    static let labelWidth: CGFloat = 136
    static let columnSpacing: CGFloat = 15
    /// 259 pt: the control column runs from x = 171 to the right margin.
    static let controlWidth = contentWidth - 2 * margin - labelWidth - columnSpacing
    /// Between two rows.
    static let rowSpacing: CGFloat = 17
    /// Above and below a separator.
    static let separatorSpacing: CGFloat = 18
    /// Between a control and the hint under it.
    static let hintSpacing: CGFloat = 6
    /// Between two options (checkbox + hint) of one row.
    static let optionSpacing: CGFloat = 12
    static let sliderWidth: CGFloat = 180
    static let valueLabelWidth: CGFloat = 44

    // MARK: - Type

    /// Size of the secondary text under a control: 11 pt, the small system font, like the
    /// hints of the storyboard panes. One constant for every pane built in code.
    static let hintFontSize: CGFloat = NSFont.smallSystemFontSize

    static var hintFont: NSFont {
        return NSFont.systemFont(ofSize: hintFontSize)
    }

    /// Row titles in the label column.
    static var labelFont: NSFont {
        return NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    }

    static var sectionHeaderFont: NSFont {
        return NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
    }

    // MARK: - Pane

    /// Same background as the storyboard panes. With `plainContent` (the panes of the
    /// Preferences window) what stands on it draws in the plain light or dark appearance,
    /// as in System Settings, not in the vibrant one of the material
    /// (`PreferencesBackgroundView`).
    static func makeBackground(plainContent: Bool = true) -> NSVisualEffectView {
        let root = plainContent ? PreferencesBackgroundView() : NSVisualEffectView()
        root.blendingMode = .behindWindow
        root.material = .toolTip
        root.state = .followsWindowActiveState
        return root
    }

    /// The vertical stack that holds a pane's rows, pinned inside `root` with the margins.
    /// Its width fixes the pane at `contentWidth`.
    static func installContentStack(in root: NSView) -> NSStackView {
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = rowSpacing
        content.detachesHiddenViews = true
        content.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: root.topAnchor, constant: margin),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: margin),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -margin),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -margin),
            content.widthAnchor.constraint(equalToConstant: contentWidth - 2 * margin),
        ])
        return content
    }

    /// Adds rows, separators and section headers to the content stack, each as wide as the stack.
    static func add(_ rows: [NSView], to content: NSStackView) {
        for row in rows {
            content.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
    }

    /// Gives every separator of the content stack its spacing, above and below.
    static func applySeparatorSpacing(in content: NSStackView) {
        let rows = content.arrangedSubviews
        for (index, row) in rows.enumerated() where (row as? NSBox)?.boxType == .separator {
            content.setCustomSpacing(separatorSpacing, after: row)
            if index > 0 {
                content.setCustomSpacing(separatorSpacing, after: rows[index - 1])
            }
        }
    }

    /// Keeps a pane's frame at its content size. In the Preferences window the pane sizes
    /// itself by its constraints: its column grows or shrinks with it and scrolls when
    /// needed, the window keeps its size.
    static func fitToContent(_ controller: NSViewController) {
        if let host = controller.parent as? PreferencesPaneHostViewController,
           host.currentController === controller {
            host.paneDidChangeSize(controller)
            return
        }
        let view = controller.view
        let size = view.fittingSize
        if view.frame.size != size {
            view.setFrameSize(size)
        }
    }

    // MARK: - Rows

    /// A form row: right-aligned title in the label column, `column` in the control
    /// column. The caller aligns the title with the column's first control.
    static func makeRow(title: String, column: NSView) -> (row: NSView, label: NSTextField) {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: title)
        label.font = labelFont
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(label)
        row.addSubview(column)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            label.widthAnchor.constraint(equalToConstant: labelWidth),
            label.topAnchor.constraint(greaterThanOrEqualTo: row.topAnchor),
            label.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor),
            column.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: columnSpacing),
            column.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            column.topAnchor.constraint(equalTo: row.topAnchor),
            column.bottomAnchor.constraint(equalTo: row.bottomAnchor),
        ])
        return (row, label)
    }

    /// The control column of a row: controls and hints stacked from the top.
    static func makeColumn(_ views: [NSView]) -> NSStackView {
        let column = NSStackView(views: views)
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = hintSpacing
        column.detachesHiddenViews = true
        column.translatesAutoresizingMaskIntoConstraints = false
        return column
    }

    static func makeSeparator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        return box
    }

    /// Title of a group of rows. It starts at the left margin, under a separator.
    static func makeSectionHeader(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = sectionHeaderFont
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setAccessibilityRole(.staticText)
        return label
    }

    // MARK: - Controls

    /// Small secondary text under a control, like the descriptions in the storyboard panes.
    static func makeHint(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = hintFont
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = controlWidth
        label.isSelectable = false
        return label
    }

    /// Shows `text` in a hint, or hides the hint when there is nothing to say.
    static func setHint(_ label: NSTextField, _ text: String?) {
        label.stringValue = text ?? ""
        label.isHidden = text == nil
    }

    /// A checkbox whose long title wraps instead of widening the pane.
    static func makeCheckbox(title: String, target: AnyObject?, action: Selector?) -> NSButton {
        let checkbox = NSButton(checkboxWithTitle: title, target: target, action: action)
        fitInControlColumn(checkbox)
        return checkbox
    }

    /// Lets a checkbox made elsewhere wrap its title at the width of the control column.
    static func fitInControlColumn(_ checkbox: NSButton) {
        checkbox.lineBreakMode = .byWordWrapping
        checkbox.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        checkbox.widthAnchor.constraint(lessThanOrEqualToConstant: controlWidth).isActive = true
    }

    /// A small continuous slider with its value written to the right of it.
    /// `widestValue` reserves the room of the value label.
    static func makeSliderLine(
        range: ClosedRange<Double>,
        widestValue: String,
        target: AnyObject?,
        action: Selector?,
        accessibilityLabel: String
    ) -> (slider: NSSlider, valueLabel: NSTextField, line: NSView) {
        let slider = NSSlider(
            value: range.lowerBound,
            minValue: range.lowerBound,
            maxValue: range.upperBound,
            target: target,
            action: action
        )
        slider.controlSize = .small
        slider.isContinuous = true
        slider.setAccessibilityLabel(accessibilityLabel)
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalToConstant: sliderWidth).isActive = true

        let valueLabel = NSTextField(labelWithString: widestValue)
        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.widthAnchor.constraint(equalToConstant: valueLabelWidth).isActive = true

        let line = NSStackView(views: [slider, valueLabel])
        line.orientation = .horizontal
        line.alignment = .centerY
        line.spacing = 8
        return (slider, valueLabel, line)
    }

    /// A borderless button that reads as a link: link-coloured text and a pointing hand.
    static func makeLinkButton(title: String, target: AnyObject?, action: Selector?) -> NSButton {
        let button = PreferencesLinkButton(title: title, target: target, action: action)
        button.isBordered = false
        button.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: NSColor.linkColor,
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
        ])
        button.setButtonType(.momentaryChange)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    /// Clamps a slider value into `range` and rounds it to the nearest `step` from the lower bound.
    static func snapped(_ value: Double, to range: ClosedRange<Double>, step: Double) -> Double {
        guard value.isFinite else { return range.lowerBound }
        let clamped = min(range.upperBound, max(range.lowerBound, value))
        guard step > 0 else { return clamped }
        let rounded = range.lowerBound + ((clamped - range.lowerBound) / step).rounded() * step
        // Drop floating-point noise so stored values stay tidy (0.8, not 0.8000000000000002).
        let tidy = (rounded * 1_000_000).rounded() / 1_000_000
        return min(range.upperBound, max(range.lowerBound, tidy))
    }
}

/// The material behind a pane, whose content draws in the plain light or dark appearance.
///
/// An NSVisualEffectView gives everything in it a vibrant appearance. There the label and
/// fill colours are opaque greys meant to be blended by the window server, and a text or
/// control that is not blended draws them as they are: a dimmed row's tertiary text came
/// out a dark grey on a dark box, almost invisible, and the light tick marks almost
/// vanished on a light one. System Settings draws its panes without vibrancy. This view
/// keeps each of its direct subviews in the plain appearance that matches its own (light,
/// dark, or their high-contrast forms) and follows it when the system switches.
final class PreferencesBackgroundView: NSVisualEffectView {

    /// The plain appearance that matches `appearance` (vibrant or not). `bestMatch` alone
    /// drops high contrast (it matches the high-contrast vibrant dark to plain dark), so
    /// that is read from the name.
    static func plainAppearance(matching appearance: NSAppearance) -> NSAppearance? {
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let highContrast = appearance.name.rawValue.contains("Accessibility")
        let name: NSAppearance.Name
        switch (dark, highContrast) {
        case (false, false): name = .aqua
        case (true, false): name = .darkAqua
        case (false, true): name = .accessibilityHighContrastAqua
        case (true, true): name = .accessibilityHighContrastDarkAqua
        }
        return NSAppearance(named: name)
    }

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        applyPlainAppearance(to: subview)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        subviews.forEach(applyPlainAppearance)
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        subviews.forEach(applyPlainAppearance)
    }

    private func applyPlainAppearance(to subview: NSView) {
        guard let plain = Self.plainAppearance(matching: effectiveAppearance),
              subview.appearance?.name != plain.name else { return }
        subview.appearance = plain
    }
}

/// The button behind `PreferencesForm.makeLinkButton`: shows the pointing hand over itself.
final class PreferencesLinkButton: NSButton {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
