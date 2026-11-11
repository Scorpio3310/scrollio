//
//  PreferencesScrollingViewController.swift
//  Mos
//  "Scrolling" preferences tab. The same view is the content of the per-app scroll
//  settings popover (PreferencesScrollingWithApplicationViewController gives it a target
//  application). Built in code on the PreferencesForm grid; the storyboard scene is a shell.
//
//  On top a preview and what most people need: smooth scrolling, its feel, the speed and
//  the direction, closed off by a line with "Advanced" and "Reset to defaults". "Advanced"
//  (closed by default) opens the exact glide time, the smallest step, trackpad-style
//  events and the three keys under that line. The tab only edits scroll options:
//  Options.shared.scroll, or the target application's own.
//
//  Created by Caldis on 2017/1/26.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

/// The three keys of "While you hold a key".
enum ScrollHoldKey: Int, CaseIterable {
    /// `scroll.dash`
    case faster
    /// `scroll.toggle`
    case sideways
    /// `scroll.block`
    case pause

    /// Stable name, used in string keys and control identifiers.
    var name: String {
        switch self {
        case .faster: return "faster"
        case .sideways: return "sideways"
        case .pause: return "pause"
        }
    }

    var labelKey: String {
        return "scrolling-key-\(name)"
    }

    var hintKey: String {
        return "scrolling-key-\(name)-hint"
    }

    /// What the preview shows while the key's row is pointed at.
    var emphasis: ScrollPreviewView.Emphasis {
        switch self {
        case .faster: return .faster
        case .sideways: return .sideways
        case .pause: return .paused
        }
    }

    func hotkey(in scroll: OPTIONS_SCROLL_DEFAULT) -> ScrollHotkey? {
        switch self {
        case .faster: return scroll.dash
        case .sideways: return scroll.toggle
        case .pause: return scroll.block
        }
    }

    func store(_ hotkey: ScrollHotkey?, in scroll: OPTIONS_SCROLL_DEFAULT) {
        switch self {
        case .faster: scroll.dash = hotkey
        case .sideways: scroll.toggle = hotkey
        case .pause: scroll.block = hotkey
        }
    }
}

/// The button that records a key. It tells when it gains or loses the keyboard focus.
final class ScrollKeyRecorderButton: NSButton {
    var onFocusChange: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { onFocusChange?(true) }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { onFocusChange?(false) }
        return resigned
    }
}

class PreferencesScrollingViewController: NSViewController, ScrollOptionsContextProviding {

    /// Identifiers for the controls (tests and accessibility tooling).
    enum Identifier {
        static let preview = NSUserInterfaceItemIdentifier("scrolling-preview")
        static let smooth = NSUserInterfaceItemIdentifier("scrolling-smooth")
        static let feel = NSUserInterfaceItemIdentifier("scrolling-feel")
        static let feelHint = NSUserInterfaceItemIdentifier("scrolling-feel-hint")
        static let speed = NSUserInterfaceItemIdentifier("scrolling-speed")
        static let reverse = NSUserInterfaceItemIdentifier("scrolling-reverse")
        static let advanced = NSUserInterfaceItemIdentifier("scrolling-advanced")
        static let glideTime = NSUserInterfaceItemIdentifier("scrolling-glide-time")
        static let smallestStep = NSUserInterfaceItemIdentifier("scrolling-smallest-step")
        static let trackpadEvents = NSUserInterfaceItemIdentifier("scrolling-trackpad-events")
        static let reset = NSUserInterfaceItemIdentifier("scrolling-reset")

        static func key(_ key: ScrollHoldKey) -> NSUserInterfaceItemIdentifier {
            return NSUserInterfaceItemIdentifier("scrolling-key-\(key.name)")
        }

        static func keyClear(_ key: ScrollHoldKey) -> NSUserInterfaceItemIdentifier {
            return NSUserInterfaceItemIdentifier("scrolling-key-\(key.name)-clear")
        }
    }

    /// Where "Advanced" remembers whether it is open. Plain UI state, not a scroll option.
    static let advancedExpandedDefaultsKey = "scrollingAdvancedExpanded"

