//
//  ScrollEvent.swift
//  Mos
//  滚动事件基类
//  Created by Caldis on 2018/2/24.
//  Copyright © 2018年 Caldis. All rights reserved.
//

import Cocoa

enum axisType {
    case Y
    case X
}

struct axisData {
    // 基本参数
    var scrollFix = Int64(0)
    var scrollPt = 0.0
    var scrollFixPt = 0.0
    // 滚动数据是否为 Fix 类型 (非 Fix 类型在可用数据过小时需要归一化处理)
    var fixed = false
    // 滚动数据数据是否可用
    var valid = false
    // 可用的滚动数据
    var usableValue = 0.0
}

class ScrollEvent {
    
    // 滚动事件
    let event: CGEvent
    // 轴数据
    var Y: axisData
    var X: axisData
    
    // 初始化
    required init(with cgEvent: CGEvent) {
        // 保存事件引用
        event = cgEvent
        // 获取对应轴的数据
        Y = ScrollEvent.initEvent(event: cgEvent, axis: axisType.Y)
        X = ScrollEvent.initEvent(event: cgEvent, axis: axisType.X)
    }
    
    // 触控板/鼠标判断
    func isTrackpad() -> Bool {
        return ScrollEvent.isTrackpad(with: event)
    }
}

// MARK: - 工具方法
extension ScrollEvent {
    /// Whether a scroll event with these fields comes from a trackpad (or a Magic Mouse)
    /// rather than a mouse wheel. Pure.
    ///
    /// A trackpad's events always carry a phase: a touch (`scrollPhase`) or the glide after it
    /// (`momentumPhase`). The one kind without a phase is continuous. `scrollCount` counts quick
    /// successive swipes on the trackpad, and it stays set while the glide runs: the events of
    /// a mouse wheel turned during that time carry it as well (phase-less, not continuous).
    /// Taken for trackpad events, they went through unsmoothed and unreversed; so the count
    /// makes an event a trackpad's only when the event is continuous.
    static func isTrackpad(scrollPhase: Double, momentumPhase: Double, scrollCount: Double, isContinuous: Double) -> Bool {
        if scrollPhase != 0.0 || momentumPhase != 0.0 {
            return true
        }
        return scrollCount != 0.0 && isContinuous != 0.0
    }

    /// `isTrackpad(scrollPhase:momentumPhase:scrollCount:isContinuous:)` for an event, except
    /// that events sent by Logitech Options (its daemon) are wheel events.
    class func isTrackpad(with event: CGEvent) -> Bool {
        guard isTrackpad(
            scrollPhase: event.getDoubleValueField(.scrollWheelEventScrollPhase),
            momentumPhase: event.getDoubleValueField(.scrollWheelEventMomentumPhase),
            scrollCount: event.getDoubleValueField(.scrollWheelEventScrollCount),
            isContinuous: event.getDoubleValueField(.scrollWheelEventIsContinuous)
        ) else {
            return false
        }
        // 根据输入事件源增强判断
        if let specialProcessID = Utils.getRunningApplicationProcessIdentifier(withBundleIdentifier: SPECIAL_EVENT_SOURCE_APPLICATION.logitechOptions)?.processIdentifier,
           event.getIntegerValueField(.eventSourceUnixProcessID) == specialProcessID {
            return false
        }
        return true
    }
    
    // 初始化轴数据
    class func initEvent(event: CGEvent, axis: axisType) -> axisData {
        var data = axisData()
        // 获取对应轴的数据
        if axis == axisType.Y {
            data.scrollFix = Int64(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
            data.scrollPt = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
            data.scrollFixPt = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        } else {
            data.scrollFix = Int64(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
            data.scrollPt = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
            data.scrollFixPt = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        }
        // 生成可用的滚动数据
        if data.scrollPt != 0.0 {
            data.fixed = false
            data.valid = true
            data.usableValue = data.scrollPt
        } else if data.scrollFixPt != 0.0 {
            data.fixed = true
            data.valid = true
            data.usableValue = data.scrollFixPt
        } else if data.scrollFix != 0 {
            data.fixed = true
            data.valid = true
            data.usableValue = Double(data.scrollFix)
        }
        return data
    }
    
    // 翻转数据方向
    class func reverse(axis: axisType) -> (ScrollEvent) -> () {
        if axis == axisType.Y {
            return {
                (scrollEvent: ScrollEvent) in
                    scrollEvent.event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -scrollEvent.Y.scrollFix)
                    scrollEvent.event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: -scrollEvent.Y.scrollPt)
                    scrollEvent.event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -scrollEvent.Y.scrollFixPt)
                    scrollEvent.Y.usableValue = -scrollEvent.Y.usableValue
            }
        } else {
            return {
                (scrollEvent: ScrollEvent) in
                    scrollEvent.event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: -scrollEvent.X.scrollFix)
                    scrollEvent.event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: -scrollEvent.X.scrollPt)
                    scrollEvent.event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -scrollEvent.X.scrollFixPt)
                    scrollEvent.X.usableValue = -scrollEvent.X.usableValue
            }
        }
        
    }
    static let reverseX = reverse(axis: axisType.X)
    static let reverseY = reverse(axis: axisType.Y)
    
    // 归一化数据
    class func normalize(axis: axisType) -> (ScrollEvent, Double) -> () {
        if axis == axisType.Y {
            return {
                (scrollEvent: ScrollEvent, threshold: Double) in
                    let usableValue = scrollEvent.Y.usableValue
                    scrollEvent.Y.usableValue = usableValue>0.0 ? max(usableValue.magnitude, threshold) : -max(usableValue.magnitude, threshold)
            }
        } else {
            return {
                (scrollEvent: ScrollEvent, threshold: Double) in
                    let usableValue = scrollEvent.X.usableValue
                    scrollEvent.X.usableValue = usableValue>0.0 ? max(usableValue.magnitude, threshold) : -max(usableValue.magnitude, threshold)
            }
        }
    }
    static let normalizeX = normalize(axis: axisType.X)
    static let normalizeY = normalize(axis: axisType.Y)

    // 清除指定轴的数据 (用于返回原始事件时禁用某轴)
    class func clear(axis: axisType) -> (ScrollEvent) -> () {
        if axis == axisType.Y {
            return { scrollEvent in
                scrollEvent.event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 0)
                scrollEvent.event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: 0.0)
                scrollEvent.event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0.0)
                scrollEvent.Y.scrollFix = 0
                scrollEvent.Y.scrollPt = 0.0
                scrollEvent.Y.scrollFixPt = 0.0
                scrollEvent.Y.usableValue = 0.0
            }
        } else {
            return { scrollEvent in
                scrollEvent.event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: 0)
                scrollEvent.event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: 0.0)
                scrollEvent.event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: 0.0)
                scrollEvent.X.scrollFix = 0
                scrollEvent.X.scrollPt = 0.0
                scrollEvent.X.scrollFixPt = 0.0
                scrollEvent.X.usableValue = 0.0
            }
        }
    }
    static let clearX = clear(axis: axisType.X)
    static let clearY = clear(axis: axisType.Y)
}
