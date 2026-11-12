import Carbon.HIToolbox
import UniformTypeIdentifiers
import XCTest
@testable import Scrollio_Debug

final class ShortcutExecutorOpenTargetTests: XCTestCase {

    private func makeOpenTargetBinding(payload: OpenTargetPayload) -> ButtonBinding {
        return ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            openTarget: payload
        )
    }

    func testResolveAction_openTargetSentinel_returnsOpenTargetCase() {
        let payload = OpenTargetPayload(path: "/Applications/Safari.app", bundleID: "com.apple.Safari", arguments: "", kind: .application)
        let binding = makeOpenTargetBinding(payload: payload)
        let executor = ShortcutExecutor()

        let resolved = executor.resolveAction(named: "openTarget", binding: binding)
        guard case .openTarget(let resolvedPayload) = resolved else {
            return XCTFail("Expected .openTarget case, got \(String(describing: resolved))")
        }
        XCTAssertEqual(resolvedPayload, payload)
    }

    func testResolveAction_openTargetSentinelButNoPayload_returnsNil() {
        // Edge case: sentinel set but openTarget field missing — corruption guard
        let binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            systemShortcutName: "openTarget"
        )
        let executor = ShortcutExecutor()

        let resolved = executor.resolveAction(named: "openTarget", binding: binding)
        if case .systemShortcut = resolved {
            // Falls through to systemShortcut case (returns the identifier as-is, lookup will fail later)
        } else if resolved == nil {
            // Or returns nil — either is acceptable defensive behavior
        } else {
            XCTFail("Expected .systemShortcut or nil for missing payload, got \(String(describing: resolved))")
        }
    }

    func testResolveAction_existingCustomKeyPath_unaffected() {
        var binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            systemShortcutName: "custom::40:1048576"
        )
        binding.prepareCustomCache()
        let executor = ShortcutExecutor()

        let resolved = executor.resolveAction(named: "custom::40:1048576", binding: binding)
        guard case .customKey(let code, let modifiers) = resolved else {
            return XCTFail("Expected .customKey case, got \(String(describing: resolved))")
        }
        XCTAssertEqual(code, 40)
        XCTAssertEqual(modifiers, 1048576)
    }

    func testResolveAction_typedMouseBackCustomBinding_usesNamedMouseButtonPath() {
        var binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 5, modifiers: 0, displayComponents: ["🖱5"], deviceFilter: nil),
            systemShortcutName: "custom::mouse:3:0"
        )
        binding.prepareCustomCache()
        let executor = ShortcutExecutor()

        let resolved = executor.resolveAction(named: "custom::mouse:3:0", binding: binding)
        guard case .mouseButton(let kind) = resolved else {
            return XCTFail("Expected .mouseButton case, got \(String(describing: resolved))")
        }
        XCTAssertEqual(kind, .back)
    }

    func testResolveAction_typedMouseCustomBinding_usesCustomMouseButtonPath() {
        var binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 6, modifiers: 0, displayComponents: ["🖱6"], deviceFilter: nil),
            systemShortcutName: "custom::mouse:5:0"
        )
        binding.prepareCustomCache()
        let executor = ShortcutExecutor()

        let resolved = executor.resolveAction(named: "custom::mouse:5:0", binding: binding)
        guard case .customMouseButton(let buttonNumber, let modifiers) = resolved else {
            return XCTFail("Expected .customMouseButton case, got \(String(describing: resolved))")
        }
        XCTAssertEqual(buttonNumber, 5)
        XCTAssertEqual(modifiers, 0)
    }

    func testResolveAction_existingMouseButtonPath_unaffected() {
        let executor = ShortcutExecutor()
        let resolved = executor.resolveAction(named: "mouseLeftClick", binding: nil)
        guard case .mouseButton(let kind) = resolved else {
            return XCTFail("Expected .mouseButton case, got \(String(describing: resolved))")
        }
        XCTAssertEqual(kind, .left)
    }

    func testExecutionMode_openTarget_isTrigger() {
        let payload = OpenTargetPayload(path: "/x.app", bundleID: nil, arguments: "", kind: .application)
        let action: ResolvedAction = .openTarget(payload: payload)
        XCTAssertEqual(action.executionMode, .trigger)
    }

    func testExecutionMode_existingCases_unchanged() {
        XCTAssertEqual(ResolvedAction.customKey(code: 0, modifiers: 0).executionMode, .stateful)
        XCTAssertEqual(ResolvedAction.customMouseButton(buttonNumber: 5, modifiers: 0).executionMode, .stateful)
        XCTAssertEqual(ResolvedAction.mouseButton(kind: .left).executionMode, .stateful)
        XCTAssertEqual(ResolvedAction.logiAction(identifier: "logiSmartShiftToggle").executionMode, .trigger)
    }

    // MARK: - Subprocess env sanitization

    func testFilterEnvironment_stripsAllPollutionKeys() {
        // 用控制输入直接验证 filter 对每一类污染前缀都识别. 之前的测试只验证当前
        // 真实 env (CI 环境干净时跑不出有效信号), 不能算证明 strip-list 工作.
        let polluted: [String: String] = [
            "DYLD_INSERT_LIBRARIES": "/Xcode/.../libViewDebuggerSupport.dylib",
            "DYLD_FRAMEWORK_PATH": "/some/path",
            "DYLD_LIBRARY_PATH": "/some/path",
            "__XPC_DYLD_LIBRARY_PATH": "/some/path",
            "__XPC_DYLD_FRAMEWORK_PATH": "/some/path",
            "__XPC_LLVM_PROFILE_FILE": "/dev/null",
            "OS_ACTIVITY_DT_MODE": "YES",
            "MallocStackLogging": "1",
            "MallocStackLoggingNoCompact": "1",
            "NSZombieEnabled": "YES",
            "NSDeallocateZombies": "NO",
            "SWIFTUI_VIEW_DEBUG": "287",
            "ASAN_OPTIONS": "detect_leaks=1",
            "TSAN_OPTIONS": "halt_on_error=1",
            "LSAN_OPTIONS": "x",
            "UBSAN_OPTIONS": "x",
            // 常规 env: 必须保留
            "PATH": "/usr/bin:/bin",
            "HOME": "/Users/test",
            "USER": "test",
            "LANG": "en_US.UTF-8",
        ]

        let filtered = ShortcutExecutor.filterEnvironment(polluted)

        // 污染 keys 必须全部消失
        XCTAssertNil(filtered["DYLD_INSERT_LIBRARIES"])
        XCTAssertNil(filtered["DYLD_FRAMEWORK_PATH"])
        XCTAssertNil(filtered["DYLD_LIBRARY_PATH"])
        XCTAssertNil(filtered["__XPC_DYLD_LIBRARY_PATH"])
        XCTAssertNil(filtered["__XPC_DYLD_FRAMEWORK_PATH"])
        XCTAssertNil(filtered["__XPC_LLVM_PROFILE_FILE"])
        XCTAssertNil(filtered["OS_ACTIVITY_DT_MODE"])
        XCTAssertNil(filtered["MallocStackLogging"])
        XCTAssertNil(filtered["MallocStackLoggingNoCompact"])
        XCTAssertNil(filtered["NSZombieEnabled"])
        XCTAssertNil(filtered["NSDeallocateZombies"])
        XCTAssertNil(filtered["SWIFTUI_VIEW_DEBUG"])
        XCTAssertNil(filtered["ASAN_OPTIONS"])
        XCTAssertNil(filtered["TSAN_OPTIONS"])
        XCTAssertNil(filtered["LSAN_OPTIONS"])
        XCTAssertNil(filtered["UBSAN_OPTIONS"])

        // 常规 keys 必须保留
        XCTAssertEqual(filtered["PATH"], "/usr/bin:/bin")
        XCTAssertEqual(filtered["HOME"], "/Users/test")
        XCTAssertEqual(filtered["USER"], "test")
        XCTAssertEqual(filtered["LANG"], "en_US.UTF-8")
    }

    func testFilterEnvironment_emptyInput_returnsEmpty() {
        XCTAssertEqual(ShortcutExecutor.filterEnvironment([:]).count, 0)
    }
}

