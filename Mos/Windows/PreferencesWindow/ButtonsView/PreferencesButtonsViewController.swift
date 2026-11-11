//
//  PreferencesButtonsViewController.swift
//  Mos
//  "Buttons" preferences pane, built in code on the grouped kit like Scrolling, Gestures and
//  Mouse; the storyboard scene is a shell. On top a card with the mouse whose button the
//  pane is about lit up, then the list of buttons (PreferencesListBox): each row shows
//  where the button is in a small picture, names the button, says what its action needs or
//  what is wrong with it, and has the action pull-down. A button the drawing cannot show
//  ("Button 5") is found by asking the mouse: "+" and pressing it makes the card say
//  "That's Button 5"; a click on its picture then says where it is ("Which Button Is
//  This?"), and from then on it is named and lit as that part. "+" records a button (or a
//  key with a modifier), "−" removes one, and the window's Undo puts it back. Only
//  Options.shared.buttons.binding is edited, in the format it always had; a placed button
//  adds the trigger's optional `mousePart`.
//  Created by Claude on 2025/8/10.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

/// What the Buttons pane reads from the mice. `live` uses LogiCenter; tests and
/// screenshots pass fixtures, so no HID device is touched.
struct ButtonsDeviceSource {
    /// What the Logitech mouse says about a trigger code (`.normal` for other buttons).
    var captureStatus: (UInt16) -> ButtonCapturePresentationStatus
    /// The connected Logitech mouse's name, nil without one.
    var deviceName: () -> String?
    /// The mice are being asked about their buttons ("Checking buttons…").
    var isBusy: () -> Bool
    /// Asks the mice again about their buttons; answers arrive as notifications.
    var refresh: () -> Void
    /// Warns once that a newly added Logitech button may stop working over Bluetooth.
    var warnBluetoothButton: (UInt16) -> Void

    static let live = ButtonsDeviceSource(
        captureStatus: { code in
            guard LogiCenter.shared.isLogiCode(code) else { return .normal }
            return ButtonCapturePresentationStatus.from(LogiCenter.shared.buttonCaptureDiagnosis(forMosCode: code))
        },
        // The mouse the Mouse pane's card is about (the one with the most settings), so
        // the two cards never name different mice.
        deviceName: { MousePaneModel.ordered(LogiCenter.shared.mouseDeviceStates()).first?.deviceName },
        isBusy: { LogiCenter.shared.isBusy },
        refresh: { LogiCenter.shared.refreshReportingStates() },
        warnBluetoothButton: { LogiCenter.shared.showBLEHIDPPUnstableToast(forMosCode: $0) }
    )
}

class PreferencesButtonsViewController: NSViewController {

    /// The column of the Preferences window.
    static let paneWidth: CGFloat = PreferencesWindowLayout.contentWidth
    static var boxWidth: CGFloat {
        return PreferencesGroupedForm.boxWidth(paneWidth: paneWidth)
    }
    /// A button just recorded (or "That's …" for a listed one) stays on the card this long,
    /// whatever the pointer is over.
    static let recordedPartDuration: TimeInterval = 1.5
    /// "Checking buttons…" stays at least this long, so it never only flickers.
    static let busyMinimumDuration: TimeInterval = 0.5

    enum Identifier {
        static let header = NSUserInterfaceItemIdentifier("buttons-header")
        static let list = NSUserInterfaceItemIdentifier("buttons-list")
        static let busy = NSUserInterfaceItemIdentifier("buttons-busy")
    }

    // MARK: - Seams (tests and screenshots replace them)

