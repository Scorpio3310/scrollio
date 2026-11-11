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
//  An illustration, not a product render: no logo, no brand marks.
//

import Cocoa

// MARK: - Which mouse

/// Which drawing the panes show.
enum MouseArtworkModel: CaseIterable {
    /// Logitech MX Master 4: three side buttons (gesture, forward, back) under the thumb
    /// wheel, and the thumb rest that clicks and pulses (the haptic sense panel).
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

/// The shapes of one model's drawing on the design grid (`grid`, top-left origin, the front
/// at the top, the thumb side on the left). A painter scales them to the size it draws at.
struct MouseArtworkShapes {

    /// Every drawing fits this grid; the MX Master fills it, the plain mouse is narrower.
    static let grid = NSSize(width: 88, height: 120)
    /// The clear rim along the MX Master 4's buttons.
    static let rimWidth: CGFloat = 3.5

    let model: MouseArtworkModel
    /// For the rows' small pictures: the side buttons, the thumb wheel and the button
    /// behind the wheel larger and further apart (not to scale), so front, middle and rear
    /// can be told apart at 20 points.
    var schematic = false

    init(model: MouseArtworkModel, schematic: Bool = false) {
        self.model = model
        self.schematic = schematic
    }

    private var isMaster: Bool {
        return model != .generic
    }

    // MARK: Body

    /// The outline. The MX Master: narrow at the front (the left button reaching a little
    /// further forward than the right), the right side one long curve, the thumb wing
    /// flaring out low on the left. The plain mouse: symmetric, rounder at the back.
    func outline() -> NSBezierPath {
        let path = NSBezierPath()
        if isMaster {
            path.move(to: p(38, 2.5))
            path.curve(to: p(62.5, 6.5), controlPoint1: p(46, 1), controlPoint2: p(56, 2.5))
            path.curve(to: p(74.5, 17), controlPoint1: p(68.5, 9), controlPoint2: p(72.5, 12.5))
            path.curve(to: p(86, 66), controlPoint1: p(79.5, 30), controlPoint2: p(85, 48))
            path.curve(to: p(81.5, 101), controlPoint1: p(86.8, 82), controlPoint2: p(86, 93))
            path.curve(to: p(58, 119), controlPoint1: p(76.5, 110.5), controlPoint2: p(68, 119))
            path.curve(to: p(30, 112.5), controlPoint1: p(47, 119), controlPoint2: p(37, 117))
            path.curve(to: p(4, 89), controlPoint1: p(19, 106), controlPoint2: p(6.5, 99))
            path.curve(to: p(1.5, 68), controlPoint1: p(2, 81), controlPoint2: p(0.8, 74))
            path.curve(to: p(11, 47.5), controlPoint1: p(2.2, 60), controlPoint2: p(6, 52))
            path.curve(to: p(19.5, 36), controlPoint1: p(15.5, 44), controlPoint2: p(18.5, 40.5))
            path.curve(to: p(38, 2.5), controlPoint1: p(21, 22), controlPoint2: p(27, 4))
        } else {
            path.move(to: p(44, 2))
            path.curve(to: p(74, 34), controlPoint1: p(61, 2), controlPoint2: p(72, 15))
            path.curve(to: p(77, 84), controlPoint1: p(76, 50), controlPoint2: p(78, 68))
            path.curve(to: p(44, 119), controlPoint1: p(76, 106), controlPoint2: p(62, 119))
            path.curve(to: p(11, 84), controlPoint1: p(26, 119), controlPoint2: p(12, 106))
            path.curve(to: p(14, 34), controlPoint1: p(10, 68), controlPoint2: p(12, 50))
            path.curve(to: p(44, 2), controlPoint1: p(16, 15), controlPoint2: p(27, 2))
        }
        path.close()
        return path
    }

    /// The body without the thumb wing, for centring the drawing.
    var mainBody: NSRect {
        return isMaster ? NSRect(x: 18, y: 2, width: 69, height: 117) : NSRect(x: 10.5, y: 2, width: 67, height: 117)
    }

