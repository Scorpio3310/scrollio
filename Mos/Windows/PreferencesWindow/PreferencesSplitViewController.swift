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
    /// The sidebar, a fixed width as in System Settings.
    static let sidebarWidth: CGFloat = 200
    /// The column every pane sits in.
    static let contentWidth: CGFloat = 520
    /// A new window, before the user resizes it (the height is remembered).
    static let defaultContentHeight: CGFloat = 640
    /// Keeps every sidebar row in sight.
    static let minimumContentHeight: CGFloat = 420
    /// Name under which the window keeps its frame in the user defaults.
    static let frameAutosaveName = "PreferencesWindow"

    /// The window's content width: the sidebar and the column, side by side (a full-height
    /// sidebar draws its edge over itself). Fixed; only the height is the user's.
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
        PreferencesPane(identifier: MousePreferencesViewController.tabIdentifier, symbolName: "computermouse.fill", tileColor: Tile.gray, startsGroup: false),
        PreferencesPane(identifier: PANEL_IDENTIFIER.application, symbolName: "square.grid.2x2.fill", tileColor: Tile.indigo, startsGroup: true),
        PreferencesPane(identifier: PANEL_IDENTIFIER.general, symbolName: "gearshape.fill", tileColor: Tile.gray, startsGroup: true),
        PreferencesPane(identifier: AboutPreferencesViewController.tabIdentifier, symbolName: "info", tileColor: Tile.teal, startsGroup: false),
    ]

    /// The tile colours of System Settings.
    enum Tile {
        static let blue = NSColor(srgbRed: 0.04, green: 0.48, blue: 1.0, alpha: 1)
        static let orange = NSColor(srgbRed: 1.0, green: 0.58, blue: 0.0, alpha: 1)
        static let pink = NSColor(srgbRed: 1.0, green: 0.22, blue: 0.37, alpha: 1)
        static let gray = NSColor(srgbRed: 0.55, green: 0.55, blue: 0.58, alpha: 1)
        static let indigo = NSColor(srgbRed: 0.35, green: 0.34, blue: 0.84, alpha: 1)
        static let teal = NSColor(srgbRed: 0.19, green: 0.69, blue: 0.78, alpha: 1)
    }

    /// A new view controller for this pane, as the toolbar tabs made them: the storyboard
    /// scene of the same identifier, or the controller built in code.
    func makeController(storyboard: NSStoryboard) -> NSViewController {
        switch identifier {
        case GesturesPreferencesViewController.tabIdentifier:
            return GesturesPreferencesViewController()
        case MousePreferencesViewController.tabIdentifier:
            return MousePreferencesViewController()
        case AboutPreferencesViewController.tabIdentifier:
            return AboutPreferencesViewController()
        default:
            guard let controller = storyboard.instantiateController(withIdentifier: identifier) as? NSViewController else {
                fatalError("Main.storyboard has no pane \(identifier)")
            }
            return controller
        }
    }
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

    private let controllers: [String: NSViewController]
    private(set) var selectedPaneIdentifier: String?

    init(
        panes: [PreferencesPane] = PreferencesPane.all,
        storyboard: NSStoryboard = NSStoryboard(name: "Main", bundle: Bundle(for: PreferencesSplitViewController.self)),
        uiStateDefaults: UserDefaults? = AppRuntime.isRunningXCTest ? nil : .standard
    ) {
        self.panes = panes
        self.uiStateDefaults = uiStateDefaults
        // Every pane's controller is made up front, as the tabs were; views load on first show.
        var controllers: [String: NSViewController] = [:]
        for pane in panes {
            controllers[pane.identifier] = pane.makeController(storyboard: storyboard)
        }
        self.controllers = controllers
        self.sidebar = PreferencesSidebarViewController(panes: panes, titles: panes.map { controllers[$0.identifier]?.title ?? "" })
        self.host = PreferencesPaneHostViewController()
        super.init(nibName: nil, bundle: nil)
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

        sidebar.delegate = self
        let remembered = uiStateDefaults?.string(forKey: Self.selectedPaneDefaultsKey)
        let initial = remembered.flatMap { id in panes.contains { $0.identifier == id } ? id : nil }
            ?? Self.defaultPaneIdentifier
        show(initial, remember: false)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        updateWindowTitle()
    }

    /// Both widths are fixed: the divider does not move.
    override func splitView(_ splitView: NSSplitView, effectiveRect proposedEffectiveRect: NSRect, forDrawnRect drawnRect: NSRect, ofDividerAt dividerIndex: Int) -> NSRect {
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
        }
        sidebar.select(identifier)
        if remember {
            uiStateDefaults?.set(identifier, forKey: Self.selectedPaneDefaultsKey)
        }
    }

    /// The window is named after the pane it shows, as in System Settings; the title bar
    /// shows that name next to the sidebar.
    func updateWindowTitle() {
        guard let window = view.window, let title = selectedController?.title, !title.isEmpty else { return }
        window.title = title
    }
}
