//
//  PreferencesScrollingViewController.swift
//  Mos
//  滚动选项界面
//  Created by Caldis on 2017/1/26.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

class PreferencesScrollingViewController: NSViewController, ScrollOptionsContextProviding {

    // Target application
    // - Using when the VC is inside the Application Setting Popup
    var currentTargetApplication: Application?
    // UI Elements
    @IBOutlet weak var scrollSmoothCheckBox: NSButton!
    @IBOutlet weak var scrollReverseCheckBox: NSButton!
    @IBOutlet weak var dashKeyBindButton: NSButton!
    @IBOutlet weak var dashKeyDelButton: NSButton!
    @IBOutlet weak var toggleKeyBindButton: NSButton!
    @IBOutlet weak var toggleKeyDelButton: NSButton!
    @IBOutlet weak var disableKeyBindButton: NSButton!
    @IBOutlet weak var disableKeyDelButton: NSButton!
    @IBOutlet weak var scrollStepSlider: NSSlider!
    @IBOutlet weak var scrollStepInput: NSTextField!
    @IBOutlet weak var scrollStepStepper: NSStepper!
    @IBOutlet weak var scrollSpeedSlider: NSSlider!
    @IBOutlet weak var scrollSpeedInput: NSTextField!
    @IBOutlet weak var scrollSpeedStepper: NSStepper!
    @IBOutlet weak var scrollDurationSlider: NSSlider!
    @IBOutlet weak var scrollDurationInput: NSTextField!
    @IBOutlet weak var scrollDurationStepper: NSStepper!
    @IBOutlet weak var scrollDurationDescriptionLabel: NSTextField?
    @IBOutlet weak var resetToDefaultsButton: NSButton!
    var resetButtonHeightConstraint: NSLayoutConstraint?
    // 快速滚动 (预设 / free-spin / 加速度) 入口, 代码创建并插在时长说明与重置按钮之间
    private var scrollTuningButton: NSButton?
    private var scrollTuningButtonHeightConstraint: NSLayoutConstraint?
    private var scrollTuningPopover: ScrollTuningSettingsPopover?
    private static let scrollTuningButtonHeight: CGFloat = 24
    // Constants
    let DefaultConfigForCompare = OPTIONS_SCROLL_DEFAULT()
    private var scrollDurationDescriptionDefaultText: String?
    private let scrollDurationLockedDescription = NSLocalizedString(
        "scrollDurationLockedMessage",
        comment: "Message shown when simulate trackpad locks the duration setting"
    )
    // KeyRecorder for custom hotkey recording
    private let keyRecorder = KeyRecorder()
    private weak var currentRecordingPopup: NSButton?

    override func viewDidLoad() {
        // 禁止自动 Focus
        scrollStepInput.refusesFirstResponder = true
        scrollSpeedInput.refusesFirstResponder = true
        scrollDurationInput.refusesFirstResponder = true
        // 创建高度约束
        resetButtonHeightConstraint = resetToDefaultsButton.heightAnchor.constraint(equalToConstant: 24)
        resetButtonHeightConstraint?.isActive = true
        scrollDurationDescriptionDefaultText = scrollDurationDescriptionLabel?.stringValue
        // 设置 KeyRecorder 代理
        keyRecorder.delegate = self
        // 快速滚动入口
        installScrollTuningButton()
        // 读取设置
        syncViewWithOptions()
    }

    /// Inserts the "Presets & Fast Scrolling…" button between the duration description and
    /// the reset button by re-pinning the reset button's top constraint.
    private func installScrollTuningButton() {
        guard let anchor = scrollDurationDescriptionLabel,
              let container = resetToDefaultsButton.superview,
              let resetTop = container.constraints.first(where: {
                  ($0.firstItem as? NSView) === resetToDefaultsButton && $0.firstAttribute == .top
              }) else { return }

        let button = NSButton(
            title: NSLocalizedString("scroll-tuning-button", comment: ""),
            target: self,
            action: #selector(scrollTuningClick(_:))
        )
        button.bezelStyle = .rounded
        button.translatesAutoresizingMaskIntoConstraints = false
        if #available(macOS 11.0, *) {
            button.image = NSImage(systemSymbolName: "speedometer", accessibilityDescription: nil)
            button.imagePosition = .imageLeading
        }
        container.addSubview(button)

