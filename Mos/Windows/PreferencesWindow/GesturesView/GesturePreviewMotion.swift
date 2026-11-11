//
//  GesturePreviewMotion.swift
//  Mos
//  The script of the picture at the top of the Gestures tab (GesturePreviewView): what the
//  hand does with the mouse and what the little desktop does in answer, at any moment of
//  the loop. Pure values, no views and no clock.
//
//  A loop is a few legs. A leg is one hold of the gesture button: the button goes down,
//  the mouse moves one way (or not at all, for Click), the button comes up, the mouse
//  glides back. "Follow the hand" moves the desktops with the mouse while the button is
//  held; "one action per hold" runs the action once, when the mouse has moved far enough.
//  The desktops are an endless row of two alternating wallpapers, so a slide always has a
//  neighbour to go to and the loop can end on the picture it started with.
//
//  Nothing here runs an action: the effects are only numbers the artwork draws.
//

import Foundation
import CoreGraphics

/// What an action looks like on the little desktop.
enum GesturePreviewEffect: Equatable {
    /// "No Action": the hand moves and nothing happens.
    case none
    /// Mission Control: the windows shrink into an overview and the Spaces bar comes down.
    case missionControl
    /// Launchpad (Apps on macOS 26): a grid of app icons over the desktop.
    case appGrid
    /// Move a Space: the desktop slides once, to its neighbour on that side.
    case space(MouseGestureDirection)
    /// Anything else: a short pulse with the action's icon in the middle of the desktop.
    case pulse(symbolName: String)

    /// The effect of a stored action identifier ("" is "No Action").
    init(action identifier: String) {
        switch identifier {
        case "":
            self = .none
        case SystemShortcut.missionControl.identifier:
            self = .missionControl
        case SystemShortcut.appExpose.identifier:
            // Shown as "Launchpad" in the menus: the F4 key that opens the app grid.
            self = .appGrid
        case SystemShortcut.moveSpaceLeft.identifier:
            self = .space(.left)
        case SystemShortcut.moveSpaceRight.identifier:
            self = .space(.right)
        default:
            self = .pulse(symbolName: SystemShortcut.getShortcut(named: identifier)?.symbolName ?? Self.fallbackSymbol)
        }
    }

    /// For an action the shortcut table does not know (an "Open…" target, say).
    static let fallbackSymbol = "bolt.fill"

    /// Desktops the row moves when the action runs: −1 to the neighbour on the left, +1 to
    /// the one on the right.
    var shift: Int {
        switch self {
        case .space(.left): return -1
        case .space(.right): return 1
        default: return 0
        }
    }

    /// How long the effect takes from the moment the action runs. Every effect has ended
    /// (the overview and the grid are closed again) after this time.
    var duration: TimeInterval {
        switch self {
        case .none: return 0
        case .missionControl, .appGrid:
            return GesturePreviewLoop.overlayIn + GesturePreviewLoop.overlayHold + GesturePreviewLoop.overlayOut
        case .space: return GesturePreviewLoop.slideDuration
        case .pulse:
            return GesturePreviewLoop.pulseIn + GesturePreviewLoop.pulseHold + GesturePreviewLoop.pulseOut
        }
    }
}

/// What the preview shows: the settings, with the mode in effect, and the row it is about.
struct GesturePreviewScene: Equatable {
    /// The gesture settings; `mode` is the mode in effect (discrete where "Follow the hand"
    /// is not available, whatever is stored).
    var gesture = MouseGestureSettings.default
    /// The row under the pointer or with the keyboard focus. nil: left and right in turn.
    var focus: MouseGestureSettingsControls.Slot?

    init(gesture: MouseGestureSettings = .default, focus: MouseGestureSettingsControls.Slot? = nil) {
        self.gesture = gesture
        self.focus = focus
    }
}

/// One hold of the gesture button.
struct GesturePreviewLeg: Equatable {

    enum Kind: Equatable {
        /// "Follow the hand", sideways: the desktops move with the mouse while it is held.
        case follow
        /// One action per hold: the mouse moves one way and the action runs once.
        case move
        /// The button is pressed and let go without moving: the Click action runs.
        case click
    }

