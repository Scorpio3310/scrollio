//
//  MouseHeaderView.swift
//  Mos
//  The card at the top of the Mouse tab: on the left the mouse seen from above, on the
//  right its name, that it is connected and its battery. The part of the mouse the setting
//  under the pointer (or with the keyboard focus) is about lights up in the accent colour.
//  Without a Logitech mouse the card shows a plain two-button mouse and says that the app
//  works with any mouse. The card has the look of the Scrolling tab's preview cards
//  (ScrollPreviewPalette).
//

import Cocoa

final class MouseHeaderView: NSView {

    static let preferredHeight: CGFloat = 150
    static let cornerRadius: CGFloat = 10
    /// The mouse is centred in this much of the card's left side; the text starts after it.
    static let artworkColumnWidth: CGFloat = 170
    /// Right of the text.
    static let textTrailingInset: CGFloat = 20
    /// The line under the name wraps; more than this many lines are cut off.
    static let detailMaximumLines = 3

    static var nameFont: NSFont {
        return NSFont.systemFont(ofSize: 17, weight: .semibold)
    }

    static var detailFont: NSFont {
        return NSFont.systemFont(ofSize: NSFont.systemFontSize)
    }

    var content = MousePaneModel.Header(title: "", subtitle: nil, battery: nil, isConnected: false) {
        didSet {
            if content != oldValue { applyContent() }
        }
    }

    /// The part that is lit up; nil: none.
    var emphasis: MousePart? {
        didSet {
            guard emphasis != oldValue else { return }
            artwork.setEmphasis(emphasis, animated: window != nil && !prefersReducedMotion())
        }
    }

    /// Reduce Motion in System Settings › Accessibility: the light then switches without fading.
    var prefersReducedMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    let artwork = MouseArtworkView()
    let nameLabel = NSTextField(labelWithString: "")
    let statusLabel = NSTextField(wrappingLabelWithString: "")
    let batteryIcon = NSImageView()
    let batteryLabel = NSTextField(labelWithString: "")
    private let batteryLine = NSStackView()

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

        nameLabel.font = Self.nameFont
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        statusLabel.font = Self.detailFont
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.isSelectable = false
        statusLabel.maximumNumberOfLines = Self.detailMaximumLines
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.cell?.truncatesLastVisibleLine = true
        batteryLabel.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        batteryLabel.textColor = .secondaryLabelColor
        for label in [nameLabel, statusLabel, batteryLabel] {
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }

        batteryIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: NSFont.systemFontSize, weight: .regular)
        batteryIcon.imageScaling = .scaleNone
        batteryIcon.setContentHuggingPriority(.required, for: .horizontal)
        // The text says it; the picture is read out with it.
        batteryIcon.setAccessibilityElement(false)
        batteryLine.orientation = .horizontal
        batteryLine.alignment = .centerY
        batteryLine.spacing = 5
        batteryLine.addArrangedSubview(batteryIcon)
        batteryLine.addArrangedSubview(batteryLabel)

        let text = NSStackView(views: [nameLabel, statusLabel, batteryLine])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 3
        text.setCustomSpacing(4, after: nameLabel)
        text.detachesHiddenViews = true
        text.translatesAutoresizingMaskIntoConstraints = false
        addSubview(text)

        let artworkSize = MouseArtworkView.size
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.preferredHeight),
            artwork.widthAnchor.constraint(equalToConstant: artworkSize.width),
            artwork.heightAnchor.constraint(equalToConstant: artworkSize.height),
            artwork.centerXAnchor.constraint(equalTo: leadingAnchor, constant: Self.artworkColumnWidth / 2),
            artwork.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.artworkColumnWidth),
            text.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Self.textTrailingInset),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        applyContent()
    }

    override var isFlipped: Bool { return true }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: NSView.noIntrinsicMetric, height: Self.preferredHeight)
    }

    /// The text column ends `textTrailingInset` before the card's edge: the line under the
    /// name wraps there.
    override func layout() {
        let width = max(0, bounds.width - Self.artworkColumnWidth - Self.textTrailingInset)
        if statusLabel.preferredMaxLayoutWidth != width {
            statusLabel.preferredMaxLayoutWidth = width
        }
        super.layout()
    }

    private func applyContent() {
        nameLabel.stringValue = content.title
        statusLabel.stringValue = content.subtitle ?? ""
        statusLabel.isHidden = content.subtitle == nil
        artwork.style = content.isConnected ? .mxMaster : .anyMouse
        if let battery = content.battery {
            batteryLine.isHidden = false
            batteryLabel.stringValue = battery.text
            batteryLabel.setAccessibilityLabel(battery.accessibilityLabel)
            batteryIcon.image = NSImage(systemSymbolName: battery.symbolName, accessibilityDescription: nil)
            let tint: NSColor = battery.isLow ? .systemRed : .secondaryLabelColor
            batteryIcon.contentTintColor = tint
            batteryLabel.textColor = battery.isLow ? .systemRed : .secondaryLabelColor
        } else {
            batteryLine.isHidden = true
            batteryLabel.stringValue = ""
            batteryIcon.image = nil
        }
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
}

