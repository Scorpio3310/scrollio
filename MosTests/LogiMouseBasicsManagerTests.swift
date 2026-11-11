import XCTest
@testable import Mos_Debug

/// The manager and facade side of the basic mouse settings: what is stored for mice that
/// connect later, the shared notification, ids, and the Options -> LogiCenter push.
final class LogiMouseBasicsManagerTests: XCTestCase {

    func testApplyStoresTheSettingsForMiceThatConnectLater() {
        let manager = LogiSessionManager()
        XCTAssertEqual(manager.mouseSettings, .default)
        XCTAssertFalse(manager.mouseManaged)
        manager.applyMouseSettings(LogiMouseSettings(pointerDPI: 1600, hapticsOn: false), managed: true)
        XCTAssertEqual(manager.mouseSettings, LogiMouseSettings(pointerDPI: 1600, hapticsOn: false))
        XCTAssertTrue(manager.mouseManaged)
    }

    func testNoMiceMeansNoStates() {
        let manager = LogiSessionManager()
        XCTAssertEqual(manager.mouseDeviceStates(), [])
    }

    func testRefreshWithoutMicePostsOnce() {
        let manager = LogiSessionManager()
        let posted = expectation(forNotification: LogiCenter.mouseStateChanged, object: nil)
        manager.refreshMouseStates()
        wait(for: [posted], timeout: 2)
    }

    func testChangesInOneTurnArePostedOnce() {
        let manager = LogiSessionManager()
        XCTAssertFalse(manager.mouseStateNotificationScheduled)
        manager.notifyMouseStateChanged()
        XCTAssertTrue(manager.mouseStateNotificationScheduled, "one post is on its way")
        manager.notifyMouseStateChanged()
        let drained = expectation(description: "main queue turn")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 2)
        XCTAssertFalse(manager.mouseStateNotificationScheduled, "posted, ready for the next change")
    }

    func testAWheelChangeIsAMouseChangeToo() {
        let manager = LogiSessionManager()
        manager.notifyWheelStateChanged()
        XCTAssertTrue(manager.mouseStateNotificationScheduled, "the mouse states carry the wheel state")
        XCTAssertTrue(manager.wheelStateNotificationScheduled)
    }

    func testASampleWithoutMiceDoesNothing() {
        let manager = LogiSessionManager()
        manager.playHapticSample()
        XCTAssertTrue(manager.hapticSamplePending)
        manager.applyMouseSettings(.default, managed: false)
        XCTAssertFalse(manager.hapticSamplePending, "played behind the settings push")
    }

    func testDuplicateMiceGetDistinctIdsAndTheirWheelFollows() {
        let wheel = LogiWheelDeviceState(id: "046D:B042", deviceName: "MX Master 4", supportsSmartShift: true,
                                         supportsScrollForce: true, mode: .init(onMouse: .smartShift, setByYou: nil),
                                         smartShiftSensitivity: .init(onMouse: 50, setByYou: nil),
                                         scrollForce: .init(onMouse: 50, setByYou: 70))
        let state = LogiMouseDeviceState(id: "046D:B042", deviceName: "MX Master 4", supported: [.battery], managed: false,
                                         battery: nil, pointerSpeed: nil, haptics: nil, pressForce: nil, wheel: wheel)
        let states = LogiSessionManager.disambiguatedMouseStates([state, state])
        XCTAssertEqual(states.map(\.id), ["046D:B042", "046D:B042#2"])
        XCTAssertEqual(states.map { $0.wheel?.id }, ["046D:B042", "046D:B042#2"])
        XCTAssertEqual(states[1].wheel?.scrollForce, wheel.scrollForce, "the wheel keeps its values")
    }

    func testGestureCuesMaySwitchHapticsOnUntilTheUserSwitchedThemOff() {
        let manager = LogiSessionManager()
        XCTAssertTrue(manager.gestureCuesMayEnableHaptics, "never touched: today's behaviour")
        manager.applyMouseSettings(LogiMouseSettings(hapticStrength: 40), managed: true)
        XCTAssertTrue(manager.gestureCuesMayEnableHaptics)
        manager.applyMouseSettings(LogiMouseSettings(hapticsOn: false), managed: true)
        XCTAssertFalse(manager.gestureCuesMayEnableHaptics)
        manager.applyMouseSettings(LogiMouseSettings(hapticsOn: false), managed: false)
        XCTAssertFalse(manager.gestureCuesMayEnableHaptics, "the user said off, whatever the switch")
        manager.applyMouseSettings(LogiMouseSettings(hapticsOn: true), managed: true)
        XCTAssertTrue(manager.gestureCuesMayEnableHaptics)
    }

    // MARK: - Send Again

    func testSendAgainWithoutMicePostsOnce() {
        let manager = LogiSessionManager()
        manager.applyMouseSettings(LogiMouseSettings(pointerDPI: 1600), managed: true)
        manager.applyWheelSettings(LogiWheelSettings(managedByMos: true, scrollForce: 70))
        let posted = expectation(forNotification: LogiCenter.mouseStateChanged, object: nil)
        manager.sendMouseSettingsAgain()
        wait(for: [posted], timeout: 2)
        XCTAssertEqual(manager.mouseSettings, LogiMouseSettings(pointerDPI: 1600), "nothing stored changes")
    }

    func testSendAgainGoesThroughLogiCenter_unmanagedItOnlyReads() {
        let manager = LogiSessionManager()
        let center = LogiCenter(manager: manager, registry: UsageRegistry(sessionProvider: { [] }))
        let posted = expectation(forNotification: LogiCenter.mouseStateChanged, object: nil) { _ in
            Thread.isMainThread
        }
        center.sendMouseSettingsAgain()
        wait(for: [posted], timeout: 2)
        XCTAssertFalse(manager.mouseManaged)
        XCTAssertFalse(manager.wheelSettings.managedByMos)
    }

    func testLogiCenterExposesTheSurface() {
        XCTAssertEqual(LogiCenter.mouseStateChanged.rawValue, "LogiMouseStateChanged")
        XCTAssertNotNil(LogiCenter.shared.mouseDeviceStates())
    }

    // MARK: - Options -> LogiCenter

    func testBootstrapPushesTheSettingsAndTheSharedSwitch() {
        let options = Options.shared
        let manager = LogiSessionManager.shared
        let saved = (options.logiMouse, options.logiWheel, manager.mouseSettings, manager.mouseManaged)
        defer {
            options.logiMouse = saved.0
            options.logiWheel = saved.1
            manager.mouseSettings = saved.2
            manager.mouseManaged = saved.3
        }
        options.logiMouse = LogiMouseSettings(pointerDPI: 1200, hapticStrength: 40)
        options.logiWheel.managedByMos = true
        LogiUsageBootstrap.pushMouseSettings()
        XCTAssertEqual(manager.mouseSettings, LogiMouseSettings(pointerDPI: 1200, hapticStrength: 40))
        XCTAssertTrue(manager.mouseManaged)

        options.logiWheel.managedByMos = false
        LogiUsageBootstrap.pushMouseSettings()
        XCTAssertFalse(manager.mouseManaged)
    }
}
