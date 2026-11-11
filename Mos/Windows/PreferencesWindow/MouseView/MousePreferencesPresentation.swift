//
//  MousePreferencesPresentation.swift
//  Mos
//  What the Mouse tab shows, worked out without views so the rules can be unit tested:
//  where the mice come from, which rows a mouse gets, what each control shows, when it
//  can be changed and when an "On the mouse: …" line is due.
//
//  The rules:
//  - A row for something no connected mouse has is hidden, not disabled.
//  - "Let Scrollio manage this mouse" off: the rows show the mouse's own values, greyed out.
//  - On: they show the user's values; a basic setting the user never set shows the mouse's.
//  - "On the mouse: …" only where the user's value differs from what the mouse reports.
//

import Foundation

/// Where the Mouse tab reads the connected mice from and what it asks of them. `live`
/// uses LogiCenter; tests and renders pass fixtures, so no mouse is read or written.
struct MouseDeviceSource {
    var deviceStates: () -> [LogiMouseDeviceState]
    var refresh: () -> Void
    var showDiagnostics: () -> Void
    /// One pulse at the new strength, after the strength slider is let go.
    var playHapticSample: () -> Void = {}

    static let live = MouseDeviceSource(
        deviceStates: { LogiCenter.shared.mouseDeviceStates() },
        refresh: { LogiCenter.shared.refreshMouseStates() },
        showDiagnostics: { LogiCenter.shared.showDebugPanel() },
        playHapticSample: { LogiCenter.shared.playHapticSample() }
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
        /// The mouse's name, or that none is connected.
        let title: String
        let subtitle: String?
        let battery: Battery?
        let isConnected: Bool
    }

    /// A slider row. Its slider runs over `range`; a slider with `tickCount` > 0 stops only
    /// at its tick marks (one per value the mouse accepts).
    struct Slider: Equatable {
        let range: ClosedRange<Double>
        let position: Double
        let tickCount: Int
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

    let header: Header
    let hasMouse: Bool
    let managed: Bool
    /// nil: the row is hidden.
    let pointerSpeed: Slider?
    /// The DPI values the pointer speed slider stops at, ascending.
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
    /// to 6 % (at the sensitive end), so a value within 3 % of the user's is the same choice.
    static let sensitivityTolerance = 3

