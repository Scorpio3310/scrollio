//
//  DockSwipeSynthesizer.swift
//  Mos
//
//  Synthesizes the "dock swipe" a trackpad or Magic Mouse sends to the Dock to switch
//  Spaces, so a held mouse button can drag the desktop and let it follow the hand. The
//  same event with another motion opens Mission Control (vertical) and Show Desktop or
//  Launchpad / Apps (the pinch).
//
//  A swipe is a stream of CGEvents of type 30 posted to the session event tap:
//  began -> changed ... -> ended | cancelled. Progress is cumulative from the start of the
//  swipe. The payload has two layouts:
//
//  - "fields" (macOS 26 and older): private CGEvent fields
//        110      gesture HID type      23 (dock swipe)
//        123/165  motion                1 horizontal, 2 vertical, 3 pinch
//        119/139  motion                the same value as float32 bits read as a double
//        124      progress              double, positive = next Space (horizontal)
//        135      progress              float32 bits stored in an integer
//        132/134  phase                 1 began, 2 changed, 4 ended, 8 cancelled
//        136      natural scrolling     1 when the system preference is on (horizontal);
//                                       always 1 for the other two motions
//        129/130  velocity              only on ended / cancelled
//    followed by an empty companion event of type 29.
//
//  - "hid" (macOS 27 and newer): the Dock ignores those fields and reads an IOHIDEvent
//    attached with SkyLight's SLEventSetIOHIDEvent:
//        IOHIDEvent type 23, event flags = phase << 24
//        (23 << 16) | 1   motion
//        (23 << 16) | 5   flavor = 3 (dock primary)
//        (23 << 16) | 2   progress
//        child IOHIDEvent type 9 with (9 << 16) | 0 and | 1 = velocity, on ended / cancelled
//    Values are 16.16 fixed point. Progress is in device coordinates: for the horizontal
//    motion the Dock applies the natural-scrolling preference itself (on: negative = next
//    Space).
//
//  Scrollio's own convention, used by every type below. Horizontal: positive progress and
//  velocity move towards the next Space (the one on the right); the natural-scrolling
//  preference is folded in when the event is built, so callers never see it. Vertical and
//  pinch: positive progress opens Mission Control (vertical) and Show Desktop (pinch), and
//  negative is the other end of the motion (App Exposé; Launchpad / Apps). On these two
//  the preference plays no part: a swipe up is Mission Control whatever the scrolling
//  direction, so the event is built as a trackpad with natural scrolling sends it. "hid":
//  the device value is Scrollio's value. "fields": field 124 is Scrollio's value turned
//  over, with field 136 = 1 (with the flag off the Dock reads a pinch's release velocity
//  backwards before macOS 26). The velocity always carries the sign of the progress.
//  (Derived from Mac Mouse Fix and, for "fields", an older second implementation; only
//  the "hid" layout can be seen on a Mac that runs macOS 27.)
//
//  Own implementation written from the documented constants. References for the event
//  format and its pitfalls: Mac Mouse Fix (Noah Nuebling; TouchSimulator.m and the
//  three-finger-swipe drag output) and InstantSpaceSwitcher (MIT).
//

import Cocoa

// MARK: - Frames

enum DockSwipeAxis: Int, Equatable {
    /// Switches between Spaces. Positive: towards the next Space.
    case horizontal = 1
    /// Mission Control (positive) / App Exposé (negative).
    case vertical = 2
    /// Show Desktop (positive: the spread) / Launchpad, Apps from macOS 26 on (negative:
    /// the pinch with the thumb and three fingers).
    case pinch = 3

    /// Whether the system's natural-scrolling preference turns this motion. Sideways it
    /// does: the desktops move as content does. The other two have one fixed direction (up
    /// is Mission Control whatever the preference), so it is not consulted for them.
    var followsScrollingPreference: Bool {
        return self == .horizontal
    }
}

enum DockSwipePhase: UInt32, Equatable {
    case began = 1
    case changed = 2
    case ended = 4
    case cancelled = 8

    var isTerminal: Bool { self == .ended || self == .cancelled }
}

