//
//  InputProcessor.swift
//  Mos
//  统一事件处理器 - 接收 InputEvent, 匹配 ButtonBinding, 执行动作
//  Created by Mos on 2026/3/16.
//  Copyright © 2026 Caldis. All rights reserved.
//

import Carbon.HIToolbox
import Cocoa

// MARK: - InputResult
/// 事件处理结果
enum InputResult: Equatable {
    case consumed     // 事件已处理,不再传递
    case passthrough  // 事件未匹配,继续传递
}

// MARK: - InputProcessor
/// 统一事件处理器
/// 从 ButtonUtils 获取绑定配置, 匹配 InputEvent, 执行 ShortcutExecutor
/// 使用 activeBindings 表跟踪按下中的绑定, 确保 Up 事件正确配对
class InputProcessor: ModifierFlagsProviding {
    static let shared = InputProcessor()
    init() {
        observeSurroundings()
        // The first look at the screens: a later "the screens changed" is compared with it.
        lastScreenFrames = screenFrames()
        // Both swipes of the desktops (a hold's and the thumb wheel's) end through the one
        // synthesizer: when macOS reports the change of the desktop late, it is known for
        // Scrollio's own (`surroundingsChanged`).
        DockSwipeSynthesizer.shared.desktopsSwipeDidEnd = { [weak self] in
            self?.desktopsSwipeEnded()
        }
    }

    private static let scrollActionTapReplayMovementTolerance: CGFloat = 8.0
    /// A gesture hold older than this is abandoned, in case its button-up was lost. The same
    /// limit as the pointer lock and the "follow the hand" session use.
    static let mouseGestureHoldTimeout: TimeInterval = MouseGesturePointerLock.safetyTimeout
    /// Tests shorten the hold timeout to see the watchdog fire for real.
    private var mouseGestureHoldTimeoutOverride: TimeInterval?

    // MARK: - Active Bindings Table
    /// 跟踪当前按下中的 stateful 动作, 用于 Up 事件配对
    private var activeBindings: [TriggerKey: ActiveBindingSession] = [:]
    /// 按住中的手势导航按键, 每个按键一次按住对应一个识别器
    private var activeMouseGestures: [TriggerKey: ActiveMouseGestureSession] = [:]
    /// Native mouse buttons whose press ran a trigger action and was swallowed: their
    /// button-up is swallowed too, so the app under the pointer never gets an up without its
    /// down. A new press of the button or `clearActiveBindings` forgets the entry.
    private var swallowedTriggerPresses: Set<TriggerKey> = []
    /// Whose bindings a key's press went by (`ButtonUtils.scopeOfPress`), for that key's
    /// auto-repeats: a repeat belongs to its press, whatever app the press brought to the
    /// front (an app's own ⌘Q that hides it must not let the repeats quit the next app).
    /// Set at a key's first down; its up and `clearActiveBindings` forget it.
    private var keyPressScopes: [TriggerKey: ButtonBindingScope] = [:]

    var hasActiveMouseGestureSessions: Bool {
        return !activeMouseGestures.isEmpty
    }

    // MARK: - Shortcut Ring
    //
    // The ring's trigger is a binding like Gesture Navigation's: `process` hands its press
    // and its release to `ShortcutRingController`, which exists only once such a press has
    // come. Everyone else pays, per button or key event, a look at an empty set (and for
    // Esc a comparison of the controller with nil); nothing per wheel event; and per
    // pointer event one comparison with nil, only while the pointer-movement tap runs at
    // all (a gesture hold, a synthetic drag, a held modifier).

    /// The trigger whose press the ring took and whose release ends the hold.
    private var ringTrigger: TriggerKey?
    /// Every ring trigger that is down: `ringTrigger`, and a second one that was pressed
    /// while the first held the ring (it means nothing). Until its release every further
    /// down of such a trigger is swallowed: a held key repeats, and its repeats no longer
    /// match the binding once the modifiers are let go.
    private var heldRingTriggers: Set<TriggerKey> = []

    /// A ring is held open: the pointer-movement tap runs and its deltas go to the ring.
    var hasHeldShortcutRing: Bool {
        return ShortcutRingController.existing?.isHeld ?? false
    }

    /// One motion event of the pointer-movement tap, for everything that reads the hand
    /// while something is held: the gesture holds and a Shortcut Ring that is held open.
    /// `location` is the event's pointer location before the pointer lock rewrites it.
    /// Runs inside the motion tap's callback; nothing is posted from here.
    ///
    /// The pointer freeze can add a false delta when it has to warp the pointer back. The
    /// compensation keeps state, so it runs exactly once per motion event, here, and every
    /// reader gets its result. (Unchanged while nothing keeps the pointer still.)
    func handlePointerMovement(deltaX: CGFloat, deltaY: CGFloat, location: CGPoint) {
        let ringIsHeld = hasHeldShortcutRing
        guard pointerTrackedGestureCount > 0 || ringIsHeld else { return }
        let delta = MouseGesturePointerLock.shared.physicalDelta(CGPoint(x: deltaX, y: deltaY), at: location)
        handleMouseGestureMovement(deltaX: delta.x, deltaY: delta.y)
        if ringIsHeld {
            handleShortcutRingMovement(deltaX: delta.x, deltaY: delta.y, location: location)
        }
    }

    /// Hands the movement of one motion event to a ring that is held open: the hand's
    /// movement (`handlePointerMovement`) and where the event says the pointer is.
    func handleShortcutRingMovement(deltaX: CGFloat, deltaY: CGFloat, location: CGPoint) {
        guard let ring = ShortcutRingController.existing, ring.isHeld else { return }
        ring.pointerMoved(by: CGPoint(x: deltaX, y: deltaY), to: location)
    }

    /// The release of a ring trigger, or of Esc after it closed a ring.
    private func releaseForShortcutRing(_ event: InputEvent) -> Bool {
        if !heldRingTriggers.isEmpty {
            let key = TriggerKey(type: event.type, code: event.code)
            if heldRingTriggers.remove(key) != nil {
                if ringTrigger == key {
                    ringTrigger = nil
                    ShortcutRingController.existing?.triggerReleased(isMadeUp: event.isSyntheticRelease)
                }
                return true
            }
        }
        if event.type == .keyboard, event.code == KeyCode.escape,
           let ring = ShortcutRingController.existing, ring.escapeReleased() {
            return true
        }
        return false
    }

    /// A down that is the ring's before any binding is looked at: a held trigger again,
    /// or Esc while a ring is open or until the Esc that closed one is up.
    private func pressForOpenShortcutRing(_ event: InputEvent, key: TriggerKey) -> Bool {
        if !heldRingTriggers.isEmpty, heldRingTriggers.contains(key) {
            // A repeat of a held key, or a second down of the button that holds the ring.
            if event.isAutoRepeat || (ringTrigger == key && ShortcutRingController.existing?.isHeld == true) {
                return true
            }
            // A new press while the last one's release never came: it starts over.
            heldRingTriggers.remove(key)
            if ringTrigger == key {
                ringTrigger = nil
            }
        }
        if event.type == .keyboard, event.code == KeyCode.escape, let ring = ShortcutRingController.existing {
            // The Esc that closed the ring is the ring's until it is up, its repeats
            // included: held a moment longer, it would reach the app in front after all.
            // A fresh Esc down while its release is still awaited means that release was
            // lost: the wait ends and this press is the app's.
            if ring.awaitsEscapeRelease {
                if event.isAutoRepeat { return true }
                _ = ring.escapeReleased()
                return false
            }
            if ring.isOpen, !event.isAutoRepeat {
                return ring.escapePressed()
            }
        }
        return false
    }

    /// The press of a button or key bound to the Shortcut Ring.
    private func pressShortcutRingTrigger(_ event: InputEvent, key: TriggerKey) {
        heldRingTriggers.insert(key)
        if let held = ringTrigger, held != key, ShortcutRingController.existing?.isHeld == true {
            // A second trigger while the first really holds a ring: its press, its repeats
            // and its release are taken and mean nothing.
            return
        }
        // (After a release that never came, the other trigger opens a ring like any press.)
        ringTrigger = key
        // A view of the Dock that is opening with the hand goes back before the ring comes:
        // the ring's places may ask the Dock for a view themselves.
        takeBackSwipe(onlyTowardsAView: true, because: .ringOpened)
        ShortcutRingController.shared.triggerPressed(by: event)
    }

    /// Held gesture buttons that read pointer movement, the only ones that need the motion
    /// tap. A hold the mouse tracks itself gets its movement from `handleDeviceGestureMovement`.
    private var pointerTrackedGestureCount = 0

    var hasPointerTrackedMouseGestureSessions: Bool {
        return pointerTrackedGestureCount > 0
    }

    private struct TriggerKey: Hashable {
        let type: EventType
        let code: UInt16
    }

    private struct ActiveBindingSession {
        let action: ResolvedAction
        let mouseSessionID: UUID?
        var scrollActionTapReplay: ScrollActionTapReplay?
        /// What holds the action on the hardware, for the watchdog of held actions; nil for
        /// a trigger the Mac cannot be asked about (a Logitech button that arrives over
        /// HID++).
        var physicalHold: PhysicalHold?
    }

