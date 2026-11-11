//
//  MousePreferencesTests.swift
//  MosTests
//
//  The Mouse tab: every control reads and writes the right option, which rows MX Master 4,
//  MX Master 3S, MX Master 3 and no Logitech mouse get, what is greyed out while Scrollio
//  does not manage the mouse, the "On the mouse" lines, the sample pulse of the strength
//  slider, the header lighting up the part of the hovered or focused row, the "Pointer
//  (macOS)" box for any mouse, and the tab's place in the toolbar. The mice and the macOS
//  settings are fixtures: nothing is read from or written to a real mouse or the real macOS
//  settings, and nothing is shown on screen.
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
            mode: .init(onMouse: mode, setByYou: nil),
            smartShiftSensitivity: .init(onMouse: sensitivity, setByYou: nil),
            scrollForce: .init(onMouse: scrollForce, setByYou: nil)
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

/// The user's macOS pointer settings as a test double: what macOS "has", whether it takes a
/// new value, and every read and write.
final class FakeMacPointer {
    var trackingSpeed: Double? = 0.6875
    var pointerAcceleration: Bool? = true
    /// false: macOS refuses every write and keeps its values.
    var accepts = true
    private(set) var reads = 0
    private(set) var trackingSpeedWrites: [Double] = []
    private(set) var accelerationWrites: [Bool] = []

    var writes: Int {
        return trackingSpeedWrites.count + accelerationWrites.count
    }

    var settings: MacPointerSettings {
        return MacPointerSettings(
            readTrackingSpeed: { [unowned self] in
                self.reads += 1
                return self.trackingSpeed
            },
            writeTrackingSpeed: { [unowned self] value in
                self.trackingSpeedWrites.append(value)
                if self.accepts { self.trackingSpeed = value }
                return self.accepts
            },
            readPointerAcceleration: { [unowned self] in self.pointerAcceleration },
            writePointerAcceleration: { [unowned self] on in
                self.accelerationWrites.append(on)
                if self.accepts { self.pointerAcceleration = on }
                return self.accepts
            }
        )
    }
}

final class MousePreferencesViewControllerTests: XCTestCase {

    private typealias Fixtures = MouseDeviceFixtures

    private var savedMouse = LogiMouseSettings.default
    private var savedWheel = LogiWheelSettings.default
    private var devices: [LogiMouseDeviceState] = []
    private var refreshCount = 0
    private var diagnosticsCount = 0
    private var sampleCount = 0
    private var mac = FakeMacPointer()

    override func setUp() {
        super.setUp()
        savedMouse = Options.shared.logiMouse
        savedWheel = Options.shared.logiWheel
        Options.shared.logiMouse = .default
        Options.shared.logiWheel = .default
        devices = []
        refreshCount = 0
        diagnosticsCount = 0
        sampleCount = 0
        mac = FakeMacPointer()
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
        controller.pointerSettings = mac.settings
        controller.readbackSettleTime = 0
        _ = controller.view
        controller.reloadDevices()
        return controller
    }

    /// The switch, and wheel values the user set (nil = not set).
    private func manage(_ on: Bool = true, mode: LogiWheelMode? = .smartShift, sensitivity: Int? = 50, scrollForce: Int? = 100) {
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
        return [c.trackingSpeedRow, c.pointerSpeedRow, c.sensitivityRow, c.firmnessRow, c.strengthRow, c.pressForceRow]
    }

    /// The Logitech rows, top to bottom.
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

        for section in [controller.macSection!, controller.managedSection!, controller.pointerSection!,
                        controller.wheelSection!, controller.hapticsSection!] {
            XCTAssertFalse(section.isHidden)
        }
        for row in settingRows(controller) + [controller.trackingSpeedRow!, controller.pointerAccelerationRow!] {
            XCTAssertFalse(row.isHidden, row.title)
        }
        XCTAssertEqual(controller.headerView.nameLabel.stringValue, "MX Master 4")
        XCTAssertEqual(controller.headerView.statusLabel.stringValue, text("mouse-header-connected"))
        XCTAssertEqual(controller.headerView.batteryLabel.stringValue, MouseText.percent(75))
        XCTAssertEqual(controller.headerView.artwork.alphaValue, 1)
        XCTAssertEqual(controller.headerView.artwork.style, .mxMaster)
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

