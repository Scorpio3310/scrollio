//
//  MouseArtworkTests.swift
//  MosTests
//
//  The drawing per model: which drawing a connected mouse gets, which parts each drawing
//  has and where, the two views of the MX Master 4 and 3 and the turn between them, and how a
//  part the shown mouse does not have is shown (the Buttons pane's pictures and "Which
//  Button Is This?").
//

import XCTest
@testable import Scrollio_Debug

final class MouseArtworkTests: XCTestCase {

    // MARK: - Which drawing

    func testTheDrawingFollowsTheMousesName() {
        let cases: [(String?, MouseArtworkModel)] = [
            ("MX Master 4", .mxMaster4),
            ("MX Master 4 for Business", .mxMaster4),
            ("MX Master 3", .mxMaster3),
            ("MX Master 3S", .mxMaster3),
            ("MX Master 3S For Mac", .mxMaster3),
            ("MX Master 3 for Mac", .mxMaster3),
            ("Wireless Mouse MX Master 3", .mxMaster3),
            ("mx master 3s", .mxMaster3),
            ("MX Master 2S", .generic),
            ("MX Master", .generic),
            ("MX Anywhere 2S", .generic),
            ("MX Master 45", .generic),
            ("Master 4", .generic),
            ("M720 Triathlon", .generic),
            ("", .generic),
            (nil, .generic),
        ]
        for (name, model) in cases {
            XCTAssertEqual(MouseArtworkModel.model(forDeviceName: name), model, name ?? "nil")
        }
    }

    // MARK: - The parts of each drawing

    func testEachDrawingHasItsOwnParts() {
        // (The button on the MX Vertical's top is that mouse's alone: MouseArtworkMoreMiceTests.)
        XCTAssertEqual(MouseArtworkModel.mxMaster4.parts, MouseArtworkPart.allCases.filter { $0 != .pointerSpeed })
        XCTAssertEqual(Set(MouseArtworkModel.mxMaster3.parts), Set(MouseArtworkPart.allCases).subtracting([.thumbPanel, .pointerSpeed]))
        XCTAssertEqual(Set(MouseArtworkModel.generic.parts), [.body, .left, .right, .wheel, .back, .forward])
        for model in MouseArtworkModel.allCases {
            for schematic in [false, true] {
                // A part the mouse has has a shape in at least one view, and one in the
                // view it lights in; a part it does not have has none anywhere.
                for part in MouseArtworkPart.allCases {
                    let shapes = model.viewpoints.map { MouseArtworkShapes(model: model, schematic: schematic, viewpoint: $0) }
                    XCTAssertEqual(shapes.contains { $0.shape(of: part) != nil }, model.has(part), "\(model) \(part)")
                    let lighting = MouseArtworkShapes(model: model, schematic: schematic, lighting: part)
                    XCTAssertEqual(lighting.shape(of: part) != nil, model.has(part), "\(model) \(part) where it lights")
                    for view in shapes {
                        XCTAssertEqual(view.lights(part), model.has(part) && view.viewpoint == lighting.viewpoint,
                                       "\(model) \(part) lights in one view")
                        guard let shape = view.shape(of: part) else {
                            XCTAssertFalse(view.lights(part), "\(model) \(part) lights only where it has a shape")
                            continue
                        }
                        XCTAssertFalse(shape.isEmpty, "\(model) \(part)")
                        XCTAssertTrue(view.outline().bounds.intersects(shape.bounds), "\(model) \(part) is on the mouse")
                    }
                }
            }
        }
    }

    // MARK: - The views

    /// From above for every mouse; the MX Master 4 and 3 also from the thumb side. What the
    /// thumb works lights there (on the MX Master 3 that is the thumb wheel and the two side
    /// buttons; its gesture button is the thumb rest itself, pressed down, and lights from
    /// above; it has no thumb panel), the rest from above; nothing lit, the whole mouse, or
    /// a part the mouse does not have: from above.
    func testAPartLightsInOneViewOfTheDrawing() {
        XCTAssertEqual(MouseArtworkModel.mxMaster4.viewpoints, [.above, .thumbSide])
        XCTAssertEqual(MouseArtworkModel.mxMaster3.viewpoints, [.above, .thumbSide])
        XCTAssertEqual(MouseArtworkModel.generic.viewpoints, [.above])
        XCTAssertTrue(MouseArtworkModel.mxMaster4.hasSideView)
        XCTAssertTrue(MouseArtworkModel.mxMaster3.hasSideView)
        XCTAssertFalse(MouseArtworkModel.generic.hasSideView)
        let side: Set<MouseArtworkPart> = [.thumbWheel, .forward, .back, .gesture, .thumbPanel]
        for part in MouseArtworkPart.allCases {
            XCTAssertEqual(MouseArtworkModel.mxMaster4.viewpoint(lighting: part), side.contains(part) ? .thumbSide : .above, "\(part)")
            XCTAssertEqual(MouseArtworkModel.mxMaster3.viewpoint(lighting: part),
                           side.contains(part) && part != .thumbPanel && part != .gesture ? .thumbSide : .above, "\(part)")
            XCTAssertEqual(MouseArtworkModel.generic.viewpoint(lighting: part), .above, "\(part)")
        }
        XCTAssertEqual(MouseArtworkModel.mxMaster3.sideParts, [.thumbWheel, .forward, .back])
        for model in MouseArtworkModel.allCases {
            XCTAssertEqual(model.viewpoint(lighting: nil), .above)
            XCTAssertTrue(model.sideParts.isSubset(of: Set(model.parts)))
            XCTAssertEqual(model.sideParts.isEmpty, !model.hasSideView)
            // A view the mouse does not have is drawn from above.
            XCTAssertEqual(MouseArtworkShapes(model: model, viewpoint: .thumbSide).viewpoint, model.hasSideView ? .thumbSide : .above)
        }
    }