    private final class ActiveMouseGestureSession {
        /// Snapshot at button-down, so editing settings mid-hold cannot mix two configurations,
        /// and a change of the app in front cannot either: the general settings, or those
        /// with the own set of the app in front at the press (`MouseGestureChoice`).
        let settings: MouseGestureSettings
        /// The set is the own one of the app in front (for the log, which never names an app).
        let isAppsOwn: Bool
        /// Fixed for the whole hold: movement from the other source never reaches it.
        let movementSource: MouseGestureMovementSource
        /// The button to name when asking for a haptic cue: set for buttons that arrive
        /// over HID++ while haptic feedback is on, nil otherwise.
        let hapticCode: UInt16?
        var recognizer = MouseGestureRecognizer()
        /// Set in "follow the hand" mode; the recognizer above is then unused.
        var interactive: InteractiveGestureSession?
        /// "Up and Down follow the hand too": what Up and Down do in this hold, decided
        /// with `interactive` when the hold's settings have the switch on; nil: as before.
        var follow: DockFollowHold?
        /// The swipe this hold began, by its number (`DockSwipeSynthesizer.swipeNumber`);
        /// 0 until it began one. A swipe that is no longer the one running gets nothing
        /// more from this hold: it was taken back, and another may run by now.
        var swipeNumber = 0
        /// The motion this hold drives up or down, in numbers, for its line in the log.
        var followed: DockFollowedMotion?
        /// Gives up on the hold when its button-up never arrives.
        var watchdog: DispatchWorkItem?
        /// The watchdog gave up on this hold. It stays in the table, so a late button-up is
        /// still swallowed, but it reads no movement and the next press starts over.
        var isAbandoned = false

        init(
            settings: MouseGestureSettings, isAppsOwn: Bool, movementSource: MouseGestureMovementSource, hapticCode: UInt16?
        ) {
            self.settings = settings
            self.isAppsOwn = isAppsOwn
            self.movementSource = movementSource
            self.hapticCode = hapticCode
        }

        /// The pointer is only frozen for holds that read it: a mouse that tracks the hold
        /// itself already keeps the pointer still.
        var freezesPointer: Bool {
            return settings.freezePointer && movementSource == .pointer
        }
    }

    // MARK: - Interactive Gesture State
    /// The hold that drives the interactive swipe. Only one swipe can run at a time, so a
    /// second gesture button pressed meanwhile behaves like the discrete mode. (Nil again
    /// once the hold's swipe was taken back or could not begin, while its button is still
    /// down: that hold reads no more movement.)
    private var interactiveGestureKey: TriggerKey?
    /// Movement source of that hold (kept apart so the motion tap callback needs no lookup).
    private var interactiveGestureSource = MouseGestureMovementSource.pointer
    /// Movement received in the motion tap callback and not yet handed to the session.
    private var pendingInteractiveDelta = CGPoint.zero
    private var isInteractiveFlushScheduled = false
    /// Invalidates a scheduled flush that is no longer wanted.
    private var interactiveFlushToken = 0
    private var lastInteractiveFlushTime = -TimeInterval.infinity
    private var interactiveFrameDuration = InteractiveGestureEnvironment.fallbackScreen.frameDuration
    /// Counts the swipes begun and the stops that take every swipe back (Scrollio stops,
    /// the screens change, the displays sleep). A release hands its swipe events to the
    /// next turn of the main queue with the number of that moment: once it has changed,
    /// they are not sent. So a terminal event queued for one swipe can never end a later
    /// one, and a whole flick (begin, update, end in one turn) does not go out after a stop.
    private var interactiveSwipeGeneration = 0
    /// The same for what stops only a motion towards a view and leaves the desktops' swipe
    /// alone (the Shortcut Ring opens, the desktop in use changes, the Dock is asked for a
    /// view in one go): the queued events of a motion up or down are not sent after it,
    /// while a swipe of the desktops still gets its end.
    private var viewSwipeGeneration = 0
    private var interactiveEnvironment = InteractiveGestureEnvironment.system
    /// Plays a haptic cue on the mouse a button belongs to. Replaced in tests.
    private var gestureHapticPlayer: (MouseGestureHapticCue, UInt16) -> Void = InputProcessor.systemGestureHapticPlayer

    private static let systemGestureHapticPlayer: (MouseGestureHapticCue, UInt16) -> Void = { cue, code in
        LogiCenter.shared.playGestureHaptic(cue, forScrollioCode: code)
    }
    /// Writes the line of a gesture's action (`mouseGestureRunLine`). Replaced in tests.
    private var mouseGestureLog: (String) -> Void = { AppSystemLog.note($0) }
    /// Whether a view of the Dock follows the hand on this Mac now, asked once per hold
    /// whose settings have "Up and Down follow the hand too" on. Replaced in tests.
    private var followAvailability: () -> DockFollowAvailability = { .live }
    /// The view of the Dock Scrollio believes it put up itself (`DockBelief`). Main thread.
    private var dockBelief = DockBelief()
    /// The frames of the screens, in points. Replaced in tests.
    private var screenFrames: () -> [CGRect] = InputProcessor.systemScreenFrames
    private static let systemScreenFrames: () -> [CGRect] = { NSScreen.screens.map(\.frame) }
    /// The screens' frames when they were last looked at (`screensReallyChanged`).
    private var lastScreenFrames: [CGRect] = []
    /// When Scrollio's own swipe of the desktops last ended (a hold's or the thumb wheel's),
    /// on the gestures' clock: macOS tells of the change of the desktop after it, late.
    private var desktopsSwipeEndedAt = -TimeInterval.infinity
    /// The app in front when a gesture button goes down: whose gestures the hold runs
    /// (`MouseGestureChoice`). Read once per hold, inside the event callback: what
    /// `NSWorkspace` and the running app already hold, as for the ring's press, and then
    /// two lookups in the per-app list; nothing on disk. Replaced in tests.
    private var mouseGestureFrontApplication: () -> ShortcutRingChoice.FrontApp? = { .current() }

    private struct ScrollActionTapReplay {
        let context: MouseTapReplayContext
        /// 仅 CG 鼠标事件设置。HID++/Logi 按键不可靠更新 NSEvent.pressedMouseButtons,
        /// 不能用 AppKit 的物理按钮位图做兜底释放判断。
        let releaseCheckButtonNumber: Int64?
        var didScroll = false
    }

    // MARK: - The keyboard

    /// Whether ButtonCore needs to see the keyboard at all (its keys tap exists only then):
    /// an enabled binding is triggered by a key, a button holds a modifier that the keys
    /// typed meanwhile must carry, or an action started by a key is still held (its key-up
    /// must arrive even when its binding was removed or switched off meanwhile).
    var needsKeyEvents: Bool {
        if activeModifierFlags != 0 { return true }
        if activeBindings.keys.contains(where: { $0.type == .keyboard }) { return true }
        // Esc closes an open Shortcut Ring, whatever opened it; and a key that opened one
        // is the ring's until it is up.
        if ShortcutRingController.existing?.needsKeys == true { return true }
        if heldRingTriggers.contains(where: { $0.type == .keyboard }) { return true }
        return ButtonUtils.shared.hasKeyboardTriggers
    }

    // MARK: - Held actions whose release never came
    //
    // A held action (a modifier, a mouse button, a held key, a scroll hold) ends with the
    // release of its trigger. That release can get lost: a password field or Terminal's
    // "Secure Keyboard Entry" starts while the bound key is down (no tap gets its key-up),
    // or a button-up goes missing. The action then stayed held, and with a held modifier
    // every key typed afterwards carried it, until the trigger was pressed again. Only
    // gesture holds had a watchdog. While actions are held, a timer compares them with the
    // hardware once a second and releases one whose trigger is up at two looks in a row
    // (a real release arrives within milliseconds, long before the second look).
    //
    // - A native mouse button: up when macOS says no such button is pressed (the check the
    //   scroll holds already use when the wheel turns).
    // - A key: only while another app has secure keyboard entry on, since only then can its
    //   key-up not arrive; up when macOS says the key is up (the state of the keyboards and
    //   of the keys other programs post, so a key another program holds counts as held).
    // In both cases "up" needs every way of asking to agree (`HeldInputProbe.system`).

    /// What holds an action on the hardware.
    enum PhysicalHold: Equatable {
        case mouseButton(Int64)
        case key(UInt16)
    }

    /// The hardware as the watchdog asks it. Replaced in tests.
    struct HeldInputProbe {
        var isMouseButtonDown: (Int64) -> Bool
        var isKeyDown: (UInt16) -> Bool
        var isSecureInputOn: () -> Bool

