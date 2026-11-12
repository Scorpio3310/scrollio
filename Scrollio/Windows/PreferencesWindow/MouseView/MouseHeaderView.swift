//
//  MouseHeaderView.swift
//  Mos
//  The card at the top of the Mouse tab: on the left the mouse seen from above, on the
//  right its name, that it is connected and its battery. The part of the mouse the setting
//  under the pointer (or with the keyboard focus) is about lights up in the accent colour;
//  for a part on the thumb side of a mouse drawn in two views, the drawing turns to it.
//  The drawing is the connected mouse's (MouseArtworkModel); without a Logitech mouse the
//  card shows a plain mouse and says that the app works with any mouse. The card has the
//  look of the Scrolling tab's preview cards (ScrollPreviewPalette).
//

import Cocoa

final class MouseHeaderView: NSView {

    static let preferredHeight: CGFloat = 150
    static let cornerRadius: CGFloat = 10
    /// The mouse is centred in this much of the card's left side; the text starts after it.
    static let artworkColumnWidth: CGFloat = 170
    /// Right of the text.
    static let textTrailingInset: CGFloat = 20
    /// The line under the name wraps; more than this many lines are cut off.
    static let detailMaximumLines = 3

    static var nameFont: NSFont {
        return NSFont.systemFont(ofSize: 17, weight: .semibold)
    }

    static var detailFont: NSFont {
        return NSFont.systemFont(ofSize: NSFont.systemFontSize)
    }

    var content = MousePaneModel.Header(title: "", subtitle: nil, battery: nil, isConnected: false, model: .generic) {
        didSet {
            if content != oldValue { applyContent() }
        }
    }

    /// The part that is lit up; nil: none.
    var emphasis: MousePart? {
        didSet {
            guard emphasis != oldValue else { return }
            artwork.setEmphasis(emphasis?.artworkPart, animated: window != nil && !prefersReducedMotion())
        }
    }

    /// Reduce Motion in System Settings › Accessibility: the light then switches without fading.
    var prefersReducedMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    let artwork = MouseArtworkView()
    let nameLabel = NSTextField(labelWithString: "")
    let statusLabel = NSTextField(wrappingLabelWithString: "")
    let batteryIcon = NSImageView()
    let batteryLabel = NSTextField(labelWithString: "")
    private let batteryLine = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        translatesAutoresizingMaskIntoConstraints = false
        artwork.translatesAutoresizingMaskIntoConstraints = false
        addSubview(artwork)

        nameLabel.font = Self.nameFont
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        statusLabel.font = Self.detailFont
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.isSelectable = false
        statusLabel.maximumNumberOfLines = Self.detailMaximumLines
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.cell?.truncatesLastVisibleLine = true
        batteryLabel.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        batteryLabel.textColor = .secondaryLabelColor
        for label in [nameLabel, statusLabel, batteryLabel] {
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }

        batteryIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: NSFont.systemFontSize, weight: .regular)
        batteryIcon.imageScaling = .scaleNone
        batteryIcon.setContentHuggingPriority(.required, for: .horizontal)
        // The text says it; the picture is read out with it.
        batteryIcon.setAccessibilityElement(false)
        batteryLine.orientation = .horizontal
        batteryLine.alignment = .centerY
        batteryLine.spacing = 5
        batteryLine.addArrangedSubview(batteryIcon)
        batteryLine.addArrangedSubview(batteryLabel)

        let text = NSStackView(views: [nameLabel, statusLabel, batteryLine])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 3
        text.setCustomSpacing(4, after: nameLabel)
        text.detachesHiddenViews = true
        text.translatesAutoresizingMaskIntoConstraints = false
        addSubview(text)

        let artworkSize = MouseArtworkView.size
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.preferredHeight),
            artwork.widthAnchor.constraint(equalToConstant: artworkSize.width),
            artwork.heightAnchor.constraint(equalToConstant: artworkSize.height),
            artwork.centerXAnchor.constraint(equalTo: leadingAnchor, constant: Self.artworkColumnWidth / 2),
            artwork.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.artworkColumnWidth),
            text.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Self.textTrailingInset),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        applyContent()
    }

    override var isFlipped: Bool { return true }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: NSView.noIntrinsicMetric, height: Self.preferredHeight)
    }

    /// The text column ends `textTrailingInset` before the card's edge: the line under the
    /// name wraps there.
    override func layout() {
        let width = max(0, bounds.width - Self.artworkColumnWidth - Self.textTrailingInset)
        if statusLabel.preferredMaxLayoutWidth != width {
            statusLabel.preferredMaxLayoutWidth = width
        }
        super.layout()
    }

    private func applyContent() {
        nameLabel.stringValue = content.title
        statusLabel.stringValue = content.subtitle ?? ""
        statusLabel.isHidden = content.subtitle == nil
        artwork.model = content.model
        if let battery = content.battery {
            batteryLine.isHidden = false
            batteryLabel.stringValue = battery.text
            batteryLabel.setAccessibilityLabel(battery.accessibilityLabel)
            batteryIcon.image = NSImage(systemSymbolName: battery.symbolName, accessibilityDescription: nil)
            let tint: NSColor = battery.isLow ? .systemRed : .secondaryLabelColor
            batteryIcon.contentTintColor = tint
            batteryLabel.textColor = battery.isLow ? .systemRed : .secondaryLabelColor
        } else {
            batteryLine.isHidden = true
            batteryLabel.stringValue = ""
            batteryIcon.image = nil
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let card = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            xRadius: Self.cornerRadius, yRadius: Self.cornerRadius
        )
        ScrollPreviewPalette.cardFill.setFill()
        card.fill()
        ScrollPreviewPalette.cardEdge.setStroke()
        card.lineWidth = 1
        card.stroke()
    }
}

