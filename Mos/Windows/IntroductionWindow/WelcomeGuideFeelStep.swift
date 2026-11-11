//
//  WelcomeGuideFeelStep.swift
//  Mos
//  Step 3 of the Welcome Guide: how scrolling feels. The five "Feel" presets of the
//  Scrolling pane as cards, each with the path the page takes after three clicks (the scroll
//  engine's own maths, ScrollPreviewMotion), and over them a real page to scroll: a scroll
//  view in a drawn window, smoothed by Scrollio's engine itself, as any other window is.
//
//  A pick applies at once and stores only the preset's glide time (`ScrollFeel.apply`, as
//  the Scrolling pane's Feel control). Under the cards, the Scrolling pane's "Reverse wheel
//  direction" switch (`reversesWheel`, the pane's own path): the page is right above it, so
//  a wrong direction is felt and flipped; the engine reads it at the next scroll. These two
//  values are all the step stores. While the pointer is away from the page a short
//  demo plays the chosen feel on it (three clicks there and back); while the pointer is on
//  the page nothing animates: the scroll tap runs on the main thread too. When the page
//  cannot be smoothed (Scrollio not running, "Limit scrolling to these apps" without
//  Scrollio, smoothing off) the text says to watch the demo, and a line in the window
//  says why.
//

import Cocoa

final class WelcomeGuideFeelStep: NSObject, WelcomeGuideStepView {

    let step = WelcomeGuideStep.feel
    let picture: NSView
    let content: NSView

    let artwork: WelcomeGuideFeelPicture
    private(set) var titleLabel: NSTextField!
    private(set) var textLabel: NSTextField!
    private(set) var hintLabel: NSTextField!
    private(set) var noteLabel: NSTextField!
    private(set) var feelButtons: [WelcomeGuideFeelButton] = []
    /// "Reverse wheel direction", the row of the Scrolling pane, in a box of its own.
    private(set) var reverseRow: PreferencesSwitchRow!
    private(set) var reverseBox: PreferencesGroupBox!

    /// The scroll options the pick goes to (the Scrolling pane's).
    var scrollOptions: () -> OPTIONS_SCROLL_DEFAULT
    /// Whether the page is smoothed now.
    var tryAreaState: () -> WelcomeGuideTryArea
    /// The drawing for the connected mouse.
    var mouseSource: () -> MouseArtworkModel

    private(set) var tryArea: WelcomeGuideTryArea = .smoothed

    /// The preset of the stored glide time; nil for a custom one.
    var selectedFeel: ScrollFeel? {
        return ScrollFeel.matching(duration: scrollOptions().duration)
    }

    init(
        scrollOptions: @escaping () -> OPTIONS_SCROLL_DEFAULT,
        tryAreaState: @escaping () -> WelcomeGuideTryArea,
        mouseSource: @escaping () -> MouseArtworkModel
    ) {
        self.scrollOptions = scrollOptions
        self.tryAreaState = tryAreaState
        self.mouseSource = mouseSource
        artwork = WelcomeGuideFeelPicture(frame: NSRect(origin: .zero, size: WelcomeGuideLayout.pictureSize))
        picture = artwork

        let title = WelcomeGuideText.makeTitle(WelcomeGuideText.localized("intro-feel-title"))
        let text = WelcomeGuideText.makeText(WelcomeGuideText.localized("intro-feel-text"))
        let buttons = ScrollFeel.allCases.map { WelcomeGuideFeelButton(feel: $0) }
        let row = NSStackView(views: buttons)
        row.orientation = .horizontal
        row.spacing = WelcomeGuideFeelButton.spacing
        row.translatesAutoresizingMaskIntoConstraints = false
        row.setAccessibilityElement(true)
        row.setAccessibilityRole(.radioGroup)
        row.setAccessibilityLabel(WelcomeGuideText.localized("scrolling-feel-label"))
        let hint = WelcomeGuideText.makeText("", font: NSFont.systemFont(ofSize: 12))
        let note = WelcomeGuideText.makeText(
            WelcomeGuideText.localized("intro-feel-note"), font: PreferencesForm.hintFont, color: .tertiaryLabelColor
        )
        let reverse = PreferencesSwitchRow(
            title: WelcomeGuideText.localized("scrolling-reverse"),
            explanation: WelcomeGuideText.localized("scrolling-reverse-hint"),
            target: nil, action: nil
        )
        let box = PreferencesGroupBox(width: WelcomeGuideLayout.rowBoxWidth, rows: [reverse])
        let (view, stack) = WelcomeGuideText.makeContent([title, text, row, hint, box, note])
        stack.setCustomSpacing(WelcomeGuideLayout.titleToText, after: title)
        stack.setCustomSpacing(WelcomeGuideLayout.textToControl, after: text)
        stack.setCustomSpacing(8, after: row)
        stack.setCustomSpacing(10, after: hint)
        stack.setCustomSpacing(8, after: box)
        // The hint changes with the pick: its height stays that of one line.
        hint.heightAnchor.constraint(equalToConstant: 16).isActive = true
        content = view

        super.init()
        titleLabel = title
        textLabel = text
        hintLabel = hint
        noteLabel = note
        feelButtons = buttons
        reverseRow = reverse
        reverseBox = box
        for button in buttons {
            button.target = self
            button.action = #selector(feelClicked(_:))
        }
        reverse.toggle.target = self
        reverse.toggle.action = #selector(reverseClicked(_:))
        refresh()
    }

