//
//  GesturePreviewArtwork.swift
//  Mos
//  The drawing of GesturePreviewView: on the left the connected mouse seen from above with
//  the button that really runs the gestures (`TriggerPicture`), on the right a small
//  desktop. Everything is drawn with paths, in the colours of the Scrolling preview
//  (ScrollPreviewPalette), so the two panes look alike in light and in dark.
//
//  The mouse is a view of its own that is moved, and only redrawn when its button changes;
//  the arrow ahead of it is a small view of its own too, so the device card is never
//  redrawn by a frame. The desktop is redrawn when the frame changes; while the demo rests
//  it is not redrawn.
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
    /// Over the desktop while Launchpad's grid shows. (Mission Control leaves the
    /// wallpaper as it is.)
    static let gridShade = NSColor(white: 0, alpha: 0.42)
    /// Mission Control's Spaces bar, the strip that takes the menu bar's place, and the
    /// names of the Spaces on it: the one on screen, and the other.
    static let spacesBar = ScrollPreviewPalette.adaptive(light: NSColor(white: 1, alpha: 0.62), dark: NSColor(white: 0, alpha: 0.45))
    static let spacesBarEdge = ScrollPreviewPalette.adaptive(light: NSColor(white: 0, alpha: 0.10), dark: NSColor(white: 1, alpha: 0.10))
    static let spaceName = ScrollPreviewPalette.adaptive(light: NSColor(white: 0, alpha: 0.70), dark: NSColor(white: 1, alpha: 0.90))
    static let otherSpaceName = ScrollPreviewPalette.adaptive(light: NSColor(white: 0, alpha: 0.30), dark: NSColor(white: 1, alpha: 0.40))
    static let hudFill = ScrollPreviewPalette.adaptive(light: NSColor(white: 0.90, alpha: 0.95), dark: NSColor(white: 0.20, alpha: 0.92))
    static let hudEdge = ScrollPreviewPalette.adaptive(light: NSColor(white: 0, alpha: 0.12), dark: NSColor(white: 1, alpha: 0.12))
    static let hudSymbol = ScrollPreviewPalette.adaptive(light: NSColor(white: 0.15, alpha: 1), dark: NSColor(white: 0.92, alpha: 1))
    /// What lies on the desktop and shows when the windows are out of the way (Show
    /// Desktop): folders, a document, and the names under them.
    static let desktopFolder = ScrollPreviewPalette.adaptive(
        light: NSColor(srgbRed: 0.25, green: 0.62, blue: 0.98, alpha: 1),
        dark: NSColor(srgbRed: 0.22, green: 0.55, blue: 0.92, alpha: 1)
    )
    static let desktopFolderTab = ScrollPreviewPalette.adaptive(
        light: NSColor(srgbRed: 0.16, green: 0.50, blue: 0.90, alpha: 1),
        dark: NSColor(srgbRed: 0.15, green: 0.42, blue: 0.78, alpha: 1)
    )
    static let desktopDocument = ScrollPreviewPalette.adaptive(light: .white, dark: NSColor(white: 0.86, alpha: 1))
    static let desktopDocumentLine = NSColor(white: 0, alpha: 0.28)
    static let desktopItemName = ScrollPreviewPalette.adaptive(light: NSColor(white: 1, alpha: 0.9), dark: NSColor(white: 1, alpha: 0.7))
    /// Apps (macOS 26 and later): its panel, the search field at the panel's top and what
    /// stands in the field.
    static let appsPanel = ScrollPreviewPalette.adaptive(light: NSColor(white: 0.97, alpha: 0.95), dark: NSColor(white: 0.17, alpha: 0.95))
    static let appsPanelEdge = ScrollPreviewPalette.adaptive(light: NSColor(white: 1, alpha: 0.75), dark: NSColor(white: 1, alpha: 0.18))
    static let appsSearchField = ScrollPreviewPalette.adaptive(light: NSColor(white: 0, alpha: 0.07), dark: NSColor(white: 1, alpha: 0.10))
    static let appsSearchText = ScrollPreviewPalette.adaptive(light: NSColor(white: 0, alpha: 0.34), dark: NSColor(white: 1, alpha: 0.40))
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

/// Base class of the artwork: top-left origin, and nothing here takes a click. A frame of
/// the demo redraws only the pieces that change: every piece has a layer of its own (also
/// one that starts hidden, which otherwise draws into its parent's), and draws inside its
/// bounds and clips to them (a view that does not, the default since macOS 14, is drawn
/// again each time it moves, and the pieces move on every frame).
class GesturePreviewArtworkView: NSView {
    override var isFlipped: Bool { return true }

    init() {
        super.init(frame: .zero)
        drawOnlyWhatChanges()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        drawOnlyWhatChanges()
    }

    private func drawOnlyWhatChanges() {
        wantsLayer = true
        clipsToBounds = true
    }
}

// MARK: - The device card

/// The left card: the mouse, moved by the hand, and an arrow ahead of it while it moves.
/// The card itself only draws its background: the mouse and the arrow are views of their
/// own, so a frame of the demo moves the mouse and redraws the arrow's small rectangle,
/// never the whole card. With the trigger (`picture`) come the caps of the modifiers held
/// with the button (lower left; they sink with it) and the icon of the app whose own
/// button it is (top left): small views of their own, set only when the trigger changes.
final class GesturePreviewDeviceCard: GesturePreviewArtworkView {

    static let cornerRadius: CGFloat = 10
    /// Between the mouse's edge and the arrow, and the arrow's length.
    static let arrowGap: CGFloat = 5
    static let arrowLength: CGFloat = 14
    /// The modifiers' caps: their faces' height, how far in from the lower-left corner,
    /// and between two.
    static let capHeight: CGFloat = 20
    static let capInset: CGFloat = 10
    static let capSpacing: CGFloat = 4
    /// The app chip, in from the top-left corner.
    static let chipInset: CGFloat = 8

