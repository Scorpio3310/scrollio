//
//  ScrollDispatchContext.swift
//  Mos
//
//  Created by Codex on 2026/3/5.
//

import Cocoa
import os

final class ScrollDispatchContext {

    static let shared = ScrollDispatchContext()

    struct PostingSnapshot {
        let event: CGEvent
        let targetPID: pid_t
        let generation: UInt64
        /// When this frame was made (`ScrollPoster.monotonicNow`).
        let createdAt: CFTimeInterval
        /// The frame opens or closes a gesture for the app: "began", "ended", "momentum
        /// began", "momentum ended" (`ScrollOutgoingFrame.opensOrClosesGesture`). A stop that
        /// comes while such a frame still waits on the post queue does not drop it, as it
        /// drops the frames that only move the page: see `enqueue`.
        var opensOrClosesGesture = false
    }

    private struct SnapshotState {
        var eventTemplate: CGEvent?
        var targetPID: pid_t = 0
        var generation: UInt64 = 0
    }

    private var state = SnapshotState()
    /// Frames that open or close a gesture and still wait on the post queue. Guarded by `lock`.
    private var waitingGestureFrames = 0
    private var lock = os_unfair_lock_s()
    private let postQueue = DispatchQueue(label: "com.nikklemenc.Scrollio.scrollposter.post", qos: .userInteractive)
    // TTL 仅作为 enqueue 投递时的兜底安全网, 不用于快照创建门控
    // A frame that waited this long on the post queue is not posted any more. It is counted
    // from when the frame was made. It used to be counted from the last wheel event: at glide
    // time 5.0 a long scroll's last frames, and the "momentum ended" that closes it, come more
    // than 5 s after that event and were dropped, so the app's glide never ended.
#if DEBUG
    var eventTTL: CFTimeInterval = 5.0
#else
    private let eventTTL: CFTimeInterval = 5.0
#endif

#if DEBUG
    /// Tests: receives each frame that would be posted, with its target, instead of the process.
    var postObserverForTests: ((CGEvent, pid_t) -> Void)?
    private var postedFrames: UInt64 = 0
    private var droppedFramesByGeneration: UInt64 = 0
    private var droppedFramesByTTL: UInt64 = 0
    private var skippedSyntheticEvents: UInt64 = 0
    private var updateSnapshotFailures: UInt64 = 0
#endif

#if DEBUG
    init() {}
#else
    private init() {}
#endif

    @discardableResult
    func capture(event: CGEvent) -> Bool {
        guard let template = event.copy() else {
#if DEBUG
            os_unfair_lock_lock(&lock)
            updateSnapshotFailures &+= 1
            os_unfair_lock_unlock(&lock)
#endif
            return false
        }
        let pid = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
        os_unfair_lock_lock(&lock)
        state.eventTemplate = template
        state.targetPID = pid
        os_unfair_lock_unlock(&lock)
        return true
    }

    /// The process the frames go to: the target of the last wheel event captured. nil: none
    /// (no scroll since the last stop).
    var targetPID: pid_t? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return state.targetPID != 0 ? state.targetPID : nil
    }

    func advanceGeneration() {
        os_unfair_lock_lock(&lock)
        state.generation &+= 1
        os_unfair_lock_unlock(&lock)
    }

    func clearContext() {
        os_unfair_lock_lock(&lock)
        state.eventTemplate = nil
        state.targetPID = 0
        os_unfair_lock_unlock(&lock)
    }

    func invalidateAll() {
        os_unfair_lock_lock(&lock)
        state.generation &+= 1
        state.eventTemplate = nil
        state.targetPID = 0
        os_unfair_lock_unlock(&lock)
    }

    func preparePostingSnapshot() -> PostingSnapshot? {
        os_unfair_lock_lock(&lock)
        guard state.targetPID != 0,
              let eventClone = state.eventTemplate?.copy() else {
            os_unfair_lock_unlock(&lock)
            return nil
        }
        let snapshot = PostingSnapshot(event: eventClone, targetPID: state.targetPID, generation: state.generation, createdAt: ScrollPoster.monotonicNow())
        os_unfair_lock_unlock(&lock)
        return snapshot
    }

    /// Posts a frame from the post queue, in the order queued.
    ///
    /// A stop moves the generation on, and a frame from before it that only moves the page
    /// is dropped: the scroll is over. A frame that opens or closes a gesture is not: the
    /// app's gesture has to stay whole whatever comes between its queueing and its post. The
    /// one touch's "ended" is queued by the display link's thread, and the stop for that
    /// scroll follows it 40 ms to a quarter of a second later (a click or a finger can come
    /// sooner); when a post before it took longer than that, the "ended" was still waiting,
    /// was dropped here, and the stop queued nothing in its place: "began" without "ended".
    /// Such a frame goes out without its distance when the scroll it belonged to was stopped
    /// ("momentum began" carries the glide's first step). Only its age can drop it.
    func enqueue(_ snapshot: PostingSnapshot) {
        if snapshot.opensOrClosesGesture {
            os_unfair_lock_lock(&lock)
            waitingGestureFrames += 1
            os_unfair_lock_unlock(&lock)
        }
        postQueue.async { [self] in
            os_unfair_lock_lock(&self.lock)
            let now = ScrollPoster.monotonicNow()
            let currentGeneration = snapshot.generation == self.state.generation
            let validGeneration = currentGeneration || snapshot.opensOrClosesGesture
            let validTTL = now - snapshot.createdAt <= self.eventTTL
            if snapshot.opensOrClosesGesture {
                self.waitingGestureFrames -= 1
            }
            if !validGeneration {
#if DEBUG
                self.droppedFramesByGeneration &+= 1
#endif
            } else if !validTTL {
#if DEBUG
                self.droppedFramesByTTL &+= 1
#endif
            }
            os_unfair_lock_unlock(&self.lock)
            guard validGeneration && validTTL else { return }
            if !currentGeneration {
                // Its scroll was stopped: the gesture is opened or closed, the page is not moved.
                snapshot.event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: 0.0)
                snapshot.event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: 0.0)
            }
            // 使用 CGEventPostToPid 直接投递到目标进程:
            // 1. 不依赖 proxy → 无生命周期崩溃 (issue #868)
            // 2. 不经过 session event tap 链路重新路由 → 动量阶段光标移动不会
            //    将滚动事件"带到"其他应用, 始终送达原始滚动目标进程
            // 3. 进程内通过 event.location 做窗口级 hit-testing, 路由到正确窗口
            // 合成事件标记 (eventSourceUserData) 作为防御性旁路保留
