//
//  LogiReviewFixesTests.swift
//  MosTests
//
//  Regression tests for the fixes of the Scrollio/Logi review (2026-11-11): getFeature answers
//  matched in request order (replayed report bytes), the controllers rebuilt after a
//  receiver sweep, the feature index cache dropped on "invalid index" errors, a failed
//  IOHIDManagerOpen, and the diagnostics spinner. Nothing here opens a HID device.
//

import XCTest
import IOKit
@testable import Scrollio_Debug

// MARK: - getFeature answers (C)

final class LogiFeatureDiscoveryQueueTests: XCTestCase {

    private let swid = LogiDeviceSession.hidppSoftwareId

    /// An IRoot report as it arrives: [0x11, deviceIndex, 0x00, fn << 4 | swid, payload..., 0...].
    private func iRoot(device: UInt8 = 0xFF, function: UInt8, softwareId: UInt8, _ payload: [UInt8]) -> [UInt8] {
        var bytes: [UInt8] = [0x11, device, 0x00, function << 4 | softwareId] + payload
        bytes += [UInt8](repeating: 0, count: max(0, 20 - bytes.count))
        return bytes
    }

    /// getFeature answer: index (0 = not present), type, version.
    private func answer(_ index: UInt8, device: UInt8 = 0xFF, softwareId: UInt8? = nil) -> [UInt8] {
        return iRoot(device: device, function: 0, softwareId: softwareId ?? swid, [index, 0x00, 0x00])
    }

    /// The MX Master 4 echoes the app's software id: its haptics getState answer this
    /// morning was 11 FF 0B 11 00 64 00 (fn1, swid 1). The queue matches on that id.
    func testTheMouseEchoesTheAppsSoftwareId() {
        let haptics: [UInt8] = [0x11, 0xFF, 0x0B, 0x11, 0x00, 0x64, 0x00]
        XCTAssertEqual(haptics[3] & 0x0F, swid)
        XCTAssertEqual(LogiFeatureDiscoveryQueue(softwareId: swid).softwareId, 0x01)
        let request = LogiDeviceSession.hidppLongRequest(deviceIndex: 0xFF, featureIndex: 0x00, functionId: 0, params: [0x1B, 0x04])
        XCTAssertEqual(request?[3], 0x01, "getFeature goes out as fn0 | swid 1")
    }

    /// A serial probe chain as the session runs it: each answer starts the next request.
    func testNormalProbeChain() {
        var queue = LogiFeatureDiscoveryQueue(softwareId: swid)
        var results: [UInt16: UInt8?] = [:]
        let chain: [UInt16] = [0x1B04, 0x19B0, 0x2110, 0x1004]
        let wire: [UInt8] = [0x08, 0x0B, 0x00, 0x09]  // 0x2110 is not on the MX Master 4

        func request(_ i: Int) {
            guard i < chain.count else { return }
            queue.append(deviceIndex: 0xFF, featureId: chain[i]) { index in
                results[chain[i]] = index
                request(i + 1)
            }
        }
        request(0)
        for index in wire {
            XCTAssertEqual(queue.count, 1, "one getFeature at a time")
            guard let (entry, featureIndex) = queue.takeAnswer(answer(index)) else {
                return XCTFail("answer 0x\(String(index, radix: 16)) not matched")
            }
            entry.completion(featureIndex)
        }
        XCTAssertTrue(queue.isEmpty)
        XCTAssertEqual(results[0x1B04], .some(0x08))
        XCTAssertEqual(results[0x19B0], .some(0x0B))
        XCTAssertEqual(results[0x2110], .some(nil), "index 0 = the device does not have it")
        XCTAssertEqual(results[0x1004], .some(0x09))
    }

    /// Regression: a ping answer (fn1, protocol 4.5) on index 0 while a getFeature waited was
    /// taken as its answer: "feature at index 4".
    func testAPingAnswerIsNoGetFeatureAnswer() {
        var queue = LogiFeatureDiscoveryQueue(softwareId: swid)
        queue.append(deviceIndex: 0xFF, featureId: 0x1B04) { _ in XCTFail("answered by a ping") }
        XCTAssertNil(queue.takeAnswer(iRoot(function: 1, softwareId: swid, [0x04, 0x05, 0x00])))
        // A receiver slot ping (short report, fn1, swid 0x0A) that arrives late.
        XCTAssertNil(queue.takeAnswer([0x10, 0x02, 0x00, 0x1A, 0x04, 0x05, 0x02]))
        XCTAssertEqual(queue.count, 1)

        var got: UInt8?? = nil
        queue.removeAll()
        queue.append(deviceIndex: 0xFF, featureId: 0x1B04) { got = $0 }
        _ = queue.takeAnswer(iRoot(function: 1, softwareId: swid, [0x04, 0x05, 0x00]))
        if let (entry, index) = queue.takeAnswer(answer(0x08)) { entry.completion(index) }
        XCTAssertEqual(got, .some(0x08))
    }

