//
//  ShortcutRingArtwork.swift
//  Scrollio
//
//  How the Shortcut Ring looks: what its places show (`ShortcutRingFace`, made from the
//  stored ring as the Buttons pane shows an action) and the drawing itself, one
//  function for the ring on screen, the ring in the Settings pane and the pictures the
//  render tests make. The sizes are `ShortcutRingGeometry`'s.
//
//  On screen the ring lies on a system material (`ShortcutRingPanel`), which only the
//  window server can draw; `Backdrop.drawn` paints a plain disc in its place, for the pane,
//  for "Reduce transparency" and for pictures made without a screen.
//

import Cocoa

/// What the ring shows, place by place.
struct ShortcutRingFace {

    struct Place {
        /// The action's name, for the middle of the ring; empty for an empty place.
        var title: String
        /// The action's SF Symbol.
        var symbolName: String
        /// A picture instead of the symbol: the icon of an app or a file.
        var image: NSImage?
        /// Text instead of the symbol: a recorded key combination as its keys ("⇧⌘K"),
        /// on one line or two (the modifiers above a key with a long name).
        var glyphs: [String] = []
        /// Nothing is here, or nothing this version runs: a faint dot.
        var isEmpty: Bool

        static let empty = Place(title: "", symbolName: "", isEmpty: true)
    }

    var places: [Place]

    /// Which places hold an action that runs, as `ShortcutRingSession` wants it.
    var filled: [Bool] {
        return places.map { !$0.isEmpty }
    }

    init(places: [Place]) {
        var places = Array(places.prefix(ShortcutRingSettings.placeCount))
        while places.count < ShortcutRingSettings.placeCount {
            places.append(.empty)
        }
        self.places = places
    }

    /// The face of a stored ring: each place as the Buttons pane shows that action (a
    /// listed action's name and symbol, an app's name and icon, a key combination's keys).
    /// It looks an app's icon up on disk and asks the keyboard layout for a key's name:
    /// not for an event callback (the ring's controller makes it when the ring is shown,
    /// on the main queue, and keeps it until the ring changes).
    init(_ ring: ShortcutRingSettings, resolver: ActionDisplayResolver = ActionDisplayResolver()) {
        self.init(places: ring.places.map { place in
            switch place.content {
            case .nothing:
                return .empty
            case .shortcut(let shortcut):
                return Place(title: shortcut.localizedName, symbolName: shortcut.symbolName, isEmpty: false)
            case .keyCombination(let code, let modifiers):
                let text = ButtonTriggerNaming.shortcutText(type: .keyboard, code: code, modifiers: modifiers)
                return Place(
                    title: text, symbolName: "keyboard",
                    glyphs: Self.glyphLines(code: code, modifiers: modifiers), isEmpty: false
                )
            case .open:
                let shown = resolver.resolve(state: CellActionState(binding: place.asBinding()))
                return Place(
                    title: shown.title, symbolName: shown.symbolName ?? "arrow.up.forward.app",
                    image: shown.image, isEmpty: false
                )
            }
        })
    }

    /// A key combination as it stands in a place: "⇧⌘K" on one line; the modifiers above
    /// the key when the key's name is a word ("⌃⌥" over "Space").
    static func glyphLines(code: UInt16, modifiers: UInt64) -> [String] {
        let whole = ButtonTriggerNaming.shortcutText(type: .keyboard, code: code, modifiers: modifiers)
        let key = ButtonTriggerNaming.keyName(code, modifiers: modifiers)
        guard key.count > 1, whole.hasSuffix(key), whole.count > key.count else { return [whole] }
        let symbols = String(whole.dropLast(key.count)).trimmingCharacters(in: .whitespaces)
        return symbols.isEmpty ? [whole] : [symbols, key]
    }
}

enum ShortcutRingArtwork {

    /// What lies under the places.
    enum Backdrop {
        /// Nothing is painted: the window's material shows.
        case material
        /// A plain disc in the colours of the material.
        case drawn
    }

    struct Style {
        var backdrop = Backdrop.material
        /// "Increase contrast": firmer outlines, no faint fills.
        var increasesContrast = false
        /// Drawn `scale` times as large (the pane shows the ring smaller than the screen).
        var scale: CGFloat = 1
        /// Everything fainter: the ring as a whole fades in.
        var opacity: CGFloat = 1
    }

    // MARK: Sizes

