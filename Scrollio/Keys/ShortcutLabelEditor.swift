//
//  ShortcutLabelEditor.swift
//  Scrollio
//
//  The part of the recorder's popover where a recorded key combination gets its name and
//  its icon (`ShortcutLabel`): a field for the name, a button that shows the icon and
//  opens the choice (a search field over a grid of symbols in groups, `ShortcutIconSet`,
//  a small field for one typed character, "No Icon"), a line that says where they show,
//  and "Record Again" and "Done". `KeyPopover` shows it under the keys once keys are
//  there; while keys are being recorded it is hidden, since the recording takes every key.
//
//  It only holds what is typed and chosen (`label`); whoever opened the popover stores it
//  when the popover closes.
//

import Cocoa

/// One symbol of the choice.
final class ShortcutIconCellButton: NSButton {

    static let side: CGFloat = 30

    let symbolName: String
    /// The symbol is the icon now: an accent-coloured ground behind it.
    var isChosen = false {
        didSet {
            guard isChosen != oldValue else { return }
            needsDisplay = true
            setAccessibilityValue(isChosen ? NSNumber(value: true) : NSNumber(value: false))
        }
    }

    init(symbol: ShortcutIconSet.Symbol, target: AnyObject?, action: Selector) {
        symbolName = symbol.name
        super.init(frame: NSRect(x: 0, y: 0, width: Self.side, height: Self.side))
        isBordered = false
        setButtonType(.momentaryChange)
        image = NSImage(systemSymbolName: symbol.name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .regular))
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        contentTintColor = .labelColor
        toolTip = symbol.spokenName
        setAccessibilityLabel(symbol.spokenName)
        identifier = NSUserInterfaceItemIdentifier("shortcut-icon-" + symbol.name)
        self.target = target
        self.action = action
    }

    required init?(coder: NSCoder) {
        fatalError("ShortcutIconCellButton is built in code")
    }

    override func draw(_ dirtyRect: NSRect) {
        if isChosen {
            NSColor.controlAccentColor.withAlphaComponent(0.3).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6).fill()
        }
        super.draw(dirtyRect)
    }
}

/// The symbols of the choice, group under group, eight to a row.
final class ShortcutIconGridView: NSView {

    static let columns = 8
    static let gap: CGFloat = 2
    static let headerHeight: CGFloat = 22
    static var contentWidth: CGFloat {
        return CGFloat(columns) * ShortcutIconCellButton.side + CGFloat(columns - 1) * gap
    }

    private(set) var buttons: [ShortcutIconCellButton] = []
    private(set) var headers: [NSTextField] = []
    /// The symbol that is the icon now; nil: none of them.
    var chosen: String? {
        didSet {
            buttons.forEach { $0.isChosen = $0.symbolName == chosen }
        }
    }
    var onChoose: ((String) -> Void)?

    override var isFlipped: Bool {
        return true
    }

    /// Lays out `groups`, each under its name.
    func show(_ groups: [ShortcutIconSet.Group]) {
        subviews.forEach { $0.removeFromSuperview() }
        buttons = []
        headers = []
        let side = ShortcutIconCellButton.side
        var y: CGFloat = 0
        for group in groups {
            let header = NSTextField(labelWithString: group.title)
            header.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
            header.textColor = .secondaryLabelColor
            header.frame = NSRect(x: 2, y: y + 4, width: Self.contentWidth - 4, height: 15)
            addSubview(header)
            headers.append(header)
            y += Self.headerHeight
            for (index, symbol) in group.symbols.enumerated() {
                let button = ShortcutIconCellButton(symbol: symbol, target: self, action: #selector(chose(_:)))
                button.frame = NSRect(
                    x: CGFloat(index % Self.columns) * (side + Self.gap),
                    y: y + CGFloat(index / Self.columns) * (side + Self.gap), width: side, height: side
                )
                button.isChosen = symbol.name == chosen
                addSubview(button)
                buttons.append(button)
            }
            let rows = (group.symbols.count + Self.columns - 1) / Self.columns
            y += CGFloat(rows) * (side + Self.gap) + 4
        }
        setFrameSize(NSSize(width: Self.contentWidth, height: max(y, 1)))
    }

    @objc private func chose(_ sender: ShortcutIconCellButton) {
        onChoose?(sender.symbolName)
    }
}

final class ShortcutLabelEditorView: NSView, NSTextFieldDelegate, NSSearchFieldDelegate {

    enum Identifier {
        static let name = NSUserInterfaceItemIdentifier("shortcut-label-name")
        static let icon = NSUserInterfaceItemIdentifier("shortcut-label-icon")
        static let search = NSUserInterfaceItemIdentifier("shortcut-label-icon-search")
        static let character = NSUserInterfaceItemIdentifier("shortcut-label-icon-character")
        static let removeIcon = NSUserInterfaceItemIdentifier("shortcut-label-icon-remove")
        static let noMatch = NSUserInterfaceItemIdentifier("shortcut-label-icon-no-match")
        static let note = NSUserInterfaceItemIdentifier("shortcut-label-note")
        static let recordAgain = NSUserInterfaceItemIdentifier("shortcut-label-record-again")
        static let done = NSUserInterfaceItemIdentifier("shortcut-label-done")
    }

