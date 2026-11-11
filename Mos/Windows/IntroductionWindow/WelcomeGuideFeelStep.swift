//
//  WelcomeGuideFeelStep.swift
//  Mos
//  Step 3 of the Welcome Guide: how scrolling feels. The five "Feel" presets of the
//  Scrolling pane as cards, each with a small picture of how far the page glides on (a dot
//  resting further from the wheel's stop, card by card), its name and a word on how it stops;
//  over them a real page to scroll: a scroll view in a drawn window, smoothed by Scrollio's engine
//  itself, as any other window is. A line under the cards shows only for a glide time of
//  the user's own (none of the five is chosen).
//
//  A pick applies at once and stores only the preset's glide time (`ScrollFeel.apply`, as
//  the Scrolling pane's Feel control). Under the cards, the Scrolling pane's "Reverse wheel
//  direction" switch (`reversesWheel`, the pane's own path): the page is right above it, so
//  a wrong direction is felt and flipped; the engine reads it at the next scroll. These two
//  values are all the step stores. While the pointer is away from the page a short
//  demo plays the chosen feel on it (three clicks there and back); while the pointer is on
//  the page nothing animates: the scroll tap runs on the main thread too. When the page
//  cannot be smoothed (Scrollio not running, "Limit scrolling to these apps" without
//  Scrollio, smoothing off) the text says to watch the demo (with Reduce Motion, where
//  nothing moves, just to pick), and a line in the window says why.
//

import Cocoa

final class WelcomeGuideFeelStep: NSObject, WelcomeGuideStepView {

    let step = WelcomeGuideStep.feel
    let picture: NSView
    let content: NSView

    let artwork: WelcomeGuideFeelPicture
    private(set) var titleLabel: NSTextField!
    private(set) var textLabel: NSTextField!
    /// Under the cards, only while the glide time is none of the five.
    private(set) var hintLabel: NSTextField!
    private(set) var feelButtons: [WelcomeGuideFeelButton] = []
    private var stack: NSStackView!
    private var row: NSStackView!
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
        let hint = WelcomeGuideText.makeText(WelcomeGuideText.localized("intro-feel-custom-hint"), font: NSFont.systemFont(ofSize: 12))
        let reverse = PreferencesSwitchRow(
            title: WelcomeGuideText.localized("scrolling-reverse"),
            explanation: WelcomeGuideText.localized("scrolling-reverse-hint"),
            target: nil, action: nil
        )
        let box = PreferencesGroupBox(width: WelcomeGuideLayout.rowBoxWidth, rows: [reverse])
        let (view, stack) = WelcomeGuideText.makeContent([title, text, row, hint, box])
        stack.setCustomSpacing(WelcomeGuideLayout.titleToText, after: title)
        stack.setCustomSpacing(WelcomeGuideLayout.textToControl, after: text)
        stack.setCustomSpacing(Self.hintSpacing, after: hint)
        content = view

        super.init()
        titleLabel = title
        textLabel = text
        hintLabel = hint
        self.stack = stack
        self.row = row
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

    /// Between the cards and the switch's box; with the line for a custom glide time, around it.
    static let rowToBox: CGFloat = 14
    static let hintSpacing: CGFloat = 6

    /// Puts the stored feel, the try area's state and the mouse on screen.
    func refresh() {
        let feel = selectedFeel
        for button in feelButtons {
            button.state = button.feel == feel ? .on : .off
        }
        hintLabel.isHidden = feel != nil
        stack.setCustomSpacing(feel == nil ? Self.hintSpacing : Self.rowToBox, after: row)
        reverseRow.isOn = scrollOptions().reversesWheel
        artwork.model = mouseSource()
        artwork.setScene(duration: scrollOptions().duration, speed: scrollOptions().speed)
        refreshTryArea()
    }

