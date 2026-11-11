//
//  LogiGestureController.swift
//  Mos
//
//  Per-device (per receiver slot) state of what Gesture Navigation uses on a Logitech
//  mouse: raw XY diversion of held controls and haptic cues. Like LogiWheelController it
//  owns no transport: the session injects the closures and forwards the reports, so the
//  logic is testable with fake bytes. Byte layouts: LogiGestureProtocol.
//
//  Raw XY rules:
//  - A control is armed only when Mos asked for it (`setRawXYRequest`), the control has
//    the raw_xy capability and it is being diverted anyway. Arming goes out together with
//    the divert (0x33), at the time the binding is applied, never in the middle of a hold.
//  - A hold is tracked by the device only when the mouse acknowledged the arm request
//    before the button went down. No acknowledgement within `acknowledgeTimeout`, or an
//    HID++ error, drops the control back to the pointer path until the request changes.
//  - Controls Mos never armed keep getting the exact bytes they always got (0x03 / 0x02).
//  - The first movement sample of every hold is dropped (OpenLogi saw a large jump there).
//
//  Haptic rules: play only when the mouse has 0x19B0, says haptics are enabled and lists
//  the waveform. Read-only otherwise: intensity and power saving are never written.
//
//  Main thread only (HID++ callbacks run on the main run loop).
//

import Foundation

final class LogiGestureController {

    /// Sends setCidReporting for one control of this device.
    typealias SendReporting = (_ cid: UInt16, _ flags: UInt8) -> Void
    /// Sends a request to the haptic feature of this device.
    typealias SendHaptic = (_ functionId: UInt8, _ params: [UInt8]) -> Void
    /// Hands movement of a tracked hold to the app, in sensor counts.
    typealias DeliverMovement = (_ cid: UInt16, _ deltaX: Int, _ deltaY: Int) -> Void
    /// Runs the block on the main queue after the delay.
    typealias Schedule = (_ delay: TimeInterval, _ work: @escaping () -> Void) -> Void

    /// How long the mouse has to echo an arm request. Its answers normally take a few
    /// milliseconds; the session uses the same 2 s for its own acknowledgement bookkeeping.
    static let acknowledgeTimeout: TimeInterval = 2

    private let sendReporting: SendReporting
    private let sendHaptic: SendHaptic
    private let deliverMovement: DeliverMovement
    private let schedule: Schedule
    private let onChange: () -> Void
    private let log: (String) -> Void

    init(
        sendReporting: @escaping SendReporting,
        sendHaptic: @escaping SendHaptic,
        deliverMovement: @escaping DeliverMovement,
        schedule: @escaping Schedule,
        onChange: @escaping () -> Void = {},
        log: @escaping (String) -> Void = { _ in }
    ) {
        self.sendReporting = sendReporting
        self.sendHaptic = sendHaptic
        self.deliverMovement = deliverMovement
        self.schedule = schedule
        self.onChange = onChange
        self.log = log
    }

    // MARK: - Raw XY state

    private enum RawXYPhase: Equatable {
        /// 0x33 sent, echo not seen yet.
        case arming(attempt: Int)
        /// The mouse echoed 0x33: the next press of the control is tracked by the device.
        case armed
    }

    private struct TrackedHold {
        let cid: UInt16
        var droppedFirstSample = false
        var samples = 0
    }

    /// Diverted controls of this device that can report raw XY (getCidInfo).
    private(set) var rawXYCapableCIDs: Set<UInt16> = []
    /// Controls Mos wants tracked by the device, whatever this device can do.
    private(set) var rawXYRequest: Set<UInt16> = []
    /// Controls whose arm request failed; they stay on the pointer path until they leave
    /// the request (setting off, binding removed) or the device is discovered again.
    private(set) var rejectedCIDs: Set<UInt16> = []
    /// Controls Mos set raw XY on. Absent: Mos never touched their raw XY bit.
    private var rawXYPhases: [UInt16: RawXYPhase] = [:]
    /// Controls the device itself reported with raw XY on although Mos did not set it now:
    /// left over from a Mos that died, or set by another app. Cleared the next time Mos
    /// writes that control. Read from getCidReporting, whose layout is the least certain
    /// part of the research, so it is only ever used to send that one extra "raw XY off".
    private var leftoverRawXY: Set<UInt16> = []
    private var armAttempt = 0
    /// Usually zero or one entry; an array keeps the 125 Hz sample path free of allocations.
    private var trackedHolds: [TrackedHold] = []

    /// At least one control of this device can report movement itself.
    var supportsRawXY: Bool { !rawXYCapableCIDs.isEmpty }

