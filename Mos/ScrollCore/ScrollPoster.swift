//
//  ScrollPoster.swift
//  Mos
//
//  Created by Caldis on 2020/12/3.
//  Copyright © 2020 Caldis. All rights reserved.
//

import Cocoa
import os

/// One wheel event for ScrollPoster, already resolved by ScrollCore (speed, tuning, dash).
struct ScrollPosterInput {
    /// Signed distance to add per axis (px).
    var y: Double
    var x: Double
    /// Distance of one notch per axis at the current speed and multipliers (px), for the lead cap floor.
    var notch: (y: Double, x: Double)
    /// Per-frame interpolation factor at 60 Hz.
    var duration: Double
    /// Skip ScrollFilter (see ScrollMotion.shouldBypassFilter).
    var bypassFilter: Bool
    /// Glide after a flick; nil = off (scrolling and posting exactly as without momentum).
    var momentum: ScrollMomentumSettings? = nil
    /// Vertical wheel speed in lines per second (ScrollSpinTracker), for the fling gain.
    var lineRate = 0.0
    /// The vertical wheel spins freely (latched): it has its own inertia.
    var isFreeSpin = false
    /// Cmd, Ctrl or Option is held (zooming and other modified scrolling).
    var modifiersHeld = false
    /// Post the horizontal input as a phased gesture (began / changed / ended, no momentum),
    /// so apps run their interactive back/forward swipe.
    var pageSwipe = false
}

/// One scroll event as ScrollPoster sends it.
struct ScrollOutgoingFrame: Equatable {
    /// Pixel deltas; whole numbers when `precise`.
    var y: Double
    var x: Double
    /// Line deltas (`precise` only).
    var linesY: Int64 = 0
    var linesX: Int64 = 0
    /// Phase field values; nil leaves the phase fields of the copied wheel event alone.
    var scrollPhase: Double? = nil
    var momentumPhase: Double? = nil
    /// Whole pixels with matching line and fixed-point deltas and a fresh timestamp.
    /// false = the classic posting: only the point delta is written (CoreGraphics drops its
    /// fraction), and line delta and timestamp stay those of the copied wheel event.
    var precise = false

    /// Pixels per line of the fixed-point and line deltas.
    static let pixelsPerLine = 10.0

    func write(to event: CGEvent, now: UInt64 = mach_absolute_time()) {
        if let scrollPhase = scrollPhase, let momentumPhase = momentumPhase {
            event.setDoubleValueField(.scrollWheelEventScrollPhase, value: scrollPhase)
            event.setDoubleValueField(.scrollWheelEventMomentumPhase, value: momentumPhase)
        }
        guard precise else {
            event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: y)
            event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: x)
            // 是否连续滚动: 始终为 1.0
            event.setDoubleValueField(.scrollWheelEventIsContinuous, value: 1.0)
            return
        }
        // The order matters: writing a line delta makes CoreGraphics derive the fixed-point
        // and point deltas from it, so the line deltas go first.
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: linesY)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: linesX)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: y / Self.pixelsPerLine)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: x / Self.pixelsPerLine)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(y))
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(x))
        event.setDoubleValueField(.scrollWheelEventIsContinuous, value: 1.0)
        event.timestamp = ScrollEventClock.timestamp(now: now, like: event.timestamp)
    }
}

/// The display link found the motion finished and asks the main thread to end the session.
struct ScrollStopRequest: Equatable {
    /// Phase to end with (`ScrollPoster.stop(_:)`).
    let phase: Phase
    /// The wheel input the request was made after (`ScrollPoster.inputSequence`).
    let inputSequence: UInt64
}

class ScrollPoster {

    // 单例
    static let shared = ScrollPoster()
    /// The shared poster uses the shared phase machine and dispatch context; tests pass their own.
    init(phases: ScrollPhase = .shared, dispatchContext: ScrollDispatchContext = .shared) {
        self.phases = phases
        self.dispatchContext = dispatchContext
        NSLog("Module initialized: ScrollPoster")
    }

