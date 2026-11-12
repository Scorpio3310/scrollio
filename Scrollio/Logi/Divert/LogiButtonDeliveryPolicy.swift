//
//  LogiButtonDeliveryPolicy.swift
//  Mos
//

import Foundation

enum LogiButtonDeliveryPhase {
    case normal
    case recording
}

struct LogiButtonDeliveryPolicy {
    let standardMouseButtonsUseNativeEvents: Bool
    let standardButtonUndivertGuardEnabled: Bool
    let standardButtonUndivertGuardInterval: TimeInterval

    /// The shortest time between two rounds of the standard-button guard: each round sends
    /// requests to the mouse.
    static let minimumGuardInterval: TimeInterval = 0.5

    init(
        standardMouseButtonsUseNativeEvents: Bool,
        standardButtonUndivertGuardEnabled: Bool = false,
        standardButtonUndivertGuardInterval: TimeInterval = 2.0
    ) {
        self.standardMouseButtonsUseNativeEvents = standardMouseButtonsUseNativeEvents
        self.standardButtonUndivertGuardEnabled = standardButtonUndivertGuardEnabled
        self.standardButtonUndivertGuardInterval = max(standardButtonUndivertGuardInterval, Self.minimumGuardInterval)
    }

    /// What the app uses: over Bluetooth the middle, back and forward buttons arrive as
    /// ordinary mouse buttons (they are not diverted), and the guard that keeps re-reading
    /// them is off. These used to be read from three preference keys nothing documented
    /// (LogiBLEStandardButtonsNativeFirst, LogiBLEStandardUndivertGuardEnabled,
    /// LogiBLEStandardUndivertGuardInterval): a hidden value changed what was written to the
    /// mouse, and an interval of 0.001 made a write every millisecond. They are no longer read.
    static let `default` = LogiButtonDeliveryPolicy(standardMouseButtonsUseNativeEvents: true)

    /// The left and the right button (controls 0x0050 and 0x0051). They are never diverted,
    /// not for a binding and not while a button is recorded: a diverted click reaches no
    /// program but Scrollio, so one binding of it (recorded by the click that closes the
    /// recorder) would take the click away for good. On most mice they cannot be diverted
    /// anyway; a mouse that allows it must not be trusted with it.
    static let primaryClickCIDs: Set<UInt16> = [0x0050, 0x0051]

    /// The controls of `divertableCIDs` Scrollio may divert at all.
    static func divertCandidates(_ divertableCIDs: Set<UInt16>) -> Set<UInt16> {
        return divertableCIDs.subtracting(primaryClickCIDs)
    }

    func shouldUseHIDPPDelivery(
        transport: LogiTransportIdentity,
        cid: UInt16,
        phase: LogiButtonDeliveryPhase
    ) -> Bool {
        switch transport {
        case .receiver:
            return true
        case .unsupported:
            return false
        case .bleDirect:
            if standardMouseButtonsUseNativeEvents,
               LogiCIDDirectory.nativeMouseButton(forCID: cid) != nil {
                return false
            }
            return true
        }
    }
}
