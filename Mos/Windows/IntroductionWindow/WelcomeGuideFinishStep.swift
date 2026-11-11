//
//  WelcomeGuideFinishStep.swift
//  Mos
//  The last step of the Welcome Guide: where Scrollio lives now. A drawn menu bar whose
//  Scrollio icon pulses twice and then opens its menu (the real items of the status-bar
//  menu); with Reduce Motion the menu is simply open. Open Settings and Done are the
//  container's buttons.
//

import Cocoa

final class WelcomeGuideFinishStep: WelcomeGuideStepView {

    let step = WelcomeGuideStep.finish
    let picture: NSView
    let content: NSView

    let artwork: WelcomeGuideFinishPicture
    private(set) var titleLabel: NSTextField!
    private(set) var textLabel: NSTextField!

    /// Whether the menu bar icon is hidden (General › Show in menu bar is off).
    var isMenuBarIconHidden: () -> Bool

    init(isMenuBarIconHidden: @escaping () -> Bool) {
        self.isMenuBarIconHidden = isMenuBarIconHidden
        artwork = WelcomeGuideFinishPicture(frame: NSRect(origin: .zero, size: WelcomeGuideLayout.pictureSize))
        picture = artwork
        let title = WelcomeGuideText.makeTitle(WelcomeGuideText.localized("intro-finish-title"))
        let text = WelcomeGuideText.makeText("")
        let (view, stack) = WelcomeGuideText.makeContent([title, text])
        stack.setCustomSpacing(WelcomeGuideLayout.titleToText, after: title)
        content = view
        titleLabel = title
        textLabel = text
        refresh()
    }

    func refresh() {
        textLabel.stringValue = WelcomeGuideText.localized(
            isMenuBarIconHidden() ? "intro-status-granted-detail-hidden-icon" : "intro-finish-text"
        )
    }

    func setShown(_ shown: Bool) {
        if shown { refresh() }
        artwork.setAnimating(shown)
    }
}

/// The top of a desktop: the menu bar with Scrollio's icon, and its menu under it.
final class WelcomeGuideFinishPicture: WelcomeGuideAnimatedView {

    static let loopLength: TimeInterval = 7.4
    static let menuBarHeight: CGFloat = 26
    static let iconSize = NSSize(width: 18, height: 18)
    /// The icon's place in the menu bar: among the status items on the right.
    static var iconRect: NSRect {
        return NSRect(x: 330, y: (menuBarHeight - iconSize.height) / 2, width: iconSize.width, height: iconSize.height)
    }
    static let menuWidth: CGFloat = 226
    static let menuItemHeight: CGFloat = 22
    static let menuPadding: CGFloat = 5
    static let separatorHeight: CGFloat = 9

    /// The items of the status-bar menu as it opens without a mouse battery to report: the
    /// title and its shortcut; nil is a separator.
    static var menuItems: [(title: String, shortcut: String)?] {
        return [
            (WelcomeGuideText.localized("status-menu-pause"), ""),
            (WelcomeGuideText.localized("main-menu-settings"), "⌘,"),
            nil,
            (WelcomeGuideText.localized("main-menu-quit"), "⌘Q"),
        ]
    }

    static var menuRect: NSRect {
        let height = menuItems.reduce(2 * menuPadding) { $0 + ($1 == nil ? separatorHeight : menuItemHeight) }
        let x = min(WelcomeGuideLayout.pictureSize.width - menuWidth - 8, iconRect.minX - 10)
        return NSRect(x: x, y: menuBarHeight + 4, width: menuWidth, height: height)
    }

    struct Frame: Equatable {
        /// Opacity and scale (1 = the icon's size) of the two rings.
        var rings: [CGFloat] = [0, 0]
        var ringScales: [CGFloat] = [1, 1]
        var menu: CGFloat = 0
        var menuDrop: CGFloat = 0
        var iconSelected = false
    }

