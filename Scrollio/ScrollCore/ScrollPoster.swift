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
    /// Given on every frame that carries phases ("Trackpad-style scrolling"): apps take the
    /// speed of a gesture from the time between its events (`ScrollPoster.stampLocked`).
    var timestamp: UInt64? = nil
    /// A frame of "Trackpad-style scrolling": it carries phases and is written as a
    /// trackpad's event, with a time, line deltas and a scroll count of its own. (The one
    /// frame with a phase that is not: the "ended" Chrome gets at a stop with the switch off,
    /// written as it always was.)
    var isTrackpadStyle = false
    /// The frame's own line deltas (whole lines: a tenth of the pixels, the fraction carried
    /// on to the next frame). Written on a trackpad-style frame only.
    var lineY: Int64 = 0
    var lineX: Int64 = 0

    /// Whether the frame carries phases at all.
    var carriesPhases: Bool {
        return scrollPhase != nil && momentumPhase != nil
    }

    /// Whether the frame opens or closes a gesture for the app: "began", "ended", "momentum
    /// began", "momentum ended", and the two frames of the tap after a forced end ("may
    /// begin", "cancelled": `ScrollPoster.twoFingerTap`). Never a frame without phases.
    var opensOrClosesGesture: Bool {
        return scrollPhase == 1.0 || scrollPhase == 4.0 || scrollPhase == 128.0 || scrollPhase == 8.0
            || momentumPhase == 1.0 || momentumPhase == 3.0
    }

    /// Pixels in a line, as macOS counts them for a scroll event.
    static let pixelsPerLine = 10.0

    /// A whole number of lines as the integer the line delta field takes. A number no
    /// `Int64` holds (a hand-edited Step of 1e25 gives frames that large: `isUsable` only
    /// asks for a finite number) is written as the largest one of its sign: `Int64(_:)`
    /// trapped on it.
    static func wholeLines(_ lines: Double) -> Int64 {
        guard lines.isFinite else { return 0 }
        return Int64(exactly: lines.rounded(.towardZero)) ?? (lines < 0 ? Int64.min : Int64.max)
    }

    /// Without phases only the point delta is written: the line delta, the fixed-point delta,
    /// the scroll count and the timestamp stay those of the copied wheel event, as they
    /// always did. CoreGraphics drops the fraction of a point delta, so the frames of a glide
    /// come here in whole pixels (ScrollPixelCarry keeps the fraction for the next).
    ///
    /// A trackpad-style frame is a trackpad's event to the app, and what it copied was a
    /// wheel's:
    /// - the scroll count (field 100) is set to 0. AppKit multiplies the delta of a precise
    ///   event by 1 + count / 100 from a count of 3 (its "third fast flick" acceleration), and
    ///   every frame carried whatever the wheel event did;
    /// - the line delta and the fixed-point delta are the frame's own (a tenth of its
    ///   pixels). Every frame of a wheel event carried that event's whole line delta: 26
    ///   frames of one click each said "one line". The line delta is written first: writing
    ///   it rewrites the other two fields;
    /// - never a touch phase and a momentum phase together (`ScrollPhase.swift`,
    ///   `PhaseValueMapping`): Chromium asserts on such an event.
    func write(to event: CGEvent) {
        if isTrackpadStyle {
            event.setIntegerValueField(.scrollWheelEventScrollCount, value: 0)
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: lineY)
            event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: lineX)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: y / Self.pixelsPerLine)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: x / Self.pixelsPerLine)
        }
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
    static let shared: ScrollPoster = {
        let poster = ScrollPoster()
        // The app's own poster reads where a page ends through Accessibility. Never under
        // XCTest: a test may not read another app's interface.
        if !AppRuntime.isRunningXCTest {
            poster.endWatch = AccessibilityScrollEndWatch()
        }
        // The app's own poster reads the two switches under "Trackpad-style scrolling (Experimental)".
        poster.trackpadStyleInBrowsers = { Options.shared.trackpadStyleInBrowsers }
        poster.trackpadStyleInMacApps = { Options.shared.trackpadStyleInMacApps }
        return poster
    }()
    /// The shared poster uses the shared phase machine and dispatch context; tests pass their own.
    init(phases: ScrollPhase = .shared, dispatchContext: ScrollDispatchContext = .shared) {
        self.phases = phases
        self.dispatchContext = dispatchContext
#if DEBUG
        // Tests and the measuring harness: a watch that sees mid-page at once, so that a one
        // touch opens with the wheel event. (In a release build only `shared` exists.)
        endWatch = ScrollEndWatchSeenInMidPage()
#endif
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
    /// The two switches under "Trackpad-style scrolling (Experimental)": where it works. Asked only
    /// while the main switch is on for the app. The app's own poster reads the settings
    /// (`shared`); any other poster (tests, the measuring harness) counts both as on unless
    /// it is told otherwise.
    /// In browsers: the flick (Chromium, Gecko, Safari and DuckDuckGo), and in a native
    /// shell around Chromium the page's flick with its careful look. Off: these apps scroll
    /// as with the main switch off, and no look is made.
    var trackpadStyleInBrowsers: () -> Bool = { true }
    /// In Mac apps: the one touch with its end watch for every other app. Off: such an app
    /// scrolls as with the main switch off and nothing is asked of it through
    /// Accessibility; in a native shell a list with a scroll bar scrolls plain like the
    /// rest of the shell.
    var trackpadStyleInMacApps: () -> Bool = { true }
    /// Whether that kind is known already: false while the look into the app's bundle is on
    /// its way (asked only for a one touch). Until it is, the end watch does not look.
    var appKindIsKnown: (CGEvent) -> Bool = {
        ScrollUtils.shared.trackpadStyleKindIsKnown(of: $0)
    }
    /// Whether an event goes to Chrome, for the "ended" Chrome gets at a stop with the switch
    /// off (`stop`). Tests answer here: no running app is looked up.
    var isEventTargetingChrome: (CGEvent) -> Bool = {
        ScrollUtils.shared.isEventTargetingChrome($0)
    }
    /// Seconds on a clock that is never set back or forward (the wall clock was used here:
    /// set back by a time sync, it refused every new display link and kept a touch open for
    /// as long as it was set back). Both threads read the same clock.
    static func monotonicNow() -> CFTimeInterval {
        return Double(ScrollEventClock.uptimeNanoseconds()) / 1_000_000_000
    }
    /// Seconds of the event clock as its nanoseconds; nil for what is no time on it.
    static func nanoseconds(_ seconds: CFTimeInterval) -> UInt64? {
        guard seconds.isFinite, seconds > 0, seconds < 1e9 else { return nil }
        return UInt64((seconds * 1_000_000_000).rounded())
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
    //   scroll is one touch until it has run out, and no glide events at all (`config.oneTouch`):
    //   every frame is a "changed". WebKit, in a web view of any app, follows the touch's
    //   frames whole (measured in a WKWebView: 205 of 205 px); it makes a glide of its own
    //   and drops the one it is sent only when "momentum began" carries a hardware record
    //   (`ScrollHardwareRecord`).
    //   The one touch is laid over the scroll as it runs with the switch off: the phase machine
    //   runs exactly as it does then (it only times the scroll; nothing of it is posted), and
    //   what the app gets is "began" with the first wheel event, "changed" on every frame that
    //   moves the page, "ended" after the last one (`oneTouchIsOpen`). So the motion of a
    //   one-touch scroll is the switch-off scroll's, frame for frame.
    //   How the touch ends:
    //   - A scroll that runs out by itself: "ended" goes out `oneTouchRest` (0.2 s) after the
    //     touch's last frame, with a time that far after it. AppKit adds a glide of its own
    //     after "ended", sized from the speed of the touch's frames by their times, and takes
    //     that speed for stale (0) when "ended" comes 0.2 s after the last one (read from
    //     AppKit 27.2: `NSScrollViewScrollVelocityZeroingTimeout`). An "ended" right after
    //     the last frame finds the last frames' speed (about 155 pt/s for a click at Smooth:
    //     13 pt more, a soft landing of AppKit's own; much more for a scroll cut short). A
    //     wheel event during the rest goes on with the open touch. The scroll's own end
    //     can come before the rest is over: then the motion is put back to nothing, as its
    //     stop would (`restMotionLocked`), and the scroll stays up until "ended" is out.
    //   - A forced end (a click, a finger on the trackpad, the wheel going on 30 pt away or
    //     over another app, Pause, a restart of the tap, the switch): "ended" at once, and
    //     right after it a "two-finger tap" (`twoFingerTap`): the pair a trackpad sends when
    //     two fingers touch it and lift without scrolling. It is what stops an app that
    //     glides on by itself (Mac Mouse Fix and LinearMouse send it for that).
    //   (Before, the touch lasted while the wheel turned, until it had been still for
    //   `manualContinuationThreshold`, and the rest went out as momentum: 70 of a click's
    //   205 px at Smooth, 136 at Float, which such views never followed. That form is still
    //   here behind an evaluation switch, `usesOldLongTouch`.)
    // - The Chromium engine (Chrome, Dia, Arc, Electron apps) and the Gecko engine (Firefox)
    //   scroll by the momentum events too. For them the scroll is a flick (`config.flick`),
    //   as described below.
    // - Safari and the DuckDuckGo browser (WebKit) get the flick too, where the wheel event's
    //   hardware record comes off a frame, and no phases where it does not
    //   (`ScrollUtils.TrackpadStyleTarget.safari`). The apps where a wheel has to stay a
    //   wheel get no phases (`.plainScrolling`).
    // - A scroll that is mainly sideways carries no phases in any app (`isMainlySideways`).
    //
    // A real flick is a short touch (3 or 4 events, ~50 ms) and then a long glide (momentum).
    // At a page edge apps treat the two very differently: the touch drags the page past the edge
    // as a finger would (the stretch follows every delta, with resistance, until the finger lifts),
    // while a glide that reaches the edge starts the bounce at once, sized by the glide's speed,
    // and the rest of the glide is ignored. Sent as one long touch for as long as the wheel turned
    // (and 0.18 s more), a fast scroll dragged the page far past the edge and held it there, and a
    // tick that put the finger down again during the bounce made the page jump.
    //
    // The flick as an app gets it (Chromium, Gecko):
    // - "began" is the first frame that moves the page, with that frame's distance, as a
    //   trackpad's "began" carries its first pixel. It used to be a frame of its own without
    //   distance, posted with the wheel event. Gecko picks the scroller for the whole gesture
    //   from the first event and finds none for an event without distance: it then keeps the
    //   innermost scrollable box under the pointer, whatever the direction, and a page under a
    //   box that scrolls only sideways does not move (read in its source). Chromium marks the
    //   later events of a gesture as not blocking only after a "began" that has a distance.
    // - The touch lasts `trackpadStyleTouchTime` from the wheel event and until two frames
    //   that move the page have gone out in it (when the motion has that many): an app takes
    //   the speed for a bounce from two frames.
    // - "ended" goes out in the same display frame as "momentum began", right before it: it
    //   is held back until the glide's first frame is posted (`endedWaitsForGlide`). It used
    //   to go out when the touch was over, and "momentum began" waited for the first frame
    //   that came to a whole pixel: Chromium drops a glide whose "momentum began" comes more
    //   than 100 ms after "ended" (a scroll of a few pixels at a long glide time). When no
    //   frame of the glide ever comes, "ended" goes out alone when the scroll ends.
    /// The finger lifts this long after the touch began; the rest of the scroll is its glide.
    private let trackpadStyleTouchTime: CFTimeInterval = 0.045
    /// When the current touch began ("began" planned), for `fingerLiftedLocked`.
    private var touchBeganTime: CFTimeInterval = 0.0
    /// Flick: how many frames that move the page have gone out in the current touch.
    private var movingTouchFrames = 0
    /// Flick: the touch is over for the machine, and its "ended" waits for the glide's first
    /// frame (`flushHeldEndedLocked`).
    private var endedWaitsForGlide = false
    /// A tick turned back during the glide; its touch begins with the first frame that moves its way.
    private var touchWaitsForTurn = false
    /// The direction of the touch and its glide: the last wheel input that did not ask for a turn.
    private var glideDelta = (y: 0.0, x: 0.0)
    /// Where the current touch began and where the last wheel input was. nil: not known, or the
    /// touch began without trackpad-style events (the app got no "began" for it).
    private var touchPlace: ScrollInputPlace?
    private var lastInputPlace: ScrollInputPlace?
    /// One touch to the end: the app has got "began" and not yet "ended".
    private var oneTouchIsOpen = false
    // One touch: the end watch (design v3; `ScrollEndWatch.swift`).
    //
    // An app follows a touch past the page's end for as long as its frames come, and lets
    // the page go only at "ended". A wheel that kept turning into the end of a Finder list
    // held it stretched for one to two seconds (the owner, build 1674). An app bounces by
    // itself only from its own glide, which it starts at an "ended" that still has speed.
    // So at a page's end the touch has to END, at the moment the page arrives, and for that
    // Scrollio has to know where the page is: the watch reads the scroll bar under the
    // pointer, off this thread, and answers later.
    //
    // 1. A scroll that would be a one touch asks for a look (`watchForOneTouchLocked`). Until
    //    the answer "seen" is in, its frames are plain (no phases, written as with the switch
    //    off); the touch opens with the answer ("began"), and the frames after it are
    //    "changed". Should the answer come after the first frames: the same, the scroll goes
    //    on plain until it is in. (Not "stay plain for that scroll": an answer that is a
    //    frame late would then cost the whole scroll its form.)
    // 2. Not seen (no scroll area, no bar, an error, a timeout, a value that moves the wrong
    //    way, no watch at all): that scroll carries no phases. Found in mid-touch: the touch
    //    is ended by force (with its tap) and the rest is plain.
    // 3. While the touch is open the bar is read once per display frame at most, one read
    //    in flight. The page is at the end the scroll heads for, and its value was seen to
    //    move toward that end during this touch: "ended" at once, with the clock's time
    //    (right after the last moving frame: the app holds the page's real speed and makes
    //    its own bounce from it), no tap, and the rest of the motion is dropped.
    // 4. A wheel event that heads further into the end the page is at is taken in and nothing
    //    is sent (`endHold`), while a look at the pointer no older than `endHoldFreshness`
    //    still finds the same bar at that end, in the same app within 30 pt, in the same
    //    direction, and for `endHoldLongestLife` at most. Anything else (stale, a look that
    //    fails or finds another bar, the value left the end, another place, the other way,
    //    too long) ends the hold and the event scrolls as usual.
    // 5. A scroll that starts with the page already at the end it heads for: a short touch
    //    ("began", two moving frames, "ended" at once after the second), so the app makes
    //    one small bounce. Then, where the bar the look found is proven (an arrival was
    //    seen on it): the rest is dropped and held as in 4; where it is not: the rest goes out plain,
    //    and nothing is ever taken in. One bounce per fresh start: "fresh" is a wheel that
    //    paused for `endHoldFreshness`.
    /// Reads where the page under the pointer is. nil: nothing is read and nothing is ever
    /// seen. Set before the first scroll; called without the lock, never waited for.
    var endWatch: ScrollEndWatching?
    /// The look whose answers this scroll takes; older answers are thrown away.
    private var watchToken: UInt64 = 0
    /// This scroll's look was asked for (one per scroll and place).
    private var watchAsked = false
    private var watchAskedAt: CFTimeInterval = 0
    /// nil: no answer yet. false: not seen, the scroll is plain. true: seen.
    private var watchSeen: Bool?
    /// One read in flight at most (`ScrollEndWatching.read`).
    private var watchReadInFlight = false
    /// A call to the watch that is made once the lock is let go (`takeWatchCallLocked`).
    private var watchCall: WatchCall?
    private enum WatchCall {
        case look(token: UInt64, epoch: UInt64, pid: pid_t, point: CGPoint, forHold: Bool, forShell: Bool = false, readsRoles: Bool)
        case read(token: UInt64, epoch: UInt64, askedAt: CFTimeInterval)
        case content(token: UInt64, epoch: UInt64, retake: CGPoint?, pid: pid_t)
    }
    // The watch's judgement is not for the whole scroll. A wheel that goes up and down
    // without a pause makes one scroll of many seconds and many turns (the owner: 335
    // wheel events in 9.4 s), and one verdict lasted to its end: "plain from there" after
    // a single slow read, or after a turn that the lagging reads (up to 100 ms behind while
    // Finder flings) made look like "the wrong way".
    // - A turn of the wheel starts the judgement afresh (`watchEpoch`): "followed" and the
    //   first value are counted from reads asked after the turn, a read asked before it
    //   says nothing, and a scroll that had gone plain gets a new look at once.
    // - Being blind is temporary: after a lost bar, a look that saw none, or a short touch
    //   at an end that is not proven, the scroll is plain and a new look is asked every
    //   `watchRetryInterval` while it goes on; the touch opens again when the bar is seen
    //   and the page is not at the end the scroll heads for.
    // - One read that fails does not cost the bar; the second in a row does. And a touch is
    //   never open longer than `watchBlindLimit` without a fresh reading.
    // - "The wrong way" is judged against the frames that were sent, not the wheel, and
    //   only in a stretch where every frame went the same way for `sameWayMargin` before
    //   the read was asked: three such reads in a row against the frames, by
    //   `wrongWaySlack` in all. Then the scroll is plain until the wheel turns.
    /// Counts the wheel's turns in this scroll; a read carries the count it was asked under.
    private var watchEpoch: UInt64 = 0
    /// The last wheel event's direction in this scroll: toward the bottom (value 1) or the top.
    private var watchHeadsToBottom: Bool?
    /// The bar's value at the first reading since the last turn, and at the last one.
    private var watchHasFirstValue = false
    private var watchFirstValue = 0.0
    private var watchValue = 0.0
    /// When the open touch last got a reading, on the clock of the wheel events and display
    /// frames this poster has seen (`latestNow`): what the blind limit and the retry are
    /// counted on.
    private var watchLastAnswerAt: CFTimeInterval = 0
    /// The latest time a wheel event or a display frame brought.
    private var latestNow: CFTimeInterval = 0
    /// Reads that failed in a row.
    private var watchReadFailures = 0
    /// Blind: when the next look is asked. nil: none (seen, or the verdict "the wrong way").
    private var watchRetryAt: CFTimeInterval?
    /// The look in flight is such a retry: it opens the touch only away from the end.
    private var watchLookIsRetry = false
    /// "The wrong way": the direction of the frames, since when they all went that way, the
    /// value at the last read that counts, and the reads in a row that went against them.
    private var framesHeadToBottom: Bool?
    private var framesSameWaySince: CFTimeInterval = 0
    private var watchJudgedValue: Double?
    private var watchWrongWayReads = 0
    private var watchWrongWayMoved = 0.0
    static let watchRetryInterval: CFTimeInterval = 0.25
    static let watchBlindLimit: CFTimeInterval = 0.35
    static let sameWayMargin: CFTimeInterval = 0.2
    static let wrongWayReadsInARow = 3
    /// The value was seen to move toward the end the touch heads for: the bar is the
    /// scrolled view's own.
    private var watchFollowed = false
    /// Rule 5: the short touch of a scroll that started at the end, and its moving frames.
    private var oneTouchIsShort = false
    private var shortTouchFrames = 0
    /// The touch ended by itself after its rest: what still comes out over the dead zone by
    /// itself is left out, until the next wheel event.
    private var oneTouchLeavesFramesOut = false
    /// The bar on which an arrival at a page's end was seen: it is proven to follow
    /// Scrollio's frames, and only over it wheel events are ever taken in.
    /// It is the BAR that is proven, not the place: the scroll bar (as the reader numbers
    /// the elements it finds) whose value followed Scrollio's frames into an end. A place
    /// (an app, 30 pt) could hold another view tomorrow, or 20 pt further on.
    private var provenBar: UInt64?
    /// The bar this scroll's look found (`ScrollEndReading.bar`).
    private var watchBar: UInt64 = 0
    /// Rule 4: the page is at an end and the wheel still turns into it. The most careful
    /// part of the watch, because it sends nothing for a wheel event: every wheel event it
    /// takes in asks for a LOOK at the pointer (not a read of the old bar), and the hold
    /// lives only while such a look, no older than `endHoldFreshness`, finds the same bar
    /// at that end; and it has a longest life.
    private struct EndHold {
        var token: UInt64
        var place: ScrollInputPlace
        var bar: UInt64
        var towardBottom: Bool
        /// When a look last said "that bar, at that end".
        var lastAtEnd: CFTimeInterval
        var startedAt: CFTimeInterval
        var taken = 0
    }
    /// However fresh its looks: a hold ends after this long, and its bar is no longer
    /// proven (the next start there gets its short touch and then plain frames, which move
    /// whatever can move). The owner's longest free spin was 3.3 s.
    static let endHoldLongestLife: CFTimeInterval = 4.0
    /// A check that ends a hold which only went stale is on its way (main queue).
    private var holdExpiryIsScheduled = false

    // The second way to know a page's end, after the bar: THE CONTENT UNDER THE POINTER IS
    // SEEN TO FOLLOW. Only for a one touch outside a native shell, and only where a look
    // saw no bar but the element under the pointer says where it is on the screen (its
    // position and size: `ScrollEndReading.content`). In mid-page that element moves by
    // what Scrollio sends; at the page's end it stops.
    // 1. Proof first. The scroll starts plain, as it did. The element's position is read
    //    once per display frame (one read in flight). When it has moved with the frames
    //    (`contentProofLow` to `contentProofHigh` of the distance sent, over three
    //    readings and `contentProofDistance` at least), the view follows: the touch opens
    //    for this scroll, and the place is remembered (`followsMemory`, 60 s after its
    //    last use), where the next scroll's touch opens with its look.
    // 2. Arrival. While the touch is open: when the element moved less than
    //    `contentArrivalShare` of what was sent, over two readings and
    //    `contentArrivalWindow` at least and `contentArrivalDistance` sent ("lag" is not
    //    judged: a late answer still says where the element is when it comes), "ended"
    //    goes out at once with its real time, no tap, and the rest of the motion is
    //    dropped, as at an arrival seen on a bar: the app bounces by itself.
    // 3. Never held, never swallowed. The touch is never open longer than
    //    `watchBlindLimit` without a reading (then it ends by force and the scroll goes on
    //    plain). After an arrival nothing is taken in: there is no hold (that stays the
    //    bar's); the wheel events that follow go out plain.
    // 4. A start in a remembered place at the end the last scroll there reached, after a
    //    pause of the wheel (`endHoldFreshness`): the short touch, then plain.
    // 5. The element goes away (no position any more, or `contentFarOff` from the pointer):
    //    the element under the pointer is taken again; nothing is judged across the change.
    // 6. Not following (three stretches in a row), no position, a reader that fails: plain.
    private struct ContentWatch {
        /// The touch is opened on its strength.
        var follows = false
        /// The readings the judgement runs over: when, where the element was, how much had been sent.
        var samples: [(at: CFTimeInterval, y: Double, sent: Double)] = []
        var needsRetake = false
        var misses = 0
        var failedStretches = 0
        var startedAt: CFTimeInterval
    }
    private var contentWatch: ContentWatch?
    /// The up-down distance posted in this scroll, signed (one touch only).
    private var contentSent = 0.0
    private struct FollowsMemory {
        var place: ScrollInputPlace
        var usedAt: CFTimeInterval
        /// The end the last scroll there was seen to reach, if it reached one.
        var arrivedToBottom: Bool?
    }
    private var followsMemory: FollowsMemory?
    /// How long the wheel had rested at a remembered place before the wheel event that
    /// asked for this scroll's look.
    private var pauseBeforeLook: CFTimeInterval = 0
    static let contentProofDistance = 48.0
    static let contentProofLow = 0.75
    static let contentProofHigh = 1.25
    static let contentArrivalWindow: CFTimeInterval = 0.1
    static let contentArrivalDistance = 30.0
    static let contentArrivalShare = 0.5
    static let contentFarOff: CGFloat = 400
    static let followsMemoryLife: CFTimeInterval = 60

    // A native shell around Chromium (`ScrollUtils.TrackpadStyleTarget.nativeShell`: Dia,
    // Arc). Its web pages want the flick. Everything else in its windows is the shell's
    // own: an AppKit or SwiftUI view, which follows a touch and ignores a glide's events,
    // so under a flick a list there stopped in mid-scroll (the owner, Dia's sidebar). And
    // such a list need not show a scroll bar (his log: none was seen there), so without a
    // readable end it gets no touch either: it scrolls plain, the switch-off stream, which
    // is always the right distance. Only where a bar is seen it gets the one touch with
    // its end watch, as in a native app.
    // What is under the pointer, a look of the end watch says, in its form that asks no
    // element for its role (`ScrollEndClimb.carefulLook`: the view that holds a web page
    // switches on Chromium's accessibility when asked for it): the page's view is known by
    // numbers (`ScrollEndShellFacts.isThePage`).
    // - A place that is not known starts as a flick, frame for frame as in any Chromium
    //   app, and asks for one look. "The page", no answer, or an answer that cannot tell:
    //   nothing changes. "Not the page": what the app has of the flick is closed at once
    //   and the same scroll goes on as a one touch (`enterOneTouchLocked`), which is plain
    //   frames unless the look saw a bar.
    // - A place known as not the page starts as that one touch with the first wheel event.
    //   It looks for itself at each scroll, as always; an answer "the page" there makes
    //   the next wheel event a flick again.
    // - A verdict lasts while it is used: "the page" for `shellPageVerdictLife` after the
    //   last wheel event there, "not the page" for `shellOtherVerdictLife` (wrongly kept,
    //   the first costs a list that stops short, the second one look and a few plain frames
    //   on a page).
    private struct ShellVerdict {
        var place: ScrollInputPlace
        var isThePage: Bool
        var usedAt: CFTimeInterval
    }
    private var shellVerdict: ShellVerdict?
    private var shellLookSerial: UInt64 = 0
    /// When the look that is on its way was asked; nil: none is.
    private var shellLookAskedAt: CFTimeInterval?
    static let shellPageVerdictLife: CFTimeInterval = 2.0
    static let shellOtherVerdictLife: CFTimeInterval = 60.0
    /// A look that has not answered after this long no longer keeps the next from being asked.
    static let shellLookPatience: CFTimeInterval = 1.0
    private var endHold: EndHold?
    /// Main thread's own note that a hold may be up, so that a wheel event asks under the
    /// lock only then. Set where a scroll stops; a wheel event that finds none clears it.
    private var endHoldHint = false
    /// A read older than this is stale: the hold ends, and the next wheel event is a fresh
    /// start (a short touch and one bounce, rule 5).
    static let endHoldFreshness: CFTimeInterval = 0.3
    /// How close to 0 or 1 the bar's value counts as "at the end".
    /// AppKit's scroller gives exactly 0 and 1 at the ends (the owner's log: 0.0000 and
    /// 1.0000). A wider slack ended the touch early in a long document: 0.0001 of
    /// 3,000,000 px is 300 px. This is 3 px there and nothing in a short page.
    static let pageEndSlack = 0.000_001
    /// A value that has moved this far against the frames since the touch began is not the
    /// scrolled view's (or the page grew under it): not seen.
    static let wrongWaySlack = 0.05
    static func isAtEnd(_ value: Double, towardBottom: Bool) -> Bool {
        return towardBottom ? value >= 1 - pageEndSlack : value <= pageEndSlack
    }
    /// One touch: how long after the touch's last frame its "ended" goes out when the scroll
    /// has run out by itself, as the time between the two frames' timestamps (ns): AppKit's
    /// 0.2 s, and half a millisecond so that no display rate lands on the limit itself.
    static let oneTouchRest: UInt64 = 200_500_000
    /// One touch: the scroll itself is over (the machine asked for its stop) while the
    /// app's touch still rests. The stop is asked for once "ended" has gone out.
    private var oneTouchStopIsHeld = false
    /// What follows a forced "ended": scroll phase 128 ("may begin"), then 8 ("cancelled"),
    /// both without distance and without a momentum phase.
    static let twoFingerTap: [(scroll: Double, momentum: Double)] = [(scroll: 128.0, momentum: 0.0), (scroll: 8.0, momentum: 0.0)]
    /// The scroll that runs is sent as one touch: the phase machine runs as with the switch
    /// off and nothing of it is posted. Kept with the scroll, not read from the config: the
    /// form of the next wheel event can be another (the look into a Chromium-based app answers
    /// in mid-scroll; `leaveOneTouchLocked`).
    private var scrollIsOneTouch = false
    /// A tick adds to the glide only where its touch began: in the same app, with the pointer no
    /// farther than this (points) from there. Apps keep a gesture on the scroller that got its
    /// "began", so a tick over another pane has to begin a touch of its own; a hand that turns
    /// the wheel moves the pointer by a few points at most. The same for the one touch: a tick
    /// farther away ends it and begins a new one (`endOneTouchLocked(unlessAt:)`).
    private let trackpadStylePointerSlack: CGFloat = 30
    /// Whether the wheel event's hardware record is taken off a trackpad-style frame: the
    /// self-test passed (`ScrollHardwareRecord.comesOff`; its first call runs the self-test).
    /// Asked only for a wheel event whose frames carry phases (`configSnapshot`), so never
    /// with the switch off. Tests answer here. Main thread.
    var hardwareRecordComesOff: () -> Bool = { ScrollHardwareRecord.comesOff }
    /// EVALUATION SWITCH, removed before the one-touch form is released: apps that are not
    /// Chromium-based get the old long touch (`TrackpadStyleEvaluation`). Read once at launch;
    /// tests set it. Main thread.
    var usesOldLongTouch = TrackpadStyleEvaluation.usesOldLongTouch
    // Ending a session from the display link (see `displayLinkFrameLocked`)
    /// Counts wheel inputs; a stop the display link asked for is dropped when it is stale.
    private var inputSequence: UInt64 = 0
    /// Input sequence of the stop request already handed to the main thread; nil = none yet.
    private var requestedStopSequence: UInt64?
    // Trackpad-style: the time each frame carries. An app takes a gesture's speed from the
    // time between its events: AppKit for the glide it adds after "ended", WebKit, Chromium
    // and Gecko for the bounce at a page end, all as delta / (this event's time − the last
    // one's). So the times have to step as evenly as the display's frames do. They used to be
    // the wheel event's (one touch, long touch: every frame of a wheel event the same time)
    // or the moment the frame was made (flick: uneven by whatever the callback was late).
    /// The time of the display frame that runs, on an even grid: the frame before it plus the
    /// display's interval; the clock's time only for the first frame of a scroll and after a
    /// stall. Nanoseconds of the event clock; 0: no display frame yet in this scroll.
    private var frameStamp: UInt64 = 0
    /// The interval of that frame (ns).
    private var frameStampStep: UInt64 = 0
    /// The time the last frame with phases was given; 0: none yet. Kept from one scroll to
    /// the next: the times never go back.
    private var lastPhasedStamp: UInt64 = 0
    /// A display frame is being worked off (`processFrameLocked`).
    private var isInDisplayFrame = false
    /// Two frames never carry the same time, or times in the wrong order: the later one is
    /// at least this much after (ns). An app's speed is 0 for a step of 0.
    static let leastStampStep: UInt64 = 1_000_000
    /// The fraction of a line not yet written into a frame's line delta (`ScrollOutgoingFrame`).
    private var lineCarry = ScrollPixelCarry()
    /// Counts the frames handed to the post queue (`post`), so that `stop(_:)` knows whether
    /// it queued a closing frame. Guarded by stateLock.
    private var queuedFrames: UInt64 = 0
    /// Whether the scroll that runs carries trackpad phases; nil while none runs. Main thread
    /// only and read without the lock: set when a wheel event is taken (`smooth`), cleared by
    /// `stop`. A wheel event compares its own form with it. (It used to compare under
    /// stateLock: two more lock rounds for every wheel event, with the switch off as well.)
    private var runningScrollHasPhases: Bool?
    /// Whether the scroll that runs is a sideways one that for that reason carries no phases
    /// (`ConfigSnapshot.sideways`). Main thread, as `runningScrollHasPhases`.
    private var runningScrollIsSideways = false
    /// The "scroll sideways" key is held: the main thread's own copy of `shifting`, read
    /// without the lock when a wheel event's form is decided (`updateShifting`).
    private var sidewaysKeyIsDown = false
    /// When the line about closing frames that still waited was last written. Main thread.
    private var lastClosingFramesStillWaitLine: CFTimeInterval = -.infinity
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
        /// The switch is on, but this app gets no trackpad-style events (`ScrollUtils
        /// .TrackpadStyleTarget.safari` and `.plainScrolling`); `simTrackpadEnabled` is false then.
        var withheld = false
        /// Trackpad-style for an app that is not Chromium-based or Gecko-based: one touch
        /// until the scroll has run out, no glide events. (false with phases and without `flick`: the old long
        /// touch of the evaluation switch.)
        var oneTouch = false
        /// The switch is on, but this scroll is mainly sideways and carries no phases
        /// (`isMainlySideways`); `simTrackpadEnabled` is false then.
        var sideways = false
        /// The frames go out without the wheel event's hardware record
        /// (`hardwareRecordComesOff`, with trackpad-style only).
        var takesRecordOff = false
        /// One touch, in an app whose kind is not known yet (the look into its bundle is on
        /// its way): the end watch does not look. An app that turns out to be Chromium's
        /// would be asked for the role of the view that holds its web page, and Chromium
        /// switches on the page's accessibility support at that question (`ScrollEndClimb`).
        /// The frames are plain meanwhile, as before any look's answer.
        var looksWait = false
        /// The app is a native shell around Chromium: a flick asks for the place's verdict,
        /// and every look there asks no element for its role before a bar is seen.
        var isShell = false
        /// A native shell with "In Mac apps" off: a scroll bar seen there opens no touch.
        var shellStaysPlain = false
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
    /// Tests: the clock a wheel event's time is read from in `smooth(event:input:)`
    /// (`monotonicNow` otherwise), so that a run through the real path can have its wheel
    /// events and display frames on one simulated clock.
    var inputClockForTests: (() -> CFTimeInterval)?
    /// Tests: a flick's "ended" waits for its glide's first frame.
    var endedWaitsForGlideForTests: Bool {
        os_unfair_lock_lock(&stateLock)
        defer { os_unfair_lock_unlock(&stateLock) }
        return endedWaitsForGlide
    }
    /// Tests: how often a wheel event asked, under the lock, whether an open touch has to end
    /// (`endOneTouchLocked(unlessAt:)`). Never with the switch off.
    var touchChecksForTests = 0
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
    /// touch-only): whether the frames carry phases at all, as a flick or as one touch, and
    /// whether the switch is on but the app gets none.
    /// `oldLongTouch`: the evaluation switch (`usesOldLongTouch`). `oneTouch` is the form of
    /// every app that gets phases and no flick, unless that switch asks for the old one.
    /// `recordComesOff`: whether the wheel event's hardware record comes off a frame here
    /// (asked for a WebKit browser only). Safari and the other browsers WebKit draws then get
    /// the flick; where it does not come off (before macOS 27, a failed self-test) they get
    /// no phases. A glide whose "momentum began" carries a record never goes to an app known
    /// as WebKit's: WebKit would replace it by a glide of its own. (Safari with the flick
    /// and no record: seen on the owner's screen, macOS 27.2, 2026-11-12; WebKit's own log
    /// said it followed every one of Scrollio's glides.)
    static func trackpadStyleForm(switchOn: Bool, target: ScrollUtils.TrackpadStyleTarget?, oldLongTouch: Bool = false, recordComesOff: Bool = false) -> (phases: Bool, flick: Bool, withheld: Bool, oneTouch: Bool) {
        guard switchOn else {
            return (phases: false, flick: false, withheld: false, oneTouch: false)
        }
        switch target {
        case .plainScrolling:
            return (phases: false, flick: false, withheld: true, oneTouch: false)
        case .safari:
            return recordComesOff
                ? (phases: true, flick: true, withheld: false, oneTouch: false)
                : (phases: false, flick: false, withheld: true, oneTouch: false)
        case .followsGlide, .nativeShell:
            // (A native shell is asked with the place's verdict already applied,
            // `configSnapshot`: without one it is a flick.)
            return (phases: true, flick: true, withheld: false, oneTouch: false)
        case .touchOnly, nil:
            return (phases: true, flick: false, withheld: false, oneTouch: !oldLongTouch)
        }
    }

    /// Whether a wheel event scrolls mainly sideways: the thumb wheel, Shift (macOS and some
    /// drivers then send the main wheel's turns as sideways events), Scrollio's own "scroll
    /// sideways" key (`sidewaysKey`: the frames of a vertical event are turned sideways when
    /// they are posted, `shift(with:)`), a tilt.
    ///
    /// Such a scroll carries no phases, in any app: a sideways scroll with a touch phase is
    /// a swipe to the app. Chrome and Firefox take it for a Magic Mouse's and go back or
    /// forward a page when the page cannot scroll sideways (Chrome from 160 at 200 pt of
    /// touch; Firefox when "began" is sideways), iTerm2 switches tabs, and AppKit asks the
    /// responders above a scroll view whether one wants the gesture as a swipe. A frame
    /// without phases cannot start any of that and scrolls as far. What it costs: no bounce
    /// at the sideways end of a list.
    ///
    /// `running`: whether the scroll that runs is a sideways one (nil: none runs). An event
    /// with both deltas keeps the running scroll's kind unless the other axis leads two to
    /// one. A device whose events carry both (a trackball, a wheel that tilts while it
    /// turns) wobbles about the diagonal, and decided anew at every event each flip ended
    /// the scroll with its remaining distance (measured: 316 of 2,410 px arrived). An event
    /// with one delta, which is every event of an ordinary wheel, is judged the same
    /// whatever runs.
    static func isMainlySideways(y: Double, x: Double, sidewaysKey: Bool, running: Bool? = nil) -> Bool {
        if sidewaysKey && y != 0.0 && x == 0.0 {
            return true
        }
        switch running {
        case .some(true): return abs(x) * 2 > abs(y)
        case .some(false): return abs(x) > abs(y) * 2
        case .none: return abs(x) > abs(y)
        }
    }

    /// Whether "Trackpad-style scrolling" is on anywhere: in the Scrolling pane, or in the
    /// own settings of some app in the Apps pane. At launch this decides whether the
    /// hardware record's self-test runs then (`ScrollHardwareRecord`): for a user who has it
    /// off everywhere, nothing of it runs.
    static func trackpadStyleIsOnSomewhere(global: OPTIONS_SCROLL_DEFAULT, applications: [Application]) -> Bool {
        return global.smoothSimTrackpad || applications.contains { !$0.inherit && $0.scroll.smoothSimTrackpad }
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
    ///   mid-scroll; or the wheel turned from up-down to sideways or back, and a sideways
    ///   scroll carries no phases): that scroll is ended first, in the form it was sent in
    ///   (`endScroll(unlessPhasesStay:)`).
    /// - it comes far from where the one touch that is open began (another pane of the same
    ///   app): that touch is ended first, at its own place (`endOneTouchLocked(unlessAt:)`),
    ///   in one stretch under the lock with the "began" that follows.
    /// - Returns: whether the event was taken. false: the caller lets it through.
    func smooth(event: CGEvent, input: ScrollPosterInput) -> Bool {
        guard input.isUsable else { return false }
        let target = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
        if endHoldHint, takesInAtPageEnd(event: event, input: input, target: target) {
            // One touch, the page at its end and the wheel still turning into it: nothing is
            // sent (rule 4 of the end watch). Never with the switch off: no hold is up then.
            return true
        }
        endScroll(unlessFor: target)
        // The form of this event's scroll is read once the event is known to be taken, as it
        // always was. Only while a scroll runs it is read here, before: that scroll has to be
        // ended first when the two differ in whether they carry phases, and that has to
        // happen before the display link is started and the event is stored.
        var formReadBefore: ConfigSnapshot?
        var bothCarryPhases = false
        if let runsWithPhases = runningScrollHasPhases {
            let form = configSnapshot(for: event, input: input)
            formReadBefore = form
            if form.simTrackpadEnabled != runsWithPhases {
                endScroll(unlessPhasesStay: form.simTrackpadEnabled,
                          reason: form.sideways != runningScrollIsSideways ? .axisChanged : .settingChanged)
            } else {
                bothCarryPhases = runsWithPhases
            }
        }
        guard tryStart() else { return false }
        let snapshot: ConfigSnapshot
        if bothCarryPhases, let form = formReadBefore {
            // An open one touch may have to end at its own place before this event is stored
            // (its "ended" is a copy of the event stored until then), and nothing may fall between
            // that "ended" and the "began" this event brings: one stretch under the lock, the
            // storing of the event included. (They were two stretches: a display frame that
            // ran between them found no touch to belong to, and its distance was lost.)
            os_unfair_lock_lock(&stateLock)
            if endHold != nil, holdTakesLocked(form: form, place: ScrollInputPlace(pid: target, pointer: event.location), input: input) {
                // (The same while the scroll that arrived there is still up.)
                let call = takeWatchCallLocked()
                os_unfair_lock_unlock(&stateLock)
                make(call)
                return true
            }
            endOneTouchLocked(unlessAt: { ScrollInputPlace(pid: target, pointer: event.location) })
            if config.flick, !staysAtTouchPlaceLocked(ScrollInputPlace(pid: target, pointer: event.location)) {
                // A flick, and the wheel goes on far from where its touch began: what the app
                // has of that gesture is closed now, as copies of the event stored until
                // here, at the gesture's own place (`closeFlickGestureLocked`).
                closeFlickGestureLocked()
            }
            guard dispatchContext.capture(event: event) else {
                os_unfair_lock_unlock(&stateLock)
                return false
            }
            snapshot = form
        } else {
            // Without phases, and for the first event of a scroll: as it always was.
            guard dispatchContext.capture(event: event) else { return false }
            // 捕获本次手势的配置快照 (主线程读 Options/ScrollCore, CVDisplayLink 线程只读)
            snapshot = formReadBefore ?? configSnapshot(for: event, input: input)
            os_unfair_lock_lock(&stateLock)
        }
        applyConfigLocked(snapshot)
        let place = (config.flick || config.oneTouch) ? ScrollInputPlace(pid: target, pointer: event.location) : nil
        handleInputLocked(input, at: inputClock(), place: place)
        runningScrollHasPhases = snapshot.simTrackpadEnabled
        runningScrollIsSideways = snapshot.sideways
        if config.isShell && config.flick, let place = place {
            askForShellLookLocked(at: place)
        }
        // (One touch, and a flick in a native shell: the look, asked for once the lock is let go.)
        let call = takeWatchCallLocked()
        os_unfair_lock_unlock(&stateLock)
        make(call)
        return true
    }

    // MARK: A native shell around Chromium: the verdict for a place

    /// Whether the last look said "the page" about this place, if that still counts; nil:
    /// nothing does. Using it keeps it. Caller holds stateLock.
    private func shellVerdictLocked(at place: ScrollInputPlace, now: CFTimeInterval) -> Bool? {
        guard var verdict = shellVerdict else { return nil }
        let life = verdict.isThePage ? Self.shellPageVerdictLife : Self.shellOtherVerdictLife
        guard verdict.place.pid == place.pid,
              hypot(place.pointer.x - verdict.place.pointer.x, place.pointer.y - verdict.place.pointer.y) <= trackpadStylePointerSlack,
              now - verdict.usedAt <= life else {
            return nil
        }
        verdict.usedAt = max(verdict.usedAt, now)
        shellVerdict = verdict
        return verdict.isThePage
    }

    /// What a look that asks no roles says about its place: false where a bar was seen or
    /// the numbers say "not the page's view", true for the page's view, nil where it
    /// cannot be told (no answer, no facts).
    private static func isThePage(_ reading: ScrollEndReading) -> Bool? {
        if reading.value.flatMap(AccessibilityScrollEndWatch.fromZeroToOne) != nil { return false }
        return reading.shell?.isThePage
    }

    /// A flick in a native shell, at a place without a verdict: one look, in the form that
    /// asks no roles. One on its way at most. Caller holds stateLock; main thread.
    private func askForShellLookLocked(at place: ScrollInputPlace) {
        let now = inputClock()
        guard endWatch != nil, watchCall == nil, place.pid != getpid(), shellVerdictLocked(at: place, now: now) == nil else { return }
        if let askedAt = shellLookAskedAt, now - askedAt < Self.shellLookPatience { return }
        shellLookAskedAt = now
        shellLookSerial &+= 1
        sessionLog.endWatch.looks += 1
        sessionLog.endWatch.otherwise = "the flick goes on"
        watchCall = .look(token: shellLookSerial, epoch: 0, pid: place.pid, point: place.pointer, forHold: false, forShell: true, readsRoles: false)
    }

    /// The answer to a flick's look: the verdict for its place, and, where it is "not the
    /// page", the end of the flick in the scroll that runs. On the watch's thread, or
    /// inside the call for a stand-in; never while the lock is held.
    private func shellLookAnswered(_ reading: ScrollEndReading, serial: UInt64, place: ScrollInputPlace) {
        os_unfair_lock_lock(&stateLock)
        defer { os_unfair_lock_unlock(&stateLock) }
        guard serial == shellLookSerial else { return }
        let runsHere = !sessionLog.isEmpty && config.isShell && config.flick && !scrollIsOneTouch
        guard let isThePage = Self.isThePage(reading) else {
            // It cannot be told (the app did not answer in time, or said too little): the
            // flick goes on, as on a page, and the place is asked again after
            // `shellLookPatience`, not with every wheel event.
            if runsHere {
                sessionLog.endWatch.note(reading, isLook: true)
                sessionLog.endWatch.add("cannot tell what is under the pointer")
            }
            return
        }
        shellLookAskedAt = nil
        shellVerdict = ShellVerdict(place: place, isThePage: isThePage, usedAt: watchClockLocked())
        guard runsHere else { return }
        if isThePage {
            sessionLog.endWatch.note(reading, isLook: true)
            sessionLog.endWatch.add("the page")
            return
        }
        // Not the page, and the wheel is still where the look was made: the flick ends now
        // and the scroll goes on as a one touch, with this answer as that touch's look.
        guard let last = lastInputPlace, last.pid == place.pid,
              hypot(last.pointer.x - place.pointer.x, last.pointer.y - place.pointer.y) <= trackpadStylePointerSlack else {
            sessionLog.endWatch.note(reading, isLook: true)
            return
        }
        var form = config
        form.flick = false
        form.oneTouch = true
        applyConfigLocked(form)
        enterOneTouchLocked()
        sessionLog.oneTouch = true
        sessionLog.endWatch.otherwise = "plain"
        sessionLog.endWatch.add("not the page: the flick is closed")
        touchPlace = place
        prepareForALookLocked(now: latestNow, isRetry: false)
        judgeLocked(reading, token: watchToken, epoch: watchEpoch, askedAt: 0, isLook: true, forHold: false)
    }

    /// A one touch in a native shell looked for itself: its answer is the place's verdict
    /// too. Caller holds stateLock.
    private func noteShellVerdictLocked(_ reading: ScrollEndReading) {
        guard config.isShell, let place = touchPlace, let isThePage = Self.isThePage(reading) else { return }
        shellVerdict = ShellVerdict(place: place, isThePage: isThePage, usedAt: watchClockLocked())
        if isThePage {
            sessionLog.endWatch.add("the page after all: a flick from the next wheel event")
        }
    }

    /// The clock of a wheel event's time. Main thread.
    private func inputClock() -> CFTimeInterval {
#if DEBUG
        return inputClockForTests?() ?? Self.monotonicNow()
#else
        return Self.monotonicNow()
#endif
    }

    // MARK: One touch: the end watch

    /// Rule 4, with no scroll up: whether this wheel event is taken in at the page's end.
    /// Asked only while `endHoldHint` says a hold may be up. Main thread.
    private func takesInAtPageEnd(event: CGEvent, input: ScrollPosterInput, target: pid_t) -> Bool {
        let form = configSnapshot(for: event, input: input)
        os_unfair_lock_lock(&stateLock)
        let taken = holdTakesLocked(form: form, place: ScrollInputPlace(pid: target, pointer: event.location), input: input)
        if endHold == nil {
            endHoldHint = false
        }
        let call = takeWatchCallLocked()
        os_unfair_lock_unlock(&stateLock)
        make(call)
        return taken
    }

    /// Rule 4: a wheel event that heads further into the end the page is at is taken in,
    /// while a fresh look says its bar is still there, at that end. Anything else ends the
    /// hold. Caller holds stateLock; main thread.
    private func holdTakesLocked(form: ConfigSnapshot, place: ScrollInputPlace, input: ScrollPosterInput) -> Bool {
        guard var hold = endHold else { return false }
        let isFresh = inputClock() - hold.lastAtEnd <= Self.endHoldFreshness
        let isThere = form.oneTouch && place.pid == hold.place.pid
            && hypot(place.pointer.x - hold.place.pointer.x, place.pointer.y - hold.place.pointer.y) <= trackpadStylePointerSlack
        let headsIn = input.y != 0.0 && (input.y < 0) == hold.towardBottom
        let isYoung = inputClock() - hold.startedAt <= Self.endHoldLongestLife
        guard isFresh && isThere && headsIn && isYoung else {
            if !isYoung {
                provenBar = nil
            }
            endHoldEndsLocked()
            return false
        }
        hold.taken += 1
        endHold = hold
        if !watchReadInFlight && watchCall == nil {
            // A look at where the pointer is now: is it still that bar, still at that end?
            watchReadInFlight = true
            watchCall = .look(token: hold.token, epoch: watchEpoch, pid: place.pid, point: place.pointer, forHold: true, readsRoles: !form.isShell)
        }
        scheduleHoldExpiryLocked()
        return true
    }

    /// The hold is over; the log says how many wheel events it took in. Caller holds stateLock.
    private func endHoldEndsLocked() {
        guard let hold = endHold else { return }
        endHold = nil
        if hold.taken > 0 {
            ScrollSystemLog.notePageEnd(taken: hold.taken)
        }
    }

    /// A hold that only goes stale (the wheel stopped) is ended by the next wheel event, and
    /// only then did the log get its line. A check on the main queue ends it a moment after
    /// it has gone stale, so the line is there when the wheel has stopped. Caller holds stateLock.
    private func scheduleHoldExpiryLocked() {
#if DEBUG
        // (A test's clock is not the main queue's: a test calls `endHoldIfStale` itself.)
        if inputClockForTests != nil || eventClockForTests != nil { return }
#endif
        guard !holdExpiryIsScheduled else { return }
        holdExpiryIsScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.endHoldFreshness + 0.05) { [weak self] in
            self?.endHoldIfStale()
        }
    }

    /// Main thread.
    func endHoldIfStale() {
        os_unfair_lock_lock(&stateLock)
        holdExpiryIsScheduled = false
        if let hold = endHold {
            if inputClock() - hold.lastAtEnd > Self.endHoldFreshness {
                endHoldEndsLocked()
                endHoldHint = false
            } else {
                scheduleHoldExpiryLocked()
            }
        }
        os_unfair_lock_unlock(&stateLock)
    }

    /// The call to the watch that waits, to be made once the lock is let go. Caller holds stateLock.
    private func takeWatchCallLocked() -> WatchCall? {
        guard let call = watchCall else { return nil }
        watchCall = nil
        return call
    }

    /// Asks the watch. Never under the lock (a stand-in may answer inside the call), and
    /// never waited for: the real reader hands the work to a queue of its own.
    private func make(_ call: WatchCall?) {
        guard let call = call, let watch = endWatch else { return }
        switch call {
        case .look(let token, let epoch, let pid, let point, let forHold, let forShell, let readsRoles):
            watch.look(pid: pid, at: point, readsRoles: readsRoles) { [weak self] reading in
                if forShell {
                    self?.shellLookAnswered(reading, serial: token, place: ScrollInputPlace(pid: pid, pointer: point))
                } else {
                    self?.endWatchAnswered(reading, token: token, epoch: epoch, askedAt: 0, isLook: true, forHold: forHold)
                }
            }
        case .read(let token, let epoch, let askedAt):
            watch.read { [weak self] in self?.endWatchAnswered($0, token: token, epoch: epoch, askedAt: askedAt, isLook: false, forHold: false) }
        case .content(let token, let epoch, let retake, let pid):
            watch.readContent(retakingAt: retake, pid: pid) { [weak self] in
                self?.endWatchAnswered($0, token: token, epoch: epoch, askedAt: 0, isLook: false, forHold: false)
            }
        }
    }

    /// One touch: this wheel event's scroll needs its look, unless the touch is open (the
    /// wheel goes on with it) or the look for this scroll was asked for already. Until the
    /// answer the frames are plain. A wheel event that turns the scroll around starts the
    /// watch's judgement afresh. `towardBottom`: the event's direction (nil: none up-down).
    /// Caller holds stateLock.
    private func watchForOneTouchLocked(at place: ScrollInputPlace?, now: CFTimeInterval, towardBottom: Bool?) {
        // (A place where the content was seen to follow: how long the wheel had rested there.)
        var pause: CFTimeInterval = 0
        if var memory = followsMemory, let place = place, memory.place.pid == place.pid,
           hypot(place.pointer.x - memory.place.pointer.x, place.pointer.y - memory.place.pointer.y) <= trackpadStylePointerSlack {
            pause = now - memory.usedAt
            if pause > Self.followsMemoryLife {
                followsMemory = nil
            } else {
                memory.usedAt = now
                followsMemory = memory
            }
        }
        if let heading = towardBottom {
            if let last = watchHeadsToBottom, last != heading {
                // The wheel turned. What the watch judged, it judged for the other way.
                watchEpoch &+= 1
                watchFollowed = false
                watchHasFirstValue = false
                watchJudgedValue = nil
                watchWrongWayReads = 0
                watchWrongWayMoved = 0
                // (A short touch at an end heads away from that end now: an ordinary touch.)
                oneTouchIsShort = false
                contentWatch?.samples.removeAll()
                sessionLog.endWatch.turns += 1
                if watchSeen == false {
                    // Plain (blind, or "the wrong way"): a new look at once.
                    watchAsked = false
                }
            }
            watchHeadsToBottom = heading
        }
        guard !oneTouchIsOpen else { return }
        oneTouchLeavesFramesOut = false
        if watchAsked {
            // Asked already. Not seen stays not seen until the retry or a turn, unless the
            // wheel goes on somewhere else; a touch that ended by itself gets a look of its own.
            let moved: Bool
            if let last = touchPlace, let place = place {
                moved = last.pid != place.pid || hypot(place.pointer.x - last.pointer.x, place.pointer.y - last.pointer.y) > trackpadStylePointerSlack
            } else {
                moved = false
            }
            // (A touch the content watch had opened and that ended by its rest opens again
            // with a look, as one opened on a bar does.)
            let contentTouchRested = contentWatch?.follows == true
            if watchSeen == nil || (watchSeen == false && !moved && !contentTouchRested) { return }
        }
        if config.looksWait {
            // Asked at the next wheel event, when the app's kind is known (and the app is
            // still one that gets the one touch).
            watchAsked = false
            return
        }
        touchPlace = place
        askForALookLocked(now: now, isRetry: false)
        pauseBeforeLook = pause
    }

    /// Asks for a look at the scroll's place. Caller holds stateLock.
    private func askForALookLocked(now: CFTimeInterval, isRetry: Bool) {
        prepareForALookLocked(now: now, isRetry: isRetry)
        sessionLog.endWatch.looks += 1
        if isRetry {
            sessionLog.endWatch.retries += 1
        }
        guard endWatch != nil else {
            watchSeen = false
            sessionLog.endWatch.note(.notSeen("no watch"), isLook: true)
            return
        }
        guard touchPlace?.pid != getpid() else {
            // Never a look into Scrollio's own windows (`AccessibilityScrollEndWatch`): they
            // scroll as with the switch off.
            watchSeen = false
            sessionLog.endWatch.note(.notSeen(AccessibilityScrollEndWatch.ownWindow), isLook: true)
            return
        }
        watchCall = .look(token: watchToken, epoch: watchEpoch, pid: touchPlace?.pid ?? 0, point: touchPlace?.pointer ?? .zero, forHold: false, readsRoles: !config.isShell)
    }

    // MARK: One touch: the content under the pointer is seen to follow

    /// A look saw no bar, but the element under the pointer says where it is: the scroll
    /// goes on plain while that element is read, unless the place is remembered. Caller
    /// holds stateLock.
    private func startContentWatchLocked(frame: CGRect, now: CFTimeInterval) {
        watchSeen = false
        watchRetryAt = nil
        if sessionLog.endWatch.content == nil {
            sessionLog.endWatch.content = ScrollEndWatchLog.Content(width: Double(frame.width), height: Double(frame.height))
        }
        var watch = ContentWatch(startedAt: now)
        watch.samples = [(now, Double(frame.minY), contentSent)]
        let headsToBottom = watchHeadsToBottom ?? (delta.y < 0)
        if let memory = followsMemory, let place = touchPlace, memory.place.pid == place.pid,
           hypot(place.pointer.x - memory.place.pointer.x, place.pointer.y - memory.place.pointer.y) <= trackpadStylePointerSlack {
            if memory.arrivedToBottom != headsToBottom {
                // Seen to follow here not long ago: the touch opens with the look.
                watch.follows = true
                contentWatch = watch
                watchLastAnswerAt = now
                sessionLog.endWatch.content?.decided.append("followed here before: the touch opened")
                beginOneTouchLocked(at: touchPlace)
                return
            }
            if pauseBeforeLook >= Self.endHoldFreshness {
                // At the end the last scroll here reached, after a pause: the short touch
                // (one small bounce), then plain.
                pauseBeforeLook = 0
                contentWatch = nil
                oneTouchIsShort = true
                shortTouchFrames = 0
                sessionLog.endWatch.content?.decided.append("started at the end it had reached: a short touch")
                beginOneTouchLocked(at: touchPlace)
                return
            }
            // (The wheel has not paused since that arrival: plain, and the proof anew.)
        }
        contentWatch = watch
    }

    /// The answer to a reading of the content element. Caller holds stateLock.
    private func judgeContentLocked(_ reading: ScrollEndReading, epoch: UInt64) {
        guard var watch = contentWatch else { return }
        let now = latestNow
        sessionLog.endWatch.answers += 1
        sessionLog.endWatch.slowest = max(sessionLog.endWatch.slowest, reading.milliseconds)
        sessionLog.endWatch.content?.reads += 1
        guard let frame = reading.content else {
            // The element is gone: the one under the pointer is taken next. Twice in a
            // row there is none: plain.
            watch.misses += 1
            watch.samples.removeAll()
            watch.needsRetake = true
            contentWatch = watch
            if watch.misses >= 2 {
                sessionLog.endWatch.content?.decided.append("lost the element: plain")
                contentWatch = nil
                goPlainLocked(retry: true, now: now)
            }
            return
        }
        watch.misses = 0
        watchLastAnswerAt = now
        if reading.contentIsNew {
            // Another element: nothing is judged across the change.
            watch.samples.removeAll()
            watch.needsRetake = false
            sessionLog.endWatch.content?.retakes += 1
        }
        // (A reading asked before the wheel's last turn says nothing about this way.)
        guard epoch == watchEpoch else {
            contentWatch = watch
            return
        }
        watch.samples.append((now, Double(frame.minY), contentSent))
        if watch.samples.count > 24 { watch.samples.removeFirst() }
        if let pointer = touchPlace?.pointer, !frame.insetBy(dx: -Self.contentFarOff, dy: -Self.contentFarOff).contains(pointer) {
            watch.needsRetake = true
        }
        guard let first = watch.samples.first, let last = watch.samples.last else {
            contentWatch = watch
            return
        }
        if !watch.follows {
            // The proof: three readings, enough sent between the first and the last, and
            // the element moved by about as much, the same way.
            let sent = last.sent - first.sent
            let moved = last.y - first.y
            if watch.samples.count >= 3, abs(sent) >= Self.contentProofDistance {
                let share = moved / sent
                if share >= Self.contentProofLow && share <= Self.contentProofHigh {
                    watch.follows = true
                    watch.samples = [last]
                    contentWatch = watch
                    sessionLog.endWatch.content?.moved = abs(moved)
                    sessionLog.endWatch.content?.sent = abs(sent)
                    sessionLog.endWatch.content?.decided.append("followed after \(Int(((now - watch.startedAt) * 1000).rounded())) ms: the touch opened")
                    if let place = touchPlace {
                        followsMemory = FollowsMemory(place: place, usedAt: now, arrivedToBottom: nil)
                    }
                    beginOneTouchLocked(at: touchPlace)
                    return
                }
                // Not with the frames over this stretch: the next one is judged afresh.
                watch.failedStretches += 1
                watch.samples = [last]
                if watch.failedStretches >= 3 {
                    if sessionLog.endWatch.content?.moved == nil {
                        sessionLog.endWatch.content?.moved = abs(moved)
                        sessionLog.endWatch.content?.sent = abs(sent)
                    }
                    sessionLog.endWatch.content?.decided.append("never followed: plain")
                    contentWatch = nil
                    return
                }
            }
        } else if oneTouchIsOpen {
            // The arrival: over the last readings (two steps and `contentArrivalWindow`
            // at least) the element moved clearly less than was sent.
            let count = watch.samples.count
            if count >= 3, let from = watch.samples[0..<(count - 2)].last(where: { last.at - $0.at >= Self.contentArrivalWindow }) {
                let sent = last.sent - from.sent
                let moved = last.y - from.y
                if abs(sent) >= Self.contentArrivalDistance, moved / sent < Self.contentArrivalShare {
                    sessionLog.endWatch.content?.decided.append(String(format: "arrived (moved %.0f of %.0f sent): ended at once", moved * (sent < 0 ? -1 : 1), abs(sent)))
                    if let place = touchPlace {
                        followsMemory = FollowsMemory(place: place, usedAt: now, arrivedToBottom: sent < 0)
                    }
                    contentWatch = nil
                    // As at an arrival seen on a bar, without its hold: "ended" at once with
                    // the clock's time, no tap, the rest dropped. Nothing is taken in after it.
                    endOneTouchLocked(forced: false)
                    resetMotionLocked()
                    oneTouchStopIsHeld = true
                    return
                }
            }
        }
        contentWatch = watch
    }

    /// The watch's state as a look that was just asked leaves it. Caller holds stateLock.
    private func prepareForALookLocked(now: CFTimeInterval, isRetry: Bool) {
        // (A watch of the content belongs to the look before.)
        contentWatch = nil
        pauseBeforeLook = 0
        watchToken &+= 1
        watchAsked = true
        watchAskedAt = now
        watchSeen = nil
        watchFollowed = false
        watchHasFirstValue = false
        watchJudgedValue = nil
        watchWrongWayReads = 0
        watchWrongWayMoved = 0
        watchReadFailures = 0
        watchRetryAt = nil
        watchLookIsRetry = isRetry
        watchBar = 0
        oneTouchIsShort = false
    }

    /// The scroll goes on plain: the bar is not seen. An open touch is ended by force.
    /// `retry`: blind for now, a new look is asked in `watchRetryInterval`; false: the
    /// verdict stands until the wheel turns. Caller holds stateLock.
    private func goPlainLocked(retry: Bool, now: CFTimeInterval) {
        watchSeen = false
        watchRetryAt = retry ? now + Self.watchRetryInterval : nil
        oneTouchIsShort = false
        endOneTouchLocked(forced: true)
    }

    /// The watch answered: on its own thread, or inside the call for a stand-in; never
    /// while this lock is held. A late answer (another look has been asked for, the scroll
    /// is over) is thrown away. `epoch`: the count of the wheel's turns the request was
    /// made under; `askedAt`: when a read was asked.
    private func endWatchAnswered(_ reading: ScrollEndReading, token: UInt64, epoch: UInt64, askedAt: CFTimeInterval, isLook: Bool, forHold: Bool) {
        os_unfair_lock_lock(&stateLock)
        judgeLocked(reading, token: token, epoch: epoch, askedAt: askedAt, isLook: isLook, forHold: forHold)
        // An answer that took longer than a display frame (an app that is busy scrolling:
        // Finder took 60 to 100 ms) is followed by the next read at once, not at the next
        // display frame: with answers that slow every read counts. An answer that came
        // faster waits for the frame (one read per frame at most).
        if oneTouchIsOpen && watchSeen == true && !watchReadInFlight && watchCall == nil
            && (isLook ? watchClockLocked() - watchAskedAt : latestNow - askedAt) >= ScrollMotion.referenceFrameInterval {
            watchReadInFlight = true
            watchCall = .read(token: watchToken, epoch: watchEpoch, askedAt: latestNow)
        }
        let call = takeWatchCallLocked()
        os_unfair_lock_unlock(&stateLock)
        make(call)
    }

    /// What an answer of the watch means for the scroll. Caller holds stateLock.
    private func judgeLocked(_ answer: ScrollEndReading, token: UInt64, epoch: UInt64, askedAt: CFTimeInterval, isLook: Bool, forHold: Bool) {
        // A second fence behind the reader's: a value that is no number from 0 to 1 is no
        // reading of where the page is.
        var reading = answer
        if let value = answer.value {
            if let inRange = AccessibilityScrollEndWatch.fromZeroToOne(value) {
                reading.value = inRange
            } else {
                reading = .notSeen(AccessibilityScrollEndWatch.notFromZeroToOne, roles: answer.roles, milliseconds: answer.milliseconds)
                reading.shell = answer.shell
            }
        }
        if !isLook || forHold {
            watchReadInFlight = false
        }
        if !isLook, !forHold, contentWatch != nil {
            // The content watch's reading: where the element under the pointer is.
            guard token == watchToken, scrollIsOneTouch, !sessionLog.isEmpty else { return }
            judgeContentLocked(reading, epoch: epoch)
            return
        }
        // Rule 4: the hold lives by looks that still find its bar at that end.
        if forHold {
            guard var hold = endHold, hold.token == token else { return }
            if let value = reading.value, reading.bar == hold.bar, Self.isAtEnd(value, towardBottom: hold.towardBottom) {
                hold.lastAtEnd = watchClockLocked()
                endHold = hold
            } else {
                if reading.value == nil {
                    // The bar is gone: it is not proven any more. A fresh start there gets
                    // its short touch and plain frames, and nothing is taken in.
                    provenBar = nil
                }
                endHoldEndsLocked()
            }
            return
        }
        guard token == watchToken, scrollIsOneTouch, !sessionLog.isEmpty else { return }
        sessionLog.endWatch.note(reading, isLook: isLook)
        let now = latestNow
        guard let value = reading.value else {
            if isLook {
                // No bar seen: plain, and another look in a while.
                guard watchSeen == nil else { return }
                noteShellVerdictLocked(reading)
                provenBar = nil
                if !config.isShell, let frame = reading.content {
                    // No bar, but the element under the pointer says where it is.
                    startContentWatchLocked(frame: frame, now: now)
                    return
                }
                // (In a native shell "no bar" is what most of its own views say: plain to
                // the scroll's end or the wheel's next turn, without asking again and again.)
                goPlainLocked(retry: !config.isShell, now: now)
            } else if oneTouchIsOpen {
                // One read that fails is asked again with the next display frame; the
                // second in a row loses the bar.
                watchReadFailures += 1
                if watchReadFailures >= 2 {
                    sessionLog.endWatch.lost += 1
                    sessionLog.endWatch.add("lost the bar: ended the touch, plain until it is seen again")
                    provenBar = nil
                    goPlainLocked(retry: true, now: now)
                }
            }
            return
        }
        watchReadFailures = 0
        let towardBottom = watchHeadsToBottom ?? (delta.y < 0)
        if isLook {
            guard watchSeen == nil else { return }
            noteShellVerdictLocked(reading)
            if config.shellStaysPlain {
                // A bar of the shell's own, but "In Mac apps" is off: plain like the rest.
                sessionLog.endWatch.add("a scroll bar, and \"In Mac apps\" is off")
                goPlainLocked(retry: false, now: now)
                return
            }
            let isAtItsEnd = Self.isAtEnd(value, towardBottom: towardBottom)
            if watchLookIsRetry && isAtItsEnd {
                // Seen again, but the page is at the end the scroll heads for: plain goes on.
                watchSeen = false
                watchRetryAt = now + Self.watchRetryInterval
                return
            }
            watchSeen = true
            watchBar = reading.bar
            watchLastAnswerAt = now
            watchFollowed = false
            // (A look asked before the wheel's last turn opens the touch; the first value
            // for "followed" is then the first read's.)
            watchHasFirstValue = epoch == watchEpoch
            watchFirstValue = value
            watchValue = value
            let waited = Int((max(0, watchClockLocked() - watchAskedAt) * 1000).rounded())
            if isAtItsEnd {
                oneTouchIsShort = true
                shortTouchFrames = 0
                sessionLog.endWatch.add("started at the end: a short touch after \(waited) ms")
            } else {
                sessionLog.endWatch.add(watchLookIsRetry ? "seen again: opened the touch" : "opened the touch after \(waited) ms")
            }
            beginOneTouchLocked(at: touchPlace)
            return
        }
        guard oneTouchIsOpen, watchSeen == true else { return }
        watchLastAnswerAt = now
        // "The wrong way": against the frames, in a stretch where they all went one way.
        if let framesToBottom = framesHeadToBottom, askedAt - framesSameWaySince >= Self.sameWayMargin {
            if let before = watchJudgedValue {
                let moved = (value - before) * (framesToBottom ? 1.0 : -1.0)
                if moved < -1e-7 {
                    watchWrongWayReads += 1
                    watchWrongWayMoved -= moved
                } else if moved > 1e-7 {
                    watchWrongWayReads = 0
                    watchWrongWayMoved = 0
                }
            }
            watchJudgedValue = value
            if watchWrongWayReads >= Self.wrongWayReadsInARow && watchWrongWayMoved >= Self.wrongWaySlack {
                sessionLog.endWatch.add("the value went against the frames over \(watchWrongWayReads) reads: ended the touch, plain until the wheel turns")
                provenBar = nil
                goPlainLocked(retry: false, now: now)
                return
            }
        } else {
            watchJudgedValue = nil
        }
        // A read asked before the wheel's last turn says nothing about this way.
        guard epoch == watchEpoch else { return }
        guard watchHasFirstValue else {
            watchHasFirstValue = true
            watchFirstValue = value
            watchValue = value
            return
        }
        if (value - watchValue) * (towardBottom ? 1.0 : -1.0) > 1e-7 {
            watchFollowed = true
        }
        watchValue = value
        if !oneTouchIsShort && watchFollowed && Self.isAtEnd(value, towardBottom: towardBottom) {
            arriveAtPageEndLocked()
        }
    }

    /// The clock the hold's freshness is counted on: the wheel events' own. Caller holds stateLock.
    private func watchClockLocked() -> CFTimeInterval {
#if DEBUG
        return inputClockForTests?() ?? eventClockForTests.map { Double($0()) / 1_000_000_000 } ?? Self.monotonicNow()
#else
        return Self.monotonicNow()
#endif
    }

    /// Rule 3: the page has reached the end the touch heads for. "Ended" at once, with the
    /// clock's time (right after the last moving frame, not stale: the app keeps the page's
    /// speed and bounces by itself), no tap (it would stop that bounce), and what was left
    /// of the motion is dropped. The scroll itself ends with the next display frame; wheel
    /// events that still head into the end are held (rule 4). Caller holds stateLock.
    private func arriveAtPageEndLocked() {
        sessionLog.endWatch.add("reached the end and ended at once")
        endOneTouchLocked(forced: false)
        holdAtPageEndLocked()
    }

    /// The rest of the scroll's motion is dropped and the hold is up. Caller holds stateLock.
    private func holdAtPageEndLocked() {
        provenBar = watchBar != 0 ? watchBar : nil
        if let place = touchPlace, watchBar != 0 {
            let now = watchClockLocked()
            endHold = EndHold(token: watchToken, place: place, bar: watchBar, towardBottom: watchHeadsToBottom ?? (delta.y < 0), lastAtEnd: now, startedAt: now)
            scheduleHoldExpiryLocked()
        }
        resetMotionLocked()
        oneTouchStopIsHeld = true
    }

    /// Rule 5: the short touch of a scroll that started at the end has had its two moving
    /// frames. "Ended" right after the second, with its real time, so the app makes one
    /// small bounce. Where the bar is proven the rest is dropped and held; where it is
    /// not, the rest of this scroll goes out plain and nothing is taken in. Caller holds
    /// stateLock.
    private func endShortTouchLocked() {
        oneTouchIsShort = false
        endOneTouchLocked(forced: false)
        // Proven is the bar this look found, not the place it was found at.
        let isProven = watchBar != 0 && provenBar == watchBar
        if isProven {
            sessionLog.endWatch.add("the rest dropped")
            holdAtPageEndLocked()
        } else {
            // Plain for now, not for the rest of the scroll: a look is asked again in a
            // while, and at once when the wheel turns.
            sessionLog.endWatch.add("the rest plain (this bar is not proven)")
            watchSeen = false
            watchRetryAt = latestNow + Self.watchRetryInterval
        }
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
    /// Main thread; no lock (`runningScrollHasPhases`).
    private func endScroll(unlessPhasesStay phases: Bool, reason: ScrollSystemLog.EndReason = .settingChanged) {
        guard let running = runningScrollHasPhases, running != phases else { return }
        stop(reason: reason)
    }
    /// One touch to the end: the wheel goes on more than `trackpadStylePointerSlack` from where
    /// the open touch began, in the same process (another pane, another window; for another
    /// process the scroll was ended already). The touch is ended here, before anything of the
    /// new event is stored, so its "ended" is a copy of the last event at its own place. The
    /// new event then begins a touch of its own and takes the motion on, as a flick's wheel
    /// event elsewhere does and as it is with the switch off. Left open, the touch held on to
    /// the first pane until the scroll ran out: apps keep a gesture on the scroller that got
    /// its "began". (The old long touch never looked at the place; it was over 0.18 s after
    /// the wheel stopped.)
    /// `place`: the new event's place, asked only while such a touch is open (in the other
    /// forms nothing of the event is read here; with the switch off this is never called).
    /// Caller holds stateLock, and keeps it until the event's own "began" has gone out.
    private func endOneTouchLocked(unlessAt place: () -> ScrollInputPlace) {
#if DEBUG
        touchChecksForTests += 1
#endif
        guard oneTouchIsOpen, let began = touchPlace else { return }
        let place = place()
        let isFar = place.pid != began.pid
            || hypot(place.pointer.x - began.pointer.x, place.pointer.y - began.pointer.y) > trackpadStylePointerSlack
        guard isFar else { return }
        endOneTouchLocked(forced: true)
    }
    /// Flick: the wheel goes on more than `trackpadStylePointerSlack` from where the touch
    /// began, in the same process (another pane, another window). What the app has of the
    /// running gesture is closed, as a stop closes it: a held "ended" goes out, an open
    /// touch gets its "ended", a glide its "momentum ended"; a touch of which nothing went
    /// out is taken back. Called before the new event is stored, so the closing frames are
    /// copies of the last event at the gesture's own place: an app routes a scroll event by
    /// its place, and posted after the new event was stored they went to the pane under it
    /// (a "momentum ended" for a glide that pane never saw begin, while the first pane's
    /// glide or touch stayed open). The new event then begins a touch of its own, where it
    /// is, and takes the motion on. Caller holds stateLock.
    private func closeFlickGestureLocked() {
        flushHeldEndedLocked()
        phases.dropWaitingMomentumBegan()
        perform(phases.onMomentumFinish(), emitTargetImmediately: true)
        manualInputEnded = true
        momentumActive = false
        momentumEndScheduledTime = nil
        trackingEndScheduledTime = nil
        touchWaitsForTurn = false
    }
    /// One touch: "began", unless the touch is open. Caller holds stateLock.
    private func beginOneTouchLocked(at place: ScrollInputPlace?) {
        guard !oneTouchIsOpen else { return }
        oneTouchIsOpen = true
        touchPlace = place
        sessionLog.touches += 1
        post((y: 0.0, x: 0.0), phaseOverride: phaseValues(for: .TrackingBegin), fallbackToCurrentPhase: false, advancesPhase: false)
    }
    /// One touch: "ended", if the touch is open. Caller holds stateLock.
    /// `forced`: the touch does not end by itself after its rest. Then the two-finger tap
    /// follows the "ended" at once, so that an app that would glide on by itself stops.
    private func endOneTouchLocked(forced: Bool) {
        guard oneTouchIsOpen else { return }
        oneTouchIsOpen = false
        post((y: 0.0, x: 0.0), phaseOverride: phaseValues(for: .TrackingEnd), fallbackToCurrentPhase: false, advancesPhase: false)
        guard forced else { return }
        for phase in Self.twoFingerTap {
            post((y: 0.0, x: 0.0), phaseOverride: phase, fallbackToCurrentPhase: false, advancesPhase: false)
        }
    }
    /// A scroll that ran as one touch goes on in a form the phase machine posts itself: the
    /// app's kind was found in mid-scroll (Chromium-based: a flick). The app's touch is ended,
    /// and the machine, which ran as with the switch off, starts from nothing, so the wheel
    /// event begins a gesture of the new form. (The other way round does not happen: a kind
    /// only changes from not known to Chromium-based.) Caller holds stateLock.
    private func leaveOneTouchLocked() {
        endOneTouchLocked(forced: true)
        scrollIsOneTouch = false
        phases.reset()
        manualInputEnded = true
        momentumActive = false
        momentumEndScheduledTime = nil
        trackingEndScheduledTime = nil
    }
    /// A scroll goes on as one touch. As a rule it begins as one, and nothing is open. But
    /// when it ran in a form the phase machine posts (a flick, the old long touch), what
    /// the app has of that gesture is closed first, as a stop closes it: an open touch gets
    /// its "ended", a glide its "momentum ended". Then the machine starts from nothing and
    /// runs as with the switch off. (No path does that today: an app's kind only changes
    /// from not known to "follows the glide". Without this such a change left the glide
    /// open for good: the one touch posts nothing of the machine's.) Caller holds stateLock.
    private func enterOneTouchLocked() {
        if phases.beganIsWaiting {
            // A flick's touch of which nothing went out: there is nothing to close.
            phases.reset()
        } else {
            flushHeldEndedLocked()
            phases.dropWaitingMomentumBegan()
            perform(phases.onMomentumFinish(), emitTargetImmediately: true)
            phases.reset()
        }
        manualInputEnded = true
        momentumActive = false
        momentumEndScheduledTime = nil
        trackingEndScheduledTime = nil
        touchWaitsForTurn = false
        endedWaitsForGlide = false
        scrollIsOneTouch = true
    }
    /// 处理一次滚轮输入: 缓冲与阶段 (调用方须持有 stateLock)
    private func handleInputLocked(_ input: ScrollPosterInput, at now: CFTimeInterval, place: ScrollInputPlace? = nil) {
        if sessionLog.isEmpty {
            sessionLog.startedAt = now
        }
        latestNow = max(latestNow, now)
        sessionLog.inputs += 1
        sessionLog.transition = input.duration
        sessionLog.inputDistance += abs(input.y) + abs(input.x)
        sessionLog.lastInputAt = now
        sessionLog.trackpadStyle = config.simTrackpadEnabled
        sessionLog.flick = config.flick
        sessionLog.oneTouch = config.oneTouch
        sessionLog.trackpadStyleWithheld = config.withheld
        sessionLog.trackpadStyleSideways = config.sideways
        lastActivityTime = now
        inputSequence &+= 1
        // (One touch: a stop that waited for the touch's rest is off; the scroll goes on.)
        oneTouchStopIsHeld = false
        if scrollIsOneTouch != config.oneTouch {
            if config.oneTouch {
                enterOneTouchLocked()
            } else {
                leaveOneTouchLocked()
            }
        }
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
        if config.simTrackpadEnabled && !scrollIsOneTouch {
            // (The forms the machine posts. As the old long touch the glide's "momentum ended"
            // went out here although its "momentum began" had not: no frame of the glide had
            // been posted.)
            // A flick's "ended" that still waited for that glide goes out first.
            flushHeldEndedLocked()
            phases.dropWaitingMomentumBegan()
        }
        let phase = phases.phase
        let separatedPhase = (phase == .Idle || phase == .MomentumEnd || phase == .TrackingEnd)
        let separated = manualInputEnded || separatedByTime || separatedPhase
        let plan = phases.onManualInputDetected(isSeparated: separated)
        if plan.beginsTouch && !scrollIsOneTouch {
            touchBeganTime = now
            movingTouchFrames = 0
            touchPlace = place
            sessionLog.touches += 1
        }
        touchWaitsForTurn = false
        glideDelta = delta
        perform(plan, emitTargetImmediately: false, beganWaitsForItsFrame: config.flick)
        lastManualEventTime = now
        manualInputEnded = false
        momentumActive = false
        momentumEndScheduledTime = nil
        trackingEndScheduledTime = nil
        if scrollIsOneTouch {
            // The app's touch: it begins with the scroll's first wheel event, and again with a
            // wheel event that comes after it has ended (the frames had run out, or the wheel
            // went on far from its place). While it is open a wheel event only goes on with it,
            // however long after the last one: the machine counts that as a new scroll by its
            // time alone, the touch does not.
            // Since the end watch the touch opens with the answer to this scroll's look
            // (`endWatchAnswered`), not here: until then the frames are plain.
            watchForOneTouchLocked(at: place, now: now, towardBottom: input.y != 0.0 ? input.y < 0 : nil)
        }
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
        flushHeldEndedLocked()
        phases.dropWaitingMomentumBegan()
        // "Momentum ended" goes out now; "began" goes out on this frame (`config.flick`).
        perform(phases.onManualInputDetected(isSeparated: true), emitTargetImmediately: false, beganWaitsForItsFrame: config.flick)
        touchBeganTime = now
        movingTouchFrames = 0
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
    /// The "scroll sideways" key went down or up. Main thread.
    func updateShifting(enable: Bool) {
        if enable != sidewaysKeyIsDown && runningScrollHasPhases == true {
            // The frames of the scroll that runs would turn sideways (or back) with their
            // phases on: a sideways gesture is a swipe to the app (`isMainlySideways`). The
            // scroll is ended, as when the wheel itself turns sideways. Never with the
            // switch off, and never for a scroll without phases.
            stop(reason: .axisChanged)
        }
        sidewaysKeyIsDown = enable
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
    /// Without `flick`: one touch to the end, or with `oldLongTouch` the long touch of the
    /// evaluation switch.
    func setConfigForTests(simTrackpadEnabled: Bool, deadZone: Double = 1.0, flick: Bool = true, oldLongTouch: Bool = false) {
        os_unfair_lock_lock(&stateLock)
        applyConfigLocked(ConfigSnapshot(
            simTrackpadEnabled: simTrackpadEnabled,
            flick: simTrackpadEnabled && flick,
            oneTouch: simTrackpadEnabled && !flick && !oldLongTouch,
            deadZone: deadZone
        ))
        os_unfair_lock_unlock(&stateLock)
    }
    /// The form the next wheel event arrives in, taken up as `smooth(event:input:)` does it: a
    /// scroll that runs with phases is ended first when the new form has none, and the other
    /// way round.
    func changeFormForTests(simTrackpadEnabled: Bool, deadZone: Double = 1.0, flick: Bool = true, oldLongTouch: Bool = false) {
        endScroll(unlessPhasesStay: simTrackpadEnabled)
        setConfigForTests(simTrackpadEnabled: simTrackpadEnabled, deadZone: deadZone, flick: flick, oldLongTouch: oldLongTouch)
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
        if let place = place {
            endOneTouchLocked(unlessAt: { place })
            if config.flick, !staysAtTouchPlaceLocked(place) {
                closeFlickGestureLocked()
            }
        }
        handleInputLocked(input, at: time, place: place)
        let phases = config.simTrackpadEnabled
        let call = takeWatchCallLocked()
        os_unfair_lock_unlock(&stateLock)
        runningScrollHasPhases = phases
        make(call)
    }
    /// One display frame at `now`, exactly as the display link runs it but without the hop
    /// to the main thread: returns the stop request the frame makes, if any.
    func displayLinkFrameForTests(frameInterval: Double, now: CFTimeInterval) -> ScrollStopRequest? {
        os_unfair_lock_lock(&stateLock)
        let request = displayLinkFrameLocked(frameInterval: frameInterval, now: now)
        let call = takeWatchCallLocked()
        os_unfair_lock_unlock(&stateLock)
        make(call)
        return request
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
        let call = takeWatchCallLocked()
        os_unfair_lock_unlock(&stateLock)
        make(call)
        if let request = request {
            scheduleStop(request)
        }
    }
#endif

    private func resetUnlocked() {
        // 重置数值
        dispatchContext.clearContext()
        resetMotionLocked()
        lastFrameHostTime = 0
        touchPlace = nil
        lastInputPlace = nil
        oneTouchIsOpen = false
        scrollIsOneTouch = false
        oneTouchStopIsHeld = false
        // The end watch: answers still on their way belong to no scroll now. (A hold at a
        // page's end and the proven bar outlive the scroll.)
        watchToken &+= 1
        watchAsked = false
        watchSeen = nil
        watchCall = nil
        watchFollowed = false
        watchHasFirstValue = false
        watchHeadsToBottom = nil
        watchRetryAt = nil
        watchLookIsRetry = false
        watchReadFailures = 0
        watchJudgedValue = nil
        watchWrongWayReads = 0
        watchWrongWayMoved = 0
        framesHeadToBottom = nil
        oneTouchIsShort = false
        oneTouchLeavesFramesOut = false
        contentWatch = nil
        contentSent = 0
        frameStamp = 0
        frameStampStep = 0
        // (`lastPhasedStamp` stays: the next scroll's frames come after this one's. Its
        // closing frames can sit a little ahead of the clock, and a wheel event right
        // after a stop began a gesture with a time before the one that had just closed.)
        lineCarry.reset()
    }

    /// The motion and the phase machine back to nothing, as a stop leaves them. Without what
    /// belongs to the app's gesture and to the posting: the event to copy, the open touch
    /// and its place, the frames' times. `stop` does both; a one touch that still rests
    /// when its scroll is over does this alone (`processFrameLocked`), so that a wheel event
    /// in the rest meets what it would meet after the stop. Caller holds stateLock.
    private func resetMotionLocked() {
        current = ( y: 0.0, x: 0.0 )
        delta = ( y: 0.0, x: 0.0 )
        buffer = ( y: 0.0, x: 0.0 )
        leadLimiterY.reset()
        leadLimiterX.reset()
        pixelCarry.reset()
        // 重置插值器
        filter.reset()
        phases.reset()
        manualInputEnded = true
        momentumActive = false
        lastManualEventTime = 0.0
        touchBeganTime = 0.0
        movingTouchFrames = 0
        endedWaitsForGlide = false
        touchWaitsForTurn = false
        glideDelta = ( y: 0.0, x: 0.0 )
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
        runningScrollHasPhases = nil
        runningScrollIsSideways = false
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
            if scrollIsOneTouch {
                // What the app has is the touch, not the machine's phases: it is ended, if
                // it is still open. A touch that is open at a stop did not end by itself.
                endOneTouchLocked(forced: true)
            } else {
                // A flick's "ended" that waited for a glide of which no frame came: alone.
                flushHeldEndedLocked()
                perform(plan, emitTargetImmediately: true)
            }
        } else {
            // Chrome only, from Mos ("only [4, 0] lets Chrome recover"): after frames without
            // phases Chrome stays in its scroll until an "ended" arrives, so one is posted at
            // every stop although the switch is off. Kept exactly as it was: it is part of
            // what Chrome gets at the default settings, and whether Chrome still needs it (or
            // the other Chromium apps want it too) can only be seen on screen.
            if let snapshot = dispatchContext.preparePostingSnapshot(),
               isEventTargetingChrome(snapshot.event),
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
        // here (Chrome's "ended" above goes out as it always did), and a stop waits for nothing.
        let closingFrameQueued = enableSimTrackpad && queuedFrames != queuedBefore
        manualInputEnded = true
        momentumActive = false
        let finished = sessionLog
        sessionLog = ScrollSystemLog.Session()
        endHoldHint = endHold != nil
        // 重置参数 (不递增 generation, 保留本次收尾帧有效性)
        resetUnlocked()
        os_unfair_lock_unlock(&stateLock)
        // A frame that closes the gesture can also wait from before this stop: the one
        // touch's "ended" is queued by the display link's thread (it is kept, see `enqueue`).
        if closingFrameQueued || (enableSimTrackpad && dispatchContext.hasWaitingGestureFrames) {
            // The closing frames ("ended", "momentum ended") are out before this returns,
            // unless a post takes longer than the wait's deadline (50 ms).
            // They are posted from the post queue, and what ended the scroll is often an
            // event on its own way to the same app: a finger that begins to scroll on the
            // trackpad (the tap's callback lets that "began" through right after this), a
            // click. Nothing ordered the two: when the trackpad's "began" arrived first, the
            // app got "began, ended" and the finger's scroll had no gesture left. At quit the
            // process could be gone before the frame was posted. The wait is short, and it
            // has a deadline: see `ScrollDispatchContext.waitForQueuedFrames`.
            if !dispatchContext.waitForQueuedFrames() {
                noteClosingFramesStillWait()
            }
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
    /// The line for the `app` log when a stop's wait for its closing frames ran out.
    static let closingFramesStillWaitLine = "ScrollPoster: the frames that close a scroll's gesture were still waiting to be posted when the stop's wait for them ran out; the stop went on, and they are posted in their order when the queue reaches them"
    /// At most one such line in this many seconds.
    static let closingFramesStillWaitInterval: CFTimeInterval = 10
    /// A stop waited its whole deadline for the post queue. One line, not one per stop: while
    /// a post hangs, every stop finds the same. Main thread.
    private func noteClosingFramesStillWait() {
        let now = Self.monotonicNow()
        guard now - lastClosingFramesStillWaitLine >= Self.closingFramesStillWaitInterval else { return }
        lastClosingFramesStillWaitLine = now
        logHealth(problem: Self.closingFramesStillWaitLine)
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
    /// `beganWaitsForItsFrame`: as a flick. A "began" in the plan is not posted as a frame of
    /// its own: the machine takes it up, and the next frame that moves the page carries it
    /// (`ScrollPhase.holdsWaitingBegan`).
    func perform(_ plan: ScrollPhase.TransitionPlan, emitTargetImmediately: Bool, beganWaitsForItsFrame: Bool = false) {
        if plan.queue.isEmpty && plan.target == nil {
            return
        }
        for item in plan.queue {
            if beganWaitsForItsFrame && item.0 == .TrackingBegin {
                phases.apply(phase: item.0, autoAdvance: item.1)
            } else {
                emitPhase(item)
            }
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
        if scrollIsOneTouch {
            // One touch: the machine moves on as it does with the switch off, and nothing of
            // it is posted (there a frame without distance goes out here, which moves no page).
            phases.didDeliverFrame()
            return
        }
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
        // (One touch only: the next read of the scroll bar is asked for off this thread,
        // once the lock is let go; nothing here waits for it.)
        let call = takeWatchCallLocked()
        os_unfair_lock_unlock(&stateLock)
        make(call)
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
    /// forms the machine posts: as the old long touch (the evaluation switch), too, the touch
    /// ends when the wheel has been still for `manualContinuationThreshold` and either a
    /// glide follows or the last frame has gone out.
    /// As one touch to the end nothing of this reaches the app either: the machine runs as
    /// with the switch off, and the app's touch ends by a rule of its own
    /// (`oneTouchHasRunOutLocked`). Caller holds stateLock.
    func fingerLiftedLocked(now: CFTimeInterval, glideFollows: Bool, outputSettled: Bool) -> Bool {
        if config.flick {
            guard now - touchBeganTime >= trackpadStyleTouchTime else { return false }
            if movingTouchFrames >= 2 {
                return glideFollows || outputSettled
            }
            // Fewer than two frames have moved the page: the touch goes on for the frames
            // that still come, and ends only when the scroll has nothing more to send.
            return !glideFollows && outputSettled
        }
        let wheelIsStill = now - lastManualEventTime > manualContinuationThreshold
        // Without phases nothing of this reaches an app: exactly as it always was.
        guard config.simTrackpadEnabled, !scrollIsOneTouch else { return wheelIsStill }
        return wheelIsStill && (glideFollows || outputSettled)
    }

    /// One touch to the end: whether the open touch ends with this frame. The wheel is still
    /// (as for the machine: `manualContinuationThreshold`), the last frame has gone out (this
    /// one is under the dead zone), and none is still to come: after a wheel event the other
    /// way the motion comes to a standstill before it turns (what the old way left runs down
    /// first), with most of the way back still ahead, and the frames the remaining distance
    /// asks for are over the dead zone. That is no end. Caller holds stateLock.
    func oneTouchHasRunOutLocked(now: CFTimeInterval, outputMagnitude: Double, residualMagnitude: Double, speedDeadZone: Double) -> Bool {
        return now - lastManualEventTime > manualContinuationThreshold
            && outputMagnitude <= speedDeadZone
            && residualMagnitude * duration <= speedDeadZone
    }

    /// 处理一帧, 返回需要以哪个阶段结束会话 (nil 表示继续)。调用方须持有 stateLock。
    func processFrameLocked(frameInterval: Double, now: CFTimeInterval) -> Phase? {
        var pendingStopPhase: Phase?
        latestNow = max(latestNow, now)
        if config.simTrackpadEnabled {
            advanceFrameStampLocked(frameInterval: frameInterval, now: now)
            isInDisplayFrame = true
        }
        defer { isInDisplayFrame = false }
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
            if config.flick && residualMagnitude > deadZone, endPlan.queue.isEmpty, let target = endPlan.target, target.0 == .TrackingEnd {
                // A glide follows: "ended" goes out with its first frame (`flushHeldEndedLocked`).
                phases.apply(phase: target.0, autoAdvance: target.1)
                endedWaitsForGlide = true
            } else if !(endPlan.queue.isEmpty && endPlan.target == nil) {
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
        // One touch to the end: while the app's touch is not open nothing goes out. (It ends
        // when the frames have fallen under the dead zone and none is to come, and a wheel
        // event opens it again, so no frame falls in between; one that came out over the dead
        // zone again by itself, after an uneven frame interval, would have no touch to belong
        // to: that pixel is left out.)
        // (Only after a touch that ended by itself. While this scroll's look has no answer
        // yet, and when the bar was not seen, the frames go out plain: `post`.)
        let oneTouchIsOver = scrollIsOneTouch && !oneTouchIsOpen && oneTouchLeavesFramesOut
        // 发送滚动结果 - 只有当输出值超过死区阈值时才发送
        if outputMagnitude > speedDeadZone && !oneTouchIsOver {
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
                if scrollIsOneTouch { contentSent += pixels.y }
                sessionLog.largestFrame = max(sessionLog.largestFrame, moved)
                sessionLog.lastFrameAt = now
                lastActivityTime = now
                if oneTouchIsOpen {
                    if pixels.y != 0.0, framesHeadToBottom != (pixels.y < 0) {
                        // The frames turned: "the wrong way" is judged from here anew.
                        framesHeadToBottom = pixels.y < 0
                        framesSameWaySince = now
                        watchJudgedValue = nil
                        watchWrongWayReads = 0
                        watchWrongWayMoved = 0
                    }
                    if oneTouchIsShort {
                        shortTouchFrames += 1
                        if shortTouchFrames >= 2 {
                            endShortTouchLocked()
                        }
                    }
                }
            }
        }
        if oneTouchIsOpen && oneTouchHasRunOutLocked(now: now, outputMagnitude: outputMagnitude, residualMagnitude: residualMagnitude, speedDeadZone: speedDeadZone)
            && oneTouchHasRestedLocked() {
            // By itself: "ended" alone, its time `oneTouchRest` after the touch's last frame.
            endOneTouchLocked(forced: false)
            oneTouchLeavesFramesOut = true
            oneTouchIsShort = false
        }
        if scrollIsOneTouch {
            if let content = contentWatch {
                if oneTouchIsOpen && now - watchLastAnswerAt > Self.watchBlindLimit {
                    // No reading for too long: the touch is not left open without one.
                    sessionLog.endWatch.content?.decided.append("no reading for \(Int(Self.watchBlindLimit * 1000)) ms: ended by force, plain")
                    contentWatch = nil
                    goPlainLocked(retry: true, now: now)
                } else if !watchReadInFlight && watchCall == nil {
                    watchReadInFlight = true
                    watchCall = .content(token: watchToken, epoch: watchEpoch,
                                         retake: content.needsRetake ? touchPlace?.pointer : nil, pid: touchPlace?.pid ?? 0)
                }
            } else if oneTouchIsOpen && watchSeen == true {
                if now - watchLastAnswerAt > Self.watchBlindLimit {
                    // No reading for too long (a watch that does not answer): the touch is
                    // not left open without one.
                    sessionLog.endWatch.lost += 1
                    sessionLog.endWatch.add("no reading for \(Int(Self.watchBlindLimit * 1000)) ms: ended the touch, plain until the bar is seen again")
                    goPlainLocked(retry: true, now: now)
                } else if !watchReadInFlight && watchCall == nil {
                    // The bar is read again, once per display frame at most.
                    watchReadInFlight = true
                    watchCall = .read(token: watchToken, epoch: watchEpoch, askedAt: now)
                }
            } else if watchSeen == false, let retryAt = watchRetryAt, now >= retryAt, watchCall == nil, !oneTouchIsOpen {
                // Blind, and the scroll goes on: look again.
                askForALookLocked(now: now, isRetry: true)
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
        if scrollIsOneTouch {
            if pendingStopPhase != nil && oneTouchIsOpen {
                // The scroll is over, as it would be with the switch off, but the app's touch
                // still rests. The motion is put back to nothing, as the stop would leave it,
                // and the stop itself waits until "ended" has gone out. A wheel event until
                // then goes on with the open touch.
                resetMotionLocked()
                oneTouchStopIsHeld = true
                pendingStopPhase = nil
            } else if oneTouchStopIsHeld && !oneTouchIsOpen {
                oneTouchStopIsHeld = false
                pendingStopPhase = .TrackingEnd
            }
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
    private func configSnapshot(for event: CGEvent?, input: ScrollPosterInput? = nil) -> ConfigSnapshot {
        let switchOn = Self.trackpadStyleIsOn(application: ScrollCore.shared.application, global: Options.shared.scroll)
        // With the switch on only: a scroll that is mainly sideways carries no phases.
        let sideways = switchOn && (input.map {
            Self.isMainlySideways(y: $0.y, x: $0.x, sidewaysKey: sidewaysKeyIsDown,
                                  running: runningScrollHasPhases == nil ? nil : runningScrollIsSideways)
        } ?? false)
        let simTrackpad = switchOn && !sideways
        // Asked with trackpad-style events only. It never reads the disk here: an app seen
        // for the first time counts as touch-only until its bundle was looked into, off this
        // thread (`ScrollUtils.trackpadStyleTarget`).
        var target = simTrackpad ? event.map { trackpadStyleTarget($0) } : nil
        var isShell = false
        // The two switches under the main one: where it works. (Not asked with it off.)
        var isAllowed = true
        var shellStaysPlain = false
        if simTrackpad {
            switch target {
            case .followsGlide, .safari, .nativeShell:
                isAllowed = trackpadStyleInBrowsers()
                shellStaysPlain = target == .nativeShell && isAllowed && !trackpadStyleInMacApps()
            case .touchOnly, nil:
                isAllowed = trackpadStyleInMacApps()
            case .plainScrolling:
                break
            }
        }
        if !isAllowed {
            // As with the main switch off: no phases, no look, nothing asked of the app.
            return ConfigSnapshot(simTrackpadEnabled: false, flick: false, withheld: true, sideways: sideways,
                                  deadZone: OPTIONS_SCROLL_DEFAULT.usableDeadZone(Options.shared.scroll.deadZone))
        }
        if target == .nativeShell, let event = event {
            // A native shell around Chromium: the one touch (plain frames, unless a bar is
            // seen) where a look has said "not the page" about this place, the flick
            // everywhere else.
            isShell = true
            let place = ScrollInputPlace(pid: pid_t(event.getIntegerValueField(.eventTargetUnixProcessID)), pointer: event.location)
            os_unfair_lock_lock(&stateLock)
            let isNotThePage = shellVerdictLocked(at: place, now: inputClock()) == false
            os_unfair_lock_unlock(&stateLock)
            target = isNotThePage ? .touchOnly : .followsGlide
        }
        // Whether the record comes off is asked only where the answer is needed: over a
        // WebKit browser, and for frames that carry phases. With the switch off
        // (and for an app that gets no phases) nobody asks, and the self-test does not run.
        let form = Self.trackpadStyleForm(switchOn: simTrackpad, target: target, oldLongTouch: usesOldLongTouch,
                                          recordComesOff: simTrackpad && target == .safari && hardwareRecordComesOff())
        return ConfigSnapshot(
            simTrackpadEnabled: form.phases,
            flick: form.flick,
            withheld: form.withheld,
            oneTouch: form.oneTouch,
            sideways: sideways,
            takesRecordOff: form.phases && hardwareRecordComesOff(),
            looksWait: form.oneTouch && !(event.map { appKindIsKnown($0) } ?? true),
            isShell: isShell,
            shellStaysPlain: shellStaysPlain,
            deadZone: OPTIONS_SCROLL_DEFAULT.usableDeadZone(Options.shared.scroll.deadZone)
        )
    }

    /// Caller holds stateLock.
    private func applyConfigLocked(_ snapshot: ConfigSnapshot) {
        config = snapshot
        // Both forms of trackpad-style events (it used to be the flick only: as one long
        // touch a glide whose first frame came to no whole pixel lost its "momentum began").
        // (Not as one touch: there the machine runs as with the switch off.)
        phases.holdsWaitingMomentumBegan = snapshot.simTrackpadEnabled && !snapshot.oneTouch
        phases.holdsWaitingBegan = snapshot.flick
    }

    /// Flick: the "ended" that waited for the glide goes out now: right before the glide's
    /// first frame ("momentum began", in the same display frame), before a new touch, or
    /// alone when the scroll ends. Caller holds stateLock.
    func flushHeldEndedLocked() {
        guard endedWaitsForGlide else { return }
        endedWaitsForGlide = false
        post((y: 0.0, x: 0.0), phaseOverride: phaseValues(for: .TrackingEnd), fallbackToCurrentPhase: false, advancesPhase: false)
    }

    /// Trackpad-style: moves the frames' time grid on by one display frame. The grid starts
    /// at the clock's time and then steps by the display's own interval, the value the
    /// frame's distance was computed with, whenever the callback ran.
    /// - The clock is more than a frame ahead of the next grid time (the link stalled, or a
    ///   callback ran more than a frame late): the grid goes forward to the clock.
    /// - The grid's next time is more than a frame ahead of the clock (after a late
    ///   callback the link caught up at once; the display's rate went up): the grid goes on
    ///   by half a step until the clock has caught up. It never goes back: put back on the
    ///   clock, the next frame's time fell before the last one's and came out 1 ms after
    ///   it, with a whole frame's distance (an app that divides the two read 17 times the
    ///   speed).
    /// So the times of two frames from display frames that follow each other are never less
    /// than half a display interval apart. `now`: the display frame's own reading of the
    /// clock (`monotonicNow`, the event clock in seconds). Caller holds stateLock.
    func advanceFrameStampLocked(frameInterval: Double, now seconds: CFTimeInterval) {
        let now = Self.nanoseconds(seconds) ?? eventTimestamp()
        // (An interval that is no sane number counts as none: the grid then follows the clock.)
        let step = frameInterval.isFinite && frameInterval > 0 && frameInterval < 10 ? UInt64((frameInterval * 1_000_000_000).rounded()) : 0
        frameStampStep = step
        guard frameStamp != 0 else {
            frameStamp = max(now, lastPhasedStamp)
            return
        }
        let next = frameStamp &+ step
        if now > next &+ step {
            frameStamp = now
        } else if next > now &+ step {
            frameStamp = frameStamp &+ max(step / 2, Self.leastStampStep)
        } else {
            frameStamp = next
        }
    }

    /// One touch: whether the open touch has rested, so that its "ended" can go out with this
    /// display frame: the time that "ended" would carry is `oneTouchRest` or more after the
    /// time of the touch's last frame (its last "changed", or its "began"). Counted in the
    /// frames' own times, which is what the app compares. Caller holds stateLock.
    func oneTouchHasRestedLocked() -> Bool {
        guard isInDisplayFrame, frameStamp != 0, lastPhasedStamp != 0 else { return false }
        return nextStampLocked(moves: false) >= lastPhasedStamp &+ Self.oneTouchRest
    }

    /// Trackpad-style: the time for the next frame with phases.
    /// - A frame that moves the page, from a display frame: that frame's time on the grid, so
    ///   two such frames are exactly as far apart as their display frames.
    /// - A frame without distance from a display frame ("ended", "momentum ended"): just
    ///   after the display frame before. It can be followed in the same display frame by one
    ///   that moves the page ("ended", then "momentum began" with its distance), and that one
    ///   keeps its place on the grid.
    /// - A frame from the main thread ("began" at a wheel event, the frames of a stop): the
    ///   clock's time.
    /// Never the same time twice and never backward (`leastStampStep`). Caller holds stateLock.
    func stampLocked(moves: Bool) -> UInt64 {
        let stamp = nextStampLocked(moves: moves)
        lastPhasedStamp = stamp
        if moves && isInDisplayFrame && stamp > frameStamp {
            // The frame had to be put after the one before it (that one came from the main
            // thread, or from the scroll before): the grid goes on from here, so that the
            // next frame is a whole step after this one.
            frameStamp = stamp
        }
        return stamp
    }

    /// The time `stampLocked` would give, without taking it. Caller holds stateLock.
    func nextStampLocked(moves: Bool) -> UInt64 {
        var stamp: UInt64
        if isInDisplayFrame && frameStamp != 0 {
            stamp = moves || frameStamp <= frameStampStep ? frameStamp : frameStamp - frameStampStep + Self.leastStampStep
        } else {
            stamp = eventTimestamp()
        }
        if lastPhasedStamp != 0 && stamp < lastPhasedStamp &+ Self.leastStampStep {
            stamp = lastPhasedStamp &+ Self.leastStampStep
        }
        return stamp
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
    /// `advancesPhase`: the phase machine moves on with this frame (`didDeliverFrame`), as it
    /// does with every frame it posts or times. Not with the one touch's own "began" and
    /// "ended": the machine knows nothing of them and runs as with the switch off.
    func post(_ v: (y: Double, x: Double), phaseOverride: (scroll: Double, momentum: Double)? = nil, fallbackToCurrentPhase: Bool = true, advancesPhase: Bool = true, using preparedSnapshot: ScrollDispatchContext.PostingSnapshot? = nil) -> Bool {
        let moves = v.y != 0.0 || v.x != 0.0
        if moves && endedWaitsForGlide {
            // The glide's first frame: its touch's "ended" goes out right before it.
            flushHeldEndedLocked()
        }
        var phaseValues = phaseOverride
        if phaseValues == nil && fallbackToCurrentPhase && config.simTrackpadEnabled {
            // One touch: every frame that moves the page is a "changed" of the open touch.
            // While the touch is not open (no answer from the end watch yet, or the bar was
            // not seen) the frame has no phases: it is written as with the switch off.
            phaseValues = scrollIsOneTouch
                ? (oneTouchIsOpen ? self.phaseValues(for: .TrackingOngoing) : nil)
                : self.phaseValues(for: phases.phase)
        }
        var frame = ScrollOutgoingFrame(y: v.y, x: v.x, scrollPhase: phaseValues?.scroll, momentumPhase: phaseValues?.momentum)
        if config.simTrackpadEnabled && frame.carriesPhases {
            // Its own time and its own line delta (`ScrollOutgoingFrame.write`). Not the
            // "ended" Chrome gets at a stop with the switch off: that one stays as it was.
            frame.isTrackpadStyle = true
            if moves && (frame.scrollPhase == 1.0 || frame.scrollPhase == 2.0) {
                movingTouchFrames += 1
            }
            frame.timestamp = stampLocked(moves: moves)
            let lines = lineCarry.take((y: v.y / ScrollOutgoingFrame.pixelsPerLine, x: v.x / ScrollOutgoingFrame.pixelsPerLine))
            frame.lineY = ScrollOutgoingFrame.wholeLines(lines.y)
            frame.lineX = ScrollOutgoingFrame.wholeLines(lines.x)
        }
#if DEBUG
        if let recorder = frameRecorderForTests {
            recorder(frame)
            targetRecorderForTests?(frame, dispatchContext.targetPID ?? 0)
            if advancesPhase { phases.didDeliverFrame() }
            return true
        }
#endif
        guard var snapshot = preparedSnapshot ?? dispatchContext.preparePostingSnapshot() else {
            return false
        }
        frame.write(to: snapshot.event)
        if frame.isTrackpadStyle && config.takesRecordOff {
            // The copy still carries the wheel's record: its time and "one notch". WebKit
            // makes a glide of its own from the record on "momentum began" and drops the
            // glide it is sent; nobody else reads it (`ScrollHardwareRecord`).
            ScrollHardwareRecord.remove(from: snapshot.event)
        }
        snapshot.opensOrClosesGesture = frame.opensOrClosesGesture
        ScrollUtils.shared.markSyntheticSmoothEvent(snapshot.event)
        // 通过 CGEventPostToPid 直投目标进程:
        // 不依赖 proxy (消除崩溃), 不经过 tap 链重新路由 (动量不跟随光标)
        // ref: @shichangone MR: https://github.com/Caldis/Mos/pull/523, issue #868
        dispatchContext.enqueue(snapshot)
        queuedFrames &+= 1
        if advancesPhase { phases.didDeliverFrame() }
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
