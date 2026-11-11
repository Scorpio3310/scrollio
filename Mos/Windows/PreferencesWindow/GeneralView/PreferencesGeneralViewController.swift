//
//  PreferencesViewController.swift
//  Mos
//  "General" preferences pane: opening at login and the menu bar icon, two switches in a
//  box of the grouped kit (PreferencesGroupedForm), as in System Settings. Built in code;
//  the storyboard scene is a shell.
//  Created by Caldis on 2017/1/15.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

class PreferencesGeneralViewController: NSViewController {

    /// The column of the Preferences window.
    static let paneWidth: CGFloat = PreferencesWindowLayout.contentWidth

    // MARK: - Views (read access for tests)

    private(set) var launchOnLoginRow: PreferencesSwitchRow!
    private(set) var hideStatusBarIconRow: PreferencesSwitchRow!

    var launchOnLoginSwitch: NSSwitch! { return launchOnLoginRow?.toggle }
    var hideStatusBarIconSwitch: NSSwitch! { return hideStatusBarIconRow?.toggle }

    private var keyWindowObserver: NSObjectProtocol?

    override func loadView() {
        let root = PreferencesForm.makeBackground()
        let content = PreferencesGroupedForm.installContentStack(in: root, paneWidth: Self.paneWidth)
        content.setHuggingPriority(.defaultHigh, for: .vertical)

        launchOnLoginRow = PreferencesSwitchRow(
            title: NSLocalizedString("general-launch-at-login", comment: ""),
            explanation: NSLocalizedString("general-launch-at-login-hint", comment: ""),
            target: self,
            action: #selector(launchOnLoginClick(_:))
        )
        hideStatusBarIconRow = PreferencesSwitchRow(
            title: NSLocalizedString("general-hide-menu-bar-icon", comment: ""),
            explanation: NSLocalizedString("general-hide-menu-bar-icon-hint", comment: ""),
            target: self,
            action: #selector(hideStatusBarIconClick(_:))
        )
        let box = PreferencesGroupSection(
            width: PreferencesGroupedForm.boxWidth(paneWidth: Self.paneWidth),
            rows: [launchOnLoginRow, hideStatusBarIconRow]
        )
        PreferencesGroupedForm.add([box], to: content)

        view = root
        root.setFrameSize(root.fittingSize)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
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
    /// runs, so the switch shows what the system says each time the pane appears.
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
    @objc func launchOnLoginClick(_ sender: NSSwitch) {
        let wanted = sender.state == .on
        if !wanted {
            // Switching it off always removes the registration, also one that only waits
            // for approval in System Settings.
            LoginItem.removeRegistration()
        }
        Options.shared.general.autoLaunch = wanted
        // Shows what the system did: an item that needs approval in System Settings is not
        // on yet, so the switch stays off until it is approved there.
        refreshLaunchAtLoginState()
    }

    // 隐藏
    @objc func hideStatusBarIconClick(_ sender: NSSwitch) {
        Options.shared.general.hideStatusItem = sender.state == .on
        syncViewWithOptions()
    }
}

/**
 * 设置同步
 **/
extension PreferencesGeneralViewController {
    // 同步界面与设置
    func syncViewWithOptions() {
        guard isViewLoaded else { return }
        // 自启
        launchOnLoginRow.isOn = Options.shared.general.autoLaunch
        // 隐藏
        hideStatusBarIconRow.isOn = Options.shared.general.hideStatusItem
    }
}