/// One event of a swipe in Scrollio's convention (positive = towards the next Space,
/// Mission Control or Show Desktop, by the axis).
struct DockSwipeFrame: Equatable {
    var phase: DockSwipePhase
    var axis: DockSwipeAxis
    /// Cumulative offset since the swipe began.
    var progress: Double
    /// Release velocity in progress units per second. Only sent with a terminal phase.
    var velocity: Double = 0
}

enum DockSwipeEventLayout: Equatable {
    case fields
    case hid

    static let firstHIDMajorVersion = 27

    static func layout(forMajorVersion majorVersion: Int) -> DockSwipeEventLayout {
        return majorVersion >= firstHIDMajorVersion ? .hid : .fields
    }

    static var current: DockSwipeEventLayout {
        return layout(forMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    }
}

// MARK: - Payload values (pure)

/// Private CGEvent fields of the "fields" layout, keyed by field number.
struct DockSwipeFieldValues: Equatable {
    var integers: [UInt32: Int64] = [:]
    var doubles: [UInt32: Double] = [:]
}

/// Content of the IOHIDEvent of the "hid" layout.
struct DockSwipeHIDValues: Equatable {
    var eventFlags: UInt32
    var motion: Int
    var flavor: Int
    /// Device coordinates.
    var progress: Double
    /// Device coordinates; nil unless the phase is terminal.
    var velocity: Double?
}

enum DockSwipeEventEncoding {
    static let dockControlEventType: UInt32 = 30
    static let gestureCompanionEventType: UInt32 = 29

    static let hidDockSwipeType: UInt32 = 23
    static let hidVelocityType: UInt32 = 9
    static let hidFlavorDockPrimary = 3
    static let hidPhaseShift: UInt32 = 24
    static let hidDockSwipeMotionField: UInt32 = (hidDockSwipeType << 16) | 1
    static let hidDockSwipeProgressField: UInt32 = (hidDockSwipeType << 16) | 2
    static let hidDockSwipeFlavorField: UInt32 = (hidDockSwipeType << 16) | 5
    static let hidVelocityXField: UInt32 = (hidVelocityType << 16) | 0
    static let hidVelocityYField: UInt32 = (hidVelocityType << 16) | 1

    /// HID values are 16.16 fixed point, so magnitudes must stay below 32768.
    static let fixedPointLimit: Double = 32_000

    static let fieldHIDType: UInt32 = 110
    static let fieldMotion: UInt32 = 123
    static let fieldMotionAlias: UInt32 = 165
    static let fieldMotionFloatBits: UInt32 = 119
    static let fieldMotionFloatBitsAlias: UInt32 = 139
    static let fieldProgress: UInt32 = 124
    static let fieldProgressFloatBits: UInt32 = 135
    static let fieldPhase: UInt32 = 132
    static let fieldPhaseAlias: UInt32 = 134
    static let fieldNaturalScrolling: UInt32 = 136
    static let fieldVelocityX: UInt32 = 129
    static let fieldVelocityY: UInt32 = 130

    /// Event types Scrollio posts for a swipe. None of Scrollio's own event taps listens to them.
    static let ownEventTypes: [UInt32] = [gestureCompanionEventType, dockControlEventType]

    /// macOS 26 and older. Horizontal: positive progress = next Space, whatever the
    /// scrolling preference; the preference only travels along as a flag. Vertical and
    /// pinch: Scrollio's value turned over (progress and velocity alike) with the flag
    /// always set, as a trackpad with natural scrolling sends them.
    static func fieldValues(for frame: DockSwipeFrame, naturalScrolling: Bool) -> DockSwipeFieldValues {
        let motion = Int64(frame.axis.rawValue)
        let motionAsDouble = Double(Float(bitPattern: UInt32(frame.axis.rawValue)))
        let phase = Int64(frame.phase.rawValue)
        let followsPreference = frame.axis.followsScrollingPreference
        // The horizontal values go out untouched, bit for bit.
        let progress = followsPreference ? frame.progress : turnedOver(frame.progress)
        let velocity = followsPreference ? frame.velocity : turnedOver(frame.velocity)

        var values = DockSwipeFieldValues()
        values.integers[fieldHIDType] = Int64(hidDockSwipeType)
        values.integers[fieldPhase] = phase
        values.integers[fieldPhaseAlias] = phase
        values.integers[fieldMotion] = motion
        values.integers[fieldMotionAlias] = motion
        values.doubles[fieldMotionFloatBits] = motionAsDouble
        values.doubles[fieldMotionFloatBitsAlias] = motionAsDouble
        values.doubles[fieldProgress] = progress
        values.integers[fieldProgressFloatBits] = Int64(Float(progress).bitPattern)
        values.integers[fieldNaturalScrolling] = (followsPreference ? naturalScrolling : true) ? 1 : 0
        if frame.phase.isTerminal {
            values.doubles[fieldVelocityX] = velocity
            values.doubles[fieldVelocityY] = velocity
        }
        return values
    }

