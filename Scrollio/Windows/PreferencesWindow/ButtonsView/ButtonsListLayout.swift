//
//  ButtonsListLayout.swift
//  Mos
//  Which rows the Buttons pane shows, top to bottom. With a mouse that has a drawing of its
//  own connected (an MX Master, an MX Anywhere 3, the MX Vertical): one row per button of
//  that mouse, in the order they sit on it, each with the binding of that button without
//  modifiers, or none ("Default"), and on an MX Master the thumb wheel's row after the mode
//  shift button; then every other binding, as stored, under "Other buttons and keys". With
//  any other mouse: the bindings as stored, as before. Also the trigger a "Default" row
//  stores once it gets an action, and what it says until then. Pure: the pane and its tests
//  share it, and nothing is stored by it.
//
//  The thumb wheel's row is a row of its own kind: it is no button and has no binding. It
//  shows what the sideways wheel does (Options.shared.thumbWheel, as under Scrolling), and
//  the bindings are laid out exactly as without it.
//

import Foundation

extension ButtonsMousePart {

    /// The buttons of `mouse` that get a row of their own, in the order they sit on it: the
    /// wheel and the button behind it, the side buttons front to back, then the thumb rest.
    /// On the MX Vertical the button on its top comes right after the wheel: what the
    /// fingers work first (the view from above), then what the thumb works. Left and right
    /// clicks are not listed; a mouse without a drawing of its own has none.
    static func listed(on mouse: MouseArtworkModel) -> [ButtonsMousePart] {
        let order: [ButtonsMousePart]
        switch mouse {
        case .mxMaster4: order = [.middle, .modeShift, .gesture, .forward, .back, .thumbPanel]
        case .mxMaster3: order = [.middle, .modeShift, .forward, .back, .gesture]
        case .mxAnywhere3: order = [.middle, .modeShift, .forward, .back]
        case .mxVertical: order = [.middle, .pointerSpeed, .forward, .back]
        case .generic: order = []
        }
        return order.filter { mouse.has($0.artworkPart) }
    }

    /// The role of the Logitech control that is this part; nil for left and right.
    var logitechRole: LogiControlRole? {
        switch self {
        case .left, .right: return nil
        case .middle: return .middle
        case .back: return .back
        case .forward: return .forward
        case .gesture: return .gesture
        case .modeShift: return .modeShift
        case .thumbPanel: return .thumbPanel
        case .pointerSpeed: return .pointerSpeed
        }
    }

    /// What "+" records when this part of the connected Logitech mouse is pressed, without
    /// modifiers (`normalizedTrigger`): the standard middle, back or forward button where
    /// the mouse sends it as one (over Bluetooth Scrollio leaves those buttons native; a
    /// control no Logitech session reports is not diverted at all), otherwise the Logitech
    /// control, which reaches Scrollio only diverted (over a receiver every control is
    /// diverted while "+" records; the gesture button, the mode shift button and the thumb
    /// panel always). Left and right: the left and right buttons. Reads, never writes to a
    /// mouse.
    func recordedTrigger(
        logitechCode: (LogiControlRole) -> UInt16 = { LogiCenter.shared.scrollioCode(for: $0) },
        diagnosis: (UInt16) -> LogiButtonCaptureDiagnosis = { LogiCenter.shared.buttonCaptureDiagnosis(forScrollioCode: $0) }
    ) -> RecordedEvent {
        guard let role = logitechRole else {
            return RecordedEvent(type: .mouse, code: self == .left ? 0 : 1, modifiers: 0, deviceFilter: nil)
        }
        let code = logitechCode(role)
        let found = diagnosis(code)
        if let native = found.nativeMouseButton, found.ownershipKey == nil || found.usesNativeEvents {
            return RecordedEvent(type: .mouse, code: native, modifiers: 0, deviceFilter: nil)
        }
        return RecordedEvent(type: .mouse, code: code, modifiers: 0, deviceFilter: nil)
    }

    /// What the button does while it has no action, where that is certain: the standard
    /// buttons reach the app as they are, and the mode shift button switches the wheel by
    /// itself. Anything else: no claim.
    var defaultExplanationKey: String {
        switch self {
        case .back: return "buttons-default-back"
        case .forward: return "buttons-default-forward"
        case .middle: return "buttons-default-middle"
        case .modeShift: return "buttons-default-mode-shift"
        // The MX Vertical's top button: what it does by itself is known from Logitech's
        // description only, so no more is claimed than for the others.
        case .left, .right, .gesture, .thumbPanel, .pointerSpeed: return "buttons-default-own"
        }
    }
}

/// The rows of the Buttons pane (see the file header). Pure.
struct ButtonsListLayout: Equatable {

    /// A button of the shown mouse.
    struct PartRow: Equatable {
        let part: ButtonsMousePart
        /// The stored binding of the button without modifiers; nil: none ("Default").
        let binding: ButtonBinding?
    }

    /// One row of the list.
    enum Row: Equatable {
        /// A button of the shown mouse.
        case part(PartRow)
        /// The thumb wheel of the shown mouse: what it does, not a binding.
        case thumbWheel
        /// Any other binding, under "Other buttons and keys".
        case other(ButtonBinding)
    }

