//
//  MousePreferencesTests.swift
//  MosTests
//
//  The Mouse tab: every control reads and writes the right option, which rows MX Master 4,
//  MX Master 3S, MX Master 3 and no mouse get, what is greyed out while Scrollio does not
//  manage the mouse, the "On the mouse" lines, the sample pulse of the strength slider,
//  the header lighting up the part of the hovered or focused row, and the tab's place in
//  the toolbar. The mice are fixtures: nothing is read from or written to a real mouse, and
//  nothing is shown on screen.
//

import XCTest
@testable import Mos_Debug

/// What the mice report, as LogiCenter would hand it to the tab. The MX Master 4 values are
/// the owner's mouse on 2026-11-11.
enum MouseDeviceFixtures {

    static let dpiChoices = Array(stride(from: 200, through: 8000, by: 50))

    static func battery(
        _ percent: Int?,
        level: LogiMouseDeviceState.Battery.Level = .good,
        charging: LogiMouseDeviceState.Battery.Charging = .discharging,
        approximate: Bool = false
    ) -> LogiMouseDeviceState.Battery {
        return LogiMouseDeviceState.Battery(percent: percent, level: level, charging: charging, isApproximate: approximate)
    }

    static func wheel(
        id: String, name: String, scrollForceSupported: Bool,
        mode: LogiWheelMode?, sensitivity: Int?, scrollForce: Int?
    ) -> LogiWheelDeviceState {
        return LogiWheelDeviceState(
            id: id, deviceName: name, supportsSmartShift: true, supportsScrollForce: scrollForceSupported,
            mode: mode, smartShiftSensitivity: sensitivity, scrollForce: scrollForce
        )
    }

    static func mxMaster4(
        id: String = "mx4",
        managed: Bool = false,
        battery: LogiMouseDeviceState.Battery? = battery(75),
        dpiChoices: [Int] = dpiChoices,
        dpi: Int? = 1000,
        hapticsOn: Bool? = false,
        strength: Int? = 100,
        fewLevels: Bool? = false,
        pressForce: Int? = 4134,
        pressRange: ClosedRange<Int>? = 4134...6872,
        pressChangeable: Bool = true,
        mode: LogiWheelMode? = .smartShift,
        sensitivity: Int? = 50,
        scrollForce: Int? = 100
    ) -> LogiMouseDeviceState {
        let name = "MX Master 4"
        return LogiMouseDeviceState(
            id: id,
            deviceName: name,
            supported: [.battery, .pointerSpeed, .haptics, .pressForce],
            managed: managed,
            battery: battery,
            pointerSpeed: .init(choices: dpiChoices, dpi: .init(onMouse: dpi, setByYou: nil), defaultDPI: 1000),
            haptics: .init(
                isOn: .init(onMouse: hapticsOn, setByYou: nil),
                strength: .init(onMouse: strength, setByYou: nil),
                hasFewLevels: fewLevels,
                fewLevelChoices: [25, 50, 75, 100]
            ),
            pressForce: .init(
                force: .init(onMouse: pressForce, setByYou: nil),
                range: pressRange,
                defaultForce: 5167,
                isChangeable: pressChangeable
            ),
            wheel: wheel(id: id, name: name, scrollForceSupported: true, mode: mode, sensitivity: sensitivity, scrollForce: scrollForce)
        )
    }

    static func mxMaster3S(
        id: String = "mx3s",
        battery: LogiMouseDeviceState.Battery? = battery(90),
        dpi: Int? = 1000,
        mode: LogiWheelMode? = .smartShift,
        sensitivity: Int? = 50
    ) -> LogiMouseDeviceState {
        let name = "MX Master 3S"
        return LogiMouseDeviceState(
            id: id,
            deviceName: name,
            supported: [.battery, .pointerSpeed],
            managed: false,
            battery: battery,
            pointerSpeed: .init(choices: dpiChoices, dpi: .init(onMouse: dpi, setByYou: nil), defaultDPI: 1000),
            haptics: nil,
            pressForce: nil,
            wheel: wheel(id: id, name: name, scrollForceSupported: false, mode: mode, sensitivity: sensitivity, scrollForce: nil)
        )
    }

    /// The original MX Master 3: the battery only in coarse steps, the older SmartShift.
    static func mxMaster3(id: String = "mx3") -> LogiMouseDeviceState {
        let name = "MX Master 3"
        return LogiMouseDeviceState(
            id: id,
            deviceName: name,
            supported: [.battery, .pointerSpeed],
            managed: false,
            battery: battery(50, level: .good, approximate: true),
            pointerSpeed: .init(
                choices: Array(stride(from: 200, through: 4000, by: 50)),
                dpi: .init(onMouse: 1000, setByYou: nil),
                defaultDPI: 1000
            ),
            haptics: nil,
            pressForce: nil,
            wheel: wheel(id: id, name: name, scrollForceSupported: false, mode: .smartShift, sensitivity: 50, scrollForce: nil)
        )
    }
}

final class MousePreferencesViewControllerTests: XCTestCase {

    private typealias Fixtures = MouseDeviceFixtures

    private var savedMouse = LogiMouseSettings.default
    private var savedWheel = LogiWheelSettings.default
    private var devices: [LogiMouseDeviceState] = []
    private var tracking = false
    private var refreshCount = 0
    private var diagnosticsCount = 0
    private var sampleCount = 0

    override func setUp() {
        super.setUp()
        savedMouse = Options.shared.logiMouse
        savedWheel = Options.shared.logiWheel
        Options.shared.logiMouse = .default
        Options.shared.logiWheel = .default
        devices = []
        tracking = false
        refreshCount = 0
        diagnosticsCount = 0
        sampleCount = 0
    }

