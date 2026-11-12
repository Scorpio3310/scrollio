//
//  SettingsImportSheet.swift
//  Scrollio
//  The sheet between choosing a settings file and importing it (General › Settings file ›
//  Import…, and Restore…). It says what the file holds, in the words of the panes, and
//  asks before anything changes:
//
//      Import these settings?
//      “Scrollio Settings 2026-11-12.json”, saved by Scrollio 1.0.1 on 12 Nov 2026 at 10:42.
//      ┌ Scrolling settings · Thumb wheel · 4 apps with their own settings ·
//      └ 12 button and key actions · Gestures · Logitech mouse values · Show in menu bar: on
//      ┌ ⚠ 2 actions open an app or a file, or run a script
//      │ Each starts at a press of its button or key. …
//      └ ⌥ Button 5: runs the script /Users/…/sync.sh (arguments: --all)   (every one, scrolls)
//        Button 4: opens the app /Applications/Notes.app, or else the app with the ID com.apple.Notes
//      These settings replace the ones on this Mac. Your current settings are saved first, …
//                                                                   [Cancel] [Import]
//
//  A settings file can give a button or key an action that opens an app or a file, or runs
//  a script (SECURITY.md). When the file holds such actions the sheet says how many and
//  lists every one with its button or key and its whole path, and "Cancel" is the button
//  Return presses (Esc cancels as always; importing then takes a click on "Import"). A
//  path is shown as it is stored, with characters that draw nothing or turn the text
//  around written out ("\u{202E}"), so a path cannot look like another.
//
//  The same sheet says why a file cannot be used, or why an export or import failed: a
//  title, one or two plain sentences, "OK". It is a sheet on the settings window, never
//  an alert that is modal for the app (AGENTS.md, "Module boundaries").
//
//  `SettingsFileText` holds every text of it, pure, so the tests read the same words.
//

import Cocoa

// MARK: - Texts

enum SettingsFileText {

    private static func text(_ key: String) -> String {
        return NSLocalizedString(key, comment: "")
    }

    /// One line of what a file holds, with the symbol before it.
    struct Item: Equatable {
        let symbolName: String
        let text: String
    }

    /// What `contents` holds, in the order of the sidebar: one line per group of settings
    /// an import would replace.
    static func items(of contents: SettingsFile.Contents) -> [Item] {
        var items: [Item] = []
        if contents.groups.contains(.scroll) {
            items.append(Item(symbolName: "arrow.up.and.down", text: text("general-settings-import-scrolling")))
        }
        if contents.groups.contains(.thumbWheel) {
            items.append(Item(symbolName: "arrow.left.and.right", text: text("general-settings-import-thumb-wheel")))
        }
        if contents.groups.contains(.buttons) {
            items.append(Item(
                symbolName: "button.horizontal.top.press",
                text: counted(contents.bindings?.count ?? 0, "general-settings-import-actions")
            ))
        }
        if contents.groups.contains(.gesture) {
            items.append(Item(symbolName: "hand.draw", text: text("general-settings-import-gestures")))
        }
        if contents.holdsLogitechValues {
            items.append(Item(symbolName: "computermouse", text: text("general-settings-import-logitech")))
        }
        if contents.groups.contains(.application) {
            items.append(Item(
                symbolName: "square.grid.2x2",
                text: counted(contents.applications?.count ?? 0, "general-settings-import-apps")
            ))
            if contents.allowlist == true {
                items.append(Item(symbolName: "line.3.horizontal.decrease", text: text("general-settings-import-apps-limit")))
            }
        }
        if let hidden = contents.hidesMenuBarIcon {
            items.append(Item(
                symbolName: "menubar.rectangle",
                text: text(hidden ? "general-settings-import-menu-bar-off" : "general-settings-import-menu-bar-on")
            ))
        }
        return items
    }

    /// "No …", "1 …" or "%d …": the catalog has one string for each (`key` + "-none",
    /// "-one", "-other").
    static func counted(_ count: Int, _ key: String) -> String {
        switch count {
        case 0: return text(key + "-none")
        case 1: return text(key + "-one")
        default: return String(format: text(key + "-other"), count)
        }
    }

