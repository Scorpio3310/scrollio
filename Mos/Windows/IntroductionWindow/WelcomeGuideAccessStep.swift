//
//  WelcomeGuideAccessStep.swift
//  Mos
//  Step 2 of the Welcome Guide: Accessibility access. A drawn System Settings list with
//  Scrollio's row, whose switch a pointer turns on (a 4.2 s loop while the access is
//  missing), why the access is needed, a status line that follows the real permission and
//  the start of the event taps, and "Having trouble?" with the help of a stale entry.
//  Before the user opened System Settings the status line is a to-do ("Not allowed yet");
//  only then does it wait, with a spinner.
//
//  What the button does and when the access counts are the container's
//  (IntroductionViewController); this step only shows the state it is given.
//

import Cocoa

final class WelcomeGuideAccessStep: WelcomeGuideStepView {

    let step = WelcomeGuideStep.access
    let picture: NSView
    let content: NSView

    let artwork: WelcomeGuideAccessPicture
    private(set) var titleLabel: NSTextField!
    private(set) var textLabel: NSTextField!
    private(set) var statusBox: WelcomeGuideStatusBox!
    private(set) var helpButton: NSButton!

    private(set) var state: WelcomeGuideAccessState = .missing
    private(set) var context = Context()
    private var isShown = false

    /// What the status line says besides the state.
    struct Context: Equatable {
        var menuBarIconHidden = false
        /// Another step comes after this one (it says where Scrollio lives).
        var stepFollows = false
        /// "Open Accessibility Settings" was used in this run.
        var settingsOpened = false
    }

    init(target: AnyObject, helpAction: Selector) {
        let card = WelcomeGuideCardView(frame: NSRect(origin: .zero, size: WelcomeGuideLayout.pictureSize))
        artwork = WelcomeGuideAccessPicture(frame: card.bounds)
        artwork.autoresizingMask = [.width, .height]
        card.addSubview(artwork)
        picture = card

        let title = WelcomeGuideText.makeTitle(WelcomeGuideText.localized("intro-access-title"))
        let text = WelcomeGuideText.makeText(WelcomeGuideText.localized("intro-access-text"))
        let status = WelcomeGuideStatusBox()
        let help = PreferencesForm.makeLinkButton(
            title: WelcomeGuideText.localized("intro-help-link"), target: target, action: helpAction
        )
        help.setAccessibilityExpanded(false)

        let (view, stack) = WelcomeGuideText.makeContent([title, text, status, help])
        stack.setCustomSpacing(WelcomeGuideLayout.titleToText, after: title)
        stack.setCustomSpacing(WelcomeGuideLayout.textToControl, after: text)
        stack.setCustomSpacing(12, after: status)
        content = view

        titleLabel = title
        textLabel = text
        statusBox = status
        helpButton = help
        show(.missing, context: Context())
    }

    /// The pointer loop plays only while the access is missing: once it is allowed the picture
    /// stands still with the switch on, and no display link ticks for it.
    func setShown(_ shown: Bool) {
        isShown = shown
        artwork.setAnimating(shown && !state.isGranted)
        statusBox.setAnimating(shown)
    }

    func show(_ state: WelcomeGuideAccessState, context: Context) {
        self.state = state
        self.context = context
        artwork.isAllowed = state.isGranted
        artwork.setAnimating(isShown && !state.isGranted)
        helpButton.isHidden = state.isGranted
        statusBox.show(state, texts: Self.statusTexts(for: state, context: context), waits: Self.waits(state, context: context))
    }

    /// The spinner turns while something is under way: the user went to System Settings and
    /// the access is still missing, or the event taps are starting.
    static func waits(_ state: WelcomeGuideAccessState, context: Context) -> Bool {
        return (state == .missing && context.settingsOpened) || state == .starting
    }

    /// The status line's title and the line under it, as shown for `state`.
    static func statusTexts(for state: WelcomeGuideAccessState, context: Context) -> (title: String, detail: String) {
        let allowed = WelcomeGuideText.localized("general-accessibility-allowed")
        switch state {
        case .missing where !context.settingsOpened:
            return (WelcomeGuideText.localized("intro-access-todo"), WelcomeGuideText.localized("intro-access-todo-detail"))
        case .missing:
            return (WelcomeGuideText.localized("intro-access-waiting"), WelcomeGuideText.localized("intro-access-waiting-detail"))
        case .starting:
            return (allowed, WelcomeGuideText.localized("intro-access-starting"))
        case .running:
            // The last step says where Scrollio lives; the Accessibility step alone says it here.
            let detail = context.stepFollows ? "intro-status-running"
                : context.menuBarIconHidden ? "intro-status-granted-detail-hidden-icon" : "intro-status-granted-detail"
            return (allowed, WelcomeGuideText.localized(detail))
        case .paused:
            return (allowed, WelcomeGuideText.localized("intro-access-paused"))
        case .couldNotStart:
            return (allowed, WelcomeGuideText.localized("intro-access-could-not-start"))
        }
    }
}

