//
//  WelcomeGuideFinishStep.swift
//  Mos
//  The last step of the Welcome Guide: where Scrollio lives now. A drawn menu bar whose
//  Scrollio icon pulses twice and then opens its menu (the real items of the status-bar
//  menu); with Reduce Motion the menu is simply open. With the menu bar icon hidden the
//  picture shows only the empty place of the icon, and the text says how to reach Settings.
//  Under the text, where to go next: one box with a row for Buttons, Gestures and the
//  Shortcut Ring (the sidebar's tile and name, a hint, a chevron); a click opens Settings on
//  that pane and ends the guide (the container's `nextPlaceClicked`). Under it, General's
//  "Open at login" switch: on for a new user, the system's state when the guide runs by
//  hand. The choice is the container's, applied when the user leaves the step
//  (IntroductionViewController.applyOpenAtLogin).
//

import Cocoa

final class WelcomeGuideFinishStep: WelcomeGuideStepView {

    let step = WelcomeGuideStep.finish
    let picture: NSView
    let content: NSView

    let artwork: WelcomeGuideFinishPicture
    private(set) var titleLabel: NSTextField!
    private(set) var textLabel: NSTextField!
    /// Where to go next: Buttons, Gestures, Shortcut Ring, in the sidebar's order.
    private(set) var nextBox: WelcomeGuideNextBox!
    var nextRows: [WelcomeGuideNextRow] {
        return nextBox.rows
    }
    /// "Open at login", General's row, in a box of its own.
    private(set) var loginRow: PreferencesSwitchRow!
    private(set) var loginBox: PreferencesGroupBox!

    /// Whether the menu bar icon is hidden (General › Show in menu bar is off).
    var isMenuBarIconHidden: () -> Bool
    /// "Pause Scrollio" is on.
    var isPaused: () -> Bool
    /// What the switch shows: the choice the user leaves with.
    var opensAtLogin: () -> Bool
    /// macOS waits for the login item to be approved in System Settings.
    var loginItemWaitsForApproval: () -> Bool

    init(
        isMenuBarIconHidden: @escaping () -> Bool,
        isPaused: @escaping () -> Bool,
        opensAtLogin: @escaping () -> Bool,
        loginItemWaitsForApproval: @escaping () -> Bool,
        target: AnyObject, loginAction: Selector, nextAction: Selector
    ) {
        self.isMenuBarIconHidden = isMenuBarIconHidden
        self.isPaused = isPaused
        self.opensAtLogin = opensAtLogin
        self.loginItemWaitsForApproval = loginItemWaitsForApproval
        artwork = WelcomeGuideFinishPicture(frame: NSRect(origin: .zero, size: WelcomeGuideLayout.pictureSize))
        picture = artwork
        let title = WelcomeGuideText.makeTitle(WelcomeGuideText.localized("intro-finish-title"))
        let text = WelcomeGuideText.makeText("")
        let next = WelcomeGuideNextBox(
            width: WelcomeGuideLayout.rowBoxWidth,
            rows: WelcomeGuideNextPlace.allCases.map { WelcomeGuideNextRow(place: $0, target: target, action: nextAction) }
        )
        let login = PreferencesSwitchRow(
            title: WelcomeGuideText.localized("general-launch-at-login"),
            explanation: WelcomeGuideText.localized("general-launch-at-login-hint"),
            target: target, action: loginAction
        )
        let box = PreferencesGroupBox(width: WelcomeGuideLayout.rowBoxWidth, rows: [login])
        let (view, stack) = WelcomeGuideText.makeContent([title, text, next, box])
        stack.setCustomSpacing(WelcomeGuideLayout.titleToText, after: title)
        stack.setCustomSpacing(WelcomeGuideLayout.textToControl, after: text)
        stack.setCustomSpacing(WelcomeGuideLayout.controlToControl, after: next)
        content = view
        titleLabel = title
        textLabel = text
        nextBox = next
        loginRow = login
        loginBox = box
        refresh()
    }

