//
//  MouseArtworkVertical.swift
//  Scrollio
//  The drawing of the MX Vertical: its two views on the grid of MouseArtwork.swift.
//
//  The MX Vertical stands upright: the hand holds it as in a handshake. Its two buttons
//  and the wheel are on the outer face, which leans away from the thumb; Back and Forward
//  are under the thumb on the inner face; and a plate runs along its top, with a button at
//  its rear end that switches the pointer speed.
//
//  From above (front at the top, thumb side on the left): the plate with its button, and
//  right of it the outer face, seen at a slant: the left button beside the plate, the right
//  button beyond it, the wheel on the split between them. Everything a finger works shows
//  here. Under and behind them the base spreads out, widest on the thumb side.
//
//  From the thumb side (front to the left, the mouse on its base; wider than the grid,
//  inside MouseArtworkShapes.canvas): the upright silhouette, a tall front and a long fall
//  to the tail, the plate along the top (its button shows here too, seen at a slant, and
//  lights from above), and Forward and Back as the two halves of one key under the plate.
//  The wheel and the two buttons are on the far face: they are not here.
//
//  Both views are the same mouse at the same size, 114 units long. Where the parts are was
//  measured on a model of the mouse; the lines are this app's own, and every point is a
//  number below that can be moved. How the shapes are painted is in
//  MouseArtworkTwoViews.swift.
//

import Cocoa

struct MouseArtworkVertical: MouseArtworkTwoViews {

    typealias Bar = MouseArtworkBar

    let viewpoint: MouseArtworkViewpoint
    /// For the small pictures: the parts larger and further apart, not to scale. (From the
    /// side this mouse is tall enough as it is: it is not drawn taller.)
    var schematic = false

    /// No thumb wheel and nothing that holds one; no thumb rest that is a part (the thumb
    /// panel is a part this mouse does not have); no clear rim, no marks, no light.
    var roller: Bar? { return nil }
    var thumbWheelHousing: NSBezierPath? { return nil }
    let restPart = MouseArtworkPart.thumbPanel
    let hasClearRim = false
    var panelDots: NSBezierPath? { return nil }
    var restRidge: NSBezierPath? { return nil }
    var light: NSBezierPath? { return nil }
    /// The wheel is on the far face from the thumb side.
    var wheelCrest: NSBezierPath? { return nil }

    // MARK: - Body

    /// The outline.
    /// From above: the plate's round front end at the front left, a short front edge, the
    /// outer face's side swelling to the right, a round back, and on the left the base
    /// running out wide under the thumb and back in to the plate.
    /// From the side: a tall, nearly upright front, the top rising a little to the peak
    /// behind the middle, a long straight fall to the tail, and the flat base.
    func outline() -> NSBezierPath {
        let path = NSBezierPath()
        switch viewpoint {
        case .above:
            // The front edge, from the plate's front end.
            path.move(to: p(36.8, 3.2))
            path.curve(to: p(60, 3.6), controlPoint1: p(44, 4.4), controlPoint2: p(53, 3.0))
            // The front right corner and the outer side.
            path.curve(to: p(75.7, 17.6), controlPoint1: p(66, 4.4), controlPoint2: p(71.8, 10))
            path.curve(to: p(84.2, 52), controlPoint1: p(80.2, 26), controlPoint2: p(84.2, 39))
            path.curve(to: p(75.3, 93), controlPoint1: p(84.2, 66), controlPoint2: p(81.5, 81))
            // The back.
            path.curve(to: p(41, 117), controlPoint1: p(68.5, 106), controlPoint2: p(56, 117))
            path.curve(to: p(9.5, 93), controlPoint1: p(27, 117), controlPoint2: p(15.5, 106))
            // The base under the thumb: out to its widest point, then in to the plate.
            path.curve(to: p(4.0, 72), controlPoint1: p(6.6, 86.5), controlPoint2: p(4.0, 79.5))
            path.curve(to: p(15.1, 39), controlPoint1: p(4.0, 61), controlPoint2: p(8.5, 49.5))
            path.curve(to: p(30.2, 16), controlPoint1: p(20, 31.5), controlPoint2: p(28.5, 24))
            // Up beside the plate and round its front end.
            path.line(to: p(31.2, 8.5))
            path.curve(to: p(36.8, 3.2), controlPoint1: p(31.3, 5.6), controlPoint2: p(33.6, 3.3))
        case .thumbSide:
            // The top front corner, and the top up to the peak.
            path.move(to: p(-12.6, 40))
            path.curve(to: p(-6, 33.2), controlPoint1: p(-12.6, 36), controlPoint2: p(-10, 33.9))
            path.curve(to: p(47, 21.6), controlPoint1: p(12, 28.8), controlPoint2: p(30, 24.8))
            path.curve(to: p(59.5, 25.4), controlPoint1: p(52.5, 20.4), controlPoint2: p(56.5, 21.6))
            // The long fall to the tail.
            path.line(to: p(98.5, 79.5))
            path.curve(to: p(100.6, 85), controlPoint1: p(100.3, 82), controlPoint2: p(101.4, 83.3))
            path.curve(to: p(88, 99.1), controlPoint1: p(99, 90), controlPoint2: p(95, 99.1))
            // The base.
            path.line(to: p(-5, 99.1))
            // Up the front, which draws in a little at the waist.
            path.curve(to: p(-12.9, 84), controlPoint1: p(-10, 99.1), controlPoint2: p(-13.2, 92))
            path.curve(to: p(-11.4, 62), controlPoint1: p(-12.6, 77), controlPoint2: p(-11.4, 70))
            path.curve(to: p(-12.6, 40), controlPoint1: p(-11.4, 54), controlPoint2: p(-12.6, 47))
        }
        path.close()
        return path
    }

