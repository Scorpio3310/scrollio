import XCTest
@testable import Mos_Debug

/// Scroll presets: the tuning table, `apply` and "which preset is this" detection.
final class ScrollPresetTests: XCTestCase {

    private var globalSnapshot: ScrollPresetGlobalSnapshot?

    override func setUp() {
        super.setUp()
        globalSnapshot = ScrollPresetGlobalSnapshot()
    }

    override func tearDown() {
        globalSnapshot?.restore()
        globalSnapshot = nil
        super.tearDown()
    }

    // MARK: - Table

    /// Current tuning (to be retuned at engine integration; update together with `ScrollPreset.values`).
    func testPresetTable_currentValues() {
        assertValues(.direct, step: 33.6, speed: 2.0, duration: 1.0, smoothness: 0.5, freeSpinSpeed: 0.8, acceleration: 0)
        assertValues(.balanced, step: 33.6, speed: 2.7, duration: 2.0, smoothness: 1.0, freeSpinSpeed: 0.8, acceleration: 0)
        assertValues(.smooth, step: 33.6, speed: 2.7, duration: 3.13, smoothness: 1.5, freeSpinSpeed: 0.7, acceleration: 0)
        assertValues(.trackpadLike, step: 33.6, speed: 2.7, duration: 4.35, smoothness: 2.5, freeSpinSpeed: 1.0, acceleration: 0.3)
        for preset in ScrollPreset.allCases {
            // Only Magic Mouse turns on "Simulate trackpad" (see ScrollMomentumPresetTests).
            XCTAssertEqual(preset.values.simulateTrackpad, preset == .magicMouse, "\(preset)")
            XCTAssertTrue(preset.values.tuning.freeSpinEnabled, "\(preset)")
        }
    }

    func testPresetTable_valuesStayInsideControlRanges() {
        for preset in ScrollPreset.allCases {
            let values = preset.values
            XCTAssertGreaterThan(values.step, 0, "\(preset)")
            XCTAssertGreaterThan(values.speed, 0, "\(preset)")
            XCTAssertTrue((0...5).contains(values.duration), "\(preset)")
            XCTAssertTrue(ScrollTuningSettings.freeSpinSmoothnessRange.contains(values.tuning.freeSpinSmoothness), "\(preset)")
            XCTAssertTrue(ScrollTuningSettings.freeSpinSpeedRange.contains(values.tuning.freeSpinSpeed), "\(preset)")
            XCTAssertTrue(ScrollTuningSettings.accelerationRange.contains(values.tuning.acceleration), "\(preset)")
        }
    }

    func testPresetTable_eachPresetMatchesOnlyItself() {
        for preset in ScrollPreset.allCases {
            let (scroll, tuning) = applied(preset)
            XCTAssertEqual(ScrollPreset.matching(scroll: scroll, tuning: tuning), preset)
            for other in ScrollPreset.allCases where other != preset {
                XCTAssertFalse(other.matches(scroll: scroll, tuning: tuning), "\(other) must not match \(preset)")
            }
        }
    }

    func testPresetNames_areDistinct() {
        let names = ScrollPreset.allCases.map { $0.localizedName } + [ScrollPreset.customLocalizedName]
        XCTAssertEqual(Set(names).count, names.count)
        let descriptions = ScrollPreset.allCases.map { $0.localizedDescription }
        XCTAssertEqual(Set(descriptions).count, descriptions.count)
    }

    // MARK: - Apply

    func testApply_writesScrollValuesAndTuning() {
        for preset in ScrollPreset.allCases {
            let scroll = OPTIONS_SCROLL_DEFAULT()
            scroll.smooth = false
            scroll.smoothSimTrackpad = true
            scroll.durationBeforeSimTrackpadLock = 1.2
            scroll.step = 99
            scroll.speed = 9
            scroll.duration = ScrollDurationLimits.simulateTrackpadDefault
            var tuning = ScrollTuningSettings(freeSpinEnabled: false, freeSpinSmoothness: 4, freeSpinSpeed: 3, acceleration: 1)

            preset.apply(to: scroll, tuning: &tuning)

            let values = preset.values
            XCTAssertTrue(scroll.smooth, "\(preset)")
            XCTAssertEqual(scroll.smoothSimTrackpad, values.simulateTrackpad, "\(preset)")
            XCTAssertNil(scroll.durationBeforeSimTrackpadLock, "\(preset)")
            XCTAssertEqual(scroll.step, values.step, "\(preset)")
            XCTAssertEqual(scroll.speed, values.speed, "\(preset)")
            XCTAssertEqual(scroll.duration, values.duration, "\(preset)")
            XCTAssertEqual(tuning, values.tuning, "\(preset)")
        }
    }

    func testApply_leavesUnrelatedScrollOptionsAlone() {
        let scroll = OPTIONS_SCROLL_DEFAULT()
        scroll.reverse = false
        scroll.reverseHorizontal = false
        scroll.smoothVertical = false
        scroll.deadZone = 3
        scroll.dash = nil
        var tuning = ScrollTuningSettings.default

        ScrollPreset.direct.apply(to: scroll, tuning: &tuning)

        XCTAssertFalse(scroll.reverse)
        XCTAssertFalse(scroll.reverseHorizontal)
        XCTAssertFalse(scroll.smoothVertical)
        XCTAssertEqual(scroll.deadZone, 3)
        XCTAssertNil(scroll.dash)
        XCTAssertNotNil(scroll.toggle)
    }

