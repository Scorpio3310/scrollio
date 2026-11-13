//
//  ShortcutRingDropsView.swift
//  Scrollio
//
//  The ring's nine drops as views (`ShortcutRingDrops` says where each is and how large;
//  the panel asks for one `Frame` after the other while the ring opens or a place lights).
//
//  A drop is a body and what stands in it.
//
//  What stands in it is the same for every material: one small view per drop
//  (`ShortcutRingDropContentView`) that draws a place's symbol, icon or keys, or the hub's
//  name, once per look. While a drop travels its view is only moved and scaled; nothing is
//  drawn again until the lighting changes.
//
//  The bodies are one of three, each on its own and small:
//  - `.drawn`: opaque drops painted by `ShortcutRingArtwork.drawBodies` in one view
//    (`ShortcutRingDrawnBodiesView`). What the pictures of the render tests show exactly.
//  - `.blur` (macOS 14 and 15): ONE `NSVisualEffectView` as large as the ring, whose mask is
//    the nine circles of the moment (`ShortcutRingArtwork.drawMask`), with the drawn view
//    above it for the rims and the lit colour. One material view and not nine: a mask is a
//    small bitmap, drawn again only for the frames of the opening (a third of a second)
//    and of a change of the lit place, and the window server keeps one region to blur.
//  - `.glass` (macOS 26 and later): one `NSGlassEffectView` per drop in one
//    `NSGlassEffectContainerView`, which lets drops flow into each other while they are
//    closer than its `spacing`: as they leave the middle. Each drop's content stands in its
//    glass view's `contentView`, the only place the system promises to keep inside the
//    glass, in the label colour, so it is as legible as the system's own glass buttons
//    over a light or a dark desktop. The lit drop is glass tinted with the accent colour.
//    A glass drop is never faded (only moved and resized, by its frame and corner radius).
//
//  Nobody saw real glass or a real blur when this was written (no screen may be captured
//  by the tests): the glass and the blur follow the SDK's headers and the ring's first
//  version, which showed its disc with the same material.
//

import Cocoa

// MARK: - What stands in a drop

final class ShortcutRingDropContentView: NSView {

    enum Content {
        case nothing
        /// A place's symbol, icon or keys.
        case place(ShortcutRingFace.Place)
        /// The hub's name of the lit action.
        case name(String)
    }

    /// The side of a place's content at rest: room for its symbol when lit.
    static let placeSide = (ShortcutRingGeometry.placeDiameter * ShortcutRingDrops.litContentScale).rounded()
    static let hubSide = ShortcutRingDrops.hubDiameter

    /// The side of the square at rest. The view is as large as it is shown (`put`) and
    /// draws its content at that size.
    let side: CGFloat

    var content = Content.nothing {
        didSet { needsDisplay = true }
    }
    /// How far the place is lit: its content grows a little and takes the lit ink.
    var lit: CGFloat = 0 {
        didSet {
            guard lit != oldValue else { return }
            needsDisplay = true
        }
    }
    /// Inside glass: the system's label colour, which follows what the glass does.
    var usesLabelColour = false
    /// How often a new picture was asked for because the size changed (tests read it).
    private(set) var picturesForANewSize = 0

    init(side: CGFloat) {
        self.side = side
        super.init(frame: NSRect(x: 0, y: 0, width: side, height: side))
        wantsLayer = true
        // Drawn again whenever its look or its size changes (`put` asks for it): a picture
        // drawn small while the drop travels and then stretched stayed soft and a little
        // off its middle until the place was lit, which drew it afresh.
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) {
        fatalError("ShortcutRingDropContentView is built in code")
    }

    override var isOpaque: Bool { return false }