    /// Controls whose next press the device tracks.
    var armedCIDs: Set<UInt16> {
        return Set(rawXYPhases.filter { $0.value == .armed }.keys)
    }

    /// A tracked button is held right now, so raw XY events are expected.
    var hasTrackedHold: Bool { !trackedHolds.isEmpty }

    // MARK: - Raw XY: what Mos wants

    func setRawXYCapableControls(_ cids: Set<UInt16>) {
        guard cids != rawXYCapableCIDs else { return }
        let supported = supportsRawXY
        rawXYCapableCIDs = cids
        if supported != supportsRawXY { onChange() }
    }

    /// Stores the request; nothing is sent until the controls are written or reconciled.
    func setRawXYRequest(_ cids: Set<UInt16>) {
        rawXYRequest = cids
        // A control that left the request gets a fresh attempt when it comes back.
        rejectedCIDs.formIntersection(cids)
    }

    private func wantsRawXY(_ cid: UInt16) -> Bool {
        return rawXYRequest.contains(cid) && rawXYCapableCIDs.contains(cid) && !rejectedCIDs.contains(cid)
    }

    // MARK: - Raw XY: reporting writes

    /// The flags for a divert change of one control, with raw XY folded in. The session
    /// sends them; calling this records the request, so call it exactly once per write.
    func reportingFlags(cid: UInt16, divert: Bool) -> UInt8 {
        let change = nextChange(cid: cid, divert: divert)
        // Whatever goes out next states the raw XY bit Mos wants, so a leftover is settled.
        leftoverRawXY.remove(cid)
        if change == .divertWithRawXY {
            // Re-asserting a control the mouse already confirmed keeps it armed.
            if rawXYPhases[cid] != .armed {
                armAttempt += 1
                let attempt = armAttempt
                rawXYPhases[cid] = .arming(attempt: attempt)
                schedule(Self.acknowledgeTimeout) { [weak self] in
                    self?.armingTimedOut(cid: cid, attempt: attempt)
                }
            }
        } else {
            // A hold in progress stays tracked: the mouse applies the change at the next press.
            rawXYPhases[cid] = nil
        }
        if change != .divert && change != .undivert {
            log(String(format: "raw XY: CID 0x%04X <- flags 0x%02X", cid, change.flags))
        }
        return change.flags
    }

    private func nextChange(cid: UInt16, divert: Bool) -> LogiGestureProtocol.ReportingChange {
        if divert && wantsRawXY(cid) { return .divertWithRawXY }
        let rawXYMayBeOn = rawXYPhases[cid] != nil || leftoverRawXY.contains(cid)
        if rawXYMayBeOn { return divert ? .divertWithoutRawXY : .undivertAndClearRawXY }
        return divert ? .divert : .undivert
    }

    private func write(cid: UInt16, divert: Bool) {
        sendReporting(cid, reportingFlags(cid: cid, divert: divert))
    }

    /// Controls that stay diverted get no write from the session's divert diff. Re-states
    /// the ones whose raw XY state is not the wanted one: the setting was toggled, or the
    /// device reported a leftover.
    func reconcile(diverted: Set<UInt16>) {
        for cid in diverted.sorted() {
            let wants = wantsRawXY(cid)
            let isSet = rawXYPhases[cid] != nil
            if wants != isSet || (!wants && leftoverRawXY.contains(cid)) {
                write(cid: cid, divert: true)
            }
        }
    }

    /// The echo of a setCidReporting request.
    func handleReportingAcknowledgement(cid: UInt16, flags: UInt8) {
        guard case .arming? = rawXYPhases[cid], LogiGestureProtocol.acknowledgesRawXY(flags: flags) else { return }
        rawXYPhases[cid] = .armed
        log(String(format: "raw XY: CID 0x%04X armed", cid))
    }

    /// An HID++ error for setCidReporting. It does not name the control, so every arm
    /// request still waiting counts as refused.
    func handleReportingError() {
        let waiting = rawXYPhases.filter { phase in
            if case .arming = phase.value { return true }
            return false
        }
        for cid in waiting.keys.sorted() {
            rejectArming(cid: cid, reason: "refused by the device")
        }
    }

    private func armingTimedOut(cid: UInt16, attempt: Int) {
        guard rawXYPhases[cid] == .arming(attempt: attempt) else { return }
        rejectArming(cid: cid, reason: "not acknowledged")
    }

    /// Back to the pointer path. Whether the mouse took the request is unknown, so the
    /// control is re-stated as "diverted, raw XY off" rather than left alone.
    private func rejectArming(cid: UInt16, reason: String) {
        log(String(format: "raw XY: CID 0x%04X %@, using pointer movement", cid, reason))
        rejectedCIDs.insert(cid)
        write(cid: cid, divert: true)
    }

