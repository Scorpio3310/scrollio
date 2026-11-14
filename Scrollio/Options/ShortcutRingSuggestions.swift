//
//  ShortcutRingSuggestions.swift
//  Scrollio
//
//  The Shortcut Ring suggested for popular apps: for each, the app's most used shortcuts on
//  the eight places, from `ShortcutRingSuggestions.json` beside this file (made from the
//  researched presets; no notes, no sources in it).
//
//  Nothing is filled by itself. A suggestion is used only when the user turns off "Use the
//  general ring" on the page of an app that has one and never had a ring of its own (its
//  ring starts with the suggestion instead of a copy of the general ring), and when the
//  user clicks "Use Suggested Shortcuts" there. What it fills in are ordinary places: a
//  listed action (Undo, Copy … where the suggestion is exactly that action) or a recorded
//  key combination with the suggestion's name and symbol as its label. So the settings
//  file, Undo and older versions read them as any other place.
//
//  An app is found by the bundle identifier of its entry's app, read from the bundle's
//  Info.plist when the page asks (never in the event path): one of the app's identifiers,
//  case aside, or else the longest of its prefixes (versioned identifiers:
//  "com.autodesk.AutoCAD2026").
//
//  The keys: a suggestion stores what a shortcut is on a US keyboard (the unshifted
//  character of its key, or a named key, and its modifiers). When it fills a ring, each
//  becomes the key that types that character on the keyboard layout in use
//  (`KeyboardLayoutLayers`): on QWERTZ ⌘Z is the US Y key and stays Undo. A shortcut whose
//  character the layout types only with Option ("[" on German) takes the layout-free
//  alternative the suggestion names (Back and Forward of the browsers: Scrollio's own
//  Back and Forward), else its place stays empty.
//
//  Resource format (`scrollio-ring-suggestions`, version 1):
//
//      {"format": "scrollio-ring-suggestions", "version": 1, "apps": [
//        {"name": "Figma", "bundleIdentifiers": ["com.figma.Desktop"],
//         "bundleIdentifierPrefixes": [...],                 (optional)
//         "places": [                                        (eight, clockwise from the top)
//           {"name": "Zoom In", "symbol": "plus.magnifyingglass", "character": "=",
//            "modifiers": ["command"], "modifierless": false,
//            "alternative": {"action": "navigateBack"} | {"character": "left", "modifiers": [...]}},
//           {"empty": "why the place is left empty"}, …]}]}
//

import Cocoa

/// The ring suggested for one app.
struct ShortcutRingSuggestion: Equatable {

    /// A shortcut as a US keyboard has it.
    struct Keys: Equatable {
        /// The unshifted character of the US key ("z", "=", "[") or a named key
        /// (`namedKeys`: "left", "space", "keypad-0" …).
        let character: String
        /// Control, Option, Shift and Command, Shift where the US shortcut needs it.
        let modifiers: CGEventFlags

        /// The named keys a suggestion may use, and the marks of a real press of them that
        /// a recorded combination keeps ("fn" for the arrows, the page keys and the F-keys).
        static let namedKeys: [String: (code: CGKeyCode, flags: CGEventFlags)] = [
            "up": (126, .maskSecondaryFn), "down": (125, .maskSecondaryFn),
            "left": (123, .maskSecondaryFn), "right": (124, .maskSecondaryFn),
            "home": (115, .maskSecondaryFn), "end": (119, .maskSecondaryFn),
            "pageup": (116, .maskSecondaryFn), "pagedown": (121, .maskSecondaryFn),
            "f6": (97, .maskSecondaryFn),
            "delete": (51, []), "return": (36, []), "tab": (48, []), "space": (49, []), "escape": (53, []),
            "keypad-decimal": (65, []), "keypad-0": (82, []), "keypad-divide": (75, []),
        ]

        static let modifierNames: [String: CGEventFlags] = [
            "control": .maskControl, "option": .maskAlternate, "shift": .maskShift, "command": .maskCommand,
        ]

