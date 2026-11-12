//
//  PreferencesScrollingContainer.swift
//  Mos
//  What holds the Scrolling settings for one app (the app's page under Apps,
//  ApplicationDetailViewController): the settings tell it when their height changed.
//

import Cocoa

protocol PreferencesScrollingContainer: AnyObject {
    /// The embedded settings loaded, or "Advanced" opened or closed: the container takes
    /// the height of its content again.
    func fitToContent()
}
