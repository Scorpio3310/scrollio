//
//  MousePreferencesPresentation.swift
//  Mos
//  What the Mouse tab shows, worked out without views so the rules can be unit tested:
//  where the mice come from, which rows a mouse gets, what each control shows, when it
//  can be changed and when an "On the mouse: …" line is due. The "Pointer (macOS)" box,
//  shown for any mouse, is `MacPointerPaneModel`.
//
//  The rules:
//  - A row for something no connected mouse has is hidden, not disabled.
//  - "Let Scrollio manage this mouse" off: the rows show the mouse's own values, greyed out.
//  - On: they show the user's values; a setting the user never set (basic or wheel) shows
//    the mouse's.
//  - "On the mouse: …" only where the user's value differs from what the mouse reports,
//    with why when the Logi layer knows it ("Still sending your value…", "The mouse
//    refused 1600 DPI.", …).
//  - A muted line under the switch: while it is off, why the rows are greyed; while it is
//    on and a value is not on the mouse for a reason other than "still sending", that it is
//    not, with "Send Again".
//  - Turning the switch on changes no setting: nothing is taken over from a mouse.
//

import Foundation

/// Where the Mouse tab reads the connected mice from and what it asks of them. `live`
/// uses LogiCenter; tests and renders pass fixtures, so no mouse is read or written.
struct MouseDeviceSource {
    var deviceStates: () -> [LogiMouseDeviceState]
    var refresh: () -> Void
    /// One pulse at the new strength, after the strength slider is let go.
    var playHapticSample: () -> Void = {}
    /// "Send Again": the mice are read again and given what differs (LogiCenter writes only
    /// values the user set, only while managed, only where the fresh read differs).
    var sendAgain: () -> Void = {}

    static let live = MouseDeviceSource(
        deviceStates: { LogiCenter.shared.mouseDeviceStates() },
        refresh: { LogiCenter.shared.refreshMouseStates() },
        playHapticSample: { LogiCenter.shared.playHapticSample() },
        sendAgain: { LogiCenter.shared.sendMouseSettingsAgain() }
    )
}

/// The part of the mouse a setting is about. The picture at the top of the tab lights it up.
enum MousePart: Int, CaseIterable {
    /// The whole mouse: how far the pointer moves.
    case body
    case wheel
    /// The thumb rest of MX Master 4, which pulses and clicks.
    case thumbPanel
}

/// The settings of the tab, one per control.
enum MouseSetting: CaseIterable {
    case pointerSpeed, wheelMode, sensitivity, firmness, haptics, strength, pressForce

    var part: MousePart {
        switch self {
        case .pointerSpeed: return .body
        case .wheelMode, .sensitivity, .firmness: return .wheel
        case .haptics, .strength, .pressForce: return .thumbPanel
        }
    }
}

/// Everything the tab shows for the connected mice and the stored settings.
struct MousePaneModel: Equatable {

    struct Battery: Equatable {
        /// "75%", "About 50%", "Low".
        let text: String
        let symbolName: String
        let isCharging: Bool
        /// Shown in red.
        let isLow: Bool
        let accessibilityLabel: String
    }

    struct Header: Equatable {
        /// The Logitech mouse's name, or "Mouse" while none is connected.
        let title: String
        let subtitle: String?
        let battery: Battery?
        let isConnected: Bool
        /// The drawing: the connected mouse's, the plain one while none is connected.
        let model: MouseArtworkModel
    }

    /// A slider row. Its slider runs over `range` with the tick marks of `scale`; the knob
    /// sits at `position`, the tick nearest the value shown in `valueText`. A value between
    /// two ticks is shown, not changed: only moving the slider writes a tick's value.
    struct Slider: Equatable {
        let range: ClosedRange<Double>
        let scale: PreferencesSliderScale?
        let position: Double
        let valueText: String
        let isEnabled: Bool
        /// "On the mouse: …", or nil.
        let readback: String?
    }

    struct Toggle: Equatable {
        let isOn: Bool
        let isEnabled: Bool
        let readback: String?
    }

    struct Mode: Equatable {
        let mode: LogiWheelMode
        let isEnabled: Bool
        let readback: String?
    }

