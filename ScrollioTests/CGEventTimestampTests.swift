//
//  CGEventTimestampTests.swift
//  MosTests
//
//  The time column of the Monitor window: an event's clock time, not the time since the
//  Mac started read as a 1970 date, and read in seconds by AppKit, whatever the unit of the
//  raw timestamp is on this Mac.
//

import XCTest
@testable import Scrollio_Debug

final class CGEventTimestampTests: XCTestCase {

    func testTheDateIsTheMomentOfTheEventBeforeNow() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        // The Mac has been up 1000 s; the event came at 997.5 s.
        let date = CGEvent.date(ofUptime: 997.5, now: now, uptime: 1000)
        XCTAssertEqual(date.timeIntervalSince(now), -2.5, accuracy: 1e-6)
    }

    /// Seconds since the Mac started become the time of day, with fixed numbers: 2.5 s
    /// before a time whose seconds are :00.000 (any time zone moves whole minutes).
    func testAnUptimeBecomesTheTimeOfDay() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let text = CGEvent.timeOfDay(ofUptime: 997.5, now: now, uptime: 1000)
        XCTAssertEqual(text, CGEvent.timestampFormatter.string(from: now.addingTimeInterval(-2.5)))
        XCTAssertTrue(text.hasSuffix(":57.500"), text)
        XCTAssertEqual(text.count, "HH:mm:ss.SSS".count, text)
    }

    /// The event's uptime is what AppKit reads from it, in seconds, whatever unit the raw
    /// timestamp has on this Mac.
    func testTheEventsUptimeIsAppKitsSeconds() throws {
        let made = try XCTUnwrap(NSEvent.mouseEvent(
            with: .otherMouseDown, location: .zero, modifierFlags: [], timestamp: 1234.25,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        let event = try XCTUnwrap(made.cgEvent)
        XCTAssertEqual(event.uptimeSeconds, 1234.25, accuracy: 1e-3)
    }

    /// An event of now shows the time of day (within a second; midnight wraps around).
    func testAnEventOfNowShowsTheTimeOfDay() throws {
        let made = try XCTUnwrap(NSEvent.mouseEvent(
            with: .otherMouseDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        let text = try XCTUnwrap(made.cgEvent).timestampFormatted
        let shown = try XCTUnwrap(CGEvent.timestampFormatter.date(from: text), text)
        let calendar = Calendar.current
        let secondsOfDay: (Date) -> Double = { date in
            let parts = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
            return Double(parts.hour! * 3600 + parts.minute! * 60 + parts.second!) + Double(parts.nanosecond!) / 1e9
        }
        let difference = abs(secondsOfDay(shown) - secondsOfDay(Date()))
        XCTAssertLessThan(min(difference, 86_400 - difference), 1, "\(text) is the time of day")
    }

    func testEveryLineSharesOneFormatter() {
        XCTAssertTrue(CGEvent.timestampFormatter === CGEvent.timestampFormatter)
        XCTAssertEqual(CGEvent.timestampFormatter.dateFormat, "HH:mm:ss.SSS")
    }
}
