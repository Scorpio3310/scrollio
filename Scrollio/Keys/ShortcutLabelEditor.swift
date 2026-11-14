//
//  ShortcutLabelEditor.swift
//  Scrollio
//
//  The part of the recorder's popover where a recorded key combination gets its name and
//  its icon (`ShortcutLabel`): one row with the icon well and the name field, a line that
//  says where they show, and "Record Again" and "Done". It has one size whatever it holds.
//  The well shows the icon and opens the chooser (`ShortcutIconChooser.swift`) in a
//  popover of its own that points at it, as the small colour well of macOS opens its
//  picker. `KeyPopover` shows the editor under the keys once keys are there; while keys
//  are being recorded it is hidden, since the recording takes every key.
//
//  It only holds what is typed and chosen (`label`); whoever opened the popover stores it
//  when the popover closes.
//

import Cocoa

/// The icon well: a small square button that shows the icon (a symbol in the accent
/// colour, or the typed character), or a quiet plus when there is none. A click, or Space
/// while it has the keyboard, opens the chooser; Delete takes the icon away.
final class ShortcutIconWell: NSButton {

    static let side: CGFloat = 36

    /// Delete or Forward Delete while the well has the keyboard.
    var onDelete: (() -> Void)?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.side, height: Self.side))
        bezelStyle = .flexiblePush
        setButtonType(.momentaryPushIn)
        title = ""
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        if #available(macOS 26.0, *) {
            borderShape = .roundedRectangle
        }
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.side),
            heightAnchor.constraint(equalToConstant: Self.side),
        ])
        show(nil)
    }

    required init?(coder: NSCoder) {
        fatalError("ShortcutIconWell is built in code")
    }

    // The well takes the keyboard (Tab from the name stops at it, and focus comes back to
    // it from the chooser) also without "Keyboard navigation" on in System Settings: it is
    // the one way to the icon.
    override var acceptsFirstResponder: Bool {
        return true
    }

    override var canBecomeKeyView: Bool {
        return true
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 51, 117: // Delete, Forward Delete
            onDelete?()
        default:
            super.keyDown(with: event)
        }
    }

    /// A symbol drawn in `colour`. (The colour is in the picture: a bordered button of
    /// macOS 26 and later draws its image in the label colour whatever its tint.)
    private static func symbol(_ name: String, size: CGFloat, colour: NSColor) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [colour]))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
    }

    /// Shows `icon`, and says it to VoiceOver: "Icon: arrow clockwise", or "Choose Icon".
    func show(_ icon: ShortcutLabel.Icon?) {
        let text = { (key: String) in NSLocalizedString(key, comment: "") }
        let name: String
        switch icon {
        case .symbol(let symbol)?:
            image = Self.symbol(symbol, size: 18, colour: .controlAccentColor)
            contentTintColor = .controlAccentColor
            name = String(format: text("key-recorder-icon-well"), symbol.replacingOccurrences(of: ".", with: " "))
        case .character(let character)?:
            image = ShortcutIconSet.image(of: .character(character), side: 24)
            contentTintColor = nil
            name = String(format: text("key-recorder-icon-well"), character)
        case nil:
            image = Self.symbol("plus", size: 13, colour: .secondaryLabelColor)
            contentTintColor = .secondaryLabelColor
            name = text("key-recorder-icon-choose")
        }
        if image == nil, case .symbol? = icon {
            // A symbol this Mac does not have (a settings file may name one).
            image = Self.symbol("questionmark", size: 15, colour: .secondaryLabelColor)
        }
        toolTip = name
        setAccessibilityLabel(name)
    }
}

final class ShortcutLabelEditorView: NSView, NSTextFieldDelegate, NSPopoverDelegate {

    enum Identifier {
        static let name = NSUserInterfaceItemIdentifier("shortcut-label-name")
        static let icon = NSUserInterfaceItemIdentifier("shortcut-label-icon")
        static let note = NSUserInterfaceItemIdentifier("shortcut-label-note")
        static let recordAgain = NSUserInterfaceItemIdentifier("shortcut-label-record-again")
        static let done = NSUserInterfaceItemIdentifier("shortcut-label-done")
    }

    static let width: CGFloat = 280

    let nameField = NSTextField()
    /// Shows the icon and opens the chooser.
    let iconWell = ShortcutIconWell()
    let noteLabel = NSTextField(labelWithString: "")
    let recordAgainButton = NSButton(title: "", target: nil, action: nil)
    let doneButton = NSButton(title: "", target: nil, action: nil)