// MARK: - The mouse

/// A right-handed mouse in the shape of an MX Master, seen from above in line art: the wheel
/// between the two buttons, a small button behind it and the thumb rest on the left. Each
/// part that can light up has a layer of its own above the drawing, faded in and out.
/// `anyMouse` draws a plain symmetric mouse instead (two buttons and a wheel), with nothing
/// to light up.
final class MouseArtworkView: NSView {

    enum Style {
        /// The connected Logitech mouse.
        case mxMaster
        /// Any mouse: shown while no Logitech mouse is connected.
        case anyMouse
    }

    var style: Style = .mxMaster {
        didSet {
            guard style != oldValue else { return }
            for highlight in highlights.values {
                highlight.isHidden = style != .mxMaster
            }
            needsDisplay = true
        }
    }

    /// The drawing is laid out on this grid (top-left origin) and scaled to `bodySize`.
    static let designSize = NSSize(width: 78, height: 120)
    static let bodySize = NSSize(width: 72, height: 111)
    /// Room around the body for its shadow and the glow of a lit part.
    static let margin: CGFloat = 9
    static let size = NSSize(width: bodySize.width + 2 * margin, height: bodySize.height + 2 * margin)
    static let fadeDuration: TimeInterval = 0.18

    private(set) var emphasis: MousePart?
    private(set) var highlights: [MousePart: MouseArtworkHighlight] = [:]

    init() {
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        for part in MousePart.allCases {
            let highlight = MouseArtworkHighlight(part: part)
            highlight.frame = bounds
            highlight.autoresizingMask = [.width, .height]
            highlight.alphaValue = 0
            addSubview(highlight)
            highlights[part] = highlight
        }
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        fatalError("MouseArtworkView is built in code")
    }

    override var isFlipped: Bool { return true }

    override var intrinsicContentSize: NSSize { return Self.size }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    /// Lights `part` up and puts out the others.
    func setEmphasis(_ part: MousePart?, animated: Bool) {
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

    // MARK: Geometry (view coordinates)

    /// A point of the design grid in the view.
    static func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        return NSPoint(
            x: margin + x * bodySize.width / designSize.width,
            y: margin + y * bodySize.height / designSize.height
        )
    }

