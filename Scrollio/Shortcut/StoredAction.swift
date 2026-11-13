//
//  StoredAction.swift
//  Scrollio
//  Whether a stored action is one this version of Scrollio runs: asked when a settings
//  file is read (SettingsFile), so that an import takes only actions whose meaning this
//  version knows.
//
//  At launch an action with a name this version does not know is kept and does nothing
//  (it may be a newer version's, and the user may go back to that version). A file is
//  another matter: its name could be one a later version gives a meaning, and then a
//  press would run something that no sheet ever showed. On a Logitech button such a
//  binding would also take the button from the mouse and do nothing with it.
//
//  The answer is the executor's own (`ShortcutExecutor.resolveAction`, which only looks
//  the action up and starts nothing), minus what resolves and still runs nothing: an
//  action that was retired, and a Logitech action the Logitech code no longer has.
//

import Foundation

enum StoredAction {

    /// Whether a button or key with `binding` does something this version knows: one of
    /// the listed actions, a recorded shortcut, opening an app or a file or running a
    /// script, Gesture Navigation; or the binding is a row that has no action yet.
    static func isKnown(_ binding: ButtonBinding) -> Bool {
        let name = binding.systemShortcutName
        if name.isEmpty {
            return binding.openTarget == nil
        }
        // Gesture Navigation is no action of the executor's: the hold itself runs it.
        if name == SystemShortcut.mouseGestureNavigation.identifier {
            return true
        }
        // Nor is the Shortcut Ring: its trigger opens the ring.
        if name == SystemShortcut.shortcutRing.identifier {
            return true
        }
        var prepared = binding
        prepared.prepareCustomCache()
        return runs(ShortcutExecutor.shared.resolveAction(named: name, binding: prepared), named: name)
    }

    /// Whether a direction (or the click) of Gesture Navigation with this action does
    /// something this version knows. No action ("") is known.
    static func isKnown(gestureAction identifier: String) -> Bool {
        if identifier.isEmpty {
            return true
        }
        return runs(ShortcutExecutor.shared.resolveAction(named: identifier), named: identifier)
    }

    private static func runs(_ action: ResolvedAction?, named name: String) -> Bool {
        guard let action, !SystemShortcut.isRetired(name) else { return false }
        if case .logiAction(let identifier) = action {
            return LogiCenter.shared.runsAction(named: identifier)
        }
        return true
    }
}