    // 阶段状态机
    private let phases: ScrollPhase
    // 插值器
    private let filter = ScrollFilter()
    // 发送器
    private var poster: CVDisplayLink?
    // 滚动数据
    private var current = (y: 0.0, x: 0.0)  // 当前滚动距离
    private var delta = (y: 0.0, x: 0.0)  // 滚动方向记录
    private var buffer = (y: 0.0, x: 0.0)  // 滚动缓冲距离
    // 滚动配置
    private var shifting = false
    private var duration = Options.shared.scroll.durationTransition
    private var bypassFilter = false
    // 领先量限制 (buffer - current), 滚轮停下后滑行尽快结束
    private var leadLimiterY = ScrollLeadLimiter()
    private var leadLimiterX = ScrollLeadLimiter()
    // 当前手势的发送方式, 每次滚轮输入时确定; 默认 (momentum 关闭) 即原有行为
    private var gesture = GestureMode()
    // 惯性滑行 (仅竖向滚轮), 在插值之下运行: 每帧位移不小于滑行位移
    private var coast = ScrollMomentum()
    // 松手判定间隔 (见 ScrollMomentum.releaseGap), 精确模式下取代 manualContinuationThreshold
    private var releaseGap = ScrollMomentum.releaseGapRange.upperBound
    // 亚像素 / 亚行余量 (按输出轴), 精确模式下发送整数像素
    private var pixelCarry = (y: ScrollSubpixelCarry(), x: ScrollSubpixelCarry())
    private var lineCarry = (y: ScrollSubpixelCarry(), x: ScrollSubpixelCarry())
    // 上一帧的显示时间 (mach host time), 用于按真实帧间隔换算插值系数; 0 表示新会话
    private var lastFrameHostTime: UInt64 = 0
    // 输入节奏追踪
    private var lastManualEventTime: CFTimeInterval = 0.0
    private var manualInputEnded = true
    private var momentumActive = false
    private var momentumEndScheduledTime: CFTimeInterval? = nil
    private var trackingEndScheduledTime: CFTimeInterval? = nil
    // 阈值: 鼠标滚轮事件间隔低于 continuationThreshold 视为持续跟随
    //      介于 continuationThreshold 与 separationThreshold 之间模拟惯性衔接
    private let manualContinuationThreshold: CFTimeInterval = 0.18
    private let manualSeparationThreshold: CFTimeInterval = 0.45
    private let trackingEndAdvance: CFTimeInterval = 0.04
    private let momentumEndDelay: CFTimeInterval = 0.13
    // Ending a session from the display link (see `displayLinkFrameLocked`)
    /// Counts wheel inputs; a stop the display link asked for is dropped when it is stale.
    private var inputSequence: UInt64 = 0
    /// Input sequence of the stop request already handed to the main thread; nil = none yet.
    private var requestedStopSequence: UInt64?
    // 状态锁和投递上下文
    private var stateLock = os_unfair_lock_s()
    private let dispatchContext: ScrollDispatchContext
    // 滚动配置快照: 主线程在 update 时捕获, CVDisplayLink 线程只读, 避免热路径跨线程读 Options/ScrollCore
    private struct ConfigSnapshot {
        var simTrackpadEnabled: Bool
        var deadZone: Double
    }
    private var config = ConfigSnapshot(simTrackpadEnabled: false, deadZone: 1.0)
    /// How the current gesture is sent. The default is the classic behaviour.
    private struct GestureMode {
        /// Momentum settings of this gesture; nil = momentum off.
        var momentum: ScrollMomentumSettings? = nil
        /// Thumb wheel posted as a back/forward swipe gesture.
        var pageSwipe = false
        /// Phase fields are written (precise gestures only; classic gestures follow `config.simTrackpadEnabled`).
        var writesPhases = false
        /// Wheel events of this gesture may start a glide.
        var coastAllowed = false
        /// Whole-pixel posting, release by `releaseGap`, momentum phases from the coast only.
        var precise: Bool { return momentum != nil || pageSwipe }
    }
#if DEBUG
    /// Tests: receives every frame instead of posting it.
    var frameRecorderForTests: ((ScrollOutgoingFrame) -> Void)?
#endif
    // CVDisplayLink 恢复机制
    private var keeper: Timer?
    private var lastCallbackTime: CFTimeInterval = 0.0
    private var lastRecreateAttempt: CFTimeInterval = 0.0
    private let recreateCooldown: CFTimeInterval = 3.0
    // CVDisplayLink 刷新率自纠 (issue #958):
    // 显示器唤醒/重连时会先短暂报告过渡刷新率 (如先 60Hz 再升 144Hz), 若重建正好落在这个窗口,
    // 就会把 link 绑到偏低的刷新率, 使平滑滚动只按低帧率绘制 (卡顿), 而现有恢复机制识别不了.
    // 对策: 每次建立 link 后延迟复查若干次, 发现 link 标称率明显低于显示器实际率就重建追平.
    private var rateVerifyTimer: Timer?
    private var rateVerifyAttemptsLeft = 0
    private var isVerifying = false
    private let rateVerifyDelays: [TimeInterval] = [2.0, 4.0, 8.0]
    private let rateVerifyRatio = 0.7
    // 主线程访问, 无需锁
    var isAvailable: Bool { return poster != nil }
}