    /// Between two rows. Tighter than the form kit's 17 pt: with "Advanced" open the tab
    /// has a dozen rows under the preview and has to stay on a laptop screen.
    static let rowSpacing: CGFloat = 12
    /// Between the rows of the three keys, and between their title and the first of them.
    private static let keyRowSpacing: CGFloat = 8
    /// Between a slider and the words under its ends.
    private static let sliderEndsSpacing: CGFloat = 1
    private static let keyButtonWidth: CGFloat = 120
    private static let keyClearButtonSize: CGFloat = 20

    // MARK: - State

    /// Set while the view sits in the per-app settings popover.
    var currentTargetApplication: Application? {
        didSet { syncViewWithOptions() }
    }

    /// Keeps the state of "Advanced"; tests and screenshots give it a store of their own.
    var uiStateDefaults: UserDefaults = .standard

    private(set) var isAdvancedExpanded = false

    /// The key whose recorder is recording. Recording wins over the pointer and the focus.
    var recordingKey: ScrollHoldKey? {
        didSet { updatePreviewScene() }
    }
    /// The key of the recorder button that was just clicked, until the recorder has started.
    private var clickedKey: ScrollHoldKey?
    /// The key row under the pointer.
    private var hoveredKey: ScrollHoldKey?
    /// The key whose recorder button has the keyboard focus.
    private var focusedKey: ScrollHoldKey?

    private let keyRecorder = KeyRecorder()

    // MARK: - Views (read access for tests)

    private(set) var previewView: ScrollPreviewView!
    private(set) var scrollSmoothCheckBox: NSButton!
    private(set) var feelControl: NSSegmentedControl!
    private(set) var feelHintLabel: NSTextField!
    private(set) var scrollSpeedSlider: NSSlider!
    private(set) var scrollSpeedValueLabel: NSTextField!
    private(set) var scrollReverseCheckBox: NSButton!
    private(set) var advancedButton: NSButton!
    private(set) var glideTimeSlider: NSSlider!
    private(set) var glideTimeValueLabel: NSTextField!
    private(set) var smallestStepSlider: NSSlider!
    private(set) var smallestStepValueLabel: NSTextField!
    private(set) var trackpadEventsCheckBox: NSButton!
    /// One recorder button and one "clear" button per `ScrollHoldKey`, in `allCases` order.
    private(set) var keyBindButtons: [NSButton] = []
    private(set) var keyClearButtons: [NSButton] = []
    private(set) var resetToDefaultsButton: NSButton!
    /// Everything "Advanced" shows and hides.
    private(set) var advancedRows: [NSView] = []

    // MARK: - Lifecycle

    override func loadView() {
        let root = PreferencesForm.makeBackground()
        let content = PreferencesForm.installContentStack(in: root)
        content.spacing = Self.rowSpacing
        // The pane wants to be exactly as tall as its rows, more strongly than a window or
        // popover wants to keep its size: what hosts it shrinks again when "Advanced" closes.
        content.setHuggingPriority(.defaultHigh, for: .vertical)

        let preview = ScrollPreviewView()
        preview.identifier = Identifier.preview
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.heightAnchor.constraint(equalToConstant: ScrollPreviewView.preferredHeight).isActive = true
        previewView = preview

        let smoothRow = makeSmoothRow()
        let feelRow = makeFeelRow()
        let speedRow = makeSpeedRow()
        let reverseRow = makeReverseRow()
        let footerRow = makeFooterRow()
        let glideTimeRow = makeGlideTimeRow()
        let smallestStepRow = makeSmallestStepRow()
        let trackpadEventsRow = makeTrackpadEventsRow()
        let keysHeader = makeKeysHeader()
        let keyRows = ScrollHoldKey.allCases.map { makeKeyRow($0) }

        advancedRows = [glideTimeRow, smallestStepRow, trackpadEventsRow, keysHeader] + keyRows

        var rows: [NSView] = [
            preview, smoothRow, feelRow, speedRow, reverseRow,
            PreferencesForm.makeSeparator(), footerRow,
        ]
        rows.append(contentsOf: advancedRows)
        PreferencesForm.add(rows, to: content)
        PreferencesForm.applySeparatorSpacing(in: content)
        content.setCustomSpacing(Self.keyRowSpacing, after: keysHeader)
        for row in keyRows.dropLast() {
            content.setCustomSpacing(Self.keyRowSpacing, after: row)
        }

        keyRecorder.delegate = self
        view = root
        isAdvancedExpanded = uiStateDefaults.bool(forKey: Self.advancedExpandedDefaultsKey)
        applyAdvancedExpanded()
        syncViewWithOptions()
        root.setFrameSize(root.fittingSize)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // In the per-app popover: the popover takes its size from these settings.
        (parent as? PreferencesScrollingWithApplicationViewController)?.fitToContent()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        // The options may have changed while the tab was not showing.
        syncViewWithOptions()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        previewView.setAnimating(!previewView.isHidden)
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        previewView.setAnimating(false)
        hoveredKey = nil
        updatePreviewScene()
    }

