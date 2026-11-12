//
//  ButtonCore.swift
//  Mos
//  鼠标按钮事件截取与处理核心类
//  Created by Claude on 2025/8/10.
//  Copyright © 2025年 Caldis. All rights reserved.
//
//  Two event taps, both served by the main thread:
//
//  - the buttons tap (the extra mouse buttons), while the cores run;
//  - the keys tap (key down and up), only while it is needed: an enabled binding has a key
//    as its trigger, a button holds a modifier for the keys typed meanwhile, or an action
//    started by a key is still held (`InputProcessor.needsKeyEvents`). `OnDemandKeyTap` makes
//    it at the first need, pauses it between needs and lets it go when the cores stop.
//
//  They were one tap that always listened to the keyboard, so every keystroke of the Mac
//  waited for this app's main thread, also with no key bound at all (the default). Now a
//  stall of the app cannot hold up typing unless the user bound a key.
//

import Cocoa

class ButtonCore {

    // 单例
    static let shared = ButtonCore()
    init() {}

    // 执行状态
    var isActive = false

    // 拦截层
    /// The buttons tap: an `Interceptor` in the app, a double in the tests.
    var dispatchInterceptor: KeyEventTap?
    /// Makes the buttons tap when the core is enabled. The seam: tests pass a double, so
    /// the start, the stop and the restart after a timeout can be tested without a real
    /// event tap.
    var makeButtonsTap: (ButtonCore) throws -> KeyEventTap = { core in
        let interceptor = try Interceptor(
            event: core.dispatchEventMask,
            handleBy: core.buttonEventCallBack,
            listenOn: core.dispatchEventTapLocation,
            placeAt: .tailAppendEventTap,
            for: .defaultTap
        )
        interceptor.onRestart = {
            InputProcessor.shared.clearActiveBindings()
        }
        return interceptor
    }
    // 组合的按钮事件掩码
    let otherDown = CGEventMask(1 << CGEventType.otherMouseDown.rawValue)
    let keyDown = CGEventMask(1 << CGEventType.keyDown.rawValue)
    let otherUp = CGEventMask(1 << CGEventType.otherMouseUp.rawValue)
    let keyUp = CGEventMask(1 << CGEventType.keyUp.rawValue)
    /// The buttons tap.
    var dispatchEventMask: CGEventMask {
        // Primary mouse buttons are intentionally excluded. Scrollio does not allow
        // recording an unmodified primary click, and installing a global tap for
        // those events can disturb applications that manage their own drag state.
        return otherDown | otherUp
    }
    /// The keys tap.
    var keyEventMask: CGEventMask {
        return keyDown | keyUp
    }

    // 在系统处理 Mission Control 等原生鼠标按钮快捷键之前拦截。
    // 未被 Mos 绑定的事件继续向下传递，由系统按原有语义消费。
    let dispatchEventTapLocation = CGEventTapLocation.cgSessionEventTap

    /// The keys tap, made and paused as it is needed. (Settable for the tests, which put
    /// one in that makes doubles.)
    lazy var keyTap: OnDemandKeyTap = OnDemandKeyTap(
        makeTap: { [unowned self] in
            let interceptor = try Interceptor(
                event: self.keyEventMask,
                handleBy: self.keyEventCallBack,
                listenOn: self.dispatchEventTapLocation,
                placeAt: .tailAppendEventTap,
                for: .defaultTap
            )
            interceptor.onRestart = {
                InputProcessor.shared.clearActiveBindings()
            }
            // A restart (after a timeout, or by the tap's keeper) only when the keyboard is
            // still needed; otherwise the tap stays off like a paused one.
            interceptor.shouldRestart = { [weak self] in
                return self?.keyTap.isStillNeededAtRestart() ?? false
            }
            return interceptor
        },
        isNeeded: { InputProcessor.shared.needsKeyEvents }
    )

    // MARK: - 按钮事件处理

    /// One event of either tap: matched against the bindings; a key that passes through gets
    /// the modifiers a button holds.
    private static func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // 跳过 Mos 合成事件, 避免 executeCustom 发出的事件被重复处理
        if event.getIntegerValueField(.eventSourceUserData) == ScrollioEventMarker.syntheticCustom {
            return Unmanaged.passUnretained(event)
        }