    var deviceSource: ButtonsDeviceSource = .live
    /// The keys of Scrolling › While you hold a key.
    var scrollHoldKeys: () -> [ScrollHotkey] = {
        let scroll = Options.shared.scroll
        return [scroll.dash, scroll.toggle, scroll.block].compactMap { $0 }
    }
    /// Starts recording a button at "+". nil: the real recorder, which taps the system's
    /// events; tests never use it.
    var startRecording: ((NSView) -> Void)?
    /// Ends a recording that is still open (the pane went away). nil: the real recorder.
    var stopRecording: (() -> Void)?
    /// Shows "Open App or File" at a row's pull-down. Tests replace it: nothing is shown.
    var presentOpenTarget: (OpenTargetConfigPopover, NSView, OpenTargetPayload?) -> Void = { popover, anchor, existing in
        popover.show(at: anchor, existing: existing)
    }
    /// Opens a row's action menu. The menu runs until it closes, so tests replace it.
    var openActionMenu: (NSPopUpButton) -> Void = { $0.performClick(nil) }
    /// Opens "Which Button Is This?" under a row's picture. The menu runs until it closes,
    /// so tests replace it.
    var presentPlaceMenu: (NSMenu, NSView) -> Void = { menu, anchor in
        let below = anchor.isFlipped ? anchor.bounds.maxY + 4 : anchor.bounds.minY - 4
        menu.popUp(positioning: nil, at: NSPoint(x: anchor.bounds.minX, y: below), in: anchor)
    }
    /// Shows another pane of the window (the Gestures pane).
    var showPane: ((String) -> Void)?
    /// Takes Undo and Redo of a removal; the window's when nil.
    var paneUndoManager: UndoManager?

    // MARK: - State

    private(set) var buttonBindings: [ButtonBinding] = []
    /// The drawing of the connected mouse, on the card and in every row's picture.
    private(set) var mouse: MouseArtworkModel = .generic
    /// "+" waits for a button: the card says "Press a button".
    private(set) var isRecording = false
    /// The recorder is open, from its start until it reports that it stopped (after a
    /// button was caught it stays open a moment longer to show it).
    private(set) var isRecorderOpen = false
    /// The button just recorded: the card shows it for a moment.
    private(set) var recordedFocus: ButtonsHeaderContent.Focus?
    /// The action a binding added next gets (Gestures › Set Up…), nil: none.
    private(set) var pendingAction: SystemShortcut.Shortcut?
    /// What the recorder caught, kept until it closes.
    private var pendingRecorded: RecordedEvent?
    private var recordedFocusWork: DispatchWorkItem?
    /// The pane went away (another pane, the window closed) and has not come back.
    private var isAway = false
    private var busyShownAt: Date?
    private var busyStopWork: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []

    private let recorder = KeyRecorder()
    private let resolver = ActionDisplayResolver()

    // MARK: - Views (read access for tests)

    private(set) var headerView: ButtonsHeaderView!
    private(set) var list: PreferencesListBox!
    private(set) var busyView: NSStackView!
    private(set) var busySpinner: NSProgressIndicator!
    private(set) var rows: [ButtonBindingRow] = []
    private(set) var problemPopover: NSPopover?
    /// "Open App or File", while it is open.
    private(set) var openTargetPopover: OpenTargetConfigPopover?

    // MARK: - Lifecycle

