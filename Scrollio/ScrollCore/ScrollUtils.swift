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
    init() {}
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
        /// Safari: no trackpad-style events at all, the frames go out as with the switch off.
        /// With phases Safari does not scroll smoothly (owner, build 1521; the frames went out as
        /// always). WebKit reads, on every scroll event that has a phase, the record of the
        /// hardware event the frame still carries as a copy of the wheel event: its time (the
        /// same for every frame of a tick) and the wheel's raw delta, for a glide of its own.
        /// Frames made anew without that record did not scroll Safari at all (build 1538).
        /// Also the other apps whose whole window is WebKit's and that are known by name
        /// (`getsPlainScrolling`): Safari's web apps, the DuckDuckGo browser.
        case plainScrolling
    }

    /// Bundle path -> answer. Main thread.
    private var trackpadStyleTargetByBundlePath: [String: TrackpadStyleTarget] = [:]

    /// Looks into an app's bundle off the main thread and calls back on the main queue with
    /// whether it is Chromium-based. Tests put their own in its place (no disk).
    var inspectBundle: (_ bundleURL: URL, _ completion: @escaping (Bool) -> Void) -> Void = { bundleURL, completion in
        ScrollUtils.bundleInspectionQueue.async {
            // The folder an alias in Applications points to is judged again: never outside.
            let resolved = bundleURL.resolvingSymlinksInPath()
            let isChromium = ScrollUtils.mayLookIntoBundle(atPath: resolved.path) && ScrollUtils.isChromiumBased(bundleURL: resolved)
            DispatchQueue.main.async { completion(isChromium) }
        }
    }
    private static let bundleInspectionQueue = DispatchQueue(label: "com.nikklemenc.Scrollio.bundle-inspection", qos: .utility)

    /// The kind of the app a wheel event goes to. Main thread, inside the scroll tap's
    /// callback: it never touches the disk.
    func trackpadStyleTarget(of event: CGEvent) -> TrackpadStyleTarget {
        guard let application = getRunningApplication(from: event), let bundleURL = application.bundleURL else {
            return .touchOnly
        }
        return trackpadStyleTarget(bundleIdentifier: application.bundleIdentifier, bundleURL: bundleURL)
    }

    /// The answer for an app, at once. Safari is known by its name (`getsPlainScrolling`). Any
    /// other app counts as touch-only the first time it is seen (what an app that is not known
    /// gets; an app is first seen when it comes to the front, `applicationCameToFront`, or by
    /// its first wheel event), and its
    /// bundle is looked into once, off the main thread; the answer is stored on the main
    /// queue for the scrolls after it. It used to be looked into here, inside the tap's
    /// callback: for an app in Documents, Desktop, Downloads or on a network volume macOS
    /// held that call (a privacy prompt in Scrollio's name, or the wait for the share) and
    /// with it every event tap. A bundle outside the Applications folders and /System is
    /// never looked into (`mayLookIntoBundle`), so macOS never asks for a folder of the
    /// user's on Scrollio's behalf; such an app stays touch-only.
    func trackpadStyleTarget(bundleIdentifier: String?, bundleURL: URL) -> TrackpadStyleTarget {
        let path = bundleURL.path
        if let known = trackpadStyleTargetByBundlePath[path] {
            return known
        }
        if let identifier = bundleIdentifier, Self.getsPlainScrolling(bundleIdentifier: identifier) {
            trackpadStyleTargetByBundlePath[path] = .plainScrolling
            return .plainScrolling
        }
        // Stored at once: one look per app, however many wheel events come before its answer.
        trackpadStyleTargetByBundlePath[path] = .touchOnly
        guard Self.mayLookIntoBundle(atPath: path) else {
            return .touchOnly
        }
        inspectBundle(bundleURL) { [weak self] isChromium in
            if isChromium {
                self?.trackpadStyleTargetByBundlePath[path] = .followsGlide
            }
        }
        return .touchOnly
    }

    /// Whether an app's bundle may be looked into: only inside /Applications, /System (with
    /// /System/Applications) and the user's own Applications folder. None of them is a
    /// folder macOS guards with a privacy prompt (Documents, Desktop, Downloads, iCloud
    /// Drive, removable and network volumes are). /System/Volumes is left out: the data
    /// volume, and so every user's folders, can be reached through it. Pure: the path as it
    /// is given, no disk.
    static func mayLookIntoBundle(atPath path: String, homeDirectory: String = ScrollUtils.homeDirectory) -> Bool {
        guard path.hasPrefix("/"), !path.contains("/../"), !path.hasSuffix("/..") else { return false }
        if path.hasPrefix("/System/") {
            return !path.hasPrefix("/System/Volumes/")
        }
        return path.hasPrefix("/Applications/") || path.hasPrefix(homeDirectory + "/Applications/")
    }
    private static let homeDirectory = NSHomeDirectory()

    /// Whether an app gets no trackpad-style events at all (`TrackpadStyleTarget
    /// .plainScrolling`): a browser whose pages WebKit draws, known by its bundle id.
    ///
    /// - Safari: every id that begins with `com.apple.Safari`. That is Safari itself, Safari
    ///   Technology Preview, and the web apps made with "Add to Dock"
    ///   (`com.apple.Safari.WebApp.<id>`), which used to count as touch-only and got the form
    ///   Safari could not scroll with.
    /// - The DuckDuckGo browser (WKWebView): both ids are in its own repository,
    ///   github.com/duckduckgo/apple-browsers, `macOS/Configuration/DeveloperID.xcconfig`
    ///   (the download) and `macOS/Configuration/AppStore.xcconfig` (the Mac App Store build).
    ///
    /// An id goes in here only from a source that can be named. (Orion is WebKit too; its id
    /// could not be confirmed from Kagi's own material, so it is not listed.) Firefox, and web
    /// views inside other apps, count as touch-only: not checked on screen, and a web view
    /// cannot be told from the app's own lists.
    static func getsPlainScrolling(bundleIdentifier: String) -> Bool {
        return bundleIdentifier.hasPrefix(safariBundleIdentifierPrefix)
            || webKitBrowserBundleIdentifiers.contains(bundleIdentifier)
    }
    static let safariBundleIdentifierPrefix = "com.apple.Safari"
    static let webKitBrowserBundleIdentifiers: Set<String> = [
        "com.duckduckgo.macos.browser", "com.duckduckgo.mobile.ios",
    ]

    /// An app came to the front. With trackpad-style events on for it, its kind is asked for
    /// now (the look into its bundle runs off the main thread, as always), so that the first
    /// scroll in it already knows. It used to be asked by the first wheel event, and that
    /// scroll (until the answer) went out as for an app that is not known: over a
    /// Chromium-based app as one long touch instead of a flick. An app that never comes to
    /// the front (a scroll over a window in the background) is still asked for by its first
    /// wheel event. Main thread.
    func applicationCameToFront(bundleIdentifier: String?, bundleURL: URL?, trackpadStyleOn: Bool) {
        guard trackpadStyleOn, let bundleURL = bundleURL else { return }
        _ = trackpadStyleTarget(bundleIdentifier: bundleIdentifier, bundleURL: bundleURL)
    }

    /// A Chromium-based app carries the engine's resources (`resources.pak`) in one of its
    /// frameworks: "Google Chrome Framework", "Electron Framework", "Chromium Embedded
    /// Framework", Dia's and Arc's "ArcCore". A web app installed from such a browser (Chrome,
    /// Brave, Edge: "Install as app") is a small bundle of its own without frameworks: its
    /// program is the browser's `app_mode_loader`, and its windows live in that process, so it
    /// is known by that file. One look into `Contents/Frameworks` and `Contents/MacOS`: reads
    /// the disk, so never on the main thread (`inspectBundle`).
    static func isChromiumBased(bundleURL: URL, fileManager: FileManager = .default) -> Bool {
        let appModeLoader = bundleURL.appendingPathComponent("Contents/MacOS/app_mode_loader")
        if fileManager.fileExists(atPath: appModeLoader.path) {
            return true
        }
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
