import XCTest
@testable import Scrollio_Debug

/// Regression tests for `Options.readOptions()`: the scroll `step` / `speed` /
/// `duration` defaults (33.6 / 6.50 / 3.69) must survive a missing UserDefaults
/// key — mirroring the existing `deadZone` nil-guard.
///
/// `UserDefaults.double(forKey:)` returns `0.0` (not `nil`) for a missing key,
/// which previously stomped those defaults. `speed == 0.0` is especially bad: every
/// event's distance is multiplied by the speed (`ScrollCore.posterInput`), so with a
/// zero speed nothing ever moves and scrolling in the affected app dies entirely.
///
/// The settings are read from a store of the test's own (`Options.defaults`), never from
/// the debug app's real preferences.
final class OptionsScrollDefaultsTests: XCTestCase {

    private var defaults: UserDefaults!
    // In-memory snapshot of every scroll field readOptions() writes, so the
    // shared singleton is left exactly as we found it.
    private var scrollSnapshot: ScrollSnapshot?
    // Everything else `readOptions()` replaces (bindings, apps, gestures, the mice).
    private var otherSettings: OptionsSnapshot?

    private let expectedStep = OPTIONS_SCROLL_DEFAULT().step         // 33.6
    private let expectedSpeed = OPTIONS_SCROLL_DEFAULT().speed       // 6.50
    private let expectedDuration = OPTIONS_SCROLL_DEFAULT().duration // 3.69

    // MARK: - Missing key falls back to the OPTIONS_SCROLL_DEFAULT() value

    func testReadOptions_restoresSpeedDefault_whenKeyMissing() {
        // Mark "options exist" so readOptions() skips its first-run re-seed and
        // exercises the read path directly — modelling a partial-write state
        // where optionsExist is set but a scroll key is absent.
        snapshotUserDefaultsAndSet(OptionItem.General.OptionsExist, to: "optionsExist")
        snapshotUserDefaultsAndRemove(OptionItem.Scroll.Speed)
        Options.shared.readOptions()
        XCTAssertEqual(Options.shared.scroll.speed, expectedSpeed, accuracy: 1e-9,
                       "speed must fall back to 6.50 when its key is missing, not 0.0")
    }

    func testReadOptions_restoresStepAndDurationDefaults_whenKeysMissing() {
        snapshotUserDefaultsAndSet(OptionItem.General.OptionsExist, to: "optionsExist")
        snapshotUserDefaultsAndRemove(OptionItem.Scroll.Step)
        snapshotUserDefaultsAndRemove(OptionItem.Scroll.Duration)
        Options.shared.readOptions()
        XCTAssertEqual(Options.shared.scroll.step, expectedStep, accuracy: 1e-9,
                       "step must fall back to 33.6 when its key is missing, not 0.0")
        XCTAssertEqual(Options.shared.scroll.duration, expectedDuration, accuracy: 1e-9,
                       "duration must fall back to 3.69 when its key is missing, not 0.0")
    }

    // MARK: - A genuinely stored value is honoured (regression guard)

    func testReadOptions_keepsStoredValue_whenKeyPresent() {
        snapshotUserDefaultsAndSet(OptionItem.General.OptionsExist, to: "optionsExist")
        snapshotUserDefaultsAndSet(OptionItem.Scroll.Speed, to: 5.0)
        Options.shared.readOptions()
        XCTAssertEqual(Options.shared.scroll.speed, 5.0, accuracy: 1e-9,
                       "a real stored speed must not be overwritten by the default")
    }

    // MARK: - Invariant: a missing speed key must never deaden scrolling

    func testReadOptions_doesNotDeadenScrolling_whenSpeedKeyMissing() {
        // The default speed is the contract that scrolling keeps working even
        // when the key is absent; it must never resolve to 0.
        XCTAssertNotEqual(OPTIONS_SCROLL_DEFAULT().speed, 0.0)
        snapshotUserDefaultsAndSet(OptionItem.General.OptionsExist, to: "optionsExist")
        snapshotUserDefaultsAndRemove(OptionItem.Scroll.Speed)
        Options.shared.readOptions()
        XCTAssertNotEqual(Options.shared.scroll.speed, 0.0,
                          "missing speed key must never resolve to 0.0 (deadens scrolling)")
    }

    // MARK: - A fresh installation: the wheel starts in the classic direction for this Mac

    /// Answers "Natural scrolling is on" with `on` and counts the questions.
    private func macOSNaturalScrolling(_ on: Bool) {
        naturalScrollingQuestions = 0
        Options.naturalScrollingIsOn = { [unowned self] in
            self.naturalScrollingQuestions += 1
            return on
        }
    }

