//
//  DifferentInAppsLine.swift
//  Scrollio
//
//  The last line of the Scrolling, Buttons, Gestures and Shortcut Ring panes: "Different in
//  Safari and Figma", the apps that have settings of that kind of their own. They are
//  exactly the apps the Apps list marks for it (`ApplicationPagePart.hasOwnSettings`), so
//  the line never disagrees with the marks or with "Own: …". Each name is a link to that
//  app's page on that part, as a click on its mark is. Up to three apps are named; of four
//  or more the first two, and the rest are counted ("Safari, Figma and 3 more", "3 more"
//  leading to Apps). While no app differs the line takes no room, so a pane is as tall as
//  it is without it.
//
//  `DifferentInApps` is the pure part: who counts, the cut, the sentence, its pieces and
//  the rows they flow into. `DifferentInAppsLine` is the one view of all four panes. It
//  refreshes itself (when its pane comes on show, when its window becomes key, after an
//  Undo or Redo), so a pane only adds it. Nothing is stored.
//

import Cocoa

enum DifferentInApps {

    // MARK: - Who counts

    /// The apps of `applications` that have settings of `part`'s kind of their own, in
    /// their order: those the Apps list marks for it. Values are never compared: an app
    /// whose own values equal the pane's still counts, since the pane's next change does
    /// not reach it.
    static func applications(for part: ApplicationPagePart, among applications: [Application]) -> [Application] {
        return applications.filter(part.hasOwnSettings)
    }

    // MARK: - The cut

    /// The most apps the line names.
    static let namedAtMost = 3

    /// One item of the line's list.
    enum Item: Equatable {
        /// The app at this place among those that count.
        case app(Int)
        /// "N more": the apps that are not named.
        case more(Int)
    }

    /// How many of `count` apps are named: up to three all of them, of four or more the
    /// first two (so the rest is never "1 more").
    static func namedCount(forCount count: Int) -> Int {
        return count > namedAtMost ? namedAtMost - 1 : max(0, count)
    }

    /// The list for `count` apps: those named, then the rest counted.
    static func items(forCount count: Int) -> [Item] {
        let named = namedCount(forCount: count)
        let apps = (0..<named).map(Item.app)
        return count > named ? apps + [.more(count - named)] : apps
    }

    /// "3 more".
    static func moreTitle(_ count: Int) -> String {
        return String(format: NSLocalizedString("apps-different-more", comment: ""), count)
    }

    // MARK: - The sentence

    /// One piece of the sentence: plain text, the name of the app at a place among those
    /// that count, or "N more".
    enum Piece: Equatable {
        case text(String)
        case app(Int)
        case more
    }

    /// The first of the private-use characters that stand for the items while the sentence
    /// is put together.
    private static let firstMark: UInt32 = 0xE000

    /// The sentence for `count` apps in pieces, joined as every list of the window is
    /// (`InterfaceList`). It is built with one private-use character per item and split at
    /// those, so the names never pass through the joiner or the format: one that holds
    /// ",", "and" or "%" cannot break it. Empty for no app.
    static func pieces(forCount count: Int, locale: Locale = InterfaceList.locale) -> [Piece] {
        let items = self.items(forCount: count)
        guard !items.isEmpty else { return [] }
        let marks = items.indices.compactMap { Unicode.Scalar(firstMark + UInt32($0)).map { String(Character($0)) } }
        let template = String(
            format: NSLocalizedString("apps-different-in", comment: ""), InterfaceList.joined(marks, locale: locale)
        )
        var pieces: [Piece] = []
        var text = String.UnicodeScalarView()
        func endText() {
            guard !text.isEmpty else { return }
            pieces.append(.text(String(text)))
            text = String.UnicodeScalarView()
        }
        for scalar in template.unicodeScalars {
            let place = Int(scalar.value) - Int(firstMark)
            guard items.indices.contains(place) else {
                text.append(scalar)
                continue
            }
            endText()
            switch items[place] {
            case .app(let index): pieces.append(.app(index))
            case .more: pieces.append(.more)
            }
        }
        endText()
        return pieces
    }

    /// `pieces` put together: `names` for the apps (those named, in their order) and
    /// "N more" for the rest of `count`.
    static func text(of pieces: [Piece], names: [String], count: Int) -> String {
        return pieces.map { piece -> String in
            switch piece {
            case .text(let text): return text
            case .app(let index): return index < names.count ? names[index] : ""
            case .more: return moreTitle(count - namedCount(forCount: count))
            }
        }.joined()
    }

