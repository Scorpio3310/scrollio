//
//  ApplicationButtonsViewController.swift
//  Scrollio
//
//  The Buttons part of an app's page: only the buttons and keys that do something else
//  while the app is in front (`ApplicationButtons`); every other button does what the
//  Buttons pane says. Each row is a row of the Buttons pane (where the button is, its name,
//  the action pull-down with "Default" for "does what it does by itself here"), with a
//  second line that says what it does everywhere else. "+" offers the buttons of the
//  connected mouse, "Record a Button or Key…" (the Buttons pane's recorder) and the
//  buttons the Buttons pane has an action for; a new row starts with the action it has
//  everywhere, and its menu opens. "−" (or Delete) gives the button back to Buttons, and
//  the window's Undo takes it again. What opens the Shortcut Ring and Gesture Navigation
//  stay general: their buttons are not offered, and the two actions are not in the menus.
//
//  A Logitech button that no binding of Buttons uses is the mouse's own in every other
//  app: Scrollio asks the mouse for it only while this app is in front
//  (`LogiUsageBootstrap.refreshButtonUsage`).
//
//  Only the app's own list is edited (`Application.setOwnButtonBindings`); Buttons is
//  never touched.
//

import Cocoa

final class ApplicationButtonsViewController: NSViewController, ApplicationPagePartController {

    enum Identifier {
        static let list = NSUserInterfaceItemIdentifier("apps-buttons-list")
        static let note = NSUserInterfaceItemIdentifier("apps-buttons-note")
    }

    /// What a "+" item adds.
    enum AddChoice {
        /// A button of the connected mouse, or a binding of Buttons: this trigger.
        case trigger(RecordedEvent)
        /// "Record a Button or Key…".
        case record
    }

    let application: Application
    var onHeightChange: (() -> Void)?
    /// The app's own buttons changed (the list of apps shows a mark for them). An Undo of a
    /// removal keeps it and may run after the page is gone: it must not hold the page.
    var onOwnButtonsChange: (() -> Void)?
    /// The Buttons part that shows an app's entry now, if any (the pane's answer). An Undo
    /// or Redo of a removal asks it when it runs, maybe after this page closed and the
    /// app's page opened again: it must not hold the page. nil: this part, while it is there.
    var partShowing: ((Application) -> ApplicationButtonsViewController?)?

    // MARK: - Seams (tests and screenshots replace them)

    /// The connected mouse and what it says about its buttons.
    var deviceSource: ButtonsDeviceSource = .live
    /// Shows the "+" menu at the button; tests catch the menu instead.
    var presentMenu: (NSMenu, NSView) -> Void = { menu, anchor in
        let below = anchor.isFlipped ? anchor.bounds.maxY + 4 : anchor.bounds.minY - 4
        menu.popUp(positioning: nil, at: NSPoint(x: anchor.bounds.minX, y: below), in: anchor)
    }
    /// Starts recording at "+". nil: the real recorder, which taps the system's events;
    /// tests never use it.
    var startRecording: ((NSView) -> Void)?
    /// Ends a recording that is still open. nil: the real recorder.
    var stopRecording: (() -> Void)?
    /// Opens a row's action menu. The menu runs until it closes, so tests replace it.
    var openActionMenu: (NSPopUpButton) -> Void = { $0.performClick(nil) }
    /// Shows "Open App or File" at a row's pull-down. Tests replace it: nothing is shown.
    var presentOpenTarget: (OpenTargetConfigPopover, NSView, OpenTargetPayload?) -> Void = { popover, anchor, existing in
        popover.show(at: anchor, existing: existing)
    }
    /// Takes Undo and Redo of a removal; the window's when nil.
    var paneUndoManager: UndoManager?

    // MARK: - Views and state (read access for tests)

    private(set) var list: PreferencesListBox!
    private(set) var noteLabel: NSTextField!
    /// The rows, in the order of the app's list.
    private(set) var rows: [ButtonBindingRow] = []
    /// The drawing of the connected mouse, in every row's picture.
    private(set) var mouse: MouseArtworkModel = .generic
    private(set) var isRecorderOpen = false
    /// "Open App or File", while it is open.
    private(set) var openTargetPopover: OpenTargetConfigPopover?
    private var pendingRecorded: RecordedEvent?
    private let recorder = KeyRecorder()
    private let resolver = ActionDisplayResolver()

