//
//  ThumbWheelEngine.swift
//  Mos
//
//  The sideways wheel's own settings (Options.thumbWheel) in the scroll tap. ScrollCore hands
//  over every sideways wheel event (`ScrollCore.isSidewaysWheelEvent`); while the wheel runs a
//  function, the event feeds the stepper and the steps run their actions on the main queue,
//  never inside the tap callback. Every sideways event, at the defaults as well, goes into the
//  roll's one log line.
//

import Cocoa

/// The X deltas of one sideways wheel event as it arrived at the scroll tap, before any
/// direction rule.
struct ThumbWheelEvent: Equatable {
    /// The integer line delta (`scrollWheelEventDeltaAxis2`).
    var lineDelta: Int64
    /// The fixed-point line delta (`scrollWheelEventFixedPtDeltaAxis2`).
    var fixedDelta: Double
    /// The point delta (`scrollWheelEventPointDeltaAxis2`).
    var pointDelta: Double
    /// `scrollWheelEventIsContinuous` is set (a wheel without notches, or a smoothing driver).
    var isContinuous: Bool
    /// The event's own `CGEvent.timestamp` (0: it has none). Rests are measured with it, not
    /// with the time the callback runs: after a stall of the main thread the queued events
    /// arrive in a burst, and the first would otherwise look like the start of a new roll.
    var timestamp: UInt64

    init(lineDelta: Int64, fixedDelta: Double, pointDelta: Double, isContinuous: Bool, timestamp: UInt64 = 0) {
        self.lineDelta = lineDelta
        self.fixedDelta = fixedDelta
        self.pointDelta = pointDelta
        self.isContinuous = isContinuous
        self.timestamp = timestamp
    }

    /// From the X axis as `ScrollEvent` read it.
    init(axis: axisData, isContinuous: Bool, timestamp: UInt64) {
        self.init(lineDelta: axis.scrollFix, fixedDelta: axis.scrollFixPt, pointDelta: axis.scrollPt,
                  isContinuous: isContinuous, timestamp: timestamp)
    }
}

/// What one step of the thumb wheel does.
enum ThumbWheelAction: Equatable {
    /// An action of the action menu, run the way a button binding runs it
    /// (`ShortcutExecutor.execute(named:)`: Spaces use the shortcut set in System Settings).
    case named(String)
    /// A key combination that is not in the action menu (`ShortcutExecutor.execute(_:)`).
    case keys(SystemShortcut.Shortcut)
    /// Zoom in or out in an app: ⌘ with the key that types "+" (else "=") or "-" on the
    /// keyboard layout in use (`AppZoomKeys`), looked up when the step runs. Not
    /// `SystemShortcut.zoomIn` / `zoomOut` (⌘⌥= / ⌘⌥−): that is the screen zoom of the
    /// Accessibility settings, off unless the user turned its keyboard shortcuts on.
    case zoomIn
    case zoomOut
    /// A volume key of an Apple keyboard.
    case volume(SystemVolumeKey)

    /// The next and previous tab: ⌃⇥ and ⌃⇧⇥ (Tab is key code 48 on every layout), as
    /// Safari, Chrome, Firefox, Terminal and Finder have them. Not the action menu's
    /// `switchTabRight` / `nextTab` (⌘⌥→ / ⌘⇧→), which button bindings keep using.
    static let nextTab = SystemShortcut.Shortcut("thumbWheelNextTab", 48, .control)
    static let previousTab = SystemShortcut.Shortcut("thumbWheelPreviousTab", 48, [.control, .shift])

    /// What a step does. Toward "next" is a negative X delta of the raw event, turned around
    /// only by "Swap direction" (`ThumbWheelStepper`). Nil while the wheel scrolls.
    static func action(for function: ThumbWheelFunction, towardNext: Bool) -> ThumbWheelAction? {
        switch function {
        case .scroll:
            return nil
        case .zoom:
            return towardNext ? .zoomIn : .zoomOut
        case .tabs:
            return .keys(towardNext ? nextTab : previousTab)
        case .desktops:
            return .named(towardNext ? SystemShortcut.moveSpaceRight.identifier : SystemShortcut.moveSpaceLeft.identifier)
        case .backForward:
            return .named(towardNext ? SystemShortcut.navigateForward.identifier : SystemShortcut.navigateBack.identifier)
        case .volume:
            return .volume(towardNext ? .up : .down)
        }
    }
}