    override func tearDown() {
        Options.shared.logiMouse = savedMouse
        Options.shared.logiWheel = savedWheel
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeController(_ devices: [LogiMouseDeviceState] = []) -> MousePreferencesViewController {
        self.devices = devices
        let controller = MousePreferencesViewController()
        controller.deviceSource = MouseDeviceSource(
            deviceStates: { [weak self] in self?.devices ?? [] },
            refresh: { [weak self] in self?.refreshCount += 1 },
            showDiagnostics: { [weak self] in self?.diagnosticsCount += 1 },
            playHapticSample: { [weak self] in self?.sampleCount += 1 }
        )
        controller.isTrackingMouse = { [weak self] in self?.tracking ?? false }
        controller.readbackSettleTime = 0
        _ = controller.view
        controller.reloadDevices()
        return controller
    }

    private func manage(_ on: Bool = true, mode: LogiWheelMode = .smartShift, sensitivity: Int = 50, scrollForce: Int = 100) {
        Options.shared.logiWheel = LogiWheelSettings(
            managedByMos: on, mode: mode, smartShiftSensitivity: sensitivity, scrollForce: scrollForce
        )
    }

    private func send(_ control: NSControl, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(control.sendAction(control.action, to: control.target), file: file, line: line)
    }

    private func set(_ toggle: NSSwitch, _ on: Bool) {
        toggle.state = on ? .on : .off
        send(toggle)
    }

    private func drag(_ slider: NSSlider, to value: Double) {
        slider.doubleValue = value
        send(slider)
    }

    private func text(_ key: String) -> String {
        return NSLocalizedString(key, comment: "")
    }

    private func onTheMouse(_ value: String) -> String {
        return MouseText.onTheMouse(value)
    }

    private func allSubviews(of view: NSView) -> [NSView] {
        return view.subviews.flatMap { [$0] + allSubviews(of: $0) }
    }

    /// Where a view sits in the pane by its alignment rectangle (the root is not flipped).
    private func frame(of view: NSView, in controller: MousePreferencesViewController) -> NSRect {
        return controller.view.convert(view.alignmentRect(forFrame: view.frame), from: view.superview)
    }

    private func sliderRows(_ c: MousePreferencesViewController) -> [PreferencesSliderRow] {
        return [c.pointerSpeedRow, c.sensitivityRow, c.firmnessRow, c.strengthRow, c.pressForceRow]
    }

    /// Every row of the tab except "no mouse", top to bottom.
    private func settingRows(_ c: MousePreferencesViewController) -> [PreferencesGroupRow] {
        return [c.managedRow, c.pointerSpeedRow, c.wheelModeRow, c.sensitivityRow, c.firmnessRow,
                c.hapticsRow, c.strengthRow, c.pressForceRow]
    }

    // MARK: - Controls write Options

    func testManagedSwitchIsTheOneSwitchForTheMouse() {
        let controller = makeController([Fixtures.mxMaster4()])
        XCTAssertFalse(controller.managedRow.isOn)

        set(controller.managedSwitch, true)
        XCTAssertTrue(Options.shared.logiMouseManaged)
        XCTAssertTrue(Options.shared.logiWheel.managedByMos)

        set(controller.managedSwitch, false)
        XCTAssertFalse(Options.shared.logiMouseManaged)
    }

    func testPointerSpeedStopsAtTheRungsOfTheLadder() throws {
        manage()
        let controller = makeController([Fixtures.mxMaster4()])
        let slider = try XCTUnwrap(controller.pointerSpeedSlider as? PreferencesSlider)
        let ladder = MousePaneModel.pointerLadder
        XCTAssertEqual(ladder, [400, 600, 800, 1000, 1200, 1600, 2000, 2400, 3200, 4000, 6000, 8000])
        XCTAssertEqual(controller.model.pointerChoices, ladder, "200…8000 in steps of 50 has every rung")
        XCTAssertEqual(slider.minValue, 0)
        XCTAssertEqual(slider.maxValue, 11)
        XCTAssertEqual(slider.numberOfTickMarks, 12)
        XCTAssertEqual(slider.tickMarkPosition, .below)
        XCTAssertTrue(slider.allowsTickMarkValuesOnly)
        XCTAssertEqual(slider.doubleValue, 3, "1000 DPI")
        XCTAssertEqual(controller.pointerSpeedRow.valueText, "1000 DPI")

        drag(slider, to: 5.3)
        XCTAssertEqual(Options.shared.logiMouse.pointerDPI, 1600)
        XCTAssertEqual(controller.pointerSpeedRow.valueText, "1600 DPI")
        XCTAssertEqual(slider.doubleValue, 5, "the knob stops on the rung")

        for (index, dpi) in ladder.enumerated() {
            drag(slider, to: Double(index))
            XCTAssertEqual(Options.shared.logiMouse.pointerDPI, dpi)
            XCTAssertEqual(controller.pointerSpeedRow.valueText, MouseText.dpi(dpi))
        }

        // Arrow keys move one rung.
        XCTAssertFalse(slider.moveKnob(by: 1), "already at 8000")
        XCTAssertTrue(slider.moveKnob(by: -1))
        XCTAssertEqual(Options.shared.logiMouse.pointerDPI, 6000)
        XCTAssertTrue(slider.moveKnob(by: -1))
        XCTAssertEqual(Options.shared.logiMouse.pointerDPI, 4000)
    }

    func testAMouseWithAShortDPIListGetsTheRungsItHas() throws {
        manage()
        let controller = makeController([Fixtures.mxMaster4(dpiChoices: [400, 800, 1600, 3200], dpi: 800)])
        let slider = try XCTUnwrap(controller.pointerSpeedSlider)
        XCTAssertEqual(controller.model.pointerChoices, [400, 800, 1600, 3200])
        XCTAssertEqual(slider.numberOfTickMarks, 4)
        XCTAssertTrue(slider.allowsTickMarkValuesOnly)
        XCTAssertEqual(slider.doubleValue, 1)

        drag(slider, to: 3)
        XCTAssertEqual(Options.shared.logiMouse.pointerDPI, 3200)
        // A stored value the mouse does not take shows as the nearest it does.
        Options.shared.logiMouse.pointerDPI = 1000
        controller.syncControls()
        XCTAssertEqual(controller.pointerSpeedRow.valueText, "800 DPI")
        XCTAssertEqual(slider.doubleValue, 1)
        XCTAssertEqual(Options.shared.logiMouse.pointerDPI, 1000, "kept as stored")
    }

    func testPointerRungsAreTheLadderAsTheMouseOffersIt() {
        let ladder = MousePaneModel.pointerLadder
        XCTAssertEqual(MousePaneModel.pointerRungs(offered: Fixtures.dpiChoices), ladder)
        XCTAssertEqual(MousePaneModel.pointerRungs(offered: [400, 800, 1600, 3200]), [400, 800, 1600, 3200])
        // MX Master 3 stops at 4000: the two top rungs become 4000 once.
        XCTAssertEqual(
            MousePaneModel.pointerRungs(offered: Array(stride(from: 200, through: 4000, by: 50))),
            [400, 600, 800, 1000, 1200, 1600, 2000, 2400, 3200, 4000]
        )
        // Each rung becomes the nearest the mouse offers (the lower one on a tie).
        XCTAssertEqual(MousePaneModel.pointerRungs(offered: [500, 1000, 2000, 4000]), [500, 1000, 2000, 4000])
        XCTAssertEqual(MousePaneModel.pointerRungs(offered: [1000]), [1000])
        XCTAssertEqual(MousePaneModel.pointerRungs(offered: []), [])
        // One value only: no tick marks, the slider has nothing to choose.
        let model = MousePaneModel(devices: [Fixtures.mxMaster4(dpiChoices: [1000])], settings: .default, wheel: .default)
        XCTAssertNil(model.pointerSpeed?.scale)
    }

    func testADPIBetweenTwoRungsShowsOnTheNearerTickAndIsKept() throws {
        manage()
        Options.shared.logiMouse.pointerDPI = 1750
        let controller = makeController([Fixtures.mxMaster4(dpi: 1750)])
        let slider = try XCTUnwrap(controller.pointerSpeedSlider as? PreferencesSlider)
        XCTAssertEqual(slider.doubleValue, 5, "1600 is nearer than 2000")
        XCTAssertEqual(controller.pointerSpeedRow.valueText, "1750 DPI")
        XCTAssertNil(controller.pointerSpeedRow.explanation?.components(separatedBy: "\n").dropFirst().first)

        controller.reloadDevices()
        controller.viewWillAppear()
        XCTAssertEqual(Options.shared.logiMouse.pointerDPI, 1750, "showing it writes nothing")

        // Only moving the slider writes a rung.
        XCTAssertTrue(slider.moveKnob(by: 1))
        XCTAssertEqual(Options.shared.logiMouse.pointerDPI, 2000)

        // The mouse's own value, while Scrollio does not manage it.
        manage(false)
        Options.shared.logiMouse = .default
        let other = makeController([Fixtures.mxMaster4(dpi: 2300)])
        XCTAssertEqual(other.pointerSpeedSlider.doubleValue, 7, "2400")
        XCTAssertEqual(other.pointerSpeedRow.valueText, "2300 DPI")
        XCTAssertNil(Options.shared.logiMouse.pointerDPI)
    }

    func testWheelModeWritesEachMode() {
        manage()
        let controller = makeController([Fixtures.mxMaster4()])
        let expected: [LogiWheelMode] = [.smartShift, .ratchet, .freeSpin]
        XCTAssertEqual(controller.wheelModeControl.segmentCount, 3)
        for (index, mode) in expected.enumerated().reversed() {
            controller.wheelModeControl.selectedSegment = index
            send(controller.wheelModeControl)
            XCTAssertEqual(Options.shared.logiWheel.mode, mode)
            XCTAssertEqual(controller.wheelModeRow.explanation, MouseText.modeHint(mode).appending(
                mode == .smartShift ? "" : "\n" + onTheMouse(MouseText.modeName(.smartShift))
            ))
        }
    }

    func testSensitivityAndFirmnessWriteTheWheelSettings() {
        manage()
        let controller = makeController([Fixtures.mxMaster4()])

        for slider in [controller.sensitivitySlider!, controller.firmnessSlider!] {
            XCTAssertEqual(slider.minValue, 0)
            XCTAssertEqual(slider.maxValue, 100)
            XCTAssertEqual(slider.numberOfTickMarks, 11, "a tick every 10 %")
            XCTAssertTrue(slider.allowsTickMarkValuesOnly)
        }

        drag(controller.sensitivitySlider, to: 72.4)
        XCTAssertEqual(Options.shared.logiWheel.smartShiftSensitivity, 70)
        XCTAssertEqual(controller.sensitivityRow.valueText, MouseText.percent(70))

        drag(controller.firmnessSlider, to: 18.6)
        XCTAssertEqual(Options.shared.logiWheel.scrollForce, 20)
        XCTAssertEqual(controller.firmnessRow.valueText, MouseText.percent(20))

        // The lowest tick writes the least the mouse takes.
        drag(controller.firmnessSlider, to: 0)
        XCTAssertEqual(Options.shared.logiWheel.scrollForce, 1)
        XCTAssertEqual(controller.firmnessRow.valueText, MouseText.percent(1))
        XCTAssertEqual(controller.firmnessSlider.doubleValue, 0)
    }

    func testHapticsSwitchAndStrengthWriteTheMouseSettings() {
        manage()
        let controller = makeController([Fixtures.mxMaster4()])
        XCTAssertFalse(controller.hapticsRow.isOn)

        set(controller.hapticsSwitch, true)
        XCTAssertEqual(Options.shared.logiMouse.hapticsOn, true)

        XCTAssertEqual(controller.strengthSlider.minValue, 20)
        XCTAssertEqual(controller.strengthSlider.maxValue, 100)
        XCTAssertEqual(controller.strengthSlider.numberOfTickMarks, 5, "20, 40, 60, 80 and 100 %")
        XCTAssertTrue(controller.strengthSlider.allowsTickMarkValuesOnly)
        drag(controller.strengthSlider, to: 63.4)
        XCTAssertEqual(Options.shared.logiMouse.hapticStrength, 60)
        XCTAssertEqual(controller.strengthRow.valueText, MouseText.percent(60))

        set(controller.hapticsSwitch, false)
        XCTAssertEqual(Options.shared.logiMouse.hapticsOn, false)
        XCTAssertEqual(Options.shared.logiMouse.hapticStrength, 60)
    }

    func testStrengthOnAMouseWithFewLevelsStopsAtThem() {
        manage()
        Options.shared.logiMouse.hapticsOn = true
        let controller = makeController([Fixtures.mxMaster4(hapticsOn: true, strength: 75, fewLevels: true)])
        let slider = controller.strengthSlider!
        XCTAssertEqual(slider.maxValue, 3)
        XCTAssertEqual(slider.numberOfTickMarks, 4)
        XCTAssertTrue(slider.allowsTickMarkValuesOnly)
        XCTAssertEqual(slider.doubleValue, 2)
        XCTAssertEqual(controller.strengthRow.valueText, MouseText.percent(75))

        drag(slider, to: 1)
        XCTAssertEqual(Options.shared.logiMouse.hapticStrength, 50)
    }

    func testThumbPanelPressWritesTheMouseOwnUnits() {
        manage()
        let controller = makeController([Fixtures.mxMaster4()])
        let slider = controller.pressForceSlider!
        XCTAssertEqual(slider.minValue, 4134)
        XCTAssertEqual(slider.maxValue, 6872)
        XCTAssertEqual(slider.numberOfTickMarks, 5, "0, 25, 50, 75 and 100 % of the mouse's range")
        XCTAssertTrue(slider.allowsTickMarkValuesOnly)
        XCTAssertEqual(slider.doubleValue, 4134, "the mouse's own value until you set one")
        XCTAssertEqual(controller.pressForceRow.valueText, MouseText.percent(0))

        drag(slider, to: 5503.4)
        XCTAssertEqual(Options.shared.logiMouse.pressForce, 5503)
        XCTAssertEqual(controller.pressForceRow.valueText, MouseText.percent(50))
    }

    func testOneControlLeavesTheOtherSettingsAlone() {
        manage(mode: .ratchet, sensitivity: 30, scrollForce: 80)
        Options.shared.logiMouse = LogiMouseSettings(pointerDPI: 1600, hapticsOn: true, hapticStrength: 40, pressForce: 6000)
        let controller = makeController([Fixtures.mxMaster4()])

        controller.wheelModeControl.selectedSegment = 0
        send(controller.wheelModeControl)
        drag(controller.strengthSlider, to: 80)

        XCTAssertEqual(
            Options.shared.logiWheel,
            LogiWheelSettings(managedByMos: true, mode: .smartShift, smartShiftSensitivity: 30, scrollForce: 80)
        )
        XCTAssertEqual(
            Options.shared.logiMouse,
            LogiMouseSettings(pointerDPI: 1600, hapticsOn: true, hapticStrength: 80, pressForce: 6000)
        )
    }

    // MARK: - Tick marks

    /// Values set before the sliders had tick marks stay as they are until a slider moves.
    func testStoredValuesBetweenTicksAreShownAndNeverRewritten() {
        manage(sensitivity: 72, scrollForce: 19)
        let stored = LogiMouseSettings(pointerDPI: 1750, hapticsOn: true, hapticStrength: 63, pressForce: 5167)
        Options.shared.logiMouse = stored
        let wheel = Options.shared.logiWheel
        let controller = makeController([Fixtures.mxMaster4(dpi: 1750, hapticsOn: true, strength: 63, pressForce: 5167, sensitivity: 72, scrollForce: 19)])

        XCTAssertEqual(controller.sensitivitySlider.doubleValue, 70)
        XCTAssertEqual(controller.sensitivityRow.valueText, MouseText.percent(72))
        XCTAssertEqual(controller.firmnessSlider.doubleValue, 20)
        XCTAssertEqual(controller.firmnessRow.valueText, MouseText.percent(19))
        XCTAssertEqual(controller.strengthSlider.doubleValue, 60)
        XCTAssertEqual(controller.strengthRow.valueText, MouseText.percent(63))
        XCTAssertEqual(controller.pressForceSlider.doubleValue, 5503)
        XCTAssertEqual(controller.pressForceRow.valueText, MouseText.percent(38))
        for row in sliderRows(controller) {
            XCTAssertNil(row.explanation?.components(separatedBy: "\n").dropFirst().first, "no \"On the mouse\" line: \(row.title)")
        }

        controller.reloadDevices()
        controller.viewWillAppear()
        controller.syncControls()
        XCTAssertEqual(Options.shared.logiMouse, stored, "loading and showing write nothing")
        XCTAssertEqual(Options.shared.logiWheel, wheel)
    }

    func testEverySliderWritesTheValueOfATick() {
        manage()
        Options.shared.logiMouse.hapticsOn = true
        let controller = makeController([Fixtures.mxMaster4(hapticsOn: true)])
        let cases: [(NSSlider, () -> Int?, [Int])] = [
            (controller.pointerSpeedSlider, { Options.shared.logiMouse.pointerDPI }, MousePaneModel.pointerLadder),
            (controller.sensitivitySlider, { Options.shared.logiWheel.smartShiftSensitivity }, [1, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100]),
            (controller.firmnessSlider, { Options.shared.logiWheel.scrollForce }, [1, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100]),
            (controller.strengthSlider, { Options.shared.logiMouse.hapticStrength }, [20, 40, 60, 80, 100]),
            (controller.pressForceSlider, { Options.shared.logiMouse.pressForce }, [4134, 4819, 5503, 6188, 6872]),
        ]
        for (slider, stored, grid) in cases {
            var written = Set<Int>()
            for fraction in stride(from: 0.0, through: 1.0, by: 0.01) {
                drag(slider, to: slider.minValue + fraction * (slider.maxValue - slider.minValue))
                if let value = stored() {
                    XCTAssertTrue(grid.contains(value), "\(value) is not a tick of \(grid)")
                    written.insert(value)
                }
            }
            XCTAssertEqual(written, Set(grid), "every tick can be reached")
        }
    }

    // MARK: - What the controls show

    func testManagedTheControlsShowYourValues() throws {
        manage(mode: .smartShift, sensitivity: 30, scrollForce: 80)
        Options.shared.logiMouse = LogiMouseSettings(pointerDPI: 1600, hapticsOn: true, hapticStrength: 40, pressForce: 6000)
        let controller = makeController([Fixtures.mxMaster4()])

        XCTAssertTrue(controller.managedRow.isOn)
        XCTAssertEqual(controller.pointerSpeedSlider.doubleValue, Double(try XCTUnwrap(MousePaneModel.pointerLadder.firstIndex(of: 1600))))
        XCTAssertEqual(controller.wheelModeControl.selectedSegment, 0)
        XCTAssertEqual(controller.sensitivitySlider.doubleValue, 30)
        XCTAssertEqual(controller.firmnessSlider.doubleValue, 80)
        XCTAssertTrue(controller.hapticsRow.isOn)
        XCTAssertEqual(controller.strengthSlider.doubleValue, 40)
        XCTAssertEqual(controller.pressForceSlider.doubleValue, 6187.5, "6000 shows on the nearest tick")
        XCTAssertEqual(controller.pressForceRow.valueText, MouseText.percent(68))
        for row in settingRows(controller) {
            XCTAssertTrue(row.isEnabled, row.title)
        }
    }

    func testNotManagedTheRowsShowTheMouseOwnValuesGreyedOut() {
        manage(false, mode: .freeSpin, sensitivity: 30, scrollForce: 80)
        Options.shared.logiMouse = LogiMouseSettings(pointerDPI: 1600, hapticsOn: true, hapticStrength: 40, pressForce: 6000)
        let controller = makeController([Fixtures.mxMaster4()])

        XCTAssertFalse(controller.managedRow.isOn)
        XCTAssertTrue(controller.managedRow.isEnabled)
        XCTAssertTrue(controller.managedSwitch.isEnabled)
        XCTAssertEqual(controller.pointerSpeedRow.valueText, "1000 DPI")
        XCTAssertEqual(controller.wheelModeControl.selectedSegment, 0, "the mouse is in SmartShift")
        XCTAssertFalse(controller.sensitivityRow.isHidden)
        XCTAssertEqual(controller.sensitivitySlider.doubleValue, 50)
        XCTAssertEqual(controller.firmnessSlider.doubleValue, 100)
        XCTAssertFalse(controller.hapticsRow.isOn)
        XCTAssertEqual(controller.strengthSlider.doubleValue, 100)
        XCTAssertEqual(controller.pressForceSlider.doubleValue, 4134)

        for row in settingRows(controller).dropFirst() {
            XCTAssertFalse(row.isHidden, row.title)
            XCTAssertFalse(row.isEnabled, row.title)
            XCTAssertEqual(row.titleLabel.textColor, PreferencesGroupedForm.titleColor(enabled: false), row.title)
        }
        XCTAssertFalse(controller.pointerSpeedSlider.isEnabled)
        XCTAssertFalse(controller.wheelModeControl.isEnabled)
        XCTAssertFalse(controller.hapticsSwitch.isEnabled)
        XCTAssertFalse(controller.pressForceSlider.isEnabled)
    }

    func testAValueTheMouseHasNotReportedFallsBackOnYoursOrTheDefault() {
        let controller = makeController([Fixtures.mxMaster4(dpi: nil, hapticsOn: nil, strength: nil, pressForce: nil)])
        XCTAssertEqual(controller.pointerSpeedRow.valueText, "1000 DPI", "the mouse's default")
        XCTAssertFalse(controller.hapticsRow.isOn)
        XCTAssertEqual(controller.pressForceRow.valueText, MouseText.percent(38), "the mouse's default")
        XCTAssertEqual(controller.pressForceSlider.doubleValue, 5503, "on the tick nearest the default")
    }

    // MARK: - Which rows each mouse gets

    func testMXMaster4GetsEveryRow() {
        manage()
        let controller = makeController([Fixtures.mxMaster4()])

        XCTAssertTrue(controller.noMouseSection.isHidden)
        for section in [controller.managedSection!, controller.pointerSection!, controller.wheelSection!, controller.hapticsSection!] {
            XCTAssertFalse(section.isHidden)
        }
        for row in settingRows(controller) {
            XCTAssertFalse(row.isHidden, row.title)
        }
        XCTAssertEqual(controller.headerView.nameLabel.stringValue, "MX Master 4")
        XCTAssertEqual(controller.headerView.statusLabel.stringValue, text("mouse-header-connected"))
        XCTAssertEqual(controller.headerView.batteryLabel.stringValue, MouseText.percent(75))
        XCTAssertEqual(controller.headerView.artwork.alphaValue, 1)
    }

    func testMXMaster3SHasNoHapticsAndNoClickFirmness() {
        manage()
        let controller = makeController([Fixtures.mxMaster3S()])

        XCTAssertTrue(controller.hapticsSection.isHidden)
        XCTAssertTrue(controller.firmnessRow.isHidden)
        XCTAssertFalse(controller.pointerSection.isHidden)
        XCTAssertFalse(controller.wheelSection.isHidden)
        XCTAssertFalse(controller.wheelModeRow.isHidden)
        XCTAssertFalse(controller.sensitivityRow.isHidden)
        XCTAssertEqual(controller.wheelSection.box.visibleRows, [controller.wheelModeRow, controller.sensitivityRow])
        XCTAssertEqual(controller.headerView.nameLabel.stringValue, "MX Master 3S")
        XCTAssertEqual(controller.headerView.batteryLabel.stringValue, MouseText.percent(90))
    }

    func testMXMaster3ShowsItsCoarseBatteryAsAnEstimate() {
        let controller = makeController([Fixtures.mxMaster3()])

        XCTAssertTrue(controller.hapticsSection.isHidden)
        XCTAssertTrue(controller.firmnessRow.isHidden)
        XCTAssertFalse(controller.pointerSpeedRow.isHidden)
        XCTAssertEqual(controller.pointerSpeedSlider.maxValue, 9, "ten rungs up to 4000 DPI")
        XCTAssertEqual(controller.pointerSpeedSlider.numberOfTickMarks, 10)
        XCTAssertEqual(
            controller.headerView.batteryLabel.stringValue,
            String(format: text("mouse-battery-about"), MouseText.percent(50))
        )
    }

    func testWithoutAMouseOnlyAnExplanationIsLeft() {
        let controller = makeController()

        XCTAssertEqual(controller.headerView.nameLabel.stringValue, text("mouse-header-no-mouse"))
        XCTAssertTrue(controller.headerView.statusLabel.isHidden)
        XCTAssertEqual(controller.headerView.artwork.alphaValue, MouseHeaderView.dimmedAlpha)
        XCTAssertNil(controller.headerView.content.battery)
        XCTAssertFalse(controller.noMouseSection.isHidden)
        for section in [controller.managedSection!, controller.pointerSection!, controller.wheelSection!, controller.hapticsSection!] {
            XCTAssertTrue(section.isHidden)
        }
        XCTAssertFalse(controller.footer.isHidden)
        XCTAssertTrue(controller.diagnosticsButton.isEnabled)
        // Nothing to point at.
        controller.rowHoverChanged(.wheel, inside: true)
        XCTAssertNil(controller.headerView.emphasis)
    }

    func testTheTabFollowsTheMiceComingAndGoing() {
        let controller = makeController()
        let emptyHeight = controller.view.frame.height

        devices = [Fixtures.mxMaster4()]
        NotificationCenter.default.post(name: LogiCenter.mouseStateChanged, object: nil)
        XCTAssertFalse(controller.hapticsSection.isHidden)
        XCTAssertGreaterThan(controller.view.frame.height, emptyHeight)
        XCTAssertEqual(controller.view.frame.size, controller.view.fittingSize)

        devices = []
        NotificationCenter.default.post(name: LogiCenter.mouseStateChanged, object: nil)
        XCTAssertFalse(controller.noMouseSection.isHidden)
        XCTAssertTrue(controller.managedSection.isHidden)
        XCTAssertEqual(controller.view.frame.height, emptyHeight)
    }

    func testSensitivityOnlyShowsInSmartShiftMode() {
        manage(mode: .ratchet)
        let controller = makeController([Fixtures.mxMaster4(mode: .ratchet, sensitivity: nil)])
        XCTAssertTrue(controller.sensitivityRow.isHidden)

        controller.wheelModeControl.selectedSegment = 0
        send(controller.wheelModeControl)
        XCTAssertFalse(controller.sensitivityRow.isHidden)

        controller.wheelModeControl.selectedSegment = 2
        send(controller.wheelModeControl)
        XCTAssertTrue(controller.sensitivityRow.isHidden)
        XCTAssertFalse(controller.firmnessRow.isHidden)
    }

    func testStrengthIsGreyedOutWhileHapticsAreOff() {
        manage()
        let controller = makeController([Fixtures.mxMaster4()])
        XCTAssertFalse(controller.strengthRow.isEnabled)
        XCTAssertTrue(controller.pressForceRow.isEnabled, "the press force does not depend on the pulses")

        set(controller.hapticsSwitch, true)
        XCTAssertTrue(controller.strengthRow.isEnabled)
        XCTAssertTrue(controller.strengthSlider.isEnabled)
    }

    func testThumbPanelPressNeedsAButtonThatCanChangeAndItsRange() {
        manage()
        let fixed = makeController([Fixtures.mxMaster4(pressChangeable: false)])
        XCTAssertTrue(fixed.pressForceRow.isHidden)
        XCTAssertFalse(fixed.hapticsSection.isHidden)

        let unread = makeController([Fixtures.mxMaster4(pressRange: nil)])
        XCTAssertTrue(unread.pressForceRow.isHidden)
    }

    func testAMouseWithoutItsDPIListYetHasNoPointerSpeed() {
        let controller = makeController([Fixtures.mxMaster4(dpiChoices: [])])
        XCTAssertTrue(controller.pointerSection.isHidden)
    }

    func testSeveralMiceShareOneSetOfChoices() {
        let model = MousePaneModel(
            devices: [Fixtures.mxMaster3S(), Fixtures.mxMaster4()],
            settings: .default, wheel: .default
        )
        // The mouse with the most settings is the one in the header.
        XCTAssertEqual(model.header.title, "MX Master 4")
        XCTAssertEqual(model.header.subtitle, String(format: text("mouse-header-connected-several"), 2))
        XCTAssertNotNil(model.haptics)
        XCTAssertNotNil(model.firmness)
    }

    // MARK: - "On the mouse"

    func testNoLineUnderAValueYouNeverSet() {
        manage()
        let controller = makeController([Fixtures.mxMaster4(dpi: 1200, hapticsOn: true, strength: 30)])
        for row in [controller.pointerSpeedRow!, controller.hapticsRow!, controller.strengthRow!, controller.pressForceRow!] {
            XCTAssertFalse(row.explanation?.contains("\n") ?? false, row.title)
        }
        XCTAssertEqual(controller.pointerSpeedRow.valueText, "1200 DPI")
    }

    func testALineWhereYourValueDiffersFromTheMouse() {
        manage(mode: .ratchet, sensitivity: 50, scrollForce: 80)
        Options.shared.logiMouse = LogiMouseSettings(pointerDPI: 1600, hapticsOn: true, hapticStrength: 40, pressForce: 5503)
        let controller = makeController([Fixtures.mxMaster4()])

        let expected: [(PreferencesGroupRow, String, String)] = [
            (controller.pointerSpeedRow, "mouse-pointer-speed-hint", "1000 DPI"),
            (controller.wheelModeRow, "mouse-wheel-mode-ratchet-hint", MouseText.modeName(.smartShift)),
            (controller.firmnessRow, "mouse-wheel-force-hint", MouseText.percent(100)),
            (controller.hapticsRow, "mouse-haptics-hint", MouseText.onOff(false)),
            (controller.strengthRow, "mouse-haptics-strength-hint", MouseText.percent(100)),
            (controller.pressForceRow, "mouse-press-force-hint", MouseText.percent(0)),
        ]
        for (row, hint, value) in expected {
            XCTAssertEqual(row.explanation, text(hint) + "\n" + onTheMouse(value), row.title)
        }
    }

    func testTheLineGoesOnceTheMouseHasYourValue() {
        manage()
        Options.shared.logiMouse.pointerDPI = 1600
        let controller = makeController([Fixtures.mxMaster4()])
        XCTAssertEqual(controller.pointerSpeedRow.explanation, text("mouse-pointer-speed-hint") + "\n" + onTheMouse("1000 DPI"))

        devices = [Fixtures.mxMaster4(dpi: 1600)]
        NotificationCenter.default.post(name: LogiCenter.mouseStateChanged, object: nil)
        XCTAssertEqual(controller.pointerSpeedRow.explanation, text("mouse-pointer-speed-hint"))
    }

    func testNoLinesWhileScrollioDoesNotManageTheMouse() {
        manage(false, mode: .ratchet, scrollForce: 20)
        Options.shared.logiMouse = LogiMouseSettings(pointerDPI: 1600, hapticsOn: true, hapticStrength: 40, pressForce: 5503)
        let controller = makeController([Fixtures.mxMaster4()])
        for row in settingRows(controller) where !row.isHidden {
            XCTAssertFalse(row.explanation?.contains(onTheMouse("")) ?? false, row.title)
        }
    }

    func testSensitivityAllowsForTheCoarseStepsOfTheMouse() {
        manage(sensitivity: 72)
        let close = makeController([Fixtures.mxMaster4(sensitivity: 75)])
        XCTAssertEqual(close.sensitivityRow.explanation, text("mouse-wheel-sensitivity-hint"))

        manage(sensitivity: 60)
        let far = makeController([Fixtures.mxMaster4(sensitivity: 75)])
        XCTAssertEqual(far.sensitivityRow.explanation, text("mouse-wheel-sensitivity-hint") + "\n" + onTheMouse(MouseText.percent(75)))

        // In another mode the mouse keeps an old sensitivity: only the mode is reported.
        manage(sensitivity: 60)
        let freeSpin = makeController([Fixtures.mxMaster4(mode: .freeSpin, sensitivity: 75)])
        XCTAssertEqual(freeSpin.sensitivityRow.explanation, text("mouse-wheel-sensitivity-hint"))
        XCTAssertEqual(freeSpin.wheelModeRow.explanation, MouseText.modeHint(.smartShift) + "\n" + onTheMouse(MouseText.modeName(.freeSpin)))
    }

    func testTheLineWaitsWhileTheMouseTakesANewValue() throws {
        manage(scrollForce: 80)
        let controller = makeController([Fixtures.mxMaster4()])
        controller.readbackSettleTime = 60
        XCTAssertEqual(controller.firmnessRow.explanation, text("mouse-wheel-force-hint") + "\n" + onTheMouse(MouseText.percent(100)))

        let index = try XCTUnwrap(Fixtures.dpiChoices.firstIndex(of: 1600))
        drag(controller.pointerSpeedSlider, to: Double(index))
        XCTAssertEqual(controller.pointerSpeedRow.explanation, text("mouse-pointer-speed-hint"), "not yet")
        // The other settings keep theirs.
        XCTAssertEqual(controller.firmnessRow.explanation, text("mouse-wheel-force-hint") + "\n" + onTheMouse(MouseText.percent(100)))

        controller.readbackSettleTime = 0
        controller.syncControls()
        XCTAssertEqual(controller.pointerSpeedRow.explanation, text("mouse-pointer-speed-hint") + "\n" + onTheMouse("1000 DPI"))
    }

    // MARK: - Turning management on

    func testTurningManagementOnStartsFromTheWheelOfTheMouse() {
        Options.shared.logiMouse.pointerDPI = 1600
        let controller = makeController([Fixtures.mxMaster4(mode: .ratchet, sensitivity: nil, scrollForce: 100)])
        XCTAssertEqual(Options.shared.logiWheel.scrollForce, 50, "the stored default")

        set(controller.managedSwitch, true)
        XCTAssertEqual(
            Options.shared.logiWheel,
            LogiWheelSettings(managedByMos: true, mode: .ratchet, smartShiftSensitivity: 50, scrollForce: 100)
        )
        XCTAssertEqual(controller.firmnessSlider.doubleValue, 100, "nothing on the mouse changes")
        XCTAssertEqual(Options.shared.logiMouse, LogiMouseSettings(pointerDPI: 1600), "the basics you set stay")

        // Off and on again while managed values exist: on again starts from the mouse again.
        Options.shared.logiWheel.scrollForce = 30
        set(controller.managedSwitch, false)
        XCTAssertEqual(Options.shared.logiWheel.scrollForce, 30)
        set(controller.managedSwitch, true)
        XCTAssertEqual(Options.shared.logiWheel.scrollForce, 100)
    }

    // MARK: - Sample pulse and dragging

    func testStrengthPlaysOneSamplePulseWhenLetGo() {
        manage()
        Options.shared.logiMouse.hapticsOn = true
        let controller = makeController([Fixtures.mxMaster4(hapticsOn: true)])

        tracking = true
        drag(controller.strengthSlider, to: 60)
        drag(controller.strengthSlider, to: 75)
        XCTAssertEqual(sampleCount, 0, "not while it is dragged")
        XCTAssertEqual(Options.shared.logiMouse.hapticStrength, 80, "stored as it moves, tick by tick")

        tracking = false
        drag(controller.strengthSlider, to: 40)
        XCTAssertEqual(sampleCount, 1)
        XCTAssertEqual(Options.shared.logiMouse.hapticStrength, 40)

        // An arrow key is a move that is let go at once: one pulse each.
        let strength = controller.strengthSlider as! PreferencesSlider
        XCTAssertTrue(strength.moveKnob(by: 1))
        XCTAssertEqual(Options.shared.logiMouse.hapticStrength, 60)
        XCTAssertEqual(sampleCount, 2)

        // Other sliders play nothing.
        drag(controller.pressForceSlider, to: 5000)
        drag(controller.firmnessSlider, to: 40)
        XCTAssertEqual(sampleCount, 2)
    }

    func testAMouseUpdateDuringADragLeavesTheKnobAlone() {
        manage()
        let controller = makeController([Fixtures.mxMaster4()])

        tracking = true
        drag(controller.sensitivitySlider, to: 80)
        controller.pressForceSlider.doubleValue = 6187.5
        devices = [Fixtures.mxMaster4(dpi: 1200, pressForce: 4500, sensitivity: 40)]
        NotificationCenter.default.post(name: LogiCenter.mouseStateChanged, object: nil)
        XCTAssertEqual(controller.sensitivitySlider.doubleValue, 80)
        XCTAssertEqual(controller.pressForceSlider.doubleValue, 6187.5)

        tracking = false
        NotificationCenter.default.post(name: LogiCenter.mouseStateChanged, object: nil)
        XCTAssertEqual(controller.sensitivitySlider.doubleValue, 80, "your value")
        XCTAssertEqual(controller.pressForceSlider.doubleValue, 4818.5, "the tick nearest the mouse's 4500: you never set one")
        XCTAssertEqual(controller.pressForceRow.valueText, MouseText.percent(MousePaneModel.share(of: 4500, in: 4134...6872)))
        XCTAssertEqual(controller.pointerSpeedRow.valueText, "1200 DPI")
    }

    // MARK: - The header lights up the part

    func testEachRowLightsUpItsPartOfTheMouse() {
        let controller = makeController([Fixtures.mxMaster4()])
        let expected: [(PreferencesGroupRow, MousePart)] = [
            (controller.pointerSpeedRow, .body),
            (controller.wheelModeRow, .wheel), (controller.sensitivityRow, .wheel), (controller.firmnessRow, .wheel),
            (controller.hapticsRow, .thumbPanel), (controller.strengthRow, .thumbPanel), (controller.pressForceRow, .thumbPanel),
        ]
        XCTAssertEqual(controller.rowParts.map { $0.row }, expected.map { $0.0 })
        XCTAssertEqual(controller.rowParts.map { $0.part }, expected.map { $0.1 })
        for (row, part) in expected {
            XCTAssertEqual(row.trackingAreas.count, 1, row.title)
            let area = row.trackingAreas[0]
            XCTAssertTrue(area.owner === controller)
            XCTAssertTrue(area.options.contains(.mouseEnteredAndExited))
            XCTAssertTrue(area.options.contains(.inVisibleRect))
            XCTAssertEqual(area.userInfo?["mousePart"] as? Int, part.rawValue)
        }
        XCTAssertTrue(controller.managedRow.trackingAreas.isEmpty, "about the whole tab, not a part")
    }

    func testHoverAndFocusLightUpThePart() {
        let controller = makeController([Fixtures.mxMaster4()])
        let header = controller.headerView!
        XCTAssertNil(header.emphasis)

        for part in MousePart.allCases {
            controller.rowHoverChanged(part, inside: true)
            XCTAssertEqual(header.emphasis, part)
            XCTAssertEqual(header.artwork.emphasis, part)
            for candidate in MousePart.allCases {
                XCTAssertEqual(header.artwork.highlights[candidate]?.alphaValue, candidate == part ? 1 : 0)
            }
            controller.rowHoverChanged(part, inside: false)
            XCTAssertNil(header.emphasis)
        }

        let focused: [(NSView, MousePart?)] = [
            (controller.pointerSpeedSlider, .body), (controller.wheelModeControl, .wheel),
            (controller.sensitivitySlider, .wheel), (controller.firmnessSlider, .wheel),
            (controller.hapticsSwitch, .thumbPanel), (controller.strengthSlider, .thumbPanel),
            (controller.pressForceSlider, .thumbPanel), (controller.managedSwitch, nil),
            (controller.diagnosticsButton, nil),
        ]
        for (control, part) in focused {
            controller.firstResponderDidChange(control)
            XCTAssertEqual(header.emphasis, part, "\(control)")
        }
        controller.firstResponderDidChange(nil)
        XCTAssertNil(header.emphasis)

        // The pointer wins over the focus; leaving one row after entering the next keeps the next.
        controller.firstResponderDidChange(controller.pointerSpeedSlider)
        controller.rowHoverChanged(.wheel, inside: true)
        controller.rowHoverChanged(.thumbPanel, inside: true)
        controller.rowHoverChanged(.wheel, inside: false)
        XCTAssertEqual(header.emphasis, .thumbPanel)
        controller.rowHoverChanged(.thumbPanel, inside: false)
        XCTAssertEqual(header.emphasis, .body)

        controller.viewDidDisappear()
        XCTAssertNil(header.emphasis)
    }

    func testTheFocusIsFollowedThroughTheWindow() {
        manage()
        let controller = makeController([Fixtures.mxMaster4()])
        // A window that is never ordered in: nothing shows and nothing takes the focus.
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: controller.view.frame.size),
            styleMask: [.titled], backing: .buffered, defer: true
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = controller.view
        controller.viewWillAppear()

        XCTAssertTrue(window.makeFirstResponder(controller.firmnessSlider))
        XCTAssertEqual(controller.focusedPart, .wheel)
        XCTAssertTrue(window.makeFirstResponder(nil))
        XCTAssertNil(controller.focusedPart)
        controller.viewDidDisappear()
    }

