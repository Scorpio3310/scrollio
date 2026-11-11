//
//  Filter.swift
//  Mos
//  曲线峰值滤波, 用于去除滚动的起始抖动
//  Created by Caldis on 2018/3/21.
//  Copyright © 2018年 Caldis. All rights reserved.
//

import Cocoa

/// Low-pass on the per-frame scroll distance.
///
/// Smooth scrolling is two lags in a row: the lerp toward the target (ScrollPoster) and this
/// filter. The lerp alone starts every notch at full speed and then only slows down; the filter
/// rounds that start off, so a notch is one smooth bump. It loses no distance: what it holds
/// back (`pending`) comes out in the following frames.
class ScrollFilter {

    // 首帧权重 (60Hz 参考帧率下)
    static let defaultWeight = ScrollMotion.filterWeight

    /// The smoothed per-frame distance: what the last `fill` or `passThrough` returned.
    private(set) var smoothed = (y: 0.0, x: 0.0)
    // 已输入但尚未输出的距离 (sum(in) - sum(out)), 跳过滤波时补发, 不丢失也不突跳
    private(set) var pending = (y: 0.0, x: 0.0)

    // 填充值
    // weight: 本帧权重, 按真实帧间隔换算 (ScrollMotion.transition), 60Hz 时等于 defaultWeight
    public func fill(with nextValue: ( y: Double, x: Double ), weight: Double = ScrollFilter.defaultWeight) -> ( y: Double, x: Double ) {
        let w = weight.isFinite ? min(1.0, max(0.0, weight)) : 1.0
        smoothed.y += w * (nextValue.y - smoothed.y)
        smoothed.x += w * (nextValue.x - smoothed.x)
        pending.y += nextValue.y - smoothed.y
        pending.x += nextValue.x - smoothed.x
        return smoothed
    }
    // 跳过滤波: 输出本帧输入, 并按 catchUp 比例补发滤波器中尚未输出的距离;
    // 平滑值停在本次输出值, 之后重新启用滤波时速度连续
    public func passThrough(with nextValue: ( y: Double, x: Double ), catchUp: Double) -> ( y: Double, x: Double ) {
        let k = catchUp.isFinite ? min(1.0, max(0.0, catchUp)) : 1.0
        let output = (y: nextValue.y + pending.y * k, x: nextValue.x + pending.x * k)
        pending = (y: pending.y * (1 - k), x: pending.x * (1 - k))
        smoothed = output
        return output
    }
    /// The caller sent `output` on this axis this frame and has taken over everything that was
    /// still pending there (see `ScrollLanding`). Filtering continues from `output`, so the
    /// speed stays continuous when the wheel moves again.
    public func settleY(at output: Double) {
        smoothed.y = output
        pending.y = 0.0
    }
    public func settleX(at output: Double) {
        smoothed.x = output
        pending.x = 0.0
    }
    // 获取值
    public func value() -> ( y: Double, x: Double ) {
        return smoothed
    }
    /// Clears one axis (see `reset()`).
    public func resetY() {
        smoothed.y = 0.0
        pending.y = 0.0
    }
    public func resetX() {
        smoothed.x = 0.0
        pending.x = 0.0
    }
    // 清空
    public func reset() {
        smoothed = (y: 0.0, x: 0.0)
        pending = (y: 0.0, x: 0.0)
    }

}