    func setShown(_ shown: Bool) {
        if shown { refresh() }
        artwork.setAnimating(shown)
    }

    /// Puts the stored feel, the try area's state and the mouse on screen.
    func refresh() {
        let feel = selectedFeel
        for button in feelButtons {
            button.state = button.feel == feel ? .on : .off
        }
        hintLabel.stringValue = ScrollFeel.hint(for: feel)
        reverseRow.isOn = scrollOptions().reversesWheel
        artwork.model = mouseSource()
        artwork.setScene(duration: scrollOptions().duration, speed: scrollOptions().speed)
        refreshTryArea()
    }

    /// The page is smoothed or not (the access, the per-app list, the switch): the text and
    /// the line in the window follow. Cheap; the container calls it with its poll.
    func refreshTryArea() {
        let state = tryAreaState()
        tryArea = state
        textLabel.stringValue = WelcomeGuideText.localized(state == .smoothed ? "intro-feel-text" : "intro-feel-text-watch")
        artwork.tryArea = state
    }

    @objc func feelClicked(_ sender: WelcomeGuideFeelButton) {
        choose(sender.feel)
    }

    /// The pick: the preset's glide time, nothing else, as the Scrolling pane's Feel control.
    func choose(_ feel: ScrollFeel) {
        feel.apply(to: scrollOptions())
        refresh()
        artwork.restartDemo()
    }

    /// The Scrolling pane's switch: on reverses both axes, off clears the main flag. The
    /// engine reads the options at every wheel event, so the next scroll on the page has it.
    @objc func reverseClicked(_ sender: NSSwitch) {
        setReversesWheel(sender.state == .on)
    }

    func setReversesWheel(_ on: Bool) {
        scrollOptions().reversesWheel = on
        refresh()
    }
}

// MARK: - A choice

/// One preset: the path of the page over time for three clicks, and its name. A radio
/// button: the five are one group (arrow keys move between them), VoiceOver reads the
/// name and the line that says how it feels.
final class WelcomeGuideFeelButton: NSButton {

    static let size = NSSize(width: 100, height: 64)
    static let spacing: CGFloat = 8
    static let curveSize = NSSize(width: 80, height: 28)
    static let cornerRadius: CGFloat = 10

    let feel: ScrollFeel
    /// Points of the curve in its 80 × 28 box (top left origin).
    let curve: [NSPoint]

