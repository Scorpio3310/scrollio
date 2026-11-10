//
//  ScrollTuningSettingsPopover.swift
//  Mos
//
//  Scroll presets, free-spin and acceleration settings, opened from the Scrolling tab.
//  Everything here is global (Options.shared.scroll / Options.shared.scrollTuning) and
//  applies immediately.
//
//  CONTRACT: PreferencesScrollingViewController uses `onSettingsChanged`, `onClose`,
//  `show(at:)` and `hide()`. Keep these signatures.
//

import Cocoa

/// Slider steps, clamping and value labels, kept out of the view code so they can be tested.
enum ScrollTuningControlValues {
    static let smoothnessStep = 0.05
    static let speedStep = 0.05
    static let accelerationStep = 0.05

    /// Clamps `value` into `range` and rounds it to the nearest `step` from the lower bound.
    static func snapped(_ value: Double, to range: ClosedRange<Double>, step: Double) -> Double {
        guard value.isFinite else { return range.lowerBound }
        let clamped = min(range.upperBound, max(range.lowerBound, value))
        guard step > 0 else { return clamped }
        let rounded = range.lowerBound + ((clamped - range.lowerBound) / step).rounded() * step
        // Drop floating-point noise so stored values stay tidy (0.8, not 0.8000000000000002).
        let tidy = (rounded * 1_000_000).rounded() / 1_000_000
        return min(range.upperBound, max(range.lowerBound, tidy))
    }

    static func smoothnessText(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    static func speedText(_ value: Double) -> String {
        String(format: "%.2f×", value)
    }

    static func accelerationText(_ value: Double) -> String {
        guard value >= accelerationStep / 2 else {
            return NSLocalizedString("scroll-tuning-acceleration-off", comment: "")
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int((value * 100).rounded()))%"
    }
}

final class ScrollTuningSettingsPopover: NSObject, NSPopoverDelegate {

    /// Called after any change to Options.shared.scroll or Options.shared.scrollTuning.
    var onSettingsChanged: (() -> Void)?
    var onClose: (() -> Void)?

    private var popover: NSPopover?
    private var controls: Controls?

    private static let contentWidth: CGFloat = 340
    private static let padding: CGFloat = 16
    private static let columnSpacing: CGFloat = 10
    private static let valueColumnWidth: CGFloat = 48
    private static let customPresetTag = -1

    /// Identifiers for the controls (tests and accessibility tooling).
    enum Identifier {
        static let preset = NSUserInterfaceItemIdentifier("scroll-tuning-preset")
        static let presetDescription = NSUserInterfaceItemIdentifier("scroll-tuning-preset-description")
        static let freeSpin = NSUserInterfaceItemIdentifier("scroll-tuning-free-spin")
        static let smoothness = NSUserInterfaceItemIdentifier("scroll-tuning-free-spin-smoothness")
        static let speed = NSUserInterfaceItemIdentifier("scroll-tuning-free-spin-speed")
        static let acceleration = NSUserInterfaceItemIdentifier("scroll-tuning-acceleration")
    }

    /// Which tuning value a slider edits.
    private enum SliderKind: Int {
        case smoothness, speed, acceleration

        var range: ClosedRange<Double> {
            switch self {
            case .smoothness: return ScrollTuningSettings.freeSpinSmoothnessRange
            case .speed: return ScrollTuningSettings.freeSpinSpeedRange
            case .acceleration: return ScrollTuningSettings.accelerationRange
            }
        }

        var step: Double {
            switch self {
            case .smoothness: return ScrollTuningControlValues.smoothnessStep
            case .speed: return ScrollTuningControlValues.speedStep
            case .acceleration: return ScrollTuningControlValues.accelerationStep
            }
        }

        var titleKey: String {
            switch self {
            case .smoothness: return "scroll-tuning-free-spin-smoothness"
            case .speed: return "scroll-tuning-free-spin-speed"
            case .acceleration: return "scroll-tuning-acceleration"
            }
        }

        var identifier: NSUserInterfaceItemIdentifier {
            switch self {
            case .smoothness: return Identifier.smoothness
            case .speed: return Identifier.speed
            case .acceleration: return Identifier.acceleration
            }
        }

        func value(in tuning: ScrollTuningSettings) -> Double {
            switch self {
            case .smoothness: return tuning.freeSpinSmoothness
            case .speed: return tuning.freeSpinSpeed
            case .acceleration: return tuning.acceleration
            }
        }

        func store(_ value: Double, in tuning: inout ScrollTuningSettings) {
            switch self {
            case .smoothness: tuning.freeSpinSmoothness = value
            case .speed: tuning.freeSpinSpeed = value
            case .acceleration: tuning.acceleration = value
            }
        }

        func text(for value: Double) -> String {
            switch self {
            case .smoothness: return ScrollTuningControlValues.smoothnessText(value)
            case .speed: return ScrollTuningControlValues.speedText(value)
            case .acceleration: return ScrollTuningControlValues.accelerationText(value)
            }
        }
    }

