//
//  MouseArtworkMaster3.swift
//  Scrollio
//  The drawing of the MX Master 3, 3S and 3 for Mac: its two views on the grid of
//  MouseArtwork.swift.
//
//  From above (front at the top, thumb side on the left): the two buttons with the wheel
//  in its long slot between them, the small button behind the wheel on the palm shell, the
//  thumb wheel in its slot along the left shoulder, and the full thumb wing. The two side
//  buttons are under the body's overhang: they are not here.
//
//  From the thumb side (front to the left, the mouse on its base; wider than the grid,
//  inside MouseArtworkShapes.canvas): the thumb wheel on top, Forward and Back in a row
//  right under it, and the thumb rest beneath. This mouse has no gesture button of its
//  own: the front of the thumb rest is pressed down, and that pad, with a short ridge, is
//  what lights for it. It has no thumb panel.
//
//  Both views are the same mouse at the same size, 117 units long. Where the parts are was
//  measured on the mouse; the lines are this app's own, and every point is a number below
//  that can be moved. How the shapes are painted is in MouseArtworkTwoViews.swift.
//

import Cocoa

struct MouseArtworkMaster3: MouseArtworkTwoViews {

    typealias Bar = MouseArtworkBar

    let viewpoint: MouseArtworkViewpoint
    /// For the small pictures: the parts larger and further apart, not to scale; from the
    /// side the mouse is also drawn taller (`MouseArtworkBar.schematicRise`).
    var schematic = false

    /// The gesture pad is the tinted area of the thumb rest. No clear rim, no light and no
    /// ring of dots on this mouse.
    let restPart = MouseArtworkPart.gesture
    let hasClearRim = false
    var panelDots: NSBezierPath? { return nil }
    var light: NSBezierPath? { return nil }

    // MARK: - Body

    /// The outline.
    /// From above: a rounded front that slants back to the right, straight sides, a round
    /// back, and the thumb wing: it leaves the left button's side early and swells into a
    /// full lobe that runs into the back.
    /// From the side: a low nose, the back of the buttons rising to the hump two thirds
    /// back, a steep fall to the tail, a flat base and the chin under the buttons.
    func outline() -> NSBezierPath {
        let path = NSBezierPath()
        switch viewpoint {
        case .above:
            path.move(to: p(26.8, 16))
            // The front left corner.
            path.curve(to: p(37.0, 2.4), controlPoint1: p(27.0, 8.6), controlPoint2: p(30.2, 3.6))
            // The front edge, falling back to the right.
            path.curve(to: p(58.1, 4.9), controlPoint1: p(44, 1.0), controlPoint2: p(51.5, 3.0))
            path.curve(to: p(72.2, 9.4), controlPoint1: p(63, 6.2), controlPoint2: p(68, 7.6))
            // The front right corner.
            path.curve(to: p(79.6, 23), controlPoint1: p(76.6, 11.4), controlPoint2: p(79.0, 16.2))
            // The right side, widest low down.
            path.curve(to: p(83.5, 80), controlPoint1: p(80.1, 42), controlPoint2: p(81.6, 62))
            // The back.
            path.curve(to: p(79.7, 102.7), controlPoint1: p(84.0, 89), controlPoint2: p(82.8, 96.5))
            path.curve(to: p(64.6, 116.8), controlPoint1: p(76.6, 109), controlPoint2: p(71, 113.8))
            path.curve(to: p(40.4, 116.8), controlPoint1: p(58, 120), controlPoint2: p(47, 120))
            path.curve(to: p(16.4, 102.7), controlPoint1: p(33, 113.2), controlPoint2: p(23.5, 108.6))
            // Round the wing's lobe to its outermost point, and up its front.
            path.curve(to: p(4.45, 83.5), controlPoint1: p(10.5, 98), controlPoint2: p(4.6, 91.5))
            path.curve(to: p(8.1, 57.1), controlPoint1: p(4.3, 75), controlPoint2: p(6.0, 64))
            path.curve(to: p(18.6, 46.5), controlPoint1: p(9.4, 52.5), controlPoint2: p(13.5, 49.6))
            // The wing's top edge, into the notch at the left button's side.
            path.curve(to: p(26.5, 37.2), controlPoint1: p(22.6, 44.2), controlPoint2: p(23.4, 38.6))
            // The left button's side.
            path.curve(to: p(26.8, 16), controlPoint1: p(26.4, 31), controlPoint2: p(26.6, 23))
        case .thumbSide:
            // The nose, and the back of the buttons up to where they end.
            path.move(to: p(-12.6, 67.9))
            path.curve(to: p(33.6, 42.1), controlPoint1: p(1.5, 58.2), controlPoint2: p(18, 48.0))
            // Over the hump.
            path.curve(to: p(58.1, 35.97), controlPoint1: p(42, 38.7), controlPoint2: p(50.5, 35.97))
            path.curve(to: p(82.6, 48.6), controlPoint1: p(66, 35.97), controlPoint2: p(75, 42.6))
            // Down the palm to the tail.
            path.curve(to: p(102.3, 66.6), controlPoint1: p(89.5, 54.4), controlPoint2: p(97, 61.2))
            path.curve(to: p(101.4, 71.4), controlPoint1: p(103.4, 68.2), controlPoint2: p(102.9, 69.8))
            path.curve(to: p(89.5, 84.0), controlPoint1: p(98, 75.8), controlPoint2: p(93.5, 84.0))
            // The base.
            path.line(to: p(2.6, 84.0))
            // The chin, up to the nose.
            path.curve(to: p(-1.2, 82.4), controlPoint1: p(0.9, 84.0), controlPoint2: p(-0.3, 83.4))
            path.curve(to: p(-14.1, 71.2), controlPoint1: p(-6, 78.6), controlPoint2: p(-10.6, 74.6))
            path.curve(to: p(-12.6, 67.9), controlPoint1: p(-15.2, 70.2), controlPoint2: p(-14.6, 68.6))
        }
        path.close()
        return risen(path)
    }

