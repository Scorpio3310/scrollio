//
//  PreferencesFormTests.swift
//  MosTests
//
//  What the panes built in code share besides the grouped kit: the hint and header type,
//  and snapping a slider value.
//

import XCTest
@testable import Scrollio_Debug

final class PreferencesFormTests: XCTestCase {

    func testHintsUseOneFontSizeOfAtLeastTenPoints() {
        XCTAssertGreaterThanOrEqual(PreferencesForm.hintFontSize, 10)
        XCTAssertEqual(PreferencesForm.hintFontSize, NSFont.smallSystemFontSize)
        XCTAssertEqual(PreferencesForm.hintFont.pointSize, PreferencesForm.hintFontSize)
    }

    func testASectionHeaderIsSemiboldAtTheSystemSize() {
        let font = PreferencesForm.sectionHeaderFont
        XCTAssertEqual(font.pointSize, 13)
        let traits = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
        XCTAssertEqual(traits?[.weight] as? CGFloat ?? 0, NSFont.Weight.semibold.rawValue, accuracy: 0.01)
    }

    func testSnappedClampsToTheRangeAndRoundsToTheStep() {
        XCTAssertEqual(PreferencesForm.snapped(-1, to: 0...1, step: 0.05), 0)
        XCTAssertEqual(PreferencesForm.snapped(9, to: 0...1, step: 0.05), 1)
        XCTAssertEqual(PreferencesForm.snapped(0.42, to: 0...1, step: 0.05), 0.4)
        XCTAssertEqual(PreferencesForm.snapped(0.43, to: 0...1, step: 0.05), 0.45)
        // From the lower bound, without floating-point noise.
        XCTAssertEqual(PreferencesForm.snapped(0.81, to: 0.25...3, step: 0.05), 0.8)
        XCTAssertEqual(PreferencesForm.snapped(1.26, to: 0.5...3, step: 0.1), 1.3)
        // Not a number: the lower bound.
        XCTAssertEqual(PreferencesForm.snapped(.nan, to: 0.25...3, step: 0.05), 0.25)
        XCTAssertEqual(PreferencesForm.snapped(.infinity, to: 0...5, step: 0.05), 0)
        // No step: only clamped.
        XCTAssertEqual(PreferencesForm.snapped(0.123, to: 0...1, step: 0), 0.123)
    }

    /// A link button is in the accent colour (the app's violet), not the system's blue link
    /// colour: "Having trouble?" was the one blue thing in the windows.
    func testALinkButtonIsInTheAccentColour() throws {
        let button = PreferencesForm.makeLinkButton(title: "Having trouble?", target: nil, action: nil)
        let colour = try XCTUnwrap(
            button.attributedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        )
        XCTAssertEqual(colour, .controlAccentColor)
        XCTAssertNotEqual(colour, .linkColor)
        XCTAssertEqual(PreferencesForm.linkColor, .controlAccentColor)
        XCTAssertFalse(button.isBordered)
    }
}

/// Toasts: how long one stays (as long as its text takes to read, and not while the pointer
/// is over it) and that VoiceOver hears it. No toast is put on screen here.
final class ToastTests: XCTestCase {

    private func text(_ key: String) -> String {
        return NSLocalizedString(key, comment: "")
    }

    /// A manager of its own that shows nothing and says nothing aloud.
    private func makeManager() -> (manager: ToastManager, spoken: () -> [String]) {
        let manager = ToastManager()
        manager.orderFront = { _ in }
        var spoken: [String] = []
        manager.announce = { message, _ in spoken.append(message) }
        addTeardownBlock { manager.testingRemoveAll() }
        return (manager, { spoken })
    }

    // MARK: - Time by length

    func testAShortToastStaysThreeSecondsAndALongOneUpToTen() {
        XCTAssertEqual(ToastTiming.readingDuration(for: ""), 3)
        XCTAssertEqual(ToastTiming.readingDuration(for: "Saved"), 3)
        XCTAssertEqual(ToastTiming.readingDuration(for: String(repeating: "x", count: 25)), 3, accuracy: 0.05)
        XCTAssertEqual(ToastTiming.readingDuration(for: String(repeating: "x", count: 51)), 4.5, accuracy: 1e-9)
        XCTAssertEqual(ToastTiming.readingDuration(for: String(repeating: "x", count: 92)), 1.5 + 92.0 / 17, accuracy: 1e-9)
        XCTAssertEqual(ToastTiming.readingDuration(for: String(repeating: "x", count: 400)), 10)
        var last: TimeInterval = 0
        for length in stride(from: 0, through: 300, by: 7) {
            let duration = ToastTiming.readingDuration(for: String(repeating: "x", count: length))
            XCTAssertGreaterThanOrEqual(duration, last, "\(length): a longer text never stays shorter")
            last = duration
        }
    }

