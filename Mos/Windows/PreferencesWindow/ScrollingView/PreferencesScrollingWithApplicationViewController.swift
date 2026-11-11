//
//  PreferencesScrollingWithApplicationViewController.swift
//  Mos
//  滚动窗口容器
//  Created by Caldis on 31/10/2019.
//  Copyright © 2019 Caldis. All rights reserved.
//

import Cocoa

class PreferencesScrollingWithApplicationViewController: NSViewController {
    
    // Parent view
    private var parentTableView: NSTableView?
    private var parentTableRow: Int!
    // Target application
    private var currentTargetApplication: Application?
    private var currentContentViewController: PreferencesScrollingViewController?
    /// Height of what sits above the scroll settings (see `fitToContent`).
    private var headerHeight: CGFloat?
    // UI Elements
    @IBOutlet weak var currentTargetApplicationIcon: NSImageView!
    @IBOutlet weak var currentTargetApplicationName: NSTextField!
    /// On: the app uses the global scroll settings ("Use global settings").
    @IBOutlet weak var inheritGlobalSettingSwitch: NSSwitch!
    
    override func viewDidLoad() {
        // The app's name and "inherit" sit in a box like the settings' boxes under them.
        if let header = view.subviews.compactMap({ $0 as? NSBox }).first {
            PreferencesGroupedForm.styleAsGroupBox(header)
        }
        // 初始化显示内容
        currentTargetApplicationIcon.image = currentTargetApplication?.getIcon()
        currentTargetApplicationIcon.toolTip = currentTargetApplication?.path
        currentTargetApplicationName.stringValue = currentTargetApplication?.getName() ?? ""
        // 读取设置
        syncViewWithOptions()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        fitToContent()
    }

    /// The popover is as tall as the app's header and the scroll settings under it. The
    /// settings call this once they are loaded (the embedded view loads after this one)
    /// and whenever "Advanced" opens or closes.
    ///
    /// `preferredContentSize` becomes a constraint on the view, so once it is set the
    /// view's own fitting size can no longer shrink. The header is therefore measured once,
    /// before that, and the settings are measured on their own each time.
    func fitToContent() {
        guard isViewLoaded, let content = currentContentViewController, content.isViewLoaded else { return }
        let contentSize = content.view.fittingSize
        let header: CGFloat
        if let measured = headerHeight {
            header = measured
        } else {
            // Until the settings are in this view, its fitting size is the header alone.
            let isEmbedded = content.view.isDescendant(of: view)
            header = max(0, view.fittingSize.height - (isEmbedded ? contentSize.height : 0))
            headerHeight = header
        }
        let size = NSSize(width: contentSize.width, height: contentSize.height + header)
        if preferredContentSize != size {
            preferredContentSize = size
        }
    }
    
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        currentContentViewController = (segue.destinationController as! PreferencesScrollingViewController)
        if let vaildContentViewController = currentContentViewController, let validTargetApplication = currentTargetApplication {
            vaildContentViewController.currentTargetApplication = validTargetApplication
        }
    }
    
    public func updateTargetApplication(with target: Application?) {
        currentTargetApplication = target
        if let vaildContentViewController = currentContentViewController, let validTargetApplication = currentTargetApplication {
            vaildContentViewController.currentTargetApplication = validTargetApplication
        }
    }
    public func updateParentData(with target: NSTableView, for row: Int) {
        parentTableView = target
        parentTableRow = row
    }
    
    // 名称
    @IBAction func currentTargetApplicationNameChange(_ sender: NSTextField) {
        let name = sender.stringValue
        if name.count > 0 {
            currentTargetApplication?.displayName = name
            if let validParentTableView = parentTableView, let validParentTableRow = parentTableRow {
                validParentTableView.reloadData(forRowIndexes: [validParentTableRow], columnIndexes: [0, 1, 2])
            }
        }
    }
    
    // 继承
    // Logi divert 用量同步由 LogiUsageBootstrap 的 Options 订阅自动完成 (inherit didSet → .application)
    @IBAction func inheritGlobalSettingClick(_ sender: NSSwitch) {
        if let vaildContentViewController = currentContentViewController, let validTargetApplication = currentTargetApplication {
            validTargetApplication.inherit = sender.state.rawValue==0 ? false : true
            vaildContentViewController.syncViewWithOptions()
        }
    }
}

/**
 * 工具函数
 **/
extension PreferencesScrollingWithApplicationViewController {
    // 同步界面与设置
    func syncViewWithOptions() {
        // 继承
        inheritGlobalSettingSwitch.state = (currentTargetApplication?.inherit ?? false) ? .on : .off
    }
}
