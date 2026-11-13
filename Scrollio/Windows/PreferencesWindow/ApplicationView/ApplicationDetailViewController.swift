//
//  ApplicationDetailViewController.swift
//  Mos
//  The page of one app under Apps, opened from its row in the list (it replaces the old
//  per-app popover). The way back is the window's: a back button in its title bar, beside
//  the app's name (PreferencesWindowController), as in System Settings; Esc and ⌘[ go back
//  too. A box shows the app
//  (icon, name, where it is) and "Use settings from Scrolling"; under it the Scrolling
//  settings themselves, editing the app's own options (PreferencesScrollingViewController
//  with a target application: no preview, dimmed while the app uses the Scrolling settings,
//  its own "Reset to Defaults"). At the end "Shortcut Ring": the switch "Use the general
//  ring" and, while it is off, the app's own ring: the drawing and the eight rows of the
//  Shortcut Ring pane (RingPreferencesViewController with this app), which open while the
//  app is in front. What opens the ring and its freeze switch are the same for every app
//  and stay in the Shortcut Ring pane.
//
//  The page only edits the app it was opened for: `inherit` and its scroll options, and
//  its `ring`. When the switch goes off while its own options were never edited, they
//  become a copy of the Scrolling settings first; when "Use the general ring" goes off
//  for an app that never had a ring, its ring starts as a copy of the general one. The
//  Apps pane puts the page in place of the list and takes it away again.
//

import Cocoa

final class ApplicationDetailViewController: NSViewController, PreferencesScrollingContainer {

    /// Identifiers for the controls (tests and accessibility tooling).
    enum Identifier {
        static let header = NSUserInterfaceItemIdentifier("apps-detail-header")
        static let inherit = NSUserInterfaceItemIdentifier("apps-detail-inherit")
        static let generalRing = NSUserInterfaceItemIdentifier("apps-detail-general-ring")
    }

    /// As wide as the Scrolling settings under the header.
    static let paneWidth: CGFloat = PreferencesScrollingViewController.paneWidth

    let application: Application
    private let uiStateDefaults: UserDefaults

    /// Esc or ⌘[ asked to go back to the list.
    var onBack: (() -> Void)?
    /// "Use settings from Scrolling" was switched (the list says which apps have their own).
    var onInheritChange: (() -> Void)?
    /// The page's height changed: the settings loaded, "Advanced" opened or closed.
    var onHeightChange: (() -> Void)?

    // MARK: - Views (read access for tests)

    private(set) var headerRow: ApplicationDetailHeaderRow!
    private(set) var inheritRow: PreferencesSwitchRow!
    private(set) var headerSection: PreferencesGroupSection!
    private(set) var scrollingController: PreferencesScrollingViewController!
    /// "Shortcut Ring": the box with "Use the general ring".
    private(set) var ringSection: PreferencesGroupSection!
    private(set) var generalRingRow: PreferencesSwitchRow!
    /// The app's own ring, its drawing and its eight rows: there only while "Use the
    /// general ring" is off.
    private(set) var ringController: RingPreferencesViewController?
    /// The page ends under the switch's box (no own ring), or under the own ring.
    private var endsUnderRingSection: NSLayoutConstraint!
    private var ownRingConstraints: [NSLayoutConstraint] = []

    var inheritSwitch: NSSwitch { return inheritRow.toggle }
    var generalRingSwitch: NSSwitch { return generalRingRow.toggle }

    // MARK: - Lifecycle

    /// - Parameter uiStateDefaults: where "Advanced" of the Scrolling settings is remembered
    ///   (shared with the Scrolling pane); tests and screenshots give a store of their own.
    init(application: Application, uiStateDefaults: UserDefaults = .standard) {
        self.application = application
        self.uiStateDefaults = uiStateDefaults
        super.init(nibName: nil, bundle: nil)
        title = application.getName()
    }

    required init?(coder: NSCoder) {
        fatalError("ApplicationDetailViewController is built in code")
    }

