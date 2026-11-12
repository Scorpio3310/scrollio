//
//  MouseArtworkMaster4.swift
//  Scrollio
//  The MX Master 4's drawing: its two views on the grid of MouseArtwork.swift.
//
//  From above (front at the top, thumb side on the left): the two buttons with the wheel
//  between them, the small button behind the wheel on the palm shell with its light, the
//  thumb wheel at the left shoulder right behind the left button, and the thumb panel on
//  the wing. The three side buttons are under the body's overhang: they are not here.
//
//  From the thumb side (front to the left, the mouse on its base; wider than the grid,
//  inside MouseArtworkShapes.canvas): the thumb wheel on top, right under it Forward and
//  Back in one row, the gesture button in front of them and a little lower, and the thumb
//  panel beneath with its ring of dots.
//
//  Both views are the same mouse at the same size, 117 units long, so the drawing can turn
//  from one to the other in place. Where the parts are was measured on the mouse; the
//  lines are this app's own, and every point is a number below that can be moved. How the
//  shapes are painted is in MouseArtworkTwoViews.swift, shared with the MX Master 3.
//

import Cocoa

struct MouseArtworkMaster4: MouseArtworkTwoViews {

    typealias Bar = MouseArtworkBar

    let viewpoint: MouseArtworkViewpoint
    /// For the small pictures: the parts larger and further apart, not to scale; from the
    /// side the mouse is also drawn taller (`MouseArtworkBar.schematicRise`), to give them
    /// room.
    var schematic = false

    /// The thumb panel is the tinted area under the buttons; the two buttons have a clear
    /// rim along their edge.
    let restPart = MouseArtworkPart.thumbPanel
    let hasClearRim = true
    var restRidge: NSBezierPath? { return nil }

    // MARK: - Body

    /// The outline.
    /// From above: a wide, nearly flat front that slants back to the right (the left button
    /// reaches further forward), straight sides, a round back, and the thumb wing standing
    /// out low on the left, where its top edge leaves the left button's side.
    /// From the side: a low nose, the back of the buttons rising to the hump two thirds
    /// back, a steep fall to the tail, a flat base and the chin under the buttons.
    func outline() -> NSBezierPath {
        let path = NSBezierPath()
        switch viewpoint {
        case .above:
            path.move(to: p(26.8, 14.3))
            // The front left corner.
            path.curve(to: p(34.2, 2.4), controlPoint1: p(27.0, 8.5), controlPoint2: p(29.3, 3.6))
            // The left button's front edge, to the split.
            path.curve(to: p(52.5, 5.0), controlPoint1: p(40, 1.0), controlPoint2: p(47, 3.6))
            // The right button's front edge, falling back.
            path.curve(to: p(73.5, 12.5), controlPoint1: p(59, 6.6), controlPoint2: p(67.5, 9.4))
            // The front right corner.
            path.curve(to: p(80.2, 25.5), controlPoint1: p(77.6, 14.8), controlPoint2: p(79.6, 19.5))
            // The right side, widest low down.
            path.curve(to: p(84.3, 80), controlPoint1: p(81.2, 42), controlPoint2: p(83.2, 62))
            // The back.
            path.curve(to: p(79.5, 104), controlPoint1: p(84.7, 89), controlPoint2: p(83.2, 97.5))
            path.curve(to: p(61.4, 118), controlPoint1: p(76, 110.5), controlPoint2: p(69.5, 115.6))
            path.curve(to: p(45, 118), controlPoint1: p(56, 119.6), controlPoint2: p(50, 119.6))
            path.curve(to: p(24.3, 106.8), controlPoint1: p(38.5, 116), controlPoint2: p(30.5, 112))
            // Up the wing's lower edge to its outermost point.
            path.curve(to: p(6.4, 87.2), controlPoint1: p(18, 101.2), controlPoint2: p(10.5, 93.5))
            path.curve(to: p(6.8, 67.6), controlPoint1: p(2.8, 81.5), controlPoint2: p(3.2, 75))
            // The wing's front edge, and its top edge back to the left button's side.
            path.curve(to: p(15.6, 50.8), controlPoint1: p(9.0, 62.5), controlPoint2: p(11.5, 55))
            path.curve(to: p(25.7, 46.4), controlPoint1: p(18.5, 48.2), controlPoint2: p(22.5, 46.9))
            // The left button's side.
            path.curve(to: p(26.8, 14.3), controlPoint1: p(25.9, 36), controlPoint2: p(26.4, 24))
        case .thumbSide:
            // The nose, and the back of the buttons up to where they end.
            path.move(to: p(-13.6, 67.9))
            path.curve(to: p(37.3, 43.0), controlPoint1: p(2, 58.7), controlPoint2: p(20, 49.9))
            // Over the hump.
            path.curve(to: p(59.9, 36.65), controlPoint1: p(45, 39.8), controlPoint2: p(52.5, 36.65))
            path.curve(to: p(82.4, 48.1), controlPoint1: p(67.5, 36.65), controlPoint2: p(75.5, 42.2))
            // Down the palm to the tail.
            path.curve(to: p(102.2, 66.6), controlPoint1: p(89, 53.8), controlPoint2: p(96.5, 60.6))
            path.curve(to: p(101.2, 71.6), controlPoint1: p(103.3, 68.2), controlPoint2: p(102.8, 69.9))
            path.curve(to: p(91, 83.3), controlPoint1: p(98.8, 75.5), controlPoint2: p(95.5, 83.3))
            // The base.
            path.line(to: p(2.5, 83.3))
            // The chin, up to the nose.
            path.curve(to: p(-1.5, 82.0), controlPoint1: p(0.8, 83.3), controlPoint2: p(-0.6, 82.9))
            path.curve(to: p(-14.2, 70.6), controlPoint1: p(-6, 78.4), controlPoint2: p(-10.5, 74.3))
            path.curve(to: p(-13.6, 67.9), controlPoint1: p(-15.2, 69.7), controlPoint2: p(-15.0, 68.4))
        }
        path.close()
        return risen(path)
    }

