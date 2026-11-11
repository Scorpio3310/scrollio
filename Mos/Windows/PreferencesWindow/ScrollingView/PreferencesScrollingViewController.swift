//
//  PreferencesScrollingViewController.swift
//  Mos
//  "Scrolling" preferences tab. The same view is the content of the per-app scroll
//  settings popover (PreferencesScrollingWithApplicationViewController gives it a target
//  application). Built in code on PreferencesGroupedForm, in the boxes of System Settings;
//  the storyboard scene is a shell.
//
//  On top a preview, then a box with what most people need: smooth scrolling, its feel,
//  the speed and the direction. A second box starts with "Advanced" (closed by default),
//  which opens the exact glide time, the smallest step and trackpad-style events in that
//  box and the three keys in a box of their own. "Reset to defaults" sits under the boxes.
//  The tab only edits scroll options: Options.shared.scroll, or the target application's own.
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

    /// Wider than the other panes (450 pt): the sliders and the key recorders sit on the
    /// right of their rows, and the explanations next to them still take one line.
    static let paneWidth: CGFloat = 520
    static var boxWidth: CGFloat {
        return PreferencesGroupedForm.boxWidth(paneWidth: paneWidth)
    }
    private static let keyButtonWidth: CGFloat = 150
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
    private(set) var smoothSwitch: NSSwitch!
    private(set) var feelControl: NSSegmentedControl!
    /// The explanation of the Feel row: it says how the chosen preset feels.
    private(set) var feelHintLabel: NSTextField!
    private(set) var scrollSpeedSlider: NSSlider!
    private(set) var scrollSpeedValueLabel: NSTextField!
    private(set) var reverseSwitch: NSSwitch!
    private(set) var advancedButton: NSButton!
    private(set) var glideTimeSlider: NSSlider!
    private(set) var glideTimeValueLabel: NSTextField!
    private(set) var smallestStepSlider: NSSlider!
    private(set) var smallestStepValueLabel: NSTextField!
    private(set) var trackpadEventsSwitch: NSSwitch!
    /// One recorder button and one "clear" button per `ScrollHoldKey`, in `allCases` order.
    private(set) var keyBindButtons: [NSButton] = []
    private(set) var keyClearButtons: [NSButton] = []
    private(set) var resetToDefaultsButton: NSButton!

    /// The rows of the first box: smooth scrolling, feel, speed, direction.
    private(set) var smoothRow: PreferencesSwitchRow!
    private(set) var feelRow: PreferencesGroupRow!
    private(set) var speedRow: PreferencesSliderRow!
    private(set) var reverseRow: PreferencesSwitchRow!
    /// The second box: "Advanced" and what it opens in that box.
    private(set) var advancedRow: PreferencesDisclosureRow!
    private(set) var glideTimeRow: PreferencesSliderRow!
    private(set) var smallestStepRow: PreferencesSliderRow!
    private(set) var trackpadEventsRow: PreferencesSwitchRow!
    /// "While you hold a key": its title and box, and the row of each key.
    private(set) var keysSection: PreferencesGroupSection!
    private(set) var keyRows: [PreferencesGroupRow] = []
    /// The boxes (as sections), top to bottom.
    private(set) var sections: [PreferencesGroupSection] = []
    /// Everything "Advanced" shows and hides: three rows of its box and the keys' section.
    private(set) var advancedRows: [NSView] = []

    // MARK: - Lifecycle

    override func loadView() {
        let root = PreferencesForm.makeBackground()
        let content = PreferencesGroupedForm.installContentStack(in: root, paneWidth: Self.paneWidth)
        // The pane wants to be exactly as tall as its rows, more strongly than a window or
        // popover wants to keep its size: what hosts it shrinks again when "Advanced" closes.
        content.setHuggingPriority(.defaultHigh, for: .vertical)

        let preview = ScrollPreviewView()
        preview.identifier = Identifier.preview
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.heightAnchor.constraint(equalToConstant: ScrollPreviewView.preferredHeight).isActive = true
        previewView = preview

        let width = Self.boxWidth
        let basic = PreferencesGroupSection(width: width, rows: [
            makeSmoothRow(), makeFeelRow(), makeSpeedRow(), makeReverseRow(),
        ])
        let advanced = PreferencesGroupSection(width: width, rows: [
            makeAdvancedRow(), makeGlideTimeRow(), makeSmallestStepRow(), makeTrackpadEventsRow(),
        ])
        keyRows = ScrollHoldKey.allCases.map { makeKeyRow($0) }
        let keys = PreferencesGroupSection(title: text("scrolling-keys-header"), width: width, rows: keyRows)
        keysSection = keys
        sections = [basic, advanced, keys]

        let reset = PreferencesGroupedForm.makePushButton(
            title: text("scrolling-reset"),
            target: self,
            action: #selector(resetToDefaultClick(_:))
        )
        reset.identifier = Identifier.reset
        resetToDefaultsButton = reset

        advancedRows = [glideTimeRow, smallestStepRow, trackpadEventsRow, keys]
        advancedRow.revealedViews = advancedRows

        PreferencesGroupedForm.add(
            [preview, basic, advanced, keys, PreferencesGroupFooter(trailing: [reset])],
            to: content
        )

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

        smoothRow.isOn = scroll.smooth
        smoothRow.isEnabled = editable

        let feel = ScrollFeel.matching(duration: scroll.duration)
        feelControl.selectedSegment = feel?.rawValue ?? -1
        feelRow.explanation = ScrollFeel.hint(for: feel)
        feelRow.isEnabled = smoothEditable

        sync(speedRow, .speed, value: scroll.speed, enabled: smoothEditable, isTracking: isTracking)

        reverseRow.isOn = scroll.reversesWheel
        reverseRow.isEnabled = editable

        sync(glideTimeRow, .glideTime, value: scroll.duration, enabled: smoothEditable, isTracking: isTracking)
        sync(smallestStepRow, .smallestStep, value: scroll.step, enabled: smoothEditable, isTracking: isTracking)

        trackpadEventsRow.isOn = scroll.smoothSimTrackpad
        trackpadEventsRow.isEnabled = smoothEditable

        for key in ScrollHoldKey.allCases {
            keyRows[key.rawValue].isEnabled = editable
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

    /// A slider row and its value. A refresh arriving mid-drag must not move the knob.
    private func sync(
        _ row: PreferencesSliderRow,
        _ setting: ScrollSliderSetting,
        value: Double,
        enabled: Bool,
        isTracking: Bool
    ) {
        if !isTracking {
            row.slider.doubleValue = value
        }
        row.valueText = setting.text(value)
        row.isEnabled = enabled
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
        advancedRow.isExpanded = isAdvancedExpanded
        if !isAdvancedExpanded {
            hoveredKey = nil
            focusedKey = nil
        }
    }

    private func contentHeightDidChange() {
        if let container = parent as? PreferencesScrollingWithApplicationViewController {
            container.fitToContent()
        } else {
            PreferencesForm.fitToContent(self)
        }
    }

    // MARK: - Actions

    @objc func scrollSmoothClick(_ sender: NSSwitch) {
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

    @objc func scrollReverseClick(_ sender: NSSwitch) {
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
    @objc func trackpadEventsClick(_ sender: NSSwitch) {
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

    private func makeSmoothRow() -> PreferencesGroupRow {
        let row = PreferencesSwitchRow(
            title: text("scrolling-smooth"),
            explanation: text("scrolling-smooth-hint"),
            target: self,
            action: #selector(scrollSmoothClick(_:))
        )
        row.toggle.identifier = Identifier.smooth
        smoothRow = row
        smoothSwitch = row.toggle
        return row
    }

    /// The title and the line that says how the chosen preset feels, the five presets
    /// under them across the box.
    private func makeFeelRow() -> PreferencesGroupRow {
        let control = NSSegmentedControl(
            labels: ScrollFeel.allCases.map(\.localizedName),
            trackingMode: .selectOne,
            target: self,
            action: #selector(feelChanged(_:))
        )
        control.identifier = Identifier.feel
        control.segmentDistribution = .fillEqually
        feelControl = control

        let row = PreferencesGroupRow(
            title: text("scrolling-feel-label"),
            explanation: ScrollFeel.smooth.localizedHint,
            accessory: control,
            placement: .below
        )
        // Room for the longest line, so picking another preset never changes the height.
        row.reservedExplanations = ScrollFeel.allCases.map(\.localizedHint) + [ScrollFeel.customHint]
        row.explanationLabel.identifier = Identifier.feelHint
        feelRow = row
        feelHintLabel = row.explanationLabel
        return row
    }

    private func makeSpeedRow() -> PreferencesGroupRow {
        let row = makeSliderRow(
            titleKey: "scrolling-speed-label",
            hintKey: "scrolling-speed-hint",
            setting: .speed,
            ends: (low: text("scrolling-speed-shorter"), high: text("scrolling-speed-farther")),
            identifier: Identifier.speed,
            action: #selector(scrollSpeedSliderChange(_:))
        )
        speedRow = row
        scrollSpeedSlider = row.slider
        scrollSpeedValueLabel = row.valueLabel
        return row
    }

    private func makeReverseRow() -> PreferencesGroupRow {
        let row = PreferencesSwitchRow(
            title: text("scrolling-reverse"),
            explanation: text("scrolling-reverse-hint"),
            target: self,
            action: #selector(scrollReverseClick(_:))
        )
        row.toggle.identifier = Identifier.reverse
        reverseRow = row
        reverseSwitch = row.toggle
        return row
    }

    /// "Advanced": the first row of the second box; it opens the rest of that box and the keys.
    private func makeAdvancedRow() -> PreferencesGroupRow {
        let row = PreferencesDisclosureRow(
            title: text("scrolling-advanced"),
            target: self,
            action: #selector(advancedClick(_:))
        )
        row.button.identifier = Identifier.advanced
        advancedRow = row
        advancedButton = row.button
        return row
    }

    private func makeGlideTimeRow() -> PreferencesGroupRow {
        let row = makeSliderRow(
            titleKey: "scrolling-glide-time-label",
            hintKey: "scrolling-glide-time-hint",
            setting: .glideTime,
            identifier: Identifier.glideTime,
            action: #selector(glideTimeSliderChange(_:))
        )
        glideTimeRow = row
        glideTimeSlider = row.slider
        glideTimeValueLabel = row.valueLabel
        return row
    }

    private func makeSmallestStepRow() -> PreferencesGroupRow {
        let row = makeSliderRow(
            titleKey: "scrolling-step-label",
            hintKey: "scrolling-step-hint",
            setting: .smallestStep,
            identifier: Identifier.smallestStep,
            action: #selector(smallestStepSliderChange(_:))
        )
        smallestStepRow = row
        smallestStepSlider = row.slider
        smallestStepValueLabel = row.valueLabel
        return row
    }

    private func makeTrackpadEventsRow() -> PreferencesGroupRow {
        let row = PreferencesSwitchRow(
            title: text("scrolling-trackpad-events"),
            explanation: text("scrolling-trackpad-events-hint"),
            target: self,
            action: #selector(trackpadEventsClick(_:))
        )
        row.toggle.identifier = Identifier.trackpadEvents
        trackpadEventsRow = row
        trackpadEventsSwitch = row.toggle
        return row
    }

    /// A slider with its value on the right of its row. All of the tab's sliders have the
    /// same width, so they line up.
    private func makeSliderRow(
        titleKey: String,
        hintKey: String,
        setting: ScrollSliderSetting,
        ends: (low: String, high: String)? = nil,
        identifier: NSUserInterfaceItemIdentifier,
        action: Selector
    ) -> PreferencesSliderRow {
        let row = PreferencesSliderRow(
            title: text(titleKey),
            explanation: text(hintKey),
            range: setting.range,
            ends: ends,
            target: self,
            action: action
        )
        row.slider.identifier = identifier
        return row
    }

    /// The recorder of one key with its "clear" button on the right, what the key does
    /// under its name. The row tells the preview when the pointer is over it.
    private func makeKeyRow(_ key: ScrollHoldKey) -> PreferencesGroupRow {
        let bind = ScrollKeyRecorderButton(
            title: text("Disabled"),
            target: self,
            action: #selector(keyBindClick(_:))
        )
        bind.identifier = Identifier.key(key)
        bind.tag = key.rawValue
        bind.bezelStyle = .push
        bind.alignment = .left
        bind.imageScaling = .scaleProportionallyDown
        bind.lineBreakMode = .byTruncatingTail
        bind.translatesAutoresizingMaskIntoConstraints = false
        bind.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        bind.widthAnchor.constraint(equalToConstant: Self.keyButtonWidth).isActive = true
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

        let row = PreferencesGroupRow(
            title: text(key.labelKey),
            explanation: text(key.hintKey),
            accessory: line,
            centeredOn: bind,
            controls: [bind]
        )
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
