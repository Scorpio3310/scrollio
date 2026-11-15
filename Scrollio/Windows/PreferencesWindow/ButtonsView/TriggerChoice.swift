//
//  TriggerChoice.swift
//  Scrollio
//
//  The pull-down of the Gestures pane's "Button to hold" and of the Shortcut Ring pane's
//  "Button or key": the button that runs the gestures (or opens the ring) is chosen where
//  the pane names it, without a trip to Buttons. Both panes have the same one
//  (`TriggerChooser`, made for their `ApplicationTriggerRule`).
//
//  Its title is what does it now, as the row names it ("Gesture button"), "Choose" while
//  nothing of Buttons does it, "Multiple" while two or more do. Its menu: the buttons of
//  the connected mouse in the order they sit on it (`ButtonsListLayout`, the rows of the
//  Buttons pane), each with what it does now in grey ("Back button — Copy, will be
//  replaced"; without an action what a press does (`ButtonDefaultOutcome`): "Default
//  (Back), will be replaced" where what it then does is certain, another row's action that
//  a press runs ("Mission Control, will be replaced"), else what Buttons says, "Default"
//  or "No Action"; the one that does it is ticked); then
//  "Record a Button…" (the ring: "Record a Button or Key…"), the recorder's popover at the
//  pull-down, which says what the caught button or key loses ("Replaces: Copy",
//  `TriggerChoiceMenu.replaced`); then "Show in Buttons", which says where it goes: "Show in Notes › Buttons" while only
//  an app's own button or key does it, since it then shows that app's Buttons part. While
//  two or more of Buttons' buttons or keys do it, the menu offers "Show in Buttons" only:
//  which one to keep is decided there.
//
//  Buttons stays the one place a button's action is stored: a choice writes the binding
//  that pane writes for that row (an action for a button of the mouse that has none, the
//  action replaced on one that has one) and takes the binding that did it until then
//  away, as "Default" (or "−") there would, so that one button does it, as the title says.
//  Edit › Undo ("Undo Change Button to Hold", "Undo Change What Opens the Ring") puts back
//  exactly the bindings the choice changed, by their ids, on the settings themselves
//  (`Options.shared` is the target), so it works while another pane shows, and a change
//  made in between to another binding stays.
//

import Cocoa

extension ApplicationTriggerRule {
    /// The action a binding has that does it.
    var action: SystemShortcut.Shortcut {
        switch self {
        case .shortcutRing: return SystemShortcut.shortcutRing
        case .gestureNavigation: return SystemShortcut.mouseGestureNavigation
        }
    }
}

/// What the pull-down shows and offers (see the file header). Pure.
struct TriggerChoiceMenu: Equatable {

    /// A button of the connected mouse.
    struct Item: Equatable {
        let part: ButtonsMousePart
        /// What is stored for it when it is chosen: the trigger of its row in Buttons.
        let trigger: RecordedEvent
        /// As Buttons names its row ("Back button").
        let title: String
        /// What it does now, as Buttons names the action; nil: nothing of its own ("Default").
        let action: String?
        /// It does it now.
        let isChosen: Bool
        /// Without an action: what a press does (`ButtonDefaultOutcome`).
        var defaultOutcome: ButtonDefaultOutcome = .passes(nil)
        /// The action of another row that a press runs (`defaultOutcome` is `.runs`), as
        /// Buttons names it.
        var runsAction: String? = nil

        /// Without an action: what "Default" does, where that is certain ("Default (Back)").
        var defaultEffect: ButtonsMousePart? {
            return defaultOutcome.effect
        }

        /// Choosing it replaces an action it has, one a press runs, or what "Default"
        /// certainly does.
        var replacesAction: Bool {
            return (action != nil || runsAction != nil || defaultEffect != nil) && !isChosen
        }

        /// What it does now: "Copy", "Mission Control" (another row's, which a press runs),
        /// "Default (Back)", "No Action".
        var shownAction: String {
            return action ?? runsAction ?? defaultOutcome.title
        }
    }

    enum Title: Equatable {
        /// Nothing of Buttons does it.
        case choose
        /// One button or key does it, named as the row names it.
        case trigger(String)
        /// Two or more do it.
        case several
    }

