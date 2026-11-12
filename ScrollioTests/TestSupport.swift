//
//  TestSupport.swift
//  ScrollioTests
//
//  What several test classes share.
//

import XCTest
@testable import Scrollio_Debug

/// A `UserDefaults` store of a test's own, kept in a folder of the temporary directory that
/// is removed when the test ends.
///
/// Why not `UserDefaults(suiteName: "ScrollioTests.<area>.<UUID>")`: the preferences daemon
/// keeps a file for such a suite in ~/Library/Preferences also after
/// `removePersistentDomain(forName:)` emptied it. The suite left about 170 of them in the
/// home folder at every run. A suite named by an absolute path is stored at that path
/// (`<path>.plist`), so it goes with its folder.
///
///     let defaults = TestDefaults.make(for: self)          // in setUp or in a test
///
/// Without a test at hand (a helper object that outlives no test), keep the store itself:
/// it removes its folder when it is let go, or when `remove()` is called.
final class TestDefaults {

    let defaults: UserDefaults
    /// The suite's name (a path), for the calls that take one: `persistentDomain(forName:)`.
    let suiteName: String
    private var folder: URL?

    init() {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScrollioTests-defaults-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            XCTFail("could not make a folder for a test's settings: \(error)")
        }
        self.folder = folder
        suiteName = folder.appendingPathComponent("suite").path
        // Nil only for the app's own domain and the global one, which a path never is.
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        remove()
    }

    /// A new, empty store that is removed when `test` ends.
    static func make(for test: XCTestCase) -> UserDefaults {
        return makeStore(for: test).defaults
    }

    /// The same, with the suite's name.
    static func makeStore(for test: XCTestCase) -> TestDefaults {
        let store = TestDefaults()
        test.addTeardownBlock { store.remove() }
        return store
    }

    /// Empties the store and removes its folder. Safe to call twice.
    func remove() {
        guard let folder else { return }
        self.folder = nil
        defaults.removePersistentDomain(forName: suiteName)
        // The daemon has taken the removal before the folder goes: it writes nothing after.
        CFPreferencesAppSynchronize(suiteName as CFString)
        try? FileManager.default.removeItem(at: folder)
    }

    /// The file a suite of this store is kept in, for the tests of the helper itself.
    var fileURL: URL {
        return URL(fileURLWithPath: suiteName + ".plist")
    }
}

/// What `Options.readOptions()` replaces in the shared settings besides the scroll
/// options: taken before a test reads settings from a store of its own, put back after it,
/// so the test leaves the shared object as it found it.
struct OptionsSnapshot {
    private let hideStatusItem = Options.shared.general.hideStatusItem
    private let bindings = Options.shared.buttons.binding
    private let allowlist = Options.shared.application.allowlist
    private let applications = Options.shared.application.applications
    private let gesture = Options.shared.gesture
    private let logiWheel = Options.shared.logiWheel
    private let logiMouse = Options.shared.logiMouse
    private let thumbWheel = Options.shared.thumbWheel

    func restore() {
        let options = Options.shared
        if options.general.hideStatusItem != hideStatusItem {
            options.general.hideStatusItem = hideStatusItem
        }
        options.buttons.binding = bindings
        ButtonUtils.shared.invalidateCache()
        options.application.allowlist = allowlist
        options.application.applications = applications
        options.gesture = gesture
        options.logiWheel = logiWheel
        options.logiMouse = logiMouse
        options.thumbWheel = thumbWheel
    }
}

/// The helper itself: its store is a file in the temporary folder, never one in
/// ~/Library/Preferences, and nothing of it is left when it is removed.
final class TestDefaultsTests: XCTestCase {

    func testTheStoreIsKeptInATemporaryFolderAndGoesWithIt() throws {
        let store = TestDefaults()
        let folder = store.fileURL.deletingLastPathComponent()
        let temporary = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path
        XCTAssertTrue(folder.resolvingSymlinksInPath().path.hasPrefix(temporary), "in the temporary directory")
        XCTAssertFalse(store.suiteName.contains("/Library/Preferences/"))

        store.defaults.set(7, forKey: "value")
        XCTAssertTrue(CFPreferencesAppSynchronize(store.suiteName as CFString))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL.path), "the store is the file at the suite's path")
        XCTAssertEqual(store.defaults.persistentDomain(forName: store.suiteName)?["value"] as? Int, 7)

        store.remove()
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path), "the folder is gone")
        store.remove()   // a second time does nothing
    }

    func testAStoreMadeForATestIsEmptyAndItsOwn() {
        let first = TestDefaults.makeStore(for: self)
        let second = TestDefaults.makeStore(for: self)
        XCTAssertNotEqual(first.suiteName, second.suiteName)
        first.defaults.set("a", forKey: "key")
        XCTAssertNil(second.defaults.persistentDomain(forName: second.suiteName)?["key"])
        XCTAssertNil(UserDefaults.standard.persistentDomain(forName: first.suiteName)?["other"])
    }
}

/// The one switch of the render tests. They draw panes, the Welcome Guide and the two
/// demos off screen and write PNG files for a look at them; they only run when asked to:
///
///     TEST_RUNNER_SCROLLIO_SHOTS_DIR=<folder> xcodebuild … test -only-testing:ScrollioTests/<Class>
///
/// xcodebuild hands a variable to the tests only when its name begins with `TEST_RUNNER_`,
/// and strips that prefix: inside the tests it is `SCROLLIO_SHOTS_DIR`. (There were four
/// different names, two of them documented without the prefix.)
enum RenderShots {

    /// The variable as the test process sees it.
    static let variable = "SCROLLIO_SHOTS_DIR"

    /// The folder the pictures go to (made if needed), or a skip that says how to ask.
    /// - Parameters:
    ///   - what: what would be rendered, for the skip's text ("the Mouse tab").
    ///   - subfolder: a folder of its own inside it, for tests whose file names are plain
    ///     words that another test might use too.
    static func directory(for what: String, subfolder: String? = nil) throws -> URL {
        guard let folder = ProcessInfo.processInfo.environment[variable], !folder.isEmpty else {
            throw XCTSkip("set TEST_RUNNER_\(variable) to a folder to render \(what)")
        }
        var directory = URL(fileURLWithPath: folder, isDirectory: true)
        if let subfolder {
            directory.appendPathComponent(subfolder, isDirectory: true)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