    let kind: Kind
    /// The way the hand moves the mouse; nil for a click.
    let direction: MouseGestureDirection?
    /// What the action shows (follow: nothing, the slide is the hand's).
    let effect: GesturePreviewEffect
    /// Desktops the row has moved by the end of the leg: −1, 0 or +1.
    let shift: Int
    /// Seconds from the start of the leg.
    let pressTime: TimeInterval
    let releaseTime: TimeInterval
    /// When the action runs; nil when it does nothing (follow, "No Action").
    let fireTime: TimeInterval?
    let length: TimeInterval
    /// The moment Reduce Motion shows: what the action does at its clearest.
    let stillTime: TimeInterval
    /// The moment the hand is at its clearest: the mouse moved, the button held. Reduce
    /// Motion shows the mouse at this moment next to the desktop at `stillTime`, so the one
    /// picture holds cause and effect.
    let holdTime: TimeInterval

    /// A sideways hold in "Follow the hand". Moving left brings in the desktop on the right
    /// (the desktops move with the hand), unless left and right are inverted.
    static func follow(_ direction: MouseGestureDirection, invert: Bool) -> GesturePreviewLeg {
        let towardsLeft = direction == .left
        let shift = (towardsLeft != invert) ? 1 : -1
        typealias L = GesturePreviewLoop
        return GesturePreviewLeg(
            kind: .follow, direction: direction, effect: .none, shift: shift,
            pressTime: L.pressTime, releaseTime: L.followRelease, fireTime: nil,
            length: L.followReturnEnd + L.rest,
            stillTime: (L.followFirstStopEnd + L.followSecondStart) / 2,
            holdTime: (L.followFirstStopEnd + L.followSecondStart) / 2
        )
    }

    /// A hold that moves the mouse one way and runs `effect` once on the way.
    static func move(_ direction: MouseGestureDirection, effect: GesturePreviewEffect) -> GesturePreviewLeg {
        typealias L = GesturePreviewLoop
        let fire = L.moveStart + L.activationFraction * L.moveDuration
        let fires = effect != .none
        return GesturePreviewLeg(
            kind: .move, direction: direction, effect: effect, shift: effect.shift,
            pressTime: L.pressTime, releaseTime: L.moveRelease, fireTime: fires ? fire : nil,
            length: max(L.moveReturnEnd, fire + effect.duration) + L.rest,
            stillTime: Self.stillTime(fire: fire, effect: effect, fallback: (L.moveEnd + L.moveRelease) / 2),
            holdTime: (L.moveEnd + L.moveRelease) / 2
        )
    }

    /// A press and release without moving: Click runs at the release.
    static func click(effect: GesturePreviewEffect) -> GesturePreviewLeg {
        typealias L = GesturePreviewLoop
        let fires = effect != .none
        return GesturePreviewLeg(
            kind: .click, direction: nil, effect: effect, shift: effect.shift,
            pressTime: L.pressTime, releaseTime: L.clickRelease, fireTime: fires ? L.clickRelease : nil,
            length: max(L.clickRelease + L.pressPulseDuration, L.clickRelease + effect.duration) + L.rest,
            stillTime: Self.stillTime(fire: L.clickRelease, effect: effect, fallback: (L.pressTime + L.clickRelease) / 2),
            holdTime: (L.pressTime + L.buttonTravel + L.clickRelease) / 2
        )
    }

    /// The overview, the grid or the pulse fully shown; a slide half-way.
    private static func stillTime(fire: TimeInterval, effect: GesturePreviewEffect, fallback: TimeInterval) -> TimeInterval {
        typealias L = GesturePreviewLoop
        switch effect {
        case .none: return fallback
        case .missionControl, .appGrid: return fire + L.overlayIn + L.overlayHold / 2
        case .space: return fire + L.slideDuration / 2
        case .pulse: return fire + L.pulseIn + L.pulseHold / 2
        }
    }
}

/// The demo loop and the picture at any moment of it.
struct GesturePreviewLoop {

    // MARK: - Timing (seconds from the start of a leg)

    /// The button goes down after a short rest, and takes this long to go down or up.
    static let pressTime: TimeInterval = 0.4
    static let buttonTravel: TimeInterval = 0.08
    /// The ring around the button when it goes down.
    static let pressPulseDuration: TimeInterval = 0.4
    /// The rest at the end of every leg.
    static let rest: TimeInterval = 0.5

    /// One action per hold: the mouse moves out, waits, the button comes up, it glides back.
    static let moveStart: TimeInterval = 0.55
    static let moveDuration: TimeInterval = 0.45
    static var moveEnd: TimeInterval { return moveStart + moveDuration }
    static let moveRelease: TimeInterval = 1.4
    static let moveReturnStart: TimeInterval = 1.5
    static let moveReturnEnd: TimeInterval = 1.9
    /// The action runs this far into the movement: the mouse has then passed the
    /// recognizer's activation distance, drawn as `activationShare` of the way.
    static let activationFraction = 0.6
    /// How far the mouse moves in a discrete hold (points of the device card).
    static let horizontalReach: CGFloat = 22
    static let verticalReach: CGFloat = 12

