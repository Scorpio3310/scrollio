//
//  TriggerPictureTests.swift
//  ScrollioTests
//
//  The one rule the Gestures and Shortcut Ring panes' pictures share (`TriggerPicture`):
//  which trigger the picture is of (`TriggerPictureSource.make`), what it shows for it on
//  each drawing of the mouse, the keys of a trigger one by one (`capLabels`, the pieces of
//  the row's title) and the pieces the pictures are drawn with. Pure, apart from the
//  drawing of the badge and the placeholder off screen. The app of the "only in an app"
//  case is Notes, which every Mac has.
//

import XCTest
@testable import Scrollio_Debug

final class TriggerPictureTests: XCTestCase {

    private static let notes = "/System/Applications/Notes.app"
    private static let models = MouseArtworkModel.allCases

    private let control = UInt(CGEventFlags.maskControl.rawValue)
    private let option = UInt(CGEventFlags.maskAlternate.rawValue)
    private let shift = UInt(CGEventFlags.maskShift.rawValue)
    private let command = UInt(CGEventFlags.maskCommand.rawValue)
    private let fn = UInt(CGEventFlags.maskSecondaryFn.rawValue)

    private func mouse(_ code: UInt16, modifiers: UInt = 0, placed: PlacedMousePart? = nil) -> RecordedEvent {
        return RecordedEvent(type: .mouse, code: code, modifiers: modifiers, deviceFilter: nil, mousePart: placed)
    }

    private func logitech(_ role: LogiControlRole, modifiers: UInt = 0) -> RecordedEvent {
        return mouse(LogiCenter.shared.scrollioCode(for: role), modifiers: modifiers)
    }

    private func key(_ code: UInt16, modifiers: UInt) -> RecordedEvent {
        return RecordedEvent(type: .keyboard, code: code, modifiers: modifiers, deviceFilter: nil)
    }

    private func binding(_ event: RecordedEvent, _ action: SystemShortcut.Shortcut, enabled: Bool = true) -> ButtonBinding {
        return ButtonBinding(triggerEvent: event, systemShortcutName: action.identifier, isEnabled: enabled)
    }

    private func picture(_ event: RecordedEvent?, on model: MouseArtworkModel, app: String? = nil) -> TriggerPicture {
        return TriggerPicture.make(TriggerPictureSource(event: event, onlyInAppPath: app), mouse: model)
    }

    /// The parts each drawing has, as the Buttons pane names them (left and right aside).
    private static let drawn: [MouseArtworkModel: Set<ButtonsMousePart>] = [
        .mxMaster4: [.middle, .back, .forward, .gesture, .modeShift, .thumbPanel],
        .mxMaster3: [.middle, .back, .forward, .gesture, .modeShift],
        .mxAnywhere3: [.middle, .back, .forward, .modeShift],
        .mxVertical: [.middle, .back, .forward, .pointerSpeed],
        .generic: [.middle, .back, .forward],
    ]

    /// The parts that light in the view from the thumb side (the drawing turns for them).
    private static let fromTheSide: [MouseArtworkModel: Set<ButtonsMousePart>] = [
        .mxMaster4: [.gesture, .thumbPanel, .back, .forward],
        .mxMaster3: [.back, .forward],
        .mxAnywhere3: [.back, .forward],
        .mxVertical: [.back, .forward],
        .generic: [],
    ]

    // MARK: - Every case on every drawing (spec 2.3)

