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

    init(lineDelta: Int64, fixedDelta: Double, pointDelta: Double, isContinuous: Bool) {
        self.lineDelta = lineDelta
        self.fixedDelta = fixedDelta
        self.pointDelta = pointDelta
        self.isContinuous = isContinuous
    }

    /// From the X axis as `ScrollEvent` read it.
    init(axis: axisData, isContinuous: Bool) {
        self.init(lineDelta: axis.scrollFix, fixedDelta: axis.scrollFixPt, pointDelta: axis.scrollPt, isContinuous: isContinuous)
    }
}

/// What one step of the thumb wheel does.
enum ThumbWheelAction: Equatable {
    /// An action of the action menu, run the way a button binding runs it
    /// (`ShortcutExecutor.execute(named:)`: Spaces use the shortcut set in System Settings).
    case named(String)
    /// A key combination that is not in the action menu (`ShortcutExecutor.execute(_:)`).
    case keys(SystemShortcut.Shortcut)
    /// A volume key of an Apple keyboard.
    case volume(SystemVolumeKey)

    /// Zoom in an app: ⌘= (zoom in) and ⌘− (zoom out), as browsers, Preview and editors have
    /// them. `SystemShortcut.zoomIn` / `zoomOut` are ⌘⌥= / ⌘⌥−, the screen zoom of the
    /// Accessibility settings, which is off unless the user turned its keyboard shortcuts on.
    /// Key codes of the US layout, as every key action of the executor.
    static let appZoomIn = SystemShortcut.Shortcut("thumbWheelZoomIn", 24, .command)
    static let appZoomOut = SystemShortcut.Shortcut("thumbWheelZoomOut", 27, .command)

    /// What a step does. Toward "next" is the turn that would scroll to the right
    /// (`ThumbWheelStepper`). Nil while the wheel scrolls.
    static func action(for function: ThumbWheelFunction, towardNext: Bool) -> ThumbWheelAction? {
        switch function {
        case .scroll:
            return nil
        case .zoom:
            return .keys(towardNext ? appZoomIn : appZoomOut)
        case .tabs:
            // ⌘⌥→ / ⌘⌥←: the next and previous tab in Chrome, Firefox, Edge and VS Code.
            // (`nextTab` / `previousTab` are ⌘⇧→ / ⌘⇧←, which select text in a text field.)
            return .named(towardNext ? SystemShortcut.switchTabRight.identifier : SystemShortcut.switchTabLeft.identifier)
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

    func perform(_ action: ThumbWheelAction, times: Int) {
        guard times > 0 else { return }
        for _ in 0..<times {
            switch action {
            case .named(let name):
                executor.execute(named: name)
            case .keys(let shortcut):
                executor.execute(shortcut)
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
    /// The roll whose log line is not written yet.
    private(set) var roll: Roll?
    /// Runs a step's action this many times, on the main queue (tests replace it).
    var perform: (ThumbWheelAction, Int) -> Void = { action, times in
        ThumbWheelActionPerformer().perform(action, times: times)
    }
    /// Runs work on the main queue after a delay (0: as soon as the tap callback returned).
    var schedule: (TimeInterval, @escaping () -> Void) -> Void = ThumbWheelEngine.scheduleOnMainQueue
    /// Writes a roll's log line.
    var writeLog: (Roll) -> Void = ScrollSystemLog.noteThumbWheelRoll
    /// Seconds on a monotonic clock.
    var clock: () -> TimeInterval = { CACurrentMediaTime() }

    /// A look at the open roll is scheduled: one at a time, and none once the wheel rested.
    private var checkScheduled = false
    /// Moves on with `reset()`: steps decided before it do not run.
    private var generation = 0

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
    ///   - flipped: X is turned around once ("Reverse wheel direction" or "Swap direction").
    /// - Returns: the steps this event ran (positive toward "next").
    @discardableResult
    func handle(_ event: ThumbWheelEvent, settings: ThumbWheelSettings, flipped: Bool) -> Int {
        let now = clock()
        var steps = 0
        if settings.function != .scroll {
            let travel = ThumbWheelStepper.travel(
                lineDelta: event.lineDelta, fixedDelta: event.fixedDelta, pointDelta: event.pointDelta,
                flipped: flipped, speed: settings.speed
            )
            steps = stepper.feed(travel: travel, function: settings.function, at: now)
            if steps != 0, let action = ThumbWheelAction.action(for: settings.function, towardNext: steps > 0) {
                let times = abs(steps)
                let generation = self.generation
                schedule(0) { [weak self] in
                    guard let self = self, self.generation == generation else { return }
                    self.perform(action, times)
                }
            }
        }
        record(event, settings: settings, steps: steps, at: now)
        return steps
    }

    private func record(_ event: ThumbWheelEvent, settings: ThumbWheelSettings, steps: Int, at now: TimeInterval) {
        if let open = roll, open.hasRested(at: now) || !open.matches(settings) {
            // Its look has not come yet, or a setting changed in the middle of the roll: the
            // roll ends here. Its line is written after the callback.
            roll = nil
            let writeLog = self.writeLog
            schedule(0) { writeLog(open) }
        }
        if roll == nil {
            roll = Roll(settings: settings, at: now)
        }
        roll?.add(event, steps: steps, at: now)
        if !checkScheduled {
            checkScheduled = true
            schedule(ThumbWheelTuning.rollRest) { [weak self] in self?.checkRoll() }
        }
    }

    /// Writes the open roll's line once the wheel rested (or the roll has gone on for
    /// `logInterval`); until then it looks again when that could be. Runs only while a roll is
    /// open: nothing keeps running while the wheel is still.
    func checkRoll() {
        checkScheduled = false
        guard let open = roll else { return }
        let now = clock()
        let due = open.lineDueAt
        if now >= due {
            roll = nil
            writeLog(open)
            return
        }
        checkScheduled = true
        schedule(due - now) { [weak self] in self?.checkRoll() }
    }

    /// Scrollio's scroll handling stopped (`ScrollCore.disable`): steps already decided do not
    /// run, the next event starts a new roll, and the open roll's line is written now.
    func reset() {
        generation &+= 1
        stepper.reset()
        if let open = roll {
            roll = nil
            writeLog(open)
        }
    }
}
