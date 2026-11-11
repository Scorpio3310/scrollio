//
//  PreferencesScrollingViewController.swift
//  Mos
//  "Scrolling" preferences tab. The same view edits one app's own scroll settings on that
//  app's page under Apps (a PreferencesScrollingContainer gives it a target application).
//  Built in code on PreferencesGroupedForm, in the boxes of System Settings; the storyboard
//  scene is a shell.
//
//  On top a preview, then a box with what most people need: smooth scrolling, its feel,
//  the speed and the direction. Under it "Thumb wheel": what the sideways wheel of a mouse
//  does, its speed and its direction, with a line under the box on which wheel that is;
//  global only, so not on an app's page (VoiceOver hears it as a group of that name, so its
//  "Speed" is not taken for the main wheel's). Then "While you hold a key" with the three
//  keys, which work from the first launch, so they always show. The last box starts with "Advanced"
//  (closed by default), which opens the exact glide time, the smallest step and
//  trackpad-style events in that box. "Reset to defaults" sits under the boxes; Edit › Undo
//  takes a reset back.
//  The tab edits scroll options (Options.shared.scroll, or the target application's own) and,
//  on the tab itself, Options.shared.thumbWheel, which the Buttons pane edits too: a change
//  made there shows here at once (ThumbWheelSettingsChange).
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

/// The tab's three sliders and how each shows its value. Speed writes its factor next to
/// the slider ("6.3×"). Glide time (a scale of 1 to 5 that reads like seconds but is not)
/// and Smallest step write no number: the words under their ends say which way is which,
/// and VoiceOver reads where the knob is between them ("67%"). Numbers follow the user's
/// locale ("6,3×" with a decimal comma). Display only: the stored values do not change.
enum ScrollingSlider: CaseIterable {
    case speed, glideTime, smallestStep

    /// The range, the tick marks and the grid of the slider.
    var setting: ScrollSliderSetting {
        switch self {
        case .speed: return .speed
        case .glideTime: return .glideTime
        case .smallestStep: return .smallestStep
        }
    }

    /// What is written next to the slider; empty for none. A value off the grid keeps the
    /// decimals it needs (`ScrollSliderSetting.maxDecimals`), so it is not shown as another.
    func shownText(for value: Double, locale: Locale = .current) -> String {
        switch self {
        case .speed:
            let formatter = NumberFormatter()
            formatter.locale = locale
            formatter.numberStyle = .decimal
            formatter.minimumFractionDigits = setting.decimals
            formatter.maximumFractionDigits = setting.maxDecimals
            let number = formatter.string(from: NSNumber(value: value)) ?? ""
            return String(format: NSLocalizedString("scrolling-speed-value", comment: ""), number)
        case .glideTime, .smallestStep:
            return ""
        }
    }