    /// A part the drawing has lights, in the view it lights in; a Logitech part the drawing
    /// lacks is the badge of a button of this mouse. The standard middle, back and forward
    /// buttons light on every drawing, the plain one included.
    func testAPartLightsWhereTheDrawingHasItAndIsABadgeWhereItDoesNot() {
        let roles: [(LogiControlRole, ButtonsMousePart)] = [
            (.gesture, .gesture), (.thumbPanel, .thumbPanel), (.modeShift, .modeShift), (.middle, .middle),
            (.back, .back), (.forward, .forward), (.pointerSpeed, .pointerSpeed),
        ]
        for model in Self.models {
            let has = Self.drawn[model]!
            for (role, part) in roles {
                let shown = picture(logitech(role), on: model)
                let expected: TriggerPicture.Hold = has.contains(part) ? .part(part) : .notDrawn(part)
                XCTAssertEqual(shown, TriggerPicture(hold: expected), "\(role) on \(model)")
                XCTAssertEqual(shown.litPart, has.contains(part) ? part : nil)
                if let lit = shown.litPart {
                    let side = Self.fromTheSide[model]!.contains(lit)
                    XCTAssertEqual(model.viewpoint(lighting: lit.artworkPart), side ? .thumbSide : .above, "\(role) on \(model)")
                }
            }
            for (code, part) in [(UInt16(2), ButtonsMousePart.middle), (3, .back), (4, .forward)] {
                XCTAssertEqual(picture(mouse(code), on: model), TriggerPicture(hold: .part(part)), "button \(code) on \(model)")
            }
        }
        // The owner's case: the thumb panel on an MX Master 4 is the panel, from the side.
        XCTAssertEqual(picture(logitech(.thumbPanel), on: .mxMaster4).litPart, .thumbPanel)
        XCTAssertEqual(MouseArtworkModel.mxMaster4.viewpoint(lighting: .thumbPanel), .thumbSide)
    }

    /// A button the Mac knows only by its number: its number on a badge; placed on a part
    /// ("Which button is this?"), that part where the drawing has it, else the number again.
    func testANumberedButtonIsItsBadgeUnlessItsPlaceIsDrawn() {
        for model in Self.models {
            XCTAssertEqual(picture(mouse(6), on: model), TriggerPicture(hold: .number(6)), "\(model)")
            let placed = picture(mouse(6, placed: .thumbPanel), on: model)
            let expected: TriggerPicture.Hold = model == .mxMaster4 ? .part(.thumbPanel) : .number(6)
            XCTAssertEqual(placed, TriggerPicture(hold: expected), "\(model)")
            let back = picture(mouse(7, placed: .backButton), on: model)
            XCTAssertEqual(back, TriggerPicture(hold: .part(.back)), "a place every drawing has: \(model)")
        }
    }

    /// Modifiers held with a button are caps of their own; the button is the part as above.
    func testModifiersOfAButtonAreCaps() {
        for model in Self.models {
            let back = picture(mouse(3, modifiers: option), on: model)
            XCTAssertEqual(back, TriggerPicture(hold: .part(.back), modifiers: ["⌥"]), "\(model)")
            let panel = picture(logitech(.thumbPanel, modifiers: control | command), on: model)
            XCTAssertEqual(panel.modifiers, ["⌃", "⌘"])
            let six = picture(mouse(6, modifiers: shift), on: model)
            XCTAssertEqual(six, TriggerPicture(hold: .number(6), modifiers: ["⇧"]))
        }
    }

    /// A key is its caps, on any drawing; no modifiers of a button.
    func testAKeyIsItsCaps() {
        let space = key(49, modifiers: control | option)
        let f13 = key(KeyCode.F13, modifiers: fn)
        for model in Self.models {
            XCTAssertEqual(picture(space, on: model), TriggerPicture(hold: .keys(["⌃", "⌥", "⎵"])))
            XCTAssertEqual(picture(f13, on: model), TriggerPicture(hold: .keys(["F13"])))
            XCTAssertNil(picture(space, on: model).litPart)
        }
    }

    /// Nothing does it: the default picture, on every drawing.
    func testNothingIsTheDefaultPicture() {
        for model in Self.models {
            XCTAssertEqual(picture(nil, on: model), .none)
            XCTAssertNil(TriggerPicture.none.hold)
            XCTAssertEqual(TriggerPicture.make(.none, mouse: model), .none)
        }
    }

    /// Only in an app: the app's trigger as above, and its path for the chip.
    func testOnlyInAnAppAddsItsChip() {
        for model in Self.models {
            let shown = picture(logitech(.thumbPanel), on: model, app: Self.notes)
            XCTAssertEqual(shown.appPath, Self.notes)
            XCTAssertEqual(shown.hold, model == .mxMaster4 ? .part(.thumbPanel) : .notDrawn(.thumbPanel))
            XCTAssertEqual(picture(key(49, modifiers: control | option), on: model, app: Self.notes).appPath, Self.notes)
        }
        XCTAssertNil(picture(mouse(3), on: .generic).appPath)
    }

