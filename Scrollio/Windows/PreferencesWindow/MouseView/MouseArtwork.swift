//
//  MouseArtwork.swift
//  Mos
//  The mouse the Mouse, Buttons and Gestures panes draw, seen from above in line art, one
//  drawing per model: the MX Master 4, the MX Master 3 and 3S, and a plain mouse for any
//  other. Here are which drawing a connected mouse gets, the shapes of its parts on one
//  grid (front at the top, the thumb side on the left) and the painter that draws them in
//  the colours of the Scrolling preview (ScrollPreviewPalette), at any size: the cards'
//  drawing, the rows' small pictures (a schematic variant whose small buttons are drawn
//  larger and further apart) and the Gestures preview.
//
//  A model can have a second view, from the thumb side (MouseArtworkViewpoint): what the
//  thumb works is hidden under the body's overhang from above. The MX Master 4 and the MX
//  Master 3 have one (their two views are in MouseArtworkMaster4.swift and
//  MouseArtworkMaster3.swift, painted by MouseArtworkTwoViews.swift); a part lights in one
//  view, and the panes turn the drawing to it (MouseArtworkTurn). The plain mouse has the
//  one view from above, and its shapes and painting are here.
//
//  An illustration, not a product render: no logo, no brand marks.
//

import Cocoa

// MARK: - Which mouse

/// Which drawing the panes show.
enum MouseArtworkModel: CaseIterable {
    /// Logitech MX Master 4: on its thumb side the thumb wheel, under it Forward and Back
    /// in a row with the gesture button in front of them, and beneath them the thumb rest
    /// that clicks and pulses (the haptic sense panel). Drawn in two views.
    case mxMaster4
    /// Logitech MX Master 3, 3S and 3 for Mac: two side buttons under the thumb wheel, the
    /// gesture button hidden in the thumb rest.
    case mxMaster3
    /// Any other mouse: symmetric, a wheel and two side buttons.
    case generic

    /// The drawing for a mouse that calls itself `name` (as `LogiCenter` reports the
    /// connected Logitech mouse); nil, or a mouse without a drawing of its own: `generic`.
    /// "MX Master 4" → `mxMaster4`; "MX Master 3", "MX Master 3S", "MX Master 3 for Mac"
    /// → `mxMaster3`.
    static func model(forDeviceName name: String?) -> MouseArtworkModel {
        guard let name else { return .generic }
        // Words of letters and digits: "MX Master 3S for Mac" → mx, master, 3s, for, mac.
        let words = name.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard let master = words.indices.first(where: { $0 > 0 && words[$0 - 1] == "mx" && words[$0] == "master" }),
              master + 1 < words.count else { return .generic }
        switch words[master + 1] {
        case "4": return .mxMaster4
        case "3", "3s": return .mxMaster3
        default: return .generic
        }
    }

    /// The parts this mouse has (each has a shape of its own in its drawing).
    var parts: [MouseArtworkPart] {
        switch self {
        case .mxMaster4: return MouseArtworkPart.allCases
        case .mxMaster3: return MouseArtworkPart.allCases.filter { $0 != .thumbPanel }
        case .generic: return [.body, .left, .right, .wheel, .back, .forward]
        }
    }

    func has(_ part: MouseArtworkPart) -> Bool {
        return parts.contains(part)
    }

    /// The button the Gestures preview holds down: the gesture button; a plain mouse has
    /// none, there the Back button stands in (the side button a gesture is set on most).
    var gesturePreviewPart: MouseArtworkPart {
        return has(.gesture) ? .gesture : .back
    }

    // MARK: Views

    /// The views this mouse is drawn in: from above always, and from the thumb side where
    /// the drawing has that view.
    var viewpoints: [MouseArtworkViewpoint] {
        return self == .generic ? [.above] : [.above, .thumbSide]
    }

    var hasSideView: Bool {
        return viewpoints.contains(.thumbSide)
    }

    /// The parts that light in the view from the thumb side: what the thumb works. From
    /// above they are under the body's overhang (the side buttons do not show there at
    /// all; the thumb wheel and the thumb rest show, small and partly covered). Empty for
    /// a mouse drawn from above only.
    var sideParts: Set<MouseArtworkPart> {
        switch self {
        case .mxMaster4: return [.thumbWheel, .forward, .back, .gesture, .thumbPanel]
        // The MX Master 3's gesture button is its thumb rest, pressed down: it lights from above.
        case .mxMaster3: return [.thumbWheel, .forward, .back]
        case .generic: return []
        }
    }