// MARK: - 滚动数据更新控制
extension ScrollPoster {
    func update(event: CGEvent, duration: Double, y: Double, x: Double, speed: Double, amplification: Double = 1) -> Self {
        let gain = speed * amplification
        return update(event: event, input: ScrollPosterInput(
            y: y * gain,
            x: x * gain,
            notch: (y: abs(y * gain), x: abs(x * gain)),
            duration: duration,
            bypassFilter: ScrollMotion.shouldBypassFilter(freeSpinBlend: 0)
        ))
    }
    func update(event: CGEvent, input: ScrollPosterInput) -> Self {
        guard dispatchContext.capture(event: event) else {
            return self
        }
        os_unfair_lock_lock(&stateLock)
        defer { os_unfair_lock_unlock(&stateLock) }
        // 捕获本次手势的配置快照 (主线程读 Options/ScrollCore, CVDisplayLink 线程只读)
        captureConfigSnapshotLocked()
        handleInputLocked(input, at: CFAbsoluteTimeGetCurrent())
        return self
    }
    /// 处理一次滚轮输入: 手势方式, 缓冲, 滑行与阶段 (调用方须持有 stateLock)
    private func handleInputLocked(_ input: ScrollPosterInput, at now: CFTimeInterval) {
        inputSequence &+= 1
        let next = gestureMode(for: input)
        if gesture.precise {
            // 滑行中反向拨动一格: 停止滑行, 这一格本身不滚动
            if isReverseTickDuringMomentum(input, next: next) {
                cancelMomentumLocked()
                return
            }
            // 接下来的事件不带阶段 (进入 free-spin / 换到横向): 先结束进行中的手势
            if gesture.writesPhases && !next.writesPhases {
                closePhaseSequenceLocked()
            }
        }
        gesture = next
        let interval = lastManualEventTime > 0.0 ? now - lastManualEventTime : nil
        releaseGap = ScrollMomentum.releaseGap(lastInterval: interval)
        applyInputLocked(input, at: now)
        // 精确模式下不带阶段的手势不驱动状态机 (原有模式始终驱动)
        if !gesture.precise || gesture.writesPhases {
            let separatedByTime = interval == nil ? true : interval! >= manualSeparationThreshold
            let phase = phases.phase
            let separatedPhase = (phase == .Idle || phase == .Leave || phase == .MomentumEnd || phase == .TrackingEnd)
            let separated = manualInputEnded || separatedByTime || separatedPhase
            let plan = phases.onManualInputDetected(isSeparated: separated)
            perform(plan, emitTargetImmediately: false)
        }
        lastManualEventTime = now
        manualInputEnded = false
        momentumActive = false
        momentumEndScheduledTime = nil
        trackingEndScheduledTime = nil
    }
    /// How the gesture this input belongs to is sent.
    private func gestureMode(for input: ScrollPosterInput) -> GestureMode {
        if input.pageSwipe && input.x != 0.0 && input.y == 0.0 {
            return GestureMode(momentum: nil, pageSwipe: true, writesPhases: true, coastAllowed: false)
        }
        guard let momentum = input.momentum else {
            return GestureMode()
        }
        // 输出为横向: 拇指滚轮, 或按住转换键的竖向滚轮
        let horizontal = input.x != 0.0 || shifting
        let writesPhases = config.simTrackpadEnabled
            && (!horizontal || momentum.phasesOnHorizontal)
            && (!input.isFreeSpin || momentum.phasesInFreeSpin)
        // 只有竖向滚轮会滑行
        let coastAllowed = input.y != 0.0 && input.x == 0.0
            && (!input.isFreeSpin || momentum.coastInFreeSpin)
            && !(input.modifiersHeld && momentum.noCoastWithModifiers)
        return GestureMode(momentum: momentum, pageSwipe: false, writesPhases: writesPhases, coastAllowed: coastAllowed)
    }
    private func isReverseTickDuringMomentum(_ input: ScrollPosterInput, next: GestureMode) -> Bool {
        guard let momentum = gesture.momentum, momentum.stopOnReverseTick, next.momentum != nil else {
            return false
        }
        return manualInputEnded && momentumActive && coast.isActive
            && input.y != 0.0 && input.y * coast.velocity < 0.0
    }
    /// 停止滑行并丢弃剩余距离, 向应用补发收尾阶段; 下一帧因静止而结束会话
    private func cancelMomentumLocked() {
        coast.cancel()
        buffer = current
        filter.reset()
        resetCarriesLocked()
        if gesture.writesPhases {
            perform(phases.onMomentumCancelled(), emitTargetImmediately: true)
        }
        manualInputEnded = true
        momentumActive = false
    }
    /// 结束进行中的带阶段手势 (之后的事件不再带阶段)
    private func closePhaseSequenceLocked() {
        switch phases.phase {
        case .TrackingBegin, .TrackingOngoing:
            emitPhase((Phase.TrackingEnd, Phase.Idle), delta: (0.0, 0.0))
        case .MomentumBegin, .MomentumOngoing:
            emitPhase((Phase.MomentumEnd, Phase.Idle), delta: (0.0, 0.0))
        default:
            break
        }
        phases.reset()
    }
    private func resetCarriesLocked() {
        pixelCarry = (y: ScrollSubpixelCarry(), x: ScrollSubpixelCarry())
        lineCarry = (y: ScrollSubpixelCarry(), x: ScrollSubpixelCarry())
    }
    /// 更新滚动配置与缓冲 (调用方须持有 stateLock)
    private func applyInputLocked(_ input: ScrollPosterInput, at now: CFTimeInterval) {
        duration = input.duration
        bypassFilter = input.bypassFilter
        let timeConstant = ScrollMotion.timeConstant(forTransition: input.duration)
        // 同向累加, 反向则重新开始
        if input.y*delta.y > 0 {
            buffer.y += input.y
        } else {
            buffer.y = input.y
            current.y = 0.0
            leadLimiterY.reset()
            coast.cancel()
        }
        if input.x*delta.x > 0 {
            buffer.x += input.x
        } else {
            buffer.x = input.x
            current.x = 0.0
            leadLimiterX.reset()
        }
        // 真正换向时 (而非该轴本次无输入) 丢弃亚像素余量, 反向的第一格不带上一方向的零头
        if input.y*delta.y < 0 || input.x*delta.x < 0 {
            resetCarriesLocked()
        }
        // 精确模式下换向即停: 滤波器中上一方向尚未发送的距离一并丢弃, 反向的每一格都是完整的一格。
        // 原有模式保留滤波器状态, 速度平滑地掉头 (与之前一致)。
        if gesture.precise {
            if input.y*delta.y < 0 { filter.resetY() }
            if input.x*delta.x < 0 { filter.resetX() }
        }
        // 限制领先量: 滚轮减速或停下时, 不再继续释放之前积累的距离
        if input.y != 0.0 {
            let inputSpeed = leadLimiterY.register(distance: input.y, at: now, timeConstant: timeConstant)
            let cap = ScrollLeadLimiter.cap(notch: input.notch.y, distance: input.y, inputSpeed: inputSpeed, timeConstant: timeConstant)
            buffer.y = ScrollLeadLimiter.limit(buffer: buffer.y, current: current.y, cap: cap)
            // 滑行速度取自当前的输入速度: 单格与慢速滚动 (fling gain 为 0) 不留滑行
            if let momentum = gesture.momentum, gesture.coastAllowed {
                coast.seed(inputSpeed: inputSpeed, direction: input.y, lineRate: input.lineRate, settings: momentum)
            } else {
                coast.cancel()
            }
        }
        if input.x != 0.0 {
            let inputSpeed = leadLimiterX.register(distance: input.x, at: now, timeConstant: timeConstant)
            let cap = ScrollLeadLimiter.cap(notch: input.notch.x, distance: input.x, inputSpeed: inputSpeed, timeConstant: timeConstant)
            buffer.x = ScrollLeadLimiter.limit(buffer: buffer.x, current: current.x, cap: cap)
        }
        delta = (y: input.y, x: input.x)
    }
    func updateShifting(enable: Bool) {
        os_unfair_lock_lock(&stateLock)
        shifting = enable
        os_unfair_lock_unlock(&stateLock)
    }
    func shift(with nextValue: ( y: Double, x: Double )) -> (y: Double, x: Double) {
        // 如果按下 Shift, 则始终将滚动转为横向
        if shifting {
            // 判断哪个轴有值, 有值则赋给 X
            // 某些鼠标 (MXMaster/MXAnywhere), 按下 Shift 后会显式转换方向为横向, 此处针对这类转换进行归一化处理
            if nextValue.y != 0.0 && nextValue.x == 0.0 {
                return (y: nextValue.x, x: nextValue.y)
            } else {
                return (y: nextValue.y, x: nextValue.x)
            }
        } else {
            return (y: nextValue.y, x: nextValue.x)
        }
    }
    func brake() {
        os_unfair_lock_lock(&stateLock)
        buffer = current
        coast.cancel()
        perform(phases.onMomentumFinish(), emitTargetImmediately: true)
        manualInputEnded = true
        momentumActive = false
        momentumEndScheduledTime = nil
        os_unfair_lock_unlock(&stateLock)
    }
    func reset() {
        dispatchContext.invalidateAll()
        os_unfair_lock_lock(&stateLock)
        resetUnlocked()
        os_unfair_lock_unlock(&stateLock)
    }

#if DEBUG
    func captureConfigSnapshotForTests() {
        os_unfair_lock_lock(&stateLock)
        captureConfigSnapshotLocked()
        os_unfair_lock_unlock(&stateLock)
    }
    var configSnapshotForTests: (simTrackpadEnabled: Bool, deadZone: Double) {
        os_unfair_lock_lock(&stateLock)
        defer { os_unfair_lock_unlock(&stateLock) }
        return (config.simTrackpadEnabled, config.deadZone)
    }