// MARK: - The keyboard layout in use

/// A layout whose keys type something else with Command held (the seam's second map).
final class FakeCommandLayout: KeyboardLayoutSource {
    var id: String?
    var plain: [CGKeyCode: String]
    var command: [CGKeyCode: String]
    /// How often the layout's keys were translated (both maps count as one).
    private(set) var translations = 0

    init(id: String?, plain: [CGKeyCode: String], command: [CGKeyCode: String]? = nil) {
        self.id = id
        self.plain = plain
        self.command = command ?? plain
    }

    func currentLayoutID() -> String? { return id }
    func currentCharacters() -> [CGKeyCode: String] {
        translations += 1
        return plain
    }
    func currentCommandCharacters() -> [CGKeyCode: String] { return command }

    /// The letters and a few symbols of the US layout, by key code.
    static let usKeys: [CGKeyCode: String] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v", 11: "b", 12: "q", 13: "w",
        14: "e", 15: "r", 16: "y", 17: "t", 31: "o", 32: "u", 34: "i", 35: "p", 37: "l", 38: "j", 40: "k",
        45: "n", 46: "m", 18: "1", 19: "2", 20: "3", 21: "4", 41: ";", 43: ",", 24: "=", 27: "-", 50: "`",
        // The keypad types digits and signs on every layout.
        82: "0", 83: "1", 69: "+", 78: "-",
    ]

    private static func swapping(_ changes: [CGKeyCode: String]) -> [CGKeyCode: String] {
        return usKeys.merging(changes) { $1 }
    }

    static var us: FakeCommandLayout {
        return FakeCommandLayout(id: "com.apple.keylayout.US", plain: usKeys)
    }
    /// AZERTY: A and Q, Z and W change places, M is where US has ";", the digits need Shift.
    static var french: FakeCommandLayout {
        return FakeCommandLayout(id: "com.apple.keylayout.French", plain: swapping([
            0: "q", 12: "a", 6: "w", 13: "z", 41: "m", 46: ",", 43: ";", 18: "&", 19: "é", 20: "\"", 21: "'",
        ]))
    }
    /// QWERTZ: Z and Y change places.
    static var german: FakeCommandLayout {
        return FakeCommandLayout(id: "com.apple.keylayout.German", plain: swapping([6: "y", 16: "z", 27: "ß", 24: "´"]))
    }
    /// "Dvorak - QWERTY ⌘": Dvorak to type, QWERTY while Command is held.
    static var dvorakQwertyCommand: FakeCommandLayout {
        return FakeCommandLayout(
            id: "com.apple.keylayout.DVORAK-QWERTYCMD",
            plain: swapping([0: "a", 1: "o", 2: "e", 3: "u", 8: "j", 9: "k", 7: "q", 6: ";", 12: "'", 13: ",", 34: "c", 11: "x"]),
            command: usKeys
        )
    }
    /// Cyrillic to type, Latin (QWERTY) while Command is held.
    static var russian: FakeCommandLayout {
        return FakeCommandLayout(
            id: "com.apple.keylayout.Russian",
            plain: [0: "ф", 6: "я", 8: "с", 9: "м", 12: "й", 13: "ц", 24: "=", 27: "-"],
            command: usKeys
        )
    }
}

/// The listed letter shortcuts are sent with the key that types their letter on the layout
/// in use, the keys are named by that layout, and a recorded shortcut is compared with the
/// layout's key. They were all the US layout's: on a French keyboard "Select All" pressed ⌘Q
/// and quit the app in front.
final class KeyboardLayoutKeysTests: XCTestCase {

    private let command = UInt64(NSEvent.ModifierFlags.command.rawValue)

    override func tearDown() {
        KeyboardLayoutKeys.shared.setTestingLayout(nil)
        ShortcutExecutor.shared.clearTestingKeyboardShortcutObserver()
        super.tearDown()
    }

    private func keys(_ layout: FakeCommandLayout?) -> KeyboardLayoutKeys {
        return KeyboardLayoutKeys(layout: layout)
    }

    private func code(of shortcut: SystemShortcut.Shortcut, on layout: FakeCommandLayout?) -> CGKeyCode {
        return keys(layout).keyCode(for: shortcut)
    }

    // MARK: Which key a listed shortcut is sent with

    func testOnTheUSLayoutEveryShortcutKeepsItsKey() {
        for shortcut in SystemShortcut.allShortcuts.values {
            XCTAssertEqual(code(of: shortcut, on: .us), shortcut.code, shortcut.identifier)
            XCTAssertEqual(code(of: shortcut, on: nil), shortcut.code, "no layout: \(shortcut.identifier)")
        }
    }