    /// The body without the thumb wing, for centring the drawing (from the side: all of it).
    var mainBody: NSRect {
        switch viewpoint {
        case .above: return NSRect(x: 25.7, y: 2, width: 58.6, height: 117.2)
        case .thumbSide: return risen(NSBezierPath(rect: NSRect(x: -14.6, y: 36.65, width: 117.2, height: 46.65))).bounds
        }
    }

    /// `path` as the small pictures draw the view from the side: taller. Everything else
    /// is `path` itself.
    private func risen(_ path: NSBezierPath) -> NSBezierPath {
        return schematic && viewpoint == .thumbSide ? MouseArtworkBar.risen(path) : path
    }

    /// The fine lines inside the outline; the painter clips them to it.
    /// From above: where the two buttons end (the palm shell's front edge, which turns
    /// down at the shoulder behind the thumb wheel), the split between them, the left
    /// button's lower corner over the thumb wheel, and the body's edge over the wing.
    /// From the side: the buttons' lower edge from the nose to the thumb wheel, the front
    /// of the thumb area, and the line the body stands on its base with.
    func seams() -> NSBezierPath {
        let path = NSBezierPath()
        switch viewpoint {
        case .above:
            path.move(to: p(86, 41.3))
            path.curve(to: p(34.6, 48.2), controlPoint1: p(66, 43.4), controlPoint2: p(49, 45.4))
            path.curve(to: p(31.6, 52.2), controlPoint1: p(32.6, 48.6), controlPoint2: p(31.6, 49.8))
            path.line(to: p(31.6, 69))
            // The split.
            path.move(to: p(Self.split, -2))
            path.line(to: p(Self.split, 44.9))
            // The left button ends over the thumb wheel.
            path.move(to: p(25.7, 46.4))
            path.line(to: p(25.7, 52.3))
            path.line(to: p(31.6, 52.3))
            // The body's edge below the thumb panel.
            path.move(to: p(27.6, 100.4))
            path.curve(to: p(24.4, 107.4), controlPoint1: p(27.2, 103), controlPoint2: p(26, 105.6))
        case .thumbSide:
            // Under the buttons.
            path.move(to: p(-14, 70.5))
            path.curve(to: p(36.4, 52.9), controlPoint1: p(3, 64.8), controlPoint2: p(20, 59))
            // The front of the thumb area, then along the base to the tail.
            path.move(to: p(23.3, 58.4))
            path.curve(to: p(35.9, 77.1), controlPoint1: p(21.6, 63.5), controlPoint2: p(27.5, 73.2))
            path.curve(to: p(68.3, 75.6), controlPoint1: p(46, 78.2), controlPoint2: p(58, 76.6))
            path.curve(to: p(103, 68), controlPoint1: p(79, 74.6), controlPoint2: p(93, 72.2))
        }
        return risen(path)
    }