    /// The roles come from a static table: no mouse needs to be connected. A role-less
    /// Logitech control is a badge of a button of this mouse, without a part.
    func testALogitechControlOfNoKnownRoleIsABadge() {
        let shown = TriggerPicture.make(
            TriggerPictureSource(event: logitech(.gesture)), mouse: .mxMaster4, logitechRole: { _ in nil }
        )
        XCTAssertEqual(shown, TriggerPicture(hold: .notDrawn(nil)))
    }

    // MARK: - Which trigger (TriggerPictureSource.make)

    func testTheSourceIsTheFirstTriggerThatDoesIt() {
        let gestures = ApplicationTriggerRule.gestureNavigation
        let ring = ApplicationTriggerRule.shortcutRing
        let panel = logitech(.thumbPanel)
        let space = key(49, modifiers: control | option)
        let general = [
            binding(mouse(4), SystemShortcut.copy),
            binding(mouse(5), SystemShortcut.mouseGestureNavigation, enabled: false),
            binding(panel, SystemShortcut.mouseGestureNavigation),
            binding(space, SystemShortcut.shortcutRing),
            binding(mouse(3), SystemShortcut.mouseGestureNavigation),
            binding(panel, SystemShortcut.shortcutRing),
        ]
        // First taken: not the disabled one, and the Buttons pane's order.
        XCTAssertEqual(TriggerPictureSource.make(rule: gestures, general: general, onlyInApps: nil), TriggerPictureSource(event: panel))
        XCTAssertEqual(TriggerPictureSource.make(rule: ring, general: general, onlyInApps: nil), TriggerPictureSource(event: space))
        // A key never runs the gestures; an unrunnable key never opens the ring.
        let plainKey = binding(key(40, modifiers: 0), SystemShortcut.shortcutRing)
        let commandKey = binding(key(40, modifiers: command), SystemShortcut.mouseGestureNavigation)
        XCTAssertEqual(TriggerPictureSource.make(rule: ring, general: [plainKey], onlyInApps: nil), .none)
        XCTAssertEqual(TriggerPictureSource.make(rule: gestures, general: [commandKey], onlyInApps: nil), .none)

        // With none of Buttons: the first app's first own trigger, and that app.
        let apps = ApplicationTriggers(
            applicationNames: ["Notes"], triggerTitles: ["Thumb panel"], path: Self.notes, bindingID: UUID(), trigger: panel
        )
        XCTAssertEqual(
            TriggerPictureSource.make(rule: gestures, general: [binding(mouse(4), SystemShortcut.copy)], onlyInApps: apps),
            TriggerPictureSource(event: panel, onlyInAppPath: Self.notes)
        )
        // Buttons' own wins over an app's.
        XCTAssertEqual(
            TriggerPictureSource.make(rule: gestures, general: general, onlyInApps: apps), TriggerPictureSource(event: panel)
        )
        // Neither.
        XCTAssertEqual(TriggerPictureSource.make(rule: gestures, general: [], onlyInApps: nil), .none)
        XCTAssertEqual(TriggerPictureSource.make(rule: ring, general: [], onlyInApps: ApplicationTriggers(applicationNames: [], triggerTitles: [])), .none)
    }

    /// The apps' entry carries its first app's first own trigger, the binding "Change" selects.
    func testTheAppsEntryCarriesItsFirstTrigger() throws {
        let panel = logitech(.thumbPanel)
        let notes = Application(path: Self.notes)
        let own = [binding(panel, SystemShortcut.mouseGestureNavigation), binding(mouse(3), SystemShortcut.mouseGestureNavigation)]
        let entry = try XCTUnwrap(ApplicationTriggers([(application: notes, bindings: own)], titles: { $0.map { "\($0.code)" } }))
        XCTAssertEqual(entry.trigger, panel)
        XCTAssertEqual(entry.bindingID, own[0].id)
        XCTAssertEqual(entry.path, Self.notes)
        XCTAssertNil(ApplicationTriggers(applicationNames: ["Notes"], triggerTitles: []).trigger, "nil unless given")
    }