    // MARK: - Header

    func testBatteryTexts() {
        let fixtures = MouseDeviceFixtures.self
        let charging = MousePaneModel.battery(fixtures.battery(75, charging: .charging))
        XCTAssertEqual(charging?.text, MouseText.percent(75))
        XCTAssertEqual(charging?.symbolName, "battery.100percent.bolt")
        XCTAssertEqual(charging?.isCharging, true)
        XCTAssertEqual(charging?.accessibilityLabel, String(format: text("mouse-battery-accessibility-charging"), MouseText.percent(75)))

        let full = MousePaneModel.battery(fixtures.battery(75))
        XCTAssertEqual(full?.symbolName, "battery.75percent")
        XCTAssertEqual(full?.isLow, false)
        XCTAssertEqual(full?.accessibilityLabel, String(format: text("mouse-battery-accessibility"), MouseText.percent(75)))

        XCTAssertEqual(MousePaneModel.battery(fixtures.battery(8))?.isLow, true)
        XCTAssertEqual(MousePaneModel.battery(fixtures.battery(8))?.symbolName, "battery.0percent")
        XCTAssertEqual(MousePaneModel.battery(fixtures.battery(nil, level: .low))?.text, text("mouse-battery-low"))
        XCTAssertEqual(MousePaneModel.battery(fixtures.battery(nil, level: .critical))?.isLow, true)
        XCTAssertNil(MousePaneModel.battery(fixtures.battery(nil, level: .unknown)))
        XCTAssertEqual(
            MousePaneModel.battery(fixtures.battery(40, charging: .problem))?.text,
            String(format: text("mouse-battery-not-charging"), MouseText.percent(40))
        )
    }

