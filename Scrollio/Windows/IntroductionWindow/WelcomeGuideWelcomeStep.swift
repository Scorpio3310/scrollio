//
//  WelcomeGuideWelcomeStep.swift
//  Mos
//  Step 1 of the Welcome Guide: what Scrollio does. The connected mouse lights one part
//  every 2 s (the wheel turns, the side buttons press, the gesture button lights while the
//  mouse slides; the gesture button only on a model that has one), and the matching one of
//  the three features under the title is boxed. With Reduce Motion every part is lit and
//  nothing moves.
//

import Cocoa

final class WelcomeGuideWelcomeStep: WelcomeGuideStepView {

    let step = WelcomeGuideStep.welcome
    let picture: NSView
    let content: NSView

    let artwork: WelcomeGuideWelcomePicture
    private(set) var titleLabel: NSTextField!
    private(set) var textLabel: NSTextField!
    private(set) var iconView: NSImageView!
    private(set) var features: [WelcomeGuideFeatureView] = []
    private var observers: [NSObjectProtocol] = []

    /// The drawing for the connected mouse. A seam for the tests and renders.
    var mouseSource: () -> MouseArtworkModel {
        didSet { reloadMouse() }
    }

    init(mouseSource: @escaping () -> MouseArtworkModel) {
        self.mouseSource = mouseSource
        let card = WelcomeGuideCardView(frame: NSRect(origin: .zero, size: WelcomeGuideLayout.pictureSize))
        artwork = WelcomeGuideWelcomePicture(frame: card.bounds)
        artwork.autoresizingMask = [.width, .height]
        card.addSubview(artwork)
        picture = card

        let title = WelcomeGuideText.makeTitle(WelcomeGuideText.localized("intro-title"))
        let text = WelcomeGuideText.makeText(WelcomeGuideText.localized("intro-subtitle"))
        let kinds: [WelcomeGuideFeatureView.Kind] = [.scrolling, .buttons, .gestures]
        let featureViews = kinds.map { WelcomeGuideFeatureView(kind: $0) }
        let row = NSStackView(views: featureViews)
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = WelcomeGuideFeatureView.spacing
        row.translatesAutoresizingMaskIntoConstraints = false
        // One height for the three, so the box that moves from one to the next keeps its size.
        for view in featureViews.dropFirst() {
            view.heightAnchor.constraint(equalTo: featureViews[0].heightAnchor).isActive = true
        }

        let (view, stack) = WelcomeGuideText.makeContent([title, text, row])
        stack.setCustomSpacing(WelcomeGuideLayout.titleToText, after: title)
        stack.setCustomSpacing(WelcomeGuideLayout.textToControl, after: text)
        content = view

        // The app icon sits on the lower edge of the picture.
        let iconSide: CGFloat = 52
        let icon = NSImageView(frame: NSRect(
            x: (WelcomeGuideLayout.windowSize.width - iconSide) / 2, y: -30, width: iconSide, height: iconSide
        ))
        icon.image = NSImage(named: NSImage.applicationIconName)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.setAccessibilityElement(false)
        icon.wantsLayer = true
        icon.shadow = {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
            shadow.shadowBlurRadius = 8
            shadow.shadowOffset = NSSize(width: 0, height: -4)
            return shadow
        }()
        view.addSubview(icon)

        titleLabel = title
        textLabel = text
        iconView = icon
        features = featureViews

        artwork.onPhaseChange = { [weak self] phase in
            guard let self else { return }
            for (index, feature) in self.features.enumerated() {
                feature.isHighlighted = phase == index
            }
        }
        for name in [LogiCenter.sessionChanged, LogiCenter.mouseStateChanged] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.reloadMouse()
            })
        }
        reloadMouse()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func reloadMouse() {
        let model = mouseSource()
        artwork.model = model
        for feature in features {
            feature.model = model
        }
    }

    func setShown(_ shown: Bool) {
        if shown { reloadMouse() }
        artwork.setAnimating(shown)
    }
}

/// The drawing of step 1.
final class WelcomeGuideWelcomePicture: WelcomeGuideAnimatedView {

    /// Points per unit of the drawing's grid, and where the grid starts: the mouse in the middle.
    static let unit: CGFloat = 1.36
    static var mouseOrigin: NSPoint {
        let width = MouseArtworkShapes.grid.width * unit
        return NSPoint(x: ((WelcomeGuideLayout.pictureSize.width - width) / 2).rounded(), y: 18)
    }
    static let phaseLength: TimeInterval = 2
    /// How far the mouse slides for a gesture.
    static let slide: CGFloat = 14
    static let glowRadius: CGFloat = 62

