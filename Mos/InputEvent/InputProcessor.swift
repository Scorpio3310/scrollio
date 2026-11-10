//
//  InputProcessor.swift
//  Mos
//  统一事件处理器 - 接收 InputEvent, 匹配 ButtonBinding, 执行动作
//  Created by Mos on 2026/3/16.
//  Copyright © 2026 Caldis. All rights reserved.
//

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
    init() { NSLog("Module initialized: InputProcessor") }

    private static let mosScrollTapReplayMovementTolerance: CGFloat = 8.0

    // MARK: - Active Bindings Table
    /// 跟踪当前按下中的 stateful 动作, 用于 Up 事件配对
    private var activeBindings: [TriggerKey: ActiveBindingSession] = [:]
    /// 按住中的手势导航按键, 每个按键一次按住对应一个识别器
    private var activeMouseGestures: [TriggerKey: ActiveMouseGestureSession] = [:]

    var hasActiveMouseGestureSessions: Bool {
        return !activeMouseGestures.isEmpty
    }

    private struct TriggerKey: Hashable {
        let type: EventType
        let code: UInt16
    }

    private struct ActiveBindingSession {
        let action: ResolvedAction
        let mouseSessionID: UUID?
        var mosScrollTapReplay: MosScrollTapReplay?
    }

    private final class ActiveMouseGestureSession {
        /// Snapshot at button-down, so editing settings mid-hold cannot mix two configurations.
        let settings: MouseGestureSettings
        var recognizer = MouseGestureRecognizer()
        /// Set in "follow the hand" mode; the recognizer above is then unused.
        var interactive: InteractiveGestureSession?

        init(settings: MouseGestureSettings) {
            self.settings = settings
        }
    }

    // MARK: - Interactive Gesture State
    /// The hold that drives the interactive swipe. Only one swipe can run at a time, so a
    /// second gesture button pressed meanwhile behaves like the discrete mode.
    private var interactiveGestureKey: TriggerKey?
    /// Movement received in the motion tap callback and not yet handed to the session.
    private var pendingInteractiveDelta = CGPoint.zero
    private var isInteractiveFlushScheduled = false
    /// Invalidates a scheduled flush that is no longer wanted.
    private var interactiveFlushToken = 0
    private var lastInteractiveFlushTime = -TimeInterval.infinity
    private var interactiveFrameDuration = InteractiveGestureEnvironment.fallbackScreen.frameDuration
    /// Counts swipes, so a terminal event queued for one swipe can never end a later one.
    private var interactiveSwipeGeneration = 0
    private var interactiveWatchdog: DispatchWorkItem?
    private var interactiveEnvironment = InteractiveGestureEnvironment.system

    private struct MosScrollTapReplay {
        let context: MouseTapReplayContext
        /// 仅 CG 鼠标事件设置。HID++/Logi 按键不可靠更新 NSEvent.pressedMouseButtons,
        /// 不能用 AppKit 的物理按钮位图做兜底释放判断。
        let releaseCheckButtonNumber: Int64?
        var didScroll = false
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
        cancelInteractiveGesture()
        activeMouseGestures.removeAll()
        MouseGesturePointerLock.shared.unlock()
        activeModifierFlags = 0
        MouseInteractionSessionController.shared.clearAllSessions()
        MouseInteractionSessionController.shared.refreshMotionTapState()
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
            if releaseActiveMouseGesture(for: event) {
                return .consumed
            }
            if releaseActiveBinding(for: event) {
                return .consumed
            }
            return .passthrough
        }

        // Down 事件: 完整匹配 (type + code + modifiers + deviceFilter)
        let key = TriggerKey(type: event.type, code: event.code)
        guard let binding = ButtonUtils.shared.getBestMatchingBinding(for: event) else {
            return .passthrough
        }
        if binding.systemShortcutName == SystemShortcut.mouseGestureNavigation.identifier {
            guard event.type == .mouse else { return .passthrough }
            beginMouseGesture(key: key)
            return .consumed
        }

        guard let action = ShortcutExecutor.shared.resolveAction(
                named: binding.systemShortcutName,
                binding: binding
              ) else {
            return .passthrough
        }

        if action.executionMode == .trigger {
            ShortcutExecutor.shared.execute(action: action, phase: .down, inputModifiers: event.modifiers)
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
            mosScrollTapReplay: mosScrollTapReplay(for: action, event: event)
        )
        recomputeActiveModifierFlags()
        return .consumed
    }

    // MARK: - Mouse Gesture Navigation

    private func beginMouseGesture(key: TriggerKey) {
        if let existing = activeMouseGestures[key] {
            // A duplicate down for a held button keeps the running gesture.
            guard existing.interactive?.phase == .finished else { return }
            // The watchdog gave up on that hold because its button-up never came: start over.
            if interactiveGestureKey == key {
                interactiveGestureKey = nil
            }
        }
        let session = ActiveMouseGestureSession(settings: Options.shared.gesture)
        activeMouseGestures[key] = session
        if session.settings.freezePointer {
            MouseGesturePointerLock.shared.lock()
        }
        beginInteractiveGestureIfEnabled(session, key: key)
        MouseInteractionSessionController.shared.refreshMotionTapState()
    }

    private func releaseActiveMouseGesture(for event: InputEvent) -> Bool {
        let key = TriggerKey(type: event.type, code: event.code)
        guard let session = activeMouseGestures.removeValue(forKey: key) else {
            return false
        }

        if activeMouseGestures.isEmpty {
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
    func handleMouseGestureMovement(deltaX: CGFloat, deltaY: CGFloat, location: CGPoint? = nil) {
        guard !activeMouseGestures.isEmpty else { return }
        if interactiveGestureKey != nil {
            accumulateInteractiveMovement(deltaX: deltaX, deltaY: deltaY, location: location)
        }
        guard deltaX != 0 || deltaY != 0 else { return }

        var recognizedAction: String?
        for session in activeMouseGestures.values where session.interactive == nil {
            if let direction = session.recognizer.append(deltaX: deltaX, deltaY: deltaY),
               recognizedAction == nil {
                recognizedAction = session.settings.actionIdentifier(for: direction)
            }
        }
        if let recognizedAction {
            executeMouseGestureAction(named: recognizedAction)
        }
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
        interactiveFrameDuration = screen.frameDuration
        pendingInteractiveDelta = .zero

        let watchdog = DispatchWorkItem { [weak self] in
            self?.interactiveGestureWatchdogFired(key: key)
        }
        interactiveWatchdog?.cancel()
        interactiveWatchdog = watchdog
        let timeout = session.interactive?.configuration.watchdogTimeout ?? MouseGesturePointerLock.safetyTimeout
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: watchdog)
    }

    /// Runs inside the motion tap callback: only adds up the movement. The session sees it
    /// on the main queue at most once per display frame, because the Dock stutters when
    /// swipe events arrive faster than it draws, and nothing may be posted from the callback.
    private func accumulateInteractiveMovement(deltaX: CGFloat, deltaY: CGFloat, location: CGPoint?) {
        var delta = CGPoint(x: deltaX, y: deltaY)
        if let location {
            // The pointer freeze can add a false delta when it has to warp the pointer back.
            delta = MouseGesturePointerLock.shared.physicalDelta(delta, at: location)
        }
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
            interactiveWatchdog?.cancel()
            interactiveWatchdog = nil
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
        interactiveWatchdog?.cancel()
        interactiveWatchdog = nil
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

    private func interactiveGestureWatchdogFired(key: TriggerKey) {
        guard interactiveGestureKey == key, let session = activeMouseGestures[key] else { return }
        NSLog("InputProcessor: interactive gesture watchdog, abandoning the hold")
        let commands = session.interactive?.expire() ?? []
        perform(commands, for: session)
    }

    private func perform(_ commands: [InteractiveGestureSession.Command], for session: ActiveMouseGestureSession) {
        for command in commands {
            switch command {
            case .begin(let axis):
                interactiveSwipeGeneration += 1
                DockSwipeSynthesizer.shared.begin(axis: axis)
            case .update(let progress):
                DockSwipeSynthesizer.shared.update(progress: progress)
            case .end(let velocity):
                DockSwipeSynthesizer.shared.end(velocity: velocity)
            case .cancel:
                DockSwipeSynthesizer.shared.cancel()
            case .discrete(let direction):
                executeMouseGestureAction(named: session.settings.actionIdentifier(for: direction))
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

    /// Runs the watchdog now instead of after its timeout.
    func fireInteractiveGestureWatchdogForTests() {
        guard let key = interactiveGestureKey else { return }
        interactiveGestureWatchdogFired(key: key)
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
        if let tapReplay = session.mosScrollTapReplay,
           shouldReplayMosScrollTap(tapReplay, releaseEvent: event) {
            ShortcutExecutor.shared.replayMouseTap(tapReplay.context)
        }
        recomputeActiveModifierFlags()
    }

    /// 标记 Mos Scroll 会话已经被真实滚动使用; 后续 mouseUp 不再重放原始点击。
    /// 已标记的会话不重复写回, 避免滚动高频路径上的无意义字典更新。
    func markMosScrollActionSessionsUsedForScroll() {
        for key in activeBindings.keys {
            guard var session = activeBindings[key],
                  var tapReplay = session.mosScrollTapReplay,
                  !tapReplay.didScroll else { continue }
            tapReplay.didScroll = true
            session.mosScrollTapReplay = tapReplay
            activeBindings[key] = session
        }
    }

    /// CG 鼠标按钮丢失 Up 事件时的兜底释放。
    /// 只在真实滚轮 delta 到达后调用, 因此不会给普通按键处理路径增加持续开销。
    func releaseMosScrollMouseSessionsIfPhysicalButtonsAreUp() {
        let releasedKeys = activeBindings.compactMap { key, session -> TriggerKey? in
            guard let tapReplay = session.mosScrollTapReplay,
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

    private func mosScrollTapReplay(for action: ResolvedAction, event: InputEvent) -> MosScrollTapReplay? {
        guard case .mosScroll = action,
              let context = ShortcutExecutor.shared.mouseTapReplayContext(for: event) else {
            return nil
        }
        return MosScrollTapReplay(
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

    private func shouldReplayMosScrollTap(_ tapReplay: MosScrollTapReplay, releaseEvent: InputEvent) -> Bool {
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
        return distance <= Self.mosScrollTapReplayMovementTolerance
    }

    private static func isMouseButtonPressed(_ buttonNumber: Int64) -> Bool {
        guard buttonNumber >= 0,
              buttonNumber < Int64(Int.bitWidth) else {
            return true
        }
        return (NSEvent.pressedMouseButtons & (1 << Int(buttonNumber))) != 0
    }
}
