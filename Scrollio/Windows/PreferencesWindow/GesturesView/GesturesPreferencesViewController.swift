//
//  GesturesPreferencesViewController.swift
//  Mos
//  "Gestures" preferences tab: everything about Gesture Navigation in one place, built in
//  code on PreferencesGroupedForm, in the boxes of System Settings like the Scrolling tab.
//
//  On top a preview that shows what a gesture does with the current settings (and the
//  gesture of the row under the pointer). Then a box with the mode, a box with the action
//  of every direction and of Click, a box with how a gesture behaves (invert, freeze,
//  swipe speed) and, when a connected mouse can do it, a box with what a Logitech mouse
//  does itself; under it, while the mouse has its haptics off because the user switched
//  them off under Mouse, a muted line that says so and leads there ("Open Mouse"). Last,
//  "Reset to Defaults", as in the Scrolling pane (`PreferencesPaneReset`): every gesture
//  setting of a new installation; the button to hold is a binding of Buttons and stays.
//  Mode, actions, invert and freeze come from MouseGestureSettingsControls.
//  The tab only edits Options.shared.gesture; which button runs Gesture Navigation is
//  chosen in the Buttons tab, and the first row ("Button to hold") names it and leads there:
//  "Set Up…" records one, "Change" shows the Buttons pane with that button's row selected.
//

import Cocoa

final class GesturesPreferencesViewController: NSViewController {

    static let tabIdentifier = "gestures"

    /// As wide as the Scrolling tab: the pop-ups and switches sit on the right of their rows.
    static let paneWidth: CGFloat = 520
    static var boxWidth: CGFloat {
        return PreferencesGroupedForm.boxWidth(paneWidth: paneWidth)
    }
    /// All action pop-ups have this width, so they line up.
    static let popUpWidth: CGFloat = 240
    /// Room for the widest tracking speed ("2.75×"): the kit's value column, so the slider
    /// stands where the Scrolling pane's sliders stand.
    static let trackingSpeedValueWidth: CGFloat = PreferencesGroupedForm.sliderValueWidth

    /// Identifiers for the views of the tab (tests and accessibility tooling). The shared
    /// controls have theirs in `MouseGestureSettingsControls.Identifier`.
    enum Identifier {
        static let preview = NSUserInterfaceItemIdentifier("gestures-preview")
        static let gestureButton = NSUserInterfaceItemIdentifier("gestures-gesture-button")
        static let directionsHint = NSUserInterfaceItemIdentifier("gestures-directions-hint")
        static let trackingSpeed = NSUserInterfaceItemIdentifier("gesture-tracking-speed")
        static let deviceTracking = NSUserInterfaceItemIdentifier("gesture-device-tracking")
        static let haptics = NSUserInterfaceItemIdentifier("gesture-haptics")
        static let logitechNeeds = NSUserInterfaceItemIdentifier("gestures-logitech-needs")
        static let hapticsOffNote = NSUserInterfaceItemIdentifier("gestures-haptics-off-note")
        static let openMouse = NSUserInterfaceItemIdentifier("gestures-open-mouse")
        static let reset = NSUserInterfaceItemIdentifier("gestures-reset")
    }

    typealias Slot = MouseGestureSettingsControls.Slot

    // MARK: - State

    /// What the connected mice can do; tests and screenshots replace it with fixtures.
    var deviceSource: MouseGestureDeviceSource = .live
    /// Which buttons use Gesture Navigation; tests and screenshots replace it with fixtures.
    var bindingSummary: () -> MouseGestureBindingSummary = { .current }
    /// "Set Up…" or "Change": shows the Buttons pane and, with no gesture button yet
    /// (true), records one that gets Gesture Navigation; with one (false), selects its row
    /// there. Tests replace it.
    var openButtonsPane: ((Bool) -> Void)?
    /// "Open Mouse": shows the Mouse pane. Tests replace it.
    var openMousePane: (() -> Void)?
    /// Takes Undo and Redo of "Reset to Defaults"; the window's when nil.
    var paneUndoManager: UndoManager?