    override func loadView() {
        let root = ApplicationDetailView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.onBack = { [weak self] in self?.goBack() }

        let name = application.getName()
        headerRow = ApplicationDetailHeaderRow(
            name: name,
            path: application.path,
            icon: application.getIcon()
        )
        headerRow.identifier = Identifier.header
        let inherit = PreferencesSwitchRow(
            title: text("apps-detail-inherit"),
            explanation: nil,
            target: self,
            action: #selector(inheritClick(_:))
        )
        inherit.toggle.identifier = Identifier.inherit
        // Room for the longer of the two lines, so switching never changes the height.
        inherit.reservedExplanations = [true, false].map { Self.inheritExplanation(on: $0, name: name) }
        inheritRow = inherit
        let header = PreferencesGroupSection(
            width: PreferencesGroupedForm.boxWidth(paneWidth: Self.paneWidth),
            rows: [headerRow, inherit]
        )
        headerSection = header

        // The Scrolling settings, for this app. Added as a child first: they tell their
        // container their height as soon as they load.
        let scrolling = PreferencesScrollingViewController()
        scrolling.uiStateDefaults = uiStateDefaults
        scrolling.currentTargetApplication = application
        addChild(scrolling)
        scrollingController = scrolling
        let settings = scrolling.view
        settings.translatesAutoresizingMaskIntoConstraints = false

        // The Shortcut Ring of this app: the general one, or its own.
        let generalRing = PreferencesSwitchRow(
            title: text("apps-detail-ring-general"),
            explanation: nil,
            target: self,
            action: #selector(generalRingClick(_:))
        )
        generalRing.toggle.identifier = Identifier.generalRing
        generalRing.reservedExplanations = [true, false].map { Self.generalRingExplanation(on: $0, name: name) }
        generalRingRow = generalRing
        let ring = PreferencesGroupSection(
            title: text("ring-tab-title"),
            width: PreferencesGroupedForm.boxWidth(paneWidth: Self.paneWidth),
            rows: [generalRing]
        )
        ringSection = ring

        for view in [header, settings, ring] {
            root.addSubview(view)
        }
        let margin = PreferencesGroupedForm.margin
        endsUnderRingSection = ring.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -margin)
        NSLayoutConstraint.activate([
            // The app's box begins where the first box of every pane does.
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: margin),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: margin),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -margin),
            // The settings bring their own margins: the space above their first box is the
            // space between two sections.
            settings.topAnchor.constraint(equalTo: header.bottomAnchor),
            settings.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            settings.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            // Their margin under "Reset to Defaults" is the space above the ring's title.
            ring.topAnchor.constraint(equalTo: settings.bottomAnchor),
            ring.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: margin),
            ring.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -margin),
            endsUnderRingSection,
        ])

        view = root
        syncViewWithOptions()
        root.setFrameSize(root.fittingSize)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        // The Scrolling pane may have changed what an inheriting app shows.
        syncViewWithOptions()
    }

    // MARK: - Refresh

    func syncViewWithOptions() {
        guard isViewLoaded else { return }
        inheritRow.isOn = application.inherit
        inheritRow.explanation = Self.inheritExplanation(on: application.inherit, name: application.getName())
        scrollingController.syncViewWithOptions()
        let usesGeneralRing = application.usesGeneralRing
        generalRingRow.isOn = usesGeneralRing
        generalRingRow.explanation = Self.generalRingExplanation(on: usesGeneralRing, name: application.getName())
        showOwnRing(!usesGeneralRing)
        ringController?.reload()
    }

    /// "While Safari is in front, the general ring opens." / "While Safari is in front,
    /// the ring below opens." (The app in front decides, not the one under the pointer.)
    static func generalRingExplanation(on: Bool, name: String) -> String {
        let format = NSLocalizedString(on ? "apps-detail-ring-general-on" : "apps-detail-ring-general-off", comment: "")
        return String(format: format, name)
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

    /// "Changes under Scrolling apply to Safari too." / "Safari keeps its own settings below."
    static func inheritExplanation(on: Bool, name: String) -> String {
        let format = NSLocalizedString(on ? "apps-detail-inherit-on" : "apps-detail-inherit-off", comment: "")
        return String(format: format, name)
    }

    // MARK: - PreferencesScrollingContainer

    func fitToContent() {
        guard isViewLoaded else { return }
        onHeightChange?()
    }

    // MARK: - Actions

    /// On: the app follows the Scrolling pane; its own options stay stored for later.
    /// Off: the app's own options, which start as a copy of the Scrolling settings when
    /// they were never edited (so switching off changes nothing until the user does).
    @objc func inheritClick(_ sender: NSSwitch) {
        application.setUsesScrollingSettings(sender.state == .on, scrolling: Options.shared.scroll)
        syncViewWithOptions()
        onInheritChange?()
    }

    /// On: the ring of the Shortcut Ring pane opens while the app is in front; the app's
    /// own ring stays stored for later. Off: the app's own ring, which starts as a copy of
    /// the general ring as it is now when the app never had one.
    @objc func generalRingClick(_ sender: NSSwitch) {
        application.setUsesGeneralRing(sender.state == .on, general: Options.shared.ring)
        syncViewWithOptions()
        onHeightChange?()
    }

    /// Esc, when a control of the page passes it on as a command.
    override func cancelOperation(_ sender: Any?) {
        goBack()
    }

    private func goBack() {
        onBack?()
    }

    // MARK: - Views

    private func text(_ key: String) -> String {
        return NSLocalizedString(key, comment: "")
    }

    /// Where the app is, for its header: the app bundle (not the program inside it that
    /// running apps are stored by), with `~` for the home folder.
    static func displayPath(for path: String) -> String {
        var bundlePath = path
        if let range = path.range(of: ".app/Contents/", options: .backwards) {
            bundlePath = String(path[..<path.index(range.lowerBound, offsetBy: 4)])
        }
        return (bundlePath as NSString).abbreviatingWithTildeInPath
    }

    /// The tooltip of an app's row and of its header: the name, which may be cut off, then
    /// the whole path on a second line.
    static func toolTip(name: String, path: String) -> String {
        return "\(name)\n\(path)"
    }
}