    /// Regression: another HID++ client's getFeature answer (Logi Options+, its own software
    /// id) completed this app's request with that client's index.
    func testAnotherClientsAnswerIsIgnored() {
        var queue = LogiFeatureDiscoveryQueue(softwareId: swid)
        queue.append(deviceIndex: 0xFF, featureId: 0x19B0) { _ in }
        for foreign: UInt8 in [0x00, 0x02, 0x03, 0x0A, 0x0F] {
            XCTAssertNil(queue.takeAnswer(answer(0x0D, softwareId: foreign)), "swid 0x\(String(foreign, radix: 16))")
        }
        XCTAssertEqual(queue.count, 1)
        XCTAssertEqual(queue.takeAnswer(answer(0x0B))?.featureIndex, 0x0B)
    }

    func testTwoInFlightAreAnsweredInRequestOrder() {
        var queue = LogiFeatureDiscoveryQueue(softwareId: swid)
        var got: [UInt16: UInt8?] = [:]
        queue.append(deviceIndex: 0xFF, featureId: 0x2201) { got[0x2201] = $0 }
        queue.append(deviceIndex: 0xFF, featureId: 0x1814) { got[0x1814] = $0 }
        for index: UInt8 in [0x14, 0x0E] {
            if let (entry, featureIndex) = queue.takeAnswer(answer(index)) { entry.completion(featureIndex) }
        }
        XCTAssertEqual(got[0x2201], .some(0x14))
        XCTAssertEqual(got[0x1814], .some(0x0E))
        XCTAssertTrue(queue.isEmpty)
    }

    /// A timeout fails only its own request; the other keeps waiting and gets the answer.
    func testOneOfTwoTimingOut() {
        var queue = LogiFeatureDiscoveryQueue(softwareId: swid)
        var got: [UInt16: UInt8?] = [:]
        let first = queue.append(deviceIndex: 0xFF, featureId: 0x2201) { got[0x2201] = $0 }
        let second = queue.append(deviceIndex: 0xFF, featureId: 0x1814) { got[0x1814] = $0 }

        // The first request's timer fires.
        queue.remove(token: first)?.completion(nil)
        XCTAssertEqual(got[0x2201], .some(nil))
        XCTAssertFalse(got.keys.contains(0x1814), "the second one still waits")
        XCTAssertEqual(queue.count, 1)
        if let (entry, index) = queue.takeAnswer(answer(0x0E)) { entry.completion(index) }
        XCTAssertEqual(got[0x1814], .some(0x0E))
        XCTAssertNil(queue.remove(token: second), "answered: its late timer finds nothing")

        // The other way round: the second times out, the first still gets its answer.
        got.removeAll()
        queue.append(deviceIndex: 0xFF, featureId: 0x2201) { got[0x2201] = $0 }
        let late = queue.append(deviceIndex: 0xFF, featureId: 0x1814) { got[0x1814] = $0 }
        queue.remove(token: late)?.completion(nil)
        if let (entry, index) = queue.takeAnswer(answer(0x14)) { entry.completion(index) }
        XCTAssertEqual(got[0x2201], .some(0x14))
        XCTAssertEqual(got[0x1814], .some(nil))
    }

    /// Behind a receiver every slot answers its own requests: an answer from slot 3 does not
    /// complete the older request to slot 2.
    func testAnswersBelongToTheirSlot() {
        var queue = LogiFeatureDiscoveryQueue(softwareId: swid)
        var got: [UInt8: UInt8?] = [:]
        queue.append(deviceIndex: 2, featureId: 0x1B04) { got[2] = $0 }
        queue.append(deviceIndex: 3, featureId: 0x1B04) { got[3] = $0 }
        if let (entry, index) = queue.takeAnswer(answer(0x09, device: 3)) { entry.completion(index) }
        XCTAssertEqual(got[3], .some(0x09))
        XCTAssertFalse(got.keys.contains(2), "slot 2 still waits")
        XCTAssertNil(queue.takeAnswer(answer(0x05, device: 4)), "nobody asked slot 4")
        XCTAssertEqual(queue.count, 1)
    }