    /// The MX Master 4 from above: the wheel between the two buttons, the small button
    /// behind them on the palm shell, the thumb wheel at the left shoulder right behind the
    /// left button, the thumb panel on the wing. The three side buttons are under the
    /// overhang: they are not in this view.
    func testTheMasterFourFromAbove() throws {
        for schematic in [false, true] {
            let above = MouseArtworkShapes(model: .mxMaster4, schematic: schematic)
            for hidden in [MouseArtworkPart.back, .forward, .gesture] {
                XCTAssertNil(above.shape(of: hidden), "\(hidden) does not show from above")
            }
            let left = try XCTUnwrap(above.shape(of: .left)).bounds
            let right = try XCTUnwrap(above.shape(of: .right)).bounds
            let wheel = try XCTUnwrap(above.shape(of: .wheel)).bounds
            let modeShift = try XCTUnwrap(above.shape(of: .modeShift)).bounds
            let thumbWheel = try XCTUnwrap(above.shape(of: .thumbWheel)).bounds
            let panel = try XCTUnwrap(above.shape(of: .thumbPanel)).bounds
            XCTAssertLessThan(left.minY, right.minY, "the left button reaches further forward")
            XCTAssertEqual(left.maxX, right.minX, accuracy: 0.5, "one split")
            XCTAssertEqual(wheel.midX, left.maxX, accuracy: 0.5, "the wheel on the split")
            XCTAssertGreaterThan(modeShift.minY, wheel.maxY, "behind the wheel")
            XCTAssertEqual(modeShift.midX, wheel.midX, accuracy: 0.5)
            if !schematic {
                XCTAssertGreaterThan(modeShift.minY, right.maxY - 1, "behind where the buttons end")
                XCTAssertGreaterThan(thumbWheel.minY, left.maxY - 0.5, "right behind the left button")
            }
            XCTAssertLessThan(thumbWheel.maxX, wheel.minX, "at the left shoulder")
            XCTAssertLessThan(panel.minX, thumbWheel.minX, "the wing stands out to the left")
            XCTAssertGreaterThan(panel.maxY, thumbWheel.maxY, "and reaches further back")
            XCTAssertLessThan(above.outline().bounds.minX, above.mainBody.minX - 15, "the wing")
        }
    }

    /// The MX Master 4 from the thumb side, front to the left: the thumb wheel on top, right
    /// under it Forward (in front) and Back in a row, the gesture button in front of them
    /// and a little lower, the thumb panel beneath them all. This is what the drawing from
    /// above alone got wrong: there the thumb wheel stood in front of three buttons.
    func testTheMasterFourFromTheThumbSide() throws {
        for schematic in [false, true] {
            let side = MouseArtworkShapes(model: .mxMaster4, schematic: schematic, viewpoint: .thumbSide)
            for hidden in [MouseArtworkPart.left, .right, .wheel, .modeShift] {
                XCTAssertNil(side.shape(of: hidden), "\(hidden) does not light from the side")
            }
            let outline = side.outline().bounds
            XCTAssertGreaterThan(outline.width, 1.8 * outline.height, "the mouse lies across")
            let thumbWheel = try XCTUnwrap(side.shape(of: .thumbWheel))
            let forward = try XCTUnwrap(side.shape(of: .forward))
            let back = try XCTUnwrap(side.shape(of: .back))
            let gesture = try XCTUnwrap(side.shape(of: .gesture))
            let panel = try XCTUnwrap(side.shape(of: .thumbPanel))
            // The thumb wheel is over both buttons of the row, not in front of them.
            for (name, button) in [("Forward", forward), ("Back", back)] {
                XCTAssertGreaterThan(button.bounds.midY, thumbWheel.bounds.midY, "\(name) under the thumb wheel")
                XCTAssertGreaterThan(button.bounds.midX, thumbWheel.bounds.minX, "\(name) under the thumb wheel, not before it")
                XCTAssertLessThan(button.bounds.midX, thumbWheel.bounds.maxX + (schematic ? 8 : 0), "\(name) under the thumb wheel, not behind it")
                XCTAssertTrue(button.cgPath.intersection(thumbWheel.cgPath).isEmpty, "\(name) apart from the thumb wheel")
            }
            XCTAssertLessThan(forward.bounds.midX, back.bounds.midX, "Forward in front of Back")
            XCTAssertLessThan(gesture.bounds.midX, forward.bounds.minX, "the gesture button in front of them")
            XCTAssertGreaterThan(gesture.bounds.midY, forward.bounds.midY, "and a little lower")
            XCTAssertLessThan(gesture.bounds.midX, thumbWheel.bounds.minX, "in front of the thumb wheel, not under it")
            for (first, second) in [(gesture, forward), (forward, back), (gesture, back)] {
                XCTAssertTrue(first.cgPath.intersection(second.cgPath).isEmpty, "the three buttons are apart")
                // In a row's small picture front, middle and rear can be told apart: their
                // middles are at least three points from each other there.
                if schematic {
                    let unit = ButtonsMouseMiniature.mouseHeight / MouseArtworkShapes.grid.height
                    let distance = hypot(first.bounds.midX - second.bounds.midX, first.bounds.midY - second.bounds.midY) * unit
                    XCTAssertGreaterThanOrEqual(distance, 3, "apart in the small pictures")
                }
            }
            for button in [gesture, forward, back] {
                XCTAssertGreaterThan(panel.bounds.midY, button.bounds.midY, "the thumb panel beneath")
                XCTAssertTrue(panel.cgPath.intersection(button.cgPath).isEmpty, "and apart from the buttons")
                XCTAssertGreaterThan(panel.bounds.width * panel.bounds.height, 4 * button.bounds.width * button.bounds.height,
                                     "the thumb panel is the large one")
            }
        }
    }