    /// The line under the title: the file's name, and who saved it when, if the file says.
    static func source(
        fileName: String, header: SettingsFile.Header, locale: Locale = .current, timeZone: TimeZone = .current
    ) -> String {
        let name = visible(fileName)
        guard let version = header.appVersion else {
            return String(format: text("general-settings-import-source-plain"), name)
        }
        guard let exported = header.exported else {
            return String(format: text("general-settings-import-source-version"), name, version)
        }
        return String(format: text("general-settings-import-source"), name, version, moment(exported, locale: locale, timeZone: timeZone))
    }

    /// "12 Nov 2026 at 10:42" in the user's format.
    static func moment(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// "2 actions open an app or a file, or run a script".
    static func launchTitle(count: Int) -> String {
        return count == 1
            ? text("general-settings-import-launch-one")
            : String(format: text("general-settings-import-launch-other"), count)
    }

    /// "⌥ Button 5: runs the script /Users/…/sync.sh (arguments: --all)": the button or
    /// key, what a press does, and the whole path as it is stored. An app is opened at
    /// its path, and when nothing is there, as the app macOS knows by the stored
    /// identifier (`ShortcutExecutor.applicationURL`): the identifier is part of what a
    /// press can open, so it is written out too.
    static func launchLine(for action: SettingsFile.LaunchAction, logitech: ButtonTriggerNaming.Logitech = .live) -> String {
        var target = visible(action.target.path)
        if action.target.kind == .application, let identifier = action.target.bundleID, !identifier.isEmpty {
            target = String(format: text("general-settings-import-launch-identifier"), target, visible(identifier))
        }
        if !action.target.arguments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            target = String(format: text("general-settings-import-launch-arguments"), target, visible(action.target.arguments))
        }
        let key: String
        switch action.target.kind {
        case .application: key = "general-settings-import-launch-app"
        case .file: key = "general-settings-import-launch-file"
        case .script: key = "general-settings-import-launch-script"
        }
        return String(format: text(key), ButtonTriggerNaming.title(for: action.trigger, logitech: logitech), target)
    }

    /// "3 values were out of range and were corrected."
    static func corrected(count: Int) -> String {
        return count == 1
            ? text("general-settings-import-corrected-one")
            : String(format: text("general-settings-import-corrected-other"), count)
    }

    /// "2 entries this version of Scrollio does not know are left out.": entries it
    /// cannot read, and buttons, keys and gesture directions with an action it does not run.
    static func unreadable(count: Int) -> String {
        return count == 1
            ? text("general-settings-import-unreadable-one")
            : String(format: text("general-settings-import-unreadable-other"), count)
    }

    /// Why a file cannot be used, or an export or import was not done: plain sentences.
    static func explanation(of problem: SettingsFile.Problem) -> String {
        switch problem {
        case .cannotRead(let reason):
            return joined(text("general-settings-problem-read"), reason)
        case .tooLarge:
            return text("general-settings-problem-too-large")
        case .notASettingsFile:
            return text("general-settings-problem-not-settings")
        case .newerFormat:
            return text("general-settings-problem-newer")
        case .damaged(let part):
            return String(format: text("general-settings-problem-damaged"), visible(part))
        case .nothingToImport:
            return text("general-settings-problem-empty")
        case .tooManyEntries:
            return String(format: text("general-settings-problem-too-many"), SettingsFile.maximumEntries)
        case .cannotStore:
            return text("general-settings-problem-not-stored")
        case .cannotWrite(let reason):
            return joined(text("general-settings-problem-write"), reason)
        case .backupFailed(let reason):
            return joined(text("general-settings-problem-backup"), reason)
        case .storeUnavailable:
            return text("general-settings-problem-store")
        }
    }

    private static func joined(_ sentence: String, _ reason: String) -> String {
        let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return reason.isEmpty ? sentence : sentence + " " + reason
    }

    /// `text` with every character that draws nothing, breaks the line or turns the
    /// writing direction around written out as "\u{…}". A path or an argument of a file
    /// is shown through this, so it cannot hide a part of itself or look like another.
    static func visible(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .surrogate, .privateUse, .unassigned:
                out += "\\u{" + String(scalar.value, radix: 16, uppercase: true) + "}"
            default:
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }
}

// MARK: - The sheet

final class SettingsImportSheetViewController: NSViewController {

