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
//  Scrolling: "Scrolling in Safari" (Same as Scrolling, Own Settings, Left to macOS) and,
//  under it, the Scrolling settings for the app.
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

    /// What the app has of its own, in words, for its row in the list and its page's
    /// header, as System Settings › Notifications says it of an app: "Own scrolling, 2
    /// buttons and ring", "Own ring", "Nothing of its own yet". The parts' order. The list
    /// is joined in the app's own language (`listLocale`), not the Mac's region: an English
    /// app on a Slovenian Mac says "and", never "in".
    static func summary(of application: Application, locale: Locale = listLocale) -> String {
        var items: [String] = []
        if !application.inherit {
            items.append(NSLocalizedString("apps-summary-scrolling", comment: ""))
        }
        let buttons = application.ownButtonBindings.count
        if buttons == 1 {
            items.append(NSLocalizedString("apps-summary-buttons-one", comment: ""))
        } else if buttons > 1 {
            items.append(String(format: NSLocalizedString("apps-summary-buttons-other", comment: ""), buttons))
        }
        if application.ownThumbWheelFunction != nil {
            items.append(NSLocalizedString("apps-summary-thumb-wheel", comment: ""))
        }
        if application.ownGestures != nil {
            items.append(NSLocalizedString("apps-summary-gestures", comment: ""))
        }
        if application.ownRingPlaces != nil {
            items.append(NSLocalizedString("apps-summary-ring", comment: ""))
        }
        guard !items.isEmpty else { return NSLocalizedString("apps-summary-none", comment: "") }
        return String(format: NSLocalizedString("apps-summary-own", comment: ""), joinedList(items, locale: locale))
    }

    /// The language the app's texts are shown in (its first localization in use), for the
    /// words a list is joined with.
    static var listLocale: Locale {
        return Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
    }

    /// "1 button, gestures and ring": `items` joined as `locale` joins a list.
    static func joinedList(_ items: [String], locale: Locale) -> String {
        let formatter = ListFormatter()
        formatter.locale = locale
        return formatter.string(from: items) ?? items.joined(separator: ", ")
    }

    /// `name` whole, or cut short at its end with "…", so that every text `texts` makes
    /// with it takes at most two lines `width` wide in the explanations' font (an
    /// explanation fits two lines). Where such a text stands the whole name is at hand: in
    /// the app's box above it, and in a title's tooltip.
    static func name(_ name: String, fittingTwoLinesOf width: CGFloat, in texts: (String) -> [String]) -> String {
        guard width > 0 else { return name }
        let measure = NSTextField(wrappingLabelWithString: "")
        measure.font = PreferencesGroupedForm.explanationFont
        measure.preferredMaxLayoutWidth = width
        func height(_ text: String) -> CGFloat {
            measure.stringValue = text
            return measure.fittingSize.height
        }
        let twoLines = height("A\nA") + 0.5
        func fits(_ candidate: String) -> Bool {
            return texts(candidate).allSatisfy { height($0) <= twoLines }
        }
        guard !fits(name) else { return name }
        // The longest beginning of the name that fits, by halves.
        let characters = Array(name)
        var shortest = 1, longest = characters.count - 1
        var fitting = String(characters.prefix(1)) + "…"
        while shortest <= longest {
            let length = (shortest + longest) / 2
            let candidate = String(characters.prefix(length)).trimmingCharacters(in: .whitespaces) + "…"
            if fits(candidate) {
                fitting = candidate
                shortest = length + 1
            } else {
                longest = length - 1
            }
        }
        return fitting
    }
}

// MARK: - The first rows' push button

extension ApplicationTriggerRow {

    /// The widest the push button of the Gestures and Shortcut Ring parts' first rows gets:
    /// "Show in <app>" with a long name is cut short (the whole of it in its tooltip), and
    /// the row's line keeps its room.
    static let buttonMaxWidth: CGFloat = 200