    func testOnAZERTYTheLetterShortcutsUseTheKeysThatTypeTheirLetters() {
        let french = FakeCommandLayout.french
        // The destructive ones of the report: these pressed ⌘Q, ⌘W, ⌘Z, ⌘A and ⌘, before.
        XCTAssertEqual(code(of: SystemShortcut.selectAll, on: french), 12, "A is where US has Q")
        XCTAssertEqual(code(of: SystemShortcut.undo, on: french), 13, "Z is where US has W")
        XCTAssertEqual(code(of: SystemShortcut.redo, on: french), 13)
        XCTAssertEqual(code(of: SystemShortcut.closeWindow, on: french), 6, "W is where US has Z")
        XCTAssertEqual(code(of: SystemShortcut.closeAllWindows, on: french), 6)
        XCTAssertEqual(code(of: SystemShortcut.quitApp, on: french), 0, "Q is where US has A")
        XCTAssertEqual(code(of: SystemShortcut.lockScreen, on: french), 0)
        XCTAssertEqual(code(of: SystemShortcut.logout, on: french), 0)
        XCTAssertEqual(code(of: SystemShortcut.minimizeWindow, on: french), 41, "M is where US has ;")
        // Letters that do not move.
        XCTAssertEqual(code(of: SystemShortcut.copy, on: french), 8)
        XCTAssertEqual(code(of: SystemShortcut.paste, on: french), 9)
        XCTAssertEqual(code(of: SystemShortcut.find, on: french), 3)
    }

    func testOnQWERTZUndoAndRedoUseTheZKey() {
        XCTAssertEqual(code(of: SystemShortcut.undo, on: .german), 16)
        XCTAssertEqual(code(of: SystemShortcut.redo, on: .german), 16)
        XCTAssertEqual(code(of: SystemShortcut.selectAll, on: .german), 0)
    }

    /// Keys that are the same keys on every layout are never looked up: arrows, Tab, Space,
    /// Esc, Delete, the digit keys (AZERTY types "&" there, and ⌘1 is still that key), the
    /// Apple keys.
    func testShortcutsWithoutALetterKeepTheirKeyOnEveryLayout() {
        let unchanged: [SystemShortcut.Shortcut] = [
            SystemShortcut.navigateBack, SystemShortcut.navigateForward, SystemShortcut.nextTab, SystemShortcut.previousTab,
            SystemShortcut.switchApp, SystemShortcut.spotlight, SystemShortcut.forceQuit, SystemShortcut.moveToTrash,
            SystemShortcut.viewAsIcons, SystemShortcut.viewAsGallery, SystemShortcut.screenshot,
            SystemShortcut.missionControl, SystemShortcut.moveSpaceLeft, SystemShortcut.escapeKey, SystemShortcut.nextWindow,
        ]
        for layout in [FakeCommandLayout.french, .german, .dvorakQwertyCommand, .russian] {
            for shortcut in unchanged {
                XCTAssertNil(shortcut.letter, shortcut.identifier)
                XCTAssertEqual(code(of: shortcut, on: layout), shortcut.code, "\(shortcut.identifier) on \(layout.id ?? "")")
            }
        }
        // The actions that are no keys are not keys on any layout.
        for shortcut in [SystemShortcut.mouseLeftClick, SystemShortcut.scrollDash, SystemShortcut.modifierShift,
                         SystemShortcut.logiHost1, SystemShortcut.mouseGestureNavigation] {
            XCTAssertNil(shortcut.letter, shortcut.identifier)
        }
    }

    /// Layouts that change under Command are asked with Command held: that is what an app
    /// compares the shortcut with.
    func testALayoutThatChangesUnderCommandIsAskedWithCommandHeld() {
        let dvorak = FakeCommandLayout.dvorakQwertyCommand
        XCTAssertEqual(code(of: SystemShortcut.copy, on: dvorak), 8, "QWERTY while ⌘ is held, although C types \"j\" there")
        XCTAssertEqual(code(of: SystemShortcut.cut, on: dvorak), 7, "not ⌘Q")
        XCTAssertEqual(code(of: SystemShortcut.selectAll, on: .russian), 0, "Latin under ⌘")
        XCTAssertEqual(code(of: SystemShortcut.undo, on: .russian), 6)
        // Without Command in the shortcut the plain keys are asked.
        XCTAssertEqual(keys(dvorak).keyCode(typing: "c", withCommand: false, usKeyCode: 8), 34)
        XCTAssertEqual(keys(dvorak).keyCode(typing: "c", withCommand: true, usKeyCode: 8), 8)
    }

    func testALetterTheLayoutDoesNotTypeFallsBackToTheUSKey() {
        // A layout with only a few letters (some Sami layouts type no Q, W, X or Y).
        let sparse = FakeCommandLayout(id: "sparse", plain: [0: "a", 8: "c"])
        XCTAssertEqual(code(of: SystemShortcut.quitApp, on: sparse), 12)
        XCTAssertEqual(code(of: SystemShortcut.cut, on: sparse), 7)
        XCTAssertEqual(code(of: SystemShortcut.copy, on: sparse), 8)
        XCTAssertEqual(code(of: SystemShortcut.selectAll, on: FakeCommandLayout(id: "empty", plain: [:])), 0)
        XCTAssertEqual(code(of: SystemShortcut.selectAll, on: FakeCommandLayout(id: nil, plain: FakeCommandLayout.french.plain)), 0,
                       "no layout in use")
    }

    func testALetterOnTwoKeysPrefersTheUSKeyAndTheKeypadIsLeftOut() {
        XCTAssertEqual(KeyboardLayoutKeys.letterKeys(typing: [7: "x", 24: "x", 13: "w", 50: "w"]), ["x": 7, "w": 13])
        XCTAssertEqual(KeyboardLayoutKeys.letterKeys(typing: [30: "w", 50: "w"]), ["w": 30], "neither is the US key: the lower")
        XCTAssertEqual(KeyboardLayoutKeys.letterKeys(typing: [82: "a", 12: "A"]), ["a": 12], "a keypad key never; upper case counts")
        XCTAssertEqual(KeyboardLayoutKeys.letterKeys(typing: [0: "ф", 1: "ß", 2: "1", 3: ""]), [:])
    }

