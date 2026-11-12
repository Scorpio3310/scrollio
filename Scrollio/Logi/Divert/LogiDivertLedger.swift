//
//  LogiDivertLedger.swift
//  Scrollio
//
//  What Scrollio believes about the diverted buttons of one mouse (one receiver slot), and
//  the rules that keep that belief true. `LogiDeviceSession` holds one per slot and does the
//  sending; nothing here touches a device, so a unit test can drive every step.
//
//  The rule of the project for buttons: a button is diverted for a binding and while a
//  button is being recorded, and every button Scrollio diverted is given back when Scrollio
//  pauses or quits. That only works while the ledger never forgets a button it diverted
//  without evidence that the mouse let go of it. The evidence is an answer to
//  GetControlReporting, and an answer is evidence only when it is newer than every write of
//  Scrollio for that control: a mouse answers its requests in the order they were sent, so the
//  answer to a query that went out before a write tells the state before that write.
//
//  Main thread only, like the session.
//

import Foundation

struct LogiDivertLedger: Equatable {

    /// What a usage pass makes of the diverts.
    enum Pass: Equatable {
        /// The buttons that have a binding (the usage registry's aggregate).
        case bindings
        /// Every button that can be diverted: a button is being recorded.
        case everyControl
    }

    /// While a button is being recorded every pass keeps every control diverted, whoever
    /// asked for the pass (a binding that changed, the end of a re-read of the buttons'
    /// state, a divert another app cleared). A pass for the bindings would give the
    /// unbound controls back under the recorder's hands.
    static func pass(whileRecording recording: Bool) -> Pass {
        return recording ? .everyControl : .bindings
    }

    /// The set the last pass wanted diverted.
    var lastApplied: Set<UInt16> = []
    /// Controls Scrollio sent "divert on" for and has not given back since.
    var diverted: Set<UInt16> = []
    /// Controls Scrollio wrote since their GetControlReporting query went out: the answer
    /// to that query (already in hand, or still on its way) is older than the write.
    private(set) var writtenSinceQuery: Set<UInt16> = []
    /// SetControlReporting requests whose echo has not come back yet.
    private(set) var pendingAcks = LogiPendingReportingAcks()

    // MARK: - Writes and queries, in the order they are sent

    /// A SetControlReporting for `cid` was queued.
    /// - Parameter countsAsDiverted: false for a write that must not change what Scrollio
    ///   believes is diverted (none today; the session's writes all count).
    mutating func noteWrite(cid: UInt16, divert: Bool, countsAsDiverted: Bool = true) {
        writtenSinceQuery.insert(cid)
        guard countsAsDiverted else { return }
        if divert {
            diverted.insert(cid)
        } else {
            diverted.remove(cid)
        }
    }

    /// A GetControlReporting for `cid` was queued: its answer will tell the state after
    /// every write so far.
    mutating func noteQuerySent(cid: UInt16) {
        writtenSinceQuery.remove(cid)
    }

    /// Whether what is known about `cid` from GetControlReporting is older than a write of
    /// Scrollio, and so says nothing about the control's state now.
    func answerPredatesAWrite(cid: UInt16) -> Bool {
        return writtenSinceQuery.contains(cid)
    }

    // MARK: - After a re-read of the buttons' state

    /// The controls of `lastApplied` that a re-read found not diverted: the mouse dropped
    /// the divert (it slept, another app cleared it). They are forgotten here, without a
    /// write. A control Scrollio wrote since its query went out is never among them: its
    /// answer is older than the write.
    @discardableResult
    mutating func dropLost(queriedControls: [LogiDeviceSession.QueriedControlState]) -> Set<UInt16> {
        let temporaryDivert: UInt8 = 0x01
        let lost = Set(queriedControls.compactMap { control -> UInt16? in
            guard lastApplied.contains(control.cid),
                  control.reportingQueried,
                  control.reportingFlags & temporaryDivert == 0,
                  !writtenSinceQuery.contains(control.cid) else {
                return nil
            }
            return control.cid
        })
        lastApplied.subtract(lost)
        diverted.subtract(lost)
        return lost
    }

    // MARK: - Letting go

    /// Everything to give back when Scrollio lets go of the mouse (Pause, Quit, sleep): what
    /// it diverted and, to be on the safe side, what the last pass wanted diverted. One
    /// write too many gives a button back that already was; one too few leaves a button dead.
    var toGiveBack: Set<UInt16> {
        return diverted.union(lastApplied)
    }

    /// The mouse is discovered anew, or is gone: nothing is believed any more.
    mutating func forgetDiverts() {
        lastApplied.removeAll()
        diverted.removeAll()
        pendingAcks.removeAll()
    }

    // MARK: - Echoes of Scrollio's own writes

    mutating func expectAck(cid: UInt16, flags: UInt8, targetCID: UInt16, now: Date) {
        pendingAcks.expect(cid: cid, flags: flags, targetCID: targetCID, now: now)
    }

    /// Whether a SetControlReporting echo is the echo of a write of Scrollio (and takes that
    /// write off the list). An echo that is not is another app's write.
    mutating func consumeAck(cid: UInt16, flags: UInt8, targetCID: UInt16, now: Date) -> Bool {
        return pendingAcks.consume(cid: cid, flags: flags, targetCID: targetCID, now: now)
    }

    mutating func forgetPendingAcks() {
        pendingAcks.removeAll()
    }
}

/// The SetControlReporting requests of Scrollio that wait for their echo, per control, oldest
/// first. The mouse echoes every such request, also another app's (Logi Options+): an echo
/// that matches none of these is somebody else's write.
///
/// One entry per control was not enough: "give back" and then "divert" for the same control
/// within the answer time (a binding removed and put back with Undo; over Bluetooth an
/// answer can take a few hundred milliseconds after an idle time) overwrote the first entry,
/// and the echo of Scrollio's own "give back" then counted as another app's. Two of those
/// within 30 s mark the control as taken over by Logi Options+.
struct LogiPendingReportingAcks: Equatable {

    struct Entry: Equatable {
        let flags: UInt8
        let targetCID: UInt16
        let expiresAt: Date
    }

    /// How long an echo may take. The session used the same 2 s for its single entry.
    static let lifetime: TimeInterval = 2.0
    /// More unanswered writes than this for one control are not kept (a mouse that does not
    /// answer at all): the oldest go first.
    static let maximumPerControl = 8

    private(set) var entries: [UInt16: [Entry]] = [:]

    var isEmpty: Bool { entries.isEmpty }

    mutating func expect(cid: UInt16, flags: UInt8, targetCID: UInt16, now: Date) {
        var list = (entries[cid] ?? []).filter { $0.expiresAt >= now }
        list.append(Entry(flags: flags, targetCID: targetCID, expiresAt: now.addingTimeInterval(Self.lifetime)))
        if list.count > Self.maximumPerControl {
            list.removeFirst(list.count - Self.maximumPerControl)
        }
        entries[cid] = list
    }

    /// Takes the oldest live entry for `cid` with these flags and target. False when there
    /// is none: the echo belongs to another app's write.
    mutating func consume(cid: UInt16, flags: UInt8, targetCID: UInt16, now: Date) -> Bool {
        var list = (entries[cid] ?? []).filter { $0.expiresAt >= now }
        defer { entries[cid] = list.isEmpty ? nil : list }
        guard let index = list.firstIndex(where: { $0.flags == flags && $0.targetCID == targetCID }) else {
            return false
        }
        list.remove(at: index)
        return true
    }

    mutating func removeAll() {
        entries.removeAll()
    }
}
