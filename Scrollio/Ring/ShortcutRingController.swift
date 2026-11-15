//
//  ShortcutRingController.swift
//  Scrollio
//
//  The Shortcut Ring between its rules (`ShortcutRingSession`, pure), the input side
//  (`InputProcessor`) and the screen (`ShortcutRingPresenting`, the panel).
//
//  What reaches it, and from where:
//
//  - The trigger's press and release: `InputProcessor.process`, for a button or key bound
//    to `SystemShortcut.shortcutRing`. The controller is made at the first such press;
//    for someone who never bound the ring it does not exist (`existing` is nil).
//  - The hand's movement while the trigger is held: the pointer-movement tap, which runs
//    for the length of the hold as it does for a gesture hold
//    (`MouseInteractionSessionController`). Its deltas keep coming when the pointer stands
//    at the edge of a screen.
//  - The pointer over a ring that stands open: no event tap. A timer looks where the
//    pointer is, and stops with the ring. No pointer event of the Mac waits on Scrollio
//    while a ring stands open.
//  - The click that chooses or dismisses, held or left open: the panel itself takes it
//    (the window server gives the panel the click's up with its down), so the app
//    underneath gets neither; on another screen, where a pointer that is not kept still
//    can carry a held click, that screen's panel takes it. A click that goes to another
//    app all the same (before the panels are on screen, or should a panel not have taken
//    it), or to a window of Scrollio's own, closes the ring and runs nothing: while a ring
//    is open, and only then, two monitors hear of such clicks.
//  - Esc: the keys tap, which is kept running while a ring is open
//    (`InputProcessor.needsKeyEvents`).
//
//  The ring closes and runs nothing when the event taps stop or are restarted
//  (`InputProcessor.clearActiveBindings`), when another button's action runs, when
//  another app comes to the front, the Space or the screens change, after
//  `ShortcutRingSession.holdLimit` of a hold whose release never came and after
//  `idleLimit` without the pointer moving over an open ring. It does not open while the
//  left or the right button is down (a drag).
//
//  Which ring opens is decided when the trigger goes down, by the app in front
//  (`ShortcutRingChoice`): its own ring if it has one in use, else the general ring. That
//  ring stays the ring until it closes, whatever comes to the front meanwhile.
//
//  What a place that opens an app shows (its name, its icon) takes a look on disk. That
//  never happens in the turn in which a ring is shown: the face is made at a quiet moment
//  (`preparedFaces`, one per ring: the general one and each app's own), and a ring for
//  which none is there yet shows the file's name and a plain symbol once. So does the
//  app's icon that an app's own ring shows in its middle while nothing is lit (and the
//  app's name, which VoiceOver hears in the ring's label): it is made as the faces are,
//  one per app (`preparedAppMarks`), and a ring for which none is there yet has an empty
//  middle. The general ring's middle is always empty.
//
//  Nothing is drawn and nothing is posted inside an event callback: the panel is shown on
//  the next turn of the main queue, and so is the chosen action, after the panel is gone.
//  A place runs as a button's action runs: resolved by the executor from a binding built
//  from the place, down and then up for what is held (a recorded key, a click).
//  A pulse (`MouseGestureHapticCue`) is played only for a trigger that arrived over HID++,
//  on the mouse it belongs to, and only while Gestures › Haptic feedback is on (the one
//  switch for the pulses of a hold): a light one when a place lights (at most one every
//  `tickSpacing`, the others dropped), a firmer one when an action runs.
//

import Cocoa

final class ShortcutRingController {

    // MARK: The one controller

    /// The controller, once a ring was first asked for. Nil for everyone else: the paths
    /// that ask "is a ring open?" cost them a comparison with nil.
    private(set) static var existing: ShortcutRingController?

    /// The controller, made now if there is none yet.
    static var shared: ShortcutRingController {
        if let existing { return existing }
        let controller = ShortcutRingController()
        existing = controller
        return controller
    }

    // MARK: The face, made at a quiet moment

    /// Rings' faces with what it took a look on disk to know (an app's name and icon),
    /// made when no ring was held: by Settings whenever it shows a ring (the pane the
    /// general one, an app's page the app's own), at launch and after a change of the
    /// settings for the rings that can open and open something, and after a ring closed
    /// that had to be shown without it. Only rings that open something keep one (`prepare`).
    /// The newest first, one per ring: a face belongs to the eight places it was made for
    /// and is never shown for others, so the ring of one app never shows another's. It
    /// also belongs to the keyboard layout it was made on (the keys it names, and what a
    /// suggested shortcut is there): the faces of another layout are dropped
    /// (`dropFacesOfAnotherLayout`).
    private(set) static var preparedFaces: [(ring: ShortcutRingSettings, face: ShortcutRingFace)] = []

    /// The keyboard layout the kept faces were made on (`ShortcutRingSuggestions.layoutID`).
    private static var preparedFacesLayout: String?

    /// Drops the kept faces when the keyboard layout in use is not the one they were made
    /// on. Asked wherever a face is looked for or kept: on the main queue, never inside an
    /// event callback.
    private static func dropFacesOfAnotherLayout() {
        let layout = ShortcutRingSuggestions.layoutID()
        guard layout != preparedFacesLayout else { return }
        preparedFacesLayout = layout
        preparedFaces = []
    }

    /// How many faces are kept (the general ring's and those of apps' own rings). A ring
    /// beyond them is shown once without its icons and then takes the oldest one's place.
    static let preparedFaceLimit = 12

    /// The face that was made last.
    static var preparedFace: (ring: ShortcutRingSettings, face: ShortcutRingFace)? {
        return preparedFaces.first
    }

