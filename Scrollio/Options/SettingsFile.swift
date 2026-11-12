//
//  SettingsFile.swift
//  Scrollio
//  All of the user's settings as one file: "Export…" writes it, "Import…" reads it
//  (General › Settings file). This file is the format, the list of what is in it, the
//  checks of a file that is read, and the two steps themselves; no UI in here.
//
//  The format: JSON (UTF-8), readable and changeable in a text editor.
//
//      {
//        "format": "scrollio-settings",
//        "formatVersion": 1,
//        "appVersion": "1.0.1",
//        "appBuild": "1612",
//        "exported": "2026-11-12T09:42:07Z",
//        "settings": { "smooth": true, "speed": 6.3, "buttonBindings": [ … ], … }
//      }
//
//  "settings" holds the app's own stored representation: each name is the UserDefaults
//  key of that setting (OptionItem), and its value is what the preferences hold under it.
//  A switch is a JSON boolean, a number a JSON number, and what the preferences keep as
//  JSON data (the bindings, the per-app list, the gesture, thumb wheel and Logitech
//  settings, the hold keys) stands in the file as that JSON itself. So the names inside
//  are persisted identifiers like the keys of the preferences: never rename one
//  (AGENTS.md), and that includes the six names of the file's own top level.
//
//  Why JSON and not a property list: the larger half of the settings is JSON already. A
//  property list would hold it as base64 data nobody can read, or as a second
//  representation that has to be kept in step with the first.
//
//  What is in a file and what is not: `exportedKeys` and `leftOut` below. Two things are
//  left out on purpose and never imported: "Let Scrollio manage this mouse" (it stays as
//  it is on this Mac, so a file alone never makes Scrollio write to a mouse it was not
//  allowed to write to) and "Open at login" (the system's own state).
//
//  Reading a file (`read`): at most `maximumFileSize` bytes, JSON, the format's name, a
//  format version this build knows. Then only the names on the allow-list are looked at,
//  each checked for its type; a name the list does not have is ignored. What is JSON in
//  the preferences is decoded by the same decoders as at launch, with their tolerance
//  (one bad value falls back, one unreadable entry of a list does not take the list with
//  it), and what goes into the store afterwards is what those decoders understood, written
//  by the app's own encoders: an entry or a name this version cannot read is left out,
//  not kept for a later version. The four numbers of Scrolling (and of each app's own
//  settings) are brought into the range the panes and the engine work with
//  (`range(ofScrollNumber:)`), and what was corrected is counted for the sheet: the
//  preferences take any number, but a file can come from anywhere, and a dead zone of
//  1e300 is a wheel that does nothing in a setting no pane shows. What a file can make the app do is therefore exactly
//  what `Contents` holds, and the sheet shown before the import is drawn from it
//  (`launchActions`: every app, file and script a button or key would open or run).
//
//  Importing (`apply`): the settings come in group by group (OptionsGroup). A group the
//  file holds replaces that group as a whole: a name of the group that the file does not
//  have reads as it does at launch (a switch or a number is the default, a hold key is
//  "none"). A group the file does not hold stays as it is. The values go into the store
//  under their keys, and then everything is read again exactly as at launch
//  (`Options.reloadFromStore`), so the launch's clean-up runs too, and the observers of
//  the imported groups are told as after a change made by hand. Importing runs nothing:
//  nothing in this file can open an app or start a script.
//
//  Before an import the current settings are written to a backup with the code of an
//  export (`SettingsFileCenter.importSettings`, `SettingsBackups`).
//

import Foundation

enum SettingsFile {

    // MARK: - The format

