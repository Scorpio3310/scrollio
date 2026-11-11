//
//  BatteryWatcher.swift
//  Mos
//  Warns once when a Logitech mouse's battery runs low, and once more when it is almost
//  empty. Charging (or a battery that is clearly full again) starts over.
//
//  It only reads what LogiCenter already knows (`mouseDeviceStates`) whenever the mice
//  report something (`LogiCenter.mouseStateChanged`); it asks the mice nothing and writes
//  nothing to them. The battery arrives with the mouse's own battery events and with the
//  reads of the Mouse pane and the status-bar menu. Nothing is stored: after a relaunch a
//  low battery is reported once again.
//

import Cocoa

final class BatteryWatcher {

    static let shared = BatteryWatcher()

    /// How urgent a battery is. Ordered: a warning is shown when this rises.
    enum Alert: Int, Comparable {
        case none
        case low
        case critical

        static func < (lhs: Alert, rhs: Alert) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }

    /// At or under these percentages the battery is low or almost empty. The Mouse pane shows
    /// the battery in red from the same low mark.
    static let lowPercent = 10
    static let criticalPercent = 5
    /// At or above this the battery counts as charged again (a charge the app did not see).
    static let recoveredPercent = 30

    // MARK: - Seams (tests replace them: no mouse, no toast)

    /// The connected mice as LogiCenter knows them.
    var deviceStates: () -> [LogiMouseDeviceState] = { LogiCenter.shared.mouseDeviceStates() }
    /// Shows a warning.
    var showToast: (String) -> Void = { message in
        Toast.show(message, style: .warning, duration: 8)
    }

    // MARK: - State

    /// The last warning shown per mouse (by `LogiMouseDeviceState.id`).
    private(set) var shownAlerts: [String: Alert] = [:]
    private var observer: NSObjectProtocol?

    var isWatching: Bool {
        return observer != nil
    }

    deinit {
        stop()
    }

    /// Follows the mice from now on, and looks at what is known already.
    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: LogiCenter.mouseStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.check()
        }
        check()
    }

    func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
    }

    /// Looks at every connected mouse.
    func check() {
        for mouse in deviceStates() {
            update(id: mouse.id, name: mouse.deviceName, battery: mouse.battery)
        }
    }

    private func update(id: String, name: String, battery: LogiMouseDeviceState.Battery?) {
        guard let battery else { return }
        if Self.isCharging(battery) || Self.isRecovered(battery) {
            shownAlerts[id] = Alert.none
            return
        }
        let alert = Self.alert(for: battery)
        guard alert > shownAlerts[id, default: .none] else { return }
        shownAlerts[id] = alert
        if let message = Self.message(for: alert, name: name, battery: battery) {
            showToast(message)
        }
    }

    // MARK: - Rules (pure)

    /// How urgent `battery` is, from its percentage and from the level the mouse reports,
    /// whichever says more. Charging is not looked at here.
    static func alert(for battery: LogiMouseDeviceState.Battery) -> Alert {
        var fromPercent = Alert.none
        if let percent = battery.percent {
            if percent <= criticalPercent {
                fromPercent = .critical
            } else if percent <= lowPercent {
                fromPercent = .low
            }
        }
        let fromLevel: Alert
        switch battery.level {
        case .critical: fromLevel = .critical
        case .low: fromLevel = .low
        case .good, .full, .unknown: fromLevel = .none
        }
        return max(fromPercent, fromLevel)
    }

    static func isCharging(_ battery: LogiMouseDeviceState.Battery) -> Bool {
        switch battery.charging {
        case .charging, .chargingSlowly, .almostFull, .full: return true
        case .discharging, .problem, .unknown: return false
        }
    }

    /// Clearly charged again, also when the charging itself was not seen.
    static func isRecovered(_ battery: LogiMouseDeviceState.Battery) -> Bool {
        if let percent = battery.percent {
            return percent >= recoveredPercent
        }
        return battery.level == .good || battery.level == .full
    }

    /// "MX Master 4 battery is low (8%)." A coarse reading (original MX Master 3) leaves the
    /// number out.
    static func message(for alert: Alert, name: String, battery: LogiMouseDeviceState.Battery) -> String? {
        let percent = battery.isApproximate ? nil : battery.percent.map(MouseText.percent)
        switch alert {
        case .none:
            return nil
        case .low:
            guard let percent else {
                return String(format: NSLocalizedString("toast-battery-low-plain", comment: ""), name)
            }
            return String(format: NSLocalizedString("toast-battery-low", comment: ""), name, percent)
        case .critical:
            guard let percent else {
                return String(format: NSLocalizedString("toast-battery-critical-plain", comment: ""), name)
            }
            return String(format: NSLocalizedString("toast-battery-critical", comment: ""), name, percent)
        }
    }
}
