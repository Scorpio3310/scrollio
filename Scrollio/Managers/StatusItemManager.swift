//
//  StatusItemManager.swift
//  Mos
//  The menu bar icon and its menu.
//
//  With Accessibility access, in groups: one line per Logitech mouse with its battery
//  ("MX Master 4: 75%"; a click opens Settings › Mouse) | "Smooth Scrolling in Safari" for
//  the app in front (while the event handling runs; `AppSmoothing`), "Settings for
//  Safari…" under it (for any app in front but Scrollio, also while paused; Settings ›
//  Apps on its page, or offering to add it there), "Pause Scrollio" (until "Resume
//  Scrollio") and under it "Pause For" with "15 Minutes" and "1 Hour" (a pause that ends by
//  itself, `AppRunController.pause(for:)`) |
//  "Settings…" (and "Check for Updates…") | "Quit Scrollio". While Option is held (always in
//  the debug build) the diagnostic windows are added above Quit: Logitech Diagnostics in
//  every build, Scroll Monitor and Test Toasts only in the debug build.
//
//  While Scrollio does not work, and only then, the menu starts with a title that says so and
//  the action for it under the title: "Scrollio is paused" (for a pause that ends by itself
//  "Scrollio is paused until 14:30", the local time alone) with "Resume Scrollio";
//  "Scrollio needs Accessibility access" with "Allow Accessibility Access…" (the Welcome
//  Guide; the menu then has only the updater and Quit besides); "Scrollio couldn't start and
//  is trying again" with "Try Again Now" (a start that failed, `AppRunController`) and
//  the two pause items, or with the pause items alone (an event tap whose restarts are refused
//  for a while comes back by itself, `Interceptor`); "Scrollio can't send events to apps" with
//  "Open Accessibility Settings…" and the pause items (macOS does not let Scrollio post events,
//  `ScrollPoster.canPostEvents`: nothing is smoothed, and shortcuts may not reach apps; the
//  item's tooltip is General's line with the way out, which starts with Pause: removing
//  Scrollio from that list while its event taps run can stop the mouse and keyboard);
//  "Smooth scrolling is off: no display frames" with the pause items (three display links in
//  a row sent no frame, `ScrollPoster.displaySendsFrames`; quitting and reopening is the way
//  out). The menu is built when it opens. Each
//  item says what it does: Pause pauses and Resume resumes, so "Resume Scrollio" in a menu
//  left open across the end of a pause does not pause again.
//
//  In a copy that updates itself (UpdateCenter) "Check for Updates…" follows "Settings…";
//  while a found update waits for an answer, "Update to Scrollio 1.1.0…" stands at the top
//  (under the title, when there is one) instead, which brings the updater's window to the
//  front. Both are there without the access too: an update may be what is needed.
//
//  The icon is dimmed while the event handling does not run: paused, the access is missing,
//  or the access is there but an event tap could not be created or stays off because its
//  restarts are throttled (AppRunController, Interceptor), or macOS does not let Scrollio
//  post events or sends it no display frames (ScrollPoster). Its tooltip says which, in the
//  words and the order of the menu's title (the missing access first, also while paused).
//
//  While a Logitech mouse's battery is low and not charging, its percentage stands next to the
//  icon ("8%", "Low" for a mouse that reports only levels), the lowest of several mice, and
//  VoiceOver reads "Scrollio, mouse battery 8%". It follows what LogiCenter reports
//  (`mouseStateChanged`) and goes when the mouse charges, recovers or disconnects.
//
//  What the menu lists is decided by `StatusMenu` from a `StatusMenu.State`, and what its
//  items do is in `StatusMenuActions`, so both are tested without a status item.
//
//  Created by Caldis on 2018/3/7.
//  Copyright © 2018年 Caldis. All rights reserved.
//
import Cocoa

class StatusItemManager: NSMenu, NSMenuDelegate {

    // 状态栏引用
    static let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let item = StatusItemManager.statusItem

    /// What the items do.
    let actions = StatusMenuActions()

    private var isOpen = false
    private var observers: [NSObjectProtocol] = []
    /// How the button places its icon without a battery next to it.
    private var plainImagePosition: NSControl.ImagePosition = .imageOnly

