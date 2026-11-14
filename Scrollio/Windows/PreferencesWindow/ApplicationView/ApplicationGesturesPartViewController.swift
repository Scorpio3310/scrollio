//
//  ApplicationGesturesPartViewController.swift
//  Scrollio
//
//  The Gestures part of an app's page: "Use the general gestures" and, while it is off,
//  the app's own set: the five rows of the Gestures pane (Up, Down, Left, Right, Click, the
//  same pull-downs, "Keyboard Shortcut…" with a name and an icon among them) and "Invert
//  left and right". They run while the app is in front (`MouseGestureChoice`). The mode,
//  the swipe speed, the freeze switch and what a Logitech mouse does are the same for every
//  app and stay in the Gestures pane; in "Follow the hand" the Left and Right rows say so,
//  as the pane's do. The button to hold is a binding of Buttons, or of the app's Buttons
//  part: while it is another one with the app in front (or none), a line under the
//  switch's box says so.
//

import Cocoa

final class ApplicationGesturesPartViewController: NSViewController, ApplicationPagePartController {

    enum Identifier {
        static let generalGestures = NSUserInterfaceItemIdentifier("apps-detail-general-gestures")
        static let buttonNote = NSUserInterfaceItemIdentifier("apps-detail-gestures-button-note")
    }

    typealias Slot = MouseGestureSettingsControls.Slot

    let application: Application
    var onHeightChange: (() -> Void)?
    /// Whether the menus offer Logitech actions (a Logitech button runs Gesture
    /// Navigation), as in the Gestures pane. Tests replace it.
    var showsLogiActions: () -> Bool = { MouseGestureBindingSummary.current.hasLogitechGestureButton }
    /// Whether "Follow the hand" can run at all (without it the mode is discrete). Tests
    /// replace it.
    var isInteractiveAvailable: () -> Bool = { DockSwipeSynthesizer.shared.isAvailable }

    private(set) var generalSection: PreferencesGroupSection!
    private(set) var generalGesturesRow: PreferencesSwitchRow!
    /// The line under the switch's box: in sight only while the button to hold differs
    /// with the app in front from the one of Buttons (`buttonNote(for:general:)`).
    private(set) var buttonNoteLabel: NSTextField!
    /// The app's own set: there only while "Use the general gestures" is off.
    private(set) var controls: MouseGestureSettingsControls?
    /// Up, Down, Left, Right, Click, in `Slot.allCases` order; empty while the app uses the
    /// general gestures.
    private(set) var directionRows: [PreferencesGroupRow] = []
    private(set) var directionsSection: PreferencesGroupSection?
    private(set) var invertRow: PreferencesGroupRow?
    private(set) var invertSection: PreferencesGroupSection?
    private var content: NSStackView!

    var generalGesturesSwitch: NSSwitch { return generalGesturesRow.toggle }

