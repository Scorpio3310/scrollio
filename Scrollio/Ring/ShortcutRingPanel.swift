//
//  ShortcutRingPanel.swift
//  Scrollio
//
//  The Shortcut Ring on screen: a panel as large as the screen the pointer is on, with the
//  ring drawn where it stands. The panel never takes the keyboard and never brings Scrollio
//  to the front: the app the user works in stays in front and its window stays key, so
//  what a place sends (Copy, Paste) goes there.
//
//  - Non-activating, borderless, never key or main (`ShortcutRingPanel`), shown with
//    `orderFrontRegardless`, above the menu bar, the Dock and full-screen apps, on every
//    Space, and not hidden when Scrollio is not the active app (a panel's default).
//  - While the trigger is held the panel ignores the mouse: the hand's movement chooses
//    (`ShortcutRingSession`) and a click goes where it would go without a ring.
//  - Once the ring stands open the panel takes the mouse on its whole screen, so the click
//    that chooses or dismisses reaches the ring and never the app underneath. Its clear
//    part is filled almost invisibly for that: a pixel without any alpha lets a click
//    through. A click acts when the button comes up.
//
//  The ring lies on a system material cut to a circle; with "Reduce transparency" a plain
//  disc is drawn instead. It opens with a short fade and a small growth of its places;
//  with "Reduce motion" it is simply there. It goes away at once, without a fade, so that
//  an action which looks at the screen (a screenshot) never finds it.
//
//  The panel itself is never faded: its alpha is 1 from the moment it is ordered in. A
//  window's alpha animation can stay at its start (it did, for two seconds and more, on a
//  Mac whose display slept), and the ring would then take clicks without being seen. The
//  opening only animates layers of the drawing, from values that are not the layers' own:
//  where no animation runs, the ring is simply there.
//

import Cocoa

// MARK: - What the system asks for

/// The accessibility settings the ring follows.
struct ShortcutRingAppearance: Equatable {
    var reducesMotion = false
    var reducesTransparency = false
    var increasesContrast = false

    static var system: ShortcutRingAppearance {
        let workspace = NSWorkspace.shared
        return ShortcutRingAppearance(
            reducesMotion: workspace.accessibilityDisplayShouldReduceMotion,
            reducesTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
            increasesContrast: workspace.accessibilityDisplayShouldIncreaseContrast
        )
    }

    /// How long the ring takes to appear; nothing with "Reduce motion".
    var openDuration: TimeInterval {
        return reducesMotion ? 0 : ShortcutRingPanelPresenter.openDuration
    }

    var backdrop: ShortcutRingArtwork.Backdrop {
        return reducesTransparency ? .drawn : .material
    }
}

// MARK: - Screens

/// A screen as the ring needs it, in the coordinates of events (y grows downwards from
/// the top of the main screen).
struct ShortcutRingScreen: Equatable {
    /// The whole screen: what the panel covers.
    var frame: CGRect
    /// The screen without its notch: where the ring may stand.
    var usable: CGRect
}

enum ShortcutRingScreens {

