//
//  PreferencesViewController.swift
//  Mos
//  "General" preferences pane, built in code on the grouped kit (PreferencesGroupedForm);
//  the storyboard scene is a shell. On top a card with the app icon, its name, version and
//  build, and for a build installed by scripts/install.sh its commit and date
//  (GeneralHeaderView; the About pane that showed them is gone, and "About Scrollio" in the
//  app menu shows the standard About panel). Under it, only while Scrollio is paused, "Scrollio is
//  paused" with "Resume" (with the menu bar icon hidden there is no other way back). Then
//  two boxes:
//  - "Open at login" (with a row to approve it in System Settings while macOS waits for
//    that) and "Show in menu bar";
//  - "Permissions": whether Scrollio has Accessibility access, with a way to System
//    Settings when it has not (the row then says "Not allowed." in its line under the
//    title, so the orange sign and the button leave that line room for two lines).
//  - "Updates": in a copy that updates itself (a released one, UpdateCenter) the two
//    switches "Check for updates automatically" and "Install updates automatically", and
//    a row with "Check Now" and the time of the last check, which says "Scrollio 1.1.0 is
//    available" with "Update…" while a found update waits. In every other copy one line
//    that says why it does not update itself.
//  - "Settings file": "Export…" writes all settings to a file the user names, "Import…"
//    reads such a file, says in a sheet what it holds and asks before anything changes
//    (SettingsFile, SettingsFileCenter, SettingsImportSheet). Under it, once an import
//    was made, "Settings from before an import" with "Restore…": an open panel on the
//    folder of the backups the imports wrote (the last five, named by their time); the
//    chosen one goes through the same sheet. The panels and the sheet are sheets on the
//    settings window, opened from the click; nothing here is modal for the app.
//  The developer tools (scroll monitor, Logitech diagnostics) are not in the pane: the
//  status-bar menu lists them while Option is held.
//  At the bottom a box with the Welcome Guide and "Scrollio on GitHub" (the repository in the
//  default browser), and one muted line with the credit for the project Scrollio is based on
//  (the licence asks for it: it stays visible).
//  Created by Caldis on 2017/1/15.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa
import UniformTypeIdentifiers

class PreferencesGeneralViewController: NSViewController {

    /// The column of the Preferences window.
    static let paneWidth: CGFloat = PreferencesWindowLayout.contentWidth

    /// Retired: where the pane's "Advanced" (gone with the developer tools) remembered
    /// whether it was open. Plain UI state, not a setting. Nothing reads or writes it any
    /// more; a stored value is left alone, and the name stays taken (never reuse it).
    static let advancedExpandedDefaultsKey = "generalAdvancedExpanded"

