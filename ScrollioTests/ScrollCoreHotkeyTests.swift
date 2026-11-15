//
//  ScrollCoreHotkeyTests.swift
//  MosTests
//
//  ScrollCore.handleScrollHotkey 热键匹配测试 (Task 9)
//
//  注意: 这些测试直接操作 ScrollCore.shared 的热键状态,
//  由于 handleScrollHotkey 内部会调用 ScrollUtils.shared 和
//  NSWorkspace 来获取热键配置, 在 CI 环境中配置可能为 nil。
//  因此仅测试 key-up 释放逻辑 (不依赖热键配置) 和基本返回值。
//

import XCTest
@testable import Scrollio_Debug

final class ScrollCoreHotkeyTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // 重置 ScrollCore 热键状态
        ScrollCore.shared.dashScroll = false
        ScrollCore.shared.dashAmplification = 1.0
        ScrollCore.shared.toggleScroll = false
        ScrollCore.shared.blockSmooth = false
        ScrollCore.shared.dashKeyHeld = false
        ScrollCore.shared.slowKeyHeld = false
        ScrollCore.shared.slowScroll = false
        ScrollCore.shared.toggleKeyHeld = false
        ScrollCore.shared.blockKeyHeld = false
    }

    override func tearDown() {
        // 清理状态
        ScrollCore.shared.dashScroll = false
        ScrollCore.shared.dashAmplification = 1.0
        ScrollCore.shared.toggleScroll = false
        ScrollCore.shared.blockSmooth = false
        ScrollCore.shared.dashKeyHeld = false
        ScrollCore.shared.slowKeyHeld = false
        ScrollCore.shared.slowScroll = false
        ScrollCore.shared.toggleKeyHeld = false
        ScrollCore.shared.blockKeyHeld = false
        super.tearDown()
    }

    // MARK: - key-up: 无已激活状态时

    func testKeyUp_withNoHeldCodes_returnsFalse() {
        let result = ScrollCore.shared.handleScrollHotkey(code: 42, isDown: false)
        XCTAssertFalse(result, "key-up with no held codes should return false")
    }

    // MARK: - key-up: 释放已跟踪的 code

    func testKeyUp_releasesTrackedDashCode() {
        // 模拟 dash 已被 HID++ 按下
        ScrollCore.shared.dashScroll = true
        ScrollCore.shared.dashAmplification = 5.0
        ScrollCore.shared.dashKeyHeld = true

        // 直接设置私有的 hidDashHeldCode (通过模拟一次完整的 down-up)
        // 由于 hidDashHeldCode 是 private, 我们需要通过正常的 key-down 路径设置
        // 但 key-down 依赖 Options 配置, 所以这里测试 key-up 对不匹配的 code 不会误清除
        let result = ScrollCore.shared.handleScrollHotkey(code: 999, isDown: false)
        XCTAssertFalse(result, "key-up with non-matching code should return false")

        // 验证状态没有被错误清除
        XCTAssertTrue(ScrollCore.shared.dashScroll, "dashScroll should not be cleared by non-matching key-up")
        XCTAssertEqual(ScrollCore.shared.dashAmplification, 5.0, "dashAmplification should not be cleared")
    }

    // MARK: - key-down: 无热键配置时

    func testKeyDown_withNoHotkeyConfig_returnsFalse() {
        // 在没有配置 HID++ 鼠标按键热键时 (默认热键是键盘修饰键),
        // mouse type 的 code 不会匹配, 应返回 false
        // 默认: dash=optionL(keyboard), toggle=shiftL(keyboard), block=commandL(keyboard)
        let result = ScrollCore.shared.handleScrollHotkey(code: 100, isDown: true)
        // 由于默认热键是 keyboard 类型, 而 HID++ 匹配要求 type == .mouse,
        // 所以不会匹配
        XCTAssertFalse(result, "keyboard-type hotkey should not match mouse code from HID++")
    }

    // MARK: - key-down 后 key-up 完整流程 (需要配置 mouse 类型热键)

    func testKeyDown_thenKeyUp_withMouseHotkey() {
        // 临时配置 dash 热键为 mouse 按键 code=50
        let originalDash = Options.shared.scroll.dash
        Options.shared.scroll.dash = ScrollHotkey(type: .mouse, code: 50)
        defer { Options.shared.scroll.dash = originalDash }

        // key-down
        let downResult = ScrollCore.shared.handleScrollHotkey(code: 50, isDown: true)
        XCTAssertTrue(downResult, "mouse hotkey matching code should return true on key-down")
        XCTAssertTrue(ScrollCore.shared.dashScroll, "dashScroll should be set on key-down")
        XCTAssertTrue(ScrollCore.shared.dashKeyHeld, "dashKeyHeld should be set")
        XCTAssertEqual(ScrollCore.shared.dashAmplification, 5.0, "dashAmplification should be 5.0")

        // key-up
        let upResult = ScrollCore.shared.handleScrollHotkey(code: 50, isDown: false)
        XCTAssertTrue(upResult, "key-up of tracked code should return true")
        XCTAssertFalse(ScrollCore.shared.dashScroll, "dashScroll should be cleared on key-up")
        XCTAssertFalse(ScrollCore.shared.dashKeyHeld, "dashKeyHeld should be cleared")
        XCTAssertEqual(ScrollCore.shared.dashAmplification, 1.0, "dashAmplification should reset to 1.0")
    }

    func testKeyDown_thenKeyUp_toggleHotkey() {
        let originalToggle = Options.shared.scroll.toggle
        Options.shared.scroll.toggle = ScrollHotkey(type: .mouse, code: 60)
        defer { Options.shared.scroll.toggle = originalToggle }

        let downResult = ScrollCore.shared.handleScrollHotkey(code: 60, isDown: true)
        XCTAssertTrue(downResult)
        XCTAssertTrue(ScrollCore.shared.toggleScroll)
        XCTAssertTrue(ScrollCore.shared.toggleKeyHeld)

        let upResult = ScrollCore.shared.handleScrollHotkey(code: 60, isDown: false)
        XCTAssertTrue(upResult)
        XCTAssertFalse(ScrollCore.shared.toggleScroll)
        XCTAssertFalse(ScrollCore.shared.toggleKeyHeld)
    }

    func testKeyDown_thenKeyUp_blockHotkey() {
        let originalBlock = Options.shared.scroll.block
        Options.shared.scroll.block = ScrollHotkey(type: .mouse, code: 70)
        defer { Options.shared.scroll.block = originalBlock }

        let downResult = ScrollCore.shared.handleScrollHotkey(code: 70, isDown: true)
        XCTAssertTrue(downResult)
        XCTAssertTrue(ScrollCore.shared.blockSmooth)
        XCTAssertTrue(ScrollCore.shared.blockKeyHeld)

        let upResult = ScrollCore.shared.handleScrollHotkey(code: 70, isDown: false)
        XCTAssertTrue(upResult)
        XCTAssertFalse(ScrollCore.shared.blockSmooth)
        XCTAssertFalse(ScrollCore.shared.blockKeyHeld)
    }

    // MARK: - 多个热键同时按下

    func testMultipleHotkeys_simultaneouslyPressed() {
        let originalDash = Options.shared.scroll.dash
        let originalToggle = Options.shared.scroll.toggle
        Options.shared.scroll.dash = ScrollHotkey(type: .mouse, code: 50)
        Options.shared.scroll.toggle = ScrollHotkey(type: .mouse, code: 60)
        defer {
            Options.shared.scroll.dash = originalDash
            Options.shared.scroll.toggle = originalToggle
        }

        // 按下 dash
        ScrollCore.shared.handleScrollHotkey(code: 50, isDown: true)
        XCTAssertTrue(ScrollCore.shared.dashScroll)

        // 同时按下 toggle
        ScrollCore.shared.handleScrollHotkey(code: 60, isDown: true)
        XCTAssertTrue(ScrollCore.shared.toggleScroll)
        XCTAssertTrue(ScrollCore.shared.dashScroll, "dash should still be active")

        // 释放 dash
        ScrollCore.shared.handleScrollHotkey(code: 50, isDown: false)
        XCTAssertFalse(ScrollCore.shared.dashScroll, "dash should be released")
        XCTAssertTrue(ScrollCore.shared.toggleScroll, "toggle should still be active")

        // 释放 toggle
        ScrollCore.shared.handleScrollHotkey(code: 60, isDown: false)
        XCTAssertFalse(ScrollCore.shared.toggleScroll, "toggle should be released")
    }

    // MARK: - key-up 不依赖当前 app 配置 (防止焦点切换状态卡死)

    func testKeyUp_releasesRegardlessOfCurrentConfig() {
        // 配置 dash 为 mouse code=50 并按下
        let originalDash = Options.shared.scroll.dash
        Options.shared.scroll.dash = ScrollHotkey(type: .mouse, code: 50)
        ScrollCore.shared.handleScrollHotkey(code: 50, isDown: true)
        XCTAssertTrue(ScrollCore.shared.dashScroll)

        // 改变配置 (模拟焦点切换到不同 app)
        Options.shared.scroll.dash = ScrollHotkey(type: .mouse, code: 999)

        // key-up 仍然应该按照跟踪的 code 释放
        let upResult = ScrollCore.shared.handleScrollHotkey(code: 50, isDown: false)
        XCTAssertTrue(upResult, "key-up should release by tracked code, not current config")
        XCTAssertFalse(ScrollCore.shared.dashScroll)

        Options.shared.scroll.dash = originalDash
    }

    // MARK: - 同一 code 配置给多个热键

    func testSameCode_matchesAllConfiguredHotkeys() {
        let originalDash = Options.shared.scroll.dash
        let originalToggle = Options.shared.scroll.toggle
        let originalBlock = Options.shared.scroll.block
        // 配置所有热键为同一 code
        Options.shared.scroll.dash = ScrollHotkey(type: .mouse, code: 80)
        Options.shared.scroll.toggle = ScrollHotkey(type: .mouse, code: 80)
        Options.shared.scroll.block = ScrollHotkey(type: .mouse, code: 80)
        defer {
            Options.shared.scroll.dash = originalDash
            Options.shared.scroll.toggle = originalToggle
            Options.shared.scroll.block = originalBlock
        }

        let downResult = ScrollCore.shared.handleScrollHotkey(code: 80, isDown: true)
        XCTAssertTrue(downResult)
        XCTAssertTrue(ScrollCore.shared.dashScroll)
        XCTAssertTrue(ScrollCore.shared.toggleScroll)
        XCTAssertTrue(ScrollCore.shared.blockSmooth)

        let upResult = ScrollCore.shared.handleScrollHotkey(code: 80, isDown: false)
        XCTAssertTrue(upResult)
        XCTAssertFalse(ScrollCore.shared.dashScroll)
        XCTAssertFalse(ScrollCore.shared.toggleScroll)
        XCTAssertFalse(ScrollCore.shared.blockSmooth)
    }

    // MARK: - B4: a mouse button number above 127

    /// CoreGraphics keeps a mouse event's button number in 8 bits and reads it back signed:
    /// 200 comes back as -56, and `UInt16(-56)` traps. The hold-key tap read it that way for
    /// every other-button event: an event another program made up with such a number crashed
    /// the app, each time.
    func testAButtonNumberAbove127_isReadWithoutATrap() throws {
        let event = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .otherMouseUp,
                                          mouseCursorPosition: CGPoint(x: 40, y: 40), mouseButton: .center))
        event.setIntegerValueField(.mouseEventButtonNumber, value: 200)
        let field = event.getIntegerValueField(.mouseEventButtonNumber)
        XCTAssertEqual(field, -56, "what CoreGraphics gives back for 200")
        XCTAssertNil(UInt16(exactly: field), "the conversion that trapped")

        XCTAssertEqual(ScrollCore.mouseButtonNumber(fromField: field), 200)
        XCTAssertEqual(ScrollCore.mouseButtonNumber(fromField: -128), 128)
        XCTAssertEqual(ScrollCore.mouseButtonNumber(fromField: -1), 255)
        for number in [Int64(0), 2, 31, 127] {
            XCTAssertEqual(ScrollCore.mouseButtonNumber(fromField: number), UInt16(number), "as before")
        }
    }

    /// The same through the hold-key tap's callback, with the release of button 200 (the
    /// press first asks `CGEvent.mouseCode`, which has the same conversion and its own fix).
    /// A scroll key recorded for that button is released by it, so the number read is 200.
    func testTheHoldKeyTap_takesAReleaseOfButton200() throws {
        let saved = (Options.shared.scroll.dash, ScrollCore.shared.application, ScrollCore.shared.currentApplication)
        defer {
            Options.shared.scroll.dash = saved.0
            ScrollCore.shared.application = saved.1
            ScrollCore.shared.currentApplication = saved.2
        }
        ScrollCore.shared.application = nil
        ScrollCore.shared.currentApplication = nil
        Options.shared.scroll.dash = ScrollHotkey(type: .mouse, code: 200)
        ScrollCore.shared.dashKeyHeld = true
        ScrollCore.shared.dashScroll = true
        ScrollCore.shared.dashAmplification = 5.0

        let release = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .otherMouseUp,
                                            mouseCursorPosition: CGPoint(x: 40, y: 40), mouseButton: .center))
        release.setIntegerValueField(.mouseEventButtonNumber, value: 200)
        let result = ScrollCore.shared.hotkeyEventCallBack(CGEventTapProxy(bitPattern: 1)!, .otherMouseUp, release, nil)

        XCTAssertNil(result, "a listen-only tap returns nothing")
        XCTAssertFalse(ScrollCore.shared.dashKeyHeld, "button 200 was recognised")
        XCTAssertEqual(ScrollCore.shared.dashAmplification, 1.0)

        // Another button does not release it.
        ScrollCore.shared.dashKeyHeld = true
        let other = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .otherMouseUp,
                                          mouseCursorPosition: CGPoint(x: 40, y: 40), mouseButton: .center))
        other.setIntegerValueField(.mouseEventButtonNumber, value: 255)
        _ = ScrollCore.shared.hotkeyEventCallBack(CGEventTapProxy(bitPattern: 1)!, .otherMouseUp, other, nil)
        XCTAssertTrue(ScrollCore.shared.dashKeyHeld)
    }
}

