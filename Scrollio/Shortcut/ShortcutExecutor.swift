//
//  ShortcutExecutor.swift
//  Mos
//  系统快捷键执行器 - 发送快捷键事件
//  Created by Claude on 2025/8/10.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

enum MouseButtonActionKind {
    case left
    case right
    case middle
    case back
    case forward

    init?(shortcutIdentifier: String) {
        switch shortcutIdentifier {
        case "mouseLeftClick":
            self = .left
        case "mouseRightClick":
            self = .right
        case "mouseMiddleClick":
            self = .middle
        case "mouseBackClick":
            self = .back
        case "mouseForwardClick":
            self = .forward
        default:
            return nil
        }
    }

    init?(buttonNumber: UInt16) {
        switch buttonNumber {
        case 0:
            self = .left
        case 1:
            self = .right
        case 2:
            self = .middle
        case 3:
            self = .back
        case 4:
            self = .forward
        default:
            return nil
        }
    }
}

enum ScrollActionKind {
    case dash
    case toggle
    case block

    init?(shortcutIdentifier: String) {
        switch shortcutIdentifier {
        case "scrollDash":
            self = .dash
        case "scrollToggle":
            self = .toggle
        case "scrollBlock":
            self = .block
        default:
            return nil
        }
    }

    var role: ScrollRole {
        switch self {
        case .dash:
            return .dash
        case .toggle:
            return .toggle
        case .block:
            return .block
        }
    }
}

enum ResolvedAction {
    case customKey(code: UInt16, modifiers: UInt64)
    case customMouseButton(buttonNumber: UInt16, modifiers: UInt64)
    case mouseButton(kind: MouseButtonActionKind)
    case scrollAction(role: ScrollRole)
    case systemShortcut(identifier: String)
    case logiAction(identifier: String)
    case openTarget(payload: OpenTargetPayload)

    var executionMode: ActionExecutionMode {
        switch self {
        case .customKey, .customMouseButton, .mouseButton, .scrollAction:
            return .stateful
        case .logiAction, .openTarget:
            return .trigger
        case .systemShortcut(let identifier):
            return SystemShortcut.getShortcut(named: identifier)?.executionMode ?? .trigger
        }
    }
}


struct ActionExecutionResult {
    let mouseSessionID: UUID?

    static let none = ActionExecutionResult(mouseSessionID: nil)
}

struct MouseTapReplayContext {
    let buttonNumber: Int64
    let location: CGPoint?
    let modifiers: CGEventFlags
}

/// One start of a bound script: what runs, with what, where.
///
/// The script is started as a program of its own, not as Scrollio's child in the eyes of
/// macOS's privacy checks: `posix_spawn` with the responsibility disclaimed
/// (`responsibility_spawnattrs_setdisclaim`, the function debuggers and browsers use to
/// start other people's programs). A child started the plain way has Scrollio as its
/// "responsible process": it could post and read input events with the Accessibility access
/// the user gave Scrollio, so anything able to write a binding into the settings had a way
/// into that access; and a script that sent Apple events failed without a prompt, because
/// Scrollio has no entitlement for them. Disclaimed, macOS judges the script by itself (its
/// interpreter): it has none of Scrollio's permissions and is asked for its own.
///
/// The function is not in a public header, so it is looked up at run time; where it is
/// missing or refuses, the script is started as a plain child, as before, and the log says so.
struct ScriptLaunch: Equatable {
    var executable: URL
    var arguments: [String]
    var environment: [String: String]
    var workingDirectory: URL

    /// How the script ended: its exit status (or the signal's number), and whether a signal
    /// ended it.
    typealias Ended = (_ status: Int32, _ endedBySignal: Bool) -> Void

    /// A script that was started.
    struct Started: Equatable {
        var processIdentifier: pid_t
        /// macOS judges it by itself; false: started as a plain child of Scrollio.
        var isDisclaimed: Bool
    }

    /// Starts it (no shell: the arguments are passed as they are, so quotes and spaces in
    /// them cannot run anything else). Its output is discarded. `ended` is called on a
    /// background queue.
    @discardableResult
    func start(ended: @escaping Ended) throws -> Started {
        if let setDisclaim = Self.setDisclaim {
            if let pid = try startDisclaimed(setDisclaim, ended: ended) {
                return Started(processIdentifier: pid, isDisclaimed: true)
            }
        }
        Self.noteThatScriptsAreNotDisclaimed()
        return Started(processIdentifier: try startAsChild(ended: ended), isDisclaimed: false)
    }

    // MARK: Disclaimed

