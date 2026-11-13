//
//  ShortcutRingDropsTests.swift
//  ScrollioTests
//
//  The Shortcut Ring as drops: what the drops are made of on which system, where each
//  drop is at which moment of the opening, how the lit one grows, and that the panel
//  shows exactly that, frame by frame, without ever waiting for it.
//

import XCTest
@testable import Scrollio_Debug

// MARK: - The numbers

final class ShortcutRingDropsTests: XCTestCase {

    private typealias Drops = ShortcutRingDrops
    private typealias Geometry = ShortcutRingGeometry

    private let allFilled = [Bool](repeating: true, count: 8)

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        return hypot(a.x - b.x, a.y - b.y)
    }

    private func lit(_ place: Int, _ amount: CGFloat = 1) -> [CGFloat] {
        var amounts = [CGFloat](repeating: 0, count: 8)
        amounts[place] = amount
        return amounts
    }

    // MARK: At rest

    /// Nine drops and nothing else: each place's drop on its place, the hub in the middle,
    /// with the same gap between two neighbours and between the hub and a place.
    func testAtRestEveryDropIsOnItsPlaceAndStandsApart() {
        let rest = Drops.settled(filled: allFilled)
        XCTAssertEqual(rest.places.count, 8)
        XCTAssertEqual(rest.all.count, 9)
        for (index, drop) in rest.places.enumerated() {
            let place = Geometry.offset(ofPlace: index)
            XCTAssertEqual(drop.offset.x, place.x, accuracy: 0.001)
            XCTAssertEqual(drop.offset.y, place.y, accuracy: 0.001)
            XCTAssertEqual(drop.diameter, Geometry.placeDiameter)
            XCTAssertEqual(drop.opacity, 1)
            XCTAssertEqual(drop.contentScale, 1)
            XCTAssertEqual(drop.lit, 0)
        }
        XCTAssertEqual(rest.hub.offset, .zero)
        XCTAssertEqual(rest.hub.diameter, 88)
        XCTAssertEqual(rest.hub.opacity, 1)
        // The hub lies under the places' drops, which leave the middle on top of it.
        XCTAssertEqual(rest.stacked.first, rest.hub)
        XCTAssertEqual(Array(rest.stacked.dropFirst()), rest.places)

        let between = distance(rest.places[0].offset, rest.places[1].offset) - Geometry.placeDiameter
        let toHub = Geometry.placeRadius - Geometry.placeDiameter / 2 - Drops.hubDiameter / 2
        XCTAssertEqual(between, 13, accuracy: 0.5)
        XCTAssertEqual(toHub, 13, accuracy: 0.5)
        // Glass drops flow together only when they are closer than the container's spacing.
        XCTAssertLessThan(Drops.glassSpacing, between)
        XCTAssertLessThan(Drops.glassSpacing, toHub)
    }

    // MARK: The opening

    /// The first frame: the places' drops in the middle, small and transparent, the hub
    /// small but there.
    func testTheOpeningStartsInTheMiddle() {
        let start = Drops.frame(at: 0, filled: allFilled)
        for drop in start.places {
            XCTAssertEqual(drop.offset, .zero)
            XCTAssertEqual(drop.diameter, Geometry.placeDiameter * 0.4, accuracy: 0.001)
            XCTAssertEqual(drop.opacity, 0)
        }
        XCTAssertEqual(start.hub.diameter, 88 * 0.6, accuracy: 0.001)
        XCTAssertEqual(start.hub.opacity, 1, "something is seen from the first frame")
        XCTAssertEqual(Drops.frame(at: -1, filled: allFilled), start, "before the start is the start")
    }

    /// One after the other, clockwise from the top, 12 ms apart.
    func testTheDropsLeaveOneAfterTheOtherClockwiseFromTheTop() {
        XCTAssertEqual(Drops.stagger, 0.012, accuracy: 0.0001)
        let early = Drops.frame(at: 0.030, filled: allFilled)
        let travelled = early.places.map { hypot($0.offset.x, $0.offset.y) }
        XCTAssertGreaterThan(travelled[0], travelled[1])
        XCTAssertGreaterThan(travelled[1], travelled[2])
        XCTAssertGreaterThan(travelled[2], 0)
        // The fourth leaves 36 ms after the first: it has not left yet.
        for index in 3..<8 {
            XCTAssertEqual(travelled[index], 0, "place \(index)")
            XCTAssertEqual(early.places[index].opacity, 0)
        }
        // Every drop goes the same way, only later: the second is at 62 ms where the
        // first was at 50.
        let first = Drops.frame(at: 0.050, filled: allFilled).places[0]
        let second = Drops.frame(at: 0.062, filled: allFilled).places[1]
        XCTAssertEqual(hypot(second.offset.x, second.offset.y), hypot(first.offset.x, first.offset.y), accuracy: 0.001)
        XCTAssertEqual(second.diameter, first.diameter, accuracy: 0.001)
        XCTAssertEqual(second.opacity, first.opacity, accuracy: 0.001)
        // Each travels along its own ray.
        let third = early.places[2].offset
        let ray = Geometry.offset(ofPlace: 2, radius: 1)
        XCTAssertEqual(third.x * ray.y - third.y * ray.x, 0, accuracy: 0.001)
    }

    /// After 0.35 s everything rests, exactly, and stays so.
    func testTheOpeningHasSettledAfterAThirdOfASecond() {
        XCTAssertEqual(Drops.openDuration, 0.35, accuracy: 0.001)
        let rest = Drops.settled(filled: allFilled)
        XCTAssertEqual(Drops.frame(at: Drops.openDuration, filled: allFilled), rest)
        XCTAssertEqual(Drops.frame(at: 1, filled: allFilled), rest)
        XCTAssertEqual(Drops.frame(at: 3600, filled: allFilled), rest)
        // The hub is full size after 0.12 s.
        XCTAssertEqual(Drops.frame(at: 0.12, filled: allFilled).hub.diameter, 88)
        XCTAssertLessThan(Drops.frame(at: 0.06, filled: allFilled).hub.diameter, 88)
        XCTAssertGreaterThan(Drops.frame(at: 0.06, filled: allFilled).hub.diameter, 88 * 0.6)
    }

    /// A spring: a drop is at its place well before it rests, goes a little past it and
    /// comes back; what is left of the swing when it is put to rest cannot be seen.
    func testADropsWayIsASpringThatEndsWithoutAJump() {
        XCTAssertEqual(Drops.spring(0), 0)
        XCTAssertEqual(Drops.spring(-1), 0)
        XCTAssertEqual(Drops.spring(Drops.travelDuration), 1)
        XCTAssertEqual(Drops.spring(.infinity), 1)
        var highest: CGFloat = 0
        var last: CGFloat = 0
        var firstArrival: TimeInterval?
        for step in 0...266 {
            let time = Double(step) / 1000
            let value = Drops.spring(time)
            XCTAssertLessThan(abs(value - last), 0.03, "no jump at \(time)")
            if value >= 1, firstArrival == nil { firstArrival = time }
            highest = max(highest, value)
            last = value
        }
        XCTAssertGreaterThan(highest, 1.02, "it goes past its place")
        XCTAssertLessThan(highest, 1.06, "but not far: under 5 points of the 82")
        XCTAssertLessThan(try XCTUnwrap(firstArrival), 0.14)
        XCTAssertEqual(Drops.spring(Drops.travelDuration - 0.0005), 1, accuracy: 0.006, "put to rest without a jump")
    }

    /// A drop shows as it comes out of the hub: while it is well inside, nothing of it is
    /// seen (nothing crawls over the hub's face and the name on it); from where its middle
    /// is at the hub's edge it is fully there.
    func testATravellingDropShowsAsItLeavesTheHub() {
        let hubRadius = Drops.hubDiameter / 2
        var sawHidden = false, sawPartly = false, sawFull = false
        var last: CGFloat = 0
        for step in 0...266 {
            let drop = Drops.frame(at: Double(step) / 1000, filled: allFilled).places[0]
            let out = hypot(drop.offset.x, drop.offset.y)
            XCTAssertGreaterThanOrEqual(drop.opacity, last - 0.0001, "it only ever shows more")
            XCTAssertLessThan(drop.opacity - last, 0.2, "and never at a stroke")
            if out < Geometry.placeRadius * 0.25 {
                XCTAssertEqual(drop.opacity, 0, "\(step) ms")
                sawHidden = true
            } else if out >= hubRadius + 1.5 {
                XCTAssertEqual(drop.opacity, 1, "\(step) ms")
                sawFull = true
            } else if drop.opacity > 0, drop.opacity < 1 {
                sawPartly = true
            }
            last = drop.opacity
        }
        XCTAssertTrue(sawHidden && sawPartly && sawFull)
        XCTAssertEqual(Drops.frame(at: 0.08, filled: allFilled).places[0].opacity, 1, "there after 80 ms at the latest")
    }

    /// "Reduce motion": the settled state from the first moment.
    func testWithReduceMotionEveryDropIsInItsPlaceAtTimeZero() {
        let rest = Drops.settled(filled: allFilled)
        XCTAssertEqual(Drops.frame(at: 0, filled: allFilled, reducesMotion: true), rest)
        XCTAssertEqual(Drops.frame(at: 0.05, filled: allFilled, reducesMotion: true), rest)
        XCTAssertEqual(
            Drops.frame(at: 0, filled: allFilled, lit: lit(3), reducesMotion: true),
            Drops.settled(filled: allFilled, lit: 3)
        )
    }

    // MARK: The lit place

    /// The lit drop is 1.3 times as large and 6 points farther out along its ray; what
    /// stands in it grows by 12 percent. The others stay as they are.
    func testTheLitDropGrowsAndMovesOutwardsAlongItsRay() {
        let rest = Drops.settled(filled: allFilled)
        for place in 0..<8 {
            let shown = Drops.settled(filled: allFilled, lit: place)
            let drop = shown.places[place]
            XCTAssertEqual(drop.diameter, Geometry.placeDiameter * 1.3, accuracy: 0.001)
            XCTAssertEqual(drop.contentScale, 1.12, accuracy: 0.001)
            XCTAssertEqual(drop.lit, 1)
            let outwards = Geometry.offset(ofPlace: place, radius: Geometry.placeRadius + 6)
            XCTAssertEqual(drop.offset.x, outwards.x, accuracy: 0.001)
            XCTAssertEqual(drop.offset.y, outwards.y, accuracy: 0.001)
            for other in 0..<8 where other != place {
                XCTAssertEqual(shown.places[other], rest.places[other])
            }
            XCTAssertEqual(shown.hub, rest.hub)
            // It still stands apart from its neighbours and from the hub: glass drops
            // would flow together below the container's spacing.
            for neighbour in [(place + 1) % 8, (place + 7) % 8] {
                let gap = distance(drop.offset, shown.places[neighbour].offset) - drop.diameter / 2 - Geometry.placeDiameter / 2
                XCTAssertGreaterThan(gap, Drops.glassSpacing + 1)
            }
            XCTAssertGreaterThan(hypot(drop.offset.x, drop.offset.y) - drop.diameter / 2 - 44, Drops.glassSpacing + 1)
            // And inside what the ring keeps free at a screen's edge.
            XCTAssertLessThan(
                hypot(drop.offset.x, drop.offset.y) + drop.diameter / 2, Geometry.outerRadius + Geometry.screenMargin
            )
            XCTAssertLessThan(hypot(drop.offset.x, drop.offset.y) + drop.diameter / 2 + 12, Geometry.canvasSide / 2)
        }
        // Half lit is half of each.
        let half = Drops.frame(at: .infinity, filled: allFilled, lit: lit(2, 0.5)).places[2]
        XCTAssertEqual(half.diameter, Geometry.placeDiameter * 1.15, accuracy: 0.001)
        XCTAssertEqual(half.offset.x, Geometry.placeRadius + 3, accuracy: 0.001)
    }

    /// The ring is used from its first frame: a place lit while its drop still travels
    /// shows lit there.
    func testAPlaceLitWhileItsDropTravelsShowsLit() {
        let plain = Drops.frame(at: 0.05, filled: allFilled).places[0]
        let shown = Drops.frame(at: 0.05, filled: allFilled, lit: lit(0)).places[0]
        XCTAssertEqual(shown.lit, 1)
        XCTAssertEqual(shown.diameter, plain.diameter * 1.3, accuracy: 0.001)
        XCTAssertEqual(shown.offset.y, plain.offset.y - 6, accuracy: 0.001, "the top place: 6 points farther up")
        XCTAssertEqual(shown.opacity, plain.opacity)
    }

    /// An empty place is a small faint drop that travels like the others and never
    /// grows or lights, whatever it is told.
    func testAnEmptyPlaceIsASmallFaintDropThatNeverLights() {
        var filled = allFilled
        filled[3] = false
        let rest = Drops.settled(filled: filled)
        XCTAssertEqual(rest.places[3].diameter, 14)
        XCTAssertEqual(rest.places[3].opacity, 0.6, accuracy: 0.001)
        XCTAssertEqual(rest.places[3].offset.x, Geometry.offset(ofPlace: 3).x, accuracy: 0.001)
        XCTAssertEqual(Drops.settled(filled: filled, lit: 3), rest)
        XCTAssertEqual(Drops.frame(at: .infinity, filled: filled, lit: lit(3)), rest)
        XCTAssertEqual(Drops.frame(at: 0, filled: filled).places[3].diameter, 14 * 0.4, accuracy: 0.001)

        var lighting = Drops.Lighting()
        lighting.light(3, at: 10, filled: filled)
        XCTAssertNil(lighting.target)
        XCTAssertEqual(lighting.amounts(at: 11), [CGFloat](repeating: 0, count: 8))
        lighting.light(3, at: 12, filled: filled, eased: false)
        XCTAssertNil(lighting.target)
        lighting.light(9, at: 13, filled: filled)
        XCTAssertNil(lighting.target, "a place that is none")
        // Nothing filled at all (a face that was never made).
        XCTAssertEqual(Drops.frame(at: .infinity, filled: []).places.map(\.diameter), [CGFloat](repeating: 14, count: 8))
    }

    // MARK: Lighting over time

    /// The change starts at once and is done after 0.12 s.
    func testLightingStartsAtOnceAndEasesInAnEighthOfASecond() {
        XCTAssertEqual(Drops.litDuration, 0.12, accuracy: 0.001)
        var lighting = Drops.Lighting()
        XCTAssertTrue(lighting.isSettled(at: 0))
        lighting.light(2, at: 100, filled: allFilled)
        XCTAssertEqual(lighting.target, 2)
        XCTAssertEqual(lighting.amounts(at: 100)[2], 0)
        XCTAssertGreaterThan(lighting.amounts(at: 100.008)[2], 0.15, "after one frame it shows")
        XCTAssertGreaterThan(lighting.amounts(at: 100.06)[2], 0.8, "fast first")
        XCTAssertLessThan(lighting.amounts(at: 100.06)[2], 1)
        XCTAssertFalse(lighting.isSettled(at: 100.06))
        XCTAssertEqual(lighting.amounts(at: 100.12)[2], 1)
        XCTAssertTrue(lighting.isSettled(at: 100.12))
        XCTAssertEqual(lighting.amounts(at: 500)[2], 1)
        // The same place again changes nothing (the session says it once; were it said
        // again, the ease would not start over).
        let before = lighting
        lighting.light(2, at: 100.05, filled: allFilled)
        XCTAssertEqual(lighting, before)
    }

    /// From one place to the next: the old one eases back while the new one eases in, each
    /// from where it is. Nothing jumps, so nothing flickers.
    func testGoingFromOnePlaceToTheNextNeverJumps() {
        var lighting = Drops.Lighting()
        lighting.light(2, at: 100, filled: allFilled)
        // On to the next place before the first is fully lit.
        let atChange = lighting.amounts(at: 100.05)
        lighting.light(3, at: 100.05, filled: allFilled)
        XCTAssertEqual(lighting.amounts(at: 100.05), atChange, "the moment of the change shows what was there")
        var last = atChange
        for step in 1...140 {
            let now = lighting.amounts(at: 100.05 + Double(step) / 1000)
            for place in 0..<8 {
                XCTAssertLessThan(abs(now[place] - last[place]), 0.04, "place \(place) at step \(step)")
            }
            XCTAssertLessThanOrEqual(now[2], last[2], "the old place only fades")
            XCTAssertGreaterThanOrEqual(now[3], last[3], "the new one only grows")
            last = now
        }
        XCTAssertEqual(last, lit(3))
        // Back to nothing: the lit place eases out.
        lighting.light(nil, at: 200, filled: allFilled)
        XCTAssertEqual(lighting.amounts(at: 200)[3], 1)
        XCTAssertLessThan(lighting.amounts(at: 200.06)[3], 0.2)
        XCTAssertEqual(lighting.amounts(at: 200.12), [CGFloat](repeating: 0, count: 8))
    }

    /// "Reduce motion": lit is lit at once, with no way there.
    func testWithReduceMotionLightingChangesAtOnce() {
        var lighting = Drops.Lighting()
        lighting.light(5, at: 100, filled: allFilled, eased: false)
        XCTAssertEqual(lighting.amounts(at: 100), lit(5))
        XCTAssertTrue(lighting.isSettled(at: 100))
        lighting.light(6, at: 100.01, filled: allFilled, eased: false)
        XCTAssertEqual(lighting.amounts(at: 100.01), lit(6))
        lighting.light(nil, at: 100.02, filled: allFilled, eased: false)
        XCTAssertEqual(lighting.amounts(at: 100.02), [CGFloat](repeating: 0, count: 8))
    }
}

