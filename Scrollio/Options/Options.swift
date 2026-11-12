//
//  Options.swift
//  Mos
//  配置参数
//  Created by Caldis on 2018/2/19.
//  Copyright © 2018年 Caldis. All rights reserved.
//

import Cocoa

struct OptionItem {
    struct General {
        static let OptionsExist = "optionsExist"
        static let HideStatusItem = "hideStatusItem"
        /// The Welcome Guide (an Int, `WelcomeGuideProgress`): 0 while a new user has not
        /// finished it, the version of the guide once finished. Read and written only by the
        /// guide, never by `readOptions` or a save.
        static let WelcomeGuideCompletedVersion = "welcomeGuideCompletedVersion"
    }

    struct Scroll {
        static let Smooth = "smooth"
        static let Reverse = "reverse"
        static let ReverseVertical = "reverseVertical"
        static let ReverseHorizontal = "reverseHorizontal"
        static let Dash = "dash"
        static let Toggle = "toggle"
        static let Block = "block"
        static let Step = "step"
        static let Speed = "speed"
        static let Duration = "duration"
        static let DeadZone = "deadZone"
        static let SmoothSimTrackpad = "smoothSimTrackpad"
        static let SmoothVertical = "smoothVertical"
        static let SmoothHorizontal = "smoothHorizontal"
    }

    struct Button {
        static let Bindings = "buttonBindings"
    }

    struct Gesture {
        static let Settings = "mouseGestureSettings"
    }

    struct MouseWheel {
        static let Settings = "logiWheelSettings"
    }

    struct MouseBasics {
        static let Settings = "logiMouseSettings"
    }

    struct ThumbWheel {
        static let Settings = "thumbWheelSettings"
    }

    struct Application {
        static let Allowlist = "allowlist"
        static let Applications = "applications"
    }
}

/// 配置分组: 变更通知与脏组写入的粒度
enum OptionsGroup: CaseIterable {
    case general, scroll, buttons, application, gesture, logiWheel, logiMouse, thumbWheel
}

class Options {

    // 单例
    static let shared = Options()
    init() {}

    /// Where the settings are read from and written to: the app's preferences. A test
    /// passes a store of its own (`TestDefaults`), and must put this one back.
    var defaults: UserDefaults = .standard
    /// Whether changes are written at all. Under XCTest never to the app's real
    /// preferences, whatever a test changes or forgets; only to a store a test passed in.
    /// A settings file follows the same rule (`SettingsFile`): it is neither made from the
    /// app's real preferences under XCTest nor imported into them.
    var writesToDefaults: Bool {
        return !AppRuntime.isRunningXCTest || defaults !== UserDefaults.standard
    }

    // 读取锁, 防止冲突
    private var readingOptionsLock = false
    // JSON 编解码工具
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // 常规
    var general = OPTIONS_GENERAL_DEFAULT() {
        didSet { markChanged(.general) }
    }
    // 滚动
    var scroll = OPTIONS_SCROLL_DEFAULT() {
        didSet { markChanged(.scroll) }
    }
    // 按钮绑定
    var buttons = OPTIONS_BUTTONS_DEFAULT() {
        didSet { markChanged(.buttons) }
    }
    // 应用
    var application = OPTIONS_APPLICATION_DEFAULT() {
        didSet { markChanged(.application) }
    }
    // 手势导航 (所有 Gesture Navigation 绑定共用)
    var gesture = MouseGestureSettings.default {
        didSet { markChanged(.gesture) }
    }
    // Logitech 滚轮硬件设置 (SmartShift 模式 / 灵敏度 / 齿感力度). Every value is optional
    // (nil = leave the mouse's own); written only while `managedByScrollio` is on.
    var logiWheel = LogiWheelSettings.default {
        didSet { markChanged(.logiWheel) }
    }
    // Logitech basic mouse settings (pointer speed, haptics, press force). Every value is
    // optional (nil = leave the mouse's own); written only while `logiMouseManaged` is on.
    var logiMouse = LogiMouseSettings.default {
        didSet { markChanged(.logiMouse) }
    }
    // What the sideways wheel does (function, speed, direction): ThumbWheelSettings. Used by
    // the scroll engine only; nothing is written to a mouse.
    var thumbWheel = ThumbWheelSettings.default {
        didSet { markChanged(.thumbWheel) }
    }
    /// "Let Scrollio manage this mouse": the one switch for everything Scrollio writes to a
    /// Logitech mouse (wheel and basic settings). Stored as `logiWheel.managedByScrollio`.
    var logiMouseManaged: Bool {
        get { logiWheel.managedByScrollio }
        set { logiWheel.managedByScrollio = newValue }
    }

