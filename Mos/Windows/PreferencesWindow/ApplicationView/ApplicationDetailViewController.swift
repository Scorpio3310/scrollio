//
//  ApplicationDetailViewController.swift
//  Mos
//  The page of one app under Apps, opened from its row in the list (it replaces the old
//  per-app popover). On top "‹ Apps" goes back (so do Esc and ⌘[). A box shows the app
//  (icon, name, where it is) and "Use settings from Scrolling"; under it the Scrolling
//  settings themselves, editing the app's own options (PreferencesScrollingViewController
//  with a target application: no preview, dimmed while the app uses the Scrolling settings,
//  its own "Reset to Defaults").
//
//  The page only edits the app it was opened for: `inherit` and its scroll options. The
//  Apps pane puts the page in place of the list and takes it away again.
//

import Cocoa

final class ApplicationDetailViewController: NSViewController, PreferencesScrollingContainer {

    /// Identifiers for the controls (tests and accessibility tooling).
    enum Identifier {
        static let back = NSUserInterfaceItemIdentifier("apps-detail-back")
        static let header = NSUserInterfaceItemIdentifier("apps-detail-header")
        static let inherit = NSUserInterfaceItemIdentifier("apps-detail-inherit")
    }

    /// As wide as the Scrolling settings under the header.
    static let paneWidth: CGFloat = PreferencesScrollingViewController.paneWidth
    /// Between the top of the page and "‹ Apps", and between it and the app's box.
    static let backButtonTop: CGFloat = 12
    static let backButtonSpacing: CGFloat = 8

    let application: Application
    private let uiStateDefaults: UserDefaults

    /// "‹ Apps", Esc or ⌘[ asked to go back to the list.
    var onBack: (() -> Void)?
    /// "Use settings from Scrolling" was switched (the list says which apps have their own).
    var onInheritChange: (() -> Void)?
    /// The page's height changed: the settings loaded, "Advanced" opened or closed.
    var onHeightChange: (() -> Void)?

    // MARK: - Views (read access for tests)

    private(set) var backButton: NSButton!
    private(set) var headerRow: ApplicationDetailHeaderRow!
    private(set) var inheritRow: PreferencesSwitchRow!
    private(set) var headerSection: PreferencesGroupSection!
    private(set) var scrollingController: PreferencesScrollingViewController!

    var inheritSwitch: NSSwitch { return inheritRow.toggle }

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

        let back = makeBackButton()
        backButton = back

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

        for view in [back, header, settings] {
            root.addSubview(view)
        }
        let margin = PreferencesGroupedForm.margin
        NSLayoutConstraint.activate([
            back.topAnchor.constraint(equalTo: root.topAnchor, constant: Self.backButtonTop),
            // The chevron lines up with the texts in the boxes.
            back.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: margin + PreferencesGroupedForm.rowHorizontalInset - 4),
            header.topAnchor.constraint(equalTo: back.bottomAnchor, constant: Self.backButtonSpacing),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: margin),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -margin),
            // The settings bring their own margins: the space above their first box is the
            // space between two sections.
            settings.topAnchor.constraint(equalTo: header.bottomAnchor),
            settings.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            settings.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            settings.bottomAnchor.constraint(equalTo: root.bottomAnchor),
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
    @objc func inheritClick(_ sender: NSSwitch) {
        let inherit = sender.state == .on
        if application.inherit != inherit {
            application.inherit = inherit
        }
        syncViewWithOptions()
        onInheritChange?()
    }

    @objc func backClick(_ sender: Any?) {
        goBack()
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

    /// "‹ Apps": borderless, in the accent colour, as a link back.
    private func makeBackButton() -> NSButton {
        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        let image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) ?? NSImage()
        let button = NSButton(title: text("apps-back"), image: image, target: self, action: #selector(backClick(_:)))
        button.identifier = Identifier.back
        button.isBordered = false
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.font = PreferencesGroupedForm.titleFont
        button.contentTintColor = .controlAccentColor
        button.setAccessibilityLabel(text("apps-back-accessibility"))
        button.toolTip = text("apps-back-accessibility")
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
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
}

// MARK: - Header row

/// The app's row at the top of its page: its 32 pt icon, its name and where it is (one
/// line, shortened in the middle; the full path in the tooltip).
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
        toolTip = path
        explanationLabel.toolTip = path

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