    /// The face made for a ring with the places of `ring`; nil when there is none. (A
    /// face shows the places and nothing else: the freeze switch plays no part.)
    static func preparedFace(for ring: ShortcutRingSettings) -> ShortcutRingFace? {
        dropFacesOfAnotherLayout()
        return preparedFaces.first { $0.ring.places == ring.places }?.face
    }

    /// Keeps `face` for the next ring that is `ring`. A ring that opens nothing needs no
    /// look on disk (its face is whole when it is made at a press): its face is not kept,
    /// so that the app pages a user browses never push out a face with an app's icon.
    static func prepare(_ face: ShortcutRingFace, for ring: ShortcutRingSettings) {
        guard ring.opensSomething else { return }
        dropFacesOfAnotherLayout()
        preparedFaces.removeAll { $0.ring.places == ring.places }
        preparedFaces.insert((ring, face), at: 0)
        if preparedFaces.count > preparedFaceLimit {
            preparedFaces.removeLast(preparedFaces.count - preparedFaceLimit)
        }
    }

    /// The rings whose face is made at launch and after a change of the settings: of those
    /// that can open, the ones with a place that opens an app or a file, each set of places
    /// once (an app's own ring starts as a copy of the general one); none while nothing
    /// opens the ring. A ring can open when the bindings that count while some app is in
    /// front open it: the general ring when Buttons opens it (any app without a ring of its
    /// own) or when an app without a ring of its own opens it with a binding of its own;
    /// an app's own ring when the app's bindings (Buttons with its own merged over them)
    /// open it. So a ring that only an app's own button or key opens has its face too, and
    /// an app whose own bindings take the ring's button away does not need one.
    static func ringsToPrepareAtLaunch(options: Options = .shared) -> [ShortcutRingSettings] {
        let canOpen = ringsThatCanOpen(options: options)
        var distinct: [ShortcutRingSettings] = []
        for ring in (canOpen.general ? [options.ring] : []) + canOpen.own.map(\.ring)
        where ring.opensSomething && !distinct.contains(where: { $0.places == ring.places }) {
            distinct.append(ring)
        }
        return Array(distinct.prefix(preparedFaceLimit))
    }

    /// The rings that can open (`ringsToPrepareAtLaunch`): whether the general ring can,
    /// and each app whose own ring can, by the path of its entry, with that ring.
    private static func ringsThatCanOpen(
        options: Options
    ) -> (general: Bool, own: [(path: String, ring: ShortcutRingSettings)]) {
        let general = options.buttons.binding
        let generalOpens = opensTheRing(general)
        var generalCanOpen = generalOpens
        var own: [(path: String, ring: ShortcutRingSettings)] = []
        let applications = options.application.applications
        for index in 0..<applications.count {
            // Of two entries of one path, the one a press finds (`get(by:)`, the last).
            guard let entry = applications.get(by: index), applications.get(by: entry.path) === entry else { continue }
            let opens = entry.hasOwnButtons
                ? opensTheRing(ApplicationButtons.merged(general: general, own: entry.ownButtonBindings))
                : generalOpens
            guard opens else { continue }
            if entry.ownRingPlaces != nil {
                own.append((entry.path, entry.ringThatOpens(general: options.ring)))
            } else {
                generalCanOpen = true
            }
        }
        return (generalCanOpen, own)
    }

    /// An enabled binding of `bindings` opens the ring.
    private static func opensTheRing(_ bindings: [ButtonBinding]) -> Bool {
        return bindings.contains { $0.isEnabled && $0.systemShortcutName == SystemShortcut.shortcutRing.identifier }
    }

    // MARK: The apps' marks, made at a quiet moment

    /// What an app's own ring shows of the app (`ShortcutRingAppMark`: its icon for the
    /// middle, its name for VoiceOver), by the stored path of the app's entry, the newest
    /// first. Made where the faces are made and as they are, one app per turn of the main
    /// queue: after the faces at launch and after a change of the settings, for the apps
    /// whose own ring can open (`appMarksToPrepare`); by an app's page that shows its ring;
    /// after an app's own ring closed that had none. Never at a press: a ring whose mark is
    /// not there has an empty middle. Dropped when the app leaves the list; at most
    /// `preparedFaceLimit` (an app beyond them takes the oldest one's place).
    private(set) static var preparedAppMarks: [(path: String, mark: ShortcutRingAppMark)] = []

    /// The mark made for the app stored at `path`; nil when there is none.
    static func preparedAppMark(forPath path: String) -> ShortcutRingAppMark? {
        return preparedAppMarks.first { $0.path == path }?.mark
    }

    /// Keeps `mark` for the next own ring of the app stored at `path`.
    static func prepare(_ mark: ShortcutRingAppMark, forAppAt path: String) {
        preparedAppMarks.removeAll { $0.path == path }
        preparedAppMarks.insert((path, mark), at: 0)
        if preparedAppMarks.count > preparedFaceLimit {
            preparedAppMarks.removeLast(preparedAppMarks.count - preparedFaceLimit)
        }
    }

    /// Drops the marks of apps that are no longer on the per-app list.
    static func dropAppMarks(notOn applications: EnhanceArray<Application>) {
        preparedAppMarks.removeAll { applications.get(by: $0.path) == nil }
    }

    /// The apps whose mark is made at launch and after a change: those whose own ring can
    /// open, by the paths of their entries, in the list's order; at most
    /// `preparedFaceLimit`.
    static func appMarksToPrepare(options: Options = .shared) -> [String] {
        return Array(ringsThatCanOpen(options: options).own.map(\.path).prefix(preparedFaceLimit))
    }