    /// The value of "format": what makes a JSON file a Scrollio settings file.
    static let formatName = "scrollio-settings"
    /// The newest "formatVersion" this build reads, and the one it writes. A file with a
    /// higher one is refused; raise it only for a change an older build must not read.
    static let formatVersion = 1
    /// ".json": any text editor opens it, the open and save panels know the type
    /// (`public.json`), and nothing has to be registered with macOS. Scrollio claims no
    /// document type: a settings file is imported from Settings, by a click there, never
    /// by opening the file.
    static let fileExtension = "json"
    /// A file larger than this is refused before it is parsed. A real one has a few
    /// kilobytes; 200 apps and 200 buttons stay under 200 KB.
    static let maximumFileSize = 2 * 1024 * 1024

    /// The names of the file's top level. Persisted identifiers: never rename one.
    enum Field {
        static let format = "format"
        static let formatVersion = "formatVersion"
        static let appVersion = "appVersion"
        static let appBuild = "appBuild"
        static let exported = "exported"
        static let settings = "settings"
    }

    // MARK: - What is in a file

    /// How a setting stands in the file, and what `read` checks it for.
    enum Kind {
        /// A JSON boolean.
        case bool
        /// A JSON number (finite).
        case number
        /// A hold key of Scrolling (`ScrollHotkey`), a JSON object. No name: no key.
        case hotkey
        /// The buttons and keys with their actions, a JSON array of `ButtonBinding`.
        case bindings
        /// The per-app list, a JSON array of `Application`.
        case applications
        /// `MouseGestureSettings`, a JSON object.
        case gesture
        /// `LogiWheelSettings`, a JSON object, without "managedByScrollio".
        case logiWheel
        /// `LogiMouseSettings`, a JSON object.
        case logiMouse
        /// `ThumbWheelSettings`, a JSON object.
        case thumbWheel
    }

    struct Key: Equatable {
        /// The UserDefaults key, and the name in the file.
        let name: String
        let group: OptionsGroup
        let kind: Kind
    }

    /// The allow-list: every setting a file holds, in the order it is written. A file's
    /// name that is not here is never read, and no other key of the store is ever touched
    /// by an import.
    static let exportedKeys: [Key] = [
        // Scrolling
        Key(name: OptionItem.Scroll.Smooth, group: .scroll, kind: .bool),
        Key(name: OptionItem.Scroll.Reverse, group: .scroll, kind: .bool),
        Key(name: OptionItem.Scroll.ReverseVertical, group: .scroll, kind: .bool),
        Key(name: OptionItem.Scroll.ReverseHorizontal, group: .scroll, kind: .bool),
        Key(name: OptionItem.Scroll.Step, group: .scroll, kind: .number),
        Key(name: OptionItem.Scroll.Speed, group: .scroll, kind: .number),
        Key(name: OptionItem.Scroll.Duration, group: .scroll, kind: .number),
        Key(name: OptionItem.Scroll.DeadZone, group: .scroll, kind: .number),
        Key(name: OptionItem.Scroll.SmoothSimTrackpad, group: .scroll, kind: .bool),
        Key(name: OptionItem.Scroll.SmoothVertical, group: .scroll, kind: .bool),
        Key(name: OptionItem.Scroll.SmoothHorizontal, group: .scroll, kind: .bool),
        Key(name: OptionItem.Scroll.Dash, group: .scroll, kind: .hotkey),
        Key(name: OptionItem.Scroll.Toggle, group: .scroll, kind: .hotkey),
        Key(name: OptionItem.Scroll.Block, group: .scroll, kind: .hotkey),
        // The thumb wheel
        Key(name: OptionItem.ThumbWheel.Settings, group: .thumbWheel, kind: .thumbWheel),
        // Apps: the "only these apps" switch and the list with each app's own settings
        Key(name: OptionItem.Application.Allowlist, group: .application, kind: .bool),
        Key(name: OptionItem.Application.Applications, group: .application, kind: .applications),
        // Buttons and keys
        Key(name: OptionItem.Button.Bindings, group: .buttons, kind: .bindings),
        // Gestures
        Key(name: OptionItem.Gesture.Settings, group: .gesture, kind: .gesture),
        // Logitech: the wheel and the basics
        Key(name: OptionItem.MouseWheel.Settings, group: .logiWheel, kind: .logiWheel),
        Key(name: OptionItem.MouseBasics.Settings, group: .logiMouse, kind: .logiMouse),
        // General: "Show in menu bar" (stored as its opposite)
        Key(name: OptionItem.General.HideStatusItem, group: .general, kind: .bool),
    ]

