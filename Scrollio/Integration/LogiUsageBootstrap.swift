//
//  LogiUsageBootstrap.swift
//  Mos
//
//  Pushes Options state into LogiCenter at app launch.
//  Idempotent. Options 订阅驱动: 绑定/热键/应用列表变更时整体刷新 (installOptionsObservers).
//

import Cocoa

enum LogiUsageBootstrap {

    /// 上次推送过 appScroll 用量的 app path, 用于 app 移除后推送空集清理注册表残留
    private static var lastPushedAppPaths: Set<String> = []

    /// The app in front, whose own buttons count for what the mouse gives to Scrollio.
    /// Tests give one of their own.
    static var frontApplication: () -> ShortcutRingChoice.FrontApp? = { .current() }
    /// What the apps' own bindings change in the divert, as the last line of the log said it
    /// (a line only after a change of the settings, and only when this changes).
    private static var lastOwnLogitechButtons = OwnLogitechButtons.none
    /// Writes the line about the apps' own Logitech buttons. Tests give their own.
    static var log: (String) -> Void = { AppSystemLog.note($0) }
    /// The Logitech buttons that are down now (`LogiIntegrationBridge`). Tests give their own.
    static var heldButtonCodes: () -> Set<UInt16> = { LogiIntegrationBridge.shared.heldButtonCodes }
    /// The buttons the bindings had of the mouse at the last refresh.
    private static var lastButtonBindingCodes: Set<UInt16> = []
    /// Buttons that stay with Scrollio only because they were down when the bindings that
    /// count stopped needing them: given back at their release (`buttonWasReleased`).
    private(set) static var keptWhileHeld: Set<UInt16> = []
    private static var frontApplicationObserver: NSObjectProtocol?

    /// 订阅 Options 变更, 集中刷新 Logi 用量 (替代偏好面板各处手动 setUsage)
    static func installOptionsObservers() {
        Options.shared.observe([.buttons, .scroll, .application]) { _ in
            refreshAll()
        }
        // The buttons the mouse gives to Scrollio, and those it tracks for Gesture
        // Navigation, follow the app in front: an app with buttons of its own may need one
        // the general bindings leave to the mouse, or give one back.
        if frontApplicationObserver == nil {
            frontApplicationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { note in
                let application = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                frontApplicationChanged(to: ShortcutRingChoice.FrontApp.current(application))
            }
        }
        // Logitech 滚轮硬件设置 (SmartShift / 灵敏度 / 齿感力度), 见 LogiUsageBootstrap+Wheel
        installWheelObserver()
        // Logitech basic mouse settings (DPI / haptics / press force), see LogiUsageBootstrap+Basics
        installMouseObserver()
        // 手势导航的设备侧位移跟踪 (raw XY), 见 LogiUsageBootstrap+Gesture
        installGestureObserver()
    }

    static func refreshAll() {
        // 1. Button bindings (直读 Options, 不依赖 ButtonUtils 缓存失效的订阅顺序): those
        //    that count while the app in front is.
        refreshButtonUsage(front: frontApplication(), afterASettingsChange: true)

        // 2. Global scroll
        for role in ScrollRole.allCases {
            let codes = globalScrollCodes(role: role)
            LogiCenter.shared.setUsage(source: .globalScroll(role), codes: codes)
        }

        // 3. App scroll
        var currentPaths: Set<String> = []
        let apps = Options.shared.application.applications
        for i in 0..<apps.count {
            guard let app = apps.get(by: i) else { continue }
            currentPaths.insert(app.path)
            for role in ScrollRole.allCases {
                let codes = appScrollCodes(app: app, role: role)
                LogiCenter.shared.setUsage(source: .appScroll(key: app.path, role: role), codes: codes)
            }
        }
        // 3b. 已移除 app 的用量清理
        for stalePath in lastPushedAppPaths.subtracting(currentPaths) {
            for role in ScrollRole.allCases {
                LogiCenter.shared.setUsage(source: .appScroll(key: stalePath, role: role), codes: [])
            }
        }
        lastPushedAppPaths = currentPaths

        // 4. Gesture Navigation 绑定里由鼠标自行跟踪位移的按键 (依赖上面的绑定与热键)
        refreshGestureTracking(afterASettingsChange: true)
    }