    private var naturalScrollingQuestions = 0

    /// Natural scrolling on (macOS's default): macOS turns the wheel too, and "Reverse wheel
    /// direction" starts on, as before.
    func testAFreshInstallationWithNaturalScrollingReversesTheWheel() {
        macOSNaturalScrolling(true)
        Options.shared.readOptions()
        XCTAssertEqual(naturalScrollingQuestions, 1)
        XCTAssertTrue(Options.shared.scroll.reversesWheel)
        XCTAssertTrue(Options.shared.scroll.reverse)
        XCTAssertTrue(Options.shared.scroll.reverseVertical)
        XCTAssertTrue(Options.shared.scroll.reverseHorizontal)
        XCTAssertEqual(defaults.object(forKey: OptionItem.Scroll.Reverse) as? Bool, true, "stored at once")
        XCTAssertNotNil(defaults.object(forKey: OptionItem.General.OptionsExist))
    }

    /// Natural scrolling off: the wheel is classic already, so the switch starts off, the
    /// way the switch turns it off (the main flag; the axes keep theirs).
    func testAFreshInstallationWithoutNaturalScrollingLeavesTheWheelAlone() {
        macOSNaturalScrolling(false)
        Options.shared.readOptions()
        XCTAssertEqual(naturalScrollingQuestions, 1)
        XCTAssertFalse(Options.shared.scroll.reversesWheel)
        XCTAssertFalse(Options.shared.scroll.reverse)
        XCTAssertTrue(Options.shared.scroll.reverseVertical, "as the switch leaves it when turned off")
        XCTAssertTrue(Options.shared.scroll.reverseHorizontal)
        XCTAssertEqual(defaults.object(forKey: OptionItem.Scroll.Reverse) as? Bool, false, "stored at once")

        // The next launch reads what was stored, and asks macOS nothing more.
        Options.shared.scroll.reverse = true
        Options.shared.readOptions()
        XCTAssertEqual(naturalScrollingQuestions, 1)
        XCTAssertFalse(Options.shared.scroll.reversesWheel)

        // Turned on by hand it stays on, whatever macOS says.
        Options.shared.scroll.reversesWheel = true
        Options.shared.flushPendingSaves()
        Options.shared.readOptions()
        XCTAssertTrue(Options.shared.scroll.reversesWheel)
        XCTAssertEqual(naturalScrollingQuestions, 1)
    }

    /// Settings that exist keep their direction, also one that macOS's setting would
    /// change, and also when the direction's keys are missing (their default, on).
    func testAnInstallationWithSettingsKeepsItsWheelDirection() {
        for natural in [false, true] {
            for stored in [nil, false, true] as [Bool?] {
                let store = TestDefaults.make(for: self)
                store.set("optionsExist", forKey: OptionItem.General.OptionsExist)
                if let stored {
                    store.set(stored, forKey: OptionItem.Scroll.Reverse)
                    store.set(stored, forKey: OptionItem.Scroll.ReverseVertical)
                    store.set(stored, forKey: OptionItem.Scroll.ReverseHorizontal)
                }
                Options.shared.defaults = store
                macOSNaturalScrolling(natural)
                Options.shared.readOptions()
                XCTAssertEqual(naturalScrollingQuestions, 0, "macOS is not asked: natural \(natural), stored \(String(describing: stored))")
                XCTAssertEqual(Options.shared.scroll.reversesWheel, stored ?? true, "natural \(natural), stored \(String(describing: stored))")
                XCTAssertEqual(store.object(forKey: OptionItem.Scroll.Reverse) as? Bool, stored, "nothing written")
            }
        }
    }

