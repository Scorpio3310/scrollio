//
//  IntroductionViewController.swift
//  Mos
//  The Welcome Guide, built in code: what Scrollio is, the one step it needs (Accessibility
//  access) and whether that step is done. The storyboard scene is only a shell.
//
//  Two states, taken from the real permission and polled while the window is open:
//  - access missing: two numbered steps, a status row, "Open Accessibility Settings" and
//    the "Having trouble?" help under it;
//  - access granted: the status row and a button that closes the window.
//
//  Created by Caldis on 15/11/2019.
//  Copyright © 2019 Caldis. All rights reserved.
//

import Cocoa

final class IntroductionViewController: NSViewController {

    enum AccessState {
        case missing
        case granted
    }

    // MARK: - Layout

    /// The window is as wide as a preferences pane and uses the type sizes of the form
    /// kit, so the two windows look like one app.
    enum Layout {
        static let width = PreferencesForm.contentWidth
        static let sideMargin: CGFloat = 32
        /// Above the icon: the content runs under the transparent title bar.
        static let topInset: CGFloat = 44
        static let bottomMargin: CGFloat = 28
        static let iconSize: CGFloat = 72
        static let cardPadding: CGFloat = 16
        static let cardWidth = width - 2 * sideMargin
        static let cardTextWidth = cardWidth - 2 * cardPadding
        static let badgeSize: CGFloat = 20
        static let badgeSpacing: CGFloat = 10
        /// Between a row's title and the small print under it.
        static let detailSpacing: CGFloat = 3
        static let primaryButtonMinWidth: CGFloat = 230
    }

    // MARK: - Seams (tests replace them: no prompt, no other app, no window)

    /// Whether macOS lets Scrollio use the Accessibility API right now.
    var isAccessGranted: () -> Bool = { Utils.isHadAccessibilityPermissions() }
    /// Asks macOS for the permission. It adds Scrollio to the Accessibility list and,
    /// when macOS decides to, shows the system prompt.
    var requestAccess: () -> Void = { Utils.requireAccessibilityPermissions() }
    /// Opens System Settings › Privacy & Security › Accessibility.
    var openAccessibilitySettings: () -> Void = IntroductionViewController.openAccessibilityPane
    /// Selects the app in Finder, so it can be dragged into the Accessibility list.
    var revealApplication: () -> Void = {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }
    /// The permission arrived while the window was open.
    var accessWasGranted: () -> Void = {
        (NSApp.delegate as? AppDelegate)?.accessibilityPermissionWasGranted()
    }
    /// Whether the menu bar icon is hidden (General › Hide Menu Bar Icon).
    var isMenuBarIconHidden: () -> Bool = { Options.shared.general.hideStatusItem }

    // MARK: - State

    private(set) var accessState: AccessState = .missing
    private(set) var isHelpExpanded = false
    /// Opened by hand (About › Welcome Guide, Help › Welcome Guide), not by the app at launch.
    private(set) var isManuallyOpened = false
    /// "Open Accessibility Settings" was used; the help opens by itself once when the user
    /// comes back and the access is still missing.
    private var didOpenSettings = false
    private var didOfferHelp = false

    /// Polls the permission while the window is open.
    private(set) var accessibilityPermissionsCheckerTimer: Timer?

    // MARK: - Views (read access for tests)

    private(set) var iconView: NSImageView!
    private(set) var titleLabel: NSTextField!
    private(set) var subtitleLabel: NSTextField!
    private(set) var accessCard: NSView!
    private(set) var accessHeadingLabel: NSTextField!
    private(set) var accessExplanationLabel: NSTextField!
    private(set) var stepLabels: [NSTextField] = []
    private(set) var stepDetailLabels: [NSTextField] = []
    private(set) var statusIconView: NSImageView!
    private(set) var statusLabel: NSTextField!
    private(set) var statusDetailLabel: NSTextField!
    private(set) var primaryButton: NSButton!
    private(set) var helpButton: NSButton!
    private(set) var helpCard: NSView!
    private(set) var helpHeadingLabel: NSTextField!
    private(set) var helpTextLabel: NSTextField!
    private(set) var showInFinderButton: NSButton!

    /// Rows of the access card that only make sense while the access is missing.
    private var stepsRows: [NSView] = []

    // MARK: - Lifecycle