    /// A rectangle of AppKit's screen coordinates (y upwards) in event coordinates, or
    /// the other way round: the same flip about the main screen's height.
    static func flipped(_ rect: CGRect, mainScreenHeight: CGFloat) -> CGRect {
        return CGRect(x: rect.minX, y: mainScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func flipped(_ point: CGPoint, mainScreenHeight: CGFloat) -> CGPoint {
        return CGPoint(x: point.x, y: mainScreenHeight - point.y)
    }

    /// The height of the screen whose corner is the origin of both coordinate systems.
    static var mainScreenHeight: CGFloat {
        return NSScreen.screens.first?.frame.height ?? 0
    }

    /// The screen that holds `point` (event coordinates): the one the pointer is on, never
    /// the one with the key window. Without any screen, an empty one.
    static func screen(containing point: CGPoint) -> ShortcutRingScreen {
        let height = mainScreenHeight
        let screens = NSScreen.screens
        let cocoaPoint = flipped(point, mainScreenHeight: height)
        guard let screen = screens.first(where: { NSMouseInRect(cocoaPoint, $0.frame, false) }) ?? screens.first else {
            return ShortcutRingScreen(frame: .zero, usable: .zero)
        }
        let insets = screen.safeAreaInsets
        var usable = screen.frame
        usable.origin.x += insets.left
        usable.origin.y += insets.bottom
        usable.size.width -= insets.left + insets.right
        usable.size.height -= insets.top + insets.bottom
        return ShortcutRingScreen(
            frame: flipped(screen.frame, mainScreenHeight: height),
            usable: flipped(usable, mainScreenHeight: height)
        )
    }

    /// Where the pointer is, in event coordinates.
    static func pointerLocation() -> CGPoint {
        return flipped(NSEvent.mouseLocation, mainScreenHeight: mainScreenHeight)
    }
}

// MARK: - The panel

/// A panel that can never be the key or the main window.
final class ShortcutRingPanel: NSPanel {

    override var canBecomeKey: Bool { return false }
    override var canBecomeMain: Bool { return false }

    static func make() -> ShortcutRingPanel {
        let panel = ShortcutRingPanel(
            contentRect: NSRect(x: 0, y: 0, width: ShortcutRingGeometry.canvasSide, height: ShortcutRingGeometry.canvasSide),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        // Above the menu bar, the Dock and open menus.
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // The ring draws its own shadow: the panel is as large as the screen.
        panel.hasShadow = false
        // A panel hides when its app is not the active one; Scrollio never is.
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.isExcludedFromWindowsMenu = true
        panel.worksWhenModal = true
        panel.ignoresMouseEvents = true
        return panel
    }
}

/// The ring's shadow, around the disc of material.
final class ShortcutRingShadowView: NSView {

    override var isOpaque: Bool { return false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        ShortcutRingArtwork.drawShadow(centre: CGPoint(x: bounds.midX, y: bounds.midY))
    }
}

/// The panel's content: the almost invisible fill that takes the clicks, the ring's
/// shadow, the material and the ring itself. The stage draws nothing itself (it is as
/// large as a screen: its fill is its layer's colour, which needs no bitmap).
final class ShortcutRingStageView: NSView {

    /// The fill of the clear part while the ring stands open: enough for the window
    /// server to give the panel a click there, too little to see.
    static let clickFillAlpha: CGFloat = 0.015

    /// A pointer button went down (true) or came up at a point in event coordinates:
    /// 0 the left button, 1 any other.
    var onButton: ((_ button: Int, _ isDown: Bool, _ location: CGPoint) -> Void)?

    let shadowView = ShortcutRingShadowView()
    let material = NSVisualEffectView()
    let faceView = ShortcutRingFaceView()

    /// The screen the panel covers, in event coordinates.
    private(set) var screenFrame = CGRect.zero
    /// The ring's middle in this view.
    private(set) var ringCentre = CGPoint.zero

    var takesClicks = false {
        didSet {
            layer?.backgroundColor = takesClicks ? NSColor(white: 0, alpha: Self.clickFillAlpha).cgColor : nil
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // A layer of its own from the start: the opening fades it.
        shadowView.wantsLayer = true
        shadowView.layerContentsRedrawPolicy = .onSetNeedsDisplay
        addSubview(shadowView)
        material.material = .hudWindow
        material.blendingMode = .behindWindow
        // A window that is never key would otherwise show the material's inactive grey.
        material.state = .active
        material.maskImage = Self.discMask(diameter: ShortcutRingGeometry.outerRadius * 2)
        addSubview(material)
        addSubview(faceView)
    }

    required init?(coder: NSCoder) {
        fatalError("ShortcutRingStageView is built in code")
    }

    /// Puts the ring at `centre` of `screen` (both in event coordinates).
    func place(centre: CGPoint, on screen: CGRect) {
        screenFrame = screen
        ringCentre = CGPoint(x: centre.x - screen.minX, y: screen.maxY - centre.y)
        let outer = ShortcutRingGeometry.outerRadius
        material.frame = NSRect(x: ringCentre.x - outer, y: ringCentre.y - outer, width: outer * 2, height: outer * 2)
        let side = ShortcutRingGeometry.canvasSide
        let canvas = NSRect(x: ringCentre.x - side / 2, y: ringCentre.y - side / 2, width: side, height: side)
        faceView.frame = canvas
        // Room for the shadow's blur beyond the canvas.
        shadowView.frame = canvas.insetBy(dx: -24, dy: -24)
        shadowView.needsDisplay = true
    }

    /// A point of this view in event coordinates.
    func eventLocation(of point: NSPoint) -> CGPoint {
        return CGPoint(x: screenFrame.minX + point.x, y: screenFrame.maxY - point.y)
    }

    static func discMask(diameter: CGFloat) -> NSImage {
        return NSImage(size: NSSize(width: diameter, height: diameter), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
    }

    // MARK: The mouse

    /// Every point of the panel is the stage's, the ring's included: the material and
    /// the drawing take no click themselves (a view that is hit and does not accept the
    /// first click of a window that is not key would let that click do nothing).
    override func hitTest(_ point: NSPoint) -> NSView? {
        return super.hitTest(point) == nil ? nil : self
    }

    /// The first click on a window that is not key is a click, not a way to make it key.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    private func report(_ button: Int, isDown: Bool, _ event: NSEvent) {
        onButton?(button, isDown, eventLocation(of: convert(event.locationInWindow, from: nil)))
    }

    override func mouseDown(with event: NSEvent) { report(0, isDown: true, event) }
    override func mouseUp(with event: NSEvent) { report(0, isDown: false, event) }
    override func rightMouseDown(with event: NSEvent) { report(1, isDown: true, event) }
    override func rightMouseUp(with event: NSEvent) { report(1, isDown: false, event) }
    override func otherMouseDown(with event: NSEvent) { report(1, isDown: true, event) }
    override func otherMouseUp(with event: NSEvent) { report(1, isDown: false, event) }
    /// The wheel does nothing over an open ring (the panel covers what is underneath).
    override func scrollWheel(with event: NSEvent) {}
}

/// Draws the ring's places and the lit action's name (`ShortcutRingArtwork`).
final class ShortcutRingFaceView: NSView {

    var face = ShortcutRingFace(places: []) {
        didSet { needsDisplay = true }
    }
    var lit: Int? {
        didSet {
            guard lit != oldValue else { return }
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
        fatalError("ShortcutRingFaceView is built in code")
    }

    override var isOpaque: Bool { return false }

    /// Clicks are the stage's.
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        ShortcutRingArtwork.draw(face, lit: lit, centre: CGPoint(x: bounds.midX, y: bounds.midY), style: style)
    }
}

// MARK: - The presenter

/// What the ring's controller asks of the screen. The app's is the panel; tests pass one
/// that only remembers.
protocol ShortcutRingPresenting: AnyObject {
    /// A pointer button went down or came up on the ring's panel (event coordinates).
    var onButton: ((_ button: Int, _ isDown: Bool, _ location: CGPoint) -> Void)? { get set }
    /// Shows the ring with its middle at `centre` on `screen` (event coordinates).
    func show(_ face: ShortcutRingFace, centre: CGPoint, screen: ShortcutRingScreen, lit: Int?, takesClicks: Bool)
    func light(_ place: Int?)
    /// Whether the panel takes the mouse (the ring stands open) or ignores it (held).
    func setTakesClicks(_ takesClicks: Bool)
    /// Takes the ring off the screen at once.
    func hide()
    /// Whether `window` is the ring's own panel.
    func owns(_ window: NSWindow?) -> Bool
}

final class ShortcutRingPanelPresenter: ShortcutRingPresenting {

    /// A small fade and growth.
    static let openDuration: TimeInterval = 0.12
    /// The places start this much smaller.
    static let openScale: CGFloat = 0.94
    static let fadeAnimationKey = "open-fade"
    static let growAnimationKey = "open"

    var onButton: ((Int, Bool, CGPoint) -> Void)?

    /// Puts the panel on screen without making Scrollio the active app. Under XCTest it
    /// does nothing, whatever a test forgets to replace: no ring appears on the screen of
    /// whoever runs the tests.
    var orderFront: (NSPanel) -> Void = AppRuntime.isRunningXCTest
        ? { _ in }
        : { $0.orderFrontRegardless() }
    /// The accessibility settings in effect. Tests replace it.
    var appearance: () -> ShortcutRingAppearance = { .system }

    /// Made at the first ring, on the main queue, never inside an event callback.
    private(set) var panel: ShortcutRingPanel?
    private(set) var stage: ShortcutRingStageView?
    /// How the ring last appeared: its fade's length (0: at once).
    private(set) var lastOpenDuration: TimeInterval = 0

    private func makePanelIfNeeded() -> (ShortcutRingPanel, ShortcutRingStageView) {
        if let panel, let stage { return (panel, stage) }
        let panel = ShortcutRingPanel.make()
        let stage = ShortcutRingStageView(frame: panel.contentLayoutRect)
        stage.autoresizingMask = [.width, .height]
        stage.onButton = { [weak self] button, isDown, location in
            self?.onButton?(button, isDown, location)
        }
        panel.contentView = stage
        self.panel = panel
        self.stage = stage
        return (panel, stage)
    }

    func show(_ face: ShortcutRingFace, centre: CGPoint, screen: ShortcutRingScreen, lit: Int?, takesClicks: Bool) {
        assertMainThread()
        let (panel, stage) = makePanelIfNeeded()
        let appearance = self.appearance()
        let height = ShortcutRingScreens.mainScreenHeight
        panel.setFrame(ShortcutRingScreens.flipped(screen.frame, mainScreenHeight: height), display: false)
        stage.frame = NSRect(origin: .zero, size: screen.frame.size)
        stage.place(centre: centre, on: screen.frame)
        stage.material.isHidden = appearance.reducesTransparency
        var style = ShortcutRingArtwork.Style()
        style.backdrop = appearance.backdrop
        style.increasesContrast = appearance.increasesContrast
        stage.faceView.style = style
        stage.faceView.face = face
        stage.faceView.lit = lit
        setTakesClicks(takesClicks)

        let duration = appearance.openDuration
        lastOpenDuration = duration
        let layers = [stage.faceView.layer, stage.shadowView.layer].compactMap { $0 }
        layers.forEach { $0.removeAllAnimations() }
        // Never faded as a window (see the top of the file).
        panel.alphaValue = 1
        orderFront(panel)
        guard duration > 0 else { return }

        let easeOut = CAMediaTimingFunction(name: .easeOut)
        for layer in layers {
            // The layer's own opacity stays 1: the animation only shows the way there.
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = duration
            fade.timingFunction = easeOut
            layer.add(fade, forKey: Self.fadeAnimationKey)
        }
        if let layer = stage.faceView.layer {
            // Grows about its middle (an AppKit layer is anchored at its corner).
            let scale = Self.openScale
            let size = stage.faceView.bounds.size
            let small = CATransform3DScale(
                CATransform3DMakeTranslation(size.width / 2 * (1 - scale), size.height / 2 * (1 - scale), 0),
                scale, scale, 1
            )
            let grow = CABasicAnimation(keyPath: "transform")
            grow.fromValue = NSValue(caTransform3D: small)
            grow.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            grow.duration = duration
            grow.timingFunction = easeOut
            layer.add(grow, forKey: Self.growAnimationKey)
        }
    }

    func light(_ place: Int?) {
        stage?.faceView.lit = place
    }

    func setTakesClicks(_ takesClicks: Bool) {
        panel?.ignoresMouseEvents = !takesClicks
        stage?.takesClicks = takesClicks
    }

    func owns(_ window: NSWindow?) -> Bool {
        guard let window, let panel else { return false }
        return window === panel
    }

    func hide() {
        guard let panel else { return }
        stage?.faceView.layer?.removeAllAnimations()
        stage?.shadowView.layer?.removeAllAnimations()
        panel.ignoresMouseEvents = true
        // At once, and with nothing to wait for.
        panel.orderOut(nil)
    }
}
