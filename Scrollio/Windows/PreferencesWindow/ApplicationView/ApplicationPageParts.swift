//
//  ApplicationPageParts.swift
//  Scrollio
//
//  The parts of an app's page under Apps: one kind of the app's settings each, shown one at
//  a time under the app's box and chosen with a segmented control (as Apple's detail pages
//  do for a few peer views), so that the page stays short. The table of parts says, per
//  part, its name, its mark in the list of apps, whether the app has settings of that kind
//  of its own, and how its controller is made. Another kind is one more entry.
//
//  Scrolling: "Use settings from Scrolling" and the Scrolling settings for the app.
//  Buttons: the app's own buttons (`ApplicationButtonsViewController`).
//  Gestures: "Use the general gestures" and, while it is off, the app's own gestures
//  (`ApplicationGesturesPartViewController`).
//  Shortcut Ring: "Use the general ring" and, while it is off, the app's own ring (which
//  starts with the app's suggested shortcuts when it has some, `ShortcutRingSuggestions`).
//  The order is the sidebar's.
//

import Cocoa

/// What the page asks of a part's controller.
protocol ApplicationPagePartController: NSViewController {
    /// The part's height changed (Advanced opened, a ring or a row came or went).
    var onHeightChange: (() -> Void)? { get set }
    /// The settings may have changed elsewhere: the part shows them again.
    func syncViewWithOptions()
    /// The part goes out of sight (another part, the list): what it opened closes.
    func partWillHide()
}

/// One part of an app's page.
struct ApplicationPagePart: Equatable {

    /// What the page remembers (in the window's UI state, not a setting).
    let id: String
    /// The segment's title.
    let titleKey: String
    /// The mark in the list of apps while the app has settings of this kind of its own: an
    /// SF Symbol, and what VoiceOver and the tooltip say.
    let markSymbol: String
    let markLabelKey: String
    /// The app has settings of this kind of its own (computed from the app's entry, never
    /// stored).
    let hasOwnSettings: (Application) -> Bool
    /// The part's controller for `application`; `uiStateDefaults` keeps what a part opens
    /// and closes (Advanced of Scrolling).
    let makeController: (_ application: Application, _ uiStateDefaults: UserDefaults) -> ApplicationPagePartController

    static func == (a: ApplicationPagePart, b: ApplicationPagePart) -> Bool {
        return a.id == b.id
    }

    var title: String {
        return NSLocalizedString(titleKey, comment: "")
    }

    var markLabel: String {
        return NSLocalizedString(markLabelKey, comment: "")
    }

    static let scrolling = ApplicationPagePart(
        id: "scrolling",
        titleKey: "apps-detail-part-scrolling",
        markSymbol: "arrow.up.and.down",
        markLabelKey: "apps-mark-scrolling",
        hasOwnSettings: { !$0.inherit },
        makeController: { ApplicationScrollingPartViewController(application: $0, uiStateDefaults: $1) }
    )

    static let buttons = ApplicationPagePart(
        id: "buttons",
        titleKey: "apps-detail-part-buttons",
        markSymbol: "button.horizontal.top.press",
        markLabelKey: "apps-mark-buttons",
        // A button or key of its own, or the thumb wheel (`ApplicationThumbWheel`).
        hasOwnSettings: { $0.hasOwnButtonsPart },
        makeController: { application, _ in ApplicationButtonsViewController(application: application) }
    )

    static let gestures = ApplicationPagePart(
        id: "gestures",
        titleKey: "apps-detail-part-gestures",
        markSymbol: "hand.draw",
        markLabelKey: "apps-mark-gestures",
        hasOwnSettings: { $0.ownGestures != nil },
        makeController: { application, _ in ApplicationGesturesPartViewController(application: application) }
    )

    static let ring = ApplicationPagePart(
        id: "ring",
        titleKey: "apps-detail-part-ring",
        markSymbol: "circle.grid.cross",
        markLabelKey: "apps-mark-ring",
        hasOwnSettings: { $0.ownRingPlaces != nil },
        makeController: { application, _ in ApplicationRingPartViewController(application: application) }
    )

    /// The parts in the order of the control and of the marks (the sidebar's order).
    static let all: [ApplicationPagePart] = [.scrolling, .buttons, .gestures, .ring]