    /// - Parameters:
    ///   - settings: `Options.shared.logiMouse`.
    ///   - wheel: `Options.shared.logiWheel`; its `managedByMos` is the tab's main switch.
    ///   - heldReadbacks: settings the user just changed; their "On the mouse" line waits
    ///     until the mouse has had time to take the new value.
    init(
        devices: [LogiMouseDeviceState],
        settings: LogiMouseSettings,
        wheel: LogiWheelSettings,
        heldReadbacks: Set<MouseSetting> = []
    ) {
        let managed = wheel.managedByMos
        self.managed = managed
        let mice = Self.ordered(devices)
        hasMouse = !mice.isEmpty
        header = Self.header(for: mice)

        func readback<T: Equatable>(_ setting: MouseSetting, mine: T?, onMouse: T?, text: (T) -> String) -> String? {
            guard managed, !heldReadbacks.contains(setting),
                  let mine, let onMouse, mine != onMouse else { return nil }
            return MouseText.onTheMouse(text(onMouse))
        }
        /// The user's value while managed, the mouse's otherwise; each falls back on the other.
        func shown<T>(mine: T?, onMouse: T?, fallback: T) -> T {
            return managed ? (mine ?? onMouse ?? fallback) : (onMouse ?? mine ?? fallback)
        }

        // Pointer speed: snapped to the DPI values the mouse accepts.
        if let pointer = mice.lazy.compactMap({ $0.pointerSpeed }).first(where: { !$0.choices.isEmpty }) {
            let choices = pointer.choices
            let mine = settings.pointerDPI.map { Self.nearest($0, in: choices) }
            let value = Self.nearest(
                shown(mine: mine, onMouse: pointer.dpi.onMouse, fallback: pointer.defaultDPI ?? choices[choices.count / 2]),
                in: choices
            )
            let index = choices.firstIndex(of: value) ?? 0
            pointerChoices = choices
            pointerSpeed = Slider(
                range: 0...Double(max(1, choices.count - 1)),
                position: Double(index),
                tickCount: choices.count <= Self.maxTickMarks ? choices.count : 0,
                valueText: MouseText.dpi(value),
                isEnabled: managed,
                readback: readback(.pointerSpeed, mine: mine, onMouse: pointer.dpi.onMouse, text: MouseText.dpi)
            )
        } else {
            pointerChoices = []
            pointerSpeed = nil
        }

        // The wheel: mode and SmartShift sensitivity, and the firmness of its clicks.
        if let state = mice.lazy.compactMap({ $0.wheel }).first(where: { $0.supportsSmartShift }) {
            let mode = managed ? wheel.mode : (state.mode ?? wheel.mode)
            wheelMode = Mode(
                mode: mode,
                isEnabled: managed,
                readback: readback(.wheelMode, mine: wheel.mode, onMouse: state.mode, text: MouseText.modeName)
            )
            if mode == .smartShift {
                let value = managed ? wheel.smartShiftSensitivity : (state.smartShiftSensitivity ?? wheel.smartShiftSensitivity)
                // Compared only while the mouse is in SmartShift: in another mode it keeps an old value.
                var differs: String?
                if state.mode == .smartShift, let onMouse = state.smartShiftSensitivity,
                   abs(onMouse - wheel.smartShiftSensitivity) > Self.sensitivityTolerance {
                    differs = readback(.sensitivity, mine: wheel.smartShiftSensitivity, onMouse: onMouse, text: MouseText.percent)
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
            let value = managed ? wheel.scrollForce : (state.scrollForce ?? wheel.scrollForce)
            firmness = Self.percentSlider(
                value, range: LogiWheelSettings.scrollForceRange, enabled: managed,
                readback: readback(.firmness, mine: wheel.scrollForce, onMouse: state.scrollForce, text: MouseText.percent)
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
                readback: readback(.haptics, mine: settings.hapticsOn, onMouse: state.isOn.onMouse, text: MouseText.onOff)
            )
            let few = state.hasFewLevels == true && !state.fewLevelChoices.isEmpty ? state.fewLevelChoices : nil
            let mine = settings.hapticStrength.map { value in few.map { Self.nearest(value, in: $0) } ?? value }
            let range = LogiMouseSettings.hapticStrengthRange
            let value = Self.clamp(
                shown(mine: mine, onMouse: state.strength.onMouse, fallback: range.upperBound), to: range
            )
            let differs = readback(.strength, mine: mine, onMouse: state.strength.onMouse, text: MouseText.percent)
            if let few {
                let level = Self.nearest(value, in: few)
                strength = Slider(
                    range: 0...Double(max(1, few.count - 1)),
                    position: Double(few.firstIndex(of: level) ?? 0),
                    tickCount: few.count,
                    valueText: MouseText.percent(level),
                    isEnabled: managed && isOn,
                    readback: differs
                )
            } else {
                strength = Self.percentSlider(value, range: range, enabled: managed && isOn, readback: differs)
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
            pressForce = Slider(
                range: Double(range.lowerBound)...Double(max(range.upperBound, range.lowerBound + 1)),
                position: Double(value),
                tickCount: 0,
                valueText: share(value),
                isEnabled: managed,
                readback: readback(.pressForce, mine: mine, onMouse: state.force.onMouse, text: share)
            )
        } else {
            pressForceRange = nil
            pressForce = nil
        }
    }

    /// More choices than this make a slider without tick marks (a dot every 50 DPI would be a smear).
    static let maxTickMarks = 12

    // MARK: - Helpers

    /// The mouse the header is about first (the one with the most settings), then the others:
    /// each row takes its values from the first mouse that has it.
    static func ordered(_ devices: [LogiMouseDeviceState]) -> [LogiMouseDeviceState] {
        func score(_ device: LogiMouseDeviceState) -> Int {
            return device.supported.count + (device.wheel == nil ? 0 : 1)
        }
        // `max(by:)` keeps the first of equals: the list's own order breaks ties.
        guard let best = devices.indices.max(by: { score(devices[$0]) < score(devices[$1]) }) else {
            return []
        }
        var result = devices
        let first = result.remove(at: best)
        return [first] + result
    }

    private static func header(for mice: [LogiMouseDeviceState]) -> Header {
        guard let mouse = mice.first else {
            return Header(title: MouseText.text("mouse-header-no-mouse"), subtitle: nil, battery: nil, isConnected: false)
        }
        let subtitle = mice.count > 1
            ? String(format: MouseText.text("mouse-header-connected-several"), mice.count)
            : MouseText.text("mouse-header-connected")
        return Header(title: mouse.deviceName, subtitle: subtitle, battery: battery(mouse.battery), isConnected: true)
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

    private static func percentSlider(_ value: Int, range: ClosedRange<Int>, enabled: Bool, readback: String?) -> Slider {
        let clamped = clamp(value, to: range)
        return Slider(
            range: Double(range.lowerBound)...Double(range.upperBound),
            position: Double(clamped),
            tickCount: 0,
            valueText: MouseText.percent(clamped),
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

/// Text shown in the Mouse tab.
enum MouseText {

    static func text(_ key: String) -> String {
        return NSLocalizedString(key, comment: "")
    }

    /// Segment order of the wheel mode control.
    static let modes: [LogiWheelMode] = [.smartShift, .ratchet, .freeSpin]

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

    /// The explanation of a row with its "On the mouse" line under it.
    static func explanation(_ hint: String, readback: String?) -> String {
        guard let readback else { return hint }
        return hint + "\n" + readback
    }
}
