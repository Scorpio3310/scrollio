import XCTest
@testable import Scrollio_Debug

/// The dock swipe events are checked by value. Nothing in this file posts an event: frames
/// are encoded, or built into CGEvents and read back.
final class DockSwipeSynthesizerTests: XCTestCase {

    private typealias Encoding = DockSwipeEventEncoding

    override func tearDown() {
        DockSwipeSynthesizer.shared.clearTestingDriver()
        super.tearDown()
    }

    // MARK: - Layout choice

    func testLayoutFollowsTheMacOSMajorVersion() {
        XCTAssertEqual(DockSwipeEventLayout.layout(forMajorVersion: 12), .fields)
        XCTAssertEqual(DockSwipeEventLayout.layout(forMajorVersion: 15), .fields)
        XCTAssertEqual(DockSwipeEventLayout.layout(forMajorVersion: 26), .fields)
        XCTAssertEqual(DockSwipeEventLayout.layout(forMajorVersion: 27), .hid)
        XCTAssertEqual(DockSwipeEventLayout.layout(forMajorVersion: 28), .hid)
    }

    // MARK: - "fields" layout values

    func testFieldValuesOfAChangedFrame() {
        let frame = DockSwipeFrame(phase: .changed, axis: .horizontal, progress: 0.25)
        let values = Encoding.fieldValues(for: frame, naturalScrolling: true)

        XCTAssertEqual(values.integers, [
            110: 23,
            132: 2, 134: 2,
            123: 1, 165: 1,
            135: Int64(Float(0.25).bitPattern),
            136: 1,
        ])
        // Motion 1 as float32 bits read as a double: the smallest subnormal float.
        XCTAssertEqual(values.doubles[119], Double(Float.leastNonzeroMagnitude))
        XCTAssertEqual(values.doubles[139], Double(Float.leastNonzeroMagnitude))
        XCTAssertEqual(values.doubles[124], 0.25)
        XCTAssertNil(values.doubles[129], "velocity only on a terminal frame")
        XCTAssertNil(values.doubles[130])
    }

    func testFieldValuesKeepTheSignWhateverTheScrollingPreference() {
        let frame = DockSwipeFrame(phase: .changed, axis: .horizontal, progress: -0.4)
        let natural = Encoding.fieldValues(for: frame, naturalScrolling: true)
        let classic = Encoding.fieldValues(for: frame, naturalScrolling: false)

        XCTAssertEqual(natural.doubles[124], -0.4)
        XCTAssertEqual(classic.doubles[124], -0.4)
        XCTAssertEqual(natural.integers[135], Int64(Float(-0.4).bitPattern))
        XCTAssertEqual(natural.integers[136], 1)
        XCTAssertEqual(classic.integers[136], 0)
    }

    func testFieldValuesOfTerminalFramesCarryPhaseAndVelocity() {
        let ended = Encoding.fieldValues(
            for: DockSwipeFrame(phase: .ended, axis: .horizontal, progress: 0.6, velocity: 1.5),
            naturalScrolling: true
        )
        XCTAssertEqual(ended.integers[132], 4)
        XCTAssertEqual(ended.integers[134], 4)
        XCTAssertEqual(ended.doubles[124], 0.6)
        XCTAssertEqual(ended.doubles[129], 1.5)
        XCTAssertEqual(ended.doubles[130], 1.5)

        let cancelled = Encoding.fieldValues(
            for: DockSwipeFrame(phase: .cancelled, axis: .horizontal, progress: 0.1),
            naturalScrolling: true
        )
        XCTAssertEqual(cancelled.integers[132], 8)
        XCTAssertEqual(cancelled.doubles[129], 0)

        let began = Encoding.fieldValues(
            for: DockSwipeFrame(phase: .began, axis: .vertical, progress: 0.01),
            naturalScrolling: true
        )
        XCTAssertEqual(began.integers[132], 1)
        XCTAssertEqual(began.integers[123], 2)
        XCTAssertEqual(began.doubles[119], Double(Float(bitPattern: 2)))
    }

    // MARK: - "hid" layout values

    func testHIDValuesUseDeviceCoordinates() {
        let frame = DockSwipeFrame(phase: .changed, axis: .horizontal, progress: 0.25)

        // Natural scrolling on: the Dock moves the desktop with the fingers, so "next Space"
        // is a negative device offset.
        let natural = Encoding.hidValues(for: frame, naturalScrolling: true)
        XCTAssertEqual(natural.eventFlags, 2 << 24)
        XCTAssertEqual(natural.motion, 1)
        XCTAssertEqual(natural.flavor, 3)
        XCTAssertEqual(natural.progress, -0.25)
        XCTAssertNil(natural.velocity)

        // Off: the Dock flips it, so Scrollio sends the opposite sign for the same result.
        let classic = Encoding.hidValues(for: frame, naturalScrolling: false)
        XCTAssertEqual(classic.progress, 0.25)
    }

    func testHIDValuesOfTerminalFrames() {
        let ended = Encoding.hidValues(
            for: DockSwipeFrame(phase: .ended, axis: .horizontal, progress: 0.6, velocity: 1.5),
            naturalScrolling: true
        )
        XCTAssertEqual(ended.eventFlags, 4 << 24)
        XCTAssertEqual(ended.progress, -0.6)
        XCTAssertEqual(ended.velocity, -1.5)

        let cancelled = Encoding.hidValues(
            for: DockSwipeFrame(phase: .cancelled, axis: .horizontal, progress: -0.2),
            naturalScrolling: false
        )
        XCTAssertEqual(cancelled.eventFlags, 8 << 24)
        XCTAssertEqual(cancelled.progress, -0.2)
        XCTAssertEqual(cancelled.velocity, 0)

        XCTAssertEqual(
            Encoding.hidValues(for: DockSwipeFrame(phase: .began, axis: .horizontal, progress: 0), naturalScrolling: true).eventFlags,
            1 << 24
        )
    }

    func testHIDValuesStayInsideTheFixedPointRange() {
        let wild = DockSwipeFrame(phase: .ended, axis: .horizontal, progress: 1e9, velocity: -.infinity)
        let values = Encoding.hidValues(for: wild, naturalScrolling: false)
        XCTAssertEqual(values.progress, 32_000)
        XCTAssertEqual(values.velocity, 0, "a non-finite velocity is dropped")

        let fast = DockSwipeFrame(phase: .ended, axis: .horizontal, progress: 0.5, velocity: 1e6)
        XCTAssertEqual(Encoding.hidValues(for: fast, naturalScrolling: true).velocity, -32_000)
        XCTAssertLessThan(Encoding.fixedPointLimit, 32_768)
    }

