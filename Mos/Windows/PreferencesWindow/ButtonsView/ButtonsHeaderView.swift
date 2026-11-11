//
//  ButtonsHeaderView.swift
//  Mos
//  The card at the top of the Buttons pane, with the metrics and colours of the Mouse
//  pane's card (MouseHeaderView): on the left the mouse seen from above, its buttons
//  drawn, on the right what the pane is about. The button of the row under the pointer
//  (or the selected row, or the button just recorded) lights up in the accent colour; a
//  button the drawing cannot show ("Button 5") gets its number on a badge by the mouse and
//  a line on how to find it. Idle, a second line says how to tell the buttons apart: "+"
//  and a press of a listed button makes the card answer "That's …".
//

import Cocoa

// MARK: - What the card says

/// The texts of the card and the part it lights. Pure: the pane and its tests share it.
struct ButtonsHeaderContent: Equatable {
    var title: String
    var subtitle: String?
    var part: ButtonsMousePart?
    /// A smaller line under the subtitle: how to find out which button is which.
    var hint: String? = nil
    /// The number of a button the drawing cannot show ("Button 5"), on a badge by the mouse.
    var number: Int? = nil

    /// A row the card is about: its title, its action and its picture.
    struct Focus: Equatable {
        var title: String
        /// The action's name; nil: none.
        var action: String?
        var picture: ButtonTriggerPicture
        var reason: Reason = .row

        /// Why the card is about the button.
        enum Reason: Equatable {
            /// Its row is pointed at or selected.
            case row
            /// "+" caught it and the list does not have it yet.
            case recorded
            /// "+" caught a button the list has: the card says "That's …".
            case answer
        }

        var part: ButtonsMousePart? {
            return picture.part
        }
    }

    /// - Parameters:
    ///   - deviceName: the connected Logitech mouse, nil without one.
    ///   - boundCount: buttons that have an action.
    ///   - isRecording: "+" waits for a button.
    ///   - focus: the row pointed at (it wins), else the selected row or the one just
    ///     recorded; nil: none.
    static func make(deviceName: String?, boundCount: Int, isRecording: Bool, focus: Focus?) -> ButtonsHeaderContent {
        if isRecording {
            return ButtonsHeaderContent(
                title: text("buttons-header-recording"),
                subtitle: text("buttons-header-recording-hint"),
                part: nil
            )
        }
        if let focus {
            let title = focus.reason == .answer ? String(format: text("buttons-header-answer"), focus.title) : focus.title
            // A listed button the drawing cannot show: the mouse tells which one it is, and
            // a numbered one can be said to be a part ("Which button is this?" at its picture).
            var hint: String?
            if focus.reason == .row && focus.picture.isUnplaced {
                hint = text(focus.picture.number == nil ? "buttons-header-find-this-one" : "buttons-header-place-this-one")
            }
            return ButtonsHeaderContent(
                title: title,
                subtitle: focus.action ?? text("buttons-header-no-action"),
                part: focus.part,
                hint: hint,
                number: focus.picture.number
            )
        }
        let subtitle: String
        switch boundCount {
        case 0: subtitle = text("buttons-header-none")
        case 1: subtitle = text("buttons-header-one")
        default: subtitle = String(format: text("buttons-header-count"), boundCount)
        }
        let name = deviceName.flatMap { $0.isEmpty ? nil : $0 } ?? text("buttons-header-your-mouse")
        return ButtonsHeaderContent(title: name, subtitle: subtitle, part: nil, hint: text("buttons-header-find-hint"))
    }

    private static func text(_ key: String) -> String {
        return NSLocalizedString(key, comment: "")
    }
}

// MARK: - The card

final class ButtonsHeaderView: NSView {

    static let preferredHeight = MouseHeaderView.preferredHeight
    static let cornerRadius = MouseHeaderView.cornerRadius
    static let artworkColumnWidth = MouseHeaderView.artworkColumnWidth
    static let textTrailingInset = MouseHeaderView.textTrailingInset

    var content = ButtonsHeaderContent(title: "", subtitle: nil, part: nil) {
        didSet {
            guard content != oldValue else { return }
            applyContent(animated: window != nil && !prefersReducedMotion())
        }
    }