    /// The value with the other sign; a zero stays a plain zero (field 135 carries the
    /// bits, and "nothing moved" must not read as a negative number there).
    static func turnedOver(_ value: Double) -> Double {
        return 0 - value
    }

    /// macOS 27 and newer: device coordinates. Horizontal: with natural scrolling on, the
    /// Dock moves the desktop with the fingers, so a negative value brings in the next
    /// Space; with it off the meaning flips. Scrollio undoes that here, so its own sign
    /// never depends on the preference. Vertical and pinch: the device value is Scrollio's
    /// value (up, and the spread, are positive), whatever the preference.
    /// (Derived from Mac Mouse Fix; to be confirmed on real hardware.)
    static func hidValues(for frame: DockSwipeFrame, naturalScrolling: Bool) -> DockSwipeHIDValues {
        let deviceSign: Double = frame.axis.followsScrollingPreference && naturalScrolling ? -1 : 1
        return DockSwipeHIDValues(
            eventFlags: frame.phase.rawValue << hidPhaseShift,
            motion: frame.axis.rawValue,
            flavor: hidFlavorDockPrimary,
            progress: fixedPointClamped(deviceSign * frame.progress),
            velocity: frame.phase.isTerminal ? fixedPointClamped(deviceSign * frame.velocity) : nil
        )
    }

    static func fixedPointClamped(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, -fixedPointLimit), fixedPointLimit)
    }
}

// MARK: - Private symbols

/// IOKit and SkyLight functions for the "hid" layout, resolved at run time so Scrollio has no
/// link-time dependency on them. `load` returns nil when any of them is missing.
struct DockSwipeHIDBridge {
    typealias Create = @convention(c) (CFAllocator?, UInt32, UInt64, UInt32) -> UnsafeMutableRawPointer?
    typealias SetInteger = @convention(c) (UnsafeMutableRawPointer, UInt32, CFIndex) -> Void
    typealias SetDouble = @convention(c) (UnsafeMutableRawPointer, UInt32, Double) -> Void
    typealias SetFlags = @convention(c) (UnsafeMutableRawPointer, UInt32) -> Void
    typealias Append = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer, UInt32) -> Void
    typealias Attach = @convention(c) (CGEvent, UnsafeMutableRawPointer) -> Void

    enum Library: String {
        case ioKit = "/System/Library/Frameworks/IOKit.framework/IOKit"
        case skyLight = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
    }

    typealias Resolver = (Library, String) -> UnsafeMutableRawPointer?

    /// Every entry must resolve; an entry lists alternative names for the same function.
    static let requiredSymbols: [(library: Library, names: [String])] = [
        (.ioKit, ["IOHIDEventCreate"]),
        (.ioKit, ["IOHIDEventSetIntegerValue"]),
        // IOHIDFloat is a double on 64-bit systems, so both names share one signature.
        (.ioKit, ["IOHIDEventSetDoubleValue", "IOHIDEventSetFloatValue"]),
        (.ioKit, ["IOHIDEventSetEventFlags"]),
        (.ioKit, ["IOHIDEventAppendEvent"]),
        (.skyLight, ["SLEventSetIOHIDEvent"]),
    ]

    let create: Create
    let setInteger: SetInteger
    let setDouble: SetDouble
    let setFlags: SetFlags
    let append: Append
    let attach: Attach

    static let shared: DockSwipeHIDBridge? = load()

    static func systemResolver(_ library: Library, _ name: String) -> UnsafeMutableRawPointer? {
        guard let handle = dlopen(library.rawValue, RTLD_LAZY) else { return nil }
        return dlsym(handle, name)
    }

    static func load(resolver: Resolver = DockSwipeHIDBridge.systemResolver) -> DockSwipeHIDBridge? {
        var addresses: [UnsafeMutableRawPointer] = []
        for symbol in requiredSymbols {
            var address: UnsafeMutableRawPointer?
            for name in symbol.names where address == nil {
                address = resolver(symbol.library, name)
            }
            guard let address else {
                AppSystemLog.problem("Gestures: macOS has no \(symbol.names[0]) here; "
                    + "\"Follow the hand\" is not available and holds use the one-action gestures")
                return nil
            }
            addresses.append(address)
        }
        return DockSwipeHIDBridge(
            create: unsafeBitCast(addresses[0], to: Create.self),
            setInteger: unsafeBitCast(addresses[1], to: SetInteger.self),
            setDouble: unsafeBitCast(addresses[2], to: SetDouble.self),
            setFlags: unsafeBitCast(addresses[3], to: SetFlags.self),
            append: unsafeBitCast(addresses[4], to: Append.self),
            attach: unsafeBitCast(addresses[5], to: Attach.self)
        )
    }

    /// Balances the +1 reference IOHIDEventCreate returned.
    func release(_ event: UnsafeMutableRawPointer) {
        Unmanaged<AnyObject>.fromOpaque(event).release()
    }
}