/// The status under the text: an icon, a line and the small print under it, in the box
/// of the Settings panes (an edge only with Increase Contrast).
final class WelcomeGuideStatusBox: WelcomeGuideFlippedView {

    static let width = WelcomeGuideLayout.rowBoxWidth
    static let padding = NSEdgeInsets(top: 11, left: 14, bottom: 11, right: 14)
    static let iconSize: CGFloat = 20

    private(set) var titleLabel: NSTextField!
    private(set) var detailLabel: NSTextField!
    private(set) var iconView: NSImageView!
    private(set) var spinner: NSProgressIndicator!
    private var animating = false
    private var state: WelcomeGuideAccessState = .missing

    /// Reduce Motion: the spinner stands still as a dashed circle.
    var prefersReducedMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.imageScaling = .scaleNone
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.setAccessibilityElement(false)
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isDisplayedWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.setAccessibilityElement(false)

        let title = NSTextField(labelWithString: "")
        title.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        title.textColor = .labelColor
        title.lineBreakMode = .byWordWrapping
        title.maximumNumberOfLines = 0
        title.translatesAutoresizingMaskIntoConstraints = false
        let textWidth = Self.width - Self.padding.left - Self.padding.right - Self.iconSize - 10
        title.preferredMaxLayoutWidth = textWidth
        let detail = WelcomeGuideText.makeText("", font: PreferencesForm.hintFont, alignment: .left, width: textWidth)

        for view in [icon, spinner, title, detail] as [NSView] {
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.width),
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.padding.left),
            icon.topAnchor.constraint(equalTo: topAnchor, constant: Self.padding.top - 1),
            icon.widthAnchor.constraint(equalToConstant: Self.iconSize),
            icon.heightAnchor.constraint(equalToConstant: Self.iconSize),
            spinner.centerXAnchor.constraint(equalTo: icon.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.padding.right),
            title.topAnchor.constraint(equalTo: topAnchor, constant: Self.padding.top),
            detail.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            detail.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
            detail.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.padding.bottom),
        ])
        titleLabel = title
        detailLabel = detail
        iconView = icon
        self.spinner = spinner

        // Read as one line; VoiceOver hears of changes through an announcement.
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    required init?(coder: NSCoder) {
        fatalError("built in code")
    }

    func show(_ state: WelcomeGuideAccessState, texts: (title: String, detail: String), waits: Bool) {
        self.state = state
        titleLabel.stringValue = texts.title
        detailLabel.stringValue = texts.detail
        setAccessibilityLabel(texts.title + ". " + texts.detail)

        let reduce = prefersReducedMotion()
        spinner.isHidden = !waits || reduce
        iconView.isHidden = waits && !reduce
        let symbol: (name: String, tint: NSColor)
        switch state {
        case .missing, .starting: symbol = ("circle.dashed", .tertiaryLabelColor)
        case .running: symbol = ("checkmark.circle.fill", .systemGreen)
        case .paused: symbol = ("pause.circle.fill", .secondaryLabelColor)
        case .couldNotStart: symbol = ("exclamationmark.circle.fill", .systemOrange)
        }
        iconView.image = NSImage(systemSymbolName: symbol.name, accessibilityDescription: nil)
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        iconView.contentTintColor = symbol.tint
        updateSpinner()
    }

    func setAnimating(_ on: Bool) {
        animating = on
        updateSpinner()
    }

    private func updateSpinner() {
        if animating && !spinner.isHidden {
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = PreferencesGroupedForm.boxCornerRadius
        PreferencesGroupedForm.boxFillColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        if PreferencesGroupedForm.isHighContrast(effectiveAppearance) {
            PreferencesGroupedForm.drawOutline(of: bounds)
        }
    }
}

/// The drawn Accessibility list of System Settings: schematic, in the guide's own colours,
/// so it reads right on every macOS without copying one. Scrollio's row sits between two
/// faint rows; a pointer glides to its switch and turns it on.
final class WelcomeGuideAccessPicture: WelcomeGuideAnimatedView {

