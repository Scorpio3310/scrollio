//
//  Utils.swift
//  Mos
//  实用方法
//  Created by Caldis on 2017/3/24.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

// 实用方法
public class Utils {

    /// Determines whether the app is currently in Dark Mode.
    /// - Parameter view: Unused; kept for the callers (it helped on macOS 10.13 and earlier).
    /// - Returns: `true` if the effective appearance is dark-like, otherwise `false`.
    class func isDarkMode(for view: NSView?) -> Bool {
        return NSApp.effectiveAppearance
            .bestMatch(
                from: [
                    .darkAqua,
                    .vibrantDark,
                    .accessibilityHighContrastDarkAqua,
                    .accessibilityHighContrastVibrantDark
                ]
            ) != nil
    }


    // 切换自启 (SMAppService.mainApp, 见 LoginItem.swift)
    class func launchAtStartup(on: Bool) {
        LoginItem.setEnabled(on)
    }
    
    // 动画
    // 需要设置 allowsImplicitAnimation = true 才能让 contentSize 有动画, https://stackoverflow.com/a/46946957/6727040
    class func groupAnimatorContainer(_ group: (NSAnimationContext?)->Void, completionHandler: @escaping ()->Void = {()}) {
        NSAnimationContext.runAnimationGroup({ (context) -> Void in
            context.duration = ANIMATION.duration
            context.allowsImplicitAnimation = true
            group(context)
        }, completionHandler: completionHandler)
    }
    class func groupAnimatorContainer(_ group: (NSAnimationContext?)->Void, headHandler: @escaping ()->Void = {()}, completionHandler: @escaping ()->Void = {()}) {
        headHandler()
        groupAnimatorContainer(group, completionHandler: completionHandler)
    }
    
    // 禁止重复运行
    // killExist = true 则杀掉已有进程, 否则自杀
    /// With `killExist`, another running copy of this app is asked to quit and waited for (at
    /// most `timeout`, then force-quit), the way LegacyAppQuitter quits the old Mos: until it
    /// is gone both copies would run event taps and Logitech sessions, bound actions could fire
    /// twice and the old copy's answers to its teardown writes would confuse this one. Call it
    /// before any event tap or Logitech session starts; it blocks the main thread meanwhile.
    ///
    /// Only a copy that started later replaces one that started earlier. Two copies that
    /// start together (both login items, an old one in ~/Applications and the new one in
    /// /Applications) each used to ask the other to quit and then wait with a blocked main
    /// thread, so neither could answer: 3 s lost at every login, and when both reached the
    /// force-quit in the same moment, no Scrollio was left. Now the earlier of the two does
    /// not wait: it goes on, and quits when the later one asks.
    class func preventMultiRunning(killExist kill: Bool = false, timeout: TimeInterval = 3.0) {
        guard let mainBundleID = Bundle.main.bundleIdentifier else { return }
        let everyCopy = NSRunningApplication.runningApplications(withBundleIdentifier: mainBundleID)
        let own = ProcessInfo.processInfo.processIdentifier
        guard !otherInstanceProcessIdentifiers(running: everyCopy.map { $0.processIdentifier }, own: own).isEmpty else { return }
        if kill {
            let ownLaunch = NSRunningApplication.current.launchDate
            let others = everyCopy.filter { $0.processIdentifier != own }
            let earlier = others.filter {
                startedEarlier(other: ($0.processIdentifier, $0.launchDate), thanOwn: (own, ownLaunch))
            }
            if earlier.count < others.count {
                AppSystemLog.note("Another copy of Scrollio started after this one: not waiting for it, it replaces this one")
            }
            guard !earlier.isEmpty else { return }
            let outcome = quitOtherInstances(earlier, own: own, timeout: timeout)
            let quitWhenAsked = outcome.forced.isEmpty && outcome.stillRunning.isEmpty
            for line in otherInstanceLines(outcome, timeout: timeout) {
                if quitWhenAsked {
                    AppSystemLog.note(line)
                } else {
                    AppSystemLog.problem(line)
                }
            }
        } else {
            AppSystemLog.note("Another copy of Scrollio runs: this one quits")
            NSApp.terminate(nil)
        }
    }

    /// Whether another copy started before this one, so this one replaces it: by the launch
    /// time, and by the process id when the times are equal or one is unknown (the lower id
    /// counts as earlier). Exactly one of two copies answers true about the other. Pure.
    class func startedEarlier(
        other: (pid: pid_t, launched: Date?),
        thanOwn own: (pid: pid_t, launched: Date?)
    ) -> Bool {
        if let otherLaunch = other.launched, let ownLaunch = own.launched, otherLaunch != ownLaunch {
            return otherLaunch < ownLaunch
        }
        return other.pid < own.pid
    }