    /// The JSON name inside "logiWheelSettings" that is never written and never read:
    /// "Let Scrollio manage this mouse".
    static let managedSwitchName = "managedByScrollio"

    /// A stored value that is not in a file, and why.
    struct LeftOut: Equatable {
        /// The UserDefaults key, or the beginning of several (`isPrefix`).
        let key: String
        let isPrefix: Bool
        let reason: String

        init(_ key: String, prefix: Bool = false, _ reason: String) {
            self.key = key
            self.isPrefix = prefix
            self.reason = reason
        }
    }

    /// Everything else the app's preferences can hold, each with the reason it stays out
    /// of a file. Together with `exportedKeys` this is every key the app or the system
    /// writes there (`SettingsFileFormatTests` saves every setting and looks for a key
    /// that is on neither list). Not UserDefaults keys, and left out too: "Open at login"
    /// (the login item is the system's), "Let Scrollio manage this mouse"
    /// (`managedSwitchName`, a name inside "logiWheelSettings"), and where notices sit and
    /// how they look (a preferences domain of its own, "<bundle id>.toast").
    static let leftOut: [LeftOut] = [
        LeftOut(OptionItem.General.OptionsExist, "marks that settings were saved once; the app writes it itself"),
        LeftOut(OptionItem.General.WelcomeGuideCompletedVersion, "the Welcome Guide's progress on this Mac"),
        LeftOut("preferencesSelectedPane", "window state: the pane that was open last"),
        LeftOut("scrollingAdvancedExpanded", "window state: whether Advanced is open"),
        LeftOut("generalAdvancedExpanded", "retired window state; nothing reads it"),
        LeftOut("durationForOtherTrackpadState", "retired scroll setting, removed at launch"),
        LeftOut("scrollTuning", "retired scroll settings, removed at launch"),
        LeftOut("logitechFeatureCache", "a cache of what a mouse model supports, read again from the mouse"),
        // (A prefix, and not the key's whole name: the boundary lint reads every name that
        // begins with these four letters and a capital as a type of Scrollio/Logi.)
        LeftOut("Logi", prefix: true, "a developer's trace switch that the debug build reads and nothing writes"),
        LeftOut("SU", prefix: true, "the updater's own choices and state (Sparkle keeps them in the same preferences)"),
        LeftOut("NSStatusItem ", prefix: true, "where the menu bar icon sits and whether macOS shows it, kept by macOS"),
        LeftOut("NSWindow Frame ", prefix: true, "where a window was, kept by macOS"),
        LeftOut("NSSplitView Subview Frames ", prefix: true, "a debug window's layout, kept by macOS"),
        LeftOut("NSNav", prefix: true, "where the open and save panels were, kept by macOS"),
        LeftOut("NSOSPLastRootDirectory", "where the open panel was, kept by macOS"),
    ]

    static func isExported(_ key: String) -> Bool {
        return exportedKeys.contains { $0.name == key }
    }

    static func isLeftOut(_ key: String) -> Bool {
        return leftOut.contains { $0.isPrefix ? key.hasPrefix($0.key) : key == $0.key }
    }

    // MARK: - What a file was found to hold

    /// The lines of a file above its settings. For the reader only: nothing is decided by them.
    struct Header: Equatable {
        var appVersion: String?
        var appBuild: String?
        var exported: Date?
    }

    /// An action that opens an app or a file, or runs a script, when its button or key is
    /// pressed. The sheet before an import lists each one.
    struct LaunchAction: Equatable {
        let trigger: RecordedEvent
        let target: OpenTargetPayload
        /// The app whose own buttons the action is stored with; nil for the buttons of
        /// every app. (No version runs an app's own buttons yet; they are listed anyway.)
        let applicationPath: String?
    }

