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
    init() {}

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

    var hasActiveMouseGestureSessions: Bool {
        return !activeMouseGestures.isEmpty
    }

    // MARK: - Shortcut Ring
    //
    // The ring's trigger is a binding like Gesture Navigation's: `process` hands its press
    // and its release to `ShortcutRingController`, which exists only once such a press has
    // come. Everyone else pays, per button or key event, a comparison of `ringTrigger`
    // with nil (and for Esc one more, of the controller with nil); nothing per wheel
    // event; and per pointer event one comparison with nil, only while the
    // pointer-movement tap runs at all (a gesture hold, a synthetic drag, a held modifier).

    /// The trigger whose press the ring took, until its release: every further down of it
    /// is the ring's too (a held key repeats, and its repeats no longer match the binding
    /// once the modifiers are let go), and so is its up.
    private var ringTrigger: TriggerKey?

    /// A ring is held open: the pointer-movement tap runs and its deltas go to the ring.
    var hasHeldShortcutRing: Bool {
        return ShortcutRingController.existing?.isHeld ?? false
    }

    /// Hands the movement of one motion event to a ring that is held open. Runs inside the
    /// motion tap's callback; nothing is posted from here.
    func handleShortcutRingMovement(deltaX: CGFloat, deltaY: CGFloat, location: CGPoint) {
        guard let ring = ShortcutRingController.existing, ring.isHeld else { return }
        ring.pointerMoved(by: CGPoint(x: deltaX, y: deltaY), to: location)
    }

    /// The release of the ring's trigger, or of Esc after it closed a ring.
    private func releaseForShortcutRing(_ event: InputEvent) -> Bool {
        let key = TriggerKey(type: event.type, code: event.code)
        if ringTrigger == key {
            ringTrigger = nil
            ShortcutRingController.existing?.triggerReleased(isMadeUp: event.isSyntheticRelease)
            return true
        }
        if event.type == .keyboard, event.code == KeyCode.escape,
           let ring = ShortcutRingController.existing, ring.escapeReleased() {
            return true
        }
        return false
    }

    /// A down that is the ring's before any binding is looked at: the held trigger again,
    /// or Esc while a ring is open.
    private func pressForOpenShortcutRing(_ event: InputEvent, key: TriggerKey) -> Bool {
        if ringTrigger == key {
            // A repeat of the held key, or a second down of the held button.
            if event.isAutoRepeat || ShortcutRingController.existing?.isHeld == true {
                return true
            }
            // A new press while the last one's release never came: it starts over.
            ringTrigger = nil
        }
        if event.type == .keyboard, event.code == KeyCode.escape, !event.isAutoRepeat,
           let ring = ShortcutRingController.existing, ring.isOpen {
            return ring.escapePressed()
        }
        return false
    }

    /// The press of a button or key bound to the Shortcut Ring.
    private func pressShortcutRingTrigger(_ event: InputEvent, key: TriggerKey) {
        if let held = ringTrigger, held != key {
            // A second trigger while the first is held: its press and release are taken
            // and mean nothing.
            swallowedTriggerPresses.insert(key)
            return
        }
        ringTrigger = key
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
        /// Snapshot at button-down, so editing settings mid-hold cannot mix two configurations.
        let settings: MouseGestureSettings
        /// Fixed for the whole hold: movement from the other source never reaches it.
        let movementSource: MouseGestureMovementSource
        /// The button to name when asking for a haptic cue: set for buttons that arrive
        /// over HID++ while haptic feedback is on, nil otherwise.
        let hapticCode: UInt16?
        var recognizer = MouseGestureRecognizer()
        /// Set in "follow the hand" mode; the recognizer above is then unused.
        var interactive: InteractiveGestureSession?
        /// Gives up on the hold when its button-up never arrives.
        var watchdog: DispatchWorkItem?
        /// The watchdog gave up on this hold. It stays in the table, so a late button-up is
        /// still swallowed, but it reads no movement and the next press starts over.
        var isAbandoned = false

        init(settings: MouseGestureSettings, movementSource: MouseGestureMovementSource, hapticCode: UInt16?) {
            self.settings = settings
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
    /// second gesture button pressed meanwhile behaves like the discrete mode.
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
    /// Counts swipes, so a terminal event queued for one swipe can never end a later one.
    private var interactiveSwipeGeneration = 0
    private var interactiveEnvironment = InteractiveGestureEnvironment.system
    /// Plays a haptic cue on the mouse a button belongs to. Replaced in tests.
    private var gestureHapticPlayer: (MouseGestureHapticCue, UInt16) -> Void = InputProcessor.systemGestureHapticPlayer

    private static let systemGestureHapticPlayer: (MouseGestureHapticCue, UInt16) -> Void = { cue, code in
        LogiCenter.shared.playGestureHaptic(cue, forScrollioCode: code)
    }

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
        // Esc closes an open Shortcut Ring, whatever opened it.
        if ShortcutRingController.existing?.needsKeys == true { return true }
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
        // An open Shortcut Ring closes and runs nothing.
        ringTrigger = nil
        ShortcutRingController.existing?.cancel()
        cancelInteractiveGesture()
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
    /// - Returns: .consumed 表示事件已处理, .passthrough 表示未匹配
    func process(_ event: InputEvent) -> InputResult {
        assertMainThread()
        if event.phase == .up {
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
        guard let binding = ButtonUtils.shared.getBestMatchingBinding(for: event) else {
            return .passthrough
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
              ) else {
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

    // MARK: - Mouse Gesture Navigation

    private func beginMouseGesture(key: TriggerKey, event: InputEvent) {
        if let existing = activeMouseGestures[key] {
            // A duplicate down for a held button keeps the running gesture.
            guard existing.isAbandoned || existing.interactive?.phase == .finished else { return }
            // The watchdog gave up on that hold because its button-up never came: start over.
            // (The motion tap is refreshed once, at the end, for the new hold.)
            abandonMouseGesture(existing, key: key, refreshMotionTap: false)
        }
        let settings = Options.shared.gesture
        var hapticCode: UInt16?
        if settings.hapticFeedback, case .hidPP = event.source {
            hapticCode = event.code
        }
        let session = ActiveMouseGestureSession(
            settings: settings,
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
            abandonMouseGesture(session, key: key)
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
            executeMouseGestureAction(named: session.settings.clickAction)
        }
        MouseInteractionSessionController.shared.refreshMotionTapState()
        return true
    }

    /// Feeds pointer movement from the motion tap into every held gesture button.
    /// `location` is the event's pointer location before the pointer lock rewrites it.
    ///
    /// Holds the mouse tracks itself are skipped: their movement arrives through
    /// `handleDeviceGestureMovement`, and counting the pointer as well would double it.
    func handleMouseGestureMovement(deltaX: CGFloat, deltaY: CGFloat, location: CGPoint? = nil) {
        guard pointerTrackedGestureCount > 0 else { return }
        // The pointer freeze can add a false delta when it has to warp the pointer back.
        // The compensation keeps state, so it runs exactly once per motion event, and both
        // kinds of hold (discrete and "follow the hand") read its result.
        var delta = CGPoint(x: deltaX, y: deltaY)
        if let location {
            delta = MouseGesturePointerLock.shared.physicalDelta(delta, at: location)
        }
        if interactiveGestureKey != nil, interactiveGestureSource == .pointer {
            accumulateInteractiveMovement(delta)
        }
        guard delta != .zero else { return }

        var recognizedAction: String?
        for session in activeMouseGestures.values
        where session.interactive == nil && session.movementSource == .pointer && !session.isAbandoned {
            if let direction = session.recognizer.append(deltaX: delta.x, deltaY: delta.y) {
                let action = session.settings.actionIdentifier(for: direction)
                playLockInHaptic(for: session, action: action)
                if recognizedAction == nil {
                    recognizedAction = action
                }
            }
        }
        if let recognizedAction {
            executeMouseGestureAction(named: recognizedAction)
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
        let action = session.settings.actionIdentifier(for: direction)
        playLockInHaptic(for: session, action: action)
        executeMouseGestureAction(named: action)
    }

    // MARK: - Haptic cues
    //
    // - lockIn (light): a discrete action fires, or a "follow the hand" swipe begins.
    // - commit (stronger): a swipe is released towards a switch
    //   (`InteractiveGestureSession.isExpectedToSwitch`).
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
    private func playLockInHaptic(for session: ActiveMouseGestureSession, action: String) {
        guard !action.isEmpty else { return }
        playGestureHaptic(.lockIn, for: session)
    }

    /// Runs one gesture action as a single press: trigger actions fire once, stateful ones
    /// (mouse buttons, custom keys) get a down followed by an up.
    ///
    /// Posts after the CGEvent tap callback returns. Posting a synthetic event from inside
    /// the callback re-enters the event pipeline and can time out the tap.
    private func executeMouseGestureAction(named identifier: String) {
        guard !identifier.isEmpty else { return }
        DispatchQueue.main.async {
            guard let action = ShortcutExecutor.shared.resolveAction(named: identifier) else { return }
            let result = ShortcutExecutor.shared.execute(action: action, phase: .down)
            if action.executionMode == .stateful {
                ShortcutExecutor.shared.execute(
                    action: action,
                    phase: .up,
                    mouseSessionID: result.mouseSessionID
                )
            }
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
        session.interactive = InteractiveGestureSession(
            configuration: InteractiveGestureSession.Configuration(
                progressPerPoint: DockSwipeGeometry.progressPerPoint(
                    screenWidth: screen.width,
                    spaceCount: screen.spaceCount,
                    trackingSpeed: session.settings.trackingSpeed
                ),
                maximumProgress: DockSwipeGeometry.progressPerSpace(spaceCount: screen.spaceCount),
                invertHorizontal: session.settings.invertHorizontal
            ),
            startTime: environment.now()
        )
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
            DispatchQueue.main.async { [weak self] in
                guard let self, self.interactiveSwipeGeneration == generation else { return }
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
            perform(commands.filter { $0.isSwipeCommand }, for: session)
        }
        // Also covers a released swipe whose terminal event is still queued.
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
        refreshMotionTap: Bool = true
    ) {
        guard !session.isAbandoned else { return }
        session.isAbandoned = true
        session.watchdog?.cancel()
        session.watchdog = nil
        if interactiveGestureKey == key {
            let commands = session.interactive?.expire() ?? []
            perform(commands, for: session)
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

    private func perform(_ commands: [InteractiveGestureSession.Command], for session: ActiveMouseGestureSession) {
        for command in commands {
            switch command {
            case .begin(let axis):
                interactiveSwipeGeneration += 1
                DockSwipeSynthesizer.shared.begin(axis: axis)
                playGestureHaptic(.lockIn, for: session)
            case .update(let progress):
                DockSwipeSynthesizer.shared.update(progress: progress)
            case .end(let velocity):
                DockSwipeSynthesizer.shared.end(velocity: velocity)
                if session.interactive?.isExpectedToSwitch(releaseVelocity: velocity) == true {
                    playGestureHaptic(.commit, for: session)
                }
            case .cancel:
                DockSwipeSynthesizer.shared.cancel()
            case .discrete(let direction):
                let action = session.settings.actionIdentifier(for: direction)
                playLockInHaptic(for: session, action: action)
                executeMouseGestureAction(named: action)
            case .click:
                executeMouseGestureAction(named: session.settings.clickAction)
            }
        }
    }

    #if DEBUG
    /// A new environment brings its own clock, so the frame pacing starts over.
    func setTestingInteractiveGestureEnvironment(_ environment: InteractiveGestureEnvironment) {
        interactiveEnvironment = environment
        lastInteractiveFlushTime = -TimeInterval.infinity
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
