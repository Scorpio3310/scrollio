//
//  AboutPreferencesViewController.swift
//  Mos
//  "About" preferences tab, built in code: the app icon, its name and version, one
//  credit line for the project Scrollio is based on, and a link that opens the
//  Welcome Guide again.
//

import Cocoa

final class AboutPreferencesViewController: NSViewController {

    static let tabIdentifier = "about"

    // MARK: - Layout

    private static let iconSize: CGFloat = 64
    /// The link sits in the top-left corner, above the centred column.
    private static let linkTop: CGFloat = 16
    private static let iconTop: CGFloat = 28
    private static let nameSpacing: CGFloat = 10
    private static let versionSpacing: CGFloat = 2
    private static let creditSpacing: CGFloat = 14
    private static let bottomMargin: CGFloat = 24

    // MARK: - Views (read access for tests)

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

    override func loadView() {
        let root = PreferencesForm.makeBackground()

        let link = PreferencesForm.makeLinkButton(
            title: NSLocalizedString("about-welcome-guide", comment: ""),
            target: self,
            action: #selector(welcomeGuideClicked(_:))
        )
        welcomeGuideButton = link

        let icon = NSImageView()
        icon.image = NSImage(named: NSImage.applicationIconName)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
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

        let credit = NSTextField(wrappingLabelWithString: NSLocalizedString("about-credit", comment: ""))
        credit.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        credit.textColor = .secondaryLabelColor
        credit.alignment = .center
        credit.isSelectable = false
        credit.preferredMaxLayoutWidth = PreferencesForm.contentWidth - 2 * PreferencesForm.margin
        creditLabel = credit

        for view in [link, icon, name, version, credit] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        let margin = PreferencesForm.margin
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: PreferencesForm.contentWidth),

            // A borderless button draws its title 2 pt inside its frame.
            link.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: margin - 2),
            link.topAnchor.constraint(equalTo: root.topAnchor, constant: Self.linkTop),

            icon.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            icon.topAnchor.constraint(equalTo: root.topAnchor, constant: Self.iconTop),
            icon.widthAnchor.constraint(equalToConstant: Self.iconSize),
            icon.heightAnchor.constraint(equalToConstant: Self.iconSize),

            name.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            name.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: Self.nameSpacing),

            version.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            version.topAnchor.constraint(equalTo: name.bottomAnchor, constant: Self.versionSpacing),

            credit.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            credit.topAnchor.constraint(equalTo: version.bottomAnchor, constant: Self.creditSpacing),
            credit.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: margin),
            credit.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -margin),
            credit.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -Self.bottomMargin),
        ])

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

    // MARK: - Toolbar

    /// The image the storyboard tab used.
    static func tabImage() -> NSImage? {
        let image = NSImage(named: "SF.person.crop.circle.dashed")
        image?.accessibilityDescription = NSLocalizedString("about-tab-title", comment: "")
        return image
    }
}
