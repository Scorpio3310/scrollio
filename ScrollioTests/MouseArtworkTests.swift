//
//  MouseArtworkTests.swift
//  MosTests
//
//  The drawing per model: which drawing a connected mouse gets, which parts each drawing
//  has and where, and how a part the shown mouse does not have is shown (the Buttons pane's
//  pictures and "Which Button Is This?").
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
            ("MX Anywhere 3S", .generic),
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
        XCTAssertEqual(MouseArtworkModel.mxMaster4.parts, MouseArtworkPart.allCases)
        XCTAssertEqual(Set(MouseArtworkModel.mxMaster3.parts), Set(MouseArtworkPart.allCases).subtracting([.thumbPanel]))
        XCTAssertEqual(Set(MouseArtworkModel.generic.parts), [.body, .left, .right, .wheel, .back, .forward])
        for model in MouseArtworkModel.allCases {
            for schematic in [false, true] {
                let shapes = MouseArtworkShapes(model: model, schematic: schematic)
                let outline = shapes.outline().bounds
                for part in MouseArtworkPart.allCases {
                    let shape = shapes.shape(of: part)
                    XCTAssertEqual(shape != nil, model.has(part), "\(model) \(part)")
                    if let shape {
                        XCTAssertFalse(shape.isEmpty, "\(model) \(part)")
                        XCTAssertTrue(outline.intersects(shape.bounds), "\(model) \(part) is on the mouse")
                    }
                }
            }
        }
    }

    /// The side buttons run front to back: on the MX Master 4 the gesture button, Forward,
    /// Back; on the others Forward, Back. Apart from each other at the card's size and in
    /// the small pictures, and on the thumb side.
    func testTheSideButtonsRunFrontToBack() throws {
        for model in MouseArtworkModel.allCases {
            for schematic in [false, true] {
                let shapes = MouseArtworkShapes(model: model, schematic: schematic)
                let order: [MouseArtworkPart] = model == .mxMaster4 ? [.gesture, .forward, .back] : [.forward, .back]
                let buttons = try order.map { try XCTUnwrap(shapes.shape(of: $0)?.bounds, "\(model) \($0)") }
                for (front, rear) in zip(buttons, buttons.dropFirst()) {
                    XCTAssertLessThan(front.maxY, rear.minY, "\(model) schematic: \(schematic): apart, front to back")
                }
                let middle = shapes.outline().bounds.midX
                XCTAssertTrue(buttons.allSatisfy { $0.maxX < middle }, "\(model): on the thumb side")
            }
        }
    }

    /// The MX Master 4's gesture button is the front side button and its thumb panel the
    /// thumb rest; the MX Master 3's gesture button is in the thumb rest.
    func testTheGestureButtonIsWhereTheModelHasIt() throws {
        let four = MouseArtworkShapes(model: .mxMaster4)
        let gesture4 = try XCTUnwrap(four.shape(of: .gesture)).bounds
        let rest4 = try XCTUnwrap(four.shape(of: .thumbPanel)).bounds
        let forward4 = try XCTUnwrap(four.shape(of: .forward)).bounds
        XCTAssertLessThan(gesture4.maxY, forward4.minY, "in front of Forward")
        XCTAssertGreaterThan(rest4.height, 2 * gesture4.height, "the thumb rest is the large one")
        XCTAssertNotEqual(gesture4, rest4)

        let three = MouseArtworkShapes(model: .mxMaster3)
        let gesture3 = try XCTUnwrap(three.shape(of: .gesture)).bounds
        let forward3 = try XCTUnwrap(three.shape(of: .forward)).bounds
        XCTAssertLessThan(gesture3.minX, forward3.minX, "below the side buttons, in the thumb rest")
        XCTAssertNotNil(three.gestureRidge())
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
