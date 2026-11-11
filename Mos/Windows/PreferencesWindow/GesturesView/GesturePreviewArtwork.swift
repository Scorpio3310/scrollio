//
//  GesturePreviewArtwork.swift
//  Mos
//  The drawing of GesturePreviewView: on the left the connected mouse seen from above with
//  its gesture button, on the right a small desktop. Everything is drawn with paths, in the
//  colours of the Scrolling preview (ScrollPreviewPalette), so the two panes look alike in
//  light and in dark.
//
//  The mouse is a view of its own that is moved, and only redrawn when its button changes.
//  The desktop is redrawn when the frame changes; while the demo rests it is not redrawn.
//

import Cocoa

// MARK: - Colours

enum GesturePreviewPalette {

    /// The second desktop: warm, so a slide between the two is easy to follow.
    static let secondDesktopStart = ScrollPreviewPalette.adaptive(
        light: NSColor(srgbRed: 1.00, green: 0.80, blue: 0.58, alpha: 1),
        dark: NSColor(srgbRed: 0.45, green: 0.23, blue: 0.10, alpha: 1)
    )
    static let secondDesktopEnd = ScrollPreviewPalette.adaptive(
        light: NSColor(srgbRed: 0.98, green: 0.58, blue: 0.66, alpha: 1),
        dark: NSColor(srgbRed: 0.42, green: 0.12, blue: 0.27, alpha: 1)
    )
    /// Between two desktops while they slide.
    static let desktopGap = NSColor(white: 0, alpha: 0.85)
    static let dock = ScrollPreviewPalette.adaptive(light: NSColor(white: 1, alpha: 0.45), dark: NSColor(white: 0.1, alpha: 0.45))
    static let dockEdge = ScrollPreviewPalette.adaptive(light: NSColor(white: 1, alpha: 0.6), dark: NSColor(white: 1, alpha: 0.12))
    /// Over the desktop while Mission Control or the app grid shows.
    static let overviewShade = NSColor(white: 0, alpha: 0.28)
    static let gridShade = NSColor(white: 0, alpha: 0.42)
    static let hudFill = ScrollPreviewPalette.adaptive(light: NSColor(white: 0.90, alpha: 0.95), dark: NSColor(white: 0.20, alpha: 0.92))
    static let hudEdge = ScrollPreviewPalette.adaptive(light: NSColor(white: 0, alpha: 0.12), dark: NSColor(white: 1, alpha: 0.12))
    static let hudSymbol = ScrollPreviewPalette.adaptive(light: NSColor(white: 0.15, alpha: 1), dark: NSColor(white: 0.92, alpha: 1))
    /// App icons, the photos in the second desktop's window and the dock.
    static let tiles: [NSColor] = [
        .systemBlue, .systemOrange, .systemGreen, .systemPink, .systemPurple,
        .systemYellow, .systemTeal, .systemRed, .systemIndigo, .systemMint,
        .systemBrown, .systemCyan, .systemGray, .systemGreen, .systemOrange,
    ]
}

private extension NSColor {
    func mixed(_ fraction: CGFloat, with other: NSColor) -> NSColor {
        return blended(withFraction: min(1, max(0, fraction)), of: other) ?? self
    }
}

private func capsule(_ rect: NSRect) -> NSBezierPath {
    let radius = min(rect.width, rect.height) / 2
    return NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
    return a + (b - a) * t
}

private func lerp(_ a: NSRect, _ b: NSRect, _ t: CGFloat) -> NSRect {
    return NSRect(x: lerp(a.minX, b.minX, t), y: lerp(a.minY, b.minY, t), width: lerp(a.width, b.width, t), height: lerp(a.height, b.height, t))
}

/// Base class of the artwork: top-left origin, and nothing here takes a click.
class GesturePreviewArtworkView: NSView {
    override var isFlipped: Bool { return true }

    init() {
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}

// MARK: - The device card

/// The left card: the mouse, moved by the hand, and an arrow ahead of it while it moves.
final class GesturePreviewDeviceCard: GesturePreviewArtworkView {

