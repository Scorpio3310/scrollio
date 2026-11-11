//
//  PreferencesApplicationViewController.swift
//  Mos
//  "Apps" preferences pane: apps with scrolling settings of their own. Built in code on
//  PreferencesGroupedForm and its PreferencesListBox, in the boxes of System Settings;
//  the storyboard scene is a shell.
//
//  On top "Limit scrolling to these apps" (the allowlist: it only gates smoothing and
//  reversing, so it says so; buttons and gestures work everywhere). Under it the list of
//  apps, each with its icon, its name and whether it has settings of its own. "+" offers
//  the running apps and "Choose in Finder…", "−" and Delete remove (Edit › Undo brings the
//  app back with its settings). Double-click, Return or the chevron open the app's page
//  (ApplicationDetailViewController) in place of the list; "‹ Apps", Esc and ⌘[ come back,
//  and leaving the pane always comes back to the list.
//
//  The pane edits Options.shared.application: the allowlist switch and the list of apps.
//  What is stored and how is unchanged: running apps are stored by their program's path,
//  apps chosen in Finder by their bundle's, as before.
//
//  Created by Caldis on 2017/1/29.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa
import UniformTypeIdentifiers

/// A running app that "+" offers.
struct ApplicationCandidate {
    /// What is stored for it when it is added: the program's path, as running apps always were.
    let path: String
    /// Every path under which the list may hold it already (the bundle's and the program's).
    let knownPaths: [String]
    let name: String
    let icon: NSImage?

    /// The running apps with a Dock icon, Scrollio itself left out, by name.
    static func running() -> [ApplicationCandidate] {
        let ownProcess = ProcessInfo.processInfo.processIdentifier
        var seen = Set<String>()
        var candidates: [ApplicationCandidate] = []
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular, app.processIdentifier != ownProcess,
                  let program = app.executableURL?.path, seen.insert(program).inserted else { continue }
            let bundle = app.bundleURL?.path
            candidates.append(ApplicationCandidate(
                path: program,
                knownPaths: [bundle, program].compactMap { $0 },
                name: app.localizedName ?? Utils.getApplicationName(fromPath: program),
                icon: app.icon ?? Utils.getApplicationIcon(fromPath: bundle ?? program)
            ))
        }
        return candidates.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

class PreferencesApplicationViewController: NSViewController {

    /// The column of the Preferences window.
    static let paneWidth: CGFloat = PreferencesWindowLayout.contentWidth
    static var boxWidth: CGFloat {
        return PreferencesGroupedForm.boxWidth(paneWidth: paneWidth)
    }
    /// The app icons in the "+" menu.
    static let menuIconSize: CGFloat = 16

    /// Identifiers for the controls (tests and accessibility tooling).
    enum Identifier {
        static let allowlist = NSUserInterfaceItemIdentifier("apps-limit")
        static let list = NSUserInterfaceItemIdentifier("apps-list")
        static let chooseInFinder = NSUserInterfaceItemIdentifier("apps-choose-in-finder")
    }

    // MARK: - Seams

    /// The running apps "+" offers; tests give fixed ones.
    var runningApplications: () -> [ApplicationCandidate] = { ApplicationCandidate.running() }

