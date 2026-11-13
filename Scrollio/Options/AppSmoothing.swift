//
//  AppSmoothing.swift
//  Mos
//  Smooth scrolling in one app as the scroll engine decides it, and the one-click change of
//  it that the status-bar menu offers ("Smooth Scrolling in Safari").
//
//  The engine (ScrollCore with ScrollUtils.getTargetApplication) looks the app up on the
//  per-app list by its bundle's path, then by its program's path:
//  - on the list, "Use settings from Scrolling" on: the Scrolling settings, global switch
//    included;
//  - on the list with its own settings: those alone; the global "Smooth scrolling" does not
//    reach it (Application.isSmooth);
//  - not on the list: the Scrolling settings, or, while "Limit scrolling to these apps" is
//    on, the way macOS scrolls (no smoothing and no reversing).
//  Both axes always follow "Smooth scrolling" (ScrollSettingsCleanup), so that one switch says
//  whether the app is smoothed.
//
//  A click changes the list as the Apps pane does: an app not on it is added as "+" adds a
//  running app, "Use settings from Scrolling" is switched off with the same step
//  (`setUsesScrollingSettings`), and then only "Smooth scrolling" of the app's own settings
//  changes. What is stored, and how, stays as it is.
//

import Cocoa

enum AppSmoothing {

    /// An app as the menu sees it: the app in front.
    struct App: Equatable {
        /// As the menu names it ("Safari").
        let name: String
        let bundlePath: String?
        let executablePath: String?

        /// What is stored for it when it is added: the program's path, as "+" stores a running
        /// app (the bundle's when the program's is not known).
        var pathToStore: String? {
            return executablePath ?? bundlePath
        }
    }

    /// What the per-app list holds for an app.
    enum Rule: Equatable {
        case notListed
        /// On the list with "Use settings from Scrolling" on.
        case usesScrollingSettings
        /// On the list with its own settings; `smooth` is their "Smooth scrolling".
        case own(smooth: Bool)
    }

    /// What a click changes.
    enum Change: Equatable {
        /// Not on the list: added, with its own settings (a copy of the Scrolling settings) and
        /// smoothing off.
        case addWithSmoothingOff
        /// On the list with the Scrolling settings: its own settings (copied from Scrolling
        /// when never edited), smoothing off.
        case ownSettingsWithSmoothingOff
        /// Its own settings: "Smooth scrolling" on or off, nothing else.
        case setOwnSmoothing(Bool)
    }

    /// What the menu item says and does.
    struct Decision: Equatable {
        /// Smoothing is in effect for the app now: the checkmark.
        let isSmoothed: Bool
        /// What a click changes; nil: the item is disabled.
        let change: Change?
    }

    /// - Parameters:
    ///   - scrollingSmooth: "Smooth scrolling" of the Scrolling settings (the global switch).
    ///   - limitedToListedApps: "Limit scrolling to these apps".
    static func decide(rule: Rule, scrollingSmooth: Bool, limitedToListedApps: Bool) -> Decision {
        switch rule {
        case .notListed where limitedToListedApps:
            // Scrollio leaves the app alone. Adding it to the list would start reversing in
            // it too, which a smoothing switch must not do.
            return Decision(isSmoothed: false, change: nil)
        case .notListed:
            // Smoothing off globally: the item is not the place to make an exception.
            return Decision(isSmoothed: scrollingSmooth, change: scrollingSmooth ? .addWithSmoothingOff : nil)
        case .usesScrollingSettings:
            return Decision(isSmoothed: scrollingSmooth, change: scrollingSmooth ? .ownSettingsWithSmoothingOff : nil)
        case .own(let smooth):
            // Its own settings only, whatever the global switch says.
            return Decision(isSmoothed: smooth, change: .setOwnSmoothing(!smooth))
        }
    }

    /// The entry the engine uses for `app`: by the bundle's path, then by the program's.
    static func entry(for app: App, in list: EnhanceArray<Application>) -> Application? {
        return list.get(by: app.bundlePath) ?? list.get(by: app.executablePath)
    }

    static func rule(of entry: Application?) -> Rule {
        guard let entry else { return .notListed }
        return entry.inherit ? .usesScrollingSettings : .own(smooth: entry.scroll.smooth)
    }

    /// The decision for `app` with the settings as they are.
    static func decision(for app: App, list: OPTIONS_APPLICATION_DEFAULT, scrolling: OPTIONS_SCROLL_DEFAULT) -> Decision {
        return decide(
            rule: rule(of: entry(for: app, in: list.applications)),
            scrollingSmooth: scrolling.smooth,
            limitedToListedApps: list.allowlist
        )
    }

    /// A click on the item: decides again with the settings as they are and makes the change.
    /// Returns what was changed; nil when the item is disabled for them.
    @discardableResult
    static func toggle(_ app: App, list: OPTIONS_APPLICATION_DEFAULT, scrolling: OPTIONS_SCROLL_DEFAULT) -> Change? {
        guard let change = decision(for: app, list: list, scrolling: scrolling).change else { return nil }
        switch change {
        case .addWithSmoothingOff:
            guard let path = app.pathToStore else { return nil }
            addWithSmoothingOff(path: path, list: list, scrolling: scrolling)
        case .ownSettingsWithSmoothingOff:
            guard let entry = entry(for: app, in: list.applications) else { return nil }
            entry.setUsesScrollingSettings(false, scrolling: scrolling)
            entry.scroll.smooth = false
        case .setOwnSmoothing(let on):
            guard let entry = entry(for: app, in: list.applications) else { return nil }
            entry.scroll.smooth = on
        }
        return change
    }

    /// Adds the app stored as `path` with its own settings and smoothing off: the entry of
    /// an app that is left to macOS for its smoothing. The wheel's direction stays as the
    /// Scrolling settings have it.
    @discardableResult
    static func addWithSmoothingOff(path: String, list: OPTIONS_APPLICATION_DEFAULT, scrolling: OPTIONS_SCROLL_DEFAULT) -> Application {
        // A new entry uses the Scrolling settings and its own are those of a new entry,
        // as after "+"; then the same steps as for an app already on the list.
        let added = Application(path: path)
        added.setUsesScrollingSettings(false, scrolling: scrolling)
        added.scroll.smooth = false
        list.applications.append(added)
        return added
    }
}

// MARK: - Apps that 1.0.4 put on the list by itself

/// Version 1.0.4 put Calendar on the per-app list by itself, once, with smoothing off (its
/// month view takes a smoothed wheel badly). The owner's verdict the day after: an app does
/// not appear on a user's list unless the user puts it there. Nothing is added any more.
///
/// An entry that 1.0.4 made stays where it is: it cannot be told from one the user made,
/// and it is an ordinary entry he can change or remove. What is left here is the name of
/// the mark that version wrote on such a Mac, which a settings file still leaves out.
enum AppsLeftToMacOS {

    /// Written by 1.0.4 (an array of bundle ids). Nothing reads it.
    static let offeredKey = "appsLeftToMacOSOffered"
}
