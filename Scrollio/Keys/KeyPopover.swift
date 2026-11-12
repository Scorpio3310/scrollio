//
//  KeyPopover.swift
//  Mos
//  录制按键时显示的 Popover UI 组件
//  Created by Claude on 2025/9/13.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

/// The recorder's popover. From the moment it opens it says what to press (the waiting
/// hint), shows the key slot that fills in with what is held and then recorded, and under
/// it a small line: "Press Esc to cancel", replaced by why a press was refused, and gone
/// (its room kept) once a press is recorded: nothing is left to cancel then. It grows to fit
/// its texts, and VoiceOver hears the waiting hint when it opens.
class KeyPopover: NSObject {
    private enum RecordingHint {
        case escape
        case duplicate
        /// Refused for another reason, as the recorder's delegate says it.
        case refused(String)

        var localizedText: String {
            switch self {
            case .escape:
                return NSLocalizedString("Press ESC to cancel recording", comment: "ESC hint in key recording popover")
            case .duplicate:
                return NSLocalizedString("button-recording-duplicate-hint", comment: "Duplicate key hint in key recording popover")
            case .refused(let reason):
                return reason
            }
        }
    }

    // MARK: - Properties
    private var popover: NSPopover?
    var keyPreview: KeyPreview!
    private var waitingLabel: NSTextField?
    private var hintLabel: NSTextField?
    private var contentView: NSView?
    /// Says `text` to VoiceOver. Tests replace it.
    var announce: (String) -> Void = KeyPopover.postAnnouncement

    // MARK: - Constants
    /// The widest a text gets before it wraps.
    static let maxTextWidth: CGFloat = 260
    private static let minWidth: CGFloat = 165
    private static let insets = NSEdgeInsets(top: 12, left: 16, bottom: 10, right: 16)
    /// The small line under the keys: the small system font (11 pt), as every hint of the
    /// panes. At 10 pt in the secondary colour it was too faint to read.
    private static let hintFontSize: CGFloat = NSFont.smallSystemFontSize

    /// One spoken sentence from the popover's lines: line breaks become spaces, and a line
    /// without its own end mark ends with a full stop before the next.
    static func spokenText(_ lines: [String]) -> String {
        let sentences = lines
            .map { $0.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var text = ""
        for (index, sentence) in sentences.enumerated() {
            text += sentence
            if index < sentences.count - 1 {
                text += ".!?…".contains(sentence.last!) ? " " : ". "
            }
        }
        return text
    }

    // MARK: - Visibility
    /// 显示录制 popover, asking for `waitingHint`
    func show(at sourceView: NSView, waitingHint: String) {
        hide() // 确保之前的 popover 被关闭
        setupPopover(waitingHint: waitingHint)
        popover?.show(relativeTo: sourceView.bounds, of: sourceView, preferredEdge: .maxY)
        announce(Self.spokenText([waitingHint, RecordingHint.escape.localizedText]))
    }

    /// 隐藏 popover
    func hide() {
        popover?.close()
        popover = nil
    }

    // MARK: - Public Methods
    /// 显示 ESC 退出提示 (on from the start: this keeps it)
    func showEscHint() {
        showHint(.escape)
    }

    /// A refused event: `reason` (already localized), or "Duplicate key" when nil.
    func showRefusalHint(_ reason: String?) {
        showHint(reason.map { .refused($0) } ?? .duplicate)
    }

    /// The key slot shows a recorded press (green): the line under it goes, since
    /// "Press Esc to cancel" no longer holds. It keeps its room, so the popover does not
    /// jump in the moment it stays open. Any other status shows the line again.
    private func keyStatusDidChange(_ status: KeyPreview.Status) {
        guard let label = hintLabel else { return }
        let hidden = status == .recorded
        label.alphaValue = hidden ? 0 : 1
        label.setAccessibilityElement(!hidden)
    }

    /// The line under the key slot says `hint`; a new text grows the popover to fit and is
    /// said to VoiceOver.
    private func showHint(_ hint: RecordingHint) {
        guard let label = hintLabel else { return }
        let text = hint.localizedText
        guard label.stringValue != text else { return }
        label.stringValue = text
        updatePopoverContentSize()
        announce(text)
    }

#if DEBUG
    func testingPrepareContent(waitingHint: String = KeyRecordingMode.combination.waitingHint) {
        hide()
        setupPopover(waitingHint: waitingHint)
    }

    var testingContentView: NSView? {
        contentView
    }

    var testingWaitingText: String? {
        waitingLabel?.stringValue
    }

    var testingHintText: String? {
        hintLabel?.stringValue
    }

    var testingHintIsVisible: Bool {
        guard let label = hintLabel else { return false }
        return !label.isHiddenOrHasHiddenAncestor && label.alphaValue > 0 && label.fittingSize.height > 0
    }

    var testingHintFontPointSize: CGFloat? {
        hintLabel?.font?.pointSize
    }

    var testingHintAlignment: NSTextAlignment? {
        hintLabel?.alignment
    }

    var testingContentSize: NSSize? {
        popover?.contentSize
    }

    /// The waiting hint, the key slot and the line under it, laid out in the content: the
    /// rects the constraints place (a text field's frame is 2 pt wider on each side).
    var testingRowFrames: [NSRect] {
        guard let contentView else { return [] }
        contentView.layoutSubtreeIfNeeded()
        return ([waitingLabel, keyPreview, hintLabel] as [NSView?]).compactMap { row in
            row.map { $0.alignmentRect(forFrame: $0.frame) }
        }
    }
#endif

    // MARK: - Private Methods
    private func updatePopoverContentSize() {
        guard let contentView else { return }
        contentView.layoutSubtreeIfNeeded()
        let size = contentView.fittingSize
        contentView.setFrameSize(size)
        popover?.contentSize = size
    }

    private static func makeLabel(_ text: String, fontSize: CGFloat, color: NSColor) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.isSelectable = false
        label.font = NSFont.systemFont(ofSize: fontSize)
        label.textColor = color
        label.alignment = .center
        label.preferredMaxLayoutWidth = maxTextWidth
        label.translatesAutoresizingMaskIntoConstraints = false
        // As wide and tall as its text: the popover grows instead.
        label.setContentHuggingPriority(.required, for: .vertical)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }

    private func getContentView(waitingHint: String) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        contentView = view

        // What to press, from the start
        let waitingLabel = Self.makeLabel(waitingHint, fontSize: NSFont.systemFontSize, color: .labelColor)
        self.waitingLabel = waitingLabel
        // 创建按键显示组件
        keyPreview = KeyPreview()
        keyPreview.onStatusChange = { [weak self] status in
            self?.keyStatusDidChange(status)
        }
        // 录制提示: "Press Esc to cancel" from the start, then why a press was refused
        let hintLabel = Self.makeLabel(RecordingHint.escape.localizedText, fontSize: Self.hintFontSize, color: .secondaryLabelColor)
        self.hintLabel = hintLabel

        // A column, each centred and kept off the sides; the popover is as wide as the
        // widest (at least `minWidth`) and as tall as all three.
        let insets = Self.insets
        var constraints: [NSLayoutConstraint] = [
            waitingLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: insets.top),
            keyPreview.topAnchor.constraint(equalTo: waitingLabel.bottomAnchor, constant: 8),
            hintLabel.topAnchor.constraint(equalTo: keyPreview.bottomAnchor, constant: 6),
            hintLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -insets.bottom),
            // 内容视图宽度约束
            view.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.minWidth),
        ]
        for row in [waitingLabel, keyPreview!, hintLabel] as [NSView] {
            view.addSubview(row)
            // The margins size the popover (fitting honours them); not required, so a key
            // slot that grows while the popover is open does not break the layout.
            let leading = row.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: insets.left)
            let trailing = row.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -insets.right)
            leading.priority = .defaultHigh
            trailing.priority = .defaultHigh
            constraints += [row.centerXAnchor.constraint(equalTo: view.centerXAnchor), leading, trailing]
        }
        NSLayoutConstraint.activate(constraints)

        // VoiceOver: the popover is a group named by what it asks for.
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
        view.setAccessibilityLabel(Self.spokenText([waitingHint]))

        view.setFrameSize(view.fittingSize)
        return view
    }

    private func setupPopover(waitingHint: String) {
        let newPopover = NSPopover()
        newPopover.contentViewController = NSViewController()
        let view = getContentView(waitingHint: waitingHint)
        newPopover.contentViewController?.view = view
        newPopover.contentSize = view.frame.size
        newPopover.behavior = .transient
        popover = newPopover
    }

    /// A high-priority VoiceOver announcement (nothing happens without VoiceOver).
    private static func postAnnouncement(_ text: String) {
        guard let app = NSApp else { return }
        NSAccessibility.post(element: app, notification: .announcementRequested, userInfo: [
            .announcement: text,
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }
}
