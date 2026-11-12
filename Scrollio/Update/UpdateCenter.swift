//
//  UpdateCenter.swift
//  Scrollio
//  New versions of Scrollio. The work is Sparkle's (https://sparkle-project.org): it asks
//  the feed for the newest version, downloads the disk image, checks it and puts the new
//  app in the place of the old one. This file is the only one that imports Sparkle; the
//  rest of the app sees `UpdateStatus` and four calls.
//
//  Which copies update themselves: only a released one. scripts/release.sh writes the
//  feed's address into the Info.plist (SUFeedURL); every other build (scripts/install.sh,
//  Xcode, a copy built by someone else) has none, so it starts no updater and makes no
//  network request. That matters for more than tidiness: the released app is signed with
//  the Developer ID, a development build is not, and macOS ties the Accessibility
//  permission to the signature. An update of a development build to the released app
//  would lose the permission.
//
//  What is trusted: the feed only says which version is the newest and where its disk
//  image is. The image must carry an EdDSA signature made with the key whose public half
//  is in the Info.plist (SUPublicEDKey), and that is checked before the image is opened
//  (SUVerifyUpdateBeforeExtraction). So whoever controls the feed or the download can
//  keep an update away, but cannot make Scrollio install something else. The feed's
//  address is always the one of the Info.plist: a value planted in the preferences file
//  is not used (`feedURLString(for:)`). Nothing about the Mac is sent with a check: the
//  system profile is off in the Info.plist, and should the preferences file say
//  otherwise, the profile is empty (`allowedSystemProfileKeys(for:)`).
//
//  What the user meets:
//  - on the second launch Sparkle asks once whether to check automatically (its own
//    window); General has the two switches and "Check Now" afterwards;
//  - "Check for Updates…" in the menu bar menu and in the Scrollio menu; "nothing newer"
//    and "the check failed" come as the alert every Mac app with Sparkle shows ("You're
//    up to date!", "Update Error!"), opened so that nothing in Scrollio waits for it
//    (`UpdateWindows` says how);
//  - when a scheduled check finds a version, Sparkle shows its window: in front only
//    right after Scrollio started or the user touched the updater (the first seconds),
//    otherwise behind what the user is doing, or, while a settings window is open, the
//    next time Scrollio comes to the front. Until it is answered Scrollio sits in the
//    Dock with a badge, the menu bar menu starts with "Update to Scrollio 1.1.0…" and
//    General says so (`UpdateReminder`).
//

import Cocoa
import Sparkle

/// Whether this copy of Scrollio updates itself.
enum UpdateAvailability: Equatable {
    /// A released build, in a place where it can be replaced.
    case available
    /// No feed in the Info.plist: built from source (scripts/install.sh, Xcode).
    case builtFromSource
    /// Runs from a disk image or from a translocated copy: there is nothing to replace.
    case wrongPlace
    /// The feed or the key of this build is not usable, or Sparkle did not start. The
    /// `app` log says which.
    case failed
}

/// The updater as the settings pane and the menus show it.
struct UpdateStatus: Equatable {
    var availability: UpdateAvailability = .builtFromSource
    /// A check can be started now (false while one runs in the background).
    var canCheck = false
    var checksAutomatically = false
    var installsAutomatically = false
    /// "Install updates automatically" can be chosen (it needs the automatic checks).
    var canInstallAutomatically = false
    var lastCheck: Date? = nil
    /// The version that waits for the user's answer ("1.1.0"); nil: none.
    var waitingVersion: String? = nil

    var isAvailable: Bool { return availability == .available }
}

/// What Scrollio shows while a found update waits for the user's answer. Pure: the Dock
/// and the menus read it.
struct UpdateReminder: Equatable {
    /// The version in Sparkle's window ("1.1.0"); nil: no update waits.
    private(set) var waitingVersion: String?
    /// The Dock icon carries a badge: the update came from a scheduled check and the user
    /// has not looked at it yet.
    private(set) var showsBadge = false

