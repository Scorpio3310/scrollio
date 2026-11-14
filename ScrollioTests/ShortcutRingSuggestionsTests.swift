//
//  ShortcutRingSuggestionsTests.swift
//  ScrollioTests
//
//  The Shortcut Ring suggested for popular apps (`ShortcutRingSuggestions`): the shipped
//  file and what is in it, finding an app by its bundle identifier, the keys a suggestion
//  becomes on the US layout and on layouts where letters and signs sit elsewhere, the
//  safety rules over the whole file, the switch "Use the general ring" and "Use
//  Suggested Shortcuts" with its Undo on an app's page, that nothing is filled or added
//  without the user, and a filled ring in a settings file.
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

    static let identifiers: [String: String] = [
        figmaPath: "com.figma.Desktop",
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

    /// The app carries the file, and it reads: fifty apps, eight places each, a place left
    /// empty only with its reason; names fit a label, symbols are on this Mac, keys are
    /// one character or a named key.
    func testTheShippedFileReadsWithFiftyAppsOfEightPlaces() throws {
        XCTAssertEqual(catalog.apps.count, 50)
        var empty: [String] = []
        var identifiers: [String] = []
        for app in catalog.apps {
            XCTAssertEqual(app.slots.count, ShortcutRingSettings.placeCount, app.appName)
            XCTAssertFalse(app.bundleIdentifiers.isEmpty, app.appName)
            identifiers += app.bundleIdentifiers.map { $0.lowercased() }
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
                    XCTAssertEqual(place.modifierless, place.keys.modifiers.isEmpty, what)
                }
            }
        }
        XCTAssertEqual(empty, ["Mail ring-place-right", "Mail ring-place-bottom", "Mail ring-place-left"])
        XCTAssertEqual(Set(identifiers).count, identifiers.count, "every bundle identifier names one app")
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
    /// back, ends a call or quits; Excel's Delete Cells (where every other app zooms out)
    /// gave way to the font size pair. The deletes left are each taken back by the app's
    /// Undo or a bin, or asked about first.
    func testNoPlaceIsDestructive() throws {
        let never: Set<String> = [
            "Delete Cells", "Insert Cells", "Leave Call", "Leave Meeting", "Delete Now", "Empty Trash", "Quit", "Force Quit",
            "Close Window",
        ]
        let recoverable: Set<String> = [
            "Finder: Move to Trash", "Microsoft Outlook: Delete", "Photos: Delete",
            "Final Cut Pro: Ripple Delete", "Adobe Premiere Pro: Ripple Delete", "DaVinci Resolve: Ripple Delete",
        ]
        for app in catalog.apps {
            for place in app.slots.compactMap(\.place) {
                let what = "\(app.appName): \(place.name)"
                XCTAssertFalse(never.contains(place.name), what)
                if place.name.contains("Delete") || place.name.contains("Trash") {
                    XCTAssertTrue(recoverable.contains(what), what)
                }
            }
        }
        let excel = try SuggestionFixtures.app("Microsoft Excel")
        XCTAssertEqual(excel.slots[0].place?.name, "Increase Font Size")
        XCTAssertEqual(excel.slots[4].place?.name, "Decrease Font Size")
    }

    /// A key without modifiers only in apps whose canvas, timeline or player takes it
    /// (creative and CAD apps, Photos, Spotify); never in apps with text fields as their
    /// main surface. An alternative always has modifiers.
    func testKeysWithoutModifiersAreOnlyInCanvasApps() {
        let canvasApps: Set<String> = [
            "Adobe After Effects", "Adobe Lightroom Classic", "Adobe Premiere Pro", "Autodesk Fusion", "Blender", "Cinema 4D",
            "Final Cut Pro", "Logic Pro", "Photos", "Rhinoceros", "SketchUp", "Spotify",
        ]
        var withoutModifiers: Set<String> = []
        for app in catalog.apps {
            for place in app.slots.compactMap(\.place) {
                if place.keys.modifiers.isEmpty {
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

        // ⇧⌘. is ⌘> on US: ">" is Shift and the key left of Y on German; "<" needs no Shift.
        let notes = try SuggestionFixtures.app("Notes").places(on: german)
        let zoomIn = try XCTUnwrap(ShortcutRingPlace.keyCombination(named: notes[0].action))
        XCTAssertEqual(german.commandShift[zoomIn.code], ">")
        XCTAssertEqual(zoomIn.modifiers, CGEventFlags([.maskShift, .maskCommand]).rawValue)
        let zoomOut = try XCTUnwrap(ShortcutRingPlace.keyCombination(named: notes[4].action))
        XCTAssertEqual(german.command[zoomOut.code], "<")
        XCTAssertEqual(zoomOut.modifiers, CGEventFlags.maskCommand.rawValue)

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

    /// On every QWERTZ layout the system has: a letter is the key that types it, and a
    /// place whose character needs Option takes its alternative or stays empty; nothing
    /// is sent with a key that types another character.
    func testOnQWERTZLayoutsNoPlaceSendsAnotherCharacter() throws {
        var checked = 0
        for id in ["com.apple.keylayout.German", "com.apple.keylayout.Slovenian", "com.apple.keylayout.SwissGerman"] {
            guard let source = SuggestionFixtures.inputSource(id), let layout = KeyboardLayoutLayers.of(source) else { continue }
            checked += 1
            for app in catalog.apps {
                for (slot, place) in zip(app.slots, app.places(on: layout)) {
                    guard let suggested = slot.place else { continue }
                    let what = "\(id) \(app.appName): \(suggested.name)"
                    if ["[", "]", "\\"].contains(suggested.keys.character) {
                        switch suggested.alternative {
                        case .listed(let shortcut)?: XCTAssertEqual(place, ShortcutRingPlace(shortcut), what)
                        case .keys?: XCTAssertNotEqual(place.action, "", what)
                        case nil: XCTAssertEqual(place, .empty, what)
                        }
                        continue
                    }
                    guard let key = ShortcutRingPlace.keyCombination(named: place.action) else { continue }
                    if KeyCode.usLetterKeyCodes[suggested.keys.character] != nil {
                        let layer = suggested.keys.modifiers.contains(.maskCommand) ? layout.command : layout.plain
                        XCTAssertEqual(layer[key.code]?.lowercased(), suggested.keys.character, what)
                    }
                    XCTAssertEqual(key.modifiers & CGEventFlags.maskAlternate.rawValue,
                                   suggested.keys.modifiers.rawValue & CGEventFlags.maskAlternate.rawValue, "no Option added: \(what)")
                }
            }
        }
        guard checked > 0 else { throw XCTSkip("no QWERTZ layout on this Mac") }
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

    /// The page: turning the switch off fills the ring from the suggestion, and the row
    /// says the ring started from it (its button off, nothing to do); after a change the
    /// row offers it again, the button fills all eight places, Undo takes it back and
    /// Redo puts it back. The general ring is never touched.
    func testThePageFillsFromTheSuggestionAndUseSuggestedShortcutsHasUndo() throws {
        let figma = add(SuggestionFixtures.figmaPath, name: "Figma")
        let undo = UndoManager()
        undo.groupsByEvent = false
        let part = part(for: figma, undo: undo)
        XCTAssertNotNil(part.suggestion)
        XCTAssertTrue(part.suggestionRow.isHidden, "the general ring: no row")
        XCTAssertNil(figma.ring, "showing the page fills nothing")

        turn(part, general: false)
        XCTAssertEqual(figma.ownRingPlaces, figmaSuggestion)
        XCTAssertFalse(part.suggestionRow.isHidden)
        XCTAssertEqual(part.suggestionRow.explanation, "The ring started from the shortcuts suggested for Figma.")
        XCTAssertFalse(part.useSuggestedButton.isEnabled)
        XCTAssertNotNil(part.ringController)

        figma.ring?[0] = ShortcutRingPlace(SystemShortcut.find)
        figma.ring?[3] = .empty
        part.syncViewWithOptions()
        XCTAssertEqual(part.suggestionRow.explanation, "Fills all eight places with the shortcuts suggested for Figma.")
        XCTAssertTrue(part.useSuggestedButton.isEnabled)
        let edited = try XCTUnwrap(figma.ownRingPlaces)

        undo.beginUndoGrouping()
        XCTAssertTrue(part.useSuggestedButton.sendAction(part.useSuggestedButton.action, to: part.useSuggestedButton.target))
        undo.endUndoGrouping()
        XCTAssertEqual(figma.ownRingPlaces, figmaSuggestion)
        XCTAssertFalse(part.useSuggestedButton.isEnabled)
        XCTAssertEqual(undo.undoActionName, "Use Suggested Shortcuts")

        undo.undo()
        XCTAssertEqual(figma.ownRingPlaces, edited)
        XCTAssertTrue(part.useSuggestedButton.isEnabled)
        undo.redo()
        XCTAssertEqual(figma.ownRingPlaces, figmaSuggestion)
        XCTAssertEqual(Options.shared.ring, .default)

        // Back to the general ring: the row goes, the own ring is kept for later.
        turn(part, general: true)
        XCTAssertTrue(part.suggestionRow.isHidden)
        XCTAssertEqual(figma.ring?.places, figmaSuggestion)
    }

    /// Without a suggestion the part is as before: no row, and the switch copies the
    /// general ring.
    func testAnAppWithoutASuggestionGetsACopyOfTheGeneralRingAndNoRow() {
        var general = ShortcutRingSettings.default
        general[1] = ShortcutRingPlace(SystemShortcut.undo)
        Options.shared.ring = general
        let calculator = add(SuggestionFixtures.calculatorPath)
        let part = part(for: calculator)
        XCTAssertNil(part.suggestion)
        turn(part, general: false)
        XCTAssertEqual(calculator.ownRingPlaces, general.places)
        XCTAssertTrue(part.suggestionRow.isHidden)
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
        // The button does nothing while the general ring is in use.
        part.useSuggestedClick(nil)
        XCTAssertNil(figma.ring)
    }

    /// The row's line fits two lines, also for an app with a long name.
    func testTheSuggestionLineFitsTwoLines() throws {
        let long = add(SuggestionFixtures.figmaPath, name: "Adobe Lightroom Classic Long Edition")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 900), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        addTeardownBlock { window.close() }
        let part = part(for: long)
        window.contentView = part.view
        turn(part, general: false)
        part.view.layoutSubtreeIfNeeded()
        let width = part.suggestionRow.titleColumnWidth
        XCTAssertGreaterThan(width, 200)
        let font = PreferencesGroupedForm.explanationFont
        let twoLines = 2 * ceil(font.ascender - font.descender + font.leading) + 2
        for holdsIt in [true, false] {
            let text = ApplicationRingPartViewController.suggestionExplanation(holdsIt: holdsIt, name: long.displayName!)
            let height = (text as NSString).boundingRect(
                with: NSSize(width: width, height: 1000), options: [.usesLineFragmentOrigin], attributes: [.font: font]
            ).height
            XCTAssertLessThanOrEqual(height, twoLines, text)
        }
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
