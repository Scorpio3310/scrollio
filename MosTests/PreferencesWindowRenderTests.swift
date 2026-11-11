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

    func testRenderGestures() throws {
        let master4 = MouseGestureDeviceSupport(deviceTracking: true, haptics: true)
        let cases: [(name: String, mode: MouseGestureMode, support: MouseGestureDeviceSupport, bound: Bool)] = [
            ("gestures-discrete-no-logitech", .discrete, .none, true),
            ("gestures-discrete-mx-master-4", .discrete, master4, true),
            ("gestures-follow-no-logitech", .interactive, .none, true),
            ("gestures-follow-mx-master-4", .interactive, master4, true),
            ("gestures-no-gesture-button", .discrete, .none, false),
        ]
        for item in cases {
            var gesture = MouseGestureSettings.default
            gesture.mode = item.mode
            gesture.deviceTracking = item.support.deviceTracking
            Options.shared.gesture = gesture
            // A pane of its own: "Follow the hand" is available whatever this Mac says.
            try renderPane(GesturesPreferencesViewController.tabIdentifier, name: item.name, replacement: {
                let gestures = GesturesPreferencesViewController(isInteractiveAvailable: { true })
                gestures.deviceSource = MouseGestureDeviceSource(support: { item.support }, refresh: {})
                gestures.bindingSummary = {
                    MouseGestureBindingSummary(hasGestureButton: item.bound, hasLogitechGestureButton: item.support.deviceTracking)
                }
                return gestures
            }, afterLoad: { controller in
                guard let gestures = controller as? GesturesPreferencesViewController else { return }
                gestures.previewView.prefersReducedMotion = { true }
                gestures.previewView.reduceMotionDidChange()
            })
        }
    }

    func testRenderGeneral() throws {
        try renderPane(PANEL_IDENTIFIER.general, name: "general")
    }

    func testRenderAbout() throws {
        try renderPane(AboutPreferencesViewController.tabIdentifier, name: "about")
    }

    func testRenderButtons() throws {
        // The window calls viewWillAppear, which shows or hides the empty list's hint.
        let appear: (NSViewController) -> Void = { $0.viewWillAppear() }
        Options.shared.buttons.binding = []
        try renderPane(PANEL_IDENTIFIER.buttons, name: "buttons-empty", afterLoad: appear)
        Options.shared.buttons.binding = [
            binding(3, SystemShortcut.mouseGestureNavigation.identifier, display: ["Mouse 4"]),
            binding(4, SystemShortcut.mosScrollDash.identifier, display: ["Mouse 5"]),
            binding(5, SystemShortcut.mosScrollToggle.identifier, display: ["Mouse 6"]),
            binding(6, SystemShortcut.mosScrollBlock.identifier, display: ["Mouse 7"]),
            binding(7, SystemShortcut.copy.identifier, display: ["Mouse 8"]),
        ]
        try renderPane(PANEL_IDENTIFIER.buttons, name: "buttons-bindings", afterLoad: appear)
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
                ("note", gestures.buttonsNoteLabel),
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

    private func binding(_ code: UInt16, _ action: String, display: [String]) -> ButtonBinding {
        let trigger = RecordedEvent(type: .mouse, code: code, modifiers: 0, displayComponents: display, deviceFilter: nil)
        return ButtonBinding(triggerEvent: trigger, systemShortcutName: action, isEnabled: true)
    }

    private func renderMouse(_ devices: [LogiMouseDeviceState], name: String) throws {
        try renderPane(MousePreferencesViewController.tabIdentifier, name: name, prepare: { preferences in
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
            let height = max(PreferencesWindowLayout.defaultContentHeight, ceil(paneHeight + top))
            window.setContentSize(NSSize(width: content.frame.width, height: height))
            content.layoutSubtreeIfNeeded()
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            let column = preferences.host.scrollView.convert(preferences.host.scrollView.bounds, to: content)
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
                PreferencesListRow(id: "calculator", title: "Calculator", explanation: "Own scrolling settings",
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
