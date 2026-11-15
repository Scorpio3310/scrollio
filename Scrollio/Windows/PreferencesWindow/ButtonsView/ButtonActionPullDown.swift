//
//  ButtonActionPullDown.swift
//  Mos
//  The action of one button in the Buttons pane: a pull-down 240 pt wide that shows the
//  action as the pull-downs of the Gestures pane do (a symbol and a name), and opens the
//  menu of ShortcutManager. "Open App or File…", "Keyboard Shortcut…" and "Show Gesture
//  Settings" are handed to the pane (or recorded here); every other item binds directly.
//  On every row of Buttons (`offersDefault`) "No Action" is "Default": the button or key
//  keeps doing what it does by itself (a press without an action is passed on), and the
//  pane removes the binding of a button of the connected mouse. Where what it then does is
//  certain the title and the item say it in parentheses, "Default (Back)" (`defaultEffect`,
//  the parenthesis in grey in the title), and the pull-down's tooltip has its sentence
//  ("Goes back in apps that support it.").
//
//  On an app's Buttons part the menu starts with "Same as Other Apps (Mission Control)"
//  (`sameAsOtherAppsTitle`, `onSameAsOtherApps`): the button follows Buttons there again.
//
//  "Keyboard Shortcut…" and a name: a recorded key combination can be called something
//  and given an icon (`ShortcutLabel`). After a recording that caught one, the recorder's
//  popover stays open and shows the name field and the icon choice under the keys
//  (`takesPopover`); on a row that already holds one, "Keyboard Shortcut…" opens that
//  state at once, with "Record Again" for other keys. The keys are stored when they are
//  recorded, as ever; the name and icon when the popover closes, in whatever way.
//  Recording other keys keeps the name and icon; a listed action, a mouse button or an
//  app in their place drops them.
//
//  The rows of the Shortcut Ring pane and of the Gestures pane use it too (`Use`): their
//  menus offer what a place or a direction can hold, and their recorder takes only what a
//  place of the ring can run (a key combination, the Back or the Forward button).
//

import Cocoa

class ButtonActionPullDown: NSPopUpButton, NSMenuDelegate {

    /// What the pull-down chooses for: its menu, and what its recorder takes.
    enum Use: Equatable {
        /// A button's or a key's binding (the Buttons pane): every action.
        case binding
        /// A place of the Shortcut Ring: what a place can hold
        /// (`ShortcutManager.buildShortcutMenu(forRingPlace:)`).
        case ringPlace
        /// A direction or the click of Gesture Navigation: the one-shot actions of the
        /// Gestures pane (`MouseGestureSettingsControls.actionCategories`, with the
        /// Logitech ones while a Logitech button runs the gestures) and "Keyboard Shortcut…".
        case gesture(showsLogiActions: Bool)

        /// The recorder takes only what a place of the ring runs.
        var recordsWhatARingPlaceRuns: Bool {
            return self != .binding
        }
    }

    static let width: CGFloat = 240
    /// Pictures before the title (an app's icon) are drawn this size.
    static let imageSize: CGFloat = 16

    // MARK: Callbacks

    /// A listed action was chosen, or No Action (nil).
    var onShortcutSelected: ((SystemShortcut.Shortcut?) -> Void)?
    /// A keyboard shortcut was recorded: its stored name, and the name and icon it has
    /// (nil: none). Also called when only the name or the icon of the recorded shortcut
    /// changed, with the same stored name.
    var onCustomShortcutRecorded: ((String, ShortcutLabel?) -> Void)?
    /// "Open App or File…" was chosen.
    var onOpenTargetSelectionRequested: (() -> Void)?
    /// "Show Gesture Settings" was chosen.
    var onGestureSettingsRequested: (() -> Void)?
    /// "Same as Other Apps (…)" was chosen (an app's Buttons part).
    var onSameAsOtherApps: (() -> Void)?

    // MARK: State