    private struct SliderRow {
        let kind: SliderKind
        let label: NSTextField
        let slider: NSSlider
        let valueLabel: NSTextField

        func setEnabled(_ enabled: Bool) {
            slider.isEnabled = enabled
            label.textColor = enabled ? .secondaryLabelColor : .tertiaryLabelColor
            valueLabel.textColor = enabled ? .secondaryLabelColor : .tertiaryLabelColor
        }
    }

    private struct Controls {
        let presetPopUp: NSPopUpButton
        let presetDescription: NSTextField
        let freeSpinCheckbox: NSButton
        let sliders: [SliderRow]
    }

    // MARK: - Show / hide

    func show(at sourceView: NSView) {
        hide()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = makeContentViewController()
        popover.show(relativeTo: sourceView.bounds, of: sourceView, preferredEdge: .maxY)
        self.popover = popover
    }

    func hide() {
        popover?.close()
        popover = nil
    }

    func popoverDidClose(_ notification: Notification) {
        popover = nil
        onClose?()
    }

    // MARK: - View construction

    func makeContentViewController() -> NSViewController {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: NSLocalizedString("scroll-tuning-title", comment: ""))
        title.font = NSFont.boldSystemFont(ofSize: 13)

        // Preset
        let presetLabel = makeRowLabel(NSLocalizedString("scroll-tuning-preset-label", comment: ""))
        let presetPopUp = makePresetPopUp()
        presetPopUp.setAccessibilityLabel(presetLabel.stringValue)
        let presetDescription = NSTextField(wrappingLabelWithString: "")
        presetDescription.identifier = Identifier.presetDescription
        presetDescription.font = NSFont.systemFont(ofSize: 11)
        presetDescription.textColor = .secondaryLabelColor

        // Free-spin
        let freeSpinCheckbox = NSButton(
            checkboxWithTitle: NSLocalizedString("scroll-tuning-free-spin-checkbox", comment: ""),
            target: self,
            action: #selector(freeSpinToggled(_:))
        )
        freeSpinCheckbox.identifier = Identifier.freeSpin
        let smoothness = makeSliderRow(.smoothness)
        let speed = makeSliderRow(.speed)

        // Acceleration
        let acceleration = makeSliderRow(.acceleration)