        // 使用原始 flags 匹配绑定 (不注入虚拟修饰键, 保证匹配准确)
        let inputEvent = InputEvent(fromCGEvent: event)
        let result = InputProcessor.shared.process(inputEvent)
        switch result {
        case .consumed:
            return nil
        case .passthrough:
            // 注入虚拟修饰键 flags 到 passthrough 事件
            // 使长按鼠标侧键(绑定到修饰键) + 键盘/鼠标输入 = 修饰键组合输入
            let activeFlags = InputProcessor.shared.activeModifierFlags
            let supportsVirtualModifiers =
                type == .keyDown ||
                type == .keyUp
            if activeFlags != 0 && supportsVirtualModifiers {
                event.flags = CGEventFlags(rawValue: event.flags.rawValue | activeFlags)
            }
            return Unmanaged.passUnretained(event)
        }
    }

    /// The buttons tap's callback.
    let buttonEventCallBack: CGEventTapCallBack = { (proxy, type, event, refcon) in
        // Tap 被系统禁用时, 清理活跃绑定状态并直接放行
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            EventTapDisableLog.note(.buttons, type)
            InputProcessor.shared.clearActiveBindings()
            if type == .tapDisabledByTimeout {
                // On again now: until the keeper's next look every button went by unhandled.
                ButtonCore.shared.dispatchInterceptor?.restartAfterTimeout()
            }
            return Unmanaged.passUnretained(event)
        }
        return ButtonCore.handle(type: type, event: event)
    }

    /// The keys tap's callback.
    let keyEventCallBack: CGEventTapCallBack = { (proxy, type, event, refcon) in
        if type == .tapDisabledByUserInput {
            // What the callback gets after the app itself paused this tap, each time the
            // keyboard is no longer needed. Nothing went wrong and nothing is cleared: a
            // clear here would release every held action of the buttons.
            return Unmanaged.passUnretained(event)
        }
        if type == .tapDisabledByTimeout {
            EventTapDisableLog.note(.keys, type)
            InputProcessor.shared.clearActiveBindings()
            // On again now, as the buttons tap.
            ButtonCore.shared.keyTap.restartAfterTimeout()
            return Unmanaged.passUnretained(event)
        }
        return ButtonCore.handle(type: type, event: event)
    }

    // MARK: - 启用和禁用

    // 启用按钮监控
    func enable() {
        if !isActive {
            do {
                dispatchInterceptor = try makeButtonsTap(self)
                isActive = true
                // The keyboard follows the bindings from here on.
                ButtonUtils.shared.onInvalidate = { [weak self] in
                    self?.keyTap.refresh()
                }
                keyTap.enable()
            } catch {
                dispatchInterceptor?.stop()
                dispatchInterceptor = nil
                AppSystemLog.problem("ButtonCore: could not start its event tap: \(error)")
            }
        }
    }

    // 禁用按钮监控
    func disable() {
        if isActive {
            dispatchInterceptor?.stop()
            dispatchInterceptor = nil
            keyTap.disable()
            InputProcessor.shared.clearActiveBindings()
            isActive = false
        }
    }
}

// MARK: - The keys tap

/// The keys tap as its owner uses it: an `Interceptor` in the app, a double in the tests.
protocol KeyEventTap: PointerMotionTap {
    /// macOS turned the tap off after a timeout: on again, unless its restarts are throttled.
    func restartAfterTimeout()
}

extension Interceptor: KeyEventTap {
    func restartAfterTimeout() {
        restartUnlessThrottled(after: .timeout)
    }
}

/// ButtonCore's keys tap, there only while the keyboard is needed.
///
/// - `enable()`: the cores run. The tap is made and started if it is needed now.
/// - `refresh()`: what is needed may have changed (the bindings, a held modifier, a held
///   key). Needed and not running: started at once (made first, if there is none yet).
///   No longer needed: paused on the next turn of the main queue, never inside the call:
///   the caller may be this tap's own callback, and the need may be back by then (a
///   modifier button pressed again).
/// - `disable()`: the cores stop. The tap is switched off and let go; nothing is made
///   again until `enable()`.
///
/// A tap that is off right after it was started is replaced once (as the pointer-movement
/// tap); one that cannot be started is tried again every `retryInterval` while it is needed.
/// Main thread only.
final class OnDemandKeyTap {

    /// Tries to get a running tap each time one is needed: the kept tap (or a new one),
    /// then once more a new one.
    static let attempts = 2
    /// Between two tries while the tap is needed and does not run.
    static let retryInterval: TimeInterval = 5

    private let makeTap: () throws -> KeyEventTap
    private let isNeeded: () -> Bool
    /// Runs the block on the next turn of the main queue. Tests run it by hand.
    private let schedule: (@escaping () -> Void) -> Void
    /// Starts the repeating retry; nil in tests, which try by hand (`retryNow`).
    private let makeRetryTimer: ((@escaping () -> Void) -> Timer)?

