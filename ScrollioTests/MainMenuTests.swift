//
//  MainMenuTests.swift
//  MosTests
//
//  The app's menu bar (MainMenuManager): which menus and items it has, their shortcuts,
//  where each action goes, and that it is installed at launch. Menus are built and read,
//  never opened; the actions that would open a window are replaced.
//

import XCTest
@testable import Scrollio_Debug

final class MainMenuTests: XCTestCase {

    /// One row of a menu as the user reads it: title and shortcut, or a separator.
    private struct Row: Equatable, CustomStringConvertible {
        let title: String
        let shortcut: String

        static let separator = Row(title: "—", shortcut: "")

        init(title: String, shortcut: String = "") {
            self.title = title
            self.shortcut = shortcut
        }

        init(_ item: NSMenuItem) {
            if item.isSeparatorItem {
                self = .separator
                return
            }
            var shortcut = ""
            if !item.keyEquivalent.isEmpty {
                let flags = item.keyEquivalentModifierMask
                if flags.contains(.control) { shortcut += "⌃" }
                if flags.contains(.option) { shortcut += "⌥" }
                if flags.contains(.shift) { shortcut += "⇧" }
                if flags.contains(.command) { shortcut += "⌘" }
                shortcut += item.keyEquivalent.uppercased()
            }
            self.init(title: item.title, shortcut: shortcut)
        }

        var description: String {
            return shortcut.isEmpty ? title : "\(title) [\(shortcut)]"
        }
    }

    private var manager: MainMenuManager!
    private var menus: MainMenuManager.Menus!
    private var openedPreferences: [String?] = []
    private var openedWelcomeGuide = 0
    private var updateStatus = UpdateStatus()
    private var updateChecks = 0

    override func setUp() {
        super.setUp()
        openedPreferences = []
        openedWelcomeGuide = 0
        // Its own manager: the items hold their target weakly, and nothing here may open a window.
        manager = MainMenuManager()
        manager.showPreferences = { [unowned self] tab in self.openedPreferences.append(tab) }
        manager.showWelcomeGuide = { [unowned self] in self.openedWelcomeGuide += 1 }
        updateStatus = UpdateStatus()
        updateChecks = 0
        manager.updateStatus = { [unowned self] in self.updateStatus }
        manager.checkForUpdates = { [unowned self] in self.updateChecks += 1 }
        menus = manager.makeMenus()
    }

    override func tearDown() {
        menus = nil
        manager = nil
        super.tearDown()
    }

    private func submenu(_ identifier: NSUserInterfaceItemIdentifier) throws -> NSMenu {
        return try XCTUnwrap(menus.main.items.compactMap(\.submenu).first { $0.identifier == identifier })
    }

    private func rows(_ menu: NSMenu) -> [Row] {
        return menu.items.map(Row.init)
    }

    private func item(_ title: String, in menu: NSMenu) throws -> NSMenuItem {
        return try XCTUnwrap(menu.items.first { $0.title == title }, "no item \"\(title)\"")
    }

    private func allItems(of menu: NSMenu) -> [NSMenuItem] {
        return menu.items.flatMap { [$0] + ($0.submenu.map(allItems(of:)) ?? []) }
    }

    /// What a click on the item does.
    private func choose(_ item: NSMenuItem) -> Bool {
        guard let action = item.action else { return false }
        return NSApp.sendAction(action, to: item.target, from: item)
    }

    // MARK: - Structure

    func testMenuBarHasTheFourMenus() {
        XCTAssertEqual(menus.main.items.map(\.title), ["Scrollio", "Edit", "Window", "Help"])
        XCTAssertEqual(menus.main.items.compactMap(\.submenu).map(\.title), ["Scrollio", "Edit", "Window", "Help"])
        XCTAssertEqual(
            menus.main.items.map { $0.submenu?.identifier },
            [
                MainMenuManager.Identifier.applicationMenu,
                MainMenuManager.Identifier.editMenu,
                MainMenuManager.Identifier.windowMenu,
                MainMenuManager.Identifier.helpMenu,
            ]
        )
    }