    private(set) var binding: ButtonBinding
    /// The pull-down reads "Default" without an action, and its menu offers "Default"
    /// where it offers "No Action" (nil, as "No Action"): every row of Buttons, and of an
    /// app's Buttons part. The Shortcut Ring's places and the Gestures pane's directions say
    /// "No Action".
    var offersDefault: Bool {
        return use == .binding
    }
    /// What a press does without an action (`ButtonDefaultOutcome`): "Default (Back)" or
    /// "Default" where it passes through, else "No Action" (another row's action runs, or
    /// nothing happens). The owner of the row works it out.
    var defaultOutcome: ButtonDefaultOutcome = .passes(nil) {
        didSet {
            guard defaultOutcome != oldValue else { return }
            applyNoActionTitle()
            refreshActionDisplay()
        }
    }

    /// What "Default" does where that is certain, named in its parentheses ("Default
    /// (Back)"); nil: "Default", or no default at all.
    var defaultEffect: ButtonsMousePart? {
        get { return defaultOutcome.effect }
        set { defaultOutcome = .passes(newValue) }
    }
    /// The title of "Same as Other Apps (Mission Control)", the first item of the menu (an
    /// app's Buttons part); nil: no such item.
    var sameAsOtherAppsTitle: String? {
        didSet {
            guard sameAsOtherAppsTitle != oldValue else { return }
            applySameAsOtherApps()
        }
    }
    private var isCustomRecordingActive = false
    /// The recorder of "Keyboard Shortcut…" caught a key; it is stored after the recorder's
    /// moment of feedback.
    private var isShortcutCaught = false
    private let resolver = ActionDisplayResolver()

    /// Starts the recorder of "Keyboard Shortcut…" at the pull-down. Tests replace it: a
    /// real recorder taps the system's events.
    var startShortcutRecorder: ((ButtonActionPullDown) -> Void)?

    /// Made the first time a shortcut is recorded.
    private var customRecorder: KeyRecorder?

    /// The action a recording caught, until it is stored (after the recorder's moment of
    /// feedback, or when the recorder hands its popover on, whichever comes first).
    private var caughtAction: String?
    /// The recorder's popover while it shows the name and icon of the recorded shortcut.
    private(set) var detailsPopover: KeyPopover?
    /// Makes the popover for the name and icon of a shortcut the row already holds.
    /// Tests replace it with one that opens no window.
    var makeDetailsPopover: () -> KeyPopover = { KeyPopover() }

    /// What the pull-down shows now.
    var actionState: CellActionState {
        if isCustomRecordingActive { return .recordingPrompt }
        return CellActionState(binding: binding)
    }

    /// What the pull-down chooses for. Changing it builds the menu anew.
    var use: Use {
        didSet {
            guard use != oldValue else { return }
            buildMenu()
            refreshActionDisplay()
        }
    }

    /// The pull-down of a place of the Shortcut Ring: its menu offers only what a place
    /// can hold (`ShortcutManager.buildShortcutMenu(forRingPlace:)`).
    var isForRingPlace: Bool {
        return use == .ringPlace
    }

