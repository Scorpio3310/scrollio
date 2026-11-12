//
//  PreferencesGroupedForm.swift
//  Mos
//  Layout kit for preference panes in the style of System Settings: the settings sit in
//  rounded boxes on the window background, one setting per row. A row has its title on
//  the left with an optional explanation under it and its control on the right, centred
//  on the title line; hairlines separate the rows of a box.
//
//  The pieces:
//  - PreferencesGroupedForm: the numbers, the pane's content stack, section titles and
//    the footer line under the boxes.
//  - PreferencesGroupBox: a box of rows, as wide as the pane's content.
//  - PreferencesGroupSection: a box with an optional small title above it.
//  - PreferencesGroupRow: a row with any control on the right, or below the title (stacked).
//    PreferencesSwitchRow, PreferencesSliderRow and PreferencesDisclosureRow are the
//    common kinds.
//  - PreferencesSliderScale: the tick marks under a slider (System Settings' little dots)
//    and the steps its value moves in; PreferencesSlider draws them and steps by them.
//  Lists of selectable rows with + and − (PreferencesListBox) are in PreferencesListBox.swift.
//
//  The numbers are measured on System Settings › Trackpad (macOS 26, 2x screenshot).
//

import Cocoa

enum PreferencesGroupedForm {

    // MARK: - Metrics

    /// Between the pane's edges and its boxes.
    static let margin: CGFloat = 20
    static let boxCornerRadius: CGFloat = 10
    /// Between a box's edges and the content of its rows, left and right. The hairlines
    /// between the rows are inset by the same amount.
    static let rowHorizontalInset: CGFloat = 10
    /// How much further in a row stands that depends on the row above it (a switch that
    /// only counts while the switch above is on), as dependent controls stand on the Mac.
    static let dependentRowIndent: CGFloat = 18
    /// Above and below the text of a row.
    static let rowVerticalInset: CGFloat = 10
    /// The least room above and below a control that is taller than the title line.
    static let controlMinimumInset: CGFloat = 4
    /// Between a row's title and its explanation.
    static let explanationSpacing: CGFloat = 2
    /// The least room between the title column and the control on the right.
    static let controlSpacing: CGFloat = 16
    /// Between the text of a stacked row and the control under it.
    static let stackedControlSpacing: CGFloat = 8
    /// Between two boxes.
    static let boxSpacing: CGFloat = 16
    /// Above a titled section and above the footer.
    static let sectionSpacing: CGFloat = 20
    /// Between a section's title and its box.
    static let sectionTitleSpacing: CGFloat = 6
    /// Between a box and the muted note under it.
    static let noteSpacing: CGFloat = 10
    /// A slider's default width.
    static let sliderWidth: CGFloat = 140
    /// Between a slider and its value, and the room kept for the value: enough for the
    /// widest factor ("2.75×", "10.0×"). The Scrolling and the Gestures pane both use it, so
    /// their sliders stand in one column; the Mouse pane needs more for "8000 DPI"
    /// (`MousePreferencesViewController.sliderValueWidth`), and one column of that width
    /// for all three would wrap the explanations of two rows here.
    static let sliderValueSpacing: CGFloat = 8
    static let sliderValueWidth: CGFloat = 40
    /// Between a slider and the words under its ends.
    static let sliderEndsSpacing: CGFloat = 2
    /// The switches of System Settings: 36 × 16 pt on macOS 26.
    static let switchControlSize: NSControl.ControlSize = .mini

    // MARK: - Type

    /// Row titles: the regular system font, 13 pt.
    static var titleFont: NSFont {
        return NSFont.systemFont(ofSize: NSFont.systemFontSize)
    }

    /// Explanations under a title: 11 pt, the hint size of every pane.
    static var explanationFont: NSFont {
        return NSFont.systemFont(ofSize: PreferencesForm.hintFontSize)
    }

    static var sectionTitleFont: NSFont {
        return NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
    }

    /// The words under a slider's ends and its value.
    static var sliderLabelFont: NSFont {
        return NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    }

    static var sliderValueFont: NSFont {
        return NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
    }

    // MARK: - Colours

    /// A box: a light grey on a light window, a slightly lighter grey on a dark one. It is
    /// the system's tertiary fill (black or white at about 5%).
    static let boxFillColor = plain(name: "PreferencesGroupBoxFill") { .tertiarySystemFill }

    /// The line between two rows of a box.
    static let hairlineColor = plain(name: "PreferencesGroupHairline") { .separatorColor }

    /// A system colour as it is outside vibrancy. The panes stand on an NSVisualEffectView,
    /// which gives everything in it a vibrant appearance; there the system fills are opaque
    /// greys that only look right when the system blends them (a near-black box otherwise).
    /// The box draws as an ordinary view, so it takes the colour of the matching plain
    /// appearance: still dynamic, light and dark and high contrast follow the system.
    static func plain(name: String, _ color: @escaping () -> NSColor) -> NSColor {
        return NSColor(name: NSColor.Name(name)) { appearance in
            var resolved = color()
            PreferencesBackgroundView.plainAppearance(matching: appearance)?.performAsCurrentDrawingAppearance {
                resolved = color().usingColorSpace(.extendedSRGB) ?? resolved
            }
            return resolved
        }
    }