    /// Where the two buttons end (a curve across the body) and the split between them; the
    /// painter clips them to the outline.
    func seams() -> NSBezierPath {
        let path = NSBezierPath()
        if isMaster {
            path.move(to: p(18.8, 49.5))
            path.curve(to: p(90, 46), controlPoint1: p(36, 62), controlPoint2: p(64, 62))
            path.move(to: p(50, -2))
            path.line(to: p(50.5, 58))
        } else {
            path.move(to: p(6, 47))
            path.curve(to: p(82, 47), controlPoint1: p(28, 57), controlPoint2: p(60, 57))
            path.move(to: p(44, -2))
            path.line(to: p(44, 53))
        }
        return path
    }

    /// The line where the thumb rest meets the side of the body, behind the side buttons
    /// (MX Master).
    func shoulder() -> NSBezierPath? {
        guard isMaster else { return nil }
        let path = NSBezierPath()
        path.move(to: p(18.6, 41))
        path.curve(to: p(21.2, 82), controlPoint1: p(18.2, 55), controlPoint2: p(18.8, 70))
        path.curve(to: p(33.5, 110.8), controlPoint1: p(23, 95), controlPoint2: p(28, 105))
        return path
    }

    /// The left (or right) button: the body in front of where the buttons end, on its side
    /// of the split.
    func buttonArea(left: Bool) -> NSBezierPath {
        let front = NSBezierPath()
        let split: CGFloat = isMaster ? 50.25 : 44
        if isMaster {
            // Bounded on the left by the side of the body, where the thumb rest begins.
            front.move(to: p(-4, 40.5))
            front.line(to: p(18.6, 40.5))
            front.line(to: p(18.8, 49.5))
            front.curve(to: p(90, 46), controlPoint1: p(36, 62), controlPoint2: p(64, 62))
            front.line(to: p(92, 46))
        } else {
            front.move(to: p(-4, 47))
            front.line(to: p(6, 47))
            front.curve(to: p(82, 47), controlPoint1: p(28, 57), controlPoint2: p(60, 57))
            front.line(to: p(92, 47))
        }
        front.line(to: p(92, -4))
        front.line(to: p(-4, -4))
        front.close()
        let side = NSBezierPath(rect: left
            ? NSRect(x: -4, y: -4, width: split + 4, height: 80)
            : NSRect(x: split, y: -4, width: 96 - split, height: 80))
        var area = outline().cgPath.intersection(front.cgPath).intersection(side.cgPath)
        // The thumb wheel at its edge is not part of the button.
        if let roller = shape(of: .thumbWheel) {
            area = area.subtracting(roller.cgPath)
        }
        return NSBezierPath(cgPath: area)
    }

    // MARK: Wheel

    var wheelRect: NSRect {
        let rect = isMaster ? NSRect(x: 45.5, y: 10, width: 9.5, height: 25) : NSRect(x: 39.5, y: 11, width: 9, height: 24)
        return schematic ? grown(rect, width: 1.5, height: 1) : rect
    }

    /// The slot the wheel turns in.
    var wellRect: NSRect {
        return wheelRect.insetBy(dx: -3, dy: -3)
    }

    // MARK: Parts

    /// The shape of `part` in this drawing; nil when this mouse does not have it.
    func shape(of part: MouseArtworkPart) -> NSBezierPath? {
        guard model.has(part) else { return nil }
        switch part {
        case .body:
            return outline()
        case .left:
            return buttonArea(left: true)
        case .right:
            return buttonArea(left: false)
        case .wheel:
            return capsule(wheelRect)
        case .modeShift:
            var rect = NSRect(x: 47.25, y: 40.5, width: 6, height: 7)
            if schematic { rect = grown(rect, width: 2, height: 1.6) }
            let radius = min(rect.width, rect.height) * 0.35
            return NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        case .thumbWheel:
            let axis = thumbWheelAxis
            return capsule(from: axis.start, to: axis.end, width: axis.width)
        case .back, .forward:
            return sideButton(part)
        case .gesture:
            return model == .mxMaster4 ? sideButton(part) : gesturePad()
        case .thumbPanel:
            return thumbRest()
        }
    }

