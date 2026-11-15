//
//  PreferencesDisclosureSection.swift
//  Scrollio
//  A titled section of a pane whose title can fold away what is under it, as the
//  collapsible sections of System Settings do: the section's title with a chevron after it
//  ("Shortcuts ›"). A click on it (Space while it has the keyboard, VoiceOver's press)
//  opens the section, the chevron turns down and everything in it can be used; another
//  click folds it again. While the section cannot fold (`isCollapsible` off) it is an
//  ordinary titled section: the same title at the same place as plain text, and what is
//  under it shown.
//
//  A pane folds a section while what it sets cannot run yet (nothing opens the Shortcut
//  Ring, no button runs Gesture Navigation): the settings stay, quietly, a click away. The
//  pane decides when a section can fold and refits itself (`onExpandedChange`); this view
//  only shows and hides. A section that becomes foldable starts folded.
//
//  The title is the kit's section title (`PreferencesGroupedForm.makeSectionTitle`) in both
//  states, so folding never moves it. The chevron turns in `animationDuration` and what
//  opens fades in over the same time; with Reduce Motion both happen at once. To VoiceOver
//  the title is a disclosure triangle with the section's name that says "collapsed" or
//  "expanded"; with keyboard navigation on (System Settings › Keyboard) Tab reaches it as
//  it reaches a button, and Space opens or folds it. A control that folds away gives up the
//  keyboard.
//

import Cocoa

final class PreferencesDisclosureSection: NSView {

    /// How long the chevron turns and what opens fades in.
    static let animationDuration: TimeInterval = 0.2

    /// Runs a change as one animation of `duration`, easing in and out: the chevron's turn
    /// and the body's fade. The change is told whether to go through `animator()` (true
    /// here). Tests replace it and ask for the change at once: an animation moves with the
    /// display's frames, a window that is on no screen gets none, and a value set through
    /// `animator()` arrives only with a frame, whatever the duration.
    static var animate: (TimeInterval, (_ animated: Bool) -> Void) -> Void = { duration, change in
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            change(true)
        }
    }

    let title: String
    /// What the title folds away.
    let body: NSView
    /// The title as plain text, while the section cannot fold.
    let titleLabel: NSTextField
    /// The title with its chevron, while it can.
    let disclosure: PreferencesDisclosureTitle

    /// The user opened (true) or folded (false) the section.
    var onExpandedChange: ((Bool) -> Void)?
    /// Tests replace it.
    var prefersReducedMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Whether the title folds what is under it. Turned on, the section starts folded.
    var isCollapsible = false {
        didSet {
            guard isCollapsible != oldValue else { return }
            if isCollapsible {
                isExpanded = false
                disclosure.setExpanded(false, animated: false)
            }
            apply(fading: false)
        }
    }

    /// Open, while the section can fold.
    private(set) var isExpanded = false

    /// What is under the title shows: the section cannot fold, or it is open.
    var showsBody: Bool {
        return !isCollapsible || isExpanded
    }

    private var bottomOnBody: NSLayoutConstraint!
    private var bottomOnTitle: NSLayoutConstraint!

    /// - Parameters:
    ///   - body: what the title folds away, as wide as the section (a box, or a muted line
    ///     and a box).
    ///   - spacing: between the title and `body`.
    init(title: String, body: NSView, spacing: CGFloat = PreferencesGroupedForm.sectionTitleSpacing) {
        self.title = title
        self.body = body
        titleLabel = PreferencesGroupedForm.makeSectionTitle(title)
        disclosure = PreferencesDisclosureTitle(title: title)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        body.translatesAutoresizingMaskIntoConstraints = false
        for view in [titleLabel, disclosure, body] as [NSView] {
            addSubview(view)
        }
        let inset = PreferencesGroupedForm.rowHorizontalInset
        // The plain title keeps its place while it is hidden: the chevron's title stands on
        // it, and the body and the section's bottom are measured from it.
        bottomOnBody = body.bottomAnchor.constraint(equalTo: bottomAnchor)
        bottomOnTitle = titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -inset),
            disclosure.topAnchor.constraint(equalTo: titleLabel.topAnchor),
            disclosure.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            disclosure.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -inset),
            body.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: spacing),
            body.leadingAnchor.constraint(equalTo: leadingAnchor),
            body.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        disclosure.onPress = { [weak self] in self?.toggle() }
        apply(fading: false)
    }

    required init?(coder: NSCoder) {
        fatalError("PreferencesDisclosureSection is built in code")
    }

    /// Opens or folds the section; nothing while it cannot fold.
    func setExpanded(_ expanded: Bool, animated: Bool = false) {
        guard isCollapsible, expanded != isExpanded else { return }
        isExpanded = expanded
        let animates = animated && !prefersReducedMotion()
        disclosure.setExpanded(expanded, animated: animates)
        apply(fading: animates && expanded)
    }

    /// The title was clicked, or pressed with the keyboard or by VoiceOver.
    func toggle() {
        guard isCollapsible else { return }
        setExpanded(!isExpanded, animated: true)
        onExpandedChange?(isExpanded)
    }

    private func apply(fading: Bool) {
        let shows = showsBody
        if !shows {
            giveUpKeyboard()
        }
        titleLabel.isHidden = isCollapsible
        disclosure.isHidden = !isCollapsible
        body.isHidden = !shows
        NSLayoutConstraint.deactivate([bottomOnBody, bottomOnTitle])
        NSLayoutConstraint.activate([shows ? bottomOnBody : bottomOnTitle])
        guard fading else {
            body.alphaValue = 1
            return
        }
        body.alphaValue = 0
        Self.animate(Self.animationDuration) { animated in
            (animated ? body.animator() : body).alphaValue = 1
        }
    }

    /// A control that folds away does not keep the keyboard: the title takes it while it
    /// can (keyboard navigation on), else the window.
    private func giveUpKeyboard() {
        guard let window, let responder = window.firstResponder as? NSView,
              responder.isDescendant(of: body) else { return }
        if !window.makeFirstResponder(disclosure) {
            window.makeFirstResponder(nil)
        }
    }
}

