//
//  PreferencesViewController.swift
//  Mos
//  "General" preferences pane, built in code on the grouped kit (PreferencesGroupedForm);
//  the storyboard scene is a shell. On top, only while Scrollio is paused, "Scrollio is
//  paused" with "Resume" (with the menu bar icon hidden there is no other way back). Then
//  three boxes:
//  - "Open at login" (with a row to approve it in System Settings while macOS waits for
//    that) and "Show in menu bar";
//  - "Permissions": whether Scrollio has Accessibility access, with a way to System
//    Settings when it has not;
//  - "Advanced" (closed by default, remembered): the scroll monitor and the Logitech
//    diagnostics windows.
//  Created by Caldis on 2017/1/15.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

class PreferencesGeneralViewController: NSViewController {

    /// The column of the Preferences window.
    static let paneWidth: CGFloat = PreferencesWindowLayout.contentWidth

    /// Where "Advanced" remembers whether it is open. Plain UI state, not a setting.
    static let advancedExpandedDefaultsKey = "generalAdvancedExpanded"

    // MARK: - Seams (tests and renders replace them: no permission read, no window, no menu bar change)

    /// Whether macOS lets Scrollio use the Accessibility API right now.
    var isAccessGranted: () -> Bool = { Utils.isHadAccessibilityPermissions() }
    /// System Settings › Privacy & Security › Accessibility.
    var openAccessibilitySettings: () -> Void = IntroductionViewController.openAccessibilityPane
    /// The stored "hide the menu bar icon" (`hideStatusItem`); the switch shows its opposite.
    var isMenuBarIconHidden: () -> Bool = { Options.shared.general.hideStatusItem }
    var setMenuBarIconHidden: (Bool) -> Void = { Options.shared.general.hideStatusItem = $0 }
    var openScrollMonitor: () -> Void = {
        WindowManager.shared.showWindow(withIdentifier: WINDOW_IDENTIFIER.monitorWindowController)
    }
    var openDiagnostics: () -> Void = { LogiCenter.shared.showDebugPanel() }
    /// "Pause Scrollio" of the status-bar menu is on.
    var isPaused: () -> Bool = { AppRunController.shared.isPaused }
    /// Ends the pause, as "Resume Scrollio" of the status-bar menu does.
    var resume: () -> Void = { AppRunController.shared.setPaused(false) }
    /// Keeps the state of "Advanced"; tests and screenshots give it a store of their own.
    var uiStateDefaults: UserDefaults = .standard

    // MARK: - Views (read access for tests)

    /// The box on top, shown only while Scrollio is paused.
    private(set) var pausedSection: PreferencesGroupSection!
    private(set) var pausedRow: PreferencesGroupRow!
    private(set) var resumeButton: NSButton!
    private(set) var launchOnLoginRow: PreferencesSwitchRow!
    /// Shown while macOS waits for the login item to be approved in System Settings.
    private(set) var loginApprovalRow: PreferencesGroupRow!
    private(set) var openLoginItemsButton: NSButton!
    private(set) var showInMenuBarRow: PreferencesSwitchRow!

    private(set) var accessibilityRow: PreferencesGroupRow!
    private(set) var accessibilityStatusIcon: NSImageView!
    private(set) var accessibilityStatusLabel: NSTextField!
    private(set) var openAccessibilitySettingsButton: NSButton!

    private(set) var advancedRow: PreferencesDisclosureRow!
    private(set) var scrollMonitorRow: PreferencesGroupRow!
    private(set) var scrollMonitorButton: NSButton!
    private(set) var diagnosticsRow: PreferencesGroupRow!
    private(set) var diagnosticsButton: NSButton!

    var launchOnLoginSwitch: NSSwitch! { return launchOnLoginRow?.toggle }
    var showInMenuBarSwitch: NSSwitch! { return showInMenuBarRow?.toggle }

    // MARK: - State

    private(set) var isAdvancedExpanded = false
    /// What the Accessibility row shows.
    private(set) var hasAccess = false
    /// What the login item rows show.
    private(set) var loginItemStatus: LoginItemStatus = .notRegistered

    private var observers: [NSObjectProtocol] = []

    // MARK: - Building

    private func text(_ key: String) -> String {
        return NSLocalizedString(key, comment: "")
    }