// MARK: - Event construction (no posting)

struct DockSwipeEventFactory {
    /// Whether the IOHIDEvent carries the current time. A trackpad stamps its events, but
    /// Mac Mouse Fix, the working reference on macOS 27, leaves the timestamp at 0, and Scrollio
    /// does the same. Kept as a switch for hardware tests.
    static let stampsHIDEvents = false
    /// The "fields" layout is followed by an empty type-29 event, as Mac Mouse Fix does.
    static let postsGestureCompanion = true

    let layout: DockSwipeEventLayout
    let bridge: DockSwipeHIDBridge?

    static let system = DockSwipeEventFactory(
        layout: .current,
        bridge: DockSwipeEventLayout.current == .hid ? DockSwipeHIDBridge.shared : nil
    )

    /// False when the layout needs private symbols that this system does not have.
    var isAvailable: Bool {
        return layout == .fields || bridge != nil
    }

    /// The events for one frame, in posting order. Builds them only; nothing is posted.
    func makeEvents(for frame: DockSwipeFrame, naturalScrolling: Bool) -> [CGEvent]? {
        switch layout {
        case .fields:
            guard let event = makeFieldsEvent(for: frame, naturalScrolling: naturalScrolling) else { return nil }
            guard Self.postsGestureCompanion else { return [event] }
            guard let companion = Self.makeMarkedEvent(type: DockSwipeEventEncoding.gestureCompanionEventType) else {
                return nil
            }
            return [event, companion]
        case .hid:
            guard let event = makeHIDEvent(for: frame, naturalScrolling: naturalScrolling) else { return nil }
            return [event]
        }
    }

    private func makeFieldsEvent(for frame: DockSwipeFrame, naturalScrolling: Bool) -> CGEvent? {
        guard let event = Self.makeMarkedEvent(type: DockSwipeEventEncoding.dockControlEventType) else { return nil }
        let values = DockSwipeEventEncoding.fieldValues(for: frame, naturalScrolling: naturalScrolling)
        for (field, value) in values.integers {
            event.setIntegerValueField(Self.field(field), value: value)
        }
        for (field, value) in values.doubles {
            event.setDoubleValueField(Self.field(field), value: value)
        }
        return event
    }