    let title: Title
    /// Empty while `title` is `.several`.
    let items: [Item]

    /// Buttons can be chosen here (else only "Show in Buttons").
    var offersChoice: Bool {
        return title != .several
    }

    /// - Parameters:
    ///   - triggerTitles: what the pane's row names as doing it (each once).
    ///   - bindings: Buttons' bindings, as stored.
    ///   - mouse: the drawing of the connected mouse.
    ///   - recordedTrigger: what "+" of Buttons records for a button of the mouse.
    ///   - actionName: what Buttons calls a binding's action.
    ///   - holdKeys: the keys of While you hold a key the mouse is asked for
    ///     (`ButtonDefaultOutcome.holdKeysThatCatch`).
    static func make(
        rule: ApplicationTriggerRule,
        triggerTitles: [String],
        bindings: [ButtonBinding],
        mouse: MouseArtworkModel,
        recordedTrigger: (ButtonsMousePart) -> RecordedEvent,
        actionName: (ButtonBinding) -> String?,
        holdKeys: [ScrollHotkey] = [],
        logitechRole: @escaping (UInt16) -> LogiControlRole? = { LogiCenter.shared.controlRole(forScrollioCode: $0) },
        titles: ([RecordedEvent]) -> [String] = { ButtonTriggerNaming.titles(for: $0) },
        title: (RecordedEvent) -> String = { ButtonTriggerNaming.title(for: $0) }
    ) -> TriggerChoiceMenu {
        guard triggerTitles.count < 2 else { return TriggerChoiceMenu(title: .several, items: []) }
        let layout = ButtonsListLayout.make(bindings: bindings, mouse: mouse, logitechRole: logitechRole)
        let names = Dictionary(
            zip(bindings.map(\.id), titles(bindings.map(\.triggerEvent))), uniquingKeysWith: { first, _ in first }
        )
        let items = layout.partRows.compactMap { row -> Item? in
            let trigger = row.binding?.triggerEvent
                ?? TriggerChoiceEdit.defaultTrigger(for: row.part, in: bindings, recordedTrigger: recordedTrigger)
            guard ButtonUtils.isRunnable(trigger) else { return nil }
            let action = row.binding.flatMap { CellActionState(binding: $0).hasBoundAction ? actionName($0) : nil }
            let outcome = action != nil ? .passes(nil) : ButtonDefaultOutcome.of(
                trigger, part: row.part, bindings: bindings, holdKeys: holdKeys, logitechRole: logitechRole
            )
            var runs: String?
            if case .runs(let other) = outcome {
                runs = actionName(other)
            }
            return Item(
                part: row.part,
                trigger: trigger,
                title: row.binding.flatMap { names[$0.id] } ?? title(trigger),
                action: action,
                isChosen: row.binding.map(rule.takes) ?? false,
                defaultOutcome: outcome,
                runsAction: runs
            )
        }
        return TriggerChoiceMenu(title: triggerTitles.first.map(Title.trigger) ?? .choose, items: items)
    }

    /// What choosing `trigger` (a button or key "Record a Button…" caught) takes the place
    /// of, named as the menu names it: the action of the binding it gets ("Copy"), the
    /// action of another binding a press of it runs now ("Mission Control"), or what
    /// "Default" certainly does there ("Default (Back)"). Nil when it does it already, when
    /// nothing certain is lost (a press that does nothing loses nothing), and when it
    /// cannot be chosen.
    static func replaced(
        by trigger: RecordedEvent,
        rule: ApplicationTriggerRule,
        bindings: [ButtonBinding],
        mouse: MouseArtworkModel,
        actionName: (ButtonBinding) -> String?,
        holdKeys: [ScrollHotkey] = [],
        logitechRole: @escaping (UInt16) -> LogiControlRole? = { LogiCenter.shared.controlRole(forScrollioCode: $0) }
    ) -> String? {
        if rule == .gestureNavigation, trigger.type != .mouse { return nil }
        guard ButtonUtils.isRunnable(trigger) else { return nil }
        let trigger = TriggerChoiceEdit.placedLikeItsButton(trigger, in: bindings)
        let layout = ButtonsListLayout.make(bindings: bindings, mouse: mouse, logitechRole: logitechRole)
        // The binding that gets the action, as `TriggerChoiceEdit.choosing` finds it.
        let part = layout.part(for: trigger, logitechRole: logitechRole)
        let existing: ButtonBinding?
        if let part {
            existing = layout.row(of: part)?.binding
        } else {
            existing = bindings.first { $0.triggerEvent == trigger }
        }
        if let existing, CellActionState(binding: existing).hasBoundAction {
            return rule.takes(existing) ? nil : actionName(existing)
        }
        switch ButtonDefaultOutcome.of(trigger, part: part, bindings: bindings, holdKeys: holdKeys, logitechRole: logitechRole) {
        case .runs(let other):
            return rule.takes(other) ? nil : actionName(other)
        case .passes(let effect):
            return effect.map { ButtonsMousePart.defaultTitle(effect: $0) }
        case .caught:
            return nil
        }
    }
}

