//
//  ShortcutRingRenderTests.swift
//  ScrollioTests
//
//  Pictures of the Shortcut Ring, drawn off screen for a look at them: a contact sheet of
//  its states in each of its three materials (light and dark), a strip of its opening and
//  the frames of a short demo. Nothing is captured from a screen: the ring is drawn by the
//  app's own code (`ShortcutRingArtwork`, at the moments `ShortcutRingDrops` gives) over a
//  painted desktop, and the demo's ring is driven by the app's own rules
//  (`ShortcutRingSession`) along a scripted pointer path.
//
//  What the pictures cannot show: Liquid Glass and the blurred material (only the window
//  server draws them). Their rows are stand-ins, flat fills painted here and labelled so:
//  where the drops are, how large, what stands in them and the lit colour are the app's;
//  the glass itself (its bending of what is behind it, its highlights, drops flowing into
//  each other) and the blur are not. The row of drawn drops is exact: it is what "Reduce
//  transparency" and "Increase contrast" show. Nothing of a real screen, a real app in
//  front or a real mouse is in any of them.
//
//  Only runs when asked to:
//  `TEST_RUNNER_SCROLLIO_SHOTS_DIR=<folder> xcodebuild … test -only-testing:ScrollioTests/ShortcutRingRenderTests`.
//  The sheets are written to the folder itself (`drops-sheet-light.png`, `drops-sheet-dark.png`,
//  `drops-opening.png`), the demo's frames to `frames/` inside it.
//

import XCTest
@testable import Scrollio_Debug

