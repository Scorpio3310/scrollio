//
//  NSColor+Extensions.swift
//  Mos
//  NSColor 相关的扩展方法
//  Created by Claude on 2025/10/05
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

extension NSColor {
    static let mainGreen = NSColor(calibratedRed: 0.15, green: 0.65, blue: 0.30, alpha: 1.0)
    static func getMainLightBlack(for view: NSView?) -> NSColor {
        return Utils.isDarkMode(for: view)
            ? NSColor(calibratedWhite: 0.5, alpha: 0.2)
            : NSColor(calibratedWhite: 0.0, alpha: 0.1)
    }
    static func getWarningColor(for view: NSView?) -> NSColor {
        return Utils.isDarkMode(for: view)
            ? NSColor(calibratedRed: 0.85, green: 0.25, blue: 0.20, alpha: 1.0)
            : NSColor(calibratedRed: 0.95, green: 0.35, blue: 0.30, alpha: 1.0)
    }

}

