//
//  ScrollHardwareRecord.swift
//  Scrollio
//
//  The hardware record of a scroll event, and taking it off the frames of
//  "Trackpad-style scrolling (Beta)".
//

import Cocoa

/// A scroll event that comes from a device carries a hardware record (an IOHIDEvent): the
/// device's own time and its raw delta. `CGEvent.copy()` keeps it, so every frame Scrollio
/// posts (a copy of the wheel event) carried the wheel's record: the wheel event's time and
/// "one notch", on a frame that says "3 px of a glide, now".
///
/// Who reads it: WebKit, and only for a glide. When the frame that says "momentum began"
/// carries a record, WebKit runs a glide of its own from that record's raw delta and drops
/// the glide events it is sent (measured in a WKWebView on macOS 27.2: 36 of a flick's
/// 205 px arrived, 146 of the old long touch's). Without a record it follows the frames it
/// is sent, all of them. AppKit, Chromium and Gecko do not read the record (read in their
/// sources). So a frame that carries phases goes out without one.
///
/// The record is taken off with SkyLight's `SLEventSetIOHIDEvent(event, NULL)`, a private
/// function resolved at run time, as `DockSwipeHIDBridge` resolves it to attach one. Copies
/// of an event share one record object, so it is never changed in place: it is taken off the
/// frame's own copy and the wheel event keeps its own.
///
/// It is used only when a self-test has passed (`check`): attach a record to an event,
/// read it back, take it off a copy, read nil there and the record still on the original.
/// Where a function is missing or a step fails, frames keep the record as they always did
/// and the `app` log says so once.
///
/// The self-test runs once, the first time somebody asks whether the record comes off
/// (`comesOff`), and never for a user who has "Trackpad-style scrolling" off: nobody asks
/// then, at launch or at a wheel event. It is asked at launch when the switch is on in the
/// Scrolling pane or in some app's own settings (`ScrollPoster.trackpadStyleIsOnSomewhere`),
/// and otherwise by the first wheel event whose frames would carry phases (the switch was
/// turned on in this run): about 30 microseconds, once. So a macOS on which the private
/// call misbehaves reaches only a user who has the Beta on, and he can still start the app
/// and switch it off. The `app` log line is written when the self-test runs.
///
/// The self-test passes NULL to a private function in this process. That was run on macOS
/// 27.2 only; whether macOS 14, 15 and 26 accept NULL there is not known, and a crash in the
/// self-test would be a crash at every launch. So on a macOS older than `testedFromMacOS` it
/// is not tried at all: frames keep the record there, and the log says so. (One constant, to
/// be lowered when the probe has run on such a Mac.)
enum ScrollHardwareRecord {

    /// `SLEventSetIOHIDEvent(event, record)`: attaches a record, or with NULL takes it off.
    typealias SetRecord = @convention(c) (CGEvent, UnsafeMutableRawPointer?) -> Void
    /// `CGEventCopyIOHIDEvent(event)`: the event's record (+1), or NULL.
    typealias CopyRecord = @convention(c) (CGEvent) -> UnsafeMutableRawPointer?
    /// `IOHIDEventCreateScrollEvent(allocator, time, x, y, z, options)` (+1): for the self-test.
    typealias CreateScrollRecord = @convention(c) (CFAllocator?, UInt64, Double, Double, Double, UInt32) -> UnsafeMutableRawPointer?

    struct Calls {
        let set: SetRecord
        let copy: CopyRecord
        let createScroll: CreateScrollRecord
    }

    /// What the launch found.
    enum Outcome: Equatable {
        /// The self-test passed: the record is taken off every frame that carries phases.
        case comesOff
        /// An older macOS than the one this was run on: not tried.
        case notTried(macOS: Int)
        /// macOS has no such function here.
        case missing(String)
        /// A step of the self-test failed.
        case failed(String)
    }

    /// The first macOS on which taking a record off with NULL was run (27.2).
    static let testedFromMacOS = 27

    static let symbols: [(library: String, name: String)] = [
        ("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", "SLEventSetIOHIDEvent"),
        ("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", "CGEventCopyIOHIDEvent"),
        ("/System/Library/Frameworks/IOKit.framework/IOKit", "IOHIDEventCreateScrollEvent"),
    ]

    typealias Resolver = (_ library: String, _ name: String) -> UnsafeMutableRawPointer?

    static func systemResolver(_ library: String, _ name: String) -> UnsafeMutableRawPointer? {
        guard let handle = dlopen(library, RTLD_LAZY) else { return nil }
        return dlsym(handle, name)
    }

    /// The three functions, or the name of the first that is missing.
    static func load(resolver: Resolver = ScrollHardwareRecord.systemResolver) -> (calls: Calls?, missing: String?) {
        var addresses: [UnsafeMutableRawPointer] = []
        for symbol in symbols {
            guard let address = resolver(symbol.library, symbol.name) else {
                return (nil, symbol.name)
            }
            addresses.append(address)
        }
        return (Calls(
            set: unsafeBitCast(addresses[0], to: SetRecord.self),
            copy: unsafeBitCast(addresses[1], to: CopyRecord.self),
            createScroll: unsafeBitCast(addresses[2], to: CreateScrollRecord.self)
        ), nil)
    }