/// What a choice writes into Buttons' bindings (see the file header). Pure.
enum TriggerChoiceEdit {

    /// What a button of the mouse without a binding stores once it gets an action, as
    /// Buttons has it: a numbered button said to be that part, else what "+" records for it.
    static func defaultTrigger(
        for part: ButtonsMousePart, in bindings: [ButtonBinding], recordedTrigger: (ButtonsMousePart) -> RecordedEvent
    ) -> RecordedEvent {
        if let placed = bindings.first(where: { $0.triggerEvent.placedPart?.drawingPart == part })?.triggerEvent {
            return RecordedEvent(type: .mouse, code: placed.code, modifiers: 0, deviceFilter: nil, mousePart: placed.mousePart)
        }
        return recordedTrigger(part)
    }

    /// `trigger` placed as the bindings of its button number are (the same button with
    /// other modifiers), as Buttons places a button it adds.
    static func placedLikeItsButton(_ trigger: RecordedEvent, in bindings: [ButtonBinding]) -> RecordedEvent {
        guard ButtonTriggerPicture.number(for: trigger) != nil,
              let sibling = bindings.first(where: { $0.triggerEvent.type == .mouse && $0.triggerEvent.code == trigger.code })
        else { return trigger }
        let part = sibling.triggerEvent.mousePart
        return trigger.mousePart == part ? trigger : trigger.placed(at: part)
    }

    /// The bindings once `trigger` does what `rule` does: the binding of its row in Buttons
    /// (a button of the shown mouse pressed without modifiers), else the one stored for it,
    /// gets the action, or a new one is added at the end; every other binding that did it
    /// goes. nil when nothing changes, and for a key while it is the gestures' (a key
    /// cannot be held while the mouse moves).
    static func choosing(
        _ trigger: RecordedEvent,
        for rule: ApplicationTriggerRule,
        in bindings: [ButtonBinding],
        mouse: MouseArtworkModel,
        logitechRole: @escaping (UInt16) -> LogiControlRole? = { LogiCenter.shared.controlRole(forScrollioCode: $0) }
    ) -> [ButtonBinding]? {
        if rule == .gestureNavigation, trigger.type != .mouse { return nil }
        guard ButtonUtils.isRunnable(trigger) else { return nil }
        let trigger = placedLikeItsButton(trigger, in: bindings)
        let layout = ButtonsListLayout.make(bindings: bindings, mouse: mouse, logitechRole: logitechRole)
        let existing: ButtonBinding?
        if let part = layout.part(for: trigger, logitechRole: logitechRole) {
            existing = layout.row(of: part)?.binding
        } else {
            existing = bindings.first { $0.triggerEvent == trigger }
        }
        let action = rule.action.identifier
        var result: [ButtonBinding] = []
        for binding in bindings {
            if binding.id == existing?.id {
                result.append(rule.takes(binding) ? binding : ButtonBinding(
                    id: binding.id, triggerEvent: binding.triggerEvent, systemShortcutName: action,
                    isEnabled: true, createdAt: binding.createdAt
                ))
            } else if !rule.takes(binding) {
                result.append(binding)
            }
        }
        if existing == nil {
            result.append(ButtonBinding(triggerEvent: trigger, systemShortcutName: action, isEnabled: true))
        }
        return result == bindings ? nil : result
    }
}