    // MARK: - Refresh

    /// Puts the scroll options (global, or the target application's) into every control.
    func syncViewWithOptions() {
        guard isViewLoaded else { return }
        // An app that inherits shows the global values, greyed out.
        let editable = !isTargetApplicationInheritOptions()
        let scroll = getTargetApplicationScrollOptions()
        // What only applies while the wheel is smoothed.
        let smoothEditable = editable && scroll.smooth
        let isTracking = PreferencesForm.isTrackingMouse

        // The preview belongs to the tab; the per-app popover stays small.
        previewView.isHidden = currentTargetApplication != nil

        scrollSmoothCheckBox.state = scroll.smooth ? .on : .off
        scrollSmoothCheckBox.isEnabled = editable

        let feel = ScrollFeel.matching(duration: scroll.duration)
        feelControl.selectedSegment = feel?.rawValue ?? -1
        feelControl.isEnabled = smoothEditable
        feelHintLabel.stringValue = ScrollFeel.hint(for: feel)

        sync(scrollSpeedSlider, scrollSpeedValueLabel, .speed, value: scroll.speed, enabled: smoothEditable, isTracking: isTracking)

        scrollReverseCheckBox.state = scroll.reversesWheel ? .on : .off
        scrollReverseCheckBox.isEnabled = editable

        sync(glideTimeSlider, glideTimeValueLabel, .glideTime, value: scroll.duration, enabled: smoothEditable, isTracking: isTracking)
        sync(smallestStepSlider, smallestStepValueLabel, .smallestStep, value: scroll.step, enabled: smoothEditable, isTracking: isTracking)

        trackpadEventsCheckBox.state = scroll.smoothSimTrackpad ? .on : .off
        trackpadEventsCheckBox.isEnabled = smoothEditable

        for key in ScrollHoldKey.allCases {
            updateHotkeyButton(
                keyBindButtons[key.rawValue],
                delButton: keyClearButtons[key.rawValue],
                hotkey: key.hotkey(in: scroll),
                enabled: editable
            )
        }

        resetToDefaultsButton.isEnabled = hasSettingsToReset
        updatePreviewScene()
    }

    /// A slider and the value next to it. A refresh arriving mid-drag must not move the knob.
    private func sync(
        _ slider: NSSlider,
        _ valueLabel: NSTextField,
        _ setting: ScrollSliderSetting,
        value: Double,
        enabled: Bool,
        isTracking: Bool
    ) {
        if !isTracking {
            slider.doubleValue = value
        }
        valueLabel.stringValue = setting.text(value)
        slider.isEnabled = enabled
        valueLabel.textColor = enabled ? .labelColor : .tertiaryLabelColor
    }

    /// True while the options differ from the defaults (an app that inherits has none of its own).
    var hasSettingsToReset: Bool {
        guard !isTargetApplicationInheritOptions() else { return false }
        return getTargetApplicationScrollOptions() != OPTIONS_SCROLL_DEFAULT()
    }

    // MARK: - Preview

    /// What the preview points out: a key only while "Advanced" shows the key rows.
    var previewEmphasis: ScrollPreviewView.Emphasis {
        guard isAdvancedExpanded else { return .wheel }
        return (recordingKey ?? hoveredKey ?? focusedKey)?.emphasis ?? .wheel
    }

    private func updatePreviewScene() {
        guard isViewLoaded else { return }
        let scroll = getTargetApplicationScrollOptions()
        var scene = ScrollPreviewView.Scene()
        scene.smoothing = scroll.smooth
        scene.duration = scroll.duration
        scene.speed = scroll.speed
        scene.reversed = scroll.reversesWheel
        scene.emphasis = previewEmphasis
        if previewView.scene != scene {
            previewView.scene = scene
        }
    }

