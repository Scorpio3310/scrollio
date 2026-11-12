//
//  SettingsFileCenter.swift
//  Scrollio
//  What General's "Settings file" row does with a file (the format and its checks are in
//  SettingsFile.swift): write the settings to the place the user chose, read a file the
//  user chose, and import it. Nothing is lost by an import: before the settings change,
//  the current ones are written to a backup with the code of an export, and only then
//  the file's are put in effect. A backup that cannot be written stops the import.
//
//  The backups (`SettingsBackups`) are settings files like any other, kept in
//  ~/Library/Application Support/<bundle id>/Settings Backups, named by the moment (UTC)
//  they were written: the last five, older ones are deleted. No two of them hold the same
//  settings: when the settings an import is about to replace are already in a backup,
//  that backup becomes the newest and no second one is written. (Going back and forth
//  between two states would otherwise fill the five places with copies of those two, and
//  the user's own settings from before the first import would be the ones deleted.)
//  General's "Restore…" opens the folder in an open panel; the chosen backup goes through
//  the same import, with the same sheet before it, so going back can be undone the same way.
//
//  Under XCTest nothing real is touched unless a test hands it in: the app's preferences
//  are closed to settings files (`Options.writesToDefaults`), and `SettingsBackups.live`
//  has no folder, so an import that a test forgot to prepare is refused and writes nothing.
//

import Foundation

// MARK: - Backups

/// The settings from before an import, as files in one folder.
struct SettingsBackups {

    /// How many are kept.
    static let keepCount = 5
    /// A backup's name is this, its moment in UTC and the extension: "Scrollio Settings
    /// Backup 2026-11-12 09.42.07 UTC.json". The name is how the folder's backups are told
    /// from anything else in it and put in order, so it is the same in every language and
    /// never changes.
    ///
    /// Names only go forward. They are UTC, so a journey west or the hour that summer
    /// time gives back does not put a new backup before an old one; and when the clock
    /// itself went back, a new backup is named one second after the newest there is
    /// (`moment(for:)`). A backup named by the wall clock could sort as the oldest of the
    /// folder and be deleted by the very write that made it.
    static let namePrefix = "Scrollio Settings Backup "
    static let nameSuffix = " UTC"
    private static let stampFormat = "yyyy-MM-dd HH.mm.ss"

    /// Where the backups are; nil: nowhere, every write fails.
    let directory: URL?
    var fileManager: FileManager = .default

    /// ~/Library/Application Support/<bundle id>/Settings Backups in the app; no folder
    /// under XCTest.
    static var live: SettingsBackups {
        guard !AppRuntime.isRunningXCTest,
              let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return SettingsBackups(directory: nil)
        }
        let folder = Bundle.main.bundleIdentifier ?? "Scrollio"
        return SettingsBackups(directory: support
            .appendingPathComponent(folder, isDirectory: true)
            .appendingPathComponent("Settings Backups", isDirectory: true))
    }

    struct Entry: Equatable {
        let url: URL
        /// The moment in its name: when it was written (or a second after the backup
        /// before it, when the clock had gone back).
        let date: Date
    }

    enum Failure: Error {
        case noFolder
    }

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = stampFormat
        return formatter
    }()

    /// "Scrollio Settings Backup 2026-11-12 09.42.07 UTC.json".
    static func name(for moment: Date) -> String {
        return namePrefix + stampFormatter.string(from: moment) + nameSuffix + "." + SettingsFile.fileExtension
    }

    /// The moment a backup written at `now` is named by: `now` to the second, or one
    /// second after the newest backup there is, whichever is later.
    func moment(for now: Date) -> Date {
        let second = Date(timeIntervalSince1970: now.timeIntervalSince1970.rounded(.down))
        guard let newest = entries().first else { return second }
        return max(second, newest.date.addingTimeInterval(1))
    }

    /// Keeps `data` as the newest backup, then deletes all but the newest `keepCount`
    /// (never the newest itself). Throws when the folder or the file cannot be made;
    /// nothing else is touched then.
    ///
    /// `holdsTheSame` says of a backup that is already there whether it holds what `data`
    /// holds. Then no second one is written: that backup becomes the newest, under the
    /// name a new one would have got.
    @discardableResult
    func write(_ data: Data, now: Date = Date(), holdsTheSame: ((Data) -> Bool)? = nil) throws -> URL {
        guard let directory else { throw Failure.noFolder }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = freeURL(in: directory, from: moment(for: now))
        if let holdsTheSame, let twin = entries().first(where: { entry in
            guard case .success(let kept) = SettingsFile.data(ofFileAt: entry.url) else { return false }
            return holdsTheSame(kept)
        }), (try? fileManager.moveItem(at: twin.url, to: url)) != nil {
            prune(keeping: url)
            return url
        }
        try data.write(to: url, options: .atomic)
        prune(keeping: url)
        return url
    }

    /// The first name from `moment` on that no file has. (After `moment(for:)` it is that
    /// moment's; an earlier file is never written over, whatever is in the folder.)
    private func freeURL(in directory: URL, from moment: Date) -> URL {
        var moment = moment
        var url = directory.appendingPathComponent(Self.name(for: moment))
        while fileManager.fileExists(atPath: url.path) {
            moment += 1
            url = directory.appendingPathComponent(Self.name(for: moment))
        }
        return url
    }

    /// The backups in the folder, newest first. Only files with a backup's name count.
    func entries() -> [Entry] {
        guard let directory,
              let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return [] }
        let ending = Self.nameSuffix + "." + SettingsFile.fileExtension
        let entries: [Entry] = names.compactMap { name in
            guard name.hasPrefix(Self.namePrefix), name.hasSuffix(ending) else { return nil }
            let stamp = String(name.dropFirst(Self.namePrefix.count).dropLast(ending.count))
            guard stamp.count == Self.stampFormat.count, let date = Self.stampFormatter.date(from: stamp),
                  Self.name(for: date) == name else { return nil }
            return Entry(url: directory.appendingPathComponent(name), date: date)
        }
        return entries.sorted { $0.date > $1.date }
    }

    /// The newest backup.
    var latest: Entry? {
        return entries().first
    }

    /// Deletes the backups beyond the newest `keepCount`, and never `written`. Nothing
    /// else in the folder.
    private func prune(keeping written: URL) {
        for entry in entries().dropFirst(Self.keepCount) where entry.url.lastPathComponent != written.lastPathComponent {
            try? fileManager.removeItem(at: entry.url)
        }
    }
}

