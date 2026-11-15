//
//  ButtonRowChange.swift
//  Scrollio
//
//  One change of a row of a list of bindings that Edit › Undo takes back: the Buttons
//  pane's list, or an app's own buttons. It holds the bindings the change touched as they
//  are to be again, by id (none where there was no binding), and puts them into a list
//  without touching anything else in it: a binding added or removed meanwhile in another
//  row stays as it is. Applying it gives the states it replaced, which are the change the
//  other way round (Redo). Pure: the panes store the list and register the Undo.
//

import Foundation

struct ButtonRowChange: Equatable {

    /// What Edit › Undo calls the change.
    enum Kind: String, Equatable {
        /// Another action, or one where there was none ("Default" or "No Action" before).
        case action = "buttons-undo-change-action"
        /// Only the name or the icon of the same recorded key combination.
        case rename = "buttons-undo-rename"
        /// "Which Button Is This?": where a numbered button is on the mouse.
        case whichButton = "buttons-undo-which-button"
        /// A button of the mouse back to "Default" ("−", Delete, or "Default" in its menu).
        case clear = "buttons-undo-clear-action"

        /// "Change Action": the undo manager makes "Undo Change Action" of it.
        var actionName: String {
            return NSLocalizedString(rawValue, comment: "")
        }

        /// What changing `old` into `new` is called: a rename when the action is the same
        /// recorded key combination (or the same listed action) and only its name or icon
        /// changed.
        static func of(_ old: ButtonBinding, to new: ButtonBinding) -> Kind {
            let sameAction = old.isEnabled == new.isEnabled && old.systemShortcutName == new.systemShortcutName
                && old.openTarget == new.openTarget
            return sameAction && old.label != new.label ? .rename : .action
        }
    }

    /// A binding as the change is to leave it: `binding` nil where it is not to be in the
    /// list, `index` where it goes back in when it is not there.
    struct State: Equatable {
        let id: UUID
        let binding: ButtonBinding?
        let index: Int
    }

    let kind: Kind
    /// The touched bindings, the one whose row is shown afterwards first.
    let states: [State]

    /// `a` and `b` are the same binding stored the same way (`==` leaves out where a
    /// numbered button is said to be, which "Which Button Is This?" changes).
    static func isSame(_ a: ButtonBinding?, _ b: ButtonBinding?) -> Bool {
        return a == b && a?.triggerEvent.mousePart == b?.triggerEvent.mousePart
    }

    /// `bindings` with the change made, and the states it replaced (the change the other
    /// way round); nil when it changes nothing. A binding to put back whose trigger is in
    /// the list again meanwhile (`sameTrigger`) is not put back: that one stays. `place`
    /// gives a binding put back its place on the mouse as the list says now.
    func applied(
        to bindings: [ButtonBinding],
        sameTrigger: (ButtonBinding, ButtonBinding) -> Bool,
        place: (ButtonBinding) -> ButtonBinding = { $0 }
    ) -> (bindings: [ButtonBinding], replaced: [State])? {
        var list = bindings
        var replaced: [State] = []
        for state in states {
            let index = list.firstIndex { $0.id == state.id }
            switch (index, state.binding) {
            case (let index?, nil):
                replaced.append(State(id: state.id, binding: list[index], index: index))
                list.remove(at: index)
            case (let index?, let binding?):
                guard !Self.isSame(list[index], binding) else { continue }
                replaced.append(State(id: state.id, binding: list[index], index: index))
                list[index] = binding
            case (nil, let binding?):
                guard !list.contains(where: { sameTrigger($0, binding) }) else { continue }
                let at = min(max(0, state.index), list.count)
                list.insert(place(binding), at: at)
                replaced.append(State(id: state.id, binding: nil, index: at))
            case (nil, nil):
                continue
            }
        }
        return replaced.isEmpty ? nil : (list, replaced)
    }
}