    /// The MX Master 3 from above: the wheel in its long slot between the two buttons, the
    /// small button behind the slot, the thumb wheel along the left shoulder under the left
    /// button's end, and the thumb wing with the gesture pad: the thumb rest itself is that
    /// button, in the middle of the wing. Its side buttons are under the overhang: they are
    /// not in this view.
    func testTheMasterThreeFromAbove() throws {
        for schematic in [false, true] {
            let above = MouseArtworkShapes(model: .mxMaster3, schematic: schematic)
            for hidden in [MouseArtworkPart.back, .forward, .thumbPanel] {
                XCTAssertNil(above.shape(of: hidden), "\(hidden) does not show from above")
            }
            // The gesture pad: on the wing, outside the thumb wheel, in the middle of the
            // wing's length, and the large part of the thumb's side.
            let pad = try XCTUnwrap(above.shape(of: .gesture))
            let roller = try XCTUnwrap(above.shape(of: .thumbWheel))
            let whole = above.outline()
            XCTAssertLessThan(pad.bounds.maxX, above.mainBody.minX, "on the wing, not on the body")
            XCTAssertTrue(pad.cgPath.intersection(roller.cgPath).isEmpty, "beside the thumb wheel, not under it")
            for corner in [NSPoint(x: pad.bounds.midX, y: pad.bounds.minY + 1), NSPoint(x: pad.bounds.midX, y: pad.bounds.maxY - 1),
                           NSPoint(x: pad.bounds.minX + 1, y: pad.bounds.midY), NSPoint(x: pad.bounds.maxX - 1, y: pad.bounds.midY)] {
                XCTAssertTrue(whole.contains(corner), "the pad is on the mouse")
            }
            let wing = NSRect(x: whole.bounds.minX, y: 46, width: above.mainBody.minX - whole.bounds.minX, height: 57)
            XCTAssertEqual(pad.bounds.midY, wing.midY, accuracy: 6, "in the middle of the wing, not at its front")
            XCTAssertGreaterThan(pad.bounds.height, 0.5 * wing.height, "the whole rest is the button")
            let left = try XCTUnwrap(above.shape(of: .left)).bounds
            let right = try XCTUnwrap(above.shape(of: .right)).bounds
            let wheel = try XCTUnwrap(above.shape(of: .wheel)).bounds
            let modeShift = try XCTUnwrap(above.shape(of: .modeShift)).bounds
            let thumbWheel = try XCTUnwrap(above.shape(of: .thumbWheel)).bounds
            XCTAssertLessThan(left.minY, right.minY, "the left button reaches further forward")
            XCTAssertEqual(left.maxX, right.minX, accuracy: 0.5, "one split")
            XCTAssertEqual(wheel.midX, left.maxX, accuracy: 0.5, "the wheel on the split")
            XCTAssertGreaterThan(modeShift.minY, wheel.maxY, "behind the wheel")
            XCTAssertEqual(modeShift.midX, wheel.midX, accuracy: 0.5)
            XCTAssertLessThan(thumbWheel.maxX, wheel.minX, "at the left shoulder")
            XCTAssertGreaterThan(thumbWheel.midY, left.maxY, "behind where the left button ends")
            if !schematic {
                XCTAssertGreaterThan(above.wellRect.maxY, wheel.maxY + 4, "the wheel's slot reaches back to where the buttons end")
                XCTAssertLessThan(thumbWheel.maxX, above.mainBody.minX + 1.5, "outside the body's edge, in the wing's notch")
            }
            XCTAssertLessThan(above.outline().bounds.minX, above.mainBody.minX - 15, "the wing")
        }
        // Not the MX Master 4's outline: the wing leaves the body further forward.
        let three = MouseArtworkShapes(model: .mxMaster3).outline()
        let four = MouseArtworkShapes(model: .mxMaster4).outline()
        XCTAssertTrue(three.contains(NSPoint(x: 16, y: 50)), "the MX Master 3's wing is there")
        XCTAssertFalse(four.contains(NSPoint(x: 16, y: 50)), "the MX Master 4's is not yet")
    }

    /// The MX Master 3 from the thumb side, front to the left: the thumb wheel on top,
    /// Forward (in front) and Back in a row right under it, and beneath them the thumb rest.
    /// The gesture button is that rest, pressed down: it lights from above, not here.
    func testTheMasterThreeFromTheThumbSide() throws {
        for schematic in [false, true] {
            let side = MouseArtworkShapes(model: .mxMaster3, schematic: schematic, viewpoint: .thumbSide)
            for hidden in [MouseArtworkPart.left, .right, .wheel, .modeShift, .gesture, .thumbPanel] {
                XCTAssertNil(side.shape(of: hidden), "\(hidden) does not light from the side")
            }
            let outline = side.outline().bounds
            XCTAssertGreaterThan(outline.width, 1.8 * outline.height, "the mouse lies across")
            let thumbWheel = try XCTUnwrap(side.shape(of: .thumbWheel))
            let forward = try XCTUnwrap(side.shape(of: .forward))
            let back = try XCTUnwrap(side.shape(of: .back))
            for (name, button) in [("Forward", forward), ("Back", back)] {
                XCTAssertGreaterThan(button.bounds.midY, thumbWheel.bounds.midY, "\(name) under the thumb wheel")
                XCTAssertGreaterThan(button.bounds.midX, thumbWheel.bounds.minX, "\(name) under the thumb wheel, not before it")
                XCTAssertLessThan(button.bounds.minX, thumbWheel.bounds.maxX + (schematic ? 2 : 0), "\(name) under the thumb wheel, not behind it")
                XCTAssertTrue(button.cgPath.intersection(thumbWheel.cgPath).isEmpty, "\(name) apart from the thumb wheel")
            }
            XCTAssertLessThan(forward.bounds.midX, back.bounds.midX, "Forward in front of Back")
            XCTAssertTrue(forward.cgPath.intersection(back.cgPath).isEmpty, "apart")
            if schematic {
                let unit = ButtonsMouseMiniature.mouseHeight / MouseArtworkShapes.grid.height
                let distance = hypot(forward.bounds.midX - back.bounds.midX, forward.bounds.midY - back.bounds.midY) * unit
                XCTAssertGreaterThanOrEqual(distance, 3, "front and rear apart in the small pictures")
            }
            // The pad is this drawing's thumb rest part; its ridge shows from above, on the card.
            let views = try XCTUnwrap(side.views)
            XCTAssertEqual(views.restPart, .gesture)
            XCTAssertNil(views.restRidge, "nothing of the pad from the side")
            XCTAssertFalse(views.hasClearRim)
            let above = try XCTUnwrap(MouseArtworkShapes(model: .mxMaster3, schematic: schematic).views)
            XCTAssertEqual(above.restRidge != nil, !schematic)
        }
    }