    /// A file that was read and found usable: only what is on the allow-list, each value
    /// of its type and decoded as at launch. Nothing of it is in effect before `apply`.
    struct Contents {
        var header = Header()
        /// The groups the file holds: the ones an import replaces.
        var groups: Set<OptionsGroup> = []

        /// "hideStatusItem".
        var hidesMenuBarIcon: Bool?
        /// The switches of Scrolling, by their key.
        var scrollSwitches: [String: Bool] = [:]
        /// The numbers of Scrolling, by their key.
        var scrollNumbers: [String: Double] = [:]
        /// The hold keys of Scrolling, by their key. A key not in here is "none".
        var scrollHotkeys: [String: ScrollHotkey] = [:]
        var thumbWheel: ThumbWheelSettings?
        var allowlist: Bool?
        var applications: [Application]?
        var bindings: [ButtonBinding]?
        var gesture: MouseGestureSettings?
        /// Its "Let Scrollio manage this mouse" means nothing: `apply` puts this Mac's in.
        var logiWheel: LogiWheelSettings?
        var logiMouse: LogiMouseSettings?
        /// Entries of the two lists that this version cannot read. They are left out.
        var unreadableEntries = 0
        /// Numbers of Scrolling, the file's or an app's own, that were out of range and
        /// were brought into it.
        var correctedValues = 0

        /// Every action of the file that opens an app or a file, or runs a script: of the
        /// buttons and keys, switched on or off, and of each app's own buttons.
        var launchActions: [LaunchAction] {
            var actions: [LaunchAction] = []
            for binding in bindings ?? [] {
                if let target = binding.openTarget {
                    actions.append(LaunchAction(trigger: binding.triggerEvent, target: target, applicationPath: nil))
                }
            }
            for application in applications ?? [] {
                for binding in application.buttons?.binding ?? [] {
                    if let target = binding.openTarget {
                        actions.append(LaunchAction(trigger: binding.triggerEvent, target: target, applicationPath: application.path))
                    }
                }
            }
            return actions
        }

        /// The file has Logitech values (the wheel's or the basics').
        var holdsLogitechValues: Bool {
            return groups.contains(.logiWheel) || groups.contains(.logiMouse)
        }
    }

    /// Why a file cannot be used, or an export or import could not be done.
    enum Problem: Error, Equatable {
        /// The file could not be opened or read; the system's own words.
        case cannotRead(String)
        /// Larger than `maximumFileSize`.
        case tooLarge
        /// Not JSON, or JSON without the format's name: some other file, or a broken one.
        case notASettingsFile
        /// Its format version is newer than this build knows.
        case newerFormat
        /// A settings file, but a part of it is not what it has to be: the name of the part.
        case damaged(String)
        /// A settings file without a single setting this build knows.
        case nothingToImport
        /// The file could not be written; the system's own words.
        case cannotWrite(String)
        /// The current settings could not be saved before an import: nothing was changed.
        case backupFailed(String)
        /// The store is not open to settings files (the app's real preferences under XCTest).
        case storeUnavailable
    }

    // MARK: - Reading

    /// Reads the file at `url`: only a regular file, and never more than
    /// `maximumFileSize` bytes of it.
    ///
    /// It is opened without waiting and then asked what it is, on the opened file itself
    /// (so it cannot be swapped between the question and the read). A named pipe called
    /// "settings.json" held a plain open, on the main thread, until somebody wrote to it;
    /// a device would be read without end. A file's size is known before a byte is read.
    static func read(contentsOf url: URL) -> Result<Contents, Problem> {
        func systemReason() -> String {
            return NSError(domain: NSPOSIXErrorDomain, code: Int(errno)).localizedDescription
        }
        let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return .failure(.cannotRead(systemReason())) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { return .failure(.cannotRead(systemReason())) }
        guard info.st_mode & S_IFMT == S_IFREG else { return .failure(.notASettingsFile) }
        guard info.st_size <= off_t(maximumFileSize) else { return .failure(.tooLarge) }
        let data: Data
        do {
            data = try handle.read(upToCount: maximumFileSize + 1) ?? Data()
        } catch {
            return .failure(.cannotRead(error.localizedDescription))
        }
        return read(data)
    }