    /// The side buttons, front to back, on the side of the body under the thumb wheel (the
    /// MX Master) or on the left edge (the plain mouse).
    private func sideButton(_ part: MouseArtworkPart) -> NSBezierPath? {
        typealias Button = (from: NSPoint, to: NSPoint, width: CGFloat)
        let buttons: [MouseArtworkPart: Button]
        switch (model, schematic) {
        case (.mxMaster4, false):
            buttons = [
                .gesture: (p(19.5, 46.5), p(19.3, 49.5), 5.4),
                .forward: (p(19.2, 56.3), p(19.3, 63.3), 5.6),
                .back: (p(19.5, 70.2), p(20.3, 77.2), 5.6),
            ]
        case (.mxMaster4, true):
            buttons = [
                .gesture: (p(16.8, 45.5), p(16.4, 48), 10),
                .forward: (p(16, 61.5), p(15.8, 66.5), 10),
                .back: (p(16, 80), p(16.8, 85), 10),
            ]
        case (.mxMaster3, false):
            buttons = [
                .forward: (p(19.4, 47.6), p(19.2, 57.0), 5.6),
                .back: (p(19.3, 64.0), p(20.0, 73.5), 5.6),
            ]
        case (.mxMaster3, true):
            buttons = [
                .forward: (p(16.6, 48.5), p(16.2, 55.5), 10),
                .back: (p(16, 68.5), p(16.4, 75.5), 10),
            ]
        case (.generic, false):
            buttons = [
                .forward: (p(12.7, 45), p(12.1, 54.5), 5.6),
                .back: (p(11.6, 61.5), p(11.3, 71), 5.6),
            ]
        case (.generic, true):
            buttons = [
                .forward: (p(11.8, 42), p(11.2, 49), 10),
                .back: (p(10.4, 62), p(10.4, 69), 10),
            ]
        }
        guard let button = buttons[part] else { return nil }
        return capsule(from: button.from, to: button.to, width: button.width)
    }