    init(feel: ScrollFeel) {
        self.feel = feel
        curve = Self.curvePoints(duration: feel.duration)
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        setButtonType(.radio)
        isBordered = false
        title = feel.localizedName
        imagePosition = .noImage
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: Self.size.width).isActive = true
        heightAnchor.constraint(equalToConstant: Self.size.height).isActive = true
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(feel.localizedName)
        setAccessibilityHelp(feel.localizedHint)
        toolTip = feel.localizedHint
    }

    required init?(coder: NSCoder) {
        fatalError("built in code")
    }

    override var isFlipped: Bool { return true }

    override var intrinsicContentSize: NSSize {
        return Self.size
    }

    override var state: NSControl.StateValue {
        didSet { needsDisplay = true }
    }

    /// Where the page is over 1.4 s after three clicks 0.15 s apart, as the engine moves it
    /// (ScrollPreviewMotion), from 0 (bottom of the box) to the three clicks' distance (top).
    static func curvePoints(duration: Double) -> [NSPoint] {
        var scene = ScrollPreviewView.Scene()
        scene.duration = duration
        let clicks = [0.0, 0.15, 0.3].map { ScrollPreviewMotion.Click(time: $0, turn: 1) }
        let motion = ScrollPreviewMotion(scene: scene, clicks: clicks, start: 0)
        let end = max(0.001, motion.end - motion.start)
        let span = 1.4
        let samples = 48
        return (0...samples).map { index in
            let time = span * Double(index) / Double(samples)
            let progress = (motion.value(at: time) - motion.start) / end
            return NSPoint(
                x: 4 + (curveSize.width - 8) * CGFloat(index) / CGFloat(samples),
                y: 25 - 21 * CGFloat(min(1.05, max(0, progress)))
            )
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let selected = state == .on
        let box = NSBezierPath(
            roundedRect: bounds.insetBy(dx: selected ? 1 : 0.5, dy: selected ? 1 : 0.5),
            xRadius: Self.cornerRadius, yRadius: Self.cornerRadius
        )
        (selected ? WelcomeGuidePalette.selectedFill : WelcomeGuidePalette.box).setFill()
        box.fill()
        if isHighlighted {
            NSColor.black.withAlphaComponent(0.06).setFill()
            box.fill()
        }
        if selected {
            box.lineWidth = 2
            NSColor.controlAccentColor.setStroke()
        } else {
            box.lineWidth = 1
            WelcomeGuidePalette.boxEdge.setStroke()
        }
        box.stroke()

        // The curve, in a box 80 × 28 centred at the top.
        let origin = NSPoint(x: ((bounds.width - Self.curveSize.width) / 2).rounded(), y: 8)
        let axis = NSBezierPath()
        axis.move(to: NSPoint(x: origin.x + 4, y: origin.y + 25.5))
        axis.line(to: NSPoint(x: origin.x + Self.curveSize.width - 4, y: origin.y + 25.5))
        axis.lineWidth = 1
        WelcomeGuidePalette.hairline.setStroke()
        axis.stroke()
        if let first = curve.first {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: origin.x + first.x, y: origin.y + first.y))
            for point in curve.dropFirst() {
                path.line(to: NSPoint(x: origin.x + point.x, y: origin.y + point.y))
            }
            path.lineWidth = 1.6
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            (selected ? NSColor.controlAccentColor : NSColor.secondaryLabelColor).setStroke()
            path.stroke()
        }

        let name = NSAttributedString(string: feel.localizedName, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: selected ? .semibold : .medium),
            .foregroundColor: NSColor.labelColor,
        ])
        let size = name.size()
        name.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: bounds.height - 8 - size.height))
    }

    override var focusRingMaskBounds: NSRect {
        return bounds
    }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius).fill()
    }
}

// MARK: - The picture

/// Two cards: the mouse whose wheel turns with the demo, and a desktop with a window whose
/// page is a real scroll view.
final class WelcomeGuideFeelPicture: WelcomeGuideAnimatedView {

    static let mouseCardWidth: CGFloat = 170
    static let cardSpacing: CGFloat = 12
    static let mouseUnit: CGFloat = 1.25
    /// The window on the desktop card, in the card.
    static let windowRect = NSRect(x: 34, y: 26, width: 302, height: 196)
    static let titleBarHeight: CGFloat = 20
    /// The demo's page moves this many times the Scrolling preview's points.
    static let demoGain: CGFloat = 3.5
    /// After the pointer left the page, the demo comes back after this long.
    static let resumeDelay: TimeInterval = 1.5

    let mouseCard = WelcomeGuideFeelMouseCard()
    let desktopCard = WelcomeGuideFeelDesktopCard()
    let scrollView = WelcomeGuideTryScrollView()
    let page = WelcomeGuideSamplePage()
    let pill = WelcomeGuidePill()

    var model: MouseArtworkModel = .generic {
        didSet { mouseCard.model = model }
    }

