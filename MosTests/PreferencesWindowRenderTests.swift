//
//  PreferencesWindowRenderTests.swift
//  MosTests
//
//  Renders the panes of the Preferences window off screen, the way the window shows them:
//  every pane in its 520 pt column of the real window, in its main states, light and dark,
//  an app's page under Apps, and the kit's list (PreferencesListBox) in a key and a
//  non-key window. The appearance is set on the window, so every pane
//  gets it through the window's materials, as on screen (the parent, not the pane: a pane
//  given its appearance directly misses the vibrancy of the material above it). The window
//  is never shown.
//
//  Off screen the behind-window materials draw nothing, so the window colour stands in
//  for them; vibrant text would not be blended by the window server (the panes draw
//  without vibrancy, see PreferencesBackgroundView); and the app is not active, so the
//  controls show their inactive grey instead of the accent colour.
//
//  Only runs when asked to:
//  `TEST_RUNNER_SCROLLIO_SHOTS_DIR=<folder> xcodebuild … test -only-testing:MosTests/PreferencesWindowRenderTests`.
//

import XCTest
@testable import Mos_Debug

final class PreferencesWindowRenderTests: XCTestCase {

    private let app = Bundle(for: PreferencesSplitViewController.self)
    private var savedScroll: OPTIONS_SCROLL_DEFAULT!
    private var savedMouse = LogiMouseSettings.default
    private var savedWheel = LogiWheelSettings.default
    private var savedGesture = MouseGestureSettings.default
    private var savedBindings: [ButtonBinding] = []
    private var savedAllowlist = false
    private var addedApplications: [String] = []
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        guard let folder = ProcessInfo.processInfo.environment["SCROLLIO_SHOTS_DIR"], !folder.isEmpty else {
            throw XCTSkip("set TEST_RUNNER_SCROLLIO_SHOTS_DIR to render the Preferences window")
        }
        directory = URL(fileURLWithPath: folder, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        savedScroll = Options.shared.scroll
        savedMouse = Options.shared.logiMouse
        savedWheel = Options.shared.logiWheel
        savedGesture = Options.shared.gesture
        savedBindings = Options.shared.buttons.binding
        savedAllowlist = Options.shared.application.allowlist
        Options.shared.scroll = OPTIONS_SCROLL_DEFAULT()
    }

    override func tearDown() {
        if let savedScroll {
            Options.shared.scroll = savedScroll
        }
        Options.shared.logiMouse = savedMouse
        Options.shared.logiWheel = savedWheel
        Options.shared.gesture = savedGesture
        Options.shared.buttons.binding = savedBindings
        Options.shared.application.allowlist = savedAllowlist
        for key in addedApplications where Options.shared.application.applications.get(by: key) != nil {
            Options.shared.application.applications.remove(from: key)
        }
        addedApplications = []
        super.tearDown()
    }

    // MARK: - Panes

    func testRenderScrolling() throws {
        for advanced in [false, true] {
            let state = advanced ? "advanced" : "closed"
            Options.shared.scroll = OPTIONS_SCROLL_DEFAULT()
            try renderPane(PANEL_IDENTIFIER.scrolling, name: "scrolling-\(state)", prepare: { preferences in
                (preferences.controller(for: PANEL_IDENTIFIER.scrolling) as? PreferencesScrollingViewController)?
                    .uiStateDefaults = self.uiDefaults(advanced: advanced)
            })
            Options.shared.scroll.smooth = false
            try renderPane(PANEL_IDENTIFIER.scrolling, name: "scrolling-\(state)-smoothing-off", prepare: { preferences in
                (preferences.controller(for: PANEL_IDENTIFIER.scrolling) as? PreferencesScrollingViewController)?
                    .uiStateDefaults = self.uiDefaults(advanced: advanced)
            })
        }
    }

    func testRenderMouse() throws {
        let master4 = MouseDeviceFixtures.mxMaster4()
        Options.shared.logiMouse = .default
        Options.shared.logiWheel = LogiWheelSettings(managedByMos: true)
        try renderMouse([master4], name: "mouse-mx-master-4-managed")
        Options.shared.logiMouse = LogiMouseSettings(pointerDPI: 1600, hapticsOn: true, hapticStrength: 60, pressForce: 5167)
        try renderMouse([master4], name: "mouse-mx-master-4-managed-haptics-on")
        Options.shared.logiMouse = .default
        Options.shared.logiWheel = .default
        try renderMouse([master4], name: "mouse-mx-master-4-not-managed")
        try renderMouse([MouseDeviceFixtures.mxMaster3S()], name: "mouse-mx-master-3s")
        try renderMouse([], name: "mouse-no-mouse")
    }

    /// The modes with and without a Logitech mouse, no gesture button, and the MX Master 4
    /// with its haptics off because they were switched off under Mouse (the line under the
    /// Logitech box with "Open Mouse").
    func testRenderGestures() throws {
        let master4 = MouseGestureDeviceSupport(deviceTracking: true, haptics: true)
        let master4HapticsOff = MouseGestureDeviceSupport(deviceTracking: true, haptics: true, hapticsOffOnMouse: true)
        let cases: [(name: String, mode: MouseGestureMode, support: MouseGestureDeviceSupport, bound: Bool, hapticsOnUnderMouse: Bool?)] = [
            ("gestures-discrete-no-logitech", .discrete, .none, true, nil),
            ("gestures-discrete-mx-master-4", .discrete, master4, true, nil),
            ("gestures-discrete-mx-master-4-haptics-off", .discrete, master4HapticsOff, true, false),
            ("gestures-follow-no-logitech", .interactive, .none, true, nil),
            ("gestures-follow-mx-master-4", .interactive, master4, true, nil),
            ("gestures-no-gesture-button", .discrete, .none, false, nil),
        ]
        for item in cases {
            var gesture = MouseGestureSettings.default
            gesture.mode = item.mode
            gesture.deviceTracking = item.support.deviceTracking
            Options.shared.gesture = gesture
            Options.shared.logiMouse = LogiMouseSettings(hapticsOn: item.hapticsOnUnderMouse)
            // A pane of its own: "Follow the hand" is available whatever this Mac says.
            try renderPane(GesturesPreferencesViewController.tabIdentifier, name: item.name, replacement: {
                let gestures = GesturesPreferencesViewController(isInteractiveAvailable: { true })
                gestures.deviceSource = MouseGestureDeviceSource(support: { item.support }, refresh: {})
                gestures.bindingSummary = {
                    MouseGestureBindingSummary(
                        hasGestureButton: item.bound,
                        hasLogitechGestureButton: item.support.deviceTracking,
                        buttonTitles: item.bound ? (item.support.deviceTracking ? ["Gesture button"] : ["Back button"]) : []
                    )
                }
                return gestures
            }, afterLoad: { controller in
                guard let gestures = controller as? GesturesPreferencesViewController else { return }
                gestures.previewView.prefersReducedMotion = { true }
                gestures.previewView.reduceMotionDidChange()
            })
        }
    }

