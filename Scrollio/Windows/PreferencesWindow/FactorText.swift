//
//  FactorText.swift
//  Scrollio
//  How a factor is written next to its slider: Speed and the thumb wheel's Speed in
//  Scrolling, Swipe speed in Gestures, and the same rows on an app's page.
//

import Foundation

/// One form for every factor: one decimal, and a second only when it is not zero ("6.5×",
/// "1.0×", "10.0×", "1.25×"), never a third, with the region's decimal mark ("1,25×").
/// VoiceOver reads the same text as the slider's value.
///
/// A stored value no slider stops on is not shown as another (6.31 -> "6.31×") and is
/// rounded only at the third decimal (1.999 -> "2.0×"). Every stop of the three sliders is
/// four or five characters, so the value column keeps its width. A number with a unit
/// ("1000 DPI", "40%") and a factor inside a sentence ("5× the distance") are not written
/// here: they stay whole.
///
/// Pure, display only: no stored value is changed.
enum FactorText {
    static func string(_ value: Double, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 2
        let number = formatter.string(from: NSNumber(value: value)) ?? ""
        return String(format: NSLocalizedString("scrolling-speed-value", comment: ""), number)
    }
}
