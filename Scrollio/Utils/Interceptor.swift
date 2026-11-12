//
//  Interceptor.swift
//  Mos
//  事件截取工具函数
//  Created by Caldis on 2018/3/18.
//  Copyright © 2018年 Caldis. All rights reserved.
//

import Cocoa

/// The system calls an `Interceptor` makes. The app uses `live`; a test passes its own and
/// so makes an Interceptor without a real event tap and without Accessibility access.
struct EventTapSystem {
    var create: (_ tap: CGEventTapLocation, _ place: CGEventTapPlacement, _ options: CGEventTapOptions,
                 _ mask: CGEventMask, _ callback: CGEventTapCallBack) -> CFMachPort?
    var enable: (_ tap: CFMachPort, _ enable: Bool) -> Void
    var isEnabled: (_ tap: CFMachPort) -> Bool
    /// Whether the app has Accessibility access.
    var isTrusted: () -> Bool

    static let live = EventTapSystem(
        create: { tap, place, options, mask, callback in
            CGEvent.tapCreate(tap: tap, place: place, options: options, eventsOfInterest: mask, callback: callback, userInfo: nil)
        },
        enable: { tap, enable in CGEvent.tapEnable(tap: tap, enable: enable) },
        isEnabled: { tap in CGEvent.tapIsEnabled(tap: tap) },
        isTrusted: { AXIsProcessTrusted() }
    )
}

class Interceptor {

    private var keeper: Timer?
    private var _eventTapRef: CFMachPort?
    private var _runLoopSourceRef: CFRunLoopSource?
    /// What this tap listens to, for the log.
    let kind: EventTapKind
    private let system: EventTapSystem

    /// keeper 触发的自动重启时间戳, 仅保留冷却窗口内的记录
    /// Seconds of `monotonicNow`, never the wall clock: set back by N seconds (by hand, or a
    /// time sync), the wall clock kept a tap that was restarted three times off for N + 60 s.
    private var autoRestartHistory: [TimeInterval] = []
    /// The restarts of this tap are refused by the throttle; it is off. Cleared when a
    /// restart is admitted again, and when the tap is stopped or paused on purpose.
    private(set) var restartsThrottled = false

    // 防自锁: 主线程被阻塞时 (如 TCC 权限弹窗挂起同步文件调用), active tap 无响应,
    // 系统超时禁用 tap 后输入才恢复; keeper 若盲目重启会把刚恢复的输入再次冻住,
    // 用户永远点不到弹窗. 窗口期内重启达到上限即进入冷却, 让系统输入保持可用.
    static let autoRestartWindow: TimeInterval = 60
    static let autoRestartLimit = 3
    /// A restarted tap goes on again after this long (`restart`).
    static let restartDelay: TimeInterval = 0.5

    /// The clock of the restart throttle: seconds since the Mac started, never set back or
    /// forward.
    static func monotonicNow() -> TimeInterval {
        return ProcessInfo.processInfo.systemUptime
    }

    /// 纯函数: 窗口期内自动重启次数达到上限 → 冷却 (跳过本轮重启)
    static func isAutoRestartThrottled(history: [TimeInterval], now: TimeInterval) -> Bool {
        let windowStart = now - autoRestartWindow
        return history.filter { $0 > windowStart }.count >= autoRestartLimit
    }

    /// Counts one automatic restart unless the throttle refuses it: drops the entries that
    /// left the window, and adds `now` when the restart may go ahead.
    static func admitAutoRestart(history: inout [TimeInterval], now: TimeInterval) -> Bool {
        history.removeAll { now - $0 >= autoRestartWindow }
        guard !isAutoRestartThrottled(history: history, now: now) else { return false }
        history.append(now)
        return true
    }

    /// 重启时的额外清理操作 (由调用方注入, 避免 Interceptor 耦合特定子系统)
    /// 注意: 闭包不应捕获 Interceptor 实例, 否则会形成循环引用
    var onRestart: (() -> Void)?
    /// 控制是否继续执行自动重启逻辑 (默认 true)
    var shouldRestart: (() -> Bool)?
    
    // 可访问对象只读
    public var eventTapRef: CFMachPort? { _eventTapRef }
    public var runLoopSourceRef: CFRunLoopSource? { _runLoopSourceRef }
    
