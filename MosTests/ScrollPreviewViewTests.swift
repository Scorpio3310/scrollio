//
//  ScrollPreviewViewTests.swift
//  MosTests
//
//  The picture at the top of the Scrolling tab (ScrollPreviewView): that it builds, when
//  its timer runs, that a changed scene restarts the demo, what Reduce Motion shows, and
//  that it draws off screen in light and dark. Nothing is shown on screen: windows are
//  created but never ordered in, and frames are asked for by loop time, not waited for.
//
//  With SCROLL_PREVIEW_SHOTS set to a directory, `testContactSheets` also writes contact
//  sheets of the demo there, for a look at the artwork:
//  TEST_RUNNER_SCROLL_PREVIEW_SHOTS=/some/dir xcodebuild … test -only-testing:MosTests/ScrollPreviewViewTests/testContactSheets
//

import XCTest
@testable import Mos_Debug

final class ScrollPreviewViewTests: XCTestCase {

    private typealias Motion = ScrollPreviewMotion
    private typealias Loop = ScrollPreviewLoop

    private let size = NSSize(width: 560, height: ScrollPreviewView.preferredHeight)

    private func makeView(reduceMotion: Bool = false, size: NSSize? = nil) -> ScrollPreviewView {
        let view = ScrollPreviewView(frame: NSRect(origin: .zero, size: size ?? self.size))
        view.prefersReducedMotion = { reduceMotion }
        view.reduceMotionDidChange()
        // The test windows are never shown, so none of them is ever really visible.
        view.isWindowVisible = { _ in true }
        return view
    }

