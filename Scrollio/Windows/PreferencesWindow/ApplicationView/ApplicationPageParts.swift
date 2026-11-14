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
//  Shortcut Ring: "Use the general ring" and, while it is off, the app's own ring.
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
        hasOwnSettings: { $0.hasOwnButtons },
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
/// open while the app is in front. What opens the ring and its freeze switch are the same
/// for every app and stay in the Shortcut Ring pane.
final class ApplicationRingPartViewController: NSViewController, ApplicationPagePartController {

    enum Identifier {
        static let generalRing = NSUserInterfaceItemIdentifier("apps-detail-general-ring")
    }

    let application: Application
    var onHeightChange: (() -> Void)?

    private(set) var ringSection: PreferencesGroupSection!
    private(set) var generalRingRow: PreferencesSwitchRow!
    /// The app's own ring, its drawing and its eight rows: there only while "Use the
    /// general ring" is off.
    private(set) var ringController: RingPreferencesViewController?
    /// The part ends under the switch's box (no own ring), or under the own ring.
    private var endsUnderRingSection: NSLayoutConstraint!
    private var ownRingConstraints: [NSLayoutConstraint] = []

    init(application: Application) {
        self.application = application
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
        generalRing.reservedExplanations = [true, false].map { ApplicationDetailViewController.generalRingExplanation(on: $0, name: name) }
            + [ApplicationDetailViewController.generalRingExplanation(on: true, name: name, opens: false)]
        generalRingRow = generalRing
        // (No title: the part's segment names it.)
        let section = PreferencesGroupSection(
            width: PreferencesGroupedForm.boxWidth(paneWidth: ApplicationDetailViewController.paneWidth),
            rows: [generalRing]
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
        guard isViewLoaded else { return }
        let usesGeneralRing = application.usesGeneralRing
        generalRingRow.isOn = usesGeneralRing
        // (What opens the ring is set in the Shortcut Ring pane, and the page has no row
        // for it: without one, the line says so instead of promising a ring.)
        generalRingRow.explanation = ApplicationDetailViewController.generalRingExplanation(
            on: usesGeneralRing, name: application.getName(), opens: ShortcutRingBindingSummary.current.hasTrigger
        )
        showOwnRing(!usesGeneralRing)
        ringController?.reload()
    }

    func partWillHide() {
        ringController?.endEditing()
    }

    /// Puts the app's own ring (the drawing and the eight rows) under the switch's box, or
    /// takes it away again: it is there exactly while "Use the general ring" is off.
    private func showOwnRing(_ shows: Bool) {
        guard shows != (ringController != nil) else { return }
        if let ring = ringController {
            ring.endEditing()
            NSLayoutConstraint.deactivate(ownRingConstraints)
            ownRingConstraints = []
            ring.view.removeFromSuperview()
            ring.removeFromParent()
            ringController = nil
            endsUnderRingSection.isActive = true
            return
        }
        let ring = RingPreferencesViewController(application: application)
        addChild(ring)
        let ringView = ring.view
        ringView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(ringView)
        endsUnderRingSection.isActive = false
        // The ring's view brings its own margins, as the Scrolling settings do.
        ownRingConstraints = [
            ringView.topAnchor.constraint(equalTo: ringSection.bottomAnchor),
            ringView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            ringView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ringView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ]
        NSLayoutConstraint.activate(ownRingConstraints)
        ringController = ring
    }

    /// On: the ring of the Shortcut Ring pane opens while the app is in front; the app's
    /// own ring stays stored for later. Off: the app's own ring, which starts as a copy of
    /// the general ring as it is now when the app never had one.
    @objc func generalRingClick(_ sender: NSSwitch) {
        // First what is being edited (a name typed in a row's popover) goes into the ring,
        // while it is still the app's own.
        ringController?.endEditing()
        application.setUsesGeneralRing(sender.state == .on, general: Options.shared.ring)
        syncViewWithOptions()
        onHeightChange?()
    }
}
