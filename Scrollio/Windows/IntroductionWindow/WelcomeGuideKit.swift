//
//  WelcomeGuideKit.swift
//  Mos
//  What every step of the Welcome Guide shares: the grid of the window, the text styles,
//  the picture card, the step dots and the clock of the animated pictures.
//
//  The window is 600 × 680 pt and never changes its size while it is open (600 × 620 with
//  tighter gaps on a screen too short for it: `WelcomeGuideLayout.Metrics`). Every step puts
//  a 552 × 236 picture at the top, then its title, at most two sentences and one control
//  under it; the bottom bar holds Back, the dots and the main button.
//

import Cocoa
import QuartzCore

enum WelcomeGuideLayout {

    /// How tall the window is and how much air its parts get. The feel step holds the most
    /// (a sentence of two lines, five cards, a box): in 620 pt its parts sat 14 to 18 pt
    /// apart, which looked crammed. Roomy unless the screen is too short for it.
    struct Metrics: Equatable {
        let windowHeight: CGFloat
        /// From the top of the text area to the title: the same on every step (the Welcome
        /// step's icon on the picture's edge fits above it).
        let titleTop: CGFloat
        let titleToText: CGFloat
        /// The control under the text.
        let textToControl: CGFloat
        /// A second control under the first (the box under the feel cards).
        let controlToControl: CGFloat
        let barBottom: CGFloat

        static let roomy = Metrics(
            windowHeight: 680, titleTop: 40, titleToText: 10, textToControl: 28, controlToControl: 28, barBottom: 24
        )
        /// The whole guide in 620 pt, for a screen that cannot show the roomy window whole:
        /// the window does not resize, and its bottom bar (Continue) would lie under the Dock.
        static let tight = Metrics(
            windowHeight: 620, titleTop: 36, titleToText: 8, textToControl: 18, controlToControl: 14, barBottom: 20
        )
        /// What must stay free around the roomy window on its screen.
        static let screenMargin: CGFloat = 16

        /// The measures for a screen with this much height between the menu bar and the Dock.
        static func fitting(visibleHeight: CGFloat?) -> Metrics {
            guard let visibleHeight else { return .roomy }
            return visibleHeight >= roomy.windowHeight + screenMargin ? .roomy : .tight
        }
    }

    /// Chosen for the screen before a guide's window is built
    /// (`IntroductionWindowController`); the views read it as they are built.
    static var metrics = Metrics.roomy

    static var windowSize: NSSize {
        return NSSize(width: 600, height: metrics.windowHeight)
    }
    static let sideMargin: CGFloat = 24
    /// Under the transparent title bar.
    static let pictureTop: CGFloat = 44
    static let pictureSize = NSSize(width: 552, height: 236)
    /// The text area of a step: from under the picture to 8 pt above the bar.
    static let contentTop: CGFloat = 280
    static var contentHeight: CGFloat {
        return barFrame.minY - 8 - contentTop
    }
    static var titleTop: CGFloat { return metrics.titleTop }
    static var titleToText: CGFloat { return metrics.titleToText }
    static var textToControl: CGFloat { return metrics.textToControl }
    static var controlToControl: CGFloat { return metrics.controlToControl }
    static let textWidth: CGFloat = 452
    /// A box of settings rows under the text (the status line is as wide).
    static let rowBoxWidth: CGFloat = 440
    static let barHeight: CGFloat = 28
    static var barBottom: CGFloat { return metrics.barBottom }
    static let pictureCornerRadius: CGFloat = 12

    /// In the flipped canvas of the window (origin top left).
    static var pictureFrame: NSRect {
        return NSRect(x: sideMargin, y: pictureTop, width: pictureSize.width, height: pictureSize.height)
    }

    static var contentFrame: NSRect {
        return NSRect(x: 0, y: contentTop, width: windowSize.width, height: contentHeight)
    }

    static var barFrame: NSRect {
        return NSRect(
            x: sideMargin, y: windowSize.height - barBottom - barHeight,
            width: windowSize.width - 2 * sideMargin, height: barHeight
        )
    }
}

/// The type of the guide: one title size, one text size, the small print of the panes.
enum WelcomeGuideText {

    static func localized(_ key: String) -> String {
        return NSLocalizedString(key, comment: "")
    }

    /// Semibold, as every heading of the Settings window.
    static var titleFont: NSFont {
        return NSFont.systemFont(ofSize: 22, weight: .semibold)
    }

    static var bodyFont: NSFont {
        return NSFont.systemFont(ofSize: NSFont.systemFontSize)
    }