    func testTheKeysAreTranslatedOncePerLayoutAndAChangeIsNoticed() {
        let layout = FakeCommandLayout.us
        let keys = KeyboardLayoutKeys(layout: layout)
        for _ in 0..<5 {
            XCTAssertEqual(keys.keyCode(for: SystemShortcut.selectAll), 0)
            XCTAssertEqual(keys.label(of: 0, withCommand: false), "A")
        }
        XCTAssertEqual(layout.translations, 1)

        layout.id = FakeCommandLayout.french.id
        layout.plain = FakeCommandLayout.french.plain
        layout.command = FakeCommandLayout.french.command
        XCTAssertEqual(keys.keyCode(for: SystemShortcut.selectAll), 12)
        XCTAssertEqual(keys.keyCode(for: SystemShortcut.quitApp), 0)
        XCTAssertEqual(layout.translations, 2)

        // warmUp reads the layout before the first shortcut does.
        let cold = FakeCommandLayout.german
        let warmed = KeyboardLayoutKeys(layout: cold)
        warmed.warmUp()
        XCTAssertEqual(cold.translations, 1)
        XCTAssertEqual(warmed.keyCode(for: SystemShortcut.undo), 16)
        XCTAssertEqual(cold.translations, 1)
    }

    // MARK: What the executor posts

    func testTheExecutorPostsTheLayoutsKey() {
        var posted: [(CGKeyCode, UInt64)] = []
        ShortcutExecutor.shared.setTestingKeyboardShortcutObserver { code, flags, _ in posted.append((code, flags)) }

        // Under XCTest there is no layout: the US keys, whatever keyboard the Mac has.
        ShortcutExecutor.shared.execute(named: "selectAll")
        XCTAssertEqual(posted.last?.0, 0)

        KeyboardLayoutKeys.shared.setTestingLayout(FakeCommandLayout.french)
        ShortcutExecutor.shared.execute(named: "selectAll")
        XCTAssertEqual(posted.last?.0, 12, "the key that types A on AZERTY; key 0 is Q there: it quit the app in front")
        XCTAssertEqual(posted.last?.1, command)
        ShortcutExecutor.shared.execute(named: "undo")
        XCTAssertEqual(posted.last?.0, 13, "key 6 is W on AZERTY: it closed the window")
        ShortcutExecutor.shared.execute(named: "quitApp")
        XCTAssertEqual(posted.last?.0, 0)
        ShortcutExecutor.shared.execute(SystemShortcut.redo)
        XCTAssertEqual(posted.last?.0, 13)
        XCTAssertEqual(posted.last?.1, UInt64(NSEvent.ModifierFlags([.command, .shift]).rawValue))
        // A key that does not depend on the layout, and a recorded key: as they are.
        ShortcutExecutor.shared.execute(named: "navigateBack")
        XCTAssertEqual(posted.last?.0, 123)
        ShortcutExecutor.shared.execute(code: 0, flags: command)
        XCTAssertEqual(posted.last?.0, 0, "a raw key code is never looked up")

        KeyboardLayoutKeys.shared.setTestingLayout(FakeCommandLayout.german)
        ShortcutExecutor.shared.execute(named: "undo")
        XCTAssertEqual(posted.last?.0, 16)
    }

    // MARK: Key names

    func testKeysAreNamedByTheLayoutInUse() {
        // No layout (and under XCTest): the US names, as before.
        XCTAssertEqual(KeyCode.name(of: 0), "A")
        XCTAssertEqual(KeyCode.name(of: 6), "Z")

        KeyboardLayoutKeys.shared.setTestingLayout(FakeCommandLayout.french)
        XCTAssertEqual(KeyCode.name(of: 0), "Q", "the key that read \"A\" on a French keyboard")
        XCTAssertEqual(KeyCode.name(of: 12), "A")
        XCTAssertEqual(KeyCode.name(of: 18), "&", "what the key types without Shift, as macOS shows it")
        // Keys that are the same on every layout keep their names.
        XCTAssertEqual(KeyCode.name(of: 49), "⎵")
        XCTAssertEqual(KeyCode.name(of: 53), "⎋")
        XCTAssertEqual(KeyCode.name(of: 122), "F1")
        XCTAssertEqual(KeyCode.name(of: 123), "←")
        XCTAssertEqual(KeyCode.name(of: 55), "⌘")
        XCTAssertNil(KeyCode.name(of: 200), "a key without a name on any layout")
        // The recorder's and the rows' texts follow.
        let trigger = RecordedEvent(type: .keyboard, code: 12, modifiers: UInt(CGEventFlags.maskCommand.rawValue), deviceFilter: nil)
        XCTAssertEqual(trigger.displayComponents, ["⌘", "A"])
        XCTAssertEqual(ButtonTriggerNaming.title(for: trigger), "⌘ A")
        XCTAssertEqual(ButtonTriggerNaming.shortcutText(type: .keyboard, code: 0, modifiers: CGEventFlags.maskCommand.rawValue), "⌘Q")
        XCTAssertEqual(ScrollHotkey(type: .keyboard, code: 0).displayName, "Q")

        KeyboardLayoutKeys.shared.setTestingLayout(FakeCommandLayout.german)
        XCTAssertEqual(KeyCode.name(of: 6), "Y")
        XCTAssertEqual(KeyCode.name(of: 27), "ß", "no upper case of two letters")

        // With Command the key is named as a ⌘ shortcut sees it.
        KeyboardLayoutKeys.shared.setTestingLayout(FakeCommandLayout.russian)
        XCTAssertEqual(KeyCode.name(of: 0), "Ф")
        XCTAssertEqual(KeyCode.name(of: 0, modifiers: CGEventFlags.maskCommand.rawValue), "A")
        KeyboardLayoutKeys.shared.setTestingLayout(FakeCommandLayout.dvorakQwertyCommand)
        XCTAssertEqual(KeyCode.name(of: 8), "J")
        XCTAssertEqual(KeyCode.name(of: 8, modifiers: CGEventFlags.maskCommand.rawValue), "C")
    }