    /// 保留无法 decode 的 binding 原始 JSON 元素 (来自未来 Mos 版本).
    /// 在 save 时再合回去, 防止用户升级后再降级时丢失新版数据.
    fileprivate var preservedUnknownBindings: [Any] = []
    /// Per-app entries this version cannot read (from a newer version, or damaged), as they
    /// were stored. Saved back after the apps it knows, like `preservedUnknownBindings`.
    fileprivate var preservedUnknownApplications: [Any] = []

    // 变更订阅 (append-only; 订阅者均为进程级单例, 无注销需求)
    fileprivate var observers: [(groups: Set<OptionsGroup>, handler: (OptionsGroup) -> Void)] = []
    // 待写入的脏组与调度标志
    fileprivate var pendingSaveGroups: Set<OptionsGroup> = []
    fileprivate var saveFlushScheduled = false
    #if DEBUG
    /// 测试钩子: flush 发生时回调脏组集合 (XCTest 下真实写入被跳过, 用它观测合并行为)
    var onFlushForTests: ((Set<OptionsGroup>) -> Void)?
    /// 测试钩子: 在读取锁内执行 body, 验证抑制语义
    func withReadingLockForTests(_ body: () -> Void) {
        readingOptionsLock = true
        defer { readingOptionsLock = false }
        body()
    }
    /// Tests: how many observers there are, and a way to take the newest ones away again.
    /// The app's observers stay for its life; a test that installs the launch's own on
    /// the shared settings (to see a change travel through them) must not leave them
    /// there for every test that runs after it.
    var observerCountForTests: Int {
        return observers.count
    }
    func removeNewestObserversForTests(_ count: Int) {
        observers.removeLast(min(max(0, count), observers.count))
    }
    #endif
}

/**
 * 变更订阅与脏组写入
 **/
extension Options {

    /// 订阅指定组的变更 (同步派发, 主线程)
    func observe(_ groups: Set<OptionsGroup>, handler: @escaping (OptionsGroup) -> Void) {
        observers.append((groups: groups, handler: handler))
    }

    /// 变更入口: 通知订阅者并调度该组的延迟写入 (同 tick 合并)
    func markChanged(_ group: OptionsGroup) {
        assert(Thread.isMainThread, "Options.markChanged is main-thread-only")
        // 读取期间 (readOptions) 抑制通知与保存
        guard !readingOptionsLock else { return }
        for observer in observers where observer.groups.contains(group) {
            observer.handler(group)
        }
        pendingSaveGroups.insert(group)
        scheduleSaveFlush()
    }

    /// 身份路由: scroll 容器被全局配置与 per-app (Application.scroll) 复用
    func markChanged(scrollContainer: OPTIONS_SCROLL_DEFAULT) {
        markChanged(scrollContainer === scroll ? .scroll : .application)
    }
    /// 身份路由: buttons 容器被全局配置与 per-app (Application.buttons) 复用
    func markChanged(buttonsContainer: OPTIONS_BUTTONS_DEFAULT) {
        markChanged(buttonsContainer === buttons ? .buttons : .application)
    }

    private func scheduleSaveFlush() {
        guard !saveFlushScheduled else { return }
        saveFlushScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.flushPendingSaves()
        }
    }

    /// 写入所有脏组 (应用退出前由 AppDelegate 兜底调用)
    func flushPendingSaves() {
        saveFlushScheduled = false
        guard !pendingSaveGroups.isEmpty else { return }
        let groups = pendingSaveGroups
        pendingSaveGroups = []
        #if DEBUG
        onFlushForTests?(groups)
        #endif
        guard writesToDefaults else { return }
        defaults.set("optionsExist", forKey: OptionItem.General.OptionsExist)
        for group in groups { save(group: group) }
    }
}

