//
//  ButtonsMouseMiniature.swift
//  Mos
//  The small picture in front of each row of the Buttons pane: the card's mouse (the
//  connected model's drawing, MouseArtwork.swift) about 20 pt tall with the row's button
//  filled in the accent colour, a keyboard for a key, and for a button the drawing cannot
//  show the mouse with nothing lit and the button's number on a badge. The outline, the
//  seams and the two buttons are the card's; the side buttons, the thumb wheel, the wheel
//  and the button behind it are the schematic variant's, larger and further apart than on
//  the card, so the front, middle and rear side buttons can be told apart at this size.
//

import Cocoa

enum ButtonsMouseMiniature {

    /// The list's picture size (PreferencesListRow, an image icon).
    static let size = NSSize(width: PreferencesListRow.imageIconSize, height: PreferencesListRow.imageIconSize)
    /// The mouse's height in the picture.
    static let mouseHeight: CGFloat = 22
    /// The badge with a button's number, at the picture's lower right.
    static let badgeHeight: CGFloat = 11
    static var badgeFont: NSFont {
        return NSFont.systemFont(ofSize: 8.5, weight: .bold)
    }

    /// The picture of `picture` on `mouse`'s drawing; `highlighted`: on the accent-coloured
    /// selection, drawn in white. It is drawn each time it shows, in the appearance and
    /// accent colour of then.
    static func image(for picture: ButtonTriggerPicture, mouse: MouseArtworkModel, highlighted: Bool) -> NSImage {
        let image = NSImage(size: size, flipped: true) { rect in
            draw(picture, mouse: mouse, in: rect, highlighted: highlighted)
            return true
        }
        image.cacheMode = .never
        return image
    }

    static func draw(_ picture: ButtonTriggerPicture, mouse: MouseArtworkModel, in rect: NSRect, highlighted: Bool) {
        switch picture {
        case .key:
            drawKeyboard(in: rect, highlighted: highlighted)
        case .mouse(let part, let number):
            drawMouse(mouse, in: rect, lit: part, highlighted: highlighted)
            if let number {
                let fill = highlighted ? NSColor.white : MiniaturePalette.badge
                let text = highlighted ? NSColor.controlAccentColor : MiniaturePalette.badgeText
                let badgeSize = badgeSize(for: number, font: badgeFont, height: badgeHeight)
                let badge = NSRect(
                    x: rect.maxX - badgeSize.width, y: rect.maxY - badgeSize.height,
                    width: badgeSize.width, height: badgeSize.height
                )
                drawBadge(number, in: badge, font: badgeFont, fill: fill, text: text)
            }
        }
    }

    // MARK: - Geometry

    /// The shape of `part` in a picture of `mouse` drawn in `rect` (flipped); nil when the
    /// mouse does not have it.
    static func shape(of part: ButtonsMousePart, mouse: MouseArtworkModel, in rect: NSRect) -> NSBezierPath? {
        guard let path = MouseArtworkShapes(model: mouse, schematic: true).shape(of: part.artworkPart) else { return nil }
        path.transform(using: transform(in: rect))
        return path
    }

    /// The mouse's outline in a picture drawn in `rect` (flipped).
    static func bodyPath(of mouse: MouseArtworkModel, in rect: NSRect) -> NSBezierPath {
        let path = MouseArtworkShapes(model: mouse, schematic: true).outline()
        path.transform(using: transform(in: rect))
        return path
    }

    /// Points per unit of the drawing's grid.
    private static var unit: CGFloat {
        return mouseHeight / MouseArtworkShapes.grid.height
    }

    /// From the drawing's grid to the picture: the grid `mouseHeight` tall, in the middle
    /// of `rect`.
    private static func transform(in rect: NSRect) -> AffineTransform {
        let grid = MouseArtworkShapes.grid
        var transform = AffineTransform(
            translationByX: rect.minX + (rect.width - grid.width * unit) / 2,
            byY: rect.minY + (rect.height - mouseHeight) / 2
        )
        transform.scale(unit)
        return transform
    }

    // MARK: - Drawing

    private static func drawMouse(_ mouse: MouseArtworkModel, in rect: NSRect, lit: ButtonsMousePart?, highlighted: Bool) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        (transform(in: rect) as NSAffineTransform).concat()
        MouseArtworkPainter.draw(
            MouseArtworkShapes(model: mouse, schematic: true),
            ink: ink(highlighted: highlighted), lit: lit?.artworkPart, unit: unit
        )
    }

    /// The card's colours with finer lines; on the selection everything in white, the parts
    /// that are not lit faint, so the lit one stands out.
    private static func ink(highlighted: Bool) -> MouseArtworkInk {
        let white = NSColor.white
        var ink = MouseArtworkInk.card
        ink.bodyFill = highlighted ? white.withAlphaComponent(0.14) : ScrollPreviewPalette.mouseFill
        ink.outline = highlighted ? white : ScrollPreviewPalette.mouseLine
        ink.seam = highlighted ? white.withAlphaComponent(0.5) : ScrollPreviewPalette.mouseSeam
        ink.partEdge = highlighted ? white.withAlphaComponent(0.4) : MiniaturePalette.partEdge
        ink.lit = highlighted ? white : .controlAccentColor
        ink.outlineWidth = 1
        ink.seamWidth = 0.6
        ink.partEdgeWidth = 0.6
        ink.ridges = false
        ink.shadow = false
        ink.drawsWell = false
        ink.fillsParts = !highlighted
        return ink
    }

    private static func drawKeyboard(in rect: NSRect, highlighted: Bool) {
        let color = highlighted ? NSColor.white : ScrollPreviewPalette.mouseLine
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let symbol = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return }
        let size = symbol.size
        symbol.draw(
            in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height),
            from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil
        )
    }

    // MARK: - The badge (also the card's)

    /// A capsule `height` tall that holds `number` in `font`, at least as wide as tall.
    static func badgeSize(for number: Int, font: NSFont, height: CGFloat) -> NSSize {
        let text = NSAttributedString(string: String(number), attributes: [.font: font])
        let padding = height * 0.45
        return NSSize(width: max(height, ceil(text.size().width) + padding), height: height)
    }

    static func drawBadge(_ number: Int, in rect: NSRect, font: NSFont, fill: NSColor, text color: NSColor) {
        fill.setFill()
        let radius = min(rect.width, rect.height) / 2
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        let text = NSAttributedString(string: String(number), attributes: [.font: font, .foregroundColor: color])
        let size = text.size()
        text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
    }
}

private enum MiniaturePalette {
    /// The edge of a part inside the body: finer than the outline, clearer than the seam.
    static let partEdge = ScrollPreviewPalette.adaptive(
        light: NSColor(white: 0, alpha: 0.36),
        dark: NSColor(white: 1, alpha: 0.42)
    )
    /// The badge of a button the drawing cannot show: grey, as nothing is lit.
    static let badge = ScrollPreviewPalette.adaptive(
        light: NSColor(white: 0.40, alpha: 1),
        dark: NSColor(white: 0.78, alpha: 1)
    )
    static let badgeText = ScrollPreviewPalette.adaptive(light: .white, dark: NSColor(white: 0.12, alpha: 1))
}