    /// The step's title, centred.
    static func makeTitle(_ string: String) -> NSTextField {
        let label = NSTextField(labelWithString: string)
        label.font = titleFont
        label.textColor = .labelColor
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setAccessibilityRole(.staticText)
        return label
    }

    /// Wrapping text, `width` wide at most.
    static func makeText(
        _ string: String, font: NSFont = bodyFont, color: NSColor = .secondaryLabelColor,
        alignment: NSTextAlignment = .center, width: CGFloat = WelcomeGuideLayout.textWidth
    ) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: string)
        label.font = font
        label.textColor = color
        label.alignment = alignment
        label.isSelectable = false
        label.preferredMaxLayoutWidth = width
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    /// The column of a step's text area: the views stacked from `top`, centred.
    static func makeContent(_ views: [NSView], top: CGFloat = WelcomeGuideLayout.titleTop) -> (view: NSView, stack: NSStackView) {
        let content = WelcomeGuideFlippedView(frame: NSRect(origin: .zero, size: WelcomeGuideLayout.contentFrame.size))
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 0
        stack.detachesHiddenViews = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: top),
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor, constant: -2 * WelcomeGuideLayout.sideMargin),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor),
        ])
        return (content, stack)
    }
}

/// Top-left origin, as the grid of the guide is written.
class WelcomeGuideFlippedView: NSView {
    override var isFlipped: Bool { return true }
}

/// The area a step's picture or text sits in. While the steps change it takes no clicks:
/// the incoming step's controls are in place before they can be seen.
final class WelcomeGuideStepHost: WelcomeGuideFlippedView {
    var takesClicks = true

    override func hitTest(_ point: NSPoint) -> NSView? {
        return takesClicks ? super.hitTest(point) : nil
    }
}

/// Colours of the drawings that the Scrolling preview's palette does not have: the drawn
/// System Settings window and the menu. Their own, so they read right on every macOS.
enum WelcomeGuidePalette {
    private static func ink(_ light: CGFloat, _ dark: CGFloat) -> NSColor {
        return ScrollPreviewPalette.adaptive(light: NSColor(white: 0, alpha: light), dark: NSColor(white: 1, alpha: dark))
    }

    static let settingsWindow = ScrollPreviewPalette.adaptive(light: NSColor(white: 0.925, alpha: 1), dark: NSColor(white: 0.15, alpha: 1))
    static let settingsList = ScrollPreviewPalette.adaptive(light: .white, dark: NSColor(white: 0.2, alpha: 1))
    static let settingsEdge = ink(0.12, 0.12)
    static let settingsShadow = ScrollPreviewPalette.adaptive(light: NSColor(white: 0, alpha: 0.22), dark: NSColor(white: 0, alpha: 0.6))
    static let hairline = ink(0.09, 0.10)
    static let placeholder = ink(0.18, 0.22)
    static let faint = ink(0.30, 0.30)
    static let switchOff = ink(0.10, 0.16)
    static let knob = ScrollPreviewPalette.adaptive(light: .white, dark: NSColor(white: 0.91, alpha: 1))
    static let knobShadow = NSColor(white: 0, alpha: 0.3)
    static let menu = ScrollPreviewPalette.adaptive(
        light: NSColor(srgbRed: 0.965, green: 0.965, blue: 0.973, alpha: 0.94),
        dark: NSColor(srgbRed: 0.17, green: 0.17, blue: 0.18, alpha: 0.94)
    )
    static let menuEdge = ink(0.12, 0.14)
    static let menuText = ink(0.86, 0.9)
    static let menuShortcut = ink(0.42, 0.45)
    static let menuBarText = ink(0.85, 0.92)
    static let menuBarSelection = ink(0.12, 0.2)
    /// A selected choice: the accent colour, faint.
    static let selectedFill = NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        var colour = NSColor.controlAccentColor
        appearance.performAsCurrentDrawingAppearance {
            colour = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? colour
        }
        return colour.withAlphaComponent(dark ? 0.2 : 0.11)
    }
    /// The box behind a choice and behind the status line.
    static let box = ink(0.045, 0.06)
    /// Over a choice while the mouse button is down on it: darker in light, lighter in dark.
    static let pressed = ink(0.08, 0.10)
    static let boxEdge = NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        if PreferencesGroupedForm.isHighContrast(appearance) {
            return NSColor(white: dark ? 1 : 0, alpha: dark ? 0.5 : 0.45)
        }
        return NSColor(white: dark ? 1 : 0, alpha: dark ? 0.06 : 0.05)
    }
}

/// The card at the top of a step: the look of the Settings panes' header cards.
final class WelcomeGuideCardView: WelcomeGuideFlippedView {

    var cornerRadius = WelcomeGuideLayout.pictureCornerRadius

