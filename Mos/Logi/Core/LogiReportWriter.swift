//
//  LogiReportWriter.swift
//  Mos
//
//  Sends output reports to one HID device on a serial queue of its own, in the order they
//  were given.
//
//  Why: `IOHIDDeviceSetReport` returns only when the device has taken the report. Over
//  Bluetooth that is 15 to 29 ms (measured on an MX Master 4, 2026-11-11: about 55 writes at
//  every connect, 320 ms for the first 20). Called on the main thread it held up everything
//  else that runs there for that long, the event taps included: scrolling, keys and buttons
//  of the whole system waited for the mouse.
//
//  Nothing waited for the call itself: the answer to a request comes back as an input report
//  on the main run loop, as before, and only the call's result went to the diagnostics log.
//  So the session queues the report here and goes on. The order of the reports of one device
//  is the order they were queued in (one writer per session, one serial queue per writer).
//
//  Before a device is closed or the app exits, `drain` waits for what is still queued: the
//  requests that give a mouse its buttons back at teardown must have gone out.
//

import Foundation
import IOKit

final class LogiReportWriter {

    /// What became of one report.
    struct Outcome: Equatable {
        /// The device call's result.
        let result: IOReturn
        /// Nanoseconds the device call took.
        let duration: UInt64
        /// Nanoseconds the report waited in the queue behind earlier ones.
        let waited: UInt64
    }

    /// The device call: `IOHIDDeviceSetReport` in the app, a recorder in tests. Runs on the
    /// writer's queue, never on the main thread.
    typealias Send = (_ report: [UInt8]) -> IOReturn

    private let queue: DispatchQueue
    private let send: Send
    /// Carries an outcome back to where the session lives (the main queue).
    private let deliver: (@escaping () -> Void) -> Void
    /// Monotonic nanoseconds.
    private let clock: () -> UInt64

    init(
        label: String,
        send: @escaping Send,
        deliver: @escaping (@escaping () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) },
        clock: @escaping () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
    ) {
        // User-initiated: a haptic cue at the moment a gesture locks in is one of these writes.
        queue = DispatchQueue(label: label, qos: .userInitiated)
        self.send = send
        self.deliver = deliver
        self.clock = clock
    }

    /// Queues `report` and returns at once. `completion` gets the outcome through `deliver`
    /// (the main queue) after the device call.
    func write(_ report: [UInt8], completion: @escaping (Outcome) -> Void) {
        let queuedAt = clock()
        queue.async { [send, deliver, clock] in
            let started = clock()
            let result = send(report)
            let ended = clock()
            let outcome = Outcome(result: result, duration: ended &- started, waited: started &- queuedAt)
            deliver { completion(outcome) }
        }
    }

    /// Runs `block` (through `deliver`, the main queue) once every report queued so far has
    /// gone out and its outcome was delivered. Does not wait.
    func afterQueued(_ block: @escaping () -> Void) {
        queue.async { [deliver] in
            deliver(block)
        }
    }

    /// Waits until every report queued so far has gone out, at most `timeout` seconds.
    /// The outcomes are delivered afterwards, as usual.
    /// - Returns: false when the timeout passed first (a device that does not answer).
    @discardableResult
    func drain(timeout: TimeInterval) -> Bool {
        let done = DispatchSemaphore(value: 0)
        queue.async { done.signal() }
        return done.wait(timeout: .now() + timeout) == .success
    }
}