    /// Any mouse: a plain mouse on the card, what works with it, and the macOS settings.
    func testWithoutALogitechMouseTheCardAndTheMacOSBoxShow() {
        let controller = makeController()
        controller.view.layoutSubtreeIfNeeded()

        let header = controller.headerView!
        XCTAssertEqual(header.nameLabel.stringValue, text("mouse-header-any-mouse"))
        XCTAssertEqual(header.statusLabel.stringValue, text("mouse-header-any-mouse-detail"))
        XCTAssertFalse(header.statusLabel.isHidden)
        XCTAssertEqual(header.artwork.style, .anyMouse)
        XCTAssertEqual(header.artwork.alphaValue, 1, "a mouse of its own, not a dimmed MX Master")
        XCTAssertTrue(header.artwork.highlights.values.allSatisfy(\.isHidden), "nothing to light up")
        XCTAssertNil(header.content.battery)
        // The line wraps inside the card and is not cut off.
        let detail = frame(of: header.statusLabel, in: controller)
        XCTAssertLessThanOrEqual(detail.maxX, frame(of: header, in: controller).maxX - MouseHeaderView.textTrailingInset + 0.5)
        XCTAssertGreaterThan(detail.height, header.statusLabel.font!.boundingRectForFont.height, "more than one line")
        XCTAssertLessThan(header.statusLabel.fittingSize.height, MouseHeaderView.preferredHeight)

        XCTAssertFalse(controller.macSection.isHidden)
        XCTAssertEqual(controller.macSection.titleLabel?.stringValue, text("mouse-macos-header"))
        XCTAssertEqual(controller.macSection.box.visibleRows, [controller.trackingSpeedRow, controller.pointerAccelerationRow])
        for section in [controller.managedSection!, controller.pointerSection!, controller.wheelSection!, controller.hapticsSection!] {
            XCTAssertTrue(section.isHidden)
        }
        XCTAssertFalse(controller.footer.isHidden)
        XCTAssertTrue(controller.diagnosticsButton.isEnabled)
        XCTAssertEqual(controller.view.frame.size, controller.view.fittingSize)
        // Nothing to point at.
        controller.rowHoverChanged(.wheel, inside: true)
        XCTAssertNil(controller.headerView.emphasis)
        controller.rowHoverChanged(.body, inside: true)
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
        XCTAssertFalse(controller.macSection.isHidden)
        XCTAssertEqual(controller.headerView.artwork.style, .anyMouse)
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

    /// The regression: turning the switch on copied the first mouse's wheel into the
    /// settings. Now it takes nothing over: what was not set stays unset, and the rows show
    /// the mouse's own values.
    func testTurningManagementOnTakesNothingFromTheMouse() {
        Options.shared.logiMouse.pointerDPI = 1600
        let controller = makeController([Fixtures.mxMaster4(mode: .ratchet, sensitivity: nil, scrollForce: 100)])
        XCTAssertEqual(Options.shared.logiWheel, LogiWheelSettings(), "a fresh install sets nothing")

        set(controller.managedSwitch, true)
        XCTAssertEqual(Options.shared.logiWheel, LogiWheelSettings(managedByMos: true))
        XCTAssertEqual(Options.shared.logiMouse, LogiMouseSettings(pointerDPI: 1600), "the basics you set stay")
        XCTAssertEqual(controller.wheelModeControl.selectedSegment, 1, "the mouse's ratchet")
        XCTAssertEqual(controller.firmnessSlider.doubleValue, 100, "the mouse's force")
        XCTAssertEqual(controller.firmnessRow.explanation, text("mouse-wheel-force-hint"), "nothing to differ from")
        XCTAssertEqual(controller.wheelModeRow.explanation, MouseText.modeHint(.ratchet))

        // Off and on again: still nothing set.
        set(controller.managedSwitch, false)
        set(controller.managedSwitch, true)
        XCTAssertEqual(Options.shared.logiWheel, LogiWheelSettings(managedByMos: true))
    }

    /// The regression: switched on before the mouse had reported, the stored defaults
    /// (SmartShift / 50 / 50) were kept and written to it.
    func testTurningManagementOnBeforeTheMouseReportedSetsNothing() {
        let controller = makeController([Fixtures.mxMaster4(mode: nil, sensitivity: nil, scrollForce: nil)])
        set(controller.managedSwitch, true)
        XCTAssertEqual(Options.shared.logiWheel, LogiWheelSettings(managedByMos: true))

        // The mouse reports afterwards: its values show, and still nothing is set.
        devices = [Fixtures.mxMaster4(mode: .freeSpin, sensitivity: 75, scrollForce: 30)]
        NotificationCenter.default.post(name: LogiCenter.mouseStateChanged, object: nil)
        XCTAssertEqual(controller.wheelModeControl.selectedSegment, 2, "free-spin")
        XCTAssertEqual(controller.firmnessRow.valueText, MouseText.percent(30))
        XCTAssertEqual(Options.shared.logiWheel, LogiWheelSettings(managedByMos: true))
    }

    /// The regression: with two mice the first one's wheel became the settings, and so the
    /// second one's.
    func testTwoMiceNeverExchangeValues() {
        let controller = makeController([
            Fixtures.mxMaster4(mode: .ratchet, sensitivity: nil, scrollForce: 100),
            Fixtures.mxMaster3S(id: "mx3s", mode: .smartShift, sensitivity: 50),
        ])
        set(controller.managedSwitch, true)
        XCTAssertEqual(Options.shared.logiWheel, LogiWheelSettings(managedByMos: true))
    }

    // MARK: - Wheel values the user never set

    func testUnsetWheelValuesShowTheMouse() {
        manage(mode: nil, sensitivity: nil, scrollForce: nil)
        let controller = makeController([Fixtures.mxMaster4(mode: .smartShift, sensitivity: 72, scrollForce: 30)])
        XCTAssertEqual(controller.wheelModeControl.selectedSegment, 0)
        XCTAssertEqual(controller.sensitivityRow.valueText, MouseText.percent(72))
        XCTAssertEqual(controller.sensitivitySlider.doubleValue, 70, "on the nearest tick")
        XCTAssertEqual(controller.firmnessRow.valueText, MouseText.percent(30))
        for row in [controller.wheelModeRow!, controller.sensitivityRow!, controller.firmnessRow!] {
            XCTAssertTrue(row.isEnabled, row.title)
            XCTAssertFalse(row.explanation?.contains("\n") ?? false, "no \"On the mouse\" line for a value you never set: \(row.title)")
        }

        // A set value shows instead, with the line where the mouse has something else.
        Options.shared.logiWheel.scrollForce = 80
        controller.syncControls()
        XCTAssertEqual(controller.firmnessRow.valueText, MouseText.percent(80))
        XCTAssertEqual(controller.firmnessRow.explanation, text("mouse-wheel-force-hint") + "\n" + onTheMouse(MouseText.percent(30)))
        XCTAssertEqual(controller.sensitivityRow.valueText, MouseText.percent(72), "the others still show the mouse")
    }

    func testEachWheelControlSetsExactlyOneValue() {
        manage(mode: nil, sensitivity: nil, scrollForce: nil)
        let controller = makeController([Fixtures.mxMaster4(mode: .smartShift, sensitivity: 50, scrollForce: 100)])

        drag(controller.sensitivitySlider, to: 70)
        XCTAssertEqual(Options.shared.logiWheel, LogiWheelSettings(managedByMos: true, smartShiftSensitivity: 70))

        drag(controller.firmnessSlider, to: 20)
        XCTAssertEqual(Options.shared.logiWheel, LogiWheelSettings(managedByMos: true, smartShiftSensitivity: 70, scrollForce: 20))

        manage(mode: nil, sensitivity: nil, scrollForce: nil)
        controller.wheelModeControl.selectedSegment = 1
        send(controller.wheelModeControl)
        XCTAssertEqual(Options.shared.logiWheel, LogiWheelSettings(managedByMos: true, mode: .ratchet))
        XCTAssertEqual(Options.shared.logiMouse, .default, "the basics are not touched")
    }

    /// SmartShift chosen on a mouse that is always ratchet: the slider shows the threshold the
    /// mouse will get (the factory default), and the sensitivity stays unset.
    func testSmartShiftOnARatchetMouseShowsTheDefaultSensitivity() {
        manage(mode: nil, sensitivity: nil, scrollForce: nil)
        let controller = makeController([Fixtures.mxMaster4(mode: .ratchet, sensitivity: nil)])
        XCTAssertTrue(controller.sensitivityRow.isHidden)
        controller.wheelModeControl.selectedSegment = 0
        send(controller.wheelModeControl)
        XCTAssertFalse(controller.sensitivityRow.isHidden)
        XCTAssertEqual(controller.sensitivityRow.valueText, MouseText.percent(LogiWheelSettings.defaultSmartShiftSensitivity))
        XCTAssertNil(Options.shared.logiWheel.smartShiftSensitivity)
    }

    // MARK: - Sample pulse and dragging

    func testStrengthPlaysOneSamplePulseWhenLetGo() {
        manage()
        Options.shared.logiMouse.hapticsOn = true
        let controller = makeController([Fixtures.mxMaster4(hapticsOn: true)])
        let strength = controller.strengthSlider as! PreferencesSlider

        strength.beginTracking()
        drag(strength, to: 60)
        drag(strength, to: 75)
        XCTAssertEqual(sampleCount, 0, "not while it is dragged")
        XCTAssertEqual(Options.shared.logiMouse.hapticStrength, 80, "stored as it moves, tick by tick")

        // Let go: one pulse at the strength it was left at.
        strength.endTracking()
        XCTAssertEqual(sampleCount, 1)
        XCTAssertEqual(Options.shared.logiMouse.hapticStrength, 80)

        // A move outside a drag (VoiceOver, a click handled at once) is let go at once.
        drag(strength, to: 40)
        XCTAssertEqual(sampleCount, 2)
        XCTAssertEqual(Options.shared.logiMouse.hapticStrength, 40)

        // An arrow key is a move that is let go at once: one pulse each.
        XCTAssertTrue(strength.moveKnob(by: 1))
        XCTAssertEqual(Options.shared.logiMouse.hapticStrength, 60)
        XCTAssertEqual(sampleCount, 3)

        // Other sliders play nothing, dragged or not.
        let force = controller.pressForceSlider as! PreferencesSlider
        force.beginTracking()
        drag(force, to: 5000)
        force.endTracking()
        drag(controller.firmnessSlider, to: 40)
        XCTAssertEqual(sampleCount, 3)
    }

    func testAMouseUpdateDuringADragLeavesTheKnobAlone() {
        manage()
        let controller = makeController([Fixtures.mxMaster4()])
        let sensitivity = controller.sensitivitySlider as! PreferencesSlider

        // Only the knob under the pointer is left alone; every other one follows the mouse
        // at once (a refresh used to skip all of them while any mouse button was down).
        sensitivity.beginTracking()
        drag(sensitivity, to: 80)
        controller.pressForceSlider.doubleValue = 6187.5
        devices = [Fixtures.mxMaster4(dpi: 1200, pressForce: 4500, sensitivity: 40)]
        NotificationCenter.default.post(name: LogiCenter.mouseStateChanged, object: nil)
        XCTAssertEqual(sensitivity.doubleValue, 80)
        XCTAssertEqual(controller.pressForceSlider.doubleValue, 4818.5, "the tick nearest the mouse's 4500: you never set one")
        XCTAssertEqual(controller.pressForceRow.valueText, MouseText.percent(MousePaneModel.share(of: 4500, in: 4134...6872)))
        XCTAssertEqual(controller.pointerSpeedRow.valueText, "1200 DPI")

        sensitivity.endTracking()
        NotificationCenter.default.post(name: LogiCenter.mouseStateChanged, object: nil)
        XCTAssertEqual(sensitivity.doubleValue, 80, "your value")
        XCTAssertEqual(controller.sensitivityRow.valueText, MouseText.percent(80))
    }

    // MARK: - The header lights up the part

    func testEachRowLightsUpItsPartOfTheMouse() {
        let controller = makeController([Fixtures.mxMaster4()])
        let expected: [(PreferencesGroupRow, MousePart)] = [
            (controller.trackingSpeedRow, .body), (controller.pointerAccelerationRow, .body),
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
            (controller.trackingSpeedSlider, .body), (controller.pointerAccelerationSwitch, .body),
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
        controller.viewDidAppear()

        XCTAssertTrue(window.makeFirstResponder(controller.firmnessSlider))
        XCTAssertEqual(controller.focusedPart, .wheel)
        XCTAssertTrue(window.makeFirstResponder(nil))
        XCTAssertNil(controller.focusedPart)
        controller.viewDidDisappear()
    }

    /// Opened from the sidebar the pane is put into the window by the pane host: it has no
    /// window yet when it is about to appear, only once it has appeared. The focus is
    /// followed from then on (it used to be set up in viewWillAppear, through no window).
    func testTheFocusIsFollowedWhenTheSidebarOpensThePane() throws {
        manage()
        let controller = makeController([Fixtures.mxMaster4()])
        let host = PreferencesPaneHostViewController()
        // A window that is never ordered in: nothing shows and nothing takes the focus.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: PreferencesWindowLayout.contentWidth, height: 600),
            styleMask: [.titled], backing: .buffered, defer: true
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentViewController = host

        // The order AppKit keeps on screen.
        controller.viewWillAppear()
        XCTAssertNil(controller.view.window, "not in the window yet")
        host.show(controller)
        XCTAssertTrue(controller.view.window === window)
        controller.viewDidAppear()

        XCTAssertTrue(window.makeFirstResponder(controller.firmnessSlider))
        XCTAssertEqual(controller.focusedPart, .wheel)
        XCTAssertEqual(controller.headerView.emphasis, .wheel)
        XCTAssertTrue(window.makeFirstResponder(controller.hapticsSwitch))
        XCTAssertEqual(controller.focusedPart, .thumbPanel)

        // Gone from the screen: no longer followed.
        controller.viewDidDisappear()
        XCTAssertTrue(window.makeFirstResponder(controller.pointerSpeedSlider))
        XCTAssertNil(controller.focusedPart)
    }

    /// A refresh never leaves a slider empty: not on the first show (the sidebar switches
    /// panes on a mouse-down, and a refresh used to skip every slider while any button was
    /// down), and not for a slider other than the one being dragged.
    func testTheFirstShowFillsEverySlider() {
        manage()
        let controller = makeController([Fixtures.mxMaster4()])
        for row in [controller.pointerSpeedRow!, controller.sensitivityRow!, controller.firmnessRow!, controller.pressForceRow!] {
            XCTAssertFalse(row.isHidden, row.title)
            XCTAssertFalse(row.valueText.isEmpty, row.title)
            XCTAssertFalse(row.isTracking, row.title)
        }
        XCTAssertEqual(controller.pointerSpeedRow.valueText, "1000 DPI")
        // The pointer speed moves through the mouse's DPI steps, not the 0…100 it is made with.
        XCTAssertNotEqual(controller.pointerSpeedSlider.maxValue, MousePaneModel.percentSliderRange.upperBound)
    }

    // MARK: - Pointer (macOS)

    func testTheMacOSBoxShowsWhatMacOSHas() {
        mac.trackingSpeed = 3
        mac.pointerAcceleration = false
        let controller = makeController([Fixtures.mxMaster4()])

        XCTAssertEqual(controller.trackingSpeedRow.title, text("mouse-macos-tracking-speed"))
        XCTAssertEqual(controller.trackingSpeedRow.explanation, text("mouse-macos-tracking-speed-hint"))
        XCTAssertEqual(controller.trackingSpeedRow.lowEndLabel?.stringValue, text("mouse-macos-tracking-speed-slow"))
        XCTAssertEqual(controller.trackingSpeedRow.highEndLabel?.stringValue, text("mouse-macos-tracking-speed-fast"))
        XCTAssertEqual(controller.trackingSpeedRow.valueText, "", "macOS shows no number either")
        XCTAssertEqual(controller.pointerAccelerationRow.title, text("mouse-macos-acceleration"))
        XCTAssertEqual(controller.pointerAccelerationRow.explanation, text("mouse-macos-acceleration-hint"))

        // Ten stops, as in System Settings › Mouse.
        let slider = controller.trackingSpeedSlider!
        XCTAssertEqual(slider.minValue, 0)
        XCTAssertEqual(slider.maxValue, 9)
        XCTAssertEqual(slider.numberOfTickMarks, 10)
        XCTAssertTrue(slider.allowsTickMarkValuesOnly)
        XCTAssertEqual(slider.doubleValue, 9)
        XCTAssertFalse(controller.pointerAccelerationRow.isOn)
        // Not greyed out with the Logitech rows: macOS settings need no "manage".
        XCTAssertFalse(controller.managedRow.isOn)
        XCTAssertTrue(controller.trackingSpeedRow.isEnabled)
        XCTAssertTrue(controller.pointerAccelerationRow.isEnabled)
        XCTAssertEqual(mac.writes, 0)
    }

    func testAValueOffTheScaleShowsOnTheNearestStopAndIsKept() {
        mac.trackingSpeed = 1.2
        let controller = makeController()
        XCTAssertEqual(controller.trackingSpeedSlider.doubleValue, 5, "1.2 is nearest the 1.0 stop")
        mac.trackingSpeed = -1
        controller.reloadMacPointerSettings()
        XCTAssertEqual(controller.trackingSpeedSlider.doubleValue, 0, "below the scale: the slow end")
        controller.syncControls()
        XCTAssertEqual(mac.writes, 0, "showing a value never writes it")
    }

    /// Reading happens on load, when the pane appears and when the app becomes active; none
    /// of them writes.
    func testNothingIsWrittenWhenThePaneLoadsAppearsOrTheAppBecomesActive() {
        let controller = makeController([Fixtures.mxMaster4()])
        XCTAssertEqual(mac.reads, 1, "read once on load")

        mac.trackingSpeed = 2
        controller.viewWillAppear()
        XCTAssertEqual(mac.reads, 2)
        XCTAssertEqual(controller.trackingSpeedSlider.doubleValue, 7)

        // Back from System Settings: the app becomes active and the pane shows the change.
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: controller.view.frame.size),
            styleMask: [.titled], backing: .buffered, defer: true
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = controller.view
        mac.trackingSpeed = 0.5
        mac.pointerAcceleration = false
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        XCTAssertEqual(mac.reads, 3)
        XCTAssertEqual(controller.trackingSpeedSlider.doubleValue, 2)
        XCTAssertFalse(controller.pointerAccelerationRow.isOn)

        // Not in a window (another pane is shown): nothing to update.
        window.contentView = nil
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        XCTAssertEqual(mac.reads, 3)

        devices = []
        NotificationCenter.default.post(name: LogiCenter.mouseStateChanged, object: nil)
        controller.viewDidDisappear()
        XCTAssertEqual(mac.writes, 0)
    }

    func testTrackingSpeedWritesTheValueOfTheStop() {
        let controller = makeController()
        let slider = controller.trackingSpeedSlider!

        drag(slider, to: 9)
        XCTAssertEqual(mac.trackingSpeedWrites, [3])
        drag(slider, to: 9)
        XCTAssertEqual(mac.trackingSpeedWrites, [3], "the same stop again writes nothing")
        drag(slider, to: 0)
        drag(slider, to: 4.4)
        XCTAssertEqual(mac.trackingSpeedWrites, [3, 0, 0.875], "4.4 stops at the fifth tick")
        XCTAssertEqual(slider.doubleValue, 4)
        // Every stop writes its own value of the scale.
        for (index, speed) in MacPointerSettings.trackingSpeeds.enumerated().reversed() {
            drag(slider, to: Double(index))
            XCTAssertEqual(mac.trackingSpeed, speed)
        }
        XCTAssertTrue(mac.accelerationWrites.isEmpty, "one control, one setting")
    }

    func testPointerAccelerationSwitchWritesMacOS() {
        let controller = makeController([Fixtures.mxMaster4()])
        set(controller.pointerAccelerationSwitch, false)
        XCTAssertEqual(mac.accelerationWrites, [false])
        XCTAssertFalse(controller.pointerAccelerationRow.isOn)
        set(controller.pointerAccelerationSwitch, true)
        XCTAssertEqual(mac.accelerationWrites, [false, true])
        XCTAssertTrue(mac.trackingSpeedWrites.isEmpty, "one control, one setting")
        XCTAssertEqual(Options.shared.logiMouse, .default, "no Scrollio setting")
        XCTAssertEqual(Options.shared.logiWheel, .default)
    }

    /// A value macOS does not take is not kept: the control shows what macOS has again (a
    /// dragged knob once it is let go).
    func testAValueMacOSDoesNotTakePutsTheControlBack() throws {
        let controller = makeController()
        mac.accepts = false

        set(controller.pointerAccelerationSwitch, false)
        XCTAssertEqual(mac.accelerationWrites, [false])
        XCTAssertTrue(controller.pointerAccelerationRow.isOn)

        let slider = try XCTUnwrap(controller.trackingSpeedSlider as? PreferencesSlider)
        XCTAssertEqual(slider.doubleValue, 3)
        slider.beginTracking()
        drag(slider, to: 8)
        XCTAssertEqual(mac.trackingSpeedWrites, [2.5])
        XCTAssertEqual(slider.doubleValue, 8, "the knob stays under the pointer while dragged")
        slider.endTracking()
        XCTAssertEqual(slider.doubleValue, 3, "let go: back where macOS is")
        XCTAssertEqual(mac.trackingSpeed, 0.6875)
    }

    /// A value macOS does not give hides its row, and the box once both are hidden; the
    /// Logitech part is not touched.
    func testValuesThatCannotBeReadHideTheirRows() {
        mac.trackingSpeed = nil
        let controller = makeController([Fixtures.mxMaster4()])
        XCTAssertTrue(controller.trackingSpeedRow.isHidden)
        XCTAssertFalse(controller.pointerAccelerationRow.isHidden)
        XCTAssertFalse(controller.macSection.isHidden)

        mac.trackingSpeed = 1
        mac.pointerAcceleration = nil
        controller.reloadMacPointerSettings()
        XCTAssertFalse(controller.trackingSpeedRow.isHidden)
        XCTAssertTrue(controller.pointerAccelerationRow.isHidden)
        XCTAssertEqual(controller.view.frame.size, controller.view.fittingSize)

        mac.trackingSpeed = nil
        controller.reloadMacPointerSettings()
        XCTAssertTrue(controller.macSection.isHidden)
        XCTAssertFalse(controller.managedSection.isHidden)
        XCTAssertFalse(controller.pointerSection.isHidden)
        XCTAssertEqual(controller.view.frame.size, controller.view.fittingSize)

        // Without a Logitech mouse only the card and the footer are left.
        devices = []
        controller.reloadDevices()
        XCTAssertFalse(controller.headerView.isHidden)
        XCTAssertFalse(controller.footer.isHidden)
        for section in [controller.macSection!, controller.managedSection!, controller.pointerSection!,
                        controller.wheelSection!, controller.hapticsSection!] {
            XCTAssertTrue(section.isHidden)
        }
        XCTAssertEqual(mac.writes, 0)
    }

    /// In tests the pane never reaches the real macOS settings: its default is inert.
    func testThePaneUsesTheInertSettingsInTests() {
        XCTAssertTrue(AppRuntime.isRunningXCTest)
        let controller = MousePreferencesViewController()
        XCTAssertEqual(controller.pointerSettings.read(), MacPointerSettings.inert.read())
        XCTAssertEqual(MacPointerSettings.standard.read(), MacPointerState(trackingSpeed: 0.6875, pointerAcceleration: true))
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

        // The header and the boxes span the pane between its margins, top to bottom.
        let boxes = [controller.headerView!, controller.macSection.box, controller.managedSection.box,
                     controller.pointerSection.box, controller.wheelSection.box, controller.hapticsSection.box] as [NSView]
        for view in boxes {
            let box = frame(of: view, in: controller)
            XCTAssertEqual(box.minX, margin, accuracy: 0.5)
            XCTAssertEqual(box.maxX, boxRight, accuracy: 0.5)
        }
        let tops = boxes.map { frame(of: $0, in: controller).maxY }
        XCTAssertEqual(tops, tops.sorted(by: >), "the macOS box above the Logitech boxes")
        // The Logitech part keeps a section's distance from the macOS box above it.
        let gap = frame(of: controller.macSection.box, in: controller).minY - frame(of: controller.managedSection.box, in: controller).maxY
        XCTAssertEqual(gap, PreferencesGroupedForm.sectionSpacing, accuracy: 0.5)
        for row in settingRows(controller) + [controller.trackingSpeedRow!, controller.pointerAccelerationRow!] {
            XCTAssertEqual(frame(of: row.titleLabel, in: controller).minX, margin + inset, accuracy: 0.5, row.title)
        }
        // The switches and the values end at the box's inset; the sliders form one column.
        let rightEdges: [NSView] = [controller.managedSwitch, controller.hapticsSwitch, controller.wheelModeControl,
                                    controller.pointerAccelerationSwitch]
            + sliderRows(controller).compactMap(\.valueLabel)
        for view in rightEdges {
            XCTAssertEqual(frame(of: view, in: controller).maxX, boxRight - inset, accuracy: 1, "\(view)")
        }
        let sliders = sliderRows(controller).map { frame(of: $0.slider, in: controller) }
        XCTAssertEqual(Set(sliders.map { $0.minX.rounded() }).count, 1)
        XCTAssertEqual(Set(sliders.map { $0.width.rounded() }).count, 1)
        // Each control sits on the line of its title.
        var lines: [(NSView, PreferencesGroupRow)] = [(controller.managedSwitch, controller.managedRow),
                                                      (controller.hapticsSwitch, controller.hapticsRow),
                                                      (controller.pointerAccelerationSwitch, controller.pointerAccelerationRow)]
        lines += sliderRows(controller).map { ($0.slider as NSView, $0 as PreferencesGroupRow) }
        for (control, row) in lines {
            XCTAssertEqual(frame(of: control, in: controller).midY, frame(of: row.titleLabel, in: controller).midY, accuracy: 1, row.title)
        }
        // The three modes fill the box under the text of "Wheel mode".
        let modes = frame(of: controller.wheelModeControl, in: controller)
        XCTAssertEqual(modes.minX, margin + inset, accuracy: 1)
        for toggle in [controller.managedSwitch!, controller.hapticsSwitch!, controller.pointerAccelerationSwitch!] {
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
        let measure = NSTextField(wrappingLabelWithString: "X")
        measure.font = PreferencesForm.hintFont
        let oneLine = measure.fittingSize.height
        let lines: [(PreferencesGroupRow, Int)] = [
            (controller.trackingSpeedRow, 2), (controller.pointerAccelerationRow, 1),
            (controller.managedRow, 2), (controller.pointerSpeedRow, 2), (controller.wheelModeRow, 1),
            (controller.sensitivityRow, 1), (controller.firmnessRow, 1), (controller.hapticsRow, 1),
            // One line each at 520 pt: no word left alone on a second line.
            (controller.strengthRow, 1), (controller.pressForceRow, 1),
        ]
        for (row, count) in lines {
            XCTAssertEqual(row.explanationLabel.font?.pointSize, PreferencesForm.hintFontSize, row.title)
            XCTAssertEqual(row.explanationLabel.frame.height, CGFloat(count) * oneLine, accuracy: 0.5, row.title)
        }
        // No protocol words in the tab: "DPI" only as the unit of a value, and where Pointer
        // speed says what it is beside the macOS tracking speed.
        XCTAssertEqual(controller.pointerSpeedRow.explanation, text("mouse-pointer-speed-hint"))
        XCTAssertTrue(text("mouse-pointer-speed-hint").contains("tracking speed"))
        let texts = allSubviews(of: controller.view).compactMap { ($0 as? NSTextField)?.stringValue }
        for text in texts where text != controller.pointerSpeedRow.valueText && text != controller.pointerSpeedRow.explanation {
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

/// The scale and the reading rules of the macOS pointer settings. Only the pure parts:
/// nothing here reads or writes the real settings.
final class MacPointerSettingsTests: XCTestCase {

    func testTheScaleIsTheOneOfSystemSettings() {
        XCTAssertEqual(MacPointerSettings.trackingSpeeds, [0, 0.125, 0.5, 0.6875, 0.875, 1, 1.5, 2, 2.5, 3])
        XCTAssertEqual(MacPointerPaneModel.trackingSpeedRange, 0...9)
        XCTAssertEqual(MacPointerPaneModel.trackingSpeedScale, .ticksOnly(10))
    }

    func testTheNearestStop() {
        for (index, speed) in MacPointerSettings.trackingSpeeds.enumerated() {
            XCTAssertEqual(MacPointerSettings.trackingSpeedIndex(nearest: speed), index)
        }
        XCTAssertEqual(MacPointerSettings.trackingSpeedIndex(nearest: 0.3125), 1, "the slower one on a tie")
        XCTAssertEqual(MacPointerSettings.trackingSpeedIndex(nearest: 0.7), 3)
        XCTAssertEqual(MacPointerSettings.trackingSpeedIndex(nearest: -1), 0)
        XCTAssertEqual(MacPointerSettings.trackingSpeedIndex(nearest: 5), 9)
    }

    func testTheModelHidesWhatCannotBeRead() {
        let full = MacPointerPaneModel(MacPointerState(trackingSpeed: 1.5, pointerAcceleration: false))
        XCTAssertEqual(full.trackingSpeedIndex, 6)
        XCTAssertEqual(full.pointerAcceleration, false)
        XCTAssertFalse(full.isEmpty)
        let none = MacPointerPaneModel(MacPointerState())
        XCTAssertNil(none.trackingSpeedIndex)
        XCTAssertNil(none.pointerAcceleration)
        XCTAssertTrue(none.isEmpty)
    }

    /// The HID event system keeps 16.16 fixed point: 3.0 is the 196608 `hidutil` shows.
    func testFixedPoint() {
        XCTAssertEqual(MacPointerSystem.fixedPoint(3), 196608)
        XCTAssertEqual(MacPointerSystem.fixedPoint(0.6875), 45056)
        XCTAssertEqual(MacPointerSystem.fixedPoint(0), 0)
        XCTAssertEqual(MacPointerSystem.double(fromFixedPoint: 196608), 3)
        for speed in MacPointerSettings.trackingSpeeds {
            XCTAssertEqual(MacPointerSystem.double(fromFixedPoint: Int(MacPointerSystem.fixedPoint(speed))), speed)
        }
    }

    func testTheKeysAreTheOnesSystemSettingsUses() {
        XCTAssertEqual(MacPointerSystem.trackingSpeedPreferenceKey, "com.apple.mouse.scaling")
        XCTAssertEqual(MacPointerSystem.linearPreferenceKey, "com.apple.mouse.linear")
        XCTAssertEqual(MacPointerSystem.trackingSpeedProperty, "HIDMouseAcceleration")
        XCTAssertEqual(MacPointerSystem.linearProperty, "HIDUseLinearScalingMouseAcceleration")
    }

    /// What is in effect wins over what is stored.
    func testReadingTheTrackingSpeed() {
        let read = MacPointerSystem.trackingSpeed(property:preference:)
        XCTAssertEqual(read(NSNumber(value: 196608), NSNumber(value: 1.0)), 3)
        XCTAssertEqual(read(NSNumber(value: 0), NSNumber(value: 1.0)), 0, "slowest is a number, not false")
        XCTAssertEqual(read(nil, NSNumber(value: 1.5)), 1.5)
        XCTAssertEqual(read(nil, "2"), 2, "defaults write without -float stores text")
        XCTAssertNil(read(nil, NSNumber(value: true)), "a Boolean is no speed")
        XCTAssertNil(read(nil, "fast"))
        XCTAssertNil(read(nil, nil))
    }

    /// On unless linear tracking is set; on is also the macOS default.
    func testReadingPointerAcceleration() {
        let read = MacPointerSystem.pointerAcceleration(property:preference:)
        XCTAssertFalse(read(NSNumber(value: 1), nil))
        XCTAssertTrue(read(NSNumber(value: 0), NSNumber(value: true)), "what is in effect wins")
        XCTAssertFalse(read(nil, NSNumber(value: true)))
        XCTAssertTrue(read(nil, NSNumber(value: false)))
        XCTAssertFalse(read(nil, NSNumber(value: 1)))
        XCTAssertFalse(read(nil, "YES"))
        XCTAssertTrue(read(nil, "NO"))
        XCTAssertTrue(read(nil, nil))
    }

    func testTheInertSettingsNeverWrite() {
        let inert = MacPointerSettings.inert
        XCTAssertFalse(inert.writeTrackingSpeed(1))
        XCTAssertFalse(inert.writePointerAcceleration(false))
        XCTAssertEqual(inert.read(), MacPointerState(trackingSpeed: 0.6875, pointerAcceleration: true))
    }
}

final class MousePreferencesTabPlacementTests: XCTestCase {

    func testMousePaneSitsAfterGestures() throws {
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesSplitViewController.self))
        let windowController = try XCTUnwrap(
            storyboard.instantiateController(withIdentifier: "preferencesWindowController") as? NSWindowController
        )
        defer { windowController.close() }
        let preferences = try XCTUnwrap(windowController.contentViewController as? PreferencesSplitViewController)

        let identifiers = preferences.panes.map(\.identifier)
        let mouse = try XCTUnwrap(identifiers.firstIndex(of: "mouse"))
        XCTAssertEqual(identifiers[mouse - 1], "gestures")
        let controller = try XCTUnwrap(preferences.controller(for: "mouse"))
        XCTAssertTrue(controller is MousePreferencesViewController)
        XCTAssertFalse(controller.title?.isEmpty ?? true)
        XCTAssertNotEqual(controller.title, "mouse-tab-title", "the pane title must be localized")
    }
}

/// Renders the tab off screen for a look at it, light and dark: MX Master 4 managed and not,
/// with "On the mouse" lines and each part lit up, MX Master 3S, any mouse with its macOS
/// settings, and macOS settings that could not be read. Off screen the
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

        func tab(_ devices: [LogiMouseDeviceState], mac: FakeMacPointer = FakeMacPointer()) -> MousePreferencesViewController {
            let controller = MousePreferencesViewController()
            controller.deviceSource = MouseDeviceSource(deviceStates: { devices }, refresh: {}, showDiagnostics: {})
            controller.pointerSettings = mac.settings
            controller.readbackSettleTime = 0
            _ = controller.view
            controller.reloadDevices()
            return controller
        }
        let master4 = MouseDeviceFixtures.mxMaster4()

        // The owner's mouse as it reports now, Scrollio managing it with nothing changed yet.
        Options.shared.logiMouse = .default
        Options.shared.logiWheel = LogiWheelSettings(managedByMos: true)
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

        // Any mouse: the macOS settings as on the owner's Mac (fastest, acceleration on), then
        // a slow linear one, then values macOS did not give.
        let owner = FakeMacPointer()
        owner.trackingSpeed = 3
        try render(tab([], mac: owner).view, name: "any-mouse", into: directory)
        let linear = FakeMacPointer()
        linear.trackingSpeed = 0.5
        linear.pointerAcceleration = false
        try render(tab([], mac: linear).view, name: "any-mouse-linear", into: directory)
        let speedOnly = FakeMacPointer()
        speedOnly.pointerAcceleration = nil
        try render(tab([], mac: speedOnly).view, name: "any-mouse-acceleration-unreadable", into: directory)
        let unreadable = FakeMacPointer()
        unreadable.trackingSpeed = nil
        unreadable.pointerAcceleration = nil
        try render(tab([], mac: unreadable).view, name: "any-mouse-unreadable", into: directory)
        try render(tab([master4], mac: unreadable).view, name: "mx-master-4-macos-unreadable", into: directory)
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
