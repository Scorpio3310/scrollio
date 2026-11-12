//
//  ScrollEndWatch.swift
//  Scrollio
//
//  "Trackpad-style scrolling (Beta)", the one touch: where the page under the pointer ends.
//

import Cocoa
import ApplicationServices

/// What one look at the scroll bar under the pointer found.
struct ScrollEndReading: Equatable {
    /// The vertical scroll bar's value: 0 at the top, 1 at the bottom. nil: not seen.
    var value: Double?
    /// Not seen: the step that failed, in a few words (never anything read from the app).
    var failedAt = ""
    /// The roles met on the way up from the element under the pointer (a look only), the
    /// scroll area last. Roles only: "AXStaticText", "AXRow", "AXScrollArea".
    var roles: [String] = []
    /// How long it took (ms).
    var milliseconds = 0.0

    static func notSeen(_ failedAt: String, roles: [String] = [], milliseconds: Double = 0) -> ScrollEndReading {
        return ScrollEndReading(value: nil, failedAt: failedAt, roles: roles, milliseconds: milliseconds)
    }
}

/// Reads where a native view's page is, so that a one touch can end when the page reaches
/// its end (`ScrollPoster`, "the end watch"). An app follows a touch past the page's end
/// for as long as its frames come and lets go only at "ended": a wheel that kept turning
/// held the page stretched for seconds (the owner, build 1674). So the touch has to end the
/// moment the page arrives, and for that Scrollio has to know where the page ends.
///
/// Nothing here may run on the main thread (the event taps) or on the display link's
/// thread, and neither may wait for it: both calls come back at once, and the answer comes
/// later, on any thread, or never. One request runs at a time; the poster asks for the next
/// only when the last has answered.
protocol ScrollEndWatching: AnyObject {
    /// Finds the scroll area under `point` (global, top-left origin, as `CGEvent.location`)
    /// in the app `pid` and reads its vertical scroll bar.
    func look(pid: pid_t, at point: CGPoint, answer: @escaping (ScrollEndReading) -> Void)
    /// Reads the bar the last look found again.
    func read(answer: @escaping (ScrollEndReading) -> Void)
}

/// The real reader: Accessibility, on a queue of its own.
///
/// What it reads, and nothing else: the element under the pointer, the ROLE of that element
/// and of its parents up to the first scroll area (a dozen at most), that area's vertical
/// scroll bar, and the bar's value. Never a title, a text or the value of anything else;
/// nothing is kept but the bar, and that only until the next look.
///
/// - It asks only where `AXIsProcessTrusted()` is true, and never calls the variant that
///   can raise a prompt.
/// - Every element it messages gets a short messaging timeout first
///   (`AXUIElementSetMessagingTimeout` counts for that one element object only), so an app
///   that does not answer costs one timeout and the answer "not seen".
/// - `AXUIElementCopyElementAtPosition` takes "top-left relative screen coordinates": the
///   global space of `CGEvent.location`. Asked of the app's own element, the hit test stays
///   inside that app.
///
/// None of this was run against another app before the owner's first test: a test process
/// may not read another app's interface. The scroll log says per scroll what it met.
final class AccessibilityScrollEndWatch: ScrollEndWatching {

    /// Seconds an app gets to answer one message.
    static let messagingTimeout: Float = 0.1
    /// How far up from the element under the pointer the scroll area is looked for.
    static let deepestClimb = 12

    private let queue = DispatchQueue(label: "com.nikklemenc.Scrollio.end-watch", qos: .userInteractive)
    private let isTrusted: () -> Bool
    /// The bar the last look found. Only on `queue`.
    private var bar: AXUIElement?
    /// The `app` log gets one line at the first look. Only on `queue`.
    private var saidWhetherTrusted = false

    /// `isTrusted`: tests answer here (a test never messages another app).
    init(isTrusted: @escaping () -> Bool = { AXIsProcessTrusted() }) {
        self.isTrusted = isTrusted
    }

    func look(pid: pid_t, at point: CGPoint, answer: @escaping (ScrollEndReading) -> Void) {
        queue.async { [self] in
            let began = DispatchTime.now().uptimeNanoseconds
            bar = nil
            var reading = lookOnQueue(pid: pid, at: point)
            reading.milliseconds = Double(DispatchTime.now().uptimeNanoseconds - began) / 1_000_000
            answer(reading)
        }
    }

    func read(answer: @escaping (ScrollEndReading) -> Void) {
        queue.async { [self] in
            let began = DispatchTime.now().uptimeNanoseconds
            var reading: ScrollEndReading
            if let bar = bar, isTrusted() {
                reading = Self.value(of: bar).map { ScrollEndReading(value: $0) } ?? .notSeen("the bar's value could not be read again")
            } else {
                reading = .notSeen("no bar to read again")
            }
            if reading.value == nil { bar = nil }
            reading.milliseconds = Double(DispatchTime.now().uptimeNanoseconds - began) / 1_000_000
            answer(reading)
        }
    }