    /// The two views are the same mouse at the same size, centred on the same point, so the
    /// drawing can turn from one to the other in place; and everything of every drawing is
    /// inside the canvas the views that show it are sized by.
    func testBothViewsAreTheSameMouseAndFitTheCanvas() {
        for model in MouseArtworkModel.allCases where model.hasSideView {
            let above = MouseArtworkShapes(model: model).outline().bounds
            let side = MouseArtworkShapes(model: model, viewpoint: .thumbSide).outline().bounds
            XCTAssertEqual(side.width, above.height, accuracy: 1, "\(model): as long from the side as from above")
            XCTAssertEqual(above.midX, MouseArtworkShapes.centre.x, accuracy: 1, "\(model)")
            XCTAssertEqual(above.midY, MouseArtworkShapes.centre.y, accuracy: 1, "\(model)")
            XCTAssertEqual(side.midX, MouseArtworkShapes.centre.x, accuracy: 1, "\(model)")
            XCTAssertEqual(side.midY, MouseArtworkShapes.centre.y, accuracy: 1, "\(model)")
        }
        XCTAssertEqual(MouseArtworkShapes.canvas.midX, MouseArtworkShapes.centre.x)
        XCTAssertEqual(MouseArtworkShapes.canvas.midY, MouseArtworkShapes.centre.y)
        for model in MouseArtworkModel.allCases {
            for viewpoint in model.viewpoints {
                for schematic in [false, true] {
                    let shapes = MouseArtworkShapes(model: model, schematic: schematic, viewpoint: viewpoint)
                    var all = [shapes.outline().bounds]
                    all += MouseArtworkPart.allCases.compactMap { shapes.shape(of: $0)?.bounds }
                    for bounds in all {
                        XCTAssertTrue(MouseArtworkShapes.canvas.contains(bounds), "\(model) \(viewpoint) \(bounds)")
                    }
                    if viewpoint == .above {
                        XCTAssertTrue(NSRect(origin: .zero, size: MouseArtworkShapes.grid).contains(all[0]), "\(model) from above fits the grid")
                    }
                }
            }
        }
    }

    /// The turn: the view from above alone at its start, the one from the thumb side alone
    /// at its end, in between both fading and turned the same way round; a quarter of a
    /// second, eased, and the rest of the way in proportion when it is interrupted.
    func testTheTurnBetweenTheViews() throws {
        XCTAssertEqual(MouseArtworkTurn.duration, 0.25)
        XCTAssertEqual(MouseArtworkTurn.faces(at: 0), [MouseArtworkTurn.Face(viewpoint: .above, alpha: 1, rotation: 0)])
        XCTAssertEqual(MouseArtworkTurn.faces(at: 1), [MouseArtworkTurn.Face(viewpoint: .thumbSide, alpha: 1, rotation: 0)])
        XCTAssertEqual(MouseArtworkTurn.faces(at: -1), MouseArtworkTurn.faces(at: 0))
        XCTAssertEqual(MouseArtworkTurn.faces(at: 2), MouseArtworkTurn.faces(at: 1))
        let middle = MouseArtworkTurn.faces(at: 0.5)
        XCTAssertEqual(middle.map(\.viewpoint), [.above, .thumbSide])
        for face in middle {
            XCTAssertGreaterThan(face.alpha, 0)
            XCTAssertLessThan(face.alpha, 0.5, "neither view is strong while both show")
        }
        // The front swings from up to left: the view that leaves turns anticlockwise, the
        // one that comes arrives from the clockwise side.
        XCTAssertLessThan(middle[0].rotation, 0)
        XCTAssertGreaterThan(middle[1].rotation, 0)
        XCTAssertLessThanOrEqual(abs(middle[0].rotation), MouseArtworkTurn.angle)
        var last: CGFloat = -1
        for step in 0...25 {
            let progress = MouseArtworkTurn.progress(from: 0, to: 1, elapsed: Double(step) / 100)
            XCTAssertGreaterThanOrEqual(progress, last)
            last = progress
            let above = MouseArtworkTurn.face(of: .above, at: progress)?.alpha ?? 0
            let side = MouseArtworkTurn.face(of: .thumbSide, at: progress)?.alpha ?? 0
            XCTAssertGreaterThan(above + side, 0.3, "the mouse never disappears")
        }
        XCTAssertEqual(MouseArtworkTurn.progress(from: 0, to: 1, elapsed: 0), 0)
        XCTAssertEqual(MouseArtworkTurn.progress(from: 0, to: 1, elapsed: 0.25), 1)
        XCTAssertEqual(MouseArtworkTurn.progress(from: 1, to: 0, elapsed: 0.25), 0)
        XCTAssertEqual(MouseArtworkTurn.progress(from: 1, to: 0, elapsed: 0.125), 0.5, accuracy: 1e-9)
        XCTAssertEqual(MouseArtworkTurn.progress(from: 0.5, to: 1, elapsed: 0.125), 1, "half the way takes half the time")
        XCTAssertEqual(MouseArtworkTurn.progress(from: 1, to: 1, elapsed: 0), 1)
        // The drawing turns about its middle.
        let turned = MouseArtworkTurn.transform(for: middle[0], placement: AffineTransform(scale: 2))
        let centre = turned.transform(MouseArtworkShapes.centre)
        XCTAssertEqual(centre.x, 2 * MouseArtworkShapes.centre.x, accuracy: 1e-9)
        XCTAssertEqual(centre.y, 2 * MouseArtworkShapes.centre.y, accuracy: 1e-9)
    }