    /// "Different in Safari, Figma and 3 more" for apps named `names` (all that count, in
    /// their order); nil for none.
    static func sentence(names: [String], locale: Locale = InterfaceList.locale) -> String? {
        guard !names.isEmpty else { return nil }
        return text(of: pieces(forCount: names.count, locale: locale), names: names, count: names.count)
    }

    // MARK: - Widths and rows

    /// How wide `text` is in the notes' font, a space at its end included: the next piece
    /// starts where this one ends.
    static func width(of text: String, font: NSFont = PreferencesGroupedForm.explanationFont) -> CGFloat {
        return NSAttributedString(string: text, attributes: [.font: font]).size().width
    }

    /// `name` whole, or its longest beginning with "…" that is at most `width` wide. (The
    /// whole name is in the link's tooltip and in what VoiceOver says.)
    static func name(_ name: String, cutTo width: CGFloat, font: NSFont = PreferencesGroupedForm.explanationFont) -> String {
        guard self.width(of: name, font: font) > width else { return name }
        let characters = Array(name)
        var shortest = 1, longest = characters.count - 1
        var fitting = "…"
        while shortest <= longest {
            let length = (shortest + longest) / 2
            let candidate = String(characters.prefix(length)).trimmingCharacters(in: .whitespaces) + "…"
            if self.width(of: candidate, font: font) <= width {
                fitting = candidate
                shortest = length + 1
            } else {
                longest = length - 1
            }
        }
        return fitting
    }

    /// The pieces of each row, for pieces `widths` wide in rows `lineWidth` wide: a row
    /// takes pieces while they fit and breaks only between two of them (a piece wider than
    /// a row stands alone in one).
    static func rows(widths: [CGFloat], lineWidth: CGFloat) -> [Range<Int>] {
        var rows: [Range<Int>] = []
        var start = 0
        var used: CGFloat = 0
        for (index, width) in widths.enumerated() {
            if index > start, used + width > lineWidth {
                rows.append(start..<index)
                start = index
                used = 0
            }
            used += width
        }
        if start < widths.count {
            rows.append(start..<widths.count)
        }
        return rows
    }
}

// MARK: - The view

/// "Different in Safari and Figma" under a pane's last view. See the file's header.
final class DifferentInAppsLine: NSView {

    enum Identifier {
        static let line = NSUserInterfaceItemIdentifier("differentInAppsLine")
        static let more = NSUserInterfaceItemIdentifier("differentInAppsMore")
    }

    /// The room of a row: the width of a pane's muted notes (460 pt).
    static let lineWidth = PreferencesGroupedForm.boxWidth(paneWidth: PreferencesWindowLayout.contentWidth)
        - 2 * PreferencesGroupedForm.rowHorizontalInset
    /// The widest a name gets; a longer one is cut at its end with "…".
    static let nameMaxWidth: CGFloat = 150
    /// An app's icon before its name (the Shortcut Ring pane), and the room between them.
    static let iconSize: CGFloat = 13
    static let iconSpacing: CGFloat = 3
    /// A label and a borderless button both draw their text this far inside their frames
    /// (a label's alignment rectangle leaves that margin out, a button's does not). The
    /// pieces are placed by their text, so the sentence runs as one.
    private static let textInset: CGFloat = 2

    /// A row's height: a line of the notes' font, as a label has it.
    static let rowHeight: CGFloat = {
        let probe = NSTextField(labelWithString: " ")
        probe.font = PreferencesGroupedForm.explanationFont
        return ceil(probe.intrinsicContentSize.height)
    }()

    /// The kind of settings the line is about: its pane's.
    let part: ApplicationPagePart
    /// Each name has its app's icon before it.
    let showsIcons: Bool
    private weak var pane: NSViewController?

    // MARK: What it shows (read access for tests)

    /// The apps that differ, as the line shows them now.
    private(set) var applications: [Application] = []
    /// The whole sentence, every name uncut; nil while no app differs.
    private(set) var sentence: String?
    /// The links of the apps named, in their order, and "N more".
    private(set) var nameButtons: [NSButton] = []
    private(set) var moreButton: NSButton?
    private(set) var iconViews: [NSImageView] = []
    private(set) var textLabels: [NSTextField] = []
    /// The rows the pieces take.
    private(set) var rowCount = 0

    /// The names of the apps named, as they were when the line was built.
    private var names: [String] = []
    private var height: NSLayoutConstraint!

    // MARK: - Lifecycle

    /// Puts the line of `part` under what `content` holds, as the last view of `pane`'s
    /// stack. It brings its own room above it and none while it is empty, so the stack
    /// keeps no spacing before it.
    @discardableResult
    static func add(
        to content: NSStackView, part: ApplicationPagePart, pane: NSViewController, showsIcons: Bool = false
    ) -> DifferentInAppsLine {
        let line = DifferentInAppsLine(part: part, pane: pane, showsIcons: showsIcons)
        let above = content.arrangedSubviews.last
        content.addArrangedSubview(line)
        line.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        if let above {
            content.setCustomSpacing(0, after: above)
        }
        line.refresh()
        return line
    }