    /// What one moment shows.
    struct Frame: Equatable {
        /// 0 wheel, 1 side buttons, 2 gesture button; nil: everything lit (the still).
        var phase: Int?
        var wheelTurn: Double = 0
        var pulse: Double = 0
        var pressed: Set<MouseArtworkPart> = []
        var slide: CGFloat = 0
        var arrow: CGFloat = 0
        /// From the last part's glow to this one's (0...1).
        var glowTravel: CGFloat = 1
        /// How far the mouse has turned to its view from the thumb side (0...1), where the
        /// phase's parts light there; a mouse drawn from above only stays at 0.
        var turn: CGFloat = 0
    }

    var model: MouseArtworkModel = .generic {
        didSet {
            guard model != oldValue else { return }
            needsDisplay = true
            updateClock()
        }
    }

    /// The feature boxed under the title follows the lit part.
    var onPhaseChange: ((Int?) -> Void)?

    /// What is drawn.
    private(set) var shownFrame = Frame(phase: 0)
    /// The phase the features were last told about (nil inside: the still).
    private var notifiedPhase: Int?? = .none

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(WelcomeGuideText.localized("intro-welcome-picture"))
    }

    required init?(coder: NSCoder) {
        fatalError("built in code")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    var phaseCount: Int {
        return model.has(.gesture) ? 3 : 2
    }

    func parts(ofPhase phase: Int) -> [MouseArtworkPart] {
        switch phase {
        case 0: return [.wheel]
        case 1: return [.forward, .back]
        default: return [.gesture]
        }
    }

    /// The view of the drawing a phase's parts light in.
    func viewpoint(ofPhase phase: Int) -> MouseArtworkViewpoint {
        return model.viewpoint(lighting: parts(ofPhase: phase).first)
    }

    /// The still of a mouse drawn in two views shows both, everything lit, each part in
    /// its view: the view from above this far left of the middle and the one from the
    /// thumb side this far right (points).
    static let stillSpread: (above: CGFloat, side: CGFloat) = (92, 78)

    /// Where the gesture's arrow starts from: left of the mouse, by the gesture button
    /// (the drawing's grid).
    func arrowAnchor(in viewpoint: MouseArtworkViewpoint) -> NSPoint {
        guard model.hasSideView else { return NSPoint(x: 0, y: 49) }
        return viewpoint == .thumbSide ? NSPoint(x: -18, y: 64) : NSPoint(x: 0, y: 66)
    }

    /// The moment `time` seconds into the loop.
    func frame(at time: TimeInterval) -> Frame {
        let length = Self.phaseLength * Double(phaseCount)
        var loop = time.isFinite ? time.truncatingRemainder(dividingBy: length) : 0
        if loop < 0 { loop += length }
        let phase = min(phaseCount - 1, Int(loop / Self.phaseLength))
        let local = loop - Double(phase) * Self.phaseLength
        var result = Frame(phase: phase)
        result.glowTravel = CGFloat(Self.easeOut(local / 0.45))
        // The mouse turns to the view the phase's parts light in, from the one before's
        // (the loop's very first phase has none before it).
        let end = MouseArtworkTurn.progress(showing: viewpoint(ofPhase: phase))
        let isFirstEver = time.isFinite && time >= 0 && time < Self.phaseLength
        result.turn = isFirstEver ? end : MouseArtworkTurn.progress(
            from: MouseArtworkTurn.progress(showing: viewpoint(ofPhase: (phase + phaseCount - 1) % phaseCount)),
            to: end, elapsed: local
        )
        switch phase {
        case 0:
            for click in [0.3, 0.45, 0.6] where local >= click {
                result.wheelTurn += Self.easeOut((local - click) / 0.13)
                result.pulse = max(result.pulse, 1 - Self.clamp01((local - click) / 0.32))
            }
        case 1:
            if local > 0.35 && local < 0.5 { result.pressed.insert(.forward) }
            if local > 0.85 && local < 1.0 { result.pressed.insert(.back) }
        default:
            let out = Self.easeInOut((local - 0.3) / 0.45)
            let back = Self.easeInOut((local - 1.4) / 0.4)
            result.slide = -Self.slide * CGFloat(out - back)
            result.arrow = CGFloat(Self.clamp01((local - 0.3) / 0.2) - Self.clamp01((local - 1.35) / 0.2))
        }
        return result
    }

    /// Everything lit, nothing moving.
    var stillFrame: Frame {
        var result = Frame(phase: nil)
        result.arrow = model.has(.gesture) ? 1 : 0
        return result
    }

    override func show(time: TimeInterval) {
        apply(frame(at: time))
    }

    override func showStill() {
        apply(stillFrame)
    }

    private func apply(_ next: Frame) {
        if notifiedPhase != .some(next.phase) {
            notifiedPhase = .some(next.phase)
            onPhaseChange?(next.phase)
        }
        guard next != shownFrame else { return }
        shownFrame = next
        needsDisplay = true
    }

    private func glowCentre(ofPhase phase: Int?, drawing: WelcomeGuideMouseDrawing) -> NSPoint {
        guard let phase else { return drawing.point(NSPoint(x: 44, y: 54)) }
        return drawing.centre(of: parts(ofPhase: phase)) ?? drawing.point(NSPoint(x: 44, y: 54))
    }

    override func draw(_ dirtyRect: NSRect) {
        // Everything stays inside the card: the glow round the wheel would reach above it.
        let radius = WelcomeGuideLayout.pictureCornerRadius - 1
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: radius, yRadius: radius).addClip()
        let current = shownFrame
        var drawing = WelcomeGuideMouseDrawing(model: model, unit: Self.unit, origin: Self.mouseOrigin)
        drawing.origin.x += current.slide
        drawing.turn = current.turn
        // The still of a mouse drawn in two views: both, side by side.
        let showsBothViews = current.phase == nil && model.hasSideView

        // The soft accent glow behind the lit part; it travels to the next one.
        let to = glowCentre(ofPhase: current.phase, drawing: drawing)
        var centre = to
        if let phase = current.phase, current.glowTravel < 1 {
            let previous = (phase + phaseCount - 1) % phaseCount
            let from = glowCentre(ofPhase: previous, drawing: WelcomeGuideMouseDrawing(model: model, unit: Self.unit, origin: Self.mouseOrigin))
            centre = NSPoint(
                x: from.x + (to.x - from.x) * current.glowTravel,
                y: from.y + (to.y - from.y) * current.glowTravel
            )
        }
        let accent = NSColor.controlAccentColor
        let glow = NSGradient(colors: [accent.withAlphaComponent(0.28), accent.withAlphaComponent(0)])
        glow?.draw(fromCenter: centre, radius: 0, toCenter: centre, radius: Self.glowRadius, options: [])

        if let phase = current.phase {
            drawing.lit = Set(parts(ofPhase: phase))
        } else {
            drawing.lit = [.wheel, .forward, .back, .gesture]
        }
        drawing.pressed = current.pressed
        drawing.wheelTurn = current.wheelTurn
        drawing.pulse = current.pulse
        if showsBothViews {
            var side = drawing
            side.turn = 1
            side.origin.x += Self.stillSpread.side
            side.draw()
            drawing.origin.x -= Self.stillSpread.above
        }
        drawing.draw()

        // The gesture: an arrow the way the mouse moves.
        if current.arrow > 0, model.has(.gesture) {
            let left = drawing.point(arrowAnchor(in: drawing.turn >= 0.5 ? .thumbSide : .above))
            let arrow = NSBezierPath()
            let start = NSPoint(x: left.x + 6, y: left.y)
            let end = NSPoint(x: left.x - 16, y: left.y)
            arrow.move(to: start)
            arrow.line(to: end)
            arrow.move(to: NSPoint(x: end.x + 7, y: end.y - 7))
            arrow.line(to: end)
            arrow.line(to: NSPoint(x: end.x + 7, y: end.y + 7))
            arrow.lineWidth = 2
            arrow.lineCapStyle = .round
            arrow.lineJoinStyle = .round
            accent.withAlphaComponent(current.arrow).setStroke()
            arrow.stroke()
        }
    }
}

