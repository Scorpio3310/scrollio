//
//  MousePreferencesViewController.swift
//  Mos
//  "Mouse" preferences tab: hardware settings of connected Logitech mice
//  (scroll mode, SmartShift sensitivity, scrolling force). Built in code on the
//  PreferencesForm grid, like the storyboard tabs. It only edits Options.shared.logiWheel;
//  the Logi layer applies it to the mice. What a mouse does during Gesture Navigation
//  is in the Gestures tab.
//

import Cocoa

final class MousePreferencesViewController: NSViewController {

    static let tabIdentifier = "mouse"

    // MARK: - Layout (the PreferencesForm grid)

    /// Width of every preferences tab.
    static let contentWidth = PreferencesForm.contentWidth
    private static let controlWidth = PreferencesForm.controlWidth
    private static let separatorSpacing = PreferencesForm.separatorSpacing
    private static let noteSpacing = PreferencesForm.hintSpacing

    // MARK: - State

    /// Device data source; tests and screenshots replace it with fixtures.
    var deviceSource: MouseWheelDeviceSource = .live

    /// Connected mice as last read from `deviceSource`.
    private(set) var devices: [LogiWheelDeviceState] = []

    // MARK: - Views (read access for tests)

    private(set) var deviceListColumn: NSStackView!
    private(set) var deviceEntryViews: [NSView] = []
    private(set) var emptyStateView: NSView!
    private(set) var managedCheckbox: NSButton!
    private(set) var modeControl: NSSegmentedControl!
    private(set) var modeReadbackLabel: NSTextField!
    private(set) var sensitivitySlider: NSSlider!
    private(set) var sensitivityValueLabel: NSTextField!
    private(set) var sensitivityReadbackLabel: NSTextField!
    private(set) var scrollForceSlider: NSSlider!
    private(set) var scrollForceValueLabel: NSTextField!
    private(set) var scrollForceReadbackLabel: NSTextField!
    private(set) var diagnosticsButton: NSButton!

    private var devicesRowLabel: NSTextField!
    private var emptyStateTitle: NSTextField!
    private var devicesLabelBaseline: NSLayoutConstraint?

    // MARK: - Lifecycle