    /// Increase Contrast is on where `appearance` draws: System Settings then outlines its
    /// boxes. Read from the name, as `PreferencesBackgroundView.plainAppearance` does.
    static func isHighContrast(_ appearance: NSAppearance) -> Bool {
        return appearance.name.rawValue.contains("Accessibility")
    }

    /// The outline of a box under Increase Contrast, half a point inside its edge.
    static func drawOutline(of rect: NSRect) {
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: boxCornerRadius - 0.5, yRadius: boxCornerRadius - 0.5)
        path.lineWidth = 1
        hairlineColor.setStroke()
        path.stroke()
    }

    static func titleColor(enabled: Bool) -> NSColor {
        return enabled ? .labelColor : .tertiaryLabelColor
    }

    static func explanationColor(enabled: Bool) -> NSColor {
        return enabled ? .secondaryLabelColor : .tertiaryLabelColor
    }

    // MARK: - Pane

    /// Width of the boxes in a pane `paneWidth` wide.
    static func boxWidth(paneWidth: CGFloat) -> CGFloat {
        return paneWidth - 2 * margin
    }

    /// The vertical stack that holds a pane's preview, boxes and footer, pinned inside
    /// `root` with the margins. Its width fixes the pane at `paneWidth`.
    static func installContentStack(in root: NSView, paneWidth: CGFloat) -> NSStackView {
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = boxSpacing
        content.detachesHiddenViews = true
        content.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: root.topAnchor, constant: margin),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: margin),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -margin),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -margin),
            content.widthAnchor.constraint(equalToConstant: boxWidth(paneWidth: paneWidth)),
        ])
        return content
    }

    /// Adds views to the content stack, each as wide as the stack. A titled section and the
    /// footer get `sectionSpacing` above them, everything else `boxSpacing`.
    static func add(_ views: [NSView], to content: NSStackView) {
        for view in views {
            content.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        let all = content.arrangedSubviews
        for (index, view) in all.enumerated() where index > 0 && needsSectionSpacing(above: view) {
            content.setCustomSpacing(sectionSpacing, after: all[index - 1])
        }
    }

    private static func needsSectionSpacing(above view: NSView) -> Bool {
        if let section = view as? PreferencesGroupSection {
            return section.titleLabel != nil
        }
        if let section = view as? PreferencesListSection {
            return section.titleLabel != nil
        }
        return view is PreferencesGroupFooter
    }

    /// The small title above a box, as System Settings puts it over a group.
    static func makeSectionTitle(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = sectionTitleFont
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setAccessibilityRole(.staticText)
        return label
    }

    /// Lays out a section: `title` (if any) at the rows' inset, `body` under it at full width.
    static func layOutSection(_ section: NSView, title: NSTextField?, body: NSView) {
        section.addSubview(body)
        var constraints = [
            body.leadingAnchor.constraint(equalTo: section.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: section.trailingAnchor),
            body.bottomAnchor.constraint(equalTo: section.bottomAnchor),
        ]
        if let title {
            section.addSubview(title)
            constraints += [
                title.topAnchor.constraint(equalTo: section.topAnchor),
                title.leadingAnchor.constraint(equalTo: section.leadingAnchor, constant: rowHorizontalInset),
                title.trailingAnchor.constraint(lessThanOrEqualTo: section.trailingAnchor, constant: -rowHorizontalInset),
                body.topAnchor.constraint(equalTo: title.bottomAnchor, constant: sectionTitleSpacing),
            ]
        } else {
            constraints.append(body.topAnchor.constraint(equalTo: section.topAnchor))
        }
        NSLayoutConstraint.activate(constraints)
    }

    /// A switch in the size System Settings uses in its boxes.
    static func makeSwitch(target: AnyObject?, action: Selector?) -> NSSwitch {
        let toggle = NSSwitch()
        toggle.controlSize = switchControlSize
        toggle.target = target
        toggle.action = action
        toggle.translatesAutoresizingMaskIntoConstraints = false
        return toggle
    }

    /// A push button for the footer, such as "Reset to defaults".
    static func makePushButton(title: String, target: AnyObject?, action: Selector?) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .push
        button.controlSize = .regular
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }
}

// MARK: - Box

/// A rounded box of rows. Rows that are hidden take no room, and the hairlines are only
/// drawn between rows that show.
final class PreferencesGroupBox: NSView {

    let width: CGFloat
    private let stack = NSStackView()
    private(set) var rows: [PreferencesGroupRow] = []

