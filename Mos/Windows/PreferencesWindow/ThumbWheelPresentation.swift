//
//  ThumbWheelPresentation.swift
//  Mos
//  How the panes show the thumb wheel settings (ThumbWheelSettings, Options.shared.thumbWheel):
//  the name, the line and the SF Symbol of each function, the menu items that offer them,
//  the speed slider's grid and how its value is written, and the notification that tells
//  every pane showing them that they changed. The Scrolling pane (its "Thumb wheel" group)
//  and the Buttons pane (the "Thumb wheel" row of an MX Master) share it, so the two never
//  name a function differently. Display only: what a function does is the scroll engine's.
//

import Cocoa

// MARK: - The functions

extension ThumbWheelFunction {

    /// Stable name, used in string keys ("thumb-wheel-function-<name>").
    var identifierName: String {
        switch self {
        case .scroll: return "scroll"
        case .zoom: return "zoom"
        case .tabs: return "tabs"
        case .desktops: return "desktops"
        case .backForward: return "back-forward"
        case .volume: return "volume"
        }
    }

    /// "Scroll sideways", "Zoom", "Switch tabs", …
    var localizedName: String {
        return NSLocalizedString("thumb-wheel-function-\(identifierName)", comment: "")
    }

    /// What a turn does, one line: "Scrolls sideways.", "Zooms in and out.", …
    var localizedHint: String {
        return NSLocalizedString("thumb-wheel-function-\(identifierName)-hint", comment: "")
    }

    /// The SF Symbol before its name in the menus.
    var symbolName: String {
        switch self {
        case .scroll: return "arrow.left.and.right"
        case .zoom: return "plus.magnifyingglass"
        case .tabs: return "rectangle.on.rectangle"
        case .desktops: return "rectangle.split.3x1"
        case .backForward: return "chevron.left.chevron.right"
        case .volume: return "speaker.wave.2"
        }
    }

    /// The symbol as a template image (it takes the colour of the text it stands with).
    var symbolImage: NSImage? {
        return NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
    }
}

/// The texts, items and slider of the thumb wheel settings. Pure, apart from the localized
/// strings and the menu items it makes.
enum ThumbWheelPresentation {

    /// "Thumb wheel": the Scrolling pane's group and the Buttons pane's row.
    static var title: String {
        return NSLocalizedString("thumb-wheel-title", comment: "")
    }

    /// The Buttons pane shows the default function (scroll) as its other rows show a button
    /// without an action: "Default". Every other function by its name.
    static func buttonsTitle(for function: ThumbWheelFunction) -> String {
        return function == .scroll ? NSLocalizedString("buttons-default", comment: "") : function.localizedName
    }

    /// The symbol before the Buttons pane's title: none for "Default", as on the other rows.
    static func buttonsImage(for function: ThumbWheelFunction) -> NSImage? {
        return function == .scroll ? nil : function.symbolImage
    }

    /// A menu item that picks `function`: its symbol and its name (in the Buttons pane the
    /// default reads "Default", without a symbol), `function.rawValue` as its represented
    /// object. macOS 27 is asked to keep the symbol (`keepImageVisible`).
    static func menuItem(
        for function: ThumbWheelFunction,
        defaultAsDefault: Bool = false,
        target: AnyObject?,
        action: Selector?
    ) -> NSMenuItem {
        let title = defaultAsDefault ? buttonsTitle(for: function) : function.localizedName
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        item.representedObject = function.rawValue
        item.image = defaultAsDefault ? buttonsImage(for: function) : function.symbolImage
        item.toolTip = function.localizedHint
        item.keepImageVisible()
        return item
    }

    /// The function a menu item made by `menuItem` picks.
    static func function(of item: NSMenuItem?) -> ThumbWheelFunction? {
        return (item?.representedObject as? String).flatMap(ThumbWheelFunction.init(rawValue:))
    }

    // MARK: Speed

    /// The speed slider: 0.25× to 3×, a tick every quarter, values in steps of 0.05.
    static let speedSetting = ScrollSliderSetting(
        range: ThumbWheelSettings.speedRange,
        scale: .ticks(12, step: 0.05),
        decimals: 2
    )

    /// "1.25×", always two decimals ("1.00×"), in the user's locale ("1,25×"); also what
    /// VoiceOver reads as the slider's value. Display only: the stored value is not changed.
    static func speedText(_ value: Double, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = speedSetting.decimals
        formatter.maximumFractionDigits = speedSetting.maxDecimals
        let number = formatter.string(from: NSNumber(value: value)) ?? ""
        return String(format: NSLocalizedString("scrolling-speed-value", comment: ""), number)
    }

    /// What the speed means for `function`: how far a sideways scroll goes, or how little of
    /// a turn a step takes.
    static func speedHintKey(for function: ThumbWheelFunction) -> String {
        return function == .scroll ? "scrolling-thumb-wheel-speed-hint-scroll" : "scrolling-thumb-wheel-speed-hint-steps"
    }

    static let speedHintKeys = ["scrolling-thumb-wheel-speed-hint-scroll", "scrolling-thumb-wheel-speed-hint-steps"]

    /// The speed changes nothing while the wheel scrolls sideways unsmoothed: the scroll
    /// engine applies it only to a smoothed sideways scroll ("Smooth scrolling" off: let
    /// through as it comes). The other functions use it always.
    static func speedHasEffect(function: ThumbWheelFunction, smoothing: Bool) -> Bool {
        return function != .scroll || smoothing
    }
}

// MARK: - Changes

/// Tells the panes when the thumb wheel settings changed, wherever the change came from (the
/// Scrolling pane, the Buttons pane, "Reset to Defaults" and its Undo). Options keeps its
/// observers for the life of the app, and panes come and go: so Options has one observer,
/// installed the first time a pane asks, that posts a notification the panes stop
/// listening to when they go. Main thread only, delivered at once.
enum ThumbWheelSettingsChange {

    static let notification = Notification.Name("ScrollioThumbWheelSettingsDidChange")

    private static var isRelaying = false

    /// `handler` runs after every change of `Options.shared.thumbWheel`, on the main thread,
    /// before the change returns; until the returned observer is removed from the default
    /// notification center.
    static func addObserver(_ handler: @escaping () -> Void) -> NSObjectProtocol {
        startRelaying()
        return NotificationCenter.default.addObserver(forName: notification, object: nil, queue: nil) { _ in
            handler()
        }
    }

    private static func startRelaying() {
        guard !isRelaying else { return }
        isRelaying = true
        Options.shared.observe([.thumbWheel]) { _ in
            NotificationCenter.default.post(name: notification, object: nil)
        }
    }
}
