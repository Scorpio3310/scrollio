//
//  GesturePreviewViewTests.swift
//  MosTests
//
//  The picture at the top of the Gestures tab (GesturePreviewView): that it builds, when
//  its timer runs, that a changed scene restarts the demo, what Reduce Motion shows, that
//  the mouse and the desktop follow the loop, and that it draws off screen in light and
//  dark; for a row that follows the hand up or down, that its view stands half open at the
//  stop and under Reduce Motion, that the mouse and its arrow stay in their card, and what
//  Show Desktop draws. Nothing is shown on screen: windows are created but never ordered
//  in, and frames are asked for by loop time, not waited for. Nothing runs a real action.
//
//  With the render tests' switch set (`RenderShots`), `testContactSheets` also writes contact
//  sheets of the demo into `gesture-preview` in that folder, for a look at the artwork, and
//  `testRenderFollowedRows` single pictures of the rows that follow, four times their size:
//  TEST_RUNNER_SCROLLIO_SHOTS_DIR=/some/dir xcodebuild … test -only-testing:ScrollioTests/GesturePreviewViewTests/testContactSheets
//

import XCTest
@testable import Scrollio_Debug

final class GesturePreviewViewTests: XCTestCase {

    private typealias Loop = GesturePreviewLoop

    /// The width the preview has in the tab (520 pt pane, 20 pt margins).
    private let size = NSSize(width: 480, height: GesturePreviewView.preferredHeight)

