//
//  ButtonBindingRow.swift
//  Mos
//  One button of the Buttons pane: a row of the kit's list with a small picture of where
//  the button is (ButtonsMouseMiniature), the button's name, a line under it only when
//  there is something to say (what the action needs, a problem after an orange sign, or
//  that a numbered button is an extra one), an ⓘ that explains a problem, and the action
//  pull-down. A numbered button's picture (and the row's context menu) opens "Which Button
//  Is This?" (ButtonPlaceMenu). A button of the connected mouse has its row whether or not
//  it has a binding: without an action its pull-down reads "Default" and the line says
//  what the button then does, and it is never removed with "−".
//

import Cocoa

// MARK: - The line under the title

/// What the line under a button's title says, if anything. Pure: the pane and its tests
/// share the rules.
struct ButtonRowNote: Equatable {

    enum Kind: Equatable {
        /// Gesture Navigation: the directions are under Gestures.
        case gestureNavigation
        /// Gesture Navigation on a key (from before): a key cannot run it.
        case keyGestureNavigation
        /// A scroll action works while the button is held.
        case holdAction
        /// No action yet.
        case noAction
        /// A button the Mac knows only by its number ("Button 5"): where it is, the mouse
        /// tells when "+" records it.
        case extraButton
        /// The button is also a key under Scrolling › While you hold a key.
        case alsoScrollKey
        /// What the Logitech mouse says about the button.
        case capture(ButtonCapturePresentationStatus)
        /// A button of the connected mouse without an action: what it does by itself.
        case defaultAction
    }

    enum Tone: Equatable {
        /// Secondary text, like any explanation.
        case plain
        /// After an orange warning sign.
        case problem
        /// After a light bulb in the accent colour: a better way exists.
        case hint
    }

    let kind: Kind
    let text: String

    var tone: Tone {
        switch kind {
        case .gestureNavigation, .holdAction, .noAction, .extraButton, .defaultAction:
            return .plain
        case .alsoScrollKey, .keyGestureNavigation:
            return .problem
        case .capture(let status):
            return status == .standardMouseAliasAvailable ? .hint : .problem
        }
    }

    /// The ⓘ next to the pull-down explains it.
    var hasDetails: Bool {
        return tone != .plain
    }

    /// The ⓘ popover offers "Use Standard Button".
    var offersStandardButton: Bool {
        return kind == .capture(.standardMouseAliasAvailable)
    }

    var detailTitle: String {
        switch kind {
        case .alsoScrollKey: return Self.text("buttons-scroll-key-title")
        case .keyGestureNavigation: return Self.text("buttons-gesture-needs-mouse-button")
        case .capture(let status): return Self.text(status.titleKey)
        case .gestureNavigation, .holdAction, .noAction, .extraButton, .defaultAction: return text
        }
    }

    var detailText: String {
        switch kind {
        case .alsoScrollKey: return Self.text("buttons-scroll-key-detail")
        case .keyGestureNavigation: return Self.text("buttons-gesture-needs-mouse-button-detail")
        case .capture(let status): return Self.text(status.detailKey)
        case .gestureNavigation, .holdAction, .noAction, .extraButton, .defaultAction: return ""
        }
    }

