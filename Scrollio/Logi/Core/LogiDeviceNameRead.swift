//
//  LogiDeviceNameRead.swift
//  Scrollio
//
//  Reads a device's own name from HID++ feature 0x0005 (Device Name and Type): function 0
//  gives the length, function 1 gives the name in pieces from a character index on. It is
//  the model name the device carries ("MX Master 3S"), the same over Bluetooth and through
//  any receiver, and not a name the user gave the device in the Bluetooth settings.
//
//  Reading only; the session sends the requests and feeds the answers in. The functions are
//  the ones the diagnostics window lists for 0x0005 (GetCount 0, GetName 1 with a character
//  index, GetType 2, which the session already used). The answer to function 0 has the
//  length in byte 4; the answer to function 1 has the characters from byte 4 on, as many as
//  fit in the report (the payload of every HID++ 2.0 answer starts there). Not seen on a
//  device yet: an answer that does not fit ends the read without a name.
//

import Foundation

struct LogiDeviceNameRead: Equatable {

    static let lengthFunction: UInt8 = 0
    static let nameFunction: UInt8 = 1
    /// Longer than any name a device carries; a length above this is a misread answer.
    static let maximumLength = 64

    /// What to do after an answer.
    enum Step: Equatable {
        /// Ask function 1 for the characters from this index on.
        case requestPiece(from: UInt8)
        /// The whole name arrived.
        case finished(String)
        /// The answer made no sense: the read ends without a name.
        case failed
    }

    private(set) var expectedLength = 0
    private(set) var bytes: [UInt8] = []

    /// The answer to function 0 (the length).
    mutating func handleLength<Bytes: RandomAccessCollection>(_ report: Bytes) -> Step
    where Bytes.Element == UInt8, Bytes.Index == Int {
        guard report.count >= 5 else { return .failed }
        let length = Int(report[report.startIndex + 4])
        guard length > 0, length <= Self.maximumLength else { return .failed }
        expectedLength = length
        bytes.removeAll()
        return .requestPiece(from: 0)
    }

    /// An answer to function 1 (a piece of the name).
    mutating func handlePiece<Bytes: RandomAccessCollection>(_ report: Bytes) -> Step
    where Bytes.Element == UInt8, Bytes.Index == Int {
        guard expectedLength > 0, report.count > 4 else { return .failed }
        let missing = expectedLength - bytes.count
        let piece = report.dropFirst(4).prefix(missing).prefix { $0 != 0 }
        // An empty piece would ask for the same index for ever.
        guard !piece.isEmpty else { return finish() ?? .failed }
        bytes.append(contentsOf: piece)
        if bytes.count >= expectedLength {
            return finish() ?? .failed
        }
        return .requestPiece(from: UInt8(bytes.count))
    }

    private func finish() -> Step? {
        guard !bytes.isEmpty, let text = String(bytes: bytes, encoding: .utf8) else { return nil }
        // Printable characters only: the name goes into the interface and the log.
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F }) else {
            return nil
        }
        return .finished(name)
    }
}
