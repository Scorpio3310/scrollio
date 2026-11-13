//
//  MouseArtworkMoreMiceTests.swift
//  ScrollioTests
//
//  The MX Anywhere 3 / 3S and the MX Vertical: which names get their drawings, the parts
//  each has and where they are in its two views, the rows the Buttons pane lists for them
//  and in which order, and what each control they report is on the mouse. (The rules every
//  drawing follows are in MouseArtworkTests; these are the ones of the two mice.)
//

import XCTest
@testable import Scrollio_Debug

final class MouseArtworkMoreMiceTests: XCTestCase {

    private var savedBindings: [ButtonBinding] = []

    override func setUp() {
        super.setUp()
        savedBindings = Options.shared.buttons.binding
        Options.shared.buttons.binding = []
    }

    override func tearDown() {
        Options.shared.buttons.binding = savedBindings
        super.tearDown()
    }

    private static let mice: [MouseArtworkModel] = [.mxAnywhere3, .mxVertical]

    private func trigger(_ code: UInt16, placed part: PlacedMousePart? = nil) -> RecordedEvent {
        return RecordedEvent(type: .mouse, code: code, modifiers: 0, deviceFilter: nil, mousePart: part)
    }

    private func binding(_ code: UInt16, _ action: String = "") -> ButtonBinding {
        return ButtonBinding(triggerEvent: trigger(code), systemShortcutName: action, isEnabled: !action.isEmpty)
    }

    /// The code Scrollio records a Logitech control by.
    private func code(ofControl cid: UInt16) -> UInt16 {
        return LogiCIDDirectory.toScrollioCode(cid)
    }

    // MARK: - Which drawing

    /// The MX Anywhere 3 and 3S (also "for Mac", "for Business") and the MX Vertical are
    /// known by the name the mouse reports. The MX Anywhere 2 and 2S are another mouse (a
    /// tilt wheel, a gesture button behind it) and stay plain, as does everything else.
    func testTheTwoMiceAreKnownByTheirNames() {
        let cases: [(String?, MouseArtworkModel)] = [
            ("MX Anywhere 3", .mxAnywhere3),
            ("MX Anywhere 3S", .mxAnywhere3),
            ("MX Anywhere 3 for Mac", .mxAnywhere3),
            ("MX Anywhere 3S for Mac", .mxAnywhere3),
            ("MX Anywhere 3 for Business", .mxAnywhere3),
            ("MX Anywhere 3S for Business", .mxAnywhere3),
            ("mx anywhere 3s", .mxAnywhere3),
            ("Wireless Mouse MX Anywhere 3", .mxAnywhere3),
            ("MX Vertical", .mxVertical),
            ("MX Vertical Advanced Ergonomic Mouse", .mxVertical),
            ("MX Vertical for Business", .mxVertical),
            ("mx vertical", .mxVertical),
            ("Logitech MX Vertical", .mxVertical),
            ("MX Anywhere 2S", .generic),
            ("MX Anywhere 2", .generic),
            ("MX Anywhere", .generic),
            ("MX Anywhere 4", .generic),
            ("MX Anywhere 35", .generic),
            ("Anywhere 3", .generic),
            ("MX Vertical 2", .generic),
            ("Vertical", .generic),
            ("Lift Vertical Ergonomic Mouse", .generic),
            ("MX Ergo", .generic),
        ]
        for (name, model) in cases {
            XCTAssertEqual(MouseArtworkModel.model(forDeviceName: name), model, name ?? "nil")
        }
    }

    // MARK: - The parts

