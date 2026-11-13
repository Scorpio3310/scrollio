//
//  PreferencesRingTests.swift
//  ScrollioTests
//
//  The Shortcut Ring pane: its row for what opens the ring and its way to the Buttons
//  pane, the eight places with their pull-downs, what the pull-downs offer and store, the
//  drawing that follows the row pointed at, "Reset to Defaults" with its Undo; and the
//  Buttons pane's side: the action in its menu, for a button and for a key. Nothing is
//  shown on screen.
//

import XCTest
@testable import Scrollio_Debug

final class PreferencesRingTests: XCTestCase {

    private var savedRing = ShortcutRingSettings.default
    private var summary = ShortcutRingBindingSummary(triggerTitles: [])

    override func setUp() {
        super.setUp()
        savedRing = Options.shared.ring
        Options.shared.ring = .default
        summary = ShortcutRingBindingSummary(triggerTitles: [])
    }

    override func tearDown() {
        Options.shared.ring = savedRing
        super.tearDown()
    }

    private func makeController() -> RingPreferencesViewController {
        let controller = RingPreferencesViewController()
        controller.bindingSummary = { [unowned self] in self.summary }
        _ = controller.view
        return controller
    }

    /// The menu item of a listed action in a place's pull-down.
    private func item(_ identifier: String, in popUp: NSPopUpButton) -> NSMenuItem? {
        func find(_ menu: NSMenu?) -> NSMenuItem? {
            for item in menu?.items ?? [] {
                if (item.representedObject as? SystemShortcut.Shortcut)?.identifier == identifier { return item }
                if let found = find(item.submenu) { return found }
            }
            return nil
        }
        return find(popUp.menu)
    }

    /// "Open App or File…" or "Keyboard Shortcut…" of a place's pull-down.
    private func item(marked marker: String, in popUp: NSPopUpButton) -> NSMenuItem? {
        return popUp.menu?.items.first { $0.representedObject as? String == marker }
    }

    // MARK: The pane

    func testThePaneIsCalledShortcutRingAndIsAsWideAsTheOthers() {
        let controller = makeController()
        XCTAssertEqual(controller.title, "Shortcut Ring")
        XCTAssertEqual(RingPreferencesViewController.tabIdentifier, "ring")
        XCTAssertEqual(controller.view.frame.width, 520)
        XCTAssertFalse(controller.view.hasAmbiguousLayout)
        XCTAssertEqual(controller.sections.count, 4, "the drawing, what opens the ring, the places, the footer")
    }

    /// Eight rows, clockwise from the top, each showing what the stored ring holds there.
    func testEightPlacesClockwiseFromTheTopShowTheStoredRing() {
        var ring = ShortcutRingSettings.default
        ring[3] = .empty
        ring[4] = ShortcutRingPlace(action: "somethingNewer")
        Options.shared.ring = ring
        let controller = makeController()
        XCTAssertEqual(controller.placeRows.map { $0.title }, [
            "Top", "Top right", "Right", "Bottom right", "Bottom", "Bottom left", "Left", "Top left",
        ])
        let shown = controller.placePopUps.map { $0.menu?.items.first?.title }
        XCTAssertEqual(shown[0], "Mission Control")
        XCTAssertEqual(shown[2], SystemShortcut.moveSpaceRight.localizedName)
        XCTAssertEqual(shown[3], "No Action")
        XCTAssertEqual(shown[4], "No Action", "an action this version does not run shows as none")
        XCTAssertEqual(shown[5], "Copy")
        controller.view.layoutSubtreeIfNeeded()
        for (place, popUp) in controller.placePopUps.enumerated() {
            XCTAssertTrue(popUp.pullsDown)
            XCTAssertEqual(popUp.frame.width, 240, "they line up")
            XCTAssertEqual(popUp.accessibilityLabel(), controller.placeRows[place].title)
            XCTAssertTrue(controller.placeRows[place].accessory === popUp)
        }
        XCTAssertNotNil(controller.placePopUps[0].menu?.items.first?.image, "the action's symbol")
        XCTAssertNil(controller.placePopUps[3].menu?.items.first?.image)
        // The pull-down is the one of a row of the Buttons pane.
        XCTAssertTrue(controller.placePopUps.allSatisfy { $0.isForRingPlace })
    }

    func testChoosingAnActionStoresItAndNoActionEmptiesThePlace() throws {
        let controller = makeController()
        let popUp = controller.placePopUps[1]
        popUp.shortcutSelected(try XCTUnwrap(item("undo", in: popUp)))
        XCTAssertEqual(Options.shared.ring[1].action, "undo")
        XCTAssertEqual(popUp.menu?.items.first?.title, "Undo")
        XCTAssertEqual(controller.previewView.face.places[1].title, "Undo", "the drawing follows")

        popUp.shortcutSelected(try XCTUnwrap(popUp.noActionItem))
        XCTAssertTrue(Options.shared.ring[1].isEmpty)
        XCTAssertEqual(popUp.menu?.items.first?.title, "No Action")
        XCTAssertTrue(controller.previewView.face.places[1].isEmpty)
        // The other places stay.
        XCTAssertEqual(Options.shared.ring[0].action, "missionControl")
        XCTAssertEqual(Options.shared.ring[2].action, "moveSpaceRight")
    }