    // 初始化
    override func awakeFromNib() {
        // 设置图标/行为
        item.button?.image = #imageLiteral(resourceName: "AppStatusBarIcon")
        plainImagePosition = item.button?.imagePosition ?? .imageOnly
        // 设置事件响应
        item.menu = self
        item.menu?.delegate = self
        observers = [
            NotificationCenter.default.addObserver(
                forName: AppRunController.didChangeNotification,
                object: AppRunController.shared,
                queue: .main
            ) { [weak self] _ in
                self?.updateIcon()
            },
            // The access taken away or given back while paused changes nothing of the run
            // state, but the tooltip says it, as the menu's title does.
            DistributedNotificationCenter.default().addObserver(
                forName: AppDelegate.accessibilityListChangedNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + AppDelegate.accessibilityCheckDelay) {
                    self?.updateIcon()
                }
            },
            // A tap whose restarts are refused stays off: the icon says so until it runs again.
            NotificationCenter.default.addObserver(
                forName: Interceptor.restartThrottleDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.updateIcon()
            },
            // macOS stopped or started letting Scrollio post events: "can't send events to apps".
            NotificationCenter.default.addObserver(
                forName: ScrollPoster.postEventAccessDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.updateIcon()
            },
            // Display links sent no frame, or one did again: "no display frames".
            NotificationCenter.default.addObserver(
                forName: ScrollPoster.displayFramesDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.updateIcon()
            },
            // What the mice report (also when one connects, disconnects or the Logitech
            // sessions stop): the battery next to the icon, and the answers to the battery
            // read made when the menu opened.
            NotificationCenter.default.addObserver(
                forName: LogiCenter.mouseStateChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                let mice = LogiCenter.shared.mouseDeviceStates()
                self.show(StatusMenu.batteryBadge(for: mice))
                if self.isOpen {
                    StatusMenu.updateBatteryItems(in: self, with: StatusMenu.batteries(from: mice))
                }
            },
        ]
        show(StatusMenu.batteryBadge(for: LogiCenter.shared.mouseDeviceStates()))
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    /// Dims the icon while Scrollio is paused, waits for the access or could not start, and
    /// says why. A pause whose time is up ends first (`AppRunController.endPauseIfDue`;
    /// not when the controller's own change is what called this).
    func updateIcon() {
        let controller = AppRunController.shared
        controller.endPauseIfDue()
        let look = StatusMenu.IconLook(
            hasAccess: Utils.isHadAccessibilityPermissions(),
            coresActive: controller.coresActive,
            isPaused: controller.isPaused,
            startFailed: controller.isRetryingStart,
            tapRestartsThrottled: Interceptor.hasThrottledTap,
            pauseEnd: controller.pauseEnd,
            canPostEvents: ScrollPoster.shared.canPostEvents,
            displaySendsFrames: ScrollPoster.shared.displaySendsFrames
        )
        item.button?.appearsDisabled = look.appearsDisabled
        item.button?.toolTip = look.toolTip
    }

    /// The battery of a mouse that runs low next to the icon, and the item's name for VoiceOver.
    func show(_ badge: StatusMenu.BatteryBadge) {
        guard let button = item.button else { return }
        if button.title != badge.title {
            button.title = badge.title
            button.imagePosition = badge.title.isEmpty ? plainImagePosition : .imageLeading
        }
        button.setAccessibilityLabel(badge.accessibilityLabel)
    }

    /// The state the menu is built from, read when it opens. A pause whose time is up ends
    /// first: its end hangs on one timer, which macOS may fire late in an idle menu bar
    /// app, and the menu must not say "paused until 14:30" after 14:30. `controller` is
    /// the app's; a test hands in one with a clock of its own.
    static func liveState(of controller: AppRunController = .shared) -> StatusMenu.State {
        controller.endPauseIfDue()
        let hasAccess = Utils.isHadAccessibilityPermissions()
        #if DEBUG
        let showsDiagnostics = true
        #else
        let showsDiagnostics = NSEvent.modifierFlags.contains(.option)
        #endif
        return StatusMenu.State(
            hasAccess: hasAccess,
            isPaused: controller.isPaused,
            showsDiagnostics: showsDiagnostics,
            batteries: hasAccess ? StatusMenu.batteries(from: LogiCenter.shared.mouseDeviceStates()) : [],
            appSmoothing: hasAccess ? liveAppSmoothingItem() : nil,
            appSettings: hasAccess ? liveAppSettingsItem() : nil,
            updates: StatusMenu.updates(from: UpdateCenter.shared.status),
            startProblem: StatusMenu.startProblem(
                coresActive: controller.coresActive,
                startFailed: controller.isRetryingStart,
                tapRestartsThrottled: Interceptor.hasThrottledTap,
                canPostEvents: ScrollPoster.shared.canPostEvents,
                displaySendsFrames: ScrollPoster.shared.displaySendsFrames
            ),
            pauseEnd: controller.pauseEnd
        )
    }

    /// "Smooth Scrolling in …" for the app in front. Opening this menu does not change which
    /// app is in front: Scrollio is a menu-bar app.
    static func liveAppSmoothingItem() -> StatusMenu.AppSmoothingItem? {
        let controller = AppRunController.shared
        let running = NSWorkspace.shared.frontmostApplication
        let front = running.map(frontApp)
        let list = Options.shared.application
        return StatusMenu.appSmoothingItem(
            front: front,
            isScrollio: running?.processIdentifier == ProcessInfo.processInfo.processIdentifier,
            scrollingRuns: controller.coresActive && !controller.isPaused && !Interceptor.hasThrottledTap,
            rule: front.map { AppSmoothing.rule(of: AppSmoothing.entry(for: $0, in: list.applications)) } ?? .notListed,
            scrollingSmooth: Options.shared.scroll.smooth,
            limitedToListedApps: list.allowlist
        )
    }

