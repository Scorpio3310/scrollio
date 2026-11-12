// Scrollio/Logi/LogiCenter.swift
import Foundation
import Cocoa

/// The single public facade for everything Logi. External code must NOT
/// reference any other Logi type by name (CI lint enforces this from Step 5).
final class LogiCenter {
    static let shared = LogiCenter()

    // MARK: - Internal collaborators (Step 2: facade only delegates to manager;
    //                                  Step 3: registry added; Step 4: bridge filled in)
    private let manager: LogiSessionManager
    internal let registry: UsageRegistry
    internal private(set) var externalBridge: LogiExternalBridge

    // MARK: - Production init
    private init() {
        self.manager = LogiSessionManager.shared
        let mgr = self.manager  // capture for closure
        self.registry = UsageRegistry(sessionProvider: { [weak mgr] in
            return mgr?.activeSessions ?? []
        })
        self.externalBridge = LogiNoOpBridge.shared
    }

    // MARK: - Test-injectable init (Tier 2 harness)
    #if DEBUG
    internal init(manager: LogiSessionManager,
                  registry: UsageRegistry,
                  bridge: LogiExternalBridge = LogiNoOpBridge.shared) {
        self.manager = manager
        self.registry = registry
        self.externalBridge = bridge
    }
    #endif

    // MARK: - Bridge installation (DEBUG: precondition main thread)
    func installBridge(_ bridge: LogiExternalBridge) {
        #if DEBUG
        precondition(Thread.isMainThread, "installBridge must be called on main")
        #endif
        self.externalBridge = bridge
    }

    // MARK: - Lifecycle
    func start() {
        #if DEBUG
        precondition(Thread.isMainThread, "LogiCenter is main-thread-only")
        #endif
        manager.start()
    }
    func stop() {
        #if DEBUG
        precondition(Thread.isMainThread)
        #endif
        manager.stop()
    }

    // MARK: - CID directory (read-only)
    func isLogiCode(_ code: UInt16) -> Bool { LogiCIDDirectory.isLogitechCode(code) }
    func name(forScrollioCode code: UInt16) -> String? {
        let displayName = LogiCIDDirectory.name(forScrollioCode: code)
        return displayName.isEmpty ? nil : displayName
    }
    /// What a Logitech control is on the mouse, for the Buttons pane's drawing: the gesture
    /// button, the MX Master 4's thumb panel, the mode shift button behind the wheel, or one
    /// of the buttons a standard mouse has too. nil for any other control and for codes that
    /// are not Logitech's.
    func controlRole(forScrollioCode code: UInt16) -> LogiControlRole? {
        guard let cid = LogiCIDDirectory.toCID(code) else { return nil }
        return LogiControlRole(cid: cid)
    }
    /// The code of the control with `role` on an MX Master (the control the role is named
    /// after: 0x52 middle, 0x53 back, 0x56 forward, 0xC3 gesture, 0xC4 mode shift, 0x1A0 the
    /// MX Master 4's thumb panel): what a press of it is recorded as while it is diverted.
    /// Read-only; touches no device.
    func scrollioCode(for role: LogiControlRole) -> UInt16 {
        let cid: UInt16
        switch role {
        case .middle: cid = 0x0052
        case .back: cid = 0x0053
        case .forward: cid = 0x0056
        case .gesture: cid = 0x00C3
        case .modeShift: cid = 0x00C4
        case .thumbPanel: cid = 0x01A0
        }
        return LogiCIDDirectory.toScrollioCode(cid)
    }
    func nativeMouseButton(forScrollioCode code: UInt16) -> UInt16? {
        let nativeButton = LogiCIDDirectory.nativeMouseButton(forScrollioCode: code)
        #if DEBUG
        LogiTrace.log("[Mapping] nativeMouseButton scrollioCode=\(code) -> \(nativeButton.map(String.init) ?? "nil")")
        #endif
        return nativeButton
    }

    // MARK: - Conflict
    func buttonCaptureDiagnosis(forScrollioCode code: UInt16) -> LogiButtonCaptureDiagnosis {
        return manager.buttonCaptureDiagnosis(forScrollioCode: code)
    }
    func conflictStatus(forScrollioCode code: UInt16) -> ConflictStatus {
        return manager.conflictStatus(forScrollioCode: code)
    }
    func isDeliveryContended(forScrollioCode code: UInt16) -> Bool {
        return manager.deliveryMode(forScrollioCode: code) == .contended
    }
    func showBLEHIDPPUnstableToast(forScrollioCode code: UInt16) {
        guard let cid = LogiCIDDirectory.toCID(code) else { return }
        let controlName = LogiCIDDirectory.name(forCID: cid)
        let message = String(
            format: NSLocalizedString("logi_ble_hidpp_unstable_toast", comment: ""),
            controlName
        )
        externalBridge.showLogiToast(message, severity: .warning)
    }

