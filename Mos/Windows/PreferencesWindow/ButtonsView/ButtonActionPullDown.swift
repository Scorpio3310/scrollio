//
//  ButtonActionPullDown.swift
//  Mos
//  The action of one button in the Buttons pane: a pull-down 240 pt wide that shows the
//  action as the pull-downs of the Gestures pane do (a symbol and a name), and opens the
//  menu of ShortcutManager. "Open App or File…", "Keyboard Shortcut…" and "Show Gesture
//  Settings" are handed to the pane (or recorded here); every other item binds directly.
//

import Cocoa

final class ButtonActionPullDown: NSPopUpButton, NSMenuDelegate {

    static let width: CGFloat = 240
    /// Pictures before the title (an app's icon) are drawn this size.
    static let imageSize: CGFloat = 16

    // MARK: Callbacks

    /// A listed action was chosen, or No Action (nil).
    var onShortcutSelected: ((SystemShortcut.Shortcut?) -> Void)?
    /// A keyboard shortcut was recorded: its stored name.
    var onCustomShortcutRecorded: ((String) -> Void)?
    /// "Open App or File…" was chosen.
    var onOpenTargetSelectionRequested: (() -> Void)?
    /// "Show Gesture Settings" was chosen.
    var onGestureSettingsRequested: (() -> Void)?

    // MARK: State

    private(set) var binding: ButtonBinding
    private var isCustomRecordingActive = false
    private let resolver = ActionDisplayResolver()

    /// Starts the recorder of "Keyboard Shortcut…" at the pull-down. Tests replace it: a
    /// real recorder taps the system's events.
    var startShortcutRecorder: ((ButtonActionPullDown) -> Void)?

    /// Made the first time a shortcut is recorded.
    private var customRecorder: KeyRecorder?

    /// What the pull-down shows now.
    var actionState: CellActionState {
        if isCustomRecordingActive { return .recordingPrompt }
        return CellActionState(binding: binding)
    }

    init(binding: ButtonBinding) {
        self.binding = binding
        super.init(frame: .zero, pullsDown: true)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: Self.width).isActive = true
        configure(with: binding)
    }

    required init?(coder: NSCoder) {
        fatalError("ButtonActionPullDown is built in code")
    }

    deinit {
        customRecorder?.stopRecording()
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
        refreshActionDisplay()
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        ShortcutManager.buildShortcutMenu(
            into: menu,
            target: self,
            action: #selector(shortcutSelected(_:)),
            showLogiActions: isLogitechTrigger,
            showsGestureSettings: true
        )
        // Item 0 is the title of a pull-down; the separator after it would open the menu.
        if menu.items.count > 1, menu.items[1].isSeparatorItem {
            menu.items[1].isHidden = true
        }
        // Key equivalents only show while the menu is open: a shortcut a button sends
        // must never pick an item of a closed menu.
        disableKeyEquivalents(in: menu)
        self.menu = menu
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
        let presentation = resolver.resolve(state: actionState)
        titleItem.title = presentation.title
        if let image = presentation.image {
            let sized = image.copy() as? NSImage ?? image
            sized.size = NSSize(width: Self.imageSize, height: Self.imageSize)
            titleItem.image = sized
        } else {
            titleItem.image = presentation.symbolName.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        }
        synchronizeTitleAndSelectedItem()
    }

    /// "Keyboard Shortcut…": the title asks for a key, and the recorder starts.
    func beginCustomShortcutSelection(startRecorder: Bool = true) {
        isCustomRecordingActive = true
        refreshActionDisplay()
        guard startRecorder else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.window != nil else { return }
            if let start = self.startShortcutRecorder {
                start(self)
            } else {
                let recorder = self.customRecorder ?? KeyRecorder()
                recorder.delegate = self
                self.customRecorder = recorder
                recorder.startRecording(from: self, mode: .adaptive)
            }
        }
    }

    // MARK: Menu

    @objc func shortcutSelected(_ sender: NSMenuItem) {
        switch sender.representedObject as? String {
        case ShortcutManager.MenuMarker.openTarget?:
            refreshActionDisplay()
            onOpenTargetSelectionRequested?()
            return
        case ShortcutManager.MenuMarker.keyboardShortcut?:
            beginCustomShortcutSelection()
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
        let actionName = Self.bindingName(forRecorded: event)
        DispatchQueue.main.asyncAfter(deadline: .now() + KeyRecorder.recordingFeedbackDelay(isDuplicate: false)) { [weak self] in
            guard let self else { return }
            self.isCustomRecordingActive = false
            let old = self.binding
            self.configure(with: ButtonBinding(
                id: old.id,
                triggerEvent: old.triggerEvent,
                systemShortcutName: actionName,
                isEnabled: true,
                createdAt: old.createdAt
            ))
            self.onCustomShortcutRecorded?(actionName)
        }
    }

    /// The button cannot be its own shortcut.
    func validateRecordedEvent(_ recorder: KeyRecorder, event: InputEvent) -> Bool {
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
