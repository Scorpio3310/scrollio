//
//  ScrollTuningTests.swift
//  MosTests
//
//  The stored fast-scroll tuning (ScrollTuningSettings, ScrollMomentumSettings): plain data
//  that the preferences still read and write. The scroll engine does not use it any more;
//  these tests keep the stored format readable until the settings are removed.
//

import XCTest
@testable import Mos_Debug

final class ScrollTuningTests: XCTestCase {

    func testSettings_encodesExactlyTheFourContractFields() throws {
        let data = try JSONEncoder().encode(ScrollTuningSettings.default)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["freeSpinEnabled", "freeSpinSmoothness", "freeSpinSpeed", "acceleration"])
    }

    func testSettings_decodingIsTolerant() throws {
        let partial = try JSONDecoder().decode(ScrollTuningSettings.self, from: Data(#"{"freeSpinSpeed": 9, "acceleration": -1, "future": 1}"#.utf8))
        XCTAssertEqual(partial.freeSpinEnabled, ScrollTuningSettings.default.freeSpinEnabled)
        XCTAssertEqual(partial.freeSpinSmoothness, ScrollTuningSettings.default.freeSpinSmoothness)
        XCTAssertEqual(partial.freeSpinSpeed, 3)
        XCTAssertEqual(partial.acceleration, 0)
    }

    func testDefaults_areOff() {
        XCTAssertNil(ScrollTuningSettings.default.momentum)
        XCTAssertEqual(ScrollTuningSettings.default.horizontalWheelAction, .scroll)
        let four = ScrollTuningSettings(freeSpinEnabled: true, freeSpinSmoothness: 1, freeSpinSpeed: 1, acceleration: 0)
        XCTAssertNil(four.momentum)
        XCTAssertEqual(four.horizontalWheelAction, .scroll)
    }

    func testMomentumDefaults() {
        let m = ScrollMomentumSettings.default
        XCTAssertEqual(m.decayPer8ms, 0.975)
        XCTAssertEqual(m.tailSpeed, 250)
        XCTAssertEqual(m.tailDecayPer8ms, 0.91)
        XCTAssertEqual(m.stopDelta, 0.5)
        XCTAssertEqual(m.coastGain, 1.0)
        XCTAssertEqual(m.minFlingRate, 8)
        XCTAssertEqual(m.fullFlingRate, 16)
        XCTAssertTrue(m.stopOnReverseTick)
        XCTAssertTrue(m.noCoastWithModifiers)
        XCTAssertFalse(m.coastInFreeSpin)
        XCTAssertFalse(m.phasesInFreeSpin)
        XCTAssertFalse(m.phasesOnHorizontal)
    }

    func testDecoding_settingsFromBeforeMomentum() throws {
        let old = #"{"freeSpinEnabled":false,"freeSpinSmoothness":2.5,"freeSpinSpeed":0.7,"acceleration":0.3}"#
        let settings = try JSONDecoder().decode(ScrollTuningSettings.self, from: Data(old.utf8))
        XCTAssertNil(settings.momentum)
        XCTAssertEqual(settings.horizontalWheelAction, .scroll)
        XCTAssertFalse(settings.freeSpinEnabled)
        XCTAssertEqual(settings.freeSpinSmoothness, 2.5)
        XCTAssertEqual(settings.freeSpinSpeed, 0.7)
        XCTAssertEqual(settings.acceleration, 0.3)
        // And they are written back unchanged: no new keys while both stay off.
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["freeSpinEnabled", "freeSpinSmoothness", "freeSpinSpeed", "acceleration"])
    }

    func testEncoding_roundTripsMomentumAndWheelAction() throws {
        var momentum = ScrollMomentumSettings.default
        momentum.coastGain = 1.5
        momentum.phasesOnHorizontal = true
        let settings = ScrollTuningSettings(
            freeSpinEnabled: false, freeSpinSmoothness: 2, freeSpinSpeed: 1, acceleration: 0,
            momentum: momentum, horizontalWheelAction: .pageSwipe
        )
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(ScrollTuningSettings.self, from: data), settings)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["horizontalWheelAction"] as? String, "pageSwipe")
        XCTAssertNotNil(object["momentum"] as? [String: Any])
    }

    func testDecoding_partialMomentumFallsBackToDefaultsAndClamps() throws {
        let json = #"{"momentum":{"coastGain":99,"decayPer8ms":2,"minFlingRate":20,"fullFlingRate":10,"stopOnReverseTick":false,"future":1}}"#
        let settings = try JSONDecoder().decode(ScrollTuningSettings.self, from: Data(json.utf8))
        let momentum = try XCTUnwrap(settings.momentum)
        XCTAssertEqual(momentum.coastGain, ScrollMomentumSettings.coastGainRange.upperBound)
        XCTAssertEqual(momentum.decayPer8ms, ScrollMomentumSettings.decayRange.upperBound)
        XCTAssertEqual(momentum.minFlingRate, 20)
        XCTAssertEqual(momentum.fullFlingRate, 20, "never below the minimum")
        XCTAssertFalse(momentum.stopOnReverseTick)
        XCTAssertEqual(momentum.tailSpeed, 250)
        XCTAssertEqual(momentum.tailDecayPer8ms, 0.91)
        XCTAssertEqual(momentum.stopDelta, 0.5)
        XCTAssertTrue(momentum.noCoastWithModifiers)
        XCTAssertEqual(settings.freeSpinEnabled, ScrollTuningSettings.default.freeSpinEnabled)

        let empty = try JSONDecoder().decode(ScrollTuningSettings.self, from: Data(#"{"momentum":{}}"#.utf8))
        XCTAssertEqual(empty.momentum, .default, "an empty block is momentum with default values")
    }

    func testDecoding_unreadableValuesTurnTheFeatureOffInsteadOfFailing() throws {
        let json = #"{"acceleration":0.5,"momentum":"yes","horizontalWheelAction":"teleport"}"#
        let settings = try JSONDecoder().decode(ScrollTuningSettings.self, from: Data(json.utf8))
        XCTAssertNil(settings.momentum)
        XCTAssertEqual(settings.horizontalWheelAction, .scroll)
        XCTAssertEqual(settings.acceleration, 0.5, "the rest is still read")

        let nulls = try JSONDecoder().decode(ScrollTuningSettings.self, from: Data(#"{"momentum":null,"horizontalWheelAction":7}"#.utf8))
        XCTAssertNil(nulls.momentum)
        XCTAssertEqual(nulls.horizontalWheelAction, .scroll)
    }
}