    /// Puts the view into a window that is never shown.
    @discardableResult
    private func host(_ view: ScrollPreviewView) -> NSWindow {
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

    private func descendants<T: NSView>(of view: NSView, as type: T.Type = T.self) -> [T] {
        return view.subviews.flatMap { subview -> [T] in
            ((subview as? T).map { [$0] } ?? []) + descendants(of: subview, as: type)
        }
    }

    private func scene(_ emphasis: ScrollPreviewView.Emphasis, speed: Double = 2.7) -> ScrollPreviewView.Scene {
        var scene = ScrollPreviewView.Scene()
        scene.emphasis = emphasis
        scene.speed = speed
        return scene
    }

    private func page(of view: ScrollPreviewView) throws -> ScrollPreviewPage {
        return try XCTUnwrap(descendants(of: view, as: ScrollPreviewPage.self).first)
    }

    private func key(of view: ScrollPreviewView) throws -> ScrollPreviewKeyCap {
        return try XCTUnwrap(descendants(of: view, as: ScrollPreviewKeyCap.self).first)
    }

    private func assertSame(
        _ a: ScrollPreviewLoop.Frame, _ b: ScrollPreviewLoop.Frame,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(Double(a.offset.x), Double(b.offset.x), accuracy: 1e-6, file: file, line: line)
        XCTAssertEqual(Double(a.offset.y), Double(b.offset.y), accuracy: 1e-6, file: file, line: line)
        XCTAssertEqual(a.wheelTurn, b.wheelTurn, accuracy: 1e-6, file: file, line: line)
        XCTAssertEqual(a.pulse, b.pulse, accuracy: 1e-6, file: file, line: line)
        XCTAssertEqual(a.keyDepth, b.keyDepth, accuracy: 1e-6, file: file, line: line)
        XCTAssertEqual(a.isAtRest, b.isAtRest, file: file, line: line)
    }

    // MARK: - Building

    func testItBuildsTwoCardsSideBySide() throws {
        let view = makeView()
        XCTAssertEqual(ScrollPreviewView.preferredHeight, 150)
        XCTAssertEqual(view.intrinsicContentSize.height, 150)
        XCTAssertEqual(view.intrinsicContentSize.width, NSView.noIntrinsicMetric)

        let device = try XCTUnwrap(descendants(of: view, as: ScrollPreviewDeviceCard.self).first)
        let screen = try XCTUnwrap(descendants(of: view, as: ScrollPreviewScreenCard.self).first)
        XCTAssertEqual(device.frame, NSRect(x: 0, y: 0, width: 274, height: 150))
        XCTAssertEqual(screen.frame, NSRect(x: 286, y: 0, width: 274, height: 150))

        XCTAssertEqual(descendants(of: view, as: ScrollPreviewMouse.self).count, 1)
        XCTAssertEqual(descendants(of: view, as: ScrollPreviewWheel.self).count, 1)
        XCTAssertEqual(descendants(of: view, as: ScrollPreviewThumb.self).count, 1)
        XCTAssertTrue(try key(of: view).isHidden, "the plain wheel shows no key")

        // The mouse is inside its card, and the page fills the window's content area.
        let mouse = try XCTUnwrap(descendants(of: view, as: ScrollPreviewMouse.self).first)
        XCTAssertTrue(device.bounds.contains(mouse.frame))
        XCTAssertEqual(mouse.frame.midX, device.bounds.midX, accuracy: 0.5)
        let page = try page(of: view)
        let viewport = try XCTUnwrap(page.superview)
        XCTAssertTrue(viewport.clipsToBounds)
        XCTAssertTrue(screen.bounds.insetBy(dx: 10, dy: 10).contains(viewport.frame))
        XCTAssertEqual(page.frame.width, viewport.bounds.width)
    }

    /// A picture only: clicks go through it and it is not read out.
    func testItIsInert() {
        let view = makeView()
        XCTAssertNil(view.hitTest(NSPoint(x: 100, y: 75)))
        XCTAssertNil(view.hitTest(NSPoint(x: 400, y: 75)))
        XCTAssertFalse(view.isAccessibilityElement())
    }

    func testItFollowsItsWidth() throws {
        let view = makeView(size: NSSize(width: 410, height: 150))
        let device = try XCTUnwrap(descendants(of: view, as: ScrollPreviewDeviceCard.self).first)
        let screen = try XCTUnwrap(descendants(of: view, as: ScrollPreviewScreenCard.self).first)
        XCTAssertEqual(device.frame, NSRect(x: 0, y: 0, width: 199, height: 150))
        XCTAssertEqual(screen.frame, NSRect(x: 211, y: 0, width: 199, height: 150))

        view.scene = scene(.faster)
        view.setFrameSize(NSSize(width: 480, height: 150))
        XCTAssertEqual(device.frame.width, 234)
        XCTAssertEqual(screen.frame.maxX, 480)
        let mouse = try XCTUnwrap(descendants(of: view, as: ScrollPreviewMouse.self).first)
        let key = try key(of: view)
        XCTAssertTrue(device.bounds.contains(mouse.frame))
        XCTAssertTrue(device.bounds.contains(key.frame))
        XCTAssertLessThan(key.frame.midX, mouse.frame.minX, "the key is to the left of the mouse")
        // What is drawn of the pair (the views carry a margin around it) is centred in the card.
        let left = key.frame.minX + ScrollPreviewKeyCap.margin
        let right = mouse.frame.maxX - ScrollPreviewMouse.margin
        XCTAssertEqual((left + right) / 2, device.bounds.midX, accuracy: 0.5)
        XCTAssertEqual(mouse.frame.minX + ScrollPreviewMouse.margin - (key.frame.maxX - ScrollPreviewKeyCap.margin), ScrollPreviewDeviceCard.keySpacing)
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
        let plain = ScrollPreviewView(frame: NSRect(origin: .zero, size: size))
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
        view.showLoop(at: 1.0)
        XCTAssertGreaterThan(view.shownFrame.offset.y, 0)
        view.setAnimating(false)
        XCTAssertEqual(view.loopTime, 0)
        XCTAssertEqual(view.shownFrame, view.loop.frame(at: 0))
    }

    // MARK: - The scene

    func testAChangedSceneRestartsTheLoop() {
        let view = makeView()
        host(view)
        view.setAnimating(true)
        XCTAssertEqual(view.loopTime, 0)

        view.showLoop(at: 1.0)
        XCTAssertEqual(view.loopTime, 1.0, accuracy: 1e-9)
        assertSame(view.shownFrame, Loop(scene: ScrollPreviewView.Scene()).frame(at: 1.0))
        XCTAssertGreaterThan(view.shownFrame.offset.y, 0)

        view.scene.speed = 10
        XCTAssertEqual(view.loopTime, 0, "a changed scene starts the loop again")
        XCTAssertEqual(view.loop.scene, view.scene)
        XCTAssertEqual(view.shownFrame, view.loop.frame(at: 0))
        XCTAssertEqual(view.shownFrame.offset, .zero)
        XCTAssertTrue(view.isTimerRunning)

        // The new scene plays: the top speed takes the page farther.
        view.showLoop(at: view.loop.out.settleTime + 0.1)
        XCTAssertEqual(Double(view.shownFrame.offset.y), 3 * 33.6 * Motion.shownSpeed(10) * Motion.pointsPerPixel, accuracy: 1e-6)

        // Setting the same scene again is not a change.
        let time = view.loopTime
        let same = view.scene
        view.scene = same
        XCTAssertEqual(view.loopTime, time)
    }

    func testLoopTimeWrapsAround() {
        let view = makeView()
        let length = view.loop.length
        // Between two clicks: at the instant of a click the flash of the wheel jumps.
        let between = Loop.leadIn + 1.5 * Loop.clickInterval
        view.showLoop(at: length + between)
        XCTAssertEqual(view.loopTime, between, accuracy: 1e-9)
        assertSame(view.shownFrame, view.loop.frame(at: between))
        view.showLoop(at: 5 * length + view.loop.outLength + between)
        XCTAssertEqual(view.loopTime, view.loop.outLength + between, accuracy: 1e-9)
        view.showLoop(at: -0.5)
        XCTAssertEqual(view.loopTime, length - 0.5, accuracy: 1e-9)
    }

    func testTheSceneDecidesTheKeyAndThePage() throws {
        let view = makeView()
        let key = try key(of: view)
        let page = try page(of: view)
        let viewport = try XCTUnwrap(page.superview)
        let travel = CGFloat(Motion.travel)

        XCTAssertTrue(key.isHidden)
        XCTAssertEqual(page.frame.size, NSSize(width: viewport.bounds.width, height: viewport.bounds.height + travel))

        for (emphasis, glyph) in [(ScrollPreviewView.Emphasis.faster, "⌥"), (.sideways, "⇧"), (.paused, "⌘")] {
            view.scene = scene(emphasis)
            XCTAssertFalse(key.isHidden, glyph)
            XCTAssertEqual(key.glyph, glyph)
            XCTAssertEqual(ScrollPreviewDeviceCard.glyph(for: emphasis), glyph)
            if emphasis == .sideways {
                XCTAssertEqual(page.frame.size, NSSize(width: viewport.bounds.width + travel, height: viewport.bounds.height))
            } else {
                XCTAssertEqual(page.frame.size, NSSize(width: viewport.bounds.width, height: viewport.bounds.height + travel))
            }
        }

        view.scene = scene(.wheel)
        XCTAssertTrue(key.isHidden)
        XCTAssertNil(ScrollPreviewDeviceCard.glyph(for: .wheel))
    }

    // MARK: - The picture follows the loop

    func testThePageFollowsTheLoop() throws {
        let view = makeView()
        let page = try page(of: view)
        let thumb = try XCTUnwrap(descendants(of: view, as: ScrollPreviewThumb.self).first)
        XCTAssertEqual(page.frame.origin, .zero)
        let thumbAtTheTop = thumb.frame

        // On the way the page is exactly where the motion says.
        view.showLoop(at: Loop.lastClickTime + 0.05)
        XCTAssertFalse(view.shownFrame.isAtRest)
        XCTAssertEqual(page.frame.origin.y, -view.shownFrame.offset.y, accuracy: 1e-9)
        XCTAssertEqual(page.frame.origin.x, 0)
        XCTAssertLessThan(page.frame.origin.y, -5)

        // Arrived, it sits on whole pixels, within half a pixel of where it should be.
        view.showLoop(at: view.loop.out.settleTime + 0.2)
        XCTAssertTrue(view.shownFrame.isAtRest)
        XCTAssertEqual(page.frame.origin.y, -view.shownFrame.offset.y, accuracy: 0.25 + 1e-9)
        XCTAssertEqual((page.frame.origin.y * 2).rounded(), page.frame.origin.y * 2, accuracy: 1e-9)
        XCTAssertGreaterThan(thumb.frame.minY, thumbAtTheTop.minY, "the scroller thumb goes down with the page")
        XCTAssertEqual(thumb.frame.minX, thumbAtTheTop.minX)

        // Sideways it is the x axis.
        view.scene = scene(.sideways)
        XCTAssertEqual(page.frame.origin, .zero)
        let thumbAtTheLeft = thumb.frame
        XCTAssertGreaterThan(thumbAtTheLeft.width, thumbAtTheLeft.height)
        view.showLoop(at: Loop.lastClickTime + 0.05)
        XCTAssertEqual(page.frame.origin.x, -view.shownFrame.offset.x, accuracy: 1e-9)
        XCTAssertEqual(page.frame.origin.y, 0)
        XCTAssertLessThan(page.frame.origin.x, -5)
        XCTAssertGreaterThan(thumb.frame.minX, thumbAtTheLeft.minX)
    }

    func testTheKeyIsPressedWhileTheWheelTurns() throws {
        let view = makeView()
        view.scene = scene(.faster)
        let key = try key(of: view)
        XCTAssertEqual(key.depth, 0)
        view.showLoop(at: Loop.leadIn)
        XCTAssertEqual(key.depth, 1, accuracy: 1e-6)
        view.showLoop(at: view.loop.outLength - 0.05)
        XCTAssertEqual(key.depth, 0, accuracy: 1e-6)
    }

    // MARK: - Reduce Motion

    func testReduceMotionShowsAStillFrame() throws {
        var reduce = true
        let view = makeView()
        view.prefersReducedMotion = { reduce }
        view.reduceMotionDidChange()
        host(view)
        let page = try page(of: view)
        let half = CGFloat(Motion.travel / 2)

        view.setAnimating(true)
        XCTAssertFalse(view.isTimerRunning, "nothing runs with Reduce Motion on")
        XCTAssertEqual(view.shownFrame, view.loop.stillFrame)
        XCTAssertEqual(page.frame.origin, NSPoint(x: 0, y: -half), "the page rests half-way")

        // A changed scene changes the still frame, and still nothing runs.
        view.scene = scene(.sideways)
        XCTAssertFalse(view.isTimerRunning)
        XCTAssertEqual(view.shownFrame, view.loop.stillFrame)
        XCTAssertEqual(page.frame.origin, NSPoint(x: -half, y: 0))
        XCTAssertEqual(try key(of: view).depth, 1, "the key is shown held")

        // Reduce Motion off: the demo starts from the beginning.
        reduce = false
        view.reduceMotionDidChange()
        XCTAssertTrue(view.isTimerRunning)
        XCTAssertEqual(view.shownFrame, view.loop.frame(at: 0))
        XCTAssertEqual(page.frame.origin, .zero)

        // And on again while it runs.
        reduce = true
        view.reduceMotionDidChange()
        XCTAssertFalse(view.isTimerRunning)
        XCTAssertEqual(view.shownFrame, view.loop.stillFrame)
    }

    // MARK: - Drawing

    /// One picture of the view, rendered off screen.
    private func render(
        _ scene: ScrollPreviewView.Scene, dark: Bool, time: TimeInterval?, size: NSSize? = nil
    ) throws -> NSBitmapImageRep {
        let view = makeView(reduceMotion: time == nil, size: size)
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

    func testItDrawsInLightAndDark() throws {
        let light = try render(scene(.wheel), dark: false, time: 0)
        let dark = try render(scene(.wheel), dark: true, time: 0)
        XCTAssertEqual(light.size, size)
        XCTAssertGreaterThanOrEqual(light.pixelsWide, 560)

        // The palm of the mouse (left card) and the margin of the page in the window (right card).
        let mouse = (x: CGFloat(137), y: CGFloat(105))
        let paper = (x: CGFloat(286 + 22 + 5), y: CGFloat(90))
        XCTAssertGreaterThan(try colour(in: light, x: mouse.x, y: mouse.y).whiteComponentOfRGB, 0.9)
        XCTAssertGreaterThan(try colour(in: light, x: paper.x, y: paper.y).whiteComponentOfRGB, 0.9)
        XCTAssertLessThan(try colour(in: dark, x: mouse.x, y: mouse.y).whiteComponentOfRGB, 0.45)
        XCTAssertLessThan(try colour(in: dark, x: paper.x, y: paper.y).whiteComponentOfRGB, 0.3)
        for rep in [light, dark] {
            XCTAssertEqual(try colour(in: rep, x: mouse.x, y: mouse.y).alphaComponent, 1, accuracy: 0.01)
            // Between the cards nothing is drawn.
            XCTAssertEqual(try colour(in: rep, x: 280, y: 75).alphaComponent, 0, accuracy: 0.01)
            // The desktop has colour.
            let desktop = try colour(in: rep, x: 286 + 8, y: 140)
            XCTAssertGreaterThan(desktop.blueComponent, desktop.redComponent + 0.1)
        }
    }

    func testThePictureChangesWithTheLoop() throws {
        for emphasis in [ScrollPreviewView.Emphasis.wheel, .sideways] {
            let loop = Loop(scene: scene(emphasis))
            let start = try render(scene(emphasis), dark: false, time: 0)
            let arrived = try render(scene(emphasis), dark: false, time: loop.out.settleTime + 0.5)
            let again = try render(scene(emphasis), dark: false, time: loop.length)
            XCTAssertNotEqual(try pixels(of: start), try pixels(of: arrived), "the page has moved")
            XCTAssertEqual(try pixels(of: start), try pixels(of: again), "and is back after a round")
        }
        // The wheel flashes at a click.
        let loop = Loop(scene: scene(.wheel))
        let before = try render(scene(.wheel), dark: false, time: Loop.leadIn - 0.05)
        let click = try render(scene(.wheel), dark: false, time: Loop.leadIn + 0.02)
        XCTAssertNotEqual(try pixels(of: before), try pixels(of: click))
        XCTAssertGreaterThan(loop.frame(at: Loop.leadIn + 0.02).pulse, 0.9)
    }

    /// Every scene paints both cards, moving and still, in light and in dark.
    func testEverySceneDraws() throws {
        for emphasis in [ScrollPreviewView.Emphasis.wheel, .faster, .sideways, .paused] {
            for dark in [false, true] {
                for time in [Loop.leadIn + Loop.clickInterval + 0.03, nil] as [TimeInterval?] {
                    let rep = try render(scene(emphasis), dark: dark, time: time)
                    let message = "\(emphasis), dark \(dark), at \(String(describing: time))"
                    // The left card is a faint tint of the pane behind it; the palm of the mouse
                    // (under this point with and without a key beside it) and the desktop are solid.
                    XCTAssertGreaterThan(try colour(in: rep, x: 12, y: 12).alphaComponent, 0.02, message)
                    XCTAssertLessThan(try colour(in: rep, x: 12, y: 12).alphaComponent, 0.2, message)
                    XCTAssertEqual(try colour(in: rep, x: 150, y: 110).alphaComponent, 1, accuracy: 0.01, message)
                    XCTAssertEqual(try colour(in: rep, x: 548, y: 138).alphaComponent, 1, accuracy: 0.01, message)
                }
            }
        }
    }

    // MARK: - Contact sheets

    /// Writes contact sheets of the demo when SCROLL_PREVIEW_SHOTS names a directory.
    func testContactSheets() throws {
        guard let path = ProcessInfo.processInfo.environment["SCROLL_PREVIEW_SHOTS"], !path.isEmpty else {
            throw XCTSkip("SCROLL_PREVIEW_SHOTS is not set")
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        func write(_ name: String, _ scene: ScrollPreviewView.Scene, dark: Bool, size: NSSize? = nil) throws {
            let sheet = try contactSheet(title: name, scene: scene, dark: dark, size: size ?? self.size)
            let data = try XCTUnwrap(sheet.representation(using: .png, properties: [:]))
            try data.write(to: directory.appendingPathComponent("\(name).png"))
        }

        let emphases: [(String, ScrollPreviewView.Emphasis)] = [
            ("wheel", .wheel), ("faster", .faster), ("sideways", .sideways), ("paused", .paused),
        ]
        for (name, emphasis) in emphases {
            try write("\(name)-light", scene(emphasis), dark: false)
            try write("\(name)-dark", scene(emphasis), dark: true)
        }

        var off = scene(.wheel)
        off.smoothing = false
        var reversed = scene(.wheel)
        reversed.reversed = true
        var short = scene(.wheel)
        short.duration = 1.5
        var long = scene(.wheel)
        long.duration = 4.6
        try write("option-smoothing-off-light", off, dark: false)
        try write("option-reversed-light", reversed, dark: false)
        try write("option-speed-1-light", scene(.wheel, speed: 1), dark: false)
        try write("option-speed-10-dark", scene(.wheel, speed: 10), dark: true)
        try write("option-duration-1.5-light", short, dark: false)
        try write("option-duration-4.6-dark", long, dark: true)
        try write("width-410-sideways-light", scene(.sideways), dark: false, size: NSSize(width: 410, height: 150))
        try write("width-410-faster-dark", scene(.faster), dark: true, size: NSSize(width: 410, height: 150))
    }

    /// Ten moments of the loop, two to a row, each with what it shows and when.
    private func contactSheet(
        title: String, scene: ScrollPreviewView.Scene, dark: Bool, size: NSSize
    ) throws -> NSBitmapImageRep {
        let loop = Loop(scene: scene)
        let lead = Loop.leadIn
        let gap = Loop.clickInterval
        let moments: [(label: String, time: TimeInterval?)] = [
            ("start", 0.05),
            ("before the first click", lead - 0.08),
            ("click 1 +40 ms", lead + 0.04),
            ("click 2 +40 ms", lead + gap + 0.04),
            ("click 3 +60 ms", lead + 2 * gap + 0.06),
            ("click 3 +250 ms", lead + 2 * gap + 0.25),
            ("arrived +0.5 s", loop.out.settleTime + 0.5),
            ("back: click 1 +40 ms", loop.outLength + lead + 0.04),
            ("back: click 3 +120 ms", loop.outLength + lead + 2 * gap + 0.12),
            ("Reduce Motion: the still frame", nil),
        ]
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
        let pictures = try moments.map { try render(scene, dark: dark, time: $0.time, size: size) }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
        // About the background of a preferences pane.
        (dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.925, alpha: 1)).setFill()
        NSRect(origin: .zero, size: sheetSize).fill()
        let ink = dark ? NSColor(white: 1, alpha: 0.8) : NSColor(white: 0, alpha: 0.75)
        let heading = String(
            format: "%@  ·  %.0f × %.0f pt  ·  loop %.2f s (page arrives %.2f s into each half)",
            title, size.width, size.height, loop.length, loop.out.settleTime
        )
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

private extension NSColor {
    /// The mean of red, green and blue.
    var whiteComponentOfRGB: CGFloat {
        return (redComponent + greenComponent + blueComponent) / 3
    }
}