    /// Click: pressed and let go; the action runs at the release.
    static let clickRelease: TimeInterval = 0.75

    /// Follow the hand: half-way, a stop, on to most of the way, let go; the desktops
    /// settle on the next one by themselves, as a real swipe does.
    static let followFirstStart: TimeInterval = 0.55
    static let followFirstStopEnd: TimeInterval = 1.1
    static let followSecondStart: TimeInterval = 1.7
    static let followRelease: TimeInterval = 2.0
    static let followSettle: TimeInterval = 0.35
    static let followReturnStart: TimeInterval = 2.1
    static let followReturnEnd: TimeInterval = 2.55
    /// The hand stops at these shares of a desktop.
    static let followFirstStop = 0.5
    static let followReleaseShare = 0.8
    /// Mouse travel for one whole desktop at tracking speed 1 (points), and the range it is
    /// kept in so that the mouse still visibly moves at 3× and stays in its card at 0.5×.
    static let followTravelAtSpeed1: CGFloat = 30
    static let followTravelRange: ClosedRange<CGFloat> = 14...56

    // Effects
    static let overlayIn: TimeInterval = 0.4
    static let overlayHold: TimeInterval = 1.0
    static let overlayOut: TimeInterval = 0.35
    static let slideDuration: TimeInterval = 0.5
    static let pulseIn: TimeInterval = 0.15
    static let pulseHold: TimeInterval = 0.5
    static let pulseOut: TimeInterval = 0.3

    /// The pointer moves this many points per point of mouse travel when it is not frozen.
    static let pointerGain: CGFloat = 1

    // MARK: - The picture at one moment

    struct Frame: Equatable {
        /// Which leg is playing.
        var leg: Int
        /// Where the mouse is from its place in the middle of the card (points, y down).
        var mouseOffset: CGPoint
        /// 0: the gesture button is up, 1: held.
        var buttonDepth: Double
        /// 1 when the button has just gone down, falling to 0.
        var pressPulse: Double
        /// 0…1: how much the arrow of the movement shows.
        var arrow: Double
        /// The way the mouse moves in this leg; nil for a click.
        var direction: MouseGestureDirection?
        /// The desktop on screen: 0 the first, 1 the second, fractions while they slide (0..<2).
        var desktop: Double
        /// Follow the hand: how far the hold has moved the desktops (signed, in desktops).
        var swipeProgress: Double
        /// 0…1: the Mission Control overview, the app grid and the pulse.
        var overview: Double
        var appGrid: Double
        var pulse: Double
        var pulseSymbol: String?
        /// Where the pointer is from its place on the desktop (points, y down).
        var pointerOffset: CGPoint
        /// Actions that ran since the loop began.
        var actionsFired: Int
        /// Nothing moves: the picture can sit on whole pixels.
        var isAtRest: Bool
    }

    let scene: GesturePreviewScene
    let legs: [GesturePreviewLeg]
    /// When each leg starts (seconds from the start of the loop).
    let starts: [TimeInterval]
    let length: TimeInterval
    /// Desktops travelled per point of mouse travel in "Follow the hand".
    let followTravel: CGFloat

    init(scene: GesturePreviewScene) {
        self.scene = scene
        followTravel = Self.followTravel(trackingSpeed: scene.gesture.trackingSpeed)
        var legs = Self.legs(for: scene)
        // The row must come back to the wallpaper it started on.
        if legs.reduce(0, { $0 + $1.shift }) % 2 != 0 {
            legs += legs
        }
        self.legs = legs
        var starts: [TimeInterval] = []
        var time: TimeInterval = 0
        for leg in legs {
            starts.append(time)
            time += leg.length
        }
        self.starts = starts
        length = time
    }

    /// Mouse travel for one desktop: less at a higher tracking speed.
    static func followTravel(trackingSpeed: Double) -> CGFloat {
        let speed = trackingSpeed.isFinite && trackingSpeed > 0 ? trackingSpeed : MouseGestureSettings.defaultTrackingSpeed
        let travel = followTravelAtSpeed1 / CGFloat(speed)
        return min(followTravelRange.upperBound, max(followTravelRange.lowerBound, travel))
    }