    /// The muted line under "Let Scrollio manage this mouse".
    enum ManagedNote: Equatable {
        /// The switch is off: the rows below are greyed and show what the mouse reports.
        case notManaged
        /// The switch is on and a value the user set is not on the mouse, for a reason other
        /// than "still sending": the line comes with "Send Again".
        case notOnTheMouse
    }

    let header: Header
    let hasMouse: Bool
    let managed: Bool
    /// nil: no line.
    let managedNote: ManagedNote?
    /// nil: the row is hidden.
    let pointerSpeed: Slider?
    /// The DPI values the pointer speed slider stops at, ascending: `pointerLadder` as the
    /// mouse offers it.
    let pointerChoices: [Int]
    let wheelMode: Mode?
    /// Only in SmartShift mode.
    let sensitivity: Slider?
    let firmness: Slider?
    let haptics: Toggle?
    let strength: Slider?
    /// The strengths the slider stops at, on a mouse with only a few; nil: any 1…100.
    let strengthChoices: [Int]?
    let pressForce: Slider?
    /// The force range of the thumb panel the slider covers.
    let pressForceRange: ClosedRange<Int>?

    /// The read-back of SmartShift sensitivity is coarse: the mouse keeps it in steps of up
    /// to 6 % (at the sensitive end), so a value within 3 % of the user's is the same choice
    /// (the Logi layer does not write it again either).
    static let sensitivityTolerance = LogiWheelSettings.sensitivityTolerance

    /// What a wheel row shows while the user has set nothing and the mouse has not reported:
    /// SmartShift at the factory sensitivity, a middle force.
    static let wheelModeFallback = LogiWheelMode.smartShift
    static let sensitivityFallback = LogiWheelSettings.defaultSmartShiftSensitivity
    static let scrollForceFallback = 50