    /// The part with `id`; Scrolling for one that does not exist (any more).
    static func part(withID id: String?) -> ApplicationPagePart {
        return all.first { $0.id == id } ?? .scrolling
    }

    /// The part the page shows when it opens: the one shown last, for every app alike.
    static let shownDefaultsKey = "appsPageShownPart"

    static func remembered(in defaults: UserDefaults) -> ApplicationPagePart {
        return part(withID: defaults.string(forKey: shownDefaultsKey))
    }

    func remember(in defaults: UserDefaults) {
        defaults.set(id, forKey: Self.shownDefaultsKey)
    }

    /// The kinds `application` has settings of its own of, in the order of the parts.
    static func ownSettings(of application: Application) -> [ApplicationPagePart] {
        return all.filter { $0.hasOwnSettings(application) }
    }
}

// MARK: - Scrolling

/// "Use settings from Scrolling" and, under it, the Scrolling settings editing the app's
/// own options (PreferencesScrollingViewController with a target application: no preview,
/// dimmed while the app uses the Scrolling settings, its own "Reset to Defaults").
final class ApplicationScrollingPartViewController: NSViewController, ApplicationPagePartController, PreferencesScrollingContainer {

    enum Identifier {
        static let inherit = NSUserInterfaceItemIdentifier("apps-detail-inherit")
    }

    let application: Application
    private let uiStateDefaults: UserDefaults
    var onHeightChange: (() -> Void)?
    /// "Use settings from Scrolling" was switched (the list says which apps have their own).
    var onInheritChange: (() -> Void)?

    private(set) var inheritRow: PreferencesSwitchRow!
    private(set) var inheritSection: PreferencesGroupSection!
    private(set) var scrollingController: PreferencesScrollingViewController!

    init(application: Application, uiStateDefaults: UserDefaults) {
        self.application = application
        self.uiStateDefaults = uiStateDefaults
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("ApplicationScrollingPartViewController is built in code")
    }

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        let name = application.getName()
        let inherit = PreferencesSwitchRow(
            title: NSLocalizedString("apps-detail-inherit", comment: ""),
            explanation: nil,
            target: self,
            action: #selector(inheritClick(_:))
        )
        inherit.toggle.identifier = Identifier.inherit
        // Room for the longer of the two lines, so switching never changes the height.
        inherit.reservedExplanations = [true, false].map { ApplicationDetailViewController.inheritExplanation(on: $0, name: name) }
        inheritRow = inherit
        let section = PreferencesGroupSection(
            width: PreferencesGroupedForm.boxWidth(paneWidth: ApplicationDetailViewController.paneWidth),
            rows: [inherit]
        )
        inheritSection = section

        // Added as a child first: the settings tell their container their height as soon
        // as they load.
        let scrolling = PreferencesScrollingViewController()
        scrolling.uiStateDefaults = uiStateDefaults
        scrolling.currentTargetApplication = application
        addChild(scrolling)
        scrollingController = scrolling
        let settings = scrolling.view
        settings.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(section)
        root.addSubview(settings)
        let margin = PreferencesGroupedForm.margin
        NSLayoutConstraint.activate([
            section.topAnchor.constraint(equalTo: root.topAnchor, constant: margin),
            section.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: margin),
            section.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -margin),
            // The settings bring their own margins.
            settings.topAnchor.constraint(equalTo: section.bottomAnchor),
            settings.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            settings.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            settings.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root
        syncViewWithOptions()
    }

    func syncViewWithOptions() {
        guard isViewLoaded else { return }
        inheritRow.isOn = application.inherit
        inheritRow.explanation = ApplicationDetailViewController.inheritExplanation(on: application.inherit, name: application.getName())
        scrollingController.syncViewWithOptions()
    }

    func partWillHide() {}

    /// The embedded settings changed their height (they loaded, Advanced opened or closed).
    func fitToContent() {
        guard isViewLoaded else { return }
        onHeightChange?()
    }

    /// On: the app follows the Scrolling pane; its own options stay stored for later.
    /// Off: the app's own options, which start as a copy of the Scrolling settings when
    /// they were never edited (so switching off changes nothing until the user does).
    @objc func inheritClick(_ sender: NSSwitch) {
        application.setUsesScrollingSettings(sender.state == .on, scrolling: Options.shared.scroll)
        syncViewWithOptions()
        onInheritChange?()
    }
}

// MARK: - Shortcut Ring

