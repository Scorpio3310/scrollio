//
//  DockViewWatch.swift
//  Scrollio
//
//  What Scrollio hears about the Dock's views while "Up and Down follow the hand too" is in
//  use: macOS's own word about Mission Control, an app's windows (App Exposé) and Show
//  Desktop, and that the main mouse button was pressed.
//
//  With that switch a hold must know what shows before it moves anything (`DockBelief`):
//  the direction whose view shows closes it, and the opposite direction leaves it with the
//  hand instead of putting its own view on top. Two things tell:
//
//  - An accessibility notification is posted when one of the three views is shown and
//    when it is left, however the view was opened (a key, a hot corner, the trackpad, a
//    hold of Scrollio's). The Dock names the four notifications, and so does the window
//    manager; which of the two posts them differs by macOS, so both are listened to
//    (`Source`), and the log says who spoke.
//  - A press of the main mouse button anywhere outside Scrollio: a click on a window or on
//    the desktop is how Mission Control is left, and a click beside the panel how Apps is,
//    often with no other sign of it (`InputProcessor.pointerClicked`). Only that it
//    happened is taken, not where or on what.
//
//  It hears four names and the fact of a click, and nothing else: no window, no title, no
//  app, no position. The names come through the Accessibility access Scrollio already has
//  for its buttons; nothing is asked of the Dock beyond the listening, and nothing is
//  stored. Without the switch nobody asks for the watch and it never starts. Apps
//  (Launchpad's successor) is no view of the Dock's own from macOS 26 on, so nothing is
//  said about it: Apps stays a belief.
//
//  Main thread. Never under XCTest: a test tells `InputProcessor.dockSaid` and
//  `pointerClicked` itself.
//

import Cocoa
import ApplicationServices

final class DockViewWatch {

    static let shared = DockViewWatch()

    /// Who is listened to for the word about the Dock's views.
    enum Source: Int, CaseIterable {
        case dock
        case windowManager

        var bundleIdentifier: String {
            switch self {
            case .dock: return DockGestureSwitches.domain
            case .windowManager: return "com.apple.WindowManager"
            }
        }

        /// For the log.
        var logName: String {
            switch self {
            case .dock: return "the Dock"
            case .windowManager: return "the window manager"
            }
        }
    }

    /// The notifications, by name, and what each says.
    static let words: [(name: String, word: DockWord)] = [
        ("AXExposeShowAllWindows", .missionControl),
        ("AXExposeShowFrontWindows", .appWindows),
        ("AXExposeShowDesktop", .desktop),
        ("AXExposeExit", .left),
    ]

    /// What a notification says; nil for any other name.
    static func word(forNotification name: String) -> DockWord? {
        return words.first { $0.name == name }?.word
    }

    /// How often the listening is tried before it is given up for this run of the app (a
    /// source is not there, the Accessibility access is missing, or this macOS has none of
    /// the notifications). The Dock starting again gives it another try.
    static let attempts = 3

    /// Where a word goes; a test gives its own.
    var onWord: (DockWord, Source) -> Void = { InputProcessor.shared.dockSaid($0, by: $1) }
    /// Where a press of the main mouse button goes; a test gives its own.
    var onClick: () -> Void = { InputProcessor.shared.pointerClicked() }

    /// One source that is listened to. The element is kept for as long as the observer.
    private struct Listening {
        let observer: AXObserver
        let element: AXUIElement
    }

    private var listening: [Source: Listening] = [:]
    private var clickMonitor: Any?
    private var isStartQueued = false
    private var attemptsMade = 0
    /// Whether a hold ever asked for the watch: only then does a new Dock get it again.
    private var isWanted = false

    var isListening: Bool {
        return !listening.isEmpty || clickMonitor != nil
    }

    /// A hold with "Up and Down follow the hand too" asks for the watch. Called at the
    /// press of a gesture button, inside an event tap's callback: nothing is done here but
    /// a flag, and the listening itself begins on a later turn of the main queue (it talks
    /// to the Dock, which may take a moment). Once it listens this costs nothing.
    func want() {
        guard !AppRuntime.isRunningXCTest, !isStartQueued, !isComplete else { return }
        isWanted = true
        isStartQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isStartQueued = false
            self.start()
        }
    }

    /// Everything that can be listened to is, or was tried often enough.
    private var isComplete: Bool {
        return clickMonitor != nil && (listening.count == Source.allCases.count || attemptsMade >= Self.attempts)
    }

    /// The Dock started (again): the old listening is void, and what was said before no
    /// longer holds (`InputProcessor.surroundingsChanged(.dockStarted)`, told by the
    /// caller). Listens again where a hold had asked before.
    func dockStarted() {
        guard isWanted, !AppRuntime.isRunningXCTest else { return }
        for source in Source.allCases {
            stop(source)
        }
        attemptsMade = 0
        start()
    }

    private func start() {
        guard !AppRuntime.isRunningXCTest else { return }
        if clickMonitor == nil {
            // Only that the button went down: the handler takes nothing of the event.
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
                self?.onClick()
            }
        }
        guard listening.count < Source.allCases.count, attemptsMade < Self.attempts else { return }
        attemptsMade += 1
        var counts: [String] = []
        if AXIsProcessTrusted() {
            for source in Source.allCases where listening[source] == nil {
                let added = listen(to: source)
                counts.append("\(source.logName): \(added) of \(Self.words.count)")
            }
        }
        if listening.count == Source.allCases.count || attemptsMade == Self.attempts {
            let heard = Source.allCases.filter { listening[$0] != nil }.map(\.logName)
            AppSystemLog.note(
                "Gestures: listening for the Dock's views to "
                    + (heard.isEmpty ? "nobody (the notifications are not available)" : heard.joined(separator: " and "))
                    + (counts.isEmpty ? "" : " (\(counts.joined(separator: ", ")))")
                    + ", and for clicks"
            )
        }
    }

    /// Begins to listen to one source; how many of the notifications it took.
    private func listen(to source: Source) -> Int {
        guard let application = NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleIdentifier).first
        else { return 0 }
        let process = application.processIdentifier
        var made: AXObserver?
        guard AXObserverCreate(process, DockViewWatch.heard, &made) == .success, let made else { return 0 }
        let element = AXUIElementCreateApplication(process)
        // A source that does not answer must not hold the main thread for long.
        AXUIElementSetMessagingTimeout(element, 1)
        // The callback learns who spoke from this number (never a pointer to anything).
        let tag = UnsafeMutableRawPointer(bitPattern: source.rawValue + 1)
        var added = 0
        for (name, _) in Self.words where AXObserverAddNotification(made, element, name as CFString, tag) == .success {
            added += 1
        }
        guard added > 0 else { return 0 }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(made), .commonModes)
        listening[source] = Listening(observer: made, element: element)
        return added
    }

    private func stop(_ source: Source) {
        guard let was = listening.removeValue(forKey: source) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(was.observer), .commonModes)
    }

    /// Who a callback's tag stands for (`listen`).
    static func source(forTag tag: UnsafeMutableRawPointer?) -> Source? {
        guard let tag else { return nil }
        return Source(rawValue: Int(bitPattern: tag) - 1)
    }

    /// A notification arrives here, on the main run loop.
    private static let heard: AXObserverCallback = { _, _, notification, tag in
        guard let word = DockViewWatch.word(forNotification: notification as String),
              let source = DockViewWatch.source(forTag: tag) else { return }
        DockViewWatch.shared.onWord(word, source)
    }
}
