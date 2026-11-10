import XCTest
@testable import Mos_Debug

/// The "Presets & Fast Scrolling" popover: slider clamping, value labels and how the
/// controls follow and write the global settings.
final class ScrollPresetPopoverTests: XCTestCase {

    private typealias Values = ScrollTuningControlValues
    private typealias ID = ScrollTuningSettingsPopover.Identifier

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

    // MARK: - Slider clamping and snapping

    func testSnapped_clampsToRange() {
        XCTAssertEqual(Values.snapped(-1, to: ScrollTuningSettings.freeSpinSmoothnessRange, step: Values.smoothnessStep), 0)
        XCTAssertEqual(Values.snapped(9, to: ScrollTuningSettings.freeSpinSmoothnessRange, step: Values.smoothnessStep), 5)
        XCTAssertEqual(Values.snapped(0.1, to: ScrollTuningSettings.freeSpinSpeedRange, step: Values.speedStep), 0.25)
        XCTAssertEqual(Values.snapped(4, to: ScrollTuningSettings.freeSpinSpeedRange, step: Values.speedStep), 3)
        XCTAssertEqual(Values.snapped(1.5, to: ScrollTuningSettings.accelerationRange, step: Values.accelerationStep), 1)
    }

    func testSnapped_nonFiniteFallsToLowerBound() {
        XCTAssertEqual(Values.snapped(.nan, to: ScrollTuningSettings.freeSpinSpeedRange, step: Values.speedStep), 0.25)
        XCTAssertEqual(Values.snapped(.infinity, to: ScrollTuningSettings.accelerationRange, step: Values.accelerationStep), 0)
    }

    func testSnapped_roundsToStepWithoutFloatNoise() {
        XCTAssertEqual(Values.snapped(1.23, to: ScrollTuningSettings.freeSpinSmoothnessRange, step: Values.smoothnessStep), 1.25)
        XCTAssertEqual(Values.snapped(0.78, to: ScrollTuningSettings.freeSpinSpeedRange, step: Values.speedStep), 0.8)
        XCTAssertEqual(Values.snapped(0.77, to: ScrollTuningSettings.freeSpinSpeedRange, step: Values.speedStep), 0.75)
        XCTAssertEqual(Values.snapped(0.31, to: ScrollTuningSettings.accelerationRange, step: Values.accelerationStep), 0.3)
        XCTAssertEqual(Values.snapped(0.02, to: ScrollTuningSettings.accelerationRange, step: Values.accelerationStep), 0)
    }

    /// Every preset value must be reachable with the sliders.
    func testSnapped_keepsPresetValues() {
        for preset in ScrollPreset.allCases {
            let tuning = preset.values.tuning
            XCTAssertEqual(Values.snapped(tuning.freeSpinSmoothness, to: ScrollTuningSettings.freeSpinSmoothnessRange, step: Values.smoothnessStep), tuning.freeSpinSmoothness, "\(preset)")
            XCTAssertEqual(Values.snapped(tuning.freeSpinSpeed, to: ScrollTuningSettings.freeSpinSpeedRange, step: Values.speedStep), tuning.freeSpinSpeed, "\(preset)")
            XCTAssertEqual(Values.snapped(tuning.acceleration, to: ScrollTuningSettings.accelerationRange, step: Values.accelerationStep), tuning.acceleration, "\(preset)")
        }
    }

    // MARK: - Value labels

    func testValueTexts() {
        XCTAssertEqual(Values.smoothnessText(1.5), "1.50")
        XCTAssertEqual(Values.speedText(0.8), "0.80×")
        XCTAssertEqual(Values.accelerationText(0), NSLocalizedString("scroll-tuning-acceleration-off", comment: ""))
        XCTAssertTrue(Values.accelerationText(0.3).contains("30"))
        XCTAssertTrue(Values.accelerationText(1).contains("100"))
    }

    // MARK: - Popover controls

    func testPopover_showsMatchingPresetOrCustom() {
        ScrollPreset.smooth.apply()
        var view = ScrollTuningSettingsPopover().makeContentViewController().view
        XCTAssertEqual(popUp(in: view).selectedTag(), ScrollPreset.allCases.firstIndex(of: .smooth))
        XCTAssertEqual(label(ID.presetDescription, in: view).stringValue, ScrollPreset.smooth.localizedDescription)

        Options.shared.scroll.speed = 3.3
        view = ScrollTuningSettingsPopover().makeContentViewController().view
        XCTAssertEqual(popUp(in: view).titleOfSelectedItem, ScrollPreset.customLocalizedName)
    }

