//
//  GesturesPreferencesViewController.swift
//  Mos
//  "Gestures" preferences tab: everything about Gesture Navigation in one place, built in
//  code on PreferencesGroupedForm, in the boxes of System Settings like the Scrolling tab.
//
//  On top a preview that shows what a gesture does with the current settings (and the
//  gesture of the row under the pointer), on the connected mouse holding the button the
//  first row names first (`MouseGestureBindingSummary.picture`). Then a box with the mode, a box with the action
//  of every direction and of Click, a box with how a gesture behaves (invert, freeze,
//  swipe speed) and, when a connected mouse can do it, a box with what a Logitech mouse
//  does itself; under it, while the mouse has its haptics off because the user switched
//  them off under Mouse, a muted line that says so and leads there ("Show in Mouse"). Last,
//  "Reset to Defaults", as in the Scrolling pane (`PreferencesPaneReset`): every gesture
//  setting of a new installation; the button to hold is a binding of Buttons and stays.
//  Mode, actions, invert and freeze come from MouseGestureSettingsControls, the rows from
//  `MouseGestureRows` (an app's Gestures part shows the same rows for the app's own set).
//  The tab edits Options.shared.gesture. Which button runs Gesture Navigation is a binding
//  of the Buttons tab, and the first row ("Button to hold") names it and chooses it in
//  place: its pull-down (`TriggerChooser`) lists the connected mouse's buttons with what
//  each does now, "Record a Button…" and "Show in Buttons" (the Buttons pane with that
//  button's row selected), and a choice writes the binding Buttons would, with Undo.
//  While only an app's own button runs it, the row says where ("Only in Figma: Back
//  button.") and "Show in Buttons" shows that app's Buttons part (`ApplicationTriggerRule`).
//  While no button runs it at all, everything under the first box is folded under its
//  titles ("Directions ›", "Behavior ›", "Logitech mouse ›",
//  `PreferencesDisclosureSection`), each with the muted line that belongs to it: one click
//  opens a section and it can be edited as ever. Once a button runs the gestures the
//  sections show by themselves, with plain titles.
//

import Cocoa

final class GesturesPreferencesViewController: NSViewController {

    static let tabIdentifier = "gestures"

    /// As wide as the Scrolling tab: the pop-ups and switches sit on the right of their rows.
    static let paneWidth: CGFloat = 520
    static var boxWidth: CGFloat {
        return PreferencesGroupedForm.boxWidth(paneWidth: paneWidth)
    }
    /// All action pop-ups have this width, so they line up (the Buttons pane's).
    static let popUpWidth: CGFloat = ButtonActionPullDown.width
    /// Room for the widest tracking speed ("2.75×"): the kit's value column, so the slider
    /// stands where the Scrolling pane's sliders stand.
    static let trackingSpeedValueWidth: CGFloat = PreferencesGroupedForm.sliderValueWidth

