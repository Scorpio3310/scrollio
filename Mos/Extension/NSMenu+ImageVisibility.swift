//
//  NSMenu+ImageVisibility.swift
//  Mos
//
//  Since macOS 27 AppKit decides whether a menu item's image is shown and "will typically
//  hide images" (NSMenuItem.h). Scrollio's menus are lists of things to recognise at a
//  glance (an action and its symbol, a button and its place on the mouse, a mouse and its
//  battery), so their images are asked to stay.
//

import Cocoa

extension NSMenuItem {

    /// Asks AppKit to show this item's image whatever the system's default is.
    func keepImageVisible() {
        if #available(macOS 27.0, *) {
            preferredImageVisibility = .visible
        }
    }
}

extension NSMenu {

    /// `keepImageVisible()` for every item that has an image, in this menu and its submenus.
    func keepItemImagesVisible() {
        for item in items {
            if item.image != nil {
                item.keepImageVisible()
            }
            item.submenu?.keepItemImagesVisible()
        }
    }
}