    init(event mask: CGEventMask, handleBy eventHandler: @escaping CGEventTapCallBack, listenOn eventTap: CGEventTapLocation, placeAt eventPlace: CGEventTapPlacement, for behaver: CGEventTapOptions, system: EventTapSystem = .live) throws {
        // 创建拦截层
        kind = EventTapKind.of(mask: mask)
        self.system = system
        guard let tap = system.create(eventTap, eventPlace, behaver, mask, eventHandler) else {
            AppSystemLog.problem("Could not create the \(kind.rawValue) event tap")
            throw InterceptorError.eventTapCreationFailed
        }
        _eventTapRef = tap
        _runLoopSourceRef = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        // 启动
        try start()
    }
    
    deinit {
        // 先停止所有操作
        stop()
        // 清理 event tap
        if let tap = _eventTapRef {
            system.enable(tap, false)
            // CoreGraphics 内部持有该 CFMachPort 的引用, 仅释放引用不会销毁它; 不调用
            // CFMachPortInvalidate 的话, WindowServer 会保留这个 (已禁用的) tap 注册直到
            // 进程退出。ScrollCore/ButtonCore 每次休眠唤醒都重建 Interceptor, 累积的僵尸
            // 注册会拖慢全系统输入 (#970)。
            CFMachPortInvalidate(tap)
            _eventTapRef = nil
        }
        // 清理 run loop source
        if let source = _runLoopSourceRef {
            if CFRunLoopContainsSource(CFRunLoopGetCurrent(), source, .commonModes) {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
            _runLoopSourceRef = nil
        }
    }
}

// MARK: - Error Type
extension Interceptor {
    enum InterceptorError: Error {
        case eventTapCreationFailed
        case eventTapEnableFailed
    }
}

// MARK: - 开关
extension Interceptor {
    @objc public func start() throws {
        // 创建拦截层
        guard let tap = _eventTapRef, let source = _runLoopSourceRef else {
            throw InterceptorError.eventTapEnableFailed
        }
        // 权限已被撤销时, 不启用 tap, 避免僵尸 tap 吞没系统事件
        guard system.isTrusted() else {
            NotificationCenter.default.post(name: .scrollioAccessibilityPermissionLost, object: nil)
            throw InterceptorError.eventTapEnableFailed
        }
        // 确保 source 没有被重复添加
        if !CFRunLoopContainsSource(CFRunLoopGetCurrent(), source, .commonModes) {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        // 启动拦截层
        system.enable(tap, true)
        // 启动守护 (also while a menu is open: see CommonModesTimer)
        Self.replaceKeeper(&keeper, with: CommonModesTimer.scheduled(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.keeperLook()
        })
    }

    /// One look of the keeper, every 5 s while the tap is started.
    func keeperLook() {
        // 权限被撤销时, 主动停止 tap 并通知, 不等 restart 判断
        guard system.isTrusted() else {
            stop()
            onRestart?()
            NotificationCenter.default.post(name: .scrollioAccessibilityPermissionLost, object: nil)
            return
        }
        if !isRunning() {
            restartUnlessThrottled(after: .foundOff)
        }
    }

    /// Why an automatic restart was asked for.
    enum RestartCause: String {
        /// macOS turned the tap off because a callback took too long (`tapDisabledByTimeout`).
        case timeout = "macOS turned it off after a timeout"
        /// The keeper found the tap off.
        case foundOff = "the keeper found it off"
    }

    /// An automatic restart: the keeper found the tap off, or the system turned it off
    /// because a callback took too long (`tapDisabledByTimeout`, handled in the callback so
    /// the tap is not left off until the keeper's next look, up to 5 s later). Both go
    /// through the same throttle.
    /// - Returns: false when the throttle refused it.
    @discardableResult
    func restartUnlessThrottled(after cause: RestartCause = .timeout) -> Bool {
        guard Self.admitAutoRestart(history: &autoRestartHistory, now: Self.monotonicNow()) else {
            if !restartsThrottled {
                setRestartsThrottled(true)
                AppSystemLog.problem(Self.throttledLine(kind: kind))
            }
            return false
        }
        if restartsThrottled {
            setRestartsThrottled(false)
        }
        AppSystemLog.note(Self.restartLine(kind: kind, cause: cause, restartsInWindow: autoRestartHistory.count))
        restart()
        return true
    }

    static func restartLine(kind: EventTapKind, cause: RestartCause, restartsInWindow: Int) -> String {
        return "Restarting the \(kind.rawValue) event tap: \(cause.rawValue) "
            + "(restart \(restartsInWindow) of \(autoRestartLimit) allowed within \(Int(autoRestartWindow)) s)"
    }

    static func throttledLine(kind: EventTapKind) -> String {
        return "Not restarting the \(kind.rawValue) event tap: it was restarted \(autoRestartLimit) times "
            + "within \(Int(autoRestartWindow)) s. It stays off until that time has passed, so input stays usable; "
            + "the keeper tries again every 5 s"
    }

    // MARK: Restarts refused by the throttle

    /// Posted (main queue, object nil) when a tap's restarts started or stopped being refused
    /// by the throttle. The status item follows it: while a tap stays off, Scrollio does not
    /// work although it looks as if it did.
    static let restartThrottleDidChangeNotification = Notification.Name("ScrollioEventTapRestartThrottleDidChange")

    /// The taps whose restarts the throttle refuses now. Main thread only, as the taps.
    private static var throttledTaps = ThrottledTaps()

    /// Some event tap is off and its restarts are refused until the throttle's window passed.
    static var hasThrottledTap: Bool {
        return !throttledTaps.isEmpty
    }

    private func setRestartsThrottled(_ throttled: Bool) {
        restartsThrottled = throttled
        guard Self.throttledTaps.set(throttled, for: ObjectIdentifier(self)) else { return }
        // Later, never from inside a tap callback.
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.restartThrottleDidChangeNotification, object: nil)
        }
    }

