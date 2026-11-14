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
//  Scrolling: "Use settings from Scrolling" and, while it is off, the Scrolling settings
//  for the app.
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

/// "Use settings from Scrolling" and, while it is off, the Scrolling settings editing the
/// app's own options under the switch's box (PreferencesScrollingViewController with a
/// target application: no preview, its own "Reset to Defaults"), as the Gestures and
/// Shortcut Ring parts show what is under their switch: while it is on the part is the
/// switch's box alone. The settings' "Thumb wheel" box has the app's own speed and swap
/// (scroll values like the others) and its own action, which is the thumb wheel's row of
/// the Buttons part: while the switch is on that row is where the action is set.
///
/// The settings' controller is made with the part and kept while the switch is on, its
/// view out of the part: "Advanced", the reset's Undo (which shows on the controller that
/// made it) and its "Undo Reset" stay with the one controller for the page's life.
final class ApplicationScrollingPartViewController: NSViewController, ApplicationPagePartController, PreferencesScrollingContainer {

    enum Identifier {
        static let inherit = NSUserInterfaceItemIdentifier("apps-detail-inherit")
    }

    let application: Application
    private let uiStateDefaults: UserDefaults
    var onHeightChange: (() -> Void)?
    /// "Use settings from Scrolling" was switched (the list says which apps have their own).
    var onInheritChange: (() -> Void)?
    /// The app's own thumb wheel function changed in these settings (its action, a reset or
    /// the reset's Undo): the Buttons part and the list show it. Handed on to the settings
    /// as it is, so that an Undo after the page closed still reaches the list.
    var onOwnThumbWheelChange: (() -> Void)? {
        didSet { scrollingController?.onApplicationThumbWheelChange = onOwnThumbWheelChange }
    }

    private(set) var inheritRow: PreferencesSwitchRow!
    private(set) var inheritSection: PreferencesGroupSection!
    /// The app's own settings: in the part only while "Use settings from Scrolling" is off
    /// (`showsSettings`), kept while it is on.
    private(set) var scrollingController: PreferencesScrollingViewController!
    /// The settings stand under the switch's box (the switch is off).
    var showsSettings: Bool {
        return isViewLoaded && scrollingController.view.superview === view
    }
    /// The part ends under the switch's box (the switch is on), or under the settings.
    private var endsUnderInheritSection: NSLayoutConstraint!
    private var settingsConstraints: [NSLayoutConstraint] = []

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
        // as they load. They load with the page, also while the switch keeps them out.
        let scrolling = PreferencesScrollingViewController()
        scrolling.uiStateDefaults = uiStateDefaults
        scrolling.currentTargetApplication = application
        scrolling.onApplicationThumbWheelChange = onOwnThumbWheelChange
        addChild(scrolling)
        scrollingController = scrolling
        scrolling.view.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(section)
        let margin = PreferencesGroupedForm.margin
        endsUnderInheritSection = section.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -margin)
        NSLayoutConstraint.activate([
            section.topAnchor.constraint(equalTo: root.topAnchor, constant: margin),
            section.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: margin),
            section.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -margin),
            endsUnderInheritSection,
        ])
        view = root
        syncViewWithOptions()
    }

    func syncViewWithOptions() {
        if sync() {
            onHeightChange?()
        }
    }

    /// Shows the stored settings; true when the settings came or went while the part is on
    /// screen (an Undo of the app's removal, a change made elsewhere): the page measures
    /// again.
    @discardableResult
    private func sync() -> Bool {
        guard isViewLoaded else { return false }
        let inherits = application.inherit
        inheritRow.isOn = inherits
        inheritRow.explanation = ApplicationDetailViewController.inheritExplanation(on: inherits, name: application.getName())
        // Out of the part before they change and into it after, so that the page hears of
        // their height once, from here.
        var moved = inherits && showSettings(false)
        scrollingController.syncViewWithOptions()
        moved = (!inherits && showSettings(true)) || moved
        return moved && view.superview != nil
    }

    func partWillHide() {}

    /// Puts the app's own settings under the switch's box, or takes them away again: they
    /// are there exactly while "Use settings from Scrolling" is off. True when they came or
    /// went.
    private func showSettings(_ shows: Bool) -> Bool {
        guard shows != showsSettings else { return false }
        let settings = scrollingController.view
        guard shows else {
            // "Undo Reset" is not offered for settings out of sight.
            scrollingController.endUndoOffer()
            NSLayoutConstraint.deactivate(settingsConstraints)
            settingsConstraints = []
            settings.removeFromSuperview()
            endsUnderInheritSection.isActive = true
            return true
        }
        endsUnderInheritSection.isActive = false
        view.addSubview(settings)
        settingsConstraints = [
            // The settings bring their own margins.
            settings.topAnchor.constraint(equalTo: inheritSection.bottomAnchor),
            settings.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            settings.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            settings.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ]
        NSLayoutConstraint.activate(settingsConstraints)
        return true
    }

    /// The embedded settings changed their height (Advanced opened or closed, a line came
    /// or went). Out of the part, their height is not the page's.
    func fitToContent() {
        guard showsSettings else { return }
        onHeightChange?()
    }

    /// On: the app follows the Scrolling pane; its own options stay stored for later, out
    /// of sight. Off: the app's own options under the switch's box, which start as a copy
    /// of the Scrolling settings when they were never edited, and the thumb wheel's speed
    /// and swap as the wheel runs with them now when the app has none yet (so switching off
    /// changes nothing until the user does).
    @objc func inheritClick(_ sender: NSSwitch) {
        application.setUsesScrollingSettings(
            sender.state == .on, scrolling: Options.shared.scroll, thumbWheel: Options.shared.thumbWheel
        )
        // (The settings came or went: the page measures again, once.)
        sync()
        onHeightChange?()
        onInheritChange?()
    }
}

