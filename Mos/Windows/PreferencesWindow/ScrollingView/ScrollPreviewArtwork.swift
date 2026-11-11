//
//  ScrollPreviewArtwork.swift
//  Mos
//  The drawing of ScrollPreviewView: the two cards and what is on them. Everything is
//  drawn with paths, so it is sharp at any scale, in light and in dark.
//
//  The parts that move are views of their own (the wheel, the key, the page, the scroller
//  thumb): a frame of the demo then redraws a few square points or only moves a view.
//

import Cocoa

// MARK: - Colours

enum ScrollPreviewPalette {

    static func adaptive(light: NSColor, dark: NSColor) -> NSColor {
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    private static func ink(_ light: CGFloat, _ dark: CGFloat) -> NSColor {
        return adaptive(light: NSColor(white: 0, alpha: light), dark: NSColor(white: 1, alpha: dark))
    }

    // The cards (also the Mouse and Buttons cards). Under Increase Contrast the edge is as
    // clear as the outline of the kit's boxes.
    static let cardFill = ink(0.04, 0.055)
    static let cardEdge = NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        if PreferencesGroupedForm.isHighContrast(appearance) {
            return NSColor(white: dark ? 1 : 0, alpha: dark ? 0.5 : 0.45)
        }
        return NSColor(white: dark ? 1 : 0, alpha: dark ? 0.09 : 0.07)
    }

    // The mouse and the key
    static let mouseFill = adaptive(light: .white, dark: NSColor(white: 0.27, alpha: 1))
    static let mouseLine = ink(0.58, 0.70)
    static let mouseShadow = adaptive(light: NSColor(white: 0, alpha: 0.30), dark: NSColor(white: 0, alpha: 0.55))
    static let mouseSeam = ink(0.20, 0.26)
    static let wheelWell = ink(0.07, 0.16)
    static let keyFace = adaptive(light: .white, dark: NSColor(white: 0.30, alpha: 1))
    static let keySide = adaptive(light: NSColor(white: 0.80, alpha: 1), dark: NSColor(white: 0.16, alpha: 1))
    static let keyEdge = ink(0.30, 0.34)
    static let keyGlyph = ink(0.62, 0.78)

    // The desktop
    static let desktopStart = adaptive(
        light: NSColor(srgbRed: 0.60, green: 0.80, blue: 0.99, alpha: 1),
        dark: NSColor(srgbRed: 0.07, green: 0.20, blue: 0.42, alpha: 1)
    )
    static let desktopEnd = adaptive(
        light: NSColor(srgbRed: 0.86, green: 0.76, blue: 0.98, alpha: 1),
        dark: NSColor(srgbRed: 0.27, green: 0.15, blue: 0.43, alpha: 1)
    )
    static let menuBar = adaptive(light: NSColor(white: 1, alpha: 0.5), dark: NSColor(white: 0, alpha: 0.3))
    static let menuItem = ink(0.35, 0.5)

    // The window
    static let windowBody = adaptive(light: .white, dark: NSColor(white: 0.13, alpha: 1))
    static let windowTitleBar = adaptive(light: NSColor(white: 0.93, alpha: 1), dark: NSColor(white: 0.22, alpha: 1))
    static let windowTitleLine = adaptive(light: NSColor(white: 0, alpha: 0.10), dark: NSColor(white: 0, alpha: 0.55))
    static let windowEdge = ink(0.16, 0.24)
    static let windowShadow = adaptive(light: NSColor(white: 0, alpha: 0.5), dark: NSColor(white: 0, alpha: 0.8))
    static let trafficLights = [
        NSColor(srgbRed: 1.00, green: 0.37, blue: 0.34, alpha: 1),
        NSColor(srgbRed: 1.00, green: 0.74, blue: 0.18, alpha: 1),
        NSColor(srgbRed: 0.16, green: 0.78, blue: 0.25, alpha: 1),
    ]

    // The page
    static let pageHeading = ink(0.50, 0.62)
    static let pageLine = ink(0.15, 0.20)
    static let scrollerThumb = ink(0.26, 0.36)
}

private extension NSColor {
    /// `self` mixed towards `other`, both read in the appearance that is being drawn.
    func mixed(_ fraction: CGFloat, with other: NSColor) -> NSColor {
        return blended(withFraction: min(1, max(0, fraction)), of: other) ?? self
    }
}