    /// Whether the page is smoothed: the line in the window says why not.
    var tryArea: WelcomeGuideTryArea = .smoothed {
        didSet { updatePill() }
    }

    /// The user's wheel turned on the page (called for every event: keep it cheap).
    var onUserScroll: (() -> Void)?

    private(set) var loop = ScrollPreviewLoop(scene: ScrollPreviewView.Scene())
    /// Where the demo's leg starts on the page.
    private(set) var anchor: CGFloat = 0
    /// The pointer is on the page, or just left it: the demo waits.
    private(set) var isDemoPaused = false
    private(set) var hasUserScrolled = false
    private(set) var sawTrackpad = false
    private var isShown = false
    private var resumeTimer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let height = frameRect.height
        mouseCard.frame = NSRect(x: 0, y: 0, width: Self.mouseCardWidth, height: height)
        let desktopX = Self.mouseCardWidth + Self.cardSpacing
        desktopCard.frame = NSRect(x: desktopX, y: 0, width: frameRect.width - desktopX, height: height)
        addSubview(mouseCard)
        addSubview(desktopCard)

        let window = Self.windowRect.offsetBy(dx: desktopX, dy: 0)
        scrollView.frame = NSRect(
            x: window.minX + 1, y: window.minY + Self.titleBarHeight + 1,
            width: window.width - 2, height: window.height - Self.titleBarHeight - 2
        )
        scrollView.documentView = page
        page.frame = NSRect(x: 0, y: 0, width: scrollView.contentSize.width, height: WelcomeGuideSamplePage.height)
        scrollView.contentView.scroll(to: .zero)
        addSubview(scrollView)

        pill.maxWidth = window.width - 40
        addSubview(pill)
        pill.centreX = window.midX
        pill.bottom = window.maxY - 14

        scrollView.onHover = { [weak self] inside in self?.pointerOnPage(inside) }
        scrollView.onWheel = { [weak self] trackpad in
            guard let self else { return }
            self.userDidScroll()
            self.onUserScroll?()
            if trackpad && !self.sawTrackpad {
                self.sawTrackpad = true
                self.updatePill()
            }
        }
        // The cards are pictures; the page is what VoiceOver finds.
        setAccessibilityElement(false)
        updatePill()
    }

    required init?(coder: NSCoder) {
        fatalError("built in code")
    }

    deinit {
        resumeTimer?.invalidate()
    }

    func setScene(duration: Double, speed: Double) {
        var scene = ScrollPreviewView.Scene()
        scene.duration = duration
        scene.speed = speed
        guard scene != loop.scene else { return }
        loop = ScrollPreviewLoop(scene: scene)
    }

    /// A new pick shows at once: the demo starts again from where the page is.
    func restartDemo() {
        anchor = demoAnchor()
        restartLoop()
    }

    override func setAnimating(_ on: Bool) {
        isShown = on
        if !on {
            resumeTimer?.invalidate()
            resumeTimer = nil
        }
        anchor = demoAnchor()
        setClockRunning(on && !isDemoPaused)
    }

    private func setClockRunning(_ on: Bool) {
        super.setAnimating(on)
    }

    /// The first scroll on the page: the invitation goes.
    func userDidScroll() {
        if !hasUserScrolled {
            hasUserScrolled = true
            updatePill()
        }
        if !isDemoPaused {
            pointerOnPage(true)
        }
    }

    private func pointerOnPage(_ inside: Bool) {
        resumeTimer?.invalidate()
        resumeTimer = nil
        if inside {
            isDemoPaused = true
            setClockRunning(false)
        } else {
            resumeTimer = Timer.scheduledTimer(withTimeInterval: Self.resumeDelay, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.isDemoPaused = false
                self.anchor = self.demoAnchor()
                self.setClockRunning(self.isShown)
            }
        }
    }

    /// The farthest the demo moves the page.
    private var demoReach: CGFloat {
        return CGFloat(max(loop.out.end, loop.back.start)) * Self.demoGain
    }

    /// Where the page is now, so the leg there and back stays on the page.
    private func demoAnchor() -> CGFloat {
        let maxY = max(0, page.frame.height - scrollView.contentSize.height)
        return min(max(0, scrollView.contentView.bounds.minY), max(0, maxY - demoReach))
    }

    override func show(time: TimeInterval) {
        guard !isDemoPaused else {
            mouseCard.show(wheelTurn: 0, pulse: 0)
            return
        }
        let frame = loop.frame(at: time)
        mouseCard.show(wheelTurn: frame.wheelTurn, pulse: frame.pulse)
        scrollPage(to: anchor + CGFloat(frame.offset.y) * Self.demoGain)
    }

    override func showStill() {
        mouseCard.show(wheelTurn: 0, pulse: 0)
    }

    private func scrollPage(to y: CGFloat) {
        let clip = scrollView.contentView
        let scale = window?.backingScaleFactor ?? 2
        let target = (y * scale).rounded() / scale
        guard abs(clip.bounds.minY - target) >= 0.25 else { return }
        clip.scroll(to: NSPoint(x: 0, y: target))
        scrollView.reflectScrolledClipView(clip)
    }

    /// What the dark line in the window says: why the page is not smoothed, that a
    /// trackpad was used, or, until the first scroll, where to scroll.
    var pillText: String? {
        switch tryArea {
        case .notRunning: return WelcomeGuideText.localized("intro-feel-not-running")
        case .notInAppList: return WelcomeGuideText.localized("intro-feel-not-in-list")
        case .smoothingOff: return WelcomeGuideText.localized("intro-feel-smoothing-off")
        case .smoothed:
            if sawTrackpad { return WelcomeGuideText.localized("intro-feel-trackpad") }
            return hasUserScrolled ? nil : WelcomeGuideText.localized("intro-feel-try")
        }
    }

    private func updatePill() {
        pill.text = pillText
    }
}

