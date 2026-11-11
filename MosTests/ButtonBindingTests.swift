import XCTest
@testable import Mos_Debug

private final class ShortcutMenuTestTarget: NSObject {
    @objc func noop(_ sender: Any?) {}
}

final class ButtonBindingTests: XCTestCase {

    private func makeResolvedPresentation(
        shortcut: SystemShortcut.Shortcut? = nil,
        customBindingName: String? = nil,
        isRecording: Bool = false
    ) -> ActionPresentation {
        ActionDisplayResolver().resolve(
            shortcut: shortcut,
            customBindingName: customBindingName,
            isRecording: isRecording
        )
    }

    /// A button's action pull-down, as the Buttons pane makes it. Nothing is recorded:
    /// tests call the recorder's delegate methods themselves.
    private func makePullDown(
        binding: ButtonBinding,
        onShortcutSelected: @escaping (SystemShortcut.Shortcut?) -> Void = { _ in },
        onOpenTargetSelectionRequested: @escaping () -> Void = {},
        onGestureSettingsRequested: @escaping () -> Void = {}
    ) -> ButtonActionPullDown {
        let pullDown = ButtonActionPullDown(binding: binding)
        pullDown.onShortcutSelected = onShortcutSelected
        pullDown.onOpenTargetSelectionRequested = onOpenTargetSelectionRequested
        pullDown.onGestureSettingsRequested = onGestureSettingsRequested
        pullDown.startShortcutRecorder = { _ in }
        return pullDown
    }

    /// The title a pull-down shows: its first item.
    private func shownTitle(_ pullDown: NSPopUpButton) -> String? {
        return pullDown.menu?.items.first?.title
    }

