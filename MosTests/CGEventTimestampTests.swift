//
//  CGEventTimestampTests.swift
//  MosTests
//
//  The time column of the Monitor window: an event's clock time, not the time since the
//  Mac started read as a 1970 date.
//

import XCTest
@testable import Mos_Debug

final class CGEventTimestampTests: XCTestCase {

    func testTheDateIsTheMomentOfTheEventBeforeNow() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        // The Mac has been up 1000 s; the event came at 997.5 s.
        let date = CGEvent.date(ofTimestamp: 997_500_000_000, now: now, uptime: 1000)
        XCTAssertEqual(date.timeIntervalSince(now), -2.5, accuracy: 1e-6)
    }

    func testAnEventOfNowShowsTheTimeOfDay() throws {
        let event = try XCTUnwrap(CGEvent(source: nil))
        event.timestamp = CGEventTimestamp(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
        let text = event.timestampFormatted

        // Read back on the same clock: within a second of now (midnight wraps around).
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