    func testApplyGlobal_writesOptionsShared() {
        Options.shared.scroll.smooth = false
        Options.shared.scrollTuning = .default

        ScrollPreset.smooth.apply()

        XCTAssertTrue(Options.shared.scroll.smooth)
        XCTAssertEqual(Options.shared.scroll.step, 33.6)
        XCTAssertEqual(Options.shared.scroll.speed, 2.7)
        XCTAssertEqual(Options.shared.scroll.duration, 3.13)
        XCTAssertEqual(Options.shared.scrollTuning, ScrollPreset.smooth.values.tuning)
        XCTAssertEqual(ScrollPreset.current, .smooth)
    }

    // MARK: - Matching

    func testMatching_toleratesDisplayRounding() {
        var (scroll, tuning) = applied(.balanced)
        scroll.speed += 0.004
        scroll.duration -= 0.004
        tuning.freeSpinSpeed += 0.004
        XCTAssertEqual(ScrollPreset.matching(scroll: scroll, tuning: tuning), .balanced)

        scroll.speed += 0.01
        XCTAssertNil(ScrollPreset.matching(scroll: scroll, tuning: tuning), "a visible change makes it Custom")
    }

    func testMatching_customWhenSmoothScrollingIsOff() {
        let (scroll, tuning) = applied(.direct)
        scroll.smooth = false
        XCTAssertNil(ScrollPreset.matching(scroll: scroll, tuning: tuning))
    }

    func testMatching_customWhenSimulateTrackpadIsOn() {
        let (scroll, tuning) = applied(.trackpadLike)
        scroll.smoothSimTrackpad = true
        XCTAssertNil(ScrollPreset.matching(scroll: scroll, tuning: tuning))
    }

    func testMatching_customWhenAnyTuningValueDiffers() {
        let (scroll, base) = applied(.trackpadLike)

        var tuning = base
        tuning.freeSpinEnabled = false
        XCTAssertNil(ScrollPreset.matching(scroll: scroll, tuning: tuning), "free-spin off")

        tuning = base
        tuning.freeSpinSmoothness += 0.25
        XCTAssertNil(ScrollPreset.matching(scroll: scroll, tuning: tuning), "smoothness")

        tuning = base
        tuning.freeSpinSpeed -= 0.1
        XCTAssertNil(ScrollPreset.matching(scroll: scroll, tuning: tuning), "free-spin speed")

        tuning = base
        tuning.acceleration = 0
        XCTAssertNil(ScrollPreset.matching(scroll: scroll, tuning: tuning), "acceleration")
    }

    func testMatching_customWhenStepDiffers() {
        let (scroll, tuning) = applied(.smooth)
        scroll.step = 50
        XCTAssertNil(ScrollPreset.matching(scroll: scroll, tuning: tuning))
    }

    // MARK: - Helpers

    private func applied(_ preset: ScrollPreset) -> (OPTIONS_SCROLL_DEFAULT, ScrollTuningSettings) {
        let scroll = OPTIONS_SCROLL_DEFAULT()
        var tuning = ScrollTuningSettings.default
        preset.apply(to: scroll, tuning: &tuning)
        return (scroll, tuning)
    }

    private func assertValues(
        _ preset: ScrollPreset,
        step: Double, speed: Double, duration: Double,
        smoothness: Double, freeSpinSpeed: Double, acceleration: Double,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let values = preset.values
        XCTAssertEqual(values.step, step, accuracy: 1e-9, "\(preset) step", file: file, line: line)
        XCTAssertEqual(values.speed, speed, accuracy: 1e-9, "\(preset) speed", file: file, line: line)
        XCTAssertEqual(values.duration, duration, accuracy: 1e-9, "\(preset) duration", file: file, line: line)
        XCTAssertEqual(values.tuning.freeSpinSmoothness, smoothness, accuracy: 1e-9, "\(preset) smoothness", file: file, line: line)
        XCTAssertEqual(values.tuning.freeSpinSpeed, freeSpinSpeed, accuracy: 1e-9, "\(preset) free-spin speed", file: file, line: line)
        XCTAssertEqual(values.tuning.acceleration, acceleration, accuracy: 1e-9, "\(preset) acceleration", file: file, line: line)
    }
}

/// Saves the global scroll fields that presets write, and puts them back.
struct ScrollPresetGlobalSnapshot {
    private let smooth: Bool
    private let step: Double
    private let speed: Double
    private let duration: Double
    private let smoothSimTrackpad: Bool
    private let durationBeforeSimTrackpadLock: Double?
    private let tuning: ScrollTuningSettings

    init() {
        let scroll = Options.shared.scroll
        smooth = scroll.smooth
        step = scroll.step
        speed = scroll.speed
        duration = scroll.duration
        smoothSimTrackpad = scroll.smoothSimTrackpad
        durationBeforeSimTrackpadLock = scroll.durationBeforeSimTrackpadLock
        tuning = Options.shared.scrollTuning
    }

    func restore() {
        let scroll = Options.shared.scroll
        scroll.smooth = smooth
        scroll.step = step
        scroll.speed = speed
        scroll.duration = duration
        scroll.smoothSimTrackpad = smoothSimTrackpad
        scroll.durationBeforeSimTrackpadLock = durationBeforeSimTrackpadLock
        Options.shared.scrollTuning = tuning
    }
}