    /// The warnings that are sent without a duration and say what to do were on screen for
    /// 2.5 seconds, less than half of what they take to read.
    func testTheWarningsThatSayWhatToDoStayLongEnoughToRead() {
        let warnings = [
            String(format: text("logi_ble_contention_standard_mouse_alias_toast"), "Back button"),
            String(format: text("logi_ble_hidpp_unstable_toast"), "Mode shift button"),
            String(format: text("openTargetAppNotFound"), "Visual Studio Code.app"),
            String(format: text("openTargetScriptNotExecutable"), "deploy.sh"),
        ]
        for warning in warnings {
            let duration = ToastTiming.readingDuration(for: warning)
            XCTAssertGreaterThan(duration, 2.5, warning)
            // At a calm reading pace, with a moment to notice the toast first.
            XCTAssertGreaterThanOrEqual(duration, min(10, Double(warning.count) / 17 + 1.5) - 1e-9, warning)
        }
        XCTAssertGreaterThanOrEqual(
            ToastTiming.readingDuration(for: String(format: text("logi_ble_contention_standard_mouse_alias_toast"), "Back button")), 6
        )
    }

    /// A toast shown without a duration gets the reading time; a caller's own duration stands.
    func testAToastWithoutADurationGetsItsReadingTime() {
        let (manager, _) = makeManager()
        let message = String(repeating: "A warning that says what to do. ", count: 3)
        XCTAssertEqual(Toast.resolvedDuration(nil, for: message), ToastTiming.readingDuration(for: message))
        XCTAssertEqual(Toast.resolvedDuration(nil, for: "Saved"), 3, "no longer 2.5 s for everything")
        XCTAssertEqual(Toast.resolvedDuration(8, for: message), 8)
        XCTAssertEqual(Toast.resolvedDuration(0.5, for: message), 0.5, "the debug panel's own choice stands")
        manager.present(message: message, style: .warning, duration: Toast.resolvedDuration(nil, for: message), icon: nil, showsIcon: true)
        manager.present(message: "Eight seconds", style: .warning, duration: 8, icon: nil, showsIcon: true)
        let toasts = manager.testingToasts
        XCTAssertEqual(toasts.map(\.message), [message, "Eight seconds"])
        XCTAssertEqual(toasts[0].remaining, 1.5 + Double(message.count) / 17, accuracy: 1e-9)
        XCTAssertEqual(toasts[1].remaining, 8)
        XCTAssertTrue(toasts.allSatisfy { $0.hasTimer && !$0.isPaused })
    }

    // MARK: - The pointer over a toast

    func testTheCountdownStandsStillWhilePaused() {
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        var countdown = ToastCountdown(duration: 6, now: start)
        XCTAssertFalse(countdown.isPaused)
        XCTAssertNil(countdown.resume(now: start.addingTimeInterval(1)), "running: nothing to restart")

        countdown.pause(now: start.addingTimeInterval(2))
        XCTAssertTrue(countdown.isPaused)
        XCTAssertEqual(countdown.remaining, 4, accuracy: 1e-9)
        countdown.pause(now: start.addingTimeInterval(30))
        XCTAssertEqual(countdown.remaining, 4, accuracy: 1e-9, "a second pause changes nothing")

        // A minute later the pointer leaves: what was left is still left.
        XCTAssertEqual(try XCTUnwrap(countdown.resume(now: start.addingTimeInterval(62))), 4, accuracy: 1e-9)
        XCTAssertFalse(countdown.isPaused)

        // Paused in its last half second: a moment is left when the pointer leaves.
        countdown.pause(now: start.addingTimeInterval(65.7))
        XCTAssertEqual(countdown.remaining, 0.3, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(countdown.resume(now: start.addingTimeInterval(70))), ToastTiming.minimumAfterHover)

        // Past its end (the timer had not fired yet): never negative.
        var late = ToastCountdown(duration: 3, now: start)
        late.pause(now: start.addingTimeInterval(9))
        XCTAssertEqual(late.remaining, 0)
    }