    /// "Settings for …" for the app in front.
    static func liveAppSettingsItem() -> StatusMenu.AppSettingsItem? {
        let running = NSWorkspace.shared.frontmostApplication
        return StatusMenu.appSettingsItem(
            front: running.map(frontApp),
            isScrollio: running?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        )
    }

    /// A running app as the menu names and finds it.
    static func frontApp(_ running: NSRunningApplication) -> AppSmoothing.App {
        let bundle = running.bundleURL?.path
        let program = running.executableURL?.path
        return AppSmoothing.App(
            name: running.localizedName ?? Utils.getApplicationName(fromPath: bundle ?? program),
            bundlePath: bundle,
            executablePath: program
        )
    }
}

/**
 * 菜单响应
 **/
extension StatusItemManager {
    // 打开菜单
    func menuWillOpen(_ menu: NSMenu) {
        isOpen = true
        let state = Self.liveState()
        StatusMenu.build(into: self, state: state, actions: actions)
        // Ask the mice again (the battery at most every few minutes); the answers update the
        // battery lines while the menu is open.
        if state.hasAccess {
            LogiCenter.shared.refreshMouseStates()
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        isOpen = false
    }
}

/**
 * 图标显示
 **/
extension StatusItemManager {
    /// Shows or hides the icon in the menu bar. A test that hides it takes this instead
    /// (the icon is the test host's own, and macOS stores whether it shows).
    static var setStatusItemVisible: (Bool) -> Void = { visible in
        statusItem.isVisible = visible
    }
    // 显示状态栏图标
    class func showStatusItem() {
        setStatusItemVisible(true)
    }
    // 隐藏状态栏图标
    class func hideStatusItem() {
        setStatusItemVisible(false)
    }
}

// MARK: - Content

/// What the status-bar menu lists, and its items. Building a menu opens nothing.
enum StatusMenu {

    /// What the menu is built from.
    struct State: Equatable {
        /// macOS lets Scrollio use the Accessibility API.
        var hasAccess: Bool
        /// Paused from this menu.
        var isPaused: Bool
        /// Option is held, or the debug build: the diagnostic windows are listed.
        var showsDiagnostics: Bool
        /// One line per Logitech mouse that reports its battery.
        var batteries: [Battery]
        /// "Smooth Scrolling in Safari" for the app in front; nil: no such item.
        var appSmoothing: AppSmoothingItem? = nil
        /// "Settings for Safari…" for the app in front; nil: no such item.
        var appSettings: AppSettingsItem? = nil
        /// What the menu offers of the updater.
        var updates: Updates = .none
        /// The access is there and Scrollio is not paused, but it does not work; nil while it
        /// works (or for another reason it does not).
        var startProblem: StartProblem? = nil
        /// When a pause ends by itself (`AppRunController.pauseEnd`); nil for a pause until
        /// "Resume Scrollio", and while not paused.
        var pauseEnd: Date? = nil
        /// The developer tools (Scroll Monitor, Test Toasts) are offered only in the debug build.
        var isDebugBuild: Bool = StatusMenu.isDebugBuild
    }

    /// Why Scrollio does not work although it has the access and is not paused: the icon's
    /// "couldn't start" (`IconLook`).
    enum StartProblem: Equatable {
        /// A start failed (an event tap could not be created); the controller tries again
        /// every few seconds, and the menu offers to try at once.
        case retrying
        /// An event tap is off and its restarts are refused for up to a minute; it comes
        /// back by itself.
        case tapOff
        /// The cores run, but macOS does not let Scrollio post events, while the access may
        /// still show as allowed (`ScrollPoster.canPostEvents`). Nothing is smoothed, and
        /// what buttons, gestures and the Shortcut Ring send does not reach apps; the way out
        /// is in System Settings › Privacy & Security › Accessibility, after a pause.
        case cannotPostEvents
        /// The cores run, but the display links send no frames: three made in a row sent
        /// none (`ScrollPoster.displaySendsFrames`). The wheel goes on unsmoothed; quitting
        /// and reopening Scrollio is the way out. The first frame ends it.
        case noDisplayFrames
    }

    /// The run state's start problem, by the icon's rule. A tap kept off comes first: it
    /// comes back by itself, and until then nothing reaches the poster anyway. No argument
    /// has a default: every caller says what it read (one that lost `canPostEvents` kept
    /// every test green).
    static func startProblem(
        coresActive: Bool, startFailed: Bool, tapRestartsThrottled: Bool, canPostEvents: Bool,
        displaySendsFrames: Bool
    ) -> StartProblem? {
        if !coresActive && startFailed { return .retrying }
        if coresActive && tapRestartsThrottled { return .tapOff }
        if coresActive && !canPostEvents { return .cannotPostEvents }
        if coresActive && !displaySendsFrames { return .noDisplayFrames }
        return nil
    }

