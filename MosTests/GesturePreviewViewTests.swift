//
//  GesturePreviewViewTests.swift
//  MosTests
//
//  The picture at the top of the Gestures tab (GesturePreviewView): that it builds, when
//  its timer runs, that a changed scene restarts the demo, what Reduce Motion shows, that
//  the mouse and the desktop follow the loop, and that it draws off screen in light and
//  dark. Nothing is shown on screen: windows are created but never ordered in, and frames
//  are asked for by loop time, not waited for. Nothing runs a real action.
//
//  With GESTURE_PREVIEW_SHOTS set to a directory, `testContactSheets` also writes contact
//  sheets of the demo there, for a look at the artwork:
//  TEST_RUNNER_GESTURE_PREVIEW_SHOTS=/some/dir xcodebuild … test -only-testing:MosTests/GesturePreviewViewTests/testContactSheets
//

import XCTest
@testable import Mos_Debug

final class GesturePreviewViewTests: XCTestCase {

    private typealias Loop = GesturePreviewLoop

    /// The width the preview has in the tab (520 pt pane, 20 pt margins).
    private let size = NSSize(width: 480, height: GesturePreviewView.preferredHeight)

    private func makeView(reduceMotion: Bool = false, size: NSSize? = nil, mouse: MouseArtworkModel = .mxMaster4) -> GesturePreviewView {
        let view = GesturePreviewView(frame: NSRect(origin: .zero, size: size ?? self.size))
        view.mouseSource = { mouse }
        view.reloadMouse()
        view.prefersReducedMotion = { reduceMotion }
        view.reduceMotionDidChange()
        // The test windows are never shown, so none of them is ever really visible.
        view.isWindowVisible = { _ in true }
        return view
    }