    /// Whose ring `choice` opens, with what was made of the app at a quiet moment: no look
    /// on disk. Without a mark the app's name is the one its path has, and the middle stays
    /// empty.
    static func owner(of choice: ShortcutRingChoice) -> ShortcutRingOwner {
        guard let path = choice.appPath else { return .general }
        let mark = preparedAppMark(forPath: path)
        return .app(name: mark?.name ?? ShortcutRingAppMark.plainName(ofPath: path), icon: mark?.icon)
    }

    // MARK: The passes of faces and marks

    /// How long a face that was due at launch waits while a ring is open.
    static let launchFaceWait: TimeInterval = 0.5

    /// At launch: when something opens the ring and a place of a ring opens an app or a
    /// file, the faces are made on later turns of the main queue, one place that opens
    /// something per turn (`ShortcutRingFace.InSteps`: the event taps wait on the same
    /// queue), a ring's face kept once its last place is in, and never while a ring is
    /// open, so that the first ring already has the icons. For everyone else: one pass
    /// over the bindings and the apps, nothing more. `after` runs a block on the main
    /// queue after a delay; `makePlace` makes one place with its look on disk. (The apps'
    /// marks follow from `prepareFacesAfterChanges`, once these faces are made.)
    static func prepareFaceAtLaunch(
        options: Options = .shared,
        after: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, block in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: block)
        },
        makePlace: @escaping (ShortcutRingPlace) -> ShortcutRingFace.Place = { ShortcutRingFace.place($0) }
    ) {
        // The general ring last, so that it is the newest.
        prepareQuietly(
            faces: ringsToPrepareAtLaunch(options: options).reversed(), marks: [],
            after: after, makePlace: makePlace, makeMark: { ShortcutRingAppMark.make(forPath: $0) }
        )
    }

    /// After every change of the bindings (Buttons and the apps' own), of the per-app list
    /// or of the general ring, the faces of the rings that can open now and have none yet,
    /// and the marks of the apps whose own ring can open now (`prepareMissingFaces`): a
    /// binding of an app's own that opens the ring, made while no pane showed that ring,
    /// gets its face and its mark before its first ring. Called once, at launch, after
    /// `prepareFaceAtLaunch`: the apps' marks are made then too, after the launch's faces.
    /// (Options keeps its observers for the app's life.)
    static func prepareFacesAfterChanges(options: Options = .shared) {
        options.observe([.buttons, .application, .ring]) { [weak options] _ in
            guard let options else { return }
            prepareMissingFaces(options: options)
        }
        prepareMissingFaces(options: options)
    }

    /// A pass of `prepareMissingFaces` waits for its turn: a burst of changes (a slider of
    /// an app's page dragged) asks for one.
    private static var missingFacesAreDue = false
    /// The passes of faces and marks under way (`prepareQuietly`): `prepareMissingFaces`
    /// decides only while none is, so that two passes never take turns together.
    private static var quietPasses = 0
    /// Counts `forgetPreparedFaces` (tests): a turn of a pass from before it does nothing.
    private static var quietGeneration = 0

    /// The faces of the rings that can open (`ringsToPrepareAtLaunch`) and have none yet,
    /// and the marks of the apps whose own ring can open (`appMarksToPrepare`) that have
    /// none yet, made as at launch: decided on the next turn of the main queue, or once
    /// the pass under way is over (what a pane made in the meantime is not made again;
    /// the marks of apps that left the list are dropped then), then one place that opens
    /// something or one app's mark per turn, never while a ring is open. Nothing more for a
    /// change that leaves every face and mark there. `makeMark`: one app's mark with its
    /// look on disk.
    static func prepareMissingFaces(
        options: Options = .shared,
        after: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, block in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: block)
        },
        makePlace: @escaping (ShortcutRingPlace) -> ShortcutRingFace.Place = { ShortcutRingFace.place($0) },
        makeMark: @escaping (String) -> ShortcutRingAppMark = { ShortcutRingAppMark.make(forPath: $0) }
    ) {
        guard !missingFacesAreDue else { return }
        missingFacesAreDue = true
        let generation = quietGeneration
        after(0) {
            decideMissing(generation: generation, options: options, after: after, makePlace: makePlace, makeMark: makeMark)
        }
    }

    private static func decideMissing(
        generation: Int, options: Options,
        after: @escaping (TimeInterval, @escaping () -> Void) -> Void,
        makePlace: @escaping (ShortcutRingPlace) -> ShortcutRingFace.Place,
        makeMark: @escaping (String) -> ShortcutRingAppMark
    ) {
        guard generation == quietGeneration else { return }
        guard quietPasses == 0 else {
            // (The launch's faces: what they make is not missing any more when they are done.)
            after(launchFaceWait) {
                decideMissing(generation: generation, options: options, after: after, makePlace: makePlace, makeMark: makeMark)
            }
            return
        }
        missingFacesAreDue = false
        dropAppMarks(notOn: options.application.applications)
        let faces = ringsToPrepareAtLaunch(options: options).filter { preparedFace(for: $0) == nil }
        let marks = appMarksToPrepare(options: options).filter { preparedAppMark(forPath: $0) == nil }
        prepareQuietly(faces: faces.reversed(), marks: marks, after: after, makePlace: makePlace, makeMark: makeMark)
    }

    /// A pass: the faces of `faces` in order, then the marks of the apps at `marks`.
    private static func prepareQuietly(
        faces: [ShortcutRingSettings], marks: [String],
        after: @escaping (TimeInterval, @escaping () -> Void) -> Void,
        makePlace: @escaping (ShortcutRingPlace) -> ShortcutRingFace.Place,
        makeMark: @escaping (String) -> ShortcutRingAppMark
    ) {
        guard !faces.isEmpty || !marks.isEmpty else { return }
        quietPasses += 1
        prepareFaces(
            of: faces, then: marks, generation: quietGeneration, after: after, makePlace: makePlace, makeMark: makeMark
        )
    }

    /// One turn: the next place of the first of `rings` (whose face `steps` holds once it
    /// is begun), then a turn for what is left. A ring whose face was made meanwhile (by a
    /// pane, after a ring closed) is left out before its first place. After the last ring
    /// the marks of `marks`.
    private static func prepareFaces(
        of rings: [ShortcutRingSettings], then marks: [String], steps: ShortcutRingFace.InSteps? = nil,
        generation: Int,
        after: @escaping (TimeInterval, @escaping () -> Void) -> Void,
        makePlace: @escaping (ShortcutRingPlace) -> ShortcutRingFace.Place,
        makeMark: @escaping (String) -> ShortcutRingAppMark
    ) {
        func next(_ rings: [ShortcutRingSettings], _ steps: ShortcutRingFace.InSteps? = nil) {
            prepareFaces(
                of: rings, then: marks, steps: steps, generation: generation, after: after, makePlace: makePlace,
                makeMark: makeMark
            )
        }
        guard let ring = rings.first else {
            return prepareMarks(marks, generation: generation, after: after, makeMark: makeMark)
        }
        after(0) {
            guard generation == quietGeneration else { return }
            guard existing?.isOpen != true else {
                after(launchFaceWait) { next(rings, steps) }
                return
            }
            if steps == nil, preparedFace(for: ring) != nil {
                next(Array(rings.dropFirst()))
                return
            }
            var steps = steps ?? ShortcutRingFace.InSteps(ring)
            steps.step(makePlace)
            guard let whole = steps.whole else {
                next(rings, steps)
                return
            }
            prepare(whole, for: ring)
            next(Array(rings.dropFirst()))
        }
    }

    /// One turn: the mark of the first app of `paths` that has none yet, then a turn for
    /// what is left. The pass is over when none is left.
    private static func prepareMarks(
        _ paths: [String], generation: Int,
        after: @escaping (TimeInterval, @escaping () -> Void) -> Void,
        makeMark: @escaping (String) -> ShortcutRingAppMark
    ) {
        // (A page, or a ring that closed, may have made some meanwhile.)
        let waiting = paths.filter { preparedAppMark(forPath: $0) == nil }
        guard let path = waiting.first else {
            quietPasses = max(0, quietPasses - 1)
            return
        }
        after(0) {
            guard generation == quietGeneration else { return }
            guard existing?.isOpen != true else {
                after(launchFaceWait) { prepareMarks(waiting, generation: generation, after: after, makeMark: makeMark) }
                return
            }
            if preparedAppMark(forPath: path) == nil {
                prepare(makeMark(path), forAppAt: path)
            }
            prepareMarks(Array(waiting.dropFirst()), generation: generation, after: after, makeMark: makeMark)
        }
    }

    #if DEBUG
    /// Tests: puts a controller of their own in the app's place (nil: none, as before the
    /// first ring).
    static func setTestingController(_ controller: ShortcutRingController?) {
        existing?.cancel()
        existing = controller
    }

    /// Tests: no face and no app's mark is prepared, as before the first ring (and no pass
    /// is under way or waiting for its turn).
    static func forgetPreparedFaces() {
        preparedFaces = []
        preparedFacesLayout = nil
        preparedAppMarks = []
        missingFacesAreDue = false
        quietPasses = 0
        quietGeneration += 1
    }
    #endif

    // MARK: What it needs from the system

    struct Environment {
        /// Monotonic time in seconds.
        var now: () -> TimeInterval
        /// Where the pointer is, in event coordinates.
        var pointerLocation: () -> CGPoint
        /// The screen that holds a point (event coordinates).
        var screen: (CGPoint) -> ShortcutRingScreen
        /// The left or the right button is down.
        var isPrimaryButtonDown: () -> Bool
        /// Runs the block on the next turn of the main queue, never inside the caller.
        var schedule: (@escaping () -> Void) -> Void
        /// Runs the block on the main queue after this many seconds.
        var scheduleAfter: (TimeInterval, @escaping () -> Void) -> Void
        /// A repeating timer, or nil when the caller drives `tick()` itself (tests).
        var makeTimer: (TimeInterval, @escaping () -> Void) -> Timer?
        /// The general ring this Mac's settings hold.
        var ring: () -> ShortcutRingSettings
        /// The ring that opens now, given the general one: the own ring of the app in
        /// front, or the general ring. Asked once per ring, when the trigger goes down,
        /// inside the event callback: nothing slow in it (no disk, no Launch Services).
        /// By default the general ring (tests).
        var choice: (ShortcutRingSettings) -> ShortcutRingChoice = { .general($0) }
        /// One place of a ring's face with its look on disk (an app's or a file's name
        /// and icon, the icon drawn). Only called while no ring is open.
        var makePlace: (ShortcutRingPlace) -> ShortcutRingFace.Place
        /// The mark of the app stored at a path (its icon drawn, its name), with its look
        /// on disk. Only called while no ring is open.
        var makeAppMark: (String) -> ShortcutRingAppMark = { ShortcutRingAppMark.make(forPath: $0) }
        /// Runs a place's action.
        var run: (ShortcutRingPlace) -> Void
        /// Whether a ring may ask a mouse for pulses: Gestures › Haptic feedback, the one
        /// switch for the pulses of a hold. (A cue can switch a mouse's haptics on; it is
        /// only asked for while the user has that switch on.)
        var allowsHaptics: () -> Bool
        /// Plays a pulse on the mouse the button with this code was pressed on.
        var playHaptic: (MouseGestureHapticCue, UInt16) -> Void
        /// Says the lit action's name to VoiceOver.
        var announce: (String) -> Void
        /// The held state changed: the pointer-movement tap follows it.
        var refreshMotionTap: () -> Void
        /// Keeps the pointer where it is, and lets it go again: for a hold of a ring whose
        /// "Freeze pointer while the ring is held" is on.
        var lockPointer: () -> Void
        var unlockPointer: () -> Void
        /// Whether the ring needs the keyboard changed: the keys tap follows it.
        var refreshKeyTap: () -> Void
        /// One line of the `app` log: a ring opened, was left open, ran something or
        /// closed. A few lines per use of the ring, never one per pointer event.
        var log: (String) -> Void
        /// Something that should not happen did: a line of the `app` log as a problem.
        var logProblem: (String) -> Void
        /// Starts to hear of mouse-downs that did not go to the ring: those that went to
        /// other apps, and those in windows of Scrollio's own (the handler gets that
        /// window; nil for another app's). The result ends it
        /// (`stopWatchingClicksElsewhere`). Nil: nothing was started (tests).
        var watchClicksElsewhere: (@escaping (NSWindow?) -> Void) -> Any?
        var stopWatchingClicksElsewhere: (Any) -> Void

        static let system = Environment(
            now: { ProcessInfo.processInfo.systemUptime },
            pointerLocation: { ShortcutRingScreens.pointerLocation() },
            screen: { ShortcutRingScreens.screen(containing: $0) },
            isPrimaryButtonDown: { NSEvent.pressedMouseButtons & 0b11 != 0 },
            schedule: { DispatchQueue.main.async(execute: $0) },
            scheduleAfter: { delay, block in DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: block) },
            makeTimer: { interval, block in
                // Under XCTest no timer runs; a test calls `tick()`.
                guard !AppRuntime.isRunningXCTest else { return nil }
                return CommonModesTimer.scheduled(withTimeInterval: interval, repeats: true) { _ in block() }
            },
            ring: { Options.shared.ring },
            choice: { general in
                ShortcutRingChoice.make(
                    front: .current(), applications: Options.shared.application.applications, general: general
                )
            },
            makePlace: { ShortcutRingFace.place($0) },
            run: { ShortcutRingController.run($0) },
            allowsHaptics: { Options.shared.gesture.hapticFeedback },
            playHaptic: { cue, code in LogiCenter.shared.playGestureHaptic(cue, forScrollioCode: code) },
            announce: { ShortcutRingController.announce($0) },
            refreshMotionTap: { MouseInteractionSessionController.shared.refreshMotionTapState() },
            lockPointer: { MouseGesturePointerLock.shared.lock(for: .shortcutRing) },
            unlockPointer: { MouseGesturePointerLock.shared.unlock(for: .shortcutRing) },
            refreshKeyTap: { ButtonCore.shared.keyTap.refresh() },
            log: { AppSystemLog.note($0) },
            logProblem: { AppSystemLog.problem($0) },
            watchClicksElsewhere: { handler in
                // Under XCTest nothing listens to the Mac's clicks.
                guard !AppRuntime.isRunningXCTest else { return nil }
                let downs: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
                // Clicks in other apps, and clicks in Scrollio's own windows (its Settings
                // on another screen): the global monitor does not hear of the second kind.
                let monitors: [Any?] = [
                    NSEvent.addGlobalMonitorForEvents(matching: downs) { _ in handler(nil) },
                    NSEvent.addLocalMonitorForEvents(matching: downs) { event in
                        handler(event.window)
                        return event
                    },
                ]
                return monitors.compactMap { $0 }
            },
            stopWatchingClicksElsewhere: { watch in
                for monitor in watch as? [Any] ?? [] {
                    NSEvent.removeMonitor(monitor)
                }
            }
        )
    }

    /// Between two light pulses; a place that lights sooner gets none.
    static let tickSpacing: TimeInterval = 0.1
    /// For this long after a place's action was started, a change of Space or of the app
    /// in front does not close a ring: it is what that action did ("Move right a space",
    /// an app that opens), and it may arrive when the next ring is already held.
    static let quietAfterRun: TimeInterval = 1.0
    /// How often the pointer is looked at while the ring stands open.
    static let pointerInterval: TimeInterval = 1.0 / 60.0
    /// How often a held ring is looked at: its limit, and a hand that stopped between the
    /// dead zone and twice of it in the first moments, whose place lights when those are
    /// over although no movement arrives any more.
    static let holdCheckInterval: TimeInterval = 0.1

    var environment: Environment
    let presenter: ShortcutRingPresenting

    // MARK: State

    private(set) var session = ShortcutRingSession()
    /// The ring as it was when it opened: what is shown and what a place runs.
    private var ring = ShortcutRingSettings.default
    /// The keyboard layout in use when `filled` and `face` were worked out
    /// (`ShortcutRingSuggestions.layoutID`): on another layout a suggested shortcut is
    /// other keys, or none, and every key has another name.
    private var ringLayout: String?
    /// Which of its places run something, worked out when the ring or the keyboard layout
    /// changes, not per press.
    private var filled = ShortcutRingSettings.default.filled
    private var face: ShortcutRingFace?
    /// `face` knows everything (an app's name and icon); false while it was made without
    /// a look on disk, for a ring that had to be shown before a whole face was there.
    private var faceIsComplete = false
    /// The screen the ring opened on.
    private var screen = ShortcutRingScreen(frame: .zero, usable: .zero)
    /// The button to name when asking for a pulse: set for a trigger that arrived over
    /// HID++, nil otherwise.
    private var hapticCode: UInt16?
    /// What opened the ring, for the log.
    private var openedBy = ""
    /// The ring that opened is the own one of the app in front, for the log.
    private var isAppsOwnRing = false
    /// Whose ring opened: its label, and an app's icon for the middle when one was made.
    private(set) var owner = ShortcutRingOwner.general
    /// The stored path of the app whose own ring opened (nil: the general ring): its mark
    /// is made after the ring closed when there was none.
    private var ownerPath: String?
    private var lastTick = -TimeInterval.infinity
    /// When a place's action was last started.
    private var lastRun = -TimeInterval.infinity
    /// Drops a show that was scheduled for a ring that is gone.
    private var showGeneration = 0
    private var timer: Timer?
    private var timerPhase = ShortcutRingSession.Phase.closed
    private var lastPolledPointer: CGPoint?
    private var wasHeld = false
    /// This hold keeps the pointer still (the ring's own switch).
    private var holdsPointer = false
    /// Where the pointer stood when the trigger went down.
    private var pressPointer = CGPoint.zero
    private var neededKeys = false
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    /// Hears of clicks that went to other apps, while a ring is open.
    private var clickWatch: Any?
    /// The line about a click the panel did not take is written once per run.
    private var didLogMissedClick = false
    /// The ring that is open is on the screen (it is shown a turn after the press).
    private var isShown = false
    /// The ring closes at the up of a click that went down while the trigger was held:
    /// the log says so.
    private var closesByAHeldClick = false

    init(environment: Environment = .system, presenter: ShortcutRingPresenting = ShortcutRingPanelPresenter()) {
        self.environment = environment
        self.presenter = presenter
        presenter.onButton = { [weak self] button, isDown, location in
            self?.button(button, isDown: isDown, at: location)
        }
        observeWhatClosesTheRing()
    }

    deinit {
        timer?.invalidate()
        if let clickWatch {
            environment.stopWatchingClicksElsewhere(clickWatch)
        }
        for observer in observers {
            observer.center.removeObserver(observer.token)
        }
    }

    // MARK: What others ask

    var isOpen: Bool {
        return session.isOpen
    }

    /// The trigger is down and the hand's movement chooses: the pointer-movement tap is
    /// needed.
    var isHeld: Bool {
        return session.phase == .held
    }

    /// Esc is the ring's: the keys tap is needed.
    var needsKeys: Bool {
        return session.needsKeys
    }

    /// Esc closed the ring and is not up yet: until then every Esc down (its repeats) is
    /// the ring's too.
    var awaitsEscapeRelease: Bool {
        return session.needsKeys && !session.isOpen
    }

    // MARK: The trigger (InputProcessor)

    /// The ring's trigger went down. Never a key's auto-repeat.
    func triggerPressed(by event: InputEvent) {
        assertMainThread()
        if !session.isOpen {
            // In the middle of a drag the ring stays away.
            guard !environment.isPrimaryButtonDown() else { return }
            // The app in front decides, now: this ring stays until it closes.
            let choice = environment.choice(environment.ring())
            let stored = choice.ring
            isAppsOwnRing = choice.isAppsOwn
            // The app's icon only if it was made at a quiet moment: nothing is loaded now.
            owner = Self.owner(of: choice)
            ownerPath = choice.appPath
            // (The layout's id is read, nothing is translated unless the layout changed
            // and the ring holds a suggested shortcut.)
            let layout = ShortcutRingSuggestions.layoutID()
            if stored != ring || layout != ringLayout {
                // Another ring than last time (changed in Settings, or another app in
                // front): the face of the last one is not this one's. Nor is it after a
                // change of the keyboard layout: the keys have other names there, and a
                // suggested shortcut is other keys, or none.
                ring = stored
                ringLayout = layout
                filled = stored.filled
                face = nil
                faceIsComplete = false
            }
            if case .hidPP = event.source, environment.allowsHaptics() {
                hapticCode = event.code
            } else {
                hapticCode = nil
            }
            openedBy = Self.kind(of: event)
        }
        let pointer = Self.pointerLocation(of: event) ?? environment.pointerLocation()
        if !session.isOpen {
            screen = environment.screen(pointer)
            pressPointer = pointer
        }
        perform(session.triggerPressed(
            at: environment.now(), pointer: pointer, screen: screen.usable, filled: filled
        ))
    }

    /// The trigger came up; `isMadeUp` for a release Scrollio made up itself.
    func triggerReleased(isMadeUp: Bool) {
        assertMainThread()
        perform(session.triggerReleased(at: environment.now(), isMadeUp: isMadeUp))
    }

    /// What kind of trigger an event is, for the log.
    private static func kind(of event: InputEvent) -> String {
        if case .hidPP = event.source { return "a button over HID++" }
        return event.type == .keyboard ? "a key" : "a mouse button"
    }

    /// Where the pointer was when a mouse button's event was made; nil for a key and for
    /// a button that arrived over HID++.
    private static func pointerLocation(of event: InputEvent) -> CGPoint? {
        guard event.type == .mouse, case .cgEvent(let cgEvent) = event.source else { return nil }
        return cgEvent.location
    }

    // MARK: The pointer (the motion tap while held, the timer while open)

    /// The mouse moved while the trigger is held. Runs inside the motion tap's callback.
    func pointerMoved(by delta: CGPoint, to location: CGPoint) {
        guard session.phase == .held else { return }
        // A pointer that is kept still stands where the press found it, whatever an event
        // says that was made before the freeze took hold: a ring that is then left open
        // must not take that event's place for the pointer's, and light what it is under.
        let stands = holdsPointer ? pressPointer : location
        perform(session.pointerMoved(by: delta, to: stands, at: environment.now()))
    }

    /// One look of the timer: where the pointer is over an open ring, and whether the
    /// ring's time is up.
    func tick() {
        guard session.isOpen else {
            stopTimer()
            return
        }
        let now = environment.now()
        if session.phase == .latched {
            let pointer = environment.pointerLocation()
            if pointer != lastPolledPointer {
                lastPolledPointer = pointer
                perform(session.pointerMoved(by: .zero, to: pointer, at: now))
            }
        }
        perform(session.timePassed(to: now))
    }

    // MARK: Clicks (the panel) and Esc (the keys tap)

    private func button(_ button: Int, isDown: Bool, at location: CGPoint) {
        assertMainThread()
        if isDown {
            perform(session.buttonPressed(button, at: location, time: environment.now()))
        } else {
            closesByAHeldClick = session.phase == .held
            perform(session.buttonReleased(button))
            closesByAHeldClick = false
        }
    }

    /// A mouse button went down and the click went to another app, while a ring is open:
    /// the ring closes and runs nothing. That is how a click in the moment before a held
    /// ring is on the screen looks. Once it is there, a panel on every screen should have
    /// taken the click: it did not, the app underneath got it, and choosing a shortcut on
    /// top of that would act on a click the user did not make there; the log says so.
    func clickWentElsewhere(in window: NSWindow? = nil) {
        assertMainThread()
        // A click on one of the ring's own panels is the ring's (the panel reports it).
        guard session.isOpen, !presenter.owns(window) else { return }
        if isShown, !didLogMissedClick {
            didLogMissedClick = true
            environment.logProblem("Shortcut Ring: a click went to the app under the ring's panels "
                + "(the panel did not take it); the ring closed without running anything")
        }
        cancel()
    }

    /// Esc went down. True: it was the ring's and goes no further.
    func escapePressed() -> Bool {
        let result = session.escapePressed()
        perform(result.commands)
        return result.answer == .swallow
    }

    /// Esc came up. True: its press closed the ring, so its release is the ring's too.
    func escapeReleased() -> Bool {
        let swallowed = session.escapeReleased() == .swallow
        followTheSession()
        return swallowed
    }

    // MARK: Giving up

    /// Closes the ring, if one is open, and runs nothing.
    func cancel() {
        perform(session.cancel())
    }

    private func observeWhatClosesTheRing() {
        let workspace = NSWorkspace.shared.notificationCenter
        // (center, name, whether it can be the late echo of what a place just did)
        let names: [(NotificationCenter, Notification.Name, Bool)] = [
            (workspace, NSWorkspace.activeSpaceDidChangeNotification, true),
            (workspace, NSWorkspace.didActivateApplicationNotification, true),
            (NotificationCenter.default, NSApplication.didChangeScreenParametersNotification, false),
        ]
        for (center, name, followsARun) in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self, self.session.isOpen else { return }
                // The echo of what a place just did keeps the ring, unless the ring is no
                // longer the one the app in front has: pressed again before that app came
                // forward, it is the last app's, and its places are not for this one.
                if followsARun, self.environment.now() - self.lastRun < Self.quietAfterRun,
                   self.environment.choice(self.environment.ring()).ring == self.ring {
                    return
                }
                self.cancel()
            }
            observers.append((center, token))
        }
    }

    // MARK: Carrying out what the rules say

    private func perform(_ commands: [ShortcutRingSession.Command]) {
        guard !commands.isEmpty else {
            followTheSession()
            return
        }
        var closed = false
        var ran: String?
        for command in commands {
            switch command {
            case .open(let centre):
                showGeneration += 1
                let generation = showGeneration
                lastPolledPointer = nil
                // Not inside the event callback this runs in: a panel is made and shown
                // on the main queue's next turn.
                environment.schedule { [weak self] in
                    guard let self, self.showGeneration == generation, self.session.isOpen else { return }
                    let face = self.faceForShowing()
                    // Held or left open, a click on its screen is the ring's.
                    self.presenter.show(
                        face, owner: self.owner, centre: centre, screen: self.screen, lit: self.session.lit, takesClicks: true
                    )
                    self.isShown = true
                    // The panel never takes the focus, so VoiceOver would never hear whose
                    // ring this is: an app's own ring says it once ("Shortcut Ring for
                    // Safari"), before any place it lights.
                    if case .app = self.owner {
                        self.environment.announce(self.owner.accessibilityLabel)
                    }
                }
                // A hand that stopped between the dead zone and twice of it lights its
                // place the moment the first moments are over, not at the timer's next look.
                environment.scheduleAfter(ShortcutRingSession.quickRelease + 0.005) { [weak self] in
                    guard let self, self.showGeneration == generation, self.session.phase == .held else { return }
                    self.perform(self.session.timePassed(to: self.environment.now()))
                }
                // (Which app is in front is not said: the log never names an app.)
                environment.log("Shortcut Ring: opened by \(openedBy)"
                    + (isAppsOwnRing ? ", the own ring of the app in front" : "")
                    + (ring.freezePointer ? ", the pointer is kept still while it is held" : ""))
            case .light(let place):
                presenter.light(place)
                if let place {
                    placeWasLit(place)
                }
            case .close:
                showGeneration += 1
                presenter.hide()
                isShown = false
                closed = true
            case .run(let place):
                let chosen = ring[place]
                guard chosen.runs else { continue }
                ran = Self.logName(of: chosen)
                lastRun = environment.now()
                if let code = hapticCode {
                    lastTick = environment.now()
                    let play = environment.playHaptic
                    environment.schedule { play(.commit, code) }
                }
                // After the panel is gone, and after this callback has returned.
                let run = environment.run
                environment.schedule { run(chosen) }
            }
        }
        if closed {
            let how = closesByAHeldClick ? " (a click during the hold)" : ""
            environment.log((ran.map { "Shortcut Ring: closed, ran \($0)" } ?? "Shortcut Ring: closed, nothing ran") + how)
            if !faceIsComplete {
                // (The app's mark after it.)
                completeFaceLater()
            } else {
                completeAppMarkLater()
            }
        }
        followTheSession()
    }

    /// The face for a ring that is being shown now, without a look on disk: the one made
    /// at a quiet moment if there is one for this ring, else names and plain symbols.
    private func faceForShowing() -> ShortcutRingFace {
        if let face { return face }
        if let prepared = Self.preparedFace(for: ring) {
            face = prepared
            faceIsComplete = true
            return prepared
        }
        let quick = ShortcutRingFace(ring, looksOnDisk: false)
        face = quick
        faceIsComplete = !ring.opensSomething
        return quick
    }

    /// After a ring that was shown without its icons has closed (and after its action was
    /// started): the whole face is made, for the next ring, one place per turn of the main
    /// queue as at launch (`steps`: what the turns before made). A ring that opens
    /// meanwhile ends it; the next close of a ring without its icons begins it again.
    private func completeFaceLater(_ steps: ShortcutRingFace.InSteps? = nil) {
        let wanted = steps?.ring ?? ring
        environment.schedule { [weak self] in
            guard let self, !self.session.isOpen, self.ring == wanted, !self.faceIsComplete else { return }
            var steps = steps ?? ShortcutRingFace.InSteps(wanted)
            steps.step(self.environment.makePlace)
            guard let whole = steps.whole else {
                self.completeFaceLater(steps)
                return
            }
            self.face = whole
            self.faceIsComplete = true
            Self.prepare(whole, for: wanted)
            self.completeAppMarkLater()
        }
    }

    /// After an app's own ring that was shown without the app's mark has closed: the mark
    /// is made on the next turn of the main queue, for the app's next ring, unless a ring
    /// is open by then or the mark was made meanwhile.
    private func completeAppMarkLater() {
        guard let path = ownerPath, Self.preparedAppMark(forPath: path) == nil else { return }
        environment.schedule { [weak self] in
            guard let self, !self.session.isOpen, Self.preparedAppMark(forPath: path) == nil else { return }
            Self.prepare(self.environment.makeAppMark(path), forAppAt: path)
        }
    }

    private func placeWasLit(_ place: Int) {
        let now = environment.now()
        if let code = hapticCode, now - lastTick >= Self.tickSpacing {
            lastTick = now
            let play = environment.playHaptic
            environment.schedule { play(.lockIn, code) }
        }
        // (The face is made when the ring is shown; a place that lights before that, in
        // the same turn as the press, is not announced.)
        if let title = face?.places[place].title {
            let announce = environment.announce
            environment.schedule { announce(title) }
        }
    }

    /// Brings the taps, the panel and the timer in line with the session.
    private func followTheSession() {
        let phase = session.phase
        let held = phase == .held
        // The pointer is kept still for the hold alone: it is let go the moment the hold
        // ends, however it ends, so a ring that stays open has a pointer to click with.
        let freezes = held && ring.freezePointer
        if freezes != holdsPointer {
            holdsPointer = freezes
            if freezes {
                environment.lockPointer()
            } else {
                environment.unlockPointer()
            }
        }
        if held != wasHeld {
            wasHeld = held
            environment.refreshMotionTap()
        }
        let keys = session.needsKeys
        if keys != neededKeys {
            neededKeys = keys
            environment.refreshKeyTap()
        }
        guard phase != timerPhase else { return }
        timerPhase = phase
        stopTimer()
        if phase != .closed {
            if clickWatch == nil {
                clickWatch = environment.watchClicksElsewhere { [weak self] window in
                    self?.clickWentElsewhere(in: window)
                }
            }
        } else if let watch = clickWatch {
            clickWatch = nil
            environment.stopWatchingClicksElsewhere(watch)
        }
        switch phase {
        case .closed:
            break
        case .held:
            presenter.setTakesClicks(true)
            startTimer(every: Self.holdCheckInterval)
        case .latched:
            presenter.setTakesClicks(true)
            startTimer(every: Self.pointerInterval)
            environment.log("Shortcut Ring: left open (the trigger was let go with nothing lit)")
        }
    }

    private func startTimer(every interval: TimeInterval) {
        timer = environment.makeTimer(interval) { [weak self] in
            self?.tick()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: The system's side

    /// What a place ran, for the log: a listed action by its identifier, anything else by
    /// its kind (never a key the user chose, never a path).
    static func logName(of place: ShortcutRingPlace) -> String {
        switch place.content {
        case .nothing: return "nothing"
        case .shortcut(let shortcut): return shortcut.identifier
        case .keyCombination: return "a recorded key combination"
        case .open(let target):
            switch target.kind {
            case .application: return "an app to open"
            case .file: return "a file to open"
            case .script: return "a script"
            }
        }
    }

    /// Runs a place's action as one press, as a direction of Gesture Navigation runs its
    /// action (`ShortcutExecutor.executeOnePress`): resolved from a binding built from the
    /// place (a recorded key combination and what to open are read from the binding, not
    /// from the name), down and then up for a click, a recorded key combination as a listed
    /// shortcut goes out.
    static func run(_ place: ShortcutRingPlace) {
        guard let action = place.resolvedAction else { return }
        ShortcutExecutor.shared.executeOnePress(action)
    }

    /// The ring takes no focus, so VoiceOver would never say what is lit: it is announced.
    /// Nothing happens without VoiceOver.
    static func announce(_ text: String) {
        guard NSWorkspace.shared.isVoiceOverEnabled, let app = NSApp else { return }
        NSAccessibility.post(element: app, notification: .announcementRequested, userInfo: [
            .announcement: text,
            .priority: NSAccessibilityPriorityLevel.medium.rawValue,
        ])
    }
}
