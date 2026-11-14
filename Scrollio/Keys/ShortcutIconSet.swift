//
//  ShortcutIconSet.swift
//  Scrollio
//
//  The icons a recorded key combination can be given (`ShortcutLabel.Icon`): a chosen set
//  of SF Symbols in a few groups, for the choice in the recorder's popover, and how an
//  icon is drawn small (a row's pull-down, the popover's own button).
//
//  The set is a choice, not a catalogue: what a keyboard shortcut of an app usually does
//  (go back, reload, copy, save, zoom, play, send, build, hide …). Every name in it is an
//  SF Symbol that macOS 14 has (a test asks the Mac it runs on for each; that Mac runs a
//  newer macOS, so 14 itself is not asked).
//  Anything else is the one character the user types instead. A stored symbol does not
//  have to be in the set: a file may name another, and it is shown if this Mac has it.
//

import Cocoa

enum ShortcutIconSet {

    struct Symbol: Equatable {
        /// The SF Symbol's name, which is also what is stored.
        let name: String
        /// More words the search finds it by, beside the words of its name.
        let words: String

        /// The name as it is read out and shown as a tool tip: "arrow clockwise".
        var spokenName: String {
            return name.replacingOccurrences(of: ".", with: " ")
        }

        /// Whether every word of `query` begins a word of the symbol's name or of its
        /// extra words. An empty query matches everything.
        func matches(_ query: String) -> Bool {
            let wanted = query.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            guard !wanted.isEmpty else { return true }
            let own = (spokenName + " " + words).lowercased().split(separator: " ")
            return wanted.allSatisfy { word in own.contains { $0.hasPrefix(word) } }
        }
    }

    struct Group: Equatable {
        /// The catalog key of the group's name.
        let titleKey: String
        let symbols: [Symbol]

        var title: String {
            return NSLocalizedString(titleKey, comment: "")
        }
    }

    private static func group(_ titleKey: String, _ symbols: [(String, String)]) -> Group {
        return Group(titleKey: titleKey, symbols: symbols.map { Symbol(name: $0.0, words: $0.1) })
    }