    override func loadView() {
        let root = PreferencesForm.makeBackground()

        let icon = NSImageView()
        icon.image = NSImage(named: NSImage.applicationIconName)
        icon.imageScaling = .scaleProportionallyUpOrDown
        // Decoration: the title under it names the app.
        icon.setAccessibilityElement(false)
        iconView = icon

        let title = NSTextField(labelWithString: text("intro-title"))
        title.font = NSFont.systemFont(ofSize: 24, weight: .bold)
        title.alignment = .center
        titleLabel = title

        let subtitle = Self.makeText(text("intro-subtitle"), font: NSFont.systemFont(ofSize: NSFont.systemFontSize), width: Layout.cardWidth)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center
        subtitleLabel = subtitle

        let access = makeAccessCard()
        accessCard = access

        let primary = NSButton(title: "", target: self, action: #selector(primaryButtonClicked(_:)))
        primary.bezelStyle = .push
        primary.controlSize = .large
        primary.keyEquivalent = "\r"
        primaryButton = primary

        let help = PreferencesForm.makeLinkButton(
            title: text("intro-help-link"),
            target: self,
            action: #selector(helpButtonClicked(_:))
        )
        helpButton = help

        let helpContent = makeHelpCard()
        helpCard = helpContent

        let content = NSStackView(views: [icon, title, subtitle, access, primary, help, helpContent])
        content.orientation = .vertical
        content.alignment = .centerX
        content.detachesHiddenViews = true
        content.spacing = PreferencesForm.rowSpacing
        content.setCustomSpacing(14, after: icon)
        content.setCustomSpacing(6, after: title)
        content.setCustomSpacing(24, after: subtitle)
        content.setCustomSpacing(20, after: access)
        content.setCustomSpacing(12, after: primary)
        content.setCustomSpacing(14, after: help)
        content.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(content)

        // The window is sized by hand (fitWindowToContent), from the top edge down. The
        // bottom constraint stays below NSLayoutConstraint.Priority.windowSizeStayPut, so
        // Auto Layout does not resize the window as well while that change animates.
        let bottom = content.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -Layout.bottomMargin)
        bottom.priority = .defaultLow
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: Layout.width),
            content.topAnchor.constraint(equalTo: root.topAnchor, constant: Layout.topInset),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: Layout.sideMargin),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -Layout.sideMargin),
            bottom,
            icon.widthAnchor.constraint(equalToConstant: Layout.iconSize),
            icon.heightAnchor.constraint(equalToConstant: Layout.iconSize),
            access.widthAnchor.constraint(equalToConstant: Layout.cardWidth),
            helpContent.widthAnchor.constraint(equalToConstant: Layout.cardWidth),
            primary.widthAnchor.constraint(greaterThanOrEqualToConstant: Layout.primaryButtonMinWidth),
        ])

        view = root
        accessState = isAccessGranted() ? .granted : .missing
        applyState(animated: false)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshAccessState()
        startPolling()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive(_:)),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        stopPolling()
        NotificationCenter.default.removeObserver(self, name: NSApplication.didBecomeActiveNotification, object: nil)
    }

    // MARK: - Building

    private func text(_ key: String) -> String {
        return NSLocalizedString(key, comment: "")
    }

    /// A label that wraps at `width`.
    private static func makeText(_ string: String, font: NSFont, width: CGFloat) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: string)
        label.font = font
        label.isSelectable = false
        label.preferredMaxLayoutWidth = width
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private static func makeSymbolView(_ name: String, pointSize: CGFloat, weight: NSFont.Weight, tint: NSColor) -> NSImageView {
        let view = NSImageView()
        view.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        view.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        view.contentTintColor = tint
        view.imageScaling = .scaleNone
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(.required, for: .horizontal)
        return view
    }

    /// A rounded card with `rows` stacked inside, each as wide as the card's text column.
    private static func makeCard(rows: [NSView]) -> (card: IntroductionCardView, stack: NSStackView) {
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.detachesHiddenViews = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        for row in rows {
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        let card = IntroductionCardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        let padding = Layout.cardPadding
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: padding),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: padding),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -padding),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -padding),
        ])
        return (card, stack)
    }

    /// Icon or number on the left, text to its right, both starting at the top.
    private static func makeIconRow(icon: NSView, text: NSView) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(icon)
        row.addSubview(text)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            icon.widthAnchor.constraint(equalToConstant: Layout.badgeSize),
            icon.heightAnchor.constraint(equalToConstant: Layout.badgeSize),
            icon.topAnchor.constraint(equalTo: row.topAnchor),
            icon.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor),
            text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: Layout.badgeSpacing),
            text.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            // Puts the first line of 13 pt text on the middle of the 20 pt icon.
            text.topAnchor.constraint(equalTo: row.topAnchor, constant: 2),
            text.bottomAnchor.constraint(equalTo: row.bottomAnchor),
        ])
        return row
    }

    private func makeAccessCard() -> NSView {
        let rowTextWidth = Layout.cardTextWidth - Layout.badgeSize - Layout.badgeSpacing

        let heading = PreferencesForm.makeSectionHeader(text("intro-access-heading"))
        accessHeadingLabel = heading

        let explanation = Self.makeText(text("intro-access-explanation"), font: PreferencesForm.hintFont, width: Layout.cardTextWidth)
        explanation.textColor = .secondaryLabelColor
        accessExplanationLabel = explanation

        let intro = PreferencesForm.makeColumn([heading, explanation])

        // Every row of the card reads the same way: what, and under it the small print.
        func makeTitleAndDetail(_ title: String, _ detail: String, weight: NSFont.Weight) -> (NSTextField, NSTextField, NSView) {
            let titleLabel = Self.makeText(title, font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: weight), width: rowTextWidth)
            let detailLabel = Self.makeText(detail, font: PreferencesForm.hintFont, width: rowTextWidth)
            detailLabel.textColor = .secondaryLabelColor
            let column = PreferencesForm.makeColumn([titleLabel, detailLabel])
            column.spacing = Layout.detailSpacing
            return (titleLabel, detailLabel, column)
        }

        var steps: [NSView] = []
        for (index, key) in ["intro-step-open-settings", "intro-step-turn-on"].enumerated() {
            let badge = Self.makeSymbolView("\(index + 1).circle.fill", pointSize: 17, weight: .regular, tint: .controlAccentColor)
            badge.setAccessibilityElement(false)
            let (label, detail, column) = makeTitleAndDetail(text(key), text(key + "-detail"), weight: .regular)
            // VoiceOver reads the number the badge shows.
            label.setAccessibilityLabel(String(format: text("intro-step-accessibility"), index + 1, text(key)))
            stepLabels.append(label)
            stepDetailLabels.append(detail)
            steps.append(Self.makeIconRow(icon: badge, text: column))
        }

        let statusIcon = Self.makeSymbolView("circle.dashed", pointSize: 17, weight: .regular, tint: .secondaryLabelColor)
        statusIcon.setAccessibilityElement(false)
        statusIconView = statusIcon
        let (status, detail, statusColumn) = makeTitleAndDetail("", "", weight: .medium)
        statusLabel = status
        statusDetailLabel = detail
        let statusRow = Self.makeIconRow(icon: statusIcon, text: statusColumn)

        let stepsSeparator = PreferencesForm.makeSeparator()
        let statusSeparator = PreferencesForm.makeSeparator()
        stepsRows = [intro, stepsSeparator] + steps + [statusSeparator]

        let (card, _) = Self.makeCard(rows: stepsRows + [statusRow])
        return card
    }

    private func makeHelpCard() -> NSView {
        let heading = PreferencesForm.makeSectionHeader(text("intro-help-heading"))
        heading.lineBreakMode = .byWordWrapping
        heading.maximumNumberOfLines = 0
        heading.preferredMaxLayoutWidth = Layout.cardTextWidth
        helpHeadingLabel = heading

        let body = Self.makeText(text("intro-help-text"), font: PreferencesForm.hintFont, width: Layout.cardTextWidth)
        body.textColor = .secondaryLabelColor
        helpTextLabel = body

        let finder = NSButton(title: text("intro-help-finder-button"), target: self, action: #selector(showInFinderClicked(_:)))
        finder.bezelStyle = .push
        finder.translatesAutoresizingMaskIntoConstraints = false
        showInFinderButton = finder

        // The button keeps its own width: it sits in a row of its own, at the leading edge.
        let buttonRow = NSView()
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.addSubview(finder)
        NSLayoutConstraint.activate([
            finder.leadingAnchor.constraint(equalTo: buttonRow.leadingAnchor),
            finder.topAnchor.constraint(equalTo: buttonRow.topAnchor),
            finder.bottomAnchor.constraint(equalTo: buttonRow.bottomAnchor),
            finder.trailingAnchor.constraint(lessThanOrEqualTo: buttonRow.trailingAnchor),
        ])

        let (card, stack) = Self.makeCard(rows: [heading, body, buttonRow])
        stack.setCustomSpacing(PreferencesForm.hintSpacing, after: heading)
        return card
    }

    // MARK: - State

    /// The window was opened by hand: the button that closes it says "Done".
    func setManuallyOpened(_ manually: Bool) {
        isManuallyOpened = manually
        applyState(animated: false)
    }

    /// Reads the permission and shows it. Returns the state it found.
    @discardableResult
    func refreshAccessState() -> AccessState {
        let found: AccessState = isAccessGranted() ? .granted : .missing
        guard found != accessState else { return found }
        accessState = found
        applyState(animated: true)
        if found == .granted {
            accessWasGranted()
        }
        return found
    }

    /// Shows or hides the help under "Having trouble?".
    func setHelpExpanded(_ expanded: Bool, animated: Bool) {
        guard expanded != isHelpExpanded else { return }
        isHelpExpanded = expanded
        applyState(animated: animated)
    }

    private func applyState(animated: Bool) {
        guard isViewLoaded else { return }
        let granted = accessState == .granted

        for row in stepsRows {
            row.isHidden = granted
        }
        if granted {
            statusIconView.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
            statusIconView.contentTintColor = .systemGreen
            statusLabel.stringValue = text("intro-status-granted")
            statusDetailLabel.stringValue = text(
                isMenuBarIconHidden() ? "intro-status-granted-detail-hidden-icon" : "intro-status-granted-detail"
            )
            primaryButton.title = text(isManuallyOpened ? "intro-done-button" : "intro-get-started-button")
        } else {
            statusIconView.image = NSImage(systemSymbolName: "exclamationmark.circle.fill", accessibilityDescription: nil)
            statusIconView.contentTintColor = .systemOrange
            statusLabel.stringValue = text("intro-status-missing")
            statusDetailLabel.stringValue = text("intro-status-missing-detail")
            primaryButton.title = text("intro-open-settings-button")
        }

        helpButton.isHidden = granted
        helpCard.isHidden = granted || !isHelpExpanded
        helpButton.setAccessibilityExpanded(isHelpExpanded)

        fitWindowToContent(animated: animated)
    }

    /// Makes the window (or, without one, the view) as tall as the content. The top edge
    /// of the window stays where it is.
    private func fitWindowToContent(animated: Bool) {
        let size = view.fittingSize
        guard let window = view.window else {
            view.setFrameSize(size)
            return
        }
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        guard frame.size != window.frame.size else { return }
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        // Growing downwards must not push the buttons off the screen.
        if let visible = window.screen?.visibleFrame, frame.minY < visible.minY {
            frame.origin.y = min(visible.minY, visible.maxY - frame.height)
        }
        window.setFrame(frame, display: true, animate: animated && window.isVisible)
    }

    // MARK: - Polling

    private func startPolling() {
        stopPolling()
        accessibilityPermissionsCheckerTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            self?.accessibilityPermissionsChecker(timer)
        }
    }

    private func stopPolling() {
        accessibilityPermissionsCheckerTimer?.invalidate()
        accessibilityPermissionsCheckerTimer = nil
    }

    /// One tick of the poll: the status row follows the permission, both ways.
    func accessibilityPermissionsChecker(_ timer: Timer?) {
        refreshAccessState()
    }

    /// Back in Scrollio. If the user went to System Settings from here and the access is
    /// still missing, the help opens by itself, once.
    @objc func applicationDidBecomeActive(_ notification: Notification?) {
        guard refreshAccessState() == .missing, didOpenSettings, !didOfferHelp else { return }
        didOfferHelp = true
        setHelpExpanded(true, animated: true)
    }

    // MARK: - Actions

    @objc func primaryButtonClicked(_ sender: Any?) {
        switch accessState {
        case .missing:
            didOpenSettings = true
            // The request puts Scrollio into the Accessibility list; the pane shows the list.
            requestAccess()
            openAccessibilitySettings()
        case .granted:
            view.window?.close()
        }
    }

    @objc func helpButtonClicked(_ sender: Any?) {
        didOfferHelp = true
        setHelpExpanded(!isHelpExpanded, animated: true)
    }

    @objc func showInFinderClicked(_ sender: Any?) {
        revealApplication()
    }

    /// System Settings › Privacy & Security › Accessibility.
    static let accessibilityPaneURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    private static func openAccessibilityPane() {
        NSWorkspace.shared.open(accessibilityPaneURL)
    }
}

/// The rounded box behind a group of rows, like the groups of System Settings.
final class IntroductionCardView: NSView {

    static let cornerRadius: CGFloat = 10

    override func draw(_ dirtyRect: NSRect) {
        // Drawn here, not with a layer colour: system colours follow light and dark by
        // themselves when they are resolved while drawing.
        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            xRadius: Self.cornerRadius,
            yRadius: Self.cornerRadius
        )
        NSColor.quaternarySystemFill.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}
