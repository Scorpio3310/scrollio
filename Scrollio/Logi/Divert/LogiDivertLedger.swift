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
//  A divert counts as taken only when the mouse echoed it. A write the mouse did not take
//  (asleep, out of range, busy; refused on the way or by the receiver) gets no echo, and the
//  session only logs the refusal. The next re-read then finds the button not diverted: that
//  is no evidence that another app cleared it, so the control is not counted as lost (two of
//  those within 30 s used to mark it as taken over by Logi Options+ until Pause, sleep or a
//  reconnect) and the pass that ends the re-read writes it again (`heldBack`).
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

    /// The set the last pass wanted diverted, less the controls held back (`heldBack`). The
    /// session also sets it directly (a slot that disconnects, a rediscovery): a control set
    /// here is no longer held back.
    var lastApplied: Set<UInt16> = [] {
        didSet { heldBack.subtract(lastApplied) }
    }
    /// Controls Scrollio sent "divert on" for and has not given back since. A control the
    /// session takes out of here (it forgets the slot, another app cleared the divert) no
    /// longer waits for an echo and is no longer held back.
    var diverted: Set<UInt16> = [] {
        didSet {
            unacknowledged.formIntersection(diverted)
            heldBack.formIntersection(diverted)
            if !refusedInARow.isEmpty {
                refusedInARow = refusedInARow.filter { diverted.contains($0.key) }
            }
        }
    }
    /// Controls Scrollio wrote since their GetControlReporting query went out: the answer
    /// to that query (already in hand, or still on its way) is older than the write.
    private(set) var writtenSinceQuery: Set<UInt16> = []
    /// SetControlReporting requests whose echo has not come back yet.
    private(set) var pendingAcks = LogiPendingReportingAcks()
    /// Controls whose latest write of Scrollio was "divert on" and that the mouse has not
    /// echoed since: whether the mouse took the divert is not known.
    private(set) var unacknowledged: Set<UInt16> = []
    /// Controls of the last pass left out of `lastApplied` because their GetControlReporting
    /// went out while their divert was unacknowledged. The mouse answers in order, so an echo
    /// comes before that answer if it comes at all, and puts the control back. Without one
    /// the answer "not diverted" is the mouse's refusal, not another app's doing: `dropLost`
    /// does not see the control, and the pass that ends the re-read writes it again, once
    /// per re-read (a discovery, or the Buttons pane at most every 10 s).
    private(set) var heldBack: Set<UInt16> = []
    /// Per control: how many diverts of Scrollio's in a row the mouse did not take, each held
    /// back and written again. An echo of the divert or a give-back starts it again. At
    /// `refusalsWorthALine` one line goes to the log; a binding the mouse refuses every
    /// time is otherwise written again at every re-read with no word.
    private(set) var refusedInARow: [UInt16: Int] = [:]
    static let refusalsWorthALine = 3
    /// Controls a re-read found dropped (`dropLost`), until their next write or query: a
    /// divert of one of them is a divert the mouse had dropped, written again.
    private(set) var droppedAtReRead: Set<UInt16> = []

    /// Where the ledger's lines go: the `logi` category of the system log. Tests set their own.
    static var log: (String) -> Void = { LogiSystemLog.note($0) }
    /// Told when a divert the mouse did not have is written again: one held back, or one a
    /// re-read found dropped. Its observer (`LogiUsageBootstrap.ButtonsReadAgain`) asks for
    /// one more re-read a few seconds later. Tests set their own.
    static var announceWrittenAgain: () -> Void = {
        NotificationCenter.default.post(name: LogiCenter.divertWrittenAgain, object: nil)
    }

    /// The line for a divert the mouse did not take `times` times in a row.
    static func keepsRefusingLine(cid: UInt16, times: Int) -> String {
        return String(format: "Button 0x%04X ", cid) + LogiCIDDirectory.name(forCID: cid)
            + ": the mouse did not take its divert \(times) times in a row (no echo by the time the buttons "
            + "were checked); it is written again each time Scrollio checks the buttons, and until the mouse "
            + "takes it the button does what it does without Scrollio"
    }

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
    /// every write so far. A control whose divert the mouse has not echoed yet is held back
    /// from `lastApplied` until the echo comes.
    mutating func noteQuerySent(cid: UInt16) {
        writtenSinceQuery.remove(cid)
        droppedAtReRead.remove(cid)
        if unacknowledged.contains(cid), lastApplied.contains(cid) {
            lastApplied.remove(cid)
            heldBack.insert(cid)
        }
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
    /// answer is older than the write. Nor is one whose divert the mouse never echoed: it
    /// is held back (`noteQuerySent`), not in `lastApplied`.
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
        droppedAtReRead.formUnion(lost)
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
        unacknowledged.removeAll()
        heldBack.removeAll()
        refusedInARow.removeAll()
        droppedAtReRead.removeAll()
    }

    // MARK: - Echoes of Scrollio's own writes

    /// A SetControlReporting of Scrollio is on its way (the session calls this right before
    /// `noteWrite`). Until its echo comes, a divert is not known to be taken. A divert of a
    /// control held back is the one the mouse did not take, written again; one of a control
    /// a re-read found dropped is the one the mouse dropped. Either is announced
    /// (`announceWrittenAgain`).
    mutating func expectAck(cid: UInt16, flags: UInt8, targetCID: UInt16, now: Date) {
        pendingAcks.expect(cid: cid, flags: flags, targetCID: targetCID, now: now)
        let dropped = droppedAtReRead.remove(cid) != nil
        switch Self.divert(statedBy: flags) {
        case true?:
            let notTaken = heldBack.contains(cid)
            if notTaken {
                let refused = (refusedInARow[cid] ?? 0) + 1
                refusedInARow[cid] = refused
                if refused == Self.refusalsWorthALine {
                    Self.log(Self.keepsRefusingLine(cid: cid, times: refused))
                }
            }
            if notTaken || dropped {
                Self.announceWrittenAgain()
            }
            unacknowledged.insert(cid)
        case false?:
            unacknowledged.remove(cid)
            heldBack.remove(cid)
            refusedInARow[cid] = nil
        case nil:
            break
        }
    }

    /// Whether a SetControlReporting echo is the echo of a write of Scrollio (and takes that
    /// write off the list). An echo that is not is another app's write. The echo of a divert
    /// of Scrollio's shows that the mouse took it: a control held back goes back into
    /// `lastApplied`. Another app's echo never does.
    ///
    /// Nor does the echo of a divert while a "give back" of Scrollio's for the control is
    /// still on its way: the mouse answers in order, so that echo may be of a divert written
    /// before the give-back (divert, give back, divert again within the answer time), and it
    /// tells nothing of the divert written after it. The echo of that last divert counts.
    mutating func consumeAck(cid: UInt16, flags: UInt8, targetCID: UInt16, now: Date) -> Bool {
        guard pendingAcks.consume(cid: cid, flags: flags, targetCID: targetCID, now: now) else {
            return false
        }
        let givenBackSince = pendingAcks.entries[cid]?.contains { Self.divert(statedBy: $0.flags) == false } ?? false
        if Self.divert(statedBy: flags) == true, !givenBackSince, unacknowledged.remove(cid) != nil {
            refusedInARow[cid] = nil
            if heldBack.remove(cid) != nil {
                lastApplied.insert(cid)
            }
        }
        return true
    }

    /// What a SetControlReporting with these flags does to the divert: sets it, clears it,
    /// or (without the "divert valid" bit) leaves it as it is.
    static func divert(statedBy flags: UInt8) -> Bool? {
        guard flags & LogiGestureProtocol.flagDivertValid != 0 else { return nil }
        return flags & LogiGestureProtocol.flagDivert != 0
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