    /// The id of the thumb wheel's row in the list. A part of the drawing, so it is never
    /// the id of another row (a button of the mouse, or a binding's id).
    static let thumbWheelRowID = AnyHashable(MouseArtworkPart.thumbWheel)

    /// The buttons of the shown mouse, in the order they sit on it; none for a mouse
    /// without a drawing of its own.
    let partRows: [PartRow]
    /// The shown mouse has a thumb wheel: it gets a row after the mode shift button.
    let hasThumbWheel: Bool
    /// Every other binding, in the stored order: with modifiers, keys, numbered buttons not
    /// placed on a part, controls the shown mouse does not have, and a second binding of a
    /// button that has its row.
    let others: [ButtonBinding]

    init(partRows: [PartRow], hasThumbWheel: Bool = false, others: [ButtonBinding]) {
        self.partRows = partRows
        self.hasThumbWheel = hasThumbWheel
        self.others = others
    }

    /// - Parameters:
    ///   - bindings: as stored.
    ///   - mouse: the drawing of the shown mouse.
    ///   - logitechRole: what a Logitech code is on the mouse.
    static func make(
        bindings: [ButtonBinding],
        mouse: MouseArtworkModel,
        logitechRole: (UInt16) -> LogiControlRole? = { LogiCenter.shared.controlRole(forScrollioCode: $0) }
    ) -> ButtonsListLayout {
        var taken = Set<UUID>()
        let partRows = ButtonsMousePart.listed(on: mouse).map { part -> PartRow in
            let candidates = bindings.filter {
                !taken.contains($0.id) && plainPart(of: $0.triggerEvent, logitechRole: logitechRole) == part
            }
            // Two bindings of one button (the standard Back button and the Logitech one):
            // the one with an action is the row, the other stays below.
            let chosen = candidates.first { CellActionState(binding: $0).hasBoundAction } ?? candidates.first
            if let chosen {
                taken.insert(chosen.id)
            }
            return PartRow(part: part, binding: chosen)
        }
        return ButtonsListLayout(
            partRows: partRows,
            hasThumbWheel: showsThumbWheel(on: mouse),
            others: bindings.filter { !taken.contains($0.id) }
        )
    }

    /// The thumb wheel has a row on a mouse whose drawing has one (the MX Master 4, 3 and
    /// 3S). Any other mouse's sideways wheel is set up under Scrolling only.
    static func showsThumbWheel(on mouse: MouseArtworkModel) -> Bool {
        return mouse.has(.thumbWheel) && !ButtonsMousePart.listed(on: mouse).isEmpty
    }

    /// Every row, top to bottom: the buttons of the mouse with the thumb wheel right after
    /// the mode shift button (after the last button if the mouse had none), then the other
    /// bindings.
    var rows: [Row] {
        var result = partRows.map(Row.part)
        if hasThumbWheel {
            let after = partRows.firstIndex { $0.part == .modeShift }.map { $0 + 1 } ?? partRows.count
            result.insert(.thumbWheel, at: after)
        }
        return result + others.map(Row.other)
    }

    /// The part `event` presses when it has no modifiers; nil for a key, a trigger with
    /// modifiers ("⌥ Back button") and a button the drawing does not show.
    static func plainPart(
        of event: RecordedEvent,
        logitechRole: (UInt16) -> LogiControlRole? = { LogiCenter.shared.controlRole(forScrollioCode: $0) }
    ) -> ButtonsMousePart? {
        guard event.type == .mouse,
              UInt64(event.modifiers) & ButtonBinding.customBindingRelevantModifierMask == 0
        else { return nil }
        return ButtonsMousePart.part(for: event, logitechRole: logitechRole)
    }

    /// The parts that have a row.
    var parts: [ButtonsMousePart] {
        return partRows.map(\.part)
    }

    /// The row of `part`, nil when it has none.
    func row(of part: ButtonsMousePart) -> PartRow? {
        return partRows.first { $0.part == part }
    }

    /// The part whose row `event` (without modifiers) is; nil when it has none.
    func part(for event: RecordedEvent, logitechRole: (UInt16) -> LogiControlRole? = { LogiCenter.shared.controlRole(forScrollioCode: $0) }) -> ButtonsMousePart? {
        guard let part = Self.plainPart(of: event, logitechRole: logitechRole), parts.contains(part) else { return nil }
        return part
    }

    /// Scrollio catches `part`'s Logitech control for another binding (one with modifiers
    /// that has an action): the mouse then sends it only to Scrollio, so without an action
    /// of its own the plain press does not do what the button does by itself.
    static func catchesControl(
        of part: ButtonsMousePart,
        in bindings: [ButtonBinding],
        isLogitechCode: (UInt16) -> Bool = { LogiCenter.shared.isLogiCode($0) },
        logitechRole: (UInt16) -> LogiControlRole? = { LogiCenter.shared.controlRole(forScrollioCode: $0) }
    ) -> Bool {
        return bindings.contains { binding in
            let trigger = binding.triggerEvent
            return binding.isEnabled && trigger.type == .mouse && isLogitechCode(trigger.code)
                && ButtonsMousePart.part(for: trigger, logitechRole: logitechRole) == part
        }
    }
}
