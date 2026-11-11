import XCTest
@testable import Mos_Debug

/// Strings of the preferences panes, the window and its kit, the menus and the Introduction
/// window must exist in every shipped locale, keep their format specifiers, and never fall
/// back to the raw key. Several keys are built from variables in code, so a missing one
/// would only show up as the key itself in the UI.
final class PreferencesLocalizationTests: XCTestCase {

    /// English only for now. The string catalogs stay, so adding a language means adding
    /// its translations to the catalogs, its region to the project and its code here.
    static let locales = ["en"]

    // MARK: - Keys, per area
    // Each task edits only the arrays of its own area; `keys` is their union.

    /// Mouse pane.
    static let mouseKeys = [
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
    ]

    /// Scrolling pane.
    static let scrollingKeys = [
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
    ]

    /// Buttons pane: the card, the list and its rows, the action menu, "Which Button Is
    /// This?", the ⓘ popovers and the Open App or File popover.
    static let buttonsKeys = [
        "buttons-trigger-left", "buttons-trigger-right", "buttons-trigger-middle", "buttons-trigger-back",
        "buttons-trigger-forward", "buttons-trigger-number", "buttons-trigger-gesture", "buttons-trigger-mode-shift",
        "buttons-trigger-thumb-panel", "buttons-trigger-pointer-speed",
        "buttons-trigger-logitech", "buttons-trigger-logitech-twin", "buttons-trigger-key",
        "buttons-header-your-mouse", "buttons-header-count", "buttons-header-one", "buttons-header-none",
        "buttons-header-no-action", "buttons-header-recording", "buttons-header-recording-hint",
        "buttons-header-find-hint", "buttons-header-find-this-one", "buttons-header-answer", "buttons-note-extra-button",
        "buttons-empty-title", "buttons-empty-hint", "buttons-list-label",
        "buttons-note-gesture-navigation", "buttons-note-hold-action", "buttons-note-no-action",
        "buttons-note-scroll-key", "buttons-note-conflict", "buttons-note-contended", "buttons-note-bluetooth",
        "buttons-note-standard-button", "buttons-scroll-key-title", "buttons-scroll-key-detail",
        "buttons-problem-info", "buttons-checking", "buttons-undo-remove", "buttons-show-gesture-settings",
        "buttons-trigger-placed", "buttons-header-place-this-one", "buttons-place-title", "buttons-place-help",
        "buttons-place-gesture", "buttons-place-thumb-panel", "buttons-place-back", "buttons-place-forward",
        "buttons-place-mode-shift", "buttons-place-middle", "buttons-place-none", "buttons-place-used-by",
        "buttons-place-in-list",
        "button_conflict_title", "button_conflict_detail", "button_contended_title", "button_contended_detail",
        "button_standard_mouse_alias_title", "button_standard_mouse_alias_detail",
        "button_ble_hidpp_unstable_title", "button_ble_hidpp_unstable_detail", "button_use_native_mouse",
        "unbound", "custom-recording-prompt", "custom-shortcut", "open-target-action",
        "mouseGestureNavigation", "gesture-navigation-menu-tooltip",
        "categoryMosMouseScroll", "categoryLogiActions", "categoryFinderActions",
        "open-target-title", "open-target-empty-primary", "open-target-empty-secondary",
        "open-target-arguments-placeholder", "open-target-stale-warning", "open-target-cancel", "open-target-done",
    ]

    /// Gestures pane and its gesture controls.
    static let gesturesKeys = [
        "gesture-direction-up", "gesture-direction-down",
        "gesture-direction-left", "gesture-direction-right", "gesture-direction-click", "gesture-action-none",
        "gesture-invert-horizontal", "gesture-freeze-pointer",
        "gesture-mode-discrete", "gesture-mode-interactive", "gesture-mode-interactive-note",
        "gesture-mode-interactive-unavailable", "gesture-follow-horizontal-value",
        "gestures-tab-title", "gesture-mode-label", "gesture-mode-discrete-description",
        "gesture-mode-interactive-description", "gesture-invert-horizontal-hint", "gesture-freeze-pointer-hint",
        "gesture-tracking-speed-label", "gesture-tracking-speed-hint", "gesture-tracking-speed-hint-discrete",
        "gesture-tracking-speed-slower", "gesture-tracking-speed-faster",
        "gestures-gesture-button", "gestures-gesture-button-none", "gestures-gesture-button-bound", "gestures-gesture-button-set-up",
        "gestures-gesture-button-change", "gestures-directions-header", "gestures-directions-hint",
        "gestures-behaviour-header", "gestures-logitech-header", "gestures-logitech-needs",
        "mouse-gesture-device-tracking", "mouse-gesture-device-tracking-hint", "mouse-gesture-device-tracking-unavailable",
        "mouse-gesture-haptics", "mouse-gesture-haptics-hint", "mouse-gesture-haptics-unavailable",
        "gestures-haptics-off-under-mouse", "gestures-open-mouse",
    ]