    func testHIDFieldNumbers() {
        XCTAssertEqual(Encoding.hidDockSwipeMotionField, 0x0017_0001)
        XCTAssertEqual(Encoding.hidDockSwipeProgressField, 0x0017_0002)
        XCTAssertEqual(Encoding.hidDockSwipeFlavorField, 0x0017_0005)
        XCTAssertEqual(Encoding.hidVelocityXField, 0x0009_0000)
        XCTAssertEqual(Encoding.hidVelocityYField, 0x0009_0001)
    }

    // MARK: - Mission Control (vertical) and the pinch: a fixed sign

    func testTheThreeMotionsAreTheHIDGestureMotions() {
        XCTAssertEqual(DockSwipeAxis.horizontal.rawValue, 1)
        XCTAssertEqual(DockSwipeAxis.vertical.rawValue, 2, "Mission Control / App Exposé")
        XCTAssertEqual(DockSwipeAxis.pinch.rawValue, 3, "the HID \"scale\" motion: Show Desktop / Launchpad")
    }

    /// Scrollio's own sign on these two axes: positive opens Mission Control (vertical) and
    /// Show Desktop (pinch). In the "fields" layout that is the value turned over with the
    /// flag set, as a trackpad with natural scrolling sends it, whatever the preference is.
    func testFieldValuesOfAVerticalAndAPinchFrameIgnoreTheScrollingPreference() {
        let motions: [(DockSwipeAxis, Int64, Double)] = [
            (.vertical, 2, 2.802596928649634e-45),
            (.pinch, 3, 4.203895392974451e-45),
        ]
        for (axis, motion, motionAsDouble) in motions {
            let frame = DockSwipeFrame(phase: .changed, axis: axis, progress: 0.25)
            for naturalScrolling in [true, false] {
                let values = Encoding.fieldValues(for: frame, naturalScrolling: naturalScrolling)
                let name = "\(axis), natural scrolling \(naturalScrolling)"
                // The whole of it, so that nothing of another motion leaks in.
                XCTAssertEqual(values.integers, [
                    110: 23,
                    132: 2, 134: 2,
                    123: motion, 165: motion,
                    135: 3_196_059_648, // the bits of Float(-0.25)
                    136: 1,
                ], name)
                XCTAssertEqual(values.doubles, [119: motionAsDouble, 139: motionAsDouble, 124: -0.25], name)
            }
        }
    }

    /// The other end of each axis (App Exposé; Launchpad / Apps) is the negative progress.
    func testFieldValuesOfTheOtherEndOfAVerticalAndAPinchFrame() {
        for axis in [DockSwipeAxis.vertical, .pinch] {
            let values = Encoding.fieldValues(
                for: DockSwipeFrame(phase: .changed, axis: axis, progress: -0.5), naturalScrolling: false
            )
            XCTAssertEqual(values.doubles[124], 0.5, "\(axis)")
            XCTAssertEqual(values.integers[135], 1_056_964_608, "\(axis): the bits of Float(0.5)")
            XCTAssertEqual(values.integers[136], 1, "\(axis)")
        }
    }

    /// The velocity carries the sign of the progress, so it is turned over with it.
    func testFieldValuesOfTerminalVerticalAndPinchFrames() {
        for naturalScrolling in [true, false] {
            let ended = Encoding.fieldValues(
                for: DockSwipeFrame(phase: .ended, axis: .pinch, progress: 0.5, velocity: 1.5),
                naturalScrolling: naturalScrolling
            )
            XCTAssertEqual(ended.integers[132], 4)
            XCTAssertEqual(ended.integers[134], 4)
            XCTAssertEqual(ended.integers[123], 3)
            XCTAssertEqual(ended.doubles[124], -0.5)
            XCTAssertEqual(ended.integers[135], 3_204_448_256, "the bits of Float(-0.5)")
            XCTAssertEqual(ended.integers[136], 1)
            XCTAssertEqual(ended.doubles[129], -1.5)
            XCTAssertEqual(ended.doubles[130], -1.5)

            let cancelled = Encoding.fieldValues(
                for: DockSwipeFrame(phase: .cancelled, axis: .vertical, progress: 0.3125),
                naturalScrolling: naturalScrolling
            )
            XCTAssertEqual(cancelled.integers[132], 8)
            XCTAssertEqual(cancelled.doubles[124], -0.3125)
            XCTAssertEqual(cancelled.integers[135], 3_198_156_800, "the bits of Float(-0.3125)")
            XCTAssertEqual(cancelled.doubles[129], 0)
            XCTAssertEqual(cancelled.doubles[130], 0)
        }
    }

    /// Nothing moved yet: a plain zero, not a negative one (field 135 carries the bits).
    func testAVerticalOrPinchFrameAtTheStartIsAPlainZero() throws {
        for axis in [DockSwipeAxis.vertical, .pinch] {
            let values = Encoding.fieldValues(
                for: DockSwipeFrame(phase: .cancelled, axis: axis, progress: 0), naturalScrolling: true
            )
            XCTAssertEqual(values.integers[135], 0, "\(axis)")
            XCTAssertEqual(try XCTUnwrap(values.doubles[124]).sign, .plus, "\(axis)")
            XCTAssertEqual(try XCTUnwrap(values.doubles[129]).sign, .plus, "\(axis)")
        }
    }

    /// The "hid" layout carries Scrollio's value as it is on these two axes: the Dock does
    /// not turn them with the scrolling preference, and Scrollio does not either.
    func testHIDValuesOfAVerticalAndAPinchFrameIgnoreTheScrollingPreference() {
        for (axis, motion) in [(DockSwipeAxis.vertical, 2), (.pinch, 3)] {
            for naturalScrolling in [true, false] {
                let name = "\(axis), natural scrolling \(naturalScrolling)"
                let changed = Encoding.hidValues(
                    for: DockSwipeFrame(phase: .changed, axis: axis, progress: 0.3125), naturalScrolling: naturalScrolling
                )
                XCTAssertEqual(changed, DockSwipeHIDValues(
                    eventFlags: 2 << 24, motion: motion, flavor: 3, progress: 0.3125, velocity: nil
                ), name)

                let ended = Encoding.hidValues(
                    for: DockSwipeFrame(phase: .ended, axis: axis, progress: -0.5, velocity: -1.5),
                    naturalScrolling: naturalScrolling
                )
                XCTAssertEqual(ended, DockSwipeHIDValues(
                    eventFlags: 4 << 24, motion: motion, flavor: 3, progress: -0.5, velocity: -1.5
                ), name)

                let wild = Encoding.hidValues(
                    for: DockSwipeFrame(phase: .ended, axis: axis, progress: 1e9, velocity: -.infinity),
                    naturalScrolling: naturalScrolling
                )
                XCTAssertEqual(wild.progress, 32_000, name)
                XCTAssertEqual(wild.velocity, 0, name)
            }
        }
    }