        let height = button.heightAnchor.constraint(equalToConstant: Self.scrollTuningButtonHeight)
        resetTop.isActive = false
        NSLayoutConstraint.activate([
            height,
            button.topAnchor.constraint(equalTo: anchor.bottomAnchor, constant: 14),
            button.leadingAnchor.constraint(equalTo: anchor.leadingAnchor),
            resetToDefaultsButton.topAnchor.constraint(equalTo: button.bottomAnchor, constant: 14),
        ])
        scrollTuningButton = button
        scrollTuningButtonHeightConstraint = height
    }

    @objc private func scrollTuningClick(_ sender: NSButton) {
        let popover = ScrollTuningSettingsPopover()
        popover.onSettingsChanged = { [weak self] in
            self?.syncViewWithOptions()
        }
        popover.onClose = { [weak self, weak popover] in
            guard let self, self.scrollTuningPopover === popover else { return }
            self.scrollTuningPopover = nil
        }
        scrollTuningPopover = popover
        popover.show(at: sender)
    }

    /// The tuning is global, so the entry is hidden in per-app scroll settings.
    private func updateScrollTuningButtonVisibility() {
        let visible = currentTargetApplication == nil
        scrollTuningButton?.isHidden = !visible
        scrollTuningButtonHeightConstraint?.constant = visible ? Self.scrollTuningButtonHeight : 0
    }

    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)
        if let smoothPopover = segue.destinationController as? ScrollSmoothDetailSettingsPopoverViewController {
            smoothPopover.currentTargetApplication = currentTargetApplication
            smoothPopover.onOptionsChanged = { [weak self] in
                self?.syncViewWithOptions()
            }
        } else if let reversePopover = segue.destinationController as? ScrollReverseDetailSettingsPopoverViewController {
            reversePopover.currentTargetApplication = currentTargetApplication
            reversePopover.onOptionsChanged = { [weak self] in
                self?.syncViewWithOptions()
            }
        }
    }
    
    // 平滑
    @IBAction func scrollSmoothClick(_ sender: NSButton) {
        getTargetApplicationScrollOptions().smooth = sender.state.rawValue != 0
        syncViewWithOptions()
    }

    // 翻转
    @IBAction func scrollReverseClick(_ sender: NSButton) {
        getTargetApplicationScrollOptions().reverse = sender.state.rawValue != 0
        syncViewWithOptions()
    }
    
    // 加速键 - 点击触发录制
    @IBAction func dashKeyButtonClick(_ sender: NSButton) {
        currentRecordingPopup = sender
        keyRecorder.startRecording(from: sender, mode: .singleKey)
    }
    // 加速键 - 清除绑定
    @IBAction func dashKeyDelButtonClick(_ sender: NSButton) {
        getTargetApplicationScrollOptions().dash = nil
        syncViewWithOptions()
    }
    // 转换键 - 点击触发录制
    @IBAction func toggleKeyButtonClick(_ sender: NSButton) {
        currentRecordingPopup = sender
        keyRecorder.startRecording(from: sender, mode: .singleKey)
    }
    // 转换键 - 清除绑定
    @IBAction func toggleKeyDelButtonClick(_ sender: NSButton) {
        getTargetApplicationScrollOptions().toggle = nil
        syncViewWithOptions()
    }
    // 禁用键 - 点击触发录制
    @IBAction func disableKeyButtonClick(_ sender: NSButton) {
        currentRecordingPopup = sender
        keyRecorder.startRecording(from: sender, mode: .singleKey)
    }
    // 禁用键 - 清除绑定
    @IBAction func disableKeyDelButtonClick(_ sender: NSButton) {
        getTargetApplicationScrollOptions().block = nil
        syncViewWithOptions()
    }
    
    // 步长
    @IBAction func scrollStepSliderChange(_ sender: NSSlider) {
        setScrollStep(value: sender.doubleValue)
    }
    @IBAction func scrollStepInputChange(_ sender: NSTextField) {
        setScrollStep(value: sender.doubleValue)
    }
    @IBAction func scrollStepStepperChange(_ sender: NSStepper) {
        setScrollStep(value: sender.doubleValue)
    }
    func setScrollStep(value: Double) {
        getTargetApplicationScrollOptions().step = value
        syncViewWithOptions()
    }
    
    // 速度
    @IBAction func scrollSpeedSliderChange(_ sender: NSSlider) {
        setScrollSpeed(value: sender.doubleValue)
    }
    @IBAction func scrollSpeedInputChange(_ sender: NSTextField) {
        setScrollSpeed(value: sender.doubleValue)
    }
    @IBAction func scrollSpeedStepperChange(_ sender: NSStepper) {
        setScrollSpeed(value: sender.doubleValue)
    }
    func setScrollSpeed(value: Double) {
        getTargetApplicationScrollOptions().speed = value
        syncViewWithOptions()
    }
    
    // 过渡
    @IBAction func scrollDurationSliderChange(_ sender: NSSlider) {
        setScrollDuration(value: sender.doubleValue)
    }
    @IBAction func scrollDurationInputChange(_ sender: NSTextField) {
        setScrollDuration(value: sender.doubleValue)
    }
    @IBAction func scrollDurationStepperChange(_ sender: NSStepper) {
        setScrollDuration(value: sender.doubleValue)
    }
    func setScrollDuration(value: Double) {
        let scrollOptions = getTargetApplicationScrollOptions()
        if scrollOptions.smoothSimTrackpad {
            scrollOptions.duration = ScrollDurationLimits.simulateTrackpadDefault
        } else {
            scrollOptions.duration = value
        }
        syncViewWithOptions()
    }
    
    // 重置
    // 全局配置同时重置快速滚动设置 (预设 / free-spin / 加速度); 分应用配置只有滚动选项
    @IBAction func resetToDefaultClick(_ sender: NSButton) {
        if let target = currentTargetApplication {
            target.scroll = OPTIONS_SCROLL_DEFAULT()
        } else {
            Options.shared.scroll = OPTIONS_SCROLL_DEFAULT()
            Options.shared.scrollTuning = ScrollTuningSettings.default
        }
        syncViewWithOptions()
    }

}

