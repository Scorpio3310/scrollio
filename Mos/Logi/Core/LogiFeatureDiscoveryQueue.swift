//
//  LogiFeatureDiscoveryQueue.swift
//  Mos
//
//  The getFeature requests (IRoot, feature index 0, function 0) of one session that wait
//  for their answer, oldest first.
//
//  An IRoot answer names no feature: it only carries the index. A device answers its
//  requests in the order they were sent, so an answer belongs to the oldest request still
//  waiting for that device (BLE: 0xFF, receiver: the slot). Only function 0 with this
//  app's own software id is such an answer: a ping answer is function 1, and other HID++
//  clients (Logi Options+) and the receiver slot pings (0x0A) use other software ids.
//  A HID++ error that refuses one of these requests fails the oldest one the same way;
//  a timeout fails only its own request. The session owns the timers and sends.
//
//  Main thread only, like the session.
//

import Foundation

struct LogiFeatureDiscoveryQueue {

    typealias Completion = (UInt8?) -> Void

    struct Entry {
        /// Identifies the request for its timeout.
        let token: Int
        /// report[1] the request went out with: 0xFF for BLE, the slot behind a receiver.
        let deviceIndex: UInt8
        let featureId: UInt16
        /// The feature index, or nil when the device does not have the feature, refused
        /// the request or did not answer.
        let completion: Completion
    }

    /// The software id in the low nibble of byte 3 of this app's requests.
    let softwareId: UInt8

    private(set) var entries: [Entry] = []
    private var nextToken = 1

    init(softwareId: UInt8) {
        self.softwareId = softwareId
    }

    var isEmpty: Bool { entries.isEmpty }
    var count: Int { entries.count }

    /// Adds a request that was just sent. Returns its token.
    @discardableResult
    mutating func append(deviceIndex: UInt8, featureId: UInt16, completion: @escaping Completion) -> Int {
        let token = nextToken
        nextToken += 1
        entries.append(Entry(token: token, deviceIndex: deviceIndex, featureId: featureId, completion: completion))
        return token
    }

    /// The feature index a report answers a getFeature with (0 = the device does not have
    /// the feature), or nil when the report is no answer to a getFeature of this app.
    /// Bytes: [reportId, deviceIndex, 0x00, fn << 4 | swid, index, ...].
    static func getFeatureAnswerIndex<Bytes: RandomAccessCollection>(_ report: Bytes, softwareId: UInt8) -> UInt8?
    where Bytes.Element == UInt8, Bytes.Index == Int {
        guard report.count >= 5 else { return nil }
        let base = report.startIndex
        let functionByte = report[base + 3]
        guard report[base + 2] == 0x00,
              functionByte >> 4 == 0,
              functionByte & 0x0F == softwareId else { return nil }
        return report[base + 4]
    }

    /// Whether a HID++ error refuses a getFeature of this app: the request it names is
    /// feature index 0, function 0, with this app's software id. Works for both layouts,
    /// 2.0 [.., 0xFF, featureIndex, fn|swid, code] and 1.0 [.., 0x8F, featureIndex, fn|swid, code].
    static func errorRefusesGetFeature(originalFeatureIndex: UInt8, originalFunctionByte: UInt8, softwareId: UInt8) -> Bool {
        return originalFeatureIndex == 0x00
            && originalFunctionByte >> 4 == 0
            && originalFunctionByte & 0x0F == softwareId
    }

    /// Takes the request a report answers: the oldest one sent to the report's device.
    /// nil when the report is no getFeature answer of this app or nothing waits for it.
    /// `featureIndex` is nil when the device does not have the feature.
    mutating func takeAnswer<Bytes: RandomAccessCollection>(_ report: Bytes) -> (entry: Entry, featureIndex: UInt8?)?
    where Bytes.Element == UInt8, Bytes.Index == Int {
        guard let index = Self.getFeatureAnswerIndex(report, softwareId: softwareId),
              let entry = removeOldest(deviceIndex: report[report.startIndex + 1]) else { return nil }
        return (entry, index == 0 ? nil : index)
    }

    /// Takes the request a HID++ error refuses: the oldest one sent to that device, when
    /// the error names a getFeature of this app. nil otherwise.
    mutating func takeRefused(deviceIndex: UInt8, originalFeatureIndex: UInt8, originalFunctionByte: UInt8) -> Entry? {
        guard Self.errorRefusesGetFeature(
            originalFeatureIndex: originalFeatureIndex,
            originalFunctionByte: originalFunctionByte,
            softwareId: softwareId
        ) else { return nil }
        return removeOldest(deviceIndex: deviceIndex)
    }

    /// A timeout: removes only that request, if it still waits.
    mutating func remove(token: Int) -> Entry? {
        guard let i = entries.firstIndex(where: { $0.token == token }) else { return nil }
        return entries.remove(at: i)
    }

    /// Removes every request (teardown, a new discovery that replaces the old one).
    @discardableResult
    mutating func removeAll() -> [Entry] {
        let all = entries
        entries.removeAll()
        return all
    }

    private mutating func removeOldest(deviceIndex: UInt8) -> Entry? {
        guard let i = entries.firstIndex(where: { $0.deviceIndex == deviceIndex }) else { return nil }
        return entries.remove(at: i)
    }
}
