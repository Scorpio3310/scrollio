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
//  The ring is nine drops (`ShortcutRingDropsView`) of Liquid Glass, of the system's blurred
//  material or drawn plainly, as the system offers and asks (`ShortcutRingAppearance`). It
//  opens with its places' drops leaving the middle one after the other; with "Reduce
//  motion" it is simply there. It goes away at once, without a fade, so that an action
//  which looks at the screen (a screenshot) never finds it.
//
//  The opening never holds the ring up: the session and the lighting do not know of it,
//  and a place that is lit while its drop still travels shows lit. What is shown at any
//  moment is `ShortcutRingDrops.frame` for the time since the ring opened; a display link
//  asks for it once per frame of the screen, only while something moves (a third of a
//  second after the ring opens, an eighth after the lit place changes), and stops.
//
//  The panel itself is never faded: its alpha is 1 from the moment it is ordered in. A
//  window's alpha animation can stay at its start (it did, for two seconds and more, on a
//  Mac whose display slept), and the ring would then take clicks without being seen. A
//  display link can stay silent in the same way, so the frames are not trusted either:
//  the hub is there from the first moment, and a timer of the main queue puts everything
//  in its place half a second after the ring opened (and after a change of the lit place)
//  whether a frame came or not.
//

import Cocoa

// MARK: - What the system asks for

/// What decides how the ring is made and whether it moves: the accessibility settings and
/// what the system has.
struct ShortcutRingAppearance: Equatable {
    var reducesMotion = false
    var reducesTransparency = false
    var increasesContrast = false
    /// macOS 26 or later: Liquid Glass is there.
    var hasLiquidGlass = false

