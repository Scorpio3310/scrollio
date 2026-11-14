import XCTest
@testable import Scrollio_Debug

final class LogiUsageBootstrapTests: XCTestCase {

    /// Smoke: refreshAll runs without crashing and reads Options without trapping.
    /// Cannot deterministically assert registry content because Options.shared has live state.
    func testRefreshAll_runsWithoutCrash() {
        LogiUsageBootstrap.refreshAll()
        XCTAssertNotNil(LogiCenter.shared)
    }

    /// app 从列表移除后, refreshAll 应推送空集清理其 appScroll 用量 (防注册表残留)
    func testRefreshAllClearsUsageForRemovedApp() {
        let key = "/tmp/ScrollioUsageBootstrapTest.app"
        let code: UInt16 = 1006  // Logi Back 的 ScrollioCode (与 LogiCenterDeviceIntegrationTests 一致)
        let app = Application(path: key)
        app.inherit = false
        app.scroll.dash = ScrollHotkey(type: .mouse, code: code)
        Options.shared.application.applications.append(app)
        defer {
            if Options.shared.application.applications.get(by: key) != nil {
                Options.shared.application.applications.remove(from: key)
            }
            LogiUsageBootstrap.refreshAll()
        }

        LogiUsageBootstrap.refreshAll()
        XCTAssertTrue(LogiCenter.shared.usages(of: code).contains(.appScroll(key: key, role: .dash)),
                      "注册后应能查询到 appScroll 用量")

        Options.shared.application.applications.remove(from: key)
        LogiUsageBootstrap.refreshAll()
        XCTAssertFalse(LogiCenter.shared.usages(of: code).contains(.appScroll(key: key, role: .dash)),
                       "app 移除后用量应被清理")
    }

    /// Turning "Let the mouse track the gesture" on (off and on again), in Gestures or for an
    /// app's own gestures, asks the mice once more for a button they refused to track;
    /// another change of the settings, turning it off, or a switch of apps does not.
    func testTurningATrackingSwitchOnAsksTheMiceAgain() {
        let savedGesture = Options.shared.gesture
        let savedApplications = Options.shared.application.applications
        LogiUsageBootstrap.log = { _ in }
        defer {
            Options.shared.gesture = savedGesture
            Options.shared.application.applications = savedApplications
            LogiUsageBootstrap.refreshGestureTracking(front: nil, afterASettingsChange: true)
            LogiUsageBootstrap.log = { AppSystemLog.note($0) }
        }
        let figma = Application(path: "/Applications/Figma.app")
        Options.shared.application.applications = EnhanceArray<Application>(withArray: [figma], matchKey: "path")
        Options.shared.gesture.deviceTracking = true
        LogiUsageBootstrap.refreshGestureTracking(front: nil, afterASettingsChange: true)
        let before = LogiGestureController.retryGeneration

        LogiUsageBootstrap.refreshGestureTracking(front: nil, afterASettingsChange: true)
        Options.shared.gesture.deviceTracking = false
        LogiUsageBootstrap.refreshGestureTracking(front: nil, afterASettingsChange: true)
        LogiUsageBootstrap.frontApplicationChanged(to: nil)
        XCTAssertEqual(LogiGestureController.retryGeneration, before, "nothing turned on")

        Options.shared.gesture.deviceTracking = true
        LogiUsageBootstrap.refreshGestureTracking(front: nil, afterASettingsChange: true)
        XCTAssertEqual(LogiGestureController.retryGeneration, before + 1, "the Gestures pane's switch")

        figma.setUsesGeneralGestures(false, general: Options.shared.gesture)
        figma.changeOwnGestures { $0.deviceTracking = false }
        LogiUsageBootstrap.refreshGestureTracking(front: nil, afterASettingsChange: true)
        XCTAssertEqual(LogiGestureController.retryGeneration, before + 1)
        figma.changeOwnGestures { $0.deviceTracking = true }
        LogiUsageBootstrap.refreshGestureTracking(front: nil, afterASettingsChange: true)
        XCTAssertEqual(LogiGestureController.retryGeneration, before + 2, "an app's own switch")
    }
}
