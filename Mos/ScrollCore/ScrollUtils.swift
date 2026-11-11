//
//  ScrollUtils.swift
//  Mos
//  滚动事件截取与判断核心工具方法
//  Created by Caldis on 2018/2/19.
//  Copyright © 2018年 Caldis. All rights reserved.
//

import Cocoa

class ScrollUtils {
    
    // 单例
    static let shared = ScrollUtils()
    init() { NSLog("Module initialized: ScrollUtils") }
    private let syntheticSmoothEventMarker: Int64 = 0x4D4F53534D4F4F54
    
    func markSyntheticSmoothEvent(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: syntheticSmoothEventMarker)
    }

    func isSyntheticSmoothEvent(_ event: CGEvent) -> Bool {
        return event.getIntegerValueField(.eventSourceUserData) == syntheticSmoothEventMarker
    }
    
    // 从 CGEvent 中携带的 PID 获取应用信息
    private var lastEventTargetPID: pid_t = 1  // 事件的目标进程 PID (先前)
    private var currEventTargetPID: pid_t = 1  // 事件的目标进程 PID (当前)
    private var cachedRunningApplication: NSRunningApplication?
    func getRunningApplication(from event: CGEvent) -> NSRunningApplication? {
        // Guard
        let pid = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
        if pid == pid_t(1) { return nil }
        // 保存上次 PID
        lastEventTargetPID = currEventTargetPID
        // 更新当前 PID
        currEventTargetPID = pid
        // 使用 PID 获取 BID
        // 如果目标 PID 变化, 则重新获取一次窗口 BID
        if lastEventTargetPID != currEventTargetPID {
            cachedRunningApplication = NSRunningApplication.init(processIdentifier: pid)
        }
        return cachedRunningApplication
    }
    
    // MARK: - What the app under the pointer does with trackpad-style events

    /// What an app does with the events of a glide ("momentum"), so that "Trackpad-style
    /// events" can be sent in the form it scrolls by (ScrollPoster).
    enum TrackpadStyleTarget: Equatable {
        /// AppKit and UIKit scroll views, and anything not known: they follow the touch only and
        /// compute the glide themselves. One touch for as long as the wheel turns.
        case touchOnly
        /// The Chromium engine (Chrome, Dia, Arc, Edge, Electron and CEF apps) scrolls by the
        /// glide's events: a flick.
        case followsGlide
        /// WebKit in Safari scrolls by them too, but only when the events carry no record of the
        /// wheel's hardware event (`ScrollDispatchContext.eventWithoutHardwareRecord`): a flick
        /// of newly made events.
        case followsGlideWithoutHardwareRecord
    }

    /// Bundle path -> answer. Main thread.
    private var trackpadStyleTargetByBundlePath: [String: TrackpadStyleTarget] = [:]

    /// The kind of the app a wheel event goes to; looked into once per app. Main thread.
    func trackpadStyleTarget(of event: CGEvent) -> TrackpadStyleTarget {
        guard let application = getRunningApplication(from: event), let bundleURL = application.bundleURL else {
            return .touchOnly
        }
        if let known = trackpadStyleTargetByBundlePath[bundleURL.path] {
            return known
        }
        let target = Self.trackpadStyleTarget(bundleIdentifier: application.bundleIdentifier, bundleURL: bundleURL)
        trackpadStyleTargetByBundlePath[bundleURL.path] = target
        return target
    }

    /// Safari by its name, a Chromium-based app by what its bundle carries. (Firefox, and web
    /// views inside other apps, count as touch-only: not checked on screen, and a web view
    /// cannot be told from the app's own lists.)
    static func trackpadStyleTarget(bundleIdentifier: String?, bundleURL: URL, fileManager: FileManager = .default) -> TrackpadStyleTarget {
        if let identifier = bundleIdentifier, safariBundleIdentifiers.contains(identifier) {
            return .followsGlideWithoutHardwareRecord
        }
        return isChromiumBased(bundleURL: bundleURL, fileManager: fileManager) ? .followsGlide : .touchOnly
    }

    static let safariBundleIdentifiers: Set<String> = ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]

    /// A Chromium-based app carries the engine's resources (`resources.pak`) in one of its
    /// frameworks: "Google Chrome Framework", "Electron Framework", "Chromium Embedded
    /// Framework", Dia's and Arc's "ArcCore". One look into `Contents/Frameworks`.
    static func isChromiumBased(bundleURL: URL, fileManager: FileManager = .default) -> Bool {
        let frameworks = bundleURL.appendingPathComponent("Contents/Frameworks", isDirectory: true)
        guard let names = try? fileManager.contentsOfDirectory(atPath: frameworks.path) else {
            return false
        }
        for name in names where name.hasSuffix(".framework") {
            let framework = frameworks.appendingPathComponent(name, isDirectory: true)
            for resources in ["Resources", "Versions/Current/Resources"] {
                let pak = framework.appendingPathComponent(resources, isDirectory: true).appendingPathComponent("resources.pak")
                if fileManager.fileExists(atPath: pak.path) {
                    return true
                }
            }
        }
        return false
    }

    // 判断目标是否为 Chrome
    func isEventTargetingChrome(_ event: CGEvent?) -> Bool {
        guard let validEvent = event else {
            return false
        }
        guard let targetRunningApplication = getRunningApplication(from: validEvent) else {
            return false
        }
        if let targetBundleIdentifier = targetRunningApplication.bundleIdentifier, targetBundleIdentifier == "com.google.Chrome" {
            return true
        }
        return false
    }
    
    // 判断 LaunchPad 是否激活
    static let dockExecutablePath = "/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock"
    func getLaunchpadActivity(withRunningApplication runningApplication: NSRunningApplication?) -> Bool {
        guard let validRunningApplication = runningApplication else {
            return false
        }
        // macOS 26+ LaunchPad 已无分页功能, 平滑滚动是预期行为, 无需特殊处理
        if #available(macOS 26.0, *) {
            return false
        }
        return Self.isLaunchpadHost(executablePath: validRunningApplication.executableURL?.path)
    }
    /// Before macOS 26, Launchpad lives in the Dock process: a scroll aimed at the Dock is
    /// treated as a scroll in Launchpad.
    /// (The window-list scan that macOS 10.14 and earlier needed is gone with the 14.0 target.)
    // FIXME: 当 Dock 的目录设置为 "叠放" 时, 应用对 Dock 的目录预览无法平滑, 且发送平滑后的滚动事件无法被识别, 需要找别的方式
    static func isLaunchpadHost(executablePath: String?) -> Bool {
        return executablePath == dockExecutablePath
    }

    // 从 Applications 中取回符合传入的 key 的 Application 对象
    // Key 在 applications 初始化时指定于 Application 中
    func getTargetApplication(from runningApplication: NSRunningApplication?) -> Application? {
        if let applicationByBundlePath = Options.shared.application.applications.get(by: runningApplication?.bundleURL?.path) {
            return applicationByBundlePath
        }
        if let applicationByExecutablePath = Options.shared.application.applications.get(by: runningApplication?.executableURL?.path) {
            return applicationByExecutablePath
        }
        return nil
    }

    // MARK: - 远程桌面事件检测
    // 远程桌面事件检测缓存
    private var lastSourcePID: pid_t = 0
    private var lastSourceIsRemoteControl: Bool = false

    /// 检测事件来源是否为远程桌面应用
    func isFromRemoteApplication(_ event: CGEvent) -> Bool {
        let sourcePID = pid_t(event.getIntegerValueField(.eventSourceUnixProcessID))
        if sourcePID == 0 { return false }

        if sourcePID != lastSourcePID {
            lastSourcePID = sourcePID
            lastSourceIsRemoteControl = false

            if let app = NSRunningApplication(processIdentifier: sourcePID) {
                // 检查可执行文件路径（系统守护进程）
                if let path = app.executableURL?.path {
                    for keyword in REMOTE_CONTROL_APPLICATION.executableKeywords {
                        if path.contains(keyword) {
                            lastSourceIsRemoteControl = true
                            break
                        }
                    }
                }
                // 检查 Bundle Identifier（第三方应用）
                if !lastSourceIsRemoteControl, let bundleId = app.bundleIdentifier {
                    lastSourceIsRemoteControl = REMOTE_CONTROL_APPLICATION.bundleIdentifiers.contains(bundleId)
                }
            }
        }
        return lastSourceIsRemoteControl
    }