    /// What the title at the top of the menu says. Only while Scrollio does not work.
    enum Title: Equatable {
        case paused
        case needsAccess
        case couldNotStart
        case cannotPostEvents
        case noDisplayFrames

        var key: String {
            switch self {
            case .paused: return "status-menu-title-paused"
            case .needsAccess: return "status-menu-title-needs-access"
            case .couldNotStart: return "status-menu-title-could-not-start"
            case .cannotPostEvents: return "status-menu-title-cannot-post-events"
            case .noDisplayFrames: return "status-menu-title-no-display-frames"
            }
        }
    }

    /// The title for `state`; nil while Scrollio works (the menu then has none).
    static func title(for state: State) -> Title? {
        return title(hasAccess: state.hasAccess, isPaused: state.isPaused, startProblem: state.startProblem)
    }

    /// The menu's title and the icon's tooltip (`IconLook`) say the same, in this order:
    /// the missing access first (also while paused), then the pause, then a start problem.
    static func title(hasAccess: Bool, isPaused: Bool, startProblem: StartProblem?) -> Title? {
        if !hasAccess { return .needsAccess }
        if isPaused { return .paused }
        switch startProblem {
        case .cannotPostEvents?: return .cannotPostEvents
        case .noDisplayFrames?: return .noDisplayFrames
        case .retrying?, .tapOff?: return .couldNotStart
        case nil: break
        }
        return nil
    }

    /// What a title says. A pause that ends by itself says when: "Scrollio is paused until
    /// 14:30". The other titles, and a pause until "Resume Scrollio", are their key's text.
    static func titleText(_ title: Title, pauseEnd: Date?) -> String {
        if title == .paused, let pauseEnd {
            return String(format: NSLocalizedString("status-menu-title-paused-until", comment: ""), pauseEndText(pauseEnd))
        }
        return NSLocalizedString(title.key, comment: "")
    }

    /// The end of a pause as the menu, the tooltip and General show it: the time alone, as
    /// the Mac writes it ("14:30", "2:30 PM"). No date: the longest pause is an hour. Pure.
    static func pauseEndText(
        _ end: Date, locale: Locale = .autoupdatingCurrent, timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: end)
    }

    /// The lengths "Pause For" offers, with the keys of their items.
    static let pauseLengths: [(length: AppRunController.PauseLength, key: String)] = [
        (.fifteenMinutes, "status-menu-pause-15-minutes"),
        (.oneHour, "status-menu-pause-1-hour"),
    ]

    /// This build is the debug build.
    static let isDebugBuild: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    /// The diagnostic windows listed while Option is held: Logitech Diagnostics in every
    /// build, the developer tools only in the debug build.
    static func diagnosticItems(isDebugBuild: Bool) -> [Item] {
        return isDebugBuild ? [.scrollMonitor, .diagnostics, .testToasts] : [.diagnostics]
    }

    /// What the menu offers of the updater.
    enum Updates: Equatable {
        /// This copy does not update itself: nothing.
        case none
        /// "Check for Updates…"; disabled while a check runs in the background.
        case check(enabled: Bool)
        /// "Update to Scrollio 1.1.0…": a found update waits for the user's answer.
        case waiting(version: String)
    }

    /// The updater's state as the menu shows it.
    static func updates(from status: UpdateStatus) -> Updates {
        guard status.isAvailable else { return .none }
        if let version = status.waitingVersion {
            return .waiting(version: version)
        }
        return .check(enabled: status.canCheck)
    }

    /// The battery line of one mouse: "MX Master 4: 75%", "MX Master 4: 75%, charging".
    struct Battery: Equatable {
        let title: String
        let symbolName: String
    }

    /// "Smooth Scrolling in Safari", checked while Safari is smoothed; a click changes its
    /// rule (`AppSmoothing.toggle`).
    struct AppSmoothingItem: Equatable {
        let app: AppSmoothing.App
        let title: String
        let isChecked: Bool
        let isEnabled: Bool
    }

    /// The item for the app in front. None without an app in front (or one without a path),
    /// for Scrollio itself, and while Scrollio does not run its event taps (paused, could not
    /// start, a tap kept off): smoothing then is in effect nowhere.
    ///
    /// - Parameters:
    ///   - rule: what the per-app list holds for `front`.
    ///   - scrollingSmooth: "Smooth scrolling" of the Scrolling settings.
    ///   - limitedToListedApps: "Limit scrolling to these apps".
    static func appSmoothingItem(
        front: AppSmoothing.App?, isScrollio: Bool, scrollingRuns: Bool,
        rule: AppSmoothing.Rule, scrollingSmooth: Bool, limitedToListedApps: Bool
    ) -> AppSmoothingItem? {
        guard let front, front.pathToStore != nil, !isScrollio, scrollingRuns else { return nil }
        let decision = AppSmoothing.decide(rule: rule, scrollingSmooth: scrollingSmooth, limitedToListedApps: limitedToListedApps)
        return AppSmoothingItem(
            app: front,
            title: String(format: NSLocalizedString("status-menu-app-smoothing", comment: ""), front.name),
            isChecked: decision.isSmoothed,
            isEnabled: decision.change != nil
        )
    }

