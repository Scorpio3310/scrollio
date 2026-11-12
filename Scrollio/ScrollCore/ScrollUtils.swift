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
        /// compute the glide themselves. One touch until the scroll has run out.
        case touchOnly
        /// The Chromium engine (Chrome, Dia, Arc, Edge, Electron and CEF apps) and the Gecko
        /// engine (Firefox and its rebuilds, Thunderbird) scroll by the glide's events and make
        /// no glide of their own: a flick.
        case followsGlide
        /// No trackpad-style events at all, the frames go out as with the switch off: the apps
        /// where a wheel has to stay a wheel (`wheelOnlyBundleIdentifiers`): Maps, Find My,
        /// Calendar, iPhone Mirroring, Blender, the Godot editor.
        case plainScrolling
        /// A browser whose pages WebKit draws: Safari, Safari Technology Preview and Safari's
        /// web apps (every id that begins with `com.apple.Safari`), and the DuckDuckGo browser.
        /// Where the wheel event's hardware record comes off a frame they get the flick, as
        /// Chromium does; where it does not (before macOS 27, a failed self-test) they get no
        /// trackpad-style events at all (`ScrollPoster.trackpadStyleForm`).
        /// Why the record decides: when the "momentum began" frame carries a hardware record,
        /// WebKit runs a glide of its own from the record's raw delta and drops the glide it
        /// is sent (that is what made Safari not scroll smoothly: owner, build 1521, the old
        /// long touch with the wheel's record on every frame); without a record it follows
        /// every frame. Seen for Safari on the owner's screen (macOS 27.2, 2026-11-12:
        /// "works well, quite smooth", and WebKit's own log said 71 times that it followed
        /// Scrollio's glide and never that it replaced one). DuckDuckGo is the same engine
        /// and was not seen. (The frames made anew that did not scroll Safari at all, build
        /// 1538, probably never arrived: an event made anew has no window number. Suspected.)
        case safari
    }

    /// Bundle path -> answer. Main thread.
    private var trackpadStyleTargetByBundlePath: [String: TrackpadStyleTarget] = [:]
    /// The bundles of apps seen without a bundle id that were looked into already. Main thread.
    private var bundlesLookedIntoWithoutIdentifier: Set<String> = []
    /// The bundles whose look is on its way: until its answer the app's kind is not known
    /// (it counts as touch-only meanwhile). Main thread.
    private var bundlesBeingLookedInto: Set<String> = []

    /// Whether the kind of the app a wheel event goes to is known: false only between an
    /// app's first sight and the answer of the look into its bundle. Main thread; no disk.
    func trackpadStyleKindIsKnown(of event: CGEvent) -> Bool {
        guard let bundleURL = getRunningApplication(from: event)?.bundleURL else { return true }
        return trackpadStyleKindIsKnown(bundleURL: bundleURL)
    }

    func trackpadStyleKindIsKnown(bundleURL: URL) -> Bool {
        return !bundlesBeingLookedInto.contains(bundleURL.path)
    }

    /// Looks into an app's bundle off the main thread and calls back on the main queue with
    /// whether it scrolls by a glide's events (Chromium-based or Gecko-based). Tests put
    /// their own in its place (no disk).
    var inspectBundle: (_ bundleURL: URL, _ completion: @escaping (Bool) -> Void) -> Void = { bundleURL, completion in
        ScrollUtils.bundleInspectionQueue.async {
            let followsGlide = ScrollUtils.lookFindsGlideFollower(bundleURL: bundleURL)
            DispatchQueue.main.async { completion(followsGlide) }
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
            let isWebKitBrowser = identifier.hasPrefix(Self.safariBundleIdentifierPrefix) || Self.webKitBrowserBundleIdentifiers.contains(identifier)
            let target: TrackpadStyleTarget = isWebKitBrowser ? .safari : .plainScrolling
            trackpadStyleTargetByBundlePath[path] = target
            return target
        }
        if bundleIdentifier != nil {
            // Stored at once: one look per app, however many wheel events come before its answer.
            trackpadStyleTargetByBundlePath[path] = .touchOnly
        } else {
            // An app seen without its bundle id is not written down as touch-only: once its
            // id is known it may be Safari or a listed app, and a stored answer is never
            // asked again in this run. (Whether macOS ever gives a running app with an
            // Info.plist no id is not known; a process that is still starting is the
            // suspected case.) It is touch-only for this event and asked again at the next
            // one; its bundle is still looked into once.
            guard bundlesLookedIntoWithoutIdentifier.insert(path).inserted else {
                return .touchOnly
            }
        }
        guard Self.mayLookIntoBundle(atPath: path) else {
            return .touchOnly
        }
        bundlesBeingLookedInto.insert(path)
        inspectBundle(bundleURL) { [weak self] followsGlide in
            self?.bundlesBeingLookedInto.remove(path)
            if followsGlide {
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
    /// .plainScrolling`, or `.safari` for Safari's ids), known by its bundle id: a browser whose pages WebKit draws, or an
    /// app where a wheel has to stay a wheel.
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
    /// could not be confirmed from Kagi's own material, so it is not listed.) A web view
    /// inside another app counts as touch-only: it cannot be told from the app's own lists.
    /// (Firefox is known by its engine: `isGeckoBased`.)
    ///
    /// And the apps where a wheel has to stay a wheel (`wheelOnlyBundleIdentifiers`).
    static func getsPlainScrolling(bundleIdentifier: String) -> Bool {
        return bundleIdentifier.hasPrefix(safariBundleIdentifierPrefix)
            || webKitBrowserBundleIdentifiers.contains(bundleIdentifier)
            || wheelOnlyBundleIdentifiers.contains(bundleIdentifier)
    }
    static let safariBundleIdentifierPrefix = "com.apple.Safari"
    static let webKitBrowserBundleIdentifiers: Set<String> = [
        "com.duckduckgo.macos.browser", "com.duckduckgo.mobile.ios",
    ]
    /// Apps where a wheel has to stay a wheel: they tell a mouse from a trackpad by the
    /// phase on a scroll event and do something else with a trackpad's scroll, or do not
    /// follow phased events that do not come from a trackpad. Known from the trackers of
    /// other mouse tools (Mac Mouse Fix, LinearMouse, Mos), where people report it for a
    /// wheel that is sent with phases; none of it was seen with Scrollio on a screen.
    ///
    /// - Maps `com.apple.Maps`: the wheel pans the map instead of zooming (Mac Mouse Fix
    ///   #436, #610).
    /// - Find My `com.apple.findmy`: the same (LinearMouse #1503, on macOS 27.2).
    /// - Calendar `com.apple.iCal`: the month view does not scroll by phased scroll events
    ///   alone, or stutters and runs backwards (LinearMouse #1217, #1290).
    /// - iPhone Mirroring `com.apple.ScreenContinuity`: phased events that do not come from
    ///   a trackpad are not followed (Mos #1045, Mac Mouse Fix #1015).
    /// - Blender `org.blenderfoundation.blender`: the wheel orbits the view instead of
    ///   zooming (Mac Mouse Fix #523).
    /// - The Godot editor `org.godotengine.godot`: the wheel pans instead of zooming (it
    ///   reads the phase to tell the devices apart).
    ///
    /// Where each id comes from: the four Apple apps from their own `Info.plist` on macOS
    /// 27.2 (`/System/Applications/…`); Blender from its source, blender/blender
    /// `release/darwin/Blender.app/Contents/Info.plist`; Godot from godotengine/godot
    /// `misc/dist/macos_tools.app/Contents/Info.plist` (the editor: a game made with Godot
    /// has an id of its own). Autodesk Fusion and Rhino are reported the same way (Mac
    /// Mouse Fix #868, LinearMouse #1502), but their ids could not be confirmed from a
    /// source that can be named, so they are not listed: such an app gets one touch until
    /// its user gives it its own settings in the Apps pane with the switch off.
    static let wheelOnlyBundleIdentifiers: Set<String> = [
        "com.apple.Maps", "com.apple.findmy", "com.apple.iCal", "com.apple.ScreenContinuity",
        "org.blenderfoundation.blender", "org.godotengine.godot",
    ]

    /// An app came to the front. With trackpad-style events on for it, its kind is asked for
    /// now (the look into its bundle runs off the main thread, as always), so that the first
    /// scroll in it already knows. It used to be asked by the first wheel event, and that
    /// scroll (until the answer) went out as for an app that is not known: over a
    /// Chromium-based app as one touch instead of a flick. An app that never comes to
    /// the front (a scroll over a window in the background) is still asked for by its first
    /// wheel event. Main thread.
    func applicationCameToFront(bundleIdentifier: String?, bundleURL: URL?, trackpadStyleOn: Bool) {
        guard trackpadStyleOn, let bundleURL = bundleURL else { return }
        _ = trackpadStyleTarget(bundleIdentifier: bundleIdentifier, bundleURL: bundleURL)
    }

    /// The look into a bundle, as it runs off the main thread: whether the app scrolls by a
    /// glide's events. The folder an alias in Applications points to is judged again: never
    /// outside the folders that may be looked into.
    static func lookFindsGlideFollower(bundleURL: URL, homeDirectory: String = ScrollUtils.homeDirectory) -> Bool {
#if DEBUG
        lookThreadObserverForTests?(Thread.isMainThread)
#endif
        let resolved = bundleURL.resolvingSymlinksInPath()
        return mayLookIntoBundle(atPath: resolved.path, homeDirectory: homeDirectory) && scrollsByGlideEvents(bundleURL: resolved)
    }

#if DEBUG
    /// Tests: called by every look into a bundle with whether it runs on the main thread.
    static var lookThreadObserverForTests: ((Bool) -> Void)?
#endif

    /// Whether an app scrolls by the events of a glide and makes none of its own: the
    /// Chromium engine or the Gecko engine. One look into the bundle: reads the disk, so
    /// never on the main thread (`inspectBundle`).
    static func scrollsByGlideEvents(bundleURL: URL, fileManager: FileManager = .default) -> Bool {
        return isChromiumBased(bundleURL: bundleURL, fileManager: fileManager)
            || isGeckoBased(bundleURL: bundleURL, fileManager: fileManager)
    }

    /// A Gecko-based app carries the engine as one library beside its program:
    /// `Contents/MacOS/XUL` (mozilla-central, `toolkit/library/moz.build`: on macOS the
    /// shared library's name is "XUL"). That is every build of the engine without a list of
    /// names: Firefox and its channels, rebuilds such as LibreWolf, Zen, Tor Browser and
    /// Waterfox, Thunderbird, Zotero. Gecko follows every delta it is sent, touch and glide
    /// alike, and makes no glide of its own (read in its source at two revisions; not seen
    /// on a screen), so it gets the flick as Chromium does.
    static func isGeckoBased(bundleURL: URL, fileManager: FileManager = .default) -> Bool {
        return fileManager.fileExists(atPath: bundleURL.appendingPathComponent("Contents/MacOS/XUL").path)
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