// MARK: - The drops on the panel

final class ShortcutRingDropsPanelTests: XCTestCase {

    /// Frames that come when the test says so.
    private final class Frames: ShortcutRingFrames {
        var stopped = false
        func stop() { stopped = true }
    }

    private final class Rig {
        let presenter = ShortcutRingPanelPresenter()
        var now: TimeInterval = 0
        var frames: [Frames] = []
        var deadlines: [(delay: TimeInterval, work: () -> Void)] = []
        var face = ShortcutRingFace(.default)

        init(appearance: ShortcutRingAppearance) {
            presenter.orderFront = { _ in }
            presenter.appearance = { appearance }
            presenter.clock = { [unowned self] in self.now }
            presenter.startFrames = { [unowned self] _, _ in
                let frames = Frames()
                self.frames.append(frames)
                return frames
            }
            presenter.after = { [unowned self] delay, work in
                self.deadlines.append((delay, work))
            }
        }

        func show(lit: Int? = nil) {
            let screen = ShortcutRingScreen(
                frame: CGRect(x: 0, y: 0, width: 1512, height: 982), usable: CGRect(x: 0, y: 32, width: 1512, height: 950)
            )
            presenter.show(face, centre: CGPoint(x: 400, y: 300), screen: screen, lit: lit, takesClicks: false)
        }