/**
 * 读取和写入
 **/
extension Options {
    
    // 从 UserDefaults 中读取到 currentOptions
    func readOptions() {
        // 配置项如果不存在则尝试用当前设置(默认设置)保存一次
        if defaults.object(forKey: OptionItem.General.OptionsExist) == nil { saveOptions() }
        // 锁定
        readingOptionsLock = true
        // 常规
        // The login item lives in the system, not in UserDefaults. Assigning the value that
        // was just read makes the property's observer a no-op (LoginItem.setEnabled).
        general.autoLaunch = LoginItem.isEnabled
        general.hideStatusItem = defaults.bool(forKey: OptionItem.General.HideStatusItem)
        // 滚动
        // A missing key is the default (on), as for the keys below: `bool(forKey:)` reads a
        // missing key as off, so a settings file without "smooth" switched smoothing off.
        scroll.smooth = Self.storedBool(forKey: OptionItem.Scroll.Smooth, default: OPTIONS_SCROLL_DEFAULT().smooth, in: defaults)
        scroll.reverse = Self.storedBool(forKey: OptionItem.Scroll.Reverse, default: OPTIONS_SCROLL_DEFAULT().reverse, in: defaults)
        if defaults.object(forKey: OptionItem.Scroll.ReverseVertical) == nil {
            scroll.reverseVertical = true
        } else {
            scroll.reverseVertical = defaults.bool(forKey: OptionItem.Scroll.ReverseVertical)
        }
        if defaults.object(forKey: OptionItem.Scroll.ReverseHorizontal) == nil {
            scroll.reverseHorizontal = true
        } else {
            scroll.reverseHorizontal = defaults.bool(forKey: OptionItem.Scroll.ReverseHorizontal)
        }
        scroll.dash = loadScrollHotkey(forKey: OptionItem.Scroll.Dash, default: OPTIONS_SCROLL_DEFAULT().dash)
        scroll.toggle = loadScrollHotkey(forKey: OptionItem.Scroll.Toggle, default: OPTIONS_SCROLL_DEFAULT().toggle)
        scroll.block = loadScrollHotkey(forKey: OptionItem.Scroll.Block, default: OPTIONS_SCROLL_DEFAULT().block)
        if let storedStep = defaults.object(forKey: OptionItem.Scroll.Step) as? Double {
            scroll.step = storedStep
        } else {
            scroll.step = OPTIONS_SCROLL_DEFAULT().step
        }
        if let storedSpeed = defaults.object(forKey: OptionItem.Scroll.Speed) as? Double {
            scroll.speed = storedSpeed
        } else {
            scroll.speed = OPTIONS_SCROLL_DEFAULT().speed
        }
        if let storedDuration = defaults.object(forKey: OptionItem.Scroll.Duration) as? Double {
            scroll.duration = storedDuration
        } else {
            scroll.duration = OPTIONS_SCROLL_DEFAULT().duration
        }
        if let storedDeadZone = defaults.object(forKey: OptionItem.Scroll.DeadZone) as? Double {
            scroll.deadZone = storedDeadZone
        } else {
            scroll.deadZone = OPTIONS_SCROLL_DEFAULT().deadZone
        }
        scroll.smoothSimTrackpad = defaults.bool(forKey: OptionItem.Scroll.SmoothSimTrackpad)
        if defaults.object(forKey: OptionItem.Scroll.SmoothVertical) == nil {
            scroll.smoothVertical = true
        } else {
            scroll.smoothVertical = defaults.bool(forKey: OptionItem.Scroll.SmoothVertical)
        }
        if defaults.object(forKey: OptionItem.Scroll.SmoothHorizontal) == nil {
            scroll.smoothHorizontal = true
        } else {
            scroll.smoothHorizontal = defaults.bool(forKey: OptionItem.Scroll.SmoothHorizontal)
        }
        // 按钮绑定
        buttons.binding = loadButtonsData()
        ButtonUtils.shared.invalidateCache()
        // 应用
        application.allowlist = defaults.bool(forKey: OptionItem.Application.Allowlist)
        application.applications = loadApplicationsData()
        // 手势导航
        gesture = loadGestureSettings()
        // Logitech 滚轮
        logiWheel = Self.decodeLogiWheelSettings(defaults.data(forKey: OptionItem.MouseWheel.Settings))
        // Logitech basic mouse settings
        logiMouse = Self.decodeLogiMouseSettings(defaults.data(forKey: OptionItem.MouseBasics.Settings))
        // The sideways wheel
        thumbWheel = Self.decodeThumbWheelSettings(defaults.data(forKey: OptionItem.ThumbWheel.Settings))
        // What the Scrolling tab can no longer show is brought in line (global and per app),
        // and the keys of retired settings are removed. Still inside the lock: nothing is
        // notified or saved, the next save writes it.
        ScrollSettingsCleanup.run(
            global: scroll,
            applications: (0..<application.applications.count).compactMap { application.applications.get(by: $0) },
            defaults: writesToDefaults ? defaults : nil
        )
        // 解锁
        readingOptionsLock = false
    }
    
