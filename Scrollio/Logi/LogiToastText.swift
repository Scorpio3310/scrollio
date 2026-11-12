//
//  LogiToastText.swift
//  Scrollio
//
//  The texts of the toasts the Logitech code shows. A button is called what the Buttons pane
//  calls it ("Back button", "Mode shift button"): the name comes from outside Scrollio/Logi
//  through LogiExternalBridge.logiButtonName. A control without a name is "a button", never
//  "Unknown(0x00D7)". A feature a mouse lacks is named in the words of the panes.
//

import Foundation

enum LogiToastText {

    /// What a mouse can lack when a button action asks for it.
    enum MissingFeature: Equatable {
        case pointerSpeed
        case haptics
        case wheelForce
        case pressForce

        var catalogKey: String {
            switch self {
            case .pointerSpeed: return "logi-feature-pointer-speed"
            case .haptics: return "logi-feature-haptics"
            case .wheelForce: return "logi-feature-wheel-force"
            case .pressForce: return "logi-feature-press-force"
            }
        }
    }

    /// The pane's name for a control, or nil when it has none worth showing: the control is
    /// not in the directory (its "name" would be "Unknown(0x00D7)") and has no role.
    static func buttonName(forCID cid: UInt16, paneName: (UInt16) -> String?) -> String? {
        guard LogiControlRole(cid: cid) != nil || LogiCIDDirectory.hasName(forCID: cid) else { return nil }
        guard let name = paneName(LogiCIDDirectory.toScrollioCode(cid)), !name.isEmpty else { return nil }
        return name
    }

    /// `format` with the button's name, or with "a button" ("A button" where the name starts
    /// the sentence) when it has none.
    static func buttonToast(
        formatKey: String,
        buttonName: String?,
        localized: (String) -> String = { NSLocalizedString($0, comment: "") }
    ) -> String {
        let format = localized(formatKey)
        let startsSentence = format.hasPrefix("%@")
        let name = buttonName ?? localized(startsSentence ? "logi-toast-a-button-start" : "logi-toast-a-button")
        return String(format: format, name)
    }

    /// "<mouse> does not support <feature>."
    static func featureNotAvailable(
        mouse: String,
        feature: MissingFeature,
        localized: (String) -> String = { NSLocalizedString($0, comment: "") }
    ) -> String {
        return String(format: localized("featureNotAvailable"), mouse, localized(feature.catalogKey))
    }
}