        var drops: ShortcutRingDropsView {
            return presenter.stage!.dropsView!
        }

        /// The next frame of the screen, `seconds` later.
        func frame(after seconds: TimeInterval) {
            now += seconds
            presenter.step()
        }
    }

    private var filled: [Bool] { return ShortcutRingFace(.default).filled }

    // MARK: What the drops are made of

    /// Liquid Glass where the system has it, the blurred material before that; drawn
    /// plainly whenever transparency is not wanted or outlines are, on every system.
    func testTheMaterialFollowsTheSystemAndTheAccessibilitySettings() {
        XCTAssertEqual(ShortcutRingAppearance(hasLiquidGlass: true).material, .glass)
        XCTAssertEqual(ShortcutRingAppearance(hasLiquidGlass: false).material, .blur)
        for hasLiquidGlass in [true, false] {
            XCTAssertEqual(ShortcutRingAppearance(reducesTransparency: true, hasLiquidGlass: hasLiquidGlass).material, .drawn)
            XCTAssertEqual(ShortcutRingAppearance(increasesContrast: true, hasLiquidGlass: hasLiquidGlass).material, .drawn)
            XCTAssertEqual(
                ShortcutRingAppearance(reducesTransparency: true, increasesContrast: true, hasLiquidGlass: hasLiquidGlass).material,
                .drawn
            )
            // "Reduce motion" is about movement, not about what the drops are made of.
            XCTAssertEqual(
                ShortcutRingAppearance(reducesMotion: true, hasLiquidGlass: hasLiquidGlass).material,
                hasLiquidGlass ? .glass : .blur
            )
        }
        var onThisSystem = false
        if #available(macOS 26.0, *) {
            onThisSystem = true
        }
        XCTAssertEqual(ShortcutRingAppearance.system.hasLiquidGlass, onThisSystem)
    }

    /// What the panel shows is the pure function's answer for the time since it opened,
    /// frame after frame; once the drops rest, no more frames are asked for.
    func testThePanelShowsTheOpeningFrameByFrameAndThenStops() throws {
        let rig = Rig(appearance: ShortcutRingAppearance())
        rig.show()
        XCTAssertEqual(rig.drops.drops, ShortcutRingDrops.frame(at: 0, filled: filled))
        XCTAssertTrue(rig.presenter.isMoving)
        XCTAssertEqual(rig.frames.count, 1)

        rig.frame(after: 0.05)
        XCTAssertEqual(rig.drops.drops, ShortcutRingDrops.frame(at: 0.05, filled: filled))
        // The first place's drop is on its way up from the ring's middle, and what stands
        // in it is with it, as small as the drop.
        let canvas = ShortcutRingGeometry.canvasSide
        let circle = try XCTUnwrap(rig.drops.circle(ofDrop: 0))
        XCTAssertEqual(circle.midX, canvas / 2, accuracy: 0.001)
        XCTAssertGreaterThan(circle.midY, canvas / 2 + 20)
        XCTAssertLessThan(circle.midY, canvas / 2 + ShortcutRingGeometry.placeRadius)
        let content = rig.drops.contents[0]
        XCTAssertEqual(content.frame.midX, circle.midX, accuracy: 0.001)
        XCTAssertEqual(content.frame.midY, circle.midY, accuracy: 0.001)
        XCTAssertLessThan(content.frame.width, content.side)
        XCTAssertEqual(content.bounds.width, content.side, accuracy: 0.001, "drawn once, scaled by its frame")
        XCTAssertEqual(content.side, 56)
        XCTAssertTrue(rig.presenter.isMoving)

        rig.frame(after: 0.31)
        XCTAssertEqual(rig.drops.drops, ShortcutRingDrops.settled(filled: filled))
        XCTAssertFalse(rig.presenter.isMoving, "nothing runs once the drops rest")
        XCTAssertTrue(rig.frames[0].stopped)
        for (index, content) in rig.drops.contents.enumerated() {
            let circle = try XCTUnwrap(rig.drops.circle(ofDrop: index))
            XCTAssertEqual(content.frame.midX, circle.midX, accuracy: 0.001)
            XCTAssertEqual(content.frame.midY, circle.midY, accuracy: 0.001)
            XCTAssertEqual(content.frame.width, content.side, accuracy: 0.001)
            XCTAssertEqual(content.alphaValue, 1)
        }
        // The top place stands above the middle on the screen (AppKit's y grows upwards).
        XCTAssertEqual(try XCTUnwrap(rig.drops.circle(ofDrop: 0)).midY, canvas / 2 + ShortcutRingGeometry.placeRadius, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(rig.drops.circle(ofDrop: 8)).width, 88)
        rig.presenter.hide()
    }

    /// A display that sends no frame (it sleeps) must not leave a ring that takes clicks
    /// and is not seen: half a second after it opened everything is in its place.
    func testWithoutAnyFrameTheRingStandsAfterHalfASecond() throws {
        let rig = Rig(appearance: ShortcutRingAppearance())
        rig.show()
        XCTAssertEqual(rig.deadlines.count, 1)
        XCTAssertEqual(rig.deadlines[0].delay, 0.5, accuracy: 0.001)
        XCTAssertLessThanOrEqual(ShortcutRingDrops.openDuration, 0.5)
        // No frame came, and the clock is of no help either.
        rig.deadlines[0].work()
        XCTAssertEqual(rig.drops.drops, ShortcutRingDrops.settled(filled: filled))
        XCTAssertFalse(rig.presenter.isMoving)
        XCTAssertTrue(rig.frames[0].stopped)
        rig.presenter.hide()

        // The deadline of a ring that is gone, or of the ring before this one, does nothing.
        rig.show()
        rig.presenter.hide()
        rig.show()
        let start = rig.drops.drops
        rig.deadlines[1].work()
        XCTAssertEqual(rig.drops.drops, start)
        XCTAssertTrue(rig.presenter.isMoving)
        rig.presenter.hide()
        rig.deadlines[2].work()
        XCTAssertFalse(rig.presenter.isMoving)
    }

    /// The ring is used from the first frame. Shown with a place lit, that place is lit at
    /// once; lit a moment later, its drop is lit while it travels, and the hub names it.
    func testAPlaceIsLitFromTheFirstFrameAndWhileItsDropTravels() throws {
        let rig = Rig(appearance: ShortcutRingAppearance())
        rig.show(lit: 2)
        XCTAssertEqual(rig.drops.drops?.places[2].lit, 1)
        XCTAssertEqual(rig.drops.title, rig.face.places[2].title)
        XCTAssertEqual(rig.drops.contents[2].lit, 1)
        rig.presenter.hide()

        rig.show()
        XCTAssertNil(rig.drops.title)
        rig.frame(after: 0.04)
        rig.presenter.light(0)
        XCTAssertEqual(rig.drops.title, rig.face.places[0].title, "the name is there at once")
        rig.frame(after: 0.03)
        let travelling = try XCTUnwrap(rig.drops.drops?.places[0])
        XCTAssertGreaterThan(travelling.lit, 0.5)
        XCTAssertLessThan(travelling.grow, 1.05)
        XCTAssertEqual(rig.drops.contents[0].lit, travelling.lit)
        rig.frame(after: 0.40)
        XCTAssertEqual(rig.drops.drops, ShortcutRingDrops.settled(filled: filled, lit: 0))
        XCTAssertFalse(rig.presenter.isMoving)
        rig.presenter.hide()
    }

    /// At rest a change of the lit place asks for frames again, for an eighth of a second,
    /// and has its own deadline; the same place again asks for nothing.
    func testLightingAPlaceMovesTheRingForAnEighthOfASecond() throws {
        let rig = Rig(appearance: ShortcutRingAppearance())
        rig.show()
        rig.frame(after: 0.4)
        XCTAssertFalse(rig.presenter.isMoving)
        XCTAssertEqual(rig.frames.count, 1)

        rig.presenter.light(5)
        XCTAssertTrue(rig.presenter.isMoving)
        XCTAssertEqual(rig.frames.count, 2)
        XCTAssertEqual(rig.deadlines.count, 2)
        XCTAssertLessThanOrEqual(rig.deadlines[1].delay, 0.25)
        XCTAssertGreaterThan(rig.deadlines[1].delay, ShortcutRingDrops.litDuration)
        rig.presenter.light(5)
        XCTAssertEqual(rig.frames.count, 2)
        XCTAssertEqual(rig.deadlines.count, 2, "the same place again: nothing new")

        rig.frame(after: 0.05)
        rig.presenter.light(6)
        XCTAssertEqual(rig.frames.count, 2, "frames are already coming")
        rig.frame(after: 0.02)
        let between = try XCTUnwrap(rig.drops.drops)
        XCTAssertGreaterThan(between.places[5].lit, 0)
        XCTAssertGreaterThan(between.places[6].lit, 0)
        XCTAssertEqual(rig.drops.title, rig.face.places[6].title)
        rig.frame(after: 0.2)
        XCTAssertEqual(rig.drops.drops, ShortcutRingDrops.settled(filled: filled, lit: 6))
        XCTAssertFalse(rig.presenter.isMoving)
        XCTAssertTrue(rig.frames[1].stopped)

        // Without a frame the lit place still shows by its deadline.
        rig.presenter.light(1)
        rig.now += 0.3
        try XCTUnwrap(rig.deadlines.last).work()
        XCTAssertEqual(rig.drops.drops, ShortcutRingDrops.settled(filled: filled, lit: 1))
        XCTAssertFalse(rig.presenter.isMoving)

        // A ring that is gone lights nothing and asks for nothing.
        rig.presenter.hide()
        rig.presenter.light(3)
        XCTAssertFalse(rig.presenter.isMoving)
        XCTAssertEqual(rig.frames.count, 3)
    }

    /// "Reduce motion": everything is in its place when the ring appears, a place is lit
    /// at once, and no frame and no deadline is ever asked for.
    func testWithReduceMotionNothingMoves() {
        let rig = Rig(appearance: ShortcutRingAppearance(reducesMotion: true))
        rig.show()
        XCTAssertEqual(rig.drops.drops, ShortcutRingDrops.settled(filled: filled))
        rig.presenter.light(4)
        XCTAssertEqual(rig.drops.drops, ShortcutRingDrops.settled(filled: filled, lit: 4))
        XCTAssertEqual(rig.drops.title, rig.face.places[4].title)
        rig.presenter.light(nil)
        XCTAssertEqual(rig.drops.drops, ShortcutRingDrops.settled(filled: filled))
        XCTAssertNil(rig.drops.title)
        XCTAssertFalse(rig.presenter.isMoving)
        XCTAssertTrue(rig.frames.isEmpty)
        XCTAssertTrue(rig.deadlines.isEmpty)
        rig.presenter.hide()
    }

    /// An empty place shows nothing in its drop and never lights on the panel either.
    func testAnEmptyPlaceShowsNothingAndNeverLightsOnThePanel() {
        var ring = ShortcutRingSettings.default
        ring[3] = .empty
        let rig = Rig(appearance: ShortcutRingAppearance(reducesMotion: true))
        rig.face = ShortcutRingFace(ring)
        rig.show(lit: 3)
        XCTAssertTrue(rig.drops.contents[3].isHidden)
        XCTAssertFalse(rig.drops.contents[2].isHidden)
        XCTAssertNil(rig.presenter.lighting.target)
        XCTAssertNil(rig.drops.title)
        XCTAssertEqual(rig.drops.drops?.places[3].diameter, 14)
        rig.presenter.light(3)
        XCTAssertEqual(rig.drops.drops?.places[3].lit, 0)
        rig.presenter.hide()
    }

    /// Each material is built of its own views and of nothing of the others; the drops
    /// are made anew only when the system's settings changed between two rings.
    func testEachMaterialHasItsOwnViews() throws {
        let drawn = Rig(appearance: ShortcutRingAppearance(reducesTransparency: true, hasLiquidGlass: true))
        drawn.show()
        XCTAssertEqual(drawn.drops.material, .drawn)
        XCTAssertNil(drawn.drops.blurView)
        XCTAssertNil(drawn.drops.glassBodies)
        XCTAssertEqual(drawn.drops.bodiesView?.style.backdrop, .drawn)
        XCTAssertEqual(drawn.drops.bodiesView?.drops, drawn.drops.drops)
        XCTAssertTrue(drawn.drops.contents.allSatisfy { $0.superview === drawn.drops && !$0.usesLabelColour })
        let first = drawn.drops
        drawn.presenter.hide()
        drawn.show()
        XCTAssertTrue(drawn.drops === first, "the same drops for the next ring")
        drawn.presenter.hide()

        let blur = Rig(appearance: ShortcutRingAppearance())
        blur.show()
        XCTAssertEqual(blur.drops.material, .blur)
        let material = try XCTUnwrap(blur.drops.blurView)
        XCTAssertEqual(material.material, .hudWindow)
        XCTAssertEqual(material.blendingMode, .behindWindow)
        XCTAssertEqual(material.state, .active)
        XCTAssertEqual(material.frame, blur.drops.bounds, "one material view for all nine drops")
        XCTAssertNotNil(material.maskImage, "cut to the drops")
        XCTAssertEqual(blur.drops.bodiesView?.style.backdrop, .material)
        XCTAssertNil(blur.drops.glassBodies)
        // The mask follows the drops.
        let atStart = material.maskImage
        blur.frame(after: 0.05)
        XCTAssertFalse(material.maskImage === atStart)
        blur.frame(after: 0.4)
        let atRest = material.maskImage
        blur.presenter.step()
        XCTAssertTrue(material.maskImage === atRest, "and is not made again while nothing changes")
        blur.presenter.hide()

        if #available(macOS 26.0, *) {
            let glass = Rig(appearance: ShortcutRingAppearance(hasLiquidGlass: true))
            glass.show(lit: 1)
            XCTAssertEqual(glass.drops.material, .glass)
            XCTAssertNil(glass.drops.blurView)
            XCTAssertNil(glass.drops.bodiesView)
            let bodies = try XCTUnwrap(glass.drops.glassBodies as? ShortcutRingGlassBodies)
            XCTAssertEqual(bodies.container.spacing, ShortcutRingDrops.glassSpacing)
            XCTAssertTrue(bodies.container.contentView === bodies.field)
            XCTAssertEqual(bodies.drops.count, 9)
            glass.frame(after: 0.4)
            // Whatever the glass views do when they are laid out, the drops stay where
            // they were put and their content views fill them.
            glass.presenter.stage?.layoutSubtreeIfNeeded()
            for (index, drop) in bodies.drops.enumerated() {
                XCTAssertTrue(drop.isDescendant(of: try XCTUnwrap(bodies.container.contentView)))
                let circle = try XCTUnwrap(glass.drops.circle(ofDrop: index))
                XCTAssertEqual(drop.frame, circle)
                XCTAssertEqual(drop.cornerRadius, circle.width / 2, "round")
                XCTAssertEqual(drop.alphaValue, 1, "glass is never faded")
                // What stands in the drop is in the glass's content view, in its middle.
                let content = glass.drops.contents[index]
                XCTAssertTrue(content.superview === drop.contentView)
                XCTAssertEqual(drop.contentView?.frame, NSRect(origin: .zero, size: circle.size))
                XCTAssertTrue(content.usesLabelColour)
                XCTAssertEqual(content.frame.midX, circle.width / 2, accuracy: 0.001)
                XCTAssertEqual(content.frame.midY, circle.height / 2, accuracy: 0.001)
            }
            XCTAssertNotNil(bodies.drops[1].tintColor, "the lit drop is tinted")
            XCTAssertNil(bodies.drops[0].tintColor)
            XCTAssertNil(bodies.drops[8].tintColor)
            glass.presenter.light(nil)
            glass.frame(after: 0.2)
            XCTAssertNil(bodies.drops[1].tintColor)
            glass.presenter.hide()

            // The settings changed between two rings: other drops, and the old ones gone.
            let first = glass.drops
            glass.presenter.appearance = { ShortcutRingAppearance(increasesContrast: true, hasLiquidGlass: true) }
            glass.show()
            XCTAssertEqual(glass.drops.material, .drawn)
            XCTAssertNil(first.superview)
            XCTAssertEqual(glass.presenter.stage?.subviews.count, 1)
            XCTAssertEqual(glass.drops.bodiesView?.style.increasesContrast, true)
            glass.presenter.hide()
        }
    }

    /// The mask of the blurred material is the nine circles of the moment and nothing else.
    func testTheBlursMaskIsTheDropsCircles() throws {
        let rest = ShortcutRingDrops.settled(filled: filled, lit: 2)
        let side = ShortcutRingGeometry.canvasSide
        let image = ShortcutRingDropsView.mask(rest, size: NSSize(width: side, height: side))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(side), pixelsHigh: Int(side), bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        /// The mask's alpha at an offset from the ring's middle (y downwards, as the geometry's).
        func alpha(_ offset: CGPoint) -> CGFloat {
            return bitmap.colorAt(x: Int(side / 2 + offset.x), y: Int(side / 2 + offset.y))?.alphaComponent ?? -1
        }
        XCTAssertEqual(alpha(.zero), 1, accuracy: 0.01, "the hub")
        for place in 0..<8 {
            XCTAssertEqual(alpha(rest.places[place].offset), 1, accuracy: 0.01, "place \(place)")
        }
        // Between the hub and a place, between two places and outside the ring: nothing.
        XCTAssertEqual(alpha(CGPoint(x: 0, y: -50.5)), 0, accuracy: 0.01)
        XCTAssertEqual(alpha(ShortcutRingGeometry.offset(ofPlace: 5, radius: 82 + 31)), 0, accuracy: 0.01)
        let between = ShortcutRingGeometry.angle(ofPlace: 4) + .pi / 8
        XCTAssertEqual(alpha(CGPoint(x: sin(between) * 82, y: -cos(between) * 82)), 0, accuracy: 0.01)
        XCTAssertEqual(alpha(CGPoint(x: -130, y: 130)), 0, accuracy: 0.01)
        // The lit drop is larger and farther out: the material is under all of it.
        XCTAssertEqual(alpha(ShortcutRingGeometry.offset(ofPlace: 2, radius: 88 + 30)), 1, accuracy: 0.01)
        XCTAssertEqual(alpha(ShortcutRingGeometry.offset(ofPlace: 6, radius: 82 + 28)), 0, accuracy: 0.01)
    }
}
