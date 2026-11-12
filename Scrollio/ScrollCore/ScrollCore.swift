//
//  ScrollCore.swift
//  Mos
//  滚动事件截取与插值计算核心类
//  Created by Caldis on 2017/1/14.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

class ScrollCore: ScrollActionPort {

    // 单例
    static let shared = ScrollCore()
    init() {}
    
    // 执行状态
    var isActive = false
    // 热键数据
    var dashScroll = false
    var dashAmplification = 1.0
    var toggleScroll = false {
        didSet { ScrollPoster.shared.updateShifting(enable: toggleScroll) }
    }
    var blockSmooth = false
    // 非修饰键热键的按下状态跟踪
    var dashKeyHeld = false
    var toggleKeyHeld = false
    var blockKeyHeld = false
    private var dashActionCount = 0
    private var toggleActionCount = 0
    private var blockActionCount = 0
    /// Who moves the page when the trackpad and the wheel overlap. Main thread (scroll tap).
    var handover = ScrollHandover()
    /// The sideways wheel's functions and its log line. Main thread (scroll tap, main queue).
    var thumbWheelEngine = ThumbWheelEngine()
    /// Tells when an app comes to the front, while the core runs (`watchFrontApplication`).
    private var frontApplicationObserver: NSObjectProtocol?
    /// What is done for an app that came to the front. Tests put their own in its place.
    var applicationCameToFront: (NSRunningApplication?) -> Void = { ScrollCore.prepareTrackpadStyle(for: $0) }
#if DEBUG
    /// Tests: receives what a smoothed wheel event would give the poster, instead of the
    /// poster (nothing glides, nothing is posted).
    static var posterInputObserverForTests: ((ScrollPosterInput) -> Void)?
#endif
    // 例外应用数据
    var application: Application?
    var currentApplication: Application? // 用于区分按下热键及抬起时的作用目标
    // 拦截层
    var scrollEventInterceptor: Interceptor?
    var hotkeyEventInterceptor: Interceptor?
    var mouseEventInterceptor: Interceptor?
    /// Creates one of the three event taps. Tests replace it to make a tap fail.
    var makeInterceptor: (CGEventMask, @escaping CGEventTapCallBack, CGEventTapOptions) throws -> Interceptor = { mask, callback, options in
        try Interceptor(
            event: mask,
            handleBy: callback,
            listenOn: .cgAnnotatedSessionEventTap,
            placeAt: .tailAppendEventTap,
            for: options
        )
    }
    // 拦截掩码
    let scrollEventMask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
    let hotkeyEventMask: CGEventMask = {
        let flagsChanged = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let keyDown = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let keyUp = CGEventMask(1 << CGEventType.keyUp.rawValue)
        let otherMouseDown = CGEventMask(1 << CGEventType.otherMouseDown.rawValue)
        let otherMouseUp = CGEventMask(1 << CGEventType.otherMouseUp.rawValue)
        return flagsChanged | keyDown | keyUp | otherMouseDown | otherMouseUp
    }()
    let mouseLeftEventMask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
    
