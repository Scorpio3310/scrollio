//
//  TriggerPictureViews.swift
//  Scrollio
//  The pieces the trigger pictures (`TriggerPicture`) are drawn with, shared by the
//  Gestures pane's device card and the Shortcut Ring pane's trigger card: a key in the
//  Scrolling pane's look, the accent badge of a button the drawing cannot show, the dashed
//  placeholder of the default picture and the chip with an app's icon.
//
//  All of them are pictures only: they take no click and are not read out (the panes' rows
//  already say what the picture shows).
//

import Cocoa

// MARK: - A key

/// One key of a trigger, as the Scrolling pane draws its key (`ScrollPreviewKeyCap.draw`)
/// at `faceHeight`: as wide as its label needs, at least square. Pressed (`depth` 1) it
/// sinks, its face takes the accent colour and its label turns white. As a placeholder it
/// is a dashed outline without fill or label: a key that is not set yet.
final class TriggerKeyCap: NSView {

    /// The Scrolling pane's key, which the other sizes are scaled from.
    private static let referenceHeight: CGFloat = 34
    static let margin: CGFloat = 2

    let faceHeight: CGFloat

    var label: String {
        didSet {
            guard label != oldValue else { return }
            setFrameSize(Self.size(label: label, faceHeight: faceHeight))
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    /// 0: up, 1: pressed.
    var depth: CGFloat = 0 {
        didSet { if depth != oldValue { needsDisplay = true } }
    }

    var isPlaceholder = false {
        didSet { if isPlaceholder != oldValue { needsDisplay = true } }
    }

    init(label: String, faceHeight: CGFloat) {
        self.label = label
        self.faceHeight = faceHeight
        super.init(frame: NSRect(origin: .zero, size: Self.size(label: label, faceHeight: faceHeight)))
        // Redrawn alone while it sinks; nothing outside its bounds.
        wantsLayer = true
        clipsToBounds = true
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        fatalError("TriggerKeyCap is built in code")
    }

    override var isFlipped: Bool { return true }

    override var intrinsicContentSize: NSSize {
        return Self.size(label: label, faceHeight: faceHeight)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    // MARK: Geometry

    private static func scale(_ faceHeight: CGFloat) -> CGFloat {
        return faceHeight / referenceHeight
    }

    static func font(faceHeight: CGFloat) -> NSFont {
        return NSFont.systemFont(ofSize: (17 * scale(faceHeight)).rounded(), weight: .medium)
    }

    /// How far the key stands up and sinks: the Scrolling pane's 3 pt at its size, at
    /// least 2 pt.
    static func travel(faceHeight: CGFloat) -> CGFloat {
        return max(2, (ScrollPreviewKeyCap.height * scale(faceHeight)).rounded())
    }

    static func cornerRadius(faceHeight: CGFloat) -> CGFloat {
        return ScrollPreviewKeyCap.cornerRadius * scale(faceHeight)
    }

    /// The face: at least square, and wide enough for the label with the Scrolling pane's
    /// room around it (20 pt at 34 pt).
    static func faceWidth(label: String, faceHeight: CGFloat) -> CGFloat {
        let text = NSAttributedString(string: label, attributes: [.font: font(faceHeight: faceHeight)])
        return max(faceHeight, ceil(text.size().width) + 20 * scale(faceHeight))
    }

    /// The view: the face, its travel under it, and `margin` all round.
    static func size(label: String, faceHeight: CGFloat) -> NSSize {
        return NSSize(
            width: faceWidth(label: label, faceHeight: faceHeight) + 2 * margin,
            height: faceHeight + travel(faceHeight: faceHeight) + 2 * margin
        )
    }

    /// Where the face is while the key is up.
    var faceRect: NSRect {
        return NSRect(
            x: Self.margin, y: Self.margin,
            width: Self.faceWidth(label: label, faceHeight: faceHeight), height: faceHeight
        )
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let radius = Self.cornerRadius(faceHeight: faceHeight)
        if isPlaceholder {
            let outline = NSBezierPath(roundedRect: faceRect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
            TriggerPlaceholder.stroke(outline, highContrast: PreferencesGroupedForm.isHighContrast(effectiveAppearance))
            return
        }
        ScrollPreviewKeyCap.draw(
            glyph: label, depth: depth, face: faceRect, travel: Self.travel(faceHeight: faceHeight),
            cornerRadius: radius, font: Self.font(faceHeight: faceHeight)
        )
    }
}

// MARK: - The badge

/// The accent badge that stands in for a button the drawing cannot show: its number
/// (`.number`), or the symbol of a programmable button (`.notDrawn`: a button of this mouse
/// the drawing does not have). The Buttons card's number badge, at any height.
enum TriggerBadge {

    /// The symbol of `.notDrawn`. If it ever does not load, the badge is drawn empty.
    static let symbolName = "button.programmable"

    static func font(height: CGFloat) -> NSFont {
        return NSFont.systemFont(ofSize: (height * 0.6).rounded(), weight: .bold)
    }

    /// A capsule `height` tall, at least as wide; zero for a hold that is no badge.
    static func size(for hold: TriggerPicture.Hold, height: CGFloat) -> NSSize {
        switch hold {
        case .number(let number):
            return ButtonsMouseMiniature.badgeSize(for: number, font: font(height: height), height: height)
        case .notDrawn:
            return NSSize(width: height, height: height)
        case .part, .keys:
            return .zero
        }
    }

    /// The badge filling `rect` (in a flipped view); nothing for a hold that is no badge.
    static func draw(
        _ hold: TriggerPicture.Hold, in rect: NSRect, symbolName: String = TriggerBadge.symbolName,
        accent: NSColor = .controlAccentColor
    ) {
        let ink = ShortcutRingArtwork.litInk(on: accent)
        switch hold {
        case .number(let number):
            // (White, or near black on a light accent such as Yellow.)
            ButtonsMouseMiniature.drawBadge(number, in: rect, font: font(height: rect.height), fill: accent, text: ink)
        case .notDrawn:
            accent.setFill()
            let radius = min(rect.width, rect.height) / 2
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            guard let symbol = symbol(named: symbolName, height: rect.height, ink: ink) else { return }
            let size = symbol.size
            symbol.draw(
                in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height),
                from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil
            )
        case .part, .keys:
            break
        }
    }

    /// The symbol in `ink` (white on the accent colour) for a badge `height` tall; nil when
    /// the system has no such symbol.
    static func symbol(named name: String = TriggerBadge.symbolName, height: CGFloat, ink: NSColor = .white) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: (height * 0.55).rounded(), weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [ink]))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
    }
}