    static let loopLength: TimeInterval = 4.2
    static let windowRect = NSRect(x: 66, y: 18, width: 420, height: 200)
    static let rowHeight: CGFloat = 34
    static let switchSize = NSSize(width: 30, height: 17)
    static let pointerSize = NSSize(width: 15, height: 22)
    static let pointerStart = NSPoint(x: 536, y: 228)

    static var listRect: NSRect {
        let window = windowRect
        return NSRect(x: window.minX + 14, y: window.minY + 60, width: window.width - 28, height: 3 * rowHeight)
    }

    static func rowRect(_ index: Int) -> NSRect {
        let list = listRect
        return NSRect(x: list.minX, y: list.minY + CGFloat(index) * rowHeight, width: list.width, height: rowHeight)
    }

    static func switchRect(inRow index: Int) -> NSRect {
        let row = rowRect(index)
        return NSRect(
            x: row.maxX - 12 - switchSize.width, y: (row.midY - switchSize.height / 2).rounded(),
            width: switchSize.width, height: switchSize.height
        )
    }

    /// Where the pointer's tip ends: on Scrollio's switch.
    static var pointerTarget: NSPoint {
        let target = switchRect(inRow: 1)
        return NSPoint(x: target.midX + 2, y: target.midY + 2)
    }

    struct Frame: Equatable {
        /// 0 off ... 1 on (the knob's way).
        var switchOn: CGFloat = 0
        var switchAlpha: CGFloat = 1
        var pointer: NSPoint = WelcomeGuideAccessPicture.pointerStart
        var pointerAlpha: CGFloat = 0
        var pointerScale: CGFloat = 1
        /// Reduce Motion: a dashed ring round the switch says "here".
        var ring = false
    }

    /// The access is there: the loop stops with the switch on.
    var isAllowed = false {
        didSet {
            guard isAllowed != oldValue else { return }
            updateClock()
            if isAllowed { apply(Frame(switchOn: 1)) }
        }
    }