/// What one change of the bindings did, by their ids: applied again on whatever the
/// bindings are by then (Redo), or the other way round (Undo, `inverse`), it touches only
/// those bindings. Pure.
struct ButtonBindingsPatch: Equatable {

    struct Placed: Equatable {
        let index: Int
        let binding: ButtonBinding
    }

    struct Changed: Equatable {
        let old: ButtonBinding
        let new: ButtonBinding
    }

    let removed: [Placed]
    let inserted: [Placed]
    let changed: [Changed]

    /// The change from `before` to `after`.
    init(from before: [ButtonBinding], to after: [ButtonBinding]) {
        let beforeIDs = Set(before.map(\.id))
        let afterIDs = Set(after.map(\.id))
        removed = before.enumerated().filter { !afterIDs.contains($0.element.id) }.map { Placed(index: $0.offset, binding: $0.element) }
        inserted = after.enumerated().filter { !beforeIDs.contains($0.element.id) }.map { Placed(index: $0.offset, binding: $0.element) }
        changed = after.compactMap { new in
            guard let old = before.first(where: { $0.id == new.id }), old != new else { return nil }
            return Changed(old: old, new: new)
        }
    }

    private init(removed: [Placed], inserted: [Placed], changed: [Changed]) {
        self.removed = removed
        self.inserted = inserted
        self.changed = changed
    }

    /// The change back.
    var inverse: ButtonBindingsPatch {
        return ButtonBindingsPatch(removed: inserted, inserted: removed, changed: changed.map { Changed(old: $0.new, new: $0.old) })
    }

    var isEmpty: Bool {
        return removed.isEmpty && inserted.isEmpty && changed.isEmpty
    }

    /// `bindings` with the change: a changed binding that is still there is replaced, a
    /// removed one goes, an inserted one comes back at its place (not when a binding of the
    /// same trigger was added meanwhile: that one stays, as Buttons' Undo of a removal
    /// keeps it).
    func applied(to bindings: [ButtonBinding]) -> [ButtonBinding] {
        var result = bindings.map { binding in
            changed.first(where: { $0.old.id == binding.id })?.new ?? binding
        }
        let removedIDs = Set(removed.map(\.binding.id))
        result.removeAll { removedIDs.contains($0.id) }
        for placed in inserted.sorted(by: { $0.index < $1.index }) {
            guard !result.contains(where: { $0.id == placed.binding.id || $0.triggerEvent == placed.binding.triggerEvent }) else { continue }
            result.insert(placed.binding, at: min(max(0, placed.index), result.count))
        }
        return result
    }
}

/// The pull-down and what it does, for one pane (see the file header).
final class TriggerChooser: NSObject, NSMenuDelegate, KeyRecorderDelegate {

    enum Identifier {
        static let record = NSUserInterfaceItemIdentifier("trigger-choice-record")
        static let showInButtons = NSUserInterfaceItemIdentifier("trigger-choice-show-in-buttons")

        static func item(_ part: ButtonsMousePart) -> NSUserInterfaceItemIdentifier {
            return NSUserInterfaceItemIdentifier("trigger-choice-\(part)")
        }
    }

    let rule: ApplicationTriggerRule
    let pullDown: TriggerChoicePullDown

    // MARK: Seams (the panes, tests and pictures replace them)

    /// The connected mouse, as the Buttons pane reads it.
    var deviceSource: ButtonsDeviceSource = .live
    /// Buttons' bindings, read and written.
    var bindings: () -> [ButtonBinding] = { Options.shared.buttons.binding }
    /// Every key of While you hold a key the mouse is asked for: a Logitech one keeps its
    /// button with Scrollio.
    var holdKeys: () -> [ScrollHotkey] = { ButtonDefaultOutcome.holdKeysThatCatch() }
    var store: ([ButtonBinding]) -> Void = { Options.shared.buttons.binding = $0 }
    /// Takes Undo and Redo of a choice.
    var undoManager: () -> UndoManager? = { nil }
    /// "Show in Buttons" (the pane knows where).
    var showInButtons: () -> Void = {}
    /// A choice, or its Undo or Redo, changed the bindings: the pane shows them.
    var didChange: () -> Void = {}
    /// An Undo or Redo of a choice ran, maybe while another pane shows: the pane comes
    /// forward, so that it shows where it acts. Not called for the choice itself.
    var comeForward: () -> Void = {}
    /// Starts recording at the pull-down. nil: the real recorder, which taps the system's
    /// events; tests never use it.
    var startRecording: ((NSView) -> Void)?
    /// Ends a recording that is still open. nil: the real recorder.
    var stopRecording: (() -> Void)?

