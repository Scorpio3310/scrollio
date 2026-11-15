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
///
/// For the "Keyboard Shortcut…" action it has a second state, the details: once a key
/// combination is recorded (or when the row already holds one) the key slot shows the
/// keys and under it stands `ShortcutLabelEditorView`, where the combination gets a name
/// and an icon, with "Record Again" and "Done". The waiting hint and the Esc line are gone
/// then: nothing is being recorded, and the keyboard types into the name. Whoever uses
/// the popover hears when it closes (`onClose`) and reads `editedLabel`.
///
/// The icon is chosen in a second popover that points at the editor's icon well. A
/// transient popover shown from inside another may close it, and a click in the second
/// is outside the first: while the chooser is open this popover is semi-transient (a
/// click in the settings window still closes it, a click in the chooser does not), and
/// it closes with the chooser when that one closed for a click outside both, or when
/// another app comes forward. Afterwards it is transient again.
class KeyPopover: NSObject, NSPopoverDelegate {
    private enum RecordingHint {
        case escape
        case duplicate
        /// Refused for another reason, as the recorder's delegate says it.
        case refused(String)
        /// Recorded, and what taking it changes, as the recorder's delegate says it.
        case note(String)

        var localizedText: String {
            switch self {
            case .escape:
                return NSLocalizedString("Press ESC to cancel recording", comment: "ESC hint in key recording popover")
            case .duplicate:
                return NSLocalizedString("button-recording-duplicate-hint", comment: "Duplicate key hint in key recording popover")
            case .refused(let reason), .note(let reason):
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

    // MARK: - The details (a name and an icon for the recorded keys)
    /// Where the name and the icon are set; hidden while keys are recorded.
    private(set) var labelEditor: ShortcutLabelEditorView?
    /// The popover shows the details, not a recording.
    private(set) var isShowingDetails = false
    private var recordingConstraints: [NSLayoutConstraint] = []
    private var detailsConstraints: [NSLayoutConstraint] = []
    /// What the popover's behaviour was before the chooser opened; nil: it is not open.
    private var behaviorBeforeChooser: NSPopover.Behavior?
    private var appResignObserver: NSObjectProtocol?
    /// The keys are a place's of the Shortcut Ring: the line under the name says it shows
    /// in the ring too. A button's or a direction's name shows only in Settings.
    var labelShowsInRing = false
    /// "Record Again" was pressed.
    var onRecordAgain: (() -> Void)?
    /// The popover closed, in whatever way ("Done", a click elsewhere, Esc, `hide`). Told
    /// once, then forgotten: set it again for a popover that is used again.
    var onClose: (() -> Void)?

    /// The name and icon as the details hold them now; nil: neither, or no details.
    var editedLabel: ShortcutLabel? {
        return labelEditor?.label
    }

    /// The popover is on screen. (A stand-in of the tests says so without a window.)
    var isOpen: Bool {
        return popover?.isShown ?? false
    }

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
    /// 显示录制 popover, asking for `waitingHint`. A popover that is open with the
    /// details ("Record Again") goes back to asking for keys where it is, without closing.
    func show(at sourceView: NSView, waitingHint: String) {
        if isOpen, contentView != nil {
            turnToRecording(waitingHint: waitingHint)
        } else {
            hide() // 确保之前的 popover 被关闭
            setupPopover(waitingHint: waitingHint)
            popover?.show(relativeTo: sourceView.bounds, of: sourceView, preferredEdge: .maxY)
        }
        announce(Self.spokenText([waitingHint, RecordingHint.escape.localizedText]))
    }

    /// Opens the popover with keys that are already recorded: their name and icon can be
    /// changed, and "Record Again" asks for other keys.
    func showDetails(at sourceView: NSView, keys: [String], label: ShortcutLabel?) {
        hide()
        setupPopover(waitingHint: "")
        keyPreview.update(from: keys, status: .normal)
        turnToDetails(label: label)
        popover?.show(relativeTo: sourceView.bounds, of: sourceView, preferredEdge: .maxY)
        focusNameField()
    }

    /// 隐藏 popover
    func hide() {
        // (The card is going away: its window is not made the key one again.)
        labelEditor?.closeChooser(refocus: false)
        guard let closing = popover else { return }
        popover = nil
        // (Told here, not by the system: a popover that was never on screen closes
        // without a word.)
        closing.delegate = nil
        closing.close()
        tellClosed()
    }

    /// The user closed the popover: a click elsewhere, Esc, the window going away.
    func popoverDidClose(_ notification: Notification) {
        guard let closed = notification.object as? NSPopover, closed === popover else { return }
        popover = nil
        labelEditor?.closeChooser(refocus: false)
        tellClosed()
    }

    // MARK: - The chooser of icons, a popover in this one

    private func chooserWillOpen() {
        guard let popover, behaviorBeforeChooser == nil else { return }
        behaviorBeforeChooser = popover.behavior
        popover.behavior = .semitransient
        appResignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.hide()
        }
    }

    private func chooserDidClose(closesParent: Bool) {
        if let observer = appResignObserver {
            NotificationCenter.default.removeObserver(observer)
            appResignObserver = nil
        }
        if let behavior = behaviorBeforeChooser {
            popover?.behavior = behavior
            behaviorBeforeChooser = nil
        }
        if closesParent {
            hide()
        }
    }

    private func tellClosed() {
        let handler = onClose
        onClose = nil
        handler?()
    }

    // MARK: - The two states

    /// The keys are recorded and stand in the key slot: the popover goes on to their name
    /// and icon, showing `label` (nil: none yet).
    func turnToDetails(label: ShortcutLabel?) {
        guard let editor = labelEditor else { return }
        isShowingDetails = true
        waitingLabel?.isHidden = true
        hintLabel?.isHidden = true
        let note = ShortcutLabelEditorView.note(showsInRing: labelShowsInRing)
        editor.noteLabel.stringValue = note
        editor.show(label)
        editor.isHidden = false
        NSLayoutConstraint.deactivate(recordingConstraints)
        NSLayoutConstraint.activate(detailsConstraints)
        contentView?.setAccessibilityLabel(NSLocalizedString("custom-shortcut", comment: ""))
        updatePopoverContentSize()
        focusNameField()
        announce(Self.spokenText([NSLocalizedString("key-recorder-name", comment: ""), note]))
    }

    /// Back to asking for keys, in the popover as it is open.
    private func turnToRecording(waitingHint: String) {
        isShowingDetails = false
        labelEditor?.closeChooser()
        labelEditor?.isHidden = true
        waitingLabel?.stringValue = waitingHint
        waitingLabel?.isHidden = false
        hintLabel?.stringValue = RecordingHint.escape.localizedText
        hintLabel?.isHidden = false
        keyPreview.update(from: [KeyPreview.WAITING_WORDING], status: .recording)
        NSLayoutConstraint.deactivate(detailsConstraints)
        NSLayoutConstraint.activate(recordingConstraints)
        contentView?.setAccessibilityLabel(Self.spokenText([waitingHint]))
        // (The keyboard is the recording's now: nothing of the popover holds it.)
        contentView?.window?.makeFirstResponder(nil)
        updatePopoverContentSize()
    }

    /// The name field takes the keyboard, once the popover has its window. (While keys
    /// were recorded nothing in the popover could take it, so its window may not be the
    /// key window yet.)
    private func focusNameField() {
        guard let editor = labelEditor, let window = editor.window else { return }
        window.makeFirstResponder(editor.nameField)
        if !window.isKeyWindow, window.canBecomeKey {
            window.makeKey()
        }
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

    /// A recorded press: `note` (already localized, "Replaces: Copy") on the line under the
    /// keys, which a recorded press otherwise leaves empty; said to VoiceOver.
    func showRecordedNote(_ note: String) {
        guard let label = hintLabel else { return }
        label.alphaValue = 1
        label.setAccessibilityElement(true)
        showHint(.note(note))
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

    /// The system popover's behaviour; nil: there is none (it closed).
    var testingBehavior: NSPopover.Behavior? {
        popover?.behavior
    }

    /// The details without a window: the keys, their name and icon.
    func testingPrepareDetails(keys: [String], label: ShortcutLabel?) {
        hide()
        setupPopover(waitingHint: "")
        keyPreview.update(from: keys, status: .normal)
        turnToDetails(label: label)
    }

    /// As if the user closed the popover (a click elsewhere): what the system tells it.
    func testingCloseAsTheUserDoes() {
        guard let popover else { return }
        popoverDidClose(Notification(name: NSPopover.didCloseNotification, object: popover))
    }

    var testingWaitingIsVisible: Bool {
        guard let label = waitingLabel else { return false }
        return !label.isHidden
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

        // The name and icon of the recorded keys, for the state after the recording.
        let editor = ShortcutLabelEditorView()
        editor.isHidden = true
        editor.onRecordAgain = { [weak self] in
            self?.onRecordAgain?()
        }
        editor.onDone = { [weak self] in
            self?.hide()
        }
        editor.onChooserOpen = { [weak self] in
            self?.chooserWillOpen()
        }
        editor.onChooserClose = { [weak self] closesParent in
            self?.chooserDidClose(closesParent: closesParent)
        }
        labelEditor = editor
        isShowingDetails = false

        // A column, each centred and kept off the sides; the popover is as wide as the
        // widest (at least `minWidth`) and as tall as all three.
        let insets = Self.insets
        recordingConstraints = [
            waitingLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: insets.top),
            keyPreview.topAnchor.constraint(equalTo: waitingLabel.bottomAnchor, constant: 8),
            hintLabel.topAnchor.constraint(equalTo: keyPreview.bottomAnchor, constant: 6),
            hintLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -insets.bottom),
        ]
        // The details: the keys on top, the editor under them.
        detailsConstraints = [
            keyPreview.topAnchor.constraint(equalTo: view.topAnchor, constant: insets.top + 2),
            editor.topAnchor.constraint(equalTo: keyPreview.bottomAnchor, constant: 14),
            editor.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -insets.top),
            editor.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: insets.left),
            editor.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -insets.right),
            // (The two lines of a recording are hidden then; they still need a place.)
            waitingLabel.topAnchor.constraint(equalTo: view.topAnchor),
            hintLabel.topAnchor.constraint(equalTo: view.topAnchor),
        ]
        view.addSubview(editor)
        var constraints: [NSLayoutConstraint] = recordingConstraints + [
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
        newPopover.delegate = self
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