    private func lookOnQueue(pid: pid_t, at point: CGPoint) -> ScrollEndReading {
        let trusted = isTrusted()
        if !saidWhetherTrusted {
            saidWhetherTrusted = true
            AppSystemLog.note(Self.firstLookLine(trusted: trusted))
        }
        guard trusted else { return .notSeen("Scrollio is not trusted for Accessibility") }
        guard pid > 0 else { return .notSeen("no app") }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, Self.messagingTimeout)
        var hit: AXUIElement?
        let hitError = AXUIElementCopyElementAtPosition(application, Float(point.x), Float(point.y), &hit)
        guard hitError == .success, var element = hit else {
            return .notSeen("no element under the pointer (\(hitError.rawValue))")
        }
        var roles: [String] = []
        for _ in 0..<Self.deepestClimb {
            AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
            guard let role = Self.copy(element, kAXRoleAttribute) as? String else {
                return .notSeen("an element without a role", roles: roles)
            }
            roles.append(role)
            if role == kAXScrollAreaRole {
                guard let found = Self.copy(element, kAXVerticalScrollBarAttribute), CFGetTypeID(found) == AXUIElementGetTypeID() else {
                    return .notSeen("a scroll area without a vertical scroll bar", roles: roles)
                }
                // swiftlint:disable:next force_cast
                let scrollBar = found as! AXUIElement
                AXUIElementSetMessagingTimeout(scrollBar, Self.messagingTimeout)
                guard let value = Self.value(of: scrollBar) else {
                    return .notSeen("a scroll bar without a value", roles: roles)
                }
                bar = scrollBar
                return ScrollEndReading(value: value, roles: roles)
            }
            guard let parent = Self.copy(element, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else {
                return .notSeen("no scroll area above the element under the pointer", roles: roles)
            }
            // swiftlint:disable:next force_cast
            element = parent as! AXUIElement
        }
        return .notSeen("no scroll area within \(Self.deepestClimb) parents", roles: roles)
    }

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    /// A scroll bar's value as a number from 0 to 1; nil for anything else.
    private static func value(of bar: AXUIElement) -> Double? {
        guard let number = copy(bar, kAXValueAttribute) as? NSNumber else { return nil }
        let value = number.doubleValue
        return value.isFinite ? value : nil
    }

    /// The line for the `app` log at the first look.
    static func firstLookLine(trusted: Bool) -> String {
        return trusted
            ? "Trackpad-style scrolling: the end watch reads the scroll bar under the pointer through Accessibility (Scrollio is trusted)"
            : "Trackpad-style scrolling: Scrollio is not trusted for Accessibility, so no scroll bar is read and native apps scroll as with the switch off"
    }
}

/// What the end watch met and did in one scroll, for the scroll log. Roles and numbers
/// only: nothing an app's interface says.
struct ScrollEndWatchLog: Equatable {
    /// Looks asked for (0: the scroll was no one touch).
    var looks = 0
    /// Whether the last look saw the bar; nil: no answer came.
    var seen: Bool?
    /// Not seen: the step that failed.
    var failedAt = ""
    /// The roles the last look met on the way up.
    var roles: [String] = []
    var firstValue: Double?
    var lastValue: Double?
    /// Answers that came (looks and reads), and the slowest (ms).
    var answers = 0
    var slowest = 0.0
    /// What the watch did, in order.
    var did: [String] = []

    mutating func note(_ reading: ScrollEndReading, isLook: Bool) {
        answers += 1
        slowest = max(slowest, reading.milliseconds)
        if isLook {
            seen = reading.value != nil
            roles = Array(reading.roles.prefix(AccessibilityScrollEndWatch.deepestClimb))
            failedAt = reading.failedAt
        } else if reading.value == nil {
            seen = false
            failedAt = reading.failedAt
        }
        if let value = reading.value {
            if firstValue == nil { firstValue = value }
            lastValue = value
        }
    }

    /// The line for the scroll log; nil for a scroll that never asked.
    var line: String? {
        guard looks > 0 else { return nil }
        var parts: [String] = []
        switch seen {
        case .some(true): parts.append("seen")
        case .some(false): parts.append("not seen (\(failedAt.isEmpty ? "no reason given" : failedAt)): plain")
        case .none: parts.append("no answer: plain")
        }
        if !roles.isEmpty {
            parts.append("roles " + roles.joined(separator: " > "))
        }
        if let first = firstValue, let last = lastValue {
            parts.append(String(format: "value %.4f -> %.4f", first, last))
        }
        parts.append(String(format: "%d looks, %d answers (slowest %.1f ms)", looks, answers, slowest))
        if !did.isEmpty {
            parts.append(did.joined(separator: "; "))
        }
        return "scroll end watch: " + parts.joined(separator: ", ")
    }
}

#if DEBUG
/// Tests and the measuring harness: a watch that answers at once, inside the call, that the
/// bar was seen in mid-page. With it a one touch opens with the wheel event, as it did
/// before there was a watch. Every poster but the app's own gets it (`ScrollPoster.init`).
final class ScrollEndWatchSeenInMidPage: ScrollEndWatching {
    private(set) var looks = 0
    private(set) var reads = 0
    func look(pid: pid_t, at point: CGPoint, answer: @escaping (ScrollEndReading) -> Void) {
        looks += 1
        answer(ScrollEndReading(value: 0.5, roles: ["AXScrollArea"]))
    }
    func read(answer: @escaping (ScrollEndReading) -> Void) {
        reads += 1
        answer(ScrollEndReading(value: 0.5))
    }
}
#endif