    static func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
        let origin = point(x, y)
        let end = point(x + width, y + height)
        return NSRect(x: origin.x, y: origin.y, width: end.x - origin.x, height: end.y - origin.y)
    }

    /// Narrow at the front, the right side gently curved, and on the left a ledge where the
    /// thumb rest juts out.
    static func bodyPath() -> NSBezierPath {
        let p = point
        let path = NSBezierPath()
        path.move(to: p(38, 1))
        path.curve(to: p(68, 16), controlPoint1: p(52, 0), controlPoint2: p(64, 6))
        path.curve(to: p(76, 66), controlPoint1: p(73, 30), controlPoint2: p(77, 48))
        path.curve(to: p(58, 118), controlPoint1: p(76, 96), controlPoint2: p(71, 118))
        path.curve(to: p(18, 114), controlPoint1: p(44, 119), controlPoint2: p(27, 118))
        path.curve(to: p(2, 90), controlPoint1: p(9, 110), controlPoint2: p(1, 101))
        path.curve(to: p(5, 66), controlPoint1: p(3, 79), controlPoint2: p(2, 71))
        path.curve(to: p(14, 52), controlPoint1: p(7, 60), controlPoint2: p(11, 55))
        path.curve(to: p(14, 22), controlPoint1: p(16, 44), controlPoint2: p(13, 32))
        path.curve(to: p(38, 1), controlPoint1: p(16, 9), controlPoint2: p(26, 1))
        path.close()
        return path
    }

    static var wheelRect: NSRect {
        return rect(34.5, 10, 10, 26)
    }

    /// The slot the wheel turns in.
    static var wellRect: NSRect {
        return wheelRect.insetBy(dx: -3, dy: -3)
    }

    /// The small button behind the wheel.
    static var backButtonRect: NSRect {
        return rect(36, 43, 7, 9)
    }

    /// Where the two buttons end, and the split between them (clipped by the body).
    static func seamPath() -> NSBezierPath {
        let p = point
        let path = NSBezierPath()
        path.move(to: p(13, 48))
        path.curve(to: p(78, 43), controlPoint1: p(32, 59), controlPoint2: p(56, 59))
        path.move(to: p(38.5, 0))
        path.line(to: p(39.5, 56))
        return path
    }

    /// A plain mouse, the same size: symmetric, rounder at the back.
    static func anyMouseBodyPath() -> NSBezierPath {
        let p = point
        let path = NSBezierPath()
        path.move(to: p(39, 1))
        path.curve(to: p(70, 34), controlPoint1: p(57, 1), controlPoint2: p(68, 14))
        path.curve(to: p(73, 84), controlPoint1: p(72, 50), controlPoint2: p(74, 68))
        path.curve(to: p(39, 119), controlPoint1: p(72, 106), controlPoint2: p(58, 119))
        path.curve(to: p(5, 84), controlPoint1: p(20, 119), controlPoint2: p(6, 106))
        path.curve(to: p(8, 34), controlPoint1: p(4, 68), controlPoint2: p(6, 50))
        path.curve(to: p(39, 1), controlPoint1: p(10, 14), controlPoint2: p(21, 1))
        path.close()
        return path
    }

    /// The plain mouse's wheel, on its middle line.
    static var anyMouseWheelRect: NSRect {
        return rect(34, 11, 10, 24)
    }

    /// Where the plain mouse's two buttons end, and the split between them.
    static func anyMouseSeamPath() -> NSBezierPath {
        let p = point
        let path = NSBezierPath()
        path.move(to: p(4, 46))
        path.curve(to: p(74, 46), controlPoint1: p(24, 56), controlPoint2: p(54, 56))
        path.move(to: p(39, 0))
        path.line(to: p(39, 51))
        return path
    }

    /// The thumb rest's panel: a rounded strip along the left edge.
    static func thumbPanelPath() -> NSBezierPath {
        let top = point(10.5, 71)
        let bottom = point(14.5, 103)
        let width = 8 * bodySize.width / designSize.width
        let dx = bottom.x - top.x
        let dy = bottom.y - top.y
        let length = (dx * dx + dy * dy).squareRoot() + width
        let path = NSBezierPath(
            roundedRect: NSRect(x: -length / 2, y: -width / 2, width: length, height: width),
            xRadius: width / 2, yRadius: width / 2
        )
        let angle = atan2(dy, dx)
        path.transform(using: AffineTransform(
            m11: cos(angle), m12: sin(angle), m21: -sin(angle), m22: cos(angle),
            tX: (top.x + bottom.x) / 2, tY: (top.y + bottom.y) / 2
        ))
        return path
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        switch style {
        case .mxMaster: drawMXMaster()
        case .anyMouse: drawAnyMouse()
        }
    }

    /// A soft shadow under the mouse, cast by a copy of `outline` that is moved down and
    /// then covered by the body.
    private func drawShadow(of outline: NSBezierPath) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = ScrollPreviewPalette.mouseShadow
        shadow.shadowBlurRadius = 5
        shadow.shadowOffset = .zero
        shadow.set()
        ScrollPreviewPalette.mouseShadow.setFill()
        let cast = outline.copy() as! NSBezierPath
        cast.transform(using: AffineTransform(translationByX: 0, byY: 2))
        cast.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawAnyMouse() {
        let outline = Self.anyMouseBodyPath()
        drawShadow(of: outline)
        ScrollPreviewPalette.mouseFill.setFill()
        outline.fill()

        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        let seams = Self.anyMouseSeamPath()
        seams.lineWidth = 1
        ScrollPreviewPalette.mouseSeam.setStroke()
        seams.stroke()
        NSGraphicsContext.restoreGraphicsState()

        let well = Self.anyMouseWheelRect.insetBy(dx: -3, dy: -3)
        let slot = NSBezierPath(roundedRect: well, xRadius: well.width / 2, yRadius: well.width / 2)
        ScrollPreviewPalette.mouseFill.setFill()
        slot.fill()
        ScrollPreviewPalette.wheelWell.setFill()
        slot.fill()
        ScrollPreviewPalette.mouseSeam.setStroke()
        slot.lineWidth = 1
        slot.stroke()
        MouseArtworkHighlight.drawWheel(in: Self.anyMouseWheelRect, fill: MouseArtworkPalette.wheel, ridges: MouseArtworkPalette.wheelRidge)

        ScrollPreviewPalette.mouseLine.setStroke()
        outline.lineWidth = 1.5
        outline.stroke()
    }

    private func drawMXMaster() {
        let outline = Self.bodyPath()

        drawShadow(of: outline)

        ScrollPreviewPalette.mouseFill.setFill()
        outline.fill()

        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        let seams = Self.seamPath()
        seams.lineWidth = 1
        ScrollPreviewPalette.mouseSeam.setStroke()
        seams.stroke()
        NSGraphicsContext.restoreGraphicsState()

        // The slot of the wheel and the button behind it cover the split.
        for (rect, radius) in [(Self.wellRect, Self.wellRect.width / 2), (Self.backButtonRect, 3)] {
            let shape = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
            ScrollPreviewPalette.mouseFill.setFill()
            shape.fill()
            ScrollPreviewPalette.wheelWell.setFill()
            shape.fill()
            ScrollPreviewPalette.mouseSeam.setStroke()
            shape.lineWidth = 1
            shape.stroke()
        }
        MouseArtworkHighlight.drawWheel(in: Self.wheelRect, fill: MouseArtworkPalette.wheel, ridges: MouseArtworkPalette.wheelRidge)

        let panel = Self.thumbPanelPath()
        MouseArtworkPalette.panel.setFill()
        panel.fill()
        ScrollPreviewPalette.mouseSeam.setStroke()
        panel.lineWidth = 1
        panel.stroke()

        ScrollPreviewPalette.mouseLine.setStroke()
        outline.lineWidth = 1.5
        outline.stroke()
    }
}

