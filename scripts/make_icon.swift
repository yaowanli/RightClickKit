// App 图标生成器:纯 CoreGraphics 矢量渲染,输出 .build/AppIcon.iconset 后由 iconutil 合成 Resources/AppIcon.icns
// 运行:swift scripts/make_icon.swift
import AppKit

let topColor = NSColor(calibratedRed: 0.40, green: 0.56, blue: 1.00, alpha: 1)
let bottomColor = NSColor(calibratedRed: 0.20, green: 0.32, blue: 0.80, alpha: 1)
let barAccent = NSColor(calibratedRed: 0.184, green: 0.42, blue: 0.949, alpha: 1)
let barGray = NSColor(calibratedRed: 0.847, green: 0.847, blue: 0.874, alpha: 1)
let arrowFill = NSColor(calibratedRed: 0.086, green: 0.086, blue: 0.102, alpha: 1)

func draw(_ size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let g = ctx.cgContext
    let s = size

    // macOS 模板口径:1024 画布内 824 圆角方(四边留白 100,圆角 185.4)
    let inset = 100 / 1024 * s
    let shape = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = 185.4 / 1024 * s
    g.addPath(CGPath(roundedRect: shape, cornerWidth: radius, cornerHeight: radius, transform: nil))
    g.clip()

    // 背景渐变:顶部亮 → 底部暗(CG 原点在左下, maxY 即视觉顶部)
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [topColor.cgColor, bottomColor.cgColor] as CFArray,
                          locations: [0, 1])!
    g.drawLinearGradient(grad, start: CGPoint(x: shape.midX, y: shape.maxY),
                         end: CGPoint(x: shape.midX, y: shape.minY), options: [])

    // 菜单面板(白卡 + 下投影)
    let panel = CGRect(x: 0.235 * s, y: s - 0.685 * s, width: 0.53 * s, height: 0.45 * s)
    g.saveGState()
    g.setShadow(offset: CGSize(width: 0, height: -0.025 * s), blur: 0.05 * s,
                color: NSColor.black.withAlphaComponent(0.30).cgColor)
    g.addPath(CGPath(roundedRect: panel, cornerWidth: 0.055 * s, cornerHeight: 0.055 * s, transform: nil))
    g.setFillColor(NSColor.white.cgColor)
    g.fillPath()
    g.restoreGState()

    // 三条菜单条:首条高亮(选中行隐喻),其余灰
    let barH = 0.052 * s
    let bars: [(yTd: CGFloat, w: CGFloat, color: NSColor)] = [
        (0.315, 0.38, barAccent), (0.425, 0.38, barGray), (0.535, 0.24, barGray),
    ]
    for (yTd, w, color) in bars {
        let r = CGRect(x: 0.31 * s, y: s - yTd * s - barH, width: w * s, height: barH)
        g.addPath(CGPath(roundedRect: r, cornerWidth: barH / 2, cornerHeight: barH / 2, transform: nil))
        g.setFillColor(color.cgColor)
        g.fillPath()
    }

    // 光标箭头(经典指针轮廓,白描边黑填充),叠在面板右下角制造「点击菜单」隐喻
    let k = 0.28 * s / 16.6
    let (tipX, tipY) = (0.585 * s, 0.52 * s)
    let pts: [(CGFloat, CGFloat)] = [
        (0, 0), (0, 14.2), (3.95, 10.9), (6.5, 16.6), (8.9, 15.6), (6.4, 10.0), (11.6, 10.0),
    ]
    let arrow = CGMutablePath()
    arrow.move(to: CGPoint(x: tipX + pts[0].0 * k, y: s - (tipY + pts[0].1 * k)))
    for (px, py) in pts.dropFirst() {
        arrow.addLine(to: CGPoint(x: tipX + px * k, y: s - (tipY + py * k)))
    }
    arrow.closeSubpath()
    g.saveGState()
    g.setShadow(offset: CGSize(width: 0.006 * s, height: -0.006 * s), blur: 0.02 * s,
                color: NSColor.black.withAlphaComponent(0.25).cgColor)
    g.addPath(arrow)
    g.setStrokeColor(NSColor.white.cgColor)
    g.setLineWidth(0.022 * s)
    g.setLineJoin(.round)
    g.strokePath()
    g.addPath(arrow)
    g.setFillColor(arrowFill.cgColor)
    g.fillPath()
    g.restoreGState()

    return rep
}

let root = URL(fileURLWithPath: (#file as NSString).deletingLastPathComponent).deletingLastPathComponent()
let iconset = root.appendingPathComponent(".build/AppIcon.iconset")
let fm = FileManager.default
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
let entries: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (name, px) in entries {
    let png = draw(CGFloat(px)).representation(using: .png, properties: [:])!
    try png.write(to: iconset.appendingPathComponent(name))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try p.run()
p.waitUntilExit()
guard p.terminationStatus == 0 else { fatalError("iconutil 退出码 \(p.terminationStatus)") }
print("已生成 Resources/AppIcon.icns")
