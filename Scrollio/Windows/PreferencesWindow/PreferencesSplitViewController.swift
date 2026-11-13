//
//  PreferencesSplitViewController.swift
//  Mos
//  The content of the Preferences window, laid out like System Settings: a sidebar that
//  lists the panes on the left, the selected pane on the right, its name in the title bar.
//

import Cocoa

/// Sizes of the Preferences window. Pane authors: a pane is at most `contentWidth` wide
/// (narrower panes are centred), as tall as its content (`PreferencesForm.fitToContent`
/// after a change), and scrolls when it is taller than the window.
enum PreferencesWindowLayout {
    /// The sidebar, a fixed width as in System Settings. It is what the sidebar's item is
    /// given; the column the system makes of it can be wider (macOS 26 adds 8 pt beside
    /// the floating glass), so nothing is placed by this number.
    static let sidebarWidth: CGFloat = 200
    /// The column every pane sits in.
    static let contentWidth: CGFloat = 520
    /// A new window, before the user resizes it (the height is remembered).
    static let defaultContentHeight: CGFloat = 640
    /// Keeps every sidebar row in sight.
    static let minimumContentHeight: CGFloat = 420
    /// Name under which the window keeps its frame in the user defaults.
    static let frameAutosaveName = "PreferencesWindow"

    /// Whether the pane's background runs on under the sidebar. Since macOS 26 the
    /// sidebar is a pane of glass that floats above the window's content, and the split
    /// view lets the item beside it lie under it. On older systems the sidebar draws a
    /// material of its own and the two lie side by side.
    static var paneLiesUnderSidebar: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    /// The window's content width: the sidebar and the column, side by side (a full-height
    /// sidebar draws its edge over itself), as the split view itself asks for them: 720 pt
    /// on macOS 27, 728 pt on macOS 26. Fixed; only the height is the user's.
    static func contentWidth(of splitView: NSSplitView?) -> CGFloat {
        let fitting = splitView?.fittingSize.width ?? 0
        return fitting > 0 ? fitting : sidebarWidth + contentWidth
    }

    /// A saved (or proposed) frame with the window's fixed width and at least its minimum
    /// height, kept inside the visible screen where possible. The top edge stays put.
    static func normalizedFrame(_ frame: NSRect, width: CGFloat, minimumHeight: CGFloat, visibleFrame: NSRect?) -> NSRect {
        var height = max(frame.height, minimumHeight)
        if let visible = visibleFrame {
            height = min(height, max(visible.height, minimumHeight))
        }
        var result = NSRect(x: frame.minX, y: frame.maxY - height, width: width, height: height)
        if let visible = visibleFrame {
            if result.maxY > visible.maxY { result.origin.y = visible.maxY - height }
            if result.minY < visible.minY { result.origin.y = min(visible.minY, visible.maxY - height) }
            if result.maxX > visible.maxX { result.origin.x = max(visible.minX, visible.maxX - width) }
            if result.minX < visible.minX { result.origin.x = visible.minX }
        }
        return result
    }
}

/// One pane of the Preferences window as the sidebar shows it.
struct PreferencesPane: Equatable {
    /// PANEL_IDENTIFIER, or the `tabIdentifier` of a pane built in code. Remembered as the
    /// last open pane, so it never changes.
    let identifier: String
    /// SF Symbol drawn in white on the coloured tile.
    let symbolName: String
    /// Colour of the tile, the same in light and dark (as in System Settings).
    let tileColor: NSColor
    /// A gap separates this pane from the one above it.
    let startsGroup: Bool