    /// Scrollio's repository: its source code and new versions.
    static let gitHubURL = URL(string: "https://github.com/Scorpio3310/scrollio")!

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
    /// Opens a web page in the default browser.
    var openURL: (URL) -> Void = { _ = NSWorkspace.shared.open($0) }
    /// The app's Info.plist, for the version line; tests and renders give one with or
    /// without a build stamp.
    var bundleInfo: () -> [String: Any] = { Bundle.main.infoDictionary ?? [:] }
    /// The updater as the pane shows it, and what its controls do.
    var updateStatus: () -> UpdateStatus = { UpdateCenter.shared.status }
    var checkForUpdates: () -> Void = { UpdateCenter.shared.checkForUpdates() }
    var setChecksForUpdates: (Bool) -> Void = { UpdateCenter.shared.setChecksAutomatically($0) }
    var setInstallsUpdates: (Bool) -> Void = { UpdateCenter.shared.setInstallsAutomatically($0) }
    /// Export, reading a file, import and the backups: the app's settings, or under XCTest
    /// what a test hands in (the app's own are closed to settings files there).
    var settingsFiles: SettingsFileCenter = .live
    /// Asks where the exported file goes, as a sheet on the window, with the name offered;
    /// nil when cancelled. Under XCTest nothing is asked unless a test answers.
    var chooseExportFile: (NSWindow?, String, @escaping (URL?) -> Void) -> Void = AppRuntime.isRunningXCTest
        ? { _, _, completion in completion(nil) }
        : { window, name, completion in
            let panel = PreferencesGeneralViewController.makeExportPanel(name: name)
            let finish: (NSApplication.ModalResponse) -> Void = { response in
                // The panel's sheet goes before a notice or another sheet comes.
                panel.orderOut(nil)
                completion(response == .OK ? panel.url : nil)
            }
            if let window {
                panel.beginSheetModal(for: window, completionHandler: finish)
            } else {
                panel.begin(completionHandler: finish)
            }
        }
    /// Asks for the file to import, as a sheet on the window; nil when cancelled. Under
    /// XCTest nothing is asked unless a test answers.
    var chooseImportFile: (NSWindow?, @escaping (URL?) -> Void) -> Void = AppRuntime.isRunningXCTest
        ? { _, completion in completion(nil) }
        : { window, completion in
            let panel = PreferencesGeneralViewController.makeImportPanel()
            let finish: (NSApplication.ModalResponse) -> Void = { response in
                // The panel's sheet goes before the sheet about the file comes.
                panel.orderOut(nil)
                completion(response == .OK ? panel.url : nil)
            }
            if let window {
                panel.beginSheetModal(for: window, completionHandler: finish)
            } else {
                panel.begin(completionHandler: finish)
            }
        }
    /// Asks which of the settings kept before an import to go back to: an open panel, as
    /// a sheet on the window, that starts in their folder; nil when cancelled. Under
    /// XCTest nothing is asked unless a test answers.
    var chooseBackupFile: (NSWindow?, URL, @escaping (URL?) -> Void) -> Void = AppRuntime.isRunningXCTest
        ? { _, _, completion in completion(nil) }
        : { window, folder, completion in
            let panel = PreferencesGeneralViewController.makeRestorePanel(folder: folder)
            let finish: (NSApplication.ModalResponse) -> Void = { response in
                // The panel's sheet goes before the sheet about the file comes.
                panel.orderOut(nil)
                completion(response == .OK ? panel.url : nil)
            }
            if let window {
                panel.beginSheetModal(for: window, completionHandler: finish)
            } else {
                panel.begin(completionHandler: finish)
            }
        }
    /// Shows the sheet about a file (what it holds, or why it cannot be used) on the
    /// pane's window, and takes it away again.
    var presentSettingsSheet: (SettingsImportSheetViewController, NSViewController) -> Void = { sheet, pane in
        guard pane.view.window != nil else { return }
        pane.presentAsSheet(sheet)
    }
    var dismissSettingsSheet: (SettingsImportSheetViewController) -> Void = { sheet in
        sheet.presentingViewController?.dismiss(sheet)
    }
    /// One of Scrollio's notices: an export or an import is done. Nothing under XCTest.
    var showNotice: (String, Toast.Style) -> Void = AppRuntime.isRunningXCTest ? { _, _ in } : { text, style in
        Toast.show(text, style: style)
    }

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

    private(set) var updatesSection: PreferencesGroupSection!
    private(set) var updatesAutomaticRow: PreferencesSwitchRow!
    private(set) var updatesInstallRow: PreferencesSwitchRow!
    /// "Check for updates" with "Check Now"; "Scrollio 1.1.0 is available" with "Update…".
    private(set) var updatesCheckRow: PreferencesGroupRow!
    private(set) var updatesCheckButton: NSButton!
    /// Shown alone in a copy that does not update itself: why not.
    private(set) var updatesUnavailableRow: PreferencesGroupRow!

