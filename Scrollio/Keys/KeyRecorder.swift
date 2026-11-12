//
//  KeyRecorder.swift
//  Mos
//  用于录制热键
//
//  Created by Claude on 2025/8/31.
//  Copyright © 2025 Caldis. All rights reserved.
//

import Carbon.HIToolbox
import Cocoa

/// The recording's event tap as the recorder uses it: an `Interceptor` in the app, a double
/// in the tests (a test never installs a real tap).
protocol KeyRecordingTap: AnyObject {
    func stop()
}

extension Interceptor: KeyRecordingTap {}

/// 录制模式
enum KeyRecordingMode {
    /// 组合键模式：需要修饰键+普通键的组合 (用于 ButtonsView)
    case combination
    /// 单键模式：支持单个按键，包括单独的修饰键 (用于 ScrollingView)
    case singleKey
    /// 自适应模式：支持所有输入类型，通过时间间隔判断意图 (用于自定义绑定)
    case adaptive
}

extension KeyRecordingMode {
    /// What the recorder's popover asks for while it waits: what this mode records (see
    /// `InputEvent.isRecordable`, `isRecordableAsSingleKey`, `isRecordableAsAdaptive`).
    var waitingHint: String {
        switch self {
        case .combination:
            // A mouse button other than left and right (no tap of the app sees those two),
            // or a key with a modifier (F-keys also alone).
            return NSLocalizedString("key-recorder-waiting-combination", comment: "Key recorder popover while it waits (Buttons pane +)")
        case .singleKey:
            // Any key, a modifier alone, or a mouse button other than left and right.
            return NSLocalizedString("key-recorder-waiting-single-key", comment: "Key recorder popover while it waits (Scrolling pane hold keys)")
        case .adaptive:
            // A key, a key with modifiers, modifiers alone, or a mouse button but the left.
            return NSLocalizedString("key-recorder-waiting-adaptive", comment: "Key recorder popover while it waits (Keyboard Shortcut… action)")
        }
    }
}

protocol KeyRecorderDelegate: AnyObject {
    /// 录制开始回调
    func onRecordingStarted(_ recorder: KeyRecorder)

    /// 录制完成回调
    func onEventRecorded(_ recorder: KeyRecorder, didRecordEvent event: InputEvent, isDuplicate: Bool)

    /// 录制结束回调
    func onRecordingStopped(_ recorder: KeyRecorder, didRecord: Bool)

    /// 验证录制的事件是否为重复
    func validateRecordedEvent(_ recorder: KeyRecorder, event: InputEvent) -> Bool

    /// Why `validateRecordedEvent` refused `event`, as the recorder's hint shows it; nil:
    /// a duplicate ("Duplicate key").
    func refusalHint(_ recorder: KeyRecorder, event: InputEvent) -> String?

    /// What the recorder's popover asks for while it waits, when the caller takes less than
    /// `mode` does; nil: the mode's own text (`KeyRecordingMode.waitingHint`).
    func waitingHint(_ recorder: KeyRecorder, mode: KeyRecordingMode) -> String?
}

/// 默认实现 (替代 @objc optional 语义)
extension KeyRecorderDelegate {
    func onRecordingStarted(_ recorder: KeyRecorder) {}

    func onRecordingStopped(_ recorder: KeyRecorder, didRecord: Bool) {}

    func validateRecordedEvent(_ recorder: KeyRecorder, event: InputEvent) -> Bool {
        return true
    }

    func refusalHint(_ recorder: KeyRecorder, event: InputEvent) -> String? {
        return nil
    }

    func waitingHint(_ recorder: KeyRecorder, mode: KeyRecordingMode) -> String? {
        return nil
    }
}

class KeyRecorder: NSObject {

    // MARK: - Constants
    static let TIMEOUT: TimeInterval = 10.0
    /// The timeout of this recorder: `TIMEOUT` in the app, shorter in tests.
    var timeout: TimeInterval = KeyRecorder.TIMEOUT
    private static let recordedFeedbackDelay: TimeInterval = 0.7
    private static let duplicateFeedbackDelay: TimeInterval = 1.0
    static let FLAG_CHANGE_NOTI_NAME = NSNotification.Name("RECORD_FLAG_CHANGE_NOTI_NAME")
    static let FINISH_NOTI_NAME = NSNotification.Name("RECORD_FINISH_NOTI_NAME")
    static let CANCEL_NOTI_NAME = NSNotification.Name("RECORD_CANCEL_NOTI_NAME")