    /// The holds the scene demonstrates.
    static func legs(for scene: GesturePreviewScene) -> [GesturePreviewLeg] {
        let gesture = scene.gesture
        func hand(_ direction: MouseGestureDirection) -> GesturePreviewLeg {
            let isSideways = direction == .left || direction == .right
            if isSideways && gesture.mode == .interactive {
                return .follow(direction, invert: gesture.invertHorizontal)
            }
            return .move(direction, effect: GesturePreviewEffect(action: gesture.actionIdentifier(for: direction)))
        }
        switch scene.focus {
        case nil:
            return [hand(.left), hand(.right)]
        case .up?:
            return [hand(.up)]
        case .down?:
            return [hand(.down)]
        case .click?:
            return [.click(effect: GesturePreviewEffect(action: gesture.clickAction))]
        case .left?, .right?:
            // The row's own action: with left and right inverted the other hand runs it.
            let row: MouseGestureDirection = scene.focus == .left ? .left : .right
            let physical = gesture.invertHorizontal && gesture.mode == .discrete ? row.opposite : row
            return [hand(physical)]
        }
    }

    // MARK: - Frames

    /// The picture `time` seconds into the loop; times beyond its length wrap around.
    func frame(at time: TimeInterval) -> Frame {
        var time = time.isFinite && length > 0 ? time.truncatingRemainder(dividingBy: length) : 0
        if time < 0 { time += length }
        var index = 0
        while index + 1 < legs.count, time >= starts[index + 1] {
            index += 1
        }
        let shiftsBefore = legs.prefix(index).reduce(0) { $0 + $1.shift }
        let firedBefore = legs.prefix(index).filter { $0.fireTime != nil }.count
        return frame(ofLeg: index, at: time - starts[index], position: Double(shiftsBefore), fired: firedBefore)
    }

    /// The picture without motion (Reduce Motion): the first hold at its clearest, the hand
    /// still holding the button while the desktop shows what the action does.
    var stillFrame: Frame {
        guard let leg = legs.first else { return frame(at: 0) }
        var frame = self.frame(at: leg.stillTime)
        let hand = self.frame(at: leg.holdTime)
        frame.mouseOffset = hand.mouseOffset
        frame.buttonDepth = hand.buttonDepth
        frame.arrow = hand.arrow
        frame.pointerOffset = hand.pointerOffset
        frame.pressPulse = 0
        frame.isAtRest = true
        return frame
    }

    private func frame(ofLeg index: Int, at t: TimeInterval, position base: Double, fired: Int) -> Frame {
        let leg = legs[index]
        let buttonDepth = Self.smoothstep((t - leg.pressTime) / Self.buttonTravel)
            - Self.smoothstep((t - leg.releaseTime) / Self.buttonTravel)
        // A ring when the button goes down, and for a click again when it comes up.
        var pressPulse = Self.ring(since: t - leg.pressTime)
        if leg.kind == .click {
            pressPulse = max(pressPulse, Self.ring(since: t - leg.releaseTime))
        }

        // How far along its way the mouse is (0 at its place, 1 at `reach`).
        let reach: CGFloat
        let share: Double
        var swipe = 0.0
        var position = base
        switch leg.kind {
        case .follow:
            reach = followTravel
            share = Self.followShare(at: t)
            let progress = t <= leg.releaseTime
                ? share
                : Self.followReleaseShare + (1 - Self.followReleaseShare) * Self.easeOut((t - leg.releaseTime) / Self.followSettle)
            swipe = Double(leg.shift) * progress
            position += swipe
        case .move:
            reach = leg.direction == .up || leg.direction == .down ? Self.verticalReach : Self.horizontalReach
            share = Self.smoothstep((t - Self.moveStart) / Self.moveDuration)
                - Self.smoothstep((t - Self.moveReturnStart) / (Self.moveReturnEnd - Self.moveReturnStart))
        case .click:
            reach = 0
            share = 0
        }
        let offset = Self.point(towards: leg.direction, distance: reach * CGFloat(share))

        // The action, from the moment it runs.
        var frame = Frame(
            leg: index, mouseOffset: offset, buttonDepth: buttonDepth, pressPulse: pressPulse,
            arrow: leg.direction == nil ? 0 : buttonDepth * min(1, share / 0.3),
            direction: leg.direction, desktop: 0, swipeProgress: swipe,
            overview: 0, appGrid: 0, pulse: 0, pulseSymbol: nil,
            pointerOffset: scene.gesture.freezePointer
                ? .zero
                : CGPoint(x: offset.x * Self.pointerGain, y: offset.y * Self.pointerGain),
            actionsFired: fired, isAtRest: false
        )
        var effectRunning = false
        if let fire = leg.fireTime, t >= fire {
            frame.actionsFired += 1
            let since = t - fire
            effectRunning = since < leg.effect.duration
            switch leg.effect {
            case .none:
                break
            case .missionControl:
                frame.overview = Self.envelope(since, in: Self.overlayIn, hold: Self.overlayHold, out: Self.overlayOut)
            case .appGrid:
                frame.appGrid = Self.envelope(since, in: Self.overlayIn, hold: Self.overlayHold, out: Self.overlayOut)
            case .space:
                position += Double(leg.effect.shift) * Self.easeInOut(since / Self.slideDuration)
            case .pulse(let symbol):
                frame.pulse = Self.envelope(since, in: Self.pulseIn, hold: Self.pulseHold, out: Self.pulseOut)
                frame.pulseSymbol = symbol
            }
        }
        frame.desktop = Self.wrappedDesktop(position)

        let buttonMoving = (t > leg.pressTime && t < leg.pressTime + Self.buttonTravel)
            || (t > leg.releaseTime && t < leg.releaseTime + Self.buttonTravel)
        let settling = leg.kind == .follow && t > leg.releaseTime && t < leg.releaseTime + Self.followSettle
        let mouseMoving: Bool
        switch leg.kind {
        case .follow:
            mouseMoving = (t > Self.followFirstStart && t < Self.followFirstStopEnd)
                || (t > Self.followSecondStart && t < Self.followRelease)
                || (t > Self.followReturnStart && t < Self.followReturnEnd)
        case .move:
            mouseMoving = (t > Self.moveStart && t < Self.moveEnd)
                || (t > Self.moveReturnStart && t < Self.moveReturnEnd)
        case .click:
            mouseMoving = false
        }
        frame.isAtRest = !(buttonMoving || settling || mouseMoving || effectRunning || pressPulse > 0)
        return frame
    }

