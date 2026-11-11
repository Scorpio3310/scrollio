//
//  GesturePreviewView.swift
//  Mos
//  The picture at the top of the Gestures tab: on the left the connected mouse (its
//  model's drawing, MouseArtwork.swift) whose gesture button is held while the hand moves it, on the right a small desktop that answers as the settings
//  say (the desktops follow the hand, Mission Control opens, the app grid shows, a Space
//  changes, or the action's icon pulses). Built like the Scrolling tab's preview.
//
//  The view only keeps time: it asks GesturePreviewLoop for the picture at the current
//  moment and hands it to the artwork (GesturePreviewArtwork.swift). Nothing runs while it
//  is not asked to animate, has no window, its window cannot be seen (minimised, hidden, or
//  covered by other windows), it is scrolled out of the visible part of the pane, or Reduce
//  Motion is on. It is a drawing: it never runs an action or touches Spaces.
//

import Cocoa
import QuartzCore

final class GesturePreviewView: NSView {

    /// Changing it restarts the demo loop at once.
    var scene = GesturePreviewScene() {
        didSet {
            guard scene != oldValue else { return }
            loop = GesturePreviewLoop(scene: scene)
            restartLoop()
        }
    }

    static let preferredHeight: CGFloat = 150
    /// Between the two cards.
    static let cardSpacing: CGFloat = 12

    /// Reduce Motion in System Settings › Accessibility. A seam for the tests; call
    /// `reduceMotionDidChange()` after replacing it.
    var prefersReducedMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Some of `window` shows on screen: not minimised, not hidden, not covered by other
    /// windows. A seam for the tests; call `occlusionDidChange()` after replacing it.
    var isWindowVisible: (NSWindow) -> Bool = { $0.occlusionState.contains(.visible) }
    /// The window whose occlusion is followed.
    private weak var observedWindow: NSWindow?
    /// The clip view of the scroll view the preview sits in (the pane's column), whose
    /// scrolling and resizing are followed.
    private weak var observedClipView: NSClipView?

    /// The drawing for the connected mouse. A seam for the tests and renders; call
    /// `reloadMouse()` after replacing it. The preview follows a mouse coming and going.
    var mouseSource: () -> MouseArtworkModel = {
        MouseArtworkModel.model(forDeviceName: MousePaneModel.shownMouse()?.deviceName)
    }

    private(set) var loop = GesturePreviewLoop(scene: GesturePreviewScene())
    /// The moment of the loop that is on screen (seconds from its start).
    private(set) var loopTime: TimeInterval = 0
    /// What is on screen.
    private(set) var shownFrame = GesturePreviewLoop(scene: GesturePreviewScene()).frame(at: 0)

    let deviceCard = GesturePreviewDeviceCard()
    let screenCard = GesturePreviewScreenCard()

    private var wantsAnimation = false
    private var frameLink: CADisplayLink?
    /// Display time at which the running loop began; nil until its first frame.
    private var loopOrigin: CFTimeInterval?