    private func makeHIDEvent(for frame: DockSwipeFrame, naturalScrolling: Bool) -> CGEvent? {
        guard let bridge else { return nil }
        let values = DockSwipeEventEncoding.hidValues(for: frame, naturalScrolling: naturalScrolling)
        let timestamp = Self.stampsHIDEvents ? mach_absolute_time() : 0

        guard let swipe = bridge.create(nil, DockSwipeEventEncoding.hidDockSwipeType, timestamp, 0) else { return nil }
        defer { bridge.release(swipe) }
        bridge.setFlags(swipe, values.eventFlags)
        bridge.setInteger(swipe, DockSwipeEventEncoding.hidDockSwipeMotionField, values.motion)
        bridge.setInteger(swipe, DockSwipeEventEncoding.hidDockSwipeFlavorField, values.flavor)
        bridge.setDouble(swipe, DockSwipeEventEncoding.hidDockSwipeProgressField, values.progress)

        if let velocity = values.velocity {
            guard let child = bridge.create(nil, DockSwipeEventEncoding.hidVelocityType, timestamp, 0) else { return nil }
            defer { bridge.release(child) }
            bridge.setDouble(child, DockSwipeEventEncoding.hidVelocityXField, velocity)
            bridge.setDouble(child, DockSwipeEventEncoding.hidVelocityYField, velocity)
            bridge.append(swipe, child, 0)
        }

        guard let event = Self.makeMarkedEvent(type: DockSwipeEventEncoding.dockControlEventType) else { return nil }
        // SkyLight copies the IOHIDEvent into the CGEvent, so ours is released on return.
        bridge.attach(event, swipe)
        return event
    }

    /// An empty event of a private type, marked as Scrollio's own so every Scrollio event tap skips it.
    private static func makeMarkedEvent(type: UInt32) -> CGEvent? {
        guard let event = CGEvent(source: nil) else { return nil }
        // The private types are not cases of the Swift enum.
        event.type = unsafeBitCast(type, to: CGEventType.self)
        event.setIntegerValueField(.eventSourceUserData, value: ScrollioEventMarker.syntheticCustom)
        return event
    }

    static func field(_ rawValue: UInt32) -> CGEventField {
        // CGEventField is a UInt32-backed C enum; the private numbers are not among its cases.
        return unsafeBitCast(rawValue, to: CGEventField.self)
    }
}

// MARK: - Driver

/// The side effects of a swipe, replaceable in tests so they never reach the Dock.
struct DockSwipeDriver {
    var isAvailable: () -> Bool
    var begin: (DockSwipeAxis) -> Void
    var update: (Double) -> Void
    var end: (Double) -> Void
    var cancel: () -> Void
    /// Posts now, once, what a finished swipe still had to post again, and drops the timers
    /// (`DockSwipeSynthesizer.settle`). The last member and with a default, so a driver made
    /// without it (the test doubles of the sideways swipe) settles nothing.
    var settle: () -> Void = {}

    static let system = DockSwipeDriver(
        isAvailable: { DockSwipeSystemPoster.shared.isAvailable },
        begin: { DockSwipeSystemPoster.shared.begin(axis: $0) },
        update: { DockSwipeSystemPoster.shared.update(progress: $0) },
        end: { DockSwipeSystemPoster.shared.finish(phase: .ended, velocity: $0) },
        cancel: { DockSwipeSystemPoster.shared.finish(phase: .cancelled, velocity: 0) },
        settle: { DockSwipeSystemPoster.shared.settle() }
    )

    /// Used while XCTest runs without an explicit test driver: reports itself unavailable,
    /// so gesture buttons keep the discrete behaviour, and never posts anything.
    static let inert = DockSwipeDriver(
        isAvailable: { false },
        begin: { _ in },
        update: { _ in },
        end: { _ in },
        cancel: {}
    )
}

/// Entry point for the gesture code. Guarantees a well-formed stream whatever the caller
/// does: no update outside began ... terminal, and exactly one terminal per began.
final class DockSwipeSynthesizer {
    static let shared = DockSwipeSynthesizer()

    /// Decided once, because the check is too slow to repeat for every frame of a swipe.
    /// A test process is recognizable from its launch environment on.
    private static let defaultDriver: DockSwipeDriver = AppRuntime.isRunningXCTest ? .inert : .system

    private var testDriver: DockSwipeDriver?
    private var driver: DockSwipeDriver {
        return testDriver ?? Self.defaultDriver
    }

    /// True between `begin` and the terminal call.
    private(set) var isActive = false
    /// The motion of the swipe that runs; nil while none does.
    private(set) var runningAxis: DockSwipeAxis?
    /// Counts the swipes begun. Two drivers share the one swipe the Dock can follow (a
    /// gesture hold and the thumb wheel's "Follow the wheel"): a swipe is the caller's while
    /// it is active and still has the number its `begin` gave it. A `begin` of the other
    /// cancels it (below), and its owner then sends nothing more.
    private(set) var swipeNumber = 0