    // Delegate
    weak var delegate: KeyRecorderDelegate?
    // Recording
    private var interceptor: KeyRecordingTap?
    private var isRecording = false
    private var isRecorded = false // 是否已经记录过 (每次启动只记录一个按键
    /// `stopRecording` ran; `isRecording` stays true a little longer (the popover's closing
    /// animation). A second stop meanwhile (the timeout, the popover closing) does nothing:
    /// it used to tell the delegate "stopped" and end the Logitech recording twice.
    private var isStopping = false
    private var recordTimeoutTimer: Timer? // 超时保护定时器
    /// Looks once a second whether another app switched secure keyboard entry on or off.
    private var secureInputTimer: Timer?
    private var isShowingSecureInputHint = false
    /// The popover closing by itself and the app going to the background end the recording.
    private var closeObservers: [NSObjectProtocol] = []
    private var invalidKeyPressCount = 0 // 无效按键计数
    private let invalidKeyThreshold = 5 // 显示 ESC 提示的阈值
    private var recordingMode: KeyRecordingMode = .combination // 当前录制模式
    private var hidEventObserver: NSObjectProtocol?  // HID++ 事件监听 (录制期间)
    // Adaptive mode state
    private enum AdaptiveState {
        case idle
        case modifierHeld(modifiers: CGEventFlags)
        case modifierReleasedWaiting(modifiers: CGEventFlags)
        case recorded
    }
    private var adaptiveState: AdaptiveState = .idle
    private var adaptiveConfirmTimer: Timer?  // 300ms post-release timer
    private var holdConfirmTimer: Timer?       // 9.5s fallback timer
    // 同时释放检测 (类似格斗游戏组合键输入缓冲)
    private var previousAdaptiveFlags: CGEventFlags = []
    private var modifierReleaseTimestamps: [(flags: CGEventFlags, time: TimeInterval)] = []
    private var displayDebounceTimer: Timer?  // 释放时延迟更新 preview, 避免闪烁中间态

    // Adaptive mode constants
    private static let ADAPTIVE_CONFIRM_DELAY: TimeInterval = 0.3
    private static let HOLD_CONFIRM_DELAY: TimeInterval = 9.5
    private static let SIMULTANEOUS_RELEASE_WINDOW: TimeInterval = 0.05  // 50ms 内视为同时释放
    private static let modifierFlagsMask: UInt64 =
        CGEventFlags.maskShift.rawValue |
        CGEventFlags.maskControl.rawValue |
        CGEventFlags.maskAlternate.rawValue |
        CGEventFlags.maskCommand.rawValue |
        CGEventFlags.maskSecondaryFn.rawValue

    static func recordingFeedbackDelay(isDuplicate: Bool) -> TimeInterval {
        return isDuplicate ? duplicateFeedbackDelay : recordedFeedbackDelay
    }

    /// What the popover asks for while it waits in `mode`: the delegate's text, or the
    /// mode's own.
    func waitingHint(for mode: KeyRecordingMode) -> String {
        return delegate?.waitingHint(self, mode: mode) ?? mode.waitingHint
    }

    // UI 组件
    private var keyPopover: KeyPopover?
    
    // MARK: - Life Cycle
    deinit {
        // Without the delayed reset: no weak reference can be made to an object that is
        // going away.
        stopRecording(isDeallocating: true)
    }
    
    // MARK: - Event Masks
    // 事件掩码 (支持鼠标和键盘事件，包括修饰键变化)
    private var eventMask: CGEventMask {
        let leftDown = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
        let rightDown = CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
        let otherDown = CGEventMask(1 << CGEventType.otherMouseDown.rawValue)
        let keyDown = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let flagsChanged = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        return leftDown | rightDown | otherDown | keyDown | flagsChanged
    }
    
