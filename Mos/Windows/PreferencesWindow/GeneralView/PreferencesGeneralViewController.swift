//
//  PreferencesViewController.swift
//  Mos
//  基础选项界面
//  Created by Caldis on 2017/1/15.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

class PreferencesGeneralViewController: NSViewController {
    
    // UI Elements
    @IBOutlet weak var launchOnLoginCheckBox: NSButton!
    @IBOutlet weak var hideStatusBarIconCheckBox: NSButton!

    private var keyWindowObserver: NSObjectProtocol?

    override func viewDidLoad() {
        // 读取设置
        syncViewWithOptions()
        // Back from System Settings, where the login item may have been approved or
        // switched off: the window becomes key again.
        keyWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, let window = notification.object as? NSWindow,
                  window === self.view.window else { return }
            self.refreshLaunchAtLoginState()
        }
    }

    deinit {
        if let keyWindowObserver {
            NotificationCenter.default.removeObserver(keyWindowObserver)
        }
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshLaunchAtLoginState()
    }

    /// The login item lives in the system, and System Settings can switch it while the app
    /// runs, so the checkbox shows what the system says each time the pane appears.
    /// Assigning the state that was just read changes nothing in the system
    /// (LoginItem.setEnabled is a no-op then).
    func refreshLaunchAtLoginState() {
        let enabled = LoginItem.isEnabled
        if Options.shared.general.autoLaunch != enabled {
            Options.shared.general.autoLaunch = enabled
        }
        syncViewWithOptions()
    }
    
    // 自启
    @IBAction func launchOnLoginClick(_ sender: NSButton) {
        let wanted = sender.state == .on
        if !wanted {
            // Unchecking always removes the registration, also one that only waits for
            // approval in System Settings.
            LoginItem.removeRegistration()
        }
        Options.shared.general.autoLaunch = wanted
        // Shows what the system did: an item that needs approval in System Settings is not
        // on yet, so the box is not checked until it is approved there.
        refreshLaunchAtLoginState()
    }
    
    // 隐藏
    @IBAction func hideStatusBarIconClick(_ sender: NSButton) {
        Options.shared.general.hideStatusItem = sender.state.rawValue==0 ? false : true
        syncViewWithOptions()
    }
}

/**
 * 设置同步
 **/
extension PreferencesGeneralViewController {
    // 同步界面与设置
    func syncViewWithOptions() {
        // 自启
        launchOnLoginCheckBox.state = NSControl.StateValue(rawValue: Options.shared.general.autoLaunch ? 1 : 0)
        // 隐藏
        hideStatusBarIconCheckBox.state = NSControl.StateValue(rawValue: Options.shared.general.hideStatusItem ? 1 : 0)
    }
}
