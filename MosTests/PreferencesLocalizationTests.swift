import XCTest
@testable import Mos_Debug

/// Strings of the reorganised preferences (Mouse tab, Presets & Fast Scrolling, Gesture
/// Settings) must exist in every shipped locale, keep their format specifiers, and never
/// fall back to the raw key. Several keys are built from variables in code, so a missing
/// one would only show up as the key itself in the UI.
final class PreferencesLocalizationTests: XCTestCase {

    static let locales = [
        "cs", "de", "el", "en", "fr", "ja", "ko", "ru", "th", "tr", "uk",
        "zh-Hans", "zh-Hant", "zh-Hant-HK", "zh-Hant-TW",
    ]

    static let keys = [
        // Mouse tab
        "mouse-tab-title", "mouse-devices-label", "mouse-devices-empty", "mouse-devices-empty-hint",
        "mouse-device-supports-smartshift", "mouse-device-supports-scroll-force", "mouse-device-supports-none",
        "mouse-wheel-label", "mouse-wheel-managed", "mouse-wheel-managed-hint", "mouse-wheel-mode-label",
        "mouse-wheel-mode-smartshift", "mouse-wheel-mode-ratchet", "mouse-wheel-mode-free-spin",
        "mouse-wheel-sensitivity-label", "mouse-wheel-sensitivity-hint", "mouse-wheel-force-label",
        "mouse-wheel-force-hint", "mouse-wheel-readback-one", "mouse-wheel-readback-named",
        "mouse-advanced-label", "mouse-diagnostics-button", "mouse-diagnostics-hint",
        // Presets & Fast Scrolling
        "scroll-tuning-button", "scroll-tuning-title", "scroll-tuning-preset-label",
        "scroll-preset-direct", "scroll-preset-balanced", "scroll-preset-smooth", "scroll-preset-trackpad-like",
        "scroll-preset-custom", "scroll-preset-direct-description", "scroll-preset-balanced-description",
        "scroll-preset-smooth-description", "scroll-preset-trackpad-like-description",
        "scroll-preset-custom-description", "scroll-preset-smooth-off-description",
        "scroll-tuning-free-spin-checkbox", "scroll-tuning-free-spin-smoothness", "scroll-tuning-free-spin-speed",
        "scroll-tuning-acceleration", "scroll-tuning-acceleration-off", "scroll-tuning-footnote",
        // Gesture Settings
        "mouseGestureNavigation", "gesture-settings-menu", "gesture-direction-up", "gesture-direction-down",
        "gesture-direction-left", "gesture-direction-right", "gesture-direction-click", "gesture-action-none",
        "gesture-invert-horizontal", "gesture-freeze-pointer", "gesture-settings-footnote",
    ]

    private static let missing = "\u{1}missing"

    private func bundle(for locale: String) -> Bundle? {
        let app = Bundle(for: PreferencesTabViewController.self)
        guard let path = app.path(forResource: locale, ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }

    private func specifiers(_ text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: "%(?:\\d+\\$)?[@dDuUxXoOfeEgGcCsSpaAF]|%%")
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).map { (text as NSString).substring(with: $0.range) }.sorted()
    }

    func testEveryLocaleTranslatesThePreferencesStrings() throws {
        let english = try XCTUnwrap(bundle(for: "en"), "en.lproj")
        for locale in Self.locales {
            guard let localized = bundle(for: locale) else {
                XCTFail("\(locale).lproj is missing")
                continue
            }
            for key in Self.keys {
                let value = localized.localizedString(forKey: key, value: Self.missing, table: nil)
                XCTAssertNotEqual(value, Self.missing, "\(locale): \(key) missing")
                XCTAssertNotEqual(value, key, "\(locale): \(key) shows the raw key")
                XCTAssertFalse(value.isEmpty, "\(locale): \(key) empty")
                let source = english.localizedString(forKey: key, value: Self.missing, table: nil)
                XCTAssertEqual(specifiers(value), specifiers(source), "\(locale): \(key) format specifiers")
            }
        }
    }
}