    /// Sparkle is about to show `version`. `userInitiated`: the user asked for the check,
    /// so the window opens in front of them and needs no badge.
    mutating func willShow(version: String, userInitiated: Bool) {
        waitingVersion = version
        showsBadge = !userInitiated
    }

    /// The user brought the window to the front or answered it.
    mutating func userLooked() {
        showsBadge = false
    }

    /// Installed, skipped, postponed or failed: Sparkle's window is gone.
    mutating func sessionEnded() {
        self = UpdateReminder()
    }
}

/// Sparkle's own windows (its question about automatic checks, "Checking for updates…",
/// the window of a found update, the progress of a download, its alerts), with the alerts
/// opened from the run loop.
///
/// Sparkle's standard windows say "You're up to date!", "Update Error!" and "Update
/// Installed" with an alert that is modal for the whole app (`NSAlert.runModal`). The
/// updater calls its windows from inside a block of the main dispatch queue, and an alert
/// opened there stops that queue: a run loop started inside a block of the main queue does
/// not serve the queue, so until the alert is closed macOS runs no other block of it.
/// Scrollio's event taps would still be served, but everything they hand to the main
/// queue would wait for a click on "OK": actions of buttons, follow-ups of gestures, the
/// timeout that frees a held pointer, the thumb wheel, the Logitech answers.
///
/// So these three calls return at once and reach Sparkle's windows a moment later from
/// the main run loop itself (`fromTheRunLoop`). The alert is the same one, with Sparkle's
/// icon, words and buttons; behind it the main queue, the timers and the event taps go
/// on, because an alert's run loop runs in the modal panel mode, one of the common modes,
/// and serves the queue when it was not started from it. Everything else goes to
/// Sparkle's windows unchanged.
///
/// Version 1.0.1 said the three as toasts, for the same reason. Never hand one of them to
/// `standard` directly, and never give the updater Sparkle's windows without this class.
final class UpdateWindows: NSObject, SPUUserDriver {

    private let standard: SPUStandardUserDriver

    init(standard: SPUStandardUserDriver) {
        self.standard = standard
    }

    /// Runs `work` on the main thread a moment later, called by the main run loop itself
    /// and not from a block of the main dispatch queue: a timer in the common modes (an
    /// open menu and a modal panel are among them, so neither holds an alert up). Call it
    /// on the main thread.
    ///
    /// Why a timer and not `CFRunLoopPerformBlock` or `RunLoop.perform(inModes:)`: the run
    /// loop takes all the blocks that wait and runs them one after the other, so a block
    /// that stays (an open alert) holds back the blocks queued in the same turn until it
    /// returns. A timer that stays holds back nothing: the alert's run loop serves the
    /// other timers, the sources, the blocks and the main queue. (Measured on macOS 27.2;
    /// `UpdateCenterTests` holds it.)
    static func fromTheRunLoop(_ work: @escaping () -> Void) {
        _ = CommonModesTimer.scheduled(withTimeInterval: 0, repeats: false) { _ in work() }
    }

    // MARK: Sparkle's alerts, opened from the run loop