    func testHeaderTextsAndBatteryIcon() {
        let controller = makeController([Fixtures.mxMaster4(battery: MouseDeviceFixtures.battery(75, charging: .charging))])
        let header = controller.headerView!
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(header.identifier, MousePreferencesViewController.Identifier.header)
        XCTAssertEqual(header.frame.height, MouseHeaderView.preferredHeight)
        XCTAssertFalse(header.batteryLabel.isHidden)
        XCTAssertNotNil(header.batteryIcon.image)
        XCTAssertEqual(header.batteryLabel.accessibilityLabel(), String(format: text("mouse-battery-accessibility-charging"), MouseText.percent(75)))

        devices = [Fixtures.mxMaster4(battery: nil)]
        controller.reloadDevices()
        XCTAssertNil(header.batteryIcon.image)
        XCTAssertTrue(header.batteryLabel.superview?.isHidden ?? false)
    }

    // MARK: - Pane

    func testPaneIsAsWideAsScrollingAndFitsItsRows() {
        let controller = makeController([Fixtures.mxMaster4()])
        XCTAssertEqual(controller.title, text("mouse-tab-title"))
        XCTAssertEqual(controller.view.frame.width, MousePreferencesViewController.paneWidth)
        XCTAssertEqual(MousePreferencesViewController.paneWidth, PreferencesScrollingViewController.paneWidth)
        XCTAssertEqual(controller.view.frame.size, controller.view.fittingSize)
    }