    /// An error for a getFeature of this app fails the oldest request only; errors for a ping,
    /// another feature or another client fail nothing.
    func testErrorsFailOnlyTheirOwnRequest() {
        var queue = LogiFeatureDiscoveryQueue(softwareId: swid)
        queue.append(deviceIndex: 0xFF, featureId: 0x2201) { _ in }
        queue.append(deviceIndex: 0xFF, featureId: 0x1814) { _ in }
        XCTAssertNil(queue.takeRefused(deviceIndex: 0xFF, originalFeatureIndex: 0x00, originalFunctionByte: 0x11), "ping")
        XCTAssertNil(queue.takeRefused(deviceIndex: 0xFF, originalFeatureIndex: 0x0E, originalFunctionByte: 0x21), "wheel SetState")
        XCTAssertNil(queue.takeRefused(deviceIndex: 0xFF, originalFeatureIndex: 0x00, originalFunctionByte: 0x03), "another client")
        XCTAssertNil(queue.takeRefused(deviceIndex: 0x02, originalFeatureIndex: 0x00, originalFunctionByte: 0x01), "another device")
        XCTAssertEqual(queue.count, 2)
        XCTAssertEqual(queue.takeRefused(deviceIndex: 0xFF, originalFeatureIndex: 0x00, originalFunctionByte: 0x01)?.featureId, 0x2201)
        XCTAssertEqual(queue.count, 1)
        XCTAssertEqual(queue.takeAnswer(answer(0x0E))?.entry.featureId, 0x1814)
    }

    func testShortOrUnrelatedReportsAreNoAnswer() {
        var queue = LogiFeatureDiscoveryQueue(softwareId: swid)
        queue.append(deviceIndex: 0xFF, featureId: 0x1B04) { _ in }
        XCTAssertNil(queue.takeAnswer([0x11, 0xFF, 0x00, 0x01]))
        XCTAssertNil(queue.takeAnswer([0x11, 0xFF, 0x08, 0x01, 0x07]), "not IRoot")
        XCTAssertEqual(queue.removeAll().map { $0.featureId }, [0x1B04])
        XCTAssertNil(queue.takeAnswer(answer(0x08)), "nobody waits")
    }
}

// MARK: - Controllers after a receiver sweep (D)

final class LogiReceiverSweepRebuildTests: XCTestCase {

    /// Regression: a keyboard waking on the mouse's receiver made the mouse's (the cursor
    /// slot's) wheel and basic controllers start again: its values were read and written again.
    func testASweepOfAnotherSlotLeavesTheCursorAlone() {
        XCTAssertNil(LogiDeviceSession.receiverSweepRebuildSlot(cursor: 2, sweptSlots: [1], probeAlreadyRan: true))
    }

    func testTheReconnectedCursorSlotIsRebuilt() {
        XCTAssertEqual(LogiDeviceSession.receiverSweepRebuildSlot(cursor: 2, sweptSlots: [2], probeAlreadyRan: true), 2)
        XCTAssertEqual(LogiDeviceSession.receiverSweepRebuildSlot(cursor: 2, sweptSlots: [1, 2], probeAlreadyRan: true), 2)
    }

    func testAtLaunchTheProbeChainBuildsThem() {
        XCTAssertNil(LogiDeviceSession.receiverSweepRebuildSlot(cursor: 2, sweptSlots: [2], probeAlreadyRan: false))
    }
}

// MARK: - Feature index cache (F)

final class LogiFeatureCacheInvalidationTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaults = TestDefaults.make(for: self)
    }

    override func tearDown() {
        defaults = nil
        super.tearDown()
    }

    /// Byte 4 of an error: the refused request's function << 4 | software id. This app's id is 1.
    private let ownGetState: UInt8 = 0x11
    private let foreignGetState: UInt8 = 0x1A

    func testInvalidIndexOrFunctionOnACachedIndexDropsTheCache() {
        let cached: Set<UInt8> = [0x08, 0x09, 0x0B, 0x0C, 0x14]
        XCTAssertTrue(LogiDeviceSession.errorInvalidatesFeatureCache(
            errorCode: 0x06, originalFeatureIndex: 0x0B, originalFunctionByte: ownGetState, cachedIndices: cached))
        XCTAssertTrue(LogiDeviceSession.errorInvalidatesFeatureCache(
            errorCode: 0x07, originalFeatureIndex: 0x14, originalFunctionByte: ownGetState, cachedIndices: cached))
    }

    func testOtherErrorsAndIndicesKeepIt() {
        let cached: Set<UInt8> = [0x08, 0x09]
        for code: UInt8 in [0x01, 0x02, 0x03, 0x04, 0x05, 0x08, 0x09] {
            XCTAssertFalse(LogiDeviceSession.errorInvalidatesFeatureCache(
                errorCode: code, originalFeatureIndex: 0x08, originalFunctionByte: ownGetState, cachedIndices: cached))
        }
        XCTAssertFalse(LogiDeviceSession.errorInvalidatesFeatureCache(
            errorCode: 0x06, originalFeatureIndex: 0x0E, originalFunctionByte: ownGetState, cachedIndices: cached),
            "an index that was looked up on this connection, not cached")
        XCTAssertFalse(LogiDeviceSession.errorInvalidatesFeatureCache(
            errorCode: 0x06, originalFeatureIndex: 0x00, originalFunctionByte: ownGetState, cachedIndices: [0x00]),
            "IRoot is never cached")
        XCTAssertFalse(LogiDeviceSession.errorInvalidatesFeatureCache(
            errorCode: 0x06, originalFeatureIndex: 0x08, originalFunctionByte: ownGetState, cachedIndices: []),
            "a receiver session never uses the cache")
    }

    /// An error for another HID++ client's request (Logi Options+ asking with its own indices)
    /// says nothing about this app's cache.
    func testAnotherClientsErrorKeepsTheCache() {
        let cached: Set<UInt8> = [0x08, 0x09]
        for code: UInt8 in [0x06, 0x07] {
            XCTAssertFalse(LogiDeviceSession.errorInvalidatesFeatureCache(
                errorCode: code, originalFeatureIndex: 0x08, originalFunctionByte: foreignGetState, cachedIndices: cached))
            XCTAssertFalse(LogiDeviceSession.errorInvalidatesFeatureCache(
                errorCode: code, originalFeatureIndex: 0x08, originalFunctionByte: 0x10, cachedIndices: cached),
                "software id 0: a device event, not an answer to this app")
        }
    }

    /// Dropping one product leaves the others and the stored format as they were.
    func testRemovingOneProductKeepsTheOthersAndTheFormat() throws {
        let mx4: [UInt16: UInt8] = [0x1B04: 0x08, 0x19B0: 0x0B, 0x1004: 0x09]
        let other: [UInt16: UInt8] = [0x1B04: 0x05]
        LogiDeviceSession.saveCachedFeatureIndexForTests(for: 0xB042, featureMap: mx4, defaults: defaults)
        LogiDeviceSession.saveCachedFeatureIndexForTests(for: 0xB034, featureMap: other, defaults: defaults)

        LogiDeviceSession.removeCachedFeatureIndexForTests(for: 0xB042, defaults: defaults)

        XCTAssertNil(LogiDeviceSession.loadCachedFeatureIndexForTests(for: 0xB042, defaults: defaults))
        XCTAssertEqual(LogiDeviceSession.loadCachedFeatureIndexForTests(for: 0xB034, defaults: defaults), other)
        let data = try XCTUnwrap(defaults.data(forKey: LogiDeviceSession.featureCacheKeyForTests))
        let stored = try JSONDecoder().decode([UInt16: [UInt16: UInt8]].self, from: data)
        XCTAssertEqual(stored, [0xB034: other])

        // Removing what is not there writes nothing new.
        LogiDeviceSession.removeCachedFeatureIndexForTests(for: 0xB042, defaults: defaults)
        XCTAssertEqual(defaults.data(forKey: LogiDeviceSession.featureCacheKeyForTests), data)
    }
}

// MARK: - IOHIDManagerOpen (B)

final class LogiSessionManagerOpenTests: XCTestCase {