    /// The whole body, for centring the drawing (this mouse has no thumb wing).
    var mainBody: NSRect {
        switch viewpoint {
        case .above: return NSRect(x: 4, y: 3, width: 80.2, height: 114)
        case .thumbSide: return NSRect(x: -13, y: 21, width: 114, height: 78.1)
        }
    }

    /// The fine lines inside the outline; the painter clips them to it.
    /// From above: the split between the two buttons, the right button's outer edge, and
    /// where the buttons end (a line that runs back a little towards the right); and the
    /// edge of the base where it shows behind the thumb.
    /// From the side: the upper edge of the base, and the edge of the inner face where it
    /// meets the back.
    func seams() -> NSBezierPath {
        let path = NSBezierPath()
        switch viewpoint {
        case .above:
            // The split.
            path.move(to: p(Self.split, -2))
            path.line(to: Self.splitEnd)
            // The right button's edge, its rear corner, and where the buttons end.
            path.move(to: p(68.8, 7.2))
            path.curve(to: p(77.2, 31), controlPoint1: p(73.2, 12.5), controlPoint2: p(77.2, 21))
            path.line(to: p(77.2, 51.5))
            path.curve(to: Self.rightCorner, controlPoint1: p(77.2, 54.2), controlPoint2: p(76, 56.2))
            path.line(to: buttonsEndAtPlate)
            // The base behind the thumb.
            path.move(to: p(10.5, 95))
            path.curve(to: p(33, 88), controlPoint1: p(17, 92.5), controlPoint2: p(26, 89.5))
        case .thumbSide:
            // The base.
            path.move(to: p(-12.9, 83.8))
            path.curve(to: p(45, 76.2), controlPoint1: p(5, 80.5), controlPoint2: p(25, 76.6))
            path.curve(to: p(100.8, 83), controlPoint1: p(65, 75.8), controlPoint2: p(88, 79.5))
            // The inner face's rear edge.
            path.move(to: p(55.4, 28.4))
            path.curve(to: p(80.9, 78), controlPoint1: p(59, 40), controlPoint2: p(71.5, 63))
        }
        return path
    }

    // MARK: - The plate along the top

    /// The plate from above: a long bar with round ends, its rear end a little further
    /// right than its front.
    private var plate: Bar {
        return Bar(centre: p(39.2, 38.6), length: 70.4, thickness: 13.2, degrees: 88.7, startRadius: 6.2, endRadius: 6.6)
    }

    /// The plate, tinted: from above the whole of it; from the side the band along the top
    /// that ends in a round end at the peak (the painter cuts it off at the outline).
    var trim: NSBezierPath? {
        switch viewpoint {
        case .above:
            return plate.path
        case .thumbSide:
            let path = NSBezierPath()
            // Its lower edge, front to back, and round its rear end; then round the outside.
            path.move(to: p(-16, 40.4))
            path.line(to: p(44.1, 31.2))
            path.curve(to: p(58.9, 24.4), controlPoint1: p(50.5, 30.2), controlPoint2: p(57.6, 28.6))
            path.line(to: p(62, 12))
            path.line(to: p(-16, 12))
            path.close()
            return path
        }
    }