    /// Only sideways asks for the scrolling preference: the desktops move as content does.
    func testOnlyTheSidewaysMotionFollowsTheScrollingPreference() {
        XCTAssertTrue(DockSwipeAxis.horizontal.followsScrollingPreference)
        XCTAssertFalse(DockSwipeAxis.vertical.followsScrollingPreference)
        XCTAssertFalse(DockSwipeAxis.pinch.followsScrollingPreference)
    }

    // MARK: - Built events (never posted)

    func testFieldsEventOfAVerticalAndAPinchFrameCarriesTheFixedSign() throws {
        let factory = DockSwipeEventFactory(layout: .fields, bridge: nil)
        for (axis, motion) in [(DockSwipeAxis.vertical, Int64(2)), (.pinch, Int64(3))] {
            let frame = DockSwipeFrame(phase: .ended, axis: axis, progress: 0.25, velocity: 1.5)
            let events = try XCTUnwrap(factory.makeEvents(for: frame, naturalScrolling: false))
            XCTAssertEqual(events.map { $0.type.rawValue }, [30, 29])
            for event in events {
                XCTAssertEqual(event.getIntegerValueField(.eventSourceUserData), ScrollioEventMarker.syntheticCustom)
            }
            let event = events[0]
            func integer(_ field: UInt32) -> Int64 { event.getIntegerValueField(DockSwipeEventFactory.field(field)) }
            func double(_ field: UInt32) -> Double { event.getDoubleValueField(DockSwipeEventFactory.field(field)) }
            XCTAssertEqual(integer(110), 23, "\(axis)")
            XCTAssertEqual(integer(123), motion, "\(axis)")
            XCTAssertEqual(integer(132), 4, "\(axis)")
            XCTAssertEqual(double(124), -0.25, "\(axis)")
            XCTAssertEqual(integer(136), 1, "\(axis): the flag is set whatever the preference")
            XCTAssertEqual(double(129), -1.5, "\(axis)")
        }
    }

    /// The macOS 27 event of the two motions, built with the real symbols and read back.
    /// Skipped where the private symbols do not exist.
    func testHIDEventOfAVerticalAndAPinchFrameCarriesTheMotionAndTheSign() throws {
        guard let bridge = DockSwipeHIDBridge.load() else {
            throw XCTSkip("IOKit / SkyLight symbols for the attached IOHIDEvent are missing")
        }
        guard let reader = HIDEventReader() else {
            throw XCTSkip("IOHIDEvent read-back symbols are missing")
        }
        let factory = DockSwipeEventFactory(layout: .hid, bridge: bridge)
        for (axis, motion) in [(DockSwipeAxis.vertical, 2), (.pinch, 3)] {
            let changed = try XCTUnwrap(factory.makeEvents(
                for: DockSwipeFrame(phase: .changed, axis: axis, progress: 0.3125), naturalScrolling: true
            ))
            XCTAssertEqual(changed.count, 1)
            XCTAssertEqual(changed[0].type.rawValue, 30)
            let changedHID = try XCTUnwrap(reader.copyHIDEvent(changed[0]))
            defer { reader.release(changedHID) }
            XCTAssertEqual(reader.type(changedHID), 23)
            XCTAssertEqual(reader.flags(changedHID), 2 << 24)
            XCTAssertEqual(reader.integer(changedHID, Encoding.hidDockSwipeMotionField), motion)
            XCTAssertEqual(reader.integer(changedHID, Encoding.hidDockSwipeFlavorField), 3)
            XCTAssertEqual(reader.double(changedHID, Encoding.hidDockSwipeProgressField), 0.3125, "\(axis): not turned over")
            XCTAssertEqual(reader.children(changedHID).count, 0)

            let ended = try XCTUnwrap(factory.makeEvents(
                for: DockSwipeFrame(phase: .ended, axis: axis, progress: 0.5, velocity: 1.5), naturalScrolling: true
            ))
            let endedHID = try XCTUnwrap(reader.copyHIDEvent(ended[0]))
            defer { reader.release(endedHID) }
            XCTAssertEqual(reader.flags(endedHID), 4 << 24)
            XCTAssertEqual(reader.double(endedHID, Encoding.hidDockSwipeProgressField), 0.5)
            let children = reader.children(endedHID)
            XCTAssertEqual(children.count, 1)
            if let velocity = children.first {
                XCTAssertEqual(reader.type(velocity), 9)
                XCTAssertEqual(reader.double(velocity, Encoding.hidVelocityXField), 1.5)
                XCTAssertEqual(reader.double(velocity, Encoding.hidVelocityYField), 1.5)
            }
        }
    }

    func testFieldsEventCarriesTypeMarkerAndFields() throws {
        let factory = DockSwipeEventFactory(layout: .fields, bridge: nil)
        XCTAssertTrue(factory.isAvailable, "the fields layout needs no private symbols")

        let frame = DockSwipeFrame(phase: .ended, axis: .horizontal, progress: 0.25, velocity: 1.5)
        let events = try XCTUnwrap(factory.makeEvents(for: frame, naturalScrolling: true))
        XCTAssertEqual(events.map { $0.type.rawValue }, [30, 29], "dock event first, then the empty companion")
        for event in events {
            XCTAssertEqual(event.getIntegerValueField(.eventSourceUserData), ScrollioEventMarker.syntheticCustom)
        }

        let event = events[0]
        func integer(_ field: UInt32) -> Int64 { event.getIntegerValueField(DockSwipeEventFactory.field(field)) }
        func double(_ field: UInt32) -> Double { event.getDoubleValueField(DockSwipeEventFactory.field(field)) }
        XCTAssertEqual(integer(110), 23)
        XCTAssertEqual(integer(132), 4)
        XCTAssertEqual(integer(123), 1)
        XCTAssertEqual(double(124), 0.25)
        XCTAssertEqual(integer(135), Int64(Float(0.25).bitPattern))
        XCTAssertEqual(integer(136), 1)
        XCTAssertEqual(double(129), 1.5)
    }

    func testHIDLayoutIsUnavailableWithoutItsSymbols() {
        XCTAssertFalse(DockSwipeEventFactory(layout: .hid, bridge: nil).isAvailable)
        XCTAssertNil(
            DockSwipeEventFactory(layout: .hid, bridge: nil)
                .makeEvents(for: DockSwipeFrame(phase: .began, axis: .horizontal, progress: 0), naturalScrolling: true)
        )
    }

    func testBridgeLoadFailsWhenAnySymbolIsMissing() {
        for missing in ["IOHIDEventCreate", "IOHIDEventSetEventFlags", "IOHIDEventAppendEvent", "SLEventSetIOHIDEvent"] {
            let bridge = DockSwipeHIDBridge.load { library, name in
                name == missing ? nil : DockSwipeHIDBridge.systemResolver(library, name)
            }
            XCTAssertNil(bridge, "\(missing) missing must make the bridge unavailable")
        }
        // The float setter has two names; one is enough, none is not.
        let withoutBothSetters = DockSwipeHIDBridge.load { library, name in
            name.hasPrefix("IOHIDEventSetDoubleValue") || name.hasPrefix("IOHIDEventSetFloatValue")
                ? nil
                : DockSwipeHIDBridge.systemResolver(library, name)
        }
        XCTAssertNil(withoutBothSetters)
    }

