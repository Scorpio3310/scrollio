//
//  ScrollPreviewView.swift
//  Mos
//  STUB of the preview graphic at the top of the Scrolling tab. The real view is built on
//  another branch and replaces this file when the branches are merged. Only the API is
//  agreed: `Scene`, `scene`, `setAnimating(_:)` and `preferredHeight`. The Scrolling tab
//  uses nothing else of this file.
//
//  Until then it draws a marked placeholder that names the scene it was given.
//

import Cocoa

final class ScrollPreviewView: NSView {

    /// What the graphic points out: the plain wheel, or what one of the three keys does.
    enum Emphasis { case wheel, faster, sideways, paused }

    struct Scene: Equatable {
        /// false: the page jumps click by click.
        var smoothing = true
        /// As stored in `scroll.duration`.
        var duration = 3.67
        /// `scroll.speed`.
        var speed = 2.7
        var reversed = false
        var emphasis: Emphasis = .wheel
    }

    /// Changing it restarts the demo loop.
    var scene = Scene() {
        didSet {
            if scene != oldValue { needsDisplay = true }
        }
    }

    static let preferredHeight: CGFloat = 150

    private var isAnimating = false

    /// The tab calls it with true when it appears and false when it disappears.
    func setAnimating(_ on: Bool) {
        isAnimating = on
        needsDisplay = true
    }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: NSView.noIntrinsicMetric, height: Self.preferredHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        let frame = bounds.insetBy(dx: 0.5, dy: 0.5)
        let box = NSBezierPath(roundedRect: frame, xRadius: 10, yRadius: 10)
        NSColor.quaternaryLabelColor.withAlphaComponent(0.08).setFill()
        box.fill()
        NSColor.tertiaryLabelColor.setStroke()
        box.setLineDash([5, 4], count: 2, phase: 0)
        box.lineWidth = 1
        box.stroke()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let title = NSAttributedString(string: "Preview placeholder", attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ])
        let detail = NSAttributedString(string: Self.describe(scene), attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor,
            .paragraphStyle: paragraph,
        ])
        let titleHeight = title.size().height
        let detailHeight = detail.size().height
        let top = bounds.midY + (titleHeight + 4 + detailHeight) / 2
        title.draw(in: NSRect(x: bounds.minX, y: top - titleHeight, width: bounds.width, height: titleHeight))
        detail.draw(in: NSRect(x: bounds.minX, y: top - titleHeight - 4 - detailHeight, width: bounds.width, height: detailHeight))
    }

    private static func describe(_ scene: Scene) -> String {
        let parts = [
            scene.smoothing ? "smooth" : "stepped",
            String(format: "glide %.2f", scene.duration),
            String(format: "speed %.1f", scene.speed),
            scene.reversed ? "reversed" : "not reversed",
            "\(scene.emphasis)",
        ]
        return parts.joined(separator: " · ")
    }
}