private func capsule(_ rect: NSRect) -> NSBezierPath {
    let radius = min(rect.width, rect.height) / 2
    return NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

/// Base class of the artwork: top-left origin, and nothing here takes a click.
class ScrollPreviewArtworkView: NSView {
    override var isFlipped: Bool { return true }

    init() {
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}

// MARK: - The device card

/// The left card: the mouse, and beside it the key the scene is about.
final class ScrollPreviewDeviceCard: ScrollPreviewArtworkView {

    static let cornerRadius: CGFloat = 10
    /// Between the key and the mouse.
    static let keySpacing: CGFloat = 14

    private let mouse = ScrollPreviewMouse()
    private let key = ScrollPreviewKeyCap()
    private var emphasis: ScrollPreviewView.Emphasis = .wheel

    override init() {
        super.init()
        key.isHidden = true
        addSubview(key)
        addSubview(mouse)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    static func glyph(for emphasis: ScrollPreviewView.Emphasis) -> String? {
        switch emphasis {
        case .wheel: return nil
        case .faster: return "⌥"
        case .sideways: return "⇧"
        case .paused: return "⌘"
        }
    }

    /// Places the mouse, alone or with the key to its left; the pair is centred in the card.
    func setEmphasis(_ emphasis: ScrollPreviewView.Emphasis, animated: Bool) {
        self.emphasis = emphasis
        let glyph = Self.glyph(for: emphasis)
        let showsKey = glyph != nil
        if let glyph {
            key.glyph = glyph
        }

        let mouseSize = ScrollPreviewMouse.size
        let keySize = ScrollPreviewKeyCap.size
        // What is centred is the drawing: the views carry a margin around it.
        let keyWidth = ScrollPreviewKeyCap.faceSize.width
        let bodyWidth = ScrollPreviewMouse.bodySize.width
        let groupWidth = showsKey ? keyWidth + Self.keySpacing + bodyWidth : bodyWidth
        let left = ((bounds.width - groupWidth) / 2).rounded()
        let keyOrigin = NSPoint(
            x: left - ScrollPreviewKeyCap.margin,
            y: ((bounds.height - keySize.height) / 2).rounded()
        )
        let mouseOrigin = NSPoint(
            x: (showsKey ? left + keyWidth + Self.keySpacing : left) - ScrollPreviewMouse.margin,
            y: ((bounds.height - mouseSize.height) / 2).rounded()
        )
        key.setFrameSize(keySize)
        mouse.setFrameSize(mouseSize)
        key.setFrameOrigin(keyOrigin)

        guard animated, window != nil else {
            mouse.setFrameOrigin(mouseOrigin)
            key.alphaValue = 1
            key.isHidden = !showsKey
            return
        }
        if showsKey && key.isHidden {
            key.alphaValue = 0
            key.isHidden = false
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            mouse.animator().setFrameOrigin(mouseOrigin)
            key.animator().alphaValue = showsKey ? 1 : 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.key.isHidden = self.emphasis == .wheel
        })
    }

    func show(wheelTurn: Double, pulse: Double, keyDepth: Double) {
        mouse.wheel.show(turn: wheelTurn, pulse: pulse)
        key.depth = CGFloat(keyDepth)
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

/// A mouse seen from above, in line art. The wheel is a view of its own.
final class ScrollPreviewMouse: ScrollPreviewArtworkView {

    static let bodySize = NSSize(width: 62, height: 100)
    /// Room around the body for its outline and the flash of the wheel.
    static let margin: CGFloat = 8
    static let size = NSSize(width: bodySize.width + 2 * margin, height: bodySize.height + 2 * margin)
    /// The wheel inside the body: centred, this far from its top.
    static let wheelSize = NSSize(width: 11, height: 28)
    static let wheelTop: CGFloat = 18
    /// The slot the wheel sits in is this much larger on every side.
    static let wellInset: CGFloat = 3
    /// Where the two buttons end (from the top of the body).
    static let seamY: CGFloat = 54

    let wheel = ScrollPreviewWheel()

    override init() {
        super.init()
        let wheelRect = Self.wheelRect.insetBy(dx: -ScrollPreviewWheel.margin, dy: -ScrollPreviewWheel.margin)
        wheel.frame = wheelRect
        addSubview(wheel)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    private static var bodyRect: NSRect {
        return NSRect(x: margin, y: margin, width: bodySize.width, height: bodySize.height)
    }

    private static var wheelRect: NSRect {
        let body = bodyRect
        return NSRect(
            x: body.midX - wheelSize.width / 2, y: body.minY + wheelTop,
            width: wheelSize.width, height: wheelSize.height
        )
    }

    /// Rounded shoulders at the top, a fuller palm rest at the bottom.
    private static func bodyPath(in r: NSRect) -> NSBezierPath {
        let path = NSBezierPath()
        let shoulder = r.minY + 38
        let palm = r.maxY - 35
        path.move(to: NSPoint(x: r.minX, y: shoulder))
        path.curve(
            to: NSPoint(x: r.midX, y: r.minY),
            controlPoint1: NSPoint(x: r.minX, y: r.minY + 14),
            controlPoint2: NSPoint(x: r.minX + 12, y: r.minY)
        )
        path.curve(
            to: NSPoint(x: r.maxX, y: shoulder),
            controlPoint1: NSPoint(x: r.maxX - 12, y: r.minY),
            controlPoint2: NSPoint(x: r.maxX, y: r.minY + 14)
        )
        path.line(to: NSPoint(x: r.maxX, y: palm))
        path.curve(
            to: NSPoint(x: r.midX, y: r.maxY),
            controlPoint1: NSPoint(x: r.maxX, y: r.maxY - 13),
            controlPoint2: NSPoint(x: r.maxX - 13, y: r.maxY)
        )
        path.curve(
            to: NSPoint(x: r.minX, y: palm),
            controlPoint1: NSPoint(x: r.minX + 13, y: r.maxY),
            controlPoint2: NSPoint(x: r.minX, y: r.maxY - 13)
        )
        path.close()
        return path
    }

    override func draw(_ dirtyRect: NSRect) {
        let body = Self.bodyRect
        let outline = Self.bodyPath(in: body)

        // A soft shadow under the mouse, cast by a copy that is moved down and then covered
        // (see the window's shadow in ScrollPreviewScreenCard).
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = ScrollPreviewPalette.mouseShadow
        shadow.shadowBlurRadius = 5
        shadow.shadowOffset = .zero
        shadow.set()
        ScrollPreviewPalette.mouseShadow.setFill()
        Self.bodyPath(in: body.insetBy(dx: 2, dy: 2).offsetBy(dx: 0, dy: 2)).fill()
        NSGraphicsContext.restoreGraphicsState()

        ScrollPreviewPalette.mouseFill.setFill()
        outline.fill()

        // The seams between the buttons, kept inside the outline.
        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        let seams = NSBezierPath()
        let seamY = body.minY + Self.seamY
        seams.move(to: NSPoint(x: body.minX, y: seamY - 3))
        seams.curve(
            to: NSPoint(x: body.maxX, y: seamY - 3),
            controlPoint1: NSPoint(x: body.minX + 18, y: seamY + 3),
            controlPoint2: NSPoint(x: body.maxX - 18, y: seamY + 3)
        )
        seams.move(to: NSPoint(x: body.midX, y: body.minY))
        seams.line(to: NSPoint(x: body.midX, y: seamY + 1.5))
        seams.lineWidth = 1
        ScrollPreviewPalette.mouseSeam.setStroke()
        seams.stroke()
        NSGraphicsContext.restoreGraphicsState()

        // The slot of the wheel covers the seam behind it.
        let well = capsule(Self.wheelRect.insetBy(dx: -Self.wellInset, dy: -Self.wellInset))
        ScrollPreviewPalette.mouseFill.setFill()
        well.fill()
        ScrollPreviewPalette.wheelWell.setFill()
        well.fill()
        ScrollPreviewPalette.mouseSeam.setStroke()
        well.lineWidth = 1
        well.stroke()

        ScrollPreviewPalette.mouseLine.setStroke()
        outline.lineWidth = 1.5
        outline.stroke()
    }
}

/// The wheel, in the accent colour. Its ridges travel over it as it turns, bunching up
/// towards the ends as on a real cylinder, and every click flashes. One ridge is a bright
/// notch mark: it starts on the far half of the wheel, a burst of three clicks carries it
/// to the near half and the burst back returns it, so the direction of the turn can be
/// followed with the eye.
final class ScrollPreviewWheel: ScrollPreviewArtworkView {

    /// Room around the wheel for the flash.
    static let margin: CGFloat = 7
    /// One click turns the wheel by one ridge.
    static let ridgeAngle = Double.pi / 6
    /// Where the notch mark is before the loop's first click: as far before the middle of
    /// the wheel as a burst leaves it behind it.
    static let markStartAngle = -ridgeAngle * Double(ScrollPreviewLoop.clicksPerBurst) / 2

    private var turn = 0.0
    private var pulse = 0.0

    func show(turn: Double, pulse: Double) {
        guard turn != self.turn || pulse != self.pulse else { return }
        self.turn = turn
        self.pulse = pulse
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: Self.margin, dy: Self.margin)
        let accent = NSColor.controlAccentColor
        let glow = CGFloat(min(1, max(0, pulse)))

        // The flash of a click: a ring that opens up and fades.
        if glow > 0 {
            let spread = 1 + (1 - glow) * (Self.margin - 2)
            accent.withAlphaComponent(0.42 * glow).setFill()
            capsule(rect.insetBy(dx: -spread, dy: -spread)).fill()
        }

        let body = capsule(rect)
        accent.mixed(0.22 * glow, with: .white).setFill()
        body.fill()

        NSGraphicsContext.saveGraphicsState()
        body.addClip()
        // Angles around the wheel: −90° at its far end, 0 in the middle, +90° at the near end.
        let markAngle = Self.markStartAngle + turn * Self.ridgeAngle
        let reach = Int((Double.pi / Self.ridgeAngle).rounded(.up)) + 1
        let nearest = ((0 - markAngle) / Self.ridgeAngle).rounded()
        for offset in -reach...reach {
            let index = nearest + Double(offset)
            let angle = markAngle + index * Self.ridgeAngle
            guard abs(angle) < Double.pi / 2 else { continue }
            let facing = CGFloat(cos(angle))
            let isMark = index == 0
            let y = rect.midY + rect.height / 2 * CGFloat(sin(angle))
            let inset: CGFloat = isMark ? 1.5 : 2.5
            let ridge = NSBezierPath()
            ridge.move(to: NSPoint(x: rect.minX + inset, y: y))
            ridge.line(to: NSPoint(x: rect.maxX - inset, y: y))
            ridge.lineWidth = (isMark ? 2.2 : 1.0) * (0.45 + 0.55 * facing)
            ridge.lineCapStyle = .round
            NSColor.white.withAlphaComponent((isMark ? 1.0 : 0.5) * facing).setStroke()
            ridge.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// A key of the keyboard. Pressed, it sinks and takes the accent colour, as the wheel has it.
final class ScrollPreviewKeyCap: ScrollPreviewArtworkView {

    static let faceSize = NSSize(width: 34, height: 34)
    /// How far the key stands up, and sinks when pressed.
    static let height: CGFloat = 3
    static let margin: CGFloat = 2
    static let size = NSSize(width: faceSize.width + 2 * margin, height: faceSize.height + height + 2 * margin)
    static let cornerRadius: CGFloat = 7

    var glyph = "" {
        didSet { if glyph != oldValue { needsDisplay = true } }
    }

    /// 0: up, 1: pressed.
    var depth: CGFloat = 0 {
        didSet { if depth != oldValue { needsDisplay = true } }
    }

    override func draw(_ dirtyRect: NSRect) {
        let pressed = min(1, max(0, depth))
        let sink = Self.height * pressed
        let face = NSRect(
            x: Self.margin, y: Self.margin + sink,
            width: Self.faceSize.width, height: Self.faceSize.height
        )
        let side = NSRect(
            x: face.minX, y: face.minY,
            width: face.width, height: face.height + Self.height - sink
        )
        let accent = NSColor.controlAccentColor
        let edge = ScrollPreviewPalette.keyEdge.mixed(pressed, with: accent.mixed(0.25, with: .black))

        let sidePath = NSBezierPath(roundedRect: side.insetBy(dx: 0.5, dy: 0.5), xRadius: Self.cornerRadius, yRadius: Self.cornerRadius)
        ScrollPreviewPalette.keySide.mixed(pressed, with: accent.mixed(0.3, with: .black)).setFill()
        sidePath.fill()
        edge.setStroke()
        sidePath.lineWidth = 1
        sidePath.stroke()

        let facePath = NSBezierPath(roundedRect: face.insetBy(dx: 0.5, dy: 0.5), xRadius: Self.cornerRadius, yRadius: Self.cornerRadius)
        ScrollPreviewPalette.keyFace.mixed(pressed, with: accent).setFill()
        facePath.fill()
        edge.setStroke()
        facePath.lineWidth = 1
        facePath.stroke()

        let text = NSAttributedString(string: glyph, attributes: [
            .font: NSFont.systemFont(ofSize: 17, weight: .medium),
            .foregroundColor: ScrollPreviewPalette.keyGlyph.mixed(pressed, with: .white),
        ])
        let size = text.size()
        text.draw(at: NSPoint(x: face.midX - size.width / 2, y: face.midY - size.height / 2))
    }
}

// MARK: - The screen card

/// The right card: a desktop with one window. The page inside the window is a view that
/// is moved behind the window's content area.
final class ScrollPreviewScreenCard: ScrollPreviewArtworkView {

    static let cornerRadius: CGFloat = 10
    static let menuBarHeight: CGFloat = 8
    static let titleBarHeight: CGFloat = 16
    static let windowCornerRadius: CGFloat = 7
    static let thumbThickness: CGFloat = 3
    static let thumbInset: CGFloat = 3

    private let viewport = ScrollPreviewArtworkView()
    private let page = ScrollPreviewPage()
    private let thumb = ScrollPreviewThumb()
    private var offset = CGPoint.zero
    private var atRest = true

    override init() {
        super.init()
        viewport.clipsToBounds = true
        viewport.addSubview(page)
        addSubview(viewport)
        addSubview(thumb)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    /// The window on the desktop.
    private var windowRect: NSRect {
        let side = min(22, (bounds.width * 0.09).rounded())
        let top = Self.menuBarHeight + 9
        return NSRect(x: side, y: top, width: bounds.width - 2 * side, height: bounds.height - top - 12)
    }

    /// The window's content area: what the page is seen through.
    private var viewportRect: NSRect {
        let window = windowRect
        return NSRect(
            x: window.minX + 1, y: window.minY + Self.titleBarHeight,
            width: max(0, window.width - 2), height: max(0, window.height - Self.titleBarHeight - 1)
        )
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutPage()
    }

    /// Another display: whole pixels are somewhere else.
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        place()
    }

    /// The page scrolls sideways (it is wider than the window) or down (it is longer).
    func setSideways(_ sideways: Bool) {
        guard page.sideways != sideways else { return }
        page.sideways = sideways
        layoutPage()
    }

    private func layoutPage() {
        let rect = viewportRect
        viewport.frame = rect
        let travel = CGFloat(ScrollPreviewMotion.travel)
        page.setFrameSize(NSSize(
            width: rect.width + (page.sideways ? travel : 0),
            height: rect.height + (page.sideways ? 0 : travel)
        ))
        needsDisplay = true
        place()
    }

    func show(offset: CGPoint, atRest: Bool) {
        guard offset != self.offset || atRest != self.atRest else { return }
        self.offset = offset
        self.atRest = atRest
        place()
    }

    /// Moves the page and the scroller thumb to the current offset. While the page moves it
    /// may sit between pixels; at rest it sits on whole ones, so it is sharp.
    private func place() {
        let travel = CGFloat(ScrollPreviewMotion.travel)
        let scale = window?.backingScaleFactor ?? 2
        func aligned(_ value: CGFloat) -> CGFloat {
            return atRest ? (value * scale).rounded() / scale : value
        }
        let x = min(travel, max(0, offset.x))
        let y = min(travel, max(0, offset.y))
        let origin = NSPoint(x: page.sideways ? -aligned(x) : 0, y: page.sideways ? 0 : -aligned(y))
        if page.frame.origin != origin {
            page.setFrameOrigin(origin)
        }

        let rect = viewportRect
        let thickness = Self.thumbThickness
        let inset = Self.thumbInset
        var thumbFrame: NSRect
        if page.sideways {
            let track = max(0, rect.width - 2 * inset)
            let length = (track * rect.width / max(1, page.frame.width)).rounded()
            thumbFrame = NSRect(
                x: rect.minX + inset + aligned((track - length) * x / travel),
                y: rect.maxY - inset - thickness, width: length, height: thickness
            )
        } else {
            let track = max(0, rect.height - 2 * inset)
            let length = (track * rect.height / max(1, page.frame.height)).rounded()
            thumbFrame = NSRect(
                x: rect.maxX - inset - thickness,
                y: rect.minY + inset + aligned((track - length) * y / travel), width: thickness, height: length
            )
        }
        if thumb.frame != thumbFrame {
            thumb.frame = thumbFrame
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let card = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            xRadius: Self.cornerRadius, yRadius: Self.cornerRadius
        )

        NSGraphicsContext.saveGraphicsState()
        card.addClip()

        // The desktop, and a hint of the menu bar.
        let desktop = NSGradient(starting: ScrollPreviewPalette.desktopStart, ending: ScrollPreviewPalette.desktopEnd)
        desktop?.draw(in: bounds, angle: -35)
        ScrollPreviewPalette.menuBar.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: Self.menuBarHeight).fill(using: .sourceOver)
        ScrollPreviewPalette.menuItem.setFill()
        var itemX: CGFloat = 10
        for width in [5, 12, 9, 11] as [CGFloat] {
            capsule(NSRect(x: itemX, y: Self.menuBarHeight / 2 - 1, width: width, height: 2)).fill()
            itemX += width + 5
        }
        capsule(NSRect(x: bounds.width - 10 - 14, y: Self.menuBarHeight / 2 - 1, width: 14, height: 2)).fill()

        // The window: shadow, body, title bar.
        let window = windowRect
        let radius = Self.windowCornerRadius
        let frame = NSBezierPath(roundedRect: window, xRadius: radius, yRadius: radius)
        // The shadow falls downwards. It is cast, without an offset, by a shape that is
        // itself moved down and stays hidden behind the window, so it does not depend on
        // which way a context reads a shadow offset.
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = ScrollPreviewPalette.windowShadow
        shadow.shadowBlurRadius = 10
        shadow.shadowOffset = .zero
        shadow.set()
        ScrollPreviewPalette.windowShadow.setFill()
        NSBezierPath(
            roundedRect: window.insetBy(dx: 3, dy: 3).offsetBy(dx: 0, dy: 3),
            xRadius: radius, yRadius: radius
        ).fill()
        NSGraphicsContext.restoreGraphicsState()
        ScrollPreviewPalette.windowBody.setFill()
        frame.fill()

        NSGraphicsContext.saveGraphicsState()
        frame.addClip()
        let titleBar = NSRect(x: window.minX, y: window.minY, width: window.width, height: Self.titleBarHeight)
        ScrollPreviewPalette.windowTitleBar.setFill()
        titleBar.fill()
        ScrollPreviewPalette.windowTitleLine.setFill()
        NSRect(x: window.minX, y: titleBar.maxY - 0.5, width: window.width, height: 0.5).fill(using: .sourceOver)
        for (index, colour) in ScrollPreviewPalette.trafficLights.enumerated() {
            colour.setFill()
            NSBezierPath(ovalIn: NSRect(
                x: window.minX + 7 + CGFloat(index) * 7.5, y: titleBar.midY - 2.5, width: 5, height: 5
            )).fill()
        }
        NSGraphicsContext.restoreGraphicsState()

        let edge = NSBezierPath(roundedRect: window.insetBy(dx: 0.25, dy: 0.25), xRadius: radius, yRadius: radius)
        edge.lineWidth = 0.5
        ScrollPreviewPalette.windowEdge.setStroke()
        edge.stroke()

        NSGraphicsContext.restoreGraphicsState()

        ScrollPreviewPalette.cardEdge.setStroke()
        card.lineWidth = 1
        card.stroke()
    }
}

/// The page in the window: a heading, lines of text, and a circle, a square and a
/// triangle to follow with the eye. Longer than the window, or wider for sideways scrolling.
final class ScrollPreviewPage: ScrollPreviewArtworkView {

    var sideways = false {
        didSet { if sideways != oldValue { needsDisplay = true } }
    }

    private static let padding: CGFloat = 12
    private static let lineHeight: CGFloat = 4
    private static let shapeColours: [NSColor] = [.systemOrange, .systemGreen, .systemPink]

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if changed { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        if sideways {
            drawColumns()
        } else {
            drawArticle()
        }
    }

    private func line(x: CGFloat, y: CGFloat, width: CGFloat, heading: Bool = false) {
        guard width > 0 else { return }
        (heading ? ScrollPreviewPalette.pageHeading : ScrollPreviewPalette.pageLine).setFill()
        capsule(NSRect(x: x, y: y, width: width, height: heading ? 6 : Self.lineHeight)).fill()
    }

    private func shape(_ index: Int, in rect: NSRect) {
        Self.shapeColours[index % Self.shapeColours.count].setFill()
        switch index % 3 {
        case 0:
            NSBezierPath(ovalIn: rect).fill()
        case 1:
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
        default:
            let triangle = NSBezierPath()
            triangle.move(to: NSPoint(x: rect.midX, y: rect.minY + 1))
            triangle.line(to: NSPoint(x: rect.maxX - 1, y: rect.maxY - 1))
            triangle.line(to: NSPoint(x: rect.minX + 1, y: rect.maxY - 1))
            triangle.close()
            triangle.lineJoinStyle = .round
            triangle.lineWidth = 2
            Self.shapeColours[index % Self.shapeColours.count].setStroke()
            triangle.fill()
            triangle.stroke()
        }
    }

    /// Down the page: a heading and two lines, then three times a shape with text beside
    /// it and two lines under it.
    private func drawArticle() {
        let pad = Self.padding
        let width = bounds.width - 2 * pad
        guard width > 0 else { return }
        line(x: pad, y: 11, width: (width * 0.44).rounded(), heading: true)
        line(x: pad, y: 25, width: width)
        line(x: pad, y: 33, width: (width * 0.82).rounded())

        let shapeSide: CGFloat = 26
        let gap: CGFloat = 10
        var y: CGFloat = 46
        for index in 0..<3 {
            let onLeft = index % 2 == 0
            let shapeRect = NSRect(x: onLeft ? pad : pad + width - shapeSide, y: y, width: shapeSide, height: shapeSide)
            shape(index, in: shapeRect)
            let textX = onLeft ? pad + shapeSide + gap : pad
            let textWidth = width - shapeSide - gap
            line(x: textX, y: y + 3, width: textWidth)
            line(x: textX, y: y + 11, width: (textWidth * 0.9).rounded())
            line(x: textX, y: y + 19, width: (textWidth * 0.55).rounded())
            line(x: pad, y: y + 36, width: width)
            line(x: pad, y: y + 44, width: (width * (index == 1 ? 0.7 : 0.88)).rounded())
            y += 56
        }
    }

    /// Across the page: a column of text, then the three shapes side by side, each with
    /// two lines under it. The column is wide enough that the window cuts the second shape
    /// before the page is scrolled: there is more to the right.
    private func drawColumns() {
        let pad = Self.padding
        let height = bounds.height
        let window = bounds.width - CGFloat(ScrollPreviewMotion.travel)
        let textWidth = (window * 0.39).rounded()
        line(x: pad, y: 16, width: (textWidth * 0.6).rounded(), heading: true)
        var y: CGFloat = 31
        for fraction in [1.0, 0.85, 1.0, 0.7, 0.95, 0.85, 0.5] as [CGFloat] where y + Self.lineHeight < height - 16 {
            line(x: pad, y: y, width: (textWidth * fraction).rounded())
            y += 8
        }

        let gap: CGFloat = 14
        let first = pad + textWidth + gap
        let tile = ((bounds.width - pad - first - 2 * gap) / 3).rounded(.down)
        guard tile > 0 else { return }
        let side = min(tile, max(0, height - 55))
        for index in 0..<3 {
            let x = first + CGFloat(index) * (tile + gap)
            shape(index, in: NSRect(x: x + ((tile - side) / 2).rounded(), y: 16, width: side, height: side))
            line(x: x, y: 16 + side + 9, width: tile)
            line(x: x, y: 16 + side + 17, width: (tile * 0.6).rounded())
        }
    }
}

/// The thumb of the window's scroller.
final class ScrollPreviewThumb: ScrollPreviewArtworkView {

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if changed { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        ScrollPreviewPalette.scrollerThumb.setFill()
        capsule(bounds).fill()
    }
}