    /// The line for `binding`: a problem first, then what the action needs, then for a
    /// numbered button that it is an extra one, else nothing.
    /// - Parameters:
    ///   - captureStatus: what the Logitech mouse says about the trigger (`.normal` for
    ///     any other button).
    ///   - scrollHoldKeys: the keys of Scrolling › While you hold a key.
    ///   - standardButtonName: the standard button a Logitech one can stand in for.
    static func make(
        for binding: ButtonBinding,
        captureStatus: ButtonCapturePresentationStatus,
        scrollHoldKeys: [ScrollHotkey],
        standardButtonName: String? = nil
    ) -> ButtonRowNote? {
        let trigger = binding.triggerEvent
        if trigger.type == .mouse, scrollHoldKeys.contains(where: { $0.type == .mouse && $0.code == trigger.code }) {
            return ButtonRowNote(kind: .alsoScrollKey, text: text("buttons-note-scroll-key"))
        }
        if captureStatus.shouldShowIndicator {
            let line: String
            if captureStatus == .standardMouseAliasAvailable {
                let name = standardButtonName ?? text("buttons-trigger-back")
                line = String(format: text(captureStatus.noteKey), name)
            } else {
                line = text(captureStatus.noteKey)
            }
            return ButtonRowNote(kind: .capture(captureStatus), text: line)
        }
        if let action = actionNote(for: binding) {
            return action
        }
        // Placed: its name says where it is.
        if ButtonTriggerPicture.number(for: trigger) != nil, trigger.placedPart == nil {
            return ButtonRowNote(kind: .extraButton, text: text("buttons-note-extra-button"))
        }
        return nil
    }

    /// The line of a button of the connected mouse without an action ("Default"): that it
    /// is also a key under Scrolling › While you hold a key, else what it does by itself,
    /// only where that is certain. Nothing when Scrollio catches its Logitech control for
    /// another binding (the plain press then reaches only Scrollio).
    /// - Parameters:
    ///   - trigger: what the row stores once it gets an action. A numbered button the user
    ///     placed there sends its number, not a standard button: no claim beyond its own.
    ///   - isCaught: `ButtonsListLayout.catchesControl(of:in:)`.
    static func makeDefault(
        for part: ButtonsMousePart,
        trigger: RecordedEvent,
        scrollHoldKeys: [ScrollHotkey],
        isCaught: Bool
    ) -> ButtonRowNote? {
        let isScrollKey = scrollHoldKeys.contains { key in
            key.type == .mouse && ButtonsMousePart.part(for: RecordedEvent(type: .mouse, code: key.code, modifiers: 0, deviceFilter: nil)) == part
        }
        if isScrollKey {
            return ButtonRowNote(kind: .alsoScrollKey, text: text("buttons-note-scroll-key"))
        }
        guard !isCaught else { return nil }
        let key = ButtonTriggerPicture.number(for: trigger) == nil ? part.defaultExplanationKey : "buttons-default-own"
        return ButtonRowNote(kind: .defaultAction, text: text(key))
    }

    /// What the action needs: an action at all, the directions of Gesture Navigation (a
    /// mouse button: on a key it does nothing), the button held for a scroll action.
    private static func actionNote(for binding: ButtonBinding) -> ButtonRowNote? {
        switch CellActionState(binding: binding) {
        case .unbound, .recordingPrompt:
            return ButtonRowNote(kind: .noAction, text: text("buttons-note-no-action"))
        case .namedShortcut(let shortcut):
            if shortcut.identifier == SystemShortcut.mouseGestureNavigation.identifier {
                if binding.triggerEvent.type == .keyboard {
                    return ButtonRowNote(kind: .keyGestureNavigation, text: text("buttons-note-key-gesture-navigation"))
                }
                return ButtonRowNote(kind: .gestureNavigation, text: text("buttons-note-gesture-navigation"))
            }
            if SystemShortcut.mouseScrollCategory.shortcuts.contains(where: { $0.identifier == shortcut.identifier }) {
                return ButtonRowNote(kind: .holdAction, text: text("buttons-note-hold-action"))
            }
            return nil
        case .customBinding, .openTarget:
            return nil
        }
    }

    private static func text(_ key: String) -> String {
        return NSLocalizedString(key, comment: "")
    }
}

// MARK: - The row

final class ButtonBindingRow: PreferencesListRow {

    /// Between the ⓘ and the pull-down, and between the title and the ⓘ.
    static let infoSpacing: CGFloat = 8