    /// The panes in sidebar order: what the mouse does, then the per-app rules, then the app.
    static let all: [PreferencesPane] = [
        PreferencesPane(identifier: PANEL_IDENTIFIER.scrolling, symbolName: "arrow.up.and.down", tileColor: Tile.blue, startsGroup: false),
        PreferencesPane(identifier: PANEL_IDENTIFIER.buttons, symbolName: "button.horizontal.top.press.fill", tileColor: Tile.orange, startsGroup: false),
        PreferencesPane(identifier: GesturesPreferencesViewController.tabIdentifier, symbolName: "hand.draw.fill", tileColor: Tile.pink, startsGroup: false),
        PreferencesPane(identifier: RingPreferencesViewController.tabIdentifier, symbolName: "circle.grid.cross.fill", tileColor: Tile.teal, startsGroup: false),
        PreferencesPane(identifier: MousePreferencesViewController.tabIdentifier, symbolName: "computermouse.fill", tileColor: Tile.gray, startsGroup: false),
        PreferencesPane(identifier: PANEL_IDENTIFIER.application, symbolName: "square.grid.2x2.fill", tileColor: Tile.indigo, startsGroup: true),
        PreferencesPane(identifier: PANEL_IDENTIFIER.general, symbolName: "gearshape.fill", tileColor: Tile.gray, startsGroup: true),
    ]

    /// Panes that were merged into another, by the identifier a window may still remember:
    /// About is the card on top of General now.
    static let mergedIdentifiers: [String: String] = ["about": PANEL_IDENTIFIER.general]

    /// The tile colours of System Settings.
    enum Tile {
        static let blue = NSColor(srgbRed: 0.04, green: 0.48, blue: 1.0, alpha: 1)
        static let orange = NSColor(srgbRed: 1.0, green: 0.58, blue: 0.0, alpha: 1)
        static let pink = NSColor(srgbRed: 1.0, green: 0.22, blue: 0.37, alpha: 1)
        static let teal = NSColor(srgbRed: 0.19, green: 0.69, blue: 0.78, alpha: 1)
        static let gray = NSColor(srgbRed: 0.55, green: 0.55, blue: 0.58, alpha: 1)
        static let indigo = NSColor(srgbRed: 0.35, green: 0.34, blue: 0.84, alpha: 1)
    }

    /// A new view controller for this pane, as the toolbar tabs made them: the storyboard
    /// scene of the same identifier, or the controller built in code.
    func makeController(storyboard: NSStoryboard) -> NSViewController {
        switch identifier {
        case GesturesPreferencesViewController.tabIdentifier:
            return GesturesPreferencesViewController()
        case RingPreferencesViewController.tabIdentifier:
            return RingPreferencesViewController()
        case MousePreferencesViewController.tabIdentifier:
            return MousePreferencesViewController()
        default:
            guard let controller = storyboard.instantiateController(withIdentifier: identifier) as? NSViewController else {
                fatalError("Main.storyboard has no pane \(identifier)")
            }
            return controller
        }
    }
}

/// A pane that can show a page of its own in place of its first one: Apps shows an app's
/// page in place of the list. While it does, the window is named after that page and its
/// title bar has a back button, as in System Settings.
protocol PreferencesPaneWithSubpage: AnyObject {
    /// The name of the page on show; nil while the pane shows its first page.
    var subpageTitle: String? { get }
    /// Back to the pane's first page.
    func leaveSubpage()
    /// The pane calls it when a page was opened or left.
    var onSubpageChange: (() -> Void)? { get set }
}

final class PreferencesSplitViewController: NSSplitViewController, PreferencesSidebarDelegate {

    /// UserDefaults key of the pane that was open last.
    static let selectedPaneDefaultsKey = "preferencesSelectedPane"
    /// Where a new window opens when nothing is remembered.
    static let defaultPaneIdentifier = PANEL_IDENTIFIER.scrolling

    let panes: [PreferencesPane]
    let sidebar: PreferencesSidebarViewController
    let host: PreferencesPaneHostViewController
    /// Remembers the last open pane. Nil remembers nothing: the tests run without the
    /// app's defaults.
    let uiStateDefaults: UserDefaults?
    /// `PreferencesWindowLayout.paneLiesUnderSidebar`, as this window was built.
    let paneLiesUnderSidebar: Bool

