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

    /// Whether the poster can work with it. A stored Step or Speed that is not a finite
    /// number (a hand-edited preference: a Step of 1e308 times Speed is infinite) gives a
    /// distance no frame can move toward: nothing was posted, the scroll never ended and the
    /// display link ran on. Such an event is let through unsmoothed instead.
    var isUsable: Bool {
        return y.isFinite && x.isFinite && notch.isFinite && duration.isFinite
    }
}

/// Where a wheel event goes: the app that gets it and the pointer's place (global points).
struct ScrollInputPlace: Equatable {
    var pid: pid_t
    var pointer: CGPoint
}

/// One scroll event as ScrollPoster sends it.
struct ScrollOutgoingFrame: Equatable {
    /// Pixel deltas.
    var y: Double
    var x: Double
    /// Phase field values; nil leaves the phase fields of the copied wheel event alone.
    var scrollPhase: Double? = nil
    var momentumPhase: Double? = nil
    /// Event timestamp (`ScrollEventClock.uptimeNanoseconds`); nil keeps the copied wheel event's.
    /// Given with "Trackpad-style events" only: apps take the speed of a gesture from the time
    /// between its events, and every frame of a wheel tick used to carry that tick's time.
    var timestamp: UInt64? = nil

    /// Only the point delta is written; the line delta stays that of the copied wheel event,
    /// and so does the timestamp unless one is given. CoreGraphics drops the fraction of a point
    /// delta, so the frames of a glide come here in whole pixels (ScrollPixelCarry keeps the
    /// fraction for the next).
    func write(to event: CGEvent) {
        if let scrollPhase = scrollPhase, let momentumPhase = momentumPhase {
            event.setDoubleValueField(.scrollWheelEventScrollPhase, value: scrollPhase)
            event.setDoubleValueField(.scrollWheelEventMomentumPhase, value: momentumPhase)
        }
        if let timestamp = timestamp {
            event.timestamp = timestamp
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
    }

    // 阶段状态机
    private let phases: ScrollPhase
    // 插值器
    private let filter = ScrollFilter()
    // 发送器
    private var poster: ScrollDisplayLink?
    /// Makes a display link. Tests stand in for a display here.
    var makeDisplayLink: () -> (link: ScrollDisplayLink?, result: CVReturn) = {
        ScrollCVDisplayLink.make(output: ScrollPoster.displayLinkOutput)
    }
    /// The kind of the app a wheel event goes to, for the form of "Trackpad-style scrolling"
    /// (asked only while that is on). Tests say the kind here: no running app is looked up.
    var trackpadStyleTarget: (CGEvent) -> ScrollUtils.TrackpadStyleTarget = {
        ScrollUtils.shared.trackpadStyleTarget(of: $0)
    }
    /// Seconds on a clock that is never set back or forward (the wall clock was used here:
    /// set back by a time sync, it refused every new display link and kept a touch open for
    /// as long as it was set back). Both threads read the same clock.
    static func monotonicNow() -> CFTimeInterval {
        return Double(ScrollEventClock.uptimeNanoseconds()) / 1_000_000_000
    }
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
    // 每帧只发整数像素, 小数部分留给下一帧 (见 ScrollPixelCarry)
    private var pixelCarry = ScrollPixelCarry()
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
    // "Trackpad-style events": how a wheel scroll looks as a trackpad gesture. Two forms, by what
    // the app under the pointer does with the events of a glide ("momentum"):
    //
    // - AppKit and UIKit scroll views (Finder, Settings, Notes, most apps) follow the touch only.
    //   When it ends they compute a glide of their own from its speed and ignore what the
    //   momentum events say (measured in the owner's recording of a Finder list: 7,225 px posted,
    //   mostly as momentum, moved the list by ~250 pt along AppKit's own decay). For them the
    //   touch lasts as long as the wheel turns (until it has been still for
    //   `manualContinuationThreshold`), and only the tail goes out as momentum.
    // - The Chromium engine (Chrome, Dia, Arc, Electron apps) scrolls by the momentum events
    //   too. For it the scroll is a flick (`config.flick`), as described below.
    // - Safari gets no phases at all, as with the switch off: with them it does not scroll
    //   smoothly (`ScrollUtils.TrackpadStyleTarget.plainScrolling` says what was tried).
    //
    // A real flick is a short touch (3 or 4 events, ~50 ms) and then a long glide (momentum).
    // At a page edge apps treat the two very differently: the touch drags the page past the edge
    // as a finger would (the stretch follows every delta, with resistance, until the finger lifts),
    // while a glide that reaches the edge starts the bounce at once, sized by the glide's speed,
    // and the rest of the glide is ignored. Sent as one long touch for as long as the wheel turned
    // (and 0.18 s more), a fast scroll dragged the page far past the edge and held it there, and a
    // tick that put the finger down again during the bounce made the page jump.
    /// The finger lifts this long after the touch began; the rest of the scroll is its glide.
    private let trackpadStyleTouchTime: CFTimeInterval = 0.045
    /// When the current touch began ("began" planned), for `fingerLiftedLocked`.
    private var touchBeganTime: CFTimeInterval = 0.0
    /// A tick turned back during the glide; its touch begins with the first frame that moves its way.
    private var touchWaitsForTurn = false
    /// The direction of the touch and its glide: the last wheel input that did not ask for a turn.
    private var glideDelta = (y: 0.0, x: 0.0)
    /// Where the current touch began and where the last wheel input was. nil: not known, or the
    /// touch began without trackpad-style events (the app got no "began" for it).
    private var touchPlace: ScrollInputPlace?
    private var lastInputPlace: ScrollInputPlace?
    /// A tick adds to the glide only where its touch began: in the same app, with the pointer no
    /// farther than this (points) from there. Apps keep a gesture on the scroller that got its
    /// "began", so a tick over another pane has to begin a touch of its own; a hand that turns
    /// the wheel moves the pointer by a few points at most.
    private let trackpadStylePointerSlack: CGFloat = 30
    // Ending a session from the display link (see `displayLinkFrameLocked`)
    /// Counts wheel inputs; a stop the display link asked for is dropped when it is stale.
    private var inputSequence: UInt64 = 0
    /// Input sequence of the stop request already handed to the main thread; nil = none yet.
    private var requestedStopSequence: UInt64?
    /// Counts the frames handed to the post queue (`post`), so that `stop(_:)` knows whether
    /// it queued a closing frame. Guarded by stateLock.
    private var queuedFrames: UInt64 = 0
    // 状态锁和投递上下文
    private var stateLock = os_unfair_lock_s()
    private let dispatchContext: ScrollDispatchContext
    // 滚动配置快照: 主线程在 update 时捕获, CVDisplayLink 线程只读, 避免热路径跨线程读 Options/ScrollCore
    private struct ConfigSnapshot {
        /// "Trackpad-style events": the frames carry trackpad phases.
        var simTrackpadEnabled: Bool
        /// Trackpad-style for an app that scrolls by the events of a glide (`ScrollUtils
        /// .trackpadStyleTarget`): a short touch and its glide. Without it the touch lasts as long
        /// as the wheel turns, as it always did.
        var flick: Bool
        /// The switch is on, but this app gets no trackpad-style events (Safari:
        /// `ScrollUtils.TrackpadStyleTarget.plainScrolling`); `simTrackpadEnabled` is false then.
        var withheld = false
        var deadZone: Double
    }
    private var config = ConfigSnapshot(simTrackpadEnabled: false, flick: false, deadZone: 1.0)
#if DEBUG
    /// Tests: receives every frame instead of posting it.
    var frameRecorderForTests: ((ScrollOutgoingFrame) -> Void)?
    /// Tests: with `frameRecorderForTests`, also receives the process each frame would be
    /// posted to (0: none is known).
    var targetRecorderForTests: ((ScrollOutgoingFrame, pid_t) -> Void)?
    /// Tests: the clock of the frames' timestamps (`ScrollEventClock.uptimeNanoseconds` otherwise).
    var eventClockForTests: (() -> UInt64)?
    /// Tests: the lines about the display link's health written to the `app` log, oldest first.
    var healthLinesForTests: [String] = []
    /// The cumulative drop counters of the dispatch context, as `stop` logs them.
    struct DropCounts: Equatable {
        var byGeneration: UInt64 = 0
        var byTTL: UInt64 = 0
        var snapshotFailures: UInt64 = 0

        /// The counters only grow: once one was above 0, every stop logged a line. A line is
        /// written when they changed since the last one.
        func isLogDue(lastLogged: DropCounts) -> Bool {
            return self != DropCounts() && self != lastLogged
        }
    }
    /// What the last diagnostics line said (main thread, in `stop`).
    private var lastLoggedDrops = DropCounts()
#endif
    // CVDisplayLink 恢复机制
    private var keeper: Timer?
    static let keeperInterval: TimeInterval = 5.0
    private var lastCallbackTime: CFTimeInterval = 0.0
    private var lastRecreateAttempt: CFTimeInterval = 0.0
    private let recreateCooldown: CFTimeInterval = 3.0
    /// Tries to make a display link that failed since the last one that worked. The log gets
    /// the first failure and the first success after it, not a line per try: with the display
    /// off a try fails every time, and the keeper tried every 5 s (720 error lines an hour).
    private var failedDisplayLinkTries = 0
    /// While no link can be made, the keeper tries again after this long, twice as long after
    /// every failure up to `missingLinkBackoffLimit`. A display that wakes and the next wheel
    /// event try at once.
    private var missingLinkBackoff: TimeInterval = ScrollPoster.keeperInterval
    private var missingLinkRetryAt: CFTimeInterval = 0.0
    static let missingLinkBackoffLimit: TimeInterval = 60.0
    private var screensDidWakeObserver: NSObjectProtocol?
    /// When the poster last had something to do: a wheel input, a posted frame, or the start
    /// of the display link. Guarded by stateLock. The keeper stops a link that runs on long
    /// after it (`idleLinkLimit`): the app idles at 0 % CPU whatever state it got into.
    private var lastActivityTime: CFTimeInterval = 0.0
    /// No scroll leaves the link running this long with nothing posted and no wheel event:
    /// a scroll ends a quarter of a second after its last frame.
    static let idleLinkLimit: TimeInterval = 5.0
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
    /// Whether a scroll runs: from its first wheel event until its stop.
    var isGliding: Bool {
        os_unfair_lock_lock(&stateLock)
        defer { os_unfair_lock_unlock(&stateLock) }
        return !sessionLog.isEmpty
    }
}

// MARK: - 滚动数据更新控制
extension ScrollPoster {
    /// What "Trackpad-style events" come to for an app of the given kind (nil: not known, as
    /// touch-only): whether the frames carry phases at all, as a flick or as one long touch, and
    /// whether the switch is on but the app gets none.
    static func trackpadStyleForm(switchOn: Bool, target: ScrollUtils.TrackpadStyleTarget?) -> (phases: Bool, flick: Bool, withheld: Bool) {
        guard switchOn else {
            return (phases: false, flick: false, withheld: false)
        }
        switch target {
        case .plainScrolling:
            return (phases: false, flick: false, withheld: true)
        case .followsGlide:
            return (phases: true, flick: true, withheld: false)
        case .touchOnly, nil:
            return (phases: true, flick: false, withheld: false)
        }
    }