    /// Builds the macOS 27 event with the real IOKit / SkyLight symbols and reads the attached
    /// IOHIDEvent back. Skipped where the private symbols do not exist.
    func testHIDEventCarriesTheAttachedIOHIDEvent() throws {
        guard let bridge = DockSwipeHIDBridge.load() else {
            throw XCTSkip("IOKit / SkyLight symbols for the attached IOHIDEvent are missing")
        }
        guard let reader = HIDEventReader() else {
            throw XCTSkip("IOHIDEvent read-back symbols are missing")
        }
        let factory = DockSwipeEventFactory(layout: .hid, bridge: bridge)
        XCTAssertTrue(factory.isAvailable)

        let changed = try XCTUnwrap(factory.makeEvents(
            for: DockSwipeFrame(phase: .changed, axis: .horizontal, progress: 0.3125),
            naturalScrolling: true
        ))
        XCTAssertEqual(changed.count, 1)
        XCTAssertEqual(changed[0].type.rawValue, 30)
        XCTAssertEqual(changed[0].getIntegerValueField(.eventSourceUserData), ScrollioEventMarker.syntheticCustom)
        let changedHID = try XCTUnwrap(reader.copyHIDEvent(changed[0]))
        defer { reader.release(changedHID) }
        XCTAssertEqual(reader.type(changedHID), 23)
        XCTAssertEqual(reader.flags(changedHID), 2 << 24)
        XCTAssertEqual(reader.integer(changedHID, Encoding.hidDockSwipeMotionField), 1)
        XCTAssertEqual(reader.integer(changedHID, Encoding.hidDockSwipeFlavorField), 3)
        // 16.16 fixed point: 0.3125 is exact.
        XCTAssertEqual(reader.double(changedHID, Encoding.hidDockSwipeProgressField), -0.3125)
        XCTAssertEqual(reader.children(changedHID).count, 0)

        let ended = try XCTUnwrap(factory.makeEvents(
            for: DockSwipeFrame(phase: .ended, axis: .horizontal, progress: 0.5, velocity: 1.5),
            naturalScrolling: false
        ))
        let endedHID = try XCTUnwrap(reader.copyHIDEvent(ended[0]))
        defer { reader.release(endedHID) }
        XCTAssertEqual(reader.flags(endedHID), 4 << 24)
        XCTAssertEqual(reader.double(endedHID, Encoding.hidDockSwipeProgressField), 0.5)
        let children = reader.children(endedHID)
        XCTAssertEqual(children.count, 1)
        if let velocity = children.first {
            XCTAssertEqual(reader.type(velocity), 9)
            XCTAssertEqual(reader.double(velocity, Encoding.hidVelocityXField), 1.5)
            XCTAssertEqual(reader.double(velocity, Encoding.hidVelocityYField), 1.5)
        }
    }

    // MARK: - Own events and Scrollio's event taps

    func testNoScrollioEventTapListensToDockSwipeEvents() {
        let masks: [(String, CGEventMask)] = [
            ("motion", MouseInteractionSessionController.motionEventMask),
            ("buttons", ButtonCore.shared.dispatchEventMask),
            ("scroll", ScrollCore.shared.scrollEventMask),
            ("hotkey", ScrollCore.shared.hotkeyEventMask),
            ("left mouse", ScrollCore.shared.mouseLeftEventMask),
        ]
        for type in Encoding.ownEventTypes {
            for (name, mask) in masks {
                XCTAssertEqual(mask & (CGEventMask(1) << CGEventMask(type)), 0, "\(name) tap must not see event type \(type)")
            }
        }
        XCTAssertEqual(Encoding.ownEventTypes, [29, 30])
    }

    // MARK: - Synthesizer guards

    private func installRecordingDriver(available: Bool = true) -> () -> [String] {
        var calls: [String] = []
        DockSwipeSynthesizer.shared.setTestingDriver(DockSwipeDriver(
            isAvailable: { available },
            begin: { calls.append("begin \($0)") },
            update: { calls.append("update \($0)") },
            end: { calls.append("end \($0)") },
            cancel: { calls.append("cancel") }
        ))
        return { calls }
    }

    func testSynthesizerIsInertUnderXCTestWithoutADriver() {
        DockSwipeSynthesizer.shared.clearTestingDriver()
        XCTAssertFalse(DockSwipeSynthesizer.shared.isAvailable, "tests must never reach the system driver")
        DockSwipeSynthesizer.shared.begin(axis: .horizontal)
        DockSwipeSynthesizer.shared.update(progress: 0.5)
        DockSwipeSynthesizer.shared.end(velocity: 1)
        XCTAssertFalse(DockSwipeSynthesizer.shared.isActive)
        XCTAssertFalse(DockSwipeDriver.inert.isAvailable())
    }

    func testSynthesizerReportsDriverAvailability() {
        _ = installRecordingDriver(available: false)
        XCTAssertFalse(DockSwipeSynthesizer.shared.isAvailable)
        _ = installRecordingDriver(available: true)
        XCTAssertTrue(DockSwipeSynthesizer.shared.isAvailable)
    }

    func testSynthesizerForwardsAWellFormedSwipe() {
        let calls = installRecordingDriver()
        let synthesizer = DockSwipeSynthesizer.shared

        synthesizer.begin(axis: .horizontal)
        XCTAssertTrue(synthesizer.isActive)
        synthesizer.update(progress: 0.1)
        synthesizer.update(progress: 0.2)
        synthesizer.end(velocity: 1.5)
        XCTAssertFalse(synthesizer.isActive)

        XCTAssertEqual(calls(), ["begin horizontal", "update 0.1", "update 0.2", "end 1.5"])
    }

    func testSynthesizerDropsCallsOutsideASwipe() {
        let calls = installRecordingDriver()
        let synthesizer = DockSwipeSynthesizer.shared

        synthesizer.update(progress: 0.1)
        synthesizer.end(velocity: 1)
        synthesizer.cancel()
        XCTAssertEqual(calls(), [])

        synthesizer.begin(axis: .horizontal)
        synthesizer.cancel()
        synthesizer.cancel()
        synthesizer.end(velocity: 1)
        synthesizer.update(progress: 0.3)
        XCTAssertEqual(calls(), ["begin horizontal", "cancel"], "exactly one terminal per began")
    }

