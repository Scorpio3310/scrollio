import AppKit
import XCTest
@testable import Scrollio_Debug

/// Small helpers in Utils that used to fail on edge cases, and the app's accent colour and
/// status item image.
final class UtilsTests: XCTestCase {

    // MARK: - Single instance

    /// The list of running copies includes this process, at any position. Only the other
    /// copies may be asked to quit.
    func testOtherInstancesNeverContainTheOwnProcess() {
        XCTAssertEqual(Utils.otherInstanceProcessIdentifiers(running: [100, 200], own: 100), [200])
        XCTAssertEqual(Utils.otherInstanceProcessIdentifiers(running: [200, 100], own: 100), [200])
        XCTAssertEqual(Utils.otherInstanceProcessIdentifiers(running: [300, 100, 200], own: 100), [300, 200])
    }

    func testNoOtherInstancesWhenOnlyThisProcessRuns() {
        XCTAssertEqual(Utils.otherInstanceProcessIdentifiers(running: [100], own: 100), [])
        XCTAssertEqual(Utils.otherInstanceProcessIdentifiers(running: [], own: 100), [])
    }

    /// A copy that is not in the list yet (still registering) must not hide the others.
    func testOtherInstancesWhenTheOwnProcessIsNotListed() {
        XCTAssertEqual(Utils.otherInstanceProcessIdentifiers(running: [200], own: 100), [200])
    }

    // MARK: - Application name from a path

    /// "50% Off" is not valid percent-encoding; the name used to be force-unwrapped.
    func testParseNameKeepsANameWithAStrayPercentSign() {
        XCTAssertEqual(Utils.parseName(fromPath: "/Applications/50% Off.app"), "50% Off")
        XCTAssertEqual(Utils.parseName(fromPath: "/Applications/100%.app"), "100%")
    }

    func testParseNameStillDecodesPercentEncoding() {
        XCTAssertEqual(Utils.parseName(fromPath: "/Applications/My%20App.app"), "My App")
    }

    /// Only the ".app" extension is removed, not any "app" inside the name.
    func testParseNameRemovesOnlyTheExtension() {
        XCTAssertEqual(Utils.parseName(fromPath: "/Applications/Snapper.app"), "Snapper")
        XCTAssertEqual(Utils.parseName(fromPath: "/Applications/Safari.app"), "Safari")
        XCTAssertEqual(Utils.parseName(fromPath: "/usr/bin/happy"), "happy")
    }

    // MARK: - Accent colour

    /// The launch line of the `app` log says which accent the user sees: the app's purple
    /// while the system's choice is "Multicolour" (no value stored), else the user's own.
    /// Pure: no setting of this Mac is read.
    func testTheAccentLineSaysWhichAccentIsInEffect() {
        XCTAssertEqual(AppAccent.systemAccentKey, "AppleAccentColor")
        XCTAssertEqual(AppAccent.logLine(systemAccentValue: nil), "Accent colour: the app's own (purple)")
        // Graphite is -1, red 0, purple 5: any stored value is a choice of the user's.
        for value: Any in [-1, 0, 4, 5, "5"] {
            XCTAssertEqual(
                AppAccent.logLine(systemAccentValue: value),
                "Accent colour: the user's system choice (the app's purple shows with \"Multicolour\")",
                "\(value)"
            )
        }
    }