    /// Apps pane and an app's page.
    static let appsKeys = [
        "apps-limit", "apps-limit-hint", "apps-list-header", "apps-row-inherit", "apps-row-own",
        "apps-empty-title", "apps-empty-hint", "apps-choose-in-finder", "apps-open-panel-prompt",
        "apps-undo-remove", "apps-back", "apps-back-accessibility", "apps-detail-inherit",
        "apps-detail-inherit-on", "apps-detail-inherit-off",
    ]

    /// General pane, with what the About pane showed (the `about-*` keys).
    static let generalKeys = [
        "general-launch-at-login", "general-launch-at-login-hint", "general-launch-at-login-waiting",
        "general-login-approval", "general-open-login-items",
        "general-show-in-menu-bar", "general-show-in-menu-bar-hint",
        "general-paused", "general-paused-hint", "general-resume",
        "general-permissions-header", "general-accessibility", "general-accessibility-hint",
        "general-accessibility-allowed", "general-accessibility-not-allowed", "general-accessibility-open-settings",
        "general-advanced", "general-scroll-monitor", "general-scroll-monitor-hint",
        "general-diagnostics", "general-diagnostics-hint", "general-open-window",
        "about-app-name", "about-version", "about-credit", "about-welcome-guide",
        "about-welcome-guide-open", "about-welcome-guide-hint",
    ]

    /// The window and the kit: the sidebar, the + and − under a list.
    static let windowKeys = [
        "preferences-sidebar", "list-add", "list-remove",
    ]

    /// Main menu and status-bar menu, the windows they open, and the toasts of the app.
    static let menuKeys = [
        "status-menu-pause", "status-menu-resume", "status-menu-allow-access", "status-menu-test-toasts",
        "status-menu-battery", "status-menu-battery-charging", "status-item-paused", "status-item-needs-access",
        "scroll-monitor-title", "logitech-diagnostics-title",
        "toast-accessibility-lost", "toast-battery-low", "toast-battery-low-plain",
        "toast-battery-critical", "toast-battery-critical-plain",
        "logi_ble_hidpp_unstable_toast", "logi_ble_contention_standard_mouse_alias_toast",
        "logi_hidpp_contention_toast", "openTargetScriptNotExecutable",
        "main-menu-application", "main-menu-about", "main-menu-settings", "main-menu-services",
        "main-menu-hide", "main-menu-hide-others", "main-menu-show-all", "main-menu-quit",
        "main-menu-edit", "main-menu-undo", "main-menu-redo", "main-menu-cut", "main-menu-copy",
        "main-menu-paste", "main-menu-select-all", "main-menu-window", "main-menu-minimize",
        "main-menu-zoom", "main-menu-close", "main-menu-bring-all-to-front", "main-menu-help",
        "main-menu-welcome-guide",
    ]

    /// Introduction window (Welcome Guide).
    static let introKeys = [
        "intro-title", "intro-subtitle", "intro-access-heading", "intro-access-explanation",
        "intro-step-open-settings", "intro-step-open-settings-detail", "intro-step-turn-on",
        "intro-step-turn-on-detail", "intro-step-accessibility",
        "intro-status-missing", "intro-status-missing-detail", "intro-status-granted",
        "intro-status-granted-detail", "intro-status-granted-detail-hidden-icon",
        "intro-open-settings-button", "intro-open-app-settings-button", "intro-done-button",
        "intro-help-link", "intro-help-heading", "intro-help-text", "intro-help-finder-button",
    ]

    static let keys = mouseKeys + scrollingKeys + buttonsKeys + gesturesKeys + appsKeys
        + generalKeys + windowKeys + menuKeys + introKeys

    private static let missing = "\u{1}missing"

    private func bundle(for locale: String) -> Bundle? {
        let app = Bundle(for: PreferencesSplitViewController.self)
        guard let path = app.path(forResource: locale, ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }

    private func specifiers(_ text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: "%(?:\\d+\\$)?[@dDuUxXoOfeEgGcCsSpaAF]|%%")
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).map { (text as NSString).substring(with: $0.range) }.sorted()
    }

    /// A key belongs to one area, so two tasks never list the same key.
    func testEveryKeyIsListedOnce() {
        var seen = Set<String>()
        let repeated = Self.keys.filter { !seen.insert($0).inserted }
        XCTAssertEqual(repeated, [])
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