    let mouse = GesturePreviewMouse()
    /// The arrow, under the mouse as the card's own drawing would be.
    let arrowView = GesturePreviewArrow()
    /// The modifiers held with the button, in order.
    private(set) var caps: [TriggerKeyCap] = []
    let chip = TriggerAppChip()
    private var offset = CGPoint.zero
    private var arrow = 0.0
    private var direction: MouseGestureDirection?
    private var atRest = true
    private var buttonDepth = 0.0

    override init() {
        super.init()
        arrowView.isHidden = true
        // The default picture until a trigger is set.
        arrowView.colour = .secondaryLabelColor
        chip.setFrameOrigin(NSPoint(x: Self.chipInset, y: Self.chipInset))
        addSubview(chip)
        addSubview(arrowView)
        addSubview(mouse)
        mouse.setFrameSize(GesturePreviewMouse.size)
    }

    /// The trigger the mouse holds. A change redraws the mouse and the small views; the
    /// demo goes on where it is.
    var picture = TriggerPicture.none {
        didSet {
            guard picture != oldValue else { return }
            mouse.hold = picture.hold
            // The accent means "yours": the default picture has none, its arrow neither.
            arrowView.colour = picture.hold == nil ? .secondaryLabelColor : .controlAccentColor
            chip.path = picture.appPath
            if picture.modifiers != oldValue.modifiers {
                setCaps(picture.modifiers)
            }
            placeMouse()
        }
    }

    /// One cap per modifier, in a row from the lower-left corner, under the mouse.
    private func setCaps(_ labels: [String]) {
        caps.forEach { $0.removeFromSuperview() }
        caps = labels.map { TriggerKeyCap(label: $0, faceHeight: Self.capHeight) }
        for cap in caps {
            cap.depth = CGFloat(min(1, max(0, buttonDepth)))
            addSubview(cap, positioned: .below, relativeTo: arrowView)
        }
        placeCaps()
    }

