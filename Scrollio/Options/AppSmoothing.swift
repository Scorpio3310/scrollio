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

// MARK: - Apps left to macOS unless the user says otherwise

/// Apps that scroll badly when their wheel is smoothed get an entry on the per-app list by
/// themselves, once: an ordinary entry with its own settings and "Smooth scrolling" off,
/// the one "Smooth Scrolling in …" of the status-bar menu makes. The Apps pane lists it;
/// the user switches it back ("Use settings from Scrolling", or "Smooth scrolling" on its
/// page or in the menu) or removes it, and what he did stays (`offeredKey`).
enum AppsLeftToMacOS {

    /// Bundle ids. An app goes in here only after it was seen to need it.
    ///
    /// - Calendar `com.apple.iCal`: its month view aligns itself to weeks and handles a
    ///   smoothed stream badly: a small turn of the wheel barely moves it and a little
    ///   more runs away, with or without Trackpad-style scrolling (the owner, 2026-11-12;
    ///   also in 1.0.0).
    static let bundleIdentifiers = ["com.apple.iCal"]

    /// The stored list of the bundle ids that were offered on this Mac (an array of
    /// strings). An id on it is never offered again, so an entry the user removed does not
    /// come back; an id a later version adds to `bundleIdentifiers` is not on it and is
    /// offered then. It stays on this Mac (`SettingsFile.leftOut`).
    static let offeredKey = "appsLeftToMacOSOffered"

    /// Where an app is on this Mac.
    struct Location: Equatable {
        /// What the entry stores, as "Choose in Finder…" does.
        let bundlePath: String
        let executablePath: String?
    }

    /// Offers each built-in app that was not offered yet. Run at launch once the settings
    /// are read, and when the Welcome Guide is finished.
    /// - Not installed (`locate` gives nil): nothing; it is tried again at a later launch.
    /// - On the list already, under its bundle's or its program's path: the user's entry
    ///   stays as he made it, and the app counts as offered.
    /// - "Change scrolling only in these apps" is on: nothing, and it is tried again
    ///   later. The app is left to macOS as it is, and an entry would start reversing in
    ///   it (the menu's item is off there for the same reason, `AppSmoothing.decide`).
    /// - Otherwise it is added: the Scrolling settings as its own, smoothing off.
    ///
    /// While a new user has not finished the Welcome Guide nothing is offered: the guide
    /// sets the wheel's direction and the feel, and the entry's own settings are a copy of
    /// what Scrolling has when it is made.
    /// - Returns: the entries it added.
    @discardableResult
    static func offer(to options: Options, guideIsPending: Bool, locate: (String) -> Location?) -> [Application] {
        guard !guideIsPending, options.writesToDefaults else { return [] }
        let stored = options.defaults.stringArray(forKey: offeredKey) ?? []
        var offered = stored
        var added: [Application] = []
        for identifier in bundleIdentifiers where !offered.contains(identifier) {
            guard let location = locate(identifier) else { continue }
            let app = AppSmoothing.App(name: "", bundlePath: location.bundlePath, executablePath: location.executablePath)
            if AppSmoothing.entry(for: app, in: options.application.applications) == nil {
                guard !options.application.allowlist else { continue }
                added.append(AppSmoothing.addWithSmoothingOff(
                    path: location.bundlePath, list: options.application, scrolling: options.scroll
                ))
            }
            offered.append(identifier)
        }
        if offered != stored {
            options.defaults.set(offered, forKey: offeredKey)
        }
        return added
    }

    /// The offer with the app's own settings and the apps of this Mac. Nothing under XCTest.
    static func offerLive() {
        guard !AppRuntime.isRunningXCTest else { return }
        let added = offer(to: .shared, guideIsPending: WelcomeGuideProgress.live.isPending) { identifier in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else { return nil }
            return Location(bundlePath: url.path, executablePath: Bundle(url: url)?.executablePath)
        }
        if !added.isEmpty {
            AppSystemLog.note("Apps: \(added.count) app(s) that scroll badly when smoothed were added to the list with smoothing off")
        }
    }
}
