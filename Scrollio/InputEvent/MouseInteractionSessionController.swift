//
//  MouseInteractionSessionController.swift
//  Mos
//  管理 synthetic 鼠标拖拽会话与虚拟修饰键的鼠标交互传播
//

import Cocoa

enum SyntheticMouseTarget: Equatable {
    case left
    case right
    case other(buttonNumber: Int64)
}

enum PhysicalMouseTarget: Equatable {
    case none
    case left
    case right
    case other(buttonNumber: Int64)
}

/// The pointer-movement event tap as the controller uses it: an `Interceptor` in the app, a
/// double in the tests.
protocol PointerMotionTap: AnyObject {
    func start() throws
    func pause()
    func stop()
    func isRunning() -> Bool
}

extension Interceptor: PointerMotionTap {}

/// A pointer-movement tap that listens to nothing: what the controller makes under XCTest.
final class InertPointerMotionTap: PointerMotionTap {
    private var running = true
    func start() throws { running = true }
    func pause() { running = false }
    func stop() { running = false }
    func isRunning() -> Bool { return running }
}

/// The pointer-movement tap is made on demand: by the first gesture hold that reads pointer
/// movement, a synthetic mouse drag or a virtual modifier. Between those it is paused. When
/// the cores stop (AppRunController) it is released and the next use makes a new one; a
/// tap that is off right after it was started is replaced once (`startRunningMotionTap`).
final class MouseInteractionSessionController {
    static let shared = MouseInteractionSessionController()

    /// Tries to get a running tap each time one is needed: the kept tap (or a new one),
    /// then once more a new one.
    static let motionTapAttempts = 2

    /// Mouse movement only. Scrollio's own dock swipe events (types 29 and 30) never reach this tap.
    static let motionEventMask: CGEventMask =
        (CGEventMask(1 << CGEventType.mouseMoved.rawValue)) |
        (CGEventMask(1 << CGEventType.leftMouseDragged.rawValue)) |
        (CGEventMask(1 << CGEventType.rightMouseDragged.rawValue)) |
        (CGEventMask(1 << CGEventType.otherMouseDragged.rawValue))

    private static let motionEventCallback: CGEventTapCallBack = { _, type, event, _ in
        MouseInteractionSessionController.shared.handleMotionTapEvent(type: type, event: event)
    }

    private let startMotionTapOverride: (() -> Void)?
    private let stopMotionTapOverride: (() -> Void)?
    /// Makes the tap in tests; nil makes the real one (`makeSystemMotionTap`).
    private let makeMotionTapOverride: (() throws -> PointerMotionTap)?
    private(set) var isMotionTapRunning = false
    private var activeSessions: [UUID: SyntheticMouseTarget] = [:]
    private var dominantTarget: SyntheticMouseTarget?
    private var motionTap: PointerMotionTap?
    private var testStartMotionTap: (() -> Void)?
    private var testStopMotionTap: (() -> Void)?
    var activeSessionCount: Int { activeSessions.count }
    private var hasActiveVirtualModifiers: Bool { InputProcessor.shared.activeModifierFlags != 0 }
    /// Only gesture holds that read pointer movement need the tap; a hold the mouse
    /// tracks itself (raw XY over HID++) does not.
    private var hasActiveMouseGestures: Bool { InputProcessor.shared.hasPointerTrackedMouseGestureSessions }

    init(
        startMotionTap: (() -> Void)? = nil,
        stopMotionTap: (() -> Void)? = nil,
        makeMotionTap: (() throws -> PointerMotionTap)? = nil
    ) {
        self.startMotionTapOverride = startMotionTap
        self.stopMotionTapOverride = stopMotionTap
        self.makeMotionTapOverride = makeMotionTap
    }

    static func dominantSyntheticTarget(from targets: [SyntheticMouseTarget]) -> SyntheticMouseTarget? {
        guard !targets.isEmpty else { return nil }
        return targets.min(by: { lhs, rhs in
            syntheticPriority(of: lhs) < syntheticPriority(of: rhs)
        })
    }

    static func effectiveTarget(
        physical: PhysicalMouseTarget,
        synthetic: SyntheticMouseTarget?
    ) -> SyntheticMouseTarget? {
        guard let synthetic else {
            switch physical {
            case .none:
                return nil
            case .left:
                return .left
            case .right:
                return .right
            case .other(let buttonNumber):
                return .other(buttonNumber: buttonNumber)
            }
        }

        let physicalAsSynthetic: SyntheticMouseTarget? = {
            switch physical {
            case .none:
                return nil
            case .left:
                return .left
            case .right:
                return .right
            case .other(let buttonNumber):
                return .other(buttonNumber: buttonNumber)
            }
        }()

        guard let physicalAsSynthetic else { return synthetic }
        return syntheticPriority(of: physicalAsSynthetic) <= syntheticPriority(of: synthetic) ? physicalAsSynthetic : synthetic
    }