    /// Access allowed and not, the login item waiting for approval, "Advanced" open. The
    /// login item and the permission are fixed, nothing is asked of the system.
    func testRenderGeneral() throws {
        final class FixedLoginItem: LoginItemService {
            let status: LoginItemStatus
            init(_ status: LoginItemStatus) { self.status = status }
            func register() throws {}
            func unregister() throws {}
            func openSystemSettings() {}
        }
        let savedAutoLaunch = Options.shared.general.autoLaunch
        defer {
            LoginItem.service = InertLoginItemService()
            Options.shared.general.autoLaunch = savedAutoLaunch
            LoginItem.service = LoginItem.defaultService
        }
        let cases: [(name: String, access: Bool, login: LoginItemStatus, advanced: Bool, paused: Bool)] = [
            ("general", true, .enabled, false, false),
            ("general-no-access", false, .notRegistered, false, false),
            ("general-login-approval", true, .requiresApproval, false, false),
            ("general-advanced", true, .enabled, true, false),
            ("general-paused", true, .enabled, false, true),
        ]
        for item in cases {
            LoginItem.service = FixedLoginItem(item.login)
            let suite = "ScrollioTests.window-render.general.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defaults.set(item.advanced, forKey: PreferencesGeneralViewController.advancedExpandedDefaultsKey)
            addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
            try renderPane(PANEL_IDENTIFIER.general, name: item.name, prepare: { preferences in
                guard let general = preferences.controller(for: PANEL_IDENTIFIER.general)
                    as? PreferencesGeneralViewController else { return }
                general.isAccessGranted = { item.access }
                general.isPaused = { item.paused }
                general.resume = {}
                general.isMenuBarIconHidden = { false }
                general.uiStateDefaults = defaults
            }, afterLoad: { controller in
                // The window calls viewWillAppear, which reads the login item.
                controller.viewWillAppear()
            })
        }
    }

    /// The Buttons pane: empty; with buttons; a row pointed at (its button lit); a row
    /// selected; recording; and rows with problems while the mice are asked.
    func testRenderButtons() throws {
        let option = UInt(CGEventFlags.maskAlternate.rawValue)
        let controlOption = UInt(CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue)
        let bindings = [
            binding(3, SystemShortcut.mouseGestureNavigation.identifier),
            binding(4, SystemShortcut.mosScrollDash.identifier),
            binding(2, SystemShortcut.missionControl.identifier, modifiers: option),
            binding(5, SystemShortcut.copy.identifier),
            binding(6, ""),
            ButtonBinding(
                triggerEvent: RecordedEvent(type: .keyboard, code: 40, modifiers: controlOption, deviceFilter: nil),
                systemShortcutName: "custom::21:\(UInt64(CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue))"
            ),
        ]
        let plain = ButtonsDeviceSource(captureStatus: { _ in .normal }, deviceName: { "MX Master 4" }, isBusy: { false }, refresh: {}, warnBluetoothButton: { _ in })
        let none = ButtonsDeviceSource(captureStatus: { _ in .normal }, deviceName: { nil }, isBusy: { false }, refresh: {}, warnBluetoothButton: { _ in })

        Options.shared.buttons.binding = []
        try renderButtons(name: "buttons-empty", source: none)

        Options.shared.buttons.binding = bindings
        try renderButtons(name: "buttons-bindings", source: plain)
        try renderButtons(name: "buttons-hovered", source: plain) { buttons in
            self.hover(buttons, rowAt: 0)
        }
        try renderButtons(name: "buttons-selected", source: plain) { buttons in
            buttons.list.select(buttons.rows[2].id)
        }
        try renderButtons(name: "buttons-recording", source: plain) { buttons in
            buttons.onRecordingStarted(KeyRecorder())
        }

        // A Logitech mouse that reports trouble, while the pane asks it again.
        Options.shared.buttons.binding = [
            binding(1000, SystemShortcut.mouseGestureNavigation.identifier),
            binding(1006, SystemShortcut.navigateBack.identifier),
            binding(1001, SystemShortcut.logiSmartShiftToggle.identifier),
            binding(5, SystemShortcut.mosScrollDash.identifier),
        ]
        let troubled = ButtonsDeviceSource(
            captureStatus: { code in
                switch code {
                case 1000: return .conflict(.foreignDivert)
                case 1006: return .standardMouseAliasAvailable
                case 1001: return .bleHIDPPUnstable
                default: return .normal
                }
            },
            deviceName: { "MX Master 4" }, isBusy: { true }, refresh: {}, warnBluetoothButton: { _ in }
        )
        try renderButtons(name: "buttons-problems", source: troubled, scrollKeys: [ScrollHotkey(type: .mouse, code: 5)]) { buttons in
            buttons.list.select(buttons.rows[1].id)
        }

        // A Logitech Back button next to the standard one, and the MX Master 4's thumb
        // panel selected: the card lights the thumb panel.
        Options.shared.buttons.binding = [
            binding(3, SystemShortcut.navigateBack.identifier),
            binding(1006, SystemShortcut.mouseGestureNavigation.identifier),
            binding(2000 + 0x01A0, SystemShortcut.missionControl.identifier),
        ]
        try renderButtons(name: "buttons-twins-thumb-panel", source: plain) { buttons in
            buttons.list.select(buttons.rows[2].id)
        }
        try renderMouseParts()
        try renderRowPictures()
    }