    init(application: Application) {
        self.application = application
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("ApplicationGesturesPartViewController is built in code")
    }

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        content = PreferencesGroupedForm.installContentStack(in: root, paneWidth: ApplicationDetailViewController.paneWidth)
        let name = application.getName()
        let general = PreferencesSwitchRow(
            title: text("apps-detail-gestures-general"),
            explanation: nil,
            target: self,
            action: #selector(generalGesturesClick(_:))
        )
        general.toggle.identifier = Identifier.generalGestures
        // Room for the longer of the two lines, so switching never moves the rows below.
        general.reservedExplanations = [true, false].map { ApplicationDetailViewController.generalGesturesExplanation(on: $0, name: name) }
        generalGesturesRow = general
        // (No title: the part's segment names it.)
        let section = PreferencesGroupSection(width: Self.boxWidth, rows: [general])
        generalSection = section
        let note = NSTextField(wrappingLabelWithString: "")
        note.identifier = Identifier.buttonNote
        note.font = PreferencesGroupedForm.explanationFont
        note.textColor = PreferencesGroupedForm.explanationColor(enabled: true)
        note.isSelectable = false
        let inset = PreferencesGroupedForm.rowHorizontalInset
        note.preferredMaxLayoutWidth = Self.boxWidth - 2 * inset
        note.translatesAutoresizingMaskIntoConstraints = false
        buttonNoteLabel = note
        let holder = NSView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        holder.isHidden = true
        holder.addSubview(note)
        NSLayoutConstraint.activate([
            note.topAnchor.constraint(equalTo: holder.topAnchor),
            note.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
            note.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: inset),
            note.trailingAnchor.constraint(equalTo: holder.trailingAnchor, constant: -inset),
        ])
        PreferencesGroupedForm.add([section, holder], to: content)
        view = root
        syncViewWithOptions()
    }

    /// The line under the switch's box while the button that runs Gesture Navigation with
    /// the app in front is not the one of Buttons: the app's own buttons gave that button
    /// another action ("…no button runs Gesture Navigation…"), or gave another one Gesture
    /// Navigation ("Button to hold while Figma is in front: Back button."). nil: the same
    /// button as in Buttons. The bindings counted are what a press goes by
    /// (`ApplicationButtons.merged`), with the Gestures pane's rule of what runs gestures.
    static func buttonNote(for application: Application, general: [ButtonBinding]) -> String? {
        let merged = ApplicationButtons.merged(general: general, own: application.ownButtonBindings)
        let runs: (ButtonBinding) -> Bool = {
            $0.isEnabled && $0.triggerEvent.type == .mouse
                && $0.systemShortcutName == SystemShortcut.mouseGestureNavigation.identifier
        }
        guard merged.filter(runs).map(\.identity) != general.filter(runs).map(\.identity) else { return nil }
        let name = application.getName()
        let titles = MouseGestureBindingSummary(bindings: merged, isLogitechCode: { _ in false }).buttonTitles
        guard !titles.isEmpty else {
            return String(format: NSLocalizedString("apps-detail-gestures-no-button", comment: ""), name)
        }
        let buttons = ListFormatter.localizedString(byJoining: titles)
        return String(format: NSLocalizedString("apps-detail-gestures-button", comment: ""), name, buttons)
    }

    /// Shows the line, or takes it away: a line sits close under its box; without it the
    /// titled box of the app's own set keeps its gap. The page's height follows.
    private func syncButtonNote() {
        guard let holder = buttonNoteLabel.superview else { return }
        let note = Self.buttonNote(for: application, general: Options.shared.buttons.binding)
        buttonNoteLabel.stringValue = note ?? ""
        content.setCustomSpacing(
            note == nil ? PreferencesGroupedForm.sectionSpacing : PreferencesGroupedForm.noteSpacing, after: generalSection
        )
        guard holder.isHidden != (note == nil) else { return }
        holder.isHidden = note == nil
        if view.superview != nil {
            onHeightChange?()
        }
    }

    private static var boxWidth: CGFloat {
        return PreferencesGroupedForm.boxWidth(paneWidth: ApplicationDetailViewController.paneWidth)
    }

    private func text(_ key: String) -> String {
        return NSLocalizedString(key, comment: "")
    }

    // MARK: - ApplicationPagePartController

    func syncViewWithOptions() {
        guard isViewLoaded else { return }
        let usesGeneral = application.usesGeneralGestures
        generalGesturesRow.isOn = usesGeneral
        generalGesturesRow.explanation = ApplicationDetailViewController.generalGesturesExplanation(
            on: usesGeneral, name: application.getName()
        )
        syncButtonNote()
        showOwnSet(!usesGeneral)
        guard let controls else { return }
        controls.showLogiActions = showsLogiActions()
        controls.sync()
        applyModeRules()
    }

    func partWillHide() {
        controls?.endEditing()
    }

    // MARK: - The app's own set

    /// The Left and Right rows are dimmed while the desktop follows the hand (the general
    /// mode), as in the Gestures pane; their pull-downs say so (`MouseGestureSettingsControls`).
    private func applyModeRules() {
        guard let controls else { return }
        let editable = controls.modePresentation.areHorizontalActionsEditable
        for slot in Slot.allCases where slot.isHorizontal {
            directionRows[slot.rawValue].isEnabled = editable
        }
    }

    /// Puts the app's own set (the five rows and the invert switch) under the switch's
    /// box, or takes it away again: it is there exactly while "Use the general gestures"
    /// is off.
    private func showOwnSet(_ shows: Bool) {
        guard shows != (controls != nil) else { return }
        if let controls {
            controls.endEditing()
            for section in [directionsSection, invertSection].compactMap({ $0 }) {
                content.removeArrangedSubview(section)
                section.removeFromSuperview()
            }
            self.controls = nil
            directionRows = []
            directionsSection = nil
            invertRow = nil
            invertSection = nil
            return
        }
        let controls = MouseGestureSettingsControls(
            showLogiActions: showsLogiActions(),
            edits: .application(application),
            isInteractiveAvailable: { [weak self] in self?.isInteractiveAvailable() ?? false }
        )
        controls.onChange = { [weak self] in self?.applyModeRules() }
        self.controls = controls
        // The rows of the Gestures pane, each with its pull-down (`popUpWidth` wide by itself).
        directionRows = Slot.allCases.map { slot in
            PreferencesGroupRow(title: text(slot.labelKey), accessory: controls.actionPopUp(for: slot))
        }
        let directions = PreferencesGroupSection(title: text("gestures-directions-header"), width: Self.boxWidth, rows: directionRows)
        directionsSection = directions
        let invert = PreferencesGroupRow(
            title: text("gesture-invert-horizontal"),
            explanation: text("gesture-invert-horizontal-hint"),
            accessory: controls.invertToggle
        )
        invertRow = invert
        let invertBox = PreferencesGroupSection(width: Self.boxWidth, rows: [invert])
        invertSection = invertBox
        PreferencesGroupedForm.add([directions, invertBox], to: content)
    }

    // MARK: - Actions

    /// On: the gestures of the Gestures pane run while the app is in front; the app's own
    /// set stays stored for later. Off: the app's own set, which starts as a copy of the
    /// general actions and invert switch as they are now when the app never had one.
    @objc func generalGesturesClick(_ sender: NSSwitch) {
        // First what is being edited (a name typed in a row's popover) goes into the set,
        // while it is still the app's own.
        controls?.endEditing()
        application.setUsesGeneralGestures(sender.state == .on, general: Options.shared.gesture)
        syncViewWithOptions()
        onHeightChange?()
    }
}