    /// The binding the row shows. On a button of the connected mouse without one, the
    /// binding the row would store once an action is chosen (`isStored` is false).
    private(set) var binding: ButtonBinding
    /// `binding` is in the stored list.
    private(set) var isStored: Bool
    /// The button of the connected mouse the row is about; nil for any other binding. The
    /// row stays while the mouse does, whatever its binding.
    let part: ButtonsMousePart?
    private(set) var note: ButtonRowNote?
    /// What the picture before the title shows.
    private(set) var picture: ButtonTriggerPicture
    /// The mouse the picture is drawn on.
    private(set) var mouse: MouseArtworkModel
    let pullDown: ButtonActionPullDown
    /// The ⓘ before the pull-down, on the title line; it shows while the note is a problem
    /// or a hint. It is not part of the accessory: the note under the title runs on below
    /// it, so a problem takes two lines, not three.
    let infoButton: NSButton
    /// Over the picture of a numbered button ("Button 6"): opens "Which Button Is This?".
    /// Hidden for a button whose place is known and for a key.
    let placeButton = ButtonPlacePictureButton()
    /// The picture was clicked: the pane opens the menu under it.
    var onPlaceRequested: ((NSView) -> Void)?
    /// The menu of a right-click on the row: "Which Button Is This?" for
    /// a numbered button, nil otherwise.
    var placeMenu: (() -> NSMenu?)?
    /// Keeps the title off the ⓘ while it shows.
    private var titleBeforeInfo: NSLayoutConstraint?
    /// The picture the icon shows now, on which mouse, and whether drawn for the selection.
    private var shownPicture: (picture: ButtonTriggerPicture, mouse: MouseArtworkModel, highlighted: Bool)?

    /// - Parameters:
    ///   - part: the button of the connected mouse the row is about (its id is the part);
    ///     nil: a row of `binding` (its id is the binding's).
    ///   - isStored: `binding` is stored; false for a button of the connected mouse that has
    ///     no binding.
    init(
        binding: ButtonBinding,
        title: String,
        note: ButtonRowNote?,
        mouse: MouseArtworkModel,
        pullDown: ButtonActionPullDown,
        part: ButtonsMousePart? = nil,
        isStored: Bool = true
    ) {
        self.binding = binding
        self.isStored = isStored
        self.part = part
        self.note = note
        self.mouse = mouse
        self.pullDown = pullDown
        pullDown.offersDefault = part != nil
        let picture = ButtonTriggerPicture.make(for: binding.triggerEvent, mouse: mouse)
        self.picture = picture

        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        let image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) ?? NSImage()
        let info = NSButton(image: image, target: nil, action: nil)
        info.isBordered = false
        info.imagePosition = .imageOnly
        info.contentTintColor = .secondaryLabelColor
        info.setAccessibilityLabel(NSLocalizedString("buttons-problem-info", comment: ""))
        info.translatesAutoresizingMaskIntoConstraints = false
        infoButton = info