        let empty = NSGridCell.emptyContentView
        let grid = NSGridView(views: [
            [presetLabel, presetPopUp, empty],
            [empty, presetDescription, empty],
            [makeSeparator(), empty, empty],
            [empty, freeSpinCheckbox, empty],
            [smoothness.label, smoothness.slider, smoothness.valueLabel],
            [speed.label, speed.slider, speed.valueLabel],
            [makeSeparator(), empty, empty],
            [acceleration.label, acceleration.slider, acceleration.valueLabel],
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 8
        grid.columnSpacing = Self.columnSpacing
        grid.rowAlignment = .none
        grid.yPlacement = .center
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        grid.column(at: 2).xPlacement = .trailing
        grid.column(at: 2).width = Self.valueColumnWidth
        // Popup, description and checkbox span the slider and value columns; separators span all.
        for row in [0, 1, 3] {
            grid.mergeCells(inHorizontalRange: NSRange(location: 1, length: 2), verticalRange: NSRange(location: row, length: 1))
        }
        for row in [2, 6] {
            grid.mergeCells(inHorizontalRange: NSRange(location: 0, length: 3), verticalRange: NSRange(location: row, length: 1))
            grid.row(at: row).topPadding = 4
            grid.row(at: row).bottomPadding = 4
            grid.cell(atColumnIndex: 0, rowIndex: row).xPlacement = .fill
        }
        grid.cell(atColumnIndex: 1, rowIndex: 1).xPlacement = .fill
        grid.cell(atColumnIndex: 1, rowIndex: 1).yPlacement = .top
        grid.cell(atColumnIndex: 1, rowIndex: 3).xPlacement = .leading
        grid.row(at: 1).topPadding = -2

        let footnote = NSTextField(wrappingLabelWithString: NSLocalizedString("scroll-tuning-footnote", comment: ""))
        footnote.font = NSFont.systemFont(ofSize: 11)
        footnote.textColor = .tertiaryLabelColor

        let stack = NSStackView(views: [title, grid, footnote])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(14, after: title)
        stack.setCustomSpacing(14, after: grid)
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        // Fixed widths keep wrapping labels deterministic. The description reserves the height
        // of its longest text so the popover does not jump when switching presets.
        let innerWidth = Self.contentWidth - 2 * Self.padding
        let labelColumnWidth = ceil([presetLabel, smoothness.label, speed.label, acceleration.label]
            .map { $0.fittingSize.width }.max() ?? 0)
        let descriptionWidth = innerWidth - labelColumnWidth - Self.columnSpacing
        presetDescription.preferredMaxLayoutWidth = descriptionWidth
        footnote.preferredMaxLayoutWidth = innerWidth
        let descriptionBounds = NSRect(x: 0, y: 0, width: descriptionWidth, height: .greatestFiniteMagnitude)
        let descriptionHeight = Self.descriptionTexts.map { text -> CGFloat in
            presetDescription.stringValue = text
            return ceil(presetDescription.cell?.cellSize(forBounds: descriptionBounds).height ?? 0)
        }.max() ?? 0

        let padding = Self.padding
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: Self.contentWidth),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: padding),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -padding),
            grid.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footnote.widthAnchor.constraint(equalTo: stack.widthAnchor),
            presetDescription.widthAnchor.constraint(equalToConstant: descriptionWidth),
            presetDescription.heightAnchor.constraint(greaterThanOrEqualToConstant: descriptionHeight),
        ])

        controls = Controls(
            presetPopUp: presetPopUp,
            presetDescription: presetDescription,
            freeSpinCheckbox: freeSpinCheckbox,
            sliders: [smoothness, speed, acceleration]
        )
        syncControls()

        let vc = NSViewController()
        vc.view = container
        return vc
    }

    private func makeRowLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.alignment = .right
        label.textColor = .secondaryLabelColor
        return label
    }

    private func makeSeparator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        return separator
    }

    private func makePresetPopUp() -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.identifier = Identifier.preset
        popup.target = self
        popup.action = #selector(presetSelected(_:))

        let menu = NSMenu()
        menu.autoenablesItems = false
        for (index, preset) in ScrollPreset.allCases.enumerated() {
            let item = NSMenuItem(title: preset.localizedName, action: nil, keyEquivalent: "")
            item.tag = index
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())
        // Selected when the values match no preset; choosing it changes nothing.
        let custom = NSMenuItem(title: ScrollPreset.customLocalizedName, action: nil, keyEquivalent: "")
        custom.tag = Self.customPresetTag
        menu.addItem(custom)

        popup.menu = menu
        return popup
    }

    private func makeSliderRow(_ kind: SliderKind) -> SliderRow {
        let label = makeRowLabel(NSLocalizedString(kind.titleKey, comment: ""))

        let slider = NSSlider(
            value: kind.range.lowerBound,
            minValue: kind.range.lowerBound,
            maxValue: kind.range.upperBound,
            target: self,
            action: #selector(sliderChanged(_:))
        )
        slider.tag = kind.rawValue
        slider.identifier = kind.identifier
        slider.isContinuous = true
        slider.setAccessibilityLabel(label.stringValue)

        let valueLabel = NSTextField(labelWithString: "")
        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right

        return SliderRow(kind: kind, label: label, slider: slider, valueLabel: valueLabel)
    }

    private static var customDescription: String {
        NSLocalizedString("scroll-preset-custom-description", comment: "")
    }

    private static var smoothOffDescription: String {
        NSLocalizedString("scroll-preset-smooth-off-description", comment: "")
    }

    /// Every text the preset description can show.
    private static var descriptionTexts: [String] {
        ScrollPreset.allCases.map { $0.localizedDescription } + [customDescription, smoothOffDescription]
    }

    // MARK: - Sync

    /// Reads the global settings into every control.
    private func syncControls(except activeSlider: NSSlider? = nil) {
        guard let controls else { return }
        let scroll = Options.shared.scroll
        let tuning = Options.shared.scrollTuning
        let preset = ScrollPreset.matching(scroll: scroll, tuning: tuning)

        if let preset, let index = ScrollPreset.allCases.firstIndex(of: preset) {
            controls.presetPopUp.selectItem(withTag: index)
            controls.presetDescription.stringValue = preset.localizedDescription
        } else {
            controls.presetPopUp.selectItem(withTag: Self.customPresetTag)
            controls.presetDescription.stringValue = scroll.smooth ? Self.customDescription : Self.smoothOffDescription
        }

        controls.freeSpinCheckbox.state = tuning.freeSpinEnabled ? .on : .off
        for row in controls.sliders {
            let value = row.kind.value(in: tuning)
            if row.slider !== activeSlider {
                row.slider.doubleValue = value
            }
            row.valueLabel.stringValue = row.kind.text(for: value)
            row.setEnabled(row.kind == .acceleration || tuning.freeSpinEnabled)
        }
    }

    // MARK: - Actions

    @objc private func presetSelected(_ sender: NSPopUpButton) {
        let tag = sender.selectedTag()
        if ScrollPreset.allCases.indices.contains(tag) {
            ScrollPreset.allCases[tag].apply()
            onSettingsChanged?()
        }
        syncControls()
    }

    @objc private func freeSpinToggled(_ sender: NSButton) {
        Options.shared.scrollTuning.freeSpinEnabled = sender.state == .on
        syncControls()
        onSettingsChanged?()
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        guard let kind = SliderKind(rawValue: sender.tag) else { return }
        let value = ScrollTuningControlValues.snapped(sender.doubleValue, to: kind.range, step: kind.step)
        var tuning = Options.shared.scrollTuning
        kind.store(value, in: &tuning)
        if tuning != Options.shared.scrollTuning {
            Options.shared.scrollTuning = tuning
            onSettingsChanged?()
        }
        syncControls(except: sender)
    }
}