    /// Six groups, each a whole number of rows of the chooser's eight columns (16 or 24),
    /// "Common" first: what a shortcut most often does. No symbol stands in two groups.
    static let groups: [Group] = [
        group("key-recorder-icon-group-common", [
            ("arrow.clockwise", "reload refresh redo"), ("arrow.uturn.backward", "undo back"),
            ("arrow.uturn.forward", "redo"), ("square.and.arrow.up", "share export"),
            ("magnifyingglass", "search find"), ("sidebar.left", "panel navigator"),
            ("plus.rectangle.on.rectangle", "new tab window"), ("xmark", "close cancel"),
            ("square.and.arrow.down", "save import download"), ("playpause", "play pause toggle"),
            ("speaker.slash", "mute silence"), ("lock", "private secure"), ("star", "favourite favorite rate"),
            ("trash", "delete remove bin"), ("doc.on.doc", "copy duplicate"), ("gearshape", "settings preferences"),
        ]),
        group("key-recorder-icon-group-arrows", [
            ("arrow.left", "back previous"), ("arrow.right", "forward next"), ("arrow.up", "top"), ("arrow.down", "bottom"),
            ("chevron.left", "back previous"), ("chevron.right", "forward next"),
            ("arrow.counterclockwise", "revert undo"), ("arrow.triangle.2.circlepath", "sync refresh update"),
            ("arrow.left.arrow.right", "swap switch"), ("arrow.up.arrow.down", "sort swap"),
            ("arrow.up.left.and.arrow.down.right", "full screen expand enlarge"),
            ("arrow.down.right.and.arrow.up.left", "shrink collapse exit"), ("arrowshape.turn.up.left", "reply"),
            ("arrowshape.turn.up.right", "forward share"), ("arrow.up.to.line", "top beginning start"),
            ("return", "enter newline"),
        ]),
        group("key-recorder-icon-group-editing", [
            ("pencil", "edit rename write"), ("square.and.pencil", "compose new edit"), ("scissors", "cut"),
            ("doc.on.clipboard", "paste"), ("plus", "add new"), ("minus", "remove"),
            ("checkmark", "done accept confirm"), ("square.dashed", "select selection marquee"),
            ("bold", "strong"), ("italic", "emphasis"), ("underline", ""), ("strikethrough", ""),
            ("list.bullet", "list"), ("text.alignleft", "align paragraph"), ("highlighter", "mark highlight"),
            ("wand.and.stars", "magic auto fix"),
        ]),
        group("key-recorder-icon-group-files", [
            ("doc", "file document new"), ("folder", "open directory"), ("printer", "print"),
            ("plus.magnifyingglass", "zoom in"), ("minus.magnifyingglass", "zoom out"), ("link", "url"),
            ("paperclip", "attach"), ("bookmark", "favourite favorite"), ("tag", "label"), ("macwindow", "window"),
            ("sidebar.right", "inspector panel"), ("rectangle.split.2x1", "split columns"),
            ("square.grid.2x2", "grid overview"), ("rectangle.on.rectangle", "windows tabs"),
            ("eye", "show preview view"), ("eye.slash", "hide"),
        ]),
        group("key-recorder-icon-group-media", [
            ("play", "start run"), ("pause", ""), ("stop", ""), ("backward", "rewind previous"),
            ("forward", "next skip"), ("record.circle", "record"), ("speaker.wave.2", "volume sound audio"),
            ("music.note", "song"), ("mic", "microphone"), ("mic.slash", "mute microphone"),
            ("video", "camera call"), ("video.slash", "camera off"), ("camera", "photo screenshot capture"),
            ("photo", "image picture"), ("envelope", "mail email"), ("paperplane", "send"),
            ("bubble.left", "message chat comment"), ("phone", "call"), ("bell", "notification alert"),
            ("bell.slash", "mute silence do not disturb"), ("person", "user account contact"),
            ("person.2", "people team share"), ("at", "mention"), ("hand.raised", "stop raise"),
        ]),
        group("key-recorder-icon-group-tools", [
            ("slider.horizontal.3", "adjust filter controls"), ("terminal", "console shell command"),
            ("chevron.left.forwardslash.chevron.right", "code source"), ("hammer", "build"),
            ("wrench.and.screwdriver", "tools fix"), ("ladybug", "bug debug"), ("command", "key"), ("keyboard", "keys"),
            ("bolt", "quick action run"), ("power", "off quit"), ("moon", "dark night"), ("lightbulb", "idea hint"),
            ("sparkles", "new ai magic"), ("calendar", "date event"), ("clock", "time history recent"),
            ("globe", "web browser language"),
        ]),
    ]

    /// Every symbol of the set, in the order of the groups.
    static var all: [Symbol] {
        return groups.flatMap { $0.symbols }
    }

    /// The groups with only the symbols `query` finds; groups without any are left out.
    static func groups(matching query: String) -> [Group] {
        return groups.compactMap { group in
            let found = group.symbols.filter { $0.matches(query) }
            return found.isEmpty ? nil : Group(titleKey: group.titleKey, symbols: found)
        }
    }

    // MARK: Drawing an icon small

    /// `icon` as a picture `side` points high, for a row's pull-down or a button: the
    /// symbol, or the typed character in `ink` (the label colour; an emoji in its own
    /// colours). Nil for a symbol this Mac does not have.
    static func image(of icon: ShortcutLabel.Icon, side: CGFloat = 16, ink: NSColor = .labelColor) -> NSImage? {
        switch icon {
        case .symbol(let name):
            guard ShortcutRingFace.hasSymbol(named: name) else { return nil }
            return NSImage(systemSymbolName: name, accessibilityDescription: nil)
        case .character(let text):
            let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
                var size = side * 0.82
                var string = NSAttributedString()
                // (A wide character, an emoji with a long sequence, is made to fit.)
                for _ in 0..<2 {
                    string = NSAttributedString(string: text, attributes: [
                        .font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: ink,
                    ])
                    let width = string.size().width
                    guard width > rect.width, width > 0 else { break }
                    size *= rect.width / width
                }
                let measured = string.size()
                string.draw(at: NSPoint(x: rect.midX - measured.width / 2, y: rect.midY - measured.height / 2))
                return true
            }
            return image
        }
    }
}