    /// Checks `data` and decodes what is on the allow-list. Pure: nothing is changed.
    static func read(_ data: Data) -> Result<Contents, Problem> {
        guard data.count <= maximumFileSize else { return .failure(.tooLarge) }
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              root[Field.format] as? String == formatName else {
            return .failure(.notASettingsFile)
        }
        guard let version = integer(root[Field.formatVersion]), version >= 1 else {
            return .failure(.damaged(Field.formatVersion))
        }
        guard version <= formatVersion else { return .failure(.newerFormat) }
        guard let settings = root[Field.settings] as? [String: Any] else {
            return .failure(.damaged(Field.settings))
        }

        var contents = Contents()
        contents.header = header(of: root)
        for key in exportedKeys {
            guard let value = settings[key.name] else { continue }
            guard take(value, for: key, into: &contents) else {
                return .failure(.damaged(key.name))
            }
            contents.groups.insert(key.group)
        }
        guard !contents.groups.isEmpty else { return .failure(.nothingToImport) }
        return .success(contents)
    }

    /// Puts the value of one allow-listed name into `contents`. False: not of its type.
    private static func take(_ value: Any, for key: Key, into contents: inout Contents) -> Bool {
        switch key.kind {
        case .bool:
            guard let flag = bool(value) else { return false }
            switch key.name {
            case OptionItem.General.HideStatusItem: contents.hidesMenuBarIcon = flag
            case OptionItem.Application.Allowlist: contents.allowlist = flag
            default: contents.scrollSwitches[key.name] = flag
            }
        case .number:
            guard let number = number(value) else { return false }
            let kept = inRange(number, scrollNumber: key.name)
            contents.scrollNumbers[key.name] = kept
            if kept != number { contents.correctedValues += 1 }
        case .hotkey:
            guard let hotkey: ScrollHotkey = decoded(value) else { return false }
            contents.scrollHotkeys[key.name] = hotkey
        case .bindings:
            guard let entries = value as? [Any] else { return false }
            let bindings: [ButtonBinding] = decodedEntries(entries)
            contents.bindings = bindings
            contents.unreadableEntries += entries.count - bindings.count
        case .applications:
            guard let entries = value as? [Any] else { return false }
            var applications: [Application] = []
            for entry in entries {
                var corrected = 0
                guard let application: Application = decoded(applicationEntry(entry, corrected: &corrected)) else { continue }
                applications.append(application)
                contents.correctedValues += corrected
            }
            contents.applications = applications
            contents.unreadableEntries += entries.count - applications.count
        case .gesture:
            guard let gesture: MouseGestureSettings = decoded(value) else { return false }
            contents.gesture = gesture
        case .logiWheel:
            guard let wheel: LogiWheelSettings = decoded(value) else { return false }
            contents.logiWheel = wheel
        case .logiMouse:
            guard let mouse: LogiMouseSettings = decoded(value) else { return false }
            contents.logiMouse = mouse
        case .thumbWheel:
            guard let thumbWheel: ThumbWheelSettings = decoded(value) else { return false }
            contents.thumbWheel = thumbWheel
        }
        return true
    }

    // MARK: - Numbers in range

    /// The dead zone a file may bring. No pane sets it and the app only ever writes its
    /// default (1); a file's is kept within a factor of ten of that. Far below, a glide
    /// takes very long to count as ended; far above, the frames of a scroll are slower
    /// than the dead zone and none is posted: the wheel does nothing.
    static let deadZoneRange: ClosedRange<Double> = 0.1...10

