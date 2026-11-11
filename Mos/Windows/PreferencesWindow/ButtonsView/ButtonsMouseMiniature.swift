//
//  ButtonsMouseMiniature.swift
//  Mos
//  The small picture in front of each row of the Buttons pane: the card's mouse
//  (ButtonsMouseArtworkView) about 20 pt tall with the row's button filled in the accent
//  colour, a keyboard for a key, and for a button the drawing cannot show the mouse with
//  nothing lit and the button's number on a badge. The body, the seam and the two buttons
//  are the card's geometry; the wheel, the button behind it, the side buttons and the thumb
//  panel sit where the card has them but larger, so they can be told apart at this size.
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

    /// The picture of `picture`; `highlighted`: on the accent-coloured selection, drawn in
    /// white. It is drawn each time it shows, in the appearance and accent colour of then.
    static func image(for picture: ButtonTriggerPicture, highlighted: Bool) -> NSImage {
        let image = NSImage(size: size, flipped: true) { rect in
            draw(picture, in: rect, highlighted: highlighted)
            return true
        }
        image.cacheMode = .never
        return image
    }

    static func draw(_ picture: ButtonTriggerPicture, in rect: NSRect, highlighted: Bool) {
        switch picture {
        case .key:
            drawKeyboard(in: rect, highlighted: highlighted)
        case .mouse(let part, let number):
            drawMouse(in: rect, lit: part, highlighted: highlighted)
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

    /// The shape of `part` in a picture drawn in `rect` (flipped).
    static func shape(of part: ButtonsMousePart, in rect: NSRect) -> NSBezierPath {
        let path = artworkShape(of: part)
        path.transform(using: transform(in: rect))
        return path
    }

    /// The mouse's outline in a picture drawn in `rect` (flipped).
    static func bodyPath(in rect: NSRect) -> NSBezierPath {
        let path = MouseArtworkView.bodyPath()
        path.transform(using: transform(in: rect))
        return path
    }

    /// From the card's mouse (ButtonsMouseArtworkView's coordinates) to the picture: the
    /// body `mouseHeight` tall, in the middle of `rect`.
    private static func transform(in rect: NSRect) -> AffineTransform {
        let scale = mouseHeight / MouseArtworkView.bodySize.height
        let width = MouseArtworkView.bodySize.width * scale
        let originX = rect.minX + (rect.width - width) / 2
        let originY = rect.minY + (rect.height - mouseHeight) / 2
        let margin = MouseArtworkView.margin
        return AffineTransform(m11: scale, m12: 0, m21: 0, m22: scale, tX: originX - margin * scale, tY: originY - margin * scale)
    }

    /// One point of the picture in the card's coordinates.
    private static var hairline: CGFloat {
        return MouseArtworkView.bodySize.height / mouseHeight
    }

    /// `part` in the card's coordinates, larger than the card draws it where it is small.
    private static func artworkShape(of part: ButtonsMousePart) -> NSBezierPath {
        let p = MouseArtworkView.point
        let unit = MouseArtworkView.bodySize.width / MouseArtworkView.designSize.width
        switch part {
        case .left:
            return ButtonsMouseArtworkView.buttonAreaPath(left: true)
        case .right:
            return ButtonsMouseArtworkView.buttonAreaPath(left: false)
        case .middle:
            return MouseArtworkHighlight.capsule(grown(MouseArtworkView.wheelRect, width: 1.5, height: 1))
        case .modeShift:
            let rect = grown(MouseArtworkView.backButtonRect, width: 2.0, height: 1.6)
            return NSBezierPath(roundedRect: rect, xRadius: hairline, yRadius: hairline)
        // Along the left edge above the thumb panel, Forward in front; they lie on the
        // outline so they read as buttons on the side.
        case .forward:
            return capsule(from: p(17.5, 44.5), to: p(15.5, 51.5), width: 9.5 * unit)
        case .back:
            return capsule(from: p(12, 59.5), to: p(7.5, 66), width: 9.5 * unit)
        case .gesture:
            return capsule(from: p(11.5, 80), to: p(14.5, 103), width: 11 * unit)
        }
    }

    private static func grown(_ rect: NSRect, width: CGFloat, height: CGFloat) -> NSRect {
        return rect.insetBy(dx: -rect.width * (width - 1) / 2, dy: -rect.height * (height - 1) / 2)
    }

    /// A capsule `width` wide whose round ends are centred on `start` and `end`.
    private static func capsule(from start: NSPoint, to end: NSPoint, width: CGFloat) -> NSBezierPath {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = (dx * dx + dy * dy).squareRoot() + width
        let path = NSBezierPath(
            roundedRect: NSRect(x: -length / 2, y: -width / 2, width: length, height: width),
            xRadius: width / 2, yRadius: width / 2
        )
        let angle = atan2(dy, dx)
        path.transform(using: AffineTransform(
            m11: cos(angle), m12: sin(angle), m21: -sin(angle), m22: cos(angle),
            tX: (start.x + end.x) / 2, tY: (start.y + end.y) / 2
        ))
        return path
    }

    // MARK: - Drawing

    private static func drawMouse(in rect: NSRect, lit: ButtonsMousePart?, highlighted: Bool) {
        let accent = NSColor.controlAccentColor
        let white = NSColor.white
        let litColor = highlighted ? white : accent
        let bodyFill = highlighted ? white.withAlphaComponent(0.14) : ScrollPreviewPalette.mouseFill
        let outline = highlighted ? white : ScrollPreviewPalette.mouseLine
        let seamColor = highlighted ? white.withAlphaComponent(0.5) : ScrollPreviewPalette.mouseSeam
        // On the selection the parts that are not lit stay faint, so the lit one stands out.
        let partEdge = highlighted ? white.withAlphaComponent(0.4) : MiniaturePalette.partEdge
        let px = hairline

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let move = transform(in: rect)
        (move as NSAffineTransform).concat()

        let body = MouseArtworkView.bodyPath()
        bodyFill.setFill()
        body.fill()
        if lit == .left || lit == .right {
            litColor.setFill()
            artworkShape(of: lit == .left ? .left : .right).fill()
        }
        NSGraphicsContext.saveGraphicsState()
        body.addClip()
        let seams = MouseArtworkView.seamPath()
        seams.lineWidth = 0.6 * px
        seamColor.setStroke()
        seams.stroke()
        NSGraphicsContext.restoreGraphicsState()

        /// A part inside the body: lit, or in its own colour with a fine edge.
        func drawInner(_ part: ButtonsMousePart, fill: NSColor) {
            let shape = artworkShape(of: part)
            if part == lit {
                litColor.setFill()
                shape.fill()
                return
            }
            if !highlighted {
                ScrollPreviewPalette.mouseFill.setFill()
                shape.fill()
                fill.setFill()
                shape.fill()
            }
            shape.lineWidth = 0.6 * px
            partEdge.setStroke()
            shape.stroke()
        }
        drawInner(.middle, fill: MouseArtworkPalette.wheel)
        drawInner(.modeShift, fill: ScrollPreviewPalette.wheelWell)
        drawInner(.gesture, fill: MouseArtworkPalette.panel)

        body.lineWidth = px
        outline.setStroke()
        body.stroke()

        // The side buttons over the outline.
        for part in [ButtonsMousePart.forward, .back] {
            let shape = artworkShape(of: part)
            if part == lit {
                litColor.setFill()
                shape.fill()
            } else if !highlighted {
                ScrollPreviewPalette.mouseFill.setFill()
                shape.fill()
                ScrollPreviewPalette.wheelWell.setFill()
                shape.fill()
            }
            shape.lineWidth = 0.8 * px
            (part == lit ? litColor : (highlighted ? partEdge : outline)).setStroke()
            shape.stroke()
        }
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
        MouseArtworkHighlight.capsule(rect).fill()
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