    /// Which button is which: the owner's MX Master 4 over Bluetooth (Gesture Navigation on
    /// Button 6, a shortcut on Button 5, a screenshot on the mode shift button), a row of
    /// every part the drawing knows and a key, numbered buttons, and the card's answer
    /// after "+" ("That's …").
    func testRenderButtonIdentity() throws {
        let plain = ButtonsDeviceSource(captureStatus: { _ in .normal }, deviceName: { "MX Master 4" }, isBusy: { false }, refresh: {}, warnBluetoothButton: { _ in })
        let optionCommand = UInt64(CGEventFlags.maskCommand.rawValue | CGEventFlags.maskAlternate.rawValue)
        Options.shared.buttons.binding = [
            binding(6, SystemShortcut.mouseGestureNavigation.identifier),
            binding(5, "custom::17:\(optionCommand)"),
            binding(1001, SystemShortcut.screenshotSelection.identifier),
        ]
        try renderButtons(name: "buttons-owner", source: plain)
        try renderButtons(name: "buttons-owner-hovered-button-6", source: plain) { buttons in
            self.hover(buttons, rowAt: 0)
        }
        try renderButtons(name: "buttons-owner-selected-button-5", source: plain) { buttons in
            buttons.list.select(buttons.rows[1].id)
        }
        try renderButtons(name: "buttons-owner-thats-button-6", source: plain) { buttons in
            self.answer(buttons, code: 6)
        }
        try renderButtons(name: "buttons-owner-thats-mode-shift", source: plain) { buttons in
            self.answer(buttons, code: 1001)
        }

        let controlOption = UInt(CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue)
        Options.shared.buttons.binding = [
            binding(0, SystemShortcut.copy.identifier, modifiers: UInt(CGEventFlags.maskCommand.rawValue)),
            binding(1, SystemShortcut.paste.identifier, modifiers: UInt(CGEventFlags.maskCommand.rawValue)),
            binding(2, SystemShortcut.missionControl.identifier),
            binding(3, SystemShortcut.navigateBack.identifier),
            binding(4, SystemShortcut.navigateForward.identifier),
            binding(1000, SystemShortcut.mouseGestureNavigation.identifier),
            binding(1001, SystemShortcut.logiSmartShiftToggle.identifier),
            binding(2000 + 0x01A0, SystemShortcut.missionControl.identifier, modifiers: UInt(CGEventFlags.maskAlternate.rawValue)),
            ButtonBinding(
                triggerEvent: RecordedEvent(type: .keyboard, code: 40, modifiers: controlOption, deviceFilter: nil),
                systemShortcutName: SystemShortcut.screenshotSelection.identifier
            ),
        ]
        try renderButtons(name: "buttons-every-part", source: plain) { buttons in
            buttons.list.select(buttons.rows[3].id)
        }

        Options.shared.buttons.binding = [
            binding(5, SystemShortcut.copy.identifier),
            binding(6, ""),
            binding(7, SystemShortcut.paste.identifier),
            binding(12, SystemShortcut.missionControl.identifier),
            binding(2000 + 0x005B, SystemShortcut.navigateBack.identifier),
        ]
        try renderButtons(name: "buttons-numbered-hovered", source: plain) { buttons in
            self.hover(buttons, rowAt: 3)
        }
    }

    /// "Which button is this?" on the owner's bindings (Gesture Navigation on Button 6, a
    /// shortcut on Button 5, a screenshot on the mode shift button): before, with the
    /// picture under the pointer, and after Button 6 was said to be the gesture button and
    /// Button 5 the thumb panel (the rows, the card, "That's …", the Gestures pane's line),
    /// and the menu's items. An NSMenu draws only on screen: its items are drawn here from
    /// the menu the pane builds, in the menu's order, as a stand-in.
    func testRenderButtonPlace() throws {
        let plain = ButtonsDeviceSource(captureStatus: { _ in .normal }, deviceName: { "MX Master 4" }, isBusy: { false }, refresh: {}, warnBluetoothButton: { _ in })
        let optionCommand = UInt64(CGEventFlags.maskCommand.rawValue | CGEventFlags.maskAlternate.rawValue)
        let before = [
            binding(6, SystemShortcut.mouseGestureNavigation.identifier),
            binding(5, "custom::17:\(optionCommand)"),
            binding(1001, SystemShortcut.screenshotSelection.identifier),
        ]
        Options.shared.buttons.binding = before
        try renderButtons(name: "button-place-before", source: plain)
        try renderButtons(name: "button-place-before-hovered-button-6", source: plain) { buttons in
            self.hover(buttons, rowAt: 0)
        }
        try renderButtons(name: "button-place-before-picture-pointed", source: plain) { buttons in
            buttons.list.select(buttons.rows[1].id)
            buttons.rows[1].placeButton.isPointerInside = true
            buttons.rows[0].placeButton.isPointerInside = true
        }
        try renderPlaceMenu(name: "button-place-menu-before", rowAt: 0)

        let after = before.enumerated().map { index, binding -> ButtonBinding in
            let part: PlacedMousePart? = [0: .gestureButton, 1: .thumbPanel][index]
            return part.map { binding.replacingTriggerEvent(binding.triggerEvent.placed(at: $0)) } ?? binding
        }
        Options.shared.buttons.binding = after
        try renderButtons(name: "button-place-after", source: plain)
        try renderButtons(name: "button-place-after-selected-button-6", source: plain) { buttons in
            buttons.list.select(buttons.rows[0].id)
        }
        try renderButtons(name: "button-place-after-hovered-button-5", source: plain) { buttons in
            self.hover(buttons, rowAt: 1)
        }
        try renderButtons(name: "button-place-after-thats-button-6", source: plain) { buttons in
            self.answer(buttons, code: 6)
        }
        try renderPlaceMenu(name: "button-place-menu-after", rowAt: 0)
        var gesture = MouseGestureSettings.default
        gesture.mode = .discrete
        Options.shared.gesture = gesture
        try renderPane(GesturesPreferencesViewController.tabIdentifier, name: "button-place-after-gestures", replacement: {
            let gestures = GesturesPreferencesViewController(isInteractiveAvailable: { true })
            gestures.deviceSource = MouseGestureDeviceSource(support: { MouseGestureDeviceSupport(deviceTracking: true, haptics: true) }, refresh: {})
            gestures.bindingSummary = { .current }
            return gestures
        }, afterLoad: { controller in
            guard let gestures = controller as? GesturesPreferencesViewController else { return }
            gestures.previewView.prefersReducedMotion = { true }
            gestures.previewView.reduceMotionDidChange()
        })
    }