    /// A place's menu is the Buttons row's menu with what a place can hold: the listed
    /// keyboard shortcuts by category, Back and Forward of the mouse buttons, "Open App or
    /// File…" and "Keyboard Shortcut…". Not: the left, right and middle click, what is
    /// only held, the Logitech actions, Gesture Navigation, the ring itself.
    func testAPullDownOffersWhatAPlaceCanHoldAndNothingElse() throws {
        let controller = makeController()
        let menu = try XCTUnwrap(controller.placePopUps[0].menu)
        let top = menu.items.dropFirst().filter { !$0.isSeparatorItem }
        XCTAssertEqual(top.first?.title, "No Action")
        let categories = top.filter { $0.submenu != nil }
        XCTAssertEqual(
            categories.map { $0.title },
            SystemShortcut.shortcutsByCategory.map { SystemShortcut.localizedCategoryName($0.category) } + ["Mouse Buttons"]
        )
        let offered = categories.flatMap { $0.submenu?.items ?? [] }.compactMap { ($0.representedObject as? SystemShortcut.Shortcut)?.identifier }
        XCTAssertTrue(offered.contains("copy"))
        XCTAssertTrue(offered.contains("screenshotSelection"))
        for identifier in offered {
            XCTAssertTrue(ShortcutRingPlace(action: identifier).runs, identifier)
        }
        let mouse = try XCTUnwrap(categories.last?.submenu)
        XCTAssertEqual(mouse.items.compactMap { ($0.representedObject as? SystemShortcut.Shortcut)?.identifier }, ["mouseBackClick", "mouseForwardClick"])
        let leaves = top.filter { $0.submenu == nil }.map { $0.title }
        XCTAssertEqual(leaves, ["No Action", "Open App or File…", "Keyboard Shortcut…"])
    }

    // MARK: A key combination and an app in a place

    /// "Keyboard Shortcut…" records a key combination with the Buttons pane's recorder;
    /// the place stores it as a button does, the pull-down shows its keys and the drawing
    /// writes them in the place.
    func testKeyboardShortcutRecordsACombinationIntoThePlace() throws {
        let controller = makeController()
        controller.startShortcutRecorder = { _ in }
        let popUp = controller.placePopUps[7]
        XCTAssertNotNil(popUp.startShortcutRecorder, "the pane's recorder seam reaches every pull-down")
        popUp.shortcutSelected(try XCTUnwrap(item(marked: ShortcutManager.MenuMarker.keyboardShortcut, in: popUp)))
        XCTAssertEqual(popUp.actionState, .recordingPrompt)
        XCTAssertEqual(Options.shared.ring[7].action, "showDesktop", "nothing is stored until a key is pressed")

        // ⇧⌘K was pressed: what the recorder hands the pull-down, and the pull-down the pane.
        let shiftCommand = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue)
        let pressed = InputEvent(type: .keyboard, code: 40, modifiers: shiftCommand, phase: .down, source: .hidPP, device: nil)
        let name = ButtonActionPullDown.bindingName(forRecorded: pressed)
        XCTAssertEqual(name, "custom::40:1179648")
        popUp.onEventRecorded(KeyRecorder(), didRecordEvent: pressed, isDuplicate: false)
        RunLoop.main.run(until: Date().addingTimeInterval(KeyRecorder.recordingFeedbackDelay(isDuplicate: false) + 0.2))
        XCTAssertEqual(Options.shared.ring[7], ShortcutRingPlace(action: name))
        XCTAssertEqual(controller.selectedPlace, 7)
        let face = controller.previewView.face.places[7]
        XCTAssertFalse(face.isEmpty)
        XCTAssertEqual(face.glyphs.joined(), face.title)
        XCTAssertTrue(face.title.hasPrefix("⇧⌘"))
        XCTAssertEqual(popUp.menu?.items.first?.title, face.title, "the pull-down shows the keys")