    /// What VoiceOver reads as the slider's value: the text next to it, or for a slider
    /// without one how far along its range the value lies, from the low end.
    func spokenValue(for value: Double, locale: Locale = .current) -> String {
        let shown = shownText(for: value, locale: locale)
        guard shown.isEmpty else { return shown }
        let range = setting.range
        let span = range.upperBound - range.lowerBound
        let fraction = span > 0 && value.isFinite ? (value - range.lowerBound) / span : 0
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: min(1, max(0, fraction)))) ?? ""
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
        static let thumbWheelFunction = NSUserInterfaceItemIdentifier("scrolling-thumb-wheel-function")
        static let thumbWheelFunctionHint = NSUserInterfaceItemIdentifier("scrolling-thumb-wheel-function-hint")
        static let thumbWheelSpeed = NSUserInterfaceItemIdentifier("scrolling-thumb-wheel-speed")
        static let thumbWheelSwap = NSUserInterfaceItemIdentifier("scrolling-thumb-wheel-swap")
        static let thumbWheelNote = NSUserInterfaceItemIdentifier("scrolling-thumb-wheel-note")
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

    /// The width of the Preferences window's column (`PreferencesWindowLayout.contentWidth`):
    /// the sliders and the key recorders sit on the right of their rows, and the
    /// explanations next to them still take one line.
    static let paneWidth: CGFloat = 520
    static var boxWidth: CGFloat {
        return PreferencesGroupedForm.boxWidth(paneWidth: paneWidth)
    }
    private static let keyButtonWidth: CGFloat = 150
    private static let keyClearButtonSize: CGFloat = 20
    /// The thumb wheel's pop-up: room for the longest function with its symbol.
    static let thumbWheelPopUpWidth: CGFloat = 180

    // MARK: - State

    /// Set while the view sits on an app's page under Apps.
    var currentTargetApplication: Application? {
        didSet { syncViewWithOptions() }
    }

    /// Keeps the state of "Advanced"; tests and screenshots give it a store of their own.
    var uiStateDefaults: UserDefaults = .standard

    /// Takes Undo and Redo of "Reset to Defaults"; the window's when nil.
    var paneUndoManager: UndoManager?

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
    /// The last box: "Advanced" and what it opens in that box.
    private(set) var advancedSection: PreferencesGroupSection!
    private(set) var advancedRow: PreferencesDisclosureRow!
    private(set) var glideTimeRow: PreferencesSliderRow!
    private(set) var smallestStepRow: PreferencesSliderRow!
    private(set) var trackpadEventsRow: PreferencesSwitchRow!
    /// "While you hold a key": its title and box, and the row of each key.
    private(set) var keysSection: PreferencesGroupSection!
    private(set) var keyRows: [PreferencesGroupRow] = []
    /// "Thumb wheel": its title and box, the line under the box, and its three rows. Only on
    /// the tab (hidden on an app's page: the thumb wheel has no per-app settings).
    private(set) var thumbWheelSection: PreferencesGroupSection!
    /// The line under the box (in a holder that insets it, which is what hides).
    private(set) var thumbWheelNote: NSTextField!
    private(set) var thumbWheelFunctionRow: PreferencesGroupRow!
    private(set) var thumbWheelFunctionPopUp: NSPopUpButton!
    private(set) var thumbWheelSpeedRow: PreferencesSliderRow!
    private(set) var thumbWheelSpeedSlider: NSSlider!
    private(set) var thumbWheelSwapRow: PreferencesSwitchRow!
    private(set) var thumbWheelSwapSwitch: NSSwitch!
    /// The boxes (as sections), top to bottom: the main box, the thumb wheel, the keys,
    /// "Advanced".
    private(set) var sections: [PreferencesGroupSection] = []
    /// What "Advanced" shows and hides: the three rows of its box under it.
    private(set) var advancedRows: [NSView] = []
    /// Hears of every change of the thumb wheel settings (the Buttons pane edits them too).
    private var thumbWheelObserver: NSObjectProtocol?

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
        advancedSection = advanced
        keyRows = ScrollHoldKey.allCases.map { makeKeyRow($0) }
        let keys = PreferencesGroupSection(title: text("scrolling-keys-header"), width: width, rows: keyRows)
        keysSection = keys
        let thumbWheel = PreferencesGroupSection(title: ThumbWheelPresentation.title, width: width, rows: [
            makeThumbWheelFunctionRow(), makeThumbWheelSpeedRow(), makeThumbWheelSwapRow(),
        ])
        thumbWheelSection = thumbWheel
        let thumbWheelNoteHolder = makeThumbWheelNote()
        // For VoiceOver one group named "Thumb wheel": its "Speed" is not the main wheel's,
        // its "Action" is the thumb wheel's. The title is the group's name, not a text of its
        // own; the line under the box is the group's help.
        thumbWheel.setAccessibilityElement(true)
        thumbWheel.setAccessibilityRole(.group)
        thumbWheel.setAccessibilityLabel(ThumbWheelPresentation.title)
        thumbWheel.setAccessibilityHelp(thumbWheelNote.stringValue)
        thumbWheel.titleLabel?.setAccessibilityElement(false)
        sections = [basic, thumbWheel, keys, advanced]

        let reset = PreferencesGroupedForm.makePushButton(
            title: text("scrolling-reset"),
            target: self,
            action: #selector(resetToDefaultClick(_:))
        )
        reset.identifier = Identifier.reset
        resetToDefaultsButton = reset

        advancedRows = [glideTimeRow, smallestStepRow, trackpadEventsRow]
        advancedRow.revealedViews = advancedRows

        // The thumb wheel above the keys, so the default window shows it. Hidden (an app's
        // page) it takes no room, and the keys keep the gap above their title.
        PreferencesGroupedForm.add(
            [preview, basic, thumbWheel, thumbWheelNoteHolder, keys, advanced, PreferencesGroupFooter(trailing: [reset])],
            to: content
        )
        // The line about the thumb wheel sits close under its box, as the muted lines of the
        // other panes do.
        content.setCustomSpacing(PreferencesGroupedForm.noteSpacing, after: thumbWheel)

        keyRecorder.delegate = self
        view = root
        isAdvancedExpanded = uiStateDefaults.bool(forKey: Self.advancedExpandedDefaultsKey)
        applyAdvancedExpanded()
        syncViewWithOptions()
        root.setFrameSize(root.fittingSize)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // On an app's page: the page takes its size from these settings.
        (parent as? PreferencesScrollingContainer)?.fitToContent()
        // The thumb wheel settings may change under Buttons while this tab exists.
        thumbWheelObserver = ThumbWheelSettingsChange.addObserver { [weak self] in
            self?.syncViewWithOptions()
        }
    }

    deinit {
        if let thumbWheelObserver {
            ThumbWheelSettingsChange.removeObserver(thumbWheelObserver)
        }
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

        // The preview belongs to the tab; an app's page stays short.
        previewView.isHidden = currentTargetApplication != nil

        smoothRow.isOn = scroll.smooth
        smoothRow.isEnabled = editable

        let feel = ScrollFeel.matching(duration: scroll.duration)
        feelControl.selectedSegment = feel?.rawValue ?? -1
        feelRow.explanation = ScrollFeel.hint(for: feel)
        feelRow.isEnabled = smoothEditable

        sync(speedRow, .speed, value: scroll.speed, enabled: smoothEditable)

        reverseRow.isOn = scroll.reversesWheel
        reverseRow.isEnabled = editable

        sync(glideTimeRow, .glideTime, value: scroll.duration, enabled: smoothEditable)
        sync(smallestStepRow, .smallestStep, value: scroll.step, enabled: smoothEditable)

        trackpadEventsRow.isOn = scroll.smoothSimTrackpad
        trackpadEventsRow.isEnabled = smoothEditable

        for key in ScrollHoldKey.allCases {
            keyRows[key.rawValue].isEnabled = editable
        }
        updateKeyButtons(in: scroll, enabled: editable)
        syncThumbWheel()

        resetToDefaultsButton.isEnabled = hasSettingsToReset
        updatePreviewScene()
    }

    /// The thumb wheel group: on the tab only. It shows Options.shared.thumbWheel and writes
    /// nothing. The speed slider is always on: with "Smooth scrolling" off an app with its
    /// own settings may still smooth the wheel at this speed, and the line says so.
    private func syncThumbWheel() {
        let shown = currentTargetApplication == nil
        thumbWheelSection.isHidden = !shown
        // The line's holder is what the column of boxes holds.
        thumbWheelNote.superview?.isHidden = !shown
        guard shown else { return }

        let settings = Options.shared.thumbWheel
        let function = settings.function
        if let index = ThumbWheelFunction.allCases.firstIndex(of: function),
           thumbWheelFunctionPopUp.indexOfSelectedItem != index {
            thumbWheelFunctionPopUp.selectItem(at: index)
        }
        if thumbWheelFunctionRow.explanation != function.localizedHint {
            thumbWheelFunctionRow.explanation = function.localizedHint
        }

        let speedRow = thumbWheelSpeedRow!
        if !speedRow.isTracking {
            speedRow.showValue(settings.speed)
        }
        speedRow.valueText = ThumbWheelPresentation.speedText(settings.speed)
        let speedHint = text(ThumbWheelPresentation.speedHintKey(for: function, smoothing: Options.shared.scroll.smooth))
        if speedRow.explanation != speedHint {
            speedRow.explanation = speedHint
        }

        thumbWheelSwapRow.isOn = settings.swapsDirection
    }

    /// A slider row and its value. A refresh arriving while the user drags this knob must
    /// not move it; every other knob follows. A stored value off the slider's grid is shown
    /// as it is, not snapped.
    private func sync(
        _ row: PreferencesSliderRow,
        _ slider: ScrollingSlider,
        value: Double,
        enabled: Bool
    ) {
        if !row.isTracking {
            row.showValue(value)
        }
        row.valueText = slider.shownText(for: value)
        row.slider.setAccessibilityValueDescription(slider.spokenValue(for: value))
        row.isEnabled = enabled
    }

    /// True while the options differ from the defaults (an app that inherits has none of its
    /// own). On the tab the thumb wheel settings count too; on an app's page they do not.
    var hasSettingsToReset: Bool {
        guard !isTargetApplicationInheritOptions() else { return false }
        if currentTargetApplication == nil, Options.shared.thumbWheel != .default {
            return true
        }
        return getTargetApplicationScrollOptions() != OPTIONS_SCROLL_DEFAULT()
    }

    // MARK: - Preview

    /// What the preview points out: the key whose row is recording, under the pointer or
    /// focused, in that order; otherwise the wheel.
    var previewEmphasis: ScrollPreviewView.Emphasis {
        return (recordingKey ?? hoveredKey ?? focusedKey)?.emphasis ?? .wheel
    }

    private func updatePreviewScene() {
        guard isViewLoaded else { return }
        let scroll = getTargetApplicationScrollOptions()
        var scene = ScrollPreviewView.Scene()
        scene.smoothing = scroll.smooth
        scene.duration = scroll.duration
        scene.speed = scroll.speed
        // The preview turns the vertical wheel: reversed as the engine reverses that axis
        // (the switch is also on when only the horizontal one is).
        scene.reversed = scroll.reverse && scroll.reverseVertical
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
        contentHeightDidChange()
    }

    private func applyAdvancedExpanded() {
        advancedRow.isExpanded = isAdvancedExpanded
    }

    private func contentHeightDidChange() {
        if let container = parent as? PreferencesScrollingContainer {
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
        feel.apply(to: getTargetApplicationScrollOptions())
        syncViewWithOptions()
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

    /// The thumb wheel's function. Written only when it changes; the tab (and the Buttons
    /// pane) then follow through ThumbWheelSettingsChange.
    @objc func thumbWheelFunctionChanged(_ sender: NSPopUpButton) {
        guard let function = ThumbWheelPresentation.function(of: sender.selectedItem) else { return }
        if Options.shared.thumbWheel.function != function {
            Options.shared.thumbWheel.function = function
        }
        syncViewWithOptions()
    }

    /// The thumb wheel's speed, on the slider's grid of 0.05. The slider sends nothing for a
    /// press that does not move its knob, and a value it already has is not written again.
    @objc func thumbWheelSpeedChanged(_ sender: NSSlider) {
        let value = ThumbWheelPresentation.speedSetting.snapped(sender.doubleValue)
        if Options.shared.thumbWheel.speed != value {
            Options.shared.thumbWheel.speed = value
        }
        syncViewWithOptions()
    }

    @objc func thumbWheelSwapClick(_ sender: NSSwitch) {
        let swaps = sender.state == .on
        if Options.shared.thumbWheel.swapsDirection != swaps {
            Options.shared.thumbWheel.swapsDirection = swaps
        }
        syncViewWithOptions()
    }

    /// Back to the scroll options of a new installation: the "Smooth" feel, the default
    /// speed and step, the three default keys, trackpad-style events off; on the tab also the
    /// thumb wheel (scrolls sideways at 1×, not swapped). "Advanced" stays as it is. One
    /// click, no question: Edit › Undo ("Undo Reset Scrolling") brings back every value it
    /// changed.
    @objc func resetToDefaultClick(_ sender: NSButton) {
        Self.resetScrollOptions(of: currentTargetApplication, undoManager: undoTarget) { [weak self] in
            self?.syncViewWithOptions()
        }
    }

    // MARK: - Reset, with Undo

    /// Where a reset registers its Undo: the window's undo manager while the tab (or the
    /// app's page) is in the window. Undo and Redo stay with the manager the reset used.
    var undoTarget: UndoManager? {
        return paneUndoManager ?? view.window?.undoManager
    }

    /// What a reset replaces: the scroll options, and on the tab the thumb wheel settings
    /// (nil on an app's page: they are not the app's and are left alone).
    private struct ResettableSettings {
        var scroll: OPTIONS_SCROLL_DEFAULT
        var thumbWheel: ThumbWheelSettings?

        /// The defaults for the app (nil: the tab).
        static func defaults(for application: Application?) -> ResettableSettings {
            return ResettableSettings(scroll: OPTIONS_SCROLL_DEFAULT(), thumbWheel: application == nil ? .default : nil)
        }
    }

    /// Gives the app (nil: the Scrolling tab) new default scroll options, and the tab default
    /// thumb wheel settings; Undo gives back the ones it had. The undo target is the
    /// settings, not this controller: an app's page and its controller are gone once the
    /// list shows again, and its Undo still works.
    private static func resetScrollOptions(
        of application: Application?,
        undoManager undo: UndoManager?,
        didChange: @escaping () -> Void
    ) {
        let previous = replaceSettings(of: application, with: .defaults(for: application))
        didChange()
        guard let undo else { return }
        undo.registerUndo(withTarget: Options.shared) { [weak undo] _ in
            Self.restoreScrollOptions(previous, of: application, undoManager: undo, didChange: didChange)
        }
        undo.setActionName(NSLocalizedString("scrolling-undo-reset", comment: ""))
    }

    /// Undo of a reset: the settings from before it, every value as it was. Redo resets again.
    private static func restoreScrollOptions(
        _ settings: ResettableSettings,
        of application: Application?,
        undoManager undo: UndoManager?,
        didChange: @escaping () -> Void
    ) {
        replaceSettings(of: application, with: settings)
        didChange()
        guard let undo else { return }
        undo.registerUndo(withTarget: Options.shared) { [weak undo] _ in
            Self.resetScrollOptions(of: application, undoManager: undo, didChange: didChange)
        }
        undo.setActionName(NSLocalizedString("scrolling-undo-reset", comment: ""))
    }

    /// Puts `settings` in place of the app's (nil: the global) scroll options, and of the
    /// thumb wheel settings when it has them, and returns the ones it replaced. A reset only
    /// ever swaps the whole scroll container, so the replaced one keeps every value it had.
    /// The thumb wheel settings are written only when they differ.
    @discardableResult
    private static func replaceSettings(
        of application: Application?,
        with settings: ResettableSettings
    ) -> ResettableSettings {
        if let application {
            let previous = application.scroll
            application.scroll = settings.scroll
            return ResettableSettings(scroll: previous, thumbWheel: nil)
        }
        let previous = ResettableSettings(scroll: Options.shared.scroll, thumbWheel: Options.shared.thumbWheel)
        Options.shared.scroll = settings.scroll
        if let thumbWheel = settings.thumbWheel, Options.shared.thumbWheel != thumbWheel {
            Options.shared.thumbWheel = thumbWheel
        }
        return previous
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

    /// "Advanced": the first row of the last box; it opens the rest of that box.
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
            ends: (low: text("scrolling-glide-time-shorter"), high: text("scrolling-glide-time-longer")),
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
            ends: (low: text("scrolling-step-smaller"), high: text("scrolling-step-larger")),
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

    // MARK: Thumb wheel

    /// "Action": the six functions in a pop-up, each with its symbol; the line under the
    /// title says what the chosen one does.
    private func makeThumbWheelFunctionRow() -> PreferencesGroupRow {
        let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
        popUp.identifier = Identifier.thumbWheelFunction
        popUp.target = self
        popUp.action = #selector(thumbWheelFunctionChanged(_:))
        popUp.translatesAutoresizingMaskIntoConstraints = false
        popUp.widthAnchor.constraint(equalToConstant: Self.thumbWheelPopUpWidth).isActive = true
        let menu = NSMenu()
        menu.autoenablesItems = false
        for function in ThumbWheelFunction.allCases {
            // The pop-up sends its own action; the items only carry the function.
            menu.addItem(ThumbWheelPresentation.menuItem(for: function, target: nil, action: nil))
        }
        // macOS 27 hides menu item images unless asked: every function keeps its symbol.
        menu.keepItemImagesVisible()
        popUp.menu = menu
        thumbWheelFunctionPopUp = popUp

        let row = PreferencesGroupRow(
            title: text("scrolling-thumb-wheel-function"),
            explanation: ThumbWheelFunction.scroll.localizedHint,
            accessory: popUp
        )
        // Room for the longest line, so picking another function never changes the height.
        row.reservedExplanations = ThumbWheelFunction.allCases.map(\.localizedHint)
        row.explanationLabel.identifier = Identifier.thumbWheelFunctionHint
        thumbWheelFunctionRow = row
        return row
    }

    /// "Speed": 0.25× to 3× in steps of 0.05, its value next to it ("1.25×"). What it
    /// changes depends on the function: the line under the title says which.
    private func makeThumbWheelSpeedRow() -> PreferencesGroupRow {
        let setting = ThumbWheelPresentation.speedSetting
        let row = PreferencesSliderRow(
            title: text("scrolling-thumb-wheel-speed"),
            explanation: text(ThumbWheelPresentation.speedHintKey(for: .scroll, smoothing: true)),
            range: setting.range,
            scale: setting.scale,
            ends: (low: text("scrolling-speed-shorter"), high: text("scrolling-speed-farther")),
            target: self,
            action: #selector(thumbWheelSpeedChanged(_:))
        )
        row.slider.identifier = Identifier.thumbWheelSpeed
        row.reservedExplanations = ThumbWheelPresentation.speedHintKeys.map(text)
        thumbWheelSpeedRow = row
        thumbWheelSpeedSlider = row.slider
        return row
    }

    private func makeThumbWheelSwapRow() -> PreferencesGroupRow {
        let row = PreferencesSwitchRow(
            title: text("scrolling-thumb-wheel-swap"),
            explanation: text("scrolling-thumb-wheel-swap-hint"),
            target: self,
            action: #selector(thumbWheelSwapClick(_:))
        )
        row.toggle.identifier = Identifier.thumbWheelSwap
        thumbWheelSwapRow = row
        thumbWheelSwapSwitch = row.toggle
        return row
    }

    /// The muted line under the thumb wheel's box: which wheel that is. Inset like the text
    /// of the rows above it.
    private func makeThumbWheelNote() -> NSView {
        let inset = PreferencesGroupedForm.rowHorizontalInset
        let label = NSTextField(wrappingLabelWithString: text("scrolling-thumb-wheel-note"))
        label.identifier = Identifier.thumbWheelNote
        label.font = PreferencesGroupedForm.explanationFont
        label.textColor = PreferencesGroupedForm.explanationColor(enabled: true)
        label.isSelectable = false
        label.preferredMaxLayoutWidth = Self.boxWidth - 2 * inset
        label.translatesAutoresizingMaskIntoConstraints = false
        thumbWheelNote = label
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

    /// A slider with the words for its ends under it, the setting's tick marks and, on the
    /// right, the column of its value (`ScrollingSlider`). All of the tab's sliders have the
    /// same width and keep that column, also when they write no value, so they line up.
    private func makeSliderRow(
        titleKey: String,
        hintKey: String,
        setting: ScrollSliderSetting,
        ends: (low: String, high: String),
        identifier: NSUserInterfaceItemIdentifier,
        action: Selector
    ) -> PreferencesSliderRow {
        let row = PreferencesSliderRow(
            title: text(titleKey),
            explanation: text(hintKey),
            range: setting.range,
            scale: setting.scale,
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
            title: text("scrolling-key-none"),
            target: self,
            action: #selector(keyBindClick(_:))
        )
        bind.identifier = Identifier.key(key)
        bind.tag = key.rawValue
        bind.bezelStyle = .push
        bind.alignment = .left
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
        clear.setAccessibilityLabel(String(format: text("scrolling-key-clear-for"), text(key.labelKey)))
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

    /// What the recorder buttons say, in the order of `hotkeys`: each key as the Buttons pane
    /// names its triggers ("⌥", "K", "Back button", "Button 5", a Logitech control's name,
    /// "Back button (Logitech)" next to a standard Back button), "None" for a row without a
    /// key. Display only: the stored keys are not touched.
    static func holdKeyTitles(
        for hotkeys: [ScrollHotkey?],
        logitech: ButtonTriggerNaming.Logitech = .live
    ) -> [String] {
        let events = hotkeys.compactMap { $0 }.map {
            RecordedEvent(type: $0.type, code: $0.code, modifiers: 0, deviceFilter: nil)
        }
        var names = ButtonTriggerNaming.titles(for: events, logitech: logitech).makeIterator()
        return hotkeys.map { hotkey in
            guard hotkey != nil, let name = names.next() else {
                return NSLocalizedString("scrolling-key-none", comment: "A hold key that is not set")
            }
            return name
        }
    }

    /// The recorder buttons' titles and whether there is a key to clear.
    private func updateKeyButtons(in scroll: OPTIONS_SCROLL_DEFAULT, enabled: Bool) {
        let hotkeys = ScrollHoldKey.allCases.map { $0.hotkey(in: scroll) }
        let titles = Self.holdKeyTitles(for: hotkeys)
        for key in ScrollHoldKey.allCases {
            let button = keyBindButtons[key.rawValue]
            button.title = titles[key.rawValue]
            button.isEnabled = enabled

            // The clear button only shows while there is a key to clear. Hidden by its alpha,
            // so the recorder keeps its place; out of the accessibility tree while hidden.
            let canClear = hotkeys[key.rawValue] != nil && enabled
            let clear = keyClearButtons[key.rawValue]
            clear.alphaValue = canClear ? 1.0 : 0.0
            clear.isEnabled = canClear
            clear.setAccessibilityElement(canClear)
        }
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
