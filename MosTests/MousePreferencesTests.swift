//
//  MousePreferencesTests.swift
//  MosTests
//
//  Mouse tab: controls write Options.shared.logiWheel, enabling rules, empty and
//  populated device list, read-back text and the tab's place in the toolbar.
//  Devices come from fixtures; no HID device is touched.
//

import XCTest
@testable import Mos_Debug

private func device(
    _ id: String,
    name: String,
    smartShift: Bool = true,
    scrollForce: Bool = false,
    mode: LogiWheelMode? = nil,
    sensitivity: Int? = nil,
    force: Int? = nil
) -> LogiWheelDeviceState {
    return LogiWheelDeviceState(
        id: id,
        deviceName: name,
        supportsSmartShift: smartShift,
        supportsScrollForce: scrollForce,
        mode: mode,
        smartShiftSensitivity: sensitivity,
        scrollForce: force
    )
}

final class MousePreferencesViewControllerTests: XCTestCase {

    private var savedSettings = LogiWheelSettings.default
    private var devices: [LogiWheelDeviceState] = []
    private var refreshCount = 0
    private var diagnosticsCount = 0

    override func setUp() {
        super.setUp()
        savedSettings = Options.shared.logiWheel
        Options.shared.logiWheel = .default
        devices = []
        refreshCount = 0
        diagnosticsCount = 0
    }

    override func tearDown() {
        Options.shared.logiWheel = savedSettings
        super.tearDown()
    }

    private func makeController() -> MousePreferencesViewController {
        let controller = MousePreferencesViewController()
        controller.deviceSource = MouseWheelDeviceSource(
            deviceStates: { [weak self] in self?.devices ?? [] },
            refresh: { [weak self] in self?.refreshCount += 1 },
            showDiagnostics: { [weak self] in self?.diagnosticsCount += 1 }
        )
        _ = controller.view
        controller.reloadDevices()
        return controller
    }

    private func setManaged(_ managed: Bool, mode: LogiWheelMode = .smartShift) {
        var settings = Options.shared.logiWheel
        settings.managedByMos = managed
        settings.mode = mode
        Options.shared.logiWheel = settings
    }

    private func send(_ control: NSControl) {
        XCTAssertTrue(control.sendAction(control.action, to: control.target))
    }

    // MARK: - Controls write Options

    func testManagedCheckboxWritesOptions() {
        let controller = makeController()
        XCTAssertEqual(controller.managedCheckbox.state, .off)

        controller.managedCheckbox.state = .on
        send(controller.managedCheckbox)
        XCTAssertTrue(Options.shared.logiWheel.managedByMos)

        controller.managedCheckbox.state = .off
        send(controller.managedCheckbox)
        XCTAssertFalse(Options.shared.logiWheel.managedByMos)
    }

    func testModeControlWritesEachMode() {
        setManaged(true)
        let controller = makeController()

        controller.modeControl.selectedSegment = 1
        send(controller.modeControl)
        XCTAssertEqual(Options.shared.logiWheel.mode, .ratchet)

        controller.modeControl.selectedSegment = 2
        send(controller.modeControl)
        XCTAssertEqual(Options.shared.logiWheel.mode, .freeSpin)

        controller.modeControl.selectedSegment = 0
        send(controller.modeControl)
        XCTAssertEqual(Options.shared.logiWheel.mode, .smartShift)
    }

    func testSensitivitySliderWritesRoundedPercent() {
        setManaged(true)
        let controller = makeController()

        controller.sensitivitySlider.doubleValue = 72.4
        send(controller.sensitivitySlider)

        XCTAssertEqual(Options.shared.logiWheel.smartShiftSensitivity, 72)
        XCTAssertEqual(controller.sensitivityValueLabel.stringValue, MouseWheelText.percent(72))
    }

    func testScrollForceSliderWritesRoundedPercent() {
        devices = [device("a", name: "MX Master 4", scrollForce: true)]
        setManaged(true)
        let controller = makeController()

        controller.scrollForceSlider.doubleValue = 18.6
        send(controller.scrollForceSlider)

        XCTAssertEqual(Options.shared.logiWheel.scrollForce, 19)
        XCTAssertEqual(controller.scrollForceValueLabel.stringValue, MouseWheelText.percent(19))
    }

