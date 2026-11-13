//
//  MouseArtworkAnywhere3.swift
//  Scrollio
//  The drawing of the MX Anywhere 3 and 3S (also "for Mac" and "for Business"; they look
//  alike): its two views on the grid of MouseArtwork.swift.
//
//  From above (front at the top, thumb side on the left): a small symmetric mouse with one
//  shell over its whole top. The two buttons are the front of that shell, with no seam
//  where they end; down the middle runs one long slot that holds the wheel, the button
//  behind it and a small light. Behind the middle the body is wider than the shell: the
//  two side grips show as crescents. The two side buttons are on the side face: they are
//  not here.
//
//  From the thumb side (front to the left, the mouse on its base; wider than the grid,
//  inside MouseArtworkShapes.canvas): a low body, the wheel standing over the buttons, and
//  Forward and Back as the two halves of one leaf-shaped key right under the shell's edge.
//  This mouse has no thumb wheel, no gesture button and no thumb rest.
//
//  Both views are the same mouse at the same size, 114 units long. Where the parts are was
//  measured on a model of the mouse; the lines are this app's own, and every point is a
//  number below that can be moved. How the shapes are painted is in
//  MouseArtworkTwoViews.swift.
//

import Cocoa

struct MouseArtworkAnywhere3: MouseArtworkTwoViews {

    typealias Bar = MouseArtworkBar

    let viewpoint: MouseArtworkViewpoint
    /// For the small pictures: the parts larger and further apart, not to scale; from the
    /// side the mouse is also drawn taller (`MouseArtworkBar.schematicRise`).
    var schematic = false

    /// No thumb wheel and nothing that holds one; no thumb rest that is a part (the thumb
    /// panel is a part this mouse does not have); no clear rim, no marks.
    var roller: Bar? { return nil }
    var thumbWheelHousing: NSBezierPath? { return nil }
    let restPart = MouseArtworkPart.thumbPanel
    let hasClearRim = false
    var panelDots: NSBezierPath? { return nil }
    var restRidge: NSBezierPath? { return nil }

    // MARK: - Body

    /// The middle of the mouse from above: it is symmetric about it.
    static let middle: CGFloat = 44

    /// The right half of the outline from above, from the middle of the front edge round
    /// to the middle of the back; the left half is its mirror image. A nearly straight
    /// front edge, tight front corners, sides that widen slowly, the bulge of the side
    /// grip behind the middle, and a round back.
    private static let half: [(to: NSPoint, c1: NSPoint, c2: NSPoint)] = [
        // The front edge.
        (NSPoint(x: 70.5, y: 9.5), NSPoint(x: 54, y: 3), NSPoint(x: 65.5, y: 4.6)),
        // The front corner.
        (NSPoint(x: 76.2, y: 23), NSPoint(x: 73.8, y: 12.2), NSPoint(x: 75.6, y: 17.5)),
        // The side beside the buttons.
        (NSPoint(x: 78.6, y: 52), NSPoint(x: 77.2, y: 32), NSPoint(x: 78.6, y: 42)),
        // The side grip, to the widest point.
        (NSPoint(x: 82.0, y: 80), NSPoint(x: 78.6, y: 60), NSPoint(x: 81.8, y: 70)),
        // The back.
        (NSPoint(x: 73, y: 105), NSPoint(x: 82.2, y: 90), NSPoint(x: 79.5, y: 98.5)),
        (NSPoint(x: 44, y: 117), NSPoint(x: 66.5, y: 112.5), NSPoint(x: 56, y: 117)),
    ]

