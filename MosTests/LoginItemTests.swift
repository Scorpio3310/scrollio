import XCTest
@testable import Mos_Debug

/// "Launch at login" through SMAppService, against a fake service: the real one is never
/// touched from a test, so no login item is ever registered or removed here.
final class LoginItemTests: XCTestCase {

    private final class FakeService: LoginItemService {
        var status: LoginItemStatus
        /// Status after a successful register(); nil = register() throws.
        var statusAfterRegister: LoginItemStatus? = .enabled
        var unregisterFails = false
        private(set) var registerCalls = 0
        private(set) var unregisterCalls = 0
        private(set) var openSettingsCalls = 0

        init(status: LoginItemStatus) {
            self.status = status
        }

        func register() throws {
            registerCalls += 1
            guard let next = statusAfterRegister else {
                throw NSError(domain: "LoginItemTests", code: 1)
            }
            status = next
        }

        func unregister() throws {
            unregisterCalls += 1
            if unregisterFails {
                throw NSError(domain: "LoginItemTests", code: 2)
            }
            status = .notRegistered
        }

        func openSystemSettings() {
            openSettingsCalls += 1
        }
    }

    private var savedAutoLaunch = false

    override func setUp() {
        super.setUp()
        savedAutoLaunch = Options.shared.general.autoLaunch
    }

    override func tearDown() {
        // Put the option back while nothing real is attached, then restore the default.
        LoginItem.service = InertLoginItemService()
        Options.shared.general.autoLaunch = savedAutoLaunch
        LoginItem.service = LoginItem.defaultService
        super.tearDown()
    }

    @discardableResult
    private func install(_ status: LoginItemStatus) -> FakeService {
        let fake = FakeService(status: status)
        LoginItem.service = fake
        return fake
    }

    // MARK: - XCTest never registers anything

    func testTheDefaultServiceIsInertUnderXCTest() {
        XCTAssertTrue(LoginItem.defaultService is InertLoginItemService)
        XCTAssertTrue(LoginItem.service is InertLoginItemService,
                      "no test may leave another service installed")
    }

    func testTheInertServiceIgnoresEveryRequest() {
        LoginItem.service = InertLoginItemService()
        XCTAssertFalse(LoginItem.isEnabled)
        XCTAssertFalse(LoginItem.setEnabled(true), "nothing was registered, so it is not enabled")
        XCTAssertFalse(LoginItem.isEnabled)
        XCTAssertTrue(LoginItem.setEnabled(false))
        Utils.launchAtStartup(on: true)
        XCTAssertFalse(LoginItem.isEnabled)
    }

    // MARK: - Reading the state

    func testOnlyAnEnabledItemCountsAsEnabled() {
        install(.enabled)
        XCTAssertTrue(LoginItem.isEnabled)
        install(.requiresApproval)
        XCTAssertFalse(LoginItem.isEnabled)
        install(.notRegistered)
        XCTAssertFalse(LoginItem.isEnabled)
    }

    // MARK: - Enabling

    func testEnablingRegistersOnce() {
        let fake = install(.notRegistered)
        XCTAssertTrue(LoginItem.setEnabled(true))
        XCTAssertEqual(fake.registerCalls, 1)
        XCTAssertEqual(fake.openSettingsCalls, 0)
        XCTAssertTrue(LoginItem.isEnabled)
    }

    func testEnablingAnEnabledItemDoesNothing() {
        let fake = install(.enabled)
        XCTAssertTrue(LoginItem.setEnabled(true))
        XCTAssertEqual(fake.registerCalls, 0)
        XCTAssertEqual(fake.unregisterCalls, 0)
    }

    /// The user switched the item off in System Settings: registering cannot turn it on,
    /// so the Login Items page opens.
    func testEnablingAnItemThatNeedsApprovalOpensSystemSettings() {
        let fake = install(.requiresApproval)
        fake.statusAfterRegister = nil
        XCTAssertFalse(LoginItem.setEnabled(true))
        XCTAssertEqual(fake.registerCalls, 1)
        XCTAssertEqual(fake.openSettingsCalls, 1)
    }