    private func makeBinding(_ shortcut: SystemShortcut.Shortcut) -> ButtonBinding {
        return ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            systemShortcutName: shortcut.identifier
        )
    }

    // MARK: - Gesture Navigation in the action menu

    func testShowGestureSettings_onlyWhileGestureNavigationIsTheAction() throws {
        let gesture = makePullDown(binding: makeBinding(SystemShortcut.mouseGestureNavigation))
        let menu = try XCTUnwrap(gesture.menu)
        let item = try XCTUnwrap(gesture.gestureSettingsItem)
        XCTAssertFalse(item.isHidden)
        XCTAssertEqual(item.title, "Show Gesture Settings")
        // Right under Gesture Navigation.
        let gestureIndex = try XCTUnwrap(menu.items.firstIndex {
            ($0.representedObject as? SystemShortcut.Shortcut)?.identifier == SystemShortcut.mouseGestureNavigation.identifier
        })
        XCTAssertEqual(menu.index(of: item), gestureIndex + 1)

        let copy = makePullDown(binding: makeBinding(SystemShortcut.copy))
        XCTAssertEqual(copy.gestureSettingsItem?.isHidden, true)
    }

    func testShowGestureSettings_asksForTheGesturesPaneWithoutChangingTheBinding() throws {
        var requests = 0
        var selected = 0
        let pullDown = makePullDown(
            binding: makeBinding(SystemShortcut.mouseGestureNavigation),
            onShortcutSelected: { _ in selected += 1 },
            onGestureSettingsRequested: { requests += 1 }
        )
        let item = try XCTUnwrap(pullDown.gestureSettingsItem)

        pullDown.shortcutSelected(item)

        XCTAssertEqual(requests, 1)
        XCTAssertEqual(selected, 0)
        XCTAssertEqual(shownTitle(pullDown), SystemShortcut.mouseGestureNavigation.localizedName)
    }

    func testSelectingGestureNavigation_bindsItAndOffersItsSettings() throws {
        var requests = 0
        var selected: [String?] = []
        let pullDown = makePullDown(
            binding: makeBinding(SystemShortcut.copy),
            onShortcutSelected: { selected.append($0?.identifier) },
            onGestureSettingsRequested: { requests += 1 }
        )
        let menu = try XCTUnwrap(pullDown.menu)
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.representedObject = SystemShortcut.mouseGestureNavigation

        pullDown.shortcutSelected(item)

        XCTAssertEqual(selected, [SystemShortcut.mouseGestureNavigation.identifier])
        XCTAssertEqual(requests, 0, "no popover any more: the menu offers the Gestures pane")
        XCTAssertTrue(pullDown.menu === menu, "choosing an item never replaces the menu it came from")
        XCTAssertEqual(pullDown.gestureSettingsItem?.isHidden, false)
    }

    func testGestureActionCategories_offerOneShotActionsOnly() {
        let identifiers = MouseGestureSettingsControls.actionCategories(showLogiActions: false)
            .flatMap { $0.shortcuts.map(\.identifier) }

        XCTAssertTrue(identifiers.contains(SystemShortcut.moveSpaceLeft.identifier))
        XCTAssertTrue(identifiers.contains(SystemShortcut.navigateBack.identifier))
        XCTAssertTrue(identifiers.contains(SystemShortcut.mouseBackClick.identifier))
        XCTAssertFalse(identifiers.contains(SystemShortcut.mouseGestureNavigation.identifier))
        XCTAssertFalse(identifiers.contains(SystemShortcut.modifierShift.identifier))
        XCTAssertFalse(identifiers.contains(SystemShortcut.mosScrollDash.identifier))
        XCTAssertFalse(identifiers.contains(SystemShortcut.logiSmartShiftToggle.identifier))

        let withLogi = MouseGestureSettingsControls.actionCategories(showLogiActions: true)
            .flatMap { $0.shortcuts.map(\.identifier) }
        XCTAssertTrue(withLogi.contains(SystemShortcut.logiSmartShiftToggle.identifier))
    }

    private func flushMainQueue() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }

    private func advanceMainRunLoop(by interval: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(interval))
    }

    func testPrepareCustomCache_regularKey() {
        var binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            systemShortcutName: "custom::40:1048576"
        )
        binding.prepareCustomCache()
        XCTAssertEqual(binding.cachedCustomCode, 40)
        XCTAssertEqual(binding.cachedCustomModifiers, 1048576)
    }

    func testPrepareCustomCache_modifierKey_stripsRedundantFlag() {
        var binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            systemShortcutName: "custom::56:131072"
        )
        binding.prepareCustomCache()
        XCTAssertEqual(binding.cachedCustomCode, 56)
        XCTAssertEqual(binding.cachedCustomModifiers, 0)
    }

    func testPrepareCustomCache_nonCustomBinding() {
        var binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            systemShortcutName: "missionControl"
        )
        binding.prepareCustomCache()
        XCTAssertNil(binding.cachedCustomCode)
        XCTAssertNil(binding.cachedCustomModifiers)
    }

    func testPrepareCustomCache_invalidFormat() {
        var binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            systemShortcutName: "custom::abc:xyz"
        )
        binding.prepareCustomCache()
        XCTAssertNil(binding.cachedCustomCode)
        XCTAssertNil(binding.cachedCustomModifiers)
    }

    func testPrepareCustomCache_masksIrrelevantModifierFlags() {
        let rawModifiers = UInt64(NSEvent.ModifierFlags.command.union(.shift).rawValue) | (1 << 24)
        var binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            systemShortcutName: "custom::21:\(rawModifiers)"
        )

        binding.prepareCustomCache()

        XCTAssertEqual(binding.cachedCustomCode, 21)
        XCTAssertEqual(
            binding.cachedCustomModifiers,
            UInt64(NSEvent.ModifierFlags.command.union(.shift).rawValue)
        )
    }

    func testPrepareCustomCache_typedMouseBindingPreservesMouseType() {
        var binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 5, modifiers: 0, displayComponents: ["🖱5"], deviceFilter: nil),
            systemShortcutName: "custom::mouse:3:0"
        )

        binding.prepareCustomCache()

        XCTAssertEqual(binding.cachedCustomType, .mouse)
        XCTAssertEqual(binding.cachedCustomCode, 3)
        XCTAssertEqual(binding.cachedCustomModifiers, 0)
    }

    func testPrepareCustomCache_legacyHighCodeBindingInfersMouseType() {
        var binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 5, modifiers: 0, displayComponents: ["🖱5"], deviceFilter: nil),
            systemShortcutName: "custom::1006:0"
        )

        binding.prepareCustomCache()

        XCTAssertEqual(binding.cachedCustomType, .mouse)
        XCTAssertEqual(binding.cachedCustomCode, 1006)
        XCTAssertEqual(binding.cachedCustomModifiers, 0)
    }

    func testNormalizedCustomBindingName_encodesMouseType() {
        XCTAssertEqual(
            ButtonBinding.normalizedCustomBindingName(type: .mouse, code: 3, modifiers: 0),
            "custom::mouse:3:0"
        )
    }

    func testInit_withCreatedAt_preservesTimestamp() {
        let pastDate = Date(timeIntervalSince1970: 1000000)
        let binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            systemShortcutName: "test",
            createdAt: pastDate
        )
        XCTAssertEqual(binding.createdAt, pastDate)
    }

    func testInit_defaultCreatedAt_usesNow() {
        let before = Date()
        let binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            systemShortcutName: "test"
        )
        let after = Date()
        XCTAssertGreaterThanOrEqual(binding.createdAt, before)
        XCTAssertLessThanOrEqual(binding.createdAt, after)
    }

    func testCodableRoundtrip_preservesFields() {
        let original = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            systemShortcutName: "custom::56:0"
        )
        let data = try! JSONEncoder().encode(original)
        let decoded = try! JSONDecoder().decode(ButtonBinding.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.systemShortcutName, "custom::56:0")
        XCTAssertNil(decoded.cachedCustomCode)
    }

    func testEquatable_ignoresTransientCache() {
        var a = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            systemShortcutName: "custom::56:0"
        )
        let b = a
        a.prepareCustomCache()
        XCTAssertEqual(a, b)
    }

    func testPredefinedModifierShortcut_matchesEquivalentCustomBinding() {
        XCTAssertEqual(
            SystemShortcut.predefinedModifierShortcut(matchingCustomBinding: "custom::56:0")?.identifier,
            "modifierShift"
        )
        XCTAssertEqual(
            SystemShortcut.predefinedModifierShortcut(matchingCustomBinding: "custom::56:131072")?.identifier,
            "modifierShift"
        )
        XCTAssertEqual(
            SystemShortcut.predefinedModifierShortcut(matchingCustomBinding: "custom::58:524288")?.identifier,
            "modifierOption"
        )
        XCTAssertNil(SystemShortcut.predefinedModifierShortcut(matchingCustomBinding: "custom::58:131072"))
    }

    func testDisplayShortcut_matchesUniqueCustomBindingEquivalent() {
        let modifiers = UInt64(NSEvent.ModifierFlags.command.union(.shift).rawValue)
        XCTAssertEqual(
            SystemShortcut.displayShortcut(matchingBindingName: "custom::21:\(modifiers)")?.identifier,
            "screenshotSelection"
        )
    }

    func testDisplayShortcut_matchesUniqueCustomBindingEquivalentWithIrrelevantFlags() {
        let modifiers = UInt64(NSEvent.ModifierFlags.command.union(.shift).rawValue) | (1 << 24)
        XCTAssertEqual(
            SystemShortcut.displayShortcut(matchingBindingName: "custom::21:\(modifiers)")?.identifier,
            "screenshotSelection"
        )
    }

    func testDisplayShortcut_returnsNilForAmbiguousCustomBindingEquivalent() {
        let modifiers = UInt64(NSEvent.ModifierFlags.command.rawValue)
        XCTAssertNil(SystemShortcut.displayShortcut(matchingBindingName: "custom::34:\(modifiers)"))
    }

    func testDisplayShortcut_doesNotMatchMosScrollPlaceholderCode() {
        XCTAssertNil(SystemShortcut.displayShortcut(matchingBindingName: "custom::65532:0"))
    }

    func testDisplayShortcut_matchesTypedMouseBackCustomBinding() {
        XCTAssertEqual(
            SystemShortcut.displayShortcut(matchingBindingName: "custom::mouse:3:0")?.identifier,
            "mouseBackClick"
        )
    }

    func testActionDisplayResolver_prioritizesRecordingPromptOverExistingShortcut() {
        let presentation = makeResolvedPresentation(
            shortcut: SystemShortcut.screenshotSelection,
            customBindingName: "custom::1007:0",
            isRecording: true
        )

        XCTAssertEqual(presentation.kind, .recordingPrompt)
        XCTAssertEqual(presentation.title, NSLocalizedString("custom-recording-prompt", comment: ""))
        XCTAssertNil(presentation.symbolName)
        XCTAssertNil(presentation.image)
    }

    func testActionDisplayResolver_upgradesRecognizedCustomBindingToNamedAction() {
        let modifiers = UInt64(NSEvent.ModifierFlags.command.union(.shift).rawValue)
        let presentation = makeResolvedPresentation(customBindingName: "custom::21:\(modifiers)")

        XCTAssertEqual(presentation.kind, .namedAction)
        XCTAssertEqual(presentation.title, SystemShortcut.screenshotSelection.localizedName)
        XCTAssertEqual(presentation.symbolName, SystemShortcut.screenshotSelection.symbolName)
    }

    func testActionDisplayResolver_upgradesTypedMouseBackCustomBindingToNamedAction() {
        let presentation = makeResolvedPresentation(customBindingName: "custom::mouse:3:0")

        XCTAssertEqual(presentation.kind, .namedAction)
        XCTAssertEqual(presentation.title, SystemShortcut.mouseBackClick.localizedName)
    }

    func testActionDisplayResolver_showsTypedMouseCustomBindingAsText() {
        let presentation = makeResolvedPresentation(customBindingName: "custom::mouse:5:0")

        XCTAssertEqual(presentation.kind, .keyCombo)
        XCTAssertEqual(presentation.title, "Button 5")
        XCTAssertEqual(presentation.symbolName, "computermouse")
    }

    func testActionDisplayResolver_showsAKeyboardShortcutAsTextInMenuOrder() {
        // ⌘⇧ and 4, stored in any order of flags, reads as macOS menus write it. Code 21 is
        // the 4 key; the combination is not a listed action once ⌥ is added.
        let modifiers = UInt64(NSEvent.ModifierFlags.command.union(.shift).union(.option).rawValue)
        let presentation = makeResolvedPresentation(customBindingName: "custom::21:\(modifiers)")

        XCTAssertEqual(presentation.kind, .keyCombo)
        XCTAssertEqual(presentation.title, "⌥⇧⌘4")
        XCTAssertEqual(presentation.symbolName, "keyboard")
    }

    func testInputEventUsesSemanticNamesForStandardMouseBackAndForwardButtons() {
        let back = InputEvent(
            type: .mouse,
            code: 3,
            modifiers: [],
            phase: .down,
            source: .hidPP,
            device: nil
        )
        let forward = InputEvent(
            type: .mouse,
            code: 4,
            modifiers: [],
            phase: .down,
            source: .hidPP,
            device: nil
        )

        XCTAssertEqual(back.displayComponents, ["🖱️ Back"])
        XCTAssertEqual(forward.displayComponents, ["🖱️ Forward"])
    }

    func testRecordedEventDisplayComponentsRefreshLegacyStandardMouseButtonNames() {
        let back = RecordedEvent(
            type: .mouse,
            code: 3,
            modifiers: 0,
            displayComponents: ["🖱4"],
            deviceFilter: nil
        )
        let forward = RecordedEvent(
            type: .mouse,
            code: 4,
            modifiers: UInt(CGEventFlags.maskShift.rawValue),
            displayComponents: ["⇧", "🖱5"],
            deviceFilter: nil
        )

        XCTAssertEqual(back.displayComponents, ["🖱️ Back"])
        XCTAssertEqual(forward.displayComponents, ["⇧", "🖱️ Forward"])
    }

    func testRecordedEventDecodesLegacyDisplayComponentsButIgnoresStoredPresentation() throws {
        let modifiers = UInt(CGEventFlags.maskShift.rawValue)
        let json = """
        {
            "type": "mouse",
            "code": 3,
            "modifiers": \(modifiers),
            "displayComponents": ["Legacy Back"],
            "deviceFilter": null
        }
        """

        let event = try JSONDecoder().decode(RecordedEvent.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(event.displayComponents, ["⇧", "🖱️ Back"])
    }

    func testRecordedEventEncodingOmitsDisplayComponents() throws {
        let event = RecordedEvent(
            type: .mouse,
            code: 3,
            modifiers: 0,
            displayComponents: ["Legacy Back"],
            deviceFilter: nil
        )

        let data = try JSONEncoder().encode(event)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNil(object["displayComponents"])
        XCTAssertEqual(object["type"] as? String, "mouse")
        XCTAssertEqual(object["code"] as? Int, 3)
    }

    func testActionDisplayResolver_namesASingleLogitechButtonShortcutLikeARow() {
        // Code 1007 is the Logitech Forward control: it reads as the row of that button would.
        let presentation = makeResolvedPresentation(customBindingName: "custom::1007:0")

        XCTAssertEqual(presentation.kind, .keyCombo)
        XCTAssertEqual(presentation.title, "Forward button")
    }

    func testActionDisplayResolver_scrollActionsHaveASymbolAndNoBrandTag() {
        let presentation = makeResolvedPresentation(shortcut: SystemShortcut.mosScrollDash)

        XCTAssertEqual(presentation.kind, .namedAction)
        XCTAssertEqual(presentation.title, "Scroll Faster")
        XCTAssertEqual(presentation.symbolName, "speedometer")
        XCTAssertNil(presentation.image)
    }

    func testPullDown_showsASingleLogitechButtonShortcutWithASymbol() {
        let binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            systemShortcutName: "custom::1007:0"
        )

        let pullDown = makePullDown(binding: binding)

        XCTAssertEqual(shownTitle(pullDown), "Forward button")
        XCTAssertNotNil(pullDown.menu?.items.first?.image)
    }

    func testActionDisplayResolver_returnsUnboundWhenNoActionExists() {
        let presentation = makeResolvedPresentation()

        XCTAssertEqual(presentation.kind, .unbound)
        XCTAssertEqual(presentation.title, NSLocalizedString("unbound", comment: ""))
    }

    func testPullDown_recordingPromptHasNoPicture() {
        let pullDown = makePullDown(binding: makeBinding(SystemShortcut.copy))
        XCTAssertNotNil(pullDown.menu?.items.first?.image)

        pullDown.beginCustomShortcutSelection(startRecorder: false)

        XCTAssertEqual(shownTitle(pullDown), NSLocalizedString("custom-recording-prompt", comment: ""))
        XCTAssertNil(pullDown.menu?.items.first?.image)
    }

    func testPullDown_isAPullDownAsWideAsTheGesturesPullDowns() {
        let pullDown = makePullDown(binding: makeBinding(SystemShortcut.mosScrollDash))
        XCTAssertTrue(pullDown.pullsDown)
        XCTAssertEqual(ButtonActionPullDown.width, GesturesPreferencesViewController.popUpWidth)
        XCTAssertEqual(shownTitle(pullDown), "Scroll Faster")
        // The symbol alone: no brand tag drawn in front of it.
        let image = pullDown.menu?.items.first?.image
        let symbol = NSImage(systemSymbolName: "speedometer", accessibilityDescription: nil)
        XCTAssertEqual(image?.size, symbol?.size)
    }

    func testPullDown_showsAKeyboardShortcutAsText() {
        let modifiers = UInt64(NSEvent.ModifierFlags.control.rawValue)
        let binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            systemShortcutName: "custom::40:\(modifiers)"
        )

        let pullDown = makePullDown(binding: binding)

        XCTAssertEqual(shownTitle(pullDown), "⌃K")
    }

    // MARK: - ActionPresentation openTarget

    func testActionDisplayResolver_returnsOpenTargetKindWhenPayloadProvided() {
        let payload = OpenTargetPayload(
            path: "/Applications/Safari.app",
            bundleID: "com.apple.Safari",
            arguments: "",
            kind: .application
        )
        let presentation = ActionDisplayResolver().resolve(
            shortcut: nil,
            customBindingName: nil,
            isRecording: false,
            openTarget: payload
        )
        XCTAssertEqual(presentation.kind, .openTarget)
        // Title should be either the file's basename or app displayName — both acceptable.
        XCTAssertFalse(presentation.title.isEmpty)
    }

    func testActionDisplayResolver_openTargetStalePathProducesUnavailableTitle() {
        let payload = OpenTargetPayload(
            path: "/totally-fake-path-do-not-exist.app",
            bundleID: "com.does.not.exist",
            arguments: "",
            kind: .application
        )
        let presentation = ActionDisplayResolver().resolve(
            shortcut: nil,
            customBindingName: nil,
            isRecording: false,
            openTarget: payload
        )
        XCTAssertEqual(presentation.kind, .openTarget)
        XCTAssertTrue(
            presentation.title.contains(NSLocalizedString("open-target-placeholder-stale", comment: ""))
                || presentation.title.contains("totally-fake-path-do-not-exist"),
            "Stale path should produce either filename + (unavailable) suffix or just '(unavailable)'; got: \(presentation.title)"
        )
    }

    func testPullDown_showsAnAppWithItsIcon() {
        let payload = OpenTargetPayload(
            path: "/System/Applications/Calculator.app",
            bundleID: "com.apple.calculator",
            arguments: "",
            kind: .application
        )
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let pullDown = makePullDown(binding: ButtonBinding(triggerEvent: trigger, openTarget: payload))

        XCTAssertFalse(shownTitle(pullDown)?.isEmpty ?? true)
        let image = try? XCTUnwrap(pullDown.menu?.items.first?.image)
        XCTAssertEqual(image?.size, NSSize(width: ButtonActionPullDown.imageSize, height: ButtonActionPullDown.imageSize))
    }

    func testBuildShortcutMenu_includesModifierCategoryWithSingleModifierShortcuts() {
        let menu = NSMenu()
        let target = ShortcutMenuTestTarget()

        ShortcutManager.buildShortcutMenu(
            into: menu,
            target: target,
            action: #selector(ShortcutMenuTestTarget.noop(_:))
        )

        let modifierCategoryName = SystemShortcut.localizedCategoryName(SystemShortcut.modifierKeysCategory.category)
        let mouseCategoryName = SystemShortcut.localizedCategoryName(SystemShortcut.mouseButtonsCategory.category)

        guard let modifierIndex = menu.items.firstIndex(where: { $0.title == modifierCategoryName }),
              let mouseIndex = menu.items.firstIndex(where: { $0.title == mouseCategoryName }) else {
            return XCTFail("Expected modifier and mouse categories to exist in shortcut menu")
        }

        XCTAssertLessThan(modifierIndex, mouseIndex)

        let modifierItems = menu.items[modifierIndex].submenu?.items.compactMap {
            ($0.representedObject as? SystemShortcut.Shortcut)?.identifier
        }
        XCTAssertEqual(
            modifierItems,
            ["modifierShift", "modifierOption", "modifierControl", "modifierCommand", "modifierFn"]
        )

        let mouseItems = menu.items[mouseIndex].submenu?.items.compactMap {
            ($0.representedObject as? SystemShortcut.Shortcut)?.identifier
        }
        XCTAssertEqual(
            mouseItems,
            ["mouseLeftClick", "mouseRightClick", "mouseMiddleClick", "mouseBackClick", "mouseForwardClick"]
        )
    }

    func testBuildShortcutMenu_placesMosMouseScrollBelowMouseButtons() {
        let menu = NSMenu()
        let target = ShortcutMenuTestTarget()

        ShortcutManager.buildShortcutMenu(
            into: menu,
            target: target,
            action: #selector(ShortcutMenuTestTarget.noop(_:)),
            showLogiActions: true
        )

        let mouseCategoryName = SystemShortcut.localizedCategoryName(SystemShortcut.mouseButtonsCategory.category)
        let mosCategoryName = SystemShortcut.localizedCategoryName(SystemShortcut.mosMouseScrollCategory.category)
        let logiCategoryName = SystemShortcut.localizedCategoryName(SystemShortcut.logiActionsCategory.category)

        guard let mouseIndex = menu.items.firstIndex(where: { $0.title == mouseCategoryName }),
              let mosIndex = menu.items.firstIndex(where: { $0.title == mosCategoryName }),
              let logiIndex = menu.items.firstIndex(where: { $0.title == logiCategoryName }) else {
            return XCTFail("Expected mouse, Mos scroll, and Logi categories to exist in shortcut menu")
        }

        XCTAssertLessThan(mouseIndex, mosIndex)
        XCTAssertLessThan(mosIndex, logiIndex)
        XCTAssertNotNil(menu.items[mosIndex].image)

        let mosItems = menu.items[mosIndex].submenu?.items.compactMap {
            ($0.representedObject as? SystemShortcut.Shortcut)?.identifier
        }
        XCTAssertEqual(mosItems, ["mosScrollDash", "mosScrollToggle", "mosScrollBlock"])
    }

    func testBuildShortcutMenu_includesOpenTargetEntryAboveCustom() {
        let menu = NSMenu()
        let target = ShortcutMenuTestTarget()

        ShortcutManager.buildShortcutMenu(
            into: menu,
            target: target,
            action: #selector(ShortcutMenuTestTarget.noop(_:))
        )

        guard let openIndex = menu.items.firstIndex(where: {
            ($0.representedObject as? String) == "__open__"
        }) else {
            return XCTFail("Expected '__open__' menu entry to exist")
        }
        guard let customIndex = menu.items.firstIndex(where: {
            ($0.representedObject as? String) == "__custom__"
        }) else {
            return XCTFail("Expected '__custom__' menu entry to exist")
        }
        XCTAssertLessThan(openIndex, customIndex, "Open Application should appear above Custom Shortcut")

        let openItem = menu.items[openIndex]
        XCTAssertEqual(openItem.title, NSLocalizedString("open-target-action", comment: ""))
    }

    func testBuildShortcutMenu_disablesMouseLeftClickAction() {
        let menu = NSMenu()
        let target = ShortcutMenuTestTarget()

        ShortcutManager.buildShortcutMenu(
            into: menu,
            target: target,
            action: #selector(ShortcutMenuTestTarget.noop(_:))
        )

        let mouseCategoryName = SystemShortcut.localizedCategoryName(SystemShortcut.mouseButtonsCategory.category)
        guard let mouseCategory = menu.items.first(where: { $0.title == mouseCategoryName }),
              let leftClickItem = mouseCategory.submenu?.items.first(where: {
                  ($0.representedObject as? SystemShortcut.Shortcut)?.identifier == "mouseLeftClick"
              }) else {
            return XCTFail("Expected mouse left click item in mouse buttons category")
        }

        XCTAssertFalse(leftClickItem.isEnabled)
    }

    func testBuildShortcutMenu_keepsManualDisabledStateDuringMenuPresentation() {
        let menu = NSMenu()
        let target = ShortcutMenuTestTarget()

        ShortcutManager.buildShortcutMenu(
            into: menu,
            target: target,
            action: #selector(ShortcutMenuTestTarget.noop(_:))
        )

        let mouseCategoryName = SystemShortcut.localizedCategoryName(SystemShortcut.mouseButtonsCategory.category)
        guard let mouseCategory = menu.items.first(where: { $0.title == mouseCategoryName }),
              let mouseSubmenu = mouseCategory.submenu,
              let leftClickItem = mouseSubmenu.items.first(where: {
                  ($0.representedObject as? SystemShortcut.Shortcut)?.identifier == "mouseLeftClick"
              }) else {
            return XCTFail("Expected mouse left click item in mouse buttons category")
        }

        XCTAssertFalse(menu.autoenablesItems)
        XCTAssertFalse(mouseSubmenu.autoenablesItems)
        mouseSubmenu.update()
        XCTAssertFalse(leftClickItem.isEnabled)
    }

    func testBuildShortcutMenu_usesShortCustomShortcutTitle() {
        let menu = NSMenu()
        let target = ShortcutMenuTestTarget()

        ShortcutManager.buildShortcutMenu(
            into: menu,
            target: target,
            action: #selector(ShortcutMenuTestTarget.noop(_:))
        )

        guard let customItem = menu.items.first(where: {
            ($0.representedObject as? String) == "__custom__"
        }) else {
            return XCTFail("Expected custom shortcut item")
        }

        XCTAssertEqual(customItem.title, "Keyboard Shortcut…")
    }

    func testShortcutSelected_openSentinel_invokesOpenSelectionCallback() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "")

        var openSelectionInvoked = false
        let pullDown = makePullDown(binding: binding, onOpenTargetSelectionRequested: {
            openSelectionInvoked = true
        })

        let openItem = NSMenuItem(title: "Open App or File…", action: nil, keyEquivalent: "")
        openItem.representedObject = ShortcutManager.MenuMarker.openTarget as NSString
        pullDown.shortcutSelected(openItem)

        XCTAssertTrue(openSelectionInvoked, "Open App or File… asks the pane for the app or file")
    }

    func testShortcutSelected_openSentinelRestoresCurrentActionDisplay() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "copy")
        let pullDown = makePullDown(binding: binding)
        pullDown.menu?.items.first?.title = NSLocalizedString("open-target-action", comment: "")

        let openItem = NSMenuItem(title: "Open App or File…", action: nil, keyEquivalent: "")
        openItem.representedObject = ShortcutManager.MenuMarker.openTarget as NSString
        pullDown.shortcutSelected(openItem)

        XCTAssertEqual(shownTitle(pullDown), SystemShortcut.copy.localizedName)
    }

    func testBuildShortcutMenu_functionKeysHoldEscapeButNotGestureNavigation() {
        let menu = NSMenu()
        let target = ShortcutMenuTestTarget()

        ShortcutManager.buildShortcutMenu(
            into: menu,
            target: target,
            action: #selector(ShortcutMenuTestTarget.noop(_:))
        )

        let functionCategoryName = SystemShortcut.localizedCategoryName("categoryFunctionKeys")
        guard let functionCategoryIndex = menu.items.firstIndex(where: { $0.title == functionCategoryName }) else {
            return XCTFail("Expected function keys category to exist in shortcut menu")
        }

        let functionItems = menu.items[functionCategoryIndex].submenu?.items.compactMap {
            ($0.representedObject as? SystemShortcut.Shortcut)?.identifier
        } ?? []

        XCTAssertTrue(functionItems.contains("escapeKey"))
        XCTAssertFalse(functionItems.contains("mouseGestureNavigation"))
    }

    func testBuildShortcutMenu_listsGestureNavigationAtTopLevelNextToOpen() throws {
        let menu = NSMenu()
        let target = ShortcutMenuTestTarget()

        ShortcutManager.buildShortcutMenu(
            into: menu,
            target: target,
            action: #selector(ShortcutMenuTestTarget.noop(_:)),
            showLogiActions: true
        )

        let gestureIdentifier = SystemShortcut.mouseGestureNavigation.identifier
        let gestureIndex = try XCTUnwrap(menu.items.firstIndex {
            ($0.representedObject as? SystemShortcut.Shortcut)?.identifier == gestureIdentifier
        })
        let openIndex = try XCTUnwrap(menu.items.firstIndex { ($0.representedObject as? String) == "__open__" })
        let customIndex = try XCTUnwrap(menu.items.firstIndex { ($0.representedObject as? String) == "__custom__" })

        // One group after the last separator: Gesture Navigation, Open…, Custom….
        XCTAssertTrue(menu.items[gestureIndex - 1].isSeparatorItem)
        XCTAssertEqual(openIndex, gestureIndex + 1)
        XCTAssertEqual(customIndex, gestureIndex + 2)
        XCTAssertEqual(customIndex, menu.items.count - 1)

        let gestureItem = menu.items[gestureIndex]
        XCTAssertEqual(gestureItem.title, SystemShortcut.mouseGestureNavigation.localizedName)
        XCTAssertNil(gestureItem.submenu)
        XCTAssertTrue(gestureItem.isEnabled)
        XCTAssertTrue(gestureItem.target === target)
        XCTAssertEqual(gestureItem.action, #selector(ShortcutMenuTestTarget.noop(_:)))
        XCTAssertEqual(gestureItem.keyEquivalent, "")

        // It is offered once: no category repeats it.
        let inSubmenus = menu.items.compactMap(\.submenu).flatMap(\.items).filter {
            ($0.representedObject as? SystemShortcut.Shortcut)?.identifier == gestureIdentifier
        }
        XCTAssertTrue(inSubmenus.isEmpty)
        XCTAssertFalse(SystemShortcut.shortcutsByCategory.flatMap(\.shortcuts).contains { $0.identifier == gestureIdentifier })
    }

    func testGestureNavigationKeepsItsIdentifierAndLookup() {
        XCTAssertEqual(SystemShortcut.mouseGestureNavigation.identifier, "mouseGestureNavigation")
        XCTAssertEqual(
            SystemShortcut.getShortcut(named: "mouseGestureNavigation")?.identifier,
            SystemShortcut.mouseGestureNavigation.identifier
        )
    }

    func testSelectingTheTopLevelGestureItem_bindsGestureNavigation() throws {
        var selected: [String?] = []
        let pullDown = makePullDown(binding: makeBinding(SystemShortcut.copy), onShortcutSelected: { selected.append($0?.identifier) })
        let menu = try XCTUnwrap(pullDown.menu)
        let item = try XCTUnwrap(menu.items.first {
            ($0.representedObject as? SystemShortcut.Shortcut)?.identifier == SystemShortcut.mouseGestureNavigation.identifier
        })

        pullDown.shortcutSelected(item)

        XCTAssertEqual(selected, [SystemShortcut.mouseGestureNavigation.identifier])
        XCTAssertEqual(menu.items.first?.title, SystemShortcut.mouseGestureNavigation.localizedName)
        XCTAssertEqual(pullDown.binding.systemShortcutName, SystemShortcut.mouseGestureNavigation.identifier)
    }

    func testPredefinedModifierShortcut_localizedNamesAreSemanticLabels() {
        let symbolFallbacks = [
            "modifierShift": "⇧",
            "modifierOption": "⌥",
            "modifierControl": "⌃",
            "modifierCommand": "⌘",
            "modifierFn": "Fn",
        ]

        for (identifier, symbolFallback) in symbolFallbacks {
            guard let shortcut = SystemShortcut.getShortcut(named: identifier) else {
                return XCTFail("Expected shortcut \(identifier) to exist")
            }
            XCTAssertFalse(shortcut.localizedName.isEmpty)
            XCTAssertNotEqual(shortcut.localizedName, symbolFallback)
        }
    }

    func testEscapeShortcut_localizedNameIsSemanticLabel() {
        guard let shortcut = SystemShortcut.getShortcut(named: "escapeKey") else {
            return XCTFail("Expected escape shortcut to exist")
        }

        XCTAssertEqual(shortcut.localizedName, NSLocalizedString("escapeKey", comment: ""))
        XCTAssertNotEqual(shortcut.localizedName, "escapeKey")
    }

    func testPullDown_showsNamedShortcutForEquivalentCustomBinding() {
        let modifiers = UInt64(NSEvent.ModifierFlags.command.union(.shift).rawValue)
        let binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            systemShortcutName: "custom::21:\(modifiers)"
        )

        let pullDown = makePullDown(binding: binding)

        XCTAssertEqual(pullDown.menu?.items.first?.title, SystemShortcut.screenshotSelection.localizedName)
    }

    func testPullDown_preservesDirectNamedShortcutForEquivalentConflictingCombo() {
        let binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            systemShortcutName: "getInfo"
        )

        let pullDown = makePullDown(binding: binding)

        XCTAssertEqual(pullDown.menu?.items.first?.title, SystemShortcut.getInfo.localizedName)
    }

    func testBeginCustomShortcutSelection_showsRecordingPromptWhileAwaitingRecording() {
        let binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            systemShortcutName: "",
            isEnabled: false
        )
        let pullDown = makePullDown(binding: binding)

        pullDown.beginCustomShortcutSelection(startRecorder: false)
        flushMainQueue()

        XCTAssertEqual(
            pullDown.menu?.items.first?.title,
            NSLocalizedString("custom-recording-prompt", comment: "")
        )
    }

    func testCustomRecordingDidStop_restoresUnboundDisplayWhenNoKeyRecorded() {
        let binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            systemShortcutName: "",
            isEnabled: false
        )
        let pullDown = makePullDown(binding: binding)

        pullDown.beginCustomShortcutSelection(startRecorder: false)
        flushMainQueue()
        pullDown.onRecordingStopped(KeyRecorder(), didRecord: false)
        flushMainQueue()

        XCTAssertEqual(pullDown.menu?.items.first?.title, NSLocalizedString("unbound", comment: ""))
    }

    func testCustomRecordingDidStop_restoresExistingDisplayWhenNoKeyRecorded() {
        let modifiers = UInt64(NSEvent.ModifierFlags.command.union(.shift).rawValue)
        let binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            systemShortcutName: "custom::21:\(modifiers)"
        )
        let pullDown = makePullDown(binding: binding)

        pullDown.beginCustomShortcutSelection(startRecorder: false)
        flushMainQueue()
        pullDown.onRecordingStopped(KeyRecorder(), didRecord: false)
        flushMainQueue()

        XCTAssertEqual(pullDown.menu?.items.first?.title, SystemShortcut.screenshotSelection.localizedName)
    }

    func testRecordedEquivalentCustomShortcut_updatesSelectedActionDisplayToNamedShortcut() {
        let binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            systemShortcutName: "",
            isEnabled: false
        )
        let pullDown = makePullDown(binding: binding)
        let event = InputEvent(
            type: .keyboard,
            code: 21,
            modifiers: [.maskCommand, .maskShift],
            phase: .down,
            source: .hidPP,
            device: nil
        )

        pullDown.onEventRecorded(KeyRecorder(), didRecordEvent: event, isDuplicate: false)
        advanceMainRunLoop(by: 0.75)

        XCTAssertEqual(pullDown.menu?.items.first?.title, SystemShortcut.screenshotSelection.localizedName)
    }

    func testRecordedEquivalentCustomShortcut_withIrrelevantFlagsStillDisplaysNamedShortcut() {
        let binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            systemShortcutName: "",
            isEnabled: false
        )
        let pullDown = makePullDown(binding: binding)
        let event = InputEvent(
            type: .keyboard,
            code: 21,
            modifiers: CGEventFlags(rawValue: UInt64(NSEvent.ModifierFlags.command.union(.shift).rawValue) | (1 << 24)),
            phase: .down,
            source: .hidPP,
            device: nil
        )

        pullDown.onEventRecorded(KeyRecorder(), didRecordEvent: event, isDuplicate: false)
        advanceMainRunLoop(by: 0.75)

        XCTAssertEqual(pullDown.menu?.items.first?.title, SystemShortcut.screenshotSelection.localizedName)
    }

    func testRecordedMouseCustomShortcut_updatesSelectedActionDisplayToNamedMouseAction() {
        let binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 5, modifiers: 0, displayComponents: ["🖱5"], deviceFilter: nil),
            systemShortcutName: "",
            isEnabled: false
        )
        let pullDown = makePullDown(binding: binding)
        let event = InputEvent(
            type: .mouse,
            code: 3,
            modifiers: [],
            phase: .down,
            source: .hidPP,
            device: nil
        )

        pullDown.onEventRecorded(KeyRecorder(), didRecordEvent: event, isDuplicate: false)
        advanceMainRunLoop(by: 0.75)

        XCTAssertEqual(pullDown.menu?.items.first?.title, SystemShortcut.mouseBackClick.localizedName)
    }

    func testPrimaryMouseButtonsRecordabilityInAdaptiveMode() {
        let leftClick = InputEvent(
            type: .mouse,
            code: 0,
            modifiers: [],
            phase: .down,
            source: .hidPP,
            device: nil
        )
        let rightClick = InputEvent(
            type: .mouse,
            code: 1,
            modifiers: [],
            phase: .down,
            source: .hidPP,
            device: nil
        )

        XCTAssertFalse(leftClick.isRecordableAsAdaptive)
        XCTAssertFalse(leftClick.isRecordableAsSingleKey)
        XCTAssertFalse(leftClick.isRecordable)

        XCTAssertTrue(rightClick.isRecordableAsAdaptive)
        XCTAssertFalse(rightClick.isRecordableAsSingleKey)
        XCTAssertFalse(rightClick.isRecordable)
    }

    func testKeyPopoverDuplicateHintUsesDedicatedTextAndEscHintStyle() {
        let popover = KeyPopover()
        popover.testingPrepareContent()

        popover.showDuplicateHint()

        XCTAssertEqual(
            popover.testingHintText,
            NSLocalizedString("button-recording-duplicate-hint", comment: "")
        )
        XCTAssertEqual(popover.testingHintFontPointSize, 10)
        XCTAssertEqual(popover.testingHintAlignment, NSTextAlignment.center)
        XCTAssertEqual(popover.testingHintBottomPadding, 5)

        popover.hide()
    }

    func testKeyRecorderDuplicateFeedbackDelayIsLongerThanRecordedFeedback() {
        XCTAssertEqual(KeyRecorder.recordingFeedbackDelay(isDuplicate: false), 0.7)
        XCTAssertEqual(KeyRecorder.recordingFeedbackDelay(isDuplicate: true), 1.0)
    }

    func testCustomRecordingValidationRejectsRecordingTriggerItself() {
        let binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱3"], deviceFilter: nil),
            systemShortcutName: "",
            isEnabled: false
        )
        let pullDown = makePullDown(binding: binding)
        let event = InputEvent(
            type: .mouse,
            code: 3,
            modifiers: [],
            phase: .down,
            source: .hidPP,
            device: nil
        )

        XCTAssertFalse(pullDown.validateRecordedEvent(KeyRecorder(), event: event))
    }

    func testDuplicateCustomRecordingRestoresPreviousActionDisplay() {
        let binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱3"], deviceFilter: nil),
            systemShortcutName: "",
            isEnabled: false
        )
        let pullDown = makePullDown(binding: binding)
        let event = InputEvent(
            type: .mouse,
            code: 3,
            modifiers: [],
            phase: .down,
            source: .hidPP,
            device: nil
        )

        pullDown.beginCustomShortcutSelection(startRecorder: false)
        flushMainQueue()
        pullDown.onEventRecorded(KeyRecorder(), didRecordEvent: event, isDuplicate: true)
        pullDown.onRecordingStopped(KeyRecorder(), didRecord: true)
        advanceMainRunLoop(by: KeyRecorder.recordingFeedbackDelay(isDuplicate: true) + 0.05)

        XCTAssertEqual(pullDown.menu?.items.first?.title, NSLocalizedString("unbound", comment: ""))
    }

    func testDuplicateCustomRecordingKeepsPromptUntilDuplicateFeedbackEnds() {
        let binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱3"], deviceFilter: nil),
            systemShortcutName: "",
            isEnabled: false
        )
        let pullDown = makePullDown(binding: binding)
        let event = InputEvent(
            type: .mouse,
            code: 3,
            modifiers: [],
            phase: .down,
            source: .hidPP,
            device: nil
        )

        pullDown.beginCustomShortcutSelection(startRecorder: false)
        flushMainQueue()
        pullDown.onEventRecorded(KeyRecorder(), didRecordEvent: event, isDuplicate: true)

        advanceMainRunLoop(by: KeyRecorder.recordingFeedbackDelay(isDuplicate: false) + 0.05)
        XCTAssertEqual(pullDown.menu?.items.first?.title, NSLocalizedString("custom-recording-prompt", comment: ""))

        advanceMainRunLoop(by: KeyRecorder.recordingFeedbackDelay(isDuplicate: true))
        XCTAssertEqual(pullDown.menu?.items.first?.title, NSLocalizedString("unbound", comment: ""))
    }

    // MARK: - OpenTarget extension

    func testOpenTargetSentinel_isStableConstant() {
        XCTAssertEqual(ButtonBinding.openTargetSentinel, "openTarget")
    }

    func testInit_withOpenTargetPayload_setsSentinelName() {
        let payload = OpenTargetPayload(
            path: "/Applications/Safari.app",
            bundleID: "com.apple.Safari",
            arguments: "",
            kind: .application
        )
        let binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            openTarget: payload
        )
        XCTAssertEqual(binding.systemShortcutName, "openTarget")
        XCTAssertEqual(binding.openTarget, payload)
    }

    func testCodableRoundtrip_preservesOpenTarget() {
        let payload = OpenTargetPayload(
            path: "/Applications/Safari.app",
            bundleID: "com.apple.Safari",
            arguments: "https://example.com",
            kind: .application
        )
        let original = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            openTarget: payload
        )
        let data = try! JSONEncoder().encode(original)
        let decoded = try! JSONDecoder().decode(ButtonBinding.self, from: data)
        XCTAssertEqual(decoded.systemShortcutName, "openTarget")
        XCTAssertEqual(decoded.openTarget, payload)
    }

    func testCodableRoundtrip_legacyBindingHasNilOpenTarget() {
        // Old JSON format: no openTarget field
        let legacyJSON = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "triggerEvent": {
                "type": "mouse",
                "code": 3,
                "modifiers": 0,
                "displayComponents": ["🖱4"],
                "deviceFilter": null
            },
            "systemShortcutName": "copy",
            "isEnabled": true,
            "createdAt": "2025-01-01T00:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = legacyJSON.data(using: .utf8)!
        let decoded = try! decoder.decode(ButtonBinding.self, from: data)
        XCTAssertEqual(decoded.systemShortcutName, "copy")
        XCTAssertNil(decoded.openTarget)
    }

    func testEquatable_distinguishesByOpenTarget() {
        let payloadA = OpenTargetPayload(path: "/a.app", bundleID: nil, arguments: "", kind: .application)
        let payloadB = OpenTargetPayload(path: "/b.app", bundleID: nil, arguments: "", kind: .application)
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let id = UUID()
        let createdAt = Date(timeIntervalSince1970: 0)

        let a = ButtonBinding(id: id, triggerEvent: trigger, openTarget: payloadA, isEnabled: true, createdAt: createdAt)
        let b = ButtonBinding(id: id, triggerEvent: trigger, openTarget: payloadA, isEnabled: true, createdAt: createdAt)
        let c = ButtonBinding(id: id, triggerEvent: trigger, openTarget: payloadB, isEnabled: true, createdAt: createdAt)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - Sentinel/payload consistency (decode 拒绝 mismatch)

    func testCodable_sentinelWithoutPayload_throws() {
        // {"systemShortcutName":"openTarget", 缺 openTarget} → 不一致, 应该 throw
        let json = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "triggerEvent": {"type":"mouse","code":3,"modifiers":0,"displayComponents":["🖱4"],"deviceFilter":null},
            "systemShortcutName": "openTarget",
            "isEnabled": true,
            "createdAt": "2025-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertThrowsError(try decoder.decode(ButtonBinding.self, from: json)) { error in
            guard case DecodingError.dataCorrupted = error else {
                XCTFail("Expected DecodingError.dataCorrupted, got \(error)")
                return
            }
        }
    }

    func testCodable_payloadWithNonSentinelName_throws() {
        // {"systemShortcutName":"copy", "openTarget":{...}} → 不一致, 应该 throw
        let json = """
        {
            "id": "22222222-2222-2222-2222-222222222222",
            "triggerEvent": {"type":"mouse","code":3,"modifiers":0,"displayComponents":["🖱4"],"deviceFilter":null},
            "systemShortcutName": "copy",
            "isEnabled": true,
            "createdAt": "2025-01-01T00:00:00Z",
            "openTarget": {
                "path": "/Applications/Safari.app",
                "bundleID": "com.apple.Safari",
                "arguments": "",
                "kind": "application"
            }
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertThrowsError(try decoder.decode(ButtonBinding.self, from: json)) { error in
            guard case DecodingError.dataCorrupted = error else {
                XCTFail("Expected DecodingError.dataCorrupted, got \(error)")
                return
            }
        }
    }

    func testCodable_sentinelWithPayload_decodesOK() {
        // 一致状态: 应正常 decode
        let json = """
        {
            "id": "33333333-3333-3333-3333-333333333333",
            "triggerEvent": {"type":"mouse","code":3,"modifiers":0,"displayComponents":["🖱4"],"deviceFilter":null},
            "systemShortcutName": "openTarget",
            "isEnabled": true,
            "createdAt": "2025-01-01T00:00:00Z",
            "openTarget": {
                "path": "/Applications/Safari.app",
                "bundleID": "com.apple.Safari",
                "arguments": "https://example.com",
                "kind": "application"
            }
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let binding = try! decoder.decode(ButtonBinding.self, from: json)
        XCTAssertEqual(binding.systemShortcutName, "openTarget")
        XCTAssertNotNil(binding.openTarget)
        XCTAssertEqual(binding.openTarget?.kind, .application)
    }

    func testCodable_nonSentinelWithoutPayload_decodesOK() {
        // 一致状态: 普通 system shortcut, 无 openTarget. 应正常 decode.
        let json = """
        {
            "id": "44444444-4444-4444-4444-444444444444",
            "triggerEvent": {"type":"mouse","code":3,"modifiers":0,"displayComponents":["🖱4"],"deviceFilter":null},
            "systemShortcutName": "copy",
            "isEnabled": true,
            "createdAt": "2025-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let binding = try! decoder.decode(ButtonBinding.self, from: json)
        XCTAssertEqual(binding.systemShortcutName, "copy")
        XCTAssertNil(binding.openTarget)
    }
}