    private func makeView(
        reduceMotion: Bool = false, size: NSSize? = nil, mouse: MouseArtworkModel = .mxMaster4,
        picture: TriggerPictureSource = .none
    ) -> GesturePreviewView {
        let view = GesturePreviewView(frame: NSRect(origin: .zero, size: size ?? self.size))
        view.mouseSource = { mouse }
        view.reloadMouse()
        view.picture = picture
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

    /// The button the tests that hold "the gesture button" hold: the model's gesture
    /// button, Back on a mouse without one (the plain mouse, the MX Anywhere, the MX Vertical).
    private func gestureButton(on model: MouseArtworkModel) -> TriggerPictureSource {
        let code = model.has(.gesture) ? LogiCenter.shared.scrollioCode(for: .gesture) : 3
        return TriggerPictureSource(event: RecordedEvent(type: .mouse, code: code, modifiers: 0, deviceFilter: nil))
    }

    private func trigger(_ role: LogiControlRole, modifiers: UInt = 0) -> TriggerPictureSource {
        let event = RecordedEvent(type: .mouse, code: LogiCenter.shared.scrollioCode(for: role), modifiers: modifiers, deviceFilter: nil)
        return TriggerPictureSource(event: event)
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

    /// "Follow the hand" with "Up and Down follow the hand too" on, on a Mac where Mission
    /// Control, Show Desktop and Apps all follow (a value: this Mac is not asked).
    private func followScene(
        focus: MouseGestureSettingsControls.Slot? = nil,
        configure: (inout MouseGestureSettings) -> Void = { _ in }
    ) -> GesturePreviewScene {
        var gesture = MouseGestureSettings.default
        gesture.mode = .interactive
        gesture.actionsFollowHand = true
        configure(&gesture)
        let everything = DockFollowAvailability(
            swipeIsAvailable: true, canPostEvents: true, majorVersion: 27, switches: .allOn, appsMayFollow: true
        )
        return GesturePreviewScene(gesture: gesture, focus: focus, availability: everything)
    }

    /// Show Desktop on the Up row, following.
    private var showDesktopScene: GesturePreviewScene {
        return followScene(focus: .up) { $0.upAction = SystemShortcut.showDesktop.identifier }
    }

    /// The moment the hand stands still half-way, and one at which a followed view is whole.
    private let stopTime = (Loop.followFirstStopEnd + Loop.followSecondStart) / 2
    private let wholeTime = Loop.followRelease + Loop.followSettle + 0.3

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

    // MARK: - A row that follows the hand up or down

    func testARowThatFollowsShowsItsViewHalfOpenAtTheStop() {
        let view = makeView()
        let mouse = view.deviceCard.mouse
        let home = mouse.frame.origin
        view.scene = followScene(focus: .up)
        view.showLoop(at: stopTime)
        XCTAssertEqual(view.screenCard.shown, view.shownFrame)
        XCTAssertEqual(view.screenCard.shown?.overview ?? 0, 0.5, accuracy: 1e-9)
        XCTAssertEqual(mouse.frame.origin.x, home.x, accuracy: 1e-9)
        XCTAssertEqual(mouse.frame.origin.y, home.y - view.loop.followVerticalTravel / 2, accuracy: 0.5, "up is towards the top of the card")
        let arrow = view.deviceCard.arrowSegment
        XCTAssertLessThan(arrow?.to.y ?? 0, arrow?.from.y ?? 0, "the arrow points up")

        view.scene = followScene(focus: .down)
        view.showLoop(at: stopTime)
        XCTAssertEqual(view.screenCard.shown?.appGrid ?? 0, 0.5, accuracy: 1e-9)
        XCTAssertEqual(mouse.frame.origin.y, home.y + view.loop.followVerticalTravel / 2, accuracy: 0.5)

        view.scene = showDesktopScene
        view.showLoop(at: stopTime)
        XCTAssertEqual(view.screenCard.shown?.showDesktop ?? 0, 0.5, accuracy: 1e-9)
        view.showLoop(at: view.loop.length - 0.05)
        XCTAssertEqual(view.screenCard.shown?.showDesktop ?? 1, 0)
        XCTAssertEqual(mouse.frame.origin, home)
    }

    /// The longest way the hand goes (the slowest Swipe speed), at the moment it lets go:
    /// every mouse, in the view it is held in, and the arrow ahead of it are inside the card.
    func testTheMouseAndItsArrowStayInTheCardWhileARowFollows() {
        for model in MouseArtworkModel.allCases {
            for picture in [TriggerPictureSource.none, gestureButton(on: model)] {
                for focus in [MouseGestureSettingsControls.Slot.up, .down] {
                    let view = makeView(mouse: model, picture: picture)
                    view.scene = followScene(focus: focus) { $0.trackingSpeed = MouseGestureSettings.trackingSpeedRange.lowerBound }
                    XCTAssertEqual(view.loop.followVerticalTravel, Loop.followVerticalTravelRange.upperBound)
                    view.showLoop(at: Loop.followRelease)
                    let card = view.deviceCard
                    let mouse = card.mouse
                    let outline = mouse.outlineRect.offsetBy(dx: mouse.frame.minX, dy: mouse.frame.minY)
                    let message = "\(model), held \(picture == .none ? "nothing" : "its button"), \(focus)"
                    XCTAssertEqual(view.shownFrame.arrow, 1, accuracy: 1e-9, message)
                    XCTAssertFalse(card.arrowView.isHidden, message)
                    XCTAssertTrue(card.bounds.contains(card.arrowView.frame), "the arrow \(card.arrowView.frame): \(message)")
                    XCTAssertTrue(card.bounds.insetBy(dx: 1, dy: 1).contains(outline), "the mouse \(outline): \(message)")
                }
            }
        }
    }

    func testReduceMotionShowsARowThatFollowsHalfOpen() {
        let view = makeView(reduceMotion: true, picture: gestureButton(on: .mxMaster4))
        host(view)
        view.setAnimating(true)

        view.scene = followScene(focus: .up)
        XCTAssertFalse(view.isTimerRunning, "nothing runs with Reduce Motion on")
        XCTAssertEqual(view.shownFrame, view.loop.stillFrame)
        XCTAssertEqual(view.shownFrame.overview, 0.5, accuracy: 1e-9, "Mission Control half open")
        XCTAssertEqual(view.shownFrame.buttonDepth, 1, accuracy: 1e-9, "the button is shown held")
        XCTAssertEqual(view.shownFrame.mouseOffset.y, -view.loop.followVerticalTravel / 2, accuracy: 1e-9, "the mouse half-way up")
        XCTAssertEqual(view.screenCard.shown, view.shownFrame)

        view.scene = showDesktopScene
        XCTAssertFalse(view.isTimerRunning)
        XCTAssertEqual(view.shownFrame.showDesktop, 0.5, accuracy: 1e-9, "the windows half-way out")

        // The same row in "One action per hold" shows the view whole.
        var once = followScene(focus: .up)
        once.gesture.mode = .discrete
        view.scene = once
        XCTAssertEqual(view.shownFrame.overview, 1, accuracy: 1e-9)
    }

    /// Show Desktop: every window keeps its size and slides straight to an edge of the
    /// screen, where a sliver of it stays in sight; none goes down, where the Dock is; the
    /// things on the desktop lie in the part that is free then.
    func testShowDesktopSlidesTheWindowsToTheEdges() {
        typealias Card = GesturePreviewScreenCard
        let size = NSSize(width: 234, height: 150)
        let screen = NSRect(origin: .zero, size: size)
        let sliver = Card.showDesktopSliver
        let free = NSRect(
            x: sliver, y: Card.menuBarHeight + sliver,
            width: size.width - 2 * sliver, height: size.height - Card.menuBarHeight - sliver
        )
        for kind in Card.WindowKind.allCases {
            let home = Card.windowRect(kind, in: size)
            let away = Card.showDesktopRect(kind, in: size)
            XCTAssertEqual(away.size, home.size, "\(kind) keeps its size")
            XCTAssertTrue(away.minX == home.minX || away.minY == home.minY, "\(kind) slides straight")
            XCTAssertNotEqual(away, home, "\(kind)")
            XCTAssertLessThanOrEqual(away.maxY, home.maxY, "\(kind) does not go down")
            XCTAssertFalse(away.intersection(screen).isEmpty, "a sliver of \(kind) stays in sight")
            XCTAssertFalse(away.intersects(free), "\(kind) is out of the way")
        }
        XCTAssertEqual(Card.showDesktopRect(.article, in: size).maxX, sliver, "the window on the left goes left")
        XCTAssertEqual(Card.showDesktopRect(.notes, in: size).minX, size.width - sliver, "the one on the right goes right")
        XCTAssertEqual(Card.showDesktopRect(.photos, in: size).maxY, Card.menuBarHeight + sliver, "the one in the middle goes up, under the menu bar")

        let items = Card.desktopItemRects(in: size)
        XCTAssertEqual(items.count, Card.desktopItemCount)
        for (index, item) in items.enumerated() {
            XCTAssertTrue(free.insetBy(dx: 4, dy: 4).contains(item), "item \(index)")
            XCTAssertLessThan(item.maxY + 8, size.height - Card.dockHeight - 4, "above the Dock, with its name: item \(index)")
            if index > 0 {
                XCTAssertGreaterThan(item.minY, items[index - 1].maxY + 6, "room for the name of the one above")
            }
        }
    }

    /// A frame that only moves the windows redraws the desktop; one that only moves the
    /// mouse does not.
    func testTheDesktopIsRedrawnWhileTheWindowsSlide() {
        let rest = Loop(scene: scene()).frame(at: 0)
        var slid = rest
        slid.showDesktop = 0.3
        XCTAssertFalse(GesturePreviewScreenCard.looksTheSame(rest, slid))
        var moved = rest
        moved.mouseOffset = CGPoint(x: 0, y: -4)
        moved.buttonDepth = 1
        XCTAssertTrue(GesturePreviewScreenCard.looksTheSame(rest, moved))
    }

    func testShowDesktopUncoversTheDesktop() throws {
        // Where the front window's page is at rest; a point both windows of the first
        // desktop cover at rest and neither does half-way; the sliver of the front window
        // at the left edge; the front of the first folder on the desktop.
        let page = (x: CGFloat(246 + 23), y: CGFloat(106))
        let middle = (x: CGFloat(246 + 125), y: CGFloat(66))
        let sliver = (x: CGFloat(246 + 2.5), y: CGFloat(60))
        let folder = GesturePreviewScreenCard.desktopItemRects(in: NSSize(width: 234, height: 150))[0]
        let item = (x: 246 + folder.midX, y: folder.maxY - 3)
        func isWallpaper(_ colour: NSColor) -> Bool {
            return colour.blueComponent > colour.redComponent + 0.1 && colour.alphaComponent > 0.99
        }
        func isWindow(_ colour: NSColor, dark: Bool) -> Bool {
            let isGrey = abs(colour.blueComponent - colour.redComponent) < 0.05
            return isGrey && (dark ? mean(colour) < 0.3 : mean(colour) > 0.85)
        }
        for dark in [false, true] {
            let rest = try render(showDesktopScene, dark: dark, time: 0)
            let half = try render(showDesktopScene, dark: dark, time: stopTime)
            let whole = try render(showDesktopScene, dark: dark, time: wholeTime)
            let message = dark ? "dark" : "light"

            XCTAssertTrue(isWindow(try colour(in: rest, x: page.x, y: page.y), dark: dark), message)
            XCTAssertTrue(isWindow(try colour(in: rest, x: middle.x, y: middle.y), dark: dark), message)
            XCTAssertTrue(isWallpaper(try colour(in: half, x: middle.x, y: middle.y)), "half-way the windows have parted: \(message)")
            XCTAssertTrue(isWallpaper(try colour(in: whole, x: middle.x, y: middle.y)), message)
            XCTAssertTrue(isWallpaper(try colour(in: whole, x: page.x, y: page.y)), "the desktop shows where the window was: \(message)")
            XCTAssertTrue(isWindow(try colour(in: whole, x: sliver.x, y: sliver.y), dark: dark), "a sliver of the window stays: \(message)")

            // What lies on the desktop comes up with it: a folder, bluer than the wallpaper.
            let folderShown = try colour(in: whole, x: item.x, y: item.y)
            let before = try colour(in: rest, x: item.x, y: item.y)
            XCTAssertGreaterThan(folderShown.blueComponent - folderShown.redComponent, 0.5, message)
            XCTAssertLessThan(before.blueComponent - before.redComponent, 0.45, "nothing there at rest: \(message)")

            // The menu bar and the Dock stay where they are.
            for point in [(x: CGFloat(246 + 117), y: CGFloat(4)), (x: CGFloat(246 + 117), y: CGFloat(140))] {
                XCTAssertEqual(try colour(in: rest, x: point.x, y: point.y), try colour(in: whole, x: point.x, y: point.y), message)
            }
        }
    }

    func testAFollowedRowsPictureChangesWithTheLoopAndComesBack() throws {
        let round = followScene()
        let cases: [(GesturePreviewScene, TimeInterval)] = [
            (followScene(focus: .up), stopTime),
            (followScene(focus: .down), stopTime),
            (showDesktopScene, stopTime),
            (showDesktopScene, wholeTime),
            (round, Loop(scene: round).starts[2] + stopTime),
            (round, Loop(scene: round).starts[3] + wholeTime),
        ]
        for (scene, moment) in cases {
            let loop = Loop(scene: scene)
            for dark in [false, true] {
                let start = try render(scene, dark: dark, time: 0)
                let middle = try render(scene, dark: dark, time: moment)
                let again = try render(scene, dark: dark, time: loop.length)
                XCTAssertNotEqual(try pixels(of: start), try pixels(of: middle), "\(scene)")
                XCTAssertEqual(try pixels(of: start), try pixels(of: again), "back after a round: \(scene)")
                // Both cards are painted, moving and still.
                for rep in [middle, try render(scene, dark: dark, time: nil)] {
                    XCTAssertLessThan(try colour(in: rep, x: 12, y: 12).alphaComponent, 0.2, "\(scene)")
                    XCTAssertEqual(try colour(in: rep, x: 470, y: 30).alphaComponent, 1, accuracy: 0.01, "\(scene)")
                }
            }
        }
    }

    // MARK: - Reduce Motion

    func testReduceMotionShowsAStillFrame() {
        var reduce = true
        let view = makeView(picture: gestureButton(on: .mxMaster4))
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

    /// One picture of the view, rendered off screen (`scale`: pixels per point, for a
    /// picture to look at; without it, as the view would cache itself).
    private func render(
        _ scene: GesturePreviewScene, dark: Bool, time: TimeInterval?, size: NSSize? = nil, mouse: MouseArtworkModel = .mxMaster4,
        picture: TriggerPictureSource = .none, scale: CGFloat? = nil
    ) throws -> NSBitmapImageRep {
        let view = makeView(reduceMotion: time == nil, size: size, mouse: mouse, picture: picture)
        view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        view.scene = scene
        if let time {
            view.showLoop(at: time)
        }
        guard let scale else {
            let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)
            return rep
        }
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * scale), pixelsHigh: Int(view.bounds.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        rep.size = view.bounds.size
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
    /// accent has a lighter shade in dark (#6A4EC2) than in light (#563CA6).
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
        let button = gestureButton(on: .mxMaster4)
        let up = try render(scene(focus: .click), dark: false, time: 0, picture: button)
        let held = try render(scene(focus: .click), dark: false, time: Loop.pressTime + 0.3, picture: button)
        let mouse = makeView(picture: button).deviceCard.mouse
        let mouseOrigin = mouse.frame.origin
        let rect = mouse.buttonRect
        let x = mouseOrigin.x + rect.midX, y = mouseOrigin.y + rect.midY
        let idle = try colour(in: up, x: x, y: y)
        let pressed = try colour(in: held, x: x, y: y)
        let accent = try accent(dark: false)
        func distance(_ a: NSColor, _ b: NSColor) -> CGFloat {
            return abs(a.redComponent - b.redComponent) + abs(a.greenComponent - b.greenComponent) + abs(a.blueComponent - b.blueComponent)
        }
        XCTAssertLessThan(distance(pressed, accent), distance(idle, accent))
        XCTAssertLessThan(distance(pressed, accent), 0.3)
    }

    /// A mouse whose gesture button is on its thumb side (the MX Master 4 and 3) turns to
    /// the view from there for the hold and back afterwards, as the loop says (`sideTurn`);
    /// under Reduce Motion the still shows it turned, the button held. The plain mouse does
    /// not turn.
    func testTheMasterFourTurnsToItsThumbSideForTheHold() {
        let view = makeView(mouse: .mxMaster4, picture: gestureButton(on: .mxMaster4))
        let card = view.deviceCard
        let mouse = card.mouse
        let loop = view.loop
        let press = loop.legs[0].pressTime, release = loop.legs[0].releaseTime
        card.show(loop.frame(at: 0))
        XCTAssertEqual(mouse.turn, 0)
        XCTAssertEqual(mouse.viewpoint, .above, "at rest: from above")
        card.show(loop.frame(at: press - MouseArtworkTurn.duration / 2))
        XCTAssertGreaterThan(mouse.turn, 0)
        XCTAssertLessThan(mouse.turn, 1, "turning right before the button goes down")
        card.show(loop.frame(at: press + Loop.buttonTravel))
        XCTAssertEqual(mouse.turn, 1, "from the thumb side while the button is held")
        XCTAssertEqual(mouse.viewpoint, .thumbSide)
        card.show(loop.frame(at: (press + release) / 2))
        XCTAssertEqual(mouse.turn, 1)
        // The arrow is placed by the drawing that shows.
        let outline = mouse.outlineRect.offsetBy(dx: mouse.frame.minX, dy: mouse.frame.minY)
        if let arrow = card.arrowSegment {
            XCTAssertFalse(outline.insetBy(dx: 1, dy: 1).contains(arrow.from), "the arrow starts outside the mouse")
        }
        XCTAssertTrue(card.bounds.contains(outline), "the mouse on its side stays in the card")
        card.show(loop.frame(at: release + Loop.buttonTravel + MouseArtworkTurn.duration))
        XCTAssertEqual(mouse.turn, 0, "back from above once the button is up")
        XCTAssertEqual(mouse.viewpoint, .above)

        XCTAssertEqual(loop.stillFrame.sideTurn, 1, "Reduce Motion: the still shows the button held")
        card.show(loop.stillFrame)
        XCTAssertEqual(mouse.viewpoint, .thumbSide)

        // The MX Master 3's gesture button is its thumb rest, pressed down: it shows from
        // above, so this mouse does not turn for the hold. The plain mouse has one view.
        let three = makeView(mouse: .mxMaster3, picture: gestureButton(on: .mxMaster3))
        three.deviceCard.show(three.loop.frame(at: (press + release) / 2))
        XCTAssertEqual(three.deviceCard.mouse.turn, 0)
        XCTAssertEqual(three.deviceCard.mouse.viewpoint, .above)
        XCTAssertTrue(three.deviceCard.mouse.outlineRect.contains(three.deviceCard.mouse.buttonRect))
        let plain = makeView(mouse: .generic, picture: gestureButton(on: .generic))
        plain.deviceCard.show(plain.loop.frame(at: (press + release) / 2))
        XCTAssertEqual(plain.deviceCard.mouse.turn, 0, "the plain mouse has one view")
        XCTAssertEqual(plain.deviceCard.mouse.viewpoint, .above)

        // A mouse that connects while the frame shows: turned as the frame says, at once.
        var connected = MouseArtworkModel.generic
        let late = makeView(reduceMotion: true, mouse: .generic, picture: gestureButton(on: .mxMaster4))
        late.mouseSource = { connected }
        late.reloadMouse()
        late.deviceCard.show(late.loop.stillFrame)
        XCTAssertEqual(late.deviceCard.mouse.viewpoint, .above)
        connected = .mxMaster4
        late.reloadMouse()
        XCTAssertEqual(late.deviceCard.mouse.model, .mxMaster4)
        XCTAssertEqual(late.deviceCard.mouse.turn, 1)
        XCTAssertEqual(late.deviceCard.mouse.viewpoint, .thumbSide, "the still shows the held button's side")
    }

    /// The mouse is the connected one's drawing and follows a mouse coming and going; the
    /// button held is where the model has its gesture button (the plain mouse: Back).
    func testTheMouseFollowsTheConnectedModel() throws {
        var connected = MouseArtworkModel.mxMaster4
        let view = makeView(picture: gestureButton(on: .mxMaster4))
        view.mouseSource = { connected }
        view.reloadMouse()
        let mouse = view.deviceCard.mouse
        XCTAssertEqual(mouse.model, .mxMaster4)
        // The MX Master 4's gesture button is on its thumb side: in the drawing from there.
        XCTAssertEqual(mouse.buttonViewpoint, .thumbSide)
        let four = mouse.buttonRect
        XCTAssertEqual(mouse.viewpoint, .above, "at rest the mouse is seen from above")
        mouse.show(buttonDepth: 1, pressPulse: 0, turn: 1)
        XCTAssertEqual(mouse.viewpoint, .thumbSide)
        XCTAssertTrue(mouse.outlineRect.contains(four), "on the mouse seen from its thumb side")
        XCTAssertTrue(mouse.bounds.contains(mouse.outlineRect), "the view holds the drawing from the side")
        XCTAssertEqual(mouse.outlineRect.midX, mouse.bodyRect.midX, accuracy: 1, "turned in the place of the body")
        mouse.show(buttonDepth: 0, pressPulse: 0, turn: 0)

        connected = .mxMaster3
        NotificationCenter.default.post(name: LogiCenter.mouseStateChanged, object: nil)
        XCTAssertEqual(mouse.model, .mxMaster3)
        XCTAssertNotEqual(mouse.buttonRect, four)
        XCTAssertEqual(mouse.buttonViewpoint, .above, "the thumb rest is the button, seen from above")
        XCTAssertGreaterThan(mouse.buttonRect.height, four.height, "a pad, larger than the MX Master 4's button")

        connected = .generic
        NotificationCenter.default.post(name: LogiCenter.sessionChanged, object: nil)
        XCTAssertEqual(mouse.model, .generic)
        view.picture = gestureButton(on: .generic)
        let body = mouse.bodyRect.offsetBy(dx: mouse.frame.minX, dy: mouse.frame.minY)
        XCTAssertEqual(body.midX, view.deviceCard.bounds.midX, accuracy: 0.5, "the body stays centred")
        XCTAssertLessThan(mouse.buttonRect.maxX, mouse.bodyRect.minX + 6, "the Back button, on the left side")
        // The held button takes the accent colour on every model.
        for model in MouseArtworkModel.allCases {
            let held = try render(scene(focus: .click), dark: true, time: Loop.pressTime + 0.3, mouse: model, picture: gestureButton(on: model))
            let preview = makeView(mouse: model, picture: gestureButton(on: model)).deviceCard.mouse
            let button = preview.buttonRect
            let point = preview.frame.origin
            // Most of it: lit as the Buttons card lights it, its marks (the MX Master 3's
            // ridge, the panel's dots) drawn lit on it.
            let accent = try accent(dark: true)
            var near = 0, all = 0
            for x in stride(from: button.minX + 0.25, to: button.maxX, by: 0.5) {
                for y in stride(from: button.minY + 0.25, to: button.maxY, by: 0.5) {
                    let colour = try self.colour(in: held, x: point.x + x, y: point.y + y)
                    all += 1
                    if abs(colour.redComponent - accent.redComponent) + abs(colour.greenComponent - accent.greenComponent)
                        + abs(colour.blueComponent - accent.blueComponent) < 0.3 { near += 1 }
                }
            }
            XCTAssertGreaterThan(Double(near) / Double(max(1, all)), 0.3, "\(model)")
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
    ///
    /// Measured against a reference drawn the same way in the same moments (a plain card of
    /// the same size: one gradient, one rounded outline), not against the clock: the limit
    /// of 8 ms per frame held on a fast Mac that was idle and said nothing true on a slow
    /// or a busy one. The desktop cost 4.0 times the reference when this was written (three
    /// runs: 3.99, 4.00, 4.01); three times that is the limit, the headroom the 8 ms gave.
    func testDrawingTheDesktopIsCheap() throws {
        let view = makeView()
        view.appearance = NSAppearance(named: .darkAqua)
        view.scene = scene(focus: .up)
        let card = view.screenCard
        let rep = try XCTUnwrap(card.bitmapImageRepForCachingDisplay(in: card.bounds))
        let reference = ReferenceCard(frame: card.bounds)
        let referenceRep = try XCTUnwrap(reference.bitmapImageRepForCachingDisplay(in: reference.bounds))
        let loop = view.loop
        let frames = 120
        var desktopTime: CFAbsoluteTime = 0
        var referenceTime: CFAbsoluteTime = 0
        for index in 0..<frames {
            view.showLoop(at: loop.length * Double(index) / Double(frames))
            let start = CFAbsoluteTimeGetCurrent()
            card.cacheDisplay(in: card.bounds, to: rep)
            let middle = CFAbsoluteTimeGetCurrent()
            reference.cacheDisplay(in: reference.bounds, to: referenceRep)
            desktopTime += middle - start
            referenceTime += CFAbsoluteTimeGetCurrent() - middle
        }
        let ratio = desktopTime / referenceTime
        XCTAssertLessThan(
            ratio, 12,
            "the desktop takes \(ratio) times the reference card "
                + "(\(desktopTime / Double(frames) * 1000) ms and \(referenceTime / Double(frames) * 1000) ms per frame)"
        )
    }

    /// What the desktop's drawing time is compared with.
    private final class ReferenceCard: NSView {
        override func draw(_ dirtyRect: NSRect) {
            NSGradient(starting: .darkGray, ending: .black)?.draw(in: bounds, angle: 90)
            NSColor.white.setStroke()
            let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 4), xRadius: 10, yRadius: 10)
            outline.lineWidth = 2
            outline.stroke()
        }
    }

    // MARK: - The trigger held (TriggerPicture)

    /// The view of `mouse` alone, rendered in light (the accent forced to the app's purple,
    /// so a user's grey accent cannot hide it).
    private func shot(of mouse: GesturePreviewMouse) throws -> NSBitmapImageRep {
        mouse.appearance = NSAppearance(named: .aqua)
        let rep = try XCTUnwrap(mouse.bitmapImageRepForCachingDisplay(in: mouse.bounds))
        mouse.cacheDisplay(in: mouse.bounds, to: rep)
        return rep
    }

    private func forceAppAccent() throws -> NSColor {
        try ForcedAppAccent.install()
        addTeardownBlock { ForcedAppAccent.uninstall() }
        return try accent(dark: false)
    }

    private func distance(_ a: NSColor, _ b: NSColor) -> CGFloat {
        return abs(a.redComponent - b.redComponent) + abs(a.greenComponent - b.greenComponent) + abs(a.blueComponent - b.blueComponent)
    }

    /// The owner's case: the MX Master 4 with its thumb panel bound turns to its thumb side
    /// and lights the panel, as the Buttons card does; held and with the ring at its
    /// strongest, Forward, Back and the gesture button on the panel's edge stay as they are.
    func testTheMasterFoursThumbPanelLightsAndLeavesTheButtonsOnItAlone() throws {
        let accent = try forceAppAccent()
        let view = makeView(mouse: .mxMaster4, picture: trigger(.thumbPanel))
        let mouse = view.deviceCard.mouse
        XCTAssertEqual(view.deviceCard.picture.hold, .part(.thumbPanel))
        XCTAssertEqual(mouse.buttonViewpoint, .thumbSide)
        XCTAssertEqual(view.loop.stillFrame.sideTurn, 1)
        view.deviceCard.show(view.loop.stillFrame)
        XCTAssertEqual(mouse.viewpoint, .thumbSide, "turned for the hold")

        mouse.show(buttonDepth: 0, pressPulse: 0, turn: 1)
        let rest = try shot(of: mouse)
        mouse.show(buttonDepth: 1, pressPulse: 1, turn: 1)
        let held = try shot(of: mouse)
        let panel = mouse.buttonRect
        XCTAssertLessThan(distance(try colour(in: held, x: panel.midX, y: panel.midY), accent), 0.3, "the panel is lit")
        let side = MouseArtworkShapes(model: .mxMaster4, viewpoint: .thumbSide)
        for part in [MouseArtworkPart.forward, .back, .gesture] {
            let shape = try XCTUnwrap(side.shape(of: part))
            shape.transform(using: mouse.placement(for: .thumbSide))
            let centre = NSPoint(x: shape.bounds.midX, y: shape.bounds.midY)
            let lit = try colour(in: held, x: centre.x, y: centre.y)
            XCTAssertLessThan(distance(lit, try colour(in: rest, x: centre.x, y: centre.y)), 0.03, "\(part) as when nothing is held")
            XCTAssertGreaterThan(distance(lit, accent), 0.3, "\(part) is not lit")
        }
    }

    /// The ring of a press or a release leaves the thumb wheel's roller as it is (spec
    /// §2.4): Forward and Back light right under it on the MX Master 4 and 3, the MX Master
    /// 4's thumb panel around it. (The roller lies inside its slot: one even-odd clip of
    /// both put the roller back under the ring.) Each pixel well inside the roller, with
    /// the ring at three moments of its fading, is the pixel at rest.
    func testThePressRingLeavesTheThumbWheelAlone() throws {
        _ = try forceAppAccent()
        let cases: [(model: MouseArtworkModel, role: LogiControlRole)] = [
            (.mxMaster4, .forward), (.mxMaster4, .back), (.mxMaster4, .thumbPanel), (.mxMaster3, .forward), (.mxMaster3, .back),
        ]
        for item in cases {
            let what = "\(item.model) \(item.role)"
            let mouse = makeView(mouse: item.model, picture: trigger(item.role)).deviceCard.mouse
            XCTAssertEqual(mouse.buttonViewpoint, .thumbSide, what)
            mouse.show(buttonDepth: 0, pressPulse: 0, turn: 1)
            let rest = try shot(of: mouse)
            let roller = try XCTUnwrap(MouseArtworkShapes(model: item.model, viewpoint: .thumbSide).shape(of: .thumbWheel), what)
            roller.transform(using: mouse.placement(for: .thumbSide))
            let margin: CGFloat = 0.75
            var inside: [NSPoint] = []
            for x in stride(from: roller.bounds.minX, to: roller.bounds.maxX, by: 0.5) {
                for y in stride(from: roller.bounds.minY, to: roller.bounds.maxY, by: 0.5) {
                    let around = [(0, 0), (margin, 0), (-margin, 0), (0, margin), (0, -margin)].map { NSPoint(x: x + $0.0, y: y + $0.1) }
                    if around.allSatisfy(roller.contains) {
                        inside.append(NSPoint(x: x, y: y))
                    }
                }
            }
            XCTAssertGreaterThan(inside.count, 50, what)
            for pulse in [0.8, 0.6, 0.4] {
                mouse.show(buttonDepth: 0, pressPulse: pulse, turn: 1)
                let ringed = try shot(of: mouse)
                var worst: CGFloat = 0
                for point in inside {
                    worst = max(worst, distance(try colour(in: ringed, x: point.x, y: point.y), try colour(in: rest, x: point.x, y: point.y)))
                }
                XCTAssertLessThan(worst, 0.02, "\(what), the ring at \(pulse)")
            }
        }
    }

    /// The MX Master 3 has no thumb panel: its badge, which never turns, sits inside the
    /// mouse view and moves with the mouse; held, it is pressed in.
    func testTheMasterThreesThumbPanelIsABadgeThatMovesWithTheMouse() throws {
        let accent = try forceAppAccent()
        let view = makeView(mouse: .mxMaster3, picture: trigger(.thumbPanel))
        view.scene = scene(focus: .right)
        let card = view.deviceCard, mouse = card.mouse
        XCTAssertEqual(card.picture.hold, .notDrawn(.thumbPanel))
        XCTAssertTrue(mouse.showsBadge)
        XCTAssertEqual(mouse.buttonViewpoint, .above)
        let leg = view.loop.legs[0]
        view.showLoop(at: (leg.pressTime + leg.releaseTime) / 2)
        XCTAssertEqual(mouse.turn, 0, "no turn for a badge")
        XCTAssertEqual(mouse.viewpoint, .above)
        XCTAssertTrue(mouse.bounds.insetBy(dx: 1, dy: 1).contains(mouse.badgeRect), "inside the mouse view")
        XCTAssertEqual(mouse.badgeRect.height, GesturePreviewMouse.badgeHeight)
        XCTAssertEqual(mouse.buttonRect, mouse.badgeRect)

        view.showLoop(at: 0)
        let home = mouse.frame.origin
        let badgeAtHome = mouse.badgeRect.offsetBy(dx: home.x, dy: home.y)
        view.showLoop(at: Loop.moveEnd)
        XCTAssertGreaterThan(mouse.frame.minX, home.x + 1, "the mouse moved")
        let badgeMoved = mouse.badgeRect.offsetBy(dx: mouse.frame.minX, dy: mouse.frame.minY)
        XCTAssertEqual(badgeMoved.minX - badgeAtHome.minX, mouse.frame.minX - home.x, accuracy: 1e-9, "with it")

        // Accent, and smaller while held.
        mouse.show(buttonDepth: 0, pressPulse: 0)
        let up = try shot(of: mouse)
        mouse.show(buttonDepth: 1, pressPulse: 0)
        let pressed = try shot(of: mouse)
        let badge = mouse.badgeRect
        XCTAssertLessThan(distance(try colour(in: up, x: badge.midX - 6, y: badge.midY), accent), 0.3)
        XCTAssertLessThan(distance(try colour(in: pressed, x: badge.midX - 5, y: badge.midY), accent), 0.3)
        XCTAssertNotEqual(try pixels(of: up), try pixels(of: pressed), "pressed in")
    }

    /// Nothing runs the gestures: the default picture has no accent anywhere on its card,
    /// held or not; its arrow is grey; the dashed outline is where the gesture button is.
    func testTheDefaultPictureHasNoAccent() throws {
        let accent = try forceAppAccent()
        for model in [MouseArtworkModel.mxMaster4, .generic] {
            let view = makeView(mouse: model)
            view.appearance = NSAppearance(named: .aqua)
            view.scene = scene(focus: .right)
            let card = view.deviceCard
            XCTAssertNil(card.picture.hold)
            XCTAssertEqual(card.arrowView.colour, .secondaryLabelColor)
            XCTAssertNotEqual(card.arrowView.colour, .controlAccentColor)
            XCTAssertEqual(card.mouse.heldPart, model.gesturePreviewPart, "the outline is where Set Up… usually ends")
            XCTAssertTrue(card.caps.isEmpty)
            XCTAssertTrue(card.chip.isHidden)
            // Just down: held, the ring still strong.
            let ringTime = Loop.pressTime + Loop.buttonTravel
            for time in [ringTime, Loop.moveStart + Loop.moveDuration * 0.5] {
                view.showLoop(at: time)
                XCTAssertEqual(view.shownFrame.buttonDepth, 1, accuracy: 1e-6, "held")
                let rep = try XCTUnwrap(card.bitmapImageRepForCachingDisplay(in: card.bounds))
                card.cacheDisplay(in: card.bounds, to: rep)
                var near = 0
                for x in 0..<rep.pixelsWide {
                    for y in 0..<rep.pixelsHigh {
                        guard let pixel = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), pixel.alphaComponent > 0.3 else { continue }
                        if distance(pixel, accent) < 0.3 { near += 1 }
                    }
                }
                XCTAssertEqual(near, 0, "no accent on the default card: \(model) at \(time)")
            }
            XCTAssertGreaterThan(view.loop.frame(at: ringTime).pressPulse, 0.5, "the moment of the ring was looked at")
        }
    }

    /// "⌥ Thumb panel" only in Notes: a cap per modifier in the lower-left corner, sinking
    /// with the button, and the app's icon in the upper-left one; neither is redrawn by a
    /// frame that does not change them, and the card itself is never.
    func testTheCapsAndTheChipComeWithTheTrigger() throws {
        let view = makeView(mouse: .mxMaster4)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(view)
        addTeardownBlock { window.close() }
        let notes = "/System/Applications/Notes.app"
        let option = UInt(CGEventFlags.maskAlternate.rawValue)
        var source = trigger(.thumbPanel, modifiers: option)
        source.onlyInAppPath = notes
        view.scene = scene(focus: .right)
        view.picture = source
        let card = view.deviceCard
        XCTAssertEqual(card.picture, TriggerPicture(hold: .part(.thumbPanel), modifiers: ["⌥"], appPath: notes))
        XCTAssertEqual(card.caps.map(\.label), ["⌥"])
        let cap = try XCTUnwrap(card.caps.first)
        XCTAssertEqual(cap.faceHeight, 20)
        XCTAssertEqual(cap.frame.minX + TriggerKeyCap.margin, 10, "10 pt in from the left")
        XCTAssertEqual(cap.frame.maxY - TriggerKeyCap.margin, card.bounds.height - 10, accuracy: 1e-9, "and from the bottom")
        XCTAssertFalse(card.chip.isHidden)
        XCTAssertEqual(card.chip.path, notes)
        XCTAssertEqual(card.chip.frame, NSRect(x: 8, y: 8, width: 18, height: 18))
        XCTAssertEqual(card.arrowView.colour, .controlAccentColor)
        let subviews = card.subviews
        XCTAssertLessThan(try XCTUnwrap(subviews.firstIndex(of: cap)), try XCTUnwrap(subviews.firstIndex(of: card.mouse)), "under the mouse")

        view.showLoop(at: 0)
        XCTAssertEqual(cap.depth, 0)
        view.showLoop(at: Loop.moveStart + Loop.moveDuration * 0.4)
        XCTAssertEqual(cap.depth, 1, "it sinks with the button")
        window.displayIfNeeded()
        drawPendingLayers(of: view)
        view.showLoop(at: Loop.moveStart + Loop.moveDuration * 0.6)
        XCTAssertEqual(card.layer?.needsDisplay(), false, "the card is not redrawn")
        XCTAssertEqual(cap.layer?.needsDisplay(), false, "nor the cap, which did not move")
        XCTAssertEqual(card.arrowView.layer?.needsDisplay(), true)

        // Another trigger redraws the mouse; the demo goes on where it was.
        let time = view.loopTime
        view.picture = gestureButton(on: .mxMaster4)
        XCTAssertEqual(view.loopTime, time)
        XCTAssertTrue(card.caps.isEmpty)
        XCTAssertTrue(card.chip.isHidden)
        XCTAssertEqual(card.mouse.hold, .part(.gesture))
    }

    /// A trigger is resolved for the mouse that is drawn, again when another connects.
    func testThePictureFollowsTheMouse() {
        var connected = MouseArtworkModel.mxMaster4
        let view = makeView(picture: trigger(.thumbPanel))
        view.mouseSource = { connected }
        view.reloadMouse()
        XCTAssertEqual(view.deviceCard.picture.hold, .part(.thumbPanel))
        connected = .mxMaster3
        NotificationCenter.default.post(name: LogiCenter.mouseStateChanged, object: nil)
        XCTAssertEqual(view.deviceCard.picture.hold, .notDrawn(.thumbPanel))
        XCTAssertEqual(view.deviceCard.mouse.buttonViewpoint, .above)
        view.picture = TriggerPictureSource(event: RecordedEvent(type: .mouse, code: 6, modifiers: 0, deviceFilter: nil))
        XCTAssertEqual(view.deviceCard.picture.hold, .number(6))
    }

    // MARK: - Contact sheets

    /// Writes contact sheets of the demo when the render tests are asked for (`RenderShots`).
    func testContactSheets() throws {
        let directory = try RenderShots.directory(for: "the gesture demo's contact sheets", subfolder: "gesture-preview")

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
            ("discrete-up-show-desktop", scene(focus: .up) { $0.upAction = SystemShortcut.showDesktop.identifier }),
            ("follow-up-mission-control", followScene(focus: .up)),
            ("follow-down-apps", followScene(focus: .down)),
            ("follow-up-show-desktop", showDesktopScene),
            ("follow-down-show-desktop-slow-pointer-free", followScene(focus: .down) {
                $0.downAction = SystemShortcut.showDesktop.identifier
                $0.trackingSpeed = 0.5
                $0.freezePointer = false
            }),
            ("follow-up-mission-control-fast", followScene(focus: .up) { $0.trackingSpeed = 3 }),
        ]
        for (name, scene) in cases {
            try write("\(name)-light", scene, dark: false)
            try write("\(name)-dark", scene, dark: true)
        }
        // The round with nothing pointed at: its third and fourth hold, up and down.
        for dark in [false, true] {
            let name = "follow-cycle-up-and-down-\(dark ? "dark" : "light")"
            let sheet = try contactSheet(title: name, scene: followScene(), dark: dark, legs: 2..<4)
            try XCTUnwrap(sheet.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent("\(name).png"))
        }
    }

