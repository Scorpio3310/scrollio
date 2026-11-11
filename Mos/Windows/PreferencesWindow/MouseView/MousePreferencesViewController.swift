//
//  MousePreferencesViewController.swift
//  Mos
//  "Mouse" preferences tab, in the boxes of System Settings like the Scrolling tab
//  (PreferencesGroupedForm). On top a card with the mouse; under it "Pointer (macOS)", the
//  user's macOS tracking speed and pointer acceleration, shown for any mouse. With a
//  Logitech mouse the card shows its name and battery, and "Let Scrollio manage this mouse",
//  the pointer speed, the wheel and the haptics follow. A row for something the mouse does
//  not have, or a macOS value that could not be read, is hidden. A muted line under the
//  switch says why the rows are greyed while it is off, and, while it is on, that a value
//  is not on the mouse, with "Send Again" (LogiCenter reads the mice again and writes what
//  differs, as on a reconnect).
//
//  The Logitech rows only edit Options.shared.logiMouse and Options.shared.logiWheel; the
//  Logi layer sends them to the mice (LogiUsageBootstrap). What the mice report comes in
//  with LogiCenter.mouseStateChanged. The macOS rows read the macOS settings when the pane
//  appears and when the app becomes active, and write them only when the user moves their
//  control (MacPointerSettings). What a mouse does during Gesture Navigation is in the
//  Gestures tab.
//

import Cocoa

final class MousePreferencesViewController: NSViewController {

    static let tabIdentifier = "mouse"

    /// Identifiers for the controls (tests and accessibility tooling).
    enum Identifier {
        static let header = NSUserInterfaceItemIdentifier("mouse-header")
        static let trackingSpeed = NSUserInterfaceItemIdentifier("mouse-macos-tracking-speed")
        static let pointerAcceleration = NSUserInterfaceItemIdentifier("mouse-macos-pointer-acceleration")
        static let managed = NSUserInterfaceItemIdentifier("mouse-managed")
        static let managedOffNote = NSUserInterfaceItemIdentifier("mouse-managed-off-note")
        static let notOnTheMouseNote = NSUserInterfaceItemIdentifier("mouse-not-on-mouse-note")
        static let sendAgain = NSUserInterfaceItemIdentifier("mouse-send-again")
        static let pointerSpeed = NSUserInterfaceItemIdentifier("mouse-pointer-speed")
        static let wheelMode = NSUserInterfaceItemIdentifier("mouse-wheel-mode")
        static let sensitivity = NSUserInterfaceItemIdentifier("mouse-wheel-sensitivity")
        static let firmness = NSUserInterfaceItemIdentifier("mouse-wheel-firmness")
        static let haptics = NSUserInterfaceItemIdentifier("mouse-haptics")
        static let strength = NSUserInterfaceItemIdentifier("mouse-haptics-strength")
        static let pressForce = NSUserInterfaceItemIdentifier("mouse-press-force")
    }

    /// As wide as the Scrolling tab: the sliders sit on the right of their rows.
    static let paneWidth: CGFloat = 520
    static var boxWidth: CGFloat {
        return PreferencesGroupedForm.boxWidth(paneWidth: paneWidth)
    }
    /// Room for "8000 DPI"; every slider of the tab gets it, so they line up.
    static let sliderValueWidth: CGFloat = 56

    // MARK: - State

    /// Where the mice come from; tests and renders replace it with fixtures.
    var deviceSource: MouseDeviceSource = .live

    /// The user's macOS pointer settings; tests and renders replace it.
    var pointerSettings: MacPointerSettings = .standard

    /// The macOS pointer settings as last read.
    private(set) var macPointer = MacPointerState()

    /// How long the "On the mouse" line of a setting the user just changed waits, so it does
    /// not flash up while the mouse takes the new value.
    var readbackSettleTime: TimeInterval = 1.5

    /// The connected mice as last read from `deviceSource`.
    private(set) var devices: [LogiMouseDeviceState] = []
    /// What the controls show.
    private(set) var model = MousePaneModel(devices: [], settings: .default, wheel: .default)

    /// When the user last changed each setting.
    private var changedAt: [MouseSetting: Date] = [:]
    private var settleWork: DispatchWorkItem?