    /// The pointer entered or left the row of `key`.
    func keyRowHoverChanged(_ key: ScrollHoldKey, inside: Bool) {
        if inside {
            hoveredKey = key
        } else if hoveredKey == key {
            hoveredKey = nil
        }
        updatePreviewScene()
    }

    /// The recorder button of `key` gained or lost the keyboard focus.
    func keyFocusChanged(_ key: ScrollHoldKey, focused: Bool) {
        if focused {
            focusedKey = key
        } else if focusedKey == key {
            focusedKey = nil
        }
        updatePreviewScene()
    }

    private static let hoverKeyInfo = "scrollHoldKey"

    private static func holdKey(of event: NSEvent) -> ScrollHoldKey? {
        guard let raw = event.trackingArea?.userInfo?[hoverKeyInfo] as? Int else { return nil }
        return ScrollHoldKey(rawValue: raw)
    }

    override func mouseEntered(with event: NSEvent) {
        guard let key = Self.holdKey(of: event) else { return super.mouseEntered(with: event) }
        keyRowHoverChanged(key, inside: true)
    }

    override func mouseExited(with event: NSEvent) {
        guard let key = Self.holdKey(of: event) else { return super.mouseExited(with: event) }
        keyRowHoverChanged(key, inside: false)
    }

    // MARK: - Advanced

    /// Opens or closes "Advanced", remembers it, and lets the window (or popover) follow.
    func setAdvancedExpanded(_ expanded: Bool) {
        guard expanded != isAdvancedExpanded else { return }
        isAdvancedExpanded = expanded
        uiStateDefaults.set(expanded, forKey: Self.advancedExpandedDefaultsKey)
        applyAdvancedExpanded()
        updatePreviewScene()
        contentHeightDidChange()
    }

    private func applyAdvancedExpanded() {
        for row in advancedRows {
            row.isHidden = !isAdvancedExpanded
        }
        advancedButton.image = Self.disclosureImage(expanded: isAdvancedExpanded)
        advancedButton.setAccessibilityExpanded(isAdvancedExpanded)
        if !isAdvancedExpanded {
            hoveredKey = nil
            focusedKey = nil
        }
    }