    /// The button at the plate's rear end, which switches the pointer speed. From above an
    /// oval a little towards the thumb; from the side the same oval seen at a slant.
    private var topButton: Bar {
        switch (viewpoint, schematic) {
        case (.above, false):
            return Bar(centre: p(38.5, 60.5), length: 16.8, thickness: 8.0, degrees: 88.7, startRadius: 4.0, endRadius: 4.0)
        case (.above, true):
            return Bar(centre: p(39.2, 59), length: 21, thickness: 11.5, degrees: 88.7, startRadius: 5.7, endRadius: 5.7)
        case (.thumbSide, false):
            return Bar(centre: p(44.7, 26.1), length: 17.4, thickness: 4.0, degrees: -11, startRadius: 2.0, endRadius: 2.0)
        case (.thumbSide, true):
            return Bar(centre: p(43.5, 26.4), length: 19, thickness: 4.6, degrees: -11, startRadius: 2.3, endRadius: 2.3)
        }
    }

    // MARK: - From above: the buttons and the wheel

    /// The split between the two buttons, and the middle of the wheel.
    static let split: CGFloat = 61.6
    /// Where the split meets the buttons' end, and the right button's rear corner.
    private static let splitEnd = NSPoint(x: split, y: 52.9)
    private static let rightCorner = NSPoint(x: 73.6, y: 55.7)

    /// A point on the plate's right edge, `along` its axis from its middle.
    private func plateEdge(along: CGFloat) -> NSPoint {
        return plate.point(along: along, across: -plate.thickness / 2)
    }

    /// Where the buttons' end meets the plate.
    private var buttonsEndAtPlate: NSPoint {
        return plateEdge(along: 10.8)
    }

    /// The left (or right) button: the outer face in front of where the buttons end. The
    /// left one lies between the plate and the split, the right one between the split and
    /// its own outer edge (the wheel lies over both).
    func buttonArea(left: Bool) -> NSBezierPath? {
        guard viewpoint == .above else { return nil }
        let area = NSBezierPath()
        if left {
            area.move(to: plateEdge(along: -40))
            area.line(to: buttonsEndAtPlate)
            area.line(to: Self.splitEnd)
            area.line(to: p(Self.split, -4))
        } else {
            area.move(to: p(Self.split, -4))
            area.line(to: Self.splitEnd)
            area.line(to: Self.rightCorner)
            area.curve(to: p(77.2, 51.5), controlPoint1: p(76, 56.2), controlPoint2: p(77.2, 54.2))
            area.line(to: p(77.2, 31))
            area.curve(to: p(68.8, 7.2), controlPoint1: p(77.2, 21), controlPoint2: p(73.2, 12.5))
            area.line(to: p(66, -4))
        }
        area.close()
        return NSBezierPath(cgPath: outline().cgPath.intersection(area.cgPath))
    }

    var wheelRect: NSRect {
        let rect = NSRect(x: Self.split - 3.0, y: 12.6, width: 6.0, height: 18.2)
        return schematic ? grown(rect, width: 1.8, height: 1.15) : rect
    }

    /// The small recess the wheel turns in.
    var wellRect: NSRect {
        return wheelRect.insetBy(dx: -1.6, dy: -2.2)
    }

    // MARK: - From the thumb side

    /// Forward (in front, the longer one) and Back: the two halves of one key under the
    /// plate, which rises a little to the rear.
    private func sideButton(_ part: MouseArtworkPart) -> Bar? {
        guard viewpoint == .thumbSide else { return nil }
        switch (part, schematic) {
        case (.forward, false):
            return Bar(centre: p(19.2, 43.7), length: 14.6, thickness: 4.8, degrees: -9.3, startRadius: 2.4, endRadius: 0.8)
        case (.back, false):
            return Bar(centre: p(32.2, 41.6), length: 10.2, thickness: 4.8, degrees: -9.3, startRadius: 0.8, endRadius: 2.4)
        case (.forward, true):
            return Bar(centre: p(15.5, 47.5), length: 16, thickness: 10, degrees: -9.3, startRadius: 5, endRadius: 5)
        case (.back, true):
            return Bar(centre: p(36, 44.2), length: 14, thickness: 10, degrees: -9.3, startRadius: 5, endRadius: 5)
        default:
            return nil
        }
    }

    // MARK: - Parts

    /// The shape of `part` in this view; nil when it does not show from here, and for a
    /// part this mouse does not have.
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
        case .back, .forward:
            return sideButton(part)?.path
        case .pointerSpeed:
            return topButton.path
        case .modeShift, .thumbWheel, .gesture, .thumbPanel:
            return nil
        }
    }

    /// Where the badge of a button the drawing cannot show sits: on the right edge, low
    /// (the badge shows with the view from above).
    var badgeCentre: NSPoint {
        return p(71, 97)
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
