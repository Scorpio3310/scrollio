//
//  MonitorWindowController.swift
//  Mos
//  滚动监控界面的容器 Window
//  Created by Caldis on 2017/1/15.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

class MonitorWindowController: NSWindowController, NSWindowDelegate {
    
    @IBOutlet weak var monitorWindow: NSWindow!

    override func windowDidLoad() {
        super.windowDidLoad()
        // The same name as the item that opens it (status-bar menu, General › Advanced).
        window?.title = NSLocalizedString("scroll-monitor-title", comment: "")
    }

    func windowWillClose(_ notification: Notification) {
        WindowManager.shared.hideWindow(withIdentifier: WINDOW_IDENTIFIER.monitorWindowController, destroy: true)
    }
    
}