    /// "You're up to date!" Sparkle's windows close "Checking for updates…" first; the
    /// updater ends the session after the acknowledgement, which comes when the alert was
    /// closed.
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        Self.fromTheRunLoop { [standard] in
            standard.showUpdateNotFoundWithError(error, acknowledgement: acknowledgement)
        }
    }

    /// "Update Error!"
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        Self.fromTheRunLoop { [standard] in
            standard.showUpdaterError(error, acknowledgement: acknowledgement)
        }
    }

    /// "Update Installed": Sparkle shows the alert only when the app was not started
    /// again (Scrollio always is).
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        Self.fromTheRunLoop { [standard] in
            standard.showUpdateInstalledAndRelaunched(relaunched, acknowledgement: acknowledgement)
        }
    }

    // MARK: Sparkle's windows, unchanged

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        standard.show(request, reply: reply)
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        standard.showUserInitiatedUpdateCheck(cancellation: cancellation)
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        standard.showUpdateFound(with: appcastItem, state: state, reply: reply)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        standard.showUpdateReleaseNotes(with: downloadData)
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {
        standard.showUpdateReleaseNotesFailedToDownloadWithError(error)
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        standard.showDownloadInitiated(cancellation: cancellation)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        standard.showDownloadDidReceiveExpectedContentLength(expectedContentLength)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        standard.showDownloadDidReceiveData(ofLength: length)
    }

    func showDownloadDidStartExtractingUpdate() {
        standard.showDownloadDidStartExtractingUpdate()
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        standard.showExtractionReceivedProgress(progress)
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        standard.showReady(toInstallAndRelaunch: reply)
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        standard.showInstallingUpdate(withApplicationTerminated: applicationTerminated, retryTerminatingApplication: retryTerminatingApplication)
    }

    func dismissUpdateInstallation() {
        standard.dismissUpdateInstallation()
    }

    /// Brings the window of a waiting update (or of a running check) to the front.
    func showUpdateInFocus() {
        standard.showUpdateInFocus()
    }
}

final class UpdateCenter: NSObject {

    static let shared = UpdateCenter()

    /// Posted (main thread) when `status` changed.
    static let didChangeNotification = Notification.Name("ScrollioUpdateStatusDidChange")

    /// Where a released build asks for new versions, and the key their signature is
    /// checked with.
    struct Configuration: Equatable {
        let feedURL: URL
        /// The Ed25519 public key, base64, as Sparkle reads it from the Info.plist.
        let publicKey: String
    }

    static let feedKey = "SUFeedURL"
    static let publicKeyKey = "SUPublicEDKey"