    override func loadView() {
        let root = PreferencesForm.makeBackground()
        let content = PreferencesGroupedForm.installContentStack(in: root, paneWidth: Self.paneWidth)
        content.setHuggingPriority(.defaultHigh, for: .vertical)

        let header = ButtonsHeaderView()
        header.identifier = Identifier.header
        headerView = header

        let list = PreferencesListBox(
            width: Self.boxWidth,
            emptyTitle: text("buttons-empty-title"),
            emptyExplanation: text("buttons-empty-hint")
        )
        list.identifier = Identifier.list
        list.rowsView.setAccessibilityLabel(text("buttons-list-label"))
        list.onAdd = { [weak self] _ in self?.beginAddingBinding() }
        list.onRemove = { [weak self] id in
            guard let id = id as? UUID else { return }
            self?.removeBinding(id: id)
        }
        list.onOpen = { [weak self] id in
            guard let self, let row = self.row(for: id) else { return }
            self.openActionMenu(row.pullDown)
        }
        list.onHover = { [weak self] _ in self?.updateHeader() }
        list.onSelect = { [weak self] _ in self?.updateHeader() }
        list.footerAccessory = makeBusyView()
        self.list = list

        PreferencesGroupedForm.add([header, list], to: content)
        view = root
        recorder.delegate = self
        reload()
        root.setFrameSize(root.fittingSize)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let center = NotificationCenter.default
        // What the mice say about their buttons changed: the notes follow.
        for name in [LogiCenter.sessionChanged, LogiCenter.reportingDidComplete, LogiCenter.conflictChanged] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.reloadRows()
                self?.updateHeader()
            })
        }
        // Another mouse connected or the one there left: the drawings follow.
        observers.append(center.addObserver(forName: LogiCenter.mouseStateChanged, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.connectedMouse() != self.mouse else { return }
            self.reloadRows()
            self.updateHeader()
        })
        observers.append(center.addObserver(forName: LogiCenter.activityChanged, object: nil, queue: .main) { [weak self] _ in
            self?.syncBusy()
        })
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        isAway = false
        // Bindings may have changed elsewhere (Gestures › Set Up…); then ask the mice again.
        reload()
        deviceSource.refresh()
        syncBusy()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        isAway = true
        closeTransientUI()
    }

    /// The pane goes away (another pane, the window closes): what it opened goes with it,
    /// the ⓘ popover, "Open App or File" (as Cancel), the recorder of "+" and the
    /// recorder of a "Keyboard Shortcut…".
    func closeTransientUI() {
        problemPopover?.close()
        problemPopover = nil
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

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        recordedFocusWork?.cancel()
        busyStopWork?.cancel()
    }

    // MARK: - Data

    /// Reads the bindings and shows them.
    func reload() {
        guard isViewLoaded, list != nil else { return }
        buttonBindings = Options.shared.buttons.binding
        reloadRows()
        updateHeader()
    }

    /// Writes the bindings. ButtonUtils and the Logitech divert follow the stored value.
    private func save() {
        Options.shared.buttons.binding = buttonBindings
    }

    func binding(for id: UUID) -> ButtonBinding? {
        return buttonBindings.first { $0.id == id }
    }

    func row(for id: AnyHashable) -> ButtonBindingRow? {
        return rows.first { $0.id == id }
    }

    /// Puts every binding into its row: the rows of bindings still there are updated (a
    /// pull-down keeps the keyboard focus), new ones made, and the list told only when the
    /// rows themselves changed.
    func reloadRows() {
        guard let list else { return }
        mouse = connectedMouse()
        let old = rows
        let titles = ButtonTriggerNaming.titles(for: buttonBindings.map(\.triggerEvent))
        rows = zip(buttonBindings, titles).map { binding, title in
            let note = note(for: binding)
            if let existing = old.first(where: { $0.id == AnyHashable(binding.id) }) {
                existing.update(binding: binding, title: title, note: note, mouse: mouse)
                return existing
            }
            return makeRow(for: binding, title: title, note: note)
        }
        if rows.count != old.count || zip(rows, old).contains(where: { $0 !== $1 }) {
            list.setRows(rows)
        }
        PreferencesForm.fitToContent(self)
    }

    func note(for binding: ButtonBinding) -> ButtonRowNote? {
        let trigger = binding.triggerEvent
        let status = trigger.type == .mouse ? deviceSource.captureStatus(trigger.code) : .normal
        let standard = binding.standardMouseAliasBindingIfAvailable().map {
            ButtonTriggerNaming.buttonName(code: $0.triggerEvent.code)
        }
        return ButtonRowNote.make(
            for: binding,
            captureStatus: status,
            scrollHoldKeys: scrollHoldKeys(),
            standardButtonName: standard
        )
    }

    private func makeRow(for binding: ButtonBinding, title: String, note: ButtonRowNote?) -> ButtonBindingRow {
        let id = binding.id
        let pullDown = ButtonActionPullDown(binding: binding)
        pullDown.onShortcutSelected = { [weak self] shortcut in
            self?.setAction(of: id, to: shortcut)
        }
        pullDown.onCustomShortcutRecorded = { [weak self] name in
            self?.setAction(of: id, toShortcutNamed: name)
        }
        pullDown.onOpenTargetSelectionRequested = { [weak self] in
            self?.presentOpenTargetPopover(forBindingID: id)
        }
        pullDown.onGestureSettingsRequested = { [weak self] in
            self?.showGesturesPane()
        }
        let row = ButtonBindingRow(binding: binding, title: title, note: note, mouse: mouse, pullDown: pullDown)
        row.infoButton.target = self
        row.infoButton.action = #selector(infoClicked(_:))
        row.onPlaceRequested = { [weak self] anchor in
            self?.showPlaceMenu(for: id, from: anchor)
        }
        row.placeMenu = { [weak self] in
            guard let self, let menu = self.placeMenu(for: id) else { return nil }
            self.list.select(id)
            return menu
        }
        return row
    }

    // MARK: - Changing actions

    func setAction(of id: UUID, to shortcut: SystemShortcut.Shortcut?) {
        update(id) { old in
            ButtonBinding(
                id: old.id,
                triggerEvent: old.triggerEvent,
                systemShortcutName: shortcut?.identifier ?? "",
                isEnabled: shortcut != nil,
                createdAt: old.createdAt
            )
        }
    }

    func setAction(of id: UUID, toShortcutNamed name: String) {
        update(id) { old in
            ButtonBinding(id: old.id, triggerEvent: old.triggerEvent, systemShortcutName: name, isEnabled: true, createdAt: old.createdAt)
        }
    }

    func setAction(of id: UUID, toOpen payload: OpenTargetPayload) {
        update(id) { old in
            ButtonBinding(id: old.id, triggerEvent: old.triggerEvent, openTarget: payload, isEnabled: true, createdAt: old.createdAt)
        }
    }

    private func update(_ id: UUID, _ transform: (ButtonBinding) -> ButtonBinding) {
        guard let index = buttonBindings.firstIndex(where: { $0.id == id }) else { return }
        buttonBindings[index] = transform(buttonBindings[index])
        save()
        reloadRows()
        updateHeader()
    }

    /// Replaces a binding (its trigger may change: "Use Standard Button"); a binding of the
    /// same trigger merges into it.
    func replaceBinding(_ binding: ButtonBinding) {
        guard buttonBindings.contains(where: { $0.id == binding.id }) else { return }
        buttonBindings = ButtonBindingReplacement.replacing(binding, in: buttonBindings)
        save()
        reloadRows()
        updateHeader()
    }

    /// "Use Standard Button": the Logitech button becomes the standard button it stands for.
    func useStandardButton(for id: UUID) {
        guard let updated = binding(for: id)?.standardMouseAliasBindingIfAvailable() else { return }
        LogiCenter.shared.logButtonCaptureDiagnostic(
            "[StandardMouseAlias] converted binding id=\(updated.id) nativeButton=\(updated.triggerEvent.code)"
        )
        problemPopover?.close()
        problemPopover = nil
        replaceBinding(updated)
    }

    // MARK: - Which button is this?

    /// "Which Button Is This?" for `id`'s row; nil when its button's place is known.
    func placeMenu(for id: UUID) -> NSMenu? {
        guard let binding = binding(for: id),
              let model = ButtonPlaceMenuModel.make(for: binding.triggerEvent, among: buttonBindings.map(\.triggerEvent), mouse: mouse)
        else { return nil }
        return ButtonPlaceMenu.make(model, bindingID: id, target: self, action: #selector(placeChosen(_:)))
    }

    /// The row's picture was clicked: the row is selected (the card shows it) and the menu
    /// opens under the picture.
    func showPlaceMenu(for id: UUID, from anchor: NSView) {
        guard let menu = placeMenu(for: id) else { return }
        list.select(id)
        presentPlaceMenu(menu, anchor)
    }

    @objc func placeChosen(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? ButtonPlaceChoice else { return }
        setPlace(of: choice.bindingID, to: choice.part)
    }

    /// Says that `id`'s numbered button is `part` of the mouse (nil: not on the list), for
    /// every row of that button number: they are the same button with other modifiers.
    /// Only the display changes; nothing is saved when nothing changes.
    func setPlace(of id: UUID, to part: PlacedMousePart?) {
        guard let trigger = binding(for: id)?.triggerEvent, ButtonTriggerPicture.number(for: trigger) != nil else { return }
        var changed = false
        buttonBindings = buttonBindings.map { binding in
            let other = binding.triggerEvent
            guard Self.isSameButton(other, as: trigger), other.mousePart != part else { return binding }
            changed = true
            return binding.replacingTriggerEvent(other.placed(at: part))
        }
        guard changed else { return }
        save()
        reloadRows()
        updateHeader()
    }

    /// `trigger` placed as the list's rows of its button number are (the same button with
    /// other modifiers); as it is when the list has no other row of that number.
    func placedLikeItsButton(_ trigger: RecordedEvent, except id: UUID? = nil) -> RecordedEvent {
        guard ButtonTriggerPicture.number(for: trigger) != nil,
              let sibling = buttonBindings.first(where: { $0.id != id && Self.isSameButton($0.triggerEvent, as: trigger) })
        else { return trigger }
        let part = sibling.triggerEvent.mousePart
        return trigger.mousePart == part ? trigger : trigger.placed(at: part)
    }

    private static func isSameButton(_ a: RecordedEvent, as b: RecordedEvent) -> Bool {
        return a.type == .mouse && b.type == .mouse && a.code == b.code
    }

    // MARK: - Removing, with Undo

    /// Where a removal registers its Undo: the window's undo manager while the pane is in
    /// the window. Undo and Redo stay with the manager the removal used, also when they
    /// run while another pane is shown (this pane is then out of the window).
    var undoTarget: UndoManager? {
        return paneUndoManager ?? view.window?.undoManager
    }

    /// Removes the binding; the window's Undo ("Undo Remove Button") puts it back.
    func removeBinding(id: UUID) {
        removeBinding(id: id, undoManager: undoTarget)
    }

    private func removeBinding(id: UUID, undoManager undo: UndoManager?) {
        guard let index = buttonBindings.firstIndex(where: { $0.id == id }) else { return }
        let removed = buttonBindings.remove(at: index)
        save()
        reloadRows()
        updateHeader()
        guard let undo else { return }
        undo.registerUndo(withTarget: self) { [weak undo] controller in
            controller.restoreBinding(removed, at: index, undoManager: undo)
        }
        undo.setActionName(text("buttons-undo-remove"))
    }

    /// Puts a removed binding back where it was, selects it and gives the list the
    /// keyboard (Undo). Redo removes it again.
    func restoreBinding(_ binding: ButtonBinding, at index: Int) {
        restoreBinding(binding, at: index, undoManager: undoTarget)
    }

    private func restoreBinding(_ binding: ButtonBinding, at index: Int, undoManager undo: UndoManager?) {
        if let existing = buttonBindings.first(where: { $0.triggerEvent == binding.triggerEvent }) {
            // Recorded again meanwhile: the new one stays.
            list.select(existing.id)
            focusList()
            return
        }
        // Its place as the rows of its button say now (it keeps its own when it is alone).
        let placed = placedLikeItsButton(binding.triggerEvent, except: binding.id)
        let binding = placed.mousePart == binding.triggerEvent.mousePart ? binding : binding.replacingTriggerEvent(placed)
        buttonBindings.insert(binding, at: min(max(0, index), buttonBindings.count))
        save()
        reloadRows()
        list.select(binding.id)
        focusList()
        updateHeader()
        guard let undo else { return }
        undo.registerUndo(withTarget: self) { [weak undo] controller in
            controller.removeBinding(id: binding.id, undoManager: undo)
        }
        undo.setActionName(text("buttons-undo-remove"))
    }

    /// The list takes the keyboard (after an add or an Undo), when the pane is shown.
    private func focusList() {
        guard !isAway, let window = view.window, list.window === window else { return }
        window.makeFirstResponder(list)
    }

    // MARK: - Adding

    /// "+": records a button, or a key with a modifier. A new one is added without an
    /// action, selected, and its menu opens; with `action` (Gestures › Set Up…) it gets
    /// that action instead, and so does a button the list has without an action.
    ///
    /// The recording lasts as long as the recorder says: it reports its start, and its end
    /// however it ends (a button, Esc, its timeout, which a held modifier extends, or no
    /// event tap). `action` waits until then.
    func beginAddingBinding(action: SystemShortcut.Shortcut? = nil) {
        _ = view
        guard !isRecording, !isRecorderOpen else { return }
        pendingAction = action
        pendingRecorded = nil
        let anchor = list.addButton
        // With a long list "+" is below the visible part: the recorder's popover hangs on it.
        anchor.scrollToVisible(anchor.bounds)
        if let startRecording {
            startRecording(anchor)
        } else {
            recorder.startRecording(from: anchor, mode: .combination)
        }
    }

    /// The trigger of a recorded event, placed like the rows of its button number.
    private func normalizedTrigger(for event: InputEvent) -> RecordedEvent {
        let recorded = RecordedEvent(from: event)
        let diagnosis = LogiCenter.shared.buttonCaptureDiagnosis(forMosCode: event.code)
        return placedLikeItsButton(recorded.normalizedForButtonBinding(diagnosis: diagnosis))
    }

    /// The binding the list has for `trigger`, if any.
    func existingBinding(for trigger: RecordedEvent) -> ButtonBinding? {
        return buttonBindings.first { $0.triggerEvent == trigger }
    }

    /// A recorded `trigger` that the list has already, and that takes `action` (Gestures ›
    /// Set Up…) because it has no action yet.
    private func takesPendingAction(_ existing: ButtonBinding, action: SystemShortcut.Shortcut?) -> Bool {
        return action != nil && !CellActionState(binding: existing).hasBoundAction
    }

    /// Adds `trigger` and returns the id. A trigger the list has already is selected and
    /// flashes; with `action` and no action of its own it gets `action`. The list then
    /// has the keyboard.
    @discardableResult
    func addBinding(for trigger: RecordedEvent, action: SystemShortcut.Shortcut?) -> UUID {
        defer { focusList() }
        if let existing = existingBinding(for: trigger) {
            if takesPendingAction(existing, action: action) {
                setAction(of: existing.id, to: action)
                list.select(existing.id)
            } else {
                list.flash(existing.id)
            }
            return existing.id
        }
        let binding = ButtonBinding(
            triggerEvent: placedLikeItsButton(trigger),
            systemShortcutName: action?.identifier ?? "",
            isEnabled: action != nil
        )
        buttonBindings.append(binding)
        save()
        reloadRows()
        list.select(binding.id)
        if trigger.type == .mouse, deviceSource.captureStatus(trigger.code) == .bleHIDPPUnstable {
            deviceSource.warnBluetoothButton(trigger.code)
        }
        return binding.id
    }

    // MARK: - Open App or File

    private func presentOpenTargetPopover(forBindingID id: UUID) {
        guard let binding = binding(for: id), let row = row(for: id) else { return }
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
        presentOpenTarget(popover, row.pullDown, binding.openTarget)
    }

    // MARK: - Gestures

    /// "Show Gesture Settings": the Gestures pane.
    func showGesturesPane() {
        let identifier = GesturesPreferencesViewController.tabIdentifier
        if let showPane {
            showPane(identifier)
            return
        }
        Self.splitViewController(of: self)?.selectPane(withIdentifier: identifier)
    }

    static func splitViewController(of controller: NSViewController) -> PreferencesSplitViewController? {
        var current: NSViewController? = controller.parent
        while let candidate = current {
            if let split = candidate as? PreferencesSplitViewController { return split }
            current = candidate.parent
        }
        return nil
    }

    // MARK: - The ⓘ of a row

    @objc private func infoClicked(_ sender: NSButton) {
        guard let row = rows.first(where: { $0.infoButton === sender }) else { return }
        showProblem(of: row, relativeTo: sender)
    }

    /// The popover that explains the row's note, next to `anchor`.
    @discardableResult
    func showProblem(of row: ButtonBindingRow, relativeTo anchor: NSView) -> ButtonProblemPopoverController? {
        guard let note = row.note, note.hasDetails else { return nil }
        problemPopover?.close()
        let content = ButtonProblemPopoverController(note: note)
        let id = row.binding.id
        content.onUseStandardButton = { [weak self] in self?.useStandardButton(for: id) }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = content
        problemPopover = popover
        if anchor.window != nil {
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        }
        return content
    }

    // MARK: - The card

    /// The card's texts and lit part: recording, the button just recorded, the row pointed
    /// at, the selected row, or the mouse and how many buttons have actions.
    func updateHeader() {
        guard let headerView else { return }
        var focus: ButtonsHeaderContent.Focus? = recordedFocus
        if focus == nil, let id = (list.hoveredID ?? list.selectedID) as? UUID, let binding = binding(for: id) {
            focus = self.focus(for: binding)
        }
        let bound = buttonBindings.filter { CellActionState(binding: $0).hasBoundAction }.count
        headerView.mouse = mouse
        headerView.content = ButtonsHeaderContent.make(
            deviceName: deviceSource.deviceName(),
            boundCount: bound,
            isRecording: isRecording,
            mouseButtonOnly: Self.needsMouseButton(pendingAction),
            focus: focus
        )
    }

    /// Gesture Navigation is held while the mouse moves: only a mouse button can have it.
    static func needsMouseButton(_ action: SystemShortcut.Shortcut?) -> Bool {
        return action?.identifier == SystemShortcut.mouseGestureNavigation.identifier
    }

    /// What the card says about `binding`'s row, pointed at or selected, or (`.answer`)
    /// pressed after "+" ("That's …").
    func focus(for binding: ButtonBinding, reason: ButtonsHeaderContent.Focus.Reason = .row) -> ButtonsHeaderContent.Focus {
        return ButtonsHeaderContent.Focus(
            title: title(for: binding.triggerEvent),
            action: resolver.actionName(of: binding),
            picture: ButtonTriggerPicture.make(for: binding.triggerEvent, mouse: mouse),
            reason: reason
        )
    }

    /// Shows `focus` on the card for `recordedPartDuration`.
    private func showRecorded(_ focus: ButtonsHeaderContent.Focus) {
        recordedFocusWork?.cancel()
        recordedFocus = focus
        updateHeader()
        let work = DispatchWorkItem { [weak self] in
            self?.recordedFocus = nil
            self?.recordedFocusWork = nil
            self?.updateHeader()
        }
        recordedFocusWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.recordedPartDuration, execute: work)
    }

    /// What the list calls `trigger` (with the bindings it has).
    func title(for trigger: RecordedEvent) -> String {
        return ButtonTriggerNaming.title(for: trigger, among: buttonBindings.map(\.triggerEvent))
    }

    /// The drawing for the connected mouse, as the card names it.
    private func connectedMouse() -> MouseArtworkModel {
        return MouseArtworkModel.model(forDeviceName: deviceSource.deviceName())
    }

    // MARK: - "Checking buttons…"

    private func makeBusyView() -> NSView {
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            spinner.widthAnchor.constraint(equalToConstant: 12),
            spinner.heightAnchor.constraint(equalToConstant: 12),
        ])
        let label = NSTextField(labelWithString: text("buttons-checking"))
        label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        let busy = NSStackView(views: [spinner, label])
        busy.orientation = .horizontal
        busy.alignment = .centerY
        busy.spacing = 6
        busy.identifier = Identifier.busy
        busy.isHidden = true
        busyView = busy
        busySpinner = spinner
        return busy
    }

    /// Shows "Checking buttons…" while the mice are asked, at least `busyMinimumDuration`.
    func syncBusy() {
        guard let busyView else { return }
        if deviceSource.isBusy() {
            busyStopWork?.cancel()
            busyStopWork = nil
            if busyShownAt == nil {
                busyShownAt = Date()
                busyView.isHidden = false
                busySpinner.startAnimation(nil)
            }
            return
        }
        guard let shownAt = busyShownAt else { return }
        let remaining = Self.busyMinimumDuration - Date().timeIntervalSince(shownAt)
        guard remaining > 0 else { return hideBusy() }
        busyStopWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hideBusy() }
        busyStopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: work)
    }

    private func hideBusy() {
        busyStopWork = nil
        busyShownAt = nil
        busySpinner.stopAnimation(nil)
        busyView.isHidden = true
    }

    private func text(_ key: String) -> String {
        return NSLocalizedString(key, comment: "")
    }
}

