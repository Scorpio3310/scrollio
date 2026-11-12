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
    // 配置: 按钮绑定 (可选表示继承全局配置)
    var buttons: OPTIONS_BUTTONS_DEFAULT? {
        didSet { Options.shared.markChanged(.application) }
    }
    // 初始化
    init(path: String) {
        self.path = path
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
        scroll = try container.decodeIfPresent(OPTIONS_SCROLL_DEFAULT.self, forKey: .scroll) ?? OPTIONS_SCROLL_DEFAULT()
        // One-time migration: settings stored while "Trackpad-style events" locked Duration get
        // the Duration from before the lock back. The remembered value is not kept in the model,
        // so the next save drops it.
        if let legacy = try? container.decodeIfPresent(OPTIONS_SCROLL_DEFAULT.LegacySimTrackpadLock.self, forKey: .scroll) {
            scroll.restoreDuration(from: legacy)
        }
        // 按钮绑定
        buttons = try container.decodeIfPresent(OPTIONS_BUTTONS_DEFAULT.self, forKey: .buttons)
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
    func isReverse() -> Bool {
        return resolvedScrollOptions().reverse
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
    // 按钮绑定
    func getButtonBindings() -> [ButtonBinding] {
        return buttons?.binding ?? Options.shared.buttons.binding
    }
}

// MARK: - Own settings from the Scrolling settings

extension Application {
    /// Before "Use settings from Scrolling" is switched off: scroll options of the app's
    /// own that were never edited (exactly those of a new entry, `OPTIONS_SCROLL_DEFAULT()`)
    /// become a copy of `global`, so the app scrolls on as it did until the user changes
    /// something. Options that were edited are kept. Returns whether they were copied.
    /// The app keeps its own container: only its values change, stored as before.
    @discardableResult
    func adoptScrollOptionsIfUnedited(from global: OPTIONS_SCROLL_DEFAULT) -> Bool {
        guard scroll == OPTIONS_SCROLL_DEFAULT(), scroll != global else { return false }
        let own = scroll
        own.smooth = global.smooth
        own.reverse = global.reverse
        own.reverseVertical = global.reverseVertical
        own.reverseHorizontal = global.reverseHorizontal
        own.dash = global.dash
        own.toggle = global.toggle
        own.block = global.block
        own.step = global.step
        own.speed = global.speed
        own.duration = global.duration
        own.deadZone = global.deadZone
        own.smoothSimTrackpad = global.smoothSimTrackpad
        own.smoothVertical = global.smoothVertical
        own.smoothHorizontal = global.smoothHorizontal
        return true
    }
}

private extension Application {
    func resolvedScrollOptions() -> OPTIONS_SCROLL_DEFAULT {
        return inherit ? Options.shared.scroll : scroll
    }
}