    func testWhatAKeyTypesAsItsName() {
        XCTAssertEqual(KeyboardLayoutKeys.label(from: "a"), "A")
        XCTAssertEqual(KeyboardLayoutKeys.label(from: "ß"), "ß")
        XCTAssertEqual(KeyboardLayoutKeys.label(from: "é"), "É")
        XCTAssertEqual(KeyboardLayoutKeys.label(from: "<"), "<")
        XCTAssertNil(KeyboardLayoutKeys.label(from: ""))
        XCTAssertNil(KeyboardLayoutKeys.label(from: " "))
        XCTAssertNil(KeyboardLayoutKeys.label(from: "\u{1b}"), "a control character")
        XCTAssertNil(KeyboardLayoutKeys.label(from: "\u{F704}"), "the private code of a function key")
        XCTAssertEqual(KeyCode.usLetters.count, 26)
        XCTAssertEqual(KeyCode.usLetters[0], "a")
        XCTAssertEqual(KeyCode.usLetterKeyCodes["z"], 6)
        XCTAssertFalse(KeyCode.layoutDependentKeys.contains(49))
        XCTAssertTrue(KeyCode.layoutDependentKeys.contains(10), "the extra key of ISO keyboards")
    }

    // MARK: A recorded shortcut that is a listed action

    private func recorded(_ code: UInt16, _ flags: CGEventFlags = .maskCommand) -> String {
        return ButtonBinding.normalizedCustomBindingName(code: code, modifiers: flags.rawValue)
    }

    private func listedAction(for code: UInt16, _ flags: CGEventFlags = .maskCommand) -> String? {
        return SystemShortcut.displayShortcut(matchingBindingName: recorded(code, flags))?.identifier
    }

    func testARecordedShortcutIsComparedWithTheLayoutsKey() {
        // US (no layout): as before.
        XCTAssertEqual(listedAction(for: 0), "selectAll")
        XCTAssertEqual(listedAction(for: 12), "quitApp")

        // AZERTY: ⌘ with the A key (the US Q key) was stored and shown as "Quit App".
        KeyboardLayoutKeys.shared.setTestingLayout(FakeCommandLayout.french)
        XCTAssertEqual(listedAction(for: 12), "selectAll")
        XCTAssertEqual(listedAction(for: 0), "quitApp")
        XCTAssertEqual(listedAction(for: 13), "undo")
        XCTAssertEqual(listedAction(for: 6), "closeWindow")
        XCTAssertEqual(listedAction(for: 13, [.maskCommand, .maskShift]), "redo")
        // And what is stored is the action, which is then sent by its letter on any layout.
        let event = InputEvent(type: .keyboard, code: 12, modifiers: .maskCommand, phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(ButtonActionPullDown.bindingName(forRecorded: event), "selectAll")

        KeyboardLayoutKeys.shared.setTestingLayout(FakeCommandLayout.german)
        XCTAssertEqual(listedAction(for: 16), "undo")
        XCTAssertNil(listedAction(for: 6), "⌘Y is no listed action")
    }

    // MARK: The real translation

    /// UCKeyTranslate with Command held, for installed layouts picked by id (the layout the
    /// Mac types with does not matter).
    func testInstalledLayoutsTranslateWithCommandHeldAsTheFakesSay() throws {
        func installed(_ id: String) -> TISInputSource? {
            let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
            guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as NSArray?,
                  let first = list.firstObject else { return nil }
            return (first as! TISInputSource)
        }
        var checked = 0
        for fake in [FakeCommandLayout.us, .french, .german] {
            guard let id = fake.id, let source = installed(id) else { continue }
            checked += 1
            let command = SystemKeyboardLayoutSource.characters(of: source, modifierKeyState: SystemKeyboardLayoutSource.commandKeyState)
            let keys = KeyboardLayoutKeys.letterKeys(typing: command)
            let expected = KeyboardLayoutKeys.letterKeys(typing: fake.command)
            for letter in ["a", "q", "w", "z", "y", "m", "c", "v", "x"] {
                XCTAssertEqual(keys[letter], expected[letter], "\(id): \(letter)")
            }
        }
        // Dvorak - QWERTY ⌘ types Dvorak and, with Command, QWERTY.
        if let source = installed("com.apple.keylayout.DVORAK-QWERTYCMD") {
            checked += 1
            let plain = SystemKeyboardLayoutSource.characters(of: source)
            let command = SystemKeyboardLayoutSource.characters(of: source, modifierKeyState: SystemKeyboardLayoutSource.commandKeyState)
            XCTAssertEqual(plain[8], "j")
            XCTAssertEqual(command[8], "c")
            XCTAssertEqual(AppZoomKeys.codes(typing: command), AppZoomKeys.usCodes, "zoom follows the keys under ⌘ too")
        }
        try XCTSkipIf(checked == 0, "none of the layouts is installed")
    }
}

// MARK: - The executor: Logitech actions, retired and unknown actions, apps, scripts

final class ShortcutExecutorFixesTests: XCTestCase {

    // MARK: Logitech actions

    /// Four of the seven did nothing when a gesture or a standard button ran them: only
    /// three names were known here. (Ten were offered once; the three toggles that left the
    /// mouse changed were removed from the list.)
    func testEveryLogitechActionReachesTheMouse() {
        let executor = ShortcutExecutor()
        var performed: [String] = []
        executor.logiActionPerformer = { performed.append($0) }
        let identifiers = SystemShortcut.logiActionsCategory.shortcuts.map(\.identifier)
        XCTAssertEqual(identifiers.count, 7)
        for identifier in identifiers {
            guard let action = executor.resolveAction(named: identifier), case .logiAction = action else {
                XCTFail("\(identifier) is a Logitech action")
                continue
            }
            executor.execute(action: action, phase: .down)
            executor.execute(action: action, phase: .up)
        }
        XCTAssertEqual(performed, identifiers, "each once, at the press")
    }

    // MARK: "Shut Down…"

    /// It was sent as Control-Z: no dialog, and the app in front got ⌃Z.
    func testShutDownIsNoLongerOfferedAndSendsNothing() {
        XCTAssertFalse(SystemShortcut.shortcutsByCategory.flatMap(\.shortcuts).contains { $0.identifier == "shutdownDialog" })
        XCTAssertTrue(SystemShortcut.isRetired("shutdownDialog"))
        // A stored binding keeps its name and stays an action (the button is taken) ...
        XCTAssertEqual(SystemShortcut.getShortcut(named: "shutdownDialog")?.localizedName, "Shut Down…")
        let executor = ShortcutExecutor()
        var posted = 0
        executor.setTestingKeyboardShortcutObserver { _, _, _ in posted += 1 }
        guard let action = executor.resolveAction(named: "shutdownDialog") else { return XCTFail("still an action") }
        // ... and a press sends nothing.
        executor.execute(action: action, phase: .down)
        executor.execute(action: action, phase: .up)
        executor.execute(named: "shutdownDialog")
        XCTAssertEqual(posted, 0)
        // A recorded ⌃Z is not shown as "Shut Down…".
        let controlZ = ButtonBinding.normalizedCustomBindingName(code: 6, modifiers: CGEventFlags.maskControl.rawValue)
        XCTAssertNil(SystemShortcut.displayShortcut(matchingBindingName: controlZ))
        // The other actions still post.
        executor.execute(named: "copy")
        XCTAssertEqual(posted, 1)
    }