    private(set) var shownFrame = Frame()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(WelcomeGuideText.localized("intro-access-picture"))
    }

    required init?(coder: NSCoder) {
        fatalError("built in code")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    /// The moment `time` seconds into the loop: the pointer glides in from 0.5 s, clicks at
    /// 1.3 s, the switch turns on at 1.4 s, everything fades at 3.4-3.95 s.
    static func frame(at time: TimeInterval) -> Frame {
        var loop = time.isFinite ? time.truncatingRemainder(dividingBy: loopLength) : 0
        if loop < 0 { loop += loopLength }
        let glide = CGFloat(easeOut((loop - 0.5) / 0.8))
        var frame = Frame()
        frame.pointer = NSPoint(
            x: pointerStart.x + (pointerTarget.x - pointerStart.x) * glide,
            y: pointerStart.y + (pointerTarget.y - pointerStart.y) * glide
        )
        frame.pointerScale = loop > 1.3 && loop < 1.42 ? 0.88 : 1
        frame.pointerAlpha = CGFloat(clamp01((loop - 0.5) / 0.2) - clamp01((loop - 3.4) / 0.3))
        if loop >= 1.4 && loop < 3.75 {
            frame.switchOn = CGFloat(easeOut((loop - 1.4) / 0.25))
        }
        if loop > 3.55 && loop < 3.95 {
            frame.switchAlpha = CGFloat(1 - sin(Double.pi * (loop - 3.55) / 0.4))
        }
        return frame
    }

    override func show(time: TimeInterval) {
        apply(isAllowed ? Frame(switchOn: 1) : Self.frame(at: time))
    }

    override func showStill() {
        apply(Frame(switchOn: 1, ring: !isAllowed))
    }

    func apply(_ frame: Frame) {
        guard frame != shownFrame else { return }
        shownFrame = frame
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let window = Self.windowRect
        let frame = shownFrame

        // The window, with its shadow.
        let windowPath = NSBezierPath(roundedRect: window, xRadius: 10, yRadius: 10)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = WelcomeGuidePalette.settingsShadow
        shadow.shadowBlurRadius = 11
        shadow.shadowOffset = NSSize(width: 0, height: -6)
        shadow.set()
        WelcomeGuidePalette.settingsWindow.setFill()
        windowPath.fill()
        NSGraphicsContext.restoreGraphicsState()
        WelcomeGuidePalette.settingsEdge.setStroke()
        windowPath.lineWidth = 0.5
        windowPath.stroke()

        // The title bar: three dots, back and forward, the pane's name.
        WelcomeGuidePalette.switchOff.setFill()
        for index in 0..<3 {
            NSBezierPath(ovalIn: NSRect(x: window.minX + 12 + CGFloat(index) * 14, y: window.minY + 12, width: 8, height: 8)).fill()
        }
        let chevrons = NSBezierPath()
        chevrons.move(to: NSPoint(x: window.minX + 70, y: window.minY + 11))
        chevrons.line(to: NSPoint(x: window.minX + 66, y: window.minY + 16))
        chevrons.line(to: NSPoint(x: window.minX + 70, y: window.minY + 21))
        chevrons.move(to: NSPoint(x: window.minX + 80, y: window.minY + 11))
        chevrons.line(to: NSPoint(x: window.minX + 84, y: window.minY + 16))
        chevrons.line(to: NSPoint(x: window.minX + 80, y: window.minY + 21))
        chevrons.lineWidth = 1.5
        chevrons.lineCapStyle = .round
        chevrons.lineJoinStyle = .round
        WelcomeGuidePalette.faint.setStroke()
        chevrons.stroke()
        let title = NSAttributedString(string: WelcomeGuideText.localized("general-accessibility"), attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .bold),
            .foregroundColor: NSColor.labelColor,
        ])
        title.draw(at: NSPoint(x: window.minX + 98, y: window.minY + 8))

        // Two lines of text over the list, as placeholders (as faint as the rows' names).
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(0.5)
        WelcomeGuidePalette.faint.setFill()
        capsule(NSRect(x: window.minX + 16, y: window.minY + 38, width: 300, height: 5)).fill()
        capsule(NSRect(x: window.minX + 16, y: window.minY + 47, width: 180, height: 5)).fill()
        NSGraphicsContext.restoreGraphicsState()

        // The list.
        let list = Self.listRect
        let listPath = NSBezierPath(roundedRect: list, xRadius: 8, yRadius: 8)
        WelcomeGuidePalette.settingsList.setFill()
        listPath.fill()
        WelcomeGuidePalette.settingsEdge.setStroke()
        listPath.lineWidth = 0.5
        listPath.stroke()
        WelcomeGuidePalette.hairline.setFill()
        for index in 1..<3 {
            let row = Self.rowRect(index)
            NSRect(x: row.minX + 40, y: row.minY, width: row.width - 40, height: 0.5).fill(using: .sourceOver)
        }

        drawPlaceholderRow(0, nameWidth: 74, on: true, tint: NSColor(srgbRed: 0.56, green: 0.6, blue: 0.68, alpha: 1))
        drawScrollioRow(frame)
        drawPlaceholderRow(2, nameWidth: 96, on: false, tint: NSColor(srgbRed: 0.5, green: 0.64, blue: 0.56, alpha: 1))

        // + and − under the list.
        let signs = NSBezierPath()
        let signsY = list.maxY + 12
        signs.move(to: NSPoint(x: list.minX + 4, y: signsY))
        signs.line(to: NSPoint(x: list.minX + 14, y: signsY))
        signs.move(to: NSPoint(x: list.minX + 9, y: signsY - 5))
        signs.line(to: NSPoint(x: list.minX + 9, y: signsY + 5))
        signs.move(to: NSPoint(x: list.minX + 26, y: signsY))
        signs.line(to: NSPoint(x: list.minX + 36, y: signsY))
        signs.lineWidth = 1.5
        signs.lineCapStyle = .round
        WelcomeGuidePalette.faint.setStroke()
        signs.stroke()

        if frame.pointerAlpha > 0 {
            drawPointer(at: frame.pointer, scale: frame.pointerScale, alpha: frame.pointerAlpha)
        }
    }

    private func capsule(_ rect: NSRect) -> NSBezierPath {
        let radius = min(rect.width, rect.height) / 2
        return NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    }

    private func iconRect(inRow index: Int) -> NSRect {
        let row = Self.rowRect(index)
        return NSRect(x: row.minX + 10, y: (row.midY - 10).rounded(), width: 20, height: 20)
    }

    private func drawPlaceholderRow(_ index: Int, nameWidth: CGFloat, on: Bool, tint: NSColor) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(0.5)
        let row = Self.rowRect(index)
        let icon = iconRect(inRow: index)
        tint.setFill()
        NSBezierPath(roundedRect: icon, xRadius: 5, yRadius: 5).fill()
        WelcomeGuidePalette.faint.setFill()
        capsule(NSRect(x: icon.maxX + 10, y: row.midY - 3.5, width: nameWidth, height: 7)).fill()
        drawSwitch(in: Self.switchRect(inRow: index), on: on ? 1 : 0)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawScrollioRow(_ frame: Frame) {
        let row = Self.rowRect(1)
        let icon = iconRect(inRow: 1)
        NSImage(named: NSImage.applicationIconName)?.draw(
            in: icon, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil
        )
        let name = NSAttributedString(string: WelcomeGuideText.localized("about-app-name"), attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.labelColor,
        ])
        let size = name.size()
        name.draw(at: NSPoint(x: icon.maxX + 10, y: row.midY - size.height / 2))

        let switchRect = Self.switchRect(inRow: 1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(frame.switchAlpha)
        drawSwitch(in: switchRect, on: frame.switchOn)
        NSGraphicsContext.restoreGraphicsState()

        if frame.ring {
            let ring = NSBezierPath(roundedRect: switchRect.insetBy(dx: -5, dy: -5), xRadius: 13.5, yRadius: 13.5)
            ring.lineWidth = 1.5
            ring.setLineDash([4, 3], count: 2, phase: 0)
            NSColor.controlAccentColor.setStroke()
            ring.stroke()
        }
    }

    private func drawSwitch(in rect: NSRect, on: CGFloat) {
        let track = capsule(rect)
        WelcomeGuidePalette.switchOff.setFill()
        track.fill()
        if on > 0 {
            NSColor.controlAccentColor.withAlphaComponent(on).setFill()
            track.fill()
        }
        let knobSide = rect.height - 3
        let knob = NSRect(
            x: rect.minX + 1.5 + (rect.width - knobSide - 3) * on, y: rect.minY + 1.5,
            width: knobSide, height: knobSide
        )
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = WelcomeGuidePalette.knobShadow
        shadow.shadowBlurRadius = 1.5
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        shadow.set()
        WelcomeGuidePalette.knob.setFill()
        NSBezierPath(ovalIn: knob).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// The arrow pointer, its tip at `tip`.
    private func drawPointer(at tip: NSPoint, scale: CGFloat, alpha: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(alpha)
        let transform = NSAffineTransform()
        transform.translateX(by: tip.x - 1.5 * scale, yBy: tip.y - 1.5 * scale)
        transform.scale(by: scale)
        transform.concat()
        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: 1.5, y: 1.5))
        arrow.line(to: NSPoint(x: 1.5, y: 17.7))
        arrow.line(to: NSPoint(x: 5.5, y: 13.8))
        arrow.line(to: NSPoint(x: 8.1, y: 19.9))
        arrow.line(to: NSPoint(x: 11.1, y: 18.6))
        arrow.line(to: NSPoint(x: 8.5, y: 12.7))
        arrow.line(to: NSPoint(x: 14.1, y: 12.7))
        arrow.close()
        arrow.lineJoinStyle = .round
        arrow.lineWidth = 1.3
        NSColor.black.setFill()
        arrow.fill()
        NSColor.white.setStroke()
        arrow.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// "Having trouble?": what to do when Scrollio is in the list but does not work (a stale
