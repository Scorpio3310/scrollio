//
//  ShortcutRingSession.swift
//  Scrollio
//
//  The Shortcut Ring's rules as a state machine: what the trigger, the pointer, a click and
//  Esc mean while the ring is closed, held open or left open. Pure: it is told what happened
//  and when, and answers with what to do (`Command`); the panel, the timers, the pulses and
//  the actions are `ShortcutRingController`'s.
//
//  Two ways to choose, both always there:
//
//  - Hold. The trigger goes down: the ring opens at the pointer. The hand's movement since
//    the press chooses by its direction, once it is past the dead zone; the pointer need
//    not land on a place, and it need not be able to move at all (the edge of a screen).
//    The trigger goes up with a place lit: that place's action runs. Up in the middle
//    after a place had been lit: the ring closes and nothing runs.
//  - Click. The trigger goes up and nothing was ever lit, however long the press lasted:
//    the ring stays open. Once the pointer has moved a little (`latchSlack`: a ring that
//    was drawn away from the pointer at a screen edge must not light, or run, the place
//    it happens to stand under) the pointer chooses by where it is: a click on a place
//    runs its action (when the button comes up, so that nothing is held while the action
//    runs). A click anywhere else (the middle, an empty place, outside), another button,
//    Esc or the trigger again close the ring and run nothing, and so do `idleLimit`
//    seconds without the pointer moving. This is the way that suits a trigger that cannot
//    be held: a keystroke another app sends as down and up at once.
//
//  What is lit when the trigger comes up is what runs, at any speed. No clock decides
//  between the two ways: a firm press of a stiff button can last as long as a short hold.
//  What a clock does guard against is the jerk a press gives the mouse: the movement of
//  the first `pressGrace` seconds is not counted, and for the first `quickRelease`
//  seconds a place lights only once the hand went `quickReleaseReach` far, twice the
//  dead zone (a hand that stopped short of that lights its place when that time is over).
//
//  An empty place never lights and never runs.
//  The ring is closed before an action runs: `.close` always comes before `.run`. A
//  release that is made up (the mouse went away mid-hold), a hold longer than `holdLimit`
//  and `cancel` close the ring and run nothing.
//

import CoreGraphics
import Foundation

struct ShortcutRingSession {

    enum Phase: Equatable {
        case closed
        /// The trigger is down: the hand's movement since the press chooses.
        case held
        /// The trigger was let go with nothing lit and the ring stands open: the pointer's
        /// place and a click choose.
        case latched
    }

    enum Command: Equatable {
        /// Show the ring with its middle at `centre` (event coordinates).
        case open(centre: CGPoint)
        /// Another place is lit, or none (nil).
        case light(Int?)
        /// Take the ring off the screen. Always before `.run`.
        case close
        /// Run the action of this place.
        case run(Int)
    }

    /// What becomes of Esc.
    enum Answer: Equatable {
        /// It was the ring's: the app in front does not get it.
        case swallow
        /// Not the ring's: it goes on as if there were no ring.
        case pass
    }

    /// What a click that is down will do when it comes up.
    private enum Press: Equatable {
        case choose(Int)
        case dismiss
    }

    /// The movement of the first moments after the press is the press itself pushing
    /// the mouse: it is not counted.
    static let pressGrace: TimeInterval = 0.04
    /// For this long after the press …
    static let quickRelease: TimeInterval = 0.2
    /// … a place lights only when the hand moved at least this far (later: the dead zone).
    static let quickReleaseReach: CGFloat = ShortcutRingGeometry.deadZone * 2
    /// A ring that was left open lights nothing, and a click chooses nothing, until the
    /// pointer has moved this far from where it stood.
    static let latchSlack: CGFloat = 4
    /// A ring left open closes after this long without the pointer moving.
    static let idleLimit: TimeInterval = 10
    /// A held ring whose release never comes closes after this long (the limit of a
    /// gesture hold, for the same reason: a button-up can get lost).
    static let holdLimit: TimeInterval = MouseGesturePointerLock.safetyTimeout