    /// Makes `button` such a push button: no wider than `buttonMaxWidth`.
    static func limitWidth(of button: NSButton) {
        button.lineBreakMode = .byTruncatingTail
        button.widthAnchor.constraint(lessThanOrEqualToConstant: buttonMaxWidth).isActive = true
    }

    /// Shows `title` on `button`, with the whole of it in the tooltip while it is cut short.
    static func show(_ title: String, on button: NSButton) {
        if button.title != title {
            button.title = title
        }
        let cut = (button.cell?.cellSize.width ?? 0) > buttonMaxWidth
        button.toolTip = cut ? title : nil
    }
}

// MARK: - Scrolling

/// "Scrolling in Safari", one choice in a pop-up (`ApplicationScrollingChoice`): Same as
/// Scrolling, Own Settings or Left to macOS, worked out from what is stored. Under its box
/// the Scrolling settings editing the app's own options (PreferencesScrollingViewController
/// with a target application: no preview, "Copy from Scrolling") for Own Settings; for Left
/// to macOS only what still acts there, the Thumb wheel box (`isLeftToMacOS`); for Same
/// as Scrolling nothing, the choice's box alone, as the Gestures and Shortcut Ring parts
/// show what is under their switch. The settings' "Thumb
/// wheel" box has the app's own speed and swap (scroll values like the others) and its own
/// action, which is the thumb wheel's row of the Buttons part: with Same as Scrolling that
/// row is where the action is set.
///
/// The pop-up follows what is stored, with one exception: while the part is on screen it
/// never moves from Own Settings to Left to macOS for what the user does here (the pick
/// itself, or smoothing and reversing switched off by hand), so nothing folds under the
/// pointer; the next showing of the part says Left to macOS. A change made elsewhere (the
/// menu bar, Undo or Redo, "Copy from Scrolling") shows at once.
///
/// Each pick is one step of Edit › Undo ("Change Scrolling in Safari"), registered on the
/// settings (`Options.shared`) so that it outlives the page: Undo and Redo find the app's
/// entry by its path and show on the part the pane says is open (`partShowing`).
///
/// The settings' controller is made with the part and kept while the app uses the
/// Scrolling settings, its view out of the part: "Advanced", the reset's Undo (which shows
/// on the controller that made it) and its "Undo Reset" stay with the one controller for
/// the page's life.
final class ApplicationScrollingPartViewController: NSViewController, ApplicationPagePartController, PreferencesScrollingContainer {

    enum Identifier {
        /// The pop-up keeps the identifier of the switch it replaced.
        static let inherit = NSUserInterfaceItemIdentifier("apps-detail-inherit")
    }

    let application: Application
    private let uiStateDefaults: UserDefaults
    var onHeightChange: (() -> Void)?
    /// What the app has of its own changed (a pick, its Undo or Redo): the list says which
    /// apps have their own. The page hands on the pane's, which outlives the page.
    var onInheritChange: (() -> Void)?
    /// The choice the pop-up shows changed: the page's line under the app's box follows.
    var onChoiceChange: (() -> Void)?
    /// The app's own thumb wheel function changed in these settings (its action, a reset or
    /// the reset's Undo): the Buttons part and the list show it. Handed on to the settings
    /// as it is, so that an Undo after the page closed still reaches the list.
    var onOwnThumbWheelChange: (() -> Void)? {
        didSet { scrollingController?.onApplicationThumbWheelChange = onOwnThumbWheelChange }
    }
    /// The pane's answer to which Scrolling part shows an app's entry now: an Undo or Redo
    /// of a pick or of "Copy from Scrolling" shows there, on the page open when it runs
    /// (the page that made it may be gone). Nil: this part, while it shows that entry.
    var partShowing: ((Application) -> ApplicationScrollingPartViewController?)? {
        didSet { handOnPartShowing() }
    }
    /// Takes Undo and Redo of a pick; the window's when nil.
    var paneUndoManager: UndoManager?