// MARK: - The mouse

/// The connected mouse in line art (MouseArtwork.swift: one drawing per model), seen from
/// above. Each part that can light up has a layer of its own above the drawing, faded in
/// and out. A mouse drawn in two views turns to the view from the thumb side while a part
/// that lights there is lit, and back from above when another part or none is.
final class MouseArtworkView: NSView {

    /// Which mouse is drawn; the lit part stays lit in the new drawing, if it has it.
    var model: MouseArtworkModel = .generic {
        didSet {
            guard model != oldValue else { return }
            for highlight in highlights.values {
                highlight.model = model
            }
            show(model.viewpoint(lighting: emphasis), animated: false)
            needsDisplay = true
        }
    }

    /// The drawing's grid is drawn this many points per unit: the body 111 points tall.
    static let unit: CGFloat = 111 / MouseArtworkShapes.grid.height
    /// Room around the drawing for its shadow and the glow of a lit part.
    static let margin: CGFloat = 9
    /// Wide enough for the view from the side, which lies across (MouseArtworkShapes.canvas);
    /// a whole, even number of points, so the grid's middle falls where it does in a
    /// narrower view centred on the same point.
    static let size = NSSize(
        width: 2 * (MouseArtworkShapes.canvas.width * unit / 2 + margin).rounded(.up),
        height: MouseArtworkShapes.grid.height * unit + 2 * margin
    )
    static let fadeDuration: TimeInterval = 0.18

    private(set) var emphasis: MouseArtworkPart?
    private(set) var highlights: [MouseArtworkPart: MouseArtworkHighlight] = [:]

    /// The view that shows, or the one the drawing is turning to.
    private(set) var viewpoint: MouseArtworkViewpoint = .above
    /// How far the drawing has turned: 0 from above, 1 from the thumb side (MouseArtworkTurn).
    private(set) var turn: CGFloat = 0 {
        didSet {
            guard turn != oldValue else { return }
            for highlight in highlights.values {
                highlight.turn = turn
            }
            needsDisplay = true
        }
    }
    /// A turn that is under way: where it began, where it ends, and when it began.
    private var turning: (from: CGFloat, to: CGFloat, since: TimeInterval)?
    private var turnTimer: Timer?
    /// The time a turn runs by.
    var clock: () -> TimeInterval = { CACurrentMediaTime() }

    var isTurning: Bool {
        return turning != nil
    }

    init() {
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        for part in MouseArtworkPart.allCases {
            let highlight = MouseArtworkHighlight(part: part, model: model)
            highlight.frame = bounds
            highlight.autoresizingMask = [.width, .height]
            highlight.alphaValue = 0
            addSubview(highlight)
            highlights[part] = highlight
        }
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        fatalError("MouseArtworkView is built in code")
    }

    deinit {
        turnTimer?.invalidate()
    }

    override var isFlipped: Bool { return true }