    // MARK: Unknown actions

    func testAnActionThisVersionDoesNotKnowIsNoAction() {
        let executor = ShortcutExecutor()
        XCTAssertNil(executor.resolveAction(named: "actionOfANewerVersion"))
        XCTAssertNil(executor.resolveAction(named: "logiActionOfANewerVersion"))
        XCTAssertNil(executor.resolveAction(named: ""))
        XCTAssertNotNil(executor.resolveAction(named: "copy"))
        XCTAssertNotNil(executor.resolveAction(named: "logiHost2"))
    }

    // MARK: Next Tab / Previous Tab

    func testNextAndPreviousTabAreControlTab() {
        XCTAssertEqual(SystemShortcut.nextTab.code, 48)
        XCTAssertEqual(SystemShortcut.nextTab.modifiers, .control)
        XCTAssertEqual(SystemShortcut.previousTab.code, 48)
        XCTAssertEqual(SystemShortcut.previousTab.modifiers, [.control, .shift])
        // The identifiers, and so the stored bindings, are the same.
        XCTAssertEqual(SystemShortcut.getShortcut(named: "nextTab"), SystemShortcut.nextTab)
        XCTAssertEqual(SystemShortcut.getShortcut(named: "previousTab"), SystemShortcut.previousTab)
        let controlTab = ButtonBinding.normalizedCustomBindingName(code: 48, modifiers: CGEventFlags.maskControl.rawValue)
        XCTAssertEqual(SystemShortcut.displayShortcut(matchingBindingName: controlTab)?.identifier, "nextTab")
    }

    // MARK: Which app opens

    /// The identifier came first: a button set to one copy of an app opened the other copy,
    /// the one macOS prefers for the identifier.
    func testAnAppIsOpenedByItsPathWhileItIsThere() {
        let payload = OpenTargetPayload(path: "/Applications/Editor-beta.app", bundleID: "com.example.editor",
                                        arguments: "", kind: .application)
        let other = URL(fileURLWithPath: "/Applications/Editor.app")
        XCTAssertEqual(
            ShortcutExecutor.applicationURL(for: payload, fileExists: { _ in true }, urlForBundleIdentifier: { _ in other })?.path,
            "/Applications/Editor-beta.app"
        )
        // Gone from its path (moved, renamed): whatever app macOS knows by the identifier.
        XCTAssertEqual(
            ShortcutExecutor.applicationURL(for: payload, fileExists: { _ in false }, urlForBundleIdentifier: { _ in other }),
            other
        )
        XCTAssertNil(ShortcutExecutor.applicationURL(for: payload, fileExists: { _ in false }, urlForBundleIdentifier: { _ in nil }))
        // A file or script has no identifier: its path, or nothing.
        let file = OpenTargetPayload(path: "/tmp/notes.txt", bundleID: nil, arguments: "", kind: .file)
        XCTAssertNil(ShortcutExecutor.applicationURL(for: file, fileExists: { _ in false }, urlForBundleIdentifier: { _ in other }))
    }

    // MARK: Scripts

    func testAScriptGetsTheUsersToolFoldersAtTheEndOfItsPath() {
        let bare = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": "/Users/test", "DYLD_INSERT_LIBRARIES": "/x.dylib"]
        let both = ShortcutExecutor.scriptEnvironment(from: bare, existingFolders: { _ in true })
        XCTAssertEqual(both["PATH"], "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin",
                       "after the system's folders: nothing there stands in for a system tool")
        XCTAssertEqual(both["HOME"], "/Users/test")
        XCTAssertNil(both["DYLD_INSERT_LIBRARIES"], "still without what a debugger injects")
        // Only folders that exist, and none twice.
        let intel = ShortcutExecutor.scriptEnvironment(from: bare, existingFolders: { $0 == "/usr/local/bin" })
        XCTAssertEqual(intel["PATH"], "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin")
        let already = ShortcutExecutor.scriptEnvironment(from: ["PATH": "/opt/homebrew/bin:/usr/bin"], existingFolders: { _ in true })
        XCTAssertEqual(already["PATH"], "/opt/homebrew/bin:/usr/bin:/usr/local/bin")
        let none = ShortcutExecutor.scriptEnvironment(from: [:], existingFolders: { _ in false })
        XCTAssertEqual(none["PATH"], "/usr/bin:/bin:/usr/sbin:/sbin")
    }

    func testOnlyAScriptThatFailsSoonGetsAToast() {
        XCTAssertTrue(ShortcutExecutor.showsScriptFailure(status: 1, endedBySignal: false, elapsed: 0.2))
        XCTAssertTrue(ShortcutExecutor.showsScriptFailure(status: 127, endedBySignal: false, elapsed: 4.9))
        XCTAssertFalse(ShortcutExecutor.showsScriptFailure(status: 0, endedBySignal: false, elapsed: 0.2), "it worked")
        XCTAssertFalse(ShortcutExecutor.showsScriptFailure(status: 1, endedBySignal: false, elapsed: 60), "long after the press")
        XCTAssertFalse(ShortcutExecutor.showsScriptFailure(status: 15, endedBySignal: true, elapsed: 0.2), "quit by the user")
    }

    /// The log never carries a path: an error is written as where it comes from and its number.
    func testAnErrorIsLoggedWithoutItsText() {
        let error = NSError(domain: NSCocoaErrorDomain, code: 260, userInfo: [
            NSLocalizedDescriptionKey: "The file “/Users/someone/Secret Plans.sh” doesn’t exist.",
            NSFilePathErrorKey: "/Users/someone/Secret Plans.sh",
        ])
        XCTAssertEqual(ShortcutExecutor.logText(of: error), "NSCocoaErrorDomain 260")
    }