// MARK: - Recording a new button

extension PreferencesButtonsViewController: KeyRecorderDelegate {

    func onRecordingStarted(_ recorder: KeyRecorder) {
        isRecording = true
        isRecorderOpen = true
        updateHeader()
    }

    /// A trigger that is already in the list counts as a duplicate (the recorder says so),
    /// unless it has no action and gets the one waiting (Gestures › Set Up…).
    func validateRecordedEvent(_ recorder: KeyRecorder, event: InputEvent) -> Bool {
        let trigger = normalizedTrigger(for: event)
        // A key cannot be the gesture button (Gestures › Set Up…): refused, and the
        // recorder says why (`refusalHint`).
        if Self.needsMouseButton(pendingAction), trigger.type == .keyboard { return false }
        guard let existing = existingBinding(for: trigger) else { return true }
        return takesPendingAction(existing, action: pendingAction)
    }

    /// The recorder's hint for a refused event: a key while the gesture button is set up
    /// ("Gestures need a mouse button"); nil (a duplicate) otherwise.
    func refusalHint(_ recorder: KeyRecorder, event: InputEvent) -> String? {
        guard Self.needsMouseButton(pendingAction), normalizedTrigger(for: event).type == .keyboard else { return nil }
        return NSLocalizedString("buttons-gesture-needs-mouse-button", comment: "")
    }