// MARK: - Title

/// The title of a section that can fold, with its chevron: the whole of it is the control.
/// A disclosure triangle to VoiceOver.
final class PreferencesDisclosureTitle: NSView {

    /// Between the title and the chevron's box.
    static let chevronSpacing: CGFloat = 3

    let label: NSTextField
    let chevron: PreferencesDisclosureChevron
    /// A click, Space, or VoiceOver's press.
    var onPress: (() -> Void)?

    private(set) var isExpanded = false
    /// The mouse is down on the title (and still over it).
    private(set) var isPressed = false {
        didSet {
            guard isPressed != oldValue else { return }
            label.textColor = isPressed ? .secondaryLabelColor : .labelColor
            chevron.isPressed = isPressed
        }
    }

    init(title: String) {
        label = PreferencesGroupedForm.makeSectionTitle(title)
        label.setAccessibilityElement(false)
        chevron = PreferencesDisclosureChevron()
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        focusRingType = .default
        addSubview(label)
        addSubview(chevron)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            chevron.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: Self.chevronSpacing),
            chevron.centerYAnchor.constraint(equalTo: label.centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("PreferencesDisclosureTitle is built in code")
    }

    /// Turns the chevron: right while folded, down while open.
    func setExpanded(_ expanded: Bool, animated: Bool) {
        let changed = expanded != isExpanded
        isExpanded = expanded
        let turn: CGFloat = expanded ? 1 : 0
        if animated {
            PreferencesDisclosureSection.animate(PreferencesDisclosureSection.animationDuration) { animated in
                (animated ? chevron.animator() : chevron).turn = turn
            }
        } else {
            chevron.turn = turn
        }
        if changed {
            NSAccessibility.post(element: self, notification: .valueChanged)
        }
    }

    // MARK: Mouse

    /// The label and the chevron do not take the clicks: the title does.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, frame.contains(point) else { return nil }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
    }

    override func mouseDragged(with event: NSEvent) {
        isPressed = isInside(event)
    }

    override func mouseUp(with event: NSEvent) {
        let inside = isInside(event)
        isPressed = false
        if inside {
            onPress?()
        }
    }

    private func isInside(_ event: NSEvent) -> Bool {
        return bounds.contains(convert(event.locationInWindow, from: nil))
    }

    // MARK: Keyboard

    /// As a button: in the key view loop while keyboard navigation is on.
    override var acceptsFirstResponder: Bool {
        return NSApp?.isFullKeyboardAccessEnabled ?? false
    }

    override func keyDown(with event: NSEvent) {
        guard event.charactersIgnoringModifiers == " " else {
            return super.keyDown(with: event)
        }
        onPress?()
    }

    override var focusRingMaskBounds: NSRect {
        return bounds.insetBy(dx: -3, dy: -1)
    }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: focusRingMaskBounds, xRadius: 4, yRadius: 4).fill()
    }

    override func layout() {
        super.layout()
        noteFocusRingMaskChanged()
    }

    // MARK: Accessibility

    override func isAccessibilityElement() -> Bool {
        return true
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        return .disclosureTriangle
    }

    override func accessibilityLabel() -> String? {
        return label.stringValue
    }

    /// 1 open, 0 folded: what VoiceOver reads as "expanded" or "collapsed".
    override func accessibilityValue() -> Any? {
        return NSNumber(value: isExpanded ? 1 : 0)
    }

    override func isAccessibilityExpanded() -> Bool {
        return isExpanded
    }

    override func isAccessibilityEnabled() -> Bool {
        return true
    }

    override func accessibilityPerformPress() -> Bool {
        onPress?()
        return true
    }
}

// MARK: - Chevron

/// The chevron after the title: "chevron.right" in the secondary label colour, turned a
/// quarter clockwise by `turn` (0 right, 1 down). `turn` animates through `animator()`.
final class PreferencesDisclosureChevron: NSView {

    static let size = NSSize(width: 14, height: 14)
    static let pointSize: CGFloat = 11

    @objc dynamic var turn: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    var isPressed = false {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        fatalError("PreferencesDisclosureChevron is built in code")
    }

    override class func defaultAnimation(forKey key: NSAnimatablePropertyKey) -> Any? {
        if key == "turn" {
            return CABasicAnimation()
        }
        return super.defaultAnimation(forKey: key)
    }

    override var intrinsicContentSize: NSSize {
        return Self.size
    }

    /// The colour it is drawn in.
    var color: NSColor {
        return isPressed ? .tertiaryLabelColor : .secondaryLabelColor
    }

    private static let symbol: NSImage? = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold))

    override func draw(_ dirtyRect: NSRect) {
        guard let symbol = Self.symbol else { return }
        let color = self.color
        let size = symbol.size
        // The symbol in the colour, its transparency too (source-in: the colour where the
        // symbol is), made at draw time so it follows the appearance.
        let tinted = NSImage(size: size, flipped: false) { rect in
            symbol.draw(in: rect)
            color.set()
            rect.fill(using: .sourceIn)
            return true
        }
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: bounds.midX, yBy: bounds.midY)
        // Clockwise: the view is not flipped.
        transform.rotate(byDegrees: -90 * turn)
        transform.concat()
        tinted.draw(in: NSRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        NSGraphicsContext.restoreGraphicsState()
    }
}