    /// After a settings file was put into the store (`SettingsFile.apply`): everything is
    /// read again exactly as at launch (the same decoding, the same clean-up), then the
    /// observers of `groups` are told and those groups are saved, as after a change made
    /// by hand. Reading alone tells nobody (`readingOptionsLock`). Main thread.
    func reloadFromStore(notifying groups: [OptionsGroup]) {
        readOptions()
        for group in groups {
            markChanged(group)
        }
    }

    /// A stored switch, or `defaultValue` when the key is missing.
    static func storedBool(forKey key: String, default defaultValue: Bool, in defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }

    // 同步写入全部配置 (首启播种与遗留路径; 常规变更走 markChanged 的脏组合并写入)
    func saveOptions() {
        guard writesToDefaults else { return }

        if !readingOptionsLock {
            // 标识配置项存在
            defaults.set("optionsExist", forKey: OptionItem.General.OptionsExist)
            for group in OptionsGroup.allCases { save(group: group) }
        }
    }

    // 按组写入 UserDefaults (键与全量写入逐一对应, 零增减)
    private func save(group: OptionsGroup) {
        switch group {
        case .general:
            defaults.set(general.hideStatusItem, forKey: OptionItem.General.HideStatusItem)
        case .scroll:
            defaults.set(scroll.smooth, forKey: OptionItem.Scroll.Smooth)
            defaults.set(scroll.reverse, forKey: OptionItem.Scroll.Reverse)
            defaults.set(scroll.reverseVertical, forKey: OptionItem.Scroll.ReverseVertical)
            defaults.set(scroll.reverseHorizontal, forKey: OptionItem.Scroll.ReverseHorizontal)
            saveScrollHotkey(scroll.dash, forKey: OptionItem.Scroll.Dash)
            saveScrollHotkey(scroll.toggle, forKey: OptionItem.Scroll.Toggle)
            saveScrollHotkey(scroll.block, forKey: OptionItem.Scroll.Block)
            defaults.set(scroll.step, forKey: OptionItem.Scroll.Step)
            defaults.set(scroll.speed, forKey: OptionItem.Scroll.Speed)
            defaults.set(scroll.duration, forKey: OptionItem.Scroll.Duration)
            defaults.set(scroll.deadZone, forKey: OptionItem.Scroll.DeadZone)
            defaults.set(scroll.smoothSimTrackpad, forKey: OptionItem.Scroll.SmoothSimTrackpad)
            defaults.set(scroll.smoothVertical, forKey: OptionItem.Scroll.SmoothVertical)
            defaults.set(scroll.smoothHorizontal, forKey: OptionItem.Scroll.SmoothHorizontal)
        case .buttons:
            saveButtonBindingsData()
        case .application:
            defaults.set(application.allowlist, forKey: OptionItem.Application.Allowlist)
            if let applicationsData = Self.applicationsDataForSaving(
                known: application.applications.json(),
                preservedUnknown: preservedUnknownApplications
            ) {
                defaults.set(applicationsData, forKey: OptionItem.Application.Applications)
            } else {
                AppSystemLog.problem("Settings: the list of apps could not be written; the stored list stays as it was")
            }
        case .gesture:
            if let data = try? encoder.encode(gesture) {
                defaults.set(data, forKey: OptionItem.Gesture.Settings)
            } else {
                AppSystemLog.problem("Settings: the gesture settings could not be written")
            }
        case .logiWheel:
            if let data = try? encoder.encode(logiWheel) {
                defaults.set(data, forKey: OptionItem.MouseWheel.Settings)
            } else {
                AppSystemLog.problem("Settings: the Logitech wheel settings could not be written")
            }
        case .logiMouse:
            if let data = try? encoder.encode(logiMouse) {
                defaults.set(data, forKey: OptionItem.MouseBasics.Settings)
            } else {
                AppSystemLog.problem("Settings: the Logitech mouse settings could not be written")
            }
        case .thumbWheel:
            if let data = try? encoder.encode(thumbWheel) {
                defaults.set(data, forKey: OptionItem.ThumbWheel.Settings)
            } else {
                AppSystemLog.problem("Settings: the thumb wheel settings could not be written")
            }
        }
    }

