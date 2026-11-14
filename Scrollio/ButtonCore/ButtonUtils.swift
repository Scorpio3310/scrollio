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

/// Whose bindings a press goes by, decided once when the button or key goes down: the
/// general ones, or those of the app in front that has buttons of its own
/// (`ApplicationButtons`). The release never asks again: it ends what the press started.
struct ButtonBindingScope: Equatable {
    /// The path of the app's entry; nil: the general bindings.
    let applicationPath: String?

    static let general = ButtonBindingScope(applicationPath: nil)

    /// The bindings of the app in front, not the general ones (for the log, which never
    /// names an app).
    var isAppsOwn: Bool {
        return applicationPath != nil
    }
}

class ButtonUtils {

    // 单例
    static let shared = ButtonUtils()
    init() {
        // 绑定组变更时自动失效缓存 (订阅者为进程级单例, 无需注销). An app's own buttons are
        // stored with the per-app list: its changes count too.
        Options.shared.observe([.buttons, .application]) { [weak self] _ in
            self?.invalidateCache()
        }
    }

    // MARK: - 缓存

    /// 缓存的绑定列表 (已预解析 custom:: 字段)
    private var cachedBindings: [ButtonBinding] = []
    private var cachedBindingsByTriggerKey: [ButtonBindingTriggerKey: [ButtonBinding]] = [:]
    /// For each app with buttons of its own (by its entry's path; of two entries of one
    /// path, the one `get(by:)` returns, as for every other reader): the general bindings
    /// with the app's own merged over them, by trigger. Built
    /// with the general table; an app without buttons of its own has none and costs nothing.
    private var cachedAppBindingsByTriggerKey: [String: [ButtonBindingTriggerKey: [ButtonBinding]]] = [:]
    /// The buttons and keys some app has a binding of its own on: only a press of one of
    /// them asks which app is in front.
    private var cachedAppTriggerKeys: Set<ButtonBindingTriggerKey> = []
    /// An enabled binding has a key as its trigger (and can run): the key tap is needed.
    /// The general bindings and every app's own.
    private var cachedHasKeyboardTriggers = false
    private var isDirty = true
    /// Called after the bindings changed (ButtonCore: its key tap follows them).
    var onInvalidate: (() -> Void)?

    /// The app in front when a button or key goes down. Tests give one of their own.
    var frontApplication: () -> ShortcutRingChoice.FrontApp? = { .current() }

    // MARK: - 获取按钮绑定配置

    /// 获取当前应用的按钮绑定配置 (带缓存和预解析)
    /// - Returns: 按钮绑定列表
    func getButtonBindings() -> [ButtonBinding] {
        refreshCacheIfNeeded()
        return cachedBindings
    }

    func getButtonBindings(for type: EventType, code: UInt16, scope: ButtonBindingScope = .general) -> [ButtonBinding] {
        refreshCacheIfNeeded()
        let key = ButtonBindingTriggerKey(type: type, code: code)
        if let path = scope.applicationPath, let table = cachedAppBindingsByTriggerKey[path] {
            return table[key] ?? []
        }
        return cachedBindingsByTriggerKey[key] ?? []
    }

    /// Whose bindings a press of `event`'s button or key goes by now: those of the app in
    /// front when it has a binding of its own on that button or key, else the general ones
    /// (for any other button the app's bindings are the general ones). The app in front is
    /// read only for a button or key some app has a binding of its own on (what
    /// `NSWorkspace` holds already: nothing on disk, no Launch Services); for every other
    /// press this is one look into a set.
    func scopeOfPress(for event: InputEvent) -> ButtonBindingScope {
        refreshCacheIfNeeded()
        let twin = Self.twin(of: event)
        guard cachedAppTriggerKeys.contains(ButtonBindingTriggerKey(type: event.type, code: event.code))
                || twin.map({ cachedAppTriggerKeys.contains(ButtonBindingTriggerKey(type: $0.type, code: $0.code)) }) == true,
              let entry = ApplicationButtons.entry(front: frontApplication(), applications: Options.shared.application.applications),
              cachedAppBindingsByTriggerKey[entry.path] != nil else { return .general }
        return ButtonBindingScope(applicationPath: entry.path)
    }

    /// The binding a press goes by. `scope`: whose bindings (`scopeOfPress`); nil reads
    /// the app in front now. A caller that looks twice for one press (the Logitech probe,
    /// then `InputProcessor`) decides the scope once and passes it to both.
    ///
    /// A standard middle, back or forward press is a press of its Logitech twin too
    /// (`twin(of:)`): set up while the mouse was on its receiver, such a button is stored
    /// under the Logitech code, and over Bluetooth it arrives as the standard button. The
    /// bindings of both codes are ranked together: more modifier keys win, and on a tie the
    /// standard code. A Logitech press goes by the Logitech bindings alone (an app's
    /// binding stored under the standard number replaces the general one of the Logitech
    /// code and gives that button back to the mouse: `ButtonBindingIdentity`).
    func getBestMatchingBinding(
        for event: InputEvent,
        scope: ButtonBindingScope? = nil,
        where predicate: ((ButtonBinding) -> Bool)? = nil
    ) -> ButtonBinding? {
        let scope = scope ?? scopeOfPress(for: event)
        var best: ButtonBinding?
        var bestPriority = Int.min
        Self.rank(getButtonBindings(for: event.type, code: event.code, scope: scope), against: event,
                  where: predicate, best: &best, bestPriority: &bestPriority)
        if let twin = Self.twin(of: event) {
            Self.rank(getButtonBindings(for: twin.type, code: twin.code, scope: scope), against: twin,
                      where: predicate, best: &best, bestPriority: &bestPriority)
        }
        return best
    }