    override func loadView() {
        let root = PreferencesForm.makeBackground()
        let content = PreferencesGroupedForm.installContentStack(in: root, paneWidth: Self.paneWidth)
        content.setHuggingPriority(.defaultHigh, for: .vertical)
        let width = PreferencesGroupedForm.boxWidth(paneWidth: Self.paneWidth)

        let paused = PreferencesGroupSection(width: width, rows: [makePausedRow()])
        paused.isHidden = true
        pausedSection = paused
        let startup = PreferencesGroupSection(width: width, rows: [
            makeLaunchOnLoginRow(), makeLoginApprovalRow(), makeShowInMenuBarRow(),
        ])
        let permissions = PreferencesGroupSection(
            title: text("general-permissions-header"), width: width, rows: [makeAccessibilityRow()]
        )
        let advanced = PreferencesGroupSection(width: width, rows: [
            makeAdvancedRow(), makeScrollMonitorRow(), makeDiagnosticsRow(),
        ])
        advancedRow.revealedViews = [scrollMonitorRow, diagnosticsRow]
        PreferencesGroupedForm.add([paused, startup, permissions, advanced], to: content)

        view = root
        // The seams are set by now (before the view loads): show the real state at once, so
        // the pane is as tall as what it shows.
        isAdvancedExpanded = uiStateDefaults.bool(forKey: Self.advancedExpandedDefaultsKey)
        advancedRow.isExpanded = isAdvancedExpanded
        syncViewWithOptions()
        refreshAccessState()
        refreshPauseState()
        root.setFrameSize(root.fittingSize)
    }

    /// "Scrollio is paused", with "Resume".
    private func makePausedRow() -> PreferencesGroupRow {
        let button = PreferencesGroupedForm.makePushButton(
            title: text("general-resume"),
            target: self,
            action: #selector(resumeClicked(_:))
        )
        resumeButton = button
        let row = PreferencesGroupRow(
            title: text("general-paused"),
            explanation: text("general-paused-hint"),
            accessory: button
        )
        pausedRow = row
        return row
    }

    private func makeLaunchOnLoginRow() -> PreferencesGroupRow {
        let row = PreferencesSwitchRow(
            title: text("general-launch-at-login"),
            explanation: text("general-launch-at-login-hint"),
            target: self,
            action: #selector(launchOnLoginClick(_:))
        )
        launchOnLoginRow = row
        return row
    }

    private func makeLoginApprovalRow() -> PreferencesGroupRow {
        let button = PreferencesGroupedForm.makePushButton(
            title: text("general-open-login-items"),
            target: self,
            action: #selector(openLoginItemsClicked(_:))
        )
        openLoginItemsButton = button
        let row = PreferencesGroupRow(title: text("general-login-approval"), accessory: button)
        row.isHidden = true
        loginApprovalRow = row
        return row
    }

    private func makeShowInMenuBarRow() -> PreferencesGroupRow {
        let row = PreferencesSwitchRow(
            title: text("general-show-in-menu-bar"),
            explanation: text("general-show-in-menu-bar-hint"),
            target: self,
            action: #selector(showInMenuBarClick(_:))
        )
        showInMenuBarRow = row
        return row
    }

    /// "Accessibility": a green check and "Allowed", or an orange warning, "Not allowed" and
    /// "Open Settings…".
    private func makeAccessibilityRow() -> PreferencesGroupRow {
        let icon = NSImageView()
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: NSFont.systemFontSize, weight: .regular)
        icon.imageScaling = .scaleNone
        icon.setContentHuggingPriority(.required, for: .horizontal)
        // The word next to it says the same.
        icon.setAccessibilityElement(false)
        accessibilityStatusIcon = icon

        let label = NSTextField(labelWithString: "")
        label.font = PreferencesGroupedForm.titleFont
        label.textColor = .secondaryLabelColor
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        accessibilityStatusLabel = label

        let button = PreferencesGroupedForm.makePushButton(
            title: text("general-accessibility-open-settings"),
            target: self,
            action: #selector(openAccessibilitySettingsClicked(_:))
        )
        openAccessibilitySettingsButton = button

        let status = NSStackView(views: [icon, label])
        status.orientation = .horizontal
        status.alignment = .centerY
        status.spacing = 4
        let accessory = NSStackView(views: [status, button])
        accessory.orientation = .horizontal
        accessory.alignment = .centerY
        accessory.spacing = 10
        accessory.detachesHiddenViews = true

