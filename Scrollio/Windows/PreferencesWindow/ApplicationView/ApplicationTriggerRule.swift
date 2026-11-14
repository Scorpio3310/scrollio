//
//  ApplicationTriggerRule.swift
//  Scrollio
//
//  One rule for what opens the Shortcut Ring and what runs Gesture Navigation, counted as
//  a press goes by the bindings: while an app on the list is in front, the Buttons pane's
//  bindings with the app's own in them (`ApplicationButtons.merged`); in every other app,
//  the Buttons pane's alone. The Shortcut Ring and Gestures panes
//  (`ShortcutRingBindingSummary`, `MouseGestureBindingSummary`) and an app's Ring and
//  Gestures parts all count by it, so none of them says that nothing opens the ring (or
//  runs the gestures) while an app's own button does.
//

import Foundation

enum ApplicationTriggerRule {
    /// Opens the Shortcut Ring: an enabled binding with that action whose trigger can run
    /// at all, a mouse button or a key.
    case shortcutRing
    /// Runs Gesture Navigation: an enabled binding of a mouse button with that action (a
    /// key never starts a gesture).
    case gestureNavigation

    /// Whether a press of `binding` does it, as InputProcessor runs it.
    func takes(_ binding: ButtonBinding) -> Bool {
        guard binding.isEnabled else { return false }
        switch self {
        case .shortcutRing:
            return binding.systemShortcutName == SystemShortcut.shortcutRing.identifier
                && ButtonUtils.isRunnable(binding.triggerEvent)
        case .gestureNavigation:
            return binding.triggerEvent.type == .mouse
                && binding.systemShortcutName == SystemShortcut.mouseGestureNavigation.identifier
        }
    }

    /// The bindings that do it while an app whose own bindings are `own` is in front, in
    /// the order a press goes by them; with none of its own (every app not on the list),
    /// those of `general` alone.
    func bindings(general: [ButtonBinding], own: [ButtonBinding] = []) -> [ButtonBinding] {
        return ApplicationButtons.merged(general: general, own: own).filter(takes)
    }

    /// The apps on the list, in its order, in front of which their own bindings do it,
    /// with those bindings; only while nothing of `general` does it (else it is done in
    /// every app that does not take it away). Empty: nowhere.
    func onlyInApps(general: [ButtonBinding], applications: [Application]) -> [(application: Application, bindings: [ButtonBinding])] {
        guard bindings(general: general).isEmpty else { return [] }
        return applications.compactMap { application in
            let own = application.ownButtonBindings
            guard !own.isEmpty else { return nil }
            let here = bindings(general: general, own: own)
            return here.isEmpty ? nil : (application, here)
        }
    }

    /// The apps on the list, in their stored order.
    static var storedApplications: [Application] {
        let stored = Options.shared.application.applications
        return (0..<stored.count).compactMap { stored.get(by: $0) }
    }
}

/// While nothing of the Buttons pane opens the ring (or runs the gestures) but an app's own
/// button or key does: what the pane says ("Only in Figma: Thumb panel") and where its
/// "Change" leads (the first such app's Buttons part, that binding's row selected).
struct ApplicationTriggers: Equatable {
    /// The apps, by name, in the order of the list.
    var applicationNames: [String]
    /// What does it there, named as the Buttons pane names it, each once.
    var triggerTitles: [String]
    /// The first app's stored path and its own binding that does it.
    var path: String
    var bindingID: UUID?

    init(applicationNames: [String], triggerTitles: [String], path: String = "", bindingID: UUID? = nil) {
        self.applicationNames = applicationNames
        self.triggerTitles = triggerTitles
        self.path = path
        self.bindingID = bindingID
    }

    /// - Parameter titles: what the Buttons pane calls the triggers, in order.
    init?(
        _ entries: [(application: Application, bindings: [ButtonBinding])],
        titles: ([RecordedEvent]) -> [String]
    ) {
        guard let first = entries.first else { return nil }
        var names: [String] = []
        for entry in entries {
            for title in titles(entry.bindings.map(\.triggerEvent)) where !names.contains(title) {
                names.append(title)
            }
        }
        self.init(
            applicationNames: entries.map { $0.application.getName() },
            triggerTitles: names,
            path: first.application.path,
            // (Nothing of Buttons does it: every binding that does it there is the app's own.)
            bindingID: first.bindings.first?.id
        )
    }

    /// "Only in Figma: Thumb panel" / "Only in Figma and Safari: Thumb panel and Back
    /// button", without a full stop (the panes' lines go on).
    var text: String {
        return String(
            format: NSLocalizedString("apps-trigger-only-in", comment: ""),
            ListFormatter.localizedString(byJoining: applicationNames),
            ListFormatter.localizedString(byJoining: triggerTitles)
        )
    }
}
