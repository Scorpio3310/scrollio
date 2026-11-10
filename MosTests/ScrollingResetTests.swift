import XCTest
@testable import Mos_Debug

/// "Reset to defaults" in the Scrolling tab. In the global settings it also resets the
/// Presets & Fast Scrolling tuning (free-spin, acceleration); per-app settings have no
/// tuning of their own, so there it only resets the app's scroll options.
final class ScrollingResetTests: XCTestCase {

    private var originalScroll: OPTIONS_SCROLL_DEFAULT!
    private var originalTuning: ScrollTuningSettings!

    override func setUp() {
        super.setUp()
        originalScroll = Options.shared.scroll
        originalTuning = Options.shared.scrollTuning
        // A fresh container, so the tests never edit the one they restore.
        Options.shared.scroll = OPTIONS_SCROLL_DEFAULT()
        Options.shared.scrollTuning = .default
    }

    override func tearDown() {
        Options.shared.scroll = originalScroll
        Options.shared.scrollTuning = originalTuning
        originalScroll = nil
        originalTuning = nil
        super.tearDown()
    }

    private func makeController(target: Application? = nil) -> PreferencesScrollingViewController {
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesScrollingViewController.self))
        let controller = storyboard.instantiateController(withIdentifier: "scrolling") as! PreferencesScrollingViewController
        controller.currentTargetApplication = target
        _ = controller.view
        return controller
    }

    private var changedTuning: ScrollTuningSettings {
        var tuning = ScrollTuningSettings.default
        tuning.acceleration = 0.5
        tuning.freeSpinEnabled = false
        return tuning
    }

    // MARK: - Global settings

    func testNothingToResetWithDefaults() {
        let controller = makeController()
        XCTAssertFalse(controller.hasSettingsToReset)
        XCTAssertFalse(controller.resetToDefaultsButton.isEnabled)
    }

    func testResetButtonAppearsWhenOnlyTheTuningDiffers() {
        let controller = makeController()
        Options.shared.scrollTuning = changedTuning
        controller.syncViewWithOptions()

        XCTAssertTrue(controller.hasSettingsToReset)
        XCTAssertTrue(controller.resetToDefaultsButton.isEnabled)
    }

    func testGlobalResetRestoresScrollOptionsAndTuning() {
        let controller = makeController()
        Options.shared.scroll.speed = 4.2
        Options.shared.scrollTuning = changedTuning
        controller.syncViewWithOptions()
        XCTAssertTrue(controller.hasSettingsToReset)

        controller.resetToDefaultClick(controller.resetToDefaultsButton)

        XCTAssertEqual(Options.shared.scroll, OPTIONS_SCROLL_DEFAULT())
        XCTAssertEqual(Options.shared.scrollTuning, .default)
        XCTAssertFalse(controller.hasSettingsToReset)
        XCTAssertFalse(controller.resetToDefaultsButton.isEnabled)
    }

    // MARK: - Per-app settings

    func testPerAppSettingsIgnoreTheGlobalTuning() {
        let application = Application(path: "/Applications/ScrollingResetTest.app")
        application.inherit = false
        Options.shared.scrollTuning = changedTuning

        let controller = makeController(target: application)

        XCTAssertFalse(controller.hasSettingsToReset)
    }

    func testPerAppResetKeepsTheGlobalTuning() {
        let application = Application(path: "/Applications/ScrollingResetTest.app")
        application.inherit = false
        application.scroll.speed = 4.2
        Options.shared.scrollTuning = changedTuning
        let controller = makeController(target: application)
        XCTAssertTrue(controller.hasSettingsToReset)

        controller.resetToDefaultClick(controller.resetToDefaultsButton)

        XCTAssertEqual(application.scroll, OPTIONS_SCROLL_DEFAULT())
        XCTAssertEqual(Options.shared.scrollTuning, changedTuning)
        XCTAssertFalse(controller.hasSettingsToReset)
    }

    func testInheritingAppHasNothingToReset() {
        let application = Application(path: "/Applications/ScrollingResetTest.app")
        application.inherit = true
        Options.shared.scroll.speed = 4.2
        Options.shared.scrollTuning = changedTuning

        let controller = makeController(target: application)

        XCTAssertFalse(controller.hasSettingsToReset)
    }
}