    /// The Info.plist's value for `key`, trimmed; "" when it is missing.
    static func value(_ key: String, in info: [String: Any]) -> String {
        return (info[key] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The feed and the key of an Info.plist, when both are usable: an https address with
    /// a host, and 32 bytes of key. Pure.
    static func configuration(info: [String: Any]) -> Configuration? {
        let feed = value(feedKey, in: info)
        let key = value(publicKeyKey, in: info)
        guard let url = URL(string: feed), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty else { return nil }
        guard let keyData = Data(base64Encoded: key), keyData.count == 32 else { return nil }
        return Configuration(feedURL: url, publicKey: key)
    }

    // MARK: - Seams (tests replace them; under XCTest the Dock and the front app are left alone)

    var showDockIcon: () -> Void = AppRuntime.isRunningXCTest ? {} : { Utils.showDockIcon() }
    var releaseDockIcon: () -> Void = AppRuntime.isRunningXCTest ? {} : { Utils.releaseDockIcon() }
    var setDockBadge: (String?) -> Void = AppRuntime.isRunningXCTest ? { _ in } : { NSApp.dockTile.badgeLabel = $0 }
    var activateApp: () -> Void = AppRuntime.isRunningXCTest ? {} : { NSApp.activate(ignoringOtherApps: true) }
    var log: (String) -> Void = { AppSystemLog.note($0) }
    /// Whether an updater may start at all. Never under XCTest: a started updater asks
    /// the network, whatever feed a test hands in.
    var mayStart: () -> Bool = { !AppRuntime.isRunningXCTest }

    // MARK: - State

    private(set) var availability: UpdateAvailability = .builtFromSource
    private(set) var configuration: Configuration?
    private(set) var reminder = UpdateReminder()

    private var updater: SPUUpdater?
    /// Sparkle's own windows, and what stands between them and the updater.
    private var standardWindows: SPUStandardUserDriver?
    private var windows: UpdateWindows?
    private var observations: [NSKeyValueObservation] = []

    /// The Dock icon stays while an update waits, also when the last settings window closes.
    var holdsDockIcon: Bool { return reminder.waitingVersion != nil }

    // MARK: - Start

    /// Starts the updater in a copy that updates itself; in every other copy only notes
    /// why not. Main thread, once, at launch.
    ///
    /// - Parameters:
    ///   - info: the app's Info.plist.
    ///   - runsFromWrongPlace: the app runs from a disk image or a translocated copy.
    func start(
        info: [String: Any] = Bundle.main.infoDictionary ?? [:],
        runsFromWrongPlace: Bool = AppLocation.runningCopyShouldBeMoved
    ) {
        guard updater == nil else { return }
        guard !Self.value(Self.feedKey, in: info).isEmpty else {
            availability = .builtFromSource
            log("Updates: off, this copy has no update feed (it was not built by scripts/release.sh)")
            return
        }
        guard let configuration = Self.configuration(info: info) else {
            availability = .failed
            log("Updates: off, the feed address or the public key in this build's Info.plist is not usable")
            return
        }
        guard !runsFromWrongPlace else {
            availability = .wrongPlace
            log("Updates: off while Scrollio runs from a disk image or a translocated copy")
            return
        }
        guard mayStart() else {
            availability = .failed
            log("Updates: off, no updater starts while the tests run")
            return
        }
        self.configuration = configuration
        let standard = SPUStandardUserDriver(hostBundle: .main, delegate: self)
        let windows = UpdateWindows(standard: standard)
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: windows, delegate: self)
        do {
            try updater.start()
        } catch {
            self.configuration = nil
            availability = .failed
            log("Updates: off, Sparkle did not start: \(error.localizedDescription)")
            return
        }
        self.standardWindows = standard
        self.windows = windows
        self.updater = updater
        availability = .available
        observe(updater)
        log("Updates: on, automatic checks \(updater.automaticallyChecksForUpdates ? "on" : "off"), "
            + "automatic install \(updater.automaticallyDownloadsUpdates ? "on" : "off"), feed at \(configuration.feedURL.host ?? "?")")
        statusDidChange()
    }

    /// What Sparkle changes by itself (a check started or ended, the user answered its
    /// question about automatic checks) reaches the pane and the menus.
    private func observe(_ updater: SPUUpdater) {
        let changed: () -> Void = { [weak self] in
            DispatchQueue.main.async { self?.statusDidChange() }
        }
        observations = [
            updater.observe(\.canCheckForUpdates) { _, _ in changed() },
            updater.observe(\.automaticallyChecksForUpdates) { _, _ in changed() },
            updater.observe(\.automaticallyDownloadsUpdates) { _, _ in changed() },
            updater.observe(\.allowsAutomaticUpdates) { _, _ in changed() },
        ]
    }

    private func statusDidChange() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    // MARK: - What the app asks

    var status: UpdateStatus {
        guard let updater else {
            return UpdateStatus(availability: availability)
        }
        return UpdateStatus(
            availability: .available,
            canCheck: updater.canCheckForUpdates,
            checksAutomatically: updater.automaticallyChecksForUpdates,
            installsAutomatically: updater.automaticallyDownloadsUpdates,
            canInstallAutomatically: updater.allowsAutomaticUpdates,
            lastCheck: updater.lastUpdateCheckDate,
            waitingVersion: reminder.waitingVersion
        )
    }

    /// "Check for Updates…": asks now and says what it found, in Sparkle's windows. While
    /// an update already waits, this brings its window to the front.
    func checkForUpdates() {
        guard let updater, updater.canCheckForUpdates else { return }
        // A menu bar app is not in front when its menu was used.
        activateApp()
        updater.checkForUpdates()
    }

    /// The switch in General. Sparkle stores it (in the app's preferences) and plans the
    /// next check; a choice made here also answers Sparkle's own question at launch.
    func setChecksAutomatically(_ on: Bool) {
        updater?.automaticallyChecksForUpdates = on
        statusDidChange()
    }

    /// The second switch: download a new version in the background and install it when
    /// Scrollio quits.
    func setInstallsAutomatically(_ on: Bool) {
        updater?.automaticallyDownloadsUpdates = on
        statusDidChange()
    }

    // MARK: - The reminder

    /// Sparkle is about to show a found update.
    func updateWillBeShown(version: String, userInitiated: Bool) {
        reminder.willShow(version: version, userInitiated: userInitiated)
        // In the Dock the window can be reached with ⌘Tab and by a click on the icon.
        showDockIcon()
        setDockBadge(reminder.showsBadge ? "1" : nil)
        statusDidChange()
    }

    /// The user looked at Sparkle's window.
    func updateGotAttention() {
        reminder.userLooked()
        setDockBadge(nil)
    }

    /// Sparkle's window is gone.
    func updateSessionEnded() {
        let waited = reminder.waitingVersion != nil
        reminder.sessionEnded()
        setDockBadge(nil)
        if waited {
            releaseDockIcon()
        }
        statusDidChange()
    }
}

// MARK: - Sparkle: the updater

extension UpdateCenter: SPUUpdaterDelegate {