    /// The items of "Which Button Is This?" for the row at `index` of the stored bindings,
    /// as the pane builds the menu: drawn by this test in the menu's order (the section
    /// title, a tick, each picture, the title, the mark at the end, the separator), on the
    /// window colour. AppKit's menu itself cannot be drawn off screen.
    private func renderPlaceMenu(name: String, rowAt index: Int) throws {
        let buttons = PreferencesButtonsViewController()
        buttons.deviceSource = ButtonsDeviceSource(captureStatus: { _ in .normal }, deviceName: { nil }, isBusy: { false }, refresh: {}, warnBluetoothButton: { _ in })
        buttons.presentPlaceMenu = { _, _ in }
        _ = buttons.view
        let menu = try XCTUnwrap(buttons.placeMenu(for: buttons.rows[index].binding.id))
        let width: CGFloat = 300
        let heights = menu.items.map { item -> CGFloat in
            if item.isSeparatorItem { return 11 }
            if item.isSectionHeader { return 22 }
            return 30
        }
        let bounds = NSRect(x: 0, y: 0, width: width, height: heights.reduce(10, +))
        for (suffix, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            let scale: CGFloat = 2
            let canvas = try XCTUnwrap(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * scale), pixelsHigh: Int(bounds.height * scale),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ))
            canvas.size = bounds.size
            let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: canvas))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
            context.cgContext.translateBy(x: 0, y: bounds.height)
            context.cgContext.scaleBy(x: 1, y: -1)
            appearance.performAsCurrentDrawingAppearance {
                NSColor.windowBackgroundColor.setFill()
                NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
                NSColor.separatorColor.setStroke()
                NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10).stroke()
                var y: CGFloat = 5
                let font = NSFont.menuFont(ofSize: 0)
                for (item, height) in zip(menu.items, heights) {
                    defer { y += height }
                    if item.isSeparatorItem {
                        NSColor.separatorColor.setFill()
                        NSRect(x: 14, y: y + 5, width: width - 28, height: 1).fill()
                        continue
                    }
                    let isHeader = item.isSectionHeader
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: isHeader ? NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold) : font,
                        .foregroundColor: isHeader ? NSColor.secondaryLabelColor : NSColor.labelColor,
                    ]
                    let title = NSAttributedString(string: item.title, attributes: attributes)
                    var x: CGFloat = 14
                    if !isHeader {
                        if item.state == .on {
                            NSAttributedString(string: "✓", attributes: [.font: font, .foregroundColor: NSColor.labelColor])
                                .draw(at: NSPoint(x: x, y: y + (height - font.boundingRectForFont.height) / 2 + 1))
                        }
                        x += 16
                        if let image = item.image {
                            image.draw(in: NSRect(x: x, y: y + (height - image.size.height) / 2, width: image.size.width, height: image.size.height),
                                       from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                            x += image.size.width + 6
                        }
                    }
                    title.draw(at: NSPoint(x: x, y: y + (height - title.size().height) / 2))
                    if let mark = item.badge?.stringValue {
                        let badge = NSAttributedString(string: mark, attributes: [
                            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.secondaryLabelColor,
                        ])
                        badge.draw(at: NSPoint(x: width - 14 - badge.size().width, y: y + (height - badge.size().height) / 2))
                    }
                }
            }
            NSGraphicsContext.restoreGraphicsState()
            let png = try XCTUnwrap(canvas.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent("\(name)-\(suffix).png"))
        }
    }

    /// "+" waits, then a listed button is pressed: the recorder is stubbed, nothing is
    /// recorded from the system.
    private func answer(_ buttons: PreferencesButtonsViewController, code: UInt16) {
        let recorder = KeyRecorder()
        buttons.onRecordingStarted(recorder)
        let event = InputEvent(type: .mouse, code: code, modifiers: [], phase: .down, source: .hidPP, device: nil)
        buttons.onEventRecorded(recorder, didRecordEvent: event, isDuplicate: true)
    }

    /// The rows' pictures: each part lit, buttons the drawing cannot show (with and
    /// without a number) and a key, on the list's box and on the selection, at their size
    /// on a Retina screen and at six times that.
    private func renderRowPictures() throws {
        let pictures: [ButtonTriggerPicture] = ButtonsMousePart.allCases.map { .mouse(part: $0, number: nil) }
            + [.mouse(part: nil, number: 5), .mouse(part: nil, number: 6), .mouse(part: nil, number: 12), .mouse(part: nil, number: nil), .key]
        let cell: CGFloat = 32
        let size = ButtonsMouseMiniature.size
        let bounds = NSRect(x: 0, y: 0, width: cell * CGFloat(pictures.count), height: cell * 2)
        for (suffix, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            for scale in [CGFloat(2), 6] {
                let canvas = try XCTUnwrap(NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * scale), pixelsHigh: Int(bounds.height * scale),
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
                ))
                canvas.size = bounds.size
                let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: canvas))
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = context
                appearance.performAsCurrentDrawingAppearance {
                    NSColor.windowBackgroundColor.setFill()
                    bounds.fill()
                    PreferencesGroupedForm.boxFillColor.setFill()
                    NSRect(x: 0, y: cell, width: bounds.width, height: cell).fill()
                    NSColor.controlAccentColor.setFill()
                    NSRect(x: 0, y: 0, width: bounds.width, height: cell).fill()
                    for (index, picture) in pictures.enumerated() {
                        for (row, highlighted) in [(1, false), (0, true)] {
                            let frame = NSRect(
                                x: CGFloat(index) * cell + (cell - size.width) / 2,
                                y: CGFloat(row) * cell + (cell - size.height) / 2,
                                width: size.width, height: size.height
                            )
                            ButtonsMouseMiniature.image(for: picture, highlighted: highlighted).draw(in: frame)
                        }
                    }
                }
                NSGraphicsContext.restoreGraphicsState()
                let png = try XCTUnwrap(canvas.representation(using: .png, properties: [:]))
                try png.write(to: directory.appendingPathComponent("buttons-row-pictures-\(Int(scale))x-\(suffix).png"))
            }
        }
    }

    /// The mouse of the Buttons pane with nothing lit, then each part lit, side by side on
    /// the card's colour, at four times the size.
    private func renderMouseParts() throws {
        let size = ButtonsMouseArtworkView.size
        let parts: [ButtonsMousePart?] = [nil] + ButtonsMousePart.allCases
        let strip = NSView(frame: NSRect(x: 0, y: 0, width: size.width * CGFloat(parts.count), height: size.height))
        strip.wantsLayer = true
        for (index, part) in parts.enumerated() {
            let artwork = ButtonsMouseArtworkView()
            artwork.frame.origin = NSPoint(x: size.width * CGFloat(index), y: 0)
            artwork.setEmphasis(part, animated: false)
            strip.addSubview(artwork)
        }
        for (suffix, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            strip.appearance = appearance
            strip.display()
            let rep = try XCTUnwrap(strip.bitmapImageRepForCachingDisplay(in: strip.bounds))
            strip.cacheDisplay(in: strip.bounds, to: rep)
            let scale: CGFloat = 4
            let canvas = try XCTUnwrap(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(strip.bounds.width * scale), pixelsHigh: Int(strip.bounds.height * scale),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ))
            canvas.size = strip.bounds.size
            let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: canvas))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            appearance.performAsCurrentDrawingAppearance {
                ScrollPreviewPalette.cardFill.setFill()
                strip.bounds.fill()
            }
            NSGraphicsContext.restoreGraphicsState()
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            appearance.performAsCurrentDrawingAppearance {
                strip.displayIgnoringOpacity(strip.bounds, in: context)
            }
            NSGraphicsContext.restoreGraphicsState()
            let png = try XCTUnwrap(canvas.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent("buttons-mouse-parts-\(suffix).png"))
        }
    }

    private func renderButtons(
        name: String,
        source: ButtonsDeviceSource,
        scrollKeys: [ScrollHotkey] = [],
        key: Bool = true,
        windowHeight: CGFloat? = nil,
        then change: @escaping (PreferencesButtonsViewController) -> Void = { _ in }
    ) throws {
        try renderPane(PANEL_IDENTIFIER.buttons, name: name, key: key, windowHeight: windowHeight, prepare: { preferences in
            guard let buttons = preferences.controller(for: PANEL_IDENTIFIER.buttons) as? PreferencesButtonsViewController else { return }
            buttons.deviceSource = source
            buttons.scrollHoldKeys = { scrollKeys }
            buttons.startRecording = { _ in }
            buttons.openActionMenu = { _ in }
            buttons.presentPlaceMenu = { _, _ in }
        }, afterLoad: { controller in
            guard let buttons = controller as? PreferencesButtonsViewController else { return }
            buttons.headerView.prefersReducedMotion = { true }
            buttons.viewWillAppear()
            buttons.view.layoutSubtreeIfNeeded()
            change(buttons)
        })
    }

    /// Points at a row: a mouse-moved event handed to the list, never posted.
    private func hover(_ buttons: PreferencesButtonsViewController, rowAt index: Int) {
        guard let window = buttons.view.window else { return }
        window.contentView?.layoutSubtreeIfNeeded()
        let row = buttons.rows[index]
        let point = row.convert(NSPoint(x: row.bounds.midX, y: row.bounds.midY), to: nil)
        guard let event = NSEvent.mouseEvent(
            with: .mouseMoved, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0
        ) else { return }
        buttons.list.mouseMoved(with: event)
    }

    /// The empty list, and a list with apps (one with settings of its own, selected) and the
    /// switch on, in a key and a non-key window.
    func testRenderApps() throws {
        let stored = Options.shared.application.applications
        addTeardownBlock { Options.shared.application.applications = stored }
        Options.shared.application.applications = EnhanceArray<Application>(matchKey: "path")
        Options.shared.application.allowlist = false
        try renderPane(PANEL_IDENTIFIER.application, name: "apps-empty")

        let calculator = Application(path: "/System/Applications/Calculator.app")
        calculator.inherit = false
        let textEdit = Application(path: "/System/Applications/TextEdit.app/Contents/MacOS/TextEdit")
        let safari = Application(path: "/Applications/Safari.app")
        Options.shared.application.applications = EnhanceArray<Application>(withArray: [calculator, textEdit, safari], matchKey: "path")
        Options.shared.application.allowlist = true
        let selectCalculator: (NSViewController) -> Void = { controller in
            (controller as? PreferencesApplicationViewController)?.list.select(calculator.path)
        }
        try renderPane(PANEL_IDENTIFIER.application, name: "apps-with-apps", afterLoad: selectCalculator)
        try renderPane(PANEL_IDENTIFIER.application, name: "apps-with-apps-not-key", key: false, afterLoad: selectCalculator)
    }

    /// An app's page: with settings of its own and using the Scrolling settings, "Advanced"
    /// closed and open, as the pane shows it in place of the list.
    func testRenderAppPage() throws {
        let stored = Options.shared.application.applications
        addTeardownBlock { Options.shared.application.applications = stored }
        for advanced in [false, true] {
            for inherit in [false, true] {
                let calculator = Application(path: "/System/Applications/Calculator.app")
                calculator.inherit = inherit
                calculator.scroll.duration = ScrollFeel.direct.duration
                calculator.scroll.speed = 4.5
                Options.shared.application.applications = EnhanceArray<Application>(withArray: [calculator], matchKey: "path")
                let defaults = uiDefaults(advanced: advanced)
                let name = "app-page-\(inherit ? "inherit" : "own")-\(advanced ? "advanced" : "closed")"
                try renderPane(PANEL_IDENTIFIER.application, name: name, prepare: { preferences in
                    (preferences.controller(for: PANEL_IDENTIFIER.application) as? PreferencesApplicationViewController)?
                        .uiStateDefaults = defaults
                }, afterLoad: { controller in
                    (controller as? PreferencesApplicationViewController)?.openApplication(withID: calculator.path)
                })
            }
        }
    }

    // MARK: - States for the final visual check

    /// The tallest panes at the window's minimum height: the column as the window shows it.
    func testRenderMinimumHeight() throws {
        let minimum = PreferencesWindowLayout.minimumContentHeight
        Options.shared.scroll = OPTIONS_SCROLL_DEFAULT()
        try renderPane(PANEL_IDENTIFIER.scrolling, name: "min-scrolling-advanced", windowHeight: minimum, prepare: { preferences in
            (preferences.controller(for: PANEL_IDENTIFIER.scrolling) as? PreferencesScrollingViewController)?
                .uiStateDefaults = self.uiDefaults(advanced: true)
        })
        Options.shared.logiMouse = .default
        Options.shared.logiWheel = LogiWheelSettings(managedByMos: true)
        try renderMouse([MouseDeviceFixtures.mxMaster4()], name: "min-mouse-managed", windowHeight: minimum)
        Options.shared.logiWheel = .default
        Options.shared.buttons.binding = [
            binding(3, SystemShortcut.mouseGestureNavigation.identifier),
            binding(4, SystemShortcut.mosScrollDash.identifier),
            binding(2, SystemShortcut.missionControl.identifier),
            binding(5, SystemShortcut.copy.identifier),
            binding(6, ""),
        ]
        let plain = ButtonsDeviceSource(captureStatus: { _ in .normal }, deviceName: { "MX Master 4" }, isBusy: { false }, refresh: {}, warnBluetoothButton: { _ in })
        try renderButtons(name: "min-buttons", source: plain, windowHeight: minimum)
        var gesture = MouseGestureSettings.default
        gesture.mode = .interactive
        gesture.deviceTracking = true
        Options.shared.gesture = gesture
        try renderPane(GesturesPreferencesViewController.tabIdentifier, name: "min-gestures-follow", windowHeight: minimum, replacement: {
            let gestures = GesturesPreferencesViewController(isInteractiveAvailable: { true })
            gestures.deviceSource = MouseGestureDeviceSource(support: { MouseGestureDeviceSupport(deviceTracking: true, haptics: true) }, refresh: {})
            gestures.bindingSummary = {
                MouseGestureBindingSummary(hasGestureButton: true, hasLogitechGestureButton: true, buttonTitles: ["Gesture button"])
            }
            return gestures
        }, afterLoad: { controller in
            guard let gestures = controller as? GesturesPreferencesViewController else { return }
            gestures.previewView.prefersReducedMotion = { true }
            gestures.previewView.reduceMotionDidChange()
        })
        let stored = Options.shared.application.applications
        addTeardownBlock { Options.shared.application.applications = stored }
        let calculator = Application(path: "/System/Applications/Calculator.app")
        calculator.inherit = false
        Options.shared.application.applications = EnhanceArray<Application>(withArray: [calculator], matchKey: "path")
        let defaults = uiDefaults(advanced: true)
        try renderPane(PANEL_IDENTIFIER.application, name: "min-app-page-own-advanced", windowHeight: minimum, prepare: { preferences in
            (preferences.controller(for: PANEL_IDENTIFIER.application) as? PreferencesApplicationViewController)?
                .uiStateDefaults = defaults
        }, afterLoad: { controller in
            (controller as? PreferencesApplicationViewController)?.openApplication(withID: calculator.path)
        })
    }

    /// Long names: a Logitech control with a long name, every modifier, a long action, a
    /// long mouse name, a problem note on each row; a selection in a window that is not key.
    func testRenderButtonsLongNames() throws {
        let all = UInt(CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue
            | CGEventFlags.maskShift.rawValue | CGEventFlags.maskCommand.rawValue)
        Options.shared.buttons.binding = [
            binding(2214, SystemShortcut.mosScrollDash.identifier),
            binding(2253, SystemShortcut.logiDPICycleUp.identifier),
            binding(4, SystemShortcut.missionControl.identifier, modifiers: all),
            binding(1001, SystemShortcut.logiSmartShiftToggle.identifier),
            binding(1000, ""),
        ]
        let source = ButtonsDeviceSource(
            captureStatus: { code in
                switch code {
                case 2214: return .contended
                case 2253: return .conflict(.foreignDivert)
                case 1001: return .bleHIDPPUnstable
                default: return .normal
                }
            },
            deviceName: { "MX Master 3S for Mac with a very long name" }, isBusy: { false }, refresh: {}, warnBluetoothButton: { _ in }
        )
        try renderButtons(name: "buttons-long-names", source: source, scrollKeys: [ScrollHotkey(type: .mouse, code: 4)])
        try renderButtons(name: "buttons-long-names-selected", source: source, scrollKeys: [ScrollHotkey(type: .mouse, code: 4)]) { buttons in
            buttons.list.select(buttons.rows[0].id)
        }
        Options.shared.buttons.binding = [
            binding(3, SystemShortcut.mouseGestureNavigation.identifier),
            binding(4, SystemShortcut.mosScrollDash.identifier),
            binding(5, SystemShortcut.copy.identifier),
        ]
        let plain = ButtonsDeviceSource(captureStatus: { _ in .normal }, deviceName: { nil }, isBusy: { false }, refresh: {}, warnBluetoothButton: { _ in })
        try renderButtons(name: "buttons-selected-not-key", source: plain, key: false) { buttons in
            buttons.list.select(buttons.rows[1].id)
        }
    }

    /// The ⓘ popover of each kind of problem, in the popover's material.
    func testRenderButtonProblemPopovers() throws {
        let kinds: [(String, ButtonCapturePresentationStatus?)] = [
            ("conflict", .conflict(.foreignDivert)),
            ("contended", .contended),
            ("bluetooth", .bleHIDPPUnstable),
            ("standard-button", .standardMouseAliasAvailable),
            ("scroll-key", nil),
        ]
        for (name, status) in kinds {
            let note: ButtonRowNote?
            if let status {
                note = ButtonRowNote.make(for: binding(1006, SystemShortcut.copy.identifier), captureStatus: status, scrollHoldKeys: [], standardButtonName: "Back button")
            } else {
                note = ButtonRowNote.make(for: binding(4, SystemShortcut.copy.identifier), captureStatus: .normal, scrollHoldKeys: [ScrollHotkey(type: .mouse, code: 4)])
            }
            let controller = ButtonProblemPopoverController(note: try XCTUnwrap(note))
            let view = controller.view
            view.setFrameSize(view.fittingSize)
            try renderInPopoverMaterial(view, name: "buttons-popover-\(name)")
        }
    }

    /// Apps with long names, and the page of one of them.
    func testRenderAppsLongNames() throws {
        let stored = Options.shared.application.applications
        addTeardownBlock { Options.shared.application.applications = stored }
        let long = Application(path: "/Applications/Microsoft Visual Studio Code Insiders Edition With A Long Name.app")
        long.displayName = "Microsoft Visual Studio Code Insiders Edition With A Very Long Name"
        long.inherit = false
        let calculator = Application(path: "/System/Applications/Calculator.app")
        Options.shared.application.applications = EnhanceArray<Application>(withArray: [long, calculator], matchKey: "path")
        Options.shared.application.allowlist = false
        try renderPane(PANEL_IDENTIFIER.application, name: "apps-long-names", afterLoad: { controller in
            (controller as? PreferencesApplicationViewController)?.list.select(long.path)
        })
        try renderPane(PANEL_IDENTIFIER.application, name: "app-page-long-name", afterLoad: { controller in
            (controller as? PreferencesApplicationViewController)?.openApplication(withID: long.path)
        })
    }

    // MARK: - Kit

    /// The kit's list in a pane: four rows (symbol and app icons, explanations, a pull-down,
    /// a chevron, one selected) with a note under the box, and an empty list. The selection
    /// in a key window and in one that is not.
    func testRenderListBox() throws {
        for key in [true, false] {
            let state = key ? "key" : "not-key"
            try renderPane(PANEL_IDENTIFIER.general, name: "list-\(state)", key: key, replacement: {
                ListRenderController(empty: false)
            })
        }
        try renderPane(PANEL_IDENTIFIER.general, name: "list-empty", replacement: {
            ListRenderController(empty: true)
        })
    }

    // MARK: - Probes

    /// Writes how the disabled texts resolve on screen: the appearance they get, the colour,
    /// and whether the window server blends them (vibrancy). Read by hand.
    func testWriteColourProbe() throws {
        var lines: [String] = []
        var gesture = MouseGestureSettings.default
        gesture.mode = .interactive
        Options.shared.gesture = gesture
        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            let (window, preferences) = try makeWindow(appearance: appearanceName)
            let gestures = GesturesPreferencesViewController(isInteractiveAvailable: { true })
            gestures.deviceSource = MouseGestureDeviceSource(support: { .none }, refresh: {})
            preferences.host.show(gestures)
            window.contentView?.layoutSubtreeIfNeeded()
            let left = gestures.directionRows[MouseGestureSettingsControls.Slot.left.rawValue]
            let up = gestures.directionRows[MouseGestureSettingsControls.Slot.up.rawValue]
            for (label, view) in [("disabled title", left.titleLabel), ("enabled title", up.titleLabel)] as [(String, NSTextField)] {
                lines.append("\(appearanceName.rawValue) \(label): appearance \(view.effectiveAppearance.name.rawValue), "
                    + "allowsVibrancy \(view.allowsVibrancy), colour \(describe(view.textColor, in: view.effectiveAppearance))")
            }
            let box = try XCTUnwrap(left.superview?.superview as? PreferencesGroupBox)
            lines.append("\(appearanceName.rawValue) box fill: \(describe(PreferencesGroupedForm.boxFillColor, in: box.effectiveAppearance)), allowsVibrancy \(box.allowsVibrancy)")
            let controls: [(String, NSView)] = [
                ("switch", gestures.controls.invertToggle),
                ("slider", gestures.trackingSpeedSlider),
                ("segmented", gestures.controls.modeControl),
                ("pop-up", gestures.controls.actionPopUp(for: .left)),
                ("note", gestures.logitechNeedsLabel),
            ]
            for (label, view) in controls {
                lines.append("\(appearanceName.rawValue) \(label): \(type(of: view)) allowsVibrancy \(view.allowsVibrancy) enabled \((view as? NSControl)?.isEnabled ?? true)")
            }
            lines.append("\(appearanceName.rawValue) window key \(window.isKeyWindow) main \(window.isMainWindow)")
            for name in ["labelColor", "secondaryLabelColor", "tertiaryLabelColor", "quaternaryLabelColor", "disabledControlTextColor"] {
                let color = NSColor.value(forKey: name) as? NSColor
                lines.append("\(appearanceName.rawValue) \(name): vibrant \(describe(color, in: left.effectiveAppearance)) plain \(describe(color, in: NSAppearance(named: appearanceName)!))")
            }
        }
        try lines.joined(separator: "\n").write(to: directory.appendingPathComponent("colour-probe.txt"), atomically: true, encoding: .utf8)
    }

    // MARK: - Helpers

    private func uiDefaults(advanced: Bool) -> UserDefaults {
        let suite = "ScrollioTests.window-render.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(advanced, forKey: PreferencesScrollingViewController.advancedExpandedDefaultsKey)
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    private func binding(_ code: UInt16, _ action: String, modifiers: UInt = 0) -> ButtonBinding {
        let trigger = RecordedEvent(type: .mouse, code: code, modifiers: modifiers, deviceFilter: nil)
        return ButtonBinding(triggerEvent: trigger, systemShortcutName: action, isEnabled: !action.isEmpty)
    }

    private func renderMouse(_ devices: [LogiMouseDeviceState], name: String, windowHeight: CGFloat? = nil) throws {
        try renderPane(MousePreferencesViewController.tabIdentifier, name: name, windowHeight: windowHeight, prepare: { preferences in
            guard let mouse = preferences.controller(for: MousePreferencesViewController.tabIdentifier)
                as? MousePreferencesViewController else { return }
            mouse.deviceSource = MouseDeviceSource(deviceStates: { devices }, refresh: {}, showDiagnostics: {})
            mouse.readbackSettleTime = 0
        }, afterLoad: { controller in
            (controller as? MousePreferencesViewController)?.reloadDevices()
        })
    }

    /// The Preferences window as the app makes it, in `appearance`; key unless `key` is
    /// false. Never shown.
    private func makeWindow(
        appearance: NSAppearance.Name,
        key: Bool = true,
        prepare: (PreferencesSplitViewController) -> Void = { _ in }
    ) throws -> (NSWindow, PreferencesSplitViewController) {
        let storyboard = NSStoryboard(name: "Main", bundle: app)
        let controller = try XCTUnwrap(
            storyboard.instantiateController(withIdentifier: WINDOW_IDENTIFIER.preferencesWindowController) as? PreferencesWindowController
        )
        // A window that counts as key and main, so the controls draw in the accent colour
        // as in the window the user works in. Never ordered in.
        let window = RenderWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: PreferencesWindowLayout.defaultContentHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: true
        )
        window.isReleasedWhenClosed = false
        window.isKey = key
        controller.window = window
        window.appearance = NSAppearance(named: appearance)
        let preferences = PreferencesSplitViewController(storyboard: storyboard, uiStateDefaults: nil)
        prepare(preferences)
        controller.contentViewController = preferences
        controller.configure(window, remembersFrame: false)
        preferences.updateWindowTitle()
        window.contentView?.layoutSubtreeIfNeeded()
        addTeardownBlock { controller.close() }
        return (window, preferences)
    }

    /// Writes `<name>-light.png` and `<name>-dark.png`: the pane's column (520 pt) as tall as
    /// the pane, cut from the whole window. (The sidebar's source list draws nothing off
    /// screen, so only the column is written.) `replacement` puts a controller of the
    /// test's own in the column instead of the pane's.
    private func renderPane(
        _ identifier: String,
        name: String,
        key: Bool = true,
        windowHeight: CGFloat? = nil,
        prepare: @escaping (PreferencesSplitViewController) -> Void = { _ in },
        replacement: (() -> NSViewController)? = nil,
        afterLoad: @escaping (NSViewController) -> Void = { _ in }
    ) throws {
        for (suffix, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let (window, preferences) = try makeWindow(appearance: appearanceName, key: key, prepare: prepare)
            XCTAssertTrue(preferences.selectPane(withIdentifier: identifier), identifier)
            if let replacement {
                preferences.host.show(replacement())
            }
            let controller = try XCTUnwrap(preferences.host.currentController)
            afterLoad(controller)
            let content = try XCTUnwrap(window.contentView)
            content.layoutSubtreeIfNeeded()
            let top = preferences.host.view.safeAreaInsets.top
            let paneHeight = max(controller.view.frame.height, controller.view.fittingSize.height)
            let height = windowHeight ?? max(PreferencesWindowLayout.defaultContentHeight, ceil(paneHeight + top))
            window.setContentSize(NSSize(width: content.frame.width, height: height))
            content.layoutSubtreeIfNeeded()
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            // At a given window height: the column as the window shows it, the title bar's
            // strip included, so a pane that does not fit shows where it is cut.
            let scroll = preferences.host.scrollView!
            let column = windowHeight == nil
                ? scroll.convert(scroll.bounds, to: content)
                : NSRect(x: scroll.convert(scroll.bounds, to: content).minX, y: 0, width: scroll.frame.width, height: content.frame.height)
            try write(content, rect: column, appearance: appearance, to: directory.appendingPathComponent("\(name)-\(suffix).png"))
        }
    }

    /// The popover's content in its own material, as NSPopover shows it.
    private func renderInPopoverMaterial(_ view: NSView, name: String) throws {
        for (suffix, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            let outer = NSView(frame: view.frame)
            outer.appearance = appearance
            let material = NSVisualEffectView(frame: view.frame)
            material.material = .popover
            material.blendingMode = .behindWindow
            outer.addSubview(material)
            material.addSubview(view)
            view.setFrameOrigin(.zero)
            view.layoutSubtreeIfNeeded()
            try write(outer, appearance: appearance, to: directory.appendingPathComponent("\(name)-\(suffix).png"))
            view.removeFromSuperview()
        }
    }

    /// Draws `view` at 2x over the window colour (the materials draw nothing off screen).
    private func write(_ view: NSView, rect: NSRect? = nil, appearance: NSAppearance, to url: URL) throws {
        view.display()
        let area = rect ?? view.bounds
        let bounds = NSRect(origin: .zero, size: area.size)
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: area))
        view.cacheDisplay(in: area, to: rep)

        let canvas = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * 2), pixelsHigh: Int(bounds.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        canvas.size = bounds.size
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: canvas))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        appearance.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            bounds.fill()
        }
        rep.draw(in: bounds)
        NSGraphicsContext.restoreGraphicsState()

        let png = try XCTUnwrap(canvas.representation(using: .png, properties: [:]))
        try png.write(to: url)
    }

    private func describe(_ color: NSColor?, in appearance: NSAppearance) -> String {
        guard let color else { return "nil" }
        var text = ""
        appearance.performAsCurrentDrawingAppearance {
            if let rgb = color.usingColorSpace(.sRGB) {
                text = String(format: "rgba(%.0f, %.0f, %.0f, %.2f)", rgb.redComponent * 255, rgb.greenComponent * 255, rgb.blueComponent * 255, rgb.alphaComponent)
            } else {
                text = "\(color)"
            }
        }
        return text
    }
}

