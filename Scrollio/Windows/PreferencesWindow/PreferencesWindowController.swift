//
//  PreferencesWindowController.swift
//  Mos
//  偏好设置面板容器 Window
//  Created by Caldis on 2017/1/15.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

class PreferencesWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {

    @IBOutlet weak var preferenceWindow: NSWindow!

    /// The window's content: the sidebar and the selected pane.
    var splitViewController: PreferencesSplitViewController? {
        return contentViewController as? PreferencesSplitViewController
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        guard let window else { return }
        contentViewController = PreferencesSplitViewController(
            storyboard: storyboard ?? NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesWindowController.self))
        )
        configure(window, remembersFrame: !AppRuntime.isRunningXCTest)
        splitViewController?.updateWindowTitle()
    }

    /// System Settings' window: a full-height sidebar under the traffic lights, the pane's
    /// name in the title bar next to it, a fixed width and a height the user chooses.
    func configure(_ window: NSWindow, remembersFrame: Bool) {
        window.styleMask.insert([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        // The toolbar holds no items: it gives the title bar System Settings' height and
        // puts the title next to the sidebar.
        let toolbar = NSToolbar(identifier: "PreferencesToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.collectionBehavior.insert(.fullScreenNone)
        // Panes are built in code and swapped in the column: the key view loop follows
        // them, so Tab (and Full Keyboard Access) runs through the pane shown, top to bottom.
        window.autorecalculatesKeyViewLoop = true

        let size = NSSize(
            width: PreferencesWindowLayout.contentWidth(of: splitViewController?.splitView),
            height: PreferencesWindowLayout.defaultContentHeight
        )
        window.contentMinSize = NSSize(width: size.width, height: PreferencesWindowLayout.minimumContentHeight)
        window.contentMaxSize = NSSize(width: size.width, height: CGFloat.greatestFiniteMagnitude)
        window.setContentSize(size)

        guard remembersFrame else { return }
        shouldCascadeWindows = false
        if window.setFrameUsingName(PreferencesWindowLayout.frameAutosaveName) {
            // A frame saved by another version may have another width.
            let width = window.frameRect(forContentRect: NSRect(origin: .zero, size: size)).width
            window.setFrame(
                PreferencesWindowLayout.normalizedFrame(
                    window.frame,
                    width: width,
                    minimumHeight: window.frameRect(forContentRect: NSRect(origin: .zero, size: window.contentMinSize)).height,
                    visibleFrame: window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
                ),
                display: false
            )
        } else {
            window.center()
        }
        _ = window.setFrameAutosaveName(PreferencesWindowLayout.frameAutosaveName)
    }

    // MARK: - NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.sidebarTrackingSeparator]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.sidebarTrackingSeparator]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard itemIdentifier == .sidebarTrackingSeparator, let splitView = splitViewController?.splitView else { return nil }
        return NSTrackingSeparatorToolbarItem(identifier: itemIdentifier, splitView: splitView, dividerIndex: 0)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        WindowManager.shared.hideWindow(withIdentifier: WINDOW_IDENTIFIER.preferencesWindowController, destroy: true)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        // 窗口获得焦点时 (打开面板 / App 从后台切回 / 从其他应用切回) 触发一次冲突状态刷新.
        // Manager 内部有 10s 防抖,不会对 HID 链路造成压力;查询全异步,不阻塞 UI.
        LogiCenter.shared.refreshReportingStates()
    }
}