    /// "Settings for Safari…": Settings › Apps on the app's page, or, for an app that is not
    /// on the list, the list with a line that offers to add it. The item adds nothing.
    struct AppSettingsItem: Equatable {
        let app: AppSmoothing.App
        let title: String
    }

    /// The item for the app in front: any app with a path but Scrollio itself, whether
    /// Scrollio runs its event taps or not (its settings can be changed while paused). The
    /// name is whole, as in "Smooth Scrolling in …".
    static func appSettingsItem(front: AppSmoothing.App?, isScrollio: Bool) -> AppSettingsItem? {
        guard let front, front.pathToStore != nil, !isScrollio else { return nil }
        return AppSettingsItem(
            app: front,
            title: String(format: NSLocalizedString("status-menu-app-settings", comment: ""), front.name)
        )
    }

    enum Item: Equatable {
        case title(Title)
        case battery(Battery)
        case appSmoothing(AppSmoothingItem)
        case appSettings(AppSettingsItem)
        case separator
        /// "Pause Scrollio": until "Resume Scrollio".
        case pause
        /// "Pause For", with the lengths under it.
        case pauseFor
        case resume
        case tryAgain
        /// "Open Accessibility Settings…": System Settings › Privacy & Security ›
        /// Accessibility, under "Scrollio can't send events to apps". Its tooltip says what
        /// to do there, Pause first (General's line).
        case openAccessibilitySettings
        case settings
        case scrollMonitor
        case diagnostics
        case testToasts
        case allowAccess
        case checkForUpdates(enabled: Bool)
        case updateWaiting(version: String)
        case quit
    }

    /// Tag of the battery lines, so they can be updated while the menu is open.
    static let batteryTag = 7_301

    /// The groups, top to bottom: the title and its action (only while Scrollio does not
    /// work) | a waiting update | the batteries | the app in front and Pause | Settings and
    /// the check for updates | the diagnostics | Quit. While there is a title, Pause stands
    /// under it, in the title's group, and the app in front's group holds only "Settings
    /// for …" (smoothing is in effect nowhere then). "Pause For" always follows Pause.
    static func items(for state: State) -> [Item] {
        var waiting: [Item] = []
        var check: [Item] = []
        switch state.updates {
        case .none: break
        case .check(let enabled): check = [.checkForUpdates(enabled: enabled)]
        case .waiting(let version): waiting = [.updateWaiting(version: version), .separator]
        }
        guard state.hasAccess else {
            return [.title(.needsAccess), .allowAccess, .separator] + waiting
                + (check.isEmpty ? [] : check + [.separator]) + [.quit]
        }
        // The title with its action, while there is one.
        let heading = title(for: state)
        var items: [Item] = []
        switch heading {
        case .paused?:
            items = [.title(.paused), .resume, .separator]
        case .couldNotStart?:
            let tryAgain: [Item] = state.startProblem == .retrying ? [.tryAgain] : []
            items = [.title(.couldNotStart)] + tryAgain + [.pause, .pauseFor, .separator]
        case .cannotPostEvents?:
            items = [.title(.cannotPostEvents), .openAccessibilitySettings, .pause, .pauseFor, .separator]
        case .noDisplayFrames?:
            // The way out is Quit, at the bottom.
            items = [.title(.noDisplayFrames), .pause, .pauseFor, .separator]
        case .needsAccess?, nil:
            break
        }
        items += waiting + state.batteries.map(Item.battery)
        if !state.batteries.isEmpty {
            items.append(.separator)
        }
        // The app in front: "Smooth Scrolling in …" (while Scrollio works), "Settings for …"
        // under it, then Pause while there is no title.
        var front: [Item] = []
        if heading == nil, let smoothing = state.appSmoothing {
            front.append(.appSmoothing(smoothing))
        }
        if let settings = state.appSettings {
            front.append(.appSettings(settings))
        }
        if heading == nil {
            front += [.pause, .pauseFor]
        }
        if !front.isEmpty {
            items += front + [.separator]
        }
        items += [.settings] + check + [.separator]
        if state.showsDiagnostics {
            items += diagnosticItems(isDebugBuild: state.isDebugBuild) + [.separator]
        }
        items.append(.quit)
        return items
    }

    /// The battery lines of the connected mice. A mouse that has not reported its battery
    /// (or has none) gets no line.
    static func batteries(from mice: [LogiMouseDeviceState]) -> [Battery] {
        return mice.compactMap { mouse in
            guard let battery = MousePaneModel.battery(mouse.battery) else { return nil }
            let format = NSLocalizedString(battery.isCharging ? "status-menu-battery-charging" : "status-menu-battery", comment: "")
            return Battery(title: String(format: format, mouse.deviceName, battery.text), symbolName: battery.symbolName)
        }
    }