    static let width: CGFloat = 272
    /// The room of the symbols: five rows and a group's name show, the rest scrolls.
    static let gridHeight: CGFloat = 164
    private static let captionWidth: CGFloat = 40

    let nameField = NSTextField()
    /// Shows the icon (or "None") and opens and closes the choice.
    let iconButton = NSButton(title: "", target: nil, action: nil)
    let searchField = NSSearchField()
    let grid = ShortcutIconGridView()
    let gridScroll = NSScrollView()
    let noMatchLabel = NSTextField(wrappingLabelWithString: "")
    let characterField = NSTextField()
    let removeIconButton = NSButton(title: "", target: nil, action: nil)
    let noteLabel = NSTextField(wrappingLabelWithString: "")
    let recordAgainButton = NSButton(title: "", target: nil, action: nil)
    let doneButton = NSButton(title: "", target: nil, action: nil)
    private let chooser = NSStackView()

    /// The icon as chosen now.
    private(set) var icon: ShortcutLabel.Icon?

    var onRecordAgain: (() -> Void)?
    var onDone: (() -> Void)?
    /// The choice of icons opened or closed: the editor is taller or shorter.
    var onLayoutChange: (() -> Void)?

    /// What the name field and the icon hold, as it is stored; nil: neither.
    var label: ShortcutLabel? {
        return ShortcutLabel(name: nameField.stringValue, icon: icon)
    }

    /// The choice of icons is open.
    var isChoosingIcon: Bool {
        return !chooser.isHidden
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

    // MARK: Filling

    /// Shows `label` (nil: an empty name, no icon), with the choice of icons closed.
    func show(_ label: ShortcutLabel?) {
        nameField.stringValue = label?.name ?? ""
        icon = label?.icon
        searchField.stringValue = ""
        showSymbols(matching: "")
        chooser.isHidden = true
        syncIcon()
    }

    /// Opens or closes the choice of icons.
    func setChoosingIcon(_ choosing: Bool) {
        guard choosing != isChoosingIcon else { return }
        chooser.isHidden = !choosing
        onLayoutChange?()
        if choosing {
            window?.makeFirstResponder(searchField)
        }
    }

    /// The symbol `name` is the icon.
    func chooseSymbol(_ name: String) {
        icon = ShortcutLabel.cleaned(.symbol(name))
        syncIcon()
        setChoosingIcon(false)
    }

    private func syncIcon() {
        let picture = icon.flatMap { ShortcutIconSet.image(of: $0, side: 16) }
        iconButton.image = picture
        iconButton.imagePosition = picture == nil ? .noImage : .imageOnly
        iconButton.title = picture == nil ? Self.text("key-recorder-icon-none") : ""
        removeIconButton.isEnabled = icon != nil
        switch icon {
        case .symbol(let name)?:
            grid.chosen = name
            characterField.stringValue = ""
            iconButton.setAccessibilityValue(name.replacingOccurrences(of: ".", with: " "))
        case .character(let character)?:
            grid.chosen = nil
            characterField.stringValue = character
            iconButton.setAccessibilityValue(character)
        case nil:
            grid.chosen = nil
            characterField.stringValue = ""
            iconButton.setAccessibilityValue(Self.text("key-recorder-icon-none"))
        }
    }

    private func showSymbols(matching query: String) {
        let found = ShortcutIconSet.groups(matching: query)
        grid.show(found)
        gridScroll.isHidden = found.isEmpty
        noMatchLabel.isHidden = !found.isEmpty
        gridScroll.contentView.scroll(to: .zero)
        gridScroll.reflectScrolledClipView(gridScroll.contentView)
    }

    // MARK: Actions

    @objc private func iconButtonClicked(_ sender: NSButton) {
        setChoosingIcon(!isChoosingIcon)
    }

    @objc private func removeIcon(_ sender: NSButton) {
        icon = nil
        syncIcon()
        setChoosingIcon(false)
    }

    @objc private func recordAgain(_ sender: NSButton) {
        onRecordAgain?()
    }

    @objc private func done(_ sender: Any?) {
        onDone?()
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        if field === nameField {
            // Never longer than a name is stored.
            if field.stringValue.count > ShortcutLabel.maximumNameLength {
                field.stringValue = String(field.stringValue.prefix(ShortcutLabel.maximumNameLength))
            }
        } else if field === searchField {
            showSymbols(matching: field.stringValue)
        } else if field === characterField {
            // One character: the first that can be seen of what was typed or pasted. An
            // emptied field takes a typed icon away, and leaves a chosen symbol.
            if let typed = ShortcutLabel.cleaned(.character(field.stringValue)) {
                icon = typed
            } else if case .character? = icon {
                icon = nil
            }
            syncIcon()
        }
    }

    /// Return in the name field is "Done".
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === nameField || control === characterField,
              commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
        done(control)
        return true
    }

