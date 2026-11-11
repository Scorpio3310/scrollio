//
//  AboutPreferencesViewController.swift
//  Mos
//  "About" preferences pane, built in code on the grouped kit: the app icon, its name and
//  version, a box with a button that opens the Welcome Guide again, and one credit line
//  for the project Scrollio is based on.
//

import Cocoa

final class AboutPreferencesViewController: NSViewController {

    static let tabIdentifier = "about"

    /// The column of the Preferences window.
    static let paneWidth: CGFloat = PreferencesWindowLayout.contentWidth

    // MARK: - Layout

    private static let iconSize: CGFloat = 64
    private static let nameSpacing: CGFloat = 10
    private static let versionSpacing: CGFloat = 2
    /// Between the box and the credit line under it, as close as the muted lines of Gestures.
    private static let creditSpacing: CGFloat = 10

    // MARK: - Views (read access for tests)

    private(set) var welcomeGuideRow: PreferencesGroupRow!
    private(set) var welcomeGuideButton: NSButton!
    private(set) var iconView: NSImageView!
    private(set) var nameLabel: NSTextField!
    private(set) var versionLabel: NSTextField!
    private(set) var creditLabel: NSTextField!

    /// Opens the Welcome Guide. Tests replace it, so no window is shown.
    var showWelcomeGuide: () -> Void = IntroductionWindowController.showWelcomeGuide

    // MARK: - Lifecycle

    init() {
        super.init(nibName: nil, bundle: nil)
        title = NSLocalizedString("about-tab-title", comment: "")
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        title = NSLocalizedString("about-tab-title", comment: "")
    }

    /// The app on top, centred: icon, name and version. Under it a box with the Welcome
    /// Guide, then one muted line with the credit, as the other panes of the grouped kit.
    override func loadView() {
        let root = PreferencesForm.makeBackground()
        let content = PreferencesGroupedForm.installContentStack(in: root, paneWidth: Self.paneWidth)
        content.setHuggingPriority(.defaultHigh, for: .vertical)
        let boxWidth = PreferencesGroupedForm.boxWidth(paneWidth: Self.paneWidth)

        let icon = NSImageView()
        icon.image = NSImage(named: NSImage.applicationIconName)
        icon.imageScaling = .scaleProportionallyUpOrDown
        // Decoration: the name right under it says the same.
        icon.setAccessibilityElement(false)
        iconView = icon

        let name = NSTextField(labelWithString: NSLocalizedString("about-app-name", comment: ""))
        name.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        name.alignment = .center
        nameLabel = name

        let version = NSTextField(labelWithString: Self.versionText())
        version.font = NSFont.systemFont(ofSize: 12)
        version.textColor = .secondaryLabelColor
        version.alignment = .center
        version.isSelectable = true
        versionLabel = version

        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        for view in [icon, name, version] {
            view.translatesAutoresizingMaskIntoConstraints = false
            header.addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: header.topAnchor),
            icon.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            icon.widthAnchor.constraint(equalToConstant: Self.iconSize),
            icon.heightAnchor.constraint(equalToConstant: Self.iconSize),
            name.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: Self.nameSpacing),
            name.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            version.topAnchor.constraint(equalTo: name.bottomAnchor, constant: Self.versionSpacing),
            version.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            version.bottomAnchor.constraint(equalTo: header.bottomAnchor),
        ])

        let open = PreferencesGroupedForm.makePushButton(
            title: NSLocalizedString("about-welcome-guide-open", comment: ""),
            target: self,
            action: #selector(welcomeGuideClicked(_:))
        )
        welcomeGuideButton = open
        let row = PreferencesGroupRow(
            title: NSLocalizedString("about-welcome-guide", comment: ""),
            explanation: NSLocalizedString("about-welcome-guide-hint", comment: ""),
            accessory: open
        )
        welcomeGuideRow = row
        let box = PreferencesGroupSection(width: boxWidth, rows: [row])

        let credit = NSTextField(wrappingLabelWithString: NSLocalizedString("about-credit", comment: ""))
        credit.font = PreferencesGroupedForm.explanationFont
        credit.textColor = PreferencesGroupedForm.explanationColor(enabled: true)
        credit.alignment = .center
        credit.isSelectable = false
        credit.preferredMaxLayoutWidth = boxWidth
        credit.translatesAutoresizingMaskIntoConstraints = false
        creditLabel = credit

        PreferencesGroupedForm.add([header, box, credit], to: content)
        content.setCustomSpacing(PreferencesGroupedForm.sectionSpacing, after: header)
        content.setCustomSpacing(Self.creditSpacing, after: box)

        view = root
        root.setFrameSize(root.fittingSize)
    }

    // MARK: - Content

    /// "Version 1.0", with the number the bundle was built with.
    static func versionText(bundle: Bundle = .main) -> String {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        return String(format: NSLocalizedString("about-version", comment: ""), version)
    }

    // MARK: - Actions

    @objc func welcomeGuideClicked(_ sender: NSButton) {
        showWelcomeGuide()
    }
}
