//
//  SettingsFileTests.swift
//  ScrollioTests
//
//  The settings as one file (General › Settings file): what is in a file and what is not,
//  the frozen shape of a file, the checks of a file that is read, that an import changes
//  only what is on the allow-list and reaches every part of the app, the backup written
//  before it, the row in General and the sheet that says what a file holds.
//
//  Every test works on settings of its own: a store from `TestDefaults`, backups in a
//  temporary folder. The app's preferences and its Application Support folder are never
//  read or written, the menu bar icon is never hidden (the tests take
//  `StatusItemManager.setStatusItemVisible`), and no panel or sheet is shown.
//

import XCTest
@testable import Scrollio_Debug

// MARK: - What the tests share

/// Files as a user (or anyone else) could write them, in JSON text.
private enum Fixture {

    static let copyBinding = #"{"id":"11111111-1111-1111-1111-111111111111","triggerEvent":{"type":"mouse","code":4,"modifiers":0},"#
        + #""systemShortcutName":"copy","isEnabled":true,"createdAt":700000000}"#
    /// ⌥F5 runs a script with an argument.
    static let scriptBinding = #"{"id":"22222222-2222-2222-2222-222222222222","triggerEvent":{"type":"keyboard","code":96,"modifiers":524288},"#
        + #""systemShortcutName":"openTarget","isEnabled":true,"createdAt":700000001,"#
        + #""openTarget":{"path":"/Users/someone/bin/sync.sh","arguments":"--all","kind":"script"}}"#
    /// Button 5 opens an app; the binding is switched off.
    static let appBinding = #"{"id":"33333333-3333-3333-3333-333333333333","triggerEvent":{"type":"mouse","code":5,"modifiers":0},"#
        + #""systemShortcutName":"openTarget","isEnabled":false,"createdAt":700000002,"#
        + #""openTarget":{"path":"/Applications/Notes.app","bundleID":"com.apple.Notes","arguments":"","kind":"application"}}"#
    /// The Logitech "Back" button (Scrollio code 1006) copies.
    static let logiBinding = #"{"id":"44444444-4444-4444-4444-444444444444","triggerEvent":{"type":"mouse","code":1006,"modifiers":0},"#
        + #""systemShortcutName":"copy","isEnabled":true,"createdAt":700000003}"#

    static func file(_ settings: String, format: String = #""scrollio-settings""#, version: String = "1", more: String = "") -> Data {
        return Data((#"{"format":"# + format + #","formatVersion":"# + version + more + #","settings":{"# + settings + "}}").utf8)
    }

    static func contents(_ settings: String, file: StaticString = #filePath, line: UInt = #line) throws -> SettingsFile.Contents {
        switch SettingsFile.read(Fixture.file(settings)) {
        case .success(let contents): return contents
        case .failure(let problem):
            XCTFail("the file was refused: \(problem)", file: file, line: line)
            throw problem
        }
    }
}

/// The menu bar icon of the test host stays as it is: what an import would show or hide
/// is recorded instead.
private final class StatusItemRecorder {
    private let saved = StatusItemManager.setStatusItemVisible
    private(set) var calls: [Bool] = []

    init() {
        StatusItemManager.setStatusItemVisible = { [weak self] in self?.calls.append($0) }
    }

    func restore() {
        StatusItemManager.setStatusItemVisible = saved
    }
}

/// Settings of a test's own, never the app's: an `Options` over a store in a temporary
/// folder, and a center whose backups go to another temporary folder.
private final class OwnSettings {
    let options = Options()
    let store: TestDefaults
    let center = SettingsFileCenter()
    let backupFolder: URL
    private(set) var logLines: [String] = []

    init(for test: XCTestCase) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScrollioTests-backups-\(UUID().uuidString)", isDirectory: true)
        store = TestDefaults.makeStore(for: test)
        backupFolder = folder
        test.addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let options = self.options
        options.defaults = store.defaults
        center.options = { options }
        center.backups = SettingsBackups(directory: folder)
        center.bundleInfo = { ["CFBundleShortVersionString": "1.2.3", "CFBundleVersion": "456"] }
        center.afterImport = {}
        center.log = { [weak self] in self?.logLines.append($0) }
    }

    var stored: [String: Any] {
        return store.defaults.persistentDomain(forName: store.suiteName) ?? [:]
    }
}

private func temporaryFolder(for test: XCTestCase) throws -> URL {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScrollioTests-settings-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    test.addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
    return folder
}

// MARK: - The format

final class SettingsFileFormatTests: XCTestCase {

    private var statusItem: StatusItemRecorder!

    override func setUp() {
        super.setUp()
        statusItem = StatusItemRecorder()
    }

    override func tearDown() {
        statusItem.restore()
        super.tearDown()
    }

    private static let moment = Date(timeIntervalSince1970: 1_794_476_527)   // 2026-11-12 09:42:07 UTC

    // MARK: What is in a file, what is not

    /// The two lists, frozen. A name in a file is the UserDefaults key of the setting and
    /// never changes; a key that moves from one list to the other changes what an import
    /// can do, so it is spelled out here.
    func testTheTwoListsAreFrozen() {
        XCTAssertEqual(SettingsFile.exportedKeys.map(\.name), [
            "smooth", "reverse", "reverseVertical", "reverseHorizontal", "step", "speed", "duration", "deadZone",
            "smoothSimTrackpad", "smoothVertical", "smoothHorizontal", "dash", "toggle", "block",
            "thumbWheelSettings", "allowlist", "applications", "buttonBindings", "mouseGestureSettings",
            "logiWheelSettings", "logiMouseSettings", "hideStatusItem",
        ])
        XCTAssertEqual(SettingsFile.leftOut.map { $0.key + ($0.isPrefix ? "*" : "") }, [
            "optionsExist", "welcomeGuideCompletedVersion", "preferencesSelectedPane", "scrollingAdvancedExpanded",
            "generalAdvancedExpanded", "durationForOtherTrackpadState", "scrollTuning", "logitechFeatureCache",
            "Logi*", "SU*", "NSStatusItem *", "NSWindow Frame *", "NSSplitView Subview Frames *",
            "NSNav*", "NSOSPLastRootDirectory",
        ])
        XCTAssertEqual(SettingsFile.managedSwitchName, "managedByScrollio")
        for entry in SettingsFile.leftOut {
            XCTAssertFalse(entry.reason.isEmpty, entry.key)
        }
        // The file's own names.
        XCTAssertEqual(SettingsFile.formatName, "scrollio-settings")
        XCTAssertEqual(SettingsFile.formatVersion, 1)
        XCTAssertEqual(SettingsFile.fileExtension, "json")
        XCTAssertEqual(
            [SettingsFile.Field.format, SettingsFile.Field.formatVersion, SettingsFile.Field.appVersion,
             SettingsFile.Field.appBuild, SettingsFile.Field.exported, SettingsFile.Field.settings],
            ["format", "formatVersion", "appVersion", "appBuild", "exported", "settings"]
        )
    }

    /// Every key the app stores is on exactly one of the two lists. The settings are saved
    /// with every value set: a key that a later version adds to the saving and that is on
    /// neither list fails here, until someone decided whether a file holds it.
    func testEveryStoredKeyIsOnExactlyOneList() {
        let own = OwnSettings(for: self)
        XCTAssertNotNil(own.options.scroll.dash)
        XCTAssertNotNil(own.options.scroll.toggle)
        XCTAssertNotNil(own.options.scroll.block)
        own.options.saveOptions()

        let saved = Set(own.stored.keys)
        XCTAssertEqual(saved, Set(SettingsFile.exportedKeys.map(\.name) + ["optionsExist"]),
                       "what the app saves: every setting of a file, and the mark that settings exist")
        // What the rest of the app and macOS keep in the same preferences.
        let others = [
            WelcomeGuideProgress.key, PreferencesSplitViewController.selectedPaneDefaultsKey,
            PreferencesScrollingViewController.advancedExpandedDefaultsKey,
            PreferencesGeneralViewController.advancedExpandedDefaultsKey,
            LogiDeviceSession.featureCacheKeyForTests, "LogiVerboseTraceEnabled",
            "SUEnableAutomaticChecks", "SUAutomaticallyUpdate", "SULastCheckTime", "SUHasLaunchedBefore", "SUFeedURL",
            "NSStatusItem Visible Item-0", "NSStatusItem Preferred Position Item-0",
            "NSWindow Frame " + PreferencesWindowLayout.frameAutosaveName,
            "NSSplitView Subview Frames HIDDebug.FeaturesControls.v3",
            "NSNavLastRootDirectory", "NSNavPanelExpandedSizeForSaveMode", "NSOSPLastRootDirectory",
        ] + ScrollSettingsCleanup.retiredDefaultsKeys + LogiDebugPanel.autosaveNamesSnapshotForTests.map { "NSSplitView Subview Frames " + $0 }
        for key in saved.union(others) {
            XCTAssertNotEqual(SettingsFile.isExported(key), SettingsFile.isLeftOut(key), "\(key) is on both lists or on neither")
        }
        for key in others {
            XCTAssertTrue(SettingsFile.isLeftOut(key), key)
        }
        // Each setting of a file belongs to the group that saves it.
        XCTAssertEqual(Set(SettingsFile.exportedKeys.map(\.group)), Set(OptionsGroup.allCases))
    }

    // MARK: The shape of a file

    private func makeSource() -> OwnSettings {
        let own = OwnSettings(for: self)
        let options = own.options
        options.scroll.speed = 4.5
        options.scroll.toggle = nil
        options.thumbWheel = ThumbWheelSettings(function: .zoom, speed: 1.5, swapsDirection: true)
        let notes = Application(path: "/Applications/Notes.app")
        notes.inherit = false
        notes.scroll.speed = 2.5
        options.application.applications.append(notes)
        let trigger = RecordedEvent(type: .mouse, code: 4, modifiers: 0, deviceFilter: nil)
        let key = RecordedEvent(type: .keyboard, code: 96, modifiers: 524_288, deviceFilter: nil)
        options.buttons.binding = [
            ButtonBinding(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, triggerEvent: trigger,
                systemShortcutName: "missionControl", createdAt: Date(timeIntervalSinceReferenceDate: 700_000_000)
            ),
            ButtonBinding(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, triggerEvent: key,
                openTarget: OpenTargetPayload(path: "/Users/someone/bin/sync.sh", bundleID: nil, arguments: "--all", kind: .script),
                createdAt: Date(timeIntervalSinceReferenceDate: 700_000_001)
            ),
        ]
        options.logiWheel = LogiWheelSettings(managedByScrollio: true, mode: .ratchet)
        options.logiMouse = LogiMouseSettings(pointerDPI: 1600)
        return own
    }