    /// - Parameters:
    ///   - settings: `Options.shared.logiMouse`.
    ///   - wheel: `Options.shared.logiWheel`; its `managedByScrollio` is the tab's main switch.
    ///   - heldReadbacks: settings the user just changed; their "On the mouse" line waits
    ///     until the mouse has had time to take the new value.
    init(
        devices: [LogiMouseDeviceState],
        settings: LogiMouseSettings,
        wheel: LogiWheelSettings,
        heldReadbacks: Set<MouseSetting> = []
    ) {
        let managed = wheel.managedByScrollio
        self.managed = managed
        let mice = Self.ordered(devices)
        hasMouse = !mice.isEmpty
        header = Self.header(for: mice, managed: managed)

        /// A shown line whose value Scrollio is not (or no longer) sending: "Send Again" helps.
        var notOnTheMouse = false
        func readback<T: Equatable>(
            _ setting: MouseSetting, mine: T?, onMouse: T?,
            why: LogiMouseDeviceState.Mismatch?, text: (T) -> String
        ) -> String? {
            guard managed, !heldReadbacks.contains(setting),
                  let mine, let onMouse, mine != onMouse else { return nil }
            if why != .sending { notOnTheMouse = true }
            return MouseText.onTheMouse(text(onMouse), why: why, yours: text(mine))
        }
        /// The user's value while managed, the mouse's otherwise; each falls back on the other.
        func shown<T>(mine: T?, onMouse: T?, fallback: T) -> T {
            return managed ? (mine ?? onMouse ?? fallback) : (onMouse ?? mine ?? fallback)
        }

        // Pointer speed: a tick per rung of the ladder the mouse offers. The label shows the
        // DPI as it is (snapped to what the mouse accepts), the knob the nearest rung.
        if let pointer = mice.lazy.compactMap({ $0.pointerSpeed }).first(where: { !$0.choices.isEmpty }) {
            let choices = pointer.choices
            let rungs = Self.pointerRungs(offered: choices)
            let mine = settings.pointerDPI.map { Self.nearest($0, in: choices) }
            let value = Self.nearest(
                shown(mine: mine, onMouse: pointer.dpi.onMouse, fallback: pointer.defaultDPI ?? choices[choices.count / 2]),
                in: choices
            )
            let index = rungs.firstIndex(of: Self.nearest(value, in: rungs)) ?? 0
            pointerChoices = rungs
            pointerSpeed = Slider(
                range: 0...Double(max(1, rungs.count - 1)),
                scale: rungs.count > 1 ? .ticksOnly(rungs.count) : nil,
                position: Double(index),
                valueText: MouseText.dpi(value),
                isEnabled: managed,
                readback: readback(.pointerSpeed, mine: mine, onMouse: pointer.dpi.onMouse, why: pointer.dpi.mismatch, text: MouseText.dpi)
            )
        } else {
            pointerChoices = []
            pointerSpeed = nil
        }

        // The wheel: mode and SmartShift sensitivity, and the firmness of its clicks. Like the
        // basics, a value the user never set shows the mouse's.
        if let state = mice.lazy.compactMap({ $0.wheel }).first(where: { $0.supportsSmartShift }) {
            let mode = shown(mine: wheel.mode, onMouse: state.mode.onMouse, fallback: Self.wheelModeFallback)
            wheelMode = Mode(
                mode: mode,
                isEnabled: managed,
                readback: readback(
                    .wheelMode, mine: wheel.mode, onMouse: state.mode.onMouse, why: state.mode.mismatch, text: MouseText.modeName
                )
            )
            if mode == .smartShift {
                let onMouse = state.smartShiftSensitivity.onMouse
                let value = shown(mine: wheel.smartShiftSensitivity, onMouse: onMouse, fallback: Self.sensitivityFallback)
                // Compared only while the mouse is in SmartShift: in another mode it keeps an old value.
                var differs: String?
                if state.mode.onMouse == .smartShift, let mine = wheel.smartShiftSensitivity, let onMouse,
                   abs(onMouse - mine) > Self.sensitivityTolerance {
                    differs = readback(
                        .sensitivity, mine: mine, onMouse: onMouse, why: state.smartShiftSensitivity.mismatch, text: MouseText.percent
                    )
                }
                sensitivity = Self.percentSlider(value, range: LogiWheelSettings.sensitivityRange, enabled: managed, readback: differs)
            } else {
                sensitivity = nil
            }
        } else {
            wheelMode = nil
            sensitivity = nil
        }
        if let state = mice.lazy.compactMap({ $0.wheel }).first(where: { $0.supportsScrollForce }) {
            let onMouse = state.scrollForce.onMouse
            let value = shown(mine: wheel.scrollForce, onMouse: onMouse, fallback: Self.scrollForceFallback)
            firmness = Self.percentSlider(
                value, range: LogiWheelSettings.scrollForceRange, enabled: managed,
                readback: readback(
                    .firmness, mine: wheel.scrollForce, onMouse: onMouse, why: state.scrollForce.mismatch, text: MouseText.percent
                )
            )
        } else {
            firmness = nil
        }

        // Haptics: the switch, and the strength while it is on.
        if let state = mice.lazy.compactMap({ $0.haptics }).first {
            let isOn = shown(mine: settings.hapticsOn, onMouse: state.isOn.onMouse, fallback: false)
            haptics = Toggle(
                isOn: isOn,
                isEnabled: managed,
                readback: readback(
                    .haptics, mine: settings.hapticsOn, onMouse: state.isOn.onMouse, why: state.isOn.mismatch, text: MouseText.onOff
                )
            )
            let few = state.hasFewLevels == true && !state.fewLevelChoices.isEmpty ? state.fewLevelChoices : nil
            let mine = settings.hapticStrength.map { value in few.map { Self.nearest(value, in: $0) } ?? value }
            let range = LogiMouseSettings.hapticStrengthRange
            let value = Self.clamp(
                shown(mine: mine, onMouse: state.strength.onMouse, fallback: range.upperBound), to: range
            )
            let differs = readback(
                .strength, mine: mine, onMouse: state.strength.onMouse, why: state.strength.mismatch, text: MouseText.percent
            )
            if let few {
                let level = Self.nearest(value, in: few)
                strength = Slider(
                    range: 0...Double(max(1, few.count - 1)),
                    scale: few.count > 1 ? .ticksOnly(few.count) : nil,
                    position: Double(few.firstIndex(of: level) ?? 0),
                    valueText: MouseText.percent(level),
                    isEnabled: managed && isOn,
                    readback: differs
                )
            } else {
                strength = Self.slider(
                    value, over: Self.strengthSliderRange, scale: Self.strengthScale, text: MouseText.percent,
                    enabled: managed && isOn, readback: differs
                )
            }
            strengthChoices = few
        } else {
            haptics = nil
            strength = nil
            strengthChoices = nil
        }

        // Thumb panel press: in the mouse's own units, shown as a share of its range.
        if let state = mice.lazy.compactMap({ $0.pressForce }).first(where: { $0.isChangeable && $0.range != nil }),
           let range = state.range {
            let mine = settings.pressForce.map { Self.clamp($0, to: range) }
            let value = Self.clamp(
                shown(mine: mine, onMouse: state.force.onMouse, fallback: state.defaultForce ?? range.lowerBound), to: range
            )
            let share = { (force: Int) in MouseText.percent(Self.share(of: force, in: range)) }
            pressForceRange = range
            pressForce = Self.slider(
                value, over: Double(range.lowerBound)...Double(max(range.upperBound, range.lowerBound + 1)),
                scale: Self.pressForceScale, text: share, enabled: managed,
                readback: readback(.pressForce, mine: mine, onMouse: state.force.onMouse, why: state.force.mismatch, text: share)
            )
        } else {
            pressForceRange = nil
            pressForce = nil
        }

        let hasSettings = pointerSpeed != nil || wheelMode != nil || firmness != nil || haptics != nil || pressForce != nil
        if !hasMouse || !hasSettings {
            managedNote = nil
        } else if !managed {
            managedNote = .notManaged
        } else {
            managedNote = notOnTheMouse ? .notOnTheMouse : nil
        }
    }

