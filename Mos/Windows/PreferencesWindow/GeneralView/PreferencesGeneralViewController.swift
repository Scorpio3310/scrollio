//
//  PreferencesViewController.swift
//  Mos
//  "General" preferences pane, built in code on the grouped kit (PreferencesGroupedForm);
//  the storyboard scene is a shell. On top a card with the app icon, its name, version and
//  build, and for a build installed by scripts/install.sh its commit and date
//  (GeneralHeaderView; the About pane that showed them is gone, "About Scrollio" in the app
//  menu opens this pane). Under it, only while Scrollio is paused, "Scrollio is
//  paused" with "Resume" (with the menu bar icon hidden there is no other way back). Then
//  two boxes:
//  - "Open at login" (with a row to approve it in System Settings while macOS waits for
//    that) and "Show in menu bar";
//  - "Permissions": whether Scrollio has Accessibility access, with a way to System
//    Settings when it has not.
//  The developer tools (scroll monitor, Logitech diagnostics) are not in the pane: the
//  status-bar menu lists them while Option is held.
//  At the bottom a box with the Welcome Guide and one muted line with the credit for the
//  project Scrollio is based on (the licence asks for it: it stays visible).
//  Created by Caldis on 2017/1/15.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

class PreferencesGeneralViewController: NSViewController {

    /// The column of the Preferences window.
    static let paneWidth: CGFloat = PreferencesWindowLayout.contentWidth

    /// Retired: where the pane's "Advanced" (gone with the developer tools) remembered
    /// whether it was open. Plain UI state, not a setting. Nothing reads or writes it any
    /// more; a stored value is left alone, and the name stays taken (never reuse it).
    static let advancedExpandedDefaultsKey = "generalAdvancedExpanded"

    // MARK: - Seams (tests and renders replace them: no permission read, no window, no menu bar change)

    /// Whether macOS lets Scrollio use the Accessibility API right now.
    var isAccessGranted: () -> Bool = { Utils.isHadAccessibilityPermissions() }
    /// System Settings › Privacy & Security › Accessibility.
    var openAccessibilitySettings: () -> Void = IntroductionViewController.openAccessibilityPane
    /// The stored "hide the menu bar icon" (`hideStatusItem`); the switch shows its opposite.
    var isMenuBarIconHidden: () -> Bool = { Options.shared.general.hideStatusItem }
    var setMenuBarIconHidden: (Bool) -> Void = { Options.shared.general.hideStatusItem = $0 }
    /// "Pause Scrollio" of the status-bar menu is on.
    var isPaused: () -> Bool = { AppRunController.shared.isPaused }
    /// Ends the pause, as "Resume Scrollio" of the status-bar menu does.
    var resume: () -> Void = { AppRunController.shared.setPaused(false) }
    /// Opens the Welcome Guide.
    var showWelcomeGuide: () -> Void = IntroductionWindowController.showWelcomeGuide
    /// The app's Info.plist, for the version line; tests and renders give one with or
    /// without a build stamp.
    var bundleInfo: () -> [String: Any] = { Bundle.main.infoDictionary ?? [:] }

    // MARK: - Views (read access for tests)

    /// The card on top: the app icon, its name and version.
    private(set) var headerView: GeneralHeaderView!
    /// The box under the card, shown only while Scrollio is paused.
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

    private(set) var welcomeGuideRow: PreferencesGroupRow!
    private(set) var welcomeGuideButton: NSButton!
    /// "Based on Mos by Caldis, …": the attribution the licence asks for.
    private(set) var creditLabel: NSTextField!

    var launchOnLoginSwitch: NSSwitch! { return launchOnLoginRow?.toggle }
    var showInMenuBarSwitch: NSSwitch! { return showInMenuBarRow?.toggle }

    // MARK: - State

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