/// Counts as the key and main window, so controls draw as in the window the user works in;
/// or, with `isKey` off, as a window behind another.
private final class RenderWindow: NSWindow {
    var isKey = true
    override var isKeyWindow: Bool { return isKey }
    override var isMainWindow: Bool { return isKey }
}

/// A pane with the kit's list, as the Buttons and Apps panes build theirs.
private final class ListRenderController: NSViewController {

    private let empty: Bool

    init(empty: Bool) {
        self.empty = empty
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("built in code")
    }

    override func loadView() {
        let paneWidth = PreferencesWindowLayout.contentWidth
        let width = PreferencesGroupedForm.boxWidth(paneWidth: paneWidth)
        let root = PreferencesForm.makeBackground()
        let content = PreferencesGroupedForm.installContentStack(in: root, paneWidth: paneWidth)
        content.setHuggingPriority(.defaultHigh, for: .vertical)

        let list = PreferencesListBox(
            width: width,
            emptyTitle: "No buttons yet",
            emptyExplanation: "Click + and press a mouse button to give it an action."
        )
        let section: NSView
        if empty {
            section = list
        } else {
            let calculator = NSWorkspace.shared.icon(forFile: "/System/Applications/Calculator.app")
            let popUp = NSPopUpButton(frame: .zero, pullsDown: true)
            popUp.addItem(withTitle: "")
            popUp.addItems(withTitles: ["Copy", "Paste"])
            popUp.item(at: 0)?.title = "Mission Control"
            popUp.item(at: 0)?.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: nil)
            popUp.widthAnchor.constraint(equalToConstant: 240).isActive = true
            let selectedPopUp = NSPopUpButton(frame: .zero, pullsDown: true)
            selectedPopUp.addItem(withTitle: "Gesture Navigation")
            selectedPopUp.item(at: 0)?.image = NSImage(systemSymbolName: "hand.draw", accessibilityDescription: nil)
            selectedPopUp.widthAnchor.constraint(equalToConstant: 240).isActive = true
            let info = NSButton(image: NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)!, target: nil, action: nil)
            info.isBordered = false
            let accessory = NSStackView(views: [info, selectedPopUp])
            accessory.spacing = 8
            list.setRows([
                PreferencesListRow(id: "back", title: "⌥ Back button", explanation: "Hold and move the mouse. Set the directions under Gestures.",
                                   icon: .symbol("computermouse"), accessory: accessory, centeredOn: selectedPopUp, controls: [selectedPopUp]),
                PreferencesListRow(id: "forward", title: "Forward button", icon: .symbol("arrow.right.circle"), accessory: popUp),
                PreferencesListRow(id: "calculator", title: "Calculator", explanation: "Uses its own scrolling settings",
                                   icon: .image(calculator), showsChevron: true),
                PreferencesListRow(id: "dimmed", title: "Button 6", explanation: "Choose what this button does.",
                                   icon: .symbol("questionmark.circle")),
            ])
            list.rows[3].isEnabled = false
            list.select("back")
            let spinner = NSProgressIndicator()
            spinner.style = .spinning
            spinner.controlSize = .small
            spinner.widthAnchor.constraint(equalToConstant: 12).isActive = true
            spinner.heightAnchor.constraint(equalToConstant: 12).isActive = true
            let checking = NSTextField(labelWithString: "Checking buttons…")
            checking.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            checking.textColor = .secondaryLabelColor
            let busy = NSStackView(views: [spinner, checking])
            busy.spacing = 6
            list.footerAccessory = busy
            section = PreferencesListSection(title: "Apps", list: list)
        }
        let switchBox = PreferencesGroupSection(width: width, rows: [
            PreferencesSwitchRow(title: "Limit scrolling to these apps", explanation: "Apps not in the list scroll the way macOS does.", target: nil, action: nil),
        ])
        let note = PreferencesGroupedForm.makeNote("Buttons and gestures still work everywhere. A second line of the note shows where it wraps under the box.")
        PreferencesGroupedForm.add([switchBox, section, note], to: content)
        view = root
        root.setFrameSize(root.fittingSize)
    }
}