        let row = PreferencesGroupRow(
            title: text("general-accessibility"),
            explanation: text("general-accessibility-hint"),
            accessory: accessory,
            centeredOn: status,
            controls: [button]
        )
        accessibilityRow = row
        return row
    }

    /// "Advanced": the first row of the last box; it opens the rest of that box.
    private func makeAdvancedRow() -> PreferencesGroupRow {
        let row = PreferencesDisclosureRow(
            title: text("general-advanced"),
            target: self,
            action: #selector(advancedClick(_:))
        )
        advancedRow = row
        return row
    }

    private func makeScrollMonitorRow() -> PreferencesGroupRow {
        let button = PreferencesGroupedForm.makePushButton(
            title: text("general-open-window"),
            target: self,
            action: #selector(scrollMonitorClicked(_:))
        )
        scrollMonitorButton = button
        let row = PreferencesGroupRow(
            title: text("general-scroll-monitor"),
            explanation: text("general-scroll-monitor-hint"),
            accessory: button
        )
        scrollMonitorRow = row
        return row
    }

    private func makeDiagnosticsRow() -> PreferencesGroupRow {
        let button = PreferencesGroupedForm.makePushButton(
            title: text("general-open-window"),
            target: self,
            action: #selector(diagnosticsClicked(_:))
        )
        diagnosticsButton = button
        let row = PreferencesGroupRow(
            title: text("general-diagnostics"),
            explanation: text("general-diagnostics-hint"),
            accessory: button
        )
        diagnosticsRow = row
        return row
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        let center = NotificationCenter.default
        observers = [
            // Back from System Settings, where the login item or the access may have changed:
            // the window becomes key again.
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] notification in
                guard let self, let window = notification.object as? NSWindow,
                      window === self.view.window else { return }
                self.refreshLaunchAtLoginState()
                self.refreshAccessState()
            },
            // The access was turned off while Scrollio ran, or came back (the cores started).
            center.addObserver(forName: .mosAccessibilityPermissionLost, object: nil, queue: .main) { [weak self] _ in
                self?.refreshAccessState()
            },
            // Paused, resumed, or the cores started or stopped.
            center.addObserver(forName: AppRunController.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.refreshAccessState()
                self?.refreshPauseState()
            },
        ]
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshLaunchAtLoginState()
        refreshAccessState()
        refreshPauseState()
    }

    // MARK: - Pause

    /// Shows "Scrollio is paused" while it is.
    func refreshPauseState() {
        guard isViewLoaded else { return }
        let paused = isPaused()
        guard pausedSection.isHidden == paused else { return }
        pausedSection.isHidden = !paused
        PreferencesForm.fitToContent(self)
    }

    @objc func resumeClicked(_ sender: NSButton) {
        resume()
        // The run controller posts its change; this covers a resume that posts nothing.
        refreshPauseState()
    }

    // MARK: - Login item

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
        // on yet, so the switch stays off and the row says it waits for the approval.
        refreshLaunchAtLoginState()
    }

    @objc func openLoginItemsClicked(_ sender: NSButton) {
        LoginItem.service.openSystemSettings()
    }

    // MARK: - Menu bar

    @objc func showInMenuBarClick(_ sender: NSSwitch) {
        setMenuBarIconHidden(sender.state != .on)
        syncViewWithOptions()
    }

    // MARK: - Accessibility

    /// Reads the permission and shows it.
    func refreshAccessState() {
        guard isViewLoaded else { return }
        hasAccess = isAccessGranted()
        let symbol = hasAccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        accessibilityStatusIcon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        accessibilityStatusIcon.contentTintColor = hasAccess ? .systemGreen : .systemOrange
        accessibilityStatusLabel.stringValue = text(hasAccess ? "general-accessibility-allowed" : "general-accessibility-not-allowed")
        openAccessibilitySettingsButton.isHidden = hasAccess
        PreferencesForm.fitToContent(self)
    }

    @objc func openAccessibilitySettingsClicked(_ sender: NSButton) {
        openAccessibilitySettings()
    }

    // MARK: - Advanced

    /// Opens or closes "Advanced", remembers it, and lets the column follow.
    func setAdvancedExpanded(_ expanded: Bool) {
        guard expanded != isAdvancedExpanded else { return }
        isAdvancedExpanded = expanded
        uiStateDefaults.set(expanded, forKey: Self.advancedExpandedDefaultsKey)
        advancedRow.isExpanded = expanded
        PreferencesForm.fitToContent(self)
    }

    @objc func advancedClick(_ sender: NSButton) {
        setAdvancedExpanded(!isAdvancedExpanded)
    }

    @objc func scrollMonitorClicked(_ sender: NSButton) {
        openScrollMonitor()
    }

    @objc func diagnosticsClicked(_ sender: NSButton) {
        openDiagnostics()
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
        loginItemStatus = LoginItem.service.status
        let waiting = loginItemStatus == .requiresApproval
        launchOnLoginRow.explanation = text(waiting ? "general-launch-at-login-waiting" : "general-launch-at-login-hint")
        loginApprovalRow.isHidden = !waiting
        // 菜单栏图标
        showInMenuBarRow.isOn = !isMenuBarIconHidden()
        // The approval row came or went.
        PreferencesForm.fitToContent(self)
    }
}