    func testASuccessfulOpenLogsNothing() {
        XCTAssertNil(LogiSessionManager.openFailureLogLine(result: kIOReturnSuccess))
    }

    /// The failure used to show only in the diagnostics panel's memory; now it is one line
    /// in the system log (category logi), with the code.
    func testAFailedOpenIsOneSystemLogLine() {
        let line = LogiSessionManager.openFailureLogLine(result: kIOReturnNotPermitted)
        XCTAssertEqual(line, "IOHIDManagerOpen returned 0xe00002e2; the manager stays open for the devices it could open")
    }
}

// MARK: - Diagnostics spinner (G)

final class BrailleSpinnerTests: XCTestCase {

    /// The spinner's 80 ms timer used to run for the rest of the app's life once the
    /// diagnostics panel had been opened. It runs only between start() and stop() now; the
    /// panel is never opened in the tests, so the shared spinner is idle here.
    func testItTicksOnlyBetweenStartAndStop() {
        let spinner = BrailleSpinner.shared
        _ = spinner.currentFrame
        XCTAssertFalse(spinner.isRunning, "reading a frame starts nothing")
        spinner.start()
        spinner.start()
        XCTAssertTrue(spinner.isRunning)
        spinner.stop()
        XCTAssertFalse(spinner.isRunning)
        spinner.stop()
        XCTAssertFalse(spinner.isRunning)
    }
}

// MARK: - How long the HID++ writes take

/// A HID++ write (IOHIDDeviceSetReport) takes 15 to 29 ms over Bluetooth. The writes run on
/// the session's own queue; what they took goes to the `logi` log once per connection as a
/// summary, and one by one only when the link struggles or the device refuses. Only the
/// wording and the limits are tested here; nothing is written.
final class LogiWriteTimingTests: XCTestCase {

    private let ms: UInt64 = 1_000_000
    private let second: UInt64 = 1_000_000_000

    /// An ordinary Bluetooth write (about 22 ms) no longer holds the main thread: no line.
    func testOrdinaryWritesWriteNoLine() {
        var timing = LogiWriteTiming()
        XCTAssertNil(timing.record(duration: 22 * ms, now: 10 * second, request: .feature(index: 0x05, function: 1), link: .bluetooth))
        XCTAssertNil(timing.record(duration: 99_999_999, now: 11 * second, request: .feature(index: 0x05, function: 1), link: .bluetooth))
    }

    func testASlowWriteIsWrittenWithWhatItAskedAndTheLink() {
        var timing = LogiWriteTiming()
        XCTAssertEqual(
            timing.record(duration: 123_400_000, now: 10 * second, request: .feature(index: 0x05, function: 1), link: .bluetooth),
            "Slow HID++ write: 123.4 ms (feature index 0x05, function 1, over Bluetooth); "
                + "1 write of 100 ms or more since the last such line, longest 123.4 ms"
        )
        var receiver = LogiWriteTiming()
        XCTAssertEqual(
            receiver.record(duration: 100 * ms, now: 10 * second, request: .ping(slot: 2), link: .receiver),
            "Slow HID++ write: 100.0 ms (ping of slot 0x02, through a receiver); "
                + "1 write of 100 ms or more since the last such line, longest 100.0 ms"
        )
        XCTAssertEqual(LogiWriteTiming.Request.receiverRegister(0xB5, long: true).text, "receiver register 0xB5 long read")
        XCTAssertEqual(LogiWriteTiming.Request.receiverRegister(0xB5, long: false).text, "receiver register 0xB5 read")
        XCTAssertEqual(LogiWriteTiming.Request.receiverRegisterWrite(0x00).text, "receiver register 0x00 write")
    }

    /// At most one line a second; the next one counts the slow writes in between.
    func testAtMostOneLineASecondWithTheCountAndTheLongest() {
        var timing = LogiWriteTiming()
        let request = LogiWriteTiming.Request.feature(index: 0x0B, function: 3)
        XCTAssertNotNil(timing.record(duration: 110 * ms, now: 10 * second, request: request, link: .bluetooth))
        XCTAssertNil(timing.record(duration: 300 * ms, now: 10 * second + 200 * ms, request: request, link: .bluetooth))
        XCTAssertNil(timing.record(duration: 20 * ms, now: 10 * second + 300 * ms, request: request, link: .bluetooth), "ordinary: not counted")
        XCTAssertNil(timing.record(duration: 150 * ms, now: 10 * second + 999 * ms, request: request, link: .bluetooth))
        XCTAssertEqual(
            timing.record(duration: 120 * ms, now: 11 * second, request: request, link: .bluetooth),
            "Slow HID++ write: 120.0 ms (feature index 0x0B, function 3, over Bluetooth); "
                + "3 writes of 100 ms or more since the last such line, longest 300.0 ms"
        )
    }