    private(set) var choiceRow: PreferencesGroupRow!
    private(set) var choicePopUp: NSPopUpButton!
    private(set) var choiceSection: PreferencesGroupSection!
    /// What the pop-up shows (`syncViewWithOptions` sets it).
    private(set) var shownChoice: ApplicationScrollingChoice = .sameAsScrolling
    /// The app's name the row is titled with, and as its lines say it (cut short when a
    /// line would take more than two lines beside the pop-up).
    private var titledName: String?
    private var linesName = ""
    /// Own Settings is held over stored values that say Left to macOS: the user made them
    /// so here, by hand, while the part shows. Kept while those values stay as they are
    /// and the part is on screen.
    private var heldOwnSettings: ChoiceInputs?
    /// The app's own settings: in the part except with Same as Scrolling (`showsSettings`),
    /// kept while that shows.
    private(set) var scrollingController: PreferencesScrollingViewController!
    /// The settings stand under the choice's box.
    var showsSettings: Bool {
        return isViewLoaded && scrollingController.view.superview === view
    }
    /// The part ends under the choice's box (Same as Scrolling), or under the settings.
    private var endsUnderChoiceSection: NSLayoutConstraint!
    private var settingsConstraints: [NSLayoutConstraint] = []

    /// What the choice is worked out from.
    private struct ChoiceInputs: Equatable {
        let inherit: Bool
        let smooth: Bool
        let reversesWheel: Bool

        init(_ application: Application) {
            inherit = application.inherit
            smooth = application.scroll.smooth
            reversesWheel = application.scroll.reversesWheel
        }
    }

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
        let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
        popUp.identifier = Identifier.inherit
        popUp.target = self
        popUp.action = #selector(choiceChanged(_:))
        for choice in ApplicationScrollingChoice.allCases {
            popUp.addItem(withTitle: NSLocalizedString(choice.titleKey, comment: ""))
            popUp.lastItem?.tag = choice.rawValue
        }
        choicePopUp = popUp
        // (The title and the lines are set by `sync`, once the row knows its width.)
        let row = PreferencesGroupRow(
            title: Self.choiceTitle(name: name),
            explanation: Self.explanation(of: .sameAsScrolling, name: name),
            accessory: popUp
        )
        choiceRow = row
        let section = PreferencesGroupSection(
            width: PreferencesGroupedForm.boxWidth(paneWidth: ApplicationDetailViewController.paneWidth),
            rows: [row]
        )
        choiceSection = section