    // MARK: - 滚动事件处理
    let scrollEventCallBack: CGEventTapCallBack = { (proxy, type, event, refcon) in
        _ = refcon
        // Tap 被系统禁用或重启边界时，强制清理 poster 上下文并失效历史异步帧
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            EventTapDisableLog.note(.scroll, type)
            // After a timeout the tap is restarted from here: it goes on again half a second
            // later (`Interceptor.restart`), not at the keeper's next look up to 5 s later.
            // Until it is on the wheel goes by raw (and the other way round with "reverse"
            // on). The restart ends the scroll session itself (onRestart), so it is not ended
            // here as well.
            let restarted = type == .tapDisabledByTimeout
                && (ScrollCore.shared.scrollEventInterceptor?.restartUnlessThrottled() ?? false)
            if !restarted {
                ScrollPoster.shared.stop(.TrackingEnd, reason: .tapRestarted)
            }
            return Unmanaged.passUnretained(event)
        }
        if type != .scrollWheel {
            return Unmanaged.passUnretained(event)
        }
        // 跳过 Mos 自己合成的平滑事件，避免重复进入平滑管线
        if ScrollUtils.shared.isSyntheticSmoothEvent(event) {
#if DEBUG
            ScrollPoster.shared.recordSkippedSyntheticEvent()
#endif
            return Unmanaged.passUnretained(event)
        }
        // 滚动事件
        let scrollEvent = ScrollEvent(with: event)
        let hasVerticalDelta = scrollEvent.Y.valid && scrollEvent.Y.usableValue != 0.0
        let hasHorizontalDelta = scrollEvent.X.valid && scrollEvent.X.usableValue != 0.0
        if hasVerticalDelta || hasHorizontalDelta {
            // 只有真实滚动才会取消 tap replay, 同时触发丢失 mouseUp 的轻量兜底释放。
            InputProcessor.shared.markScrollActionSessionsUsedForScroll()
            InputProcessor.shared.releaseScrollActionMouseSessionsIfPhysicalButtonsAreUp()
        }
        // 不处理触控板
        // 无法区分黑苹果, 因为黑苹果的触控板驱动直接模拟鼠标输入
        // 无法区分 Magic Mouse, 因为其滚动特征与内置的 Trackpad 一致
        if scrollEvent.isTrackpad() {
            // Trackpad and wheel together (ScrollHandover): a finger that begins to scroll
            // stops the wheel's glide; the rest of a trackpad glide the wheel took over is dropped.
            let scrollPhase = event.getDoubleValueField(.scrollWheelEventScrollPhase)
            if ScrollCore.stopWheelGlide(forTrackpadScrollPhase: scrollPhase) {
                ScrollSystemLog.noteFingerTookOverWheelGlide()
            }
            switch ScrollCore.shared.handover.trackpadEvent(
                scrollPhase: scrollPhase,
                momentumPhase: event.getDoubleValueField(.scrollWheelEventMomentumPhase),
                hasDelta: hasVerticalDelta || hasHorizontalDelta
            ) {
            case .swallow:
                return nil
            case .letThroughEndingTakeover(let dropped):
                ScrollSystemLog.noteWheelTookOverGlide(droppedMomentumEvents: dropped)
            case .letThrough:
                break
            }
            if ScrollHandover.carriesTheWheelsDelta(
                momentumPhase: event.getDoubleValueField(.scrollWheelEventMomentumPhase),
                isContinuous: event.getDoubleValueField(.scrollWheelEventIsContinuous),
                hasDelta: hasVerticalDelta || hasHorizontalDelta
            ) {
                // The glide's "ended" that comes with a wheel event: the app gets it to close
                // the glide, without the wheel's delta (that arrives with the wheel event).
                ScrollEvent.clearY(scrollEvent)
                ScrollEvent.clearX(scrollEvent)
                return Unmanaged.passUnretained(event)
            }
            if hasVerticalDelta || hasHorizontalDelta { ScrollSystemLog.notePassthrough(.trackpad) }
            return Unmanaged.passUnretained(event)
        }
        // 当事件来自远程桌面，且其发送的事件 isContinuous=1.0，此时跳过本地平滑
        let remoteSmoothed = ScrollUtils.shared.isRemoteSmoothedEvent(event)
        // The sideways wheel (the thumb wheel of an MX Master, or a wheel that tilts) has its
        // own settings. The tap's run loop source is on the main run loop (in the common modes,
        // so this also runs while a menu is open): Options are read here, on the main thread,
        // as everywhere in this callback; one copy of a small struct, nothing allocated.
        let thumbWheel = Options.shared.thumbWheel
        let sideways = ScrollCore.isSidewaysWheelEvent(
            hasVerticalDelta: hasVerticalDelta,
            hasHorizontalDelta: hasHorizontalDelta,
            remoteSmoothed: remoteSmoothed,
            shiftDown: event.flags.contains(.maskShift)
        )
        // A turn that runs a function (zoom, tabs, ...) is swallowed further down: it is not
        // smoothed and never reaches an app, whatever "Smooth scrolling", an app's rule, the
        // allowlist or Launchpad say.
        let runsThumbWheelFunction = sideways && thumbWheel.function != .scroll
        // Its X deltas as they arrived, before any direction rule, and its own time (for the
        // stepper and the log).
        let thumbWheelEvent = sideways
            ? ThumbWheelEvent(
                axis: scrollEvent.X,
                isContinuous: event.getDoubleValueField(.scrollWheelEventIsContinuous) != 0,
                timestamp: event.timestamp
            )
            : nil
        // A wheel event takes over a trackpad glide that still runs, whether it is smoothed or
        // not: let through raw, it would still move the page against the glide. A turn of the
        // thumb wheel that runs a function moves no page: the glide goes on.
        if (hasVerticalDelta || hasHorizontalDelta) && !runsThumbWheelFunction {
            ScrollCore.shared.handover.wheelEvent()
        }
        if remoteSmoothed {
            ScrollSystemLog.notePassthrough(.remoteSmoothed)
            return Unmanaged.passUnretained(event)
        }
        // 当鼠标输入, 根据需要执行翻转方向/平滑滚动
        // 获取事件目标
        let targetRunningApplication = ScrollUtils.shared.getRunningApplication(from: event)
        // 获取列表中应用程序的列外设置信息
        ScrollCore.shared.application = ScrollUtils.shared.getTargetApplication(from: targetRunningApplication)
        // 平滑/翻转
        var enableSmooth = false,
            enableSmoothVertical = false,
            enableSmoothHorizontal = false,
            enableReverseVertical = false,
            enableReverseHorizontal = false
        var step = Options.shared.scroll.step,
            speed = Options.shared.scroll.speed,
            duration = Options.shared.scroll.durationTransition
        if let targetApplication = ScrollCore.shared.application {
            enableSmooth = targetApplication.isSmooth(ScrollCore.shared.blockSmooth)
            enableSmoothVertical = targetApplication.isSmoothVertical(ScrollCore.shared.blockSmooth)
            enableSmoothHorizontal = targetApplication.isSmoothHorizontal(ScrollCore.shared.blockSmooth)
            enableReverseVertical = targetApplication.isReverseVertical()
            enableReverseHorizontal = targetApplication.isReverseHorizontal()
            step = targetApplication.getStep()
            speed = targetApplication.getSpeed()
            duration = targetApplication.getDuration()
        } else if !Options.shared.application.allowlist {
            enableSmooth = Options.shared.scroll.smooth && !ScrollCore.shared.blockSmooth
            enableSmoothVertical = enableSmooth && Options.shared.scroll.smoothVertical
            enableSmoothHorizontal = enableSmooth && Options.shared.scroll.smoothHorizontal
            let allowReverse = Options.shared.scroll.reverse
            enableReverseVertical = allowReverse && Options.shared.scroll.reverseVertical
            enableReverseHorizontal = allowReverse && Options.shared.scroll.reverseHorizontal
        }
        // Launchpad 激活则强制屏蔽平滑
        if ScrollUtils.shared.getLaunchpadActivity(withRunningApplication: targetRunningApplication) {
            enableSmooth = false
            enableSmoothVertical = false
            enableSmoothHorizontal = false
        }
        let willShiftVerticalToHorizontal = ScrollCore.shared.toggleScroll && hasVerticalDelta && !hasHorizontalDelta
        let verticalReversePreference = willShiftVerticalToHorizontal ? enableReverseHorizontal : enableReverseVertical
        if hasVerticalDelta && verticalReversePreference {
            ScrollEvent.reverseY(scrollEvent)
        }
        // While the sideways wheel scrolls, its "Swap direction" turns it around once more,
        // after "Reverse wheel direction" (global or the app's): X is turned around once or not
        // at all. (Two `reverseX` would not undo each other: each writes the negated original.)
        let flipsHorizontal = ScrollCore.flipsHorizontal(
            reverseRule: enableReverseHorizontal,
            swapsSideways: sideways && thumbWheel.swapsDirection
        )
        if hasHorizontalDelta && flipsHorizontal {
            ScrollEvent.reverseX(scrollEvent)
        }
        if let thumbWheelEvent = thumbWheelEvent {
            // A function's direction is the turn itself, turned around only by "Swap
            // direction": "Reverse wheel direction" (global or the app's) and the allowlist
            // depend on the app under the pointer, and the volume or the desktop must not.
            ScrollCore.shared.thumbWheelEngine.handle(
                thumbWheelEvent, settings: thumbWheel,
                flipped: runsThumbWheelFunction ? thumbWheel.swapsDirection : flipsHorizontal
            )
            if runsThumbWheelFunction {
                // Swallowed: the steps run on the main queue. No glide starts or changes, and
                // the hand-over above left a trackpad glide alone.
                return nil
            }
        }