    /// False when the events cannot be built on this system. Callers then stay discrete.
    var isAvailable: Bool {
        return driver.isAvailable()
    }

    func begin(axis: DockSwipeAxis) {
        // A swipe that was never finished must not be left hanging in the Dock.
        if isActive { cancel() }
        isActive = true
        runningAxis = axis
        swipeNumber &+= 1
        driver.begin(axis)
    }

    /// The swipe numbered `number` is the one running.
    func isRunning(_ number: Int) -> Bool {
        return isActive && swipeNumber == number
    }

    /// Cumulative progress; positive = towards the next Space (horizontal), Mission Control
    /// (vertical) or Show Desktop (pinch).
    func update(progress: Double) {
        guard isActive else { return }
        driver.update(progress)
    }

    /// Lets macOS complete or revert the swipe from its position and the release velocity.
    func end(velocity: Double) {
        guard isActive else { return }
        isActive = false
        runningAxis = nil
        driver.end(velocity)
    }

    /// Returns to what the swipe started from (the Space it began on; the desktop, or the
    /// view that was showing). Safe to call when idle.
    func cancel() {
        guard isActive else { return }
        isActive = false
        runningAxis = nil
        driver.cancel()
    }

    /// The Dock hears one voice about its views at a time. Before Scrollio asks it for a
    /// view in one go (the instant toggle of Mission Control or Show Desktop, the Apps
    /// key), nothing of a motion towards a view may still be on its way: a vertical swipe
    /// or a pinch that runs is cancelled (its owner then sends nothing more, `isRunning`),
    /// and a terminal event that was still to be posted again is posted now, once, and its
    /// timers are dropped. Otherwise that re-post would reach the Dock after the toggle, as
    /// a terminal event of a swipe that never began.
    ///
    /// A swipe of the desktops that runs is left alone (a hold's, the thumb wheel's slide
    /// or its rest after a turn): it ends by itself and the toggle goes out beside it, as
    /// it always did. Taking it back would put the desktop back where the wheel had just
    /// moved it from.
    ///
    /// Safe to call when idle, and as often as wanted. Main thread.
    func settle() {
        if let runningAxis, runningAxis != .horizontal {
            cancel()
        }
        driver.settle()
    }

    #if DEBUG
    func setTestingDriver(_ driver: DockSwipeDriver) {
        cancel()
        testDriver = driver
    }

    func clearTestingDriver() {
        cancel()
        testDriver = nil
    }
    #endif
}

// MARK: - The terminal event, posted again

/// The posts of a swipe's terminal event that are still to come. Under load the Dock can
/// miss the first one and leave the desktop stuck between two Spaces (or a view half open);
/// Mac Mouse Fix posts it again after 0.2 s and 0.5 s for the same reason and reports that
/// it almost always frees it. A terminal event without a began is ignored, and what still
/// waits never outlives its swipe: a new swipe drops it (`drop`), and an instant toggle of
/// a Dock view first posts it once, at once (`postNowAndDrop`), so that nothing of the old
/// swipe arrives after a newer voice. `Event` is what `post` takes (the poster's events; a
/// test's own). Main thread.
final class DockSwipeTerminalResends<Event> {
    /// Runs the work item on the main queue after the delay.
    typealias Schedule = (TimeInterval, DispatchWorkItem) -> Void

    private let delays: [TimeInterval]
    private let schedule: Schedule
    private let post: (Event) -> Void
    private var event: Event?
    private var workItems: [DispatchWorkItem] = []
    private var remaining = 0

    init(delays: [TimeInterval], schedule: @escaping Schedule, post: @escaping (Event) -> Void) {
        self.delays = delays
        self.schedule = schedule
        self.post = post
    }

    /// A post is still to come.
    var isPending: Bool {
        return remaining > 0
    }

    /// The terminal event was posted: it is posted again after each delay. An empty list
    /// of delays turns the re-post off.
    func begin(with event: Event) {
        drop()
        guard !delays.isEmpty else { return }
        self.event = event
        remaining = delays.count
        for delay in delays {
            let workItem = DispatchWorkItem { [weak self] in self?.postOneMore() }
            workItems.append(workItem)
            schedule(delay, workItem)
        }
    }

