//
//  ShortcutRingDrops.swift
//  Scrollio
//
//  The Shortcut Ring as drops, in numbers: nine round drops and no disc behind them. Eight
//  stand at the ring's places (`ShortcutRingGeometry`), one in the middle (the hub) names
//  the lit action. Pure: where each drop is and how large, at any moment of the opening
//  and for any lighting. The panel (`ShortcutRingPanel`), the Settings pane and the render
//  tests all draw what `frame` says.
//
//  - The opening: the place drops start in the middle, small and transparent, and travel
//    to their places on a spring, one after the other clockwise from the top, showing as
//    they come out of the hub; the hub grows. Everything has settled after `openDuration`.
//  - The lit place: its drop grows, moves a little outwards along its ray and takes the
//    accent colour, eased over `litDuration`. The place lit before eases back in the same
//    time (`Lighting`), so going from one place to the next never jumps.
//  - An empty place is a small faint drop that travels like the others and never lights.
//  - With "Reduce motion" there is no opening and no easing: `frame` gives the settled
//    state at any time, and `Lighting` changes at once.
//
//  Offsets are in the geometry's coordinates: from the ring's middle, y DOWNWARDS.
//

import CoreGraphics
import Foundation

/// What the ring's drops are made of.
enum ShortcutRingMaterial: Equatable {
    /// Opaque drops drawn by the app: for "Reduce transparency" and "Increase contrast".
    case drawn
    /// Liquid Glass (macOS 26 and later).
    case glass
    /// The system's blurred material, cut to the drops (macOS 14 and 15).
    case blur
}

enum ShortcutRingDrops {

    static let placeCount = ShortcutRingGeometry.placeCount

    // MARK: Sizes (points)

    /// The drop in the middle. With the places' drops (50 wide, 82 from the middle) it
    /// leaves 13 points to each of them, as much as two neighbouring places leave.
    static let hubDiameter: CGFloat = 88
    /// An empty place: a small drop.
    static let emptyDiameter: CGFloat = 14
    /// And a faint one (where the material can be faint: not on glass).
    static let emptyOpacity: CGFloat = 0.6

    // MARK: The lit place

    /// The lit drop is this much larger,
    static let litScale: CGFloat = 1.3
    /// this far outwards along its ray,
    static let litPush: CGFloat = 6
    /// and what stands in it grows by this much.
    static let litContentScale: CGFloat = 1.12
    /// How long the change takes; it starts at once.
    static let litDuration: TimeInterval = 0.12

    // MARK: The opening

    /// A place's drop starts this small, in the middle.
    static let startScale: CGFloat = 0.4
    /// The hub starts this small
    static let hubStartScale: CGFloat = 0.6
    /// and is full size after this long.
    static let hubDuration: TimeInterval = 0.12
    /// Each place's drop leaves this long after the one before it, clockwise from the top.
    static let stagger: TimeInterval = 0.012
    /// A drop's own way to its place, from its start to rest.
    static let travelDuration: TimeInterval = 0.266
    /// A travelling drop shows as it comes out of the hub: not at all on the first
    /// quarter of its way, fully from where its middle reaches the hub's edge (the hub is
    /// 44 points wide from its middle, a place 82 away). So nothing crawls over the hub's
    /// face and the name on it.
    static let revealStart: CGFloat = 0.25
    static let revealEnd: CGFloat = 0.55
    /// From the first frame until the last drop rests: 0.35 s.
    static let openDuration: TimeInterval = stagger * Double(placeCount - 1) + travelDuration

    /// The spring of a drop's way: a little under-damped, so a drop goes about 5 percent
    /// past its place and comes back (under 4 points of the 82).
    static let springDamping: Double = 0.7
    /// Radians per second: with the damping above, what is left of the swing after
    /// `travelDuration` is half a percent (under half a point), and the drop is put to rest.
    static let springFrequency: Double = 28.5

    /// Liquid Glass: drops closer than this flow into each other
    /// (`NSGlassEffectContainerView.spacing`). Less than the lit drop leaves to its
    /// neighbours (about 8), so drops only join while they are still leaving the middle.
    static let glassSpacing: CGFloat = 6

    // MARK: One drop

    struct Drop: Equatable {
        /// Its middle, from the ring's middle (y downwards).
        var offset: CGPoint
        /// How wide it is at rest and unlit.
        var restDiameter: CGFloat
        /// The opening's part of its size: `startScale` … 1 (a little more on the way).
        var grow: CGFloat
        /// How far it is lit, 0 … 1.
        var lit: CGFloat
        /// 0 … 1.
        var opacity: CGFloat

        /// How wide it is now.
        var diameter: CGFloat {
            return restDiameter * grow * (1 + (ShortcutRingDrops.litScale - 1) * lit)
        }

        /// How large its symbol (or the hub's name) is now, 1 at rest and unlit.
        var contentScale: CGFloat {
            return grow * (1 + (ShortcutRingDrops.litContentScale - 1) * lit)
        }
    }

    /// All nine at one moment.
    struct Frame: Equatable {
        /// The places' drops, clockwise from the top.
        var places: [Drop]
        var hub: Drop