    func testRowsSitInTheirBoxes() {
        manage()
        let controller = makeController([Fixtures.mxMaster4()])
        controller.view.layoutSubtreeIfNeeded()
        let inset = PreferencesGroupedForm.rowHorizontalInset
        let margin = PreferencesGroupedForm.margin
        let boxRight = MousePreferencesViewController.paneWidth - margin

        // The header and the boxes span the pane between its margins.
        for view in [controller.headerView!, controller.managedSection.box, controller.pointerSection.box,
                     controller.wheelSection.box, controller.hapticsSection.box] as [NSView] {
            let box = frame(of: view, in: controller)
            XCTAssertEqual(box.minX, margin, accuracy: 0.5)
            XCTAssertEqual(box.maxX, boxRight, accuracy: 0.5)
        }
        for row in settingRows(controller) {
            XCTAssertEqual(frame(of: row.titleLabel, in: controller).minX, margin + inset, accuracy: 0.5, row.title)
        }
        // The switches and the values end at the box's inset; the sliders form one column.
        let rightEdges: [NSView] = [controller.managedSwitch, controller.hapticsSwitch, controller.wheelModeControl]
            + sliderRows(controller).compactMap(\.valueLabel)
        for view in rightEdges {
            XCTAssertEqual(frame(of: view, in: controller).maxX, boxRight - inset, accuracy: 1, "\(view)")
        }
        let sliders = sliderRows(controller).map { frame(of: $0.slider, in: controller) }
        XCTAssertEqual(Set(sliders.map { $0.minX.rounded() }).count, 1)
        XCTAssertEqual(Set(sliders.map { $0.width.rounded() }).count, 1)
        // Each control sits on the line of its title.
        var lines: [(NSView, PreferencesGroupRow)] = [(controller.managedSwitch, controller.managedRow),
                                                      (controller.hapticsSwitch, controller.hapticsRow)]
        lines += sliderRows(controller).map { ($0.slider as NSView, $0 as PreferencesGroupRow) }
        for (control, row) in lines {
            XCTAssertEqual(frame(of: control, in: controller).midY, frame(of: row.titleLabel, in: controller).midY, accuracy: 1, row.title)
        }
        // The three modes fill the box under the text of "Wheel mode".
        let modes = frame(of: controller.wheelModeControl, in: controller)
        XCTAssertEqual(modes.minX, margin + inset, accuracy: 1)
        for toggle in [controller.managedSwitch!, controller.hapticsSwitch!] {
            XCTAssertEqual(toggle.controlSize, PreferencesGroupedForm.switchControlSize)
        }
        // "8000 DPI" fits the value column.
        controller.pointerSpeedRow.valueText = "8000 DPI"
        let value = controller.pointerSpeedRow.valueLabel!
        XCTAssertLessThanOrEqual(value.intrinsicContentSize.width, MousePreferencesViewController.sliderValueWidth)
    }