    // MARK: Building

    private func caption(_ key: String) -> NSTextField {
        let label = NSTextField(labelWithString: Self.text(key))
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: Self.captionWidth).isActive = true
        return label
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    /// Takes the room that is left in a row.
    private func spacer() -> NSView {
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: 1).isActive = true
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        return spacer
    }

    private func build() {
        let text = Self.text

        nameField.placeholderString = text("key-recorder-name-placeholder")
        nameField.delegate = self
        nameField.identifier = Identifier.name
        nameField.lineBreakMode = .byTruncatingTail
        nameField.cell?.usesSingleLineMode = true
        nameField.setAccessibilityLabel(text("key-recorder-name"))
        nameField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        iconButton.bezelStyle = .rounded
        // (A plain push button: lit like "Done" while the symbols are open, it read as
        // the thing to press next.)
        iconButton.setButtonType(.momentaryPushIn)
        iconButton.target = self
        iconButton.action = #selector(iconButtonClicked(_:))
        iconButton.identifier = Identifier.icon
        iconButton.setAccessibilityLabel(text("key-recorder-icon"))
        iconButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 58).isActive = true

        searchField.placeholderString = text("key-recorder-icon-search")
        searchField.delegate = self
        searchField.identifier = Identifier.search
        searchField.controlSize = .small
        searchField.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        searchField.sendsSearchStringImmediately = true

        grid.onChoose = { [weak self] name in
            self?.chooseSymbol(name)
        }
        gridScroll.documentView = grid
        gridScroll.hasVerticalScroller = true
        gridScroll.drawsBackground = false
        gridScroll.borderType = .noBorder
        gridScroll.translatesAutoresizingMaskIntoConstraints = false
        gridScroll.heightAnchor.constraint(equalToConstant: Self.gridHeight).isActive = true

        noMatchLabel.stringValue = text("key-recorder-icon-no-match")
        noMatchLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        noMatchLabel.textColor = .secondaryLabelColor
        noMatchLabel.identifier = Identifier.noMatch
        noMatchLabel.preferredMaxLayoutWidth = Self.width
        noMatchLabel.isHidden = true

        let characterCaption = NSTextField(labelWithString: text("key-recorder-icon-character"))
        characterCaption.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        characterField.delegate = self
        characterField.identifier = Identifier.character
        characterField.alignment = .center
        characterField.controlSize = .small
        characterField.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        characterField.setAccessibilityLabel(text("key-recorder-icon-character"))
        characterField.translatesAutoresizingMaskIntoConstraints = false
        characterField.widthAnchor.constraint(equalToConstant: 34).isActive = true

        removeIconButton.title = text("key-recorder-icon-remove")
        removeIconButton.bezelStyle = .rounded
        removeIconButton.controlSize = .small
        removeIconButton.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        removeIconButton.target = self
        removeIconButton.action = #selector(removeIcon(_:))
        removeIconButton.identifier = Identifier.removeIcon

        let characterSpacer = spacer()
        let characterRow = row([characterCaption, characterField, characterSpacer, removeIconButton])

        chooser.orientation = .vertical
        chooser.alignment = .leading
        chooser.spacing = 6
        for view in [searchField, gridScroll, noMatchLabel, characterRow] as [NSView] {
            chooser.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: chooser.widthAnchor).isActive = true
        }

        noteLabel.stringValue = text("key-recorder-label-note")
        noteLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        noteLabel.textColor = .secondaryLabelColor
        noteLabel.identifier = Identifier.note
        noteLabel.preferredMaxLayoutWidth = Self.width
        noteLabel.isSelectable = false

        recordAgainButton.title = text("key-recorder-record-again")
        recordAgainButton.bezelStyle = .rounded
        recordAgainButton.target = self
        recordAgainButton.action = #selector(recordAgain(_:))
        recordAgainButton.identifier = Identifier.recordAgain

        doneButton.title = text("key-recorder-done")
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"
        doneButton.target = self
        doneButton.action = #selector(done(_:))
        doneButton.identifier = Identifier.done

        let iconSpacer = spacer()
        let buttonSpacer = spacer()

        let column = NSStackView(views: [
            row([caption("key-recorder-name"), nameField]),
            row([caption("key-recorder-icon"), iconButton, iconSpacer]),
            chooser,
            noteLabel,
            row([recordAgainButton, buttonSpacer, doneButton]),
        ])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 10
        column.setCustomSpacing(12, after: noteLabel)
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        var constraints = [
            widthAnchor.constraint(equalToConstant: Self.width),
            column.topAnchor.constraint(equalTo: topAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor),
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
        ]
        for view in column.arrangedSubviews {
            constraints.append(view.widthAnchor.constraint(equalTo: column.widthAnchor))
        }
        NSLayoutConstraint.activate(constraints)
    }
}