        /// "Up" only when every way of asking says so (AppKit, the session's state with
        /// what other programs post, the hardware alone): a hold is never released on one
        /// source's word. A button number macOS has no state for counts as down.
        static let system = HeldInputProbe(
            isMouseButtonDown: { number in
                guard number >= 0, number < 32, let button = CGMouseButton(rawValue: UInt32(number)) else { return true }
                return InputProcessor.isMouseButtonPressed(number)
                    || CGEventSource.buttonState(.combinedSessionState, button: button)
                    || CGEventSource.buttonState(.hidSystemState, button: button)
            },
            isKeyDown: { code in
                return CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(code))
                    || CGEventSource.keyState(.hidSystemState, key: CGKeyCode(code))
            },
            isSecureInputOn: { IsSecureEventInputEnabled() }
        )
    }

    static let heldActionCheckInterval: TimeInterval = 1.0

    /// nil under XCTest: no timer runs and nothing asks the real hardware; a test sets a
    /// probe and calls `checkHeldActions()` itself.
    private var heldInputProbe: HeldInputProbe? = AppRuntime.isRunningXCTest ? nil : .system
    private var heldActionTimer: Timer?
    /// Held actions whose trigger was up at the last look.
    private var suspectedLostReleases: Set<TriggerKey> = []

    /// Whether a hold lost its release, as far as the hardware can tell. Pure.
    static func hasLostItsRelease(_ hold: PhysicalHold, probe: HeldInputProbe) -> Bool {
        switch hold {
        case .mouseButton(let number):
            return !probe.isMouseButtonDown(number)
        case .key(let code):
            return probe.isSecureInputOn() && !probe.isKeyDown(code)
        }
    }

    private static func physicalHold(of event: InputEvent) -> PhysicalHold? {
        guard case .cgEvent = event.source else { return nil }
        switch event.type {
        case .mouse: return .mouseButton(Int64(event.code))
        case .keyboard: return .key(event.code)
        }
    }

    /// The timer runs exactly while some held action can be compared with the hardware.
    private func updateHeldActionTimer() {
        let needed = heldInputProbe != nil && activeBindings.values.contains { $0.physicalHold != nil }
        if needed {
            guard heldActionTimer == nil else { return }
            heldActionTimer = CommonModesTimer.scheduled(
                withTimeInterval: Self.heldActionCheckInterval, repeats: true
            ) { [weak self] _ in
                self?.checkHeldActions()
            }
        } else {
            heldActionTimer?.invalidate()
            heldActionTimer = nil
            suspectedLostReleases.removeAll()
        }
    }

    /// One look of the watchdog.
    func checkHeldActions() {
        assertMainThread()
        guard let probe = heldInputProbe else { return }
        var stillSuspected: Set<TriggerKey> = []
        var lost: [TriggerKey] = []
        for (key, session) in activeBindings {
            guard let hold = session.physicalHold, Self.hasLostItsRelease(hold, probe: probe) else { continue }
            if suspectedLostReleases.contains(key) {
                lost.append(key)
            } else {
                stillSuspected.insert(key)
            }
        }
        suspectedLostReleases = stillSuspected
        guard !lost.isEmpty else { return }
        for key in lost {
            guard let session = activeBindings.removeValue(forKey: key) else { continue }
            ShortcutExecutor.shared.execute(
                action: session.action,
                phase: .up,
                mouseSessionID: session.mouseSessionID
            )
            // A button-up that arrives after all belongs to the swallowed press.
            if key.type == .mouse {
                swallowedTriggerPresses.insert(key)
            }
        }
        AppSystemLog.problem("InputProcessor: released \(lost.count) held action\(lost.count == 1 ? "" : "s") "
            + "whose button or key is up (its release never came)")
        recomputeActiveModifierFlags()
    }

    /// 清空所有活跃绑定和虚拟修饰键状态 (ButtonCore disable 时调用, 防止状态残留)
    func clearActiveBindings() {
        assertMainThread()
        for session in activeBindings.values where session.action.executionMode == .stateful {
            ShortcutExecutor.shared.execute(
                action: session.action,
                phase: .up,
                mouseSessionID: session.mouseSessionID
            )
        }
        activeBindings.removeAll()
        swallowedTriggerPresses.removeAll()
        keyPressScopes.removeAll()
        // An open Shortcut Ring closes and runs nothing. A key that holds it stays the
        // ring's until it is up: its repeats match no binding once the modifiers are let
        // go, and would be typed into the document. (A button's release may pass, as a
        // gesture button's does.)
        heldRingTriggers = heldRingTriggers.filter { $0.type == .keyboard }
        if let held = ringTrigger, held.type != .keyboard {
            ringTrigger = nil
        }
        ShortcutRingController.existing?.cancel()
        cancelInteractiveGesture()
        // Scrollio stops looking (sleep, Pause, another user, an event tap that started
        // over): what it believed the Dock shows is not known any more.
        dockBelief.drop()
        for session in activeMouseGestures.values {
            session.watchdog?.cancel()
        }
        activeMouseGestures.removeAll()
        pointerTrackedGestureCount = 0
        MouseGesturePointerLock.shared.unlock()
        activeModifierFlags = 0
        MouseInteractionSessionController.shared.clearAllSessions()
        MouseInteractionSessionController.shared.refreshMotionTapState()
        updateHeldActionTimer()
        ButtonCore.shared.keyTap.refresh()
    }

    // MARK: - Virtual Modifier Flags
    /// 当前激活的虚拟修饰键 flags (从 activeBindings 中所有自定义修饰键绑定动态派生)
    /// ButtonCore 回调读取此值, 注入到 passthrough 的键盘事件中
    private(set) var activeModifierFlags: UInt64 = 0

    /// 从 activeBindings 表重新计算 activeModifierFlags
    private func recomputeActiveModifierFlags() {
        var flags: UInt64 = 0
        for session in activeBindings.values {
            guard case let .customKey(code, modifiers) = session.action,
                  KeyCode.modifierKeys.contains(code) else { continue }
            flags |= modifiers | KeyCode.getKeyMask(code).rawValue
        }
        activeModifierFlags = flags
        MouseInteractionSessionController.shared.refreshMotionTapState()
        // Called after every change of the held actions: the watchdog and the keys tap
        // follow them.
        updateHeldActionTimer()
        ButtonCore.shared.keyTap.refresh()
    }

    /// 合并当前物理修饰键与虚拟修饰键, 供 synthetic / rewritten 事件复用
    func combinedModifierFlags(physicalModifiers: CGEventFlags? = nil) -> CGEventFlags {
        let physicalFlags = physicalModifiers ?? CGEventSource.flagsState(.combinedSessionState)
        return CGEventFlags(rawValue: physicalFlags.rawValue | activeModifierFlags)
    }

    /// 处理输入事件
    /// - Parameter event: 统一输入事件
    /// - Parameter scope: whose bindings a press goes by, when the caller decided it for this
    ///   press already (the Logitech probe); nil: the app in front decides here, once, at the
    ///   down (`ButtonUtils.scopeOfPress`); a key's auto-repeat goes by its press's. A
    ///   release never looks: it ends what its press started, whatever app is in front by
    ///   then.
    /// - Returns: .consumed 表示事件已处理, .passthrough 表示未匹配
    func process(_ event: InputEvent, scope: ButtonBindingScope? = nil) -> InputResult {
        assertMainThread()
        if event.phase == .up {
            if event.type == .keyboard {
                keyPressScopes.removeValue(forKey: TriggerKey(type: event.type, code: event.code))
            }
            // Up 事件: 按 (type, code) 查表, 忽略 modifiers (用户可能已松开修饰键)
            if releaseForShortcutRing(event) {
                return .consumed
            }
            if releaseBindingPressedAfterAnAbandonedGesture(for: event) {
                return .consumed
            }
            if releaseActiveMouseGesture(for: event) {
                return .consumed
            }
            if releaseActiveBinding(for: event) {
                return .consumed
            }
            if swallowedTriggerPresses.remove(TriggerKey(type: event.type, code: event.code)) != nil {
                return .consumed
            }
            return .passthrough
        }

        // Down 事件: 完整匹配 (type + code + modifiers + deviceFilter)
        let key = TriggerKey(type: event.type, code: event.code)
        if pressForOpenShortcutRing(event, key: key) {
            return .consumed
        }
        // A gesture hold of this button that the watchdog abandoned lost its up. A new press
        // ends it, whatever the press binds, so it cannot swallow this press's up.
        if let stale = activeMouseGestures[key], stale.isAbandoned {
            activeMouseGestures.removeValue(forKey: key)
        }
        // A trigger press of this button whose up never came: this press is a new one.
        swallowedTriggerPresses.remove(key)
        // A held key repeats its keyDown. The press it repeats holds its action already: the
        // repeat is swallowed, not run as a new press (that released and pressed the action
        // again: repeated clicks instead of a drag, a flickering modifier). A plain key output
        // still repeats like the key itself.
        if event.isAutoRepeat, let session = activeBindings[key], !Self.repeatsWhileHeld(session.action) {
            return .consumed
        }
        // A trigger action holds nothing, so its repeats come this far: they go by the
        // bindings of their press, not by those of the app that press brought forward.
        let pressScope: ButtonBindingScope
        if let scope {
            pressScope = scope
        } else if event.isAutoRepeat, let kept = keyPressScopes[key] {
            pressScope = kept
        } else {
            pressScope = ButtonUtils.shared.scopeOfPress(for: event)
        }
        if event.type == .keyboard, !event.isAutoRepeat {
            keyPressScopes[key] = pressScope
        }
        guard let binding = ButtonUtils.shared.getBestMatchingBinding(for: event, scope: pressScope) else {
            // A Logitech button Scrollio keeps for another binding: the press no binding
            // takes goes on as the button it is.
            guard let action = Self.standardButton(forCaughtPressWithoutBinding: event) else {
                return .passthrough
            }
            if let ring = ShortcutRingController.existing, ring.isOpen {
                ring.cancel()
            }
            return hold(action, for: key, event: event)
        }
        if binding.systemShortcutName == SystemShortcut.shortcutRing.identifier {
            // A key's repeat never opens or closes the ring: checked first.
            guard !event.isAutoRepeat else { return .consumed }
            pressShortcutRingTrigger(event, key: key)
            return .consumed
        }
        // Any other binding that fires closes an open ring, which runs nothing.
        if let ring = ShortcutRingController.existing, ring.isOpen {
            ring.cancel()
        }
        if binding.systemShortcutName == SystemShortcut.mouseGestureNavigation.identifier {
            guard event.type == .mouse else { return .passthrough }
            beginMouseGesture(key: key, event: event)
            return .consumed
        }

        guard let action = ShortcutExecutor.shared.resolveAction(
                named: binding.systemShortcutName,
                binding: binding
              ) ?? Self.standardButton(forAppsOwnDefault: binding, of: event, scope: pressScope) else {
            return .passthrough
        }

        if action.executionMode == .trigger {
            // A trigger action runs once per press: a held key's repeats are swallowed (they
            // used to run it again and again; a key whose action posts that same key ran it
            // in a loop).
            guard !event.isAutoRepeat else { return .consumed }
            ShortcutExecutor.shared.execute(action: action, phase: .down, inputModifiers: event.modifiers)
            if event.type == .mouse, case .cgEvent = event.source {
                swallowedTriggerPresses.insert(key)
            }
            return .consumed
        }
        return hold(action, for: key, event: event)
    }

    /// The press of an action that is held until its button or key is up: down now, up at
    /// the release (`releaseActiveBinding`). An action the same button or key still holds
    /// is let go first.
    private func hold(_ action: ResolvedAction, for key: TriggerKey, event: InputEvent) -> InputResult {
        if let existing = activeBindings.removeValue(forKey: key) {
            ShortcutExecutor.shared.execute(
                action: existing.action,
                phase: .up,
                mouseSessionID: existing.mouseSessionID,
                inputModifiers: event.modifiers
            )
        }

        let executionResult = ShortcutExecutor.shared.execute(action: action, phase: .down, inputModifiers: event.modifiers)
        activeBindings[key] = ActiveBindingSession(
            action: action,
            mouseSessionID: executionResult.mouseSessionID,
            scrollActionTapReplay: scrollActionTapReplay(for: action, event: event),
            physicalHold: Self.physicalHold(of: event)
        )
        suspectedLostReleases.remove(key)
        recomputeActiveModifierFlags()
        return .consumed
    }

    /// A plain key (not a modifier) as the action of a held keyboard trigger: each repeat of
    /// the trigger releases and presses it again, as it always did, so it repeats like the
    /// key itself. Every other held action (mouse buttons, modifiers, Scrollio scroll
    /// actions) stays pressed until the trigger's key-up.
    static func repeatsWhileHeld(_ action: ResolvedAction) -> Bool {
        if case .customKey(let code, _) = action {
            return !KeyCode.modifierKeys.contains(code)
        }
        return false
    }

    /// What a Logitech press does when its binding is the app's own "Default" ("the button
    /// does what it does by itself in this app"): a press that came over HID++ was caught by
    /// Scrollio for another binding of the same button (on a receiver every caught press
    /// does), and passed on it reached nobody. It goes on as the standard middle, back or
    /// forward button it is, down at the press and up at the release, as an action would.
    /// Nil for any other press, and for a control without a standard button (mode shift):
    /// that one still does nothing.
    static func standardButton(
        forAppsOwnDefault binding: ButtonBinding, of event: InputEvent, scope: ButtonBindingScope
    ) -> ResolvedAction? {
        guard binding.systemShortcutName.isEmpty, case .hidPP = event.source, let path = scope.applicationPath,
              let native = LogiStandardMouseButtonAlias.nativeButtonCode(forScrollioCode: event.code),
              (2...4).contains(native), let kind = MouseButtonActionKind(buttonNumber: native),
              let application = Options.shared.application.applications.get(by: path),
              application.ownButtonBindings.contains(where: { $0.identity == binding.identity }) else { return nil }
        return .mouseButton(kind: kind)
    }

    /// What a Logitech press does when no binding takes it. It came over HID++ because
    /// Scrollio keeps the button for another binding (one with modifier keys, in Buttons or
    /// the app's own; on a receiver every press of that button then comes this way), and
    /// passed on it reached nobody: the button was dead where the settings say it does what
    /// it does by itself. It goes on as the standard middle, back or forward button it is,
    /// down at the press and up at the release, as an app's own "Default" does
    /// (`standardButton(forAppsOwnDefault:)`); `ButtonDefaultOutcome` says the same in the
    /// settings. Nil for any other press, for a control without a standard button (the mode
    /// shift button, the gesture button: still nothing), and for a press that
    /// Scrolling › While you hold a key took (the session hands every press there first):
    /// that one is the key alone, as it always was. Nil too while a binding stored under
    /// the button's standard number has an action for the press (recorded over Bluetooth;
    /// a caught press does not reach it, `ButtonUtils.getBestMatchingBinding`): the button
    /// has an action in the settings, so it is not sent on as if it had none.
    static func standardButton(forCaughtPressWithoutBinding event: InputEvent) -> ResolvedAction? {
        guard event.type == .mouse, case .hidPP = event.source,
              let native = LogiStandardMouseButtonAlias.nativeButtonCode(forScrollioCode: event.code),
              (2...4).contains(native), let kind = MouseButtonActionKind(buttonNumber: native),
              !ScrollCore.shared.holdsScrollKey(code: event.code) else { return nil }
        let asStandard = InputEvent(
            type: .mouse, code: native, modifiers: event.modifiers, phase: .down, source: event.source, device: event.device
        )
        if let other = ButtonUtils.shared.getBestMatchingBinding(for: asStandard), !other.systemShortcutName.isEmpty {
            return nil
        }
        return .mouseButton(kind: kind)
    }

    // MARK: - Mouse Gesture Navigation

    private func beginMouseGesture(key: TriggerKey, event: InputEvent) {
        if let existing = activeMouseGestures[key] {
            // A duplicate down for a held button keeps the running gesture.
            guard existing.isAbandoned || existing.interactive?.phase == .finished else { return }
            // The watchdog gave up on that hold because its button-up never came: start over.
            // (The motion tap is refreshed once, at the end, for the new hold.)
            abandonMouseGesture(existing, key: key, refreshMotionTap: false)
        }
        // The app in front now decides whose actions the hold runs; the hold keeps them.
        let choice = MouseGestureChoice.make(
            front: mouseGestureFrontApplication(),
            applications: Options.shared.application.applications,
            general: Options.shared.gesture
        )
        let settings = choice.settings
        var hapticCode: UInt16?
        if settings.hapticFeedback, case .hidPP = event.source {
            hapticCode = event.code
        }
        let session = ActiveMouseGestureSession(
            settings: settings,
            isAppsOwn: choice.isAppsOwn,
            // The event says what the mouse does for this hold; the setting only decides
            // whether the mouse was asked to (LogiUsageBootstrap).
            movementSource: event.tracksMovementOnDevice ? .device : .pointer,
            hapticCode: hapticCode
        )
        activeMouseGestures[key] = session
        if session.movementSource == .pointer {
            pointerTrackedGestureCount += 1
        }
        if session.freezesPointer {
            MouseGesturePointerLock.shared.lock()
        }
        beginInteractiveGestureIfEnabled(session, key: key)
        armMouseGestureWatchdog(for: session, key: key)
        MouseInteractionSessionController.shared.refreshMotionTapState()
    }

    /// An up for a button whose abandoned gesture hold is still in the table while another
    /// binding of the same button is held: the up belongs to that binding (its press came
    /// later), and the stale hold goes with it.
    private func releaseBindingPressedAfterAnAbandonedGesture(for event: InputEvent) -> Bool {
        let key = TriggerKey(type: event.type, code: event.code)
        guard let gesture = activeMouseGestures[key], gesture.isAbandoned,
              activeBindings[key] != nil else { return false }
        activeMouseGestures.removeValue(forKey: key)
        return releaseActiveBinding(for: event)
    }

    private func releaseActiveMouseGesture(for event: InputEvent) -> Bool {
        let key = TriggerKey(type: event.type, code: event.code)
        guard let session = activeMouseGestures.removeValue(forKey: key) else {
            return false
        }
        session.watchdog?.cancel()
        session.watchdog = nil
        // The watchdog already released everything this hold owned; its late button-up is
        // only swallowed, so the app under the pointer never sees an up without a down.
        guard !session.isAbandoned else { return true }
        if event.isSyntheticRelease {
            // The hold was interrupted (the mouse went away), not released: unwind it like
            // the watchdog does. No click action, a running swipe is reverted, the pointer
            // and the motion tap are released.
            abandonMouseGesture(session, key: key, because: .mouseWentAway)
            return true
        }
        if session.movementSource == .pointer {
            pointerTrackedGestureCount -= 1
        }

        // Holds tracked by the mouse never locked the pointer and do not keep it locked.
        if pointerTrackedGestureCount == 0 {
            MouseGesturePointerLock.shared.unlock()
        }
        if session.interactive != nil {
            releaseInteractiveGesture(session, key: key)
        } else if session.recognizer.shouldReplayClick {
            // A plain click without movement runs the click action (Mission Control by
            // default, like the gesture button in Logi Options+).
            executeMouseGestureAction(session.settings.actions.click, part: .click, appsOwn: session.isAppsOwn)
        }
        MouseInteractionSessionController.shared.refreshMotionTapState()
        return true
    }

    /// Feeds the hand's movement into every held gesture button: the movement of one
    /// motion event as `handlePointerMovement` hands it on (the false delta of the pointer
    /// freeze already taken out), which both kinds of hold (discrete and "follow the hand")
    /// read.
    ///
    /// Holds the mouse tracks itself are skipped: their movement arrives through
    /// `handleDeviceGestureMovement`, and counting the pointer as well would double it.
    func handleMouseGestureMovement(deltaX: CGFloat, deltaY: CGFloat) {
        guard pointerTrackedGestureCount > 0 else { return }
        let delta = CGPoint(x: deltaX, y: deltaY)
        if interactiveGestureKey != nil, interactiveGestureSource == .pointer {
            accumulateInteractiveMovement(delta)
        }
        guard delta != .zero else { return }

        var recognized: (action: GestureAction, direction: MouseGestureDirection, appsOwn: Bool)?
        for session in activeMouseGestures.values
        where session.interactive == nil && session.movementSource == .pointer && !session.isAbandoned {
            if let direction = session.recognizer.append(deltaX: delta.x, deltaY: delta.y) {
                let action = session.settings.action(for: direction)
                playLockInHaptic(for: session, action: action)
                if recognized == nil {
                    recognized = (action, direction, session.isAppsOwn)
                }
            }
        }
        if let recognized {
            executeMouseGestureAction(recognized.action, part: .direction(recognized.direction), appsOwn: recognized.appsOwn)
        }
    }

    /// Feeds movement a mouse reports itself (Logitech raw XY, in sensor counts) into the
    /// hold of that one button. Runs in the HID report callback on the main thread, about
    /// 125 times a second; like the motion tap path it never posts anything itself.
    func handleDeviceGestureMovement(code: UInt16, countsX: Int, countsY: Int) {
        let key = TriggerKey(type: .mouse, code: code)
        guard let session = activeMouseGestures[key], session.movementSource == .device,
              !session.isAbandoned else { return }
        let deltaX = CGFloat(countsX) * MouseGestureDeviceTracking.pointsPerCount
        let deltaY = CGFloat(countsY) * MouseGestureDeviceTracking.pointsPerCount
        guard deltaX != 0 || deltaY != 0 else { return }

        if interactiveGestureKey == key {
            // The pointer is not frozen by Scrollio for this hold, so there is no warp to
            // compensate for.
            accumulateInteractiveMovement(CGPoint(x: deltaX, y: deltaY))
            return
        }
        guard session.interactive == nil,
              let direction = session.recognizer.append(deltaX: deltaX, deltaY: deltaY) else { return }
        let action = session.settings.action(for: direction)
        playLockInHaptic(for: session, action: action)
        executeMouseGestureAction(action, part: .direction(direction), appsOwn: session.isAppsOwn)
    }

    // MARK: - Haptic cues
    //
    // - lockIn (light): a discrete action fires, or a "follow the hand" swipe begins
    //   (sideways, or up or down towards a view of the Dock; a flick that then runs the
    //   direction's action once plays no second one).
    // - commit (stronger): a swipe is released towards a switch: the next Space, or a view
    //   that is expected to open or to be left (`InteractiveGestureSession.isExpectedToSwitch`).
    // Only for buttons that arrive over HID++ and while "haptic feedback" is on; the mouse
    // side decides whether it can and may play (LogiCenter.playGestureHaptic).

    /// Asks the mouse that owns the held button for a haptic cue. Deferred like the actions:
    /// the callers run inside event callbacks, and the request is a blocking device write.
    private func playGestureHaptic(_ cue: MouseGestureHapticCue, for session: ActiveMouseGestureSession) {
        guard let code = session.hapticCode else { return }
        let player = gestureHapticPlayer
        DispatchQueue.main.async {
            player(cue, code)
        }
    }

    /// A direction with "No Action" assigned fires nothing, so it gives no cue either.
    private func playLockInHaptic(for session: ActiveMouseGestureSession, action: GestureAction) {
        guard !action.isEmpty else { return }
        playGestureHaptic(.lockIn, for: session)
    }

    /// What of a gesture ran an action, for the log.
    enum MouseGesturePart: Equatable {
        case direction(MouseGestureDirection)
        case click

        var logName: String {
            switch self {
            case .direction(.up): return "up"
            case .direction(.down): return "down"
            case .direction(.left): return "left"
            case .direction(.right): return "right"
            case .click: return "click"
            }
        }
    }

    /// What became of a gesture's action, for its line in the log.
    enum MouseGestureOutcome: Equatable {
        /// Sent: keys, a click, the Dock asked, an app or a file handed on to be opened.
        case ran
        /// A Logitech action, asked of the mouse (the `logi` log says whether one could).
        case askedFor
        /// A listed action that sent nothing.
        case sentNothing(ShortcutRefusal)

        init(_ action: ResolvedAction, _ result: ActionExecutionResult) {
            if let refusal = result.refusal {
                self = .sentNothing(refusal)
            } else if case .logiAction = action {
                self = .askedFor
            } else {
                self = .ran
            }
        }
    }

    /// The one line a gesture's action leaves in the log: what it did, a listed action by
    /// its identifier, a recorded key combination by its kind, and whether it was of the
    /// own gestures of the app in front. Never its keys, never the name the user gave it,
    /// never the app's name.
    static func mouseGestureRunLine(
        _ action: GestureAction, part: MouseGesturePart, appsOwn: Bool = false, outcome: MouseGestureOutcome = .ran
    ) -> String {
        let what: String
        switch outcome {
        case .ran: what = "ran \(action.logName)"
        case .askedFor: what = "asked for \(action.logName)"
        case .sentNothing(.retired): what = "sent nothing: \(action.logName) is retired"
        case .sentNothing(.switchedOffInSystemSettings):
            what = "sent nothing: \(action.logName) is switched off in System Settings"
        }
        return "Gestures: \(part.logName) \(what)" + (appsOwn ? ", the app in front has its own gestures" : "")
    }

    /// Runs one gesture action as a single press (`ShortcutExecutor.executeOnePress`, the
    /// way a place of the Shortcut Ring runs one): trigger actions fire once, a click gets a
    /// down followed by an up, a recorded key combination goes out as a listed shortcut does.
    /// Its keys were read when the settings were (`GestureAction.keys`), nothing is parsed
    /// here.
    ///
    /// Posts after the CGEvent tap callback returns. Posting a synthetic event from inside
    /// the callback re-enters the event pipeline and can time out the tap.
    private func executeMouseGestureAction(_ gestureAction: GestureAction, part: MouseGesturePart, appsOwn: Bool) {
        guard !gestureAction.isEmpty else { return }
        let log = mouseGestureLog
        DispatchQueue.main.async {
            guard let action = gestureAction.resolvedAction else { return }
            let result = ShortcutExecutor.shared.executeOnePress(action)
            log(InputProcessor.mouseGestureRunLine(
                gestureAction, part: part, appsOwn: appsOwn, outcome: MouseGestureOutcome(action, result)
            ))
        }
    }

    // MARK: - Interactive Gesture ("follow the hand")

    private func beginInteractiveGestureIfEnabled(_ session: ActiveMouseGestureSession, key: TriggerKey) {
        guard session.settings.mode == .interactive,
              interactiveGestureKey == nil,
              DockSwipeSynthesizer.shared.isAvailable else {
            // Not available (or already driven by another button): the hold stays discrete.
            return
        }
        let environment = interactiveEnvironment
        let screen = environment.screen()
        let startTime = environment.now()
        var configuration = InteractiveGestureSession.Configuration(
            progressPerPoint: DockSwipeGeometry.progressPerPoint(
                screenWidth: screen.width,
                spaceCount: screen.spaceCount,
                trackingSpeed: session.settings.trackingSpeed
            ),
            maximumProgress: DockSwipeGeometry.progressPerSpace(spaceCount: screen.spaceCount),
            invertHorizontal: session.settings.invertHorizontal
        )
        if session.settings.actionsFollowNow {
            // "Up and Down follow the hand too": what each of the two does in this hold is
            // decided here, before anything is sent, from the hold's own settings (the own
            // set of the app in front counts as the pane's does), from what this Mac
            // follows now and from the view Scrollio believes it put up. Left and Right
            // stay the desktops' as they are, and with the switch off nobody asks.
            let follow = DockFollowHold(
                settings: session.settings, availability: followAvailability(), believed: dockBelief.view(at: startTime)
            )
            session.follow = follow
            let speed = session.settings.trackingSpeed
            if let channel = follow.up.channel(screenHeight: screen.height, trackingSpeed: speed) {
                configuration.roles.up = .channel(channel)
            }
            if let channel = follow.down.channel(screenHeight: screen.height, trackingSpeed: speed) {
                configuration.roles.down = .channel(channel)
            }
        }
        session.interactive = InteractiveGestureSession(configuration: configuration, startTime: startTime)
        interactiveGestureKey = key
        interactiveGestureSource = session.movementSource
        interactiveFrameDuration = screen.frameDuration
        pendingInteractiveDelta = .zero
    }

    /// Runs inside the motion tap callback: only adds up the movement. The session sees it
    /// on the main queue at most once per display frame, because the Dock stutters when
    /// swipe events arrive faster than it draws, and nothing may be posted from the callback.
    /// `delta` is already the physical movement (see `handleMouseGestureMovement`).
    private func accumulateInteractiveMovement(_ delta: CGPoint) {
        guard delta != .zero else { return }
        pendingInteractiveDelta.x += delta.x
        pendingInteractiveDelta.y += delta.y
        scheduleInteractiveFlush()
    }

    private func scheduleInteractiveFlush() {
        guard !isInteractiveFlushScheduled else { return }
        isInteractiveFlushScheduled = true
        interactiveFlushToken += 1
        let token = interactiveFlushToken
        let environment = interactiveEnvironment
        // The first movement after a pause goes out on the next main-queue turn; while the
        // hand keeps moving, flushes are one frame apart.
        let delay = max(0, lastInteractiveFlushTime + interactiveFrameDuration - environment.now())
        environment.schedule(delay) { [weak self] in
            guard let self, self.interactiveFlushToken == token else { return }
            self.flushInteractiveMovement()
        }
    }

    private func flushInteractiveMovement() {
        assertMainThread()
        isInteractiveFlushScheduled = false
        let delta = pendingInteractiveDelta
        pendingInteractiveDelta = .zero
        guard delta != .zero,
              let key = interactiveGestureKey,
              let session = activeMouseGestures[key] else { return }
        let now = interactiveEnvironment.now()
        lastInteractiveFlushTime = now
        let commands = session.interactive?.move(deltaX: delta.x, deltaY: delta.y, at: now) ?? []
        perform(commands, for: session)
    }

    private func releaseInteractiveGesture(_ session: ActiveMouseGestureSession, key: TriggerKey) {
        var pending = CGPoint.zero
        if interactiveGestureKey == key {
            pending = pendingInteractiveDelta
            pendingInteractiveDelta = .zero
            interactiveGestureKey = nil
        }
        let commands = session.interactive?.release(
            pendingDeltaX: pending.x,
            pendingDeltaY: pending.y,
            at: interactiveEnvironment.now()
        ) ?? []

        // The button-up arrives inside an event tap callback, so the swipe events wait for
        // the next main-queue turn, like the actions (which defer themselves).
        let swipeCommands = commands.filter { $0.isSwipeCommand }
        if !swipeCommands.isEmpty {
            let generation = interactiveSwipeGeneration
            let viewGeneration = viewSwipeGeneration
            let isTowardsAView = (session.interactive?.followedChannel?.motion ?? .horizontal) != .horizontal
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.interactiveSwipeGeneration == generation,
                      !isTowardsAView || self.viewSwipeGeneration == viewGeneration else {
                    // Revoked meanwhile (another swipe began, or a stop): nothing more is
                    // sent, and nothing is believed. A motion that had begun was taken
                    // back by whatever stopped it and gets its line here; a flick that was
                    // still whole never reached the Dock and writes none.
                    self.finishFollowedMotion(of: session, .cancelled(.takenBack))
                    return
                }
                self.perform(swipeCommands, for: session)
            }
        }
        perform(commands.filter { !$0.isSwipeCommand }, for: session)
    }

    /// Reverts a running swipe at once. Unlike a release this posts synchronously: the
    /// callers are the cancel paths (event tap disabled, sleep, quit), where the main queue
    /// may never run again and a deferred event would leave the desktop between two Spaces.
    private func cancelInteractiveGesture() {
        if let key = interactiveGestureKey, let session = activeMouseGestures[key] {
            let commands = session.interactive?.cancel() ?? []
            perform(commands.filter { $0.isSwipeCommand }, for: session, cancelledBy: .scrollioStopped)
        }
        // Also covers a released swipe whose terminal event is still queued; and what a
        // release queued for the next turn (a whole flick among it) is not sent after this.
        interactiveSwipeGeneration += 1
        DockSwipeSynthesizer.shared.cancel()
        interactiveGestureKey = nil
        pendingInteractiveDelta = .zero
        isInteractiveFlushScheduled = false
        interactiveFlushToken += 1
    }

    // MARK: - Hold watchdog
    //
    // A button-up can get lost (the event tap was disabled for a moment, the mouse went to
    // sleep or out of range mid-hold). Without a limit such a hold would keep the motion tap
    // running, keep feeding movement to the recognizer and swallow the next press of the
    // button as a "duplicate down". Every hold is therefore abandoned after a timeout, in
    // both modes.

    /// Arms the watchdog of a hold that has just begun.
    private func armMouseGestureWatchdog(for session: ActiveMouseGestureSession, key: TriggerKey) {
        let watchdog = DispatchWorkItem { [weak self, weak session] in
            guard let self, let session else { return }
            self.mouseGestureWatchdogFired(session, key: key)
        }
        session.watchdog?.cancel()
        session.watchdog = watchdog
        let timeout = mouseGestureHoldTimeoutOverride
            ?? session.interactive?.configuration.watchdogTimeout
            ?? Self.mouseGestureHoldTimeout
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: watchdog)
    }

    private func mouseGestureWatchdogFired(_ session: ActiveMouseGestureSession, key: TriggerKey) {
        // Only for the hold the watchdog was armed for, not a later press of the same button.
        guard activeMouseGestures[key] === session, !session.isAbandoned else { return }
        AppSystemLog.problem("InputProcessor: gesture hold watchdog fired (the button-up never came), abandoning the hold")
        abandonMouseGesture(session, key: key)
    }

    /// Gives up on a hold whose button-up never came: reverts a running swipe, stops reading
    /// movement for it and releases the pointer and the motion tap. No click is replayed.
    /// The entry stays in `activeMouseGestures` until its button-up or the next press.
    private func abandonMouseGesture(
        _ session: ActiveMouseGestureSession,
        key: TriggerKey,
        refreshMotionTap: Bool = true,
        because interruption: DockFollowedMotion.Interruption = .noButtonUp
    ) {
        guard !session.isAbandoned else { return }
        session.isAbandoned = true
        session.watchdog?.cancel()
        session.watchdog = nil
        if interactiveGestureKey == key {
            let commands = session.interactive?.expire() ?? []
            perform(commands, for: session, cancelledBy: interruption)
            interactiveGestureKey = nil
            pendingInteractiveDelta = .zero
        }
        if session.movementSource == .pointer {
            pointerTrackedGestureCount -= 1
        }
        if pointerTrackedGestureCount == 0 {
            MouseGesturePointerLock.shared.unlock()
        }
        if refreshMotionTap {
            MouseInteractionSessionController.shared.refreshMotionTapState()
        }
    }

    /// Turns the commands of a hold's state machine into the swipe and the actions.
    /// `interruption`: what took the hold's motion back, when it was not its own release.
    ///
    /// A swipe is the hold's own while it is the one that runs and has the number its
    /// begin gave it (`DockSwipeSynthesizer.isRunning`). One that was taken back meanwhile
    /// (the Dock was asked for a view in one go, which settles the swipe first) gets
    /// nothing more: a late update or end could otherwise reach a swipe that began after it.
    private func perform(
        _ commands: [InteractiveGestureSession.Command],
        for session: ActiveMouseGestureSession,
        cancelledBy interruption: DockFollowedMotion.Interruption? = nil
    ) {
        // The motion began in this very pass: the button came up in the turn that took the
        // hand past the starting distance, and the release brought begin and end at once.
        var beganInThisPass = false
        for command in commands {
            switch command {
            case .begin(let axis):
                beganInThisPass = true
                if axis != .horizontal, DockSwipeSynthesizer.shared.isActive {
                    // Only the thumb wheel's swipe of the desktops can run here (one hold
                    // drives at a time), or its tail while the wheel rests. A motion towards
                    // a view never takes it over: the Dock would get the end of one motion
                    // and the begin of another in one go. The direction runs its action
                    // once instead, beside the wheel's slide, which finishes by itself (the
                    // settle of an instant toggle leaves a swipe of the desktops alone);
                    // the rest of this hold's commands are dropped.
                    runOnceInsteadOfFollowing(session)
                    return
                }
                interactiveSwipeGeneration += 1
                DockSwipeSynthesizer.shared.begin(axis: axis)
                session.swipeNumber = DockSwipeSynthesizer.shared.swipeNumber
                noteFollowedMotionBegan(by: session, axis: axis)
                playGestureHaptic(.lockIn, for: session)
            case .update(let progress):
                guard DockSwipeSynthesizer.shared.isRunning(session.swipeNumber) else { continue }
                DockSwipeSynthesizer.shared.update(progress: progress)
                session.followed?.told(progress: progress)
            case .end(let velocity):
                guard DockSwipeSynthesizer.shared.isRunning(session.swipeNumber) else {
                    finishFollowedMotion(of: session, .cancelled(.takenBack))
                    continue
                }
                let expected = session.interactive?.isExpectedToSwitch(releaseVelocity: velocity) == true
                if expected || beganInThisPass, let motion = session.followed, motion.isFlickIfReleasedToSwitch {
                    // A quick flick: the view has barely moved and only the hand's speed
                    // says "open". Whether the Dock would finish that is its own secret,
                    // and before the direction could follow the hand such a flick opened
                    // the view. So the motion goes back and the direction's action runs
                    // once, through the usual path (a later turn; it settles the swipe and
                    // writes its line). No second pulse: the light one played at the begin.
                    //
                    // The same for a hold let go in the turn its motion began, whatever
                    // speed it is given: that speed is the last few points over a whole
                    // frame, far too low for a hand that was flicking, so the Dock would be
                    // told to begin and end a motion that shows nothing and nothing would
                    // run, where the action ran at this distance before.
                    DockSwipeSynthesizer.shared.cancel()
                    finishFollowedMotion(of: session, .flick(velocity: velocity))
                    executeMouseGestureAction(
                        session.settings.action(for: motion.direction), part: .direction(motion.direction),
                        appsOwn: session.isAppsOwn
                    )
                    continue
                }
                DockSwipeSynthesizer.shared.end(velocity: velocity)
                if expected {
                    playGestureHaptic(.commit, for: session)
                }
                finishFollowedMotion(of: session, .ended(velocity: velocity, expected: expected))
            case .cancel:
                guard DockSwipeSynthesizer.shared.isRunning(session.swipeNumber) else {
                    finishFollowedMotion(of: session, .cancelled(.takenBack))
                    continue
                }
                DockSwipeSynthesizer.shared.cancel()
                finishFollowedMotion(of: session, interruption.map { .cancelled($0) } ?? .cancelledAtRelease)
            case .discrete(let direction):
                let action = session.settings.action(for: direction)
                if let part = session.follow?[direction], case .onceInstead(_, let reason) = part, !action.isEmpty {
                    // It could have followed the hand: the log says why it did not.
                    let appsOwn = session.isAppsOwn
                    noteMouseGesture { DockFollowHold.ranOnceLine(direction, insteadOf: part, reason: reason, appsOwn: appsOwn) }
                }
                playLockInHaptic(for: session, action: action)
                executeMouseGestureAction(action, part: .direction(direction), appsOwn: session.isAppsOwn)
            case .click:
                executeMouseGestureAction(session.settings.actions.click, part: .click, appsOwn: session.isAppsOwn)
            }
        }
    }

    // MARK: - Up and Down follow the hand too
    //
    // In "Follow the hand", with the switch on, an Up or Down direction whose action shows
    // a view of the Dock drives that view's motion with the hand (`DockFollowHold`, decided
    // in `beginInteractiveGestureIfEnabled`). What is here keeps the Dock from hearing two
    // voices at once, keeps what Scrollio believes the Dock shows, and writes the hold's
    // line in the log.

    /// Writes a line of a hold to the log on a later turn of the main queue, where its text
    /// is made too: the callers run inside event callbacks.
    private func noteMouseGesture(_ line: @escaping () -> String) {
        let log = mouseGestureLog
        DispatchQueue.main.async {
            log(line())
        }
    }

    /// A motion up or down that may not begin (`perform`): for the state machine the hold
    /// is over, nothing of it reached the Dock, and its direction runs its action once, as
    /// it does without the switch.
    private func runOnceInsteadOfFollowing(_ session: ActiveMouseGestureSession) {
        guard let direction = session.interactive?.followedDirection else { return }
        _ = session.interactive?.cancel()
        if let key = interactiveGestureKey, activeMouseGestures[key] === session {
            interactiveGestureKey = nil
            pendingInteractiveDelta = .zero
        }
        let action = session.settings.action(for: direction)
        if let part = session.follow?[direction], !action.isEmpty {
            let appsOwn = session.isAppsOwn
            noteMouseGesture {
                DockFollowHold.ranOnceLine(direction, insteadOf: part, reason: .wheelSwipeRunning, appsOwn: appsOwn)
            }
        }
        playLockInHaptic(for: session, action: action)
        executeMouseGestureAction(action, part: .direction(direction), appsOwn: session.isAppsOwn)
    }

    /// A hold began a motion: for Up and Down its numbers are kept for the log (the
    /// desktops' swipe writes no line, as before).
    private func noteFollowedMotionBegan(by session: ActiveMouseGestureSession, axis: DockSwipeAxis) {
        guard axis != .horizontal, let interactive = session.interactive,
              let direction = interactive.followedDirection, let channel = interactive.followedChannel,
              let part = session.follow?[direction] else { return }
        session.followed = DockFollowedMotion(
            direction: direction,
            part: part,
            motion: axis,
            sign: channel.sign,
            fullProgress: channel.maximumProgress,
            beganAfter: interactiveEnvironment.now() - interactive.startTime
        )
    }

    /// The last event of a hold's motion up or down went out, or the motion had been taken
    /// back before: its one line in the log, and what Scrollio believes the Dock shows now
    /// (`DockFollowedMotion.beliefChange`: a hold that was let go and is expected to open
    /// its view put that view up; one that left Mission Control and was not turned back to
    /// its start leaves nothing believed).
    private func finishFollowedMotion(of session: ActiveMouseGestureSession, _ ending: DockFollowedMotion.Ending) {
        guard let motion = session.followed else { return }
        session.followed = nil
        var ending = ending
        let now = interactiveEnvironment.now()
        if ending == .cancelledAtRelease, let interactive = session.interactive,
           now - interactive.startTime >= interactive.configuration.watchdogTimeout {
            // The state machine gave the hold up itself: older than its limit.
            ending = .cancelled(.noButtonUp)
        }
        switch motion.beliefChange(after: ending) {
        case .opened(let target): dockBelief.holdOpened(target, at: now)
        case .dropped: dockBelief.drop()
        case .none: break
        }
        let appsOwn = session.isAppsOwn
        noteMouseGesture { motion.line(ending, appsOwn: appsOwn) }
    }

    /// Takes back the swipe that runs, at once (synchronously, as every abnormal end): the
    /// hold that drives it sends nothing more and runs nothing, and a swipe whose button is
    /// already up, or the thumb wheel's, goes back as well; what a release still held for
    /// the next turn of the main queue is not sent. A motion towards a view says so
    /// in its own line; a swipe of the desktops, which writes none otherwise, gets one here
    /// (a hold that is dead until its button is up should not be a riddle in the log).
    /// - onlyTowardsAView: only a motion towards a view of the Dock (vertical, pinch); the
    ///   desktops' swipe goes on.
    private func takeBackSwipe(onlyTowardsAView: Bool, because interruption: DockFollowedMotion.Interruption) {
        // What a release queued for the next turn is revoked as well, whether or not a
        // swipe runs yet: a whole flick must not begin after this. (Not the queued events
        // of the desktops' swipe where that swipe goes on: it still needs its end.)
        if onlyTowardsAView {
            viewSwipeGeneration += 1
        } else {
            interactiveSwipeGeneration += 1
        }
        guard let axis = DockSwipeSynthesizer.shared.runningAxis, !onlyTowardsAView || axis != .horizontal else { return }
        if let key = interactiveGestureKey, let session = activeMouseGestures[key], session.interactive?.phase == .swiping {
            let commands = session.interactive?.cancel() ?? []
            perform(commands.filter { $0.isSwipeCommand }, for: session, cancelledBy: interruption)
            // The hold stays in the table until its button is up; it reads no more movement.
            interactiveGestureKey = nil
            pendingInteractiveDelta = .zero
            isInteractiveFlushScheduled = false
            interactiveFlushToken += 1
        }
        DockSwipeSynthesizer.shared.cancel()
        if axis == .horizontal {
            noteMouseGesture { DockFollowedMotion.desktopsSwipeTakenBackLine(interruption) }
        }
    }

    // MARK: - What happens around a hold

    /// What macOS tells Scrollio that matters to a swipe or to the belief.
    enum SurroundingsChange: Equatable {
        case anotherApplicationCameToFront
        /// Finder came to the front: as any other app, except that a believed Show Desktop
        /// stays (a click on a file on the desktop is what that view is for).
        case finderCameToFront
        case activeSpaceChanged
        case screenParametersChanged
        case displaysWentToSleep

        static let finderBundleIdentifier = "com.apple.finder"

        /// The change that an app coming to the front is, by the app's bundle identifier.
        static func applicationCameToFront(bundleIdentifier: String?) -> SurroundingsChange {
            return bundleIdentifier == finderBundleIdentifier ? .finderCameToFront : .anotherApplicationCameToFront
        }
    }

    /// macOS told of a change (the observers below), or a test did.
    /// - Another app came to the front, or the desktop in use changed: whatever view
    ///   Scrollio put up is most likely gone, so nothing is believed to show any more.
    ///   Finder in front keeps a believed Show Desktop: clicking a file on the desktop
    ///   brings Finder to the front and is that view's use, and the view stays.
    /// - The desktop in use changed: a motion towards a view is taken back too (the Dock
    ///   has just rebuilt what the motion was moving). The desktops' own swipe goes on: its
    ///   own switch is such a change. And macOS tells of that switch late, up to about
    ///   half a second after the swipe ended: a change that comes within
    ///   `DockFollowTuning.lateDesktopChange` of the end of Scrollio's own swipe of the
    ///   desktops (a hold's or the thumb wheel's) is that swipe's, and changes nothing here.
    ///   Otherwise a flick sideways would take back the view the next hold is opening.
    /// - The screens changed, or the displays went to sleep: any swipe that runs is taken
    ///   back, and a swipe of the desktops that is taken back so writes a line. (Sleep,
    ///   another user, Pause and quit stop the cores, which does the same:
    ///   `clearActiveBindings`.) macOS also says "the screens changed" when only the Dock
    ///   changed its size or its place (an app that starts adds an icon): that takes
    ///   nothing back. A swipe goes back only when a screen's frame or the number of
    ///   screens is not what it was at the last look (`screensReallyChanged`).
    func surroundingsChanged(_ change: SurroundingsChange) {
        assertMainThread()
        switch change {
        case .anotherApplicationCameToFront:
            dockBelief.drop()
        case .finderCameToFront:
            if dockBelief.view(at: interactiveEnvironment.now()) != .showDesktop {
                dockBelief.drop()
            }
        case .activeSpaceChanged:
            guard !isLateWordOfOwnDesktopsSwipe else { return }
            dockBelief.drop()
            takeBackSwipe(onlyTowardsAView: true, because: .spaceChanged)
        case .screenParametersChanged:
            guard screensReallyChanged() else { return }
            takeBackSwipe(onlyTowardsAView: false, because: .screensChanged)
        case .displaysWentToSleep:
            takeBackSwipe(onlyTowardsAView: false, because: .displaysSlept)
        }
    }

    /// Looks at the screens: whether a frame, or how many there are, differs from the last
    /// look (the one at the start, then one per "the screens changed"). The frames are
    /// the whole screens: the Dock and the menu bar are not in them.
    private func screensReallyChanged() -> Bool {
        let frames = screenFrames()
        defer { lastScreenFrames = frames }
        return frames != lastScreenFrames
    }

    /// A swipe of the desktops was let go to macOS (`DockSwipeSynthesizer.desktopsSwipeDidEnd`).
    private func desktopsSwipeEnded() {
        desktopsSwipeEndedAt = interactiveEnvironment.now()
    }

    /// Scrollio's own swipe of the desktops ended so short a while ago that a change of the
    /// desktop told now is taken for its own.
    private var isLateWordOfOwnDesktopsSwipe: Bool {
        let since = interactiveEnvironment.now() - desktopsSwipeEndedAt
        return since >= 0 && since < DockFollowTuning.lateDesktopChange
    }

    private var surroundingsObservers: [NSObjectProtocol] = []

    /// Hears the four changes from macOS for as long as the app runs. Not under XCTest: a
    /// test tells `surroundingsChanged` itself, and what happens on the Mac that runs the
    /// tests must not reach them.
    private func observeSurroundings() {
        guard !AppRuntime.isRunningXCTest else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        let watched: [(NotificationCenter, Notification.Name, (Notification) -> SurroundingsChange)] = [
            (workspace, NSWorkspace.didActivateApplicationNotification, { notification in
                // Which app it is, only to know Finder (what the notification carries).
                let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                return .applicationCameToFront(bundleIdentifier: application?.bundleIdentifier)
            }),
            (workspace, NSWorkspace.activeSpaceDidChangeNotification, { _ in .activeSpaceChanged }),
            (workspace, NSWorkspace.screensDidSleepNotification, { _ in .displaysWentToSleep }),
            (NotificationCenter.default, NSApplication.didChangeScreenParametersNotification, { _ in .screenParametersChanged }),
        ]
        surroundingsObservers = watched.map { center, name, change in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                self?.surroundingsChanged(change(notification))
            }
        }
    }

    /// Scrollio is about to ask the Dock for one of its views in one go: Mission Control
    /// or Show Desktop by name (or by key), Apps by its key; from a button, a gesture, the
    /// Shortcut Ring (`ShortcutExecutor.dockViewWillBeToggled`). The Dock hears one voice
    /// about its views at a time, so whatever is left of a swipe is settled first: a motion
    /// towards a view that runs is cancelled, and a last event that was still to be posted
    /// again is posted now. A swipe of the desktops that runs goes on (the thumb wheel's
    /// slide ends by itself, and the desktop switches, as before). And the toggle ends
    /// what Scrollio believes the Dock shows: it closes the believed view or puts up
    /// another, and it is never believed itself (it may have closed a view that was
    /// opened elsewhere; only a hold that followed the hand sets the belief). Main thread.
    func dockViewWillBeToggled(_ view: DockFollowTarget) {
        assertMainThread()
        // A motion towards a view that a release still holds for the next turn (a whole
        // flick) is not sent after the toggle either.
        viewSwipeGeneration += 1
        DockSwipeSynthesizer.shared.settle()
        dockBelief.drop()
    }

    #if DEBUG
    /// What follows the hand for the next gesture holds; nil asks this Mac again.
    func setTestingFollowAvailability(_ availability: (() -> DockFollowAvailability)?) {
        followAvailability = availability ?? { .live }
    }

    /// The screens of the Mac a test makes up (their frames); nil looks at the real ones
    /// again. The frames it gives now are the last look.
    func setTestingScreenFrames(_ frames: (() -> [CGRect])?) {
        screenFrames = frames ?? InputProcessor.systemScreenFrames
        lastScreenFrames = screenFrames()
    }

    /// The view of the Dock Scrollio believes it put up, now.
    var believedDockView: DockFollowTarget? {
        return dockBelief.view(at: interactiveEnvironment.now())
    }

    /// A new environment brings its own clock, so the frame pacing starts over.
    func setTestingInteractiveGestureEnvironment(_ environment: InteractiveGestureEnvironment) {
        interactiveEnvironment = environment
        lastInteractiveFlushTime = -TimeInterval.infinity
        desktopsSwipeEndedAt = -TimeInterval.infinity
    }

    func clearTestingInteractiveGestureEnvironment() {
        setTestingInteractiveGestureEnvironment(.system)
    }

    /// Runs the watchdog of the "follow the hand" hold now instead of after its timeout.
    func fireInteractiveGestureWatchdogForTests() {
        guard let key = interactiveGestureKey, let session = activeMouseGestures[key] else { return }
        mouseGestureWatchdogFired(session, key: key)
    }

    /// Runs the watchdog of the held gesture buttons now instead of after its timeout:
    /// of all of them, or only of the mouse button with `code`.
    func fireMouseGestureWatchdogsForTests(code: UInt16? = nil) {
        for (key, session) in activeMouseGestures where code == nil || key.code == code {
            mouseGestureWatchdogFired(session, key: key)
        }
    }

    /// nil restores the real timeout.
    func setTestingMouseGestureHoldTimeout(_ timeout: TimeInterval?) {
        mouseGestureHoldTimeoutOverride = timeout
    }

    func setTestingGestureHapticPlayer(_ player: @escaping (MouseGestureHapticCue, UInt16) -> Void) {
        gestureHapticPlayer = player
    }

    func clearTestingGestureHapticPlayer() {
        gestureHapticPlayer = InputProcessor.systemGestureHapticPlayer
    }

    /// nil writes to the system log again.
    func setTestingMouseGestureLog(_ log: ((String) -> Void)?) {
        mouseGestureLog = log ?? { AppSystemLog.note($0) }
    }

    /// The app in front for the next gesture holds; nil reads the real one again.
    func setTestingMouseGestureFrontApplication(_ front: (() -> ShortcutRingChoice.FrontApp?)?) {
        mouseGestureFrontApplication = front ?? { .current() }
    }

    /// The hardware the watchdog of held actions asks; nil: none (no timer, no look).
    func setTestingHeldInputProbe(_ probe: HeldInputProbe?) {
        heldInputProbe = probe
        updateHeldActionTimer()
    }

    /// Whether the watchdog's timer runs.
    var isHeldActionTimerRunning: Bool {
        return heldActionTimer != nil
    }
    #endif

    private func releaseActiveBinding(for event: InputEvent) -> Bool {
        let key = TriggerKey(type: event.type, code: event.code)
        if let session = activeBindings.removeValue(forKey: key) {
            release(session, with: event)
            return true
        }
        return false
    }

    private func release(_ session: ActiveBindingSession, with event: InputEvent) {
        ShortcutExecutor.shared.execute(
            action: session.action,
            phase: .up,
            mouseSessionID: session.mouseSessionID,
            inputModifiers: event.modifiers
        )
        // A made-up release (the mouse went away mid-hold) is not a tap.
        if !event.isSyntheticRelease,
           let tapReplay = session.scrollActionTapReplay,
           shouldReplayScrollActionTap(tapReplay, releaseEvent: event) {
            ShortcutExecutor.shared.replayMouseTap(tapReplay.context)
        }
        recomputeActiveModifierFlags()
    }

    /// 标记 Mos Scroll 会话已经被真实滚动使用; 后续 mouseUp 不再重放原始点击。
    /// 已标记的会话不重复写回, 避免滚动高频路径上的无意义字典更新。
    func markScrollActionSessionsUsedForScroll() {
        for key in activeBindings.keys {
            guard var session = activeBindings[key],
                  var tapReplay = session.scrollActionTapReplay,
                  !tapReplay.didScroll else { continue }
            tapReplay.didScroll = true
            session.scrollActionTapReplay = tapReplay
            activeBindings[key] = session
        }
    }

    /// CG 鼠标按钮丢失 Up 事件时的兜底释放。
    /// 只在真实滚轮 delta 到达后调用, 因此不会给普通按键处理路径增加持续开销。
    func releaseScrollActionMouseSessionsIfPhysicalButtonsAreUp() {
        let releasedKeys = activeBindings.compactMap { key, session -> TriggerKey? in
            guard let tapReplay = session.scrollActionTapReplay,
                  let buttonNumber = tapReplay.releaseCheckButtonNumber,
                  !Self.isMouseButtonPressed(buttonNumber) else {
                return nil
            }
            return key
        }

        guard !releasedKeys.isEmpty else { return }

        for key in releasedKeys {
            guard let session = activeBindings.removeValue(forKey: key) else { continue }
            ShortcutExecutor.shared.execute(
                action: session.action,
                phase: .up,
                mouseSessionID: session.mouseSessionID
            )
        }
        recomputeActiveModifierFlags()
    }

    private func scrollActionTapReplay(for action: ResolvedAction, event: InputEvent) -> ScrollActionTapReplay? {
        guard case .scrollAction = action,
              let context = ShortcutExecutor.shared.mouseTapReplayContext(for: event) else {
            return nil
        }
        return ScrollActionTapReplay(
            context: context,
            releaseCheckButtonNumber: releaseCheckButtonNumber(for: event, context: context)
        )
    }

    private func releaseCheckButtonNumber(for event: InputEvent, context: MouseTapReplayContext) -> Int64? {
        guard event.type == .mouse,
              case .cgEvent = event.source else {
            return nil
        }
        return context.buttonNumber
    }

    private func shouldReplayScrollActionTap(_ tapReplay: ScrollActionTapReplay, releaseEvent: InputEvent) -> Bool {
        guard !tapReplay.didScroll else {
            return false
        }
        guard let downLocation = tapReplay.context.location,
              case .cgEvent(let cgEvent) = releaseEvent.source else {
            return true
        }
        let upLocation = cgEvent.location
        let deltaX = downLocation.x - upLocation.x
        let deltaY = downLocation.y - upLocation.y
        let distance = hypot(deltaX, deltaY)
        return distance <= Self.scrollActionTapReplayMovementTolerance
    }

    private static func isMouseButtonPressed(_ buttonNumber: Int64) -> Bool {
        guard buttonNumber >= 0,
              buttonNumber < Int64(Int.bitWidth) else {
            return true
        }
        return (NSEvent.pressedMouseButtons & (1 << Int(buttonNumber))) != 0
    }
}
