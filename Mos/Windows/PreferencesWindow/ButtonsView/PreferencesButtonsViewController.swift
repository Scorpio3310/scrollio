//
//  PreferencesButtonsViewController.swift
//  Mos
//  "Buttons" preferences pane, built in code on the grouped kit like Scrolling, Gestures and
//  Mouse; the storyboard scene is a shell. On top a card with the mouse whose button the
//  pane is about lit up, then the list of buttons (PreferencesListBox): each row shows
//  where the button is in a small picture, names the button, says what its action needs or
//  what is wrong with it, and has the action pull-down. With an MX Master connected the
//  list starts with every button of that mouse (ButtonsListLayout), whether or not it has
//  an action: one without reads "Default", and choosing an action stores its binding,
//  choosing "Default" removes it. Every other binding follows under "Other buttons and
//  keys", where "+" and "−" work as they always did. A button the drawing cannot show
//  ("Button 5") is found by asking the mouse: "+" and pressing it makes the card say
//  "That's Button 5"; a click on its picture then says where it is ("Which Button Is
//  This?"), and from then on it is named and lit as that part. "+" records a button (or a
//  key with a modifier), "−" removes one, and the window's Undo puts it back. Only
//  Options.shared.buttons.binding is edited, in the format it always had; a placed button
//  adds the trigger's optional `mousePart`. The one row that is no button, the MX Master's
//  thumb wheel (after the mode shift button), edits what the sideways wheel does instead
//  (Options.shared.thumbWheel, as Scrolling › Thumb wheel does) and never a binding.
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
    /// What "+" records for a button of the connected mouse pressed without modifiers
    /// (`ButtonsMousePart.recordedTrigger`). Reads only.
    var recordedTrigger: (ButtonsMousePart) -> RecordedEvent = { $0.recordedTrigger() }

    static let live = ButtonsDeviceSource(
        captureStatus: { code in
            guard LogiCenter.shared.isLogiCode(code) else { return .normal }
            return ButtonCapturePresentationStatus.from(LogiCenter.shared.buttonCaptureDiagnosis(forMosCode: code))
        },
        // The mouse the Mouse pane's card is about, so the two cards never name different mice.
        deviceName: { MousePaneModel.shownMouse()?.deviceName },
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
    /// The rows: the connected mouse's buttons, then every other binding.
    private(set) var layout = ButtonsListLayout(partRows: [], others: [])
    /// The trigger each button of the mouse last had while the pane showed this mouse: set to
    /// "Default" and given an action again, it gets it back. Kept in memory only.
    private var lastPartTriggers: [ButtonsMousePart: RecordedEvent] = [:]
    private var lastPartTriggersMouse: String?
    /// What a button of the mouse without a binding shows, by part; the same binding (and
    /// id) while its trigger stays.
    private var defaultBindings: [ButtonsMousePart: ButtonBinding] = [:]
    /// The drawing of the connected mouse, on the card and in every row's picture.
    private(set) var mouse: MouseArtworkModel = .generic
    /// The name of the mouse the card was last made for (`deviceSource.deviceName()`).
    private(set) var shownDeviceName: String?
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
    /// Hears of every change of the thumb wheel settings (Scrolling edits them too).
    private var thumbWheelObserver: NSObjectProtocol?

    private let recorder = KeyRecorder()
    private let resolver = ActionDisplayResolver()

    // MARK: - Views (read access for tests)

    private(set) var headerView: ButtonsHeaderView!
    private(set) var list: PreferencesListBox!
    private(set) var busyView: NSStackView!
    private(set) var busySpinner: NSProgressIndicator!
    /// The rows of bindings and of the mouse's buttons, top to bottom (not the thumb wheel's).
    private(set) var rows: [ButtonBindingRow] = []
    /// The thumb wheel's row while the shown mouse has one (`ButtonsListLayout.hasThumbWheel`).
    private(set) var thumbWheelRow: ButtonsThumbWheelRow?
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
            guard let self else { return }
            if id == ButtonsListLayout.thumbWheelRowID, let thumbWheel = self.thumbWheelRow {
                self.openActionMenu(thumbWheel.pullDown)
                return
            }
            guard let row = self.row(for: id) else { return }
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
        // Another mouse connected or the one there left: the drawings and the card's name
        // follow (another mouse may have the same drawing).
        observers.append(center.addObserver(forName: LogiCenter.mouseStateChanged, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            let name = self.deviceSource.deviceName()
            guard MouseArtworkModel.model(forDeviceName: name) != self.mouse || name != self.shownDeviceName else { return }
            self.reloadRows()
            self.updateHeader()
        })
        observers.append(center.addObserver(forName: LogiCenter.activityChanged, object: nil, queue: .main) { [weak self] _ in
            self?.syncBusy()
        })
        // What the thumb wheel does may change under Scrolling while this pane exists.
        thumbWheelObserver = ThumbWheelSettingsChange.addObserver { [weak self] in
            self?.syncThumbWheel()
        }
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
        if let thumbWheelObserver {
            ThumbWheelSettingsChange.removeObserver(thumbWheelObserver)
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

    /// The row with `id` (a binding's id, or a button of the mouse), or the row that shows
    /// the stored binding with that id.
    func row(for id: AnyHashable) -> ButtonBindingRow? {
        return rows.first { $0.id == id } ?? rows.first { $0.isStored && AnyHashable($0.binding.id) == id }
    }

    /// The id of the row that shows the binding with `id`: a button of the mouse has its
    /// part as id, any other binding its own.
    func rowID(forBinding id: UUID) -> AnyHashable {
        return rows.first { $0.binding.id == id }?.id ?? AnyHashable(id)
    }

    /// The stored binding of the row with `id`; nil for a button of the mouse without one.
    func storedBinding(ofRow id: AnyHashable) -> ButtonBinding? {
        if let part = id as? ButtonsMousePart {
            return layout.row(of: part)?.binding
        }
        return (id as? UUID).flatMap(binding(for:))
    }

    /// Puts every binding into its row: first a row for each button of the connected mouse
    /// (with its binding or "Default") and the thumb wheel's, then the other bindings under
    /// their title. The rows still there are updated (a pull-down keeps the keyboard focus),
    /// new ones made, and the list told only when the rows themselves changed.
    func reloadRows() {
        guard let list else { return }
        mouse = connectedMouse()
        layout = ButtonsListLayout.make(bindings: buttonBindings, mouse: mouse)
        rememberPartTriggers()
        let old = rows
        let titles = Dictionary(
            zip(buttonBindings.map(\.id), ButtonTriggerNaming.titles(for: buttonBindings.map(\.triggerEvent))),
            uniquingKeysWith: { first, _ in first }
        )
        var shown: [ButtonBindingRow] = []
        var listed: [PreferencesListRow] = []
        var thumbWheel: ButtonsThumbWheelRow?
        for entry in layout.rows {
            switch entry {
            case .part(let partRow):
                let part = partRow.part
                let binding = partRow.binding ?? defaultBinding(for: part)
                let isStored = partRow.binding != nil
                let title = titles[binding.id] ?? ButtonTriggerNaming.title(for: binding.triggerEvent)
                let note = CellActionState(binding: binding).hasBoundAction
                    ? note(for: binding)
                    : defaultNote(for: part, trigger: binding.triggerEvent)
                let row: ButtonBindingRow
                if let existing = old.first(where: { $0.id == AnyHashable(part) }) {
                    existing.update(binding: binding, title: title, note: note, mouse: mouse, isStored: isStored)
                    row = existing
                } else {
                    row = makeRow(for: binding, title: title, note: note, part: part, isStored: isStored)
                }
                shown.append(row)
                listed.append(row)
            case .thumbWheel:
                let row = thumbWheelRow ?? makeThumbWheelRow()
                row.update(function: Options.shared.thumbWheel.function, mouse: mouse)
                thumbWheel = row
                listed.append(row)
            case .other(let binding):
                let title = titles[binding.id] ?? title(for: binding.triggerEvent)
                let note = note(for: binding)
                let row: ButtonBindingRow
                if let existing = old.first(where: { $0.id == AnyHashable(binding.id) }) {
                    existing.update(binding: binding, title: title, note: note, mouse: mouse)
                    row = existing
                } else {
                    row = makeRow(for: binding, title: title, note: note)
                }
                shown.append(row)
                listed.append(row)
            }
        }
        rows = shown
        thumbWheelRow = thumbWheel
        // "Other buttons and keys" above the first binding under the mouse's buttons.
        var groupTitles: [AnyHashable: String] = [:]
        if !layout.partRows.isEmpty, let first = layout.others.first {
            groupTitles[AnyHashable(first.id)] = text("buttons-list-other")
        }
        if listed.count != list.rows.count || zip(listed, list.rows).contains(where: { $0 !== $1 })
            || Set(list.groupTitles.keys) != Set(groupTitles.keys) {
            list.setRows(listed, groupTitles: groupTitles)
        }
        PreferencesForm.fitToContent(self)
    }

    // MARK: - The thumb wheel

    /// The thumb wheel's row: what it does, as stored. Choosing a function stores it in
    /// Options.shared.thumbWheel (never a binding).
    private func makeThumbWheelRow() -> ButtonsThumbWheelRow {
        let row = ButtonsThumbWheelRow(function: Options.shared.thumbWheel.function, mouse: mouse)
        row.pullDown.onFunctionSelected = { [weak self] function in
            self?.setThumbWheelFunction(function)
        }
        return row
    }

    /// Stores what the thumb wheel does, only when it changes. Both panes then show it
    /// (ThumbWheelSettingsChange); the bindings are not touched.
    func setThumbWheelFunction(_ function: ThumbWheelFunction) {
        if Options.shared.thumbWheel.function != function {
            Options.shared.thumbWheel.function = function
        }
        syncThumbWheel()
    }

    /// The thumb wheel's row (and the card while it is about that row) shows the stored
    /// value. Writes nothing.
    func syncThumbWheel() {
        guard let thumbWheelRow else { return }
        thumbWheelRow.update(function: Options.shared.thumbWheel.function, mouse: mouse)
        updateHeader()
    }

    /// Remembers the trigger of every button of the mouse that has a binding; another mouse
    /// starts afresh.
    private func rememberPartTriggers() {
        let name = deviceSource.deviceName()
        if name != lastPartTriggersMouse {
            lastPartTriggers = [:]
            lastPartTriggersMouse = name
        }
        for partRow in layout.partRows {
            if let binding = partRow.binding {
                lastPartTriggers[partRow.part] = binding.triggerEvent
            }
        }
    }

    /// What a button of the mouse without a binding stores once it gets an action: the
    /// trigger it last had here; else a numbered button the list says is there (that is what
    /// the mouse sends for it on this Mac); else what "+" records for it on this mouse.
    func defaultTrigger(for part: ButtonsMousePart) -> RecordedEvent {
        if let last = lastPartTriggers[part] {
            return last
        }
        if let placed = buttonBindings.first(where: { $0.triggerEvent.placedPart?.drawingPart == part })?.triggerEvent {
            return RecordedEvent(type: .mouse, code: placed.code, modifiers: 0, deviceFilter: nil, mousePart: placed.mousePart)
        }
        return deviceSource.recordedTrigger(part)
    }

    /// The binding a "Default" row shows (not stored, no action), the same one while its
    /// trigger stays.
    private func defaultBinding(for part: ButtonsMousePart) -> ButtonBinding {
        let trigger = defaultTrigger(for: part)
        if let shown = defaultBindings[part], shown.triggerEvent == trigger, shown.triggerEvent.mousePart == trigger.mousePart {
            return shown
        }
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "", isEnabled: false)
        defaultBindings[part] = binding
        return binding
    }

    /// The line of a button of the mouse without an action.
    func defaultNote(for part: ButtonsMousePart, trigger: RecordedEvent) -> ButtonRowNote? {
        return ButtonRowNote.makeDefault(
            for: part,
            trigger: trigger,
            scrollHoldKeys: scrollHoldKeys(),
            isCaught: ButtonsListLayout.catchesControl(of: part, in: buttonBindings)
        )
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

    private func makeRow(
        for binding: ButtonBinding,
        title: String,
        note: ButtonRowNote?,
        part: ButtonsMousePart? = nil,
        isStored: Bool = true
    ) -> ButtonBindingRow {
        let rowID = part.map { AnyHashable($0) } ?? AnyHashable(binding.id)
        let pullDown = ButtonActionPullDown(binding: binding)
        pullDown.onShortcutSelected = { [weak self] shortcut in
            self?.setAction(ofRow: rowID, to: shortcut)
        }
        pullDown.onCustomShortcutRecorded = { [weak self] name in
            self?.setAction(ofRow: rowID, toShortcutNamed: name)
        }
        pullDown.onOpenTargetSelectionRequested = { [weak self] in
            self?.presentOpenTargetPopover(forRow: rowID)
        }
        pullDown.onGestureSettingsRequested = { [weak self] in
            self?.showGesturesPane()
        }
        let row = ButtonBindingRow(binding: binding, title: title, note: note, mouse: mouse, pullDown: pullDown, part: part, isStored: isStored)
        row.infoButton.target = self
        row.infoButton.action = #selector(infoClicked(_:))
        // A button of the mouse shows another binding over time: the one shown now.
        row.onPlaceRequested = { [weak self, weak row] anchor in
            guard let row else { return }
            self?.showPlaceMenu(for: row.binding.id, from: anchor)
        }
        row.placeMenu = { [weak self, weak row] in
            guard let self, let row, let menu = self.placeMenu(for: row.binding.id) else { return nil }
            self.list.select(row.id)
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

    /// The action chosen in the pull-down of the row with `id`. On a button of the mouse
    /// without a binding an action stores one (the trigger the row shows) and "Default"
    /// does nothing; on one with a binding "Default" removes it, with Undo.
    func setAction(ofRow id: AnyHashable, to shortcut: SystemShortcut.Shortcut?) {
        if let stored = storedBinding(ofRow: id) {
            if shortcut == nil, id is ButtonsMousePart {
                removeBinding(id: stored.id)
            } else {
                setAction(of: stored.id, to: shortcut)
            }
            return
        }
        guard let part = id as? ButtonsMousePart else { return }
        guard let shortcut else {
            reloadRows()
            return
        }
        addBinding(toPart: part) { trigger in
            ButtonBinding(triggerEvent: trigger, systemShortcutName: shortcut.identifier, isEnabled: true)
        }
    }

    func setAction(ofRow id: AnyHashable, toShortcutNamed name: String) {
        if let stored = storedBinding(ofRow: id) {
            setAction(of: stored.id, toShortcutNamed: name)
            return
        }
        guard let part = id as? ButtonsMousePart else { return }
        addBinding(toPart: part) { trigger in
            ButtonBinding(triggerEvent: trigger, systemShortcutName: name, isEnabled: true)
        }
    }

    func setAction(ofRow id: AnyHashable, toOpen payload: OpenTargetPayload) {
        if let stored = storedBinding(ofRow: id) {
            setAction(of: stored.id, toOpen: payload)
            return
        }
        guard let part = id as? ButtonsMousePart else { return }
        addBinding(toPart: part) { trigger in
            ButtonBinding(triggerEvent: trigger, openTarget: payload, isEnabled: true)
        }
    }

    /// Stores the binding `make` builds for a button of the mouse that has none, from the
    /// trigger its row shows.
    private func addBinding(toPart part: ButtonsMousePart, _ make: (RecordedEvent) -> ButtonBinding) {
        guard layout.row(of: part)?.binding == nil, let shown = row(for: part)?.binding else { return }
        append(make(placedLikeItsButton(shown.triggerEvent)))
        updateHeader()
    }

    /// Adds `binding` at the end and saves; a Logitech button that may stop working over
    /// Bluetooth warns once.
    private func append(_ binding: ButtonBinding) {
        buttonBindings.append(binding)
        save()
        reloadRows()
        let trigger = binding.triggerEvent
        if trigger.type == .mouse, deviceSource.captureStatus(trigger.code) == .bleHIDPPUnstable {
            deviceSource.warnBluetoothButton(trigger.code)
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
        list.select(rowID(forBinding: id))
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
        // Said to be a button of the mouse, it may move to that button's row (or back): the
        // selection goes with it.
        let wasSelected = list.selectedID != nil && list.selectedID == rowID(forBinding: id)
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
        if wasSelected {
            list.select(rowID(forBinding: id))
        }
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
            list.select(rowID(forBinding: existing.id))
            focusList()
            return
        }
        // Its place as the rows of its button say now (it keeps its own when it is alone).
        let placed = placedLikeItsButton(binding.triggerEvent, except: binding.id)
        let binding = placed.mousePart == binding.triggerEvent.mousePart ? binding : binding.replacingTriggerEvent(placed)
        buttonBindings.insert(binding, at: min(max(0, index), buttonBindings.count))
        save()
        reloadRows()
        list.select(rowID(forBinding: binding.id))
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

    /// The binding the list has for `trigger`, if any. A button of the connected mouse
    /// pressed without modifiers is its row: the row's stored binding, or for a row without
    /// one the binding it shows (no action: it takes the one of Gestures › Set Up…).
    func existingBinding(for trigger: RecordedEvent) -> ButtonBinding? {
        if let part = layout.part(for: trigger), let row = row(for: part) {
            return row.binding
        }
        return buttonBindings.first { $0.triggerEvent == trigger }
    }

    /// A recorded `trigger` that the list has already, and that takes `action` (Gestures ›
    /// Set Up…) because it has no action yet.
    private func takesPendingAction(_ existing: ButtonBinding, action: SystemShortcut.Shortcut?) -> Bool {
        return action != nil && !CellActionState(binding: existing).hasBoundAction
    }

    /// Adds `trigger` and returns the id. A trigger the list has already is selected and
    /// flashes; with `action` and no action of its own it gets `action` (a button of the
    /// mouse without a binding gets one, of what was pressed). The list then has the
    /// keyboard.
    @discardableResult
    func addBinding(for trigger: RecordedEvent, action: SystemShortcut.Shortcut?) -> UUID {
        defer { focusList() }
        if let existing = existingBinding(for: trigger) {
            guard takesPendingAction(existing, action: action) else {
                list.flash(rowID(forBinding: existing.id))
                return existing.id
            }
            if binding(for: existing.id) != nil {
                setAction(of: existing.id, to: action)
                list.select(rowID(forBinding: existing.id))
                return existing.id
            }
        }
        let binding = ButtonBinding(
            triggerEvent: placedLikeItsButton(trigger),
            systemShortcutName: action?.identifier ?? "",
            isEnabled: action != nil
        )
        append(binding)
        list.select(rowID(forBinding: binding.id))
        return binding.id
    }

    // MARK: - Open App or File

    /// "Open App or File" at the pull-down of the row with `id`.
    private func presentOpenTargetPopover(forRow id: AnyHashable) {
        guard let row = row(for: id) else { return }
        openTargetPopover?.hide()
        let popover = OpenTargetConfigPopover()
        openTargetPopover = popover
        popover.onCommit = { [weak self] payload in
            self?.setAction(ofRow: id, toOpen: payload)
            self?.openTargetPopover = nil
        }
        popover.onCancel = { [weak self] in
            self?.openTargetPopover = nil
        }
        presentOpenTarget(popover, row.pullDown, storedBinding(ofRow: id)?.openTarget)
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
        if focus == nil, let id = list.hoveredID ?? list.selectedID {
            if id == ButtonsListLayout.thumbWheelRowID, let thumbWheelRow {
                focus = .thumbWheel(
                    title: thumbWheelRow.title,
                    action: ThumbWheelPresentation.buttonsTitle(for: thumbWheelRow.function)
                )
            } else if let row = row(for: id) {
                focus = self.focus(for: row)
            }
        }
        let bound = buttonBindings.filter { CellActionState(binding: $0).hasBoundAction }.count
        let deviceName = deviceSource.deviceName()
        shownDeviceName = deviceName
        headerView.mouse = mouse
        headerView.content = ButtonsHeaderContent.make(
            deviceName: deviceName,
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
        if let row = rows.first(where: { $0.binding.id == binding.id }) {
            return focus(for: row, reason: reason)
        }
        return ButtonsHeaderContent.Focus(
            title: title(for: binding.triggerEvent),
            action: resolver.actionName(of: binding),
            picture: ButtonTriggerPicture.make(for: binding.triggerEvent, mouse: mouse),
            reason: reason
        )
    }

    /// What the card says about `row`: its title, its action ("Default" for a button of the
    /// mouse without one) and its picture.
    func focus(for row: ButtonBindingRow, reason: ButtonsHeaderContent.Focus.Reason = .row) -> ButtonsHeaderContent.Focus {
        return ButtonsHeaderContent.Focus(
            title: row.title,
            action: row.isDefault ? text("buttons-default") : resolver.actionName(of: row.binding),
            picture: row.picture,
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

    /// What the recorder's popover asks for while it waits: a mouse button only while the
    /// gesture button is set up; nil (the mode's own text) otherwise.
    func waitingHint(_ recorder: KeyRecorder, mode: KeyRecordingMode) -> String? {
        guard Self.needsMouseButton(pendingAction) else { return nil }
        return NSLocalizedString("buttons-recorder-waiting-gesture", comment: "")
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
            list.flash(rowID(forBinding: existing.id))
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