    /// A bound script is started in its own folder (it was "/"), with its arguments as they
    /// are, and a failure soon after the start is noticed. Runs a real, harmless child
    /// process (/bin/sh) through the same `ScriptLaunch` the app uses.
    func testAScriptStartsInItsOwnFolderAndItsEndIsNoticed() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ScrollioTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let script = folder.appendingPathComponent("write here.sh")
        try "#!/bin/sh\npwd > where.txt\nprintf '%s|' \"$@\" > args.txt\nexit 3\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let ended = expectation(description: "the script ended")
        var result: (status: Int32, bySignal: Bool)?
        let launch = ScriptLaunch(
            executable: script,
            arguments: ArgumentSplitter.split("--name='My File' two"),
            environment: ShortcutExecutor.scriptEnvironment(from: ["PATH": "/usr/bin:/bin"], existingFolders: { _ in false }),
            workingDirectory: folder
        )
        try launch.start { status, bySignal in
            result = (status, bySignal)
            ended.fulfill()
        }
        wait(for: [ended], timeout: 10)
        XCTAssertEqual(result?.status, 3)
        XCTAssertEqual(result?.bySignal, false)
        let where_ = try String(contentsOf: folder.appendingPathComponent("where.txt"), encoding: .utf8)
        XCTAssertEqual(URL(fileURLWithPath: where_.trimmingCharacters(in: .whitespacesAndNewlines)).resolvingSymlinksInPath().path,
                       folder.resolvingSymlinksInPath().path)
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("args.txt"), encoding: .utf8), "--name=My File|two|")
    }

    /// A bound script is started as a program of its own: macOS holds the script itself
    /// responsible, not Scrollio, so it does not act with Scrollio's Accessibility access.
    /// Asked of the system for two real, harmless child processes (/bin/sleep).
    func testAScriptIsStartedWithTheResponsibilityDisclaimed() throws {
        typealias ResponsiblePid = @convention(c) (pid_t) -> pid_t
        guard ScriptLaunch.setDisclaim != nil,
              let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else {
            throw XCTSkip("this macOS does not have the functions")
        }
        let responsiblePid = unsafeBitCast(symbol, to: ResponsiblePid.self)
        let launch = ScriptLaunch(
            executable: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["30"],
            environment: ["PATH": "/usr/bin:/bin"],
            workingDirectory: URL(fileURLWithPath: "/")
        )

        let disclaimedEnded = expectation(description: "the disclaimed one ended")
        var disclaimedEnd: (status: Int32, bySignal: Bool)?
        let disclaimed = try launch.start { status, bySignal in
            disclaimedEnd = (status, bySignal)
            disclaimedEnded.fulfill()
        }
        XCTAssertTrue(disclaimed.isDisclaimed)
        XCTAssertEqual(responsiblePid(disclaimed.processIdentifier), disclaimed.processIdentifier,
                       "macOS holds the script itself responsible")

        // The plain child, as it was started before: whoever is responsible for this process.
        let childEnded = expectation(description: "the plain child ended")
        let child = try launch.startAsChild { _, _ in childEnded.fulfill() }
        XCTAssertEqual(responsiblePid(child), responsiblePid(getpid()))
        XCTAssertNotEqual(responsiblePid(child), child)

        // Ended by a signal: collected (no dead process stays behind) and reported as such.
        kill(disclaimed.processIdentifier, SIGTERM)
        kill(child, SIGTERM)
        wait(for: [disclaimedEnded, childEnded], timeout: 10)
        XCTAssertEqual(disclaimedEnd?.bySignal, true)
        XCTAssertEqual(disclaimedEnd?.status, SIGTERM)
        XCTAssertEqual(kill(disclaimed.processIdentifier, 0), -1, "gone and collected")
    }

    func testHowAProcessEndedIsReadFromItsWaitStatus() {
        XCTAssertTrue(ScriptLaunch.outcome(ofWaitStatus: 0) == (0, false))
        XCTAssertTrue(ScriptLaunch.outcome(ofWaitStatus: 3 << 8) == (3, false))
        XCTAssertTrue(ScriptLaunch.outcome(ofWaitStatus: 127 << 8) == (127, false))
        XCTAssertTrue(ScriptLaunch.outcome(ofWaitStatus: SIGTERM) == (SIGTERM, true))
        XCTAssertTrue(ScriptLaunch.outcome(ofWaitStatus: SIGKILL | 0x80) == (SIGKILL, true), "with a core dump flag")
    }

    /// A script that cannot be started at all throws, the same way on both paths.
    func testAScriptThatCannotBeStartedThrows() {
        let launch = ScriptLaunch(
            executable: URL(fileURLWithPath: "/nonexistent/ScrollioTests-no-such-script"),
            arguments: [],
            environment: [:],
            workingDirectory: URL(fileURLWithPath: "/")
        )
        XCTAssertThrowsError(try launch.start { _, _ in XCTFail("it never ran") })
    }

    // MARK: A Spaces action whose shortcut is switched off

    /// "Move left a space" works through the user's shortcut. Switched off in System
    /// Settings, ⌃← was sent anyway: no Space changed and the app in front got the keys.
    func testASpacesActionWhoseShortcutIsSwitchedOffSendsNothingAndSaysSo() {
        defer { SystemShortcut.setTestingSystemShortcutState(nil) }
        let executor = ShortcutExecutor()
        var posted: [(CGKeyCode, UInt64)] = []
        var notices: [String] = []
        executor.setTestingKeyboardShortcutObserver { code, flags, _ in posted.append((code, flags)) }
        executor.switchedOffNotice = { notices.append($0) }

        // Not customized: the standard keys.
        SystemShortcut.setTestingSystemShortcutState(SystemShortcut.SystemShortcutState())
        executor.execute(named: "moveSpaceLeft")
        XCTAssertEqual(posted.last?.0, 123)
        // The user's own keys.
        SystemShortcut.setTestingSystemShortcutState(SystemShortcut.SystemShortcutState(
            resolved: ["moveSpaceLeft": (code: 0, modifiers: 0x40000)]
        ))
        executor.execute(named: "moveSpaceLeft")
        XCTAssertEqual(posted.last?.0, 0)
        XCTAssertEqual(notices, [])

        // Switched off: nothing is sent, and the user is told.
        SystemShortcut.setTestingSystemShortcutState(SystemShortcut.SystemShortcutState(switchedOff: ["moveSpaceLeft"]))
        let before = posted.count
        executor.execute(named: "moveSpaceLeft")
        XCTAssertEqual(posted.count, before)
        XCTAssertEqual(notices, [SystemShortcut.moveSpaceLeft.localizedName])
        // The other direction is still on.
        executor.execute(named: "moveSpaceRight")
        XCTAssertEqual(posted.last?.0, 124)
        XCTAssertEqual(notices.count, 1)
    }

    func testWhichShortcutsAreSwitchedOffIsReadFromSystemSettings() {
        func entry(enabled: Any) -> [String: Any] {
            return ["enabled": enabled, "value": ["parameters": [65535, 123, 8650752], "type": "standard"]]
        }
        XCTAssertEqual(SystemShortcut.switchedOffShortcuts(fromSymbolicHotKeys: [:]), [], "not customized is not off")
        XCTAssertEqual(SystemShortcut.switchedOffShortcuts(fromSymbolicHotKeys: ["79": entry(enabled: true), "81": entry(enabled: true)]), [])
        XCTAssertEqual(SystemShortcut.switchedOffShortcuts(fromSymbolicHotKeys: ["79": entry(enabled: false), "81": entry(enabled: true)]),
                       ["moveSpaceLeft"])
        XCTAssertEqual(SystemShortcut.switchedOffShortcuts(fromSymbolicHotKeys: ["79": entry(enabled: false), "81": entry(enabled: false)]),
                       ["moveSpaceLeft", "moveSpaceRight"])
        // Only the main shortcuts count, and data of another shape is no answer.
        XCTAssertEqual(SystemShortcut.switchedOffShortcuts(fromSymbolicHotKeys: ["80": entry(enabled: false), "82": entry(enabled: false)]), [])
        XCTAssertEqual(SystemShortcut.switchedOffShortcuts(fromSymbolicHotKeys: ["79": "off", "81": ["enabled": "no"]]), [])
        // Under XCTest the Mac's own shortcuts are never read.
        XCTAssertNil(SystemShortcut.resolveSystemShortcut("moveSpaceLeft"))
        XCTAssertFalse(SystemShortcut.isSwitchedOffInSystemSettings("moveSpaceLeft"))
        let text = String(format: NSLocalizedString("toast-system-shortcut-off", comment: ""), "Move Space Left")
        XCTAssertTrue(text.contains("Move Space Left") && text.contains("System Settings"), text)
    }

    // MARK: Open or run

    /// The executable bit alone decided: on an exFAT volume, where every file has it, a PDF
    /// was stored as a script.
    func testAFileIsRunOnlyWhenItsTypeSaysItIsAProgram() {
        typealias Popover = OpenTargetConfigPopover
        XCTAssertEqual(Popover.defaultKind(isExecutable: true, contentType: .pdf), .file)
        XCTAssertEqual(Popover.defaultKind(isExecutable: true, contentType: .png), .file)
        XCTAssertEqual(Popover.defaultKind(isExecutable: true, contentType: .plainText), .file)
        XCTAssertEqual(Popover.defaultKind(isExecutable: true, contentType: nil), .file)
        XCTAssertEqual(Popover.defaultKind(isExecutable: true, contentType: .shellScript), .script)
        XCTAssertEqual(Popover.defaultKind(isExecutable: true, contentType: .pythonScript), .script)
        XCTAssertEqual(Popover.defaultKind(isExecutable: true, contentType: .unixExecutable), .script)
        // Without the bit nothing can run it.
        XCTAssertEqual(Popover.defaultKind(isExecutable: false, contentType: .shellScript), .file)
        XCTAssertEqual(Popover.defaultKind(isExecutable: false, contentType: .unixExecutable), .file)
    }

    /// The slot is a button for the keyboard and VoiceOver; it was a plain view with a
    /// mouse-down only.
    func testTheFileSlotIsAButtonForTheKeyboardAndVoiceOver() {
        let slot = FileSlotView(frame: NSRect(x: 0, y: 0, width: 320, height: 76))
        var clicks = 0
        slot.onClick = { clicks += 1 }
        XCTAssertTrue(slot.acceptsFirstResponder)
        XCTAssertTrue(slot.canBecomeKeyView)
        XCTAssertTrue(slot.isAccessibilityElement())
        XCTAssertEqual(slot.accessibilityRole(), .button)
        XCTAssertEqual(slot.accessibilityLabel(), NSLocalizedString("open-target-empty-primary", comment: ""))
        XCTAssertTrue(slot.accessibilityPerformPress())
        XCTAssertEqual(clicks, 1)
        XCTAssertTrue(FileSlotView.isPressKey(49) && FileSlotView.isPressKey(36) && FileSlotView.isPressKey(76))
        XCTAssertFalse(FileSlotView.isPressKey(0))
        for code: UInt16 in [49, 36] {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                         context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false,
                                         keyCode: code)!
            slot.keyDown(with: event)
        }
        XCTAssertEqual(clicks, 3, "Space and Return press it")

        slot.setState(.filled(FileSlotView.FilledContent(icon: nil, title: "Safari", subtitle: "/Applications/Safari.app")), animated: false)
        XCTAssertEqual(slot.accessibilityLabel(), "Safari, /Applications/Safari.app")
        // The "x" is named for VoiceOver, and the texts that were close to invisible are secondary.
        func labels(in view: NSView) -> [NSTextField] {
            return view.subviews.flatMap { ($0 as? NSTextField).map { [$0] } ?? labels(in: $0) }
        }
        func buttons(in view: NSView) -> [NSButton] {
            return view.subviews.flatMap { ($0 as? NSButton).map { [$0] } ?? buttons(in: $0) }
        }
        XCTAssertEqual(buttons(in: slot).first?.accessibilityLabel(), NSLocalizedString("open-target-clear-tooltip", comment: ""))
        let secondaryTexts = labels(in: slot).filter { $0.textColor == NSColor.secondaryLabelColor }.map(\.stringValue)
        XCTAssertTrue(secondaryTexts.contains(NSLocalizedString("open-target-empty-secondary", comment: "")))
        XCTAssertTrue(secondaryTexts.contains("/Applications/Safari.app"))
        XCTAssertFalse(labels(in: slot).contains { $0.textColor == NSColor.tertiaryLabelColor })
    }
}