    /// The part of the mouse whose row is under the pointer, and whose control has the focus.
    private(set) var hoveredPart: MousePart?
    private(set) var focusedPart: MousePart?
    private var firstResponderObservation: NSKeyValueObservation?

    // MARK: - Views (read access for tests)

    private(set) var headerView: MouseHeaderView!
    private(set) var macSection: PreferencesGroupSection!
    private(set) var managedSection: PreferencesGroupSection!
    private(set) var pointerSection: PreferencesGroupSection!
    private(set) var wheelSection: PreferencesGroupSection!
    private(set) var hapticsSection: PreferencesGroupSection!
    /// The muted lines under the switch: why the rows are greyed while it is off, and "a value
    /// is not on the mouse" with "Send Again" while it is on. At most one shows.
    private(set) var managedOffNote: NSView!
    private(set) var notOnTheMouseNote: NSView!
    private(set) var sendAgainButton: NSButton!

    private(set) var trackingSpeedRow: PreferencesSliderRow!
    private(set) var pointerAccelerationRow: PreferencesSwitchRow!
    private(set) var managedRow: PreferencesSwitchRow!
    private(set) var pointerSpeedRow: PreferencesSliderRow!
    private(set) var wheelModeRow: PreferencesGroupRow!
    private(set) var sensitivityRow: PreferencesSliderRow!
    private(set) var firmnessRow: PreferencesSliderRow!
    private(set) var hapticsRow: PreferencesSwitchRow!
    private(set) var strengthRow: PreferencesSliderRow!
    private(set) var pressForceRow: PreferencesSliderRow!

    private(set) var trackingSpeedSlider: NSSlider!
    private(set) var pointerAccelerationSwitch: NSSwitch!
    private(set) var managedSwitch: NSSwitch!
    private(set) var pointerSpeedSlider: NSSlider!
    private(set) var wheelModeControl: NSSegmentedControl!
    private(set) var sensitivitySlider: NSSlider!
    private(set) var firmnessSlider: NSSlider!
    private(set) var hapticsSwitch: NSSwitch!
    private(set) var strengthSlider: NSSlider!
    private(set) var pressForceSlider: NSSlider!

    /// Every row that lights up a part of the mouse, with that part.
    private(set) var rowParts: [(row: PreferencesGroupRow, part: MousePart)] = []

    /// The boxes and the header, top to bottom, as they sit in the content stack.
    private var contentStack: NSStackView!
    private var lastLayoutShape: [String] = []

    // MARK: - Lifecycle

    init() {
        super.init(nibName: nil, bundle: nil)
        title = MouseText.text("mouse-tab-title")
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        title = MouseText.text("mouse-tab-title")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        settleWork?.cancel()
    }