    /// The summary of a connection: what the writes took on their queue, and how long the
    /// main thread was held to queue them (the number that used to be the whole total).
    func testTheSummaryOfAConnectionIsWrittenOnce() {
        var timing = LogiWriteTiming()
        let request = LogiWriteTiming.Request.feature(index: 0x00, function: 0)
        for duration in [22 * ms, 15 * ms, 29 * ms] {
            timing.noteQueued(mainThreadHeld: 20_000)
            XCTAssertNil(timing.record(duration: duration, now: 10 * second, request: request, link: .bluetooth))
        }
        XCTAssertEqual(
            timing.finishSetup(link: .bluetooth),
            "HID++ writes while connecting (over Bluetooth): 3, 66.0 ms in total on the write queue, "
                + "longest 29.0 ms; the main thread was held 0.1 ms to queue them"
        )
        XCTAssertNil(timing.finishSetup(link: .bluetooth), "once per connection")
        // Later writes are not added to a summary that was written.
        timing.noteQueued(mainThreadHeld: 20_000)
        XCTAssertNil(timing.record(duration: 22 * ms, now: 20 * second, request: request, link: .bluetooth))
        XCTAssertEqual(timing.setupWrites, 3)
        XCTAssertEqual(timing.setupMainThread, 60_000)
    }

    /// A write the device refused: said once a second at most, with how many.
    func testARefusedWriteIsWrittenAtMostOnceASecond() {
        var timing = LogiWriteTiming()
        let request = LogiWriteTiming.Request.feature(index: 0x0B, function: 2)
        let notOpen = Int32(bitPattern: 0xE00002CD)
        XCTAssertEqual(
            timing.recordFailure(result: notOpen, now: 10 * second, request: request, link: .bluetooth),
            "HID++ write refused: 0xe00002cd (feature index 0x0B, function 2, over Bluetooth); 1 refused write since the last such line"
        )
        XCTAssertNil(timing.recordFailure(result: notOpen, now: 10 * second + 500 * ms, request: request, link: .bluetooth))
        XCTAssertEqual(
            timing.recordFailure(result: notOpen, now: 11 * second, request: request, link: .bluetooth),
            "HID++ write refused: 0xe00002cd (feature index 0x0B, function 2, over Bluetooth); 2 refused writes since the last such line"
        )
    }

    func testTheLineAboutWaitingAtTeardown() {
        XCTAssertEqual(LogiWriteTiming.drainLine(waited: 198_300_000, finished: true, reason: "teardown"),
                       "Waited 198.3 ms for the queued HID++ writes (teardown)")
        XCTAssertEqual(LogiWriteTiming.drainLine(waited: 2_000_000_000, finished: false, reason: "teardown"),
                       "The queued HID++ writes did not finish within 2000.0 ms (teardown); going on without them")
    }
}

// MARK: - Writes off the main thread

/// The writer sends a device's reports one after another, in the order given, on a queue of
/// its own: the caller (the main thread) never waits for the device, except where it asks to.
final class LogiReportWriterTests: XCTestCase {

    /// Collects what the "device" was sent, from the writer's queue.
    private final class Device {
        private let lock = NSLock()
        private var reports: [[UInt8]] = []
        var result: IOReturn = kIOReturnSuccess
        var delay: TimeInterval = 0
        /// A device that does not answer: while a gate is set and closed, every send waits
        /// in front of it. `open()` lets them through, one after another.
        var gate: DispatchSemaphore?
        /// Whether a send ran on the main thread.
        private(set) var sentOnMainThread = false

        func open() {
            gate?.signal()
        }

        func send(_ report: [UInt8]) -> IOReturn {
            if let gate {
                gate.wait()
                gate.signal()
            }
            if delay > 0 { Thread.sleep(forTimeInterval: delay) }
            lock.lock()
            reports.append(report)
            if Thread.isMainThread { sentOnMainThread = true }
            lock.unlock()
            return result
        }