    /// The view `part` lights in. From above for everything the fingers work, for the
    /// whole mouse, for nothing (nil) and for a part this mouse does not have.
    func viewpoint(lighting part: MouseArtworkPart?) -> MouseArtworkViewpoint {
        guard let part, has(part), sideParts.contains(part) else { return .above }
        return .thumbSide
    }
}

/// From where a drawing shows the mouse.
enum MouseArtworkViewpoint: Int, CaseIterable {
    /// From above: the front at the top, the thumb side on the left. Every model has it;
    /// it is the view at rest.
    case above
    /// From the thumb side: the front to the left, the mouse standing on its base.
    case thumbSide
}

/// The parts of the drawings that can light up.
enum MouseArtworkPart: Int, CaseIterable {
    /// The whole mouse: its outline lights.
    case body
    case left
    case right
    /// The wheel: turning it, and pressing it (the middle button).
    case wheel
    /// The small button behind the wheel.
    case modeShift
    /// The roller on the thumb side.
    case thumbWheel
    case back
    case forward
    /// MX Master 4: the front one of the three side buttons. MX Master 3: the pad in the
    /// front of the thumb rest.
    case gesture
    /// MX Master 4: the thumb rest, which clicks and pulses.
    case thumbPanel
}

// MARK: - The shapes

/// The shapes of one view of one model's drawing on the design grid (`grid`, top-left
/// origin; from above the front at the top and the thumb side on the left). A painter
/// scales them to the size it draws at.
struct MouseArtworkShapes {

    /// Every drawing from above fits this grid; the MX Master fills it, the plain mouse is
    /// narrower.
    static let grid = NSSize(width: 88, height: 120)
    /// The grid widened for a view from the side, where the mouse lies across: as long as
    /// it is from above (the two views are the same mouse at the same size) and centred on
    /// the grid's middle, so a drawing can turn from one view to the other in place. Every
    /// drawing of every view fits it.
    static let canvas = NSRect(x: -16, y: 0, width: 120, height: 120)
    /// The middle of both: what a drawing turns about.
    static let centre = NSPoint(x: grid.width / 2, y: grid.height / 2)
    /// The clear rim along the MX Master 4's buttons.
    static let rimWidth: CGFloat = 3.5

    let model: MouseArtworkModel
    /// For the rows' small pictures: the side buttons, the thumb wheel and the button
    /// behind the wheel larger and further apart (not to scale), so front, middle and rear
    /// can be told apart at 20 points.
    var schematic = false
    /// From where the mouse is seen. A model without the view asked for is seen from above.
    let viewpoint: MouseArtworkViewpoint

    init(model: MouseArtworkModel, schematic: Bool = false, viewpoint: MouseArtworkViewpoint = .above) {
        self.model = model
        self.schematic = schematic
        self.viewpoint = model.viewpoints.contains(viewpoint) ? viewpoint : .above
    }

    /// The view `part` lights in; from above for nil.
    init(model: MouseArtworkModel, schematic: Bool = false, lighting part: MouseArtworkPart?) {
        self.init(model: model, schematic: schematic, viewpoint: model.viewpoint(lighting: part))
    }

    /// `part` lights in this view: the mouse has it, and this is the view it lights in.
    func lights(_ part: MouseArtworkPart) -> Bool {
        return model.has(part) && model.viewpoint(lighting: part) == viewpoint
    }

    /// The drawing of a mouse that is drawn in two views, which has shapes of its own for
    /// each (MouseArtworkMaster4.swift, MouseArtworkMaster3.swift); nil for the plain mouse,
    /// whose one drawing is below.
    var views: MouseArtworkTwoViews? {
        switch model {
        case .mxMaster4: return MouseArtworkMaster4(viewpoint: viewpoint, schematic: schematic)
        case .mxMaster3: return MouseArtworkMaster3(viewpoint: viewpoint, schematic: schematic)
        case .generic: return nil
        }
    }

    // MARK: Body

