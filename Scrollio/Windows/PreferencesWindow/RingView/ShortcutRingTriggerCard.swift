//
//  ShortcutRingTriggerCard.swift
//  Scrollio
//  The Shortcut Ring pane's header: two cards side by side, as the Gestures pane has its
//  preview. On the left what the hand does (`ShortcutRingTriggerCard`): the button or key
//  that opens the ring, drawn by the rule the Gestures pane's picture shares
//  (`TriggerPicture`); on the right the ring as it opens (`ShortcutRingPreviewView`, which
//  keeps its hover and its clicks).
//
//  The trigger card is still. It holds the Buttons card's mouse (`ButtonsMouseArtworkView`:
//  the part lit and the drawing turned to the view it lights in, a number badge) and, where
//  the trigger is a key, keys in the Scrolling pane's look; with nothing that opens the
//  ring, the mouse at rest and a dashed blank key under it (nothing in the accent colour:
//  the accent means "yours"). It plays one press, a ring around what is held, when the pane
//  appears, when the trigger changes and when the pointer enters the "Button or key" row,
//  at most every 1.5 s, and none under Reduce Motion. It takes no click and is not read out:
//  the row under it names the trigger.
//

import Cocoa

/// The pane's header: the trigger card and the ring card, each half of the width less the
/// 12 pt between them (the Gestures preview's arithmetic).
final class ShortcutRingHeaderView: NSView {

    static let preferredHeight = ShortcutRingPreviewView.preferredHeight
    static let cardSpacing = GesturePreviewView.cardSpacing

    let triggerCard: ShortcutRingTriggerCard
    let ringCard: ShortcutRingPreviewView

    init(triggerCard: ShortcutRingTriggerCard = ShortcutRingTriggerCard(), ringCard: ShortcutRingPreviewView = ShortcutRingPreviewView()) {
        self.triggerCard = triggerCard
        self.ringCard = ringCard
        super.init(frame: NSRect(x: 0, y: 0, width: 480, height: Self.preferredHeight))
        addSubview(triggerCard)
        addSubview(ringCard)
        layoutCards()
    }

    required init?(coder: NSCoder) {
        fatalError("ShortcutRingHeaderView is built in code")
    }

    override var isFlipped: Bool { return true }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: NSView.noIntrinsicMetric, height: Self.preferredHeight)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutCards()
    }

    override func layout() {
        super.layout()
        layoutCards()
    }

    private func layoutCards() {
        let width = max(0, floor((bounds.width - Self.cardSpacing) / 2))
        triggerCard.frame = NSRect(x: 0, y: 0, width: width, height: bounds.height)
        ringCard.frame = NSRect(x: bounds.width - width, y: 0, width: width, height: bounds.height)
    }
}

/// The left card: the trigger that opens the ring on the shown mouse, or its keys.
final class ShortcutRingTriggerCard: NSView {

    static let cornerRadius = ShortcutRingPreviewView.cornerRadius
    /// A key alone: the Scrolling pane's key.
    static let keyFaceHeight: CGFloat = 34
    /// The keys held with a button, and the blank key of the default picture.
    static let smallKeyFaceHeight: CGFloat = 24
    /// Between two keys at 34 pt; smaller keys in proportion.
    static let keySpacing: CGFloat = 6
    /// Between the mouse's body and the keys under it.
    static let keysGap: CGFloat = 8
    /// The widest row of keys (16 pt in from each side of the card): a longer row is drawn
    /// smaller.
    static let keysMaxWidth: CGFloat = 202
    /// The app's chip, from the card's top left corner.
    static let chipInset: CGFloat = 8
    /// The badge of a button the drawing lacks: the Buttons card's number badge's height.
    static let badgeHeight = ButtonsMouseNumberBadge.height

    /// The press: a ring whose line widens from 3 to 15 pt while it fades from 0.45 over
    /// 0.4 s.
    static let pressDuration: CFTimeInterval = 0.4
    static let pressLineWidth: (from: CGFloat, to: CGFloat) = (3, 15)
    static let pressOpacity: Float = 0.45
    /// At most one press in this time.
    static let pulseInterval: TimeInterval = 1.5

    /// What opens the ring; the picture follows it (and presses once while shown).
    var source = TriggerPictureSource.none {
        didSet {
            guard source != oldValue else { return }
            let before = picture
            resolve()
            if picture != before {
                pulse()
            }
        }
    }

    /// The drawing for the connected mouse: the Gestures preview's seam. Tests and pictures
    /// replace it; call `reloadMouse()` after. The card follows a mouse coming and going.
    var mouseSource: () -> MouseArtworkModel = {
        MouseArtworkModel.model(forDeviceName: MousePaneModel.shownMouse()?.deviceName)
    }