        var sent: [[UInt8]] {
            lock.lock(); defer { lock.unlock() }
            return reports
        }
    }

    private func makeWriter(_ device: Device) -> LogiReportWriter {
        return LogiReportWriter(label: "test.logi.write", send: device.send)
    }

    func testReportsGoOutInTheOrderGivenAndNeverOnTheMainThread() {
        let device = Device()
        device.delay = 0.01
        // The device takes nothing until the test says so.
        device.gate = DispatchSemaphore(value: 0)
        let writer = makeWriter(device)
        let reports: [[UInt8]] = (0..<20).map { [0x11, 0xFF, UInt8($0)] }
        var outcomes: [LogiReportWriter.Outcome] = []
        let delivered = expectation(description: "all outcomes delivered")
        delivered.expectedFulfillmentCount = reports.count

        for report in reports {
            writer.write(report) { outcome in
                XCTAssertTrue(Thread.isMainThread, "outcomes come back on the main thread")
                outcomes.append(outcome)
                delivered.fulfill()
            }
        }
        // All twenty are queued and the device has taken none: the caller did not wait for
        // it. (Not a measured time: that depended on how busy the Mac was.)
        XCTAssertEqual(device.sent, [])
        device.open()

        wait(for: [delivered], timeout: 5)
        XCTAssertEqual(device.sent, reports)
        XCTAssertFalse(device.sentOnMainThread)
        XCTAssertEqual(outcomes.count, reports.count)
        XCTAssertTrue(outcomes.allSatisfy { $0.result == kIOReturnSuccess })
        XCTAssertTrue(outcomes.allSatisfy { $0.duration >= 8_000_000 }, "each took the device's time")
        XCTAssertGreaterThan(outcomes.last?.waited ?? 0, outcomes.first?.waited ?? .max, "the last one waited behind the others")
    }

    /// Teardown waits for what is queued: the requests that give the mouse its buttons back
    /// must have gone out before the device is closed.
    func testDrainWaitsForEverythingQueued() {
        let device = Device()
        device.delay = 0.005
        let writer = makeWriter(device)
        for index in 0..<5 {
            writer.write([0x11, 0xFF, UInt8(index)]) { _ in }
        }
        XCTAssertTrue(writer.drain(timeout: 2))
        XCTAssertEqual(device.sent.count, 5, "all five went out before drain returned")
    }

    /// A device that does not answer must not hold teardown forever.
    func testDrainGivesUpAfterItsTimeout() {
        let device = Device()
        device.gate = DispatchSemaphore(value: 0)
        let writer = makeWriter(device)
        writer.write([0x11, 0xFF, 0x00]) { _ in }
        // The write cannot finish before the gate opens, so a drain that comes back at all
        // has given up (one that waited for the device would hang here, and the test plan's
        // time limit would end it). Not a measured time: that depended on the Mac.
        XCTAssertFalse(writer.drain(timeout: 0.05))
        XCTAssertEqual(device.sent, [], "the device still has not answered")
        // Let the stuck write finish so the test leaves nothing behind.
        device.open()
        XCTAssertTrue(writer.drain(timeout: 5))
        XCTAssertEqual(device.sent.count, 1)
    }

    func testARefusalComesBackAsTheOutcome() {
        let device = Device()
        device.result = kIOReturnNotOpen
        let writer = makeWriter(device)
        let delivered = expectation(description: "outcome")
        writer.write([0x10, 0xFF, 0x00]) { outcome in
            XCTAssertEqual(outcome.result, kIOReturnNotOpen)
            delivered.fulfill()
        }
        wait(for: [delivered], timeout: 2)
    }

    /// The summary of a connection is written once the writes queued before it were counted.
    func testAfterQueuedRunsOnceTheEarlierOutcomesWereDelivered() {
        let device = Device()
        device.delay = 0.002
        let writer = makeWriter(device)
        var order: [String] = []
        let done = expectation(description: "afterQueued")
        writer.write([1]) { _ in order.append("first") }
        writer.write([2]) { _ in order.append("second") }
        writer.afterQueued {
            order.append("after")
            done.fulfill()
        }
        XCTAssertTrue(order.isEmpty, "nothing ran yet: the caller did not wait")
        wait(for: [done], timeout: 2)
        XCTAssertEqual(order, ["first", "second", "after"])
    }
}