        let verticalPreference = willShiftVerticalToHorizontal ? enableSmoothHorizontal : enableSmoothVertical
        var shouldSmoothVertical = hasVerticalDelta && verticalPreference
        var shouldSmoothHorizontal = hasHorizontalDelta && enableSmoothHorizontal

        if !enableSmooth {
            shouldSmoothVertical = false
            shouldSmoothHorizontal = false
        }

        var smoothedY = 0.0
        var smoothedX = 0.0

        if shouldSmoothVertical {
            if scrollEvent.Y.usableValue.magnitude < step {
                ScrollEvent.normalizeY(scrollEvent, step)
            }
            smoothedY = scrollEvent.Y.usableValue
        }
        if shouldSmoothHorizontal {
            if scrollEvent.X.usableValue.magnitude < step {
                ScrollEvent.normalizeX(scrollEvent, step)
            }
            smoothedX = scrollEvent.X.usableValue
        }

        let needVerticalPassthrough = hasVerticalDelta && !shouldSmoothVertical
        let needHorizontalPassthrough = hasHorizontalDelta && !shouldSmoothHorizontal
        let needsPassthrough = needVerticalPassthrough || needHorizontalPassthrough
        let shouldSmoothAny = (smoothedY != 0.0) || (smoothedX != 0.0)