// MARK: - Header row

/// The app's row at the top of its page: its 32 pt icon, its name and where it is (one
/// line, shortened in the middle; the full name and path in the tooltip).
final class ApplicationDetailHeaderRow: PreferencesGroupRow {

    static let iconSize: CGFloat = 32
    /// Between the icon and the texts.
    static let iconSpacing: CGFloat = 10

    let iconView: NSImageView
    let path: String

    init(name: String, path: String, icon: NSImage) {
        let view = PreferencesListImageView()
        view.image = icon
        view.imageScaling = .scaleProportionallyUpOrDown
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setAccessibilityElement(false)
        iconView = view
        self.path = path
        let inset = PreferencesGroupedForm.rowHorizontalInset
        super.init(
            title: name,
            explanation: ApplicationDetailViewController.displayPath(for: path),
            leadingInset: inset + Self.iconSize + Self.iconSpacing
        )
        titleLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        explanationLabel.usesSingleLineMode = true
        explanationLabel.cell?.wraps = false
        explanationLabel.lineBreakMode = .byTruncatingMiddle
        explanationLabel.maximumNumberOfLines = 1
        toolTip = ApplicationDetailViewController.toolTip(name: name, path: path)
        explanationLabel.toolTip = toolTip

        addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            view.centerYAnchor.constraint(equalTo: centerYAnchor),
            view.widthAnchor.constraint(equalToConstant: Self.iconSize),
            view.heightAnchor.constraint(equalToConstant: Self.iconSize),
            view.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: PreferencesGroupedForm.controlMinimumInset),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("ApplicationDetailHeaderRow is built in code")
    }

    override func isAccessibilityElement() -> Bool {
        return true
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        return .group
    }

    /// The name, then where the app is.
    override func accessibilityLabel() -> String? {
        guard let explanation, !explanation.isEmpty else { return title }
        return "\(title), \(explanation)"
    }
}

// MARK: - Page view

/// The page's view. Esc (passed up from whatever has the focus on the page) and ⌘[ go back.
final class ApplicationDetailView: NSView {

    var onBack: (() -> Void)?

    /// The focus lands here when the page opens, so Esc works straight away.
    override var acceptsFirstResponder: Bool { return true }

    /// Not a stop of Tab: only the page's controls are.
    override var canBecomeKeyView: Bool { return false }

    override func keyDown(with event: NSEvent) {
        if Self.isEscape(event) {
            onBack?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if Self.isBackShortcut(event) {
            onBack?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private static func modifiers(of event: NSEvent) -> NSEvent.ModifierFlags {
        return event.modifierFlags.intersection([.command, .option, .control, .shift])
    }

    /// Esc without modifiers.
    static func isEscape(_ event: NSEvent) -> Bool {
        return event.type == .keyDown && event.keyCode == KeyCode.escape && modifiers(of: event).isEmpty
    }

    /// ⌘[, as "Back" in Finder and Safari.
    static func isBackShortcut(_ event: NSEvent) -> Bool {
        return event.type == .keyDown && modifiers(of: event) == .command && event.charactersIgnoringModifiers == "["
    }
}