    init(width: CGFloat, rows: [PreferencesGroupRow] = []) {
        self.width = width
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 0))
        translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.detachesHiddenViews = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: width),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        rows.forEach(addRow)
    }

    required init?(coder: NSCoder) {
        fatalError("PreferencesGroupBox is built in code")
    }

    override var isFlipped: Bool { return true }

    func addRow(_ row: PreferencesGroupRow) {
        rows.append(row)
        row.contentWidth = width
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        needsDisplay = true
    }

    /// The rows that show, top to bottom.
    var visibleRows: [PreferencesGroupRow] {
        return rows.filter { !$0.isHidden }
    }

    /// The hairlines, in the box's (flipped) coordinates: one on top of every row that
    /// shows, except the first. Inset like the rows' content, one pixel thick.
    var separatorRects: [NSRect] {
        let inset = PreferencesGroupedForm.rowHorizontalInset
        let thickness = 1 / max(1, window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
        return visibleRows.dropFirst().map { row in
            let top = convert(row.bounds, from: row).minY
            return NSRect(x: inset, y: top, width: bounds.width - 2 * inset, height: thickness)
        }
    }

    override func layout() {
        super.layout()
        // A row that hides or shows moves the hairlines.
        needsDisplay = true
    }

    /// Under Increase Contrast the box has an outline.
    var drawsOutline: Bool {
        return PreferencesGroupedForm.isHighContrast(effectiveAppearance)
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = PreferencesGroupedForm.boxCornerRadius
        PreferencesGroupedForm.boxFillColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        PreferencesGroupedForm.hairlineColor.setFill()
        for rect in separatorRects {
            rect.fill()
        }
        if drawsOutline {
            PreferencesGroupedForm.drawOutline(of: bounds)
        }
    }
}

// MARK: - Section

/// A box with an optional title above it ("While you hold a key").
final class PreferencesGroupSection: NSView {

    let titleLabel: NSTextField?
    let box: PreferencesGroupBox

    init(title: String? = nil, box: PreferencesGroupBox) {
        self.box = box
        self.titleLabel = title.map(PreferencesGroupedForm.makeSectionTitle)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        PreferencesGroupedForm.layOutSection(self, title: titleLabel, body: box)
    }

    convenience init(title: String? = nil, width: CGFloat, rows: [PreferencesGroupRow]) {
        self.init(title: title, box: PreferencesGroupBox(width: width, rows: rows))
    }

    required init?(coder: NSCoder) {
        fatalError("PreferencesGroupSection is built in code")
    }
}

// MARK: - Footer

/// The line under the boxes: buttons at the right edge, like "Set Up Bluetooth Trackpad…".
final class PreferencesGroupFooter: NSView {

    let views: [NSView]

    init(trailing views: [NSView]) {
        self.views = views
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let line = NSStackView(views: views)
        line.orientation = .horizontal
        line.alignment = .centerY
        line.spacing = 12
        line.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line)
        NSLayoutConstraint.activate([
            line.topAnchor.constraint(equalTo: topAnchor),
            line.bottomAnchor.constraint(equalTo: bottomAnchor),
            line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("PreferencesGroupFooter is built in code")
    }
}

// MARK: - Row

/// One setting: the title on the left, an optional explanation under it, the control on
/// the right (centred on the title line) or, in a stacked row, under the text at full width.
class PreferencesGroupRow: NSView {

    enum Placement {
        /// On the right, centred on the title line.
        case trailing
        /// Under the title and the explanation, as wide as the row.
        case below
    }

    let titleLabel: NSTextField
    /// Always there; hidden while the row has no explanation.
    let explanationLabel: NSTextField
    let accessory: NSView?
    let placement: Placement
    /// The controls the row names (accessibility) and turns on and off with itself.
    let controls: [NSControl]
    /// Between the row's left edge and its texts: the rows' inset, more when something sits
    /// before the texts (a list row's icon).
    let leadingInset: CGFloat
    /// Between the row's right edge and its control (or its texts): the rows' inset, more
    /// when something sits after the control (a list row's chevron).
    let trailingInset: CGFloat

    /// The width of the box the row is in. Its box sets it; it fixes where explanations wrap.
    var contentWidth: CGFloat = 0 {
        didSet { updateExplanationWidth() }
    }

    /// Texts the explanation may show, so that switching between them never changes the
    /// row's height ("Feel" changes its explanation with the choice).
    var reservedExplanations: [String] = [] {
        didSet { updateExplanationWidth() }
    }

    /// Off: the title, the explanation and the controls are dimmed together.
    var isEnabled = true {
        didSet { applyEnabled() }
    }

    var title: String {
        get { return titleLabel.stringValue }
        set {
            titleLabel.stringValue = newValue
            labelControls()
        }
    }

    var explanation: String? {
        get { return explanationLabel.isHidden ? nil : explanationLabel.stringValue }
        set {
            explanationLabel.stringValue = newValue ?? ""
            explanationLabel.isHidden = newValue == nil
            updateExplanationConstraints()
            labelControls()
        }
    }

    private var reservedHeightConstraint: NSLayoutConstraint?
    /// Active while the explanation shows, and while it does not.
    private var explanationShownConstraints: [NSLayoutConstraint] = []
    private var explanationHiddenConstraints: [NSLayoutConstraint] = []