/// The left card: the mouse, its wheel lit; it turns and flashes with the demo's clicks.
final class WelcomeGuideFeelMouseCard: WelcomeGuideFlippedView {

    var model: MouseArtworkModel = .generic {
        didSet { if model != oldValue { needsDisplay = true } }
    }
    private var wheelTurn = 0.0
    private var pulse = 0.0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        fatalError("built in code")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    func show(wheelTurn: Double, pulse: Double) {
        let turn = (wheelTurn * 100).rounded() / 100
        let flash = (pulse * 50).rounded() / 50
        guard turn != self.wheelTurn || flash != self.pulse else { return }
        self.wheelTurn = turn
        self.pulse = flash
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        WelcomeGuideCardView.drawCard(in: bounds)
        let unit = WelcomeGuideFeelPicture.mouseUnit
        let size = NSSize(width: MouseArtworkShapes.grid.width * unit, height: MouseArtworkShapes.grid.height * unit)
        var drawing = WelcomeGuideMouseDrawing(
            model: model, unit: unit,
            origin: NSPoint(x: ((bounds.width - size.width) / 2).rounded(), y: ((bounds.height - size.height) / 2).rounded())
        )
        drawing.lit = [.wheel]
        drawing.wheelTurn = wheelTurn
        drawing.pulse = pulse
        drawing.draw()
    }
}