// MARK: - Export, read, import

/// The three things the "Settings file" row does. The app's is `live`; a test makes one
/// around settings and a folder of its own.
final class SettingsFileCenter {

    /// The app's settings, and the backups in Application Support.
    static let live = SettingsFileCenter()

    /// The settings a file is made from and imported into.
    var options: () -> Options = { Options.shared }
    var backups: SettingsBackups = .live
    /// The app's Info.plist, for the version a file says it was saved by.
    var bundleInfo: () -> [String: Any] = { Bundle.main.infoDictionary ?? [:] }
    var now: () -> Date = { Date() }
    /// What follows no observer of the settings: the scroll engine remembers the app that
    /// was scrolled in last (an entry of the list that was just replaced) and the hold
    /// keys that are down.
    var afterImport: () -> Void = { ScrollCore.shared.settingsWereReplaced() }
    /// One line per export and import in the `app` log. Never a path or a file's name.
    var log: (String) -> Void = { AppSystemLog.note($0) }

    /// Writes the settings to `url`. Nil: done.
    func export(to url: URL) -> SettingsFile.Problem? {
        switch SettingsFile.export(from: options(), bundleInfo: bundleInfo(), now: now()) {
        case .failure(let problem):
            log("Settings file: not exported (\(Self.logName(of: problem)))")
            return problem
        case .success(let data):
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                log("Settings file: not exported (the file could not be written)")
                return .cannotWrite(error.localizedDescription)
            }
            log("Settings file: exported (\(data.count) bytes)")
            return nil
        }
    }

    /// Reads and checks the file at `url`. Changes nothing.
    func read(_ url: URL) -> Result<SettingsFile.Contents, SettingsFile.Problem> {
        let result = SettingsFile.read(contentsOf: url)
        if case .failure(let problem) = result {
            log("Settings file: a file was not usable (\(Self.logName(of: problem)))")
        }
        return result
    }

    /// Imports `contents`: the current settings are written to a backup, then the file's
    /// are put in effect. Returns the backup, or why nothing was changed.
    func importSettings(_ contents: SettingsFile.Contents) -> Result<URL, SettingsFile.Problem> {
        let options = self.options()
        // Before anything is written, the backup included: every value of the file can be
        // put in the form the store takes.
        guard SettingsFile.storeValues(of: contents, managedByScrollio: options.logiMouseManaged) != nil else {
            log("Settings file: not imported (\(Self.logName(of: .cannotStore)))")
            return .failure(.cannotStore)
        }
        let backup: URL
        switch SettingsFile.export(from: options, bundleInfo: bundleInfo(), now: now()) {
        case .failure(let problem):
            log("Settings file: not imported (\(Self.logName(of: problem)))")
            return .failure(problem)
        case .success(let data):
            do {
                backup = try backups.write(data, now: now(), holdsTheSame: { SettingsFile.holdSameSettings($0, data) })
            } catch {
                log("Settings file: not imported (the current settings could not be saved first)")
                return .failure(.backupFailed(Self.text(of: error)))
            }
        }
        guard SettingsFile.apply(contents, to: options) else {
            log("Settings file: not imported (\(Self.logName(of: .storeUnavailable)))")
            return .failure(.storeUnavailable)
        }
        afterImport()
        let groups = OptionsGroup.allCases.filter(contents.groups.contains).map { "\($0)" }.joined(separator: ", ")
        log("Settings file: imported (\(groups); \(contents.launchActions.count) action(s) that open or run something; "
            + "\(contents.leftOutCount) entr\(contents.leftOutCount == 1 ? "y" : "ies") left out)")
        return .success(backup)
    }

    /// The newest of the settings kept from before an import, if there is one.
    func latestBackup() -> SettingsBackups.Entry? {
        return backups.latest
    }

    /// The folder the backups are in, when there is at least one: where "Restore…" opens.
    func backupFolder() -> URL? {
        return backups.latest == nil ? nil : backups.directory
    }

    private static func text(of error: Error) -> String {
        if case SettingsBackups.Failure.noFolder = error { return "" }
        return error.localizedDescription
    }

    /// A problem for the log: its kind, without the system's words (they can hold a path).
    static func logName(of problem: SettingsFile.Problem) -> String {
        switch problem {
        case .cannotRead: return "the file could not be read"
        case .tooLarge: return "too large"
        case .notASettingsFile: return "not a settings file"
        case .newerFormat: return "a newer format"
        case .damaged(let part): return "damaged: \(SettingsFile.isExported(part) || part == SettingsFile.Field.settings || part == SettingsFile.Field.formatVersion ? part : "?")"
        case .nothingToImport: return "no settings this version knows"
        case .tooManyEntries: return "too many buttons or apps"
        case .cannotStore: return "a value could not be encoded"
        case .cannotWrite: return "the file could not be written"
        case .backupFailed: return "the current settings could not be saved first"
        case .storeUnavailable: return "the settings are not open to files here"
        }
    }
}