    /// The card shows the button at once; a listed one's row flashes while the recorder
    /// says "Duplicate key", and the card answers "That's <row title>" with its part lit
    /// (or its number by the mouse). A new one is added, or a listed one without an action
    /// gets the waiting action, when the recorder closes.
    func onEventRecorded(_ recorder: KeyRecorder, didRecordEvent event: InputEvent, isDuplicate: Bool) {
        let trigger = normalizedTrigger(for: event)
        isRecording = false
        if Self.needsMouseButton(pendingAction), trigger.type == .keyboard {
            // Nothing is added: the card says why.
            pendingRecorded = nil
            showRecorded(ButtonsHeaderContent.Focus(
                title: NSLocalizedString("buttons-gesture-needs-mouse-button", comment: ""),
                action: NSLocalizedString("buttons-gesture-needs-mouse-button-detail", comment: ""),
                picture: ButtonTriggerPicture.make(for: trigger, mouse: mouse),
                reason: .recorded
            ))
            return
        }
        if let existing = existingBinding(for: trigger), !takesPendingAction(existing, action: pendingAction) {
            pendingRecorded = nil
            list.flash(existing.id)
            showRecorded(focus(for: existing, reason: .answer))
            return
        }
        pendingRecorded = trigger
        showRecorded(ButtonsHeaderContent.Focus(
            title: title(for: trigger),
            action: pendingAction.map(\.localizedName),
            picture: ButtonTriggerPicture.make(for: trigger, mouse: mouse),
            reason: .recorded
        ))
    }

    /// The recorder closed, however: the recording ends here, and only here.
    func onRecordingStopped(_ recorder: KeyRecorder, didRecord: Bool) {
        isRecording = false
        isRecorderOpen = false
        let action = pendingAction
        pendingAction = nil
        defer { updateHeader() }
        guard didRecord, let trigger = pendingRecorded else { return }
        pendingRecorded = nil
        let isNew = existingBinding(for: trigger) == nil
        let id = addBinding(for: trigger, action: action)
        updateHeader()
        guard action == nil, isNew else { return }
        // The recorder's popover is gone: the new button's menu opens by itself (not when
        // the pane went away meanwhile).
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isAway, let row = self.row(for: id),
                  self.list.selectedID == AnyHashable(id) else { return }
            self.openActionMenu(row.pullDown)
        }
    }
}
