//
//  ButtonPlaceMenu.swift
//  Mos
//  "Which Button Is This?": a button the Mac knows only by its number ("Button 6") can be
//  said to be a part of the drawing. The menu opens from the row's picture or its context
//  menu; it lists the parts the shown mouse has by name with their pictures, the one chosen
//  ticked and the ones another row has marked, and "Not on This List" to take the answer
//  back. The answer only changes what the pane shows (`RecordedEvent.mousePart`); one the
//  shown mouse does not have is kept, listed ticked but disabled (so it is not lost by
//  accident), and shows again on a mouse that has it.
//

import Cocoa

/// What the menu offers for a numbered button. Pure: the pane and its tests share it.
struct ButtonPlaceMenuModel: Equatable {

    struct Item: Equatable {
        let part: PlacedMousePart
        /// Title Case, as menus name things.
        let title: String
        /// The row's button is said to be here.
        let isChosen: Bool
        /// Another button of the list is here already ("Used by button 5", "Already in
        /// the list"); still offered.
        let mark: String?
        /// The shown mouse has the part. Only the chosen part can be listed without it:
        /// ticked and disabled, so the stored answer shows and is not lost by accident.
        var isOnMouse = true
    }

    /// The button's number ("Button 6").
    let number: Int
    /// The mouse whose parts are offered, and whose drawing the pictures show.
    let mouse: MouseArtworkModel
    let items: [Item]

    /// The menu for `trigger` among the triggers of the list (which may hold `trigger`
    /// itself and other rows of its button) on `mouse`; nil for a trigger whose place is
    /// known or is no button.
    static func make(
        for trigger: RecordedEvent,
        among list: [RecordedEvent],
        mouse: MouseArtworkModel,
        logitechRole: (UInt16) -> LogiControlRole? = { LogiCenter.shared.controlRole(forScrollioCode: $0) }
    ) -> ButtonPlaceMenuModel? {
        guard let number = ButtonTriggerPicture.number(for: trigger) else { return nil }
        var marks: [PlacedMousePart: String] = [:]
        // The rows of the same button number are this button, with other modifiers.
        for other in list where !(other.type == .mouse && other.code == trigger.code) {
            let mark: (part: PlacedMousePart, text: String)?
            if let placed = other.placedPart, let otherNumber = ButtonTriggerPicture.number(for: other) {
                mark = (placed, String(format: text("buttons-place-used-by"), otherNumber))
            } else if let known = PlacedMousePart.known(for: other, logitechRole: logitechRole) {
                mark = (known, text("buttons-place-in-list"))
            } else {
                mark = nil
            }
            if let mark, marks[mark.part] == nil {
                marks[mark.part] = mark.text
            }
        }
        let chosen = trigger.placedPart
        // The parts of the shown mouse, and the stored answer even when the mouse lacks it.
        let items = PlacedMousePart.allCases.compactMap { part -> Item? in
            let isOnMouse = mouse.has(part.drawingPart.artworkPart)
            guard isOnMouse || part == chosen else { return nil }
            return Item(part: part, title: menuTitle(of: part), isChosen: part == chosen, mark: marks[part], isOnMouse: isOnMouse)
        }
        return ButtonPlaceMenuModel(number: number, mouse: mouse, items: items)
    }

    static func menuTitle(of part: PlacedMousePart) -> String {
        switch part {
        case .gestureButton: return text("buttons-place-gesture")
        case .thumbPanel: return text("buttons-place-thumb-panel")
        case .backButton: return text("buttons-place-back")
        case .forwardButton: return text("buttons-place-forward")
        case .modeShiftButton: return text("buttons-place-mode-shift")
        case .middleButton: return text("buttons-place-middle")
        }
    }

    fileprivate static func text(_ key: String) -> String {
        return NSLocalizedString(key, comment: "")
    }
}

/// What a menu item of "Which Button Is This?" answers: the row and the part (nil: "Not on
/// This List").
final class ButtonPlaceChoice: NSObject {
    let bindingID: UUID
    let part: PlacedMousePart?

    init(bindingID: UUID, part: PlacedMousePart?) {
        self.bindingID = bindingID
        self.part = part
    }
}

enum ButtonPlaceMenu {

    /// The menu of `model` for the row `bindingID`: a section title, each part with its
    /// picture (ticked when chosen, a mark at the end when another button has it; a chosen
    /// part the mouse does not have is disabled), then "Not on This List" with the button's
    /// number as the row shows it unplaced. Every item sends `action` to `target` with a
    /// `ButtonPlaceChoice`.
    static func make(_ model: ButtonPlaceMenuModel, bindingID: UUID, target: AnyObject, action: Selector) -> NSMenu {
        let title = ButtonPlaceMenuModel.text("buttons-place-title")
        let menu = NSMenu(title: title)
        menu.autoenablesItems = false
        menu.addItem(NSMenuItem.sectionHeader(title: title))
        for item in model.items {
            let menuItem = NSMenuItem(title: item.title, action: action, keyEquivalent: "")
            menuItem.target = target
            menuItem.representedObject = ButtonPlaceChoice(bindingID: bindingID, part: item.part)
            menuItem.image = ButtonsMouseMiniature.image(
                for: .mouse(part: item.isOnMouse ? item.part.drawingPart : nil, number: nil), mouse: model.mouse, highlighted: false
            )
            menuItem.state = item.isChosen ? .on : .off
            menuItem.isEnabled = item.isOnMouse
            if let mark = item.mark {
                menuItem.badge = NSMenuItemBadge(string: mark)
            }
            menu.addItem(menuItem)
        }
        menu.addItem(.separator())
        let none = NSMenuItem(title: ButtonPlaceMenuModel.text("buttons-place-none"), action: action, keyEquivalent: "")
        none.target = target
        none.representedObject = ButtonPlaceChoice(bindingID: bindingID, part: nil)
        none.image = ButtonsMouseMiniature.image(for: .mouse(part: nil, number: model.number), mouse: model.mouse, highlighted: false)
        menu.addItem(none)
        // macOS 27 hides menu item images unless asked: the pictures say which part an item is.
        menu.keepItemImagesVisible()
        return menu
    }
}

/// The picture of a numbered button's row as a button: a click opens "Which Button Is
/// This?". It lies over the row's picture and draws only a faint rounded background while
/// the pointer is on it or it is pressed.
final class ButtonPlacePictureButton: NSButton {

    /// The row is on the accent-coloured selection: the background is drawn light.
    var isOnSelection = false {
        didSet { if isOnSelection != oldValue { needsDisplay = true } }
    }
    /// The pointer is on it (set by tracking; renders and tests set it directly).
    var isPointerInside = false {
        didSet { if isPointerInside != oldValue { needsDisplay = true } }
    }
    private var trackingArea: NSTrackingArea?

    init() {
        super.init(frame: .zero)
        title = ""
        isBordered = false
        imagePosition = .noImage
        setButtonType(.momentaryPushIn)
        let help = NSLocalizedString("buttons-place-help", comment: "")
        toolTip = help
        setAccessibilityLabel(help)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        fatalError("ButtonPlacePictureButton is built in code")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isPointerInside = true
    }

    override func mouseExited(with event: NSEvent) {
        isPointerInside = false
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            isPointerInside = false
        }
    }

    override var isHighlighted: Bool {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isPointerInside || isHighlighted else { return }
        let alpha: CGFloat = isHighlighted ? 0.18 : 0.10
        let color = isOnSelection ? NSColor.white.withAlphaComponent(alpha * 2) : NSColor.labelColor.withAlphaComponent(alpha)
        color.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
    }
}