    @discardableResult
    func beginSession(target: SyntheticMouseTarget) -> UUID {
        let sessionID = UUID()
        activeSessions[sessionID] = target
        recomputeDominantTarget()
        refreshMotionTapState()
        return sessionID
    }

    func endSession(id: UUID) {
        guard activeSessions.removeValue(forKey: id) != nil else { return }
        recomputeDominantTarget()
        refreshMotionTapState()
    }

    func clearAllSessions() {
        guard !activeSessions.isEmpty || isMotionTapRunning else { return }
        activeSessions.removeAll()
        dominantTarget = nil
        refreshMotionTapState()
    }

    func refreshMotionTapState() {
        if shouldKeepMotionTapRunning {
            if !isMotionTapRunning {
                startMotionTap()
            }
            return
        }

        guard isMotionTapRunning else { return }
        stopMotionTap()
    }

    /// The cores stop (AppRunController: sleep, another user, lost Accessibility access,
    /// Pause, quit). The tap is released, not only paused, and the next use makes a new one:
    /// a tap kept across a loss of the access or a switch to another user can stay off for
    /// good. A hold still in progress ends first, as when ButtonCore stops: the pointer is
    /// released.
    func releaseMotionTap() {
        if InputProcessor.shared.hasActiveMouseGestureSessions
            || hasActiveVirtualModifiers
            || !activeSessions.isEmpty
            || MouseGesturePointerLock.shared.isLocked {
            InputProcessor.shared.clearActiveBindings()
        }
        activeSessions.removeAll()
        dominantTarget = nil
        if isMotionTapRunning {
            stopMotionTap()
        }
        dropMotionTap()
    }

    func rewriteMouseInteractionEvent(_ event: CGEvent) {
        let shouldApplyVirtualModifiers = hasActiveVirtualModifiers
        let synthetic = dominantTarget

        guard synthetic != nil || shouldApplyVirtualModifiers else { return }

        if let synthetic {
            let physical = Self.physicalTarget(from: event)
            if let effective = Self.effectiveTarget(physical: physical, synthetic: synthetic) {
                rewrite(event, as: effective)
            }
        }

        event.flags = InputProcessor.shared.combinedModifierFlags(physicalModifiers: event.flags)
    }

    func setTestingMotionTapHooks(start: (() -> Void)? = {}, stop: (() -> Void)? = {}) {
        testStartMotionTap = start
        testStopMotionTap = stop
    }

    func clearTestingMotionTapHooks() {
        testStartMotionTap = nil
        testStopMotionTap = nil
    }

    #if DEBUG
    @discardableResult
    func handleMotionTapEventForTests(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        return handleMotionTapEvent(type: event.type, event: event)
    }

    /// The same with the type the callback is called with (a "tap disabled" type is not the
    /// type of the event that comes with it).
    @discardableResult
    func handleMotionTapEventForTests(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        return handleMotionTapEvent(type: type, event: event)
    }
    #endif

    private static func syntheticPriority(of target: SyntheticMouseTarget) -> (Int, Int64) {
        switch target {
        case .left:
            return (0, 0)
        case .right:
            return (1, 0)
        case .other(let buttonNumber):
            return (2, buttonNumber)
        }
    }

    private static func physicalTarget(from event: CGEvent) -> PhysicalMouseTarget {
        switch event.type {
        case .leftMouseDragged:
            return .left
        case .rightMouseDragged:
            return .right
        case .otherMouseDragged:
            return .other(buttonNumber: event.getIntegerValueField(.mouseEventButtonNumber))
        case .mouseMoved:
            return .none
        default:
            return .none
        }
    }

    private func recomputeDominantTarget() {
        dominantTarget = Self.dominantSyntheticTarget(from: Array(activeSessions.values))
    }

    private var shouldKeepMotionTapRunning: Bool {
        !activeSessions.isEmpty || hasActiveVirtualModifiers || hasActiveMouseGestures
    }

    private func rewrite(_ event: CGEvent, as target: SyntheticMouseTarget) {
        switch target {
        case .left:
            event.type = .leftMouseDragged
            event.setIntegerValueField(.mouseEventButtonNumber, value: 0)
        case .right:
            event.type = .rightMouseDragged
            event.setIntegerValueField(.mouseEventButtonNumber, value: 1)
        case .other(let buttonNumber):
            event.type = .otherMouseDragged
            event.setIntegerValueField(.mouseEventButtonNumber, value: buttonNumber)
        }
    }

    private func startMotionTap() {
        if let startMotionTapOverride {
            startMotionTapOverride()
            isMotionTapRunning = true
            return
        }

        if let testStartMotionTap {
            testStartMotionTap()
            isMotionTapRunning = true
            return
        }

        isMotionTapRunning = startRunningMotionTap()
    }

