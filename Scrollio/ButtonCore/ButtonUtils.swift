//
//  ButtonUtils.swift
//  Mos
//  按钮绑定工具类 - 获取配置和管理绑定 (带缓存)
//  Created by Claude on 2025/8/10.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

struct ButtonBindingTriggerKey: Hashable {
    let type: EventType
    let code: UInt16
}

class ButtonUtils {

    // 单例
    static let shared = ButtonUtils()
    init() {
        // 绑定组变更时自动失效缓存 (订阅者为进程级单例, 无需注销)
        Options.shared.observe([.buttons]) { [weak self] _ in
            self?.invalidateCache()
        }
    }

    // MARK: - 缓存

    /// 缓存的绑定列表 (已预解析 custom:: 字段)
    private var cachedBindings: [ButtonBinding] = []
    private var cachedBindingsByTriggerKey: [ButtonBindingTriggerKey: [ButtonBinding]] = [:]
    /// An enabled binding has a key as its trigger (and can run): the key tap is needed.
    private var cachedHasKeyboardTriggers = false
    private var isDirty = true
    /// Called after the bindings changed (ButtonCore: its key tap follows them).
    var onInvalidate: (() -> Void)?

    // MARK: - 获取按钮绑定配置

    /// 获取当前应用的按钮绑定配置 (带缓存和预解析)
    /// - Returns: 按钮绑定列表
    func getButtonBindings() -> [ButtonBinding] {
        refreshCacheIfNeeded()
        return cachedBindings
    }

    func getButtonBindings(for type: EventType, code: UInt16) -> [ButtonBinding] {
        refreshCacheIfNeeded()
        return cachedBindingsByTriggerKey[ButtonBindingTriggerKey(type: type, code: code)] ?? []
    }

    func getBestMatchingBinding(
        for event: InputEvent,
        where predicate: ((ButtonBinding) -> Bool)? = nil
    ) -> ButtonBinding? {
        let candidates = getButtonBindings(for: event.type, code: event.code)
        var bestBinding: ButtonBinding?
        var bestPriority = Int.min

        for binding in candidates {
            guard binding.isEnabled else {
                continue
            }
            if let predicate, !predicate(binding) {
                continue
            }
            guard let priority = binding.triggerEvent.matchPriority(for: event) else {
                continue
            }
            if priority > bestPriority {
                bestBinding = binding
                bestPriority = priority
            }
        }

        return bestBinding
    }

    /// Whether some enabled binding is triggered by a key. Only then (and while a button
    /// holds a modifier) does ButtonCore listen to the keyboard at all.
    var hasKeyboardTriggers: Bool {
        refreshCacheIfNeeded()
        return cachedHasKeyboardTriggers
    }

    /// 标记缓存失效 (绑定变更后调用)
    func invalidateCache() {
        assertMainThread()
        isDirty = true
        onInvalidate?()
    }

    // MARK: - Triggers that can run

    /// Whether a stored trigger can run at all: what the recorder takes
    /// (`InputEvent.isRecordable`).
    ///
    /// - A key needs ⌘, ⌥, ⌃ or ⇧, unless it is an F-key. The rule used to live in the
    ///   recorder only, and a binding is data: anything that can write the settings could
    ///   store a plain letter or Space as the trigger of "open this file" or "run this
    ///   script", and the next press of that key ran it. A modifier key alone is no trigger
    ///   either (the button tap does not see modifier keys).
    /// - The left and right mouse buttons are never a trigger: no event tap of the app sees
    ///   them.
    ///
    /// A binding that cannot run stays stored and listed; it is only never matched.
    static func isRunnable(_ trigger: RecordedEvent) -> Bool {
        switch trigger.type {
        case .keyboard:
            if KeyCode.modifierKeys.contains(trigger.code) { return false }
            if KeyCode.functionKeys.contains(trigger.code) { return true }
            return UInt64(trigger.modifiers) & KeyCode.modifiersMask != 0
        case .mouse:
            return !KeyCode.mouseMainKeys.contains(trigger.code)
        }
    }

    private func refreshCacheIfNeeded() {
        guard isDirty else { return }

        cachedBindings = Options.shared.buttons.binding.map { binding in
            var b = binding
            b.prepareCustomCache()
            return b
        }

        // Only what can run is matched (`isRunnable`); the list above keeps every binding.
        let runnable = cachedBindings.filter { Self.isRunnable($0.triggerEvent) }
        cachedBindingsByTriggerKey = Dictionary(grouping: runnable) { binding in
            ButtonBindingTriggerKey(
                type: binding.triggerEvent.type,
                code: binding.triggerEvent.code
            )
        }
        cachedHasKeyboardTriggers = runnable.contains { $0.isEnabled && $0.triggerEvent.type == .keyboard }

        isDirty = false
    }

    // MARK: - 分应用支持 (预留接口)

    /// 获取当前焦点应用的配置对象 (预留)
    /// - Returns: Application 对象或 nil
    private func getTargetApplication() -> Application? {
        return nil
    }
}
