//
//  DockViewWatch.swift
//  Scrollio
//
//  The Dock's own word about its views: Mission Control, an app's windows (App Exposé) and
//  Show Desktop.
//
//  The Dock posts an accessibility notification when it shows one of the three and when
//  that view is left, however the view was opened (a key, a hot corner, the trackpad, a
//  hold of Scrollio's). With "Up and Down follow the hand too" a hold must know what shows
//  before it moves anything (`DockBelief`): the direction whose view shows closes it, and
//  the opposite direction leaves it with the hand instead of putting its own view on top.
//  So from the first such hold on, Scrollio listens to those four notifications.
//
//  It hears four names and nothing else: no window, no title, no app. They come through
//  the Accessibility access Scrollio already has for its buttons; nothing is asked of the
//  Dock beyond the listening, and nothing is stored. Without the switch nobody asks for
//  the watch and it never starts. Apps (Launchpad's successor) is not the Dock's own from
//  macOS 26 on, so the Dock says nothing about it: Apps stays a belief.
//
//  Main thread. Never under XCTest: a test tells `InputProcessor.dockSaid` itself.
//

import Cocoa
import ApplicationServices

final class DockViewWatch {

    static let shared = DockViewWatch()

    /// The Dock's notifications, by name, and what each says.
    static let words: [(name: String, word: DockWord)] = [
        ("AXExposeShowAllWindows", .missionControl),
        ("AXExposeShowFrontWindows", .appWindows),
        ("AXExposeShowDesktop", .desktop),
        ("AXExposeExit", .left),
    ]

    /// What a notification of the Dock says; nil for any other name.
    static func word(forNotification name: String) -> DockWord? {
        return words.first { $0.name == name }?.word
    }

    /// How often the listening is tried before it is given up for this run of the app (the
    /// Dock is not there, the Accessibility access is missing, or this macOS has none of
    /// the notifications). The Dock starting again gives it another try.
    static let attempts = 3

    /// Where a word goes; a test gives its own.
    var onWord: (DockWord) -> Void = { InputProcessor.shared.dockSaid($0) }

    private var observer: AXObserver?
    private var isStartQueued = false
    private var failedAttempts = 0
    /// Whether a hold ever asked for the watch: only then does a new Dock get it again.
    private var isWanted = false

    var isListening: Bool {
        return observer != nil
    }

    /// A hold with "Up and Down follow the hand too" asks for the Dock's word. Called at
    /// the press of a gesture button, inside an event tap's callback: nothing is done here
    /// but a flag, and the listening itself begins on a later turn of the main queue (it
    /// talks to the Dock, which may take a moment). Once it listens this costs nothing.
    func want() {
        guard observer == nil, !isStartQueued, failedAttempts < Self.attempts,
              !AppRuntime.isRunningXCTest else { return }
        isWanted = true
        isStartQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isStartQueued = false
            self.start()
        }
    }

    /// The Dock started (again): the old listening is void, and what the Dock said before
    /// no longer holds (`InputProcessor.surroundingsChanged(.dockStarted)`, told by the
    /// caller). Listens to the new Dock where a hold had asked before.
    func dockStarted() {
        guard isWanted, !AppRuntime.isRunningXCTest else { return }
        stop()
        failedAttempts = 0
        start()
    }

    private func start() {
        guard observer == nil, !AppRuntime.isRunningXCTest else { return }
        guard AXIsProcessTrusted(),
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: DockGestureSwitches.domain).first
        else {
            failed("the Dock or the Accessibility access is missing")
            return
        }
        let process = dock.processIdentifier
        var made: AXObserver?
        guard AXObserverCreate(process, DockViewWatch.heard, &made) == .success, let made else {
            failed("no observer for the Dock")
            return
        }
        let element = AXUIElementCreateApplication(process)
        // A Dock that does not answer must not hold the main thread for long.
        AXUIElementSetMessagingTimeout(element, 1)
        var added = 0
        for (name, _) in Self.words where AXObserverAddNotification(made, element, name as CFString, nil) == .success {
            added += 1
        }
        guard added > 0 else {
            failed("the Dock takes none of the notifications")
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(made), .commonModes)
        observer = made
        AppSystemLog.note("Gestures: listening to the Dock for its views (\(added) of \(Self.words.count) notifications)")
    }

    private func stop() {
        guard let observer else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        self.observer = nil
    }

    private func failed(_ reason: String) {
        failedAttempts += 1
        guard failedAttempts == Self.attempts else { return }
        AppSystemLog.note("Gestures: the Dock's word about its views is not available (\(reason)); "
            + "what shows is what Scrollio opened itself")
    }

    /// The Dock's notification arrives here, on the main run loop.
    private static let heard: AXObserverCallback = { _, _, notification, _ in
        guard let word = DockViewWatch.word(forNotification: notification as String) else { return }
        DockViewWatch.shared.onWord(word)
    }
}