    // MARK: - Recording
    var isRecording: Bool { manager.isRecording }
    func beginKeyRecording() { manager.temporarilyDivertAll() }
    func endKeyRecording() { manager.restoreDivertToBindings() }

    // MARK: - Feature actions
    func executeSmartShiftToggle() { manager.executeSmartShiftToggle() }
    func executeDPICycle(direction: Direction) { manager.executeDPICycle(direction: direction) }

    // MARK: - Reporting refresh
    func refreshReportingStates() { manager.refreshReportingStates() }

    // MARK: - Scroll wheel hardware settings (contract: Scrollio/Logi/Wheel/LogiWheelTypes.swift)

    /// Connected Logitech mice that expose wheel settings (SmartShift 0x2110 / 0x2111).
    /// Values are the last ones read from each device. Main thread only.
    func wheelDeviceStates() -> [LogiWheelDeviceState] {
        #if DEBUG
        precondition(Thread.isMainThread, "LogiCenter is main-thread-only")
        #endif
        return manager.wheelDeviceStates()
    }

    /// Re-reads wheel state from connected devices; posts `wheelStateChanged` when
    /// answers arrive (or right away when no device has a wheel feature).
    func refreshWheelStates() {
        #if DEBUG
        precondition(Thread.isMainThread, "LogiCenter is main-thread-only")
        #endif
        manager.refreshWheelStates()
    }

    /// Remembers `settings` for devices that (re)connect later and writes them to every
    /// connected device that supports them. Never writes when `settings.managedByScrollio`
    /// is false. Main thread only.
    func applyWheelSettings(_ settings: LogiWheelSettings) {
        #if DEBUG
        precondition(Thread.isMainThread, "LogiCenter is main-thread-only")
        #endif
        manager.applyWheelSettings(settings)
    }

    // MARK: - Basic mouse settings (contract: Scrollio/Logi/Basics/LogiMouseBasicsTypes.swift)

    /// One entry per connected Logitech mouse with battery, pointer speed, haptics, press
    /// force or a wheel: what each reports (last read) and what the user set, the wheel state
    /// inside. Main thread only.
    func mouseDeviceStates() -> [LogiMouseDeviceState] {
        #if DEBUG
        precondition(Thread.isMainThread, "LogiCenter is main-thread-only")
        #endif
        return manager.mouseDeviceStates()
    }

    /// Re-reads every connected mouse (the battery at most every few minutes; it also
    /// follows the mouse's own battery events). Posts `mouseStateChanged` when answers
    /// arrive, or right away when there is nothing to read. Main thread only.
    func refreshMouseStates() {
        #if DEBUG
        precondition(Thread.isMainThread, "LogiCenter is main-thread-only")
        #endif
        manager.refreshMouseStates()
    }

    /// Remembers `settings` for mice that connect later and hands them to every connected
    /// mouse. Nothing is written unless `managed` ("Let Scrollio manage this mouse") is on;
    /// then a value is written only when the user set it and the mouse reports something
    /// else. Reading never needs `managed`. Main thread only.
    func applyMouseSettings(_ settings: LogiMouseSettings, managed: Bool) {
        #if DEBUG
        precondition(Thread.isMainThread, "LogiCenter is main-thread-only")
        #endif
        manager.applyMouseSettings(settings, managed: managed)
    }

    /// "Send Again" in the Mouse tab: every connected mouse is read again and then given the
    /// values the user set that it reports differently, the way a reconnect does it. Nothing
    /// is written unless "Let Scrollio manage this mouse" is on, and a value the user never
    /// set is never written. Posts `mouseStateChanged`. Main thread only.
    func sendMouseSettingsAgain() {
        #if DEBUG
        precondition(Thread.isMainThread, "LogiCenter is main-thread-only")
        #endif
        manager.sendMouseSettingsAgain()
    }

    /// Plays one pulse at the current strength on every connected mouse whose haptics are
    /// on (the "feel it" pulse after the strength slider is let go). It waits briefly for
    /// the settings push of that slider, so it is felt at the new strength. Main thread only.
    func playHapticSample() {
        #if DEBUG
        precondition(Thread.isMainThread, "LogiCenter is main-thread-only")
        #endif
        manager.playHapticSample()
    }

    // MARK: - Gesture Navigation hardware support (contract: Scrollio/Logi/Gesture/LogiGestureTypes.swift)