    init(part: ApplicationPagePart, pane: NSViewController, showsIcons: Bool = false) {
        self.part = part
        self.pane = pane
        self.showsIcons = showsIcons
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        identifier = Identifier.line
        setAccessibilityRole(.group)
        setAccessibilityElement(false)
        height = heightAnchor.constraint(equalToConstant: 0)
        height.isActive = true
        // Edit › Undo or Redo of a change on an app's page can run while the pane shows.
        for name in [Notification.Name.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange] {
            NotificationCenter.default.addObserver(self, selector: #selector(undoDidRun(_:)), name: name, object: nil)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("DifferentInAppsLine is built in code")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// The pane comes on show: what an app's page changed meanwhile arrives here (that page
    /// shows only under Apps). The line is never hidden, also while it is empty: a stack
    /// takes a hidden view out, and a view that is out does not hear this.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let center = NotificationCenter.default
        center.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
        guard let window else { return }
        // "Smooth Scrolling in …" of the menu bar can change an app while the pane shows:
        // the line follows when its window is key again, as the Apps list does.
        center.addObserver(self, selector: #selector(windowDidBecomeKey(_:)), name: NSWindow.didBecomeKeyNotification, object: window)
        guard refresh() else { return }
        // The window's column lays the pane out as it shows it; a pane that stands alone
        // takes its new size here.
        if let pane, pane.isViewLoaded, !(pane.parent is PreferencesPaneHostViewController) {
            PreferencesForm.fitToContent(pane)
        }
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        refreshAndFit()
    }

    @objc private func undoDidRun(_ notification: Notification) {
        guard window != nil else { return }
        refreshAndFit()
    }

    private func refreshAndFit() {
        guard refresh(), let pane, pane.isViewLoaded else { return }
        PreferencesForm.fitToContent(pane)
    }

    // MARK: - Content

    /// Shows the apps that differ now. The views are made anew only when the apps, the
    /// names shown or their number differ from what the line shows; true when they did.
    @discardableResult
    func refresh() -> Bool {
        let applications = DifferentInApps.applications(for: part, among: ApplicationTriggerRule.storedApplications)
        let names = applications.prefix(DifferentInApps.namedCount(forCount: applications.count)).map { $0.getName() }
        let same = names == self.names && applications.count == self.applications.count
            && zip(applications, self.applications).allSatisfy { $0 === $1 }
        guard !same else { return false }
        self.applications = applications
        self.names = names
        rebuild()
        return true
    }

    private func rebuild() {
        // (The constraints that placed them go with them.)
        subviews.forEach { $0.removeFromSuperview() }
        nameButtons = []
        moreButton = nil
        iconViews = []
        textLabels = []
        let count = applications.count
        let pieces = DifferentInApps.pieces(forCount: count)
        guard !pieces.isEmpty else {
            sentence = nil
            rowCount = 0
            height.constant = 0
            setAccessibilityElement(false)
            setAccessibilityLabel(nil)
            return
        }
        let sentence = DifferentInApps.text(of: pieces, names: names, count: count)
        self.sentence = sentence
        // VoiceOver: a group that says the whole sentence, with the links in it.
        setAccessibilityElement(true)
        setAccessibilityLabel(sentence)

        /// A piece's views: its text (a label or a link) and, before a name, its icon.
        struct Placed {
            let text: NSView
            let icon: NSImageView?
            /// Where its text starts after the piece's start, and the whole piece's width.
            let textOffset: CGFloat
            let width: CGFloat
            let textWidth: CGFloat
        }
        var placed: [Placed] = []
        for piece in pieces {
            switch piece {
            case .text(let text):
                let label = makeText(text)
                textLabels.append(label)
                let width = DifferentInApps.width(of: text)
                placed.append(Placed(text: label, icon: nil, textOffset: 0, width: width, textWidth: width))
            case .app(let index):
                let name = index < names.count ? names[index] : ""
                let shown = DifferentInApps.name(name, cutTo: Self.nameMaxWidth)
                let destination = String(format: NSLocalizedString("buttons-show-in-app-part", comment: ""), name, part.title)
                let button = makeLink(shown, says: destination, help: sentence, action: #selector(showApplication(_:)))
                nameButtons.append(button)
                let icon = showsIcons && index < applications.count ? makeIcon(of: applications[index]) : nil
                if let icon {
                    iconViews.append(icon)
                }
                let offset = icon == nil ? 0 : Self.iconSize + Self.iconSpacing
                let width = DifferentInApps.width(of: shown)
                placed.append(Placed(text: button, icon: icon, textOffset: offset, width: offset + width, textWidth: width))
            case .more:
                let title = DifferentInApps.moreTitle(count - DifferentInApps.namedCount(forCount: count))
                let destination = NSLocalizedString("apps-different-show-apps", comment: "")
                let button = makeLink(title, says: destination, help: sentence, action: #selector(showApps(_:)))
                button.identifier = Identifier.more
                moreButton = button
                let width = DifferentInApps.width(of: title)
                placed.append(Placed(text: button, icon: nil, textOffset: 0, width: width, textWidth: width))
            }
        }

        let rows = DifferentInApps.rows(widths: placed.map(\.width), lineWidth: Self.lineWidth)
        rowCount = rows.count
        let inset = PreferencesGroupedForm.rowHorizontalInset
        let top = PreferencesGroupedForm.noteSpacing
        var constraints: [NSLayoutConstraint] = []
        for (row, range) in rows.enumerated() {
            var start: CGFloat = 0
            var first: NSView?
            for piece in placed[range] {
                addSubview(piece.text)
                let textStart = inset + start + piece.textOffset
                // (Constraints place alignment rectangles.)
                let before = Self.textInset - piece.text.alignmentRectInsets.left
                let after = Self.textInset - piece.text.alignmentRectInsets.right
                constraints += [
                    piece.text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: textStart - before),
                    piece.text.widthAnchor.constraint(equalToConstant: ceil(piece.textWidth) + before + after),
                ]
                if let first {
                    // One line of text: every piece of a row on the first one's baseline.
                    constraints.append(piece.text.firstBaselineAnchor.constraint(equalTo: first.firstBaselineAnchor))
                } else {
                    constraints.append(piece.text.topAnchor.constraint(equalTo: topAnchor, constant: top + CGFloat(row) * Self.rowHeight))
                    first = piece.text
                }
                if let icon = piece.icon {
                    addSubview(icon)
                    constraints += [
                        icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset + start),
                        icon.centerYAnchor.constraint(equalTo: piece.text.centerYAnchor),
                        icon.widthAnchor.constraint(equalToConstant: Self.iconSize),
                        icon.heightAnchor.constraint(equalToConstant: Self.iconSize),
                    ]
                }
                start += piece.width
            }
        }
        NSLayoutConstraint.activate(constraints)
        height.constant = top + CGFloat(rows.count) * Self.rowHeight
    }

    /// A plain piece of the sentence, in the muted notes' type. Not an element of its own:
    /// the group says the sentence.
    private func makeText(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = PreferencesGroupedForm.explanationFont
        label.textColor = PreferencesGroupedForm.explanationColor(enabled: true)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setAccessibilityElement(false)
        return label
    }

    /// A link of the sentence titled `title`. Its tooltip and VoiceOver say where it goes
    /// (`destination`, with a cut name whole), and VoiceOver's help the sentence it is in.
    private func makeLink(_ title: String, says destination: String, help: String, action: Selector) -> NSButton {
        let button = PreferencesForm.makeLinkButton(title: title, target: self, action: action)
        button.toolTip = destination
        button.setAccessibilityLabel(destination)
        button.setAccessibilityHelp(help)
        return button
    }

    /// An app's icon before its name: decoration, not read out.
    private func makeIcon(of application: Application) -> NSImageView {
        let icon = NSImageView()
        icon.image = application.getIcon()
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.setAccessibilityElement(false)
        return icon
    }

    // MARK: - Clicks

    /// A name: what a click on that app's mark in the Apps list does, its page on this
    /// part. The app's entry is looked up again (the same one, else the one stored under
    /// the same path); when it left the list meanwhile the line follows and nothing opens.
    @objc private func showApplication(_ sender: NSButton) {
        guard let index = nameButtons.firstIndex(of: sender), index < applications.count else { return }
        let shown = applications[index]
        let stored = ApplicationTriggerRule.storedApplications
        guard let entry = stored.first(where: { $0 === shown }) ?? stored.first(where: { $0.path == shown.path }) else {
            refreshAndFit()
            return
        }
        guard let pane else { return }
        PreferencesButtonsViewController.splitViewController(of: pane)?.bringForward(pageOf: entry, part: part)
    }

    /// "N more": the Apps list, whose marks say which apps they are.
    @objc private func showApps(_ sender: NSButton) {
        guard let pane else { return }
        PreferencesButtonsViewController.splitViewController(of: pane)?.selectPane(withIdentifier: PANEL_IDENTIFIER.application)
    }
}