    /// Single pictures of the rows that follow the hand, four times their size, when the
    /// render tests are asked for (`RenderShots`): Mission Control, the app grid and Show
    /// Desktop half open at the stop and whole, and the frame Reduce Motion shows, in
    /// light and in dark.
    func testRenderFollowedRows() throws {
        let directory = try RenderShots.directory(for: "the rows that follow the hand", subfolder: "gesture-preview-follow")
        let showDesktopDownSlowest = followScene(focus: .down) {
            $0.downAction = SystemShortcut.showDesktop.identifier
            $0.trackingSpeed = 0.5
        }
        var showDesktopOnce = showDesktopScene
        showDesktopOnce.gesture.mode = .discrete
        let cases: [(String, GesturePreviewScene, TimeInterval?)] = [
            ("up-mission-control-half", followScene(focus: .up), stopTime),
            ("up-mission-control-let-go", followScene(focus: .up), Loop.followRelease),
            ("up-mission-control-whole", followScene(focus: .up), wholeTime),
            ("up-mission-control-reduce-motion", followScene(focus: .up), nil),
            ("up-mission-control-slowest-let-go", followScene(focus: .up) { $0.trackingSpeed = 0.5 }, Loop.followRelease),
            ("down-apps-half", followScene(focus: .down), stopTime),
            ("down-apps-reduce-motion", followScene(focus: .down), nil),
            ("up-show-desktop-quarter", showDesktopScene, 0.8),
            ("up-show-desktop-half", showDesktopScene, stopTime),
            ("up-show-desktop-let-go", showDesktopScene, Loop.followRelease),
            ("up-show-desktop-whole", showDesktopScene, wholeTime),
            ("up-show-desktop-reduce-motion", showDesktopScene, nil),
            ("down-show-desktop-slowest-let-go", showDesktopDownSlowest, Loop.followRelease),
            ("once-show-desktop-reduce-motion", showDesktopOnce, nil),
        ]
        for (name, scene, time) in cases {
            for dark in [false, true] {
                let rep = try render(scene, dark: dark, time: time, picture: gestureButton(on: .mxMaster4), scale: 4)
                let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                try data.write(to: directory.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
            }
        }
    }

    /// Moments of the loop (of its first two holds, or of `legs`), two to a row, each with
    /// what it shows and when.
    private func contactSheet(
        title: String, scene: GesturePreviewScene, dark: Bool, legs shown: Range<Int>? = nil
    ) throws -> NSBitmapImageRep {
        let loop = Loop(scene: scene)
        var moments: [(label: String, time: TimeInterval?)] = []
        for index in (shown ?? 0..<2).clamped(to: 0..<loop.legs.count) {
            let leg = loop.legs[index]
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
                if leg.opensWithTheHand {
                    moments += [
                        ("\(prefix): whole, the mouse back", start + Loop.followReturnEnd + 0.3),
                        ("\(prefix): closing", start + Loop.followCloseStart + Loop.overlayOut / 2),
                    ]
                }
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