    private(set) var phase = Phase.closed
    /// The middle of the ring as it is drawn (event coordinates).
    private(set) var centre = CGPoint.zero
    /// The lit place.
    private(set) var lit: Int?
    /// The hand's movement since the press (the hold way).
    private(set) var travel = CGPoint.zero

    /// Which places hold an action that runs. Fixed while the ring is open.
    private var filled: [Bool] = []
    private var pressTime: TimeInterval = 0
    /// When the pointer last moved (the click way's idle limit counts from here).
    private var lastMovement: TimeInterval = 0
    /// A place was lit at some point of this hold.
    private var hasLitAPlace = false
    private var pointer = CGPoint.zero
    /// Where the pointer stood when the ring was left open, until it has moved away.
    private var latchPointer: CGPoint?
    /// The pointer buttons that are down on the ring, each with what it will do.
    private var pressedButtons: [Int: Press] = [:]
    /// Esc's press closed the ring: its release is the ring's too, so that the app in
    /// front never sees an up without its down.
    private var swallowsEscapeRelease = false

    var isOpen: Bool {
        return phase != .closed
    }

    /// Whether the session has to see the keyboard: Esc while the ring is open, and
    /// after Esc closed it until that key is up.
    var needsKeys: Bool {
        return isOpen || swallowsEscapeRelease
    }

    /// A place's click is down: it stays lit until the button is up.
    private var pressedPlace: Int? {
        for press in pressedButtons.values {
            if case .choose(let place) = press { return place }
        }
        return nil
    }

    // MARK: The trigger

    /// The trigger went down (never a key's auto-repeat: the caller drops those).
    /// `pointer` and `screen` (the frame of the screen the pointer is on) are in event
    /// coordinates; `filled` says which places hold an action that runs.
    mutating func triggerPressed(at time: TimeInterval, pointer: CGPoint, screen: CGRect, filled: [Bool]) -> [Command] {
        switch phase {
        case .held:
            // A second trigger, or a down that came twice: the hold goes on.
            return []
        case .latched:
            // The trigger again closes a ring that was left open.
            return close()
        case .closed:
            phase = .held
            self.filled = filled
            self.pointer = pointer
            pressTime = time
            lastMovement = time
            travel = .zero
            hasLitAPlace = false
            lit = nil
            latchPointer = nil
            pressedButtons.removeAll()
            centre = ShortcutRingGeometry.centre(forPointer: pointer, in: screen)
            return [.open(centre: centre)]
        }
    }

    /// The trigger came up. `isMadeUp`: not a real release (the mouse went away or was
    /// set up again mid-hold): the ring closes and nothing runs.
    mutating func triggerReleased(at time: TimeInterval, isMadeUp: Bool = false) -> [Command] {
        guard phase == .held else { return [] }
        guard !isMadeUp else { return close() }
        // What is lit runs.
        if let place = lit {
            return close() + [.run(place)]
        }
        if hasLitAPlace {
            // Back in the middle (or on an empty place) after a place was lit: nothing.
            return close()
        }
        // Nothing was chosen: the ring stays open for the pointer and a click.
        phase = .latched
        lastMovement = time
        latchPointer = pointer
        return []
    }

    /// The place the hand's movement means at `time` of a hold: by direction, past the
    /// dead zone, and in the first moments after the press only past twice the dead zone.
    private func placeOfTravel(at time: TimeInterval) -> Int? {
        let zone = time - pressTime < Self.quickRelease ? Self.quickReleaseReach : ShortcutRingGeometry.deadZone
        return ShortcutRingGeometry.place(forOffset: travel, deadZone: zone, current: lit)
            .flatMap { isFilled($0) ? $0 : nil }
    }

    private mutating func relightForTravel(at time: TimeInterval) -> [Command] {
        let place = placeOfTravel(at: time)
        if place != nil {
            hasLitAPlace = true
        }
        return relight(place)
    }

    // MARK: The pointer

