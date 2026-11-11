//
//  PreferencesForm.swift
//  Mos
//  What the panes built in code share besides the grouped kit (PreferencesGroupedForm):
//  the window background, fitting a pane to its content, the hint type, and the column,
//  separators and headers of the Welcome Guide.
//

import Cocoa

enum PreferencesForm {

    // MARK: - Metrics

    /// Width of the Welcome Guide's content.
    static let contentWidth: CGFloat = 450
    /// Between two blocks of the Welcome Guide.
    static let rowSpacing: CGFloat = 17
    /// Between a line and the smaller text under it.
    static let hintSpacing: CGFloat = 6

    // MARK: - Type

    /// Size of the secondary text under a control: 11 pt, the small system font. One
    /// constant for every pane built in code.
    static let hintFontSize: CGFloat = NSFont.smallSystemFontSize

    static var hintFont: NSFont {
        return NSFont.systemFont(ofSize: hintFontSize)
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

    // MARK: - Pieces

    /// Lines stacked from the top, `hintSpacing` apart.
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

    /// Title of a group of lines.
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