    func refresh() {
        let hidden = isMenuBarIconHidden()
        let paused = isPaused()
        titleLabel.stringValue = WelcomeGuideText.localized(Self.titleKey(iconHidden: hidden, paused: paused))
        textLabel.stringValue = WelcomeGuideText.localized(Self.textKey(iconHidden: hidden, paused: paused))
        artwork.isIconHidden = hidden
        loginRow.isOn = opensAtLogin()
        // As General says it: an item that waits for approval is not on yet.
        loginRow.explanation = WelcomeGuideText.localized(
            loginItemWaitsForApproval() ? "general-launch-at-login-waiting" : "general-launch-at-login-hint"
        )
    }

    func setShown(_ shown: Bool) {
        if shown { refresh() }
        artwork.setAnimating(shown)
    }

    /// The title: "Scrollio is ready", except while it is paused with its menu bar icon
    /// hidden. The text under it then only says how to reach Settings, and nothing else on
    /// the step would tell that Scrollio does not run.
    static func titleKey(iconHidden: Bool, paused: Bool) -> String {
        return iconHidden && paused ? "intro-finish-title-hidden-icon-paused" : "intro-finish-title"
    }

    /// The sentence under the title; paused, it does not claim that Scrollio runs.
    static func textKey(iconHidden: Bool, paused: Bool) -> String {
        guard iconHidden else { return "intro-finish-text" }
        return paused ? "intro-finish-hidden-icon-paused" : "intro-status-granted-detail-hidden-icon"
    }
}

// MARK: - Where to go next

/// A pane of Settings the last step leads to, in the sidebar's order.
enum WelcomeGuideNextPlace: CaseIterable {
    case buttons, gestures, ring

    /// The pane's identifier, as the sidebar and `showPreferencesWindow` know it.
    var paneIdentifier: String {
        switch self {
        case .buttons: return PANEL_IDENTIFIER.buttons
        case .gestures: return GesturesPreferencesViewController.tabIdentifier
        case .ring: return RingPreferencesViewController.tabIdentifier
        }
    }

    /// The pane as the sidebar shows it: its symbol on its coloured tile.
    var pane: PreferencesPane? {
        return PreferencesPane.all.first { $0.identifier == paneIdentifier }
    }

    /// The pane's name as the sidebar shows it. The sidebar names Gestures and the
    /// Shortcut Ring by these keys; Buttons' sidebar title comes from the storyboard, and
    /// an app's page names the same place "Buttons" with `apps-detail-part-buttons`.
    var title: String {
        switch self {
        case .buttons: return WelcomeGuideText.localized("apps-detail-part-buttons")
        case .gestures: return WelcomeGuideText.localized("gestures-tab-title")
        case .ring: return WelcomeGuideText.localized("ring-tab-title")
        }
    }

    /// What the pane is for, in a few words.
    var hint: String {
        switch self {
        case .buttons: return WelcomeGuideText.localized("intro-finish-next-buttons")
        case .gestures: return WelcomeGuideText.localized("intro-finish-next-gestures")
        case .ring: return WelcomeGuideText.localized("intro-finish-next-ring")
        }
    }
}

/// The box of the "where next" rows, drawn as the boxes of the Settings panes
/// (PreferencesGroupBox): the same fill, hairlines between the rows, an outline under
/// Increase Contrast. Its rows are buttons, which a PreferencesGroupBox does not hold.
final class WelcomeGuideNextBox: WelcomeGuideFlippedView {

    let rows: [WelcomeGuideNextRow]

