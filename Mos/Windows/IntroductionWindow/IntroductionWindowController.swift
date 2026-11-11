//
//  IntroductionWindowController.swift
//  Mos
//  The window of the Welcome Guide. Its content is built in IntroductionViewController.
//  Created by Caldis on 15/11/2019.
//  Copyright © 2019 Caldis. All rights reserved.
//

import Cocoa

class IntroductionWindowController: NSWindowController, NSWindowDelegate {

    @IBOutlet weak var introductionWindow: NSWindow!

    override func windowDidLoad() {
        super.windowDidLoad()
        guard let window = window else { return }
        // The content names the window; the title is still set, for the Window menu,
        // Mission Control and VoiceOver.
        window.title = NSLocalizedString("intro-title", comment: "")
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        if let content = contentViewController?.view {
            window.setContentSize(content.fittingSize)
        }
        // Always in the middle of the screen, not cascaded from the last window.
        shouldCascadeWindows = false
        window.center()
    }

    func windowWillClose(_ notification: Notification) {
        WindowManager.shared.hideWindow(withIdentifier: WINDOW_IDENTIFIER.introductionWindowController, destroy: true)
    }

    /// Opens the Welcome Guide by hand: General › Welcome Guide and Help › Welcome Guide.
    static func showWelcomeGuide() {
        let identifier = WINDOW_IDENTIFIER.introductionWindowController
        let wasOpen = WindowManager.shared.refs[identifier] != nil
        WindowManager.shared.showWindow(withIdentifier: identifier)
        // A guide the app opened itself at launch stays what it is.
        guard !wasOpen,
              let content = WindowManager.shared.refs[identifier]?.contentViewController as? IntroductionViewController
        else { return }
        content.setManuallyOpened(true)
    }
}