        // Whether the poster took the event: it then posts the smoothed axes itself. When it
        // could not (`notTaken` says why), the event goes on as it came, with those axes.
        var taken = false
        var notTaken = ScrollSystemLog.PassthroughReason.noDisplayLink
        if shouldSmoothAny {
            // 每个事件的距离: max(step, |point delta|) × 速度 × 冲刺倍率; 一格为 step × 速度 × 冲刺倍率
            // The sideways wheel scrolls at its own speed on top (1 at the default: the same).
            let input = ScrollCore.posterInput(
                smoothedY: smoothedY, smoothedX: smoothedX, step: step, speed: speed,
                dash: ScrollCore.shared.dashAmplification,
                sidewaysSpeed: sideways ? thumbWheel.speed : 1.0,
                duration: duration
            )
            if !input.isUsable {
                notTaken = .unusableSettings
            } else {
#if DEBUG
                if let observe = ScrollCore.posterInputObserverForTests {
                    observe(input)
                    taken = true
                } else {
                    taken = ScrollPoster.shared.smooth(event: event, input: input)
                }
#else
                taken = ScrollPoster.shared.smooth(event: event, input: input)
#endif
            }
        }

        if needsPassthrough {
            // Reached whenever an axis with a delta is not smoothed: smoothing off for the
            // whole event, or on but not for that axis. The detail is only built for a line
            // that is written (at most one per reason every few seconds).
            ScrollSystemLog.notePassthrough(ScrollCore.passthroughReason(smoothingEnabled: enableSmooth)) {
                ScrollCore.passthroughDetail(
                    smoothingEnabled: enableSmooth,
                    smoothedVertical: shouldSmoothVertical,
                    smoothedHorizontal: shouldSmoothHorizontal,
                    appRule: ScrollCore.shared.application != nil
                )
            }
            // An axis the poster took leaves the event; one it could not take stays in it
            // (cleared all the same, its distance was lost).
            if shouldSmoothVertical && taken {
                ScrollEvent.clearY(scrollEvent)
            }
            if shouldSmoothHorizontal && taken {
                ScrollEvent.clearX(scrollEvent)
            }
            if shouldSmoothAny && !taken {
                ScrollSystemLog.notePassthrough(notTaken)
            }
            return Unmanaged.passUnretained(event)
        }

