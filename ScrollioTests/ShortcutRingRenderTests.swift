//
//  ShortcutRingRenderTests.swift
//  ScrollioTests
//
//  Pictures of the Shortcut Ring, drawn off screen for a look at them: a contact sheet of
//  its states (light and dark) and the frames of a short demo. Nothing is captured from a
//  screen: the ring is drawn by the app's own code (`ShortcutRingArtwork`) over a painted
//  desktop, and the demo's ring is driven by the app's own rules (`ShortcutRingSession`)
//  along a scripted pointer path.
//
//  What the pictures cannot show: the system material under the ring (only the window
//  server draws it; the plain disc of "Reduce transparency" stands in), and anything of a
//  real screen, a real app in front or a real mouse.
//
//  Only runs when asked to:
//  `TEST_RUNNER_SCROLLIO_SHOTS_DIR=<folder> xcodebuild … test -only-testing:ScrollioTests/ShortcutRingRenderTests`.
//  The sheets are written to the folder itself (`ring-sheet-light.png`, `ring-sheet-dark.png`),
//  the demo's frames to `frames/` inside it.
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

    // MARK: - The contact sheet

    private struct Cell {
        var caption: String
        var ring = ShortcutRingSettings.default
        /// The ring's middle and the pointer's tip, from the cell's top left corner.
        var centre = CGPoint(x: 190, y: 165)
        var pointer = CGPoint(x: 190, y: 165)
        var lit: Int?
        var isCorner = false
        var increasesContrast = false
        var showsClick = false
    }

    private static let cellSize = CGSize(width: 380, height: 330)

    private static var cells: [Cell] {
        let middle = CGPoint(x: 190, y: 165)
        func towards(_ place: Int, _ distance: CGFloat) -> CGPoint {
            let offset = ShortcutRingGeometry.offset(ofPlace: place, radius: distance)
            return CGPoint(x: middle.x + offset.x, y: middle.y + offset.y)
        }
        var withGaps = ShortcutRingSettings.default
        withGaps[1] = .empty
        withGaps[3] = .empty
        let corner = ShortcutRingGeometry.centre(
            forPointer: CGPoint(x: 5, y: 6), in: CGRect(origin: .zero, size: cellSize)
        )
        return [
            Cell(caption: "Just opened, at the pointer"),
            Cell(caption: "Hold and move towards a shortcut: it lights, let go runs it", pointer: towards(5, 52), lit: 5),
            Cell(caption: "An empty place is a faint dot and does nothing", ring: withGaps, pointer: towards(1, 60), lit: nil),
            Cell(caption: "Left open after a press: point at a shortcut and click",
                 pointer: CGPoint(x: middle.x + 92, y: middle.y + 12), lit: 2),
            Cell(caption: "In a corner the whole ring stays on screen; the hand's direction chooses",
                 centre: corner, pointer: CGPoint(x: 5, y: 6), lit: 7, isCorner: true),
            Cell(caption: "With Increase contrast", pointer: towards(0, 52), lit: 0, increasesContrast: true),
        ]
    }

    func testRenderTheRingsContactSheets() throws {
        let margin: CGFloat = 24, gap: CGFloat = 20, captionHeight: CGFloat = 40
        let cell = Self.cellSize
        let columns = 3, rows = 2
        let size = CGSize(
            width: margin * 2 + CGFloat(columns) * cell.width + CGFloat(columns - 1) * gap,
            height: margin * 2 + CGFloat(rows) * (cell.height + captionHeight) + CGFloat(rows - 1) * gap
        )
        for (suffix, name) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let dark = name == .darkAqua
            try render(size: size, scale: 2, appearance: name, to: directory.appendingPathComponent("ring-sheet-\(suffix).png")) {
                (dark ? NSColor(white: 0.11, alpha: 1) : NSColor(white: 0.95, alpha: 1)).setFill()
                CGRect(origin: .zero, size: size).fill()
                for (index, item) in Self.cells.enumerated() {
                    let column = index % columns, row = index / columns
                    // The sheet is drawn with y upwards: the first row is the top one.
                    let origin = CGPoint(
                        x: margin + CGFloat(column) * (cell.width + gap),
                        y: size.height - margin - CGFloat(row + 1) * cell.height - CGFloat(row) * (captionHeight + gap)
                    )
                    RingMock.drawCell(item, in: CGRect(origin: origin, size: cell), dark: dark)
                    RingMock.drawCaption(
                        item.caption,
                        in: CGRect(x: origin.x, y: origin.y - captionHeight, width: cell.width, height: captionHeight - 6),
                        dark: dark
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
        let picks = [30, 40, 95, 140, 225, 300, 385, 420].map { min($0, frames.count - 1) }
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

        /// The ring as the app draws it, on the plain disc that stands in for the material.
        static func drawRing(
            _ face: ShortcutRingFace, lit: Int?, centre: CGPoint,
            opacity: CGFloat = 1, scale: CGFloat = 1, increasesContrast: Bool = false
        ) {
            var style = ShortcutRingArtwork.Style()
            style.backdrop = .drawn
            style.opacity = opacity
            style.scale = scale
            style.increasesContrast = increasesContrast
            if opacity > 0.5 {
                ShortcutRingArtwork.drawShadow(centre: centre, scale: scale)
            }
            ShortcutRingArtwork.draw(face, lit: lit, centre: centre, style: style)
        }

        /// A click: a ring around the pointer's tip.
        static func drawClick(at tip: CGPoint, progress: CGFloat = 0.5) {
            let radius = 6 + 12 * progress
            let path = NSBezierPath(ovalIn: CGRect(x: tip.x - radius, y: tip.y - radius, width: radius * 2, height: radius * 2))
            path.lineWidth = 2
            NSColor.white.withAlphaComponent(0.9 * (1 - progress)).setStroke()
            path.stroke()
        }

        static func drawCell(_ cell: Cell, in rect: CGRect, dark: Bool) {
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
            drawRing(ShortcutRingFace(cell.ring), lit: cell.lit, centre: point(cell.centre), increasesContrast: cell.increasesContrast)
            if cell.showsClick {
                drawClick(at: point(cell.pointer))
            }
            drawPointer(at: point(cell.pointer))
            context.restoreGState()
        }

        static func drawCaption(_ text: String, in rect: CGRect, dark: Bool) {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byWordWrapping
            let string = NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
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
            /// 0 … 1: how far the ring's fade and growth have come.
            var openProgress: CGFloat = 1
            var caption = ""
            var isTriggerHeld = false
            /// 0 … 1 while a click's ripple shows.
            var click: CGFloat?
        }

        private static func ease(_ t: CGFloat) -> CGFloat {
            let x = min(max(t, 0), 1)
            return x * x * (3 - 2 * x)
        }

        /// Where the pointer is at `time`: straight moves between the stops, eased.
        private static func pointer(at time: Double) -> CGPoint {
            let stops: [(time: Double, point: CGPoint)] = [
                (0.0, CGPoint(x: 250, y: 190)), (0.75, CGPoint(x: 250, y: 190)),
                (1.45, CGPoint(x: 202, y: 238)),            // towards "Copy", bottom left
                (2.4, CGPoint(x: 202, y: 238)),
                (3.3, CGPoint(x: 400, y: 200)), (4.1, CGPoint(x: 400, y: 200)),
                (4.9, CGPoint(x: 458, y: 142)),             // over the top right place
                (5.4, CGPoint(x: 458, y: 142)),
                (6.1, CGPoint(x: 482, y: 200)),             // over the right place
                (8.0, CGPoint(x: 482, y: 200)),
            ]
            guard let next = stops.firstIndex(where: { $0.time >= time }), next > 0 else {
                return time <= 0 ? stops[0].point : stops[stops.count - 1].point
            }
            let a = stops[next - 1], b = stops[next]
            let t = ease(CGFloat((time - a.time) / (b.time - a.time)))
            return CGPoint(x: a.point.x + (b.point.x - a.point.x) * t, y: a.point.y + (b.point.y - a.point.y) * t)
        }

        static func frames() -> [Frame] {
            let pressAt = 0.6, releaseAt = 2.2
            let tapDownAt = 3.6, tapUpAt = 3.7
            let clickDownAt = 6.6, clickUpAt = 6.72
            let screen = CGRect(origin: .zero, size: sceneSize)
            let filled = ShortcutRingSettings.default.filled
            var session = ShortcutRingSession()
            var frames: [Frame] = []
            var previous = pointer(at: 0)
            var openedAt: Double?
            var caption = "Hold the button …"
            var ran: (title: String, at: Double)?
            let face = ShortcutRingFace(.default)

            func handle(_ commands: [ShortcutRingSession.Command], at time: Double) {
                for command in commands {
                    switch command {
                    case .open: openedAt = time
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
                if happens(4.2) { caption = "Point at a shortcut …" }
                if happens(clickDownAt) {
                    handle(session.buttonPressed(0, at: now), at: time)
                    caption = "… and click it"
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
                    frame.openProgress = CGFloat(min(1, (time - openedAt) / ShortcutRingPanelPresenter.openDuration))
                }
                if time >= clickDownAt, time < clickDownAt + 0.35 {
                    frame.click = CGFloat((time - clickDownAt) / 0.35)
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
                let progress = ease(frame.openProgress)
                let scale = ShortcutRingPanelPresenter.openScale + (1 - ShortcutRingPanelPresenter.openScale) * progress
                RingMock.drawRing(ShortcutRingFace(.default), lit: frame.lit, centre: point(centre), opacity: progress, scale: scale)
            }
            if let click = frame.click {
                RingMock.drawClick(at: point(frame.pointer), progress: click)
            }
            RingMock.drawPointer(at: point(frame.pointer))
            drawCaption(frame.caption, held: frame.isTriggerHeld, in: scene, dark: dark)
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