    func testExplanationsAreShortLinesInTheHintStyle() {
        manage()
        let controller = makeController([Fixtures.mxMaster4()])
        controller.view.layoutSubtreeIfNeeded()
        let oneLine = PreferencesForm.makeHint("X").fittingSize.height
        let lines: [(PreferencesGroupRow, Int)] = [
            (controller.managedRow, 2), (controller.pointerSpeedRow, 1), (controller.wheelModeRow, 1),
            (controller.sensitivityRow, 1), (controller.firmnessRow, 1), (controller.hapticsRow, 1),
            (controller.strengthRow, 1), (controller.pressForceRow, 2),
        ]
        for (row, count) in lines {
            XCTAssertEqual(row.explanationLabel.font?.pointSize, PreferencesForm.hintFontSize, row.title)
            XCTAssertEqual(row.explanationLabel.frame.height, CGFloat(count) * oneLine, accuracy: 0.5, row.title)
        }
        // No protocol words in the tab: "DPI" only as the unit of a value.
        let texts = allSubviews(of: controller.view).compactMap { ($0 as? NSTextField)?.stringValue }
        for text in texts where text != controller.pointerSpeedRow.valueText {
            XCTAssertFalse(text.contains("HID++"), text)
            XCTAssertFalse(text.contains("DPI"), text)
        }
    }