/// The right card: a desktop with a menu bar and one window; the window's page is the
/// scroll view laid over it.
final class WelcomeGuideFeelDesktopCard: WelcomeGuideFlippedView {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        fatalError("built in code")
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = WelcomeGuideLayout.pictureCornerRadius
        let card = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        card.addClip()
        NSGradient(starting: ScrollPreviewPalette.desktopStart, ending: ScrollPreviewPalette.desktopEnd)?
            .draw(in: bounds, angle: -35)
        ScrollPreviewPalette.menuBar.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 12).fill(using: .sourceOver)
        ScrollPreviewPalette.menuItem.setFill()
        var x: CGFloat = 10
        for width in [6, 14, 10, 12] as [CGFloat] {
            NSBezierPath(roundedRect: NSRect(x: x, y: 4.5, width: width, height: 3), xRadius: 1.5, yRadius: 1.5).fill()
            x += width + 5
        }
        NSBezierPath(roundedRect: NSRect(x: bounds.width - 30, y: 4.5, width: 18, height: 3), xRadius: 1.5, yRadius: 1.5).fill()

        let window = WelcomeGuideFeelPicture.windowRect
        let windowPath = NSBezierPath(roundedRect: window, xRadius: 9, yRadius: 9)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = ScrollPreviewPalette.windowShadow
        shadow.shadowBlurRadius = 10
        shadow.shadowOffset = .zero
        shadow.set()
        ScrollPreviewPalette.windowShadow.setFill()
        NSBezierPath(roundedRect: window.insetBy(dx: 3, dy: 3).offsetBy(dx: 0, dy: 4), xRadius: 9, yRadius: 9).fill()
        NSGraphicsContext.restoreGraphicsState()
        ScrollPreviewPalette.windowBody.setFill()
        windowPath.fill()

        NSGraphicsContext.saveGraphicsState()
        windowPath.addClip()
        let titleBar = NSRect(x: window.minX, y: window.minY, width: window.width, height: WelcomeGuideFeelPicture.titleBarHeight)
        ScrollPreviewPalette.windowTitleBar.setFill()
        titleBar.fill()
        ScrollPreviewPalette.windowTitleLine.setFill()
        NSRect(x: window.minX, y: titleBar.maxY - 0.5, width: window.width, height: 0.5).fill(using: .sourceOver)
        for (index, colour) in ScrollPreviewPalette.trafficLights.enumerated() {
            colour.setFill()
            NSBezierPath(ovalIn: NSRect(
                x: window.minX + 7.6 + CGFloat(index) * 10.5, y: titleBar.midY - 3.4, width: 6.8, height: 6.8
            )).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let edge = NSBezierPath(roundedRect: window.insetBy(dx: 0.25, dy: 0.25), xRadius: 9, yRadius: 9)
        edge.lineWidth = 0.5
        ScrollPreviewPalette.windowEdge.setStroke()
        edge.stroke()
        NSGraphicsContext.restoreGraphicsState()

        ScrollPreviewPalette.cardEdge.setStroke()
        card.lineWidth = 1
        card.stroke()
    }
}

/// The page to scroll: a real scroll view. It tells when the pointer comes and goes and
/// when the wheel turns on it, and whether that was a trackpad (a scroll phase that is not
/// one of Scrollio's own smoothed frames).
final class WelcomeGuideTryScrollView: NSScrollView {

    var onHover: ((Bool) -> Void)?
    /// Every scroll event on the page; true: from a trackpad or Magic Mouse.
    var onWheel: ((Bool) -> Void)?
    /// Once a trackpad was seen the events are no longer looked at.
    private var trackpadSeen = false
    private var tracking: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true
        scrollerStyle = .overlay
        horizontalScrollElasticity = .none
        drawsBackground = true
        backgroundColor = ScrollPreviewPalette.windowBody
        borderType = .noBorder
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        setAccessibilityLabel(WelcomeGuideText.localized("intro-feel-try-area"))
    }

    required init?(coder: NSCoder) {
        fatalError("built in code")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
    }

    override func scrollWheel(with event: NSEvent) {
        var trackpad = false
        if !trackpadSeen, !event.phase.isEmpty || !event.momentumPhase.isEmpty {
            // Scrollio's own frames may carry phases too ("Trackpad-style events").
            let synthetic = event.cgEvent.map { ScrollUtils.shared.isSyntheticSmoothEvent($0) } ?? false
            if !synthetic {
                trackpad = true
                trackpadSeen = true
            }
        }
        onWheel?(trackpad)
        super.scrollWheel(with: event)
    }
}

/// A page of text, headings and coloured shapes, long enough to scroll for a while.
final class WelcomeGuideSamplePage: WelcomeGuideFlippedView {

    static let blockHeight: CGFloat = 196
    static let blocks = 10
    static var height: CGFloat {
        return blockHeight * CGFloat(blocks) + 24
    }

