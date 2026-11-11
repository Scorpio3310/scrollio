// Mos/Logi/LogiCenter.swift
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
    func name(forMosCode code: UInt16) -> String? {
        let displayName = LogiCIDDirectory.name(forMosCode: code)
        return displayName.isEmpty ? nil : displayName
    }
    func nativeMouseButton(forMosCode code: UInt16) -> UInt16? {
        let nativeButton = LogiCIDDirectory.nativeMouseButton(forMosCode: code)
        #if DEBUG
        LogiTrace.log("[Mapping] nativeMouseButton mosCode=\(code) -> \(nativeButton.map(String.init) ?? "nil")")
        #endif
        return nativeButton
    }

    // MARK: - Conflict
    func buttonCaptureDiagnosis(forMosCode code: UInt16) -> LogiButtonCaptureDiagnosis {
        return manager.buttonCaptureDiagnosis(forMosCode: code)
    }
    func conflictStatus(forMosCode code: UInt16) -> ConflictStatus {
        return manager.conflictStatus(forMosCode: code)
    }
    func isDeliveryContended(forMosCode code: UInt16) -> Bool {
        return manager.deliveryMode(forMosCode: code) == .contended
    }
    func showBLEHIDPPUnstableToast(forMosCode code: UInt16) {
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

    // MARK: - Scroll wheel hardware settings (contract: Mos/Logi/Wheel/LogiWheelTypes.swift)

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
    /// connected device that supports them. Never writes when `settings.managedByMos`
    /// is false. Main thread only.
    func applyWheelSettings(_ settings: LogiWheelSettings) {
        #if DEBUG
        precondition(Thread.isMainThread, "LogiCenter is main-thread-only")
        #endif
        manager.applyWheelSettings(settings)
    }

    // MARK: - Gesture Navigation hardware support (contract: Mos/Logi/Gesture/LogiGestureTypes.swift)

    /// Mos codes of the Logitech buttons whose holds the mouse should track itself (raw XY
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
    func playGestureHaptic(_ cue: MouseGestureHapticCue, forMosCode code: UInt16) {
        #if DEBUG
        precondition(Thread.isMainThread, "LogiCenter is main-thread-only")
        #endif
        manager.playGestureHaptic(cue, forMosCode: code)
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
