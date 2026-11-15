//
//  RingPlaceMenu.swift
//  Scrollio
//  The ring's drawing as an editor (`RingPreferencesViewController`): "Swap With", which
//  exchanges a place with one of the seven others, and "Clear". A secondary click on a drop
//  of the drawing offers the two; "Swap With" also ends every place's own menu, which is
//  how the keyboard and VoiceOver reach it (the drawing is one image to them). The submenu
//  names each place in Title Case with what its row shows, "Top Right (Copy)"; an item that
//  would change nothing to see is disabled.
//

import Cocoa

/// What "Swap With" and "Clear" offer for one place of a ring. Pure: the pane and its
/// tests share it.
struct RingPlaceMenuModel: Equatable {

    struct Item: Equatable {
        /// The place to swap with.
        let place: Int
        /// "Top Right (Copy)": the place, then what its row shows.
        let title: String
        /// Off where a swap would show nothing new: the place holds the same, or neither
        /// of the two holds anything that runs.
        let isEnabled: Bool
    }

    /// The place whose menu it is.
    let place: Int
    /// The seven other places, clockwise from the top.
    let swaps: [Item]
    /// Off for a place that holds nothing.
    let canClear: Bool

    /// The catalog keys of the places as a menu names them, clockwise from the top ("Top
    /// Right": the rows' titles are in sentence case, `ShortcutRingPlaceName`).
    static let placeKeys = [
        "ring-menu-place-top", "ring-menu-place-top-right", "ring-menu-place-right", "ring-menu-place-bottom-right",
        "ring-menu-place-bottom", "ring-menu-place-bottom-left", "ring-menu-place-left", "ring-menu-place-top-left",
    ]

    static func menuTitle(ofPlace place: Int) -> String {
        return text(placeKeys.indices.contains(place) ? placeKeys[place] : placeKeys[0])
    }

    /// What a place's row shows: the action's name (a named key combination's name without
    /// its keys); nil for a place that holds nothing.
    static func shownName(of place: ShortcutRingPlace) -> String? {
        return ActionDisplayResolver().actionName(of: place.asBinding())
    }

    /// - Parameters:
    ///   - place: the place whose menu it is.
    ///   - ring: the ring as stored, the general one or an app's own.
    ///   - name: what a place's row shows; nil reads "No Action".
    static func make(
        for place: Int, in ring: ShortcutRingSettings, name: (ShortcutRingPlace) -> String? = shownName
    ) -> RingPlaceMenuModel {
        let own = ring[place]
        let swaps = (0..<ShortcutRingSettings.placeCount).filter { $0 != place }.map { other -> Item in
            let held = ring[other]
            return Item(
                place: other,
                title: String(format: text("ring-menu-swap-item"), menuTitle(ofPlace: other), name(held) ?? text("unbound")),
                isEnabled: held != own && (held.runs || own.runs)
            )
        }
        return RingPlaceMenuModel(place: place, swaps: swaps, canClear: own.runs)
    }

    fileprivate static func text(_ key: String) -> String {
        return NSLocalizedString(key, comment: "")
    }
}

/// What an item of "Swap With" answers: the place whose menu it is in, and the one it names.
final class RingPlaceSwap: NSObject {
    let place: Int
    let other: Int

    init(place: Int, other: Int) {
        self.place = place
        self.other = other
    }
}

/// The submenu of "Swap With". Its items are made each time it is about to show
/// (`menuNeedsUpdate`: what the places hold changes between two openings, and a menu must
/// not change in `menuWillOpen`). It has no key equivalents, and says so, so that a key
/// press in the window never fills it.
final class RingSwapMenu: NSMenu, NSMenuDelegate {

    private let model: () -> RingPlaceMenuModel?
    private weak var swapTarget: AnyObject?
    private let swapAction: Selector

    init(model: @escaping () -> RingPlaceMenuModel?, target: AnyObject, action: Selector) {
        self.model = model
        swapTarget = target
        swapAction = action
        super.init(title: RingPlaceMenuModel.text("ring-menu-swap-with"))
        autoenablesItems = false
        delegate = self
    }

    required init(coder: NSCoder) {
        fatalError("RingSwapMenu is built in code")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        removeAllItems()
        guard let model = model() else { return }
        for swap in model.swaps {
            let item = NSMenuItem(title: swap.title, action: swapAction, keyEquivalent: "")
            item.target = swapTarget
            item.representedObject = RingPlaceSwap(place: model.place, other: swap.place)
            item.isEnabled = swap.isEnabled
            addItem(item)
        }
    }

    func menuHasKeyEquivalent(
        _ menu: NSMenu, for event: NSEvent, target: AutoreleasingUnsafeMutablePointer<AnyObject?>,
        action: UnsafeMutablePointer<Selector?>
    ) -> Bool {
        return false
    }
}

enum RingPlaceMenu {

    /// "Swap With" with its submenu, for the place `model` describes when the submenu is
    /// about to show. Every item of the submenu sends `action` to `target` with a
    /// `RingPlaceSwap`.
    static func swapItem(model: @escaping () -> RingPlaceMenuModel?, target: AnyObject, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: RingPlaceMenuModel.text("ring-menu-swap-with"), action: nil, keyEquivalent: "")
        item.submenu = RingSwapMenu(model: model, target: target, action: action)
        return item
    }

    /// The menu of a secondary click on a drop: "Swap With" and "Clear" (disabled on a place
    /// that holds nothing; it sends `clear` to `target`, its tag the place).
    static func make(_ model: RingPlaceMenuModel, target: AnyObject, swap: Selector, clear: Selector) -> NSMenu {
        let menu = NSMenu(title: RingPlaceMenuModel.menuTitle(ofPlace: model.place))
        menu.autoenablesItems = false
        menu.addItem(swapItem(model: { model }, target: target, action: swap))
        let clearItem = NSMenuItem(title: RingPlaceMenuModel.text("ring-menu-clear"), action: clear, keyEquivalent: "")
        clearItem.target = target
        clearItem.tag = model.place
        clearItem.isEnabled = model.canClear
        menu.addItem(clearItem)
        return menu
    }
}