    /// Identifiers for the views of the tab (tests and accessibility tooling). The shared
    /// controls have theirs in `MouseGestureSettingsControls.Identifier`.
    enum Identifier {
        static let preview = NSUserInterfaceItemIdentifier("gestures-preview")
        static let gestureButton = NSUserInterfaceItemIdentifier("gestures-gesture-button")
        static let directionsHint = NSUserInterfaceItemIdentifier("gestures-directions-hint")
        static let trackingSpeed = MouseGestureSettingsControls.Identifier.trackingSpeed
        static let deviceTracking = MouseGestureSettingsControls.Identifier.deviceTracking
        static let haptics = MouseGestureSettingsControls.Identifier.haptics
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
    /// What the pane shows of it now: "Show in Buttons" goes where the row says.
    private var shownSummary: MouseGestureBindingSummary?
    /// "Show in Buttons": shows the Buttons pane, with the row of the button that runs
    /// Gesture Navigation selected when one does. Tests replace it.
    var openButtonsPane: (() -> Void)?
    /// "Show in Buttons" while only an app's own button runs Gesture Navigation: shows that
    /// app's Buttons part, its row selected. Tests replace it.
    var openApplicationButtons: ((ApplicationTriggers) -> Void)?
    /// "Show in Mouse": shows the Mouse pane. Tests replace it.
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
    /// "Button to hold"'s pull-down, and what it does.
    private(set) var triggerChooser: TriggerChooser!
    var gestureButtonButton: TriggerChoicePullDown {
        return triggerChooser.pullDown
    }
    private(set) var modeRow: PreferencesGroupRow!
    /// Up, Down, Left, Right, Click, in `Slot.allCases` order, and the line under the title.
    private(set) var directionRows: [PreferencesGroupRow] = []
    private(set) var directionsHintLabel: NSTextField!
    /// "Directions": the line on how a gesture is made and the box of rows.
    private(set) var directionsSection: PreferencesDisclosureSection!
    /// "Behavior": invert, freeze and the swipe speed. Its box is followed by the muted
    /// line on what a Logitech mouse adds while none is connected.
    private(set) var behaviourSection: PreferencesDisclosureSection!
    private(set) var invertRow: PreferencesGroupRow!
    private(set) var freezeRow: PreferencesGroupRow!
    private(set) var trackingSpeedRow: PreferencesSliderRow!
    /// "Logitech mouse": shown when a connected mouse supports one of its options; the
    /// muted line under the boxes says what is needed otherwise.
    private(set) var logitechSection: PreferencesDisclosureSection!
    private(set) var logitechBox: PreferencesGroupBox!
    private(set) var deviceTrackingRow: PreferencesSwitchRow!
    private(set) var hapticsRow: PreferencesSwitchRow!
    /// "Haptic feedback is off under Mouse." with "Show in Mouse", under the Logitech box.
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
    /// The sections whose titles fold them while no button runs Gesture Navigation.
    var foldingSections: [PreferencesDisclosureSection] {
        return [directionsSection, behaviourSection, logitechSection]
    }
    private var contentStack: NSStackView!

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
        directionsSection = directions
        let behaviour = PreferencesDisclosureSection(
            title: text("gestures-behaviour-header"),
            body: PreferencesGroupBox(width: width, rows: [makeInvertRow(), makeFreezeRow(), makeTrackingSpeedRow()])
        )
        behaviourSection = behaviour
        logitechBox = PreferencesGroupBox(width: width, rows: [makeDeviceTrackingRow(), makeHapticsRow()])
        let logitech = PreferencesDisclosureSection(title: text("gestures-logitech-header"), body: logitechBox)
        logitechSection = logitech
        for section in [directions, behaviour, logitech] {
            // (The muted lines and the spacing follow the section: `reload`.)
            section.onExpandedChange = { [weak self] _ in self?.reload() }
        }
        hapticsOffNote = makeHapticsOffNote()
        logitechNeedsLabel = Self.makeNote(text("gestures-logitech-needs"), identifier: Identifier.logitechNeeds)
        let logitechNeeds = Self.inset(logitechNeedsLabel)
        resetToDefaults = makeReset()
        footer = PreferencesGroupFooter(trailing: [resetToDefaults.button])

        sections = [preview, first, directions, behaviour, logitech, hapticsOffNote, logitechNeeds, footer]
        PreferencesGroupedForm.add(sections, to: content)
        contentStack = content
        // The titled sections keep a section's room above them (`add`). The muted lines sit
        // close under the boxes (only one of them shows: one needs the Logitech box, the
        // other its absence, and each folds with its box). The footer keeps its room above
        // whichever view shows last: a muted line (here) or a section (`reload`).
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
        // Edit › Undo or Redo of a change in Buttons or an app's Buttons part can change
        // which button runs the gestures while the pane shows.
        for name in [Notification.Name.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange] {
            NotificationCenter.default.addObserver(self, selector: #selector(undoDidRun(_:)), name: name, object: nil)
        }
    }