    func testApplicationMenu() throws {
        let menu = try submenu(MainMenuManager.Identifier.applicationMenu)
        XCTAssertEqual(rows(menu), [
            Row(title: "About Scrollio"),
            Row(title: "Check for Updates…"),
            Row(title: "Settings…", shortcut: "⌘,"),
            .separator,
            Row(title: "Services"),
            .separator,
            Row(title: "Hide Scrollio", shortcut: "⌘H"),
            Row(title: "Hide Others", shortcut: "⌥⌘H"),
            Row(title: "Show All"),
            .separator,
            Row(title: "Quit Scrollio", shortcut: "⌘Q"),
        ])
        // The application menu is the first one: that is how AppKit recognises it.
        XCTAssertTrue(menus.main.items.first?.submenu === menu)
    }

    func testServicesIsTheSubmenuAppKitFills() throws {
        let menu = try submenu(MainMenuManager.Identifier.applicationMenu)
        let services = try item("Services", in: menu)
        XCTAssertTrue(services.submenu === menus.services)
        XCTAssertTrue(menus.services.items.isEmpty, "macOS fills it")
    }

    func testEditMenu() throws {
        let menu = try submenu(MainMenuManager.Identifier.editMenu)
        XCTAssertEqual(rows(menu), [
            Row(title: "Undo", shortcut: "⌘Z"),
            Row(title: "Redo", shortcut: "⇧⌘Z"),
            .separator,
            Row(title: "Cut", shortcut: "⌘X"),
            Row(title: "Copy", shortcut: "⌘C"),
            Row(title: "Paste", shortcut: "⌘V"),
            Row(title: "Select All", shortcut: "⌘A"),
        ])
    }

    func testWindowMenu() throws {
        let menu = try submenu(MainMenuManager.Identifier.windowMenu)
        XCTAssertEqual(rows(menu), [
            Row(title: "Minimize", shortcut: "⌘M"),
            Row(title: "Zoom"),
            Row(title: "Close", shortcut: "⌘W"),
            .separator,
            Row(title: "Bring All to Front"),
        ])
        XCTAssertTrue(menu === menus.window)
    }

    func testHelpMenu() throws {
        let menu = try submenu(MainMenuManager.Identifier.helpMenu)
        XCTAssertEqual(rows(menu), [Row(title: "Welcome Guide")])
        XCTAssertTrue(menu === menus.help)
    }

    func testNoShortcutIsUsedTwice() {
        let shortcuts = allItems(of: menus.main).map(Row.init).map(\.shortcut).filter { !$0.isEmpty }
        XCTAssertEqual(shortcuts.count, Set(shortcuts).count, "\(shortcuts)")
        // Every shortcut the menu bar claims while a Scrollio window is in front. A new one
        // has to be checked against the key recorders of the Buttons and Scrolling tabs.
        XCTAssertEqual(
            Set(shortcuts),
            ["⌘,", "⌘H", "⌥⌘H", "⌘Q", "⌘Z", "⇧⌘Z", "⌘X", "⌘C", "⌘V", "⌘A", "⌘M", "⌘W"]
        )
    }

    func testEveryTitleIsLocalized() {
        for item in allItems(of: menus.main) where !item.isSeparatorItem {
            XCTAssertFalse(item.title.isEmpty)
            XCTAssertFalse(item.title.hasPrefix("main-menu-"), "\(item.title) shows the raw key")
        }
    }

    // MARK: - Actions

