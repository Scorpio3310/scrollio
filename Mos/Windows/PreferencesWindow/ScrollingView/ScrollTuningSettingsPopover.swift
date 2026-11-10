//
//  ScrollTuningSettingsPopover.swift
//  Mos
//
//  Scroll presets, free-spin and acceleration settings, opened from the Scrolling tab.
//
//  CONTRACT: PreferencesScrollingViewController uses `onSettingsChanged`, `onClose`,
//  `show(at:)` and `hide()`. Keep these signatures.
//

import Cocoa

final class ScrollTuningSettingsPopover: NSObject, NSPopoverDelegate {

    /// Called after any change to Options.shared.scroll or Options.shared.scrollTuning.
    var onSettingsChanged: (() -> Void)?
    var onClose: (() -> Void)?

    private var popover: NSPopover?

    func show(at sourceView: NSView) {
        hide()
        // STUB: implemented by the scroll presets UI work package.
        let popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        let vc = NSViewController()
        vc.view = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 80))
        popover.contentViewController = vc
        popover.show(relativeTo: sourceView.bounds, of: sourceView, preferredEdge: .maxY)
        self.popover = popover
    }

    func hide() {
        popover?.close()
        popover = nil
    }

    func popoverDidClose(_ notification: Notification) {
        popover = nil
        onClose?()
    }
}
