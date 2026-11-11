//
//  IntroductionWindowTests.swift
//  MosTests
//
//  The Welcome Guide (IntroductionViewController): what it shows while Accessibility
//  access is missing and once it is granted, that it follows the real permission, and
//  what its buttons do. The permission, the system prompt, System Settings and Finder are
//  replaced; nothing is shown on screen (windows are created but never ordered in).
//

import XCTest
@testable import Mos_Debug

private func allSubviews(of view: NSView) -> [NSView] {
    return view.subviews.flatMap { [$0] + allSubviews(of: $0) }
}

/// Hidden itself or inside a hidden view.
private func isShown(_ view: NSView) -> Bool {
    return !view.isHiddenOrHasHiddenAncestor
}

final class IntroductionWindowTests: XCTestCase {

    /// What the controller is told about the outside world, and what it did to it.
    private final class World {
        var accessGranted = false
        var menuBarIconHidden = false
        var requests = 0
        var settingsOpened = 0
        var reveals = 0
        var grantsReported = 0
    }

    private func makeController(accessGranted: Bool) -> (IntroductionViewController, World) {
        let world = World()
        world.accessGranted = accessGranted
        let controller = IntroductionViewController()
        controller.isAccessGranted = { world.accessGranted }
        controller.isMenuBarIconHidden = { world.menuBarIconHidden }
        controller.requestAccess = { world.requests += 1 }
        controller.openAccessibilitySettings = { world.settingsOpened += 1 }
        controller.revealApplication = { world.reveals += 1 }
        controller.accessWasGranted = { world.grantsReported += 1 }
        _ = controller.view
        return (controller, world)
    }