    // MARK: - Buttons of the app in front

    /// Another app came to the front: the divert and the buttons the mouse tracks follow
    /// it. Both write nothing to a mouse when their set did not change, and no line in the
    /// log either way (that is for a change of the settings).
    static func frontApplicationChanged(to front: ShortcutRingChoice.FrontApp?) {
        refreshButtonUsage(front: front)
        refreshGestureTracking(front: front)
    }

    /// Tells the mice which of their Logitech buttons Scrollio takes for the bindings that
    /// count while `front` is in front: the general ones with the app's own merged over them
    /// (`ApplicationButtons`). A button no general binding uses is taken only while an app
    /// with its own binding for it is in front, and given back to the mouse when another
    /// app comes; a general one the app sets to "Default" is the mouse's while the app is in
    /// front. Without an app of its own in front this is exactly the general set. The
    /// registry ignores a set that did not change; a change is written to the mouse off the
    /// main thread, as every divert is.
    ///
    /// A button that is down stays with Scrollio until it is up, even when the bindings
    /// that count no longer need it: an app's own "Open App" on a button brings another
    /// app forward while the button is still pressed, and a button given back in the middle
    /// of its press could reach that app as half a press. Its release refreshes again.
    ///
    /// `afterASettingsChange`: the settings changed (the `Options` path), not the app in
    /// front; only then a line in the log.
    static func refreshButtonUsage(front: ShortcutRingChoice.FrontApp?, afterASettingsChange: Bool = false) {
        let general = Options.shared.buttons.binding
        let isLogiCode: (UInt16) -> Bool = { LogiCenter.shared.isLogiCode($0) }
        let applications = Options.shared.application.applications
        let entry = ApplicationButtons.entry(front: front, applications: applications)
        let wanted = buttonBindingCodes(general: general, frontAppOwn: entry?.ownButtonBindings ?? [], isLogiCode: isLogiCode)
        let kept = lastButtonBindingCodes.subtracting(wanted).intersection(heldButtonCodes())
        let codes = wanted.union(kept)
        keptWhileHeld = kept
        lastButtonBindingCodes = codes
        LogiCenter.shared.setUsage(source: .buttonBinding, codes: codes)

        // One line when what the apps' own bindings change is not what the last line said
        // (counts over the list, never which app, whatever app is in front: a change of the
        // settings is made with Scrollio in front), and only after a change of the settings:
        // a line per switch of apps filled the log and kept a trail of the user's switches.
        guard afterASettingsChange else { return }
        let own = ownLogitechButtons(general: general, applications: applications, isLogiCode: isLogiCode)
        guard own != lastOwnLogitechButtons else { return }
        lastOwnLogitechButtons = own
        log(own.line)
    }

    /// What the apps on the list change with bindings of their own in the Logitech buttons
    /// Scrollio takes: how many apps take a button from the mouse or give one back while
    /// they are in front, and how many buttons each way (a button counts once).
    struct OwnLogitechButtons: Equatable {
        static let none = OwnLogitechButtons(apps: 0, taken: 0, givenBack: 0)

        var apps: Int
        var taken: Int
        var givenBack: Int

        /// The log's line (counts only).
        var line: String {
            guard apps > 0 else {
                return "Buttons: no app has its own binding for a Logitech button: the Logitech buttons are as Buttons sets them in every app"
            }
            return "Buttons: \(apps) app(s) have their own binding for a Logitech button: \(taken) Logitech button(s) "
                + "taken from the mouse and \(givenBack) given back while such an app is in front"
        }
    }