    /// The range a number of Scrolling is kept in, by its name (the UserDefaults key, and
    /// the name inside an app's own "scroll"): what the pane's sliders can set, and for
    /// the dead zone `deadZoneRange`.
    static func range(ofScrollNumber name: String) -> ClosedRange<Double>? {
        switch name {
        case OptionItem.Scroll.Step: return ScrollSliderSetting.smallestStep.range
        case OptionItem.Scroll.Speed: return ScrollSliderSetting.speed.range
        case OptionItem.Scroll.Duration: return ScrollSliderSetting.glideTime.range
        case OptionItem.Scroll.DeadZone: return deadZoneRange
        default: return nil
        }
    }

    static func inRange(_ number: Double, scrollNumber name: String) -> Double {
        guard let range = range(ofScrollNumber: name) else { return number }
        return min(max(number, range.lowerBound), range.upperBound)
    }

    /// An app's entry as it goes to the decoder: the numbers of its own scroll settings
    /// brought into range, in the JSON itself (changing them on the decoded object would
    /// tell the app's observers of a change). Anything else is left for the decoder to
    /// judge. `corrected` counts what was changed.
    private static func applicationEntry(_ entry: Any, corrected: inout Int) -> Any {
        guard var object = entry as? [String: Any], var scroll = object["scroll"] as? [String: Any] else { return entry }
        for key in exportedKeys where key.kind == .number {
            guard let number = number(scroll[key.name]) else { continue }
            let kept = inRange(number, scrollNumber: key.name)
            if kept != number {
                scroll[key.name] = kept
                corrected += 1
            }
        }
        object["scroll"] = scroll
        return object
    }

    /// A JSON object of the file as the model's own decoder reads it (the decoder the
    /// preferences are read with at launch). Nil: not an object, not one that can be
    /// written as JSON again, or the decoder refused it.
    ///
    /// `isValidJSONObject` is not a formality: JSONSerialization reads a number such as
    /// -1e999 as negative infinity, and writing that back raises an Objective-C
    /// exception, which `try?` does not catch. The launch has the same guard
    /// (`Options.decodeButtonBindingsWithUnknowns`).
    private static func decoded<Value: Decodable>(_ value: Any) -> Value? {
        guard let object = value as? [String: Any],
              JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    /// The entries of a list that the model's decoder can read, in their order. One that
    /// it cannot read does not take the others with it, as at launch; here it is left out.
    private static func decodedEntries<Value: Decodable>(_ entries: [Any]) -> [Value] {
        return entries.compactMap { decoded($0) }
    }

    private static func header(of root: [String: Any]) -> Header {
        var header = Header()
        header.appVersion = versionText(root[Field.appVersion])
        header.appBuild = versionText(root[Field.appBuild])
        if let text = root[Field.exported] as? String {
            header.exported = ISO8601DateFormatter().date(from: text)
        }
        return header
    }

    /// A version or build as a file may say it: short, and only letters, digits, ".", "+"
    /// and "-". The sheet shows it, and a file is not to put a sentence there.
    static func versionText(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty, text.count <= 24 else { return nil }
        let allowed = CharacterSet(charactersIn: "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.+-")
        return text.unicodeScalars.allSatisfy(allowed.contains) ? text : nil
    }

    // MARK: - JSON values

    /// A JSON boolean: `true` or `false`, not a number.
    static func bool(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    /// A JSON number that is finite, not a boolean.
    static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        return double.isFinite ? double : nil
    }

    /// A JSON number that is a whole number an Int holds.
    static func integer(_ value: Any?) -> Int? {
        guard let double = number(value), double == double.rounded(), abs(double) < 1e15 else { return nil }
        return Int(double)
    }

    // MARK: - Exporting

    /// The settings of `options` as a file's bytes. The store is made complete and current
    /// first (`saveOptions`: every group, as the app writes it), and the file is what the
    /// store then holds under the keys of the allow-list.
    static func export(
        from options: Options,
        bundleInfo: [String: Any] = Bundle.main.infoDictionary ?? [:],
        now: Date = Date()
    ) -> Result<Data, Problem> {
        assertMainThread()
        guard options.writesToDefaults else { return .failure(.storeUnavailable) }
        options.saveOptions()

        let defaults = options.defaults
        var settings: [(String, Any)] = []
        for key in exportedKeys {
            if let value = fileValue(of: key, in: defaults) {
                settings.append((key.name, value))
            }
        }
        var header: [(String, Any)] = [
            (Field.format, formatName),
            (Field.formatVersion, formatVersion),
        ]
        if let version = versionText(bundleInfo["CFBundleShortVersionString"]) {
            header.append((Field.appVersion, version))
        }
        if let build = versionText(bundleInfo["CFBundleVersion"]) {
            header.append((Field.appBuild, build))
        }
        let formatter = ISO8601DateFormatter()
        header.append((Field.exported, formatter.string(from: now)))
        return .success(Data(SettingsFileJSON.fileText(header: header, settings: settings).utf8))
    }

    /// What the store holds under `key`, as it stands in a file. Nil: nothing stored, or
    /// something the app itself would not read (it is left out, and reads as the default).
    private static func fileValue(of key: Key, in defaults: UserDefaults) -> Any? {
        guard let stored = defaults.object(forKey: key.name) else { return nil }
        switch key.kind {
        case .bool:
            return defaults.bool(forKey: key.name)
        case .number:
            guard let number = stored as? Double, number.isFinite else { return nil }
            return number
        case .bindings, .applications:
            guard let data = stored as? Data,
                  let list = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return nil }
            return list
        case .hotkey, .gesture, .logiMouse, .thumbWheel:
            guard let data = stored as? Data,
                  let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
            return object
        case .logiWheel:
            guard let data = stored as? Data,
                  var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
            object[managedSwitchName] = nil
            return object
        }
    }