    // MARK: State

    /// What the pane's row names as doing it.
    private(set) var triggerTitles: [String] = []
    /// The app whose Buttons part "Show in Buttons" shows (only its own button or key does
    /// it): the item says "Show in <app> › Buttons". nil: the Buttons pane.
    private(set) var showsInApplication: String?
    /// What the menu shows, as last built.
    private(set) var menuModel = TriggerChoiceMenu(title: .choose, items: [])
    /// The recorder of "Record a Button…" is open.
    private(set) var isRecorderOpen = false
    /// What the recorder caught, kept until it closes.
    private var pendingRecorded: RecordedEvent?
    private lazy var recorder: KeyRecorder = {
        let recorder = KeyRecorder()
        recorder.delegate = self
        return recorder
    }()
    private let resolver = ActionDisplayResolver()

    init(rule: ApplicationTriggerRule) {
        self.rule = rule
        pullDown = TriggerChoicePullDown()
        super.init()
        rebuildMenu()
    }

    /// The pane's row now names `titles` as doing it: the title and the menu follow.
    /// `application`: "Show in Buttons" shows that app's Buttons part (`showsInApplication`).
    func update(triggerTitles titles: [String], showsInApplication application: String? = nil) {
        triggerTitles = titles
        showsInApplication = application
        rebuildMenu()
    }

    /// The pane goes away: an open recorder closes, and nothing is chosen.
    func endEditing() {
        guard isRecorderOpen else { return }
        pendingRecorded = nil
        if let stopRecording {
            stopRecording()
        } else {
            recorder.stopRecording()
        }
    }

    // MARK: The menu

    private var mouse: MouseArtworkModel {
        return MouseArtworkModel.model(forDeviceName: deviceSource.deviceName())
    }

    private func text(_ key: String) -> String {
        return NSLocalizedString(key, comment: "")
    }

    var titleText: String {
        switch menuModel.title {
        case .choose: return text("buttons-trigger-choice-choose")
        case .trigger(let name): return name
        case .several: return text("buttons-trigger-choice-several")
        }
    }