        // A recorded combination that is a listed action is stored as that action.
        let command = InputEvent(type: .keyboard, code: 8, modifiers: .maskCommand, phase: .down, source: .hidPP, device: nil)
        popUp.onCustomShortcutRecorded?(ButtonActionPullDown.bindingName(forRecorded: command))
        XCTAssertEqual(Options.shared.ring[7].action, "copy")
    }

    /// The recorder of a place asks for what a place takes and refuses the rest when it
    /// is pressed: a mouse button other than Back and Forward, a modifier key by itself.
    /// (It used to invite "a mouse button", show it as recorded and then drop it.)
    func testTheRecorderOfAPlaceSaysWhatItTakesAndRefusesTheRest() {
        let controller = makeController()
        let popUp = controller.placePopUps[2]
        let recorder = KeyRecorder()
        XCTAssertEqual(popUp.waitingHint(recorder, mode: .adaptive), "Press a shortcut or a key")
        func event(_ type: EventType, _ code: UInt16, _ modifiers: CGEventFlags = []) -> InputEvent {
            return InputEvent(type: type, code: code, modifiers: modifiers, phase: .down, source: .hidPP, device: nil)
        }
        for refused in [event(.mouse, 2), event(.mouse, 5), event(.keyboard, KeyCode.shiftL)] {
            XCTAssertFalse(popUp.validateRecordedEvent(recorder, event: refused), "\(refused.type) \(refused.code)")
            XCTAssertEqual(popUp.refusalHint(recorder, event: refused), "A place takes a shortcut or a key")
        }
        let shiftCommand = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue)
        for taken in [event(.keyboard, 40, shiftCommand), event(.keyboard, 96), event(.mouse, 3), event(.mouse, 4)] {
            XCTAssertTrue(popUp.validateRecordedEvent(recorder, event: taken), "\(taken.type) \(taken.code)")
            XCTAssertNil(popUp.refusalHint(recorder, event: taken))
        }
        // A row of the Buttons pane keeps the recorder's own words and takes a mouse button.
        let trigger = RecordedEvent(type: .mouse, code: 4, modifiers: 0, deviceFilter: nil)
        let button = ButtonActionPullDown(binding: ButtonBinding(triggerEvent: trigger, systemShortcutName: "copy"))
        XCTAssertNil(button.waitingHint(recorder, mode: .adaptive))
        XCTAssertTrue(button.validateRecordedEvent(recorder, event: event(.mouse, 2)))
        XCTAssertNil(button.refusalHint(recorder, event: event(.mouse, 2)))
    }

    /// What a place cannot hold is not stored when the recorder hands it over: a mouse
    /// button (a click) and a modifier key by itself. The place keeps what it had.
    func testARecordedMouseButtonOrModifierIsNotStored() {
        let controller = makeController()
        let popUp = controller.placePopUps[2]
        for name in ["custom::mouse:5:0", "modifierShift", "mouseLeftClick", "custom::56:0"] {
            popUp.onCustomShortcutRecorded?(name)
            XCTAssertEqual(Options.shared.ring[2].action, "moveSpaceRight", name)
            XCTAssertEqual(popUp.menu?.items.first?.title, SystemShortcut.moveSpaceRight.localizedName, name)
        }
    }

    /// "Open App or File…" opens the Buttons pane's popover at the place's pull-down, with
    /// what the place opens now; the app that is chosen is stored as a button stores it,
    /// its icon stands in the place and its name in the middle of the ring.
    func testOpenAppOrFilePutsAnAppIntoThePlace() throws {
        let controller = makeController()
        var shown: [(anchor: NSView, existing: OpenTargetPayload?)] = []
        controller.presentOpenTarget = { _, anchor, existing in shown.append((anchor, existing)) }
        let popUp = controller.placePopUps[4]
        popUp.shortcutSelected(try XCTUnwrap(item(marked: ShortcutManager.MenuMarker.openTarget, in: popUp)))
        XCTAssertEqual(shown.count, 1)
        XCTAssertTrue(shown.first?.anchor === popUp)
        XCTAssertNil(shown.first?.existing)
        XCTAssertEqual(Options.shared.ring[4].action, "appExpose", "nothing is stored until an app is chosen")

        let calculator = OpenTargetPayload(
            path: "/System/Applications/Calculator.app", bundleID: "com.apple.calculator", arguments: "", kind: .application
        )
        try XCTUnwrap(controller.openTargetPopover).onCommit?(calculator)
        XCTAssertNil(controller.openTargetPopover)
        XCTAssertEqual(Options.shared.ring[4], ShortcutRingPlace(openTarget: calculator))
        XCTAssertEqual(Options.shared.ring[4].action, "openTarget")
        // (The app's name is the system's, in the language of whoever runs the tests.)
        let face = controller.previewView.face.places[4]
        XCTAssertFalse(face.title.isEmpty)
        XCTAssertFalse(face.title.contains("/"), "its name, not its path")
        XCTAssertNotNil(face.image, "the app's icon")
        XCTAssertEqual(popUp.menu?.items.first?.title, face.title, "the pull-down and the ring name it alike")
        XCTAssertNotNil(popUp.menu?.items.first?.image)
        // The pane hands the face on to the ring on screen: no look on disk at a press.
        XCTAssertTrue(ShortcutRingController.preparedFace?.ring == Options.shared.ring)
        XCTAssertNotNil(ShortcutRingController.preparedFace?.face.places[4].image)

        // Asked again, the popover starts from what the place opens; Cancel changes nothing.
        popUp.shortcutSelected(try XCTUnwrap(item(marked: ShortcutManager.MenuMarker.openTarget, in: popUp)))
        XCTAssertEqual(shown.last?.existing, calculator)
        try XCTUnwrap(controller.openTargetPopover).onCancel?()
        XCTAssertNil(controller.openTargetPopover)
        XCTAssertEqual(Options.shared.ring[4], ShortcutRingPlace(openTarget: calculator))
    }

    // MARK: What opens the ring

    func testWithNothingBoundTheRowOffersToSetOneUp() {
        let controller = makeController()
        XCTAssertEqual(controller.triggerRow.title, "Button or key")
        XCTAssertEqual(controller.triggerRow.explanation,
                       "Nothing opens the ring yet. A key combination works too, even one that Logi Options+ sends for a button.")
        XCTAssertEqual(controller.triggerButton.title, "Set Up…")
        var requests: [Bool] = []
        controller.openButtonsPane = { requests.append($0) }
        controller.triggerButton.performClick(nil)
        XCTAssertEqual(requests, [true], "it records a button or key that gets the ring")
    }

    func testWithATriggerTheRowNamesItAndLeadsToItsRow() {
        summary = ShortcutRingBindingSummary(triggerTitles: ["Thumb panel", "⌃⌥ Space"])
        let controller = makeController()
        XCTAssertEqual(controller.triggerRow.explanation,
                       "Thumb panel and ⌃⌥ Space. A key combination works too, even one that Logi Options+ sends for a button.")
        XCTAssertEqual(controller.triggerButton.title, "Change")
        var requests: [Bool] = []
        controller.openButtonsPane = { requests.append($0) }
        controller.triggerButton.performClick(nil)
        XCTAssertEqual(requests, [false])
    }

    /// The row answers "can a key open it?" whether or not something opens the ring yet:
    /// yes, also a keystroke that Logi Options+ sends for a button.
    func testTheRowSaysThatAKeyCombinationWorks() {
        for titles in [[], ["Thumb panel"]] {
            summary = ShortcutRingBindingSummary(triggerTitles: titles)
            let explanation = makeController().triggerRow.explanation ?? ""
            XCTAssertTrue(explanation.contains("key combination works too"), explanation)
            XCTAssertTrue(explanation.contains("Logi Options+"), explanation)
        }
    }

    /// What opens the ring: enabled bindings with its action, a button or a key that can
    /// run; each named once, as the Buttons pane names it.
    func testTheSummaryCountsButtonsAndKeysThatCanRun() {
        func binding(_ type: EventType, _ code: UInt16, modifiers: UInt = 0, action: String = "shortcutRing", enabled: Bool = true) -> ButtonBinding {
            return ButtonBinding(
                triggerEvent: RecordedEvent(type: type, code: code, modifiers: modifiers, deviceFilter: nil),
                systemShortcutName: action, isEnabled: enabled
            )
        }
        let control = UInt(CGEventFlags.maskControl.rawValue)
        let bindings = [
            binding(.mouse, 4),
            binding(.keyboard, 49, modifiers: control),
            binding(.mouse, 3, action: "copy"),
            binding(.mouse, 5, enabled: false),
            binding(.keyboard, 0),                      // a plain letter never runs
        ]
        let summary = ShortcutRingBindingSummary(bindings: bindings, titles: { $0.map { "\($0.type.rawValue) \($0.code)" } })
        XCTAssertEqual(summary.triggerTitles, ["mouse 4", "keyboard 49"])
        XCTAssertTrue(summary.hasTrigger)
        XCTAssertFalse(ShortcutRingBindingSummary(bindings: [binding(.mouse, 3, action: "copy")]).hasTrigger)
    }

    // MARK: Texts

    /// Every explanation of the pane is plain sentences that fit two lines where it
    /// stands: the row's beside its button, the hint across the box.
    /// "Freeze pointer while the ring is held": a switch under what opens the ring, off for
    /// a new ring, that shows and stores the ring's own setting (Gestures keeps its own).
    func testTheFreezeSwitchShowsAndStoresTheRingsOwnSetting() throws {
        let gestureFreeze = Options.shared.gesture.freezePointer
        let controller = makeController()
        XCTAssertEqual(controller.freezeRow.title, "Freeze pointer while the ring is held")
        XCTAssertEqual(controller.freezeRow.explanation,
                       "The pointer stays where it is while you hold the button. The way your hand moves still chooses.")
        XCTAssertTrue(controller.freezeRow.accessory === controller.freezeToggle)
        let toggle = try XCTUnwrap(controller.freezeToggle as? NSSwitch)
        XCTAssertEqual(toggle.state, .off, "a new ring leaves the pointer alone")

        toggle.state = .on
        controller.freezeToggled(toggle)
        XCTAssertTrue(Options.shared.ring.freezePointer)
        XCTAssertEqual(Options.shared.ring.places, ShortcutRingSettings.default.places, "the places stay")
        XCTAssertEqual(Options.shared.gesture.freezePointer, gestureFreeze, "Gestures keeps its own switch")
        XCTAssertEqual(ShortcutRingController.preparedFace?.ring, Options.shared.ring,
                       "the face kept for the ring on screen is the stored ring's")
        XCTAssertEqual((makeController().freezeToggle as? NSSwitch)?.state, .on, "a pane made later shows it")

        toggle.state = .off
        controller.freezeToggled(toggle)
        XCTAssertFalse(Options.shared.ring.freezePointer)
        XCTAssertEqual(Options.shared.ring, .default)
    }

    func testEveryExplanationFitsTwoLines() {
        let font = PreferencesGroupedForm.explanationFont
        let twoLines = 2 * ceil(font.ascender - font.descender + font.leading) + 2
        func height(_ text: String, width: CGFloat) -> CGFloat {
            return (text as NSString).boundingRect(
                with: NSSize(width: width, height: 1000), options: [.usesLineFragmentOrigin], attributes: [.font: font]
            ).height
        }
        for titles in [[], ["Thumb panel", "⌃⌥ Space"], ["Middle button", "Thumb panel", "⌃⌥ Space"]] {
            summary = ShortcutRingBindingSummary(triggerTitles: titles)
            let controller = makeController()
            controller.view.layoutSubtreeIfNeeded()
            let label = controller.triggerRow.explanationLabel
            let text = label.stringValue
            XCTAssertTrue(text.hasSuffix("."), text)
            XCTAssertGreaterThan(label.frame.width, 200)
            XCTAssertLessThanOrEqual(height(text, width: label.frame.width), twoLines, "\(text) in \(label.frame.width) pt")
        }
        let controller = makeController()
        controller.view.layoutSubtreeIfNeeded()
        let freeze = controller.freezeRow.explanationLabel
        XCTAssertGreaterThan(freeze.frame.width, 200)
        XCTAssertLessThanOrEqual(height(freeze.stringValue, width: freeze.frame.width), twoLines, freeze.stringValue)
        let hint = controller.placesHintLabel.stringValue
        // Two sentences, each on its own line (wrapped as one text, the second line was two words).
        XCTAssertEqual(hint, "Hold the button and move towards a shortcut, then let go.\nOr press and let go, then click one.")
        for line in hint.split(separator: "\n") {
            XCTAssertLessThanOrEqual(height(String(line), width: RingPreferencesViewController.boxWidth - 2 * PreferencesGroupedForm.rowHorizontalInset),
                                     twoLines / 2 + 1, String(line))
        }
        let width = RingPreferencesViewController.boxWidth - 2 * PreferencesGroupedForm.rowHorizontalInset
        XCTAssertLessThanOrEqual(height(hint, width: width), twoLines, hint)
        // The rows of the places have a title and no explanation.
        XCTAssertTrue(controller.placeRows.allSatisfy { $0.explanation == nil })
    }

    // MARK: The drawing

    func testTheDrawingShowsTheRingAndLightsThePlaceOfTheRowPointedAt() {
        let controller = makeController()
        let preview = controller.previewView!
        XCTAssertEqual(preview.face.places.map { $0.title }.first, "Mission Control")
        XCTAssertEqual(preview.face.filled, Array(repeating: true, count: 8))
        XCTAssertNil(preview.lit)
        XCTAssertEqual(preview.accessibilityLabel(), "The ring as it opens at the pointer")

        controller.placeHoverChanged(5, inside: true)
        XCTAssertEqual(preview.lit, 5)
        // The row whose place is lit says so: its title is tinted, the others are not.
        XCTAssertEqual(controller.placeRows[5].titleLabel.textColor, NSColor.controlAccentColor)
        XCTAssertEqual(controller.placeRows[4].titleLabel.textColor, NSColor.labelColor)
        controller.placeHoverChanged(6, inside: true)
        controller.placeHoverChanged(5, inside: false)
        XCTAssertEqual(preview.lit, 6, "leaving the old row after entering the new one keeps the new one")
        controller.placeHoverChanged(6, inside: false)
        XCTAssertNil(preview.lit)
        XCTAssertTrue(controller.placeRows.allSatisfy { $0.titleLabel.textColor == NSColor.labelColor })
        // Each row tells when the pointer is over it.
        for row in controller.placeRows {
            XCTAssertEqual(row.trackingAreas.filter { $0.owner === controller }.count, 1)
        }
    }

    /// The other way round: a place of the drawing under the pointer is lit, and a click
    /// on it selects its row (the pull-down takes the keyboard, the place stays lit).
    func testAPlaceOfTheDrawingCanBePointedAtAndClicked() throws {
        let controller = makeController()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 900), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        addTeardownBlock { window.close() }
        controller.view.layoutSubtreeIfNeeded()
        let preview = try XCTUnwrap(controller.previewView)

        // Where the drawing has its places: by the screen's geometry, drawn smaller.
        func point(ofPlace place: Int) -> NSPoint {
            let offset = ShortcutRingGeometry.offset(ofPlace: place)
            let scale = ShortcutRingPreviewView.ringScale
            return NSPoint(x: preview.bounds.midX + offset.x * scale, y: preview.bounds.midY - offset.y * scale)
        }
        for place in 0..<8 {
            XCTAssertEqual(preview.place(at: point(ofPlace: place)), place)
        }
        XCTAssertNil(preview.place(at: NSPoint(x: preview.bounds.midX, y: preview.bounds.midY)), "the middle is no place")
        XCTAssertNil(preview.place(at: NSPoint(x: 12, y: 12)), "nor is the card beside the ring")

        preview.onPlaceHovered?(2)
        XCTAssertEqual(preview.lit, 2)
        preview.onPlaceHovered?(nil)
        XCTAssertNil(preview.lit)

        preview.onPlaceClicked?(6)
        XCTAssertEqual(controller.selectedPlace, 6)
        XCTAssertEqual(preview.lit, 6, "the selected row's place stays lit")
        XCTAssertTrue(window.firstResponder === controller.placePopUps[6], "its pull-down has the keyboard")
        // Pointing elsewhere shows that place, and then the selected one again.
        controller.placeHoverChanged(1, inside: true)
        XCTAssertEqual(preview.lit, 1)
        controller.placeHoverChanged(1, inside: false)
        XCTAssertEqual(preview.lit, 6)
        // Using another row's pull-down selects that row.
        let other = controller.placePopUps[3]
        other.shortcutSelected(try XCTUnwrap(item("undo", in: other)))
        XCTAssertEqual(controller.selectedPlace, 3)
        XCTAssertEqual(preview.lit, 3)
    }

    // MARK: Reset to Defaults

    private func send(_ control: NSControl) {
        XCTAssertTrue(control.sendAction(control.action, to: control.target))
    }

    /// A ring that differs from a new one: another action, an empty place, an app, a
    /// recorded key combination, and the pointer frozen.
    private var changedRing: ShortcutRingSettings {
        var ring = ShortcutRingSettings.default
        ring[0] = ShortcutRingPlace(action: "undo")
        ring[3] = .empty
        ring[4] = ShortcutRingPlace(openTarget: OpenTargetPayload(
            path: "/System/Applications/Calculator.app", bundleID: "com.apple.calculator", arguments: "", kind: .application
        ))
        ring[7] = ShortcutRingPlace(action: "custom::40:1179648")
        ring.freezePointer = true
        return ring
    }

    /// What the pull-downs show, top and clockwise.
    private func shownActions(_ controller: RingPreferencesViewController) -> [String?] {
        return controller.placePopUps.map { $0.menu?.items.first?.title }
    }

    /// A pane whose reset has an Undo to register. The offer lasts until the test ends it.
    private func makeControllerWithUndo() -> (RingPreferencesViewController, UndoManager) {
        let controller = makeController()
        let undo = UndoManager()
        undo.groupsByEvent = false
        controller.paneUndoManager = undo
        controller.resetToDefaults.undoOfferDuration = 60
        return (controller, undo)
    }

    /// A click that resets, as one event: its Undo is one group.
    private func click(_ button: NSButton, _ undo: UndoManager) {
        undo.beginUndoGrouping()
        send(button)
        undo.endUndoGrouping()
    }

    /// The button is the Scrolling pane's: the same title, in a footer under the last box,
    /// at the right edge and at the same distances.
    func testResetToDefaultsSitsUnderTheBoxesAsInScrolling() throws {
        let controller = makeController()
        controller.view.layoutSubtreeIfNeeded()
        let button = controller.resetToDefaultsButton
        XCTAssertEqual(button.title, "Reset to Defaults")
        XCTAssertEqual(button.identifier, RingPreferencesViewController.Identifier.reset)
        let footer = try XCTUnwrap(controller.sections.last as? PreferencesGroupFooter)
        XCTAssertTrue(footer.views.count == 1 && footer.views.first === button)

        func frame(_ view: NSView, in pane: NSViewController) -> NSRect {
            return pane.view.convert(view.alignmentRect(forFrame: view.frame), from: view.superview)
        }
        let places = frame(controller.sections[2], in: controller)
        // The root view is not flipped: lower on screen is a smaller y.
        XCTAssertEqual(places.minY - frame(footer, in: controller).maxY, PreferencesGroupedForm.sectionSpacing, accuracy: 0.5)
        XCTAssertEqual(frame(footer, in: controller).minY, PreferencesGroupedForm.margin, accuracy: 0.5, "the last thing in the pane")
        XCTAssertEqual(frame(button, in: controller).maxX, places.maxX, accuracy: 0.5, "at the boxes' right edge")
        XCTAssertEqual(controller.view.frame.size, controller.view.fittingSize)
        XCTAssertFalse(controller.view.hasAmbiguousLayout)

        // Side by side with the Scrolling pane's button.
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesScrollingViewController.self))
        let scrolling = try XCTUnwrap(
            storyboard.instantiateController(withIdentifier: PANEL_IDENTIFIER.scrolling) as? PreferencesScrollingViewController
        )
        scrolling.uiStateDefaults = TestDefaults.make(for: self)
        scrolling.view.layoutSubtreeIfNeeded()
        let model = try XCTUnwrap(scrolling.resetToDefaultsButton)
        XCTAssertEqual(button.title, model.title)
        XCTAssertEqual(button.bezelStyle, model.bezelStyle)
        XCTAssertEqual(button.controlSize, model.controlSize)
        XCTAssertEqual(button.font, model.font)
        let mine = frame(button, in: controller)
        let its = frame(model, in: scrolling)
        XCTAssertEqual(mine.size.width, its.size.width, accuracy: 0.5)
        XCTAssertEqual(mine.size.height, its.size.height, accuracy: 0.5)
        XCTAssertEqual(mine.maxX, its.maxX, accuracy: 0.5)
        XCTAssertEqual(mine.minY, its.minY, accuracy: 0.5, "as far from the pane's lower edge")
    }

    func testResetIsOnlyOfferedWhenTheRingDiffers() throws {
        let controller = makeController()
        let button = controller.resetToDefaultsButton
        XCTAssertFalse(controller.resetToDefaults.hasSettingsToReset)
        XCTAssertFalse(button.isEnabled, "a new ring has nothing to reset")

        let popUp = controller.placePopUps[1]
        popUp.shortcutSelected(try XCTUnwrap(item("undo", in: popUp)))
        XCTAssertTrue(controller.resetToDefaults.hasSettingsToReset)
        XCTAssertTrue(button.isEnabled)
        popUp.shortcutSelected(try XCTUnwrap(item(SystemShortcut.screenshotSelection.identifier, in: popUp)))
        XCTAssertFalse(button.isEnabled, "the place holds again what a new ring holds there")

        let toggle = try XCTUnwrap(controller.freezeToggle as? NSSwitch)
        toggle.state = .on
        send(toggle)
        XCTAssertTrue(button.isEnabled, "the switch counts")
        toggle.state = .off
        send(toggle)
        XCTAssertFalse(button.isEnabled)

        // A ring that changed while the pane was away (a settings file was imported).
        Options.shared.ring = changedRing
        controller.viewWillAppear()
        XCTAssertTrue(button.isEnabled)
        XCTAssertEqual(button.title, "Reset to Defaults")
    }

    /// The reset is the ring of a new installation, its eight places and the switch, shown
    /// at once in the rows and the drawing. What opens the ring is a binding of the Buttons
    /// pane: it stays, and the first row still names it.
    func testResetPutsBackTheNewRingAndLeavesWhatOpensIt() throws {
        let savedBindings = Options.shared.buttons.binding
        defer {
            Options.shared.buttons.binding = savedBindings
            ButtonUtils.shared.invalidateCache()
        }
        func binding(_ type: EventType, _ code: UInt16, modifiers: UInt = 0, action: String) -> ButtonBinding {
            return ButtonBinding(
                triggerEvent: RecordedEvent(type: type, code: code, modifiers: modifiers, deviceFilter: nil),
                systemShortcutName: action, isEnabled: true
            )
        }
        let ringAction = SystemShortcut.shortcutRing.identifier
        let bindings = [
            binding(.mouse, 4, action: ringAction),
            binding(.keyboard, 49, modifiers: UInt(CGEventFlags.maskControl.rawValue), action: ringAction),
            binding(.mouse, 3, action: "copy"),
        ]
        Options.shared.buttons.binding = bindings
        Options.shared.ring = changedRing
        // The pane as the window has it: the first row reads the stored bindings.
        let controller = RingPreferencesViewController()
        _ = controller.view
        let opens = try XCTUnwrap(controller.triggerRow.explanation)
        XCTAssertEqual(controller.triggerButton.title, "Change")
        XCTAssertEqual(shownActions(controller)[0], "Undo")
        XCTAssertEqual(shownActions(controller)[3], "No Action")
        XCTAssertEqual((controller.freezeToggle as? NSSwitch)?.state, .on)
        XCTAssertTrue(controller.resetToDefaultsButton.isEnabled)

        send(controller.resetToDefaultsButton)

        let ring = Options.shared.ring
        XCTAssertEqual(ring, .default)
        XCTAssertEqual(ring.places.map(\.action), [
            SystemShortcut.missionControl, SystemShortcut.screenshotSelection, SystemShortcut.moveSpaceRight,
            SystemShortcut.paste, SystemShortcut.appExpose, SystemShortcut.copy,
            SystemShortcut.moveSpaceLeft, SystemShortcut.showDesktop,
        ].map(\.identifier), "the eight places of a new ring, clockwise from the top")
        XCTAssertTrue(ring.places.allSatisfy { $0.openTarget == nil })
        XCTAssertFalse(ring.freezePointer, "and its switch: off")

        // The rows and the drawing follow at once.
        XCTAssertEqual(shownActions(controller), [
            SystemShortcut.missionControl, SystemShortcut.screenshotSelection, SystemShortcut.moveSpaceRight,
            SystemShortcut.paste, SystemShortcut.appExpose, SystemShortcut.copy,
            SystemShortcut.moveSpaceLeft, SystemShortcut.showDesktop,
        ].map(\.localizedName))
        XCTAssertEqual((controller.freezeToggle as? NSSwitch)?.state, .off)
        XCTAssertEqual(controller.previewView.face.places.map(\.title), ShortcutRingFace(.default).places.map(\.title))
        XCTAssertEqual(controller.previewView.face.filled, Array(repeating: true, count: 8))
        XCTAssertNil(controller.previewView.face.places[4].image, "the app's icon is gone from the drawing")
        XCTAssertEqual(ShortcutRingController.preparedFace?.ring, .default, "the ring on screen gets the same face")

        // What opens the ring: as it was.
        XCTAssertEqual(Options.shared.buttons.binding, bindings)
        XCTAssertEqual(controller.triggerRow.explanation, opens)
        XCTAssertEqual(controller.triggerButton.title, "Change")

        XCTAssertFalse(controller.resetToDefaultsButton.isEnabled, "nothing differs any more")
        XCTAssertEqual(controller.resetToDefaultsButton.title, "Reset to Defaults", "in no window there is no Undo to offer")
    }

    /// After a reset the button reads "Undo Reset" and brings back exactly the ring that
    /// was there, places and switch; Edit › Undo and Redo ("Reset Shortcut Ring") do the
    /// same. A change, or the pane going away, makes it "Reset to Defaults" again.
    func testAfterAResetTheButtonOffersToUndoItAndUndoBringsBackTheRing() throws {
        Options.shared.ring = changedRing
        let before = Options.shared.ring
        let (controller, undo) = makeControllerWithUndo()
        let button = controller.resetToDefaultsButton
        let shownBefore = shownActions(controller)
        XCTAssertEqual(button.title, "Reset to Defaults")
        XCTAssertTrue(button.isEnabled)
        XCTAssertFalse(controller.resetToDefaults.offersUndo)

        click(button, undo)
        XCTAssertEqual(Options.shared.ring, .default)
        XCTAssertTrue(controller.resetToDefaults.offersUndo)
        XCTAssertEqual(button.title, "Undo Reset")
        XCTAssertTrue(button.isEnabled, "not greyed out although nothing differs")
        XCTAssertEqual(undo.undoMenuItemTitle, "Undo Reset Shortcut Ring")

        // "Undo Reset": every place and the switch are back, and shown.
        send(button)
        XCTAssertEqual(Options.shared.ring, before)
        XCTAssertEqual(Options.shared.ring[4].openTarget?.path, "/System/Applications/Calculator.app")
        XCTAssertTrue(Options.shared.ring.freezePointer)
        XCTAssertEqual(shownActions(controller), shownBefore)
        XCTAssertEqual((controller.freezeToggle as? NSSwitch)?.state, .on)
        XCTAssertEqual(controller.previewView.face.places[0].title, "Undo")
        XCTAssertTrue(controller.previewView.face.places[3].isEmpty)
        XCTAssertFalse(controller.resetToDefaults.offersUndo)
        XCTAssertEqual(button.title, "Reset to Defaults")
        XCTAssertTrue(button.isEnabled)
        XCTAssertTrue(undo.canRedo)
        XCTAssertEqual(undo.redoMenuItemTitle, "Redo Reset Shortcut Ring")

        // Edit › Redo resets again, Edit › Undo takes that back too.
        undo.redo()
        XCTAssertEqual(Options.shared.ring, .default)
        XCTAssertEqual(shownActions(controller)[0], "Mission Control")
        XCTAssertFalse(button.isEnabled)
        undo.undo()
        XCTAssertEqual(Options.shared.ring, before)
        XCTAssertTrue(button.isEnabled)

        // A change after a reset ends the offer: the next click resets, it does not undo.
        click(button, undo)
        XCTAssertTrue(controller.resetToDefaults.offersUndo)
        let popUp = controller.placePopUps[2]
        popUp.shortcutSelected(try XCTUnwrap(item("undo", in: popUp)))
        XCTAssertFalse(controller.resetToDefaults.offersUndo)
        XCTAssertEqual(button.title, "Reset to Defaults")
        XCTAssertTrue(button.isEnabled)
        click(button, undo)
        XCTAssertEqual(Options.shared.ring, .default, "a reset")
        XCTAssertTrue(controller.resetToDefaults.offersUndo)

        // The ring changed behind the pane's back: the click still resets.
        Options.shared.ring.freezePointer = true
        click(button, undo)
        XCTAssertEqual(Options.shared.ring, .default, "a reset, not an Undo of the one before")

        // The pane goes away: the offer goes with it.
        XCTAssertTrue(controller.resetToDefaults.offersUndo)
        controller.viewDidDisappear()
        XCTAssertFalse(controller.resetToDefaults.offersUndo)
        XCTAssertEqual(button.title, "Reset to Defaults")
        XCTAssertFalse(button.isEnabled)
    }

    /// The offer lasts a moment (eight seconds, as in Scrolling) and ends by itself; the
    /// reset stays under Edit › Undo.
    func testTheUndoOfferEndsByItselfAndEditUndoStillWorks() {
        Options.shared.ring = changedRing
        let before = Options.shared.ring
        XCTAssertEqual(makeController().resetToDefaults.undoOfferDuration, 8)
        XCTAssertEqual(PreferencesScrollingViewController().undoOfferDuration, 8, "the same moment")
        let (controller, undo) = makeControllerWithUndo()
        controller.resetToDefaults.undoOfferDuration = 0.05
        let button = controller.resetToDefaultsButton

        click(button, undo)
        XCTAssertEqual(button.title, "Undo Reset")
        let deadline = Date().addingTimeInterval(10)
        while controller.resetToDefaults.offersUndo, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertFalse(controller.resetToDefaults.offersUndo)
        XCTAssertEqual(button.title, "Reset to Defaults")
        XCTAssertFalse(button.isEnabled, "nothing differs from a new ring")
        XCTAssertEqual(Options.shared.ring, .default, "the reset stays")

        XCTAssertEqual(undo.undoMenuItemTitle, "Undo Reset Shortcut Ring")
        undo.undo()
        XCTAssertEqual(Options.shared.ring, before)
        XCTAssertTrue(button.isEnabled)
    }

    /// In no window there is no undo manager and so no Undo to offer: the button stays
    /// "Reset to Defaults", greyed out after a reset. In the window, the window's takes it.
    func testWithoutUndoTheButtonOffersNoneAndInTheWindowTheWindowsTakesIt() {
        Options.shared.ring = changedRing
        let controller = makeController()
        XCTAssertNil(controller.undoTarget)
        send(controller.resetToDefaultsButton)
        XCTAssertEqual(Options.shared.ring, .default)
        XCTAssertFalse(controller.resetToDefaults.offersUndo)
        XCTAssertEqual(controller.resetToDefaultsButton.title, "Reset to Defaults")
        XCTAssertFalse(controller.resetToDefaultsButton.isEnabled)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 800), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(controller.view)
        XCTAssertTrue(controller.undoTarget === window.undoManager)
        controller.view.removeFromSuperview()
        window.close()
    }

    /// "Undo Reset" takes back only the reset: with something else on top of the Undo stack
    /// (a button removed under Buttons, in the same window) it does nothing.
    func testUndoResetLeavesAnotherUndoAlone() {
        Options.shared.ring = changedRing
        let (controller, undo) = makeControllerWithUndo()
        let button = controller.resetToDefaultsButton
        click(button, undo)
        XCTAssertTrue(controller.resetToDefaults.offersUndo)

        var otherUndone = false
        undo.beginUndoGrouping()
        undo.registerUndo(withTarget: self) { _ in otherUndone = true }
        undo.setActionName("Remove Button")
        undo.endUndoGrouping()

        send(button)
        XCTAssertFalse(otherUndone, "not its Undo to take")
        XCTAssertEqual(Options.shared.ring, .default, "the reset stays")
        XCTAssertFalse(controller.resetToDefaults.offersUndo)
        XCTAssertEqual(undo.undoMenuItemTitle, "Undo Remove Button")
    }
}