        super.init(
            id: part.map { AnyHashable($0) } ?? AnyHashable(binding.id),
            title: title,
            explanation: note?.text,
            icon: .image(ButtonsMouseMiniature.image(for: picture, mouse: mouse, highlighted: false)),
            accessory: pullDown,
            centeredOn: pullDown,
            controls: [pullDown]
        )
        addSubview(info)
        let spacing = Self.infoSpacing
        NSLayoutConstraint.activate([
            info.trailingAnchor.constraint(equalTo: pullDown.leadingAnchor, constant: -spacing),
            info.centerYAnchor.constraint(equalTo: pullDown.centerYAnchor),
        ])
        titleBeforeInfo = titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: info.leadingAnchor, constant: -spacing)
        if let iconView {
            // A little larger than the picture, so its background has room around it.
            addSubview(placeButton)
            let outset = Self.placeButtonOutset
            NSLayoutConstraint.activate([
                placeButton.leadingAnchor.constraint(equalTo: iconView.leadingAnchor, constant: -outset),
                placeButton.trailingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: outset),
                placeButton.topAnchor.constraint(equalTo: iconView.topAnchor, constant: -outset),
                placeButton.bottomAnchor.constraint(equalTo: iconView.bottomAnchor, constant: outset),
            ])
            placeButton.target = self
            placeButton.action = #selector(placeClicked(_:))
        }
        // A button of the mouse is cleared with "Default", never removed.
        isRemovable = part == nil
        applyNote()
    }

    /// How far the picture's button reaches beyond the picture on each side.
    static let placeButtonOutset: CGFloat = 2

    required init?(coder: NSCoder) {
        fatalError("ButtonBindingRow is built in code")
    }

    /// Shows `binding` with `title` and `note` on `mouse`; the row and its pull-down stay the
    /// same views.
    func update(binding: ButtonBinding, title: String, note: ButtonRowNote?, mouse: MouseArtworkModel, isStored: Bool = true) {
        self.binding = binding
        self.isStored = isStored
        self.note = note
        self.mouse = mouse
        // "Use Standard Button" gives the row another trigger.
        picture = ButtonTriggerPicture.make(for: binding.triggerEvent, mouse: mouse)
        if self.title != title {
            self.title = title
        }
        explanation = note?.text
        pullDown.configure(with: binding)
        applyNote()
    }

    /// A button of the connected mouse without an action: its pull-down reads "Default".
    var isDefault: Bool {
        return part != nil && !CellActionState(binding: binding).hasBoundAction
    }

    /// The picture is a button only for a stored button the Mac knows by its number.
    var offersPlace: Bool {
        return isStored && ButtonTriggerPicture.number(for: binding.triggerEvent) != nil
    }

    @objc private func placeClicked(_ sender: NSButton) {
        onPlaceRequested?(sender)
    }

    /// A right-click on the row (not on its controls) offers "Which Button Is This?".
    override func menu(for event: NSEvent) -> NSMenu? {
        guard offersPlace, let menu = placeMenu?() else { return super.menu(for: event) }
        return menu
    }

    private func applyNote() {
        placeButton.isHidden = !offersPlace
        let details = note?.hasDetails ?? false
        infoButton.isHidden = !details
        titleBeforeInfo?.isActive = details
        infoButton.toolTip = details ? note?.detailTitle : nil
        infoButton.setAccessibilityHelp(details ? note?.detailTitle : nil)
        applyEnabled()
    }

    /// The colour of the note's sign: orange for a problem, the accent colour for a hint.
    static func symbolColor(for tone: ButtonRowNote.Tone) -> NSColor {
        return tone == .problem ? .systemOrange : .controlAccentColor
    }

    /// The note's sign before its text, the sign in its colour and the text in the colour
    /// of any explanation (orange or accent-coloured text is too faint on a light box to
    /// read); all white on the selection.
    override func applyEnabled() {
        super.applyEnabled()
        applyPicture()
        placeButton.isOnSelection = isHighlighted
        // The ⓘ draws like the pull-down: light on the accent-coloured selection.
        infoButton.appearance = accessory?.appearance
        infoButton.contentTintColor = isHighlighted ? .alternateSelectedControlTextColor : .secondaryLabelColor
        guard let note, note.tone != .plain else { return }
        let symbolColor: NSColor
        let textColor: NSColor
        if isHighlighted {
            symbolColor = NSColor.alternateSelectedControlTextColor.withAlphaComponent(0.85)
            textColor = symbolColor
        } else {
            symbolColor = Self.symbolColor(for: note.tone)
            textColor = PreferencesGroupedForm.explanationColor(enabled: isEnabled)
        }
        let symbol = note.tone == .problem ? "exclamationmark.triangle.fill" : "lightbulb.fill"
        explanationLabel.attributedStringValue = Self.noteText(
            note.text, symbol: symbol, symbolColor: symbolColor, textColor: textColor, font: explanationLabel.font
        )
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        infoButton.appearance = accessory?.appearance
        iconView?.needsDisplay = true
    }

    /// The picture for the row's trigger, in white on the accent-coloured selection.
    private func applyPicture() {
        guard let iconView else { return }
        let wanted = (picture: picture, mouse: mouse, highlighted: isHighlighted)
        if let shownPicture, shownPicture == wanted { return }
        shownPicture = wanted
        iconView.image = ButtonsMouseMiniature.image(for: wanted.picture, mouse: wanted.mouse, highlighted: wanted.highlighted)
    }

    /// The note as text: the label holds the sign in front of it.
    override var explanation: String? {
        get { return note?.text ?? super.explanation }
        set { super.explanation = newValue }
    }

    /// The row names its note as plain text (the sign is decoration).
    override func accessibilityLabel() -> String? {
        guard let note else { return title }
        return "\(title), \(note.text)"
    }

    static func noteText(_ text: String, symbol: String, symbolColor: NSColor, textColor: NSColor, font: NSFont?) -> NSAttributedString {
        let font = font ?? PreferencesGroupedForm.explanationFont
        let result = NSMutableAttributedString()
        let configuration = NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [symbolColor]))
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) {
            let attachment = NSTextAttachment()
            attachment.image = image
            let size = image.size
            attachment.bounds = NSRect(x: 0, y: (font.capHeight - size.height) / 2, width: size.width, height: size.height)
            result.append(NSAttributedString(attachment: attachment))
            result.append(NSAttributedString(string: " ", attributes: [.foregroundColor: symbolColor]))
        }
        let start = result.length
        result.append(NSAttributedString(string: text))
        result.addAttribute(.font, value: font, range: NSRange(location: 0, length: result.length))
        if start > 0 {
            result.addAttribute(.foregroundColor, value: symbolColor, range: NSRange(location: 0, length: start))
        }
        result.addAttribute(.foregroundColor, value: textColor, range: NSRange(location: start, length: result.length - start))
        return result
    }
}