    /// The outline. The plain mouse: symmetric, rounder at the back.
    func outline() -> NSBezierPath {
        if let views { return views.outline() }
        let path = NSBezierPath()
        path.move(to: p(44, 2))
        path.curve(to: p(74, 34), controlPoint1: p(61, 2), controlPoint2: p(72, 15))
        path.curve(to: p(77, 84), controlPoint1: p(76, 50), controlPoint2: p(78, 68))
        path.curve(to: p(44, 119), controlPoint1: p(76, 106), controlPoint2: p(62, 119))
        path.curve(to: p(11, 84), controlPoint1: p(26, 119), controlPoint2: p(12, 106))
        path.curve(to: p(14, 34), controlPoint1: p(10, 68), controlPoint2: p(12, 50))
        path.curve(to: p(44, 2), controlPoint1: p(16, 15), controlPoint2: p(27, 2))
        path.close()
        return path
    }

    /// The body without the thumb wing, for centring the drawing.
    var mainBody: NSRect {
        if let views { return views.mainBody }
        return NSRect(x: 10.5, y: 2, width: 67, height: 117)
    }

    /// Where the two buttons end (a curve across the body) and the split between them; the
    /// painter clips them to the outline.
    func seams() -> NSBezierPath {
        if let views { return views.seams() }
        let path = NSBezierPath()
        path.move(to: p(6, 47))
        path.curve(to: p(82, 47), controlPoint1: p(28, 57), controlPoint2: p(60, 57))
        path.move(to: p(44, -2))
        path.line(to: p(44, 53))
        return path
    }

    /// The plain mouse's left (or right) button: the body in front of where the buttons
    /// end, on its side of the split.
    private func buttonArea(left: Bool) -> NSBezierPath {
        let front = NSBezierPath()
        let split: CGFloat = 44
        front.move(to: p(-4, 47))
        front.line(to: p(6, 47))
        front.curve(to: p(82, 47), controlPoint1: p(28, 57), controlPoint2: p(60, 57))
        front.line(to: p(92, 47))
        front.line(to: p(92, -4))
        front.line(to: p(-4, -4))
        front.close()
        let side = NSBezierPath(rect: left
            ? NSRect(x: -4, y: -4, width: split + 4, height: 80)
            : NSRect(x: split, y: -4, width: 96 - split, height: 80))
        return NSBezierPath(cgPath: outline().cgPath.intersection(front.cgPath).intersection(side.cgPath))
    }

    // MARK: Wheel

    var wheelRect: NSRect {
        if let views { return views.wheelRect }
        let rect = NSRect(x: 39.5, y: 11, width: 9, height: 24)
        return schematic ? grown(rect, width: 1.5, height: 1) : rect
    }

    /// The slot the wheel turns in.
    var wellRect: NSRect {
        if let views { return views.wellRect }
        return wheelRect.insetBy(dx: -3, dy: -3)
    }

    // MARK: Parts

    /// The shape of `part` in this view of the drawing; nil when this mouse does not have
    /// it, or when it does not show from here (the side buttons of a mouse drawn in two
    /// views from above, its two buttons and the wheel from the side).
    func shape(of part: MouseArtworkPart) -> NSBezierPath? {
        guard model.has(part) else { return nil }
        if let views { return views.shape(of: part) }
        switch part {
        case .body:
            return outline()
        case .left:
            return buttonArea(left: true)
        case .right:
            return buttonArea(left: false)
        case .wheel:
            return capsule(wheelRect)
        case .back, .forward:
            return sideButton(part)
        case .modeShift, .thumbWheel, .gesture, .thumbPanel:
            // The plain mouse has none of them.
            return nil
        }
    }

    /// The plain mouse's side buttons, front to back, on its left edge.
    private func sideButton(_ part: MouseArtworkPart) -> NSBezierPath? {
        typealias Button = (from: NSPoint, to: NSPoint, width: CGFloat)
        let buttons: [MouseArtworkPart: Button] = schematic
            ? [
                .forward: (p(11.8, 42), p(11.2, 49), 10),
                .back: (p(10.4, 62), p(10.4, 69), 10),
            ]
            : [
                .forward: (p(12.7, 45), p(12.1, 54.5), 5.6),
                .back: (p(11.6, 61.5), p(11.3, 71), 5.6),
            ]
        guard let button = buttons[part] else { return nil }
        return capsule(from: button.from, to: button.to, width: button.width)
    }

    /// Where the badge of a button the drawing cannot show sits: on the right edge, low.
    var badgeCentre: NSPoint {
        if let views { return views.badgeCentre }
        return p(72, 98)
    }

    // MARK: Helpers