// MARK: - The Buttons pane's side

final class ShortcutRingButtonsTests: XCTestCase {

    private var savedBindings: [ButtonBinding] = []

    override func setUp() {
        super.setUp()
        savedBindings = Options.shared.buttons.binding
        Options.shared.buttons.binding = []
    }

    override func tearDown() {
        Options.shared.buttons.binding = savedBindings
        ButtonUtils.shared.invalidateCache()
        super.tearDown()
    }

    private func makePane(_ bindings: [ButtonBinding] = []) -> PreferencesButtonsViewController {
        Options.shared.buttons.binding = bindings
        let pane = PreferencesButtonsViewController()
        pane.deviceSource = ButtonsDeviceSource(
            captureStatus: { _ in .normal }, deviceName: { nil }, isBusy: { false }, refresh: {}, warnBluetoothButton: { _ in }
        )
        pane.scrollHoldKeys = { [] }
        pane.startRecording = { _ in }
        pane.stopRecording = {}
        pane.presentOpenTarget = { _, _, _ in }
        pane.openActionMenu = { _ in }
        pane.presentPlaceMenu = { _, _ in }
        pane.showPane = { _ in }
        pane.paneUndoManager = UndoManager()
        _ = pane.view
        return pane
    }

    private func binding(_ type: EventType, _ code: UInt16, modifiers: UInt = 0, action: String = "") -> ButtonBinding {
        return ButtonBinding(
            triggerEvent: RecordedEvent(type: type, code: code, modifiers: modifiers, deviceFilter: nil),
            systemShortcutName: action, isEnabled: !action.isEmpty
        )
    }

