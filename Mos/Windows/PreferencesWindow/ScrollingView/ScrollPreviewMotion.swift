//
//  ScrollPreviewMotion.swift
//  Mos
//  The maths behind the demo at the top of the Scrolling tab (ScrollPreviewView): where
//  the little page is at any moment after a script of wheel clicks, and the loop the demo
//  plays. Pure values, no views and no clock.
//
//  The page is moved by the scroll engine's own functions (the Duration factor, its
//  frame-rate conversion, the filter and its weight), frame by frame as ScrollPoster does,
//  so the demo cannot drift from what the wheel really does.
//

import Foundation
import CoreGraphics

/// Where the demo page is after a script of wheel clicks.
struct ScrollPreviewMotion {

    /// One click of the wheel.
    struct Click: Equatable {
        /// Seconds from the start of the script.
        var time: TimeInterval
        /// +1: rolled towards the hand (down the page, unless reversed); −1: away from it.
        var turn: Double
    }

    /// Real pixels one click scrolls at speed 1 (the engine's step).
    static let pixelsPerClick = 33.6
    /// What the "scroll faster" key multiplies a click by.
    static let fasterFactor = 5.0
    /// Demo points per real pixel. With it three clicks move the page 7 pt at speed 1,
    /// 19 pt at the default 2.7 and 71 pt at speed 10; five times the default (95 pt)
    /// still fits into `travel`.
    static let pointsPerPixel = 0.07
    /// How far the demo page can scroll, in points: it is this much longer than its window.
    static let travel = 104.0
    /// The slider scale of `Scene.duration`.
    static let durationRange = 0.0...5.0
    /// Step of the simulation. The engine's factors are defined per 60 Hz frame and
    /// converted to the real frame interval; the same conversion is used here.
    static let frameInterval = 1.0 / 120.0
    /// The motion counts as finished when less than this is left to go (points; an eighth
    /// of a point is a quarter of a pixel on a Retina display).
    static let restDistance = 0.125
    /// No script runs longer than this after its last click (guards against a factor of 0).
    static let longestTail: TimeInterval = 12

    let scene: ScrollPreviewView.Scene
    let clicks: [Click]
    /// Offsets along the scrolling axis, 0...`travel`.
    let start: Double
    let end: Double
    /// When the page has arrived (seconds from the start of the script).
    let settleTime: TimeInterval

    /// Eased motion: the offset after every simulated frame; `samples[i]` is at i × frameInterval.
    private let samples: [Double]
    /// Jumping motion: the offset from each click on.
    private let jumps: [(time: TimeInterval, offset: Double)]

    /// - Parameter start: offset along the scrolling axis before the first click. nil: the
    ///   end of the page that leaves room for the first click (see `restingStart`).
    init(scene: ScrollPreviewView.Scene, clicks: [Click], start: Double? = nil) {
        let clicks = clicks.sorted { $0.time < $1.time }
        let distance = Self.clickDistance(for: scene)
        let origin = Self.clamped(start ?? Self.restingStart(for: scene, firstTurn: clicks.first?.turn ?? 1))
        self.scene = scene
        self.clicks = clicks
        self.start = origin

        guard Self.isEased(scene) else {
            var offset = origin
            var jumps: [(time: TimeInterval, offset: Double)] = []
            for click in clicks {
                offset = Self.clamped(offset + click.turn * distance * Self.pointsPerPixel)
                jumps.append((click.time, offset))
            }
            self.jumps = jumps
            self.samples = []
            self.end = offset
            self.settleTime = clicks.last?.time ?? 0
            return
        }

        // One frame of ScrollPoster.advanceMotionLocked, without the parts that depend on
        // how fast the wheel turns: the target takes the clicks, the position goes a
        // fraction of the way there, and the filter rounds the start of that step off.
        let interval = Self.frameInterval
        let duration = Self.transition(forDuration: scene.duration)
        let transition = ScrollMotion.transition(duration, frameInterval: interval)
        let weight = ScrollMotion.transition(ScrollMotion.filterWeight(forTransition: duration), frameInterval: interval)
        let filter = ScrollFilter()
        let lastClick = clicks.last?.time ?? 0

        var target = 0.0        // real pixels asked for by the wheel
        var position = 0.0      // real pixels the smoothing has reached
        var delivered = 0.0     // real pixels handed to the page
        var offset = origin
        var samples = [origin]
        var next = 0
        while true {
            let time = Double(samples.count) * interval
            while next < clicks.count, clicks[next].time <= time {
                target += clicks[next].turn * distance
                next += 1
            }
            let frame = (target - position) * transition
            position += frame
            let output = filter.fill(with: (y: frame, x: 0), weight: weight).y
            delivered += output
            // The page stops at its ends, as a real one does.
            offset = Self.clamped(offset + output * Self.pointsPerPixel)
            samples.append(offset)
            let remaining = abs(target - delivered) * Self.pointsPerPixel
            if next == clicks.count && remaining < Self.restDistance { break }
            if time > lastClick + Self.longestTail { break }
        }
        self.samples = samples
        self.jumps = []
        self.end = Self.clamped(offset + (target - delivered) * Self.pointsPerPixel)
        self.settleTime = Double(samples.count - 1) * interval
    }

