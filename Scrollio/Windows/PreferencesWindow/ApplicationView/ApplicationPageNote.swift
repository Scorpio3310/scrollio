//
//  ApplicationPageNote.swift
//  Scrollio
//
//  A muted line under a box of an app's page, with a small push button beside it when it
//  leads somewhere, as "Haptic feedback is off under Mouse." + "Show in Mouse" in the Gestures
//  pane: "Scrollio has suggested shortcuts for Figma." + "Use Suggested Shortcuts". While
//  it has nothing to say it takes no room at all, so the box's neighbours stand where they
//  stood without it.
//

import Cocoa

final class ApplicationPageNote: NSView {

    let label: NSTextField
    let button: NSButton
    private let boxWidth: CGFloat
    /// The line in its place, the note as tall as it is; and the button's, while there is one.
    private var shownConstraints: [NSLayoutConstraint] = []
    private var buttonConstraints: [NSLayoutConstraint] = []
    /// No room at all.
    private var collapsed: NSLayoutConstraint!
    /// The line's end: before the button, or at the box's inset without one.
    private var endsAtInset: NSLayoutConstraint!

    /// - Parameters:
    ///   - boxWidth: the width of the box above, which the note's texts are inset like.
    ///   - target, action: the button's.
    init(boxWidth: CGFloat, target: AnyObject?, action: Selector?) {
        self.boxWidth = boxWidth
        let label = NSTextField(wrappingLabelWithString: "")
        label.font = PreferencesGroupedForm.explanationFont
        label.textColor = PreferencesGroupedForm.explanationColor(enabled: true)
        label.isSelectable = false
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        self.label = label
        let button = PreferencesGroupedForm.makePushButton(title: "", target: target, action: action)
        button.controlSize = .small
        button.font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small))
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        self.button = button
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        addSubview(button)
        let inset = PreferencesGroupedForm.rowHorizontalInset
        let spacing = PreferencesGroupedForm.controlSpacing
        endsAtInset = label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -inset)
        // Both on one middle line, the note as tall as the taller of the two.
        let middle = label.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        middle.priority = .defaultHigh
        let hug = heightAnchor.constraint(equalToConstant: 0)
        hug.priority = .fittingSizeCompression
        shownConstraints = [
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            label.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: PreferencesGroupedForm.noteSpacing),
            label.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
            hug,
        ]
        buttonConstraints = [
            label.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -spacing),
            button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            button.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: PreferencesGroupedForm.noteSpacing),
            button.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
            middle,
        ]
        collapsed = heightAnchor.constraint(equalToConstant: 0)
        show(nil)
    }

    required init?(coder: NSCoder) {
        fatalError("ApplicationPageNote is built in code")
    }

    /// What the line says; nil while the note says nothing (it takes no room then).
    private(set) var text: String?

    /// The note says `text`, with a button titled `buttonTitle` beside it (nil: none);
    /// with no text it takes no room. True when it came, went or changed.
    @discardableResult
    func show(_ text: String?, buttonTitle: String? = nil) -> Bool {
        let changed = text != self.text || (text != nil && (buttonTitle ?? "") != (button.isHidden ? "" : button.title))
        self.text = text
        guard let text else {
            label.isHidden = true
            button.isHidden = true
            NSLayoutConstraint.deactivate(shownConstraints + buttonConstraints + [endsAtInset])
            collapsed.isActive = true
            return changed
        }
        label.stringValue = text
        label.isHidden = false
        button.title = buttonTitle ?? ""
        button.isHidden = buttonTitle == nil
        // The button says where it goes; the line next to it says why.
        button.setAccessibilityHelp(buttonTitle == nil ? nil : text)
        let inset = PreferencesGroupedForm.rowHorizontalInset
        let room = buttonTitle == nil ? 0 : button.fittingSize.width + PreferencesGroupedForm.controlSpacing
        label.preferredMaxLayoutWidth = max(0, boxWidth - 2 * inset - room)
        collapsed.isActive = false
        endsAtInset.isActive = buttonTitle == nil
        NSLayoutConstraint.activate(shownConstraints)
        if buttonTitle == nil {
            NSLayoutConstraint.deactivate(buttonConstraints)
        } else {
            NSLayoutConstraint.activate(buttonConstraints)
        }
        return changed
    }
}
