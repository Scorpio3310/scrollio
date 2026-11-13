//
//  ShortcutRingArtwork.swift
//  Scrollio
//
//  How the Shortcut Ring looks: what its places show (`ShortcutRingFace`, made from the
//  stored ring as the Buttons pane shows an action) and the drawing itself, the same
//  functions for the ring on screen, the ring in the Settings pane and the pictures the
//  render tests make. The ring is nine drops and no disc (`ShortcutRingDrops` says where
//  each is and how large); the sizes of the places are `ShortcutRingGeometry`'s.
//
//  A drop has a body and what stands in it (a place's symbol, icon or keys; the hub's
//  name of the lit action). The body depends on the material (`Backdrop`): drawn opaque
//  by `drawBodies`; or the system's blurred material, which only the window server can
//  draw, with `drawBodies` adding its rim and the lit colour and `drawMask` cutting it to
//  the drops; or Liquid Glass, which is views of its own (`ShortcutRingPanel`) and gets
//  nothing drawn here.
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
    ///
    /// An app's or a file's name and icon are looked up on disk (does the file exist,
    /// Launch Services, the icon): never while a ring is held or is being shown, when the
    /// event taps wait on the main thread. With `looksOnDisk` false such a place shows the
    /// file's own name and a plain symbol instead; `ShortcutRingController` shows that
    /// until a face made at a quiet moment is there (`prepare`, and after a ring closed).
    init(_ ring: ShortcutRingSettings, looksOnDisk: Bool = true, resolver: ActionDisplayResolver = ActionDisplayResolver()) {
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
            case .open(let target):
                guard looksOnDisk else {
                    return Place(title: Self.plainName(of: target), symbolName: "arrow.up.forward.app", isEmpty: false)
                }
                let shown = resolver.resolve(state: CellActionState(binding: place.asBinding()))
                return Place(
                    title: shown.title, symbolName: shown.symbolName ?? "arrow.up.forward.app",
                    image: shown.image, isEmpty: false
                )
            }
        })
    }

    /// What a place that opens something is called without a look on disk: the file's
    /// name as its path has it, an app's without ".app".
    static func plainName(of target: OpenTargetPayload) -> String {
        let file = (target.path as NSString).lastPathComponent
        let name = target.kind == .application ? (file as NSString).deletingPathExtension : file
        return name.isEmpty ? target.path : name
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

    /// What the drops' bodies are.
    enum Backdrop {
        /// Opaque drops, drawn here: "Reduce transparency", "Increase contrast", the
        /// Settings pane and pictures made without a screen.
        case drawn
        /// The window's blurred material shows in each drop: only the rim and the lit
        /// colour are drawn.
        case material
        /// Liquid Glass: the bodies are glass views, nothing of them is drawn.
        case glass
    }

    struct Style {
        var backdrop = Backdrop.material
        /// "Increase contrast": firmer outlines.
        var increasesContrast = false
        /// Drawn `scale` times as large (the pane shows the ring smaller than the screen).
        var scale: CGFloat = 1
    }

    // MARK: Sizes

    static let symbolPointSize: CGFloat = 20
    /// An app's or a file's icon in a place.
    static let iconSide: CGFloat = 34
    /// A key combination's text in a place: at most this large, smaller when it is long,
    /// and never wider than this part of the place.
    static let glyphPointSize: CGFloat = 15
    static let glyphWidth: CGFloat = 40
    /// The name in the hub. (13 in the free middle of the disc, which was wider.)
    static let titleFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
    /// The room the name has in the hub: the drop without 6 points at either side.
    static let titleWidth: CGFloat = ShortcutRingDrops.hubDiameter - 12
    /// A name too long for two lines of the hub gets three, this much smaller.
    static let longTitleShrink: CGFloat = 0.88

    // MARK: Colours

    /// The lit place: the accent colour (the app's purple, or the user's own choice).
    static var litFill: NSColor { return NSColor.controlAccentColor }

    /// What stands on a lit place: white, or near black on an accent colour that is light
    /// itself (white on the system's yellow cannot be read).
    static var litInk: NSColor {
        return litInk(on: litFill)
    }

    static func litInk(on fill: NSColor) -> NSColor {
        guard let colour = fill.usingColorSpace(.sRGB) else { return .white }
        func linear(_ value: CGFloat) -> CGFloat {
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(colour.redComponent) + 0.7152 * linear(colour.greenComponent)
            + 0.0722 * linear(colour.blueComponent)
        // Where black has the better contrast than white (WCAG's contrast ratio).
        return luminance > 0.36 ? NSColor(white: 0, alpha: 0.85) : .white
    }

    static func isDark() -> Bool {
        return NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// A drawn drop's body.
    static func dropFill(dark: Bool, contrast: Bool) -> NSColor {
        if contrast {
            return dark ? NSColor(white: 0.10, alpha: 1) : NSColor(white: 0.98, alpha: 1)
        }
        return dark ? NSColor(white: 0.19, alpha: 1) : NSColor(white: 0.97, alpha: 1)
    }

    static func rim(dark: Bool, contrast: Bool) -> NSColor {
        if contrast {
            return dark ? NSColor(white: 1, alpha: 0.75) : NSColor(white: 0, alpha: 0.65)
        }
        return dark ? NSColor(white: 1, alpha: 0.18) : NSColor(white: 0, alpha: 0.14)
    }

    static func ink(dark: Bool) -> NSColor {
        return dark ? NSColor(white: 1, alpha: 0.92) : NSColor(white: 0, alpha: 0.82)
    }

    /// `amount` of the way from one colour to another (0: `from`, 1: `to`).
    static func blend(_ from: NSColor, _ to: NSColor, _ amount: CGFloat) -> NSColor {
        guard amount > 0 else { return from }
        guard amount < 1 else { return to }
        return from.usingColorSpace(.sRGB)?.blended(withFraction: amount, of: to.usingColorSpace(.sRGB) ?? to) ?? to
    }

    // MARK: Drawing the whole ring

    /// Draws the ring at rest with its middle at `centre` into the current context (y
    /// upwards), in the current drawing appearance: the Settings pane and still pictures.
    static func draw(_ face: ShortcutRingFace, lit: Int?, centre: CGPoint, style: Style = Style()) {
        let lit = lit.flatMap { face.places.indices.contains($0) && !face.places[$0].isEmpty ? $0 : nil }
        draw(
            face, drops: ShortcutRingDrops.settled(filled: face.filled, lit: lit),
            title: lit.map { face.places[$0].title }, centre: centre, style: style
        )
    }

    /// Draws the ring as `drops` has it: the bodies, what stands in the places and
    /// `title` in the hub.
    static func draw(_ face: ShortcutRingFace, drops: ShortcutRingDrops.Frame, title: String?, centre: CGPoint, style: Style = Style()) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let dark = isDark()
        let scale = style.scale
        drawBodies(drops, centre: centre, style: style)
        for (place, drop) in zip(face.places, drops.places) where !place.isEmpty && drop.opacity > 0 {
            context.saveGState()
            context.setAlpha(drop.opacity)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            drawContent(
                of: place, at: middle(of: drop, centre: centre, scale: scale),
                scale: scale * drop.contentScale, colour: blend(ink(dark: dark), litInk, drop.lit)
            )
            context.endTransparencyLayer()
            context.restoreGState()
        }
        if let title, !title.isEmpty {
            let grow = drops.hub.contentScale
            drawTitle(
                title, centre: centre, colour: ink(dark: dark), width: titleWidth * scale * grow,
                pointSize: titleFont.pointSize * scale * grow
            )
        }
    }

    /// Where a drop's middle is in a drawing with its ring's middle at `centre`.
    static func middle(of drop: ShortcutRingDrops.Drop, centre: CGPoint, scale: CGFloat = 1) -> CGPoint {
        // The geometry's y grows downwards, the drawing's upwards.
        return CGPoint(x: centre.x + drop.offset.x * scale, y: centre.y - drop.offset.y * scale)
    }

    static func circle(of drop: ShortcutRingDrops.Drop, centre: CGPoint, scale: CGFloat = 1) -> CGRect {
        let middle = self.middle(of: drop, centre: centre, scale: scale)
        let diameter = drop.diameter * scale
        return CGRect(x: middle.x - diameter / 2, y: middle.y - diameter / 2, width: diameter, height: diameter)
    }

    // MARK: The bodies

    /// The drops' bodies as far as they are drawn (see `Backdrop`), each with a soft shadow
    /// around it and none under it: what lies under a drop of material must show through.
    static func drawBodies(_ drops: ShortcutRingDrops.Frame, centre: CGPoint, style: Style = Style()) {
        guard style.backdrop != .glass, let context = NSGraphicsContext.current?.cgContext else { return }
        let dark = isDark()
        let contrast = style.increasesContrast
        let scale = style.scale
        let visible = drops.stacked.filter { $0.opacity > 0 && $0.diameter > 0 }

        for drop in visible {
            let circle = self.circle(of: drop, centre: centre, scale: scale)
            context.saveGState()
            let outside = CGMutablePath()
            outside.addRect(circle.insetBy(dx: -24 * scale, dy: -24 * scale))
            outside.addEllipse(in: circle)
            context.addPath(outside)
            context.clip(using: .evenOdd)
            context.setShadow(
                offset: CGSize(width: 0, height: -2 * scale), blur: 9 * scale,
                color: NSColor(white: 0, alpha: (dark ? 0.42 : 0.24) * drop.opacity).cgColor
            )
            context.setFillColor(NSColor.black.cgColor)
            context.fillEllipse(in: circle)
            context.restoreGState()
        }

        let rimWidth: CGFloat = contrast ? 1.5 : 1
        for drop in visible {
            let circle = self.circle(of: drop, centre: centre, scale: scale)
            context.saveGState()
            context.setAlpha(drop.opacity)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            switch style.backdrop {
            case .drawn:
                blend(dropFill(dark: dark, contrast: contrast), litFill, drop.lit).setFill()
                NSBezierPath(ovalIn: circle).fill()
            case .material, .glass:
                if drop.lit > 0 {
                    litFill.withAlphaComponent(drop.lit).setFill()
                    NSBezierPath(ovalIn: circle).fill()
                }
            }
            // A lit drop needs no outline, except where outlines are asked for.
            let rimAlpha = contrast ? 1 : 1 - drop.lit
            if rimAlpha > 0, circle.width > rimWidth * 2 {
                let outline = NSBezierPath(ovalIn: circle.insetBy(dx: rimWidth / 2, dy: rimWidth / 2))
                outline.lineWidth = rimWidth
                let colour = rim(dark: dark, contrast: contrast)
                colour.withAlphaComponent(colour.alphaComponent * rimAlpha).setStroke()
                outline.stroke()
            }
            context.endTransparencyLayer()
            context.restoreGState()
        }
    }

    /// Where the blurred material shows: every drop's circle, as opaque as the drop is
    /// (an `NSVisualEffectView`'s `maskImage` is drawn with this).
    static func drawMask(_ drops: ShortcutRingDrops.Frame, centre: CGPoint) {
        for drop in drops.all where drop.opacity > 0 && drop.diameter > 0 {
            NSColor(white: 0, alpha: drop.opacity).setFill()
            NSBezierPath(ovalIn: circle(of: drop, centre: centre)).fill()
        }
    }

    // MARK: What stands in a drop

    /// A place's icon, keys or symbol with its middle at `middle`, `scale` times as large
    /// as on screen at rest. Nothing for an empty place.
    static func drawContent(of place: ShortcutRingFace.Place, at middle: CGPoint, scale: CGFloat, colour: NSColor) {
        guard !place.isEmpty, scale > 0 else { return }
        if let image = place.image {
            let side = iconSide * scale
            image.draw(
                in: CGRect(x: middle.x - side / 2, y: middle.y - side / 2, width: side, height: side),
                from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                hints: [.interpolation: NSNumber(value: NSImageInterpolation.high.rawValue)]
            )
            return
        }
        if !place.glyphs.isEmpty {
            drawGlyphs(place.glyphs, at: middle, colour: colour, scale: scale)
            return
        }
        guard let symbol = symbolImage(named: place.symbolName, pointSize: symbolPointSize * scale, colour: colour) else {
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

    /// The lit action's name in the hub, `width` wide: one or two lines; a name that
    /// needs a third ("Screenshot and Recording Options") gets it, a little smaller. Only
    /// what is longer still is cut with an ellipsis.
    static func drawTitle(_ title: String, centre: CGPoint, colour: NSColor, width: CGFloat, pointSize: CGFloat) {
        guard width > 0, pointSize > 0 else { return }
        let layout = titleLayout(title, width: width, pointSize: pointSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        let text = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: layout.pointSize, weight: .semibold),
            .foregroundColor: colour,
            .paragraphStyle: paragraph,
        ])
        text.draw(
            with: CGRect(x: centre.x - width / 2, y: centre.y - layout.height / 2, width: width, height: layout.height),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
        )
    }

    /// How a name stands in a hub with `width` of room: at `pointSize` on up to two lines, else
    /// smaller on up to three.
    static func titleLayout(_ title: String, width: CGFloat, pointSize: CGFloat) -> (pointSize: CGFloat, lines: Int, height: CGFloat) {
        func measure(_ size: CGFloat) -> (lines: Int, lineHeight: CGFloat) {
            let font = NSFont.systemFont(ofSize: size, weight: .semibold)
            let lineHeight = ceil(font.ascender - font.descender + font.leading)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byWordWrapping
            let needed = (title as NSString).boundingRect(
                with: CGSize(width: width, height: 10_000), options: [.usesLineFragmentOrigin],
                attributes: [.font: font, .paragraphStyle: paragraph]
            ).height
            return (max(1, Int((needed / lineHeight).rounded())), lineHeight)
        }
        let usual = measure(pointSize)
        if usual.lines <= 2 {
            return (pointSize, usual.lines, usual.lineHeight * CGFloat(usual.lines) + 1)
        }
        let smaller = pointSize * longTitleShrink
        let shrunk = measure(smaller)
        let lines = min(3, shrunk.lines)
        return (smaller, lines, shrunk.lineHeight * CGFloat(lines) + 1)
    }
}