    func recordSkippedSyntheticEvent() {
        dispatchContext.recordSkippedSyntheticEvent()
    }

    func diagnosticsSnapshot() -> (postedFrames: UInt64, droppedFramesByGeneration: UInt64, droppedFramesByTTL: UInt64, skippedSyntheticEvents: UInt64, updateSnapshotFailures: UInt64) {
        dispatchContext.diagnosticsSnapshot()
    }

    /// Applies an input to the buffer without capturing the event or touching the scroll phase.
    func applyInputForTests(_ input: ScrollPosterInput, at time: CFTimeInterval) {
        os_unfair_lock_lock(&stateLock)
        applyInputLocked(input, at: time)
        lastManualEventTime = time
        os_unfair_lock_unlock(&stateLock)
    }
    /// Advances the motion by one frame without posting; returns the frame's output.
    func advanceForTests(frameInterval: Double, now: CFTimeInterval) -> (y: Double, x: Double) {
        os_unfair_lock_lock(&stateLock)
        defer { os_unfair_lock_unlock(&stateLock) }
        return advanceMotionLocked(frameInterval: frameInterval, now: now)
    }
    var motionStateForTests: (current: (y: Double, x: Double), buffer: (y: Double, x: Double), duration: Double, bypassFilter: Bool) {
        os_unfair_lock_lock(&stateLock)
        defer { os_unfair_lock_unlock(&stateLock) }
        return (current, buffer, duration, bypassFilter)
    }
    /// Sets the config snapshot directly (an event would read it from Options).
    func setConfigForTests(simTrackpadEnabled: Bool, deadZone: Double = 1.0) {
        os_unfair_lock_lock(&stateLock)
        config = ConfigSnapshot(simTrackpadEnabled: simTrackpadEnabled, deadZone: deadZone)
        os_unfair_lock_unlock(&stateLock)
    }
    /// One wheel event through the whole input path (gesture mode, coast, phases), without
    /// an event to copy. Frames go to `frameRecorderForTests`.
    func inputForTests(_ input: ScrollPosterInput, at time: CFTimeInterval) {
        os_unfair_lock_lock(&stateLock)
        handleInputLocked(input, at: time)
        os_unfair_lock_unlock(&stateLock)
    }
    /// One display frame at `now`, as the display link runs it. Returns the phase to pass to
    /// `stop(_:)` when the motion has ended (the display link then stops), or nil while it goes on.
    func frameForTests(frameInterval: Double, now: CFTimeInterval) -> Phase? {
        os_unfair_lock_lock(&stateLock)
        defer { os_unfair_lock_unlock(&stateLock) }
        return processFrameLocked(frameInterval: frameInterval, now: now)
    }
    /// One display frame at `now`, exactly as the display link runs it but without the hop
    /// to the main thread: returns the stop request the frame makes, if any.
    func displayLinkFrameForTests(frameInterval: Double, now: CFTimeInterval) -> ScrollStopRequest? {
        os_unfair_lock_lock(&stateLock)
        defer { os_unfair_lock_unlock(&stateLock) }
        return displayLinkFrameLocked(frameInterval: frameInterval, now: now)
    }
    /// The whole display link callback at `now`, including the hop to the main thread.
    func displayLinkCallbackForTests(frameInterval: Double, now: CFTimeInterval) {
        os_unfair_lock_lock(&stateLock)
        let request = displayLinkFrameLocked(frameInterval: frameInterval, now: now)
        os_unfair_lock_unlock(&stateLock)
        if let request = request {
            scheduleStop(request)
        }
    }
    /// Signed glide velocity in px/s (0 = no glide).
    var coastVelocityForTests: Double {
        os_unfair_lock_lock(&stateLock)
        defer { os_unfair_lock_unlock(&stateLock) }
        return coast.velocity
    }
#endif

    private func resetUnlocked() {
        // 重置数值
        dispatchContext.clearContext()
        current = ( y: 0.0, x: 0.0 )
        delta = ( y: 0.0, x: 0.0 )
        buffer = ( y: 0.0, x: 0.0 )
        leadLimiterY.reset()
        leadLimiterX.reset()
        lastFrameHostTime = 0
        gesture = GestureMode()
        coast.cancel()
        releaseGap = ScrollMomentum.releaseGapRange.upperBound
        resetCarriesLocked()
        // 重置插值器
        filter.reset()
        phases.reset()
        manualInputEnded = true
        momentumActive = false
        lastManualEventTime = 0.0
        momentumEndScheduledTime = nil
        trackingEndScheduledTime = nil
    }
}