    static let symbolPointSize: CGFloat = 20
    /// An app's or a file's icon in a place.
    static let iconSide: CGFloat = 34
    /// A key combination's text in a place: at most this large, smaller when it is long,
    /// and never wider than this part of the place.
    static let glyphPointSize: CGFloat = 15
    static let glyphWidth: CGFloat = 40
    static let emptyDotDiameter: CGFloat = 7
    static let titleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    /// A lit place grows by this much.
    static let litScale: CGFloat = 1.08

    // MARK: Colours

    /// The lit place: the accent colour (the app's purple, or the user's own choice).
    static var litFill: NSColor { return NSColor.controlAccentColor }
    static let litInk = NSColor.white

    private static func isDark() -> Bool {
        return NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// The disc that stands in for the material.
    static func backdropFill(dark: Bool, contrast: Bool) -> NSColor {
        if contrast {
            return dark ? NSColor(white: 0.10, alpha: 1) : NSColor(white: 0.97, alpha: 1)
        }
        return dark ? NSColor(white: 0.16, alpha: 0.92) : NSColor(white: 0.96, alpha: 0.92)
    }

    static func rim(dark: Bool, contrast: Bool) -> NSColor {
        if contrast {
            return dark ? NSColor(white: 1, alpha: 0.75) : NSColor(white: 0, alpha: 0.65)
        }
        return dark ? NSColor(white: 1, alpha: 0.16) : NSColor(white: 0, alpha: 0.12)
    }

    static func placeFill(dark: Bool, contrast: Bool) -> NSColor {
        if contrast {
            return dark ? NSColor(white: 1, alpha: 0.22) : NSColor(white: 0, alpha: 0.14)
        }
        return dark ? NSColor(white: 1, alpha: 0.11) : NSColor(white: 0, alpha: 0.065)
    }

    static func ink(dark: Bool) -> NSColor {
        return dark ? NSColor(white: 1, alpha: 0.92) : NSColor(white: 0, alpha: 0.82)
    }

    static func emptyDot(dark: Bool, contrast: Bool) -> NSColor {
        let alpha: CGFloat = contrast ? 0.5 : 0.2
        return dark ? NSColor(white: 1, alpha: alpha) : NSColor(white: 0, alpha: alpha)
    }

    // MARK: Drawing

    /// Draws the ring with its middle at `centre` into the current context (y upwards),
    /// in the current drawing appearance.
    static func draw(_ face: ShortcutRingFace, lit: Int?, centre: CGPoint, style: Style = Style()) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let dark = isDark()
        let contrast = style.increasesContrast
        let scale = style.scale

        context.saveGState()
        context.setAlpha(style.opacity)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        defer {
            context.endTransparencyLayer()
            context.restoreGState()
        }

        let outer = ShortcutRingGeometry.outerRadius * scale
        let disc = CGRect(x: centre.x - outer, y: centre.y - outer, width: outer * 2, height: outer * 2)
        if style.backdrop == .drawn {
            backdropFill(dark: dark, contrast: contrast).setFill()
            NSBezierPath(ovalIn: disc).fill()
        }
        let rimWidth: CGFloat = contrast ? 1.5 : 1
        let rimPath = NSBezierPath(ovalIn: disc.insetBy(dx: rimWidth / 2, dy: rimWidth / 2))
        rimPath.lineWidth = rimWidth
        rim(dark: dark, contrast: contrast).setStroke()
        rimPath.stroke()

        for (index, place) in face.places.enumerated() {
            let offset = ShortcutRingGeometry.offset(ofPlace: index)
            // The geometry's y grows downwards, the drawing's upwards.
            let middle = CGPoint(x: centre.x + offset.x * scale, y: centre.y - offset.y * scale)
            draw(place, at: middle, isLit: lit == index, dark: dark, contrast: contrast, scale: scale)
        }

        if let lit, face.places.indices.contains(lit), !face.places[lit].isEmpty {
            drawTitle(face.places[lit].title, centre: centre, dark: dark, scale: scale)
        }
    }