    /// Reduce Motion in System Settings › Accessibility: the light then switches without fading.
    var prefersReducedMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    let artwork = ButtonsMouseArtworkView()
    let titleLabel = NSTextField(labelWithString: "")
    let subtitleLabel = NSTextField(wrappingLabelWithString: "")
    /// How to find out which button is which, under the subtitle.
    let hintLabel = NSTextField(wrappingLabelWithString: "")

    static var hintFont: NSFont {
        return NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        translatesAutoresizingMaskIntoConstraints = false
        artwork.translatesAutoresizingMaskIntoConstraints = false
        addSubview(artwork)

        titleLabel.font = MouseHeaderView.nameFont
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.font = MouseHeaderView.detailFont
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.isSelectable = false
        subtitleLabel.maximumNumberOfLines = 3
        hintLabel.font = Self.hintFont
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.isSelectable = false
        hintLabel.maximumNumberOfLines = 2
        // The column right of the mouse in the pane's box width; `layout` follows the card.
        let textWidth = PreferencesGroupedForm.boxWidth(paneWidth: PreferencesWindowLayout.contentWidth)
            - Self.artworkColumnWidth - Self.textTrailingInset
        subtitleLabel.preferredMaxLayoutWidth = textWidth
        hintLabel.preferredMaxLayoutWidth = textWidth
        for label in [titleLabel, subtitleLabel, hintLabel] {
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }

        let text = NSStackView(views: [titleLabel, subtitleLabel, hintLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 4
        text.setCustomSpacing(8, after: subtitleLabel)
        text.detachesHiddenViews = true
        text.translatesAutoresizingMaskIntoConstraints = false
        addSubview(text)

        let size = ButtonsMouseArtworkView.size
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.preferredHeight),
            artwork.widthAnchor.constraint(equalToConstant: size.width),
            artwork.heightAnchor.constraint(equalToConstant: size.height),
            artwork.centerXAnchor.constraint(equalTo: leadingAnchor, constant: Self.artworkColumnWidth / 2),
            artwork.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.artworkColumnWidth),
            text.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Self.textTrailingInset),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        applyContent(animated: false)
    }

    override var isFlipped: Bool { return true }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: NSView.noIntrinsicMetric, height: Self.preferredHeight)
    }

    override func layout() {
        super.layout()
        // The subtitle and the hint wrap in the column right of the mouse.
        let width = max(0, bounds.width - Self.artworkColumnWidth - Self.textTrailingInset)
        for label in [subtitleLabel, hintLabel] where width > 0 && abs(label.preferredMaxLayoutWidth - width) > 0.5 {
            label.preferredMaxLayoutWidth = width
        }
    }

    private func applyContent(animated: Bool) {
        titleLabel.stringValue = content.title
        subtitleLabel.stringValue = content.subtitle ?? ""
        subtitleLabel.isHidden = content.subtitle == nil
        hintLabel.stringValue = content.hint ?? ""
        hintLabel.isHidden = content.hint == nil
        artwork.setEmphasis(content.part, animated: animated)
        artwork.setNumber(content.number, animated: animated)
        setAccessibilityLabel([content.title, content.subtitle, content.hint].compactMap { $0 }.joined(separator: ", "))
    }

    override func draw(_ dirtyRect: NSRect) {
        let card = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            xRadius: Self.cornerRadius, yRadius: Self.cornerRadius
        )
        ScrollPreviewPalette.cardFill.setFill()
        card.fill()
        ScrollPreviewPalette.cardEdge.setStroke()
        card.lineWidth = 1
        card.stroke()
    }

    // MARK: Accessibility

    /// One element: what the card says.
    override func isAccessibilityElement() -> Bool {
        return true
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        return .group
    }

    override func accessibilityChildren() -> [Any]? {
        return []
    }
}

// MARK: - The mouse

/// The Mouse pane's mouse (MouseArtworkView, its drawing as it is) with the buttons the
/// Buttons pane names: the two halves above the seam, the wheel, the small button behind
/// it, the thumb panel and the two side buttons above the thumb panel. Each part that can
/// light up has a layer of its own above the drawing, faded in and out.
final class ButtonsMouseArtworkView: NSView {

    static let size = MouseArtworkView.size
    static let fadeDuration = MouseArtworkView.fadeDuration