/// "Scroll slower": the hold key that makes a scroll go a fifth as far, the mirror of
/// "Scroll faster". The wheel goes through the scroll tap's callback as the tap runs it;
/// nothing is posted: what the poster would get goes to `posterInputObserverForTests`.
final class ScrollSlowerKeyTests: XCTestCase {

    private var inputs: [ScrollPosterInput] = []
    private var savedScroll: OPTIONS_SCROLL_DEFAULT!
    private var savedAllowlist = false
    private var savedApplication: Application?
    private var savedCurrentApplication: Application?

    override func setUp() {
        super.setUp()
        savedScroll = Options.shared.scroll
        savedAllowlist = Options.shared.application.allowlist
        savedApplication = ScrollCore.shared.application
        savedCurrentApplication = ScrollCore.shared.currentApplication
        // The settings of a new installation, with a mouse button for each of the two keys.
        let scroll = OPTIONS_SCROLL_DEFAULT()
        scroll.reverse = false
        scroll.dash = ScrollHotkey(type: .mouse, code: 50)
        scroll.slow = ScrollHotkey(type: .mouse, code: 51)
        Options.shared.scroll = scroll
        Options.shared.application.allowlist = false
        ScrollCore.shared.application = nil
        ScrollCore.shared.currentApplication = nil
        ScrollCore.shared.handover = ScrollHandover()
        ScrollCore.shared.toggleScroll = false
        ScrollCore.shared.blockSmooth = false
        ScrollUtils.shared.treatAsRemoteForTests(sourcePID: nil)
        releaseBoth()
        inputs = []
        ScrollCore.posterInputObserverForTests = { [unowned self] input in self.inputs.append(input) }
    }