final class ShortcutRingRenderTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = try RenderShots.directory(for: "the Shortcut Ring")
        try ForcedAppAccent.install()
    }

    override func tearDown() {
        ForcedAppAccent.uninstall()
        super.tearDown()
    }

    // MARK: - The contact sheets

    /// What a row of the sheet is made of.
    private enum Look {
        /// Liquid Glass, as a flat stand-in.
        case glass
        /// The blurred material, as a flat stand-in.
        case blur
        /// Drawn drops: exactly what the app paints.
        case drawn

        var title: String {
            switch self {
            case .glass: return "Liquid Glass (macOS 26 and later)  ·  STAND-IN: flat fills where the system draws glass"
            case .blur: return "Blurred material (macOS 14 and 15)  ·  STAND-IN: flat fills where the system blurs the desktop"
            case .drawn: return "Drawn (Reduce transparency, Increase contrast)  ·  EXACT: what the app paints"
            }
        }

        var note: String {
            switch self {
            case .glass:
                return "Stand-in. Real glass bends and brightens what is behind it, has its own highlights and "
                    + "shadow, and lets drops flow into each other while they are close. None of that can be "
                    + "drawn off screen. Exact here: where each drop is, its size, the symbols (in the label "
                    + "colour inside the glass) and the lit drop's accent tint."
            case .blur:
                return "Stand-in. The real material blurs the desktop behind each drop (the same material the "
                    + "ring's disc had). Exact here: the drops' places and sizes, the thin rim, the symbols and "
                    + "the lit colour."
            case .drawn:
                return ""
            }
        }
    }

    private struct Cell {
        var caption: String
        var ring = ShortcutRingSettings.default
        /// The ring's middle and the pointer's tip, from the cell's top left corner.
        var centre = CGPoint(x: 160, y: 140)
        var pointer = CGPoint(x: 160, y: 140)
        var lit: Int?
        var isCorner = false
        var increasesContrast = false
        var showsClick = false
    }

    private static let cellSize = CGSize(width: 320, height: 280)

    private static var cells: [Cell] {
        let middle = CGPoint(x: 160, y: 140)
        func towards(_ place: Int, _ distance: CGFloat) -> CGPoint {
            let offset = ShortcutRingGeometry.offset(ofPlace: place, radius: distance)
            return CGPoint(x: middle.x + offset.x, y: middle.y + offset.y)
        }
        // A ring of one's own: an app, a recorded key combination, two empty places.
        var withGaps = ShortcutRingSettings.default
        withGaps[1] = ShortcutRingPlace(openTarget: OpenTargetPayload(
            path: "/System/Applications/Calculator.app", bundleID: "com.apple.calculator", arguments: "", kind: .application
        ))
        withGaps[3] = .empty
        withGaps[5] = .empty
        withGaps[7] = ShortcutRingPlace(action: "custom::40:1179648")   // ⇧⌘K
        let corner = ShortcutRingGeometry.centre(
            forPointer: CGPoint(x: 5, y: 6), in: CGRect(origin: .zero, size: cellSize)
        )
        return [
            Cell(caption: "Just opened and settled, at the pointer"),
            Cell(caption: "Hold and move towards a shortcut: its drop grows and lights", pointer: towards(5, 52), lit: 5),
            Cell(caption: "An app, your own key combination; an empty place is a small faint drop",
                 ring: withGaps, pointer: towards(1, 56), lit: 1),
            Cell(caption: "Left open after a press: point at a shortcut and click",
                 pointer: CGPoint(x: middle.x + 90, y: middle.y + 10), lit: 2, showsClick: true),
            Cell(caption: "In a corner the whole ring stays on screen",
                 centre: corner, pointer: CGPoint(x: 5, y: 6), lit: 7, isCorner: true),
        ]
    }

    func testRenderTheDropsSheets() throws {
        let margin: CGFloat = 24, gap: CGFloat = 16, captionHeight: CGFloat = 36, headerHeight: CGFloat = 26
        let cell = Self.cellSize
        let looks: [Look] = [.glass, .blur, .drawn]
        let columns = 6
        let rowHeight = headerHeight + cell.height + captionHeight
        let size = CGSize(
            width: margin * 2 + CGFloat(columns) * cell.width + CGFloat(columns - 1) * gap,
            height: margin * 2 + CGFloat(looks.count) * rowHeight + CGFloat(looks.count - 1) * gap
        )
        for (suffix, name) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let dark = name == .darkAqua
            try render(size: size, scale: 2, appearance: name, to: directory.appendingPathComponent("drops-sheet-\(suffix).png")) {
                (dark ? NSColor(white: 0.11, alpha: 1) : NSColor(white: 0.95, alpha: 1)).setFill()
                CGRect(origin: .zero, size: size).fill()
                for (row, look) in looks.enumerated() {
                    // The sheet is drawn with y upwards: the first row is the top one.
                    let top = size.height - margin - CGFloat(row) * (rowHeight + gap)
                    RingMock.drawText(
                        look.title, in: CGRect(x: margin, y: top - headerHeight, width: size.width - margin * 2, height: headerHeight - 6),
                        size: 13, weight: .semibold, alignment: .left, dark: dark
                    )
                    var items = Self.cells
                    if look == .drawn {
                        let up = ShortcutRingGeometry.offset(ofPlace: 0, radius: 52)
                        items.append(Cell(
                            caption: "With Increase contrast: firm outlines",
                            pointer: CGPoint(x: 160 + up.x, y: 140 + up.y), lit: 0, increasesContrast: true
                        ))
                    }
                    for (column, item) in items.enumerated() {
                        let origin = CGPoint(x: margin + CGFloat(column) * (cell.width + gap), y: top - headerHeight - cell.height)
                        RingMock.drawCell(item, look: look, in: CGRect(origin: origin, size: cell), dark: dark)
                        RingMock.drawText(
                            item.caption,
                            in: CGRect(x: origin.x, y: origin.y - captionHeight, width: cell.width, height: captionHeight - 6),
                            size: 12, weight: .medium, alignment: .center, dark: dark
                        )
                    }
                    if !look.note.isEmpty {
                        let x = margin + CGFloat(columns - 1) * (cell.width + gap)
                        RingMock.drawText(
                            look.note,
                            in: CGRect(x: x + 8, y: top - headerHeight - cell.height + 20, width: cell.width - 16, height: cell.height - 40),
                            size: 13, weight: .regular, alignment: .left, dark: dark
                        )
                    }
                }
            }
        }
    }

    // MARK: - The opening

    /// The opening at six moments, each as the app has it then (`ShortcutRingDrops.frame`):
    /// drawn drops (exact), the glass stand-in, and a ring whose top right place is lit
    /// from 40 ms on: the ring is used while it opens.
    func testRenderTheOpeningStrip() throws {
        let moments: [TimeInterval] = [0, 0.040, 0.080, 0.120, 0.200, 0.350]
        let margin: CGFloat = 24, gap: CGFloat = 14, headerHeight: CGFloat = 26, captionHeight: CGFloat = 24
        let cell = CGSize(width: 290, height: 270)
        let rows: [(title: String, look: Look, litFrom: TimeInterval?)] = [
            ("Drawn drops  ·  EXACT", .drawn, nil),
            ("Liquid Glass  ·  STAND-IN (real glass drops flow into each other while they are this close)", .glass, nil),
            ("Drawn drops, the hand already moving: the top right place is lit from 40 ms on  ·  EXACT", .drawn, 0.040),
        ]
        let rowHeight = headerHeight + cell.height + captionHeight
        let size = CGSize(
            width: margin * 2 + CGFloat(moments.count) * cell.width + CGFloat(moments.count - 1) * gap,
            height: margin * 2 + CGFloat(rows.count) * rowHeight + CGFloat(rows.count - 1) * gap
        )
        let face = ShortcutRingFace(.default)
        try render(size: size, scale: 2, appearance: .aqua, to: directory.appendingPathComponent("drops-opening.png")) {
            NSColor(white: 0.95, alpha: 1).setFill()
            CGRect(origin: .zero, size: size).fill()
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            for (row, item) in rows.enumerated() {
                let top = size.height - margin - CGFloat(row) * (rowHeight + gap)
                RingMock.drawText(
                    item.title, in: CGRect(x: margin, y: top - headerHeight, width: size.width - margin * 2, height: headerHeight - 6),
                    size: 13, weight: .semibold, alignment: .left, dark: false
                )
                for (column, moment) in moments.enumerated() {
                    let rect = CGRect(
                        x: margin + CGFloat(column) * (cell.width + gap), y: top - headerHeight - cell.height,
                        width: cell.width, height: cell.height
                    )
                    var lighting = ShortcutRingDrops.Lighting()
                    if let litFrom = item.litFrom, moment >= litFrom {
                        lighting.light(1, at: litFrom, filled: face.filled)
                    }
                    let drops = ShortcutRingDrops.frame(at: moment, filled: face.filled, lit: lighting.amounts(at: moment))
                    context.saveGState()
                    NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12).addClip()
                    RingMock.drawDesktop(in: rect, dark: false)
                    let centre = CGPoint(x: rect.midX, y: rect.midY)
                    RingMock.drawRing(
                        face, drops: drops, title: lighting.target.map { face.places[$0].title }, centre: centre, look: item.look
                    )
                    // Towards the lit place, beside the hub's name.
                    let pointer = lighting.target == nil
                        ? centre
                        : CGPoint(x: centre.x + 36, y: centre.y + 36)
                    RingMock.drawPointer(at: pointer)
                    context.restoreGState()
                    RingMock.drawText(
                        "\(Int((moment * 1000).rounded())) ms",
                        in: CGRect(x: rect.minX, y: rect.minY - captionHeight, width: rect.width, height: captionHeight - 4),
                        size: 12, weight: .medium, alignment: .center, dark: false
                    )
                }
            }
        }
    }

    // MARK: - The panel's own views

    /// The views the panel shows (`ShortcutRingDropsView`), not the artwork's drawing of
    /// the ring: what stands in each drop is a view of its own that is moved and scaled,
    /// and this is the look at where those views are. Drawn in-process and therefore on
    /// a plain ground, black or white as AppKit's cache gives it (such a picture has no
    /// desktop behind the ring): the drawn drops are complete; the blurred material and
    /// the glass are flat discs, and the lit glass drop's tint, which is the glass's, is
    /// not there at all.
    func testRenderThePanelsOwnViews() throws {
        var cells: [(caption: String, appearance: ShortcutRingAppearance, elapsed: TimeInterval, lit: Int?)] = [
            ("Drawn, 60 ms after it opened", ShortcutRingAppearance(reducesTransparency: true), 0.06, nil),
            ("Drawn, 60 ms, the top right place already lit", ShortcutRingAppearance(reducesTransparency: true), 0.06, 1),
            ("Drawn, at rest, a place lit", ShortcutRingAppearance(reducesTransparency: true), 1, 5),
            ("Increase contrast, at rest, a place lit", ShortcutRingAppearance(increasesContrast: true), 1, 0),
            ("Blur: the material is a flat grey here; the mask of nine circles and the lit colour are real",
             ShortcutRingAppearance(), 1, 5),
        ]
        if #available(macOS 26.0, *) {
            cells.append((
                "Glass: flat discs here, and the lit drop's tint is missing; where the drops and symbols are is real",
                ShortcutRingAppearance(hasLiquidGlass: true), 1, 5
            ))
        }
        let margin: CGFloat = 24, gap: CGFloat = 14, captionHeight: CGFloat = 50, headerHeight: CGFloat = 30
        let side = ShortcutRingGeometry.canvasSide
        let cell = CGSize(width: side + 12, height: side + 12)
        let names: [NSAppearance.Name] = [.aqua, .darkAqua]
        let size = CGSize(
            width: margin * 2 + CGFloat(cells.count) * cell.width + CGFloat(cells.count - 1) * gap,
            height: margin * 2 + headerHeight + CGFloat(names.count) * (cell.height + captionHeight) + gap
        )
        let screen = ShortcutRingScreen(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982), usable: CGRect(x: 0, y: 0, width: 1512, height: 982)
        )
        // Each ring's views, drawn into a bitmap of their own.
        var pictures: [[NSBitmapImageRep]] = []
        for name in names {
            var row: [NSBitmapImageRep] = []
            for item in cells {
                let presenter = ShortcutRingPanelPresenter()
                var now: TimeInterval = 0
                presenter.orderFront = { _ in }
                presenter.after = { _, _ in }
                presenter.clock = { now }
                presenter.appearance = { item.appearance }
                presenter.show(ShortcutRingFace(.default), centre: CGPoint(x: 600, y: 400), screen: screen, lit: item.lit, takesClicks: false)
                now = item.elapsed
                presenter.step()
                let drops = try XCTUnwrap(presenter.stage?.dropsView)
                drops.appearance = NSAppearance(named: name)
                drops.layoutSubtreeIfNeeded()
                drops.display()
                // A bitmap of its own that starts clear: the ring has no ground.
                let rep = try XCTUnwrap(NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: Int(side * 2), pixelsHigh: Int(side * 2),
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
                ))
                rep.size = drops.bounds.size
                drops.cacheDisplay(in: drops.bounds, to: rep)
                row.append(rep)
                presenter.hide()
            }
            pictures.append(row)
        }
        try render(size: size, scale: 2, appearance: .aqua, to: directory.appendingPathComponent("drops-views.png")) {
            NSColor(white: 0.95, alpha: 1).setFill()
            CGRect(origin: .zero, size: size).fill()
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            RingMock.drawText(
                "The panel's own views, drawn in-process on a plain ground (light above, dark below). A check of where the "
                    + "views are, NOT how the ring looks on a screen.",
                in: CGRect(x: margin, y: size.height - margin - headerHeight, width: size.width - margin * 2, height: headerHeight - 8),
                size: 13, weight: .semibold, alignment: .left, dark: false
            )
            for row in names.indices {
                for (column, item) in cells.enumerated() {
                    let rect = CGRect(
                        x: margin + CGFloat(column) * (cell.width + gap),
                        y: size.height - margin - headerHeight - CGFloat(row + 1) * cell.height - CGFloat(row) * (captionHeight + gap),
                        width: cell.width, height: cell.height
                    )
                    context.saveGState()
                    NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12).addClip()
                    NSColor.black.setFill()
                    rect.fill()
                    pictures[row][column].draw(in: rect.insetBy(dx: 6, dy: 6))
                    context.restoreGState()
                    RingMock.drawText(
                        item.caption, in: CGRect(x: rect.minX, y: rect.minY - captionHeight, width: rect.width, height: captionHeight - 6),
                        size: 12, weight: .medium, alignment: .center, dark: false
                    )
                }
            }
        }
    }

    // MARK: - The demo

    /// The demo's frames, in four parts (each test has its time limit).
    func testRenderTheDemosFrames1() throws { try renderDemoFrames(part: 0) }
    func testRenderTheDemosFrames2() throws { try renderDemoFrames(part: 1) }
    func testRenderTheDemosFrames3() throws { try renderDemoFrames(part: 2) }
    func testRenderTheDemosFrames4() throws { try renderDemoFrames(part: 3) }

    /// Eight frames of the demo side by side, for a look without a player.
    func testRenderTheDemosStrip() throws {
        let frames = RingDemo.frames()
        // At rest, the press, a place lit, its action ran; the tap with its press mark, a
        // place pointed at, "… and click it", the click's action ran.
        let picks = [30, 43, 102, 150, 222, 324, 396, 436].map { min($0, frames.count - 1) }
        let scene = RingDemo.sceneSize
        let scale: CGFloat = 0.5
        let cellSize = CGSize(width: scene.width * scale, height: scene.height * scale)
        let gap: CGFloat = 8
        let size = CGSize(width: cellSize.width * 4 + gap * 5, height: cellSize.height * 2 + gap * 3)
        try render(size: size, scale: 2, appearance: .aqua, to: directory.appendingPathComponent("ring-demo-strip.png")) {
            NSColor(white: 0.95, alpha: 1).setFill()
            CGRect(origin: .zero, size: size).fill()
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            for (index, pick) in picks.enumerated() {
                let column = index % 4, row = index / 4
                context.saveGState()
                context.translateBy(
                    x: gap + CGFloat(column) * (cellSize.width + gap),
                    y: size.height - gap - CGFloat(row + 1) * cellSize.height - CGFloat(row) * gap
                )
                context.scaleBy(x: scale, y: scale)
                context.clip(to: CGRect(origin: .zero, size: scene))
                RingDemo.draw(frames[pick], dark: false)
                context.restoreGState()
            }
        }
    }

    private func renderDemoFrames(part: Int) throws {
        let folder = directory.appendingPathComponent("frames", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let frames = RingDemo.frames()
        XCTAssertEqual(frames.count, RingDemo.frameCount)
        let perPart = frames.count / 4
        let range = (part * perPart)..<(part == 3 ? frames.count : (part + 1) * perPart)
        for index in range {
            let url = folder.appendingPathComponent(String(format: "frame-%04d.png", index))
            try render(size: RingDemo.sceneSize, scale: 2, appearance: .aqua, to: url) {
                RingDemo.draw(frames[index], dark: false)
            }
        }
    }

    // MARK: - Drawing into a file

    /// `draw`, in a context `size` large with y upwards and in `appearance`, written at
    /// `scale` pixels per point.
    private func render(size: CGSize, scale: CGFloat, appearance name: NSAppearance.Name, to url: URL, draw: () -> Void) throws {
        let canvas = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        canvas.size = size
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: canvas))
        let appearance = try XCTUnwrap(NSAppearance(named: name))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        appearance.performAsCurrentDrawingAppearance(draw)
        NSGraphicsContext.restoreGraphicsState()
        let png = try XCTUnwrap(canvas.representation(using: .png, properties: [:]))
        try png.write(to: url)
    }

    // MARK: - A painted desktop, a pointer and the ring on them

    private enum RingMock {

        /// A soft wallpaper with a window on it, so the ring is seen over something.
        static func drawDesktop(in rect: CGRect, dark: Bool, window: Bool = true) {
            let start = dark ? NSColor(srgbRed: 0.09, green: 0.14, blue: 0.27, alpha: 1) : NSColor(srgbRed: 0.72, green: 0.84, blue: 0.97, alpha: 1)
            let end = dark ? NSColor(srgbRed: 0.20, green: 0.12, blue: 0.30, alpha: 1) : NSColor(srgbRed: 0.90, green: 0.82, blue: 0.96, alpha: 1)
            NSGradient(starting: start, ending: end)?.draw(in: rect, angle: -35)
            guard window else { return }
            let frame = CGRect(x: rect.minX + rect.width * 0.14, y: rect.minY + rect.height * 0.12, width: rect.width * 0.72, height: rect.height * 0.70)
            let path = NSBezierPath(roundedRect: frame, xRadius: 10, yRadius: 10)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor(white: 0, alpha: dark ? 0.5 : 0.22)
            shadow.shadowBlurRadius = 18
            shadow.shadowOffset = NSSize(width: 0, height: -6)
            shadow.set()
            (dark ? NSColor(white: 0.17, alpha: 1) : NSColor(white: 0.99, alpha: 1)).setFill()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()
            // A title bar's three dots and a few lines of "text".
            for (index, colour) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
                colour.withAlphaComponent(0.85).setFill()
                NSBezierPath(ovalIn: CGRect(x: frame.minX + 12 + CGFloat(index) * 16, y: frame.maxY - 20, width: 10, height: 10)).fill()
            }
            let line = dark ? NSColor(white: 1, alpha: 0.10) : NSColor(white: 0, alpha: 0.09)
            line.setFill()
            var y = frame.maxY - 48
            var index = 0
            while y > frame.minY + 16 {
                let width = frame.width * [0.82, 0.74, 0.86, 0.55, 0.80, 0.68, 0.84, 0.40][index % 8] - 32
                NSBezierPath(roundedRect: CGRect(x: frame.minX + 16, y: y, width: max(20, width), height: 7), xRadius: 3.5, yRadius: 3.5).fill()
                y -= 18
                index += 1
            }
        }

        /// The arrow pointer with its tip at `tip` (y upwards).
        static func drawPointer(at tip: CGPoint) {
            let points: [CGPoint] = [
                CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 16.6), CGPoint(x: 3.9, y: 13.0), CGPoint(x: 6.7, y: 19.4),
                CGPoint(x: 9.2, y: 18.3), CGPoint(x: 6.4, y: 12.1), CGPoint(x: 11.8, y: 12.1),
            ]
            let path = NSBezierPath()
            for (index, point) in points.enumerated() {
                let p = CGPoint(x: tip.x + point.x, y: tip.y - point.y)
                if index == 0 { path.move(to: p) } else { path.line(to: p) }
            }
            path.close()
            path.lineJoinStyle = .round
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor(white: 0, alpha: 0.35)
            shadow.shadowBlurRadius = 3
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.set()
            NSColor.white.setStroke()
            path.lineWidth = 2.4
            path.stroke()
            NSGraphicsContext.restoreGraphicsState()
            NSColor.black.setFill()
            path.fill()
        }

        /// The ring as the app draws it at one moment. Drawn drops are the app's own; for
        /// glass and the blur a flat fill is painted here where the system would draw.
        static func drawRing(
            _ face: ShortcutRingFace, drops: ShortcutRingDrops.Frame, title: String?, centre: CGPoint,
            look: Look, increasesContrast: Bool = false
        ) {
            var style = ShortcutRingArtwork.Style()
            style.increasesContrast = increasesContrast
            switch look {
            case .drawn:
                style.backdrop = .drawn
            case .blur:
                style.backdrop = .material
                drawStandIn(drops, centre: centre, look: .blur)
            case .glass:
                style.backdrop = .glass
                drawStandIn(drops, centre: centre, look: .glass)
            }
            ShortcutRingArtwork.draw(face, drops: drops, title: title, centre: centre, style: style)
        }

        /// Flat fills where the system draws a material. Not the app's code.
        static func drawStandIn(_ drops: ShortcutRingDrops.Frame, centre: CGPoint, look: Look) {
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            let dark = ShortcutRingArtwork.isDark()
            for drop in drops.all where drop.diameter > 0 {
                let circle = ShortcutRingArtwork.circle(of: drop, centre: centre)
                // Glass is never faded; the blurred material is as faint as its drop.
                let alpha = look == .glass ? 1 : drop.opacity
                guard alpha > 0 else { continue }
                context.saveGState()
                context.setAlpha(alpha)
                context.beginTransparencyLayer(auxiliaryInfo: nil)
                switch look {
                case .glass:
                    context.setShadow(offset: CGSize(width: 0, height: -2), blur: 8, color: NSColor(white: 0, alpha: 0.18).cgColor)
                    let clear = dark ? NSColor(white: 0.32, alpha: 0.55) : NSColor(white: 1, alpha: 0.50)
                    ShortcutRingArtwork.blend(clear, ShortcutRingArtwork.litFill.withAlphaComponent(0.88), drop.lit).setFill()
                    NSBezierPath(ovalIn: circle).fill()
                    context.setShadow(offset: .zero, blur: 0, color: nil)
                    let edge = NSBezierPath(ovalIn: circle.insetBy(dx: 0.5, dy: 0.5))
                    edge.lineWidth = 1
                    NSColor(white: 1, alpha: dark ? 0.30 : 0.75).setStroke()
                    edge.stroke()
                case .blur:
                    (dark ? NSColor(white: 0.17, alpha: 0.82) : NSColor(white: 0.95, alpha: 0.82)).setFill()
                    NSBezierPath(ovalIn: circle).fill()
                case .drawn:
                    break
                }
                context.endTransparencyLayer()
                context.restoreGState()
            }
        }

        /// The trigger's press, made visible: two rings in the accent colour that widen
        /// around the pointer and fade, the first at once, the second a little later.
        static func drawPress(at tip: CGPoint, progress: CGFloat) {
            for delay in [0, 0.25] as [CGFloat] {
                let own = (progress - delay) / 0.6
                guard own >= 0, own <= 1 else { continue }
                let radius = 9 + 22 * own
                let path = NSBezierPath(ovalIn: CGRect(x: tip.x - radius, y: tip.y - radius, width: radius * 2, height: radius * 2))
                path.lineWidth = 3
                NSColor.controlAccentColor.withAlphaComponent(0.9 * (1 - own)).setStroke()
                path.stroke()
            }
        }

        /// A click: a ring around the pointer's tip.
        static func drawClick(at tip: CGPoint, progress: CGFloat = 0.5) {
            let radius = 6 + 12 * progress
            let path = NSBezierPath(ovalIn: CGRect(x: tip.x - radius, y: tip.y - radius, width: radius * 2, height: radius * 2))
            path.lineWidth = 2
            NSColor.white.withAlphaComponent(0.9 * (1 - progress)).setStroke()
            path.stroke()
        }

        static func drawCell(_ cell: Cell, look: Look, in rect: CGRect, dark: Bool) {
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            context.saveGState()
            NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12).addClip()
            drawDesktop(in: rect, dark: dark, window: !cell.isCorner)
            if cell.isCorner {
                // The top left corner of a screen: its menu bar.
                (dark ? NSColor(white: 0.12, alpha: 0.85) : NSColor(white: 1, alpha: 0.70)).setFill()
                CGRect(x: rect.minX, y: rect.maxY - 24, width: rect.width, height: 24).fill()
                let ink = dark ? NSColor(white: 1, alpha: 0.85) : NSColor(white: 0, alpha: 0.8)
                var x = rect.minX + 44
                for width in [38, 26, 30, 34, 44] as [CGFloat] {
                    ink.withAlphaComponent(0.35).setFill()
                    NSBezierPath(roundedRect: CGRect(x: x, y: rect.maxY - 15, width: width, height: 6), xRadius: 3, yRadius: 3).fill()
                    x += width + 14
                }
            }
            // The cell's own coordinates grow downwards from its top left corner.
            func point(_ p: CGPoint) -> CGPoint {
                return CGPoint(x: rect.minX + p.x, y: rect.maxY - p.y)
            }
            let face = ShortcutRingFace(cell.ring)
            let lit = cell.lit.flatMap { face.filled[$0] ? $0 : nil }
            drawRing(
                face, drops: ShortcutRingDrops.settled(filled: face.filled, lit: lit),
                title: lit.map { face.places[$0].title }, centre: point(cell.centre),
                look: look, increasesContrast: cell.increasesContrast
            )
            if cell.showsClick {
                drawClick(at: point(cell.pointer))
            }
            drawPointer(at: point(cell.pointer))
            context.restoreGState()
        }

        static func drawText(
            _ text: String, in rect: CGRect, size: CGFloat, weight: NSFont.Weight, alignment: NSTextAlignment, dark: Bool
        ) {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = alignment
            paragraph.lineBreakMode = .byWordWrapping
            let string = NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: weight),
                .foregroundColor: dark ? NSColor(white: 1, alpha: 0.78) : NSColor(white: 0, alpha: 0.70),
                .paragraphStyle: paragraph,
            ])
            string.draw(with: rect, options: [.usesLineFragmentOrigin])
        }
    }

    // MARK: - The demo's script

    /// Eight seconds: the hold way once, the click way once. The ring's state in every
    /// frame is what `ShortcutRingSession` says for the pointer's path.
    private enum RingDemo {

        static let sceneSize = CGSize(width: 640, height: 400)
        static let frameRate = 60
        static let frameCount = 480

        struct Frame {
            /// Scene coordinates, y downwards (as the session's).
            var pointer = CGPoint.zero
            var ringCentre: CGPoint?
            var lit: Int?
            /// How long the ring has been open.
            var openElapsed: TimeInterval = 0
            /// How far each place is lit (`ShortcutRingDrops.Lighting`).
            var litAmounts: [CGFloat] = []
            var caption = ""
            var isTriggerHeld = false
            /// 0 … 1 while a click's ripple shows.
            var click: CGFloat?
            /// 0 … 1 for a second after the trigger went down: the press, made visible.
            var press: CGFloat?
        }

        private static func ease(_ t: CGFloat) -> CGFloat {
            let x = min(max(t, 0), 1)
            return x * x * (3 - 2 * x)
        }

        /// Where the pointer is at `time`: straight moves between the stops, eased.
        private static func pointer(at time: Double) -> CGPoint {
            let stops: [(time: Double, point: CGPoint)] = [
                (0.0, CGPoint(x: 250, y: 190)), (0.85, CGPoint(x: 250, y: 190)),
                (1.55, CGPoint(x: 202, y: 238)),            // towards "Copy", bottom left
                (2.5, CGPoint(x: 202, y: 238)),
                (3.3, CGPoint(x: 400, y: 200)), (4.7, CGPoint(x: 400, y: 200)),
                (5.3, CGPoint(x: 466, y: 152)),             // over the top right place
                (5.6, CGPoint(x: 466, y: 152)),
                (6.1, CGPoint(x: 492, y: 210)),             // over the right place
                (8.0, CGPoint(x: 492, y: 210)),
            ]
            guard let next = stops.firstIndex(where: { $0.time >= time }), next > 0 else {
                return time <= 0 ? stops[0].point : stops[stops.count - 1].point
            }
            let a = stops[next - 1], b = stops[next]
            let t = ease(CGFloat((time - a.time) / (b.time - a.time)))
            return CGPoint(x: a.point.x + (b.point.x - a.point.x) * t, y: a.point.y + (b.point.y - a.point.y) * t)
        }

        static func frames() -> [Frame] {
            let pressAt = 0.6, releaseAt = 2.3
            let tapDownAt = 3.6, tapUpAt = 3.72
            // "… and click it" stands for a second before the click comes.
            let clickCaptionAt = 6.1, clickDownAt = 7.0, clickUpAt = 7.12
            let pressMarkLasts = 1.0
            let screen = CGRect(origin: .zero, size: sceneSize)
            let filled = ShortcutRingSettings.default.filled
            var session = ShortcutRingSession()
            var frames: [Frame] = []
            var previous = pointer(at: 0)
            var openedAt: Double?
            var caption = "Hold the button …"
            var ran: (title: String, at: Double)?
            let face = ShortcutRingFace(.default)
            var lighting = ShortcutRingDrops.Lighting()

            func handle(_ commands: [ShortcutRingSession.Command], at time: Double) {
                for command in commands {
                    switch command {
                    case .open:
                        openedAt = time
                        lighting = ShortcutRingDrops.Lighting()
                    case .close: openedAt = nil
                    case .run(let place): ran = (face.places[place].title, time)
                    case .light: break
                    }
                }
            }

            for index in 0..<frameCount {
                let time = Double(index) / Double(frameRate)
                let step = 1.0 / Double(frameRate)
                func happens(_ moment: Double) -> Bool { return time >= moment && time - step < moment }
                let now = pointer(at: time)
                let delta = CGPoint(x: now.x - previous.x, y: now.y - previous.y)
                previous = now

                if happens(pressAt) {
                    handle(session.triggerPressed(at: time, pointer: now, screen: screen, filled: filled), at: time)
                    caption = "Hold the button and move towards a shortcut"
                }
                if happens(tapDownAt) {
                    handle(session.triggerPressed(at: time, pointer: now, screen: screen, filled: filled), at: time)
                    caption = "Or press it and let go: the ring stays open"
                }
                if delta != .zero {
                    handle(session.pointerMoved(by: delta, to: now, at: time), at: time)
                }
                if happens(releaseAt) {
                    handle(session.triggerReleased(at: time), at: time)
                }
                if happens(tapUpAt) {
                    handle(session.triggerReleased(at: time), at: time)
                }
                if happens(tapDownAt + pressMarkLasts + 0.1) { caption = "Point at a shortcut …" }
                if happens(clickCaptionAt) { caption = "… and click it" }
                if happens(clickDownAt) {
                    handle(session.buttonPressed(0, at: now), at: time)
                }
                if happens(clickUpAt) {
                    handle(session.buttonReleased(0), at: time)
                }
                if let ran, happens(ran.at) {
                    caption = "\(ran.title) runs"
                }

                var frame = Frame()
                frame.pointer = now
                frame.caption = caption
                frame.lit = session.lit
                frame.isTriggerHeld = session.phase == .held
                if session.isOpen, let openedAt {
                    frame.ringCentre = session.centre
                    frame.openElapsed = time - openedAt
                    lighting.light(session.lit, at: time, filled: filled)
                    frame.litAmounts = lighting.amounts(at: time)
                }
                if time >= clickDownAt, time < clickDownAt + 0.35 {
                    frame.click = CGFloat((time - clickDownAt) / 0.35)
                }
                for down in [pressAt, tapDownAt] where time >= down && time < down + pressMarkLasts {
                    frame.press = CGFloat((time - down) / pressMarkLasts)
                }
                frames.append(frame)
            }
            return frames
        }

        static func draw(_ frame: Frame, dark: Bool) {
            let scene = CGRect(origin: .zero, size: sceneSize)
            func point(_ p: CGPoint) -> CGPoint {
                return CGPoint(x: p.x, y: sceneSize.height - p.y)
            }
            RingMock.drawDesktop(in: scene, dark: dark)
            if let centre = frame.ringCentre {
                let face = ShortcutRingFace(.default)
                RingMock.drawRing(
                    face,
                    drops: ShortcutRingDrops.frame(at: frame.openElapsed, filled: face.filled, lit: frame.litAmounts),
                    title: frame.lit.map { face.places[$0].title }, centre: point(centre), look: .drawn
                )
            }
            if let click = frame.click {
                RingMock.drawClick(at: point(frame.pointer), progress: click)
            }
            if let press = frame.press {
                RingMock.drawPress(at: point(frame.pointer), progress: press)
            }
            RingMock.drawPointer(at: point(frame.pointer))
            // The dot before the caption: the trigger is down, or was pressed a moment ago.
            drawCaption(frame.caption, held: frame.isTriggerHeld || frame.press != nil, in: scene, dark: dark)
        }

        /// The line at the bottom, with a dot while the trigger is held.
        private static func drawCaption(_ text: String, held: Bool, in scene: CGRect, dark: Bool) {
            let font = NSFont.systemFont(ofSize: 14, weight: .medium)
            let string = NSAttributedString(string: text, attributes: [
                .font: font,
                .foregroundColor: NSColor.white,
            ])
            let size = string.size()
            let dot: CGFloat = held ? 18 : 0
            let pill = CGRect(
                x: scene.midX - (size.width + dot) / 2 - 14, y: 16,
                width: size.width + dot + 28, height: size.height + 12
            )
            NSColor(white: 0, alpha: 0.62).setFill()
            NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
            if held {
                NSColor.controlAccentColor.setFill()
                NSBezierPath(ovalIn: CGRect(x: pill.minX + 12, y: pill.midY - 4.5, width: 9, height: 9)).fill()
                NSColor.white.setStroke()
                let ring = NSBezierPath(ovalIn: CGRect(x: pill.minX + 12, y: pill.midY - 4.5, width: 9, height: 9))
                ring.lineWidth = 1
                ring.stroke()
            }
            string.draw(at: CGPoint(x: pill.minX + 14 + dot, y: pill.minY + 6))
        }
    }
}