    /// Logitech basic mouse settings from their stored JSON. Missing or unreadable data gives
    /// the default (nothing set, nothing written); single bad fields fall back to nil.
    static func decodeLogiMouseSettings(_ data: Data?) -> LogiMouseSettings {
        guard let data = data,
              let settings = try? JSONDecoder().decode(LogiMouseSettings.self, from: data) else {
            return .default
        }
        return settings
    }

    /// Thumb wheel settings from their stored JSON. Missing or unreadable data gives the
    /// default (scrolls sideways, as before the settings existed); single bad values fall
    /// back to their defaults.
    static func decodeThumbWheelSettings(_ data: Data?) -> ThumbWheelSettings {
        guard let data = data,
              let settings = try? JSONDecoder().decode(ThumbWheelSettings.self, from: data) else {
            return .default
        }
        return settings
    }

    /// Logitech wheel settings from their stored JSON. Missing or unreadable data gives the
    /// default (not managed, nothing set, nothing written); single bad values fall back to nil.
    /// Settings stored before the values were optional carry every value and load as set.
    static func decodeLogiWheelSettings(_ data: Data?) -> LogiWheelSettings {
        guard let data = data,
              let settings = try? JSONDecoder().decode(LogiWheelSettings.self, from: data) else {
            return .default
        }
        return settings
    }

    // 手势导航设置; 缺失或损坏时回退默认值
    private func loadGestureSettings() -> MouseGestureSettings {
        guard let data = defaults.data(forKey: OptionItem.Gesture.Settings),
              let settings = try? decoder.decode(MouseGestureSettings.self, from: data) else {
            return .default
        }
        return settings
    }

    // 安全加载按钮绑定数据
    private func loadButtonsData() -> [ButtonBinding] {
        let rawValue = defaults.object(forKey: OptionItem.Button.Bindings)
        guard let data = rawValue as? Data else {
            if rawValue != nil {
                // The one place where stored bindings are thrown away: it leaves a trace.
                AppSystemLog.problem("Settings: the stored button bindings are not data (a wrong type): removed them")
                defaults.removeObject(forKey: OptionItem.Button.Bindings)
            }
            preservedUnknownBindings = []
            return []
        }
        let result = Self.decodeButtonBindingsWithUnknowns(from: data)
        preservedUnknownBindings = result.unknownElements
        return result.bindings
    }