    /// The text of a file, byte for byte: the format's name and version first, the settings
    /// under the names of the preferences, numbers as they are read, what is JSON in the
    /// preferences as JSON here. A change of this text is a change of the format.
    func testAnExportedFileHasThisShape() throws {
        let own = makeSource()
        let data = try SettingsFile.export(
            from: own.options, bundleInfo: ["CFBundleShortVersionString": "1.2.3", "CFBundleVersion": "456"], now: Self.moment
        ).get()
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertEqual(text, Self.frozenFile)
        // It is JSON, and small.
        XCTAssertNotNil(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertLessThan(data.count, 8 * 1024)
    }

    static let frozenFile = """
    {
      "format": "scrollio-settings",
      "formatVersion": 1,
      "appVersion": "1.2.3",
      "appBuild": "456",
      "exported": "2026-11-12T09:42:07Z",
      "settings": {
        "smooth": true,
        "reverse": true,
        "reverseVertical": true,
        "reverseHorizontal": true,
        "step": 33.6,
        "speed": 4.5,
        "duration": 3.69,
        "deadZone": 1.0,
        "smoothSimTrackpad": false,
        "smoothVertical": true,
        "smoothHorizontal": true,
        "dash": {
          "code": 58,
          "type": "keyboard"
        },
        "block": {
          "code": 55,
          "type": "keyboard"
        },
        "thumbWheelSettings": {
          "function": "zoom",
          "speed": 1.5,
          "swapsDirection": true
        },
        "allowlist": false,
        "applications": [
          {
            "displayName": "",
            "inherit": false,
            "path": "/Applications/Notes.app",
            "scroll": {
              "block": {
                "code": 55,
                "type": "keyboard"
              },
              "dash": {
                "code": 58,
                "type": "keyboard"
              },
              "deadZone": 1,
              "duration": 3.69,
              "reverse": true,
              "reverseHorizontal": true,
              "reverseVertical": true,
              "smooth": true,
              "smoothHorizontal": true,
              "smoothSimTrackpad": false,
              "smoothVertical": true,
              "speed": 2.5,
              "step": 33.6,
              "toggle": {
                "code": 56,
                "type": "keyboard"
              }
            }
          }
        ],
        "buttonBindings": [
          {
            "createdAt": 700000000,
            "id": "11111111-1111-1111-1111-111111111111",
            "isEnabled": true,
            "systemShortcutName": "missionControl",
            "triggerEvent": {
              "code": 4,
              "modifiers": 0,
              "type": "mouse"
            }
          },
          {
            "createdAt": 700000001,
            "id": "22222222-2222-2222-2222-222222222222",
            "isEnabled": true,
            "openTarget": {
              "arguments": "--all",
              "kind": "script",
              "path": "/Users/someone/bin/sync.sh"
            },
            "systemShortcutName": "openTarget",
            "triggerEvent": {
              "code": 96,
              "modifiers": 524288,
              "type": "keyboard"
            }
          }
        ],
        "mouseGestureSettings": {
          "clickAction": "missionControl",
          "deviceTracking": false,
          "downAction": "appExpose",
          "freezePointer": true,
          "hapticFeedback": true,
          "invertHorizontal": false,
          "leftAction": "moveSpaceLeft",
          "mode": "discrete",
          "rightAction": "moveSpaceRight",
          "trackingSpeed": 1,
          "upAction": "missionControl"
        },
        "logiWheelSettings": {
          "mode": "ratchet"
        },
        "logiMouseSettings": {
          "pointerDPI": 1600
        },
        "hideStatusItem": false
      }
    }

    """

    /// A file read back gives the settings it was made from, on another Mac's settings.
    func testAFileGivesBackTheSettingsItWasMadeFrom() throws {
        let source = makeSource()
        source.options.scroll.smooth = false
        source.options.scroll.reverse = false
        source.options.scroll.duration = 2.75
        source.options.scroll.step = 44.5
        source.options.scroll.smoothSimTrackpad = true
        source.options.scroll.dash = ScrollHotkey(type: .mouse, code: 4)
        source.options.application.allowlist = true
        var gesture = MouseGestureSettings.default
        gesture.invertHorizontal = true
        gesture.trackingSpeed = 2.5
        gesture.upAction = "appExpose"
        source.options.gesture = gesture
        source.options.logiWheel = LogiWheelSettings(managedByScrollio: true, mode: .freeSpin, smartShiftSensitivity: 37, scrollForce: 80)
        source.options.logiMouse = LogiMouseSettings(pointerDPI: 1600, hapticsOn: false, hapticStrength: 75, pressForce: 5000)
        source.options.general.hideStatusItem = true
        let data = try SettingsFile.export(from: source.options, now: Self.moment).get()

        let target = OwnSettings(for: self)
        target.options.readOptions()
        let contents = try SettingsFile.read(data).get()
        XCTAssertEqual(contents.groups, Set(OptionsGroup.allCases), "a file made by an export holds every group")
        XCTAssertEqual(contents.unreadableEntries, 0)
        XCTAssertTrue(SettingsFile.apply(contents, to: target.options))

        XCTAssertTrue(target.options.scroll == source.options.scroll)
        XCTAssertNil(target.options.scroll.toggle, "a hold key that was removed is none in the file and after it")
        XCTAssertEqual(target.options.thumbWheel, source.options.thumbWheel)
        XCTAssertEqual(target.options.buttons.binding, source.options.buttons.binding)
        XCTAssertEqual(target.options.buttons.binding.last?.openTarget?.path, "/Users/someone/bin/sync.sh")
        XCTAssertTrue(target.options.application.allowlist)
        XCTAssertEqual(target.options.application.applications.count, 1)
        let notes = try XCTUnwrap(target.options.application.applications.get(by: "/Applications/Notes.app"))
        XCTAssertFalse(notes.inherit)
        XCTAssertEqual(notes.scroll.speed, 2.5)
        XCTAssertEqual(target.options.gesture, gesture)
        XCTAssertEqual(target.options.logiMouse, source.options.logiMouse)
        XCTAssertEqual(target.options.logiWheel.mode, .freeSpin)
        XCTAssertEqual(target.options.logiWheel.smartShiftSensitivity, 37)
        XCTAssertEqual(target.options.logiWheel.scrollForce, 80)
        XCTAssertTrue(target.options.general.hideStatusItem)
        XCTAssertEqual(statusItem.calls.last, false, "the icon was hidden through the option's own path")
        // The header is for the reader.
        XCTAssertEqual(contents.header.exported, Self.moment)

        // And what the import left in the store is what the app itself writes: saved
        // again, a second export is the same file (but for who wrote it and when).
        target.options.flushPendingSaves()
        let again = try SettingsFile.export(
            from: target.options, bundleInfo: Bundle.main.infoDictionary ?? [:], now: Self.moment
        ).get()
        XCTAssertEqual(String(decoding: again, as: UTF8.self), String(decoding: data, as: UTF8.self))
    }

    // MARK: What stays on this Mac

    /// "Let Scrollio manage this mouse" is not in a file and is not taken from one: an
    /// import alone never makes Scrollio write to a mouse, and never stops it either.
    func testTheManageSwitchIsNeitherWrittenNorRead() throws {
        let source = makeSource()
        XCTAssertTrue(source.options.logiMouseManaged)
        let data = try SettingsFile.export(from: source.options, now: Self.moment).get()
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("managedByScrollio"))

        // Off on this Mac: off after the import, whatever a file says.
        let off = OwnSettings(for: self)
        off.options.readOptions()
        XCTAssertFalse(off.options.logiMouseManaged)
        XCTAssertTrue(SettingsFile.apply(try SettingsFile.read(data).get(), to: off.options))
        XCTAssertFalse(off.options.logiMouseManaged)
        XCTAssertEqual(off.options.logiWheel.mode, .ratchet, "the values came")
        let planted = try Fixture.contents(#""logiWheelSettings":{"managedByScrollio":true,"mode":"freeSpin","scrollForce":55}"#)
        XCTAssertTrue(SettingsFile.apply(planted, to: off.options))
        XCTAssertFalse(off.options.logiMouseManaged, "a file that says on does not switch it on")
        XCTAssertEqual(off.options.logiWheel.mode, .freeSpin)
        off.options.flushPendingSaves()
        let stored = try XCTUnwrap(off.store.defaults.data(forKey: "logiWheelSettings"))
        XCTAssertFalse(Options.decodeLogiWheelSettings(stored).managedByScrollio, "nor in the store")

        // On on this Mac: it stays on.
        let on = OwnSettings(for: self)
        on.options.readOptions()
        on.options.logiMouseManaged = true
        let silent = try Fixture.contents(#""logiWheelSettings":{"managedByScrollio":false,"mode":"smartShift"}"#)
        XCTAssertTrue(SettingsFile.apply(silent, to: on.options))
        XCTAssertTrue(on.options.logiMouseManaged)
        XCTAssertEqual(on.options.logiWheel.mode, .smartShift)
    }

    /// The Welcome Guide's progress, the updater's choices, the caches and the window
    /// state are not in a file.
    func testAFileHoldsNothingThatBelongsToThisMac() throws {
        let own = makeSource()
        let defaults = own.store.defaults
        defaults.set(1, forKey: "welcomeGuideCompletedVersion")
        defaults.set(true, forKey: "SUEnableAutomaticChecks")
        defaults.set("https://example.invalid/appcast.xml", forKey: "SUFeedURL")
        defaults.set(Data("{}".utf8), forKey: "logitechFeatureCache")
        defaults.set("general", forKey: "preferencesSelectedPane")
        defaults.set("0 0 720 640", forKey: "NSWindow Frame PreferencesWindow")
        let data = try SettingsFile.export(from: own.options, now: Self.moment).get()
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(root.keys), ["format", "formatVersion", "appVersion", "appBuild", "exported", "settings"])
        let settings = try XCTUnwrap(root["settings"] as? [String: Any])
        for name in settings.keys {
            XCTAssertTrue(SettingsFile.isExported(name), name)
        }
        XCTAssertEqual(settings.count, SettingsFile.exportedKeys.count - 1, "everything but the hold key that is none")
        let text = String(decoding: data, as: UTF8.self)
        for word in ["welcomeGuide", "optionsExist", "SUEnable", "SUFeedURL", "FeatureCache", "preferencesSelectedPane", "NSWindow", "autoLaunch"] {
            XCTAssertFalse(text.contains(word), word)
        }
    }

    // MARK: A file that is read

    func testAFileThatCannotBeUsedIsRefusedWithItsReason() {
        func problem(_ data: Data) -> SettingsFile.Problem? {
            if case .failure(let problem) = SettingsFile.read(data) { return problem }
            return nil
        }
        let speed = #""speed":3"#
        XCTAssertNil(problem(Fixture.file(speed)), "a file with one setting is a file")
        // Something else altogether.
        XCTAssertEqual(problem(Data()), .notASettingsFile)
        XCTAssertEqual(problem(Data("not json".utf8)), .notASettingsFile)
        XCTAssertEqual(problem(Data("[1,2,3]".utf8)), .notASettingsFile)
        XCTAssertEqual(problem(Data(#"{"settings":{"speed":3}}"#.utf8)), .notASettingsFile, "no format name")
        XCTAssertEqual(problem(Fixture.file(speed, format: #""mos-settings""#)), .notASettingsFile)
        XCTAssertEqual(problem(Fixture.file(speed, format: "1")), .notASettingsFile)
        // Cut off in the middle.
        XCTAssertEqual(problem(Fixture.file(speed).dropLast(3)), .notASettingsFile)
        // A newer format: refused, not guessed at.
        XCTAssertEqual(problem(Fixture.file(speed, version: "2")), .newerFormat)
        XCTAssertEqual(problem(Fixture.file(speed, version: "999")), .newerFormat)
        for version in ["0", "-1", "1.5", "true", #""1""#, "null", "[1]"] {
            XCTAssertEqual(problem(Fixture.file(speed, version: version)), .damaged("formatVersion"), version)
        }
        XCTAssertEqual(problem(Data(#"{"format":"scrollio-settings","settings":{"speed":3}}"#.utf8)), .damaged("formatVersion"))
        // No settings, or none this version knows.
        XCTAssertEqual(problem(Data(#"{"format":"scrollio-settings","formatVersion":1}"#.utf8)), .damaged("settings"))
        XCTAssertEqual(problem(Data(#"{"format":"scrollio-settings","formatVersion":1,"settings":[]}"#.utf8)), .damaged("settings"))
        XCTAssertEqual(problem(Fixture.file("")), .nothingToImport)
        XCTAssertEqual(problem(Fixture.file(#""warpDrive":true,"SUFeedURL":"https://example.invalid""#)), .nothingToImport)
        // Too large: refused before it is parsed.
        var large = Fixture.file(speed)
        large.append(Data(repeating: 0x20, count: SettingsFile.maximumFileSize))
        XCTAssertEqual(problem(large), .tooLarge)
        XCTAssertEqual(SettingsFile.maximumFileSize, 2 * 1024 * 1024)
    }

    /// A file may bring a thousand buttons and keys and a thousand apps, far more than
    /// anybody sets by hand. 2 MB hold twelve times as many bindings and a hundred times
    /// as many apps, and putting those in effect took seconds on the main thread; such a
    /// file is refused before an entry is decoded.
    func testAFileWithTooManyEntriesIsRefused() throws {
        XCTAssertEqual(SettingsFile.maximumEntries, 1000)
        func bindings(_ count: Int, from start: Int = 0) -> String {
            return (start..<start + count).map { index in
                #"{"id":"88888888-8888-8888-8888-"# + String(format: "%012d", index)
                    + #"","triggerEvent":{"type":"mouse","code":4,"modifiers":0},"systemShortcutName":"copy","isEnabled":true,"createdAt":1}"#
            }.joined(separator: ",")
        }
        func apps(_ count: Int) -> String {
            return (0..<count).map { #"{"path":"/Applications/App \#($0).app"}"# }.joined(separator: ",")
        }
        func problem(_ settings: String) -> SettingsFile.Problem? {
            if case .failure(let problem) = SettingsFile.read(Fixture.file(settings)) { return problem }
            return nil
        }
        let full = try Fixture.contents(#""buttonBindings":["# + bindings(1000) + #"],"applications":["# + apps(1000) + "]")
        XCTAssertEqual(full.bindings?.count, 1000)
        XCTAssertEqual(full.applications?.count, 1000)
        XCTAssertEqual(problem(#""buttonBindings":["# + bindings(1001) + "]"), .tooManyEntries)
        XCTAssertEqual(problem(#""applications":["# + apps(1001) + "]"), .tooManyEntries)
        XCTAssertEqual(problem(#""speed":3,"applications":["# + apps(1001) + "]"), .tooManyEntries, "the whole file, not only that part")
        // Each app's own buttons count with the others.
        let app = #"{"path":"/Applications/Busy.app","buttons":{"binding":["# + bindings(600, from: 5000) + "]}}"
        XCTAssertNil(problem(#""buttonBindings":["# + bindings(400) + #"],"applications":["# + app + "]"))
        XCTAssertEqual(problem(#""buttonBindings":["# + bindings(401) + #"],"applications":["# + app + "]"), .tooManyEntries)
    }

    /// From a file on disk never more than the limit is read; a folder or a missing file
    /// is said as that.
    func testAFileOnDiskIsReadUpToTheLimit() throws {
        let folder = try temporaryFolder(for: self)
        let good = folder.appendingPathComponent("good.json")
        try Fixture.file(#""speed":3"#).write(to: good)
        XCTAssertEqual(try SettingsFile.read(contentsOf: good).get().scrollNumbers, ["speed": 3])

        let large = folder.appendingPathComponent("large.json")
        var data = Fixture.file(#""speed":3"#)
        data.append(Data(repeating: 0x20, count: SettingsFile.maximumFileSize + 4096))
        try data.write(to: large)
        guard case .failure(.tooLarge) = SettingsFile.read(contentsOf: large) else {
            return XCTFail("a file over the limit was read")
        }
        guard case .failure(.cannotRead(let reason)) = SettingsFile.read(contentsOf: folder.appendingPathComponent("missing.json")) else {
            return XCTFail("a file that is not there was read")
        }
        XCTAssertFalse(reason.isEmpty)
        // A file whose size says it is too large is refused before it is read: it is
        // sparse here, so there is nothing in it to read.
        let sparse = folder.appendingPathComponent("sparse.json")
        XCTAssertTrue(FileManager.default.createFile(atPath: sparse.path, contents: nil))
        let handle = try FileHandle(forWritingTo: sparse)
        try handle.truncate(atOffset: UInt64(SettingsFile.maximumFileSize) + 1)
        try handle.close()
        guard case .failure(.tooLarge) = SettingsFile.read(contentsOf: sparse) else {
            return XCTFail("a file over the limit was opened for reading")
        }
    }

    /// Only a regular file is read. A folder is no settings file; a named pipe called
    /// "settings.json" held the read (on the main thread, in the app) until somebody wrote
    /// to it, and is now refused at once.
    func testWhatIsNotARegularFileIsRefusedWithoutWaiting() throws {
        let folder = try temporaryFolder(for: self)
        guard case .failure(.notASettingsFile) = SettingsFile.read(contentsOf: folder) else {
            return XCTFail("a folder was read")
        }
        let pipe = folder.appendingPathComponent("settings.json")
        XCTAssertEqual(mkfifo(pipe.path, 0o600), 0)
        let returned = expectation(description: "the read of a named pipe returned")
        var result: Result<SettingsFile.Contents, SettingsFile.Problem>?
        DispatchQueue.global().async {
            let outcome = SettingsFile.read(contentsOf: pipe)
            DispatchQueue.main.async {
                result = outcome
                returned.fulfill()
            }
        }
        let outcome = XCTWaiter().wait(for: [returned], timeout: 5)
        if outcome != .completed {
            // Let the read go, so that the thread does not stay behind for the rest of the run.
            let writer = open(pipe.path, O_WRONLY | O_NONBLOCK)
            if writer >= 0 { close(writer) }
            return XCTFail("the read of a named pipe was still waiting after five seconds")
        }
        guard case .failure(.notASettingsFile)? = result else {
            return XCTFail("a named pipe was read: \(String(describing: result))")
        }
        // A link to a settings file is the file.
        let real = folder.appendingPathComponent("real.json")
        try Fixture.file(#""speed":3"#).write(to: real)
        let link = folder.appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        XCTAssertEqual(try SettingsFile.read(contentsOf: link).get().scrollNumbers, ["speed": 3])
    }

    /// The frozen text, read: what a file of this shape gives. (The test above only says
    /// that an export writes this text; this one says that this text is understood, so a
    /// file written today stays readable.)
    func testTheFrozenFileReadsAsTheSettingsItHolds() throws {
        let contents = try SettingsFile.read(Data(Self.frozenFile.utf8)).get()
        XCTAssertEqual(contents.groups, Set(OptionsGroup.allCases))
        XCTAssertEqual(contents.header, SettingsFile.Header(appVersion: "1.2.3", appBuild: "456", exported: Self.moment))
        XCTAssertEqual(contents.unreadableEntries, 0)
        // Scrolling
        XCTAssertEqual(contents.scrollSwitches, [
            "smooth": true, "reverse": true, "reverseVertical": true, "reverseHorizontal": true,
            "smoothSimTrackpad": false, "smoothVertical": true, "smoothHorizontal": true,
        ])
        XCTAssertEqual(contents.scrollNumbers, ["step": 33.6, "speed": 4.5, "duration": 3.69, "deadZone": 1.0])
        XCTAssertEqual(contents.scrollHotkeys, [
            "dash": ScrollHotkey(type: .keyboard, code: 58), "block": ScrollHotkey(type: .keyboard, code: 55),
        ], "no \"toggle\": that hold key is none")
        XCTAssertEqual(contents.thumbWheel, ThumbWheelSettings(function: .zoom, speed: 1.5, swapsDirection: true))
        // Apps
        XCTAssertEqual(contents.allowlist, false)
        XCTAssertEqual(contents.applications?.count, 1)
        let app = try XCTUnwrap(contents.applications?.first)
        XCTAssertEqual(app.path, "/Applications/Notes.app")
        XCTAssertEqual(app.displayName, "")
        XCTAssertFalse(app.inherit)
        XCTAssertNil(app.buttons)
        XCTAssertEqual(app.scroll.speed, 2.5)
        XCTAssertEqual(app.scroll.step, 33.6)
        XCTAssertEqual(app.scroll.duration, 3.69)
        XCTAssertEqual(app.scroll.deadZone, 1)
        XCTAssertEqual(app.scroll.toggle, ScrollHotkey(type: .keyboard, code: 56))
        XCTAssertTrue(app.scroll.smooth)
        // Buttons and keys
        let bindings = try XCTUnwrap(contents.bindings)
        XCTAssertEqual(bindings.map(\.id.uuidString), ["11111111-1111-1111-1111-111111111111", "22222222-2222-2222-2222-222222222222"])
        XCTAssertEqual(bindings.map(\.systemShortcutName), ["missionControl", "openTarget"])
        XCTAssertEqual(bindings.map(\.isEnabled), [true, true])
        XCTAssertEqual(bindings.map(\.createdAt), [Date(timeIntervalSinceReferenceDate: 700_000_000), Date(timeIntervalSinceReferenceDate: 700_000_001)])
        XCTAssertEqual(bindings[0].triggerEvent, RecordedEvent(type: .mouse, code: 4, modifiers: 0, deviceFilter: nil))
        XCTAssertNil(bindings[0].openTarget)
        XCTAssertEqual(bindings[1].triggerEvent, RecordedEvent(type: .keyboard, code: 96, modifiers: 524_288, deviceFilter: nil))
        XCTAssertEqual(bindings[1].openTarget, OpenTargetPayload(path: "/Users/someone/bin/sync.sh", bundleID: nil, arguments: "--all", kind: .script))
        XCTAssertEqual(contents.launchActions.map(\.target.path), ["/Users/someone/bin/sync.sh"])
        // Gestures, Logitech, General
        XCTAssertEqual(contents.gesture, MouseGestureSettings.default)
        XCTAssertEqual(contents.logiWheel, LogiWheelSettings(managedByScrollio: false, mode: .ratchet), "the switch is not in a file")
        XCTAssertEqual(contents.logiMouse, LogiMouseSettings(pointerDPI: 1600))
        XCTAssertEqual(contents.hidesMenuBarIcon, false)
    }

    /// Each name on the allow-list is checked for its type; a wrong one refuses the file
    /// and says which. Inside what the preferences keep as JSON, the decoders of the
    /// preferences decide, with their tolerance.
    func testEachSettingIsCheckedForItsType() throws {
        let wrong: [(String, String)] = [
            (#""smooth":1"#, "smooth"),
            (#""reverse":"yes""#, "reverse"),
            (#""smoothSimTrackpad":null"#, "smoothSimTrackpad"),
            (#""speed":"fast""#, "speed"),
            (#""step":true"#, "step"),
            (#""duration":[3]"#, "duration"),
            (#""deadZone":{"value":1}"#, "deadZone"),
            (#""dash":58"#, "dash"),
            (#""toggle":{"type":"keyboard"}"#, "toggle"),
            (#""block":{"type":"pedal","code":3}"#, "block"),
            (#""buttonBindings":{}"#, "buttonBindings"),
            (#""applications":"none""#, "applications"),
            (#""allowlist":0"#, "allowlist"),
            (#""mouseGestureSettings":[]"#, "mouseGestureSettings"),
            (#""mouseGestureSettings":{"upAction":5}"#, "mouseGestureSettings"),
            (#""logiWheelSettings":1"#, "logiWheelSettings"),
            (#""logiMouseSettings":"x""#, "logiMouseSettings"),
            (#""thumbWheelSettings":null"#, "thumbWheelSettings"),
            (#""hideStatusItem":"no""#, "hideStatusItem"),
        ]
        for (settings, name) in wrong {
            // One good setting next to it: the file is refused as a whole.
            guard case .failure(let problem) = SettingsFile.read(Fixture.file(#""reverseVertical":true,"# + settings)) else {
                XCTFail("\(settings) was taken")
                continue
            }
            XCTAssertEqual(problem, .damaged(name), settings)
        }

        // The tolerance of the preferences' own decoders: one bad value falls back, the
        // others are kept.
        let tolerant = try Fixture.contents(
            #""thumbWheelSettings":{"function":"teleport","speed":2,"swapsDirection":"x"},"#
                + #""logiMouseSettings":{"pointerDPI":"fast","hapticStrength":250},"#
                + #""mouseGestureSettings":{"mode":"telepathy","trackingSpeed":99,"upAction":"appExpose"},"#
                + #""speed":1e300"#
        )
        XCTAssertEqual(tolerant.thumbWheel, ThumbWheelSettings(function: .scroll, speed: 2, swapsDirection: false))
        XCTAssertEqual(tolerant.logiMouse, LogiMouseSettings(hapticStrength: 100))
        XCTAssertEqual(tolerant.gesture?.mode, .discrete)
        XCTAssertEqual(tolerant.gesture?.trackingSpeed, MouseGestureSettings.trackingSpeedRange.upperBound)
        XCTAssertEqual(tolerant.gesture?.upAction, "appExpose")
        // And the clean-up of the launch: a Speed the slider does not have is brought in.
        let own = OwnSettings(for: self)
        own.options.readOptions()
        XCTAssertTrue(SettingsFile.apply(tolerant, to: own.options))
        XCTAssertEqual(own.options.scroll.speed, ScrollSliderSetting.speed.range.upperBound)
    }

    /// A number too large to be one (-1e999) inside what the preferences keep as JSON.
    /// JSONSerialization reads it as negative infinity, and writing that back raised an
    /// exception that nothing caught: reading such a file ended the app. The part is
    /// refused as damaged; in the two lists the entry is left out like any other that
    /// cannot be read. (Without the fix this test does not fail, it ends the run.)
    func testANumberTooLargeToBeOneIsRefusedNotThrown() throws {
        func problem(_ settings: String) -> SettingsFile.Problem? {
            if case .failure(let problem) = SettingsFile.read(Fixture.file(settings)) { return problem }
            return nil
        }
        XCTAssertEqual(problem(#""thumbWheelSettings":{"speed":-1e999}"#), .damaged("thumbWheelSettings"))
        XCTAssertEqual(problem(#""dash":{"type":"keyboard","code":-1e999}"#), .damaged("dash"))
        XCTAssertEqual(problem(#""toggle":{"type":"keyboard","code":58,"extra":[-1e999]}"#), .damaged("toggle"))
        XCTAssertEqual(problem(#""mouseGestureSettings":{"trackingSpeed":-1e999}"#), .damaged("mouseGestureSettings"))
        XCTAssertEqual(problem(#""logiWheelSettings":{"smartShiftSensitivity":-1e999}"#), .damaged("logiWheelSettings"))
        XCTAssertEqual(problem(#""logiMouseSettings":{"pointerDPI":-1e400}"#), .damaged("logiMouseSettings"))
        XCTAssertEqual(problem(#""speed":-1e999"#), .damaged("speed"), "as a number of its own it was refused before, too")
        // The other way JSONSerialization refuses the number itself: no settings file.
        XCTAssertEqual(problem(#""thumbWheelSettings":{"speed":1e999}"#), .notASettingsFile)

        // A binding and an app with such a number: left out, the others stay.
        let binding = Fixture.copyBinding.replacingOccurrences(of: #""createdAt":700000000"#, with: #""createdAt":-1e999"#)
        let nested = Fixture.scriptBinding.replacingOccurrences(of: #""modifiers":524288"#, with: #""modifiers":-1e999"#)
        let app = StoredDataCanaryTests.readableApp.replacingOccurrences(of: #""speed":2.5"#, with: #""speed":-1e999"#)
        XCTAssertNotEqual(app, StoredDataCanaryTests.readableApp)
        let contents = try Fixture.contents(
            #""buttonBindings":["# + [binding, nested, Fixture.logiBinding].joined(separator: ",") + "],"
                + #""applications":["# + app + "," + StoredDataCanaryTests.readableApp + "]"
        )
        XCTAssertEqual(contents.bindings?.map(\.triggerEvent.code), [1006])
        XCTAssertEqual(contents.applications?.map(\.path), ["/Applications/A.app"])
        XCTAssertEqual(contents.unreadableEntries, 3)
    }

    /// The four numbers of Scrolling are brought into the range the panes and the engine
    /// work with, the file's own and each app's, and the sheet says how many were. A
    /// dead zone of 1e300 was imported as it was: no frame of a scroll is that fast, so
    /// the wheel did nothing in every smoothed app, in a setting no pane shows.
    func testNumbersNoPaneCanSetAreBroughtIntoRange() throws {
        XCTAssertEqual(SettingsFile.range(ofScrollNumber: "step"), 0.01...100)
        XCTAssertEqual(SettingsFile.range(ofScrollNumber: "speed"), 1...10)
        XCTAssertEqual(SettingsFile.range(ofScrollNumber: "duration"), 1...5)
        XCTAssertEqual(SettingsFile.range(ofScrollNumber: "deadZone"), 0.1...10)
        XCTAssertNil(SettingsFile.range(ofScrollNumber: "smooth"))
        // The ranges are the sliders' own, and the default dead zone lies inside its range.
        XCTAssertEqual(SettingsFile.range(ofScrollNumber: "step"), ScrollSliderSetting.smallestStep.range)
        XCTAssertEqual(SettingsFile.range(ofScrollNumber: "speed"), ScrollSliderSetting.speed.range)
        XCTAssertEqual(SettingsFile.range(ofScrollNumber: "duration"), ScrollSliderSetting.glideTime.range)
        XCTAssertTrue(SettingsFile.deadZoneRange.contains(OPTIONS_SCROLL_DEFAULT.defaultDeadZone))

        let app = StoredDataCanaryTests.readableApp
            .replacingOccurrences(of: #""deadZone":1,"#, with: #""deadZone":1e300,"#)
            .replacingOccurrences(of: #""duration":3.69,"#, with: #""duration":99,"#)
            .replacingOccurrences(of: #""speed":2.5,"#, with: #""speed":0,"#)
            .replacingOccurrences(of: #""step":33.6,"#, with: #""step":-5,"#)
            .replacingOccurrences(of: "A.app", with: "Wild.app")
        let contents = try Fixture.contents(
            #""deadZone":1e300,"step":-1e300,"duration":-7,"speed":3,"#
                + #""applications":["# + app + "," + StoredDataCanaryTests.readableApp + "]"
        )
        XCTAssertEqual(contents.scrollNumbers, ["deadZone": 10, "step": 0.01, "duration": 1, "speed": 3])
        let first = try XCTUnwrap(contents.applications?.first)
        XCTAssertEqual([first.scroll.deadZone, first.scroll.duration, first.scroll.speed, first.scroll.step], [10, 5, 1, 0.01])
        let second = try XCTUnwrap(contents.applications?.last)
        XCTAssertEqual([second.scroll.deadZone, second.scroll.duration, second.scroll.speed, second.scroll.step], [1, 3.69, 2.5, 33.6])
        XCTAssertEqual(contents.correctedValues, 7, "three of the file's own, four of the first app's")
        XCTAssertEqual(contents.unreadableEntries, 0)

        // In effect, they are what the engine can work with.
        let own = OwnSettings(for: self)
        own.options.readOptions()
        XCTAssertTrue(SettingsFile.apply(contents, to: own.options))
        XCTAssertEqual(own.options.scroll.deadZone, 10)
        XCTAssertEqual(OPTIONS_SCROLL_DEFAULT.usableDeadZone(own.options.scroll.deadZone), 10)
        XCTAssertEqual(own.options.scroll.step, 0.01)
        XCTAssertEqual(own.options.scroll.duration, 1)
        XCTAssertEqual(own.options.application.applications.get(by: "/Applications/Wild.app")?.scroll.deadZone, 10)
        XCTAssertEqual(own.options.application.applications.get(by: "/Applications/A.app")?.scroll.deadZone, 1)

        // The sheet says so; a file whose numbers are in range has no such line.
        let sheet = SettingsImportSheetViewController(content: .confirm(contents, fileName: "x.json"))
        _ = sheet.view
        XCTAssertEqual(sheet.correctedLabel?.stringValue, "7 values were out of range and were corrected.")
        XCTAssertEqual(SettingsFileText.corrected(count: 1), "1 value was out of range and was corrected.")
        let fine = try SettingsFile.read(Data(Self.frozenFile.utf8)).get()
        XCTAssertEqual(fine.correctedValues, 0)
        let plain = SettingsImportSheetViewController(content: .confirm(fine, fileName: "x.json"))
        _ = plain.view
        XCTAssertNil(plain.correctedLabel)
    }

    /// A name the allow-list does not have is ignored, in the file's top level and among
    /// the settings, and nothing of it reaches the store: not the updater's keys, not the
    /// Welcome Guide's, not a cache.
    func testANameOffTheAllowListNeverReachesTheStore() throws {
        let own = OwnSettings(for: self)
        own.options.readOptions()
        let defaults = own.store.defaults
        defaults.set(1, forKey: "welcomeGuideCompletedVersion")
        defaults.set("general", forKey: "preferencesSelectedPane")
        defaults.set(false, forKey: "SUEnableAutomaticChecks")
        let before = own.stored

        let data = Fixture.file(
            #""speed":3,"SUFeedURL":"https://example.invalid/appcast.xml","SUEnableAutomaticChecks":true,"#
                + #""welcomeGuideCompletedVersion":0,"optionsExist":"no","preferencesSelectedPane":"buttons","#
                + #""logitechFeatureCache":{"45091":{"1":2}},"scrollTuning":{"momentum":9},"autoLaunch":true,"#
                + #""NSWindow Frame PreferencesWindow":"0 0 10 10","warpDrive":{"on":true}"#,
            more: #","futureField":{"anything":[1,2,3]},"appVersion":"9.9.9""#
        )
        let contents = try SettingsFile.read(data).get()
        XCTAssertEqual(contents.groups, [.scroll])
        XCTAssertEqual(contents.header.appVersion, "9.9.9")
        XCTAssertTrue(SettingsFile.apply(contents, to: own.options))
        own.options.flushPendingSaves()
        XCTAssertEqual(own.options.scroll.speed, 3)

        let after = own.stored
        for key in Set(before.keys).union(after.keys) where !SettingsFile.isExported(key) {
            XCTAssertEqual(before[key] as? NSObject, after[key] as? NSObject, "\(key) was changed by the import")
        }
        XCTAssertNil(after["SUFeedURL"])
        XCTAssertNil(after["warpDrive"])
        XCTAssertNil(after["autoLaunch"])
        XCTAssertEqual(after["SUEnableAutomaticChecks"] as? Bool, false)
        XCTAssertEqual(after["welcomeGuideCompletedVersion"] as? Int, 1)
        XCTAssertEqual(after["preferencesSelectedPane"] as? String, "general")
    }

    /// An entry of the two lists that this version cannot read is left out and counted:
    /// what is imported is what was understood, nothing is kept "as stored" for later.
    func testEntriesThisVersionCannotReadAreLeftOut() throws {
        let future = #"{"id":"99999999-9999-9999-9999-999999999999","futureTrigger":{"kind":"chord"},"run":"/tmp/later.sh"}"#
        let mismatch = Fixture.copyBinding.replacingOccurrences(of: #""createdAt":700000000"#, with: #""createdAt":1,"openTarget":{"path":"/tmp/x","arguments":"","kind":"script"}"#)
        let contents = try Fixture.contents(
            #""buttonBindings":["# + Fixture.copyBinding + "," + future + ",7,null," + mismatch + "],"
                + #""applications":["# + StoredDataCanaryTests.readableApp + "," + StoredDataCanaryTests.unreadableApp + "]"
        )
        XCTAssertEqual(contents.bindings?.map(\.systemShortcutName), ["copy"])
        XCTAssertEqual(contents.applications?.map(\.path), ["/Applications/A.app"])
        XCTAssertEqual(contents.unreadableEntries, 5)
        XCTAssertTrue(contents.launchActions.isEmpty, "an action whose name and target disagree is not an action")

        let own = OwnSettings(for: self)
        own.options.readOptions()
        XCTAssertTrue(SettingsFile.apply(contents, to: own.options))
        own.options.saveOptions()
        let bindings = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(own.store.defaults.data(forKey: "buttonBindings"))) as? [[String: Any]])
        XCTAssertEqual(bindings.count, 1, "nothing this version could not read is in the store")
        XCTAssertNil(bindings.first?["run"])
        let apps = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(own.store.defaults.data(forKey: "applications"))) as? [[String: Any]])
        XCTAssertEqual(apps.compactMap { $0["path"] as? String }, ["/Applications/A.app"])
        XCTAssertNil(apps.first?["future"])
    }

    /// A button or key whose action this version does not run is left out, and a gesture
    /// direction with such an action gets none: a name this version does not know could be
    /// one a later version gives a meaning, and then a press would run what no sheet ever
    /// showed (and on a Logitech button the binding would take the button and do nothing).
    func testActionsThisVersionDoesNotRunAreLeftOut() throws {
        func binding(_ id: Int, _ name: String, code: Int = 4, enabled: Bool = true) -> String {
            return #"{"id":"77777777-7777-7777-7777-"# + String(format: "%012d", id)
                + #"","triggerEvent":{"type":"mouse","code":\#(code),"modifiers":0},"systemShortcutName":"\#(name)","#
                + #""isEnabled":\#(enabled),"createdAt":1}"#
        }
        let bindings = [
            binding(1, "copy"),
            binding(2, "teleport", code: 1006),          // no such action, on a Logitech button
            binding(3, "custom::not-a-key"),             // a recorded shortcut that is none
            binding(4, "shutdownDialog"),                // retired: it runs nothing
            binding(5, "logiThumbWheelToggle"),          // a Logitech action that was removed
            binding(6, "", enabled: false),              // a row without an action yet
            binding(7, "mouseGestureNavigation"),
            binding(8, "custom::12:1703936"),            // a recorded shortcut
            binding(9, "logiHost2"),                     // a Logitech action that is run
            Fixture.scriptBinding,
        ]
        let appButtons = [binding(20, "copy"), binding(21, "teleport"), #"{"id":"broken"}"#]
        let app = StoredDataCanaryTests.readableApp.replacingOccurrences(
            of: #"{"displayName":"","#, with: #"{"buttons":{"binding":["# + appButtons.joined(separator: ",") + #"]},"displayName":"","#
        )
        let contents = try Fixture.contents(
            #""buttonBindings":["# + bindings.joined(separator: ",") + "],"
                + #""applications":["# + app + "],"
                + #""mouseGestureSettings":{"upAction":"teleport","clickAction":"logiThumbWheelToggle","downAction":"appExpose","leftAction":"","rightAction":"logiHost3"}"#
        )
        XCTAssertEqual(contents.bindings?.map(\.systemShortcutName),
                       ["copy", "", "mouseGestureNavigation", "custom::12:1703936", "logiHost2", "openTarget"])
        XCTAssertEqual(contents.applications?.count, 1, "the app stays; its buttons are judged one by one")
        XCTAssertEqual(contents.applications?.first?.buttons?.binding.map(\.systemShortcutName), ["copy"])
        let gesture = try XCTUnwrap(contents.gesture)
        XCTAssertEqual([gesture.upAction, gesture.downAction, gesture.leftAction, gesture.rightAction, gesture.clickAction],
                       ["", "appExpose", "", "logiHost3", ""])
        XCTAssertEqual(contents.unknownActions, 4 + 1 + 2, "four buttons, one of the app's, two gesture directions")
        XCTAssertEqual(contents.unreadableEntries, 1, "the app's button that cannot be read")
        XCTAssertEqual(contents.leftOutCount, 8)
        XCTAssertFalse(contents.bindings?.contains { $0.triggerEvent.code == 1006 } ?? true, "the Logitech button is not taken")

        // The sheet counts them, and nothing of them reaches the store.
        let sheet = SettingsImportSheetViewController(content: .confirm(contents, fileName: "x.json"))
        _ = sheet.view
        XCTAssertEqual(sheet.unreadableLabel?.stringValue, "8 entries this version of Scrollio does not know are left out.")
        let own = OwnSettings(for: self)
        own.options.readOptions()
        XCTAssertTrue(SettingsFile.apply(contents, to: own.options))
        own.options.saveOptions()
        let stored = String(decoding: try XCTUnwrap(own.store.defaults.data(forKey: "buttonBindings")), as: UTF8.self)
            + String(decoding: try XCTUnwrap(own.store.defaults.data(forKey: "applications")), as: UTF8.self)
            + String(decoding: try XCTUnwrap(own.store.defaults.data(forKey: "mouseGestureSettings")), as: UTF8.self)
        for name in ["teleport", "not-a-key", "shutdownDialog", "logiThumbWheelToggle", "broken"] {
            XCTAssertFalse(stored.contains(name), name)
        }

        // What the rule is made of.
        let trigger = RecordedEvent(type: .mouse, code: 4, modifiers: 0, deviceFilter: nil)
        XCTAssertTrue(StoredAction.isKnown(ButtonBinding(triggerEvent: trigger, systemShortcutName: "missionControl")))
        XCTAssertFalse(StoredAction.isKnown(ButtonBinding(triggerEvent: trigger, systemShortcutName: "openTarget")), "the name without a target")
        XCTAssertTrue(StoredAction.isKnown(gestureAction: ""))
        XCTAssertTrue(StoredAction.isKnown(gestureAction: "mouseBackClick"))
        XCTAssertFalse(StoredAction.isKnown(gestureAction: "custom::12:1703936"), "a gesture runs no recorded shortcut")
        XCTAssertFalse(StoredAction.isKnown(gestureAction: "mouseGestureNavigation"))
        XCTAssertTrue(LogiCenter.shared.runsAction(named: "logiSmartShiftToggle"))
        XCTAssertFalse(LogiCenter.shared.runsAction(named: "logiHiResScrollToggle"))
        XCTAssertFalse(LogiCenter.shared.runsAction(named: "copy"))
    }

    /// Every action that opens an app or a file, or runs a script, is found: switched on
    /// or off, of the buttons of every app and of one app's own.
    func testEveryActionThatOpensOrRunsSomethingIsFound() throws {
        let fileBinding = #"{"id":"55555555-5555-5555-5555-555555555555","triggerEvent":{"type":"mouse","code":3,"modifiers":0},"#
            + #""systemShortcutName":"openTarget","isEnabled":true,"createdAt":5,"#
            + #""openTarget":{"path":"/Users/someone/Desktop/start.command","arguments":"ignored","kind":"file"}}"#
        let appScript = Fixture.scriptBinding
            .replacingOccurrences(of: "22222222", with: "66666666")
            .replacingOccurrences(of: "sync.sh", with: "per-app.sh")
        let appWithButtons = StoredDataCanaryTests.readableApp.replacingOccurrences(
            of: #"{"displayName":"","#, with: #"{"buttons":{"binding":["# + appScript + #"]},"displayName":"","#
        )
        XCTAssertNotEqual(appWithButtons, StoredDataCanaryTests.readableApp)
        let contents = try Fixture.contents(
            #""buttonBindings":["# + [Fixture.copyBinding, Fixture.scriptBinding, Fixture.appBinding, fileBinding].joined(separator: ",") + "],"
                + #""applications":["# + appWithButtons + "]"
        )
        XCTAssertEqual(contents.unreadableEntries, 0)
        let actions = contents.launchActions
        XCTAssertEqual(actions.map(\.target.path), [
            "/Users/someone/bin/sync.sh", "/Applications/Notes.app", "/Users/someone/Desktop/start.command",
            "/Users/someone/bin/per-app.sh",
        ])
        XCTAssertEqual(actions.map(\.target.kind), [.script, .application, .file, .script])
        XCTAssertEqual(actions.map(\.target.arguments), ["--all", "", "", "--all"], "a file takes no arguments")
        XCTAssertEqual(actions.map(\.applicationPath), [nil, nil, nil, "/Applications/A.app"])
        XCTAssertEqual(actions.first?.trigger, RecordedEvent(type: .keyboard, code: 96, modifiers: 524_288, deviceFilter: nil))
        // A file without such actions has none.
        XCTAssertTrue(try Fixture.contents(#""buttonBindings":["# + Fixture.copyBinding + "]").launchActions.isEmpty)
    }

    // MARK: What an import replaces

    /// A group the file holds is replaced as a whole: what the file does not say of it
    /// reads as at launch (a number is the default, a hold key is none). A group the file
    /// does not hold stays, and its observers hear nothing.
    func testAGroupIsReplacedAsAWholeAndTheOthersStay() throws {
        let own = OwnSettings(for: self)
        own.options.readOptions()
        own.options.scroll.duration = 2.0
        own.options.scroll.dash = ScrollHotkey(type: .keyboard, code: 61)
        var gesture = MouseGestureSettings.default
        gesture.invertHorizontal = true
        own.options.gesture = gesture
        own.options.thumbWheel = ThumbWheelSettings(function: .tabs)
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, deviceFilter: nil)
        own.options.buttons.binding = [ButtonBinding(triggerEvent: trigger, systemShortcutName: "paste")]
        var heard: [OptionsGroup] = []
        own.options.observe(Set(OptionsGroup.allCases)) { heard.append($0) }

        let contents = try Fixture.contents(#""speed":3,"smooth":false"#)
        XCTAssertEqual(contents.groups, [.scroll])
        XCTAssertTrue(SettingsFile.apply(contents, to: own.options))

        XCTAssertEqual(own.options.scroll.speed, 3)
        XCTAssertFalse(own.options.scroll.smooth)
        XCTAssertEqual(own.options.scroll.duration, OPTIONS_SCROLL_DEFAULT().duration, "not in the file: the default")
        XCTAssertNil(own.options.scroll.dash, "not in the file: no key")
        XCTAssertNil(own.options.scroll.toggle)
        XCTAssertEqual(own.options.gesture, gesture)
        XCTAssertEqual(own.options.thumbWheel, ThumbWheelSettings(function: .tabs))
        XCTAssertEqual(own.options.buttons.binding.map(\.systemShortcutName), ["paste"])
        XCTAssertEqual(heard, [.scroll], "only the observers of the imported group are told")
        // The store says the same.
        own.options.flushPendingSaves()
        XCTAssertEqual(own.stored["speed"] as? Double, 3)
        XCTAssertNil(own.stored["dash"])
        XCTAssertEqual(Options.decodeThumbWheelSettings(own.store.defaults.data(forKey: "thumbWheelSettings")).function, .tabs)
    }

    /// A change that was made a moment ago and not written yet (the app writes at the next
    /// turn of the run loop) is not lost when a file of another group is imported.
    func testAChangeNotYetWrittenSurvivesAnImportOfAnotherGroup() throws {
        let own = OwnSettings(for: self)
        own.options.readOptions()
        own.options.flushPendingSaves()
        var gesture = MouseGestureSettings.default
        gesture.clickAction = "appExpose"
        own.options.gesture = gesture
        own.options.scroll.speed = 8.5
        XCTAssertNotEqual(own.stored["speed"] as? Double, 8.5, "not written yet")
        let storedGesture = own.store.defaults.data(forKey: "mouseGestureSettings")
            .flatMap { try? JSONDecoder().decode(MouseGestureSettings.self, from: $0) }
        XCTAssertNotEqual(storedGesture?.clickAction, "appExpose", "not written yet")

        XCTAssertTrue(SettingsFile.apply(try Fixture.contents(#""buttonBindings":["# + Fixture.copyBinding + "]"), to: own.options))
        XCTAssertEqual(own.options.gesture, gesture)
        XCTAssertEqual(own.options.scroll.speed, 8.5)
        XCTAssertEqual(own.options.buttons.binding.map(\.systemShortcutName), ["copy"])
    }

    // MARK: Importing runs nothing

    /// Nothing in the code of the settings file can open an app or start anything: it
    /// names no executor, no workspace and no process. (Under XCTest opening is off
    /// anyway; this is about the app.)
    func testTheSettingsFileCodeCanStartNothing() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        for file in ["Scrollio/Options/SettingsFile.swift", "Scrollio/Options/SettingsFileCenter.swift"] {
            let code = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.drop(while: { $0 == " " || $0 == "\t" }).hasPrefix("//") }
                .joined(separator: "\n")
            XCTAssertGreaterThan(code.count, 1000, file)
            for word in ["ShortcutExecutor", "NSWorkspace", "Process(", "posix_spawn", "openApplication", ".execute(", "NSAppleScript", "runModal"] {
                XCTAssertFalse(code.contains(word), "\(file) names \(word)")
            }
        }
    }

    // MARK: The text

    func testNumbersAndTextAreWrittenAsTheyAreRead() throws {
        let object: [String: Any] = [
            "b": [1, true, NSNull(), "say \"hi\"\n\ttab \\ / ünïcödé \u{1}", 6.3, 33.6, 3.69, 1e-7, 700000000.25, [Any](), [String: Any]()] as [Any],
            "a": false,
        ]
        let text = SettingsFileJSON.text(of: object)
        XCTAssertEqual(text, """
        {
          "a": false,
          "b": [
            1,
            true,
            null,
            "say \\"hi\\"\\n\\ttab \\\\ / ünïcödé \\u0001",
            6.3,
            33.6,
            3.69,
            1e-07,
            700000000.25,
            [],
            {}
          ]
        }
        """)
        // It reads back as the same values.
        let back = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? NSDictionary)
        XCTAssertEqual(back, object as NSDictionary)
        // A whole file with nothing in it is still JSON.
        let empty = SettingsFileJSON.fileText(header: [("format", "x")], settings: [])
        XCTAssertEqual(empty, "{\n  \"format\": \"x\",\n  \"settings\": {}\n}\n")
    }

    func testTheNameOfAnExportSaysTheDay() throws {
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let tokyo = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let lateEvening = Date(timeIntervalSince1970: 1_794_476_527 + 6 * 3600)   // 15:42 UTC, the 13th in Tokyo
        XCTAssertEqual(SettingsFile.defaultFileName(now: lateEvening, timeZone: utc), "Scrollio Settings 2026-11-12.json")
        XCTAssertEqual(SettingsFile.defaultFileName(now: lateEvening, timeZone: tokyo), "Scrollio Settings 2026-11-13.json")
    }

    /// What a file says about who saved it is shown to the user: only a short version, no sentence.
    func testAFileCannotPutASentenceWhereItsVersionStands() throws {
        XCTAssertEqual(SettingsFile.versionText("1.0.1"), "1.0.1")
        XCTAssertEqual(SettingsFile.versionText("1612"), "1612")
        XCTAssertEqual(SettingsFile.versionText("2.0-beta+3"), "2.0-beta+3")
        for odd in ["", "1.0 (checked by Apple, safe)", "1.0\n", "１.０", String(repeating: "1", count: 40)] as [Any] {
            XCTAssertNil(SettingsFile.versionText(odd), "\(odd)")
        }
        XCTAssertNil(SettingsFile.versionText(1.0))
        XCTAssertNil(SettingsFile.versionText(nil))
        let contents = try SettingsFile.read(Fixture.file(
            #""speed":3"#, more: #","appVersion":"1.0 — safe, checked by Apple","appBuild":7,"exported":"yesterday""#
        )).get()
        XCTAssertEqual(contents.header, SettingsFile.Header())
    }
}

// MARK: - An import reaches every part of the app

/// The app's own settings object (`Options.shared`) over a store of the test's, so that
/// what follows the settings in the app follows here: the lookups of the scroll engine,
/// the buttons' cache and its key tap, what Logitech buttons are asked for, the menu bar
/// icon, the panes. Put back as it was when the test ends.
private final class SharedSettings {
    let store: TestDefaults
    let center = SettingsFileCenter()
    let statusItem = StatusItemRecorder()
    private let snapshot = OptionsSnapshot()
    private let savedScroll = Options.shared.scroll
    private let savedEngineApplication = ScrollCore.shared.application
    private let savedInvalidate = ButtonUtils.shared.onInvalidate
    private let savedWheel = LogiSessionManager.shared.wheelSettings
    private let savedMouse = LogiSessionManager.shared.mouseSettings
    private let savedManaged = LogiSessionManager.shared.mouseManaged

    /// One observer of every group on the shared settings, for the whole run (Options
    /// keeps its observers): it tells whoever listens at the moment.
    private static var listener: ((OptionsGroup) -> Void)?
    private static let relay: Void = {
        Options.shared.observe(Set(OptionsGroup.allCases)) { listener?($0) }
    }()
    private(set) var heard: [OptionsGroup] = []

    init(for test: XCTestCase) {
        // What earlier tests left to be written goes nowhere.
        Options.shared.flushPendingSaves()
        store = TestDefaults.makeStore(for: test)
        // A container of the test's own (reading changes the one in place), over a store
        // that holds settings and nothing else: every group at its default, whatever an
        // earlier test left in the shared object.
        Options.shared.scroll = OPTIONS_SCROLL_DEFAULT()
        store.defaults.set("optionsExist", forKey: OptionItem.General.OptionsExist)
        Options.shared.defaults = store.defaults
        Options.shared.readOptions()
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScrollioTests-backups-\(UUID().uuidString)", isDirectory: true)
        test.addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        center.backups = SettingsBackups(directory: folder)
        center.log = { _ in }
        _ = Self.relay
        Self.listener = { [weak self] in self?.heard.append($0) }
    }

    func forgetWhatWasHeard() {
        heard = []
    }

    func restore() {
        Self.listener = nil
        Options.shared.flushPendingSaves()
        Options.shared.defaults = .standard
        Options.shared.scroll = savedScroll
        snapshot.restore()
        Options.shared.flushPendingSaves()
        statusItem.restore()
        ScrollCore.shared.application = savedEngineApplication
        ButtonUtils.shared.onInvalidate = savedInvalidate
        LogiCenter.shared.applyWheelSettings(savedWheel)
        LogiCenter.shared.applyMouseSettings(savedMouse, managed: savedManaged)
        LogiUsageBootstrap.refreshAll()
    }

    @discardableResult
    func importFile(_ settings: String, file: StaticString = #filePath, line: UInt = #line) throws -> URL {
        let contents = try Fixture.contents(settings, file: file, line: line)
        return try center.importSettings(contents).get()
    }
}

final class SettingsFileImportTests: XCTestCase {

    private var shared: SharedSettings!

    override func setUp() {
        super.setUp()
        shared = SharedSettings(for: self)
    }

    override func tearDown() {
        shared.restore()
        shared = nil
        super.tearDown()
    }

    /// Scrolling: the engine reads these at each wheel event and each key, from the very
    /// object the panes hold; the hold keys on a Logitech button are asked of the mouse.
    func testScrollingSettingsAreInEffectAtOnce() throws {
        let container = Options.shared.scroll
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesScrollingViewController.self))
        let pane = try XCTUnwrap(storyboard.instantiateController(withIdentifier: PANEL_IDENTIFIER.scrolling) as? PreferencesScrollingViewController)
        pane.uiStateDefaults = TestDefaults.make(for: self)
        _ = pane.view
        XCTAssertEqual(pane.scrollSpeedSlider.doubleValue, OPTIONS_SCROLL_DEFAULT().speed, accuracy: 1e-9)
        shared.forgetWhatWasHeard()

        try shared.importFile(
            #""smooth":false,"reverse":false,"reverseVertical":true,"reverseHorizontal":true,"step":20,"speed":3.5,"#
                + #""duration":2,"deadZone":1,"smoothSimTrackpad":true,"smoothVertical":true,"smoothHorizontal":true,"#
                + #""dash":{"type":"mouse","code":1006},"block":{"type":"keyboard","code":61}"#
        )

        XCTAssertTrue(Options.shared.scroll === container, "the object the engine and the panes hold")
        XCTAssertFalse(container.smooth)
        XCTAssertFalse(container.reverse)
        XCTAssertEqual(container.step, 20)
        XCTAssertEqual(container.speed, 3.5)
        XCTAssertEqual(container.duration, 2)
        XCTAssertTrue(container.smoothSimTrackpad)
        XCTAssertEqual(shared.heard, [.scroll])
        // What the scroll engine asks at a wheel event and at a key.
        XCTAssertEqual(container.durationTransition, OPTIONS_SCROLL_DEFAULT.generateDurationTransition(with: 2))
        XCTAssertEqual(ScrollUtils.shared.optionsDashKey(application: nil), ScrollHotkey(type: .mouse, code: 1006))
        XCTAssertNil(ScrollUtils.shared.optionsToggleKey(application: nil), "not in the file: none")
        XCTAssertEqual(ScrollUtils.shared.optionsBlockKey(application: nil), ScrollHotkey(type: .keyboard, code: 61))
        // What the observer installed at launch does on a change of this group.
        XCTAssertEqual(LogiUsageBootstrap.globalScrollCodes(role: .dash), [1006])
        LogiUsageBootstrap.refreshAll()
        XCTAssertTrue(LogiCenter.shared.usages(of: 1006).contains(.globalScroll(.dash)))
        // A pane that was open shows it when it is shown again.
        pane.viewWillAppear()
        XCTAssertEqual(pane.scrollSpeedSlider.doubleValue, 3.5, accuracy: 1e-9)
        XCTAssertEqual(pane.smoothSwitch.state, .off)
        // And it is stored as the app stores it.
        Options.shared.flushPendingSaves()
        XCTAssertEqual(shared.store.defaults.object(forKey: "speed") as? Double, 3.5)
        XCTAssertEqual(shared.store.defaults.object(forKey: "smooth") as? Bool, false)
        XCTAssertNil(shared.store.defaults.object(forKey: "toggle"))
    }

    /// The thumb wheel: read at each of its events; the panes that show it are told.
    func testTheThumbWheelIsInEffectAtOnce() throws {
        var told = 0
        let observer = ThumbWheelSettingsChange.addObserver { told += 1 }
        defer { ThumbWheelSettingsChange.removeObserver(observer) }
        shared.forgetWhatWasHeard()

        try shared.importFile(#""thumbWheelSettings":{"function":"volume","speed":2,"swapsDirection":true}"#)

        XCTAssertEqual(Options.shared.thumbWheel, ThumbWheelSettings(function: .volume, speed: 2, swapsDirection: true))
        XCTAssertEqual(shared.heard, [.thumbWheel])
        XCTAssertEqual(told, 1, "the Scrolling and the Buttons pane follow")
    }

    /// Buttons and keys: the buttons' cache, the key tap that exists only while a key has
    /// an action, and the Logitech buttons the mouse is asked for.
    func testButtonAndKeyActionsAreInEffectAtOnce() throws {
        XCTAssertFalse(ButtonUtils.shared.hasKeyboardTriggers)
        var refreshed = 0
        ButtonUtils.shared.onInvalidate = { refreshed += 1 }
        shared.forgetWhatWasHeard()

        try shared.importFile(#""buttonBindings":["# + Fixture.logiBinding + "," + Fixture.scriptBinding + "]")

        XCTAssertEqual(Options.shared.buttons.binding.map(\.systemShortcutName), ["copy", "openTarget"])
        XCTAssertEqual(shared.heard, [.buttons])
        XCTAssertEqual(ButtonUtils.shared.getButtonBindings().map(\.id), Options.shared.buttons.binding.map(\.id))
        XCTAssertEqual(ButtonUtils.shared.getButtonBindings(for: .mouse, code: 1006).count, 1)
        XCTAssertTrue(ButtonUtils.shared.hasKeyboardTriggers, "a key has an action now: the key tap is needed")
        XCTAssertGreaterThanOrEqual(refreshed, 1, "the key tap was told to look again")
        LogiUsageBootstrap.refreshAll()
        XCTAssertTrue(LogiCenter.shared.usages(of: 1006).contains(.buttonBinding), "the mouse is asked for the button")
        // Importing ran nothing: the script's action is stored, and opening is off here anyway.
        XCTAssertFalse(ShortcutExecutor.shared.opensTargets)

        // A file without that key: the tap is no longer needed.
        try shared.importFile(#""buttonBindings":[]"#)
        XCTAssertTrue(Options.shared.buttons.binding.isEmpty)
        XCTAssertFalse(ButtonUtils.shared.hasKeyboardTriggers)
        LogiUsageBootstrap.refreshAll()
        XCTAssertFalse(LogiCenter.shared.usages(of: 1006).contains(.buttonBinding))
    }

    /// Apps: the list the engine looks an app up in, the "only these apps" switch, and the
    /// entry the engine remembered from the last wheel event.
    func testTheAppsListIsInEffectAtOnce() throws {
        let old = Application(path: "/Applications/Old.app")
        Options.shared.application.applications.append(old)
        ScrollCore.shared.application = old
        let app = StoredDataCanaryTests.readableApp.replacingOccurrences(
            of: #""scroll":{"#, with: #""scroll":{"dash":{"code":1006,"type":"mouse"},"#
        )
        shared.forgetWhatWasHeard()

        try shared.importFile(#""allowlist":true,"applications":["# + app + "]")

        XCTAssertTrue(Options.shared.application.allowlist)
        XCTAssertEqual(Options.shared.application.applications.count, 1)
        XCTAssertNil(Options.shared.application.applications.get(by: "/Applications/Old.app"))
        let imported = try XCTUnwrap(Options.shared.application.applications.get(by: "/Applications/A.app"))
        XCTAssertFalse(imported.inherit)
        XCTAssertEqual(imported.getSpeed(), 2.5)
        XCTAssertEqual(shared.heard, [.application])
        XCTAssertNil(ScrollCore.shared.application, "the entry of the old list is forgotten; the next wheel event looks again")
        XCTAssertEqual(ScrollUtils.shared.optionsDashKey(application: imported), ScrollHotkey(type: .mouse, code: 1006))
        LogiUsageBootstrap.refreshAll()
        XCTAssertTrue(LogiCenter.shared.usages(of: 1006).contains(.appScroll(key: "/Applications/A.app", role: .dash)))
        // The Apps pane lists what the settings hold when it is shown.
        Options.shared.flushPendingSaves()
        XCTAssertEqual(shared.store.defaults.object(forKey: "allowlist") as? Bool, true)
    }

    /// Gestures: read at each hold of a gesture button; a button the mouse tracks itself
    /// follows the imported setting.
    func testGesturesAreInEffectAtOnce() throws {
        let gestureButton = Fixture.logiBinding.replacingOccurrences(of: #""copy""#, with: #""mouseGestureNavigation""#)
        try shared.importFile(#""buttonBindings":["# + gestureButton + "]")
        XCTAssertEqual(
            LogiUsageBootstrap.gestureTrackingCodes(
                deviceTracking: Options.shared.gesture.deviceTracking, bindings: Options.shared.buttons.binding, scrollHotkeyCodes: []
            ), [], "the mouse does not track before the file says so"
        )
        shared.forgetWhatWasHeard()

        try shared.importFile(#""mouseGestureSettings":{"upAction":"appExpose","invertHorizontal":true,"deviceTracking":true,"trackingSpeed":2}"#)

        XCTAssertEqual(Options.shared.gesture.upAction, "appExpose")
        XCTAssertTrue(Options.shared.gesture.invertHorizontal)
        XCTAssertEqual(Options.shared.gesture.trackingSpeed, 2)
        XCTAssertEqual(Options.shared.gesture.downAction, MouseGestureSettings.default.downAction, "not in the file: the default")
        XCTAssertEqual(shared.heard, [.gesture])
        XCTAssertEqual(
            LogiUsageBootstrap.gestureTrackingCodes(
                deviceTracking: Options.shared.gesture.deviceTracking, bindings: Options.shared.buttons.binding, scrollHotkeyCodes: []
            ), [1006]
        )
    }

    /// The Logitech values come, and reach the Logitech layer as a change made by hand
    /// does. The switch that lets Scrollio write to a mouse does not come: while it is off
    /// on this Mac, what the layer is handed says "not managed", and it writes nothing.
    func testLogitechValuesComeButNotThePermissionToWriteThem() throws {
        XCTAssertFalse(Options.shared.logiMouseManaged)
        shared.forgetWhatWasHeard()

        try shared.importFile(
            #""logiWheelSettings":{"managedByScrollio":true,"mode":"freeSpin","smartShiftSensitivity":40},"#
                + #""logiMouseSettings":{"pointerDPI":1600,"hapticsOn":false}"#
        )

        XCTAssertFalse(Options.shared.logiMouseManaged)
        XCTAssertEqual(Options.shared.logiWheel, LogiWheelSettings(managedByScrollio: false, mode: .freeSpin, smartShiftSensitivity: 40))
        XCTAssertEqual(Options.shared.logiMouse, LogiMouseSettings(pointerDPI: 1600, hapticsOn: false))
        XCTAssertEqual(shared.heard, [.logiWheel, .logiMouse])
        // What the observers installed at launch hand to the Logitech layer.
        LogiCenter.shared.applyWheelSettings(Options.shared.logiWheel)
        LogiUsageBootstrap.pushMouseSettings()
        XCTAssertFalse(LogiSessionManager.shared.wheelSettings.managedByScrollio)
        XCTAssertFalse(LogiSessionManager.shared.mouseManaged)
        XCTAssertEqual(LogiSessionManager.shared.mouseSettings.pointerDPI, 1600)

        // With the switch on on this Mac it stays on, and the values are the file's.
        Options.shared.logiMouseManaged = true
        try shared.importFile(#""logiWheelSettings":{"mode":"ratchet"},"logiMouseSettings":{"pointerDPI":800}"#)
        XCTAssertTrue(Options.shared.logiMouseManaged)
        XCTAssertEqual(Options.shared.logiWheel, LogiWheelSettings(managedByScrollio: true, mode: .ratchet))
        XCTAssertEqual(Options.shared.logiMouse, LogiMouseSettings(pointerDPI: 800))
        Options.shared.flushPendingSaves()
        let stored = Options.decodeLogiWheelSettings(shared.store.defaults.data(forKey: "logiWheelSettings"))
        XCTAssertTrue(stored.managedByScrollio)
        XCTAssertNil(stored.smartShiftSensitivity, "the group was replaced: what the file does not say is not set")
    }

    /// "Show in menu bar": the icon goes and comes through the option's own path.
    func testTheMenuBarIconFollows() throws {
        XCTAssertFalse(Options.shared.general.hideStatusItem)
        shared.forgetWhatWasHeard()

        try shared.importFile(#""hideStatusItem":true"#)
        XCTAssertTrue(Options.shared.general.hideStatusItem)
        XCTAssertEqual(shared.statusItem.calls.last, false, "hidden")
        XCTAssertTrue(shared.heard.contains(.general))

        try shared.importFile(#""hideStatusItem":false"#)
        XCTAssertFalse(Options.shared.general.hideStatusItem)
        XCTAssertEqual(shared.statusItem.calls.last, true, "shown again")
        Options.shared.flushPendingSaves()
        XCTAssertEqual(shared.store.defaults.object(forKey: "hideStatusItem") as? Bool, false)
    }

    /// What follows no observer: the scroll engine's memory of the app scrolled in last and
    /// of hold keys that are down.
    func testTheScrollEngineForgetsWhatItRemembered() {
        let old = Application(path: "/Applications/Old.app")
        ScrollCore.shared.application = old
        ScrollCore.shared.currentApplication = old
        ScrollCore.shared.dashKeyHeld = true
        ScrollCore.shared.blockKeyHeld = true
        ScrollCore.shared.settingsWereReplaced()
        XCTAssertNil(ScrollCore.shared.application)
        XCTAssertNil(ScrollCore.shared.currentApplication)
        XCTAssertFalse(ScrollCore.shared.dashKeyHeld)
        XCTAssertFalse(ScrollCore.shared.blockKeyHeld)
        XCTAssertFalse(ScrollCore.shared.blockSmooth)
    }
}

// MARK: - Backups and the center

final class SettingsFileCenterTests: XCTestCase {

    private var statusItem: StatusItemRecorder!

    override func setUp() {
        super.setUp()
        statusItem = StatusItemRecorder()
    }

    override func tearDown() {
        statusItem.restore()
        super.tearDown()
    }

    private func names(in folder: URL) -> [String] {
        return ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    /// Nothing is lost by an import: the settings from before are a file that the same
    /// import reads, and importing it brings them back (and keeps what it replaced).
    func testTheSettingsFromBeforeAnImportAreKeptAndComeBack() throws {
        let own = OwnSettings(for: self)
        own.options.readOptions()
        own.options.scroll.speed = 7.5
        own.options.thumbWheel = ThumbWheelSettings(function: .desktops)
        var moment = Date(timeIntervalSince1970: 1_794_476_527)
        own.center.now = { moment }
        XCTAssertNil(own.center.latestBackup())
        XCTAssertEqual(names(in: own.backupFolder), [], "no folder before the first import")

        let backup = try own.center.importSettings(try Fixture.contents(#""speed":3,"thumbWheelSettings":{"function":"zoom"}"#)).get()
        XCTAssertEqual(own.options.scroll.speed, 3)
        XCTAssertEqual(own.options.thumbWheel.function, .zoom)
        XCTAssertEqual(backup.deletingLastPathComponent().path, own.backupFolder.path)
        XCTAssertTrue(backup.lastPathComponent.hasPrefix("Scrollio Settings Backup "))
        XCTAssertEqual(backup.pathExtension, "json")
        let latest = try XCTUnwrap(own.center.latestBackup())
        XCTAssertEqual(latest.url.lastPathComponent, backup.lastPathComponent)
        XCTAssertEqual(latest.date, moment)

        // The backup is a whole settings file of the moment before.
        let kept = try own.center.read(backup).get()
        XCTAssertEqual(kept.groups, Set(OptionsGroup.allCases))
        XCTAssertEqual(kept.scrollNumbers["speed"], 7.5)
        XCTAssertEqual(kept.thumbWheel?.function, .desktops)
        XCTAssertEqual(kept.header.appVersion, "1.2.3")

        // Going back is an import too: it keeps what it replaces.
        moment += 60
        let second = try own.center.importSettings(kept).get()
        XCTAssertEqual(own.options.scroll.speed, 7.5)
        XCTAssertEqual(own.options.thumbWheel.function, .desktops)
        XCTAssertNotEqual(second.lastPathComponent, backup.lastPathComponent)
        XCTAssertEqual(try own.center.read(second).get().scrollNumbers["speed"], 3)
        XCTAssertEqual(own.center.latestBackup()?.url.lastPathComponent, second.lastPathComponent)
        XCTAssertEqual(names(in: own.backupFolder).count, 2)
    }

    /// When the current settings cannot be saved first, nothing is imported.
    func testWithoutABackupNothingIsImported() throws {
        let own = OwnSettings(for: self)
        own.options.readOptions()
        own.options.scroll.speed = 7.5
        own.options.flushPendingSaves()
        let contents = try Fixture.contents(#""speed":3,"hideStatusItem":true"#)

        // No folder at all (what the app's center has under XCTest).
        own.center.backups = SettingsBackups(directory: nil)
        guard case .failure(.backupFailed) = own.center.importSettings(contents) else {
            return XCTFail("imported without a backup")
        }
        // A folder that cannot be made: a file stands where it would be.
        let folder = try temporaryFolder(for: self)
        let blocked = folder.appendingPathComponent("blocked")
        try Data("x".utf8).write(to: blocked)
        own.center.backups = SettingsBackups(directory: blocked.appendingPathComponent("Settings Backups"))
        guard case .failure(.backupFailed(let reason)) = own.center.importSettings(contents) else {
            return XCTFail("imported without a backup")
        }
        XCTAssertFalse(reason.isEmpty, "the system's reason is passed on")

        XCTAssertEqual(own.options.scroll.speed, 7.5)
        XCTAssertFalse(own.options.general.hideStatusItem)
        XCTAssertEqual(own.stored["speed"] as? Double, 7.5)
        XCTAssertTrue(own.logLines.allSatisfy { $0.contains("not imported") }, "\(own.logLines)")
    }

    /// Every value of a file is put in the form the store takes before anything is
    /// written. A value that cannot be was dropped after its group's keys had been
    /// removed: the group came out empty, without a word. Now nothing is changed, no
    /// backup is written, and the import says so.
    func testAValueThatCannotBeStoredChangesNothing() throws {
        let own = OwnSettings(for: self)
        own.options.readOptions()
        own.options.application.allowlist = true
        own.options.application.applications.append(Application(path: "/Applications/Mine.app"))
        own.options.scroll.speed = 7.5
        own.options.saveOptions()
        let before = own.stored as NSDictionary

        // No file gives such a value (a number of a file is finite and in range); the
        // contents are made by hand to reach the encoder's refusal.
        let broken = Application(path: "/Applications/Broken.app")
        broken.scroll.step = .infinity
        var contents = try Fixture.contents(#""speed":3,"allowlist":false"#)
        contents.applications = [broken]
        XCTAssertNil(SettingsFile.storeValues(of: contents, managedByScrollio: false))
        XCTAssertNotNil(SettingsFile.storeValues(of: try Fixture.contents(#""speed":3,"allowlist":false"#), managedByScrollio: false))

        XCTAssertFalse(SettingsFile.apply(contents, to: own.options))
        XCTAssertEqual(own.stored as NSDictionary, before, "not a key was removed")
        XCTAssertEqual(own.options.scroll.speed, 7.5)
        XCTAssertTrue(own.options.application.allowlist)
        XCTAssertEqual(own.options.application.applications.count, 1)

        guard case .failure(.cannotStore) = own.center.importSettings(contents) else {
            return XCTFail("imported what cannot be stored")
        }
        XCTAssertEqual(own.stored as NSDictionary, before)
        XCTAssertEqual(names(in: own.backupFolder), [], "no backup of an import that was not begun")
        XCTAssertEqual(own.logLines, ["Settings file: not imported (a value could not be encoded)"])
    }

    /// The last five backups are kept; nothing else in the folder is touched.
    func testOnlyTheLastFiveBackupsAreKept() throws {
        let folder = try temporaryFolder(for: self)
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let backups = SettingsBackups(directory: folder, timeZone: utc)
        let other = ["notes.txt", "Scrollio Settings Backup of mine.json", "Scrollio Settings Backup 2026-11-12 09.42.07.txt"]
        for name in other {
            try Data("mine".utf8).write(to: folder.appendingPathComponent(name))
        }
        let start = Date(timeIntervalSince1970: 1_794_476_527)
        var written: [String] = []
        for index in 0..<7 {
            written.append(try backups.write(Data("\(index)".utf8), now: start.addingTimeInterval(Double(index) * 90)).lastPathComponent)
        }
        XCTAssertEqual(written.first, "Scrollio Settings Backup 2026-11-12 09.42.07.json")
        XCTAssertEqual(SettingsBackups.keepCount, 5)
        let entries = backups.entries()
        XCTAssertEqual(entries.map(\.url.lastPathComponent), Array(written.suffix(5).reversed()), "the newest five, newest first")
        XCTAssertEqual(backups.latest?.url.lastPathComponent, written.last)
        XCTAssertEqual(backups.latest?.date, start.addingTimeInterval(540))
        XCTAssertEqual(try String(contentsOf: try XCTUnwrap(backups.latest?.url), encoding: .utf8), "6")
        XCTAssertEqual(names(in: folder), (other + written.suffix(5)).sorted(), "what is not a backup stays")
    }

    /// Two imports in one second: two backups, in the order they were written.
    func testBackupsOfOneSecondAreKeptApartAndInOrder() throws {
        let folder = try temporaryFolder(for: self)
        let backups = SettingsBackups(directory: folder, timeZone: try XCTUnwrap(TimeZone(identifier: "UTC")))
        let now = Date(timeIntervalSince1970: 1_794_476_527)
        let first = try backups.write(Data("first".utf8), now: now)
        let second = try backups.write(Data("second".utf8), now: now)
        let third = try backups.write(Data("third".utf8), now: now)
        XCTAssertEqual([first, second, third].map(\.lastPathComponent), [
            "Scrollio Settings Backup 2026-11-12 09.42.07.json",
            "Scrollio Settings Backup 2026-11-12 09.42.07 (2).json",
            "Scrollio Settings Backup 2026-11-12 09.42.07 (3).json",
        ])
        XCTAssertEqual(backups.entries().map(\.url.lastPathComponent), [third, second, first].map(\.lastPathComponent))
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "first", "an earlier backup is never overwritten")
        // No folder: nothing to list, and a write says so.
        let nowhere = SettingsBackups(directory: nil)
        XCTAssertTrue(nowhere.entries().isEmpty)
        XCTAssertThrowsError(try nowhere.write(Data()))
    }

    /// Under XCTest the app's own preferences are closed to settings files and its
    /// backups have no folder: a test that forgets to bring its own reads and writes nothing.
    func testTheAppsOwnSettingsAndFolderAreOutOfReachOfTheTests() throws {
        let options = Options()
        XCTAssertTrue(options.defaults === UserDefaults.standard)
        XCTAssertFalse(options.writesToDefaults)
        guard case .failure(.storeUnavailable) = SettingsFile.export(from: options) else {
            return XCTFail("the app's preferences were read into a file")
        }
        XCTAssertFalse(SettingsFile.apply(try Fixture.contents(#""speed":3"#), to: options))
        XCTAssertEqual(options.scroll.speed, OPTIONS_SCROLL_DEFAULT().speed)

        XCTAssertNil(SettingsBackups.live.directory)
        XCTAssertNil(SettingsFileCenter.live.backups.directory)
        XCTAssertNil(SettingsFileCenter.live.latestBackup())
        let folder = try temporaryFolder(for: self)
        let url = folder.appendingPathComponent("out.json")
        XCTAssertEqual(SettingsFileCenter.live.export(to: url), .storeUnavailable)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        guard case .failure(.storeUnavailable) = SettingsFileCenter.live.importSettings(try Fixture.contents(#""speed":3"#)) else {
            return XCTFail("imported into the app's preferences")
        }
    }

    /// An export is one file where the user said; one that cannot be written says why.
    func testAnExportIsWrittenWhereTheUserSaid() throws {
        let own = OwnSettings(for: self)
        own.options.readOptions()
        own.options.scroll.speed = 4.5
        let folder = try temporaryFolder(for: self)
        let url = folder.appendingPathComponent("My settings.json")
        XCTAssertNil(own.center.export(to: url))
        XCTAssertEqual(names(in: folder), ["My settings.json"], "one file, nothing beside it")
        XCTAssertEqual(try own.center.read(url).get().scrollNumbers["speed"], 4.5)
        XCTAssertEqual(names(in: own.backupFolder), [], "an export writes no backup")

        let nowhere = folder.appendingPathComponent("missing-folder").appendingPathComponent("x.json")
        guard case .cannotWrite(let reason)? = own.center.export(to: nowhere) else {
            return XCTFail("written to a folder that is not there")
        }
        XCTAssertFalse(reason.isEmpty)
    }

    /// The `app` log gets one line per export and import, and never a path or a name of a
    /// file: not the user's folder, not what a button would open.
    func testTheLogNamesNoFileAndNoPath() throws {
        let own = OwnSettings(for: self)
        own.options.readOptions()
        let folder = try temporaryFolder(for: self)
        let url = folder.appendingPathComponent("Private name.json")
        XCTAssertNil(own.center.export(to: url))
        _ = own.center.read(folder.appendingPathComponent("Secret missing.json"))
        _ = own.center.read(url)
        _ = try own.center.importSettings(try Fixture.contents(#""buttonBindings":["# + Fixture.scriptBinding + ",7]")).get()
        _ = own.center.export(to: folder.appendingPathComponent("no-folder/Private.json"))

        XCTAssertEqual(own.logLines.count, 4, "\(own.logLines)")
        XCTAssertTrue(own.logLines[0].hasPrefix("Settings file: exported ("))
        XCTAssertEqual(own.logLines[1], "Settings file: a file was not usable (the file could not be read)")
        XCTAssertEqual(own.logLines[2], "Settings file: imported (buttons; 1 action(s) that open or run something; 1 entry left out)")
        XCTAssertEqual(own.logLines[3], "Settings file: not exported (the file could not be written)")
        for line in own.logLines {
            for word in ["Private", "Secret", "sync.sh", "/Users", folder.lastPathComponent, "someone"] {
                XCTAssertFalse(line.contains(word), line)
            }
        }
        XCTAssertEqual(SettingsFileCenter.logName(of: .damaged("speed")), "damaged: speed")
        XCTAssertEqual(SettingsFileCenter.logName(of: .damaged("/Users/someone")), "damaged: ?")
    }
}

// MARK: - The sheet's words

final class SettingsFileTextTests: XCTestCase {

    private let names = ButtonTriggerNaming.Logitech(role: { _ in nil }, name: { _ in nil })

    func testTheSheetListsWhatAFileHoldsInThePanesWords() throws {
        let everything = try Fixture.contents(
            #""speed":3,"thumbWheelSettings":{},"buttonBindings":["# + Fixture.copyBinding + "," + Fixture.scriptBinding + "],"
                + #""mouseGestureSettings":{},"logiMouseSettings":{},"allowlist":true,"#
                + #""applications":["# + StoredDataCanaryTests.readableApp + "],"
                + #""hideStatusItem":false"#
        )
        XCTAssertEqual(SettingsFileText.items(of: everything).map(\.text), [
            "Scrolling settings", "Thumb wheel", "2 button and key actions", "Gestures", "Logitech mouse values",
            "1 app with its own settings", "“Change scrolling only in these apps” is on", "Show in menu bar: on",
        ])
        for item in SettingsFileText.items(of: everything) {
            XCTAssertNotNil(NSImage(systemSymbolName: item.symbolName, accessibilityDescription: nil), item.symbolName)
        }
        // Only what the file holds.
        XCTAssertEqual(SettingsFileText.items(of: try Fixture.contents(#""speed":3"#)).map(\.text), ["Scrolling settings"])
        XCTAssertEqual(SettingsFileText.items(of: try Fixture.contents(#""logiWheelSettings":{}"#)).map(\.text), ["Logitech mouse values"])
        // An import of an empty list empties the list: the sheet says so.
        XCTAssertEqual(
            SettingsFileText.items(of: try Fixture.contents(#""buttonBindings":[],"applications":[],"hideStatusItem":true"#)).map(\.text),
            ["No button or key actions", "An empty list of apps", "Show in menu bar: off"]
        )
        XCTAssertEqual(SettingsFileText.counted(1, "general-settings-import-actions"), "1 button or key action")
        XCTAssertEqual(SettingsFileText.counted(12, "general-settings-import-actions"), "12 button and key actions")
        XCTAssertEqual(SettingsFileText.counted(4, "general-settings-import-apps"), "4 apps with their own settings")
        XCTAssertEqual(SettingsFileText.unreadable(count: 1), "1 entry this version of Scrollio does not know is left out.")
        XCTAssertEqual(SettingsFileText.unreadable(count: 3), "3 entries this version of Scrollio does not know are left out.")
    }

    func testTheSheetSaysWhoSavedTheFileAndWhen() throws {
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let gb = Locale(identifier: "en_GB")
        var header = SettingsFile.Header()
        XCTAssertEqual(SettingsFileText.source(fileName: "Mine.json", header: header, locale: gb, timeZone: utc), "“Mine.json”")
        header.appVersion = "1.0.1"
        XCTAssertEqual(
            SettingsFileText.source(fileName: "Mine.json", header: header, locale: gb, timeZone: utc),
            "“Mine.json”. It says it was saved by Scrollio 1.0.1."
        )
        header.exported = Date(timeIntervalSince1970: 1_794_476_527)
        XCTAssertEqual(
            SettingsFileText.source(fileName: "Mine.json", header: header, locale: gb, timeZone: utc),
            "“Mine.json”. It says it was saved by Scrollio 1.0.1 on 12 Nov 2026 at 09:42."
        )
    }

    /// Each action that opens or runs something: its button or key, what a press does and
    /// the whole path. Nothing of a path is hidden: a character that draws nothing, breaks
    /// the line or turns the text around is written out.
    func testAnActionThatOpensOrRunsSomethingIsWrittenOutInFull() throws {
        XCTAssertEqual(SettingsFileText.launchTitle(count: 1), "1 action opens an app or a file, or runs a script")
        XCTAssertEqual(SettingsFileText.launchTitle(count: 3), "3 actions open an app or a file, or run a script")
        let key = RecordedEvent(type: .keyboard, code: 96, modifiers: 524_288, deviceFilter: nil)
        let button = RecordedEvent(type: .mouse, code: 4, modifiers: 0, deviceFilter: nil)
        let keyName = ButtonTriggerNaming.title(for: key, logitech: names)
        let buttonName = ButtonTriggerNaming.title(for: button, logitech: names)
        XCTAssertFalse(keyName.isEmpty)

        func line(_ trigger: RecordedEvent, _ path: String, _ arguments: String, _ kind: OpenTargetKind) -> String {
            let target = OpenTargetPayload(path: path, bundleID: nil, arguments: arguments, kind: kind)
            return SettingsFileText.launchLine(for: SettingsFile.LaunchAction(trigger: trigger, target: target, applicationPath: nil), logitech: names)
        }
        XCTAssertEqual(line(key, "/Users/someone/bin/sync.sh", "--all \"two words\"", .script),
                       "\(keyName): runs the script /Users/someone/bin/sync.sh (arguments: --all \"two words\")")
        XCTAssertEqual(line(key, "/Users/someone/bin/sync.sh", "  ", .script), "\(keyName): runs the script /Users/someone/bin/sync.sh")
        XCTAssertEqual(line(button, "/Applications/Notes.app", "", .application), "\(buttonName): opens the app /Applications/Notes.app")
        XCTAssertEqual(line(button, "/Applications/Notes.app", "--new", .application),
                       "\(buttonName): opens the app /Applications/Notes.app (arguments: --new)")
        // An app is also found by its identifier when nothing is at the path: a file
        // could name one app by path and another by identifier, so both are shown.
        func appLine(_ identifier: String?, _ arguments: String = "") -> String {
            let target = OpenTargetPayload(path: "/Applications/Harmless.app", bundleID: identifier, arguments: arguments, kind: .application)
            return SettingsFileText.launchLine(for: SettingsFile.LaunchAction(trigger: button, target: target, applicationPath: nil), logitech: names)
        }
        XCTAssertEqual(appLine("com.example.other"),
                       "\(buttonName): opens the app /Applications/Harmless.app, or else the app with the ID com.example.other")
        XCTAssertEqual(appLine("com.example.other", "--flag"),
                       "\(buttonName): opens the app /Applications/Harmless.app, or else the app with the ID com.example.other (arguments: --flag)")
        XCTAssertEqual(appLine("com.example\u{202E}.other"),
                       "\(buttonName): opens the app /Applications/Harmless.app, or else the app with the ID com.example\\u{202E}.other")
        XCTAssertEqual(appLine(""), "\(buttonName): opens the app /Applications/Harmless.app")
        XCTAssertEqual(appLine(nil), "\(buttonName): opens the app /Applications/Harmless.app")
        XCTAssertEqual(line(button, "/Users/someone/Desktop/start.command", "x", .file),
                       "\(buttonName): opens the file /Users/someone/Desktop/start.command")

        // A path that tries to look like another one.
        XCTAssertEqual(SettingsFileText.visible("/tmp/photo\u{202E}gpj.sh"), "/tmp/photo\\u{202E}gpj.sh")
        XCTAssertEqual(SettingsFileText.visible("/tmp/a\n\n\n/Applications/Safe.app"), "/tmp/a\\u{A}\\u{A}\\u{A}/Applications/Safe.app")
        XCTAssertEqual(SettingsFileText.visible("/tmp/zero\u{200B}width\u{0}\t"), "/tmp/zero\\u{200B}width\\u{0}\\u{9}")
        XCTAssertEqual(SettingsFileText.visible("/Users/someone/Büro/ファイル 1.sh"), "/Users/someone/Büro/ファイル 1.sh", "ordinary names stay")
        XCTAssertEqual(line(button, "/tmp/a\u{2028}b", "-x\u{202E}", .script), "\(buttonName): runs the script /tmp/a\\u{2028}b (arguments: -x\\u{202E})")
    }

    func testEveryProblemIsSaidInPlainWords() {
        let texts: [(SettingsFile.Problem, String)] = [
            (.cannotRead("The file “x” couldn’t be opened."), "Scrollio could not read the file. The file “x” couldn’t be opened."),
            (.cannotRead(""), "Scrollio could not read the file."),
            (.tooLarge, "It is too large to be a Scrollio settings file."),
            (.notASettingsFile, "It is not a Scrollio settings file, or it is damaged."),
            (.newerFormat, "It was saved by a newer version of Scrollio. Update Scrollio, then import it again."),
            (.damaged("speed"), "The file is damaged: its part “speed” cannot be read."),
            (.nothingToImport, "It holds no settings this version of Scrollio knows."),
            (.tooManyEntries, "It holds more than 1000 buttons and keys, or more than that many apps: more than Scrollio takes from a file."),
            (.cannotStore, "Scrollio could not store these settings, so nothing was changed."),
            (.cannotWrite("The folder is read-only."), "Scrollio could not save the file there. The folder is read-only."),
            (.backupFailed(""), "Your current settings could not be saved first, so nothing was changed."),
            (.storeUnavailable, "Scrollio's settings cannot be read right now."),
        ]
        for (problem, text) in texts {
            XCTAssertEqual(SettingsFileText.explanation(of: problem), text)
        }
    }
}

// MARK: - The sheet

final class SettingsImportSheetTests: XCTestCase {

    private func allSubviews(of view: NSView) -> [NSView] {
        return view.subviews.flatMap { [$0] + allSubviews(of: $0) }
    }

    private func makeSheet(_ settings: String, fileName: String = "Scrollio Settings 2026-11-12.json") throws -> SettingsImportSheetViewController {
        let sheet = SettingsImportSheetViewController(content: .confirm(try Fixture.contents(settings), fileName: fileName))
        _ = sheet.view
        return sheet
    }

    /// A file without actions that open or run something: what it holds, the note about
    /// the backup, and "Import" on Return.
    func testTheSheetAsksBeforeAnythingChanges() throws {
        let sheet = try makeSheet(#""speed":3,"buttonBindings":["# + Fixture.copyBinding + #"],"hideStatusItem":false"#)
        XCTAssertEqual(sheet.titleLabel.stringValue, "Import these settings?")
        XCTAssertEqual(sheet.detailLabel.stringValue, "“Scrollio Settings 2026-11-12.json”")
        XCTAssertEqual(sheet.itemLabels.map(\.stringValue), ["Scrolling settings", "1 button or key action", "Show in menu bar: on"])
        XCTAssertEqual(
            sheet.noteLabel?.stringValue,
            "These settings replace the ones on this Mac. Your current settings are saved first, so you can go back. "
                + "“Let Scrollio manage this mouse” and “Open at login” stay as they are."
        )
        XCTAssertNil(sheet.launchTitleLabel)
        XCTAssertNil(sheet.launchList)
        XCTAssertNil(sheet.unreadableLabel)
        let importButton = try XCTUnwrap(sheet.importButton)
        XCTAssertEqual(importButton.title, "Import")
        XCTAssertEqual(importButton.keyEquivalent, "\r")
        XCTAssertEqual(sheet.closeButton.title, "Cancel")
        XCTAssertEqual(sheet.closeButton.keyEquivalent, "\u{1b}")

        var imports = 0
        var closes = 0
        sheet.onImport = { imports += 1 }
        sheet.onClose = { closes += 1 }
        XCTAssertTrue(importButton.sendAction(importButton.action, to: importButton.target))
        XCTAssertTrue(sheet.closeButton.sendAction(sheet.closeButton.action, to: sheet.closeButton.target))
        sheet.cancelOperation(nil)
        XCTAssertEqual(imports, 1)
        XCTAssertEqual(closes, 2, "Cancel and Esc")

        XCTAssertEqual(sheet.view.frame.width, SettingsImportSheetViewController.width)
        XCTAssertEqual(sheet.view.frame.size, sheet.view.fittingSize)
        XCTAssertEqual(sheet.preferredContentSize, sheet.view.frame.size)
        sheet.view.layoutSubtreeIfNeeded()
        XCTAssertFalse(sheet.view.hasAmbiguousLayout)
    }

    /// A file with such actions: how many, each with its whole path, and Return is Cancel.
    func testActionsThatOpenOrRunSomethingAreShownBeforeTheImport() throws {
        let sheet = try makeSheet(
            #""buttonBindings":["# + [Fixture.copyBinding, Fixture.scriptBinding, Fixture.appBinding].joined(separator: ",") + ",{}]"
        )
        XCTAssertEqual(sheet.itemLabels.map(\.stringValue), ["3 button and key actions"])
        XCTAssertEqual(sheet.launchTitleLabel?.stringValue, "2 actions open an app or a file, or run a script")
        XCTAssertEqual(
            sheet.launchHintLabel?.stringValue,
            "Each starts at a press of its button or key. Import the file only if you know what they do."
        )
        let list = try XCTUnwrap(sheet.launchList)
        let lines = list.string.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].hasSuffix(": runs the script /Users/someone/bin/sync.sh (arguments: --all)"), lines[0])
        XCTAssertTrue(lines[1].hasSuffix(": opens the app /Applications/Notes.app, or else the app with the ID com.apple.Notes"), lines[1])
        XCTAssertFalse(list.isEditable)
        XCTAssertTrue(list.isSelectable, "a path can be copied")
        XCTAssertEqual(sheet.unreadableLabel?.stringValue, "1 entry this version of Scrollio does not know is left out.")
        // Return does not import: it is Cancel, and so is Esc.
        XCTAssertEqual(sheet.importButton?.keyEquivalent, "")
        XCTAssertEqual(sheet.closeButton.keyEquivalent, "\r")
        XCTAssertEqual(sheet.closeButton.title, "Cancel")
        var imports = 0
        var closes = 0
        sheet.onImport = { imports += 1 }
        sheet.onClose = { closes += 1 }
        func key(_ code: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
            return try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code
            ))
        }
        // The event is made, never posted: the button is asked as its window would ask it.
        XCTAssertTrue(sheet.closeButton.performKeyEquivalent(with: try key(53, "\u{1b}")), "Esc")
        XCTAssertEqual(closes, 1)
        XCTAssertFalse(sheet.closeButton.performKeyEquivalent(with: try key(53, "\u{1b}", .command)), "not ⌘Esc")
        XCTAssertFalse(try XCTUnwrap(sheet.importButton).performKeyEquivalent(with: try key(36, "\r")), "Return is not Import")
        XCTAssertFalse(try XCTUnwrap(sheet.importButton).performKeyEquivalent(with: try key(53, "\u{1b}")))
        XCTAssertEqual(imports, 0)
        XCTAssertEqual(closes, 1)
        XCTAssertTrue(sheet.view.acceptsFirstResponder, "the sheet takes the keyboard, not the list")
        // Everything shows: the list is as tall as its two lines.
        sheet.view.layoutSubtreeIfNeeded()
        let scroll = try XCTUnwrap(sheet.launchScrollView)
        XCTAssertGreaterThanOrEqual(scroll.frame.height, list.frame.height - 0.5)
        XCTAssertLessThan(scroll.frame.height, SettingsImportSheetViewController.launchListMaximumHeight)
        XCTAssertFalse(sheet.view.hasAmbiguousLayout)
        XCTAssertEqual(sheet.view.frame.size, sheet.view.fittingSize)
    }

    /// A file with very many of them: every one is in the list, the list scrolls, and the
    /// sheet stays a sheet.
    func testManyActionsScrollInsideTheSheet() throws {
        let many = (0..<60).map { index in
            Fixture.scriptBinding
                .replacingOccurrences(of: "22222222-2222-2222-2222-222222222222", with: String(format: "22222222-2222-2222-2222-%012d", index))
                .replacingOccurrences(of: "sync.sh", with: "a-long-folder-name/with-another-folder-inside/script-number-\(index).sh")
        }
        let sheet = try makeSheet(#""buttonBindings":["# + many.joined(separator: ",") + "]")
        XCTAssertEqual(sheet.launchTitleLabel?.stringValue, "60 actions open an app or a file, or run a script")
        let list = try XCTUnwrap(sheet.launchList)
        for index in 0..<60 {
            XCTAssertTrue(list.string.contains("script-number-\(index).sh (arguments: --all)"), "\(index)")
        }
        sheet.view.layoutSubtreeIfNeeded()
        let scroll = try XCTUnwrap(sheet.launchScrollView)
        XCTAssertEqual(scroll.frame.height, SettingsImportSheetViewController.launchListMaximumHeight, accuracy: 0.5)
        XCTAssertGreaterThan(list.frame.height, scroll.frame.height, "the list scrolls")
        XCTAssertLessThan(sheet.view.frame.height, 560)
    }

    /// Why a file cannot be used: a title, the reason, OK. The same sheet can turn into it.
    func testTheSheetSaysWhyAFileCannotBeUsed() throws {
        let sheet = SettingsImportSheetViewController(content: .problem(
            title: "This file cannot be imported", text: "It is not a Scrollio settings file, or it is damaged. Nothing was changed."
        ))
        _ = sheet.view
        XCTAssertEqual(sheet.titleLabel.stringValue, "This file cannot be imported")
        XCTAssertEqual(sheet.detailLabel.stringValue, "It is not a Scrollio settings file, or it is damaged. Nothing was changed.")
        XCTAssertNil(sheet.importButton)
        XCTAssertEqual(sheet.closeButton.title, "OK")
        XCTAssertEqual(sheet.closeButton.keyEquivalent, "\r")
        XCTAssertTrue(sheet.itemLabels.isEmpty)
        XCTAssertFalse(allSubviews(of: sheet.view).contains { ($0 as? NSButton)?.title == "Import" })
        XCTAssertEqual(sheet.view.frame.size, sheet.view.fittingSize)

        let asking = try makeSheet(#""speed":3"#)
        let tall = asking.view.frame.height
        asking.show(.problem(title: "This file cannot be imported", text: "Your current settings could not be saved first, so nothing was changed."))
        XCTAssertNil(asking.importButton)
        XCTAssertEqual(asking.closeButton.title, "OK")
        XCTAssertLessThan(asking.view.frame.height, tall)
        XCTAssertEqual(asking.preferredContentSize, asking.view.frame.size)
        XCTAssertFalse(allSubviews(of: asking.view).contains { ($0 as? NSButton)?.title == "Import" })
    }
}

// MARK: - The row in General

final class PreferencesGeneralSettingsFileTests: XCTestCase {

    private var statusItem: StatusItemRecorder!

    override func setUp() {
        super.setUp()
        statusItem = StatusItemRecorder()
    }

    override func tearDown() {
        statusItem.restore()
        super.tearDown()
    }

    /// What the pane did besides changing settings.
    private final class World {
        var exportAnswer: URL?
        var offeredNames: [String] = []
        var importAnswer: URL?
        var importPanels = 0
        var presented: [SettingsImportSheetViewController] = []
        var dismissed: [SettingsImportSheetViewController] = []
        var notices: [(text: String, style: Toast.Style)] = []
    }

    private func allSubviews(of view: NSView) -> [NSView] {
        return view.subviews.flatMap { [$0] + allSubviews(of: $0) }
    }

    private func makePane(_ own: OwnSettings, _ world: World) throws -> PreferencesGeneralViewController {
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesGeneralViewController.self))
        let pane = try XCTUnwrap(
            storyboard.instantiateController(withIdentifier: PANEL_IDENTIFIER.general) as? PreferencesGeneralViewController
        )
        pane.isAccessGranted = { true }
        pane.openAccessibilitySettings = {}
        pane.isMenuBarIconHidden = { own.options.general.hideStatusItem }
        pane.setMenuBarIconHidden = { own.options.general.hideStatusItem = $0 }
        pane.isPaused = { false }
        pane.showWelcomeGuide = {}
        pane.openURL = { _ in }
        pane.updateStatus = { UpdateStatus() }
        pane.settingsFiles = own.center
        pane.chooseExportFile = { _, name, completion in
            world.offeredNames.append(name)
            completion(world.exportAnswer)
        }
        pane.chooseImportFile = { _, completion in
            world.importPanels += 1
            completion(world.importAnswer)
        }
        pane.presentSettingsSheet = { sheet, _ in
            _ = sheet.view
            world.presented.append(sheet)
        }
        pane.dismissSettingsSheet = { world.dismissed.append($0) }
        pane.showNotice = { world.notices.append(($0, $1)) }
        _ = pane.view
        return pane
    }

    private func click(_ button: NSButton, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(button.isHiddenOrHasHiddenAncestor, "\(button.title) is hidden", file: file, line: line)
        XCTAssertTrue(button.isEnabled, "\(button.title) is disabled", file: file, line: line)
        XCTAssertTrue(button.sendAction(button.action, to: button.target), button.title, file: file, line: line)
    }

    private func write(_ settings: String, named name: String = "Other Mac.json") throws -> URL {
        let url = try temporaryFolder(for: self).appendingPathComponent(name)
        try Fixture.file(settings).write(to: url)
        return url
    }

    /// One row above the Welcome Guide: "Settings file", explained in one line, with
    /// "Export…" and "Import…".
    func testTheSettingsFileRowStandsAboveTheWelcomeGuide() throws {
        let own = OwnSettings(for: self)
        let pane = try makePane(own, World())
        let row = try XCTUnwrap(pane.settingsFileRow)
        XCTAssertEqual(row.title, "Settings file")
        XCTAssertEqual(row.explanation, "Save all your settings to a file, or load them from one.")
        XCTAssertEqual(pane.exportSettingsButton.title, "Export…")
        XCTAssertEqual(pane.importSettingsButton.title, "Import…")
        for button in [pane.exportSettingsButton!, pane.importSettingsButton!] {
            XCTAssertEqual(button.bezelStyle, .push)
            XCTAssertTrue(row.controls.contains { $0 === button })
            XCTAssertTrue(button.accessibilityTitleUIElement() as? NSTextField === row.titleLabel, button.title)
            XCTAssertEqual(button.accessibilityHelp(), row.explanation)
            XCTAssertFalse(button.isHiddenOrHasHiddenAncestor)
        }
        // Its own box, between the updates and the Welcome Guide.
        let content = try XCTUnwrap(pane.headerView.superview as? NSStackView)
        let sections = content.arrangedSubviews.filter { $0 is PreferencesGroupSection && !$0.isHidden }
        let index = try XCTUnwrap(sections.firstIndex { $0 === pane.settingsFileSection })
        XCTAssertTrue(sections[index - 1] === pane.updatesSection)
        XCTAssertTrue(sections[index + 1] === pane.welcomeGuideRow.superview?.superview?.superview)
        XCTAssertTrue(sections.last === sections[index + 1])
        XCTAssertNil(pane.settingsFileSection.titleLabel)
        // No import yet: nothing to go back to.
        XCTAssertTrue(pane.previousSettingsRow.isHidden)
        XCTAssertEqual(pane.settingsFileSection.box.visibleRows.count, 1)
        // The row fits: the text and the two buttons do not overlap, the line wraps inside.
        pane.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(pane.view.frame.size, pane.view.fittingSize)
        XCTAssertFalse(pane.view.hasAmbiguousLayout)
        let buttons = row.convert(pane.exportSettingsButton.frame, from: pane.exportSettingsButton.superview)
        let explanation = row.convert(row.explanationLabel.frame, from: row)
        XCTAssertLessThanOrEqual(explanation.maxX, buttons.minX)
        XCTAssertGreaterThanOrEqual(row.explanationLabel.frame.height, row.explanationLabel.intrinsicContentSize.height - 0.5, "not cut")
        XCTAssertLessThan(pane.exportSettingsButton.frame.maxX, pane.importSettingsButton.frame.minX, "Export first")
    }

    /// "Export…": the save panel offers a name with the day, and the file is written
    /// where the user said; a notice says so. Cancel writes nothing.
    func testExportWritesOneFileAndSaysSo() throws {
        let own = OwnSettings(for: self)
        own.options.readOptions()
        own.options.scroll.speed = 4.5
        let world = World()
        let pane = try makePane(own, world)
        let folder = try temporaryFolder(for: self)

        // Cancelled.
        click(pane.exportSettingsButton)
        XCTAssertEqual(world.offeredNames, [SettingsFile.defaultFileName()])
        XCTAssertNotNil(world.offeredNames[0].range(of: #"^Scrollio Settings \d{4}-\d{2}-\d{2}\.json$"#, options: .regularExpression))
        XCTAssertTrue(world.notices.isEmpty)
        XCTAssertTrue(world.presented.isEmpty)

        world.exportAnswer = folder.appendingPathComponent("Scrollio Settings 2026-11-12.json")
        click(pane.exportSettingsButton)
        let url = try XCTUnwrap(world.exportAnswer)
        XCTAssertEqual(try SettingsFile.read(contentsOf: url).get().scrollNumbers["speed"], 4.5)
        XCTAssertEqual(world.notices.map(\.text), ["Settings exported to “Scrollio Settings 2026-11-12.json”."])
        XCTAssertEqual(world.notices.first?.style, .success)
        XCTAssertTrue(world.presented.isEmpty, "no sheet when it worked")
        XCTAssertEqual(own.options.scroll.speed, 4.5, "an export changes nothing")

        // A place that cannot be written: a sheet says why, no notice.
        world.exportAnswer = folder.appendingPathComponent("gone/Settings.json")
        click(pane.exportSettingsButton)
        XCTAssertEqual(world.notices.count, 1)
        let sheet = try XCTUnwrap(world.presented.last)
        XCTAssertEqual(sheet.titleLabel.stringValue, "The settings could not be exported")
        XCTAssertTrue(sheet.detailLabel.stringValue.hasPrefix("Scrollio could not save the file there. "), sheet.detailLabel.stringValue)
        click(sheet.closeButton)
        XCTAssertTrue(world.dismissed.last === sheet)
        XCTAssertNil(pane.settingsSheet)
    }

    /// "Import…": the file is read, a sheet says what it holds, and nothing changes before
    /// "Import" is clicked there. Cancel leaves everything as it was, without a backup.
    func testImportAsksFirstAndCancelChangesNothing() throws {
        let own = OwnSettings(for: self)
        own.options.readOptions()
        own.options.scroll.speed = 7.5
        let world = World()
        let pane = try makePane(own, world)

        // The panel was cancelled.
        click(pane.importSettingsButton)
        XCTAssertEqual(world.importPanels, 1)
        XCTAssertTrue(world.presented.isEmpty)

        world.importAnswer = try write(#""speed":3,"thumbWheelSettings":{"function":"zoom"}"#)
        click(pane.importSettingsButton)
        let sheet = try XCTUnwrap(world.presented.last)
        XCTAssertTrue(pane.settingsSheet === sheet)
        XCTAssertEqual(sheet.titleLabel.stringValue, "Import these settings?")
        XCTAssertEqual(sheet.detailLabel.stringValue, "“Other Mac.json”")
        XCTAssertEqual(sheet.itemLabels.map(\.stringValue), ["Scrolling settings", "Thumb wheel"])
        XCTAssertEqual(own.options.scroll.speed, 7.5, "nothing changed yet")
        XCTAssertEqual(own.options.thumbWheel.function, .scroll)

        click(sheet.closeButton)
        XCTAssertTrue(world.dismissed.last === sheet)
        XCTAssertNil(pane.settingsSheet)
        XCTAssertEqual(own.options.scroll.speed, 7.5)
        XCTAssertTrue(world.notices.isEmpty)
        XCTAssertNil(own.center.latestBackup(), "no backup of an import that was not made")
        XCTAssertTrue(pane.previousSettingsRow.isHidden)
    }

    /// "Import" of the sheet: the settings are in effect, the pane shows them, a notice
    /// says it is done and how to go back, and "Restore…" brings the old ones back.
    func testImportPutsTheSettingsInEffectAndCanBeTakenBack() throws {
        let own = OwnSettings(for: self)
        own.options.readOptions()
        own.options.scroll.speed = 7.5
        let world = World()
        let pane = try makePane(own, world)
        XCTAssertEqual(pane.showInMenuBarSwitch.state, .on)
        let heightBefore = pane.view.frame.height
        // A removal that could be undone: its Undo would put an old entry into the new settings.
        let window = NSWindow(
            contentRect: NSRect(x: -20000, y: -20000, width: 520, height: 300), styleMask: [.titled], backing: .buffered, defer: true
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = pane
        defer { window.contentViewController = nil }
        let undo = try XCTUnwrap(pane.view.window?.undoManager)
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        undo.registerUndo(withTarget: pane) { _ in }
        undo.endUndoGrouping()
        XCTAssertTrue(undo.canUndo)

        world.importAnswer = try write(#""speed":3,"hideStatusItem":true"#)
        click(pane.importSettingsButton)
        let sheet = try XCTUnwrap(world.presented.last)
        click(try XCTUnwrap(sheet.importButton))

        XCTAssertEqual(own.options.scroll.speed, 3)
        XCTAssertTrue(own.options.general.hideStatusItem)
        XCTAssertEqual(statusItem.calls.last, false, "the icon is hidden")
        XCTAssertTrue(world.dismissed.last === sheet)
        XCTAssertNil(pane.settingsSheet)
        XCTAssertEqual(pane.showInMenuBarSwitch.state, .off, "the pane shows the imported setting")
        XCTAssertFalse(undo.canUndo)
        XCTAssertEqual(world.notices.map(\.text), [
            "Settings imported. To go back to the ones from before, choose Restore… under General › Settings file.",
        ])
        XCTAssertEqual(world.notices.first?.style, .success)

        // The way back is in the pane.
        let previous = try XCTUnwrap(pane.previousSettingsRow)
        XCTAssertFalse(previous.isHidden)
        XCTAssertEqual(previous.title, "Settings from before the last import")
        let backup = try XCTUnwrap(own.center.latestBackup())
        XCTAssertEqual(previous.explanation, "Saved on \(SettingsFileText.moment(backup.date)).")
        XCTAssertEqual(pane.restoreSettingsButton.title, "Restore…")
        XCTAssertTrue(pane.restoreSettingsButton.accessibilityTitleUIElement() as? NSTextField === previous.titleLabel)
        XCTAssertGreaterThan(pane.view.fittingSize.height, heightBefore, "the pane makes room for the row")
        XCTAssertEqual(pane.settingsFileSection.box.visibleRows.count, 2)

        // "Restore…" asks with the same sheet, about the backup.
        click(pane.restoreSettingsButton)
        let restore = try XCTUnwrap(world.presented.last)
        XCTAssertFalse(restore === sheet)
        XCTAssertEqual(restore.titleLabel.stringValue, "Import these settings?")
        XCTAssertTrue(restore.detailLabel.stringValue.hasPrefix("“" + backup.url.lastPathComponent + "”. It says it was saved by Scrollio 1.2.3 on "))
        XCTAssertEqual(own.options.scroll.speed, 3, "not before it is confirmed")
        click(try XCTUnwrap(restore.importButton))
        XCTAssertEqual(own.options.scroll.speed, 7.5)
        XCTAssertFalse(own.options.general.hideStatusItem)
        XCTAssertEqual(pane.showInMenuBarSwitch.state, .on)
        XCTAssertEqual(world.notices.count, 2)
        // And that can be taken back too: the newest backup is what was just replaced.
        let newest = try XCTUnwrap(own.center.latestBackup())
        XCTAssertNotEqual(newest.url.lastPathComponent, backup.url.lastPathComponent)
        XCTAssertEqual(try own.center.read(newest.url).get().scrollNumbers["speed"], 3)
    }

    /// A pane that opens later finds the backup of an earlier import.
    func testTheWayBackIsStillThereWhenThePaneOpensAgain() throws {
        let own = OwnSettings(for: self)
        own.options.readOptions()
        _ = try own.center.importSettings(try Fixture.contents(#""speed":3"#)).get()
        let pane = try makePane(own, World())
        XCTAssertFalse(pane.previousSettingsRow.isHidden)
        XCTAssertEqual(pane.view.frame.size, pane.view.fittingSize)
        // The folder was emptied meanwhile: the row goes when the pane is shown again.
        try FileManager.default.removeItem(at: own.backupFolder)
        pane.viewWillAppear()
        XCTAssertTrue(pane.previousSettingsRow.isHidden)
        XCTAssertEqual(pane.view.frame.size, pane.view.fittingSize)
    }

    /// A file that cannot be used changes nothing, and the sheet says why in plain words.
    func testAFileThatCannotBeUsedSaysWhyAndChangesNothing() throws {
        let own = OwnSettings(for: self)
        own.options.readOptions()
        own.options.scroll.speed = 7.5
        own.options.flushPendingSaves()
        let before = own.stored as NSDictionary
        let world = World()
        let pane = try makePane(own, world)
        let folder = try temporaryFolder(for: self)

        let cases: [(Data, String)] = [
            (Data("This is a text file.".utf8), "It is not a Scrollio settings file, or it is damaged. Nothing was changed."),
            (Fixture.file(#""speed":3"#, version: "7"),
             "It was saved by a newer version of Scrollio. Update Scrollio, then import it again. Nothing was changed."),
            (Fixture.file(#""speed":"fast""#), "The file is damaged: its part “speed” cannot be read. Nothing was changed."),
            (Fixture.file(#""warpDrive":1"#), "It holds no settings this version of Scrollio knows. Nothing was changed."),
        ]
        for (index, item) in cases.enumerated() {
            let url = folder.appendingPathComponent("file-\(index).json")
            try item.0.write(to: url)
            world.importAnswer = url
            click(pane.importSettingsButton)
            let sheet = try XCTUnwrap(world.presented.last)
            XCTAssertEqual(sheet.titleLabel.stringValue, "This file cannot be imported")
            XCTAssertEqual(sheet.detailLabel.stringValue, item.1)
            XCTAssertNil(sheet.importButton, "nothing to confirm")
            click(sheet.closeButton)
            XCTAssertNil(pane.settingsSheet)
        }
        XCTAssertEqual(world.presented.count, cases.count)
        XCTAssertEqual(own.options.scroll.speed, 7.5)
        XCTAssertEqual(own.stored as NSDictionary, before)
        XCTAssertTrue(world.notices.isEmpty)
        XCTAssertNil(own.center.latestBackup())
    }

    /// A file whose buttons open or run something: the sheet lists them before the
    /// import, and "Import" still imports when the user clicks it.
    func testAFileWithAScriptShowsItBeforeTheImport() throws {
        let own = OwnSettings(for: self)
        own.options.readOptions()
        let world = World()
        let pane = try makePane(own, world)
        world.importAnswer = try write(#""buttonBindings":["# + Fixture.scriptBinding + "]", named: "From the internet.json")
        click(pane.importSettingsButton)
        let sheet = try XCTUnwrap(world.presented.last)
        XCTAssertEqual(sheet.launchTitleLabel?.stringValue, "1 action opens an app or a file, or runs a script")
        XCTAssertTrue(try XCTUnwrap(sheet.launchList).string.hasSuffix(": runs the script /Users/someone/bin/sync.sh (arguments: --all)"))
        XCTAssertEqual(sheet.closeButton.keyEquivalent, "\r", "Return is Cancel")
        XCTAssertTrue(own.options.buttons.binding.isEmpty)

        click(try XCTUnwrap(sheet.importButton))
        XCTAssertEqual(own.options.buttons.binding.map(\.openTarget?.path), ["/Users/someone/bin/sync.sh"])
        XCTAssertFalse(ShortcutExecutor.shared.opensTargets, "and nothing was started")
    }

    /// When the current settings cannot be saved first, the sheet that asked says so, and
    /// nothing is imported.
    func testAnImportWithoutABackupIsNotMade() throws {
        let own = OwnSettings(for: self)
        own.options.readOptions()
        own.options.scroll.speed = 7.5
        own.center.backups = SettingsBackups(directory: nil)
        let world = World()
        let pane = try makePane(own, world)
        world.importAnswer = try write(#""speed":3"#)
        click(pane.importSettingsButton)
        let sheet = try XCTUnwrap(world.presented.last)
        click(try XCTUnwrap(sheet.importButton))

        XCTAssertEqual(own.options.scroll.speed, 7.5)
        XCTAssertTrue(pane.settingsSheet === sheet, "the same sheet stays and says why")
        XCTAssertTrue(world.dismissed.isEmpty)
        XCTAssertEqual(sheet.titleLabel.stringValue, "The settings were not imported", "nothing is wrong with the file")
        XCTAssertEqual(sheet.detailLabel.stringValue, "Your current settings could not be saved first, so nothing was changed.")
        XCTAssertNil(sheet.importButton)
        XCTAssertTrue(world.notices.isEmpty)
        click(sheet.closeButton)
        XCTAssertNil(pane.settingsSheet)
        XCTAssertTrue(pane.previousSettingsRow.isHidden)
    }

    /// The pane as the app makes it does nothing real under XCTest: no panel, no sheet
    /// without a window, no notice, and the app's own settings are out of reach.
    func testThePaneAsTheAppMakesItIsInertInTheTests() throws {
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesGeneralViewController.self))
        let pane = try XCTUnwrap(
            storyboard.instantiateController(withIdentifier: PANEL_IDENTIFIER.general) as? PreferencesGeneralViewController
        )
        pane.isAccessGranted = { true }
        pane.isPaused = { false }
        _ = pane.view
        XCTAssertTrue(pane.settingsFiles === SettingsFileCenter.live)
        XCTAssertTrue(pane.previousSettingsRow.isHidden)
        click(pane.exportSettingsButton)
        click(pane.importSettingsButton)
        XCTAssertNil(pane.settingsSheet)
        XCTAssertFalse(allSubviews(of: pane.view).contains { $0 is NSTextView })
        // The panels the app would show.
        let export = PreferencesGeneralViewController.makeExportPanel(name: "Scrollio Settings 2026-11-12.json")
        XCTAssertEqual(export.nameFieldStringValue, "Scrollio Settings 2026-11-12.json")
        XCTAssertEqual(export.allowedContentTypes.map(\.identifier), ["public.json"])
        XCTAssertFalse(export.isExtensionHidden)
        XCTAssertEqual(export.prompt, "Export")
        let open = PreferencesGeneralViewController.makeImportPanel()
        XCTAssertEqual(open.allowedContentTypes.map(\.identifier), ["public.json"])
        XCTAssertFalse(open.allowsMultipleSelection)
        XCTAssertFalse(open.canChooseDirectories)
        XCTAssertEqual(open.prompt, "Choose", "nothing is imported by the panel's button")
        XCTAssertEqual(open.message, "Choose a settings file that Scrollio exported.")
    }
}