    func testRegisteringIntoPendingApprovalOpensSystemSettings() {
        let fake = install(.notRegistered)
        fake.statusAfterRegister = .requiresApproval
        XCTAssertFalse(LoginItem.setEnabled(true))
        XCTAssertEqual(fake.openSettingsCalls, 1)
    }

    func testAFailedRegistrationIsReportedAndOpensNothing() {
        let fake = install(.notRegistered)
        fake.statusAfterRegister = nil
        XCTAssertFalse(LoginItem.setEnabled(true))
        XCTAssertEqual(fake.registerCalls, 1)
        XCTAssertEqual(fake.openSettingsCalls, 0)
        XCTAssertFalse(LoginItem.isEnabled)
    }

    // MARK: - Disabling

    func testDisablingUnregistersAnEnabledItem() {
        let fake = install(.enabled)
        XCTAssertTrue(LoginItem.setEnabled(false))
        XCTAssertEqual(fake.unregisterCalls, 1)
        XCTAssertFalse(LoginItem.isEnabled)
    }

    func testDisablingWhatIsNotEnabledDoesNothing() {
        for status in [LoginItemStatus.notRegistered, .requiresApproval] {
            let fake = install(status)
            XCTAssertTrue(LoginItem.setEnabled(false))
            XCTAssertEqual(fake.unregisterCalls, 0, "\(status)")
            XCTAssertEqual(fake.registerCalls, 0, "\(status)")
        }
    }

    func testAFailedUnregistrationIsReported() {
        let fake = install(.enabled)
        fake.unregisterFails = true
        XCTAssertFalse(LoginItem.setEnabled(false))
        XCTAssertEqual(fake.unregisterCalls, 1)
    }

    // MARK: - The API the General tab uses

    func testTheAutoLaunchOptionDrivesTheLoginItem() {
        let fake = install(.notRegistered)

        Options.shared.general.autoLaunch = true
        XCTAssertEqual(fake.registerCalls, 1)
        XCTAssertEqual(fake.status, .enabled)

        Options.shared.general.autoLaunch = false
        XCTAssertEqual(fake.unregisterCalls, 1)
        XCTAssertEqual(fake.status, .notRegistered)
    }

    func testUtilsLaunchAtStartupDrivesTheLoginItem() {
        let fake = install(.notRegistered)
        Utils.launchAtStartup(on: true)
        XCTAssertEqual(fake.registerCalls, 1)
        Utils.launchAtStartup(on: false)
        XCTAssertEqual(fake.unregisterCalls, 1)
    }

    /// Options.readOptions assigns the state it has just read. That must not change the system.
    func testAssigningTheStateThatWasJustReadChangesNothing() {
        for status in [LoginItemStatus.enabled, .requiresApproval, .notRegistered] {
            let fake = install(status)
            Options.shared.general.autoLaunch = LoginItem.isEnabled
            XCTAssertEqual(fake.registerCalls, 0, "\(status)")
            XCTAssertEqual(fake.unregisterCalls, 0, "\(status)")
            XCTAssertEqual(fake.openSettingsCalls, 0, "\(status)")
            XCTAssertEqual(fake.status, status)
        }
    }

    // MARK: - The General pane follows System Settings