    private(set) var emphasis: ButtonsMousePart?
    private(set) var highlights: [ButtonsMousePart: ButtonsMouseHighlight] = [:]
    let base = MouseArtworkView()
    /// The number of a button the drawing cannot show, as the row's picture has it.
    let badge = ButtonsMouseNumberBadge()

    init() {
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        base.frame = bounds
        base.autoresizingMask = [.width, .height]
        addSubview(base)
        let sideButtons = ButtonsMouseSideButtonsView(frame: bounds)
        sideButtons.autoresizingMask = [.width, .height]
        addSubview(sideButtons)
        for part in ButtonsMousePart.allCases {
            let highlight = ButtonsMouseHighlight(part: part)
            highlight.frame = bounds
            highlight.autoresizingMask = [.width, .height]
            highlight.alphaValue = 0
            addSubview(highlight)
            highlights[part] = highlight
        }
        badge.alphaValue = 0
        addSubview(badge)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        fatalError("ButtonsMouseArtworkView is built in code")
    }

    /// Where the badge's middle is: on the body's right edge, low, where the row's picture
    /// has it.
    static let badgeCentre = MouseArtworkView.point(72, 98)

    /// Shows `number` on the badge, or fades the badge out (nil).
    func setNumber(_ number: Int?, animated: Bool) {
        if let number {
            badge.number = number
            let size = ButtonsMouseMiniature.badgeSize(
                for: number, font: ButtonsMouseNumberBadge.font, height: ButtonsMouseNumberBadge.height
            )
            badge.frame = NSRect(
                x: Self.badgeCentre.x - size.width / 2, y: Self.badgeCentre.y - size.height / 2,
                width: size.width, height: size.height
            )
        }
        let alpha: CGFloat = number == nil ? 0 : 1
        guard animated else {
            badge.alphaValue = alpha
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            badge.animator().alphaValue = alpha
        }
    }

    override var isFlipped: Bool { return true }

    override var intrinsicContentSize: NSSize { return Self.size }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    /// Lights `part` up and puts out the others.
    func setEmphasis(_ part: ButtonsMousePart?, animated: Bool) {
        emphasis = part
        let change = {
            for (candidate, highlight) in self.highlights {
                let alpha: CGFloat = candidate == part ? 1 : 0
                if animated {
                    highlight.animator().alphaValue = alpha
                } else {
                    highlight.alphaValue = alpha
                }
            }
        }
        guard animated else { return change() }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            change()
        }
    }

    // MARK: Geometry (view coordinates, on MouseArtworkView's grid)

    /// The left (or right) button: the body above the seam, on its side of the split.
    static func buttonAreaPath(left: Bool) -> NSBezierPath {
        let p = MouseArtworkView.point
        let above = NSBezierPath()
        above.move(to: p(-4, 48))
        above.line(to: p(13, 48))
        above.curve(to: p(78, 43), controlPoint1: p(32, 59), controlPoint2: p(56, 59))
        above.line(to: p(82, 43))
        above.line(to: p(82, -4))
        above.line(to: p(-4, -4))
        above.close()
        let side = NSBezierPath()
        if left {
            side.move(to: p(-4, -4))
            side.line(to: p(38.5, -4))
            side.line(to: p(39.5, 60))
            side.line(to: p(-4, 60))
        } else {
            side.move(to: p(38.5, -4))
            side.line(to: p(82, -4))
            side.line(to: p(82, 60))
            side.line(to: p(39.5, 60))
        }
        side.close()
        let shape = MouseArtworkView.bodyPath().cgPath.intersection(above.cgPath).intersection(side.cgPath)
        return NSBezierPath(cgPath: shape)
    }

    /// A side button: a capsule along the left edge above the thumb panel, `index` 0 the
    /// one nearer the front (Forward), 1 the one behind it (Back).
    static func sideButtonPath(index: Int) -> NSBezierPath {
        let centres = [MouseArtworkView.point(17.4, 55.6), MouseArtworkView.point(13.0, 62.6)]
        let centre = centres[index]
        let scale = MouseArtworkView.bodySize.width / MouseArtworkView.designSize.width
        let length = 7.5 * scale
        let width = 4.2 * scale
        let path = NSBezierPath(
            roundedRect: NSRect(x: -length / 2, y: -width / 2, width: length, height: width),
            xRadius: width / 2, yRadius: width / 2
        )
        // Along the ledge, from (14, 52) down to (5, 66).
        let angle = atan2(14 * MouseArtworkView.bodySize.height / MouseArtworkView.designSize.height, -9 * scale)
        path.transform(using: AffineTransform(
            m11: cos(angle), m12: sin(angle), m21: -sin(angle), m22: cos(angle),
            tX: centre.x, tY: centre.y
        ))
        return path
    }

    static var forwardButtonPath: NSBezierPath { return sideButtonPath(index: 0) }
    static var backButtonPath: NSBezierPath { return sideButtonPath(index: 1) }

    /// The small button behind the wheel.
    static var modeShiftPath: NSBezierPath {
        return NSBezierPath(roundedRect: MouseArtworkView.backButtonRect, xRadius: 3, yRadius: 3)
    }

    /// The wheel, its slot and the small button behind it, as the base drawing has them.
    static func drawWheelAndModeShift() {
        for (rect, radius) in [(MouseArtworkView.wellRect, MouseArtworkView.wellRect.width / 2), (MouseArtworkView.backButtonRect, 3)] {
            let shape = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
            ScrollPreviewPalette.mouseFill.setFill()
            shape.fill()
            ScrollPreviewPalette.wheelWell.setFill()
            shape.fill()
            ScrollPreviewPalette.mouseSeam.setStroke()
            shape.lineWidth = 1
            shape.stroke()
        }
        MouseArtworkHighlight.drawWheel(in: MouseArtworkView.wheelRect, fill: MouseArtworkPalette.wheel, ridges: MouseArtworkPalette.wheelRidge)
    }
}