    init(application: Application) {
        self.application = application
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("ApplicationButtonsViewController is built in code")
    }

    deinit {
        openTargetPopover?.hide()
    }

    // MARK: - Lifecycle

    static var boxWidth: CGFloat {
        return PreferencesGroupedForm.boxWidth(paneWidth: ApplicationDetailViewController.paneWidth)
    }

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        let content = PreferencesGroupedForm.installContentStack(in: root, paneWidth: ApplicationDetailViewController.paneWidth)

        let list = PreferencesListBox(width: Self.boxWidth, emptyTitle: text("apps-buttons-empty"))
        list.identifier = Identifier.list
        list.rowsView.setAccessibilityLabel(text("apps-buttons-list-label"))
        list.onAdd = { [weak self] button in self?.showAddMenu(from: button) }
        list.onRemove = { [weak self] id in
            guard let id = id as? UUID else { return }
            self?.removeOwnBinding(id: id)
        }
        list.onOpen = { [weak self] id in
            guard let self, let row = self.row(for: id) else { return }
            self.openActionMenu(row.pullDown)
        }
        self.list = list

        let note = NSTextField(wrappingLabelWithString: Self.note(for: application.getName(), isEmpty: application.ownButtonBindings.isEmpty))
        note.identifier = Identifier.note
        note.font = PreferencesGroupedForm.explanationFont
        note.textColor = PreferencesGroupedForm.explanationColor(enabled: true)
        note.isSelectable = false
        note.preferredMaxLayoutWidth = Self.boxWidth - 2 * PreferencesGroupedForm.rowHorizontalInset
        note.translatesAutoresizingMaskIntoConstraints = false
        noteLabel = note
        let holder = NSView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(note)
        let inset = PreferencesGroupedForm.rowHorizontalInset
        NSLayoutConstraint.activate([
            note.topAnchor.constraint(equalTo: holder.topAnchor),
            note.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
            note.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: inset),
            note.trailingAnchor.constraint(equalTo: holder.trailingAnchor, constant: -inset),
        ])

        PreferencesGroupedForm.add([list, holder], to: content)
        content.setCustomSpacing(PreferencesGroupedForm.noteSpacing, after: list)
        view = root
        recorder.delegate = self
        reloadRows()
    }

    /// The line under the list: with rows, that every other button does what Buttons
    /// says; without (the list says that already), how to add one.
    static func note(for name: String, isEmpty: Bool = false) -> String {
        let key = isEmpty ? "apps-buttons-note-empty" : "apps-buttons-note"
        return String(format: NSLocalizedString(key, comment: ""), name)
    }

    func syncViewWithOptions() {
        reloadRows()
    }

    /// The page goes away or another part shows: the recorder, a row's recorder and "Open
    /// App or File" close.
    func partWillHide() {
        if let popover = openTargetPopover {
            openTargetPopover = nil
            popover.hide()
        }
        if isRecorderOpen {
            if let stopRecording {
                stopRecording()
            } else {
                recorder.stopRecording()
            }
        }
        for row in rows {
            row.pullDown.cancelShortcutRecording()
        }
    }

    // MARK: - Data

    /// The app's own bindings as stored.
    var ownBindings: [ButtonBinding] {
        return application.ownButtonBindings
    }

    /// The bindings of the Buttons pane.
    var generalBindings: [ButtonBinding] {
        return Options.shared.buttons.binding
    }

    func row(for id: AnyHashable) -> ButtonBindingRow? {
        return rows.first { $0.id == id }
    }

    /// One row per binding of the app's own; the rows still there keep their views (a
    /// pull-down keeps the keyboard focus).
    func reloadRows() {
        guard isViewLoaded, let list else { return }
        mouse = MouseArtworkModel.model(forDeviceName: deviceSource.deviceName())
        let own = ownBindings
        let general = generalBindings
        let titles = ButtonTriggerNaming.titles(for: own.map(\.triggerEvent))
        let old = rows
        var shown: [ButtonBindingRow] = []
        for (index, binding) in own.enumerated() {
            let title = titles[index]
            let note = everywhereNote(for: binding, general: general)
            let row: ButtonBindingRow
            if let existing = old.first(where: { $0.id == AnyHashable(binding.id) }) {
                existing.update(binding: binding, title: title, note: note, mouse: mouse, isStored: false)
                row = existing
            } else {
                row = makeRow(for: binding, title: title, note: note)
            }
            Self.leaveOutGeneralOnlyActions(in: row.pullDown)
            // A binding on a button that stays general (Buttons gave it the ring or Gesture
            // Navigation since) is kept, and not used: dimmed.
            row.isEnabled = ApplicationButtons.isUsable(binding, general: general)
            shown.append(row)
        }
        rows = shown
        noteLabel.stringValue = Self.note(for: application.getName(), isEmpty: own.isEmpty)
        if shown.count != list.rows.count || zip(shown, list.rows).contains(where: { $0 !== $1 }) {
            list.setRows(shown)
            onHeightChange?()
        }
    }

    /// "Everywhere: Mission Control": what the button does in every other app.
    func everywhereNote(for binding: ButtonBinding, general: [ButtonBinding]) -> ButtonRowNote {
        let generalBinding = ApplicationButtons.generalBinding(for: binding.triggerEvent, in: general)
        let action = generalBinding.flatMap { $0.isEnabled ? resolver.actionName(of: $0) : nil } ?? text("buttons-default")
        return ButtonRowNote(kind: .everywhere, text: String(format: text("apps-buttons-everywhere"), action))
    }

    private func makeRow(for binding: ButtonBinding, title: String, note: ButtonRowNote) -> ButtonBindingRow {
        let id = binding.id
        let pullDown = ButtonActionPullDown(binding: binding)
        pullDown.onShortcutSelected = { [weak self] shortcut in
            self?.setAction(of: id, named: shortcut?.identifier ?? "")
        }
        pullDown.onCustomShortcutRecorded = { [weak self] name, label in
            self?.setAction(of: id, named: name, label: label)
        }
        pullDown.onOpenTargetSelectionRequested = { [weak self] in
            self?.presentOpenTargetPopover(forRow: id)
        }
        // (No place menu here: where a numbered button is, the Buttons pane says.)
        let row = ButtonBindingRow(binding: binding, title: title, note: note, mouse: mouse, pullDown: pullDown, isStored: false)
        // Without an action the button does what it does by itself here: "Default".
        pullDown.offersDefault = true
        return row
    }

    /// The menu of an app's row has neither the Shortcut Ring nor Gesture Navigation (they
    /// stay general) nor "Show Gesture Settings". Done again after the pull-down rebuilt
    /// or re-showed its items.
    static func leaveOutGeneralOnlyActions(in pullDown: ButtonActionPullDown) {
        for item in pullDown.menu?.items ?? [] {
            if let shortcut = item.representedObject as? SystemShortcut.Shortcut,
               ApplicationButtons.isGeneralOnly(action: shortcut.identifier) {
                item.isHidden = true
            }
            if item.representedObject as? String == ShortcutManager.MenuMarker.gestureSettings {
                item.isHidden = true
            }
        }
    }

    // MARK: - Changing

    /// Stores the app's own list, shows it, and tells the page.
    private func store(_ bindings: [ButtonBinding]) {
        application.setOwnButtonBindings(bindings)
        reloadRows()
        onOwnButtonsChange?()
    }

    /// The action of the app's binding `id`: a listed one, a recorded key combination
    /// (with its name and icon), or "" ("Default": the button does what it does by itself
    /// here). The ring and Gesture Navigation are refused.
    func setAction(of id: UUID, named name: String, label: ShortcutLabel? = nil) {
        guard !ApplicationButtons.isGeneralOnly(action: name) else {
            reloadRows()
            return
        }
        var own = ownBindings
        guard let index = own.firstIndex(where: { $0.id == id }) else { return }
        let old = own[index]
        own[index] = ButtonBinding(
            id: old.id, triggerEvent: old.triggerEvent, systemShortcutName: name, isEnabled: true,
            createdAt: old.createdAt, label: label
        )
        store(own)
    }

    func setAction(of id: UUID, toOpen payload: OpenTargetPayload) {
        var own = ownBindings
        guard let index = own.firstIndex(where: { $0.id == id }) else { return }
        let old = own[index]
        own[index] = ButtonBinding(id: old.id, triggerEvent: old.triggerEvent, openTarget: payload, isEnabled: true, createdAt: old.createdAt)
        store(own)
    }

    private func presentOpenTargetPopover(forRow id: UUID) {
        guard let row = row(for: id) else { return }
        openTargetPopover?.hide()
        let popover = OpenTargetConfigPopover()
        openTargetPopover = popover
        popover.onCommit = { [weak self] payload in
            self?.setAction(of: id, toOpen: payload)
            self?.openTargetPopover = nil
        }
        popover.onCancel = { [weak self] in
            self?.openTargetPopover = nil
        }
        presentOpenTarget(popover, row.pullDown, ownBindings.first { $0.id == id }?.openTarget)
    }

    // MARK: - Adding

    /// Whether the app has a binding of its own for `trigger` already.
    func ownBinding(for trigger: RecordedEvent) -> ButtonBinding? {
        let identity = ButtonBindingIdentity(trigger)
        return ownBindings.first { $0.identity == identity }
    }

    /// `trigger` stays general (it opens the ring or runs Gesture Navigation in Buttons).
    func staysGeneral(_ trigger: RecordedEvent) -> Bool {
        return ApplicationButtons.generalOnlyTriggers(in: generalBindings)
            .contains(ButtonBindingTriggerKey(type: trigger.type, code: trigger.code))
    }

    /// What a button of the connected mouse stores: the trigger of its binding in Buttons,
    /// else what "+" of Buttons records for it on this mouse.
    func trigger(for part: ButtonsMousePart) -> RecordedEvent {
        let layout = ButtonsListLayout.make(bindings: generalBindings, mouse: mouse)
        if let binding = layout.row(of: part)?.binding {
            return binding.triggerEvent
        }
        return deviceSource.recordedTrigger(part)
    }

    /// The "+" menu: the buttons of the connected mouse the app has no binding of its own
    /// for, "Record a Button or Key…", then the bindings of Buttons not yet in the list.
    func makeAddMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        var offered: [ButtonBindingIdentity] = []
        let parts = ButtonsMousePart.listed(on: mouse).compactMap { part -> (ButtonsMousePart, RecordedEvent)? in
            let trigger = trigger(for: part)
            guard ownBinding(for: trigger) == nil, !staysGeneral(trigger), ButtonUtils.isRunnable(trigger) else { return nil }
            return (part, trigger)
        }
        if !parts.isEmpty {
            menu.addItem(NSMenuItem.sectionHeader(title: text("apps-buttons-add-mouse")))
            for (_, trigger) in parts {
                menu.addItem(item(ButtonTriggerNaming.title(for: trigger), .trigger(trigger)))
                offered.append(ButtonBindingIdentity(trigger))
            }
            menu.addItem(.separator())
        }
        menu.addItem(item(text("apps-buttons-add-record"), .record))
        let general = generalBindings.filter { binding in
            let trigger = binding.triggerEvent
            return !offered.contains(binding.identity) && ownBinding(for: trigger) == nil && !staysGeneral(trigger)
                && ButtonUtils.isRunnable(trigger) && CellActionState(binding: binding).hasBoundAction
        }
        if !general.isEmpty {
            menu.addItem(.separator())
            menu.addItem(NSMenuItem.sectionHeader(title: text("apps-buttons-add-general")))
            let titles = ButtonTriggerNaming.titles(for: generalBindings.map(\.triggerEvent))
            for binding in general {
                let index = generalBindings.firstIndex { $0.id == binding.id } ?? 0
                let action = resolver.actionName(of: binding) ?? text("buttons-default")
                let title = String(format: text("apps-buttons-add-general-item"), titles[index], action)
                menu.addItem(item(title, .trigger(binding.triggerEvent)))
            }
        }
        return menu
    }

    private func item(_ title: String, _ choice: AddChoice) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(addChosen(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = choice
        return item
    }

    func showAddMenu(from button: NSButton) {
        presentMenu(makeAddMenu(), button)
    }

    @objc func addChosen(_ sender: NSMenuItem) {
        switch sender.representedObject as? AddChoice {
        case .trigger(let trigger)?:
            addOwnBinding(for: trigger)
        case .record?:
            beginRecording()
        case nil:
            break
        }
    }

    /// Adds a binding of the app's own for `trigger` with the action the button has
    /// everywhere (so nothing changes until another one is chosen), selects it and opens
    /// its menu. A trigger the app has already is selected and flashes.
    @discardableResult
    func addOwnBinding(for trigger: RecordedEvent) -> UUID? {
        if let existing = ownBinding(for: trigger) {
            list.flash(AnyHashable(existing.id))
            return existing.id
        }
        guard !staysGeneral(trigger), ButtonUtils.isRunnable(trigger) else { return nil }
        let added = Self.newBinding(for: trigger, general: generalBindings)
        store(ownBindings + [added])
        list.select(AnyHashable(added.id))
        if trigger.type == .mouse, deviceSource.captureStatus(trigger.code) == .bleHIDPPUnstable {
            deviceSource.warnBluetoothButton(trigger.code)
        }
        // The new row's menu opens by itself, once the "+" menu or the recorder is gone.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.view.window != nil, let row = self.row(for: added.id),
                  self.list.selectedID == AnyHashable(added.id) else { return }
            self.openActionMenu(row.pullDown)
        }
        return added.id
    }

    /// A new binding of the app's own for `trigger`, with the action a press of it has
    /// everywhere, the one its "Everywhere" line names (`everywhereNote`): the general
    /// binding of that trigger, else the one such a press matches (a button bound without
    /// modifier keys runs with them too); "Default" when there is none. Never the ring or
    /// Gesture Navigation.
    static func newBinding(for trigger: RecordedEvent, general: [ButtonBinding]) -> ButtonBinding {
        if let model = ApplicationButtons.generalBinding(for: trigger, in: general), model.isEnabled,
           !ApplicationButtons.isGeneralOnly(action: model.systemShortcutName) {
            if let payload = model.openTarget {
                return ButtonBinding(triggerEvent: trigger, openTarget: payload)
            }
            return ButtonBinding(triggerEvent: trigger, systemShortcutName: model.systemShortcutName, label: model.label)
        }
        return ButtonBinding(triggerEvent: trigger, systemShortcutName: "", isEnabled: true)
    }

    // MARK: - Removing, with Undo

    var undoTarget: UndoManager? {
        return paneUndoManager ?? view.window?.undoManager
    }

    /// Gives the button back to Buttons; the window's Undo takes it again.
    func removeOwnBinding(id: UUID) {
        let showing = partShowing ?? { [weak self] entry in
            self?.application === entry ? self : nil
        }
        Self.removeOwnBinding(
            id: id, of: application, undoManager: undoTarget, showing: showing, listDidChange: onOwnButtonsChange
        )
    }

    /// The undo target is the settings, not this controller (as the Scrolling reset's): the
    /// page and its parts are gone once the list shows again, and its Undo still works.
    /// Undo and Redo find the app's entry by its path when they run (an app removed and
    /// added again is a new entry), and show the change on the part `showing` gives for it;
    /// `listDidChange` tells the list of apps (its marks). Neither holds the page.
    private static func removeOwnBinding(
        id: UUID, of application: Application, undoManager undo: UndoManager?,
        showing: @escaping (Application) -> ApplicationButtonsViewController?, listDidChange: (() -> Void)?
    ) {
        var own = application.ownButtonBindings
        guard let index = own.firstIndex(where: { $0.id == id }) else { return }
        let removed = own.remove(at: index)
        application.setOwnButtonBindings(own)
        showing(application)?.showUndoableChange(selecting: nil)
        listDidChange?()
        guard let undo else { return }
        let path = application.path
        undo.registerUndo(withTarget: Options.shared) { [weak undo] _ in
            guard let entry = Self.entry(storedAs: path) else { return }
            Self.restoreOwnBinding(removed, at: index, of: entry, undoManager: undo, showing: showing, listDidChange: listDidChange)
        }
        undo.setActionName(NSLocalizedString("buttons-undo-remove", comment: ""))
    }

    private static func restoreOwnBinding(
        _ binding: ButtonBinding, at index: Int, of application: Application, undoManager undo: UndoManager?,
        showing: @escaping (Application) -> ApplicationButtonsViewController?, listDidChange: (() -> Void)?
    ) {
        var own = application.ownButtonBindings
        if let existing = own.first(where: { $0.identity == binding.identity }) {
            // Added again meanwhile: that one stays.
            showing(application)?.showUndoableChange(selecting: existing.id)
            return
        }
        own.insert(binding, at: min(max(0, index), own.count))
        application.setOwnButtonBindings(own)
        showing(application)?.showUndoableChange(selecting: binding.id)
        listDidChange?()
        guard let undo else { return }
        let path = application.path
        undo.registerUndo(withTarget: Options.shared) { [weak undo] _ in
            guard let entry = Self.entry(storedAs: path) else { return }
            Self.removeOwnBinding(id: binding.id, of: entry, undoManager: undo, showing: showing, listDidChange: listDidChange)
        }
        undo.setActionName(NSLocalizedString("buttons-undo-remove", comment: ""))
    }

    /// The entry the list holds now for the app stored as `path`, as the Undo of an app's
    /// removal finds it (`PreferencesApplicationViewController.restoreApplication`).
    private static func entry(storedAs path: String) -> Application? {
        return PreferencesApplicationViewController.existingApplication(
            forPaths: PreferencesApplicationViewController.knownPaths(forStoredPath: path)
        )
    }

    /// A removal, its Undo or its Redo changed the app's list: the rows again, with `id`
    /// selected.
    private func showUndoableChange(selecting id: UUID?) {
        guard isViewLoaded else { return }
        reloadRows()
        if let id {
            list.select(AnyHashable(id))
        }
    }

    // MARK: - Recording

    /// "Record a Button or Key…": the Buttons pane's recorder, at "+".
    func beginRecording() {
        guard !isRecorderOpen else { return }
        pendingRecorded = nil
        let anchor = list.addButton
        if let startRecording {
            startRecording(anchor)
        } else {
            recorder.startRecording(from: anchor, mode: .combination)
        }
    }

    /// The trigger of a recorded event, as the Buttons pane stores it.
    func normalizedTrigger(for event: InputEvent) -> RecordedEvent {
        let recorded = RecordedEvent(from: event)
        let diagnosis = LogiCenter.shared.buttonCaptureDiagnosis(forScrollioCode: event.code)
        return recorded.normalizedForButtonBinding(diagnosis: diagnosis)
    }

    private func text(_ key: String) -> String {
        return NSLocalizedString(key, comment: "")
    }
}

