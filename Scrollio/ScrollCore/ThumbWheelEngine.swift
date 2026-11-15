//
//  ThumbWheelEngine.swift
//  Mos
//
//  The sideways wheel's own settings (Options.thumbWheel) in the scroll tap. ScrollCore hands
//  over every sideways wheel event (`ScrollCore.isSidewaysWheelEvent`); while the wheel runs a
//  function, the event passes the stray-tick filter (`ThumbWheelTickFilter`: small ticks at
//  a start or against the roll wait until they make half a line or a third comes, and do
//  nothing alone),
//  then feeds the stepper, and the steps it decides run their actions on the
//  main queue, never inside the tap callback. A function with a pacing (volume, desktops in
//  steps) runs them through `ThumbWheelPacer`: one at once, the others one per interval, a few
//  waiting at most (the system does not keep up with volume keys, the Dock with ⌃→); the others
//  run at once. Switch Desktops
//  with "Follow the wheel" drives a swipe of the desktops instead (`ThumbWheelFollower`).
//  Every sideways event, at the defaults as well, goes into the roll's one log line, which
//  is written on the main queue once the roll's steps ran and its swipes ended: a roll
//  that ended before that is kept by its id until then (`endedRolls`).
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
    /// only by the function's "Reverse direction" (`ThumbWheelStepper`). Nil while the wheel
    /// scrolls.
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

    /// - Returns: how many of the `times` sent nothing: the executor refused the action (a
    ///   Spaces action whose shortcut is switched off in System Settings, where its toast
    ///   says so; a retired action, or one this version does not know).
    @discardableResult
    func perform(_ action: ThumbWheelAction, times: Int) -> Int {
        guard times > 0 else { return 0 }
        // Zoom: the layout is asked once per step's action, not per key press.
        let zoomCode: CGKeyCode?
        switch action {
        case .zoomIn: zoomCode = zoomKeys.codes().zoomIn
        case .zoomOut: zoomCode = zoomKeys.codes().zoomOut
        default: zoomCode = nil
        }
        var sentNothing = 0
        for _ in 0..<times {
            switch action {
            case .named(let name):
                // As `ShortcutExecutor.execute(named:)`, keeping its answer.
                if let resolved = executor.resolveAction(named: name) {
                    if executor.execute(action: resolved, phase: .down).refusal != nil { sentNothing += 1 }
                } else {
                    sentNothing += 1
                }
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
        return sentNothing
    }
}

/// One turn of the thumb wheel: its events until the wheel rests (`ThumbWheelTuning.turnRest`,
/// by the events' own times). It runs with what the app that was in front at its first
/// event has of its own (its function, and while its own Scrolling settings are in use its
/// speed, reverses and follow switch: `ThumbWheelChoice`), whatever comes to the front
/// meanwhile: a turn that switches desktops brings another app forward, and its next stroke
/// still switches desktops at the same pace, and follows the wheel or not as it began.
struct ThumbWheelTurn: Equatable {
    /// What the app in front at the first event has of its own; nil: nothing. What is not
    /// the app's own is the general setting, read at every event (a change of it counts at
    /// once, as it always did).
    let own: ThumbWheelOwn?
    /// The last event's own time.
    var lastEventAt: TimeInterval

    /// The own function of the app in front at the first event; nil: the general one.
    var ownFunction: ThumbWheelFunction? {
        return own?.function
    }

    /// The wheel has rested before an event at `time`: the turn is over.
    func hasRested(at time: TimeInterval) -> Bool {
        return time >= lastEventAt + ThumbWheelTuning.turnRest
    }

    /// The settings an event of the turn goes by: `general` with what is the app's own in
    /// it (`ThumbWheelOwn.settings`).
    func settings(general: ThumbWheelSettings) -> ThumbWheelSettings {
        return own?.settings(general: general) ?? general
    }
}

/// The thumb wheel in the scroll tap. Main thread only: the tap callback and the main queue.
final class ThumbWheelEngine {

    typealias Roll = ScrollSystemLog.ThumbWheelRoll

    /// The turn whose events still come (`settings(for:general:)`).
    private(set) var turn: ThumbWheelTurn?
    /// The app in front, asked at a turn's first event, and only while some app on the list
    /// has a function of its own (`ThumbWheelChoice`). Tests give their own.
    var frontApplication: () -> ShortcutRingChoice.FrontApp? = { .current() }

    private(set) var stepper = ThumbWheelStepper()
    /// Holds small stray ticks until more of the roll confirms them (every function but
    /// Scroll Sideways, in steps and in Follow the wheel), and the function it filters for.
    private(set) var tickFilter = ThumbWheelTickFilter()
    private var tickFilterFunction: ThumbWheelFunction?
    /// The roll whose events still come.
    private(set) var roll: Roll?
    /// Rolls that ended before their line could be written, oldest first, each with its
    /// trace: a setting changed in the middle, or the next roll began while a swipe of
    /// Follow the wheel still waited for its Space change (up to 2.5 s after its end). A
    /// roll stays until its steps ran and its strokes and swipes ended, so an ending told
    /// late still finds its roll by its id (there was one place: a second roll that ended
    /// pushed the first out, written "no swipe" in the tap callback). At most
    /// `ThumbWheelTuning.endedRollsKept`.
    private var endedRolls: [EndedRoll] = []

    private struct EndedRoll {
        var roll: Roll
        var trace: ContiguousArray<ScrollSystemLog.ThumbWheelTraceEntry>
    }
    /// The steps of a paced function (volume) that wait, and when the last one ran.
    private(set) var pacer = ThumbWheelPacer()
    /// The function whose steps the pacer holds.
    private var pacedFunction: ThumbWheelFunction?
    /// Switch Desktops with "Follow the wheel": the swipe of a stroke. Its clock and main
    /// queue are the engine's.
    let follower = ThumbWheelFollower()
    /// A look at the pacer is scheduled: one at a time, none while no step waits.
    private var paceScheduled = false
    /// Runs a step's action this many times, on the main queue, and says how many of them
    /// sent nothing (`ThumbWheelActionPerformer.perform`; tests replace it).
    var perform: (ThumbWheelAction, Int) -> Int = { action, times in
        ThumbWheelActionPerformer().perform(action, times: times)
    }
    /// Runs work on the main queue after a delay (0: as soon as the tap callback returned).
    var schedule: (TimeInterval, @escaping () -> Void) -> Void = ThumbWheelEngine.scheduleOnMainQueue {
        didSet { follower.schedule = schedule }
    }
    /// Writes a roll's log line.
    var writeLog: (Roll) -> Void = ScrollSystemLog.noteThumbWheelRoll
    /// Writes a function roll's trace line (`ScrollSystemLog.thumbWheelTraceMessage`).
    var writeTrace: (String) -> Void = ScrollSystemLog.noteThumbWheelTrace
    /// Seconds on a monotonic clock: when the callback saw an event (the look at the open roll
    /// uses only these), and the time of an event without a timestamp.
    var clock: () -> TimeInterval = { CACurrentMediaTime() } {
        didSet { follower.clock = clock }
    }
    /// Seconds per unit of `CGEvent.timestamp`.
    var secondsPerTimestampUnit = ThumbWheelEngine.appKitSecondsPerTimestampUnit

    /// A look at the open roll is scheduled: one at a time, and none once the wheel rested.
    private var checkScheduled = false
    /// Moves on with `reset()`: steps decided before it do not run.
    private var generation = 0
    private var nextRollID = 0
    /// The trace of the open roll (each event's gap and fixed-point lines, the first
    /// `ThumbWheelTuning.traceEntries`). An ended roll keeps its own until its line is
    /// written; the buffers are reserved once, handed round and emptied, never grown, so
    /// the tap callback allocates nothing for them.
    private var traceOpen = ThumbWheelEngine.emptyTrace()
    private var spareTraces: [ContiguousArray<ScrollSystemLog.ThumbWheelTraceEntry>] = []

    private static func emptyTrace() -> ContiguousArray<ScrollSystemLog.ThumbWheelTraceEntry> {
        var trace = ContiguousArray<ScrollSystemLog.ThumbWheelTraceEntry>()
        trace.reserveCapacity(ThumbWheelTuning.traceEntries)
        return trace
    }

    init() {
        endedRolls.reserveCapacity(ThumbWheelTuning.endedRollsKept + 1)
        spareTraces = (0...ThumbWheelTuning.endedRollsKept).map { _ in ThumbWheelEngine.emptyTrace() }
        // A roll's line waits for its strokes and swipes (by its id, the tag of their events).
        follower.onStrokeEnd = { [weak self] tag, waited in
            self?.changeRoll(tag) { $0.strokeEnded(waited: waited) }
        }
        follower.onSwipeBegin = { [weak self] tag in
            self?.changeRoll(tag) { $0.pendingSwipes += 1 }
        }
        follower.onSwipeEnd = { [weak self] tag, swipe in
            self?.changeRoll(tag) { $0.swipeEnded(swipe) }
        }
    }

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

    /// The settings a sideways wheel event goes by, in the scroll tap's callback, before
    /// `handle`: `general` with what the event's turn has of an app's own. The turn's first
    /// event (the first ever, or one after the wheel rested) decides whose they are: the app
    /// in front's own function, speed, reverses and follow switch, else the general ones (`ThumbWheelChoice`:
    /// the list looked at, the app in front read only while some app has something of its
    /// own; nothing on disk, no Launch Services). Every later event of the turn keeps them:
    /// one comparison of times.
    func settings(for event: ThumbWheelEvent, general: ThumbWheelSettings) -> ThumbWheelSettings {
        let time = event.timestamp == 0 ? clock() : Double(event.timestamp) * secondsPerTimestampUnit
        let current: ThumbWheelTurn
        if var open = turn, !open.hasRested(at: time) {
            open.lastEventAt = time
            current = open
        } else {
            let own = ThumbWheelChoice.own(front: frontApplication, applications: Options.shared.application.applications)
            current = ThumbWheelTurn(own: own, lastEventAt: time)
        }
        turn = current
        return current.settings(general: general)
    }

    /// One sideways wheel event, in the scroll tap's callback. A few sums per event; a closure
    /// is made only when a step runs, a roll begins or its line is due. Nothing is logged here.
    /// - Parameters:
    ///   - flipped: X is turned around once. While the wheel runs a function: the function's
    ///     "Reverse direction" only. While it scrolls: "Reverse wheel direction" or its
    ///     "Reverse direction".
    /// - Returns: the steps this event decided (positive toward "next"; none while Switch
    ///   Desktops follows the wheel).
    @discardableResult
    func handle(_ event: ThumbWheelEvent, settings: ThumbWheelSettings, flipped: Bool) -> Int {
        let seenAt = clock()
        let time = event.timestamp == 0 ? seenAt : Double(event.timestamp) * secondsPerTimestampUnit
        // The roll first: one that rested or whose settings changed ends before this event.
        openRoll(settings: settings, at: time, seenAt: seenAt)
        let lines = ThumbWheelStepper.lines(lineDelta: event.lineDelta, fixedDelta: event.fixedDelta, pointDelta: event.pointDelta)
        var steps = 0
        var travel = 0.0
        var tick = ThumbWheelTickFilter.Result.nothing
        var newStroke = false
        if settings.followsWheelNow && follower.canFollow {
            travel = ThumbWheelFollower.travel(
                lineDelta: event.lineDelta, fixedDelta: event.fixedDelta, pointDelta: event.pointDelta,
                flipped: flipped, speed: settings.speed
            )
            // A held tick reaches neither the stepper nor the swipe.
            tick = tickFilter.filter(travel: travel, lines: lines, at: time)
            if tick.travel != 0, case .yes(let begins) = follower.add(tick.travel, at: time, seenAt: seenAt, tag: roll?.id ?? 0) {
                newStroke = begins
            }
        } else {
            // Another function, or Follow the wheel switched off in the middle of a stroke
            // (or no swipe can be made here: the desktops go in steps).
            if follower.isInStroke { follower.endStroke(at: time) }
            if settings.function != .scroll {
                travel = ThumbWheelStepper.travel(
                    lineDelta: event.lineDelta, fixedDelta: event.fixedDelta, pointDelta: event.pointDelta,
                    flipped: flipped, speed: settings.speed, function: settings.function
                )
                tick = tickFilter.filter(travel: travel, lines: lines, at: time)
                if tick.travel != 0 {
                    steps = stepper.feed(travel: tick.travel, function: settings.function, at: time, heldSince: tick.heldSince)
                }
            }
        }
        if settings.function != .scroll, traceOpen.count < ThumbWheelTuning.traceEntries, let open = roll {
            let gap = open.events > 0 ? time - open.lastEventAt : 0
            traceOpen.append(ScrollSystemLog.ThumbWheelTraceEntry(gap: gap, fixed: event.fixedDelta))
        }
        roll?.add(event, travel: travel, at: time, seenAt: seenAt)
        roll?.ticksFiltered(tick)
        scheduleRollLook()
        if newStroke {
            // The roll waits for the stroke to end.
            roll?.pendingSwipes += 1
        }
        guard steps != 0, roll != nil else { return steps }
        if let pacing = settings.function.pacing {
            pace(steps, function: settings.function, pacing: pacing, at: seenAt)
        } else if let action = ThumbWheelAction.action(for: settings.function, towardNext: steps > 0) {
            // No pacing: the steps run at once, after the callback.
            roll?.pendingSteps += abs(steps)
            let rollID = roll?.id
            let generation = self.generation
            schedule(0) { [weak self] in
                guard let self = self, self.generation == generation else { return }
                let sentNothing = self.perform(action, abs(steps))
                self.stepsRan(steps, rollID: rollID, sentNothing: sentNothing)
            }
        }
        return steps
    }

    // MARK: Pacing

    /// Steps of a paced function: one may run now (after the callback), the others wait for
    /// the pacer's interval; the ones the pacer drops are counted for the log.
    private func pace(_ steps: Int, function: ThumbWheelFunction, pacing: ThumbWheelPacing, at now: TimeInterval) {
        if pacedFunction != function {
            dropWaitingSteps()
            pacedFunction = function
        }
        let added = pacer.add(steps, pacing: pacing, at: now)
        roll?.pendingSteps += abs(steps)
        roll?.stepsDropped(added.dropped)
        if added.runNow != 0, let action = ThumbWheelAction.action(for: function, towardNext: added.runNow > 0) {
            let step = added.runNow
            let rollID = roll?.id
            let generation = self.generation
            schedule(0) { [weak self] in
                guard let self = self, self.generation == generation else { return }
                let sentNothing = self.perform(action, 1)
                self.stepsRan(step, rollID: rollID, sentNothing: sentNothing)
            }
        }
        schedulePaceLook(pacing)
    }

    /// Schedules the pacer's next look while a step waits; nothing while none waits.
    private func schedulePaceLook(_ pacing: ThumbWheelPacing) {
        guard !paceScheduled, let due = pacer.nextRunAt(pacing: pacing) else { return }
        paceScheduled = true
        let generation = self.generation
        schedule(max(0, due - clock())) { [weak self] in
            guard let self = self, self.generation == generation else { return }
            self.paceScheduled = false
            self.lookAtThePacer()
        }
    }

    /// Runs the waiting step that is due (main queue), then schedules the next look.
    private func lookAtThePacer() {
        guard let function = pacedFunction, let pacing = function.pacing else { return }
        let step = pacer.take(pacing: pacing, at: clock())
        if step != 0, let action = ThumbWheelAction.action(for: function, towardNext: step > 0) {
            let sentNothing = perform(action, 1)
            // Waiting steps belong to the open roll: a roll that ends drops them.
            stepsRan(step, rollID: roll?.id, waited: true, sentNothing: sentNothing)
        }
        schedulePaceLook(pacing)
    }

    /// Drops the steps that wait (another function, the end of the roll, a stop); the open
    /// roll counts them.
    private func dropWaitingSteps() {
        roll?.stepsDropped(pacer.dropWaiting())
    }

    /// The roll an event at `time` belongs to: the open one, unless the wheel rested or a
    /// setting changed (then it ends here; its line is written after the callback, once its
    /// steps ran), else a new one.
    private func openRoll(settings: ThumbWheelSettings, at time: TimeInterval, seenAt: TimeInterval) {
        let rested = roll?.hasRested(at: time) ?? false
        if rested {
            // A tick still held is older than the filter's window: the rested roll's, dropped.
            roll?.ticksDropped += tickFilter.dropHeld()
        }
        if settings.function != tickFilterFunction {
            // Another function starts the filter afresh.
            roll?.ticksDropped += tickFilter.reset()
            tickFilterFunction = settings.function
        }
        if let open = roll, rested || !open.matches(settings) {
            // Its look has not come yet, or a setting changed in the middle of the roll.
            endOpenRoll()
        }
        if roll == nil {
            nextRollID &+= 1
            roll = Roll(id: nextRollID, settings: settings, at: time, seenAt: seenAt)
            // (The log says when the settings were an app's own, never which app.)
            roll?.isAppsOwn = turn?.own != nil
            traceOpen.removeAll(keepingCapacity: true)
        }
    }

    private func scheduleRollLook() {
        guard !checkScheduled else { return }
        checkScheduled = true
        schedule(ThumbWheelTuning.logRollRest) { [weak self] in self?.checkRoll() }
    }

    /// The open roll is over (in the tap callback: nothing is written here). It is kept,
    /// with its trace, until its line can be written on the main queue.
    private func endOpenRoll() {
        dropWaitingSteps()
        guard let open = roll else { return }
        roll = nil
        // The next roll's trace goes into a spare buffer (a new one only when more rolls
        // ended than are ever kept before the main queue ran).
        var trace = spareTraces.popLast() ?? ThumbWheelEngine.emptyTrace()
        swap(&trace, &traceOpen)
        endedRolls.append(EndedRoll(roll: open, trace: trace))
        // Queued after the steps of its events: they have run when it is written.
        let id = open.id
        schedule(0) { [weak self] in self?.writeEndedRoll(id: id) }
        if endedRolls.count > ThumbWheelTuning.endedRollsKept {
            // More rolls wait for a swipe's ending than ever should: the oldest is written as
            // it stands, after the callback (its line says what had not ended).
            let oldest = endedRolls[0].roll.id
            schedule(0) { [weak self] in self?.writeEndedRoll(id: oldest, asItStands: true) }
        }
    }

    /// Writes the ended roll `id` and lets it go; not while a stroke or a swipe of it is
    /// still to end (its last ending writes it), unless `asItStands`. Main queue.
    private func writeEndedRoll(id: Int, asItStands: Bool = false) {
        guard let index = endedRolls.firstIndex(where: { $0.roll.id == id }),
              asItStands || endedRolls[index].roll.pendingSwipes == 0 else { return }
        var done = endedRolls.remove(at: index)
        write(done.roll, trace: &done.trace)
        if spareTraces.count <= ThumbWheelTuning.endedRollsKept { spareTraces.append(done.trace) }
    }

    /// Writes a roll's line and, for a roll that ran a function, its trace line right after
    /// it; the trace is emptied (its room kept). The trace line is written in every build for
    /// now, the owner runs Release builds to tune the wheel: cut it, or keep it to DEBUG,
    /// before the next release (`scripts/release.sh` refuses a build that still has the
    /// words "thumb wheel trace:" in it).
    private func write(_ done: Roll, trace: inout ContiguousArray<ScrollSystemLog.ThumbWheelTraceEntry>) {
        writeLog(done)
        if done.function != .scroll, done.events > 0 {
            writeTrace(ScrollSystemLog.thumbWheelTraceMessage(entries: trace, events: done.events))
        }
        trace.removeAll(keepingCapacity: true)
    }

    /// What Follow the wheel did goes to the roll whose id its events carried, open or
    /// ended (written, it is not counted again); an ended roll with nothing more to wait
    /// for is written after the callback.
    private func changeRoll(_ id: Int, _ change: (inout Roll) -> Void) {
        if roll != nil, roll?.id == id {
            change(&roll!)
        } else if let index = endedRolls.firstIndex(where: { $0.roll.id == id }) {
            change(&endedRolls[index].roll)
            if endedRolls[index].roll.pendingSwipes == 0 {
                schedule(0) { [weak self] in self?.writeEndedRoll(id: id) }
            }
        }
    }

    /// - Parameter sentNothing: how many of the steps the executor refused (`perform`).
    private func stepsRan(_ steps: Int, rollID: Int?, waited: Bool = false, sentNothing: Int = 0) {
        if roll != nil, roll?.id == rollID {
            roll?.stepsRan(steps, waited: waited, sentNothing: sentNothing)
        } else if let index = endedRolls.firstIndex(where: { $0.roll.id == rollID }) {
            endedRolls[index].roll.stepsRan(steps, waited: waited, sentNothing: sentNothing)
        }
    }

    /// Writes the open roll's line once the wheel rested (or the roll has gone on for
    /// `logInterval`) and its steps ran; until then it looks again when that could be. Runs
    /// only while a roll is open: nothing keeps running while the wheel is still.
    func checkRoll() {
        checkScheduled = false
        guard var open = roll else { return }
        let now = clock()
        let due = open.lineDueAt
        if now >= due && !open.isWaiting {
            if now >= open.lastSeenAt + ThumbWheelTuning.logRollRest {
                // The wheel rested: a tick still held is the roll's, dropped.
                open.ticksDropped += tickFilter.dropHeld()
            }
            roll = nil
            write(open, trace: &traceOpen)
            return
        }
        checkScheduled = true
        var delay = due - now
        if delay <= 0 {
            // Due, but steps still to run: look again when the next waiting one runs, or just
            // after the steps already queued; never a busy loop on the main queue.
            let nextPaced = pacedFunction?.pacing.flatMap { pacer.nextRunAt(pacing: $0) }
            delay = max(ThumbWheelTuning.pendingRecheck, (nextPaced ?? now) - now)
            if open.pendingSteps == 0 {
                // Only Follow the wheel to end: a stroke at the wheel's rest, a swipe once its
                // Space changed (or the time for that passed).
                delay = max(delay, ThumbWheelTuning.followRest / 4)
            }
        }
        schedule(delay) { [weak self] in self?.checkRoll() }
    }

    /// Scrollio's scroll handling stopped (`ScrollCore.disable`): steps already decided do not
    /// run (waiting ones included), a swipe of Follow the wheel is cancelled at once, the
    /// next event starts a new roll and a new turn (which looks at the app in front again),
    /// and the lines of the rolls so far are written now with the steps that ran.
    func reset() {
        follower.cancel()
        generation &+= 1
        turn = nil
        stepper.reset()
        roll?.ticksDropped += tickFilter.reset()
        tickFilterFunction = nil
        dropWaitingSteps()
        pacer = ThumbWheelPacer()
        pacedFunction = nil
        paceScheduled = false
        // (The stop told every swipe's ending above: nothing is still to end.)
        while let first = endedRolls.first {
            writeEndedRoll(id: first.roll.id, asItStands: true)
        }
        if let open = roll {
            roll = nil
            write(open, trace: &traceOpen)
        }
    }
}