// MARK: - The ⓘ popover

/// What the ⓘ of a row opens: the problem in a few words, what to do, and for a Logitech
/// button that can be a standard one, "Use Standard Button".
final class ButtonProblemPopoverController: NSViewController {

    static let width: CGFloat = 300
    static let padding: CGFloat = 14

    let note: ButtonRowNote
    private(set) var titleLabel: NSTextField!
    private(set) var detailLabel: NSTextField!
    private(set) var standardButton: NSButton?
    var onUseStandardButton: (() -> Void)?

    init(note: ButtonRowNote) {
        self.note = note
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("ButtonProblemPopoverController is built in code")
    }

    override func loadView() {
        let title = NSTextField(wrappingLabelWithString: note.detailTitle)
        title.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        title.isSelectable = false
        let detail = NSTextField(wrappingLabelWithString: note.detailText)
        detail.font = PreferencesGroupedForm.explanationFont
        // The explanation is what the popover is for: in the label colour, not the muted
        // one of a line under a title (too faint to read at this size).
        detail.textColor = .labelColor
        detail.isSelectable = false
        let textWidth = Self.width - 2 * Self.padding
        title.preferredMaxLayoutWidth = textWidth
        detail.preferredMaxLayoutWidth = textWidth
        titleLabel = title
        detailLabel = detail

        var views: [NSView] = [title, detail]
        if note.offersStandardButton {
            let button = NSButton(
                title: NSLocalizedString("button_use_native_mouse", comment: ""),
                target: self,
                action: #selector(useStandardButton(_:))
            )
            button.bezelStyle = .push
            button.keyEquivalent = "\r"
            standardButton = button
            views.append(button)
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        if let standardButton {
            stack.setCustomSpacing(12, after: detail)
            stack.setCustomSpacing(0, after: standardButton)
        }
        stack.edgeInsets = NSEdgeInsets(top: Self.padding, left: Self.padding, bottom: Self.padding, right: Self.padding)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: Self.width).isActive = true
        view = stack
    }

    @objc private func useStandardButton(_ sender: NSButton) {
        onUseStandardButton?()
    }
}
