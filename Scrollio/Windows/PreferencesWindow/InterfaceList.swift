//
//  InterfaceList.swift
//  Scrollio
//
//  The one way a list is joined inside a sentence of the window ("Back button and Forward
//  button", "Own: scrolling, 2 buttons, gestures and ring"): in the app's own language
//  (the first of its localizations in use) with the Mac's region. An English Scrollio on a
//  Mac set to Slovenian says "and", never "in"; on a Mac in Slovenia it leaves out the
//  comma before "and" as English there does, and keeps it in the United States.
//

import Foundation

enum InterfaceList {

    /// The Mac's own locale, whose region counts. Tests put another in.
    static var macLocale: () -> Locale = { Locale.current }

    /// The app's language with the Mac's region.
    static var locale: Locale {
        let language = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en").language
        return Locale(languageCode: language.languageCode, script: language.script, languageRegion: macLocale().region)
    }

    /// `items` joined as `locale` joins a list.
    static func joined(_ items: [String], locale: Locale = InterfaceList.locale) -> String {
        let formatter = ListFormatter()
        formatter.locale = locale
        return formatter.string(from: items) ?? items.joined(separator: ", ")
    }
}