/// "Use the general ring" and, while it is off, the app's own ring: the drawing and the
/// eight rows of the Shortcut Ring pane (RingPreferencesViewController with this app), which
/// open while the app is in front. What opens the ring is a binding of Buttons, or of the
/// app's Buttons part (the switch's line says when nothing opens it with the app in
/// front); the freeze switch is the same for every app and stays in the Shortcut Ring pane.
///
/// For an app with suggested shortcuts (`ShortcutRingSuggestions`) the ring the switch
/// makes starts with them, and while the app's own ring is in use a second row says so
/// (and how many places the keyboard layout leaves empty). Nothing is filled without a
/// click: the switch, or "Reset to Defaults".
///
/// "Reset to Defaults" ends the own ring, there with it: the ring goes back to where it
/// started (the suggestion, else a copy of the general ring as it is now), the switch
/// stays; the window's Undo takes it back, also after the page closed.
final class ApplicationRingPartViewController: NSViewController, ApplicationPagePartController {

    enum Identifier {
        static let generalRing = NSUserInterfaceItemIdentifier("apps-detail-general-ring")
        static let reset = NSUserInterfaceItemIdentifier("apps-detail-ring-reset")
    }

    let application: Application
    var onHeightChange: (() -> Void)?
    /// Takes Undo and Redo of "Reset to Defaults"; the window's when nil.
    var paneUndoManager: UndoManager?
    /// The Shortcut Ring part that shows an app's entry now, if any (the pane's answer).
    /// An Undo or Redo of "Reset to Defaults" asks it when it runs, maybe after this page
    /// closed and the app's page opened again: it must not hold the page. nil: this part,
    /// while it is there.
    var partShowing: ((Application) -> ApplicationRingPartViewController?)?
    /// The app's suggested shortcuts, found by its bundle when the page was made; nil for
    /// an app without any.
    let suggestion: ShortcutRingSuggestion?

    private(set) var ringSection: PreferencesGroupSection!
    private(set) var generalRingRow: PreferencesSwitchRow!
    /// "Suggested shortcuts" and where the ring started: shown while the app has a
    /// suggestion and its own ring is in use.
    private(set) var suggestionRow: PreferencesGroupRow!
    /// The app's own ring, its drawing and its eight rows: there only while "Use the
    /// general ring" is off.
    private(set) var ringController: RingPreferencesViewController?
    /// "Reset to Defaults" under the own ring, there with it.
    private(set) var resetToDefaults: PreferencesPaneReset!
    var resetToDefaultsButton: NSButton {
        return resetToDefaults.button
    }
    private(set) var resetFooter: PreferencesGroupFooter!
    /// The part ends under the switch's box (no own ring), or under the own ring.
    private var endsUnderRingSection: NSLayoutConstraint!
    private var ownRingConstraints: [NSLayoutConstraint] = []