    // MARK: - Importing

    /// Puts `contents` in effect: the groups it holds replace those of `options`, in the
    /// store and in memory, and their observers are told. The caller has saved the current
    /// settings first (`SettingsFileCenter.importSettings`). False: the store is not open
    /// to settings files, and nothing was changed. Runs nothing. Main thread.
    @discardableResult
    static func apply(_ contents: Contents, to options: Options) -> Bool {
        assertMainThread()
        guard options.writesToDefaults else { return false }
        // What was changed and not written yet, in any group, is in the store before the
        // store is read again.
        options.saveOptions()

        let defaults = options.defaults
        for key in exportedKeys where contents.groups.contains(key.group) {
            defaults.removeObject(forKey: key.name)
        }
        for (name, value) in storeValues(of: contents, managedByScrollio: options.logiMouseManaged) {
            defaults.set(value, forKey: name)
        }
        options.reloadFromStore(notifying: OptionsGroup.allCases.filter(contents.groups.contains))
        return true
    }

    /// What goes into the store for `contents`, by key: a switch as a Bool, a number as a
    /// Double, everything else as the JSON data the app's own encoders make of it
    /// (`Options.save(group:)` writes the same). `managedByScrollio` is this Mac's "Let
    /// Scrollio manage this mouse": whatever the file said, it stays.
    static func storeValues(of contents: Contents, managedByScrollio: Bool) -> [String: Any] {
        let encoder = JSONEncoder()
        var values: [String: Any] = [:]
        if let hidden = contents.hidesMenuBarIcon {
            values[OptionItem.General.HideStatusItem] = hidden
        }
        for (name, flag) in contents.scrollSwitches {
            values[name] = flag
        }
        for (name, number) in contents.scrollNumbers {
            values[name] = number
        }
        for (name, hotkey) in contents.scrollHotkeys {
            values[name] = try? encoder.encode(hotkey)
        }
        if let thumbWheel = contents.thumbWheel {
            values[OptionItem.ThumbWheel.Settings] = try? encoder.encode(thumbWheel)
        }
        if let allowlist = contents.allowlist {
            values[OptionItem.Application.Allowlist] = allowlist
        }
        if let applications = contents.applications {
            values[OptionItem.Application.Applications] = try? encoder.encode(applications)
        }
        if let bindings = contents.bindings {
            values[OptionItem.Button.Bindings] = try? encoder.encode(bindings)
        }
        if let gesture = contents.gesture {
            values[OptionItem.Gesture.Settings] = try? encoder.encode(gesture)
        }
        if var wheel = contents.logiWheel {
            wheel.managedByScrollio = managedByScrollio
            values[OptionItem.MouseWheel.Settings] = try? encoder.encode(wheel)
        }
        if let mouse = contents.logiMouse {
            values[OptionItem.MouseBasics.Settings] = try? encoder.encode(mouse)
        }
        return values
    }