    func testOtherSettingsAreKeptWhenOneControlChanges() {
        Options.shared.logiWheel = LogiWheelSettings(
            managedByMos: true, mode: .ratchet, smartShiftSensitivity: 30, scrollForce: 80
        )
        let controller = makeController()

        controller.modeControl.selectedSegment = 0
        send(controller.modeControl)

        XCTAssertEqual(
            Options.shared.logiWheel,
            LogiWheelSettings(managedByMos: true, mode: .smartShift, smartShiftSensitivity: 30, scrollForce: 80)
        )
    }

    func testControlsShowStoredSettings() {
        Options.shared.logiWheel = LogiWheelSettings(
            managedByMos: true, mode: .freeSpin, smartShiftSensitivity: 33, scrollForce: 66
        )
        let controller = makeController()

        XCTAssertEqual(controller.managedCheckbox.state, .on)
        XCTAssertEqual(controller.modeControl.selectedSegment, 2)
        XCTAssertEqual(controller.sensitivitySlider.integerValue, 33)
        XCTAssertEqual(controller.scrollForceSlider.integerValue, 66)
        XCTAssertEqual(controller.sensitivityValueLabel.stringValue, MouseWheelText.percent(33))
        XCTAssertEqual(controller.scrollForceValueLabel.stringValue, MouseWheelText.percent(66))
    }

    // MARK: - Enabling rules

    func testAllWheelControlsDisabledWhenNotManaged() {
        devices = [device("a", name: "MX Master 4", scrollForce: true)]
        setManaged(false)
        let controller = makeController()

        XCTAssertTrue(controller.managedCheckbox.isEnabled)
        XCTAssertFalse(controller.modeControl.isEnabled)
        XCTAssertFalse(controller.sensitivitySlider.isEnabled)
        XCTAssertFalse(controller.scrollForceSlider.isEnabled)
    }

    func testTurningManagementOnEnablesControls() {
        devices = [device("a", name: "MX Master 4", scrollForce: true)]
        let controller = makeController()

        controller.managedCheckbox.state = .on
        send(controller.managedCheckbox)

        XCTAssertTrue(controller.modeControl.isEnabled)
        XCTAssertTrue(controller.sensitivitySlider.isEnabled)
        XCTAssertTrue(controller.scrollForceSlider.isEnabled)
    }

    func testSensitivityEnabledOnlyInSmartShiftMode() {
        setManaged(true, mode: .ratchet)
        let controller = makeController()
        XCTAssertTrue(controller.modeControl.isEnabled)
        XCTAssertFalse(controller.sensitivitySlider.isEnabled)

        controller.modeControl.selectedSegment = 0
        send(controller.modeControl)
        XCTAssertTrue(controller.sensitivitySlider.isEnabled)

        controller.modeControl.selectedSegment = 2
        send(controller.modeControl)
        XCTAssertFalse(controller.sensitivitySlider.isEnabled)
    }

    func testScrollForceNeedsAConnectedMouseThatSupportsIt() {
        devices = [device("a", name: "MX Anywhere 3S")]
        setManaged(true)
        let controller = makeController()
        XCTAssertFalse(controller.scrollForceSlider.isEnabled)

        devices.append(device("b", name: "MX Master 4", scrollForce: true))
        NotificationCenter.default.post(name: LogiCenter.wheelStateChanged, object: nil)
        XCTAssertTrue(controller.scrollForceSlider.isEnabled)
    }

    func testControlRulesTable() {
        let force = [device("a", name: "A", scrollForce: true)]
        let noForce = [device("b", name: "B")]
        func rules(_ managed: Bool, _ mode: LogiWheelMode, _ devices: [LogiWheelDeviceState]) -> MouseWheelControlRules {
            let settings = LogiWheelSettings(managedByMos: managed, mode: mode, smartShiftSensitivity: 50, scrollForce: 50)
            return MouseWheelControlRules(settings: settings, devices: devices)
        }

        let off = rules(false, .smartShift, force)
        XCTAssertEqual([off.modeEnabled, off.sensitivityEnabled, off.scrollForceEnabled], [false, false, false])
        let smart = rules(true, .smartShift, force)
        XCTAssertEqual([smart.modeEnabled, smart.sensitivityEnabled, smart.scrollForceEnabled], [true, true, true])
        let ratchet = rules(true, .ratchet, noForce)
        XCTAssertEqual([ratchet.modeEnabled, ratchet.sensitivityEnabled, ratchet.scrollForceEnabled], [true, false, false])
        let noDevices = rules(true, .freeSpin, [])
        XCTAssertEqual([noDevices.modeEnabled, noDevices.sensitivityEnabled, noDevices.scrollForceEnabled], [true, false, false])
    }