    /// An Undo or Redo ran: the pane on screen shows which button runs the gestures now,
    /// when that changed (an Undo of typing elsewhere changes nothing here).
    @objc private func undoDidRun(_ notification: Notification) {
        guard isViewLoaded, view.window != nil, bindingSummary() != shownSummary else { return }
        reload()
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
        // A recording that still waits for a key, and the popover, go with the pane.
        controls.endEditing()
        triggerChooser.endEditing()
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
        shownSummary = summary
        controls.showLogiActions = summary.hasLogitechGestureButton
        controls.sync()
        let gesture = Options.shared.gesture
        let presentation = controls.modePresentation

        // One button: the pull-down names it, the line says what to do with it. Two or more
        // (the pull-down says "Multiple"), only an app's own, none: the line says which.
        gestureButtonRow.explanation = summary.hasGestureButton && summary.buttonTitles.count == 1
            ? text("gestures-gesture-button-one") : summary.gestureButtonExplanation
        // The preview's mouse holds the first button the row names.
        previewView.picture = summary.picture
        // The pull-down names what the row names first, and offers the mouse's buttons;
        // "Show in Buttons" says where it goes (`showInButtons`).
        triggerChooser.update(
            triggerTitles: summary.buttonTitles,
            showsInApplication: summary.hasGestureButton ? nil : summary.onlyInApps?.applicationNames.first
        )
        modeRow.explanation = text(presentation.descriptionKey)
        // No button runs these gestures (none at all, or only in apps that run their own):
        // what is under the first box waits, folded.
        let runsThese = summary.hasGestureButton || summary.onlyInApps?.usesGeneralSettings == true
        for section in foldingSections {
            section.isCollapsible = !runsThese
        }

        for slot in Slot.allCases where slot.isHorizontal {
            directionRows[slot.rawValue].isEnabled = presentation.areHorizontalActionsEditable
        }

        // A refresh arriving while the user drags the knob must not snap it back. A stored
        // speed between two ticks shows on the nearer one and stays as stored until the
        // slider is moved.
        MouseGestureRows.show(gesture, presentation: presentation, in: trackingSpeedRow)

        gestureSupport = deviceSource.support()
        let rules = MouseGestureControlRules(support: gestureSupport, hapticsOnUnderMouse: Options.shared.logiMouse.hapticsOn)
        logitechSection.isHidden = !rules.showsOptions
        // A muted line shows with the box it follows, and folds with it.
        let showsHapticsOffNote = rules.showsOptions && rules.showsHapticsOffNote && logitechSection.showsBody
        let showsLogitechNeeds = !rules.showsOptions && behaviourSection.showsBody
        hapticsOffNote.isHidden = !showsHapticsOffNote
        logitechNeedsLabel.superview?.isHidden = !showsLogitechNeeds
        // A muted line sits close under its box; a titled section or the footer keeps the
        // room above it.
        contentStack.setCustomSpacing(
            showsLogitechNeeds ? PreferencesGroupedForm.noteSpacing : PreferencesGroupedForm.sectionSpacing,
            after: behaviourSection
        )
        contentStack.setCustomSpacing(
            showsHapticsOffNote ? PreferencesGroupedForm.noteSpacing : PreferencesGroupedForm.sectionSpacing,
            after: logitechSection
        )
        MouseGestureRows.show(gesture, rules: rules, deviceTracking: deviceTrackingRow, haptics: hapticsRow)

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
        controls.setTrackingSpeed(value)
        updatePreviewScene()
        resetToDefaults.settingsDidChange()
    }

    @objc func deviceTrackingToggled(_ sender: NSSwitch) {
        controls.setDeviceTracking(sender.state == .on)
        reload()
    }

    @objc func hapticsToggled(_ sender: NSSwitch) {
        controls.setHapticFeedback(sender.state == .on)
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
        reset.willReset = { [weak self] in self?.controls.endEditing() }
        reset.button.identifier = Identifier.reset
        return reset
    }

    // MARK: - Rows

    private func text(_ key: String) -> String {
        return NSLocalizedString(key, comment: "")
    }

    /// "Button to hold": the buttons that run Gesture Navigation, or none yet, and the
    /// pull-down that chooses one (`TriggerChooser`): a choice shows at once in the row, the
    /// preview and the sections, which no longer fold.
    private func makeGestureButtonRow() -> PreferencesGroupRow {
        let chooser = TriggerChooser(rule: .gestureNavigation)
        chooser.undoManager = { [weak self] in self?.undoTarget }
        chooser.showInButtons = { [weak self] in self?.showInButtons() }
        chooser.didChange = { [weak self] in self?.reload() }
        chooser.pullDown.identifier = Identifier.gestureButton
        triggerChooser = chooser
        let row = PreferencesGroupRow(
            title: text("gestures-gesture-button"),
            explanation: text("gestures-gesture-button-none"),
            accessory: chooser.pullDown
        )
        gestureButtonRow = row
        return row
    }

    /// "Show in Buttons": the Buttons pane with the row of the button that runs the
    /// gestures selected (and lit on its card); while only an app's own button runs them,
    /// that app's Buttons part (the item then says "Show in Notes › Buttons").
    func showInButtons() {
        // (What the row says, which an Undo keeps up to date.)
        let summary = shownSummary ?? bindingSummary()
        if !summary.hasGestureButton, let apps = summary.onlyInApps {
            if let openApplicationButtons {
                openApplicationButtons(apps)
            } else {
                PreferencesApplicationViewController.showButtons(of: apps, from: self)
            }
            return
        }
        if let openButtonsPane {
            openButtonsPane()
            return
        }
        guard let split = PreferencesButtonsViewController.splitViewController(of: self),
              split.selectPane(withIdentifier: PANEL_IDENTIFIER.buttons) else { return }
        guard summary.hasGestureButton,
              let buttons = split.controller(for: PANEL_IDENTIFIER.buttons) as? PreferencesButtonsViewController else { return }
        // The user sees which row it is: it is selected and its button lit on the card.
        buttons.selectGestureButton()
    }