    /// The outline.
    /// From above: see `half`.
    /// From the side: a nose with a chin under it, the buttons rising to the hump just
    /// behind the middle, a long fall to the tail and a flat base.
    func outline() -> NSBezierPath {
        let path = NSBezierPath()
        switch viewpoint {
        case .above:
            let front = p(Self.middle, 3)
            path.move(to: front)
            for curve in Self.half {
                path.curve(to: curve.to, controlPoint1: curve.c1, controlPoint2: curve.c2)
            }
            // Back up the left side: the same curves mirrored, the last one first.
            let starts = [front] + Self.half.map(\.to)
            for index in Self.half.indices.reversed() {
                path.curve(
                    to: mirrored(starts[index]),
                    controlPoint1: mirrored(Self.half[index].c2), controlPoint2: mirrored(Self.half[index].c1)
                )
            }
        case .thumbSide:
            // The nose, up to where the wheel stands.
            path.move(to: p(-13, 70))
            path.curve(to: p(-1, 57.5), controlPoint1: p(-12, 65), controlPoint2: p(-6, 60.3))
            // The buttons' back, to the hump.
            path.curve(to: p(29, 44.8), controlPoint1: p(8, 52.3), controlPoint2: p(19, 47.6))
            path.curve(to: p(56, 41), controlPoint1: p(38, 42.6), controlPoint2: p(47, 41))
            // Down the palm to the tail.
            path.curve(to: p(89, 47.3), controlPoint1: p(68, 41), controlPoint2: p(80, 43.6))
            path.curve(to: p(101, 56.6), controlPoint1: p(94.5, 49.6), controlPoint2: p(99.5, 53))
            path.curve(to: p(95.5, 69.8), controlPoint1: p(101.6, 59.5), controlPoint2: p(98.6, 65.5))
            path.curve(to: p(78.5, 80.2), controlPoint1: p(92, 75), controlPoint2: p(86.5, 80.2))
            // The base.
            path.line(to: p(-3.2, 80.2))
            // The chin, up to the nose.
            path.curve(to: p(-13, 70), controlPoint1: p(-8, 80.2), controlPoint2: p(-12.6, 74))
        }
        path.close()
        return risen(path)
    }

    /// The whole body, for centring the drawing (this mouse has no thumb wing).
    var mainBody: NSRect {
        switch viewpoint {
        case .above: return NSRect(x: 6, y: 3, width: 76, height: 114)
        case .thumbSide: return risen(NSBezierPath(rect: NSRect(x: -13, y: 41, width: 114, height: 39.2))).bounds
        }
    }

    /// `path` as the small pictures draw the view from the side: taller. Everything else
    /// is `path` itself.
    private func risen(_ path: NSBezierPath) -> NSBezierPath {
        return schematic && viewpoint == .thumbSide ? MouseArtworkBar.risen(path) : path
    }

    /// The fine lines inside the outline; the painter clips them to it.
    /// From above: the split between the two buttons, in front of the slot (the top is one
    /// shell: there is no line where the buttons end).
    /// From the side: the lower edge of the top shell, from the nose over the side buttons
    /// to the tail, and the lower edge of the side grip beneath it.
    func seams() -> NSBezierPath {
        let path = NSBezierPath()
        switch viewpoint {
        case .above:
            path.move(to: p(Self.middle, -2))
            path.line(to: p(Self.middle, wellRect.minY))
        case .thumbSide:
            // The shell's edge.
            path.move(to: p(-12.6, 67.5))
            path.curve(to: p(31, 53.1), controlPoint1: p(-2, 61.5), controlPoint2: p(15, 56.2))
            path.curve(to: p(72, 48.2), controlPoint1: p(45, 50.6), controlPoint2: p(60, 48.3))
            path.curve(to: p(100.2, 56.2), controlPoint1: p(84, 48.2), controlPoint2: p(94, 51.5))
            // The grip's lower edge.
            path.move(to: p(-11.5, 69.3))
            path.curve(to: p(30, 72.6), controlPoint1: p(0, 71.2), controlPoint2: p(15, 72.6))
            path.curve(to: p(78, 63.5), controlPoint1: p(48, 72.6), controlPoint2: p(65, 69.5))
            path.curve(to: p(97.5, 54.4), controlPoint1: p(86, 59.8), controlPoint2: p(93, 56.5))
        }
        return risen(path)
    }

    /// The side grips as they show from above, beside the shell behind the middle: two
    /// crescents between the shell's edge and the outline (the painter cuts them off at
    /// the outline). Too fine for the small pictures.
    var trim: NSBezierPath? {
        guard viewpoint == .above, !schematic else { return nil }
        let path = NSBezierPath()
        for side in [false, true] {
            func q(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
                return side ? mirrored(p(x, y)) : p(x, y)
            }
            // The shell's edge, from where it leaves the outline to the back.
            path.move(to: q(78.6, 52))
            path.curve(to: q(73.0, 89), controlPoint1: q(78.9, 64), controlPoint2: q(77.2, 78))
            path.curve(to: q(57.4, 115.4), controlPoint1: q(69.5, 98), controlPoint2: q(64, 109))
            // Round the outside of the body.
            path.line(to: q(57.4, 124))
            path.line(to: q(92, 124))
            path.line(to: q(92, 52))
            path.close()
        }
        return path
    }

    // MARK: - From above: the buttons and the slot

