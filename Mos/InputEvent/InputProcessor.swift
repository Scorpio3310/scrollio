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

        init(settings: MouseGestureSettings) {
            self.settings = settings
        }
    }

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
        // A duplicate down for a held button keeps the running gesture.
        guard activeMouseGestures[key] == nil else { return }
        let session = ActiveMouseGestureSession(settings: Options.shared.gesture)
        activeMouseGestures[key] = session
        if session.settings.freezePointer {
            MouseGesturePointerLock.shared.lock()
        }
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
        if session.recognizer.shouldReplayClick {
            // A plain click without movement runs the click action (Mission Control by
            // default, like the gesture button in Logi Options+).
            executeMouseGestureAction(named: session.settings.clickAction)
        }
        MouseInteractionSessionController.shared.refreshMotionTapState()
        return true
    }

    /// Feeds pointer movement from the motion tap into every held gesture button.
    func handleMouseGestureMovement(deltaX: CGFloat, deltaY: CGFloat) {
        guard !activeMouseGestures.isEmpty else { return }
        guard deltaX != 0 || deltaY != 0 else { return }

        var recognizedAction: String?
        for session in activeMouseGestures.values {
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