    static let cornerRadius: CGFloat = 10
    /// Between the mouse's edge and the arrow, and the arrow's length.
    static let arrowGap: CGFloat = 5
    static let arrowLength: CGFloat = 14

    let mouse = GesturePreviewMouse()
    private var offset = CGPoint.zero
    private var arrow = 0.0
    private var direction: MouseGestureDirection?
    private var atRest = true

    override init() {
        super.init()
        addSubview(mouse)
        mouse.setFrameSize(GesturePreviewMouse.size)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        placeMouse()
        needsDisplay = true
    }

    /// Which mouse is drawn; its body stays centred.
    var model: MouseArtworkModel {
        get { return mouse.model }
        set {
            guard newValue != mouse.model else { return }
            mouse.model = newValue
            placeMouse()
            needsDisplay = true
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        placeMouse()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        placeMouse()
    }

    func show(_ frame: GesturePreviewLoop.Frame) {
        mouse.show(buttonDepth: frame.buttonDepth, pressPulse: frame.pressPulse)
        let changed = frame.mouseOffset != offset || frame.arrow != arrow
            || frame.direction != direction || frame.isAtRest != atRest
        guard changed else { return }
        offset = frame.mouseOffset
        arrow = frame.arrow
        direction = frame.direction
        atRest = frame.isAtRest
        placeMouse()
        needsDisplay = true
    }

    /// The body (not the thumb rest) is centred in the card, then moved by the hand. At rest
    /// it sits on whole pixels.
    private func placeMouse() {
        let scale = window?.backingScaleFactor ?? 2
        let body = mouse.bodyRect
        var x = bounds.midX - body.midX + offset.x
        var y = bounds.midY - body.midY + offset.y
        if atRest {
            x = (x * scale).rounded() / scale
            y = (y * scale).rounded() / scale
        }
        let origin = NSPoint(x: x, y: y)
        if mouse.frame.origin != origin {
            mouse.setFrameOrigin(origin)
        }
    }

    /// Where the arrow starts and ends, in the card: just outside the mouse, pointing the
    /// way it moves.
    var arrowSegment: (from: NSPoint, to: NSPoint)? {
        guard let direction else { return nil }
        let outline = mouse.outlineRect.offsetBy(dx: mouse.frame.minX, dy: mouse.frame.minY)
        let gap = Self.arrowGap, length = Self.arrowLength
        switch direction {
        case .left:
            let from = NSPoint(x: outline.minX - gap, y: outline.midY)
            return (from, NSPoint(x: from.x - length, y: from.y))
        case .right:
            let from = NSPoint(x: outline.maxX + gap, y: outline.midY)
            return (from, NSPoint(x: from.x + length, y: from.y))
        case .up:
            let from = NSPoint(x: outline.midX, y: outline.minY - gap)
            return (from, NSPoint(x: from.x, y: from.y - length))
        case .down:
            let from = NSPoint(x: outline.midX, y: outline.maxY + gap)
            return (from, NSPoint(x: from.x, y: from.y + length))
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

        guard arrow > 0.01, let segment = arrowSegment else { return }
        let accent = NSColor.controlAccentColor.withAlphaComponent(CGFloat(min(1, arrow)))
        let line = NSBezierPath()
        line.move(to: segment.from)
        line.line(to: segment.to)
        // The head: two strokes back from the tip.
        let dx = segment.to.x - segment.from.x, dy = segment.to.y - segment.from.y
        let length = max(1, hypot(dx, dy))
        let ux = dx / length, uy = dy / length
        let head: CGFloat = 5
        line.move(to: NSPoint(x: segment.to.x - ux * head - uy * head, y: segment.to.y - uy * head + ux * head))
        line.line(to: segment.to)
        line.line(to: NSPoint(x: segment.to.x - ux * head + uy * head, y: segment.to.y - uy * head - ux * head))
        line.lineWidth = 2.5
        line.lineCapStyle = .round
        line.lineJoinStyle = .round
        accent.setStroke()
        line.stroke()
    }
}

/// The connected mouse seen from above, the drawing of the Mouse and Buttons panes
/// (MouseArtwork.swift) a little smaller, with the button that runs Gesture Navigation where
/// the model has it (MouseArtworkModel.gesturePreviewPart): it takes the accent colour while
/// it is held.
final class GesturePreviewMouse: GesturePreviewArtworkView {

    /// The drawing's grid is drawn this many points per unit: the body 80 points tall.
    static let unit: CGFloat = 80 / MouseArtworkShapes.grid.height
    /// Room around the drawing for its outline, its shadow and the ring of a press.
    static let margin: CGFloat = 10
    static let size = NSSize(
        width: (MouseArtworkShapes.grid.width * unit + 2 * margin).rounded(.up),
        height: MouseArtworkShapes.grid.height * unit + 2 * margin
    )

    /// Which mouse is drawn.
    var model: MouseArtworkModel = .generic {
        didSet {
            if model != oldValue { needsDisplay = true }
        }
    }

    private var shapes: MouseArtworkShapes {
        return MouseArtworkShapes(model: model)
    }

    /// From the drawing's grid to the view: the grid centred across, `margin` from the top.
    static var placement: AffineTransform {
        var transform = AffineTransform(
            translationByX: (size.width - MouseArtworkShapes.grid.width * unit) / 2, byY: margin
        )
        transform.scale(unit)
        return transform
    }

    private func inView(_ rect: NSRect) -> NSRect {
        let path = NSBezierPath(rect: rect)
        path.transform(using: Self.placement)
        return path.bounds
    }

    /// The body without the thumb wing, in the mouse view: centred in the card. Its middle
    /// is on a half point, so the mouse at rest sits where the hand leaves it.
    var bodyRect: NSRect {
        let body = inView(shapes.mainBody)
        let mid = NSPoint(x: (body.midX * 2).rounded() / 2, y: (body.midY * 2).rounded() / 2)
        return NSRect(x: mid.x - body.width / 2, y: mid.y - body.height / 2, width: body.width, height: body.height)
    }

    /// The whole drawing (body, thumb wing, side buttons).
    var outlineRect: NSRect {
        let outline = shapes.outline()
        for part in [MouseArtworkPart.thumbWheel, .gesture, .forward, .back] {
            if let shape = shapes.shape(of: part) { outline.append(shape) }
        }
        return inView(outline.bounds)
    }

    /// The button that runs Gesture Navigation, in the mouse view.
    var buttonRect: NSRect {
        return buttonShape.bounds
    }

    private var buttonShape: NSBezierPath {
        let path = shapes.shape(of: model.gesturePreviewPart) ?? NSBezierPath()
        path.transform(using: Self.placement)
        return path
    }

    private var buttonDepth = 0.0
    private var pressPulse = 0.0

    func show(buttonDepth: Double, pressPulse: Double) {
        guard buttonDepth != self.buttonDepth || pressPulse != self.pressPulse else { return }
        self.buttonDepth = buttonDepth
        self.pressPulse = pressPulse
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        (Self.placement as NSAffineTransform).concat()
        MouseArtworkPainter.draw(shapes, ink: .card, unit: Self.unit)
        NSGraphicsContext.restoreGraphicsState()
        drawButton()
    }

    /// The gesture button: as drawn while up, the accent colour while held, and a ring that
    /// opens up and fades when it goes down.
    private func drawButton() {
        let button = buttonShape
        let accent = NSColor.controlAccentColor
        let depth = CGFloat(min(1, max(0, buttonDepth)))
        let ring = CGFloat(min(1, max(0, pressPulse)))
        if ring > 0 {
            let spread = 1.5 + (1 - ring) * 6
            accent.withAlphaComponent(0.45 * ring).setStroke()
            button.lineWidth = 2 * spread
            button.lineJoinStyle = .round
            button.stroke()
        }
        if depth > 0 {
            // Held: lit with a glow, as the cards light a part.
            NSGraphicsContext.saveGraphicsState()
            let glow = NSShadow()
            glow.shadowColor = accent.withAlphaComponent(0.65 * depth)
            glow.shadowBlurRadius = 6
            glow.shadowOffset = .zero
            glow.set()
            accent.withAlphaComponent(depth).setFill()
            button.fill()
            NSGraphicsContext.restoreGraphicsState()
            accent.mixed(0.3, with: .black).withAlphaComponent(depth).setStroke()
            button.lineWidth = 1
            button.stroke()
            // The MX Master 3's gesture button is in the thumb rest, under the side buttons.
            if model == .mxMaster3 {
                NSGraphicsContext.saveGraphicsState()
                (Self.placement as NSAffineTransform).concat()
                MouseArtworkPainter.drawSideButtons(on: shapes, ink: .card, unit: Self.unit)
                NSGraphicsContext.restoreGraphicsState()
            }
        }
    }
}

// MARK: - The screen card

/// The right card: a row of desktops seen through the screen, a menu bar and a dock that
/// stay put, the overview of Mission Control, the app grid, the pulse of other actions and
/// the pointer.
final class GesturePreviewScreenCard: GesturePreviewArtworkView {

    static let cornerRadius: CGFloat = 10
    static let menuBarHeight: CGFloat = 8
    static let titleBarHeight: CGFloat = 13
    static let windowCornerRadius: CGFloat = 6
    /// Between two desktops while they slide.
    static let desktopGap: CGFloat = 4
    static let dockHeight: CGFloat = 12
    static let dockIconSize: CGFloat = 8
    static let dockIconCount = 7
    /// How much smaller the windows get in the overview.
    static let overviewScale: CGFloat = 0.6
    static let pointerSize = NSSize(width: 11, height: 17)

    private(set) var shown: GesturePreviewLoop.Frame?

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if changed { needsDisplay = true }
    }

    func show(_ frame: GesturePreviewLoop.Frame) {
        guard frame != shown else { return }
        // A rest frame that only differs in what the mouse does need not redraw the desktop.
        if let shown, Self.looksTheSame(shown, frame) {
            self.shown = frame
            return
        }
        shown = frame
        needsDisplay = true
    }

    /// Two frames that draw the same desktop.
    static func looksTheSame(_ a: GesturePreviewLoop.Frame, _ b: GesturePreviewLoop.Frame) -> Bool {
        return a.desktop == b.desktop && a.overview == b.overview && a.appGrid == b.appGrid
            && a.pulse == b.pulse && a.pulseSymbol == b.pulseSymbol && a.pointerOffset == b.pointerOffset
            && a.isAtRest == b.isAtRest
    }

    // MARK: Layout

    /// The windows of a desktop: two on the first (one in front of the other), one on the
    /// second. Back to front.
    enum WindowKind: CaseIterable { case notes, article, photos }

    static func windows(onDesktop index: Int) -> [WindowKind] {
        return index % 2 == 0 ? [.notes, .article] : [.photos]
    }

    /// Where a window is on a desktop `size` large.
    static func windowRect(_ kind: WindowKind, in size: NSSize) -> NSRect {
        let w = size.width
        switch kind {
        case .article:
            return NSRect(x: (w * 0.08).rounded(), y: 18, width: (w * 0.56).rounded(), height: 94)
        case .notes:
            return NSRect(x: (w * 0.50).rounded(), y: 30, width: (w * 0.42).rounded(), height: 72)
        case .photos:
            return NSRect(x: (w * 0.15).rounded(), y: 19, width: (w * 0.70).rounded(), height: 96)
        }
    }

    /// Where a window is in Mission Control: smaller, side by side under the Spaces bar.
    static func overviewRect(_ kind: WindowKind, onDesktop index: Int, in size: NSSize) -> NSRect {
        let kinds = windows(onDesktop: index)
        let scale = overviewScale
        let gap: CGFloat = 10
        // Left to right in the overview: front window first.
        let order = Array(kinds.reversed())
        let sizes = order.map { kind -> NSSize in
            let rect = windowRect(kind, in: size)
            return NSSize(width: rect.width * scale, height: rect.height * scale)
        }
        let total = sizes.reduce(0) { $0 + $1.width } + gap * CGFloat(max(0, sizes.count - 1))
        var x = (size.width - total) / 2
        let top: CGFloat = 40, bottom = size.height - dockHeight - 10
        for (index, candidate) in order.enumerated() {
            let itemSize = sizes[index]
            if candidate == kind {
                return NSRect(x: x, y: top + (bottom - top - itemSize.height) / 2, width: itemSize.width, height: itemSize.height)
            }
            x += itemSize.width + gap
        }
        return windowRect(kind, in: size)
    }

    /// The pointer's tip when the hand has not moved it.
    var pointerHome: NSPoint {
        return NSPoint(x: (bounds.width * 0.72).rounded(), y: 64)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let frame = shown
        let card = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            xRadius: Self.cornerRadius, yRadius: Self.cornerRadius
        )
        NSGraphicsContext.saveGraphicsState()
        card.addClip()

        GesturePreviewPalette.desktopGap.setFill()
        bounds.fill()

        // The desktops in view: the one on screen and, while they slide, its neighbour.
        let position = frame?.desktop ?? 0
        let first = Int(position.rounded(.down))
        let fraction = CGFloat(position - Double(first))
        let pitch = bounds.width + Self.desktopGap
        let current = Int(position.rounded()) % 2
        for index in [first, first + 1] {
            let x = (CGFloat(index - first) - fraction) * pitch
            guard x < bounds.width, x + bounds.width > 0 else { continue }
            let overview = index % 2 == current ? CGFloat(frame?.overview ?? 0) : 0
            let grid = index % 2 == current ? CGFloat(frame?.appGrid ?? 0) : 0
            drawDesktop(index % 2, at: x, overview: overview, gridFade: grid)
        }

        drawMenuBar()
        if let frame, frame.appGrid > 0 {
            drawAppGrid(CGFloat(frame.appGrid))
        }
        // The dock stays on top of the app grid, as it does on a Mac.
        drawDock()
        if let frame, frame.overview > 0 {
            drawSpacesBar(progress: CGFloat(frame.overview), current: current)
        }
        if let frame, frame.pulse > 0, let symbol = frame.pulseSymbol {
            drawPulse(CGFloat(frame.pulse), symbol: symbol)
        }
        drawPointer(offset: frame?.pointerOffset ?? .zero, atRest: frame?.isAtRest ?? true)

        NSGraphicsContext.restoreGraphicsState()
        ScrollPreviewPalette.cardEdge.setStroke()
        card.lineWidth = 1
        card.stroke()
    }