    init(binding: ButtonBinding, use: Use) {
        self.binding = binding
        self.use = use
        super.init(frame: .zero, pullsDown: true)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: Self.width).isActive = true
        configure(with: binding)
    }

    convenience init(binding: ButtonBinding, forRingPlace: Bool = false) {
        self.init(binding: binding, use: forRingPlace ? .ringPlace : .binding)
    }

    required init?(coder: NSCoder) {
        fatalError("ButtonActionPullDown is built in code")
    }

    deinit {
        customRecorder?.stopRecording()
        detailsPopover?.onClose = nil
        detailsPopover?.hide()
    }

    /// Shows `binding`'s action. The menu is built for the trigger once (again only when
    /// the trigger changes), so choosing an item never replaces the menu it came from.
    func configure(with binding: ButtonBinding) {
        let rebuild = menu?.delegate !== self || self.binding.triggerEvent.type != binding.triggerEvent.type
            || self.binding.triggerEvent.code != binding.triggerEvent.code
        self.binding = binding
        if rebuild {
            buildMenu()
        }
        gestureSettingsItem?.isHidden = !isGestureNavigationBound
        // Gesture Navigation is held while the mouse moves: a key cannot run it (the input
        // side passes such a binding through), so a key is not offered it. A key that
        // already has it keeps the item, so the menu still shows what is set.
        gestureNavigationItem?.isHidden = binding.triggerEvent.type == .keyboard && !isGestureNavigationBound
        refreshActionDisplay()
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        switch use {
        case .gesture(let showsLogiActions):
            ShortcutManager.buildGestureActionMenu(
                into: menu,
                target: self,
                action: #selector(shortcutSelected(_:)),
                categories: MouseGestureSettingsControls.actionCategories(showLogiActions: showsLogiActions)
            )
        case .binding, .ringPlace:
            ShortcutManager.buildShortcutMenu(
                into: menu,
                target: self,
                action: #selector(shortcutSelected(_:)),
                showLogiActions: isLogitechTrigger,
                showsGestureSettings: true,
                forRingPlace: isForRingPlace
            )
        }
        // Item 0 is the title of a pull-down; the separator after it would open the menu.
        if menu.items.count > 1, menu.items[1].isSeparatorItem {
            menu.items[1].isHidden = true
        }
        // Key equivalents only show while the menu is open: a shortcut a button sends
        // must never pick an item of a closed menu.
        disableKeyEquivalents(in: menu)
        self.menu = menu
        applyNoActionTitle()
        applySameAsOtherApps()
    }

    /// The item that clears the action ("No Action", or "Default").
    var noActionItem: NSMenuItem? {
        return menu?.items.dropFirst().first {
            $0.action == #selector(shortcutSelected(_:)) && $0.representedObject == nil
        }
    }

    /// What the pull-down and its item say without an action: "Default (Back)", "Default",
    /// or "No Action" (`defaultOutcome`).
    var defaultTitle: String {
        return defaultOutcome.title
    }

    private func applyNoActionTitle() {
        noActionItem?.title = offersDefault ? defaultTitle : NSLocalizedString("unbound", comment: "")
    }

    /// What the "Same as Other Apps (…)" item carries.
    static let sameAsOtherAppsMarker = "same-as-other-apps"

    /// "Same as Other Apps (…)", while there is one.
    var sameAsOtherAppsItem: NSMenuItem? {
        return menu?.items.first { $0.representedObject as? String == Self.sameAsOtherAppsMarker }
    }

    /// Puts "Same as Other Apps (…)" and a separator before "Default", or takes them away.
    private func applySameAsOtherApps() {
        guard let menu else { return }
        if let item = sameAsOtherAppsItem {
            let index = menu.index(of: item)
            if let title = sameAsOtherAppsTitle {
                item.title = title
                return
            }
            menu.removeItem(at: index + 1)  // (its separator)
            menu.removeItem(at: index)
            return
        }
        guard let title = sameAsOtherAppsTitle, let noAction = noActionItem else { return }
        let item = NSMenuItem(title: title, action: #selector(sameAsOtherAppsChosen(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = Self.sameAsOtherAppsMarker
        let index = menu.index(of: noAction)
        menu.insertItem(.separator(), at: index)
        menu.insertItem(item, at: index)
    }

    @objc func sameAsOtherAppsChosen(_ sender: NSMenuItem) {
        // (The row goes; until then it shows what it had.)
        refreshActionDisplay()
        onSameAsOtherApps?()
    }

    /// "Default (Back)" with the parenthesis in grey, in `font`; nil for a title without
    /// one. The plain text is the same, for VoiceOver.
    static func defaultAttributedTitle(_ title: String, font: NSFont) -> NSAttributedString? {
        let base = NSLocalizedString("buttons-default", comment: "")
        guard title.count > base.count, title.hasPrefix(base) else { return nil }
        let text = NSMutableAttributedString(string: title, attributes: [.font: font])
        let rest = NSRange(title.index(title.startIndex, offsetBy: base.count)..<title.endIndex, in: title)
        text.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: rest)
        return text
    }

    /// The "Gesture Navigation" item of the menu.
    var gestureNavigationItem: NSMenuItem? {
        return menu?.items.first {
            ($0.representedObject as? SystemShortcut.Shortcut)?.identifier == SystemShortcut.mouseGestureNavigation.identifier
        }
    }

    /// "Show Gesture Settings", shown while Gesture Navigation is the action.
    var gestureSettingsItem: NSMenuItem? {
        return menu?.items.first { $0.representedObject as? String == ShortcutManager.MenuMarker.gestureSettings }
    }

    private var isLogitechTrigger: Bool {
        return binding.triggerEvent.type == .mouse && LogiCenter.shared.isLogiCode(binding.triggerEvent.code)
    }

    var isGestureNavigationBound: Bool {
        guard case .namedShortcut(let shortcut) = CellActionState(binding: binding) else { return false }
        return shortcut.identifier == SystemShortcut.mouseGestureNavigation.identifier
    }

    /// Puts the action into the title (item 0).
    func refreshActionDisplay() {
        guard let titleItem = menu?.items.first else { return }
        var presentation = resolver.resolve(state: actionState)
        let font = self.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let showsDefault = offersDefault && presentation.kind == .unbound
        if showsDefault {
            presentation = ActionPresentation(kind: .unbound, title: defaultTitle)
        }
        // (A named keyboard shortcut: its name, then its keys in grey; "Default (Back)": the
        // parenthesis in grey. The plain title holds it all, for VoiceOver.)
        titleItem.title = presentation.plainTitle
        titleItem.attributedTitle = showsDefault
            ? Self.defaultAttributedTitle(presentation.title, font: font)
            : presentation.attributedTitle(font: font)
        // What "Default" does, in a sentence, where that is certain: the line under the row
        // said it before.
        toolTip = showsDefault ? defaultEffect.map { NSLocalizedString($0.defaultExplanationKey, comment: "") } : nil
        if let image = presentation.image {
            let sized = image.copy() as? NSImage ?? image
            sized.size = NSSize(width: Self.imageSize, height: Self.imageSize)
            titleItem.image = sized
        } else if let glyph = presentation.glyph {
            titleItem.image = ShortcutIconSet.image(of: .character(glyph), side: Self.imageSize)
        } else {
            titleItem.image = presentation.symbolName.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        }
        synchronizeTitleAndSelectedItem()
    }

    /// "Keyboard Shortcut…": the title asks for a key, and the recorder starts.
    /// With `openPopover` (the details, "Record Again") the recording uses that popover
    /// where it is open.
    func beginCustomShortcutSelection(startRecorder: Bool = true, in openPopover: KeyPopover? = nil) {
        isCustomRecordingActive = true
        refreshActionDisplay()
        guard startRecorder else { return }
        // (After a menu the recorder waits a moment for it to close.)
        DispatchQueue.main.asyncAfter(deadline: .now() + (openPopover == nil ? 0.15 : 0)) { [weak self] in
            guard let self, self.window != nil else { return }
            if let start = self.startShortcutRecorder {
                start(self)
            } else {
                let recorder = self.customRecorder ?? KeyRecorder()
                recorder.delegate = self
                self.customRecorder = recorder
                recorder.startRecording(from: self, mode: .adaptive, in: openPopover)
            }
        }
    }

    /// Ends a "Keyboard Shortcut…" recording that still waits for a key (the pane went
    /// away): the recorder closes and the action shows again. A key already caught is
    /// kept, and so are a name and an icon that were being set.
    func cancelShortcutRecording() {
        customRecorder?.stopRecording()
        detailsPopover?.hide()
        guard isCustomRecordingActive, !isShortcutCaught else { return }
        isCustomRecordingActive = false
        refreshActionDisplay()
    }

    // MARK: The name and icon of a recorded shortcut

    /// The row holds a recorded key combination, which can have a name and an icon.
    var holdsRecordedKeys: Bool {
        return ShortcutLabel.takes(action: binding.systemShortcutName)
    }

    /// The keys of a recorded combination as the key slot shows them.
    static func keyComponents(of action: String) -> [String] {
        guard let recorded = ButtonBinding.normalizedCustomBindingDescriptor(from: action) else { return [] }
        return InputEvent(
            type: recorded.type, code: recorded.code, modifiers: CGEventFlags(rawValue: recorded.modifiers),
            phase: .down, source: .hidPP, device: nil
        ).displayComponents
    }

    /// "Keyboard Shortcut…" on a row that already holds a recorded key combination: the
    /// popover with its keys, its name and its icon. Nothing is recorded until "Record
    /// Again" is pressed there.
    func openShortcutDetails() {
        guard holdsRecordedKeys, detailsPopover == nil else { return }
        let popover = makeDetailsPopover()
        adoptDetails(popover)
        presentShortcutDetails(popover, self, Self.keyComponents(of: binding.systemShortcutName), binding.label)
    }

    /// Shows the details at the pull-down. Tests replace it: nothing opens.
    var presentShortcutDetails: (KeyPopover, NSView, [String], ShortcutLabel?) -> Void = { popover, anchor, keys, label in
        guard anchor.window != nil else { return }
        popover.showDetails(at: anchor, keys: keys, label: label)
    }

    private func adoptDetails(_ popover: KeyPopover) {
        detailsPopover = popover
        popover.labelShowsInRing = isForRingPlace
        popover.onRecordAgain = { [weak self, weak popover] in
            guard let self, let popover, self.detailsPopover === popover else { return }
            // What was typed so far stays with the row, whatever the recording brings.
            self.storeLabel(popover.editedLabel)
            self.beginCustomShortcutSelection(in: popover)
        }
        popover.onClose = { [weak self, weak popover] in
            guard let self, let popover, self.detailsPopover === popover else { return }
            self.detailsPopover = nil
            // (A popover that closes while keys are recorded into it has nothing new.)
            guard popover.isShowingDetails else { return }
            self.storeLabel(popover.editedLabel)
        }
    }

    /// Gives the recorded shortcut `label` (nil: none) and tells the pane, when that is a
    /// change.
    private func storeLabel(_ label: ShortcutLabel?) {
        guard holdsRecordedKeys, label != binding.label else { return }
        configure(with: binding.labelled(label))
        onCustomShortcutRecorded?(binding.systemShortcutName, binding.label)
    }

    /// Stores the shortcut a recording caught, once: the row shows it and the pane hears
    /// of it. Other keys keep the name and icon the row had; anything else drops them.
    private func storeCaughtShortcut() {
        guard let actionName = caughtAction else { return }
        caughtAction = nil
        isCustomRecordingActive = false
        isShortcutCaught = false
        let old = binding
        let recorded = ButtonBinding(
            id: old.id,
            triggerEvent: old.triggerEvent,
            systemShortcutName: actionName,
            isEnabled: true,
            createdAt: old.createdAt,
            label: old.label
        )
        configure(with: recorded)
        onCustomShortcutRecorded?(actionName, recorded.label)
    }

    // MARK: Menu

    @objc func shortcutSelected(_ sender: NSMenuItem) {
        switch sender.representedObject as? String {
        case ShortcutManager.MenuMarker.openTarget?:
            refreshActionDisplay()
            onOpenTargetSelectionRequested?()
            return
        case ShortcutManager.MenuMarker.keyboardShortcut?:
            // Keys that are there already: their name and icon first, other keys from there.
            if holdsRecordedKeys {
                refreshActionDisplay()
                openShortcutDetails()
            } else {
                beginCustomShortcutSelection()
            }
            return
        case ShortcutManager.MenuMarker.gestureSettings?:
            refreshActionDisplay()
            onGestureSettingsRequested?()
            return
        default:
            break
        }
        // A listed action, or nil: No Action.
        let shortcut = sender.representedObject as? SystemShortcut.Shortcut
        let old = binding
        configure(with: ButtonBinding(
            id: old.id,
            triggerEvent: old.triggerEvent,
            systemShortcutName: shortcut?.identifier ?? "",
            isEnabled: shortcut != nil,
            createdAt: old.createdAt
        ))
        onShortcutSelected?(shortcut)
    }

    func menuWillOpen(_ menu: NSMenu) {
        enableKeyEquivalents(in: menu)
    }

    func menuDidClose(_ menu: NSMenu) {
        disableKeyEquivalents(in: menu)
    }

    private func enableKeyEquivalents(in menu: NSMenu) {
        for item in menu.items {
            if let shortcut = item.representedObject as? SystemShortcut.Shortcut {
                let keyEquivalent = shortcut.keyEquivalent
                item.keyEquivalent = keyEquivalent.keyEquivalent
                item.keyEquivalentModifierMask = keyEquivalent.modifierMask
            }
            if let submenu = item.submenu {
                enableKeyEquivalents(in: submenu)
            }
        }
    }

    private func disableKeyEquivalents(in menu: NSMenu) {
        for item in menu.items {
            item.keyEquivalent = ""
            item.keyEquivalentModifierMask = []
            if let submenu = item.submenu {
                disableKeyEquivalents(in: submenu)
            }
        }
    }
}