// MARK: - 插值数据发送控制
extension ScrollPoster {
    // 初始化 CVDisplayLink
    func create() {
        // 清理旧的 CVDisplayLink
        if let old = poster {
            if CVDisplayLinkIsRunning(old) {
                CVDisplayLinkStop(old)
            }
            poster = nil
        }
        // 创建新的 CVDisplayLink, 检查返回值
        var newPoster: CVDisplayLink?
        let result = CVDisplayLinkCreateWithActiveCGDisplays(&newPoster)
        if result == kCVReturnSuccess, let validPoster = newPoster {
            CVDisplayLinkSetOutputCallback(validPoster, { (displayLink, inNow, inOutputTime, flagsIn, flagsOut, displayLinkContext) -> CVReturn in
                ScrollPoster.shared.processing(outputTime: inOutputTime.pointee)
                return kCVReturnSuccess
            }, nil)
            poster = validPoster
            // 建立成功后安排刷新率复查; 复查内部触发的重建 (isVerifying) 不重置复查序列
            if !isVerifying { scheduleRateVerify() }
        } else {
            poster = nil
            NSLog("ScrollPoster: CVDisplayLink creation failed (%d)", result)
        }
    }
    // 启动事件发送器
    func tryStart() {
        guard let validPoster = poster else {
            if !recreateDisplayLink() {
                // cooldown 拒绝了重建; 清理陈旧 buffer 防止恢复后滚动跳变
                reset()
            }
            return
        }
        if !CVDisplayLinkIsRunning(validPoster) {
            let result = CVDisplayLinkStart(validPoster)
            if result == kCVReturnSuccess {
                // 给 keeper 一个宽限期, 防止误判新启动的 poster 为僵尸
                os_unfair_lock_lock(&stateLock)
                lastCallbackTime = CFAbsoluteTimeGetCurrent()
                os_unfair_lock_unlock(&stateLock)
            } else {
                let _ = recreateDisplayLink()
            }
        }
    }
    // 停止事件发送器
    func stop(_ requestedPhase: Phase = Phase.MomentumEnd) {
        // 停止循环, 然后准备发送最后一次事件
        if let validPoster = poster {
            CVDisplayLinkStop(validPoster)
        }
        // 失效旧会话异步帧，收尾帧使用新代次
        dispatchContext.advanceGeneration()
        os_unfair_lock_lock(&stateLock)

        // 判断是否启用触控板模拟 (读 update 时主线程捕获的快照, 避免跨线程读)
        let enableSimTrackpad = resolveSimTrackpadEnabled()
        let plan: ScrollPhase.TransitionPlan
        if requestedPhase == Phase.MomentumEnd {
            plan = phases.onMomentumFinish()
        } else {
            plan = phases.onManualInputEnded()
        }

        // 发送结束事件
        if enableSimTrackpad {
            perform(plan, emitTargetImmediately: true)
        } else {
            if let snapshot = dispatchContext.preparePostingSnapshot(),
               ScrollUtils.shared.isEventTargetingChrome(snapshot.event),
               let phaseValues = phaseValues(for: .TrackingEnd) {
                _ = post(
                    (y: 0.0, x: 0.0),
                    phaseOverride: phaseValues,
                    fallbackToCurrentPhase: false,
                    using: snapshot
                )
            }
        }
        manualInputEnded = true
        momentumActive = false
        // 重置参数 (不递增 generation, 保留本次收尾帧有效性)
        resetUnlocked()
        os_unfair_lock_unlock(&stateLock)
#if DEBUG
        let diag = diagnosticsSnapshot()
        if diag.droppedFramesByGeneration > 0 || diag.droppedFramesByTTL > 0 || diag.updateSnapshotFailures > 0 {
            NSLog("[ScrollPoster] diag: posted=%llu dropGen=%llu dropTTL=%llu skipSynth=%llu snapFail=%llu",
                  diag.postedFrames, diag.droppedFramesByGeneration, diag.droppedFramesByTTL,
                  diag.skippedSyntheticEvents, diag.updateSnapshotFailures)
        }
#endif
    }
    /// Carries out a stop the display link asked for. Main thread only.
    ///
    /// A request is stale when a wheel input arrived after it was made: that input belongs to
    /// the motion now, the display link is still running, and a later frame asks again once
    /// the motion has really ended. Wheel inputs only arrive on the main thread, so none can
    /// slip in between this check and the reset in `stop(_:)`.
    /// - Returns: false when the request was stale and nothing was done.
    @discardableResult
    func performRequestedStop(_ request: ScrollStopRequest) -> Bool {
        assertMainThread()
        os_unfair_lock_lock(&stateLock)
        let isCurrent = request.inputSequence == inputSequence
        os_unfair_lock_unlock(&stateLock)
        guard isCurrent else { return false }
        stop(request.phase)
        return true
    }
    // 重建 CVDisplayLink (带冷却期)
    @discardableResult
    func recreateDisplayLink() -> Bool {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastRecreateAttempt >= recreateCooldown else { return false }
        lastRecreateAttempt = now
        create()
        if let validPoster = poster {
            let result = CVDisplayLinkStart(validPoster)
            if result == kCVReturnSuccess {
                os_unfair_lock_lock(&stateLock)
                lastCallbackTime = CFAbsoluteTimeGetCurrent()
                os_unfair_lock_unlock(&stateLock)
            } else {
                NSLog("ScrollPoster: CVDisplayLink start failed after recreate (%d)", result)
            }
        }
        return true
    }
    // 守护定时器 (与 Interceptor 的 keeper 模式一致)
    func startKeeper() {
        keeper?.invalidate()
        keeper = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.healthCheck()
        }
    }
    func stopKeeper() {
        keeper?.invalidate()
        keeper = nil
        rateVerifyTimer?.invalidate()
        rateVerifyTimer = nil
        rateVerifyAttemptsLeft = 0
    }
    private func healthCheck() {
        guard let validPoster = poster else {
            recreateDisplayLink()
            return
        }
        if CVDisplayLinkIsRunning(validPoster) {
            os_unfair_lock_lock(&stateLock)
            let lastTime = lastCallbackTime
            os_unfair_lock_unlock(&stateLock)
            // lastTime > 0 避免首次回调前误判
            if lastTime > 0 && CFAbsoluteTimeGetCurrent() - lastTime > 2.0 {
                NSLog("ScrollPoster: zombie CVDisplayLink detected, recreating")
                recreateDisplayLink()
            }
        }
    }

    // MARK: 刷新率自纠 (见属性处说明)
    // 建立 link 后调用: 重置复查序列并安排第一次复查
    private func scheduleRateVerify() {
        rateVerifyAttemptsLeft = rateVerifyDelays.count
        armNextRateVerify()
    }
    private func armNextRateVerify() {
        rateVerifyTimer?.invalidate()
        guard rateVerifyAttemptsLeft > 0 else { rateVerifyTimer = nil; return }
        let delay = rateVerifyDelays[rateVerifyDelays.count - rateVerifyAttemptsLeft]
        rateVerifyTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.verifyRateAndFixIfNeeded()
        }
    }
    // 复查: link 标称率明显低于显示器实际率 -> 重建追平 (幂等, 不受 recreateCooldown 限制)
    private func verifyRateAndFixIfNeeded() {
        rateVerifyAttemptsLeft -= 1
        guard let current = poster else { rateVerifyTimer = nil; return }
        let nominal = linkNominalHz(current)
        let maxHz = maxActiveDisplayHz()
        guard nominal > 1, maxHz > 1, nominal < maxHz * rateVerifyRatio else {
            // 已追平显示器刷新率, 结束复查
            rateVerifyTimer = nil
            rateVerifyAttemptsLeft = 0
            return
        }
        NSLog("ScrollPoster: display link rate %.0fHz below display %.0fHz, recreating", nominal, maxHz)
        // 保持原运行状态: 若正在滚动 (running) 则重建后重新启动
        let wasRunning = CVDisplayLinkIsRunning(current)
        isVerifying = true
        create()
        isVerifying = false
        if wasRunning, let refreshed = poster {
            CVDisplayLinkStart(refreshed)
        }
        // 自纠说明显示器仍在过渡: 清除冷却, 让后续 screenChange 能及时用最终配置重建
        lastRecreateAttempt = 0
        // 这次重建可能仍落在过渡态, 继续后续复查直到追平或用尽次数
        armNextRateVerify()
    }
}

