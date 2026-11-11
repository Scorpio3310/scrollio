//
//  ButtonsMousePart.swift
//  Mos
//  The parts of the mouse the Buttons pane's drawing can light up, and which part a
//  recorded trigger is. Pure: the pane and its tests share the mapping.
//

import Foundation

enum ButtonsMousePart: Int, CaseIterable {
    case left
    case right
    /// The wheel: pressing it is the middle button.
    case middle
    case back
    case forward
    /// The thumb panel of a Logitech MX Master: the gesture button of the MX Master 3 and
    /// 3S, the haptic sense panel of the MX Master 4.
    case gesture
    /// The small button behind the wheel.
    case modeShift

    /// The part a trigger presses, nil for a key or a button the drawing does not show.
    /// Modifiers do not matter: "⌥ Back button" is the Back button.
    /// - Parameter logitechRole: what a Logitech code is on the mouse
    ///   (`LogiCenter.controlRole(forMosCode:)`).
    static func part(
        for event: RecordedEvent,
        logitechRole: (UInt16) -> LogiControlRole? = { LogiCenter.shared.controlRole(forMosCode: $0) }
    ) -> ButtonsMousePart? {
        guard event.type == .mouse else { return nil }
        switch event.code {
        case 0: return .left
        case 1: return .right
        case 2: return .middle
        case 3: return .back
        case 4: return .forward
        default:
            guard let role = logitechRole(event.code) else { return nil }
            switch role {
            case .gesture, .thumbPanel: return .gesture
            case .modeShift: return .modeShift
            case .middle: return .middle
            case .back: return .back
            case .forward: return .forward
            }
        }
    }
}

/// What a row's small picture shows, and what the card adds for a button it cannot light.
/// Pure: the pane and its tests share it.
///
/// Only a button whose place is certain lights a part: the five standard buttons and the
/// Logitech controls `LogiCenter` knows the role of. A button the Mac reports only by its
/// number ("Button 5") could be any extra button of any mouse (the MX Master 4's gesture
/// button or thumb panel, or another mouse's side button), so it lights nothing and shows
/// its number instead.
enum ButtonTriggerPicture: Equatable {
    /// A key of the keyboard.
    case key
    /// The mouse with `part` lit; `part` nil: a button the drawing cannot show, with
    /// `number` when the Mac knows it only by its number.
    case mouse(part: ButtonsMousePart?, number: Int?)

    static func make(
        for event: RecordedEvent,
        logitechRole: (UInt16) -> LogiControlRole? = { LogiCenter.shared.controlRole(forMosCode: $0) }
    ) -> ButtonTriggerPicture {
        guard event.type == .mouse else { return .key }
        return .mouse(part: ButtonsMousePart.part(for: event, logitechRole: logitechRole), number: number(for: event))
    }

    /// The number of a button the Mac knows only by its number, as its row title says it
    /// ("Button 5"); nil for the five standard buttons, Logitech controls and keys.
    static func number(for event: RecordedEvent) -> Int? {
        guard event.type == .mouse, event.code > 4, !LogiCenter.shared.isLogiCode(event.code) else { return nil }
        return Int(event.code)
    }

    /// The lit part, nil for a key or a button the drawing cannot show.
    var part: ButtonsMousePart? {
        guard case .mouse(let part, _) = self else { return nil }
        return part
    }

    var number: Int? {
        guard case .mouse(_, let number) = self else { return nil }
        return number
    }

    /// A mouse button the drawing cannot show: where it is, only the mouse can tell
    /// ("+", then press it).
    var isUnplaced: Bool {
        guard case .mouse(let part, _) = self else { return false }
        return part == nil
    }
}