    /// The mouse moved by `delta` and the pointer is now at `location`.
    mutating func pointerMoved(by delta: CGPoint, to location: CGPoint, at time: TimeInterval) -> [Command] {
        pointer = location
        switch phase {
        case .closed:
            return []
        case .held:
            guard time - pressTime >= Self.pressGrace else { return [] }
            travel = ShortcutRingGeometry.travel(travel, movedBy: delta)
            return relightForTravel(at: time)
        case .latched:
            lastMovement = time
            if let stood = latchPointer {
                guard hypot(location.x - stood.x, location.y - stood.y) >= Self.latchSlack else { return [] }
                latchPointer = nil
            }
            // A place whose click is down stays lit until the button is up.
            guard pressedPlace == nil else { return [] }
            return relight(placeUnderPointer())
        }
    }

    // MARK: Clicks and Esc

    /// A pointer button went down on the ring's panel at `location`: 0 the left button,
    /// anything else another one. Nothing happens yet: a click acts when it comes up.
    mutating func buttonPressed(_ button: Int, at location: CGPoint) -> [Command] {
        guard phase == .latched else { return [] }
        pointer = location
        // Any other button closes the ring, and so does a click before the pointer has
        // moved at all since the ring was left open (it was not aimed at anything).
        guard button == 0, latchPointer == nil,
              case .place(let place) = ShortcutRingGeometry.target(at: location, centre: centre, current: lit),
              isFilled(place) else {
            // The middle, an empty place, outside: a click anywhere but on a shortcut closes.
            pressedButtons[button] = .dismiss
            return relight(pressedPlace)
        }
        pressedButtons[button] = .choose(place)
        return relight(place)
    }

    /// A pointer button came up: what its press meant happens now.
    mutating func buttonReleased(_ button: Int) -> [Command] {
        guard let press = pressedButtons.removeValue(forKey: button), phase == .latched else { return [] }
        switch press {
        case .choose(let place):
            return close() + [.run(place)]
        case .dismiss:
            return close()
        }
    }

    /// Esc went down.
    mutating func escapePressed() -> (answer: Answer, commands: [Command]) {
        guard isOpen else { return (.pass, []) }
        swallowsEscapeRelease = true
        return (.swallow, close())
    }

    /// Esc came up.
    mutating func escapeReleased() -> Answer {
        guard swallowsEscapeRelease else { return .pass }
        swallowsEscapeRelease = false
        return .swallow
    }

    // MARK: Giving up

    /// Time went by: a held ring past `holdLimit`, or a ring left open for `idleLimit`
    /// without the pointer moving, closes. Nothing runs. And a hand that stopped between
    /// the dead zone and twice of it lights its place once the first moments are over.
    mutating func timePassed(to time: TimeInterval) -> [Command] {
        switch phase {
        case .closed:
            return []
        case .held:
            return time - pressTime >= Self.holdLimit ? close() : relightForTravel(at: time)
        case .latched:
            return time - lastMovement >= Self.idleLimit ? close() : []
        }
    }

    /// The ring goes away and nothing runs: the event taps stopped, another button's
    /// action ran, the Space, the front app or the screens changed. Nothing is waited for
    /// afterwards.
    mutating func cancel() -> [Command] {
        swallowsEscapeRelease = false
        return close()
    }

    // MARK: Private

    private func isFilled(_ place: Int) -> Bool {
        return filled.indices.contains(place) && filled[place]
    }

    private func placeUnderPointer() -> Int? {
        guard case .place(let place) = ShortcutRingGeometry.target(at: pointer, centre: centre, current: lit),
              isFilled(place) else { return nil }
        return place
    }

    private mutating func relight(_ place: Int?) -> [Command] {
        guard place != lit else { return [] }
        lit = place
        return [.light(place)]
    }

    private mutating func close() -> [Command] {
        guard isOpen else { return [] }
        phase = .closed
        lit = nil
        pressedButtons.removeAll()
        travel = .zero
        return [.close]
    }
}