    func testSynthesizerCancelsAnUnfinishedSwipeBeforeBeginningAnother() {
        let calls = installRecordingDriver()
        let synthesizer = DockSwipeSynthesizer.shared

        synthesizer.begin(axis: .horizontal)
        synthesizer.update(progress: 0.1)
        synthesizer.begin(axis: .horizontal)
        synthesizer.end(velocity: 0)

        XCTAssertEqual(calls(), ["begin horizontal", "update 0.1", "cancel", "begin horizontal", "end 0.0"])
    }

    func testReplacingTheDriverCancelsARunningSwipe() {
        let calls = installRecordingDriver()
        DockSwipeSynthesizer.shared.begin(axis: .horizontal)
        DockSwipeSynthesizer.shared.clearTestingDriver()
        XCTAssertEqual(calls(), ["begin horizontal", "cancel"])
        XCTAssertFalse(DockSwipeSynthesizer.shared.isActive)
    }

    func testSynthesizerForwardsAVerticalAndAPinchSwipeAndKnowsWhichRuns() {
        let calls = installRecordingDriver()
        let synthesizer = DockSwipeSynthesizer.shared
        XCTAssertNil(synthesizer.runningAxis)

        synthesizer.begin(axis: .vertical)
        XCTAssertEqual(synthesizer.runningAxis, .vertical)
        synthesizer.update(progress: 0.25)
        synthesizer.end(velocity: 2)
        XCTAssertNil(synthesizer.runningAxis)

        synthesizer.begin(axis: .pinch)
        XCTAssertEqual(synthesizer.runningAxis, .pinch)
        synthesizer.cancel()
        XCTAssertNil(synthesizer.runningAxis)

        // A sideways swipe that runs is cancelled before another motion begins.
        synthesizer.begin(axis: .horizontal)
        XCTAssertEqual(synthesizer.runningAxis, .horizontal)
        synthesizer.begin(axis: .vertical)
        XCTAssertEqual(synthesizer.runningAxis, .vertical)
        synthesizer.cancel()

        XCTAssertEqual(calls(), [
            "begin vertical", "update 0.25", "end 2.0",
            "begin pinch", "cancel",
            "begin horizontal", "cancel", "begin vertical", "cancel",
        ])
    }

    /// The end of a swipe of the desktops is told (macOS reports the change of the desktop
    /// late, and the gestures must know it for their own): only an end, and only sideways.
    func testTheEndOfASwipeOfTheDesktopsIsTold() {
        // Its own synthesizer: under XCTest it has the driver that does nothing.
        let synthesizer = DockSwipeSynthesizer()
        var told = 0
        synthesizer.desktopsSwipeDidEnd = { told += 1 }

        synthesizer.begin(axis: .horizontal)
        synthesizer.update(progress: 0.6)
        XCTAssertEqual(told, 0)
        synthesizer.end(velocity: 1)
        XCTAssertEqual(told, 1)
        synthesizer.end(velocity: 1)
        XCTAssertEqual(told, 1, "nothing ran")

        // Taken back: the desktop stays, no change follows.
        synthesizer.begin(axis: .horizontal)
        synthesizer.cancel()
        synthesizer.begin(axis: .horizontal)
        synthesizer.begin(axis: .horizontal)
        synthesizer.settle()
        XCTAssertEqual(told, 1)
        synthesizer.end(velocity: 0)
        XCTAssertEqual(told, 2)

        // A motion towards a view is no swipe of the desktops.
        for axis in [DockSwipeAxis.vertical, .pinch] {
            synthesizer.begin(axis: axis)
            synthesizer.end(velocity: 3)
        }
        XCTAssertEqual(told, 2)
    }

    // MARK: - Settling before an instant toggle

    /// A driver that also records `settle`.
    private func installSettlingDriver() -> () -> [String] {
        var calls: [String] = []
        DockSwipeSynthesizer.shared.setTestingDriver(DockSwipeDriver(
            isAvailable: { true },
            begin: { calls.append("begin \($0)") },
            update: { calls.append("update \($0)") },
            end: { calls.append("end \($0)") },
            cancel: { calls.append("cancel") },
            settle: { calls.append("settle") }
        ))
        return { calls }
    }

    /// Before Scrollio asks the Dock for a view in one go, nothing of a motion towards a
    /// view may still be on its way: a vertical swipe or a pinch that runs is cancelled
    /// first, then the poster settles what it still had to post again.
    func testSettlingCancelsARunningSwipeAndThenSettlesThePoster() {
        for axis in [DockSwipeAxis.vertical, .pinch] {
            let calls = installSettlingDriver()
            let synthesizer = DockSwipeSynthesizer.shared

            synthesizer.begin(axis: axis)
            synthesizer.update(progress: 0.4)
            let number = synthesizer.swipeNumber
            synthesizer.settle()
            XCTAssertFalse(synthesizer.isActive)
            XCTAssertNil(synthesizer.runningAxis)
            XCTAssertFalse(synthesizer.isRunning(number), "its owner sends nothing more")
            XCTAssertEqual(calls(), ["begin \(axis)", "update 0.4", "cancel", "settle"])

            // Nothing more of that swipe afterwards.
            synthesizer.update(progress: 0.5)
            synthesizer.end(velocity: 1)
            XCTAssertEqual(calls(), ["begin \(axis)", "update 0.4", "cancel", "settle"])
        }
    }

    /// A swipe of the desktops is never taken back by an instant toggle (a hold's sideways
    /// swipe, the thumb wheel's slide or its rest after a turn): it goes on and ends by
    /// itself, and the toggle goes out beside it, as it did before there was a settle.
    func testSettlingLeavesASwipeOfTheDesktopsRunning() {
        let calls = installSettlingDriver()
        let synthesizer = DockSwipeSynthesizer.shared

        synthesizer.begin(axis: .horizontal)
        synthesizer.update(progress: 0.7)
        let number = synthesizer.swipeNumber
        synthesizer.settle()
        XCTAssertTrue(synthesizer.isActive)
        XCTAssertEqual(synthesizer.runningAxis, .horizontal)
        XCTAssertTrue(synthesizer.isRunning(number), "its owner goes on")
        XCTAssertEqual(calls(), ["begin horizontal", "update 0.7", "settle"])

        synthesizer.update(progress: 0.9)
        synthesizer.end(velocity: 1)
        XCTAssertEqual(calls(), ["begin horizontal", "update 0.7", "settle", "update 0.9", "end 1.0"])
    }

    /// With no swipe running only the poster is settled (the terminal event of a swipe that
    /// ended a moment ago may still wait to be posted again); never a second terminal.
    func testSettlingWhileIdleOnlySettlesThePoster() {
        let calls = installSettlingDriver()
        let synthesizer = DockSwipeSynthesizer.shared

        synthesizer.settle()
        XCTAssertEqual(calls(), ["settle"])

        synthesizer.begin(axis: .horizontal)
        synthesizer.end(velocity: 1.5)
        synthesizer.settle()
        synthesizer.settle()
        XCTAssertEqual(calls(), ["settle", "begin horizontal", "end 1.5", "settle", "settle"])
    }

