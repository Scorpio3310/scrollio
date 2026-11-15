//
//  ShortcutRingSuggestionsTests.swift
//  ScrollioTests
//
//  The Shortcut Ring suggested for popular apps (`ShortcutRingSuggestions`): the shipped
//  file and what is in it, finding an app by its bundle identifier, the keys a suggestion
//  becomes on the US layout and on layouts where letters and signs sit elsewhere, the
//  safety rules over the whole file and the lead's decisions on the second fifty, the
//  switch "Use the general ring", "Reset to Defaults" with its Undo and the Suggested
//  row's line on an app's page, that nothing is filled or added without the user, and a
//  filled ring in a settings file.
//
//  The apps need not be on this Mac: entries get their bundle identifier through
//  `ShortcutRingSuggestions.bundleIdentifierOfApplication`. Layouts the system has are
//  read with TISCreateInputSourceList (a test skips when one is missing). Nothing is shown
//  and nothing is sent.
//

import Carbon.HIToolbox
import XCTest
@testable import Scrollio_Debug

/// What the tests share: fixture apps with bundle identifiers, the system's layouts.
enum SuggestionFixtures {

    static let figmaPath = "/Applications/Figma.app"
    static let safariPath = "/Applications/Safari.app"
    static let calculatorPath = "/System/Applications/Calculator.app"
    static let finderPath = "/System/Library/CoreServices/Finder.app"
    static let lightroomPath = "/Applications/Adobe Lightroom Classic/Adobe Lightroom Classic.app"

    static let identifiers: [String: String] = [
        figmaPath: "com.figma.Desktop",
        finderPath: "com.apple.finder",
        lightroomPath: "com.adobe.LightroomClassicCC7",
        safariPath: "com.apple.Safari",
        "/Applications/Adobe Photoshop 2026/Adobe Photoshop 2026.app": "com.adobe.Photoshop",
        "/Applications/Microsoft Word.app": "com.microsoft.Word",
        "/Applications/Final Cut Pro.app": "com.apple.FinalCut",
        calculatorPath: "com.apple.calculator",
    ]

    /// Gives the fixture apps their identifiers until the test ends.
    static func install(for test: XCTestCase) {
        let savedIdentifier = ShortcutRingSuggestions.bundleIdentifierOfApplication
        let savedLayout = ShortcutRingSuggestions.layout
        ShortcutRingSuggestions.bundleIdentifierOfApplication = { identifiers[$0] }
        ShortcutRingSuggestions.layout = { .us }
        test.addTeardownBlock {
            ShortcutRingSuggestions.bundleIdentifierOfApplication = savedIdentifier
            ShortcutRingSuggestions.layout = savedLayout
        }
    }

    /// A keyboard layout of this Mac's system by its input source id; the test is skipped
    /// when the system does not have it.
    static func layout(_ id: String) throws -> KeyboardLayoutLayers {
        guard let source = inputSource(id), let layers = KeyboardLayoutLayers.of(source) else {
            throw XCTSkip("\(id) is not on this Mac")
        }
        return layers
    }

    static func inputSource(_ id: String) -> TISInputSource? {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] else { return nil }
        return list.first
    }

    static func app(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws -> ShortcutRingSuggestion {
        return try XCTUnwrap(ShortcutRingSuggestions.shipped.apps.first { $0.appName == name }, name, file: file, line: line)
    }

    static func place(_ name: String, of app: String, file: StaticString = #filePath, line: UInt = #line) throws -> ShortcutRingSuggestion.Place {
        let suggestion = try self.app(app, file: file, line: line)
        return try XCTUnwrap(suggestion.slots.compactMap(\.place).first { $0.name == name }, "\(app): \(name)", file: file, line: line)
    }
}

// MARK: - The file

final class ShortcutRingSuggestionsFileTests: XCTestCase {

    private var catalog: ShortcutRingSuggestions.Catalog { ShortcutRingSuggestions.shipped }

    /// The app carries the file, and it reads: a hundred apps, eight places each, a place
    /// left empty only with its reason (for safety, or because its key is a guess); names
    /// fit a label, symbols are on this Mac, keys are one character or a named key.
    func testTheShippedFileReadsWithAHundredAppsOfEightPlaces() throws {
        XCTAssertEqual(catalog.apps.count, 100)
        XCTAssertEqual(Set(catalog.apps.map(\.appName)).count, 100)
        var empty: [String] = []
        for app in catalog.apps {
            XCTAssertEqual(app.slots.count, ShortcutRingSettings.placeCount, app.appName)
            XCTAssertFalse(app.bundleIdentifiers.isEmpty, app.appName)
            for (index, slot) in app.slots.enumerated() {
                switch slot {
                case .empty(let reason):
                    XCTAssertFalse(reason.isEmpty)
                    empty.append("\(app.appName) \(ShortcutRingPlaceName.key(of: index))")
                case .place(let place):
                    let what = "\(app.appName): \(place.name)"
                    XCTAssertLessThanOrEqual(place.name.count, ShortcutLabel.maximumNameLength, what)
                    XCTAssertEqual(ShortcutLabel(name: place.name, icon: .symbol(place.symbol))?.name, place.name, what)
                    XCTAssertNotNil(ShortcutLabel.cleaned(.symbol(place.symbol)), what)
                    XCTAssertNotNil(NSImage(systemSymbolName: place.symbol, accessibilityDescription: nil), what)
                    XCTAssertTrue(
                        ShortcutRingSuggestion.Keys.namedKeys[place.keys.character] != nil || place.keys.character.count == 1, what
                    )
                    // Without a modifier: none, or Shift where US types the sign with it
                    // (GIMP's "+", which is Shift and "=" on US and a key of its own on
                    // many layouts, where the fill sends it without Shift).
                    let character = place.keys.character
                    let usShifted = place.keys.modifiers == .maskShift && KeyboardLayoutLayers.usShifted[character] != nil
                    XCTAssertEqual(place.modifierless, place.keys.modifiers.isEmpty || usShifted, what)
                }
            }
        }
        XCTAssertEqual(empty, [
            "iMovie ring-place-top", "iMovie ring-place-bottom",
            "Mail ring-place-right", "Mail ring-place-bottom", "Mail ring-place-left",
            "Microsoft Copilot ring-place-top", "Microsoft Copilot ring-place-top-right",
            "Microsoft Copilot ring-place-bottom", "Microsoft Copilot ring-place-top-left",
            "Microsoft Outlook ring-place-bottom",
            "Perplexity ring-place-top", "Perplexity ring-place-top-right", "Perplexity ring-place-bottom",
            "Perplexity ring-place-top-left",
            "WhatsApp ring-place-top", "WhatsApp ring-place-right", "WhatsApp ring-place-bottom", "WhatsApp ring-place-left",
        ])
        let gimp = try SuggestionFixtures.place("Zoom In", of: "GIMP")
        XCTAssertTrue(gimp.modifierless)
        XCTAssertEqual(gimp.keys, ShortcutRingSuggestion.Keys(character: "=", modifiers: .maskShift))
    }

    /// Every suggested name stands whole in the middle of the ring when its place lights,
    /// on screen and in the pane: at the size `namedTitleLayout` gives a name with its keys
    /// under it, it takes at most two lines, so nothing is cut ("Paste Unformatted Text"
    /// needed three and was cut to "Paste / Unformatted T…").
    func testEverySuggestedNameStandsWholeInTheMiddleOfTheRing() {
        for scale in [CGFloat(1), ShortcutRingPreviewView.ringScale] {
            let width = ShortcutRingArtwork.titleWidth * scale
            let size = ShortcutRingArtwork.titleFont.pointSize * scale
            for app in catalog.apps {
                for place in app.slots.compactMap(\.place) {
                    let layout = ShortcutRingArtwork.namedTitleLayout(place.name, keys: "⌥⇧⌘V", width: width, pointSize: size)
                    let lines = ShortcutRingArtwork.titleLines(place.name, width: width, pointSize: layout.namePointSize).lines
                    XCTAssertLessThanOrEqual(lines, 2, "\(app.appName): \(place.name), scale \(scale)")
                }
            }
        }
        XCTAssertEqual(try SuggestionFixtures.place("Paste as Plain Text", of: "LibreOffice").keys.modifiers, [.maskAlternate, .maskShift, .maskCommand])
    }

    /// Every bundle identifier names one app, case aside, and no app's prefix takes an
    /// identifier of another: Android Studio is found as itself, no longer as IntelliJ
    /// IDEA (whose ring is the same, place for place).
    func testEveryBundleIdentifierNamesOneApp() throws {
        let identifiers = catalog.apps.flatMap { $0.bundleIdentifiers.map { $0.lowercased() } }
        XCTAssertEqual(Set(identifiers).count, identifiers.count, "every bundle identifier names one app")
        for app in catalog.apps {
            for identifier in app.bundleIdentifiers {
                XCTAssertEqual(catalog.suggestion(forBundleIdentifier: identifier)?.appName, app.appName, identifier)
            }
        }
        XCTAssertEqual(catalog.suggestion(forBundleIdentifier: "com.google.android.studio")?.appName, "Android Studio")
        let intellij = try SuggestionFixtures.app("IntelliJ IDEA (and other JetBrains IDEs)")
        XCTAssertFalse(intellij.bundleIdentifiers.contains("com.google.android.studio"))
        XCTAssertEqual(try SuggestionFixtures.app("Android Studio").slots, intellij.slots)
    }