    /// The chevron of "Advanced". Both directions are drawn on one canvas, so the title
    /// next to it does not move when the row opens.
    private static func disclosureImage(expanded: Bool) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        guard let symbol = NSImage(systemSymbolName: expanded ? "chevron.down" : "chevron.right", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return nil }
        let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            let size = symbol.size
            symbol.draw(in: NSRect(
                x: rect.midX - size.width / 2,
                y: rect.midY - size.height / 2,
                width: size.width,
                height: size.height
            ))
            return true
        }
        image.isTemplate = true
        return image
    }

    private func contentHeightDidChange() {
        if let container = parent as? PreferencesScrollingWithApplicationViewController {
            container.fitToContent()
        } else {
            PreferencesForm.fitToContent(self)
        }
    }

    // MARK: - Actions

    @objc func scrollSmoothClick(_ sender: NSButton) {
        getTargetApplicationScrollOptions().smooth = sender.state == .on
        syncViewWithOptions()
    }

    /// A preset is a value of Duration: picking one moves the glide time slider with it.
    @objc func feelChanged(_ sender: NSSegmentedControl) {
        guard let feel = ScrollFeel(rawValue: sender.selectedSegment) else { return }
        setDuration(feel.duration)
    }

    @objc func scrollSpeedSliderChange(_ sender: NSSlider) {
        let scroll = getTargetApplicationScrollOptions()
        let value = ScrollSliderSetting.speed.snapped(sender.doubleValue)
        if scroll.speed != value {
            scroll.speed = value
        }
        syncViewWithOptions()
    }

    @objc func scrollReverseClick(_ sender: NSButton) {
        getTargetApplicationScrollOptions().reversesWheel = sender.state == .on
        syncViewWithOptions()
    }

    @objc func advancedClick(_ sender: NSButton) {
        setAdvancedExpanded(!isAdvancedExpanded)
    }

    /// The exact Duration. Off a preset's value, "Feel" shows nothing selected.
    @objc func glideTimeSliderChange(_ sender: NSSlider) {
        setDuration(ScrollSliderSetting.glideTime.snapped(sender.doubleValue))
    }

    private func setDuration(_ value: Double) {
        let scroll = getTargetApplicationScrollOptions()
        if scroll.duration != value {
            scroll.duration = value
        }
        syncViewWithOptions()
    }

    @objc func smallestStepSliderChange(_ sender: NSSlider) {
        let scroll = getTargetApplicationScrollOptions()
        let value = ScrollSliderSetting.smallestStep.snapped(sender.doubleValue)
        if scroll.step != value {
            scroll.step = value
        }
        syncViewWithOptions()
    }

    /// A plain switch: it leaves Duration alone.
    @objc func trackpadEventsClick(_ sender: NSButton) {
        getTargetApplicationScrollOptions().smoothSimTrackpad = sender.state == .on
        syncViewWithOptions()
    }

    /// Starts recording the key of the clicked row. The recorder ignores a click that comes
    /// while it is still busy, so the row only counts as recording once it has started.
    @objc func keyBindClick(_ sender: NSButton) {
        guard let key = ScrollHoldKey(rawValue: sender.tag) else { return }
        clickedKey = key
        keyRecorder.startRecording(from: sender, mode: .singleKey)
        clickedKey = nil
    }

    @objc func keyClearClick(_ sender: NSButton) {
        guard let key = ScrollHoldKey(rawValue: sender.tag) else { return }
        key.store(nil, in: getTargetApplicationScrollOptions())
        syncViewWithOptions()
    }

    /// Back to the scroll options of a new installation: the "Smooth" feel, the default
    /// speed and step, the three default keys, trackpad-style events off. "Advanced" stays
    /// as it is.
    @objc func resetToDefaultClick(_ sender: NSButton) {
        if let target = currentTargetApplication {
            target.scroll = OPTIONS_SCROLL_DEFAULT()
        } else {
            Options.shared.scroll = OPTIONS_SCROLL_DEFAULT()
        }
        syncViewWithOptions()
    }

    // MARK: - Rows

    private func text(_ key: String) -> String {
        return NSLocalizedString(key, comment: "")
    }

    /// A checkbox with one line of plain explanation under it.
    private func makeCheckboxRow(
        labelKey: String,
        titleKey: String,
        hintKey: String,
        identifier: NSUserInterfaceItemIdentifier,
        action: Selector
    ) -> (row: NSView, checkbox: NSButton) {
        let checkbox = PreferencesForm.makeCheckbox(title: text(titleKey), target: self, action: action)
        checkbox.identifier = identifier
        let hint = PreferencesForm.makeHint(text(hintKey))
        let (row, label) = PreferencesForm.makeRow(
            title: text(labelKey),
            column: PreferencesForm.makeColumn([checkbox, hint])
        )
        label.firstBaselineAnchor.constraint(equalTo: checkbox.firstBaselineAnchor).isActive = true
        return (row, checkbox)
    }

    /// A slider with its value to the right and one line of plain explanation under it.
    /// `endsKeys` puts a word under each end of the slider.
    private func makeSliderRow(
        labelKey: String,
        hintKey: String,
        setting: ScrollSliderSetting,
        endsKeys: (low: String, high: String)? = nil,
        identifier: NSUserInterfaceItemIdentifier,
        action: Selector
    ) -> (row: NSView, slider: NSSlider, valueLabel: NSTextField) {
        let line = PreferencesForm.makeSliderLine(
            range: setting.range,
            widestValue: setting.text(setting.range.upperBound),
            target: self,
            action: action,
            accessibilityLabel: text(labelKey)
        )
        line.slider.identifier = identifier
        let hint = PreferencesForm.makeHint(text(hintKey))

        var views: [NSView] = [line.line]
        var ends: NSView?
        if let endsKeys {
            let view = makeSliderEnds(low: text(endsKeys.low), high: text(endsKeys.high))
            views.append(view)
            ends = view
        }
        views.append(hint)
        let column = PreferencesForm.makeColumn(views)
        if ends != nil {
            column.setCustomSpacing(Self.sliderEndsSpacing, after: line.line)
        }

        let (row, label) = PreferencesForm.makeRow(title: text(labelKey), column: column)
        label.centerYAnchor.constraint(equalTo: line.slider.centerYAnchor).isActive = true
        return (row, line.slider, line.valueLabel)
    }

    /// A word under each end of a slider, as in System Settings ("Slow" and "Fast").
    private func makeSliderEnds(low: String, high: String) -> NSView {
        let ends = NSView()
        ends.translatesAutoresizingMaskIntoConstraints = false
        let lowLabel = PreferencesForm.makeHint(low)
        let highLabel = PreferencesForm.makeHint(high)
        highLabel.alignment = .right
        for label in [lowLabel, highLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            ends.addSubview(label)
        }
        NSLayoutConstraint.activate([
            ends.widthAnchor.constraint(equalToConstant: PreferencesForm.sliderWidth),
            lowLabel.leadingAnchor.constraint(equalTo: ends.leadingAnchor),
            lowLabel.topAnchor.constraint(equalTo: ends.topAnchor),
            lowLabel.bottomAnchor.constraint(equalTo: ends.bottomAnchor),
            highLabel.trailingAnchor.constraint(equalTo: ends.trailingAnchor),
            highLabel.firstBaselineAnchor.constraint(equalTo: lowLabel.firstBaselineAnchor),
            highLabel.leadingAnchor.constraint(greaterThanOrEqualTo: lowLabel.trailingAnchor, constant: 8),
        ])
        return ends
    }

    private func makeSmoothRow() -> NSView {
        let made = makeCheckboxRow(
            labelKey: "scrolling-wheel-label",
            titleKey: "scrolling-smooth",
            hintKey: "scrolling-smooth-hint",
            identifier: Identifier.smooth,
            action: #selector(scrollSmoothClick(_:))
        )
        scrollSmoothCheckBox = made.checkbox
        return made.row
    }

    /// The five presets in one control, and under it the line that says how the choice feels.
    private func makeFeelRow() -> NSView {
        let control = NSSegmentedControl(
            labels: ScrollFeel.allCases.map(\.localizedName),
            trackingMode: .selectOne,
            target: self,
            action: #selector(feelChanged(_:))
        )
        control.identifier = Identifier.feel
        control.controlSize = .small
        control.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        control.segmentDistribution = .fillEqually
        control.setAccessibilityLabel(text("scrolling-feel-label"))
        control.translatesAutoresizingMaskIntoConstraints = false
        control.widthAnchor.constraint(equalToConstant: PreferencesForm.controlWidth).isActive = true
        feelControl = control

        let hint = PreferencesForm.makeHint("")
        hint.identifier = Identifier.feelHint
        // Room for the longest line, so picking another preset never changes the height.
        let lines = ScrollFeel.allCases.map(\.localizedHint) + [ScrollFeel.customHint]
        let tallest = lines.map { PreferencesForm.makeHint($0).fittingSize.height }.max() ?? 0
        hint.heightAnchor.constraint(greaterThanOrEqualToConstant: tallest).isActive = true
        feelHintLabel = hint

        let (row, label) = PreferencesForm.makeRow(
            title: text("scrolling-feel-label"),
            column: PreferencesForm.makeColumn([control, hint])
        )
        label.firstBaselineAnchor.constraint(equalTo: control.firstBaselineAnchor).isActive = true
        return row
    }

    private func makeSpeedRow() -> NSView {
        let made = makeSliderRow(
            labelKey: "scrolling-speed-label",
            hintKey: "scrolling-speed-hint",
            setting: .speed,
            endsKeys: (low: "scrolling-speed-shorter", high: "scrolling-speed-farther"),
            identifier: Identifier.speed,
            action: #selector(scrollSpeedSliderChange(_:))
        )
        scrollSpeedSlider = made.slider
        scrollSpeedValueLabel = made.valueLabel
        return made.row
    }

    private func makeReverseRow() -> NSView {
        let made = makeCheckboxRow(
            labelKey: "scrolling-direction-label",
            titleKey: "scrolling-reverse",
            hintKey: "scrolling-reverse-hint",
            identifier: Identifier.reverse,
            action: #selector(scrollReverseClick(_:))
        )
        scrollReverseCheckBox = made.checkbox
        return made.row
    }

    /// The line under the basic settings: "Advanced" with its chevron on the left, "Reset
    /// to defaults" on the right. Both stay where they are when "Advanced" opens below.
    private func makeFooterRow() -> NSView {
        let advanced = NSButton(title: text("scrolling-advanced"), target: self, action: #selector(advancedClick(_:)))
        advanced.identifier = Identifier.advanced
        advanced.isBordered = false
        advanced.setButtonType(.momentaryChange)
        advanced.font = PreferencesForm.sectionHeaderFont
        advanced.imagePosition = .imageLeading
        advanced.imageHugsTitle = true
        advanced.contentTintColor = .secondaryLabelColor
        advancedButton = advanced

        let reset = NSButton(title: text("scrolling-reset"), target: self, action: #selector(resetToDefaultClick(_:)))
        reset.identifier = Identifier.reset
        reset.bezelStyle = .rounded
        reset.controlSize = .small
        reset.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        resetToDefaultsButton = reset

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addView(advanced, in: .leading)
        row.addView(reset, in: .trailing)
        return row
    }

    private func makeGlideTimeRow() -> NSView {
        let made = makeSliderRow(
            labelKey: "scrolling-glide-time-label",
            hintKey: "scrolling-glide-time-hint",
            setting: .glideTime,
            identifier: Identifier.glideTime,
            action: #selector(glideTimeSliderChange(_:))
        )
        glideTimeSlider = made.slider
        glideTimeValueLabel = made.valueLabel
        return made.row
    }

    private func makeSmallestStepRow() -> NSView {
        let made = makeSliderRow(
            labelKey: "scrolling-step-label",
            hintKey: "scrolling-step-hint",
            setting: .smallestStep,
            identifier: Identifier.smallestStep,
            action: #selector(smallestStepSliderChange(_:))
        )
        smallestStepSlider = made.slider
        smallestStepValueLabel = made.valueLabel
        return made.row
    }

    private func makeTrackpadEventsRow() -> NSView {
        let made = makeCheckboxRow(
            labelKey: "scrolling-apps-label",
            titleKey: "scrolling-trackpad-events",
            hintKey: "scrolling-trackpad-events-hint",
            identifier: Identifier.trackpadEvents,
            action: #selector(trackpadEventsClick(_:))
        )
        trackpadEventsCheckBox = made.checkbox
        return made.row
    }

    /// "While you hold a key": the title of the three rows under it, above their buttons.
    private func makeKeysHeader() -> NSView {
        let header = NSTextField(labelWithString: text("scrolling-keys-header"))
        header.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        header.textColor = .labelColor
        header.lineBreakMode = .byTruncatingTail
        header.translatesAutoresizingMaskIntoConstraints = false
        let (row, _) = PreferencesForm.makeRow(title: "", column: PreferencesForm.makeColumn([header]))
        return row
    }

    /// The recorder of one key with its "clear" button, and what the key does under them.
    /// The row tells the preview when the pointer is over it.
    private func makeKeyRow(_ key: ScrollHoldKey) -> NSView {
        let bind = ScrollKeyRecorderButton(
            title: text("Disabled"),
            target: self,
            action: #selector(keyBindClick(_:))
        )
        bind.identifier = Identifier.key(key)
        bind.tag = key.rawValue
        bind.bezelStyle = .rounded
        bind.alignment = .left
        bind.imageScaling = .scaleProportionallyDown
        bind.lineBreakMode = .byTruncatingTail
        bind.translatesAutoresizingMaskIntoConstraints = false
        bind.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        bind.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.keyButtonWidth).isActive = true
        bind.onFocusChange = { [weak self] focused in
            self?.keyFocusChanged(key, focused: focused)
        }

        let clear = NSButton(
            image: NSImage(named: NSImage.stopProgressFreestandingTemplateName) ?? NSImage(),
            target: self,
            action: #selector(keyClearClick(_:))
        )
        clear.identifier = Identifier.keyClear(key)
        clear.tag = key.rawValue
        clear.isBordered = false
        clear.imageScaling = .scaleProportionallyDown
        clear.contentTintColor = .secondaryLabelColor
        clear.setAccessibilityLabel(text("scrolling-key-clear"))
        clear.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            clear.widthAnchor.constraint(equalToConstant: Self.keyClearButtonSize),
            clear.heightAnchor.constraint(equalToConstant: Self.keyClearButtonSize),
        ])

        let line = NSStackView(views: [bind, clear])
        line.orientation = .horizontal
        line.alignment = .centerY
        line.spacing = 4
        line.translatesAutoresizingMaskIntoConstraints = false
        line.widthAnchor.constraint(lessThanOrEqualToConstant: PreferencesForm.controlWidth).isActive = true

        let hint = PreferencesForm.makeHint(text(key.hintKey))
        let (row, label) = PreferencesForm.makeRow(
            title: text(key.labelKey),
            column: PreferencesForm.makeColumn([line, hint])
        )
        label.centerYAnchor.constraint(equalTo: bind.centerYAnchor).isActive = true
        bind.setAccessibilityTitleUIElement(label)

        row.addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: [Self.hoverKeyInfo: key.rawValue]
        ))

        keyBindButtons.append(bind)
        keyClearButtons.append(clear)
        return row
    }
}