    // MARK: - Device list

    func testEmptyStateWithoutDevices() {
        let controller = makeController()

        XCTAssertTrue(controller.deviceEntryViews.isEmpty)
        XCTAssertEqual(controller.deviceListColumn.arrangedSubviews, [controller.emptyStateView])
        XCTAssertTrue(controller.modeReadbackLabel.isHidden)
        XCTAssertTrue(controller.sensitivityReadbackLabel.isHidden)
        XCTAssertTrue(controller.scrollForceReadbackLabel.isHidden)
    }

    func testPopulatedListShowsOneEntryPerDevice() {
        devices = [
            device("a", name: "MX Master 4", scrollForce: true, mode: .smartShift, sensitivity: 40, force: 65),
            device("b", name: "MX Anywhere 3S", mode: .ratchet, sensitivity: 50),
        ]
        let controller = makeController()

        XCTAssertEqual(controller.deviceEntryViews.count, 2)
        XCTAssertEqual(controller.deviceListColumn.arrangedSubviews, controller.deviceEntryViews)
        XCTAssertFalse(controller.deviceListColumn.arrangedSubviews.contains(controller.emptyStateView))
        let texts = controller.deviceEntryViews.flatMap(Self.labels(in:))
        XCTAssertTrue(texts.contains("MX Master 4"))
        XCTAssertTrue(texts.contains("MX Anywhere 3S"))
        XCTAssertTrue(texts.contains(MouseWheelText.capabilities(of: devices[0])))
        XCTAssertFalse(controller.modeReadbackLabel.isHidden)
        XCTAssertFalse(controller.scrollForceReadbackLabel.isHidden)
    }

    func testWheelStateNotificationSwitchesBetweenEmptyAndPopulated() {
        let controller = makeController()
        XCTAssertTrue(controller.deviceEntryViews.isEmpty)

        devices = [device("a", name: "MX Master 3S", mode: .freeSpin)]
        NotificationCenter.default.post(name: LogiCenter.wheelStateChanged, object: nil)
        XCTAssertEqual(controller.deviceEntryViews.count, 1)
        XCTAssertEqual(controller.modeReadbackLabel.stringValue, MouseWheelText.modeReadback(devices))

        devices = []
        NotificationCenter.default.post(name: LogiCenter.wheelStateChanged, object: nil)
        XCTAssertTrue(controller.deviceEntryViews.isEmpty)
        XCTAssertEqual(controller.deviceListColumn.arrangedSubviews, [controller.emptyStateView])
    }

    func testPopulatedViewIsTallerAndKeepsTabWidth() {
        let controller = makeController()
        let emptyHeight = controller.view.frame.height
        XCTAssertEqual(controller.view.frame.width, MousePreferencesViewController.contentWidth)

        devices = [device("a", name: "A"), device("b", name: "B"), device("c", name: "C")]
        controller.reloadDevices()
        XCTAssertEqual(controller.view.frame.width, MousePreferencesViewController.contentWidth)
        XCTAssertGreaterThan(controller.view.frame.height, emptyHeight)
        XCTAssertEqual(controller.view.frame.size, controller.view.fittingSize)
    }

    func testAppearingRequestsFreshDeviceState() {
        let controller = makeController()
        XCTAssertEqual(refreshCount, 0)
        controller.viewWillAppear()
        XCTAssertEqual(refreshCount, 1)
    }

    func testDiagnosticsButtonOpensPanel() {
        let controller = makeController()
        send(controller.diagnosticsButton)
        XCTAssertEqual(diagnosticsCount, 1)
    }

