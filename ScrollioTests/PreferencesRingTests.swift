//
//  PreferencesRingTests.swift
//  ScrollioTests
//
//  The Shortcut Ring pane: its row for what opens the ring and its way to the Buttons
//  pane, the eight places with their pull-downs, what the pull-downs offer and store, the
//  drawing that follows the row pointed at and edits a place where it is drawn (its menu at
//  the drop, "Swap With" and "Clear"), "Reset to Defaults" with its Undo; and the
//  Buttons pane's side: the action in its menu, for a button and for a key. Nothing is
//  shown on screen (one test sends a click through a window that is out of sight, as the
//  Welcome Guide's tests do).
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
        XCTAssertEqual(controller.sections.count, 4, "the two cards, what opens the ring, the places, the footer")
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
    /// only held, the Logitech actions, Gesture Navigation, the ring itself. ("Swap With",
    /// which ends the menu, is the pane's own: `testEveryPlacesOwnMenuEndsWithSwapWith`.)
    func testAPullDownOffersWhatAPlaceCanHoldAndNothingElse() throws {
        let controller = makeController()
        let menu = try XCTUnwrap(controller.placePopUps[0].menu)
        let top = menu.items.dropFirst().filter { !$0.isSeparatorItem && $0 !== controller.placePopUps[0].trailingItem }
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
        popUp.onCustomShortcutRecorded?(ButtonActionPullDown.bindingName(forRecorded: command), nil)
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
            popUp.onCustomShortcutRecorded?(name, nil)
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
        XCTAssertEqual(controller.triggerButton.shownTitle, "Choose")
        XCTAssertEqual(controller.triggerButton.accessibilityLabel(), "Button or key", "named by the row")
        var opened = 0
        controller.openButtonsPane = { opened += 1 }
        XCTAssertTrue(controller.triggerButton.chooseItemForTests(TriggerChooser.Identifier.showInButtons))
        XCTAssertEqual(opened, 1)
    }

    /// Two triggers: the pull-down says so and offers "Show in Buttons" only (which one
    /// stays is decided there).
    func testWithTwoTriggersTheRowNamesThemAndOffersOnlyShowInButtons() {
        summary = ShortcutRingBindingSummary(triggerTitles: ["Thumb panel", "⌃⌥ Space"])
        let controller = makeController()
        XCTAssertEqual(controller.triggerRow.explanation,
                       "Thumb panel and ⌃⌥ Space. A key combination works too, even one that Logi Options+ sends for a button.")
        XCTAssertEqual(controller.triggerButton.shownTitle, "Multiple")
        XCTAssertEqual(controller.triggerButton.menu?.items.dropFirst().map(\.title), ["Show in Buttons"])
        var opened = 0
        controller.openButtonsPane = { opened += 1 }
        XCTAssertTrue(controller.triggerButton.chooseItemForTests(TriggerChooser.Identifier.showInButtons))
        XCTAssertEqual(opened, 1)
    }

    // MARK: Folded while nothing opens the ring

    private func rect(_ view: NSView, in controller: NSViewController) -> NSRect {
        return controller.view.convert(view.alignmentRect(forFrame: view.frame), from: view.superview)
    }

    /// Nothing opens the ring: the places are folded under "Shortcuts ›"; the cards, what
    /// opens the ring with the freeze switch, and "Reset to Defaults" stay.
    func testWithNothingThatOpensTheRingThePlacesAreFoldedUnderTheirTitle() throws {
        let controller = makeController()
        controller.view.layoutSubtreeIfNeeded()
        let places = try XCTUnwrap(controller.placesSection)
        XCTAssertTrue(controller.sections[2] === places)
        XCTAssertTrue(places.isCollapsible)
        XCTAssertFalse(places.showsBody)
        XCTAssertFalse(places.disclosure.isHidden)
        XCTAssertEqual(places.disclosure.label.stringValue, "Shortcuts")
        XCTAssertEqual(places.disclosure.accessibilityRole(), .disclosureTriangle)
        XCTAssertEqual(places.disclosure.accessibilityValue() as? NSNumber, 0, "collapsed")
        for row in controller.placeRows {
            XCTAssertTrue(row.isHiddenOrHasHiddenAncestor)
        }
        XCTAssertTrue(controller.placesHintLabel.isHiddenOrHasHiddenAncestor)
        for view in [controller.headerView!, controller.triggerRow!, controller.freezeRow!, controller.resetToDefaultsButton] as [NSView] {
            XCTAssertFalse(view.isHiddenOrHasHiddenAncestor)
        }
        // The title line alone, a section's room above it and the footer's under it.
        XCTAssertEqual(rect(places, in: controller).height, places.disclosure.label.fittingSize.height, accuracy: 0.5)
        let trigger = controller.sections[1]
        XCTAssertEqual(rect(trigger, in: controller).minY - rect(places, in: controller).maxY, PreferencesGroupedForm.sectionSpacing, accuracy: 0.5)
        let footer = try XCTUnwrap(controller.sections.last)
        XCTAssertEqual(rect(places, in: controller).minY - rect(footer, in: controller).maxY, PreferencesGroupedForm.sectionSpacing, accuracy: 0.5)
        XCTAssertEqual(controller.view.frame.size, controller.view.fittingSize)
        XCTAssertFalse(controller.view.hasAmbiguousLayout)
    }

    /// A click on the title opens the places, the pane grows to them, and they are edited
    /// as ever; another folds them again.
    func testAClickOpensThePlacesAndTheyCanBeEdited() throws {
        let controller = makeController()
        let places = try XCTUnwrap(controller.placesSection)
        places.prefersReducedMotion = { true }
        let folded = controller.view.frame.height

        XCTAssertTrue(places.disclosure.accessibilityPerformPress())
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertTrue(places.showsBody)
        XCTAssertFalse(places.disclosure.isHidden, "still a disclosure: nothing opens the ring")
        XCTAssertEqual(places.disclosure.chevron.turn, 1)
        for row in controller.placeRows {
            XCTAssertFalse(row.isHiddenOrHasHiddenAncestor)
        }
        XCTAssertGreaterThan(controller.view.frame.height, folded + 300, "the pane fits the rows")
        XCTAssertEqual(controller.view.frame.size, controller.view.fittingSize)

        let popUp = controller.placePopUps[1]
        popUp.shortcutSelected(try XCTUnwrap(item("undo", in: popUp)))
        XCTAssertEqual(Options.shared.ring[1].action, "undo")
        XCTAssertTrue(places.showsBody, "editing keeps them open")

        XCTAssertTrue(places.disclosure.accessibilityPerformPress())
        XCTAssertFalse(places.showsBody)
        XCTAssertEqual(controller.view.frame.height, folded, accuracy: 0.5)
    }

    /// Once a binding of Buttons opens the ring, or only an app's own one, the places show
    /// by themselves under a plain title; without one again they are folded.
    func testOnceSomethingOpensTheRingThePlacesShowUnderAPlainTitle() throws {
        let controller = makeController()
        let places = try XCTUnwrap(controller.placesSection)
        let folded = controller.view.frame.height
        let notes = ApplicationTriggers(applicationNames: ["Notes"], triggerTitles: ["Back button"], path: "/System/Applications/Notes.app")
        for opens in [
            ShortcutRingBindingSummary(triggerTitles: ["Thumb panel"]),
            ShortcutRingBindingSummary(triggerTitles: [], onlyInApps: notes),
        ] {
            summary = opens
            controller.reload()
            XCTAssertFalse(places.isCollapsible)
            XCTAssertTrue(places.showsBody)
            XCTAssertFalse(places.titleLabel.isHidden)
            XCTAssertEqual(places.titleLabel.stringValue, "Shortcuts")
            XCTAssertTrue(places.disclosure.isHidden, "no chevron")
            XCTAssertFalse(controller.placeRows[0].isHiddenOrHasHiddenAncestor)
            XCTAssertEqual(controller.view.frame.size, controller.view.fittingSize)
        }

        summary = ShortcutRingBindingSummary(triggerTitles: [])
        controller.reload()
        XCTAssertTrue(places.isCollapsible)
        XCTAssertFalse(places.showsBody)
        XCTAssertEqual(controller.view.frame.height, folded, accuracy: 0.5)
    }

    /// Edit › Undo or Redo of a change made elsewhere (an app's Buttons part, the Buttons
    /// pane) can change what opens the ring while the pane shows: the pane shows it at
    /// once, and its button does what it says.
    func testAnUndoThatChangesWhatOpensTheRingShowsOnThePane() throws {
        summary = ShortcutRingBindingSummary(triggerTitles: [])
        let controller = makeController()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 900), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        addTeardownBlock { window.close() }
        let places = try XCTUnwrap(controller.placesSection)
        XCTAssertEqual(controller.triggerButton.shownTitle, "Choose")
        XCTAssertTrue(places.isCollapsible)

        let notes = ApplicationTriggers(applicationNames: ["Notes"], triggerTitles: ["Back button"], path: "/System/Applications/Notes.app")
        let opens = ShortcutRingBindingSummary(triggerTitles: [], onlyInApps: notes)
        let none = ShortcutRingBindingSummary(triggerTitles: [])
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        undo.registerUndo(withTarget: self) { [weak undo] test in
            test.summary = opens
            undo?.registerUndo(withTarget: test) { $0.summary = none }
        }
        undo.endUndoGrouping()
        undo.undo()
        XCTAssertFalse(places.isCollapsible, "shown at once")
        XCTAssertEqual(controller.triggerRow.explanation, "Only in Notes: Back button. A key combination works too.")
        XCTAssertEqual(controller.triggerButton.shownTitle, "Choose", "nothing of Buttons opens it")
        undo.redo()
        XCTAssertTrue(places.isCollapsible)

        // "Show in Buttons" goes where the row says, also when the bindings changed unseen.
        var opened = 0
        controller.openButtonsPane = { opened += 1 }
        controller.openApplicationButtons = { _ in XCTFail("the row says that nothing opens the ring") }
        summary = opens
        XCTAssertTrue(controller.triggerButton.chooseItemForTests(TriggerChooser.Identifier.showInButtons))
        XCTAssertEqual(opened, 1)
    }

    /// A click on a place of the drawing while the places are folded opens that place's
    /// menu at its drop and leaves them folded: the tick is what the place holds, and a
    /// listed action chosen there changes the store, the (hidden) row and the drawing, with
    /// one "Undo Change Action".
    func testAClickOnADropLeavesFoldedPlacesFolded() throws {
        let controller = makeController()
        _ = show(controller)
        let places = try XCTUnwrap(controller.placesSection)
        XCTAssertFalse(places.showsBody, "nothing opens the ring: folded")
        let size = controller.view.frame.size
        let undo = UndoManager()
        undo.groupsByEvent = false
        controller.paneUndoManager = undo
        let popUp = controller.placePopUps[4]
        let chosen = try XCTUnwrap(item("undo", in: popUp))
        var ticked: [String?] = []
        controller.presentPlaceMenu = { menu, _, _ in
            // As AppKit runs a menu: it opens, an item is chosen, it closes.
            popUp.menuWillOpen(menu)
            ticked = [popUp.shownActionItem?.item, popUp.shownActionItem?.category].map { item in
                item.flatMap { $0.state == .off ? nil : ($0.representedObject as? SystemShortcut.Shortcut)?.identifier ?? $0.title }
            }
            undo.beginUndoGrouping()
            popUp.shortcutSelected(chosen)
            undo.endUndoGrouping()
            popUp.menuDidClose(menu)
        }
        controller.previewView.onPlaceClicked?(4)
        XCTAssertEqual(ticked.first, "appExpose", "the tick is what the place holds")
        XCTAssertNotNil(ticked.last ?? nil, "and the dash its category")
        XCTAssertFalse(places.showsBody, "still folded")
        XCTAssertEqual(controller.view.frame.size, size)
        XCTAssertTrue(popUp.isHiddenOrHasHiddenAncestor)
        XCTAssertEqual(controller.selectedPlace, 4)
        XCTAssertEqual(Options.shared.ring[4].action, "undo")
        XCTAssertEqual(popUp.menu?.items.first?.title, "Undo", "the row follows, unseen")
        XCTAssertEqual(controller.previewView.face.places[4].title, "Undo", "the drawing follows")
        XCTAssertEqual(undo.undoMenuItemTitle, "Undo Change Action")
        undo.undo()
        XCTAssertEqual(Options.shared.ring, .default)
        XCTAssertFalse(undo.canUndo, "one step")
    }

    /// An app's page decides itself when its rows fold (`ApplicationRingPartViewController`):
    /// the rows of an app's own ring stand under "Shortcuts", without the pane's line on how
    /// to choose, and do not fold by what opens the general ring.
    func testAnAppsRingHasNoFoldingOfItsOwn() throws {
        let application = Application(path: "/System/Applications/Notes.app")
        let page = RingPreferencesViewController(application: application)
        page.bindingSummary = { ShortcutRingBindingSummary(triggerTitles: []) }
        _ = page.view
        let places = try XCTUnwrap(page.placesSection)
        XCTAssertEqual(places.title, "Shortcuts")
        XCTAssertFalse(places.isCollapsible)
        XCTAssertNil(page.placesHintLabel)
        XCTAssertFalse(page.placeRows[0].isHiddenOrHasHiddenAncestor)
    }

    /// The drawing of an app's own ring shows the app's icon in its middle, as the ring on
    /// screen does; the pane's drawing of the general ring never does. The page makes the
    /// mark once, and hands it to the ring on screen only when that app's own ring can
    /// open (a page that is only looked at pushes out no other app's mark).
    func testTheDrawingOfAnAppsOwnRingShowsTheAppsIcon() throws {
        ShortcutRingController.forgetPreparedFaces()
        defer { ShortcutRingController.forgetPreparedFaces() }
        let savedBindings = Options.shared.buttons.binding
        let savedApplications = Options.shared.application.applications
        defer {
            Options.shared.buttons.binding = savedBindings
            Options.shared.application.applications = savedApplications
        }
        Options.shared.buttons.binding = []
        let path = "/System/Applications/Notes.app"
        let notes = Application(path: path)
        notes.setUsesGeneralRing(false, general: .default)
        Options.shared.application.applications = EnhanceArray(withArray: [notes], matchKey: "path")

        var made: [String] = []
        func page(_ application: Application?) -> RingPreferencesViewController {
            let page = RingPreferencesViewController(application: application)
            page.bindingSummary = { ShortcutRingBindingSummary(triggerTitles: []) }
            page.makeAppMark = { path in
                made.append(path)
                return RingHarness.mark(named: "Notes")
            }
            _ = page.view
            return page
        }
        let own = page(notes)
        let icon = try XCTUnwrap(own.previewView.appIcon, "the app's own ring")
        XCTAssertEqual(made, [path])
        XCTAssertNil(ShortcutRingController.preparedAppMark(forPath: path), "nothing opens its ring: not handed on")
        own.setPlace(ShortcutRingPlace(SystemShortcut.copy), at: 0)
        XCTAssertTrue(own.previewView.appIcon === icon)
        XCTAssertEqual(made, [path], "made once")

        // A place lit: its name stands in the middle instead (the artwork draws one or the other).
        own.placePointedAt(2)
        XCTAssertEqual(own.previewView.lit, 2)
        own.placePointedAt(nil)

        XCTAssertNil(page(nil).previewView.appIcon, "the pane's general ring")
        let usesGeneral = Application(path: "/System/Applications/Maps.app")
        XCTAssertNil(page(usesGeneral).previewView.appIcon, "an app that uses the general ring")
        XCTAssertEqual(made, [path])

        // Something opens the ring: the page hands the mark on to the ring on screen, and a
        // page that comes later takes that one.
        Options.shared.buttons.binding = [ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 4, modifiers: 0, deviceFilter: nil),
            systemShortcutName: SystemShortcut.shortcutRing.identifier, isEnabled: true
        )]
        let second = page(notes)
        XCTAssertEqual(made, [path, path])
        let handedOn = try XCTUnwrap(ShortcutRingController.preparedAppMark(forPath: path))
        XCTAssertTrue(second.previewView.appIcon === handedOn.icon)
        XCTAssertTrue(page(notes).previewView.appIcon === handedOn.icon)
        XCTAssertEqual(made, [path, path], "the ring's mark is taken, not made again")
    }

    /// The icon in the drawing is half faint, and whole under Increase Contrast or Reduce
    /// Transparency, as on screen.
    func testTheIconInTheDrawingIsFaintUnlessContrastOrNoTransparency() throws {
        let preview = ShortcutRingPreviewView(frame: NSRect(x: 0, y: 0, width: 460, height: ShortcutRingPreviewView.preferredHeight))
        preview.face = ShortcutRingFace(.default)
        let icon = NSImage(size: NSSize(width: 40, height: 40), flipped: false) { rect in
            NSColor.black.setFill()
            rect.fill()
            return true
        }
        var reduces = false
        preview.reducesTransparency = { reduces }
        /// How bright the drawing's middle is (the icon, black over the light hub), drawn
        /// now into a bitmap of its own.
        func middle(appearance name: NSAppearance.Name) throws -> CGFloat {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            preview.appearance = appearance
            let rep = try XCTUnwrap(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(preview.bounds.width), pixelsHigh: Int(preview.bounds.height),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            appearance.performAsCurrentDrawingAppearance { preview.draw(preview.bounds) }
            NSGraphicsContext.restoreGraphicsState()
            let colour = try XCTUnwrap(rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)?.usingColorSpace(.sRGB))
            return colour.brightnessComponent
        }
        let empty = try middle(appearance: .aqua)
        preview.appIcon = icon
        let faint = try middle(appearance: .aqua)
        reduces = true
        let whole = try middle(appearance: .aqua)
        reduces = false
        XCTAssertGreaterThan(empty, 0.9, "the light hub")
        XCTAssertGreaterThan(faint, 0.35, "the icon is faint: the hub shows through")
        XCTAssertLessThan(faint, empty - 0.3, "the icon is there")
        XCTAssertLessThan(whole, 0.05, "Reduce Transparency: the whole icon")
        // (Some systems hand out the plain appearance while Increase Contrast is off.)
        if NSAppearance(named: .accessibilityHighContrastAqua)?.name.rawValue.contains("Accessibility") == true {
            XCTAssertLessThan(try middle(appearance: .accessibilityHighContrastAqua), 0.05, "Increase Contrast: the whole icon")
        }
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

    /// The mouse never tracks what opens the ring (that button always has another job
    /// than Gesture Navigation), so the ring's own Freeze switch decides for every hold:
    /// "Let the mouse track the gesture" changes nothing about it, in the pane or in an
    /// app's own ring.
    func testTheRingsFreezeIgnoresTracking() throws {
        let savedGesture = Options.shared.gesture
        let savedBindings = Options.shared.buttons.binding
        defer {
            Options.shared.gesture = savedGesture
            Options.shared.buttons.binding = savedBindings
        }
        func binding(_ code: UInt16, _ action: String, modifiers: UInt = 0) -> ButtonBinding {
            return ButtonBinding(
                triggerEvent: RecordedEvent(type: .mouse, code: code, modifiers: modifiers, deviceFilter: nil),
                systemShortcutName: action, isEnabled: true
            )
        }
        let ring = SystemShortcut.shortcutRing.identifier
        let gestures = SystemShortcut.mouseGestureNavigation.identifier
        let gestureButton = LogiCenter.shared.scrollioCode(for: .gesture)
        let thumbPanel = LogiCenter.shared.scrollioCode(for: .thumbPanel)
        let option = UInt(CGEventFlags.maskAlternate.rawValue)
        // The ring on its own button, and on the gesture button with ⌥.
        let bindings = [binding(gestureButton, gestures), binding(thumbPanel, ring)]
        let shared = [binding(gestureButton, gestures), binding(gestureButton, ring, modifiers: option)]
        XCTAssertEqual(
            LogiUsageBootstrap.gestureTrackingCodes(deviceTracking: true, bindings: bindings, scrollHotkeyCodes: []), [gestureButton],
            "never the button that opens the ring"
        )
        XCTAssertEqual(LogiUsageBootstrap.gestureTrackingCodes(deviceTracking: true, bindings: shared, scrollHotkeyCodes: []), [])

        Options.shared.gesture.deviceTracking = true
        Options.shared.buttons.binding = bindings
        Options.shared.ring.freezePointer = false
        let controller = makeController()
        let toggle = try XCTUnwrap(controller.freezeToggle as? NSSwitch)
        XCTAssertEqual(toggle.state, .off, "the stored value")
        XCTAssertTrue(toggle.isEnabled)
        XCTAssertTrue(controller.freezeRow.isEnabled)
        XCTAssertEqual(controller.freezeRow.explanation, NSLocalizedString("ring-freeze-pointer-hint", comment: ""))
        toggle.state = .on
        controller.freezeToggled(toggle)
        XCTAssertTrue(Options.shared.ring.freezePointer)

        // An app's own ring: its own switch, the same.
        let notes = Application(path: "/System/Applications/Notes.app")
        notes.setUsesGeneralRing(false, general: Options.shared.ring)
        notes.setOwnRingFreezePointer(false)
        let own = RingPreferencesViewController(application: notes)
        own.bindingSummary = { [unowned self] in self.summary }
        _ = own.view
        let ownToggle = try XCTUnwrap(own.freezeToggle as? NSSwitch)
        XCTAssertEqual(ownToggle.state, .off)
        XCTAssertTrue(ownToggle.isEnabled)
        XCTAssertTrue(own.freezeRow.isEnabled)
        XCTAssertEqual(own.freezeRow.explanation, NSLocalizedString("ring-freeze-pointer-hint", comment: ""))
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
                       "The pointer stays where it is while you hold the button or key. The way your hand moves still chooses.")
        XCTAssertTrue(controller.freezeRow.accessory === controller.freezeToggle)
        let toggle = try XCTUnwrap(controller.freezeToggle as? NSSwitch)
        XCTAssertEqual(toggle.state, .off, "a new ring leaves the pointer alone")

        toggle.state = .on
        controller.freezeToggled(toggle)
        XCTAssertTrue(Options.shared.ring.freezePointer)
        XCTAssertEqual(Options.shared.ring.places, ShortcutRingSettings.default.places, "the places stay")
        XCTAssertEqual(Options.shared.gesture.freezePointer, gestureFreeze, "Gestures keeps its own switch")
        XCTAssertNil(ShortcutRingController.preparedFace(for: Options.shared.ring),
                     "a ring that opens nothing keeps no face: at a press it is whole without a look on disk")
        XCTAssertEqual((makeController().freezeToggle as? NSSwitch)?.state, .on, "a pane made later shows it")

        toggle.state = .off
        controller.freezeToggled(toggle)
        XCTAssertFalse(Options.shared.ring.freezePointer)
        XCTAssertEqual(Options.shared.ring, .default)
    }

    func testEveryExplanationFitsTwoLines() throws {
        let font = PreferencesGroupedForm.explanationFont
        let twoLines = 2 * ceil(font.ascender - font.descender + font.leading) + 2
        func height(_ text: String, width: CGFloat) -> CGFloat {
            return (text as NSString).boundingRect(
                with: NSSize(width: width, height: 1000), options: [.usesLineFragmentOrigin], attributes: [.font: font]
            ).height
        }
        // Also while only apps' own buttons open it ("Only in Figma: Thumb panel.").
        let onlyInApps: [ApplicationTriggers?] = [
            nil, nil, nil,
            ApplicationTriggers(applicationNames: ["Figma"], triggerTitles: ["Thumb panel"]),
            ApplicationTriggers(applicationNames: ["Figma", "Safari"], triggerTitles: ["Thumb panel", "⌃⌥ Space"]),
        ]
        for (titles, apps) in zip([[], ["Thumb panel", "⌃⌥ Space"], ["Middle button", "Thumb panel", "⌃⌥ Space"], [], []], onlyInApps) {
            summary = ShortcutRingBindingSummary(triggerTitles: titles, onlyInApps: apps)
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
        // An app's own ring has the same switch and line on the app's page.
        let calculator = Application(path: "/System/Applications/Calculator.app")
        calculator.setUsesGeneralRing(false, general: .default)
        let own = RingPreferencesViewController(application: calculator)
        own.view.layoutSubtreeIfNeeded()
        let ownFreeze = try XCTUnwrap(own.freezeRow?.explanationLabel)
        XCTAssertEqual(ownFreeze.stringValue, freeze.stringValue)
        XCTAssertGreaterThan(ownFreeze.frame.width, 200)
        XCTAssertLessThanOrEqual(height(ownFreeze.stringValue, width: ownFreeze.frame.width), twoLines, "on an app's page")
        let hint = controller.placesHintLabel.stringValue
        // Two sentences, each on its own line (wrapped as one text, the second line was two words).
        // ("the button or key": the row above is titled so, and a key may be what opens the ring.)
        XCTAssertEqual(hint, "Hold the button or key and move towards a shortcut, then let go.\nOr press and let go, then click one.")
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
    /// on it opens its menu there and selects its row (the place stays lit; the keyboard
    /// stays where it was).
    func testAPlaceOfTheDrawingCanBePointedAtAndClicked() throws {
        let controller = makeController()
        let window = show(controller)
        let preview = try XCTUnwrap(controller.previewView)
        XCTAssertEqual(preview.bounds.size, NSSize(width: 234, height: 206), "the right card of the two")

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

        var menus: [NSMenu] = []
        controller.presentPlaceMenu = { menu, _, _ in menus.append(menu) }
        preview.onPlaceClicked?(6)
        XCTAssertEqual(controller.selectedPlace, 6)
        XCTAssertEqual(preview.lit, 6, "the selected row's place stays lit")
        XCTAssertEqual(menus.count, 1)
        XCTAssertTrue(menus.first === controller.placePopUps[6].menu, "its menu opened")
        XCTAssertFalse(window.firstResponder === controller.placePopUps[6], "the keyboard stays where it was")
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

    // MARK: The drawing as an editor

    /// The pane in a window that is never shown, laid out.
    private func show(_ controller: NSViewController) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 900), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        addTeardownBlock { window.close() }
        controller.view.layoutSubtreeIfNeeded()
        return window
    }

    private func middle(ofPlace place: Int, in preview: ShortcutRingPreviewView) -> NSPoint {
        let drop = preview.dropRect(ofPlace: place)
        return NSPoint(x: drop.midX, y: drop.midY)
    }

    private func mouse(
        _ type: NSEvent.EventType, at point: NSPoint, in view: NSView, flags: NSEvent.ModifierFlags = []
    ) throws -> NSEvent {
        return try XCTUnwrap(NSEvent.mouseEvent(
            with: type, location: view.convert(point, to: nil), modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: view.window?.windowNumber ?? 0, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1
        ))
    }

    /// The items of "Swap With", filled as AppKit fills them before the submenu shows.
    private func swaps(of item: NSMenuItem?) throws -> [NSMenuItem] {
        let submenu = try XCTUnwrap(item?.submenu)
        submenu.delegate?.menuNeedsUpdate?(submenu)
        return submenu.items
    }

    private func choose(_ item: NSMenuItem) throws {
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item))
    }

    private func picture(of view: NSView) throws -> Data {
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    /// What "Swap With" and "Clear" offer, from a ring and a place alone: the seven other
    /// places clockwise from the top, named in Title Case with what each holds ("No Action"
    /// for none); a swap that would show nothing new is off, and so is Clear on a place
    /// that holds nothing.
    func testTheMenuModelNamesTheSevenOtherPlacesAndKnowsWhatChangesNothing() {
        var ring = ShortcutRingSettings(places: [])
        ring[0] = ShortcutRingPlace(SystemShortcut.copy)
        ring[3] = ShortcutRingPlace(SystemShortcut.copy)
        ring[4] = ShortcutRingPlace(action: "somethingNewer")
        ring[7] = ShortcutRingPlace(SystemShortcut.paste)
        let names: (ShortcutRingPlace) -> String? = { $0.runs ? $0.action.uppercased() : nil }

        let top = RingPlaceMenuModel.make(for: 0, in: ring, name: names)
        XCTAssertEqual(top.place, 0)
        XCTAssertEqual(top.swaps.map(\.place), [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(top.swaps.map(\.title), [
            "Top Right (No Action)", "Right (No Action)", "Bottom Right (COPY)", "Bottom (No Action)",
            "Bottom Left (No Action)", "Left (No Action)", "Top Left (PASTE)",
        ])
        XCTAssertEqual(top.swaps.map(\.isEnabled), [true, true, false, true, true, true, true], "Bottom Right holds the same")
        XCTAssertTrue(top.canClear)

        let empty = RingPlaceMenuModel.make(for: 1, in: ring, name: names)
        XCTAssertEqual(empty.swaps.map(\.place), [0, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(empty.swaps.first?.title, "Top (COPY)")
        XCTAssertEqual(empty.swaps.map(\.isEnabled), [true, false, true, false, false, false, true], "only with a place that holds something")
        XCTAssertFalse(empty.canClear)
        XCTAssertFalse(RingPlaceMenuModel.make(for: 4, in: ring, name: names).canClear, "what this version does not run shows as nothing")

        XCTAssertEqual((0..<8).map(RingPlaceMenuModel.menuTitle(ofPlace:)), [
            "Top", "Top Right", "Right", "Bottom Right", "Bottom", "Bottom Left", "Left", "Top Left",
        ])
        // What a row shows: the action's name, a named shortcut's name without its keys.
        XCTAssertEqual(RingPlaceMenuModel.shownName(of: ring[0]), "Copy")
        XCTAssertNil(RingPlaceMenuModel.shownName(of: .empty))
        XCTAssertNil(RingPlaceMenuModel.shownName(of: ring[4]))
        let named = ShortcutRingPlace(action: "custom::1:1048576", label: ShortcutLabel(name: "Save All", icon: nil))
        XCTAssertEqual(RingPlaceMenuModel.shownName(of: named), "Save All")
    }

    /// A click on a drop opens that place's own menu under the drop's circle at rest: the
    /// row's menu object, without its title item while it is open. The place is selected
    /// and lit; nothing takes the keyboard.
    func testAClickOnAPlaceOfTheDrawingOpensItsRowsMenuAtTheDrop() throws {
        summary = ShortcutRingBindingSummary(triggerTitles: ["Thumb panel"])
        let controller = makeController()
        let window = show(controller)
        let preview = try XCTUnwrap(controller.previewView)
        var opened: [(menu: NSMenu, point: NSPoint, view: NSView, titleHidden: Bool?)] = []
        controller.presentPlaceMenu = { menu, point, view in
            opened.append((menu, point, view, menu.items.first?.isHidden))
        }
        XCTAssertTrue(window.makeFirstResponder(controller.placePopUps[2]))

        let drop = preview.dropRect(ofPlace: 6)
        let offset = ShortcutRingGeometry.offset(ofPlace: 6)
        let scale = ShortcutRingPreviewView.ringScale
        XCTAssertEqual(drop.midX, preview.bounds.midX + offset.x * scale, accuracy: 0.01)
        XCTAssertEqual(drop.midY, preview.bounds.midY - offset.y * scale, accuracy: 0.01)
        XCTAssertEqual(drop.size, NSSize(width: 37, height: 37), "the drop at rest, drawn smaller")
        XCTAssertTrue(preview.bounds.contains(drop))

        preview.mouseDown(with: try mouse(.leftMouseDown, at: middle(ofPlace: 6, in: preview), in: preview))
        XCTAssertEqual(opened.count, 1)
        let menu = try XCTUnwrap(controller.placePopUps[6].menu)
        XCTAssertTrue(opened.first?.menu === menu, "the row's own menu, not a copy")
        XCTAssertTrue(opened.first?.view === preview)
        XCTAssertEqual(opened.first?.point, NSPoint(x: drop.minX, y: drop.minY - 4), "under the drop")
        XCTAssertEqual(opened.first?.titleHidden, true, "a menu lists no title")
        XCTAssertEqual(menu.items.first?.isHidden, false, "the pull-down has it back")
        XCTAssertEqual(controller.selectedPlace, 6)
        XCTAssertEqual(preview.lit, 6)
        XCTAssertEqual(controller.placeRows[6].titleLabel.textColor, NSColor.controlAccentColor)
        XCTAssertTrue(window.firstResponder === controller.placePopUps[2], "the keyboard stays where it was")

        // An empty place and a lit one have their menu in the same spot.
        controller.setPlace(.empty, at: 6)
        controller.placePointedAt(6)
        XCTAssertEqual(preview.dropRect(ofPlace: 6), drop)
    }

    /// While a place's menu is open at its drop the title item is hidden: the row's
    /// pull-down goes on showing its action, also when it is drawn again meanwhile and
    /// when the action changes under the open menu.
    func testTheRowKeepsItsTitleWhileItsMenuIsOpenAtADrop() throws {
        summary = ShortcutRingBindingSummary(triggerTitles: ["Thumb panel"])
        let controller = makeController()
        _ = show(controller)
        let popUp = controller.placePopUps[0]
        let other = controller.placePopUps[3]
        controller.setPlace(.empty, at: 3)
        let before = try picture(of: popUp)
        XCTAssertNotEqual(before, try picture(of: other), "the pictures show the titles")
        let chosen = try XCTUnwrap(item("paste", in: popUp))

        var whileOpen: Data?
        var afterChoice: Data?
        var shownTitles: [String] = []
        controller.presentPlaceMenu = { menu, _, _ in
            popUp.menuWillOpen(menu)
            XCTAssertEqual(menu.items.first?.isHidden, true)
            popUp.needsDisplay = true
            whileOpen = try? self.picture(of: popUp)
            shownTitles.append(popUp.title)
            popUp.shortcutSelected(chosen)
            popUp.needsDisplay = true
            afterChoice = try? self.picture(of: popUp)
            shownTitles.append(popUp.title)
            popUp.menuDidClose(menu)
        }
        controller.previewView.onPlaceClicked?(0)
        XCTAssertEqual(whileOpen, before, "drawn as before while its menu is open at the drop")
        XCTAssertEqual(shownTitles, ["Mission Control", "Paste"])
        XCTAssertEqual(Options.shared.ring[0].action, "paste")
        XCTAssertEqual(afterChoice, try picture(of: popUp), "and the new action at once, as after the menu closed")
        XCTAssertNotEqual(afterChoice, before)
    }

    /// What a menu opened at a drop opens stands at that drop: "Open App or File…", the
    /// recorder of "Keyboard Shortcut…" and the name and icon of recorded keys. From the
    /// row's own menu afterwards they stand at the pull-down again. The rows stay folded
    /// through it all: a hidden pull-down still has its window.
    func testWhatAMenuAtADropOpensStandsAtTheDrop() throws {
        Options.shared.ring[5] = ShortcutRingPlace(
            action: "custom::1:1048576", label: try XCTUnwrap(ShortcutLabel(name: "Save All", icon: .symbol("square.and.arrow.down")))
        )
        let controller = makeController()
        _ = show(controller)
        let preview = try XCTUnwrap(controller.previewView)
        let places = try XCTUnwrap(controller.placesSection)
        var targets: [NSView] = []
        controller.presentOpenTarget = { _, anchor, _ in targets.append(anchor) }
        var recorders: [NSView] = []
        var recorderStarted: XCTestExpectation?
        controller.startShortcutRecorder = { pullDown in
            recorders.append(pullDown.popoverAnchor)
            recorderStarted?.fulfill()
        }
        var details: [(anchor: NSView, popover: KeyPopover)] = []
        controller.placePopUps[5].presentShortcutDetails = { popover, anchor, _, _ in details.append((anchor, popover)) }

        /// A click on the drop of `place`, and `marker`'s item chosen in the menu that opens.
        func chooseAtDrop(_ marker: String, place: Int) throws {
            let popUp = controller.placePopUps[place]
            let chosen = try XCTUnwrap(item(marked: marker, in: popUp))
            controller.presentPlaceMenu = { menu, _, _ in
                popUp.menuWillOpen(menu)
                popUp.shortcutSelected(chosen)
                popUp.menuDidClose(menu)
            }
            preview.mouseDown(with: try mouse(.leftMouseDown, at: middle(ofPlace: place, in: preview), in: preview))
        }
        /// The same item from the row's own menu, as the pull-down opens it.
        func chooseAtRow(_ marker: String, place: Int) throws {
            let popUp = controller.placePopUps[place]
            popUp.menuWillOpen(try XCTUnwrap(popUp.menu))
            popUp.shortcutSelected(try XCTUnwrap(item(marked: marker, in: popUp)))
            popUp.menuDidClose(try XCTUnwrap(popUp.menu))
        }
        func waitForRecorder(_ body: () throws -> Void) rethrows {
            let started = expectation(description: "the recorder starts a moment after the menu")
            recorderStarted = started
            try body()
            wait(for: [started], timeout: 5)
            recorderStarted = nil
        }

        // "Open App or File…"
        try chooseAtDrop(ShortcutManager.MenuMarker.openTarget, place: 3)
        let anchor = try XCTUnwrap(targets.first)
        XCTAssertTrue(anchor.superview === preview)
        XCTAssertEqual(anchor.frame, preview.dropRect(ofPlace: 3), "the drop's circle at rest")
        XCTAssertTrue(anchor.isFlipped, "a popover that asks for .maxY stands under it, as under a pull-down")
        XCTAssertTrue(controller.placePopUps[3].isFlipped)
        try XCTUnwrap(controller.openTargetPopover).onCancel?()
        try chooseAtRow(ShortcutManager.MenuMarker.openTarget, place: 3)
        XCTAssertTrue(targets.last === controller.placePopUps[3], "from the row: at the row")
        try XCTUnwrap(controller.openTargetPopover).onCancel?()

        // The recorder of "Keyboard Shortcut…", which starts a moment after the menu closed.
        XCTAssertNotNil(controller.placePopUps[3].window, "the folded pull-down has its window: the recorder starts")
        try waitForRecorder { try chooseAtDrop(ShortcutManager.MenuMarker.keyboardShortcut, place: 3) }
        XCTAssertTrue(recorders.last === anchor)
        controller.placePopUps[3].cancelShortcutRecording()
        try waitForRecorder { try chooseAtRow(ShortcutManager.MenuMarker.keyboardShortcut, place: 3) }
        XCTAssertTrue(recorders.last === controller.placePopUps[3])
        controller.placePopUps[3].cancelShortcutRecording()

        // The name and icon of keys that are there, at another place's drop.
        try chooseAtDrop(ShortcutManager.MenuMarker.keyboardShortcut, place: 5)
        XCTAssertEqual(details.count, 1)
        XCTAssertFalse(details[0].anchor === anchor, "each place has its own")
        XCTAssertEqual(details[0].anchor.frame, preview.dropRect(ofPlace: 5))
        XCTAssertEqual(anchor.frame, preview.dropRect(ofPlace: 3), "the other place's stays where it is")
        details[0].popover.onClose?()
        try chooseAtRow(ShortcutManager.MenuMarker.keyboardShortcut, place: 5)
        XCTAssertTrue(details.last?.anchor === controller.placePopUps[5])
        details.last?.popover.onClose?()

        XCTAssertFalse(places.showsBody, "folded all the while")
        XCTAssertEqual(Options.shared.ring[3], ShortcutRingSettings.default[3], "nothing was stored")
    }

    /// A secondary click on a drop offers "Swap With" (the seven other places clockwise
    /// from the top, each with what its row shows) and "Clear". A swap that would show
    /// nothing new is disabled, and so is Clear on a place that holds nothing. A
    /// Control-click that arrives as a click shows the same menu, never the place's own.
    func testASecondaryClickOffersSwapWithAndClear() throws {
        var ring = ShortcutRingSettings.default
        ring[2] = .empty
        ring[4] = ShortcutRingPlace(action: "somethingNewer")
        ring[5] = ShortcutRingPlace(
            action: "custom::1:1048576", label: try XCTUnwrap(ShortcutLabel(name: "Save All", icon: .symbol("square.and.arrow.down")))
        )
        ring[6] = ShortcutRingPlace(SystemShortcut.missionControl)
        Options.shared.ring = ring
        let controller = makeController()
        _ = show(controller)
        let preview = try XCTUnwrap(controller.previewView)
        controller.presentPlaceMenu = { _, _, _ in XCTFail("the place's own menu is the primary click's") }
        func menu(ofPlace place: Int) throws -> NSMenu {
            return try XCTUnwrap(preview.menu(for: try mouse(.rightMouseDown, at: middle(ofPlace: place, in: preview), in: preview)))
        }

        let top = try menu(ofPlace: 0)
        XCTAssertEqual(top.items.map(\.title), ["Swap With", "Clear"])
        XCTAssertEqual(controller.selectedPlace, 0, "the place is the selected one: it stays lit under the menu")
        XCTAssertEqual(preview.lit, 0)
        let offered = try swaps(of: top.items.first)
        XCTAssertEqual(offered.map(\.title), [
            "Top Right (Screenshot Selection)", "Right (No Action)", "Bottom Right (Paste)", "Bottom (No Action)",
            "Bottom Left (Save All)", "Left (Mission Control)", "Top Left (Show Desktop)",
        ], "Title Case, what the row shows; a named shortcut without its keys")
        XCTAssertEqual(offered.map(\.isEnabled), [true, true, true, true, true, false, true], "Left holds the same")
        XCTAssertTrue(offered.allSatisfy { $0.state == .off })
        XCTAssertEqual(top.items.last?.isEnabled, true)

        // An empty place: nothing to clear, and no swap with a place that shows as empty.
        let right = try menu(ofPlace: 2)
        XCTAssertEqual(right.items.last?.isEnabled, false, "Clear")
        let fromEmpty = try swaps(of: right.items.first)
        XCTAssertEqual(fromEmpty.map(\.title).first, "Top (Mission Control)")
        XCTAssertEqual(fromEmpty.map(\.isEnabled), [true, true, true, false, true, true, true], "Bottom shows as empty too")
        // A place whose action this version does not run holds nothing either.
        let bottom = try menu(ofPlace: 4)
        XCTAssertEqual(bottom.items.last?.isEnabled, false)
        XCTAssertEqual(try swaps(of: bottom.items.first).map(\.isEnabled), [true, true, false, true, true, true, true])

        // Control held: the same menu, through the click.
        var shown: [NSMenu] = []
        preview.presentContextMenu = { menu, _, view in
            XCTAssertTrue(view === preview)
            shown.append(menu)
        }
        preview.mouseDown(with: try mouse(.leftMouseDown, at: middle(ofPlace: 3, in: preview), in: preview, flags: .control))
        XCTAssertEqual(shown.count, 1)
        XCTAssertEqual(shown.first?.items.map(\.title), ["Swap With", "Clear"])
        XCTAssertEqual(try swaps(of: shown.first?.items.first).first?.title, "Top (Mission Control)")
        XCTAssertEqual(controller.selectedPlace, 3)

        // The items do what they say.
        try choose(offered[0])
        XCTAssertEqual(Options.shared.ring[0], ring[1])
        XCTAssertEqual(Options.shared.ring[1], ring[0])
        XCTAssertEqual(controller.selectedPlace, 0, "the place whose menu was used")
        try choose(try XCTUnwrap(shown.first?.items.last))
        XCTAssertTrue(Options.shared.ring[3].isEmpty, "Clear")
    }

    /// How a Control-click reaches a view when it comes through its window, as a real one
    /// does, and that the drawing answers it as the secondary click whichever way AppKit
    /// takes (`menu(for:)`, or the click itself with Control held): it is asked for the
    /// secondary menu of that place and never opens the place's own menu.
    func testAControlClickThroughTheWindowAsksForTheSecondaryMenu() throws {
        // What AppKit does with a Control-click on a view: a probe that hands out no menu
        // (AppKit would show it and wait for a choice) writes down what it is sent. A window
        // hands a click on only once it exists for the system: this one does, out of sight.
        let probe = ControlClickProbe(frame: NSRect(x: 0, y: 0, width: 80, height: 80))
        let probeWindow = OutOfSightWindow(contentRect: probe.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        probeWindow.isReleasedWhenClosed = false
        probeWindow.contentView = probe
        probeWindow.putOutOfSight()
        addTeardownBlock {
            probeWindow.orderOut(nil)
            probeWindow.close()
        }
        let onProbe = NSPoint(x: 40, y: 40)
        probeWindow.sendEvent(try mouse(.leftMouseDown, at: onProbe, in: probe))
        XCTAssertEqual(probe.calls, ["down"], "a plain click arrives as a click")
        probe.calls = []
        probeWindow.sendEvent(try mouse(.leftMouseDown, at: onProbe, in: probe, flags: .control))
        // (On macOS 27.2: `menu(for:)` first, and the click itself when no menu came.)
        let route = probe.calls
        XCTAssertFalse(route.isEmpty, "the Control-click arrived")
        XCTAssertTrue(Set(route).isSubset(of: ["menu", "down", "right down"]))

        // The drawing, sent the same: no menu is handed out here either.
        let controller = makeController()
        _ = show(controller)
        let preview = try XCTUnwrap(controller.previewView)
        var asked: [Int] = []
        var other: [String] = []
        preview.menuForPlace = { place in
            asked.append(place)
            return nil
        }
        preview.onPlaceClicked = { _ in other.append("the place's own menu") }
        preview.presentContextMenu = { _, _, _ in other.append("a menu shown by the click") }
        let click = try mouse(.leftMouseDown, at: middle(ofPlace: 1, in: preview), in: preview, flags: .control)
        for step in route {
            switch step {
            case "menu": XCTAssertNil(preview.menu(for: click))
            case "right down": preview.rightMouseDown(with: click)
            default: preview.mouseDown(with: click)
            }
        }
        XCTAssertFalse(asked.isEmpty, "asked for the secondary menu")
        XCTAssertEqual(Set(asked), [1], "of the place under the pointer")
        XCTAssertEqual(other, [], "never the place's own menu")
    }

    /// The ring's middle is no target, with an app's icon drawn there or not, and neither
    /// is the card beside the ring: no click gives a menu or selects a place.
    func testTheMiddleOfAnAppsOwnRingIsNoClickTarget() throws {
        let notes = Application(path: "/System/Applications/Notes.app")
        notes.setUsesGeneralRing(false, general: .default)
        let page = RingPreferencesViewController(application: notes)
        page.bindingSummary = { ShortcutRingBindingSummary(triggerTitles: []) }
        page.makeAppMark = { _ in RingHarness.mark(named: "Notes") }
        _ = page.view
        _ = show(page)
        let preview = try XCTUnwrap(page.previewView)
        XCTAssertNotNil(preview.appIcon, "the app's icon is drawn in the middle")
        page.presentPlaceMenu = { _, _, _ in XCTFail("no menu") }
        preview.presentContextMenu = { _, _, _ in XCTFail("no menu") }
        var asked = 0
        let menuForPlace = preview.menuForPlace
        preview.menuForPlace = { place in
            asked += 1
            return menuForPlace?(place)
        }
        let hub = NSPoint(x: preview.bounds.midX, y: preview.bounds.midY)
        let hubEdge = NSPoint(x: hub.x + (ShortcutRingGeometry.hubRadius - 2) * ShortcutRingPreviewView.ringScale, y: hub.y)
        for point in [hub, hubEdge, NSPoint(x: 12, y: 12), NSPoint(x: preview.bounds.maxX - 6, y: hub.y)] {
            XCTAssertNil(preview.place(at: point))
            preview.mouseDown(with: try mouse(.leftMouseDown, at: point, in: preview))
            preview.mouseDown(with: try mouse(.leftMouseDown, at: point, in: preview, flags: .control))
            XCTAssertNil(preview.menu(for: try mouse(.rightMouseDown, at: point, in: preview)))
        }
        XCTAssertEqual(asked, 0)
        XCTAssertNil(page.selectedPlace)
        XCTAssertNil(preview.lit)

        // A place of the app's ring is one: its own menu, for the app's ring alone.
        var opened: [NSMenu] = []
        page.presentPlaceMenu = { menu, _, _ in opened.append(menu) }
        preview.mouseDown(with: try mouse(.leftMouseDown, at: middle(ofPlace: 2, in: preview), in: preview))
        XCTAssertTrue(opened.first === page.placePopUps[2].menu)
        XCTAssertEqual(page.selectedPlace, 2)
        var changes = 0
        page.onPlaceChange = { changes += 1 }
        let menu = try XCTUnwrap(preview.menu(for: try mouse(.rightMouseDown, at: middle(ofPlace: 2, in: preview), in: preview)))
        try choose(try XCTUnwrap(try swaps(of: menu.items.first).first))
        XCTAssertEqual(notes.ownRingPlaces?[2], ShortcutRingSettings.default[0])
        XCTAssertEqual(notes.ownRingPlaces?[0], ShortcutRingSettings.default[2])
        XCTAssertEqual(changes, 1, "the page hears of it: its line and its reset follow")
        XCTAssertEqual(Options.shared.ring, .default, "the general ring stays")
    }

    /// Every place's own menu ends with "Swap With", after a separator: the keyboard's and
    /// VoiceOver's way to it. Before it the menu is what a place's menu always was, and
    /// "Swap With" is never the ticked item. The pull-downs of Buttons and Gestures have none.
    func testEveryPlacesOwnMenuEndsWithSwapWith() throws {
        var ring = ShortcutRingSettings.default
        ring[2] = .empty
        ring[3] = ShortcutRingPlace(action: "custom::1:1048576")
        ring[4] = ShortcutRingPlace(openTarget: OpenTargetPayload(
            path: "/System/Applications/Calculator.app", bundleID: "com.apple.calculator", arguments: "", kind: .application
        ))
        Options.shared.ring = ring
        let controller = makeController()
        let reference = NSMenu()
        ShortcutManager.buildShortcutMenu(
            into: reference, target: self, action: #selector(ButtonActionPullDown.shortcutSelected(_:)),
            showsGestureSettings: true, forRingPlace: true
        )
        for (place, popUp) in controller.placePopUps.enumerated() {
            let menu = try XCTUnwrap(popUp.menu)
            let last = try XCTUnwrap(menu.items.last)
            XCTAssertEqual(last.title, "Swap With", "\(place)")
            XCTAssertTrue(last === popUp.trailingItem)
            XCTAssertTrue(menu.items[menu.items.count - 2].isSeparatorItem)
            XCTAssertEqual(
                menu.items.dropFirst().dropLast(2).map(\.title), reference.items.dropFirst().map(\.title),
                "the menu's own items and their order stay"
            )
            popUp.menuWillOpen(menu)
            XCTAssertEqual(last.state, .off, "never ticked")
            let shown = try XCTUnwrap(popUp.shownActionItem)
            XCTAssertFalse(shown.item === last)
            XCTAssertFalse(shown.category === last)
            XCTAssertEqual(shown.item.state, .on)
            let offered = try swaps(of: last)
            XCTAssertEqual(offered.count, 7)
            XCTAssertEqual(offered.compactMap { ($0.representedObject as? RingPlaceSwap)?.place }, Array(repeating: place, count: 7))
            XCTAssertEqual(
                offered.compactMap { ($0.representedObject as? RingPlaceSwap)?.other }, (0..<8).filter { $0 != place },
                "clockwise from the top, without the place itself"
            )
            popUp.menuDidClose(menu)
        }
        // A key press in the window never fills the submenu: it has no key equivalents.
        let submenu = try XCTUnwrap(controller.placePopUps[0].trailingItem?.submenu)
        let key = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0, context: nil,
            characters: "c", charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8
        ))
        var target: AnyObject?
        var action: Selector?
        XCTAssertEqual(submenu.delegate?.menuHasKeyEquivalent?(submenu, for: key, target: &target, action: &action), false)

        // From the row's menu, as the keyboard reaches it: the two places change over.
        let fromRow = try swaps(of: controller.placePopUps[1].trailingItem)
        XCTAssertEqual(fromRow.first?.title, "Top (Mission Control)")
        try choose(try XCTUnwrap(fromRow.first))
        XCTAssertEqual(Options.shared.ring[1], ring[0])
        XCTAssertEqual(Options.shared.ring[0], ring[1])
        XCTAssertEqual(controller.selectedPlace, 1)
        XCTAssertEqual(controller.placePopUps[0].menu?.items.first?.title, "Screenshot Selection", "the rows follow")
        XCTAssertEqual(try swaps(of: controller.placePopUps[1].trailingItem).first?.title, "Top (Screenshot Selection)", "made anew each time")

        let trigger = RecordedEvent(type: .mouse, code: 4, modifiers: 0, deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "copy")
        for pullDown in [ButtonActionPullDown(binding: binding), ButtonActionPullDown(binding: binding, use: .gesture(showsLogiActions: false))] {
            XCTAssertNil(pullDown.trailingItem)
            XCTAssertEqual(pullDown.menu?.items.contains { $0.title == "Swap With" }, false)
        }
    }

    /// "Clear" empties the place as "No Action" of its menu does, with the same Undo; on a
    /// place that holds nothing it writes nothing and leaves no step.
    func testClearEmptiesThePlaceAsNoActionDoes() throws {
        Options.shared.ring[2] = .empty
        let controller = makeController()
        _ = show(controller)
        let preview = try XCTUnwrap(controller.previewView)
        let undo = UndoManager()
        undo.groupsByEvent = false
        controller.paneUndoManager = undo
        var writes = 0
        let observers = Options.shared.observerCountForTests
        Options.shared.observe([.ring]) { _ in writes += 1 }
        defer { Options.shared.removeNewestObserversForTests(Options.shared.observerCountForTests - observers) }
        func clear(_ place: Int) throws {
            let menu = try XCTUnwrap(preview.menu(for: try mouse(.rightMouseDown, at: middle(ofPlace: place, in: preview), in: preview)))
            try choose(try XCTUnwrap(menu.items.last))
        }

        // (The manager would take a step here by itself: an empty group of the test's is one.)
        undo.groupsByEvent = true
        try clear(2)
        XCTAssertEqual(writes, 0, "nothing to clear")
        XCTAssertFalse(undo.canUndo)
        XCTAssertEqual(undo.groupingLevel, 0, "no step")
        undo.groupsByEvent = false

        undo.beginUndoGrouping()
        try clear(3)
        undo.endUndoGrouping()
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(Options.shared.ring[3], .empty)
        XCTAssertEqual(controller.placePopUps[3].menu?.items.first?.title, "No Action")
        XCTAssertTrue(controller.previewView.face.places[3].isEmpty)
        XCTAssertEqual(controller.selectedPlace, 3)
        XCTAssertEqual(undo.undoMenuItemTitle, "Undo Change Action", "as No Action of its menu")
        undo.undo()
        XCTAssertEqual(Options.shared.ring[3], ShortcutRingSettings.default[3])
        XCTAssertFalse(undo.canUndo)
    }

    /// To VoiceOver the drawing stays one image, outside the key loop: the rows hold what
    /// the drops open, so the drops are no buttons (each place would be read twice). What
    /// stands over a drop for a popover is nothing to VoiceOver and takes no click.
    func testTheDrawingStaysOneImageToVoiceOver() throws {
        let controller = makeController()
        _ = show(controller)
        let preview = try XCTUnwrap(controller.previewView)
        controller.presentPlaceMenu = { _, _, _ in }
        for place in 0..<8 {
            preview.onPlaceClicked?(place)
        }
        XCTAssertEqual(preview.subviews.count, 8, "one view per drop, for the popovers")
        XCTAssertTrue(preview.isAccessibilityElement())
        XCTAssertEqual(preview.accessibilityRole(), .image)
        XCTAssertEqual(preview.accessibilityLabel(), "The ring as it opens at the pointer")
        XCTAssertTrue(NSAccessibility.unignoredChildren(from: preview.accessibilityChildren() ?? []).isEmpty, "no children")
        XCTAssertTrue(preview.subviews.allSatisfy { !$0.isAccessibilityElement() })
        XCTAssertFalse(preview.acceptsFirstResponder)
        XCTAssertFalse(preview.canBecomeKeyView)
        // (`hitTest` takes a point of the superview.)
        let onDrop = preview.convert(middle(ofPlace: 2, in: preview), to: preview.superview)
        XCTAssertTrue(preview.hitTest(onDrop) === preview, "a click on a drop goes to the drawing")
        // The eight rows are the way of the keyboard and of VoiceOver, with the same menu.
        XCTAssertEqual(controller.placePopUps.map { $0.accessibilityLabel() }, controller.placeRows.map { $0.title })
    }

    // MARK: The picture of what opens it

    private static let notes = "/System/Applications/Notes.app"

    private func logitech(_ role: LogiControlRole, modifiers: UInt = 0) -> RecordedEvent {
        return RecordedEvent(type: .mouse, code: LogiCenter.shared.scrollioCode(for: role), modifiers: modifiers, deviceFilter: nil)
    }

    private func ringBinding(_ event: RecordedEvent, action: String = "shortcutRing") -> ButtonBinding {
        return ButtonBinding(triggerEvent: event, systemShortcutName: action, isEnabled: true)
    }

    /// A pane whose picture shows `event` (nil: nothing opens the ring) on `mouse`.
    private func makeController(
        showing event: RecordedEvent?, on mouse: MouseArtworkModel, onlyIn app: String? = nil
    ) throws -> (RingPreferencesViewController, ShortcutRingTriggerCard) {
        summary = ShortcutRingBindingSummary(
            triggerTitles: event == nil || app != nil ? [] : ["The trigger"],
            onlyInApps: app.map { ApplicationTriggers(applicationNames: ["Notes"], triggerTitles: ["The trigger"], path: $0, trigger: event) },
            picture: TriggerPictureSource(event: event, onlyInAppPath: app)
        )
        let controller = makeController()
        let card = try XCTUnwrap(controller.triggerCard)
        card.mouseSource = { mouse }
        card.reloadMouse()
        return (controller, card)
    }

    /// The faces of the card's keys, in the card.
    private func faces(_ card: ShortcutRingTriggerCard) -> [NSRect] {
        return card.caps.map { $0.faceRect.offsetBy(dx: $0.frame.minX, dy: $0.frame.minY) }
    }

    /// On top two cards as in Gestures: what opens the ring on the left, the ring on the
    /// right (its own card, which keeps its identifier). The left one is a picture only.
    /// An app's page keeps the ring across the width.
    func testTheHeaderIsTwoCardsAsInGestures() throws {
        let controller = makeController()
        controller.view.layoutSubtreeIfNeeded()
        let header = try XCTUnwrap(controller.sections.first as? ShortcutRingHeaderView)
        XCTAssertTrue(header === controller.headerView)
        XCTAssertTrue(header.ringCard === controller.previewView)
        XCTAssertEqual(controller.previewView.identifier, RingPreferencesViewController.Identifier.preview)
        XCTAssertEqual(header.frame.size, NSSize(width: 480, height: 206))
        XCTAssertEqual(header.triggerCard.frame, NSRect(x: 0, y: 0, width: 234, height: 206))
        XCTAssertEqual(header.ringCard.frame, NSRect(x: 246, y: 0, width: 234, height: 206), "12 pt apart")

        let card = header.triggerCard
        XCTAssertNil(card.hitTest(NSPoint(x: 117, y: 103)), "it takes no click")
        XCTAssertFalse(card.isAccessibilityElement())
        for view in [card.artwork, card.chip, card.partBadge] as [NSView] {
            XCTAssertFalse(view.isAccessibilityElement())
        }
        XCTAssertEqual(controller.previewView.accessibilityLabel(), "The ring as it opens at the pointer")

        let page = RingPreferencesViewController(application: Application(path: Self.notes))
        page.view.layoutSubtreeIfNeeded()
        XCTAssertNil(page.headerView)
        XCTAssertNil(page.triggerCard)
        XCTAssertTrue(page.sections.first === page.previewView)
        XCTAssertEqual(page.previewView.frame.width, 480, "the ring across the width")
    }

    /// The owner's case: an MX Master 4 whose thumb panel opens the ring shows the thumb
    /// panel lit, from the side, turned at once as the pane loads; the mouse in the middle.
    /// A numbered button is the Buttons card's badge, a part this drawing lacks the badge of
    /// a button.
    func testTheThumbPanelOfAMasterFourLightsFromTheSide() throws {
        let (_, card) = try makeController(showing: logitech(.thumbPanel), on: .mxMaster4)
        XCTAssertEqual(card.picture, TriggerPicture(hold: .part(.thumbPanel)))
        XCTAssertEqual(card.artwork.emphasis, .thumbPanel)
        XCTAssertEqual(card.artwork.base.viewpoint, .thumbSide)
        XCTAssertFalse(card.artwork.base.isTurning, "turned without a turn")
        XCTAssertFalse(card.artwork.isHidden)
        XCTAssertTrue(card.caps.isEmpty)
        XCTAssertEqual(card.artwork.frame.midX, card.bounds.midX, accuracy: 1)
        XCTAssertEqual(card.artwork.frame.midY, card.bounds.midY, accuracy: 1)
        XCTAssertEqual(card.artwork.badge.alphaValue, 0)
        XCTAssertEqual(card.partBadge.alphaValue, 0)
        XCTAssertTrue(card.chip.isHidden)

        let (_, six) = try makeController(showing: RecordedEvent(type: .mouse, code: 6, modifiers: 0, deviceFilter: nil), on: .mxMaster4)
        XCTAssertNil(six.artwork.emphasis)
        XCTAssertEqual(six.artwork.badge.number, 6)
        XCTAssertEqual(six.artwork.badge.alphaValue, 1)

        let (_, panelOnThree) = try makeController(showing: logitech(.thumbPanel), on: .mxMaster3)
        XCTAssertEqual(panelOnThree.picture.hold, .notDrawn(.thumbPanel))
        XCTAssertNil(panelOnThree.artwork.emphasis)
        XCTAssertEqual(panelOnThree.partBadge.alphaValue, 1)
        XCTAssertEqual(panelOnThree.partBadge.frame.size, NSSize(width: 20, height: 20))
        let centre = panelOnThree.artwork.badgeCentre
        XCTAssertEqual(panelOnThree.partBadge.frame.midX, panelOnThree.artwork.frame.minX + centre.x, accuracy: 0.5)
        XCTAssertEqual(panelOnThree.partBadge.frame.midY, panelOnThree.artwork.frame.minY + centre.y, accuracy: 0.5)
        XCTAssertEqual(panelOnThree.artwork.badge.alphaValue, 0)

        // With a modifier: the button lit, and its key pressed 8 pt under the mouse's body,
        // the two in the middle together.
        let (_, optionBack) = try makeController(
            showing: RecordedEvent(type: .mouse, code: 3, modifiers: UInt(CGEventFlags.maskAlternate.rawValue), deviceFilter: nil),
            on: .mxMaster4
        )
        XCTAssertEqual(optionBack.artwork.emphasis, .back)
        XCTAssertEqual(optionBack.caps.map(\.label), ["⌥"])
        XCTAssertEqual(optionBack.caps.first?.depth, 1)
        XCTAssertEqual(optionBack.caps.first?.faceHeight, 24)
        // (From the side the drawing lies across: the body is lower than from above.)
        let extent = optionBack.bodyExtent
        XCTAssertLessThan(extent.height, 100)
        let body = optionBack.artwork.frame.minY + extent.minY
        let face = try XCTUnwrap(faces(optionBack).first)
        XCTAssertEqual(face.minY - (body + extent.height), 8, accuracy: 0.5)
        XCTAssertEqual(face.midX, optionBack.bounds.midX, accuracy: 1)
        let bottom = face.maxY + TriggerKeyCap.travel(faceHeight: 24)
        XCTAssertEqual((body + bottom) / 2, optionBack.bounds.midY, accuracy: 1)
    }

    /// A key opens the ring: its keys alone, pressed, 34 pt and 6 pt apart, in the middle;
    /// a long combination smaller, so that it fits 202 pt.
    func testAKeyCombinationIsItsKeysAlone() throws {
        let control = UInt(CGEventFlags.maskControl.rawValue)
        let option = UInt(CGEventFlags.maskAlternate.rawValue)
        let (_, card) = try makeController(
            showing: RecordedEvent(type: .keyboard, code: 49, modifiers: control | option, deviceFilter: nil), on: .mxMaster4
        )
        XCTAssertEqual(card.caps.map(\.label), ["⌃", "⌥", "⎵"])
        XCTAssertTrue(card.artwork.isHidden, "no mouse")
        XCTAssertNil(card.artwork.emphasis)
        XCTAssertTrue(card.caps.allSatisfy { $0.depth == 1 && !$0.isPlaceholder && $0.faceHeight == 34 })
        let rects = faces(card)
        for (left, right) in zip(rects, rects.dropFirst()) {
            XCTAssertEqual(right.minX - left.maxX, 6, accuracy: 0.5)
        }
        let first = try XCTUnwrap(rects.first), last = try XCTUnwrap(rects.last)
        XCTAssertEqual((first.minX + last.maxX) / 2, card.bounds.midX, accuracy: 1)
        XCTAssertEqual(first.minY + (34 + TriggerKeyCap.travel(faceHeight: 34)) / 2, card.bounds.midY, accuracy: 1)

        let shift = UInt(CGEventFlags.maskShift.rawValue), command = UInt(CGEventFlags.maskCommand.rawValue)
        let (_, long) = try makeController(
            showing: RecordedEvent(type: .keyboard, code: 121, modifiers: control | option | shift | command, deviceFilter: nil),
            on: .generic
        )
        XCTAssertEqual(long.caps.count, 5)
        let height = try XCTUnwrap(long.caps.first?.faceHeight)
        XCTAssertLessThan(height, 34, "drawn smaller")
        let row = faces(long)
        let start = try XCTUnwrap(row.first), end = try XCTUnwrap(row.last)
        XCTAssertLessThanOrEqual(end.maxX - start.minX, 202)
        XCTAssertGreaterThanOrEqual(start.minX, 16)
    }

    /// Nothing opens the ring: the mouse at rest, nothing lit, and one dashed blank key under
    /// it; nothing in the accent colour. An app's own trigger shows with the app's icon.
    func testNothingShowsTheMouseAtRestAndABlankKey() throws {
        let (_, card) = try makeController(showing: nil, on: .mxMaster4)
        XCTAssertEqual(card.picture, .none)
        XCTAssertNil(card.artwork.emphasis)
        XCTAssertEqual(card.artwork.base.viewpoint, .above)
        XCTAssertFalse(card.artwork.isHidden)
        XCTAssertEqual(card.caps.count, 1)
        XCTAssertEqual(card.caps.first?.isPlaceholder, true)
        XCTAssertEqual(card.caps.first?.depth, 0)
        XCTAssertEqual(card.caps.first?.faceHeight, 24)
        XCTAssertEqual(card.artwork.badge.alphaValue, 0)
        XCTAssertEqual(card.partBadge.alphaValue, 0)
        XCTAssertNil(card.pressTarget(), "nothing to press")
        // The mouse, 8 pt and the blank key, in the middle together.
        let extent = card.bodyExtent
        let body = card.artwork.frame.minY + extent.minY
        let face = try XCTUnwrap(faces(card).first)
        XCTAssertEqual(face.minY - (body + extent.height), 8, accuracy: 0.5)
        XCTAssertEqual((body + face.maxY + TriggerKeyCap.travel(faceHeight: 24)) / 2, card.bounds.midY, accuracy: 1)

        let (_, notes) = try makeController(showing: logitech(.thumbPanel), on: .mxMaster4, onlyIn: Self.notes)
        XCTAssertEqual(notes.picture.appPath, Self.notes)
        XCTAssertEqual(notes.chip.path, Self.notes)
        XCTAssertFalse(notes.chip.isHidden)
        XCTAssertNotNil(notes.chip.image)
        XCTAssertEqual(notes.chip.frame, NSRect(x: 8, y: 8, width: 18, height: 18))
        XCTAssertEqual(notes.artwork.emphasis, .thumbPanel)
    }

    /// The summary's picture is of the first trigger that can run, or of the first app's own
    /// while only apps' own open the ring.
    func testTheSummaryPicturesTheFirstTriggerThatRuns() {
        let control = UInt(CGEventFlags.maskControl.rawValue)
        let panel = ringBinding(logitech(.thumbPanel))
        let bindings = [
            ringBinding(logitech(.middle), action: "copy"),
            ringBinding(RecordedEvent(type: .keyboard, code: 0, modifiers: 0, deviceFilter: nil)),  // a plain letter never runs
            panel,
            ringBinding(RecordedEvent(type: .keyboard, code: 49, modifiers: control, deviceFilter: nil)),
        ]
        XCTAssertEqual(ShortcutRingBindingSummary(bindings: bindings).picture, TriggerPictureSource(event: panel.triggerEvent))
        XCTAssertEqual(ShortcutRingBindingSummary(bindings: []).picture, .none)

        let notes = Application(path: Self.notes)
        notes.setOwnButtonBindings([panel])
        XCTAssertEqual(ShortcutRingBindingSummary(bindings: [], applications: [notes]).picture,
                       TriggerPictureSource(event: panel.triggerEvent, onlyInAppPath: Self.notes))
        XCTAssertEqual(ShortcutRingBindingSummary(bindings: [panel], applications: [notes]).picture,
                       TriggerPictureSource(event: panel.triggerEvent), "Buttons' own: no app")
    }

    /// The picture presses once when the pointer enters the "Button or key" row: a ring on
    /// the lit part's outline, then no other for 1.5 s; never under Reduce Motion, never off
    /// screen. A trigger that changes while shown presses after the drawing has turned.
    /// The pointer enters as AppKit says so: an enter event of the row's tracking area,
    /// handed to the controller that owns it.
    func testThePicturePressesWhenTheRowIsPointedAtAtMostEveryOneAndAHalfSeconds() throws {
        let (controller, card) = try makeController(showing: logitech(.middle), on: .mxMaster4)
        let areas = controller.triggerRow.trackingAreas.filter { $0.owner === controller }
        XCTAssertEqual(areas.count, 1)
        let area = try XCTUnwrap(areas.first)
        var windowNumber = 0
        func pointAtTheRow() throws {
            // (An event of a tracking area carries the area as its tracking number.)
            let entered = try XCTUnwrap(NSEvent.enterExitEvent(
                with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: windowNumber, context: nil,
                eventNumber: 0, trackingNumber: Int(bitPattern: Unmanaged.passUnretained(area).toOpaque()), userData: nil
            ))
            XCTAssertTrue(entered.trackingArea === area)
            controller.mouseEntered(with: entered)
        }
        card.prefersReducedMotion = { false }
        try pointAtTheRow()
        XCTAssertNil(card.pressLayer, "none off screen")

        var now: TimeInterval = 100
        card.clock = { now }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 900), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        addTeardownBlock { window.close() }
        windowNumber = window.windowNumber

        now += 2
        try pointAtTheRow()
        let first = try XCTUnwrap(card.pressLayer)
        XCTAssertTrue(first.superlayer === card.layer)
        let wheel = try XCTUnwrap(MouseArtworkView.shape(of: .wheel, model: .mxMaster4))
        wheel.transform(using: AffineTransform(translationByX: card.artwork.frame.minX, byY: card.artwork.frame.minY))
        let ringed = try XCTUnwrap(first.path?.boundingBoxOfPath)
        XCTAssertEqual(ringed.minX, wheel.bounds.minX, accuracy: 0.5)
        XCTAssertEqual(ringed.minY, wheel.bounds.minY, accuracy: 0.5)
        XCTAssertEqual(ringed.width, wheel.bounds.width, accuracy: 0.5)
        XCTAssertEqual(first.animation(forKey: "press")?.duration, 0.4)
        XCTAssertEqual(first.lineWidth, 15)

        now += 1
        try pointAtTheRow()
        XCTAssertTrue(card.pressLayer === first, "not again within 1.5 s")
        now += 0.6
        try pointAtTheRow()
        let second = try XCTUnwrap(card.pressLayer)
        XCTAssertFalse(second === first)
        XCTAssertNil(first.superlayer)

        now += 2
        card.prefersReducedMotion = { true }
        try pointAtTheRow()
        XCTAssertTrue(card.pressLayer === second, "none under Reduce Motion")

        // Another trigger while shown: the drawing turns to the thumb panel, the press waits.
        now += 2
        card.prefersReducedMotion = { false }
        card.source = TriggerPictureSource(event: logitech(.thumbPanel))
        XCTAssertTrue(card.artwork.base.isTurning)
        XCTAssertTrue(card.pressLayer === second || card.pressLayer == nil, "it waits for the turn")
        let deadline = Date().addingTimeInterval(3)
        while (card.pressLayer == nil || card.pressLayer === second) && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        let third = try XCTUnwrap(card.pressLayer)
        XCTAssertFalse(third === second)
        XCTAssertEqual(card.artwork.base.viewpoint, .thumbSide)
    }

    /// A mouse that comes or goes changes the picture alone: the pane is not reloaded (that
    /// would make the ring's face again).
    func testAMouseChangeRedrawsThePictureAlone() throws {
        let (controller, card) = try makeController(showing: logitech(.thumbPanel), on: .generic)
        XCTAssertEqual(card.picture.hold, .notDrawn(.thumbPanel), "no mouse: the plain drawing")
        var mouse = MouseArtworkModel.mxMaster4
        card.mouseSource = { mouse }
        var reloads = 0
        controller.bindingSummary = { [unowned self] in
            reloads += 1
            return self.summary
        }
        ShortcutRingController.forgetPreparedFaces()

        NotificationCenter.default.post(name: LogiCenter.sessionChanged, object: nil)
        XCTAssertEqual(card.artwork.model, .mxMaster4)
        XCTAssertEqual(card.artwork.emphasis, .thumbPanel)
        mouse = .mxMaster3
        NotificationCenter.default.post(name: LogiCenter.mouseStateChanged, object: nil)
        XCTAssertEqual(card.artwork.model, .mxMaster3)
        XCTAssertEqual(card.picture.hold, .notDrawn(.thumbPanel))
        XCTAssertEqual(reloads, 0, "the pane is not reloaded")
        XCTAssertNil(ShortcutRingController.preparedFace, "nor the ring's face made again")
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
        XCTAssertEqual(controller.triggerButton.shownTitle, "Multiple")
        XCTAssertEqual(shownActions(controller)[0], "Undo")
        XCTAssertEqual(shownActions(controller)[3], "No Action")
        XCTAssertEqual((controller.freezeToggle as? NSSwitch)?.state, .on)
        XCTAssertTrue(controller.resetToDefaultsButton.isEnabled)
        XCTAssertNotNil(ShortcutRingController.preparedFace(for: changedRing)?.places[4].image,
                        "the pane made the face of a ring that opens an app, its icon in")

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
        XCTAssertNil(ShortcutRingController.preparedFace(for: .default),
                     "the new ring opens nothing: no face is kept, at a press it is whole without a look on disk")

        // What opens the ring: as it was.
        XCTAssertEqual(Options.shared.buttons.binding, bindings)
        XCTAssertEqual(controller.triggerRow.explanation, opens)
        XCTAssertEqual(controller.triggerButton.shownTitle, "Multiple")

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

/// Writes down how a click reaches a view: `menu(for:)`, `mouseDown` and `rightMouseDown`,
/// in order. It hands out no menu, so nothing opens. It takes a click in a window that is
/// not the key one (the test's never is).
private final class ControlClickProbe: NSView {
    var calls: [String] = []

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        calls.append("menu")
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        calls.append("down")
    }

    override func rightMouseDown(with event: NSEvent) {
        calls.append("right down")
        super.rightMouseDown(with: event)
    }
}

/// A window that exists for the system and is never seen: clear, far off every screen,
/// behind everything, taking no click of the user's and never the key or main window (as
/// the Welcome Guide's tests have one for their real clicks).
private final class OutOfSightWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }

    override var canBecomeKey: Bool { return false }
    override var canBecomeMain: Bool { return false }

    func putOutOfSight() {
        alphaValue = 0
        ignoresMouseEvents = true
        setFrameOrigin(NSPoint(x: -30_000, y: -30_000))
        orderBack(nil)
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

    /// "Change" selects what the Shortcut Ring pane names first and draws: a key that never
    /// runs (a plain letter) is passed over.
    func testTheRingsTriggerIsTheFirstThatCanRun() {
        let letter = binding(.keyboard, 0, action: "shortcutRing")
        let ring = binding(.mouse, 4, action: "shortcutRing")
        let pane = makePane([letter, ring])
        XCTAssertEqual(pane.ringTriggerBinding?.id, ring.id)
        XCTAssertNil(makePane([letter]).ringTriggerBinding)
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

// MARK: - Undo of a place

/// Edit › Undo and Redo of a place of the ring, the pane's and an app's own: the place as it
/// was (with the name and icon of its keys), named as Buttons names it; the pane, or the
/// app's page on its Shortcut Ring part, comes forward with the place's row selected, also
/// from another pane and after the page closed; in order with a change in Buttons, whose
/// Undo brings its pane forward too. The window as the app makes it, never shown.
final class RingPlaceUndoTests: XCTestCase {

    private static let calculator = "/System/Applications/Calculator.app"
    /// A recorded key combination (⌘S as the settings store it).
    private static let keys = "custom::1:1048576"

    private var savedApplications: EnhanceArray<Application>!
    private var savedBindings: [ButtonBinding] = []
    private var savedRing = ShortcutRingSettings.default
    private var uiDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        savedApplications = Options.shared.application.applications
        savedBindings = Options.shared.buttons.binding
        savedRing = Options.shared.ring
        Options.shared.application.applications = EnhanceArray<Application>(
            withArray: [], matchKey: "path", forObserver: { Options.shared.markChanged(.application) }
        )
        Options.shared.buttons.binding = []
        Options.shared.ring = .default
        ButtonUtils.shared.invalidateCache()
        uiDefaults = TestDefaults.make(for: self)
    }

    override func tearDown() {
        Options.shared.application.applications = savedApplications
        Options.shared.buttons.binding = savedBindings
        Options.shared.ring = savedRing
        ShortcutRingController.forgetPreparedFaces()
        ButtonUtils.shared.invalidateCache()
        savedApplications = nil
        uiDefaults = nil
        super.tearDown()
    }

    private struct Window {
        let window: NSWindow
        let preferences: PreferencesSplitViewController
        let undo: UndoManager
        let ring: RingPreferencesViewController
        let buttons: PreferencesButtonsViewController
        let apps: PreferencesApplicationViewController
    }

    /// The window's panes (nothing remembered, no mouse), in a window of their own whose
    /// undo manager takes a group per step.
    private func makeWindow() throws -> Window {
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesSplitViewController.self))
        let preferences = PreferencesSplitViewController(storyboard: storyboard, uiStateDefaults: nil)
        let ring = try XCTUnwrap(preferences.controller(for: RingPreferencesViewController.tabIdentifier) as? RingPreferencesViewController)
        ring.bindingSummary = { ShortcutRingBindingSummary(triggerTitles: []) }
        let buttons = try XCTUnwrap(preferences.controller(for: PANEL_IDENTIFIER.buttons) as? PreferencesButtonsViewController)
        buttons.deviceSource = ButtonsDeviceSource(
            captureStatus: { _ in .normal }, deviceName: { nil }, isBusy: { false }, refresh: {}, warnBluetoothButton: { _ in }
        )
        let apps = try XCTUnwrap(preferences.controller(for: PANEL_IDENTIFIER.application) as? PreferencesApplicationViewController)
        apps.uiStateDefaults = uiDefaults
        apps.runningApplications = { [] }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: true
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = preferences
        addTeardownBlock { window.close() }
        let undo = try XCTUnwrap(window.undoManager)
        undo.groupsByEvent = false
        return Window(window: window, preferences: preferences, undo: undo, ring: ring, buttons: buttons, apps: apps)
    }

    /// One user action: one group on the undo manager.
    private func step(_ undo: UndoManager, _ body: () throws -> Void) rethrows {
        undo.beginUndoGrouping()
        defer { undo.endUndoGrouping() }
        try body()
    }

    private func label(_ name: String) throws -> ShortcutLabel {
        return try XCTUnwrap(ShortcutLabel(name: name, icon: .symbol("square.and.arrow.down")))
    }

    /// The pane: Undo puts back the keys with their name and icon, selects the row and gives
    /// its pull-down the keyboard; Redo makes the change again. A new name alone is a rename.
    func testUndoPutsBackAPlaceWithItsNameAndIconAndRedoChangesItAgain() throws {
        let saved = ShortcutRingPlace(action: Self.keys, label: try label("Save All"))
        Options.shared.ring[2] = saved
        let w = try makeWindow()
        XCTAssertTrue(w.preferences.selectPane(withIdentifier: RingPreferencesViewController.tabIdentifier))
        let popUp = w.ring.placePopUps[2]
        XCTAssertEqual(popUp.binding.label, saved.label)

        try step(w.undo) { popUp.onShortcutSelected?(SystemShortcut.paste) }
        XCTAssertEqual(Options.shared.ring[2], ShortcutRingPlace(SystemShortcut.paste))
        XCTAssertEqual(w.undo.undoMenuItemTitle, "Undo Change Action")
        w.ring.selectPlace(5)
        w.window.makeFirstResponder(nil)

        w.undo.undo()
        XCTAssertEqual(Options.shared.ring[2], saved, "the keys with their name and icon")
        XCTAssertEqual(popUp.binding.label, saved.label, "the row shows them")
        XCTAssertEqual(w.ring.selectedPlace, 2, "the row is selected")
        XCTAssertTrue(w.window.firstResponder === popUp, "its pull-down has the keyboard")
        XCTAssertEqual(w.undo.redoMenuItemTitle, "Redo Change Action")

        w.undo.redo()
        XCTAssertEqual(Options.shared.ring[2], ShortcutRingPlace(SystemShortcut.paste))
        XCTAssertEqual(w.undo.undoMenuItemTitle, "Undo Change Action")
        w.undo.undo()
        XCTAssertEqual(Options.shared.ring[2], saved)

        // Only another name for the same keys.
        let renamed = ShortcutRingPlace(action: Self.keys, label: try label("Keep"))
        try step(w.undo) { popUp.onCustomShortcutRecorded?(Self.keys, renamed.label) }
        XCTAssertEqual(Options.shared.ring[2], renamed)
        XCTAssertEqual(w.undo.undoMenuItemTitle, "Undo Rename", "as Buttons calls it")
        w.undo.undo()
        XCTAssertEqual(Options.shared.ring[2], saved)
        XCTAssertEqual(w.undo.redoMenuItemTitle, "Redo Rename")
    }

    /// From another pane: the Shortcut Ring pane comes forward, its folded places open and
    /// the row is selected. A pane on show stays where it is.
    func testUndoFromAnotherPaneShowsTheRingPaneWithTheRowSelected() throws {
        let w = try makeWindow()
        XCTAssertTrue(w.preferences.selectPane(withIdentifier: RingPreferencesViewController.tabIdentifier))
        let places = try XCTUnwrap(w.ring.placesSection)
        XCTAssertTrue(places.isCollapsible, "nothing opens the ring: the places fold")
        places.setExpanded(true)
        try step(w.undo) { w.ring.placePopUps[6].onShortcutSelected?(nil) }
        XCTAssertEqual(Options.shared.ring[6], .empty)
        places.setExpanded(false)

        XCTAssertTrue(w.preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.general))
        XCTAssertNil(w.ring.view.window, "the pane is out of the window")
        w.undo.undo()
        XCTAssertEqual(Options.shared.ring[6], ShortcutRingSettings.default[6])
        XCTAssertEqual(w.preferences.selectedPaneIdentifier, RingPreferencesViewController.tabIdentifier)
        XCTAssertTrue(places.showsBody, "the places open")
        XCTAssertEqual(w.ring.selectedPlace, 6)
        XCTAssertTrue(w.window.firstResponder === w.ring.placePopUps[6])
        XCTAssertEqual(w.ring.placePopUps[6].binding.systemShortcutName, ShortcutRingSettings.default[6].action)
    }

    /// An app's own ring, after its page closed and while General shows: Apps comes forward
    /// with the app's page on its Shortcut Ring part, the row selected; Redo too. The general
    /// ring is never touched.
    func testUndoOfAnAppsPlaceAfterItsPageClosedOpensThePageWithTheRowSelected() throws {
        let calculator = Application(path: Self.calculator)
        Options.shared.application.applications.append(calculator)
        calculator.setUsesGeneralRing(false, general: Options.shared.ring)
        let before = try XCTUnwrap(calculator.ownRingPlaces?[5])
        let w = try makeWindow()
        XCTAssertTrue(w.preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.application))
        w.apps.openApplication(withID: try XCTUnwrap(w.apps.rowID(for: calculator)), part: .ring)
        let ring = try XCTUnwrap(w.apps.detailController?.ringPart.ringController)
        try step(w.undo) { ring.placePopUps[5].onShortcutSelected?(SystemShortcut.paste) }
        XCTAssertEqual(calculator.ownRingPlaces?[5], ShortcutRingPlace(SystemShortcut.paste))
        XCTAssertEqual(w.undo.undoMenuItemTitle, "Undo Change Action")

        w.apps.showList(focusList: false)
        XCTAssertNil(w.apps.detailController, "the page closed")
        XCTAssertTrue(w.preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.general))
        w.undo.undo()
        XCTAssertEqual(calculator.ownRingPlaces?[5], before)
        XCTAssertEqual(Options.shared.ring, .default, "the general ring is untouched")
        XCTAssertEqual(w.preferences.selectedPaneIdentifier, PANEL_IDENTIFIER.application)
        let page = try XCTUnwrap(w.apps.detailController)
        XCTAssertTrue(page.application === calculator)
        XCTAssertEqual(page.shownPart, .ring)
        let shown = try XCTUnwrap(page.ringPart.ringController)
        XCTAssertEqual(shown.placePopUps[5].binding.systemShortcutName, before.action)
        XCTAssertEqual(shown.placesSection?.showsBody, true, "its folded rows open")
        XCTAssertEqual(shown.selectedPlace, 5)
        XCTAssertTrue(w.window.firstResponder === shown.placePopUps[5])

        w.undo.redo()
        XCTAssertEqual(calculator.ownRingPlaces?[5], ShortcutRingPlace(SystemShortcut.paste))
        XCTAssertEqual(shown.placePopUps[5].binding.systemShortcutName, SystemShortcut.paste.identifier, "the page on show follows")
        XCTAssertEqual(Options.shared.ring, .default)
    }

    /// A place of an app's own ring, changed, then "Use settings from Shortcut Ring" is on
    /// again: the ring is kept for later and its part shows the switch alone. Undo and Redo
    /// still reach the kept ring, and nothing comes forward, from another pane or on the
    /// app's page. Regression: the app's Shortcut Ring part came forward with nothing
    /// changed in sight.
    func testUndoOfAPlaceOfARingKeptForLaterBringsNothingForward() throws {
        let calculator = Application(path: Self.calculator)
        Options.shared.application.applications.append(calculator)
        calculator.setUsesGeneralRing(false, general: Options.shared.ring)
        let before = try XCTUnwrap(calculator.ownRingPlaces?[0])
        let w = try makeWindow()
        XCTAssertTrue(w.preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.application))
        w.apps.openApplication(withID: try XCTUnwrap(w.apps.rowID(for: calculator)), part: .ring)
        let page = try XCTUnwrap(w.apps.detailController)
        let ring = try XCTUnwrap(page.ringPart.ringController)
        try step(w.undo) { ring.placePopUps[0].onShortcutSelected?(SystemShortcut.paste) }
        calculator.setUsesGeneralRing(true, general: Options.shared.ring)
        page.ringPart.syncViewWithOptions()
        XCTAssertNil(page.ringPart.ringController, "the part shows the switch alone")

        // On the app's page, another part on show: it stays.
        page.show(.scrolling)
        w.undo.undo()
        XCTAssertEqual(calculator.ring?.places[0], before, "the kept ring has its place back")
        XCTAssertTrue(calculator.usesGeneralRing)
        XCTAssertEqual(page.shownPart, .scrolling, "the part on show stays")

        // From another pane, the page closed: nothing comes forward.
        w.apps.showList(focusList: false)
        XCTAssertTrue(w.preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.general))
        w.undo.redo()
        XCTAssertEqual(calculator.ring?.places[0], ShortcutRingPlace(SystemShortcut.paste))
        XCTAssertEqual(w.preferences.selectedPaneIdentifier, PANEL_IDENTIFIER.general, "nothing comes forward")
        XCTAssertNil(w.apps.detailController)
        XCTAssertEqual(Options.shared.ring, .default, "the general ring is untouched")
    }

    /// A change in Buttons, then one in the ring: Undo takes back the ring's first and shows
    /// its pane, then the button's and shows Buttons with its row selected; Redo goes the
    /// other way.
    func testUndoTakesBackAPlaceAndAButtonsChangeInOrderEachInItsPane() throws {
        let copy = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, deviceFilter: nil),
            systemShortcutName: SystemShortcut.copy.identifier, isEnabled: true
        )
        Options.shared.buttons.binding = [copy]
        let w = try makeWindow()
        XCTAssertTrue(w.preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.buttons))
        let row = try XCTUnwrap(w.buttons.row(for: copy.id))
        try step(w.undo) { row.pullDown.onShortcutSelected?(SystemShortcut.paste) }
        XCTAssertEqual(Options.shared.buttons.binding.first?.systemShortcutName, SystemShortcut.paste.identifier)
        XCTAssertTrue(w.preferences.selectPane(withIdentifier: RingPreferencesViewController.tabIdentifier))
        try step(w.undo) { w.ring.placePopUps[1].onShortcutSelected?(SystemShortcut.copy) }
        XCTAssertTrue(w.preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.general))

        w.undo.undo()
        XCTAssertEqual(Options.shared.ring, .default)
        XCTAssertEqual(Options.shared.buttons.binding.first?.systemShortcutName, SystemShortcut.paste.identifier, "not yet")
        XCTAssertEqual(w.preferences.selectedPaneIdentifier, RingPreferencesViewController.tabIdentifier)
        w.undo.undo()
        XCTAssertEqual(Options.shared.buttons.binding, [copy])
        XCTAssertEqual(w.preferences.selectedPaneIdentifier, PANEL_IDENTIFIER.buttons, "Buttons comes forward")
        XCTAssertEqual(w.buttons.list.selectedID, w.buttons.rowID(forBinding: copy.id))
        XCTAssertFalse(w.undo.canUndo)

        w.undo.redo()
        XCTAssertEqual(Options.shared.buttons.binding.first?.systemShortcutName, SystemShortcut.paste.identifier)
        XCTAssertEqual(w.preferences.selectedPaneIdentifier, PANEL_IDENTIFIER.buttons)
        w.undo.redo()
        XCTAssertEqual(Options.shared.ring[1], ShortcutRingPlace(SystemShortcut.copy))
        XCTAssertEqual(w.preferences.selectedPaneIdentifier, RingPreferencesViewController.tabIdentifier)
    }

    // MARK: - Undo of a button or an app, shown where it acts too

    /// "Undo Remove Button" from another pane: Buttons comes forward with the row selected
    /// and the list has the keyboard; Redo removes it again, in sight too.
    func testUndoOfARemovedButtonFromAnotherPaneShowsButtonsWithTheRowSelected() throws {
        let copy = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, deviceFilter: nil),
            systemShortcutName: SystemShortcut.copy.identifier, isEnabled: true
        )
        Options.shared.buttons.binding = [copy]
        let w = try makeWindow()
        XCTAssertTrue(w.preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.buttons))
        try step(w.undo) { w.buttons.removeBinding(id: copy.id) }
        XCTAssertEqual(Options.shared.buttons.binding, [])
        XCTAssertEqual(w.undo.undoMenuItemTitle, "Undo Remove Button")

        XCTAssertTrue(w.preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.general))
        XCTAssertNil(w.buttons.view.window, "the pane is out of the window")
        w.undo.undo()
        XCTAssertEqual(Options.shared.buttons.binding, [copy])
        XCTAssertEqual(w.preferences.selectedPaneIdentifier, PANEL_IDENTIFIER.buttons, "Buttons comes forward")
        XCTAssertEqual(w.buttons.list.selectedID, w.buttons.rowID(forBinding: copy.id))
        XCTAssertTrue(w.window.firstResponder === w.buttons.list)

        XCTAssertTrue(w.preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.general))
        w.undo.redo()
        XCTAssertEqual(Options.shared.buttons.binding, [])
        XCTAssertEqual(w.preferences.selectedPaneIdentifier, PANEL_IDENTIFIER.buttons)
    }

    /// A row of an app's own Buttons, removed; its page closed and General shows: Undo
    /// brings Apps forward with the app's page on its Buttons part and the row selected.
    /// Buttons is never touched.
    func testUndoOfAnAppsRemovedButtonAfterItsPageClosedOpensItsButtonsWithTheRowSelected() throws {
        let calculator = Application(path: Self.calculator)
        Options.shared.application.applications.append(calculator)
        let own = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 4, modifiers: 0, deviceFilter: nil),
            systemShortcutName: SystemShortcut.copy.identifier, isEnabled: true
        )
        calculator.setOwnButtonBindings([own])
        let w = try makeWindow()
        XCTAssertTrue(w.preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.application))
        w.apps.openApplication(withID: try XCTUnwrap(w.apps.rowID(for: calculator)), part: .buttons)
        let part = try XCTUnwrap(w.apps.detailController?.buttonsPart)
        try step(w.undo) { part.removeOwnBinding(id: own.id) }
        XCTAssertTrue(calculator.ownButtonBindings.isEmpty)
        XCTAssertEqual(w.undo.undoMenuItemTitle, "Undo Remove Button")

        w.apps.showList(focusList: false)
        XCTAssertNil(w.apps.detailController, "the page closed")
        XCTAssertTrue(w.preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.general))
        w.undo.undo()
        XCTAssertEqual(calculator.ownButtonBindings.map(\.id), [own.id])
        XCTAssertEqual(w.preferences.selectedPaneIdentifier, PANEL_IDENTIFIER.application, "Apps comes forward")
        let page = try XCTUnwrap(w.apps.detailController)
        XCTAssertTrue(page.application === calculator)
        XCTAssertEqual(page.shownPart, .buttons)
        XCTAssertEqual(page.buttonsPart.list.selectedID, AnyHashable(own.id), "the row is selected")
        XCTAssertEqual(Options.shared.buttons.binding, [], "Buttons is untouched")

        w.apps.showList(focusList: false)
        XCTAssertTrue(w.preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.general))
        w.undo.redo()
        XCTAssertTrue(calculator.ownButtonBindings.isEmpty)
        XCTAssertEqual(w.preferences.selectedPaneIdentifier, PANEL_IDENTIFIER.application)
        XCTAssertEqual(w.apps.detailController?.shownPart, .buttons)
    }

    /// "Undo Remove App" from another pane: Apps comes forward with the list, the app back
    /// in its place and selected. Redo while another app's page shows: the list, without it.
    func testUndoOfARemovedAppFromAnotherPaneShowsAppsWithTheRowSelected() throws {
        let calculator = Application(path: Self.calculator)
        let textEdit = Application(path: "/System/Applications/TextEdit.app")
        Options.shared.application.applications.append(calculator)
        Options.shared.application.applications.append(textEdit)
        let w = try makeWindow()
        XCTAssertTrue(w.preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.application))
        let id = try XCTUnwrap(w.apps.rowID(for: calculator))
        try step(w.undo) { w.apps.removeApplication(withID: id) }
        XCTAssertEqual(w.apps.applications.map(\.path), [textEdit.path])
        XCTAssertEqual(w.undo.undoMenuItemTitle, "Undo Remove App")

        XCTAssertTrue(w.preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.general))
        w.undo.undo()
        XCTAssertEqual(w.apps.applications.map(\.path), [calculator.path, textEdit.path])
        XCTAssertEqual(w.preferences.selectedPaneIdentifier, PANEL_IDENTIFIER.application, "Apps comes forward")
        XCTAssertNil(w.apps.detailController)
        XCTAssertEqual(w.apps.list.selectedID, AnyHashable(id), "the row is selected")
        XCTAssertTrue(w.window.firstResponder === w.apps.list)

        w.apps.openApplication(withID: try XCTUnwrap(w.apps.rowID(for: textEdit)))
        w.undo.redo()
        XCTAssertEqual(w.apps.applications.map(\.path), [textEdit.path])
        XCTAssertNil(w.apps.detailController, "the list, where the change is")
        XCTAssertNil(w.apps.list.rows.first { $0.id == AnyHashable(id) })
    }

    // MARK: - Undo of a step of the whole pane or part, shown where it acts too

    /// "Undo Reset Shortcut Ring" from another pane (⌘Z after a slider elsewhere, which
    /// registers nothing): the Shortcut Ring pane comes forward and shows the ring that is
    /// back; Redo too. The reset itself, clicked on the pane, moves nothing.
    func testUndoOfTheRingsResetFromAnotherPaneShowsTheRingPane() throws {
        Options.shared.ring[2] = ShortcutRingPlace(SystemShortcut.paste)
        let edited = Options.shared.ring
        let w = try makeWindow()
        XCTAssertTrue(w.preferences.selectPane(withIdentifier: RingPreferencesViewController.tabIdentifier))
        step(w.undo) { w.ring.resetToDefaults.click(nil) }
        XCTAssertEqual(Options.shared.ring, .default)
        XCTAssertEqual(w.undo.undoMenuItemTitle, "Undo Reset Shortcut Ring")
        XCTAssertEqual(w.preferences.selectedPaneIdentifier, RingPreferencesViewController.tabIdentifier)

        XCTAssertTrue(w.preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.general))
        w.undo.undo()
        XCTAssertEqual(Options.shared.ring, edited)
        XCTAssertEqual(w.preferences.selectedPaneIdentifier, RingPreferencesViewController.tabIdentifier, "the pane comes forward")
        XCTAssertEqual(w.ring.placePopUps[2].binding.systemShortcutName, SystemShortcut.paste.identifier, "and shows the ring")

        XCTAssertTrue(w.preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.general))
        w.undo.redo()
        XCTAssertEqual(Options.shared.ring, .default)
        XCTAssertEqual(w.preferences.selectedPaneIdentifier, RingPreferencesViewController.tabIdentifier, "Redo too")
    }

    /// "Undo Change What Opens the Ring" from another pane: the binding of Buttons goes
    /// again, and the Shortcut Ring pane comes forward with its row saying so; Redo too.
    func testUndoOfWhatOpensTheRingFromAnotherPaneShowsTheRingPane() throws {
        let w = try makeWindow()
        w.ring.bindingSummary = { .current }
        XCTAssertTrue(w.preferences.selectPane(withIdentifier: RingPreferencesViewController.tabIdentifier))
        let chooser = try XCTUnwrap(w.ring.triggerChooser)
        chooser.deviceSource = ButtonsDeviceSource(
            captureStatus: { _ in .normal }, deviceName: { nil }, isBusy: { false }, refresh: {}, warnBluetoothButton: { _ in }
        )
        let back = RecordedEvent(type: .mouse, code: 3, modifiers: 0, deviceFilter: nil)
        step(w.undo) { chooser.choose(back) }
        XCTAssertEqual(Options.shared.buttons.binding.map(\.triggerEvent), [back])
        XCTAssertEqual(w.undo.undoMenuItemTitle, "Undo Change What Opens the Ring")
        let name = ButtonTriggerNaming.title(for: back)
        XCTAssertEqual(w.ring.triggerButton.shownTitle, name)

        XCTAssertTrue(w.preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.scrolling))
        w.undo.undo()
        XCTAssertEqual(Options.shared.buttons.binding, [])
        XCTAssertEqual(w.preferences.selectedPaneIdentifier, RingPreferencesViewController.tabIdentifier, "the pane comes forward")
        XCTAssertEqual(w.ring.triggerButton.shownTitle, "Choose", "its row says that nothing opens the ring")

        XCTAssertTrue(w.preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.scrolling))
        w.undo.redo()
        XCTAssertEqual(Options.shared.buttons.binding.map(\.triggerEvent), [back])
        XCTAssertEqual(w.preferences.selectedPaneIdentifier, RingPreferencesViewController.tabIdentifier, "Redo too")
        XCTAssertEqual(w.ring.triggerButton.shownTitle, name)
    }

    /// "Copy from Shortcut Ring" under an app's own ring, undone after its page closed and
    /// while General shows, and redone while the page shows another part: Apps comes
    /// forward with the app's page on its Shortcut Ring part. A ring kept for later (the
    /// switch on again) takes the Undo too, and nothing comes forward: the part would show
    /// the switch alone.
    func testUndoOfAnAppsRingResetShowsItsRingPartUnlessTheRingIsKeptForLater() throws {
        let calculator = Application(path: Self.calculator)
        Options.shared.application.applications.append(calculator)
        calculator.setUsesGeneralRing(false, general: Options.shared.ring)
        calculator.ring?[5] = ShortcutRingPlace(SystemShortcut.paste)
        let edited = try XCTUnwrap(calculator.ownRingPlaces)
        let w = try makeWindow()
        XCTAssertTrue(w.preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.application))
        w.apps.openApplication(withID: try XCTUnwrap(w.apps.rowID(for: calculator)), part: .ring)
        let part = try XCTUnwrap(w.apps.detailController?.ringPart)
        step(w.undo) { part.resetToDefaults.click(nil) }
        XCTAssertEqual(calculator.ownRingPlaces, ShortcutRingSettings.default.places)
        XCTAssertEqual(w.undo.undoMenuItemTitle, "Undo Copy from Shortcut Ring in Calculator")

        w.apps.showList(focusList: false)
        XCTAssertTrue(w.preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.general))
        w.undo.undo()
        XCTAssertEqual(calculator.ownRingPlaces, edited)
        XCTAssertEqual(w.preferences.selectedPaneIdentifier, PANEL_IDENTIFIER.application, "Apps comes forward")
        let page = try XCTUnwrap(w.apps.detailController)
        XCTAssertTrue(page.application === calculator)
        XCTAssertEqual(page.shownPart, .ring)
        XCTAssertEqual(
            page.ringPart.ringController?.placePopUps[5].binding.systemShortcutName, SystemShortcut.paste.identifier,
            "the page shows the ring that is back"
        )

        page.show(.buttons)
        w.undo.redo()
        XCTAssertEqual(calculator.ownRingPlaces, ShortcutRingSettings.default.places)
        XCTAssertEqual(page.shownPart, .ring, "Redo shows its part too")

        // Kept for later: the Undo reaches it, out of sight as the ring is.
        calculator.setUsesGeneralRing(true, general: Options.shared.ring)
        w.apps.showList(focusList: false)
        XCTAssertTrue(w.preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.general))
        w.undo.undo()
        XCTAssertEqual(calculator.ring?.places, edited, "the kept ring is back as it was")
        XCTAssertTrue(calculator.usesGeneralRing)
        XCTAssertEqual(w.preferences.selectedPaneIdentifier, PANEL_IDENTIFIER.general, "nothing comes forward")
    }

    // MARK: - Swap

    private func calculatorPlace() -> ShortcutRingPlace {
        return ShortcutRingPlace(openTarget: OpenTargetPayload(
            path: Self.calculator, bundleID: "com.apple.calculator", arguments: "", kind: .application
        ))
    }

    /// A swap exchanges two places whole, in one write: recorded keys with their name and
    /// icon change over with an app to open, nothing is recorded or typed again. The other
    /// six places and the freeze switch stay. An action this version does not run moves as
    /// it is stored. A swap that would change nothing writes nothing and leaves no step.
    func testSwapMovesANamedShortcutWithItsNameAndIcon() throws {
        let saved = ShortcutRingPlace(action: Self.keys, label: try label("Save All"))
        let opens = calculatorPlace()
        let newer = ShortcutRingPlace(action: "somethingNewer")
        var ring = ShortcutRingSettings.default
        ring[1] = saved
        ring[5] = opens
        ring[3] = newer
        ring[6] = .empty
        ring.freezePointer = true
        Options.shared.ring = ring
        let controller = RingPreferencesViewController()
        controller.bindingSummary = { ShortcutRingBindingSummary(triggerTitles: []) }
        _ = controller.view
        let undo = UndoManager()
        undo.groupsByEvent = false
        controller.paneUndoManager = undo
        var writes = 0
        let observers = Options.shared.observerCountForTests
        Options.shared.observe([.ring]) { _ in writes += 1 }
        defer { Options.shared.removeNewestObserversForTests(Options.shared.observerCountForTests - observers) }

        step(undo) { controller.swapPlace(1, with: 5) }
        XCTAssertEqual(writes, 1, "one write")
        XCTAssertEqual(Options.shared.ring[1], opens)
        XCTAssertEqual(Options.shared.ring[5], saved, "the keys with their name and icon")
        var expected = ring
        expected[1] = opens
        expected[5] = saved
        XCTAssertEqual(Options.shared.ring, expected, "the other six places and the freeze switch stay")
        XCTAssertTrue(Options.shared.ring.freezePointer)
        XCTAssertEqual(controller.placePopUps[5].binding.label, saved.label, "the row shows them")
        XCTAssertEqual(controller.placePopUps[1].binding.openTarget, opens.openTarget)
        XCTAssertEqual(controller.previewView.face.places[5].title, "Save All", "and so does the drawing")
        XCTAssertEqual(controller.selectedPlace, 1)
        XCTAssertEqual(undo.undoMenuItemTitle, "Undo Swap")

        // What this version does not run moves as stored, and shows as empty where it lands.
        step(undo) { controller.swapPlace(3, with: 0) }
        XCTAssertEqual(Options.shared.ring[0], newer)
        XCTAssertEqual(Options.shared.ring[3], ShortcutRingPlace(SystemShortcut.missionControl))
        XCTAssertEqual(controller.placePopUps[0].menu?.items.first?.title, "No Action")
        XCTAssertEqual(writes, 2)

        // Nothing to see: two places that show as empty, a place with itself, the same twice.
        Options.shared.ring[2] = ShortcutRingPlace(SystemShortcut.missionControl)
        controller.reload()
        writes = 0
        // (The manager would take a step here by itself: an empty group of the test's is one.)
        undo.groupsByEvent = true
        controller.swapPlace(0, with: 6)
        controller.swapPlace(4, with: 4)
        controller.swapPlace(2, with: 3)
        controller.swapPlace(1, with: 12)
        XCTAssertEqual(writes, 0)
        XCTAssertEqual(undo.groupingLevel, 0, "no new step")
        undo.groupsByEvent = false
        XCTAssertEqual(undo.undoMenuItemTitle, "Undo Swap")
        undo.undo()
        XCTAssertEqual(Options.shared.ring[0], ShortcutRingPlace(SystemShortcut.missionControl), "the step before")
    }

    /// "Undo Swap" is one step that puts both places back, and "Redo Swap" swaps them again.
    /// It writes the two places as they were, whatever happened to the ring in between, as
    /// a place's Undo writes one.
    func testUndoSwapPutsBothPlacesBackAndRedoSwapsAgain() throws {
        let saved = ShortcutRingPlace(action: Self.keys, label: try label("Save All"))
        Options.shared.ring[1] = saved
        let before = Options.shared.ring
        let w = try makeWindow()
        XCTAssertTrue(w.preferences.selectPane(withIdentifier: RingPreferencesViewController.tabIdentifier))
        // From the row's own menu, as the keyboard reaches it.
        let submenu = try XCTUnwrap(w.ring.placePopUps[1].trailingItem?.submenu)
        submenu.delegate?.menuNeedsUpdate?(submenu)
        let item = try XCTUnwrap(submenu.items.first { ($0.representedObject as? RingPlaceSwap)?.other == 4 })
        XCTAssertEqual(item.title, "Bottom (\(SystemShortcut.appExpose.localizedName))")
        try step(w.undo) { XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item)) }
        XCTAssertEqual(Options.shared.ring[4], saved)
        XCTAssertEqual(Options.shared.ring[1], before[4])
        XCTAssertEqual(w.undo.undoMenuItemTitle, "Undo Swap")

        w.ring.selectPlace(7)
        w.window.makeFirstResponder(nil)
        w.undo.undo()
        XCTAssertEqual(Options.shared.ring, before, "both places back")
        XCTAssertFalse(w.undo.canUndo, "one step")
        XCTAssertEqual(w.undo.redoMenuItemTitle, "Redo Swap")
        XCTAssertEqual(w.ring.placePopUps[1].binding.label, saved.label, "the rows show it")
        XCTAssertEqual(w.ring.selectedPlace, 1, "the row of the place whose menu was used")
        XCTAssertTrue(w.window.firstResponder === w.ring.placePopUps[1])

        w.undo.redo()
        XCTAssertEqual(Options.shared.ring[4], saved)
        XCTAssertEqual(Options.shared.ring[1], before[4])
        XCTAssertEqual(w.undo.undoMenuItemTitle, "Undo Swap")
        XCTAssertFalse(w.undo.canRedo)

        // The ring changed in between (an import, "Reset to Defaults"): the two remembered
        // places come back all the same, and Redo puts back what Undo found there.
        Options.shared.ring[1] = ShortcutRingPlace(SystemShortcut.copy)
        Options.shared.ring[6] = .empty
        w.undo.undo()
        XCTAssertEqual(Options.shared.ring[1], saved)
        XCTAssertEqual(Options.shared.ring[4], before[4])
        XCTAssertEqual(Options.shared.ring[6], .empty, "the others are left alone")
        w.undo.redo()
        XCTAssertEqual(Options.shared.ring[1], ShortcutRingPlace(SystemShortcut.copy))
        XCTAssertEqual(Options.shared.ring[4], saved)
    }

    /// From another pane: the Shortcut Ring pane comes forward, its folded places open and
    /// the row of the place whose menu was used is selected.
    func testUndoSwapFromAnotherPaneShowsTheRingPaneWithTheRowSelected() throws {
        let w = try makeWindow()
        XCTAssertTrue(w.preferences.selectPane(withIdentifier: RingPreferencesViewController.tabIdentifier))
        let places = try XCTUnwrap(w.ring.placesSection)
        XCTAssertFalse(places.showsBody, "nothing opens the ring: the places are folded")
        try step(w.undo) { w.ring.swapPlace(6, with: 2) }
        XCTAssertEqual(Options.shared.ring[6], ShortcutRingSettings.default[2])
        XCTAssertFalse(places.showsBody, "a swap at the drawing leaves them folded")

        XCTAssertTrue(w.preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.general))
        XCTAssertNil(w.ring.view.window, "the pane is out of the window")
        w.undo.undo()
        XCTAssertEqual(Options.shared.ring, .default)
        XCTAssertEqual(w.preferences.selectedPaneIdentifier, RingPreferencesViewController.tabIdentifier)
        XCTAssertTrue(places.showsBody, "the places open")
        XCTAssertEqual(w.ring.selectedPlace, 6)
        XCTAssertTrue(w.window.firstResponder === w.ring.placePopUps[6])
        XCTAssertEqual(w.ring.placePopUps[2].binding.systemShortcutName, ShortcutRingSettings.default[2].action)

        XCTAssertTrue(w.preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.general))
        w.undo.redo()
        XCTAssertEqual(Options.shared.ring[6], ShortcutRingSettings.default[2])
        XCTAssertEqual(w.preferences.selectedPaneIdentifier, RingPreferencesViewController.tabIdentifier)
        XCTAssertEqual(w.ring.selectedPlace, 6)
    }

    /// A swap in an app's own ring changes that ring alone. Its Undo works after the page
    /// closed and shows the page on its Shortcut Ring part, the row selected; for an app
    /// that is no longer on the list it does nothing.
    func testSwapInAnAppsOwnRingLeavesTheGeneralRingAndUndoWorksAfterThePageClosed() throws {
        let calculator = Application(path: Self.calculator)
        Options.shared.application.applications.append(calculator)
        calculator.setUsesGeneralRing(false, general: Options.shared.ring)
        let saved = ShortcutRingPlace(action: Self.keys, label: try label("Save All"))
        calculator.ring?[5] = saved
        let before = try XCTUnwrap(calculator.ownRingPlaces)
        let w = try makeWindow()
        XCTAssertTrue(w.preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.application))
        w.apps.openApplication(withID: try XCTUnwrap(w.apps.rowID(for: calculator)), part: .ring)
        let ring = try XCTUnwrap(w.apps.detailController?.ringPart.ringController)
        let preview = try XCTUnwrap(ring.previewView)
        // The secondary click on the drop of "Bottom left", then "Swap With ▸ Top (…)".
        let drop = preview.dropRect(ofPlace: 5)
        let click = try XCTUnwrap(NSEvent.mouseEvent(
            with: .rightMouseDown, location: preview.convert(NSPoint(x: drop.midX, y: drop.midY), to: nil), modifierFlags: [],
            timestamp: 0, windowNumber: w.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        let menu = try XCTUnwrap(preview.menu(for: click))
        let submenu = try XCTUnwrap(menu.items.first?.submenu)
        submenu.delegate?.menuNeedsUpdate?(submenu)
        let item = try XCTUnwrap(submenu.items.first)
        XCTAssertEqual(item.title, "Top (Mission Control)")
        try step(w.undo) { XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item)) }
        XCTAssertEqual(calculator.ownRingPlaces?[0], saved, "with its name and icon")
        XCTAssertEqual(calculator.ownRingPlaces?[5], before[0])
        XCTAssertEqual(Options.shared.ring, .default, "the general ring is untouched")
        XCTAssertEqual(w.undo.undoMenuItemTitle, "Undo Swap")
        XCTAssertEqual(ring.placePopUps[0].binding.label, saved.label)

        w.apps.showList(focusList: false)
        XCTAssertNil(w.apps.detailController, "the page closed")
        XCTAssertTrue(w.preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.general))
        w.undo.undo()
        XCTAssertEqual(calculator.ownRingPlaces, before)
        XCTAssertEqual(Options.shared.ring, .default)
        XCTAssertEqual(w.preferences.selectedPaneIdentifier, PANEL_IDENTIFIER.application)
        let page = try XCTUnwrap(w.apps.detailController)
        XCTAssertTrue(page.application === calculator)
        XCTAssertEqual(page.shownPart, .ring)
        let shown = try XCTUnwrap(page.ringPart.ringController)
        XCTAssertEqual(shown.placePopUps[5].binding.label, saved.label)
        XCTAssertEqual(shown.selectedPlace, 5, "the row of the place whose menu was used")
        XCTAssertTrue(w.window.firstResponder === shown.placePopUps[5])

        w.undo.redo()
        XCTAssertEqual(calculator.ownRingPlaces?[0], saved)
        XCTAssertEqual(shown.placePopUps[0].binding.label, saved.label, "the page on show follows")
        XCTAssertEqual(Options.shared.ring, .default)

        // The app was removed: nothing happens, and nothing of another ring is touched.
        let swapped = calculator.ring
        Options.shared.application.applications = EnhanceArray<Application>(
            withArray: [], matchKey: "path", forObserver: { Options.shared.markChanged(.application) }
        )
        w.undo.undo()
        XCTAssertEqual(calculator.ring, swapped)
        XCTAssertEqual(Options.shared.ring, .default)
    }

    // MARK: - The drops in the window

    /// Where a popover of a drop stands, in the window as the app makes it (720 × 500): the
    /// view over each drop is the drop's circle at rest, wholly inside the card and wholly
    /// in sight (an app's page cuts the ring's view at its margins, not the card), in the
    /// pane and on an app's Shortcut Ring part. (A popover is a window of its own: under the
    /// pane's right-hand drops, 58 pt from the window's edge, it stands past that edge.)
    func testEveryDropsAnchorIsItsCircleInSightInThePaneAndOnAnAppsPage() throws {
        let calculator = Application(path: Self.calculator)
        Options.shared.application.applications.append(calculator)
        calculator.setUsesGeneralRing(false, general: Options.shared.ring)
        let w = try makeWindow()
        func check(_ ring: RingPreferencesViewController, _ name: String) throws {
            let preview = try XCTUnwrap(ring.previewView)
            w.window.contentView?.layoutSubtreeIfNeeded()
            XCTAssertFalse(preview.isHiddenOrHasHiddenAncestor, name)
            for place in 0..<8 {
                let anchor = preview.anchor(forPlace: place)
                XCTAssertEqual(anchor.frame, preview.dropRect(ofPlace: place), "\(name) \(place)")
                XCTAssertTrue(preview.bounds.contains(anchor.frame), "\(name) \(place): inside the card")
                // Nothing cuts it: it lies inside every view above it that clips, and the window.
                var above = anchor.superview
                while let view = above {
                    let isContent = view === w.window.contentView
                    if view.clipsToBounds || view is NSClipView || isContent {
                        XCTAssertTrue(
                            view.bounds.contains(anchor.convert(anchor.bounds, to: view)),
                            "\(name) \(place): cut by \(type(of: view)) \(view.identifier?.rawValue ?? "")"
                        )
                    }
                    above = isContent ? nil : view.superview
                }
                XCTAssertEqual(anchor.frame.size, NSSize(width: 37, height: 37))
            }
            XCTAssertEqual(preview.subviews.count, 8)
        }
        XCTAssertTrue(w.preferences.selectPane(withIdentifier: RingPreferencesViewController.tabIdentifier))
        try check(w.ring, "pane")
        XCTAssertTrue(w.preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.application))
        w.apps.openApplication(withID: try XCTUnwrap(w.apps.rowID(for: calculator)), part: .ring)
        try check(try XCTUnwrap(w.apps.detailController?.ringPart.ringController), "app's page")
    }

    /// The pane on its own (no window's panes): Undo and Redo go to the pane's undo manager
    /// and show on the pane.
    func testThePaneOnItsOwnTakesUndoAndShowsIt() {
        let controller = RingPreferencesViewController()
        controller.bindingSummary = { ShortcutRingBindingSummary(triggerTitles: []) }
        _ = controller.view
        let undo = UndoManager()
        undo.groupsByEvent = false
        controller.paneUndoManager = undo
        step(undo) { controller.placePopUps[0].onShortcutSelected?(SystemShortcut.paste) }
        XCTAssertEqual(Options.shared.ring[0], ShortcutRingPlace(SystemShortcut.paste))
        controller.selectPlace(4)
        undo.undo()
        XCTAssertEqual(Options.shared.ring, .default)
        XCTAssertEqual(controller.placePopUps[0].binding.systemShortcutName, ShortcutRingSettings.default[0].action)
        XCTAssertEqual(controller.selectedPlace, 0)
        XCTAssertFalse(undo.canUndo)
        undo.redo()
        XCTAssertEqual(Options.shared.ring[0], ShortcutRingPlace(SystemShortcut.paste))
    }
}