    init(width: CGFloat, rows: [WelcomeGuideNextRow]) {
        self.rows = rows
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 0))
        translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        var constraints = [
            widthAnchor.constraint(equalToConstant: width),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ]
        constraints += rows.map { $0.widthAnchor.constraint(equalTo: stack.widthAnchor) }
        NSLayoutConstraint.activate(constraints)
    }

    required init?(coder: NSCoder) {
        fatalError("built in code")
    }

    /// The hairlines in the box's (flipped) coordinates: on top of every row but the first,
    /// inset as the rows' texts are in the panes, one pixel thick.
    var separatorRects: [NSRect] {
        let inset = PreferencesGroupedForm.rowHorizontalInset
        let thickness = 1 / max(1, window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
        return rows.dropFirst().map { row in
            let top = convert(row.bounds, from: row).minY
            return NSRect(x: inset, y: top, width: bounds.width - 2 * inset, height: thickness)
        }
    }

    override func layout() {
        super.layout()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = PreferencesGroupedForm.boxCornerRadius
        PreferencesGroupedForm.boxFillColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        PreferencesGroupedForm.hairlineColor.setFill()
        separatorRects.forEach { $0.fill() }
        if PreferencesGroupedForm.isHighContrast(effectiveAppearance) {
            PreferencesGroupedForm.drawOutline(of: bounds)
        }
    }
}

/// One row of the "where next" box: the sidebar's tile and the pane's name on the left,
/// the hint and a chevron on the right, all on one line (two-line rows do not fit the
/// window with "Open at login" under them). The whole row is one button: a click anywhere
/// on it sends the action when the mouse goes up on it, as a push button does; Space and
/// VoiceOver press it too. Not the window's default button: that is Done.
final class WelcomeGuideNextRow: NSButton {

    /// 36 pt, as a row of a Settings box; 28 pt in the window of a short screen, where the
    /// step would otherwise come closer to the bar than the grid allows.
    static var height: CGFloat {
        return WelcomeGuideLayout.metrics == .tight ? 28 : 36
    }
    static let tileSize = PreferencesSidebarViewController.tileSize
    static let tileSpacing: CGFloat = 8
    static let chevronSize = NSSize(width: 10, height: 16)
    static let chevronSpacing: CGFloat = 8
    /// The least room between the name and the hint.
    static let hintSpacing: CGFloat = 12
    /// The pressed fill and the focus ring stand this far inside the row, with the
    /// corners of a list's selection (PreferencesListBox).
    static let highlightInset = NSSize(width: 4, height: 2)
    static let highlightRadius = PreferencesListBox.selectionCornerRadius

    let place: WelcomeGuideNextPlace
    let tileView: NSImageView
    let nameLabel: NSTextField
    let hintLabel: NSTextField
    let chevronView: NSImageView

