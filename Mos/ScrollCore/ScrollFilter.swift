//
//  Filter.swift
//  Mos
//  曲线峰值滤波, 用于去除滚动的起始抖动
//  Created by Caldis on 2018/3/21.
//  Copyright © 2018年 Caldis. All rights reserved.
//

import Cocoa

class ScrollFilter {
    
    // 首帧权重 (60Hz 参考帧率下)
    static let defaultWeight = ScrollMotion.filterWeight

    var curveWindowY = [0.0, 0.0]
    var curveWindowX = [0.0, 0.0]
    // 已输入但尚未输出的距离 (sum(in) - sum(out)), 跳过滤波时补发, 不丢失也不突跳
    private(set) var pending = (y: 0.0, x: 0.0)
    
    // 填充值
    // weight: 本帧权重, 按真实帧间隔换算 (ScrollMotion.transition), 60Hz 时等于 defaultWeight
    public func fill(with nextValue: ( y: Double, x: Double ), weight: Double = ScrollFilter.defaultWeight) -> ( y: Double, x: Double ) {
        curveWindowY = polish(curveWindowY, with: nextValue.y, weight: weight)
        curveWindowX = polish(curveWindowX, with: nextValue.x, weight: weight)
        let output = value()
        pending.y += nextValue.y - output.y
        pending.x += nextValue.x - output.x
        return output
    }
    // 跳过滤波: 输出本帧输入, 并按 catchUp 比例补发滤波器中尚未输出的距离;
    // 曲线窗口停在本次输出值, 之后重新启用滤波时速度连续
    public func passThrough(with nextValue: ( y: Double, x: Double ), catchUp: Double) -> ( y: Double, x: Double ) {
        let k = catchUp.isFinite ? min(1.0, max(0.0, catchUp)) : 1.0
        let output = (y: nextValue.y + pending.y * k, x: nextValue.x + pending.x * k)
        pending = (y: pending.y * (1 - k), x: pending.x * (1 - k))
        curveWindowY = [output.y, output.y]
        curveWindowX = [output.x, output.x]
        return output
    }
    // 获取值
    public func value() -> ( y: Double, x: Double ) {
        return ( y: curveWindowY[0], x: curveWindowX[0] )
    }
    // 清空
    public func reset() {
        curveWindowY = [0.0, 0.0]
        curveWindowX = [0.0, 0.0]
        pending = (y: 0.0, x: 0.0)
    }

}

extension ScrollFilter {
    // 曲线平滑
    // 计算曲线窗口数组首位与 nextValue 的距离, 用定长的非线性数列填充以平滑曲线
    // 例如: 数组首位为 1, nextValue 为 2, 则生成数列 [1.00, 1.23, 1.50, 1.77, 2.00]
    // 只有第二项 (权重 weight) 会成为下一帧的输出, 等效于一帧延迟的指数平均
    private func polish(_ array: [Double], with nextValue: Double, weight: Double) -> [Double] {
        let first = array[1]
        let diff = nextValue - first
        return [first, first+weight*diff, first+0.5*diff, first+(1-weight)*diff, nextValue]
    }
}