    /// The Gestures pane's summary carries the picture's source (the Shortcut Ring pane's
    /// summary has its own).
    func testTheGesturesSummaryCarriesThePicture() {
        let panel = logitech(.thumbPanel)
        let summary = MouseGestureBindingSummary(
            bindings: [binding(mouse(4), SystemShortcut.copy), binding(panel, SystemShortcut.mouseGestureNavigation),
                       binding(mouse(3), SystemShortcut.mouseGestureNavigation)],
            isLogitechCode: { LogiCenter.shared.isLogiCode($0) }
        )
        XCTAssertEqual(summary.picture, TriggerPictureSource(event: panel))
        XCTAssertEqual(summary.buttonTitles.first, ButtonTriggerNaming.title(for: panel), "the first the row names")
        XCTAssertEqual(MouseGestureBindingSummary(bindings: [], isLogitechCode: { _ in false }).picture, .none)
        XCTAssertEqual(MouseGestureBindingSummary(hasGestureButton: false, hasLogitechGestureButton: false).picture, .none)
    }

    // MARK: - The keys of a trigger (capLabels)

    /// The same pieces as the row's title, one cap each.
    func testCapLabelsAreThePiecesOfTheTitle() {
        let cases: [(RecordedEvent, [String], String)] = [
            (key(49, modifiers: control | option), ["⌃", "⌥", "⎵"], "⌃⌥ ⎵"),
            // The Mac reports F-keys with Fn: it is not written.
            (key(KeyCode.F13, modifiers: fn), ["F13"], "F13"),
            (key(121, modifiers: control | option | shift | command | fn), ["⌃", "⌥", "⇧", "⌘", "PageDown"], "⌃⌥⇧⌘ PageDown"),
            // A modifier on its own: every modifier held, its own included.
            (key(KeyCode.optionL, modifiers: option), ["⌥"], "⌥"),
            (key(KeyCode.optionL, modifiers: option | control), ["⌃", "⌥"], "⌃⌥"),
            (key(49, modifiers: fn | command), ["Fn", "⌘", "⎵"], "Fn ⌘ ⎵"),
            (mouse(3, modifiers: option), ["⌥", "Back button"], "⌥ Back button"),
            (mouse(3), ["Back button"], "Back button"),
            (mouse(6, placed: .gestureButton), ["Gesture button (button 6)"], "Gesture button (button 6)"),
        ]
        for (event, caps, title) in cases {
            XCTAssertEqual(ButtonTriggerNaming.capLabels(for: event), caps, title)
            XCTAssertEqual(ButtonTriggerNaming.title(for: event), title)
        }
        // The pieces of `symbols` stay the title's.
        XCTAssertEqual(ButtonTriggerNaming.symbols(UInt64(fn | control | option)), "Fn ⌃⌥")
        XCTAssertEqual(ButtonTriggerNaming.symbols(UInt64(fn)), "Fn")
        XCTAssertEqual(ButtonTriggerNaming.symbols(UInt64(fn | command), includesFn: false), "⌘")
        XCTAssertEqual(ButtonTriggerNaming.modifierSymbols(UInt64(command | shift | control | option)), ["⌃", "⌥", "⇧", "⌘"])
    }

    // MARK: - The pieces

    /// The symbol of a button the drawing cannot show exists; were it ever missing, the
    /// badge is drawn without it (an accent disc) and nothing fails.
    func testTheBadgeSymbolLoadsAndItsLackDrawsAnEmptyBadge() throws {
        XCTAssertNotNil(TriggerBadge.symbol(height: 16), TriggerBadge.symbolName)
        XCTAssertNil(TriggerBadge.symbol(named: "no.such.symbol.scrollio", height: 16))
        let with = try render(size: NSSize(width: 20, height: 20)) { TriggerBadge.draw(.notDrawn(.thumbPanel), in: $0) }
        let without = try render(size: NSSize(width: 20, height: 20)) {
            TriggerBadge.draw(.notDrawn(.thumbPanel), in: $0, symbolName: "no.such.symbol.scrollio")
        }
        XCTAssertNotEqual(with.pixels, without.pixels, "the symbol shows on the badge")
        XCTAssertGreaterThan(try without.alpha(x: 10, y: 10), 0.9, "the disc is there without it")
        XCTAssertEqual(TriggerBadge.size(for: .notDrawn(nil), height: 16), NSSize(width: 16, height: 16))
        XCTAssertEqual(TriggerBadge.size(for: .number(6), height: 16).height, 16)
        XCTAssertGreaterThanOrEqual(TriggerBadge.size(for: .number(16), height: 16).width, 16)
        XCTAssertEqual(TriggerBadge.size(for: .part(.back), height: 16), .zero)
        XCTAssertEqual(TriggerBadge.font(height: 16).pointSize, 10, "16 pt: 10 pt bold")
        XCTAssertEqual(TriggerBadge.font(height: 20).pointSize, 12, "20 pt: the Buttons card's 12 pt")
    }