    /// Every symbol of the file came with macOS 14 or earlier (the deployment target), by
    /// the system's own table of when each SF Symbol came; a newer one would be blank there.
    func testEverySymbolIsOnMacOS14() throws {
        let url = URL(fileURLWithPath: "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_availability.plist")
        guard let table = NSDictionary(contentsOf: url),
              let symbols = table["symbols"] as? [String: String],
              let releases = table["year_to_release"] as? [String: [String: String]] else {
            throw XCTSkip("the system's table of SF Symbols is not there")
        }
        let macOS14 = OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0)
        func version(_ text: String) -> OperatingSystemVersion {
            let parts = text.split(separator: ".").compactMap { Int($0) }
            return OperatingSystemVersion(
                majorVersion: parts.first ?? 99, minorVersion: parts.count > 1 ? parts[1] : 0, patchVersion: 0
            )
        }
        let names = Set(catalog.apps.flatMap { $0.slots.compactMap(\.place).map(\.symbol) })
        XCTAssertGreaterThan(names.count, 100)
        for name in names.sorted() {
            guard let year = symbols[name], let mac = releases[year]?["macOS"] else {
                XCTFail("\(name) is not in the system's table")
                continue
            }
            let came = version(mac)
            XCTAssertTrue((came.majorVersion, came.minorVersion) <= (macOS14.majorVersion, macOS14.minorVersion), "\(name) came with macOS \(mac)")
        }
    }

    /// What ships is the suggestion and nothing of the research behind it.
    func testTheFileHoldsNoResearch() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: ShortcutRingSuggestions.resourceName, withExtension: "json"))
        let text = try String(contentsOf: url, encoding: .utf8)
        for word in ["http", "source", "confidence", "notes", "\"keys\"", "layoutSensitive"] {
            XCTAssertFalse(text.contains(word), word)
        }
        XCTAssertEqual(try ShortcutRingSuggestions.Catalog.read(Data(text.utf8)), catalog)
        XCTAssertThrowsError(try ShortcutRingSuggestions.Catalog.read(Data(#"{"format":"other","version":1,"apps":[]}"#.utf8)))
    }

    /// An app is found by one of its bundle identifiers, case aside; one with a version in
    /// its identifier by its prefix; nothing else is found.
    func testAnAppIsFoundByItsBundleIdentifierAndVersionedOnesByPrefix() {
        func name(_ identifier: String) -> String? {
            return catalog.suggestion(forBundleIdentifier: identifier)?.appName
        }
        XCTAssertEqual(name("com.figma.Desktop"), "Figma")
        XCTAssertEqual(name("COM.FIGMA.DESKTOP"), "Figma")
        XCTAssertEqual(name("com.google.Chrome.canary"), "Google Chrome")
        XCTAssertEqual(name("com.apple.FinalCutTrial"), "Final Cut Pro")
        XCTAssertEqual(name("com.autodesk.AutoCAD2031"), "AutoCAD for Mac")
        XCTAssertEqual(name("com.adobe.PremierePro.27"), "Adobe Premiere Pro")
        XCTAssertEqual(name("com.sketchup.SketchUp.2030"), "SketchUp")
        XCTAssertNil(name("com.adobe.PremiereProHeadless"))
        XCTAssertNil(name("com.sketchup.SketchUp."), "a prefix alone is no app")
        XCTAssertNil(name("com.figma"), "a part of an identifier is no match")
        XCTAssertNil(name("com.openai.chat"), "ChatGPT Classic is not the app researched")
        XCTAssertNil(name("com.apple.calculator"))
        XCTAssertNil(name(""))
    }

    /// The identifier comes from the bundle's Info.plist, for an entry stored by the
    /// bundle or by the program inside it; a program outside a bundle has none.
    func testTheBundleIdentifierIsReadFromTheAppsBundle() {
        XCTAssertEqual(ShortcutRingSuggestions.bundleIdentifier(ofApplicationAt: "/System/Applications/Calculator.app"), "com.apple.calculator")
        XCTAssertEqual(
            ShortcutRingSuggestions.bundleIdentifier(ofApplicationAt: "/System/Applications/Calculator.app/Contents/MacOS/Calculator"),
            "com.apple.calculator"
        )
        XCTAssertNil(ShortcutRingSuggestions.bundleIdentifier(ofApplicationAt: "/usr/bin/true"))
        XCTAssertNil(ShortcutRingSuggestions.bundleIdentifier(ofApplicationAt: "/Applications/No Such App Here.app"))
        let finder = Application(path: "/System/Library/CoreServices/Finder.app")
        XCTAssertEqual(ShortcutRingSuggestions.suggestion(for: finder)?.appName, "Finder")
    }

    // MARK: Safety, over the whole file

    /// Nothing destructive is suggested: no place that deletes what cannot be brought
    /// back, ends a call, quits, or changes something outside the Mac (a push, a sent
    /// request); Excel's Delete Cells (where every other app zooms out) gave way to the
    /// font size pair, and Outlook's Delete left that place empty, as Mail's is: a flick
    /// down from habit would delete a message. The deletes left are each taken back by the
    /// app's Undo or a bin, or asked about first, and none is on the bottom place. No
    /// terminal clears its scrollback (⌘K in Terminal, iTerm2 and Warp, which no Undo
    /// brings back): their top right place splits the pane instead.
    func testNoPlaceIsDestructive() throws {
        let never: Set<String> = [
            "Delete Cells", "Insert Cells", "Leave Call", "Leave Meeting", "Delete Now", "Empty Trash", "Quit", "Force Quit",
            "Close Window", "Push", "Force Push", "Commit & Push", "Send Request", "Delete Chat",
            "Clear", "Clear Buffer", "Clear to Start", "Clear Blocks", "Clear Scrollback",
        ]
        let recoverable: Set<String> = [
            "Finder: Move to Trash", "Photos: Delete",
            "Final Cut Pro: Ripple Delete", "Adobe Premiere Pro: Ripple Delete", "DaVinci Resolve: Ripple Delete",
            "CapCut: Delete", "iMovie: Delete",
        ]
        for app in catalog.apps {
            for place in app.slots.compactMap(\.place) {
                let what = "\(app.appName): \(place.name)"
                XCTAssertFalse(never.contains(place.name), what)
                if place.name.contains("Delete") || place.name.contains("Trash") {
                    XCTAssertTrue(recoverable.contains(what), what)
                    XCTAssertNotEqual(app.slots[4].place, place, "not where other apps zoom out: \(what)")
                }
            }
        }
        XCTAssertNil(try SuggestionFixtures.app("Microsoft Outlook").slots[4].place, "Outlook's bottom")
        let excel = try SuggestionFixtures.app("Microsoft Excel")
        XCTAssertEqual(excel.slots[0].place?.name, "Increase Font Size")
        XCTAssertEqual(excel.slots[4].place?.name, "Decrease Font Size")
        for name in ["Terminal", "iTerm2", "Warp"] {
            let terminal = try SuggestionFixtures.app(name)
            XCTAssertFalse(terminal.slots.compactMap(\.place).contains { $0.keys == ShortcutRingSuggestion.Keys(character: "k", modifiers: .maskCommand) }, name)
            XCTAssertEqual(terminal.slots[1].place?.keys, ShortcutRingSuggestion.Keys(character: "d", modifiers: .maskCommand), name)
            XCTAssertNotEqual(terminal.slots[1].place?.symbol, "eraser", name)
        }
    }

    /// A key without modifiers only in apps whose canvas, timeline or player takes it
    /// (creative and CAD apps, audio and video editors and players, Photos); never in
    /// apps with text fields as their main surface. An alternative always has modifiers.
    func testKeysWithoutModifiersAreOnlyInCanvasApps() {
        let canvasApps: Set<String> = [
            "Adobe After Effects", "Adobe Lightroom Classic", "Adobe Premiere Pro", "Autodesk Fusion", "Blender", "Cinema 4D",
            "Final Cut Pro", "Logic Pro", "Photos", "Rhinoceros", "SketchUp", "Spotify",
            "Ableton Live", "CapCut", "Capture One", "GarageBand", "GIMP", "IINA", "iMovie", "Music", "QuickTime Player",
            "Unity", "VLC",
        ]
        var withoutModifiers: Set<String> = []
        for app in catalog.apps {
            for place in app.slots.compactMap(\.place) {
                if place.modifierless || place.keys.modifiers.isEmpty {
                    withoutModifiers.insert(app.appName)
                    XCTAssertTrue(canvasApps.contains(app.appName), "\(app.appName): \(place.name)")
                }
                if case .keys(let alternative)? = place.alternative {
                    XCTAssertFalse(alternative.modifiers.isEmpty, "\(app.appName): \(place.name)")
                }
            }
        }
        XCTAssertEqual(withoutModifiers, canvasApps)
        XCTAssertFalse(withoutModifiers.contains("Mail"))
    }

    // MARK: The lead's decisions on the second fifty

    private func keys(_ character: String, _ modifiers: CGEventFlags) -> ShortcutRingSuggestion.Keys {
        return ShortcutRingSuggestion.Keys(character: character, modifiers: modifiers)
    }

    /// Nothing changes something outside the Mac at one flick: the git clients fetch where
    /// they pushed (Pull stays), Postman opens a tab where it sent the request.
    func testNoPlacePushesOrSendsARequest() throws {
        let github = try SuggestionFixtures.app("GitHub Desktop")
        XCTAssertEqual(github.slots[1].place?.name, "Fetch")
        XCTAssertEqual(github.slots[1].place?.keys, keys("t", [.maskShift, .maskCommand]))
        XCTAssertEqual(github.slots[7].place?.name, "Pull")
        let tower = try SuggestionFixtures.app("Tower")
        XCTAssertEqual(tower.slots[0].place?.name, "Fetch")
        XCTAssertEqual(tower.slots[0].place?.keys, keys("f", [.maskShift, .maskCommand]))
        XCTAssertEqual(tower.slots[4].place?.name, "Pull")
        // Fork had Fetch on the top right already: it moved to where Push was, over Pull.
        let fork = try SuggestionFixtures.app("Fork")
        XCTAssertEqual(fork.slots[0].place?.name, "Fetch")
        XCTAssertEqual(fork.slots[0].place?.keys, keys("f", [.maskShift, .maskCommand]))
        XCTAssertEqual(fork.slots[1].place?.name, "Reveal HEAD")
        XCTAssertEqual(fork.slots[4].place?.name, "Pull")
        let pushes: [(app: ShortcutRingSuggestion, keys: ShortcutRingSuggestion.Keys)] = [
            (github, keys("p", .maskCommand)), (tower, keys("u", [.maskShift, .maskCommand])),
            (tower, keys("u", [.maskControl, .maskCommand])), (fork, keys("p", [.maskShift, .maskCommand])),
            (fork, keys("return", [.maskAlternate, .maskCommand])),
        ]
        for push in pushes {
            XCTAssertFalse(push.app.slots.compactMap(\.place).contains { $0.keys == push.keys }, push.app.appName)
        }
        let postman = try SuggestionFixtures.app("Postman")
        XCTAssertEqual(postman.slots[1].place?.name, "New Tab")
        XCTAssertEqual(postman.slots[1].place?.keys, keys("t", .maskCommand))
        XCTAssertFalse(postman.slots.compactMap(\.place).contains { $0.keys.character == "return" }, "⌘↩ sends the request")
        // (SketchUp's Push/Pull is a modelling tool.)
        let sends: Set<String> = ["Push", "Force Push", "Commit & Push", "Send", "Send Request", "Publish"]
        for app in catalog.apps {
            for place in app.slots.compactMap(\.place) {
                XCTAssertFalse(sends.contains(place.name), "\(app.appName): \(place.name)")
            }
        }
    }

    /// No place turns a call's microphone or camera on: a flick up or down from the zoom
    /// habit of the other rings opened the mic or the camera in Zoom and Teams, and
    /// Discord's top right unmuted its voice. Teams zooms there as the other apps do; Zoom,
    /// which has no zoom keys in a meeting, goes full screen and switches between speaker
    /// and gallery view (both only on this Mac); Discord shows or hides its member list.
    func testNoPlaceTurnsTheMicrophoneOrTheCameraOn() throws {
        let never: Set<String> = [
            "Mute/Unmute", "Mute / Unmute", "Camera On/Off", "Camera On / Off", "Start / Stop Video", "Deafen/Undeafen",
        ]
        for app in catalog.apps {
            for place in app.slots.compactMap(\.place) {
                XCTAssertFalse(never.contains(place.name), "\(app.appName): \(place.name)")
            }
        }
        let teams = try SuggestionFixtures.app("Microsoft Teams")
        XCTAssertEqual(teams.slots[0].place?.name, "Zoom In")
        XCTAssertEqual(teams.slots[0].place?.keys, keys("=", .maskCommand))
        XCTAssertEqual(teams.slots[4].place?.name, "Zoom Out")
        XCTAssertEqual(teams.slots[4].place?.keys, keys("-", .maskCommand))
        let zoom = try SuggestionFixtures.app("Zoom Workplace")
        XCTAssertEqual(zoom.slots[0].place?.name, "Full Screen")
        XCTAssertEqual(zoom.slots[0].place?.keys, keys("f", [.maskShift, .maskCommand]))
        XCTAssertEqual(zoom.slots[4].place?.name, "Speaker / Gallery View")
        XCTAssertEqual(zoom.slots[4].place?.keys, keys("w", [.maskShift, .maskCommand]))
        let discord = try SuggestionFixtures.app("Discord")
        XCTAssertEqual(discord.slots[1].place?.name, "Member List")
        XCTAssertEqual(discord.slots[1].place?.keys, keys("u", .maskCommand))
        let switches: [(app: ShortcutRingSuggestion, keys: ShortcutRingSuggestion.Keys)] = [
            (teams, keys("m", [.maskShift, .maskCommand])), (teams, keys("o", [.maskShift, .maskCommand])),
            (zoom, keys("a", [.maskShift, .maskCommand])), (zoom, keys("v", [.maskShift, .maskCommand])),
            (discord, keys("m", [.maskShift, .maskCommand])), (discord, keys("d", [.maskShift, .maskCommand])),
        ]
        for that in switches {
            XCTAssertFalse(that.app.slots.compactMap(\.place).contains { $0.keys == that.keys }, that.app.appName)
        }
    }

    /// The low-confidence apps keep only the places whose keys are confirmed (Copy, Paste,
    /// Undo, Redo; WhatsApp's New Chat and Mark Read/Unread); a guessed place stays empty
    /// with its reason, in every app (iMovie's zoom).
    func testGuessedPlacesStayEmpty() throws {
        for name in ["Microsoft Copilot", "Perplexity"] {
            let app = try SuggestionFixtures.app(name)
            XCTAssertEqual(app.slots.compactMap(\.place).map(\.name), ["Redo", "Paste", "Copy", "Undo"], name)
            for index in [0, 1, 4, 7] {
                guard case .empty(let reason) = app.slots[index] else { return XCTFail("\(name) \(index)") }
                XCTAssertTrue(reason.contains("guess"), reason)
            }
        }
        let whatsapp = try SuggestionFixtures.app("WhatsApp")
        XCTAssertEqual(whatsapp.slots.compactMap(\.place).map(\.name), ["Mark Read/Unread", "Paste", "Copy", "New Chat"])
        for (index, word) in [(0, "guess"), (4, "guess"), (2, "not confirmed"), (6, "not confirmed")] {
            guard case .empty(let reason) = whatsapp.slots[index] else { return XCTFail("WhatsApp \(index)") }
            XCTAssertTrue(reason.contains(word), reason)
        }
        let imovie = try SuggestionFixtures.app("iMovie")
        XCTAssertNil(imovie.slots[0].place, "Zoom In: remembered, on no Apple page")
        XCTAssertNil(imovie.slots[4].place)
        XCTAssertEqual(imovie.slots.compactMap(\.place).count, 6)
    }

    /// ⌘[ in Discord starts a call in the open conversation: no place of Discord sends
    /// "[" or "]", nor anything that falls back to them.
    func testDiscordNeverSendsABracket() throws {
        let discord = try SuggestionFixtures.app("Discord")
        XCTAssertEqual(discord.slots.compactMap(\.place).count, 8)
        for place in discord.slots.compactMap(\.place) {
            XCTAssertFalse(["[", "]"].contains(place.keys.character), place.name)
            XCTAssertNil(place.alternative, place.name)
        }
        for layout in [KeyboardLayoutLayers.us] + ((try? SuggestionFixtures.layout("com.apple.keylayout.German")).map { [$0] } ?? []) {
            for place in discord.places(on: layout) {
                guard let key = ShortcutRingPlace.keyCombination(named: place.action) else { continue }
                XCTAssertFalse([33, 30].contains(key.code), "\(place.action): the [ and ] keys of US")
            }
        }
    }

    /// The apps the lead kept: ChatGPT Atlas, and Windsurf under the researchers' name.
    func testTheKeptAppsAreThere() throws {
        XCTAssertEqual(catalog.suggestion(forBundleIdentifier: "com.openai.atlas")?.appName, "ChatGPT Atlas")
        XCTAssertEqual(catalog.suggestion(forBundleIdentifier: "com.exafunction.windsurf")?.appName, "Windsurf (Devin Desktop)")
    }
}

// MARK: - The keys on a keyboard layout

final class ShortcutRingSuggestionKeysTests: XCTestCase {

    private var catalog: ShortcutRingSuggestions.Catalog { ShortcutRingSuggestions.shipped }

    private func custom(_ code: CGKeyCode, _ modifiers: CGEventFlags) -> String {
        return ButtonBinding.normalizedCustomBindingName(code: code, modifiers: modifiers.rawValue)
    }

    /// On US every suggested place runs and is the shortcut itself: Undo, Copy … the
    /// listed actions, everything else the US key with its modifiers, named.
    func testOnTheUSLayoutEveryPlaceIsTheShortcutItself() throws {
        for app in catalog.apps {
            let places = app.places(on: .us)
            for (slot, place) in zip(app.slots, places) {
                guard let suggested = slot.place else {
                    XCTAssertEqual(place, .empty)
                    continue
                }
                let what = "\(app.appName): \(suggested.name)"
                XCTAssertTrue(place.runs, what)
                if let listed = place.shortcut {
                    XCTAssertEqual(listed.localizedName, suggested.name, what)
                } else {
                    XCTAssertEqual(place.label, ShortcutLabel(name: suggested.name, icon: .symbol(suggested.symbol)), what)
                }
            }
        }
        let figma = try SuggestionFixtures.app("Figma").places(on: .us)
        XCTAssertEqual(figma[0].action, custom(24, .maskCommand), "Zoom In: ⌘=")
        XCTAssertEqual(figma[6], ShortcutRingPlace(SystemShortcut.undo))
        XCTAssertEqual(figma[2], ShortcutRingPlace(SystemShortcut.redo))
        XCTAssertEqual(figma[5], ShortcutRingPlace(SystemShortcut.copy))
        let safari = try SuggestionFixtures.app("Safari").places(on: .us)
        XCTAssertEqual(safari[6].action, custom(33, .maskCommand), "Back: ⌘[")
        XCTAssertEqual(safari[3].action, custom(48, .maskControl), "Next Tab: ⌃⇥")
        let notes = try SuggestionFixtures.app("Notes").places(on: .us)
        XCTAssertEqual(notes[0].action, custom(47, [.maskShift, .maskCommand]), "Zoom In: ⇧⌘.")
        let xcode = try SuggestionFixtures.app("Xcode").places(on: .us)
        XCTAssertEqual(xcode[7].action, custom(123, [.maskControl, .maskCommand, .maskSecondaryFn]), "Back: ⌃⌘←, as recorded")
        // Redo is ⌘Y in Word: the recorded key, not the listed Redo (⇧⌘Z).
        let word = try SuggestionFixtures.app("Microsoft Word").places(on: .us)
        XCTAssertEqual(word[2].action, custom(16, .maskCommand))
        XCTAssertEqual(word[7], ShortcutRingPlace(SystemShortcut.bold))
    }

    /// The system's own US layout gives what the built-in US table gives.
    func testTheSystemsUSLayoutAgreesWithTheBuiltInOne() throws {
        let us = try SuggestionFixtures.layout("com.apple.keylayout.US")
        for app in catalog.apps {
            XCTAssertEqual(app.places(on: us), app.places(on: .us), app.appName)
        }
    }

    /// Blender's three keypad places are the keypad's keys, named in the rows.
    func testBlendersKeypadPlacesAreTheKeypadsKeys() throws {
        let blender = try SuggestionFixtures.app("Blender").places(on: .us)
        XCTAssertEqual(blender[0].action, custom(65, []))
        XCTAssertEqual(blender[1].action, custom(82, []))
        XCTAssertEqual(blender[3].action, custom(75, []))
        XCTAssertEqual(KeyCode.name(of: 65), "Keypad .")
        XCTAssertEqual(KeyCode.name(of: 82), "Keypad 0")
        XCTAssertEqual(KeyCode.name(of: 75), "Keypad /")
        XCTAssertEqual(ButtonActionPullDown.keyComponents(of: blender[1].action), ["Keypad 0"])
    }

    /// German QWERTZ: Z and Y trade places, "+" and "-" have keys of their own, "=" is
    /// Shift-0, "[" "]" "\" need Option. ⌘Z stays Undo (the listed action, which is sent
    /// with the key that types Z); ⌘Y is the key that types Y; zoom is the "+" and "-"
    /// keys; a "[" shortcut takes its alternative or is left empty.
    func testOnGermanQWERTZTheKeysFollowTheCharacters() throws {
        let german = try SuggestionFixtures.layout("com.apple.keylayout.German")
        XCTAssertEqual(german.command[16], "z", "the layout this test is about")

        let figma = try SuggestionFixtures.app("Figma").places(on: german)
        XCTAssertEqual(figma[6], ShortcutRingPlace(SystemShortcut.undo))
        XCTAssertEqual(figma[0].action, custom(30, .maskCommand), "Zoom In: the + key")
        XCTAssertEqual(figma[4].action, custom(44, .maskCommand), "Zoom Out: the - key")
        let keys = KeyboardLayoutKeys(layout: FixedLayoutSource(source: try XCTUnwrap(SuggestionFixtures.inputSource("com.apple.keylayout.German"))))
        XCTAssertEqual(keys.keyCode(for: SystemShortcut.undo), 16, "Undo is sent with the key that types Z")

        let canva = try SuggestionFixtures.app("Canva").places(on: german)
        XCTAssertEqual(canva[2].action, custom(6, .maskCommand), "Redo ⌘Y: the key that types Y")
        let blender = try SuggestionFixtures.app("Blender").places(on: german)
        XCTAssertEqual(blender[5].action, custom(16, .maskAlternate), "Toggle X-Ray ⌥Z")
        let premiere = try SuggestionFixtures.app("Adobe Premiere Pro").places(on: german)
        XCTAssertEqual(premiere[0].action, custom(29, .maskShift), "Zoom In =: Shift-0")

        // ⇧⌘. is ⌘> on US: ">" and "<" are the key left of Y on German, the key whose ⌘
        // switches windows, so Notes' zoom stays empty there
        // (`testOnISOLayoutsNoPlaceIsTheKeyThatSwitchesWindows`).
        let notes = try SuggestionFixtures.app("Notes").places(on: german)
        XCTAssertEqual(notes[0], .empty, "Zoom In ⇧⌘.")
        XCTAssertEqual(notes[4], .empty, "Zoom Out ⇧⌘,")

        let safari = try SuggestionFixtures.app("Safari").places(on: german)
        XCTAssertEqual(safari[6], ShortcutRingPlace(SystemShortcut.navigateBack))
        XCTAssertEqual(safari[2], ShortcutRingPlace(SystemShortcut.navigateForward))
        let spotify = try SuggestionFixtures.app("Spotify").places(on: german)
        XCTAssertEqual(spotify[5].action, custom(123, [.maskAlternate, .maskCommand, .maskSecondaryFn]))
        XCTAssertEqual(spotify[5].label?.name, "Back")
        let claude = try SuggestionFixtures.app("Claude").places(on: german)
        XCTAssertEqual(claude[6].action, custom(48, [.maskControl, .maskShift]))
        XCTAssertEqual(claude[6].label?.name, "Previous Chat")
        XCTAssertEqual(try SuggestionFixtures.app("Finder").places(on: german)[6], .empty)
        XCTAssertEqual(try SuggestionFixtures.app("Notion").places(on: german)[4], .empty, "Toggle Sidebar ⌘\\")
        XCTAssertEqual(try SuggestionFixtures.app("Microsoft Outlook").places(on: german)[6], .empty, "⌃[")
        XCTAssertEqual(try SuggestionFixtures.app("Adobe Lightroom Classic").places(on: german)[7], .empty, "\\")
    }

    /// ⌘ and ⇧⌘ with the key that is "`" on US (code 50: beside left Shift on ISO, "<"
    /// and ">" on German, Slovenian, Swiss, French, Swedish, Spanish) are macOS's "Move
    /// focus to next window" and back, and a sent shortcut goes through them. ⇧⌘. and ⇧⌘,
    /// (zoom in Notes, Pages, Keynote, Numbers and TextEdit, Excel's font size) would land
    /// there as ⇧⌘> and ⌘<: those places stay empty, and the page counts them. On US they
    /// are the "." and "," keys as before, and ⌘` is still that key where a shortcut asks
    /// for it.
    func testOnISOLayoutsNoPlaceIsTheKeyThatSwitchesWindows() throws {
        let windowKeys: Set<UInt64> = [CGEventFlags.maskCommand.rawValue, CGEventFlags([.maskShift, .maskCommand]).rawValue]
        let modifierKeys: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
        var checked = 0
        for id in ["German", "Slovenian", "SwissGerman", "French", "Swedish-Pro", "Spanish-ISO"].map({ "com.apple.keylayout.\($0)" }) {
            guard let source = SuggestionFixtures.inputSource(id), let layout = KeyboardLayoutLayers.of(source) else { continue }
            checked += 1
            for app in catalog.apps {
                for (slot, place) in zip(app.slots, app.places(on: layout)) {
                    guard let key = ShortcutRingPlace.keyCombination(named: place.action) else { continue }
                    let modifiers = CGEventFlags(rawValue: key.modifiers).intersection(modifierKeys)
                    XCTAssertFalse(key.code == 50 && windowKeys.contains(modifiers.rawValue),
                                   "\(id) \(app.appName): \(slot.place?.name ?? place.action)")
                }
            }
        }
        guard checked > 0 else { throw XCTSkip("none of these layouts is on this Mac") }

        let german = try SuggestionFixtures.layout("com.apple.keylayout.German")
        XCTAssertEqual(german.plain[50], "<", "the layout this test is about")
        for name in ["Notes", "Pages", "Keynote", "Numbers", "TextEdit", "Microsoft Excel"] {
            let app = try SuggestionFixtures.app(name)
            let places = app.places(on: german)
            XCTAssertEqual(places[0], .empty, name)
            XCTAssertEqual(places[4], .empty, name)
            XCTAssertEqual(app.placesLeftEmpty(in: places), 2, name)
        }
        XCTAssertEqual(KeyboardLayoutLayers.us.key(for: ".", modifiers: [.maskShift, .maskCommand])?.code, 47)
        XCTAssertEqual(KeyboardLayoutLayers.us.key(for: ",", modifiers: [.maskShift, .maskCommand])?.code, 43)
        XCTAssertEqual(KeyboardLayoutLayers.us.key(for: "`", modifiers: .maskCommand)?.code, 50)
        XCTAssertNil(german.key(for: ",", modifiers: [.maskShift, .maskCommand]))
    }

    /// On QWERTZ and the other layouts where signs and digits sit elsewhere (Swiss, Polish,
    /// Turkish F and Q, Hungarian, Kurdish): every place sends a key that types what the
    /// shortcut has, never another character. A letter is the key that types it; a sign
    /// or a digit is a key that types it (or its US Shift pair: ">" for ⇧⌘., "+" for
    /// zoom's ⌘=) with the modifiers it is sent with; a place whose character the layout
    /// types only with Option takes its alternative or stays empty; Option is never added.
    /// (Zoom was sent with the US key where the layout has no "+", "=" or "-" under
    /// Command alone: ⌘^ on Swiss, ⌘X, Cut, for Zoom Out on Turkish F.)
    func testOnOtherLayoutsNoPlaceSendsAnotherCharacter() throws {
        let ids = [
            "German", "Slovenian", "SwissGerman", "SwissFrench", "Polish", "Turkish", "Turkish-QWERTY-PC",
            "Hungarian", "Hungarian-QWERTY", "Kurdish-Kurmanji",
        ].map { "com.apple.keylayout.\($0)" }
        var checked = 0
        for id in ids {
            guard let source = SuggestionFixtures.inputSource(id), let layout = KeyboardLayoutLayers.of(source) else { continue }
            checked += 1
            for app in catalog.apps {
                for (slot, place) in zip(app.slots, app.places(on: layout)) {
                    guard let suggested = slot.place else { continue }
                    let what = "\(id) \(app.appName): \(suggested.name)"
                    let character = suggested.keys.character
                    guard suggested.keys.combination(on: layout) != nil else {
                        switch suggested.alternative {
                        case .listed(let shortcut)?: XCTAssertEqual(place, ShortcutRingPlace(shortcut), what)
                        case .keys?: XCTAssertNotEqual(place.action, "", what)
                        case nil: XCTAssertEqual(place, .empty, what)
                        }
                        continue
                    }
                    // (A listed action is sent with the layout's key when it runs; a named
                    // key is the same key on every layout.)
                    guard ShortcutRingSuggestion.Keys.namedKeys[character] == nil,
                          let key = ShortcutRingPlace.keyCombination(named: place.action) else { continue }
                    let sent = CGEventFlags(rawValue: key.modifiers)
                    XCTAssertEqual(sent.contains(.maskAlternate), suggested.keys.modifiers.contains(.maskAlternate), "no Option added: \(what)")
                    let withCommand = sent.contains(.maskCommand)
                    if KeyCode.usLetterKeyCodes[character] != nil {
                        XCTAssertEqual((withCommand ? layout.command : layout.plain)[key.code]?.lowercased(), character, what)
                        continue
                    }
                    // What the key types with the modifiers it is sent with (with Shift and
                    // Command, as without Command: under Command many layouts drop Shift).
                    let typed: [String?] = sent.contains(.maskShift)
                        ? (withCommand ? [layout.commandShift[key.code], layout.shift[key.code]] : [layout.shift[key.code]])
                        : [(withCommand ? layout.command : layout.plain)[key.code]]
                    var wanted: Set<String> = [character]
                    if let shifted = KeyboardLayoutLayers.usShifted[character] {
                        if suggested.keys.modifiers.contains(.maskShift) { wanted = [shifted] }
                        if suggested.keys.modifiers == .maskCommand, character == "=" { wanted.insert(shifted) }
                    }
                    XCTAssertTrue(typed.contains { $0.map(wanted.contains) == true },
                                  "\(what): key \(key.code) types \(typed.compactMap { $0 }), not \(wanted.sorted())")
                }
            }
        }
        guard checked > 0 else { throw XCTSkip("none of these layouts is on this Mac") }
        // The cases of the review: zoom with Shift added where "=" or "-" needs it, and
        // Hungarian's "0", which is left of 1.
        if let turkish = try? SuggestionFixtures.layout("com.apple.keylayout.Turkish") {
            let figma = try SuggestionFixtures.app("Figma").places(on: turkish)
            XCTAssertEqual(figma[4].action, custom(44, [.maskShift, .maskCommand]), "Zoom Out: \"-\" is Shift and the , key")
        }
        if let swiss = try? SuggestionFixtures.layout("com.apple.keylayout.SwissGerman") {
            let figma = try SuggestionFixtures.app("Figma").places(on: swiss)
            XCTAssertEqual(figma[0].action, custom(29, [.maskShift, .maskCommand]), "Zoom In: \"=\" is Shift-0")
        }
        if let hungarian = try? SuggestionFixtures.layout("com.apple.keylayout.Hungarian") {
            let illustrator = try SuggestionFixtures.app("Adobe Illustrator").places(on: hungarian)
            let fit = try XCTUnwrap(ShortcutRingPlace.keyCombination(named: illustrator[7].action))
            XCTAssertEqual(hungarian.command[fit.code], "0", "Fit Artboard ⌘0")
        }
    }

    /// A layout that types "." only with Shift (French AZERTY): ⌘. is sent as ⇧⌘ and the
    /// key whose Shift types ".".
    func testASignThatNeedsShiftOnTheLayoutGetsShift() throws {
        let french = try SuggestionFixtures.layout("com.apple.keylayout.French")
        let stop = try SuggestionFixtures.place("Stop", of: "Xcode")
        let key = try XCTUnwrap(stop.keys.combination(on: french))
        XCTAssertTrue(key.modifiers.contains(.maskShift))
        XCTAssertEqual(french.commandShift[key.code], ".")
    }

    /// The pure part, on a layout made up for the test: Option is never added, a sign that
    /// only Option types gives nothing.
    func testACharacterOnlyOptionTypesGivesNoKey() {
        var layout = KeyboardLayoutLayers.us
        layout.plain[33] = "š"
        layout.shift[33] = "Š"
        layout.command[33] = "š"
        layout.commandShift[33] = "Š"
        XCTAssertNil(layout.key(for: "[", modifiers: .maskCommand))
        XCTAssertEqual(layout.key(for: "z", modifiers: .maskCommand)?.code, 6)
        XCTAssertEqual(KeyboardLayoutLayers.us.key(for: "=", modifiers: [.maskControl, .maskShift])?.modifiers,
                       [.maskControl, .maskShift], "⌃⇧= on US is the = key with Shift")
    }

    /// The cases of the second fifty's report, through the same resolution: Telegram's ⌘0
    /// is the 0 key with Command alone (also on AZERTY, which types "0" with Shift);
    /// GIMP's "+" without a modifier is Shift and "=" on US and the "+" key without Shift
    /// on German, and so is Ableton Live's (it was "=", Shift-0 on German); Opera's bottom corners are Copy and Paste (its ⌃⇥ cycler switches when
    /// Control is let go, which a sent shortcut does not do as a key of its own); the new
    /// browsers' ⌘[ / ⌘] take Scrollio's Back and Forward where "[" needs Option, and
    /// BBEdit's four bracket places stay empty there.
    func testTheSecondFiftysLayoutCasesComeOutRight() throws {
        XCTAssertEqual(try SuggestionFixtures.app("Telegram").places(on: .us)[1].action, custom(29, .maskCommand), "Saved Messages ⌘0")
        let gimp = try SuggestionFixtures.app("GIMP").places(on: .us)
        XCTAssertEqual(gimp[0].action, custom(24, .maskShift), "Zoom In: + is Shift and = on US")
        XCTAssertEqual(gimp[4].action, custom(27, []), "Zoom Out: -")
        XCTAssertEqual(gimp[2].action, custom(16, .maskCommand), "Redo ⌘Y (⇧⌘Z is Strong Undo in GIMP)")
        let opera = try SuggestionFixtures.app("Opera").places(on: .us)
        XCTAssertEqual(opera[5], ShortcutRingPlace(SystemShortcut.copy))
        XCTAssertEqual(opera[3], ShortcutRingPlace(SystemShortcut.paste))
        XCTAssertEqual(opera[6].action, custom(123, [.maskCommand, .maskSecondaryFn]), "Back ⌘←")
        XCTAssertFalse(try SuggestionFixtures.app("Opera").slots.compactMap(\.place).contains { $0.keys.character == "tab" })

        if let french = try? SuggestionFixtures.layout("com.apple.keylayout.French") {
            XCTAssertEqual(try SuggestionFixtures.app("Telegram").places(on: french)[1].action, custom(29, .maskCommand),
                           "⌘0 on AZERTY: the 0 key, no Shift added")
        }
        let german = try SuggestionFixtures.layout("com.apple.keylayout.German")
        XCTAssertEqual(try SuggestionFixtures.app("Telegram").places(on: german)[1].action, custom(29, .maskCommand))
        let gimpGerman = try SuggestionFixtures.app("GIMP").places(on: german)
        XCTAssertEqual(gimpGerman[0].action, custom(30, []), "Zoom In: the + key, without Shift")
        XCTAssertEqual(german.plain[30], "+")
        XCTAssertEqual(gimpGerman[2].action, custom(6, .maskCommand), "Redo ⌘Y: the key that types Y")
        // Ableton Live zooms with "+" as GIMP does: stored as GIMP's, never Shift-0 ("=").
        XCTAssertEqual(try SuggestionFixtures.place("Zoom In", of: "Ableton Live"), try SuggestionFixtures.place("Zoom In", of: "GIMP"))
        XCTAssertEqual(try SuggestionFixtures.app("Ableton Live").places(on: german)[0].action, custom(30, []), "Zoom In: the + key")
        XCTAssertEqual(try SuggestionFixtures.app("Ableton Live").places(on: .us)[0].action, custom(24, .maskShift), "Zoom In: +")
        XCTAssertEqual(try SuggestionFixtures.app("Ableton Live").places(on: german)[4].action, custom(44, []), "Zoom Out: the - key")
        for name in ["Brave Browser", "ChatGPT Atlas", "Dia", "Orion", "Zen Browser"] {
            let places = try SuggestionFixtures.app(name).places(on: german)
            XCTAssertEqual(places[6], ShortcutRingPlace(SystemShortcut.navigateBack), name)
            XCTAssertEqual(places[2], ShortcutRingPlace(SystemShortcut.navigateForward), name)
        }
        let bbedit = try SuggestionFixtures.app("BBEdit")
        XCTAssertEqual(bbedit.placesLeftEmpty(in: bbedit.places(on: german)), 4)
        XCTAssertEqual(bbedit.placesLeftEmpty(in: bbedit.places(on: .us)), 0)
    }
}

/// A layout source over one input source, for `KeyboardLayoutKeys`.
private struct FixedLayoutSource: KeyboardLayoutSource {
    let source: TISInputSource

    func currentLayoutID() -> String? {
        return SystemKeyboardLayoutSource.id(of: source)
    }

    func currentCharacters() -> [CGKeyCode: String] {
        return SystemKeyboardLayoutSource.characters(of: source)
    }

    func currentCommandCharacters() -> [CGKeyCode: String] {
        return SystemKeyboardLayoutSource.characters(of: source, modifierKeyState: SystemKeyboardLayoutSource.commandKeyState)
    }
}

// MARK: - Filling an app's ring

final class ShortcutRingSuggestionFillTests: XCTestCase {

    private var savedApplications: EnhanceArray<Application>!
    private var savedRing = ShortcutRingSettings.default
    private var savedBindings: [ButtonBinding] = []

    override func setUp() {
        super.setUp()
        savedApplications = Options.shared.application.applications
        savedRing = Options.shared.ring
        savedBindings = Options.shared.buttons.binding
        Options.shared.application.applications = list([])
        Options.shared.ring = .default
        Options.shared.buttons.binding = []
        SuggestionFixtures.install(for: self)
    }

    override func tearDown() {
        Options.shared.application.applications = savedApplications
        Options.shared.ring = savedRing
        Options.shared.buttons.binding = savedBindings
        ShortcutRingController.forgetPreparedFaces()
        savedApplications = nil
        super.tearDown()
    }

    private func list(_ applications: [Application]) -> EnhanceArray<Application> {
        return EnhanceArray<Application>(
            withArray: applications, matchKey: "path", forObserver: { Options.shared.markChanged(.application) }
        )
    }

    private func add(_ path: String, name: String? = nil) -> Application {
        let application = Application(path: path)
        application.displayName = name
        Options.shared.application.applications.append(application)
        return application
    }

    private func part(for application: Application, undo: UndoManager? = nil) -> ApplicationRingPartViewController {
        let part = ApplicationRingPartViewController(application: application)
        part.paneUndoManager = undo
        _ = part.view
        return part
    }

    private func turn(_ part: ApplicationRingPartViewController, general on: Bool) {
        part.generalRingRow.toggle.state = on ? .on : .off
        part.generalRingClick(part.generalRingRow.toggle)
    }

    private var figmaSuggestion: [ShortcutRingPlace] {
        return (try? SuggestionFixtures.app("Figma").places(on: .us)) ?? []
    }

    /// While an app with suggested shortcuts uses the general ring and never had one of its
    /// own, its Ring part says that it has some, with "Use Suggested Shortcuts", which does
    /// what turning the switch off does: the ring filled with them. Nothing is filled
    /// before the click; an app without a suggestion, and one whose own ring is kept for
    /// later, get no line.
    func testTheRingPartOffersTheSuggestedShortcutsWhileTheAppUsesTheGeneralRing() throws {
        let figma = add(SuggestionFixtures.figmaPath, name: "Figma")
        let part = part(for: figma)
        XCTAssertEqual(part.suggestionNote.text, "Scrollio has suggested shortcuts for Figma.")
        let button = part.suggestionNote.button
        XCTAssertFalse(button.isHidden)
        XCTAssertEqual(button.title, "Use Suggested Shortcuts")
        XCTAssertNil(figma.ring, "nothing is filled before the click")
        XCTAssertTrue(figma.usesGeneralRing)

        XCTAssertTrue(button.sendAction(button.action, to: button.target))
        XCTAssertFalse(figma.usesGeneralRing, "as the switch turned off")
        XCTAssertEqual(part.generalRingRow.toggle.state, .off)
        XCTAssertEqual(figma.ownRingPlaces, figmaSuggestion)
        XCTAssertNotNil(part.ringController)
        XCTAssertNil(part.suggestionNote.text, "no offer any more")
        XCTAssertEqual(Options.shared.ring, .default, "the general ring is untouched")

        // Back to the general ring: the own ring is kept, and the switch brings it back.
        turn(part, general: true)
        XCTAssertNil(part.suggestionNote.text)

        let calculator = add(SuggestionFixtures.calculatorPath)
        XCTAssertNil(self.part(for: calculator).suggestionNote.text, "no suggestion, no line")
    }

    /// "+" of Apps marks the running apps that have suggested shortcuts "Suggested ring" in
    /// grey (a badge); choosing one adds it with nothing of its own.
    func testThePlusMenuMarksAppsWithASuggestedRing() throws {
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesSplitViewController.self))
        let pane = storyboard.instantiateController(withIdentifier: PANEL_IDENTIFIER.application) as! PreferencesApplicationViewController
        pane.uiStateDefaults = TestDefaults.make(for: self)
        pane.presentMenu = { _, _ in }
        pane.chooseApplications = { _, _ in XCTFail("no open panel was expected") }
        pane.runningApplications = {
            [
                ApplicationCandidate(path: SuggestionFixtures.figmaPath + "/Contents/MacOS/Figma", knownPaths: [SuggestionFixtures.figmaPath],
                                     name: "Figma", icon: nil, bundleIdentifier: "com.figma.Desktop"),
                ApplicationCandidate(path: SuggestionFixtures.calculatorPath, knownPaths: [SuggestionFixtures.calculatorPath],
                                     name: "Calculator", icon: nil, bundleIdentifier: "com.apple.calculator"),
            ]
        }
        _ = pane.view
        let menu = pane.makeAddMenu()
        XCTAssertEqual(menu.items.first?.title, "Figma", "the name stays the item's title")
        XCTAssertEqual(menu.items.first?.badge?.stringValue, "Suggested ring")
        XCTAssertNil(menu.items[1].badge)

        let figma = try XCTUnwrap(menu.items.first)
        pane.addRunningApplication(figma)
        let added = try XCTUnwrap(Options.shared.application.applications.get(by: SuggestionFixtures.figmaPath + "/Contents/MacOS/Figma"))
        XCTAssertNil(added.ring, "nothing is filled")
        XCTAssertTrue(added.usesGeneralRing)
    }

    /// The model: off with a suggestion, the ring starts with it; without one, as a copy
    /// of the general ring; a ring the app had comes back as it was left.
    func testTheSwitchStartsTheRingWithTheSuggestionElseACopy() throws {
        var general = ShortcutRingSettings.default
        general[0] = ShortcutRingPlace(SystemShortcut.find)
        let figma = Application(path: SuggestionFixtures.figmaPath)
        let suggested = try XCTUnwrap(figma.suggestedRingPlaces())
        XCTAssertEqual(suggested, figmaSuggestion)
        figma.setUsesGeneralRing(false, general: general, suggested: suggested)
        XCTAssertEqual(figma.ownRingPlaces, suggested)

        let calculator = Application(path: SuggestionFixtures.calculatorPath)
        XCTAssertNil(calculator.suggestedRingPlaces())
        calculator.setUsesGeneralRing(false, general: general, suggested: calculator.suggestedRingPlaces())
        XCTAssertEqual(calculator.ownRingPlaces, general.places)

        // Kept for later and back: as left, not filled again.
        figma.ring?[0] = ShortcutRingPlace(SystemShortcut.paste)
        figma.setUsesGeneralRing(true, general: general, suggested: suggested)
        figma.setUsesGeneralRing(false, general: general, suggested: suggested)
        XCTAssertEqual(figma.ownRingPlaces?[0], ShortcutRingPlace(SystemShortcut.paste))
    }

    /// The page: turning the switch off fills the ring from the suggestion, with no line
    /// to add on a layout that types every key; after a change "Use Suggested Shortcuts"
    /// fills all eight places again (greyed while they hold them), Undo takes it back and
    /// Redo puts it back. The general ring is never touched.
    func testThePageFillsFromTheSuggestionAndUseSuggestedShortcutsGoesBackToIt() throws {
        let figma = add(SuggestionFixtures.figmaPath, name: "Figma")
        let undo = UndoManager()
        undo.groupsByEvent = false
        let part = part(for: figma, undo: undo)
        XCTAssertNotNil(part.suggestion)
        XCTAssertNil(figma.ring, "showing the page fills nothing")

        turn(part, general: false)
        XCTAssertEqual(figma.ownRingPlaces, figmaSuggestion)
        XCTAssertNil(part.suggestionNote.text, "nothing new to say: the layout types every key")
        XCTAssertEqual(part.resetToDefaultsButton.title, "Use Suggested Shortcuts")
        XCTAssertFalse(part.resetToDefaultsButton.isEnabled, "the ring is where it started")
        XCTAssertNotNil(part.ringController)

        figma.ring?[0] = ShortcutRingPlace(SystemShortcut.find)
        figma.ring?[3] = .empty
        part.syncViewWithOptions()
        XCTAssertNil(part.suggestionNote.text)
        XCTAssertTrue(part.resetToDefaultsButton.isEnabled)
        let edited = try XCTUnwrap(figma.ownRingPlaces)

        undo.beginUndoGrouping()
        XCTAssertTrue(part.resetToDefaultsButton.sendAction(part.resetToDefaultsButton.action, to: part.resetToDefaultsButton.target))
        undo.endUndoGrouping()
        XCTAssertEqual(figma.ownRingPlaces, figmaSuggestion)
        XCTAssertFalse(figma.usesGeneralRing, "the switch stays")
        XCTAssertEqual(part.resetToDefaultsButton.title, "Undo")
        XCTAssertEqual(undo.undoActionName, "Use Suggested Shortcuts in Figma")

        undo.undo()
        XCTAssertEqual(figma.ownRingPlaces, edited)
        XCTAssertEqual(part.resetToDefaultsButton.title, "Use Suggested Shortcuts")
        XCTAssertTrue(part.resetToDefaultsButton.isEnabled)
        undo.redo()
        XCTAssertEqual(figma.ownRingPlaces, figmaSuggestion)
        XCTAssertFalse(part.resetToDefaultsButton.isEnabled)
        XCTAssertEqual(Options.shared.ring, .default)

        // Back to the general ring: the own ring is kept for later.
        turn(part, general: true)
        XCTAssertNil(part.suggestionNote.text)
        XCTAssertEqual(figma.ring?.places, figmaSuggestion)
    }

    /// The Apps pane as the window makes it, with nothing shown on screen.
    private func makePane() -> PreferencesApplicationViewController {
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesSplitViewController.self))
        let pane = storyboard.instantiateController(withIdentifier: PANEL_IDENTIFIER.application) as! PreferencesApplicationViewController
        pane.uiStateDefaults = TestDefaults.make(for: self)
        pane.runningApplications = { [] }
        pane.presentMenu = { _, _ in }
        pane.chooseApplications = { _, _ in XCTFail("no open panel was expected") }
        _ = pane.view
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: PreferencesWindowLayout.contentWidth, height: 600),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: true
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = pane
        addTeardownBlock { window.close() }
        return pane
    }

    /// "Reset to Defaults", then the app's page is closed and opened again (new parts),
    /// then Edit › Undo and Redo: the page open now shows each change, in its rows and its
    /// button. (The part that registered the Undo is gone; the pane says which part shows
    /// the app now, as for the Buttons part.)
    func testUndoOfTheRingsResetShowsOnThePageOpenedAgain() throws {
        let figma = add(SuggestionFixtures.figmaPath, name: "Figma")
        figma.setUsesGeneralRing(false, general: .default, suggested: nil)
        let general = try XCTUnwrap(figma.ownRingPlaces)
        let pane = makePane()
        let undo = UndoManager()
        undo.groupsByEvent = false
        pane.openApplication(withID: SuggestionFixtures.figmaPath, part: .ring)
        let first = try XCTUnwrap(pane.detailController?.ringPart)
        first.paneUndoManager = undo
        undo.beginUndoGrouping()
        XCTAssertTrue(first.resetToDefaultsButton.sendAction(first.resetToDefaultsButton.action, to: first.resetToDefaultsButton.target))
        undo.endUndoGrouping()
        XCTAssertEqual(figma.ownRingPlaces, figmaSuggestion)

        pane.leaveSubpage()
        pane.openApplication(withID: SuggestionFixtures.figmaPath, part: .ring)
        let part = try XCTUnwrap(pane.detailController?.ringPart)
        XCTAssertFalse(part === first)
        func rows() throws -> [String?] {
            return try XCTUnwrap(part.ringController).placePopUps.map { $0.menu?.items.first?.title }
        }
        let suggestedRows = try rows()
        XCTAssertEqual(suggestedRows[0]?.hasPrefix("Zoom In"), true)
        XCTAssertFalse(part.resetToDefaultsButton.isEnabled)

        undo.undo()
        XCTAssertEqual(figma.ownRingPlaces, general)
        XCTAssertNotEqual(try rows(), suggestedRows, "the open page shows the ring that came back")
        XCTAssertTrue(part.resetToDefaultsButton.isEnabled)

        undo.redo()
        XCTAssertEqual(figma.ownRingPlaces, figmaSuggestion)
        XCTAssertEqual(try rows(), suggestedRows)
        XCTAssertFalse(part.resetToDefaultsButton.isEnabled)
    }

    /// Where the layout cannot type some suggested keys (German: "[" "]" "\" need Option)
    /// and those places stay empty, a quiet line says how many, while the ring holds the
    /// suggestion and after a change; on a layout that types them all there is no line.
    func testTheRowSaysHowManyPlacesTheLayoutLeavesEmpty() throws {
        let german = try SuggestionFixtures.layout("com.apple.keylayout.German")
        ShortcutRingSuggestions.layout = { german }
        let finder = add(SuggestionFixtures.finderPath, name: "Finder")
        let part = part(for: finder)
        turn(part, general: false)
        XCTAssertEqual(finder.ownRingPlaces?.filter { $0 == .empty }.count, 2, "Back and Forward")
        XCTAssertEqual(part.suggestionNote.text, "2 places stay empty: their keys can't be typed on this keyboard layout.")
        finder.ring?[0] = ShortcutRingPlace(SystemShortcut.copy)
        part.syncViewWithOptions()
        XCTAssertEqual(part.suggestionNote.text, "2 places stay empty: their keys can't be typed on this keyboard layout.")

        let lightroom = add(SuggestionFixtures.lightroomPath, name: "Adobe Lightroom Classic")
        let one = self.part(for: lightroom)
        turn(one, general: false)
        XCTAssertEqual(one.suggestionNote.text, "1 place stays empty: its keys can't be typed on this keyboard layout.")

        ShortcutRingSuggestions.layout = { .us }
        part.syncViewWithOptions()
        XCTAssertNil(part.suggestionNote.text)
    }

    /// Without a suggestion the part is as before: no line, the switch copies the general
    /// ring, and the button under it says so ("Copy from Shortcut Ring").
    func testAnAppWithoutASuggestionGetsACopyOfTheGeneralRingAndNoRow() {
        var general = ShortcutRingSettings.default
        general[1] = ShortcutRingPlace(SystemShortcut.undo)
        Options.shared.ring = general
        let calculator = add(SuggestionFixtures.calculatorPath)
        let part = part(for: calculator)
        XCTAssertNil(part.suggestion)
        turn(part, general: false)
        XCTAssertEqual(calculator.ownRingPlaces, general.places)
        XCTAssertNil(part.suggestionNote.text)
        XCTAssertEqual(part.resetToDefaultsButton.title, "Copy from Shortcut Ring")
    }

    /// Nothing changes by itself: an app with a suggestion whose switch is on stays on the
    /// general ring (its page shown, its ring chosen at a press), no app is added to the
    /// list, and an entry from before is stored as before.
    func testNothingIsFilledOrAddedWithoutTheUser() throws {
        let figma = add(SuggestionFixtures.figmaPath, name: "Figma")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let before = try encoder.encode(figma)
        let part = part(for: figma)
        part.syncViewWithOptions()
        part.viewWillAppear()
        XCTAssertNil(figma.ring)
        XCTAssertTrue(figma.usesGeneralRing)
        XCTAssertEqual(try encoder.encode(figma), before)
        let choice = ShortcutRingChoice.make(
            front: ShortcutRingChoice.FrontApp(bundlePath: SuggestionFixtures.figmaPath, executablePath: nil),
            applications: Options.shared.application.applications, general: Options.shared.ring
        )
        XCTAssertEqual(choice, .general(Options.shared.ring))
        XCTAssertEqual(Options.shared.application.applications.count, 1)
        XCTAssertNil(Options.shared.application.applications.get(by: SuggestionFixtures.safariPath))
        // "Reset to Defaults" does nothing while the general ring is in use.
        XCTAssertFalse(part.resetToDefaultsButton.isEnabled)
        part.resetToDefaults.click(nil)
        XCTAssertNil(figma.ring)
    }

    /// The quiet line fits two lines when it says how many places the layout leaves empty.
    func testTheSuggestionLineFitsTwoLines() throws {
        let long = add(SuggestionFixtures.figmaPath, name: "Adobe Lightroom Classic Long Edition")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 900), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        addTeardownBlock { window.close() }
        let part = part(for: long)
        window.contentView = part.view
        turn(part, general: false)
        part.view.layoutSubtreeIfNeeded()
        let width = PreferencesGroupedForm.boxWidth(paneWidth: ApplicationDetailViewController.paneWidth)
            - 2 * PreferencesGroupedForm.rowHorizontalInset
        XCTAssertGreaterThan(width, 200)
        XCTAssertNil(ApplicationRingPartViewController.suggestionNote(emptyPlaces: 0, startedFromIt: true))
        let font = PreferencesGroupedForm.explanationFont
        let twoLines = 2 * ceil(font.ascender - font.descender + font.leading) + 2
        for started in [true, false] {
            for empty in [1, 3] {
                let text = try XCTUnwrap(ApplicationRingPartViewController.suggestionNote(emptyPlaces: empty, startedFromIt: started))
                let height = (text as NSString).boundingRect(
                    with: NSSize(width: width, height: 1000), options: [.usesLineFragmentOrigin], attributes: [.font: font]
                ).height
                XCTAssertLessThanOrEqual(height, twoLines, text)
            }
        }
    }

    /// A ring of the app's own that did not start from the suggestion (made before there
    /// were suggestions, as a copy of the general ring, or read from the settings and
    /// changed): after "Use Suggested Shortcuts" it started from them, also after a change;
    /// Undo brings back the ring and what it knew; Redo the fill again. The button says
    /// what it does: "Use Suggested Shortcuts", then "Undo" for a moment.
    func testARingMadeByHandStartsFromTheSuggestionOnceUseSuggestedShortcutsFillsIt() throws {
        let figma = add(SuggestionFixtures.figmaPath, name: "Figma")
        figma.setUsesGeneralRing(false, general: .default, suggested: nil)
        let byHand = try XCTUnwrap(figma.ownRingPlaces)
        let undo = UndoManager()
        undo.groupsByEvent = false
        let part = part(for: figma, undo: undo)
        let suggestion = figmaSuggestion
        func startedFromSuggestion(_ part: ApplicationRingPartViewController) -> Bool {
            XCTAssertNil(part.suggestionNote.text, "the layout types every key: no line")
            return part.ringStartedFromSuggestion(suggested: suggestion)
        }
        XCTAssertFalse(startedFromSuggestion(part))
        XCTAssertEqual(part.resetToDefaultsButton.title, "Use Suggested Shortcuts")
        XCTAssertTrue(part.resetToDefaultsButton.isEnabled, "the ring is not the suggestion")

        undo.beginUndoGrouping()
        XCTAssertTrue(part.resetToDefaultsButton.sendAction(part.resetToDefaultsButton.action, to: part.resetToDefaultsButton.target))
        undo.endUndoGrouping()
        XCTAssertEqual(figma.ownRingPlaces, figmaSuggestion)
        XCTAssertTrue(startedFromSuggestion(part))
        XCTAssertEqual(part.resetToDefaultsButton.title, "Undo")
        figma.ring?[0] = ShortcutRingPlace(SystemShortcut.find)
        part.syncViewWithOptions()
        XCTAssertTrue(startedFromSuggestion(part), "filled from them, then changed")
        figma.ring?[0] = figmaSuggestion[0]
        part.syncViewWithOptions()

        undo.undo()
        XCTAssertEqual(figma.ownRingPlaces, byHand)
        XCTAssertFalse(startedFromSuggestion(part))
        undo.redo()
        XCTAssertTrue(startedFromSuggestion(part))

        // A ring read from the settings knows only its places: the same as the suggestion,
        // it started from them; changed, it did not.
        let read = try JSONDecoder().decode(Application.self, from: JSONEncoder().encode(figma))
        XCTAssertEqual(read.ring, figma.ring)
        XCTAssertFalse(try XCTUnwrap(read.ring).startedFromSuggestion)
        Options.shared.application.applications = list([read])
        let again = self.part(for: read)
        XCTAssertTrue(startedFromSuggestion(again))
        read.ring?[3] = .empty
        again.syncViewWithOptions()
        XCTAssertFalse(startedFromSuggestion(again))
    }

    /// On a layout that leaves places of the suggestion empty: the line says how many
    /// "Use Suggested Shortcuts" would leave empty.
    func testARingMadeByHandSaysHowManyPlacesTheSuggestionLeavesEmpty() throws {
        let german = try SuggestionFixtures.layout("com.apple.keylayout.German")
        ShortcutRingSuggestions.layout = { german }
        let finder = add(SuggestionFixtures.finderPath, name: "Finder")
        finder.setUsesGeneralRing(false, general: .default, suggested: nil)
        let part = part(for: finder)
        XCTAssertEqual(
            part.suggestionNote.text,
            "Use Suggested Shortcuts leaves 2 places empty: their keys can't be typed on this keyboard layout."
        )
        XCTAssertEqual(
            ApplicationRingPartViewController.suggestionNote(emptyPlaces: 1, startedFromIt: false),
            "Use Suggested Shortcuts leaves 1 place empty: its keys can't be typed on this keyboard layout."
        )
    }

    /// A ring filled from a suggestion is ordinary places: it travels in a settings file
    /// and comes back the same, with nothing left out.
    func testAFilledRingRoundTripsThroughTheSettingsFile() throws {
        let source = Options()
        source.defaults = TestDefaults.make(for: self)
        let german = try SuggestionFixtures.layout("com.apple.keylayout.German")
        let spotify = Application(path: "/Applications/Spotify.app")
        spotify.setUsesGeneralRing(false, general: .default, suggested: try SuggestionFixtures.app("Spotify").places(on: german))
        let figma = Application(path: SuggestionFixtures.figmaPath)
        figma.setUsesGeneralRing(false, general: .default, suggested: figmaSuggestion)
        source.application.applications.append(spotify)
        source.application.applications.append(figma)
        let data = try SettingsFile.export(from: source, now: Date(timeIntervalSinceReferenceDate: 0)).get()

        let contents = try SettingsFile.read(data).get()
        XCTAssertEqual(contents.leftOutCount, 0)
        XCTAssertEqual(contents.applications?.map(\.ring), [spotify.ring, figma.ring])
        let target = Options()
        target.defaults = TestDefaults.make(for: self)
        target.readOptions()
        XCTAssertTrue(SettingsFile.apply(contents, to: target))
        XCTAssertEqual(target.application.applications.get(by: SuggestionFixtures.figmaPath)?.ring, figma.ring)
        XCTAssertEqual(target.application.applications.get(by: "/Applications/Spotify.app")?.ring, spotify.ring)
    }
}