    /// The cards' drawing turns to the thumb side while a part that lights there is lit and
    /// back from above when another part or none is; at once when it is not to animate
    /// (Reduce Motion), by the clock when it is. The other mice never turn.
    func testTheCardsDrawingTurnsToThePartsView() {
        let artwork = MouseArtworkView()
        artwork.model = .mxMaster4
        XCTAssertEqual(artwork.viewpoint, .above)
        XCTAssertEqual(artwork.turn, 0)
        for (part, viewpoint): (MouseArtworkPart?, MouseArtworkViewpoint) in [
            (.back, .thumbSide), (.wheel, .above), (.thumbWheel, .thumbSide), (.forward, .thumbSide), (nil, .above),
            (.gesture, .thumbSide), (.left, .above), (.thumbPanel, .thumbSide), (.body, .above), (.modeShift, .above),
        ] {
            artwork.setEmphasis(part, animated: false)
            XCTAssertEqual(artwork.viewpoint, viewpoint, "\(String(describing: part))")
            XCTAssertEqual(artwork.turn, viewpoint == .thumbSide ? 1 : 0, "at once")
            XCTAssertFalse(artwork.isTurning, "no animation")
            XCTAssertEqual(artwork.highlights.values.filter { $0.alphaValue == 1 }.map(\.part), part.map { [$0] } ?? [])
            XCTAssertTrue(artwork.highlights.values.allSatisfy { $0.turn == artwork.turn }, "the lit part turns with the drawing")
        }

        // Animated: a quarter of a second by the clock.
        var now: TimeInterval = 100
        artwork.clock = { now }
        artwork.setEmphasis(.back, animated: true)
        XCTAssertEqual(artwork.viewpoint, .thumbSide)
        XCTAssertTrue(artwork.isTurning)
        XCTAssertEqual(artwork.turn, 0, "it starts from above")
        now += 0.1
        artwork.advanceTurn()
        XCTAssertGreaterThan(artwork.turn, 0)
        XCTAssertLessThan(artwork.turn, 1)
        XCTAssertTrue(artwork.isTurning)
        // Another part of the same side: the turn goes on.
        let midway = artwork.turn
        artwork.setEmphasis(.forward, animated: true)
        XCTAssertEqual(artwork.turn, midway)
        now += 0.15
        artwork.advanceTurn()
        XCTAssertEqual(artwork.turn, 1)
        XCTAssertFalse(artwork.isTurning, "done after a quarter of a second")
        // A part of the top turns it back; turned round half-way, it goes back from there.
        artwork.setEmphasis(.wheel, animated: true)
        XCTAssertEqual(artwork.viewpoint, .above)
        XCTAssertTrue(artwork.isTurning)
        now += 0.125
        artwork.advanceTurn()
        XCTAssertEqual(artwork.turn, 0.5, accuracy: 1e-9)
        artwork.setEmphasis(.thumbPanel, animated: true)
        XCTAssertEqual(artwork.viewpoint, .thumbSide)
        now += 0.125
        artwork.advanceTurn()
        XCTAssertEqual(artwork.turn, 1, "half the way back in half the time")
        XCTAssertFalse(artwork.isTurning)
        // Nothing lit: back from above. Without animation in mid-turn: there at once.
        artwork.setEmphasis(nil, animated: true)
        XCTAssertTrue(artwork.isTurning)
        artwork.setEmphasis(nil, animated: false)
        XCTAssertEqual(artwork.turn, 0)
        XCTAssertFalse(artwork.isTurning)

        // The plain mouse: its drawing has one view, and stays in it.
        artwork.setEmphasis(.back, animated: false)
        XCTAssertEqual(artwork.turn, 1)
        artwork.model = .generic
        XCTAssertEqual(artwork.viewpoint, .above, "the plain mouse's Back button is in its view from above")
        XCTAssertEqual(artwork.turn, 0)
        XCTAssertEqual(artwork.emphasis, .back, "still lit")
        for part in [MouseArtworkPart.back, .forward, .gesture, .thumbWheel, .thumbPanel] {
            artwork.setEmphasis(part, animated: true)
            XCTAssertEqual(artwork.viewpoint, .above, "\(part)")
            XCTAssertEqual(artwork.turn, 0)
            XCTAssertFalse(artwork.isTurning, "\(part)")
        }
        // The MX Master 3 turns as the MX Master 4 does, for its thumb wheel and its side
        // buttons. Its gesture button is the thumb rest, pressed down: that lights from
        // above and turns nothing. It has no thumb panel to turn for.
        artwork.model = .mxMaster3
        for (part, viewpoint): (MouseArtworkPart, MouseArtworkViewpoint) in [
            (.back, .thumbSide), (.wheel, .above), (.gesture, .above), (.modeShift, .above),
            (.thumbWheel, .thumbSide), (.left, .above), (.forward, .thumbSide), (.thumbPanel, .above),
        ] {
            artwork.setEmphasis(part, animated: false)
            XCTAssertEqual(artwork.viewpoint, viewpoint, "MX Master 3 \(part)")
            XCTAssertEqual(artwork.turn, viewpoint == .thumbSide ? 1 : 0)
        }
        artwork.setEmphasis(.forward, animated: true)
        XCTAssertTrue(artwork.isTurning, "the MX Master 3 turns too")
        artwork.setEmphasis(.forward, animated: false)
        artwork.setEmphasis(.gesture, animated: true)
        XCTAssertTrue(artwork.isTurning, "and back, for its gesture pad on the wing")
        artwork.setEmphasis(.gesture, animated: false)
        XCTAssertEqual(artwork.viewpoint, .above)
        // Back to the MX Master 4 with a side part lit: its side view, at once.
        artwork.setEmphasis(.back, animated: false)
        artwork.model = .mxMaster4
        XCTAssertEqual(artwork.viewpoint, .thumbSide)
        XCTAssertEqual(artwork.turn, 1)
        XCTAssertGreaterThanOrEqual(MouseArtworkView.size.width, MouseArtworkShapes.canvas.width * MouseArtworkView.unit + 2 * MouseArtworkView.margin,
                                    "the view holds the drawing from the side")
    }

