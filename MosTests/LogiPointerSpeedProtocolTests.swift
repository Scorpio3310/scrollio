import XCTest
@testable import Mos_Debug

/// Adjustable DPI (0x2201) byte layouts on fake bytes.
final class LogiPointerSpeedProtocolTests: XCTestCase {

    /// [0x11, 0xFF, 0x14, fn<<4|1, sensor, u16...] padded to 20 bytes.
    private func listReport(_ words: [UInt16], sensor: UInt8 = 0) -> [UInt8] {
        var bytes: [UInt8] = [0x11, 0xFF, 0x14, 0x11, sensor]
        for word in words { bytes += [UInt8(word >> 8), UInt8(word & 0xFF)] }
        while bytes.count < 20 { bytes.append(0) }
        return Array(bytes.prefix(20))
    }

    private func currentReport(_ current: UInt16, _ defaultDPI: UInt16, sensor: UInt8 = 0) -> [UInt8] {
        var bytes: [UInt8] = [0x11, 0xFF, 0x14, 0x21, sensor,
                              UInt8(current >> 8), UInt8(current & 0xFF),
                              UInt8(defaultDPI >> 8), UInt8(defaultDPI & 0xFF)]
        while bytes.count < 20 { bytes.append(0) }
        return bytes
    }

    func testFunctionTable() {
        XCTAssertEqual(LogiPointerSpeedProtocol.listFunction, 1)
        XCTAssertEqual(LogiPointerSpeedProtocol.getFunction, 2)
        XCTAssertEqual(LogiPointerSpeedProtocol.setFunction, 3)
        XCTAssertEqual(LogiPointerSpeedProtocol.listParams(), [0, 0, 0])
        XCTAssertEqual(LogiPointerSpeedProtocol.getParams(), [0, 0, 0])
    }

    // MARK: - List

    func testRangeWithStep() {
        // 00C8 E032 1F40 0000: 200...8000 in steps of 50
        let list = LogiPointerSpeedProtocol.parseDPIList(listReport([0x00C8, 0xE032, 0x1F40, 0x0000]))
        XCTAssertEqual(list?.values.first, 200)
        XCTAssertEqual(list?.values.last, 8000)
        XCTAssertEqual(list?.values.count, 157)
        XCTAssertEqual(list?.values[1], 250)
        XCTAssertEqual(list?.terminated, true)
    }

    func testRangeWhoseHighEndIsOffTheStepKeepsTheHighEnd() {
        let list = LogiPointerSpeedProtocol.parseDPIList(listReport([200, 0xE064, 450, 0]))
        XCTAssertEqual(list?.values, [200, 300, 400, 450])
    }

    func testExplicitList() {
        let list = LogiPointerSpeedProtocol.parseDPIList(listReport([400, 800, 1600, 3200, 0]))
        XCTAssertEqual(list?.values, [400, 800, 1600, 3200])
    }

    func testMixedListAndRange() {
        let list = LogiPointerSpeedProtocol.parseDPIList(listReport([400, 800, 0xE0C8, 1400, 4000, 0]))
        XCTAssertEqual(list?.values, [400, 800, 1000, 1200, 1400, 4000])
    }

    func testFullAnswerWithoutTerminator() {
        let list = LogiPointerSpeedProtocol.parseDPIList(listReport([100, 200, 300, 400, 500, 600, 700]))
        XCTAssertEqual(list?.values, [100, 200, 300, 400, 500, 600, 700])
        XCTAssertEqual(list?.terminated, false)
    }

    func testMalformedListsAreNil() {
        XCTAssertNil(LogiPointerSpeedProtocol.parseDPIList(listReport([0xE032, 0x1F40, 0])), "leading marker")
        XCTAssertNil(LogiPointerSpeedProtocol.parseDPIList(listReport([200, 0xE032, 0])), "marker without a high end")
        XCTAssertNil(LogiPointerSpeedProtocol.parseDPIList(listReport([200, 0xE000, 400, 0])), "step 0")
        XCTAssertNil(LogiPointerSpeedProtocol.parseDPIList(listReport([800, 0xE032, 400, 0])), "range going down")
        XCTAssertNil(LogiPointerSpeedProtocol.parseDPIList(listReport([200, 0xE032, 0xE032, 400, 0])), "two markers")
        XCTAssertNil(LogiPointerSpeedProtocol.parseDPIList(listReport([0])), "empty list")
        XCTAssertNil(LogiPointerSpeedProtocol.parseDPIList(listReport([400, 0], sensor: 1)), "another sensor")
        XCTAssertNil(LogiPointerSpeedProtocol.parseDPIList([0x11, 0xFF, 0x14, 0x11, 0x00, 0x01]), "short")
    }

    func testHugeRangeIsRefused() {
        XCTAssertNil(LogiPointerSpeedProtocol.parseDPIList(listReport([1, 0xE001, 0xDFFF, 0])))
    }

    // MARK: - Current

    func testCurrentAndDefault() {
        let parsed = LogiPointerSpeedProtocol.parseCurrent(currentReport(1600, 1000))
        XCTAssertEqual(parsed?.current, 1600)
        XCTAssertEqual(parsed?.defaultDPI, 1000)
    }

    func testCurrentZeroUsesTheDefault() {
        let parsed = LogiPointerSpeedProtocol.parseCurrent(currentReport(0, 1000))
        XCTAssertEqual(parsed?.current, 1000)
        XCTAssertEqual(parsed?.defaultDPI, 1000)
    }

    func testNoDefaultIsNil() {
        let parsed = LogiPointerSpeedProtocol.parseCurrent(currentReport(800, 0))
        XCTAssertEqual(parsed?.current, 800)
        XCTAssertNil(parsed?.defaultDPI)
        XCTAssertNil(LogiPointerSpeedProtocol.parseCurrent(currentReport(0, 0)), "nothing known")
    }

    func testCurrentShortOrOtherSensorIsNil() {
        XCTAssertNil(LogiPointerSpeedProtocol.parseCurrent([0x11, 0xFF, 0x14, 0x21, 0x00, 0x03]))
        XCTAssertNil(LogiPointerSpeedProtocol.parseCurrent(currentReport(800, 0, sensor: 2)))
    }

    // MARK: - Set and snap

    func testSetParams() {
        XCTAssertEqual(LogiPointerSpeedProtocol.setParams(dpi: 1000), [0x00, 0x03, 0xE8])
        XCTAssertNil(LogiPointerSpeedProtocol.setParams(dpi: 0), "DPI 0 is never written")
        XCTAssertNil(LogiPointerSpeedProtocol.setParams(dpi: 0xE000), "would read as a range marker")
    }

    func testSnapToNearestMember() {
        let choices = [400, 800, 1600, 3200]
        XCTAssertEqual(LogiPointerSpeedProtocol.snap(1000, to: choices), 800)
        XCTAssertEqual(LogiPointerSpeedProtocol.snap(1300, to: choices), 1600)
        XCTAssertEqual(LogiPointerSpeedProtocol.snap(1200, to: choices), 800, "a tie goes to the lower value")
        XCTAssertEqual(LogiPointerSpeedProtocol.snap(99999, to: choices), 3200)
        XCTAssertEqual(LogiPointerSpeedProtocol.snap(1, to: choices), 400)
        XCTAssertNil(LogiPointerSpeedProtocol.snap(1000, to: []))
    }
}
