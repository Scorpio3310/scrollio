//
//  Application.swift
//  Mos
//  应用程序对象
//  Created by Caldis on 2018/2/20.
//  Copyright © 2018年 Caldis. All rights reserved.
//

import Cocoa

class Application: Codable, Equatable {
    
    // 基础
    var path: String // executablePath or bundlePath
    // 配置: 名称
    var displayName: String? = "" {
        didSet { Options.shared.markChanged(.application) }
    }
    // 配置: 继承
    var inherit = true {
        didSet { Options.shared.markChanged(.application) }
    }
    // 配置: 滚动
    var scroll = OPTIONS_SCROLL_DEFAULT() {
        didSet { Options.shared.markChanged(.application) }
    }
    // The app's own buttons, only those that differ from Buttons (`ApplicationButtons.swift`).
    // Nil: none; nothing is stored for it then.
    var buttons: OPTIONS_BUTTONS_DEFAULT? {
        didSet { Options.shared.markChanged(.application) }
    }
    // The app's own Shortcut Ring and its "Use the general ring" (`ApplicationRing.swift`).
    // Nil: the app never had a ring of its own and uses the general one; nothing is
    // stored for it then, so an entry from before stays as it was.
    var ring: ApplicationRing? {
        didSet { Options.shared.markChanged(.application) }
    }
    // The app's own gestures and its "Use the general gestures" (`ApplicationGestures.swift`).
    // Nil: the app never had gestures of its own and uses the general ones; nothing is
    // stored for it then, so an entry from before stays as it was.
    var gestures: ApplicationGestures? {
        didSet { Options.shared.markChanged(.application) }
    }
    // The thumb wheel's function of the app's own (`ApplicationThumbWheel.swift`). Nil: the
    // general one; nothing is stored for it then, so an entry from before stays as it was.
    var thumbWheel: ApplicationThumbWheel? {
        didSet { Options.shared.markChanged(.application) }
    }
    // 初始化
    init(path: String) {
        self.path = path
        // A new entry's own options are those of a new installation on this Mac: never
        // edited (`adoptScrollOptionsIfUnedited`).
        self.scroll = .installationDefaults()
    }
    
    // Codable
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // 基础
        path = try container.decodeIfPresent(String.self, forKey: .path) ?? ""
        // 名称
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        // 继承
        inherit = try container.decodeIfPresent(Bool.self, forKey: .inherit) ?? true
        // 滚动
        scroll = try container.decodeIfPresent(OPTIONS_SCROLL_DEFAULT.self, forKey: .scroll) ?? .installationDefaults()
        // One-time migration: settings stored while "Trackpad-style events" locked Duration get
        // the Duration from before the lock back. The remembered value is not kept in the model,
        // so the next save drops it.
        if let legacy = try? container.decodeIfPresent(OPTIONS_SCROLL_DEFAULT.LegacySimTrackpadLock.self, forKey: .scroll) {
            scroll.restoreDuration(from: legacy)
        }
        // The app's own buttons: a value that cannot be read is none, and does not take the
        // app's entry with it.
        buttons = Self.readOwnButtons(from: container, forKey: .buttons)
        // A ring that cannot be read does not take the app's entry with it: the app then
        // uses the general ring.
        ring = (try? container.decodeIfPresent(ApplicationRing.self, forKey: .ring)) ?? nil
        // Gestures that cannot be read do not take the app's entry with them either: the app
        // then uses the general gestures.
        gestures = (try? container.decodeIfPresent(ApplicationGestures.self, forKey: .gestures)) ?? nil
        // Nor does a thumb wheel that cannot be read: the app then turns it as Buttons says.
        thumbWheel = (try? container.decodeIfPresent(ApplicationThumbWheel.self, forKey: .thumbWheel)) ?? nil
    }
    
    // Equatable
    static func == (a: Application, b: Application) -> Bool {
        return a.path == b.path
    }
}

/**
 * 工具函数
 */
