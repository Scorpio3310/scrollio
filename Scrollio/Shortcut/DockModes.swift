//
//  DockModes.swift
//  Scrollio
//
//  Mission Control and Show Desktop, asked of the Dock itself instead of pressed as keys.
//
//  Both used to be sent as a key press (the Mission Control key, F11), down and up in the
//  same moment. The Dock watches those keys for more than a press (hold to peek, a second
//  key to switch), and such presses put it out of step: after a Show Desktop from Scrollio
//  had been ended by another key from Scrollio, every Mission Control or Show Desktop key
//  made the Dock enter the other of the two modes and leave it 0 to 2 ms later, until a
//  real gesture or key set it right. Seen on macOS 27.2 on 2026-11-13 in the Dock's own
//  log ("Toggle Expose Mode", "Changing from mode"), from the Shortcut Ring; the same keys
//  are sent for a button and for a gesture.
//
//  `CoreDockSendNotification` (ApplicationServices) tells the Dock to toggle a mode by its
//  name, with no key and no hold in between; it is the call Hammerspoon's
//  `hs.spaces.toggleMissionControl` and `toggleShowDesktop` make. It is in no public
//  header, so it is looked up by name; where it is missing the key press is sent as before.
//

import Foundation

/// A mode of the Dock that a listed action toggles.
enum DockMode: String, CaseIterable {
    case missionControl = "com.apple.expose.awake"
    case showDesktop = "com.apple.showdesktop.awake"

    /// The mode a listed action means; nil for every other action (Apps, the Spaces
    /// actions and so on are still sent as their keys).
    init?(shortcutIdentifier: String) {
        switch shortcutIdentifier {
        case SystemShortcut.missionControl.identifier: self = .missionControl
        case SystemShortcut.showDesktop.identifier: self = .showDesktop
        default: return nil
        }
    }
}

struct DockModeSender {

    /// Finds a symbol by name; nil when this macOS does not have it.
    typealias Resolver = (String) -> UnsafeMutableRawPointer?

    static let library = "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices"
    static let symbol = "CoreDockSendNotification"

    /// `void CoreDockSendNotification(CFStringRef notification, int unknown)`
    private typealias Function = @convention(c) (CFString, Int32) -> Void
    private let function: Function

    /// The Dock's call on this Mac, looked up once; nil when it is not there.
    static let system: DockModeSender? = load()

    static func systemResolver(_ name: String) -> UnsafeMutableRawPointer? {
        guard let handle = dlopen(library, RTLD_LAZY) else { return nil }
        return dlsym(handle, name)
    }

    static func load(resolver: Resolver = DockModeSender.systemResolver) -> DockModeSender? {
        guard let address = resolver(symbol) else { return nil }
        return DockModeSender(function: unsafeBitCast(address, to: Function.self))
    }

    /// Toggles the mode: shows it, or leaves it when it is showing.
    func toggle(_ mode: DockMode) {
        function(mode.rawValue as CFString, 0)
    }
}
