//
//  ScrollPoster.swift
//  Mos
//
//  Created by Caldis on 2020/12/3.
//  Copyright © 2020 Caldis. All rights reserved.
//

import Cocoa
import os

/// One wheel event for ScrollPoster, as ScrollCore resolved it.
struct ScrollPosterInput {
    /// Signed distance to add per axis (px): max(step, |point delta|) × speed × dash.
    var y: Double
    var x: Double
    /// One notch, step × speed × dash (px): the lead cap never goes below two of them.
    var notch: Double
    /// Duration as the per-frame interpolation factor at 60 Hz.
    var duration: Double
}

/// One scroll event as ScrollPoster sends it.
struct ScrollOutgoingFrame: Equatable {
    /// Pixel deltas.
    var y: Double
    var x: Double
    /// Phase field values; nil leaves the phase fields of the copied wheel event alone.
    var scrollPhase: Double? = nil
    var momentumPhase: Double? = nil

    /// Only the point delta is written (CoreGraphics drops its fraction); the line delta and
    /// the timestamp stay those of the copied wheel event.
    func write(to event: CGEvent) {
        if let scrollPhase = scrollPhase, let momentumPhase = momentumPhase {
            event.setDoubleValueField(.scrollWheelEventScrollPhase, value: scrollPhase)
            event.setDoubleValueField(.scrollWheelEventMomentumPhase, value: momentumPhase)
        }
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: y)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: x)
        // 是否连续滚动: 始终为 1.0
        event.setDoubleValueField(.scrollWheelEventIsContinuous, value: 1.0)
    }
}

/// The display link found the motion finished and asks the main thread to end the session.
struct ScrollStopRequest: Equatable {
    /// Phase to end with (`ScrollPoster.stop(_:)`).
    let phase: Phase
    /// The wheel input the request was made after (`ScrollPoster.inputSequence`).
    let inputSequence: UInt64
}