    // MARK: - From above: the buttons and the wheel

    /// The split between the two buttons, and the middle of the wheel.
    static let split: CGFloat = 52.6

    /// The left (or right) button: the outline in front of the palm shell, on its side of
    /// the split. The left one ends over the thumb wheel.
    func buttonArea(left: Bool) -> NSBezierPath? {
        guard viewpoint == .above else { return nil }
        let front = NSBezierPath()
        front.move(to: p(-4, -4))
        front.line(to: p(92, -4))
        front.line(to: p(92, 41.3))
        front.line(to: p(86, 41.3))
        front.curve(to: p(34.6, 48.2), controlPoint1: p(66, 43.4), controlPoint2: p(49, 45.4))
        front.curve(to: p(31.6, 52.2), controlPoint1: p(32.6, 48.6), controlPoint2: p(31.6, 49.8))
        front.line(to: p(31.6, 52.3))
        front.line(to: p(25.7, 52.3))
        front.line(to: p(25.7, 46.4))
        front.line(to: p(-4, 46.4))
        front.close()
        let side = NSBezierPath(rect: left
            ? NSRect(x: -4, y: -4, width: Self.split + 4, height: 80)
            : NSRect(x: Self.split, y: -4, width: 96 - Self.split, height: 80))
        return NSBezierPath(cgPath: outline().cgPath.intersection(front.cgPath).intersection(side.cgPath))
    }

    var wheelRect: NSRect {
        let rect = NSRect(x: Self.split - 3.8, y: 20.2, width: 7.6, height: 17)
        return schematic ? grown(rect, width: 1.7, height: 1.25) : rect
    }

    /// The slot the wheel turns in.
    var wellRect: NSRect {
        return wheelRect.insetBy(dx: -2.1, dy: -2.3)
    }

    /// The small button behind the wheel, on the palm shell.
    private var modeShiftRect: NSRect {
        let rect = NSRect(x: Self.split - 2.8, y: 47.8, width: 5.6, height: 7.8)
        return schematic ? grown(rect, width: 2, height: 1.5) : rect
    }

    /// The light behind that button (from above; too fine for the small pictures).
    var light: NSBezierPath? {
        guard viewpoint == .above, !schematic else { return nil }
        return NSBezierPath(ovalIn: NSRect(x: Self.split - 0.8, y: 58.6, width: 1.6, height: 1.6))
    }

    // MARK: - The thumb wheel

    /// The thumb wheel: a ribbed roller in two halves.
    /// From above it lies along the shoulder, right behind the left button; from the side
    /// it is the large roller on top, along the back of the body.
    var thumbWheel: Bar {
        switch (viewpoint, schematic) {
        case (.above, false):
            return Bar(centre: p(28.5, 61.3), length: 17, thickness: 5.8, degrees: 90, startRadius: 1.3, endRadius: 1.3)
        case (.above, true):
            return Bar(centre: p(27.8, 62.5), length: 20, thickness: 8, degrees: 90, startRadius: 2, endRadius: 2)
        case (.thumbSide, false):
            return Bar(centre: p(45.9, 45.5), length: 18.6, thickness: 8.1, degrees: -18.2, startRadius: 1.4, endRadius: 1.4)
        case (.thumbSide, true):
            return Bar(centre: p(45.9, 41.6), length: 25, thickness: 12, degrees: -23, startRadius: 2.6, endRadius: 2.6)
        }
    }