    private var tap: KeyEventTap?
    private var retryTimer: Timer?
    private var isPauseScheduled = false
    /// The cores run: only then is a tap ever made.
    private(set) var isEnabled = false
    /// The tap was started and not paused since: it listens (or macOS turned it off and its
    /// own keeper is bringing it back).
    private(set) var isRunning = false
    /// A tap exists (running or paused).
    var hasTap: Bool { return tap != nil }

    init(
        makeTap: @escaping () throws -> KeyEventTap,
        isNeeded: @escaping () -> Bool,
        schedule: @escaping (@escaping () -> Void) -> Void = { block in DispatchQueue.main.async(execute: block) },
        makeRetryTimer: ((@escaping () -> Void) -> Timer)? = { block in
            CommonModesTimer.scheduled(withTimeInterval: OnDemandKeyTap.retryInterval, repeats: true) { _ in block() }
        }
    ) {
        self.makeTap = makeTap
        self.isNeeded = isNeeded
        self.schedule = schedule
        self.makeRetryTimer = makeRetryTimer
    }

    func enable() {
        assertMainThread()
        isEnabled = true
        refresh()
    }

    func disable() {
        assertMainThread()
        isEnabled = false
        cancelRetry()
        dropTap()
        isRunning = false
    }

    func refresh() {
        assertMainThread()
        guard isEnabled else { return }
        if isNeeded() {
            if !isRunning {
                start()
            }
            return
        }
        cancelRetry()
        guard isRunning, !isPauseScheduled else { return }
        isPauseScheduled = true
        schedule { [weak self] in
            self?.pauseIfNoLongerNeeded()
        }
    }

    /// The tap's callback got `tapDisabledByTimeout`.
    func restartAfterTimeout() {
        tap?.restartAfterTimeout()
    }

    /// Asked by the tap while it restarts itself (it is switched off at that moment):
    /// whether to switch it on again. When the keyboard is no longer needed it stays off,
    /// and counts as paused, so the next need starts it.
    func isStillNeededAtRestart() -> Bool {
        let needed = isEnabled && isNeeded()
        if !needed {
            isRunning = false
        }
        return needed
    }

    /// One try of the retry, now (the timer's block; tests call it).
    func retryNow() {
        guard isEnabled, !isRunning, isNeeded() else {
            cancelRetry()
            return
        }
        start()
    }

    // MARK: - Private

    private func pauseIfNoLongerNeeded() {
        isPauseScheduled = false
        guard isEnabled, isRunning, !isNeeded() else { return }
        tap?.pause()
        isRunning = false
    }

    private func start() {
        isRunning = startRunningTap()
        if isRunning {
            cancelRetry()
        } else if retryTimer == nil, let makeRetryTimer {
            retryTimer = makeRetryTimer { [weak self] in
                self?.retryNow()
            }
        }
    }

    /// Starts the kept tap or makes one, and checks that it runs.
    /// - Returns: whether a tap runs.
    private func startRunningTap() -> Bool {
        var droppedKeptTap = false
        for attempt in 1...Self.attempts {
            let current: KeyEventTap
            let isKept = tap != nil
            if let kept = tap {
                do {
                    try kept.start()
                } catch {
                    // Only without the Accessibility access: the stop path runs meanwhile.
                    AppSystemLog.problem("Could not start the keys event tap: \(error)")
                    dropTap()
                    return false
                }
                current = kept
            } else {
                do {
                    current = try makeTap()
                } catch {
                    AppSystemLog.problem("Could not create the keys event tap: \(error)")
                    return false
                }
                tap = current
            }
            if current.isRunning() {
                if attempt > 1 {
                    AppSystemLog.note("The keys event tap was off right after it was started ("
                        + (droppedKeptTap ? "the one kept from an earlier use" : "a new one")
                        + "): made a new one, which runs")
                }
                return true
            }
            droppedKeptTap = droppedKeptTap || isKept
            dropTap()
        }
        AppSystemLog.problem("The keys event tap stays off: it was off right after it was started, and so was a new one. "
            + "Keys bound to actions pass unhandled; trying again every \(Int(Self.retryInterval)) s")
        return false
    }

    /// Switches the tap off and lets it go (`Interceptor.deinit` removes it from the window
    /// server); the next need makes a new one.
    private func dropTap() {
        tap?.stop()
        tap = nil
    }

    private func cancelRetry() {
        retryTimer?.invalidate()
        retryTimer = nil
    }
}