    /// The MX Anywhere 3: the two buttons, the wheel, the button behind it, Back and
    /// Forward. The MX Vertical: the two buttons, the wheel, Back and Forward, and the
    /// button on its top. Neither has a thumb wheel, a gesture button or a thumb panel; the
    /// button on the top is the MX Vertical's alone.
    func testThePartsOfTheTwoMice() {
        XCTAssertEqual(Set(MouseArtworkModel.mxAnywhere3.parts), [.body, .left, .right, .wheel, .modeShift, .back, .forward])
        XCTAssertEqual(Set(MouseArtworkModel.mxVertical.parts), [.body, .left, .right, .wheel, .back, .forward, .pointerSpeed])
        for model in MouseArtworkModel.allCases where model != .mxVertical {
            XCTAssertFalse(model.has(.pointerSpeed), "\(model)")
        }
        for model in Self.mice {
            XCTAssertEqual(model.parts.count, Set(model.parts).count, "\(model): each part once")
            XCTAssertNil(model.views(.above).roller, "\(model): no thumb wheel")
            XCTAssertNil(model.views(.thumbSide).roller, "\(model)")
            XCTAssertNil(model.views(.above).thumbWheelHousing, "\(model)")
            XCTAssertFalse(ButtonsListLayout.showsThumbWheel(on: model), "\(model): no thumb wheel's row")
        }
    }

    /// Both are drawn from above and from the thumb side. What the thumb works lights from
    /// the thumb side: Back and Forward. Everything else lights from above, the button on
    /// the MX Vertical's top too (it shows in both views; from above it is seen whole).
    /// The Gestures preview holds Back down, as on any mouse without a gesture button, and
    /// so turns to the thumb side.
    func testTheViewsOfTheTwoMice() throws {
        for model in Self.mice {
            XCTAssertEqual(model.viewpoints, [.above, .thumbSide], "\(model)")
            XCTAssertEqual(model.sideParts, [.forward, .back], "\(model)")
            for part in MouseArtworkPart.allCases {
                XCTAssertEqual(model.viewpoint(lighting: part), part == .forward || part == .back ? .thumbSide : .above, "\(model) \(part)")
            }
            XCTAssertEqual(model.gesturePreviewPart, .back, "\(model)")
            XCTAssertEqual(model.viewpoint(lighting: model.gesturePreviewPart), .thumbSide, "\(model)")
        }
        // The top button shows in both views of the MX Vertical.
        for viewpoint in MouseArtworkViewpoint.allCases {
            XCTAssertNotNil(MouseArtworkShapes(model: .mxVertical, viewpoint: viewpoint).shape(of: .pointerSpeed), "\(viewpoint)")
        }
        // The buttons and the wheel do not show from the thumb side, the side buttons not from above.
        for model in Self.mice {
            let above = MouseArtworkShapes(model: model, viewpoint: .above)
            let side = MouseArtworkShapes(model: model, viewpoint: .thumbSide)
            for part in [MouseArtworkPart.left, .right, .wheel, .modeShift] {
                XCTAssertNil(side.shape(of: part), "\(model) \(part) from the side")
            }
            for part in [MouseArtworkPart.forward, .back] {
                XCTAssertNil(above.shape(of: part), "\(model) \(part) from above")
            }
        }
    }

    /// Every part has a shape in the view it lights in (and in any view that shows it),
    /// inside the drawing: within the outline's bounds, at the cards' size and in the small
    /// pictures.
    func testEveryPartHasAShapeInsideTheDrawing() throws {
        for model in Self.mice {
            for schematic in [false, true] {
                for part in model.parts {
                    let lighting = MouseArtworkShapes(model: model, schematic: schematic, lighting: part)
                    XCTAssertNotNil(lighting.shape(of: part), "\(model) \(part) where it lights")
                    for viewpoint in model.viewpoints {
                        let shapes = MouseArtworkShapes(model: model, schematic: schematic, viewpoint: viewpoint)
                        guard let shape = shapes.shape(of: part) else { continue }
                        XCTAssertFalse(shape.isEmpty, "\(model) \(part) \(viewpoint)")
                        let outline = shapes.outline().bounds.insetBy(dx: -0.5, dy: -0.5)
                        XCTAssertTrue(outline.contains(shape.bounds), "\(model) \(part) \(viewpoint), schematic \(schematic): \(shape.bounds) in \(outline)")
                    }
                }
                // What is drawn besides the parts is inside the canvas too.
                for viewpoint in model.viewpoints {
                    let views = try XCTUnwrap(MouseArtworkShapes(model: model, schematic: schematic, viewpoint: viewpoint).views)
                    for extra in [views.wheelCrest, views.light].compactMap({ $0 }) {
                        XCTAssertTrue(MouseArtworkShapes.canvas.contains(extra.bounds), "\(model) \(viewpoint)")
                    }
                }
            }
        }
    }