    func testPickingAModeNeverChangesTheHeightOfItsRow() {
        manage(mode: .ratchet)
        let controller = makeController([Fixtures.mxMaster4(mode: .ratchet, sensitivity: nil)])
        // Without the "On the mouse" line, which waits while the mouse takes the new mode.
        controller.readbackSettleTime = 60
        let height = controller.wheelModeRow.fittingSize.height
        for index in [1, 2] {
            controller.wheelModeControl.selectedSegment = index
            send(controller.wheelModeControl)
            XCTAssertEqual(controller.wheelModeRow.fittingSize.height, height)
        }
    }

    func testAppearingAsksTheMiceAgain() {
        let controller = makeController()
        XCTAssertEqual(refreshCount, 0)
        controller.viewWillAppear()
        XCTAssertEqual(refreshCount, 1)
        controller.viewDidDisappear()
    }

    func testDiagnosticsButtonOpensThePanel() {
        let controller = makeController()
        XCTAssertEqual(controller.diagnosticsButton.title, text("mouse-diagnostics-button"))
        send(controller.diagnosticsButton)
        XCTAssertEqual(diagnosticsCount, 1)
    }

    func testModeSegmentsFollowTheContractOrder() {
        XCTAssertEqual(MouseText.modes, [.smartShift, .ratchet, .freeSpin])
        XCTAssertEqual(Set(MouseText.modes), Set(LogiWheelMode.allCases))
    }