    /// A driver from before `settle` (every test double of the sideways swipe) still builds,
    /// and settling with it does nothing more than cancel.
    func testADriverWithoutSettleStillCancels() {
        let calls = installRecordingDriver()
        DockSwipeSynthesizer.shared.begin(axis: .pinch)
        DockSwipeSynthesizer.shared.settle()
        XCTAssertEqual(calls(), ["begin pinch", "cancel"])
        // The inert driver of the tests: nothing at all.
        DockSwipeSynthesizer.shared.clearTestingDriver()
        DockSwipeSynthesizer.shared.settle()
        XCTAssertFalse(DockSwipeSynthesizer.shared.isActive)
    }

    // MARK: - The terminal event's posts that are still to come

    /// A scheduler that only keeps what it was asked to run; a test runs it.
    private final class Later {
        var scheduled: [(delay: TimeInterval, work: DispatchWorkItem)] = []
        var posted: [String] = []

        /// Runs what was scheduled at `index`, as its timer would; a missing one fails the
        /// test instead of stopping the test host.
        func run(_ index: Int, file: StaticString = #filePath, line: UInt = #line) {
            guard scheduled.indices.contains(index) else {
                XCTFail("nothing was scheduled at \(index)", file: file, line: line)
                return
            }
            scheduled[index].work.perform()
        }

        func makeResends(delays: [TimeInterval] = [0.2, 0.5]) -> DockSwipeTerminalResends<String> {
            return DockSwipeTerminalResends<String>(
                delays: delays,
                schedule: { [unowned self] delay, work in self.scheduled.append((delay, work)) },
                post: { [unowned self] in self.posted.append($0) }
            )
        }
    }

    func testTheTerminalEventIsPostedAgainAfterEachDelay() {
        let later = Later()
        let resends = later.makeResends()
        XCTAssertFalse(resends.isPending)

        resends.begin(with: "ended")
        XCTAssertTrue(resends.isPending)
        XCTAssertEqual(later.scheduled.map(\.delay), [0.2, 0.5])
        XCTAssertEqual(later.posted, [], "the first post is the poster's own")

        later.run(0)
        XCTAssertEqual(later.posted, ["ended"])
        XCTAssertTrue(resends.isPending, "one more to come")
        later.run(1)
        XCTAssertEqual(later.posted, ["ended", "ended"])
        XCTAssertFalse(resends.isPending)
        XCTAssertFalse(resends.postNowAndDrop(), "nothing left to settle")
        XCTAssertEqual(later.posted, ["ended", "ended"])
    }

    /// The settle of an instant toggle: what was still to come is posted once, now, and
    /// nothing of it arrives later, after the toggle.
    func testSettlingPostsTheWaitingTerminalEventOnceNowAndDropsItsTimers() {
        let later = Later()
        let resends = later.makeResends()

        resends.begin(with: "ended")
        XCTAssertTrue(resends.postNowAndDrop())
        XCTAssertEqual(later.posted, ["ended"])
        XCTAssertFalse(resends.isPending)
        later.scheduled.forEach { $0.work.perform() }
        XCTAssertEqual(later.posted, ["ended"], "the timers were dropped")
        XCTAssertFalse(resends.postNowAndDrop())

        // Between the two delays: one more post, not two.
        later.scheduled = []
        later.posted = []
        resends.begin(with: "cancelled")
        later.run(0)
        XCTAssertTrue(resends.postNowAndDrop())
        XCTAssertEqual(later.posted, ["cancelled", "cancelled"])
        later.run(1)
        XCTAssertEqual(later.posted, ["cancelled", "cancelled"])
    }

    /// A new swipe drops what the one before still had to post: it must not end the new one.
    func testANewSwipeDropsTheWaitingTerminalEventWithoutPostingIt() {
        let later = Later()
        let resends = later.makeResends()

        resends.begin(with: "ended")
        resends.drop()
        XCTAssertFalse(resends.isPending)
        later.scheduled.forEach { $0.work.perform() }
        XCTAssertEqual(later.posted, [])
        XCTAssertFalse(resends.postNowAndDrop())

        // The next terminal event replaces one that still waits.
        later.scheduled = []
        resends.begin(with: "first")
        resends.begin(with: "second")
        later.scheduled.forEach { $0.work.perform() }
        XCTAssertEqual(later.posted, ["second", "second"])
    }

    func testWithoutDelaysNothingWaits() {
        let later = Later()
        let resends = later.makeResends(delays: [])
        resends.begin(with: "ended")
        XCTAssertFalse(resends.isPending)
        XCTAssertEqual(later.scheduled.count, 0)
        XCTAssertFalse(resends.postNowAndDrop())
        XCTAssertEqual(later.posted, [])
    }

    // MARK: - The poster's own sequence
    //
    // What `DockSwipeDriver.system` drives, with an "event" that is the frame itself and
    // the scrolling preference it was built with: nothing is built for real and nothing is
    // posted anywhere but into the test's own list.

    private struct Built: Equatable {
        var frame: DockSwipeFrame
        var naturalScrolling: Bool
    }

    /// A poster whose events land in a list and whose timers a test runs.
    private final class PosterWorld {
        var posted: [Built] = []
        var scheduled: [(delay: TimeInterval, work: DispatchWorkItem)] = []
        var naturalScrolling = true
        var preferenceReads = 0
        /// false: the events of a frame cannot be built.
        var canBuild = true

        private(set) lazy var poster = DockSwipePoster<Built>(
            makeEvents: { [unowned self] frame, naturalScrolling in
                self.canBuild ? Built(frame: frame, naturalScrolling: naturalScrolling) : nil
            },
            post: { [unowned self] in self.posted.append($0) },
            isNaturalScrollingEnabled: { [unowned self] in
                self.preferenceReads += 1
                return self.naturalScrolling
            },
            resendDelays: DockSwipeSystemPoster.terminalResendDelays,
            schedule: { [unowned self] delay, work in self.scheduled.append((delay, work)) }
        )

        var frames: [DockSwipeFrame] { posted.map(\.frame) }

        func runEveryTimer() {
            scheduled.forEach { $0.work.perform() }
        }
    }

    private func frame(_ phase: DockSwipePhase, _ axis: DockSwipeAxis, _ progress: Double, velocity: Double = 0) -> DockSwipeFrame {
        return DockSwipeFrame(phase: phase, axis: axis, progress: progress, velocity: velocity)
    }