    private static let colours: [NSColor] = [.systemGreen, .systemPink, .systemOrange, .systemBlue, .systemPurple]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        fatalError("built in code")
    }

    override func draw(_ dirtyRect: NSRect) {
        ScrollPreviewPalette.windowBody.setFill()
        dirtyRect.fill()
        let first = max(0, Int((dirtyRect.minY - 14) / Self.blockHeight))
        let last = min(Self.blocks - 1, Int(dirtyRect.maxY / Self.blockHeight))
        guard first <= last else { return }
        for index in first...last {
            drawBlock(index, top: 14 + CGFloat(index) * Self.blockHeight)
        }
    }

    private func line(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, heading: Bool = false) {
        (heading ? ScrollPreviewPalette.pageHeading : ScrollPreviewPalette.pageLine).setFill()
        let height: CGFloat = heading ? 7 : 4
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: width, height: height), xRadius: height / 2, yRadius: height / 2).fill()
    }

    /// A heading, two short paragraphs and a shape beside one of them.
    private func drawBlock(_ index: Int, top: CGFloat) {
        let width = bounds.width - 32
        let x: CGFloat = 16
        line(x, top + 6, (width * (index % 2 == 0 ? 0.48 : 0.38)).rounded(), heading: true)
        line(x, top + 24, width)
        line(x, top + 34, (width * 0.9).rounded())
        line(x, top + 44, (width * 0.7).rounded())

        let colour = Self.colours[index % Self.colours.count]
        let side: CGFloat = 52
        let onRight = index % 2 == 0
        let shape = NSRect(x: onRight ? x + width - side : x, y: top + 62, width: side, height: side)
        colour.setFill()
        switch index % 3 {
        case 0: NSBezierPath(roundedRect: shape, xRadius: 7, yRadius: 7).fill()
        case 1:
            let triangle = NSBezierPath()
            triangle.move(to: NSPoint(x: shape.midX, y: shape.minY + 2))
            triangle.line(to: NSPoint(x: shape.maxX - 2, y: shape.maxY - 4))
            triangle.line(to: NSPoint(x: shape.minX + 2, y: shape.maxY - 4))
            triangle.close()
            triangle.fill()
        default: NSBezierPath(ovalIn: shape.insetBy(dx: 2, dy: 2)).fill()
        }
        let textX = onRight ? x : x + side + 14
        let textWidth = width - side - 14
        for (row, fraction) in [1.0, 0.86, 0.94, 0.6].enumerated() {
            line(textX, top + 66 + CGFloat(row) * 10, (textWidth * fraction).rounded())
        }
        line(x, top + 134, width)
        line(x, top + 144, (width * 0.82).rounded())
        line(x, top + 154, (width * 0.9).rounded())
        line(x, top + 164, (width * 0.5).rounded())
    }
}

/// A short line on a dark capsule, over a picture.
final class WelcomeGuidePill: WelcomeGuideFlippedView {

    static let padding = NSEdgeInsets(top: 3, left: 10, bottom: 3, right: 10)

    var maxWidth: CGFloat = 260 {
        didSet { relayout() }
    }
    var centreX: CGFloat = 0 {
        didSet { relayout() }
    }
    var bottom: CGFloat = 0 {
        didSet { relayout() }
    }

    var text: String? {
        didSet {
            guard text != oldValue else { return }
            label.stringValue = text ?? ""
            isHidden = text == nil
            relayout()
        }
    }

    private let label = NSTextField(wrappingLabelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.isSelectable = false
        label.drawsBackground = false
        addSubview(label)
        isHidden = true
        // Read with the page it lies on.
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    required init?(coder: NSCoder) {
        fatalError("built in code")
    }

    var stringValue: String {
        return label.stringValue
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    private func relayout() {
        let inner = maxWidth - Self.padding.left - Self.padding.right
        label.preferredMaxLayoutWidth = inner
        let fitted = label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: inner, height: 1000)) ?? .zero
        let textSize = NSSize(width: ceil(min(inner, fitted.width)), height: ceil(fitted.height))
        let size = NSSize(
            width: textSize.width + Self.padding.left + Self.padding.right,
            height: textSize.height + Self.padding.top + Self.padding.bottom
        )
        frame = NSRect(x: (centreX - size.width / 2).rounded(), y: bottom - size.height, width: size.width, height: size.height)
        label.frame = NSRect(x: Self.padding.left, y: Self.padding.top, width: textSize.width, height: textSize.height)
        setAccessibilityLabel(label.stringValue)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = min(10, bounds.height / 2)
        // Dark on the light page; on the dark page a lighter grey, so it still stands out.
        ScrollPreviewPalette.adaptive(light: NSColor(white: 0, alpha: 0.6), dark: NSColor(white: 0.36, alpha: 0.94)).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
    }
}