// MARK: - Key names

extension PreferencesScrollingViewController {

    /// 键盘按键的完整名称映射 (仅用于 ScrollingView 按钮显示)
    private static let keyFullNames: [UInt16: String] = [
        // 修饰键
        KeyCode.commandL: "⌘ Command",
        KeyCode.commandR: "⌘ Command",
        KeyCode.optionL: "⌥ Option",
        KeyCode.optionR: "⌥ Option",
        KeyCode.shiftL: "⇧ Shift",
        KeyCode.shiftR: "⇧ Shift",
        KeyCode.controlL: "⌃ Control",
        KeyCode.controlR: "⌃ Control",
        KeyCode.fnL: "Fn",
        KeyCode.fnR: "Fn",
        // 特殊键
        49: "⎵ Space",
        51: "⌫ Delete",
        53: "⎋ Escape",
        36: "↩ Return",
        76: "↩ Return",
        48: "↹ Tab",
    ]

    /// 获取按键基础名称 (不含品牌前缀)
    private func getBaseDisplayName(for hotkey: ScrollHotkey) -> String {
        switch hotkey.type {
        case .keyboard:
            if let fullName = PreferencesScrollingViewController.keyFullNames[hotkey.code] {
                return fullName
            }
            return KeyCode.keyMap[hotkey.code] ?? "Key \(hotkey.code)"
        case .mouse:
            if LogiCenter.shared.isLogiCode(hotkey.code) {
                return (LogiCenter.shared.name(forMosCode: hotkey.code) ?? "")
            }
            return KeyCode.mouseMap[hotkey.code] ?? "🖱\(hotkey.code)"
        }
    }

