//
//  PreferencesPaneReset.swift
//  Scrollio
//  "Reset to Defaults" for a pane whose settings are one stored value (the Shortcut Ring's
//  ring, the gesture settings): the button for the pane's footer, the reset with its Undo,
//  the few seconds in which the button reads "Undo Reset", and when it can be clicked.
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
    /// How long the button reads "Undo Reset" after a reset. Tests shorten it.
    var undoOfferDuration: TimeInterval = 8
    /// The button offers to take the reset back (it reads "Undo Reset").
    private(set) var offersUndo = false

    private let differsFromDefaults: () -> Bool
    private let resetSettings: (UndoManager?) -> Void
    private let undoActionName: String
    private let undoManager: () -> UndoManager?
    private var undoOfferWork: DispatchWorkItem?

    /// - Parameters:
    ///   - store: the pane's settings.
    ///   - undoManager: where a reset registers its Undo (nil: nowhere, and the button
    ///     offers none).
    ///   - didChange: the settings were replaced (by the reset, its Undo or its Redo): the
    ///     pane shows them, and tells this object with `settingsDidChange()`.
    init<Settings: Equatable>(
        store: Store<Settings>,
        undoManager: @escaping () -> UndoManager?,
        didChange: @escaping () -> Void
    ) {
        button = PreferencesGroupedForm.makePushButton(title: Self.resetTitle, target: nil, action: nil)
        differsFromDefaults = { store.read() != store.defaults }
        resetSettings = { Self.reset(store, undoManager: $0, didChange: didChange) }
        undoActionName = store.undoActionName
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
    /// takes the reset back instead.
    @objc func click(_ sender: Any?) {
        if offersUndo, !hasSettingsToReset {
            undoReset()
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
        let title = offersUndo ? Self.undoTitle : Self.resetTitle
        if button.title != title {
            button.title = title
            NSAccessibility.post(element: button as Any, notification: .titleChanged)
        }
        button.isEnabled = offersUndo || hasSettingsToReset
    }

    // MARK: - Reset, with Undo

    /// Puts the defaults in place of the stored settings; Undo gives back the ones that were
    /// there. The undo target is the settings, not a pane: Undo and Redo work whichever
    /// pane shows.
    private static func reset<Settings>(
        _ store: Store<Settings>,
        undoManager undo: UndoManager?,
        didChange: @escaping () -> Void
    ) {
        let previous = store.read()
        store.write(store.defaults)
        didChange()
        guard let undo else { return }
        undo.registerUndo(withTarget: Options.shared) { [weak undo] _ in
            Self.restore(previous, to: store, undoManager: undo, didChange: didChange)
        }
        undo.setActionName(store.undoActionName)
    }

    /// Undo of a reset: the settings from before it, every value as it was. Redo resets again.
    private static func restore<Settings>(
        _ settings: Settings,
        to store: Store<Settings>,
        undoManager undo: UndoManager?,
        didChange: @escaping () -> Void
    ) {
        store.write(settings)
        didChange()
        guard let undo else { return }
        undo.registerUndo(withTarget: Options.shared) { [weak undo] _ in
            Self.reset(store, undoManager: undo, didChange: didChange)
        }
        undo.setActionName(store.undoActionName)
    }
}