    func testPaneHelpers() {
        XCTAssertEqual(MousePaneModel.nearest(1020, in: [400, 800, 1000, 1600]), 1000)
        XCTAssertEqual(MousePaneModel.nearest(1300, in: [400, 800, 1000, 1600]), 1000, "the lower one on a tie")
        XCTAssertEqual(MousePaneModel.share(of: 4134, in: 4134...6872), 0)
        XCTAssertEqual(MousePaneModel.share(of: 6872, in: 4134...6872), 100)
        XCTAssertEqual(MousePaneModel.share(of: 5167, in: 4134...6872), 38)
        XCTAssertEqual(MouseText.dpi(1000), "1000 DPI")
        XCTAssertEqual(MouseSetting.allCases.map(\.part), [.body, .wheel, .wheel, .wheel, .thumbPanel, .thumbPanel, .thumbPanel])
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

    func testMouseTabSitsAfterGestures() {
        let (windowController, tabs) = loadPreferencesWindow()
        defer { windowController.close() }

        let identifiers = tabs.tabViewItems.compactMap { $0.identifier as? String }
        XCTAssertEqual(identifiers, ["general", "scrolling", "buttons", "gestures", "mouse", "application", "about"])
        let mouseItem = tabs.tabViewItems[4]
        XCTAssertTrue(mouseItem.viewController is MousePreferencesViewController)
        XCTAssertNotNil(mouseItem.image)
        XCTAssertFalse(mouseItem.label.isEmpty)
        XCTAssertNotEqual(mouseItem.label, "mouse-tab-title", "the tab label must be localized")
        XCTAssertEqual(tabs.selectedTabViewItemIndex, 0)
    }

    func testToolbarKeepsEveryTabWithoutFlexibleSpaces() {
        let (windowController, tabs) = loadPreferencesWindow()
        defer { windowController.close() }

        tabs.removeToolbarFlexibleSpaces()

        let toolbarIdentifiers = windowController.window?.toolbar?.items.map { $0.itemIdentifier.rawValue } ?? []
        XCTAssertEqual(toolbarIdentifiers, ["general", "scrolling", "buttons", "gestures", "mouse", "application", "about"])
    }
}

/// Renders the tab off screen for a look at it, light and dark: MX Master 4 managed and not,
/// with "On the mouse" lines and each part lit up, MX Master 3S and no mouse. Off screen the
/// window's material draws a flat grey and vibrant text is not blended, so text looks a
/// little dimmer than on screen. Only runs when asked to:
/// `TEST_RUNNER_SCROLLIO_SHOTS_DIR=<folder> xcodebuild … test -only-testing:MosTests/MousePreferencesRenderTests`.
final class MousePreferencesRenderTests: XCTestCase {

    private var savedMouse = LogiMouseSettings.default
    private var savedWheel = LogiWheelSettings.default

    override func setUp() {
        super.setUp()
        savedMouse = Options.shared.logiMouse
        savedWheel = Options.shared.logiWheel
    }

    override func tearDown() {
        Options.shared.logiMouse = savedMouse
        Options.shared.logiWheel = savedWheel
        super.tearDown()
    }

    func testRenderTheTab() throws {
        guard let folder = ProcessInfo.processInfo.environment["SCROLLIO_SHOTS_DIR"], !folder.isEmpty else {
            throw XCTSkip("set TEST_RUNNER_SCROLLIO_SHOTS_DIR to render the Mouse tab")
        }
        let directory = URL(fileURLWithPath: folder, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        func tab(_ devices: [LogiMouseDeviceState]) -> MousePreferencesViewController {
            let controller = MousePreferencesViewController()
            controller.deviceSource = MouseDeviceSource(deviceStates: { devices }, refresh: {}, showDiagnostics: {})
            controller.isTrackingMouse = { false }
            controller.readbackSettleTime = 0
            _ = controller.view
            controller.reloadDevices()
            return controller
        }
        let master4 = MouseDeviceFixtures.mxMaster4()

        // The owner's mouse as it reports now, Scrollio managing it with nothing changed yet.
        Options.shared.logiMouse = .default
        Options.shared.logiWheel = LogiWheelSettings(managedByMos: true, mode: .smartShift, smartShiftSensitivity: 50, scrollForce: 100)
        let managed = tab([master4])
        try render(managed.view, name: "mx-master-4-managed", into: directory)
        for part in MousePart.allCases {
            managed.rowHoverChanged(part, inside: true)
            try render(managed.view, name: "mx-master-4-lit-\(part)", into: directory)
            managed.rowHoverChanged(part, inside: false)
        }

        // Settings that differ from the mouse.
        Options.shared.logiMouse = LogiMouseSettings(pointerDPI: 1600, hapticsOn: true, hapticStrength: 60, pressForce: 5167)
        Options.shared.logiWheel.scrollForce = 70
        try render(tab([master4]).view, name: "mx-master-4-differs", into: directory)

        Options.shared.logiMouse = .default
        Options.shared.logiWheel = .default
        try render(tab([master4]).view, name: "mx-master-4-not-managed", into: directory)
        try render(tab([MouseDeviceFixtures.mxMaster3S()]).view, name: "mx-master-3s", into: directory)
        try render(tab([]).view, name: "no-mouse", into: directory)
    }

    /// Writes `<name>-light.png` and `<name>-dark.png`, as PreferencesScrollingRenderTests does.
    private func render(_ view: NSView, name: String, into directory: URL) throws {
        let host = NSView(frame: view.frame)
        host.addSubview(view)
        defer { view.removeFromSuperview() }
        for (suffix, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            host.appearance = appearance
            view.layoutSubtreeIfNeeded()
            view.display()
            let bounds = view.bounds
            let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: bounds))
            view.cacheDisplay(in: bounds, to: rep)

            let image = NSImage(size: bounds.size)
            image.addRepresentation(try XCTUnwrap(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * 2), pixelsHigh: Int(bounds.height * 2),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            )))
            let canvas = try XCTUnwrap(image.representations.first as? NSBitmapImageRep)
            canvas.size = bounds.size
            let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: canvas))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            appearance.performAsCurrentDrawingAppearance {
                NSColor.windowBackgroundColor.setFill()
                bounds.fill()
            }
            rep.draw(in: bounds)
            NSGraphicsContext.restoreGraphicsState()

            let png = try XCTUnwrap(canvas.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent("\(name)-\(suffix).png"))
        }
    }
}