    /// The self-test. Builds events and reads them; nothing is posted.
    static func check(_ calls: Calls) -> Outcome {
        guard let wheel = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0) else {
            return .failed("no scroll event could be made")
        }
        guard let record = calls.createScroll(nil, mach_absolute_time(), 0, 1, 0, 0) else {
            return .failed("no hardware record could be made")
        }
        defer { release(record) }
        calls.set(wheel, record)
        guard let readBack = calls.copy(wheel) else {
            return .failed("a record attached to an event could not be read back")
        }
        release(readBack)
        guard let frame = wheel.copy() else {
            return .failed("the event could not be copied")
        }
        guard let onTheCopy = calls.copy(frame) else {
            return .failed("a copy of the event did not carry its record")
        }
        release(onTheCopy)
        calls.set(frame, nil)
        if let stillThere = calls.copy(frame) {
            release(stillThere)
            return .failed("the record stayed on the event it was taken off")
        }
        guard let kept = calls.copy(wheel) else {
            return .failed("taking the record off a copy took it off the event it was copied from")
        }
        release(kept)
        return .comesOff
    }

    /// What a launch on the given macOS finds. The functions are not even looked up on a
    /// macOS the removal was never run on.
    static func prepare(macOSMajor: Int, load: () -> (calls: Calls?, missing: String?) = { ScrollHardwareRecord.load() }) -> (outcome: Outcome, calls: Calls?) {
        guard macOSMajor >= testedFromMacOS else {
            return (.notTried(macOS: macOSMajor), nil)
        }
        let loaded = load()
        guard let calls = loaded.calls else {
            return (.missing(loaded.missing ?? "a function"), nil)
        }
        let outcome = check(calls)
        return (outcome, outcome == .comesOff ? calls : nil)
    }

    /// This run: looked up and tested once, the first time it is asked for, and the `app`
    /// log told what was found. A `static let`: once, whichever thread asks first.
    static let system: (outcome: Outcome, calls: Calls?) = {
        let found = prepare(macOSMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
        announce(found.outcome, note: AppSystemLog.note, problem: AppSystemLog.problem)
        return found
    }()

    /// Whether frames go out without the record. The first call runs the self-test. Asked
    /// only where "Trackpad-style scrolling" is on: at launch, or by a wheel event whose
    /// frames would carry phases. Main thread.
    static var comesOff: Bool {
#if DEBUG
        timesAskedForTests += 1
#endif
        return system.calls != nil
    }
#if DEBUG
    /// Tests: how often `comesOff` was asked in this process.
    static var timesAskedForTests = 0
#endif

    /// Writes what the self-test found to the `app` log: a note when the record comes off
    /// and when this macOS is not tried (that is by design, no fault), a problem when a
    /// function is missing or a step failed.
    static func announce(_ outcome: Outcome, note: (String) -> Void, problem: (String) -> Void) {
        let line = launchLine(outcome)
        if line.isProblem {
            problem(line.text)
        } else {
            note(line.text)
        }
    }

    /// Takes the record off an event Scrollio owns (a frame's own copy). Nothing happens
    /// where the self-test did not pass.
    static func remove(from event: CGEvent) {
        system.calls?.set(event, nil)
    }

    /// Whether an event carries a record; nil where that cannot be asked.
    static func isCarried(by event: CGEvent, calls: Calls? = ScrollHardwareRecord.readingCalls) -> Bool? {
        guard let calls = calls else { return nil }
        guard let record = calls.copy(event) else { return false }
        release(record)
        return true
    }

    /// The functions for reading only (`isCarried`), also where the removal is not used.
    static let readingCalls: Calls? = system.calls ?? load().calls

    /// The line for the `app` log, and whether it reports a problem.
    static func launchLine(_ outcome: Outcome) -> (text: String, isProblem: Bool) {
        let kept = "the frames of Trackpad-style scrolling keep the wheel event's hardware record, as before"
        switch outcome {
        case .comesOff:
            return ("Trackpad-style scrolling: the wheel event's hardware record is taken off every frame that carries phases (self-test passed)", false)
        case .notTried(let macOS):
            return ("Trackpad-style scrolling: taking the hardware record off a frame was only run on macOS \(testedFromMacOS) and later; on macOS \(macOS) it is not tried, and \(kept)", false)
        case .missing(let name):
            return ("Trackpad-style scrolling: macOS has no \(name) here; \(kept)", true)
        case .failed(let step):
            return ("Trackpad-style scrolling: the self-test for taking the hardware record off a frame failed (\(step)); \(kept)", true)
        }
    }

    /// Balances a +1 reference (`CGEventCopyIOHIDEvent`, `IOHIDEventCreateScrollEvent`).
    private static func release(_ record: UnsafeMutableRawPointer) {
        Unmanaged<AnyObject>.fromOpaque(record).release()
    }
}