    /// The ring's shadow, drawn around the disc and nowhere inside it (what lies under
    /// the disc must show through the material).
    static func drawShadow(centre: CGPoint, scale: CGFloat = 1) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let outer = ShortcutRingGeometry.outerRadius * scale
        let disc = CGRect(x: centre.x - outer, y: centre.y - outer, width: outer * 2, height: outer * 2)
        context.saveGState()
        let outside = CGMutablePath()
        outside.addRect(disc.insetBy(dx: -60 * scale, dy: -60 * scale))
        outside.addEllipse(in: disc)
        context.addPath(outside)
        context.clip(using: .evenOdd)
        context.setShadow(
            offset: CGSize(width: 0, height: -5 * scale), blur: 22 * scale,
            color: NSColor(white: 0, alpha: 0.30).cgColor
        )
        context.setFillColor(NSColor.black.cgColor)
        context.fillEllipse(in: disc)
        context.restoreGState()
    }

    private static func draw(_ place: ShortcutRingFace.Place, at middle: CGPoint, isLit: Bool, dark: Bool, contrast: Bool, scale: CGFloat) {
        guard !place.isEmpty else {
            let side = emptyDotDiameter * scale
            emptyDot(dark: dark, contrast: contrast).setFill()
            NSBezierPath(ovalIn: CGRect(x: middle.x - side / 2, y: middle.y - side / 2, width: side, height: side)).fill()
            return
        }
        let diameter = ShortcutRingGeometry.placeDiameter * scale * (isLit ? litScale : 1)
        let circle = CGRect(x: middle.x - diameter / 2, y: middle.y - diameter / 2, width: diameter, height: diameter)
        (isLit ? litFill : placeFill(dark: dark, contrast: contrast)).setFill()
        NSBezierPath(ovalIn: circle).fill()
        if contrast && !isLit {
            let outline = NSBezierPath(ovalIn: circle.insetBy(dx: 0.5, dy: 0.5))
            outline.lineWidth = 1
            rim(dark: dark, contrast: true).setStroke()
            outline.stroke()
        }

        let grown = scale * (isLit ? litScale : 1)
        if let image = place.image {
            let side = iconSide * grown
            image.draw(
                in: CGRect(x: middle.x - side / 2, y: middle.y - side / 2, width: side, height: side),
                from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                hints: [.interpolation: NSNumber(value: NSImageInterpolation.high.rawValue)]
            )
            return
        }
        let colour = isLit ? litInk : ink(dark: dark)
        if !place.glyphs.isEmpty {
            drawGlyphs(place.glyphs, at: middle, colour: colour, scale: grown)
            return
        }
        guard let symbol = symbolImage(named: place.symbolName, pointSize: symbolPointSize * scale * (isLit ? litScale : 1), colour: colour) else {
            return
        }
        let size = symbol.size
        symbol.draw(
            in: CGRect(x: middle.x - size.width / 2, y: middle.y - size.height / 2, width: size.width, height: size.height),
            from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil
        )
    }

    /// A key combination's keys in the middle of a place, as large as fits.
    private static func drawGlyphs(_ lines: [String], at middle: CGPoint, colour: NSColor, scale: CGFloat) {
        let lines = Array(lines.prefix(2))
        let base = (lines.count > 1 ? glyphPointSize - 3 : glyphPointSize) * scale
        let texts: [NSAttributedString] = lines.map { line in
            var size = base
            let width = (line as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: .semibold)]).width
            let room = glyphWidth * scale
            if width > room {
                size = max(7 * scale, size * room / width)
            }
            return NSAttributedString(string: line, attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: .semibold),
                .foregroundColor: colour,
            ])
        }
        let heights = texts.map { ceil($0.size().height) }
        let gap: CGFloat = -2 * scale
        let total = heights.reduce(0, +) + gap * CGFloat(texts.count - 1)
        var top = middle.y + total / 2
        for (text, height) in zip(texts, heights) {
            let width = text.size().width
            text.draw(at: CGPoint(x: middle.x - width / 2, y: top - height))
            top -= height + gap
        }
    }

    /// An SF Symbol in one colour, at a size of its own.
    static func symbolImage(named name: String, pointSize: CGFloat, colour: NSColor) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [colour]))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }

    /// The lit action's name in the free middle: one or two lines, cut with an ellipsis.
    private static func drawTitle(_ title: String, centre: CGPoint, dark: Bool, scale: CGFloat) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        let font = NSFont.systemFont(ofSize: titleFont.pointSize * scale, weight: .semibold)
        let text = NSAttributedString(string: title, attributes: [
            .font: font,
            .foregroundColor: ink(dark: dark),
            .paragraphStyle: paragraph,
        ])
        let width = (ShortcutRingGeometry.hubRadius * 2 - 10) * scale
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let options: NSString.DrawingOptions = [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
        let wanted = text.boundingRect(with: CGSize(width: width, height: lineHeight * 2 + 1), options: options)
        let height = min(ceil(wanted.height), lineHeight * 2 + 1)
        text.draw(
            with: CGRect(x: centre.x - width / 2, y: centre.y - height / 2, width: width, height: height),
            options: options
        )
    }
}
