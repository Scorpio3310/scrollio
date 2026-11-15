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

    /// The rule a press of `binding` follows; nil for one that does neither.
    init?(of binding: ButtonBinding) {
        if Self.shortcutRing.takes(binding) {
            self = .shortcutRing
        } else if Self.gestureNavigation.takes(binding) {
            self = .gestureNavigation
        } else {
            return nil
        }
    }

    /// Whether, with `application` in front, what opens is the general ring (or what runs
    /// is the general gestures), not the app's own.
    func usesGeneralSettings(_ application: Application) -> Bool {
        switch self {
        case .shortcutRing:
            return application.usesGeneralRing
        case .gestureNavigation:
            return application.usesGeneralGestures
        }
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
    /// The same, app by app (in the order of `applicationNames`); empty when not known.
    var appTriggerTitles: [[String]]
    /// The first app's stored path and its own binding that does it.
    var path: String
    var bindingID: UUID?
    /// That binding's trigger: what the panes' pictures show (`TriggerPictureSource`).
    var trigger: RecordedEvent?
    /// Set while every one of these apps opens its own ring (or runs its own gestures):
    /// then nothing uses the general settings, and the panes fold them as when nothing
    /// opens the ring. nil while one of them uses the general ones.
    var ownOnly: ApplicationTriggerRule?

    /// Whether one of these apps uses the general ring (or gestures).
    var usesGeneralSettings: Bool {
        return ownOnly == nil
    }

    init(
        applicationNames: [String], triggerTitles: [String], path: String = "", bindingID: UUID? = nil,
        trigger: RecordedEvent? = nil, ownOnly: ApplicationTriggerRule? = nil, appTriggerTitles: [[String]] = []
    ) {
        self.applicationNames = applicationNames
        self.triggerTitles = triggerTitles
        self.appTriggerTitles = appTriggerTitles
        self.path = path
        self.bindingID = bindingID
        self.trigger = trigger
        self.ownOnly = ownOnly
    }

    /// - Parameter titles: what the Buttons pane calls the triggers, in order.
    init?(
        _ entries: [(application: Application, bindings: [ButtonBinding])],
        titles: ([RecordedEvent]) -> [String]
    ) {
        guard let first = entries.first else { return nil }
        var names: [String] = []
        var appNames: [[String]] = []
        for entry in entries {
            var own: [String] = []
            for title in titles(entry.bindings.map(\.triggerEvent)) where !own.contains(title) {
                own.append(title)
            }
            appNames.append(own)
            for title in own where !names.contains(title) {
                names.append(title)
            }
        }
        // (The bindings tell which rule they follow: they all follow the one that listed them.)
        let rule = first.bindings.first.flatMap(ApplicationTriggerRule.init(of:))
        let ownOnly = rule.flatMap { rule in
            entries.allSatisfy { !rule.usesGeneralSettings($0.application) } ? rule : nil
        }
        self.init(
            applicationNames: entries.map { $0.application.getName() },
            triggerTitles: names,
            path: first.application.path,
            // (Nothing of Buttons does it: every binding that does it there is the app's own.)
            bindingID: first.bindings.first?.id,
            trigger: first.bindings.first?.triggerEvent,
            ownOnly: ownOnly,
            appTriggerTitles: appNames
        )
    }

    /// "Only in Figma: Thumb panel" / "Only in Figma and Safari: Thumb panel and Back
    /// button", without a full stop (the panes' lines go on); while the apps do it with
    /// different buttons or keys, each with its own: "Only in Figma (Thumb panel) and
    /// Safari (Back button)". While every one of the apps uses its own ring (or gestures),
    /// it says so: "Only in Figma, with its own ring: Thumb panel".
    var text: String {
        if appTriggerTitles.count > 1, Set(appTriggerTitles.map { $0.sorted() }).count > 1 {
            let pairs = zip(applicationNames, appTriggerTitles).map { name, titles in
                String(
                    format: NSLocalizedString("apps-trigger-app-with", comment: ""),
                    name, InterfaceList.joined(titles)
                )
            }
            return String(
                format: NSLocalizedString("apps-trigger-only-in-each", comment: ""),
                whereText(InterfaceList.joined(pairs))
            )
        }
        return String(
            format: NSLocalizedString("apps-trigger-only-in", comment: ""),
            whereText(InterfaceList.joined(applicationNames)),
            InterfaceList.joined(triggerTitles)
        )
    }

    /// `names` (the apps, joined as a list), and with what of their own while `ownOnly`.
    private func whereText(_ names: String) -> String {
        guard let ownOnly else { return names }
        let one = applicationNames.count == 1
        let key: String
        switch ownOnly {
        case .shortcutRing:
            key = one ? "apps-trigger-own-ring" : "apps-trigger-own-rings"
        case .gestureNavigation:
            key = one ? "apps-trigger-own-gestures" : "apps-trigger-own-gestures-each"
        }
        return String(format: NSLocalizedString(key, comment: ""), names)
    }
}

