//
//  MouseArtworkTwoViews.swift
//  Scrollio
//  A mouse drawn in two views (MouseArtworkViewpoint): what such a drawing gives its
//  painter, the bar its rollers and side buttons are made of, and the painter, which draws
//  either view in the ink, strokes and fills of the other drawings. The MX Master 4's and
//  the MX Master 3's shapes are in MouseArtworkMaster4.swift and MouseArtworkMaster3.swift:
//  both views of a mouse on the grid of MouseArtwork.swift, the same mouse at the same
//  size (117 units long), so the drawing can turn from one to the other in place.
//
//  From above (front at the top, thumb side on the left) such a drawing has the two
//  buttons, the wheel and the button behind it, and the thumb wheel at the shoulder; what
//  the thumb works is under the body's overhang. From the thumb side (front to the left,
//  the mouse on its base, wider than the grid: MouseArtworkShapes.canvas) it has the thumb
//  wheel on top, the side buttons under it and the thumb rest beneath.
//

import Cocoa

/// One view of a drawing in two views.
protocol MouseArtworkTwoViews {
    var viewpoint: MouseArtworkViewpoint { get }
    /// For the small pictures: the parts larger and further apart, not to scale.
    var schematic: Bool { get }

    func outline() -> NSBezierPath
    /// The body without the thumb wing, for centring the drawing.
    var mainBody: NSRect { get }
    /// The fine lines inside the outline; the painter clips them to it.
    func seams() -> NSBezierPath
    /// The left (or right) button, from above; nil from the side.
    func buttonArea(left: Bool) -> NSBezierPath?
    var wheelRect: NSRect { get }
    /// The slot the wheel turns in.
    var wellRect: NSRect { get }
    /// The thumb wheel, a ribbed roller in two halves; nil on a mouse without one.
    var roller: MouseArtworkBar? { get }
    /// What holds the thumb wheel, drawn under it.
    var thumbWheelHousing: NSBezierPath? { get }
    /// The wheel as it shows over the buttons from the side.
    var wheelCrest: NSBezierPath? { get }
    /// The shape of `part` in this view; nil when it does not show from here.
    func shape(of part: MouseArtworkPart) -> NSBezierPath?
    /// Where the badge of a button the drawing cannot show sits.
    var badgeCentre: NSPoint { get }

    /// The part that is the tinted area of the thumb rest, drawn under everything else:
    /// the MX Master 4's thumb panel, the MX Master 3's gesture pad. A mouse without one
    /// names a part it does not have (it has no shape, so nothing is drawn).
    var restPart: MouseArtworkPart { get }
    /// A tinted area of the body that is no part and never lights, drawn inside the
    /// outline: the MX Vertical's top plate, the MX Anywhere's side grips. nil: none.
    var trim: NSBezierPath? { get }
    /// Marks on that area: a ring of dots (filled), a short ridge (a line).
    var panelDots: NSBezierPath? { get }
    var restRidge: NSBezierPath? { get }
    /// The light behind the button behind the wheel, where the mouse has one.
    var light: NSBezierPath? { get }
    /// The two buttons have a clear rim along their edge (the MX Master 4).
    var hasClearRim: Bool { get }
}

extension MouseArtworkTwoViews {
    var trim: NSBezierPath? { return nil }
}

// The MX Masters have a thumb wheel: it is their roller.
extension MouseArtworkMaster4 {
    var roller: MouseArtworkBar? { return thumbWheel }
}

extension MouseArtworkMaster3 {
    var roller: MouseArtworkBar? { return thumbWheel }
}

/// A roller (the thumb wheel) or a button, as a bar along an axis: `length` along it,
/// `thickness` across, turned by `degrees` (0: the axis runs left to right; negative: its
/// right end is higher; 90: it runs down).
struct MouseArtworkBar {
    var centre: NSPoint
    var length: CGFloat
    var thickness: CGFloat
    var degrees: CGFloat
    /// Corner radius at the end the axis starts at (the mouse's front in the side
    /// view) and at its other end.
    var startRadius: CGFloat
    var endRadius: CGFloat

    /// The axis' direction, and the direction across it.
    var along: NSPoint {
        let angle = degrees * .pi / 180
        return NSPoint(x: cos(angle), y: sin(angle))
    }

    var across: NSPoint {
        let angle = degrees * .pi / 180
        return NSPoint(x: -sin(angle), y: cos(angle))
    }

    /// A point `a` along the axis and `b` across it, from the centre.
    func point(along a: CGFloat, across b: CGFloat) -> NSPoint {
        return NSPoint(x: centre.x + along.x * a + across.x * b, y: centre.y + along.y * a + across.y * b)
    }