    /// What holds the thumb wheel, drawn under it. From above: the pointed end behind the
    /// roller. From the side: the slot it turns in, with its round cap at the hump.
    var thumbWheelHousing: NSBezierPath? {
        guard !schematic else { return nil }
        switch viewpoint {
        case .above:
            let path = NSBezierPath()
            path.move(to: p(25.6, 68))
            path.line(to: p(31.4, 68))
            path.curve(to: p(30.1, 78.6), controlPoint1: p(31.6, 72.5), controlPoint2: p(31.3, 76.5))
            path.curve(to: p(25.6, 68), controlPoint1: p(27.8, 77), controlPoint2: p(25.5, 72.5))
            path.close()
            return path
        case .thumbSide:
            let wheel = thumbWheel
            // From a little in front of the roller to the cap behind it.
            let start = wheel.point(along: -wheel.length / 2 - 0.9, across: 0)
            let end = wheel.point(along: wheel.length / 2 + 7.8, across: 0)
            let thickness = wheel.thickness + 1.5
            return Bar(
                centre: NSPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2),
                length: hypot(end.x - start.x, end.y - start.y), thickness: thickness, degrees: wheel.degrees,
                startRadius: 1.8, endRadius: thickness / 2
            ).path
        }
    }

    // MARK: - The side buttons (from the thumb side)

    /// Forward and Back are one bar cut in two, right under the thumb wheel; the gesture
    /// button is a pill of its own in front of them and a little lower.
    private func sideButton(_ part: MouseArtworkPart) -> Bar? {
        guard viewpoint == .thumbSide else { return nil }
        switch (part, schematic) {
        case (.gesture, false):
            return Bar(centre: p(31.4, 60.5), length: 11.4, thickness: 4.2, degrees: -20, startRadius: 2.1, endRadius: 2.1)
        case (.forward, false):
            return Bar(centre: p(43.6, 55.9), length: 10.4, thickness: 3.9, degrees: -18.8, startRadius: 1.95, endRadius: 0.9)
        case (.back, false):
            return Bar(centre: p(54.0, 52.25), length: 10.4, thickness: 3.9, degrees: -18.8, startRadius: 0.9, endRadius: 1.95)
        case (.gesture, true):
            return Bar(centre: p(26.5, 65.0), length: 14.5, thickness: 9, degrees: -23, startRadius: 4.5, endRadius: 4.5)
        case (.forward, true):
            return Bar(centre: p(45.5, 57.0), length: 14.5, thickness: 9, degrees: -23, startRadius: 4.5, endRadius: 4.5)
        case (.back, true):
            return Bar(centre: p(64.0, 49.4), length: 14.5, thickness: 9, degrees: -23, startRadius: 4.5, endRadius: 4.5)
        default:
            return nil
        }
    }

    // MARK: - The thumb panel

    /// The thumb rest that clicks and pulses.
    /// From above: on the wing, inside its rim, under the thumb wheel and the body's edge.
    /// From the side: the large panel beneath the buttons.
    private func thumbPanel() -> NSBezierPath {
        let path = NSBezierPath()
        switch viewpoint {
        case .above:
            path.move(to: p(16.2, 56.8))
            path.curve(to: p(19.0, 53.8), controlPoint1: p(16.8, 55.2), controlPoint2: p(17.6, 54.2))
            path.line(to: p(25.7, 52.5))
            // Under the thumb wheel and its pointed end.
            path.line(to: p(25.7, 69))
            path.curve(to: p(28.6, 82), controlPoint1: p(26, 74), controlPoint2: p(28.2, 78))
            // Along the body's edge to the panel's rear corner.
            path.curve(to: p(28.6, 97.5), controlPoint1: p(29.2, 87), controlPoint2: p(29.4, 93))
            path.curve(to: p(25.4, 100.2), controlPoint1: p(28.2, 100), controlPoint2: p(27, 101.2))
            // Back along the wing's rim.
            path.curve(to: p(9.9, 83.0), controlPoint1: p(19.5, 95.5), controlPoint2: p(13, 88.5))
            path.curve(to: p(9.0, 75.0), controlPoint1: p(8.6, 80.5), controlPoint2: p(8.2, 78))
            path.line(to: p(16.2, 56.8))
        case .thumbSide:
            path.move(to: p(32.6, 67.2))
            path.curve(to: p(35.4, 63.3), controlPoint1: p(32.0, 65.2), controlPoint2: p(33.2, 64.0))
            // The top edge, rising under the buttons.
            path.curve(to: p(62.0, 53.2), controlPoint1: p(44.3, 59.8), controlPoint2: p(54, 55.9))
            path.curve(to: p(72.6, 57.3), controlPoint1: p(66, 51.7), controlPoint2: p(69.5, 54.2))
            // Down the rear edge.
            path.curve(to: p(84.4, 66.3), controlPoint1: p(76.5, 60.3), controlPoint2: p(81, 63.6))
            path.curve(to: p(82.0, 71.0), controlPoint1: p(86.4, 67.9), controlPoint2: p(85.2, 69.8))
            // The lower edge, back to the front.
            path.curve(to: p(40.5, 75.3), controlPoint1: p(74, 74.8), controlPoint2: p(54, 75.6))
            path.curve(to: p(32.6, 67.2), controlPoint1: p(36.2, 75.2), controlPoint2: p(33.6, 71.5))
        }
        path.close()
        guard schematic, viewpoint == .thumbSide else { return path }
        // The small pictures' buttons are larger and need the room: the panel is lower
        // (its lower edge as far above the base as on the card, its upper edge under them).
        path.transform(using: AffineTransform(m11: 1, m12: 0, m21: 0, m22: 0.8, tX: 0, tY: 21.8))
        return path
    }

    /// The ring of dots at the front of the thumb panel (from the side; too fine for the
    /// small pictures).
    var panelDots: NSBezierPath? {
        guard viewpoint == .thumbSide, !schematic else { return nil }
        let centre = p(42.6, 68.9)
        let path = NSBezierPath()
        for index in 0..<8 {
            let angle = CGFloat(index) * .pi / 4 + .pi / 8
            let dot = NSPoint(x: centre.x + 1.95 * cos(angle), y: centre.y + 1.95 * sin(angle))
            path.appendOval(in: NSRect(x: dot.x - 0.42, y: dot.y - 0.42, width: 0.84, height: 0.84))
        }
        return path
    }

    /// The wheel as it shows over the buttons from the side: the top of a disc, the rest of
    /// it behind the body.
    var wheelCrest: NSBezierPath? {
        guard viewpoint == .thumbSide else { return nil }
        return risen(NSBezierPath(ovalIn: NSRect(x: 13.5 - 8.6, y: 60 - 8.6, width: 17.2, height: 17.2)))
    }

    // MARK: - Parts

    /// The shape of `part` in this view; nil when it does not show from here.
    func shape(of part: MouseArtworkPart) -> NSBezierPath? {
        switch part {
        case .body:
            return outline()
        case .left:
            return buttonArea(left: true)
        case .right:
            return buttonArea(left: false)
        case .wheel:
            guard viewpoint == .above else { return nil }
            return capsule(wheelRect)
        case .modeShift:
            guard viewpoint == .above else { return nil }
            let rect = modeShiftRect
            let radius = min(rect.width, rect.height) * 0.3
            return NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        case .thumbWheel:
            return thumbWheel.path
        case .back, .forward, .gesture:
            return sideButton(part)?.path
        case .thumbPanel:
            return thumbPanel()
        }
    }

    /// Where the badge of a button the drawing cannot show sits: on the right edge, low
    /// (the badge shows with the view from above).
    var badgeCentre: NSPoint {
        return p(78.5, 97)
    }

    // MARK: - Helpers

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
}
