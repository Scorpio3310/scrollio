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
//  part: while none runs the gestures with the app in front, the switch's line says so
//  instead (in both states); while it is another one than Buttons', a line under the
//  switch's box names it.
//
//  "Reset to Defaults" ends the own set, there with it: the five actions (with their
//  names and icons) and the invert switch go back to a copy of the general ones as they
//  are now, the switch stays; the window's Undo takes it back, also after the page closed.
//
//  While no button runs the gestures with the app in front (`ApplicationTriggerRule`),
//  the title "Directions" folds the own set and its button away
//  (`PreferencesDisclosureSection`, as the Gestures pane folds its settings): a click opens
//  them, all of it editable. Once a button runs them there, "Directions" is a plain title
//  again and the set shows as before.
//

import Cocoa

final class ApplicationGesturesPartViewController: NSViewController, ApplicationPagePartController {

    enum Identifier {
        static let generalGestures = NSUserInterfaceItemIdentifier("apps-detail-general-gestures")
        static let buttonNote = NSUserInterfaceItemIdentifier("apps-detail-gestures-button-note")
        static let reset = NSUserInterfaceItemIdentifier("apps-detail-gestures-reset")
    }

    typealias Slot = MouseGestureSettingsControls.Slot

    let application: Application
    var onHeightChange: (() -> Void)?
    /// Takes Undo and Redo of "Reset to Defaults"; the window's when nil.
    var paneUndoManager: UndoManager?
    /// The Gestures part that shows an app's entry now, if any (the pane's answer). An Undo
    /// or Redo of "Reset to Defaults" asks it when it runs, maybe after this page closed
    /// and the app's page opened again: it must not hold the page. nil: this part, while
    /// it is there.
    var partShowing: ((Application) -> ApplicationGesturesPartViewController?)?
    /// Whether the menus offer Logitech actions: a Logitech button runs Gesture Navigation
    /// while the app is in front (`ApplicationTriggerRule`), as the Gestures pane asks of
    /// its buttons. Tests replace it.
    var showsLogiActions: () -> Bool
    /// Whether "Follow the hand" can run at all (without it the mode is discrete). Tests
    /// replace it.
    var isInteractiveAvailable: () -> Bool = { DockSwipeSynthesizer.shared.isAvailable }

    private(set) var generalSection: PreferencesGroupSection!
    private(set) var generalGesturesRow: PreferencesSwitchRow!
    /// The line under the switch's box: in sight only while another button than Buttons'
    /// runs the gestures with the app in front (`buttonNote(for:general:)`).
    private(set) var buttonNoteLabel: NSTextField!
    /// The app's own set: there only while "Use the general gestures" is off.
    private(set) var controls: MouseGestureSettingsControls?
    /// Up, Down, Left, Right, Click, in `Slot.allCases` order; empty while the app uses the
    /// general gestures.
    private(set) var directionRows: [PreferencesGroupRow] = []
    /// "Directions" and under it the own set's boxes and "Reset to Defaults"; it folds
    /// them while no button runs the gestures with the app in front.
    private(set) var directionsFold: PreferencesDisclosureSection?
    /// The box of the five rows (its title is `directionsFold`'s).
    private(set) var directionsSection: PreferencesGroupSection?
    private(set) var invertRow: PreferencesGroupRow?
    private(set) var invertSection: PreferencesGroupSection?
    /// "Reset to Defaults" under the own set, there with it.
    private(set) var resetToDefaults: PreferencesPaneReset!
    var resetToDefaultsButton: NSButton {
        return resetToDefaults.button
    }
    private(set) var resetFooter: PreferencesGroupFooter!
    private var content: NSStackView!

    var generalGesturesSwitch: NSSwitch { return generalGesturesRow.toggle }

    init(application: Application) {
        self.application = application
        showsLogiActions = { [application] in
            ApplicationTriggerRule.gestureNavigation
                .bindings(general: Options.shared.buttons.binding, own: application.ownButtonBindings)
                .contains { LogiCenter.shared.isLogiCode($0.triggerEvent.code) }
        }
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
        // A titled section's room above "Directions", under the line too.
        content.setCustomSpacing(PreferencesGroupedForm.sectionSpacing, after: holder)
        let reset = PreferencesPaneReset(
            undoActionNameKey: Self.resetActionNameKey,
            hasSettingsToReset: { [weak self] in self?.hasSettingsToReset ?? false },
            undoManager: { [weak self] in self?.undoTarget },
            reset: { [weak self] undo in self?.resetGestures(undoManager: undo) }
        )
        // What is being edited (a name typed in a row's popover) goes first.
        reset.willReset = { [weak self] in self?.controls?.endEditing() }
        reset.button.identifier = Identifier.reset
        resetToDefaults = reset
        resetFooter = PreferencesGroupFooter(trailing: [reset.button])
        view = root
        syncViewWithOptions()
    }