    /// "Mode": what the selected mode does under the title, the two modes across the box.
    private func makeModeRow() -> PreferencesGroupRow {
        let row = MouseGestureRows.mode(controls.modeControl)
        modeRow = row
        return row
    }

    /// One direction (or Click) with its action pop-up. The row tells the preview when the
    /// pointer is over it.
    private func makeDirectionRow(_ slot: Slot) -> PreferencesGroupRow {
        // (The pull-down is `popUpWidth` wide by itself.)
        let popup = controls.actionPopUp(for: slot)
        let row = PreferencesGroupRow(title: text(slot.labelKey), accessory: popup)
        row.addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: [Self.hoverSlotInfo: slot.rawValue]
        ))
        return row
    }

    /// "Directions": its title, one line on how a gesture is made, and the box of rows. The
    /// title folds the line and the box while no button runs the gestures (`reload`).
    private func makeDirectionsSection(rows: [PreferencesGroupRow]) -> PreferencesDisclosureSection {
        let inset = PreferencesGroupedForm.rowHorizontalInset
        let hint = NSTextField(wrappingLabelWithString: text("gestures-directions-hint"))
        hint.identifier = Identifier.directionsHint
        hint.font = PreferencesGroupedForm.explanationFont
        hint.textColor = PreferencesGroupedForm.explanationColor(enabled: true)
        hint.isSelectable = false
        hint.preferredMaxLayoutWidth = Self.boxWidth - 2 * inset
        hint.translatesAutoresizingMaskIntoConstraints = false
        directionsHintLabel = hint
        let box = PreferencesGroupBox(width: Self.boxWidth, rows: rows)

        let body = NSView()
        body.translatesAutoresizingMaskIntoConstraints = false
        for view in [hint, box] as [NSView] {
            body.addSubview(view)
        }
        NSLayoutConstraint.activate([
            hint.topAnchor.constraint(equalTo: body.topAnchor),
            hint.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: inset),
            hint.trailingAnchor.constraint(lessThanOrEqualTo: body.trailingAnchor, constant: -inset),
            box.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: PreferencesGroupedForm.sectionTitleSpacing + 2),
            box.leadingAnchor.constraint(equalTo: body.leadingAnchor),
            box.trailingAnchor.constraint(equalTo: body.trailingAnchor),
            box.bottomAnchor.constraint(equalTo: body.bottomAnchor),
        ])
        return PreferencesDisclosureSection(
            title: text("gestures-directions-header"), body: body, spacing: PreferencesGroupedForm.explanationSpacing
        )
    }

    private func makeInvertRow() -> PreferencesGroupRow {
        let row = MouseGestureRows.invert(controls.invertToggle)
        invertRow = row
        return row
    }

    private func makeFreezeRow() -> PreferencesGroupRow {
        let row = MouseGestureRows.freeze(controls.freezeToggle)
        freezeRow = row
        return row
    }

    private func makeTrackingSpeedRow() -> PreferencesGroupRow {
        let row = MouseGestureRows.trackingSpeed(target: self, action: #selector(trackingSpeedChanged(_:)))
        trackingSpeedRow = row
        return row
    }

    private func makeDeviceTrackingRow() -> PreferencesGroupRow {
        let row = MouseGestureRows.deviceTracking(target: self, action: #selector(deviceTrackingToggled(_:)))
        deviceTrackingRow = row
        return row
    }

    /// "Haptic feedback is off under Mouse." at the rows' inset, "Show in Mouse" (small) at the
    /// right edge of the box above, in the column of its switches.
    private func makeHapticsOffNote() -> NSView {
        let note = MouseGestureRows.hapticsOffNote(boxWidth: Self.boxWidth, target: self, action: #selector(openMouseClicked(_:)))
        note.label.identifier = Identifier.hapticsOffNote
        note.button.identifier = Identifier.openMouse
        hapticsOffLabel = note.label
        openMouseButton = note.button
        return note.holder
    }

    private func makeHapticsRow() -> PreferencesGroupRow {
        let row = MouseGestureRows.haptics(target: self, action: #selector(hapticsToggled(_:)))
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
