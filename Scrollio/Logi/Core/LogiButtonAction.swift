//
//  LogiButtonAction.swift
//  Scrollio
//
//  The "Logitech Mouse" actions a button or a gesture can run on a mouse, by the name a
//  binding stores, and the bookkeeping of the ones that read the mouse before they write.
//
//  These actions write to the mouse whatever "Let Scrollio manage this mouse" says: the user
//  pressed a button for exactly that. Each write is one line in the system log
//  (LogiDeviceSession.noteActionWrite).
//

import Foundation

/// A "Logitech Mouse" action Scrollio still runs.
enum LogiButtonAction: Equatable {
    case smartShiftToggle
    case dpiCycleUp
    case dpiCycleDown
    /// Easy-Switch to a host, 0-based.
    case host(UInt8)
    case pointerSpeedCycle

    /// Actions earlier versions had and bindings may still name. They are not run any more:
    /// each flipped a state of the mouse that nothing showed and nothing put back when
    /// Scrollio paused or quit ("Toggle Thumb Wheel" left the thumb wheel dead until the
    /// mouse was switched off and on).
    static let removedNames: Set<String> = [
        "logiHiResScrollToggle",
        "logiScrollInvertToggle",
        "logiThumbWheelToggle",
    ]

    /// nil for a name that is unknown or removed: the binding then does nothing.
    init?(name: String) {
        switch name {
        case "logiSmartShiftToggle": self = .smartShiftToggle
        case "logiDPICycleUp": self = .dpiCycleUp
        case "logiDPICycleDown": self = .dpiCycleDown
        case "logiHost1": self = .host(0)
        case "logiHost2": self = .host(1)
        case "logiHost3": self = .host(2)
        case "logiPointerSpeedCycle": self = .pointerSpeedCycle
        default: return nil
        }
    }
}

/// The button actions that first read a value from the mouse and write when the answer
/// comes, each with the time until which that answer may still run it.
///
/// Without the limit a press whose read got no answer stayed armed for the whole connection:
/// minutes later some other read of the same value was answered (the Mouse pane opening, the
/// status menu) and the action ran by itself.
struct LogiPendingActions: Equatable {

    enum Kind: Hashable {
        /// DPI cycle, waiting for the mouse's list of DPI values.
        case dpiList
        /// DPI cycle, waiting for the current DPI.
        case dpiCurrent
        /// Pointer speed cycle, waiting for the current speed.
        case pointerSpeed
    }

    /// How long an answer may take: the same 2 s the wheel and the gesture code give the mouse.
    static let lifetime: TimeInterval = 2.0

    private var deadlines: [Kind: Date] = [:]

    /// The read for `kind` was just sent.
    mutating func arm(_ kind: Kind, now: Date) {
        deadlines[kind] = now.addingTimeInterval(Self.lifetime)
    }

    /// An answer for `kind` arrived: true when the action is still waiting for it. Either
    /// way it waits no longer.
    mutating func take(_ kind: Kind, now: Date) -> Bool {
        guard let deadline = deadlines.removeValue(forKey: kind) else { return false }
        return now <= deadline
    }

    func isArmed(_ kind: Kind) -> Bool {
        return deadlines[kind] != nil
    }

    mutating func cancelAll() {
        deadlines.removeAll()
    }
}