    /// The binding of `bindings` a press of `event` goes by, the bindings of its twin's
    /// code ranked with its own as `getBestMatchingBinding` ranks them.
    static func bestMatch(
        among bindings: [ButtonBinding],
        for event: InputEvent,
        where predicate: ((ButtonBinding) -> Bool)? = nil
    ) -> ButtonBinding? {
        var best: ButtonBinding?
        var bestPriority = Int.min
        rank(bindings, against: event, where: predicate, best: &best, bestPriority: &bestPriority)
        if let twin = twin(of: event) {
            rank(bindings, against: twin, where: predicate, best: &best, bestPriority: &bestPriority)
        }
        return best
    }

    /// The press as a press of its Logitech twin: a standard middle, back or forward
    /// button as the Logitech control it is (`LogiStandardMouseButtonAlias`). Nil for any
    /// other.
    static func twin(of event: InputEvent) -> InputEvent? {
        guard event.type == .mouse, let code = LogiStandardMouseButtonAlias.logitechCode(forNativeButton: event.code) else {
            return nil
        }
        return InputEvent(
            type: .mouse, code: code, modifiers: event.modifiers, phase: event.phase, source: event.source, device: event.device
        )
    }

    /// Takes the binding of `candidates` that `press` matches best when it matches better
    /// than `best` (a tie keeps `best`).
    private static func rank(
        _ candidates: [ButtonBinding],
        against press: InputEvent,
        where predicate: ((ButtonBinding) -> Bool)?,
        best: inout ButtonBinding?,
        bestPriority: inout Int
    ) {
        for binding in candidates {
            guard binding.isEnabled else {
                continue
            }
            if let predicate, !predicate(binding) {
                continue
            }
            guard let priority = binding.triggerEvent.matchPriority(for: press) else {
                continue
            }
            if priority > bestPriority {
                best = binding
                bestPriority = priority
            }
        }
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

        cachedBindings = Self.prepared(Options.shared.buttons.binding)

        // Only what can run is matched (`isRunnable`); the list above keeps every binding.
        cachedBindingsByTriggerKey = Self.table(of: cachedBindings)
        var hasKeyboardTriggers = Self.hasKeyboardTriggers(cachedBindings)

        // The apps with buttons of their own: the general bindings with theirs merged in.
        var appTables: [String: [ButtonBindingTriggerKey: [ButtonBinding]]] = [:]
        var appTriggerKeys: Set<ButtonBindingTriggerKey> = []
        let applications = Options.shared.application.applications
        for index in 0..<applications.count {
            // Two entries of one path (a settings file written by hand, or merged): the one
            // `get(by:)` returns counts, the entry the divert, the ring, the gestures and the
            // scroll engine go by (the last).
            guard let application = applications.get(by: index),
                  applications.get(by: application.path) === application else { continue }
            let own = ApplicationButtons.usable(application.ownButtonBindings, general: Options.shared.buttons.binding)
            guard !own.isEmpty else { continue }
            let merged = ApplicationButtons.merged(general: cachedBindings, own: Self.prepared(own))
            appTables[application.path] = Self.table(of: merged)
            appTriggerKeys.formUnion(own.map(\.triggerKey))
            hasKeyboardTriggers = hasKeyboardTriggers || Self.hasKeyboardTriggers(merged)
        }
        cachedAppBindingsByTriggerKey = appTables
        cachedAppTriggerKeys = appTriggerKeys
        cachedHasKeyboardTriggers = hasKeyboardTriggers

        isDirty = false
    }

    private static func prepared(_ bindings: [ButtonBinding]) -> [ButtonBinding] {
        return bindings.map { binding in
            var b = binding
            b.prepareCustomCache()
            return b
        }
    }

    /// The bindings that can run (`isRunnable`), by trigger.
    private static func table(of bindings: [ButtonBinding]) -> [ButtonBindingTriggerKey: [ButtonBinding]] {
        return Dictionary(grouping: bindings.filter { isRunnable($0.triggerEvent) }, by: \.triggerKey)
    }

    private static func hasKeyboardTriggers(_ bindings: [ButtonBinding]) -> Bool {
        return bindings.contains { $0.isEnabled && $0.triggerEvent.type == .keyboard && isRunnable($0.triggerEvent) }
    }
}