    /// Clicks are the stage's.
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    /// Puts the content with its middle at `middle` of its superview, `grow` times as
    /// large as it is drawn.
    func put(middle: CGPoint, grow: CGFloat, opacity: CGFloat) {
        let shown = side * max(grow, 0.01)
        let target = NSRect(x: middle.x - shown / 2, y: middle.y - shown / 2, width: shown, height: shown)
        if frame != target {
            let resized = frame.size != target.size
            frame = target
            // The picture is made at the size it is shown: never a small one stretched.
            if resized {
                picturesForANewSize += 1
                needsDisplay = true
            }
        }
        let alpha = min(max(opacity, 0), 1)
        if alphaValue != alpha {
            alphaValue = alpha
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let ink = usesLabelColour ? NSColor.labelColor : ShortcutRingArtwork.ink(dark: ShortcutRingArtwork.isDark())
        // Drawn in the square of `side`, at the size the view has now.
        let grow = bounds.width / side
        guard grow > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let shrink = NSAffineTransform()
        shrink.scale(by: grow)
        shrink.concat()
        let middle = CGPoint(x: side / 2, y: side / 2)
        switch content {
        case .nothing:
            break
        case .place(let place):
            ShortcutRingArtwork.drawContent(
                of: place, at: middle,
                scale: 1 + (ShortcutRingDrops.litContentScale - 1) * lit,
                colour: ShortcutRingArtwork.blend(ink, ShortcutRingArtwork.litInk, lit)
            )
        case .name(let title):
            ShortcutRingArtwork.drawTitle(
                title, centre: middle, colour: ink,
                width: ShortcutRingArtwork.titleWidth, pointSize: ShortcutRingArtwork.titleFont.pointSize
            )
        }
    }
}

// MARK: - Bodies: drawn

/// The drops' bodies where the app paints them: opaque drops (`.drawn`), or the rims and
/// the lit colour over the blurred material (`.material`).
final class ShortcutRingDrawnBodiesView: NSView {

    var drops: ShortcutRingDrops.Frame? {
        didSet {
            guard drops != oldValue else { return }
            needsDisplay = true
        }
    }
    var style = ShortcutRingArtwork.Style() {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) {
        fatalError("ShortcutRingDrawnBodiesView is built in code")
    }

    override var isOpaque: Bool { return false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let drops else { return }
        ShortcutRingArtwork.drawBodies(drops, centre: CGPoint(x: bounds.midX, y: bounds.midY), style: style)
    }
}

// MARK: - Bodies: Liquid Glass

/// One glass view per drop, in a container that joins drops that are close.
@available(macOS 26.0, *)
final class ShortcutRingGlassBodies {

    let container = NSGlassEffectContainerView()
    /// The container's content view: the drops stand in it, in the container's coordinates.
    let field = NSView()
    /// The places' drops, then the hub.
    let drops: [NSGlassEffectView]
    /// Each drop's `contentView`: what stands in the drop goes in here.
    let holders: [NSView]
    private var tints: [CGFloat]

    init(count: Int) {
        var drops: [NSGlassEffectView] = []
        var holders: [NSView] = []
        for _ in 0..<count {
            let glass = NSGlassEffectView()
            glass.style = .regular
            let holder = NSView()
            holder.autoresizingMask = [.width, .height]
            glass.contentView = holder
            drops.append(glass)
            holders.append(holder)
        }
        self.drops = drops
        self.holders = holders
        tints = [CGFloat](repeating: 0, count: count)
        // The hub (the last) lies under the places' drops.
        for glass in drops.suffix(1) + drops.dropLast() {
            field.addSubview(glass)
        }
        field.autoresizingMask = [.width, .height]
        container.spacing = ShortcutRingDrops.glassSpacing
        container.contentView = field
    }

    /// Puts each drop in its circle (the container's coordinates) and tints the lit one.
    func show(circles: [CGRect], lit: [CGFloat]) {
        for (index, glass) in drops.enumerated() where circles.indices.contains(index) {
            let circle = circles[index]
            if glass.frame != circle {
                glass.frame = circle
                glass.cornerRadius = circle.width / 2
                holders[index].frame = NSRect(origin: .zero, size: circle.size)
            }
            let amount = lit.indices.contains(index) ? lit[index] : 0
            if tints[index] != amount {
                tints[index] = amount
                glass.tintColor = amount > 0 ? ShortcutRingArtwork.litFill.withAlphaComponent(amount) : nil
            }
        }
    }
}

// MARK: - The nine drops

/// The ring where it stands: a square of `ShortcutRingGeometry.canvasSide` with the ring's
/// middle in its middle.
final class ShortcutRingDropsView: NSView {

    let material: ShortcutRingMaterial
    /// `.blur`: the material, cut to the drops.
    private(set) var blurView: NSVisualEffectView?
    /// `.drawn` and `.blur`: what the app paints of the bodies.
    private(set) var bodiesView: ShortcutRingDrawnBodiesView?
    /// `.glass`: a `ShortcutRingGlassBodies` (the type is newer than the app's oldest system).
    private(set) var glassBodies: AnyObject?
    /// What stands in the places' drops (clockwise from the top), then in the hub.
    let contents: [ShortcutRingDropContentView]
    /// What is shown.
    private(set) var drops: ShortcutRingDrops.Frame?

    var face = ShortcutRingFace(places: []) {
        didSet {
            for (place, content) in zip(face.places, contents) {
                content.content = place.isEmpty ? .nothing : .place(place)
                content.isHidden = place.isEmpty
            }
        }
    }