    typealias SetDisclaim = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, Int32) -> Int32

    /// `responsibility_spawnattrs_setdisclaim` of the system library; nil where it is missing.
    static let setDisclaim: SetDisclaim? = {
        // RTLD_DEFAULT
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_spawnattrs_setdisclaim") else {
            return nil
        }
        return unsafeBitCast(symbol, to: SetDisclaim.self)
    }()

    /// - Returns: the process id, or nil when the responsibility could not be disclaimed
    ///   (the caller then starts a plain child).
    /// - Throws: when the script itself could not be started.
    func startDisclaimed(_ setDisclaim: SetDisclaim, ended: @escaping Ended) throws -> pid_t? {
        var attributes: posix_spawnattr_t?
        guard posix_spawnattr_init(&attributes) == 0 else { return nil }
        defer { posix_spawnattr_destroy(&attributes) }
        guard setDisclaim(&attributes, 1) == 0 else { return nil }
        // Default signal handling, no signal blocked, and none of the app's open files.
        var allSignals = sigset_t()
        sigfillset(&allSignals)
        posix_spawnattr_setsigdefault(&attributes, &allSignals)
        var noSignals = sigset_t()
        sigemptyset(&noSignals)
        posix_spawnattr_setsigmask(&attributes, &noSignals)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_CLOEXEC_DEFAULT))

        var fileActions: posix_spawn_file_actions_t?
        guard posix_spawn_file_actions_init(&fileActions) == 0 else { return nil }
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        posix_spawn_file_actions_addopen(&fileActions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&fileActions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addopen(&fileActions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)
        if #available(macOS 26.0, *) {
            posix_spawn_file_actions_addchdir(&fileActions, workingDirectory.path)
        } else {
            posix_spawn_file_actions_addchdir_np(&fileActions, workingDirectory.path)
        }

        var argv: [UnsafeMutablePointer<CChar>?] = ([executable.path] + arguments).map { strdup($0) }
        argv.append(nil)
        var envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup("\($0.key)=\($0.value)") }
        envp.append(nil)
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }

        var pid: pid_t = 0
        let result = posix_spawn(&pid, executable.path, &fileActions, &attributes, argv, envp)
        guard result == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(result))
        }
        Self.watchExit(of: pid, ended: ended)
        return pid
    }

    // MARK: The end of a disclaimed script

    private static let exitQueue = DispatchQueue(label: "com.nikklemenc.Scrollio.scriptExit", qos: .utility)
    /// One source per running script, until it ended. Only touched on `exitQueue`.
    private static var exitSources: [pid_t: DispatchSourceProcess] = [:]

    private static func watchExit(of pid: pid_t, ended: @escaping Ended) {
        exitQueue.async {
            let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: exitQueue)
            exitSources[pid] = source
            source.setEventHandler {
                // It is ending: the wait returns at once.
                collectExit(of: pid, waiting: true, ended: ended)
            }
            source.resume()
            // Already over before anyone watched (a script that fails at once).
            collectExit(of: pid, waiting: false, ended: ended)
        }
    }

    /// Collects the script's exit status once (so no dead process is left behind) and
    /// reports it. On `exitQueue`.
    private static func collectExit(of pid: pid_t, waiting: Bool, ended: Ended) {
        guard let source = exitSources[pid] else { return }
        var status: Int32 = 0
        var result: pid_t
        repeat {
            result = waitpid(pid, &status, waiting ? 0 : WNOHANG)
        } while result == -1 && errno == EINTR
        // 0: still running (only when not waiting). -1: nothing to collect any more.
        guard result != 0 else { return }
        source.cancel()
        exitSources[pid] = nil
        guard result == pid else { return }
        let outcome = outcome(ofWaitStatus: status)
        ended(outcome.status, outcome.endedBySignal)
    }

    /// What `waitpid` says about how a process ended: its exit status, or the number of the
    /// signal that ended it. Pure.
    static func outcome(ofWaitStatus status: Int32) -> (status: Int32, endedBySignal: Bool) {
        let signal = status & 0x7f
        if signal == 0 {
            return ((status >> 8) & 0xff, false)
        }
        return (signal, true)
    }

    // MARK: A plain child (the fallback)

    private static var didNoteNotDisclaimed = false
    private static let noteLock = NSLock()

    /// Once per run.
    private static func noteThatScriptsAreNotDisclaimed() {
        noteLock.lock()
        let first = !didNoteNotDisclaimed
        didNoteNotDisclaimed = true
        noteLock.unlock()
        guard first else { return }
        AppSystemLog.problem("Scripts: this macOS cannot start a script as a program of its own "
            + "(responsibility_spawnattrs_setdisclaim is missing or refused); bound scripts run as "
            + "Scrollio's child, with Scrollio's permissions")
    }

    /// Starts it as a child process of Scrollio, which macOS then holds responsible for it.
    func startAsChild(ended: @escaping Ended) throws -> pid_t {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = workingDirectory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { process in
            ended(process.terminationStatus, process.terminationReason == .uncaughtSignal)
        }
        try process.run()
        return process.processIdentifier
    }
}

class ShortcutExecutor {

    // 单例
    static let shared = ShortcutExecutor()
    init() {}

    /// Mos 滚动动作端口 (启动期注入 ScrollCore.shared)。weak: 端口为永生单例, 避免强引用环。
    weak var scrollActionPort: ScrollActionPort?

    /// 修饰键 provider (启动期注入 InputProcessor.shared)。weak: provider 为永生单例。
    weak var modifierFlagsProvider: ModifierFlagsProviding?

    /// Runs one of the "Logitech Mouse" actions by its identifier (`logiSmartShiftToggle`,
    /// `logiHost2`, …): `LogiCenter` in the app. The seam for tests.
    var logiActionPerformer: (String) -> Void = { LogiCenter.shared.executeAction(named: $0) }

    /// Starts a bound script and calls `ended` (on any queue) when it ended: the seam for
    /// tests, `ScriptLaunch.start` in the app.
    var scriptLauncher: (ScriptLaunch, @escaping ScriptLaunch.Ended) throws -> Void = { launch, ended in
        try launch.start(ended: ended)
    }