    /// The side buttons run front to back, apart from each other at the card's size and in
    /// the small pictures, and on the thumb side: Forward, Back down the left edge of the
    /// plain mouse seen from above (the MX Masters' are in their view from the thumb side:
    /// `testTheMasterFourFromTheThumbSide`, `testTheMasterThreeFromTheThumbSide`).
    func testTheSideButtonsRunFrontToBack() throws {
        for model in [MouseArtworkModel.generic] {
            for schematic in [false, true] {
                let shapes = MouseArtworkShapes(model: model, schematic: schematic)
                let order: [MouseArtworkPart] = [.forward, .back]
                let buttons = try order.map { try XCTUnwrap(shapes.shape(of: $0)?.bounds, "\(model) \($0)") }
                for (front, rear) in zip(buttons, buttons.dropFirst()) {
                    XCTAssertLessThan(front.maxY, rear.minY, "\(model) schematic: \(schematic): apart, front to back")
                }
                let middle = shapes.outline().bounds.midX
                XCTAssertTrue(buttons.allSatisfy { $0.maxX < middle }, "\(model): on the thumb side")
            }
        }
    }

    /// The MX Master 4's gesture button is a side button of its own and its thumb panel the
    /// large thumb rest (in the view from the thumb side); the MX Master 3's gesture button
    /// is its thumb rest, pressed down: the pad on the wing in the view from above.
    func testTheGestureButtonIsWhereTheModelHasIt() throws {
        let four = MouseArtworkShapes(model: .mxMaster4, lighting: .gesture)
        XCTAssertEqual(four.viewpoint, .thumbSide)
        let gesture4 = try XCTUnwrap(four.shape(of: .gesture)).bounds
        let rest4 = try XCTUnwrap(four.shape(of: .thumbPanel)).bounds
        let forward4 = try XCTUnwrap(four.shape(of: .forward)).bounds
        XCTAssertLessThan(gesture4.midX, forward4.minX, "in front of Forward")
        XCTAssertGreaterThan(rest4.height, 2 * gesture4.height, "the thumb rest is the large one")
        XCTAssertNotEqual(gesture4, rest4)

        let three = MouseArtworkShapes(model: .mxMaster3, lighting: .gesture)
        XCTAssertEqual(three.viewpoint, .above)
        let gesture3 = try XCTUnwrap(three.shape(of: .gesture)).bounds
        let roller3 = try XCTUnwrap(three.shape(of: .thumbWheel)).bounds
        XCTAssertLessThan(gesture3.maxX, roller3.midX, "on the wing, outside the thumb wheel")
        XCTAssertGreaterThan(gesture3.height, 2 * roller3.height - 6, "the whole rest, not a spot at its front")
        XCTAssertNotNil(three.views?.restRidge, "marked by a short ridge")
        XCTAssertNil(MouseArtworkShapes(model: .mxMaster3, viewpoint: .thumbSide).shape(of: .gesture), "nothing to light from the side")
        XCTAssertNil(three.shape(of: .thumbPanel))
        XCTAssertEqual(MouseArtworkModel.mxMaster4.gesturePreviewPart, .gesture)
        XCTAssertEqual(MouseArtworkModel.mxMaster3.gesturePreviewPart, .gesture)
        XCTAssertEqual(MouseArtworkModel.generic.gesturePreviewPart, .back)
    }

    /// The plain mouse is symmetric.
    func testThePlainMouseIsSymmetric() {
        let outline = MouseArtworkShapes(model: .generic).outline().bounds
        XCTAssertEqual(outline.midX, MouseArtworkShapes.grid.width / 2, accuracy: 0.5)
        XCTAssertEqual(MouseArtworkShapes(model: .generic).wheelRect.midX, outline.midX, accuracy: 0.5)
    }

    /// A drawing in two views need not have a thumb wheel, and may have a tinted area that
    /// is no part. The MX Masters have the first and not the second, and their light is
    /// behind the wheel's slot, not in it (a light in the slot is drawn again over a lit
    /// button, with the slot).
    func testWhatADrawingInTwoViewsMayLeaveOut() throws {
        for model in [MouseArtworkModel.mxMaster4, .mxMaster3] {
            for viewpoint in model.viewpoints {
                let shapes = MouseArtworkShapes(model: model, viewpoint: viewpoint)
                let views = try XCTUnwrap(shapes.views)
                XCTAssertEqual(views.roller?.path.bounds, shapes.shape(of: .thumbWheel)?.bounds, "\(model) \(viewpoint): the thumb wheel")
                XCTAssertNotNil(views.roller, "\(model) \(viewpoint)")
                XCTAssertNil(views.trim, "\(model) \(viewpoint)")
                if let light = views.light {
                    XCTAssertFalse(views.wellRect.contains(light.bounds), "\(model): the light is not in the slot")
                }
            }
        }
    }