// MARK: - The placeholder

/// The dashed outline of the default picture, where a trigger would be (the button
/// "Set Up…" usually ends with, a key): in label grey, never filled, never in the accent
/// colour, so nothing looks set.
enum TriggerPlaceholder {

    /// How far outside the part's bounds the outline runs.
    static let outset: CGFloat = 3
    static let dash: [CGFloat] = [3, 2]

    /// A rounded rectangle `outset` outside `rect` (the corners at most 6 pt round; a thin
    /// part gets a capsule).
    static func path(around rect: NSRect) -> NSBezierPath {
        let outer = rect.insetBy(dx: -outset, dy: -outset)
        let radius = min(6, min(outer.width, outer.height) / 2)
        return NSBezierPath(roundedRect: outer, xRadius: radius, yRadius: radius)
    }

    /// Strokes `path` dashed: 1 pt in the secondary label colour; under Increase Contrast
    /// 1.5 pt in the label colour.
    static func stroke(_ path: NSBezierPath, highContrast: Bool) {
        path.lineWidth = highContrast ? 1.5 : 1
        path.setLineDash(dash, count: dash.count, phase: 0)
        (highContrast ? NSColor.labelColor : NSColor.secondaryLabelColor).setStroke()
        path.stroke()
    }
}

// MARK: - The app chip

/// The icon of the app whose own trigger the picture shows ("Only in Notes: …"), 18 pt.
/// No path hides it; the icon is read once per new path.
final class TriggerAppChip: NSImageView {

    static let side: CGFloat = 18

    var path: String? {
        didSet {
            guard path != oldValue else { return }
            image = path.map { Utils.getApplicationIcon(fromPath: $0) }
            isHidden = path == nil
        }
    }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.side, height: Self.side))
        imageScaling = .scaleProportionallyUpOrDown
        isHidden = true
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        fatalError("TriggerAppChip is built in code")
    }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: Self.side, height: Self.side)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}
