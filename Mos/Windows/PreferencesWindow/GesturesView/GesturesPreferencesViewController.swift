//
//  GesturesPreferencesViewController.swift
//  Mos
//  "Gestures" preferences tab: everything about Gesture Navigation in one place, built in
//  code on PreferencesGroupedForm, in the boxes of System Settings like the Scrolling tab.
//
//  On top a preview that shows what a gesture does with the current settings (and the
//  gesture of the row under the pointer). Then a box with the mode, a box with the action
//  of every direction and of Click, a box with how a gesture behaves (invert, freeze,
//  tracking speed) and, when a connected mouse can do it, a box with what a Logitech mouse
//  does itself. Mode, actions, invert and freeze come from MouseGestureSettingsControls,
//  shared with the popover in the Buttons tab. The tab only edits Options.shared.gesture;
//  which button runs Gesture Navigation is chosen in the Buttons tab.
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
    /// Room for the widest tracking speed ("2.75×"), a little more than the kit's default.
    static let trackingSpeedValueWidth: CGFloat = 40
    /// Between the last box and the muted lines under it.
    static let noteSpacing: CGFloat = 10

    /// Identifiers for the views of the tab (tests and accessibility tooling). The shared
    /// controls have theirs in `MouseGestureSettingsControls.Identifier`.
    enum Identifier {
        static let preview = NSUserInterfaceItemIdentifier("gestures-preview")
        static let unbound = NSUserInterfaceItemIdentifier("gestures-unbound")
        static let directionsHint = NSUserInterfaceItemIdentifier("gestures-directions-hint")
        static let trackingSpeed = NSUserInterfaceItemIdentifier("gesture-tracking-speed")
        static let deviceTracking = NSUserInterfaceItemIdentifier("gesture-device-tracking")
        static let haptics = NSUserInterfaceItemIdentifier("gesture-haptics")
        static let logitechNeeds = NSUserInterfaceItemIdentifier("gestures-logitech-needs")
        static let buttonsNote = NSUserInterfaceItemIdentifier("gestures-buttons-note")
    }

    typealias Slot = MouseGestureSettingsControls.Slot

    // MARK: - State

    /// What the connected mice can do; tests and screenshots replace it with fixtures.
    var deviceSource: MouseGestureDeviceSource = .live
    /// Which buttons use Gesture Navigation; tests and screenshots replace it with fixtures.
    var bindingSummary: () -> MouseGestureBindingSummary = { .current }

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

    /// The first box: "no gesture button yet" (only while none is set up) and the mode.
    private(set) var unboundRow: PreferencesGroupRow!
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
    private(set) var logitechNeedsLabel: NSTextField!
    /// "Choose the gesture button under Buttons."
    private(set) var buttonsNoteLabel: NSTextField!
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
            toggleStyle: .switches,
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
        let first = PreferencesGroupSection(width: width, rows: [makeUnboundRow(), makeModeRow()])
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
        logitechNeedsLabel = Self.makeNote(text("gestures-logitech-needs"), identifier: Identifier.logitechNeeds)
        buttonsNoteLabel = Self.makeNote(text("gestures-buttons-note"), identifier: Identifier.buttonsNote)
        let logitechNeeds = Self.inset(logitechNeedsLabel)
        let buttonsNote = Self.inset(buttonsNoteLabel)

        sections = [preview, first, directions, behaviour, logitech, logitechNeeds, buttonsNote]
        PreferencesGroupedForm.add(sections, to: content)
        contentStack = content
        behaviourSection = behaviour
        // The directions carry their title in a view of their own. The muted lines sit
        // close under the boxes and to each other.
        content.setCustomSpacing(PreferencesGroupedForm.sectionSpacing, after: first)
        content.setCustomSpacing(Self.noteSpacing, after: logitech)
        content.setCustomSpacing(PreferencesGroupedForm.sectionTitleSpacing, after: logitechNeeds)

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
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        // Show what is known right away (the popover in Buttons may have changed the
        // settings, and a button may have been bound), then ask the mice again; the
        // answer arrives as `gestureStateChanged`.
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

        unboundRow.isHidden = summary.hasGestureButton
        buttonsNoteLabel.isHidden = !summary.hasGestureButton
        modeRow.explanation = text(presentation.descriptionKey)

        for slot in Slot.allCases where slot.isHorizontal {
            directionRows[slot.rawValue].isEnabled = presentation.areHorizontalActionsEditable
        }

        // A refresh arriving mid-drag must not snap the knob back. A stored speed between two
        // ticks shows on the nearer one and stays as stored until the slider is moved.
        if !PreferencesForm.isTrackingMouse {
            trackingSpeedRow.showValue(gesture.trackingSpeed)
        }
        trackingSpeedRow.valueText = MouseGestureTrackingSpeed.text(gesture.trackingSpeed)
        trackingSpeedRow.isEnabled = presentation.isTrackingSpeedEditable
        trackingSpeedRow.explanation = text(
            presentation.isTrackingSpeedEditable ? "gesture-tracking-speed-hint" : "gesture-tracking-speed-hint-discrete"
        )

        gestureSupport = deviceSource.support()
        let rules = MouseGestureControlRules(support: gestureSupport)
        logitechSection.isHidden = !rules.showsOptions
        logitechNeedsLabel.superview?.isHidden = rules.showsOptions
        // A titled box keeps the room above its title; a muted line sits close.
        contentStack.setCustomSpacing(
            rules.showsOptions ? PreferencesGroupedForm.sectionSpacing : Self.noteSpacing,
            after: behaviourSection
        )
        deviceTrackingRow.isOn = gesture.deviceTracking
        deviceTrackingRow.isEnabled = rules.deviceTrackingEnabled
        deviceTrackingRow.explanation = text(rules.deviceTrackingHintKey)
        hapticsRow.isOn = gesture.hapticFeedback
        hapticsRow.isEnabled = rules.hapticsEnabled
        hapticsRow.explanation = text(rules.hapticsHintKey)

        updatePreviewScene()
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

    // MARK: - Rows

    private func text(_ key: String) -> String {
        return NSLocalizedString(key, comment: "")
    }

    /// Shown in place of the bottom line while no button runs Gesture Navigation: until one
    /// does, nothing on this tab has an effect.
    private func makeUnboundRow() -> PreferencesGroupRow {
        let icon = NSImageView()
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        icon.image = NSImage(systemSymbolName: "exclamationmark.circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        icon.contentTintColor = .systemOrange
        icon.setAccessibilityElement(false)
        let row = PreferencesGroupRow(
            title: text("gestures-unbound-title"),
            explanation: text("gestures-unbound-hint"),
            accessory: icon,
            controls: []
        )
        row.identifier = Identifier.unbound
        unboundRow = row
        return row
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