    /// Shows the "+" menu under the + button; tests take the menu instead.
    var presentMenu: (NSMenu, NSButton) -> Void = { menu, button in
        let below = button.isFlipped ? button.bounds.maxY + 4 : button.bounds.minY - 4
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: below), in: button)
    }

    /// Asks for apps in Finder and hands over the chosen ones (none when cancelled); tests
    /// answer themselves.
    var chooseApplications: (NSWindow?, @escaping ([URL]) -> Void) -> Void = { window, completion in
        let panel = PreferencesApplicationViewController.makeOpenPanel()
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            completion(response == .OK ? panel.urls : [])
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            panel.begin(completionHandler: finish)
        }
    }

    /// Where "Advanced" of an app's Scrolling settings is remembered (shared with the
    /// Scrolling pane); tests and screenshots give a store of their own.
    var uiStateDefaults: UserDefaults = .standard

    // MARK: - Views (read access for tests)

    private(set) var allowlistRow: PreferencesSwitchRow!
    private(set) var listSection: PreferencesListSection!
    /// The list and the switch above it.
    private(set) var listPage: NSView!
    /// The page of the app that is open; nil while the list shows.
    private(set) var detailController: ApplicationDetailViewController?
    /// The app of each row, by the row's id: the app's stored path. An app stored twice
    /// under one path (earlier builds let Finder add it again) gets "#2" after the path.
    private(set) var rowApplications: [String: Application] = [:]
    /// What the pane shows: `listPage` or the open app's page.
    private(set) var currentPage: NSView?

    var list: PreferencesListBox { return listSection.list }
    var allowlistSwitch: NSSwitch { return allowlistRow.toggle }

    // MARK: - Lifecycle

    override func loadView() {
        let root = PreferencesForm.makeBackground()

        let page = NSView()
        let content = PreferencesGroupedForm.installContentStack(in: page, paneWidth: Self.paneWidth)
        // As tall as its rows: the column shrinks again when an app is removed.
        content.setHuggingPriority(.defaultHigh, for: .vertical)

        let allowlist = PreferencesSwitchRow(
            title: text("apps-limit"),
            explanation: text("apps-limit-hint"),
            target: self,
            action: #selector(allowlistClick(_:))
        )
        allowlist.toggle.identifier = Identifier.allowlist
        allowlistRow = allowlist
        let allowlistSection = PreferencesGroupSection(width: Self.boxWidth, rows: [allowlist])

        let list = PreferencesListBox(
            width: Self.boxWidth,
            emptyTitle: text("apps-empty-title"),
            emptyExplanation: text("apps-empty-hint")
        )
        list.identifier = Identifier.list
        list.onAdd = { [weak self] button in self?.showAddMenu(from: button) }
        list.onRemove = { [weak self] id in
            guard let id = id as? String else { return }
            self?.removeApplication(withID: id)
        }
        list.onOpen = { [weak self] id in
            guard let id = id as? String else { return }
            self?.openApplication(withID: id)
        }
        listSection = PreferencesListSection(title: text("apps-list-header"), list: list)

        PreferencesGroupedForm.add([allowlistSection, listSection], to: content)
        listPage = page

        view = root
        show(page: page)
        reloadRows()
        syncViewWithOptions()
        root.setFrameSize(root.fittingSize)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        // The options may have changed while the pane was not showing.
        syncViewWithOptions()
        reloadRows()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        // Coming back to the pane always shows the list.
        showList(focusList: false)
    }

    // MARK: - Data

    /// The apps, in their stored order.
    var applications: [Application] {
        let stored = Options.shared.application.applications
        return (0..<stored.count).compactMap { stored.get(by: $0) }
    }

    private func index(of application: Application) -> Int? {
        return applications.firstIndex { $0 === application }
    }

    /// The app of the row `id`.
    func application(forRowID id: String) -> Application? {
        return rowApplications[id]
    }

    /// The id of the row that shows `application`.
    func rowID(for application: Application) -> String? {
        return rowApplications.first { $0.value === application }?.key
    }

    /// The app the list holds under one of `paths`, if any.
    func existingApplication(forPaths paths: [String]) -> Application? {
        let stored = Options.shared.application.applications
        for path in paths {
            if let application = stored.get(by: path) {
                return application
            }
        }
        return nil
    }

    // MARK: - Refresh

    func syncViewWithOptions() {
        guard isViewLoaded else { return }
        allowlistRow.isOn = Options.shared.application.allowlist
        detailController?.syncViewWithOptions()
    }

    /// Shows the stored apps in the list (the selection stays on the same app).
    func reloadRows() {
        guard isViewLoaded else { return }
        var occurrences: [String: Int] = [:]
        var targets: [String: Application] = [:]
        var rows: [PreferencesListRow] = []
        for application in applications {
            let count = occurrences[application.path, default: 0] + 1
            occurrences[application.path] = count
            let id = count == 1 ? application.path : "\(application.path)#\(count)"
            targets[id] = application
            rows.append(makeRow(application, id: id))
        }
        rowApplications = targets
        list.setRows(rows)
        // The open app is no longer on the list (a removal was redone): back to the list.
        if let detail = detailController, index(of: detail.application) == nil {
            showList(focusList: true)
        }
    }

    /// What a row of the list says about an app.
    static func explanation(for application: Application) -> String {
        return NSLocalizedString(application.inherit ? "apps-row-inherit" : "apps-row-own", comment: "")
    }

    private func makeRow(_ application: Application, id: String) -> PreferencesListRow {
        let path = application.path
        let row = ApplicationListRow(
            id: id,
            title: application.getName(),
            explanation: Self.explanation(for: application),
            icon: .image(application.getIcon()),
            showsChevron: true
        )
        row.toolTip = path
        row.onChevronClick = { [weak self] in self?.openApplication(withID: id) }
        return row
    }

    // MARK: - Allowlist

    @objc func allowlistClick(_ sender: NSSwitch) {
        let limit = sender.state == .on
        if Options.shared.application.allowlist != limit {
            Options.shared.application.allowlist = limit
        }
        syncViewWithOptions()
    }

    // MARK: - Adding

    func showAddMenu(from button: NSButton) {
        presentMenu(makeAddMenu(), button)
    }

    /// The running apps with their icons (those on the list already off, with a checkmark),
    /// then "Choose in Finder…".
    func makeAddMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for candidate in runningApplications() {
            let item = NSMenuItem(title: candidate.name, action: #selector(addRunningApplication(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = candidate
            if let icon = candidate.icon?.copy() as? NSImage {
                icon.size = NSSize(width: Self.menuIconSize, height: Self.menuIconSize)
                item.image = icon
            }
            if existingApplication(forPaths: candidate.knownPaths + [candidate.path]) != nil {
                item.isEnabled = false
                item.state = .on
            }
            menu.addItem(item)
        }
        if !menu.items.isEmpty {
            menu.addItem(.separator())
        }
        let finder = NSMenuItem(title: text("apps-choose-in-finder"), action: #selector(chooseInFinderClick(_:)), keyEquivalent: "")
        finder.target = self
        finder.identifier = Identifier.chooseInFinder
        menu.addItem(finder)
        return menu
    }

    @objc func addRunningApplication(_ sender: NSMenuItem) {
        guard let candidate = sender.representedObject as? ApplicationCandidate else { return }
        addApplication(path: candidate.path, knownPaths: candidate.knownPaths)
    }

    @objc func chooseInFinderClick(_ sender: Any?) {
        chooseApplications(view.window) { [weak self] urls in
            self?.addApplications(at: urls)
        }
    }

    /// Choosing apps in Finder: only apps, from /Applications, several at once.
    static func makeOpenPanel() -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.directoryURL = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.application]
        panel.prompt = NSLocalizedString("apps-open-panel-prompt", comment: "")
        return panel
    }

    /// Adds the apps chosen in Finder (by their bundle's path) and selects the last new one;
    /// when every one was on the list already, the first of them blinks.
    func addApplications(at urls: [URL]) {
        var added: Application?
        var existing: Application?
        for url in urls {
            let bundle = url.path
            let program = Bundle(url: url)?.executablePath
            let (application, isNew) = insertApplication(path: bundle, knownPaths: [bundle, program].compactMap { $0 })
            if isNew {
                added = application
            } else if existing == nil {
                existing = application
            }
        }
        reloadRows()
        if let id = added.flatMap(rowID(for:)) {
            list.select(id)
        } else if let id = existing.flatMap(rowID(for:)) {
            list.flash(id)
        }
        focusList()
    }

    /// Adds the app stored as `path` and selects it; an app the list holds already (under
    /// any of `knownPaths`) is selected and blinks instead.
    @discardableResult
    func addApplication(path: String, knownPaths: [String]) -> Application {
        let (application, isNew) = insertApplication(path: path, knownPaths: knownPaths)
        reloadRows()
        if let id = rowID(for: application) {
            if isNew {
                list.select(id)
            } else {
                list.flash(id)
            }
        }
        focusList()
        return application
    }

    private func insertApplication(path: String, knownPaths: [String]) -> (Application, isNew: Bool) {
        if let existing = existingApplication(forPaths: knownPaths + [path]) {
            return (existing, false)
        }
        let application = Application(path: path)
        Options.shared.application.applications.append(application)
        return (application, true)
    }

    // MARK: - Removing

    /// Removes the app of the row `id` with its settings; Undo puts it back where it was.
    func removeApplication(withID id: String) {
        guard let application = application(forRowID: id) else { return }
        remove(application)
    }

    private func remove(_ application: Application) {
        guard let position = index(of: application) else { return }
        Options.shared.application.applications.remove(at: position)
        reloadRows()
        undoManager?.registerUndo(withTarget: self) { controller in
            controller.restoreApplication(application, at: position)
        }
        undoManager?.setActionName(text("apps-undo-remove"))
    }

    /// Undo of a removal: the same app, with all its settings, in its old place. Redo
    /// removes it again.
    func restoreApplication(_ application: Application, at position: Int) {
        if index(of: application) == nil {
            Options.shared.application.applications.insert(application, at: position)
        }
        reloadRows()
        list.select(rowID(for: application))
        undoManager?.registerUndo(withTarget: self) { controller in
            controller.remove(application)
        }
        undoManager?.setActionName(text("apps-undo-remove"))
    }

    // MARK: - App page

    /// Opens the page of the app of the row `id` in place of the list.
    func openApplication(withID id: String) {
        guard isViewLoaded, let application = application(forRowID: id) else { return }
        list.select(id)
        if let detail = detailController {
            guard detail.application !== application else { return }
            closeDetail(detail)
        }
        let detail = ApplicationDetailViewController(application: application, uiStateDefaults: uiStateDefaults)
        detail.onBack = { [weak self] in self?.showList(focusList: true) }
        detail.onInheritChange = { [weak self] in self?.reloadRows() }
        detail.onHeightChange = { [weak self] in self?.contentHeightDidChange() }
        addChild(detail)
        detailController = detail
        show(page: detail.view)
        contentHeightDidChange()
        scrollToTop()
        view.window?.makeFirstResponder(detail.view)
    }

    /// Back from an app's page to the list, with that app selected.
    func showList(focusList shouldFocus: Bool) {
        guard isViewLoaded, let detail = detailController else { return }
        let application = detail.application
        closeDetail(detail)
        show(page: listPage)
        reloadRows()
        list.select(rowID(for: application))
        contentHeightDidChange()
        if shouldFocus {
            focusList()
        }
    }

    private func closeDetail(_ detail: ApplicationDetailViewController) {
        detail.view.removeFromSuperview()
        detail.removeFromParent()
        detailController = nil
    }

    /// Puts `page` (the list, or an app's page) in the pane instead of the other.
    private func show(page: NSView) {
        guard page !== currentPage else { return }
        currentPage?.removeFromSuperview()
        currentPage = page
        page.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(page)
        NSLayoutConstraint.activate([
            page.topAnchor.constraint(equalTo: view.topAnchor),
            page.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            page.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func contentHeightDidChange() {
        PreferencesForm.fitToContent(self)
    }

    private func scrollToTop() {
        guard let scrollView = view.enclosingScrollView else { return }
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func focusList() {
        guard let window = view.window, list.window === window else { return }
        window.makeFirstResponder(list)
    }

    private func text(_ key: String) -> String {
        return NSLocalizedString(key, comment: "")
    }
}

// MARK: - List row

/// A row of the apps list: a click on its chevron opens the app's page, as a double click
/// on the row does.
final class ApplicationListRow: PreferencesListRow {

    var onChevronClick: (() -> Void)?

    /// Around the chevron, where a click counts as a click on it.
    static let chevronHitOutset: CGFloat = 8

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        guard event.clickCount == 1 else { return }
        if isChevronHit(at: convert(event.locationInWindow, from: nil)) {
            onChevronClick?()
        }
    }

    /// `point` in the row's coordinates is on (or close around) the chevron.
    func isChevronHit(at point: NSPoint) -> Bool {
        guard let chevronView else { return false }
        let outset = Self.chevronHitOutset
        return chevronView.frame.insetBy(dx: -outset, dy: -outset).contains(point)
    }
}