    /// A window that holds the controller's view and is never shown.
    private func makeWindow(for controller: IntroductionViewController) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 300),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.setContentSize(controller.view.fittingSize)
        // Somewhere it can grow downwards without reaching the edge of the screen.
        if let visible = NSScreen.main?.visibleFrame {
            window.setFrameTopLeftPoint(NSPoint(x: visible.minX + 40, y: visible.maxY - 20))
        }
        addTeardownBlock { window.close() }
        return window
    }

    private func click(_ button: NSButton) {
        XCTAssertTrue(button.isEnabled, "\(button.title) is disabled")
        XCTAssertTrue(button.sendAction(button.action, to: button.target), button.title)
    }

    private func shownTexts(in view: NSView) -> [String] {
        let views = allSubviews(of: view).filter(isShown)
        return views.compactMap { ($0 as? NSTextField)?.stringValue }.filter { !$0.isEmpty }
            + views.compactMap { ($0 as? NSButton)?.title }.filter { !$0.isEmpty }
    }

    // MARK: - Access missing

    func testWithoutAccessItExplainsTheOneStep() {
        let (controller, world) = makeController(accessGranted: false)

        XCTAssertEqual(controller.accessState, .missing)
        XCTAssertEqual(controller.titleLabel.stringValue, "Welcome to Scrollio")
        XCTAssertEqual(
            controller.subtitleLabel.stringValue,
            "Smooth scrolling, gestures and button actions for your mouse."
        )
        XCTAssertNotNil(controller.iconView.image)

        XCTAssertEqual(controller.accessHeadingLabel.stringValue, "Scrollio needs Accessibility access")
        XCTAssertTrue(controller.accessExplanationLabel.stringValue.contains("mouse events"))
        XCTAssertEqual(controller.stepLabels.map(\.stringValue), [
            "Open the Accessibility settings",
            "Turn on Scrollio",
        ])
        XCTAssertEqual(controller.stepDetailLabels.count, 2)
        XCTAssertEqual(
            controller.stepDetailLabels.first?.stringValue,
            "System Settings › Privacy & Security › Accessibility"
        )
        XCTAssertTrue(controller.stepDetailLabels[1].stringValue.contains("switch next to Scrollio"))
        for label in [controller.accessHeadingLabel!, controller.accessExplanationLabel!]
            + controller.stepLabels + controller.stepDetailLabels {
            XCTAssertTrue(isShown(label), label.stringValue)
        }
        XCTAssertEqual(
            controller.stepLabels.map { $0.accessibilityLabel() },
            ["Step 1: Open the Accessibility settings", "Step 2: Turn on Scrollio"]
        )

        XCTAssertEqual(controller.statusLabel.stringValue, "Accessibility access is not allowed yet")
        XCTAssertFalse(controller.statusDetailLabel.stringValue.isEmpty)
        XCTAssertNotNil(controller.statusIconView.image)

        // Nothing was asked for by merely opening the window.
        XCTAssertEqual(world.requests, 0)
        XCTAssertEqual(world.settingsOpened, 0)
        XCTAssertEqual(world.grantsReported, 0)
    }

    func testThePrimaryButtonIsTheEnabledDefaultButton() {
        let (controller, _) = makeController(accessGranted: false)
        let button = controller.primaryButton!
        XCTAssertEqual(button.title, "Open Accessibility Settings")
        XCTAssertTrue(button.isEnabled)
        XCTAssertTrue(isShown(button))
        XCTAssertEqual(button.keyEquivalent, "\r", "Return presses it, and AppKit draws it in the accent colour")
        XCTAssertEqual(button.bezelStyle, .push)
        XCTAssertEqual(button.controlSize, .large)
        XCTAssertTrue(button.isBordered)
    }

    func testOpenAccessibilitySettingsAsksMacOSAndOpensThePane() {
        let (controller, world) = makeController(accessGranted: false)
        click(controller.primaryButton)
        XCTAssertEqual(world.requests, 1, "the request puts Scrollio into the Accessibility list")
        XCTAssertEqual(world.settingsOpened, 1)
        // Still missing: the window keeps asking, it does not close.
        XCTAssertEqual(controller.accessState, .missing)
        XCTAssertEqual(controller.primaryButton.title, "Open Accessibility Settings")
    }

    func testThePaneIsTheAccessibilityListOfSystemSettings() {
        XCTAssertEqual(
            IntroductionViewController.accessibilityPaneURL.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
    }

    // MARK: - Access granted

    func testWithAccessItShowsTheGrantedStateAndDoesNotAskAgain() {
        let (controller, world) = makeController(accessGranted: true)

        XCTAssertEqual(controller.accessState, .granted)
        XCTAssertEqual(controller.statusLabel.stringValue, "Accessibility access is allowed")
        XCTAssertEqual(
            controller.statusDetailLabel.stringValue,
            "Scrollio is running. Open Preferences from its menu bar icon."
        )
        XCTAssertEqual(controller.primaryButton.title, "Get Started")
        XCTAssertTrue(controller.primaryButton.isEnabled)
        XCTAssertEqual(controller.primaryButton.keyEquivalent, "\r")

        // The steps, the request and the help are gone.
        for label in [controller.accessHeadingLabel!, controller.accessExplanationLabel!]
            + controller.stepLabels + controller.stepDetailLabels {
            XCTAssertFalse(isShown(label), label.stringValue)
        }
        XCTAssertFalse(isShown(controller.helpButton))
        XCTAssertFalse(isShown(controller.helpCard))
        let texts = shownTexts(in: controller.view)
        XCTAssertFalse(texts.contains("Open Accessibility Settings"))
        XCTAssertFalse(texts.contains { $0.contains("System Settings") }, "\(texts)")

        XCTAssertEqual(world.requests, 0)
        XCTAssertEqual(world.settingsOpened, 0)
        XCTAssertEqual(world.grantsReported, 0, "it was granted before the window opened: nothing to start")
    }

    func testOpenedByHandWithAccessItSaysDone() {
        let (controller, world) = makeController(accessGranted: true)
        controller.setManuallyOpened(true)
        XCTAssertTrue(controller.isManuallyOpened)
        XCTAssertEqual(controller.primaryButton.title, "Done")
        XCTAssertEqual(controller.statusLabel.stringValue, "Accessibility access is allowed")
        XCTAssertEqual(world.requests, 0)
        XCTAssertEqual(world.settingsOpened, 0)
    }

    func testOpenedByHandWithoutAccessItStillAsks() {
        let (controller, _) = makeController(accessGranted: false)
        controller.setManuallyOpened(true)
        XCTAssertEqual(controller.primaryButton.title, "Open Accessibility Settings")
        XCTAssertTrue(isShown(controller.stepLabels[0]))
    }

    func testWithAHiddenMenuBarIconItSaysHowToReachTheSettings() {
        let world = World()
        world.accessGranted = true
        world.menuBarIconHidden = true
        let controller = IntroductionViewController()
        controller.isAccessGranted = { world.accessGranted }
        controller.isMenuBarIconHidden = { world.menuBarIconHidden }
        _ = controller.view
        XCTAssertEqual(
            controller.statusDetailLabel.stringValue,
            "Scrollio is running. Its menu bar icon is hidden: open Scrollio again to reach its settings."
        )
    }

    func testTheButtonOfTheGrantedStateClosesTheWindow() {
        let (controller, world) = makeController(accessGranted: true)
        let window = makeWindow(for: controller)
        let closed = expectation(forNotification: NSWindow.willCloseNotification, object: window)
        click(controller.primaryButton)
        wait(for: [closed], timeout: 1)
        XCTAssertEqual(world.requests, 0)
        XCTAssertEqual(world.settingsOpened, 0)
    }

    // MARK: - Following the permission

    func testNoPollRunsBeforeTheWindowAppears() {
        let (controller, _) = makeController(accessGranted: false)
        XCTAssertNil(controller.accessibilityPermissionsCheckerTimer)
    }

    func testThePollShowsTheGrantAndReportsItOnce() {
        let (controller, world) = makeController(accessGranted: false)

        // A tick without a change changes nothing.
        controller.accessibilityPermissionsChecker(nil)
        XCTAssertEqual(controller.accessState, .missing)
        XCTAssertEqual(world.grantsReported, 0)

        world.accessGranted = true
        controller.accessibilityPermissionsChecker(nil)
        XCTAssertEqual(controller.accessState, .granted)
        XCTAssertEqual(controller.statusLabel.stringValue, "Accessibility access is allowed")
        XCTAssertEqual(controller.primaryButton.title, "Get Started")
        XCTAssertFalse(isShown(controller.stepLabels[0]))
        XCTAssertFalse(isShown(controller.helpButton))
        XCTAssertEqual(world.grantsReported, 1, "the app starts its event handling now")

        controller.accessibilityPermissionsChecker(nil)
        controller.accessibilityPermissionsChecker(nil)
        XCTAssertEqual(world.grantsReported, 1)
    }

    func testTheWindowStaysOpenAfterTheGrantUntilItsButtonIsUsed() {
        let (controller, world) = makeController(accessGranted: false)
        let window = makeWindow(for: controller)
        var closes = 0
        let token = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: nil
        ) { _ in closes += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        world.accessGranted = true
        controller.accessibilityPermissionsChecker(nil)
        XCTAssertEqual(closes, 0)

        click(controller.primaryButton)
        XCTAssertEqual(closes, 1)
    }

    func testReportingAGrantStartsNothingWhenTheAppIsNotWaitingForOne() throws {
        // What the window calls on a grant: the app delegate fires its recovery timer early.
        // Under test there is none (startup side effects are off), so nothing starts.
        let delegate = try XCTUnwrap(NSApp.delegate as? AppDelegate)
        let scrollWasActive = ScrollCore.shared.isActive
        let buttonsWereActive = ButtonCore.shared.isActive
        delegate.accessibilityPermissionWasGranted()
        XCTAssertEqual(ScrollCore.shared.isActive, scrollWasActive)
        XCTAssertEqual(ButtonCore.shared.isActive, buttonsWereActive)
    }

    func testARevokedAccessBringsTheStepsBack() {
        let (controller, world) = makeController(accessGranted: true)
        world.accessGranted = false
        controller.accessibilityPermissionsChecker(nil)
        XCTAssertEqual(controller.accessState, .missing)
        XCTAssertEqual(controller.statusLabel.stringValue, "Accessibility access is not allowed yet")
        XCTAssertEqual(controller.primaryButton.title, "Open Accessibility Settings")
        XCTAssertTrue(isShown(controller.stepLabels[0]))
        XCTAssertTrue(isShown(controller.helpButton))
        XCTAssertEqual(world.grantsReported, 0)

        world.accessGranted = true
        controller.accessibilityPermissionsChecker(nil)
        XCTAssertEqual(world.grantsReported, 1)
    }

    // MARK: - Help

    func testHavingTroubleDisclosesPlainHelp() {
        let (controller, world) = makeController(accessGranted: false)
        XCTAssertEqual(controller.helpButton.title, "Having trouble?")
        XCTAssertTrue(isShown(controller.helpButton))
        XCTAssertFalse(isShown(controller.helpCard))
        XCTAssertFalse(controller.isHelpExpanded)
        let collapsedHeight = controller.view.fittingSize.height

        click(controller.helpButton)
        XCTAssertTrue(controller.isHelpExpanded)
        XCTAssertTrue(isShown(controller.helpCard))
        XCTAssertGreaterThan(controller.view.fittingSize.height, collapsedHeight)
        XCTAssertEqual(controller.helpHeadingLabel.stringValue, "Scrollio is in the list but does not work?")
        let help = controller.helpTextLabel.stringValue
        for word in ["update", "select Scrollio", "minus", "add it again", "Finder"] {
            XCTAssertTrue(help.contains(word), "the help does not mention \"\(word)\"")
        }
        // Text and one button: no picture.
        XCTAssertTrue(allSubviews(of: controller.helpCard).allSatisfy { !($0 is NSImageView) })

        XCTAssertEqual(controller.showInFinderButton.title, "Show Scrollio in Finder")
        click(controller.showInFinderButton)
        XCTAssertEqual(world.reveals, 1)

        click(controller.helpButton)
        XCTAssertFalse(controller.isHelpExpanded)
        XCTAssertFalse(isShown(controller.helpCard))
        XCTAssertEqual(controller.view.fittingSize.height, collapsedHeight, accuracy: 0.5)
    }

    func testTheHelpOpensByItselfOnceWhenTheUserComesBackWithoutAccess() {
        let (controller, _) = makeController(accessGranted: false)

        // Scrollio becomes active when its window opens: that is not "coming back".
        controller.applicationDidBecomeActive(nil)
        XCTAssertFalse(controller.isHelpExpanded)

        click(controller.primaryButton)
        controller.applicationDidBecomeActive(nil)
        XCTAssertTrue(controller.isHelpExpanded)

        // Closed by the user: it does not come back on its own.
        click(controller.helpButton)
        controller.applicationDidBecomeActive(nil)
        XCTAssertFalse(controller.isHelpExpanded)
    }

    func testComingBackWithAccessShowsTheGrantedStateAndNoHelp() {
        let (controller, world) = makeController(accessGranted: false)
        click(controller.primaryButton)
        world.accessGranted = true
        controller.applicationDidBecomeActive(nil)
        XCTAssertEqual(controller.accessState, .granted)
        XCTAssertFalse(isShown(controller.helpCard))
        XCTAssertEqual(world.grantsReported, 1)
    }

    func testTheHelpGoesAwayWithTheGrant() {
        let (controller, world) = makeController(accessGranted: false)
        click(controller.helpButton)
        XCTAssertTrue(isShown(controller.helpCard))
        world.accessGranted = true
        controller.accessibilityPermissionsChecker(nil)
        XCTAssertFalse(isShown(controller.helpCard))
        XCTAssertFalse(isShown(controller.helpButton))
    }

    // MARK: - Layout

    /// Every state the window can be in.
    private func controllersInEveryState() -> [(String, IntroductionViewController)] {
        let missing = makeController(accessGranted: false).0
        let help = makeController(accessGranted: false).0
        help.setHelpExpanded(true, animated: false)
        let granted = makeController(accessGranted: true).0
        let done = makeController(accessGranted: true).0
        done.setManuallyOpened(true)
        return [("missing", missing), ("help", help), ("granted", granted), ("done", done)]
    }

    func testTheViewIsAsWideAsAPreferencesPaneAndFitsItsContent() {
        for (name, controller) in controllersInEveryState() {
            let view = controller.view
            XCTAssertEqual(view.frame.width, PreferencesForm.contentWidth, name)
            XCTAssertEqual(view.frame.size, view.fittingSize, name)
            view.layoutSubtreeIfNeeded()
            XCTAssertFalse(view.hasAmbiguousLayout, name)

            // Nothing that is shown leaves the view or the margins of its card.
            for subview in allSubviews(of: view).filter(isShown) {
                let frame = view.convert(subview.bounds, from: subview)
                XCTAssertTrue(view.bounds.insetBy(dx: -0.5, dy: -0.5).contains(frame), "\(name): \(subview) at \(frame)")
            }
            for centred in [controller.iconView!, controller.titleLabel!, controller.subtitleLabel!, controller.primaryButton!] {
                let frame = view.convert(centred.bounds, from: centred)
                XCTAssertEqual(frame.midX, view.bounds.midX, accuracy: 0.5, name)
            }
        }
    }

    func testNoTextIsCutOff() {
        for (name, controller) in controllersInEveryState() {
            controller.view.layoutSubtreeIfNeeded()
            for field in allSubviews(of: controller.view).compactMap({ $0 as? NSTextField }).filter(isShown) {
                guard let cell = field.cell, !field.stringValue.isEmpty else { continue }
                let needed = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: field.bounds.width, height: .greatestFiniteMagnitude))
                XCTAssertLessThanOrEqual(needed.height, field.bounds.height + 0.5, "\(name): \"\(field.stringValue)\" is cut off")
                XCTAssertLessThanOrEqual(needed.width, field.bounds.width + 0.5, "\(name): \"\(field.stringValue)\" is cut off")
            }
            for button in allSubviews(of: controller.view).compactMap({ $0 as? NSButton }).filter(isShown) {
                XCTAssertGreaterThanOrEqual(button.frame.width, button.intrinsicContentSize.width - 0.5, "\(name): \(button.title)")
            }
        }
    }

    func testTypeSizesAreThoseOfThePreferences() {
        let (controller, _) = makeController(accessGranted: false)
        controller.setHelpExpanded(true, animated: false)
        XCTAssertEqual(controller.accessExplanationLabel.font?.pointSize, PreferencesForm.hintFontSize)
        XCTAssertEqual(controller.statusDetailLabel.font?.pointSize, PreferencesForm.hintFontSize)
        XCTAssertEqual(controller.helpTextLabel.font?.pointSize, PreferencesForm.hintFontSize)
        XCTAssertEqual(controller.accessHeadingLabel.font, PreferencesForm.sectionHeaderFont)
        XCTAssertEqual(controller.helpHeadingLabel.font, PreferencesForm.sectionHeaderFont)
        XCTAssertEqual(controller.stepLabels.first?.font?.pointSize, NSFont.systemFontSize)
        XCTAssertEqual(controller.stepDetailLabels.first?.font?.pointSize, PreferencesForm.hintFontSize)
        // No thin display type and nothing below the small system size.
        for field in allSubviews(of: controller.view).compactMap({ $0 as? NSTextField }) {
            XCTAssertGreaterThanOrEqual(field.font?.pointSize ?? 0, NSFont.smallSystemFontSize, field.stringValue)
            let traits = field.font?.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
            let weight = traits?[.weight] as? CGFloat
            XCTAssertGreaterThanOrEqual(weight ?? 0, NSFont.Weight.regular.rawValue, field.stringValue)
        }
    }

    func testColoursFollowTheAppearance() {
        let (controller, _) = makeController(accessGranted: false)
        // System colours only: they resolve differently in light and dark.
        let dynamic: [NSColor] = [
            controller.titleLabel.textColor!, controller.subtitleLabel.textColor!,
            controller.statusLabel.textColor!, controller.statusDetailLabel.textColor!,
            controller.accessExplanationLabel.textColor!,
        ]
        for colour in dynamic {
            XCTAssertEqual(colour.type, .catalog, "\(colour) is a fixed colour")
        }
        XCTAssertTrue(controller.view is NSVisualEffectView, "the same background as the preferences panes")
        XCTAssertNil(controller.view.appearance, "no fixed light or dark appearance")
    }

    func testTheWindowGrowsDownwardsWithTheHelp() {
        let (controller, world) = makeController(accessGranted: false)
        let window = makeWindow(for: controller)
        let top = window.frame.maxY
        let collapsed = window.frame.height
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).size, controller.view.fittingSize)

        click(controller.helpButton)
        XCTAssertGreaterThan(window.frame.height, collapsed)
        XCTAssertEqual(window.frame.maxY, top, accuracy: 0.5, "the title bar stays where it is")
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).size, controller.view.fittingSize)

        world.accessGranted = true
        controller.accessibilityPermissionsChecker(nil)
        XCTAssertLessThan(window.frame.height, collapsed)
        XCTAssertEqual(window.frame.maxY, top, accuracy: 0.5)
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).size, controller.view.fittingSize)
        XCTAssertFalse(window.isVisible)
    }

    // MARK: - The storyboard shell

    func testTheStoryboardWindowIsAShellAroundTheCodeBuiltView() throws {
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: IntroductionViewController.self))
        let windowController = try XCTUnwrap(
            storyboard.instantiateController(withIdentifier: WINDOW_IDENTIFIER.introductionWindowController) as? IntroductionWindowController
        )
        let window = try XCTUnwrap(windowController.window)
        addTeardownBlock { windowController.close() }
        let controller = try XCTUnwrap(windowController.contentViewController as? IntroductionViewController)

        XCTAssertEqual(window.title, "Welcome to Scrollio")
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertTrue(window.styleMask.contains(.closable))
        XCTAssertTrue(window.styleMask.contains(.miniaturizable))
        XCTAssertFalse(window.styleMask.contains(.resizable), "the content sets the size")
        XCTAssertTrue(window.delegate === windowController)
        XCTAssertFalse(windowController.shouldCascadeWindows)

        XCTAssertEqual(controller.titleLabel.stringValue, "Welcome to Scrollio")
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).size, controller.view.fittingSize)
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).width, PreferencesForm.contentWidth)
        XCTAssertFalse(window.isVisible)
        XCTAssertNil(controller.accessibilityPermissionsCheckerTimer)
        XCTAssertFalse(controller.isManuallyOpened)
    }

    func testNothingOfTheOldWindowIsLeft() {
        let (controller, _) = makeController(accessGranted: false)
        controller.setHelpExpanded(true, animated: false)
        let texts = allSubviews(of: controller.view).compactMap { ($0 as? NSTextField)?.stringValue }
            + allSubviews(of: controller.view).compactMap { ($0 as? NSButton)?.title }
        for old in ["Introducing", "Allow Access", "Not effective", "Authorized"] {
            XCTAssertFalse(texts.contains { $0.localizedCaseInsensitiveContains(old) }, old)
        }
        for name in ["manual-remove", "drag-arrow", "sparkle"] {
            XCTAssertNil(NSImage(named: name), "the picture \(name) is still in the bundle")
        }
    }
}