    /// The MX Anywhere 3 from above: symmetric; one long slot down the middle holds the
    /// wheel, behind it the small button, behind that the light; the two buttons are the
    /// front of the shell either side of the middle. From the thumb side: Forward in front
    /// of Back in one row, in the upper half of the body, and the wheel standing over the
    /// buttons near the front.
    func testTheAnywhereThreesDrawing() throws {
        for schematic in [false, true] {
            let above = MouseArtworkShapes(model: .mxAnywhere3, schematic: schematic)
            let outline = above.outline().bounds
            XCTAssertEqual(outline.midX, MouseArtworkAnywhere3.middle, accuracy: 0.1, "symmetric")
            let wheel = try XCTUnwrap(above.shape(of: .wheel)).bounds
            let button = try XCTUnwrap(above.shape(of: .modeShift)).bounds
            XCTAssertEqual(wheel.midX, outline.midX, accuracy: 0.1)
            XCTAssertEqual(button.midX, outline.midX, accuracy: 0.1)
            XCTAssertLessThan(wheel.maxY, button.minY, "the button is behind the wheel")
            let left = try XCTUnwrap(above.shape(of: .left)).bounds
            let right = try XCTUnwrap(above.shape(of: .right)).bounds
            XCTAssertEqual(left.maxX, outline.midX, accuracy: 0.2)
            XCTAssertEqual(right.minX, outline.midX, accuracy: 0.2)
            XCTAssertEqual(left.width, right.width, accuracy: 0.2)
            XCTAssertLessThan(left.maxY, outline.midY + 10, "the buttons are the front of the shell")
            XCTAssertGreaterThan(left.maxY, button.maxY, "and reach behind the small button")

            let side = MouseArtworkShapes(model: .mxAnywhere3, schematic: schematic, viewpoint: .thumbSide)
            let body = side.outline().bounds
            let forward = try XCTUnwrap(side.shape(of: .forward)).bounds
            let back = try XCTUnwrap(side.shape(of: .back)).bounds
            XCTAssertLessThan(forward.midX, back.minX, "Forward is in front (to the left)")
            XCTAssertLessThanOrEqual(forward.maxX, back.minX + 0.5, "apart")
            XCTAssertLessThan(max(forward.maxY, back.maxY), body.midY + body.height * 0.15, "high on the side")
            let crest = try XCTUnwrap(side.views?.wheelCrest).bounds
            XCTAssertLessThan(crest.midX, forward.minX, "the wheel is in front of the side buttons")
            XCTAssertLessThan(crest.minY, body.midY, "and stands in the upper half")
        }
        let above = try XCTUnwrap(MouseArtworkShapes(model: .mxAnywhere3).views)
        let slot = above.wellRect
        XCTAssertTrue(slot.contains(above.wheelRect), "the wheel is in the slot")
        XCTAssertTrue(slot.contains(try XCTUnwrap(above.shape(of: .modeShift)).bounds), "the button too")
        XCTAssertTrue(slot.contains(try XCTUnwrap(above.light).bounds), "and the light")
        XCTAssertNotNil(above.trim, "the side grips show from above")
        // As long from the side as from above, and lower than it is wide.
        let top = MouseArtworkShapes(model: .mxAnywhere3).outline().bounds
        let side = MouseArtworkShapes(model: .mxAnywhere3, viewpoint: .thumbSide).outline().bounds
        XCTAssertEqual(side.width, top.height, accuracy: 1)
        XCTAssertLessThan(side.height, top.width * 0.6, "a low mouse")
    }