extension Application {
    // 基本信息
    func getIcon() -> NSImage {
        return Utils.getApplicationIcon(fromPath: path)
    }
    func getName() -> String {
        if let name = displayName, name.count > 0 {
            return name
        }
        return Utils.getApplicationName(fromPath: path)
    }
    // 配置
    func getStep() -> Double {
        return inherit ? Options.shared.scroll.step : scroll.step
    }
    func getSpeed() -> Double {
        return inherit ? Options.shared.scroll.speed : scroll.speed
    }
    func getDuration() -> Double {
        return inherit ? Options.shared.scroll.durationTransition : scroll.durationTransition
    }
    // 功能
    // inherit=on 时 resolvedScrollOptions() 即全局配置, 结果与全局路径一致;
    // inherit=off 时完全使用应用自身配置, 不再受全局开关联动 (见 #1011)
    func isSmooth(_ block: Bool) -> Bool {
        if block { return false }
        return resolvedScrollOptions().smooth
    }
    func isReverseVertical() -> Bool {
        let target = resolvedScrollOptions()
        return target.reverse && target.reverseVertical
    }
    func isReverseHorizontal() -> Bool {
        let target = resolvedScrollOptions()
        return target.reverse && target.reverseHorizontal
    }
    func isSmoothVertical(_ block: Bool) -> Bool {
        if block { return false }
        let target = resolvedScrollOptions()
        return target.smooth && target.smoothVertical
    }
    func isSmoothHorizontal(_ block: Bool) -> Bool {
        if block { return false }
        let target = resolvedScrollOptions()
        return target.smooth && target.smoothHorizontal
    }
}

// MARK: - Own settings from the Scrolling settings

extension Application {
    /// Before "Use settings from Scrolling" is switched off: scroll options of the app's
    /// own that were never edited (`scrollOptionsWereNeverEdited`) become a copy of
    /// `global`, so the app scrolls on as it did until the user changes something. Options
    /// that were edited are kept. Returns whether they were copied. The app keeps its own
    /// container: only its values change, stored as before.
    @discardableResult
    func adoptScrollOptionsIfUnedited(from global: OPTIONS_SCROLL_DEFAULT) -> Bool {
        guard scrollOptionsWereNeverEdited, scroll != global else { return false }
        Self.copyScrollValues(from: global, to: scroll)
        return true
    }

    /// The Speed of a new entry in each release: 6.5, and 6.3 in 1.0.0 and 1.0.1. Every
    /// other value of a new entry was the same in all of them but the direction (below).
    static let newEntrySpeeds = [6.5, 6.3]

    /// The app's own scroll options are those of a new entry: nobody set them.
    /// - Exactly a new entry's on this Mac (`OPTIONS_SCROLL_DEFAULT.installationDefaults()`:
    ///   on a Mac with Natural scrolling off the wheel's direction is classic there).
    /// - Or a new entry's as any release, on any Mac, stored it, while the entry has no
    ///   thumb wheel values of its own. Up to 1.0.5 a new entry reversed the wheel on every
    ///   Mac; since then it follows the Mac's Natural scrolling, which the user can change
    ///   afterwards; a settings file brings entries from another Mac. An entry gets its
    ///   thumb wheel values the first time this version switches "Use settings from
    ///   Scrolling" off for it (`adoptThumbWheelScrollingIfNone`, right after this is
    ///   asked), so one without them never had its own settings here; and an app whose own
    ///   "Reverse wheel direction" was turned on here, on a Mac with Natural scrolling
    ///   off, has them and keeps its direction.
    var scrollOptionsWereNeverEdited: Bool {
        if scroll == OPTIONS_SCROLL_DEFAULT.installationDefaults() { return true }
        guard scroll.thumbWheel == nil else { return false }
        return Self.newEntrySpeeds.contains { speed in
            scroll == OPTIONS_SCROLL_DEFAULT(reverse: scroll.reverse, speed: speed)
        }
    }

    /// "Copy from Scrolling" of the app's Scrolling part: a new container with every scroll
    /// value of `global`, and the thumb wheel's speed, reverses and follow switch of
    /// `thumbWheel` (the general ones: no function of its own).
    static func scrollingCopy(of global: OPTIONS_SCROLL_DEFAULT, thumbWheel: ThumbWheelSettings) -> OPTIONS_SCROLL_DEFAULT {
        let copy = OPTIONS_SCROLL_DEFAULT()
        copyScrollValues(from: global, to: copy)
        copy.thumbWheel = ApplicationThumbWheelScrolling(thumbWheel)
        return copy
    }

    /// Every scroll value of `global` into `own` (its container stays its own).
    private static func copyScrollValues(from global: OPTIONS_SCROLL_DEFAULT, to own: OPTIONS_SCROLL_DEFAULT) {
        own.smooth = global.smooth
        own.reverse = global.reverse
        own.reverseVertical = global.reverseVertical
        own.reverseHorizontal = global.reverseHorizontal
        own.dash = global.dash
        own.slow = global.slow
        own.toggle = global.toggle
        own.block = global.block
        own.step = global.step
        own.speed = global.speed
        own.duration = global.duration
        own.deadZone = global.deadZone
        own.smoothSimTrackpad = global.smoothSimTrackpad
        own.smoothVertical = global.smoothVertical
        own.smoothHorizontal = global.smoothHorizontal
    }
}

private extension Application {
    func resolvedScrollOptions() -> OPTIONS_SCROLL_DEFAULT {
        return inherit ? Options.shared.scroll : scroll
    }
}