    private static func labels(in view: NSView) -> [String] {
        var result: [String] = []
        if let field = view as? NSTextField { result.append(field.stringValue) }
        for subview in view.subviews { result += labels(in: subview) }
        return result
    }
}

final class MousePreferencesTextTests: XCTestCase {

    func testReadbackIsNilWhenNoMouseReportsTheValue() {
        XCTAssertNil(MouseWheelText.sensitivityReadback([]))
        XCTAssertNil(MouseWheelText.scrollForceReadback([device("a", name: "MX Anywhere 3S", sensitivity: 40)]))
    }

    func testReadbackForOneMouse() {
        let devices = [device("a", name: "MX Master 4", sensitivity: 40)]
        let expected = String(
            format: NSLocalizedString("mouse-wheel-readback-one", comment: ""),
            MouseWheelText.percent(40)
        )
        XCTAssertEqual(MouseWheelText.sensitivityReadback(devices), expected)
    }

    func testReadbackNamesEachMouseWhenSeveralAreConnected() {
        let devices = [
            device("a", name: "MX Master 4", scrollForce: true, force: 65),
            device("b", name: "MX Anywhere 3S"),
            device("c", name: "MX Master 3S", mode: .ratchet),
        ]
        let named = NSLocalizedString("mouse-wheel-readback-named", comment: "")
        XCTAssertEqual(
            MouseWheelText.scrollForceReadback(devices),
            String(format: named, "MX Master 4", MouseWheelText.percent(65))
        )
        XCTAssertEqual(
            MouseWheelText.modeReadback(devices),
            String(format: named, "MX Master 3S", MouseWheelText.modeName(.ratchet))
        )
    }

    func testCapabilitiesListWhatTheMouseSupports() {
        let both = MouseWheelText.capabilities(of: device("a", name: "A", smartShift: true, scrollForce: true))
        let smartShift = NSLocalizedString("mouse-device-supports-smartshift", comment: "")
        let force = NSLocalizedString("mouse-device-supports-scroll-force", comment: "")
        XCTAssertEqual(both, "\(smartShift), \(force)")
        XCTAssertEqual(MouseWheelText.capabilities(of: device("b", name: "B")), smartShift)
        XCTAssertEqual(
            MouseWheelText.capabilities(of: device("c", name: "C", smartShift: false)),
            NSLocalizedString("mouse-device-supports-none", comment: "")
        )
    }

    func testModeSegmentsFollowContractOrder() {
        XCTAssertEqual(MouseWheelText.modes, [.smartShift, .ratchet, .freeSpin])
        XCTAssertEqual(Set(MouseWheelText.modes), Set(LogiWheelMode.allCases))
    }
}

final class MousePreferencesTabPlacementTests: XCTestCase {

    private func loadPreferencesWindow() -> (NSWindowController, PreferencesTabViewController) {
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesTabViewController.self))
        let windowController = storyboard.instantiateController(
            withIdentifier: "preferencesWindowController"
        ) as! NSWindowController
        _ = windowController.window
        let tabs = windowController.contentViewController as! PreferencesTabViewController
        return (windowController, tabs)
    }

    func testMouseTabSitsRightAfterButtons() {
        let (windowController, tabs) = loadPreferencesWindow()
        defer { windowController.close() }

        let identifiers = tabs.tabViewItems.compactMap { $0.identifier as? String }
        XCTAssertEqual(identifiers, ["general", "scrolling", "buttons", "mouse", "application", "updates", "about"])
        let mouseItem = tabs.tabViewItems[3]
        XCTAssertTrue(mouseItem.viewController is MousePreferencesViewController)
        XCTAssertNotNil(mouseItem.image)
        XCTAssertFalse(mouseItem.label.isEmpty)
        XCTAssertEqual(tabs.selectedTabViewItemIndex, 0)
    }

    func testToolbarKeepsEveryTabWithoutFlexibleSpaces() {
        let (windowController, tabs) = loadPreferencesWindow()
        defer { windowController.close() }

        tabs.removeToolbarFlexibleSpaces()

        let toolbarIdentifiers = windowController.window?.toolbar?.items.map { $0.itemIdentifier.rawValue } ?? []
        XCTAssertEqual(toolbarIdentifiers, ["general", "scrolling", "buttons", "mouse", "application", "updates", "about"])
    }
}
