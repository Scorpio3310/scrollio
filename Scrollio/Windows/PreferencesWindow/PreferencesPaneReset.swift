//
//  PreferencesPaneReset.swift
//  Scrollio
//  "Reset to Defaults" for a pane whose settings are one stored value (the Shortcut Ring's
//  ring, the gesture settings): the button for the pane's footer, the reset with its Undo,
//  the few seconds in which the button reads "Undo Reset", and when it can be clicked.
//  The Buttons, Gestures and Shortcut Ring parts of an app's page use the same button
//  with a reset of their own (`init(undoActionNameKey:…)`, `init(undoActionName:…)`):
//  theirs finds the app's entry again when its Undo runs, under a name of its own, and
//  the button is named by what it does there ("Remove All Buttons", "Copy from Gestures"),
//  "Undo" for a moment after a click.
//
//  The rules are the Scrolling pane's, which keeps its own code: its reset spans two
//  stores and an app's page. Change a rule in both places.
//

import Cocoa

final class PreferencesPaneReset: NSObject {

    /// A pane's settings: what a new installation has, how to read and replace the stored
    /// ones, and what the reset is called under Edit (the catalog key of "Reset Gestures").
    struct Store<Settings: Equatable> {
        var defaults: Settings
        var read: () -> Settings
        var write: (Settings) -> Void
        var undoActionNameKey: String

        var undoActionName: String {
            return NSLocalizedString(undoActionNameKey, comment: "")
        }
    }

    /// The same two titles as in the Scrolling pane.
    static var resetTitle: String {
        return NSLocalizedString("scrolling-reset", comment: "")
    }
    static var undoTitle: String {
        return NSLocalizedString("scrolling-reset-undo", comment: "")
    }

    /// The push button for the pane's footer.
    let button: NSButton
    /// Its title, and its title while it offers to take the click back.
    let title: String
    let undoTitle: String
    /// How long the button reads "Undo Reset" after a reset. Tests shorten it.
    var undoOfferDuration: TimeInterval = 8
    /// The button offers to take the reset back (it reads "Undo Reset").
    private(set) var offersUndo = false
    /// Runs first at a click: the pane ends what is being edited (a name typed in a
    /// popover is stored), so the reset takes it with what Undo gives back. The popover
    /// starts closing at the click's mouse-down but may report it only after the action.
    var willReset: () -> Void = {}

    private let differsFromDefaults: () -> Bool
    private let resetSettings: (UndoManager?) -> Void
    private let undoActionName: String
    private let undoManager: () -> UndoManager?
    private var undoOfferWork: DispatchWorkItem?

    /// - Parameters:
    ///   - store: the pane's settings.
    ///   - undoManager: where a reset registers its Undo (nil: nowhere, and the button
    ///     offers none).
    ///   - comeForward: an Undo or Redo of the reset is about to run, maybe while another
    ///     pane shows: the pane comes forward, so that it shows where it acts (as a row's
    ///     Undo does). Not called for the reset itself, which is clicked on the pane.
    ///   - didChange: the settings were replaced (by the reset, its Undo or its Redo): the
    ///     pane shows them, and tells this object with `settingsDidChange()`.
    convenience init<Settings: Equatable>(
        store: Store<Settings>,
        undoManager: @escaping () -> UndoManager?,
        comeForward: @escaping () -> Void = {},
        didChange: @escaping () -> Void
    ) {
        self.init(
            undoActionNameKey: store.undoActionNameKey,
            hasSettingsToReset: { store.read() != store.defaults },
            undoManager: undoManager,
            reset: { Self.reset(store, undoManager: $0, comeForward: comeForward, didChange: didChange) }
        )
    }

    /// For settings that are not one stored value (the parts of an app's page): the same
    /// button and offer, with the reset and its Undo made by the caller.
    /// - Parameters:
    ///   - undoActionNameKey: the catalog key of the name `reset` gives its Undo.
    ///   - hasSettingsToReset: something differs from where a reset leads.
    ///   - reset: puts the defaults in place and registers its Undo, under that name, in
    ///     the manager it is given (nil: none).
    convenience init(
        undoActionNameKey: String,
        hasSettingsToReset: @escaping () -> Bool,
        undoManager: @escaping () -> UndoManager?,
        reset: @escaping (UndoManager?) -> Void
    ) {
        self.init(
            undoActionName: NSLocalizedString(undoActionNameKey, comment: ""),
            hasSettingsToReset: hasSettingsToReset, undoManager: undoManager, reset: reset
        )
    }