    /// `begin` posts nothing; the first update is `began` and carries its progress, later
    /// ones are `changed`; the last event repeats the last progress and adds the velocity,
    /// and is posted again after 0.2 s and 0.5 s.
    func testThePostersFirstUpdateIsBeganAndItsLastEventRepeatsTheLastProgress() {
        let world = PosterWorld()
        XCTAssertEqual(DockSwipeSystemPoster.terminalResendDelays, [0.2, 0.5])

        world.poster.begin(axis: .vertical)
        XCTAssertEqual(world.frames, [], "nothing until the hand moves")
        world.poster.update(progress: 0.1)
        XCTAssertEqual(world.frames, [frame(.began, .vertical, 0.1)])
        world.poster.update(progress: 0.7)
        world.poster.update(progress: 0.4)
        world.poster.finish(phase: .ended, velocity: 2.5)
        let last = frame(.ended, .vertical, 0.4, velocity: 2.5)
        XCTAssertEqual(world.frames, [
            frame(.began, .vertical, 0.1), frame(.changed, .vertical, 0.7), frame(.changed, .vertical, 0.4), last,
        ])

        XCTAssertEqual(world.scheduled.map(\.delay), [0.2, 0.5])
        world.runEveryTimer()
        XCTAssertEqual(Array(world.frames.suffix(3)), [last, last, last], "the same event, twice more")
        XCTAssertEqual(world.frames.count, 6)

        // A swipe that is taken back ends the same way, with the other phase.
        world.posted = []
        world.poster.begin(axis: .horizontal)
        world.poster.update(progress: -0.3)
        world.poster.finish(phase: .cancelled, velocity: 0)
        XCTAssertEqual(world.frames, [frame(.began, .horizontal, -0.3), frame(.cancelled, .horizontal, -0.3)])
    }

    /// Nothing reached the Dock, so there is nothing to finish; and one swipe has one
    /// terminal event, however often it is finished.
    func testAFinishBeforeAnyUpdatePostsNothing() {
        let world = PosterWorld()

        world.poster.finish(phase: .ended, velocity: 1)
        world.poster.begin(axis: .pinch)
        world.poster.finish(phase: .cancelled, velocity: 0)
        world.poster.finish(phase: .ended, velocity: 3)
        XCTAssertEqual(world.frames, [])
        XCTAssertEqual(world.scheduled.count, 0, "and nothing to post again")

        world.poster.update(progress: 0.2)
        world.poster.finish(phase: .ended, velocity: 1)
        world.poster.finish(phase: .ended, velocity: 1)
        world.poster.finish(phase: .cancelled, velocity: 0)
        XCTAssertEqual(world.frames, [frame(.began, .pinch, 0.2), frame(.ended, .pinch, 0.2, velocity: 1)])
        XCTAssertEqual(world.scheduled.count, 2)
    }

    /// A second swipe starts clean: the re-posts of the one before are dropped (they would
    /// end the new swipe), its first update is `began` again, and its last event carries
    /// its own progress, not the old one's.
    func testASecondBeginStartsCleanAndDropsTheWaitingReposts() {
        let world = PosterWorld()

        world.poster.begin(axis: .horizontal)
        world.poster.update(progress: 0.6)
        world.poster.finish(phase: .ended, velocity: 1)
        XCTAssertEqual(world.frames.count, 2)

        world.poster.begin(axis: .pinch)
        world.runEveryTimer()
        XCTAssertEqual(world.frames.count, 2, "nothing of the first swipe after the second began")
        world.poster.update(progress: 0.1)
        world.poster.finish(phase: .cancelled, velocity: 0)
        XCTAssertEqual(Array(world.frames.suffix(2)), [frame(.began, .pinch, 0.1), frame(.cancelled, .pinch, 0.1)])

        // A swipe begun over one that never finished: no stale `changed`, no old progress.
        world.posted = []
        world.poster.begin(axis: .vertical)
        world.poster.update(progress: 0.9)
        world.poster.begin(axis: .vertical)
        world.poster.finish(phase: .ended, velocity: 0)
        XCTAssertEqual(world.frames, [frame(.began, .vertical, 0.9)], "the new swipe has nothing to finish yet")
        world.poster.update(progress: 0.05)
        world.poster.finish(phase: .ended, velocity: 0)
        XCTAssertEqual(Array(world.frames.suffix(2)), [frame(.began, .vertical, 0.05), frame(.ended, .vertical, 0.05)])
    }

    /// The settle of an instant toggle, through the poster: the last event that still
    /// waits is posted once, now, and its timers are dropped. With nothing waiting, or a
    /// swipe that still runs, it posts nothing.
    func testSettlingThePosterPostsTheWaitingLastEventOnceNow() {
        let world = PosterWorld()

        world.poster.settle()
        world.poster.begin(axis: .vertical)
        world.poster.update(progress: 0.3)
        world.poster.settle()
        XCTAssertEqual(world.frames.count, 1, "nothing waits while the swipe runs")

        world.poster.finish(phase: .cancelled, velocity: 0)
        world.poster.settle()
        let last = frame(.cancelled, .vertical, 0.3)
        XCTAssertEqual(world.frames, [frame(.began, .vertical, 0.3), last, last])
        world.poster.settle()
        world.runEveryTimer()
        XCTAssertEqual(world.frames.count, 3, "once, and the timers are gone")
    }

    /// The scrolling preference is read once per swipe, at its begin: a change mid-swipe
    /// must not flip the direction under the hand.
    func testThePosterReadsTheScrollingPreferenceOncePerSwipe() {
        let world = PosterWorld()
        world.naturalScrolling = false

        world.poster.begin(axis: .horizontal)
        XCTAssertEqual(world.preferenceReads, 1)
        world.poster.update(progress: 0.1)
        world.naturalScrolling = true
        world.poster.update(progress: 0.2)
        world.poster.finish(phase: .ended, velocity: 1)
        world.runEveryTimer()
        XCTAssertEqual(world.preferenceReads, 1)
        XCTAssertEqual(world.posted.map(\.naturalScrolling), [false, false, false, false, false])

        world.poster.begin(axis: .horizontal)
        world.poster.update(progress: 0.1)
        XCTAssertEqual(world.preferenceReads, 2)
        XCTAssertEqual(world.posted.last?.naturalScrolling, true)
    }

    /// An event that cannot be built is not posted and does not count: the next update is
    /// still `began`, and a last event that cannot be built is not posted again either.
    func testAnEventThatCannotBeBuiltIsNotCounted() {
        let world = PosterWorld()

        world.poster.begin(axis: .vertical)
        world.canBuild = false
        world.poster.update(progress: 0.1)
        world.poster.finish(phase: .ended, velocity: 1)
        XCTAssertEqual(world.frames, [])
        world.canBuild = true
        world.poster.update(progress: 0.2)
        XCTAssertEqual(world.frames, [frame(.began, .vertical, 0.2)])

        world.canBuild = false
        world.poster.finish(phase: .ended, velocity: 1)
        XCTAssertEqual(world.frames.count, 1)
        XCTAssertEqual(world.scheduled.count, 0)
        world.canBuild = true
        world.poster.finish(phase: .ended, velocity: 1)
        XCTAssertEqual(world.frames.count, 1, "that swipe is over for the poster")
    }