    /// The body without the thumb wing, for centring the drawing (from the side: all of it).
    var mainBody: NSRect {
        switch viewpoint {
        case .above: return NSRect(x: 26.5, y: 2, width: 57, height: 117.2)
        case .thumbSide: return risen(NSBezierPath(rect: NSRect(x: -14.6, y: 35.97, width: 117.2, height: 48.05))).bounds
        }
    }

    /// `path` as the small pictures draw the view from the side: taller. Everything else
    /// is `path` itself.
    private func risen(_ path: NSBezierPath) -> NSBezierPath {
        return schematic && viewpoint == .thumbSide ? MouseArtworkBar.risen(path) : path
    }

    /// The fine lines inside the outline; the painter clips them to it.
    /// From above: where each button ends (two lines that run from the sides up into the
    /// wheel's slot), the split in front of the slot, the left button's side over the thumb
    /// wheel's slot, and the body's edge over the wing behind that slot.
    /// From the side: the buttons' lower edge from the nose to the thumb wheel, and the
    /// thumb rest: its front, and its lower edge along the base to the tail.
    func seams() -> NSBezierPath {
        let path = NSBezierPath()
        switch viewpoint {
        case .above:
            // The left button's end, and the right one's.
            path.move(to: p(27.0, 49.8))
            path.curve(to: p(50, 41), controlPoint1: p(33.5, 48.6), controlPoint2: p(44.5, 46.6))
            path.move(to: p(56.2, 41))
            path.curve(to: p(86, 53.4), controlPoint1: p(60.5, 46.2), controlPoint2: p(73, 50.8))
            // The split.
            path.move(to: p(Self.split, -2))
            path.line(to: p(Self.split, 18))
            // The left button's side, over the thumb wheel's slot.
            path.move(to: p(26.5, 37.2))
            path.line(to: p(27.0, 49.8))
            // The body's edge over the wing.
            path.move(to: p(26.4, 85))
            path.curve(to: p(29.6, 96), controlPoint1: p(26.6, 89), controlPoint2: p(27.6, 93))
        case .thumbSide:
            // Under the buttons.
            path.move(to: p(-14, 71.1))
            path.curve(to: p(34.2, 48.4), controlPoint1: p(2, 63.8), controlPoint2: p(19, 55.2))
            // The thumb rest: from under the thumb wheel round its front, then along its
            // lower edge to the tail.
            path.move(to: p(37.8, 57.3))
            path.curve(to: p(24.1, 65), controlPoint1: p(33, 58.8), controlPoint2: p(27, 61.5))
            path.curve(to: p(24.4, 72.7), controlPoint1: p(22.4, 67.2), controlPoint2: p(22.6, 70.4))
            path.curve(to: p(34.6, 78.2), controlPoint1: p(26.2, 75.2), controlPoint2: p(30, 77.6))
            path.curve(to: p(73.5, 76.2), controlPoint1: p(48, 78.6), controlPoint2: p(62, 77.4))
            path.curve(to: p(103, 70), controlPoint1: p(84, 75.2), controlPoint2: p(95, 73))
        }
        return risen(path)
    }