    /// The left (or right) button: the front of the shell on its side of the middle, to
    /// about where a finger still clicks it (the slot lies over both).
    func buttonArea(left: Bool) -> NSBezierPath? {
        guard viewpoint == .above else { return nil }
        let front = NSBezierPath()
        front.move(to: p(-4, -4))
        front.line(to: p(92, -4))
        front.line(to: p(92, 57))
        front.line(to: p(84, 57))
        front.curve(to: p(4, 57), controlPoint1: p(62, 68), controlPoint2: p(26, 68))
        front.line(to: p(-4, 57))
        front.close()
        let side = NSBezierPath(rect: left
            ? NSRect(x: -4, y: -4, width: Self.middle + 4, height: 80)
            : NSRect(x: Self.middle, y: -4, width: 96 - Self.middle, height: 80))
        return NSBezierPath(cgPath: outline().cgPath.intersection(front.cgPath).intersection(side.cgPath))
    }

    var wheelRect: NSRect {
        let rect = NSRect(x: Self.middle - 4.3, y: 16.2, width: 8.6, height: 17.6)
        return schematic ? grown(rect, width: 1.6, height: 1.15) : rect
    }

    /// The long slot down the middle: it holds the wheel, the button behind it and the light.
    var wellRect: NSRect {
        return NSRect(x: Self.middle - 7.9, y: 11.6, width: 15.8, height: 63.6)
    }

    /// The button behind the wheel: a small pill in the slot.
    private var modeShiftRect: NSRect {
        let rect = NSRect(x: Self.middle - 2.7, y: 38.2, width: 5.4, height: 10.4)
        return schematic ? grown(rect, width: 1.9, height: 1.25) : rect
    }

    /// The small light in the slot, behind that button.
    var light: NSBezierPath? {
        guard viewpoint == .above, !schematic else { return nil }
        return NSBezierPath(ovalIn: NSRect(x: Self.middle - 0.9, y: 52.9, width: 1.8, height: 1.8))
    }

    // MARK: - From the thumb side

    /// Forward (in front) and Back: the two halves of one leaf-shaped key that rises a
    /// little to the rear, right under the shell's edge.
    private func sideButton(_ part: MouseArtworkPart) -> Bar? {
        guard viewpoint == .thumbSide else { return nil }
        switch (part, schematic) {
        case (.forward, false):
            return Bar(centre: p(38.9, 55.3), length: 15.4, thickness: 4.4, degrees: -8, startRadius: 2.2, endRadius: 0.8)
        case (.back, false):
            return Bar(centre: p(55.2, 52.9), length: 15.6, thickness: 4.4, degrees: -10, startRadius: 0.8, endRadius: 2.2)
        case (.forward, true):
            return Bar(centre: p(35.5, 56.5), length: 17, thickness: 9.5, degrees: -9, startRadius: 4.7, endRadius: 4.7)
        case (.back, true):
            return Bar(centre: p(57.5, 53), length: 17, thickness: 9.5, degrees: -9, startRadius: 4.7, endRadius: 4.7)
        default:
            return nil
        }
    }

    /// The wheel as it shows over the buttons from the side: the top of a disc, the rest of
    /// it behind the body.
    var wheelCrest: NSBezierPath? {
        guard viewpoint == .thumbSide else { return nil }
        return risen(NSBezierPath(ovalIn: NSRect(x: 9.8 - 7.5, y: 56.2 - 7.5, width: 15, height: 15)))
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
        case .modeShift:
            guard viewpoint == .above else { return nil }
            return capsule(modeShiftRect)
        case .back, .forward:
            return sideButton(part)?.path
        case .thumbWheel, .gesture, .thumbPanel, .pointerSpeed:
            return nil
        }
    }

    /// Where the badge of a button the drawing cannot show sits: on the right edge, low
    /// (the badge shows with the view from above).
    var badgeCentre: NSPoint {
        return p(74, 97)
    }

    // MARK: - Helpers

    private func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        return NSPoint(x: x, y: y)
    }

    /// `point` on the other side of the mouse's middle (from above).
    private func mirrored(_ point: NSPoint) -> NSPoint {
        return NSPoint(x: 2 * Self.middle - point.x, y: point.y)
    }

    private func grown(_ rect: NSRect, width: CGFloat, height: CGFloat) -> NSRect {
        return rect.insetBy(dx: -rect.width * (width - 1) / 2, dy: -rect.height * (height - 1) / 2)
    }

    private func capsule(_ rect: NSRect) -> NSBezierPath {
        let radius = min(rect.width, rect.height) / 2
        return NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    }
}