    /// Starts the kept tap or makes one, and checks that it runs. A tap that is off right
    /// after it was started (kept across a loss of the Accessibility access or a switch to
    /// another user, so macOS no longer serves it) is dropped and a new one made, once; then
    /// it gives up until the next use. Without a running tap a gesture hold reads no movement
    /// and, with "Freeze pointer during a gesture", keeps the pointer still for nothing.
    /// - Returns: whether a tap runs.
    private func startRunningMotionTap() -> Bool {
        var droppedKeptTap = false
        for attempt in 1...Self.motionTapAttempts {
            let tap: PointerMotionTap
            let isKept = motionTap != nil
            if let kept = motionTap {
                do {
                    try kept.start()
                } catch {
                    // Only without the Accessibility access: the stop path runs meanwhile.
                    AppSystemLog.problem("Could not start the pointer movement event tap: \(error)")
                    dropMotionTap()
                    return false
                }
                tap = kept
            } else {
                do {
                    tap = try (makeMotionTapOverride ?? Self.makeDefaultMotionTap ?? makeSystemMotionTap)()
                } catch {
                    AppSystemLog.problem("Could not create the pointer movement event tap: \(error)")
                    return false
                }
                motionTap = tap
            }
            if tap.isRunning() {
                if attempt > 1 {
                    AppSystemLog.note(Self.motionTapReplacedLine(droppedKeptTap: droppedKeptTap))
                }
                return true
            }
            droppedKeptTap = droppedKeptTap || isKept
            dropMotionTap()
        }
        AppSystemLog.problem(Self.motionTapGivenUpLine)
        return false
    }

    static func motionTapReplacedLine(droppedKeptTap: Bool) -> String {
        return "The pointer movement event tap was off right after it was started ("
            + (droppedKeptTap ? "the one kept from an earlier use" : "a new one")
            + "): made a new one, which runs"
    }

    static let motionTapGivenUpLine = "The pointer movement event tap stays off: it was off right after it was "
        + "started, and so was a new one. Gesture holds read no pointer movement until the next try, at the next hold"

    /// Under XCTest the controller makes a tap that does nothing unless a test passes its
    /// own: a test that started a click through the shared controller used to install a
    /// real, active tap on every pointer movement in the test process (with Accessibility
    /// access for the debug app: a stuttering pointer for the rest of the run).
    private static let makeDefaultMotionTap: (() throws -> PointerMotionTap)? =
        AppRuntime.isRunningXCTest ? { InertPointerMotionTap() } : nil

    private func makeSystemMotionTap() throws -> PointerMotionTap {
        let interceptor = try Interceptor(
            event: Self.motionEventMask,
            handleBy: Self.motionEventCallback,
            listenOn: .cgAnnotatedSessionEventTap,
            placeAt: .tailAppendEventTap,
            for: .defaultTap
        )
        interceptor.onRestart = {
            InputProcessor.shared.clearActiveBindings()
        }
        interceptor.shouldRestart = { [weak self] in
            guard let self else { return false }
            return self.shouldKeepMotionTapRunning
        }
        return interceptor
    }

    /// Switches the tap off and lets it go (`Interceptor.deinit` removes it from the window
    /// server); the next use makes a new one.
    private func dropMotionTap() {
        motionTap?.stop()
        motionTap = nil
    }

    private func stopMotionTap() {
        if let stopMotionTapOverride {
            stopMotionTapOverride()
            isMotionTapRunning = false
            return
        }

        if let testStopMotionTap {
            testStopMotionTap()
            isMotionTapRunning = false
            return
        }

        motionTap?.pause()
        isMotionTapRunning = false
    }

    private func handleMotionTapEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByUserInput {
            // What this tap's callback gets after Scrollio itself paused it (`stopMotionTap`,
            // after every use). Nothing went wrong and nothing is cleared: clearing here
            // released every other held action. A button held for "scroll fast" or a held
            // key lost its hold as soon as another button, bound to a click or a modifier,
            // was released, and its own release then reached the app as an up without a down.
            return Unmanaged.passUnretained(event)
        }
        if type == .tapDisabledByTimeout {
            EventTapDisableLog.note(.pointerMovement, type)
            InputProcessor.shared.clearActiveBindings()
            return Unmanaged.passUnretained(event)
        }

        InputProcessor.shared.handleMouseGestureMovement(
            deltaX: CGFloat(event.getDoubleValueField(.mouseEventDeltaX)),
            deltaY: CGFloat(event.getDoubleValueField(.mouseEventDeltaY)),
            location: event.location
        )
        MouseGesturePointerLock.shared.constrain(event)
        rewriteMouseInteractionEvent(event)
        return Unmanaged.passUnretained(event)
    }
}
