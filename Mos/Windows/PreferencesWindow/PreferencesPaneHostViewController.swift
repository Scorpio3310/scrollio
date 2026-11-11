//
//  PreferencesPaneHostViewController.swift
//  Mos
//  The right side of the Preferences window: the selected pane in a column
//  `PreferencesWindowLayout.contentWidth` wide, centred when the pane is narrower, at the
//  top, scrolling when it is taller than the window. The window keeps its size.
//

import Cocoa

final class PreferencesPaneHostViewController: NSViewController {

    private(set) var scrollView: NSScrollView!
    private(set) var documentView: PreferencesPaneDocumentView!
    /// The line under the title bar, shown while the pane is scrolled (as in System Settings).
    private(set) var titlebarSeparator: NSBox!
    private(set) var currentController: NSViewController?
    private var paneConstraints: [NSLayoutConstraint] = []

    override func loadView() {
        let root = PreferencesForm.makeBackground()

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.horizontalScrollElasticity = .none
        scroll.automaticallyAdjustsContentInsets = false
        scrollView = scroll

        // The document is as wide as the visible area (it never scrolls sideways) and at
        // least as tall; it grows with a taller pane. Flipped, so the clip view is too and
        // the pane hangs from the top.
        let document = PreferencesPaneDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        documentView = document
        scroll.documentView = document
        let clip = scroll.contentView
        clip.postsBoundsChangedNotifications = true
        let fill = document.heightAnchor.constraint(equalTo: clip.heightAnchor)
        fill.priority = .defaultLow
        NSLayoutConstraint.activate([
            document.topAnchor.constraint(equalTo: clip.topAnchor),
            document.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            document.widthAnchor.constraint(equalTo: clip.widthAnchor),
            document.heightAnchor.constraint(greaterThanOrEqualTo: clip.heightAnchor),
            fill,
        ])

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.isHidden = true
        titlebarSeparator = separator

        root.addSubview(scroll)
        root.addSubview(separator)
        NSLayoutConstraint.activate([
            // Below the title bar: the pane never slides under the title.
            scroll.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: scroll.topAnchor),
        ])
        view = root

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clipViewBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: clip
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Panes

    /// Puts `controller`'s pane in the column instead of the one shown, at the top.
    func show(_ controller: NSViewController) {
        _ = view
        guard controller !== currentController else { return }
        if let old = currentController {
            NSLayoutConstraint.deactivate(paneConstraints)
            paneConstraints = []
            old.view.removeFromSuperview()
        }
        if controller.parent !== self {
            controller.removeFromParent()
            addChild(controller)
        }
        currentController = controller
        let pane = controller.view
        // The size the pane gave itself (its fitting size, or its storyboard frame). Its
        // width is kept; its height only holds where the pane's own constraints leave it
        // open (the storyboard lists), so a pane that sizes itself grows and shrinks freely.
        let size = pane.frame.size
        pane.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(pane)
        let width = pane.widthAnchor.constraint(equalToConstant: size.width)
        width.priority = .init(999)
        let height = pane.heightAnchor.constraint(equalToConstant: size.height)
        height.priority = .init(1)
        let centred = pane.centerXAnchor.constraint(equalTo: documentView.centerXAnchor)
        centred.priority = .defaultHigh
        paneConstraints = [
            pane.topAnchor.constraint(equalTo: documentView.topAnchor),
            // A legacy scroller takes its width from the right margin of a full-width pane.
            pane.leadingAnchor.constraint(greaterThanOrEqualTo: documentView.leadingAnchor),
            centred,
            documentView.bottomAnchor.constraint(greaterThanOrEqualTo: pane.bottomAnchor),
            width,
            height,
        ]
        NSLayoutConstraint.activate(paneConstraints)
        view.layoutSubtreeIfNeeded()
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        updateSeparator()
    }

    /// The pane changed its height (`PreferencesForm.fitToContent`): the column follows,
    /// the window does not.
    func paneDidChangeSize(_ controller: NSViewController) {
        guard controller === currentController else { return }
        view.layoutSubtreeIfNeeded()
        updateSeparator()
    }

    @objc private func clipViewBoundsDidChange(_ notification: Notification) {
        updateSeparator()
    }

    private func updateSeparator() {
        let scrolled = scrollView.contentView.bounds.minY > 0.5
        if titlebarSeparator.isHidden == scrolled {
            titlebarSeparator.isHidden = !scrolled
        }
    }
}

/// The scroll view's document: flipped, so the pane hangs from the top.
final class PreferencesPaneDocumentView: NSView {
    override var isFlipped: Bool {
        return true
    }
}
