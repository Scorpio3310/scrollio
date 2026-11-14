//
//  TriggerPicture.swift
//  Scrollio
//  What the picture beside the Gestures pane's desktops and the Shortcut Ring pane's ring
//  shows for the trigger that runs them: one rule for both panes, so the two never
//  disagree. Pure: the panes and their tests share it.
//
//  The picture shows one trigger, the first one the pane's row names (the one its "Change"
//  selects in Buttons); the row lists the rest. While only an app's own trigger does it,
//  that app's first one, with the app's icon on a chip. With none, the default picture:
//  nothing in the accent colour (the accent means "yours").
//
//  A mouse button is resolved against the drawing of the shown mouse by
//  `ButtonTriggerPicture.make`, as the Buttons pane's rows are: a part the drawing has
//  lights; a button the Mac knows only by its number, unplaced or placed on a part this
//  drawing lacks, shows its number on a badge; a known part the drawing lacks shows a badge
//  that says "a button of this mouse". A key shows as keycaps.
//

import Foundation

/// Which trigger the picture is of, before it is resolved against a drawing.
struct TriggerPictureSource: Equatable {
    /// The first trigger the row names; nil: nothing does it.
    var event: RecordedEvent?
    /// Set while only an app's own trigger does it: that app's stored path.
    var onlyInAppPath: String?

    init(event: RecordedEvent? = nil, onlyInAppPath: String? = nil) {
        self.event = event
        self.onlyInAppPath = onlyInAppPath
    }

    static let none = TriggerPictureSource()

    /// The first binding of `general` that does it (`rule.takes`, in the Buttons pane's
    /// order); with none, the first own trigger of the first app that does it
    /// (`ApplicationTriggers.trigger`) and that app's path; with neither, `.none`.
    static func make(
        rule: ApplicationTriggerRule, general: [ButtonBinding], onlyInApps: ApplicationTriggers?
    ) -> TriggerPictureSource {
        if let binding = general.first(where: rule.takes) {
            return TriggerPictureSource(event: binding.triggerEvent)
        }
        if let onlyInApps, let trigger = onlyInApps.trigger {
            return TriggerPictureSource(event: trigger, onlyInAppPath: onlyInApps.path)
        }
        return .none
    }
}

/// What the picture shows for a trigger on one drawing of the mouse.
struct TriggerPicture: Equatable {

    enum Hold: Equatable {
        /// The part lit, in the view it lights in (`MouseArtworkModel.viewpoint(lighting:)`).
        case part(ButtonsMousePart)
        /// A button the Mac knows only by its number (unplaced, or placed on a part this
        /// drawing lacks): an accent badge with the number.
        case number(Int)
        /// A button known to be a part this drawing lacks (the thumb panel on an MX Master
        /// 3, the gesture button on the plain mouse): an accent badge with the symbol
        /// `button.programmable`. nil: a Logitech control of no role the drawings know.
        case notDrawn(ButtonsMousePart?)
        /// A key: one cap per modifier, then the key (`ButtonTriggerNaming.capLabels`).
        case keys([String])
    }

    /// What is held; nil: the default picture (nothing does it).
    var hold: Hold?
    /// The modifier keys held with a mouse button, one cap each ("⌥" of "⌥ Back button").
    var modifiers: [String] = []
    /// The app the trigger belongs to while only its own trigger does it: the chip.
    var appPath: String?

    static let none = TriggerPicture(hold: nil)

    /// `source` on the drawing of `mouse`.
    /// - Parameter logitechRole: what a Logitech code is on the mouse.
    static func make(
        _ source: TriggerPictureSource,
        mouse: MouseArtworkModel,
        logitechRole: (UInt16) -> LogiControlRole? = { LogiCenter.shared.controlRole(forScrollioCode: $0) }
    ) -> TriggerPicture {
        guard let event = source.event else { return .none }
        let appPath = source.onlyInAppPath
        guard event.type == .mouse else {
            return TriggerPicture(hold: .keys(ButtonTriggerNaming.capLabels(for: event)), appPath: appPath)
        }
        let hold: Hold
        switch ButtonTriggerPicture.make(for: event, mouse: mouse, logitechRole: logitechRole) {
        case .mouse(let part?, _, _):
            hold = .part(part)
        case .mouse(nil, let number?, _):
            hold = .number(number)
        case .mouse(nil, nil, let notDrawn):
            hold = .notDrawn(notDrawn)
        case .key:
            // (Not reached: a mouse event is never a key.)
            hold = .keys(ButtonTriggerNaming.capLabels(for: event))
        }
        // The caps without the button: its name is the row's, the picture shows the button.
        let modifiers = Array(ButtonTriggerNaming.capLabels(for: event).dropLast())
        return TriggerPicture(hold: hold, modifiers: modifiers, appPath: appPath)
    }

    /// The part that lights: the `.part` case only.
    var litPart: ButtonsMousePart? {
        guard case .part(let part)? = hold else { return nil }
        return part
    }
}