    override var intrinsicContentSize: NSSize { return Self.size }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    /// A turn does not go on off screen: the drawing is then where it was turning to.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            show(viewpoint, animated: false)
        }
    }

    /// Lights `part` up and puts out the others, and turns the drawing to the view `part`
    /// lights in (from above for none). A part this mouse does not have lights nothing.
    func setEmphasis(_ part: MouseArtworkPart?, animated: Bool) {
        emphasis = part
        show(model.viewpoint(lighting: part), animated: animated)
        let change = {
            for (candidate, highlight) in self.highlights {
                let alpha: CGFloat = candidate == part ? 1 : 0
                if animated {
                    highlight.animator().alphaValue = alpha
                } else {
                    highlight.alphaValue = alpha
                }
            }
        }
        guard animated else { return change() }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            change()
        }
    }

    // MARK: Turning

    /// Shows the drawing from `target`: at once, or turning there (MouseArtworkTurn).
    private func show(_ target: MouseArtworkViewpoint, animated: Bool) {
        viewpoint = target
        let end = MouseArtworkTurn.progress(showing: target)
        guard animated, turn != end else {
            turning = nil
            turnTimer?.invalidate()
            turnTimer = nil
            turn = end
            return
        }
        guard turning?.to != end else { return }
        turning = (turn, end, clock())
        guard turnTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            self?.advanceTurn()
        }
        RunLoop.main.add(timer, forMode: .common)
        turnTimer = timer
    }

    /// One step of a turn that is under way, by the clock.
    func advanceTurn() {
        guard let turning else { return }
        turn = MouseArtworkTurn.progress(from: turning.from, to: turning.to, elapsed: clock() - turning.since)
        if turn == turning.to {
            self.turning = nil
            turnTimer?.invalidate()
            turnTimer = nil
        }
    }

    // MARK: Geometry (view coordinates)

    /// From the drawing's grid to the view: the grid centred across, `margin` from the top.
    static var placement: AffineTransform {
        let grid = MouseArtworkShapes.grid
        var transform = AffineTransform(translationByX: (size.width - grid.width * unit) / 2, byY: margin)
        transform.scale(unit)
        return transform
    }

    /// A point of the grid in the view.
    static func point(_ gridPoint: NSPoint) -> NSPoint {
        return placement.transform(gridPoint)
    }

    /// The shape of `part` in the view, in the drawing that lights it; nil when `model`
    /// does not have it.
    static func shape(of part: MouseArtworkPart, model: MouseArtworkModel) -> NSBezierPath? {
        guard let path = MouseArtworkShapes(model: model, lighting: part).shape(of: part) else { return nil }
        path.transform(using: placement)
        return path
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        for face in MouseArtworkTurn.faces(at: turn) where model.viewpoints.contains(face.viewpoint) {
            MouseArtworkTurn.draw(face, placement: Self.placement) {
                MouseArtworkPainter.draw(
                    MouseArtworkShapes(model: model, viewpoint: face.viewpoint), ink: .card, unit: Self.unit
                )
            }
        }
    }
}

/// One part of the mouse in the accent colour, with a glow. Lies on top of the drawing, in
/// the view its part lights in, and turns with it.
final class MouseArtworkHighlight: NSView {

    let part: MouseArtworkPart
    var model: MouseArtworkModel {
        didSet {
            if model != oldValue { needsDisplay = true }
        }
    }
    /// How far the drawing has turned (MouseArtworkView.turn).
    var turn: CGFloat = 0 {
        didSet {
            if turn != oldValue { needsDisplay = true }
        }
    }

    init(part: MouseArtworkPart, model: MouseArtworkModel) {
        self.part = part
        self.model = model
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("MouseArtworkHighlight is built in code")
    }

    override var isFlipped: Bool { return true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let viewpoint = model.viewpoint(lighting: part)
        guard let face = MouseArtworkTurn.face(of: viewpoint, at: turn) else { return }
        MouseArtworkTurn.draw(face, placement: MouseArtworkView.placement) {
            MouseArtworkPainter.drawHighlight(
                part, shapes: MouseArtworkShapes(model: model, viewpoint: viewpoint), unit: MouseArtworkView.unit
            )
        }
    }
}

extension MousePart {
    /// The part of the drawing a setting about this part lights.
    var artworkPart: MouseArtworkPart {
        switch self {
        case .body: return .body
        case .wheel: return .wheel
        case .thumbPanel: return .thumbPanel
        }
    }
}
