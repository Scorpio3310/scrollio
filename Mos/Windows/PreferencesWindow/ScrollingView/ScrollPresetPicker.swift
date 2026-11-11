//
//  ScrollPresetPicker.swift
//  Mos
//  The preset popup: the presets, then "Custom", which is selected while the global
//  settings match no preset and changes nothing when chosen. The Scrolling tab and the
//  Presets & Fast Scrolling popover both show one, so the list, the matching and the
//  line that describes the choice live here once.
//

import Cocoa

final class ScrollPresetPicker: NSObject {

    /// Tag of the "Custom" item; presets use their index in `ScrollPreset.allCases`.
    static let customTag = -1

    let popUp: NSPopUpButton

    /// Called after every choice. `applied` is false for "Custom", which changes nothing.
    var onChoice: ((_ applied: Bool) -> Void)?

    init(identifier: NSUserInterfaceItemIdentifier) {
        popUp = NSPopUpButton(frame: .zero, pullsDown: false)
        popUp.identifier = identifier

        let menu = NSMenu()
        menu.autoenablesItems = false
        for (index, preset) in ScrollPreset.allCases.enumerated() {
            let item = NSMenuItem(title: preset.localizedName, action: nil, keyEquivalent: "")
            item.tag = index
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())
        // Selected when the values match no preset; choosing it changes nothing.
        let custom = NSMenuItem(title: ScrollPreset.customLocalizedName, action: nil, keyEquivalent: "")
        custom.tag = Self.customTag
        menu.addItem(custom)
        popUp.menu = menu

        super.init()
        popUp.target = self
        popUp.action = #selector(presetSelected(_:))
    }

    /// Selects the preset the global settings match, or "Custom", and returns the line
    /// that describes the selection.
    @discardableResult
    func sync() -> String {
        let scroll = Options.shared.scroll
        let preset = ScrollPreset.matching(scroll: scroll, tuning: Options.shared.scrollTuning)
        if let preset, let index = ScrollPreset.allCases.firstIndex(of: preset) {
            popUp.selectItem(withTag: index)
            return preset.localizedDescription
        }
        popUp.selectItem(withTag: Self.customTag)
        return scroll.smooth ? Self.customDescription : Self.smoothOffDescription
    }

    static var customDescription: String {
        NSLocalizedString("scroll-preset-custom-description", comment: "")
    }

    static var smoothOffDescription: String {
        NSLocalizedString("scroll-preset-smooth-off-description", comment: "")
    }

    /// Every text `sync()` can return.
    static var descriptionTexts: [String] {
        ScrollPreset.allCases.map { $0.localizedDescription } + [customDescription, smoothOffDescription]
    }

    @objc private func presetSelected(_ sender: NSPopUpButton) {
        let tag = sender.selectedTag()
        let applied = ScrollPreset.allCases.indices.contains(tag)
        if applied {
            ScrollPreset.allCases[tag].apply()
        }
        onChoice?(applied)
    }
}