    init(place: WelcomeGuideNextPlace, target: AnyObject?, action: Selector?) {
        self.place = place
        tileView = PreferencesListImageView()
        nameLabel = NSTextField(labelWithString: place.title)
        hintLabel = NSTextField(labelWithString: place.hint)
        chevronView = PreferencesListImageView()
        super.init(frame: NSRect(x: 0, y: 0, width: WelcomeGuideLayout.rowBoxWidth, height: Self.height))
        self.target = target
        self.action = action
        setButtonType(.momentaryPushIn)
        isBordered = false
        title = ""
        imagePosition = .noImage
        translatesAutoresizingMaskIntoConstraints = false
        // (A button without a title of its own reads as an unknown element otherwise.)
        setAccessibilityRole(.button)
        setAccessibilityLabel(place.title)
        setAccessibilityHelp(place.hint)

        if let pane = place.pane {
            tileView.image = PreferencesSidebarViewController.tileImage(symbolName: pane.symbolName, color: pane.tileColor)
        }
        tileView.imageScaling = .scaleNone
        let chevron = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        chevronView.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?.withSymbolConfiguration(chevron)
        chevronView.imageScaling = .scaleNone
        chevronView.contentTintColor = .tertiaryLabelColor
        nameLabel.font = PreferencesGroupedForm.titleFont
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        hintLabel.font = PreferencesGroupedForm.explanationFont
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.alignment = .right
        hintLabel.lineBreakMode = .byTruncatingTail
        // The name keeps its room; a hint too long for the row is cut short.
        hintLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        for view in [tileView, nameLabel, hintLabel, chevronView] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.setAccessibilityElement(false)
            addSubview(view)
        }
        let inset = PreferencesGroupedForm.rowHorizontalInset
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.height),
            tileView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            tileView.centerYAnchor.constraint(equalTo: centerYAnchor),
            tileView.widthAnchor.constraint(equalToConstant: Self.tileSize),
            tileView.heightAnchor.constraint(equalToConstant: Self.tileSize),
            nameLabel.leadingAnchor.constraint(equalTo: tileView.trailingAnchor, constant: Self.tileSpacing),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevronView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            chevronView.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevronView.widthAnchor.constraint(equalToConstant: Self.chevronSize.width),
            chevronView.heightAnchor.constraint(equalToConstant: Self.chevronSize.height),
            hintLabel.trailingAnchor.constraint(equalTo: chevronView.leadingAnchor, constant: -Self.chevronSpacing),
            hintLabel.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor, constant: Self.hintSpacing),
            hintLabel.firstBaselineAnchor.constraint(equalTo: nameLabel.firstBaselineAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("built in code")
    }

    override var isFlipped: Bool { return true }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: NSView.noIntrinsicMetric, height: Self.height)
    }

    override var isHighlighted: Bool {
        didSet { if isHighlighted != oldValue { needsDisplay = true } }
    }

    /// The pressed fill and the focus ring.
    var highlightRect: NSRect {
        return bounds.insetBy(dx: Self.highlightInset.width, dy: Self.highlightInset.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isHighlighted else { return }
        WelcomeGuidePalette.pressed.setFill()
        NSBezierPath(roundedRect: highlightRect, xRadius: Self.highlightRadius, yRadius: Self.highlightRadius).fill()
    }

    override var focusRingMaskBounds: NSRect {
        return highlightRect
    }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: highlightRect, xRadius: Self.highlightRadius, yRadius: Self.highlightRadius).fill()
    }

    // MARK: The mouse

    /// The tile, the texts and the chevron are the row's: a click on them is the row's.
    override func hitTest(_ point: NSPoint) -> NSView? {
        return super.hitTest(point) == nil ? nil : self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override var mouseDownCanMoveWindow: Bool {
        return false
    }

    /// As a push button tracks: pressed while the pointer is on the row, sent when the
    /// button goes up on it; released elsewhere, nothing happens.
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
            sendAction(action, to: target)
        }
    }

    private func contains(_ event: NSEvent) -> Bool {
        return bounds.contains(convert(event.locationInWindow, from: nil))
    }

    /// Space on the focused row, and VoiceOver's press.
    override func performClick(_ sender: Any?) {
        guard isEnabled else { return }
        sendAction(action, to: target)
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        sendAction(action, to: target)
        return true
    }
}

/// The top of a desktop: the menu bar with Scrollio's icon, and its menu under it.
final class WelcomeGuideFinishPicture: WelcomeGuideAnimatedView {

    static let loopLength: TimeInterval = 7.4
    static let menuBarHeight: CGFloat = 26
    static let iconSize = NSSize(width: 18, height: 18)
    /// The icon's place in the menu bar: among the status items on the right.
    static var iconRect: NSRect {
        return NSRect(x: 330, y: (menuBarHeight - iconSize.height) / 2, width: iconSize.width, height: iconSize.height)
    }
    static let menuWidth: CGFloat = 226
    static let menuItemHeight: CGFloat = 22
    static let menuPadding: CGFloat = 5
    static let separatorHeight: CGFloat = 9

    /// The items of the status-bar menu as it opens without a mouse battery to report: the
    /// title and its shortcut; nil is a separator.
    static var menuItems: [(title: String, shortcut: String)?] {
        return [
            (WelcomeGuideText.localized("status-menu-pause"), ""),
            (WelcomeGuideText.localized("main-menu-settings"), "⌘,"),
            nil,
            (WelcomeGuideText.localized("main-menu-quit"), "⌘Q"),
        ]
    }

    static var menuRect: NSRect {
        let height = menuItems.reduce(2 * menuPadding) { $0 + ($1 == nil ? separatorHeight : menuItemHeight) }
        let x = min(WelcomeGuideLayout.pictureSize.width - menuWidth - 8, iconRect.minX - 10)
        return NSRect(x: x, y: menuBarHeight + 4, width: menuWidth, height: height)
    }