#if DEBUG
    /// Tests: events from this source process count as a remote desktop's (until another
    /// source is seen, or `nil` forgets it).
    func treatAsRemoteForTests(sourcePID: pid_t?) {
        lastSourcePID = sourcePID ?? 0
        lastSourceIsRemoteControl = sourcePID != nil
    }
#endif

    /// 检测事件是否来自已被平滑的远程源
    /// 返回 true 表示应跳过平滑处理
    func isRemoteSmoothedEvent(_ event: CGEvent) -> Bool {
        if !isFromRemoteApplication(event) { return false }
        // 检查 isContinuous 字段判断是否为连续的
        let isContinuous = event.getDoubleValueField(.scrollWheelEventIsContinuous)
        return isContinuous == 1.0  // 1.0 表示主控端已平滑
    }

    // MARK: - 滚动参数: 热键
    // 返回 ScrollHotkey? 供 ScrollCore 使用
    func optionsDashKey(application: Application?) -> ScrollHotkey? {
        if let targetApplication = application {
            return targetApplication.inherit ? Options.shared.scroll.dash : targetApplication.scroll.dash
        } else {
            return Options.shared.scroll.dash
        }
    }
    func optionsToggleKey(application: Application?) -> ScrollHotkey? {
        if let targetApplication = application {
            return targetApplication.inherit ? Options.shared.scroll.toggle : targetApplication.scroll.toggle
        } else {
            return Options.shared.scroll.toggle
        }
    }
    func optionsBlockKey(application: Application?) -> ScrollHotkey? {
        if let targetApplication = application {
            return targetApplication.inherit ? Options.shared.scroll.block : targetApplication.scroll.block
        } else {
            return Options.shared.scroll.block
        }
    }
}
