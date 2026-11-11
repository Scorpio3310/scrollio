//
//  MouseGestureSettingsPopover.swift
//  Mos
//  Gesture Navigation settings next to a button bound to it: mode, action per direction
//  and click, invert left/right, freeze pointer. A shortcut to what the Gestures tab
//  shows; both use MouseGestureSettingsControls, so changes apply immediately to
//  Options.shared.gesture.
//

import Cocoa

final class MouseGestureSettingsPopover: NSObject, NSPopoverDelegate {

    var onClose: (() -> Void)?

    /// Identifiers for the controls (tests and accessibility tooling).
    typealias Identifier = MouseGestureSettingsControls.Identifier

    private var popover: NSPopover?
    private var showLogiActions = false
    private let isInteractiveAvailable: () -> Bool
    /// Controls of the content view built last. They are the target of that view's
    /// controls, so they live as long as the popover object.
    private var controls: MouseGestureSettingsControls?

    init(isInteractiveAvailable: @escaping () -> Bool = { DockSwipeSynthesizer.shared.isAvailable }) {
        self.isInteractiveAvailable = isInteractiveAvailable
        super.init()
    }

    /// Minimum sizes; long translations widen the popups (up to `maximumPopupWidth`) and the popover.
    private static let contentWidth: CGFloat = 330
    private static let padding: CGFloat = 16
    private static let columnSpacing: CGFloat = 10
    private static let popupWidth: CGFloat = 210
    private static let maximumPopupWidth: CGFloat = 300

    // MARK: - Show / hide

    func show(at sourceView: NSView, showLogiActions: Bool) {
        hide()
        self.showLogiActions = showLogiActions

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
        let controls = MouseGestureSettingsControls(
            showLogiActions: showLogiActions,
            isInteractiveAvailable: isInteractiveAvailable
        )
        self.controls = controls

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: NSLocalizedString("mouseGestureNavigation", comment: ""))
        title.font = NSFont.boldSystemFont(ofSize: 13)

        let mode = controls.modeControl
        // Spans the popover; each segment as wide as its label needs.
        mode.segmentDistribution = .fillProportionally
        let modeNote = controls.modeNote

        var labels: [NSTextField] = []
        let popups = controls.actionPopUps
        let rows: [[NSView]] = MouseGestureSettingsControls.Slot.allCases.map { slot in
            let label = NSTextField(labelWithString: "\(slot.symbol)  " + NSLocalizedString(slot.labelKey, comment: ""))
            label.alignment = .right
            label.textColor = NSColor.secondaryLabelColor
            labels.append(label)
            return [label, controls.actionPopUp(for: slot)]
        }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 8
        grid.columnSpacing = Self.columnSpacing
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline

        let separator = NSBox()
        separator.boxType = .separator

        let invert = controls.invertCheckbox
        let freeze = controls.freezeCheckbox

        let footnote = NSTextField(wrappingLabelWithString: NSLocalizedString("gesture-settings-footnote", comment: ""))
        footnote.font = NSFont.systemFont(ofSize: 11)
        footnote.textColor = NSColor.tertiaryLabelColor

        let stack = NSStackView(views: [title, mode, modeNote, grid, separator, invert, freeze, footnote])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(12, after: title)
        stack.setCustomSpacing(6, after: mode)
        stack.setCustomSpacing(14, after: modeNote)
        stack.setCustomSpacing(12, after: grid)
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        // Popups fit the actions shown now (long translated names such as "Move Space Left")
        // and the value the Left / Right rows show in follow mode, within limits; the popover
        // grows with them, with long checkbox titles and with the mode control.
        let labelColumnWidth = ceil(labels.map { $0.fittingSize.width }.max() ?? 0)
        let widestPopup = max(
            popups.map { MouseGestureSettingsControls.fittingWidth(of: $0) }.max() ?? 0,
            popups.first.map {
                MouseGestureSettingsControls.fittingWidth(of: $0, title: MouseGestureSettingsControls.followHorizontalValue)
            } ?? 0
        )
        let minimumPopupWidth = min(Self.maximumPopupWidth, max(Self.popupWidth, ceil(widestPopup)))
        let widestCheckbox = ceil([invert, freeze].map { $0.fittingSize.width }.max() ?? 0)
        let contentWidth = max(
            Self.contentWidth,
            2 * Self.padding + labelColumnWidth + Self.columnSpacing + minimumPopupWidth,
            2 * Self.padding + widestCheckbox,
            2 * Self.padding + ceil(mode.fittingSize.width)
        )
        // The popups take the room the labels leave, so every row ends at the right edge,
        // in line with the mode control and the separator.
        let popupWidth = contentWidth - 2 * Self.padding - labelColumnWidth - Self.columnSpacing
        grid.column(at: 0).width = labelColumnWidth
        for popup in popups {
            popup.widthAnchor.constraint(equalToConstant: popupWidth).isActive = true
        }

        let padding = Self.padding
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: contentWidth),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: padding),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -padding),
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footnote.widthAnchor.constraint(equalTo: stack.widthAnchor),
            mode.widthAnchor.constraint(equalTo: stack.widthAnchor),
            modeNote.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        let viewController = NSViewController()
        viewController.view = container
        return viewController
    }

    /// The actions the popups offer; see `MouseGestureSettingsControls.actionCategories`.
    static func actionCategories(showLogiActions: Bool) -> [(category: String, shortcuts: [SystemShortcut.Shortcut])] {
        return MouseGestureSettingsControls.actionCategories(showLogiActions: showLogiActions)
    }
}
