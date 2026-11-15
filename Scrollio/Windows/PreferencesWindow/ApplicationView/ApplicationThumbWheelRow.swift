//
//  ApplicationThumbWheelRow.swift
//  Scrollio
//
//  The thumb wheel in the Buttons part of an app's page (`ApplicationThumbWheel`): its row,
//  first in the list while the app has a function of its own, and what the part does with
//  it. "+" offers "Thumb wheel" in its mouse section, where the Buttons pane lists the
//  wheel (after the mode shift button), while the connected mouse has one (an MX Master 4,
//  3 or 3S) and the app has no function of its own; the new row starts with the function
//  the wheel has everywhere, is selected and its menu opens. Its pull-down is the Buttons
//  pane's ("Default (Scroll Sideways)") and changes only the app's function; the line under
//  it names the general one as Buttons names it ("In other apps: Zoom", "In other apps:
//  Default (Scroll Sideways)", kept together with no-break spaces as a button's "Default
//  (Back)" is).
//  "−" (or Delete), or "Same as Other Apps (…)" at the top of its menu, gives the wheel back
//  to Buttons, and the window's Undo takes it again,
//  with an undo target that outlives the page, as for a button's row; Undo takes back a
//  function chosen in the pull-down the same way. Buttons and
//  Scrolling › Thumb wheel are never touched. The menu's "Show in Safari › Scrolling" shows
//  the app's Scrolling part (`onThumbWheelSettingsRequested`, the page's
//  `showThumbWheelSettings`).
//

import Cocoa

// MARK: - The row

final class ApplicationThumbWheelRow: PreferencesListRow {

    static let identifier = NSUserInterfaceItemIdentifier("apps-buttons-thumb-wheel")

    let pullDown: ThumbWheelPullDown
    /// The mouse the picture is drawn on.
    private(set) var mouse: MouseArtworkModel
    private var shownPicture: (mouse: MouseArtworkModel, highlighted: Bool)?

    /// - Parameters:
    ///   - function: the app's own; `general`: the one of every other app.
    ///   - mouse: the connected mouse.
    init(function: ThumbWheelFunction, general: ThumbWheelFunction, mouse: MouseArtworkModel) {
        self.mouse = Self.pictured(mouse)
        let pullDown = ThumbWheelPullDown(function: function)
        pullDown.identifier = Self.identifier
        self.pullDown = pullDown
        super.init(
            id: ButtonsListLayout.thumbWheelRowID,
            title: ThumbWheelPresentation.title,
            explanation: Self.everywhere(general),
            icon: .image(ButtonsMouseMiniature.image(lighting: .thumbWheel, mouse: Self.pictured(mouse), highlighted: false)),
            accessory: pullDown,
            centeredOn: pullDown,
            controls: [pullDown]
        )
        pullDown.sameAsOtherAppsTitle = Self.sameAsOtherApps(general)
        applyEnabled()
    }

    required init?(coder: NSCoder) {
        fatalError("ApplicationThumbWheelRow is built in code")
    }

    /// "In other apps: Zoom", "In other apps: Default (Scroll Sideways)": what the wheel
    /// does in every other app, named as the Buttons pane's row names it (one name
    /// everywhere), "Default (Scroll Sideways)" kept on one line with no-break spaces, as a
    /// button's row keeps "Default (Back)" (`ApplicationButtonsViewController.OtherApps`).
    static func everywhere(_ general: ThumbWheelFunction) -> String {
        var name = ThumbWheelPresentation.buttonsTitle(for: general)
        if general == .scroll {
            name = name.replacingOccurrences(of: " ", with: "\u{A0}")
        }
        return String(format: NSLocalizedString("apps-buttons-everywhere", comment: ""), name)
    }

    /// "Same as Other Apps (Zoom)", "Same as Other Apps (Scroll Sideways)": the first item of
    /// the menu, which does what "−" does.
    static func sameAsOtherApps(_ general: ThumbWheelFunction) -> String {
        return String(format: NSLocalizedString("apps-buttons-same-as-other-apps", comment: ""), general.localizedName)
    }