/**
 * 工具函数
 **/
extension PreferencesScrollingViewController {
    // 同步界面与设置
    func syncViewWithOptions() {
        // 是否继承配置
        let isNotInherit = !isTargetApplicationInheritOptions()
        // 滚动配置
        let scroll = getTargetApplicationScrollOptions()
        // 平滑
        scrollSmoothCheckBox.state = NSControl.StateValue(rawValue: scroll.smooth ? 1 : 0)
        scrollSmoothCheckBox.isEnabled = isNotInherit
        // 翻转
        scrollReverseCheckBox.state = NSControl.StateValue(rawValue: scroll.reverse ? 1 : 0)
        scrollReverseCheckBox.isEnabled = isNotInherit
        // 加速键
        updateHotkeyButton(dashKeyBindButton, delButton: dashKeyDelButton, hotkey: scroll.dash, enabled: isNotInherit)
        // 转换键
        updateHotkeyButton(toggleKeyBindButton, delButton: toggleKeyDelButton, hotkey: scroll.toggle, enabled: isNotInherit)
        // 禁用键
        updateHotkeyButton(disableKeyBindButton, delButton: disableKeyDelButton, hotkey: scroll.block, enabled: isNotInherit)
        // 步长
        let step = scroll.step
        scrollStepSlider.doubleValue = step
        scrollStepSlider.isEnabled = isNotInherit
        scrollStepStepper.doubleValue = step
        scrollStepStepper.isEnabled = isNotInherit
        scrollStepInput.stringValue = String(format: "%.2f", step)
        scrollStepInput.isEnabled = isNotInherit
        // 速度
        let speed = scroll.speed
        scrollSpeedSlider.doubleValue = speed
        scrollSpeedSlider.isEnabled = isNotInherit
        scrollSpeedStepper.doubleValue = speed
        scrollSpeedStepper.isEnabled = isNotInherit
        scrollSpeedInput.stringValue = String(format: "%.2f", speed)
        scrollSpeedInput.isEnabled = isNotInherit
        // 过渡
        let isSimTrackpadEnabled = scroll.smoothSimTrackpad
        let resolvedDuration: Double
        if isSimTrackpadEnabled {
            resolvedDuration = ScrollDurationLimits.simulateTrackpadDefault
            if scroll.duration != resolvedDuration {
                scroll.duration = resolvedDuration
            }
        } else {
            resolvedDuration = scroll.duration
        }
        scrollDurationSlider.doubleValue = resolvedDuration
        scrollDurationSlider.isEnabled = isNotInherit && !isSimTrackpadEnabled
        scrollDurationStepper.doubleValue = resolvedDuration
        scrollDurationStepper.isEnabled = isNotInherit && !isSimTrackpadEnabled
        scrollDurationInput.stringValue = String(format: "%.2f", resolvedDuration)
        scrollDurationInput.isEnabled = isNotInherit && !isSimTrackpadEnabled
        if isSimTrackpadEnabled {
            scrollDurationDescriptionLabel?.stringValue = scrollDurationLockedDescription
        } else if let defaultText = scrollDurationDescriptionDefaultText {
            scrollDurationDescriptionLabel?.stringValue = defaultText
        }
        // 快速滚动入口仅在全局配置中显示
        updateScrollTuningButtonVisibility()
        // 更新重置按钮状态
        updateResetButtonState()
    }
    /// 是否有可重置的改动: 滚动选项偏离默认值, 或 (仅全局配置) 快速滚动设置偏离默认值
    var hasSettingsToReset: Bool {
        guard !isTargetApplicationInheritOptions() else { return false }
        if getTargetApplicationScrollOptions() != DefaultConfigForCompare { return true }
        return currentTargetApplication == nil && Options.shared.scrollTuning != ScrollTuningSettings.default
    }
    // 更新重置按钮状态与显示
    func updateResetButtonState() {
        let shouldShowResetButton = hasSettingsToReset
        // 动画过渡
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = ANIMATION.duration
            context.allowsImplicitAnimation = true
            resetToDefaultsButton.animator().isEnabled = shouldShowResetButton
            resetToDefaultsButton.animator().alphaValue = shouldShowResetButton ? 1.0 : 0.0
            resetButtonHeightConstraint?.animator().constant = shouldShowResetButton ? 24 : 0
        }, completionHandler: {
            // 触发父视图窗口尺寸更新
            self.view.needsLayout = true
            self.view.layout()
            (self.parent as? PreferencesTabViewController)?.updateWindowSize()
        })
    }

    /// 键盘按键的完整名称映射 (仅用于 ScrollingView 按钮显示)
    private static let keyFullNames: [UInt16: String] = [
        // 修饰键
        KeyCode.commandL: "⌘ Command",
        KeyCode.commandR: "⌘ Command",
        KeyCode.optionL: "⌥ Option",
        KeyCode.optionR: "⌥ Option",
        KeyCode.shiftL: "⇧ Shift",
        KeyCode.shiftR: "⇧ Shift",
        KeyCode.controlL: "⌃ Control",
        KeyCode.controlR: "⌃ Control",
        KeyCode.fnL: "Fn",
        KeyCode.fnR: "Fn",
        // 特殊键
        49: "⎵ Space",
        51: "⌫ Delete",
        53: "⎋ Escape",
        36: "↩ Return",
        76: "↩ Return",
        48: "↹ Tab",
    ]

    /// 获取 ScrollHotkey 的完整显示名称
    /// 获取按键基础名称 (不含品牌前缀)
    private func getBaseDisplayName(for hotkey: ScrollHotkey) -> String {
        switch hotkey.type {
        case .keyboard:
            if let fullName = PreferencesScrollingViewController.keyFullNames[hotkey.code] {
                return fullName
            }
            return KeyCode.keyMap[hotkey.code] ?? "Key \(hotkey.code)"
        case .mouse:
            if LogiCenter.shared.isLogiCode(hotkey.code) {
                return (LogiCenter.shared.name(forMosCode: hotkey.code) ?? "")
            }
            return KeyCode.mouseMap[hotkey.code] ?? "🖱\(hotkey.code)"
        }
    }

    /// 获取完整显示名称 (含品牌前缀, 用于纯文本场景)
    private func getFullDisplayName(for hotkey: ScrollHotkey) -> String {
        let baseName = getBaseDisplayName(for: hotkey)
        if let brand = BrandTag.brandForCode(hotkey.code) {
            return BrandTag.prefixedName(baseName, brand: brand)
        }
        return baseName
    }

    /// 更新热键按钮的显示文本和删除按钮可见性
    private func updateHotkeyButton(_ button: NSButton?, delButton: NSButton?, hotkey: ScrollHotkey?, enabled: Bool) {
        guard let button = button else { return }

        let hasBound = hotkey != nil

        // 设置按钮标题
        if let hotkey = hotkey {
            let baseName = getBaseDisplayName(for: hotkey)
            if let brand = BrandTag.brandForCode(hotkey.code) {
                // 品牌按键: image=tag, title=名称, 左图右文
                button.image = BrandTag.createTagImage(brand: brand, fontSize: 7, height: 14, padH: 5, marginRight: 4)
                button.imagePosition = .imageLeft
                button.title = baseName
            } else {
                button.image = nil
                button.imagePosition = .noImage
                button.title = getFullDisplayName(for: hotkey)
            }
        } else {
            button.image = nil
            button.imagePosition = .noImage
            button.title = NSLocalizedString("Disabled", comment: "Hotkey disabled state")
        }

        button.isEnabled = enabled

        // 设置删除按钮可见性：仅在有绑定且启用时显示
        delButton?.alphaValue = (hasBound && enabled) ? 1.0 : 0.0
        delButton?.isEnabled = hasBound && enabled
    }
}

// MARK: - KeyRecorderDelegate
extension PreferencesScrollingViewController: KeyRecorderDelegate {
    func onEventRecorded(_ recorder: KeyRecorder, didRecordEvent event: InputEvent, isDuplicate: Bool) {
        guard let popup = currentRecordingPopup else { return }

        let hotkey = ScrollHotkey(from: event)

        if popup === dashKeyBindButton {
            getTargetApplicationScrollOptions().dash = hotkey
        } else if popup === toggleKeyBindButton {
            getTargetApplicationScrollOptions().toggle = hotkey
        } else if popup === disableKeyBindButton {
            getTargetApplicationScrollOptions().block = hotkey
        }

        currentRecordingPopup = nil
        syncViewWithOptions()
    }
}