// MARK: - Recording a button

extension ApplicationButtonsViewController: KeyRecorderDelegate {

    func onRecordingStarted(_ recorder: KeyRecorder) {
        isRecorderOpen = true
    }

    /// A button the app has already counts as a duplicate (the recorder says so); one that
    /// stays general is refused, and the recorder says why.
    func validateRecordedEvent(_ recorder: KeyRecorder, event: InputEvent) -> Bool {
        let trigger = normalizedTrigger(for: event)
        return ownBinding(for: trigger) == nil && !staysGeneral(trigger)
    }

    func refusalHint(_ recorder: KeyRecorder, event: InputEvent) -> String? {
        return staysGeneral(normalizedTrigger(for: event)) ? text("apps-buttons-recorder-general") : nil
    }

    func onEventRecorded(_ recorder: KeyRecorder, didRecordEvent event: InputEvent, isDuplicate: Bool) {
        let trigger = normalizedTrigger(for: event)
        if let existing = ownBinding(for: trigger) {
            pendingRecorded = nil
            list.flash(AnyHashable(existing.id))
            return
        }
        pendingRecorded = isDuplicate || staysGeneral(trigger) ? nil : trigger
    }

    /// The recorder closed, however: what it caught is added now.
    func onRecordingStopped(_ recorder: KeyRecorder, didRecord: Bool) {
        isRecorderOpen = false
        guard didRecord, let trigger = pendingRecorded else { return }
        pendingRecorded = nil
        addOwnBinding(for: trigger)
    }
}