    /// The line under the switch's box while another button than the one of Buttons runs
    /// Gesture Navigation with the app in front: the app's own buttons gave one Gesture
    /// Navigation ("Button to hold while Figma is in front: Back button."). nil: the same
    /// button as in Buttons, or none at all (the switch's own line says that one). Counted
    /// by the rule the Gestures pane counts by (`ApplicationTriggerRule`).
    static func buttonNote(for application: Application, general: [ButtonBinding]) -> String? {
        let rule = ApplicationTriggerRule.gestureNavigation
        let here = rule.bindings(general: general, own: application.ownButtonBindings)
        guard !here.isEmpty, here.map(\.identity) != rule.bindings(general: general).map(\.identity) else { return nil }
        let titles = MouseGestureBindingSummary(bindings: here, isLogitechCode: { _ in false }).buttonTitles
        let buttons = ListFormatter.localizedString(byJoining: titles)
        return String(format: NSLocalizedString("apps-detail-gestures-button", comment: ""), application.getName(), buttons)
    }

    /// Whether a button runs Gesture Navigation while the app is in front.
    static func hasButton(for application: Application, general: [ButtonBinding]) -> Bool {
        return !ApplicationTriggerRule.gestureNavigation.bindings(general: general, own: application.ownButtonBindings).isEmpty
    }

    /// Shows the line, or takes it away: a line sits close under its box; without it the
    /// titled box of the app's own set keeps its gap. True when it came or went while the
    /// part is on screen: the page's height follows.
    private func syncButtonNote() -> Bool {
        guard let holder = buttonNoteLabel.superview else { return false }
        let note = Self.buttonNote(for: application, general: Options.shared.buttons.binding)
        buttonNoteLabel.stringValue = note ?? ""
        content.setCustomSpacing(
            note == nil ? PreferencesGroupedForm.sectionSpacing : PreferencesGroupedForm.noteSpacing, after: generalSection
        )
        guard holder.isHidden != (note == nil) else { return false }
        holder.isHidden = note == nil
        return view.superview != nil
    }

    private static var boxWidth: CGFloat {
        return PreferencesGroupedForm.boxWidth(paneWidth: ApplicationDetailViewController.paneWidth)
    }

    private func text(_ key: String) -> String {
        return NSLocalizedString(key, comment: "")
    }

    // MARK: - ApplicationPagePartController

    func syncViewWithOptions() {
        if sync() {
            onHeightChange?()
        }
    }

    /// Shows the stored settings; true when the page must measure again: the switch's line
    /// or the line under the box changed while the part is on screen (an Undo in the app's
    /// Buttons), and may take more or less room.
    @discardableResult
    private func sync() -> Bool {
        guard isViewLoaded else { return false }
        let usesGeneral = application.usesGeneralGestures
        generalGesturesRow.isOn = usesGeneral
        let hasButton = Self.hasButton(for: application, general: Options.shared.buttons.binding)
        let line = ApplicationDetailViewController.generalGesturesExplanation(
            on: usesGeneral, name: application.getName(), hasButton: hasButton
        )
        var remeasures = generalGesturesRow.explanation != line && view.superview != nil
        generalGesturesRow.explanation = line
        remeasures = syncButtonNote() || remeasures
        showOwnSet(!usesGeneral)
        // (Folds when it becomes foldable; the page measures again.)
        if let fold = directionsFold, fold.isCollapsible == hasButton {
            fold.isCollapsible = !hasButton
            remeasures = remeasures || view.superview != nil
        }
        resetToDefaults.settingsDidChange()
        guard let controls else { return remeasures }
        controls.showLogiActions = showsLogiActions()
        controls.sync()
        applyModeRules()
        return remeasures
    }

    func partWillHide() {
        controls?.endEditing()
        resetToDefaults.endUndoOffer()
    }

    // MARK: - Reset to Defaults

    /// The undo action's name: the Gestures pane's ("Reset Gestures").
    static let resetActionNameKey = "gestures-undo-reset"

    /// Where "Reset to Defaults" registers its Undo: the window's while the page is in it.
    var undoTarget: UndoManager? {
        return paneUndoManager ?? view.window?.undoManager
    }