        if shouldSmoothAny {
            if taken {
                return nil
            } else {
                ScrollSystemLog.notePassthrough(notTaken)
                return Unmanaged.passUnretained(event)
            }
        } else {
            // No delta on either axis: nothing to smooth and nothing to report.
            return Unmanaged.passUnretained(event)
        }
    }

    // MARK: - The sideways wheel (pure)

    /// Whether a wheel event is a sideways wheel event, the only kind the thumb wheel's
    /// settings (`Options.thumbWheel`) apply to: it moves sideways only (a horizontal delta, no
    /// vertical one), it was not smoothed by a remote desktop client, and Shift is not held
    /// (with Shift, macOS and some drivers, Logitech's among them, send the main wheel's turns
    /// as sideways-only events). An event with both deltas is not one. Scrollio's own "scroll
    /// sideways" key needs no rule: the main wheel's events are still vertical at the tap.
    /// Trackpad events and Scrollio's own are let through before this is asked.
    static func isSidewaysWheelEvent(hasVerticalDelta: Bool, hasHorizontalDelta: Bool, remoteSmoothed: Bool, shiftDown: Bool) -> Bool {
        return hasHorizontalDelta && !hasVerticalDelta && !remoteSmoothed && !shiftDown
    }

    /// Whether X of a scrolling event is turned around: by "Reverse wheel direction" (global or
    /// the app's), or by the thumb wheel's "Swap direction" for a sideways event; both together
    /// cancel out. (A function's direction uses "Swap direction" only.)
    static func flipsHorizontal(reverseRule: Bool, swapsSideways: Bool) -> Bool {
        return reverseRule != swapsSideways
    }

    /// What the poster gets for one smoothed wheel event: each axis's distance (max(Step,
    /// |delta|), done before) × Speed × dash, and for a sideways event × the thumb wheel's own
    /// speed as well; the notch the same way. With `sidewaysSpeed` 1 it is exactly what it was
    /// before the thumb wheel had a speed (× 1 changes no Double).
    static func posterInput(smoothedY: Double, smoothedX: Double, step: Double, speed: Double, dash: Double, sidewaysSpeed: Double, duration: Double) -> ScrollPosterInput {
        let gain = speed * dash * sidewaysSpeed
        return ScrollPosterInput(y: smoothedY * gain, x: smoothedX * gain, notch: step * gain, duration: duration)
    }

    /// Why an event with an unsmoothed axis is let through.
    static func passthroughReason(smoothingEnabled: Bool) -> ScrollSystemLog.PassthroughReason {
        return smoothingEnabled ? .axisNotSmoothed : .smoothingOff
    }

    /// The settings behind a passthrough, for the log line only.
    static func passthroughDetail(smoothingEnabled: Bool, smoothedVertical: Bool, smoothedHorizontal: Bool, appRule: Bool) -> String {
        guard smoothingEnabled else {
            return "smooth \(Options.shared.scroll.smooth), paused by key \(ScrollCore.shared.blockSmooth), app rule \(appRule), allowlist \(Options.shared.application.allowlist)"
        }
        return "vertical smoothed \(smoothedVertical), horizontal smoothed \(smoothedHorizontal), Shift to horizontal \(ScrollCore.shared.toggleScroll)"
    }
    
    // MARK: - HID++ 滚动热键处理

    /// 跟踪当前由哪个 HID++ 按键码激活了热键状态
    /// key-up 时按 code 清除, 不依赖当前 app 的热键配置, 避免跨应用释放时状态卡死
    private var hidDashHeldCode: UInt16?
    private var hidToggleHeldCode: UInt16?
    private var hidBlockHeldCode: UInt16?

    func handleScrollAction(role: ScrollRole, isDown: Bool) {
        assertMainThread()
        switch role {
        case .dash:
            dashActionCount = updatedActionCount(dashActionCount, isDown: isDown)
            refreshDashState()
        case .toggle:
            toggleActionCount = updatedActionCount(toggleActionCount, isDown: isDown)
            refreshToggleState()
        case .block:
            blockActionCount = updatedActionCount(blockActionCount, isDown: isDown)
            refreshBlockState()
        }
    }

    private func updatedActionCount(_ count: Int, isDown: Bool) -> Int {
        if isDown {
            return count + 1
        }
        return max(0, count - 1)
    }

    private func refreshDashState() {
        dashScroll = dashKeyHeld || dashActionCount > 0
        dashAmplification = dashScroll ? 5.0 : 1.0
    }

    private func refreshToggleState() {
        toggleScroll = toggleKeyHeld || toggleActionCount > 0
    }

    private func refreshBlockState() {
        blockSmooth = blockKeyHeld || blockActionCount > 0
    }

    /// 处理来自 Logitech HID++ 的按键事件, 匹配 dash/toggle/block 滚动热键
    @discardableResult
    func handleScrollHotkey(code: UInt16, isDown: Bool) -> Bool {
        assertMainThread()
        // Key-up: 按跟踪的 code 清除状态 (不依赖当前 app 配置, 防止焦点切换导致状态卡死)
        if !isDown {
            var matched = false
            if hidDashHeldCode == code {
                dashKeyHeld = false
                hidDashHeldCode = nil
                refreshDashState()
                matched = true
            }
            if hidToggleHeldCode == code {
                toggleKeyHeld = false
                hidToggleHeldCode = nil
                refreshToggleState()
                matched = true
            }
            if hidBlockHeldCode == code {
                blockKeyHeld = false
                hidBlockHeldCode = nil
                refreshBlockState()
                matched = true
            }
            return matched
        }

        // Key-down: 刷新前台应用上下文 (HID++ 事件不经过滚动事件路径, application 可能陈旧)
        application = ScrollUtils.shared.getTargetApplication(from: NSWorkspace.shared.frontmostApplication)

        let dashHotkey = ScrollUtils.shared.optionsDashKey(application: application)
        let toggleHotkey = ScrollUtils.shared.optionsToggleKey(application: application)
        let blockHotkey = ScrollUtils.shared.optionsBlockKey(application: application)

        var matched = false

        if let h = dashHotkey, h.type == .mouse, h.code == code {
            dashKeyHeld = true
            hidDashHeldCode = code
            refreshDashState()
            matched = true
        }
        if let h = toggleHotkey, h.type == .mouse, h.code == code {
            toggleKeyHeld = true
            hidToggleHeldCode = code
            refreshToggleState()
            matched = true
        }
        if let h = blockHotkey, h.type == .mouse, h.code == code {
            blockKeyHeld = true
            hidBlockHeldCode = code
            refreshBlockState()
            matched = true
        }

        return matched
    }

    // MARK: - 热键事件处理 (CGEventTap)
    let hotkeyEventCallBack: CGEventTapCallBack = { (proxy, type, event, refcon) in
        // 跳过 Mos 合成事件, 避免 executeCustom 的 flagsChanged 误触发 dash/toggle/block
        if event.getIntegerValueField(.eventSourceUserData) == ScrollioEventMarker.syntheticCustom {
            return nil  // listenOnly tap 返回值无影响
        }
        if type == .keyDown || type == .flagsChanged || type == .otherMouseDown,
           ScrollCore.shared.shouldDeferToScrollActionButtonBinding(event) {
            // Mos Scroll 动作由 ButtonCore/InputProcessor 接管。若同一触发器也被旧滚动
            // 热键配置使用, listenOnly tap 不能再创建第二份 held 状态。
            return nil
        }

        let keyCode = event.keyCode
        let mouseButton = ScrollCore.mouseButtonNumber(fromField: event.getIntegerValueField(.mouseEventButtonNumber))

        // 判断事件类型
        let isMouseEvent = (type == .otherMouseDown || type == .otherMouseUp)
        let isKeyDown = (type == .keyDown || type == .otherMouseDown)
        let isKeyUp = (type == .keyUp || type == .otherMouseUp)
        let isFlagsChanged = (type == .flagsChanged)

        // 记录按键时的目标应用
        if (event.isKeyDown || isKeyDown) && ScrollCore.shared.currentApplication == nil {
            ScrollCore.shared.currentApplication = ScrollCore.shared.application
        }

        // 获取配置的热键
        let dashHotkey = ScrollUtils.shared.optionsDashKey(application: ScrollCore.shared.application)
        let toggleHotkey = ScrollUtils.shared.optionsToggleKey(application: ScrollCore.shared.application)
        let blockHotkey = ScrollUtils.shared.optionsBlockKey(application: ScrollCore.shared.application)

        // 检测热键是否匹配并更新状态
        func checkAndUpdateHotkey(_ hotkey: ScrollHotkey?, keyHeld: inout Bool) -> Bool? {
            guard let hotkey = hotkey else { return nil }

            if hotkey.isModifierKey {
                // 修饰键：通过 flagsChanged 事件检测
                if isFlagsChanged && keyCode == hotkey.code {
                    return event.flags.contains(hotkey.modifierMask)
                }
            } else if hotkey.matches(event, keyCode: keyCode, mouseButton: mouseButton, isMouseEvent: isMouseEvent) {
                // 普通按键或鼠标按键
                if isKeyDown { keyHeld = true }
                if isKeyUp { keyHeld = false }
                return keyHeld
            }
            return nil
        }

        // Dash
        if let isPressed = checkAndUpdateHotkey(dashHotkey, keyHeld: &ScrollCore.shared.dashKeyHeld) {
            ScrollCore.shared.dashKeyHeld = isPressed
            ScrollCore.shared.refreshDashState()
        }
        // Toggle
        if let isPressed = checkAndUpdateHotkey(toggleHotkey, keyHeld: &ScrollCore.shared.toggleKeyHeld) {
            ScrollCore.shared.toggleKeyHeld = isPressed
            ScrollCore.shared.refreshToggleState()
        }
        // Block
        if let isPressed = checkAndUpdateHotkey(blockHotkey, keyHeld: &ScrollCore.shared.blockKeyHeld) {
            ScrollCore.shared.blockKeyHeld = isPressed
            ScrollCore.shared.refreshBlockState()
        }

        // 处理抬起时焦点 App 变化
        let isAppTargetChanged = ScrollCore.shared.currentApplication != ScrollCore.shared.application
        let isAnyKeyUp = event.isKeyUp || isKeyUp
        if isAppTargetChanged && isAnyKeyUp {
            // 重置按键状态
            ScrollCore.shared.dashKeyHeld = false
            ScrollCore.shared.toggleKeyHeld = false
            ScrollCore.shared.blockKeyHeld = false
            ScrollCore.shared.refreshDashState()
            ScrollCore.shared.refreshToggleState()
            ScrollCore.shared.refreshBlockState()
            // 并更新记录器
            ScrollCore.shared.currentApplication = nil
        }
        // 不返回原始事件
        return nil
    }

    /// The button number of a mouse event from its `mouseEventButtonNumber` field: 0...255.
    /// CoreGraphics keeps the number in 8 bits and reads it back signed, so 128...255 come
    /// back as -128...-1, and `UInt16(_:)` of a negative number traps: an other-button event
    /// that another program made up with such a number crashed the app, each time. The low
    /// 8 bits are the number that was set (200 reads back as -56).
    static func mouseButtonNumber(fromField value: Int64) -> UInt16 {
        return UInt16(UInt8(truncatingIfNeeded: value))
    }

    private func shouldDeferToScrollActionButtonBinding(_ event: CGEvent) -> Bool {
        let inputEvent = InputEvent(fromCGEvent: event)
        return ButtonUtils.shared.getBestMatchingBinding(
            for: inputEvent,
            where: { ShortcutExecutor.isScrollActionIdentifier($0.systemShortcutName) }
        ) != nil
    }
    
    // MARK: - 鼠标事件处理
    let mouseLeftEventCallBack: CGEventTapCallBack = { (proxy, type, event, refcon) in
        // 如果点击左键则停止滚动
        ScrollPoster.shared.stop(reason: .leftClick)
        return nil
    }

    /// Wheel to trackpad: a finger that begins to scroll on the trackpad while Scrollio's glide
    /// from the wheel still runs stops that glide at once, as a left click does, so that only
    /// the finger moves the page. Main thread.
    /// - Returns: whether a glide was stopped.
    @discardableResult
    static func stopWheelGlide(forTrackpadScrollPhase scrollPhase: Double, poster: ScrollPoster = .shared) -> Bool {
        guard ScrollHandover.fingerTakesOver(scrollPhase: scrollPhase), poster.isGliding else { return false }
        poster.stop(reason: .fingerOnTrackpad)
        return true
    }
    
    // MARK: - The app in front

    /// With "Trackpad-style scrolling" on for an app, its kind (Chromium-based or not) is
    /// asked for when it comes to the front, so that the first scroll in it is already sent
    /// in the right form (`ScrollUtils.applicationCameToFront`). Nothing is asked while the
    /// switch is off for that app. Main thread.
    static func prepareTrackpadStyle(for application: NSRunningApplication?, utils: ScrollUtils = .shared) {
        guard let application = application else { return }
        let rule = utils.getTargetApplication(from: application)
        utils.applicationCameToFront(
            bundleIdentifier: application.bundleIdentifier,
            bundleURL: application.bundleURL,
            trackpadStyleOn: ScrollPoster.trackpadStyleIsOn(application: rule, global: Options.shared.scroll)
        )
    }

    /// Starts telling `applicationCameToFront` about each app that comes to the front, the
    /// one in front now first. While the core runs (`enable`, `disable`).
    func watchFrontApplication(center: NotificationCenter = NSWorkspace.shared.notificationCenter,
                               frontmost: NSRunningApplication? = NSWorkspace.shared.frontmostApplication) {
        stopWatchingFrontApplication(center: center)
        frontApplicationObserver = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            self?.applicationCameToFront(note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
        }
        applicationCameToFront(frontmost)
    }

    func stopWatchingFrontApplication(center: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        if let observer = frontApplicationObserver {
            center.removeObserver(observer)
            frontApplicationObserver = nil
        }
    }

    // MARK: - 事件运行管理
    // 启动
    func enable() {
        // Guard
        if isActive { return }
        isActive = true
        // 启动事件拦截层
        do {
            scrollEventInterceptor = try makeInterceptor(scrollEventMask, scrollEventCallBack, .defaultTap)
            scrollEventInterceptor?.onRestart = {
                ScrollPoster.shared.stop(.TrackingEnd, reason: .tapRestarted)
            }
            hotkeyEventInterceptor = try makeInterceptor(hotkeyEventMask, hotkeyEventCallBack, .listenOnly)
            mouseEventInterceptor = try makeInterceptor(mouseLeftEventMask, mouseLeftEventCallBack, .listenOnly)
            // 初始化滚动事件发送器
            ScrollPoster.shared.create()
            ScrollPoster.shared.startKeeper()
            watchFrontApplication()
        } catch {
            AppSystemLog.problem("ScrollCore: could not start its event taps: \(error)")
            // Roll back: without its taps the core must not count as active, or every later
            // enable() returns early and scrolling stays unhandled until the app restarts.
            // A tap that was already created is stopped and released here as well.
            // (If the accessibility permission is the reason, the permission-lost handler has
            // already run disable() and this call is a no-op.)
            disable()
        }
    }
    // 停止
    func disable() {
        // Guard
        if !isActive {return}
        isActive = false
        // 停止滚动事件发送器
        ScrollPoster.shared.stop()
        ScrollPoster.shared.stopKeeper()
        stopWatchingFrontApplication()
        // 停止截取事件
        scrollEventInterceptor?.stop()
        hotkeyEventInterceptor?.stop()
        mouseEventInterceptor?.stop()
        // 显式释放, 避免旧 tap 残留在对象图中
        scrollEventInterceptor = nil
        hotkeyEventInterceptor = nil
        mouseEventInterceptor = nil
        releaseHeldScrollKeys()
        // Without the tap the end of a glide is not seen: the next start knows of none.
        handover = ScrollHandover()
        // Steps of the thumb wheel not yet run are dropped; the next turn starts a new roll.
        thumbWheelEngine.reset()
    }

    /// The settings were replaced as a whole (a settings file was imported). Everything
    /// else here reads the settings at each event; two things are remembered between
    /// events and may no longer be true: the per-app entry of the app scrolled in last
    /// (the list was replaced, that object is gone from it) and the hold keys that are
    /// down (they may be other keys now, whose release would not be seen as theirs). Both
    /// are forgotten, and steps of the thumb wheel not yet run are dropped; the next
    /// wheel event looks the app up again. Not on the event path. Main thread.
    func settingsWereReplaced() {
        assertMainThread()
        application = nil
        releaseHeldScrollKeys()
        thumbWheelEngine.reset()
    }

    /// Forgets every scroll key held down (the keyboard and mouse keys of the Scrolling tab,
    /// and those that arrive over HID++). Without the taps their release is never seen: sleep,
    /// Pause or lost Accessibility access while such a key was down left fast scrolling on,
    /// or smoothing paused, until that key was pressed again. Held Scrollio scroll actions of
    /// button bindings are counted apart and released by ButtonCore.
    private func releaseHeldScrollKeys() {
        dashKeyHeld = false
        toggleKeyHeld = false
        blockKeyHeld = false
        hidDashHeldCode = nil
        hidToggleHeldCode = nil
        hidBlockHeldCode = nil
        currentApplication = nil
        refreshDashState()
        refreshToggleState()
        refreshBlockState()
    }
}