    private func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        return NSPoint(x: x, y: y)
    }

    private func grown(_ rect: NSRect, width: CGFloat, height: CGFloat) -> NSRect {
        return rect.insetBy(dx: -rect.width * (width - 1) / 2, dy: -rect.height * (height - 1) / 2)
    }

    func capsule(_ rect: NSRect) -> NSBezierPath {
        let radius = min(rect.width, rect.height) / 2
        return NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    }

    /// A capsule `width` wide whose round ends are centred on `start` and `end`.
    func capsule(from start: NSPoint, to end: NSPoint, width: CGFloat) -> NSBezierPath {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = (dx * dx + dy * dy).squareRoot() + width
        let path = NSBezierPath(
            roundedRect: NSRect(x: -length / 2, y: -width / 2, width: length, height: width),
            xRadius: width / 2, yRadius: width / 2
        )
        let angle = atan2(dy, dx)
        path.transform(using: AffineTransform(
            m11: cos(angle), m12: sin(angle), m21: -sin(angle), m22: cos(angle),
            tX: (start.x + end.x) / 2, tY: (start.y + end.y) / 2
        ))
        return path
    }
}

// MARK: - Colours and the painter

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
    /// The ridges of a lit wheel.
    static let litRidge = NSColor(white: 1, alpha: 0.6)
}

/// How one picture of the mouse is drawn: its colours and line widths (in points).
struct MouseArtworkInk {
    var bodyFill: NSColor
    var outline: NSColor
    var seam: NSColor
    /// The slot of the wheel, the small buttons.
    var well: NSColor
    var wheel: NSColor
    var wheelRidge: NSColor
    /// The thumb rest.
    var panel: NSColor
    /// The edge of a small button or the thumb rest.
    var partEdge: NSColor
    /// A lit part.
    var lit: NSColor
    var outlineWidth: CGFloat
    var seamWidth: CGFloat
    var partEdgeWidth: CGFloat
    /// The ridges across the wheels; too fine for the small pictures.
    var ridges = true
    var shadow = true
    /// The small parts are drawn opaque (their colour over `bodyFill`); on the selection
    /// only their edge is drawn.
    var fillsParts = true
    /// The slot around the wheel; too fine for the small pictures.
    var drawsWell = true

    /// The cards' drawing and the Gestures preview.
    static var card: MouseArtworkInk {
        return MouseArtworkInk(
            bodyFill: ScrollPreviewPalette.mouseFill,
            outline: ScrollPreviewPalette.mouseLine,
            seam: ScrollPreviewPalette.mouseSeam,
            well: ScrollPreviewPalette.wheelWell,
            wheel: MouseArtworkPalette.wheel,
            wheelRidge: MouseArtworkPalette.wheelRidge,
            panel: MouseArtworkPalette.panel,
            partEdge: ScrollPreviewPalette.mouseSeam,
            lit: .controlAccentColor,
            outlineWidth: 1.5,
            seamWidth: 1,
            partEdgeWidth: 1
        )
    }
}

/// Draws a drawing's shapes. The caller sets up the transform: grid units to points, `unit`
/// points each (line widths are given in points).
enum MouseArtworkPainter {

    /// The whole mouse, `lit` in the ink's lit colour (the small pictures light a part in
    /// the drawing itself; the cards lay `drawHighlight` over it).
    ///
    /// The drawing is the one view `shapes` is of; a part that does not light in that view
    /// is drawn unlit.
    static func draw(_ shapes: MouseArtworkShapes, ink: MouseArtworkInk, lit: MouseArtworkPart? = nil, unit: CGFloat) {
        if let views = shapes.views {
            let lit = lit.flatMap { shapes.lights($0) ? $0 : nil }
            return drawTwoViews(views, shapes: shapes, ink: ink, lit: lit, unit: unit)
        }
        // The plain mouse.
        let outline = shapes.outline()
        if ink.shadow {
            drawShadow(of: outline)
        }
        ink.bodyFill.setFill()
        outline.fill()

        if lit == .left || lit == .right, let area = shapes.shape(of: lit!) {
            ink.lit.setFill()
            area.fill()
        }

        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        let lines = shapes.seams()
        lines.lineWidth = ink.seamWidth / unit
        lines.lineCapStyle = .round
        ink.seam.setStroke()
        lines.stroke()
        NSGraphicsContext.restoreGraphicsState()

        drawWheel(shapes, ink: ink, lit: lit == .wheel, unit: unit)

        outline.lineWidth = ink.outlineWidth / unit
        ink.outline.setStroke()
        outline.stroke()

        for part in [MouseArtworkPart.forward, .back] {
            guard let button = shapes.shape(of: part) else { continue }
            drawPart(button, lit: lit == part, fill: ink.well, opaque: true, ink: ink, unit: unit, edge: ink.outline)
        }
    }