    /// `OwnLogitechButtons` for the list: each entry that a press finds for its path (the
    /// last of two entries of one path, `ApplicationButtons.entry`) against `general`.
    static func ownLogitechButtons(
        general: [ButtonBinding], applications: EnhanceArray<Application>, isLogiCode: (UInt16) -> Bool
    ) -> OwnLogitechButtons {
        let generalCodes = buttonBindingCodes(general: general, frontAppOwn: [], isLogiCode: isLogiCode)
        var apps = 0
        var taken: Set<UInt16> = []
        var givenBack: Set<UInt16> = []
        for index in 0..<applications.count {
            guard let entry = applications.get(by: index), entry.hasOwnButtons,
                  applications.get(by: entry.path) === entry else { continue }
            let wanted = buttonBindingCodes(general: general, frontAppOwn: entry.ownButtonBindings, isLogiCode: isLogiCode)
            let takes = wanted.subtracting(generalCodes)
            let givesBack = generalCodes.subtracting(wanted)
            guard !takes.isEmpty || !givesBack.isEmpty else { continue }
            apps += 1
            taken.formUnion(takes)
            givenBack.formUnion(givesBack)
        }
        return OwnLogitechButtons(apps: apps, taken: taken.count, givenBack: givenBack.count)
    }

    /// A Logitech button came up (`LogiIntegrationBridge`): if it stayed with Scrollio, or
    /// kept its tracking, only because it was down, the bindings that count now decide
    /// again, on the next turn of the main queue (after its release went where its press
    /// went).
    static func buttonWasReleased(_ code: UInt16) {
        guard keptWhileHeld.contains(code) || trackingKeptWhileHeld.contains(code) else { return }
        DispatchQueue.main.async {
            frontApplicationChanged(to: frontApplication())
        }
    }

    /// The Logitech buttons the bindings that count while an app is in front use: every
    /// enabled binding of a mouse button, the general ones with `frontAppOwn` merged over
    /// them, except an app's own "Default" (that button does what it does by itself there).
    /// With no own bindings: the codes of the enabled general bindings, as ever.
    static func buttonBindingCodes(
        general: [ButtonBinding], frontAppOwn: [ButtonBinding], isLogiCode: (UInt16) -> Bool
    ) -> Set<UInt16> {
        let own = ApplicationButtons.usable(frontAppOwn, general: general)
        let ownIdentities = own.map(\.identity)
        var codes: Set<UInt16> = []
        for binding in ApplicationButtons.merged(general: general, own: own)
        where binding.isEnabled && binding.triggerEvent.type == .mouse && isLogiCode(binding.triggerEvent.code) {
            if binding.systemShortcutName.isEmpty, ownIdentities.contains(binding.identity) { continue }
            codes.insert(binding.triggerEvent.code)
        }
        return codes
    }

    static func globalScrollCodes(role: ScrollRole) -> Set<UInt16> {
        let hotkey: ScrollHotkey? = {
            switch role {
            case .dash:   return Options.shared.scroll.dash
            case .slow:   return Options.shared.scroll.slow
            case .toggle: return Options.shared.scroll.toggle
            case .block:  return Options.shared.scroll.block
            }
        }()
        guard let h = hotkey, h.type == .mouse, LogiCenter.shared.isLogiCode(h.code) else { return [] }
        return [h.code]
    }

    static func appScrollCodes(app: Application, role: ScrollRole) -> Set<UInt16> {
        guard !app.inherit else { return [] }
        let hotkey: ScrollHotkey? = {
            switch role {
            case .dash:   return app.scroll.dash
            case .slow:   return app.scroll.slow
            case .toggle: return app.scroll.toggle
            case .block:  return app.scroll.block
            }
        }()
        guard let h = hotkey, h.type == .mouse, LogiCenter.shared.isLogiCode(h.code) else { return [] }
        return [h.code]
    }
}