    private func postOneMore() {
        guard remaining > 0, let event else { return }
        remaining -= 1
        if remaining == 0 { drop() }
        post(event)
    }

    /// Nothing more is posted (a new swipe begins: they must not end it).
    func drop() {
        workItems.forEach { $0.cancel() }
        workItems.removeAll()
        event = nil
        remaining = 0
    }

    /// Posts what was still to come once, now, and drops the timers. False when nothing
    /// waited (then nothing is posted).
    @discardableResult
    func postNowAndDrop() -> Bool {
        guard remaining > 0, let event else { return false }
        drop()
        post(event)
        return true
    }
}

// MARK: - System poster

/// Builds and posts the events. Only reached through `DockSwipeDriver.system`.
private final class DockSwipeSystemPoster {
    static let shared = DockSwipeSystemPoster()

    /// The terminal event is posted again after these delays (`DockSwipeTerminalResends`
    /// says why). A new swipe drops the pending re-posts, so they cannot end a later
    /// gesture; `settle` brings them forward. An empty list turns the re-send off.
    static let terminalResendDelays: [TimeInterval] = [0.2, 0.5]

    private let factory = DockSwipeEventFactory.system
    private var axis = DockSwipeAxis.horizontal
    private var naturalScrolling = true
    private var hasPostedBegan = false
    private var lastProgress: Double = 0
    private lazy var resends = DockSwipeTerminalResends<[CGEvent]>(
        delays: DockSwipeSystemPoster.terminalResendDelays,
        schedule: { delay, workItem in DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem) },
        post: { [weak self] events in self?.post(events) }
    )

    var isAvailable: Bool {
        return factory.isAvailable
    }

    func begin(axis: DockSwipeAxis) {
        resends.drop()
        self.axis = axis
        // Read once per swipe: a change mid-swipe must not flip the direction under the hand.
        // (Only the horizontal motion uses it.)
        naturalScrolling = Self.isNaturalScrollingEnabled()
        hasPostedBegan = false
        lastProgress = 0
    }

    /// The first update goes out as `began` and carries the first movement, like a hand
    /// that has just started to move; later ones are `changed`.
    func update(progress: Double) {
        let phase: DockSwipePhase = hasPostedBegan ? .changed : .began
        let frame = DockSwipeFrame(phase: phase, axis: axis, progress: progress)
        guard let events = factory.makeEvents(for: frame, naturalScrolling: naturalScrolling) else { return }
        post(events)
        hasPostedBegan = true
        lastProgress = progress
    }

    /// The terminal event repeats the last progress and adds the velocity.
    func finish(phase: DockSwipePhase, velocity: Double) {
        // Nothing reached the Dock yet, so there is nothing to finish.
        guard hasPostedBegan else { return }
        hasPostedBegan = false
        let frame = DockSwipeFrame(phase: phase, axis: axis, progress: lastProgress, velocity: velocity)
        guard let events = factory.makeEvents(for: frame, naturalScrolling: naturalScrolling) else {
            AppSystemLog.problem("Gestures: the last event of a swipe could not be built; the swipe was not finished")
            return
        }
        post(events)
        resends.begin(with: events)
    }

    /// The terminal event of a swipe that just finished, if it still waits to be posted
    /// again: posted now, once, and its timers dropped (`DockSwipeSynthesizer.settle`).
    func settle() {
        resends.postNowAndDrop()
    }

    private static let wasLaunchedForTests = AppRuntime.isRunningXCTest

    private func post(_ events: [CGEvent]) {
        // Second line of defence: tests must never move the real desktops.
        guard !Self.wasLaunchedForTests, NSClassFromString("XCTestCase") == nil else { return }
        for event in events {
            event.post(tap: .cgSessionEventTap)
        }
    }

    /// An absent key means natural scrolling is on (the default since OS X 10.7).
    static func isNaturalScrollingEnabled(defaults: UserDefaults = .standard) -> Bool {
        return (defaults.object(forKey: "com.apple.swipescrolldirection") as? NSNumber)?.boolValue ?? true
    }
}

// MARK: - Geometry

/// How pointer travel maps to swipe progress.
enum DockSwipeGeometry {
    /// Gap the Dock draws between two Spaces while they slide. Mac Mouse Fix measured 63 pt;
    /// counting it keeps the desktop under the pointer instead of drifting ahead by about 4 %.
    static let spaceSeparatorWidth: CGFloat = 63

