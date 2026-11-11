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