    struct Frame: Equatable {
        /// Opacity and scale (1 = the icon's size) of the two rings.
        var rings: [CGFloat] = [0, 0]
        var ringScales: [CGFloat] = [1, 1]
        var menu: CGFloat = 0
        var menuDrop: CGFloat = 0
        var iconSelected = false
    }

    private(set) var shownFrame = Frame()

    /// General › Show in menu bar is off: the icon's place stays empty, nothing opens.
    var isIconHidden = false {
        didSet {
            guard isIconHidden != oldValue else { return }
            needsDisplay = true
            setAccessibilityLabel(WelcomeGuideText.localized(isIconHidden ? "intro-finish-picture-hidden-icon" : "intro-finish-picture"))
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(WelcomeGuideText.localized("intro-finish-picture"))
    }

    required init?(coder: NSCoder) {
        fatalError("built in code")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    /// Two rings out of the icon (from 0.3 s and 0.9 s, 1.2 s each), then the menu drops in at
    /// 1.5 s and stays until 7.0 s of the 7.4 s loop.
    static func frame(at time: TimeInterval) -> Frame {
        var loop = time.isFinite ? time.truncatingRemainder(dividingBy: loopLength) : 0
        if loop < 0 { loop += loopLength }
        var frame = Frame()
        for index in 0..<2 {
            let progress = (loop - 0.3 - Double(index) * 0.6) / 1.2
            let eased = easeOut(progress)
            frame.rings[index] = progress > 0 && progress < 1 ? CGFloat((1 - eased) * 0.9) : 0
            frame.ringScales[index] = CGFloat(1 + 1.3 * eased)
        }
        let open = easeOut((loop - 1.5) / 0.2)
        frame.menu = CGFloat(open - clamp01((loop - 7.0) / 0.25))
        frame.menuDrop = CGFloat((1 - open) * -4)
        frame.iconSelected = loop > 1.45 && loop < 7.1
        return frame
    }

    static var stillFrame: Frame {
        return Frame(menu: 1, iconSelected: true)
    }

    override func show(time: TimeInterval) {
        apply(Self.frame(at: time))
    }

    override func showStill() {
        apply(Self.stillFrame)
    }

    func apply(_ frame: Frame) {
        guard frame != shownFrame else { return }
        shownFrame = frame
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let frame = shownFrame
        let radius = WelcomeGuideLayout.pictureCornerRadius
        let card = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        card.addClip()
        NSGradient(starting: ScrollPreviewPalette.desktopStart, ending: ScrollPreviewPalette.desktopEnd)?
            .draw(in: bounds, angle: -30)

        // The menu bar: placeholders for the app's menus and the other status items.
        ScrollPreviewPalette.menuBar.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: Self.menuBarHeight).fill(using: .sourceOver)
        let ink = WelcomeGuidePalette.menuBarText
        let midY = Self.menuBarHeight / 2
        var x: CGFloat = 14
        for (index, width) in ([34, 22, 22, 26, 18] as [CGFloat]).enumerated() {
            ink.withAlphaComponent(index == 0 ? 0.85 : 0.45).setFill()
            capsule(NSRect(x: x, y: midY - (index == 0 ? 3 : 2.5), width: width, height: index == 0 ? 6 : 5)).fill()
            x += width + 14
        }
        let icon = Self.iconRect
        if isIconHidden {
            // Where the icon would be: an empty, dashed place.
            let place = NSBezierPath(roundedRect: icon.insetBy(dx: -5, dy: -1), xRadius: 5, yRadius: 5)
            place.lineWidth = 1
            place.setLineDash([3, 3], count: 2, phase: 0)
            ink.withAlphaComponent(0.35).setStroke()
            place.stroke()
        } else {
            if frame.iconSelected {
                WelcomeGuidePalette.menuBarSelection.setFill()
                NSBezierPath(roundedRect: icon.insetBy(dx: -5, dy: -1), xRadius: 5, yRadius: 5).fill()
            }
            drawStatusIcon(in: icon, colour: ink)
        }
        // The other status items and the clock: faint, so Scrollio's icon is what the eye finds.
        x = icon.maxX + 16
        ink.withAlphaComponent(0.28).setFill()
        for width in [22, 16, 14] as [CGFloat] {
            NSBezierPath(roundedRect: NSRect(x: x, y: midY - 5, width: width, height: 10), xRadius: 3, yRadius: 3).fill()
            x += width + 14
        }
        capsule(NSRect(x: bounds.width - 14 - 74, y: midY - 2.5, width: 74, height: 5)).fill()

        guard !isIconHidden else {
            NSGraphicsContext.restoreGraphicsState()
            ScrollPreviewPalette.cardEdge.setStroke()
            card.lineWidth = 1
            card.stroke()
            return
        }
        // The pulses grow along the menu bar, inside it.
        for index in 0..<2 where frame.rings[index] > 0 {
            let grow = (frame.ringScales[index] - 1) / 1.3
            let rect = icon.insetBy(dx: -5 - 14 * grow, dy: -1 - 2 * grow)
            let ring = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
            ring.lineWidth = 2
            NSColor.controlAccentColor.withAlphaComponent(frame.rings[index]).setStroke()
            ring.stroke()
        }

        if frame.menu > 0 {
            drawMenu(alpha: frame.menu, drop: frame.menuDrop)
        }
        NSGraphicsContext.restoreGraphicsState()
        ScrollPreviewPalette.cardEdge.setStroke()
        card.lineWidth = 1
        card.stroke()
    }

    private func capsule(_ rect: NSRect) -> NSBezierPath {
        let radius = min(rect.width, rect.height) / 2
        return NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    }

    /// The status item's own (template) image, in the menu bar's ink.
    private func drawStatusIcon(in rect: NSRect, colour: NSColor) {
        guard let image = NSImage(named: "AppStatusBarIcon"), let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.beginTransparencyLayer(in: rect, auxiliaryInfo: nil)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        colour.setFill()
        rect.fill(using: .sourceIn)
        context.endTransparencyLayer()
        context.restoreGState()
    }

    private func drawMenu(alpha: CGFloat, drop: CGFloat) {
        let menu = Self.menuRect.offsetBy(dx: 0, dy: drop)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(alpha)
        NSGraphicsContext.current?.cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
        let path = NSBezierPath(roundedRect: menu, xRadius: 10, yRadius: 10)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowBlurRadius = 14
        shadow.shadowOffset = .zero
        shadow.set()
        WelcomeGuidePalette.menu.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
        WelcomeGuidePalette.menuEdge.setStroke()
        path.lineWidth = 0.5
        path.stroke()

        var y = menu.minY + Self.menuPadding
        let font = NSFont.menuFont(ofSize: 13)
        for item in Self.menuItems {
            guard let item else {
                WelcomeGuidePalette.hairline.setFill()
                NSRect(x: menu.minX + 14, y: y + Self.separatorHeight / 2, width: menu.width - 28, height: 1).fill(using: .sourceOver)
                y += Self.separatorHeight
                continue
            }
            let title = NSAttributedString(string: item.title, attributes: [
                .font: font, .foregroundColor: WelcomeGuidePalette.menuText,
            ])
            let size = title.size()
            title.draw(at: NSPoint(x: menu.minX + 22, y: y + (Self.menuItemHeight - size.height) / 2))
            if !item.shortcut.isEmpty {
                let shortcut = NSAttributedString(string: item.shortcut, attributes: [
                    .font: font, .foregroundColor: WelcomeGuidePalette.menuShortcut,
                ])
                let shortcutSize = shortcut.size()
                shortcut.draw(at: NSPoint(x: menu.maxX - 14 - shortcutSize.width, y: y + (Self.menuItemHeight - shortcutSize.height) / 2))
            }
            y += Self.menuItemHeight
        }
        NSGraphicsContext.current?.cgContext.endTransparencyLayer()
        NSGraphicsContext.restoreGraphicsState()
    }
}