    /// What stands on the accent colour, the glyph of a pressed key and a badge's number or
    /// symbol, is near black on a light accent such as Yellow (white cannot be read there),
    /// as on the ring's lit places, and white on a dark one (F39).
    func testWhatStandsOnTheAccentCanBeReadOnAYellowAccent() throws {
        /// How many opaque pixels are near black, and how many near white.
        func inks(_ picture: Picture) -> (dark: Int, white: Int) {
            var dark = 0, white = 0
            for x in 0..<picture.rep.pixelsWide {
                for y in 0..<picture.rep.pixelsHigh {
                    guard let colour = picture.rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                          colour.alphaComponent > 0.9 else { continue }
                    if colour.brightnessComponent < 0.35 { dark += 1 }
                    if colour.brightnessComponent > 0.95, colour.saturationComponent < 0.15 { white += 1 }
                }
            }
            return (dark, white)
        }
        func key(_ accent: NSColor) throws -> Picture {
            return try render(size: NSSize(width: 40, height: 44)) { _ in
                ScrollPreviewKeyCap.draw(
                    glyph: "W", depth: 1, face: NSRect(x: 3, y: 3, width: 34, height: 34), travel: 4, cornerRadius: 6,
                    font: NSFont.systemFont(ofSize: 17, weight: .medium), accent: accent
                )
            }
        }
        func badge(_ hold: TriggerPicture.Hold, _ accent: NSColor) throws -> Picture {
            return try render(size: NSSize(width: 20, height: 20)) { TriggerBadge.draw(hold, in: $0, accent: accent) }
        }
        for picture in [try key(.systemYellow), try badge(.number(6), .systemYellow), try badge(.notDrawn(.thumbPanel), .systemYellow)] {
            let (dark, white) = inks(picture)
            XCTAssertGreaterThan(dark, 3, "near black on yellow")
            XCTAssertEqual(white, 0, "no white on yellow")
        }
        for picture in [try key(.systemBlue), try badge(.number(6), .systemBlue), try badge(.notDrawn(.thumbPanel), .systemBlue)] {
            XCTAssertGreaterThan(inks(picture).white, 3, "white on blue")
        }
    }

    /// The keys: the Scrolling pane's at 34 pt, as wide as the label needs, never narrower
    /// than tall; a placeholder is dashed and empty.
    func testTheKeyCapsSizes() throws {
        // As tall as the Scrolling pane's key; max(34, the label + 20) wide.
        XCTAssertEqual(TriggerKeyCap.size(label: "", faceHeight: 34), ScrollPreviewKeyCap.size, "the Scrolling pane's key")
        XCTAssertEqual(TriggerKeyCap.size(label: "⌥", faceHeight: 34).height, ScrollPreviewKeyCap.size.height)
        let label = NSAttributedString(string: "PageDown", attributes: [.font: TriggerKeyCap.font(faceHeight: 34)])
        XCTAssertEqual(TriggerKeyCap.size(label: "PageDown", faceHeight: 34).width, ceil(label.size().width) + 20 + 2 * TriggerKeyCap.margin)
        XCTAssertEqual(TriggerKeyCap.size(label: "⌥", faceHeight: 20).height, 20 + 2 + 2 * TriggerKeyCap.margin)
        let cap = TriggerKeyCap(label: "⌥", faceHeight: 24)
        XCTAssertEqual(cap.frame.size, TriggerKeyCap.size(label: "⌥", faceHeight: 24))
        XCTAssertNil(cap.hitTest(NSPoint(x: 5, y: 5)))
        XCTAssertFalse(cap.isAccessibilityElement())
        cap.label = "PageDown"
        XCTAssertEqual(cap.frame.size, TriggerKeyCap.size(label: "PageDown", faceHeight: 24), "it takes its label's width")

        // Pressed: the face takes the accent colour. A placeholder has no fill.
        let pressed = TriggerKeyCap(label: "⌥", faceHeight: 34)
        pressed.depth = 1
        let up = TriggerKeyCap(label: "⌥", faceHeight: 34)
        let blank = TriggerKeyCap(label: "", faceHeight: 34)
        blank.isPlaceholder = true
        let centre = (x: CGFloat(10), y: CGFloat(12))
        let accent = try XCTUnwrap(NSColor.controlAccentColor.usingColorSpace(.deviceRGB))
        let pressedColour = try snapshot(pressed).colour(x: centre.x, y: centre.y)
        let upColour = try snapshot(up).colour(x: centre.x, y: centre.y)
        XCTAssertLessThan(distance(pressedColour, accent), distance(upColour, accent))
        XCTAssertLessThan(try snapshot(blank).alpha(x: 19, y: 19), 0.05, "a placeholder is not filled")
        XCTAssertGreaterThan(try snapshot(blank).maxAlpha(), 0.3, "but outlined")
    }

