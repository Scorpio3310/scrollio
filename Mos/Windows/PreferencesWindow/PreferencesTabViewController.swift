//
//  PreferencesTabViewController.swift
//  Mos
//  偏好设置的 TabViewController 容器
//  Created by Caldis on 2017/1/20.
//  Copyright © 2017年 Caldis. All rights reserved.
//

//  Transition 踩坑指南
//  1. NSTabViewController 的层级构成
//  NSTabViewController - NSView - NSTabView - [tabViewItem]
//  NSTabViewController 的尺寸适应规则
//  由于 NSTabViewController 完全适配了 AutoLayout,
//  如果 tabViewItem 使用了 AutoLayout, 且对应宽或高不存在 ambiguous 的情况下, 由于整个 NSTabViewController 内的 view 都设置了对应的  AutoLayout, 因此, 最终的尺寸将自动 pin 至其 tabViewItem 的大小, 且整个 NSWindow 都会自动 Resize
//  如果 tabViewItem 其没有以 AutoLayout 指定尺寸, 则默认为 500,500
//  2. NSTabViewController 的动画适配
//  2.1 tabViewItem 使用了 AutoLayout
//  在切换 Tab 时, NSTabViewController 使用了 transition(from:to:options:completionHandler:) 方法 (方法可能经过重写, 无法通过对应 Protocol 设定其动画, 只能通过 transitionOptions 参数), 在这种情况下无法触发其 transition 动画, 仅能通过手动触发
//  这里 (在 viewDidAppear 中操作可以利用 View 出现时的自动布局, 避免第一次界面错位) 将 NSTabViewController 下的第一级 NSView 的  constraints 全部移除, 然后手动添加, 仅将其 Pin 至 top 和 left 位置 (设置 top 可以让 size 的 transition 出现在底部), 然后在  tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) 方法中获取当前 tabViewItem 的大小, 将其计算偏移量后 apply  到 NSWindow 上
//  2.2 tabViewItem 没有使用 AutoLayout
//  与上述操作类似, 只需要跳过移除已有的 constraints 步骤即可
//  3. 避免动画切换时窗口底部颜色不一致
//  于 NSTabViewController 下的 NSView 额外叠加一层 NSVisualEffectView, 并固定于界面下方, 避免切换时窗口底部颜色不一致

import Cocoa

class PreferencesTabViewController: NSTabViewController {
    
    let backgroundVisualEffectView = NSVisualEffectView()

    override func viewDidLoad() {
        super.viewDidLoad()
        insertCodeBuiltTabs()
    }

    /// Main.storyboard holds General, Scrolling, Buttons and Apps, in that order. The tabs
    /// built in code are added around them: Gestures and Mouse after Buttons, About last.
    private func insertCodeBuiltTabs() {
        let gestures = GesturesPreferencesViewController()
        insertTab(
            gestures,
            identifier: GesturesPreferencesViewController.tabIdentifier,
            image: GesturesPreferencesViewController.tabImage(),
            after: PANEL_IDENTIFIER.buttons
        )
        let mouse = MousePreferencesViewController()
        insertTab(
            mouse,
            identifier: MousePreferencesViewController.tabIdentifier,
            image: MousePreferencesViewController.tabImage(),
            after: GesturesPreferencesViewController.tabIdentifier
        )
        let about = AboutPreferencesViewController()
        insertTab(
            about,
            identifier: AboutPreferencesViewController.tabIdentifier,
            image: AboutPreferencesViewController.tabImage(),
            after: nil
        )
    }

    /// Adds a tab for `controller` after the tab `anchor`, or at the end.
    private func insertTab(_ controller: NSViewController, identifier: String, image: NSImage?, after anchor: String?) {
        guard !tabViewItems.contains(where: { ($0.identifier as? String) == identifier }) else { return }
        let item = NSTabViewItem(viewController: controller)
        item.identifier = identifier
        item.label = controller.title ?? ""
        item.image = image
        let anchorIndex = anchor.flatMap { anchor in
            tabViewItems.firstIndex { ($0.identifier as? String) == anchor }
        }
        insertTabViewItem(item, at: anchorIndex.map { $0 + 1 } ?? tabViewItems.count)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        removeToolbarFlexibleSpaces()
        updateWindowTitle()
    }

    /// PreferencesWindowController spreads the tabs with flexible spaces. With the Mouse tab
    /// added those spaces can push About into the toolbar's overflow menu at the 450 pt window
    /// width, so the tabs sit side by side instead (still centred). Runs after windowDidLoad.
    func removeToolbarFlexibleSpaces() {
        guard let toolbar = view.window?.toolbar else { return }
        for index in toolbar.items.indices.reversed() where toolbar.items[index].itemIdentifier == .flexibleSpace {
            toolbar.removeItem(at: index)
        }
    }

    override func viewDidAppear() {
        // 移除已有约束
        view.removeConstraints(view.constraints)
        // 将 tabView 固定于界面左上
        tabView.topAnchor.constraint(equalTo: view.topAnchor, constant: 0).isActive = true
        tabView.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 0).isActive = true
        // 额外叠加一层 NSVisualEffectView, 并固定于界面下方, 避免切换时窗口底部颜色不一致
        backgroundVisualEffectView.blendingMode = NSVisualEffectView.BlendingMode.behindWindow
        backgroundVisualEffectView.material = NSVisualEffectView.Material.toolTip
        view.addSubview(backgroundVisualEffectView, positioned: NSWindow.OrderingMode.below, relativeTo: tabView)
        backgroundVisualEffectView.frame.size = NSSize(width: 1000, height: 1000) // 只要比预期内容大就行, 不会有额外占用
        backgroundVisualEffectView.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 0).isActive = true
        backgroundVisualEffectView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 0).isActive = true        
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        updateWindowTitle()
        // Tab 切换后同步窗口尺寸
        updateWindowSize()
    }

    /// The window is named after the pane it shows, as in System Settings.
    func updateWindowTitle() {
        guard let window = view.window,
              tabViewItems.indices.contains(selectedTabViewItemIndex) else { return }
        let label = tabViewItems[selectedTabViewItemIndex].label
        if !label.isEmpty {
            window.title = label
        }
    }

    // 更新窗口尺寸以适应当前内容
    func updateWindowSize() {
        if let currentWindow = view.window, let currentContentView = tabView.subviews.first {
            let windowSize = currentWindow.frame.size
            let contentSize = currentContentView.frame.size
            let heightDiff = contentSize.height + TOOLBAR_HEIGHT + MACOS_TAHOE_COMPENSATE - windowSize.height
            let targetOrigin = NSPoint(x: currentWindow.frame.origin.x, y: currentWindow.frame.origin.y - heightDiff)
            let targetSize = NSSize(width: contentSize.width, height: contentSize.height + TOOLBAR_HEIGHT + MACOS_TAHOE_COMPENSATE)
            let targetRect = NSRect(origin: targetOrigin, size: targetSize)
            Utils.groupAnimatorContainer({(context) in
                currentWindow.setFrame(targetRect, display: true)
            })
        }
    }
}