/// A button's number in the accent colour, by the mouse: the card is about a button the
/// drawing cannot show.
final class ButtonsMouseNumberBadge: NSView {

    static let height: CGFloat = 20
    static var font: NSFont {
        return NSFont.systemFont(ofSize: 12, weight: .bold)
    }

    /// The number shown; kept while the badge fades out.
    var number: Int? {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { return true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let number else { return }
        ButtonsMouseMiniature.drawBadge(number, in: bounds, font: Self.font, fill: .controlAccentColor, text: .white)
    }
}

/// The two side buttons, drawn like the small button behind the wheel.
final class ButtonsMouseSideButtonsView: NSView {

    override var isFlipped: Bool { return true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        for shape in [ButtonsMouseArtworkView.forwardButtonPath, ButtonsMouseArtworkView.backButtonPath] {
            ScrollPreviewPalette.mouseFill.setFill()
            shape.fill()
            ScrollPreviewPalette.wheelWell.setFill()
            shape.fill()
            ScrollPreviewPalette.mouseSeam.setStroke()
            shape.lineWidth = 1
            shape.stroke()
        }
    }
}

/// One part of the mouse in the accent colour, with a glow, as the Mouse pane lights its
/// parts. Lies on top of the drawing.
final class ButtonsMouseHighlight: NSView {

    let part: ButtonsMousePart

    init(part: ButtonsMousePart) {
        self.part = part
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("ButtonsMouseHighlight is built in code")
    }

    override var isFlipped: Bool { return true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let accent = NSColor.controlAccentColor
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = accent.withAlphaComponent(0.65)
        glow.shadowBlurRadius = 6
        glow.shadowOffset = .zero
        glow.set()
        accent.setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()

        switch part {
        case .left, .right:
            // The wheel stays a wheel on a lit button.
            ButtonsMouseArtworkView.drawWheelAndModeShift()
        case .middle:
            MouseArtworkHighlight.drawWheel(in: MouseArtworkView.wheelRect, fill: accent, ridges: NSColor(white: 1, alpha: 0.6))
        case .back, .forward, .gesture, .modeShift:
            break
        }
    }

    private var shape: NSBezierPath {
        switch part {
        case .left: return ButtonsMouseArtworkView.buttonAreaPath(left: true)
        case .right: return ButtonsMouseArtworkView.buttonAreaPath(left: false)
        case .middle: return MouseArtworkHighlight.capsule(MouseArtworkView.wheelRect)
        case .back: return ButtonsMouseArtworkView.backButtonPath
        case .forward: return ButtonsMouseArtworkView.forwardButtonPath
        case .gesture: return MouseArtworkView.thumbPanelPath()
        case .modeShift: return ButtonsMouseArtworkView.modeShiftPath
        }
    }
}