    // MARK: - Scales

    /// The pointer speeds the slider offers, a tick each: each rung becomes the nearest DPI
    /// the mouse accepts (`pointerRungs`).
    static let pointerLadder = [400, 600, 800, 1000, 1200, 1600, 2000, 2400, 3200, 4000, 6000, 8000]

    /// SmartShift sensitivity and click firmness: a tick every 10 % from 0 to 100, the knob
    /// stops only there. The lowest tick writes the setting's least value (1 %).
    static let percentSliderRange: ClosedRange<Double> = 0...100
    static let percentScale = PreferencesSliderScale.ticksOnly(11)

    /// Haptic strength: 20, 40, 60, 80 and 100 %.
    static let strengthSliderRange: ClosedRange<Double> = 20...100
    static let strengthScale = PreferencesSliderScale.ticksOnly(5)

    /// Thumb panel press: five ticks across the mouse's own range (0, 25, 50, 75, 100 %).
    static let pressForceScale = PreferencesSliderScale.ticksOnly(5)

    /// `pointerLadder` as a mouse offering `choices` has it: every rung replaced by the
    /// nearest DPI of `choices`, without repeats, ascending.
    static func pointerRungs(offered choices: [Int]) -> [Int] {
        guard !choices.isEmpty else { return [] }
        var rungs: [Int] = []
        for rung in pointerLadder.map({ nearest($0, in: choices) }) where !rungs.contains(rung) {
            rungs.append(rung)
        }
        return rungs.sorted()
    }

    // MARK: - Helpers

    /// The mouse the panes are about when several are connected: the one with the most
    /// settings, the first of equals. The Mouse card names it, the Buttons card names and
    /// draws it, the gesture preview draws it: they never show different mice. nil: none.
    static func shownMouse(
        among devices: [LogiMouseDeviceState] = LogiCenter.shared.mouseDeviceStates()
    ) -> LogiMouseDeviceState? {
        return shownMouseIndex(devices).map { devices[$0] }
    }

    private static func shownMouseIndex(_ devices: [LogiMouseDeviceState]) -> Int? {
        func score(_ device: LogiMouseDeviceState) -> Int {
            return device.supported.count + (device.wheel == nil ? 0 : 1)
        }
        // `max(by:)` keeps the first of equals: the list's own order breaks ties.
        return devices.indices.max(by: { score(devices[$0]) < score(devices[$1]) })
    }

    /// The shown mouse first (`shownMouse`), then the others: each row takes its values
    /// from the first mouse that has it.
    static func ordered(_ devices: [LogiMouseDeviceState]) -> [LogiMouseDeviceState] {
        guard let best = shownMouseIndex(devices) else { return [] }
        var result = devices
        let first = result.remove(at: best)
        return [first] + result
    }