    /// The page offset `time` seconds after the start of the script. Only the scrolling
    /// axis moves: x for `.sideways`, y otherwise.
    func offset(at time: TimeInterval) -> CGPoint {
        return Self.point(along: scene, value(at: time))
    }

    /// The offset along the scrolling axis.
    func value(at time: TimeInterval) -> Double {
        guard time.isFinite, time > 0 else { return start }
        guard time < settleTime else { return end }
        if samples.isEmpty {
            return jumps.last { $0.time <= time }?.offset ?? start
        }
        let frames = time / Self.frameInterval
        let index = Int(frames)
        guard index + 1 < samples.count else { return end }
        let fraction = frames - Double(index)
        return samples[index] + (samples[index + 1] - samples[index]) * fraction
    }

    // MARK: - The scene

    /// Smoothing is on and not held off by the pause key: the page glides. Otherwise it jumps.
    static func isEased(_ scene: ScrollPreviewView.Scene) -> Bool {
        return scene.smoothing && scene.emphasis != .paused
    }

    /// Real pixels (signed) one click with turn +1 moves the page: 33.6 × speed, five times
    /// that while the "faster" key is held, the other way when reversed. The key only works
    /// on smoothed scrolling (unsmoothed events pass through the engine untouched).
    static func clickDistance(for scene: ScrollPreviewView.Scene) -> Double {
        let speed = scene.speed.isFinite ? max(0, scene.speed) : 0
        var distance = pixelsPerClick * speed
        if scene.emphasis == .faster && isEased(scene) {
            distance *= fasterFactor
        }
        return scene.reversed ? -distance : distance
    }

    /// The engine's per-frame factor for a Duration on the slider scale.
    static func transition(forDuration duration: Double) -> Double {
        let clamped = duration.isFinite
            ? min(durationRange.upperBound, max(durationRange.lowerBound, duration))
            : durationRange.lowerBound
        return OPTIONS_SCROLL_DEFAULT.generateDurationTransition(with: clamped)
    }

    /// The end of the page from which a first click with `firstTurn` has room to move:
    /// the top (or left edge) when it scrolls forward, the far end when it scrolls back.
    static func restingStart(for scene: ScrollPreviewView.Scene, firstTurn: Double) -> Double {
        return firstTurn * clickDistance(for: scene) < 0 ? travel : 0
    }

    static func clamped(_ offset: Double) -> Double {
        guard offset.isFinite else { return 0 }
        return min(travel, max(0, offset))
    }

    static func point(along scene: ScrollPreviewView.Scene, _ value: Double) -> CGPoint {
        return scene.emphasis == .sideways ? CGPoint(x: value, y: 0) : CGPoint(x: 0, y: value)
    }
}

/// The demo loop: a short burst of clicks, a rest once the page has arrived, the same burst
/// back, a rest, and again. Everything the picture shows at a moment of the loop.
struct ScrollPreviewLoop {

    static let clicksPerBurst = 3
    static let clickInterval: TimeInterval = 0.15
    /// From the start of a leg to its first click (the key goes down in this time).
    static let leadIn: TimeInterval = 0.4
    /// The rest after the page has arrived.
    static let rest: TimeInterval = 1.0
    /// How long the wheel takes to turn one click.
    static let tickDuration: TimeInterval = 0.13
    /// How long the flash of a click lasts.
    static let pulseDuration: TimeInterval = 0.32
    /// The key: pressed this long before the first click, let go this long after the last,
    /// and how long it takes to go down or up.
    static let keyLead: TimeInterval = 0.28
    static let keyHold: TimeInterval = 0.3
    static let keyTravel: TimeInterval = 0.1