    /// The menu as things are now. Built again each time it opens: a button may have got
    /// another action under Buttons, or the mouse changed.
    func rebuildMenu() {
        menuModel = TriggerChoiceMenu.make(
            rule: rule,
            triggerTitles: triggerTitles,
            bindings: bindings(),
            mouse: mouse,
            recordedTrigger: deviceSource.recordedTrigger,
            actionName: { [resolver] in resolver.actionName(of: $0) },
            holdKeys: holdKeys()
        )
        let menu = pullDown.menu ?? NSMenu()
        menu.removeAllItems()
        menu.delegate = self
        menu.autoenablesItems = false
        // Item 0 is a pull-down's title.
        menu.addItem(NSMenuItem(title: titleText, action: nil, keyEquivalent: ""))
        if menuModel.offersChoice {
            if !menuModel.items.isEmpty {
                menu.addItem(NSMenuItem.sectionHeader(title: text("buttons-trigger-choice-mouse")))
                for item in menuModel.items {
                    menu.addItem(menuItem(for: item))
                }
                menu.addItem(.separator())
            }
            let record = NSMenuItem(
                title: text(rule == .shortcutRing ? "ring-trigger-choice-record" : "gestures-trigger-choice-record"),
                action: #selector(recordChosen(_:)), keyEquivalent: ""
            )
            record.target = self
            record.identifier = Identifier.record
            menu.addItem(record)
            menu.addItem(.separator())
        }
        let showTitle = ButtonActionPullDown.showInTitle(
            paneKey: "buttons-trigger-choice-show", part: .buttons, application: showsInApplication
        )
        let show = NSMenuItem(title: showTitle, action: #selector(showChosen(_:)), keyEquivalent: "")
        show.target = self
        show.identifier = Identifier.showInButtons
        menu.addItem(show)
        if pullDown.menu !== menu {
            pullDown.menu = menu
        }
        pullDown.titleDidChange()
    }

    /// "Back button — Copy, will be replaced": the name, then what it does now in grey
    /// ("Default (Back), will be replaced", "Default"). The one that does it is ticked. The
    /// plain title holds both, for VoiceOver.
    private func menuItem(for item: TriggerChoiceMenu.Item) -> NSMenuItem {
        let shown = item.shownAction
        let detail = item.replacesAction ? String(format: text("buttons-trigger-choice-replaced"), shown) : shown
        let plain = String(format: text("buttons-trigger-choice-item"), item.title, detail)
        let menuItem = NSMenuItem(title: plain, action: #selector(partChosen(_:)), keyEquivalent: "")
        menuItem.target = self
        menuItem.identifier = Identifier.item(item.part)
        menuItem.representedObject = item.trigger
        menuItem.state = item.isChosen ? .on : .off
        let font = NSFont.menuFont(ofSize: 0)
        let title = NSMutableAttributedString(string: plain, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
        if let range = plain.range(of: item.title) {
            let rest = NSRange(range.upperBound..<plain.endIndex, in: plain)
            title.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: rest)
        }
        menuItem.attributedTitle = title
        return menuItem
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    @objc func partChosen(_ sender: NSMenuItem) {
        guard let trigger = sender.representedObject as? RecordedEvent else { return }
        choose(trigger)
    }

    @objc func showChosen(_ sender: NSMenuItem) {
        showInButtons()
    }

    /// "Record a Button…": the recorder's popover at the pull-down, once the menu is gone.
    @objc func recordChosen(_ sender: NSMenuItem) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.beginRecording()
        }
    }

    func beginRecording() {
        guard !isRecorderOpen else { return }
        pendingRecorded = nil
        if let startRecording {
            startRecording(pullDown)
        } else {
            guard pullDown.window != nil else { return }
            recorder.startRecording(from: pullDown, mode: .combination)
        }
    }

    // MARK: Choosing, with Undo

    /// `trigger` does it from now on (see `TriggerChoiceEdit.choosing`), with Undo.
    func choose(_ trigger: RecordedEvent) {
        let before = bindings()
        guard let after = TriggerChoiceEdit.choosing(trigger, for: rule, in: before, mouse: mouse) else { return }
        store(after)
        let patch = ButtonBindingsPatch(from: before, to: after)
        if let added = patch.inserted.first?.binding.triggerEvent, added.type == .mouse,
           deviceSource.captureStatus(added.code) == .bleHIDPPUnstable {
            deviceSource.warnBluetoothButton(added.code)
        }
        if let undo = undoManager() {
            let read = bindings
            let write = store
            Self.register(
                patch,
                name: text(rule == .shortcutRing ? "ring-undo-choose-trigger" : "gestures-undo-choose-button"),
                apply: { write($0.applied(to: read())) },
                comeForward: { [weak self] in self?.comeForward() },
                didChange: { [weak self] in self?.didChange() },
                on: undo
            )
        }
        didChange()
    }

    /// Undo applies `patch`'s inverse to the bindings as they are then, and registers Redo,
    /// which registers Undo again. Nothing of it needs the pane: it works after the pane
    /// went away (the settings are the target). While the pane is there it comes forward
    /// (`comeForward`), with the row that names the trigger: the bindings change, and
    /// nothing else on screen would say so.
    private static func register(
        _ patch: ButtonBindingsPatch,
        name: String,
        apply: @escaping (ButtonBindingsPatch) -> Void,
        comeForward: @escaping () -> Void,
        didChange: @escaping () -> Void,
        on undo: UndoManager
    ) {
        undo.registerUndo(withTarget: Options.shared) { [weak undo] _ in
            apply(patch.inverse)
            comeForward()
            didChange()
            guard let undo else { return }
            register(patch.inverse, name: name, apply: apply, comeForward: comeForward, didChange: didChange, on: undo)
        }
        undo.setActionName(name)
    }

    // MARK: Recording

    private var takesOnlyMouseButtons: Bool {
        return rule == .gestureNavigation
    }

    /// A recorded event as Buttons' "+" stores it.
    private func trigger(of event: InputEvent) -> RecordedEvent {
        let diagnosis = LogiCenter.shared.buttonCaptureDiagnosis(forScrollioCode: event.code)
        return TriggerChoiceEdit.placedLikeItsButton(
            RecordedEvent(from: event).normalizedForButtonBinding(diagnosis: diagnosis), in: bindings()
        )
    }

    func onRecordingStarted(_ recorder: KeyRecorder) {
        isRecorderOpen = true
    }

    /// A key cannot be the gesture button: refused, and the recorder says why.
    func validateRecordedEvent(_ recorder: KeyRecorder, event: InputEvent) -> Bool {
        return !(takesOnlyMouseButtons && trigger(of: event).type == .keyboard)
    }

    func refusalHint(_ recorder: KeyRecorder, event: InputEvent) -> String? {
        guard takesOnlyMouseButtons, trigger(of: event).type == .keyboard else { return nil }
        return text("buttons-gesture-needs-mouse-button")
    }

    func waitingHint(_ recorder: KeyRecorder, mode: KeyRecordingMode) -> String? {
        return takesOnlyMouseButtons ? text("buttons-recorder-waiting-gesture") : nil
    }

    func onEventRecorded(_ recorder: KeyRecorder, didRecordEvent event: InputEvent, isDuplicate: Bool) {
        pendingRecorded = isDuplicate ? nil : trigger(of: event)
    }

    /// While the popover shows the caught button or key: what it loses, in the menu's
    /// words ("Replaces: Copy"), as the menu says "will be replaced" for the same choice.
    func recordedNote(_ recorder: KeyRecorder, event: InputEvent) -> String? {
        return replacedNote(for: trigger(of: event))
    }

    /// "Replaces: Copy" for a choice of `trigger`; nil when it loses nothing certain.
    func replacedNote(for trigger: RecordedEvent) -> String? {
        let replaced = TriggerChoiceMenu.replaced(
            by: trigger, rule: rule, bindings: bindings(), mouse: mouse,
            actionName: { [resolver] in resolver.actionName(of: $0) },
            holdKeys: holdKeys()
        )
        return replaced.map { String(format: text("buttons-trigger-choice-recorded-replaces"), $0) }
    }

    /// The recorder closed, however: what it caught is chosen now.
    func onRecordingStopped(_ recorder: KeyRecorder, didRecord: Bool) {
        isRecorderOpen = false
        let caught = pendingRecorded
        pendingRecorded = nil
        guard didRecord, let caught else { return }
        choose(caught)
    }
}

/// The pull-down: as wide as its title (its menu is wider, with what each button does), up
/// to `maxWidth`: a longer title is cut short at its end, the whole of it in the tooltip, so
/// that the row's line always has room beside it.
final class TriggerChoicePullDown: NSPopUpButton {