/// Runs the actions of steps through the app's action path. Main thread.
struct ThumbWheelActionPerformer {
    var executor: ShortcutExecutor = .shared
    /// The seam for the volume keys: tests replace its `post`.
    var volumeKeys = SystemVolumeKeys()
    /// The zoom keys of the layout in use (tests pass one with a fake layout).
    var zoomKeys: AppZoomKeys = .shared

    func perform(_ action: ThumbWheelAction, times: Int) {
        guard times > 0 else { return }
        // Zoom: the layout is asked once per step's action, not per key press.
        let zoomCode: CGKeyCode?
        switch action {
        case .zoomIn: zoomCode = zoomKeys.codes().zoomIn
        case .zoomOut: zoomCode = zoomKeys.codes().zoomOut
        default: zoomCode = nil
        }
        for _ in 0..<times {
            switch action {
            case .named(let name):
                executor.execute(named: name)
            case .keys(let shortcut):
                executor.execute(shortcut)
            case .zoomIn, .zoomOut:
                if let code = zoomCode {
                    executor.execute(code: code, flags: UInt64(NSEvent.ModifierFlags.command.rawValue))
                }
            case .volume(let key):
                volumeKeys.press(key)
            }
        }
    }
}

/// The thumb wheel in the scroll tap. Main thread only: the tap callback and the main queue.
final class ThumbWheelEngine {

    typealias Roll = ScrollSystemLog.ThumbWheelRoll

    private(set) var stepper = ThumbWheelStepper()
    /// The roll whose events still come.
    private(set) var roll: Roll?
    /// A roll ended in the middle (a setting changed): written once its steps have run.
    private(set) var ended: Roll?
    /// Runs a step's action this many times, on the main queue (tests replace it).
    var perform: (ThumbWheelAction, Int) -> Void = { action, times in
        ThumbWheelActionPerformer().perform(action, times: times)
    }
    /// Runs work on the main queue after a delay (0: as soon as the tap callback returned).
    var schedule: (TimeInterval, @escaping () -> Void) -> Void = ThumbWheelEngine.scheduleOnMainQueue
    /// Writes a roll's log line.
    var writeLog: (Roll) -> Void = ScrollSystemLog.noteThumbWheelRoll
    /// Seconds on a monotonic clock: when the callback saw an event (the look at the open roll
    /// uses only these), and the time of an event without a timestamp.
    var clock: () -> TimeInterval = { CACurrentMediaTime() }
    /// Seconds per unit of `CGEvent.timestamp`.
    var secondsPerTimestampUnit = ThumbWheelEngine.appKitSecondsPerTimestampUnit

    /// A look at the open roll is scheduled: one at a time, and none once the wheel rested.
    private var checkScheduled = false
    /// Moves on with `reset()`: steps decided before it do not run.
    private var generation = 0
    private var nextRollID = 0

