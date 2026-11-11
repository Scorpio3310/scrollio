//
//  GesturesPreferencesViewController.swift
//  Mos
//  "Gestures" preferences tab: everything about Gesture Navigation in one place. The
//  mode, the action per direction and click, invert left/right, freeze pointer and the
//  tracking speed come from MouseGestureSettingsControls (shared with the popover in the
//  Buttons tab); the "Logitech" section holds what a mouse may do itself during a
//  gesture. Built in code on the PreferencesForm grid. It only edits Options.shared.gesture.
//

import Cocoa

final class GesturesPreferencesViewController: NSViewController {

    static let tabIdentifier = "gestures"

    /// Between rows of one group that carry no hints (the five action rows, two checkboxes).
    private static let groupedRowSpacing: CGFloat = 8
    /// Between a section header and its first row.
    private static let headerSpacing: CGFloat = 12

    // MARK: - State

    /// What the connected mice can do; tests and screenshots replace it with fixtures.
    var deviceSource: MouseGestureDeviceSource = .live
    /// Which buttons use Gesture Navigation; tests and screenshots replace it with fixtures.
    var bindingSummary: () -> MouseGestureBindingSummary = { .current }

    /// As last read from `deviceSource`.
    private(set) var gestureSupport = MouseGestureDeviceSupport.none

    private let isInteractiveAvailable: () -> Bool

    // MARK: - Views (read access for tests)

    /// Mode, action popups, invert, freeze and tracking speed.
    private(set) var controls: MouseGestureSettingsControls!
    private(set) var actionsHintLabel: NSTextField!
    private(set) var trackingSpeedHintLabel: NSTextField!
    private(set) var logitechHeaderLabel: NSTextField!
    private(set) var deviceTrackingCheckbox: NSButton!
    private(set) var deviceTrackingHintLabel: NSTextField!
    private(set) var hapticsCheckbox: NSButton!
    private(set) var hapticsHintLabel: NSTextField!

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
        let content = PreferencesForm.installContentStack(in: root)

        controls = MouseGestureSettingsControls(
            showLogiActions: bindingSummary().hasLogitechGestureButton,
            isInteractiveAvailable: isInteractiveAvailable
        )

        let modeRow = makeModeRow()
        let actionRows = makeActionRows()
        let optionsRow = makeOptionsRow()
        let trackingSpeedRow = makeTrackingSpeedRow()
        logitechHeaderLabel = PreferencesForm.makeSectionHeader(NSLocalizedString("gestures-logitech-header", comment: ""))
        let logitechRow = makeLogitechRow()

        var rows: [NSView] = [modeRow, PreferencesForm.makeSeparator()]
        rows.append(contentsOf: actionRows)
        rows.append(contentsOf: [
            PreferencesForm.makeSeparator(), optionsRow, trackingSpeedRow,
            PreferencesForm.makeSeparator(), logitechHeaderLabel, logitechRow,
        ])
        PreferencesForm.add(rows, to: content)
        PreferencesForm.applySeparatorSpacing(in: content)
        for row in actionRows.dropLast() {
            content.setCustomSpacing(Self.groupedRowSpacing, after: row)
        }
        content.setCustomSpacing(Self.headerSpacing, after: logitechHeaderLabel)

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

    @objc private func deviceStateDidChange(_ notification: Notification) {
        if Thread.isMainThread {
            reload()
        } else {
            DispatchQueue.main.async { [weak self] in self?.reload() }
        }
    }

    // MARK: - Refresh

    /// Puts the stored settings, the bindings and the device rules into the controls,
    /// then refits the window if the height changed.
    func reload() {
        guard controls != nil else { return }
        let summary = bindingSummary()
        controls.showLogiActions = summary.hasLogitechGestureButton
        controls.sync()
        actionsHintLabel.stringValue = NSLocalizedString(summary.actionsHintKey, comment: "")

        gestureSupport = deviceSource.support()
        let gesture = Options.shared.gesture
        let rules = MouseGestureControlRules(support: gestureSupport)
        deviceTrackingCheckbox.state = gesture.deviceTracking ? .on : .off
        deviceTrackingCheckbox.isEnabled = rules.deviceTrackingEnabled
        deviceTrackingHintLabel.stringValue = NSLocalizedString(rules.deviceTrackingHintKey, comment: "")
        hapticsCheckbox.state = gesture.hapticFeedback ? .on : .off
        hapticsCheckbox.isEnabled = rules.hapticsEnabled
        hapticsHintLabel.stringValue = NSLocalizedString(rules.hapticsHintKey, comment: "")

        if isViewLoaded {
            PreferencesForm.fitToContent(self)
        }
    }

    // MARK: - Actions

    @objc func deviceTrackingToggled(_ sender: NSButton) {
        let enabled = sender.state == .on
        if Options.shared.gesture.deviceTracking != enabled {
            Options.shared.gesture.deviceTracking = enabled
        }
        reload()
    }

    @objc func hapticsToggled(_ sender: NSButton) {
        let enabled = sender.state == .on
        if Options.shared.gesture.hapticFeedback != enabled {
            Options.shared.gesture.hapticFeedback = enabled
        }
        reload()
    }

    // MARK: - Rows