    /// As last read from `deviceSource`.
    private(set) var gestureSupport = MouseGestureDeviceSupport.none

    /// The direction row under the pointer, and the one whose pop-up has the keyboard focus.
    private(set) var hoveredSlot: Slot?
    private(set) var focusedSlot: Slot?

    private let isInteractiveAvailable: () -> Bool

    // MARK: - Views (read access for tests)

    private(set) var previewView: GesturePreviewView!
    /// Mode, action pop-ups, invert and freeze.
    private(set) var controls: MouseGestureSettingsControls!

    /// The first box: which button runs Gesture Navigation, and the mode.
    private(set) var gestureButtonRow: PreferencesGroupRow!
    private(set) var gestureButtonButton: NSButton!
    private(set) var modeRow: PreferencesGroupRow!
    /// Up, Down, Left, Right, Click, in `Slot.allCases` order, and the line under the title.
    private(set) var directionRows: [PreferencesGroupRow] = []
    private(set) var directionsHintLabel: NSTextField!
    private(set) var invertRow: PreferencesGroupRow!
    private(set) var freezeRow: PreferencesGroupRow!
    private(set) var trackingSpeedRow: PreferencesSliderRow!
    /// "Logitech mouse": shown when a connected mouse supports one of its options; the
    /// muted line under the boxes says what is needed otherwise.
    private(set) var logitechSection: PreferencesGroupSection!
    private(set) var deviceTrackingRow: PreferencesSwitchRow!
    private(set) var hapticsRow: PreferencesSwitchRow!
    /// "Haptic feedback is off under Mouse." with "Open Mouse", under the Logitech box.
    private(set) var hapticsOffNote: NSView!
    private(set) var hapticsOffLabel: NSTextField!
    private(set) var openMouseButton: NSButton!
    private(set) var logitechNeedsLabel: NSTextField!
    /// "Reset to Defaults" under everything else: all of `MouseGestureSettings` as a new
    /// installation has it. Not the button to hold.
    private(set) var resetToDefaults: PreferencesPaneReset!
    var resetToDefaultsButton: NSButton {
        return resetToDefaults.button
    }
    private(set) var footer: PreferencesGroupFooter!
    /// Everything in the content stack, top to bottom.
    private(set) var sections: [NSView] = []
    private var contentStack: NSStackView!
    private var behaviourSection: NSView!

    var trackingSpeedSlider: NSSlider { return trackingSpeedRow.slider }
    var deviceTrackingSwitch: NSSwitch { return deviceTrackingRow.toggle }
    var hapticsSwitch: NSSwitch { return hapticsRow.toggle }

    // MARK: - Lifecycle

    init(isInteractiveAvailable: @escaping () -> Bool = { DockSwipeSynthesizer.shared.isAvailable }) {
        self.isInteractiveAvailable = isInteractiveAvailable
        super.init(nibName: nil, bundle: nil)
        title = NSLocalizedString("gestures-tab-title", comment: "")
    }