    override func draw(_ dirtyRect: NSRect) {
        Self.drawCard(in: bounds, cornerRadius: cornerRadius)
    }

    static func drawCard(in rect: NSRect, cornerRadius: CGFloat = WelcomeGuideLayout.pictureCornerRadius) {
        let card = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: cornerRadius, yRadius: cornerRadius)
        ScrollPreviewPalette.cardFill.setFill()
        card.fill()
        ScrollPreviewPalette.cardEdge.setStroke()
        card.lineWidth = 1
        card.stroke()
    }
}

/// The dots in the middle of the bar: one per step, the current one a wider capsule in
/// the accent colour. VoiceOver reads "Step 2 of 4".
final class WelcomeGuideStepDots: NSView {

    static let dotSize: CGFloat = 6
    static let currentWidth: CGFloat = 18
    static let spacing: CGFloat = 7

    private(set) var count = 0
    private(set) var current = 0

    func set(current: Int, of count: Int) {
        guard current != self.current || count != self.count else { return }
        self.current = current
        self.count = count
        invalidateIntrinsicContentSize()
        needsDisplay = true
        setAccessibilityLabel(Self.spokenPosition(current: current, of: count))
    }

    static func spokenPosition(current: Int, of count: Int) -> String {
        return String(format: WelcomeGuideText.localized("intro-step-of"), current + 1, count)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    required init?(coder: NSCoder) {
        fatalError("built in code")
    }

    override var intrinsicContentSize: NSSize {
        guard count > 0 else { return NSSize(width: 0, height: Self.dotSize) }
        let width = Self.currentWidth + CGFloat(count - 1) * (Self.dotSize + Self.spacing)
        return NSSize(width: width, height: Self.dotSize)
    }

    override func draw(_ dirtyRect: NSRect) {
        var x = (bounds.width - intrinsicContentSize.width) / 2
        let y = (bounds.height - Self.dotSize) / 2
        for index in 0..<count {
            let width = index == current ? Self.currentWidth : Self.dotSize
            let dot = NSBezierPath(
                roundedRect: NSRect(x: x, y: y, width: width, height: Self.dotSize),
                xRadius: Self.dotSize / 2, yRadius: Self.dotSize / 2
            )
            (index == current ? NSColor.controlAccentColor : WelcomeGuidePalette.placeholder).setFill()
            dot.fill()
            x += width + Self.spacing
        }
    }
}

/// A picture that plays a loop. The clock runs only while the step is shown, its window
/// can be seen and Reduce Motion is off; otherwise the picture shows its still frame
/// (`showStill`). Subclasses draw the moment they are given.
class WelcomeGuideAnimatedView: WelcomeGuideFlippedView {

    /// Reduce Motion in System Settings › Accessibility. A seam for the tests.
    var prefersReducedMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion } {
        didSet { updateClock() }
    }
    /// Some of `window` shows on screen. A seam for the tests.
    var isWindowVisible: (NSWindow) -> Bool = { $0.occlusionState.contains(.visible) }

