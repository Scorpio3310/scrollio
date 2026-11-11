import XCTest
@testable import Mos_Debug

/// Strings of the reorganised preferences (Mouse tab, Scrolling tab, Gesture
/// Settings, Gestures tab), of the main menu and of the Introduction window must exist in every shipped
/// locale, keep their format specifiers, and never fall back to the raw key. Several keys are built from variables in code, so a missing
/// one would only show up as the key itself in the UI.
final class PreferencesLocalizationTests: XCTestCase {

    /// English only for now. The string catalogs stay, so adding a language means adding
    /// its translations to the catalogs, its region to the project and its code here.
    static let locales = ["en"]

    static let keys = [
        // Mouse tab
        "mouse-tab-title", "mouse-header-no-mouse", "mouse-header-connected", "mouse-header-connected-several",
        "mouse-battery-about", "mouse-battery-full", "mouse-battery-good", "mouse-battery-low",
        "mouse-battery-critical", "mouse-battery-not-charging", "mouse-battery-accessibility",
        "mouse-battery-accessibility-charging", "mouse-no-mouse", "mouse-no-mouse-hint",
        "mouse-wheel-managed", "mouse-wheel-managed-hint",
        "mouse-pointer-header", "mouse-pointer-speed", "mouse-pointer-speed-hint", "mouse-pointer-speed-slower",
        "mouse-pointer-speed-faster", "mouse-pointer-speed-value",
        "mouse-wheel-label", "mouse-wheel-mode-label", "mouse-wheel-mode-smartshift", "mouse-wheel-mode-ratchet",
        "mouse-wheel-mode-free-spin", "mouse-wheel-mode-smartshift-hint", "mouse-wheel-mode-ratchet-hint",
        "mouse-wheel-mode-free-spin-hint", "mouse-wheel-sensitivity-label", "mouse-wheel-sensitivity-hint",
        "mouse-wheel-sensitivity-later", "mouse-wheel-sensitivity-sooner", "mouse-wheel-force-label",
        "mouse-wheel-force-hint", "mouse-wheel-force-soft", "mouse-wheel-force-firm", "mouse-wheel-readback-one",
        "mouse-haptics-header", "mouse-haptics", "mouse-haptics-hint", "mouse-haptics-strength",
        "mouse-haptics-strength-hint", "mouse-haptics-strength-light", "mouse-haptics-strength-strong",
        "mouse-press-force", "mouse-press-force-hint", "mouse-press-force-light", "mouse-press-force-firm",
        "mouse-value-on", "mouse-value-off", "mouse-diagnostics-button",
        // Scrolling tab
        "scrolling-smooth", "scrolling-smooth-hint",
        "scrolling-feel-label", "scrolling-feel-direct", "scrolling-feel-quick", "scrolling-feel-smooth",
        "scrolling-feel-glide", "scrolling-feel-float", "scrolling-feel-direct-hint", "scrolling-feel-quick-hint",
        "scrolling-feel-smooth-hint", "scrolling-feel-glide-hint", "scrolling-feel-float-hint",
        "scrolling-feel-custom-hint",
        "scrolling-speed-label", "scrolling-speed-hint", "scrolling-speed-shorter", "scrolling-speed-farther",
        "scrolling-reverse", "scrolling-reverse-hint",
        "scrolling-advanced", "scrolling-glide-time-label", "scrolling-glide-time-hint",
        "scrolling-step-label", "scrolling-step-hint",
        "scrolling-trackpad-events", "scrolling-trackpad-events-hint",
        "scrolling-keys-header", "scrolling-key-faster", "scrolling-key-faster-hint",
        "scrolling-key-sideways", "scrolling-key-sideways-hint", "scrolling-key-pause", "scrolling-key-pause-hint",
        "scrolling-key-clear", "scrolling-reset",
        // Gesture Settings
        "mouseGestureNavigation", "gesture-navigation-menu-tooltip",
        "gesture-settings-menu", "gesture-direction-up", "gesture-direction-down",
        "gesture-direction-left", "gesture-direction-right", "gesture-direction-click", "gesture-action-none",
        "gesture-invert-horizontal", "gesture-freeze-pointer", "gesture-settings-footnote",
        "gesture-mode-discrete", "gesture-mode-interactive", "gesture-mode-interactive-note",
        "gesture-mode-interactive-unavailable", "gesture-follow-horizontal-value",
        // Gestures tab
        "gestures-tab-title", "gesture-mode-label", "gesture-mode-discrete-description",
        "gesture-mode-interactive-description", "gesture-invert-horizontal-hint", "gesture-freeze-pointer-hint",
        "gesture-tracking-speed-label", "gesture-tracking-speed-hint", "gesture-tracking-speed-hint-discrete",
        "gesture-tracking-speed-slower", "gesture-tracking-speed-faster",
        "gestures-unbound-title", "gestures-unbound-hint", "gestures-directions-header", "gestures-directions-hint",
        "gestures-behaviour-header", "gestures-logitech-header", "gestures-logitech-needs", "gestures-buttons-note",
        "mouse-gesture-device-tracking", "mouse-gesture-device-tracking-hint", "mouse-gesture-device-tracking-unavailable",
        "mouse-gesture-haptics", "mouse-gesture-haptics-hint", "mouse-gesture-haptics-unavailable",
        // About
        "about-tab-title", "about-app-name", "about-version", "about-credit", "about-welcome-guide",
        // Main menu
        "main-menu-application", "main-menu-about", "main-menu-settings", "main-menu-services",
        "main-menu-hide", "main-menu-hide-others", "main-menu-show-all", "main-menu-quit",
        "main-menu-edit", "main-menu-undo", "main-menu-redo", "main-menu-cut", "main-menu-copy",
        "main-menu-paste", "main-menu-select-all", "main-menu-window", "main-menu-minimize",
        "main-menu-zoom", "main-menu-close", "main-menu-bring-all-to-front", "main-menu-help",
        "main-menu-welcome-guide",
        // Introduction window
        "intro-title", "intro-subtitle", "intro-access-heading", "intro-access-explanation",
        "intro-step-open-settings", "intro-step-open-settings-detail", "intro-step-turn-on",
        "intro-step-turn-on-detail", "intro-step-accessibility",
        "intro-status-missing", "intro-status-missing-detail", "intro-status-granted",
        "intro-status-granted-detail", "intro-status-granted-detail-hidden-icon",
        "intro-open-settings-button", "intro-get-started-button", "intro-done-button",
        "intro-help-link", "intro-help-heading", "intro-help-text", "intro-help-finder-button",
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
