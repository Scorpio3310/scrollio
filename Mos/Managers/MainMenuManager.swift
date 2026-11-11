//
//  MainMenuManager.swift
//  Mos
//  The app's menu bar: Scrollio, Edit, Window, Help.
//
//  Scrollio is a menu-bar utility (LSUIElement), but while one of its windows is open it
//  is a regular app (Utils.showDockIcon) and owns the menu bar like any other. The main
//  menu of Main.storyboard is empty, which left only the Apple logo there, so the menu is
//  built here and installed at launch. The status-bar menu is separate (StatusItemManager).
//

import Cocoa

final class MainMenuManager: NSObject {

    static let shared = MainMenuManager()

    /// Identifiers of the menus and of the items with an action of our own, so they can be
    /// found without their titles.
    enum Identifier {
        static let applicationMenu = NSUserInterfaceItemIdentifier("mainMenu.application")
        static let editMenu = NSUserInterfaceItemIdentifier("mainMenu.edit")
        static let windowMenu = NSUserInterfaceItemIdentifier("mainMenu.window")
        static let helpMenu = NSUserInterfaceItemIdentifier("mainMenu.help")
        static let servicesMenu = NSUserInterfaceItemIdentifier("mainMenu.services")
        static let about = NSUserInterfaceItemIdentifier("mainMenu.about")
        static let settings = NSUserInterfaceItemIdentifier("mainMenu.settings")
        static let welcomeGuide = NSUserInterfaceItemIdentifier("mainMenu.welcomeGuide")
    }

    /// The main menu with the submenus AppKit wants to know about.
    struct Menus {
        let main: NSMenu
        let services: NSMenu
        let window: NSMenu
        let help: NSMenu
    }

    // MARK: - Seams (tests replace them, so no window is shown)

    /// Opens the Preferences window, on the tab with this identifier when one is given.
    var showPreferences: (_ tabIdentifier: String?) -> Void = MainMenuManager.showPreferencesWindow
    /// Opens the Introduction window, like the link in the About tab.
    var showWelcomeGuide: () -> Void = IntroductionWindowController.showWelcomeGuide

    // MARK: - Install

    /// Makes the menu the app's main menu. Called once, at launch.
    func install(in application: NSApplication = NSApp) {
        // No window of this app has tabs: keep "Show Tab Bar" and its friends out of the menus.
        NSWindow.allowsAutomaticWindowTabbing = false
        let menus = makeMenus()
        application.mainMenu = menus.main
        application.servicesMenu = menus.services
        application.windowsMenu = menus.window
        application.helpMenu = menus.help
    }

    // MARK: - Build

    func makeMenus() -> Menus {
        let main = NSMenu(title: "Main Menu")
        let services = NSMenu(title: text("main-menu-services"))
        let window = makeWindowMenu()
        let help = makeHelpMenu()
        add(makeApplicationMenu(services: services), to: main)
        add(makeEditMenu(), to: main)
        add(window, to: main)
        add(help, to: main)
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

    @objc func showAbout(_ sender: Any?) {
        showPreferences(AboutPreferencesViewController.tabIdentifier)
    }

    @objc func showSettings(_ sender: Any?) {
        showPreferences(nil)
    }

    @objc func showWelcomeGuideFromMenu(_ sender: Any?) {
        showWelcomeGuide()
    }

    private static func showPreferencesWindow(tabIdentifier: String?) {
        let identifier = WINDOW_IDENTIFIER.preferencesWindowController
        WindowManager.shared.showWindow(withIdentifier: identifier)
        guard let tabIdentifier,
              let tabs = WindowManager.shared.refs[identifier]?.contentViewController as? PreferencesTabViewController
        else { return }
        tabs.selectTab(withIdentifier: tabIdentifier)
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