// MARK: - Recording a keyboard shortcut

extension ButtonActionPullDown: KeyRecorderDelegate {

    func onRecordingStarted(_ recorder: KeyRecorder) {
        isCustomRecordingActive = true
        isShortcutCaught = false
        refreshActionDisplay()
    }

    func onRecordingStopped(_ recorder: KeyRecorder, didRecord: Bool) {
        guard !didRecord else { return }
        isCustomRecordingActive = false
        refreshActionDisplay()
    }

    func onEventRecorded(_ recorder: KeyRecorder, didRecordEvent event: InputEvent, isDuplicate: Bool) {
        guard !isDuplicate else {
            // The button itself: the prompt stays while the recorder says so, then the
            // action shows again.
            DispatchQueue.main.asyncAfter(deadline: .now() + KeyRecorder.recordingFeedbackDelay(isDuplicate: true)) { [weak self] in
                self?.isCustomRecordingActive = false
                self?.refreshActionDisplay()
            }
            return
        }
        caughtAction = Self.bindingName(forRecorded: event)
        isShortcutCaught = true
        DispatchQueue.main.asyncAfter(deadline: .now() + KeyRecorder.recordingFeedbackDelay(isDuplicate: false)) { [weak self] in
            self?.storeCaughtShortcut()
        }
    }