    // MARK: - Recording Manager
    // 开始记录事件
    /// - Parameters:
    ///   - sourceView: 触发录制的视图，用于显示 Popover
    ///   - mode: 录制模式，默认为组合键模式
    func startRecording(from sourceView: NSView, mode: KeyRecordingMode = .combination) {
        // Guard: 防止重复执行
        guard !isRecording else { return }
        // The event tap first. Without it nothing can be recorded (no Accessibility access):
        // then nothing is shown and no Logitech button is diverted for recording (that divert
        // would never be ended, and every Logitech button would stay swallowed until the app
        // quits). The delegate only hears that nothing was recorded, so a "Press a key" prompt
        // goes away.
        let tap: KeyRecordingTap
        do {
            tap = try makeEventTap(eventMask, Self.recordingCallback)
        } catch {
            // (Interceptor wrote the reason to the app's log.)
            delegate?.onRecordingStopped(self, didRecord: false)
            return
        }
        interceptor = tap
        isRecording = true
        isStopping = false
        recordingMode = mode
        delegate?.onRecordingStarted(self)
        // 确保清理任何存在的录制界面
        keyPopover?.hide()
        keyPopover = nil
        // 立即显示 Popover (不等待 HID++ divert), saying what to press from the start
        let popover = makePopover()
        keyPopover = popover
        popover.show(at: sourceView, waitingHint: waitingHint(for: mode))
        observeClosing(of: popover)
        startSecureInputWatch()
        // 异步 divert 所有 Logitech 按键 (BLE 通信有延迟); not when the recording already ended
        DispatchQueue.main.async { [weak self] in
            guard let self, self.interceptor === tap else { return }
            LogiCenter.shared.beginKeyRecording()
        }
        // 监听回调事件通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRecordedEvent(_:)),
            name: KeyRecorder.FINISH_NOTI_NAME,
            object: nil
        )
        // 监听修饰键变化通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleModifierFlagsChanged(_:)),
            name: KeyRecorder.FLAG_CHANGE_NOTI_NAME,
            object: nil
        )
        // 监听录制取消通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRecordingCancelled(_:)),
            name: KeyRecorder.CANCEL_NOTI_NAME,
            object: nil
        )
        // 监听 HID++ 事件 (如果 LogiCenter 已启动)
        hidEventObserver = NotificationCenter.default.addObserver(
            forName: LogiCenter.buttonEventRelay,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self, self.isRecording, !self.isRecorded else { return }
            guard let inputEvent = notification.userInfo?["event"] as? InputEvent else { return }
            guard inputEvent.phase == .down else { return }
            NotificationCenter.default.post(
                name: KeyRecorder.FINISH_NOTI_NAME,
                object: inputEvent
            )
        }
        // 启动超时保护定时器
        startTimeoutTimer()
    }

    /// The popover of a recording. Tests replace it with one that shows nothing.
    var makePopover: () -> KeyPopover = { KeyPopover() }

    /// Whether another app has secure keyboard entry on (a password field, Terminal's
    /// "Secure Keyboard Entry"): no key reaches any event tap then, so no key can be
    /// recorded. The seam for tests.
    var isSecureInputOn: () -> Bool = { IsSecureEventInputEnabled() }

    // MARK: - Ending by itself

    /// The recording's tap swallows every key and click of the whole Mac, so it must not go
    /// on once nobody can see it. The popover is transient: it closes when the settings
    /// window stops being the key window (a swipe to another Space, an app that comes
    /// forward). The recording used to go on then, up to its 10 s timeout and longer while
    /// modifiers were pressed: keys and clicks were dead in the other app, and the next key
    /// typed there became the hold key.
    private func observeClosing(of popover: KeyPopover) {
        removeCloseObservers()
        closeObservers.append(NotificationCenter.default.addObserver(
            forName: NSPopover.didCloseNotification, object: nil, queue: .main
        ) { [weak self, weak popover] notification in
            guard let self, let popover, self.keyPopover === popover,
                  let closed = notification.object as? NSPopover,
                  Self.isPopover(closed, of: popover) else { return }
            self.stopRecording()
        })
        closeObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.stopRecording()
        })
    }

    /// Whether the system popover that closed is the one `keyPopover` shows: its content
    /// holds that popover's key slot.
    static func isPopover(_ closed: NSPopover, of keyPopover: KeyPopover) -> Bool {
        guard let content = closed.contentViewController?.view,
              let preview = keyPopover.keyPreview else { return false }
        return preview.superview === content
    }

    private func removeCloseObservers() {
        for observer in closeObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        closeObservers = []
    }

    // MARK: - Secure keyboard entry

    private func startSecureInputWatch() {
        stopSecureInputWatch()
        updateSecureInputHint()
        secureInputTimer = CommonModesTimer.scheduled(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateSecureInputHint()
        }
    }

    private func stopSecureInputWatch() {
        secureInputTimer?.invalidate()
        secureInputTimer = nil
        isShowingSecureInputHint = false
    }

    /// Says so while keys cannot arrive, instead of waiting silently; "Press Esc to cancel"
    /// comes back when the other app lets go.
    private func updateSecureInputHint() {
        guard isRecording, !isRecorded, !isStopping else { return }
        let isOn = isSecureInputOn()
        guard isOn != isShowingSecureInputHint else { return }
        isShowingSecureInputHint = isOn
        if isOn {
            keyPopover?.showRefusalHint(NSLocalizedString("key-recorder-secure-input", comment: "Key recorder: another app has secure keyboard entry on"))
        } else {
            keyPopover?.showEscHint()
        }
    }

    /// Creates the recording tap (session level, in front of everything, swallowing what it
    /// records). Tests replace it: a test never installs a real tap.
    var makeEventTap: (_ mask: CGEventMask, _ callback: @escaping CGEventTapCallBack) throws -> KeyRecordingTap = { mask, callback in
        try Interceptor(
            event: mask,
            handleBy: callback,
            listenOn: CGEventTapLocation.cgSessionEventTap,
            placeAt: CGEventTapPlacement.headInsertEventTap,
            for: CGEventTapOptions.defaultTap
        )
    }

    /// Whether a click ends the recording instead of being recorded or refused: a left click
    /// with no modifier, which no mode records. It was swallowed and the popover shook: a
    /// user with only the mouse in hand had no way out but to wait for the timeout.
    static func isCancelClick(type: CGEventType, flags: CGEventFlags) -> Bool {
        return type == .leftMouseDown && flags.rawValue & KeyCode.modifiersMask == 0
    }

    /// The recording tap's callback: hands what it sees to the main thread, swallows it.
    private static let recordingCallback: CGEventTapCallBack = { (proxy, type, event, refcon) in
        // 跳过 Mos 合成事件, 避免 executeCustom 的合成事件干扰录制
        // Skipped means let through: not recorded, and not swallowed either (a key or click
        // Scrollio posts while the recorder is open still reaches the app).
        if event.getIntegerValueField(.eventSourceUserData) == ScrollioEventMarker.syntheticCustom {
            return Unmanaged.passUnretained(event)
        }
        let recordedEvent = event
        switch type {
        case .flagsChanged:
            // 修饰键变化，发送通知 (单键模式下也用于完成录制)
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: KeyRecorder.FLAG_CHANGE_NOTI_NAME,
                    object: recordedEvent
                )
            }
        case .leftMouseDown where KeyRecorder.isCancelClick(type: type, flags: event.flags):
            // Cancels like Esc, and goes on to what was clicked: the click is the user's.
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: KeyRecorder.CANCEL_NOTI_NAME,
                    object: nil
                )
            }
            return Unmanaged.passUnretained(event)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            // 鼠标按键
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: KeyRecorder.FINISH_NOTI_NAME,
                    object: recordedEvent
                )
            }
        case .keyDown:
            // ESC键特殊处理：取消录制
            if recordedEvent.keyCode == KeyCode.escape {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: KeyRecorder.CANCEL_NOTI_NAME,
                        object: nil
                    )
                }
            } else {
                // 普通按键录制
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: KeyRecorder.FINISH_NOTI_NAME,
                        object: recordedEvent
                    )
                }
            }
        default:
            break
        }
        return nil
    }

    // 修饰键变化处理
    @objc private func handleModifierFlagsChanged(_ notification: NSNotification) {
        guard isRecording && !isRecorded else { return }
        let event = notification.object as! CGEvent

        // Adaptive 模式: 使用状态机处理修饰键
        if recordingMode == .adaptive {
            handleAdaptiveFlagsChanged(event)
            return
        }

        // 单键模式：修饰键按下时直接完成录制
        if recordingMode == .singleKey && event.isKeyDown && event.isModifiers {
            NotificationCenter.default.post(
                name: KeyRecorder.FINISH_NOTI_NAME,
                object: event
            )
            return
        }

        // 组合键模式：如果有修饰键被按下，刷新超时定时器给用户更多时间
        let hasActiveModifiers = event.hasModifiers
        if hasActiveModifiers {
            startTimeoutTimer()
        }
        // 实时更新录制界面显示当前已按下的修饰键
        keyPopover?.keyPreview
            .updateForRecording(from: event)
    }
    // MARK: - Adaptive Mode

    private func handleAdaptiveFlagsChanged(_ event: CGEvent) {
        let hasActiveModifiers = event.hasModifiers

        // 检测本次释放了哪些修饰键 (previous & ~current)
        let currentBits = event.flags.rawValue & Self.modifierFlagsMask
        let previousBits = previousAdaptiveFlags.rawValue & Self.modifierFlagsMask
        let releasedBits = previousBits & ~currentBits
        if releasedBits != 0 {
            modifierReleaseTimestamps.append((
                flags: CGEventFlags(rawValue: releasedBits),
                time: CACurrentMediaTime()
            ))
        }
        previousAdaptiveFlags = event.flags

        if hasActiveModifiers {
            // 修饰键仍有按住
            cancelAdaptiveConfirmTimer()
            startHoldConfirmTimer()
            startTimeoutTimer()
            // 新手势开始时清空释放历史
            switch adaptiveState {
            case .idle, .modifierReleasedWaiting, .recorded:
                modifierReleaseTimestamps.removeAll()
            case .modifierHeld:
                break
            }
            adaptiveState = .modifierHeld(modifiers: event.flags)

            let isAdding = (currentBits & ~previousBits) != 0
            if isAdding {
                // 新增修饰键: 取消 debounce, 清空释放历史 (用户改变了意图), 立即更新显示
                cancelDisplayDebounceTimer()
                modifierReleaseTimestamps.removeAll()
                keyPopover?.keyPreview.updateForRecording(from: event)
            } else {
                // 释放修饰键但仍有按住: 延迟更新, 避免同时释放时闪烁中间态
                scheduleDisplayDebounce(event: event)
            }
        } else {
            // 所有修饰键松开
            cancelDisplayDebounceTimer() // 不再需要延迟更新, 最终结果由 confirm 流程显示
            switch adaptiveState {
            case .modifierHeld:
                cancelHoldConfirmTimer()
                // 从释放时间戳中计算同时释放的修饰键组合
                let simultaneousModifiers = computeSimultaneousReleaseModifiers()
                modifierReleaseTimestamps.removeAll()
                adaptiveState = .modifierReleasedWaiting(modifiers: simultaneousModifiers)
                startAdaptiveConfirmTimer(modifiers: simultaneousModifiers)
            default:
                break
            }
        }
    }

    /// 从释放时间戳中提取最后一组同时释放的修饰键
    /// 类似格斗游戏组合键检测: 50ms 窗口内的释放视为同时操作
    private func computeSimultaneousReleaseModifiers() -> CGEventFlags {
        guard let lastRelease = modifierReleaseTimestamps.last else { return [] }
        var combinedBits: UInt64 = 0
        for release in modifierReleaseTimestamps.reversed() {
            if lastRelease.time - release.time <= Self.SIMULTANEOUS_RELEASE_WINDOW {
                combinedBits |= release.flags.rawValue
            } else {
                break
            }
        }
        return CGEventFlags(rawValue: combinedBits)
    }

    /// Adaptive 模式下的事件完成处理 (非修饰键/组合键录入时调用)
    private func handleAdaptiveRecordedEvent(_ event: InputEvent) {
        cancelAdaptiveConfirmTimer()
        cancelHoldConfirmTimer()
        adaptiveState = .recorded
    }

    /// 确认录制当前修饰键组合 (300ms 定时器或 9.5s hold 定时器触发)
    private func confirmAdaptiveModifiers(_ modifiers: CGEventFlags) {
        guard isRecording && !isRecorded else { return }
        cancelAdaptiveConfirmTimer()
        cancelHoldConfirmTimer()
        adaptiveState = .recorded

        // 构造 InputEvent 并通过 FINISH 通知完成录制
        let inputEvent = InputEvent(
            type: .keyboard,
            code: extractPrimaryModifierCode(from: modifiers),
            modifiers: modifiers,
            phase: .down,
            source: .hidPP,
            device: nil
        )
        NotificationCenter.default.post(
            name: KeyRecorder.FINISH_NOTI_NAME,
            object: inputEvent
        )
    }

    /// 从 flags 中提取主要修饰键的 keyCode
    private func extractPrimaryModifierCode(from flags: CGEventFlags) -> UInt16 {
        if flags.rawValue & CGEventFlags.maskCommand.rawValue != 0 { return KeyCode.commandL }
        if flags.rawValue & CGEventFlags.maskShift.rawValue != 0 { return KeyCode.shiftL }
        if flags.rawValue & CGEventFlags.maskAlternate.rawValue != 0 { return KeyCode.optionL }
        if flags.rawValue & CGEventFlags.maskControl.rawValue != 0 { return KeyCode.controlL }
        if flags.rawValue & CGEventFlags.maskSecondaryFn.rawValue != 0 { return KeyCode.fnL }
        return KeyCode.commandL
    }

    // MARK: - Adaptive Timers

    private func startAdaptiveConfirmTimer(modifiers: CGEventFlags) {
        cancelAdaptiveConfirmTimer()
        // In the common run-loop modes, like every timer of the recorder: a timer in the
        // default mode waits while a menu is open or a control tracks, and these end a
        // recording whose tap swallows every key and click (CommonModesTimer).
        adaptiveConfirmTimer = CommonModesTimer.scheduled(withTimeInterval: KeyRecorder.ADAPTIVE_CONFIRM_DELAY, repeats: false) { [weak self] _ in
            self?.confirmAdaptiveModifiers(modifiers)
        }
    }

    private func cancelAdaptiveConfirmTimer() {
        adaptiveConfirmTimer?.invalidate()
        adaptiveConfirmTimer = nil
    }

    private func startHoldConfirmTimer() {
        cancelHoldConfirmTimer()
        holdConfirmTimer = CommonModesTimer.scheduled(withTimeInterval: KeyRecorder.HOLD_CONFIRM_DELAY, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if case .modifierHeld(let modifiers) = self.adaptiveState {
                self.confirmAdaptiveModifiers(modifiers)
            }
        }
    }

    private func cancelHoldConfirmTimer() {
        holdConfirmTimer?.invalidate()
        holdConfirmTimer = nil
    }

    // MARK: - Display Debounce (防止同时释放修饰键时 preview 闪烁中间态)

    private func scheduleDisplayDebounce(event: CGEvent) {
        cancelDisplayDebounceTimer()
        // 保留 event 的 flags 用于延迟更新 (CGEvent 是引用类型, 不需要拷贝 flags)
        let flags = event.flags
        displayDebounceTimer = CommonModesTimer.scheduled(withTimeInterval: Self.SIMULTANEOUS_RELEASE_WINDOW, repeats: false) { [weak self] _ in
            guard let self = self, self.isRecording, !self.isRecorded else { return }
            // 窗口期内没有更多释放事件, 说明这是一次有意的释放, 更新显示
            self.keyPopover?.keyPreview.updateForRecording(modifiers: flags)
        }
    }

    private func cancelDisplayDebounceTimer() {
        displayDebounceTimer?.invalidate()
        displayDebounceTimer = nil
    }

    // 录制取消处理
    @objc private func handleRecordingCancelled(_ notification: NSNotification) {
        guard isRecording && !isRecorded else { return }
        stopRecording()
    }
    @objc private func handleRecordedEvent(_ notification: NSNotification) {
        guard isRecording, !isStopping else { return }

        // 统一转换为 InputEvent
        // 注意: 先检查 InputEvent (value type), 再检查 CGEvent (CoreFoundation type)
        // CGEvent 的 as? 对 Any 总是成功, 所以必须后检查
        let inputEvent: InputEvent
        if let hidEvent = notification.object as? InputEvent {
            inputEvent = hidEvent
        } else if let cgEvent = notification.object, CFGetTypeID(cgEvent as CFTypeRef) == CGEvent.typeID {
            inputEvent = InputEvent(fromCGEvent: cgEvent as! CGEvent)
        } else {
            return
        }

        // Adaptive 模式: 清理定时器和状态
        if recordingMode == .adaptive {
            handleAdaptiveRecordedEvent(inputEvent)
        }

        // 检查事件有效性 (根据录制模式)
        let isValid: Bool
        switch recordingMode {
        case .singleKey:
            isValid = inputEvent.isRecordableAsSingleKey
        case .combination:
            isValid = inputEvent.isRecordable
        case .adaptive:
            isValid = inputEvent.isRecordableAsAdaptive
        }
        guard isValid else {
            keyPopover?.keyPreview.shakeWarning()
            invalidKeyPressCount += 1
            if let reason = Self.refusalReason(for: inputEvent, mode: recordingMode) {
                // Why, when "Press Esc to cancel" would not tell: these two buttons never work.
                keyPopover?.showRefusalHint(reason)
            } else if invalidKeyPressCount >= invalidKeyThreshold {
                keyPopover?.showEscHint()
            }
            return
        }

        guard !isRecorded else { return }
        isRecorded = true
        // The recording is over: only the feedback is still shown. The timeout kept running
        // and, for a key recorded in its last moments, ended the recording a second time.
        cancelTimeoutTimer()
        stopSecureInputWatch()

        let isNew = self.delegate?.validateRecordedEvent(self, event: inputEvent) ?? true
        let isDuplicate = !isNew
        let status: KeyPreview.Status = isNew ? .recorded : .duplicate

        keyPopover?.keyPreview
            .update(from: inputEvent.displayComponents, status: status)
        if isDuplicate {
            keyPopover?.showRefusalHint(self.delegate?.refusalHint(self, event: inputEvent))
        }
        self.delegate?.onEventRecorded(self, didRecordEvent: inputEvent, isDuplicate: isDuplicate)

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.recordingFeedbackDelay(isDuplicate: isDuplicate)) { [weak self] in
            self?.stopRecording()
        }
    }

    /// Why an event the mode does not record is refused, when there is a reason worth
    /// saying: the left and right buttons can never be a trigger (no event tap of the app
    /// sees them), with or without a modifier. nil: an ordinary wrong key.
    static func refusalReason(for event: InputEvent, mode: KeyRecordingMode) -> String? {
        guard event.type == .mouse, KeyCode.mouseMainKeys.contains(event.code) else { return nil }
        switch mode {
        case .combination, .singleKey:
            return NSLocalizedString("key-recorder-left-right-refused", comment: "Key recorder: the left and right buttons cannot be a trigger")
        case .adaptive:
            // What a button sends: the right button can be sent, the left cannot.
            return event.code == 0
                ? NSLocalizedString("key-recorder-left-refused", comment: "Key recorder: the left button cannot be what a button sends")
                : nil
        }
    }

    // 停止记录
    func stopRecording() {
        stopRecording(isDeallocating: false)
    }

    private func stopRecording(isDeallocating: Bool) {
        // Guard: 需要 Recording 才进行后续处理
        guard isRecording, !isStopping else { return }
        isStopping = true
        let didRecord = isRecorded
        removeCloseObservers()
        stopSecureInputWatch()
        // 隐藏录制界面
        keyPopover?.hide()
        keyPopover = nil
        // 取消超时定时器
        cancelTimeoutTimer()
        // 清理 adaptive 状态
        cancelAdaptiveConfirmTimer()
        cancelHoldConfirmTimer()
        cancelDisplayDebounceTimer()
        adaptiveState = .idle
        previousAdaptiveFlags = []
        modifierReleaseTimestamps.removeAll()
        // 取消通知和监听
        interceptor?.stop()
        interceptor = nil
        NotificationCenter.default.removeObserver(self, name: KeyRecorder.FINISH_NOTI_NAME, object: nil)
        NotificationCenter.default.removeObserver(self, name: KeyRecorder.FLAG_CHANGE_NOTI_NAME, object: nil)
        NotificationCenter.default.removeObserver(self, name: KeyRecorder.CANCEL_NOTI_NAME, object: nil)
        if let observer = hidEventObserver {
            NotificationCenter.default.removeObserver(observer)
            hidEventObserver = nil
        }
        delegate?.onRecordingStopped(self, didRecord: didRecord)
        // 录制结束: 恢复到只 divert 有绑定的按键
        LogiCenter.shared.endKeyRecording()
        // 重置状态 (添加延迟确保 Popover 结束动画完成, 避免多个 popover 重复出现导致卡住)
        guard !isDeallocating else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.restartDelay) { [weak self] in
            self?.isRecording = false
            self?.isRecorded = false
            self?.isStopping = false
            self?.invalidKeyPressCount = 0
        }
    }

    /// After a stop, how long until a new recording can start.
    static let restartDelay: TimeInterval = 0.5
    
    // MARK: - Timeout Protection
    private func startTimeoutTimer() {
        cancelTimeoutTimer()
        recordTimeoutTimer = CommonModesTimer.scheduled(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            self?.stopRecording()
        }
    }
    private func cancelTimeoutTimer() {
        recordTimeoutTimer?.invalidate()
        recordTimeoutTimer = nil
    }
}
