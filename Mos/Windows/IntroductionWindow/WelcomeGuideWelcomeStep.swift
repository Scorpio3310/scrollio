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
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false

        let (view, stack) = WelcomeGuideText.makeContent([title, text, row], top: 44)
        stack.setCustomSpacing(WelcomeGuideLayout.titleToText, after: title)
        stack.setCustomSpacing(22, after: text)
        content = view

        // The app icon sits on the lower edge of the picture.
        let icon = NSImageView(frame: NSRect(x: (WelcomeGuideLayout.windowSize.width - 60) / 2, y: -30, width: 60, height: 60))
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

    /// The moment `time` seconds into the loop.
    func frame(at time: TimeInterval) -> Frame {
        let length = Self.phaseLength * Double(phaseCount)
        var loop = time.isFinite ? time.truncatingRemainder(dividingBy: length) : 0
        if loop < 0 { loop += length }
        let phase = min(phaseCount - 1, Int(loop / Self.phaseLength))
        let local = loop - Double(phase) * Self.phaseLength
        var result = Frame(phase: phase)
        result.glowTravel = CGFloat(Self.easeOut(local / 0.45))
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
        let current = shownFrame
        var drawing = WelcomeGuideMouseDrawing(model: model, unit: Self.unit, origin: Self.mouseOrigin)
        drawing.origin.x += current.slide

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
        drawing.draw()

        // The gesture: an arrow the way the mouse moves.
        if current.arrow > 0, model.has(.gesture) {
            let left = drawing.point(NSPoint(x: 0, y: 49))
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

    static let width: CGFloat = 172
    static let glyphSize = NSSize(width: 28, height: 38)

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
            detail.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -11),
        ])
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
        WelcomeGuidePalette.box.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
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
        let shapes = MouseArtworkShapes(model: model, schematic: true)
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
        case .gestures: lit = model.has(.gesture) ? .gesture : .body
        }

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
            let outline = shapes.outline()
            outline.lineWidth = 1.6 / unit
            NSColor.controlAccentColor.setStroke()
            outline.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}