    private func drawDesktop(_ index: Int, at x: CGFloat, overview: CGFloat, gridFade: CGFloat) {
        let rect = NSRect(x: x, y: 0, width: bounds.width, height: bounds.height)
        let start = index == 0 ? ScrollPreviewPalette.desktopStart : GesturePreviewPalette.secondDesktopStart
        let end = index == 0 ? ScrollPreviewPalette.desktopEnd : GesturePreviewPalette.secondDesktopEnd
        NSGradient(starting: start, ending: end)?.draw(in: rect, angle: index == 0 ? -35 : 35)
        if overview > 0 {
            GesturePreviewPalette.overviewShade.withAlphaComponent(0.28 * overview).setFill()
            rect.fill(using: .sourceOver)
        }

        let alpha = 1 - gridFade
        guard alpha > 0.01 else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(alpha)
        NSGraphicsContext.current?.cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
        for kind in Self.windows(onDesktop: index) {
            let home = Self.windowRect(kind, in: bounds.size)
            let target = Self.overviewRect(kind, onDesktop: index, in: bounds.size)
            let place = lerp(home, target, overview).offsetBy(dx: x, dy: 0)
            drawWindow(kind, in: place, natural: home.size)
        }
        NSGraphicsContext.current?.cgContext.endTransparencyLayer()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// A window drawn at its natural size and scaled into `place`.
    private func drawWindow(_ kind: WindowKind, in place: NSRect, natural: NSSize) {
        let scale = place.width / max(1, natural.width)
        let radius = Self.windowCornerRadius
        let frame = NSRect(origin: .zero, size: natural)

        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: place.minX, yBy: place.minY)
        transform.scaleX(by: scale, yBy: scale)
        transform.concat()

        // The shadow falls downwards, cast by a shape hidden behind the window.
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = ScrollPreviewPalette.windowShadow
        shadow.shadowBlurRadius = 7
        shadow.shadowOffset = .zero
        shadow.set()
        ScrollPreviewPalette.windowShadow.setFill()
        NSBezierPath(roundedRect: frame.insetBy(dx: 3, dy: 3).offsetBy(dx: 0, dy: 2.5), xRadius: radius, yRadius: radius).fill()
        NSGraphicsContext.restoreGraphicsState()

        let outline = NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)
        ScrollPreviewPalette.windowBody.setFill()
        outline.fill()

        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        let titleBar = NSRect(x: 0, y: 0, width: frame.width, height: Self.titleBarHeight)
        ScrollPreviewPalette.windowTitleBar.setFill()
        titleBar.fill()
        ScrollPreviewPalette.windowTitleLine.setFill()
        NSRect(x: 0, y: titleBar.maxY - 0.5, width: frame.width, height: 0.5).fill(using: .sourceOver)
        for (index, colour) in ScrollPreviewPalette.trafficLights.enumerated() {
            colour.setFill()
            NSBezierPath(ovalIn: NSRect(x: 6 + CGFloat(index) * 6.5, y: titleBar.midY - 2, width: 4, height: 4)).fill()
        }
        drawContent(of: kind, in: NSRect(x: 0, y: titleBar.maxY, width: frame.width, height: frame.height - titleBar.maxY))
        NSGraphicsContext.restoreGraphicsState()