    private var wantsAnimation = false
    private var frameLink: CADisplayLink?
    private var origin: CFTimeInterval?
    private weak var observedWindow: NSWindow?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(displayOptionsDidChange),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("built in code")
    }

    deinit {
        frameLink?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    /// The step calls this with true when it shows and with false when it goes.
    func setAnimating(_ on: Bool) {
        wantsAnimation = on
        updateClock()
    }

    var isClockRunning: Bool {
        return frameLink != nil
    }

    /// Starts the loop again from its beginning (a change the user made shows at once).
    func restartLoop() {
        origin = nil
        if isClockRunning {
            show(time: 0)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let old = observedWindow {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: old)
        }
        observedWindow = window
        if let window {
            NotificationCenter.default.addObserver(
                self, selector: #selector(occlusionDidChange),
                name: NSWindow.didChangeOcclusionStateNotification, object: window
            )
        }
        updateClock()
    }

    @objc private func displayOptionsDidChange() {
        updateClock()
    }

    @objc private func occlusionDidChange() {
        updateClock()
    }

    private var shouldAnimate: Bool {
        guard wantsAnimation, let window, isWindowVisible(window) else { return false }
        return !prefersReducedMotion()
    }

    func updateClock() {
        if shouldAnimate {
            guard frameLink == nil else { return }
            origin = nil
            show(time: 0)
            let link = displayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            frameLink = link
        } else {
            frameLink?.invalidate()
            frameLink = nil
            origin = nil
            if prefersReducedMotion() {
                showStill()
            } else {
                show(time: 0)
            }
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.targetTimestamp
        let start = origin ?? now
        origin = start
        show(time: now - start)
    }

    /// The loop `time` seconds after it began (it wraps by itself).
    func show(time: TimeInterval) {}

    /// The picture without motion.
    func showStill() {}

    // MARK: - Easing (cubic: out for arrivals, in-out for moves there and back)

    static func clamp01(_ value: Double) -> Double {
        return min(1, max(0, value))
    }

    static func easeOut(_ progress: Double) -> Double {
        let p = clamp01(progress)
        return 1 - (1 - p) * (1 - p) * (1 - p)
    }

    static func easeInOut(_ progress: Double) -> Double {
        let p = clamp01(progress)
        return p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2
    }
}

/// The mouse of the Welcome and feel pictures: the connected model's drawing
/// (MouseArtwork), with lit parts, a wheel that turns and flashes, and a press.
struct WelcomeGuideMouseDrawing {

    var model: MouseArtworkModel
    /// Points per unit of the drawing's grid (88 × 120).
    var unit: CGFloat
    /// Where the grid's top left lies.
    var origin: NSPoint
    var lit: Set<MouseArtworkPart> = []
    /// Lit parts drawn pressed in.
    var pressed: Set<MouseArtworkPart> = []
    /// Clicks the wheel has turned (fractional while it turns): its ridges move.
    var wheelTurn: Double = 0
    /// 1 at a click, falling to 0: a ring round the wheel.
    var pulse: Double = 0

    var shapes: MouseArtworkShapes {
        return MouseArtworkShapes(model: model)
    }

    var size: NSSize {
        return NSSize(width: MouseArtworkShapes.grid.width * unit, height: MouseArtworkShapes.grid.height * unit)
    }

    /// A point of the grid in the view.
    func point(_ grid: NSPoint) -> NSPoint {
        return NSPoint(x: origin.x + grid.x * unit, y: origin.y + grid.y * unit)
    }

    /// The middle of a part, in the view; nil when the mouse does not have it.
    func centre(of parts: [MouseArtworkPart]) -> NSPoint? {
        let rects = parts.compactMap { shapes.shape(of: $0)?.bounds }
        guard var union = rects.first else { return nil }
        for rect in rects.dropFirst() {
            union = union.union(rect)
        }
        return point(NSPoint(x: union.midX, y: union.midY))
    }

    func draw() {
        let shapes = self.shapes
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: origin.x, yBy: origin.y)
        transform.scale(by: unit)
        transform.concat()

        MouseArtworkPainter.draw(shapes, ink: .card, unit: unit)
        for part in MouseArtworkPart.allCases where lit.contains(part) && model.has(part) {
            MouseArtworkPainter.drawHighlight(part, shapes: shapes, unit: unit)
            if pressed.contains(part), let shape = shapes.shape(of: part) {
                NSColor.black.withAlphaComponent(0.22).setFill()
                shape.fill()
            }
        }
        if lit.contains(.wheel) {
            drawTurningWheel(shapes.wheelRect)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// The lit wheel with its ridges where the turn has carried them, and the flash of a
    /// click (as the Scrolling preview's wheel).
    private func drawTurningWheel(_ rect: NSRect) {
        let accent = NSColor.controlAccentColor
        let glow = CGFloat(min(1, max(0, pulse)))
        if glow > 0 {
            let spread = (1.5 + (1 - glow) * 4) / unit * 1.6
            let ring = NSBezierPath(
                roundedRect: rect.insetBy(dx: -spread, dy: -spread),
                xRadius: rect.width / 2 + spread, yRadius: rect.width / 2 + spread
            )
            ring.lineWidth = 2 / unit
            accent.withAlphaComponent(0.9 * glow).setStroke()
            ring.stroke()
        }
        let body = NSBezierPath(roundedRect: rect, xRadius: rect.width / 2, yRadius: rect.width / 2)
        accent.setFill()
        body.fill()
        NSGraphicsContext.saveGraphicsState()
        body.addClip()
        let step = Double.pi / 6
        let shift = (wheelTurn.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * step
        for index in -3...3 {
            let angle = Double(index) * step + shift
            guard abs(angle) < Double.pi / 2 else { continue }
            let y = rect.midY + rect.height / 2 * CGFloat(sin(angle))
            let facing = CGFloat(cos(angle))
            let ridge = NSBezierPath()
            ridge.move(to: NSPoint(x: rect.minX + 2.5, y: y))
            ridge.line(to: NSPoint(x: rect.maxX - 2.5, y: y))
            ridge.lineWidth = 1 / unit
            ridge.lineCapStyle = .round
            MouseArtworkPalette.litRidge.withAlphaComponent(0.6 * facing).setStroke()
            ridge.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}