    /// Tells the user that a Spaces action did nothing because its shortcut is switched off
    /// in System Settings (the action's name is passed). Tests replace it.
    var switchedOffNotice: (String) -> Void = { name in
        Toast.show(
            String(format: NSLocalizedString("toast-system-shortcut-off", comment: "Toast: a Spaces action needs its System Settings shortcut"), name),
            style: .warning,
            duration: 8.0
        )
    }

    /// Posts one event into the Mac's event stream: every key, modifier and click the
    /// executor sends goes through here. Under XCTest it does nothing, whatever a test
    /// forgets to replace: the tests used to post real modifier events (a held Shift or
    /// Option for the time of a test) whenever the debug app had Accessibility access.
    var post: (CGEvent) -> Void = AppRuntime.isRunningXCTest
        ? { _ in }
        : { $0.post(tap: .cghidEventTap) }

    private var testingMouseEventObserver: ((CGEvent) -> Void)?
    private var testingKeyboardShortcutObserver: ((CGKeyCode, UInt64, Bool) -> Void)?

    /// 快速识别 Mos Scroll 三个 stateful 动作, 供事件热路径避免完整 action 解析。
    static func isScrollActionIdentifier(_ shortcutName: String) -> Bool {
        ScrollActionKind(shortcutIdentifier: shortcutName) != nil
    }

    // MARK: - 执行快捷键 (统一接口)

    /// 执行快捷键 (底层接口, 使用原始flags)
    /// - Parameters:
    ///   - code: 虚拟键码
    ///   - flags: 修饰键flags (UInt64原始值)
    ///   - preserveFlagsOnKeyUp: KeyUp 时是否保留修饰键 flags (默认 false)
    func execute(code: CGKeyCode, flags: UInt64, preserveFlagsOnKeyUp: Bool = false) {
        if let testingKeyboardShortcutObserver {
            testingKeyboardShortcutObserver(code, flags, preserveFlagsOnKeyUp)
            return
        }

        // 创建事件源
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return
        }

        // 发送按键按下事件
        if let keyDown = Self.shortcutKeyEvent(code: code, flags: flags, keyDown: true,
                                               preserveFlagsOnKeyUp: preserveFlagsOnKeyUp, source: source) {
            post(keyDown)
        }