        /// The places' drops, then the hub.
        var all: [Drop] {
            return places + [hub]
        }

        /// From the bottom up: the hub, then the places' drops, which leave the middle on
        /// top of it (a drop and what stands in it stay together all the way).
        var stacked: [Drop] {
            return [hub] + places
        }
    }

    // MARK: Curves

    /// 0 … 1 for 0 … 1, fast first.
    static func ease(_ x: Double) -> CGFloat {
        guard x > 0 else { return 0 }
        guard x < 1 else { return 1 }
        let rest = 1 - x
        return CGFloat(1 - rest * rest * rest)
    }

    /// How far a drop has come `time` after it left: 0 at the start, a little over 1 on
    /// the way, exactly 1 from `travelDuration` on.
    static func spring(_ time: TimeInterval) -> CGFloat {
        guard time > 0 else { return 0 }
        guard time < travelDuration else { return 1 }
        let decay = springDamping * springFrequency
        let swing = springFrequency * (1 - springDamping * springDamping).squareRoot()
        let value = 1 - exp(-decay * time) * (cos(swing * time) + decay / swing * sin(swing * time))
        return CGFloat(value)
    }

    // MARK: The ring at a moment

    /// The nine drops `elapsed` seconds after the ring opened.
    /// - Parameters:
    ///   - filled: which places hold something (`ShortcutRingFace.filled`).
    ///   - lit: how far each place is lit (`Lighting.amounts`); an empty place never is.
    ///   - reducesMotion: no opening: the settled state, whatever the time.
    static func frame(
        at elapsed: TimeInterval,
        filled: [Bool],
        lit: [CGFloat] = [],
        reducesMotion: Bool = false
    ) -> Frame {
        let elapsed = reducesMotion ? TimeInterval.infinity : elapsed
        let hub = Drop(
            offset: .zero,
            restDiameter: hubDiameter,
            grow: hubStartScale + (1 - hubStartScale) * ease(elapsed / hubDuration),
            lit: 0,
            opacity: 1
        )
        let places: [Drop] = (0..<placeCount).map { index in
            let own = elapsed - Double(index) * stagger
            let progress = spring(own)
            let isFilled = filled.indices.contains(index) && filled[index]
            let amount = isFilled && lit.indices.contains(index) ? min(max(lit[index], 0), 1) : 0
            let radius = ShortcutRingGeometry.placeRadius * progress + litPush * amount
            let ray = ShortcutRingGeometry.offset(ofPlace: index, radius: 1)
            return Drop(
                offset: CGPoint(x: ray.x * radius, y: ray.y * radius),
                restDiameter: isFilled ? ShortcutRingGeometry.placeDiameter : emptyDiameter,
                grow: startScale + (1 - startScale) * progress,
                lit: amount,
                opacity: ease(Double((progress - revealStart) / (revealEnd - revealStart))) * (isFilled ? 1 : emptyOpacity)
            )
        }
        return Frame(places: places, hub: hub)
    }

    /// The ring at rest with `lit` fully lit: what the Settings pane and still pictures show.
    static func settled(filled: [Bool], lit: Int? = nil) -> Frame {
        var amounts = [CGFloat](repeating: 0, count: placeCount)
        if let lit, amounts.indices.contains(lit) {
            amounts[lit] = 1
        }
        return frame(at: .infinity, filled: filled, lit: amounts)
    }

    // MARK: Lighting over time

    /// Which place is lit and how far each place has come on its way there or back.
    struct Lighting: Equatable {
        /// The lit place, or none.
        private(set) var target: Int?
        /// How far each place was lit when `target` last changed,
        private(set) var from = [CGFloat](repeating: 0, count: ShortcutRingDrops.placeCount)
        /// and when that was. Long ago: nothing is on its way.
        private(set) var since = -TimeInterval.infinity

        /// How far each place is lit at `time`.
        func amounts(at time: TimeInterval) -> [CGFloat] {
            let progress = ShortcutRingDrops.ease((time - since) / ShortcutRingDrops.litDuration)
            return from.indices.map { index in
                let to: CGFloat = index == target ? 1 : 0
                // Arrived is exactly there (the sum below may be a hair off).
                return progress >= 1 ? to : from[index] + (to - from[index]) * progress
            }
        }

        /// Whether nothing changes any more at `time`.
        func isSettled(at time: TimeInterval) -> Bool {
            return time - since >= ShortcutRingDrops.litDuration
        }

        /// Lights `place` (or nothing) from `time` on. An empty place never lights.
        /// `eased` false ("Reduce motion", or a ring that appears with a place lit): at once.
        mutating func light(_ place: Int?, at time: TimeInterval, filled: [Bool], eased: Bool = true) {
            let place = place.flatMap { filled.indices.contains($0) && filled[$0] ? $0 : nil }
            if eased {
                guard place != target else { return }
                from = amounts(at: time)
                since = time
            } else {
                from = from.indices.map { $0 == place ? 1 : 0 }
                since = -.infinity
            }
            target = place
        }
    }
}