    /// `part` in the accent colour with a glow, as the cards light it over the drawing;
    /// on a lit button the parts in it stay as they are. Nothing when `part` does not
    /// light in the view `shapes` is of.
    static func drawHighlight(_ part: MouseArtworkPart, shapes: MouseArtworkShapes, unit: CGFloat) {
        guard shapes.lights(part), let shape = shapes.shape(of: part) else { return }
        if let views = shapes.views {
            return drawTwoViewsHighlight(part, of: views, shapes: shapes, unit: unit)
        }
        let accent = NSColor.controlAccentColor
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = accent.withAlphaComponent(0.65)
        glow.shadowBlurRadius = 6
        glow.shadowOffset = .zero
        glow.set()
        if part == .body {
            accent.setStroke()
            shape.lineWidth = 2 / unit
            shape.stroke()
        } else {
            accent.setFill()
            shape.fill()
        }
        NSGraphicsContext.restoreGraphicsState()

        let ink = MouseArtworkInk.card
        switch part {
        case .left, .right:
            drawWheel(shapes, ink: ink, lit: false, unit: unit)
        case .wheel:
            drawRidges(in: shapes.wheelRect, color: MouseArtworkPalette.litRidge, unit: unit)
        case .body, .modeShift, .thumbWheel, .back, .forward, .gesture, .thumbPanel:
            break
        }
    }