    static var system: ShortcutRingAppearance {
        let workspace = NSWorkspace.shared
        var hasLiquidGlass = false
        if #available(macOS 26.0, *) {
            hasLiquidGlass = true
        }
        return ShortcutRingAppearance(
            reducesMotion: workspace.accessibilityDisplayShouldReduceMotion,
            reducesTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
            increasesContrast: workspace.accessibilityDisplayShouldIncreaseContrast,
            hasLiquidGlass: hasLiquidGlass
        )
    }

    /// How long the ring takes to open; nothing with "Reduce motion".
    var openDuration: TimeInterval {
        return reducesMotion ? 0 : ShortcutRingDrops.openDuration
    }

    /// What the drops are made of: drawn plainly where transparency is not wanted or
    /// outlines are (glass and a blur have neither a solid ground nor a firm edge), else
    /// Liquid Glass where the system has it, else the blurred material.
    var material: ShortcutRingMaterial {
        if reducesTransparency || increasesContrast { return .drawn }
        return hasLiquidGlass ? .glass : .blur
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
        // The drops have their own shadows: the panel is as large as the screen.
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

/// The panel's content: the almost invisible fill that takes the clicks, and the ring's
/// drops where the ring stands. The stage draws nothing itself (it is as large as a
/// screen: its fill is its layer's colour, which needs no bitmap).
final class ShortcutRingStageView: NSView {

    /// The fill of the clear part while the ring stands open: enough for the window
    /// server to give the panel a click there, too little to see.
    static let clickFillAlpha: CGFloat = 0.015

    /// A pointer button went down (true) or came up at a point in event coordinates:
    /// 0 the left button, 1 any other.
    var onButton: ((_ button: Int, _ isDown: Bool, _ location: CGPoint) -> Void)?

    /// The ring's drops, made of what the last ring asked for.
    private(set) var dropsView: ShortcutRingDropsView?

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
    }

    required init?(coder: NSCoder) {
        fatalError("ShortcutRingStageView is built in code")
    }

    /// The drops made of `material`: those of the last ring, or new ones when the system's
    /// settings changed in between.
    func drops(of material: ShortcutRingMaterial) -> ShortcutRingDropsView {
        if let dropsView, dropsView.material == material { return dropsView }
        dropsView?.removeFromSuperview()
        let view = ShortcutRingDropsView(material: material)
        addSubview(view)
        dropsView = view
        return view
    }

    /// Puts the ring at `centre` of `screen` (both in event coordinates).
    func place(centre: CGPoint, on screen: CGRect) {
        screenFrame = screen
        ringCentre = CGPoint(x: centre.x - screen.minX, y: screen.maxY - centre.y)
        let side = ShortcutRingGeometry.canvasSide
        dropsView?.frame = NSRect(x: ringCentre.x - side / 2, y: ringCentre.y - side / 2, width: side, height: side)
    }

    /// A point of this view in event coordinates.
    func eventLocation(of point: NSPoint) -> CGPoint {
        return CGPoint(x: screenFrame.minX + point.x, y: screenFrame.maxY - point.y)
    }

    // MARK: The mouse

    /// Every point of the panel is the stage's, the ring's included: the drops take no
    /// click themselves (a view that is hit and does not accept the
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

/// Calls back once per frame of the screen until it is stopped.
protocol ShortcutRingFrames: AnyObject {
    func stop()
}

/// The frames of the screen a view is on.
final class ShortcutRingDisplayLinkFrames: NSObject, ShortcutRingFrames {

    private var link: CADisplayLink?
    private let step: () -> Void

    init(view: NSView, step: @escaping () -> Void) {
        self.step = step
        super.init()
        let link = view.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        step()
    }

    func stop() {
        link?.invalidate()
        link = nil
    }
}

final class ShortcutRingPanelPresenter: ShortcutRingPresenting {

    /// However the frames come, everything is in its place this long after the ring opened
    static let openDeadline: TimeInterval = 0.5
    /// and this long after the lit place changed.
    static let lightDeadline: TimeInterval = ShortcutRingDrops.litDuration + 0.08

    var onButton: ((Int, Bool, CGPoint) -> Void)?

    /// Puts the panel on screen without making Scrollio the active app. Under XCTest it
    /// does nothing, whatever a test forgets to replace: no ring appears on the screen of
    /// whoever runs the tests.
    var orderFront: (NSPanel) -> Void = AppRuntime.isRunningXCTest
        ? { _ in }
        : { $0.orderFrontRegardless() }
    /// The accessibility settings in effect and what the system has. Tests replace it.
    var appearance: () -> ShortcutRingAppearance = { .system }
    /// Asks for a call per frame of the screen the view is on. Under XCTest nobody is
    /// asked (the panel is not on a screen there); tests pass their own and call `step`.
    var startFrames: (NSView, @escaping () -> Void) -> ShortcutRingFrames? = AppRuntime.isRunningXCTest
        ? { _, _ in nil }
        : { ShortcutRingDisplayLinkFrames(view: $0, step: $1) }
    /// The time the opening and the lighting are counted in. Tests replace it.
    var clock: () -> TimeInterval = { CACurrentMediaTime() }
    /// Runs `work` on the main queue after `delay`. Tests replace it.
    var after: (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Made at the first ring, on the main queue, never inside an event callback.
    private(set) var panel: ShortcutRingPanel?
    private(set) var stage: ShortcutRingStageView?
    /// How the ring last appeared: how long its opening takes (0: at once).
    private(set) var lastOpenDuration: TimeInterval = 0
    /// Which place is lit, and how far each has come.
    private(set) var lighting = ShortcutRingDrops.Lighting()
    /// Whether the drops are still on their way: frames are asked for.
    private(set) var isMoving = false

    private var face = ShortcutRingFace(places: [])
    private var reducesMotion = false
    private var openedAt: TimeInterval = 0
    private var isShown = false
    private var frames: ShortcutRingFrames?
    /// Counts the rings shown and hidden: a deadline of an earlier ring does nothing.
    private var generation = 0

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
        stopMoving()
        generation += 1
        let height = ShortcutRingScreens.mainScreenHeight
        panel.setFrame(ShortcutRingScreens.flipped(screen.frame, mainScreenHeight: height), display: false)
        stage.frame = NSRect(origin: .zero, size: screen.frame.size)
        let drops = stage.drops(of: appearance.material)
        stage.place(centre: centre, on: screen.frame)
        drops.increasesContrast = appearance.increasesContrast
        drops.face = face
        self.face = face
        reducesMotion = appearance.reducesMotion
        lastOpenDuration = appearance.openDuration
        isShown = true
        openedAt = clock()
        // A ring that appears with a place lit shows it lit, however far its drop has come.
        lighting = ShortcutRingDrops.Lighting()
        lighting.light(lit, at: openedAt, filled: face.filled, eased: false)
        render(at: openedAt)
        setTakesClicks(takesClicks)
        // Never faded as a window (see the top of the file).
        panel.alphaValue = 1
        orderFront(panel)
        guard !reducesMotion else { return }
        move(for: Self.openDeadline) { [weak self] in
            // The opening is over, whatever the clock says.
            self?.openedAt = -.infinity
        }
    }

    func light(_ place: Int?) {
        guard isShown else { return }
        let now = clock()
        let before = lighting.target
        lighting.light(place, at: now, filled: face.filled, eased: !reducesMotion)
        render(at: now)
        guard !reducesMotion, lighting.target != before else { return }
        move(for: Self.lightDeadline)
    }

    /// Shows the drops as they are at `time`, and the lit place's name in the hub.
    private func render(at time: TimeInterval) {
        guard let drops = stage?.dropsView else { return }
        drops.title = lighting.target.map { face.places[$0].title }
        drops.show(ShortcutRingDrops.frame(
            at: time - openedAt, filled: face.filled, lit: lighting.amounts(at: time), reducesMotion: reducesMotion
        ))
    }

    /// Asks for frames until everything rests, and makes sure it does by `deadline` from
    /// now even if no frame comes.
    private func move(for deadline: TimeInterval, atDeadline: @escaping () -> Void = {}) {
        if !isMoving, let stage {
            isMoving = true
            frames = startFrames(stage) { [weak self] in
                self?.step()
            }
        }
        let generation = self.generation
        after(deadline) { [weak self] in
            guard let self, self.generation == generation, self.isShown else { return }
            atDeadline()
            self.step()
        }
    }

    /// One frame: the drops as they are now. Stops asking for frames once they rest.
    func step() {
        guard isShown else { return }
        let now = clock()
        render(at: now)
        if now - openedAt >= lastOpenDuration, lighting.isSettled(at: now) {
            stopMoving()
        }
    }

    private func stopMoving() {
        frames?.stop()
        frames = nil
        isMoving = false
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
        stopMoving()
        generation += 1
        isShown = false
        panel.ignoresMouseEvents = true
        // At once, and with nothing to wait for.
        panel.orderOut(nil)
    }
}
