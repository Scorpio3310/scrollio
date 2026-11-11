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

    /// Same background as the storyboard panes.
    static func makeBackground() -> NSVisualEffectView {
        let root = NSVisualEffectView()
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

    /// Keeps a pane's frame at its content size; when the pane is on screen the window follows.
    static func fitToContent(_ controller: NSViewController) {
        let view = controller.view
        if let window = view.window,
           let tabs = controller.parent as? PreferencesTabViewController,
           tabs.tabView.selectedTabViewItem?.viewController === controller {
            window.contentView?.layoutSubtreeIfNeeded()
            if view.frame.size != view.fittingSize {
                view.setFrameSize(view.fittingSize)
            }
            tabs.updateWindowSize()
        } else {
            view.setFrameSize(view.fittingSize)
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

    /// True while a slider is being dragged (continuous actions arrive in between).
    static var isTrackingMouse: Bool {
        guard let type = NSApp?.currentEvent?.type else { return false }
        return type == .leftMouseDown || type == .leftMouseDragged
    }

    // MARK: - Toolbar

    /// Toolbar image of a pane built in code: an SF Symbol drawn on the same 135 pt canvas
    /// as the SF.* assets of the storyboard panes, so the glyph comes out at the same size.
    /// `fallback` draws the image where the symbol does not exist. `glyphHeight` is the
    /// share of the canvas the glyph fills; symbols with a lot of air of their own take more.
    static func toolbarImage(
        symbolName: String,
        accessibilityDescription: String,
        glyphHeight: CGFloat = 0.6,
        fallback: @escaping (NSRect) -> Void
    ) -> NSImage {
        let canvas = NSSize(width: 135, height: 135)
        let image: NSImage
        if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 64, weight: .regular)) {
            image = NSImage(size: canvas, flipped: false) { rect in
                // A wide glyph is held to 80% of the canvas width instead.
                let aspect = symbol.size.width / max(symbol.size.height, 1)
                let height = min(rect.height * glyphHeight, rect.width * 0.8 / max(aspect, 0.01))
                let width = height * aspect
                symbol.draw(in: NSRect(
                    x: rect.midX - width / 2,
                    y: rect.midY - height / 2,
                    width: width,
                    height: height
                ))
                return true
            }
        } else {
            image = NSImage(size: canvas, flipped: false) { rect in
                NSColor.black.setStroke()
                NSColor.black.setFill()
                fallback(rect)
                return true
            }
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription
        return image
    }
}

/// The button behind `PreferencesForm.makeLinkButton`: shows the pointing hand over itself.
final class PreferencesLinkButton: NSButton {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