/// One of the three features under the title: a small mouse with the part lit, a name and
/// one line. The one whose part the picture lights gets a soft box.
final class WelcomeGuideFeatureView: WelcomeGuideFlippedView {

    enum Kind {
        case scrolling, buttons, gestures

        var titleKey: String {
            switch self {
            case .scrolling: return "intro-feature-scrolling"
            case .buttons: return "intro-feature-buttons"
            case .gestures: return "intro-feature-gestures"
            }
        }

        var detailKey: String {
            return titleKey + "-detail"
        }
    }

    /// Three of them and two gaps are as wide as the picture (552 pt).
    static let width: CGFloat = 176
    static let spacing: CGFloat = 12
    /// Wider than the mouse: room for the gesture arrow on its left.
    static let glyphSize = NSSize(width: 38, height: 38)

    let kind: Kind
    private(set) var titleLabel: NSTextField!
    private(set) var detailLabel: NSTextField!
    private let glyph = WelcomeGuideFeatureGlyph()

    var model: MouseArtworkModel = .generic {
        didSet {
            glyph.model = model
        }
    }

    var isHighlighted = false {
        didSet {
            if isHighlighted != oldValue { needsDisplay = true }
        }
    }

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        glyph.kind = kind
        glyph.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: WelcomeGuideText.localized(kind.titleKey))
        title.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        title.textColor = .labelColor
        title.alignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false
        let detail = WelcomeGuideText.makeText(
            WelcomeGuideText.localized(kind.detailKey), font: PreferencesForm.hintFont, width: Self.width - 20
        )
        titleLabel = title
        detailLabel = detail

        addSubview(glyph)
        addSubview(title)
        addSubview(detail)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.width),
            glyph.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            glyph.centerXAnchor.constraint(equalTo: centerXAnchor),
            glyph.widthAnchor.constraint(equalToConstant: Self.glyphSize.width),
            glyph.heightAnchor.constraint(equalToConstant: Self.glyphSize.height),
            title.topAnchor.constraint(equalTo: glyph.bottomAnchor, constant: 6),
            title.centerXAnchor.constraint(equalTo: centerXAnchor),
            title.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -20),
            detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
            detail.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            detail.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            // As tall as the tallest of the three (the row makes them equal), the text at the top.
            detail.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -11),
        ])
        let compact = heightAnchor.constraint(equalToConstant: 0)
        compact.priority = .defaultLow
        compact.isActive = true
        // Read as one: "Smooth scrolling, Each wheel click glides."
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(title.stringValue + ", " + detail.stringValue)
        title.setAccessibilityElement(false)
        detail.setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        fatalError("built in code")
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isHighlighted else { return }
        let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        WelcomeGuidePalette.box.setFill()
        box.fill()
        // The edge of the feel cards: it carries the box under Increase Contrast.
        WelcomeGuidePalette.boxEdge.setStroke()
        box.lineWidth = 1
        box.stroke()
    }
}