    /// - Parameters:
    ///   - accessory: the control, or a view holding the controls.
    ///   - centeredOn: the view inside `accessory` whose middle sits on the title line
    ///     (a slider rather than the words under it). The accessory itself by default.
    ///   - controls: what the row names and enables; the accessory when it is a control.
    ///   - leadingInset, trailingInset: room before the texts and after the control, for
    ///     subclasses that put something there (PreferencesListRow).
    init(
        title: String,
        explanation: String? = nil,
        accessory: NSView? = nil,
        placement: Placement = .trailing,
        centeredOn anchor: NSView? = nil,
        controls: [NSControl]? = nil,
        leadingInset: CGFloat = PreferencesGroupedForm.rowHorizontalInset,
        trailingInset: CGFloat = PreferencesGroupedForm.rowHorizontalInset
    ) {
        titleLabel = NSTextField(labelWithString: title)
        explanationLabel = NSTextField(wrappingLabelWithString: explanation ?? "")
        self.accessory = accessory
        self.placement = placement
        self.controls = controls ?? [accessory as? NSControl].compactMap { $0 }
        self.leadingInset = leadingInset
        self.trailingInset = trailingInset
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = PreferencesGroupedForm.titleFont
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        explanationLabel.font = PreferencesGroupedForm.explanationFont
        explanationLabel.isSelectable = false
        explanationLabel.isHidden = explanation == nil
        explanationLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        explanationLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(explanationLabel)

        let vertical = PreferencesGroupedForm.rowVerticalInset
        var constraints = [
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: leadingInset),
            titleLabel.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: vertical),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -vertical),
            explanationLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            explanationLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: PreferencesGroupedForm.explanationSpacing),
        ]
        // The title sits at the top padding unless a tall control needs more room, and the
        // row is no taller than what it holds.
        let titleTop = titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: vertical)
        titleTop.priority = .defaultHigh
        let hug = heightAnchor.constraint(equalToConstant: 0)
        hug.priority = .fittingSizeCompression
        constraints += [titleTop, hug]
        // Only an explanation that shows holds the bottom of the row.
        explanationShownConstraints = [
            explanationLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -vertical),
        ]

        if let accessory {
            accessory.translatesAutoresizingMaskIntoConstraints = false
            addSubview(accessory)
            switch placement {
            case .trailing:
                let anchorView = anchor ?? accessory
                constraints += [
                    accessory.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -trailingInset),
                    anchorView.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
                    accessory.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: PreferencesGroupedForm.controlMinimumInset),
                    accessory.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -PreferencesGroupedForm.controlMinimumInset),
                    titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: accessory.leadingAnchor, constant: -PreferencesGroupedForm.controlSpacing),
                    explanationLabel.trailingAnchor.constraint(lessThanOrEqualTo: accessory.leadingAnchor, constant: -PreferencesGroupedForm.controlSpacing),
                ]
            case .below:
                let spacing = PreferencesGroupedForm.stackedControlSpacing
                constraints += [
                    accessory.leadingAnchor.constraint(equalTo: leadingAnchor, constant: leadingInset),
                    accessory.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -trailingInset),
                    accessory.topAnchor.constraint(greaterThanOrEqualTo: titleLabel.bottomAnchor, constant: spacing),
                    accessory.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -vertical),
                    titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -trailingInset),
                    explanationLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -trailingInset),
                ]
                // Snug under the text that shows.
                let underExplanation = accessory.topAnchor.constraint(equalTo: explanationLabel.bottomAnchor, constant: spacing)
                underExplanation.priority = .defaultHigh
                let underTitle = accessory.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: spacing)
                underTitle.priority = .defaultHigh
                explanationShownConstraints += [
                    accessory.topAnchor.constraint(greaterThanOrEqualTo: explanationLabel.bottomAnchor, constant: spacing),
                    underExplanation,
                ]
                explanationHiddenConstraints = [underTitle]
            }
        } else {
            constraints += [
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -trailingInset),
                explanationLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -trailingInset),
            ]
        }
        NSLayoutConstraint.activate(constraints)
        updateExplanationConstraints()
        applyEnabled()
        labelControls()
    }

    private func updateExplanationConstraints() {
        let shows = !explanationLabel.isHidden
        NSLayoutConstraint.deactivate(shows ? explanationHiddenConstraints : explanationShownConstraints)
        NSLayoutConstraint.activate(shows ? explanationShownConstraints : explanationHiddenConstraints)
    }

    required init?(coder: NSCoder) {
        fatalError("PreferencesGroupRow is built in code")
    }

    /// The width of the title column: the row's content minus the control on the right.
    var titleColumnWidth: CGFloat {
        let full = max(0, contentWidth - leadingInset - trailingInset)
        guard let accessory, placement == .trailing else { return full }
        let accessoryWidth = accessory.frame.width > 0 ? accessory.frame.width : accessory.fittingSize.width
        return max(0, full - accessoryWidth - PreferencesGroupedForm.controlSpacing)
    }

    override func layout() {
        super.layout()
        // A control may only know its size once it is in a window (NSSwitch): check again.
        if contentWidth > 0, abs(explanationLabel.preferredMaxLayoutWidth - titleColumnWidth) > 0.5 {
            updateExplanationWidth()
        }
    }

    private func updateExplanationWidth() {
        guard contentWidth > 0 else { return }
        let width = titleColumnWidth
        explanationLabel.preferredMaxLayoutWidth = width
        explanationLabel.invalidateIntrinsicContentSize()

        reservedHeightConstraint?.isActive = false
        reservedHeightConstraint = nil
        guard !reservedExplanations.isEmpty else { return }
        let measure = NSTextField(wrappingLabelWithString: "")
        measure.font = explanationLabel.font
        measure.preferredMaxLayoutWidth = width
        let tallest = reservedExplanations.map { text -> CGFloat in
            measure.stringValue = text
            return measure.fittingSize.height
        }.max() ?? 0
        let constraint = explanationLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: tallest)
        constraint.isActive = true
        reservedHeightConstraint = constraint
    }

    /// Dims or restores the texts and turns the controls on or off. Subclasses dim their
    /// own extra texts.
    func applyEnabled() {
        titleLabel.textColor = PreferencesGroupedForm.titleColor(enabled: isEnabled)
        explanationLabel.textColor = PreferencesGroupedForm.explanationColor(enabled: isEnabled)
        for control in controls {
            control.isEnabled = isEnabled
        }
    }

    /// Every control is named by the row's title and explained by its explanation. A
    /// button that shows a title of its own (a key recorder) keeps it and points at the
    /// row's title instead. A pop-up's title is its value, not its name: it is named by
    /// the row (a list row's title is no accessibility element of its own to point at).
    private func labelControls() {
        for control in controls {
            if let button = control as? NSButton, !(button is NSPopUpButton), !button.title.isEmpty {
                button.setAccessibilityTitleUIElement(titleLabel)
            } else {
                control.setAccessibilityLabel(titleLabel.stringValue)
            }
            control.setAccessibilityHelp(explanation)
        }
    }
}