    /// The page is smoothed or not (the access, the per-app list, the switch): the text and
    /// the line in the window follow. Cheap; the container calls it with its poll, and the
    /// text is set only when it changes (no relayout, nothing for VoiceOver to read again).
    func refreshTryArea() {
        let state = tryAreaState()
        tryArea = state
        let text = WelcomeGuideText.localized(Self.textKey(tryArea: state, reduceMotion: artwork.prefersReducedMotion()))
        if textLabel.stringValue != text {
            textLabel.stringValue = text
        }
        artwork.tryArea = state
    }

    /// Scroll the page yourself; or, when it is not smoothed, watch the demo; or, when the
    /// demo stands still too (Reduce Motion), just pick.
    static func textKey(tryArea: WelcomeGuideTryArea, reduceMotion: Bool) -> String {
        if tryArea == .smoothed { return "intro-feel-text" }
        return reduceMotion ? "intro-feel-text-still" : "intro-feel-text-watch"
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

/// One preset: a small picture of how far the page glides on, its name, and a word on how
/// it stops. A radio button: the five are one group (arrow keys move between them),
/// VoiceOver reads the name and that word.
///
/// The card tracks the mouse itself. AppKit's radio cell takes a click only on the title
/// it would draw beside its circle, a strip 47 × 16 pt at the left of the card's middle
/// that this card never shows: a click on the drawn name, the picture or an edge did nothing.
/// Here the whole card takes the click, as a button does: pressed while the pointer is
/// on it, chosen when the button is released on it, also the first click into a window
/// that is not key, and never the start of a window drag (the guide's window moves by
/// its background).
final class WelcomeGuideFeelButton: NSButton {

    /// Five cards and four gaps are as wide as the picture (552 pt).
    static let size = NSSize(width: 104, height: 76)
    static let spacing: CGFloat = 8
    static let pictureSize = NSSize(width: 80, height: 22)
    static let cornerRadius: CGFloat = 10

    let feel: ScrollFeel

    init(feel: ScrollFeel) {
        self.feel = feel
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
        setAccessibilityHelp(caption)
        toolTip = feel.localizedHint
    }

    /// The word under the name: how the page stops.
    var caption: String {
        return WelcomeGuideText.localized("intro-feel-caption-\(feel.name)")
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

    override var isHighlighted: Bool {
        didSet { if isHighlighted != oldValue { needsDisplay = true } }
    }

    // MARK: The mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override var mouseDownCanMoveWindow: Bool {
        return false
    }

    /// As a push button tracks: pressed while the pointer is on the card, chosen when the
    /// button goes up on it; released elsewhere, nothing changes.
    override func mouseDown(with event: NSEvent) {
        guard isEnabled, let window else { return }
        var inside = contains(event)
        isHighlighted = inside
        while let next = window.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
            inside = contains(next)
            isHighlighted = inside
            if next.type == .leftMouseUp { break }
        }
        isHighlighted = false
        if inside {
            choose()
        }
    }

    private func contains(_ event: NSEvent) -> Bool {
        return bounds.contains(convert(event.locationInWindow, from: nil))
    }

    /// Selects this card and tells the step: the click, Space, Return, an arrow key, and
    /// VoiceOver's press (`performClick`).
    func choose() {
        state = .on
        sendAction(action, to: target)
    }

    override func performClick(_ sender: Any?) {
        guard isEnabled else { return }
        choose()
    }

    // MARK: VoiceOver

    /// A radio button's value: 1 chosen, 0 not.
    override func accessibilityValue() -> Any? {
        return NSNumber(value: state == .on ? 1 : 0)
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        choose()
        return true
    }

    // MARK: The keyboard

    /// The five cards, left to right (the order of their row).
    private var group: [WelcomeGuideFeelButton] {
        let row = (superview as? NSStackView)?.arrangedSubviews ?? superview?.subviews ?? [self]
        return row.compactMap { $0 as? WelcomeGuideFeelButton }
    }

    /// The card Tab stops at: the selected one, the first while none is (a custom glide
    /// time). Tab reaches the group once; the arrow keys move inside it.
    var isGroupEntry: Bool {
        let cards = group
        return (cards.first { $0.state == .on } ?? cards.first) === self
    }

    override var canBecomeKeyView: Bool {
        return isGroupEntry && super.canBecomeKeyView
    }

    /// Left and up choose the card before, right and down the one after (as a radio group:
    /// the focus and the choice move together); Space chooses the focused card, and so does
    /// Return while it is not chosen yet (then Return goes on to the window's main button).
    override func keyDown(with event: NSEvent) {
        guard isEnabled, let key = event.charactersIgnoringModifiers?.unicodeScalars.first?.value else {
            return super.keyDown(with: event)
        }
        switch Int(key) {
        case NSLeftArrowFunctionKey, NSUpArrowFunctionKey:
            move(by: -1)
        case NSRightArrowFunctionKey, NSDownArrowFunctionKey:
            move(by: 1)
        case 0x20:
            choose()
        case 0x0D, 0x03:
            if state == .on {
                super.keyDown(with: event)
            } else {
                choose()
            }
        default:
            super.keyDown(with: event)
        }
    }

    private func move(by offset: Int) {
        let cards = group
        guard let index = cards.firstIndex(where: { $0 === self }) else { return }
        let target = cards[min(max(0, index + offset), cards.count - 1)]
        if target !== self {
            window?.makeFirstResponder(target)
        }
        target.choose()
    }

    /// The picture, in its 80 × 22 box (top-left origin): a mark where the wheel stops and a
    /// dot where the page comes to rest, with a trail between them.
    static let trailStart: CGFloat = 6
    static let dotRadius: CGFloat = 4
    private static let firstDot: CGFloat = 14
    private static let dotStep: CGFloat = 15

    /// How far from the mark a feel's dot rests. A rank, not a measure: the presets are in
    /// the order of their glide times, and each card's dot is one even step further than the
    /// one before. Drawn to scale (as curves of the page over time, which the cards had) the
    /// five were too alike to tell apart.
    static func dotX(for feel: ScrollFeel) -> CGFloat {
        let rank = ScrollFeel.allCases.firstIndex(of: feel) ?? 0
        return firstDot + dotStep * CGFloat(rank)
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
            WelcomeGuidePalette.pressed.setFill()
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

        // The picture, in a box 80 × 22 centred at the top.
        let origin = NSPoint(x: ((bounds.width - Self.pictureSize.width) / 2).rounded(), y: 8)
        let middle = origin.y + Self.pictureSize.height / 2
        let start = origin.x + Self.trailStart
        let dotCentre = NSPoint(x: origin.x + Self.dotX(for: feel), y: middle)
        let dot = NSRect(
            x: dotCentre.x - Self.dotRadius, y: dotCentre.y - Self.dotRadius,
            width: Self.dotRadius * 2, height: Self.dotRadius * 2
        )
        let ink = selected ? NSColor.controlAccentColor : NSColor.secondaryLabelColor
        let faint = selected ? NSColor.controlAccentColor.withAlphaComponent(0.45) : NSColor.tertiaryLabelColor

        // Where the wheel stops.
        let mark = NSBezierPath()
        mark.move(to: NSPoint(x: start, y: middle - 6))
        mark.line(to: NSPoint(x: start, y: middle + 6))
        mark.lineWidth = 1.5
        mark.lineCapStyle = .round
        faint.setStroke()
        mark.stroke()

        // The trail widens from the mark to the dot; it stays out of the dot, whose ink is
        // translucent and would show the trail through.
        NSGraphicsContext.saveGraphicsState()
        let outsideTheDot = NSBezierPath(rect: bounds)
        outsideTheDot.appendOval(in: dot)
        outsideTheDot.windingRule = .evenOdd
        outsideTheDot.addClip()
        let trail = NSBezierPath()
        trail.move(to: NSPoint(x: start, y: middle))
        trail.line(to: NSPoint(x: dotCentre.x, y: middle - 3))
        trail.line(to: NSPoint(x: dotCentre.x, y: middle + 3))
        trail.close()
        faint.setFill()
        trail.fill()
        NSGraphicsContext.restoreGraphicsState()

        // Where the page comes to rest.
        ink.setFill()
        NSBezierPath(ovalIn: dot).fill()

        // The name and the word under it, centred, cut short rather than overflowing.
        let line = NSMutableParagraphStyle()
        line.alignment = .center
        line.lineBreakMode = .byTruncatingTail
        let text = bounds.insetBy(dx: 6, dy: 0)
        NSAttributedString(string: feel.localizedName, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: selected ? .semibold : .medium),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: line,
        ]).draw(in: NSRect(x: text.minX, y: 36, width: text.width, height: 16))
        NSAttributedString(string: caption, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: line,
        ]).draw(in: NSRect(x: text.minX, y: 52, width: text.width, height: 15))
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
    /// The line about a trackpad shows this long after it appeared.
    static let trackpadNoteDuration: TimeInterval = 4

    private(set) var loop = ScrollPreviewLoop(scene: ScrollPreviewView.Scene())
    /// Where the demo's leg starts on the page.
    private(set) var anchor: CGFloat = 0
    /// The pointer is on the page, or just left it: the demo waits.
    private(set) var isDemoPaused = false
    private(set) var hasUserScrolled = false
    /// The last scroll on the page came from a trackpad or a Magic Mouse.
    private(set) var sawTrackpad = false
    /// The line that says so shows (for `trackpadNoteDuration`, from the first such scroll).
    private(set) var showsTrackpadNote = false
    private(set) var trackpadNoteTimer: Timer?
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

        pill.maxWidth = window.width - 16
        addSubview(pill)
        pill.centreX = window.midX
        pill.bottom = window.maxY - 14

        scrollView.onHover = { [weak self] inside in self?.pointerOnPage(inside) }
        scrollView.onWheel = { [weak self] trackpad in
            guard let self else { return }
            self.userDidScroll()
            self.onUserScroll?()
            self.wheelCame(fromTrackpad: trackpad)
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
        trackpadNoteTimer?.invalidate()
    }

    /// A trackpad's scroll shows the line for a while; the next wheel scroll takes it away.
    private func wheelCame(fromTrackpad trackpad: Bool) {
        guard trackpad != sawTrackpad else { return }
        sawTrackpad = trackpad
        trackpadNoteTimer?.invalidate()
        trackpadNoteTimer = nil
        showsTrackpadNote = trackpad
        if trackpad {
            trackpadNoteTimer = Timer.scheduledTimer(withTimeInterval: Self.trackpadNoteDuration, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.trackpadNoteTimer = nil
                self.showsTrackpadNote = false
                self.updatePill()
            }
        }
        updatePill()
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
            // A view taken out of the window hears no mouse-exit: a pointer still on the page
            // pauses the demo again with the next mouse-entered.
            isDemoPaused = false
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
            if showsTrackpadNote { return WelcomeGuideText.localized("intro-feel-trackpad") }
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
/// when the wheel turns on it, and whether that was a trackpad (as the scroll engine tells
/// them apart, `ScrollEvent.isTrackpad`; Scrollio's own smoothed frames are a wheel's even
/// with a phase). A press on it never drags the window (which moves by its background):
/// its clip view and its page say so.
final class WelcomeGuideTryScrollView: NSScrollView {

    var onHover: ((Bool) -> Void)?
    /// Every scroll event on the page; true: from a trackpad or Magic Mouse.
    var onWheel: ((Bool) -> Void)?
    private var tracking: NSTrackingArea?

    /// The clip view of the page: where the page does not reach (a bounce at either end),
    /// a press does not drag the window either.
    private final class ClipView: NSClipView {
        override var mouseDownCanMoveWindow: Bool { return false }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        contentView = ClipView(frame: contentView.frame)
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
        let trackpad = event.cgEvent.map {
            ScrollEvent.isTrackpad(with: $0) && !ScrollUtils.shared.isSyntheticSmoothEvent($0)
        } ?? false
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

    /// The window moves by its background; a press on the page to scroll must not move it.
    override var mouseDownCanMoveWindow: Bool {
        return false
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