    init(application: Application) {
        self.application = application
        suggestion = ShortcutRingSuggestions.suggestion(for: application)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("ApplicationRingPartViewController is built in code")
    }

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        let name = application.getName()
        let generalRing = PreferencesSwitchRow(
            title: NSLocalizedString("apps-detail-ring-general", comment: ""),
            explanation: nil,
            target: self,
            action: #selector(generalRingClick(_:))
        )
        generalRing.toggle.identifier = Identifier.generalRing
        // Room for the longer of the two lines the switch alternates, so switching never
        // moves what is below; a line on what opens the ring (the same in both states)
        // takes the room it needs, and the page measures again.
        generalRing.reservedExplanations = [true, false].map { ApplicationDetailViewController.generalRingExplanation(on: $0, name: name) }
        generalRingRow = generalRing
        let suggested = PreferencesGroupRow(
            title: NSLocalizedString("apps-detail-ring-suggested", comment: ""),
            explanation: nil
        )
        // (Its room: its line, set when it shows.)
        suggested.isHidden = true
        suggestionRow = suggested
        let reset = PreferencesPaneReset(
            undoActionNameKey: Self.resetActionNameKey,
            hasSettingsToReset: { [weak self] in self?.hasSettingsToReset ?? false },
            undoManager: { [weak self] in self?.undoTarget },
            reset: { [weak self] undo in self?.resetRing(undoManager: undo) }
        )
        // What is being edited (a name typed in a row's popover) goes first.
        reset.willReset = { [weak self] in self?.ringController?.endEditing() }
        reset.button.identifier = Identifier.reset
        resetToDefaults = reset
        resetFooter = PreferencesGroupFooter(trailing: [reset.button])
        // (No title: the part's segment names it.)
        let section = PreferencesGroupSection(
            width: PreferencesGroupedForm.boxWidth(paneWidth: ApplicationDetailViewController.paneWidth),
            rows: [generalRing, suggested]
        )
        ringSection = section
        root.addSubview(section)
        let margin = PreferencesGroupedForm.margin
        endsUnderRingSection = section.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -margin)
        NSLayoutConstraint.activate([
            section.topAnchor.constraint(equalTo: root.topAnchor, constant: margin),
            section.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: margin),
            section.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -margin),
            endsUnderRingSection,
        ])
        view = root
        syncViewWithOptions()
    }

    func syncViewWithOptions() {
        if sync() {
            onHeightChange?()
        }
    }

    /// Shows the stored settings; true when the page must measure again: the line changed
    /// while the part is on screen (an Undo in the app's Buttons), and may take more or
    /// less room.
    @discardableResult
    private func sync() -> Bool {
        guard isViewLoaded else { return false }
        let usesGeneralRing = application.usesGeneralRing
        generalRingRow.isOn = usesGeneralRing
        // (What opens the ring is a binding of Buttons or of the app's Buttons part, and
        // this part has no row for it: while nothing opens it with the app in front, the
        // line says so instead of promising a ring.)
        let line = ApplicationDetailViewController.generalRingExplanation(
            on: usesGeneralRing, name: application.getName(),
            opens: .of(application, general: Options.shared.buttons.binding)
        )
        let remeasures = generalRingRow.explanation != line && view.superview != nil
        generalRingRow.explanation = line
        showOwnRing(!usesGeneralRing)
        let suggestionMoved = showSuggestion()
        ringController?.reload()
        resetToDefaults.settingsDidChange()
        return remeasures || suggestionMoved
    }

    // MARK: - Suggested shortcuts

    /// The app's suggested shortcuts as places, on the keyboard layout in use now; nil for
    /// an app without a suggestion.
    func suggestedPlaces() -> [ShortcutRingPlace]? {
        return suggestion?.places(on: ShortcutRingSuggestions.layout())
    }

    /// "The ring started from the shortcuts suggested for Figma." When the keyboard layout
    /// leaves `emptyPlaces` places of the suggestion empty (their keys need Option there),
    /// the line says so instead of naming the app.
    static func suggestionExplanation(name: String, emptyPlaces: Int) -> String {
        guard emptyPlaces > 0 else {
            return String(format: NSLocalizedString("apps-detail-ring-suggested-in-use", comment: ""), name)
        }
        let key = "apps-detail-ring-suggested-in-use-empty" + (emptyPlaces == 1 ? "-one" : "-other")
        return String(format: NSLocalizedString(key, comment: ""), emptyPlaces)
    }

    /// The row of the suggested shortcuts: there while the app has a suggestion and its own
    /// ring is in use, its line saying how many places the layout leaves empty. True when
    /// the row came or went, or its room changed, while the part is on screen (the page
    /// measures again).
    private func showSuggestion() -> Bool {
        let shows = suggestion != nil && application.ownRingPlaces != nil
        var moved = suggestionRow.isHidden == shows && view.superview != nil
        suggestionRow.isHidden = !shows
        guard shows, let suggestion, let suggested = suggestedPlaces() else { return moved }
        let line = Self.suggestionExplanation(
            name: application.getName(), emptyPlaces: suggestion.placesLeftEmpty(in: suggested)
        )
        if suggestionRow.explanation != line {
            suggestionRow.explanation = line
            moved = moved || view.superview != nil
        }
        return moved
    }

    // MARK: - Reset to Defaults

    /// The undo action's name: the Shortcut Ring pane's ("Reset Shortcut Ring").
    static let resetActionNameKey = "ring-undo-reset"

    /// Where "Reset to Defaults" registers its Undo: the window's while the page is in it.
    var undoTarget: UndoManager? {
        return paneUndoManager ?? view.window?.undoManager
    }

    /// Where the app's own ring starts, and where "Reset to Defaults" takes it: the app's
    /// suggested shortcuts on the keyboard layout in use, else the general ring as it is
    /// now (as the switch starts it, `setUsesGeneralRing`).
    func startPlaces() -> [ShortcutRingPlace] {
        return suggestedPlaces() ?? Options.shared.ring.places
    }

    /// The app's own ring is in use and differs from where it started.
    var hasSettingsToReset: Bool {
        guard let own = application.ownRingPlaces else { return false }
        return own != startPlaces()
    }

    /// "Reset to Defaults": the own ring as it started, its eight places; the switch stays
    /// off. Edit › Undo brings back the places that were there.
    private func resetRing(undoManager undo: UndoManager?) {
        guard hasSettingsToReset else { return }
        let showing = partShowing ?? { [weak self] entry in
            self?.application === entry ? self : nil
        }
        Self.fillRing(of: application, with: startPlaces(), undoManager: undo, showing: showing)
    }

    /// As the removal of a thumb wheel (`ApplicationButtonsViewController`): the undo
    /// target is the settings, not the page; Undo and Redo find the app's entry by its path
    /// when they run, and show the change on the part `showing` gives for it. (A ring kept
    /// for later takes them too: the switch is never touched.)
    private static func fillRing(
        of application: Application, with places: [ShortcutRingPlace], undoManager undo: UndoManager?,
        showing: @escaping (Application) -> ApplicationRingPartViewController?
    ) {
        guard let before = application.ring?.places, before != places else { return }
        application.setOwnRingPlaces(places)
        showing(application)?.syncViewWithOptions()
        guard let undo else { return }
        let path = application.path
        undo.registerUndo(withTarget: Options.shared) { [weak undo] _ in
            guard let entry = PreferencesApplicationViewController.existingApplication(
                forPaths: PreferencesApplicationViewController.knownPaths(forStoredPath: path)
            ) else { return }
            fillRing(of: entry, with: before, undoManager: undo, showing: showing)
        }
        undo.setActionName(NSLocalizedString(resetActionNameKey, comment: ""))
    }

    func partWillHide() {
        ringController?.endEditing()
        resetToDefaults.endUndoOffer()
    }

    /// Puts the app's own ring (the drawing and the eight rows) and "Reset to Defaults"
    /// under the switch's box, or takes them away again: they are there exactly while "Use
    /// the general ring" is off.
    private func showOwnRing(_ shows: Bool) {
        guard shows != (ringController != nil) else { return }
        if let ring = ringController {
            ring.endEditing()
            NSLayoutConstraint.deactivate(ownRingConstraints)
            ownRingConstraints = []
            ring.view.removeFromSuperview()
            ring.removeFromParent()
            ringController = nil
            resetToDefaults.endUndoOffer()
            resetFooter.removeFromSuperview()
            endsUnderRingSection.isActive = true
            return
        }
        let ring = RingPreferencesViewController(application: application)
        ring.onPlaceChange = { [weak self] in self?.resetToDefaults.settingsDidChange() }
        addChild(ring)
        let ringView = ring.view
        ringView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(ringView)
        view.addSubview(resetFooter)
        endsUnderRingSection.isActive = false
        // The ring's view brings its own margins, as the Scrolling settings do: its margin
        // under the rows is the room above a footer.
        let margin = PreferencesGroupedForm.margin
        ownRingConstraints = [
            ringView.topAnchor.constraint(equalTo: ringSection.bottomAnchor),
            ringView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            ringView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            resetFooter.topAnchor.constraint(equalTo: ringView.bottomAnchor),
            resetFooter.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin),
            resetFooter.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -margin),
            resetFooter.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -margin),
        ]
        NSLayoutConstraint.activate(ownRingConstraints)
        ringController = ring
    }

    /// On: the ring of the Shortcut Ring pane opens while the app is in front; the app's
    /// own ring stays stored for later. Off: the app's own ring, which starts with the
    /// app's suggested shortcuts when it has some, else as a copy of the general ring as it
    /// is now, when the app never had one.
    @objc func generalRingClick(_ sender: NSSwitch) {
        // First what is being edited (a name typed in a row's popover) goes into the ring,
        // while it is still the app's own.
        ringController?.endEditing()
        let uses = sender.state == .on
        application.setUsesGeneralRing(
            uses, general: Options.shared.ring, suggested: uses || application.ring != nil ? nil : suggestedPlaces()
        )
        // (The own ring came or went: the page measures again, once.)
        sync()
        onHeightChange?()
    }
}