    // MARK: - Names

    /// "2026-11-12": the day in a file's name, in the user's time zone.
    static func dayStamp(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// The name the save panel offers: "Scrollio Settings 2026-11-12.json".
    static func defaultFileName(now: Date = Date(), timeZone: TimeZone = .current) -> String {
        let name = String(
            format: NSLocalizedString("general-settings-file-default-name", comment: ""),
            dayStamp(now, timeZone: timeZone)
        )
        return name + "." + fileExtension
    }
}

// MARK: - The file's text

/// Writes the JSON of a settings file: two spaces per level, one name per line, numbers
/// as short as they can be read back exactly ("6.3", not "6.2999999999999998", which is
/// what JSONSerialization writes). The top level and "settings" keep the order they are
/// given in; every object inside is sorted by name, so a file of the same settings is the
/// same text.
enum SettingsFileJSON {

    static func fileText(header: [(String, Any)], settings: [(String, Any)]) -> String {
        var lines = header.map { "  \(quoted($0.0)): \(text(of: $0.1, depth: 1))," }
        if settings.isEmpty {
            lines.append("  \(quoted(SettingsFile.Field.settings)): {}")
        } else {
            lines.append("  \(quoted(SettingsFile.Field.settings)): {")
            let last = settings.count - 1
            for (index, entry) in settings.enumerated() {
                lines.append("    \(quoted(entry.0)): \(text(of: entry.1, depth: 2))" + (index < last ? "," : ""))
            }
            lines.append("  }")
        }
        return "{\n" + lines.joined(separator: "\n") + "\n}\n"
    }

    /// A JSON value as text. `depth`: how deep the value's own line stands.
    static func text(of value: Any, depth: Int = 0) -> String {
        let inner = String(repeating: "  ", count: depth + 1)
        let outer = String(repeating: "  ", count: depth)
        if value is NSNull {
            return "null"
        }
        if let string = value as? String {
            return quoted(string)
        }
        if let number = value as? NSNumber {
            return text(of: number)
        }
        if let list = value as? [Any] {
            guard !list.isEmpty else { return "[]" }
            let items = list.map { inner + text(of: $0, depth: depth + 1) }
            return "[\n" + items.joined(separator: ",\n") + "\n" + outer + "]"
        }
        if let object = value as? [String: Any] {
            guard !object.isEmpty else { return "{}" }
            let items = object.keys.sorted().map { name in
                inner + quoted(name) + ": " + text(of: object[name] as Any, depth: depth + 1)
            }
            return "{\n" + items.joined(separator: ",\n") + "\n" + outer + "}"
        }
        return "null"
    }

    private static func text(of number: NSNumber) -> String {
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue ? "true" : "false"
        }
        if CFNumberIsFloatType(number) {
            let double = number.doubleValue
            // Swift writes the shortest text that reads back as the same number.
            return double.isFinite ? "\(double)" : "null"
        }
        return number.stringValue
    }

    static func quoted(_ string: String) -> String {
        var out = "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }
}