/// The first row of an app's Gestures and Shortcut Ring parts ("Button to hold", "Button or
/// key"): what does it while the app is in front, by the rule above, and where the row's
/// button leads. "Gesture button, as everywhere" (Buttons' button: "Show in Buttons", the
/// Buttons pane with its row selected); "Back button, only in Figma" (a button of the app's
/// own: "Show in Figma", the app's Buttons part with that row selected); "None in Figma"
/// ("Set Up…", which records a button for this app only; or "Show in Figma" when one of the
/// app's own rows took what does it everywhere else, that row selected).
struct ApplicationTriggerRow: Equatable {

    /// Where the row's button leads.
    enum Destination: Equatable {
        /// The Buttons pane, the row of what does it everywhere selected.
        case buttonsPane
        /// The app's Buttons part, this row of the app's own selected.
        case applicationButtons(UUID)
        /// A recording of a button (or key) that does it only while the app is in front.
        case setUp
    }

    /// The row's line.
    let text: String
    let destination: Destination
    /// With `.buttonsPane`: the binding of Buttons the line names first, whose row "Show in
    /// Buttons" selects (an app may have replaced an earlier one that does it too).
    var buttonsBindingID: UUID? = nil

    /// The button's title, which says where it goes, in the words of the Gestures and
    /// Shortcut Ring panes' pull-down: "Show in Buttons" (the Buttons pane), "Show in
    /// Figma" (the app's Buttons part; `name` is the app's), or the part's "Set Up…"
    /// (`setUpKey`).
    func buttonTitle(applicationName name: String, setUpKey: String = "gestures-gesture-button-set-up") -> String {
        switch destination {
        case .buttonsPane:
            return NSLocalizedString("apps-trigger-show-in-buttons", comment: "")
        case .applicationButtons:
            // (The pull-down's key; `value` is its English, should the catalog lack it.)
            let format = NSLocalizedString("buttons-trigger-choice-show-in-app", value: "Show in %@", comment: "")
            return String(format: format, name)
        case .setUp:
            return NSLocalizedString(setUpKey, comment: "")
        }
    }

    /// The width of the row's line beside the row's button at its widest
    /// (`buttonMaxWidth`, which "Show in <app>" reaches with a long name).
    static var lineWidth: CGFloat {
        let box = PreferencesGroupedForm.boxWidth(paneWidth: ApplicationDetailViewController.paneWidth)
        return box - 2 * PreferencesGroupedForm.rowHorizontalInset - buttonMaxWidth - PreferencesGroupedForm.controlSpacing
    }

    /// - Parameters:
    ///   - titles: what the Buttons pane calls the triggers, in order.
    ///   - width: the line's width: a line that names the app says a long name cut short,
    ///     so that it fits two lines (the whole name is in the app's box).
    static func make(
        _ rule: ApplicationTriggerRule, application: Application, general: [ButtonBinding],
        titles: ([RecordedEvent]) -> [String] = { ButtonTriggerNaming.titles(for: $0) },
        width: CGFloat = lineWidth
    ) -> ApplicationTriggerRow {
        let fullName = application.getName()
        func line(_ key: String, _ arguments: String...) -> String {
            let format = NSLocalizedString(key, comment: "")
            let name = ApplicationPagePart.name(fullName, fittingTwoLinesOf: width) { name in
                [String(format: format, arguments: arguments + [name])]
            }
            return String(format: format, arguments: arguments + [name])
        }
        let own = application.ownButtonBindings
        let everywhere = rule.bindings(general: general)
        let here = rule.bindings(general: general, own: own)
        guard !here.isEmpty else {
            let text = line("apps-trigger-none")
            // A row of the app's own on what does it everywhere else: that row is why; the
            // row of that very trigger first, before one a press of it matches too (with
            // modifier keys).
            let exact = own.first { binding in everywhere.contains { $0.identity == binding.identity } }
            if let taken = exact ?? own.first(where: { ApplicationButtons.generalBinding(for: $0.triggerEvent, in: everywhere) != nil }) {
                return ApplicationTriggerRow(text: text, destination: .applicationButtons(taken.id))
            }
            return ApplicationTriggerRow(text: text, destination: .setUp)
        }
        let shared = here.filter { binding in everywhere.contains { $0.identity == binding.identity } }
        let onlyHere = here.filter { binding in !everywhere.contains { $0.identity == binding.identity } }
        func joined(_ bindings: [ButtonBinding]) -> String {
            var unique: [String] = []
            for title in titles(bindings.map(\.triggerEvent)) where !unique.contains(title) {
                unique.append(title)
            }
            return InterfaceList.joined(unique)
        }
        guard let first = onlyHere.first else {
            let text = String(format: NSLocalizedString("apps-trigger-everywhere", comment: ""), joined(shared))
            // (A binding the app has of its own with the same action is Buttons' one there.)
            let named = shared.first.flatMap { binding in everywhere.first { $0.identity == binding.identity } }
            return ApplicationTriggerRow(text: text, destination: .buttonsPane, buttonsBindingID: named?.id)
        }
        let text = shared.isEmpty
            ? line("apps-trigger-only-here", joined(onlyHere))
            : line("apps-trigger-mixed", joined(shared), joined(onlyHere))
        return ApplicationTriggerRow(text: text, destination: .applicationButtons(first.id))
    }
}