        let header = GeneralHeaderView(
            name: text("about-app-name"),
            tagline: text("about-tagline"),
            version: Self.versionText(info: bundleInfo())
        )
        header.identifier = NSUserInterfaceItemIdentifier("general-header")
        headerView = header
        let paused = PreferencesGroupSection(width: width, rows: [makePausedRow()])
        paused.isHidden = true
        pausedSection = paused
        let startup = PreferencesGroupSection(width: width, rows: [
            makeLaunchOnLoginRow(), makeLoginApprovalRow(), makeShowInMenuBarRow(),
        ])
        let permissions = PreferencesGroupSection(
            title: text("general-permissions-header"), width: width, rows: [makeAccessibilityRow()]
        )
        let guide = PreferencesGroupSection(width: width, rows: [makeWelcomeGuideRow()])
        let credit = makeCreditLabel(width: width)
        PreferencesGroupedForm.add([header, paused, startup, permissions, guide, credit], to: content)
        // The credit sits close under the last box, as the muted lines of the other panes.
        content.setCustomSpacing(PreferencesGroupedForm.noteSpacing, after: guide)

        view = root
        // The seams are set by now (before the view loads): show the real state at once, so
        // the pane is as tall as what it shows.
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

    /// "Welcome Guide" with "Open…": the first-launch steps again.
    private func makeWelcomeGuideRow() -> PreferencesGroupRow {
        let button = PreferencesGroupedForm.makePushButton(
            title: text("about-welcome-guide-open"),
            target: self,
            action: #selector(welcomeGuideClicked(_:))
        )
        welcomeGuideButton = button
        let row = PreferencesGroupRow(
            title: text("about-welcome-guide"),
            explanation: text("about-welcome-guide-hint"),
            accessory: button
        )
        welcomeGuideRow = row
        return row
    }

    /// One muted line, centred under the last box: what Scrollio is based on.
    private func makeCreditLabel(width: CGFloat) -> NSTextField {
        let credit = NSTextField(wrappingLabelWithString: text("about-credit"))
        credit.identifier = NSUserInterfaceItemIdentifier("general-credit")
        credit.font = PreferencesGroupedForm.explanationFont
        credit.textColor = PreferencesGroupedForm.explanationColor(enabled: true)
        credit.alignment = .center
        credit.isSelectable = false
        credit.preferredMaxLayoutWidth = width
        credit.translatesAutoresizingMaskIntoConstraints = false
        creditLabel = credit
        return credit
    }

    // MARK: - Content

    /// The Info.plist keys scripts/install.sh fills (empty in every other build): the short
    /// commit, with "+" when it was built with uncommitted changes, and the day, "2026-11-11".
    static let buildCommitKey = "ScrollioBuildCommit"
    static let buildDateKey = "ScrollioBuildDate"

    /// "Version 1.0 (1)": the version and the build number the bundle was built with.
    static func versionText(bundle: Bundle = .main) -> String {
        return versionText(info: bundle.infoDictionary ?? [:])
    }

    /// The version line from an Info.plist. Pure. Without a build stamp "Version 1.0 (1)";
    /// with one, the commit (as it is, "+" included) and the day in `locale`'s format:
    /// "Version 1.0 (1456) · e904756 · 11 Nov 2026".
    static func versionText(info: [String: Any], locale: Locale = .current) -> String {
        func value(_ key: String) -> String {
            return (info[key] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let version = value("CFBundleShortVersionString")
        let build = value("CFBundleVersion")
        let commit = value(buildCommitKey)
        guard !commit.isEmpty else {
            return String(format: NSLocalizedString("about-version", comment: ""), version, build)
        }
        let day = buildDayText(value(buildDateKey), locale: locale)
        guard !day.isEmpty else {
            return String(format: NSLocalizedString("about-version-commit", comment: ""), version, build, commit)
        }
        return String(format: NSLocalizedString("about-version-commit-date", comment: ""), version, build, commit, day)
    }

    /// "2026-11-11" as `locale` writes a date ("11 Nov 2026", "Nov 11, 2026"); anything
    /// else as it is. The day is read and written in one time zone, so it never moves.
    static func buildDayText(_ iso: String, locale: Locale) -> String {
        guard let utc = TimeZone(identifier: "UTC") else { return iso }
        let reader = DateFormatter()
        reader.locale = Locale(identifier: "en_US_POSIX")
        reader.timeZone = utc
        reader.dateFormat = "yyyy-MM-dd"
        guard let date = reader.date(from: iso) else { return iso }
        let writer = DateFormatter()
        writer.locale = locale
        writer.timeZone = utc
        writer.dateStyle = .medium
        writer.timeStyle = .none
        return writer.string(from: date)
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

    // MARK: - Welcome Guide

    @objc func welcomeGuideClicked(_ sender: NSButton) {
        showWelcomeGuide()
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