    /// The MX Vertical from above: the plate along the top on the thumb side of the
    /// buttons, with its button at its rear end; right of the plate the left button, then
    /// the right one, the wheel on the split between them. From the thumb side: an upright
    /// mouse (nearly as tall as two thirds of its length), the plate along the top with its
    /// button, and under the plate Forward in front of Back.
    func testTheVerticalsDrawing() throws {
        for schematic in [false, true] {
            let above = MouseArtworkShapes(model: .mxVertical, schematic: schematic)
            let views = try XCTUnwrap(above.views)
            let plate = try XCTUnwrap(views.trim).bounds
            let top = try XCTUnwrap(above.shape(of: .pointerSpeed)).bounds
            let wheel = try XCTUnwrap(above.shape(of: .wheel)).bounds
            let left = try XCTUnwrap(above.shape(of: .left)).bounds
            let right = try XCTUnwrap(above.shape(of: .right)).bounds
            XCTAssertTrue(plate.insetBy(dx: -0.5, dy: -0.5).contains(top), "the top button is on the plate")
            XCTAssertGreaterThan(top.midY, plate.midY, "at its rear end")
            XCTAssertGreaterThan(top.minY, wheel.maxY, "behind the wheel")
            XCTAssertLessThan(plate.midX, left.minX, "the plate is on the thumb side of the buttons")
            XCTAssertGreaterThanOrEqual(left.minX, plate.maxX - 2.5, "the left button begins at the plate")
            XCTAssertEqual(left.maxX, MouseArtworkVertical.split, accuracy: 0.2)
            XCTAssertEqual(right.minX, MouseArtworkVertical.split, accuracy: 0.2)
            XCTAssertEqual(wheel.midX, MouseArtworkVertical.split, accuracy: 0.1, "the wheel is on the split")
            XCTAssertLessThan(wheel.maxY, left.maxY, "inside the buttons' length")

            let side = MouseArtworkShapes(model: .mxVertical, schematic: schematic, viewpoint: .thumbSide)
            let body = side.outline().bounds
            let band = try XCTUnwrap(side.views?.trim).bounds
            let forward = try XCTUnwrap(side.shape(of: .forward)).bounds
            let back = try XCTUnwrap(side.shape(of: .back)).bounds
            let button = try XCTUnwrap(side.shape(of: .pointerSpeed)).bounds
            XCTAssertLessThan(forward.midX, back.minX, "Forward is in front (to the left)")
            XCTAssertLessThanOrEqual(forward.maxX, back.minX + 0.5, "apart")
            XCTAssertGreaterThan(forward.width, back.width - 0.5, "Forward is the longer half")
            XCTAssertLessThan(max(forward.maxY, back.maxY), body.midY, "under the thumb, in the upper half")
            XCTAssertLessThan(button.maxY, min(forward.minY, back.minY), "the top button is above them")
            XCTAssertGreaterThan(button.midX, back.midX, "and further back")
            XCTAssertLessThan(band.minY, body.minY + 1, "the plate is along the top")
        }
        let top = MouseArtworkShapes(model: .mxVertical).outline().bounds
        let side = MouseArtworkShapes(model: .mxVertical, viewpoint: .thumbSide).outline().bounds
        XCTAssertEqual(side.width, top.height, accuracy: 1)
        XCTAssertGreaterThan(side.height, side.width * 0.6, "an upright mouse")
        XCTAssertGreaterThan(side.height, 1.8 * MouseArtworkShapes(model: .mxAnywhere3, viewpoint: .thumbSide).outline().bounds.height)
    }

