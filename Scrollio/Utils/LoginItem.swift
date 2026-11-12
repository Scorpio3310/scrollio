//
//  LoginItem.swift
//  Mos
//
//  "Launch at login" through ServiceManagement: SMAppService.mainApp registers the app
//  itself as a login item, by its identity instead of its path, and lists it in
//  System Settings > General > Login Items.
//
//  The system side sits behind `LoginItemService`, so the rules below are tested with a
//  fake. Under XCTest the default service is inert: tests never register anything and
//  never read the real state.
//
//  Not covered: a login item that an older build (or the original Mos) added by path with
//  LSSharedFileList. SMAppService neither sees nor removes those; they are removed by hand
//  in System Settings.
//

import Foundation
import ServiceManagement

/// What the system says about the app's own login item.
enum LoginItemStatus: Equatable {
    /// Registered and allowed: the app starts at login.
    case enabled
    /// Registered, but switched off in System Settings (or waiting for approval there).
    case requiresApproval
    /// Not registered.
    case notRegistered
}

protocol LoginItemService {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
    /// Shows System Settings > General > Login Items.
    func openSystemSettings()
}

/// The real thing.
struct MainAppLoginItemService: LoginItemService {
    var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered, .notFound:
            return .notRegistered
        @unknown default:
            return .notRegistered
        }
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// Used while XCTest runs: nothing is registered, nothing is read, nothing opens.
struct InertLoginItemService: LoginItemService {
    var status: LoginItemStatus { return .notRegistered }
    func register() throws {}
    func unregister() throws {}
    func openSystemSettings() {}
}

enum LoginItem {

    /// The service for this process: inert under XCTest, the system one otherwise.
    static var defaultService: LoginItemService {
        return AppRuntime.isRunningXCTest ? InertLoginItemService() : MainAppLoginItemService()
    }

    /// Replaced in tests.
    static var service: LoginItemService = defaultService

    /// The app starts at login. False while the item waits for approval in System Settings.
    static var isEnabled: Bool {
        return service.status == .enabled
    }

    /// Turns "launch at login" on or off. Does nothing when the system already is in the
    /// wanted state, so it is safe to call with the value that was just read.
    ///
    /// - Turning on registers the app. When the item needs approval (the user switched it
    ///   off in System Settings), registering cannot enable it; System Settings opens on the
    ///   Login Items page instead, where it can be switched on.
    /// - Turning off unregisters an enabled item. An item that is merely waiting for approval
    ///   is left alone: it does not launch anything, and this path also runs when the
    ///   options are read at launch, which must not change the system.
    /// - Returns: true when the system is in the wanted state afterwards.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        let status = service.status
        guard enabled else {
            guard status == .enabled else { return true }
            do {
                try service.unregister()
            } catch {
                AppSystemLog.problem("Open at login: macOS refused to remove the login item (\(logText(of: error)))")
            }
            return service.status != .enabled
        }

        guard status != .enabled else { return true }
        do {
            try service.register()
        } catch {
            AppSystemLog.problem("Open at login: macOS refused to add the login item (\(logText(of: error)))")
        }
        let result = service.status
        if result == .requiresApproval {
            service.openSystemSettings()
        }
        return result == .enabled
    }

    /// Unregisters the app whatever the system says, also an item that waits for approval.
    /// Only for an explicit choice of the user (unchecking the box): the launch path uses
    /// `setEnabled(false)`, which must leave such an item alone.
    /// - Returns: true when nothing is registered afterwards.
    @discardableResult
    static func removeRegistration() -> Bool {
        guard service.status != .notRegistered else { return true }
        do {
            try service.unregister()
        } catch {
            AppSystemLog.problem("Open at login: macOS refused to remove the login item (\(logText(of: error)))")
        }
        return service.status == .notRegistered
    }

    /// An error for the log: where it comes from and its number, not its text (which may
    /// carry the app's path).
    private static func logText(of error: Error) -> String {
        let error = error as NSError
        return "\(error.domain) \(error.code)"
    }
}