// MARK: - Switch row

/// A row with a switch on the right.
final class PreferencesSwitchRow: PreferencesGroupRow {

    let toggle: NSSwitch

    /// - Parameter leadingInset: more than the row's own for a switch that depends on the
    ///   switch above it (`PreferencesGroupedForm.dependentRowIndent` further in).
    init(
        title: String,
        explanation: String? = nil,
        target: AnyObject?,
        action: Selector?,
        leadingInset: CGFloat = PreferencesGroupedForm.rowHorizontalInset
    ) {
        toggle = PreferencesGroupedForm.makeSwitch(target: target, action: action)
        super.init(title: title, explanation: explanation, accessory: toggle, leadingInset: leadingInset)
    }

    required init?(coder: NSCoder) {
        fatalError("PreferencesSwitchRow is built in code")
    }

    var isOn: Bool {
        get { return toggle.state == .on }
        set { toggle.state = newValue ? .on : .off }
    }
}

// MARK: - Slider scale

/// The tick marks under a slider and the values it moves through, as on the sliders of
/// System Settings › Trackpad. Pure: the panes and their tests share the arithmetic.
///
/// Two kinds:
/// - `ticksOnly`: the knob stops only on the tick marks ("Click": light, medium, firm).
/// - `step`: the tick marks are a scale to read by and the value moves in finer steps,
///   whole multiples of the step ("Speed": a tick at every whole number, values in halves).
///
/// A stored value off the grid is shown, never changed: `knobPosition` says where the knob
/// shows it, and only a move by the user writes a value of the grid.
struct PreferencesSliderScale: Equatable {

    enum Stepping: Equatable {
        /// The knob stops only on the tick marks.
        case ticksOnly
        /// Values are whole multiples of this step (inside the range); the ticks only guide the eye.
        case step(Double)
    }

    /// Tick marks under the track, evenly spaced from one end to the other.
    let tickCount: Int
    let stepping: Stepping

    /// The knob stops only on `count` tick marks.
    static func ticksOnly(_ count: Int) -> PreferencesSliderScale {
        return PreferencesSliderScale(tickCount: count, stepping: .ticksOnly)
    }

    /// `count` tick marks to read by; the value moves in steps of `step`.
    static func ticks(_ count: Int, step: Double) -> PreferencesSliderScale {
        return PreferencesSliderScale(tickCount: count, stepping: .step(step))
    }

    var stopsOnTicksOnly: Bool {
        return stepping == .ticksOnly
    }

    /// The values the tick marks stand for over `range`, from the lower end.
    func tickValues(in range: ClosedRange<Double>) -> [Double] {
        guard tickCount > 1 else { return tickCount == 1 ? [range.lowerBound] : [] }
        let spacing = (range.upperBound - range.lowerBound) / Double(tickCount - 1)
        return (0..<tickCount).map { Self.tidy(range.lowerBound + Double($0) * spacing) }
    }

    /// Between two neighbouring values the slider takes; 0 when it takes any value.
    func step(in range: ClosedRange<Double>) -> Double {
        switch stepping {
        case .ticksOnly:
            return tickCount > 1 ? (range.upperBound - range.lowerBound) / Double(tickCount - 1) : 0
        case .step(let step):
            return max(0, step)
        }
    }