    /// What the picture shows at one moment.
    struct Frame: Equatable {
        /// How far the page is scrolled, 0...`ScrollPreviewMotion.travel` on each axis.
        var offset: CGPoint
        /// Clicks the wheel has turned since the loop began (signed, fractional while it turns).
        var wheelTurn: Double
        /// 1 at the moment of a click, falling to 0.
        var pulse: Double
        /// 0: the key is up, 1: pressed.
        var keyDepth: Double
        /// The page stands still (it can then sit on whole pixels).
        var isAtRest: Bool
    }

    let scene: ScrollPreviewView.Scene
    /// Away from the start of the page, and back to it.
    let out: ScrollPreviewMotion
    let back: ScrollPreviewMotion
    let outLength: TimeInterval
    let length: TimeInterval

    init(scene: ScrollPreviewView.Scene) {
        self.scene = scene
        out = ScrollPreviewMotion(scene: scene, clicks: Self.burst(turn: 1))
        back = ScrollPreviewMotion(scene: scene, clicks: Self.burst(turn: -1), start: out.end)
        outLength = Self.legLength(out)
        length = outLength + Self.legLength(back)
    }

    static func burst(turn: Double) -> [ScrollPreviewMotion.Click] {
        return (0..<clicksPerBurst).map {
            ScrollPreviewMotion.Click(time: leadIn + Double($0) * clickInterval, turn: turn)
        }
    }

    static var lastClickTime: TimeInterval {
        return leadIn + Double(clicksPerBurst - 1) * clickInterval
    }

    private static func legLength(_ motion: ScrollPreviewMotion) -> TimeInterval {
        return max(motion.settleTime, lastClickTime + keyHold + keyTravel) + rest
    }

    /// Whether the scene shows a key beside the mouse.
    static func showsKey(_ scene: ScrollPreviewView.Scene) -> Bool {
        return scene.emphasis != .wheel
    }

    /// The picture `time` seconds into the loop; times beyond its length wrap around.
    func frame(at time: TimeInterval) -> Frame {
        var time = time.isFinite && length > 0 ? time.truncatingRemainder(dividingBy: length) : 0
        if time < 0 { time += length }
        let onWayBack = time >= outLength
        let motion = onWayBack ? back : out
        let local = onWayBack ? time - outLength : time

        var turn = onWayBack ? Double(Self.clicksPerBurst) : 0
        var pulse = 0.0
        for click in motion.clicks where local >= click.time {
            let since = local - click.time
            turn += click.turn * Self.easeOut(since / Self.tickDuration)
            pulse = max(pulse, 1 - min(1, since / Self.pulseDuration))
        }

        var keyDepth = 0.0
        if Self.showsKey(scene) {
            let down = Self.smoothstep((local - (Self.leadIn - Self.keyLead)) / Self.keyTravel)
            let up = Self.smoothstep((local - (Self.lastClickTime + Self.keyHold)) / Self.keyTravel)
            keyDepth = down - up
        }

        let firstClick = motion.clicks.first?.time ?? 0
        return Frame(
            offset: motion.offset(at: local),
            wheelTurn: turn,
            pulse: pulse,
            keyDepth: keyDepth,
            isAtRest: local < firstClick || local >= motion.settleTime
        )
    }

    /// The picture without motion (Reduce Motion): the page half-way, the key held.
    var stillFrame: Frame {
        return Frame(
            offset: ScrollPreviewMotion.point(along: scene, ScrollPreviewMotion.travel / 2),
            wheelTurn: 0,
            pulse: 0,
            keyDepth: Self.showsKey(scene) ? 1 : 0,
            isAtRest: true
        )
    }

    private static func easeOut(_ progress: Double) -> Double {
        let p = min(1, max(0, progress))
        return 1 - (1 - p) * (1 - p) * (1 - p)
    }

    private static func smoothstep(_ progress: Double) -> Double {
        let p = min(1, max(0, progress))
        return p * p * (3 - 2 * p)
    }
}