    /// The picture shows where the wheel is: on the connected mouse, or on an MX Master 4
    /// when that has none (the app's function works with any sideways wheel).
    static func pictured(_ mouse: MouseArtworkModel) -> MouseArtworkModel {
        return mouse.has(.thumbWheel) ? mouse : .mxMaster4
    }

    /// What the wheel does now in the app.
    var function: ThumbWheelFunction {
        return pullDown.function
    }

    /// Shows `function` and the general one on `mouse`; the row and its pull-down stay the
    /// same views. Sends nothing and stores nothing.
    func update(function: ThumbWheelFunction, general: ThumbWheelFunction, mouse: MouseArtworkModel) {
        if pullDown.function != function {
            pullDown.show(function)
        }
        let line = Self.everywhere(general)
        if explanation != line {
            explanation = line
        }
        pullDown.sameAsOtherAppsTitle = Self.sameAsOtherApps(general)
        let pictured = Self.pictured(mouse)
        if self.mouse != pictured {
            self.mouse = pictured
            applyEnabled()
        }
    }

    /// The picture in white on the accent-coloured selection.
    override func applyEnabled() {
        super.applyEnabled()
        guard let iconView else { return }
        let wanted = (mouse: mouse, highlighted: isHighlighted)
        if let shownPicture, shownPicture == wanted { return }
        shownPicture = wanted
        iconView.image = ButtonsMouseMiniature.image(lighting: .thumbWheel, mouse: wanted.mouse, highlighted: wanted.highlighted)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        iconView?.needsDisplay = true
    }
}

// MARK: - The Buttons part

extension ApplicationButtonsViewController {

    /// What the "+" item of the thumb wheel carries (no `AddChoice`: the item has its own
    /// action).
    static let thumbWheelMenuMarker = "apps-buttons-add-thumb-wheel"

    /// The thumb wheel's row the list shows now, if any.
    var thumbWheelRow: ApplicationThumbWheelRow? {
        return list?.rows.first { $0.id == ButtonsListLayout.thumbWheelRowID } as? ApplicationThumbWheelRow
    }

    /// The row while the app has a function of its own: the one shown, brought up to date
    /// (its pull-down keeps the keyboard focus), or a new one; nil without.
    func makeThumbWheelRow() -> ApplicationThumbWheelRow? {
        guard let function = application.ownThumbWheelFunction else { return nil }
        let general = Options.shared.thumbWheel.function
        if let row = thumbWheelRow {
            row.update(function: function, general: general, mouse: mouse)
            return row
        }
        let row = ApplicationThumbWheelRow(function: function, general: general, mouse: mouse)
        row.pullDown.onFunctionSelected = { [weak self] chosen in
            self?.setOwnThumbWheelFunction(chosen)
        }
        // "Show in Safari › Scrolling": the app's part, not the pane.
        row.pullDown.settingsItem?.title = ThumbWheelPresentation.settingsItemTitle(application: application.getName())
        row.pullDown.onSettingsRequested = { [weak self] in
            self?.onThumbWheelSettingsRequested?()
        }
        // "Same as Other Apps (…)": what "−" does.
        row.pullDown.onSameAsOtherApps = { [weak self] in
            self?.removeOwnThumbWheel(undoName: ButtonRowChange.Kind.action.actionName)
        }
        return row
    }

    /// "+" offers the thumb wheel: the connected mouse has one, and the app no function of
    /// its own for it.
    var offersThumbWheel: Bool {
        return ButtonsListLayout.showsThumbWheel(on: mouse) && application.ownThumbWheelFunction == nil
    }