    private func ringItem(of pullDown: ButtonActionPullDown) -> NSMenuItem? {
        return pullDown.menu?.items.first {
            ($0.representedObject as? SystemShortcut.Shortcut)?.identifier == SystemShortcut.shortcutRing.identifier
        }
    }

    /// The action menu lists the ring on its own, next to Gesture Navigation, with its
    /// name and symbol, for a mouse button and for a key (a key can open it).
    func testTheActionMenuOffersTheRingToAButtonAndToAKey() throws {
        let control = UInt(CGEventFlags.maskControl.rawValue)
        for trigger in [binding(.mouse, 4), binding(.keyboard, 49, modifiers: control)] {
            let pullDown = ButtonActionPullDown(binding: trigger)
            let item = try XCTUnwrap(ringItem(of: pullDown))
            XCTAssertEqual(item.title, "Shortcut Ring")
            XCTAssertFalse(item.isHidden)
            XCTAssertNotNil(item.image)
            XCTAssertFalse(item.toolTip?.isEmpty ?? true)
            let items = pullDown.menu?.items ?? []
            let gesture = try XCTUnwrap(items.firstIndex { $0 === pullDown.gestureNavigationItem })
            XCTAssertGreaterThan(try XCTUnwrap(items.firstIndex { $0 === item }), gesture)

            var chosen: [SystemShortcut.Shortcut?] = []
            pullDown.onShortcutSelected = { chosen.append($0) }
            pullDown.shortcutSelected(item)
            XCTAssertEqual(chosen.first??.identifier, "shortcutRing")
            XCTAssertEqual(pullDown.binding.systemShortcutName, "shortcutRing")
            XCTAssertTrue(pullDown.binding.isEnabled)
            XCTAssertEqual(pullDown.menu?.items.first?.title, "Shortcut Ring")
        }
    }