    required init?(coder: NSCoder) {
        isInteractiveAvailable = { DockSwipeSynthesizer.shared.isAvailable }
        super.init(coder: coder)
        title = NSLocalizedString("gestures-tab-title", comment: "")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func loadView() {
        let root = PreferencesForm.makeBackground()
        let content = PreferencesGroupedForm.installContentStack(in: root, paneWidth: Self.paneWidth)
        // The pane wants to be exactly as tall as its rows: the window shrinks again when
        // the Logitech box goes away.
        content.setHuggingPriority(.defaultHigh, for: .vertical)

        controls = MouseGestureSettingsControls(
            showLogiActions: bindingSummary().hasLogitechGestureButton,
            isInteractiveAvailable: isInteractiveAvailable
        )
        controls.onChange = { [weak self] in self?.reload() }
        controls.onFocusChange = { [weak self] slot, focused in self?.slotFocusChanged(slot, focused: focused) }

        let preview = GesturePreviewView()
        preview.identifier = Identifier.preview
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.heightAnchor.constraint(equalToConstant: GesturePreviewView.preferredHeight).isActive = true
        previewView = preview

        let width = Self.boxWidth
        let first = PreferencesGroupSection(width: width, rows: [makeGestureButtonRow(), makeModeRow()])
        directionRows = Slot.allCases.map { makeDirectionRow($0) }
        let directions = makeDirectionsSection(rows: directionRows)
        let behaviour = PreferencesGroupSection(
            title: text("gestures-behaviour-header"),
            width: width,
            rows: [makeInvertRow(), makeFreezeRow(), makeTrackingSpeedRow()]
        )
        let logitech = PreferencesGroupSection(
            title: text("gestures-logitech-header"),
            width: width,
            rows: [makeDeviceTrackingRow(), makeHapticsRow()]
        )
        logitechSection = logitech
        hapticsOffNote = makeHapticsOffNote()
        logitechNeedsLabel = Self.makeNote(text("gestures-logitech-needs"), identifier: Identifier.logitechNeeds)
        let logitechNeeds = Self.inset(logitechNeedsLabel)
        resetToDefaults = makeReset()
        footer = PreferencesGroupFooter(trailing: [resetToDefaults.button])

        sections = [preview, first, directions, behaviour, logitech, hapticsOffNote, logitechNeeds, footer]
        PreferencesGroupedForm.add(sections, to: content)
        contentStack = content
        behaviourSection = behaviour
        // The directions carry their title in a view of their own. The muted lines sit
        // close under the boxes (only one of them shows: one needs the Logitech box, the
        // other its absence). The footer keeps its room above whichever view shows last:
        // a muted line (here) or the Logitech box (`reload`).
        content.setCustomSpacing(PreferencesGroupedForm.sectionSpacing, after: first)
        content.setCustomSpacing(PreferencesGroupedForm.sectionSpacing, after: hapticsOffNote)

        view = root
        reload()
        root.setFrameSize(root.fittingSize)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // A mouse that can track gestures or has haptics connected or left.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceStateDidChange(_:)),
            name: LogiCenter.gestureStateChanged,
            object: nil
        )
        // A mouse reported its haptics switched on or off.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceStateDidChange(_:)),
            name: LogiCenter.mouseStateChanged,
            object: nil
        )
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        // Show what is known right away (a button may have been bound under Buttons),
        // then ask the mice again; the answer arrives as `gestureStateChanged`.
        reload()
        deviceSource.refresh()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        previewView.setAnimating(true)
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        previewView.setAnimating(false)
        hoveredSlot = nil
        focusedSlot = nil
        updatePreviewScene()
        resetToDefaults.endUndoOffer()
    }

    @objc private func deviceStateDidChange(_ notification: Notification) {
        if Thread.isMainThread {
            reload()
        } else {
            DispatchQueue.main.async { [weak self] in self?.reload() }
        }
    }

    // MARK: - Refresh

    /// Puts the stored settings, the bindings and the device rules into the rows, then
    /// refits the window if the height changed.
    func reload() {
        guard isViewLoaded, controls != nil else { return }
        let summary = bindingSummary()
        controls.showLogiActions = summary.hasLogitechGestureButton
        controls.sync()
        let gesture = Options.shared.gesture
        let presentation = controls.modePresentation

        gestureButtonRow.explanation = summary.gestureButtonExplanation
        gestureButtonButton.title = text(summary.hasGestureButton ? "gestures-gesture-button-change" : "gestures-gesture-button-set-up")
        modeRow.explanation = text(presentation.descriptionKey)

        for slot in Slot.allCases where slot.isHorizontal {
            directionRows[slot.rawValue].isEnabled = presentation.areHorizontalActionsEditable
        }

        // A refresh arriving while the user drags the knob must not snap it back. A stored
        // speed between two ticks shows on the nearer one and stays as stored until the
        // slider is moved.
        if !trackingSpeedRow.isTracking {
            trackingSpeedRow.showValue(gesture.trackingSpeed)
        }
        trackingSpeedRow.valueText = MouseGestureTrackingSpeed.text(gesture.trackingSpeed)
        trackingSpeedRow.isEnabled = presentation.isTrackingSpeedEditable
        trackingSpeedRow.explanation = text(
            presentation.isTrackingSpeedEditable ? "gesture-tracking-speed-hint" : "gesture-tracking-speed-hint-discrete"
        )

        gestureSupport = deviceSource.support()
        let rules = MouseGestureControlRules(support: gestureSupport, hapticsOnUnderMouse: Options.shared.logiMouse.hapticsOn)
        logitechSection.isHidden = !rules.showsOptions
        hapticsOffNote.isHidden = !(rules.showsOptions && rules.showsHapticsOffNote)
        logitechNeedsLabel.superview?.isHidden = rules.showsOptions
        // A titled box keeps the room above its title; a muted line sits close.
        contentStack.setCustomSpacing(
            rules.showsOptions ? PreferencesGroupedForm.sectionSpacing : PreferencesGroupedForm.noteSpacing,
            after: behaviourSection
        )
        // Under the Logitech box comes its muted line, close, or else the footer.
        contentStack.setCustomSpacing(
            rules.showsHapticsOffNote ? PreferencesGroupedForm.noteSpacing : PreferencesGroupedForm.sectionSpacing,
            after: logitechSection
        )
        deviceTrackingRow.isOn = gesture.deviceTracking
        deviceTrackingRow.isEnabled = rules.deviceTrackingEnabled
        deviceTrackingRow.explanation = text(rules.deviceTrackingHintKey)
        hapticsRow.isOn = gesture.hapticFeedback
        hapticsRow.isEnabled = rules.hapticsEnabled
        hapticsRow.explanation = text(rules.hapticsHintKey)

        updatePreviewScene()
        resetToDefaults?.settingsDidChange()
        PreferencesForm.fitToContent(self)
    }

    // MARK: - Preview

    /// What the preview shows: the settings in effect and the row pointed at.
    var previewScene: GesturePreviewScene {
        var gesture = Options.shared.gesture
        if let controls {
            gesture.mode = controls.modePresentation.selectedMode
        }
        return GesturePreviewScene(gesture: gesture, focus: hoveredSlot ?? focusedSlot)
    }

    private func updatePreviewScene() {
        guard isViewLoaded, let previewView else { return }
        let scene = previewScene
        if previewView.scene != scene {
            previewView.scene = scene
        }
    }

    /// The pointer entered or left the row of `slot`.
    func slotHoverChanged(_ slot: Slot, inside: Bool) {
        if inside {
            hoveredSlot = slot
        } else if hoveredSlot == slot {
            hoveredSlot = nil
        }
        updatePreviewScene()
    }

    /// The pop-up of `slot` gained or lost the keyboard focus.
    func slotFocusChanged(_ slot: Slot, focused: Bool) {
        if focused {
            focusedSlot = slot
        } else if focusedSlot == slot {
            focusedSlot = nil
        }
        updatePreviewScene()
    }

    private static let hoverSlotInfo = "gestureSlot"

    private static func slot(of event: NSEvent) -> Slot? {
        guard let raw = event.trackingArea?.userInfo?[hoverSlotInfo] as? Int else { return nil }
        return Slot(rawValue: raw)
    }

    override func mouseEntered(with event: NSEvent) {
        guard let slot = Self.slot(of: event) else { return super.mouseEntered(with: event) }
        slotHoverChanged(slot, inside: true)
    }

    override func mouseExited(with event: NSEvent) {
        guard let slot = Self.slot(of: event) else { return super.mouseExited(with: event) }
        slotHoverChanged(slot, inside: false)
    }

    // MARK: - Actions

    @objc func trackingSpeedChanged(_ sender: NSSlider) {
        let value = MouseGestureTrackingSpeed.snapped(sender.doubleValue)
        trackingSpeedRow.valueText = MouseGestureTrackingSpeed.text(value)
        if Options.shared.gesture.trackingSpeed != value {
            Options.shared.gesture.trackingSpeed = value
        }
        updatePreviewScene()
        resetToDefaults.settingsDidChange()
    }

    @objc func deviceTrackingToggled(_ sender: NSSwitch) {
        let enabled = sender.state == .on
        if Options.shared.gesture.deviceTracking != enabled {
            Options.shared.gesture.deviceTracking = enabled
        }
        reload()
    }

    @objc func hapticsToggled(_ sender: NSSwitch) {
        let enabled = sender.state == .on
        if Options.shared.gesture.hapticFeedback != enabled {
            Options.shared.gesture.hapticFeedback = enabled
        }
        reload()
    }

    @objc func openMouseClicked(_ sender: NSButton) {
        if let openMousePane {
            openMousePane()
            return
        }
        PreferencesButtonsViewController.splitViewController(of: self)?
            .selectPane(withIdentifier: MousePreferencesViewController.tabIdentifier)
    }

    // MARK: - Reset

    /// Where a reset registers its Undo: the window's undo manager while the pane is in
    /// the window.
    var undoTarget: UndoManager? {
        return paneUndoManager ?? view.window?.undoManager
    }

    /// "Reset to Defaults": the gesture settings of a new installation, all of them (the
    /// mode, the action of every direction and of Click, invert, freeze, the swipe speed,
    /// and the two switches of a Logitech mouse, also while their box does not show). The
    /// button to hold is a binding of the Buttons pane and is not touched; "Haptic feedback"
    /// under Mouse is the Mouse pane's. Edit › Undo ("Undo Reset Gestures") brings back the
    /// settings that were there.
    private func makeReset() -> PreferencesPaneReset {
        let reset = PreferencesPaneReset(
            store: PreferencesPaneReset.Store(
                defaults: MouseGestureSettings.default,
                read: { Options.shared.gesture },
                write: { Options.shared.gesture = $0 },
                undoActionNameKey: "gestures-undo-reset"
            ),
            undoManager: { [weak self] in self?.undoTarget },
            didChange: { [weak self] in self?.reload() }
        )
        reset.button.identifier = Identifier.reset
        return reset
    }

    // MARK: - Rows

    private func text(_ key: String) -> String {
        return NSLocalizedString(key, comment: "")
    }

    /// "Button to hold": the buttons that run Gesture Navigation, or none yet, and a push
    /// button to the Buttons pane ("Set Up…" records a new one, "Change" shows the list with
    /// the gesture button's row selected).
    private func makeGestureButtonRow() -> PreferencesGroupRow {
        let button = PreferencesGroupedForm.makePushButton(
            title: text("gestures-gesture-button-set-up"),
            target: self,
            action: #selector(gestureButtonClicked(_:))
        )
        button.identifier = Identifier.gestureButton
        gestureButtonButton = button
        let row = PreferencesGroupRow(
            title: text("gestures-gesture-button"),
            explanation: text("gestures-gesture-button-none"),
            accessory: button
        )
        gestureButtonRow = row
        return row
    }

    @objc func gestureButtonClicked(_ sender: NSButton) {
        let addsButton = !bindingSummary().hasGestureButton
        if let openButtonsPane {
            openButtonsPane(addsButton)
            return
        }
        guard let split = PreferencesButtonsViewController.splitViewController(of: self),
              split.selectPane(withIdentifier: PANEL_IDENTIFIER.buttons) else { return }
        guard let buttons = split.controller(for: PANEL_IDENTIFIER.buttons) as? PreferencesButtonsViewController else { return }
        if addsButton {
            buttons.beginAddingBinding(action: SystemShortcut.mouseGestureNavigation)
        } else {
            // The user sees which row to change: it is selected and its button lit on the card.
            buttons.selectGestureButton()
        }
    }

    /// "Mode": what the selected mode does under the title, the two modes across the box.
    private func makeModeRow() -> PreferencesGroupRow {
        let mode = controls.modeControl
        mode.segmentDistribution = .fillEqually
        let row = PreferencesGroupRow(
            title: text("gesture-mode-label"),
            explanation: text(MouseGestureModePresentation.descriptionKeys[0]),
            accessory: mode,
            placement: .below
        )
        // Room for the longest line, so picking the other mode never changes the height.
        row.reservedExplanations = MouseGestureModePresentation.descriptionKeys.map(text)
        row.explanationLabel.identifier = MouseGestureSettingsControls.Identifier.modeNote
        modeRow = row
        return row
    }

    /// One direction (or Click) with its action pop-up. The row tells the preview when the
    /// pointer is over it.
    private func makeDirectionRow(_ slot: Slot) -> PreferencesGroupRow {
        let popup = controls.actionPopUp(for: slot)
        popup.widthAnchor.constraint(equalToConstant: Self.popUpWidth).isActive = true
        let row = PreferencesGroupRow(title: text(slot.labelKey), accessory: popup)
        row.addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: [Self.hoverSlotInfo: slot.rawValue]
        ))
        return row
    }

    /// "Directions": its title, one line on how a gesture is made, and the box of rows.
    private func makeDirectionsSection(rows: [PreferencesGroupRow]) -> NSView {
        let inset = PreferencesGroupedForm.rowHorizontalInset
        let title = PreferencesGroupedForm.makeSectionTitle(text("gestures-directions-header"))
        let hint = NSTextField(wrappingLabelWithString: text("gestures-directions-hint"))
        hint.identifier = Identifier.directionsHint
        hint.font = PreferencesGroupedForm.explanationFont
        hint.textColor = PreferencesGroupedForm.explanationColor(enabled: true)
        hint.isSelectable = false
        hint.preferredMaxLayoutWidth = Self.boxWidth - 2 * inset
        hint.translatesAutoresizingMaskIntoConstraints = false
        directionsHintLabel = hint
        let box = PreferencesGroupBox(width: Self.boxWidth, rows: rows)

        let section = NSView()
        section.translatesAutoresizingMaskIntoConstraints = false
        for view in [title, hint, box] as [NSView] {
            section.addSubview(view)
        }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: section.topAnchor),
            title.leadingAnchor.constraint(equalTo: section.leadingAnchor, constant: inset),
            title.trailingAnchor.constraint(lessThanOrEqualTo: section.trailingAnchor, constant: -inset),
            hint.topAnchor.constraint(equalTo: title.bottomAnchor, constant: PreferencesGroupedForm.explanationSpacing),
            hint.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            hint.trailingAnchor.constraint(lessThanOrEqualTo: section.trailingAnchor, constant: -inset),
            box.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: PreferencesGroupedForm.sectionTitleSpacing + 2),
            box.leadingAnchor.constraint(equalTo: section.leadingAnchor),
            box.trailingAnchor.constraint(equalTo: section.trailingAnchor),
            box.bottomAnchor.constraint(equalTo: section.bottomAnchor),
        ])
        return section
    }

    private func makeInvertRow() -> PreferencesGroupRow {
        let row = PreferencesGroupRow(
            title: text("gesture-invert-horizontal"),
            explanation: text("gesture-invert-horizontal-hint"),
            accessory: controls.invertToggle
        )
        invertRow = row
        return row
    }

    private func makeFreezeRow() -> PreferencesGroupRow {
        let row = PreferencesGroupRow(
            title: text("gesture-freeze-pointer"),
            explanation: text("gesture-freeze-pointer-hint"),
            accessory: controls.freezeToggle
        )
        freezeRow = row
        return row
    }

    private func makeTrackingSpeedRow() -> PreferencesGroupRow {
        let row = PreferencesSliderRow(
            title: text("gesture-tracking-speed-label"),
            explanation: text("gesture-tracking-speed-hint"),
            range: MouseGestureSettings.trackingSpeedRange,
            scale: MouseGestureTrackingSpeed.scale,
            ends: (low: text("gesture-tracking-speed-slower"), high: text("gesture-tracking-speed-faster")),
            valueWidth: Self.trackingSpeedValueWidth,
            target: self,
            action: #selector(trackingSpeedChanged(_:))
        )
        row.slider.identifier = Identifier.trackingSpeed
        row.reservedExplanations = [text("gesture-tracking-speed-hint"), text("gesture-tracking-speed-hint-discrete")]
        trackingSpeedRow = row
        return row
    }

    private func makeDeviceTrackingRow() -> PreferencesGroupRow {
        let row = PreferencesSwitchRow(
            title: text("mouse-gesture-device-tracking"),
            explanation: text("mouse-gesture-device-tracking-hint"),
            target: self,
            action: #selector(deviceTrackingToggled(_:))
        )
        row.toggle.identifier = Identifier.deviceTracking
        row.reservedExplanations = [text("mouse-gesture-device-tracking-hint"), text("mouse-gesture-device-tracking-unavailable")]
        deviceTrackingRow = row
        return row
    }

    /// "Haptic feedback is off under Mouse." at the rows' inset, "Open Mouse" (small) at the
    /// right edge of the box above, in the column of its switches.
    private func makeHapticsOffNote() -> NSView {
        let label = Self.makeNote(text("gestures-haptics-off-under-mouse"), identifier: Identifier.hapticsOffNote)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        hapticsOffLabel = label
        let button = PreferencesGroupedForm.makePushButton(
            title: text("gestures-open-mouse"),
            target: self,
            action: #selector(openMouseClicked(_:))
        )
        button.controlSize = .small
        button.font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small))
        button.identifier = Identifier.openMouse
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        // The button says where it goes; the line next to it says why.
        button.setAccessibilityHelp(label.stringValue)
        openMouseButton = button

        let inset = PreferencesGroupedForm.rowHorizontalInset
        let spacing = PreferencesGroupedForm.controlSpacing
        label.preferredMaxLayoutWidth = max(0, Self.boxWidth - 2 * inset - button.fittingSize.width - spacing)
        let holder = NSView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        holder.isHidden = true
        holder.addSubview(label)
        holder.addSubview(button)
        // Both on one middle line, the line as tall as the taller of the two.
        let middle = label.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        middle.priority = .defaultHigh
        let hug = holder.heightAnchor.constraint(equalToConstant: 0)
        hug.priority = .fittingSizeCompression
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: inset),
            label.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -spacing),
            label.topAnchor.constraint(greaterThanOrEqualTo: holder.topAnchor),
            label.bottomAnchor.constraint(lessThanOrEqualTo: holder.bottomAnchor),
            button.trailingAnchor.constraint(equalTo: holder.trailingAnchor, constant: -inset),
            button.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
            button.topAnchor.constraint(greaterThanOrEqualTo: holder.topAnchor),
            button.bottomAnchor.constraint(lessThanOrEqualTo: holder.bottomAnchor),
            middle, hug,
        ])
        return holder
    }

    private func makeHapticsRow() -> PreferencesGroupRow {
        let row = PreferencesSwitchRow(
            title: text("mouse-gesture-haptics"),
            explanation: text("mouse-gesture-haptics-hint"),
            target: self,
            action: #selector(hapticsToggled(_:))
        )
        row.toggle.identifier = Identifier.haptics
        row.reservedExplanations = [text("mouse-gesture-haptics-hint"), text("mouse-gesture-haptics-unavailable")]
        hapticsRow = row
        return row
    }

    /// A muted line under the boxes.
    private static func makeNote(_ string: String, identifier: NSUserInterfaceItemIdentifier) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: string)
        label.identifier = identifier
        label.font = PreferencesGroupedForm.explanationFont
        label.textColor = PreferencesGroupedForm.explanationColor(enabled: true)
        label.isSelectable = false
        label.preferredMaxLayoutWidth = boxWidth - 2 * PreferencesGroupedForm.rowHorizontalInset
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    /// `label` inset like the text of the rows above it.
    private static func inset(_ label: NSTextField) -> NSView {
        let inset = PreferencesGroupedForm.rowHorizontalInset
        let holder = NSView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: holder.topAnchor),
            label.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
            label.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: inset),
            label.trailingAnchor.constraint(lessThanOrEqualTo: holder.trailingAnchor, constant: -inset),
        ])
        return holder
    }
}