    override func tearDown() {
        ScrollCore.posterInputObserverForTests = nil
        releaseBoth()
        ScrollCore.shared.handover = ScrollHandover()
        ScrollCore.shared.application = savedApplication
        ScrollCore.shared.currentApplication = savedCurrentApplication
        Options.shared.scroll = savedScroll
        Options.shared.application.allowlist = savedAllowlist
        ScrollSystemLog.resetPassthroughForTests()
        super.tearDown()
    }

    private func releaseBoth() {
        ScrollCore.shared.handleScrollHotkey(code: 50, isDown: false)
        ScrollCore.shared.handleScrollHotkey(code: 51, isDown: false)
        ScrollCore.shared.dashKeyHeld = false
        ScrollCore.shared.slowKeyHeld = false
        ScrollCore.shared.dashScroll = false
        ScrollCore.shared.slowScroll = false
        ScrollCore.shared.dashAmplification = 1.0
    }

    private func hold(faster: Bool, slower: Bool) {
        ScrollCore.shared.handleScrollHotkey(code: 50, isDown: faster)
        ScrollCore.shared.handleScrollHotkey(code: 51, isDown: slower)
    }

    /// What the poster gets for one click of the main wheel, aimed at no app (pid 1).
    private func click(point: Double) throws -> ScrollPosterInput {
        let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 0, wheel2: 0, wheel3: 0))
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: point < 0 ? -1 : 1)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: point < 0 ? -1 : 1)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: point)
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 0)
        event.setIntegerValueField(.eventSourceUnixProcessID, value: 0)
        event.setIntegerValueField(.eventTargetUnixProcessID, value: 1)
        inputs = []
        _ = ScrollCore.shared.scrollEventCallBack(CGEventTapProxy(bitPattern: 1)!, .scrollWheel, event, nil)
        XCTAssertEqual(inputs.count, 1, "one smoothed event")
        return try XCTUnwrap(inputs.last)
    }

    /// With the key held a click goes a fifth as far: a fast one, and a slow one that is
    /// under "Smallest step" and so goes the least distance, which is a fifth too. The
    /// glide is the same one.
    func testWithTheKeyHeld_aClickGoesAFifthAsFar() throws {
        let step = Options.shared.scroll.step
        let speed = Options.shared.scroll.speed
        for point in [-120.0, 120.0, -10.0, 3.0] {
            hold(faster: false, slower: false)
            let plain = try click(point: point)
            hold(faster: false, slower: true)
            XCTAssertTrue(ScrollCore.shared.slowScroll)
            let slow = try click(point: point)

            // The plain click, written out: at least one step, times the speed.
            let distance = max(step, abs(point)) * speed
            XCTAssertEqual(abs(plain.y), distance, accuracy: 1e-9, "\(point)")
            XCTAssertEqual(slow.y, plain.y / 5, accuracy: 1e-9, "\(point): a fifth, the same way")
            XCTAssertEqual(slow.notch, plain.notch / 5, accuracy: 1e-9, "\(point): the notch with it")
            XCTAssertEqual(slow.x, 0)
            XCTAssertEqual(slow.duration, plain.duration, "\(point): the same glide")
        }
        // A slow click moves one step × speed; with the key a fifth of that.
        hold(faster: false, slower: true)
        XCTAssertEqual(abs(try click(point: -10).y), step * speed / 5, accuracy: 1e-9)
    }

    /// "Scroll faster" and "Scroll slower" held together cancel: the plain distance, to the
    /// last bit. Each alone is five times and a fifth.
    func testBothKeysHeld_giveThePlainDistance() throws {
        let plain = try click(point: -120)
        hold(faster: true, slower: true)
        XCTAssertTrue(ScrollCore.shared.dashScroll)
        XCTAssertTrue(ScrollCore.shared.slowScroll)
        let both = try click(point: -120)
        XCTAssertEqual(both.y, plain.y)
        XCTAssertEqual(both.notch, plain.notch)

        hold(faster: true, slower: false)
        XCTAssertEqual(try click(point: -120).y, plain.y * 5, accuracy: 1e-9)
        hold(faster: false, slower: false)
        XCTAssertEqual(try click(point: -120).y, plain.y)

        XCTAssertEqual(ScrollCore.amplification(faster: false, slower: false), 1.0)
        XCTAssertEqual(ScrollCore.amplification(faster: true, slower: false), 5.0)
        XCTAssertEqual(ScrollCore.amplification(faster: false, slower: true), 0.2)
        XCTAssertEqual(ScrollCore.amplification(faster: true, slower: true), 1.0)
    }

    /// With no key recorded (as installed) nothing holds it: every button and key leaves
    /// the distance alone.
    func testWithoutAKey_nothingSlowsTheScroll() throws {
        Options.shared.scroll.slow = nil
        let plain = try click(point: -120)
        XCTAssertFalse(ScrollCore.shared.handleScrollHotkey(code: 51, isDown: true), "no key of Scrollio's")
        XCTAssertFalse(ScrollCore.shared.slowScroll)
        XCTAssertEqual(try click(point: -120).y, plain.y)
    }

    /// A modifier recorded as the key, through the hold-key tap: down while the modifier's
    /// flag is set, up when it is gone.
    func testAModifierAsTheKey_isHeldWhileItsFlagIsSet() throws {
        Options.shared.scroll.slow = ScrollHotkey(type: .keyboard, code: KeyCode.controlR)
        func flagsChanged(_ flags: CGEventFlags) throws {
            let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(KeyCode.controlR), keyDown: true))
            event.type = .flagsChanged
            event.flags = flags
            _ = ScrollCore.shared.hotkeyEventCallBack(CGEventTapProxy(bitPattern: 1)!, .flagsChanged, event, nil)
        }
        try flagsChanged(.maskControl)
        XCTAssertTrue(ScrollCore.shared.slowScroll)
        XCTAssertEqual(ScrollCore.shared.dashAmplification, 0.2)
        XCTAssertFalse(ScrollCore.shared.dashScroll, "not the \"Scroll faster\" key")
        try flagsChanged([])
        XCTAssertFalse(ScrollCore.shared.slowScroll)
        XCTAssertEqual(ScrollCore.shared.dashAmplification, 1.0)
    }

    /// A button that is the key is a scroll key to the rest of the app, as its neighbours
    /// are: the Buttons pane says so on a row of that button, and a Logitech button recorded
    /// for it (globally or for an app with its own settings) is one Scrollio asks the mouse
    /// for.
    func testTheButtonsPaneAndTheMouseKnowTheKey() {
        let pane = PreferencesButtonsViewController()
        XCTAssertTrue(pane.scrollHoldKeys().contains(ScrollHotkey(type: .mouse, code: 51)))
        let onTheKey = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 51, modifiers: 0, deviceFilter: nil), systemShortcutName: "copy"
        )
        XCTAssertEqual(
            ButtonRowNote.make(for: onTheKey, captureStatus: .normal, scrollHoldKeys: pane.scrollHoldKeys())?.kind, .alsoScrollKey
        )

        Options.shared.scroll.slow = ScrollHotkey(type: .mouse, code: 1006)
        XCTAssertEqual(LogiUsageBootstrap.globalScrollCodes(role: .slow), [1006])
        XCTAssertEqual(LogiUsageBootstrap.globalScrollCodes(role: .dash), [], "its own role, not another's")
        let app = Application(path: "/Applications/A.app")
        app.scroll.slow = ScrollHotkey(type: .mouse, code: 1008)
        XCTAssertEqual(LogiUsageBootstrap.appScrollCodes(app: app, role: .slow), [], "an app that follows Scrolling has none of its own")
        app.inherit = false
        XCTAssertEqual(LogiUsageBootstrap.appScrollCodes(app: app, role: .slow), [1008])
        XCTAssertEqual(ScrollUtils.shared.optionsSlowKey(application: app), ScrollHotkey(type: .mouse, code: 1008))
        XCTAssertEqual(ScrollUtils.shared.optionsSlowKey(application: nil), ScrollHotkey(type: .mouse, code: 1006))
    }

    /// The key is forgotten when the core stops (sleep, Pause: its release is never seen),
    /// and the action of a button ("Scroll Slower" in the Buttons pane) holds it too.
    func testTheKeyIsForgottenWhenTheCoreStops_andAButtonActionHoldsIt() {
        let core = ScrollCore()
        XCTAssertTrue(core.handleScrollHotkey(code: 51, isDown: true))
        XCTAssertEqual(core.dashAmplification, 0.2)
        core.isActive = true   // as after enable(); no event tap is created here
        core.disable()
        XCTAssertFalse(core.slowScroll)
        XCTAssertFalse(core.slowKeyHeld)
        XCTAssertEqual(core.dashAmplification, 1.0)
        XCTAssertFalse(core.handleScrollHotkey(code: 51, isDown: false), "the release after the wake finds nothing held")

        XCTAssertEqual(ScrollActionKind(shortcutIdentifier: "scrollSlow")?.role, .slow)
        core.handleScrollAction(role: .slow, isDown: true)
        XCTAssertTrue(core.slowScroll)
        XCTAssertEqual(core.dashAmplification, 0.2)
        core.handleScrollAction(role: .dash, isDown: true)
        XCTAssertEqual(core.dashAmplification, 1.0, "both held: they cancel")
        core.handleScrollAction(role: .dash, isDown: false)
        core.handleScrollAction(role: .slow, isDown: false)
        XCTAssertFalse(core.slowScroll)
        XCTAssertEqual(core.dashAmplification, 1.0)
    }
}