    /// The faces' left edge and their sides' bottom `capInset` in from the corner.
    private func placeCaps() {
        var x = Self.capInset - TriggerKeyCap.margin
        for cap in caps {
            let size = cap.frame.size
            cap.setFrameOrigin(NSPoint(x: x, y: bounds.height - Self.capInset - (size.height - TriggerKeyCap.margin)))
            x += size.width - 2 * TriggerKeyCap.margin + Self.capSpacing
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        placeMouse()
        placeCaps()
        needsDisplay = true
    }

    /// Which mouse is drawn; its body stays centred. (The picture is resolved for it by
    /// the preview, `GesturePreviewView.reloadMouse`.)
    var model: MouseArtworkModel {
        get { return mouse.model }
        set {
            guard newValue != mouse.model else { return }
            mouse.model = newValue
            placeMouse()
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
        mouse.show(buttonDepth: frame.buttonDepth, pressPulse: frame.pressPulse, turn: frame.sideTurn)
        buttonDepth = frame.buttonDepth
        // (A cap redraws only while its depth changes.)
        for cap in caps {
            cap.depth = CGFloat(min(1, max(0, frame.buttonDepth)))
        }
        let changed = frame.mouseOffset != offset || frame.arrow != arrow
            || frame.direction != direction || frame.isAtRest != atRest
        guard changed else { return }
        offset = frame.mouseOffset
        arrow = frame.arrow
        direction = frame.direction
        atRest = frame.isAtRest
        placeMouse()
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
        placeArrow()
    }

    /// Puts the arrow ahead of the mouse, as strong as the frame says; hidden while there
    /// is none.
    private func placeArrow() {
        guard arrow > 0.01, let segment = arrowSegment else {
            if !arrowView.isHidden { arrowView.isHidden = true }
            return
        }
        arrowView.show(from: segment.from, to: segment.to, strength: arrow)
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
    }
}

/// The arrow ahead of the moving mouse, in the accent colour: a view only as large as the
/// arrow, so drawing it never redraws the card. Its frame is on whole points, so the arrow
/// falls on the same pixels as when the card drew it.
final class GesturePreviewArrow: GesturePreviewArtworkView {

    static let lineWidth: CGFloat = 2.5
    /// How far the two strokes of the head reach back from the tip, and to each side.
    static let headLength: CGFloat = 5

    /// The arrow in this view, and how strongly it shows (0…1).
    private var from = NSPoint.zero
    private var to = NSPoint.zero
    private var strength = 0.0

    /// Shows the arrow from `from` to `to`, given in the card, at `strength`.
    func show(from: NSPoint, to: NSPoint, strength: Double) {
        let room = Self.lineWidth / 2 + 1
        let frame = Self.path(from: from, to: to).bounds.insetBy(dx: -room, dy: -room).integral
        if self.frame != frame {
            self.frame = frame
        }
        let localFrom = NSPoint(x: from.x - frame.minX, y: from.y - frame.minY)
        let localTo = NSPoint(x: to.x - frame.minX, y: to.y - frame.minY)
        if localFrom != self.from || localTo != self.to || strength != self.strength {
            self.from = localFrom
            self.to = localTo
            self.strength = strength
            needsDisplay = true
        }
        if isHidden {
            isHidden = false
        }
    }

    /// The shaft, and the head: two strokes back from the tip.
    static func path(from: NSPoint, to: NSPoint) -> NSBezierPath {
        let line = NSBezierPath()
        line.move(to: from)
        line.line(to: to)
        let dx = to.x - from.x, dy = to.y - from.y
        let length = max(1, hypot(dx, dy))
        let ux = dx / length, uy = dy / length
        let head = headLength
        line.move(to: NSPoint(x: to.x - ux * head - uy * head, y: to.y - uy * head + ux * head))
        line.line(to: to)
        line.line(to: NSPoint(x: to.x - ux * head + uy * head, y: to.y - uy * head - ux * head))
        return line
    }

    /// The accent colour while a trigger is set; label grey for the default picture, which
    /// has no accent anywhere.
    var colour: NSColor = .controlAccentColor {
        didSet { if colour != oldValue { needsDisplay = true } }
    }

    override func draw(_ dirtyRect: NSRect) {
        let line = Self.path(from: from, to: to)
        line.lineWidth = Self.lineWidth
        line.lineCapStyle = .round
        line.lineJoinStyle = .round
        // Faded as a whole: the grey keeps its own transparency.
        NSGraphicsContext.current?.cgContext.setAlpha(CGFloat(min(1, strength)))
        colour.setStroke()
        line.stroke()
    }
}

/// The connected mouse seen from above, the drawing of the Mouse and Buttons panes
/// (MouseArtwork.swift) a little smaller, holding the trigger that really runs Gesture
/// Navigation (`TriggerPicture`): a part the drawing has is lit as the Buttons card lights
/// it while it is held, with a ring when it goes down; a button the drawing cannot show is
/// an accent badge at the body's right edge, pressed in; with no trigger, a dashed outline
/// in label grey where "Set Up…" usually ends (the gesture button, else Back), never lit.
/// A mouse whose part is on its thumb side (the MX Master 4's buttons and thumb panel, the
/// side buttons of the others) turns to the view from that side for the hold, in the place
/// of its body.
final class GesturePreviewMouse: GesturePreviewArtworkView {

    /// The drawing's grid is drawn this many points per unit: the body 80 points tall.
    static let unit: CGFloat = 80 / MouseArtworkShapes.grid.height
    /// Room around the drawing for its outline, its shadow and the ring of a press.
    static let margin: CGFloat = 10
    /// The grid with its margins, and `sideRoom` more on each side for a view from the side,
    /// which lies across and is drawn in the place of the body (right of the grid's middle
    /// by half the width of the thumb wing).
    static let size = NSSize(
        width: (MouseArtworkShapes.grid.width * unit + 2 * margin).rounded(.up) + 2 * sideRoom,
        height: MouseArtworkShapes.grid.height * unit + 2 * margin
    )
    /// Whole points, so the grid falls where it does without them.
    static let sideRoom: CGFloat = 19
    /// The badge of a button the drawing cannot show, and how small it gets pressed.
    static let badgeHeight: CGFloat = 16
    static let pressedBadgeScale: CGFloat = 0.92

    /// Which mouse is drawn.
    var model: MouseArtworkModel = .generic {
        didSet {
            if model != oldValue { needsDisplay = true }
        }
    }

    /// What is held (`TriggerPicture.hold`); nil: the default picture.
    var hold: TriggerPicture.Hold? {
        didSet {
            if hold != oldValue { needsDisplay = true }
        }
    }

    /// The part of the drawing the hold is about: the lit part, or for the default picture
    /// the placeholder's (the gesture button, else Back); nil for a badge.
    var heldPart: MouseArtworkPart? {
        switch hold {
        case .part(let part)?: return part.artworkPart
        case nil: return model.gesturePreviewPart
        case .number?, .notDrawn?, .keys?: return nil
        }
    }

    /// The hold is a badge (`.number`, `.notDrawn`).
    var showsBadge: Bool {
        switch hold {
        case .number?, .notDrawn?: return true
        case .part?, .keys?, nil: return false
        }
    }

    /// The view the part held shows in; from above for a badge, which never turns.
    var buttonViewpoint: MouseArtworkViewpoint {
        return model.viewpoint(lighting: heldPart)
    }

    /// The view that shows (the one the drawing has turned more than half-way to).
    var viewpoint: MouseArtworkViewpoint {
        return turn >= 0.5 && model.hasSideView ? buttonViewpoint : .above
    }

    private func shapes(_ viewpoint: MouseArtworkViewpoint) -> MouseArtworkShapes {
        return MouseArtworkShapes(model: model, viewpoint: viewpoint)
    }

    /// From the drawing's grid to the view: the grid centred across, `margin` from the top.
    static var placement: AffineTransform {
        var transform = AffineTransform(
            translationByX: (size.width - MouseArtworkShapes.grid.width * unit) / 2, byY: margin
        )
        transform.scale(unit)
        return transform
    }

    /// The same for one view of the drawing: the view from above as it is; a view from the
    /// side moved so that its middle is where the body's is from above, which the card
    /// centres, so the drawing turns in place.
    func placement(for viewpoint: MouseArtworkViewpoint) -> AffineTransform {
        var transform = Self.placement
        guard viewpoint != .above else { return transform }
        let body = shapes(.above).mainBody, side = shapes(viewpoint).mainBody
        transform.translate(x: body.midX - side.midX, y: body.midY - side.midY)
        return transform
    }

    private func inView(_ rect: NSRect, _ viewpoint: MouseArtworkViewpoint = .above) -> NSRect {
        let path = NSBezierPath(rect: rect)
        path.transform(using: placement(for: viewpoint))
        return path.bounds
    }

    /// The body without the thumb wing as seen from above, in the mouse view: centred in
    /// the card. Its middle is on a half point, so the mouse at rest sits where the hand
    /// leaves it.
    var bodyRect: NSRect {
        let body = inView(shapes(.above).mainBody)
        let mid = NSPoint(x: (body.midX * 2).rounded() / 2, y: (body.midY * 2).rounded() / 2)
        return NSRect(x: mid.x - body.width / 2, y: mid.y - body.height / 2, width: body.width, height: body.height)
    }

    /// The whole drawing of the view that shows (body, thumb wing, side buttons).
    var outlineRect: NSRect {
        let viewpoint = self.viewpoint
        let shapes = shapes(viewpoint)
        let outline = shapes.outline()
        for part in [MouseArtworkPart.thumbWheel, .gesture, .forward, .back] {
            if let shape = shapes.shape(of: part) { outline.append(shape) }
        }
        return inView(outline.bounds, viewpoint)
    }

    /// What is held, in the mouse view: the part (in the view of the drawing it shows in),
    /// the placeholder's part, or the badge at rest.
    var buttonRect: NSRect {
        if showsBadge {
            return badgeRect
        }
        let path = buttonShape
        path.transform(using: placement(for: buttonViewpoint))
        return path.bounds
    }

    /// That part on the grid.
    private var buttonShape: NSBezierPath {
        guard let part = heldPart else { return NSBezierPath() }
        return shapes(buttonViewpoint).shape(of: part) ?? NSBezierPath()
    }

    /// The badge while up: centred where the drawing has its badge (on the body's right
    /// edge, low), in the view from above.
    var badgeRect: NSRect {
        guard let hold, showsBadge else { return .zero }
        let size = TriggerBadge.size(for: hold, height: Self.badgeHeight)
        let centre = placement(for: .above).transform(shapes(.above).badgeCentre)
        return NSRect(x: centre.x - size.width / 2, y: centre.y - size.height / 2, width: size.width, height: size.height)
    }

    private var buttonDepth = 0.0
    private var pressPulse = 0.0
    /// How far the frame shown says the drawing has turned to the button's side (0…1).
    private var frameTurn: CGFloat = 0

    /// How far the drawing has turned to the button's side: what the frame says for a mouse
    /// whose part is in its view from the side, 0 for any other (it does not turn).
    var turn: CGFloat {
        return buttonViewpoint == .above ? 0 : frameTurn
    }

    func show(buttonDepth: Double, pressPulse: Double, turn: Double = 0) {
        let turn = CGFloat(min(1, max(0, turn)))
        guard buttonDepth != self.buttonDepth || pressPulse != self.pressPulse || turn != frameTurn else { return }
        self.buttonDepth = buttonDepth
        self.pressPulse = pressPulse
        frameTurn = turn
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        for face in MouseArtworkTurn.faces(at: turn) where model.viewpoints.contains(face.viewpoint) {
            MouseArtworkTurn.draw(face, placement: placement(for: face.viewpoint)) {
                MouseArtworkPainter.draw(shapes(face.viewpoint), ink: .card, unit: Self.unit)
                if face.viewpoint == buttonViewpoint {
                    drawHeldPart()
                }
            }
        }
        if showsBadge {
            drawBadge()
        }
    }

    /// The part held, on the grid (the widths are in points): lit as the Buttons card lights
    /// it, faded by the depth, after a ring that opens up and fades when it goes down; or,
    /// for the default picture, the dashed outline around the placeholder's part.
    private func drawHeldPart() {
        guard let part = heldPart else { return }
        let shapes = shapes(buttonViewpoint)
        guard hold != nil else {
            return drawPlaceholder(around: buttonShape.bounds)
        }
        let button = buttonShape
        let unit = Self.unit
        let depth = CGFloat(min(1, max(0, buttonDepth)))
        let ring = CGFloat(min(1, max(0, pressPulse)))
        if ring > 0 {
            // The ring leaves the buttons and the thumb wheel on and by the part alone
            // (the thumb panel lies right under Forward and Back).
            NSGraphicsContext.saveGraphicsState()
            MouseArtworkPainter.clip(outside: MouseArtworkPainter.parts(over: part, in: shapes))
            let spread = 1.5 + (1 - ring) * 6
            NSColor.controlAccentColor.withAlphaComponent(0.45 * ring).setStroke()
            button.lineWidth = 2 * spread / unit
            button.lineJoinStyle = .round
            button.stroke()
            NSGraphicsContext.restoreGraphicsState()
        }
        guard depth > 0, let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.setAlpha(depth)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        MouseArtworkPainter.drawHighlight(part, shapes: shapes, unit: unit)
        context.endTransparencyLayer()
        context.restoreGState()
    }

    /// The dashed outline of the default picture, `TriggerPlaceholder.outset` outside
    /// `rect` (on the grid), drawn in points.
    private func drawPlaceholder(around rect: NSRect) {
        guard !rect.isEmpty else { return }
        NSGraphicsContext.saveGraphicsState()
        let points = NSAffineTransform()
        points.translateX(by: rect.minX, yBy: rect.minY)
        points.scale(by: 1 / Self.unit)
        points.concat()
        let size = NSRect(x: 0, y: 0, width: rect.width * Self.unit, height: rect.height * Self.unit)
        TriggerPlaceholder.stroke(
            TriggerPlaceholder.path(around: size), highContrast: PreferencesGroupedForm.isHighContrast(effectiveAppearance)
        )
        NSGraphicsContext.restoreGraphicsState()
    }

    /// The badge, in the mouse view: pressed it gets a little smaller, and a ring opens
    /// up around it and fades as around a part.
    private func drawBadge() {
        guard let hold else { return }
        let depth = CGFloat(min(1, max(0, buttonDepth)))
        let ring = CGFloat(min(1, max(0, pressPulse)))
        let rest = badgeRect
        let scale = 1 - (1 - Self.pressedBadgeScale) * depth
        let badge = NSRect(
            x: rest.midX - rest.width * scale / 2, y: rest.midY - rest.height * scale / 2,
            width: rest.width * scale, height: rest.height * scale
        )
        if ring > 0 {
            let radius = badge.height / 2
            let outline = NSBezierPath(roundedRect: badge, xRadius: radius, yRadius: radius)
            let spread = 1.5 + (1 - ring) * 6
            NSColor.controlAccentColor.withAlphaComponent(0.45 * ring).setStroke()
            outline.lineWidth = 2 * spread
            outline.stroke()
        }
        TriggerBadge.draw(hold, in: badge)
    }
}

// MARK: - The screen card

/// What Launchpad's key opens, which the picture draws as the Mac it runs on shows it.
enum GesturePreviewAppsLook: Equatable {
    /// Before macOS 26, Launchpad: the desktop darkens and the windows give way to a grid
    /// of app icons over the whole screen.
    case launchpad
    /// From macOS 26 on, Apps: a panel in the middle of the screen, a search field at its
    /// top and the apps under it. The windows stay where they are behind it.
    case panel

    /// The look on macOS `majorVersion`. It changes with the name the rows give the action
    /// (`SystemShortcut.Shortcut.nameKey`).
    init(macOS majorVersion: Int) {
        self = majorVersion >= 26 ? .panel : .launchpad
    }

    /// This Mac's.
    static var current: GesturePreviewAppsLook {
        return GesturePreviewAppsLook(macOS: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    }
}

/// The right card: a row of desktops seen through the screen, a menu bar and a dock that
/// stay put, the overview of Mission Control (whose Spaces bar takes the menu bar's place,
/// as on a Mac), the app grid (Launchpad, or the panel of Apps: `appsLook`), the windows
/// out of the way for Show Desktop, the pulse of other actions and the pointer.
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
    static let overviewScale: CGFloat = 0.7
    /// Mission Control's Spaces bar: a strip along the top edge, a little taller than the
    /// menu bar it replaces, with the names of the Spaces in its middle. (The pictures of
    /// the Spaces only come when the pointer goes up there; the picture shows the bar as
    /// it is when Mission Control has just opened.)
    static let spacesBarHeight: CGFloat = 12
    static let spaceNameSize = NSSize(width: 22, height: 3)
    static let spaceNameGap: CGFloat = 14
    /// Show Desktop: how much of a window stays in sight at the edge it slid to.
    static let showDesktopSliver: CGFloat = 5
    /// What lies on the desktop: how many items, their size, and their place in a column
    /// from the top-right corner, as a Mac sorts them.
    static let desktopItemCount = 3
    static let desktopItemSize = NSSize(width: 15, height: 12)
    static let desktopItemPitch: CGFloat = 25
    /// Show Desktop: how far the windows have slid away (0…1) before what lies on the
    /// desktop starts to show. The window that passes over the column of items has left it
    /// by then (a test holds the number against the layout), so nothing of an item sticks
    /// out from under a window on its way, where a hold that follows the hand can stand
    /// still and where Reduce Motion shows it.
    static let desktopItemsAppearAt: CGFloat = 0.93
    /// The app grid: the windows have faded out when it is this far open, and its icons
    /// show from this far on, so that half open (the stop of a hold that follows the hand)
    /// reads as the grid arriving, not as two pictures half there.
    static let appGridWindowsGoneAt: CGFloat = 0.6
    static let appGridIconsFrom: CGFloat = 0.3
    /// The panel of Apps: its icons, and how much smaller it is when it starts to show.
    static let appsIconColumns = 6
    static let appsIconRows = 3
    static let appsIconSize: CGFloat = 12
    static let appsPanelStartScale: CGFloat = 0.6
    static let pointerSize = NSSize(width: 11, height: 17)

    private(set) var shown: GesturePreviewLoop.Frame?

    /// How the app grid is drawn: as this Mac shows it. A seam for the tests and renders.
    var appsLook = GesturePreviewAppsLook.current {
        didSet {
            if appsLook != oldValue { needsDisplay = true }
        }
    }

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
            && a.showDesktop == b.showDesktop
            && a.pulse == b.pulse && a.pulseSymbol == b.pulseSymbol && a.pulseText == b.pulseText
            && a.pointerOffset == b.pointerOffset
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

    /// Where a window is in Mission Control: smaller, side by side (none over another),
    /// in the middle of the room between the Spaces bar and the Dock.
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
        let top = spacesBarHeight, bottom = size.height - dockHeight - 4
        for (index, candidate) in order.enumerated() {
            let itemSize = sizes[index]
            if candidate == kind {
                return NSRect(x: x, y: top + (bottom - top - itemSize.height) / 2, width: itemSize.width, height: itemSize.height)
            }
            x += itemSize.width + gap
        }
        return windowRect(kind, in: size)
    }

    /// Where a window is when Show Desktop has moved the windows out of the way: at its own
    /// size, slid to the side of the screen it is nearer to until only a sliver of it is in
    /// sight; a window in the middle goes up, under the menu bar. None leaves through the
    /// bottom, where the Dock is.
    static func showDesktopRect(_ kind: WindowKind, in size: NSSize) -> NSRect {
        let home = windowRect(kind, in: size)
        let sliver = showDesktopSliver
        let fromMiddle = home.midX - size.width / 2
        if abs(fromMiddle) < size.width * 0.1 {
            return home.offsetBy(dx: 0, dy: menuBarHeight + sliver - home.maxY)
        }
        if fromMiddle < 0 {
            return home.offsetBy(dx: sliver - home.maxX, dy: 0)
        }
        return home.offsetBy(dx: size.width - sliver - home.minX, dy: 0)
    }

    /// Where the things on the desktop lie (`desktopItemCount` of them, top to bottom): the
    /// icon of each; its name is drawn under it.
    static func desktopItemRects(in size: NSSize) -> [NSRect] {
        let item = desktopItemSize
        let x = (size.width - 14 - item.width).rounded()
        return (0..<desktopItemCount).map { index in
            NSRect(x: x, y: menuBarHeight + 12 + CGFloat(index) * desktopItemPitch, width: item.width, height: item.height)
        }
    }

    /// The name under a thing on the desktop whose icon is at `item` (the second one's is
    /// shorter).
    static func desktopItemNameRect(under item: NSRect, index: Int) -> NSRect {
        let width: CGFloat = index == 1 ? 13 : 17
        return NSRect(x: item.midX - width / 2, y: item.maxY + 3, width: width, height: 2.5)
    }

    /// The panel of Apps when it is whole, on a desktop `size` large: in the middle of the
    /// room between the menu bar and the Dock, a little above it, the windows in sight on
    /// both sides.
    static func appsPanelRect(in size: NSSize) -> NSRect {
        var width = min(150, (size.width * 0.62).rounded())
        // On whole points and in the middle: as odd or even as the card is wide.
        if (size.width - width).truncatingRemainder(dividingBy: 2) != 0 { width -= 1 }
        let height: CGFloat = 92
        let room = size.height - menuBarHeight - dockHeight - 4
        let top = menuBarHeight + ((room - height) / 2).rounded() - 3
        return NSRect(x: (size.width - width) / 2, y: top, width: width, height: height)
    }

    /// The search field at the top of the panel at `panel`.
    static func appsSearchFieldRect(in panel: NSRect) -> NSRect {
        return NSRect(x: panel.minX + 7, y: panel.minY + 7, width: panel.width - 14, height: 12)
    }

    /// The app icons on the panel at `panel`, row by row from the top left: rows as wide
    /// as the search field's text, evenly apart, in the room under the field.
    static func appsIconRects(in panel: NSRect) -> [NSRect] {
        let field = appsSearchFieldRect(in: panel)
        let side = appsIconSize
        let left = panel.minX + 12, right = panel.maxX - 12
        let top = field.maxY + 9, bottom = panel.maxY - 9
        let pitchX = (right - left - side) / CGFloat(appsIconColumns - 1)
        let pitchY = (bottom - top - side) / CGFloat(appsIconRows - 1)
        var rects: [NSRect] = []
        for row in 0..<appsIconRows {
            for column in 0..<appsIconColumns {
                // On half points, a whole pixel of a Retina screen.
                let x = ((left + CGFloat(column) * pitchX) * 2).rounded() / 2
                let y = ((top + CGFloat(row) * pitchY) * 2).rounded() / 2
                rects.append(NSRect(x: x, y: y, width: side, height: side))
            }
        }
        return rects
    }

    /// Mission Control's Spaces bar when it is whole: along the top edge, where the menu
    /// bar was.
    static func spacesBarRect(in size: NSSize) -> NSRect {
        return NSRect(x: 0, y: 0, width: size.width, height: spacesBarHeight)
    }

    /// The names of the two Spaces on the whole bar, side by side in its middle.
    static func spaceNameRects(in size: NSSize) -> [NSRect] {
        let name = spaceNameSize
        let left = ((size.width - 2 * name.width - spaceNameGap) / 2).rounded()
        return (0..<2).map { index in
            NSRect(
                x: left + CGFloat(index) * (name.width + spaceNameGap), y: (spacesBarHeight - name.height) / 2,
                width: name.width, height: name.height
            )
        }
    }

    // MARK: How strongly a piece shows

    private static func unit(_ value: CGFloat) -> CGFloat {
        return min(1, max(0, value.isFinite ? value : 0))
    }

    /// What lies on the desktop while the windows are `windowsAway` (0…1) out of the way
    /// for Show Desktop: nothing until they have left (`desktopItemsAppearAt`), then it
    /// comes up, whole when they are away.
    static func desktopItemStrength(windowsAway: CGFloat) -> CGFloat {
        let p = unit((windowsAway - desktopItemsAppearAt) / (1 - desktopItemsAppearAt))
        return p * p * (3 - 2 * p)
    }

    /// Mission Control's Spaces bar while the overview is `overview` (0…1) open: how far
    /// it has come down from above the top edge, and how strong it is. In place and whole
    /// from half open on, the stop of a hold that follows the hand, where it must not
    /// stand half out or half transparent.
    static func spacesBarStrength(overview: CGFloat) -> CGFloat {
        return unit(overview * 2)
    }

    /// The menu bar while the overview is `overview` (0…1) open: it makes way for the
    /// Spaces bar, and is gone when that is in place.
    static func menuBarStrength(overview: CGFloat) -> CGFloat {
        return 1 - spacesBarStrength(overview: overview)
    }

    /// The windows while the app grid is `appGrid` (0…1) open: gone at
    /// `appGridWindowsGoneAt`, and most of the way there early (half open, a trace of them
    /// is left).
    static func windowStrength(appGrid: CGFloat) -> CGFloat {
        let left = 1 - unit(appGrid / appGridWindowsGoneAt)
        return left * left
    }

    /// The icons of the app grid while it is `appGrid` (0…1) open: from `appGridIconsFrom`
    /// on, quickly at first (half open they are half there, and clearly the picture).
    static func appGridIconStrength(_ appGrid: CGFloat) -> CGFloat {
        let missing = 1 - unit((appGrid - appGridIconsFrom) / (1 - appGridIconsFrom))
        return 1 - missing * missing
    }

    /// The panel of Apps while it is `appGrid` (0…1) open: whole from half open on, the
    /// stop of a hold that follows the hand, where the windows behind it must not show
    /// through it (the same picture twice, half there). How far it is open shows in its
    /// size.
    static func appsPanelStrength(_ appGrid: CGFloat) -> CGFloat {
        let missing = 1 - unit(appGrid * 2)
        return 1 - missing * missing
    }

    /// The panel's size while it is `appGrid` (0…1) open: it grows into place from
    /// `appsPanelStartScale`, with the hand.
    static func appsPanelScale(_ appGrid: CGFloat) -> CGFloat {
        return appsPanelStartScale + (1 - appsPanelStartScale) * unit(appGrid)
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
            let away = index % 2 == current ? CGFloat(frame?.showDesktop ?? 0) : 0
            drawDesktop(index % 2, at: x, overview: overview, gridFade: grid, windowsAway: away)
        }

        drawMenuBar(strength: Self.menuBarStrength(overview: CGFloat(frame?.overview ?? 0)))
        if let frame, frame.appGrid > 0 {
            switch appsLook {
            case .launchpad: drawAppGrid(CGFloat(frame.appGrid))
            case .panel: drawAppsPanel(CGFloat(frame.appGrid))
            }
        }
        // The dock stays on top of the app grid, as it does on a Mac.
        drawDock()
        if let frame, frame.overview > 0 {
            drawSpacesBar(progress: CGFloat(frame.overview), current: current)
        }
        if let frame, frame.pulse > 0, let symbol = frame.pulseSymbol {
            drawPulse(CGFloat(frame.pulse), symbol: symbol)
        } else if let frame, frame.pulse > 0, let text = frame.pulseText {
            drawPulse(CGFloat(frame.pulse), text: text)
        }
        drawPointer(offset: frame?.pointerOffset ?? .zero, atRest: frame?.isAtRest ?? true)

        NSGraphicsContext.restoreGraphicsState()
        ScrollPreviewPalette.cardEdge.setStroke()
        card.lineWidth = 1
        card.stroke()
    }