    /// 容错解码 button binding 数组, 保留未识别条目原始 JSON.
    ///
    /// - 外层不是 JSON 数组 → 返回空, 视作配置丢失
    /// - 单个 binding 解析失败 → 收集到 unknownElements (raw JSON), 不丢
    ///
    /// 这种 per-binding 容错设计支持向前兼容: 未来 Mos 版本写入的未知 payload
    /// 不会导致整组绑定被擦掉, 也不会在 save 时被误删 (saveButtonBindingsData
    /// 会把 preservedUnknownBindings 重新拼回数组末尾).
    static func decodeButtonBindingsWithUnknowns(
        from data: Data
    ) -> (bindings: [ButtonBinding], unknownElements: [Any]) {
        guard let elements = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            AppSystemLog.problem("Settings: the stored button bindings are not a list; none loaded")
            return (bindings: [], unknownElements: [])
        }
        let decoder = JSONDecoder()
        var bindings: [ButtonBinding] = []
        var unknown: [Any] = []
        for element in elements {
            guard JSONSerialization.isValidJSONObject(element),
                  let elementData = try? JSONSerialization.data(withJSONObject: element) else {
                continue   // 完全损坏的元素 (e.g. JSON null 顶级), 真正丢掉
            }
            if let binding = try? decoder.decode(ButtonBinding.self, from: elementData) {
                bindings.append(binding)
            } else {
                unknown.append(element)
            }
        }
        if !unknown.isEmpty {
            AppSystemLog.note("Settings: \(unknown.count) stored button binding(s) cannot be read by this version "
                + "(of a newer one, or damaged); kept as stored")
        }
        return (bindings: bindings, unknownElements: unknown)
    }

    /// Convenience wrapper: 只返回已识别的 bindings (供单测和不关心 unknowns 的调用方).
    static func decodeButtonBindings(from data: Data) -> [ButtonBinding] {
        return decodeButtonBindingsWithUnknowns(from: data).bindings
    }

    // 保存按钮绑定数据 (合并 preservedUnknownBindings, 不丢弃未来版本数据)
    private func saveButtonBindingsData() {
        do {
            let knownData = try encoder.encode(buttons.binding)
            guard var merged = try JSONSerialization.jsonObject(with: knownData) as? [Any] else {
                AppSystemLog.problem("Settings: the button bindings could not be written; the stored ones stay as they were")
                return
            }
            // 把保留的未知元素拼回去 (放在末尾, 不影响已知 bindings 顺序)
            merged.append(contentsOf: preservedUnknownBindings)
            let mergedData = try JSONSerialization.data(withJSONObject: merged)
            defaults.set(mergedData, forKey: OptionItem.Button.Bindings)
        } catch {
            AppSystemLog.problem("Settings: the button bindings could not be written (\(type(of: error))); "
                + "the stored ones stay as they were")
        }
    }

    // 加载滚动热键
    /// A scroll hold key as stored (JSON of a `ScrollHotkey`). Data that cannot be read, and
    /// a value that is no data at all, give the default key and are left as stored. (A bare
    /// key code, the form of the original app before 2026, was converted here: 0, its
    /// "Disabled", became the A key. Scrollio never wrote that form and no longer reads it.)
    private func loadScrollHotkey(forKey key: String, default defaultValue: ScrollHotkey?) -> ScrollHotkey? {
        let rawValue = defaults.object(forKey: key)

        if let data = rawValue as? Data {
            do {
                return try decoder.decode(ScrollHotkey.self, from: data)
            } catch {
                AppSystemLog.problem("Settings: the stored scroll key \"\(key)\" cannot be read; using the default key")
                return defaultValue
            }
        }
        if rawValue != nil {
            AppSystemLog.problem("Settings: the stored scroll key \"\(key)\" is not data (a wrong type); using the default key")
            return defaultValue
        }

        // 无值时: 检查配置是否已存在
        // 如果配置已存在但该键无值，说明用户主动删除了它，返回 nil
        // 如果配置不存在（首次启动），返回默认值
        let optionsExist = defaults.object(forKey: OptionItem.General.OptionsExist) != nil
        return optionsExist ? nil : defaultValue
    }

    // 保存滚动热键
    private func saveScrollHotkey(_ hotkey: ScrollHotkey?, forKey key: String) {
        guard let hotkey = hotkey else {
            defaults.removeObject(forKey: key)
            return
        }
        do {
            let data = try encoder.encode(hotkey)
            defaults.set(data, forKey: key)
        } catch {
            AppSystemLog.problem("Settings: the scroll key \"\(key)\" could not be written (\(type(of: error)))")
        }
    }

    // 安全加载应用列表数据
    private func loadApplicationsData() -> EnhanceArray<Application> {
        let defaultArray = EnhanceArray<Application>(
            matchKey: "path",
            forObserver: { Options.shared.markChanged(.application) }
        )

        // 检查 UserDefaults 中的值类型
        let rawValue = defaults.object(forKey: OptionItem.Application.Applications)
        preservedUnknownApplications = []
        guard let data = rawValue as? Data else {
            if rawValue != nil {
                AppSystemLog.problem("Settings: the stored list of apps is not data (a wrong type): removed it")
                defaults.removeObject(forKey: OptionItem.Application.Applications)
            }
            return defaultArray
        }

        // 尝试解析
        do {
            return try EnhanceArray<Application>(
                withData: data,
                matchKey: "path",
                forObserver: { Options.shared.markChanged(.application) }
            )
        } catch {
            // One entry this version cannot read used to make the whole list go. Each entry on
            // its own: the readable ones load, the others are kept as stored.
            guard let result = Self.decodeApplicationsWithUnknowns(from: data) else {
                AppSystemLog.problem("Settings: the stored list of apps cannot be read (not a list): removed it")
                defaults.removeObject(forKey: OptionItem.Application.Applications)
                return defaultArray
            }
            preservedUnknownApplications = result.unknownElements
            return EnhanceArray<Application>(
                withArray: result.applications,
                matchKey: "path",
                forObserver: { Options.shared.markChanged(.application) }
            )
        }
    }

    /// The per-app list entry by entry, for a list that cannot be read as a whole.
    ///
    /// - Not a JSON array: nil (the list is lost, as before).
    /// - An entry this version cannot read: kept in `unknownElements` as stored, never dropped.
    /// The readable entries are decoded from the stored bytes themselves, exactly as a list
    /// read as a whole.
    static func decodeApplicationsWithUnknowns(
        from data: Data
    ) -> (applications: [Application], unknownElements: [Any])? {
        guard let elements = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let decoded = try? JSONDecoder().decode([DecodedIfReadable<Application>].self, from: data),
              decoded.count == elements.count else {
            return nil
        }
        var applications: [Application] = []
        var unknown: [Any] = []
        for (element, entry) in zip(elements, decoded) {
            if let application = entry.value {
                applications.append(application)
            } else {
                unknown.append(element)
            }
        }
        if !unknown.isEmpty {
            AppSystemLog.note("Settings: \(unknown.count) stored per-app entr\(unknown.count == 1 ? "y" : "ies") cannot be "
                + "read by this version; kept as stored")
        }
        return (applications: applications, unknownElements: unknown)
    }

    /// The per-app list as it is saved. Without entries kept from loading: exactly the bytes
    /// of the apps it knows, as before. With them: those apps, then the kept entries.
    static func applicationsDataForSaving(known: Data?, preservedUnknown: [Any]) -> Data? {
        guard let known = known else { return nil }
        guard !preservedUnknown.isEmpty else { return known }
        guard var merged = (try? JSONSerialization.jsonObject(with: known)) as? [Any] else { return nil }
        // A kept entry for an app that has since been added again (the same path) is not
        // stored a second time: the entry this version can read wins.
        let knownPaths = Set(merged.compactMap { ($0 as? [String: Any])?["path"] as? String })
        merged.append(contentsOf: preservedUnknown.filter { element in
            guard let path = (element as? [String: Any])?["path"] as? String else { return true }
            return !knownPaths.contains(path)
        })
        return try? JSONSerialization.data(withJSONObject: merged)
    }
}

/// One element of a list that may not be readable: nil instead of failing the whole list.
private struct DecodedIfReadable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}