    /// The nearest value the slider takes, inside `range`. Not a number: the lower bound.
    func snapped(_ value: Double, in range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return range.lowerBound }
        let clamped = Self.clamp(value, to: range)
        let step = step(in: range)
        guard step > 0 else { return clamped }
        let origin = origin(in: range)
        return Self.clamp(Self.tidy(origin + ((clamped - origin) / step).rounded() * step), to: range)
    }

    /// `steps` values further up (positive) or down from `value`: what the arrow keys do.
    /// A value between two values of the grid moves to the neighbouring one first.
    func stepped(from value: Double, by steps: Int, in range: ClosedRange<Double>) -> Double {
        let step = step(in: range)
        guard step > 0, steps != 0 else { return snapped(value, in: range) }
        let origin = origin(in: range)
        let position = (Self.clamp(value.isFinite ? value : range.lowerBound, to: range) - origin) / step
        // A position a hair off the grid counts as on it (floating point).
        let slack = 1e-6
        let index = steps > 0
            ? (position + slack).rounded(.down) + Double(steps)
            : (position - slack).rounded(.up) + Double(steps)
        return Self.clamp(Self.tidy(origin + index * step), to: range)
    }

    /// Where the knob shows a stored `value`: on the nearest tick mark when it stops only
    /// there, otherwise at the value itself. The value is not changed.
    func knobPosition(for value: Double, in range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return range.lowerBound }
        return stopsOnTicksOnly ? snapped(value, in: range) : Self.clamp(value, to: range)
    }

    /// The grid starts at the first tick mark, or at zero for a step (whole multiples).
    private func origin(in range: ClosedRange<Double>) -> Double {
        return stopsOnTicksOnly ? range.lowerBound : 0
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        return min(range.upperBound, max(range.lowerBound, value))
    }

    /// Drops floating-point noise so stored values stay tidy (0.75, not 0.7500000000000001).
    private static func tidy(_ value: Double) -> Double {
        return (value * 1_000_000).rounded() / 1_000_000
    }
}

// MARK: - Slider

/// The slider of a PreferencesSliderRow. With a scale it has the scale's tick marks under
/// its track, its knob moves through the scale's values while it is dragged, and an arrow
/// key (or VoiceOver's increment) moves it by one value and sends the action as a drag does.
///
/// It knows when the user drags its own knob (`isTracking`): a pane leaves only that
/// knob alone while it refreshes, never the others, and never because some other mouse
/// button happens to be down. When the user lets go it sends its action once more, no
/// longer tracking: the pane then shows the stored value and does what belongs to a
/// finished move (the Mouse pane's sample pulse).
///
/// A press that does not move the knob changes nothing: no action goes out, so a stored
/// value that is not on the scale stays as it is and nothing is sent on to a mouse. A
/// slider that is off sends nothing at all. Such a press ends with `onPressEndedWithoutAction`
/// instead, so the pane can show what arrived while it was held.
final class PreferencesSlider: NSSlider {

    var scale: PreferencesSliderScale? {
        didSet { applyScale() }
    }

    /// The user let go and no action went out (the knob had not moved, or the slider was
    /// turned off meanwhile). A refresh skipped this knob while it was pressed: the pane
    /// shows the current value now. Never the action, and nothing to store.
    var onPressEndedWithoutAction: (() -> Void)?

    /// True between the user pressing on the slider and letting go.
    private(set) var isTracking = false

    /// Where the knob was when the user pressed on the slider; nil outside a press.
    private var valueAtPress: Double?
    /// Whether this press has moved the knob (an action went out).
    private var movedSincePress = false

    /// The user pressed on the slider. `mouseDown` calls it; tests call it to stand in
    /// for a drag.
    func beginTracking() {
        isTracking = true
        valueAtPress = doubleValue
        movedSincePress = false
    }

    /// The user let go: the action goes out once more, with `isTracking` false. Not after
    /// a press that never moved the knob: the knob goes back to exactly where it was.
    func endTracking() {
        guard isTracking else { return }
        isTracking = false
        let moved = movedSincePress || !knobIsWherePressed
        let pressed = valueAtPress
        valueAtPress = nil
        movedSincePress = false
        guard moved, isEnabled else {
            if let pressed, doubleValue != pressed {
                doubleValue = pressed
            }
            onPressEndedWithoutAction?()
            return
        }
        _ = sendAction(action, to: target)
    }

