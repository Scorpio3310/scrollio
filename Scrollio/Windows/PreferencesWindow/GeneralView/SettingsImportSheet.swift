//
//  SettingsImportSheet.swift
//  Scrollio
//  The sheet between choosing a settings file and importing it (General › Settings file ›
//  Import…, and Restore…). It says what the file holds, in the words of the panes, and
//  asks before anything changes:
//
//      Import these settings?
//      “Scrollio Settings 2026-11-12.json”. It says it was saved by Scrollio 1.0.1 on …
//      ┌ Scrolling settings · Thumb wheel · 3 button and key actions · Gestures ·
//      └ Logitech mouse values · 4 apps with their own settings · Show in menu bar: on
//      ┌ ⚠ 1 action opens an app or a file, or runs a script
//      │ Each starts at a press of its button or key. …
//      └ ⌥ F5: runs the script /Users/…/sync.sh (arguments: --all)
//      ┌ What the buttons, keys and gestures will do
//      │ ⌥ F5: Open App or File: sync.sh
//      │ ⌘ C: Switch to Computer 2
//      │ Middle button: ⇧ ⌘ Q
//      └ Gesture Up: Empty Trash
//      These settings replace the ones on this Mac. Your current settings are saved first, …
//                                                                   [Cancel] [Import]
//
//  What an imported setting can do when a button or key is pressed is the one thing a
//  user has to see before the import (SECURITY.md). So the sheet lists every button and
//  key of the file with its action, in the words of the Buttons pane, and the directions
//  of Gesture Navigation whose action is not the default one: a Logitech action writes to
//  the mouse whatever "Let Scrollio manage this mouse" says, a recorded shortcut can be
//  any key combination, "Move to Trash" on ⇧E is not what anybody wants to find out by
//  typing. Above that list, a box of its own for the actions that open an app or a file
//  or run a script: how many, and every one with its whole path and arguments.
//
//  "Import" is the button Return presses only when the file gives no button or key an
//  action and leaves the gestures as they are by default; otherwise Return is "Cancel"
//  (Esc cancels as always), and importing takes a click on "Import".
//
//  The boxes are the middle part of the sheet and scroll together when they are taller
//  than the screen leaves room for (`maximumHeight`); the title above and, below, the
//  notes and the buttons stay in place. A path, an argument or a name from the file is
//  shown as it is stored, with characters that draw nothing or turn the text around
//  written out ("\u{202E}", `SettingsFileText.visible`).
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
        if contents.groups.contains(.ring) {
            items.append(Item(symbolName: SystemShortcut.shortcutRing.symbolName, text: text("general-settings-import-ring")))
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

    // MARK: Every button, key and gesture

    /// One line per button and key of the file, in the order of the file: "⌥ F5: Mission
    /// Control", and for a button that is one app's own "⌥ F5 in Notes: Mission Control".
    /// The trigger and the action are named as the Buttons pane names them.
    static func actionLines(of contents: SettingsFile.Contents, logitech: ButtonTriggerNaming.Logitech = .live) -> [String] {
        return contents.allBindings.map { entry in
            let trigger = ButtonTriggerNaming.title(for: entry.binding.triggerEvent, logitech: logitech)
            let action = actionName(of: entry.binding)
            guard let application = entry.application else {
                return String(format: text("general-settings-import-action-line"), trigger, action)
            }
            return String(format: text("general-settings-import-action-line-app"), trigger, name(of: application), action)
        }
    }

    /// What a button or key does, in the Buttons pane's words: the action's name, a
    /// recorded shortcut as its keys, "No Action". An action that opens or runs something
    /// is named by its file here ("Open App or File: sync.sh"); its whole path is in the
    /// box above. Nothing on disk is looked at: the paths are a file's, not the user's.
    static func actionName(of binding: ButtonBinding) -> String {
        if let target = binding.openTarget {
            let name = (target.path as NSString).lastPathComponent
            return String(format: text("general-settings-import-action-open"), visible(name.isEmpty ? target.path : name))
        }
        return ActionDisplayResolver().actionName(of: binding) ?? text("unbound")
    }

    /// An app of the file's list by the name the file gives it, else by its file's name.
    static func name(of application: Application) -> String {
        if let name = application.displayName, !name.isEmpty {
            return visible(name)
        }
        let file = ((application.path as NSString).lastPathComponent as NSString).deletingPathExtension
        return visible(file.isEmpty ? application.path : file)
    }

    /// One line per direction of Gesture Navigation (and its click) whose action is not
    /// the default one: "Gesture Up: App Exposé". None when the file leaves them alone.
    static func gestureLines(of contents: SettingsFile.Contents) -> [String] {
        guard let gesture = contents.gesture else { return [] }
        let defaults = MouseGestureSettings.default
        return MouseGestureSettingsControls.Slot.allCases.compactMap { slot in
            let identifier = slot.value(in: gesture)
            guard identifier != slot.value(in: defaults) else { return nil }
            let action = SystemShortcut.getShortcut(named: identifier)?.localizedName ?? text("gesture-action-none")
            return String(format: text("general-settings-import-gesture-line"), text(slot.labelKey), action)
        }
    }

    /// One line per place of the Shortcut Ring whose action is not the default one: "Ring
    /// Top right: Paste". None when the file leaves the ring as a new one is.
    static func ringLines(of contents: SettingsFile.Contents) -> [String] {
        guard let ring = contents.ring else { return [] }
        let defaults = ShortcutRingSettings.default
        return ring.places.indices.compactMap { index in
            guard ring[index] != defaults[index] else { return nil }
            let action = ring[index].shortcut?.localizedName ?? text("ring-action-none")
            return String(format: text("general-settings-import-ring-line"), text(ShortcutRingPlaceName.key(of: index)), action)
        }
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

    /// `text` with every character that draws nothing, draws only space, breaks the line
    /// or turns the writing direction around written out as "\u{…}". A path, an argument
    /// or a name from a file is shown through this, so that no part of it is out of sight.
    ///
    /// What is written out (`isWrittenOut`): every space but the ordinary one (a no-break
    /// space looks like a space, and the arguments of an action are split at it too),
    /// controls and line breaks, the characters that format or are ignored by default
    /// (zero width, direction marks, variation selectors, the Hangul fillers), blank
    /// glyphs, and what has no character.
    ///
    /// A run of such characters is one mark with its length ("\u{A0}×3000"), and so is
    /// a run of four or more ordinary spaces ("\u{20}×40"): three thousand no-break
    /// spaces between two arguments showed a harmless first line and forty blank ones,
    /// the second argument far below. However long a run is, what stands for it is short.
    /// Ordinary spaces at the very start or end are written out too. Letters that look
    /// like other letters are not told apart.
    static func visible(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        var out = ""
        var index = 0
        while index < scalars.count {
            guard isBlank(scalars[index]) else {
                out.unicodeScalars.append(scalars[index])
                index += 1
                continue
            }
            var end = index
            while end < scalars.count, isBlank(scalars[end]) {
                end += 1
            }
            out += mark(for: scalars[index..<end], atAnEdge: index == 0 || end == scalars.count)
            index = end
        }
        return out
    }

    /// Glyphs that are blank although their character is a symbol: the Braille pattern
    /// without dots, and the object replacement character.
    static let blankGlyphs: Set<UInt32> = [0x2800, 0xFFFC]

    /// Whether `scalar` is shown as "\u{…}" and not as itself.
    static func isWrittenOut(_ scalar: Unicode.Scalar) -> Bool {
        if scalar == " " {
            return false
        }
        switch scalar.properties.generalCategory {
        case .control, .format, .lineSeparator, .paragraphSeparator, .spaceSeparator, .surrogate, .privateUse, .unassigned:
            return true
        default:
            return scalar.properties.isDefaultIgnorableCodePoint || blankGlyphs.contains(scalar.value)
        }
    }

    private static func isBlank(_ scalar: Unicode.Scalar) -> Bool {
        return scalar == " " || isWrittenOut(scalar)
    }

    private static func written(_ scalar: Unicode.Scalar) -> String {
        return "\\u{" + String(scalar.value, radix: 16, uppercase: true) + "}"
    }

    /// What stands for a run of blank characters: each kind with how many of it in a
    /// row, or, when the kinds change more than four times, one mark for all of it (its
    /// first kinds and the length). Up to three ordinary spaces stay spaces, unless they
    /// stand at an edge of the text.
    private static func mark(for run: ArraySlice<Unicode.Scalar>, atAnEdge: Bool) -> String {
        var groups: [(scalar: Unicode.Scalar, count: Int)] = []
        for scalar in run {
            if let last = groups.last, last.scalar == scalar {
                groups[groups.count - 1].count += 1
            } else {
                groups.append((scalar, 1))
            }
        }
        guard groups.count <= 4 else {
            var kinds: [Unicode.Scalar] = []
            for group in groups where !kinds.contains(group.scalar) {
                kinds.append(group.scalar)
                if kinds.count > 4 { break }
            }
            return kinds.prefix(4).map(written).joined() + (kinds.count > 4 ? "…" : "") + "×\(run.count)"
        }
        return groups.map { group -> String in
            if group.scalar == " ", group.count < 4, !atAnEdge {
                return String(repeating: " ", count: group.count)
            }
            return written(group.scalar) + (group.count > 1 ? "×\(group.count)" : "")
        }.joined()
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
    /// Between the title, the middle part and the notes.
    static let gap: CGFloat = 12
    /// The middle part's scroll bar stands in the sheet's right margin, so the boxes are
    /// as wide with it as without: what is left of the margin to the right of the bar.
    static var scrollBarInset: CGFloat {
        return max(0, margin - NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy))
    }
    /// The least the middle part shows, however low `maximumHeight` is.
    static let minimumMiddleHeight: CGFloat = 120

    /// The tallest the sheet gets. What does not fit scrolls, in the middle part.
    var maximumHeight = SettingsImportSheetViewController.defaultMaximumHeight()

    /// Room for the sheet under the window's title bar on the screen in use, and never
    /// more than 720 pt: a sheet is not a window.
    static func defaultMaximumHeight(screenHeight: CGFloat? = NSScreen.main?.visibleFrame.height) -> CGFloat {
        return min(720, max(420, (screenHeight ?? 900) - 160))
    }

    private(set) var content: Content
    /// "Import" was clicked.
    var onImport: (() -> Void)?
    /// "Cancel" or "OK" was clicked, or Esc pressed.
    var onClose: (() -> Void)?

    // MARK: Views (read access for tests)

    private(set) var titleLabel: NSTextField!
    /// The file's name and who it says saved it; the explanation of a problem.
    private(set) var detailLabel: NSTextField!
    /// What the file holds, one line each.
    private(set) var itemLabels: [NSTextField] = []
    /// "2 actions open an app or a file, or run a script"; nil without such actions.
    private(set) var launchTitleLabel: NSTextField?
    private(set) var launchHintLabel: NSTextField?
    /// Every such action with its whole path, one per paragraph.
    private(set) var launchList: NSTextView?
    /// "What the buttons, keys and gestures will do"; nil when the file brings none.
    private(set) var actionsTitleLabel: NSTextField?
    /// Every button and key with its action, then the gesture directions that are not
    /// the default, one per paragraph.
    private(set) var actionList: NSTextView?
    /// The middle part: the boxes, scrolling together when they do not fit.
    private(set) var middleScrollView: NSScrollView?
    /// A line above and one below the middle part while it scrolls: where it is cut.
    private(set) var middleEdgeLines: [NSBox] = []
    private(set) var noteLabel: NSTextField?
    private(set) var unreadableLabel: NSTextField?
    /// "3 values were out of range and were corrected."; nil when none was.
    private(set) var correctedLabel: NSTextField?
    private(set) var importButton: NSButton?
    /// "Cancel", or "OK" of a problem.
    private(set) var closeButton: NSButton!

    /// Everything the sheet shows. Measured by itself (`rebuild`).
    private var body: NSView?
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
        // The keyboard starts on the sheet itself, not in a list (a text that can be
        // selected would take it, and the keys with it): Return and Esc reach the buttons.
        view.window?.makeFirstResponder(view)
    }

    /// Shows something else in the same sheet: why an import that was confirmed failed.
    func show(_ content: Content) {
        self.content = content
        guard isViewLoaded else { return }
        rebuild()
    }

    private func rebuild() {
        body?.removeFromSuperview()
        itemLabels = []
        launchTitleLabel = nil
        launchHintLabel = nil
        launchList = nil
        actionsTitleLabel = nil
        actionList = nil
        middleScrollView = nil
        middleEdgeLines = []
        noteLabel = nil
        unreadableLabel = nil
        correctedLabel = nil
        importButton = nil

        let header = makeColumn(spacing: 4)
        let footer = makeColumn(spacing: 4)
        var middle: NSStackView?
        switch content {
        case .confirm(let contents, let fileName):
            middle = buildConfirmation(of: contents, fileName: fileName, header: header, footer: footer)
        case .problem(let title, let text):
            buildProblem(title: title, text: text, header: header, footer: footer)
        }

        // The body is as tall as its parts; the middle part is as tall as its boxes, or as
        // the tallest sheet leaves room for, and then it scrolls.
        let body = NSView()
        body.translatesAutoresizingMaskIntoConstraints = false
        body.addSubview(header)
        body.addSubview(footer)
        // The margin under the buttons is the one place that gives: the sheet's height is
        // a whole number of points, what it holds may not be.
        let bottomMargin = footer.bottomAnchor.constraint(equalTo: body.bottomAnchor, constant: -Self.margin)
        bottomMargin.priority = .init(999)
        var constraints = [
            body.widthAnchor.constraint(equalToConstant: Self.width),
            header.topAnchor.constraint(equalTo: body.topAnchor, constant: Self.margin),
            header.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: Self.margin),
            footer.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: Self.margin),
            footer.bottomAnchor.constraint(lessThanOrEqualTo: body.bottomAnchor, constant: -Self.margin),
            bottomMargin,
        ]
        if let middle {
            let natural = ceil(middle.fittingSize.height)
            let others = 2 * Self.margin + header.fittingSize.height + footer.fittingSize.height + 2 * Self.gap
            let shown = min(natural, max(Self.minimumMiddleHeight, floor(maximumHeight - others)))
            let scroll = makeMiddleScroll(for: middle, scrolls: natural > shown)
            middleScrollView = scroll
            body.addSubview(scroll)
            constraints += [
                scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: Self.gap),
                scroll.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: Self.margin),
                scroll.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -Self.scrollBarInset),
                scroll.heightAnchor.constraint(equalToConstant: shown),
                footer.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: Self.gap),
            ]
            if natural > shown {
                // Where the boxes are cut, a line says so (with the scroll bar, which
                // stays in sight): what shows is not all there is.
                for edge in [scroll.topAnchor, scroll.bottomAnchor] {
                    let line = NSBox()
                    line.boxType = .separator
                    line.translatesAutoresizingMaskIntoConstraints = false
                    body.addSubview(line)
                    middleEdgeLines.append(line)
                    constraints += [
                        line.centerYAnchor.constraint(equalTo: edge),
                        line.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: Self.margin),
                        line.widthAnchor.constraint(equalToConstant: contentWidth),
                    ]
                }
            }
        } else {
            constraints.append(footer.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 16))
        }
        NSLayoutConstraint.activate(constraints)

        // Measured on the body, not on the controller's view: AppKit holds that view at its
        // preferred size (a constraint of priority 501 on the view itself), and with the
        // old size in place a sheet that shows less would measure as tall as it was.
        let size = NSSize(width: Self.width, height: ceil(body.fittingSize.height))
        view.addSubview(body)
        NSLayoutConstraint.activate([
            body.topAnchor.constraint(equalTo: view.topAnchor),
            body.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            body.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        self.body = body
        view.setFrameSize(size)
        preferredContentSize = size
        view.layoutSubtreeIfNeeded()
    }

    /// A column of the sheet's content width whose rows are as wide as itself.
    private func makeColumn(spacing: CGFloat) -> NSStackView {
        let column = NSStackView()
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = spacing
        // Exactly as tall as what it holds.
        column.setHuggingPriority(.required, for: .vertical)
        column.translatesAutoresizingMaskIntoConstraints = false
        column.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        return column
    }

    private func add(_ view: NSView, to column: NSStackView, spacingBefore: CGFloat? = nil) {
        if let spacingBefore, let previous = column.arrangedSubviews.last {
            column.setCustomSpacing(spacingBefore, after: previous)
        }
        column.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
    }

    /// The middle part in its scroll view. The boxes keep the sheet's content width; the
    /// scroll view reaches into the right margin, where its bar stands when there is one.
    /// A bar that is needed stays in sight (the system's own would hide until it is
    /// used): nobody takes the first boxes for all of them.
    private func makeMiddleScroll(for middle: NSStackView, scrolls: Bool) -> NSScrollView {
        let document = PreferencesPaneDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(middle)
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = scrolls
        scroll.scrollerStyle = .legacy
        scroll.autohidesScrollers = false
        scroll.hasHorizontalScroller = false
        scroll.verticalScrollElasticity = scrolls ? .allowed : .none
        scroll.horizontalScrollElasticity = .none
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        NSLayoutConstraint.activate([
            middle.topAnchor.constraint(equalTo: document.topAnchor),
            middle.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            middle.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            middle.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
        ])
        return scroll
    }

    /// Fills the title, the notes and the buttons, and returns the middle part: what the
    /// file holds, the actions that open or run something, and every button, key and
    /// gesture with its action.
    private func buildConfirmation(
        of contents: SettingsFile.Contents, fileName: String, header: NSStackView, footer: NSStackView
    ) -> NSStackView {
        titleLabel = makeTitle(text("general-settings-import-title"))
        add(titleLabel, to: header)
        detailLabel = makeNote(SettingsFileText.source(fileName: fileName, header: contents.header), width: contentWidth)
        add(detailLabel, to: header)

        let middle = makeColumn(spacing: Self.gap)
        add(SettingsImportBox(rows: SettingsFileText.items(of: contents).map(makeItemRow)), to: middle)
        let launches = contents.launchActions
        if !launches.isEmpty {
            add(makeLaunchBox(for: launches), to: middle)
        }
        let lines = SettingsFileText.actionLines(of: contents) + SettingsFileText.gestureLines(of: contents)
            + SettingsFileText.ringLines(of: contents)
        if !lines.isEmpty {
            add(makeActionsBox(for: lines), to: middle)
        }

        let note = makeNote(text("general-settings-import-note"), width: contentWidth)
        noteLabel = note
        add(note, to: footer)
        if contents.leftOutCount > 0 {
            let unreadable = makeNote(SettingsFileText.unreadable(count: contents.leftOutCount), width: contentWidth)
            unreadableLabel = unreadable
            add(unreadable, to: footer)
        }
        if contents.correctedValues > 0 {
            let corrected = makeNote(SettingsFileText.corrected(count: contents.correctedValues), width: contentWidth)
            correctedLabel = corrected
            add(corrected, to: footer)
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
        // Return imports only a file that gives no button or key an action and leaves the
        // gestures at their defaults. Otherwise Return is "Cancel" (and so is Esc, as
        // always), and importing takes a click on "Import".
        if contents.bringsActions {
            cancel.keyEquivalent = "\r"
            cancel.alsoTakesEscape = true
        } else {
            confirm.keyEquivalent = "\r"
            cancel.keyEquivalent = "\u{1b}"
        }
        closeButton = cancel
        importButton = confirm
        add(makeButtonLine([cancel, confirm]), to: footer, spacingBefore: 16)
        return middle
    }

    private func buildProblem(title: String, text problem: String, header: NSStackView, footer: NSStackView) {
        titleLabel = makeTitle(title)
        add(titleLabel, to: header)
        detailLabel = makeNote(problem, width: contentWidth)
        detailLabel.font = PreferencesGroupedForm.titleFont
        detailLabel.textColor = .labelColor
        add(detailLabel, to: header, spacingBefore: 6)
        let ok = PreferencesGroupedForm.makePushButton(
            title: text("general-settings-import-ok"), target: self, action: #selector(closeClicked(_:))
        )
        ok.keyEquivalent = "\r"
        closeButton = ok
        add(makeButtonLine([ok]), to: footer)
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

    /// The title of a box: the size of a row's title, semibold.
    private func makeBoxTitle(_ title: String, width: CGFloat) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: title)
        label.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        label.textColor = .labelColor
        label.isSelectable = false
        label.preferredMaxLayoutWidth = width
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
    /// that means, and every one of them with its whole path.
    private func makeLaunchBox(for actions: [SettingsFile.LaunchAction]) -> NSView {
        let inner = contentWidth - 2 * SettingsImportBox.inset
        let title = makeBoxTitle(SettingsFileText.launchTitle(count: actions.count), width: inner - 28)
        launchTitleLabel = title
        let heading = NSStackView(views: [makeSymbol("exclamationmark.triangle.fill", color: .systemOrange), title])
        heading.orientation = .horizontal
        heading.alignment = .top
        heading.spacing = 8

        let hint = makeNote(text("general-settings-import-launch-hint"), width: inner)
        launchHintLabel = hint

        let list = makeList(
            actions.map { SettingsFileText.launchLine(for: $0) },
            font: NSFont.monospacedSystemFont(ofSize: PreferencesForm.hintFontSize, weight: .regular),
            width: inner, accessibilityLabel: title.stringValue
        )
        launchList = list
        return SettingsImportBox(rows: [heading, hint, list])
    }

    /// The box with every button and key of the file and what it will do, and the
    /// directions of Gesture Navigation that are not the default.
    private func makeActionsBox(for lines: [String]) -> NSView {
        let inner = contentWidth - 2 * SettingsImportBox.inset
        let title = makeBoxTitle(text("general-settings-import-actions-title"), width: inner)
        actionsTitleLabel = title
        let list = makeList(
            lines, font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize + 1), width: inner, accessibilityLabel: title.stringValue
        )
        actionList = list
        return SettingsImportBox(rows: [title, list])
    }

    /// Lines of text, each a paragraph of its own (what does not fit goes on, indented, on
    /// the next line), as tall as the text: a list does not scroll by itself, the middle
    /// part of the sheet does. The text can be selected and copied.
    private func makeList(_ lines: [String], font: NSFont, width: CGFloat, accessibilityLabel: String) -> NSTextView {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 10))
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.headIndent = 14
        paragraph.paragraphSpacing = 4
        textView.textStorage?.setAttributedString(NSAttributedString(string: lines.joined(separator: "\n"), attributes: [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]))
        textView.setAccessibilityLabel(accessibilityLabel)
        var height: CGFloat = 0
        if let container = textView.textContainer, let layout = textView.layoutManager {
            layout.ensureLayout(for: container)
            height = ceil(layout.usedRect(for: container).height)
        }
        textView.setFrameSize(NSSize(width: width, height: height))
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.heightAnchor.constraint(equalToConstant: max(height, 14)).isActive = true
        return textView
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