    enum Content {
        /// What the file holds, with "Cancel" and "Import".
        case confirm(SettingsFile.Contents, fileName: String)
        /// Why something could not be done, with "OK".
        case problem(title: String, text: String)
    }

    static let width: CGFloat = 480
    static let margin: CGFloat = 20
    /// The list of actions that open or run something scrolls when it is taller than this.
    static let launchListMaximumHeight: CGFloat = 132

    private(set) var content: Content
    /// "Import" was clicked.
    var onImport: (() -> Void)?
    /// "Cancel" or "OK" was clicked, or Esc pressed.
    var onClose: (() -> Void)?

    // MARK: Views (read access for tests)

    private(set) var titleLabel: NSTextField!
    /// The file's name and who saved it; the explanation of a problem.
    private(set) var detailLabel: NSTextField!
    /// What the file holds, one line each.
    private(set) var itemLabels: [NSTextField] = []
    /// "2 actions open an app or a file, or run a script"; nil without such actions.
    private(set) var launchTitleLabel: NSTextField?
    private(set) var launchHintLabel: NSTextField?
    /// Every such action, one per line.
    private(set) var launchList: NSTextView?
    private(set) var launchScrollView: NSScrollView?
    private(set) var noteLabel: NSTextField?
    private(set) var unreadableLabel: NSTextField?
    /// "3 values were out of range and were corrected."; nil when none was.
    private(set) var correctedLabel: NSTextField?
    private(set) var importButton: NSButton?
    /// "Cancel", or "OK" of a problem.
    private(set) var closeButton: NSButton!

    private var stack: NSStackView?
    private var contentWidth: CGFloat { return Self.width - 2 * Self.margin }