    /// The small pictures light the row's part: where the part is, the picture is in the
    /// accent colour, in the view that part lights in; with nothing lit that place is not.
    func testTheSmallPicturesLightTheRowsPart() throws {
        let frame = NSRect(origin: .zero, size: ButtonsMouseMiniature.size)
        let appearance = try XCTUnwrap(NSAppearance(named: .aqua))
        // The accent colour as the same kind of drawing gives it back.
        let accent = try colour(at: NSPoint(x: 12, y: 12), appearance: appearance) {
            NSColor.controlAccentColor.setFill()
            frame.fill()
        }
        func distance(_ a: NSColor, _ b: NSColor) -> CGFloat {
            return max(abs(a.redComponent - b.redComponent), abs(a.greenComponent - b.greenComponent), abs(a.blueComponent - b.blueComponent))
        }
        for model in Self.mice {
            for part in ButtonsMousePart.allCases where model.has(part.artworkPart) {
                let shape = try XCTUnwrap(ButtonsMouseMiniature.shape(of: part, mouse: model, in: frame), "\(model) \(part)")
                let body = ButtonsMouseMiniature.bodyPath(of: model, lighting: part, in: frame).bounds
                XCTAssertTrue(frame.contains(body), "\(model) \(part): the mouse fits the picture")
                XCTAssertEqual(body.width > body.height, part == .forward || part == .back, "\(model) \(part): from the side for the side buttons")
                let middle = NSPoint(x: shape.bounds.midX, y: shape.bounds.midY)
                XCTAssertTrue(shape.contains(middle), "\(model) \(part)")
                let lit = try colour(at: middle, appearance: appearance) {
                    ButtonsMouseMiniature.draw(.mouse(part: part, number: nil), mouse: model, in: frame, highlighted: false)
                }
                let unlit = try colour(at: middle, appearance: appearance) {
                    ButtonsMouseMiniature.draw(.mouse(part: nil, number: nil), mouse: model, in: frame, highlighted: false)
                }
                XCTAssertLessThan(distance(lit, accent), 0.03, "\(model) \(part) is lit")
                if accent.saturationComponent > 0.3 {
                    XCTAssertGreaterThan(distance(unlit, accent), 0.1, "\(model) \(part): nothing lit there otherwise")
                }
            }
        }
    }