        /// The key and modifiers that send this shortcut on `layout`; nil when the layout
        /// types its character only with Option, or not at all.
        func combination(on layout: KeyboardLayoutLayers) -> (code: CGKeyCode, modifiers: CGEventFlags)? {
            if let named = Self.namedKeys[character] {
                return (named.code, modifiers.union(named.flags))
            }
            return layout.key(for: character, modifiers: modifiers)
        }

        /// The key of this shortcut on a US keyboard.
        var usKeyCode: CGKeyCode? {
            return Self.namedKeys[character]?.code ?? KeyboardLayoutLayers.us.key(for: character, modifiers: [])?.code
        }
    }

    /// What a place falls back to where its character needs Option.
    enum Alternative: Equatable {
        /// One of Scrollio's listed actions (Back, Forward).
        case listed(SystemShortcut.Shortcut)
        /// Other keys, under the place's name and symbol.
        case keys(Keys)
    }

    struct Place: Equatable {
        /// What the place is called (at most `ShortcutLabel.maximumNameLength`).
        let name: String
        /// An SF Symbol.
        let symbol: String
        let keys: Keys
        /// A key without any modifier (only in apps whose canvas takes such keys).
        let modifierless: Bool
        let alternative: Alternative?
    }

    enum Slot: Equatable {
        case place(Place)
        /// Left empty on purpose, and why.
        case empty(reason: String)

        var place: Place? {
            if case .place(let place) = self { return place }
            return nil
        }
    }

    /// The app's name in the research (for the tests; the page names the app by its entry).
    let appName: String
    let bundleIdentifiers: [String]
    let bundleIdentifierPrefixes: [String]
    /// `ShortcutRingSettings.placeCount` slots, clockwise from the top.
    let slots: [Slot]

    // MARK: - Filling a ring

    /// The ring's places on `layout`: each suggested shortcut as a place of the ring.
    func places(on layout: KeyboardLayoutLayers) -> [ShortcutRingPlace] {
        return ShortcutRingSettings.filledUp(slots.map { slot in
            guard let place = slot.place else { return .empty }
            return Self.ringPlace(for: place, on: layout)
        })
    }

    /// How many suggested places `places` (this suggestion's places on a layout) leaves
    /// empty: the layout cannot type their keys and they have no alternative there.
    /// (Places the suggestion leaves empty on purpose are not counted.)
    func placesLeftEmpty(in places: [ShortcutRingPlace]) -> Int {
        return zip(slots, places).filter { $0.place != nil && $1 == .empty }.count
    }

    /// A suggested shortcut as a place: the listed action it is exactly (Undo, Copy …:
    /// the same name, symbol, US key and modifiers), sent with the layout's key when it
    /// runs; else the key combination that sends it on `layout`, named and with its
    /// symbol; else its alternative; else nothing.
    static func ringPlace(for place: Place, on layout: KeyboardLayoutLayers) -> ShortcutRingPlace {
        if let listed = listedAction(matching: place) {
            return ShortcutRingPlace(listed)
        }
        if let keys = place.keys.combination(on: layout) {
            return recorded(keys, named: place)
        }
        switch place.alternative {
        case .listed(let shortcut)?:
            return ShortcutRingPlace(shortcut)
        case .keys(let alternative)?:
            guard let keys = alternative.combination(on: layout) else { return .empty }
            return recorded(keys, named: place)
        case nil:
            return .empty
        }
    }

    /// The listed actions a suggested place can be: those apps share under one name.
    static let listedCandidates: [SystemShortcut.Shortcut] = [
        SystemShortcut.undo, SystemShortcut.redo, SystemShortcut.copy, SystemShortcut.paste, SystemShortcut.cut,
        SystemShortcut.bold, SystemShortcut.italic, SystemShortcut.underline, SystemShortcut.selectAll,
        SystemShortcut.moveToTrash, SystemShortcut.newFolder, SystemShortcut.nextTab, SystemShortcut.previousTab,
    ]