    /// - Parameter managed: "Let Scrollio manage this mouse" is on. Only then do the choices
    ///   go to the mice, so only then does the card say they go to all of them.
    private static func header(for mice: [LogiMouseDeviceState], managed: Bool) -> Header {
        guard let mouse = mice.first else {
            return Header(
                title: MouseText.text("mouse-header-any-mouse"),
                subtitle: MouseText.text("mouse-header-any-mouse-detail"),
                battery: nil,
                isConnected: false,
                model: .generic
            )
        }
        let subtitle = mice.count > 1 && managed
            ? String(format: MouseText.text("mouse-header-connected-several"), mice.count)
            : MouseText.text("mouse-header-connected")
        return Header(
            title: mouse.deviceName, subtitle: subtitle, battery: battery(mouse.battery), isConnected: true,
            model: MouseArtworkModel.model(forDeviceName: mouse.deviceName)
        )
    }

    static func battery(_ battery: LogiMouseDeviceState.Battery?) -> Battery? {
        guard let battery else { return nil }
        let level: Int
        var text: String
        if let percent = battery.percent {
            level = percent
            text = MouseText.percent(percent)
            if battery.isApproximate {
                text = String(format: MouseText.text("mouse-battery-about"), text)
            }
        } else {
            switch battery.level {
            case .full: level = 100; text = MouseText.text("mouse-battery-full")
            case .good: level = 50; text = MouseText.text("mouse-battery-good")
            case .low: level = 20; text = MouseText.text("mouse-battery-low")
            case .critical: level = 5; text = MouseText.text("mouse-battery-critical")
            case .unknown: return nil
            }
        }
        let charging: Bool
        switch battery.charging {
        case .charging, .chargingSlowly, .almostFull, .full: charging = true
        case .discharging, .problem, .unknown: charging = false
        }
        if battery.charging == .problem {
            text = String(format: MouseText.text("mouse-battery-not-charging"), text)
        }
        let symbol: String
        switch level {
        case _ where charging: symbol = "battery.100percent.bolt"
        case 88...: symbol = "battery.100percent"
        case 63..<88: symbol = "battery.75percent"
        case 38..<63: symbol = "battery.50percent"
        case 13..<38: symbol = "battery.25percent"
        default: symbol = "battery.0percent"
        }
        let accessibility = String(
            format: MouseText.text(charging ? "mouse-battery-accessibility-charging" : "mouse-battery-accessibility"),
            text
        )
        return Battery(
            text: text,
            symbolName: symbol,
            isCharging: charging,
            isLow: !charging && (level <= 10 || battery.level == .critical),
            accessibilityLabel: accessibility
        )
    }

    /// A 0…100 % slider with a tick every 10 % for a setting stored in `range`.
    private static func percentSlider(_ value: Int, range: ClosedRange<Int>, enabled: Bool, readback: String?) -> Slider {
        return slider(
            clamp(value, to: range), over: percentSliderRange, scale: percentScale, text: MouseText.percent,
            enabled: enabled, readback: readback
        )
    }

    /// A slider over `range` whose knob shows `value` on the nearest tick of `scale`; the
    /// label shows `value` itself.
    private static func slider(
        _ value: Int,
        over range: ClosedRange<Double>,
        scale: PreferencesSliderScale,
        text: (Int) -> String,
        enabled: Bool,
        readback: String?
    ) -> Slider {
        return Slider(
            range: range,
            scale: scale,
            position: scale.knobPosition(for: Double(value), in: range),
            valueText: text(value),
            isEnabled: enabled,
            readback: readback
        )
    }

    /// The value of `choices` nearest to `value` (the lower one on a tie).
    static func nearest(_ value: Int, in choices: [Int]) -> Int {
        return choices.min { abs($0 - value) < abs($1 - value) || (abs($0 - value) == abs($1 - value) && $0 < $1) } ?? value
    }

    static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        return min(max(value, range.lowerBound), range.upperBound)
    }

    /// Where `value` sits in `range`, 0…100.
    static func share(of value: Int, in range: ClosedRange<Int>) -> Int {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return Int((Double(clamp(value, to: range) - range.lowerBound) / Double(span) * 100).rounded())
    }
}

/// The "Pointer (macOS)" box: the user's macOS settings for every mouse. A row whose value
/// macOS did not give is hidden, and the box with it once both are.
struct MacPointerPaneModel: Equatable {