    /// What getCidReporting said about a control.
    func noteDeviceReporting(cid: UInt16, reportingFlags: UInt8) {
        if LogiGestureProtocol.reportsRawXY(reportingFlags: reportingFlags) {
            if rawXYPhases[cid] == nil { leftoverRawXY.insert(cid) }
        } else {
            leftoverRawXY.remove(cid)
        }
    }

    /// The divert of a control was lost or taken over from outside: Mos's raw XY state for
    /// it is void. The session re-applies the binding afterwards.
    func forget(cid: UInt16) {
        rawXYPhases[cid] = nil
        trackedHolds.removeAll { $0.cid == cid }
    }

    /// Teardown: gives every control Mos set raw XY on back to the mouse (0x22). The
    /// session undiverts the rest with the plain bytes.
    func disarmAll() {
        for cid in rawXYPhases.keys.sorted() {
            write(cid: cid, divert: false)
        }
        trackedHolds.removeAll()
    }

    // MARK: - Raw XY: holds and movement

    /// A diverted control went down. True when the device tracks this hold: the caller
    /// marks the button event, and movement arrives through `handleRawXY`.
    func buttonDown(cid: UInt16) -> Bool {
        trackedHolds.removeAll { $0.cid == cid }
        guard rawXYPhases[cid] == .armed else { return false }
        trackedHolds.append(TrackedHold(cid: cid))
        return true
    }

    func buttonUp(cid: UInt16) {
        guard let index = trackedHolds.firstIndex(where: { $0.cid == cid }) else { return }
        let hold = trackedHolds.remove(at: index)
        log(String(format: "raw XY: CID 0x%04X released after %d samples", cid, hold.samples))
    }

    /// One raw XY event, in sensor counts. Runs about 125 times a second during a hold.
    func handleRawXY(deltaX: Int, deltaY: Int) {
        for index in trackedHolds.indices {
            trackedHolds[index].samples += 1
            guard trackedHolds[index].droppedFirstSample else {
                trackedHolds[index].droppedFirstSample = true
                continue
            }
            if deltaX != 0 || deltaY != 0 {
                deliverMovement(trackedHolds[index].cid, deltaX, deltaY)
            }
        }
    }

    // MARK: - Haptics

    private(set) var hapticFeatureIndex: UInt8?
    /// getState bit0; nil until read.
    private(set) var hapticsEnabled: Bool?
    /// getCapabilities waveform mask; nil until read.
    private(set) var hapticWaveformMask: UInt32?

    /// The mouse has a haptic motor Mos can pulse.
    var supportsHaptics: Bool { hapticFeatureIndex != nil }

    /// Called when the feature index of 0x19B0 is known (or known to be missing).
    func setHapticFeature(index: UInt8?) {
        guard index != hapticFeatureIndex else { return }
        hapticFeatureIndex = index
        hapticsEnabled = nil
        hapticWaveformMask = nil
        onChange()
        refreshHaptics()
    }

    /// Reads what is not known yet, and the on/off state again: the user can change it.
    func refreshHaptics() {
        guard hapticFeatureIndex != nil else { return }
        if hapticWaveformMask == nil {
            sendHaptic(LogiGestureProtocol.hapticCapabilitiesFunction, [])
        }
        sendHaptic(LogiGestureProtocol.hapticGetStateFunction, [])
    }

    /// A response on the haptic feature index (software id already matched).
    func handleHapticResponse(functionId: UInt8, report: [UInt8]) {
        switch functionId {
        case LogiGestureProtocol.hapticCapabilitiesFunction:
            guard let mask = LogiGestureProtocol.hapticWaveformMask(report) else { return }
            hapticWaveformMask = mask
        case LogiGestureProtocol.hapticGetStateFunction:
            guard let enabled = LogiGestureProtocol.hapticsEnabled(report) else { return }
            hapticsEnabled = enabled
        default:
            return  // play acknowledgement, or somebody else's setState
        }
    }

    /// Plays the cue when the mouse can and the user has haptics on. Returns whether a
    /// pulse was sent.
    @discardableResult
    func play(_ cue: MouseGestureHapticCue) -> Bool {
        guard hapticFeatureIndex != nil else { return false }
        guard let enabled = hapticsEnabled, let mask = hapticWaveformMask else {
            // An answer got lost: ask again and skip this pulse.
            refreshHaptics()
            return false
        }
        let waveform = LogiGestureProtocol.waveform(for: cue)
        guard enabled, LogiGestureProtocol.supports(waveform: waveform, mask: mask) else { return false }
        sendHaptic(LogiGestureProtocol.hapticPlayFunction, [waveform])
        return true
    }
}
