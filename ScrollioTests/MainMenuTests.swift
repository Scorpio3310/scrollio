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
    private var shownAboutPanels: [[NSApplication.AboutPanelOptionKey: Any]] = []
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
        shownAboutPanels = []
        manager.showAboutPanel = { [unowned self] options in self.shownAboutPanels.append(options) }
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

    /// "About Scrollio" shows the About panel every Mac app shows, not Settings: the
    /// bundle gives the icon, the name, the version and the copyright; Scrollio adds what
    /// it is in one line and where it lives.
    func testAboutShowsTheStandardAboutPanel() throws {
        let about = try item("About Scrollio", in: try submenu(MainMenuManager.Identifier.applicationMenu))
        XCTAssertEqual(about.identifier, MainMenuManager.Identifier.about)
        XCTAssertTrue(about.target === manager)
        XCTAssertTrue(choose(about))
        XCTAssertEqual(openedPreferences, [], "no Settings window")
        XCTAssertEqual(openedWelcomeGuide, 0)
        XCTAssertEqual(shownAboutPanels.count, 1)

        let options = try XCTUnwrap(shownAboutPanels.first)
        XCTAssertEqual(Array(options.keys), [.credits], "version, name, icon and copyright are the bundle's own")
        let credits = try XCTUnwrap(options[.credits] as? NSAttributedString)
        XCTAssertEqual(credits.string, "Smooth, trackpad-like scrolling for any mouse.\ngithub.com/Scorpio3310/scrollio")
        let linkStart = (credits.string as NSString).range(of: "github.com").location
        XCTAssertEqual(
            credits.attribute(.link, at: linkStart, effectiveRange: nil) as? URL,
            URL(string: "https://github.com/Scorpio3310/scrollio")
        )
        XCTAssertNil(credits.attribute(.link, at: 0, effectiveRange: nil), "the line of words is no link")
        // The bundle's own lines, which the panel shows without being told.
        let info = Bundle(for: AppDelegate.self).infoDictionary ?? [:]
        XCTAssertNotNil(info["CFBundleShortVersionString"] as? String)
        XCTAssertTrue((info["NSHumanReadableCopyright"] as? String ?? "").contains("Caldis (Mos)"))
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

/// The Preferences can be opened on a given pane (the Dock icon and the update rows use it).
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

/// The places a Settings window showed, for View › Back and Forward (PreferencesHistory): pure.
final class PreferencesHistoryTests: XCTestCase {

    private let scrolling = PreferencesPlace(pane: "scrolling")
    private let buttons = PreferencesPlace(pane: "buttons")
    private let general = PreferencesPlace(pane: "general")
    private let apps = PreferencesPlace(pane: "application")
    private let safari = PreferencesPlace(pane: "application", page: "/Applications/Safari.app")
    private let figma = PreferencesPlace(pane: "application", page: "/Applications/Figma.app")

    private let everything: (PreferencesPlace) -> Bool = { _ in true }

    private func history(_ places: PreferencesPlace...) -> PreferencesHistory {
        var history = PreferencesHistory()
        places.forEach { history.visit($0) }
        return history
    }

    func testAVisitIsAddedAndDropsWhatWasAhead() {
        var history = PreferencesHistory()
        XCTAssertNil(history.current)
        XCTAssertFalse(history.canStep(.back, exists: everything))
        XCTAssertFalse(history.canStep(.forward, exists: everything))

        history.visit(scrolling)
        XCTAssertEqual(history.places, [scrolling])
        XCTAssertEqual(history.current, scrolling)
        XCTAssertFalse(history.canStep(.back, exists: everything), "one place is no history")
        XCTAssertFalse(history.canStep(.forward, exists: everything))

        history.visit(buttons)
        history.visit(general)
        XCTAssertEqual(history.places, [scrolling, buttons, general])
        XCTAssertEqual(history.current, general)
        XCTAssertEqual(history.step(.back, exists: everything), buttons)
        XCTAssertEqual(history.step(.back, exists: everything), scrolling)
        XCTAssertNil(history.step(.back, exists: everything))
        XCTAssertEqual(history.current, scrolling, "a step that cannot be made changes nothing")
        XCTAssertEqual(history.step(.forward, exists: everything), buttons)
        XCTAssertEqual(history.places, [scrolling, buttons, general], "a step adds and drops nothing")

        // A visit from the middle: what was ahead is gone.
        history.visit(apps)
        XCTAssertEqual(history.places, [scrolling, buttons, apps])
        XCTAssertEqual(history.current, apps)
        XCTAssertFalse(history.canStep(.forward, exists: everything))
        XCTAssertEqual(history.step(.back, exists: everything), buttons)
    }

    func testTheSamePlaceTwiceIsOneEntry() {
        var history = self.history(scrolling, scrolling, buttons, buttons)
        XCTAssertEqual(history.places, [scrolling, buttons])

        // Also in the middle: what is ahead stays.
        XCTAssertEqual(history.step(.back, exists: everything), scrolling)
        history.visit(scrolling)
        XCTAssertEqual(history.places, [scrolling, buttons])
        XCTAssertTrue(history.canStep(.forward, exists: everything))

        // A page counts by its app.
        history.visit(safari)
        history.visit(safari)
        XCTAssertEqual(history.places, [scrolling, apps, safari])
        XCTAssertEqual(history.current, safari)
    }

    func testAPageAlwaysHasItsListBeforeIt() {
        // From another pane (a jump: "Show in Safari › Buttons", "Settings for Safari…"):
        // Back is the list, as the title bar's button, and then the pane the jump came from.
        var history = self.history(buttons, safari)
        XCTAssertEqual(history.places, [buttons, apps, safari])
        XCTAssertEqual(history.step(.back, exists: everything), apps)
        XCTAssertEqual(history.step(.back, exists: everything), buttons)

        // From the list itself: the list is not added twice.
        history = self.history(apps, safari)
        XCTAssertEqual(history.places, [apps, safari])

        // From one app's page to another's.
        history = self.history(apps, safari, figma)
        XCTAssertEqual(history.places, [apps, safari, apps, figma])
        XCTAssertEqual(history.current, figma)
        XCTAssertEqual(history.step(.back, exists: everything), apps)
        XCTAssertEqual(history.step(.back, exists: everything), safari)
        XCTAssertEqual(history.step(.back, exists: everything), apps)
        XCTAssertNil(history.step(.back, exists: everything))

        // A window that starts on a page.
        history = self.history(safari)
        XCTAssertEqual(history.places, [apps, safari])
        XCTAssertEqual(history.current, safari)
        XCTAssertEqual(safari.list, apps)
        XCTAssertEqual(apps.list, apps)
    }

    func testLeavingAPageToItsListIsAStepBack() {
        var history = self.history(scrolling, apps, safari)
        history.visit(apps)
        XCTAssertEqual(history.places, [scrolling, apps, safari], "the page stays ahead")
        XCTAssertEqual(history.current, apps)
        XCTAssertEqual(history.step(.forward, exists: everything), safari, "Forward opens the page again")

        // Left again, and on to another pane: now the page is gone from what is ahead.
        history.visit(apps)
        history.visit(general)
        XCTAssertEqual(history.places, [scrolling, apps, general])
        XCTAssertFalse(history.canStep(.forward, exists: everything))
    }

    func testAStepSkipsAGoneAppAndThePlaceOnShow() throws {
        var gone: Set<String> = []
        let exists: (PreferencesPlace) -> Bool = { place in place.page.map { !gone.contains($0) } ?? true }
        var history = self.history(apps, safari, figma, general)
        XCTAssertEqual(history.places, [apps, safari, apps, figma, general])
        let all = history.places

        // Safari left the list. Back from Figma's page is the list; before it stand only
        // Safari's page and the list again, the place on show: no further way back.
        gone = [try XCTUnwrap(safari.page)]
        XCTAssertEqual(history.step(.back, exists: exists), figma)
        XCTAssertEqual(history.step(.back, exists: exists), apps)
        XCTAssertEqual(history.position, 2)
        XCTAssertFalse(history.canStep(.back, exists: exists))
        XCTAssertNil(history.step(.back, exists: exists))
        XCTAssertEqual(history.position, 2)

        // The app is back (Undo, an import): its page is in the history again.
        gone = []
        XCTAssertEqual(history.places, all, "nothing was deleted")
        XCTAssertEqual(history.step(.back, exists: exists), safari)
        XCTAssertEqual(history.step(.back, exists: exists), apps)
        XCTAssertEqual(history.position, 0)

        // Gone again: Forward from the first list passes the page and the same list.
        gone = [try XCTUnwrap(safari.page)]
        XCTAssertEqual(history.step(.forward, exists: exists), figma)
        XCTAssertEqual(history.position, 3)
        XCTAssertEqual(history.step(.forward, exists: exists), general)
        XCTAssertFalse(history.canStep(.forward, exists: exists))

        // Every page gone: from General straight to the list.
        gone = [try XCTUnwrap(safari.page), try XCTUnwrap(figma.page)]
        XCTAssertEqual(history.step(.back, exists: exists), apps)
        XCTAssertEqual(history.position, 2)
        XCTAssertEqual(history.places, all)
    }

    func testAHundredPlacesAndNeverAPageFirst() {
        XCTAssertEqual(PreferencesHistory.limit, 100)
        var history = PreferencesHistory()
        for index in 0..<150 {
            history.visit(index % 2 == 0 ? scrolling : buttons)
        }
        XCTAssertEqual(history.places.count, 100)
        XCTAssertEqual(history.current, buttons, "the newest stay")
        XCTAssertEqual(history.position, 99)
        XCTAssertEqual(history.places.first, scrolling)

        // The oldest place to go is a list whose page would then stand first: it goes too.
        history = self.history(apps, safari, general)
        for index in 0..<98 {
            history.visit(index % 2 == 0 ? scrolling : buttons)
        }
        XCTAssertEqual(history.places.count, 99)
        XCTAssertEqual(history.places.first, general)
        XCTAssertFalse(history.places.contains(safari))
        XCTAssertEqual(history.current, buttons)
        var steps = 0
        while history.step(.back, exists: everything) != nil {
            steps += 1
        }
        XCTAssertEqual(steps, 98)
        XCTAssertEqual(history.current, general)
    }
}

/// Back and Forward in a Settings window (the history of PreferencesSplitViewController),
/// and the pane items of the View menu. The window is the app's, with its content rebuilt
/// around the test's own stores, and is never shown: the Apps pane is told by hand that it
/// left the window (`viewDidDisappear`), as PreferencesApplicationTests does.
final class PreferencesNavigationTests: XCTestCase {

    private static let calculator = "/System/Applications/Calculator.app"
    private static let calculatorProgram = "/System/Applications/Calculator.app/Contents/MacOS/Calculator"
    private static let textEdit = "/System/Applications/TextEdit.app"
    private static let calculatorApp = AppSmoothing.App(name: "Calculator", bundlePath: calculator, executablePath: calculatorProgram)

    private static let scrolling = PreferencesPlace(pane: PANEL_IDENTIFIER.scrolling)
    private static let buttons = PreferencesPlace(pane: PANEL_IDENTIFIER.buttons)
    private static let general = PreferencesPlace(pane: PANEL_IDENTIFIER.general)
    private static let apps = PreferencesPlace(pane: PANEL_IDENTIFIER.application)
    private static let calculatorPage = PreferencesPlace(pane: PANEL_IDENTIFIER.application, page: calculator)
    private static let textEditPage = PreferencesPlace(pane: PANEL_IDENTIFIER.application, page: textEdit)

    private var originalApplications: EnhanceArray<Application>!
    private var pageDefaults: TestDefaults!

    private var windowController: PreferencesWindowController!
    private var window: NSWindow!
    private var preferences: PreferencesSplitViewController!
    private var apps: PreferencesApplicationViewController!

    override func setUp() {
        super.setUp()
        originalApplications = Options.shared.application.applications
        // A fresh container, so the tests never edit the one they restore.
        Options.shared.application.applications = Self.makeStore([
            Application(path: Self.calculator), Application(path: Self.textEdit),
        ])
        pageDefaults = TestDefaults.makeStore(for: self)
    }

    override func tearDown() {
        windowController?.close()
        windowController = nil
        window = nil
        preferences = nil
        apps = nil
        Options.shared.application.applications = originalApplications
        originalApplications = nil
        pageDefaults = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private static func makeStore(_ applications: [Application]) -> EnhanceArray<Application> {
        return EnhanceArray<Application>(
            withArray: applications,
            matchKey: "path",
            forObserver: { Options.shared.markChanged(.application) }
        )
    }

    /// The Settings window as the app makes it, remembering its pane in `defaults` (nil:
    /// nothing is remembered).
    private func makeWindow(defaults: UserDefaults? = nil) throws {
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesSplitViewController.self))
        windowController = try XCTUnwrap(
            storyboard.instantiateController(withIdentifier: WINDOW_IDENTIFIER.preferencesWindowController) as? PreferencesWindowController
        )
        window = try XCTUnwrap(windowController.window)
        preferences = PreferencesSplitViewController(storyboard: storyboard, uiStateDefaults: defaults)
        apps = try XCTUnwrap(preferences.controller(for: PANEL_IDENTIFIER.application) as? PreferencesApplicationViewController)
        apps.uiStateDefaults = pageDefaults.defaults
        windowController.contentViewController = preferences
        windowController.configure(window, remembersFrame: false)
        preferences.updateWindowTitle()
        window.contentView?.layoutSubtreeIfNeeded()
    }

    /// What a click on a sidebar row does: the table changes its selection and tells its
    /// delegate. (In a window on screen the Apps pane hears that it left; here it is told.)
    private func choose(_ pane: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let leavesApps = preferences.selectedPaneIdentifier == PANEL_IDENTIFIER.application && pane != PANEL_IDENTIFIER.application
        let row = try XCTUnwrap(preferences.sidebar.row(for: pane), file: file, line: line)
        preferences.sidebar.tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        if leavesApps {
            apps.viewDidDisappear()
        }
        XCTAssertEqual(preferences.selectedPaneIdentifier, pane, file: file, line: line)
    }

    /// View › Back or Forward.
    @discardableResult
    private func step(_ direction: PreferencesHistory.Direction) -> Bool {
        let wasApps = preferences.selectedPaneIdentifier == PANEL_IDENTIFIER.application
        let stepped = preferences.step(direction)
        if wasApps, preferences.selectedPaneIdentifier != PANEL_IDENTIFIER.application {
            apps.viewDidDisappear()
        }
        return stepped
    }

    /// The list of apps as it is stored.
    private func storedApplications() throws -> NSArray {
        let data = try XCTUnwrap(Options.shared.application.applications.json())
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? NSArray)
    }

    private var showsBackButton: Bool {
        return window.toolbar?.items.contains { $0.itemIdentifier == PreferencesWindowController.backItemIdentifier } ?? false
    }

    /// The window shows this pane, on its first page.
    private func assertShows(pane: String, title: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(preferences.selectedPaneIdentifier, pane, file: file, line: line)
        XCTAssertEqual(preferences.sidebar.selectedIdentifier, pane, file: file, line: line)
        XCTAssertTrue(preferences.host.currentController === preferences.controller(for: pane), file: file, line: line)
        XCTAssertNil(apps.detailController, file: file, line: line)
        XCTAssertEqual(window.title, title, file: file, line: line)
        XCTAssertFalse(showsBackButton, file: file, line: line)
        XCTAssertFalse(preferences.canGoBack, file: file, line: line)
    }

    /// The window shows the page of the app stored under `path`.
    private func assertShowsPage(of path: String, title: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(preferences.selectedPaneIdentifier, PANEL_IDENTIFIER.application, file: file, line: line)
        XCTAssertEqual(preferences.sidebar.selectedIdentifier, PANEL_IDENTIFIER.application, file: file, line: line)
        XCTAssertEqual(apps.detailController?.application.path, path, file: file, line: line)
        XCTAssertEqual(window.title, title, file: file, line: line)
        XCTAssertTrue(showsBackButton, file: file, line: line)
        XCTAssertTrue(preferences.canGoBack, file: file, line: line)
    }

    private func key(_ characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        return try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
        ))
    }

    // MARK: - Panes

    func testANewWindowHasNoHistory() throws {
        try makeWindow()
        XCTAssertEqual(preferences.history.places, [Self.scrolling], "where it opened")
        XCTAssertEqual(preferences.shownPlace, Self.scrolling)
        XCTAssertFalse(preferences.canStepBack)
        XCTAssertFalse(preferences.canStepForward)
        XCTAssertFalse(step(.back))
        XCTAssertFalse(step(.forward))
        assertShows(pane: "scrolling", title: "Scrolling")

        // The pane on show, asked for again, is no new place.
        XCTAssertTrue(preferences.selectPane(withIdentifier: "scrolling"))
        XCTAssertFalse(preferences.canStepBack)
    }

    func testBackAndForwardGoThroughThePanesShown() throws {
        let defaults = TestDefaults.make(for: self)
        let remembered = PreferencesSplitViewController.selectedPaneDefaultsKey
        try makeWindow(defaults: defaults)
        try choose("buttons")
        try choose("general")
        XCTAssertEqual(preferences.history.places, [Self.scrolling, Self.buttons, Self.general])
        XCTAssertTrue(preferences.canStepBack)
        XCTAssertFalse(preferences.canStepForward)

        XCTAssertTrue(step(.back))
        assertShows(pane: "buttons", title: "Buttons")
        XCTAssertEqual(defaults.string(forKey: remembered), "buttons", "remembered as any pane shown")
        XCTAssertTrue(preferences.canStepForward)
        XCTAssertTrue(step(.back))
        assertShows(pane: "scrolling", title: "Scrolling")
        XCTAssertEqual(defaults.string(forKey: remembered), "scrolling")
        XCTAssertFalse(preferences.canStepBack)
        XCTAssertFalse(step(.back))
        assertShows(pane: "scrolling", title: "Scrolling")

        XCTAssertTrue(step(.forward))
        assertShows(pane: "buttons", title: "Buttons")
        XCTAssertTrue(step(.forward))
        assertShows(pane: "general", title: "General")
        XCTAssertEqual(defaults.string(forKey: remembered), "general")
        XCTAssertFalse(step(.forward))
        XCTAssertEqual(preferences.history.places, [Self.scrolling, Self.buttons, Self.general], "steps add nothing")

        // A pane chosen after going back: what was ahead is gone.
        XCTAssertTrue(step(.back))
        try choose("mouse")
        XCTAssertFalse(preferences.canStepForward)
        XCTAssertEqual(preferences.history.places, [Self.scrolling, Self.buttons, PreferencesPlace(pane: "mouse")])
        XCTAssertTrue(step(.back))
        assertShows(pane: "buttons", title: "Buttons")
    }

    // MARK: - An app's page

    func testBackFromAnotherPaneOpensTheAppsPageAgain() throws {
        try makeWindow()
        try choose("application")
        apps.openApplication(withID: Self.calculator)
        assertShowsPage(of: Self.calculator, title: "Calculator")
        try choose("general")
        XCTAssertNil(apps.detailController, "leaving Apps closes the page")
        XCTAssertEqual(preferences.history.places, [Self.scrolling, Self.apps, Self.calculatorPage, Self.general])

        // Back: the page again, with the app's name and the title bar's back button.
        XCTAssertTrue(step(.back))
        assertShowsPage(of: Self.calculator, title: "Calculator")
        XCTAssertTrue(window.firstResponder === apps.detailController?.view, "Esc works straight away, as when the page is opened")
        // Then the list, then the pane before.
        XCTAssertTrue(step(.back))
        assertShows(pane: "application", title: "Apps")
        XCTAssertEqual(apps.list.selectedID, AnyHashable(Self.calculator), "the app stays selected, as after the title bar's button")
        XCTAssertTrue(step(.back))
        assertShows(pane: "scrolling", title: "Scrolling")
        XCTAssertFalse(preferences.canStepBack)

        // And forward again, the same places.
        XCTAssertTrue(step(.forward))
        assertShows(pane: "application", title: "Apps")
        XCTAssertTrue(step(.forward))
        assertShowsPage(of: Self.calculator, title: "Calculator")
        XCTAssertTrue(step(.forward))
        assertShows(pane: "general", title: "General")
        XCTAssertFalse(preferences.canStepForward)
        XCTAssertEqual(preferences.history.places, [Self.scrolling, Self.apps, Self.calculatorPage, Self.general])
    }

    func testTheTitleBarsButtonEscAndTheMenuLeaveAPageTheSameWay() throws {
        try makeWindow()
        try choose("application")
        apps.openApplication(withID: Self.calculator)
        let places = [Self.scrolling, Self.apps, Self.calculatorPage]
        XCTAssertEqual(preferences.history.places, places)

        let ways: [(name: String, leave: () throws -> Void)] = [
            ("the title bar's button", { self.windowController.goBack(nil) }),
            ("Esc", { try XCTUnwrap(self.apps.detailController).view.keyDown(with: try self.key("\u{1b}", keyCode: 53)) }),
            ("the page's ⌘[", {
                XCTAssertTrue(try XCTUnwrap(self.apps.detailController).view.performKeyEquivalent(with: try self.key("[", keyCode: 33, modifiers: .command)))
            }),
            ("View › Back", { XCTAssertTrue(self.preferences.step(.back)) }),
            ("View › Apps", { XCTAssertTrue(self.preferences.showPaneFromMenu(PANEL_IDENTIFIER.application)) }),
        ]
        for way in ways {
            assertShowsPage(of: Self.calculator, title: "Calculator")
            try way.leave()
            assertShows(pane: "application", title: "Apps")
            XCTAssertEqual(preferences.shownPlace, Self.apps, way.name)
            XCTAssertEqual(preferences.history.places, places, "\(way.name): the page stays ahead")
            XCTAssertTrue(preferences.canStepBack, way.name)
            XCTAssertTrue(preferences.canStepForward, way.name)
            // Forward opens the page again.
            XCTAssertTrue(step(.forward), way.name)
        }
        assertShowsPage(of: Self.calculator, title: "Calculator")
        XCTAssertFalse(preferences.canStepForward)
    }

    func testAJumpToAnAppsPagePassesTheListOnTheWayBack() throws {
        try makeWindow()
        try choose("buttons")
        // "Show in Calculator › Buttons", an Undo that shows where it acts.
        let calculator = try XCTUnwrap(apps.applications.first { $0.path == Self.calculator })
        XCTAssertNotNil(preferences.bringForward(pageOf: calculator, part: .buttons))
        assertShowsPage(of: Self.calculator, title: "Calculator")
        XCTAssertEqual(preferences.history.places, [Self.scrolling, Self.buttons, Self.apps, Self.calculatorPage])

        // Back on an app's page is the list, as the title bar's button; then where the jump came from.
        XCTAssertTrue(step(.back))
        assertShows(pane: "application", title: "Apps")
        XCTAssertTrue(step(.back))
        assertShows(pane: "buttons", title: "Buttons")

        // "Settings for Calculator…" of the menu bar, from General; and from one app's page to another's.
        try choose("general")
        PreferencesApplicationViewController.showSettings(for: Self.calculatorApp, in: preferences)
        let textEdit = try XCTUnwrap(apps.applications.first { $0.path == Self.textEdit })
        XCTAssertNotNil(preferences.bringForward(pageOf: textEdit, part: .ring))
        assertShowsPage(of: Self.textEdit, title: "TextEdit")
        XCTAssertEqual(
            preferences.history.places,
            [Self.scrolling, Self.buttons, Self.general, Self.apps, Self.calculatorPage, Self.apps, Self.textEditPage]
        )
        XCTAssertTrue(step(.back))
        assertShows(pane: "application", title: "Apps")
        XCTAssertTrue(step(.back))
        assertShowsPage(of: Self.calculator, title: "Calculator")
        XCTAssertTrue(step(.back))
        assertShows(pane: "application", title: "Apps")
        XCTAssertTrue(step(.back))
        assertShows(pane: "general", title: "General")
    }

    func testAPageOfARemovedAppIsSkipped() throws {
        try makeWindow()
        try choose("application")
        apps.openApplication(withID: Self.calculator)
        try choose("general")
        let places = [Self.scrolling, Self.apps, Self.calculatorPage, Self.general]
        XCTAssertEqual(preferences.history.places, places)

        // The app leaves the list (removed in the pane, or by an import).
        let stored = Options.shared.application.applications
        let position = try XCTUnwrap((0..<stored.count).first { stored.get(by: $0)?.path == Self.calculator })
        let calculator = try XCTUnwrap(stored.get(by: position))
        stored.remove(at: position)

        XCTAssertTrue(step(.back))
        assertShows(pane: "application", title: "Apps")
        XCTAssertTrue(step(.back))
        assertShows(pane: "scrolling", title: "Scrolling")
        XCTAssertTrue(step(.forward))
        assertShows(pane: "application", title: "Apps")
        XCTAssertTrue(step(.forward), "past the page that cannot be shown")
        assertShows(pane: "general", title: "General")
        XCTAssertEqual(preferences.history.places, places, "nothing was deleted")

        // It comes back (Undo, an import): its page is a place again.
        stored.insert(calculator, at: position)
        XCTAssertTrue(step(.back))
        assertShowsPage(of: Self.calculator, title: "Calculator")
    }

    func testThePartOfAPageIsNotHistory() throws {
        try makeWindow()
        try choose("application")
        apps.openApplication(withID: Self.calculator, part: .buttons)
        let places = [Self.scrolling, Self.apps, Self.calculatorPage]
        XCTAssertEqual(preferences.history.places, places)

        // Another part of the page is the same place.
        let page = try XCTUnwrap(apps.detailController)
        page.show(.ring)
        XCTAssertEqual(page.shownPart, .ring)
        XCTAssertEqual(preferences.history.places, places)
        XCTAssertFalse(preferences.canStepForward)
        XCTAssertEqual(ApplicationPagePart.remembered(in: pageDefaults.defaults), .ring)

        // A step opens the page on the part shown last, as any way to the page does, and
        // writes nothing about parts.
        try choose("general")
        ApplicationPagePart.gestures.remember(in: pageDefaults.defaults)
        let before = pageDefaults.defaults.persistentDomain(forName: pageDefaults.suiteName).map { $0 as NSDictionary }
        XCTAssertTrue(step(.back))
        assertShowsPage(of: Self.calculator, title: "Calculator")
        XCTAssertEqual(apps.detailController?.shownPart, .gestures)
        XCTAssertEqual(
            pageDefaults.defaults.persistentDomain(forName: pageDefaults.suiteName).map { $0 as NSDictionary },
            before
        )
    }

    // MARK: - The View menu's panes

    func testAppsFromTheMenuOnAnAppsPageShowsTheList() throws {
        try makeWindow()
        // A pane's item shows that pane.
        XCTAssertTrue(preferences.showPaneFromMenu("general"))
        assertShows(pane: "general", title: "General")
        XCTAssertTrue(preferences.showPaneFromMenu("application"))
        assertShows(pane: "application", title: "Apps")
        XCTAssertEqual(preferences.history.places, [Self.scrolling, Self.general, Self.apps])

        // On an app's page, "Apps" is the list.
        apps.openApplication(withID: Self.textEdit)
        assertShowsPage(of: Self.textEdit, title: "TextEdit")
        XCTAssertTrue(preferences.showPaneFromMenu("application"))
        assertShows(pane: "application", title: "Apps")
        XCTAssertTrue(window.firstResponder === apps.list, "as after the title bar's button")
        XCTAssertTrue(preferences.canStepForward, "Forward opens the page again")

        // The pane on show: nothing new, as for any way to it.
        XCTAssertTrue(preferences.showPaneFromMenu("application"))
        XCTAssertEqual(preferences.history.places, [Self.scrolling, Self.general, Self.apps, Self.textEditPage])
        XCTAssertEqual(preferences.shownPlace, Self.apps)

        XCTAssertFalse(preferences.showPaneFromMenu("no-such-pane"))
        assertShows(pane: "application", title: "Apps")
    }

    /// A window opened on a place someone asked for (a row of the Welcome Guide, the battery
    /// line, "Settings for Safari…", a pane's item) has no way back to the pane it remembered.
    func testAWindowOpenedOnAPlaceStartsThere() throws {
        let defaults = TestDefaults.make(for: self)
        defaults.set("mouse", forKey: PreferencesSplitViewController.selectedPaneDefaultsKey)
        try makeWindow(defaults: defaults)
        XCTAssertEqual(preferences.history.places, [PreferencesPlace(pane: "mouse")])

        // What MainMenuManager.showPreferencesWindow does with a window it made.
        XCTAssertTrue(preferences.selectPane(withIdentifier: "application"))
        XCTAssertTrue(preferences.canStepBack)
        preferences.startHistoryHere()
        XCTAssertEqual(preferences.history.places, [Self.apps])
        XCTAssertFalse(preferences.canStepBack)
        XCTAssertFalse(preferences.canStepForward)

        // "Settings for Calculator…" then opens the page: Back is the list, and no further.
        PreferencesApplicationViewController.showSettings(for: Self.calculatorApp, in: preferences)
        assertShowsPage(of: Self.calculator, title: "Calculator")
        XCTAssertEqual(preferences.history.places, [Self.apps, Self.calculatorPage])
        XCTAssertTrue(step(.back))
        assertShows(pane: "application", title: "Apps")
        XCTAssertFalse(preferences.canStepBack)

        // Started on a page, the list is still the way back.
        XCTAssertTrue(step(.forward))
        preferences.startHistoryHere()
        XCTAssertEqual(preferences.history.places, [Self.apps, Self.calculatorPage])
        XCTAssertEqual(preferences.shownPlace, Self.calculatorPage)
    }

    /// The history is in memory: going through the window writes the remembered pane, as
    /// before, and nothing else; a new window knows nothing of the last one's places.
    func testTheHistoryStoresNothing() throws {
        let store = TestDefaults.makeStore(for: self)
        let applicationsBefore = try storedApplications()
        try makeWindow(defaults: store.defaults)
        try choose("application")
        apps.openApplication(withID: Self.calculator)
        try choose("general")
        XCTAssertTrue(step(.back))
        XCTAssertTrue(step(.back))
        XCTAssertTrue(step(.back))
        XCTAssertTrue(step(.forward))
        XCTAssertTrue(step(.forward))
        assertShowsPage(of: Self.calculator, title: "Calculator")

        let written = try XCTUnwrap(store.defaults.persistentDomain(forName: store.suiteName))
        XCTAssertEqual(Array(written.keys), [PreferencesSplitViewController.selectedPaneDefaultsKey])
        XCTAssertEqual(written[PreferencesSplitViewController.selectedPaneDefaultsKey] as? String, "application")
        XCTAssertNil(pageDefaults.defaults.persistentDomain(forName: pageDefaults.suiteName), "nothing about an app's page")
        XCTAssertEqual(try storedApplications(), applicationsBefore, "the list of apps as it was")

        // The next window: where the last one was left, with no way back.
        windowController.close()
        try makeWindow(defaults: store.defaults)
        XCTAssertEqual(preferences.history.places, [Self.apps])
        XCTAssertNil(apps.detailController)
        XCTAssertFalse(preferences.canStepBack)
        XCTAssertFalse(preferences.canStepForward)
    }
}