/// A hold key that is a modifier (⌥, ⇧, ⌘, ⌃) whose release is lost: another program
/// swallowed it (a window switcher, a key remapper) or secure keyboard entry hid it. The key
/// stayed "held" until it was pressed again: five times the distance, smoothing paused,
/// sideways. Each wheel event from the hardware carries the modifiers that are down: one the
/// event does not carry lets its key go, as the key's own release would. Wheel events go
/// through the scroll tap's callback, keys through the hold-key tap's; nothing is posted.
final class ScrollModifierHoldKeyLostReleaseTests: XCTestCase {

    private var inputs: [ScrollPosterInput] = []
    private var savedScroll: OPTIONS_SCROLL_DEFAULT!
    private var savedAllowlist = false
    private var savedApplication: Application?
    private var savedCurrentApplication: Application?

    override func setUp() {
        super.setUp()
        savedScroll = Options.shared.scroll
        savedAllowlist = Options.shared.application.allowlist
        savedApplication = ScrollCore.shared.application
        savedCurrentApplication = ScrollCore.shared.currentApplication
        // A new installation's settings: ⌥ faster, ⇧ sideways, ⌘ pauses smoothing.
        let scroll = OPTIONS_SCROLL_DEFAULT()
        scroll.reverse = false
        Options.shared.scroll = scroll
        Options.shared.application.allowlist = false
        ScrollCore.shared.settingsWereReplaced()   // nothing held
        ScrollCore.shared.application = nil
        ScrollCore.shared.currentApplication = nil
        ScrollCore.shared.handover = ScrollHandover()
        ScrollUtils.shared.treatAsRemoteForTests(sourcePID: nil)
        ScrollCore.shared.isKeyDown = { _ in false }   // the keyboard says every key is up
        inputs = []
        ScrollCore.posterInputObserverForTests = { [unowned self] input in self.inputs.append(input) }
    }