// MARK: - 数据处理及发送
private extension ScrollPoster {
    func perform(_ plan: ScrollPhase.TransitionPlan, emitTargetImmediately: Bool, delta: (y: Double, x: Double) = (0.0, 0.0)) {
        if plan.queue.isEmpty && plan.target == nil {
            return
        }
        for item in plan.queue {
            emitPhase(item, delta: delta)
        }
        if let target = plan.target {
            if emitTargetImmediately {
                emitPhase(target, delta: delta)
            } else {
                phases.apply(phase: target.0, autoAdvance: target.1)
            }
        }
    }

    func emitPhase(_ item: (Phase, Phase?), delta: (y: Double, x: Double)) {
        phases.apply(phase: item.0, autoAdvance: item.1)
        let phaseOverride = resolveSimTrackpadEnabled() ? phaseValues(for: item.0) : nil
        // 无可用事件 (或精确模式下不带阶段的手势) 时不发送, 状态机照常推进
        if !post(delta, phaseOverride: phaseOverride, fallbackToCurrentPhase: false) {
            phases.didDeliverFrame()
        }
    }

    // 处理滚动事件 (CVDisplayLink 线程)
    func processing(outputTime: CVTimeStamp) {
        os_unfair_lock_lock(&stateLock)
        let now = CFAbsoluteTimeGetCurrent()
        lastCallbackTime = now
        let request = displayLinkFrameLocked(frameInterval: frameIntervalLocked(outputTime), now: now)
        os_unfair_lock_unlock(&stateLock)
        if let request = request {
            scheduleStop(request)
        }
    }

    /// One display frame. When the motion has ended it returns a request to end the session
    /// instead of ending it: the display link thread never calls `stop(_:)` itself.
    /// Caller holds stateLock.
    ///
    /// `stop(_:)` belongs to the main thread, where the wheel inputs arrive:
    /// - it reads `poster`, which the main thread replaces when it recreates the display link;
    /// - it asks ScrollUtils whether the target is Chrome, which updates a cache that the
    ///   scroll tap callback uses without a lock;
    /// - it resets the state. Called from here it had to give up stateLock first, and a wheel
    ///   tick that arrived in that gap was wiped by the reset although its event had already
    ///   been swallowed.
    ///
    /// At most one request is made per wheel input: in precise mode every frame of a finished
    /// motion asks for the stop again until the main thread has carried it out.
    func displayLinkFrameLocked(frameInterval: Double, now: CFTimeInterval) -> ScrollStopRequest? {
        guard let phase = processFrameLocked(frameInterval: frameInterval, now: now) else { return nil }
        guard requestedStopSequence != inputSequence else { return nil }
        requestedStopSequence = inputSequence
        return ScrollStopRequest(phase: phase, inputSequence: inputSequence)
    }

    func scheduleStop(_ request: ScrollStopRequest) {
        DispatchQueue.main.async { [weak self] in
            self?.performRequestedStop(request)
        }
    }

    /// 处理一帧, 返回需要以哪个阶段结束会话 (nil 表示继续)。调用方须持有 stateLock。
    func processFrameLocked(frameInterval: Double, now: CFTimeInterval) -> Phase? {
        if gesture.precise {
            return processPreciseFrameLocked(frameInterval: frameInterval, now: now)
        }
        return processClassicFrameLocked(frameInterval: frameInterval, now: now)
    }

    /// 原有的逐帧处理 (momentum 关闭时)。
    func processClassicFrameLocked(frameInterval: Double, now: CFTimeInterval) -> Phase? {
        var pendingStopPhase: Phase?
        // 插值并平滑 (按真实帧间隔)
        let filledValue = advanceMotionLocked(frameInterval: frameInterval, now: now)
        // 变换滚动结果，将滤波后的插值映射到当前姿态（考虑灵敏度、方向等因素）
        let shiftedValue = shift(with: filledValue)
        // 检测是否已经超过手动输入的持续时间阈值，准备结束手动阶段
        if !manualInputEnded && lastManualEventTime > 0.0 && now - lastManualEventTime > manualContinuationThreshold {
            let endPlan = phases.onManualInputEnded()
            if !(endPlan.queue.isEmpty && endPlan.target == nil) {
                perform(endPlan, emitTargetImmediately: true)
            }
            manualInputEnded = true
            if trackingEndScheduledTime == nil {
                trackingEndScheduledTime = now + trackingEndAdvance
            }
        }
        // 计算缓冲值与当前位置的剩余距离，用于判断滚动是否已收敛
        let residualY = buffer.y - current.y
        let residualX = buffer.x - current.x
        let residualMagnitude = max(residualY.magnitude, residualX.magnitude)
        let deadZone = config.deadZone
        if manualInputEnded && residualMagnitude > deadZone {
            if !momentumActive {
                perform(phases.onMomentumStart(), emitTargetImmediately: false)
                momentumActive = true
            } else {
                perform(phases.onMomentumOngoing(), emitTargetImmediately: false)
            }
            momentumEndScheduledTime = nil
            trackingEndScheduledTime = nil
        } else if momentumActive && residualMagnitude <= deadZone {
            if momentumEndScheduledTime == nil {
                momentumEndScheduledTime = now + momentumEndDelay
            }
        } else {
            momentumEndScheduledTime = nil
            if momentumActive {
                momentumActive = false
            }
        }
        // 发送滚动结果 - 只有当输出值超过死区阈值时才发送
        let outputMagnitude = max(abs(shiftedValue.y), abs(shiftedValue.x))
        if outputMagnitude > deadZone {
            _ = post(shiftedValue)
        }

        if let scheduled = momentumEndScheduledTime, momentumActive {
            if now >= scheduled {
                momentumEndScheduledTime = nil
                momentumActive = false
                pendingStopPhase = .MomentumEnd
            }
        }
        if pendingStopPhase == nil && manualInputEnded && !momentumActive && residualMagnitude <= deadZone {
            let pendingStop = trackingEndScheduledTime != nil && now >= trackingEndScheduledTime!
            let outputSettled = outputMagnitude <= deadZone
            if pendingStop && outputSettled {
                trackingEndScheduledTime = nil
                pendingStopPhase = .TrackingEnd
            }
        } else {
            trackingEndScheduledTime = nil
        }
        return pendingStopPhase
    }

