// Draws the picture behind the icons in the window of Scrollio's disk image.
//
//   swift scripts/dmg/draw-background.swift            writes scripts/dmg/background.tiff
//   swift scripts/dmg/draw-background.swift <file>     writes it somewhere else
//
// The window's content is 660 x 420 pt. The picture is drawn twice, at 1x (660 x 420 px)
// and at 2x (1320 x 840 px), and `tiffutil -cathidpicheck` puts both into one TIFF: Finder
// takes the one that fits the display, so the picture is sharp on a Retina display and
// not scaled on any other.
//
// The arrow and the line of text are part of the picture; Finder draws the two icons and
// their names over it, where scripts/dmg/write-layout.swift puts them: the app at x 180,
// the Applications folder at x 480, both 184 pt below the top, 128 pt large. Change a
// number there and here together.
//
// The text is set in the system's monospaced font, so a later macOS can draw it a little
// differently: look at the new file before you commit it.
import AppKit

let width: CGFloat = 660, height: CGFloat = 420

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func linear(_ c: CGContext, _ colours: [NSColor], from: CGPoint, to: CGPoint) {
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                              colors: colours.map { $0.cgColor } as CFArray, locations: nil)!
    c.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

/// A soft light: the colour at the centre, fading to nothing at the radius.
func glow(_ c: CGContext, at centre: CGPoint, radius: CGFloat, _ colour: NSColor) {
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                              colors: [colour.cgColor, colour.withAlphaComponent(colour.alphaComponent * 0.45).cgColor,
                                       colour.withAlphaComponent(0).cgColor] as CFArray,
                              locations: [0, 0.45, 1])!
    c.drawRadialGradient(gradient, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: radius, options: [])
}

func text(_ string: String, font: NSFont, colour: NSColor, centreX: CGFloat, baseline: CGFloat, kern: CGFloat = 0) {
    let attributed = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: colour, .kern: kern])
    let size = attributed.size()
    attributed.draw(at: CGPoint(x: centreX - size.width / 2, y: baseline + font.descender))
}

/// A thin arrow from left to right with an open head.
func arrow(_ c: CGContext, from: CGPoint, to: CGPoint, colour: NSColor, width: CGFloat, head: CGFloat) {
    c.saveGState()
    c.setStrokeColor(colour.cgColor)
    c.setLineWidth(width)
    c.setLineCap(.round)
    c.setLineJoin(.round)
    c.move(to: from)
    c.addLine(to: to)
    c.move(to: CGPoint(x: to.x - head, y: to.y + head * 0.8))
    c.addLine(to: to)
    c.addLine(to: CGPoint(x: to.x - head, y: to.y - head * 0.8))
    c.strokePath()
    c.restoreGState()
}

/// Light mist. The origin is the bottom left corner: the icons' centres are at y 236,
/// which is 184 pt below the top.
func mist(_ c: CGContext) {
    linear(c, [rgb(0xF1F2FB), rgb(0xE2E2EE)], from: CGPoint(x: 0, y: height), to: CGPoint(x: 0, y: 0))
    glow(c, at: CGPoint(x: 90, y: 360), radius: 300, rgb(0xC3B5F7, 0.55))
    glow(c, at: CGPoint(x: 560, y: 400), radius: 280, rgb(0xC6DBFC, 0.65))
    glow(c, at: CGPoint(x: 330, y: 20), radius: 330, rgb(0xCDC6EE, 0.55))
    glow(c, at: CGPoint(x: 330, y: 236), radius: 230, rgb(0xFFFFFF, 0.60))
    arrow(c, from: CGPoint(x: 272, y: 236), to: CGPoint(x: 392, y: 236), colour: rgb(0x6A6A7C, 0.85), width: 1.25, head: 10)
    text("Drag Scrollio to Applications.", font: .monospacedSystemFont(ofSize: 10.5, weight: .regular),
         colour: rgb(0x80808F), centreX: width / 2, baseline: 30, kern: 1.6)
}

/// The picture at one scale, as PNG data.
func png(scale: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)     // points: this is what makes the larger one "2x"
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    mist(context.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let script = URL(fileURLWithPath: #filePath)
let out = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : script.deletingLastPathComponent().appendingPathComponent("background.tiff")

let work = FileManager.default.temporaryDirectory.appendingPathComponent("scrollio-dmg-background-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: work) }
let small = work.appendingPathComponent("background.png")
let large = work.appendingPathComponent("background@2x.png")
try png(scale: 1).write(to: small)
try png(scale: 2).write(to: large)

let tiffutil = Process()
tiffutil.executableURL = URL(fileURLWithPath: "/usr/bin/tiffutil")
tiffutil.arguments = ["-cathidpicheck", small.path, large.path, "-out", out.path]
try tiffutil.run()
tiffutil.waitUntilExit()
guard tiffutil.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("draw-background: tiffutil could not write \(out.path)\n".utf8))
    exit(1)
}
print("wrote \(out.path)")