    /// The unit of `CGEvent.timestamp` as AppKit reads it, in seconds: nanoseconds, or mach
    /// ticks on some Macs (`CGEvent.uptimeSeconds` reads it through AppKit for that reason).
    /// Found once from one made-up event, so the tap callback converts without an NSEvent.
    static let appKitSecondsPerTimestampUnit: Double = {
        let nanoseconds = 1e-9
        let probe: UInt64 = 1_000_000_000
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 0, wheel2: 0, wheel3: 0) else {
            return nanoseconds
        }
        event.timestamp = probe
        guard let seconds = NSEvent(cgEvent: event)?.timestamp, seconds > 0, seconds.isFinite else {
            return nanoseconds
        }
        return seconds / Double(probe)
    }()

    static func scheduleOnMainQueue(after delay: TimeInterval, _ work: @escaping () -> Void) {
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    /// One sideways wheel event, in the scroll tap's callback. A few sums per event; a closure
    /// is made only when a step runs, a roll begins or its line is due. Nothing is logged here.
    /// - Parameters:
    ///   - flipped: X is turned around once. While the wheel runs a function: "Swap
    ///     direction" only. While it scrolls: "Reverse wheel direction" or "Swap direction".
    /// - Returns: the steps this event decided (positive toward "next").
    @discardableResult
    func handle(_ event: ThumbWheelEvent, settings: ThumbWheelSettings, flipped: Bool) -> Int {
        let seenAt = clock()
        let time = event.timestamp == 0 ? seenAt : Double(event.timestamp) * secondsPerTimestampUnit
        var steps = 0
        var travel = 0.0
        if settings.function != .scroll {
            travel = ThumbWheelStepper.travel(
                lineDelta: event.lineDelta, fixedDelta: event.fixedDelta, pointDelta: event.pointDelta,
                flipped: flipped, speed: settings.speed, function: settings.function
            )
            steps = stepper.feed(travel: travel, function: settings.function, at: time)
        }
        record(event, settings: settings, travel: travel, at: time, seenAt: seenAt)
        if steps != 0, let action = ThumbWheelAction.action(for: settings.function, towardNext: steps > 0), roll != nil {
            roll?.pendingSteps += abs(steps)
            let rollID = roll?.id
            let generation = self.generation
            schedule(0) { [weak self] in
                guard let self = self, self.generation == generation else { return }
                self.perform(action, abs(steps))
                self.stepsRan(steps, rollID: rollID)
            }
        }
        return steps
    }

    private func record(_ event: ThumbWheelEvent, settings: ThumbWheelSettings, travel: Double, at time: TimeInterval, seenAt: TimeInterval) {
        if let open = roll, open.hasRested(at: time) || !open.matches(settings) {
            // Its look has not come yet, or a setting changed in the middle of the roll: the
            // roll ends here. Its line is written after the callback, once its steps ran.
            endOpenRoll()
        }
        if roll == nil {
            nextRollID &+= 1
            roll = Roll(id: nextRollID, settings: settings, at: time, seenAt: seenAt)
        }
        roll?.add(event, travel: travel, at: time, seenAt: seenAt)
        if !checkScheduled {
            checkScheduled = true
            schedule(ThumbWheelTuning.logRollRest) { [weak self] in self?.checkRoll() }
        }
    }

    private func endOpenRoll() {
        guard let open = roll else { return }
        roll = nil
        if let previous = ended {
            // Two settings changes before the main queue ran: rare; written as it stands.
            writeLog(previous)
        }
        ended = open
        // Queued after the steps of its events: they have run when it is written.
        let id = open.id
        schedule(0) { [weak self] in self?.writeEndedRoll(id: id) }
    }

    /// Writes the ended roll (only that one, when `id` is given).
    private func writeEndedRoll(id: Int? = nil) {
        guard let done = ended, id == nil || done.id == id else { return }
        ended = nil
        writeLog(done)
    }

    private func stepsRan(_ steps: Int, rollID: Int?) {
        if roll?.id == rollID {
            roll?.stepsRan(steps)
        } else if ended?.id == rollID {
            ended?.stepsRan(steps)
        }
    }

    /// Writes the open roll's line once the wheel rested (or the roll has gone on for
    /// `logInterval`) and its steps ran; until then it looks again when that could be. Runs
    /// only while a roll is open: nothing keeps running while the wheel is still.
    func checkRoll() {
        checkScheduled = false
        guard let open = roll else { return }
        let now = clock()
        let due = open.lineDueAt
        if now >= due && open.pendingSteps == 0 {
            roll = nil
            writeLog(open)
            return
        }
        checkScheduled = true
        // Steps still queued run before a look scheduled now.
        schedule(max(0, due - now)) { [weak self] in self?.checkRoll() }
    }

    /// Scrollio's scroll handling stopped (`ScrollCore.disable`): steps already decided do not
    /// run, the next event starts a new roll, and the lines of the rolls so far are written now
    /// with the steps that ran.
    func reset() {
        generation &+= 1
        stepper.reset()
        writeEndedRoll()
        if let open = roll {
            roll = nil
            writeLog(open)
        }
    }
}