    /// The name in the hub; nil or empty: none.
    var title: String? {
        didSet {
            guard title != oldValue else { return }
            contents[ShortcutRingDrops.placeCount].content = (title?.isEmpty ?? true) ? .nothing : .name(title ?? "")
        }
    }

    var increasesContrast = false {
        didSet {
            guard increasesContrast != oldValue else { return }
            bodiesView?.style.increasesContrast = increasesContrast
        }
    }

    init(material: ShortcutRingMaterial) {
        self.material = material
        let side = ShortcutRingGeometry.canvasSide
        let frame = NSRect(x: 0, y: 0, width: side, height: side)
        contents = (0..<ShortcutRingDrops.placeCount).map { _ in
            ShortcutRingDropContentView(side: ShortcutRingDropContentView.placeSide)
        } + [ShortcutRingDropContentView(side: ShortcutRingDropContentView.hubSide)]
        super.init(frame: frame)
        wantsLayer = true

        switch material {
        case .glass:
            if #available(macOS 26.0, *) {
                let glass = ShortcutRingGlassBodies(count: contents.count)
                glass.container.frame = frame
                glass.container.autoresizingMask = [.width, .height]
                glass.field.frame = frame
                addSubview(glass.container)
                for (content, holder) in zip(contents, glass.holders) {
                    content.usesLabelColour = true
                    holder.addSubview(content)
                }
                glassBodies = glass
                return
            }
            // Asked for on a system without it (`ShortcutRingAppearance` never does).
            fallthrough
        case .blur:
            let blur = NSVisualEffectView(frame: frame)
            blur.material = .hudWindow
            blur.blendingMode = .behindWindow
            // A window that is never key would otherwise show the material's inactive grey.
            blur.state = .active
            blur.autoresizingMask = [.width, .height]
            addSubview(blur)
            blurView = blur
            addDrawnBodies(.material, frame: frame)
        case .drawn:
            addDrawnBodies(.drawn, frame: frame)
        }
        // The hub's name (the last) lies under what stands in the places' drops.
        (contents.suffix(1) + contents.dropLast()).forEach { addSubview($0) }
    }

    required init?(coder: NSCoder) {
        fatalError("ShortcutRingDropsView is built in code")
    }

    private func addDrawnBodies(_ backdrop: ShortcutRingArtwork.Backdrop, frame: NSRect) {
        let bodies = ShortcutRingDrawnBodiesView(frame: frame)
        bodies.style.backdrop = backdrop
        bodies.autoresizingMask = [.width, .height]
        addSubview(bodies)
        bodiesView = bodies
    }

    override var isOpaque: Bool { return false }

    /// Clicks are the stage's.
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    /// The circle of drop `index` (the places, then the hub) in this view, as shown.
    func circle(ofDrop index: Int) -> CGRect? {
        guard let all = drops?.all, all.indices.contains(index) else { return nil }
        return ShortcutRingArtwork.circle(of: all[index], centre: CGPoint(x: bounds.midX, y: bounds.midY))
    }

    /// Shows the drops as `frame` has them.
    func show(_ frame: ShortcutRingDrops.Frame) {
        guard frame != drops else { return }
        drops = frame
        let centre = CGPoint(x: bounds.midX, y: bounds.midY)
        let all = frame.all
        let circles = all.map { ShortcutRingArtwork.circle(of: $0, centre: centre) }

        bodiesView?.drops = frame
        if let blurView {
            blurView.maskImage = Self.mask(frame, size: bounds.size)
        }
        var inGlass = false
        if #available(macOS 26.0, *), let glass = glassBodies as? ShortcutRingGlassBodies {
            glass.show(circles: circles, lit: all.map(\.lit))
            inGlass = true
        }
        for (index, drop) in all.enumerated() where contents.indices.contains(index) {
            let circle = circles[index]
            // Inside a glass drop the coordinates are the drop's own.
            let middle = inGlass
                ? CGPoint(x: circle.width / 2, y: circle.height / 2)
                : CGPoint(x: circle.midX, y: circle.midY)
            contents[index].lit = drop.lit
            contents[index].put(middle: middle, grow: drop.grow, opacity: drop.opacity)
        }
    }

    /// The blurred material's mask for `frame`: the nine circles of that moment.
    static func mask(_ frame: ShortcutRingDrops.Frame, size: NSSize) -> NSImage {
        return NSImage(size: size, flipped: false) { rect in
            ShortcutRingArtwork.drawMask(frame, centre: CGPoint(x: rect.midX, y: rect.midY))
            return true
        }
    }
}