    override func loadView() {
        let root = PreferencesForm.makeBackground()
        let content = PreferencesGroupedForm.installContentStack(in: root, paneWidth: Self.paneWidth)
        // The pane is exactly as tall as what shows; the window shrinks with it.
        content.setHuggingPriority(.defaultHigh, for: .vertical)
        contentStack = content

        let header = MouseHeaderView()
        header.identifier = Identifier.header
        headerView = header

        let width = Self.boxWidth
        macSection = PreferencesGroupSection(
            title: MouseText.text("mouse-macos-header"), width: width,
            rows: [makeTrackingSpeedRow(), makePointerAccelerationRow()]
        )
        managedSection = PreferencesGroupSection(width: width, rows: [makeManagedRow()])
        managedOffNote = makeManagedOffNote()
        notOnTheMouseNote = makeNotOnTheMouseNote()
        pointerSection = PreferencesGroupSection(
            title: MouseText.text("mouse-pointer-header"), width: width, rows: [makePointerSpeedRow()]
        )
        wheelSection = PreferencesGroupSection(
            title: MouseText.text("mouse-wheel-label"), width: width,
            rows: [makeWheelModeRow(), makeSensitivityRow(), makeFirmnessRow()]
        )
        hapticsSection = PreferencesGroupSection(
            title: MouseText.text("mouse-haptics-header"), width: width,
            rows: [makeHapticsRow(), makeStrengthRow(), makePressForceRow()]
        )

        PreferencesGroupedForm.add(
            [header, macSection, managedSection, managedOffNote, notOnTheMouseNote, pointerSection, wheelSection, hapticsSection],
            to: content
        )

        // A refresh skips a pressed knob; a press let go without a move sends nothing, so
        // the pane shows here what arrived meanwhile (it only reads, nothing is written).
        for row in [trackingSpeedRow!, pointerSpeedRow!, sensitivityRow!, firmnessRow!, strengthRow!, pressForceRow!] {
            row.slider.onPressEndedWithoutAction = { [weak self] in self?.syncControls() }
        }

        rowParts = [
            (trackingSpeedRow, .body), (pointerAccelerationRow, .body),
            (pointerSpeedRow, .body),
            (wheelModeRow, .wheel), (sensitivityRow, .wheel), (firmnessRow, .wheel),
            (hapticsRow, .thumbPanel), (strengthRow, .thumbPanel), (pressForceRow, .thumbPanel),
        ]
        for (row, part) in rowParts {
            row.addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                owner: self,
                userInfo: [Self.hoverPartInfo: part.rawValue]
            ))
        }

        view = root
        macPointer = pointerSettings.read()
        syncControls()
        root.setFrameSize(root.fittingSize)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(mouseStateDidChange(_:)),
            name: LogiCenter.mouseStateChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive(_:)),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        // Show what is known right away, then ask the mice again; the answer arrives as
        // `mouseStateChanged`. The macOS settings may have changed in System Settings.
        macPointer = pointerSettings.read()
        reloadDevices()
        deviceSource.refresh()
    }

    /// Back from System Settings, say: the pane shows what macOS has now.
    @objc private func applicationDidBecomeActive(_ notification: Notification) {
        guard isViewLoaded, view.window != nil else { return }
        reloadMacPointerSettings()
    }

    /// The pane is in its window only now: opened from the sidebar it has none yet in
    /// `viewWillAppear`. From here on the focused control lights up its part.
    override func viewDidAppear() {
        super.viewDidAppear()
        firstResponderObservation = view.window?.observe(\.firstResponder, options: [.initial, .new]) { [weak self] window, _ in
            self?.firstResponderDidChange(window.firstResponder)
        }
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        firstResponderObservation = nil
        hoveredPart = nil
        focusedPart = nil
        updateEmphasis()
    }

    @objc private func mouseStateDidChange(_ notification: Notification) {
        if Thread.isMainThread {
            reloadDevices()
        } else {
            DispatchQueue.main.async { [weak self] in self?.reloadDevices() }
        }
    }

    // MARK: - Refresh

    /// Re-reads the macOS pointer settings and puts them into their controls.
    func reloadMacPointerSettings() {
        guard isViewLoaded else { return }
        macPointer = pointerSettings.read()
        syncControls()
    }

    /// Re-reads the mice and puts everything into the controls; the window follows a change
    /// of height.
    func reloadDevices() {
        guard isViewLoaded else { return }
        devices = deviceSource.deviceStates()
        syncControls()
    }

    /// Puts the stored settings and what the mice report into the controls. A slider the
    /// user is dragging keeps its knob where the pointer has it; every other one follows.
    func syncControls() {
        guard isViewLoaded else { return }
        let options = Options.shared
        let model = MousePaneModel(
            devices: devices,
            settings: options.logiMouse,
            wheel: options.logiWheel,
            heldReadbacks: heldReadbacks
        )
        self.model = model

        headerView.content = model.header
        applyMacPointer(MacPointerPaneModel(macPointer))
        managedSection.isHidden = !model.hasMouse
        managedRow.isOn = model.managed
        managedOffNote.isHidden = model.managedNote != .notManaged
        notOnTheMouseNote.isHidden = model.managedNote != .notOnTheMouse

        apply(model.pointerSpeed, to: pointerSpeedRow, hint: "mouse-pointer-speed-hint")

        if let mode = model.wheelMode {
            wheelModeRow.isHidden = false
            wheelModeControl.selectedSegment = MouseText.modes.firstIndex(of: mode.mode) ?? 0
            wheelModeRow.explanation = MouseText.explanation(MouseText.modeHint(mode.mode), readback: mode.readback)
            wheelModeRow.isEnabled = mode.isEnabled
        } else {
            wheelModeRow.isHidden = true
        }
        apply(model.sensitivity, to: sensitivityRow, hint: "mouse-wheel-sensitivity-hint")
        apply(model.firmness, to: firmnessRow, hint: "mouse-wheel-force-hint")

        if let haptics = model.haptics {
            hapticsRow.isHidden = false
            hapticsRow.isOn = haptics.isOn
            hapticsRow.explanation = MouseText.explanation(MouseText.text("mouse-haptics-hint"), readback: haptics.readback)
            hapticsRow.isEnabled = haptics.isEnabled
        } else {
            hapticsRow.isHidden = true
        }
        apply(model.strength, to: strengthRow, hint: "mouse-haptics-strength-hint")
        apply(model.pressForce, to: pressForceRow, hint: "mouse-press-force-hint")

        for section in [pointerSection!, wheelSection!, hapticsSection!] {
            section.isHidden = !model.hasMouse || section.box.visibleRows.isEmpty
        }
        updateEmphasis()
        // Only a row or a line that comes or goes changes the height: the window follows
        // then, not on every step of a slider.
        let shape = layoutShape
        if shape != lastLayoutShape {
            lastLayoutShape = shape
            updateSpacing()
            PreferencesForm.fitToContent(self)
        }
    }

    /// Every row of the tab, top to bottom.
    private var settingRows: [PreferencesGroupRow] {
        return [trackingSpeedRow, pointerAccelerationRow, managedRow, pointerSpeedRow, wheelModeRow,
                sensitivityRow, firmnessRow, hapticsRow, strengthRow, pressForceRow]
    }

    /// The "Pointer (macOS)" box. A knob the user is dragging stays where the pointer has it.
    /// VoiceOver reads the stop the knob is on ("4 of 10"): the slider shows no value.
    private func applyMacPointer(_ mac: MacPointerPaneModel) {
        if let index = mac.trackingSpeedIndex {
            trackingSpeedRow.isHidden = false
            if !trackingSpeedRow.isTracking {
                trackingSpeedSlider.doubleValue = Double(index)
            }
            trackingSpeedSlider.setAccessibilityValueDescription(
                MouseText.trackingSpeedStop(Int(trackingSpeedSlider.doubleValue.rounded()))
            )
        } else {
            trackingSpeedRow.isHidden = true
        }
        if let on = mac.pointerAcceleration {
            pointerAccelerationRow.isHidden = false
            pointerAccelerationRow.isOn = on
        } else {
            pointerAccelerationRow.isHidden = true
        }
        macSection.isHidden = mac.isEmpty
    }

    /// What decides the pane's height: which boxes, lines and rows show, and what each
    /// explanation says (an "On the mouse" line with its reason may wrap).
    private var layoutShape: [String] {
        let views: [NSView] = contentStack.arrangedSubviews + settingRows
        return views.map { $0.isHidden ? "0" : "1" } + settingRows.map { $0.explanation ?? "" }
    }

    private func apply(_ slider: MousePaneModel.Slider?, to row: PreferencesSliderRow, hint: String) {
        guard let slider else {
            row.isHidden = true
            return
        }
        row.isHidden = false
        let control = row.slider
        // Moving the range or the ticks would move the knob: not while the user drags it.
        // The knob goes to the tick nearest the value; the value itself is not rewritten.
        if !row.isTracking {
            if control.minValue != slider.range.lowerBound { control.minValue = slider.range.lowerBound }
            if control.maxValue != slider.range.upperBound { control.maxValue = slider.range.upperBound }
            if row.scale != slider.scale { row.scale = slider.scale }
            control.doubleValue = slider.position
            row.valueText = slider.valueText
        }
        row.explanation = MouseText.explanation(MouseText.text(hint), readback: slider.readback)
        row.isEnabled = slider.isEnabled
    }

    /// A titled box keeps a wider gap above it than an untitled one. Hidden views are left
    /// out of the stack, so the gaps are worked out from what shows.
    private func updateSpacing() {
        let views = contentStack.arrangedSubviews
        let shown = views.filter { !$0.isHidden }
        for view in views {
            contentStack.setCustomSpacing(PreferencesGroupedForm.boxSpacing, after: view)
        }
        for (above, below) in zip(shown, shown.dropFirst()) {
            // "Let Scrollio manage this mouse" starts the Logitech part: apart from the macOS box.
            let titled = (below as? PreferencesGroupSection)?.titleLabel != nil
                || (below === managedSection && above === macSection)
            // A muted line sits close under its box.
            let note = below === managedOffNote || below === notOnTheMouseNote
            contentStack.setCustomSpacing(
                note ? PreferencesGroupedForm.noteSpacing
                    : titled ? PreferencesGroupedForm.sectionSpacing : PreferencesGroupedForm.boxSpacing,
                after: above
            )
        }
    }

    // MARK: - "On the mouse" lines

    /// The settings changed so recently that the mouse may not have taken them yet.
    private var heldReadbacks: Set<MouseSetting> {
        let now = Date()
        return Set(changedAt.compactMap { setting, date in
            now.timeIntervalSince(date) < readbackSettleTime ? setting : nil
        })
    }

    /// Remembers that the user changed `settings`, and looks again once they have settled.
    private func noteUserChange(_ settings: [MouseSetting]) {
        let now = Date()
        for setting in settings {
            changedAt[setting] = now
        }
        settleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.settleWork = nil
            self?.syncControls()
        }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + readbackSettleTime, execute: work)
    }

    // MARK: - Emphasis

    /// The part the header lights up: the hovered row's, else the focused control's.
    var emphasis: MousePart? {
        return hoveredPart ?? focusedPart
    }

    private func updateEmphasis() {
        headerView.emphasis = model.hasMouse ? emphasis : nil
    }

    /// The pointer entered or left a row about `part`.
    func rowHoverChanged(_ part: MousePart, inside: Bool) {
        if inside {
            hoveredPart = part
        } else if hoveredPart == part {
            hoveredPart = nil
        }
        updateEmphasis()
    }

    /// The window's first responder changed: a control of a row may have the focus now.
    func firstResponderDidChange(_ responder: NSResponder?) {
        let view = responder as? NSView
        focusedPart = view.flatMap { view in
            rowParts.first { !$0.row.isHidden && view.isDescendant(of: $0.row) }?.part
        }
        updateEmphasis()
    }

    private static let hoverPartInfo = "mousePart"

    private static func part(of event: NSEvent) -> MousePart? {
        guard let raw = event.trackingArea?.userInfo?[hoverPartInfo] as? Int else { return nil }
        return MousePart(rawValue: raw)
    }

    override func mouseEntered(with event: NSEvent) {
        guard let part = Self.part(of: event) else { return super.mouseEntered(with: event) }
        rowHoverChanged(part, inside: true)
    }

    override func mouseExited(with event: NSEvent) {
        guard let part = Self.part(of: event) else { return super.mouseExited(with: event) }
        rowHoverChanged(part, inside: false)
    }

    // MARK: - Actions

    /// Writes the tick's tracking speed to macOS when the knob moved to another tick, then
    /// reads back what macOS has: a value macOS did not take puts the knob back on release.
    @objc func trackingSpeedChanged(_ sender: NSSlider) {
        let speeds = MacPointerSettings.trackingSpeeds
        let index = min(max(Int(sender.doubleValue.rounded()), 0), speeds.count - 1)
        guard index != MacPointerPaneModel(macPointer).trackingSpeedIndex else { return }
        _ = pointerSettings.writeTrackingSpeed(speeds[index])
        reloadMacPointerSettings()
    }

    @objc func pointerAccelerationToggled(_ sender: NSSwitch) {
        let on = sender.state == .on
        guard on != macPointer.pointerAcceleration else { return }
        _ = pointerSettings.writePointerAcceleration(on)
        reloadMacPointerSettings()
    }

    /// Only the switch changes: no value is taken over from a mouse. A setting the user never
    /// set stays unset, so the mouse keeps its own value (the rows show it); what the user did
    /// set is written where the mouse has something else.
    @objc func managedToggled(_ sender: NSSwitch) {
        let managed = sender.state == .on
        if managed != Options.shared.logiMouseManaged {
            Options.shared.logiMouseManaged = managed
        }
        noteUserChange(MouseSetting.allCases)
        syncControls()
    }

    /// "Send Again": LogiCenter reads the mice again and writes, as on a reconnect, only the
    /// values the user set that a mouse reports differently, only while managed. The lines
    /// wait like after a change, so the mice can answer before the pane says anything again.
    @objc func sendAgainClicked(_ sender: NSButton) {
        guard model.managed, model.managedNote == .notOnTheMouse else { return }
        deviceSource.sendAgain()
        noteUserChange(MouseSetting.allCases)
        reloadDevices()
    }

    @objc func pointerSpeedChanged(_ sender: NSSlider) {
        let choices = model.pointerChoices
        guard !choices.isEmpty else { return }
        let index = min(max(Int(sender.doubleValue.rounded()), 0), choices.count - 1)
        updateMouseSettings(.pointerSpeed) { $0.pointerDPI = choices[index] }
        pointerSpeedRow.valueText = MouseText.dpi(choices[index])
    }

    @objc func wheelModeChanged(_ sender: NSSegmentedControl) {
        guard MouseText.modes.indices.contains(sender.selectedSegment) else { return }
        let mode = MouseText.modes[sender.selectedSegment]
        updateWheelSettings(.wheelMode) { $0.mode = mode }
    }

    @objc func sensitivityChanged(_ sender: NSSlider) {
        let value = MousePaneModel.clamp(Int(sender.doubleValue.rounded()), to: LogiWheelSettings.sensitivityRange)
        updateWheelSettings(.sensitivity) { $0.smartShiftSensitivity = value }
        sensitivityRow.valueText = MouseText.percent(value)
    }

    @objc func firmnessChanged(_ sender: NSSlider) {
        let value = MousePaneModel.clamp(Int(sender.doubleValue.rounded()), to: LogiWheelSettings.scrollForceRange)
        updateWheelSettings(.firmness) { $0.scrollForce = value }
        firmnessRow.valueText = MouseText.percent(value)
    }

    @objc func hapticsToggled(_ sender: NSSwitch) {
        let on = sender.state == .on
        updateMouseSettings(.haptics) { $0.hapticsOn = on }
    }

    /// Stores the strength as it moves; once the slider is let go (its last action, no
    /// longer tracking) or an arrow key moved it, the mouse plays one pulse at the new
    /// strength.
    @objc func strengthChanged(_ sender: NSSlider) {
        let value: Int
        if let choices = model.strengthChoices, !choices.isEmpty {
            value = choices[min(max(Int(sender.doubleValue.rounded()), 0), choices.count - 1)]
        } else {
            value = MousePaneModel.clamp(Int(sender.doubleValue.rounded()), to: LogiMouseSettings.hapticStrengthRange)
        }
        updateMouseSettings(.strength) { $0.hapticStrength = value }
        strengthRow.valueText = MouseText.percent(value)
        if !strengthRow.isTracking {
            deviceSource.playHapticSample()
        }
    }

    /// A tick between two whole units of the mouse writes the nearer one.
    @objc func pressForceChanged(_ sender: NSSlider) {
        guard let range = model.pressForceRange else { return }
        let value = MousePaneModel.clamp(Int(sender.doubleValue.rounded()), to: range)
        updateMouseSettings(.pressForce) { $0.pressForce = value }
        pressForceRow.valueText = MouseText.percent(MousePaneModel.share(of: value, in: range))
    }

    private func updateMouseSettings(_ setting: MouseSetting, _ change: (inout LogiMouseSettings) -> Void) {
        var settings = Options.shared.logiMouse
        change(&settings)
        if settings != Options.shared.logiMouse {
            Options.shared.logiMouse = settings
        }
        noteUserChange([setting])
        syncControls()
    }

    private func updateWheelSettings(_ setting: MouseSetting, _ change: (inout LogiWheelSettings) -> Void) {
        var settings = Options.shared.logiWheel
        change(&settings)
        if settings != Options.shared.logiWheel {
            Options.shared.logiWheel = settings
        }
        noteUserChange([setting])
        syncControls()
    }

    // MARK: - Rows

    /// System Settings › Mouse › Tracking speed: its ten stops, slow to fast. No value is
    /// written next to it (macOS shows none), but it keeps the value column, so it lines up
    /// with the Logitech sliders.
    private func makeTrackingSpeedRow() -> PreferencesGroupRow {
        let row = PreferencesSliderRow(
            title: MouseText.text("mouse-macos-tracking-speed"),
            explanation: MouseText.text("mouse-macos-tracking-speed-hint"),
            range: MacPointerPaneModel.trackingSpeedRange,
            scale: MacPointerPaneModel.trackingSpeedScale,
            ends: (low: MouseText.text("mouse-macos-tracking-speed-slow"), high: MouseText.text("mouse-macos-tracking-speed-fast")),
            valueWidth: Self.sliderValueWidth,
            target: self,
            action: #selector(trackingSpeedChanged(_:))
        )
        row.slider.identifier = Identifier.trackingSpeed
        trackingSpeedRow = row
        trackingSpeedSlider = row.slider
        return row
    }

    private func makePointerAccelerationRow() -> PreferencesGroupRow {
        let row = PreferencesSwitchRow(
            title: MouseText.text("mouse-macos-acceleration"),
            explanation: MouseText.text("mouse-macos-acceleration-hint"),
            target: self,
            action: #selector(pointerAccelerationToggled(_:))
        )
        row.toggle.identifier = Identifier.pointerAcceleration
        pointerAccelerationRow = row
        pointerAccelerationSwitch = row.toggle
        return row
    }

    private func makeManagedRow() -> PreferencesGroupRow {
        let row = PreferencesSwitchRow(
            title: MouseText.text("mouse-wheel-managed"),
            explanation: MouseText.text("mouse-wheel-managed-hint"),
            target: self,
            action: #selector(managedToggled(_:))
        )
        row.toggle.identifier = Identifier.managed
        managedRow = row
        managedSwitch = row.toggle
        return row
    }

    /// "Turn this on to change the settings below. …", under the switch at the rows' inset.
    private func makeManagedOffNote() -> NSView {
        let label = Self.makeNote(MouseText.managedNote(.notManaged))
        label.identifier = Identifier.managedOffNote
        label.preferredMaxLayoutWidth = Self.boxWidth - 2 * PreferencesGroupedForm.rowHorizontalInset
        let holder = NSView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        holder.isHidden = true
        holder.addSubview(label)
        let inset = PreferencesGroupedForm.rowHorizontalInset
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: inset),
            label.trailingAnchor.constraint(lessThanOrEqualTo: holder.trailingAnchor, constant: -inset),
            label.topAnchor.constraint(equalTo: holder.topAnchor),
            label.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
        ])
        return holder
    }

    /// "Some values you set are not on the mouse." at the rows' inset, "Send Again" (small) at
    /// the right edge of the box above, in the column of its switch: as the Gestures tab puts
    /// "Open Mouse" under its Logitech box.
    private func makeNotOnTheMouseNote() -> NSView {
        let label = Self.makeNote(MouseText.managedNote(.notOnTheMouse))
        label.identifier = Identifier.notOnTheMouseNote
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let button = PreferencesGroupedForm.makePushButton(
            title: MouseText.text("mouse-send-again"),
            target: self,
            action: #selector(sendAgainClicked(_:))
        )
        button.controlSize = .small
        button.font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small))
        button.identifier = Identifier.sendAgain
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.toolTip = MouseText.text("mouse-send-again-help")
        button.setAccessibilityHelp(MouseText.text("mouse-send-again-help"))
        sendAgainButton = button

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

    /// A muted line under a box, in the explanations' style.
    private static func makeNote(_ string: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: string)
        label.font = PreferencesGroupedForm.explanationFont
        label.textColor = PreferencesGroupedForm.explanationColor(enabled: true)
        label.isSelectable = false
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func makePointerSpeedRow() -> PreferencesGroupRow {
        let row = makeSliderRow(
            titleKey: "mouse-pointer-speed",
            hintKey: "mouse-pointer-speed-hint",
            ends: ("mouse-pointer-speed-slower", "mouse-pointer-speed-faster"),
            identifier: Identifier.pointerSpeed,
            action: #selector(pointerSpeedChanged(_:))
        )
        pointerSpeedRow = row
        pointerSpeedSlider = row.slider
        return row
    }

    /// The title and a line on the chosen mode, the three modes under them across the box.
    private func makeWheelModeRow() -> PreferencesGroupRow {
        let control = NSSegmentedControl(
            labels: MouseText.modes.map(MouseText.modeName),
            trackingMode: .selectOne,
            target: self,
            action: #selector(wheelModeChanged(_:))
        )
        control.identifier = Identifier.wheelMode
        control.segmentDistribution = .fillEqually
        wheelModeControl = control
        let row = PreferencesGroupRow(
            title: MouseText.text("mouse-wheel-mode-label"),
            explanation: MouseText.modeHint(.smartShift),
            accessory: control,
            placement: .below
        )
        // Room for the longest line, so picking another mode never changes the height.
        row.reservedExplanations = MouseText.modes.map(MouseText.modeHint)
        wheelModeRow = row
        return row
    }

    private func makeSensitivityRow() -> PreferencesGroupRow {
        let row = makeSliderRow(
            titleKey: "mouse-wheel-sensitivity-label",
            hintKey: "mouse-wheel-sensitivity-hint",
            ends: ("mouse-wheel-sensitivity-later", "mouse-wheel-sensitivity-sooner"),
            identifier: Identifier.sensitivity,
            action: #selector(sensitivityChanged(_:))
        )
        sensitivityRow = row
        sensitivitySlider = row.slider
        return row
    }

    private func makeFirmnessRow() -> PreferencesGroupRow {
        let row = makeSliderRow(
            titleKey: "mouse-wheel-force-label",
            hintKey: "mouse-wheel-force-hint",
            ends: ("mouse-wheel-force-soft", "mouse-wheel-force-firm"),
            identifier: Identifier.firmness,
            action: #selector(firmnessChanged(_:))
        )
        firmnessRow = row
        firmnessSlider = row.slider
        return row
    }

    private func makeHapticsRow() -> PreferencesGroupRow {
        let row = PreferencesSwitchRow(
            title: MouseText.text("mouse-haptics"),
            explanation: MouseText.text("mouse-haptics-hint"),
            target: self,
            action: #selector(hapticsToggled(_:))
        )
        row.toggle.identifier = Identifier.haptics
        hapticsRow = row
        hapticsSwitch = row.toggle
        return row
    }

    private func makeStrengthRow() -> PreferencesGroupRow {
        let row = makeSliderRow(
            titleKey: "mouse-haptics-strength",
            hintKey: "mouse-haptics-strength-hint",
            ends: ("mouse-haptics-strength-light", "mouse-haptics-strength-strong"),
            identifier: Identifier.strength,
            action: #selector(strengthChanged(_:))
        )
        strengthRow = row
        strengthSlider = row.slider
        return row
    }

    private func makePressForceRow() -> PreferencesGroupRow {
        let row = makeSliderRow(
            titleKey: "mouse-press-force",
            hintKey: "mouse-press-force-hint",
            ends: ("mouse-press-force-light", "mouse-press-force-firm"),
            identifier: Identifier.pressForce,
            action: #selector(pressForceChanged(_:))
        )
        pressForceRow = row
        pressForceSlider = row.slider
        return row
    }

    /// A slider with words under its ends and its value on the right. The tab's sliders all
    /// have the same width and value column, so they line up. Each gets its range and tick
    /// marks from the model when the mice are known.
    private func makeSliderRow(
        titleKey: String,
        hintKey: String,
        ends: (low: String, high: String),
        identifier: NSUserInterfaceItemIdentifier,
        action: Selector
    ) -> PreferencesSliderRow {
        let row = PreferencesSliderRow(
            title: MouseText.text(titleKey),
            explanation: MouseText.text(hintKey),
            range: MousePaneModel.percentSliderRange,
            scale: MousePaneModel.percentScale,
            ends: (low: MouseText.text(ends.low), high: MouseText.text(ends.high)),
            valueWidth: Self.sliderValueWidth,
            target: self,
            action: action
        )
        row.slider.identifier = identifier
        return row
    }
}