    /// 精确模式的逐帧处理 (momentum 开启, 或拇指滚轮翻页手势)。
    ///
    /// 与原有模式的区别:
    /// - 滚轮停顿超过 releaseGap 视为松手。此时若有滑行, 手势结束并进入惯性阶段, 惯性阶段只由
    ///   滑行产生; 没有滑行 (单格 / 慢速 / free-spin) 则保持跟随阶段直到位移走完再结束, 没有惯性阶段。
    /// - 每帧都发送, 亚像素余量累积成整数像素, 不设死区。
    func processPreciseFrameLocked(frameInterval: Double, now: CFTimeInterval) -> Phase? {
        let filledValue = advanceMotionLocked(frameInterval: frameInterval, now: now)
        let shiftedValue = shift(with: filledValue)
        let stopDelta = gesture.momentum?.stopDelta ?? ScrollMomentumSettings.default.stopDelta
        let residualMagnitude = max(abs(buffer.y - current.y), abs(buffer.x - current.x))
        let pendingMagnitude = max(abs(filter.pending.y), abs(filter.pending.x))
        let outputMagnitude = max(abs(shiftedValue.y), abs(shiftedValue.x))
        let coasting = coast.isActive
        let atRest = !coasting && residualMagnitude <= stopDelta && pendingMagnitude <= stopDelta && outputMagnitude <= stopDelta

        if !manualInputEnded && lastManualEventTime > 0.0 && now - lastManualEventTime > releaseGap {
            if coasting {
                // 带速度松手: 结束手势, 本帧起为惯性阶段
                manualInputEnded = true
                momentumActive = true
                if gesture.writesPhases {
                    perform(phases.onManualInputEnded(), emitTargetImmediately: true)
                    perform(phases.onMomentumStart(), emitTargetImmediately: false)
                }
            } else if atRest {
                manualInputEnded = true
            }
        }
        _ = post(shiftedValue)

        guard manualInputEnded && atRest else { return nil }
        if momentumActive {
            momentumActive = false
            return .MomentumEnd
        }
        return .TrackingEnd
    }

    /// 推进一帧: 插值 current -> buffer 并经滤波 (或跳过滤波) 得到本帧输出。调用方须持有 stateLock。
    func advanceMotionLocked(frameInterval: Double, now: CFTimeInterval) -> (y: Double, x: Double) {
        // 按真实帧间隔换算插值系数 (以 60Hz 为参考, 不同刷新率下滚动时长一致)
        let trans = ScrollMotion.transition(duration, frameInterval: frameInterval)
        // 计算插值
        var frame = (
            y: Interpolator.lerp(src: current.y, dest: buffer.y, trans: trans),
            x: Interpolator.lerp(src: current.x, dest: buffer.x, trans: trans)
        )
        // 惯性滑行: 本帧位移不小于滑行位移 (松手后页面保持速度并沿系统惯性曲线减速)
        var glide = 0.0
        if coast.isActive, let momentum = gesture.momentum {
            glide = coast.advance(interval: ScrollMotion.clampedFrameInterval(frameInterval), settings: momentum)
            if glide != 0.0 && (frame.y * glide <= 0.0 || abs(glide) > abs(frame.y)) {
                frame.y = glide
            }
        }
        // 更新滚动位置
        current = (
            y: current.y + frame.y,
            x: current.x + frame.x
        )
        // 滑行越过目标时目标随之前移, 之后的滚轮输入从实际位置继续累加
        if glide != 0.0 && (buffer.y - current.y) * glide < 0.0 {
            buffer.y = current.y
        }
        // 平滑滚动结果: 滤波的时间常数跟随插值 (见 ScrollMotion.filterWeight(forTransition:));
        // free-spin 与翻页手势跳过滤波, 去掉其额外延迟
        var output: (y: Double, x: Double)
        if bypassFilter {
            output = filter.passThrough(with: frame, catchUp: trans)
        } else {
            let weight = ScrollMotion.transition(ScrollMotion.filterWeight(forTransition: duration), frameInterval: frameInterval)
            output = filter.fill(with: frame, weight: weight)
        }
        // 精确模式: 松手后速度降到落地速度时, 以该速度匀速走完剩余距离 (见 ScrollLanding)。
        // 原有模式不需要: 不足死区的帧本来就不发送, 运动在该速度处结束。
        if gesture.precise && !coast.isActive && !momentumActive
            && lastManualEventTime > 0.0 && now - lastManualEventTime > releaseGap {
            output = landLocked(output, frameInterval: frameInterval)
        }
        return output
    }

