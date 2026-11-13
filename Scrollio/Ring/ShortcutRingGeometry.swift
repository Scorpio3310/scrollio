//
//  ShortcutRingGeometry.swift
//  Scrollio
//
//  The Shortcut Ring in numbers: how large it is, which place a movement or a point means,
//  and where the ring stands near the edge of a screen. Pure.
//
//  Places are counted clockwise from the top: 0 top, 1 top right, 2 right … 7 top left.
//  Offsets and points are in the coordinates of events (`CGEvent.location`, the deltas of
//  a mouse event): x grows to the right, y grows DOWNWARDS. The drawing turns y around.
//

import CoreGraphics

enum ShortcutRingGeometry {

    static let placeCount = ShortcutRingSettings.placeCount

    // MARK: Sizes (points)

    /// From the middle to the ring's outer edge.
    static let outerRadius: CGFloat = 118
    /// From the middle to the middle of a place.
    static let placeRadius: CGFloat = 82
    /// A place is a circle this wide.
    static let placeDiameter: CGFloat = 50
    /// The free middle, where the lit action is named: up to the places' inner edge.
    static let hubRadius: CGFloat = placeRadius - placeDiameter / 2 - 3
    /// How far the hand moves before a place lights while the trigger is held. Small
    /// enough to choose with a flick, large enough that a press alone lights nothing.
    static let deadZone: CGFloat = 20
    /// The click way: a point farther than this from the middle is outside the ring: the
    /// drawn ring and a little more, and less than a pointer at the very edge of a screen
    /// is from a ring that was moved inwards (`outerRadius + screenMargin`).
    static let reach: CGFloat = outerRadius + 6
    /// The ring keeps this far from the edge of its screen.
    static let screenMargin: CGFloat = 10
    /// The hold way counts the hand's movement since the press, and no more of it than
    /// this in any direction: at the edge of a screen the pointer stops but the hand's
    /// movement still arrives, and without a limit a long push against the edge would
    /// have to be taken back in full before another place could light.
    static let travelLimit: CGFloat = outerRadius * 1.5
    /// A lit place stays lit until the direction is this far (radians) past its border,
    /// so a hand that rests on the border between two places does not flicker.
    static let stickiness: CGFloat = 6 * .pi / 180

    /// The side of the square the ring is drawn in (the ring and room for its shadow).
    static let canvasSide: CGFloat = (outerRadius + 26) * 2

    // MARK: Directions

    /// The angle of a place's middle, clockwise from straight up, in radians.
    static func angle(ofPlace index: Int) -> CGFloat {
        return CGFloat(index) * 2 * .pi / CGFloat(placeCount)
    }

    /// The direction of an offset, clockwise from straight up, in 0 ..< 2π.
    static func angle(ofOffset offset: CGPoint) -> CGFloat {
        // y grows downwards: up is -y.
        let angle = atan2(offset.x, -offset.y)
        return angle < 0 ? angle + 2 * .pi : angle
    }

    /// The middle of a place as an offset from the ring's middle (y downwards).
    static func offset(ofPlace index: Int, radius: CGFloat = placeRadius) -> CGPoint {
        let angle = self.angle(ofPlace: index)
        return CGPoint(x: sin(angle) * radius, y: -cos(angle) * radius)
    }

    /// The place an offset from the middle points at, by its direction alone; nil inside
    /// `deadZone` and for an offset that is no number. With `current` the lit place keeps
    /// its hold for `stickiness` past its borders.
    static func place(
        forOffset offset: CGPoint,
        deadZone: CGFloat = ShortcutRingGeometry.deadZone,
        current: Int? = nil
    ) -> Int? {
        guard offset.x.isFinite, offset.y.isFinite else { return nil }
        guard hypot(offset.x, offset.y) >= deadZone else { return nil }
        let direction = angle(ofOffset: offset)
        let sector = 2 * CGFloat.pi / CGFloat(placeCount)
        if let current, (0..<placeCount).contains(current) {
            var away = abs(direction - angle(ofPlace: current))
            if away > .pi { away = 2 * .pi - away }
            if away <= sector / 2 + stickiness { return current }
        }
        return Int((direction / sector).rounded()) % placeCount
    }

    // MARK: The hold way: movement since the press

    /// The hand's movement since the press after one more movement of the mouse, kept
    /// within `limit` of the start.
    static func travel(_ travel: CGPoint, movedBy delta: CGPoint, limit: CGFloat = travelLimit) -> CGPoint {
        guard delta.x.isFinite, delta.y.isFinite else { return travel }
        let moved = CGPoint(x: travel.x + delta.x, y: travel.y + delta.y)
        let length = hypot(moved.x, moved.y)
        guard length > limit, length > 0 else { return moved }
        return CGPoint(x: moved.x * limit / length, y: moved.y * limit / length)
    }

    // MARK: The click way: what is under the pointer

    enum Target: Equatable {
        /// The free middle of the ring.
        case middle
        /// A place, by the direction from the middle: one need not land on its circle.
        case place(Int)
        /// Farther from the middle than `reach`.
        case outside
    }

    /// What a point means in an open ring whose middle is at `centre`.
    static func target(at point: CGPoint, centre: CGPoint, current: Int? = nil) -> Target {
        let offset = CGPoint(x: point.x - centre.x, y: point.y - centre.y)
        guard offset.x.isFinite, offset.y.isFinite else { return .outside }
        let distance = hypot(offset.x, offset.y)
        if distance > reach { return .outside }
        if distance < hubRadius { return .middle }
        guard let place = place(forOffset: offset, deadZone: 0, current: current) else { return .middle }
        return .place(place)
    }

    // MARK: Near the edge of a screen

    /// Where the ring's middle stands for a pointer at `pointer` on a screen with the
    /// frame `screen`: at the pointer, moved inwards as far as it takes for the whole
    /// ring (and `screenMargin`) to stay on that screen. A screen too small for the ring
    /// gets it in its middle.
    static func centre(forPointer pointer: CGPoint, in screen: CGRect) -> CGPoint {
        let inset = outerRadius + screenMargin
        func kept(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
            guard low <= high else { return (low + high) / 2 }
            return min(max(value, low), high)
        }
        return CGPoint(
            x: kept(pointer.x, screen.minX + inset, screen.maxX - inset),
            y: kept(pointer.y, screen.minY + inset, screen.maxY - inset)
        )
    }
}