    // MARK: - The drawings that did not change

    /// The drawings that are not being redrawn are pinned: every shape of theirs, at the
    /// card's size and in the small pictures, as a fingerprint of its points. The plain
    /// mouse's was taken before the MX Master 4 got its second view, the MX Master 4's two
    /// views before the MX Master 3 got its own; it fails when one of their shapes moves.
    func testTheOtherDrawingsHaveNotMoved() {
        let pinned: [(MouseArtworkModel, MouseArtworkViewpoint, Bool, String)] = [
            (.generic, .above, false, "3d0e0b56666d7899"),
            (.generic, .above, true, "2c9df290e9faecaf"),
            (.mxMaster4, .above, false, "28b1acb4cc68b12d"),
            (.mxMaster4, .above, true, "780a63821b2a097e"),
            (.mxMaster4, .thumbSide, false, "83230de9673eb75f"),
            (.mxMaster4, .thumbSide, true, "3195c879cc678f2b"),
        ]
        for (model, viewpoint, schematic, fingerprint) in pinned {
            XCTAssertEqual(
                Self.fingerprint(of: MouseArtworkShapes(model: model, schematic: schematic, viewpoint: viewpoint)), fingerprint,
                "\(model) \(viewpoint), schematic: \(schematic)"
            )
        }
    }

    /// Every shape of a drawing, written out point by point (hundredths of a grid unit) and
    /// hashed (FNV-1a, 64 bits). The two buttons are cut out of the outline by Core
    /// Graphics, so only their bounds are taken (tenths).
    private static func fingerprint(of shapes: MouseArtworkShapes) -> String {
        func number(_ value: CGFloat, _ digits: Int = 2) -> String {
            let rounded = (Double(value) * pow(10, Double(digits))).rounded() / pow(10, Double(digits))
            return String(format: "%.\(digits)f", rounded == 0 ? 0 : rounded)
        }
        func rect(_ rect: NSRect, _ digits: Int = 2) -> String {
            return [rect.minX, rect.minY, rect.width, rect.height].map { number($0, digits) }.joined(separator: ",")
        }
        func points(of path: NSBezierPath?) -> String {
            guard let path else { return "none" }
            var text = ""
            var points = [NSPoint](repeating: .zero, count: 3)
            for index in 0..<path.elementCount {
                let kind = path.element(at: index, associatedPoints: &points)
                let count: Int
                switch kind {
                case .moveTo: text += "M"; count = 1
                case .lineTo: text += "L"; count = 1
                case .curveTo, .cubicCurveTo: text += "C"; count = 3
                case .closePath: text += "Z"; count = 0
                case .quadraticCurveTo: text += "Q"; count = 2
                @unknown default: text += "?"; count = 0
                }
                text += points.prefix(count).map { number($0.x) + "," + number($0.y) }.joined(separator: " ") + ";"
            }
            return text
        }
        var lines = [
            "outline " + points(of: shapes.outline()),
            "seams " + points(of: shapes.seams()),
            // Two lines only the MX Master 3's first drawing had; kept so that the plain
            // mouse's fingerprint is the one first taken.
            "shoulder none",
            "ridge none",
            "body " + rect(shapes.mainBody),
            "wheel " + rect(shapes.wheelRect),
            "well " + rect(shapes.wellRect),
            "badge " + number(shapes.badgeCentre.x) + "," + number(shapes.badgeCentre.y),
        ]
        // The MX Vertical's top button came after these fingerprints were taken; none of the
        // pinned drawings has it, and it is left out so that they stay the ones first taken.
        for part in MouseArtworkPart.allCases where part != .pointerSpeed {
            let shape = shapes.shape(of: part)
            if part == .left || part == .right {
                lines.append("\(part) " + (shape.map { rect($0.bounds, 1) } ?? "none"))
            } else {
                lines.append("\(part) " + points(of: shape))
            }
        }
        // What a drawing in two views has besides its parts.
        if let views = shapes.views {
            lines.append("housing " + points(of: views.thumbWheelHousing))
            lines.append("dots " + points(of: views.panelDots))
            lines.append("light " + points(of: views.light))
            lines.append("crest " + points(of: views.wheelCrest))
        }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in lines.joined(separator: "\n").utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(format: "%016llx", hash)
    }

    // MARK: - A part the shown mouse does not have

    private func trigger(_ code: UInt16, placed part: PlacedMousePart? = nil) -> RecordedEvent {
        return RecordedEvent(type: .mouse, code: code, modifiers: 0, deviceFilter: nil, mousePart: part)
    }

