//
//  ScrollPreviewView.swift
//  Mos
//  The picture at the top of the Scrolling tab: on the left a mouse whose wheel turns, on
//  the right a small desktop with a window whose page answers it. The page is moved by
//  ScrollPreviewMotion, which uses the scroll engine's own maths, so another feel or
//  speed visibly changes the demo.
//
//  The view only keeps time: it asks ScrollPreviewLoop for the picture at the current
//  moment and hands it to the artwork (ScrollPreviewArtwork.swift). Nothing runs while it
//  is not asked to animate, has no window, or Reduce Motion is on.
//

import Cocoa
import QuartzCore

final class ScrollPreviewView: NSView {

    /// What the demo is about: the plain wheel, or the wheel with one of the keys held.
    enum Emphasis { case wheel, faster, sideways, paused }

    struct Scene: Equatable {
        var smoothing = true      // false: the page jumps click by click
        var duration = 3.67       // as stored in scroll.duration (0…5 slider scale)
        var speed = 2.7           // scroll.speed (1…10)
        var reversed = false
        var emphasis: Emphasis = .wheel
    }

    /// Changing it restarts the demo loop at once.
    var scene = Scene() {
        didSet {
            guard scene != oldValue else { return }
            loop = ScrollPreviewLoop(scene: scene)
            layoutArtwork(animated: scene.emphasis != oldValue.emphasis && isTimerRunning)
            restartLoop()
        }
    }

    static let preferredHeight: CGFloat = 150
    /// Between the two cards.
    static let cardSpacing: CGFloat = 12

    /// Reduce Motion in System Settings › Accessibility. A seam for the tests; call
    /// `reduceMotionDidChange()` after replacing it.
    var prefersReducedMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private(set) var loop = ScrollPreviewLoop(scene: Scene())
    /// The moment of the loop that is on screen (seconds from its start).
    private(set) var loopTime: TimeInterval = 0
    /// What is on screen.
    private(set) var shownFrame = ScrollPreviewLoop(scene: Scene()).frame(at: 0)

    private let deviceCard = ScrollPreviewDeviceCard()
    private let screenCard = ScrollPreviewScreenCard()

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
        layoutArtwork(animated: false)
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
        layoutArtwork(animated: false)
        show(shownFrame)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTimer()
    }

    // MARK: - Running

    /// The tab calls this with true when it appears and with false when it disappears.
    func setAnimating(_ on: Bool) {
        wantsAnimation = on
        updateTimer()
    }

    /// The display-synchronised timer is running.
    var isTimerRunning: Bool {
        return frameLink != nil
    }

    @objc func reduceMotionDidChange() {
        updateTimer()
    }

    /// Starts or stops the timer. Stopped, the picture rests: at the start of the loop, or,
    /// with Reduce Motion, on the still frame.
    private func updateTimer() {
        let shouldRun = wantsAnimation && window != nil && !prefersReducedMotion()
        if shouldRun {
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

    private func show(_ frame: ScrollPreviewLoop.Frame) {
        shownFrame = frame
        deviceCard.show(wheelTurn: frame.wheelTurn, pulse: frame.pulse, keyDepth: frame.keyDepth)
        screenCard.show(offset: frame.offset, atRest: frame.isAtRest)
    }

    private func layoutArtwork(animated: Bool) {
        let width = max(0, floor((bounds.width - Self.cardSpacing) / 2))
        deviceCard.frame = NSRect(x: 0, y: 0, width: width, height: bounds.height)
        screenCard.frame = NSRect(x: bounds.width - width, y: 0, width: width, height: bounds.height)
        deviceCard.setEmphasis(scene.emphasis, animated: animated)
        screenCard.setSideways(scene.emphasis == .sideways)
    }
}
