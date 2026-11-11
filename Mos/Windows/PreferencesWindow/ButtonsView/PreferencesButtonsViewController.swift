//
//  PreferencesButtonsViewController.swift
//  Mos
//  "Buttons" preferences pane, built in code on the grouped kit like Scrolling, Gestures and
//  Mouse; the storyboard scene is a shell. On top a card with the mouse whose button the
//  pane is about lit up, then the list of buttons (PreferencesListBox): each row names the
//  button, says what its action needs or what is wrong with it, and has the action
//  pull-down. "+" records a button (or a key with a modifier), "−" removes one, and the
//  window's Undo puts it back. Only Options.shared.buttons.binding is edited, in the format
//  it always had.
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
        deviceName: { LogiCenter.shared.mouseDeviceStates().first?.deviceName },
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
    /// A button just recorded stays lit this long, whatever the pointer is over.
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
    /// Opens a row's action menu. The menu runs until it closes, so tests replace it.
    var openActionMenu: (NSPopUpButton) -> Void = { $0.performClick(nil) }
    /// Shows another pane of the window (the Gestures pane).
    var showPane: ((String) -> Void)?
    /// Takes Undo and Redo of a removal; the window's when nil.
    var paneUndoManager: UndoManager?

    // MARK: - State

    private(set) var buttonBindings: [ButtonBinding] = []
    /// "+" waits for a button.
    private(set) var isRecording = false
    /// The button just recorded: the card shows it for a moment.
    private(set) var recordedFocus: ButtonsHeaderContent.Focus?
    /// The action a binding added next gets (Gestures › Set Up…), nil: none.
    private(set) var pendingAction: SystemShortcut.Shortcut?
    /// What the recorder caught, kept until it closes.
    private var pendingRecorded: RecordedEvent?
    private var recordedFocusWork: DispatchWorkItem?
    /// Ends the recording state if the recorder never reports back (it could not start).
    private var recordingWatchdog: DispatchWorkItem?
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
    private var currentOpenTargetPopover: OpenTargetConfigPopover?

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
        observers.append(center.addObserver(forName: LogiCenter.activityChanged, object: nil, queue: .main) { [weak self] _ in
            self?.syncBusy()
        })
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        // Bindings may have changed elsewhere (Gestures › Set Up…); then ask the mice again.
        reload()
        deviceSource.refresh()
        syncBusy()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        problemPopover?.close()
        problemPopover = nil
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        recordedFocusWork?.cancel()
        recordingWatchdog?.cancel()
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
        let old = rows
        rows = buttonBindings.map { binding in
            let title = ButtonTriggerNaming.title(for: binding.triggerEvent)
            let note = note(for: binding)
            if let existing = old.first(where: { $0.id == AnyHashable(binding.id) }) {
                existing.update(binding: binding, title: title, note: note)
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
        let row = ButtonBindingRow(binding: binding, title: title, note: note, pullDown: pullDown)
        row.infoButton.target = self
        row.infoButton.action = #selector(infoClicked(_:))
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

    // MARK: - Removing, with Undo

    var undoTarget: UndoManager? {
        return paneUndoManager ?? view.window?.undoManager
    }

    /// Removes the binding; the window's Undo ("Undo Remove Button") puts it back.
    func removeBinding(id: UUID) {
        guard let index = buttonBindings.firstIndex(where: { $0.id == id }) else { return }
        let removed = buttonBindings.remove(at: index)
        save()
        reloadRows()
        updateHeader()
        if let undo = undoTarget {
            undo.registerUndo(withTarget: self) { controller in
                controller.restoreBinding(removed, at: index)
            }
            undo.setActionName(text("buttons-undo-remove"))
        }
    }

    /// Puts a removed binding back where it was and selects it (Undo). Redo removes it again.
    func restoreBinding(_ binding: ButtonBinding, at index: Int) {
        if let existing = buttonBindings.first(where: { $0.triggerEvent == binding.triggerEvent }) {
            // Recorded again meanwhile: the new one stays.
            list.select(existing.id)
            return
        }
        buttonBindings.insert(binding, at: min(max(0, index), buttonBindings.count))
        save()
        reloadRows()
        list.select(binding.id)
        updateHeader()
        if let undo = undoTarget {
            undo.registerUndo(withTarget: self) { controller in
                controller.removeBinding(id: binding.id)
            }
            undo.setActionName(text("buttons-undo-remove"))
        }
    }

    // MARK: - Adding

    /// "+": records a button, or a key with a modifier. A new one is added without an
    /// action, selected, and its menu opens; with `action` (Gestures › Set Up…) it gets
    /// that action instead.
    func beginAddingBinding(action: SystemShortcut.Shortcut? = nil) {
        _ = view
        guard !isRecording else { return }
        pendingAction = action
        pendingRecorded = nil
        let anchor = list.addButton
        if let startRecording {
            startRecording(anchor)
        } else {
            recorder.startRecording(from: anchor, mode: .combination)
        }
        // The recorder stops itself after its timeout; one that never started says nothing.
        recordingWatchdog?.cancel()
        let watchdog = DispatchWorkItem { [weak self] in
            guard let self, self.isRecording else { return }
            self.isRecording = false
            self.pendingAction = nil
            self.updateHeader()
        }
        recordingWatchdog = watchdog
        DispatchQueue.main.asyncAfter(deadline: .now() + KeyRecorder.TIMEOUT + 1, execute: watchdog)
    }

    private func normalizedTrigger(for event: InputEvent) -> RecordedEvent {
        let recorded = RecordedEvent(from: event)
        let diagnosis = LogiCenter.shared.buttonCaptureDiagnosis(forMosCode: event.code)
        return recorded.normalizedForButtonBinding(diagnosis: diagnosis)
    }

    /// Adds `trigger` (or selects and flashes the binding it already has) and returns the id.
    @discardableResult
    func addBinding(for trigger: RecordedEvent, action: SystemShortcut.Shortcut?) -> UUID {
        if let existing = buttonBindings.first(where: { $0.triggerEvent == trigger }) {
            list.flash(existing.id)
            return existing.id
        }
        let binding = ButtonBinding(
            triggerEvent: trigger,
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
        let popover = OpenTargetConfigPopover()
        currentOpenTargetPopover = popover
        popover.onCommit = { [weak self] payload in
            self?.setAction(of: id, toOpen: payload)
            self?.currentOpenTargetPopover = nil
        }
        popover.onCancel = { [weak self] in
            self?.currentOpenTargetPopover = nil
        }
        popover.show(at: row.pullDown, existing: binding.openTarget)
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
        headerView.content = ButtonsHeaderContent.make(
            deviceName: deviceSource.deviceName(),
            boundCount: bound,
            isRecording: isRecording,
            focus: focus
        )
    }

    func focus(for binding: ButtonBinding) -> ButtonsHeaderContent.Focus {
        return ButtonsHeaderContent.Focus(
            title: ButtonTriggerNaming.title(for: binding.triggerEvent),
            action: resolver.actionName(of: binding),
            part: ButtonsMousePart.part(for: binding.triggerEvent)
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
        updateHeader()
    }

    /// A trigger that is already in the list counts as a duplicate: the recorder says so.
    func validateRecordedEvent(_ recorder: KeyRecorder, event: InputEvent) -> Bool {
        let trigger = normalizedTrigger(for: event)
        return !buttonBindings.contains { $0.triggerEvent == trigger }
    }

    /// The card shows the button at once; a duplicate's row flashes while the recorder
    /// says "Duplicate key". A new one is added when the recorder closes.
    func onEventRecorded(_ recorder: KeyRecorder, didRecordEvent event: InputEvent, isDuplicate: Bool) {
        let trigger = normalizedTrigger(for: event)
        isRecording = false
        if let existing = buttonBindings.first(where: { $0.triggerEvent == trigger }) {
            pendingRecorded = nil
            list.flash(existing.id)
            showRecorded(focus(for: existing))
            return
        }
        pendingRecorded = trigger
        showRecorded(ButtonsHeaderContent.Focus(
            title: ButtonTriggerNaming.title(for: trigger),
            action: pendingAction.map(\.localizedName),
            part: ButtonsMousePart.part(for: trigger)
        ))
    }

    func onRecordingStopped(_ recorder: KeyRecorder, didRecord: Bool) {
        recordingWatchdog?.cancel()
        recordingWatchdog = nil
        isRecording = false
        let action = pendingAction
        pendingAction = nil
        defer { updateHeader() }
        guard didRecord, let trigger = pendingRecorded else { return }
        pendingRecorded = nil
        let id = addBinding(for: trigger, action: action)
        updateHeader()
        guard action == nil else { return }
        // The recorder's popover is gone: the new button's menu opens by itself.
        DispatchQueue.main.async { [weak self] in
            guard let self, let row = self.row(for: id), self.list.selectedID == AnyHashable(id) else { return }
            self.openActionMenu(row.pullDown)
        }
    }
}