    // MARK: - From above: the buttons and the wheel

    /// The split between the two buttons, and the middle of the wheel.
    static let split: CGFloat = 53.1

    /// The left (or right) button: the outline in front of where the buttons end, on its
    /// side of the split (the wheel's slot lies over both).
    func buttonArea(left: Bool) -> NSBezierPath? {
        guard viewpoint == .above else { return nil }
        let front = NSBezierPath()
        front.move(to: p(-4, -4))
        front.line(to: p(92, -4))
        front.line(to: p(92, 53.4))
        front.line(to: p(86, 53.4))
        front.curve(to: p(56.2, 41), controlPoint1: p(73, 50.8), controlPoint2: p(60.5, 46.2))
        front.line(to: p(50, 41))
        front.curve(to: p(27.0, 49.8), controlPoint1: p(44.5, 46.6), controlPoint2: p(33.5, 48.6))
        front.line(to: p(26.5, 37.2))
        front.line(to: p(-4, 37.2))
        front.close()
        let side = NSBezierPath(rect: left
            ? NSRect(x: -4, y: -4, width: Self.split + 4, height: 80)
            : NSRect(x: Self.split, y: -4, width: 96 - Self.split, height: 80))
        return NSBezierPath(cgPath: outline().cgPath.intersection(front.cgPath).intersection(side.cgPath))
    }

    var wheelRect: NSRect {
        let rect = NSRect(x: Self.split - 3.8, y: 18.2, width: 7.6, height: 16.8)
        return schematic ? grown(rect, width: 1.7, height: 1.25) : rect
    }

    /// The slot the wheel turns in: long, it reaches back to where the buttons end.
    var wellRect: NSRect {
        let wheel = wheelRect
        return NSRect(x: wheel.minX - 2.8, y: wheel.minY - 3.6, width: wheel.width + 5.6, height: wheel.height + 10.4)
    }

    /// The small button behind the wheel, on the palm shell.
    private var modeShiftRect: NSRect {
        let rect = NSRect(x: Self.split - 2.6, y: 44.0, width: 5.2, height: 7.0)
        return schematic ? grown(rect, width: 2, height: 1.5) : rect
    }

    // MARK: - The thumb wheel

    /// The thumb wheel: a ribbed roller in two halves.
    /// From above it lies in its slot along the left shoulder, half under the body's edge;
    /// from the side it is the large roller on top.
    var thumbWheel: Bar {
        switch (viewpoint, schematic) {
        case (.above, false):
            return Bar(centre: p(24.9, 59.0), length: 16, thickness: 4.6, degrees: 90, startRadius: 1.2, endRadius: 1.2)
        case (.above, true):
            return Bar(centre: p(24.3, 60), length: 19, thickness: 7.5, degrees: 90, startRadius: 1.8, endRadius: 1.8)
        case (.thumbSide, false):
            return Bar(centre: p(43.4, 49.6), length: 16.8, thickness: 9.1, degrees: -21.1, startRadius: 1.4, endRadius: 1.4)
        case (.thumbSide, true):
            return Bar(centre: p(43.4, 46.3), length: 23, thickness: 12, degrees: -26, startRadius: 2.6, endRadius: 2.6)
        }
    }