    /// NSSlider tracks the mouse in here until the button goes up. A slider that is off
    /// tracks nothing and sends nothing.
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return super.mouseDown(with: event) }
        beginTracking()
        super.mouseDown(with: event)
        endTracking()
    }

    /// The knob has not left the place where it was pressed. AppKit works the value out
    /// again from the knob's position when it is pressed, so "the same" allows for less
    /// than a point of travel (float noise only while the slider has no size yet).
    private var knobIsWherePressed: Bool {
        guard let valueAtPress else { return false }
        return abs(doubleValue - valueAtPress) <= Self.pressTolerance(span: maxValue - minValue, width: Double(bounds.width))
    }

    /// How far the value may be from the one at the press and still count as not moved.
    static func pressTolerance(span: Double, width: Double) -> Double {
        guard span > 0 else { return 0 }
        let travel = width - 20   // the knob's own width does not count as travel
        return travel >= 20 ? span / travel * 0.75 : span * 1e-9
    }

    /// The slider's range as set.
    var range: ClosedRange<Double> {
        return minValue...max(minValue, maxValue)
    }

    /// Puts the knob where a stored `value` shows (`PreferencesSliderScale.knobPosition`).
    /// Sends nothing.
    func showValue(_ value: Double) {
        doubleValue = scale?.knobPosition(for: value, in: range) ?? value
    }

    /// Moves the knob by `steps` values of the scale and sends the action. False when there
    /// is no scale, the slider is off, or the knob is already at that end.
    @discardableResult
    func moveKnob(by steps: Int) -> Bool {
        guard let scale, isEnabled else { return false }
        let next = scale.stepped(from: doubleValue, by: steps, in: range)
        guard next != doubleValue else { return false }
        doubleValue = next
        _ = sendAction(action, to: target)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard scale != nil else { return super.keyDown(with: event) }
        switch event.specialKey {
        case .rightArrow?, .upArrow?:
            moveKnob(by: 1)
        case .leftArrow?, .downArrow?:
            moveKnob(by: -1)
        default:
            super.keyDown(with: event)
        }
    }

    override func accessibilityPerformIncrement() -> Bool {
        guard scale != nil else { return super.accessibilityPerformIncrement() }
        moveKnob(by: 1)
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        guard scale != nil else { return super.accessibilityPerformDecrement() }
        moveKnob(by: -1)
        return true
    }

    /// A drag moves the knob through the scale's values, not in between: the action gets a
    /// value of the grid. While a press has not moved the knob nothing goes out (AppKit also
    /// sends on the press itself and when the button goes up).
    override func sendAction(_ action: Selector?, to target: Any?) -> Bool {
        if isTracking, !movedSincePress {
            guard !knobIsWherePressed else { return false }
            movedSincePress = true
        }
        if let scale {
            let snapped = scale.snapped(doubleValue, in: range)
            if snapped != doubleValue {
                doubleValue = snapped
            }
        }
        return super.sendAction(action, to: target)
    }

    private func applyScale() {
        numberOfTickMarks = scale?.tickCount ?? 0
        tickMarkPosition = .below
        allowsTickMarkValuesOnly = scale?.stopsOnTicksOnly ?? false
    }
}

// MARK: - Slider row

/// A row with a slider on the right: optionally tick marks under the track (`scale`), a
/// word under each end of the slider ("Slow" and "Fast") and the value next to it.
final class PreferencesSliderRow: PreferencesGroupRow {

    let slider: PreferencesSlider
    let valueLabel: NSTextField?
    let lowEndLabel: NSTextField?
    let highEndLabel: NSTextField?

    /// The tick marks and the values the slider moves through; nil: any value, no marks.
    var scale: PreferencesSliderScale? {
        get { return slider.scale }
        set { slider.scale = newValue }
    }

    /// The value stays in the label colour while the row is off: for a row whose value is a
    /// read-out then (the Mouse pane's greyed rows show what the mouse reports, and the line
    /// above them says so). The title, the slider and the words under its ends dim as always.
    var keepsValueReadable = false {
        didSet { applyEnabled() }
    }

    init(
        title: String,
        explanation: String? = nil,
        range: ClosedRange<Double>,
        scale: PreferencesSliderScale? = nil,
        sliderWidth: CGFloat = PreferencesGroupedForm.sliderWidth,
        ends: (low: String, high: String)? = nil,
        showsValue: Bool = true,
        valueWidth: CGFloat = PreferencesGroupedForm.sliderValueWidth,
        target: AnyObject?,
        action: Selector?
    ) {
        let slider = PreferencesSlider(value: range.lowerBound, minValue: range.lowerBound, maxValue: range.upperBound, target: target, action: action)
        slider.controlSize = .regular
        slider.isContinuous = true
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.scale = scale
        self.slider = slider

        let accessory = NSView()
        accessory.translatesAutoresizingMaskIntoConstraints = false
        accessory.addSubview(slider)
        var constraints = [
            slider.widthAnchor.constraint(equalToConstant: sliderWidth),
            slider.leadingAnchor.constraint(equalTo: accessory.leadingAnchor),
            slider.topAnchor.constraint(equalTo: accessory.topAnchor),
        ]

        if showsValue {
            let value = NSTextField(labelWithString: "")
            value.font = PreferencesGroupedForm.sliderValueFont
            value.alignment = .right
            value.translatesAutoresizingMaskIntoConstraints = false
            accessory.addSubview(value)
            constraints += [
                value.leadingAnchor.constraint(equalTo: slider.trailingAnchor, constant: PreferencesGroupedForm.sliderValueSpacing),
                value.trailingAnchor.constraint(equalTo: accessory.trailingAnchor),
                value.widthAnchor.constraint(equalToConstant: valueWidth),
                value.centerYAnchor.constraint(equalTo: slider.centerYAnchor),
            ]
            valueLabel = value
        } else {
            constraints.append(slider.trailingAnchor.constraint(equalTo: accessory.trailingAnchor))
            valueLabel = nil
        }

        if let ends {
            let low = NSTextField(labelWithString: ends.low)
            let high = NSTextField(labelWithString: ends.high)
            high.alignment = .right
            for label in [low, high] {
                label.font = PreferencesGroupedForm.sliderLabelFont
                label.translatesAutoresizingMaskIntoConstraints = false
                accessory.addSubview(label)
            }
            constraints += [
                low.leadingAnchor.constraint(equalTo: slider.leadingAnchor),
                low.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: PreferencesGroupedForm.sliderEndsSpacing),
                high.trailingAnchor.constraint(equalTo: slider.trailingAnchor),
                high.firstBaselineAnchor.constraint(equalTo: low.firstBaselineAnchor),
                high.leadingAnchor.constraint(greaterThanOrEqualTo: low.trailingAnchor, constant: 8),
                low.bottomAnchor.constraint(equalTo: accessory.bottomAnchor),
            ]
            lowEndLabel = low
            highEndLabel = high
        } else {
            constraints.append(slider.bottomAnchor.constraint(equalTo: accessory.bottomAnchor))
            lowEndLabel = nil
            highEndLabel = nil
        }
        NSLayoutConstraint.activate(constraints)