    private(set) var settingsFileSection: PreferencesGroupSection!
    /// "Settings file" with "Export…" and "Import…".
    private(set) var settingsFileRow: PreferencesGroupRow!
    private(set) var exportSettingsButton: NSButton!
    private(set) var importSettingsButton: NSButton!
    /// "Settings from before an import" with "Restore…"; shown while a backup is there.
    private(set) var previousSettingsRow: PreferencesGroupRow!
    private(set) var restoreSettingsButton: NSButton!
    /// The sheet about a file while it is up.
    private(set) var settingsSheet: SettingsImportSheetViewController?

    private(set) var welcomeGuideRow: PreferencesGroupRow!
    private(set) var welcomeGuideButton: NSButton!
    private(set) var gitHubRow: PreferencesGroupRow!
    private(set) var gitHubButton: NSButton!
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
        let updates = PreferencesGroupSection(
            title: text("general-updates-header"), width: width, rows: [
                makeUpdatesAutomaticRow(), makeUpdatesInstallRow(), makeUpdatesCheckRow(), makeUpdatesUnavailableRow(),
            ]
        )
        updatesSection = updates
        let settingsFile = PreferencesGroupSection(width: width, rows: [makeSettingsFileRow(), makePreviousSettingsRow()])
        settingsFileSection = settingsFile
        let guide = PreferencesGroupSection(width: width, rows: [makeWelcomeGuideRow(), makeGitHubRow()])
        let credit = makeCreditLabel(width: width)
        PreferencesGroupedForm.add([header, paused, startup, permissions, updates, settingsFile, guide, credit], to: content)
        // The credit sits close under the last box, as the muted lines of the other panes.
        content.setCustomSpacing(PreferencesGroupedForm.noteSpacing, after: guide)

        view = root
        // The seams are set by now (before the view loads): show the real state at once, so
        // the pane is as tall as what it shows.
        syncViewWithOptions()
        refreshAccessState()
        refreshPauseState()
        refreshUpdateState()
        refreshSettingsFileState()
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

    /// "Accessibility": a green check and "Allowed"; or an orange warning and "Open System
    /// Settings", with "Not allowed." at the start of the line under the title (next to the
    /// button the two words would squeeze that line into a narrow column of four lines).
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

    private func makeUpdatesAutomaticRow() -> PreferencesGroupRow {
        let row = PreferencesSwitchRow(
            title: text("general-updates-automatic"),
            explanation: text("general-updates-automatic-hint"),
            target: self,
            action: #selector(updatesAutomaticClicked(_:))
        )
        updatesAutomaticRow = row
        return row
    }

    private func makeUpdatesInstallRow() -> PreferencesGroupRow {
        let row = PreferencesSwitchRow(
            title: text("general-updates-install"),
            explanation: text("general-updates-install-hint"),
            target: self,
            action: #selector(updatesInstallClicked(_:))
        )
        updatesInstallRow = row
        return row
    }

    /// "Check for updates" with "Check Now" and the time of the last check; while a found
    /// update waits, its version with "Update…".
    private func makeUpdatesCheckRow() -> PreferencesGroupRow {
        let button = PreferencesGroupedForm.makePushButton(
            title: text("general-updates-check-now"),
            target: self,
            action: #selector(checkForUpdatesClicked(_:))
        )
        updatesCheckButton = button
        let row = PreferencesGroupRow(
            title: text("general-updates-check"),
            explanation: text("general-updates-never-checked"),
            accessory: button
        )
        updatesCheckRow = row
        return row
    }

    /// One line for a copy that does not update itself.
    private func makeUpdatesUnavailableRow() -> PreferencesGroupRow {
        let row = PreferencesGroupRow(
            title: text("general-updates-unavailable"),
            explanation: text("general-updates-unavailable-source")
        )
        updatesUnavailableRow = row
        return row
    }