    private(set) var shownFrame = Frame()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(WelcomeGuideText.localized("intro-finish-picture"))
    }

    required init?(coder: NSCoder) {
        fatalError("built in code")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    /// The mock's timings: two rings out of the icon, then the menu drops in and stays.
    static func frame(at time: TimeInterval) -> Frame {
        var loop = time.isFinite ? time.truncatingRemainder(dividingBy: loopLength) : 0
        if loop < 0 { loop += loopLength }
        var frame = Frame()
        for index in 0..<2 {
            let progress = (loop - 0.3 - Double(index) * 0.6) / 1.2
            let eased = easeOut(progress)
            frame.rings[index] = progress > 0 && progress < 1 ? CGFloat((1 - eased) * 0.9) : 0
            frame.ringScales[index] = CGFloat(1 + 1.3 * eased)
        }
        let open = easeOut((loop - 1.5) / 0.2)
        frame.menu = CGFloat(open - clamp01((loop - 7.0) / 0.25))
        frame.menuDrop = CGFloat((1 - open) * -4)
        frame.iconSelected = loop > 1.45 && loop < 7.1
        return frame
    }

    static var stillFrame: Frame {
        return Frame(menu: 1, iconSelected: true)
    }

    override func show(time: TimeInterval) {
        apply(Self.frame(at: time))
    }

    override func showStill() {
        apply(Self.stillFrame)
    }

    func apply(_ frame: Frame) {
        guard frame != shownFrame else { return }
        shownFrame = frame
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let frame = shownFrame
        let radius = WelcomeGuideLayout.pictureCornerRadius
        let card = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        card.addClip()
        NSGradient(starting: ScrollPreviewPalette.desktopStart, ending: ScrollPreviewPalette.desktopEnd)?
            .draw(in: bounds, angle: -30)

        // The menu bar: placeholders for the app's menus and the other status items.
        ScrollPreviewPalette.menuBar.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: Self.menuBarHeight).fill(using: .sourceOver)
        let ink = WelcomeGuidePalette.menuBarText
        let midY = Self.menuBarHeight / 2
        var x: CGFloat = 14
        for (index, width) in ([34, 22, 22, 26, 18] as [CGFloat]).enumerated() {
            ink.withAlphaComponent(index == 0 ? 0.85 : 0.45).setFill()
            capsule(NSRect(x: x, y: midY - (index == 0 ? 3 : 2.5), width: width, height: index == 0 ? 6 : 5)).fill()
            x += width + 14
        }
        let icon = Self.iconRect
        if frame.iconSelected {
            WelcomeGuidePalette.menuBarSelection.setFill()
            NSBezierPath(roundedRect: icon.insetBy(dx: -5, dy: -1), xRadius: 5, yRadius: 5).fill()
        }
        drawStatusIcon(in: icon, colour: ink)
        x = icon.maxX + 16
        ink.withAlphaComponent(0.55).setFill()
        for width in [22, 16, 14] as [CGFloat] {
            NSBezierPath(roundedRect: NSRect(x: x, y: midY - 5, width: width, height: 10), xRadius: 3, yRadius: 3).fill()
            x += width + 14
        }
        capsule(NSRect(x: bounds.width - 14 - 74, y: midY - 2.5, width: 74, height: 5)).fill()

        for index in 0..<2 where frame.rings[index] > 0 {
            let side = 30 * frame.ringScales[index]
            let ring = NSBezierPath(ovalIn: NSRect(x: icon.midX - side / 2, y: icon.midY - side / 2, width: side, height: side))
            ring.lineWidth = 2
            NSColor.controlAccentColor.withAlphaComponent(frame.rings[index]).setStroke()
            ring.stroke()
        }

        if frame.menu > 0 {
            drawMenu(alpha: frame.menu, drop: frame.menuDrop)
        }
        NSGraphicsContext.restoreGraphicsState()
        ScrollPreviewPalette.cardEdge.setStroke()
        card.lineWidth = 1
        card.stroke()
    }

    private func capsule(_ rect: NSRect) -> NSBezierPath {
        let radius = min(rect.width, rect.height) / 2
        return NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    }

    /// The status item's own (template) image, in the menu bar's ink.
    private func drawStatusIcon(in rect: NSRect, colour: NSColor) {
        guard let image = NSImage(named: "AppStatusBarIcon"), let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.beginTransparencyLayer(in: rect, auxiliaryInfo: nil)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        colour.setFill()
        rect.fill(using: .sourceIn)
        context.endTransparencyLayer()
        context.restoreGState()
    }

    private func drawMenu(alpha: CGFloat, drop: CGFloat) {
        let menu = Self.menuRect.offsetBy(dx: 0, dy: drop)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(alpha)
        NSGraphicsContext.current?.cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
        let path = NSBezierPath(roundedRect: menu, xRadius: 10, yRadius: 10)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowBlurRadius = 14
        shadow.shadowOffset = .zero
        shadow.set()
        WelcomeGuidePalette.menu.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
        WelcomeGuidePalette.menuEdge.setStroke()
        path.lineWidth = 0.5
        path.stroke()

        var y = menu.minY + Self.menuPadding
        let font = NSFont.menuFont(ofSize: 13)
        for item in Self.menuItems {
            guard let item else {
                WelcomeGuidePalette.hairline.setFill()
                NSRect(x: menu.minX + 14, y: y + Self.separatorHeight / 2, width: menu.width - 28, height: 1).fill(using: .sourceOver)
                y += Self.separatorHeight
                continue
            }
            let title = NSAttributedString(string: item.title, attributes: [
                .font: font, .foregroundColor: WelcomeGuidePalette.menuText,
            ])
            let size = title.size()
            title.draw(at: NSPoint(x: menu.minX + 22, y: y + (Self.menuItemHeight - size.height) / 2))
            if !item.shortcut.isEmpty {
                let shortcut = NSAttributedString(string: item.shortcut, attributes: [
                    .font: font, .foregroundColor: WelcomeGuidePalette.menuShortcut,
                ])
                let shortcutSize = shortcut.size()
                shortcut.draw(at: NSPoint(x: menu.maxX - 14 - shortcutSize.width, y: y + (Self.menuItemHeight - shortcutSize.height) / 2))
            }
            y += Self.menuItemHeight
        }
        NSGraphicsContext.current?.cgContext.endTransparencyLayer()
        NSGraphicsContext.restoreGraphicsState()
    }
}