    /// Fills `menu` with the items for `state`; what they do goes to `actions`.
    static func build(into menu: NSMenu, state: State, actions: StatusMenuActions) {
        menu.removeAllItems()
        for item in items(for: state) {
            menu.addItem(makeItem(item, actions: actions, pauseEnd: state.pauseEnd))
        }
        // macOS 27 hides menu item images unless asked: the battery lines keep their symbol.
        menu.keepItemImagesVisible()
    }

    /// Updates the battery lines in place while the menu is open. A mouse that came or went
    /// shows the next time the menu opens.
    static func updateBatteryItems(in menu: NSMenu, with batteries: [Battery]) {
        let lines = menu.items.filter { $0.tag == batteryTag }
        guard lines.count == batteries.count else { return }
        for (line, battery) in zip(lines, batteries) {
            line.title = battery.title
            line.image = NSImage(systemSymbolName: battery.symbolName, accessibilityDescription: nil)
        }
    }

    /// - Parameter pauseEnd: when the pause ends by itself, for the title of a paused menu.
    static func makeItem(_ item: Item, actions: StatusMenuActions, pauseEnd: Date? = nil) -> NSMenuItem {
        func action(_ key: String, _ selector: Selector, shortcut: String = "") -> NSMenuItem {
            let menuItem = NSMenuItem(title: NSLocalizedString(key, comment: ""), action: selector, keyEquivalent: shortcut)
            menuItem.target = actions
            return menuItem
        }
        switch item {
        case .title(let title):
            // A section header (macOS 14): the title of the group under it, read as a heading.
            return NSMenuItem.sectionHeader(title: titleText(title, pauseEnd: pauseEnd))
        case .battery(let battery):
            // A click opens Settings › Mouse, where the mouse is.
            let line = NSMenuItem(title: battery.title, action: #selector(StatusMenuActions.batteryClicked(_:)), keyEquivalent: "")
            line.target = actions
            line.image = NSImage(systemSymbolName: battery.symbolName, accessibilityDescription: nil)
            line.tag = batteryTag
            return line
        case .appSmoothing(let appSmoothing):
            // Without an action AppKit shows it disabled.
            let toggle = NSMenuItem(
                title: appSmoothing.title,
                action: appSmoothing.isEnabled ? #selector(StatusMenuActions.appSmoothingClicked(_:)) : nil,
                keyEquivalent: ""
            )
            toggle.target = actions
            toggle.isEnabled = appSmoothing.isEnabled
            toggle.state = appSmoothing.isChecked ? .on : .off
            toggle.representedObject = appSmoothing.app
            return toggle
        case .appSettings(let appSettings):
            let show = NSMenuItem(title: appSettings.title, action: #selector(StatusMenuActions.appSettingsClicked(_:)), keyEquivalent: "")
            show.target = actions
            show.representedObject = appSettings.app
            return show
        case .separator:
            return .separator()
        case .pause:
            return action("status-menu-pause", #selector(StatusMenuActions.pauseClicked(_:)))
        case .pauseFor:
            // A submenu with no action of its own; each length is its item's tag (its place
            // in `pauseLengths`).
            let parent = NSMenuItem(title: NSLocalizedString("status-menu-pause-for", comment: ""), action: nil, keyEquivalent: "")
            let lengths = NSMenu(title: parent.title)
            for (index, entry) in pauseLengths.enumerated() {
                let length = action(entry.key, #selector(StatusMenuActions.pauseForClicked(_:)))
                length.tag = index
                lengths.addItem(length)
            }
            parent.submenu = lengths
            return parent
        case .resume:
            return action("status-menu-resume", #selector(StatusMenuActions.resumeClicked(_:)))
        case .tryAgain:
            return action("status-menu-try-again", #selector(StatusMenuActions.tryAgainClicked(_:)))
        case .openAccessibilitySettings:
            // What to do in that list, and to pause first: the words of General's line.
            let open = action("status-menu-open-accessibility-settings", #selector(StatusMenuActions.openAccessibilitySettingsClicked(_:)))
            open.toolTip = NSLocalizedString("general-cannot-post-events-hint", comment: "")
            return open
        case .settings:
            return action("main-menu-settings", #selector(StatusMenuActions.settingsClicked(_:)), shortcut: ",")
        case .scrollMonitor:
            return action("scroll-monitor-title", #selector(StatusMenuActions.scrollMonitorClicked(_:)))
        case .diagnostics:
            return action("logitech-diagnostics-title", #selector(StatusMenuActions.diagnosticsClicked(_:)))
        case .testToasts:
            return action("status-menu-test-toasts", #selector(StatusMenuActions.testToastsClicked(_:)))
        case .allowAccess:
            return action("status-menu-allow-access", #selector(StatusMenuActions.allowAccessClicked(_:)))
        case .checkForUpdates(let enabled):
            // Without an action AppKit shows it disabled.
            let check = action("main-menu-check-for-updates", #selector(StatusMenuActions.checkForUpdatesClicked(_:)))
            if !enabled {
                check.action = nil
            }
            return check
        case .updateWaiting(let version):
            let update = action("status-menu-update-waiting", #selector(StatusMenuActions.checkForUpdatesClicked(_:)))
            update.title = String(format: NSLocalizedString("status-menu-update-waiting", comment: ""), version)
            return update
        case .quit:
            return action("main-menu-quit", #selector(StatusMenuActions.quitClicked(_:)), shortcut: "q")
        }
    }

    /// What stands next to the menu bar icon: the battery of a Logitech mouse that runs low.
    struct BatteryBadge: Equatable {
        /// "8%", "Low"; empty while no mouse runs low.
        let title: String
        /// The status item for VoiceOver: "Scrollio", "Scrollio, mouse battery 8%".
        let accessibilityLabel: String

        /// Nothing next to the icon.
        static var plain: BatteryBadge {
            return BatteryBadge(title: "", accessibilityLabel: NSLocalizedString("status-item-accessibility", comment: ""))
        }
    }

    /// The badge for the connected mice: the lowest battery that is low and not charging.
    /// Low is BatteryWatcher's rule, the one of the warnings: 10 % or less, or the mouse's
    /// own "low" or "critical". A mouse that reports only a level (or coarse steps, whose
    /// number the warnings leave out too) shows "Low".
    static func batteryBadge(for mice: [LogiMouseDeviceState]) -> BatteryBadge {
        let low = mice.compactMap(\.battery).filter { battery in
            !BatteryWatcher.isCharging(battery) && BatteryWatcher.alert(for: battery) > BatteryWatcher.Alert.none
        }
        guard let lowest = low.min(by: isEmptier) else { return .plain }
        if let percent = lowest.percent, !lowest.isApproximate {
            let text = MouseText.percent(percent)
            return BatteryBadge(
                title: text,
                accessibilityLabel: String(format: NSLocalizedString("status-item-accessibility-battery", comment: ""), text)
            )
        }
        return BatteryBadge(
            title: NSLocalizedString("status-item-battery-low", comment: ""),
            accessibilityLabel: NSLocalizedString("status-item-accessibility-battery-low", comment: "")
        )
    }

    /// `a` is emptier than `b`: almost empty before low, then the smaller number; a battery
    /// without a number after one with.
    private static func isEmptier(_ a: LogiMouseDeviceState.Battery, than b: LogiMouseDeviceState.Battery) -> Bool {
        let alertA = BatteryWatcher.alert(for: a)
        let alertB = BatteryWatcher.alert(for: b)
        if alertA != alertB {
            return alertA > alertB
        }
        switch (a.percent, b.percent) {
        case let (percentA?, percentB?): return percentA < percentB
        case (.some, nil): return true
        default: return false
        }
    }

    /// How the menu bar icon looks: dimmed while the event handling does not run, and a
    /// tooltip that says what the menu's title says (`title(hasAccess:isPaused:startProblem:)`).
    struct IconLook: Equatable {
        let appearsDisabled: Bool
        let toolTip: String?

        /// - Parameters:
        ///   - hasAccess: macOS lets Scrollio use the Accessibility API.
        ///   - startFailed: the access is there but the cores did not all start; a timer
        ///     tries again (AppRunController.isRetryingStart).
        ///   - tapRestartsThrottled: an event tap is off and its restarts are refused for a
        ///     while (Interceptor.hasThrottledTap); the cores count as running meanwhile.
        ///   - pauseEnd: when the pause ends by itself; the tooltip then says until when.
        ///   - canPostEvents: macOS lets Scrollio post events (ScrollPoster.canPostEvents).
        ///   - displaySendsFrames: the display links send frames (ScrollPoster.displaySendsFrames).
        init(
            hasAccess: Bool, coresActive: Bool, isPaused: Bool, startFailed: Bool = false,
            tapRestartsThrottled: Bool = false, pauseEnd: Date? = nil, canPostEvents: Bool,
            displaySendsFrames: Bool
        ) {
            let problem = StatusMenu.startProblem(
                coresActive: coresActive, startFailed: startFailed, tapRestartsThrottled: tapRestartsThrottled,
                canPostEvents: canPostEvents, displaySendsFrames: displaySendsFrames
            )
            switch StatusMenu.title(hasAccess: hasAccess, isPaused: isPaused, startProblem: problem) {
            case .needsAccess?:
                appearsDisabled = true
                toolTip = NSLocalizedString("status-item-needs-access", comment: "")
            case .paused?:
                appearsDisabled = !coresActive
                if let pauseEnd {
                    toolTip = String(format: NSLocalizedString("status-item-paused-until", comment: ""), StatusMenu.pauseEndText(pauseEnd))
                } else {
                    toolTip = NSLocalizedString("status-item-paused", comment: "")
                }
            case .couldNotStart?:
                appearsDisabled = true
                toolTip = NSLocalizedString("status-item-could-not-start", comment: "")
            case .cannotPostEvents?:
                // The taps run, but no scroll is smoothed: dimmed as well, so that it is seen.
                appearsDisabled = true
                toolTip = NSLocalizedString("status-item-cannot-post-events", comment: "")
            case .noDisplayFrames?:
                appearsDisabled = true
                toolTip = NSLocalizedString("status-item-no-display-frames", comment: "")
            case nil:
                // The access is back and the cores start in a moment (or the Mac sleeps,
                // another user has it): dimmed, and nothing to say, as the menu has no title.
                appearsDisabled = !coresActive
                toolTip = nil
            }
        }
    }
}

/// What the items of the status-bar menu do. Tests replace the closures.
final class StatusMenuActions: NSObject {

    var showSettings: () -> Void = { MainMenuManager.showPreferencesWindow(paneIdentifier: nil) }
    /// A battery line: Settings, on the Mouse pane.
    var showMouseSettings: () -> Void = {
        MainMenuManager.showPreferencesWindow(paneIdentifier: MousePreferencesViewController.tabIdentifier)
    }
    /// The Welcome Guide, as the app opens it (the Accessibility step alone once the guide
    /// was finished).
    var showWelcomeGuide: () -> Void = { IntroductionWindowController.showAutomatically() }
    /// "Pause Scrollio" (until resumed) and the lengths of "Pause For". Each item says what
    /// it does: there is no toggle, so "Resume Scrollio" in a menu left open across the end
    /// of a pause cannot pause again.
    var pause: (AppRunController.PauseLength) -> Void = { AppRunController.shared.pause(for: $0) }
    /// "Resume Scrollio". Nothing when the pause is over already.
    var resume: () -> Void = { AppRunController.shared.setPaused(false) }
    /// "Try Again Now": the start that failed, tried at once.
    var tryAgain: () -> Void = { AppRunController.shared.tryAgainNow() }
    /// "Open Accessibility Settings…": System Settings › Privacy & Security › Accessibility
    /// (inert under XCTest).
    var openAccessibilitySettings: () -> Void = IntroductionViewController.openAccessibilityPane
    var showScrollMonitor: () -> Void = {
        WindowManager.shared.showWindow(withIdentifier: WINDOW_IDENTIFIER.monitorWindowController)
    }
    /// "Smooth Scrolling in …": decided again with the settings as they are, then changed.
    var toggleAppSmoothing: (AppSmoothing.App) -> Void = { app in
        AppSmoothing.toggle(app, list: Options.shared.application, scrolling: Options.shared.scroll)
    }
    /// "Settings for …": Settings in front, on Apps, with the app's page or the line that
    /// offers to add it. Adds nothing.
    var showApplicationSettings: (AppSmoothing.App) -> Void = { app in
        PreferencesApplicationViewController.showSettingsWindow(for: app)
    }
    var showDiagnostics: () -> Void = { LogiCenter.shared.showDebugPanel() }
    var showTestToasts: () -> Void = { Toast.showTestPanel() }
    /// "Check for Updates…", and "Update to Scrollio …" (the same call brings a waiting
    /// update's window to the front).
    var checkForUpdates: () -> Void = { UpdateCenter.shared.checkForUpdates() }
    var quit: () -> Void = { NSApp.terminate(nil) }

    @objc func settingsClicked(_ sender: Any?) { showSettings() }
    @objc func allowAccessClicked(_ sender: Any?) { showWelcomeGuide() }
    @objc func pauseClicked(_ sender: Any?) { pause(.untilResumed) }
    @objc func pauseForClicked(_ sender: Any?) {
        guard let index = (sender as? NSMenuItem)?.tag, StatusMenu.pauseLengths.indices.contains(index) else { return }
        pause(StatusMenu.pauseLengths[index].length)
    }
    @objc func resumeClicked(_ sender: Any?) { resume() }
    @objc func tryAgainClicked(_ sender: Any?) { tryAgain() }
    @objc func openAccessibilitySettingsClicked(_ sender: Any?) { openAccessibilitySettings() }
    @objc func batteryClicked(_ sender: Any?) { showMouseSettings() }
    @objc func appSmoothingClicked(_ sender: Any?) {
        guard let app = (sender as? NSMenuItem)?.representedObject as? AppSmoothing.App else { return }
        toggleAppSmoothing(app)
    }
    @objc func appSettingsClicked(_ sender: Any?) {
        guard let app = (sender as? NSMenuItem)?.representedObject as? AppSmoothing.App else { return }
        showApplicationSettings(app)
    }
    @objc func scrollMonitorClicked(_ sender: Any?) { showScrollMonitor() }
    @objc func diagnosticsClicked(_ sender: Any?) { showDiagnostics() }
    @objc func testToastsClicked(_ sender: Any?) { showTestToasts() }
    @objc func checkForUpdatesClicked(_ sender: Any?) { checkForUpdates() }
    @objc func quitClicked(_ sender: Any?) { quit() }
}