    init() {
        super.init(nibName: nil, bundle: nil)
        title = NSLocalizedString("mouse-tab-title", comment: "")
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        title = NSLocalizedString("mouse-tab-title", comment: "")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func loadView() {
        let root = PreferencesForm.makeBackground()
        let content = PreferencesForm.installContentStack(in: root)

        let devicesRow = makeDevicesRow()
        let separator1 = Self.makeSeparator()
        let managedRow = makeManagedRow()
        let modeRow = makeModeRow()
        let sensitivityRow = makeSensitivityRow()
        let forceRow = makeScrollForceRow()
        let separator2 = Self.makeSeparator()
        let advancedRow = makeAdvancedRow()

        PreferencesForm.add([
            devicesRow, separator1, managedRow, modeRow, sensitivityRow, forceRow,
            separator2, advancedRow,
        ], to: content)
        for separator in [separator1, separator2] {
            content.setCustomSpacing(Self.separatorSpacing, after: separator)
        }
        content.setCustomSpacing(Self.separatorSpacing, after: devicesRow)
        content.setCustomSpacing(Self.separatorSpacing, after: forceRow)

        view = root
        rebuildDeviceList()
        syncControls()
        root.setFrameSize(root.fittingSize)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceStateDidChange(_:)),
            name: LogiCenter.wheelStateChanged,
            object: nil
        )
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        // Show what is known right away, then ask the mice again; the answer
        // arrives as `wheelStateChanged`.
        reloadDevices()
        deviceSource.refresh()
    }

    @objc private func deviceStateDidChange(_ notification: Notification) {
        if Thread.isMainThread {
            reloadDevices()
        } else {
            DispatchQueue.main.async { [weak self] in self?.reloadDevices() }
        }
    }

    // MARK: - Refresh

    /// Re-reads the device list and settings, then refits the window if the height changed.
    func reloadDevices() {
        guard isViewLoaded else { return }
        let newDevices = deviceSource.deviceStates()
        if newDevices != devices {
            devices = newDevices
            rebuildDeviceList()
        }
        syncControls()
        fitToContent()
    }

    /// Puts the stored settings, enabling rules and device read-backs into the controls.
    func syncControls() {
        guard isViewLoaded else { return }
        let settings = Options.shared.logiWheel
        let rules = MouseWheelControlRules(settings: settings, devices: devices)

        managedCheckbox.state = settings.managedByMos ? .on : .off

        modeControl.selectedSegment = MouseWheelText.modes.firstIndex(of: settings.mode) ?? 0
        modeControl.isEnabled = rules.modeEnabled

        // A device update arriving mid-drag must not snap the knob back.
        if !Self.isTrackingMouse {
            sensitivitySlider.integerValue = settings.smartShiftSensitivity
            sensitivityValueLabel.stringValue = MouseWheelText.percent(settings.smartShiftSensitivity)
            scrollForceSlider.integerValue = settings.scrollForce
            scrollForceValueLabel.stringValue = MouseWheelText.percent(settings.scrollForce)
        }
        sensitivitySlider.isEnabled = rules.sensitivityEnabled
        sensitivityValueLabel.textColor = rules.sensitivityEnabled ? .labelColor : .tertiaryLabelColor
        scrollForceSlider.isEnabled = rules.scrollForceEnabled
        scrollForceValueLabel.textColor = rules.scrollForceEnabled ? .labelColor : .tertiaryLabelColor

        Self.setNote(modeReadbackLabel, MouseWheelText.modeReadback(devices))
        Self.setNote(sensitivityReadbackLabel, MouseWheelText.sensitivityReadback(devices))
        Self.setNote(scrollForceReadbackLabel, MouseWheelText.scrollForceReadback(devices))
    }

    /// Keeps the frame at the content size; when the tab is on screen the window follows.
    private func fitToContent() {
        PreferencesForm.fitToContent(self)
    }

    // MARK: - Actions

    @objc func managedToggled(_ sender: NSButton) {
        let managed = sender.state == .on
        updateSettings { $0.managedByMos = managed }
    }

    @objc func modeChanged(_ sender: NSSegmentedControl) {
        guard MouseWheelText.modes.indices.contains(sender.selectedSegment) else { return }
        let mode = MouseWheelText.modes[sender.selectedSegment]
        updateSettings { $0.mode = mode }
    }

    @objc func sensitivityChanged(_ sender: NSSlider) {
        let value = Self.sliderValue(sender, in: LogiWheelSettings.sensitivityRange)
        sensitivityValueLabel.stringValue = MouseWheelText.percent(value)
        // Store once the drag ends, so the mouse is not rewritten on every step.
        guard !Self.isTrackingMouse else { return }
        updateSettings { $0.smartShiftSensitivity = value }
    }

    @objc func scrollForceChanged(_ sender: NSSlider) {
        let value = Self.sliderValue(sender, in: LogiWheelSettings.scrollForceRange)
        scrollForceValueLabel.stringValue = MouseWheelText.percent(value)
        guard !Self.isTrackingMouse else { return }
        updateSettings { $0.scrollForce = value }
    }

    @objc func diagnosticsClicked(_ sender: NSButton) {
        deviceSource.showDiagnostics()
    }

    private func updateSettings(_ change: (inout LogiWheelSettings) -> Void) {
        var settings = Options.shared.logiWheel
        change(&settings)
        if settings != Options.shared.logiWheel {
            Options.shared.logiWheel = settings
        }
        syncControls()
    }

    private static func sliderValue(_ slider: NSSlider, in range: ClosedRange<Int>) -> Int {
        let value = Int(slider.doubleValue.rounded())
        return min(max(value, range.lowerBound), range.upperBound)
    }

    /// True while the slider is being dragged (continuous actions in between).
    private static var isTrackingMouse: Bool {
        return PreferencesForm.isTrackingMouse
    }

    // MARK: - Rows

    private func makeDevicesRow() -> NSView {
        let column = Self.makeColumn([])
        column.spacing = 10
        deviceListColumn = column

        emptyStateTitle = NSTextField(wrappingLabelWithString: NSLocalizedString("mouse-devices-empty", comment: ""))
        emptyStateTitle.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        emptyStateTitle.textColor = .secondaryLabelColor
        emptyStateTitle.preferredMaxLayoutWidth = Self.controlWidth
        emptyStateTitle.isSelectable = false
        let emptyHint = Self.makeNote(NSLocalizedString("mouse-devices-empty-hint", comment: ""))
        let empty = Self.makeColumn([emptyStateTitle, emptyHint])
        empty.spacing = Self.noteSpacing
        emptyStateView = empty

        let (row, label) = Self.makeRow(
            title: NSLocalizedString("mouse-devices-label", comment: ""),
            column: column
        )
        devicesRowLabel = label
        return row
    }

    private func rebuildDeviceList() {
        for view in deviceListColumn.arrangedSubviews {
            deviceListColumn.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        deviceEntryViews = []

        let firstLine: NSView
        if devices.isEmpty {
            deviceListColumn.addArrangedSubview(emptyStateView)
            firstLine = emptyStateTitle
        } else {
            var nameLabels: [NSTextField] = []
            for device in devices {
                let (entry, name) = Self.makeDeviceEntry(device)
                deviceListColumn.addArrangedSubview(entry)
                deviceEntryViews.append(entry)
                nameLabels.append(name)
            }
            firstLine = nameLabels[0]
        }

        devicesLabelBaseline?.isActive = false
        devicesLabelBaseline = devicesRowLabel.firstBaselineAnchor.constraint(equalTo: firstLine.firstBaselineAnchor)
        devicesLabelBaseline?.isActive = true
    }

    private static func makeDeviceEntry(_ device: LogiWheelDeviceState) -> (entry: NSView, name: NSTextField) {
        let name = NSTextField(labelWithString: device.deviceName)
        name.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        name.lineBreakMode = .byTruncatingTail
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let detail = NSTextField(labelWithString: MouseWheelText.capabilities(of: device))
        detail.font = noteFont
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let text = NSStackView(views: [name, detail])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2

        var views: [NSView] = []
        if let icon = deviceIcon() {
            let imageView = NSImageView(image: icon)
            imageView.imageScaling = .scaleProportionallyUpOrDown
            if #available(macOS 10.14, *) { imageView.contentTintColor = .secondaryLabelColor }
            imageView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                imageView.widthAnchor.constraint(equalToConstant: 18),
                imageView.heightAnchor.constraint(equalToConstant: 22),
            ])
            views.append(imageView)
        }
        views.append(text)

        let entry = NSStackView(views: views)
        entry.orientation = .horizontal
        entry.alignment = .centerY
        entry.spacing = 7
        entry.translatesAutoresizingMaskIntoConstraints = false
        entry.widthAnchor.constraint(lessThanOrEqualToConstant: controlWidth).isActive = true
        entry.setAccessibilityElement(true)
        entry.setAccessibilityRole(.group)
        entry.setAccessibilityLabel("\(device.deviceName), \(MouseWheelText.capabilities(of: device))")
        return (entry, name)
    }

    private func makeManagedRow() -> NSView {
        let checkbox = NSButton(
            checkboxWithTitle: NSLocalizedString("mouse-wheel-managed", comment: ""),
            target: self,
            action: #selector(managedToggled(_:))
        )
        managedCheckbox = checkbox
        let hint = Self.makeNote(NSLocalizedString("mouse-wheel-managed-hint", comment: ""))
        let column = Self.makeColumn([checkbox, hint])
        let (row, label) = Self.makeRow(
            title: NSLocalizedString("mouse-wheel-label", comment: ""),
            column: column
        )
        label.firstBaselineAnchor.constraint(equalTo: checkbox.firstBaselineAnchor).isActive = true
        return row
    }

    private func makeModeRow() -> NSView {
        let control = NSSegmentedControl(
            labels: MouseWheelText.modes.map(MouseWheelText.modeName),
            trackingMode: .selectOne,
            target: self,
            action: #selector(modeChanged(_:))
        )
        control.translatesAutoresizingMaskIntoConstraints = false
        control.widthAnchor.constraint(lessThanOrEqualToConstant: Self.controlWidth).isActive = true
        modeControl = control
        modeReadbackLabel = Self.makeNote("")

        let title = NSLocalizedString("mouse-wheel-mode-label", comment: "")
        control.setAccessibilityLabel(title)
        let column = Self.makeColumn([control, modeReadbackLabel])
        let (row, label) = Self.makeRow(title: title, column: column)
        label.firstBaselineAnchor.constraint(equalTo: control.firstBaselineAnchor).isActive = true
        return row
    }

    private func makeSensitivityRow() -> NSView {
        let title = NSLocalizedString("mouse-wheel-sensitivity-label", comment: "")
        let (slider, valueLabel, line) = makeSliderLine(
            range: LogiWheelSettings.sensitivityRange,
            action: #selector(sensitivityChanged(_:)),
            accessibilityLabel: title
        )
        sensitivitySlider = slider
        sensitivityValueLabel = valueLabel
        let hint = Self.makeNote(NSLocalizedString("mouse-wheel-sensitivity-hint", comment: ""))
        sensitivityReadbackLabel = Self.makeNote("")
        let column = Self.makeColumn([line, hint, sensitivityReadbackLabel])
        column.setCustomSpacing(2, after: hint)
        let (row, label) = Self.makeRow(title: title, column: column)
        label.centerYAnchor.constraint(equalTo: slider.centerYAnchor).isActive = true
        return row
    }

    private func makeScrollForceRow() -> NSView {
        let title = NSLocalizedString("mouse-wheel-force-label", comment: "")
        let (slider, valueLabel, line) = makeSliderLine(
            range: LogiWheelSettings.scrollForceRange,
            action: #selector(scrollForceChanged(_:)),
            accessibilityLabel: title
        )
        scrollForceSlider = slider
        scrollForceValueLabel = valueLabel
        let hint = Self.makeNote(NSLocalizedString("mouse-wheel-force-hint", comment: ""))
        scrollForceReadbackLabel = Self.makeNote("")
        let column = Self.makeColumn([line, hint, scrollForceReadbackLabel])
        column.setCustomSpacing(2, after: hint)
        let (row, label) = Self.makeRow(title: title, column: column)
        label.centerYAnchor.constraint(equalTo: slider.centerYAnchor).isActive = true
        return row
    }

    private func makeAdvancedRow() -> NSView {
        let button = NSButton(
            title: NSLocalizedString("mouse-diagnostics-button", comment: ""),
            target: self,
            action: #selector(diagnosticsClicked(_:))
        )
        button.bezelStyle = .rounded
        diagnosticsButton = button
        let hint = Self.makeNote(NSLocalizedString("mouse-diagnostics-hint", comment: ""))
        let column = Self.makeColumn([button, hint])
        let (row, label) = Self.makeRow(
            title: NSLocalizedString("mouse-advanced-label", comment: ""),
            column: column
        )
        label.firstBaselineAnchor.constraint(equalTo: button.firstBaselineAnchor).isActive = true
        return row
    }

    private func makeSliderLine(
        range: ClosedRange<Int>,
        action: Selector,
        accessibilityLabel: String
    ) -> (NSSlider, NSTextField, NSView) {
        let line = PreferencesForm.makeSliderLine(
            range: Double(range.lowerBound)...Double(range.upperBound),
            widestValue: MouseWheelText.percent(range.upperBound),
            target: self,
            action: action,
            accessibilityLabel: accessibilityLabel
        )
        return (line.slider, line.valueLabel, line.line)
    }

    // MARK: - Building blocks (PreferencesForm)

    private static var noteFont: NSFont {
        return PreferencesForm.hintFont
    }

    private static func makeNote(_ text: String) -> NSTextField {
        return PreferencesForm.makeHint(text)
    }

    private static func setNote(_ label: NSTextField, _ text: String?) {
        PreferencesForm.setHint(label, text)
    }

    private static func makeColumn(_ views: [NSView]) -> NSStackView {
        return PreferencesForm.makeColumn(views)
    }

    private static func makeSeparator() -> NSView {
        return PreferencesForm.makeSeparator()
    }

    private static func makeRow(title: String, column: NSView) -> (row: NSView, label: NSTextField) {
        return PreferencesForm.makeRow(title: title, column: column)
    }

    // MARK: - Icons

    /// Small mouse glyph for the device list.
    private static func deviceIcon() -> NSImage? {
        if #available(macOS 11.0, *) {
            return NSImage(systemSymbolName: "computermouse", accessibilityDescription: nil)
        }
        return nil
    }

    /// Toolbar image, the size of the SF.* assets of the storyboard tabs.
    static func tabImage() -> NSImage {
        return PreferencesForm.toolbarImage(
            symbolName: "computermouse",
            accessibilityDescription: NSLocalizedString("mouse-tab-title", comment: "")
        ) { _ in
            // macOS 10.13-10.15: outline of a mouse with a button split.
            let body = NSBezierPath(
                roundedRect: NSRect(x: 45, y: 27, width: 45, height: 81),
                xRadius: 22.5,
                yRadius: 24
            )
            body.lineWidth = 7
            body.stroke()
            let split = NSBezierPath()
            split.move(to: NSPoint(x: 67.5, y: 101))
            split.line(to: NSPoint(x: 67.5, y: 84))
            split.lineWidth = 7
            split.lineCapStyle = .round
            split.stroke()
        }
    }
}