    /// The pointer over a toast stops its timer; when it leaves, the timer runs again with
    /// what was left. The other toasts run on.
    func testAToastWaitsWhileThePointerIsOverIt() throws {
        let (manager, _) = makeManager()
        var clock = Date(timeIntervalSinceReferenceDate: 5000)
        manager.now = { clock }
        manager.present(message: "First", style: .warning, duration: 6, icon: nil, showsIcon: true)
        manager.present(message: "Second", style: .info, duration: 6, icon: nil, showsIcon: true)
        let first = try XCTUnwrap(manager.testingToasts.first).panel

        clock = clock.addingTimeInterval(2)
        manager.setHovered(true, for: first)
        var toasts = manager.testingToasts
        XCTAssertEqual(toasts.map(\.isPaused), [true, false])
        XCTAssertEqual(toasts.map(\.hasTimer), [false, true], "no timer takes it away under the pointer")
        XCTAssertEqual(toasts[0].remaining, 4, accuracy: 1e-9)

        clock = clock.addingTimeInterval(20)
        manager.setHovered(false, for: first)
        toasts = manager.testingToasts
        XCTAssertEqual(toasts.map(\.isPaused), [false, false])
        XCTAssertEqual(toasts.map(\.hasTimer), [true, true])
        XCTAssertEqual(toasts[0].remaining, 4, accuracy: 1e-9, "what was left when the pointer came")

        // Leaving without having entered (the toast appeared under a pointer at rest) is nothing.
        manager.setHovered(false, for: first)
        XCTAssertEqual(manager.testingToasts[0].remaining, 4, accuracy: 1e-9)
        // A panel that is not a toast's is ignored.
        manager.setHovered(true, for: NSPanel())
        XCTAssertEqual(manager.testingToasts.map(\.isPaused), [false, false])
    }

    func testTheToastViewTracksThePointerWhicheverAppIsInFront() throws {
        let view = ToastContentView(message: "A warning", icon: nil, accentColor: nil, showsAccentIndicator: false)
        view.updateTrackingAreas()
        let area = try XCTUnwrap(view.trackingAreas.first { $0.owner === view })
        XCTAssertTrue(area.options.contains(.mouseEnteredAndExited))
        XCTAssertTrue(area.options.contains(.activeAlways), "Scrollio is rarely the app in front")
        XCTAssertTrue(area.options.contains(.inVisibleRect))
        view.updateTrackingAreas()
        XCTAssertEqual(view.trackingAreas.filter { $0.owner === view }.count, 1, "one area, however often it is asked")
    }

    /// The pointer entering and leaving a toast's view reaches its manager: the toast waits.
    func testThePointerOverAToastsViewStopsItsTime() throws {
        let (manager, _) = makeManager()
        manager.present(message: "A warning", style: .warning, duration: 6, icon: nil, showsIcon: true)
        let toast = try XCTUnwrap(manager.testingToasts.first)
        let view = try XCTUnwrap(toast.panel.contentView as? ToastContentView)
        let moved = try XCTUnwrap(NSEvent.enterExitEvent(
            with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: toast.panel.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil
        ))
        view.mouseEntered(with: moved)
        XCTAssertEqual(manager.testingToasts.map(\.isPaused), [true])
        XCTAssertEqual(manager.testingToasts.map(\.hasTimer), [false])
        view.mouseExited(with: moved)
        XCTAssertEqual(manager.testingToasts.map(\.isPaused), [false])
        XCTAssertEqual(manager.testingToasts.map(\.hasTimer), [true])
    }

    // MARK: - VoiceOver

    /// A toast takes no focus, so VoiceOver never read one: "Scrollio stopped: Accessibility
    /// access was turned off…" and the battery warnings were silent. Each new toast is
    /// announced once; one that is already on screen is not said again.
    func testANewToastIsAnnouncedOnce() {
        let manager = ToastManager()
        manager.orderFront = { _ in }
        addTeardownBlock { manager.testingRemoveAll() }
        var spoken: [(String, Toast.Style)] = []
        manager.announce = { spoken.append(($0, $1)) }
        let lost = text("toast-accessibility-lost")

        manager.present(message: lost, style: .warning, duration: 5, icon: nil, showsIcon: true)
        XCTAssertEqual(spoken.map(\.0), [lost])
        XCTAssertEqual(spoken.first?.1, .warning)

        manager.present(message: lost, style: .warning, duration: 5, icon: nil, showsIcon: true)
        XCTAssertEqual(spoken.count, 1, "the same message while it is on screen: not shown and not said twice")
        XCTAssertEqual(manager.testingToasts.count, 1)

        manager.present(message: "Battery is low.", style: .info, duration: 5, icon: nil, showsIcon: false)
        XCTAssertEqual(spoken.map(\.0), [lost, "Battery is low."])
    }
}