    /// Progress that moves the desktop by exactly one Space. Mac Mouse Fix found that the
    /// Dock scales progress with the number of Spaces on the display: 1 + 1 / (count - 1),
    /// and 2 with a single Space (rubber band only). Without the count Scrollio assumes 1.
    static func progressPerSpace(spaceCount: Int?) -> Double {
        guard let spaceCount else { return 1 }
        guard spaceCount >= 2 else { return 2 }
        return 1 + 1 / Double(spaceCount - 1)
    }

    /// Progress per point of pointer travel at the given tracking speed.
    static func progressPerPoint(screenWidth: CGFloat, spaceCount: Int?, trackingSpeed: Double) -> Double {
        let spaceWidth = Double(max(screenWidth, 1) + spaceSeparatorWidth)
        return trackingSpeed * progressPerSpace(spaceCount: spaceCount) / spaceWidth
    }

    // MARK: Mission Control, Show Desktop, Apps (the vertical motion and the pinch)

    /// Points of hand travel that take `target` from nothing to whole at Swipe speed 1: a
    /// share of the height of the screen under the pointer, kept within bounds, and shorter
    /// for Apps (`DockFollowTuning`). There are no Spaces on these motions: no count and no
    /// separator. A height that is no number counts as the default screen's.
    static func followTravel(for target: DockFollowTarget, screenHeight: CGFloat) -> CGFloat {
        let height = screenHeight.isFinite ? screenHeight : InteractiveGestureScreen.defaultHeight
        let range = DockFollowTuning.travelRange
        let travel = min(max(DockFollowTuning.travelScreenShare * height, range.lowerBound), range.upperBound)
        return travel * DockFollowTuning.travelFactor(for: target)
    }

    /// Progress per point of hand travel towards `target` at the given Swipe speed: the
    /// speed over the travel (full progress is `DockFollowTuning.fullProgress`). Always
    /// positive: the direction is the target's `sign`.
    static func followProgressPerPoint(for target: DockFollowTarget, screenHeight: CGFloat, trackingSpeed: Double) -> Double {
        return trackingSpeed * DockFollowTuning.fullProgress / Double(followTravel(for: target, screenHeight: screenHeight))
    }

    private typealias MainConnection = @convention(c) () -> Int32
    private typealias CopyManagedDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?

    /// Window server calls for the Space list, resolved once. Nil when either is missing;
    /// the swipe still works then, with the scale of an unknown Space count.
    private static let spacesAPI: (mainConnection: MainConnection, copySpaces: CopyManagedDisplaySpaces)? = {
        guard let mainConnection = DockSwipeHIDBridge.systemResolver(.skyLight, "CGSMainConnectionID"),
              let copySpaces = DockSwipeHIDBridge.systemResolver(.skyLight, "CGSCopyManagedDisplaySpaces") else {
            return nil
        }
        return (
            unsafeBitCast(mainConnection, to: MainConnection.self),
            unsafeBitCast(copySpaces, to: CopyManagedDisplaySpaces.self)
        )
    }()

    /// Number of Spaces (full-screen apps included) on a display, read from the window
    /// server. Nil when the private calls are missing or the display is not listed.
    static func spaceCount(forDisplay displayID: CGDirectDisplayID) -> Int? {
        guard let api = spacesAPI,
              let displays = api.copySpaces(api.mainConnection())?.takeRetainedValue() as? [[String: Any]] else {
            return nil
        }

        var identifier: String?
        if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() {
            identifier = CFUUIDCreateString(nil, uuid) as String?
        }
        return spaceCount(inManagedDisplaySpaces: displays, displayIdentifier: identifier)
    }

    /// With "Displays have separate Spaces" off there is a single entry named "Main".
    static func spaceCount(inManagedDisplaySpaces displays: [[String: Any]], displayIdentifier: String?) -> Int? {
        let match = displays.first { ($0["Display Identifier"] as? String) == displayIdentifier }
        guard let entry = match ?? (displays.count == 1 ? displays.first : nil),
              let spaces = entry["Spaces"] as? [Any] else {
            return nil
        }
        return spaces.count
    }
}