    func testThePlaceholderIsARoundedRectangleOutsideThePart() {
        let rect = NSRect(x: 10, y: 10, width: 20, height: 4)
        let path = TriggerPlaceholder.path(around: rect)
        XCTAssertEqual(path.bounds, rect.insetBy(dx: -3, dy: -3))
        XCTAssertEqual(TriggerPlaceholder.outset, 3)
    }

    func testTheAppChipShowsTheAppsIconOrNothing() {
        let chip = TriggerAppChip()
        XCTAssertEqual(chip.frame.size, NSSize(width: 18, height: 18))
        XCTAssertTrue(chip.isHidden)
        XCTAssertNil(chip.image)
        chip.path = Self.notes
        XCTAssertFalse(chip.isHidden)
        XCTAssertNotNil(chip.image)
        let image = chip.image
        chip.path = Self.notes
        XCTAssertTrue(chip.image === image, "read once per new path")
        chip.path = nil
        XCTAssertTrue(chip.isHidden)
        XCTAssertNil(chip.hitTest(NSPoint(x: 9, y: 9)))
        XCTAssertFalse(chip.isAccessibilityElement())
    }

    // MARK: - Helpers

    private struct Picture {
        let rep: NSBitmapImageRep

        var pixels: Data {
            return Data(bytes: rep.bitmapData!, count: rep.bytesPerRow * rep.pixelsHigh)
        }

        func colour(x: CGFloat, y: CGFloat) throws -> NSColor {
            let scale = CGFloat(rep.pixelsWide) / rep.size.width
            let colour = try XCTUnwrap(rep.colorAt(x: Int(x * scale), y: Int(y * scale)))
            return try XCTUnwrap(colour.usingColorSpace(.deviceRGB))
        }

        func alpha(x: CGFloat, y: CGFloat) throws -> CGFloat {
            return try colour(x: x, y: y).alphaComponent
        }

        func maxAlpha() throws -> CGFloat {
            var most: CGFloat = 0
            for x in 0..<rep.pixelsWide {
                for y in 0..<rep.pixelsHigh {
                    most = max(most, rep.colorAt(x: x, y: y)?.alphaComponent ?? 0)
                }
            }
            return most
        }
    }

    private final class Canvas: NSView {
        var body: (NSRect) -> Void = { _ in }
        override var isFlipped: Bool { return true }
        override func draw(_ dirtyRect: NSRect) { body(bounds) }
    }

    private func render(size: NSSize, _ body: @escaping (NSRect) -> Void) throws -> Picture {
        let canvas = Canvas(frame: NSRect(origin: .zero, size: size))
        canvas.appearance = NSAppearance(named: .aqua)
        canvas.body = body
        return try snapshot(canvas)
    }

    private func snapshot(_ view: NSView) throws -> Picture {
        if view.appearance == nil {
            view.appearance = NSAppearance(named: .aqua)
        }
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        return Picture(rep: rep)
    }

    private func distance(_ a: NSColor, _ b: NSColor) -> CGFloat {
        return abs(a.redComponent - b.redComponent) + abs(a.greenComponent - b.greenComponent) + abs(a.blueComponent - b.blueComponent)
    }
}