/// The small mouse of a feature, about 38 pt tall, in the lines of the Buttons pane's
/// row pictures.
final class WelcomeGuideFeatureGlyph: WelcomeGuideFlippedView {

    var kind: WelcomeGuideFeatureView.Kind = .scrolling {
        didSet { needsDisplay = true }
    }
    var model: MouseArtworkModel = .generic {
        didSet { if model != oldValue { needsDisplay = true } }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        fatalError("built in code")
    }

    override func draw(_ dirtyRect: NSRect) {
        let grid = MouseArtworkShapes.grid
        let unit = bounds.height / grid.height
        var ink = MouseArtworkInk.card
        ink.outlineWidth = 1.1
        ink.seamWidth = 0.7
        ink.partEdgeWidth = 0.7
        ink.ridges = false
        ink.shadow = false
        ink.drawsWell = false

        let lit: MouseArtworkPart
        switch kind {
        case .scrolling: lit = .wheel
        case .buttons: lit = .back
        // A mouse without a gesture button: an arrow the way the mouse moves (as the big
        // picture draws it), not the whole outline lit.
        case .gestures: lit = model.has(.gesture) ? .gesture : .body
        }
        // In the view its part lights in: a mouse drawn in two views lies across for the
        // parts of its thumb side.
        let shapes = MouseArtworkShapes(model: model, schematic: true, lighting: lit)

        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: (bounds.width - grid.width * unit) / 2, yBy: 0)
        transform.scale(by: unit)
        transform.concat()
        MouseArtworkPainter.draw(shapes, ink: ink, lit: lit == .body ? nil : lit, unit: unit)
        if kind == .buttons, let forward = shapes.shape(of: .forward) {
            NSColor.controlAccentColor.setFill()
            forward.fill()
        }
        if lit == .body {
            // Grid units: from the mouse's left side, 28 units out, a head 10 units deep.
            let arrow = NSBezierPath()
            arrow.move(to: NSPoint(x: 14, y: 60))
            arrow.line(to: NSPoint(x: -14, y: 60))
            arrow.move(to: NSPoint(x: -4, y: 50))
            arrow.line(to: NSPoint(x: -14, y: 60))
            arrow.line(to: NSPoint(x: -4, y: 70))
            arrow.lineWidth = 2 / unit
            arrow.lineCapStyle = .round
            arrow.lineJoinStyle = .round
            NSColor.controlAccentColor.setStroke()
            arrow.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}