    /// The icon as chosen now.
    private(set) var icon: ShortcutLabel.Icon?
    /// The name as the field held it after the last edit it kept: an edit that would make it
    /// too long is measured against it.
    private var keptName = ""

    var onRecordAgain: (() -> Void)?
    var onDone: (() -> Void)?
    /// The chooser is about to open: the popover around the editor must not close for a
    /// click in it (`KeyPopover` makes itself semi-transient).
    var onChooserOpen: (() -> Void)?
    /// The chooser closed; `true`: by a click outside both popovers (or another app came
    /// forward), so the popover around the editor closes too.
    var onChooserClose: ((_ closesParent: Bool) -> Void)?
    /// Shows the chooser's popover at the well. Tests replace it: a popover needs a window.
    var presentChooser: (NSPopover, NSView) -> Void = { popover, well in
        guard well.window != nil else { return }
        // Under the well, whichever way its view counts y.
        popover.show(relativeTo: well.bounds, of: well, preferredEdge: well.isFlipped ? .maxY : .minY)
    }

    /// The chooser, while it is open.
    private(set) var chooser: ShortcutIconChooserController?
    private var chooserPopover: NSPopover?
    private var chooserClosesParent = false
    /// The moment of a mouse-down on the well that closed the chooser (it was outside the
    /// chooser): the click that follows from it must not open the chooser again.
    private var chooserClosedByWellAt: TimeInterval?

    /// What the name field and the icon hold, as it is stored; nil: neither.
    var label: ShortcutLabel? {
        return ShortcutLabel(name: nameField.stringValue, icon: icon)
    }

    /// The chooser is open.
    var isChoosingIcon: Bool {
        return chooser != nil
    }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 10))
        translatesAutoresizingMaskIntoConstraints = false
        build()
        show(nil)
    }

    required init?(coder: NSCoder) {
        fatalError("ShortcutLabelEditorView is built in code")
    }

    private static func text(_ key: String) -> String {
        return NSLocalizedString(key, comment: "")
    }

    /// The line under the name: where the name and the icon show. A place's of the
    /// Shortcut Ring in the ring and in Settings; a button's or a direction's in Settings.
    static func note(showsInRing: Bool) -> String {
        return text(showsInRing ? "key-recorder-label-note" : "key-recorder-label-note-settings")
    }

    // MARK: Filling

    /// Shows `label` (nil: an empty name, no icon), with the chooser closed.
    func show(_ label: ShortcutLabel?) {
        closeChooser()
        nameField.stringValue = label?.name ?? ""
        keptName = nameField.stringValue
        icon = label?.icon
        iconWell.show(icon)
    }

    /// `icon` (nil: none) is the icon now.
    func choose(_ newIcon: ShortcutLabel.Icon?) {
        icon = newIcon.flatMap(ShortcutLabel.cleaned)
        iconWell.show(icon)
    }

    /// The symbol `name` is the icon.
    func chooseSymbol(_ name: String) {
        choose(.symbol(name))
    }

    // MARK: The chooser

    /// Opens the chooser at the well, its search field with the keyboard.
    func openChooser() {
        guard chooser == nil else { return }
        let controller = ShortcutIconChooserController(icon: icon)
        controller.onChoose = { [weak self] chosen in
            guard let self else { return }
            self.choose(chosen)
            self.closeChooser()
        }
        controller.onCancel = { [weak self] in
            self?.closeChooser()
        }
        let popover = NSPopover()
        popover.contentViewController = controller
        controller.view.layoutSubtreeIfNeeded()
        popover.contentSize = controller.view.fittingSize
        popover.behavior = .transient
        popover.delegate = self
        chooser = controller
        chooserPopover = popover
        chooserClosesParent = false
        // (Before it shows: a transient popover that opens may close the other ones.)
        onChooserOpen?()
        presentChooser(popover, iconWell)
        controller.focusSearch()
    }

    /// Closes the chooser, if it is open; the keyboard goes back to the well, unless
    /// `refocus` is false: the card around the editor is going away, and its window must
    /// not be made the key one again.
    func closeChooser(refocus: Bool = true) {
        guard let popover = chooserPopover else { return }
        // (Told here, not by the system: a popover that was never on screen closes without
        // a word.)
        popover.delegate = nil
        popover.close()
        chooserClosed(closesParent: false, refocus: refocus)
    }

    private func chooserClosed(closesParent: Bool, refocus: Bool) {
        chooser = nil
        chooserPopover = nil
        onChooserClose?(closesParent)
        guard refocus, !closesParent, let window = iconWell.window else { return }
        window.makeFirstResponder(iconWell)
        if !window.isKeyWindow, window.canBecomeKey {
            window.makeKey()
        }
    }

    /// The system closed the chooser. It says so after the chooser's animation: a click
    /// in the card that closed it may have given the name field the keyboard by then, and
    /// the field keeps it (typed keys must not go to the well, where Delete takes the icon
    /// away). Otherwise the keyboard goes back to the well.
    private func chooserClosedByTheSystem(closesParent: Bool) {
        let elsewhere = (iconWell.window?.firstResponder as? NSView).map { $0 !== iconWell && $0.isDescendant(of: self) } ?? false
        chooserClosed(closesParent: closesParent, refocus: !elsewhere)
    }

    /// Whether the chooser, closed by the system, takes the popover around the editor with
    /// it: when the click that closed it was in neither popover (`mouseDownInWindow`: the
    /// window number of a mouse-down that closed it, nil for anything else), or when the
    /// app is no longer in front. Esc, a choice and a click in either popover keep it.
    static func closesParent(mouseDownInWindow: Int?, parentWindow: Int?, chooserWindow: Int?, appIsActive: Bool) -> Bool {
        guard appIsActive else { return true }
        guard let clicked = mouseDownInWindow else { return false }
        return clicked != parentWindow && clicked != chooserWindow
    }

