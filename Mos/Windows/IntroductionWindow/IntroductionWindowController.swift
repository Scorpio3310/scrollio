//
//  IntroductionWindowController.swift
//  Mos
//  The window of the Welcome Guide: 600 × 680 pt (600 × 620 on a screen too short for
//  it), fixed, centred, its title bar transparent. Its content is built in IntroductionViewController. Here are also the ways
//  the app opens it: by itself (a new user at launch, the access missing) and by hand
//  (General › Welcome Guide, Help › Welcome Guide).
//  Created by Caldis on 15/11/2019.
//  Copyright © 2019 Caldis. All rights reserved.
//

import Cocoa

class IntroductionWindowController: NSWindowController, NSWindowDelegate {

    @IBOutlet weak var introductionWindow: NSWindow!

    override func windowDidLoad() {
        super.windowDidLoad()
        guard let window = window else { return }
        Self.style(window)
        // Always in the middle of the screen, not cascaded from the last window.
        shouldCascadeWindows = false
        window.center()
    }

    /// How the guide's window looks and behaves; also the tests' windows that take real
    /// clicks. It moves by its background: every control of the guide (and the page of the
    /// feel step) says that a press on it does not (`mouseDownCanMoveWindow`).
    static func style(_ window: NSWindow) {
        // The content names the window; the title is still set, for the Window menu,
        // Mission Control and VoiceOver.
        window.title = NSLocalizedString("intro-title", comment: "")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.styleMask.remove(.resizable)
        window.isMovableByWindowBackground = true
        // Tab goes through every control of the step on screen, then the bar.
        window.autorecalculatesKeyViewLoop = true
        window.setContentSize(WelcomeGuideLayout.windowSize)
        window.contentMinSize = WelcomeGuideLayout.windowSize
        window.contentMaxSize = WelcomeGuideLayout.windowSize
        window.standardWindowButton(.zoomButton)?.isEnabled = false
    }

    func windowWillClose(_ notification: Notification) {
        (contentViewController as? IntroductionViewController)?.windowWillClose()
        WindowManager.shared.hideWindow(withIdentifier: WINDOW_IDENTIFIER.introductionWindowController, destroy: true)
    }

    // MARK: - Opening

    /// Who opens the guide.
    enum Request {
        /// The app: a new user at launch, the access missing at launch or on resume,
        /// "Allow Accessibility Access…", the app reopened without the access. The whole
        /// guide until it was finished, then the Accessibility step alone.
        case automatic
        /// General › Welcome Guide, Help › Welcome Guide: the whole guide.
        case byHand
    }

    /// Opens the Welcome Guide by hand: General › Welcome Guide and Help › Welcome Guide.
    static func showWelcomeGuide() {
        show(.byHand)
    }

    /// Opens the Welcome Guide as the app does by itself.
    static func showAutomatically() {
        show(.automatic)
    }

    /// The flow a new window starts with.
    static func flow(for request: Request, progress: WelcomeGuideProgress) -> WelcomeGuideFlow {
        switch request {
        case .automatic: return WelcomeGuideFlow.automatic(guideFinished: progress.isFinished)
        case .byHand: return .full
        }
    }

    /// Whether the guide opens at launch: for a new user who has not finished it, and
    /// whenever the access is missing. (The debug build then does not open Settings.)
    static func opensAtLaunch(hasAccess: Bool, progress: WelcomeGuideProgress = .live) -> Bool {
        return progress.isPending || !hasAccess
    }

    /// The run an open guide starts again when it is asked for once more; nil: it stays as it
    /// is. By hand, the Accessibility step alone becomes the whole guide. By the app (the
    /// access is missing), a run without the Accessibility step starts again with it.
    static func restart(_ open: IntroductionViewController, for request: Request) -> WelcomeGuideFlow? {
        switch request {
        case .byHand:
            return open.flow == .accessOnly ? .full : nil
        case .automatic:
            guard !open.steps.contains(.access), !open.refreshAccessState().isReady else { return nil }
            return open.flow ?? .full
        }
    }

    private static func show(_ request: Request) {
        let identifier = WINDOW_IDENTIFIER.introductionWindowController
        if let open = WindowManager.shared.refs[identifier]?.contentViewController as? IntroductionViewController {
            if let flow = restart(open, for: request) {
                open.begin(flow)
            }
        } else {
            // Roomy, unless this screen cannot show the roomy window whole.
            WelcomeGuideLayout.metrics = .fitting(visibleHeight: NSScreen.main?.visibleFrame.height)
            let controller: NSWindowController = Utils.instantiateControllerFromStoryboard(withIdentifier: identifier)
            if let content = controller.contentViewController as? IntroductionViewController {
                content.begin(flow(for: request, progress: content.progress))
            }
            WindowManager.shared.refs[identifier] = controller
        }
        WindowManager.shared.showWindow(withIdentifier: identifier)
    }
}