    /// Asks the other copies in `running` to quit and waits for them (LegacyAppQuitter's
    /// quitAndWait). Never this process.
    class func quitOtherInstances(
        _ running: [LegacyAppHandle],
        own: pid_t,
        timeout: TimeInterval = 3.0,
        forceTimeout: TimeInterval = 1.0,
        isAlive: (LegacyAppHandle) -> Bool = { LegacyAppQuitter.isProcessAlive($0.processIdentifier) }
    ) -> LegacyAppQuitter.QuitOutcome {
        let others = otherInstanceProcessIdentifiers(running: running.map { $0.processIdentifier }, own: own)
        let targets = running.filter { others.contains($0.processIdentifier) }
        return LegacyAppQuitter.quitAndWait(targets, timeout: timeout, forceTimeout: forceTimeout, isAlive: isAlive)
    }

    /// What the log says about replacing the other copies.
    class func otherInstanceLines(_ outcome: LegacyAppQuitter.QuitOutcome, timeout: TimeInterval) -> [String] {
        let waited = String(format: "%.1f s", outcome.waited)
        var lines: [String] = []
        for pid in outcome.quit {
            lines.append("Another copy of Scrollio was running (pid \(pid)): it quit when asked, after \(waited); "
                + "this one starts now")
        }
        for pid in outcome.forced {
            lines.append("Another copy of Scrollio (pid \(pid)) did not quit within \(Int(timeout)) s: forced it to quit "
                + "(\(waited) in all); this one starts now")
        }
        for pid in outcome.stillRunning {
            lines.append("Another copy of Scrollio (pid \(pid)) still runs after it was forced to quit (\(waited)); "
                + "this one starts anyway")
        }
        return lines
    }
    /// Process ids of the other running copies of this app. Never contains `own`: the list
    /// from NSRunningApplication includes this process, in no guaranteed position, and
    /// "terminate the first one" could pick the instance that is starting up.
    class func otherInstanceProcessIdentifiers(running: [pid_t], own: pid_t) -> [pid_t] {
        return running.filter { $0 != own }
    }
    
    // 从 StoryBroad 获取一个特定 Controller 的实例
    private static let storyboard = NSStoryboard(name: "Main", bundle: nil)
    class func instantiateControllerFromStoryboard<Controller>(withIdentifier identifier: String) -> Controller {
        let id = identifier
        guard let controller = storyboard.instantiateController(withIdentifier: id) as? Controller else {
            fatalError("Can't find Controller: \(id)")
        }
        return controller
    }
    
    // 辅助功能权限相关
    // 来源: http://see.sl088.com/wiki/Mac%E5%BC%80%E5%8F%91_%E8%BE%85%E5%8A%A9%E5%8A%9F%E8%83%BD%E6%9D%83%E9%99%90
    // 查询是否有辅助功能权限
    class func isHadAccessibilityPermissions() -> Bool{
        return AXIsProcessTrusted()
    }
    // 申请辅助功能权限
    class func requireAccessibilityPermissions() {
        let trusted = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let privOptions = [trusted: true] as CFDictionary
        AXIsProcessTrustedWithOptions(privOptions)
    }
    
    // Dock 图标控制
    static var isDockIconVisible = false
    class func showDockIcon() {
        if !Utils.isDockIconVisible {
            NSApp.setActivationPolicy(NSApplication.ActivationPolicy.regular)
            isDockIconVisible = true
        }
    }
    /// Something besides the app's own windows needs the Dock icon: the updater, while a
    /// found update waits for the user's answer. A test replaces it.
    static var dockIconIsHeld: () -> Bool = { UpdateCenter.shared.holdsDockIcon }
    class func hideDockIcon() {
        if WindowManager.shared.refs.count == 1 && !dockIconIsHeld() {
            NSApp.setActivationPolicy(NSApplication.ActivationPolicy.accessory)
            isDockIconVisible = false
        }
    }
    /// The updater no longer needs the Dock icon: Scrollio leaves the Dock, unless one of
    /// its own windows is open (its closing does that then).
    class func releaseDockIcon() {
        guard isDockIconVisible, !hasOpenWindow(WindowManager.shared.refs.values.map { $0.window }) else { return }
        NSApp.setActivationPolicy(NSApplication.ActivationPolicy.accessory)
        isDockIconVisible = false
    }
    /// One of these windows is on screen (a minimized one counts). Pure.
    static func hasOpenWindow(_ windows: [NSWindow?]) -> Bool {
        return windows.contains { window in
            guard let window else { return false }
            return window.isVisible || window.isMiniaturized
        }
    }
    