    private func makeGeneralPane() throws -> PreferencesGeneralViewController {
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesGeneralViewController.self))
        let pane = try XCTUnwrap(
            storyboard.instantiateController(withIdentifier: PANEL_IDENTIFIER.general) as? PreferencesGeneralViewController
        )
        _ = pane.view
        return pane
    }

    func testTheGeneralPaneRereadsTheLoginItemEachTimeItAppears() throws {
        LoginItem.service = InertLoginItemService()
        Options.shared.general.autoLaunch = false
        let fake = install(.notRegistered)
        let pane = try makeGeneralPane()
        XCTAssertEqual(pane.launchOnLoginSwitch.state, .off)

        // Switched on in System Settings while the app runs.
        fake.status = .enabled
        pane.viewWillAppear()
        XCTAssertEqual(pane.launchOnLoginSwitch.state, .on)
        XCTAssertTrue(Options.shared.general.autoLaunch)

        // Switched off there again (it now waits for approval).
        fake.status = .requiresApproval
        pane.viewWillAppear()
        XCTAssertEqual(pane.launchOnLoginSwitch.state, .off)
        XCTAssertFalse(Options.shared.general.autoLaunch)

        // Reading never changes the system.
        XCTAssertEqual(fake.registerCalls, 0)
        XCTAssertEqual(fake.unregisterCalls, 0)
        XCTAssertEqual(fake.openSettingsCalls, 0)
        XCTAssertEqual(fake.status, .requiresApproval)
    }

    // MARK: - The switch shows the real state

    private func click(_ pane: PreferencesGeneralViewController, to state: NSControl.StateValue) {
        pane.launchOnLoginSwitch.state = state
        pane.launchOnLoginClick(pane.launchOnLoginSwitch)
    }

    func testCheckingAnItemThatNeedsApprovalLeavesTheBoxUnchecked() throws {
        LoginItem.service = InertLoginItemService()
        Options.shared.general.autoLaunch = false
        let fake = install(.requiresApproval)
        fake.statusAfterRegister = .requiresApproval
        let pane = try makeGeneralPane()

        click(pane, to: .on)

        XCTAssertEqual(fake.registerCalls, 1)
        XCTAssertEqual(fake.openSettingsCalls, 1, "System Settings opens where it can be approved")
        XCTAssertEqual(pane.launchOnLoginSwitch.state, .off, "it does not launch at login yet")
        XCTAssertFalse(Options.shared.general.autoLaunch)
    }

    func testUncheckingAlwaysUnregisters() throws {
        for status in [LoginItemStatus.enabled, .requiresApproval] {
            LoginItem.service = InertLoginItemService()
            Options.shared.general.autoLaunch = false
            let fake = install(status)
            let pane = try makeGeneralPane()
            // The box may still show an earlier state (switched off in System Settings since).
            pane.launchOnLoginSwitch.state = .on

            click(pane, to: .off)

            XCTAssertEqual(fake.unregisterCalls, 1, "\(status)")
            XCTAssertEqual(fake.status, .notRegistered, "\(status)")
            XCTAssertEqual(pane.launchOnLoginSwitch.state, .off, "\(status)")
            XCTAssertEqual(fake.openSettingsCalls, 0, "\(status)")
        }
    }

    func testUncheckingWithNothingRegisteredDoesNothing() throws {
        let fake = install(.notRegistered)
        let pane = try makeGeneralPane()
        click(pane, to: .off)
        XCTAssertEqual(fake.unregisterCalls, 0)
        XCTAssertEqual(fake.registerCalls, 0)
    }

    func testCheckingRegisters() throws {
        LoginItem.service = InertLoginItemService()
        Options.shared.general.autoLaunch = false
        let fake = install(.notRegistered)
        let pane = try makeGeneralPane()

        click(pane, to: .on)

        XCTAssertEqual(fake.registerCalls, 1)
        XCTAssertEqual(fake.status, .enabled)
        XCTAssertEqual(pane.launchOnLoginSwitch.state, .on)
        XCTAssertTrue(Options.shared.general.autoLaunch)
    }

    func testThePaneRereadsTheStateWhenItsWindowBecomesKey() throws {
        LoginItem.service = InertLoginItemService()
        Options.shared.general.autoLaunch = false
        let fake = install(.requiresApproval)
        let pane = try makeGeneralPane()
        let window = NSWindow(
            contentRect: NSRect(x: -20000, y: -20000, width: 450, height: 120),
            styleMask: [.titled], backing: .buffered, defer: true
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = pane
        defer { window.contentViewController = nil }
        XCTAssertEqual(pane.launchOnLoginSwitch.state, .off)

        // Approved in System Settings; the user comes back to the window.
        fake.status = .enabled
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        let shown = expectation(for: NSPredicate { _, _ in pane.launchOnLoginSwitch.state == .on }, evaluatedWith: nil)
        wait(for: [shown], timeout: 5)
        XCTAssertEqual(fake.registerCalls, 0)
    }
}