    /// Puts "Thumb wheel" into the "+" menu's section of the mouse, after the buttons the
    /// Buttons pane lists before it (up to the mode shift button), as that pane orders its
    /// rows (`ButtonsListLayout.rows`); with no button of the mouse offered, the section
    /// holds the wheel alone.
    func addThumbWheelItem(to menu: NSMenu) {
        guard offersThumbWheel else { return }
        let item = NSMenuItem(title: ThumbWheelPresentation.title, action: #selector(addThumbWheelChosen(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = Self.thumbWheelMenuMarker
        let header = NSLocalizedString("apps-buttons-add-mouse", comment: "")
        guard let headerIndex = menu.items.firstIndex(where: { $0.isSectionHeader && $0.title == header }) else {
            menu.insertItem(NSMenuItem.sectionHeader(title: header), at: 0)
            menu.insertItem(item, at: 1)
            menu.insertItem(.separator(), at: 2)
            return
        }
        let listed = ButtonsMousePart.listed(on: mouse)
        let before = listed.firstIndex(of: .modeShift).map { Array(listed[...$0]) } ?? listed
        let ahead = before.map { ButtonBindingIdentity(trigger(for: $0)) }
        var place = headerIndex + 1
        var index = headerIndex + 1
        while index < menu.items.count, !menu.items[index].isSeparatorItem {
            if case .trigger(let trigger)? = menu.items[index].representedObject as? AddChoice,
               ahead.contains(ButtonBindingIdentity(trigger)) {
                place = index + 1
            }
            index += 1
        }
        menu.insertItem(item, at: place)
    }

    @objc func addThumbWheelChosen(_ sender: NSMenuItem) {
        addOwnThumbWheel()
    }

    /// Gives the app the thumb wheel with the function it has everywhere (nothing changes
    /// until another is chosen), selects its row and opens its menu. A wheel the app has
    /// already is selected and flashes.
    func addOwnThumbWheel() {
        guard application.ownThumbWheelFunction == nil else {
            list.flash(ButtonsListLayout.thumbWheelRowID)
            return
        }
        application.setOwnThumbWheelFunction(Options.shared.thumbWheel.function)
        reloadRows()
        onOwnButtonsChange?()
        list.select(ButtonsListLayout.thumbWheelRowID)
        // The row's menu opens by itself, once the "+" menu is gone.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.view.window != nil, let row = self.thumbWheelRow,
                  self.list.selectedID == ButtonsListLayout.thumbWheelRowID else { return }
            self.openActionMenu(row.pullDown)
        }
    }

    /// The row's pull-down: the app's function, never the general one. Edit › Undo ("Undo
    /// Change Action", as for a button's row) puts the one before back.
    func setOwnThumbWheelFunction(_ function: ThumbWheelFunction) {
        guard let old = application.ownThumbWheelFunction else { return }
        application.setOwnThumbWheelFunction(function)
        reloadRows()
        onOwnButtonsChange?()
        guard old != function else { return }
        let showing = undoShowing
        Self.registerThumbWheelFunctionUndo(
            back: old, of: application, undoManager: undoTarget, showing: showing, listDidChange: onOwnButtonsChange
        )
    }

    /// As a removal's: the undo target is the settings, not the page; Undo finds the app's
    /// entry by its path when it runs, puts `function` back while the app still has a
    /// function of its own, shows it on the part `showing` gives for it, and registers the
    /// way back (Redo).
    private static func registerThumbWheelFunctionUndo(
        back function: ThumbWheelFunction, of application: Application, undoManager undo: UndoManager?,
        showing: @escaping (Application) -> ApplicationButtonsViewController?, listDidChange: (() -> Void)?
    ) {
        guard let undo else { return }
        let path = application.path
        undo.registerUndo(withTarget: Options.shared) { [weak undo] _ in
            guard let entry = thumbWheelEntry(storedAs: path), let now = entry.ownThumbWheelFunction, now != function else { return }
            entry.setOwnThumbWheelFunction(function)
            showing(entry)?.showThumbWheelChange(selecting: true)
            listDidChange?()
            registerThumbWheelFunctionUndo(back: now, of: entry, undoManager: undo, showing: showing, listDidChange: listDidChange)
        }
        undo.setActionName(ButtonRowChange.Kind.action.actionName)
    }