// MARK: - Shortcut Ring

/// "Use the general ring" and, while it is off, the app's own ring: the drawing, the freeze
/// switch and the eight rows of the Shortcut Ring pane (RingPreferencesViewController with
/// this app), which open while the app is in front. What opens the ring is a binding of
/// Buttons, or of the app's Buttons part (the switch's line says when nothing opens it with
/// the app in front).
///
/// For an app with suggested shortcuts (`ShortcutRingSuggestions`) the ring the switch
/// makes starts with them, and while the app's own ring is in use a second row says so
/// (and how many places the keyboard layout leaves empty); for a ring that did not start
/// with them (made before there were any, or by hand) the row says that "Reset to
/// Defaults" puts them in. Nothing is filled without a click: the switch, or "Reset to
/// Defaults".
///
/// "Reset to Defaults" ends the own ring, there with it: the ring goes back to where it
/// started (the suggestion, else a copy of the general ring as it is now; the freeze switch
/// the general ring's as it is now), the switch stays; the window's Undo takes it back, also
/// after the page closed.
///
/// While nothing opens the ring with the app in front (`ApplicationTriggerRule`), the own
/// ring's eight rows are folded under their "Shortcuts" title (`PreferencesDisclosureSection`),
/// as the Shortcut Ring pane folds its places: a click opens them, all of it editable; the
/// drawing, the freeze switch and "Reset to Defaults" stay in sight (a click on a place of
/// the drawing opens the rows too). Once something opens the ring there, "Shortcuts" is a
/// plain title.
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
    /// The own ring's view and "Reset to Defaults", as one view, under the switch's box:
    /// there only while "Use the general ring" is off. Its width is the boxes'; the ring's
    /// view inside it reaches past its edges by the margins the ring's view brings (clipped
    /// away by a view of their own, which holds the ring's view alone: the button's focus
    /// ring is not cut).
    private(set) var ownRingBody: NSView?
    /// "Shortcuts", which folds the own ring's eight rows: foldable while the own ring is in
    /// use and nothing opens the ring with the app in front; nil otherwise.
    var ownRingFold: PreferencesDisclosureSection? {
        guard let places = ringController?.placesSection, places.isCollapsible else { return nil }
        return places
    }
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
            undoActionName: Self.resetActionName(for: application),
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
        let opens = ApplicationDetailViewController.RingTrigger.of(application, general: Options.shared.buttons.binding)
        let line = ApplicationDetailViewController.generalRingExplanation(
            on: usesGeneralRing, name: application.getName(), opens: opens
        )
        var remeasures = generalRingRow.explanation != line && view.superview != nil
        generalRingRow.explanation = line
        if showOwnRing(!usesGeneralRing, folds: opens != .opens) {
            remeasures = remeasures || view.superview != nil
        }
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

    /// The row's line. For a ring that started from the suggestion: "The ring started from
    /// the shortcuts suggested for Figma."; for one that did not: "Reset to Defaults fills
    /// the ring with the shortcuts suggested for Figma." When the keyboard layout leaves
    /// `emptyPlaces` places of the suggestion empty (their keys need Option there), the
    /// line says so instead of naming the app.
    static func suggestionExplanation(name: String, emptyPlaces: Int, startedFromIt: Bool) -> String {
        let base = startedFromIt ? "apps-detail-ring-suggested-in-use" : "apps-detail-ring-suggested-reset"
        guard emptyPlaces > 0 else {
            return String(format: NSLocalizedString(base, comment: ""), name)
        }
        let key = base + "-empty" + (emptyPlaces == 1 ? "-one" : "-other")
        return String(format: NSLocalizedString(key, comment: ""), emptyPlaces)
    }

    /// Whether the app's own ring started from its suggested shortcuts: it was filled from
    /// them in this run of the app (the switch or "Reset to Defaults"), or it holds them
    /// now (a ring read from the settings knows only that).
    func ringStartedFromSuggestion(suggested: [ShortcutRingPlace]) -> Bool {
        guard let own = application.ownRingPlaces else { return false }
        return application.ring?.startedFromSuggestion == true || own == suggested
    }

    /// The row of the suggested shortcuts: there while the app has a suggestion and its own
    /// ring is in use, its line saying whether the ring started from them and how many
    /// places the layout leaves empty. True when the row came or went, or its room changed,
    /// while the part is on screen (the page measures again).
    private func showSuggestion() -> Bool {
        let shows = suggestion != nil && application.ownRingPlaces != nil
        var moved = suggestionRow.isHidden == shows && view.superview != nil
        suggestionRow.isHidden = !shows
        guard shows, let suggestion, let suggested = suggestedPlaces() else { return moved }
        let line = Self.suggestionExplanation(
            name: application.getName(), emptyPlaces: suggestion.placesLeftEmpty(in: suggested),
            startedFromIt: ringStartedFromSuggestion(suggested: suggested)
        )
        if suggestionRow.explanation != line {
            suggestionRow.explanation = line
            moved = moved || view.superview != nil
        }
        return moved
    }

    // MARK: - Reset to Defaults

    /// The undo action's name, its own, not the Shortcut Ring pane's: "Reset Shortcut Ring
    /// in Calculator" (Edit › Undo says which reset it takes back, and "Undo Reset" never
    /// takes back the pane's or another app's).
    static let resetActionNameKey = "apps-undo-reset-ring"

    static func resetActionName(for application: Application) -> String {
        return String(format: NSLocalizedString(resetActionNameKey, comment: ""), application.getName())
    }

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

    /// The app's own ring is in use and differs from where it started (its places, or its
    /// freeze switch from the general ring's as it is now).
    var hasSettingsToReset: Bool {
        guard let own = application.ownRingPlaces else { return false }
        let general = Options.shared.ring
        return own != startPlaces() || application.ringThatOpens(general: general).freezePointer != general.freezePointer
    }

    /// "Reset to Defaults": the own ring as it started, its eight places and the general
    /// ring's freeze switch; the switch stays off. Edit › Undo brings back what was there.
    private func resetRing(undoManager undo: UndoManager?) {
        guard hasSettingsToReset else { return }
        let showing = partShowing ?? { [weak self] entry in
            self?.application === entry ? self : nil
        }
        let suggested = suggestedPlaces()
        Self.fillRing(
            of: application, with: suggested ?? Options.shared.ring.places,
            freezePointer: Options.shared.ring.freezePointer, fromSuggestion: suggested != nil,
            undoManager: undo, showing: showing
        )
    }

    /// As the removal of a thumb wheel (`ApplicationButtonsViewController`): the undo
    /// target is the settings, not the page; Undo and Redo find the app's entry by its path
    /// when they run, and show the change on the part `showing` gives for it. (A ring kept
    /// for later takes them too: the switch is never touched.)
    /// (`fromSuggestion`: the places are the app's suggested shortcuts; Undo gives the ring
    /// back what it knew of them before.)
    private static func fillRing(
        of application: Application, with places: [ShortcutRingPlace], freezePointer: Bool?, fromSuggestion: Bool,
        undoManager undo: UndoManager?, showing: @escaping (Application) -> ApplicationRingPartViewController?
    ) {
        guard let before = application.ring else { return }
        application.replaceOwnRing(places: places, freezePointer: freezePointer, startedFromSuggestion: fromSuggestion)
        guard let after = application.ring,
              after != before || after.startedFromSuggestion != before.startedFromSuggestion else { return }
        showing(application)?.syncViewWithOptions()
        guard let undo else { return }
        let path = application.path
        undo.registerUndo(withTarget: Options.shared) { [weak undo] _ in
            guard let entry = PreferencesApplicationViewController.existingApplication(
                forPaths: PreferencesApplicationViewController.knownPaths(forStoredPath: path)
            ) else { return }
            fillRing(
                of: entry, with: before.places, freezePointer: before.freezePointer,
                fromSuggestion: before.startedFromSuggestion, undoManager: undo, showing: showing
            )
        }
        undo.setActionName(resetActionName(for: application))
    }

    func partWillHide() {
        ringController?.endEditing()
        resetToDefaults.endUndoOffer()
    }

    /// Puts the app's own ring (the drawing, the freeze switch and the eight rows) and
    /// "Reset to Defaults" under the switch's box, or takes them away again: they are there
    /// exactly while "Use the general ring" is off. While `folds`, the eight rows are folded
    /// under their "Shortcuts" title (folded when it can fold); else the title is a plain one.
    /// True when something came, went, folded or unfolded.
    @discardableResult
    private func showOwnRing(_ shows: Bool, folds: Bool) -> Bool {
        guard shows else {
            guard let ring = ringController else { return false }
            ring.endEditing()
            resetToDefaults.endUndoOffer()
            NSLayoutConstraint.deactivate(ownRingConstraints)
            ownRingConstraints = []
            ownRingBody?.removeFromSuperview()
            ownRingBody = nil
            resetFooter.removeFromSuperview()
            ring.view.removeFromSuperview()
            ring.removeFromParent()
            ringController = nil
            endsUnderRingSection.isActive = true
            return true
        }
        var moved = false
        if ownRingBody == nil {
            let body = makeOwnRingBody()
            endsUnderRingSection.isActive = false
            view.addSubview(body)
            let margin = PreferencesGroupedForm.margin
            ownRingConstraints = [
                // The room the ring's own top margin always made under the box.
                body.topAnchor.constraint(equalTo: ringSection.bottomAnchor, constant: margin),
                body.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin),
                body.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -margin),
                body.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -margin),
            ]
            NSLayoutConstraint.activate(ownRingConstraints)
            moved = true
        }
        if let places = ringController?.placesSection, places.isCollapsible != folds {
            places.isCollapsible = folds
            moved = true
        }
        return moved
    }

    /// The own ring's controller and the view that holds its view and "Reset to Defaults"
    /// (`ownRingBody`).
    private func makeOwnRingBody() -> NSView {
        let ring = RingPreferencesViewController(application: application)
        ring.onPlaceChange = { [weak self] in self?.resetToDefaults.settingsDidChange() }
        addChild(ring)
        ringController = ring
        let body = NSView()
        body.translatesAutoresizingMaskIntoConstraints = false
        // The ring's view reaches past the body by its own margins: they are cut off, so
        // that nothing of it covers a title above the body. Only around the ring's view:
        // the footer's button draws its focus ring past its own edges, which are the body's.
        let ringClip = NSView()
        ringClip.translatesAutoresizingMaskIntoConstraints = false
        ringClip.clipsToBounds = true
        let ringView = ring.view
        ringView.translatesAutoresizingMaskIntoConstraints = false
        // The rows opened or folded: the page measures again.
        ring.placesSection?.onExpandedChange = { [weak self] _ in self?.onHeightChange?() }
        ringClip.addSubview(ringView)
        body.addSubview(ringClip)
        body.addSubview(resetFooter)
        let margin = PreferencesGroupedForm.margin
        NSLayoutConstraint.activate([
            ringClip.topAnchor.constraint(equalTo: body.topAnchor),
            ringClip.leadingAnchor.constraint(equalTo: body.leadingAnchor),
            ringClip.trailingAnchor.constraint(equalTo: body.trailingAnchor),
            ringView.topAnchor.constraint(equalTo: ringClip.topAnchor, constant: -margin),
            ringView.leadingAnchor.constraint(equalTo: ringClip.leadingAnchor, constant: -margin),
            ringView.trailingAnchor.constraint(equalTo: ringClip.trailingAnchor, constant: margin),
            ringView.bottomAnchor.constraint(equalTo: ringClip.bottomAnchor),
            // Its margin under the rows is the room above a footer.
            resetFooter.topAnchor.constraint(equalTo: ringClip.bottomAnchor),
            resetFooter.leadingAnchor.constraint(equalTo: body.leadingAnchor),
            resetFooter.trailingAnchor.constraint(equalTo: body.trailingAnchor),
            resetFooter.bottomAnchor.constraint(equalTo: body.bottomAnchor),
        ])
        ownRingBody = body
        return body
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