    private let controllers: [String: NSViewController]
    private(set) var selectedPaneIdentifier: String?

    init(
        panes: [PreferencesPane] = PreferencesPane.all,
        storyboard: NSStoryboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesSplitViewController.self)),
        uiStateDefaults: UserDefaults? = AppRuntime.isRunningXCTest ? nil : .standard,
        paneLiesUnderSidebar: Bool = PreferencesWindowLayout.paneLiesUnderSidebar
    ) {
        self.panes = panes
        self.uiStateDefaults = uiStateDefaults
        self.paneLiesUnderSidebar = paneLiesUnderSidebar
        // Every pane's controller is made up front, as the tabs were; views load on first show.
        var controllers: [String: NSViewController] = [:]
        for pane in panes {
            controllers[pane.identifier] = pane.makeController(storyboard: storyboard)
        }
        self.controllers = controllers
        self.sidebar = PreferencesSidebarViewController(panes: panes, titles: panes.map { controllers[$0.identifier]?.title ?? "" })
        self.host = PreferencesPaneHostViewController(liesUnderSidebar: paneLiesUnderSidebar)
        super.init(nibName: nil, bundle: nil)
        for case let pane as PreferencesPaneWithSubpage in controllers.values {
            pane.onSubpageChange = { [weak self] in self?.updateWindowTitle() }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("PreferencesSplitViewController is built in code")
    }

    /// The view controller of the pane `identifier`, nil when there is no such pane.
    func controller(for identifier: String) -> NSViewController? {
        return controllers[identifier]
    }

    /// The controller of the pane on show.
    var selectedController: NSViewController? {
        return selectedPaneIdentifier.flatMap { controllers[$0] }
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        splitView.dividerStyle = .thin

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.canCollapse = false
        sidebarItem.minimumThickness = PreferencesWindowLayout.sidebarWidth
        sidebarItem.maximumThickness = PreferencesWindowLayout.sidebarWidth
        addSplitViewItem(sidebarItem)

        let contentItem = NSSplitViewItem(viewController: host)
        contentItem.minimumThickness = PreferencesWindowLayout.contentWidth
        contentItem.maximumThickness = PreferencesWindowLayout.contentWidth
        addSplitViewItem(contentItem)

        if #available(macOS 26.0, *), paneLiesUnderSidebar {
            extendPaneUnderSidebar(contentItem)
        }

        sidebar.delegate = self
        let remembered = uiStateDefaults?.string(forKey: Self.selectedPaneDefaultsKey)
        show(Self.initialPaneIdentifier(remembered: remembered, panes: panes), remember: false)
    }

    /// Lets the pane's item lie under the sidebar, so the window has one background.
    ///
    /// Since macOS 26 the sidebar is a pane of glass that floats above whatever lies under
    /// it. Beside a pane that draws a material of its own, only the window's plain
    /// background lay under it: the sidebar came out almost white next to the translucent
    /// grey of the pane. AppKit's answer is `automaticallyAdjustsSafeAreaInsets` on the
    /// item beside the sidebar: the split view extends that item's frame beneath the
    /// sidebar and tells it, as a safe area, which part is left free. The pane host's
    /// background then fills the window from edge to edge, and its column keeps to the
    /// safe area (`PreferencesPaneHostViewController`). The item's thickness still counts
    /// the free part only, so the window is as wide as before.
    ///
    /// Nothing here knows how wide the sidebar's column is. That is the system's to say:
    /// macOS 27 makes it as wide as the sidebar item (200 pt), macOS 26 sets the glass
    /// 8 pt in from the window's edge and starts the pane at 208 pt. 1.0.1 put a material
    /// of its own under the sidebar, 200 pt wide, and on macOS 26 those 8 pt showed the
    /// window's background: a line from the top of the window to its bottom.
    @available(macOS 26.0, *)
    private func extendPaneUnderSidebar(_ contentItem: NSSplitViewItem) {
        contentItem.automaticallyAdjustsSafeAreaInsets = true
    }

    /// Where a new window opens: the pane that was open last, the pane it was merged into,
    /// or the default when it is gone. What is remembered is not rewritten.
    static func initialPaneIdentifier(remembered: String?, panes: [PreferencesPane]) -> String {
        guard let remembered else { return defaultPaneIdentifier }
        let identifier = PreferencesPane.mergedIdentifiers[remembered] ?? remembered
        return panes.contains { $0.identifier == identifier } ? identifier : defaultPaneIdentifier
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        updateWindowTitle()
    }

    /// Both widths are fixed: the divider does not move, and the pointer does not offer to
    /// move it. The split view controller is its split view's delegate, and an override
    /// of a delegate method must call `super` (NSSplitViewController's documentation);
    /// its answer is not used.
    override func splitView(_ splitView: NSSplitView, effectiveRect proposedEffectiveRect: NSRect, forDrawnRect drawnRect: NSRect, ofDividerAt dividerIndex: Int) -> NSRect {
        _ = super.splitView(splitView, effectiveRect: proposedEffectiveRect, forDrawnRect: drawnRect, ofDividerAt: dividerIndex)
        return .zero
    }

    // MARK: - Selection

    /// Shows the pane `identifier` (PANEL_IDENTIFIER, or the `tabIdentifier` of a pane built
    /// in code) and selects its sidebar row. False when there is no such pane.
    @discardableResult
    func selectPane(withIdentifier identifier: String) -> Bool {
        guard controllers[identifier] != nil else { return false }
        _ = view
        show(identifier, remember: true)
        return true
    }

    func sidebar(_ sidebar: PreferencesSidebarViewController, didSelect identifier: String) {
        show(identifier, remember: true)
    }

    private func show(_ identifier: String, remember: Bool) {
        guard let controller = controllers[identifier] else { return }
        if selectedPaneIdentifier != identifier {
            selectedPaneIdentifier = identifier
            host.show(controller)
            updateWindowTitle()
            keepKeyboardFocus()
        } else {
            // Asked for the pane on show (a way to General while General is open): its top,
            // as when it is shown anew.
            host.scrollToTop()
        }
        sidebar.select(identifier)
        if remember {
            uiStateDefaults?.set(identifier, forKey: Self.selectedPaneDefaultsKey)
        }
    }

    /// A button inside a pane that switches panes ("Open Mouse", "Set Up…") goes away with
    /// its pane, and the window takes the focus: Tab would start over. The sidebar list gets
    /// it, as when the window opens, so Tab goes on into the new pane.
    private func keepKeyboardFocus() {
        guard let window = view.window, window.firstResponder === window || window.firstResponder == nil else { return }
        window.makeFirstResponder(sidebar.tableView)
    }

    /// The page of the pane on show that one goes back from (an app's page under Apps);
    /// nil while the pane shows its first page. Another pane's open page does not count:
    /// the sidebar leaves it.
    private var subpagePane: PreferencesPaneWithSubpage? {
        guard let pane = selectedController as? PreferencesPaneWithSubpage, pane.subpageTitle != nil else { return nil }
        return pane
    }

    /// Whether the window's title bar offers the way back.
    var canGoBack: Bool {
        return subpagePane != nil
    }

    /// The back button of the title bar: back to the pane's first page.
    func goBack() {
        subpagePane?.leaveSubpage()
    }

    /// Called when the pane on show, or the page inside it, changed: the window's toolbar
    /// follows (`PreferencesWindowController.syncBackItem`).
    var onNavigationChange: (() -> Void)?

    /// The window is named after the pane it shows, as in System Settings, or after the
    /// page open inside that pane (an app's name); the title bar shows that name next to
    /// the sidebar, after the back button when there is one.
    func updateWindowTitle() {
        guard isViewLoaded, let window = view.window else { return }
        if let title = subpagePane?.subpageTitle ?? selectedController?.title, !title.isEmpty {
            window.title = title
        }
        onNavigationChange?()
    }
}