    /// Always the address of the Info.plist. Sparkle would otherwise prefer a "SUFeedURL"
    /// found in the app's preferences file, which any program running as the user can write.
    func feedURLString(for updater: SPUUpdater) -> String? {
        return configuration?.feedURL.absoluteString
    }

    /// No part of Sparkle's system profile (the Mac's model, its macOS, its language…)
    /// may be sent. The profile is off in the Info.plist, but Sparkle reads that switch
    /// from the preferences file first; an empty list holds whatever is written there.
    func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? {
        return []
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        log("Updates: found \(item.displayVersionString) (\(item.versionString))")
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        log("Updates: installing \(item.displayVersionString) (\(item.versionString))")
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        log("Updates: quitting to start the new version")
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        let kind: CheckKind
        switch updateCheck {
        case .updates: kind = .askedFor
        case .updatesInBackground: kind = .scheduled
        case .updateInformation: kind = .feedOnly
        @unknown default: kind = .scheduled
        }
        log(Self.cycleLogLine(kind: kind, error: error as NSError?))
        // The time of the last check changed.
        statusDidChange()
    }

    /// Who started a check.
    enum CheckKind {
        /// "Check for Updates…", "Check Now".
        case askedFor
        /// Sparkle's own, once a day.
        case scheduled
        /// The feed was read without offering anything.
        case feedOnly
    }

    /// Sparkle's error domain and the two outcomes that are not failures.
    static let sparkleErrorDomain = SUSparkleErrorDomain
    static let noUpdateErrorCode = Int(SUError.noUpdateError.rawValue)
    static let installationCanceledErrorCode = Int(SUError.installationCanceledError.rawValue)

    /// One line of the `app` log per check. "No newer version" and an installation the
    /// user cancelled are not failures. Pure.
    static func cycleLogLine(kind: CheckKind, error: NSError?) -> String {
        let name: String
        switch kind {
        case .askedFor: name = "the check the user asked for"
        case .scheduled: name = "a scheduled check"
        case .feedOnly: name = "a look at the feed"
        }
        guard let error else {
            return "Updates: \(name) ended"
        }
        if error.domain == sparkleErrorDomain {
            if error.code == noUpdateErrorCode {
                return "Updates: \(name) found no newer version"
            }
            if error.code == installationCanceledErrorCode {
                return "Updates: \(name) ended, the installation was cancelled"
            }
        }
        return "Updates: \(name) failed: \(error.localizedDescription) (\(error.domain) \(error.code))"
    }
}

// MARK: - Sparkle: its windows

extension UpdateCenter: SPUStandardUserDriverDelegate {

    /// Scrollio adds its own reminders (the Dock, the menus, General). Sparkle still shows
    /// its window when it wants to: for an app without a Dock icon at once, behind what
    /// the user is doing (in front only in the first seconds after the updater started
    /// or its settings changed); for one in the Dock, when it next comes to the front.
    var supportsGentleScheduledUpdateReminders: Bool {
        return true
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        updateWillBeShown(version: update.displayVersionString, userInitiated: state.userInitiated)
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        updateGotAttention()
    }

    func standardUserDriverWillFinishUpdateSession() {
        updateSessionEnded()
    }
}