    /// The same, with the name itself (one made with the app's name), and the button's
    /// titles (an app's part names it by what it does).
    init(
        undoActionName: String,
        title: String = PreferencesPaneReset.resetTitle,
        undoTitle: String = PreferencesPaneReset.undoTitle,
        hasSettingsToReset: @escaping () -> Bool,
        undoManager: @escaping () -> UndoManager?,
        reset: @escaping (UndoManager?) -> Void
    ) {
        self.title = title
        self.undoTitle = undoTitle
        button = PreferencesGroupedForm.makePushButton(title: title, target: nil, action: nil)
        differsFromDefaults = hasSettingsToReset
        resetSettings = reset
        self.undoActionName = undoActionName
        self.undoManager = undoManager
        super.init()
        button.target = self
        button.action = #selector(click(_:))
        updateButton()
    }

    deinit {
        undoOfferWork?.cancel()
    }

    /// True while the stored settings differ from the defaults.
    var hasSettingsToReset: Bool {
        return differsFromDefaults()
    }

    /// One click, no question: the defaults, and Edit › Undo brings back every value. While
    /// the button reads "Undo Reset" and the settings are still the defaults, the click
    /// takes the reset back instead. A click while nothing differs (the button was not told
    /// yet that the settings came back by themselves, an Undo elsewhere) resets nothing and
    /// offers no "Undo Reset": the button only shows what is so.
    @objc func click(_ sender: Any?) {
        willReset()
        if offersUndo, !hasSettingsToReset {
            undoReset()
            return
        }
        guard hasSettingsToReset else {
            updateButton()
            return
        }
        resetSettings(undoManager())
        beginUndoOffer()
    }

    /// The pane has put the stored settings into its rows: a setting that moved off the
    /// defaults again (or a reset that was undone) ends the offer.
    func settingsDidChange() {
        if offersUndo, hasSettingsToReset {
            endUndoOffer()
        } else {
            updateButton()
        }
    }

    // MARK: - "Undo Reset", offered after a reset

    /// After a reset the button reads "Undo Reset" for `undoOfferDuration`: Edit › Undo takes
    /// a reset back, but nobody looks there. Only where that Undo exists (an undo manager).
    private func beginUndoOffer() {
        guard undoManager() != nil else { return }
        offersUndo = true
        updateButton()
        undoOfferWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.endUndoOffer() }
        undoOfferWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + undoOfferDuration, execute: work)
    }

    /// The button is "Reset to Defaults" again (the time is up, a setting changed, the pane
    /// went away). The reset stays on the Undo stack: Edit › Undo still takes it back.
    func endUndoOffer() {
        undoOfferWork?.cancel()
        undoOfferWork = nil
        guard offersUndo else { return }
        offersUndo = false
        updateButton()
    }

    /// "Undo Reset": what Edit › Undo does. Only the reset itself is taken back: with
    /// anything else on top of the Undo stack the button does nothing.
    private func undoReset() {
        let undo = undoManager()
        endUndoOffer()
        guard let undo, undo.canUndo, undo.undoActionName == undoActionName else { return }
        undo.undo()
    }

    /// The button's title and whether it can be clicked: "Undo Reset" while that is offered,
    /// else "Reset to Defaults", on only while something differs from the defaults.
    private func updateButton() {
        let title = offersUndo ? undoTitle : self.title
        if button.title != title {
            button.title = title
            NSAccessibility.post(element: button as Any, notification: .titleChanged)
        }
        button.isEnabled = offersUndo || hasSettingsToReset
    }

    // MARK: - Reset, with Undo

    /// Puts the defaults in place of the stored settings; Undo gives back the ones that were
    /// there. The undo target is the settings, not a pane: Undo and Redo work whichever
    /// pane shows, and bring the reset's pane forward first (`comeForward`).
    private static func reset<Settings>(
        _ store: Store<Settings>,
        undoManager undo: UndoManager?,
        comeForward: @escaping () -> Void,
        didChange: @escaping () -> Void
    ) {
        let previous = store.read()
        store.write(store.defaults)
        didChange()
        guard let undo else { return }
        undo.registerUndo(withTarget: Options.shared) { [weak undo] _ in
            comeForward()
            Self.restore(previous, to: store, undoManager: undo, comeForward: comeForward, didChange: didChange)
        }
        undo.setActionName(store.undoActionName)
    }

    /// Undo of a reset: the settings from before it, every value as it was. Redo resets again.
    private static func restore<Settings>(
        _ settings: Settings,
        to store: Store<Settings>,
        undoManager undo: UndoManager?,
        comeForward: @escaping () -> Void,
        didChange: @escaping () -> Void
    ) {
        store.write(settings)
        didChange()
        guard let undo else { return }
        undo.registerUndo(withTarget: Options.shared) { [weak undo] _ in
            comeForward()
            Self.reset(store, undoManager: undo, comeForward: comeForward, didChange: didChange)
        }
        undo.setActionName(store.undoActionName)
    }
}