    private func makeModeRow() -> NSView {
        let mode = controls.modeControl
        // As wide as the control column, like the action popups under it.
        mode.segmentDistribution = .fillProportionally
        mode.translatesAutoresizingMaskIntoConstraints = false
        mode.widthAnchor.constraint(equalToConstant: PreferencesForm.controlWidth).isActive = true

        let note = controls.modeNote
        note.font = PreferencesForm.hintFont
        note.preferredMaxLayoutWidth = PreferencesForm.controlWidth

        let column = PreferencesForm.makeColumn([mode, note])
        let (row, label) = PreferencesForm.makeRow(
            title: NSLocalizedString("gesture-mode-label", comment: ""),
            column: column
        )
        label.firstBaselineAnchor.constraint(equalTo: mode.firstBaselineAnchor).isActive = true
        return row
    }

    /// One row per direction and one for the click; the hint under the last one says how
    /// a gesture is made, or that no button is set up for it yet.
    private func makeActionRows() -> [NSView] {
        actionsHintLabel = PreferencesForm.makeHint("")
        let slots = MouseGestureSettingsControls.Slot.allCases
        return slots.map { slot in
            let popup = controls.actionPopUp(for: slot)
            popup.widthAnchor.constraint(equalToConstant: PreferencesForm.controlWidth).isActive = true
            let views: [NSView] = slot == slots.last ? [popup, actionsHintLabel] : [popup]
            let (row, label) = PreferencesForm.makeRow(
                title: NSLocalizedString(slot.labelKey, comment: ""),
                column: PreferencesForm.makeColumn(views)
            )
            label.firstBaselineAnchor.constraint(equalTo: popup.firstBaselineAnchor).isActive = true
            return row
        }
    }

    private func makeOptionsRow() -> NSView {
        let invert = controls.invertCheckbox
        let freeze = controls.freezeCheckbox
        for checkbox in [invert, freeze] {
            PreferencesForm.fitInControlColumn(checkbox)
        }
        let column = PreferencesForm.makeColumn([invert, freeze])
        column.spacing = Self.groupedRowSpacing
        let (row, label) = PreferencesForm.makeRow(
            title: NSLocalizedString("gesture-options-label", comment: ""),
            column: column
        )
        label.firstBaselineAnchor.constraint(equalTo: invert.firstBaselineAnchor).isActive = true
        return row
    }

    private func makeTrackingSpeedRow() -> NSView {
        trackingSpeedHintLabel = PreferencesForm.makeHint(NSLocalizedString("gesture-tracking-speed-hint", comment: ""))
        let column = PreferencesForm.makeColumn([controls.trackingSpeedLine, trackingSpeedHintLabel])
        let (row, label) = PreferencesForm.makeRow(
            title: NSLocalizedString("gesture-tracking-speed-label", comment: ""),
            column: column
        )
        label.centerYAnchor.constraint(equalTo: controls.trackingSpeedSlider.centerYAnchor).isActive = true
        return row
    }

    /// Two switches that only make sense with a mouse that can do them. The hint under
    /// each turns into the reason when no such mouse is connected.
    private func makeLogitechRow() -> NSView {
        let tracking = PreferencesForm.makeCheckbox(
            title: NSLocalizedString("mouse-gesture-device-tracking", comment: ""),
            target: self,
            action: #selector(deviceTrackingToggled(_:))
        )
        deviceTrackingCheckbox = tracking
        deviceTrackingHintLabel = PreferencesForm.makeHint(NSLocalizedString("mouse-gesture-device-tracking-hint", comment: ""))

        let haptics = PreferencesForm.makeCheckbox(
            title: NSLocalizedString("mouse-gesture-haptics", comment: ""),
            target: self,
            action: #selector(hapticsToggled(_:))
        )
        hapticsCheckbox = haptics
        hapticsHintLabel = PreferencesForm.makeHint(NSLocalizedString("mouse-gesture-haptics-hint", comment: ""))

        let column = PreferencesForm.makeColumn([tracking, deviceTrackingHintLabel, haptics, hapticsHintLabel])
        column.setCustomSpacing(PreferencesForm.optionSpacing, after: deviceTrackingHintLabel)
        let (row, label) = PreferencesForm.makeRow(
            title: NSLocalizedString("gestures-logitech-row-label", comment: ""),
            column: column
        )
        label.firstBaselineAnchor.constraint(equalTo: tracking.firstBaselineAnchor).isActive = true
        return row
    }

    // MARK: - Toolbar

    /// Toolbar image, the size of the SF.* assets of the storyboard tabs.
    static func tabImage() -> NSImage {
        return PreferencesForm.toolbarImage(
            symbolName: "hand.draw",
            accessibilityDescription: NSLocalizedString("gestures-tab-title", comment: ""),
            glyphHeight: 0.72
        ) { _ in
            // macOS 10.13-10.15: a swipe, drawn as an arc that ends in an arrowhead.
            let arc = NSBezierPath()
            arc.move(to: NSPoint(x: 30, y: 50))
            arc.curve(to: NSPoint(x: 100, y: 70), controlPoint1: NSPoint(x: 50, y: 95), controlPoint2: NSPoint(x: 80, y: 95))
            arc.lineWidth = 7
            arc.lineCapStyle = .round
            arc.stroke()
            let head = NSBezierPath()
            head.move(to: NSPoint(x: 84, y: 62))
            head.line(to: NSPoint(x: 101, y: 69))
            head.line(to: NSPoint(x: 104, y: 88))
            head.lineWidth = 7
            head.lineCapStyle = .round
            head.lineJoinStyle = .round
            head.stroke()
        }
    }
}