    func testPopover_pickingPresetUpdatesSettingsAndEveryControl() {
        ScrollPreset.trackpadLike.apply()
        let popover = ScrollTuningSettingsPopover()
        var changes = 0
        popover.onSettingsChanged = { changes += 1 }
        let view = popover.makeContentViewController().view

        let picker = popUp(in: view)
        picker.selectItem(withTag: ScrollPreset.allCases.firstIndex(of: .direct)!)
        picker.sendAction(picker.action, to: picker.target)

        let direct = ScrollPreset.direct.values
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(Options.shared.scroll.duration, direct.duration)
        XCTAssertEqual(Options.shared.scroll.speed, direct.speed)
        XCTAssertEqual(Options.shared.scrollTuning, direct.tuning)
        XCTAssertEqual(slider(ID.smoothness, in: view).doubleValue, direct.tuning.freeSpinSmoothness, accuracy: 1e-9)
        XCTAssertEqual(slider(ID.speed, in: view).doubleValue, direct.tuning.freeSpinSpeed, accuracy: 1e-9)
        XCTAssertEqual(slider(ID.acceleration, in: view).doubleValue, direct.tuning.acceleration, accuracy: 1e-9)
        XCTAssertEqual(checkbox(in: view).state, .on)
        XCTAssertEqual(label(ID.presetDescription, in: view).stringValue, ScrollPreset.direct.localizedDescription)
    }

    func testPopover_choosingCustomChangesNothing() {
        Options.shared.scroll.speed = 3.3
        let popover = ScrollTuningSettingsPopover()
        var changes = 0
        popover.onSettingsChanged = { changes += 1 }
        let view = popover.makeContentViewController().view
        let tuningBefore = Options.shared.scrollTuning

        let picker = popUp(in: view)
        picker.selectItem(withTitle: ScrollPreset.customLocalizedName)
        picker.sendAction(picker.action, to: picker.target)

        XCTAssertEqual(changes, 0)
        XCTAssertEqual(Options.shared.scroll.speed, 3.3)
        XCTAssertEqual(Options.shared.scrollTuning, tuningBefore)
    }

    func testPopover_freeSpinCheckboxDisablesOnlyFreeSpinSliders() {
        ScrollPreset.balanced.apply()
        let popover = ScrollTuningSettingsPopover()
        var changes = 0
        popover.onSettingsChanged = { changes += 1 }
        let view = popover.makeContentViewController().view

        checkbox(in: view).performClick(nil)

        XCTAssertFalse(Options.shared.scrollTuning.freeSpinEnabled)
        XCTAssertEqual(changes, 1)
        XCTAssertFalse(slider(ID.smoothness, in: view).isEnabled)
        XCTAssertFalse(slider(ID.speed, in: view).isEnabled)
        XCTAssertTrue(slider(ID.acceleration, in: view).isEnabled)
        XCTAssertEqual(popUp(in: view).titleOfSelectedItem, ScrollPreset.customLocalizedName)
    }

    func testPopover_sliderSnapsClampsAndWrites() {
        ScrollPreset.balanced.apply()
        let popover = ScrollTuningSettingsPopover()
        var changes = 0
        popover.onSettingsChanged = { changes += 1 }
        let view = popover.makeContentViewController().view

        let speed = slider(ID.speed, in: view)
        speed.doubleValue = 0.83
        speed.sendAction(speed.action, to: speed.target)
        XCTAssertEqual(Options.shared.scrollTuning.freeSpinSpeed, 0.85)
        XCTAssertEqual(changes, 1)

        let acceleration = slider(ID.acceleration, in: view)
        acceleration.doubleValue = 0.42
        acceleration.sendAction(acceleration.action, to: acceleration.target)
        XCTAssertEqual(Options.shared.scrollTuning.acceleration, 0.4)
        XCTAssertEqual(changes, 2)

        // The same snapped value again is not a change.
        acceleration.doubleValue = 0.41
        acceleration.sendAction(acceleration.action, to: acceleration.target)
        XCTAssertEqual(changes, 2)
        XCTAssertEqual(popUp(in: view).titleOfSelectedItem, ScrollPreset.customLocalizedName)
    }

    // MARK: - Helpers

    private func popUp(in view: NSView) -> NSPopUpButton {
        find(ID.preset, in: view) as! NSPopUpButton
    }

    private func slider(_ id: NSUserInterfaceItemIdentifier, in view: NSView) -> NSSlider {
        find(id, in: view) as! NSSlider
    }

    private func checkbox(in view: NSView) -> NSButton {
        find(ID.freeSpin, in: view) as! NSButton
    }

    private func label(_ id: NSUserInterfaceItemIdentifier, in view: NSView) -> NSTextField {
        find(id, in: view) as! NSTextField
    }

    private func find(_ id: NSUserInterfaceItemIdentifier, in view: NSView) -> NSView? {
        if view.identifier == id { return view }
        for subview in view.subviews {
            if let match = find(id, in: subview) { return match }
        }
        return nil
    }
}