    /// Reduce Motion in System Settings › Accessibility: no press, and the light and the
    /// turn change at once.
    var prefersReducedMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// The time the presses are spaced by.
    var clock: () -> TimeInterval = { CACurrentMediaTime() }

    private(set) var picture = TriggerPicture.none
    let artwork = ButtonsMouseArtworkView()
    /// The keys under the mouse or alone, left to right.
    private(set) var caps: [TriggerKeyCap] = []
    let chip = TriggerAppChip()
    /// The badge of a part this drawing lacks (`.notDrawn`); a number is the mouse's own badge.
    let partBadge = TriggerPartBadge()
    /// The press while it plays.
    private(set) var pressLayer: CAShapeLayer?
    /// When the last press was asked for.
    private var lastPulse: TimeInterval?
    /// A press that waits for the drawing to turn.
    private var waitingPress: DispatchWorkItem?

    /// The keys are drawn without the mouse.
    var showsKeysOnly: Bool {
        if case .keys? = picture.hold { return true }
        return false
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUp()
    }

    required init?(coder: NSCoder) {
        fatalError("ShortcutRingTriggerCard is built in code")
    }

    deinit {
        waitingPress?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    private func setUp() {
        // A layer of its own for the press.
        wantsLayer = true
        addSubview(artwork)
        partBadge.alphaValue = 0
        addSubview(partBadge)
        addSubview(chip)
        // A picture only: the row under it names the trigger.
        setAccessibilityElement(false)
        for name in [LogiCenter.sessionChanged, LogiCenter.mouseStateChanged] {
            NotificationCenter.default.addObserver(self, selector: #selector(reloadMouse), name: name, object: nil)
        }
        artwork.model = mouseSource()
        resolve()
    }

    override var isFlipped: Bool { return true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutContent()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            endPress()
        }
    }

    /// Draws the mouse `mouseSource` gives now, the trigger on it.
    @objc func reloadMouse() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.reloadMouse() }
            return
        }
        let model = mouseSource()
        // (The Logitech notifications come for a battery level too: nothing to redraw then.)
        guard artwork.model != model else { return }
        artwork.model = model
        resolve()
    }

    // MARK: - The picture

    private var animates: Bool {
        return window != nil && !prefersReducedMotion()
    }

    /// `source` on the shown mouse, into the views.
    private func resolve() {
        let new = TriggerPicture.make(source, mouse: artwork.model)
        let animated = animates
        picture = new
        let hold = new.hold
        switch hold {
        case .part(let part)?:
            artwork.setEmphasis(part, animated: animated)
        default:
            artwork.setEmphasis(nil, animated: animated)
        }
        if case .number(let number)? = hold {
            artwork.setNumber(number, animated: animated)
        } else {
            artwork.setNumber(nil, animated: animated)
        }
        if case .notDrawn? = hold, let hold {
            partBadge.hold = hold
            fade(partBadge, to: 1, animated: animated)
        } else {
            fade(partBadge, to: 0, animated: animated)
        }
        artwork.isHidden = showsKeysOnly
        chip.path = new.appPath
        makeCaps()
        layoutContent()
    }

    private func fade(_ view: NSView, to alpha: CGFloat, animated: Bool) {
        guard animated else {
            view.alphaValue = alpha
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = ButtonsMouseArtworkView.fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            view.animator().alphaValue = alpha
        }
    }

    /// The keys of the picture: a key's own at 34 pt (smaller when the row is too long), a
    /// button's modifiers at 24 pt, or one blank 24 pt key with nothing set. All pressed but
    /// the blank one.
    private func makeCaps() {
        let labels: [String]
        let preferred: CGFloat
        let placeholder: Bool
        switch picture.hold {
        case .keys(let keys)?:
            labels = keys
            preferred = Self.keyFaceHeight
            placeholder = false
        case nil:
            labels = [""]
            preferred = Self.smallKeyFaceHeight
            placeholder = true
        default:
            labels = picture.modifiers
            preferred = Self.smallKeyFaceHeight
            placeholder = false
        }
        let faceHeight = Self.faceHeight(fitting: labels, preferred: preferred)
        let same = caps.map(\.label) == labels && caps.first?.faceHeight == faceHeight
            && caps.first?.isPlaceholder == placeholder
        guard !same else { return }
        caps.forEach { $0.removeFromSuperview() }
        caps = labels.map { label in
            let cap = TriggerKeyCap(label: label, faceHeight: faceHeight)
            cap.isPlaceholder = placeholder
            cap.depth = placeholder ? 0 : 1
            addSubview(cap, positioned: .below, relativeTo: chip)
            return cap
        }
    }

    /// The face height at which `labels` fit `keysMaxWidth` in a row: `preferred` when they
    /// do, else as much smaller as needed.
    static func faceHeight(fitting labels: [String], preferred: CGFloat) -> CGFloat {
        var height = preferred
        let width = rowWidth(labels, faceHeight: height)
        guard width > keysMaxWidth else { return preferred }
        height = (preferred * keysMaxWidth / width).rounded(.down)
        while height > 12 && rowWidth(labels, faceHeight: height) > keysMaxWidth {
            height -= 1
        }
        return height
    }

    static func spacing(faceHeight: CGFloat) -> CGFloat {
        return (keySpacing * faceHeight / keyFaceHeight).rounded()
    }

    /// The faces of `labels` side by side, without the views' margins.
    static func rowWidth(_ labels: [String], faceHeight: CGFloat) -> CGFloat {
        let faces = labels.reduce(0) { $0 + TriggerKeyCap.faceWidth(label: $1, faceHeight: faceHeight) }
        return faces + CGFloat(max(0, labels.count - 1)) * spacing(faceHeight: faceHeight)
    }

    // MARK: - Layout

    /// The mouse in the middle; with keys under it, the mouse, the gap and the keys in the
    /// middle together; keys alone in the middle. The chip in the top left corner.
    private func layoutContent() {
        let size = bounds.size
        chip.frame = NSRect(x: Self.chipInset, y: Self.chipInset, width: TriggerAppChip.side, height: TriggerAppChip.side)
        let mouse = ButtonsMouseArtworkView.size
        let mouseX = ((size.width - mouse.width) / 2).rounded()
        guard let first = caps.first else {
            artwork.frame = NSRect(origin: NSPoint(x: mouseX, y: ((size.height - mouse.height) / 2).rounded()), size: mouse)
            placePartBadge()
            return
        }
        let faceHeight = first.faceHeight
        let keysHeight = faceHeight + TriggerKeyCap.travel(faceHeight: faceHeight)
        let facesTop: CGFloat
        if showsKeysOnly {
            facesTop = ((size.height - keysHeight) / 2).rounded()
        } else {
            // The body as it is drawn in the view shown: from the side the mouse lies
            // across, lower than from above.
            let body = bodyExtent
            let top = ((size.height - (body.height + Self.keysGap + keysHeight)) / 2).rounded()
            artwork.frame = NSRect(origin: NSPoint(x: mouseX, y: top - body.minY), size: mouse)
            facesTop = top + body.height + Self.keysGap
        }
        let spacing = Self.spacing(faceHeight: faceHeight)
        var x = ((size.width - Self.rowWidth(caps.map(\.label), faceHeight: faceHeight)) / 2).rounded()
        for cap in caps {
            let capSize = TriggerKeyCap.size(label: cap.label, faceHeight: faceHeight)
            cap.frame = NSRect(x: x - TriggerKeyCap.margin, y: facesTop - TriggerKeyCap.margin, width: capSize.width, height: capSize.height)
            x += capSize.width - 2 * TriggerKeyCap.margin + spacing
        }
        placePartBadge()
    }

    /// Where the drawn body is, up and down, in the mouse's view, in the view it shows (or
    /// turns to): from above the drawing's whole grid, from the side less.
    var bodyExtent: (minY: CGFloat, height: CGFloat) {
        let grid = (minY: MouseArtworkView.margin, height: MouseArtworkShapes.grid.height * MouseArtworkView.unit)
        let shapes = MouseArtworkShapes(model: artwork.model, viewpoint: artwork.base.viewpoint)
        guard let body = shapes.shape(of: .body) else { return grid }
        body.transform(using: MouseArtworkView.placement)
        let bounds = body.bounds
        return bounds.isEmpty ? grid : (bounds.minY, bounds.height)
    }

    /// The badge where the Buttons card puts its number: on the body's right edge, low.
    private func placePartBadge() {
        let size = TriggerBadge.size(for: partBadge.hold, height: Self.badgeHeight)
        let centre = artwork.badgeCentre
        partBadge.frame = NSRect(
            x: artwork.frame.minX + centre.x - size.width / 2, y: artwork.frame.minY + centre.y - size.height / 2,
            width: size.width, height: size.height
        )
    }

    // MARK: - The press

    /// One press: a ring round what is held, which opens up and fades. At most one every
    /// `pulseInterval`; none under Reduce Motion, none off screen and none for the default
    /// picture (nothing is held). While the drawing turns, it waits for the turn.
    func pulse() {
        guard window != nil, !prefersReducedMotion(), picture.hold != nil else { return }
        let now = clock()
        if let lastPulse, now - lastPulse < Self.pulseInterval { return }
        lastPulse = now
        waitingPress?.cancel()
        waitingPress = nil
        guard artwork.base.isTurning else { return press() }
        let press = DispatchWorkItem { [weak self] in
            self?.waitingPress = nil
            self?.press()
        }
        waitingPress = press
        DispatchQueue.main.asyncAfter(deadline: .now() + MouseArtworkTurn.duration, execute: press)
    }

    private func press() {
        guard window != nil, let host = layer, let target = pressTarget() else { return }
        pressLayer?.removeFromSuperlayer()
        let ring = CAShapeLayer()
        ring.frame = bounds
        ring.path = target.path
        ring.fillColor = nil
        var accent = NSColor.controlAccentColor.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            accent = NSColor.controlAccentColor.cgColor
        }
        ring.strokeColor = accent
        ring.lineJoin = .round
        // The line's inner half is hidden, as the lit part's fill hides it in Gestures, and
        // so are the parts that lie on a part the drawing puts under the others (the thumb
        // panel under Forward, Back, the gesture button and the thumb wheel).
        let mask = CAShapeLayer()
        mask.frame = bounds
        mask.path = CGPath(rect: bounds, transform: nil).subtracting(target.covered)
        ring.mask = mask
        // Where it ends; the animation runs from where it starts.
        ring.lineWidth = Self.pressLineWidth.to
        ring.opacity = 0
        let width = CABasicAnimation(keyPath: "lineWidth")
        width.fromValue = Self.pressLineWidth.from
        width.toValue = Self.pressLineWidth.to
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = Self.pressOpacity
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [width, fade]
        group.duration = Self.pressDuration
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ring.add(group, forKey: "press")
        host.addSublayer(ring)
        pressLayer = ring
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pressDuration) { [weak self, weak ring] in
            guard let self, let ring, self.pressLayer === ring else { return }
            ring.removeFromSuperlayer()
            self.pressLayer = nil
        }
    }

    private func endPress() {
        waitingPress?.cancel()
        waitingPress = nil
        pressLayer?.removeFromSuperlayer()
        pressLayer = nil
    }

    /// What the press rings, in the card's coordinates: the lit part, the badge, or the key
    /// (the last of the row); and what its line stays off. nil: nothing is held.
    func pressTarget() -> (path: CGPath, covered: CGPath)? {
        guard let hold = picture.hold else { return nil }
        let origin = AffineTransform(translationByX: artwork.frame.minX, byY: artwork.frame.minY)
        switch hold {
        case .part(let part):
            let model = artwork.model
            guard let shape = MouseArtworkView.shape(of: part.artworkPart, model: model) else { return nil }
            shape.transform(using: origin)
            var covered = shape.cgPath
            let shapes = MouseArtworkShapes(model: model, lighting: part.artworkPart)
            if shapes.views?.restPart == part.artworkPart {
                for other in MouseArtworkPart.allCases where other != part.artworkPart && other != .body {
                    guard let path = shapes.shape(of: other) else { continue }
                    path.transform(using: MouseArtworkView.placement)
                    path.transform(using: origin)
                    covered = covered.union(path.cgPath)
                }
            }
            return (shape.cgPath, covered)
        case .number:
            let rect = artwork.badge.frame.offsetBy(dx: artwork.frame.minX, dy: artwork.frame.minY)
            let path = Self.capsule(rect)
            return (path, path)
        case .notDrawn:
            let path = Self.capsule(partBadge.frame)
            return (path, path)
        case .keys:
            guard let cap = caps.last else { return nil }
            let face = cap.faceRect
                .offsetBy(dx: cap.frame.minX, dy: cap.frame.minY + TriggerKeyCap.travel(faceHeight: cap.faceHeight) * cap.depth)
            let radius = TriggerKeyCap.cornerRadius(faceHeight: cap.faceHeight)
            let path = CGPath(roundedRect: face, cornerWidth: radius, cornerHeight: radius, transform: nil)
            return (path, path)
        }
    }

    private static func capsule(_ rect: NSRect) -> CGPath {
        let radius = min(rect.width, rect.height) / 2
        return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let card = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: Self.cornerRadius, yRadius: Self.cornerRadius
        )
        ScrollPreviewPalette.cardFill.setFill()
        card.fill()
        ScrollPreviewPalette.cardEdge.setStroke()
        card.lineWidth = 1
        card.stroke()
    }
}

/// The accent badge of a button this drawing lacks (`TriggerBadge`, `.notDrawn`), by the
/// mouse where the Buttons card puts a number. A picture only.
final class TriggerPartBadge: NSView {

    var hold: TriggerPicture.Hold = .notDrawn(nil) {
        didSet {
            if hold != oldValue { needsDisplay = true }
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        fatalError("TriggerPartBadge is built in code")
    }

    override var isFlipped: Bool { return true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        TriggerBadge.draw(hold, in: bounds)
    }
}