    /// Puts the view into a window that is never shown.
    @discardableResult
    private func host(_ view: GesturePreviewView) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 200),
            styleMask: [.borderless], backing: .buffered, defer: true
        )
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(view)
        addTeardownBlock {
            view.setAnimating(false)
            window.close()
        }
        return window
    }

    private func scene(
        mode: MouseGestureMode = .discrete,
        focus: MouseGestureSettingsControls.Slot? = nil,
        configure: (inout MouseGestureSettings) -> Void = { _ in }
    ) -> GesturePreviewScene {
        var gesture = MouseGestureSettings.default
        gesture.mode = mode
        configure(&gesture)
        return GesturePreviewScene(gesture: gesture, focus: focus)
    }

    // MARK: - Building

    func testItBuildsTwoCardsSideBySide() {
        let view = makeView()
        XCTAssertEqual(GesturePreviewView.preferredHeight, 150)
        XCTAssertEqual(view.intrinsicContentSize.height, 150)
        XCTAssertEqual(view.intrinsicContentSize.width, NSView.noIntrinsicMetric)
        XCTAssertEqual(view.deviceCard.frame, NSRect(x: 0, y: 0, width: 234, height: 150))
        XCTAssertEqual(view.screenCard.frame, NSRect(x: 246, y: 0, width: 234, height: 150))

        // The mouse sits in the middle of its card, room to move on every side.
        let mouse = view.deviceCard.mouse
        XCTAssertTrue(view.deviceCard.bounds.contains(mouse.frame))
        let body = mouse.bodyRect.offsetBy(dx: mouse.frame.minX, dy: mouse.frame.minY)
        XCTAssertEqual(body.midX, view.deviceCard.bounds.midX, accuracy: 0.5)
        XCTAssertEqual(body.midY, view.deviceCard.bounds.midY, accuracy: 0.5)
        let outline = mouse.outlineRect.offsetBy(dx: mouse.frame.minX, dy: mouse.frame.minY)
        let room = Loop.verticalReach + GesturePreviewDeviceCard.arrowGap + GesturePreviewDeviceCard.arrowLength
        XCTAssertGreaterThan(outline.minY, room, "up: the mouse and its arrow stay in the card")
        XCTAssertLessThan(outline.maxY, 150 - room)
        XCTAssertGreaterThan(outline.minX, Loop.followTravelRange.upperBound * CGFloat(Loop.followReleaseShare) + GesturePreviewDeviceCard.arrowGap + GesturePreviewDeviceCard.arrowLength)
    }

    /// A picture only: clicks go through it and it is not read out.
    func testItIsInert() {
        let view = makeView()
        XCTAssertNil(view.hitTest(NSPoint(x: 100, y: 75)))
        XCTAssertNil(view.hitTest(NSPoint(x: 400, y: 75)))
        XCTAssertFalse(view.isAccessibilityElement())
    }

    func testItFollowsItsWidth() {
        let view = makeView(size: NSSize(width: 410, height: 150))
        XCTAssertEqual(view.deviceCard.frame, NSRect(x: 0, y: 0, width: 199, height: 150))
        XCTAssertEqual(view.screenCard.frame, NSRect(x: 211, y: 0, width: 199, height: 150))
        view.setFrameSize(size)
        XCTAssertEqual(view.deviceCard.frame.width, 234)
        XCTAssertEqual(view.screenCard.frame.maxX, 480)
        let mouse = view.deviceCard.mouse
        XCTAssertEqual(mouse.bodyRect.midX + mouse.frame.minX, 117, accuracy: 0.5)
    }

    // MARK: - The timer

    func testNothingRunsWithoutAWindow() {
        let view = makeView()
        XCTAssertFalse(view.isTimerRunning)
        view.setAnimating(true)
        XCTAssertFalse(view.isTimerRunning, "no window, no timer")
    }

    /// Minimised, hidden or covered by other windows: the demo pauses, and goes on when
    /// the window shows again. Only its own window counts.
    func testItPausesWhileItsWindowCannotBeSeen() {
        var visible = true
        let view = makeView()
        view.isWindowVisible = { _ in visible }
        let window = host(view)
        view.setAnimating(true)
        XCTAssertTrue(view.isTimerRunning)

        visible = false
        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
        XCTAssertFalse(view.isTimerRunning, "not while nobody can see it")

        visible = true
        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
        XCTAssertTrue(view.isTimerRunning, "on again once it shows")

        visible = false
        let other = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
        other.isReleasedWhenClosed = false
        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: other)
        XCTAssertTrue(view.isTimerRunning, "another window's change is not its own")
        other.close()

        // By default it asks the window itself: one that was never shown cannot be seen.
        let plain = GesturePreviewView(frame: NSRect(origin: .zero, size: size))
        plain.prefersReducedMotion = { false }
        host(plain)
        plain.setAnimating(true)
        XCTAssertFalse(plain.isTimerRunning)
    }

    func testSetAnimatingStartsAndStopsTheTimer() {
        let view = makeView()
        let window = host(view)
        XCTAssertFalse(view.isTimerRunning, "not before the tab asks for it")

        view.setAnimating(true)
        XCTAssertTrue(view.isTimerRunning)
        view.setAnimating(true)
        XCTAssertTrue(view.isTimerRunning)

        view.setAnimating(false)
        XCTAssertFalse(view.isTimerRunning)

        // Leaving the window stops it, coming back starts it again.
        view.setAnimating(true)
        view.removeFromSuperview()
        XCTAssertFalse(view.isTimerRunning)
        window.contentView?.addSubview(view)
        XCTAssertTrue(view.isTimerRunning)
    }

    func testStoppingReturnsToTheStartOfTheLoop() {
        let view = makeView()
        host(view)
        view.setAnimating(true)
        view.showLoop(at: Loop.moveEnd)
        XCTAssertNotEqual(view.shownFrame.mouseOffset, .zero)
        view.setAnimating(false)
        XCTAssertEqual(view.loopTime, 0)
        XCTAssertEqual(view.shownFrame, view.loop.frame(at: 0))
    }

    // MARK: - The scene

    func testAChangedSceneRestartsTheLoop() {
        let view = makeView()
        host(view)
        view.setAnimating(true)
        view.showLoop(at: 1.2)
        XCTAssertEqual(view.loopTime, 1.2, accuracy: 1e-9)

        view.scene = scene(mode: .interactive)
        XCTAssertEqual(view.loopTime, 0, "a changed scene starts the loop again")
        XCTAssertEqual(view.loop.scene, view.scene)
        XCTAssertEqual(view.loop.legs.first?.kind, .follow)
        XCTAssertEqual(view.shownFrame, view.loop.frame(at: 0))
        XCTAssertTrue(view.isTimerRunning)

        // Setting the same scene again is not a change.
        view.showLoop(at: 0.9)
        view.scene = scene(mode: .interactive)
        XCTAssertEqual(view.loopTime, 0.9, accuracy: 1e-9)

        // Any setting is a change: the tracking speed, the pointer, the row pointed at.
        for changed in [
            scene(mode: .interactive) { $0.trackingSpeed = 2 },
            scene(mode: .interactive) { $0.freezePointer = false },
            scene(mode: .interactive, focus: .up),
        ] {
            view.showLoop(at: 0.9)
            view.scene = changed
            XCTAssertEqual(view.loopTime, 0, "\(changed)")
        }
    }

    func testLoopTimeWrapsAround() {
        let view = makeView()
        let length = view.loop.length
        view.showLoop(at: length + 0.6)
        XCTAssertEqual(view.loopTime, 0.6, accuracy: 1e-9)
        XCTAssertEqual(view.shownFrame, view.loop.frame(at: view.loopTime))
        XCTAssertEqual(view.shownFrame.buttonDepth, view.loop.frame(at: 0.6).buttonDepth, accuracy: 1e-6)
        view.showLoop(at: -0.5)
        XCTAssertEqual(view.loopTime, length - 0.5, accuracy: 1e-9)
    }

    // MARK: - The picture follows the loop

    func testTheMouseMovesWithTheHand() {
        let view = makeView()
        view.scene = scene(focus: .up)
        let mouse = view.deviceCard.mouse
        let home = mouse.frame.origin
        view.showLoop(at: Loop.moveEnd)
        XCTAssertEqual(mouse.frame.origin.x, home.x, accuracy: 1e-9)
        XCTAssertEqual(mouse.frame.origin.y, home.y - Loop.verticalReach, accuracy: 0.5, "up is towards the top of the card")
        view.showLoop(at: view.loop.length - 0.05)
        XCTAssertEqual(mouse.frame.origin, home)

        view.scene = scene(focus: .right)
        view.showLoop(at: Loop.moveEnd)
        XCTAssertEqual(mouse.frame.origin.x, home.x + Loop.horizontalReach, accuracy: 0.5)
        let arrow = view.deviceCard.arrowSegment
        XCTAssertNotNil(arrow)
        XCTAssertGreaterThan(arrow?.to.x ?? 0, arrow?.from.x ?? 0, "the arrow points right")
        XCTAssertGreaterThan(arrow?.from.x ?? 0, mouse.frame.maxX - GesturePreviewMouse.margin)
    }

    /// A frame of the demo moves the mouse and redraws only the small rectangle of the arrow
    /// ahead of it: the device card, half of the view, is not redrawn.
    func testAFrameRedrawsLessThanTheWholeView() throws {
        let view = makeView()
        // A window with a window server window (never shown): its views get their layers
        // and are redrawn as on screen.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 200),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(view)
        addTeardownBlock { window.close() }
        view.scene = scene(focus: .right)
        let card = view.deviceCard
        view.showLoop(at: Loop.moveStart + Loop.moveDuration * 0.4)
        XCTAssertFalse(card.arrowView.isHidden, "the arrow shows while the mouse moves")
        window.displayIfNeeded()
        drawPendingLayers(of: view)
        XCTAssertNotNil(card.arrowView.layer, "a layer of its own")
        XCTAssertEqual(card.layer?.needsDisplay(), false)
        let arrowBefore = card.arrowView.frame
        let mouseBefore = card.mouse.frame.origin

        view.showLoop(at: Loop.moveStart + Loop.moveDuration * 0.6)

        XCTAssertGreaterThan(card.mouse.frame.minX, mouseBefore.x, "the mouse moved")
        XCTAssertEqual(card.layer?.needsDisplay(), false, "the card is not redrawn")
        XCTAssertEqual(card.arrowView.layer?.needsDisplay(), true, "the arrow is")
        // What moves clips to its bounds, so moving it draws nothing.
        XCTAssertTrue(card.mouse.clipsToBounds)
        XCTAssertTrue(card.arrowView.clipsToBounds)
        let arrow = card.arrowView.frame
        XCTAssertGreaterThan(arrow.minX, arrowBefore.minX, "and moved with the mouse")
        XCTAssertLessThan(arrow.width * arrow.height, view.bounds.width * view.bounds.height / 20)
        XCTAssertTrue(card.bounds.contains(arrow))
        XCTAssertEqual(arrow, arrow.integral, "on whole points: the arrow keeps its pixels")
        let segment = try XCTUnwrap(card.arrowSegment)
        XCTAssertTrue(arrow.contains(segment.from) && arrow.contains(segment.to), "where the card drew it")
        let subviews = card.subviews
        XCTAssertLessThan(try XCTUnwrap(subviews.firstIndex(of: card.arrowView)), try XCTUnwrap(subviews.firstIndex(of: card.mouse)),
                          "under the mouse")

        // Back at rest there is no arrow.
        view.showLoop(at: view.loop.length - 0.05)
        XCTAssertTrue(card.arrowView.isHidden)
    }

    /// Draws what waits to be drawn in every layer under `view`, as the screen would.
    private func drawPendingLayers(of view: NSView) {
        view.layer?.displayIfNeeded()
        view.subviews.forEach(drawPendingLayers)
    }

    /// Scrolled out of the visible part of the pane, the demo pauses; it goes on as soon as
    /// some of it shows again.
    func testItPausesWhileScrolledOutOfSight() {
        let view = makeView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 200),
            styleMask: [.borderless], backing: .buffered, defer: true
        )
        window.isReleasedWhenClosed = false
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 200))
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 1000))
        document.addSubview(view)
        scroll.documentView = document
        scroll.contentView.postsBoundsChangedNotifications = true
        window.contentView?.addSubview(scroll)
        addTeardownBlock {
            view.setAnimating(false)
            window.close()
        }

        scroll.contentView.scroll(to: .zero)
        view.setAnimating(true)
        XCTAssertFalse(view.visibleRect.intersection(view.bounds).isEmpty)
        XCTAssertTrue(view.isTimerRunning)

        scroll.contentView.scroll(to: NSPoint(x: 0, y: 600))
        XCTAssertTrue(view.visibleRect.intersection(view.bounds).isEmpty)
        XCTAssertFalse(view.isTimerRunning, "not while it is scrolled out of sight")
        XCTAssertEqual(view.loopTime, 0, "it rests")

        scroll.contentView.scroll(to: NSPoint(x: 0, y: 100))
        XCTAssertFalse(view.visibleRect.intersection(view.bounds).isEmpty, "partly in sight")
        XCTAssertTrue(view.isTimerRunning)

        // Laid out without a size yet, it waits for one.
        view.setFrameSize(.zero)
        XCTAssertFalse(view.isTimerRunning)
        view.setFrameSize(size)
        XCTAssertTrue(view.isTimerRunning)
    }

    func testTheDesktopCardShowsTheFrame() {
        let view = makeView()
        view.scene = scene(mode: .interactive)
        view.showLoop(at: 1.4)
        XCTAssertEqual(view.screenCard.shown, view.shownFrame)
        XCTAssertEqual(view.screenCard.shown?.desktop ?? 0, 0.5, accuracy: 1e-9)
    }

    // MARK: - Reduce Motion

    func testReduceMotionShowsAStillFrame() {
        var reduce = true
        let view = makeView()
        view.prefersReducedMotion = { reduce }
        view.reduceMotionDidChange()
        host(view)

        view.setAnimating(true)
        XCTAssertFalse(view.isTimerRunning, "nothing runs with Reduce Motion on")
        XCTAssertEqual(view.shownFrame, view.loop.stillFrame)
        XCTAssertEqual(view.shownFrame.buttonDepth, 1, accuracy: 1e-9, "the button is shown held")

        // A changed scene changes the still frame, and still nothing runs.
        view.scene = scene(mode: .interactive)
        XCTAssertFalse(view.isTimerRunning)
        XCTAssertEqual(view.shownFrame, view.loop.stillFrame)
        XCTAssertEqual(view.shownFrame.desktop, 0.5, accuracy: 1e-9, "the desktops half-way")

        // Reduce Motion off: the demo starts from the beginning.
        reduce = false
        view.reduceMotionDidChange()
        XCTAssertTrue(view.isTimerRunning)
        XCTAssertEqual(view.shownFrame, view.loop.frame(at: 0))

        // And on again while it runs.
        reduce = true
        view.reduceMotionDidChange()
        XCTAssertFalse(view.isTimerRunning)
        XCTAssertEqual(view.shownFrame, view.loop.stillFrame)
    }

    // MARK: - Drawing

    /// One picture of the view, rendered off screen.
    private func render(
        _ scene: GesturePreviewScene, dark: Bool, time: TimeInterval?, size: NSSize? = nil, mouse: MouseArtworkModel = .mxMaster4
    ) throws -> NSBitmapImageRep {
        let view = makeView(reduceMotion: time == nil, size: size, mouse: mouse)
        view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        view.scene = scene
        if let time {
            view.showLoop(at: time)
        }
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    private func pixels(of rep: NSBitmapImageRep) throws -> Data {
        return Data(bytes: try XCTUnwrap(rep.bitmapData), count: rep.bytesPerRow * rep.pixelsHigh)
    }

    /// The colour at a point of the view (top-left origin).
    private func colour(in rep: NSBitmapImageRep, x: CGFloat, y: CGFloat) throws -> NSColor {
        let scale = CGFloat(rep.pixelsWide) / rep.size.width
        let colour = try XCTUnwrap(rep.colorAt(x: Int(x * scale), y: Int(y * scale)))
        return try XCTUnwrap(colour.usingColorSpace(.deviceRGB))
    }

    private func mean(_ colour: NSColor) -> CGFloat {
        return (colour.redComponent + colour.greenComponent + colour.blueComponent) / 3
    }

    /// The accent colour as a picture rendered in that appearance draws it: the app's
    /// accent has a lighter shade in dark (#7F62D9) than in light (#5F44B3).
    private func accent(dark: Bool) throws -> NSColor {
        var resolved: NSColor?
        try XCTUnwrap(NSAppearance(named: dark ? .darkAqua : .aqua)).performAsCurrentDrawingAppearance {
            resolved = NSColor.controlAccentColor.usingColorSpace(.deviceRGB)
        }
        return try XCTUnwrap(resolved)
    }

    func testItDrawsInLightAndDark() throws {
        let light = try render(scene(), dark: false, time: 0)
        let dark = try render(scene(), dark: true, time: 0)
        XCTAssertEqual(light.size, size)

        // The palm of the mouse (left card) and the margin of the page in the window (right card).
        let palm = (x: CGFloat(117 + 10), y: CGFloat(100))
        let page = (x: CGFloat(246 + 23), y: CGFloat(106))
        XCTAssertGreaterThan(mean(try colour(in: light, x: palm.x, y: palm.y)), 0.9)
        XCTAssertGreaterThan(mean(try colour(in: light, x: page.x, y: page.y)), 0.9)
        XCTAssertLessThan(mean(try colour(in: dark, x: palm.x, y: palm.y)), 0.45)
        XCTAssertLessThan(mean(try colour(in: dark, x: page.x, y: page.y)), 0.3)
        for rep in [light, dark] {
            XCTAssertEqual(try colour(in: rep, x: palm.x, y: palm.y).alphaComponent, 1, accuracy: 0.01)
            // Between the cards nothing is drawn.
            XCTAssertEqual(try colour(in: rep, x: 240, y: 75).alphaComponent, 0, accuracy: 0.01)
            // The first desktop is blue.
            let desktop = try colour(in: rep, x: 246 + 6, y: 120)
            XCTAssertGreaterThan(desktop.blueComponent, desktop.redComponent + 0.1)
            XCTAssertEqual(desktop.alphaComponent, 1, accuracy: 0.01)
        }
    }

    func testTheButtonTakesTheAccentColourWhileHeld() throws {
        let up = try render(scene(focus: .click), dark: false, time: 0)
        let held = try render(scene(focus: .click), dark: false, time: Loop.pressTime + 0.3)
        let mouse = makeView().deviceCard.mouse
        let mouseOrigin = mouse.frame.origin
        let button = mouse.buttonRect
        let x = mouseOrigin.x + button.midX, y = mouseOrigin.y + button.midY
        let idle = try colour(in: up, x: x, y: y)
        let pressed = try colour(in: held, x: x, y: y)
        let accent = try accent(dark: false)
        func distance(_ a: NSColor, _ b: NSColor) -> CGFloat {
            return abs(a.redComponent - b.redComponent) + abs(a.greenComponent - b.greenComponent) + abs(a.blueComponent - b.blueComponent)
        }
        XCTAssertLessThan(distance(pressed, accent), distance(idle, accent))
        XCTAssertLessThan(distance(pressed, accent), 0.3)
    }

    /// The mouse is the connected one's drawing and follows a mouse coming and going; the
    /// button held is where the model has its gesture button (the plain mouse: Back).
    func testTheMouseFollowsTheConnectedModel() throws {
        var connected = MouseArtworkModel.mxMaster4
        let view = makeView()
        view.mouseSource = { connected }
        view.reloadMouse()
        let mouse = view.deviceCard.mouse
        XCTAssertEqual(mouse.model, .mxMaster4)
        let four = mouse.buttonRect
        XCTAssertLessThan(four.maxX, mouse.bodyRect.minX + 6, "on the side of the body")
        XCTAssertTrue(mouse.outlineRect.contains(four))

        connected = .mxMaster3
        NotificationCenter.default.post(name: LogiCenter.mouseStateChanged, object: nil)
        XCTAssertEqual(mouse.model, .mxMaster3)
        XCTAssertNotEqual(mouse.buttonRect, four)
        XCTAssertLessThan(mouse.buttonRect.minX, four.minX, "in the thumb rest, below the side buttons")

        connected = .generic
        NotificationCenter.default.post(name: LogiCenter.sessionChanged, object: nil)
        XCTAssertEqual(mouse.model, .generic)
        let body = mouse.bodyRect.offsetBy(dx: mouse.frame.minX, dy: mouse.frame.minY)
        XCTAssertEqual(body.midX, view.deviceCard.bounds.midX, accuracy: 0.5, "the body stays centred")
        XCTAssertLessThan(mouse.buttonRect.maxX, mouse.bodyRect.minX + 6, "the Back button, on the left side")
        // The held button takes the accent colour on every model.
        for model in MouseArtworkModel.allCases {
            let held = try render(scene(focus: .click), dark: true, time: Loop.pressTime + 0.3, mouse: model)
            let preview = makeView(mouse: model).deviceCard.mouse
            let button = preview.buttonRect
            let point = preview.frame.origin
            let colour = try self.colour(in: held, x: point.x + button.midX, y: point.y + button.midY)
            let accent = try accent(dark: true)
            XCTAssertLessThan(abs(colour.redComponent - accent.redComponent) + abs(colour.greenComponent - accent.greenComponent)
                              + abs(colour.blueComponent - accent.blueComponent), 0.3, "\(model)")
        }
    }

    func testThePictureChangesWithTheLoopAndComesBack() throws {
        let cases: [(GesturePreviewScene, TimeInterval)] = [
            (scene(), Loop.moveEnd + 0.2),
            (scene(mode: .interactive), 1.4),
            (scene(focus: .up), 1.6),
            (scene(focus: .down), 1.6),
            (scene(focus: .click) { $0.clickAction = SystemShortcut.copy.identifier }, 1.1),
        ]
        for (scene, moment) in cases {
            let loop = Loop(scene: scene)
            let start = try render(scene, dark: false, time: 0)
            let middle = try render(scene, dark: false, time: moment)
            let again = try render(scene, dark: false, time: loop.length)
            XCTAssertNotEqual(try pixels(of: start), try pixels(of: middle), "\(scene)")
            XCTAssertEqual(try pixels(of: start), try pixels(of: again), "back after a round: \(scene)")
        }
    }

    /// Every kind of scene paints both cards, moving and still, in light and in dark.
    func testEverySceneDraws() throws {
        let scenes = [
            scene(), scene(mode: .interactive), scene(focus: .up), scene(focus: .down), scene(focus: .click),
            scene(focus: .click) { $0.clickAction = SystemShortcut.copy.identifier },
        ]
        for scene in scenes {
            let loop = Loop(scene: scene)
            for dark in [false, true] {
                for time in [loop.legs[0].stillTime, nil] as [TimeInterval?] {
                    let rep = try render(scene, dark: dark, time: time)
                    let message = "\(scene), dark \(dark), at \(String(describing: time))"
                    XCTAssertGreaterThan(try colour(in: rep, x: 12, y: 12).alphaComponent, 0.02, message)
                    XCTAssertLessThan(try colour(in: rep, x: 12, y: 12).alphaComponent, 0.2, message)
                    XCTAssertEqual(try colour(in: rep, x: 470, y: 30).alphaComponent, 1, accuracy: 0.01, message)
                }
            }
        }
    }

    /// The desktop is redrawn at most once per frame that changes it; a desktop at rest is
    /// cheap enough to draw on every display refresh while it moves.
    func testDrawingTheDesktopIsCheap() throws {
        let view = makeView()
        view.appearance = NSAppearance(named: .darkAqua)
        view.scene = scene(focus: .up)
        let rep = try XCTUnwrap(view.screenCard.bitmapImageRepForCachingDisplay(in: view.screenCard.bounds))
        let loop = view.loop
        let frames = 120
        let start = CFAbsoluteTimeGetCurrent()
        for index in 0..<frames {
            view.showLoop(at: loop.length * Double(index) / Double(frames))
            view.screenCard.cacheDisplay(in: view.screenCard.bounds, to: rep)
        }
        let perFrame = (CFAbsoluteTimeGetCurrent() - start) / Double(frames)
        // Generous: an off-screen bitmap is slower than the screen, and test machines vary.
        XCTAssertLessThan(perFrame, 0.008, "\(perFrame * 1000) ms per frame")
    }

    // MARK: - Contact sheets

    /// Writes contact sheets of the demo when GESTURE_PREVIEW_SHOTS names a directory.
    func testContactSheets() throws {
        guard let path = ProcessInfo.processInfo.environment["GESTURE_PREVIEW_SHOTS"], !path.isEmpty else {
            throw XCTSkip("GESTURE_PREVIEW_SHOTS is not set")
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        func write(_ name: String, _ scene: GesturePreviewScene, dark: Bool) throws {
            let sheet = try contactSheet(title: name, scene: scene, dark: dark)
            let data = try XCTUnwrap(sheet.representation(using: .png, properties: [:]))
            try data.write(to: directory.appendingPathComponent("\(name).png"))
        }

        let cases: [(String, GesturePreviewScene)] = [
            ("follow-cycle", scene(mode: .interactive)),
            ("follow-left", scene(mode: .interactive, focus: .left)),
            ("follow-right-inverted", scene(mode: .interactive, focus: .right) { $0.invertHorizontal = true }),
            ("follow-fast-pointer-free", scene(mode: .interactive) { $0.trackingSpeed = 2.5; $0.freezePointer = false }),
            ("discrete-cycle", scene()),
            ("discrete-up-mission-control", scene(focus: .up)),
            ("discrete-down-launchpad", scene(focus: .down)),
            ("discrete-click-mission-control", scene(focus: .click)),
            ("discrete-click-copy", scene(focus: .click) { $0.clickAction = SystemShortcut.copy.identifier }),
            ("discrete-left-inverted", scene(focus: .left) { $0.invertHorizontal = true }),
            ("discrete-up-no-action", scene(focus: .up) { $0.upAction = "" }),
            ("discrete-right-pointer-free", scene(focus: .right) { $0.freezePointer = false }),
        ]
        for (name, scene) in cases {
            try write("\(name)-light", scene, dark: false)
            try write("\(name)-dark", scene, dark: true)
        }
    }

    /// Twelve moments of the loop, two to a row, each with what it shows and when.
    private func contactSheet(title: String, scene: GesturePreviewScene, dark: Bool) throws -> NSBitmapImageRep {
        let loop = Loop(scene: scene)
        var moments: [(label: String, time: TimeInterval?)] = []
        for (index, leg) in loop.legs.prefix(2).enumerated() {
            let start = loop.starts[index]
            let name = leg.direction.map { "\($0)" } ?? "click"
            let prefix = "leg \(index + 1) (\(name))"
            switch leg.kind {
            case .follow:
                moments += [
                    ("\(prefix): pressed", start + Loop.pressTime + 0.1),
                    ("\(prefix): moving", start + 0.85),
                    ("\(prefix): half-way stop", start + 1.4),
                    ("\(prefix): let go", start + Loop.followRelease + 0.1),
                    ("\(prefix): settled", start + Loop.followReturnStart + 0.2),
                ]
            case .move, .click:
                let fire = leg.fireTime ?? Loop.moveEnd
                moments += [
                    ("\(prefix): pressed", start + Loop.pressTime + 0.1),
                    ("\(prefix): action runs", start + fire + 0.15),
                    ("\(prefix): action shown", start + leg.stillTime),
                    ("\(prefix): back", start + leg.length - 0.3),
                ]
            }
        }
        moments.append(("Reduce Motion: the still frame", nil))
        if moments.count % 2 == 1 {
            moments.insert(("start", 0.05), at: 0)
        }

        let size = self.size
        let columns = 2
        let rows = (moments.count + columns - 1) / columns
        let pad: CGFloat = 16, label: CGFloat = 16, header: CGFloat = 26
        let sheetSize = NSSize(
            width: pad + CGFloat(columns) * (size.width + pad),
            height: header + CGFloat(rows) * (size.height + label + pad) + pad
        )
        let scale: CGFloat = 2
        let sheet = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(sheetSize.width * scale), pixelsHigh: Int(sheetSize.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        sheet.size = sheetSize
        let pictures = try moments.map { try render(scene, dark: dark, time: $0.time) }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
        (dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.925, alpha: 1)).setFill()
        NSRect(origin: .zero, size: sheetSize).fill()
        let ink = dark ? NSColor(white: 1, alpha: 0.8) : NSColor(white: 0, alpha: 0.75)
        let heading = String(format: "%@  ·  %.0f × %.0f pt  ·  loop %.2f s, %d holds", title, size.width, size.height, loop.length, loop.legs.count)
        NSAttributedString(string: heading, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: ink,
        ]).draw(at: NSPoint(x: pad, y: sheetSize.height - header + 6))
        for (index, moment) in moments.enumerated() {
            let x = pad + CGFloat(index % columns) * (size.width + pad)
            let top = sheetSize.height - header - CGFloat(index / columns) * (size.height + label + pad)
            pictures[index].draw(
                in: NSRect(x: x, y: top - label - size.height, width: size.width, height: size.height),
                from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil
            )
            let text = moment.time.map { String(format: "%@  ·  t = %.2f s", moment.label, $0) } ?? moment.label
            NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: 10), .foregroundColor: ink,
            ]).draw(at: NSPoint(x: x, y: top - label + 2))
        }
        NSGraphicsContext.current?.flushGraphics()
        return sheet
    }
}
