//
//  BrandTag.swift
//  Mos
//  统一的品牌标签渲染工具 - 支持多厂商品牌标识
//  Created by Mos on 2026/3/19.
//  Copyright © 2026 Caldis. All rights reserved.
//

import Cocoa

/// 可复用标签配置
struct BrandTagConfig: Equatable {
    let name: String           // 标签文字 (如 "Logi")
    let bgColor: NSColor       // 背景色
    let textColor: NSColor     // 文字色
    let borderColor: NSColor?  // 可选描边色, 用于提升浅色背景上的边界感
    let innerHighlightColor: NSColor? // 可选内高光, 比外描边更克制
    let gradientColors: [NSColor]? // 可选渐变色, nil 时使用纯色背景

    init(
        name: String,
        bgColor: NSColor,
        textColor: NSColor,
        borderColor: NSColor? = nil,
        innerHighlightColor: NSColor? = nil,
        gradientColors: [NSColor]? = nil
    ) {
        self.name = name
        self.bgColor = bgColor
        self.textColor = textColor
        self.borderColor = borderColor
        self.innerHighlightColor = innerHighlightColor
        self.gradientColors = gradientColors
    }

    // MARK: - 内置标签

    /// Logitech: 绿底黑字
    static let logi = BrandTagConfig(
        name: "Logi",
        bgColor: NSColor(calibratedRed: 0.0, green: 0.992, blue: 0.812, alpha: 1.0),  // #00FDCF
        textColor: NSColor(calibratedWhite: 0.15, alpha: 1.0)
    )

}

private final class BrandTagBackgroundView: NSView {
    private let brand: BrandTagConfig
    private let cornerRadius: CGFloat

    init(brand: BrandTagConfig, cornerRadius: CGFloat) {
        self.brand = brand
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let bgPath = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)
        BrandTag.drawTagBackground(brand: brand, in: bounds, clippingTo: bgPath)
        BrandTag.drawTagStrokeIfNeeded(brand: brand, path: bgPath)
        BrandTag.drawTagInnerHighlightIfNeeded(brand: brand, in: bounds, cornerRadius: cornerRadius)
    }
}

/// 标签渲染工具
struct BrandTag {

    // MARK: - 判断

    /// 按键码是否属于某个品牌
    static func isLogiCode(_ code: UInt16) -> Bool {
        return LogiCenter.shared.isLogiCode(code)
    }

    /// 获取按键码对应的标签配置 (nil = 非标签按键)
    static func tagForCode(_ code: UInt16) -> BrandTagConfig? {
        if isLogiCode(code) { return .logi }
        return nil
    }

    /// 获取按键码对应的品牌配置 (兼容旧调用, nil = 非品牌/标签按键)
    static func brandForCode(_ code: UInt16) -> BrandTagConfig? {
        return tagForCode(code)
    }

    // MARK: - 标签文字 (用于 NSButton.title 等纯文本场景)

    /// 在名称前添加品牌前缀 (纯文本 fallback)
    static func prefixedName(_ name: String, brand: BrandTagConfig) -> String {
        return "[\(brand.name)] \(name)"
    }

    // MARK: - 标签 NSView (用于 KeyPreview 等自定义 View 场景)

    /// 创建独立的品牌标签 View
    static func createTagView(brand: BrandTagConfig, fontSize: CGFloat = 7, height: CGFloat = 12) -> NSView {
        let container = BrandTagBackgroundView(brand: brand, cornerRadius: 2.5)
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: brand.name)
        label.font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        label.textColor = brand.textColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -0.5),
            container.widthAnchor.constraint(equalTo: label.widthAnchor, constant: 5),
            container.heightAnchor.constraint(equalToConstant: height),
        ])

        return container
    }

    // MARK: - 标签 NSImage (用于 NSMenuItem / NSButton / NSPopUpButton 场景)

    /// 创建品牌标签图片
    static func createTagImage(brand: BrandTagConfig, fontSize: CGFloat = 7, height: CGFloat = 12, padH: CGFloat = 4, marginRight: CGFloat = 2) -> NSImage {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: brand.textColor]
        let textSize = (brand.name as NSString).size(withAttributes: attrs)
        let tagWidth = textSize.width + padH * 2
        let imageSize = NSSize(width: tagWidth + marginRight, height: height)

        let image = NSImage(size: imageSize)
        image.lockFocus()
        let bgRect = NSRect(x: 0, y: 0, width: tagWidth, height: height)
        let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 3, yRadius: 3)
        drawTagBackground(brand: brand, in: bgRect, clippingTo: bgPath)
        drawTagStrokeIfNeeded(brand: brand, path: bgPath)
        drawTagInnerHighlightIfNeeded(brand: brand, in: bgRect, cornerRadius: 3)
        let textRect = NSRect(x: padH, y: (height - textSize.height) / 2, width: textSize.width, height: textSize.height)
        (brand.name as NSString).draw(in: textRect, withAttributes: attrs)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    fileprivate static func drawTagBackground(brand: BrandTagConfig, in rect: NSRect, clippingTo path: NSBezierPath) {
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        if let gradientColors = brand.gradientColors,
           let gradient = NSGradient(colors: gradientColors) {
            gradient.draw(in: rect, angle: 0)
        } else {
            brand.bgColor.setFill()
            rect.fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    fileprivate static func drawTagStrokeIfNeeded(brand: BrandTagConfig, path: NSBezierPath) {
        guard let borderColor = brand.borderColor else { return }
        borderColor.setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }

    fileprivate static func drawTagInnerHighlightIfNeeded(brand: BrandTagConfig, in rect: NSRect, cornerRadius: CGFloat) {
        guard let innerHighlightColor = brand.innerHighlightColor else { return }
        let highlightRect = rect.insetBy(dx: 0.75, dy: 0.75)
        let highlightRadius = max(0, cornerRadius - 0.75)
        let highlightPath = NSBezierPath(
            roundedRect: highlightRect,
            xRadius: highlightRadius,
            yRadius: highlightRadius
        )
        innerHighlightColor.setStroke()
        highlightPath.lineWidth = 1
        highlightPath.stroke()
    }
}