        let edge = NSBezierPath(roundedRect: frame.insetBy(dx: 0.25, dy: 0.25), xRadius: radius, yRadius: radius)
        edge.lineWidth = 0.5
        ScrollPreviewPalette.windowEdge.setStroke()
        edge.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func line(x: CGFloat, y: CGFloat, width: CGFloat, heading: Bool = false) {
        guard width > 0 else { return }
        (heading ? ScrollPreviewPalette.pageHeading : ScrollPreviewPalette.pageLine).setFill()
        capsule(NSRect(x: x, y: y, width: width, height: heading ? 5 : 3)).fill()
    }

    private func drawContent(of kind: WindowKind, in rect: NSRect) {
        let pad: CGFloat = 9
        let width = rect.width - 2 * pad
        switch kind {
        case .article:
            line(x: pad, y: rect.minY + 9, width: (width * 0.5).rounded(), heading: true)
            line(x: pad, y: rect.minY + 20, width: width)
            line(x: pad, y: rect.minY + 27, width: (width * 0.8).rounded())
            let side: CGFloat = 20
            let shape = NSRect(x: pad, y: rect.minY + 38, width: side, height: side)
            NSColor.systemOrange.setFill()
            NSBezierPath(ovalIn: shape).fill()
            let textX = shape.maxX + 8
            line(x: textX, y: shape.minY + 3, width: width - side - 8)
            line(x: textX, y: shape.minY + 10, width: ((width - side - 8) * 0.85).rounded())
            line(x: textX, y: shape.minY + 17, width: ((width - side - 8) * 0.5).rounded())
            line(x: pad, y: shape.maxY + 9, width: width)
        case .notes:
            NSColor.systemYellow.withAlphaComponent(0.85).setFill()
            NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: 3).fill()
            line(x: pad, y: rect.minY + 10, width: (width * 0.6).rounded(), heading: true)
            var y = rect.minY + 21
            for fraction in [1.0, 0.75, 0.9, 0.55, 0.8] as [CGFloat] where y + 3 < rect.maxY - 4 {
                line(x: pad, y: y, width: (width * fraction).rounded())
                y += 8
            }
        case .photos:
            let columns = 3, rows = 2
            let gap: CGFloat = 5
            let tile = min(
                (width - gap * CGFloat(columns - 1)) / CGFloat(columns),
                (rect.height - 2 * pad - gap * CGFloat(rows - 1)) / CGFloat(rows)
            )
            let gridWidth = tile * CGFloat(columns) + gap * CGFloat(columns - 1)
            let left = rect.minX + (rect.width - gridWidth) / 2
            for row in 0..<rows {
                for column in 0..<columns {
                    let colour = GesturePreviewPalette.tiles[(row * columns + column + 3) % GesturePreviewPalette.tiles.count]
                    colour.withAlphaComponent(0.85).setFill()
                    NSBezierPath(
                        roundedRect: NSRect(x: left + CGFloat(column) * (tile + gap), y: rect.minY + pad + CGFloat(row) * (tile + gap), width: tile, height: tile),
                        xRadius: 2.5, yRadius: 2.5
                    ).fill()
                }
            }
        }
    }