    override func tearDown() {
        ScrollCore.posterInputObserverForTests = nil
        ScrollCore.shared.settingsWereReplaced()
        ScrollCore.shared.handover = ScrollHandover()
        ScrollCore.shared.application = savedApplication
        ScrollCore.shared.currentApplication = savedCurrentApplication
        Options.shared.scroll = savedScroll
        Options.shared.application.allowlist = savedAllowlist
        ScrollUtils.shared.treatAsRemoteForTests(sourcePID: nil)
        ScrollCore.shared.isKeyDown = { _ in false }
        ScrollSystemLog.resetPassthroughForTests()
        super.tearDown()
    }

    /// The key's own flagsChanged (its press or its release), through the hold-key tap, from
    /// a keyboard (source pid 0) unless another process is named. (An event made here carries
    /// the test process's pid until it is set: a press another program posted.)
    private func flagsChanged(_ code: UInt16, _ flags: CGEventFlags, sourcePID: Int64 = 0) throws {
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: true))
        event.type = .flagsChanged
        event.flags = flags
        event.setIntegerValueField(.eventSourceUnixProcessID, value: sourcePID)
        _ = ScrollCore.shared.hotkeyEventCallBack(CGEventTapProxy(bitPattern: 1)!, .flagsChanged, event, nil)
    }

    /// A plain key's press or release, through the hold-key tap.
    private func key(_ code: UInt16, down: Bool) throws {
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: down))
        _ = ScrollCore.shared.hotkeyEventCallBack(CGEventTapProxy(bitPattern: 1)!, down ? .keyDown : .keyUp, event, nil)
    }

    /// One click of the main wheel down the page with these modifiers (sideways only: as macOS
    /// sends it with ⇧ down), aimed at no app (pid 1), from the hardware (source pid 0) unless
    /// another process is named, at its own time unless one is given. What the poster got, or
    /// nil when it was let through unsmoothed.
    private func click(_ flags: CGEventFlags, sideways: Bool = false, sourcePID: Int64 = 0,
                       at timestamp: CGEventTimestamp? = nil) throws -> ScrollPosterInput? {
        let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 0, wheel2: 0, wheel3: 0))
        event.setIntegerValueField(sideways ? .scrollWheelEventDeltaAxis2 : .scrollWheelEventDeltaAxis1, value: -1)
        event.setDoubleValueField(sideways ? .scrollWheelEventFixedPtDeltaAxis2 : .scrollWheelEventFixedPtDeltaAxis1, value: -1)
        event.setDoubleValueField(sideways ? .scrollWheelEventPointDeltaAxis2 : .scrollWheelEventPointDeltaAxis1, value: -120)
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 0)
        event.setIntegerValueField(.eventSourceUnixProcessID, value: sourcePID)
        event.setIntegerValueField(.eventTargetUnixProcessID, value: 1)
        event.flags = flags
        if let timestamp = timestamp { event.timestamp = timestamp }
        inputs = []
        _ = ScrollCore.shared.scrollEventCallBack(CGEventTapProxy(bitPattern: 1)!, .scrollWheel, event, nil)
        XCTAssertLessThanOrEqual(inputs.count, 1)
        return inputs.last
    }

    private func plainDistance() throws -> Double {
        return try XCTUnwrap(try click([])).y
    }

    /// The case of the report: ⌥ ("Scroll faster") is pressed, its release never comes. The
    /// wheel goes five times as far while its events carry ⌥, and the first one without ⌥
    /// lets the key go. A release that comes late changes nothing; the next press holds it.
    func testAHeldOptionWhoseReleaseNeverComes_isLetGoByTheFirstWheelEventWithoutIt() throws {
        let plain = try plainDistance()
        try flagsChanged(KeyCode.optionL, .maskAlternate)
        XCTAssertTrue(ScrollCore.shared.dashScroll)
        XCTAssertEqual(try XCTUnwrap(try click(.maskAlternate)).y, plain * 5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(try click([.maskAlternate, .maskNonCoalesced])).y, plain * 5, accuracy: 1e-9,
                       "held while the wheel carries ⌥, with whatever else")

        let after = try XCTUnwrap(try click(.maskNonCoalesced))
        XCTAssertEqual(after.y, plain, "not five times: ⌥ is up")
        XCTAssertEqual(after.notch, try XCTUnwrap(try click([])).notch)
        XCTAssertFalse(ScrollCore.shared.dashScroll)
        XCTAssertFalse(ScrollCore.shared.dashKeyHeld)
        XCTAssertEqual(ScrollCore.shared.dashAmplification, 1.0)

        try flagsChanged(KeyCode.optionL, [])
        XCTAssertFalse(ScrollCore.shared.dashScroll, "the late release finds it up")
        try flagsChanged(KeyCode.optionL, .maskAlternate)
        XCTAssertEqual(try XCTUnwrap(try click(.maskAlternate)).y, plain * 5, accuracy: 1e-9, "pressed again: held again")
        try flagsChanged(KeyCode.optionL, [])
        XCTAssertEqual(try plainDistance(), plain, "and its own release lets it go as before")
    }

    /// The other three the same way, each by its own modifier only: ⌘ (Pause smoothing),
    /// ⇧ (Scroll sideways) and a recorded ⌃ (Scroll slower). A wheel event that carries
    /// one of them lets only the others go.
    func testEachModifierHoldKey_isLetGoByItsOwnModifierOnly() throws {
        Options.shared.scroll.slow = ScrollHotkey(type: .keyboard, code: KeyCode.controlR)
        let plain = try plainDistance()
        try flagsChanged(KeyCode.commandL, .maskCommand)
        try flagsChanged(KeyCode.shiftL, [.maskCommand, .maskShift])
        try flagsChanged(KeyCode.controlR, [.maskCommand, .maskShift, .maskControl])
        XCTAssertTrue(ScrollCore.shared.blockSmooth)
        XCTAssertTrue(ScrollCore.shared.toggleScroll)
        XCTAssertTrue(ScrollCore.shared.slowScroll)
        XCTAssertNil(try click([.maskCommand, .maskShift, .maskControl]), "smoothing paused: let through")
        XCTAssertTrue(ScrollCore.shared.blockSmooth)
        XCTAssertTrue(ScrollCore.shared.toggleScroll)
        XCTAssertTrue(ScrollCore.shared.slowScroll)

        // ⌘'s release was lost.
        let shifted = try XCTUnwrap(try click([.maskShift, .maskControl]), "smoothed again")
        XCTAssertFalse(ScrollCore.shared.blockSmooth)
        XCTAssertTrue(ScrollCore.shared.toggleScroll)
        XCTAssertTrue(ScrollCore.shared.slowScroll)
        XCTAssertEqual(abs(shifted.y), abs(plain) / 5, accuracy: 1e-9)

        // ⌃'s and ⇧'s too.
        XCTAssertEqual(try XCTUnwrap(try click([])).y, plain)
        XCTAssertFalse(ScrollCore.shared.toggleScroll)
        XCTAssertFalse(ScrollCore.shared.slowScroll)
        XCTAssertEqual(ScrollCore.shared.dashAmplification, 1.0)
    }

    /// The side is the key's, as before: a right ⌥ is not held by the left one. Once held,
    /// the wheel's ⌥ keeps it (its side bits are not compared: the key's own state is asked,
    /// by its code), and a wheel event without ⌥ lets it go.
    func testTheSideOfTheKey_isAsBefore() throws {
        Options.shared.scroll.dash = ScrollHotkey(type: .keyboard, code: KeyCode.optionR)
        let plain = try plainDistance()
        try flagsChanged(KeyCode.optionL, .maskAlternate)
        XCTAssertFalse(ScrollCore.shared.dashScroll, "the left ⌥ is not the right one")
        XCTAssertEqual(try XCTUnwrap(try click(.maskAlternate)).y, plain)
        try flagsChanged(KeyCode.optionL, [])

        try flagsChanged(KeyCode.optionR, .maskAlternate)
        XCTAssertTrue(ScrollCore.shared.dashScroll)
        XCTAssertEqual(try XCTUnwrap(try click(.maskAlternate)).y, plain * 5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(try click([])).y, plain)
        XCTAssertFalse(ScrollCore.shared.dashScroll)
    }

    /// A mouse button and a plain key are not modifiers: the wheel's flags say nothing about
    /// them, and they stay held until their own release, as before.
    func testAButtonOrAPlainKey_isNotLetGoByTheWheel() throws {
        let plain = try plainDistance()
        Options.shared.scroll.dash = ScrollHotkey(type: .mouse, code: 50)
        XCTAssertTrue(ScrollCore.shared.handleScrollHotkey(code: 50, isDown: true))
        XCTAssertEqual(try XCTUnwrap(try click([])).y, plain * 5, accuracy: 1e-9)
        XCTAssertTrue(ScrollCore.shared.dashScroll, "a button: held")
        ScrollCore.shared.handleScrollHotkey(code: 50, isDown: false)
        XCTAssertFalse(ScrollCore.shared.dashScroll)

        let keyD: UInt16 = 2
        Options.shared.scroll.dash = ScrollHotkey(type: .keyboard, code: keyD)
        try key(keyD, down: true)
        XCTAssertTrue(ScrollCore.shared.dashScroll)
        XCTAssertEqual(try XCTUnwrap(try click([])).y, plain * 5, accuracy: 1e-9)
        XCTAssertTrue(ScrollCore.shared.dashScroll, "a plain key: held")
        try key(keyD, down: false)
        XCTAssertFalse(ScrollCore.shared.dashScroll)
    }

    /// A wheel event another program posted carries the flags that program gave it, which say
    /// nothing about the keyboard: it lets no key go.
    func testAWheelEventFromAnotherProgram_letsNoKeyGo() throws {
        let plain = try plainDistance()
        try flagsChanged(KeyCode.optionL, .maskAlternate)
        let pid = Int64(ProcessInfo.processInfo.processIdentifier)
        XCTAssertEqual(try XCTUnwrap(try click([], sourcePID: pid)).y, plain * 5, accuracy: 1e-9)
        XCTAssertTrue(ScrollCore.shared.dashScroll)
        XCTAssertEqual(try XCTUnwrap(try click([])).y, plain, "the hardware's says ⌥ is up")
    }

    /// fn is left as it was: it holds the key until its own release.
    func testFn_isLeftToItsOwnRelease() throws {
        Options.shared.scroll.slow = ScrollHotkey(type: .keyboard, code: KeyCode.fnL)
        let plain = try plainDistance()
        try flagsChanged(KeyCode.fnL, .maskSecondaryFn)
        XCTAssertTrue(ScrollCore.shared.slowScroll)
        XCTAssertEqual(try XCTUnwrap(try click([])).y, plain / 5, accuracy: 1e-9)
        XCTAssertTrue(ScrollCore.shared.slowScroll)
        try flagsChanged(KeyCode.fnL, [])
        XCTAssertFalse(ScrollCore.shared.slowScroll)
    }

    /// A button that holds the key after ⌥ did is not let go by a wheel event without ⌥:
    /// after the keys were forgotten (the core stopped, the settings were replaced), and when
    /// the button is pressed while ⌥ still holds it (an app with its own keys came to the front).
    func testAButtonThatHoldsTheKeyAfterAModifier_isNotLetGoByTheWheel() throws {
        let plain = try plainDistance()
        try flagsChanged(KeyCode.optionL, .maskAlternate)
        ScrollCore.shared.settingsWereReplaced()
        Options.shared.scroll.dash = ScrollHotkey(type: .mouse, code: 50)
        XCTAssertTrue(ScrollCore.shared.handleScrollHotkey(code: 50, isDown: true))
        XCTAssertEqual(try XCTUnwrap(try click([])).y, plain * 5, accuracy: 1e-9)
        XCTAssertTrue(ScrollCore.shared.dashScroll, "forgotten keys left nothing behind")
        ScrollCore.shared.handleScrollHotkey(code: 50, isDown: false)
        XCTAssertFalse(ScrollCore.shared.dashScroll)

        Options.shared.scroll.dash = ScrollHotkey(type: .keyboard, code: KeyCode.optionL)
        try flagsChanged(KeyCode.optionL, .maskAlternate)
        Options.shared.scroll.dash = ScrollHotkey(type: .mouse, code: 50)
        XCTAssertTrue(ScrollCore.shared.handleScrollHotkey(code: 50, isDown: true))
        XCTAssertEqual(try XCTUnwrap(try click([])).y, plain * 5, accuracy: 1e-9)
        XCTAssertTrue(ScrollCore.shared.dashScroll, "the button holds it now")
        ScrollCore.shared.handleScrollHotkey(code: 50, isDown: false)
        XCTAssertFalse(ScrollCore.shared.dashScroll)
    }

    /// A ⌥ another program posted (a button its driver maps to ⌥, a Hyper key, a keyboard
    /// shared over the network): the hardware's wheel events need not carry it, so the wheel
    /// does not let it go. It waits for that program's release, as in 1.1.0.
    func testAModifierAnotherProgramPressed_waitsForItsOwnRelease() throws {
        let plain = try plainDistance()
        try flagsChanged(KeyCode.optionL, .maskAlternate, sourcePID: 4242)
        XCTAssertTrue(ScrollCore.shared.dashScroll)
        XCTAssertEqual(try XCTUnwrap(try click([])).y, plain * 5, accuracy: 1e-9, "held: the wheel's flags say nothing of it")
        XCTAssertTrue(ScrollCore.shared.dashScroll)
        try flagsChanged(KeyCode.optionL, [], sourcePID: 4242)
        XCTAssertEqual(try plainDistance(), plain, "its own release lets it go")

        try flagsChanged(KeyCode.optionL, .maskAlternate)
        XCTAssertEqual(try plainDistance(), plain, "pressed on the keyboard: watched by the wheel again")
    }

    /// Two ⌥ keys, one for each: "Scroll faster" on the left one, "Scroll slower" on the
    /// right. Letting go of one while the other is down is its release: the event still has
    /// ⌥ (the other key's) but not the side bit of the key let go. (A bug since before 1.1.0:
    /// the key stayed held until the other one was let go too.) Events without side bits
    /// (posted ones may have none) are judged by ⌥ alone, as before.
    func testLettingGoOfOneSideWhileTheOtherIsDown_isItsRelease() throws {
        Options.shared.scroll.slow = ScrollHotkey(type: .keyboard, code: KeyCode.optionR)
        let plain = try plainDistance()
        let left = CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | 0x20)
        let right = CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | 0x40)
        let both = CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | 0x20 | 0x40)

        try flagsChanged(KeyCode.optionL, left)
        try flagsChanged(KeyCode.optionR, both)
        XCTAssertTrue(ScrollCore.shared.dashScroll)
        XCTAssertTrue(ScrollCore.shared.slowScroll)
        XCTAssertEqual(ScrollCore.shared.dashAmplification, 1.0, "both held: they cancel")
        try flagsChanged(KeyCode.optionR, left)
        XCTAssertFalse(ScrollCore.shared.slowScroll, "the right ⌥ is up")
        XCTAssertTrue(ScrollCore.shared.dashScroll, "the left one is still down")
        XCTAssertEqual(try XCTUnwrap(try click(left)).y, plain * 5, accuracy: 1e-9)

        try flagsChanged(KeyCode.optionR, both)
        try flagsChanged(KeyCode.optionL, right)
        XCTAssertFalse(ScrollCore.shared.dashScroll, "the left ⌥ is up")
        XCTAssertTrue(ScrollCore.shared.slowScroll, "the right one is still down")
        try flagsChanged(KeyCode.optionR, [])
        XCTAssertFalse(ScrollCore.shared.slowScroll)

        try flagsChanged(KeyCode.optionL, .maskAlternate)
        XCTAssertTrue(ScrollCore.shared.dashScroll, "no side bits: ⌥ alone says pressed")
        try flagsChanged(KeyCode.optionL, [])
        XCTAssertFalse(ScrollCore.shared.dashScroll)
    }

    /// ⇧ is "Scroll sideways" as installed. While ⇧ is down macOS sends the main wheel's turns
    /// sideways only and keeps ⇧ in their flags: such an event does not let ⇧ go.
    func testShiftWithTheWheel_isNotLetGo() throws {
        try flagsChanged(KeyCode.shiftL, .maskShift)
        XCTAssertTrue(ScrollCore.shared.toggleScroll)
        let input = try XCTUnwrap(try click(.maskShift, sideways: true))
        XCTAssertNotEqual(input.x, 0)
        XCTAssertTrue(ScrollCore.shared.toggleKeyHeld, "the event carries ⇧")
        XCTAssertTrue(ScrollCore.shared.toggleScroll)
        try flagsChanged(KeyCode.shiftL, [])
        XCTAssertFalse(ScrollCore.shared.toggleScroll)
    }

    /// Something took ⌥ off the wheel's flags while the key is down (a shortcut Scrollio
    /// posted carries only its own modifiers; a tap ahead of Scrollio's may take it off). The
    /// keyboard is asked, by the key's own code, before the key is let go: still down, it
    /// stays held. One answer serves every event with the same flags for a second, so a spin
    /// does not ask per event; other flags, a later event or a new press ask again.
    func testAKeyTheKeyboardSaysIsStillDown_isKept_andAskedOncePerFlags() throws {
        var asked: [UInt16] = []
        var down = true
        ScrollCore.shared.isKeyDown = { code in asked.append(code); return down }
        let plain = try plainDistance()
        XCTAssertEqual(asked, [], "nothing held: nothing asked")
        try flagsChanged(KeyCode.optionL, .maskAlternate)
        let second: CGEventTimestamp = 1_000_000_000
        let t0: CGEventTimestamp = 50 * second

        XCTAssertEqual(try XCTUnwrap(try click([], at: t0)).y, plain * 5, accuracy: 1e-9, "⌥ is still down")
        XCTAssertEqual(try XCTUnwrap(try click([], at: t0 + second / 2)).y, plain * 5, accuracy: 1e-9)
        XCTAssertEqual(asked, [KeyCode.optionL], "asked once for these flags, by the key's code")
        XCTAssertEqual(try XCTUnwrap(try click(.maskAlternate, at: t0 + second / 2)).y, plain * 5, accuracy: 1e-9)
        XCTAssertEqual(asked.count, 1, "the wheel carries ⌥: nothing asked")
        XCTAssertEqual(try XCTUnwrap(try click(.maskNonCoalesced, at: t0 + second / 2)).y, plain * 5, accuracy: 1e-9)
        XCTAssertEqual(asked.count, 2, "other flags: asked again")

        down = false   // its release is lost now
        XCTAssertEqual(try XCTUnwrap(try click(.maskNonCoalesced, at: t0 + second * 6 / 10)).y, plain * 5, accuracy: 1e-9,
                       "the answer of a moment ago holds")
        XCTAssertEqual(asked.count, 2)
        XCTAssertEqual(try XCTUnwrap(try click(.maskNonCoalesced, at: t0 + second * 16 / 10)).y, plain,
                       "a second later the keyboard is asked again: up, let go")
        XCTAssertEqual(asked.count, 3)
        XCTAssertFalse(ScrollCore.shared.dashScroll)
        XCTAssertFalse(ScrollCore.shared.dashKeyHeld)

        // A new press forgets the answer.
        down = true
        try flagsChanged(KeyCode.optionL, .maskAlternate)
        XCTAssertEqual(try XCTUnwrap(try click([], at: t0 + second * 2)).y, plain * 5, accuracy: 1e-9)
        XCTAssertEqual(asked.count, 4)
        try flagsChanged(KeyCode.optionL, [])
        down = false
        try flagsChanged(KeyCode.optionL, .maskAlternate)
        XCTAssertEqual(try XCTUnwrap(try click([], at: t0 + second * 2)).y, plain, "pressed again: asked again, up")
        XCTAssertEqual(asked.count, 5)
    }

    /// Two keys held on different modifiers: the keyboard is asked about each key whose
    /// modifier the wheel lacks, by its own code, and only the one that is up is let go.
    func testOnlyTheKeyTheKeyboardSaysIsUp_isLetGo() throws {
        var asked: [UInt16] = []
        ScrollCore.shared.isKeyDown = { code in asked.append(code); return code == KeyCode.commandL }
        let plain = try plainDistance()
        try flagsChanged(KeyCode.optionL, .maskAlternate)
        try flagsChanged(KeyCode.commandL, [.maskAlternate, .maskCommand])
        XCTAssertTrue(ScrollCore.shared.dashScroll)
        XCTAssertTrue(ScrollCore.shared.blockSmooth)
        XCTAssertNil(try click([]), "⌘ is still down: smoothing stays paused")
        XCTAssertEqual(Set(asked), [KeyCode.optionL, KeyCode.commandL])
        XCTAssertFalse(ScrollCore.shared.dashScroll, "⌥ is up: let go")
        XCTAssertTrue(ScrollCore.shared.blockSmooth)
        try flagsChanged(KeyCode.commandL, [])
        XCTAssertEqual(try XCTUnwrap(try click([])).y, plain)
    }

    /// The log line says which key, that it was pressed on a keyboard (a key another program
    /// pressed is never let go by the wheel) and how long it was held; no app names.
    func testTheLetGoLine_saysTheKeyWhereItWasPressedAndHowLongItWasHeld() {
        let line = ScrollCore.lostReleaseLine(of: "Scroll faster", heldFor: 2.46)
        XCTAssertTrue(line.contains("\"Scroll faster\""), line)
        XCTAssertTrue(line.contains("pressed on a keyboard"), line)
        XCTAssertTrue(line.contains("held 2.5 s"), line)
        XCTAssertTrue(ScrollCore.lostReleaseLine(of: "Pause smoothing", heldFor: -1).contains("held 0.0 s"))
    }
}