    /// Scrollio codes of the Logitech buttons whose holds the mouse should track itself (raw XY
    /// diversion) instead of moving the pointer. Remembered for mice that connect later and
    /// applied together with the button diverts. Pass an empty set to turn it off: armed
    /// controls are then put back to normal pointer movement. Main thread only.
    func setGestureTrackingCodes(_ codes: Set<UInt16>) {
        #if DEBUG
        precondition(Thread.isMainThread, "LogiCenter is main-thread-only")
        LogiTrace.log("[Center] setGestureTrackingCodes codes=\(LogiTrace.codes(codes))")
        #endif
        guard manager.setGestureTrackingCodes(codes) else { return }
        // Same coalesced pass that applies binding changes, so a control whose binding and
        // tracking change together gets one write.
        registry.scheduleReapply()
    }

    /// Plays a haptic cue on the mouse `code` was last pressed on. Does nothing unless that
    /// mouse has haptics and the user has them switched on; never changes the mouse's
    /// intensity or power saving. Main thread only.
    func playGestureHaptic(_ cue: MouseGestureHapticCue, forScrollioCode code: UInt16) {
        #if DEBUG
        precondition(Thread.isMainThread, "LogiCenter is main-thread-only")
        #endif
        manager.playGestureHaptic(cue, forScrollioCode: code)
    }

    /// A connected mouse has a control that can report movement itself.
    func supportsGestureDeviceTracking() -> Bool {
        return manager.supportsGestureDeviceTracking
    }

    /// A connected mouse has a haptic motor.
    func supportsGestureHaptics() -> Bool {
        return manager.supportsGestureHaptics
    }

    /// Asks the mice again whether their haptics are switched on.
    func refreshGestureStates() {
        #if DEBUG
        precondition(Thread.isMainThread, "LogiCenter is main-thread-only")
        #endif
        manager.refreshGestureStates()
    }

    // MARK: - Debug panel
    func showDebugPanel() {
        #if DEBUG
        precondition(Thread.isMainThread)
        #endif
        LogiDebugPanel.shared.show()
    }

    func logButtonCaptureDiagnostic(_ message: String) {
        #if DEBUG
        LogiDebugPanel.log(device: "Button Capture", type: .buttonEvent, message: message)
        #endif
    }

    // MARK: - Activity
    var isBusy: Bool { manager.isBusy }
    var currentActivitySummary: [SessionActivityStatus] { manager.currentActivitySummary }

    // MARK: - Usage registry
    func setUsage(source: UsageSource, codes: Set<UInt16>) {
        #if DEBUG
        LogiTrace.log("[Center] setUsage source=\(source) codes=\(LogiTrace.codes(codes))")
        #endif
        registry.setUsage(source: source, codes: codes)
    }
    func usages(of code: UInt16) -> [UsageSource] {
        return registry.usages(of: code)
    }

    // MARK: - Snapshots
    func activeSessionsSnapshot() -> [LogiDeviceSessionSnapshot] {
        return manager.activeSessions.map { LogiDeviceSessionSnapshot(session: $0) }
    }

    // MARK: - Namespaced notifications
    static let sessionChanged        = LogiSessionManager.sessionChangedNotification
    static let discoveryStateChanged = LogiSessionManager.discoveryStateDidChangeNotification
    static let reportingDidComplete  = LogiSessionManager.reportingQueryDidCompleteNotification
    static let activityChanged       = LogiSessionManager.activityStateDidChangeNotification
    static let conflictChanged       = LogiSessionManager.conflictChangedNotification
    static let buttonEventRelay      = LogiSessionManager.buttonEventNotification
    static let rawButtonEvent        = NSNotification.Name("LogiRawButtonEvent")  // Step 4 fills in posters
}

/// The role of a Logitech control on the mouse (`LogiCenter.controlRole(forScrollioCode:)`).
enum LogiControlRole: Equatable {
    /// The gesture button under the thumb (also its virtual twin).
    case gesture
    /// The MX Master 4's haptic sense panel under the thumb, where the MX Master 3 and 3S
    /// have their gesture button.
    case thumbPanel
    /// The small button behind the wheel that switches the wheel mode (SmartShift).
    case modeShift
    case middle
    case back
    case forward

    init?(cid: UInt16) {
        switch cid {
        case 0x00C3, 0x00D7: self = .gesture
        case 0x01A0: self = .thumbPanel
        case 0x00C4: self = .modeShift
        case 0x0052: self = .middle
        case 0x0053, 0x0054, 0x0055: self = .back
        case 0x0056, 0x0057, 0x0058: self = .forward
        default: return nil
        }
    }
}