    func testStandardItemsSendTheStandardActionsDownTheResponderChain() throws {
        let application = try submenu(MainMenuManager.Identifier.applicationMenu)
        let edit = try submenu(MainMenuManager.Identifier.editMenu)
        let window = try submenu(MainMenuManager.Identifier.windowMenu)
        let expected: [(menu: NSMenu, title: String, action: Selector, receiver: NSObject.Type)] = [
            (application, "Hide Scrollio", #selector(NSApplication.hide(_:)), NSApplication.self),
            (application, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), NSApplication.self),
            (application, "Show All", #selector(NSApplication.unhideAllApplications(_:)), NSApplication.self),
            (application, "Quit Scrollio", #selector(NSApplication.terminate(_:)), NSApplication.self),
            (edit, "Undo", Selector(("undo:")), NSWindow.self),
            (edit, "Redo", Selector(("redo:")), NSWindow.self),
            (edit, "Cut", #selector(NSText.cut(_:)), NSTextView.self),
            (edit, "Copy", #selector(NSText.copy(_:)), NSTextView.self),
            (edit, "Paste", #selector(NSText.paste(_:)), NSTextView.self),
            (edit, "Select All", #selector(NSText.selectAll(_:)), NSTextView.self),
            (window, "Minimize", #selector(NSWindow.performMiniaturize(_:)), NSWindow.self),
            (window, "Zoom", #selector(NSWindow.performZoom(_:)), NSWindow.self),
            (window, "Close", #selector(NSWindow.performClose(_:)), NSWindow.self),
            (window, "Bring All to Front", #selector(NSApplication.arrangeInFront(_:)), NSApplication.self),
        ]
        for (menu, title, action, receiver) in expected {
            let item = try item(title, in: menu)
            XCTAssertEqual(item.action, action, title)
            XCTAssertNil(item.target, "\(title) goes to the first responder")
            XCTAssertTrue(receiver.instancesRespond(to: action), "\(receiver) does not implement \(action)")
        }
    }

    /// The name and version are on top of General (there is no About pane any more).
    func testAboutOpensThePreferencesOnGeneral() throws {
        let about = try item("About Scrollio", in: try submenu(MainMenuManager.Identifier.applicationMenu))
        XCTAssertEqual(about.identifier, MainMenuManager.Identifier.about)
        XCTAssertTrue(about.target === manager)
        XCTAssertTrue(choose(about))
        XCTAssertEqual(openedPreferences, [PANEL_IDENTIFIER.general])
        XCTAssertEqual(PANEL_IDENTIFIER.general, "general")
        XCTAssertEqual(openedWelcomeGuide, 0)
    }

    func testSettingsOpensThePreferencesAsTheyAre() throws {
        let settings = try item("Settings…", in: try submenu(MainMenuManager.Identifier.applicationMenu))
        XCTAssertEqual(settings.identifier, MainMenuManager.Identifier.settings)
        XCTAssertTrue(settings.target === manager)
        XCTAssertTrue(choose(settings))
        XCTAssertEqual(openedPreferences, [nil])
    }

    func testWelcomeGuideOpensTheIntroduction() throws {
        let guide = try item("Welcome Guide", in: try submenu(MainMenuManager.Identifier.helpMenu))
        XCTAssertEqual(guide.identifier, MainMenuManager.Identifier.welcomeGuide)
        XCTAssertTrue(guide.target === manager)
        XCTAssertTrue(choose(guide))
        XCTAssertEqual(openedWelcomeGuide, 1)
        XCTAssertEqual(openedPreferences, [])
    }

    func testItemsWithATargetAreEnabledByIt() {
        // AppKit enables an item when its target implements the action.
        // (An item with a submenu has AppKit's own target and action: opening the submenu.)
        let targeted = allItems(of: menus.main).filter { $0.target != nil && !$0.hasSubmenu }
        XCTAssertEqual(targeted.map(\.title), ["About Scrollio", "Check for Updates…", "Settings…", "Welcome Guide"])
        for item in targeted {
            XCTAssertTrue(item.target === manager, item.title)
            XCTAssertTrue(item.action.map { manager.responds(to: $0) } ?? false, item.title)
        }
    }

    // MARK: - Updates

    /// "Check for Updates…" is there only in a copy that updates itself (a released one),
    /// and enabled while a check can start. AppKit asks when the menu opens.
    func testCheckForUpdatesFollowsTheUpdater() throws {
        let menu = try submenu(MainMenuManager.Identifier.applicationMenu)
        let check = try XCTUnwrap(menu.items.first { $0.identifier == MainMenuManager.Identifier.checkForUpdates })
        XCTAssertEqual(menu.items.firstIndex(of: check), 1, "right under About, where a Mac app has it")

        // Built from source, from a disk image, or the updater did not start: no item.
        for availability in [UpdateAvailability.builtFromSource, .wrongPlace, .failed] {
            updateStatus = UpdateStatus(availability: availability, canCheck: true)
            XCTAssertFalse(manager.validateMenuItem(check), "\(availability)")
            XCTAssertTrue(check.isHidden, "\(availability)")
        }

        updateStatus = UpdateStatus(availability: .available, canCheck: true)
        XCTAssertTrue(manager.validateMenuItem(check))
        XCTAssertFalse(check.isHidden)
        XCTAssertTrue(choose(check))
        XCTAssertEqual(updateChecks, 1)
        XCTAssertEqual(openedPreferences, [])

        // A check runs in the background: shown, dimmed.
        updateStatus = UpdateStatus(availability: .available, canCheck: false)
        XCTAssertFalse(manager.validateMenuItem(check))
        XCTAssertFalse(check.isHidden)
    }

    func testTheOtherItemsOfTheManagerAreAlwaysEnabled() throws {
        updateStatus = UpdateStatus()
        for item in allItems(of: menus.main) where item.target === manager && item.identifier != MainMenuManager.Identifier.checkForUpdates {
            XCTAssertTrue(manager.validateMenuItem(item), item.title)
            XCTAssertFalse(item.isHidden, item.title)
        }
    }

    // MARK: - Held shortcuts

    /// A key-down as AppKit would hand it to the app. It is only built, never posted.
    private func keyDown(_ key: String, _ modifiers: NSEvent.ModifierFlags, isRepeat: Bool) throws -> NSEvent {
        return try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: key,
            charactersIgnoringModifiers: key,
            isARepeat: isRepeat,
            keyCode: 0
        ))
    }

    func testAHeldShortcutOfTheScrollioAndWindowMenusActsOnce() throws {
        // The recorders of the Buttons and Scrolling tabs let go of the keyboard 0.7 s after
        // a shortcut was recorded: the repeats of a ⌘Q that is still held must not quit the app.
        let once: [(String, NSEvent.ModifierFlags)] = [
            (",", [.command]), ("h", [.command]), ("h", [.command, .option]),
            ("q", [.command]), ("m", [.command]), ("w", [.command]),
        ]
        for (key, modifiers) in once {
            let first = try keyDown(key, modifiers, isRepeat: false)
            XCTAssertTrue(manager.filterKeyDown(first) === first, "the first ⌘\(key) reaches the menu")
            let held = try keyDown(key, modifiers, isRepeat: true)
            XCTAssertNil(manager.filterKeyDown(held), "a repeat of \(key) with \(modifiers.rawValue) still reaches the menu")
        }
        // Caps Lock and the like do not make it another shortcut; the character may come in upper case.
        XCTAssertNil(manager.filterKeyDown(try keyDown("Q", [.command, .capsLock], isRepeat: true)))
    }

    func testOtherRepeatsPassThrough() throws {
        let passing: [(String, NSEvent.ModifierFlags)] = [
            // The Edit menu keeps its repeats: a held ⌘Z undoes step after step.
            ("z", [.command]), ("z", [.command, .shift]), ("x", [.command]), ("c", [.command]),
            ("v", [.command]), ("a", [.command]),
            // Not shortcuts of the menu bar at all.
            ("w", []), ("w", [.command, .shift]), ("q", [.control]), ("k", [.command]), ("h", [.option]),
        ]
        for (key, modifiers) in passing {
            let held = try keyDown(key, modifiers, isRepeat: true)
            XCTAssertTrue(manager.filterKeyDown(held) === held, "\(key) with \(modifiers.rawValue) was dropped")
        }
    }

    func testSingleFireShortcutsAreThoseOfTheTwoMenus() throws {
        let application = try submenu(MainMenuManager.Identifier.applicationMenu)
        let window = try submenu(MainMenuManager.Identifier.windowMenu)
        let edit = try submenu(MainMenuManager.Identifier.editMenu)
        XCTAssertTrue(MainMenuManager.isSingleFireShortcut(key: "q", modifiers: [.command], in: [application, window]))
        XCTAssertTrue(MainMenuManager.isSingleFireShortcut(key: "W", modifiers: [.command], in: [window]))
        XCTAssertFalse(MainMenuManager.isSingleFireShortcut(key: "w", modifiers: [.command], in: [application]))
        XCTAssertFalse(MainMenuManager.isSingleFireShortcut(key: "z", modifiers: [.command], in: [application, window]))
        XCTAssertTrue(MainMenuManager.isSingleFireShortcut(key: "z", modifiers: [.command], in: [edit]))
        XCTAssertFalse(MainMenuManager.isSingleFireShortcut(key: nil, modifiers: [.command], in: [application, window]))
        XCTAssertFalse(MainMenuManager.isSingleFireShortcut(key: "", modifiers: [], in: [application, window]))
    }

    // MARK: - Installed at launch

    func testTheAppDelegateInstalledTheMenu() throws {
        let installed = try XCTUnwrap(NSApp.mainMenu)
        XCTAssertEqual(
            installed.items.map { $0.submenu?.identifier },
            [
                MainMenuManager.Identifier.applicationMenu,
                MainMenuManager.Identifier.editMenu,
                MainMenuManager.Identifier.windowMenu,
                MainMenuManager.Identifier.helpMenu,
            ]
        )
        XCTAssertEqual(NSApp.windowsMenu?.identifier, MainMenuManager.Identifier.windowMenu)
        XCTAssertEqual(NSApp.helpMenu?.identifier, MainMenuManager.Identifier.helpMenu)
        let application = try XCTUnwrap(installed.items.first?.submenu)
        let services = try XCTUnwrap(application.items.first { $0.identifier == MainMenuManager.Identifier.servicesMenu })
        XCTAssertTrue(NSApp.servicesMenu === services.submenu)
        // Our own items point at the shared manager, which lives as long as the app.
        for identifier in [MainMenuManager.Identifier.about, MainMenuManager.Identifier.settings] {
            let item = try XCTUnwrap(application.items.first { $0.identifier == identifier })
            XCTAssertTrue(item.target === MainMenuManager.shared)
        }
        XCTAssertFalse(NSWindow.allowsAutomaticWindowTabbing)
    }

    func testInstallSetsTheMenusOfTheApplication() {
        // What install() assigns, read back from the menus it builds.
        XCTAssertTrue(menus.main.items.contains { $0.submenu === menus.window })
        XCTAssertTrue(menus.main.items.contains { $0.submenu === menus.help })
        XCTAssertTrue(allItems(of: menus.main).contains { $0.submenu === menus.services })
    }
}

/// "About Scrollio" needs a way to open the Preferences on a given pane (General).
final class PreferencesPaneSelectionTests: XCTestCase {

    private func makePreferences() throws -> PreferencesSplitViewController {
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesSplitViewController.self))
        let windowController = try XCTUnwrap(
            storyboard.instantiateController(withIdentifier: WINDOW_IDENTIFIER.preferencesWindowController) as? NSWindowController
        )
        let preferences = try XCTUnwrap(windowController.contentViewController as? PreferencesSplitViewController)
        _ = preferences.view
        addTeardownBlock { windowController.close() }
        return preferences
    }

    func testSelectsAPaneByItsIdentifier() throws {
        let preferences = try makePreferences()
        XCTAssertEqual(preferences.selectedPaneIdentifier, PANEL_IDENTIFIER.scrolling)

        XCTAssertTrue(preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.general))
        XCTAssertEqual(preferences.selectedPaneIdentifier, PANEL_IDENTIFIER.general)
        XCTAssertTrue(preferences.selectedController is PreferencesGeneralViewController)
        XCTAssertEqual(preferences.sidebar.selectedIdentifier, PANEL_IDENTIFIER.general)
        XCTAssertEqual(preferences.view.window?.title, "General")

        // Already there: nothing changes.
        XCTAssertTrue(preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.general))
        XCTAssertEqual(preferences.selectedPaneIdentifier, PANEL_IDENTIFIER.general)

        XCTAssertTrue(preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.buttons))
        XCTAssertEqual(preferences.view.window?.title, "Buttons")
    }

    func testAnUnknownIdentifierChangesNothing() throws {
        let preferences = try makePreferences()
        XCTAssertTrue(preferences.selectPane(withIdentifier: PANEL_IDENTIFIER.buttons))
        XCTAssertFalse(preferences.selectPane(withIdentifier: "no-such-pane"))
        XCTAssertEqual(preferences.selectedPaneIdentifier, PANEL_IDENTIFIER.buttons)
        XCTAssertEqual(preferences.sidebar.selectedIdentifier, PANEL_IDENTIFIER.buttons)
    }
}