    /// Fresh means no settings at all: no `optionsExist` and no stored wheel direction. A
    /// store that has a direction but lost `optionsExist` is not asked about macOS either.
    func testWhatCountsAsAFreshInstallation() {
        XCTAssertTrue(Options.isFreshInstallation(defaults))
        for key in [OptionItem.General.OptionsExist, OptionItem.Scroll.Reverse,
                    OptionItem.Scroll.ReverseVertical, OptionItem.Scroll.ReverseHorizontal] {
            let store = TestDefaults.make(for: self)
            store.set(key == OptionItem.General.OptionsExist ? "optionsExist" as Any : true as Any, forKey: key)
            XCTAssertFalse(Options.isFreshInstallation(store), key)
        }
        // Other settings without `optionsExist` do not decide it: a save always writes both.
        defaults.set(5.0, forKey: OptionItem.Scroll.Speed)
        XCTAssertTrue(Options.isFreshInstallation(defaults))

        // The stored direction is read as it is and not written over (regression: the read
        // first saved the settings in memory over it); only the mark is written.
        let lostTheMark = TestDefaults.make(for: self)
        lostTheMark.set(false, forKey: OptionItem.Scroll.ReverseVertical)
        lostTheMark.set(5.0, forKey: OptionItem.Scroll.Speed)
        Options.shared.scroll.reverseVertical = true
        Options.shared.defaults = lostTheMark
        macOSNaturalScrolling(false)
        Options.shared.readOptions()
        XCTAssertEqual(naturalScrollingQuestions, 0)
        XCTAssertFalse(Options.shared.scroll.reverseVertical)
        XCTAssertEqual(Options.shared.scroll.speed, 5.0)
        XCTAssertEqual(lostTheMark.object(forKey: OptionItem.Scroll.ReverseVertical) as? Bool, false)
        XCTAssertEqual(lostTheMark.object(forKey: OptionItem.Scroll.Speed) as? Double, 5.0)
        XCTAssertNotNil(lostTheMark.object(forKey: OptionItem.General.OptionsExist))
        XCTAssertNil(lostTheMark.object(forKey: OptionItem.Scroll.Reverse), "nothing else written")
    }

    /// Under XCTest the Mac's own setting is never read: the answer is macOS's default, also
    /// from a store that says Natural scrolling is off (read, it would answer off).
    func testTheTestsDoNotReadTheMacsSetting() {
        XCTAssertTrue(Self.liveNaturalScrollingIsOn())
        defaults.set(false, forKey: "com.apple.swipescrolldirection")
        XCTAssertTrue(Options.naturalScrollingIsOn(in: defaults))
    }

    // MARK: - Migration: the old Duration lock of "Trackpad-style events"

    // Builds with the lock forced Duration to 4.75 and stored the Duration from before in
    // `durationBeforeSimTrackpadLock` (per-app scroll options only; the global ones never
    // stored it). Loading gives that Duration back once and drops the key.

    func testLegacyLock_restoresTheRememberedDuration() throws {
        let app = try loadLegacyApplication(simTrackpad: true, duration: 4.75, remembered: 2.0)
        XCTAssertEqual(app.scroll.duration, 2.0)
        XCTAssertTrue(app.scroll.smoothSimTrackpad, "trackpad-style events stay on")
        XCTAssertEqual(app.scroll.step, 40, "the other values load as stored")
    }

    func testLegacyLock_keepsADurationThatIsNotTheLockedOne() throws {
        // With momentum on the lock did not apply, so Duration is the user's own.
        let app = try loadLegacyApplication(simTrackpad: true, duration: 3.13, remembered: 2.0)
        XCTAssertEqual(app.scroll.duration, 3.13)
    }

    func testLegacyLock_needsTrackpadStyleOn() throws {
        let app = try loadLegacyApplication(simTrackpad: false, duration: 4.75, remembered: 2.0)
        XCTAssertEqual(app.scroll.duration, 4.75)
    }

    func testLegacyLock_withoutARememberedDurationNothingChanges() throws {
        let app = try loadLegacyApplication(simTrackpad: true, duration: 4.75, remembered: nil)
        XCTAssertEqual(app.scroll.duration, 4.75)
        XCTAssertEqual(app.scroll.step, 40)
    }

    func testLegacyLock_theRememberedDurationIsNeverWrittenAgain() throws {
        for (simTrackpad, duration) in [(true, 4.75), (true, 3.13), (false, 4.75)] {
            let data = try legacyApplicationsData(simTrackpad: simTrackpad, duration: duration, remembered: 2.0)
            let applications = try EnhanceArray<Application>(withData: data, matchKey: "path")
            let loaded = try XCTUnwrap(applications.get(by: Self.legacyPath))
            let saved = try XCTUnwrap(applications.json())
            let text = try XCTUnwrap(String(data: saved, encoding: .utf8))
            XCTAssertFalse(text.contains("durationBeforeSimTrackpadLock"), "\(simTrackpad) \(duration)")
            // Loading the saved settings again changes nothing more.
            let reloaded = try EnhanceArray<Application>(withData: saved, matchKey: "path")
            XCTAssertEqual(try XCTUnwrap(reloaded.get(by: Self.legacyPath)).scroll, loaded.scroll, "\(simTrackpad) \(duration)")
        }
    }

    // MARK: - setUp / tearDown