/// entry after the app was replaced), and a button that shows the app in Finder.
final class WelcomeGuideHelpViewController: NSViewController {

    static let width: CGFloat = 300

    private let showInFinder: () -> Void
    private(set) var headingLabel: NSTextField!
    private(set) var textLabel: NSTextField!
    private(set) var finderButton: NSButton!

    init(showInFinder: @escaping () -> Void) {
        self.showInFinder = showInFinder
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("built in code")
    }

    override func loadView() {
        let width = Self.width - 28
        let heading = WelcomeGuideText.makeText(
            WelcomeGuideText.localized("intro-help-heading"), font: PreferencesForm.sectionHeaderFont,
            color: .labelColor, alignment: .left, width: width
        )
        let text = WelcomeGuideText.makeText(
            WelcomeGuideText.localized("intro-help-text"), font: PreferencesForm.hintFont,
            alignment: .left, width: width
        )
        let finder = NSButton(
            title: WelcomeGuideText.localized("intro-help-finder-button"), target: self, action: #selector(finderClicked(_:))
        )
        finder.bezelStyle = .push
        finder.translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView(views: [heading, text, finder])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setCustomSpacing(12, after: text)
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: Self.width).isActive = true
        for label in [heading, text] {
            label.widthAnchor.constraint(equalToConstant: width).isActive = true
        }
        headingLabel = heading
        textLabel = text
        finderButton = finder
        view = stack
        view.setFrameSize(stack.fittingSize)
        preferredContentSize = stack.fittingSize
    }

    @objc func finderClicked(_ sender: Any?) {
        showInFinder()
    }
}