    /// "Settings file" with "Export…" and "Import…". Both lead to a panel, hence the "…".
    private func makeSettingsFileRow() -> PreferencesGroupRow {
        let export = PreferencesGroupedForm.makePushButton(
            title: text("general-settings-file-export"),
            target: self,
            action: #selector(exportSettingsClicked(_:))
        )
        exportSettingsButton = export
        let importButton = PreferencesGroupedForm.makePushButton(
            title: text("general-settings-file-import"),
            target: self,
            action: #selector(importSettingsClicked(_:))
        )
        importSettingsButton = importButton
        let buttons = NSStackView(views: [export, importButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8
        let row = PreferencesGroupRow(
            title: text("general-settings-file"),
            explanation: text("general-settings-file-hint"),
            accessory: buttons,
            controls: [export, importButton]
        )
        settingsFileRow = row
        return row
    }

    /// "Settings from before an import" with "Restore…": the backups the imports wrote.
    private func makePreviousSettingsRow() -> PreferencesGroupRow {
        let button = PreferencesGroupedForm.makePushButton(
            title: text("general-settings-file-restore"),
            target: self,
            action: #selector(restoreSettingsClicked(_:))
        )
        restoreSettingsButton = button
        let row = PreferencesGroupRow(
            title: text("general-settings-file-previous"),
            explanation: "",
            accessory: button
        )
        row.isHidden = true
        previousSettingsRow = row
        return row
    }

    /// "Welcome Guide" with "Open": the first-launch steps again.
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

    /// "Scrollio on GitHub" with "Open": the repository in the default browser.
    private func makeGitHubRow() -> PreferencesGroupRow {
        let button = PreferencesGroupedForm.makePushButton(
            title: text("about-github-open"),
            target: self,
            action: #selector(gitHubClicked(_:))
        )
        gitHubButton = button
        let row = PreferencesGroupRow(
            title: text("about-github"),
            explanation: text("about-github-hint"),
            accessory: button
        )
        // "Open" alone does not say where it goes; the row's title stays its title element.
        button.setAccessibilityLabel(text("about-github-open-accessibility"))
        button.toolTip = Self.gitHubURL.absoluteString
        gitHubRow = row
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
            center.addObserver(forName: .scrollioAccessibilityPermissionLost, object: nil, queue: .main) { [weak self] _ in
                self?.refreshAccessState()
            },
            // Paused, resumed, or the cores started or stopped.
            center.addObserver(forName: AppRunController.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.refreshAccessState()
                self?.refreshPauseState()
            },
            // A check started or ended, an update was found or answered, or Sparkle's own
            // question about automatic checks was answered.
            center.addObserver(forName: UpdateCenter.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.refreshUpdateState()
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
        refreshUpdateState()
        refreshSettingsFileState()
    }

    // MARK: - Updates

    /// Shows the updater as it is: the switches, the time of the last check or the update
    /// that waits; in a copy that does not update itself, the one line that says why.
    func refreshUpdateState() {
        guard isViewLoaded else { return }
        let status = updateStatus()
        let available = status.isAvailable
        updatesAutomaticRow.isHidden = !available
        updatesInstallRow.isHidden = !available
        updatesCheckRow.isHidden = !available
        updatesUnavailableRow.isHidden = available
        if available {
            updatesAutomaticRow.isOn = status.checksAutomatically
            updatesInstallRow.isOn = status.installsAutomatically
            updatesInstallRow.isEnabled = status.canInstallAutomatically
            if let version = status.waitingVersion {
                updatesCheckRow.title = String(format: text("general-updates-waiting"), version)
                updatesCheckRow.explanation = text("general-updates-waiting-hint")
                updatesCheckButton.title = text("general-updates-show")
            } else {
                updatesCheckRow.title = text("general-updates-check")
                updatesCheckRow.explanation = Self.lastCheckText(status.lastCheck)
                updatesCheckButton.title = text("general-updates-check-now")
            }
            updatesCheckButton.isEnabled = status.canCheck
        } else {
            updatesUnavailableRow.explanation = text(Self.unavailableTextKey(for: status.availability))
        }
        PreferencesForm.fitToContent(self)
    }

    /// The line of a copy that does not update itself.
    static func unavailableTextKey(for availability: UpdateAvailability) -> String {
        switch availability {
        case .wrongPlace: return "general-updates-unavailable-place"
        case .failed: return "general-updates-unavailable-failed"
        case .available, .builtFromSource: return "general-updates-unavailable-source"
        }
    }

    /// "Last checked 12 Nov 2026 at 08:12." in `locale`'s format; "Not checked yet." Pure.
    static func lastCheckText(_ date: Date?, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        guard let date else {
            return NSLocalizedString("general-updates-never-checked", comment: "")
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return String(format: NSLocalizedString("general-updates-last-checked", comment: ""), formatter.string(from: date))
    }

    @objc func updatesAutomaticClicked(_ sender: NSSwitch) {
        setChecksForUpdates(sender.state == .on)
        refreshUpdateState()
    }

    @objc func updatesInstallClicked(_ sender: NSSwitch) {
        setInstallsUpdates(sender.state == .on)
        refreshUpdateState()
    }

    @objc func checkForUpdatesClicked(_ sender: NSButton) {
        checkForUpdates()
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
        Self.chooseOpenAtLogin(sender.state == .on)
        // Shows what the system did: an item that needs approval in System Settings is not
        // on yet, so the switch stays off and the row says it waits for the approval.
        refreshLaunchAtLoginState()
    }

    /// "Open at login" as the user chose it: this pane's switch, and the last step of the
    /// Welcome Guide. On registers the app (`LoginItem.setEnabled`; when macOS wants an
    /// approval, System Settings opens on Login Items); off removes the registration, also
    /// one that only waits for approval in System Settings. The option then says what the
    /// system did.
    static func chooseOpenAtLogin(_ wanted: Bool) {
        if !wanted {
            LoginItem.removeRegistration()
        }
        Options.shared.general.autoLaunch = wanted
        let enabled = LoginItem.isEnabled
        if Options.shared.general.autoLaunch != enabled {
            Options.shared.general.autoLaunch = enabled
        }
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
        // Without access the words are in the row's line, and the sign alone stands by the button.
        accessibilityStatusLabel.isHidden = !hasAccess
        openAccessibilitySettingsButton.isHidden = hasAccess
        let explanation = text(hasAccess ? "general-accessibility-hint" : "general-accessibility-hint-not-allowed")
        if accessibilityRow.explanation != explanation {
            accessibilityRow.explanation = explanation
        }
        PreferencesForm.fitToContent(self)
    }

    @objc func openAccessibilitySettingsClicked(_ sender: NSButton) {
        openAccessibilitySettings()
    }

    // MARK: - Settings file

    /// The save panel for an export: a JSON file, the name offered, the extension in sight.
    static func makeExportPanel(name: String) -> NSSavePanel {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.prompt = NSLocalizedString("general-settings-file-export-prompt", comment: "")
        return panel
    }

    /// The open panel for an import: one JSON file. Its button does not say "Import":
    /// nothing is imported before the sheet about the file was answered.
    static func makeImportPanel() -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = NSLocalizedString("general-settings-file-import-message", comment: "")
        panel.prompt = NSLocalizedString("general-settings-file-import-prompt", comment: "")
        return panel
    }

    /// The open panel of "Restore…": one JSON file, starting in the backups' folder.
    static func makeRestorePanel(folder: URL) -> NSOpenPanel {
        let panel = makeImportPanel()
        panel.directoryURL = folder
        panel.message = NSLocalizedString("general-settings-file-restore-message", comment: "")
        return panel
    }

    /// Shows "Settings from before an import" while a backup is there, with how many are
    /// kept and the time of the newest.
    func refreshSettingsFileState() {
        guard isViewLoaded else { return }
        let backup = settingsFiles.latestBackup()
        if let backup {
            previousSettingsRow.explanation = String(
                format: text("general-settings-file-previous-hint"), SettingsBackups.keepCount, SettingsFileText.moment(backup.date)
            )
        }
        guard previousSettingsRow.isHidden == (backup != nil) else { return }
        previousSettingsRow.isHidden = backup == nil
        PreferencesForm.fitToContent(self)
    }

    @objc func exportSettingsClicked(_ sender: NSButton) {
        chooseExportFile(view.window, SettingsFile.defaultFileName()) { [weak self] url in
            guard let self, let url else { return }
            if let problem = self.settingsFiles.export(to: url) {
                self.showSettingsSheet(.problem(
                    title: self.text("general-settings-problem-export-title"),
                    text: SettingsFileText.explanation(of: problem)
                ))
            } else {
                self.showNotice(
                    String(format: self.text("general-settings-file-exported"), SettingsFileText.visible(url.lastPathComponent)),
                    .success
                )
            }
        }
    }

    @objc func importSettingsClicked(_ sender: NSButton) {
        chooseImportFile(view.window) { [weak self] url in
            guard let self, let url else { return }
            self.offerImport(of: url)
        }
    }

    @objc func restoreSettingsClicked(_ sender: NSButton) {
        guard let folder = settingsFiles.backupFolder() else {
            refreshSettingsFileState()
            return
        }
        chooseBackupFile(view.window, folder) { [weak self] url in
            guard let self, let url else { return }
            self.offerImport(of: url)
        }
    }

    /// Reads the file and shows the sheet about it: what it holds, with "Import", or why
    /// it cannot be used. Nothing changes before "Import" is clicked there.
    func offerImport(of url: URL) {
        switch settingsFiles.read(url) {
        case .failure(let problem):
            showSettingsSheet(.problem(
                title: text("general-settings-problem-import-title"),
                text: SettingsFileText.explanation(of: problem) + " " + text("general-settings-problem-unchanged")
            ))
        case .success(let contents):
            let sheet = showSettingsSheet(.confirm(contents, fileName: url.lastPathComponent))
            sheet.onImport = { [weak self] in
                self?.importConfirmed(contents)
            }
        }
    }

    @discardableResult
    private func showSettingsSheet(_ content: SettingsImportSheetViewController.Content) -> SettingsImportSheetViewController {
        closeSettingsSheet()
        let sheet = SettingsImportSheetViewController(content: content)
        sheet.onClose = { [weak self] in
            self?.closeSettingsSheet()
        }
        settingsSheet = sheet
        presentSettingsSheet(sheet, self)
        return sheet
    }

    private func closeSettingsSheet() {
        guard let sheet = settingsSheet else { return }
        settingsSheet = nil
        dismissSettingsSheet(sheet)
    }

    /// "Import" of the sheet: the current settings are saved, then the file's are in
    /// effect everywhere. What the pane itself shows follows here; the other panes read
    /// the settings when they are shown.
    private func importConfirmed(_ contents: SettingsFile.Contents) {
        switch settingsFiles.importSettings(contents) {
        case .failure(let problem):
            // The same sheet says why; "OK" closes it. The file was fine: it is the
            // import that could not be made.
            settingsSheet?.onImport = nil
            settingsSheet?.show(.problem(
                title: text("general-settings-problem-not-imported-title"),
                text: SettingsFileText.explanation(of: problem)
            ))
        case .success:
            closeSettingsSheet()
            // An Undo of "Remove Button" or "Remove App" would put an entry of the old
            // settings into the new ones.
            view.window?.undoManager?.removeAllActions()
            syncViewWithOptions()
            refreshSettingsFileState()
            showNotice(text("general-settings-file-imported"), .success)
        }
    }

    // MARK: - Welcome Guide

    @objc func welcomeGuideClicked(_ sender: NSButton) {
        showWelcomeGuide()
    }

    // MARK: - GitHub

    @objc func gitHubClicked(_ sender: NSButton) {
        openURL(Self.gitHubURL)
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