/// Smooth scrolling. Each wheel event adds its distance to a target (`buffer`); on every
/// display frame the position (`current`) moves a share of the remaining way, set by
/// Duration and the real frame interval, ScrollFilter rounds off the start, and the frame is
/// posted when it is larger than the dead zone. Optional trackpad-style phases.
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
    // 本次滚动的统计, 结束时写入系统日志 (ScrollSystemLog)
    private var sessionLog = ScrollSystemLog.Session()
    // 领先量限制 (buffer - current), 滚轮停下后滑行尽快结束
    private var leadLimiterY = ScrollLeadLimiter()
    private var leadLimiterX = ScrollLeadLimiter()
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
    /// 处理一次滚轮输入: 缓冲与阶段 (调用方须持有 stateLock)
    private func handleInputLocked(_ input: ScrollPosterInput, at now: CFTimeInterval) {
        if sessionLog.isEmpty {
            sessionLog.startedAt = now
        }
        sessionLog.inputs += 1
        sessionLog.transition = input.duration
        sessionLog.inputDistance += abs(input.y) + abs(input.x)
        sessionLog.lastInputAt = now
        sessionLog.trackpadStyle = config.simTrackpadEnabled
        inputSequence &+= 1
        let separatedByTime = lastManualEventTime <= 0.0 || now - lastManualEventTime >= manualSeparationThreshold
        applyInputLocked(input, at: now)
        let phase = phases.phase
        let separatedPhase = (phase == .Idle || phase == .Leave || phase == .MomentumEnd || phase == .TrackingEnd)
        let separated = manualInputEnded || separatedByTime || separatedPhase
        perform(phases.onManualInputDetected(isSeparated: separated), emitTargetImmediately: false)
        lastManualEventTime = now
        manualInputEnded = false
        momentumActive = false
        momentumEndScheduledTime = nil
        trackingEndScheduledTime = nil
    }
    /// 更新滚动配置与缓冲 (调用方须持有 stateLock)
    private func applyInputLocked(_ input: ScrollPosterInput, at now: CFTimeInterval) {
        duration = input.duration
        let timeConstant = ScrollMotion.timeConstant(forTransition: input.duration)
        // 同向累加, 反向则重新开始
        if input.y*delta.y > 0 {
            buffer.y += input.y
        } else {
            buffer.y = input.y
            current.y = 0.0
            leadLimiterY.reset()
        }
        if input.x*delta.x > 0 {
            buffer.x += input.x
        } else {
            buffer.x = input.x
            current.x = 0.0
            leadLimiterX.reset()
        }
        // 限制领先量: 滚轮减速或停下时, 不再继续释放之前积累的距离
        if input.y != 0.0 {
            let inputSpeed = leadLimiterY.register(distance: input.y, at: now, timeConstant: timeConstant)
            let cap = ScrollLeadLimiter.cap(notch: input.notch, distance: input.y, inputSpeed: inputSpeed, timeConstant: timeConstant)
            buffer.y = ScrollLeadLimiter.limit(buffer: buffer.y, current: current.y, cap: cap)
        }
        if input.x != 0.0 {
            let inputSpeed = leadLimiterX.register(distance: input.x, at: now, timeConstant: timeConstant)
            let cap = ScrollLeadLimiter.cap(notch: input.notch, distance: input.x, inputSpeed: inputSpeed, timeConstant: timeConstant)
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
    func advanceForTests(frameInterval: Double) -> (y: Double, x: Double) {
        os_unfair_lock_lock(&stateLock)
        defer { os_unfair_lock_unlock(&stateLock) }
        return advanceMotionLocked(frameInterval: frameInterval)
    }
    var motionStateForTests: (current: (y: Double, x: Double), buffer: (y: Double, x: Double), duration: Double) {
        os_unfair_lock_lock(&stateLock)
        defer { os_unfair_lock_unlock(&stateLock) }
        return (current, buffer, duration)
    }
    /// What the system log line of the current scroll would say so far.
    var sessionLogForTests: ScrollSystemLog.Session {
        os_unfair_lock_lock(&stateLock)
        defer { os_unfair_lock_unlock(&stateLock) }
        return sessionLog
    }
    /// Sets the config snapshot directly (an event would read it from Options).
    func setConfigForTests(simTrackpadEnabled: Bool, deadZone: Double = 1.0) {
        os_unfair_lock_lock(&stateLock)
        config = ConfigSnapshot(simTrackpadEnabled: simTrackpadEnabled, deadZone: deadZone)
        os_unfair_lock_unlock(&stateLock)
    }
    /// One wheel event through the whole input path (buffer, lead cap, phases, session log),
    /// without an event to copy. Frames go to `frameRecorderForTests`.
    func inputForTests(_ input: ScrollPosterInput, at time: CFTimeInterval) {
        os_unfair_lock_lock(&stateLock)
        handleInputLocked(input, at: time)
        os_unfair_lock_unlock(&stateLock)
    }
    /// One display frame at `now`, exactly as the display link runs it but without the hop
    /// to the main thread: returns the stop request the frame makes, if any.
    func displayLinkFrameForTests(frameInterval: Double, now: CFTimeInterval) -> ScrollStopRequest? {
        os_unfair_lock_lock(&stateLock)
        defer { os_unfair_lock_unlock(&stateLock) }
        return displayLinkFrameLocked(frameInterval: frameInterval, now: now)
    }
    /// The display link this poster owns (nil before `create()`).
    var displayLinkForTests: CVDisplayLink? { return poster }
    var isDisplayLinkRunningForTests: Bool {
        return poster.map { CVDisplayLinkIsRunning($0) } ?? false
    }
    /// Lets the next `recreateDisplayLink` through at once.
    func clearRecreateCooldownForTests() {
        lastRecreateAttempt = 0
    }
    /// One look of the keeper, now.
    func healthCheckForTests() {
        healthCheck()
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
            if !recreateDisplayLink(scrollWaiting: true) {
                // cooldown 拒绝了重建; 清理陈旧 buffer 防止恢复后滚动跳变
                reset()
            }
            return
        }
        if !CVDisplayLinkIsRunning(validPoster) {
            followDisplayUnderPointer(validPoster)
            let result = CVDisplayLinkStart(validPoster)
            if result == kCVReturnSuccess {
                // 给 keeper 一个宽限期, 防止误判新启动的 poster 为僵尸
                os_unfair_lock_lock(&stateLock)
                lastCallbackTime = CFAbsoluteTimeGetCurrent()
                os_unfair_lock_unlock(&stateLock)
            } else {
                let _ = recreateDisplayLink(scrollWaiting: true)
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
        let enableSimTrackpad = config.simTrackpadEnabled
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
        let finished = sessionLog
        sessionLog = ScrollSystemLog.Session()
        // 重置参数 (不递增 generation, 保留本次收尾帧有效性)
        resetUnlocked()
        os_unfair_lock_unlock(&stateLock)
        if !finished.isEmpty {
            ScrollSystemLog.note(finished, endedWith: "\(requestedPhase)")
        }
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
    /// Replaces the display link (at most once per `recreateCooldown`).
    ///
    /// The new link runs only when the one it replaces was running (a glide goes on) or a
    /// wheel event waits for it (`scrollWaiting`, from `tryStart`). An idle link stays idle:
    /// started from the screen-change observer (which also runs while paused or asleep) or
    /// from the keeper, nothing stopped it before the next scroll ended, so it fired 60 to
    /// 120 times a second for nothing, and that scroll's `tryStart` found it running and
    /// skipped `followDisplayUnderPointer`.
    /// - Returns: false when the cooldown refused the recreation.
    @discardableResult
    func recreateDisplayLink(scrollWaiting: Bool = false) -> Bool {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastRecreateAttempt >= recreateCooldown else { return false }
        lastRecreateAttempt = now
        let replacedWasRunning = poster.map { CVDisplayLinkIsRunning($0) } ?? false
        create()
        if Self.startsRecreatedDisplayLink(replacedWasRunning: replacedWasRunning, scrollWaiting: scrollWaiting),
           let validPoster = poster {
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
    /// Whether `recreateDisplayLink` starts the link it made (see there).
    static func startsRecreatedDisplayLink(replacedWasRunning: Bool, scrollWaiting: Bool) -> Bool {
        return replacedWasRunning || scrollWaiting
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
            // Made, not started: the next wheel event's tryStart starts it.
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
        // The link follows the display under the pointer (see followDisplayUnderPointer), so it
        // is compared with that display's rate; a slower display is then not "too slow".
        let followed = CGDisplayCopyDisplayMode(CVDisplayLinkGetCurrentCGDisplay(current))?.refreshRate ?? 0
        let maxHz = followed > 1 ? followed : maxActiveDisplayHz()
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
    func perform(_ plan: ScrollPhase.TransitionPlan, emitTargetImmediately: Bool) {
        if plan.queue.isEmpty && plan.target == nil {
            return
        }
        for item in plan.queue {
            emitPhase(item)
        }
        if let target = plan.target {
            if emitTargetImmediately {
                emitPhase(target)
            } else {
                phases.apply(phase: target.0, autoAdvance: target.1)
            }
        }
    }

    /// Moves the phase machine on and sends a frame without distance that carries the phase
    /// ("Trackpad-style events" on) or no phase fields (off).
    func emitPhase(_ item: (Phase, Phase?)) {
        phases.apply(phase: item.0, autoAdvance: item.1)
        let phaseOverride = config.simTrackpadEnabled ? phaseValues(for: item.0) : nil
        // 无可用事件时不发送, 状态机照常推进
        if !post((y: 0.0, x: 0.0), phaseOverride: phaseOverride, fallbackToCurrentPhase: false) {
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
    /// At most one request is made per wheel input, however many frames run before the main
    /// thread has carried it out.
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
        var pendingStopPhase: Phase?
        // 插值并平滑 (按真实帧间隔)
        let filledValue = advanceMotionLocked(frameInterval: frameInterval)
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
        if outputMagnitude > deadZone && post(shiftedValue) {
            let moved = abs(shiftedValue.y) + abs(shiftedValue.x)
            sessionLog.frames += 1
            sessionLog.postedDistance += moved.rounded(.towardZero)
            sessionLog.largestFrame = max(sessionLog.largestFrame, moved)
            sessionLog.lastFrameAt = now
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

    /// 推进一帧: 插值 current -> buffer 并经滤波得到本帧输出。调用方须持有 stateLock。
    func advanceMotionLocked(frameInterval: Double) -> (y: Double, x: Double) {
        // 按真实帧间隔换算插值系数 (以 60Hz 为参考, 不同刷新率下滚动时长一致)
        let trans = ScrollMotion.transition(duration, frameInterval: frameInterval)
        // 计算插值
        let frame = (
            y: Interpolator.lerp(src: current.y, dest: buffer.y, trans: trans),
            x: Interpolator.lerp(src: current.x, dest: buffer.x, trans: trans)
        )
        // 更新滚动位置
        current = (
            y: current.y + frame.y,
            x: current.x + frame.x
        )
        // 平滑起步 (见 ScrollFilter)。权重随帧间隔与 Duration 而变, 滤波器因此多存或少存的距离
        // 按 trans 的比例补发, 不丢失也不突跳
        let weight = ScrollMotion.transition(ScrollMotion.filterWeight(forTransition: duration), frameInterval: frameInterval)
        return filter.fill(with: frame, weight: weight, catchUp: trans)
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

    func phaseValues(for phase: Phase) -> (scroll: Double, momentum: Double)? {
        guard let scrollValue = PhaseValueMapping[phase]?[.Scroll],
              let momentumValue = PhaseValueMapping[phase]?[.Momentum] else {
            return nil
        }
        return (scroll: scrollValue, momentum: momentumValue)
    }

    /// 组装并发送一帧。没有可用事件时返回 false (未发送)。
    @discardableResult
    func post(_ v: (y: Double, x: Double), phaseOverride: (scroll: Double, momentum: Double)? = nil, fallbackToCurrentPhase: Bool = true, using preparedSnapshot: ScrollDispatchContext.PostingSnapshot? = nil) -> Bool {
        var phaseValues = phaseOverride
        if phaseValues == nil && fallbackToCurrentPhase && config.simTrackpadEnabled {
            phaseValues = self.phaseValues(for: phases.phase)
        }
        let frame = ScrollOutgoingFrame(y: v.y, x: v.x, scrollPhase: phaseValues?.scroll, momentumPhase: phaseValues?.momentum)
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
    /// Ties the display link to the display the pointer is on, before a scroll starts.
    ///
    /// A display link fires in step with one display. Two displays, even at the same rate,
    /// refresh at different moments that drift against each other, so frames timed for the
    /// main display reach a window on the other one now early, now late: every so often a
    /// refresh shows no movement and the next one shows twice as much.
    func followDisplayUnderPointer(_ link: CVDisplayLink) {
        guard let location = CGEvent(source: nil)?.location else { return }
        var display: CGDirectDisplayID = 0
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(location, 1, &display, &count) == .success, count > 0,
              display != CVDisplayLinkGetCurrentCGDisplay(link) else { return }
        CVDisplayLinkSetCurrentCGDisplay(link, display)
    }
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