    /// The built app names its own accent colour (the build setting
    /// ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME), the purple of its icon.
    func testTheAppNamesThePurpleOfItsIconAsItsAccentColour() throws {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "NSAccentColorName") as? String, AppAccent.assetName)
        let accent = try XCTUnwrap(NSColor(named: AppAccent.assetName))
        XCTAssertEqual(try hex(accent, in: .aqua), "#5F44B3")
        XCTAssertEqual(try hex(accent, in: .darkAqua), "#7F62D9")
    }

    /// White on the accent (a selected row's text, the number on a lit button, a key that is
    /// already bound): at least 4.5:1 in light, the contrast of body text; at least 3:1 in
    /// dark, the contrast for large text and controls (macOS's own blue in dark, #0A84FF,
    /// gives 3.65:1).
    func testWhiteOnTheAccentIsReadable() throws {
        let accent = try XCTUnwrap(NSColor(named: AppAccent.assetName))
        XCTAssertGreaterThanOrEqual(try contrastWithWhite(accent, in: .aqua), 4.5)
        XCTAssertGreaterThanOrEqual(try contrastWithWhite(accent, in: .darkAqua), 3)
    }

    /// The menu bar icon: a template image (the menu bar gives it its colour), 18 × 18 pt.
    func testTheStatusItemImageIsATemplateOf18Points() throws {
        let image = try XCTUnwrap(NSImage(named: "AppStatusBarIcon"))
        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
    }

    private func resolved(_ color: NSColor, in name: NSAppearance.Name) throws -> NSColor {
        let appearance = try XCTUnwrap(NSAppearance(named: name))
        var result: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            result = color.usingColorSpace(.sRGB)
        }
        return try XCTUnwrap(result)
    }

    private func hex(_ color: NSColor, in name: NSAppearance.Name) throws -> String {
        let rgb = try resolved(color, in: name)
        func byte(_ value: CGFloat) -> Int { Int((value * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(rgb.redComponent), byte(rgb.greenComponent), byte(rgb.blueComponent))
    }

    /// The WCAG contrast ratio of white text on `color`.
    private func contrastWithWhite(_ color: NSColor, in name: NSAppearance.Name) throws -> Double {
        let rgb = try resolved(color, in: name)
        func linear(_ value: CGFloat) -> Double {
            let v = Double(value)
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
        return 1.05 / (luminance + 0.05)
    }
    // MARK: - A mouse button number that does not fit

    /// CoreGraphics keeps a mouse event's button number in 8 bits and reads it back signed:
    /// 128 to 255 come back negative (200 as -56). `UInt16(_:)` trapped on that, in the
    /// button tap's callback, for any such event another program made up.
    func testAButtonNumberAbove127DoesNotTrapAndIsTheNumberThatWasSet() throws {
        for number in [Int64(2), 31, 127, 128, 200, 255] {
            let event = try XCTUnwrap(CGEvent(
                mouseEventSource: nil, mouseType: .otherMouseDown, mouseCursorPosition: .zero, mouseButton: .center
            ))
            event.setIntegerValueField(.mouseEventButtonNumber, value: number)
            XCTAssertEqual(event.mouseCode, UInt16(number), "button \(number)")
            // The whole path of the button tap: the event becomes an input event, unbound.
            let input = InputEvent(fromCGEvent: event)
            XCTAssertEqual(input.type, .mouse)
            XCTAssertEqual(input.code, UInt16(number))
            XCTAssertFalse(LogiCenter.shared.isLogiCode(input.code), "never mistaken for a Logitech control")
        }
        let event = try XCTUnwrap(CGEvent(
            mouseEventSource: nil, mouseType: .otherMouseDown, mouseCursorPosition: .zero, mouseButton: .center
        ))
        event.setIntegerValueField(.mouseEventButtonNumber, value: 200)
        XCTAssertLessThan(event.getIntegerValueField(.mouseEventButtonNumber), 0, "what CoreGraphics gives back for 200")
        XCTAssertEqual(CGEvent.mouseButtonCode(fromField: -56), 200)
        XCTAssertEqual(CGEvent.mouseButtonCode(fromField: -128), 128)
        XCTAssertEqual(CGEvent.mouseButtonCode(fromField: -1), 255)
        XCTAssertEqual(CGEvent.mouseButtonCode(fromField: 3), 3)
    }

    /// A stored switch that is missing is its default, not "off".
    func testAStoredSwitchThatIsMissingIsItsDefault() throws {
        let defaults = TestDefaults.make(for: self)
        XCTAssertTrue(Options.storedBool(forKey: "smooth", default: true, in: defaults))
        XCTAssertFalse(Options.storedBool(forKey: "smooth", default: false, in: defaults))
        defaults.set(false, forKey: "smooth")
        XCTAssertFalse(Options.storedBool(forKey: "smooth", default: true, in: defaults))
        defaults.set(true, forKey: "smooth")
        XCTAssertTrue(Options.storedBool(forKey: "smooth", default: false, in: defaults))
    }
}