    init(content: Content) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("SettingsImportSheetViewController is built in code")
    }

    private func text(_ key: String) -> String {
        return NSLocalizedString(key, comment: "")
    }

    // MARK: Building

    override func loadView() {
        let root = SettingsImportSheetView()
        root.widthAnchor.constraint(equalToConstant: Self.width).isActive = true
        view = root
        rebuild()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // The keyboard starts on the sheet itself, not in the list of paths (a text that
        // can be selected would take it, and the keys with it): Return and Esc reach the
        // buttons.
        view.window?.makeFirstResponder(view)
    }

    /// A new, empty stack in the place of the one that showed something else.
    private func installStack() {
        stack?.removeFromSuperview()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        // Exactly as tall as what it holds: the sheet shrinks when it shows less.
        stack.setHuggingPriority(.defaultHigh, for: .vertical)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: Self.margin),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Self.margin),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Self.margin),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -Self.margin),
            // Its own width, so that it can be measured by itself (`rebuild`).
            stack.widthAnchor.constraint(equalToConstant: Self.width - 2 * Self.margin),
        ])
        self.stack = stack
    }

    /// Shows something else in the same sheet: why an import that was confirmed failed.
    func show(_ content: Content) {
        self.content = content
        guard isViewLoaded else { return }
        rebuild()
    }

    private func rebuild() {
        installStack()
        itemLabels = []
        launchTitleLabel = nil
        launchHintLabel = nil
        launchList = nil
        launchScrollView = nil
        noteLabel = nil
        unreadableLabel = nil
        correctedLabel = nil
        importButton = nil

        switch content {
        case .confirm(let contents, let fileName):
            buildConfirmation(of: contents, fileName: fileName)
        case .problem(let title, let text):
            buildProblem(title: title, text: text)
        }
        // Measured on the stack, not on the controller's view: AppKit holds that view at
        // its preferred size (a constraint of priority 501 on the view itself), and with
        // the old size in place a sheet that shows less would measure as tall as it was.
        let height = ceil(stack?.fittingSize.height ?? 0) + 2 * Self.margin
        let size = NSSize(width: Self.width, height: height)
        view.setFrameSize(size)
        preferredContentSize = size
        view.layoutSubtreeIfNeeded()
    }

    private func add(_ view: NSView, spacingBefore: CGFloat? = nil) {
        guard let stack else { return }
        if let spacingBefore, let previous = stack.arrangedSubviews.last {
            stack.setCustomSpacing(spacingBefore, after: previous)
        }
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func buildConfirmation(of contents: SettingsFile.Contents, fileName: String) {
        titleLabel = makeTitle(text("general-settings-import-title"))
        add(titleLabel)
        detailLabel = makeNote(SettingsFileText.source(fileName: fileName, header: contents.header), width: contentWidth)
        add(detailLabel, spacingBefore: 4)

        let rows = SettingsFileText.items(of: contents).map(makeItemRow)
        add(SettingsImportBox(rows: rows))

        let actions = contents.launchActions
        if !actions.isEmpty {
            add(makeLaunchBox(for: actions))
        }

        let note = makeNote(text("general-settings-import-note"), width: contentWidth)
        noteLabel = note
        add(note)
        if contents.leftOutCount > 0 {
            let unreadable = makeNote(SettingsFileText.unreadable(count: contents.leftOutCount), width: contentWidth)
            unreadableLabel = unreadable
            add(unreadable, spacingBefore: 4)
        }
        if contents.correctedValues > 0 {
            let corrected = makeNote(SettingsFileText.corrected(count: contents.correctedValues), width: contentWidth)
            correctedLabel = corrected
            add(corrected, spacingBefore: 4)
        }

        let cancel = SettingsSheetCancelButton(
            title: text("general-settings-import-cancel"), target: self, action: #selector(closeClicked(_:))
        )
        cancel.bezelStyle = .push
        cancel.controlSize = .regular
        cancel.translatesAutoresizingMaskIntoConstraints = false
        let confirm = PreferencesGroupedForm.makePushButton(
            title: text("general-settings-import-confirm"), target: self, action: #selector(importClicked(_:))
        )
        // Return imports, unless the file brings actions that open or run something: then
        // Return is "Cancel" (and so is Esc, as always), and importing takes a click on
        // "Import".
        if actions.isEmpty {
            confirm.keyEquivalent = "\r"
            cancel.keyEquivalent = "\u{1b}"
        } else {
            cancel.keyEquivalent = "\r"
            cancel.alsoTakesEscape = true
        }
        closeButton = cancel
        importButton = confirm
        add(makeButtonLine([cancel, confirm]), spacingBefore: 16)
    }

    private func buildProblem(title: String, text problem: String) {
        titleLabel = makeTitle(title)
        add(titleLabel)
        detailLabel = makeNote(problem, width: contentWidth)
        detailLabel.font = PreferencesGroupedForm.titleFont
        detailLabel.textColor = .labelColor
        add(detailLabel, spacingBefore: 6)
        let ok = PreferencesGroupedForm.makePushButton(
            title: text("general-settings-import-ok"), target: self, action: #selector(closeClicked(_:))
        )
        ok.keyEquivalent = "\r"
        closeButton = ok
        add(makeButtonLine([ok]), spacingBefore: 16)
    }

    private func makeTitle(_ title: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: title)
        label.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .labelColor
        label.isSelectable = false
        label.preferredMaxLayoutWidth = contentWidth
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    /// A muted line of the hint size that wraps at `width`.
    private func makeNote(_ note: String, width: CGFloat) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: note)
        label.font = PreferencesGroupedForm.explanationFont
        label.textColor = .secondaryLabelColor
        label.isSelectable = false
        label.preferredMaxLayoutWidth = width
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func makeSymbol(_ name: String, color: NSColor) -> NSImageView {
        let image = NSImageView()
        image.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: NSFont.systemFontSize, weight: .regular)
        image.contentTintColor = color
        image.imageScaling = .scaleNone
        // The words next to it say what the line is.
        image.setAccessibilityElement(false)
        image.translatesAutoresizingMaskIntoConstraints = false
        image.widthAnchor.constraint(equalToConstant: 20).isActive = true
        return image
    }

    private func makeItemRow(_ item: SettingsFileText.Item) -> NSView {
        let label = NSTextField(labelWithString: item.text)
        label.font = PreferencesGroupedForm.titleFont
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        itemLabels.append(label)
        let row = NSStackView(views: [makeSymbol(item.symbolName, color: .secondaryLabelColor), label])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    /// The box about actions that open an app or a file, or run a script: how many, what
    /// that means, and every one of them.
    private func makeLaunchBox(for actions: [SettingsFile.LaunchAction]) -> NSView {
        let inner = contentWidth - 2 * SettingsImportBox.inset
        let title = NSTextField(wrappingLabelWithString: SettingsFileText.launchTitle(count: actions.count))
        title.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        title.textColor = .labelColor
        title.isSelectable = false
        title.preferredMaxLayoutWidth = inner - 28
        launchTitleLabel = title
        let heading = NSStackView(views: [makeSymbol("exclamationmark.triangle.fill", color: .systemOrange), title])
        heading.orientation = .horizontal
        heading.alignment = .top
        heading.spacing = 8

        let hint = makeNote(text("general-settings-import-launch-hint"), width: inner)
        launchHintLabel = hint

        let lines = actions.map { SettingsFileText.launchLine(for: $0) }.joined(separator: "\n")
        let scroll = makeLaunchList(lines, width: inner)
        return SettingsImportBox(rows: [heading, hint, scroll])
    }

    /// Every action in a paragraph of its own, in a fixed-width font, as tall as its text up
    /// to `launchListMaximumHeight`; beyond that it scrolls. The text can be selected and copied.
    private func makeLaunchList(_ lines: String, width: CGFloat) -> NSScrollView {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 10))
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        // One action per paragraph; what does not fit goes on, indented, on the next line.
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.headIndent = 14
        paragraph.paragraphSpacing = 4
        textView.textStorage?.setAttributedString(NSAttributedString(string: lines, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: PreferencesForm.hintFontSize, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]))
        textView.setAccessibilityLabel(SettingsFileText.launchTitle(count: lines.components(separatedBy: "\n").count))
        var height: CGFloat = 0
        if let container = textView.textContainer, let layout = textView.layoutManager {
            layout.ensureLayout(for: container)
            height = ceil(layout.usedRect(for: container).height)
        }
        textView.setFrameSize(NSSize(width: width, height: height))
        launchList = textView

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        // A list that does not fit keeps its scroll bar in sight (the system's own would
        // hide until it is used): nobody takes the first lines for all of them.
        scroll.hasVerticalScroller = height > Self.launchListMaximumHeight
        scroll.scrollerStyle = .legacy
        scroll.hasHorizontalScroller = false
        scroll.documentView = textView
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: min(max(height, 14), Self.launchListMaximumHeight)).isActive = true
        launchScrollView = scroll
        return scroll
    }

    /// The buttons at the right edge, the one that goes on last.
    private func makeButtonLine(_ buttons: [NSButton]) -> NSView {
        let line = NSView()
        line.translatesAutoresizingMaskIntoConstraints = false
        let row = NSStackView(views: buttons)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        line.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: line.topAnchor),
            row.bottomAnchor.constraint(equalTo: line.bottomAnchor),
            row.trailingAnchor.constraint(equalTo: line.trailingAnchor),
            row.leadingAnchor.constraint(greaterThanOrEqualTo: line.leadingAnchor),
        ])
        for button in buttons {
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 76).isActive = true
        }
        return line
    }

    // MARK: Actions

    @objc func importClicked(_ sender: Any?) {
        onImport?()
    }

    @objc func closeClicked(_ sender: Any?) {
        onClose?()
    }

    /// Esc.
    override func cancelOperation(_ sender: Any?) {
        onClose?()
    }
}

/// The sheet's own view: it can hold the keyboard, so that the list of paths does not.
final class SettingsImportSheetView: NSView {
    override var acceptsFirstResponder: Bool {
        return true
    }
}

/// "Cancel" where it is the default button (Return): Esc presses it too. A button has one
/// key equivalent; this one also answers the Esc key, the way a window looks for the
/// button of a key (`performKeyEquivalent`).
final class SettingsSheetCancelButton: NSButton {

    static let escapeKeyCode: UInt16 = 53
    var alsoTakesEscape = false

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if alsoTakesEscape, isEnabled, event.type == .keyDown, modifiers.isEmpty, event.keyCode == Self.escapeKeyCode {
            return sendAction(action, to: target)
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// A rounded box of the panes' fill with its rows under each other.
final class SettingsImportBox: NSView {

    static let inset: CGFloat = 12

    init(rows: [NSView]) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: Self.inset),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.inset),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.inset),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.inset),
        ])
        for row in rows {
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    required init?(coder: NSCoder) {
        fatalError("SettingsImportBox is built in code")
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