        // Added as a child first: the settings tell their container their height as soon
        // as they load. They load with the page, also while the choice keeps them out.
        let scrolling = PreferencesScrollingViewController()
        scrolling.uiStateDefaults = uiStateDefaults
        scrolling.currentTargetApplication = application
        scrolling.onApplicationThumbWheelChange = onOwnThumbWheelChange
        scrolling.onApplicationScrollChange = { [weak self] byHand in
            self?.settingsChanged(byHand: byHand)
        }
        addChild(scrolling)
        scrollingController = scrolling
        handOnPartShowing()
        scrolling.view.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(section)
        let margin = PreferencesGroupedForm.margin
        endsUnderChoiceSection = section.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -margin)
        NSLayoutConstraint.activate([
            section.topAnchor.constraint(equalTo: root.topAnchor, constant: margin),
            section.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: margin),
            section.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -margin),
            endsUnderChoiceSection,
        ])
        view = root
        syncViewWithOptions()
    }

    /// "Scrolling in Safari".
    static func choiceTitle(name: String) -> String {
        return String(format: NSLocalizedString("apps-detail-scrolling-choice", comment: ""), name)
    }

    /// The line under the row for `choice`: "Changes under Scrolling apply to Safari too.",
    /// "Safari keeps its own settings below.", "Safari scrolls the way macOS does: not
    /// smoothed, not reversed."
    static func explanation(of choice: ApplicationScrollingChoice, name: String) -> String {
        return String(format: NSLocalizedString(choice.explanationKey, comment: ""), name)
    }

    /// The stored settings may have changed elsewhere: the part shows them (and what they
    /// say, unless Own Settings is held for what the user did here).
    func syncViewWithOptions() {
        if sync() {
            onHeightChange?()
        }
    }

    /// A change made elsewhere that shows at once, also over Own Settings held for what
    /// the user did here: an Undo or Redo, "Copy from Scrolling".
    func showStoredChoice() {
        heldOwnSettings = nil
        syncViewWithOptions()
    }

    /// Tells the settings where an Undo or Redo of their reset shows: on the Scrolling part
    /// that shows the app's entry then, with the Buttons part and the list
    /// (`onOwnThumbWheelChange`: the reset takes the app's own thumb wheel action too).
    private func handOnPartShowing() {
        let showing = partShowingNow
        scrollingController?.showUndoneResetOfApplication = { entry in
            guard let part = showing(entry) else { return }
            part.showStoredChoice()
            part.onOwnThumbWheelChange?()
        }
    }

    /// `partShowing`, or this part while it shows the entry.
    private var partShowingNow: (Application) -> ApplicationScrollingPartViewController? {
        return partShowing ?? { [weak self] entry in
            self?.application === entry ? self : nil
        }
    }

    /// Shows the stored settings; true when the settings came or went while the part is on
    /// screen (an Undo of the app's removal, a change made elsewhere): the page measures
    /// again.
    @discardableResult
    private func sync() -> Bool {
        guard isViewLoaded else { return false }
        let choice = choiceToShow()
        showName()
        choicePopUp.selectItem(withTag: choice.rawValue)
        choiceRow.explanation = Self.explanation(of: choice, name: linesName)
        let changed = choice != shownChoice
        shownChoice = choice
        let showsOwn = choice != .sameAsScrolling
        // Out of the part before they change and into it after, so that the page hears of
        // their height once, from here.
        var moved = !showsOwn && showSettings(false)
        scrollingController.syncViewWithOptions()
        scrollingController.isLeftToMacOS = choice == .leftToMacOS
        moved = (showsOwn && showSettings(true)) || moved
        if changed {
            onChoiceChange?()
        }
        return moved && view.superview != nil
    }

    /// The row's title with the app's name (a long one cut short, the whole of it in the
    /// tooltip), and room for the tallest of the three lines, so that a pick never changes
    /// the height. Again only when the name changed (an Undo of the app's removal).
    private func showName() {
        let name = application.getName()
        guard name != titledName else { return }
        titledName = name
        let title = Self.choiceTitle(name: name)
        choiceRow.title = title
        choiceRow.titleLabel.toolTip = title
        linesName = ApplicationPagePart.name(name, fittingTwoLinesOf: choiceRow.titleColumnWidth) { name in
            ApplicationScrollingChoice.allCases.map { Self.explanation(of: $0, name: name) }
        }
        choiceRow.reservedExplanations = ApplicationScrollingChoice.allCases.map { Self.explanation(of: $0, name: linesName) }
    }

    /// What the pop-up shows: what is stored says, unless Own Settings is held over it.
    private func choiceToShow() -> ApplicationScrollingChoice {
        let stored = application.scrollingChoice
        if stored == .leftToMacOS, let held = heldOwnSettings, held == ChoiceInputs(application) {
            return .ownSettings
        }
        heldOwnSettings = nil
        return stored
    }

    /// The part goes out of sight: its next showing says what is stored.
    func partWillHide() {
        heldOwnSettings = nil
    }

    /// Puts the app's own settings under the choice's box, or takes them away again: they
    /// are there except with Same as Scrolling. True when they came or went.
    private func showSettings(_ shows: Bool) -> Bool {
        guard shows != showsSettings else { return false }
        let settings = scrollingController.view
        guard shows else {
            // "Undo Reset" is not offered for settings out of sight.
            scrollingController.endUndoOffer()
            NSLayoutConstraint.deactivate(settingsConstraints)
            settingsConstraints = []
            settings.removeFromSuperview()
            endsUnderChoiceSection.isActive = true
            return true
        }
        endsUnderChoiceSection.isActive = false
        view.addSubview(settings)
        settingsConstraints = [
            // The settings bring their own margins.
            settings.topAnchor.constraint(equalTo: choiceSection.bottomAnchor),
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

    /// The app's own settings changed in the settings under the box: smoothing or the
    /// direction switched by hand (Own Settings stays while the part shows), or "Copy from
    /// Scrolling" (what it gives shows at once).
    private func settingsChanged(byHand: Bool) {
        if byHand {
            holdOwnSettingsIfLeftToMacOS()
            syncViewWithOptions()
        } else {
            showStoredChoice()
        }
    }

    /// Own Settings shows and what the user did here makes the stored values say Left to
    /// macOS: Own Settings stays while they do and the part is on screen.
    private func holdOwnSettingsIfLeftToMacOS() {
        guard shownChoice == .ownSettings, application.scrollingChoice == .leftToMacOS else { return }
        heldOwnSettings = ChoiceInputs(application)
    }

    // MARK: - A pick

    /// Where a pick registers its Undo: the window's undo manager while the page is in the
    /// window. Undo and Redo stay with the manager the pick used.
    var undoTarget: UndoManager? {
        return paneUndoManager ?? view.window?.undoManager
    }

    /// A pick in "Scrolling in Safari": writes what the move needs, as one Undo step.
    @objc func choiceChanged(_ sender: NSPopUpButton) {
        guard let choice = ApplicationScrollingChoice(rawValue: sender.selectedTag()) else { return }
        let shown = shownChoice
        heldOwnSettings = nil
        let before = ApplicationScrollingSnapshot(of: application)
        application.choose(choice, from: shown, scrolling: Options.shared.scroll, thumbWheel: Options.shared.thumbWheel)
        // Own Settings chosen over values that say Left to macOS: it stays while the part shows.
        if choice == .ownSettings, application.scrollingChoice == .leftToMacOS {
            heldOwnSettings = ChoiceInputs(application)
        }
        if ApplicationScrollingSnapshot(of: application) != before {
            Self.registerUndo(
                restoring: before, of: application, undoManager: undoTarget,
                showing: partShowingNow, list: onInheritChange
            )
        }
        // (The settings came, went or folded: the page measures again, once.)
        sync()
        onHeightChange?()
        onInheritChange?()
    }

    /// What Edit › Undo calls a pick: "Change Scrolling in Safari".
    static func undoActionName(of application: Application) -> String {
        return String(format: NSLocalizedString("apps-undo-scrolling-choice", comment: ""), application.getName())
    }

    /// Registers the step back to `snapshot` for the app's entry. The target is the
    /// settings, not this part: an Undo after the page closed still works. Undo and Redo
    /// find the entry by its path when they run (an app removed and added again is a new
    /// entry), show what they did on the part open then (`showing`) and tell the list.
    private static func registerUndo(
        restoring snapshot: ApplicationScrollingSnapshot, of application: Application, undoManager undo: UndoManager?,
        showing: @escaping (Application) -> ApplicationScrollingPartViewController?, list: (() -> Void)?
    ) {
        guard let undo else { return }
        undo.registerUndo(withTarget: Options.shared) { [weak undo] _ in
            let entry = currentEntry(of: application)
            let now = ApplicationScrollingSnapshot(of: entry)
            snapshot.apply(to: entry)
            if let part = showing(entry) {
                part.showStoredChoice()
                part.onHeightChange?()
            }
            list?()
            registerUndo(restoring: now, of: entry, undoManager: undo, showing: showing, list: list)
        }
        undo.setActionName(undoActionName(of: application))
    }

    /// The entry the list holds now for the app, or the one the pick changed when the list
    /// has none for it (nothing stores that one).
    private static func currentEntry(of application: Application) -> Application {
        return PreferencesApplicationViewController.existingApplication(
            forPaths: PreferencesApplicationViewController.knownPaths(forStoredPath: application.path)
        ) ?? application
    }
}

// MARK: - Shortcut Ring

/// "Use the general ring" and, while it is off, the app's own ring: the drawing, the freeze
/// switch and the eight rows of the Shortcut Ring pane (RingPreferencesViewController with
/// this app), which open while the app is in front. What opens the ring is a binding of
/// Buttons, or of the app's Buttons part: the first row, "Button or key", says which one
/// opens it with the app in front ("Thumb panel, as everywhere", "None in Figma",
/// `ApplicationTriggerRow`), and its button goes there ("Show in Buttons", "Show in Figma")
/// or, with none, records one that opens it only in this app ("Set Up…").
///
/// For an app with suggested shortcuts (`ShortcutRingSuggestions`) the ring the switch
/// makes starts with them, and while such an app uses the general ring and never had one
/// of its own, a line under the switch's box says that there are some, with "Use
/// Suggested Shortcuts", which does what turning the switch off does. Nothing is filled
/// without a click: the switch, that button, or the button under the own ring.
///
/// The button under the own ring is named by what it does: "Use Suggested Shortcuts" for
/// an app with a suggestion, else "Copy from Shortcut Ring". It ends the own ring, there
/// with it: the ring goes back to where it started (the suggestion, else a copy of the
/// general ring as it is now; the freeze switch the general ring's as it is now), greyed
/// while it is there; the switch stays; the window's Undo takes it back, also after the
/// page closed. A quiet line under the switch's box says how many places of the
/// suggestion the keyboard layout leaves empty, only while it leaves some.
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
        static let triggerButton = NSUserInterfaceItemIdentifier("apps-detail-ring-trigger")
        static let useSuggested = NSUserInterfaceItemIdentifier("apps-detail-ring-use-suggested")
    }

    let application: Application
    var onHeightChange: (() -> Void)?
    /// "Show in Buttons" of "Button or key": the Buttons pane, the row of what opens the
    /// ring selected. Tests replace it.
    var openButtonsPane: (() -> Void)?
    /// "Show in Figma" of "Button or key": the app's Buttons part, the row with this id
    /// selected (the page sets it).
    var showApplicationButtons: ((UUID) -> Void)?
    /// "Set Up…" of "Button or key": records a button or key at the push button that opens
    /// the ring only while the app is in front (the page sets it: the app's Buttons part
    /// records it).
    var setUpButton: ((NSView) -> Void)?
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
    /// "Button or key", the first row: what opens the ring with the app in front, and a
    /// push button that goes there.
    private(set) var triggerRow: PreferencesGroupRow!
    private(set) var triggerButton: NSButton!
    /// What the row says now, and where its button leads.
    private(set) var shownTrigger: ApplicationTriggerRow?
    /// The line under the switch's box: "Scrollio has suggested shortcuts for Figma." with
    /// "Use Suggested Shortcuts" while the app has a suggestion and uses the general ring,
    /// never having had one of its own; how many places of the suggestion the keyboard
    /// layout leaves empty, while the own ring is in use and it leaves some; else no room.
    private(set) var suggestionNote: ApplicationPageNote!
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
        // moves what is below.
        generalRing.reservedExplanations = [true, false].map { ApplicationDetailViewController.generalRingExplanation(on: $0, name: name) }
        generalRingRow = generalRing
        let trigger = PreferencesGroupedForm.makePushButton(
            title: NSLocalizedString("ring-trigger-set-up", comment: ""), target: self, action: #selector(triggerButtonClicked(_:))
        )
        trigger.identifier = Identifier.triggerButton
        ApplicationTriggerRow.limitWidth(of: trigger)
        triggerButton = trigger
        triggerRow = PreferencesGroupRow(title: NSLocalizedString("ring-trigger", comment: ""), explanation: "", accessory: trigger)
        let reset = PreferencesPaneReset(
            undoActionName: Self.resetActionName(for: application, suggested: suggestion != nil),
            title: NSLocalizedString(suggestion != nil ? "apps-ring-use-suggested" : "apps-ring-copy", comment: ""),
            undoTitle: NSLocalizedString("apps-part-undo", comment: ""),
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
            // What opens the ring first, as in the pane.
            rows: [triggerRow, generalRing]
        )
        ringSection = section
        let note = ApplicationPageNote(
            boxWidth: PreferencesGroupedForm.boxWidth(paneWidth: ApplicationDetailViewController.paneWidth),
            target: self, action: #selector(useSuggestedShortcutsClick(_:))
        )
        note.button.identifier = Identifier.useSuggested
        suggestionNote = note
        root.addSubview(section)
        root.addSubview(note)
        let margin = PreferencesGroupedForm.margin
        endsUnderRingSection = note.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -margin)
        NSLayoutConstraint.activate([
            section.topAnchor.constraint(equalTo: root.topAnchor, constant: margin),
            section.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: margin),
            section.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -margin),
            // (No room while it says nothing: the box's bottom is the note's then.)
            note.topAnchor.constraint(equalTo: section.bottomAnchor),
            note.leadingAnchor.constraint(equalTo: section.leadingAnchor),
            note.trailingAnchor.constraint(equalTo: section.trailingAnchor),
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
        let opens = ApplicationDetailViewController.RingTrigger.of(application, general: Options.shared.buttons.binding)
        let line = ApplicationDetailViewController.generalRingExplanation(on: usesGeneralRing, name: application.getName())
        var remeasures = generalRingRow.explanation != line && view.superview != nil
        generalRingRow.explanation = line
        // (What opens it here is a binding of Buttons or of the app's Buttons part.)
        let trigger = ApplicationTriggerRow.make(.shortcutRing, application: application, general: Options.shared.buttons.binding)
        shownTrigger = trigger
        ApplicationTriggerRow.show(
            trigger.buttonTitle(applicationName: application.getName(), setUpKey: "ring-trigger-set-up"), on: triggerButton
        )
        if triggerRow.explanation != trigger.text {
            remeasures = remeasures || view.superview != nil
            triggerRow.explanation = trigger.text
        }
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

    /// The quiet line, only while the keyboard layout leaves `emptyPlaces` places of the
    /// suggestion empty (their keys need Option there): for a ring that started from it "2
    /// places stay empty: …"; for one that did not, what the button would leave empty. Then
    /// also how many more the suggestion leaves empty on purpose (`emptyOnPurpose`), so
    /// that the places showing "No Action" add up. Nil: nothing new to say.
    static func suggestionNote(emptyPlaces: Int, startedFromIt: Bool, emptyOnPurpose: Int = 0) -> String? {
        guard emptyPlaces > 0 else { return nil }
        let base = startedFromIt ? "apps-ring-layout-empty" : "apps-ring-layout-would-empty"
        let key = base + (emptyPlaces == 1 ? "-one" : "-other")
        let line = String(format: NSLocalizedString(key, comment: ""), emptyPlaces)
        guard emptyOnPurpose > 0 else { return line }
        let more = emptyOnPurpose == 1
            ? NSLocalizedString("apps-detail-ring-suggested-empty-on-purpose-one", comment: "")
            : String(format: NSLocalizedString("apps-detail-ring-suggested-empty-on-purpose-other", comment: ""), emptyOnPurpose)
        return line + " " + more
    }

    /// Whether the app's own ring started from its suggested shortcuts: it was filled from
    /// them in this run of the app (the switch or "Reset to Defaults"), or it holds them
    /// now (a ring read from the settings knows only that).
    func ringStartedFromSuggestion(suggested: [ShortcutRingPlace]) -> Bool {
        guard let own = application.ownRingPlaces else { return false }
        return application.ring?.startedFromSuggestion == true || own == suggested
    }

    /// Whether the line offers the app's suggested shortcuts: the app has some, uses the
    /// general ring and never had one of its own (turning the switch off then fills them in,
    /// as the line's button does).
    var offersSuggestion: Bool {
        return suggestion != nil && application.ring == nil
    }

    /// The line under the switch's box: while `offersSuggestion`, that the app has suggested
    /// shortcuts, with "Use Suggested Shortcuts"; while the app has a suggestion and its own
    /// ring is in use, and the keyboard layout leaves places of it empty, how many (of a ring
    /// that started from it, those still empty in it: a place filled by hand is not counted;
    /// else those the button would leave empty). True when the line came, went or changed
    /// while the part is on screen (the page measures again).
    private func showSuggestion() -> Bool {
        if offersSuggestion {
            let line = String(format: NSLocalizedString("apps-ring-suggestion-offer", comment: ""), application.getName())
            return suggestionNote.show(line, buttonTitle: NSLocalizedString("apps-ring-use-suggested", comment: "")) && view.superview != nil
        }
        var line: String?
        if let suggestion, application.ownRingPlaces != nil, let suggested = suggestedPlaces() {
            let started = ringStartedFromSuggestion(suggested: suggested)
            let own = application.ownRingPlaces ?? []
            line = Self.suggestionNote(
                emptyPlaces: started ? suggestion.placesStillEmpty(in: suggested, own: own) : suggestion.placesLeftEmpty(in: suggested),
                startedFromIt: started,
                emptyOnPurpose: started ? suggestion.placesEmptyOnPurpose(own: own) : suggestion.placesEmptyOnPurpose()
            )
        }
        return suggestionNote.show(line) && view.superview != nil
    }

    // MARK: - Use Suggested Shortcuts, Copy from Shortcut Ring

    /// The undo action's name, its own, not the Shortcut Ring pane's: "Use Suggested
    /// Shortcuts in Figma", "Copy from Shortcut Ring in Calculator" (Edit › Undo says what it
    /// takes back, and the button's "Undo" never takes back the pane's reset or another
    /// app's).
    static func resetActionName(for application: Application, suggested: Bool) -> String {
        let key = suggested ? "apps-undo-use-suggested" : "apps-undo-copy-ring"
        return String(format: NSLocalizedString(key, comment: ""), application.getName())
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
            actionName: Self.resetActionName(for: application, suggested: suggestion != nil),
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
        actionName: String,
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
                fromSuggestion: before.startedFromSuggestion, actionName: actionName, undoManager: undo, showing: showing
            )
        }
        undo.setActionName(actionName)
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
                // The room the ring's own top margin always made under the box (and its line).
                body.topAnchor.constraint(equalTo: suggestionNote.bottomAnchor, constant: margin),
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
        ring.onPlaceChange = { [weak self] in
            guard let self else { return }
            self.resetToDefaults.settingsDidChange()
            // (A place filled by hand: the line counts one empty place less.)
            if self.showSuggestion() {
                self.onHeightChange?()
            }
        }
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

    /// The push button of "Button or key": where its line leads (what an Undo keeps up to
    /// date is what the row shows).
    @objc func triggerButtonClicked(_ sender: NSButton) {
        let trigger = shownTrigger
            ?? ApplicationTriggerRow.make(.shortcutRing, application: application, general: Options.shared.buttons.binding)
        switch trigger.destination {
        case .setUp:
            setUpButton?(sender)
        case .applicationButtons(let id):
            showApplicationButtons?(id)
        case .buttonsPane:
            if let openButtonsPane {
                openButtonsPane()
                return
            }
            guard let split = PreferencesButtonsViewController.splitViewController(of: self),
                  split.selectPane(withIdentifier: PANEL_IDENTIFIER.buttons),
                  let buttons = split.controller(for: PANEL_IDENTIFIER.buttons) as? PreferencesButtonsViewController else { return }
            // The row the line names.
            if let id = trigger.buttonsBindingID, buttons.selectBinding(id: id) { return }
            buttons.selectRingTrigger()
        }
    }

    /// "Use Suggested Shortcuts" beside "Scrollio has suggested shortcuts for Figma.": what
    /// turning "Use the general ring" off does for an app that never had a ring of its own,
    /// its ring filled with the suggestion.
    @objc func useSuggestedShortcutsClick(_ sender: NSButton) {
        guard offersSuggestion, application.usesGeneralRing else { return }
        application.setUsesGeneralRing(false, general: Options.shared.ring, suggested: suggestedPlaces())
        sync()
        onHeightChange?()
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