        super.init(title: title, explanation: explanation, accessory: accessory, centeredOn: slider, controls: [slider])

        // The words under the ends are text: they keep the full padding at the bottom.
        if let lowEndLabel {
            lowEndLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -PreferencesGroupedForm.rowVerticalInset).isActive = true
        }
        applyEnabled()
    }

    required init?(coder: NSCoder) {
        fatalError("PreferencesSliderRow is built in code")
    }

    /// Puts the knob where a stored `value` shows: on the nearest tick mark of a slider that
    /// stops only there. The value itself is left alone.
    func showValue(_ value: Double) {
        slider.showValue(value)
    }

    /// The user is dragging this row's knob: a refresh leaves the knob where it is.
    var isTracking: Bool {
        return slider.isTracking
    }

    /// The value written next to the slider. VoiceOver reads it as the slider's value
    /// ("1000 DPI", "50%"), not the raw number the slider holds.
    var valueText: String {
        get { return valueLabel?.stringValue ?? "" }
        set {
            valueLabel?.stringValue = newValue
            slider.setAccessibilityValueDescription(newValue.isEmpty ? nil : newValue)
        }
    }

    override func applyEnabled() {
        super.applyEnabled()
        let color = PreferencesGroupedForm.titleColor(enabled: isEnabled)
        for label in [lowEndLabel, highEndLabel].compactMap({ $0 }) {
            label.textColor = color
        }
        valueLabel?.textColor = PreferencesGroupedForm.titleColor(enabled: isEnabled || keepsValueReadable)
    }
}

// MARK: - Disclosure row

/// A header row that opens and closes the rows under it: a chevron and a title, the whole
/// row is the button. It shows or hides `revealedViews`; whoever owns it decides what else
/// happens (remembering the state, resizing the window) in the button's action.
final class PreferencesDisclosureRow: PreferencesGroupRow {

    let button: NSButton

    /// The rows (or sections) shown while the row is open.
    var revealedViews: [NSView] = [] {
        didSet { applyExpanded() }
    }

    var isExpanded = false {
        didSet { applyExpanded() }
    }

    init(title: String, target: AnyObject?, action: Selector?) {
        let button = NSButton(title: title, target: target, action: action)
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.alignment = .left
        button.contentTintColor = .secondaryLabelColor
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: PreferencesGroupedForm.titleFont,
            .foregroundColor: NSColor.labelColor,
        ])
        button.translatesAutoresizingMaskIntoConstraints = false
        self.button = button
        super.init(title: title, controls: [])

        // The button stands in for the title: the whole row is its click target.
        titleLabel.isHidden = true
        addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: leadingAnchor, constant: PreferencesGroupedForm.rowHorizontalInset),
            button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -PreferencesGroupedForm.rowHorizontalInset),
            button.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            button.heightAnchor.constraint(equalTo: heightAnchor),
        ])
        applyExpanded()
    }

    required init?(coder: NSCoder) {
        fatalError("PreferencesDisclosureRow is built in code")
    }

    private func applyExpanded() {
        button.image = Self.chevron(expanded: isExpanded)
        button.setAccessibilityExpanded(isExpanded)
        for view in revealedViews {
            view.isHidden = !isExpanded
        }
    }

    /// Both directions are drawn on one canvas, so the title does not move when the row opens.
    static func chevron(expanded: Bool) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        guard let symbol = NSImage(systemSymbolName: expanded ? "chevron.down" : "chevron.right", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return nil }
        let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            let size = symbol.size
            symbol.draw(in: NSRect(
                x: rect.midX - size.width / 2,
                y: rect.midY - size.height / 2,
                width: size.width,
                height: size.height
            ))
            return true
        }
        image.isTemplate = true
        return image
    }
}