    private func drawMenuBar() {
        ScrollPreviewPalette.menuBar.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: Self.menuBarHeight).fill(using: .sourceOver)
        ScrollPreviewPalette.menuItem.setFill()
        var itemX: CGFloat = 10
        for width in [5, 12, 9, 11] as [CGFloat] {
            capsule(NSRect(x: itemX, y: Self.menuBarHeight / 2 - 1, width: width, height: 2)).fill()
            itemX += width + 5
        }
        capsule(NSRect(x: bounds.width - 10 - 14, y: Self.menuBarHeight / 2 - 1, width: 14, height: 2)).fill()
    }

    private var dockRect: NSRect {
        let count = CGFloat(Self.dockIconCount)
        let width = count * Self.dockIconSize + (count - 1) * 3 + 8
        return NSRect(x: ((bounds.width - width) / 2).rounded(), y: bounds.height - 4 - Self.dockHeight, width: width, height: Self.dockHeight)
    }

    private func drawDock() {
        let dock = dockRect
        let shape = NSBezierPath(roundedRect: dock, xRadius: 4, yRadius: 4)
        GesturePreviewPalette.dock.setFill()
        shape.fill()
        GesturePreviewPalette.dockEdge.setStroke()
        shape.lineWidth = 0.5
        shape.stroke()
        for index in 0..<Self.dockIconCount {
            GesturePreviewPalette.tiles[index].setFill()
            NSBezierPath(
                roundedRect: NSRect(x: dock.minX + 4 + CGFloat(index) * (Self.dockIconSize + 3), y: dock.midY - Self.dockIconSize / 2, width: Self.dockIconSize, height: Self.dockIconSize),
                xRadius: 2, yRadius: 2
            ).fill()
        }
    }

    /// Mission Control's row of Spaces, coming down from the top: the one on screen framed.
    private func drawSpacesBar(progress: CGFloat, current: Int) {
        let size = NSSize(width: 34, height: 21)
        let gap: CGFloat = 8
        let total = 2 * size.width + gap
        let y = Self.menuBarHeight + 5 - (1 - progress) * 30
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(progress)
        for index in 0..<2 {
            let rect = NSRect(x: ((bounds.width - total) / 2).rounded() + CGFloat(index) * (size.width + gap), y: y, width: size.width, height: size.height)
            let start = index == 0 ? ScrollPreviewPalette.desktopStart : GesturePreviewPalette.secondDesktopStart
            let end = index == 0 ? ScrollPreviewPalette.desktopEnd : GesturePreviewPalette.secondDesktopEnd
            let thumb = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
            NSGradient(starting: start, ending: end)?.draw(in: thumb, angle: index == 0 ? -35 : 35)
            if index == current {
                NSColor.white.setStroke()
                let frame = NSBezierPath(roundedRect: rect.insetBy(dx: -1.5, dy: -1.5), xRadius: 4, yRadius: 4)
                frame.lineWidth = 1.5
                frame.stroke()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Launchpad: the desktop darkens and the windows give way to rows of app icons.
    private func drawAppGrid(_ progress: CGFloat) {
        GesturePreviewPalette.gridShade.withAlphaComponent(0.42 * progress).setFill()
        bounds.fill(using: .sourceOver)

        let columns = 5, rows = 3
        let icon: CGFloat = 16
        let spacingX: CGFloat = min(16, (bounds.width - 40 - CGFloat(columns) * icon) / CGFloat(columns - 1))
        let spacingY: CGFloat = 11
        let gridWidth = CGFloat(columns) * icon + CGFloat(columns - 1) * spacingX
        let gridHeight = CGFloat(rows) * icon + CGFloat(rows - 1) * spacingY
        let centre = NSPoint(x: bounds.midX, y: (bounds.height - Self.dockHeight) / 2 + 2)
        // The icons settle in from a little larger, as Launchpad's do.
        let zoom = 1 + 0.12 * (1 - progress)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(progress)
        for row in 0..<rows {
            for column in 0..<columns {
                let x = centre.x - gridWidth / 2 + CGFloat(column) * (icon + spacingX) + icon / 2
                let y = centre.y - gridHeight / 2 + CGFloat(row) * (icon + spacingY) + icon / 2
                let dx = (x - centre.x) * zoom, dy = (y - centre.y) * zoom
                let side = icon * zoom
                let rect = NSRect(x: centre.x + dx - side / 2, y: centre.y + dy - side / 2, width: side, height: side)
                GesturePreviewPalette.tiles[(row * columns + column) % GesturePreviewPalette.tiles.count].setFill()
                NSBezierPath(roundedRect: rect, xRadius: side * 0.24, yRadius: side * 0.24).fill()
                NSColor.white.withAlphaComponent(0.55).setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: side * 0.32, dy: side * 0.32)).fill()
            }
        }
        // Two page dots under the grid.
        let dotsY = centre.y + gridHeight / 2 + 9
        for index in 0..<2 {
            NSColor.white.withAlphaComponent(index == 0 ? 0.9 : 0.4).setFill()
            NSBezierPath(ovalIn: NSRect(x: bounds.midX - 6 + CGFloat(index) * 8, y: dotsY, width: 4, height: 4)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Any other action: its icon in a small rounded panel that pops up and fades.
    private func drawPulse(_ progress: CGFloat, symbol: String) {
        let side = 44 * (0.86 + 0.14 * progress)
        let centre = NSPoint(x: bounds.midX, y: (bounds.height + Self.menuBarHeight - Self.dockHeight) / 2)
        let rect = NSRect(x: centre.x - side / 2, y: centre.y - side / 2, width: side, height: side)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(progress)
        let panel = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.3)
        shadow.shadowBlurRadius = 6
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
        GesturePreviewPalette.hudFill.setFill()
        panel.fill()
        NSGraphicsContext.restoreGraphicsState()
        GesturePreviewPalette.hudEdge.setStroke()
        panel.lineWidth = 0.5
        panel.stroke()
        if let image = Self.symbolImage(symbol, pointSize: 19 * side / 44) {
            let size = image.size
            image.draw(
                in: NSRect(x: centre.x - size.width / 2, y: centre.y - size.height / 2, width: size.width, height: size.height),
                from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil
            )
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    static func symbolImage(_ name: String, pointSize: CGFloat) -> NSImage? {
        let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: GesturePreviewEffect.fallbackSymbol, accessibilityDescription: nil)
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [GesturePreviewPalette.hudSymbol]))
        return base?.withSymbolConfiguration(configuration)
    }

    /// The arrow pointer, black with a white edge. Frozen it stays where it is.
    private func drawPointer(offset: CGPoint, atRest: Bool) {
        let scale = window?.backingScaleFactor ?? 2
        var tip = NSPoint(x: pointerHome.x + offset.x, y: pointerHome.y + offset.y)
        if atRest {
            tip = NSPoint(x: (tip.x * scale).rounded() / scale, y: (tip.y * scale).rounded() / scale)
        }
        let points: [(CGFloat, CGFloat)] = [(0, 0), (0, 14.5), (3.6, 11.2), (6.2, 16.6), (8.6, 15.6), (6.1, 10.4), (10.6, 10.4)]
        let arrow = NSBezierPath()
        for (index, point) in points.enumerated() {
            let p = NSPoint(x: tip.x + point.0, y: tip.y + point.1)
            if index == 0 { arrow.move(to: p) } else { arrow.line(to: p) }
        }
        arrow.close()
        arrow.lineJoinStyle = .round
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.35)
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
        NSColor.white.setStroke()
        arrow.lineWidth = 2
        arrow.stroke()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.black.setFill()
        arrow.fill()
    }
}