    /// 1 at the moment, falling to 0 over `pressPulseDuration`.
    static func ring(since time: TimeInterval) -> Double {
        return time >= 0 ? max(0, 1 - time / pressPulseDuration) : 0
    }

    /// Follow the hand: the mouse's share of one desktop's travel at `t`.
    static func followShare(at t: TimeInterval) -> Double {
        if t <= followFirstStopEnd {
            return followFirstStop * smoothstep((t - followFirstStart) / (followFirstStopEnd - followFirstStart))
        }
        if t <= followRelease {
            let step = smoothstep((t - followSecondStart) / (followRelease - followSecondStart))
            return followFirstStop + (followReleaseShare - followFirstStop) * step
        }
        return followReleaseShare * (1 - smoothstep((t - followReturnStart) / (followReturnEnd - followReturnStart)))
    }

    /// A position in desktops as the picture shows it: the two wallpapers alternate, so only
    /// the position modulo 2 matters.
    static func wrappedDesktop(_ position: Double) -> Double {
        guard position.isFinite else { return 0 }
        var wrapped = position.truncatingRemainder(dividingBy: 2)
        if wrapped < 0 { wrapped += 2 }
        // −0.0000001 must not show as 1.9999999.
        if wrapped > 2 - 1e-9 { wrapped = 0 }
        return wrapped
    }

    static func point(towards direction: MouseGestureDirection?, distance: CGFloat) -> CGPoint {
        switch direction {
        case .left?: return CGPoint(x: -distance, y: 0)
        case .right?: return CGPoint(x: distance, y: 0)
        case .up?: return CGPoint(x: 0, y: -distance)
        case .down?: return CGPoint(x: 0, y: distance)
        case nil: return .zero
        }
    }

    /// Up over `in`, held for `hold`, down over `out`.
    static func envelope(_ time: TimeInterval, in rise: TimeInterval, hold: TimeInterval, out fall: TimeInterval) -> Double {
        guard time >= 0 else { return 0 }
        return easeInOut(time / rise) - easeInOut((time - rise - hold) / fall)
    }

    static func smoothstep(_ progress: Double) -> Double {
        let p = min(1, max(0, progress.isFinite ? progress : 0))
        return p * p * (3 - 2 * p)
    }

    static func easeOut(_ progress: Double) -> Double {
        let p = min(1, max(0, progress.isFinite ? progress : 0))
        return 1 - (1 - p) * (1 - p) * (1 - p)
    }

    static func easeInOut(_ progress: Double) -> Double {
        let p = min(1, max(0, progress.isFinite ? progress : 0))
        return p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2
    }
}

extension MouseGestureDirection {
    var opposite: MouseGestureDirection {
        switch self {
        case .up: return .down
        case .down: return .up
        case .left: return .right
        case .right: return .left
        }
    }
}