        // 发送按键抬起事件
        if let keyUp = Self.shortcutKeyEvent(code: code, flags: flags, keyDown: false,
                                             preserveFlagsOnKeyUp: preserveFlagsOnKeyUp, source: source) {
            post(keyUp)
        }
    }

    /// The key down or key up of a shortcut, marked as Scrollio's own (`ScrollioEventMarker`) like
    /// every other key and click it posts. Unmarked they came back through the app's own
    /// taps: a keyboard trigger bound to the shortcut it is itself ran again in a loop, and
    /// the button tap added held virtual modifiers to them.
    static func shortcutKeyEvent(code: CGKeyCode, flags: UInt64, keyDown: Bool,
                                 preserveFlagsOnKeyUp: Bool, source: CGEventSource?) -> CGEvent? {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: keyDown) else {
            return nil
        }
        if keyDown || preserveFlagsOnKeyUp {
            event.flags = CGEventFlags(rawValue: flags)
        }
        event.setIntegerValueField(.eventSourceUserData, value: ScrollioEventMarker.syntheticCustom)
        return event
    }

    /// 执行系统快捷键 (从SystemShortcut.Shortcut对象)
    /// A letter shortcut (⌘A, ⇧⌘Z) is sent with the key that types its letter on the keyboard
    /// layout in use, not with the US key: apps match a shortcut by the character, and on a
    /// French keyboard the US key of "Select All" is ⌘Q (`KeyboardLayoutKeys`).
    /// - Parameter shortcut: SystemShortcut.Shortcut对象
    func execute(_ shortcut: SystemShortcut.Shortcut) {
        execute(
            code: KeyboardLayoutKeys.shared.keyCode(for: shortcut),
            flags: UInt64(shortcut.modifiers.rawValue),
            preserveFlagsOnKeyUp: shortcut.preserveFlagsOnKeyUp
        )
    }

    /// 执行系统快捷键 (从名称解析, 支持动态读取系统配置)
    /// - Parameters:
    ///   - shortcutName: 快捷键名称
    ///   - phase: 事件阶段 (down/up), 默认 .down
    ///   - binding: 可选的 ButtonBinding (用于访问预解析的 custom cache)
    func execute(named shortcutName: String, phase: InputPhase = .down, binding: ButtonBinding? = nil, inputModifiers: CGEventFlags? = nil) {
        guard let action = resolveAction(named: shortcutName, binding: binding) else { return }
        _ = execute(action: action, phase: phase, inputModifiers: inputModifiers)
    }

    @discardableResult
    func execute(
        action: ResolvedAction,
        phase: InputPhase,
        mouseSessionID: UUID? = nil,
        inputModifiers: CGEventFlags? = nil
    ) -> ActionExecutionResult {
        switch action {
        case .customKey(let code, let modifiers):
            executeCustom(code: code, modifiers: modifiers, phase: phase)
            return .none
        case .customMouseButton(let buttonNumber, let modifiers):
            return ActionExecutionResult(
                mouseSessionID: executeCustomMouseButton(
                    buttonNumber: buttonNumber,
                    modifiers: modifiers,
                    phase: phase,
                    mouseSessionID: mouseSessionID
                )
            )
        case .mouseButton(let kind):
            return ActionExecutionResult(
                mouseSessionID: executeMouseButton(
                    kind,
                    phase: phase,
                    mouseSessionID: mouseSessionID,
                    inputModifiers: inputModifiers
                )
            )
        case .scrollAction(let role):
            scrollActionPort?.handleScrollAction(role: role, isDown: phase == .down)
            return .none
        case .logiAction(let identifier):
            guard phase == .down else { return .none }
            executeLogiAction(identifier)
            return .none
        case .openTarget(let payload):
            guard phase == .down else { return .none }
            executeOpenTarget(payload)
            return .none
        case .systemShortcut(let identifier):
            guard phase == .down else { return .none }
            executeResolvedSystemShortcut(named: identifier)
            return .none
        }
    }

    func resolveAction(named shortcutName: String, binding: ButtonBinding? = nil) -> ResolvedAction? {
        // 优先: 结构化 payload (在 cachedCustomCode 之前判定, 避免命名冲突)
        if let payload = binding?.openTarget,
           shortcutName == ButtonBinding.openTargetSentinel {
            return .openTarget(payload: payload)
        }
        if let code = binding?.cachedCustomCode {
            let modifiers = binding?.cachedCustomModifiers ?? 0
            switch binding?.cachedCustomType ?? .keyboard {
            case .keyboard:
                return .customKey(code: code, modifiers: modifiers)
            case .mouse:
                if let kind = MouseButtonActionKind(buttonNumber: code), modifiers == 0 {
                    return .mouseButton(kind: kind)
                }
                if let nativeCode = LogiStandardMouseButtonAlias.nativeButtonCode(forScrollioCode: code),
                   let kind = MouseButtonActionKind(buttonNumber: nativeCode),
                   modifiers == 0 {
                    return .mouseButton(kind: kind)
                }
                return .customMouseButton(buttonNumber: code, modifiers: modifiers)
            }
        }
        if let code = SystemShortcut.predefinedModifierCode(for: shortcutName) {
            return .customKey(code: code, modifiers: 0)
        }
        if let kind = MouseButtonActionKind(shortcutIdentifier: shortcutName) {
            return .mouseButton(kind: kind)
        }
        if let scrollAction = ScrollActionKind(shortcutIdentifier: shortcutName) {
            return .scrollAction(role: scrollAction.role)
        }
        // Gesture navigation is driven by InputProcessor while its trigger is held;
        // it is a menu action, not a synthetic keyboard shortcut.
        if shortcutName == SystemShortcut.mouseGestureNavigation.identifier {
            return nil
        }
        // An action this version does not know (settings of a newer version, a renamed
        // action) is no action: it used to count as a shortcut, which took the button (the
        // press and the release were swallowed) and sent nothing.
        guard SystemShortcut.getShortcut(named: shortcutName) != nil else { return nil }
        if shortcutName.hasPrefix("logi") {
            return .logiAction(identifier: shortcutName)
        }
        return .systemShortcut(identifier: shortcutName)
    }

    private func executeResolvedSystemShortcut(named shortcutName: String) {
        // A retired action ("Shut Down…") sends nothing.
        guard !SystemShortcut.isRetired(shortcutName) else { return }
        // "Move left a space" and "Move right a space" work through the user's shortcut for
        // them. Switched off in System Settings, the standard keys (⌃← / ⌃→) used to be sent
        // anyway: no Space changed and the app in front got them (the text cursor jumped a
        // word). Nothing is sent now, and a toast says where to switch the shortcut on.
        if SystemShortcut.isSwitchedOffInSystemSettings(shortcutName) {
            let name = SystemShortcut.getShortcut(named: shortcutName)?.localizedName ?? shortcutName
            switchedOffNotice(name)
            return
        }
        // 优先使用系统实际配置 (对于Mission Control相关快捷键)
        if let resolved = SystemShortcut.resolveSystemShortcut(shortcutName) {
            execute(code: resolved.code, flags: resolved.modifiers)
            return
        }

        // Fallback到内置快捷键定义
        guard let shortcut = SystemShortcut.getShortcut(named: shortcutName) else {
            return
        }

        execute(shortcut)
    }

    // MARK: - Custom Binding Execution

    /// 执行自定义绑定 (1:1 down/up 映射)
    private func executeCustom(code: UInt16, modifiers: UInt64, phase: InputPhase) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let isModifierKey = KeyCode.modifierKeys.contains(code)

        if isModifierKey {
            // 修饰键: 使用 flagsChanged 事件类型
            guard let event = CGEvent(source: source) else { return }
            event.type = .flagsChanged
            event.setIntegerValueField(.keyboardEventKeycode, value: Int64(code))
            if phase == .down {
                // 按下: 设置所有修饰键 flags (自身 + 附加修饰键)
                let keyMask = KeyCode.getKeyMask(code)
                event.flags = CGEventFlags(rawValue: modifiers | keyMask.rawValue)
            } else {
                // 松开: 清除所有 flags (释放全部修饰键)
                event.flags = CGEventFlags(rawValue: 0)
            }
            // 标记为 Mos 合成事件, 避免被 ScrollCore/ButtonCore/KeyRecorder 误处理
            event.setIntegerValueField(.eventSourceUserData, value: ScrollioEventMarker.syntheticCustom)
            post(event)
        } else {
            // 普通键: 使用 keyDown/keyUp
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: phase == .down) else { return }
            event.flags = CGEventFlags(rawValue: modifiers)
            // 标记为 Mos 合成事件
            event.setIntegerValueField(.eventSourceUserData, value: ScrollioEventMarker.syntheticCustom)
            post(event)
        }
    }

    private func executeCustomMouseButton(
        buttonNumber: UInt16,
        modifiers: UInt64,
        phase: InputPhase,
        mouseSessionID: UUID?
    ) -> UUID? {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return nil }
        let number = Int64(buttonNumber)
        let spec = mouseEventSpec(buttonNumber: number, phase: phase)
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: spec.type,
            mouseCursorPosition: currentMouseLocationForCGEvent(),
            mouseButton: spec.button
        ) else {
            return nil
        }

        let createdSessionID: UUID?
        if phase == .down {
            createdSessionID = MouseInteractionSessionController.shared.beginSession(target: syntheticTarget(buttonNumber: number))
        } else {
            createdSessionID = nil
            if let mouseSessionID {
                MouseInteractionSessionController.shared.endSession(id: mouseSessionID)
            } else {
                MouseInteractionSessionController.shared.clearAllSessions()
            }
        }

        if let buttonNumber = spec.buttonNumber {
            event.setIntegerValueField(.mouseEventButtonNumber, value: buttonNumber)
        }
        event.flags = CGEventFlags(rawValue: modifiers)
        event.setIntegerValueField(.eventSourceUserData, value: ScrollioEventMarker.syntheticCustom)
        notifyOrPostMouseEvent(event)
        return createdSessionID
    }

    // MARK: - Mouse Actions

    /// 执行鼠标按键动作 (1:1 down/up 映射)
    private func executeMouseButton(
        _ kind: MouseButtonActionKind,
        phase: InputPhase,
        mouseSessionID: UUID?,
        inputModifiers: CGEventFlags?
    ) -> UUID? {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return nil }
        let point = currentMouseLocationForCGEvent()
        let spec = mouseEventSpec(for: kind, phase: phase)
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: spec.type,
            mouseCursorPosition: point,
            mouseButton: spec.button
        ) else {
            return nil
        }

        let createdSessionID: UUID?
        if phase == .down {
            createdSessionID = MouseInteractionSessionController.shared.beginSession(target: syntheticTarget(for: kind))
        } else {
            createdSessionID = nil
            if let mouseSessionID {
                MouseInteractionSessionController.shared.endSession(id: mouseSessionID)
            } else {
                MouseInteractionSessionController.shared.clearAllSessions()
            }
        }

        if let buttonNumber = spec.buttonNumber {
            event.setIntegerValueField(.mouseEventButtonNumber, value: buttonNumber)
        }
        event.flags = modifierFlagsProvider?.combinedModifierFlags(physicalModifiers: inputModifiers)
            ?? inputModifiers
            ?? CGEventSource.flagsState(.combinedSessionState)
        event.setIntegerValueField(.eventSourceUserData, value: ScrollioEventMarker.syntheticCustom)
        notifyOrPostMouseEvent(event)
        return createdSessionID
    }

    func setTestingMouseEventObserver(_ observer: @escaping (CGEvent) -> Void = { _ in }) {
        testingMouseEventObserver = observer
    }

    func clearTestingMouseEventObserver() {
        testingMouseEventObserver = nil
    }

    func setTestingKeyboardShortcutObserver(
        _ observer: @escaping (CGKeyCode, UInt64, Bool) -> Void = { _, _, _ in }
    ) {
        testingKeyboardShortcutObserver = observer
    }

    func clearTestingKeyboardShortcutObserver() {
        testingKeyboardShortcutObserver = nil
    }

    func mouseTapReplayContext(for event: InputEvent) -> MouseTapReplayContext? {
        guard event.type == .mouse,
              let buttonNumber = mouseButtonNumberForTapReplay(event) else {
            return nil
        }
        let location: CGPoint?
        if case .cgEvent(let cgEvent) = event.source {
            location = cgEvent.location
        } else {
            location = nil
        }
        return MouseTapReplayContext(
            buttonNumber: buttonNumber,
            location: location,
            modifiers: event.modifiers
        )
    }

    func replayMouseTap(_ context: MouseTapReplayContext) {
        replayMouseEvent(context, phase: .down)
        replayMouseEvent(context, phase: .up)
    }

    private func syntheticTarget(for kind: MouseButtonActionKind) -> SyntheticMouseTarget {
        switch kind {
        case .left:
            return .left
        case .right:
            return .right
        case .middle:
            return .other(buttonNumber: 2)
        case .back:
            return .other(buttonNumber: 3)
        case .forward:
            return .other(buttonNumber: 4)
        }
    }

    private func syntheticTarget(buttonNumber: Int64) -> SyntheticMouseTarget {
        switch buttonNumber {
        case 0:
            return .left
        case 1:
            return .right
        default:
            return .other(buttonNumber: buttonNumber)
        }
    }

    private func mouseButtonNumberForTapReplay(_ event: InputEvent) -> Int64? {
        switch event.code {
        case 2...20:
            return Int64(event.code)
        case 1003:
            return 0
        case 1004:
            return 1
        case 1005:
            return 2
        case 1006:
            return 3
        case 1007:
            return 4
        default:
            return nil
        }
    }

    private func replayMouseEvent(
        _ context: MouseTapReplayContext,
        phase: InputPhase
    ) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let spec = mouseEventSpec(buttonNumber: context.buttonNumber, phase: phase)
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: spec.type,
            mouseCursorPosition: context.location ?? currentMouseLocationForCGEvent(),
            mouseButton: spec.button
        ) else {
            return
        }

        if let buttonNumber = spec.buttonNumber {
            event.setIntegerValueField(.mouseEventButtonNumber, value: buttonNumber)
        }
        // context.modifiers 非可选, provider 未接线时直接退化为它
        event.flags = modifierFlagsProvider?.combinedModifierFlags(physicalModifiers: context.modifiers)
            ?? context.modifiers
        event.setIntegerValueField(.eventSourceUserData, value: ScrollioEventMarker.syntheticCustom)
        notifyOrPostMouseEvent(event)
    }

    private func mouseEventSpec(for kind: MouseButtonActionKind, phase: InputPhase) -> (type: CGEventType, button: CGMouseButton, buttonNumber: Int64?) {
        switch kind {
        case .left:
            return (phase == .down ? .leftMouseDown : .leftMouseUp, .left, nil)
        case .right:
            return (phase == .down ? .rightMouseDown : .rightMouseUp, .right, nil)
        case .middle:
            return (phase == .down ? .otherMouseDown : .otherMouseUp, .center, 2)
        case .back:
            return (phase == .down ? .otherMouseDown : .otherMouseUp, .center, 3)
        case .forward:
            return (phase == .down ? .otherMouseDown : .otherMouseUp, .center, 4)
        }
    }

    private func mouseEventSpec(buttonNumber: Int64, phase: InputPhase) -> (type: CGEventType, button: CGMouseButton, buttonNumber: Int64?) {
        switch buttonNumber {
        case 0:
            return (phase == .down ? .leftMouseDown : .leftMouseUp, .left, nil)
        case 1:
            return (phase == .down ? .rightMouseDown : .rightMouseUp, .right, nil)
        default:
            return (phase == .down ? .otherMouseDown : .otherMouseUp, .center, buttonNumber)
        }
    }

    /// Where a synthesized click goes: the pointer, in CoreGraphics coordinates.
    private func currentMouseLocationForCGEvent() -> CGPoint {
        return Self.cgEventLocation(
            fromCocoa: NSEvent.mouseLocation,
            primaryScreenHeight: NSScreen.screens.first?.frame.height ?? 0
        )
    }

    /// A point in Cocoa screen coordinates (origin at the bottom left of the primary display,
    /// y up) in CoreGraphics coordinates (origin at its top left, y down). Both spaces hang
    /// on the primary display, the one with the menu bar (`NSScreen.screens.first`), whatever
    /// display the point is on. `NSScreen.main` is the screen of the key window instead: with
    /// that window on a display of another height every synthesized click landed off by the
    /// difference.
    static func cgEventLocation(fromCocoa location: NSPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        return CGPoint(x: location.x, y: primaryScreenHeight - location.y)
    }

    // MARK: - Logi HID++ Actions

    /// 执行 Logitech HID++ 动作
    /// Every "Logitech Mouse" action goes to the one entry point of `LogiCenter`, which runs
    /// it on the connected mouse. Only three of the ten were known here: a gesture or a
    /// standard button set to "Switch to Computer 2", "Toggle Hi-Res Scrolling" and the like
    /// did nothing (a Logitech button bound directly never came this way: its own session
    /// runs the action).
    private func executeLogiAction(_ name: String) {
        logiActionPerformer(name)
    }

    // MARK: - Open Target Actions

    /// 专用串行后台队列, 用于把 OpenTarget 实际执行 (NSWorkspace/Process/FileManager)
    /// 调离 CGEvent tap 回调链.
    private static let openTargetQueue = DispatchQueue(
        label: "com.nikklemenc.Scrollio.openTarget",
        qos: .userInitiated
    )

    private func executeOpenTarget(_ payload: OpenTargetPayload) {
        // CRITICAL: dispatch to background queue.
        // 调用栈: ButtonCore CGEvent tap → InputProcessor → ShortcutExecutor.execute(action:phase:).
        // CGEvent tap 有严格的回调延迟约束 (默认 1s 超时), 超时后系统会自动禁用 tap, 整个
        // 鼠标事件流断掉. NSWorkspace.openApplication / Process.run() / FileManager 都可能
        // 卡在 LaunchServices RPC、网络盘 stat、fork+exec、文件系统查询上, 同步执行有真实风险.
        Self.openTargetQueue.async { [payload] in
            switch payload.kind {
            case .application: self.launchApplication(payload)
            case .script:      self.runScript(payload)
            case .file:        self.openFile(payload)
            }
        }
    }

    /// 用系统默认 app 打开任意文件 (PNG / PDF / 文本 / etc.).
    /// NSWorkspace.open(_:) 不支持参数, payload.arguments 在此忽略.
    private func openFile(_ payload: OpenTargetPayload) {
        let url = URL(fileURLWithPath: payload.path)
        let fileName = url.lastPathComponent

        guard FileManager.default.fileExists(atPath: url.path) else {
            Toast.show(
                String(format: NSLocalizedString("openTargetFileNotFound", comment: ""), fileName),
                style: .error
            )
            // The log never names the file: its path holds the user's name, and the app's
            // log is public. The toast tells the user which one.
            AppSystemLog.problem("Open App or File: the file to open is gone")
            return
        }

        if !NSWorkspace.shared.open(url) {
            Toast.show(
                String(format: NSLocalizedString("openTargetFileFailed", comment: ""), fileName),
                style: .error
            )
            AppSystemLog.problem("Open App or File: macOS could not open the file")
        }
    }

    /// The app a stored target opens: the one at the stored path while it is there, and
    /// only when it is gone (moved, renamed) whatever app macOS knows by the stored bundle
    /// identifier. The identifier used to come first: a button set to
    /// /Applications/Xcode-beta.app opened /Applications/Xcode.app, the copy macOS prefers
    /// for the identifier the two share. Pure: the file system and Launch Services are the
    /// two closures.
    static func applicationURL(
        for payload: OpenTargetPayload,
        fileExists: (String) -> Bool,
        urlForBundleIdentifier: (String) -> URL?
    ) -> URL? {
        if fileExists(payload.path) {
            return URL(fileURLWithPath: payload.path)
        }
        return payload.bundleID.flatMap(urlForBundleIdentifier)
    }

    private func launchApplication(_ payload: OpenTargetPayload) {
        let workspace = NSWorkspace.shared
        let resolvedURL = Self.applicationURL(
            for: payload,
            fileExists: { FileManager.default.fileExists(atPath: $0) },
            urlForBundleIdentifier: { workspace.urlForApplication(withBundleIdentifier: $0) }
        )

        guard let resolvedURL else {
            let appName = (payload.path as NSString).lastPathComponent
            Toast.show(
                String(format: NSLocalizedString("openTargetAppNotFound", comment: ""), appName),
                style: .error
            )
            AppSystemLog.problem("Open App or File: the app to open is gone (not at its path, and macOS knows no app with its identifier)")
            return
        }

        // 走 NSWorkspace 而不是 Process(/usr/bin/open):
        // - LaunchServices 路径, 目标 App 由 launchd 启动, 拿到 launchd 的干净 env;
        //   不会继承 Mos 自身的 DYLD_*/__XPC_DYLD_* 等调试器注入 env vars.
        // - 这是 OS 层面的隔离, 不依赖 sanitize 黑名单.
        let appArguments = ArgumentSplitter.split(payload.arguments)
        let appName = resolvedURL.deletingPathExtension().lastPathComponent

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true   // 已运行则置前 (不重启)
        configuration.arguments = appArguments
        workspace.openApplication(at: resolvedURL, configuration: configuration) { _, error in
            if let error = error {
                Toast.show(
                    String(format: NSLocalizedString("openTargetAppLaunchFailed", comment: ""), appName),
                    style: .error
                )
                AppSystemLog.problem("Open App or File: macOS could not open the app (\(Self.logText(of: error)))")
            }
        }
    }

    /// 在 Mos 自身进程启动后, 立刻 unsetenv 掉污染 keys.
    ///
    /// 必须这么做的原因: 当 Mos Debug 由 Xcode 启动时, env 里带 DYLD_INSERT_LIBRARIES=
    /// .../libViewDebuggerSupport.dylib, 还有 __XPC_DYLD_* 等. 这些 keys 即使通过
    /// NSWorkspace.openApplication (XPC 到 launchservicesd) 启动子 App, 仍会被 macOS
    /// 沿着 XPC 链路传递到 launchservicesd 再到目标 App, 导致依赖 AVKit 的 sealed
    /// system app 加载 libViewDebuggerSupport 时找不到符号, dyld halt → SIGABRT.
    ///
    /// `Process.environment = sanitizedSubprocessEnvironment()` 只能堵 Process 这一条
    /// 路径; XPC 走的是 libxpc 内部读 live env, 必须从源头 unsetenv 才能根治.
    ///
    /// 调用时机: AppDelegate.applicationWillFinishLaunching 最早调一次. dyld 已经在
    /// app 启动时读完 DYLD_*, 之后 unsetenv 不会卸载已加载的 dylib (Xcode 视图调试
    /// 在 Mos 自身进程里继续工作), 但任何之后启动的子进程都拿不到这些 vars 了.
    ///
    /// Release 版本环境里这些 keys 本来就不存在, unsetenv 是 no-op. 安全无副作用.
    static func sanitizeOwnLaunchEnvironment() {
        for key in ProcessInfo.processInfo.environment.keys where shouldStripEnvKey(key) {
            unsetenv(key)
        }
    }

    /// 已 unsetenv 后再读, 返回当前 env 的副本 (供 Process.environment 显式赋值用).
    /// 双重保险: sanitizeOwnLaunchEnvironment 已经清干净源头, 这里再过滤一遍兜底.
    static func sanitizedSubprocessEnvironment() -> [String: String] {
        return filterEnvironment(ProcessInfo.processInfo.environment)
    }

    /// 纯函数: 输入一个 env dict, 输出剥离了污染 keys 的副本. 暴露出来供单测用控制输入验证.
    static func filterEnvironment(_ env: [String: String]) -> [String: String] {
        var out = env
        for key in env.keys where shouldStripEnvKey(key) {
            out.removeValue(forKey: key)
        }
        return out
    }

    private static func shouldStripEnvKey(_ key: String) -> Bool {
        // dyld 注入 / fallback 路径 / 框架路径
        if key.hasPrefix("DYLD_") { return true }
        // Xcode 通过 launchd XPC 传递的 dyld 注入 (会跨 XPC 边界变成子进程的 DYLD_*)
        if key.hasPrefix("__XPC_DYLD_") { return true }
        // Xcode 调试器附加 (LLVM profile / SwiftUI 视图调试 等)
        if key.hasPrefix("__XPC_LLVM_") { return true }
        if key == "SWIFTUI_VIEW_DEBUG" { return true }
        if key.hasPrefix("OS_ACTIVITY_DT_") { return true }
        // 内存分析器
        if key.hasPrefix("MallocStack") { return true }
        if key == "NSZombieEnabled" { return true }
        if key == "NSDeallocateZombies" { return true }
        // Sanitizer ABI shim
        if key.hasPrefix("LSAN_") || key.hasPrefix("ASAN_") || key.hasPrefix("TSAN_") || key.hasPrefix("UBSAN_") { return true }
        return false
    }

    // MARK: - Scripts

    /// A script that ends with an error within this time gets a toast: the press that
    /// started it is still in mind. One that fails later (a long-running tool that is quit)
    /// says nothing.
    static let scriptFailureFeedbackWindow: TimeInterval = 5

    /// The folders of tools installed by the user (Homebrew on Apple silicon and on Intel).
    static let userToolFolders = ["/opt/homebrew/bin", "/usr/local/bin"]

    /// What a bound script is started with: the app's environment without the keys a
    /// debugger injects (`filterEnvironment`), and with the folders of the user's tools at
    /// the end of PATH when they exist. An app started from Finder or at login has the bare
    /// PATH of the system (/usr/bin:/bin:/usr/sbin:/sbin), so a script beginning with
    /// `#!/usr/bin/env node`, or one that calls anything from Homebrew, could not run. At
    /// the end: nothing there can stand in for a system tool. Pure.
    static func scriptEnvironment(
        from environment: [String: String],
        existingFolders: (String) -> Bool
    ) -> [String: String] {
        var result = filterEnvironment(environment)
        var folders = (result["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
            .split(separator: ":").map(String.init)
        for folder in userToolFolders where !folders.contains(folder) && existingFolders(folder) {
            folders.append(folder)
        }
        result["PATH"] = folders.joined(separator: ":")
        return result
    }

    /// Whether a script that ended gets the "ended with an error" toast: it ended by itself
    /// with a status other than 0, soon after its start. A script ended by a signal (the
    /// user quit it) and a late failure get none. Pure.
    static func showsScriptFailure(status: Int32, endedBySignal: Bool, elapsed: TimeInterval) -> Bool {
        return !endedBySignal && status != 0 && elapsed <= scriptFailureFeedbackWindow
    }

    /// An error for the log without the paths its description may carry: where it comes
    /// from and its number.
    static func logText(of error: Error) -> String {
        let error = error as NSError
        return "\(error.domain) \(error.code)"
    }

    private func runScript(_ payload: OpenTargetPayload) {
        let url = URL(fileURLWithPath: payload.path)
        let scriptName = url.lastPathComponent

        guard FileManager.default.fileExists(atPath: url.path) else {
            Toast.show(
                String(format: NSLocalizedString("openTargetScriptNotFound", comment: ""), scriptName),
                style: .error
            )
            AppSystemLog.problem("Open App or File: the script to run is gone")
            return
        }

        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            Toast.show(
                String(format: NSLocalizedString("openTargetScriptNotExecutable", comment: ""), scriptName),
                style: .warning
            )
            AppSystemLog.problem("Open App or File: the script to run is not marked as executable")
            return
        }

        let launch = ScriptLaunch(
            executable: url,
            arguments: ArgumentSplitter.split(payload.arguments),
            environment: Self.scriptEnvironment(
                from: ProcessInfo.processInfo.environment,
                existingFolders: { FileManager.default.fileExists(atPath: $0) }
            ),
            // The script's own folder, so it finds the files next to it; it was "/".
            workingDirectory: url.deletingLastPathComponent()
        )
        let started = ProcessInfo.processInfo.systemUptime
        do {
            try scriptLauncher(launch) { status, endedBySignal in
                let elapsed = ProcessInfo.processInfo.systemUptime - started
                guard Self.showsScriptFailure(status: status, endedBySignal: endedBySignal, elapsed: elapsed) else { return }
                Toast.show(
                    String(format: NSLocalizedString("openTargetScriptExitedWithError", comment: ""), scriptName, Int(status)),
                    style: .warning
                )
                AppSystemLog.problem("Open App or File: the script ended with exit code \(status) after "
                    + String(format: "%.1f s", elapsed))
            }
        } catch {
            Toast.show(
                String(format: NSLocalizedString("openTargetScriptFailed", comment: ""), scriptName),
                style: .error
            )
            AppSystemLog.problem("Open App or File: the script could not be started (\(Self.logText(of: error)))")
        }
    }

    private func notifyOrPostMouseEvent(_ event: CGEvent) {
        if let testingMouseEventObserver {
            testingMouseEventObserver(event)
            return
        }
        post(event)
    }
}
