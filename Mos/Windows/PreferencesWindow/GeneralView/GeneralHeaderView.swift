//
//  GeneralHeaderView.swift
//  Mos
//  The card at the top of the General pane: on the left the app icon, on the right the
//  app's name and "Version 1.0 (1)" (what the About pane showed), with the commit and the
//  day of a stamped build. It has the look of the
//  Mouse pane's card (MouseHeaderView): the same height, corners, fill, columns and type,
//  so the two panes start alike.
//

import Cocoa

final class GeneralHeaderView: NSView {

    // The numbers of MouseHeaderView, kept here so the two cards can change apart.
    static let preferredHeight: CGFloat = 150
    static let cornerRadius: CGFloat = 10
    /// The icon is centred in this much of the card's left side; the text starts after it.
    static let iconColumnWidth: CGFloat = 170
    /// Right of the text.
    static let textTrailingInset: CGFloat = 20
    static let iconSize: CGFloat = 96

    static var nameFont: NSFont {
        return NSFont.systemFont(ofSize: 17, weight: .semibold)
    }

    static var detailFont: NSFont {
        return NSFont.systemFont(ofSize: NSFont.systemFontSize)
    }

    let iconView = NSImageView()
    let nameLabel = NSTextField(labelWithString: "")
    /// One line on what the app is for, under its name.
    let taglineLabel = NSTextField(wrappingLabelWithString: "")
    let versionLabel = NSTextField(labelWithString: "")

    init(name: String, tagline: String = "", version: String, icon: NSImage? = NSImage(named: NSImage.applicationIconName)) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        iconView.image = icon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        // Decoration: the name next to it says the same.
        iconView.setAccessibilityElement(false)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        nameLabel.stringValue = name
        nameLabel.font = Self.nameFont
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        taglineLabel.stringValue = tagline
        taglineLabel.font = Self.detailFont
        taglineLabel.textColor = .labelColor
        taglineLabel.maximumNumberOfLines = 2
        taglineLabel.isSelectable = false
        taglineLabel.isHidden = tagline.isEmpty
        taglineLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        versionLabel.stringValue = version
        versionLabel.font = Self.detailFont
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.lineBreakMode = .byTruncatingTail
        // The version can be copied into a bug report.
        versionLabel.isSelectable = true
        for label in [nameLabel, versionLabel] {
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }

        let text = NSStackView(views: [nameLabel, taglineLabel, versionLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 4
        text.translatesAutoresizingMaskIntoConstraints = false
        addSubview(text)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.preferredHeight),
            iconView.widthAnchor.constraint(equalToConstant: Self.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: Self.iconSize),
            iconView.centerXAnchor.constraint(equalTo: leadingAnchor, constant: Self.iconColumnWidth / 2),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.iconColumnWidth),
            text.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Self.textTrailingInset),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("GeneralHeaderView is built in code")
    }

    override var isFlipped: Bool { return true }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: NSView.noIntrinsicMetric, height: Self.preferredHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        let card = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            xRadius: Self.cornerRadius, yRadius: Self.cornerRadius
        )
        ScrollPreviewPalette.cardFill.setFill()
        card.fill()
        ScrollPreviewPalette.cardEdge.setStroke()
        card.lineWidth = 1
        card.stroke()
    }
}