#if DEBUG
            if let observe = self.postObserverForTests {
                observe(snapshot.event, snapshot.targetPID)
            } else {
                snapshot.event.postToPid(snapshot.targetPID)
            }
            os_unfair_lock_lock(&self.lock)
            self.postedFrames &+= 1
            os_unfair_lock_unlock(&self.lock)
#else
            snapshot.event.postToPid(snapshot.targetPID)
#endif
        }
    }

    /// Whether a frame that opens or closes a gesture still waits on the post queue.
    var hasWaitingGestureFrames: Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return waitingGestureFrames > 0
    }

    /// Returns once every frame handed to the post queue so far has gone out or was dropped.
    ///
    /// `ScrollPoster.stop` waits here for the frames that close the app's gesture ("ended",
    /// "momentum ended"), also inside the scroll tap's callback, so the wait has to be short
    /// and certain. It is: the queue is this context's own and serial, and a block on it
    /// takes this context's lock for a few comparisons (never across a call), then either
    /// drops its frame or hands it to the window server with `postToPid`, a message that
    /// does not wait for the app it is addressed to. No block waits for the main thread, for
    /// ScrollPoster's lock or for another queue. A stop moves the generation on before it
    /// queues its closing frames, so the frames from before it that only move the page are
    /// dropped without a post: what is waited for is the few that open or close a gesture.
    func waitForQueuedFrames() {
#if DEBUG
        waitObserverForTests?()
#endif
        postQueue.sync {}
    }

#if DEBUG
    /// Tests: called each time `waitForQueuedFrames` is asked to wait.
    var waitObserverForTests: (() -> Void)?

    /// Tests: the target of the frames, without an event to copy (frames then go to the
    /// poster's recorder, never to a process).
    func setTargetForTests(_ pid: pid_t) {
        os_unfair_lock_lock(&lock)
        state.targetPID = pid
        os_unfair_lock_unlock(&lock)
    }

    /// Tests: returns once every frame queued so far was posted or dropped.
    func waitForPostQueueForTests() {
        postQueue.sync {}
    }

    func recordSkippedSyntheticEvent() {
        os_unfair_lock_lock(&lock)
        skippedSyntheticEvents &+= 1
        os_unfair_lock_unlock(&lock)
    }

    func diagnosticsSnapshot() -> (postedFrames: UInt64, droppedFramesByGeneration: UInt64, droppedFramesByTTL: UInt64, skippedSyntheticEvents: UInt64, updateSnapshotFailures: UInt64) {
        os_unfair_lock_lock(&lock)
        let snapshot = (
            postedFrames: postedFrames,
            droppedFramesByGeneration: droppedFramesByGeneration,
            droppedFramesByTTL: droppedFramesByTTL,
            skippedSyntheticEvents: skippedSyntheticEvents,
            updateSnapshotFailures: updateSnapshotFailures
        )
        os_unfair_lock_unlock(&lock)
        return snapshot
    }

    func resetDiagnostics() {
        os_unfair_lock_lock(&lock)
        postedFrames = 0
        droppedFramesByGeneration = 0
        droppedFramesByTTL = 0
        skippedSyntheticEvents = 0
        updateSnapshotFailures = 0
        os_unfair_lock_unlock(&lock)
    }
#endif
}
