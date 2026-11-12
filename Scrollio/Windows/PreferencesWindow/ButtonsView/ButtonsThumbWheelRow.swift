//
//  ButtonsThumbWheelRow.swift
//  Mos
//  The thumb wheel's row of the Buttons pane (an MX Master 4, 3 or 3S, after the mode shift
//  button: ButtonsListLayout). It is no button and has no binding: its pull-down picks what
//  the sideways wheel does (ThumbWheelFunction, the same value as Scrolling › Thumb wheel),
//  with "Default" for scrolling sideways, as the rows of the buttons say "Default" for what
//  a button does by itself. The small picture lights the thumb wheel; the line under the
//  title says what a turn does. No recorder, no ⓘ, never removed with "−". Whoever owns the
//  row stores the choice (`onFunctionSelected`) and shows the stored value (`update`).
//

import Cocoa

// MARK: - The pull-down

/// The six functions of the thumb wheel in a pull-down as wide as the buttons' action
/// pull-downs, so the column lines up: "Default" (scrolls sideways), then the others with
/// their symbols. The one in use is ticked. Choosing one only reports it.
final class ThumbWheelPullDown: NSPopUpButton {

    /// A function was chosen (also the one already in use).
    var onFunctionSelected: ((ThumbWheelFunction) -> Void)?

    /// What the pull-down shows.
    private(set) var function: ThumbWheelFunction

    init(function: ThumbWheelFunction) {
        self.function = function
        super.init(frame: .zero, pullsDown: true)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: ButtonActionPullDown.width).isActive = true
        menu = makeMenu()
        show(function)
    }

    required init?(coder: NSCoder) {
        fatalError("ThumbWheelPullDown is built in code")
    }

    /// The items that pick a function, in the menu's order.
    var functionItems: [NSMenuItem] {
        return menu?.items.filter { ThumbWheelPresentation.function(of: $0) != nil } ?? []
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        // Item 0 is the title of a pull-down.
        menu.addItem(NSMenuItem(title: "", action: nil, keyEquivalent: ""))
        for function in ThumbWheelFunction.allCases {
            menu.addItem(ThumbWheelPresentation.menuItem(
                for: function, defaultAsDefault: true, target: self, action: #selector(functionChosen(_:))
            ))
            // "Default" stands apart from the functions that replace scrolling.
            if function == .scroll {
                menu.addItem(.separator())
            }
        }
        // macOS 27 hides menu item images unless asked: every function keeps its symbol.
        menu.keepItemImagesVisible()
        return menu
    }

    /// Shows `function` in the title and ticks its item. Sends nothing.
    func show(_ function: ThumbWheelFunction) {
        self.function = function
        guard let titleItem = menu?.items.first else { return }
        titleItem.title = ThumbWheelPresentation.buttonsTitle(for: function)
        titleItem.image = ThumbWheelPresentation.buttonsImage(for: function)
        for item in functionItems {
            item.state = ThumbWheelPresentation.function(of: item) == function ? .on : .off
        }
        synchronizeTitleAndSelectedItem()
    }

    @objc func functionChosen(_ sender: NSMenuItem) {
        guard let chosen = ThumbWheelPresentation.function(of: sender) else { return }
        show(chosen)
        onFunctionSelected?(chosen)
    }
}

// MARK: - The row

final class ButtonsThumbWheelRow: PreferencesListRow {

    static let identifier = NSUserInterfaceItemIdentifier("buttons-thumb-wheel")

    let pullDown: ThumbWheelPullDown
    /// The mouse the picture is drawn on.
    private(set) var mouse: MouseArtworkModel
    /// Whether the picture shows now is drawn for the selection, and on which mouse.
    private var shownPicture: (mouse: MouseArtworkModel, highlighted: Bool)?

    init(function: ThumbWheelFunction, mouse: MouseArtworkModel) {
        self.mouse = mouse
        let pullDown = ThumbWheelPullDown(function: function)
        pullDown.identifier = Self.identifier
        self.pullDown = pullDown
        super.init(
            id: ButtonsListLayout.thumbWheelRowID,
            title: ThumbWheelPresentation.title,
            explanation: function.localizedHint,
            icon: .image(ButtonsMouseMiniature.image(lighting: .thumbWheel, mouse: mouse, highlighted: false)),
            accessory: pullDown,
            centeredOn: pullDown,
            controls: [pullDown]
        )
        // Every function's line has room, so choosing one never changes the height.
        reservedExplanations = ThumbWheelFunction.allCases.map(\.localizedHint)
        // The thumb wheel is part of the mouse: it is never removed.
        isRemovable = false
        applyEnabled()
    }

    required init?(coder: NSCoder) {
        fatalError("ButtonsThumbWheelRow is built in code")
    }

    /// What the wheel does now.
    var function: ThumbWheelFunction {
        return pullDown.function
    }

    /// Shows `function` on `mouse`; the row and its pull-down stay the same views. Sends
    /// nothing and stores nothing.
    func update(function: ThumbWheelFunction, mouse: MouseArtworkModel) {
        if pullDown.function != function {
            pullDown.show(function)
        }
        if explanation != function.localizedHint {
            explanation = function.localizedHint
        }
        if self.mouse != mouse {
            self.mouse = mouse
            applyEnabled()
        }
    }

    /// The picture in white on the accent-coloured selection.
    override func applyEnabled() {
        super.applyEnabled()
        guard let iconView else { return }
        let wanted = (mouse: mouse, highlighted: isHighlighted)
        if let shownPicture, shownPicture == wanted { return }
        shownPicture = wanted
        iconView.image = ButtonsMouseMiniature.image(lighting: .thumbWheel, mouse: wanted.mouse, highlighted: wanted.highlighted)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        iconView?.needsDisplay = true
    }
}
