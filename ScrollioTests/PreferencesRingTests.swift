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

    /// A click on a place of the drawing while the places are folded opens them and
    /// selects that place's row.
    func testAClickOnThePlaceOfTheDrawingOpensFoldedPlaces() throws {
        let controller = makeController()
        let places = try XCTUnwrap(controller.placesSection)
        places.prefersReducedMotion = { true }
        controller.previewView.onPlaceClicked?(4)
        XCTAssertTrue(places.showsBody)
        XCTAssertEqual(controller.selectedPlace, 4)
        XCTAssertFalse(controller.placePopUps[4].isHiddenOrHasHiddenAncestor)
        XCTAssertEqual(controller.view.frame.size, controller.view.fittingSize)
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
        XCTAssertNil(ShortcutRingController.preparedFace(for: Options.shared.ring),
                     "a ring that opens nothing keeps no face: at a press it is whole without a look on disk")
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