    var path: NSBezierPath {
        let l = length / 2, t = thickness / 2
        let rs = max(0.01, min(startRadius, t, l)), re = max(0.01, min(endRadius, t, l))
        let path = NSBezierPath()
        path.move(to: NSPoint(x: -l + rs, y: -t))
        path.line(to: NSPoint(x: l - re, y: -t))
        path.appendArc(from: NSPoint(x: l, y: -t), to: NSPoint(x: l, y: -t + re), radius: re)
        path.line(to: NSPoint(x: l, y: t - re))
        path.appendArc(from: NSPoint(x: l, y: t), to: NSPoint(x: l - re, y: t), radius: re)
        path.line(to: NSPoint(x: -l + rs, y: t))
        path.appendArc(from: NSPoint(x: -l, y: t), to: NSPoint(x: -l, y: t - rs), radius: rs)
        path.line(to: NSPoint(x: -l, y: -t + rs))
        path.appendArc(from: NSPoint(x: -l, y: -t), to: NSPoint(x: -l + rs, y: -t), radius: rs)
        path.close()
        path.transform(using: AffineTransform(
            m11: along.x, m12: along.y, m21: across.x, m22: across.y, tX: centre.x, tY: centre.y
        ))
        return path
    }

    // MARK: The small pictures' view from the side

    /// How many times taller than it is the small pictures draw a mouse from the side, to
    /// give its parts room.
    static let schematicRise: CGFloat = 1.3

    /// `path` drawn that much taller, about the middle of the mouse's height.
    static func risen(_ path: NSBezierPath) -> NSBezierPath {
        let middle: CGFloat = 60
        path.transform(using: AffineTransform(
            m11: 1, m12: 0, m21: 0, m22: schematicRise, tX: 0, tY: middle * (1 - schematicRise)
        ))
        return path
    }
}

// MARK: - Painting

extension MouseArtworkPainter {

    /// One view of a drawing in two views, `lit` (a part that lights in this view) in the
    /// ink's lit colour.
    static func drawTwoViews(
        _ art: MouseArtworkTwoViews, shapes: MouseArtworkShapes, ink: MouseArtworkInk, lit: MouseArtworkPart?, unit: CGFloat
    ) {
        let outline = art.outline()
        if ink.shadow {
            drawShadow(of: outline)
        }
        // From the side the wheel shows over the buttons; the body covers the rest of it.
        if let crest = art.wheelCrest {
            NSGraphicsContext.saveGraphicsState()
            let outside = NSBezierPath(rect: MouseArtworkShapes.canvas.insetBy(dx: -20, dy: -20))
            outside.append(outline)
            outside.windingRule = .evenOdd
            outside.addClip()
            if ink.fillsParts {
                ink.bodyFill.setFill()
                crest.fill()
                ink.wheel.setFill()
                crest.fill()
            }
            crest.lineWidth = ink.partEdgeWidth / unit
            ink.outline.setStroke()
            crest.stroke()
            NSGraphicsContext.restoreGraphicsState()
        }
        ink.bodyFill.setFill()
        outline.fill()

        // A tinted area that is no part (the MX Vertical's top plate, the MX Anywhere's
        // side grips): it ends at the body's edge.
        if let trim = art.trim {
            NSGraphicsContext.saveGraphicsState()
            outline.addClip()
            drawPart(trim, lit: false, fill: ink.panel, opaque: false, ink: ink, unit: unit)
            NSGraphicsContext.restoreGraphicsState()
        }

        // The thumb rest's part (the MX Master 4's thumb panel, the MX Master 3's gesture
        // pad), under everything else, with its marks.
        let rest = art.restPart
        if let panel = art.shape(of: rest) {
            drawPart(panel, lit: lit == rest, fill: ink.panel, opaque: false, ink: ink, unit: unit)
            if ink.ridges, let dots = art.panelDots {
                (lit == rest ? MouseArtworkPalette.litRidge : ink.outline).setFill()
                dots.fill()
            }
            if let ridge = art.restRidge {
                ridge.lineWidth = 1.3 * ink.seamWidth / unit
                ridge.lineCapStyle = .round
                (lit == rest ? MouseArtworkPalette.litRidge : ink.outline).setStroke()
                ridge.stroke()
            }
        }
        // The MX Master 4's two buttons have a clear rim along their edge.
        if ink.fillsParts && art.hasClearRim {
            let rim = outline.copy() as! NSBezierPath
            rim.lineWidth = 2 * MouseArtworkShapes.rimWidth
            for left in [true, false] {
                guard let area = art.buttonArea(left: left) else { continue }
                NSGraphicsContext.saveGraphicsState()
                area.addClip()
                ink.panel.setStroke()
                rim.stroke()
                NSGraphicsContext.restoreGraphicsState()
            }
        }
        if lit == .left || lit == .right, let area = art.shape(of: lit!) {
            ink.lit.setFill()
            area.fill()
        }

        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        let lines = art.seams()
        lines.lineWidth = ink.seamWidth / unit
        lines.lineCapStyle = .round
        lines.lineJoinStyle = .round
        ink.seam.setStroke()
        lines.stroke()
        // The thumb wheel's slot ends at the body's edge.
        if art.viewpoint == .thumbSide, let housing = art.thumbWheelHousing {
            drawPart(housing, lit: false, fill: ink.well, opaque: true, ink: ink, unit: unit)
        }
        NSGraphicsContext.restoreGraphicsState()

        if art.viewpoint == .above {
            drawWheel(shapes, ink: ink, lit: lit == .wheel, unit: unit)
            if let modeShift = art.shape(of: .modeShift) {
                drawPart(modeShift, lit: lit == .modeShift, fill: ink.well, opaque: true, ink: ink, unit: unit)
            }
            if ink.ridges, let light = art.light {
                ink.seam.setFill()
                light.fill()
            }
        }
        // The button on the MX Vertical's top plate shows in both views.
        if let top = art.shape(of: .pointerSpeed) {
            drawPart(top, lit: lit == .pointerSpeed, fill: ink.well, opaque: true, ink: ink, unit: unit)
        }

        outline.lineWidth = ink.outlineWidth / unit
        ink.outline.setStroke()
        outline.stroke()

        if art.viewpoint == .above, let housing = art.thumbWheelHousing {
            drawPart(housing, lit: false, fill: ink.well, opaque: true, ink: ink, unit: unit)
        }
        if let roller = art.roller {
            drawRoller(roller, ink: ink, lit: lit == .thumbWheel, unit: unit)
        }
        for part in [MouseArtworkPart.gesture, .forward, .back] {
            guard let button = art.shape(of: part) else { continue }
            drawPart(button, lit: lit == part, fill: ink.well, opaque: true, ink: ink, unit: unit, edge: ink.outline)
        }
    }

