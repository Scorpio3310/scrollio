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

    /// The smoothed per-frame distance (what `fill` returns, before any catch-up release).
    private(set) var smoothed = (y: 0.0, x: 0.0)
    // 已输入但尚未输出的距离 (sum(in) - sum(out))
    private(set) var pending = (y: 0.0, x: 0.0)

    // 填充值
    // weight: 本帧权重, 按真实帧间隔换算; 1 = 不滤波
    // catchUp: 每帧补发 "多余" 距离的比例 (见下), 0 = 不补发
    //
    // With a constant weight the filter hands out everything it took in by itself: what it
    // still holds is (1 − w) / w × smoothed. When the weight changes on the way (the frame
    // interval varies, Duration changes), what has gone in but not out (`pending`) no longer
    // matches that. The difference is released at `catchUp` per frame, so no distance is
    // lost and the speed never jumps. A release against the direction of the motion only
    // slows it down, it never turns it around.
    public func fill(with nextValue: ( y: Double, x: Double ), weight: Double = ScrollFilter.defaultWeight, catchUp: Double = 0.0) -> ( y: Double, x: Double ) {
        let w = weight.isFinite ? min(1.0, max(0.0, weight)) : 1.0
        let k = catchUp.isFinite ? min(1.0, max(0.0, catchUp)) : 1.0
        return (
            y: Self.step(input: nextValue.y, smoothed: &smoothed.y, pending: &pending.y, weight: w, catchUp: k),
            x: Self.step(input: nextValue.x, smoothed: &smoothed.x, pending: &pending.x, weight: w, catchUp: k)
        )
    }
    private static func step(input: Double, smoothed: inout Double, pending: inout Double, weight w: Double, catchUp k: Double) -> Double {
        smoothed += w * (input - smoothed)
        var output = smoothed
        pending += input - output
        guard k > 0.0 else { return output }
        let held = w > 0.0 ? (1.0 - w) / w * smoothed : pending
        var release = (pending - held) * k
        if output > 0.0 {
            release = max(release, -output)
        } else if output < 0.0 {
            release = min(release, -output)
        }
        output += release
        pending -= release
        return output
    }
    // 获取值
    public func value() -> ( y: Double, x: Double ) {
        return smoothed
    }
    // 清空
    public func reset() {
        smoothed = (y: 0.0, x: 0.0)
        pending = (y: 0.0, x: 0.0)
    }

}