    static func listedAction(matching place: Place) -> SystemShortcut.Shortcut? {
        guard let code = place.keys.usKeyCode else { return nil }
        let modifiers = UInt64(place.keys.modifiers.rawValue)
        return listedCandidates.first { shortcut in
            shortcut.code == code && UInt64(shortcut.modifiers.rawValue) == modifiers
                && shortcut.localizedName == place.name && shortcut.symbolName == place.symbol
        }
    }

    private static func recorded(_ keys: (code: CGKeyCode, modifiers: CGEventFlags), named place: Place) -> ShortcutRingPlace {
        let action = ButtonBinding.normalizedCustomBindingName(code: keys.code, modifiers: keys.modifiers.rawValue)
        return ShortcutRingPlace(action: action, label: ShortcutLabel(name: place.name, icon: .symbol(place.symbol)))
    }
}

// MARK: - The catalog

enum ShortcutRingSuggestions {

    static let resourceName = "ShortcutRingSuggestions"

    /// The suggestions that ship with the app, read once; none when the file is missing or
    /// damaged (then no app has a suggestion and every switch copies the general ring).
    static let shipped: Catalog = {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return Catalog(apps: []) }
        return (try? Catalog.read(data)) ?? Catalog(apps: [])
    }()

    struct Catalog: Equatable {
        let apps: [ShortcutRingSuggestion]

        /// The suggestion for the app with `bundleIdentifier`: one whose identifiers hold it
        /// (case aside), else the one with the longest prefix of it.
        func suggestion(forBundleIdentifier bundleIdentifier: String) -> ShortcutRingSuggestion? {
            let wanted = bundleIdentifier.lowercased()
            guard !wanted.isEmpty else { return nil }
            if let exact = apps.first(where: { $0.bundleIdentifiers.contains { $0.lowercased() == wanted } }) {
                return exact
            }
            var best: (suggestion: ShortcutRingSuggestion, length: Int)?
            for app in apps {
                for prefix in app.bundleIdentifierPrefixes {
                    let lowered = prefix.lowercased()
                    guard wanted.count > lowered.count, wanted.hasPrefix(lowered),
                          lowered.count > (best?.length ?? 0) else { continue }
                    best = (app, lowered.count)
                }
            }
            return best?.suggestion
        }

        static func read(_ data: Data) throws -> Catalog {
            let file = try JSONDecoder().decode(File.self, from: data)
            guard file.format == "scrollio-ring-suggestions", file.version == 1 else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Not a suggestions file"))
            }
            return Catalog(apps: file.apps.map(\.suggestion))
        }
    }

    // MARK: - An app's suggestion

    /// The bundle identifier of the app stored at `path` (its bundle, or the program inside
    /// it). The seam: tests give fixture apps an identifier.
    static var bundleIdentifierOfApplication: (String) -> String? = { bundleIdentifier(ofApplicationAt: $0) }

    /// The layout a fill resolves the keys on: the one in use; the US layout under XCTest
    /// (tests that are about a layout set one) and when none can be read.
    static var layout: () -> KeyboardLayoutLayers = {
        guard !AppRuntime.isRunningXCTest else { return .us }
        return KeyboardLayoutLayers.current() ?? .us
    }

    /// The suggestion for the app of `application`'s entry, if it has one.
    static func suggestion(for application: Application, in catalog: Catalog = shipped) -> ShortcutRingSuggestion? {
        guard let identifier = bundleIdentifierOfApplication(application.path) else { return nil }
        return catalog.suggestion(forBundleIdentifier: identifier)
    }

    /// The bundle's identifier from its Info.plist, read now (Launch Services and
    /// `Bundle` keep what they read once). Nil for a program outside a bundle.
    static func bundleIdentifier(ofApplicationAt path: String) -> String? {
        var bundlePath = path
        if let range = path.range(of: ".app/Contents/", options: .backwards) {
            bundlePath = String(path[..<path.index(range.lowerBound, offsetBy: 4)])
        }
        guard bundlePath.hasSuffix(".app") else { return nil }
        let info = URL(fileURLWithPath: bundlePath).appendingPathComponent("Contents/Info.plist")
        guard let plist = NSDictionary(contentsOf: info),
              let identifier = plist["CFBundleIdentifier"] as? String, !identifier.isEmpty else { return nil }
        return identifier
    }

    // MARK: - Reading the file

    private struct File: Decodable {
        let format: String
        let version: Int
        let apps: [App]
    }

    private struct App: Decodable {
        let name: String
        let bundleIdentifiers: [String]
        let bundleIdentifierPrefixes: [String]?
        let places: [StoredSlot]

        var suggestion: ShortcutRingSuggestion {
            return ShortcutRingSuggestion(
                appName: name, bundleIdentifiers: bundleIdentifiers,
                bundleIdentifierPrefixes: bundleIdentifierPrefixes ?? [], slots: places.map(\.slot)
            )
        }
    }

    private struct StoredKeys: Decodable {
        let character: String
        let modifiers: [String]

        func keys() throws -> ShortcutRingSuggestion.Keys {
            var flags: CGEventFlags = []
            for name in modifiers {
                guard let flag = ShortcutRingSuggestion.Keys.modifierNames[name] else {
                    throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unknown modifier \(name)"))
                }
                flags.insert(flag)
            }
            return ShortcutRingSuggestion.Keys(character: character, modifiers: flags)
        }
    }

    private struct StoredSlot: Decodable {
        let slot: ShortcutRingSuggestion.Slot

        private enum CodingKeys: String, CodingKey {
            case empty, name, symbol, character, modifiers, modifierless, alternative
        }

        private enum AlternativeKeys: String, CodingKey {
            case action, character, modifiers
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let reason = try c.decodeIfPresent(String.self, forKey: .empty) {
                slot = .empty(reason: reason)
                return
            }
            let keys = try StoredKeys(
                character: c.decode(String.self, forKey: .character),
                modifiers: c.decode([String].self, forKey: .modifiers)
            ).keys()
            var alternative: ShortcutRingSuggestion.Alternative?
            if c.contains(.alternative) {
                let a = try c.nestedContainer(keyedBy: AlternativeKeys.self, forKey: .alternative)
                if let action = try a.decodeIfPresent(String.self, forKey: .action) {
                    guard let shortcut = ShortcutRingPlace.shortcut(named: action) else {
                        throw DecodingError.dataCorruptedError(forKey: .action, in: a, debugDescription: "Unknown action")
                    }
                    alternative = .listed(shortcut)
                } else {
                    alternative = .keys(try StoredKeys(
                        character: a.decode(String.self, forKey: .character),
                        modifiers: a.decode([String].self, forKey: .modifiers)
                    ).keys())
                }
            }
            slot = .place(ShortcutRingSuggestion.Place(
                name: try c.decode(String.self, forKey: .name),
                symbol: try c.decode(String.self, forKey: .symbol),
                keys: keys,
                modifierless: try c.decode(Bool.self, forKey: .modifierless),
                alternative: alternative
            ))
        }
    }
}

// MARK: - The app's ring from its suggestion

extension Application {

    /// The places the app's suggested shortcuts give on the layout in use; nil for an app
    /// without a suggestion. Reads the app's bundle and the layout: Settings only.
    func suggestedRingPlaces(in catalog: ShortcutRingSuggestions.Catalog = ShortcutRingSuggestions.shipped) -> [ShortcutRingPlace]? {
        return ShortcutRingSuggestions.suggestion(for: self, in: catalog)?.places(on: ShortcutRingSuggestions.layout())
    }
}