    /// The colour of a point of what `draw` draws in a row's picture, at eight pixels per
    /// point on the window's colour.
    private func colour(at point: NSPoint, appearance: NSAppearance, draw: () -> Void) throws -> NSColor {
        let size = ButtonsMouseMiniature.size
        let scale: CGFloat = 8
        let canvas = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        canvas.size = size
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: canvas))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
        context.cgContext.translateBy(x: 0, y: size.height)
        context.cgContext.scaleBy(x: 1, y: -1)
        appearance.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            NSRect(origin: .zero, size: size).fill()
            draw()
        }
        NSGraphicsContext.restoreGraphicsState()
        let colour = try XCTUnwrap(canvas.colorAt(x: Int(point.x * scale), y: Int(point.y * scale)))
        return try XCTUnwrap(colour.usingColorSpace(.deviceRGB))
    }

    // MARK: - What each control is

    /// The controls the two mice report (Logitech's control numbers, from the descriptions
    /// of these mice; not read off a real one): the wheel's click, Back and Forward are the
    /// standard buttons' roles, the button behind the MX Anywhere's wheel is the mode shift
    /// button, the button on the MX Vertical's top the pointer speed button. Left and right
    /// have no role (they are never taken from the mouse). The MX Anywhere's "virtual
    /// gesture button" has the role it has on an MX Master, and no part on this mouse.
    func testTheRoleOfEachControlOfTheTwoMice() {
        let anywhere: [(UInt16, LogiControlRole?)] = [
            (0x0050, nil), (0x0051, nil), (0x0052, .middle), (0x0053, .back), (0x0056, .forward),
            (0x00C4, .modeShift), (0x00D7, .gesture),
        ]
        let vertical: [(UInt16, LogiControlRole?)] = [
            (0x0050, nil), (0x0051, nil), (0x0052, .middle), (0x0053, .back), (0x0056, .forward),
            (0x00FD, .pointerSpeed),
        ]
        for (cid, role) in anywhere + vertical {
            XCTAssertEqual(LogiControlRole(cid: cid), role, String(format: "0x%04X", cid))
            XCTAssertEqual(LogiCenter.shared.controlRole(forScrollioCode: code(ofControl: cid)), role, String(format: "0x%04X", cid))
        }
        // The role names the control it was read from.
        XCTAssertEqual(LogiCenter.shared.scrollioCode(for: .pointerSpeed), code(ofControl: 0x00FD))
        XCTAssertEqual(LogiCenter.shared.controlRole(forScrollioCode: LogiCenter.shared.scrollioCode(for: .pointerSpeed)), .pointerSpeed)
        XCTAssertNil(LogiCenter.shared.nativeMouseButton(forScrollioCode: code(ofControl: 0x00FD)), "no standard button stands for it")
        // A control that is on neither list has no role, as before: it is named by its
        // own name and lights nothing.
        XCTAssertNil(LogiControlRole(cid: 0x00ED))
        XCTAssertNil(LogiControlRole(cid: 0x01A3))

        // Each role is its part of the drawing, on the mouse that has the part.
        let parts: [(UInt16, ButtonsMousePart, MouseArtworkModel)] = [
            (0x0052, .middle, .mxAnywhere3), (0x0053, .back, .mxAnywhere3), (0x0056, .forward, .mxAnywhere3),
            (0x00C4, .modeShift, .mxAnywhere3),
            (0x0052, .middle, .mxVertical), (0x0053, .back, .mxVertical), (0x0056, .forward, .mxVertical),
            (0x00FD, .pointerSpeed, .mxVertical),
        ]
        for (cid, part, model) in parts {
            let event = trigger(code(ofControl: cid))
            XCTAssertEqual(ButtonsMousePart.part(for: event), part, String(format: "0x%04X", cid))
            XCTAssertEqual(ButtonTriggerPicture.make(for: event, mouse: model), .mouse(part: part, number: nil), "\(model) \(part)")
            XCTAssertEqual(part.logitechRole, LogiControlRole(cid: cid), "\(part)")
        }
        // The virtual gesture button on an MX Anywhere, the mode shift button on an MX
        // Vertical, the pointer speed button on any other mouse: known, and not on the
        // mouse shown.
        XCTAssertEqual(ButtonTriggerPicture.make(for: trigger(code(ofControl: 0x00D7)), mouse: .mxAnywhere3),
                       .mouse(part: nil, number: nil, notDrawn: .gesture))
        XCTAssertEqual(ButtonTriggerPicture.make(for: trigger(code(ofControl: 0x00C4)), mouse: .mxVertical),
                       .mouse(part: nil, number: nil, notDrawn: .modeShift))
        for model in MouseArtworkModel.allCases where model != .mxVertical {
            XCTAssertEqual(ButtonTriggerPicture.make(for: trigger(code(ofControl: 0x00FD)), mouse: model),
                           .mouse(part: nil, number: nil, notDrawn: .pointerSpeed), "\(model)")
        }
    }

    /// The top button's row is called as the pane called that control before it had a row,
    /// and what "+" stores for it is its Logitech control (no standard button stands for it).
    func testTheTopButtonsNameAndTrigger() {
        let code = code(ofControl: 0x00FD)
        XCTAssertEqual(ButtonTriggerNaming.buttonName(code: code), "Pointer speed button")
        XCTAssertEqual(ButtonTriggerNaming.title(for: trigger(code)), "Pointer speed button")
        // Without a role (as a test or an older build would see it) the name is the same.
        let plain = ButtonTriggerNaming.Logitech(role: { _ in nil }, name: { _ in "DPI Switch" })
        XCTAssertEqual(ButtonTriggerNaming.buttonName(code: code, logitech: plain), "Pointer speed button")
        XCTAssertEqual(ButtonsMousePart.pointerSpeed.recordedTrigger(), trigger(code))
        XCTAssertEqual(ButtonsMousePart.pointerSpeed.artworkPart, .pointerSpeed)
        XCTAssertEqual(ButtonsMousePart.pointerSpeed.defaultExplanationKey, "buttons-default-own", "no claim about what it does by itself")
        // It is not a place a numbered button can be said to be: the Mac never reports it by a number.
        XCTAssertNil(PlacedMousePart(role: .pointerSpeed))
        XCTAssertNil(PlacedMousePart.known(for: trigger(code)))
        XCTAssertFalse(PlacedMousePart.allCases.contains { $0.drawingPart == .pointerSpeed })
    }

    // MARK: - The Buttons pane's rows

    /// The rows, in the order the buttons sit on the mouse. The MX Anywhere 3: the wheel,
    /// the button behind it, then the side buttons front to back. The MX Vertical: the
    /// wheel and the button on the top (what the fingers work, seen from above), then the
    /// side buttons front to back. Left and right are not listed, and neither mouse has a
    /// thumb wheel's row.
    func testTheRowsOfTheTwoMiceAndTheirOrder() {
        XCTAssertEqual(ButtonsMousePart.listed(on: .mxAnywhere3), [.middle, .modeShift, .forward, .back])
        XCTAssertEqual(ButtonsMousePart.listed(on: .mxVertical), [.middle, .pointerSpeed, .forward, .back])
        for model in Self.mice {
            let layout = ButtonsListLayout.make(bindings: [], mouse: model)
            XCTAssertEqual(layout.parts, ButtonsMousePart.listed(on: model), "\(model)")
            XCTAssertFalse(layout.hasThumbWheel, "\(model)")
            XCTAssertEqual(layout.rows.count, 4, "\(model)")
            XCTAssertTrue(layout.others.isEmpty)
            // Listed parts are parts of the drawing; the drawing turns once on the way down.
            let views = ButtonsMousePart.listed(on: model).map { model.viewpoint(lighting: $0.artworkPart) }
            XCTAssertEqual(views, [.above, .above, .thumbSide, .thumbSide], "\(model)")
        }
    }

    /// A stored binding of a button of the mouse is that button's row; one of a control the
    /// mouse does not have stays under "Other buttons and keys": the virtual gesture button
    /// on an MX Anywhere, the mode shift button on an MX Vertical, the pointer speed button
    /// on an MX Anywhere. A mouse that reports a control more is not harmed by it.
    func testBindingsAreTheRowsOfTheMouseThatHasTheButton() {
        let back = binding(3, SystemShortcut.navigateBack.identifier)
        let virtualGesture = binding(code(ofControl: 0x00D7), SystemShortcut.missionControl.identifier)
        let modeShift = binding(code(ofControl: 0x00C4), SystemShortcut.logiSmartShiftToggle.identifier)
        let speed = binding(code(ofControl: 0x00FD), SystemShortcut.copy.identifier)
        let unknown = binding(code(ofControl: 0x01A3), SystemShortcut.paste.identifier)
        let all = [back, virtualGesture, modeShift, speed, unknown]

        let anywhere = ButtonsListLayout.make(bindings: all, mouse: .mxAnywhere3)
        XCTAssertEqual(anywhere.partRows.map(\.part), [.middle, .modeShift, .forward, .back])
        XCTAssertEqual(anywhere.partRows.map(\.binding?.id), [nil, modeShift.id, nil, back.id])
        XCTAssertEqual(anywhere.others.map(\.id), [virtualGesture.id, speed.id, unknown.id])

        let vertical = ButtonsListLayout.make(bindings: all, mouse: .mxVertical)
        XCTAssertEqual(vertical.partRows.map(\.part), [.middle, .pointerSpeed, .forward, .back])
        XCTAssertEqual(vertical.partRows.map(\.binding?.id), [nil, speed.id, nil, back.id])
        XCTAssertEqual(vertical.others.map(\.id), [virtualGesture.id, modeShift.id, unknown.id])

        // Any other mouse: as before, no rows of its own.
        XCTAssertEqual(ButtonsListLayout.make(bindings: all, mouse: .generic).others.map(\.id), all.map(\.id))
    }

    /// The pane with such a mouse connected: its drawing on the card, a row per button
    /// under its name, each "Default" until it has an action, and no thumb wheel's row.
    func testThePaneListsTheButtonsOfTheConnectedMouse() throws {
        let expected: [(name: String, model: MouseArtworkModel, titles: [String], explanations: [String])] = [
            ("MX Anywhere 3S", .mxAnywhere3,
             ["Middle button", "Mode shift button", "Forward button", "Back button"],
             ["Middle click.", "Switches the wheel between clicking and spinning freely.",
              "Goes forward in apps that support it.", "Goes back in apps that support it."]),
            ("MX Vertical Advanced Ergonomic Mouse", .mxVertical,
             ["Middle button", "Pointer speed button", "Forward button", "Back button"],
             ["Middle click.", "Does what the mouse does on its own.",
              "Goes forward in apps that support it.", "Goes back in apps that support it."]),
        ]
        for mouse in expected {
            let pane = PreferencesButtonsViewController()
            pane.deviceSource = ButtonsDeviceSource(
                captureStatus: { _ in .normal }, deviceName: { mouse.name }, isBusy: { false }, refresh: {}, warnBluetoothButton: { _ in }
            )
            pane.scrollHoldKeys = { [] }
            pane.startRecording = { _ in }
            pane.openActionMenu = { _ in }
            pane.presentPlaceMenu = { _, _ in }
            pane.paneUndoManager = UndoManager()
            _ = pane.view
            pane.viewWillAppear()
            XCTAssertEqual(pane.mouse, mouse.model, mouse.name)
            XCTAssertEqual(pane.headerView.artwork.model, mouse.model, mouse.name)
            XCTAssertEqual(pane.rows.map(\.title), mouse.titles, mouse.name)
            XCTAssertEqual(pane.rows.map(\.id), ButtonsMousePart.listed(on: mouse.model).map { AnyHashable($0) }, mouse.name)
            XCTAssertEqual(pane.rows.map(\.explanation), mouse.explanations, mouse.name)
            XCTAssertEqual(pane.rows.map(\.picture), ButtonsMousePart.listed(on: mouse.model).map { ButtonTriggerPicture.mouse(part: $0, number: nil) })
            XCTAssertTrue(pane.rows.allSatisfy { $0.isDefault && !$0.isStored && !$0.isRemovable }, mouse.name)
            XCTAssertNil(pane.thumbWheelRow, mouse.name)
            XCTAssertTrue(Options.shared.buttons.binding.isEmpty, "nothing is stored by showing the rows")
            pane.viewWillDisappear()
        }
    }

    /// "Which Button Is This?" offers the parts of the mouse shown: on an MX Anywhere 3
    /// Back, Forward, the mode shift button and the middle button; on an MX Vertical Back,
    /// Forward and the middle button.
    func testWhichButtonIsThisOnTheTwoMice() throws {
        let six = trigger(6)
        func parts(_ model: MouseArtworkModel) throws -> [PlacedMousePart] {
            return try XCTUnwrap(ButtonPlaceMenuModel.make(for: six, among: [six], mouse: model)).items.map(\.part)
        }
        XCTAssertEqual(try parts(.mxAnywhere3), [.backButton, .forwardButton, .modeShiftButton, .middleButton])
        XCTAssertEqual(try parts(.mxVertical), [.backButton, .forwardButton, .middleButton])
    }
}

private extension MouseArtworkModel {
    /// The shapes of one view of a drawing in two views.
    func views(_ viewpoint: MouseArtworkViewpoint) -> MouseArtworkTwoViews {
        return MouseArtworkShapes(model: self, viewpoint: viewpoint).views!
    }
}