enum MouseArtworkPalette {
    static let wheel = ScrollPreviewPalette.adaptive(
        light: NSColor(white: 0.62, alpha: 1),
        dark: NSColor(white: 0.52, alpha: 1)
    )
    static let wheelRidge = NSColor(white: 1, alpha: 0.55)
    static let panel = ScrollPreviewPalette.adaptive(
        light: NSColor(white: 0, alpha: 0.05),
        dark: NSColor(white: 1, alpha: 0.07)
    )
}

/// One part of the mouse in the accent colour, with a glow. Lies on top of the drawing.
final class MouseArtworkHighlight: NSView {

    let part: MousePart

    init(part: MousePart) {
        self.part = part
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("MouseArtworkHighlight is built in code")
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
        switch part {
        case .body:
            let outline = MouseArtworkView.bodyPath()
            accent.setStroke()
            outline.lineWidth = 2
            outline.stroke()
        case .wheel:
            accent.setFill()
            Self.capsule(MouseArtworkView.wheelRect).fill()
        case .thumbPanel:
            accent.setFill()
            MouseArtworkView.thumbPanelPath().fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        if part == .wheel {
            Self.drawWheel(in: MouseArtworkView.wheelRect, fill: accent, ridges: NSColor(white: 1, alpha: 0.6))
        }
    }

    static func capsule(_ rect: NSRect) -> NSBezierPath {
        let radius = min(rect.width, rect.height) / 2
        return NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    }

    /// The wheel: a capsule with ridges across it, closer together towards its ends.
    static func drawWheel(in rect: NSRect, fill: NSColor, ridges: NSColor) {
        let body = capsule(rect)
        fill.setFill()
        body.fill()
        NSGraphicsContext.saveGraphicsState()
        body.addClip()
        for step in -2...2 {
            let angle = Double(step) * Double.pi / 6
            let y = rect.midY + rect.height / 2 * CGFloat(sin(angle))
            let facing = CGFloat(cos(angle))
            let ridge = NSBezierPath()
            ridge.move(to: NSPoint(x: rect.minX + 2.5, y: y))
            ridge.line(to: NSPoint(x: rect.maxX - 2.5, y: y))
            ridge.lineWidth = 1
            ridge.lineCapStyle = .round
            ridges.withAlphaComponent(ridges.alphaComponent * facing).setStroke()
            ridge.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}