    /// Whether "Trackpad-style scrolling" is on for an app: its own setting when it keeps its
    /// own (`application` is its entry in the Apps pane, nil when it has none), else the
    /// Scrolling pane's.
    static func trackpadStyleIsOn(application: Application?, global: OPTIONS_SCROLL_DEFAULT) -> Bool {
        if let application = application, !application.inherit {
            return application.scroll.smoothSimTrackpad
        }
        return global.smoothSimTrackpad
    }

    /// One wheel event to smooth. Main thread (the scroll tap's callback).
    ///
    /// "Can this event be smoothed now?" is asked before anything of it is stored:
    /// - its distance is no finite number (`ScrollPosterInput.isUsable`), or no display link
    ///   runs and none can be started (the display is off; the link's display is gone):
    ///   nothing here is touched, and the caller lets the event through. The poster used to be
    ///   fed first. Without a link the scroll then counted as open, a "began" had gone out
    ///   that never got its "ended", and the distance waited in the buffer for a link while
    ///   the event went through as well; with a link that could not be started the event was
    ///   swallowed and nothing was posted.
    /// - it goes to another app than the scroll that runs: that scroll is ended first
    ///   (`endScroll(unlessFor:)`).
    /// - its scroll carries trackpad phases and the scroll that runs has none, or the other
    ///   way round (the switch, the app's own setting or "Reset to Defaults" changed in
    ///   mid-scroll): that scroll is ended first, in the form it was sent in
    ///   (`endScroll(unlessPhasesStay:)`).
    /// - Returns: whether the event was taken. false: the caller lets it through.
    func smooth(event: CGEvent, input: ScrollPosterInput) -> Bool {
        guard input.isUsable else { return false }
        let target = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
        endScroll(unlessFor: target)
        // 捕获本次手势的配置快照 (主线程读 Options/ScrollCore, CVDisplayLink 线程只读)
        let snapshot = configSnapshot(for: event)
        endScroll(unlessPhasesStay: snapshot.simTrackpadEnabled)
        guard tryStart(), dispatchContext.capture(event: event) else { return false }
        os_unfair_lock_lock(&stateLock)
        defer { os_unfair_lock_unlock(&stateLock) }
        applyConfigLocked(snapshot)
        let place = config.flick ? ScrollInputPlace(pid: target, pointer: event.location) : nil
        handleInputLocked(input, at: Self.monotonicNow(), place: place)
        return true
    }
    /// Ends the scroll that runs when the next wheel event goes to another process, before
    /// anything of that event is stored (the event to copy, its target, the app's settings).
    /// The closing frames ("ended", "momentum ended") then go to the app that got the scroll,
    /// in that scroll's form; the new event begins a scroll of its own. They used to go to
    /// the new event's app, and so did the rest of the glide: the first app kept a touch or
    /// a glide open (with trackpad-style events), and the second got a "momentum ended" or
    /// "changed" frames for a touch it never saw begin. As a left click ends a scroll.
    private func endScroll(unlessFor target: pid_t) {
        guard let running = dispatchContext.targetPID, running != target, isGliding else { return }
        stop(reason: .anotherApp)
    }
    /// Ends the scroll that runs when the next wheel event's scroll carries trackpad phases
    /// and the running one does not, or the other way round: "Trackpad-style scrolling", the
    /// app's own setting or "Reset to Defaults" was changed in mid-scroll (from the keyboard;
    /// a click ends the scroll anyway). The running scroll is closed in the form it was sent
    /// in, and the wheel event begins a scroll of its own. It used to be taken over into the
    /// new form: the frames went on without phases, so did the closing ones, and an app that
    /// had got "began" (or "momentum began") never got its "ended".
    /// The two forms that carry phases pass into each other without an end: the first scroll
    /// over a Chromium-based app begins as one touch and goes on as a flick.
    private func endScroll(unlessPhasesStay phases: Bool) {
        os_unfair_lock_lock(&stateLock)
        let changes = !sessionLog.isEmpty && config.simTrackpadEnabled != phases
        os_unfair_lock_unlock(&stateLock)
        guard changes else { return }
        stop(reason: .settingChanged)
    }
    /// 处理一次滚轮输入: 缓冲与阶段 (调用方须持有 stateLock)
    private func handleInputLocked(_ input: ScrollPosterInput, at now: CFTimeInterval, place: ScrollInputPlace? = nil) {
        if sessionLog.isEmpty {
            sessionLog.startedAt = now
        }
        sessionLog.inputs += 1
        sessionLog.transition = input.duration
        sessionLog.inputDistance += abs(input.y) + abs(input.x)
        sessionLog.lastInputAt = now
        sessionLog.trackpadStyle = config.simTrackpadEnabled
        sessionLog.flick = config.flick
        sessionLog.trackpadStyleWithheld = config.withheld
        lastActivityTime = now
        inputSequence &+= 1
        if !config.flick {
            // The form can differ per app: a turn asked for in a flick is not carried into a
            // scroll that is not one.
            touchWaitsForTurn = false
        }
        lastInputPlace = place
        let separatedByTime = lastManualEventTime <= 0.0 || now - lastManualEventTime >= manualSeparationThreshold
        // Trackpad-style, while the glide (momentum) runs: a tick in its direction adds to it. A new
        // touch ("began") takes hold of a page that may be bouncing at an edge, and a touch that then
        // moves toward the edge snaps the stretch to what that touch alone would give (WebKit forgets
        // the stretch's force on "began"): the page jumped. A tick the other way starts a new touch,
        // but only with the first frame that moves the other way (`touchWaitsForTurn`): until the
        // motion has turned, its frames still go toward the edge and stay part of the glide.
        // Only where the touch began (`staysAtTouchPlaceLocked`): over another pane or app the tick
        // begins a touch of its own, as it did before.
        let inGlide = config.flick
            && (phases.phase == .MomentumBegin || phases.phase == .MomentumOngoing)
            && staysAtTouchPlaceLocked(place)
        let addsToGlide = inGlide && continuesGlideLocked(input)
        applyInputLocked(input, at: now)
        if inGlide {
            // A tick back in the glide's direction takes back a turn that has not happened yet.
            touchWaitsForTurn = !addsToGlide
            if addsToGlide {
                sessionLog.glideInputs += 1
            }
            lastManualEventTime = now
            momentumEndScheduledTime = nil
            trackingEndScheduledTime = nil
            return
        }
        if config.simTrackpadEnabled {
            // (Both forms. As one long touch the glide's "momentum ended" went out here
            // although its "momentum began" had not: no frame of the glide had been posted.)
            phases.dropWaitingMomentumBegan()
        }
        let phase = phases.phase
        let separatedPhase = (phase == .Idle || phase == .Leave || phase == .MomentumEnd || phase == .TrackingEnd)
        let separated = manualInputEnded || separatedByTime || separatedPhase
        let plan = phases.onManualInputDetected(isSeparated: separated)
        if plan.beginsTouch {
            touchBeganTime = now
            touchPlace = place
            sessionLog.touches += 1
        }
        touchWaitsForTurn = false
        glideDelta = delta
        perform(plan, emitTargetImmediately: false)
        lastManualEventTime = now
        manualInputEnded = false
        momentumActive = false
        momentumEndScheduledTime = nil
        trackingEndScheduledTime = nil
    }
    /// Whether a wheel input goes on in the glide's direction: the same sign on each axis that
    /// moved, and no axis newly moving. Compared with the glide (`glideDelta`), not with the last
    /// input: a tick back and at once forward again goes on with the glide. Caller holds stateLock.
    private func continuesGlideLocked(_ input: ScrollPosterInput) -> Bool {
        guard input.y != 0.0 || input.x != 0.0 else { return false }
        let sameY = input.y == 0.0 ? glideDelta.y == 0.0 : input.y * glideDelta.y > 0
        let sameX = input.x == 0.0 ? glideDelta.x == 0.0 : input.x * glideDelta.x > 0
        return sameY && sameX
    }
    /// Whether a wheel input is for the scroller its touch began on, as far as can be told: the
    /// same app, the pointer within `trackpadStylePointerSlack` of where the touch began. A touch
    /// that began without a known place (trackpad-style events were off for it) is not gone on
    /// with: its app got no "began". Caller holds stateLock.
    private func staysAtTouchPlaceLocked(_ place: ScrollInputPlace?) -> Bool {
        guard let began = touchPlace else { return place == nil }
        guard let place = place else { return true }
        guard place.pid == began.pid else { return false }
        return hypot(place.pointer.x - began.pointer.x, place.pointer.y - began.pointer.y) <= trackpadStylePointerSlack
    }
    /// Trackpad-style: the glide's motion has turned to the last input's direction; the touch that
    /// input asked for begins now ("momentum ended", "began"), and this frame is its first "changed".
    /// Caller holds stateLock.
    private func beginTouchAfterTurnLocked(now: CFTimeInterval) {
        touchWaitsForTurn = false
        glideDelta = delta
        touchPlace = lastInputPlace
        sessionLog.touches += 1
        phases.dropWaitingMomentumBegan()
        perform(phases.onManualInputDetected(isSeparated: true), emitTargetImmediately: false)
        touchBeganTime = now
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
    /// Sets the config snapshot directly (an event would read it from Options). `flick`: the app
    /// under the pointer scrolls by the events of a glide (it only counts with trackpad-style on).
    /// Nothing is ended: for the form of a scroll before it begins. In mid-scroll a wheel
    /// event's form arrives as `changeFormForTests` takes it up.
    func setConfigForTests(simTrackpadEnabled: Bool, deadZone: Double = 1.0, flick: Bool = true) {
        os_unfair_lock_lock(&stateLock)
        applyConfigLocked(ConfigSnapshot(simTrackpadEnabled: simTrackpadEnabled, flick: simTrackpadEnabled && flick, deadZone: deadZone))
        os_unfair_lock_unlock(&stateLock)
    }
    /// The form the next wheel event arrives in, taken up as `smooth(event:input:)` does it: a
    /// scroll that runs with phases is ended first when the new form has none, and the other
    /// way round.
    func changeFormForTests(simTrackpadEnabled: Bool, deadZone: Double = 1.0, flick: Bool = true) {
        endScroll(unlessPhasesStay: simTrackpadEnabled)
        setConfigForTests(simTrackpadEnabled: simTrackpadEnabled, deadZone: deadZone, flick: flick)
    }
    /// One wheel event through the whole input path (buffer, lead cap, phases, session log),
    /// without an event to copy. Frames go to `frameRecorderForTests`.
    /// `targetPID`: the process the event goes to, as `smooth(event:input:)` handles it: a
    /// scroll that runs for another process is ended first.
    func inputForTests(_ input: ScrollPosterInput, at time: CFTimeInterval, place: ScrollInputPlace? = nil, targetPID: pid_t? = nil) {
        if let targetPID = targetPID {
            endScroll(unlessFor: targetPID)
            dispatchContext.setTargetForTests(targetPID)
        }
        os_unfair_lock_lock(&stateLock)
        handleInputLocked(input, at: time, place: place)
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
    var displayLinkForTests: ScrollDisplayLink? { return poster }
    var isDisplayLinkRunningForTests: Bool {
        return poster?.isRunning ?? false
    }
    /// Lets the next `recreateDisplayLink` through at once.
    func clearRecreateCooldownForTests() {
        lastRecreateAttempt = 0
    }
    /// Stops and forgets the display link, as if none had been made yet.
    func dropDisplayLinkForTests() {
        poster?.stop()
        poster = nil
    }
    /// One look of the keeper, now or at `now` (`monotonicNow`'s clock).
    func healthCheckForTests(now: CFTimeInterval? = nil) {
        healthCheck(now: now ?? Self.monotonicNow())
    }
    /// The whole display link callback at `now`, including the hop to the main thread.
    func displayLinkCallbackForTests(frameInterval: Double, now: CFTimeInterval) {
        os_unfair_lock_lock(&stateLock)
        lastCallbackTime = now
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
        pixelCarry.reset()
        lastFrameHostTime = 0
        // 重置插值器
        filter.reset()
        phases.reset()
        manualInputEnded = true
        momentumActive = false
        lastManualEventTime = 0.0
        touchBeganTime = 0.0
        touchWaitsForTurn = false
        glideDelta = ( y: 0.0, x: 0.0 )
        touchPlace = nil
        lastInputPlace = nil
        momentumEndScheduledTime = nil
        trackingEndScheduledTime = nil
    }
}

// MARK: - 插值数据发送控制
extension ScrollPoster {
    /// The display link's output callback (the link's own thread): one frame of the shared poster.
    static let displayLinkOutput: CVDisplayLinkOutputCallback = { (_, _, inOutputTime, _, _, _) -> CVReturn in
        ScrollPoster.shared.processing(outputTime: inOutputTime.pointee)
        return kCVReturnSuccess
    }

    // 初始化 CVDisplayLink
    /// Makes a display link and puts it in the place of the one in use. The new one is made
    /// first; the old one is stopped and replaced only when that worked. It used to be
    /// released first: a try that fell into a moment without an active display (the display
    /// asleep, an external one switched off with the lid closed) threw away a link that
    /// worked and left none.
    /// - Returns: whether a new link is in place.
    @discardableResult
    func create() -> Bool {
        // 创建新的 CVDisplayLink, 检查返回值
        let made = makeDisplayLink()
        guard made.result == kCVReturnSuccess, let newPoster = made.link else {
            if failedDisplayLinkTries == 0 {
                logHealth(problem: Self.displayLinkFailureLine(result: made.result, keepsTheLinkInUse: poster != nil))
            }
            failedDisplayLinkTries += 1
            return false
        }
        if failedDisplayLinkTries > 0 {
            logHealth(note: Self.displayLinkRecoveryLine(failedTries: failedDisplayLinkTries))
            failedDisplayLinkTries = 0
        }
        // 清理旧的 CVDisplayLink
        if let old = poster, old.isRunning {
            old.stop()
        }
        poster = newPoster
        // 建立成功后安排刷新率复查; 复查内部触发的重建 (isVerifying) 不重置复查序列
        if !isVerifying { scheduleRateVerify() }
        return true
    }
    /// The one line for a display link that cannot be made, however many tries fail after it.
    static func displayLinkFailureLine(result: CVReturn, keepsTheLinkInUse: Bool) -> String {
        let consequence = keepsTheLinkInUse
            ? "the link in use stays"
            : "wheel events go through unsmoothed until one can be made"
        return "ScrollPoster: no display link can be made (CVReturn \(result); -6661 while no display is on): \(consequence). "
            + "Trying again when a display wakes, with the next wheel event and from the keeper; the next line is written when it worked"
    }
    static func displayLinkRecoveryLine(failedTries: Int) -> String {
        return "ScrollPoster: a display link could be made again, after \(failedTries) failed \(failedTries == 1 ? "try" : "tries")"
    }
    private func logHealth(problem line: String) {
#if DEBUG
        healthLinesForTests.append(line)
#endif
        AppSystemLog.problem(line)
    }
    private func logHealth(note line: String) {
#if DEBUG
        healthLinesForTests.append(line)
#endif
        AppSystemLog.note(line)
    }
    // 启动事件发送器
    /// Makes sure a display link runs, for a wheel event that waits to be smoothed.
    /// - Returns: whether one runs now. false: there is none and none can be made (or not
    ///   yet again: one try per `recreateCooldown`), or the one there cannot be started and
    ///   could not be replaced.
    @discardableResult
    func tryStart() -> Bool {
        guard let validPoster = poster else {
            recreateDisplayLink(scrollWaiting: true)
            return poster?.isRunning ?? false
        }
        if validPoster.isRunning {
            return true
        }
        validPoster.followDisplayUnderPointer()
        if validPoster.start() == kCVReturnSuccess {
            // 给 keeper 一个宽限期, 防止误判新启动的 poster 为僵尸
            noteDisplayLinkStarted()
            return true
        }
        // It cannot be started (the display it follows is gone): a new one, when the cooldown allows.
        recreateDisplayLink(scrollWaiting: true)
        return poster?.isRunning ?? false
    }
    /// A link was started: the keeper counts from now (no frame yet, nothing posted yet).
    private func noteDisplayLinkStarted() {
        let now = Self.monotonicNow()
        os_unfair_lock_lock(&stateLock)
        lastCallbackTime = now
        lastActivityTime = now
        os_unfair_lock_unlock(&stateLock)
    }
    // 停止事件发送器
    /// Ends the scroll that runs, if one does, and stops the display link. Main thread.
    /// - Parameters:
    ///   - requestedPhase: the phase to end with (a momentum is finished whatever was asked).
    ///   - reason: why, for the scroll's line in the log.
    func stop(_ requestedPhase: Phase = Phase.MomentumEnd, reason: ScrollSystemLog.EndReason = .stopped) {
        // 停止循环, 然后准备发送最后一次事件
        let wasRunning = poster?.isRunning ?? false
        poster?.stop()
        os_unfair_lock_lock(&stateLock)
        // 失效旧会话异步帧，收尾帧使用新代次
        // Only when there is something to end. Every stop used to move the generation: a
        // second stop in the same turn of the run loop (the tap's restart and then its
        // "disabled" event, the keeper and then `disable()`, a stop the display link asked
        // for after a left click) moved it again and could drop the closing frame the first
        // had just queued: a "began" without its "ended".
        if !sessionLog.isEmpty || wasRunning {
            dispatchContext.advanceGeneration()
        }

        // 判断是否启用触控板模拟 (读 update 时主线程捕获的快照, 避免跨线程读)
        let enableSimTrackpad = config.simTrackpadEnabled
        let plan: ScrollPhase.TransitionPlan
        // In a momentum phase the momentum is finished whatever phase was asked for: the plan
        // of onManualInputEnded is empty there, and a stop for TrackingEnd (tap timeout or
        // restart) left a momentum "began" without its "ended".
        let inMomentum = phases.phase == .MomentumBegin || phases.phase == .MomentumOngoing
        if requestedPhase == Phase.MomentumEnd || inMomentum {
            plan = phases.onMomentumFinish()
        } else {
            plan = phases.onManualInputEnded()
        }

        // 发送结束事件
        let queuedBefore = queuedFrames
        if enableSimTrackpad {
            perform(plan, emitTargetImmediately: true)
        } else {
            // Chrome only, from Mos ("only [4, 0] lets Chrome recover"): after frames without
            // phases Chrome stays in its scroll until an "ended" arrives, so one is posted at
            // every stop although the switch is off. Kept exactly as it was: it is part of
            // what Chrome gets at the default settings, and whether Chrome still needs it (or
            // the other Chromium apps want it too) can only be seen on screen.
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
        // With trackpad-style phases only. Without them nothing an app waits for is queued
        // here (Chrome's "ended" below goes out as it always did), and a stop waits for nothing.
        let closingFrameQueued = enableSimTrackpad && queuedFrames != queuedBefore
        manualInputEnded = true
        momentumActive = false
        let finished = sessionLog
        sessionLog = ScrollSystemLog.Session()
        // 重置参数 (不递增 generation, 保留本次收尾帧有效性)
        resetUnlocked()
        os_unfair_lock_unlock(&stateLock)
        if closingFrameQueued {
            // The closing frames ("ended", "momentum ended") are out before this returns.
            // They are posted from the post queue, and what ended the scroll is often an
            // event on its own way to the same app: a finger that begins to scroll on the
            // trackpad (the tap's callback lets that "began" through right after this), a
            // click. Nothing ordered the two: when the trackpad's "began" arrived first, the
            // app got "began, ended" and the finger's scroll had no gesture left. At quit the
            // process could be gone before the frame was posted. The wait is short and
            // certain: see `ScrollDispatchContext.waitForQueuedFrames`.
            dispatchContext.waitForQueuedFrames()
        }
        if !finished.isEmpty {
            ScrollSystemLog.note(finished, ended: reason)
        }
#if DEBUG
        let diag = diagnosticsSnapshot()
        let drops = DropCounts(byGeneration: diag.droppedFramesByGeneration, byTTL: diag.droppedFramesByTTL,
                               snapshotFailures: diag.updateSnapshotFailures)
        if drops.isLogDue(lastLogged: lastLoggedDrops) {
            lastLoggedDrops = drops
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
    /// slip in between this check and the reset in `stop(_:)`. It is stale too when the
    /// scroll was ended meanwhile (a left click, a finger on the trackpad, the tap's
    /// restart): there is nothing left to stop.
    /// - Returns: false when the request was stale and nothing was done.
    @discardableResult
    func performRequestedStop(_ request: ScrollStopRequest) -> Bool {
        assertMainThread()
        os_unfair_lock_lock(&stateLock)
        let isCurrent = request.inputSequence == inputSequence && !sessionLog.isEmpty
        os_unfair_lock_unlock(&stateLock)
        guard isCurrent else { return false }
        stop(request.phase, reason: .glidedOut)
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
        let now = Self.monotonicNow()
        guard now - lastRecreateAttempt >= recreateCooldown else { return false }
        let previousAttempt = lastRecreateAttempt
        lastRecreateAttempt = now
        let replacedWasRunning = poster?.isRunning ?? false
        guard create() else {
            // None could be made and nothing was replaced. Only a wheel event's failed try
            // holds the cooldown (one try per cooldown, however many events come); after the
            // keeper's or a screen change's the next wheel event may try at once. It used to
            // be refused for 3 s and went through unsmoothed.
            if !scrollWaiting {
                lastRecreateAttempt = previousAttempt
            }
            return true
        }
        if Self.startsRecreatedDisplayLink(replacedWasRunning: replacedWasRunning, scrollWaiting: scrollWaiting),
           let validPoster = poster {
            // A new link is tied to the main display: tie it to the display the pointer is on
            // before it runs, as tryStart does (a glide on a second display stuttered otherwise).
            validPoster.followDisplayUnderPointer()
            let result = validPoster.start()
            if result == kCVReturnSuccess {
                noteDisplayLinkStarted()
            } else {
                logHealth(problem: "ScrollPoster: CVDisplayLink start failed after recreate (\(result))")
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
        keeper = CommonModesTimer.scheduled(withTimeInterval: Self.keeperInterval, repeats: true) { [weak self] _ in
            self?.healthCheck(now: ScrollPoster.monotonicNow())
        }
        if screensDidWakeObserver == nil {
            screensDidWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                self?.screensDidWake()
            }
        }
    }
    func stopKeeper() {
        keeper?.invalidate()
        keeper = nil
        if let observer = screensDidWakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            screensDidWakeObserver = nil
        }
        rateVerifyTimer?.invalidate()
        rateVerifyTimer = nil
        rateVerifyAttemptsLeft = 0
    }
    /// A display is on again: the link that could not be made while none was on is made now
    /// (not started: the next wheel event's `tryStart` starts it). A link in use stays; a
    /// screen change replaces it (AppDelegate).
    func screensDidWake() {
        guard poster == nil else { return }
        missingLinkBackoff = Self.keeperInterval
        missingLinkRetryAt = 0
        recreateDisplayLink()
    }
    /// The keeper's look, every `keeperInterval`. `now`: `monotonicNow()`.
    private func healthCheck(now: CFTimeInterval) {
        os_unfair_lock_lock(&stateLock)
        let lastCallback = lastCallbackTime
        let lastActivity = lastActivityTime
        let scrollIsOpen = !sessionLog.isEmpty
        os_unfair_lock_unlock(&stateLock)
        guard let validPoster = poster else {
            // No link could be made (the display is off): try again, less and less often.
            // Made, not started: the next wheel event's tryStart starts it.
            guard now >= missingLinkRetryAt else { return }
            recreateDisplayLink()
            if poster == nil {
                missingLinkRetryAt = now + missingLinkBackoff
                missingLinkBackoff = min(missingLinkBackoff * 2, Self.missingLinkBackoffLimit)
            } else {
                missingLinkBackoff = Self.keeperInterval
                missingLinkRetryAt = 0
            }
            return
        }
        guard validPoster.isRunning else {
            // A scroll that is open while its link does not run (a replaced link that could
            // not be started) gets no frame and never ends by itself.
            if scrollIsOpen {
                logHealth(problem: "ScrollPoster: the keeper found a scroll open while its display link does not run, ending the scroll")
                stop(reason: .keeper)
            }
            return
        }
        // The safety net: a link that runs on with nothing to do. Whatever state kept it
        // running (a scroll that could not end, a link that sends no frames), the app idles
        // at 0 % CPU again. Asked first: a stuck link nobody scrolls with is stopped, not
        // replaced by a running one every 5 s.
        if now - lastActivity > Self.idleLinkLimit {
            logHealth(problem: String(
                format: "ScrollPoster: the keeper stopped a display link that ran for %.0f s with nothing posted and no wheel event",
                now - lastActivity
            ))
            stop(reason: .keeper)
            return
        }
        // lastTime > 0 避免首次回调前误判
        if lastCallback > 0 && now - lastCallback > 2.0 {
            logHealth(problem: "ScrollPoster: the keeper found the display link stuck (no frame for over 2 s while running), recreating it")
            recreateDisplayLink()
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
        rateVerifyTimer = CommonModesTimer.scheduled(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.verifyRateAndFixIfNeeded()
        }
    }
    // 复查: link 标称率明显低于显示器实际率 -> 重建追平 (幂等, 不受 recreateCooldown 限制)
    private func verifyRateAndFixIfNeeded() {
        rateVerifyAttemptsLeft -= 1
        guard let current = poster else { rateVerifyTimer = nil; return }
        let nominal = current.nominalHz
        // The link follows the display under the pointer (see followDisplayUnderPointer), so it
        // is compared with that display's rate; a slower display is then not "too slow".
        let followed = current.followedDisplayHz
        let maxHz = followed > 1 ? followed : maxActiveDisplayHz()
        guard nominal > 1, maxHz > 1, nominal < maxHz * rateVerifyRatio else {
            // 已追平显示器刷新率, 结束复查
            rateVerifyTimer = nil
            rateVerifyAttemptsLeft = 0
            return
        }
        AppSystemLog.note(String(format: "ScrollPoster: display link rate %.0f Hz below the display's %.0f Hz, recreating it", nominal, maxHz))
        // 保持原运行状态: 若正在滚动 (running) 则重建后重新启动
        let wasRunning = current.isRunning
        isVerifying = true
        let replaced = create()
        isVerifying = false
        // (When none could be made, the link in use stays, running if it ran.)
        if replaced, wasRunning, let refreshed = poster {
            refreshed.followDisplayUnderPointer()
            if refreshed.start() == kCVReturnSuccess {
                noteDisplayLinkStarted()
            }
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
        let now = Self.monotonicNow()
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

    /// Whether the touch ("began", "changed") is over and the rest goes out as its glide. Without
    /// trackpad-style events the phases are not posted and the touch lasts until the wheel has
    /// been still for `manualContinuationThreshold`. With them it lasts `trackpadStyleTouchTime`
    /// from its "began", however long the wheel turns: the motion is the same, only its second
    /// part reaches the app as momentum. A touch that leaves no glide (what remains is under the
    /// dead zone) lasts until its last frame has gone out: a frame posted after "ended" and
    /// before "momentum began" would carry "ended" again, with a distance. That holds for both
    /// forms of trackpad-style events: as one long touch, too, the touch ends when the wheel
    /// has been still for `manualContinuationThreshold` and either a glide follows or the
    /// last frame has gone out. Caller holds stateLock.
    func fingerLiftedLocked(now: CFTimeInterval, glideFollows: Bool, outputSettled: Bool) -> Bool {
        if config.flick {
            return now - touchBeganTime >= trackpadStyleTouchTime && (glideFollows || outputSettled)
        }
        let wheelIsStill = now - lastManualEventTime > manualContinuationThreshold
        // Without phases nothing of this reaches an app: exactly as it always was.
        guard config.simTrackpadEnabled else { return wheelIsStill }
        return wheelIsStill && (glideFollows || outputSettled)
    }

    /// 处理一帧, 返回需要以哪个阶段结束会话 (nil 表示继续)。调用方须持有 stateLock。
    func processFrameLocked(frameInterval: Double, now: CFTimeInterval) -> Phase? {
        var pendingStopPhase: Phase?
        // 插值并平滑 (按真实帧间隔)
        let filledValue = advanceMotionLocked(frameInterval: frameInterval)
        // 变换滚动结果，将滤波后的插值映射到当前姿态（考虑灵敏度、方向等因素）
        let shiftedValue = shift(with: filledValue)
        // 计算缓冲值与当前位置的剩余距离，用于判断滚动是否已收敛
        let residualY = buffer.y - current.y
        let residualX = buffer.x - current.x
        let residualMagnitude = max(residualY.magnitude, residualX.magnitude)
        // The dead zone, twice: as a distance left (the scroll has arrived) and as a speed in
        // pixels per 60 Hz frame (a frame is posted): a frame of a faster display carries less
        // distance at the same speed and is judged as the same motion. Both are the stored
        // dead zone up to Smooth's Duration; for a longer one see ScrollMotion.
        let deadZone = ScrollMotion.arrivalDeadZone(config.deadZone, transition: duration)
        let speedDeadZone = ScrollMotion.postingDeadZone(config.deadZone, transition: duration)
        let outputMagnitude = ScrollMotion.outputPerReferenceFrame(
            max(abs(shiftedValue.y), abs(shiftedValue.x)), frameInterval: frameInterval
        )
        // 检测是否已经超过手动输入的持续时间阈值，准备结束手动阶段
        if !manualInputEnded && lastManualEventTime > 0.0
            && fingerLiftedLocked(now: now, glideFollows: residualMagnitude > deadZone, outputSettled: outputMagnitude <= speedDeadZone) {
            let endPlan = phases.onManualInputEnded()
            if !(endPlan.queue.isEmpty && endPlan.target == nil) {
                perform(endPlan, emitTargetImmediately: true)
            }
            manualInputEnded = true
            if trackingEndScheduledTime == nil {
                trackingEndScheduledTime = now + trackingEndAdvance
            }
        }
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
        if outputMagnitude > speedDeadZone {
            // Whole pixels go out, the fraction waits for the next frame. A frame that comes
            // to no whole pixel yet (faster displays) posts nothing and keeps its distance.
            let pixels = pixelCarry.take(shiftedValue)
            let posts = pixels.y != 0.0 || pixels.x != 0.0
            if posts && touchWaitsForTurn
                && (filledValue.y * delta.y > 0 || filledValue.x * delta.x > 0) {
                beginTouchAfterTurnLocked(now: now)
            }
            if posts && post(pixels) {
                let moved = abs(pixels.y) + abs(pixels.x)
                sessionLog.frames += 1
                sessionLog.postedDistance += moved
                sessionLog.largestFrame = max(sessionLog.largestFrame, moved)
                sessionLog.lastFrameAt = now
                lastActivityTime = now
            }
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
            let outputSettled = outputMagnitude <= speedDeadZone
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
        applyConfigLocked(configSnapshot(for: nil))
    }

    /// The settings of a scroll: the global ones or the app's own, and whether the app the event
    /// goes to gets a flick. Main thread (Options, ScrollCore, ScrollUtils); needs no lock.
    private func configSnapshot(for event: CGEvent?) -> ConfigSnapshot {
        let simTrackpad = Self.trackpadStyleIsOn(application: ScrollCore.shared.application, global: Options.shared.scroll)
        // Asked with trackpad-style events only. It never reads the disk here: an app seen
        // for the first time counts as touch-only until its bundle was looked into, off this
        // thread (`ScrollUtils.trackpadStyleTarget`).
        let target = simTrackpad ? event.map { trackpadStyleTarget($0) } : nil
        let form = Self.trackpadStyleForm(switchOn: simTrackpad, target: target)
        return ConfigSnapshot(
            simTrackpadEnabled: form.phases,
            flick: form.flick,
            withheld: form.withheld,
            deadZone: OPTIONS_SCROLL_DEFAULT.usableDeadZone(Options.shared.scroll.deadZone)
        )
    }

    /// Caller holds stateLock.
    private func applyConfigLocked(_ snapshot: ConfigSnapshot) {
        config = snapshot
        // Both forms of trackpad-style events (it used to be the flick only: as one long
        // touch a glide whose first frame came to no whole pixel lost its "momentum began").
        phases.holdsWaitingMomentumBegan = snapshot.simTrackpadEnabled
    }

    func eventTimestamp() -> UInt64 {
#if DEBUG
        if let clock = eventClockForTests {
            return clock()
        }
#endif
        return ScrollEventClock.uptimeNanoseconds()
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
        var frame = ScrollOutgoingFrame(y: v.y, x: v.x, scrollPhase: phaseValues?.scroll, momentumPhase: phaseValues?.momentum)
        if config.flick {
            // The time of this frame, so that an app finds the glide's real speed when it bounces.
            frame.timestamp = eventTimestamp()
        }
#if DEBUG
        if let recorder = frameRecorderForTests {
            recorder(frame)
            targetRecorderForTests?(frame, dispatchContext.targetPID ?? 0)
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
        queuedFrames &+= 1
        phases.didDeliverFrame()
        return true
    }
}

// MARK: - 显示器刷新率查询 (刷新率自纠使用)
private extension ScrollPoster {
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