    /// Shown as a button the drawing cannot show: with its number when the Mac knows it by
    /// one, lit again on a mouse that has the part. Its place is known, so it is not
    /// "unplaced". The stored answer is not touched.
    func testAPartTheMouseDoesNotHaveIsShownAsAnUnknownButton() {
        let panel = trigger(2000 + 0x01A0)
        let gesture = trigger(1000)
        let placedPanel = trigger(5, placed: .thumbPanel)
        let placedGesture = trigger(6, placed: .gestureButton)

        XCTAssertEqual(ButtonTriggerPicture.make(for: panel, mouse: .mxMaster4), .mouse(part: .thumbPanel, number: nil))
        XCTAssertEqual(ButtonTriggerPicture.make(for: panel, mouse: .mxMaster3), .mouse(part: nil, number: nil, notDrawn: .thumbPanel))
        XCTAssertEqual(ButtonTriggerPicture.make(for: placedPanel, mouse: .mxMaster4), .mouse(part: .thumbPanel, number: nil))
        XCTAssertEqual(ButtonTriggerPicture.make(for: placedPanel, mouse: .mxMaster3), .mouse(part: nil, number: 5, notDrawn: .thumbPanel))
        XCTAssertEqual(placedPanel.mousePart, .thumbPanel, "kept")

        XCTAssertEqual(ButtonTriggerPicture.make(for: gesture, mouse: .mxMaster3), .mouse(part: .gesture, number: nil))
        XCTAssertEqual(ButtonTriggerPicture.make(for: gesture, mouse: .generic), .mouse(part: nil, number: nil, notDrawn: .gesture))
        XCTAssertEqual(ButtonTriggerPicture.make(for: placedGesture, mouse: .generic), .mouse(part: nil, number: 6, notDrawn: .gesture))
        XCTAssertEqual(ButtonTriggerPicture.make(for: trigger(1001), mouse: .generic), .mouse(part: nil, number: nil, notDrawn: .modeShift),
                       "a plain mouse has no button behind the wheel")

        for model in MouseArtworkModel.allCases {
            for code: UInt16 in 0...4 {
                XCTAssertNotNil(ButtonTriggerPicture.make(for: trigger(code), mouse: model).part, "\(model) \(code)")
            }
        }
        for picture in [
            ButtonTriggerPicture.make(for: panel, mouse: .mxMaster3), ButtonTriggerPicture.make(for: placedPanel, mouse: .mxMaster3),
            ButtonTriggerPicture.make(for: gesture, mouse: .generic), ButtonTriggerPicture.make(for: trigger(1001), mouse: .generic),
        ] {
            XCTAssertFalse(picture.isUnplaced, "its place is known: \(picture)")
        }
        XCTAssertTrue(ButtonTriggerPicture.make(for: trigger(6), mouse: .mxMaster3).isUnplaced, "no part known")

        // The card does not ask to find or place a known button; it says the mouse lacks it.
        let notHere = "The mouse shown doesn't have this button."
        let focus = ButtonsHeaderContent.Focus(
            title: "Thumb panel (button 5)", action: nil,
            picture: ButtonTriggerPicture.make(for: placedPanel, mouse: .mxMaster3)
        )
        let content = ButtonsHeaderContent.make(deviceName: "MX Master 3S", boundCount: 1, isRecording: false, focus: focus)
        XCTAssertNil(content.part)
        XCTAssertEqual(content.number, 5)
        XCTAssertEqual(content.hint, notHere)
        let gestureFocus = ButtonsHeaderContent.Focus(
            title: "Gesture button", action: "Copy", picture: ButtonTriggerPicture.make(for: gesture, mouse: .generic)
        )
        XCTAssertEqual(ButtonsHeaderContent.make(deviceName: nil, boundCount: 1, isRecording: false, focus: gestureFocus),
                       ButtonsHeaderContent(title: "Gesture button", subtitle: "Copy", part: nil, hint: notHere))
    }

    /// "Which Button Is This?" offers the parts of the shown mouse; an answer it does not
    /// have is listed ticked and disabled (not offered, not lost), and still stored.
    func testWhichButtonIsThisOffersThePartsOfTheShownMouse() throws {
        let six = trigger(6)
        let placed = trigger(6, placed: .thumbPanel)
        func parts(_ trigger: RecordedEvent, _ model: MouseArtworkModel) throws -> [PlacedMousePart] {
            return try XCTUnwrap(ButtonPlaceMenuModel.make(for: trigger, among: [trigger], mouse: model)).items.map(\.part)
        }
        XCTAssertEqual(try parts(six, .mxMaster4), PlacedMousePart.allCases)
        XCTAssertEqual(try parts(six, .mxMaster3), [.gestureButton, .backButton, .forwardButton, .modeShiftButton, .middleButton])
        XCTAssertEqual(try parts(six, .generic), [.backButton, .forwardButton, .middleButton])

        let onThree = try XCTUnwrap(ButtonPlaceMenuModel.make(for: placed, among: [placed], mouse: .mxMaster3))
        XCTAssertEqual(onThree.items.map(\.part), [.gestureButton, .thumbPanel, .backButton, .forwardButton, .modeShiftButton, .middleButton])
        XCTAssertEqual(onThree.items.filter(\.isChosen).map(\.part), [.thumbPanel])
        XCTAssertEqual(onThree.items.filter { !$0.isOnMouse }.map(\.part), [.thumbPanel])
        XCTAssertEqual(onThree.mouse, .mxMaster3)
        let onFour = try XCTUnwrap(ButtonPlaceMenuModel.make(for: placed, among: [placed], mouse: .mxMaster4))
        XCTAssertEqual(onFour.items.filter(\.isChosen).map(\.part), [.thumbPanel])
        XCTAssertTrue(onFour.items.allSatisfy(\.isOnMouse))
        XCTAssertEqual(placed.mousePart, .thumbPanel, "kept")
    }

    // MARK: - The stored values are the same

    /// The parts a numbered button can be said to be keep their stored names, and each
    /// lights its own part of the drawing.
    func testThePlacedPartsKeepTheirNamesAndLightTheirOwnPart() {
        XCTAssertEqual(PlacedMousePart.allCases.map(\.rawValue), [
            "gestureButton", "thumbPanel", "backButton", "forwardButton", "modeShiftButton", "middleButton",
        ])
        XCTAssertEqual(PlacedMousePart.allCases.map(\.drawingPart), [.gesture, .thumbPanel, .back, .forward, .modeShift, .middle])
        XCTAssertEqual(Set(PlacedMousePart.allCases.map(\.drawingPart.artworkPart)).count, PlacedMousePart.allCases.count)
    }
}