    /// The recording is over and caught something. A key combination that can have a
    /// name and an icon keeps the popover: it goes on to ask for them. Everything else (a
    /// listed action, a mouse button) lets it close. A popover that is gone already (the
    /// user clicked elsewhere during the moment of feedback) is not brought back.
    func takesPopover(_ recorder: KeyRecorder, _ popover: KeyPopover) -> Bool {
        storeCaughtShortcut()
        guard popover.isOpen, holdsRecordedKeys else { return false }
        adoptDetails(popover)
        popover.turnToDetails(label: binding.label)
        return true
    }

    /// What a place of the Shortcut Ring cannot run is refused when it is pressed, not
    /// taken and then dropped: a mouse button other than Back and Forward, a modifier key
    /// by itself. The same for a direction of Gesture Navigation, which runs what a place
    /// runs.
    private func isRefused(_ event: InputEvent) -> Bool {
        return use.recordsWhatARingPlaceRuns && !ShortcutRingPlace(action: Self.bindingName(forRecorded: event)).runs
    }

    /// For a place of the ring, or a direction, the recorder asks for what it takes.
    func waitingHint(_ recorder: KeyRecorder, mode: KeyRecordingMode) -> String? {
        switch use {
        case .binding: return nil
        case .ringPlace: return NSLocalizedString("ring-recorder-waiting", comment: "")
        case .gesture: return NSLocalizedString("gesture-recorder-waiting", comment: "")
        }
    }

    func refusalHint(_ recorder: KeyRecorder, event: InputEvent) -> String? {
        guard isRefused(event) else { return nil }
        return NSLocalizedString(use == .ringPlace ? "ring-recorder-refused" : "gesture-recorder-refused", comment: "")
    }

    /// The button cannot be its own shortcut.
    func validateRecordedEvent(_ recorder: KeyRecorder, event: InputEvent) -> Bool {
        if isRefused(event) { return false }
        let recorded = RecordedEvent(from: event)
        let trigger = binding.triggerEvent
        return (recorded.standardMouseAliasTriggerIfAvailable() ?? recorded)
            != (trigger.standardMouseAliasTriggerIfAvailable() ?? trigger)
    }

    /// The stored name of a recorded shortcut: a listed action when it is one.
    static func bindingName(forRecorded event: InputEvent) -> String {
        let customName = ButtonBinding.normalizedCustomBindingName(from: event)
        if let shortcut = SystemShortcut.displayShortcut(matchingBindingName: customName) {
            return shortcut.identifier
        }
        return customName
    }
}
