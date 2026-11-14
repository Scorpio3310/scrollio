//
//  ThumbWheelFollowTests.swift
//  ScrollioTests
//
//  The thumb wheel's options: each action's own "Reverse direction" and Switch Desktops'
//  "Follow the wheel", stored, carried by a settings file and run through the scroll tap.
//  The dock swipe is a fake: nothing reaches the Dock.
//

import XCTest
@testable import Scrollio_Debug

private typealias FrontApp = ShortcutRingChoice.FrontApp

// MARK: - Stored

final class ThumbWheelOptionsStoredTests: XCTestCase {

    private func decode(_ json: String) throws -> ThumbWheelSettings {
        return try JSONDecoder().decode(ThumbWheelSettings.self, from: Data(json.utf8))
    }

    private func encode(_ settings: ThumbWheelSettings) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(settings), as: UTF8.self)
    }

    /// An entry (or a file) from before, with its one "Swap direction", gives every action
    /// that value; Follow the wheel is off.
    func testTheOldSwapSeedsEveryActionAndFollowIsOff() throws {
        let old = try decode(#"{"function":"volume","speed":2.5,"swapsDirection":true}"#)
        for function in ThumbWheelFunction.allCases {
            XCTAssertTrue(old.reverses[function], "\(function)")
        }
        XCTAssertFalse(old.followsWheel)
        XCTAssertFalse(try decode(#"{"function":"desktops"}"#).followsWheel, "off by default")
        XCTAssertFalse(ThumbWheelSettings.default.followsWheel)
        XCTAssertEqual(ThumbWheelSettings.default.reverses, .none)
        let notSwapped = try decode(#"{"function":"tabs","swapsDirection":false}"#)
        XCTAssertEqual(notSwapped.reverses, .none)
    }

    /// Settings whose actions all have the same switch, without Follow the wheel, are
    /// written exactly as before; one action set apart writes every action's switch by
    /// name, with "swapsDirection" the chosen action's (what 1.0.5
    /// reads); Follow the wheel only while on. Read back, every value is as it was.
    func testTheStoredFormSaysMoreOnlyWhenItHasMoreToSay() throws {
        XCTAssertEqual(try encode(ThumbWheelSettings(function: .zoom, speed: 1.5, swapsDirection: true)),
                       #"{"function":"zoom","speed":1.5,"swapsDirection":true}"#)
        var settings = ThumbWheelSettings(function: .volume, speed: 2)
        settings.reverses[.volume] = true
        settings.reverses[.desktops] = true
        settings.followsWheel = true
        let plain = try encode(settings)
        XCTAssertEqual(plain, #"{"followsWheel":true,"function":"volume","#
            + #""reverseDirection":{"backForward":false,"desktops":true,"scroll":false,"tabs":false,"volume":true,"zoom":false},"#
            + #""speed":2,"swapsDirection":true}"#)
        XCTAssertEqual(try decode(plain), settings)

        // The chosen action not reversed while another is: 1.0.5 turns it unreversed.
        settings.function = .zoom
        XCTAssertTrue(try encode(settings).contains(#""swapsDirection":false"#))
        XCTAssertEqual(try decode(try encode(settings)), settings)
    }

    /// An action missing in "reverseDirection" takes the old switch; a map that cannot be
    /// read is none (the old switch for all); the stored names are the functions' own.
    func testAMissingOrUnreadableActionTakesTheOldSwitch() throws {
        let partial = try decode(#"{"function":"tabs","swapsDirection":true,"reverseDirection":{"zoom":false}}"#)
        XCTAssertFalse(partial.reverses[.zoom])
        XCTAssertTrue(partial.reverses[.tabs])
        XCTAssertTrue(partial.reverses[.volume])
        let broken = try decode(#"{"function":"tabs","swapsDirection":true,"reverseDirection":{"zoom":"no"},"followsWheel":"yes"}"#)
        XCTAssertEqual(broken.reverses, .all)
        XCTAssertFalse(broken.followsWheel)
        XCTAssertEqual(OptionItem.ThumbWheel.Settings, "thumbWheelSettings", "never renamed")
    }

    /// An app's own values: from before (one swap) every action takes it; a map and the
    /// follow switch are stored only when there; nothing of the app's: the general ones.
    func testAnAppsOwnValuesAreStoredAndSeededTheSameWay() throws {
        func scrolling(_ json: String) throws -> ApplicationThumbWheelScrolling {
            return try JSONDecoder().decode(ApplicationThumbWheelScrolling.self, from: Data(json.utf8))
        }
        XCTAssertEqual(try scrolling(#"{"speed":1.5,"swapsDirection":true}"#),
                       ApplicationThumbWheelScrolling(speed: 1.5, reverses: .all, followsWheel: nil))
        XCTAssertEqual(try scrolling(#"{"speed":1.5}"#), ApplicationThumbWheelScrolling(speed: 1.5, reverses: nil, followsWheel: nil))

        var reverses = ThumbWheelReversal.none
        reverses[.zoom] = true
        let own = ApplicationThumbWheelScrolling(speed: 1, reverses: reverses, followsWheel: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(own)
        XCTAssertEqual(String(decoding: data, as: UTF8.self),
                       #"{"followsWheel":true,"reverseDirection":{"backForward":false,"desktops":false,"scroll":false,"tabs":false,"volume":false,"zoom":true},"speed":1}"#)
        XCTAssertEqual(try JSONDecoder().decode(ApplicationThumbWheelScrolling.self, from: data), own)

        // What runs in the app: its own where it has them, else the general ones.
        let general = ThumbWheelSettings(function: .desktops, speed: 2, swapsDirection: true)
        let mine = ThumbWheelOwn(reverses: reverses, followsWheel: true).settings(general: general)
        XCTAssertFalse(mine.reverses[.desktops])
        XCTAssertTrue(mine.followsWheelNow)
        XCTAssertEqual(mine.speed, 2)
        XCTAssertEqual(ThumbWheelOwn(speed: 1).settings(general: general).reverses, .all, "nothing of its own: the general")
    }

    /// A settings file carries every action's switch and the follow switch, general and an
    /// app's own, and an import puts them back as they were.
    func testTheSettingsFileCarriesThem() throws {
        let source = Options()
        source.defaults = TestDefaults.make(for: self)
        var general = ThumbWheelSettings(function: .desktops, speed: 1.25, followsWheel: true)
        general.reverses[.volume] = true
        source.thumbWheel = general
        let figma = Application(path: "/Applications/Figma.app")
        figma.inherit = false
        var own = ThumbWheelSettings(function: .zoom, swapsDirection: true)
        own.reverses[.tabs] = false
        own.followsWheel = false
        figma.setOwnThumbWheelScrolling(own)
        source.application.applications.append(figma)

        let data = try SettingsFile.export(from: source, now: Date(timeIntervalSince1970: 1_794_476_527)).get()
        let contents = try SettingsFile.read(data).get()
        XCTAssertEqual(contents.thumbWheel, general)
        XCTAssertEqual(contents.leftOutCount, 0)

        let target = Options()
        target.defaults = TestDefaults.make(for: self)
        target.readOptions()
        XCTAssertTrue(SettingsFile.apply(contents, to: target))
        XCTAssertEqual(target.thumbWheel, general)
        let imported = try XCTUnwrap(target.application.applications.get(by: figma.path))
        XCTAssertEqual(imported.scroll.thumbWheel, ApplicationThumbWheelScrolling(own))
        XCTAssertFalse(imported.thumbWheelThatRuns(general: general).followsWheel, "the app's own: off")
        XCTAssertFalse(imported.thumbWheelThatRuns(general: general).reverses[.tabs])
        XCTAssertTrue(imported.thumbWheelThatRuns(general: general).reverses[.volume])
    }
}