    /// The tick of the tracking speed slider (`MacPointerSettings.trackingSpeeds`); nil: hidden.
    let trackingSpeedIndex: Int?
    /// nil: hidden.
    let pointerAcceleration: Bool?

    /// The slider runs over the ticks, 0 (slow) … 9 (fast), and stops only on them.
    static let trackingSpeedRange: ClosedRange<Double> = 0...Double(MacPointerSettings.trackingSpeeds.count - 1)
    static let trackingSpeedScale = PreferencesSliderScale.ticksOnly(MacPointerSettings.trackingSpeeds.count)

    init(_ state: MacPointerState) {
        trackingSpeedIndex = state.trackingSpeed.map(MacPointerSettings.trackingSpeedIndex(nearest:))
        pointerAcceleration = state.pointerAcceleration
    }

    var isEmpty: Bool {
        return trackingSpeedIndex == nil && pointerAcceleration == nil
    }
}

/// Text shown in the Mouse tab.
enum MouseText {

    static func text(_ key: String) -> String {
        return NSLocalizedString(key, comment: "")
    }

    /// Segment order of the wheel mode control.
    static let modes: [LogiWheelMode] = [.smartShift, .ratchet, .freeSpin]

    /// The stop of the macOS tracking speed at `index` (0 = slowest) as VoiceOver reads it:
    /// "4 of 10".
    static func trackingSpeedStop(_ index: Int) -> String {
        let count = MacPointerSettings.trackingSpeeds.count
        return String(format: text("mouse-macos-tracking-speed-value"), min(max(index, 0), count - 1) + 1, count)
    }

    static func modeName(_ mode: LogiWheelMode) -> String {
        switch mode {
        case .smartShift: return text("mouse-wheel-mode-smartshift")
        case .ratchet: return text("mouse-wheel-mode-ratchet")
        case .freeSpin: return text("mouse-wheel-mode-free-spin")
        }
    }

    /// One plain line on what the mode does, under "Wheel mode".
    static func modeHint(_ mode: LogiWheelMode) -> String {
        switch mode {
        case .smartShift: return text("mouse-wheel-mode-smartshift-hint")
        case .ratchet: return text("mouse-wheel-mode-ratchet-hint")
        case .freeSpin: return text("mouse-wheel-mode-free-spin-hint")
        }
    }

    private static let percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    /// 40 -> "40%" (spacing follows the user's locale).
    static func percent(_ value: Int) -> String {
        return percentFormatter.string(from: NSNumber(value: Double(value) / 100)) ?? "\(value)%"
    }

    /// 1000 -> "1000 DPI".
    static func dpi(_ value: Int) -> String {
        return String(format: text("mouse-pointer-speed-value"), value)
    }

    static func onOff(_ on: Bool) -> String {
        return text(on ? "mouse-value-on" : "mouse-value-off")
    }

    /// "On the mouse: 40%".
    static func onTheMouse(_ value: String) -> String {
        return String(format: text("mouse-wheel-readback-one"), value)
    }

    /// "On the mouse: 1000 DPI", and why it is not `yours` when that is known:
    /// "On the mouse: 1000 DPI. The mouse refused 1600 DPI."
    static func onTheMouse(_ value: String, why: LogiMouseDeviceState.Mismatch?, yours: String) -> String {
        switch why {
        case nil: return onTheMouse(value)
        case .sending?: return String(format: text("mouse-readback-sending"), value)
        case .refused?: return String(format: text("mouse-readback-refused"), value, yours)
        case .noAnswer?: return String(format: text("mouse-readback-no-answer"), value)
        case .notKept?: return String(format: text("mouse-readback-not-kept"), value)
        case .changedElsewhere?: return String(format: text("mouse-readback-changed"), value)
        }
    }

    /// The muted line under "Let Scrollio manage this mouse".
    static func managedNote(_ note: MousePaneModel.ManagedNote) -> String {
        switch note {
        case .notManaged: return text("mouse-managed-off-note")
        case .notOnTheMouse: return text("mouse-not-on-mouse-note")
        }
    }

    /// The explanation of a row with its "On the mouse" line under it.
    static func explanation(_ hint: String, readback: String?) -> String {
        guard let readback else { return hint }
        return hint + "\n" + readback
    }
}