    /// One desktop: its wallpaper and its windows. `overview` moves the windows to their
    /// places in Mission Control, `gridFade` is how far the app grid is open (the windows
    /// fade out under Launchpad, `windowStrength`; behind the panel of Apps they stay as
    /// they are), and `windowsAway` slides them to the edges for
    /// Show Desktop; what lies on the desktop comes up once they have left
    /// (`desktopItemStrength`). All 0…1; one of them at a time. The windows are drawn under
    /// the menu bar's lower edge only: one that goes up for Show Desktop slides in behind
    /// the menu bar and does not show through it.
    private func drawDesktop(_ index: Int, at x: CGFloat, overview: CGFloat, gridFade: CGFloat, windowsAway: CGFloat) {
        let rect = NSRect(x: x, y: 0, width: bounds.width, height: bounds.height)
        let start = index == 0 ? ScrollPreviewPalette.desktopStart : GesturePreviewPalette.secondDesktopStart
        let end = index == 0 ? ScrollPreviewPalette.desktopEnd : GesturePreviewPalette.secondDesktopEnd
        NSGradient(starting: start, ending: end)?.draw(in: rect, angle: index == 0 ? -35 : 35)
        let items = Self.desktopItemStrength(windowsAway: windowsAway)
        if items > 0 {
            drawDesktopItems(at: x, strength: items)
        }

        let alpha = appsLook == .launchpad ? Self.windowStrength(appGrid: gridFade) : 1
        guard alpha > 0.01 else { return }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: 0, y: Self.menuBarHeight, width: bounds.width, height: bounds.height - Self.menuBarHeight)).addClip()
        NSGraphicsContext.current?.cgContext.setAlpha(alpha)
        NSGraphicsContext.current?.cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
        for kind in Self.windows(onDesktop: index) {
            let home = Self.windowRect(kind, in: bounds.size)
            let target = Self.overviewRect(kind, onDesktop: index, in: bounds.size)
            var place = lerp(home, target, overview)
            if windowsAway > 0 {
                place = lerp(place, Self.showDesktopRect(kind, in: bounds.size), windowsAway)
            }
            drawWindow(kind, in: place.offsetBy(dx: x, dy: 0), natural: home.size)
        }
        NSGraphicsContext.current?.cgContext.endTransparencyLayer()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// What lies on the desktop, a column in the top-right corner: two folders and a
    /// document, each with its name under it, as strong as `strength` (0…1,
    /// `desktopItemStrength`: they come up once the windows have left).
    private func drawDesktopItems(at x: CGFloat, strength: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(min(1, max(0, strength)))
        NSGraphicsContext.current?.cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
        for (index, home) in Self.desktopItemRects(in: bounds.size).enumerated() {
            let rect = home.offsetBy(dx: x, dy: 0)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor(white: 0, alpha: 0.25)
            shadow.shadowBlurRadius = 1.5
            shadow.shadowOffset = NSSize(width: 0, height: -0.5)
            shadow.set()
            if index == Self.desktopItemCount - 1 {
                // A document: a sheet, upright.
                let sheet = NSRect(x: rect.midX - 5, y: rect.minY - 1, width: 10, height: rect.height + 1)
                GesturePreviewPalette.desktopDocument.setFill()
                NSBezierPath(roundedRect: sheet, xRadius: 1.5, yRadius: 1.5).fill()
                NSGraphicsContext.restoreGraphicsState()
                GesturePreviewPalette.desktopDocumentLine.setFill()
                for row in 0..<3 {
                    capsule(NSRect(x: sheet.minX + 2, y: sheet.minY + 3 + CGFloat(row) * 3, width: row == 2 ? 4 : 6, height: 1.2)).fill()
                }
            } else {
                // A folder: its tab behind, its front over it.
                GesturePreviewPalette.desktopFolderTab.setFill()
                NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.minY, width: rect.width * 0.5, height: 5), xRadius: 1.5, yRadius: 1.5).fill()
                NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.minY + 1.5, width: rect.width, height: rect.height - 1.5), xRadius: 2, yRadius: 2).fill()
                NSGraphicsContext.restoreGraphicsState()
                GesturePreviewPalette.desktopFolder.setFill()
                NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.minY + 3.5, width: rect.width, height: rect.height - 3.5), xRadius: 2, yRadius: 2).fill()
            }
            // Its name.
            GesturePreviewPalette.desktopItemName.setFill()
            capsule(Self.desktopItemNameRect(under: rect, index: index)).fill()
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

    /// The menu bar, as strong as `strength` (0…1): whole, except while Mission Control
    /// opens (`menuBarStrength`).
    private func drawMenuBar(strength: CGFloat = 1) {
        guard strength > 0, let context = NSGraphicsContext.current?.cgContext else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        if strength < 1 {
            context.setAlpha(strength)
        }
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

    /// Mission Control's Spaces bar, as a Mac shows it when Mission Control has just
    /// opened: a strip along the top edge in the menu bar's place, with the names of the
    /// Spaces in its middle, the one on screen stronger. It comes down from above the top
    /// edge and is in place, and whole, by half open (`spacesBarStrength`).
    private func drawSpacesBar(progress: CGFloat, current: Int) {
        let shown = Self.spacesBarStrength(overview: progress)
        guard shown > 0, let context = NSGraphicsContext.current?.cgContext else { return }
        let bar = Self.spacesBarRect(in: bounds.size).offsetBy(dx: 0, dy: -(1 - shown) * Self.spacesBarHeight)
        NSGraphicsContext.saveGraphicsState()
        context.setAlpha(shown)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        GesturePreviewPalette.spacesBar.setFill()
        bar.fill(using: .sourceOver)
        GesturePreviewPalette.spacesBarEdge.setFill()
        NSRect(x: bar.minX, y: bar.maxY - 0.5, width: bar.width, height: 0.5).fill(using: .sourceOver)
        for (index, name) in Self.spaceNameRects(in: bounds.size).enumerated() {
            (index == current ? GesturePreviewPalette.spaceName : GesturePreviewPalette.otherSpaceName).setFill()
            capsule(name.offsetBy(dx: 0, dy: bar.minY)).fill()
        }
        context.endTransparencyLayer()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Apps (macOS 26 and later): a panel that comes up in the middle of the screen over
    /// the windows, which stay as they are: a search field at its top and rows of app
    /// icons under it. It grows into place as it shows (`appsPanelScale`,
    /// `appsPanelStrength`).
    private func drawAppsPanel(_ progress: CGFloat) {
        let strength = Self.appsPanelStrength(progress)
        guard strength > 0, let context = NSGraphicsContext.current?.cgContext else { return }
        let whole = Self.appsPanelRect(in: bounds.size)
        let scale = Self.appsPanelScale(progress)
        NSGraphicsContext.saveGraphicsState()
        context.setAlpha(strength)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        let grow = NSAffineTransform()
        grow.translateX(by: whole.midX, yBy: whole.midY)
        grow.scaleX(by: scale, yBy: scale)
        grow.translateX(by: -whole.midX, yBy: -whole.midY)
        grow.concat()

        let radius: CGFloat = 10
        let panel = NSBezierPath(roundedRect: whole, xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.35)
        shadow.shadowBlurRadius = 8
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.set()
        GesturePreviewPalette.appsPanel.setFill()
        panel.fill()
        NSGraphicsContext.restoreGraphicsState()
        let edge = NSBezierPath(roundedRect: whole.insetBy(dx: 0.25, dy: 0.25), xRadius: radius, yRadius: radius)
        edge.lineWidth = 0.5
        GesturePreviewPalette.appsPanelEdge.setStroke()
        edge.stroke()

        // The search field: a magnifying glass and a word.
        let field = Self.appsSearchFieldRect(in: whole)
        GesturePreviewPalette.appsSearchField.setFill()
        capsule(field).fill()
        GesturePreviewPalette.appsSearchText.setStroke()
        let lens = NSRect(x: field.minX + 5, y: field.midY - 2.5, width: 4, height: 4)
        let glass = NSBezierPath(ovalIn: lens)
        glass.move(to: NSPoint(x: lens.maxX - 0.6, y: lens.maxY - 0.6))
        glass.line(to: NSPoint(x: lens.maxX + 1.4, y: lens.maxY + 1.4))
        glass.lineWidth = 1
        glass.lineCapStyle = .round
        glass.stroke()
        GesturePreviewPalette.appsSearchText.setFill()
        capsule(NSRect(x: lens.maxX + 5, y: field.midY - 1, width: 26, height: 2)).fill()

        for (index, rect) in Self.appsIconRects(in: whole).enumerated() {
            GesturePreviewPalette.tiles[index % GesturePreviewPalette.tiles.count].setFill()
            NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.24, yRadius: rect.width * 0.24).fill()
            NSColor.white.withAlphaComponent(0.55).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: rect.width * 0.32, dy: rect.width * 0.32)).fill()
        }
        context.endTransparencyLayer()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Launchpad (before macOS 26): the desktop darkens and the windows give way to rows of
    /// app icons, which show once the windows are on their way out (`appGridIconStrength`).
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
        let strength = Self.appGridIconStrength(progress)
        guard strength > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(strength)
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
        let centre = pulseCentre
        drawPulsePanel(NSRect(x: centre.x - side / 2, y: centre.y - side / 2, width: side, height: side), progress: progress) {
            if let image = Self.symbolImage(symbol, pointSize: 19 * side / 44) {
                let size = image.size
                image.draw(
                    in: NSRect(x: centre.x - size.width / 2, y: centre.y - size.height / 2, width: size.width, height: size.height),
                    from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil
                )
            }
        }
    }

    /// The pulse of a recorded key combination: the character of its icon, as large as a
    /// symbol, or its keys a little smaller, on a panel as wide as they need.
    private func drawPulse(_ progress: CGFloat, text: String) {
        let side = 44 * (0.86 + 0.14 * progress)
        let centre = pulseCentre
        let isOneCharacter = text.count == 1
        let font = NSFont.systemFont(ofSize: (isOneCharacter ? 20 : 14) * side / 44, weight: .medium)
        let attributed = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: GesturePreviewPalette.hudSymbol,
        ])
        let size = attributed.size()
        let width = min(bounds.width - 16, max(side, size.width + 20 * side / 44))
        let rect = NSRect(x: centre.x - width / 2, y: centre.y - side / 2, width: width, height: side)
        drawPulsePanel(rect, progress: progress) {
            attributed.draw(at: NSPoint(x: centre.x - size.width / 2, y: centre.y - size.height / 2))
        }
    }

    private var pulseCentre: NSPoint {
        return NSPoint(x: bounds.midX, y: (bounds.height + Self.menuBarHeight - Self.dockHeight) / 2)
    }

    /// The pulse's panel, faded in by `progress`, with `content` on it.
    private func drawPulsePanel(_ rect: NSRect, progress: CGFloat, content: () -> Void) {
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
        content()
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