    /// 精确模式的收尾 (见 ScrollLanding): 每个轴各自接管其尚未发送的全部距离
    /// (领先量加滤波器中未发送的部分)。调用方须持有 stateLock。
    func landLocked(_ output: (y: Double, x: Double), frameInterval: Double) -> (y: Double, x: Double) {
        var result = output
        if let landed = ScrollLanding.step(
            output: output.y, remaining: (buffer.y - current.y) + filter.pending.y,
            direction: delta.y, interval: frameInterval
        ) {
            result.y = landed.output
            current.y = buffer.y - landed.remaining
            filter.settleY(at: landed.output)
        }
        if let landed = ScrollLanding.step(
            output: output.x, remaining: (buffer.x - current.x) + filter.pending.x,
            direction: delta.x, interval: frameInterval
        ) {
            result.x = landed.output
            current.x = buffer.x - landed.remaining
            filter.settleX(at: landed.output)
        }
        return result
    }

    /// 本帧与上一帧显示时间的间隔 (秒); 新会话的第一帧使用显示器标称帧间隔。调用方须持有 stateLock。
    func frameIntervalLocked(_ outputTime: CVTimeStamp) -> Double {
        let hostTime = outputTime.hostTime
        defer { lastFrameHostTime = hostTime }
        if lastFrameHostTime != 0 && hostTime > lastFrameHostTime {
            return Double(hostTime - lastFrameHostTime) * ScrollEventClock.secondsPerTick
        }
        let periodValid = outputTime.flags & CVTimeStampFlags.videoRefreshPeriodValid.rawValue != 0
        if periodValid && outputTime.videoRefreshPeriod > 0 && outputTime.videoTimeScale > 0 {
            return Double(outputTime.videoRefreshPeriod) / Double(outputTime.videoTimeScale)
        }
        return ScrollMotion.referenceFrameInterval
    }

    /// 主线程读取当前 (全局 / 例外应用) 配置存入快照。调用方须持有 stateLock。
    func captureConfigSnapshotLocked() {
        let simTrackpad: Bool
        if let application = ScrollCore.shared.application, !application.inherit {
            simTrackpad = application.scroll.smoothSimTrackpad
        } else {
            simTrackpad = Options.shared.scroll.smoothSimTrackpad
        }
        config = ConfigSnapshot(
            simTrackpadEnabled: simTrackpad,
            deadZone: Options.shared.scroll.deadZone
        )
    }

    /// 当前手势是否写入阶段字段: 原有模式取决于 "模拟触控板", 精确模式由手势决定
    /// (free-spin 与横向不带阶段, 拇指滚轮翻页手势始终带阶段)
    func resolveSimTrackpadEnabled() -> Bool {
        return gesture.precise ? gesture.writesPhases : config.simTrackpadEnabled
    }

    func phaseValues(for phase: Phase) -> (scroll: Double, momentum: Double)? {
        guard let scrollValue = PhaseValueMapping[phase]?[.Scroll],
              let momentumValue = PhaseValueMapping[phase]?[.Momentum] else {
            return nil
        }
        return (scroll: scrollValue, momentum: momentumValue)
    }

    /// 组装并发送一帧。没有可用事件, 或精确模式下本帧不足一个像素且不是阶段切换帧时返回 false (未发送)。
    @discardableResult
    func post(_ v: (y: Double, x: Double), phaseOverride: (scroll: Double, momentum: Double)? = nil, fallbackToCurrentPhase: Bool = true, using preparedSnapshot: ScrollDispatchContext.PostingSnapshot? = nil) -> Bool {
        var phaseValues = phaseOverride
        if phaseValues == nil && fallbackToCurrentPhase && resolveSimTrackpadEnabled() {
            phaseValues = self.phaseValues(for: phases.phase)
        }
        var frame = ScrollOutgoingFrame(y: v.y, x: v.x, scrollPhase: phaseValues?.scroll, momentumPhase: phaseValues?.momentum)
        if gesture.precise {
            // 整数像素 (余量累积到后续帧), 行数与像素一致 (10 像素一行)
            let pixels = (y: pixelCarry.y.take(v.y), x: pixelCarry.x.take(v.x))
            frame.precise = true
            frame.y = Double(pixels.y)
            frame.x = Double(pixels.x)
            frame.linesY = lineCarry.y.take(frame.y / ScrollOutgoingFrame.pixelsPerLine)
            frame.linesX = lineCarry.x.take(frame.x / ScrollOutgoingFrame.pixelsPerLine)
            // 不足一个像素的普通帧不发送 (阶段切换帧始终发送); 待发的阶段留给下一帧
            if phaseOverride == nil && pixels.y == 0 && pixels.x == 0 {
                return false
            }
        }
#if DEBUG
        if let recorder = frameRecorderForTests {
            recorder(frame)
            phases.didDeliverFrame()
            return true
        }
#endif
        guard let snapshot = preparedSnapshot ?? dispatchContext.preparePostingSnapshot() else {
            return false
        }
        frame.write(to: snapshot.event)
        ScrollUtils.shared.markSyntheticSmoothEvent(snapshot.event)
        // 通过 CGEventPostToPid 直投目标进程:
        // 不依赖 proxy (消除崩溃), 不经过 tap 链重新路由 (动量不跟随光标)
        // ref: @shichangone MR: https://github.com/Caldis/Mos/pull/523, issue #868
        dispatchContext.enqueue(snapshot)
        phases.didDeliverFrame()
        return true
    }
}

// MARK: - 显示器刷新率查询 (刷新率自纠使用)
private extension ScrollPoster {
    /// CVDisplayLink 当前绑定显示器的标称刷新率 (Hz); 无效返回 -1
    func linkNominalHz(_ link: CVDisplayLink) -> Double {
        let period = CVDisplayLinkGetNominalOutputVideoRefreshPeriod(link)
        // 无效/indefinite 周期时 timeValue 或 timeScale 为 0
        guard period.timeValue != 0, period.timeScale != 0 else { return -1 }
        let seconds = Double(period.timeValue) / Double(period.timeScale)
        return seconds > 0 ? 1.0 / seconds : -1
    }
    /// 当前活跃显示器里最高刷新率 (Hz); 取不到返回 -1
    func maxActiveDisplayHz() -> Double {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return -1 }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return -1 }
        var mx = -1.0
        for id in ids.prefix(Int(count)) {
            if let hz = CGDisplayCopyDisplayMode(id)?.refreshRate, hz > mx { mx = hz }
        }
        return mx
    }
}