    /// The thumb rest of the MX Master: the wing between the outline and the shoulder line,
    /// behind the side buttons. On the MX Master 4 it is the haptic panel.
    private func thumbRest() -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: p(18.6, 45))
        path.curve(to: p(21.2, 82), controlPoint1: p(18.2, 57), controlPoint2: p(18.8, 70))
        path.curve(to: p(32, 109), controlPoint1: p(23, 94), controlPoint2: p(27.5, 104))
        path.curve(to: p(6.5, 88.5), controlPoint1: p(21, 105.5), controlPoint2: p(8.5, 97.5))
        path.curve(to: p(4.2, 68.5), controlPoint1: p(4.6, 81), controlPoint2: p(3.7, 74))
        path.curve(to: p(11.8, 51), controlPoint1: p(4.8, 61.5), controlPoint2: p(7.8, 55))
        path.curve(to: p(18.6, 45), controlPoint1: p(14.2, 48.5), controlPoint2: p(16.6, 46))
        path.close()
        return path
    }

    /// The gesture button of the MX Master 3: the front of the thumb rest, pressed down with
    /// the thumb.
    private func gesturePad() -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: p(18.5, 49))
        path.curve(to: p(18.9, 70), controlPoint1: p(18.2, 56), controlPoint2: p(18.4, 63))
        path.curve(to: p(4.8, 73), controlPoint1: p(14, 73.5), controlPoint2: p(8, 74.5))
        path.curve(to: p(7.4, 57.5), controlPoint1: p(4.2, 67), controlPoint2: p(5, 61.5))
        path.curve(to: p(18.5, 49), controlPoint1: p(10, 53), controlPoint2: p(14.5, 49.5))
        path.close()
        return path
    }

    /// The short ridge at the front of the MX Master 3's thumb rest that marks its gesture
    /// button.
    func gestureRidge() -> NSBezierPath? {
        guard model == .mxMaster3 else { return nil }
        let path = NSBezierPath()
        path.move(to: p(8.4, 58.5))
        path.curve(to: p(16, 53.5), controlPoint1: p(10.5, 55.8), controlPoint2: p(13.2, 54.2))
        return path
    }

    /// Where the badge of a button the drawing cannot show sits: on the right edge, low.
    var badgeCentre: NSPoint {
        return isMaster ? p(80, 96) : p(72, 98)
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
    static func draw(_ shapes: MouseArtworkShapes, ink: MouseArtworkInk, lit: MouseArtworkPart? = nil, unit: CGFloat) {
        let outline = shapes.outline()
        if ink.shadow {
            drawShadow(of: outline)
        }
        ink.bodyFill.setFill()
        outline.fill()

        // The thumb rest, under everything else on it.
        if shapes.model == .mxMaster4, let rest = shapes.shape(of: .thumbPanel) {
            drawPart(rest, lit: lit == .thumbPanel, fill: ink.panel, opaque: false, ink: ink, unit: unit)
        } else if shapes.model == .mxMaster3, let pad = shapes.shape(of: .gesture) {
            drawPart(pad, lit: lit == .gesture, fill: ink.panel, opaque: false, ink: ink, unit: unit)
        }
        // The MX Master 4's buttons have a clear rim along their edge.
        if shapes.model == .mxMaster4 && ink.fillsParts {
            let rim = outline.copy() as! NSBezierPath
            rim.lineWidth = 2 * MouseArtworkShapes.rimWidth
            for left in [true, false] {
                NSGraphicsContext.saveGraphicsState()
                shapes.buttonArea(left: left).addClip()
                ink.panel.setStroke()
                rim.stroke()
                NSGraphicsContext.restoreGraphicsState()
            }
        }
        if lit == .left || lit == .right, let area = shapes.shape(of: lit!) {
            ink.lit.setFill()
            area.fill()
        }

        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        let lines = shapes.seams()
        if let shoulder = shapes.shoulder() {
            lines.append(shoulder)
        }
        lines.lineWidth = ink.seamWidth / unit
        lines.lineCapStyle = .round
        ink.seam.setStroke()
        lines.stroke()
        if let ridge = shapes.gestureRidge() {
            ridge.lineWidth = 1.3 * ink.seamWidth / unit
            ridge.lineCapStyle = .round
            (lit == .gesture ? MouseArtworkPalette.litRidge : ink.outline).setStroke()
            ridge.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()

        drawWheel(shapes, ink: ink, lit: lit == .wheel, unit: unit)
        if let modeShift = shapes.shape(of: .modeShift) {
            drawPart(modeShift, lit: lit == .modeShift, fill: ink.well, opaque: true, ink: ink, unit: unit)
        }

        outline.lineWidth = ink.outlineWidth / unit
        ink.outline.setStroke()
        outline.stroke()

        if let roller = shapes.shape(of: .thumbWheel) {
            drawRoller(roller, along: shapes, ink: ink, lit: lit == .thumbWheel, unit: unit)
        }
        for part in [MouseArtworkPart.gesture, .forward, .back] where !(shapes.model == .mxMaster3 && part == .gesture) {
            guard let button = shapes.shape(of: part) else { continue }
            drawPart(button, lit: lit == part, fill: ink.well, opaque: true, ink: ink, unit: unit, edge: ink.outline)
        }
    }

    /// `part` in the accent colour with a glow, as the cards light it over the drawing;
    /// on a lit button the parts in it stay as they are.
    static func drawHighlight(_ part: MouseArtworkPart, shapes: MouseArtworkShapes, unit: CGFloat) {
        guard let shape = shapes.shape(of: part) else { return }
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
            if let modeShift = shapes.shape(of: .modeShift) {
                drawPart(modeShift, lit: false, fill: ink.well, opaque: true, ink: ink, unit: unit)
            }
        case .wheel:
            drawRidges(in: shapes.wheelRect, color: MouseArtworkPalette.litRidge, unit: unit)
        case .thumbWheel:
            drawRidges(along: shape, shapes: shapes, color: MouseArtworkPalette.litRidge, unit: unit)
        case .thumbPanel:
            drawSideButtons(on: shapes, ink: ink, unit: unit)
        case .gesture:
            // The MX Master 3's: the pad in the thumb rest, under the side buttons' edge.
            if let ridge = shapes.gestureRidge() {
                ridge.lineWidth = 1.3 / unit
                ridge.lineCapStyle = .round
                MouseArtworkPalette.litRidge.setStroke()
                ridge.stroke()
                drawSideButtons(on: shapes, ink: ink, unit: unit)
            }
        case .body, .modeShift, .back, .forward:
            break
        }
    }

    /// The side buttons, unlit, over a lit thumb rest whose edge they sit on.
    static func drawSideButtons(on shapes: MouseArtworkShapes, ink: MouseArtworkInk, unit: CGFloat) {
        for button in [MouseArtworkPart.forward, .back] + (shapes.model == .mxMaster4 ? [.gesture] : []) {
            guard let path = shapes.shape(of: button) else { continue }
            drawPart(path, lit: false, fill: ink.well, opaque: true, ink: ink, unit: unit, edge: ink.outline)
        }
    }

    /// A soft shadow under the mouse, cast by a copy of `outline` moved down and then
    /// covered by the body.
    private static func drawShadow(of outline: NSBezierPath) {
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
    private static func drawPart(
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
    private static func drawWheel(_ shapes: MouseArtworkShapes, ink: MouseArtworkInk, lit: Bool, unit: CGFloat) {
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

    /// The thumb wheel: a ribbed roller along the side.
    private static func drawRoller(_ shape: NSBezierPath, along shapes: MouseArtworkShapes, ink: MouseArtworkInk, lit: Bool, unit: CGFloat) {
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
            drawRidges(along: shape, shapes: shapes, color: lit ? MouseArtworkPalette.litRidge : ink.wheelRidge, unit: unit)
        }
        if !lit {
            shape.lineWidth = ink.partEdgeWidth / unit
            ink.outline.setStroke()
            shape.stroke()
        }
    }

    /// Ridges across the wheel, closer together towards its ends.
    private static func drawRidges(in rect: NSRect, color: NSColor, unit: CGFloat) {
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

    /// Ridges across the thumb wheel (a capsule along the side), closer towards its ends.
    private static func drawRidges(along shape: NSBezierPath, shapes: MouseArtworkShapes, color: NSColor, unit: CGFloat) {
        // The roller's axis: the capsule drawn upright, then turned like the shape.
        let bounds = shape.bounds
        let centre = NSPoint(x: bounds.midX, y: bounds.midY)
        let (start, end, width) = shapes.thumbWheelAxis
        let dx = end.x - start.x, dy = end.y - start.y
        let length = (dx * dx + dy * dy).squareRoot() + width
        let angle = atan2(dy, dx)
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        for step in -3...3 {
            let a = Double(step) * Double.pi / 8
            let along = length / 2 * CGFloat(sin(a))
            let facing = CGFloat(cos(a))
            let mid = NSPoint(x: centre.x + along * cos(angle), y: centre.y + along * sin(angle))
            let half = width / 2 - 1.2
            let ridge = NSBezierPath()
            ridge.move(to: NSPoint(x: mid.x - half * -sin(angle), y: mid.y - half * cos(angle)))
            ridge.line(to: NSPoint(x: mid.x + half * -sin(angle), y: mid.y + half * cos(angle)))
            ridge.lineWidth = 0.9 / unit
            ridge.lineCapStyle = .round
            color.withAlphaComponent(color.alphaComponent * facing).setStroke()
            ridge.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}

extension MouseArtworkShapes {
    /// The thumb wheel's axis: the centres of its round ends, and its width.
    var thumbWheelAxis: (start: NSPoint, end: NSPoint, width: CGFloat) {
        return schematic
            ? (NSPoint(x: 24, y: 15.5), NSPoint(x: 20.5, y: 32), 9)
            : (NSPoint(x: 22.6, y: 21.5), NSPoint(x: 19.6, y: 37.5), 6.5)
    }
}
