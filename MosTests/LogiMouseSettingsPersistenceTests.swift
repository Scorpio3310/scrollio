import XCTest
@testable import Mos_Debug

/// Canary for the persisted basic mouse settings (UserDefaults key "logiMouseSettings") and
/// the switch they share with the wheel (`logiWheelSettings.managedByMos`). The key names
/// below are frozen: never derive them from production code.
final class LogiMouseSettingsPersistenceTests: XCTestCase {

    private func decode(_ json: String) -> LogiMouseSettings {
        return Options.decodeLogiMouseSettings(Data(json.utf8))
    }

    func testKeyIsFrozen() {
        XCTAssertEqual(OptionItem.MouseBasics.Settings, "logiMouseSettings")
        XCTAssertEqual(OptionItem.MouseWheel.Settings, "logiWheelSettings", "the switch stays where it was")
    }

    func testMissingKeyMeansNothingSet() {
        XCTAssertEqual(Options.decodeLogiMouseSettings(nil), .default)
        XCTAssertEqual(LogiMouseSettings.default, LogiMouseSettings(pointerDPI: nil, hapticsOn: nil, hapticStrength: nil, pressForce: nil))
    }

    func testGarbageMeansNothingSet() {
        XCTAssertEqual(decode("not json"), .default)
        XCTAssertEqual(decode("[1, 2, 3]"), .default)
        XCTAssertEqual(decode(""), .default)
    }

    func testEmptyObjectMeansNothingSet() {
        XCTAssertEqual(decode("{}"), .default)
    }

    func testUnknownFieldsAreIgnored() {
        XCTAssertEqual(decode(#"{"pointerDPI": 1600, "thumbWheelReversed": true, "future": {"a": 1}}"#),
                       LogiMouseSettings(pointerDPI: 1600))
    }

    func testAWronglyTypedFieldKeepsTheOthers() {
        XCTAssertEqual(decode(#"{"pointerDPI": "fast", "hapticsOn": false, "hapticStrength": 40}"#),
                       LogiMouseSettings(hapticsOn: false, hapticStrength: 40))
        XCTAssertEqual(decode(#"{"pointerDPI": null, "pressForce": 6000}"#), LogiMouseSettings(pressForce: 6000))
    }

    func testOutOfRangeValuesAreClamped() {
        let settings = decode(#"{"pointerDPI": 0, "hapticStrength": 500, "pressForce": -5}"#)
        XCTAssertEqual(settings.pointerDPI, 1)
        XCTAssertEqual(settings.hapticStrength, 100)
        XCTAssertEqual(settings.pressForce, 0)
        XCTAssertEqual(decode(#"{"hapticStrength": 0}"#).hapticStrength, 1)
        XCTAssertEqual(decode(#"{"pointerDPI": 99999}"#).pointerDPI, 0xDFFF)
        XCTAssertEqual(decode(#"{"pressForce": 70000}"#).pressForce, 0xFFFF)
    }

    func testRoundTrip() throws {
        let values = [
            LogiMouseSettings.default,
            LogiMouseSettings(pointerDPI: 1600),
            LogiMouseSettings(pointerDPI: 800, hapticsOn: false, hapticStrength: 25, pressForce: 5089),
        ]
        for value in values {
            let data = try JSONEncoder().encode(value)
            XCTAssertEqual(Options.decodeLogiMouseSettings(data), value)
        }
    }

    /// Frozen JSON keys: a rename would silently drop what users set.
    func testEncodedKeysAreFrozen() throws {
        let data = try JSONEncoder().encode(LogiMouseSettings(pointerDPI: 1, hapticsOn: true, hapticStrength: 2, pressForce: 3))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["pointerDPI", "hapticsOn", "hapticStrength", "pressForce"])
        let empty = try JSONEncoder().encode(LogiMouseSettings.default)
        XCTAssertEqual(String(data: empty, encoding: .utf8), "{}", "unset values are not stored")
    }

    func testTheSwitchKeepsItsJSONKey() throws {
        let data = try JSONEncoder().encode(LogiWheelSettings.default)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["managedByMos"] as? Bool, false)
    }

    func testTheMouseSwitchIsTheWheelSwitch() {
        let saved = Options.shared.logiWheel
        defer { Options.shared.logiWheel = saved }
        Options.shared.logiMouseManaged = true
        XCTAssertTrue(Options.shared.logiWheel.managedByMos)
        Options.shared.logiWheel.managedByMos = false
        XCTAssertFalse(Options.shared.logiMouseManaged)
    }

    func testTheNewGroupIsObservable() {
        let options = Options()
        var received: [OptionsGroup] = []
        options.observe([.logiMouse]) { received.append($0) }
        options.logiMouse = LogiMouseSettings(pointerDPI: 1600)
        options.logiWheel = .default
        XCTAssertEqual(received, [.logiMouse])
    }
}
