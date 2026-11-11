//
//  ButtonBindingRow.swift
//  Mos
//  One button of the Buttons pane: a row of the kit's list with the button's name, a line
//  under it only when there is something to say (what the action needs, or a problem in
//  orange), an ⓘ that explains a problem, and the action pull-down.
//

import Cocoa

// MARK: - The line under the title

/// What the line under a button's title says, if anything. Pure: the pane and its tests
/// share the rules.
struct ButtonRowNote: Equatable {

    enum Kind: Equatable {
        /// Gesture Navigation: the directions are under Gestures.
        case gestureNavigation
        /// A scroll action works while the button is held.
        case holdAction
        /// No action yet.
        case noAction
        /// The button is also a key under Scrolling › While you hold a key.
        case alsoScrollKey
        /// What the Logitech mouse says about the button.
        case capture(ButtonCapturePresentationStatus)
    }

    enum Tone: Equatable {
        /// Secondary text, like any explanation.
        case plain
        /// Orange, after a warning sign.
        case problem
        /// Blue: a better way exists.
        case hint
    }

    let kind: Kind
    let text: String

    var tone: Tone {
        switch kind {
        case .gestureNavigation, .holdAction, .noAction:
            return .plain
        case .alsoScrollKey:
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
        case .capture(let status): return Self.text(status.titleKey)
        case .gestureNavigation, .holdAction, .noAction: return text
        }
    }

    var detailText: String {
        switch kind {
        case .alsoScrollKey: return Self.text("buttons-scroll-key-detail")
        case .capture(let status): return Self.text(status.detailKey)
        case .gestureNavigation, .holdAction, .noAction: return ""
        }
    }

    /// The line for `binding`: a problem first, then what the action needs, else nothing.
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
        switch CellActionState(binding: binding) {
        case .unbound, .recordingPrompt:
            return ButtonRowNote(kind: .noAction, text: text("buttons-note-no-action"))
        case .namedShortcut(let shortcut):
            if shortcut.identifier == SystemShortcut.mouseGestureNavigation.identifier {
                return ButtonRowNote(kind: .gestureNavigation, text: text("buttons-note-gesture-navigation"))
            }
            if SystemShortcut.mosMouseScrollCategory.shortcuts.contains(where: { $0.identifier == shortcut.identifier }) {
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

    private(set) var binding: ButtonBinding
    private(set) var note: ButtonRowNote?
    let pullDown: ButtonActionPullDown
    /// The ⓘ before the pull-down; it shows while the note is a problem or a hint.
    let infoButton: NSButton

    init(binding: ButtonBinding, title: String, note: ButtonRowNote?, pullDown: ButtonActionPullDown) {
        self.binding = binding
        self.note = note
        self.pullDown = pullDown

        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        let image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) ?? NSImage()
        let info = NSButton(image: image, target: nil, action: nil)
        info.isBordered = false
        info.imagePosition = .imageOnly
        info.contentTintColor = .secondaryLabelColor
        info.setAccessibilityLabel(NSLocalizedString("buttons-problem-info", comment: ""))
        infoButton = info

        let accessory = NSStackView(views: [info, pullDown])
        accessory.orientation = .horizontal
        accessory.alignment = .centerY
        accessory.spacing = 8
        accessory.detachesHiddenViews = true

        super.init(
            id: binding.id,
            title: title,
            explanation: note?.text,
            accessory: accessory,
            centeredOn: pullDown,
            controls: [pullDown]
        )
        applyNote()
    }

    required init?(coder: NSCoder) {
        fatalError("ButtonBindingRow is built in code")
    }

    /// Shows `binding` with `title` and `note`; the row and its pull-down stay the same views.
    func update(binding: ButtonBinding, title: String, note: ButtonRowNote?) {
        self.binding = binding
        self.note = note
        if self.title != title {
            self.title = title
        }
        explanation = note?.text
        pullDown.configure(with: binding)
        applyNote()
    }

    private func applyNote() {
        let details = note?.hasDetails ?? false
        infoButton.isHidden = !details
        infoButton.toolTip = details ? note?.detailTitle : nil
        infoButton.setAccessibilityHelp(details ? note?.detailTitle : nil)
        applyEnabled()
    }

    /// The note's colour, and its sign before the text; white on the selection.
    override func applyEnabled() {
        super.applyEnabled()
        guard let note, note.tone != .plain else { return }
        let color: NSColor
        if isHighlighted {
            color = NSColor.alternateSelectedControlTextColor.withAlphaComponent(0.85)
        } else {
            color = note.tone == .problem ? .systemOrange : .systemBlue
        }
        let symbol = note.tone == .problem ? "exclamationmark.triangle.fill" : "lightbulb.fill"
        explanationLabel.attributedStringValue = Self.noteText(note.text, symbol: symbol, color: color, font: explanationLabel.font)
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

    static func noteText(_ text: String, symbol: String, color: NSColor, font: NSFont?) -> NSAttributedString {
        let font = font ?? PreferencesGroupedForm.explanationFont
        let result = NSMutableAttributedString()
        let configuration = NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) {
            let attachment = NSTextAttachment()
            attachment.image = image
            let size = image.size
            attachment.bounds = NSRect(x: 0, y: (font.capHeight - size.height) / 2, width: size.width, height: size.height)
            result.append(NSAttributedString(attachment: attachment))
            result.append(NSAttributedString(string: " "))
        }
        result.append(NSAttributedString(string: text))
        result.addAttributes([.font: font, .foregroundColor: color], range: NSRange(location: 0, length: result.length))
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
        detail.textColor = .secondaryLabelColor
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