    // MARK: - Life cycle

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    deinit {
        frameLink?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    private func setUp() {
        addSubview(deviceCard)
        addSubview(screenCard)
        // A picture only: nothing to read out and nothing to click.
        setAccessibilityElement(false)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(reduceMotionDidChange),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil
        )
        for name in [LogiCenter.sessionChanged, LogiCenter.mouseStateChanged] {
            NotificationCenter.default.addObserver(self, selector: #selector(reloadMouse), name: name, object: nil)
        }
        reloadMouse()
        layoutCards()
        showResting()
    }

    override var isFlipped: Bool { return true }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: NSView.noIntrinsicMetric, height: Self.preferredHeight)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutCards()
        show(shownFrame)
        visibleRectDidChange()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeOcclusion(of: window)
        observeScrolling(in: window == nil ? nil : enclosingScrollView?.contentView)
        updateTimer()
    }

    /// Follows the scroll view the preview sits in: the demo pauses while the preview is
    /// scrolled out of sight. (The pane host's clip view posts its bounds changes.)
    private func observeScrolling(in clipView: NSClipView?) {
        guard clipView !== observedClipView else { return }
        let names = [NSView.boundsDidChangeNotification, NSView.frameDidChangeNotification]
        if let old = observedClipView {
            for name in names {
                NotificationCenter.default.removeObserver(self, name: name, object: old)
            }
        }
        observedClipView = clipView
        if let clipView {
            for name in names {
                NotificationCenter.default.addObserver(
                    self, selector: #selector(visibleRectDidChange), name: name, object: clipView
                )
            }
        }
    }

    /// Follows whether the window can be seen: the demo pauses while it cannot.
    private func observeOcclusion(of window: NSWindow?) {
        guard window !== observedWindow else { return }
        if let old = observedWindow {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: old)
        }
        observedWindow = window
        if let window {
            NotificationCenter.default.addObserver(
                self, selector: #selector(occlusionDidChange),
                name: NSWindow.didChangeOcclusionStateNotification, object: window
            )
        }
    }

    // MARK: - Running

    /// The tab calls this with true when it appears and with false when it disappears.
    func setAnimating(_ on: Bool) {
        wantsAnimation = on
        if on {
            reloadMouse()
        }
        updateTimer()
    }

    /// Draws the mouse `mouseSource` gives now.
    @objc func reloadMouse() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.reloadMouse() }
            return
        }
        deviceCard.model = mouseSource()
    }

    /// The display-synchronised timer is running.
    var isTimerRunning: Bool {
        return frameLink != nil
    }

    @objc func reduceMotionDidChange() {
        updateTimer()
    }

    /// The window was minimised, hidden or covered, or shows again.
    @objc func occlusionDidChange() {
        updateTimer()
    }

    /// The pane was scrolled or resized, or the preview got its size: it may have left the
    /// visible part of the pane, or come back. Only a change starts or stops the timer.
    @objc func visibleRectDidChange() {
        guard shouldAnimate != isTimerRunning else { return }
        updateTimer()
    }

    /// Asked to animate, in a window that can be seen, some of it in the visible part of the
    /// pane, and Reduce Motion off.
    private var shouldAnimate: Bool {
        guard wantsAnimation, let window, isWindowVisible(window), isInVisiblePart else { return false }
        return !prefersReducedMotion()
    }

    /// Some of the preview lies in the visible part of its window and of the scroll view it
    /// sits in. (`visibleRect` alone is not clipped to the view's own bounds.)
    private var isInVisiblePart: Bool {
        return !visibleRect.intersection(bounds).isEmpty
    }

    /// Starts or stops the timer. Stopped, the picture rests: at the start of the loop, or,
    /// with Reduce Motion, on the still frame.
    private func updateTimer() {
        if shouldAnimate {
            guard frameLink == nil else { return }
            loopOrigin = nil
            showLoop(at: 0)
            let link = displayLink(target: self, selector: #selector(displayLinkDidFire(_:)))
            link.add(to: .main, forMode: .common)
            frameLink = link
        } else {
            frameLink?.invalidate()
            frameLink = nil
            loopOrigin = nil
            showResting()
        }
    }

    /// Back to the start of the loop: a changed scene shows its effect at once.
    private func restartLoop() {
        loopOrigin = nil
        if isTimerRunning {
            showLoop(at: 0)
        } else {
            showResting()
        }
    }

    @objc private func displayLinkDidFire(_ link: CADisplayLink) {
        let now = link.targetTimestamp
        let origin = loopOrigin ?? now
        loopOrigin = origin
        showLoop(at: now - origin)
    }

    // MARK: - Showing

    /// Shows the loop `time` seconds after its start (wrapping around its length).
    func showLoop(at time: TimeInterval) {
        let length = loop.length
        var wrapped = time.isFinite && length > 0 ? time.truncatingRemainder(dividingBy: length) : 0
        if wrapped < 0 { wrapped += length }
        loopTime = wrapped
        show(loop.frame(at: wrapped))
    }

    private func showResting() {
        loopTime = 0
        show(prefersReducedMotion() ? loop.stillFrame : loop.frame(at: 0))
    }

    private func show(_ frame: GesturePreviewLoop.Frame) {
        shownFrame = frame
        deviceCard.show(frame)
        screenCard.show(frame)
    }

    private func layoutCards() {
        let width = max(0, floor((bounds.width - Self.cardSpacing) / 2))
        deviceCard.frame = NSRect(x: 0, y: 0, width: width, height: bounds.height)
        screenCard.frame = NSRect(x: bounds.width - width, y: 0, width: width, height: bounds.height)
    }
}