    /// The seam as the app has it, kept before any test replaces it.
    private static let liveNaturalScrollingIsOn = Options.naturalScrollingIsOn

    override func setUp() {
        super.setUp()
        scrollSnapshot = ScrollSnapshot(of: Options.shared.scroll)
        otherSettings = OptionsSnapshot()
        defaults = TestDefaults.make(for: self)
        Options.shared.defaults = defaults
        _ = Self.liveNaturalScrollingIsOn
    }

    override func tearDown() {
        // The app's own store first, then the captured in-memory values back into the
        // shared singleton (written nowhere: under XCTest the real preferences never are).
        Options.naturalScrollingIsOn = Self.liveNaturalScrollingIsOn
        Options.shared.defaults = .standard
        defaults = nil
        scrollSnapshot?.restore(into: Options.shared.scroll)
        scrollSnapshot = nil
        otherSettings?.restore()
        otherSettings = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func snapshotUserDefaultsAndRemove(_ key: String) {
        defaults.removeObject(forKey: key)
    }

    private func snapshotUserDefaultsAndSet(_ key: String, to value: Any) {
        defaults.set(value, forKey: key)
    }

    private static let legacyPath = "/Applications/Legacy.app"

    /// The stored applications list with one app whose own scroll options were saved by a build
    /// with the Duration lock (`remembered` nil: the key is absent).
    private func legacyApplicationsData(simTrackpad: Bool, duration: Double, remembered: Double?) throws -> Data {
        let app = Application(path: Self.legacyPath)
        app.inherit = false
        app.scroll.smoothSimTrackpad = simTrackpad
        app.scroll.duration = duration
        app.scroll.step = 40
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(app)) as? [String: Any])
        var scroll = try XCTUnwrap(object["scroll"] as? [String: Any])
        XCTAssertNil(scroll["durationBeforeSimTrackpadLock"], "today's model does not write the key")
        if let remembered = remembered {
            scroll["durationBeforeSimTrackpadLock"] = remembered
        }
        object["scroll"] = scroll
        return try JSONSerialization.data(withJSONObject: [object])
    }

    /// Loads the list the way `Options.loadApplicationsData()` does.
    private func loadLegacyApplication(simTrackpad: Bool, duration: Double, remembered: Double?) throws -> Application {
        let data = try legacyApplicationsData(simTrackpad: simTrackpad, duration: duration, remembered: remembered)
        let applications = try EnhanceArray<Application>(withData: data, matchKey: "path")
        return try XCTUnwrap(applications.get(by: Self.legacyPath))
    }
}

/// Value snapshot of the mutable `OPTIONS_SCROLL_DEFAULT` fields that
/// `readOptions()` writes, for deterministic single-instance teardown.
private struct ScrollSnapshot {
    let smooth: Bool
    let reverse: Bool
    let reverseVertical: Bool
    let reverseHorizontal: Bool
    let dash: ScrollHotkey?
    let toggle: ScrollHotkey?
    let block: ScrollHotkey?
    let step: Double
    let speed: Double
    let duration: Double
    let deadZone: Double
    let smoothSimTrackpad: Bool
    let smoothVertical: Bool
    let smoothHorizontal: Bool

    init(of scroll: OPTIONS_SCROLL_DEFAULT) {
        self.smooth = scroll.smooth
        self.reverse = scroll.reverse
        self.reverseVertical = scroll.reverseVertical
        self.reverseHorizontal = scroll.reverseHorizontal
        self.dash = scroll.dash
        self.toggle = scroll.toggle
        self.block = scroll.block
        self.step = scroll.step
        self.speed = scroll.speed
        self.duration = scroll.duration
        self.deadZone = scroll.deadZone
        self.smoothSimTrackpad = scroll.smoothSimTrackpad
        self.smoothVertical = scroll.smoothVertical
        self.smoothHorizontal = scroll.smoothHorizontal
    }

    func restore(into scroll: OPTIONS_SCROLL_DEFAULT) {
        scroll.smooth = smooth
        scroll.reverse = reverse
        scroll.reverseVertical = reverseVertical
        scroll.reverseHorizontal = reverseHorizontal
        scroll.dash = dash
        scroll.toggle = toggle
        scroll.block = block
        scroll.step = step
        scroll.speed = speed
        scroll.duration = duration
        scroll.deadZone = deadZone
        scroll.smoothSimTrackpad = smoothSimTrackpad
        scroll.smoothVertical = smoothVertical
        scroll.smoothHorizontal = smoothHorizontal
    }
}