    /// Return on the selected row opens its menu.
    func openThumbWheelMenu() {
        guard let row = thumbWheelRow else { return }
        openActionMenu(row.pullDown)
    }

    // MARK: Removing, with Undo

    /// Gives the thumb wheel back to Buttons; the window's Undo takes it again. `undoName`:
    /// what Edit › Undo calls it ("Remove Thumb Wheel" when nil; "Change Action" for "Same as
    /// Other Apps").
    func removeOwnThumbWheel(undoName: String? = nil) {
        let showing = undoShowing
        Self.removeOwnThumbWheel(
            of: application, undoManager: undoTarget, showing: showing, listDidChange: onOwnButtonsChange,
            undoName: undoName ?? NSLocalizedString("apps-buttons-undo-remove-thumb-wheel", comment: "")
        )
    }

    /// As a button's removal (`removeOwnBinding`): the undo target is the settings, not the
    /// page, and Undo and Redo find the app's entry by its path when they run and show the
    /// change on the part `showing` gives for it. Neither holds the page.
    private static func removeOwnThumbWheel(
        of application: Application, undoManager undo: UndoManager?,
        showing: @escaping (Application) -> ApplicationButtonsViewController?, listDidChange: (() -> Void)?,
        undoName: String
    ) {
        guard let removed = application.ownThumbWheelFunction else { return }
        application.setOwnThumbWheelFunction(nil)
        showing(application)?.showThumbWheelChange(selecting: false)
        listDidChange?()
        guard let undo else { return }
        let path = application.path
        undo.registerUndo(withTarget: Options.shared) { [weak undo] _ in
            guard let entry = thumbWheelEntry(storedAs: path) else { return }
            restoreOwnThumbWheel(removed, of: entry, undoManager: undo, showing: showing, listDidChange: listDidChange, undoName: undoName)
        }
        undo.setActionName(undoName)
    }

    private static func restoreOwnThumbWheel(
        _ function: ThumbWheelFunction, of application: Application, undoManager undo: UndoManager?,
        showing: @escaping (Application) -> ApplicationButtonsViewController?, listDidChange: (() -> Void)?,
        undoName: String
    ) {
        guard application.ownThumbWheelFunction == nil else {
            // Added again meanwhile: that one stays.
            showing(application)?.showThumbWheelChange(selecting: true)
            return
        }
        application.setOwnThumbWheelFunction(function)
        showing(application)?.showThumbWheelChange(selecting: true)
        listDidChange?()
        guard let undo else { return }
        let path = application.path
        undo.registerUndo(withTarget: Options.shared) { [weak undo] _ in
            guard let entry = thumbWheelEntry(storedAs: path) else { return }
            removeOwnThumbWheel(of: entry, undoManager: undo, showing: showing, listDidChange: listDidChange, undoName: undoName)
        }
        undo.setActionName(undoName)
    }

    /// The entry the list holds now for the app stored as `path` (an app removed and added
    /// again is a new entry), as a button's Undo finds it.
    private static func thumbWheelEntry(storedAs path: String) -> Application? {
        return PreferencesApplicationViewController.existingApplication(
            forPaths: PreferencesApplicationViewController.knownPaths(forStoredPath: path)
        )
    }

    /// A removal, its Undo or its Redo changed the app's thumb wheel: the rows again, with
    /// the wheel's row selected when it came back; and the part of the page shown now, if
    /// another one (the Scrolling part's Thumb wheel › Action is the same value), as a
    /// button's removal does (`showUndoableChange`).
    private func showThumbWheelChange(selecting: Bool) {
        guard isViewLoaded else { return }
        reloadRows()
        if selecting {
            list.select(ButtonsListLayout.thumbWheelRowID)
        }
        if let shown = (parent as? ApplicationDetailViewController)?.shownController, shown !== self {
            shown.syncViewWithOptions()
        }
    }
}