    /// A soft shadow under the mouse, cast by a copy of `outline` moved down and then
    /// covered by the body.
    static func drawShadow(of outline: NSBezierPath) {
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

    /// A small part: lit, or in `fill` (over the body's colour when `opaque`) with a fine edge.
    static func drawPart(
        _ shape: NSBezierPath, lit: Bool, fill: NSColor, opaque: Bool, ink: MouseArtworkInk, unit: CGFloat,
        edge: NSColor? = nil
    ) {
        if lit {
            ink.lit.setFill()
            shape.fill()
            // As large as the others, whose edge stands out round them.
            shape.lineWidth = ink.partEdgeWidth / unit
            ink.lit.setStroke()
            shape.stroke()
            return
        }
        if ink.fillsParts {
            if opaque {
                ink.bodyFill.setFill()
                shape.fill()
            }
            fill.setFill()
            shape.fill()
        }
        shape.lineWidth = ink.partEdgeWidth / unit
        (edge.map { ink.fillsParts ? $0 : ink.partEdge } ?? ink.partEdge).setStroke()
        shape.stroke()
    }

    /// The wheel in its slot.
    static func drawWheel(_ shapes: MouseArtworkShapes, ink: MouseArtworkInk, lit: Bool, unit: CGFloat) {
        if ink.drawsWell {
            let well = shapes.capsule(shapes.wellRect)
            if ink.fillsParts {
                ink.bodyFill.setFill()
                well.fill()
                ink.well.setFill()
                well.fill()
            }
            ink.partEdge.setStroke()
            well.lineWidth = ink.partEdgeWidth / unit
            well.stroke()
        }
        let wheel = shapes.capsule(shapes.wheelRect)
        if lit {
            ink.lit.setFill()
            wheel.fill()
        } else if ink.fillsParts {
            ink.wheel.setFill()
            wheel.fill()
        }
        if !lit && !ink.drawsWell {
            wheel.lineWidth = ink.partEdgeWidth / unit
            ink.partEdge.setStroke()
            wheel.stroke()
        }
        if ink.ridges {
            drawRidges(in: shapes.wheelRect, color: lit ? MouseArtworkPalette.litRidge : ink.wheelRidge, unit: unit)
        }
    }

    /// Ridges across the wheel, closer together towards its ends.
    static func drawRidges(in rect: NSRect, color: NSColor, unit: CGFloat) {
        let body = NSBezierPath(roundedRect: rect, xRadius: rect.width / 2, yRadius: rect.width / 2)
        NSGraphicsContext.saveGraphicsState()
        body.addClip()
        for step in -2...2 {
            let angle = Double(step) * Double.pi / 6
            let y = rect.midY + rect.height / 2 * CGFloat(sin(angle))
            let facing = CGFloat(cos(angle))
            let ridge = NSBezierPath()
            ridge.move(to: NSPoint(x: rect.minX + 2.5, y: y))
            ridge.line(to: NSPoint(x: rect.maxX - 2.5, y: y))
            ridge.lineWidth = 1 / unit
            ridge.lineCapStyle = .round
            color.withAlphaComponent(color.alphaComponent * facing).setStroke()
            ridge.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}

// MARK: - Turning between the views

/// How a drawing turns from one of its views to the other: the two cross-fade while each
/// is turned a little the way the mouse's front swings, from pointing up (seen from above)
/// to pointing left (seen from the thumb side). `progress` runs from 0, from above, to 1,
/// from the thumb side. Pure: the views that turn a drawing and their tests share it.
enum MouseArtworkTurn {

    /// A whole turn, in seconds.
    static let duration: TimeInterval = 0.25
    /// How far a view is turned when it has faded out (radians).
    static let angle: CGFloat = 16 * .pi / 180
    /// The view that leaves is gone after this share of the turn, and the one that comes
    /// shows from one minus it on: in between both show faintly.
    static let fadeShare: CGFloat = 0.7

    /// One view at one moment of a turn.
    struct Face: Equatable {
        var viewpoint: MouseArtworkViewpoint
        /// 0…1.
        var alpha: CGFloat
        /// Radians; positive turns the view clockwise in a flipped view.
        var rotation: CGFloat
    }

    /// The views that show at `progress`, with how strongly and how far turned: the one
    /// from above alone at 0, the one from the thumb side alone at 1.
    static func faces(at progress: CGFloat) -> [Face] {
        let p = min(1, max(0, progress))
        var faces: [Face] = []
        let above = 1 - smoothstep(p / fadeShare)
        if above > 0 {
            faces.append(Face(viewpoint: .above, alpha: above, rotation: -angle * p))
        }
        let side = smoothstep((p - (1 - fadeShare)) / fadeShare)
        if side > 0 {
            faces.append(Face(viewpoint: .thumbSide, alpha: side, rotation: angle * (1 - p)))
        }
        return faces
    }

    /// `viewpoint` at `progress`; nil while it does not show.
    static func face(of viewpoint: MouseArtworkViewpoint, at progress: CGFloat) -> Face? {
        return faces(at: progress).first { $0.viewpoint == viewpoint }
    }

    /// Where a view shows whole.
    static func progress(showing viewpoint: MouseArtworkViewpoint) -> CGFloat {
        return viewpoint == .thumbSide ? 1 : 0
    }

    /// Where a turn from `start` to `end` stands `elapsed` seconds after it began: eased,
    /// `duration` for the whole way and in proportion for the rest of an interrupted one.
    static func progress(from start: CGFloat, to end: CGFloat, elapsed: TimeInterval) -> CGFloat {
        let distance = abs(end - start)
        guard distance > 0, elapsed < duration * Double(distance) else { return end }
        let share = max(0, elapsed) / (duration * Double(distance))
        return start + (end - start) * smoothstep(CGFloat(share))
    }

    /// From the drawing's grid to where `face` is drawn: `placement` (the grid in the view),
    /// turned about the drawing's middle.
    static func transform(for face: Face, placement: AffineTransform) -> AffineTransform {
        // A view at rest is drawn through the placement itself, to the last bit.
        guard face.rotation != 0 else { return placement }
        let pivot = MouseArtworkShapes.centre
        var transform = placement
        transform.translate(x: pivot.x, y: pivot.y)
        transform.rotate(byRadians: face.rotation)
        transform.translate(x: -pivot.x, y: -pivot.y)
        return transform
    }

    /// Runs `body` with the current context set up for `face`: its grid placed, turned and
    /// faded (the whole of what `body` draws fades as one picture).
    static func draw(_ face: Face, placement: AffineTransform, _ body: () -> Void) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        NSGraphicsContext.saveGraphicsState()
        (transform(for: face, placement: placement) as NSAffineTransform).concat()
        if face.alpha < 1 {
            context.setAlpha(face.alpha)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        body()
        if face.alpha < 1 {
            context.endTransparencyLayer()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func smoothstep(_ value: CGFloat) -> CGFloat {
        let t = min(1, max(0, value))
        return t * t * (3 - 2 * t)
    }
}
