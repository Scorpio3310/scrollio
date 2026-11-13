//
//  PreferencesRingTests.swift
//  ScrollioTests
//
//  The Shortcut Ring pane: its row for what opens the ring and its way to the Buttons
//  pane, the eight places with their pull-downs, what the pull-downs offer and store, the
//  drawing that follows the row pointed at; and the Buttons pane's side: the action in its
//  menu, for a button and for a key. Nothing is shown on screen.
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

    private func item(_ identifier: String, in popUp: NSPopUpButton) -> NSMenuItem? {
        func find(_ menu: NSMenu?) -> NSMenuItem? {
            for item in menu?.items ?? [] {
                if item.action != nil, item.representedObject as? String == identifier { return item }
                if let found = find(item.submenu) { return found }
            }
            return nil
        }
        return find(popUp.menu)
    }

    // MARK: The pane

    func testThePaneIsCalledShortcutRingAndIsAsWideAsTheOthers() {
        let controller = makeController()
        XCTAssertEqual(controller.title, "Shortcut Ring")
        XCTAssertEqual(RingPreferencesViewController.tabIdentifier, "ring")
        XCTAssertEqual(controller.view.frame.width, 520)
        XCTAssertFalse(controller.view.hasAmbiguousLayout)
        XCTAssertEqual(controller.sections.count, 4, "the drawing, what opens the ring, its line, the places")
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
    }

    func testChoosingAnActionStoresItAndNoActionEmptiesThePlace() throws {
        let controller = makeController()
        let popUp = controller.placePopUps[1]
        controller.actionSelected(try XCTUnwrap(item("undo", in: popUp)))
        XCTAssertEqual(Options.shared.ring[1].action, "undo")
        XCTAssertEqual(popUp.menu?.items.first?.title, "Undo")
        XCTAssertEqual(controller.previewView.face.places[1].title, "Undo", "the drawing follows")

        controller.actionSelected(try XCTUnwrap(item("", in: popUp)))
        XCTAssertTrue(Options.shared.ring[1].isEmpty)
        XCTAssertEqual(popUp.menu?.items.first?.title, "No Action")
        XCTAssertTrue(controller.previewView.face.places[1].isEmpty)
        // The other places stay.
        XCTAssertEqual(Options.shared.ring[0].action, "missionControl")
        XCTAssertEqual(Options.shared.ring[2].action, "moveSpaceRight")
    }

    /// A pull-down offers the keyboard shortcuts a place runs, by category, and nothing a
    /// place must not hold: no click, no held action, no Logitech action, no Gesture
    /// Navigation, not the ring itself, no app to open and no recorded key.
    func testAPullDownOffersWhatAPlaceRunsAndNothingElse() {
        let controller = makeController()
        let menu = controller.placePopUps[0].menu
        let top = (menu?.items ?? []).dropFirst()
        XCTAssertEqual(top.first?.title, "No Action")
        let categories = top.filter { $0.submenu != nil }
        XCTAssertEqual(categories.map { $0.title }, SystemShortcut.shortcutsByCategory.map { SystemShortcut.localizedCategoryName($0.category) })
        let offered = categories.flatMap { $0.submenu?.items ?? [] }.compactMap { $0.representedObject as? String }
        XCTAssertTrue(offered.contains("copy"))
        XCTAssertTrue(offered.contains("screenshotSelection"))
        XCTAssertEqual(offered.count, ShortcutRingPlace.offeredCategories.reduce(0) { $0 + $1.shortcuts.count })
        for identifier in offered {
            XCTAssertTrue(ShortcutRingPlace(action: identifier).runs, identifier)
        }
        let leaves = top.filter { $0.submenu == nil && !$0.isSeparatorItem }
        XCTAssertEqual(leaves.count, 1, "besides the categories only No Action")
    }

    // MARK: What opens the ring

    func testWithNothingBoundTheRowOffersToSetOneUp() {
        let controller = makeController()
        XCTAssertEqual(controller.triggerRow.title, "Button or key")
        XCTAssertEqual(controller.triggerRow.explanation, "Nothing opens the ring yet. Set up a mouse button or a key combination.")
        XCTAssertEqual(controller.triggerButton.title, "Set Up…")
        var requests: [Bool] = []
        controller.openButtonsPane = { requests.append($0) }
        controller.triggerButton.performClick(nil)
        XCTAssertEqual(requests, [true], "it records a button or key that gets the ring")
    }

    func testWithATriggerTheRowNamesItAndLeadsToItsRow() {
        summary = ShortcutRingBindingSummary(triggerTitles: ["Thumb panel", "⌃⌥ Space"])
        let controller = makeController()
        XCTAssertEqual(controller.triggerRow.explanation, "Thumb panel and ⌃⌥ Space.")
        XCTAssertEqual(controller.triggerButton.title, "Change")
        var requests: [Bool] = []
        controller.openButtonsPane = { requests.append($0) }
        controller.triggerButton.performClick(nil)
        XCTAssertEqual(requests, [false])
    }

    /// The line under the first box answers "can a key open it?": yes, also a keystroke
    /// that Logi Options+ sends.
    func testTheLineUnderTheBoxSaysThatAKeyCombinationWorks() {
        let controller = makeController()
        let note = controller.triggerNoteLabel.stringValue
        XCTAssertTrue(note.contains("key combination"))
        XCTAssertTrue(note.contains("Logi Options+"))
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

    /// Every explanation of the pane is plain sentences that fit two lines of its box.
    func testEveryExplanationFitsTwoLines() {
        summary = ShortcutRingBindingSummary(triggerTitles: ["Thumb panel", "⌃⌥ Space"])
        let bound = makeController().triggerRow.explanation ?? ""
        summary = ShortcutRingBindingSummary(triggerTitles: [])
        let controller = makeController()
        let width = RingPreferencesViewController.boxWidth - 2 * PreferencesGroupedForm.rowHorizontalInset
        let font = PreferencesGroupedForm.explanationFont
        let twoLines = 2 * ceil(font.ascender - font.descender + font.leading) + 2
        let texts = [
            bound, controller.triggerRow.explanation ?? "",
            controller.triggerNoteLabel.stringValue, controller.placesHintLabel.stringValue,
        ]
        for text in texts {
            XCTAssertFalse(text.isEmpty)
            XCTAssertTrue(text.hasSuffix("."), text)
            XCTAssertLessThanOrEqual(text.count, 100, text)
            let height = (text as NSString).boundingRect(
                with: NSSize(width: width, height: 1000), options: [.usesLineFragmentOrigin], attributes: [.font: font]
            ).height
            XCTAssertLessThanOrEqual(height, twoLines, text)
        }
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
        controller.placeHoverChanged(6, inside: true)
        controller.placeHoverChanged(5, inside: false)
        XCTAssertEqual(preview.lit, 6, "leaving the old row after entering the new one keeps the new one")
        controller.placeHoverChanged(6, inside: false)
        XCTAssertNil(preview.lit)
        // Each row tells when the pointer is over it.
        for row in controller.placeRows {
            XCTAssertEqual(row.trackingAreas.filter { $0.owner === controller }.count, 1)
        }
        XCTAssertNil(preview.hitTest(NSPoint(x: 10, y: 10)), "a picture")
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