    // MARK: - Geometry

    func testProgressPerSpaceFollowsTheSpaceCount() {
        XCTAssertEqual(DockSwipeGeometry.progressPerSpace(spaceCount: nil), 1)
        XCTAssertEqual(DockSwipeGeometry.progressPerSpace(spaceCount: 0), 2)
        XCTAssertEqual(DockSwipeGeometry.progressPerSpace(spaceCount: 1), 2)
        XCTAssertEqual(DockSwipeGeometry.progressPerSpace(spaceCount: 2), 2)
        XCTAssertEqual(DockSwipeGeometry.progressPerSpace(spaceCount: 3), 1.5)
        XCTAssertEqual(DockSwipeGeometry.progressPerSpace(spaceCount: 5), 1.25)
    }

    func testProgressPerPointCrossesOneSpacePerScreenWidth() {
        // One screen width plus the gap between Spaces = one Space.
        let width: CGFloat = 1512
        let perPoint = DockSwipeGeometry.progressPerPoint(screenWidth: width, spaceCount: 3, trackingSpeed: 1)
        XCTAssertEqual(perPoint * Double(width + DockSwipeGeometry.spaceSeparatorWidth), 1.5, accuracy: 1e-12)

        let fast = DockSwipeGeometry.progressPerPoint(screenWidth: width, spaceCount: 3, trackingSpeed: 2)
        XCTAssertEqual(fast, perPoint * 2, accuracy: 1e-15)

        let unknown = DockSwipeGeometry.progressPerPoint(screenWidth: 1000, spaceCount: nil, trackingSpeed: 1)
        XCTAssertEqual(unknown, 1.0 / 1063.0, accuracy: 1e-15)
        XCTAssertTrue(DockSwipeGeometry.progressPerPoint(screenWidth: 0, spaceCount: nil, trackingSpeed: 1).isFinite)
    }

    func testSpaceCountReadsTheMatchingDisplay() {
        let displays: [[String: Any]] = [
            ["Display Identifier": "AAAA", "Spaces": [["id64": 1], ["id64": 2], ["id64": 3]]],
            ["Display Identifier": "BBBB", "Spaces": [["id64": 4]]],
        ]
        XCTAssertEqual(DockSwipeGeometry.spaceCount(inManagedDisplaySpaces: displays, displayIdentifier: "AAAA"), 3)
        XCTAssertEqual(DockSwipeGeometry.spaceCount(inManagedDisplaySpaces: displays, displayIdentifier: "BBBB"), 1)
        XCTAssertNil(DockSwipeGeometry.spaceCount(inManagedDisplaySpaces: displays, displayIdentifier: "CCCC"))
        XCTAssertNil(DockSwipeGeometry.spaceCount(inManagedDisplaySpaces: displays, displayIdentifier: nil))

        // "Displays have separate Spaces" off: one entry for every display.
        let shared: [[String: Any]] = [["Display Identifier": "Main", "Spaces": [["id64": 1], ["id64": 2]]]]
        XCTAssertEqual(DockSwipeGeometry.spaceCount(inManagedDisplaySpaces: shared, displayIdentifier: "AAAA"), 2)
        XCTAssertNil(DockSwipeGeometry.spaceCount(inManagedDisplaySpaces: [], displayIdentifier: "AAAA"))
        XCTAssertNil(DockSwipeGeometry.spaceCount(inManagedDisplaySpaces: [["Display Identifier": "Main"]], displayIdentifier: "Main"))
    }
}

/// Read-only IOKit accessors for the test above, resolved like the production bridge.
private struct HIDEventReader {
    private typealias Copy = @convention(c) (CGEvent) -> UnsafeMutableRawPointer?
    private typealias GetType = @convention(c) (UnsafeMutableRawPointer) -> UInt32
    private typealias GetFlags = @convention(c) (UnsafeMutableRawPointer) -> UInt32
    private typealias GetInteger = @convention(c) (UnsafeMutableRawPointer, UInt32) -> CFIndex
    private typealias GetDouble = @convention(c) (UnsafeMutableRawPointer, UInt32) -> Double
    private typealias GetChildren = @convention(c) (UnsafeMutableRawPointer) -> Unmanaged<CFArray>?

    private let copy: Copy
    private let getType: GetType
    private let getFlags: GetFlags
    private let getInteger: GetInteger
    private let getDouble: GetDouble
    private let getChildren: GetChildren

    init?() {
        func symbol(_ library: DockSwipeHIDBridge.Library, _ names: String...) -> UnsafeMutableRawPointer? {
            for name in names {
                if let address = DockSwipeHIDBridge.systemResolver(library, name) { return address }
            }
            return nil
        }
        guard let copy = symbol(.skyLight, "SLEventCopyIOHIDEvent", "CGEventCopyIOHIDEvent"),
              let getType = symbol(.ioKit, "IOHIDEventGetType"),
              let getFlags = symbol(.ioKit, "IOHIDEventGetEventFlags"),
              let getInteger = symbol(.ioKit, "IOHIDEventGetIntegerValue"),
              let getDouble = symbol(.ioKit, "IOHIDEventGetDoubleValue", "IOHIDEventGetFloatValue"),
              let getChildren = symbol(.ioKit, "IOHIDEventGetChildren") else {
            return nil
        }
        self.copy = unsafeBitCast(copy, to: Copy.self)
        self.getType = unsafeBitCast(getType, to: GetType.self)
        self.getFlags = unsafeBitCast(getFlags, to: GetFlags.self)
        self.getInteger = unsafeBitCast(getInteger, to: GetInteger.self)
        self.getDouble = unsafeBitCast(getDouble, to: GetDouble.self)
        self.getChildren = unsafeBitCast(getChildren, to: GetChildren.self)
    }

    /// +1 reference; balance with `release`.
    func copyHIDEvent(_ event: CGEvent) -> UnsafeMutableRawPointer? { copy(event) }
    func release(_ event: UnsafeMutableRawPointer) { Unmanaged<AnyObject>.fromOpaque(event).release() }
    func type(_ event: UnsafeMutableRawPointer) -> UInt32 { getType(event) }
    func flags(_ event: UnsafeMutableRawPointer) -> UInt32 { getFlags(event) }
    func integer(_ event: UnsafeMutableRawPointer, _ field: UInt32) -> Int { getInteger(event, field) }
    func double(_ event: UnsafeMutableRawPointer, _ field: UInt32) -> Double { getDouble(event, field) }

    /// Children are owned by the parent; valid while it is alive.
    func children(_ event: UnsafeMutableRawPointer) -> [UnsafeMutableRawPointer] {
        guard let array = getChildren(event)?.takeUnretainedValue() as? [AnyObject] else { return [] }
        return array.map { Unmanaged.passUnretained($0).toOpaque() }
    }
}
