//
//  LogiTerminationSignal.swift
//  Scrollio
//
//  Quits Scrollio the ordinary way when it is ended with SIGTERM (`kill`, `killall Scrollio`,
//  `pkill`, some uninstallers).
//
//  Why this belongs to the Logitech code: a diverted button stays diverted on the mouse
//  until the mouse is switched off or somebody gives it back. Scrollio gives its buttons
//  back when it quits (applicationWillTerminate stops the Logitech sessions), but SIGTERM
//  ends a process without that, and the mode shift button, the gesture button and (through
//  a receiver) middle, back and forward then do nothing until the mouse is switched off
//  and on. With this in place SIGTERM runs the ordinary quit.
//
//  The signal is caught on a queue of its own, so it also works while the main thread is
//  busy: the quit is handed to the main thread, and if the process is still there after
//  `grace` (the main thread hangs, a dialog holds the quit back), the signal is given its
//  default action back and sent again, so `kill` still ends Scrollio.
//
//  The signal gets a handler that does nothing, not SIG_IGN: an ignored signal stays ignored
//  in every process Scrollio starts (a script bound to a button), a handled one does not.
//

import Cocoa

final class LogiTerminationSignal {

    static let shared = LogiTerminationSignal()

    /// How long the ordinary quit may take before the signal ends the process after all.
    /// The give-back of the buttons waits at most 2 s for the mouse.
    static let defaultGrace: TimeInterval = 4

    private let queue = DispatchQueue(label: "com.nikklemenc.Scrollio.logi.termination-signal")
    private var source: DispatchSourceSignal?
    private var installedSignal: Int32?

    var isInstalled: Bool { source != nil }

    /// Starts watching `number`. Once is enough; a second call does nothing.
    /// - Parameters:
    ///   - graceful: runs on the main thread when the signal arrives (the app: `NSApp.terminate`).
    ///   - lastResort: runs on the signal's own queue when the process is still alive after
    ///     `grace` (the app: the signal's default action, sent again).
    func install(
        signal number: Int32 = SIGTERM,
        grace: TimeInterval = LogiTerminationSignal.defaultGrace,
        graceful: @escaping () -> Void = { NSApp.terminate(nil) },
        lastResort: ((Int32) -> Void)? = nil
    ) {
        guard source == nil else { return }
        // The default action (the process ends at once) has to go, or the source below is
        // never asked. A handler that does nothing; see the header for why not SIG_IGN.
        signal(number, { _ in })
        let source = DispatchSource.makeSignalSource(signal: number, queue: queue)
        let queue = self.queue
        let lastResort = lastResort ?? LogiTerminationSignal.endProcess
        source.setEventHandler {
            DispatchQueue.main.async(execute: graceful)
            queue.asyncAfter(deadline: .now() + grace) {
                lastResort(number)
            }
        }
        source.resume()
        self.source = source
        installedSignal = number
    }

    /// Stops watching and gives the signal its default action back (tests).
    func uninstall() {
        source?.cancel()
        source = nil
        if let number = installedSignal {
            signal(number, SIG_DFL)
        }
        installedSignal = nil
    }

    /// The signal's default action, sent to this process again.
    static func endProcess(_ number: Int32) {
        signal(number, SIG_DFL)
        kill(getpid(), number)
    }
}