    /// The set of taps whose restarts are refused.
    struct ThrottledTaps {
        private var taps = Set<ObjectIdentifier>()

        var isEmpty: Bool { taps.isEmpty }

        /// - Returns: whether the set changed.
        mutating func set(_ throttled: Bool, for tap: ObjectIdentifier) -> Bool {
            if throttled {
                return taps.insert(tap).inserted
            }
            return taps.remove(tap) != nil
        }
    }

    /// Installs a keeper timer, invalidating the one it replaces. A replaced timer that is
    /// still scheduled keeps firing: a second start() used to leave the first repeating
    /// keeper running for as long as the Interceptor lived.
    static func replaceKeeper(_ keeper: inout Timer?, with timer: Timer?) {
        keeper?.invalidate()
        keeper = timer
    }
    
    public func stop() {
        endThrottleOnPurpose()
        stop(removeFromRunLoop: true)
    }

    public func pause() {
        endThrottleOnPurpose()
        stop(removeFromRunLoop: false)
    }

    /// Stopped or paused on purpose: off because it should be, not because its restarts are
    /// refused.
    private func endThrottleOnPurpose() {
        if restartsThrottled {
            setRestartsThrottled(false)
        }
    }

    private func stop(removeFromRunLoop: Bool) {
        // 停止守护
        Self.replaceKeeper(&keeper, with: nil)
        // 关闭拦截层
        if let tap = _eventTapRef, let source = _runLoopSourceRef {
            system.enable(tap, false)
            if removeFromRunLoop, CFRunLoopContainsSource(CFRunLoopGetCurrent(), source, .commonModes) {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
        }
    }
}

// MARK: - 状态
extension Interceptor {
    public func isRunning() -> Bool {
        if let tap = _eventTapRef {
            return system.isEnabled(tap)
        } else {
            return false
        }
    }
    
    /// Switches the tap off, lets its owner clean up (`onRestart`) and switches it on again
    /// `restartDelay` later (not at once: the tap stays off for that half second, and the
    /// events it listens to go by untouched).
    public func restart() {
        // 权限已被撤销时, 不再尝试重新启用 tap
        guard system.isTrusted() else {
            stop()
            onRestart?()
            NotificationCenter.default.post(name: .scrollioAccessibilityPermissionLost, object: nil)
            return
        }
        stop(removeFromRunLoop: false)
        onRestart?()
        guard shouldRestart?() ?? true else { return }
        // 使用 closure timer 避免 @objc throws 方法作为 selector 的 ObjC bridge 问题
        Self.replaceKeeper(&keeper, with: CommonModesTimer.scheduled(withTimeInterval: Self.restartDelay, repeats: false) { [weak self] _ in
            try? self?.start()
        })
    }
}
