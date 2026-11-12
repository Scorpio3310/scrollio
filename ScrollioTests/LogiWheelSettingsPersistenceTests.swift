import XCTest
@testable import Scrollio_Debug

/// Canary for the persisted wheel settings (UserDefaults key "logiWheelSettings"). Since the
/// wheel values became optional (nil = not set by the user, the mouse keeps its own), an unset
/// value has no key. Settings stored before that carry every value and load as set by the user.
/// The key names and JSON below are frozen: never derive them from production code.
final class LogiWheelSettingsPersistenceTests: XCTestCase {

    private func decode(_ json: String) -> LogiWheelSettings {
        return Options.decodeLogiWheelSettings(Data(json.utf8))
    }

    private func encodedObject(_ settings: LogiWheelSettings) throws -> [String: Any] {
        let data = try JSONEncoder().encode(settings)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testKeyIsFrozen() {
        XCTAssertEqual(OptionItem.MouseWheel.Settings, "logiWheelSettings")
    }

    /// The old format, from before the values were optional: every value present, all set by
    /// the user.
    func testOldFormatLoadsAsSetByTheUser_andRoundTrips() throws {
        let old = #"{"mode":"smartShift","smartShiftSensitivity":51,"scrollForce":100,"managedByScrollio":true}"#
        let settings = decode(old)
        XCTAssertEqual(settings, LogiWheelSettings(managedByScrollio: true, mode: .smartShift, smartShiftSensitivity: 51, scrollForce: 100))

        // Out in the new format: the same keys and values, nothing lost.
        let object = try encodedObject(settings)
        XCTAssertEqual(Set(object.keys), ["managedByScrollio", "mode", "smartShiftSensitivity", "scrollForce"])
        XCTAssertEqual(object["managedByScrollio"] as? Bool, true)
        XCTAssertEqual(object["mode"] as? String, "smartShift")
        XCTAssertEqual(object["smartShiftSensitivity"] as? Int, 51)
        XCTAssertEqual(object["scrollForce"] as? Int, 100)

        // And back.
        XCTAssertEqual(Options.decodeLogiWheelSettings(try JSONEncoder().encode(settings)), settings)
    }

    /// Every old-format record loads as set, whatever the switch: the user may have set the
    /// values before turning it off.
    func testOldFormatWithTheSwitchOffLoadsAsSetToo() {
        XCTAssertEqual(decode(#"{"managedByScrollio":false,"mode":"ratchet","smartShiftSensitivity":50,"scrollForce":50}"#),
                       LogiWheelSettings(managedByScrollio: false, mode: .ratchet, smartShiftSensitivity: 50, scrollForce: 50))
    }

    func testFreshInstallSetsNothing() throws {
        XCTAssertEqual(Options.decodeLogiWheelSettings(nil), .default)
        XCTAssertEqual(LogiWheelSettings.default, LogiWheelSettings(managedByScrollio: false, mode: nil, smartShiftSensitivity: nil, scrollForce: nil))
        let data = try JSONEncoder().encode(LogiWheelSettings.default)
        XCTAssertEqual(String(data: data, encoding: .utf8), #"{"managedByScrollio":false}"#, "unset values are not stored")
    }

    func testNewFormatKeepsUnsetValuesUnset() throws {
        let switchedOn = LogiWheelSettings(managedByScrollio: true)
        XCTAssertEqual(String(data: try JSONEncoder().encode(switchedOn), encoding: .utf8), #"{"managedByScrollio":true}"#)
        XCTAssertEqual(decode(#"{"managedByScrollio":true}"#), switchedOn)

        let oneValue = LogiWheelSettings(managedByScrollio: true, scrollForce: 70)
        XCTAssertEqual(Set(try encodedObject(oneValue).keys), ["managedByScrollio", "scrollForce"])
        XCTAssertEqual(Options.decodeLogiWheelSettings(try JSONEncoder().encode(oneValue)), oneValue)
    }

    func testGarbageMeansNothingSet() {
        XCTAssertEqual(decode("not json"), .default)
        XCTAssertEqual(decode("[1, 2, 3]"), .default)
        XCTAssertEqual(decode(""), .default)
        XCTAssertEqual(decode("{}"), .default)
    }

    func testAWronglyTypedValueKeepsTheOthers() {
        XCTAssertEqual(decode(#"{"managedByScrollio":true,"mode":"turbo","smartShiftSensitivity":"high","scrollForce":40,"future":1}"#),
                       LogiWheelSettings(managedByScrollio: true, scrollForce: 40))
        XCTAssertEqual(decode(#"{"managedByScrollio":"yes","mode":"freeSpin"}"#), LogiWheelSettings(mode: .freeSpin),
                       "an unreadable switch is off")
        XCTAssertEqual(decode(#"{"managedByScrollio":true,"mode":null}"#), LogiWheelSettings(managedByScrollio: true))
    }

    func testOutOfRangeValuesAreClamped() {
        let settings = decode(#"{"smartShiftSensitivity":0,"scrollForce":500}"#)
        XCTAssertEqual(settings.smartShiftSensitivity, 1)
        XCTAssertEqual(settings.scrollForce, 100)
    }

    /// The raw values of the modes are stored: a rename would silently drop what users set.
    func testModeNamesAreFrozen() {
        XCTAssertEqual(LogiWheelMode.allCases.map(\.rawValue), ["smartShift", "ratchet", "freeSpin"])
    }
}