    // 匹配字符
    class func extractRegexMatches(target: String = "", pattern: String) -> String {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            let range = NSRange(location: 0, length: target.count)
            let result = regex.firstMatch(in: target, options: [], range: range)
            if let validResult = result {
                return NSString(string: target).substring(with: validResult.range) as String
            } else {
                return target
            }
        } catch {
            return target
        }
    }
    // 移除字符
    class func removingRegexMatches(target: String = "", pattern: String, replaceWith: String = "") -> String {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            // NSRegularExpression operates on the UTF-16 view, so the range length must be the
            // UTF-16 unit count, not String.count (grapheme clusters). For strings containing
            // astral-plane characters (e.g. emoji in an app display name) the two differ and
            // grapheme-cluster length clips the trailing units, so the suffix fails to match.
            let range = NSRange(location: 0, length: target.utf16.count)
            return regex.stringByReplacingMatches(in: target, options: [], range: range, withTemplate: replaceWith)
        } catch {
            return target
        }
    }
    
    // 从路径获取应用图标
    class func getApplicationIcon(fromPath path: String?) -> NSImage {
        guard let validPath = path else {
            return NSWorkspace.shared.icon(forFile: "")
        }
        // 尝试完整路径对应的 Bundle 获取
        if let validBundle = Bundle.init(url: URL.init(fileURLWithPath: validPath)) {
            return NSWorkspace.shared.icon(forFile: validBundle.bundlePath)
        }
        // 尝试从子路径对应的 Bundle 获取
        let subPath = extractRegexMatches(target: validPath, pattern: #"\/?.*\.app"#)
        if let validBundle = Bundle.init(url: URL.init(fileURLWithPath: subPath)) {
            return NSWorkspace.shared.icon(forFile: validBundle.bundlePath)
        }
        // 从 Path 关联的 Bundle 获取
        return NSWorkspace.shared.icon(forFile: validPath)
    }
    // 从路径获取应用名称
    class func getApplicationName(fromPath path: String?) -> String {
        guard let validPath = path else {
            return "Invalid Name"
        }
        // 尝试完整路径对应的 Bundle 获取
        if let validBundle = Bundle.init(url: URL.init(fileURLWithPath: validPath)) {
            return (
                validBundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
                validBundle.object(forInfoDictionaryKey: "CFBundleName") as? String ??
                parseName(fromPath: validPath)
            )
        }
        // 尝试从子路径对应的 Bundle 获取
        let subPath = extractRegexMatches(target: validPath, pattern: #"\/?.*\.app"#)
        if let validBundle = Bundle.init(url: URL.init(fileURLWithPath: subPath)) {
            return (
                validBundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
                validBundle.object(forInfoDictionaryKey: "CFBundleName") as? String ??
                parseName(fromPath: validPath)
            )
        }
        return parseName(fromPath: validPath)
    }
    class func parseName(fromPath path: String) -> String {
        let displayName = FileManager().displayName(atPath: path)
        // removingPercentEncoding is nil for a name with a stray "%" ("50% Off.app").
        let applicationRawName = displayName.removingPercentEncoding ?? displayName
        // Only the extension: a bare ".app" pattern also matches inside names ("Snapper").
        return Utils.removingRegexMatches(target: applicationRawName, pattern: "\\.app$")
    }
    
    static var runningApplicationThreshold = 60.0
    static var runningApplicationCache = [String: NSRunningApplication]()
    static var runningApplicationDetectTime = [String: Double]()
    class func getRunningApplicationProcessIdentifier(withBundleIdentifier bundleIdentifier: String) -> NSRunningApplication? {
        let now = NSDate().timeIntervalSince1970
        if now - (runningApplicationDetectTime[bundleIdentifier] ?? 0.0) > runningApplicationThreshold {
            let runningApplications = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            runningApplicationCache[bundleIdentifier] = runningApplications.count > 0 ? runningApplications[0] : nil
            runningApplicationDetectTime[bundleIdentifier] = now
        }
        return runningApplicationCache[bundleIdentifier] ?? nil
    }
}

/// DEBUG 下断言当前在主线程; Release 零开销。
/// 核心事件域 (ScrollCore 热键状态 / InputProcessor 绑定表 / ButtonUtils 缓存) 约定主线程 only,
/// 当前所有 CGEventTap 与 IOHIDManager 回调均调度于主 RunLoop。固化该隐式约定 (架构评估 P2-1)。
@inline(__always)
func assertMainThread(_ message: @autoclosure () -> String = "must run on main thread",
                      file: StaticString = #fileID, line: UInt = #line) {
    #if DEBUG
    assert(Thread.isMainThread, message(), file: file, line: line)
    #endif
}