    /// The widest the pull-down gets. Every name of a button fits whole, with a modifier
    /// key or two before it ("Gesture button (button 6)" is 204 pt wide); beside it a row's
    /// short line ("Hold it, move towards a shortcut and let go.") still takes two lines.
    static let maxWidth: CGFloat = 240

    init() {
        super.init(frame: .zero, pullsDown: true)
        translatesAutoresizingMaskIntoConstraints = false
        cell?.lineBreakMode = .byTruncatingTail
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        fatalError("TriggerChoicePullDown is built in code")
    }

    /// What it shows: its menu's first item.
    var shownTitle: String {
        return menu?.items.first?.title ?? ""
    }

    /// Item 0 changed: shown, and the width follows. A title too long for the pull-down
    /// is whole in the tooltip.
    func titleDidChange() {
        synchronizeTitleAndSelectedItem()
        invalidateIntrinsicContentSize()
        toolTip = titleWidth > Self.maxWidth ? shownTitle : nil
    }

    /// How wide the pull-down would be with its title whole: a cell with the title alone.
    private var titleWidth: CGFloat {
        let probe = NSPopUpButtonCell(textCell: "", pullsDown: true)
        probe.font = font
        probe.controlSize = controlSize
        probe.addItem(withTitle: shownTitle)
        return ceil(probe.cellSize.width)
    }

    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(width: min(titleWidth, Self.maxWidth), height: size.height)
    }
}