#if DEBUG
    /// As if the system closed the chooser (a click, the app in the background), the
    /// rule's answer given.
    func testingCloseChooserAsTheSystemDoes(closesParent: Bool) {
        guard let popover = chooserPopover else { return }
        popover.delegate = nil
        popover.close()
        chooserClosedByTheSystem(closesParent: closesParent)
    }
#endif

    func popoverDidShow(_ notification: Notification) {
        guard notification.object as? NSPopover === chooserPopover else { return }
        chooser?.focusSearch()
    }

    func popoverWillClose(_ notification: Notification) {
        guard notification.object as? NSPopover === chooserPopover else { return }
        let event = NSApp.currentEvent
        let mouseDowns: [NSEvent.EventType] = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        let clicked = event.flatMap { mouseDowns.contains($0.type) ? $0.windowNumber : nil }
        if let event, clicked != nil, clicked == window?.windowNumber,
           iconWell.bounds.contains(iconWell.convert(event.locationInWindow, from: nil)) {
            chooserClosedByWellAt = event.timestamp
        }
        chooserClosesParent = Self.closesParent(
            mouseDownInWindow: clicked, parentWindow: window?.windowNumber,
            chooserWindow: chooser?.view.window?.windowNumber, appIsActive: NSApp.isActive
        )
    }

    func popoverDidClose(_ notification: Notification) {
        guard notification.object as? NSPopover === chooserPopover else { return }
        chooserClosedByTheSystem(closesParent: chooserClosesParent)
    }

    // MARK: Actions

    @objc private func wellClicked(_ sender: NSButton) {
        if let closedAt = chooserClosedByWellAt {
            chooserClosedByWellAt = nil
            // (The same click: the well closed the chooser, as a second click on a colour
            // well closes its picker.)
            if let now = NSApp.currentEvent?.timestamp, now - closedAt < 1 {
                return
            }
        }
        if isChoosingIcon {
            closeChooser()
        } else {
            openChooser()
        }
    }

    @objc private func recordAgain(_ sender: NSButton) {
        onRecordAgain?()
    }

    @objc private func done(_ sender: Any?) {
        onDone?()
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, field === nameField else { return }
        let editor = field.currentEditor() as? NSTextView
        // (A composition under way is measured once it is committed.)
        if editor?.hasMarkedText() == true { return }
        // Never longer than a name is stored, in characters and in what they are made of.
        // What was typed or pasted is what gives way, not the end of the name.
        let text = field.stringValue
        if ShortcutLabel.cut(text).unicodeScalars.count != text.unicodeScalars.count {
            let (kept, caret) = Self.fitted(text, after: keptName)
            field.stringValue = kept
            editor?.selectedRange = NSRange(location: caret, length: 0)
        }
        keptName = field.stringValue
    }

    /// `text`, an edit of `before` that makes the name too long, made to fit by keeping
    /// only as much of what the edit put in as there is room for (none: the name stays as
    /// it was); and where the caret goes, in UTF-16 units: after what was kept of it.
    static func fitted(_ text: String, after before: String) -> (text: String, caret: Int) {
        let new = Array(text), old = Array(before)
        var head = 0
        while head < min(new.count, old.count), new[head] == old[head] {
            head += 1
        }
        var tail = 0
        while tail < min(new.count, old.count) - head, new[new.count - 1 - tail] == old[old.count - 1 - tail] {
            tail += 1
        }
        let prefix = String(new[..<head]), suffix = String(new[(new.count - tail)...])
        // (What was put in, each character as long as a name keeps it.)
        let inserted = Array(ShortcutLabel.cut(String(new[head..<(new.count - tail)])))
        for count in stride(from: inserted.count, through: 0, by: -1) {
            let candidate = prefix + String(inserted[..<count]) + suffix
            if ShortcutLabel.cut(candidate) == candidate {
                return (candidate, (prefix + String(inserted[..<count])).utf16.count)
            }
        }
        let cut = ShortcutLabel.cut(text)
        return (cut, cut.utf16.count)
    }

    /// Return in the name field is "Done".
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === nameField, commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
        done(control)
        return true
    }

    // MARK: Building

    private func build() {
        let text = Self.text

        iconWell.target = self
        iconWell.action = #selector(wellClicked(_:))
        iconWell.identifier = Identifier.icon
        iconWell.onDelete = { [weak self] in
            self?.choose(nil)
        }

        nameField.placeholderString = text("key-recorder-name-placeholder")
        nameField.delegate = self
        nameField.identifier = Identifier.name
        nameField.lineBreakMode = .byTruncatingTail
        nameField.cell?.usesSingleLineMode = true
        nameField.setAccessibilityLabel(text("key-recorder-name"))
        nameField.translatesAutoresizingMaskIntoConstraints = false

        noteLabel.stringValue = Self.note(showsInRing: false)
        noteLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        noteLabel.textColor = .secondaryLabelColor
        noteLabel.identifier = Identifier.note
        // One line, always: the card never grows.
        noteLabel.maximumNumberOfLines = 1
        noteLabel.lineBreakMode = .byTruncatingTail
        noteLabel.translatesAutoresizingMaskIntoConstraints = false

        recordAgainButton.title = text("key-recorder-record-again")
        recordAgainButton.bezelStyle = .push
        recordAgainButton.target = self
        recordAgainButton.action = #selector(recordAgain(_:))
        recordAgainButton.identifier = Identifier.recordAgain
        recordAgainButton.translatesAutoresizingMaskIntoConstraints = false

        doneButton.title = text("key-recorder-done")
        doneButton.bezelStyle = .push
        doneButton.keyEquivalent = "\r"
        doneButton.target = self
        doneButton.action = #selector(done(_:))
        doneButton.identifier = Identifier.done
        doneButton.translatesAutoresizingMaskIntoConstraints = false

        for view in [iconWell, nameField, noteLabel, recordAgainButton, doneButton] as [NSView] {
            addSubview(view)
        }
        // Tab: the name, the well, then the buttons (with "Keyboard navigation" on).
        nameField.nextKeyView = iconWell
        iconWell.nextKeyView = recordAgainButton
        recordAgainButton.nextKeyView = doneButton
        doneButton.nextKeyView = nameField
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.width),
            // The well and the name, one row.
            iconWell.topAnchor.constraint(equalTo: topAnchor),
            iconWell.leadingAnchor.constraint(equalTo: leadingAnchor),
            nameField.leadingAnchor.constraint(equalTo: iconWell.trailingAnchor, constant: 8),
            nameField.trailingAnchor.constraint(equalTo: trailingAnchor),
            nameField.centerYAnchor.constraint(equalTo: iconWell.centerYAnchor),
            // The line under them.
            noteLabel.topAnchor.constraint(equalTo: iconWell.bottomAnchor, constant: 8),
            noteLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            noteLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            // "Record Again" on the left, "Done" on the right.
            recordAgainButton.topAnchor.constraint(equalTo: noteLabel.bottomAnchor, constant: 14),
            recordAgainButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            doneButton.centerYAnchor.constraint(equalTo: recordAgainButton.centerYAnchor),
            doneButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            doneButton.leadingAnchor.constraint(greaterThanOrEqualTo: recordAgainButton.trailingAnchor, constant: 8),
            recordAgainButton.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}
