//
//  LogiReceiverConnectionReports.swift
//  Scrollio
//
//  The exchange with a receiver that comes before its slots are pinged: its reporting flags
//  (HID++ 1.0 register 0x00) are read, and "wireless notifications" is switched on when it
//  is off.
//
//  Only with that flag does a receiver say when a device connects or disconnects
//  (notifications 0x41 and 0x40). It is off when the receiver gets power, and every program
//  that wants the reports sets it (Logi Options+ and Solaar do). Scrollio pings the slots
//  once and used to leave the flag alone: a mouse that was asleep, switched off or out of
//  range at that moment stayed unseen until the app started again, and a mouse that was
//  switched off and on lost its buttons.
//
//  Source: Logitech, "HID++ 1.0 specification for Unifying receivers", 3.1, 3.2 and 4.1.
//
//  This type only decides: what is sent next, and when the slot pings go out. The session
//  sends and listens. No clock and no device in here, so that the order can be tested.
//

import Foundation

struct LogiReceiverConnectionReports: Equatable {

    /// What the session does next.
    enum Step: Equatable {
        case nothing
        /// Write these three bytes to the receiver's register 0x00.
        case write([UInt8])
        /// The exchange is over, or took too long: ping the slots now. `outcome` is for the log.
        case pingSlots(outcome: String)
        /// An answer that came after the slots were pinged: only the line for the log.
        case note(outcome: String)
    }

    /// Bit 0 of the second byte of register 0x00: wireless notifications.
    static let wirelessNotificationsBit: UInt8 = 0x01

    private enum Waiting: Equatable {
        case forNothing
        case forFlags
        case forWriteTaken
    }

    private var waiting: Waiting = .forNothing
    /// The slot pings went out (or nothing was started): they go out once per start.
    private var slotsPinged = true

    /// An enumeration starts. The session sends the read of register 0x00 and holds the
    /// slot pings until a step says `pingSlots`.
    mutating func start() {
        waiting = .forFlags
        slotsPinged = false
    }

    /// The receiver answered the read with the three bytes of the register.
    mutating func flagsRead(_ flags: [UInt8]) -> Step {
        guard waiting == .forFlags else { return .nothing }
        guard let value = Self.flagsToWrite(current: flags) else {
            waiting = .forNothing
            return finished("already on")
        }
        waiting = .forWriteTaken
        return .write(value)
    }

    /// The receiver took the write.
    mutating func writeTaken() -> Step {
        guard waiting == .forWriteTaken else { return .nothing }
        waiting = .forNothing
        return finished("were off, switched on")
    }

    /// The receiver refused the read or the write (a HID++ 1.0 error).
    mutating func refused(errorName: String) -> Step {
        guard waiting != .forNothing else { return .nothing }
        let request = waiting == .forFlags ? "read" : "write"
        waiting = .forNothing
        return finished("not switched on, the receiver refused the \(request) (\(errorName)); a device that connects later may go unseen")
    }

    /// No answer within the wait: the slots are pinged anyway, so that a receiver that says
    /// nothing about its flags still shows its devices. An answer that comes later is still
    /// acted on.
    mutating func waitedLongEnough() -> Step {
        guard !slotsPinged else { return .nothing }
        slotsPinged = true
        return .pingSlots(outcome: "no answer about them yet; a device that connects later may go unseen")
    }

    /// The session was torn down.
    mutating func cancel() {
        self = LogiReceiverConnectionReports()
    }

    private mutating func finished(_ outcome: String) -> Step {
        guard !slotsPinged else { return .note(outcome: outcome) }
        slotsPinged = true
        return .pingSlots(outcome: outcome)
    }

    /// What to write so that the receiver reports connections; nil when it already does, or
    /// when the answer is not the register's three bytes. Only the one bit is set: the other
    /// flags belong to whoever set them (Logi Options+, Solaar) and are written back as read.
    static func flagsToWrite(current flags: [UInt8]) -> [UInt8]? {
        guard flags.count == 3, flags[1] & wirelessNotificationsBit == 0 else { return nil }
        return [flags[0], flags[1] | wirelessNotificationsBit, flags[2]]
    }
}
