//
//  MainMenuManager.swift
//  Mos
//  The app's menu bar: Scrollio, Edit, View, Window, Help.
//
//  Scrollio is a menu-bar utility (LSUIElement), but while one of its windows is open it
//  is a regular app (Utils.showDockIcon) and owns the menu bar like any other. The main
//  menu of Main.storyboard is empty, which left only the Apple logo there, so the menu is
//  built here and installed at launch. The status-bar menu is separate (StatusItemManager).
//
//  View lists the places of the Settings window: Back (⌘[) and Forward (⌘]) through the
//  places that window showed (`PreferencesHistory`), then the panes in the sidebar's order
//  with ⌘1 … ⌘7, the one on show ticked. What it offers follows the Settings window
//  (`SettingsWindowState`): with none open a pane's item opens Settings there.
//

import Cocoa

/// The Settings window as the View menu sees it.
enum SettingsWindowState: Equatable {
    /// No Settings window (only the Welcome Guide or About is open): a pane's item opens
    /// Settings there; no way back or forward.
    case closed
    /// It is the key window: everything works; Back and Forward by its history.
    case inFront(pane: String?, canGoBack: Bool, canGoForward: Bool)
    /// A sheet or a popover of it has the keyboard, or a modal panel runs: nothing of View
    /// works, the pane on show stays ticked.
    case busy(pane: String?)
    /// Another window of Scrollio is key (the guide, About, an update): a pane's item
    /// brings Settings forward there; no way back or forward.
    case behind(pane: String?)

    /// The pane the window shows, which View ticks.
    var pane: String? {
        switch self {
        case .closed: return nil
        case let .inFront(pane, _, _), let .busy(pane), let .behind(pane): return pane
        }
    }

    /// Whether the panes' items can be chosen.
    var offersPanes: Bool {
        if case .busy = self { return false }
        return true
    }

    /// Whether Back or Forward can be chosen.
    func canStep(_ direction: PreferencesHistory.Direction) -> Bool {
        guard case let .inFront(_, back, forward) = self else { return false }
        return direction == .back ? back : forward
    }
}

final class MainMenuManager: NSObject {

    static let shared = MainMenuManager()

    /// Identifiers of the menus and of the items with an action of our own, so they can be
    /// found without their titles.
    enum Identifier {
        static let applicationMenu = NSUserInterfaceItemIdentifier("mainMenu.application")
        static let editMenu = NSUserInterfaceItemIdentifier("mainMenu.edit")
        static let viewMenu = NSUserInterfaceItemIdentifier("mainMenu.view")
        static let windowMenu = NSUserInterfaceItemIdentifier("mainMenu.window")
        static let helpMenu = NSUserInterfaceItemIdentifier("mainMenu.help")
        static let servicesMenu = NSUserInterfaceItemIdentifier("mainMenu.services")
        static let about = NSUserInterfaceItemIdentifier("mainMenu.about")
        static let checkForUpdates = NSUserInterfaceItemIdentifier("mainMenu.checkForUpdates")
        static let settings = NSUserInterfaceItemIdentifier("mainMenu.settings")
        static let welcomeGuide = NSUserInterfaceItemIdentifier("mainMenu.welcomeGuide")
        static let back = NSUserInterfaceItemIdentifier("mainMenu.back")
        static let forward = NSUserInterfaceItemIdentifier("mainMenu.forward")
        /// The item of the pane `identifier` (`PreferencesPane.identifier`), which is also
        /// the item's `representedObject`.
        static func pane(_ identifier: String) -> NSUserInterfaceItemIdentifier {
            return NSUserInterfaceItemIdentifier("mainMenu.pane.\(identifier)")
        }
    }

    /// The main menu with the submenus AppKit wants to know about.
    struct Menus {
        let main: NSMenu
        let services: NSMenu
        let window: NSMenu
        let help: NSMenu
    }

    // MARK: - Seams (tests replace them, so no window is shown)