    /// `part` in the accent colour with a glow, as the cards light it over the drawing.
    static func drawTwoViewsHighlight(
        _ part: MouseArtworkPart, of art: MouseArtworkTwoViews, shapes: MouseArtworkShapes, unit: CGFloat
    ) {
        guard let shape = art.shape(of: part) else { return }
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
            // The parts in a lit button stay as they are.
            drawWheel(shapes, ink: ink, lit: false, unit: unit)
            if let modeShift = art.shape(of: .modeShift) {
                drawPart(modeShift, lit: false, fill: ink.well, opaque: true, ink: ink, unit: unit)
            }
            // A light inside the wheel's slot (the MX Anywhere's) was covered with the slot.
            if let light = art.light, art.wellRect.contains(light.bounds) {
                ink.seam.setFill()
                light.fill()
            }
        case .wheel:
            drawRidges(in: art.wheelRect, color: MouseArtworkPalette.litRidge, unit: unit)
        case .thumbWheel:
            if let roller = art.roller {
                drawRollerRidges(roller, color: MouseArtworkPalette.litRidge, unit: unit)
            }
        case art.restPart:
            if let dots = art.panelDots {
                MouseArtworkPalette.litRidge.setFill()
                dots.fill()
            }
            if let ridge = art.restRidge {
                ridge.lineWidth = 1.3 / unit
                ridge.lineCapStyle = .round
                MouseArtworkPalette.litRidge.setStroke()
                ridge.stroke()
            }
        case .body, .modeShift, .back, .forward, .gesture, .thumbPanel, .pointerSpeed:
            break
        }
    }

    /// The thumb wheel: a roller in two ribbed halves.
    private static func drawRoller(_ roller: MouseArtworkBar, ink: MouseArtworkInk, lit: Bool, unit: CGFloat) {
        let shape = roller.path
        if lit {
            ink.lit.setFill()
            shape.fill()
        } else if ink.fillsParts {
            ink.bodyFill.setFill()
            shape.fill()
            ink.wheel.setFill()
            shape.fill()
        }
        if ink.ridges {
            drawRollerRidges(roller, color: lit ? MouseArtworkPalette.litRidge : ink.wheelRidge, unit: unit)
        }
        shape.lineWidth = ink.partEdgeWidth / unit
        (lit ? ink.lit : ink.outline).setStroke()
        shape.stroke()
    }

    /// The roller's ribs, which run along it (closer together towards its edges, where it
    /// curves away), and the ring between its two halves.
    private static func drawRollerRidges(_ roller: MouseArtworkBar, color: NSColor, unit: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        roller.path.addClip()
        let half = roller.length / 2, ring: CGFloat = 0.9
        let count = roller.thickness > 7 ? 3 : 1
        for step in -count...count {
            let angle = Double(step) * Double.pi / Double(2 * count + 2)
            let across = roller.thickness / 2 * CGFloat(sin(angle))
            let rib = NSBezierPath()
            for side in [CGFloat(-1), 1] {
                rib.move(to: roller.point(along: side * (ring + 0.9), across: across))
                rib.line(to: roller.point(along: side * (half - 1), across: across))
            }
            rib.lineWidth = 0.9 / unit
            rib.lineCapStyle = .round
            color.withAlphaComponent(color.alphaComponent * CGFloat(cos(angle))).setStroke()
            rib.stroke()
        }
        let band = NSBezierPath()
        for side in [CGFloat(-1), 1] {
            band.move(to: roller.point(along: side * ring, across: -roller.thickness / 2))
            band.line(to: roller.point(along: side * ring, across: roller.thickness / 2))
        }
        band.lineWidth = 0.9 / unit
        color.setStroke()
        band.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
}