    /// The slot that holds the thumb wheel, drawn under it. From above: long and narrow
    /// along the shoulder, from the notch of the wing to a point behind the roller. From
    /// the side: from just in front of the roller to its round cap at the hump.
    var thumbWheelHousing: NSBezierPath? {
        guard !schematic else { return nil }
        switch viewpoint {
        case .above:
            let path = NSBezierPath()
            path.move(to: p(22.6, 68))
            path.line(to: p(22.6, 44.5))
            path.curve(to: p(24.9, 41.2), controlPoint1: p(22.6, 42.6), controlPoint2: p(23.6, 41.2))
            path.curve(to: p(27.2, 44.5), controlPoint1: p(26.2, 41.2), controlPoint2: p(27.2, 42.6))
            path.line(to: p(27.2, 70))
            path.curve(to: p(26.4, 85.6), controlPoint1: p(27.5, 76), controlPoint2: p(27.3, 82.5))
            path.curve(to: p(22.6, 68), controlPoint1: p(24.4, 82), controlPoint2: p(22.6, 75))
            path.close()
            return path
        case .thumbSide:
            let wheel = thumbWheel
            let start = wheel.point(along: -wheel.length / 2 - 0.9, across: 0)
            let end = wheel.point(along: wheel.length / 2 + 13.7, across: 0)
            let thickness = wheel.thickness + 1.5
            return Bar(
                centre: NSPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2),
                length: hypot(end.x - start.x, end.y - start.y), thickness: thickness, degrees: wheel.degrees,
                startRadius: 1.8, endRadius: thickness / 2
            ).path
        }
    }

    // MARK: - The side buttons (from the thumb side)

    /// Forward (in front) and Back: two pills in a row right under the thumb wheel.
    private func sideButton(_ part: MouseArtworkPart) -> Bar? {
        guard viewpoint == .thumbSide else { return nil }
        switch (part, schematic) {
        case (.forward, false):
            return Bar(centre: p(40.4, 60.4), length: 12, thickness: 3.8, degrees: -19.5, startRadius: 1.9, endRadius: 1.9)
        case (.back, false):
            return Bar(centre: p(53.0, 55.8), length: 11.6, thickness: 3.8, degrees: -18.9, startRadius: 1.9, endRadius: 1.9)
        case (.forward, true):
            return Bar(centre: p(38.5, 62.5), length: 14.5, thickness: 9, degrees: -23, startRadius: 4.5, endRadius: 4.5)
        case (.back, true):
            return Bar(centre: p(57.5, 54.5), length: 14.5, thickness: 9, degrees: -23, startRadius: 4.5, endRadius: 4.5)
        default:
            return nil
        }
    }

    // MARK: - The gesture button

    /// The gesture button: the front of the thumb rest, pressed down with the thumb. It
    /// shows from the thumb side only, as a pad under Forward, inside the rest's edge.
    private func gesturePad() -> NSBezierPath? {
        guard viewpoint == .thumbSide else { return nil }
        let path = NSBezierPath()
        path.move(to: p(27.2, 64.6))
        // Its upper edge, under the Forward button.
        path.curve(to: p(47.0, 62.0), controlPoint1: p(33.5, 66.6), controlPoint2: p(41, 64.4))
        // Its rear edge.
        path.curve(to: p(51.0, 70), controlPoint1: p(50.2, 62.6), controlPoint2: p(51.6, 66))
        path.curve(to: p(47.5, 76.6), controlPoint1: p(50.8, 73.6), controlPoint2: p(49.8, 76.3))
        // Along the rest's lower edge, and up round its front.
        path.line(to: p(34.8, 76.8))
        path.curve(to: p(25.7, 71.8), controlPoint1: p(30.4, 76.3), controlPoint2: p(27.2, 74.4))
        path.curve(to: p(27.2, 64.6), controlPoint1: p(24.4, 69.4), controlPoint2: p(24.6, 66.2))
        path.close()
        guard schematic else { return path }
        // The small pictures' buttons are larger and need the room: the pad is lower.
        path.transform(using: AffineTransform(translationByX: 0, byY: 6.5))
        return path
    }

    /// The short ridge on the thumb rest that marks its gesture button (from the side; too
    /// fine for the small pictures).
    var restRidge: NSBezierPath? {
        guard viewpoint == .thumbSide, !schematic else { return nil }
        let path = NSBezierPath()
        path.move(to: p(31.5, 70.4))
        path.curve(to: p(40.5, 70.6), controlPoint1: p(34.5, 71.6), controlPoint2: p(37.5, 71.6))
        return path
    }

    /// The wheel as it shows over the buttons from the side: the top of a disc, the rest of
    /// it behind the body.
    var wheelCrest: NSBezierPath? {
        guard viewpoint == .thumbSide else { return nil }
        return risen(NSBezierPath(ovalIn: NSRect(x: 10.2 - 8, y: 57.6 - 8, width: 16, height: 16)))
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
        case .back, .forward:
            return sideButton(part)?.path
        case .gesture:
            return gesturePad()
        case .thumbPanel:
            return nil
        }
    }

    /// Where the badge of a button the drawing cannot show sits: on the right edge, low
    /// (the badge shows with the view from above).
    var badgeCentre: NSPoint {
        return p(78, 97)
    }

    // MARK: - Helpers

    private func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        return NSPoint(x: x, y: y)
    }

    private func grown(_ rect: NSRect, width: CGFloat, height: CGFloat) -> NSRect {
        return rect.insetBy(dx: -rect.width * (width - 1) / 2, dy: -rect.height * (height - 1) / 2)
    }

    private func capsule(_ rect: NSRect) -> NSBezierPath {
        let radius = min(rect.width, rect.height) / 2
        return NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    }
}