    /// Opens the Preferences window, on the pane with this identifier when one is given.
    var showPreferences: (_ paneIdentifier: String?) -> Void = MainMenuManager.showPreferencesWindow
    /// Shows the standard About panel with these options.
    var showAboutPanel: (_ options: [NSApplication.AboutPanelOptionKey: Any]) -> Void = MainMenuManager.orderFrontAboutPanel
    /// Opens the Introduction window, like the Welcome Guide row of General.
    var showWelcomeGuide: () -> Void = IntroductionWindowController.showWelcomeGuide
    /// The updater: whether this copy updates itself and can check now, and the check.
    var updateStatus: () -> UpdateStatus = { UpdateCenter.shared.status }
    var checkForUpdates: () -> Void = { UpdateCenter.shared.checkForUpdates() }
    /// The Settings window as it stands, asked whenever View validates an item.
    var settingsWindow: () -> SettingsWindowState = MainMenuManager.liveSettingsWindowState
    /// Shows the pane with this identifier at its top, in a Settings window that comes
    /// forward or is opened for it.
    var showPane: (_ paneIdentifier: String) -> Void = MainMenuManager.showPaneInSettingsWindow
    /// Brings General's Updates box into view in the Settings window, once `showPane` has
    /// shown General there.
    var revealUpdates: () -> Void = { MainMenuManager.revealUpdates(in: MainMenuManager.settingsContent) }
    /// Says a line to VoiceOver (nothing happens without it).
    var announce: (String) -> Void = MainMenuManager.postAnnouncement
    /// One step back or forward through the places the Settings window showed.
    var step: (PreferencesHistory.Direction) -> Void = MainMenuManager.stepInSettingsWindow
    /// The event being handled, to tell a held key by.
    var currentEvent: () -> NSEvent? = { NSApp.currentEvent }

    // MARK: - Install

    /// The menus whose shortcuts fire once per key press (see `filterKeyDown`).
    private var singleFireMenus: [NSMenu] = []
    private var keyDownMonitor: Any?