    /// The own set is in use and differs from a copy of the general one as it is now (the
    /// five actions with their names and icons, and the invert switch).
    var hasSettingsToReset: Bool {
        guard let own = application.ownGestures else { return false }
        let general = Options.shared.gesture
        return own.actions != general.actions || own.invertHorizontal != general.invertHorizontal
    }

    /// "Reset to Defaults": the own set as the switch starts it, a copy of the general one
    /// as it is now; the switch stays off. Edit › Undo brings back the set that was there.
    private func resetGestures(undoManager undo: UndoManager?) {
        guard hasSettingsToReset else { return }
        let showing = partShowing ?? { [weak self] entry in
            self?.application === entry ? self : nil
        }
        let general = Options.shared.gesture
        Self.putGestures(
            of: application, actions: general.actions, invertHorizontal: general.invertHorizontal,
            undoManager: undo, showing: showing
        )
    }

    /// As the ring's reset (`ApplicationRingPartViewController`): the undo target is the
    /// settings, not the page; Undo and Redo find the app's entry by its path when they
    /// run, and show the change on the part `showing` gives for it. (A set kept for later
    /// takes them too: the switch is never touched.)
    private static func putGestures(
        of application: Application, actions: GestureActions, invertHorizontal: Bool, undoManager undo: UndoManager?,
        showing: @escaping (Application) -> ApplicationGesturesPartViewController?
    ) {
        guard let before = application.gestures,
              before.actions != actions || before.invertHorizontal != invertHorizontal else { return }
        application.replaceOwnGestureSet(actions: actions, invertHorizontal: invertHorizontal)
        showing(application)?.syncViewWithOptions()
        guard let undo else { return }
        let path = application.path
        undo.registerUndo(withTarget: Options.shared) { [weak undo] _ in
            guard let entry = PreferencesApplicationViewController.existingApplication(
                forPaths: PreferencesApplicationViewController.knownPaths(forStoredPath: path)
            ) else { return }
            putGestures(
                of: entry, actions: before.actions, invertHorizontal: before.invertHorizontal,
                undoManager: undo, showing: showing
            )
        }
        undo.setActionName(NSLocalizedString(resetActionNameKey, comment: ""))
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

    /// Puts the app's own set (the five rows and the invert switch) and "Reset to
    /// Defaults" under the switch's box, or takes them away again: they are there exactly
    /// while "Use the general gestures" is off.
    private func showOwnSet(_ shows: Bool) {
        guard shows != (controls != nil) else { return }
        if let controls {
            controls.endEditing()
            resetToDefaults.endUndoOffer()
            if let fold = directionsFold {
                content.removeArrangedSubview(fold)
                fold.removeFromSuperview()
            }
            resetFooter.removeFromSuperview()
            self.controls = nil
            directionRows = []
            directionsFold = nil
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
        controls.onChange = { [weak self] in
            self?.applyModeRules()
            // (A row moved the set off the general one, or back: "Reset to Defaults" follows.)
            self?.resetToDefaults.settingsDidChange()
        }
        self.controls = controls
        // The rows of the Gestures pane, each with its pull-down (`popUpWidth` wide by itself).
        directionRows = Slot.allCases.map { slot in
            PreferencesGroupRow(title: text(slot.labelKey), accessory: controls.actionPopUp(for: slot))
        }
        let directions = PreferencesGroupSection(width: Self.boxWidth, rows: directionRows)
        directionsSection = directions
        let invert = PreferencesGroupRow(
            title: text("gesture-invert-horizontal"),
            explanation: text("gesture-invert-horizontal-hint"),
            accessory: controls.invertToggle
        )
        invertRow = invert
        let invertBox = PreferencesGroupSection(width: Self.boxWidth, rows: [invert])
        invertSection = invertBox
        // The two boxes and the footer as the pane's content stack spaces them, under one
        // title that folds them (a plain title while it cannot).
        let body = NSStackView()
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = PreferencesGroupedForm.boxSpacing
        // Edge to edge, so its height is its content's also while it is folded away (its
        // bottom then holds on nothing).
        body.distribution = .fill
        body.detachesHiddenViews = true
        PreferencesGroupedForm.add([directions, invertBox, resetFooter], to: body)
        let fold = PreferencesDisclosureSection(title: text("gestures-directions-header"), body: body)
        fold.isCollapsible = !Self.hasButton(for: application, general: Options.shared.buttons.binding)
        fold.onExpandedChange = { [weak self] _ in self?.onHeightChange?() }
        directionsFold = fold
        PreferencesGroupedForm.add([fold], to: content)
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
        // (The own set came or went: the page measures again, once.)
        sync()
        onHeightChange?()
    }
}