    /// 获取完整显示名称 (含品牌前缀, 用于纯文本场景)
    private func getFullDisplayName(for hotkey: ScrollHotkey) -> String {
        let baseName = getBaseDisplayName(for: hotkey)
        if let brand = BrandTag.brandForCode(hotkey.code) {
            return BrandTag.prefixedName(baseName, brand: brand)
        }
        return baseName
    }

    /// 更新热键按钮的显示文本和删除按钮可见性
    private func updateHotkeyButton(_ button: NSButton, delButton: NSButton, hotkey: ScrollHotkey?, enabled: Bool) {
        let hasBound = hotkey != nil

        // 设置按钮标题
        if let hotkey = hotkey {
            let baseName = getBaseDisplayName(for: hotkey)
            if let brand = BrandTag.brandForCode(hotkey.code) {
                // 品牌按键: image=tag, title=名称, 左图右文
                button.image = BrandTag.createTagImage(brand: brand, fontSize: 7, height: 14, padH: 5, marginRight: 4)
                button.imagePosition = .imageLeft
                button.title = baseName
            } else {
                button.image = nil
                button.imagePosition = .noImage
                button.title = getFullDisplayName(for: hotkey)
            }
        } else {
            button.image = nil
            button.imagePosition = .noImage
            button.title = NSLocalizedString("Disabled", comment: "Hotkey disabled state")
        }

        button.isEnabled = enabled

        // 设置删除按钮可见性：仅在有绑定且启用时显示
        delButton.alphaValue = (hasBound && enabled) ? 1.0 : 0.0
        delButton.isEnabled = hasBound && enabled
    }
}

// MARK: - KeyRecorderDelegate

extension PreferencesScrollingViewController: KeyRecorderDelegate {

    func onRecordingStarted(_ recorder: KeyRecorder) {
        recordingKey = clickedKey
    }

    func onEventRecorded(_ recorder: KeyRecorder, didRecordEvent event: InputEvent, isDuplicate: Bool) {
        guard let key = recordingKey else { return }
        key.store(ScrollHotkey(from: event), in: getTargetApplicationScrollOptions())
        recordingKey = nil
        syncViewWithOptions()
    }

    func onRecordingStopped(_ recorder: KeyRecorder, didRecord: Bool) {
        recordingKey = nil
    }
}