    /// Makes the menu the app's main menu. Called once, at launch.
    func install(in application: NSApplication = NSApp) {
        // No window of this app has tabs: keep "Show Tab Bar" and its friends out of the menus.
        NSWindow.allowsAutomaticWindowTabbing = false
        let menus = makeMenus()
        application.mainMenu = menus.main
        application.servicesMenu = menus.services
        application.windowsMenu = menus.window
        application.helpMenu = menus.help
        if keyDownMonitor == nil {
            keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                // (Not `self?.filterKeyDown(event) ?? event`: that would turn a dropped event back into the event.)
                guard let self = self else { return event }
                return self.filterKeyDown(event)
            }
        }
    }

    // MARK: - Held shortcuts

    /// Drops the auto-repeats of the shortcuts of the Scrollio and Window menus, so a
    /// held ⌘W, ⌘Q, ⌘H, ⌘M or ⌘, acts once.
    ///
    /// The key recorders of the Buttons and Scrolling tabs take the key-down events with
    /// an event tap, but only until 0.7 to 1 s after a shortcut was recorded
    /// (KeyRecorder.recordingFeedbackDelay). Whoever records ⌘Q and keeps the keys down a
    /// moment longer sends the repeats to the app, and without this the menu would quit
    /// Scrollio (or close, hide or minimize the window) right after the recording. The
    /// Edit menu keeps its repeats (a held ⌘Z).
    func filterKeyDown(_ event: NSEvent) -> NSEvent? {
        guard event.type == .keyDown, event.isARepeat else { return event }
        let ignored = Self.isSingleFireShortcut(
            key: event.charactersIgnoringModifiers,
            modifiers: event.modifierFlags,
            in: singleFireMenus
        )
        return ignored ? nil : event
    }

    /// Whether `key` with `modifiers` is the shortcut of an item of `menus`.
    static func isSingleFireShortcut(key: String?, modifiers: NSEvent.ModifierFlags, in menus: [NSMenu]) -> Bool {
        guard let key = key?.lowercased(), !key.isEmpty else { return false }
        let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        let pressed = modifiers.intersection(relevant)
        return menus.contains { menu in
            menu.items.contains { item in
                !item.keyEquivalent.isEmpty
                    && item.keyEquivalent == key
                    && item.keyEquivalentModifierMask.intersection(relevant) == pressed
            }
        }
    }

    // MARK: - Build

    /// Builds the menus. The manager remembers the last ones it built, for `filterKeyDown`.
    func makeMenus() -> Menus {
        let main = NSMenu(title: "Main Menu")
        let services = NSMenu(title: text("main-menu-services"))
        let application = makeApplicationMenu(services: services)
        let window = makeWindowMenu()
        let help = makeHelpMenu()
        add(application, to: main)
        add(makeEditMenu(), to: main)
        add(makeViewMenu(), to: main)
        add(window, to: main)
        add(help, to: main)
        singleFireMenus = [application, window]
        return Menus(main: main, services: services, window: window, help: help)
    }

    /// The menu named after the app. AppKit shows the process name as its title, whatever
    /// is set here.
    private func makeApplicationMenu(services: NSMenu) -> NSMenu {
        let menu = NSMenu(title: text("main-menu-application"))
        menu.identifier = Identifier.applicationMenu

        let about = item("main-menu-about", #selector(showAbout(_:)), target: self)
        about.identifier = Identifier.about
        menu.addItem(about)
        // In every copy; one that does not update itself shows General › Updates instead
        // (`checkForUpdatesFromMenu`). With About it is one group, set apart from Settings…
        // as About is in Apple's menus.
        let updates = item("main-menu-check-for-updates", #selector(checkForUpdatesFromMenu(_:)), target: self)
        updates.identifier = Identifier.checkForUpdates
        menu.addItem(updates)
        menu.addItem(.separator())
        let settings = item("main-menu-settings", #selector(showSettings(_:)), key: ",", target: self)
        settings.identifier = Identifier.settings
        menu.addItem(settings)

        menu.addItem(.separator())
        let servicesItem = item("main-menu-services", nil)
        servicesItem.identifier = Identifier.servicesMenu
        servicesItem.submenu = services
        menu.addItem(servicesItem)

        menu.addItem(.separator())
        menu.addItem(item("main-menu-hide", #selector(NSApplication.hide(_:)), key: "h"))
        menu.addItem(item(
            "main-menu-hide-others",
            #selector(NSApplication.hideOtherApplications(_:)),
            key: "h",
            modifiers: [.command, .option]
        ))
        menu.addItem(item("main-menu-show-all", #selector(NSApplication.unhideAllApplications(_:))))

        menu.addItem(.separator())
        menu.addItem(item("main-menu-quit", #selector(NSApplication.terminate(_:)), key: "q"))
        return menu
    }

    /// Standard editing commands, so their shortcuts work in the text fields of the
    /// popovers. They go to the first responder.
    private func makeEditMenu() -> NSMenu {
        let menu = NSMenu(title: text("main-menu-edit"))
        menu.identifier = Identifier.editMenu
        menu.addItem(item("main-menu-undo", Selector(("undo:")), key: "z"))
        menu.addItem(item("main-menu-redo", Selector(("redo:")), key: "z", modifiers: [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("main-menu-cut", #selector(NSText.cut(_:)), key: "x"))
        menu.addItem(item("main-menu-copy", #selector(NSText.copy(_:)), key: "c"))
        menu.addItem(item("main-menu-paste", #selector(NSText.paste(_:)), key: "v"))
        menu.addItem(item("main-menu-select-all", #selector(NSText.selectAll(_:)), key: "a"))
        return menu
    }

    /// The places of the Settings window: Back and Forward through the ones it showed,
    /// then the panes as the sidebar lists them (its order, its names, a separator where it
    /// has a gap), each with ⌘ and its position. The items keep the system's defaults for
    /// keyboards without a [ or ] key (`allowsAutomaticKeyEquivalentLocalization`).
    private func makeViewMenu() -> NSMenu {
        let menu = NSMenu(title: text("main-menu-view"))
        menu.identifier = Identifier.viewMenu
        let back = item("main-menu-back", #selector(goBackInSettings(_:)), key: "[", target: self)
        back.identifier = Identifier.back
        menu.addItem(back)
        let forward = item("main-menu-forward", #selector(goForwardInSettings(_:)), key: "]", target: self)
        forward.identifier = Identifier.forward
        menu.addItem(forward)
        menu.addItem(.separator())
        for (index, pane) in PreferencesPane.all.enumerated() {
            if pane.startsGroup {
                menu.addItem(.separator())
            }
            let paneItem = NSMenuItem(
                title: pane.title,
                action: #selector(showPaneFromMenu(_:)),
                keyEquivalent: index < 9 ? String(index + 1) : ""
            )
            paneItem.keyEquivalentModifierMask = [.command]
            paneItem.target = self
            paneItem.identifier = Identifier.pane(pane.identifier)
            paneItem.representedObject = pane.identifier
            menu.addItem(paneItem)
        }
        return menu
    }

    /// AppKit lists the open windows under these items (NSApp.windowsMenu).
    private func makeWindowMenu() -> NSMenu {
        let menu = NSMenu(title: text("main-menu-window"))
        menu.identifier = Identifier.windowMenu
        menu.addItem(item("main-menu-minimize", #selector(NSWindow.performMiniaturize(_:)), key: "m"))
        menu.addItem(item("main-menu-zoom", #selector(NSWindow.performZoom(_:))))
        menu.addItem(item("main-menu-close", #selector(NSWindow.performClose(_:)), key: "w"))
        menu.addItem(.separator())
        menu.addItem(item("main-menu-bring-all-to-front", #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }

    private func makeHelpMenu() -> NSMenu {
        let menu = NSMenu(title: text("main-menu-help"))
        menu.identifier = Identifier.helpMenu
        let guide = item("main-menu-welcome-guide", #selector(showWelcomeGuideFromMenu(_:)), target: self)
        guide.identifier = Identifier.welcomeGuide
        menu.addItem(guide)
        return menu
    }

    // MARK: - Actions

    /// The About panel every Mac app shows: icon, name, version, a few lines, the copyright
    /// (the owner's example: Messages). Until 1.0.2 this opened Settings on General.
    @objc func showAbout(_ sender: Any?) {
        showAboutPanel(MainMenuManager.aboutPanelOptions())
    }

    /// What the standard panel is given beyond what it reads from the bundle itself (the
    /// icon, the name, "Version 1.0.3 (1730)" and the copyright line of Info.plist): what
    /// Scrollio is in one line, and where it lives. Pure.
    static func aboutPanelOptions() -> [NSApplication.AboutPanelOptionKey: Any] {
        let centred = NSMutableParagraphStyle()
        centred.alignment = .center
        centred.paragraphSpacing = 6
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: centred,
        ]
        let credits = NSMutableAttributedString(
            string: NSLocalizedString("about-tagline", comment: "") + "\n",
            attributes: attributes
        )
        var link = attributes
        link[.link] = PreferencesGeneralViewController.gitHubURL
        credits.append(NSAttributedString(string: aboutPanelLinkText, attributes: link))
        return [.credits: credits]
    }

    /// The repository as the panel shows it: the address without its scheme.
    static let aboutPanelLinkText: String = {
        let url = PreferencesGeneralViewController.gitHubURL
        return (url.host ?? "") + url.path
    }()

    /// Scrollio is a menu bar app and may not be in front: the panel comes forward with it.
    static func orderFrontAboutPanel(_ options: [NSApplication.AboutPanelOptionKey: Any]) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: options)
    }

    @objc func showSettings(_ sender: Any?) {
        showPreferences(nil)
    }

    @objc func showWelcomeGuideFromMenu(_ sender: Any?) {
        showWelcomeGuide()
    }

    /// A copy that updates itself checks at once. Any other copy (built from source, run
    /// from a disk image, an updater that did not start) cannot: Settings opens on General
    /// with its Updates box at the top, where the reason stands, and VoiceOver hears that
    /// reason (the box's line).
    @objc func checkForUpdatesFromMenu(_ sender: Any?) {
        let status = updateStatus()
        guard status.isAvailable else {
            showPane(PANEL_IDENTIFIER.general)
            revealUpdates()
            announce(text(PreferencesGeneralViewController.unavailableTextKey(for: status.availability)))
            return
        }
        checkForUpdates()
    }

    /// A high-priority VoiceOver announcement, as the key recorder's (nothing happens
    /// without VoiceOver).
    private static func postAnnouncement(_ text: String) {
        guard let app = NSApp else { return }
        NSAccessibility.post(element: app, notification: .announcementRequested, userInfo: [
            .announcement: text,
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }

    // MARK: - View

    /// A key that is held sends its key-down again and again. Back, Forward and a pane's
    /// item act on the first one only: a held ⌘[ goes one place back, and the repeats of a
    /// shortcut that a key recorder has just let go of (see `filterKeyDown`) do nothing.
    /// Told by the event, not by its character: macOS can take another key for [ and ] on
    /// a keyboard without them.
    private var isHeldKey: Bool {
        guard let event = currentEvent(), event.type == .keyDown else { return false }
        return event.isARepeat
    }

    @objc func goBackInSettings(_ sender: Any?) {
        guard !isHeldKey else { return }
        step(.back)
    }

    @objc func goForwardInSettings(_ sender: Any?) {
        guard !isHeldKey else { return }
        step(.forward)
    }

    @objc func showPaneFromMenu(_ sender: Any?) {
        guard !isHeldKey, let identifier = (sender as? NSMenuItem)?.representedObject as? String else { return }
        showPane(identifier)
    }

    /// The Settings window, while there is one.
    private static var settingsWindowController: NSWindowController? {
        return WindowManager.shared.refs[WINDOW_IDENTIFIER.preferencesWindowController]
    }

    private static var settingsContent: PreferencesSplitViewController? {
        return settingsWindowController?.contentViewController as? PreferencesSplitViewController
    }

    /// The Settings window as it stands. A modal panel (an alert of the updater, the ask to
    /// move the app) stops View whether or not Settings is open.
    static func liveSettingsWindowState() -> SettingsWindowState {
        guard let window = settingsWindowController?.window, let preferences = settingsContent else {
            return NSApp.modalWindow == nil ? .closed : .busy(pane: nil)
        }
        let pane = preferences.selectedPaneIdentifier
        if NSApp.modalWindow != nil || window.attachedSheet != nil {
            return .busy(pane: pane)
        }
        if let key = NSApp.keyWindow, key !== window, belongs(key, to: window) {
            return .busy(pane: pane)
        }
        guard window.isKeyWindow else { return .behind(pane: pane) }
        return .inFront(pane: pane, canGoBack: preferences.canStepBack, canGoForward: preferences.canStepForward)
    }

    /// Whether `window` hangs on `owner`: a popover of it (a child window) or a sheet, or
    /// one of those of such a window.
    static func belongs(_ window: NSWindow, to owner: NSWindow) -> Bool {
        var current: NSWindow? = window
        // (No window hangs this deep; the count only ends a chain that would go round.)
        for _ in 0..<16 {
            guard let candidate = current else { return false }
            if candidate === owner { return true }
            current = candidate.parent ?? candidate.sheetParent
        }
        return false
    }

    /// A pane's item of View: the Settings window in front, made when there is none, on
    /// that pane at its top (Apps on its list). A window made for it starts its history there.
    static func showPaneInSettingsWindow(_ paneIdentifier: String) {
        let isNew = settingsWindowController == nil
        WindowManager.shared.showWindow(withIdentifier: WINDOW_IDENTIFIER.preferencesWindowController)
        guard let preferences = settingsContent else { return }
        preferences.showPaneFromMenu(paneIdentifier)
        if isNew {
            preferences.startHistoryHere()
        }
    }

    /// General's Updates box in view, while `preferences` shows General and no sheet is on
    /// its window (a sheet keeps the pane under it: `selectPane`).
    static func revealUpdates(in preferences: PreferencesSplitViewController?) {
        guard let preferences, !preferences.hasSheet(),
              let general = preferences.selectedController as? PreferencesGeneralViewController
        else { return }
        // A window made for the item has not been laid out yet.
        preferences.view.window?.layoutIfNeeded()
        general.revealUpdates()
    }

    static func stepInSettingsWindow(_ direction: PreferencesHistory.Direction) {
        settingsContent?.step(direction)
    }

    /// Opens the Preferences window, on the pane `paneIdentifier` when one is given. Also
    /// used by the status-bar menu and the Welcome Guide. A window made here for a pane
    /// that was asked for starts its history there, not at the pane it remembered.
    static func showPreferencesWindow(paneIdentifier: String?) {
        let identifier = WINDOW_IDENTIFIER.preferencesWindowController
        let isNew = WindowManager.shared.refs[identifier] == nil
        WindowManager.shared.showWindow(withIdentifier: identifier)
        guard let paneIdentifier,
              let preferences = WindowManager.shared.refs[identifier]?.contentViewController as? PreferencesSplitViewController
        else { return }
        preferences.selectPane(withIdentifier: paneIdentifier)
        if isNew {
            preferences.startHistoryHere()
        }
    }

    // MARK: - Helpers

    private func text(_ key: String) -> String {
        return NSLocalizedString(key, comment: "")
    }

    /// An item titled with the string `key`. Without a target the action goes down the
    /// responder chain (first responder, window, application).
    private func item(
        _ key: String,
        _ action: Selector?,
        key keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = [.command],
        target: AnyObject? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: text(key), action: action, keyEquivalent: keyEquivalent)
        if !keyEquivalent.isEmpty {
            item.keyEquivalentModifierMask = modifiers
        }
        item.target = target
        return item
    }

    private func add(_ submenu: NSMenu, to main: NSMenu) {
        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        main.addItem(item)
    }
}

// MARK: - Validation

extension MainMenuManager: NSMenuItemValidation {
    /// "Check for Updates…" is there in every copy. In one that updates itself it is enabled
    /// while a check can start; in any other it shows General › Updates, so it works when a
    /// pane's item of View does (not under a sheet, a popover or a modal panel of Settings).
    /// View's items follow the Settings window: Back and Forward work while it is the key
    /// window and has a place that way; a pane's item works unless a sheet, a popover or a
    /// modal panel has the keyboard, and the pane on show is ticked. The other items of this
    /// target are always enabled.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(checkForUpdatesFromMenu(_:)):
            let status = updateStatus()
            return status.isAvailable ? status.canCheck : settingsWindow().offersPanes
        case #selector(goBackInSettings(_:)):
            return settingsWindow().canStep(.back)
        case #selector(goForwardInSettings(_:)):
            return settingsWindow().canStep(.forward)
        case #selector(showPaneFromMenu(_:)):
            let state = settingsWindow()
            let pane = menuItem.representedObject as? String
            menuItem.state = pane != nil && pane == state.pane ? .on : .off
            return state.offersPanes
        default:
            return true
        }
    }
}
