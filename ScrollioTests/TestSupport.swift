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

/// The rule of the tests (AGENTS.md, "Verification"): under XCTest every real effect is
/// inert unless a test asks for it. Running the tests never presses a key, moves or clicks
/// the pointer, installs an event tap, shows a toast, opens an app or writes the app's
/// preferences on the Mac they run on, whatever a single test forgets to replace.
///
/// These tests keep it so. The first reads the app's sources: a call that reaches out of
/// the process may only stand in a file that is known here, behind a seam that does
/// nothing under XCTest. The others look at the test host as it is at this moment.
/// (A count of real posts at the end of the run, as first proposed, would need "the last
/// test", which a shuffled run does not have.)
final class TestIsolationTests: XCTestCase {

    /// A call that reaches out of the process, and where it may stand: a file, or a folder
    /// (ends in "/") for the scroll engine, whose files come and go.
    private struct Effect {
        let name: String
        let pattern: String
        let allowed: [String]
    }

    private static let effects: [Effect] = [
        // Posting events. ShortcutExecutor.post and SystemVolumeKeys.post do nothing under
        // XCTest; the dock swipe's driver is inert and its post refuses under XCTest.
        Effect(name: "posts an event", pattern: #"\.post\(tap:"#, allowed: [
            "Scrollio/Shortcut/ShortcutExecutor.swift",
            "Scrollio/Shortcut/SystemVolumeKeys.swift",
            "Scrollio/InputEvent/DockSwipeSynthesizer.swift",
        ]),
        // The scroll frames. A test gives the scroll tap an observer
        // (ScrollCore.posterInputObserverForTests) or a poster of its own.
        Effect(name: "posts a scroll event to an app", pattern: #"\.postToPid\("#, allowed: ["Scrollio/ScrollCore/"]),
        Effect(name: "makes a display link", pattern: #"CVDisplayLinkCreateWithActiveCGDisplays\("#, allowed: ["Scrollio/ScrollCore/"]),
        // Event taps: only Interceptor makes one, and under XCTest nothing makes an
        // Interceptor (the cores do not start; the pointer-movement tap, the keys tap, the
        // buttons tap and the recorder's tap have seams).
        Effect(name: "makes an event tap", pattern: #"CGEvent\.tapCreate\(|CGEventTapCreate\("#, allowed: ["Scrollio/Utils/Interceptor.swift"]),
        // The pointer: MouseGesturePointerDriver.inert under XCTest.
        Effect(name: "moves or detaches the pointer", pattern: #"CGWarpMouseCursorPosition\(|CGAssociateMouseAndMouseCursorPosition\("#, allowed: [
            "Scrollio/InputEvent/MouseGesturePointerLock.swift",
        ]),
        // HID: LogiCenter.start() does not run under XCTest.
        Effect(name: "opens or writes a HID device", pattern: #"IOHIDManagerOpen\(|IOHIDDeviceOpen\(|IOHIDDeviceSetReport\("#, allowed: [
            "Scrollio/Logi/Core/LogiSessionManager.swift",
            "Scrollio/Logi/Core/LogiDeviceSession.swift",
        ]),
        // Apps, files, scripts: ShortcutExecutor.opensTargets is off under XCTest; the
        // guide and the General pane open their links through closures the tests replace.
        Effect(name: "opens an app, a file or a link", pattern: #"NSWorkspace\.shared\.open\(|\.openApplication\(at:"#, allowed: [
            "Scrollio/Shortcut/ShortcutExecutor.swift",
            "Scrollio/Windows/IntroductionWindow/IntroductionViewController.swift",
            "Scrollio/Windows/PreferencesWindow/GeneralView/PreferencesGeneralViewController.swift",
        ]),
        Effect(name: "starts a process", pattern: #"posix_spawn\(|Process\(\)"#, allowed: ["Scrollio/Shortcut/ShortcutExecutor.swift"]),
        // The login item: InertLoginItemService under XCTest.
        Effect(name: "registers a login item", pattern: #"SMAppService\.mainApp\.(register|unregister)\("#, allowed: ["Scrollio/Utils/LoginItem.swift"]),
        // The permission prompt: the guide asks through a closure the tests replace.
        Effect(name: "asks for the Accessibility permission", pattern: #"AXIsProcessTrustedWithOptions\("#, allowed: ["Scrollio/Utils/Utils.swift"]),
        // The app's folder in Application Support (the settings from before an import):
        // SettingsBackups.live has no folder under XCTest, so nothing is written there.
        Effect(name: "uses the app's folder in Application Support", pattern: #"\.applicationSupportDirectory"#, allowed: [
            "Scrollio/Options/SettingsFileCenter.swift",
        ]),
    ]

    func testACallThatReachesOutOfTheProcessStandsOnlyInAKnownFile() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let sources = root.appendingPathComponent("Scrollio", isDirectory: true)
        // Paths relative to the app's folder (the folder itself may be reached by a link).
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(atPath: sources.path))
        var files = 0
        for case let relative as String in enumerator where relative.hasSuffix(".swift") {
            files += 1
            let url = sources.appendingPathComponent(relative)
            let path = "Scrollio/" + relative
            // Comments may name an API; only code counts.
            let code = try String(contentsOf: url, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.drop(while: { $0 == " " || $0 == "\t" }).hasPrefix("//") }
                .joined(separator: "\n")
            for effect in Self.effects where code.range(of: effect.pattern, options: .regularExpression) != nil {
                let known = effect.allowed.contains { $0.hasSuffix("/") ? path.hasPrefix($0) : path == $0 }
                XCTAssertTrue(
                    known,
                    "\(path) \(effect.name). Under XCTest every real effect is inert unless a test asks for it "
                        + "(AGENTS.md, Verification): put the call behind a seam whose default does nothing while "
                        + "AppRuntime.isRunningXCTest, then add the file to TestIsolationTests.effects."
                )
            }
        }
        XCTAssertGreaterThan(files, 100, "the app's sources were found")
    }

    /// The test host as the tests find it: nothing of the app was started, and what would
    /// reach out of the process is switched off or replaced by something inert.
    func testNothingOfTheAppRunsAndItsRealEffectsAreOff() {
        XCTAssertTrue(AppRuntime.isRunningXCTest)
        XCTAssertFalse(AppRuntime.shouldRunAppStartupSideEffects)
        XCTAssertFalse(AppRunController.shared.coresActive)
        XCTAssertFalse(ButtonCore.shared.isActive)
        XCTAssertFalse(ScrollCore.shared.isActive)
        XCTAssertNil(ButtonCore.shared.dispatchInterceptor)
        XCTAssertFalse(ButtonCore.shared.keyTap.hasTap)
        XCTAssertTrue(LoginItem.defaultService is InertLoginItemService)
        XCTAssertFalse(ShortcutExecutor.shared.opensTargets)
        XCTAssertFalse(LogiTerminationSignal.shared.isInstalled)
    }

    /// No event tap of this process is installed. Tests run one after another, so at any
    /// moment between two tests this must hold: a tap that an earlier test left behind
    /// would sit in the path of the Mac's input for the rest of the run. (Without
    /// Accessibility access for the debug app no tap can be made at all, and this passes
    /// trivially; with it, this is the check.)
    func testNoEventTapOfThisProcessIsInstalled() throws {
        var count: UInt32 = 0
        guard CGGetEventTapList(0, nil, &count) == .success else {
            throw XCTSkip("the list of event taps cannot be read here")
        }
        var taps = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(count) + 16)
        var actual: UInt32 = 0
        guard CGGetEventTapList(UInt32(taps.count), &taps, &actual) == .success else {
            throw XCTSkip("the list of event taps cannot be read here")
        }
        let own = taps.prefix(Int(actual)).filter { $0.tappingProcess == getpid() }
        XCTAssertEqual(own.count, 0, "an earlier test left \(own.count) event tap(s) of this process installed")
    }

    /// A toast shown by a manager nobody prepared puts no window on screen.
    func testAToastPutsNoWindowOnScreen() throws {
        let manager = ToastManager()
        manager.announce = { _, _ in }
        addTeardownBlock { manager.testingRemoveAll() }
        manager.present(message: "A toast in a test", style: .info, duration: 3, icon: nil, showsIcon: true)
        let toast = try XCTUnwrap(manager.testingToasts.first)
        XCTAssertFalse(toast.panel.isVisible)
    }

    /// "Open App or File…" pressed in a test opens nothing. The target here is a file that
    /// is not there, so even with the switch on nothing would open: the executor would only
    /// say so with a toast, and that toast is what must not come.
    func testOpenAppOrFileDoesNothingUnlessATestAsks() throws {
        XCTAssertFalse(ShortcutExecutor.shared.opensTargets)
        let name = "ScrollioTests-\(UUID().uuidString).txt"
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let payload = OpenTargetPayload(path: missing.path, bundleID: nil, arguments: "", kind: .file)
        addTeardownBlock { ToastManager.shared.testingRemoveAll() }

        _ = ShortcutExecutor.shared.execute(action: .openTarget(payload: payload), phase: .down)
        // The opening would run on a queue of its own and come back to the main queue.
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        XCTAssertFalse(ToastManager.shared.testingToasts.contains { $0.message.contains(name) }, "the executor went on to open the file")
    }
}