    /// Under a row with the ring, a line says what it does and where its shortcuts are.
    func testARowWithTheRingSaysWhereItsShortcutsAre() throws {
        let ring = binding(.mouse, 4, action: "shortcutRing")
        let pane = makePane([ring, binding(.mouse, 3, action: "copy")])
        let row = try XCTUnwrap(pane.rows.first { $0.binding.id == ring.id })
        XCTAssertEqual(row.explanation, "Opens the ring at the pointer. Set its shortcuts under Shortcut Ring.")
        XCTAssertEqual(pane.ringTriggerBinding?.id, ring.id)
        XCTAssertTrue(pane.selectRingTrigger())
        XCTAssertFalse(makePane([binding(.mouse, 3, action: "copy")]).selectRingTrigger(), "nothing opens the ring")
    }

    /// Shortcut Ring › Set Up…: what is recorded gets the ring, a mouse button or a key
    /// (Gesture Navigation refuses a key; the ring does not).
    func testSetUpGivesTheRecordedButtonOrKeyTheRing() throws {
        let pane = makePane()
        pane.beginAddingBinding(action: SystemShortcut.shortcutRing)
        let control = CGEventFlags.maskControl
        let key = InputEvent(type: .keyboard, code: 49, modifiers: control, phase: .down, source: .hidPP, device: nil)
        XCTAssertTrue(pane.validateRecordedEvent(KeyRecorder(), event: key), "a key can open the ring")
        XCTAssertNil(pane.refusalHint(KeyRecorder(), event: key))
        XCTAssertFalse(PreferencesButtonsViewController.needsMouseButton(SystemShortcut.shortcutRing))

        let trigger = RecordedEvent(type: .keyboard, code: 49, modifiers: UInt(control.rawValue), deviceFilter: nil)
        pane.addBinding(for: trigger, action: SystemShortcut.shortcutRing)
        let stored = try XCTUnwrap(Options.shared.buttons.binding.first)
        XCTAssertEqual(stored.systemShortcutName, "shortcutRing")
        XCTAssertEqual(stored.triggerEvent.type, .keyboard)
        XCTAssertTrue(stored.isEnabled)
        XCTAssertTrue(StoredAction.isKnown(stored))
    }
}
